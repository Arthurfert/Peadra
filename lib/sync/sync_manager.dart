import 'dart:async';
import 'dart:convert';

import 'package:crdt/crdt.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';

import '../../core/database/database_manager.dart';
import '../../core/services/log_service.dart';
import 'models/trusted_peer.dart';
import 'models/sync_session_status.dart';
import 'network/discovered_service.dart';
import 'network/mdns_discovery_service.dart';
import 'network/p2p_client.dart';
import 'network/p2p_server.dart';
import 'network/sync_session.dart';
import 'security/node_identity.dart';
import 'storage/crdt_database_service.dart';
import 'storage/secure_peer_storage.dart';
import 'sync_runner.dart';

/// Orchestrates the offline P2P sync layer.
///
/// Started after login (when the DB encryption key is in memory) and stopped
/// at logout. It advertises the local device, browses for peers, and:
///  - auto-syncs with a trusted peer when it appears via mDNS,
///  - syncs with all reachable trusted peers a short while after a local
///    database change,
///  - runs the one-time pairing session (user reconciliation + encryption-key
///    sharing + initial full sync) for a freshly scanned device.
///
/// A single session per peer is guaranteed by a per-peer mutex and reconnect
/// attempts are throttled by [reconnectCooldown]. Failures are logged and
/// retried on the next mDNS event; they never crash the UI.
class SyncManager {
  SyncManager({
    required this.db,
    required this.peerStorage,
    required this.identity,
    required this.server,
    required this.client,
    required this.discovery,
    this.syncDebounce = const Duration(seconds: 2),
    this.reconnectCooldown = const Duration(seconds: 15),
    SecretKey? Function()? localDbKeyResolver,
    DateTime Function()? now,
  })  : _localDbKeyResolver =
            localDbKeyResolver ?? (() => DatabaseManager.instance.encryptionKey),
        _now = now ?? DateTime.now;

  final CrdtDatabaseService db;
  final SecurePeerStorage peerStorage;
  final NodeIdentity identity;
  final P2pServer server;
  final P2pClient client;
  final MDnsDiscoveryService discovery;
  final Duration syncDebounce;
  final Duration reconnectCooldown;
  final SecretKey? Function() _localDbKeyResolver;
  final DateTime Function() _now;

  bool _running = false;
  Timer? _syncTimer;
  final Map<String, Future<void>> _locks = {};
  final Map<String, DateTime> _lastAttempt = {};
  final Map<String, DiscoveredService> _knownPeers = {};
  final Map<String, String> _pendingPairingSecrets = {};
  final Set<Future<void>> _inFlight = {};
  StreamSubscription<DiscoveredService>? _discoverySub;
  StreamSubscription<({Hlc hlc, Iterable<String> tables})>? _changeSub;
  String? _nodeId;
  String? _deviceName;

  /// Broadcasts pairing/sync progress so the UI can show live status on both
  /// the scanner side and the device displaying the pairing QR code.
  final StreamController<SyncSessionStatus> _statusController =
      StreamController<SyncSessionStatus>.broadcast();

  bool get running => _running;

  /// The port the local sync server is listening on, or null before [start].
  int? get serverPort => server.port;

  /// Emits the current [SyncSessionStatus] for pairing sessions this device
  /// participates in (both as the scanner and as the QR-code device).
  Stream<SyncSessionStatus> get onSyncStatus => _statusController.stream;

  void _emitStatus(SyncSessionStatus status) {
    if (!_statusController.isClosed) {
      _statusController.add(status);
    }
  }

  /// Registers a fresh pairing secret (generated for a QR code) so an unknown
  /// peer presenting it can authenticate during the pairing handshake.
  void registerPairingSecret(String nodeId, String sharedSecret) {
    _pendingPairingSecrets[nodeId] = sharedSecret;
  }

  Future<void> start() async {
    if (_running) return;
    _running = true;
    await _ensureIdentity();
    final port = await server.start(
      nodeId: _nodeId!,
      deviceName: _deviceName!,
      secretResolver: _resolveSecret,
      onSession: _handleServerSession,
    );
    await discovery.advertise(
      nodeId: _nodeId!,
      deviceName: _deviceName!,
      protocolVersion: SyncSession.currentProtocolVersion,
      port: port,
    );
    await discovery.startBrowsing(localNodeId: _nodeId!);
    _discoverySub = discovery.onServiceFound.listen(_onDiscovered);
    _changeSub = db.onTablesChanged.listen(_onLocalChange);
    debugPrint('[peadra-sync] SyncManager started (node ${_nodeId!} on port $port)');
    LogService().log('SyncManager started on port $port');
  }

  Future<void> stop() async {
    if (!_running) return;
    _running = false;
    await _discoverySub?.cancel();
    _discoverySub = null;
    await _changeSub?.cancel();
    _changeSub = null;
    _syncTimer?.cancel();
    _syncTimer = null;
    await discovery.stop();
    await server.stop();
    if (_inFlight.isNotEmpty) {
      await Future.wait(_inFlight.toList()).timeout(
        const Duration(seconds: 5),
        onTimeout: () => <void>[],
      );
    }
    _knownPeers.clear();
    _pendingPairingSecrets.clear();
    LogService().log('SyncManager stopped');
  }

