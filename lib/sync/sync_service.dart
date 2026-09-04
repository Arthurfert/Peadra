import 'dart:async';

import '../../core/database/database_manager.dart';
import '../../core/services/log_service.dart';
import '../../core/services/wifi_monitor.dart';
import 'models/trusted_peer.dart';
import 'models/sync_session_status.dart';
import 'network/discovered_service.dart';
import 'network/mdns_discovery_service.dart';
import 'network/p2p_client.dart';
import 'network/p2p_server.dart';
import 'network/service_advertiser.dart';
import 'network/service_browser.dart';
import 'security/node_identity.dart';
import 'storage/crdt_database_service.dart';
import 'storage/secure_peer_storage.dart';
import 'sync_manager.dart';

/// App-level facade over the sync layer.
///
/// Owns the single [SyncManager] instance wired to the production components
/// (real mDNS advertiser/browser, real TCP server/client) plus the secure
/// peer storage and node identity. Started after login and stopped at logout.
class SyncService {
  SyncService._();

  static final SyncService instance = SyncService._();

  final SecurePeerStorage _peerStorage = SecurePeerStorage();
  final NodeIdentity _identity = NodeIdentity.instance;
  final WifiMonitor _wifiMonitor = WifiMonitor();

  SyncManager? _manager;
  StreamSubscription<bool>? _wifiSub;

  /// The live manager, or null before [start] / after [stop].
  SyncManager? get manager => _manager;

  bool get isRunning => _manager?.running ?? false;

  Future<String> get nodeId => _identity.nodeId;

  Future<String> get deviceName => _identity.deviceName;

  Future<List<TrustedPeer>> getPeers() => _peerStorage.getAll();

  Future<void> forgetPeer(String peerId) => _peerStorage.delete(peerId);

  /// Whether Wi-Fi is currently available.
  bool get isWifiAvailable => _wifiMonitor.isWifiAvailable;

  /// Emits devices seen on the local network (used while scanning a QR).
  Stream<DiscoveredService> get onPeerDiscovered =>
      _manager?.discovery.onServiceFound ?? const Stream.empty();

  /// Emits pairing progress (connecting, exchanging keys, syncing, ...) so the
  /// UI can show what is happening during a first pairing on both devices.
  Stream<SyncSessionStatus> get onSyncStatus =>
      _manager?.onSyncStatus ?? const Stream.empty();

  /// Builds (once) and returns the manager with the production components.
  Future<SyncManager> ensureStarted() async {
    if (_manager != null) return _manager!;
    final manager = SyncManager(
      db: CrdtDatabaseService(await DatabaseManager.instance.database),
      peerStorage: _peerStorage,
      identity: _identity,
      server: P2pServer(),
      client: P2pClient(),
      discovery: MDnsDiscoveryService(
        advertiser: MDnsSyncServiceAdvertiser(),
        browser: MDnsSyncServiceBrowser(),
      ),
    );
    _manager = manager;
    return manager;
  }

  /// Starts advertisement, browsing and the sync server. Safe to call
  /// multiple times; failures are logged rather than thrown.
  /// Also starts monitoring Wi-Fi connectivity to auto-start sync when
  /// Wi-Fi becomes available.
  Future<void> start() async {
    _wifiMonitor.start();
    _wifiSub?.cancel();
    _wifiSub = _wifiMonitor.onWifiChanged.listen((hasWifi) {
      if (hasWifi) {
        _ensureSyncRunning();
      } else {
        _stopSyncQuietly();
      }
    });
    final hasWifi = await _wifiMonitor.checkWifi();
    if (hasWifi) {
      await _ensureSyncRunning();
    }
  }

  Future<void> _ensureSyncRunning() async {
    if (isRunning) return;
    try {
      final manager = await ensureStarted();
      await manager.start();
    } catch (e) {
      LogService().warn('SyncService start failed: $e');
    }
  }

  void _stopSyncQuietly() {
    _manager?.stop();
  }

  /// Stops the sync server, advertisement, in-flight sessions, and
  /// the Wi-Fi monitor.
  Future<void> stop() async {
    _wifiSub?.cancel();
    _wifiSub = null;
    _wifiMonitor.stop();
    try {
      await _manager?.stop();
    } catch (e) {
      LogService().warn('SyncService stop failed: $e');
    } finally {
      _manager = null;
    }
  }

  /// Registers a fresh pairing secret so an unknown peer can authenticate.
  void registerPairingSecret(String nodeId, String sharedSecret) {
    _manager?.registerPairingSecret(nodeId, sharedSecret);
  }

  /// Runs the one-time pairing session against a freshly scanned device.
  Future<void> runPairingSession({
    required String peerId,
    required String deviceName,
    required String sharedSecret,
    required String host,
    required int port,
  }) async {
    final manager = await ensureStarted();
    await manager.runPairingSession(
      peerId: peerId,
      deviceName: deviceName,
      sharedSecret: sharedSecret,
      host: host,
      port: port,
    );
  }

  /// Manual sync trigger from the peers list.
  Future<void> syncNow(String peerId, {String? host, int? port}) async {
    final manager = _manager;
    if (manager == null) return;
    await manager.syncNow(peerId, host: host, port: port);
  }

  /// Re-shares the database encryption key with a paired device after a local
  /// password change re-derived the key.
  Future<void> updatePeerKey(String peerId, {String? host, int? port}) async {
    final manager = _manager;
    if (manager == null) return;
    await manager.updatePeerKey(peerId, host: host, port: port);
  }
}
