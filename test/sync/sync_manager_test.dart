import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite_crdt/sqlite_crdt.dart';

import 'package:peadra/sync/models/trusted_peer.dart';
import 'package:peadra/sync/network/discovered_service.dart';
import 'package:peadra/sync/network/mdns_discovery_service.dart';
import 'package:peadra/sync/network/p2p_client.dart';
import 'package:peadra/sync/network/p2p_server.dart';
import 'package:peadra/sync/network/service_advertiser.dart';
import 'package:peadra/sync/network/service_browser.dart';
import 'package:peadra/sync/network/sync_session.dart';
import 'package:peadra/sync/security/auth_challenge.dart';
import 'package:peadra/sync/security/node_identity.dart';
import 'package:peadra/sync/storage/crdt_database_service.dart';
import 'package:peadra/sync/storage/secure_peer_storage.dart';
import 'package:peadra/sync/sync_manager.dart';

import '../helpers/in_memory_storage_backend.dart';
import 'test_crdt_schema.dart';

class _FakeAdvertiser implements SyncServiceAdvertiser {
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

class _FakeBrowser implements SyncServiceBrowser {
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

class _SpyClient extends P2pClient {
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

class _Device {
  _Device({
    required this.id,
    required this.name,
    required this.secret,
    this.localKey,
  });

  final String id;
  final String name;
  final String secret;
  final SecretKey? localKey;

  late final SqliteCrdt crdt;
  late final CrdtDatabaseService service;
  late final SecurePeerStorage peers;
  late final SyncManager manager;
  late final _SpyClient client;
  late final _FakeBrowser browser;

  Future<void> setUp() async {
    crdt = await createCrdtDatabase();
    service = CrdtDatabaseService(crdt);
    final store = InMemoryStorageBackend();
    await store.write('sync_local_node_id', id);
    final identity = NodeIdentity(storage: store, deviceName: name);
    peers = SecurePeerStorage(storage: store);
    client = _SpyClient();
    browser = _FakeBrowser();
    manager = SyncManager(
      db: service,
      peerStorage: peers,
      identity: identity,
      server: P2pServer(),
      client: client,
      discovery: MDnsDiscoveryService(
        advertiser: _FakeAdvertiser(),
        browser: browser,
      ),
      syncDebounce: const Duration(milliseconds: 50),
      reconnectCooldown: Duration.zero,
      localDbKeyResolver: () => localKey,
    );
  }

  Future<void> start() => manager.start();

  Future<void> stop() => manager.stop();