  Future<void> _ensureIdentity() async {
    _nodeId ??= await identity.nodeId;
    _deviceName ??= await identity.deviceName;
  }

  /// Manual sync trigger from the peers list. Falls back to the last address
  /// seen via discovery when [host]/[port] are not supplied.
  Future<void> syncNow(String peerId, {String? host, int? port}) async {
    final known = _knownPeers[peerId];
    await _syncPeer(
      peerId,
      host: host ?? known?.host,
      port: port ?? known?.port,
    );
  }

  /// Re-shares the local database encryption key with an already-paired peer
  /// (after a password change re-derived the key). Updates both sides' stored
  /// peer key and runs a regular sync in the same session.
  Future<void> updatePeerKey(String peerId, {String? host, int? port}) async {
    final known = _knownPeers[peerId];
    await _refreshPeerKey(
      peerId,
      host: host ?? known?.host,
      port: port ?? known?.port,
    );
  }

  Future<void> _refreshPeerKey(String peerId, {String? host, int? port}) async {
    final peer = await peerStorage.getById(peerId);
    if (peer == null) return;
    if (host == null || port == null) return;

    SyncSession? session;
    try {
      session = await client.connect(
        host: host,
        port: port,
        nodeId: _nodeId!,
        deviceName: _deviceName!,
        peerNodeId: peer.peerId,
        sharedSecret: peer.sharedSecret,
      );
      final remoteKey = await runKeyRefresh(
        session: session,
        localKey: await _localDbKeyBytes(),
        isInitiator: true,
      );
      final watermark = await runSyncExchange(
        session: session,
        db: db,
        since: peer.lastSyncHlc,
        isInitiator: true,
        peerKey: _peerKeyFrom(remoteKey),
      );
      await peerStorage.upsert(
        peer.copyWith(
          dbEncryptionKey: remoteKey,
          lastSyncHlc: watermark,
          lastSeen: _now(),
        ),
      );
      LogService().log('Key re-shared with ${peer.deviceName}');
    } catch (e) {
      LogService().warn('Key re-share with ${peer.deviceName} failed: $e');
    } finally {
      await session?.close();
    }
  }

  /// Pairing session for a freshly scanned device. Runs the one-time steps —
  /// encryption-key sharing, user reconciliation, and the initial full sync —
  /// then stores the peer as trusted.
  Future<void> runPairingSession({
    required String peerId,
    required String deviceName,
    required String sharedSecret,
    required String host,
    required int port,
  }) async {
    await _ensureIdentity();
    _emitStatus(SyncSessionStatus.connecting);
    debugPrint('[peadra-sync] pairing: connecting to $deviceName '
        '($peerId) at $host:$port');
    final session = await client.connect(
      host: host,
      port: port,
      nodeId: _nodeId!,
      deviceName: _deviceName!,
      peerNodeId: peerId,
      sharedSecret: sharedSecret,
    );
    try {
      final steps = await _runPairingSteps(session, isInitiator: true);
      final now = _now();
      await peerStorage.upsert(
        TrustedPeer(
          peerId: peerId,
          deviceName: deviceName,
          sharedSecret: sharedSecret,
          dbEncryptionKey: steps.remoteKey,
          lastSyncHlc: steps.watermark,
          createdAt: now,
          lastSeen: now,
        ),
      );
      debugPrint('[peadra-sync] pairing: complete with $deviceName ($peerId)');
      LogService().log('Paired with $deviceName ($peerId)');
    } catch (_) {
      _emitStatus(SyncSessionStatus.failed);
      rethrow;
    } finally {
      await session.close();
    }
  }

  Future<String?> _resolveSecret(String nodeId) async {
    final peer = await peerStorage.getById(nodeId);
    if (peer != null) {
      return peer.sharedSecret;
    }
    if (_pendingPairingSecrets.isNotEmpty) {
      return _pendingPairingSecrets.values.first;
    }
    return null;
  }

  Future<void> _onDiscovered(DiscoveredService service) async {
    if (!_running) return;
    _knownPeers[service.nodeId] = service;
    final peer = await peerStorage.getById(service.nodeId);
    if (peer == null) return;
    unawaited(_syncPeer(service.nodeId, host: service.host, port: service.port));
  }

  void _onLocalChange(({Hlc hlc, Iterable<String> tables}) change) {
    if (!_running) return;
    if (!db.isSyncSelfChange(hlc: change.hlc)) return;
    _syncTimer?.cancel();
    _syncTimer = Timer(syncDebounce, _syncAllKnown);
  }

  Future<void> _syncAllKnown() async {
    final services = Map.of(_knownPeers).values;
    for (final service in services) {
      await _syncPeer(service.nodeId, host: service.host, port: service.port);
    }
  }

  Future<void> _syncPeer(String peerId, {String? host, int? port}) async {
    if (!_running) return;
    final now = _now();
    final last = _lastAttempt[peerId];
    if (last != null && now.difference(last) < reconnectCooldown) return;
    _lastAttempt[peerId] = now;

    final previous = _locks[peerId] ?? Future<void>.value();
    final done = Completer<void>();
    _locks[peerId] = previous.then((_) => done.future);
    await previous;
    try {
      await _doSync(peerId, host: host, port: port);
    } finally {
      done.complete();
    }
  }

