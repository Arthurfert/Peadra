import 'dart:async';
import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite_crdt/sqlite_crdt.dart';

import 'package:peadra/sync/network/discovered_service.dart';
import 'package:peadra/sync/network/mdns_discovery_service.dart';
import 'package:peadra/sync/network/p2p_client.dart';
import 'package:peadra/sync/network/p2p_server.dart';
import 'package:peadra/sync/network/service_advertiser.dart';
import 'package:peadra/sync/network/service_browser.dart';
import 'package:peadra/sync/network/sync_session.dart';
import 'package:peadra/sync/security/node_identity.dart';
import 'package:peadra/sync/storage/crdt_database_service.dart';
import 'package:peadra/sync/storage/secure_peer_storage.dart';
import 'package:peadra/sync/models/trusted_peer.dart';
import 'package:peadra/sync/sync_manager.dart';

import '../helpers/in_memory_storage_backend.dart';
import 'test_crdt_schema.dart';

class FakeSyncAdvertiser implements SyncServiceAdvertiser {
  int advertiseCount = 0;
  int stopCount = 0;

  @override
  Future<void> advertise({
    required String nodeId,
    required String deviceName,
    required int protocolVersion,
    required int port,
  }) async {
    advertiseCount++;
  }

  @override
  Future<void> stop() async {
    stopCount++;
  }
}

class FakeSyncBrowser implements SyncServiceBrowser {
  final StreamController<DiscoveredService> _controller =
      StreamController<DiscoveredService>.broadcast();
  int startCount = 0;
  int stopCount = 0;

  @override
  Stream<DiscoveredService> get services => _controller.stream;

  @override
  Future<void> start() async {
    startCount++;
  }

  @override
  Future<void> stop() async {
    stopCount++;
  }

  void emit(DiscoveredService service) => _controller.add(service);
}

class SpySyncClient extends P2pClient {
  int connectCount = 0;

  @override
  Future<SyncSession> connect({
    required String host,
    required int port,
    required String nodeId,
    required String deviceName,
    required String peerNodeId,
    required String sharedSecret,
    Duration timeout = const Duration(seconds: 15),
  }) async {
    connectCount++;
    return super.connect(
      host: host,
      port: port,
      nodeId: nodeId,
      deviceName: deviceName,
      peerNodeId: peerNodeId,
      sharedSecret: sharedSecret,
      timeout: timeout,
    );
  }
}

/// A self-contained device under test: a fresh in-memory CRDT database, a
/// secure peer store and a [SyncManager] wired to fake discovery components.
class SyncTestDevice {
  SyncTestDevice({
    required this.id,
    required this.name,
    required this.secret,
    this.key,
  });

  final String id;
  final String name;
  final String secret;

  /// The device's database encryption key. Mutable so tests can simulate a
  /// password change (the manager resolves it lazily via the constructor).
  SecretKey? key;

  late final SqliteCrdt crdt;
  late final CrdtDatabaseService service;
  late final SecurePeerStorage peers;
  late final SyncManager manager;
  late final SpySyncClient client;
  late final FakeSyncBrowser browser;

  Future<void> setUp() async {
    crdt = await createCrdtDatabase();
    service = CrdtDatabaseService(crdt);
    final store = InMemoryStorageBackend();
    await store.write('sync_local_node_id', id);
    final identity = NodeIdentity(storage: store, deviceName: name);
    peers = SecurePeerStorage(storage: store);
    client = SpySyncClient();
    browser = FakeSyncBrowser();
    manager = SyncManager(
      db: service,
      peerStorage: peers,
      identity: identity,
      server: P2pServer(),
      client: client,
      discovery: MDnsDiscoveryService(
        advertiser: FakeSyncAdvertiser(),
        browser: browser,
      ),
      syncDebounce: const Duration(milliseconds: 50),
      reconnectCooldown: Duration.zero,
      localDbKeyResolver: () => key,
    );
  }

  Future<void> start() => manager.start();

  Future<void> stop() => manager.stop();

  Future<void> trust(SyncTestDevice other) => peers.upsert(
        TrustedPeer(
          peerId: other.id,
          deviceName: other.name,
          sharedSecret: other.secret,
          createdAt: DateTime(2026, 1, 1),
        ),
      );

  Future<void> seedUser(String id, String username) => crdt.execute(
        'INSERT INTO users (id, username, password_hash) VALUES (?1, ?2, ?3)',
        [id, username, 'hash'],
      );

  Future<List<Map<String, Object?>>> query(
    String sql, [
    List<Object?> args = const [],
  ]) =>
      crdt.query(sql, args);

  Future<String> keyB64() async =>
      base64Encode(await key?.extractBytes() ?? const []);

  Future<void> dispose() async {
    await stop();
    await crdt.close();
  }
}

Future<void> waitUntil(
  Future<bool> Function() condition, {
  Duration timeout = const Duration(seconds: 5),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!(await condition())) {
    if (DateTime.now().isAfter(deadline)) {
      fail('condition not met within $timeout');
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}