  Future<void> trust(_Device other) => peers.upsert(
        TrustedPeer(
          peerId: other.id,
          deviceName: other.name,
          sharedSecret: other.secret,
          createdAt: DateTime(2026, 1, 1),
        ),
      );
}

void main() {
  initializeSyncTestDb();

  late String secret;

  setUp(() {
    secret = AuthChallenge.generateSharedSecret();
  });

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

  Future<void> seedAUser(SqliteCrdt db, String id, String username) {
    return db.execute(
      'INSERT INTO users (id, username, password_hash) VALUES (?1, ?2, ?3)',
      [id, username, 'hash'],
    );
  }

  test('E2E delta exchange converges data in both directions', () async {
    final a = _Device(id: 'device-a', name: 'Device A', secret: secret);
    final b = _Device(id: 'device-b', name: 'Device B', secret: secret);
    addTearDown(() async {
      await a.stop();
      await b.stop();
      await a.crdt.close();
      await b.crdt.close();
    });
    await a.setUp();
    await b.setUp();

    await seedAUser(a.crdt, 'user-a', 'alice');
    await a.crdt.execute(
      'INSERT INTO accounts (id, user_id, name, currency) VALUES (?1, ?2, ?3, ?4)',
      ['acct-a', 'user-a', 'A account', 'EUR'],
    );
    await seedAUser(b.crdt, 'user-b', 'bob');
    await b.crdt.execute(
      'INSERT INTO descriptions (id, user_id, name) VALUES (?1, ?2, ?3)',
      ['desc-b', 'user-b', 'B description'],
    );

    await a.trust(b);
    await b.trust(a);

    await a.start();
    await b.start();
    final portA = a.manager.serverPort!;

    await b.manager.syncNow(a.id, host: 'localhost', port: portA);

    final bAccounts = await b.crdt.query('SELECT * FROM accounts WHERE is_deleted = 0');
    expect(bAccounts, hasLength(1));
    expect(bAccounts.single['name'], 'A account');

    await waitUntil(
      () async =>
          (await a.crdt.query('SELECT * FROM descriptions WHERE is_deleted = 0')).isNotEmpty,
    );
    final aDescs = await a.crdt.query('SELECT * FROM descriptions WHERE is_deleted = 0');
    expect(aDescs, hasLength(1));
    expect(aDescs.single['name'], 'B description');

    await waitUntil(() async => (await a.peers.getById(b.id))?.lastSyncHlc != null);
    final aPeer = await a.peers.getById(b.id);
    final bPeer = await b.peers.getById(a.id);
    expect(aPeer?.lastSyncHlc, isNotNull);
    expect(bPeer?.lastSyncHlc, isNotNull);

    expect(b.client.connectCount, 1);
    expect(a.client.connectCount, 0);
  });

  test('concurrent conflicting edits converge to the same value', () async {
    final a = _Device(id: 'device-a', name: 'Device A', secret: secret);
    final b = _Device(id: 'device-b', name: 'Device B', secret: secret);
    addTearDown(() async {
      await a.stop();
      await b.stop();
      await a.crdt.close();
      await b.crdt.close();
    });
    await a.setUp();
    await b.setUp();

    await seedAUser(a.crdt, 'user-x', 'alice');
    await seedAUser(b.crdt, 'user-x', 'alice');
    await a.crdt.execute(
      'INSERT INTO accounts (id, user_id, name, starting_amount) VALUES (?1, ?2, ?3, ?4)',
      ['acct-x', 'user-x', 'Shared', 0.0],
    );
    await b.crdt.execute(
      'INSERT INTO accounts (id, user_id, name, starting_amount) VALUES (?1, ?2, ?3, ?4)',
      ['acct-x', 'user-x', 'Shared', 0.0],
    );

    await a.trust(b);
    await b.trust(a);
    await a.start();
    await b.start();

    await a.crdt.execute(
      'UPDATE accounts SET starting_amount = ? WHERE id = ?',
      [5.0, 'acct-x'],
    );
    await b.crdt.execute(
      'UPDATE accounts SET starting_amount = ? WHERE id = ?',
      [99.0, 'acct-x'],
    );

    await b.manager.syncNow(a.id, host: 'localhost', port: a.manager.serverPort!);

    final bRows = await b.crdt.query('SELECT starting_amount FROM accounts WHERE id = ?', ['acct-x']);
    expect(bRows.single['starting_amount'], 99.0);

    await waitUntil(
      () async =>
          (await a.crdt.query(
                    'SELECT starting_amount FROM accounts WHERE id = ?',
                    ['acct-x'],
                  ))
              .single['starting_amount'] ==
          99.0,
    );
    final aRows = await a.crdt.query('SELECT starting_amount FROM accounts WHERE id = ?', ['acct-x']);
    expect(aRows.single['starting_amount'], 99.0);
  });

  test('unreachable peer is handled without crashing; retry succeeds', () async {
    final a = _Device(id: 'device-a', name: 'Device A', secret: secret);
    final b = _Device(id: 'device-b', name: 'Device B', secret: secret);
    addTearDown(() async {
      await a.stop();
      await b.stop();
      await a.crdt.close();
      await b.crdt.close();
    });
    await a.setUp();
    await b.setUp();

    await seedAUser(a.crdt, 'user-a', 'alice');
    await a.crdt.execute(
      'INSERT INTO accounts (id, user_id, name) VALUES (?1, ?2, ?3)',
      ['acct-a', 'user-a', 'A account'],
    );
    await a.trust(b);
    await b.trust(a);
    await a.start();
    await b.start();

    final tmp = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final deadPort = tmp.port;
    await tmp.close();

    await expectLater(
      b.manager.syncNow(a.id, host: 'localhost', port: deadPort),
      completes,
    );
    expect(b.client.connectCount, 1);

    await b.manager.syncNow(a.id, host: 'localhost', port: a.manager.serverPort!);
    final bAccounts = await b.crdt.query('SELECT * FROM accounts WHERE is_deleted = 0');
    expect(bAccounts, hasLength(1));
    expect(b.client.connectCount, 2);
  });

  test('pairing exchanges keys, reconciles users and syncs', () async {
    final a = _Device(
      id: 'device-a',
      name: 'Device A',
      secret: secret,
      localKey: SecretKey([1, 2, 3]),
    );
    final b = _Device(
      id: 'device-b',
      name: 'Device B',
      secret: secret,
      localKey: SecretKey([4, 5, 6]),
    );
    addTearDown(() async {
      await a.stop();
      await b.stop();
      await a.crdt.close();
      await b.crdt.close();
    });
    await a.setUp();
    await b.setUp();

    await seedAUser(a.crdt, 'user-a', 'alice');
    await seedAUser(b.crdt, 'user-b', 'alice');
    await b.crdt.execute(
      'INSERT INTO accounts (id, user_id, name) VALUES (?1, ?2, ?3)',
      ['acct-b', 'user-b', 'B account'],
    );

    await a.start();
    a.manager.registerPairingSecret(b.id, secret);

    await b.manager.runPairingSession(
      peerId: a.id,
      deviceName: a.name,
      sharedSecret: secret,
      host: 'localhost',
      port: a.manager.serverPort!,
    );

    await waitUntil(() async => (await a.peers.getById(b.id)) != null);
    final peerOnA = await a.peers.getById(b.id);
    final peerOnB = await b.peers.getById(a.id);
    expect(peerOnA, isNotNull);
    expect(peerOnB, isNotNull);
    expect(peerOnA?.dbEncryptionKey, base64Encode(const [4, 5, 6]));
    expect(peerOnB?.dbEncryptionKey, base64Encode(const [1, 2, 3]));

    final bUsers = await b.crdt.query('SELECT id, username FROM users WHERE is_deleted = 0');
    expect(bUsers, hasLength(1));
    expect(bUsers.single['id'], 'user-a');

    final bAccounts = await b.crdt.query('SELECT user_id FROM accounts WHERE is_deleted = 0');
    expect(bAccounts.single['user_id'], 'user-a');

    await waitUntil(
      () async =>
          (await a.crdt.query('SELECT * FROM accounts WHERE is_deleted = 0')).isNotEmpty,
    );
    final aAccounts = await a.crdt.query('SELECT * FROM accounts WHERE is_deleted = 0');
    expect(aAccounts, hasLength(1));
    expect(aAccounts.single['name'], 'B account');
  });

  test('discovery of a trusted peer triggers an automatic sync', () async {
    final a = _Device(id: 'device-a', name: 'Device A', secret: secret);
    final b = _Device(id: 'device-b', name: 'Device B', secret: secret);
    addTearDown(() async {
      await a.stop();
      await b.stop();
      await a.crdt.close();
      await b.crdt.close();
    });
    await a.setUp();
    await b.setUp();

    await seedAUser(a.crdt, 'user-a', 'alice');
    await a.crdt.execute(
      'INSERT INTO accounts (id, user_id, name) VALUES (?1, ?2, ?3)',
      ['acct-a', 'user-a', 'A account'],
    );
    await a.trust(b);
    await b.trust(a);
    await a.start();
    await b.start();

    b.browser.emit(DiscoveredService(
      nodeId: a.id,
      deviceName: a.name,
      protocolVersion: SyncSession.currentProtocolVersion,
      host: 'localhost',
      port: a.manager.serverPort!,
    ));

    await waitUntil(
      () async =>
          (await b.crdt.query('SELECT * FROM accounts WHERE is_deleted = 0')).isNotEmpty,
    );
    final bAccounts = await b.crdt.query('SELECT * FROM accounts WHERE is_deleted = 0');
    expect(bAccounts, hasLength(1));
    expect(b.client.connectCount, 1);
  });
}