  Future<void> _doSync(String peerId, {String? host, int? port}) async {
    final peer = await peerStorage.getById(peerId);
    if (peer == null) return;
    if (host == null || port == null) return;

    SyncSession? session;
    try {
      session = await client.connect(
        host: host,
        port: port,
        nodeId: _nodeId!,
        deviceName: _deviceName!,
        peerNodeId: peer.peerId,
        sharedSecret: peer.sharedSecret,
      );
      final watermark = await runSyncExchange(
        session: session,
        db: db,
        since: peer.lastSyncHlc,
        isInitiator: true,
        peerKey: _peerKeyFrom(peer.dbEncryptionKey),
      );
      await peerStorage.upsert(
        peer.copyWith(lastSyncHlc: watermark, lastSeen: _now()),
      );
      LogService().log('Sync with ${peer.deviceName} complete');
    } catch (e) {
      LogService().warn('Sync with ${peer.deviceName} failed: $e');
    } finally {
      await session?.close();
    }
  }

  Future<void> _handleServerSession(SyncSession session) {
    final future = _runServerSession(session);
    _inFlight.add(future);
    future.whenComplete(() => _inFlight.remove(future));
    return future;
  }

  Future<void> _runServerSession(SyncSession session) async {
    final peerInfo = session.peer;
    if (peerInfo == null) return;

    final existing = await peerStorage.getById(peerInfo.nodeId);
    final isPairing = existing == null && _pendingPairingSecrets.isNotEmpty;
    if (isPairing) {
      _emitStatus(SyncSessionStatus.connecting);
    }
    try {
      if (isPairing) {
        final secret = _pendingPairingSecrets.values.first;
        final steps = await _runPairingSteps(session, isInitiator: false);
        final now = _now();
        await peerStorage.upsert(
          TrustedPeer(
            peerId: peerInfo.nodeId,
            deviceName: peerInfo.deviceName,
            sharedSecret: secret,
            dbEncryptionKey: steps.remoteKey,
            lastSyncHlc: steps.watermark,
            createdAt: now,
            lastSeen: now,
          ),
        );
        _pendingPairingSecrets.clear();
        LogService().log('Paired with ${peerInfo.deviceName} (${peerInfo.nodeId})');
      } else if (existing != null) {
        final result = await runServerSession(
          session: session,
          db: db,
          since: existing.lastSyncHlc,
          localKey: await _localDbKeyBytes(),
          onRemoteKey: (_) {},
          peerKey: _peerKeyFrom(existing.dbEncryptionKey),
        );
        await peerStorage.upsert(
          existing.copyWith(
            dbEncryptionKey: result.remoteKey ?? existing.dbEncryptionKey,
            lastSyncHlc: result.watermark,
            lastSeen: _now(),
          ),
        );
      }
    } catch (e) {
      if (isPairing) {
        _emitStatus(SyncSessionStatus.failed);
      }
      LogService().warn(
        'Sync session with ${peerInfo.deviceName} failed: $e',
      );
    }
  }

  Future<({Hlc? watermark, String? remoteKey})> _runPairingSteps(
    SyncSession session, {
    required bool isInitiator,
  }) async {
    String? remoteKey;
    debugPrint('[peadra-sync] pairing: step 1/3 encryption key exchange');
    _emitStatus(SyncSessionStatus.exchangingKeys);
    await runEncryptionKeyExchange(
      session: session,
      localKey: await _localDbKeyBytes(),
      onRemoteKey: (key) => remoteKey = key,
      isInitiator: isInitiator,
    );
    debugPrint('[peadra-sync] pairing: step 2/3 user reconciliation');
    _emitStatus(SyncSessionStatus.reconcilingUsers);
    await runUserReconciliation(
      session: session,
      db: db,
      isInitiator: isInitiator,
    );
    debugPrint('[peadra-sync] pairing: step 3/3 sync exchange');
    _emitStatus(SyncSessionStatus.syncing);
    final watermark = await runSyncExchange(
      session: session,
      db: db,
      since: null,
      isInitiator: isInitiator,
      peerKey: _peerKeyFrom(remoteKey),
    );
    debugPrint('[peadra-sync] pairing: steps complete, watermark=$watermark, '
        'remoteKey=${remoteKey == null ? 'null' : 'set'}');
    _emitStatus(SyncSessionStatus.completed);
    return (watermark: watermark, remoteKey: remoteKey);
  }

  Future<List<int>?> _localDbKeyBytes() async =>
      (await _localDbKeyResolver()?.extractBytes());

  /// Decodes a peer's base64 database key (as exchanged/stored on a
  /// [TrustedPeer]) into a [SecretKey] usable for re-keying inbound data.
  SecretKey? _peerKeyFrom(String? keyB64) {
    if (keyB64 == null || keyB64.isEmpty) {
      return null;
    }
    return SecretKey(base64Decode(keyB64));
  }
}
