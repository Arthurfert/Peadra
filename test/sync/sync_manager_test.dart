import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:peadra/core/database/database_manager.dart';
import 'package:peadra/sync/models/sync_session_status.dart';
import 'package:peadra/sync/network/discovered_service.dart';
import 'package:peadra/sync/network/sync_session.dart';
import 'package:peadra/sync/security/auth_challenge.dart';

import 'sync_test_helpers.dart';
import 'test_crdt_schema.dart';

void main() {
  initializeSyncTestDb();

  late String secret;

  setUp(() {
    secret = AuthChallenge.generateSharedSecret();
  });

  Future<void> seedAUser(SyncTestDevice device, String id, String username) =>
      device.seedUser(id, username);

  test('E2E delta exchange converges data in both directions', () async {
    final a = SyncTestDevice(id: 'device-a', name: 'Device A', secret: secret);
    final b = SyncTestDevice(id: 'device-b', name: 'Device B', secret: secret);
    addTearDown(a.dispose);
    addTearDown(b.dispose);
    await a.setUp();
    await b.setUp();

    await seedAUser(a, 'user-a', 'alice');
    await a.crdt.execute(
      'INSERT INTO accounts (id, user_id, name, currency) VALUES (?1, ?2, ?3, ?4)',
      ['acct-a', 'user-a', 'A account', 'EUR'],
    );
    await seedAUser(b, 'user-b', 'bob');
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
    final a = SyncTestDevice(id: 'device-a', name: 'Device A', secret: secret);
    final b = SyncTestDevice(id: 'device-b', name: 'Device B', secret: secret);
    addTearDown(a.dispose);
    addTearDown(b.dispose);
    await a.setUp();
    await b.setUp();

    await seedAUser(a, 'user-x', 'alice');
    await seedAUser(b, 'user-x', 'alice');
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
    final a = SyncTestDevice(id: 'device-a', name: 'Device A', secret: secret);
    final b = SyncTestDevice(id: 'device-b', name: 'Device B', secret: secret);
    addTearDown(a.dispose);
    addTearDown(b.dispose);
    await a.setUp();
    await b.setUp();

    await seedAUser(a, 'user-a', 'alice');
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
    final a = SyncTestDevice(
      id: 'device-a',
      name: 'Device A',
      secret: secret,
      key: SecretKey([1, 2, 3]),
    );
    final b = SyncTestDevice(
      id: 'device-b',
      name: 'Device B',
      secret: secret,
      key: SecretKey([4, 5, 6]),
    );
    addTearDown(a.dispose);
    addTearDown(b.dispose);
    await a.setUp();
    await b.setUp();

    await seedAUser(a, 'user-a', 'alice');
    await seedAUser(b, 'user-b', 'alice');
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
    final a = SyncTestDevice(id: 'device-a', name: 'Device A', secret: secret);
    final b = SyncTestDevice(id: 'device-b', name: 'Device B', secret: secret);
    addTearDown(a.dispose);
    addTearDown(b.dispose);
    await a.setUp();
    await b.setUp();

    await seedAUser(a, 'user-a', 'alice');
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

  test('pairing emits live status progress on both devices', () async {
    final a = SyncTestDevice(id: 'device-a', name: 'Device A', secret: secret);
    final b = SyncTestDevice(id: 'device-b', name: 'Device B', secret: secret);
    addTearDown(a.dispose);
    addTearDown(b.dispose);
    await a.setUp();
    await b.setUp();

    await seedAUser(a, 'user-a', 'alice');
    await seedAUser(b, 'user-b', 'alice');

    final statusOnA = <SyncSessionStatus>[];
    final statusOnB = <SyncSessionStatus>[];
    final subA = a.manager.onSyncStatus.listen(statusOnA.add);
    final subB = b.manager.onSyncStatus.listen(statusOnB.add);
    addTearDown(subA.cancel);
    addTearDown(subB.cancel);

    await a.start();
    a.manager.registerPairingSecret(b.id, secret);

    await b.manager.runPairingSession(
      peerId: a.id,
      deviceName: a.name,
      sharedSecret: secret,
      host: 'localhost',
      port: a.manager.serverPort!,
    );

    await waitUntil(() async {
      return statusOnA.contains(SyncSessionStatus.completed) &&
          statusOnB.contains(SyncSessionStatus.completed);
    });

    // The scanner drives through the pairing steps; the QR device reports
    // connecting + syncing and ends in completed.
    expect(statusOnB, contains(SyncSessionStatus.connecting));
    expect(statusOnB, contains(SyncSessionStatus.syncing));
    expect(statusOnA, contains(SyncSessionStatus.syncing));
    expect(statusOnA, contains(SyncSessionStatus.completed));
    expect(statusOnB, contains(SyncSessionStatus.completed));
  });

  test('pairing reconciliation re-points the session user id on the scanner',
      () async {
    final a = SyncTestDevice(id: 'device-a', name: 'Device A', secret: secret);
    final b = SyncTestDevice(id: 'device-b', name: 'Device B', secret: secret);
    addTearDown(a.dispose);
    addTearDown(b.dispose);
    await a.setUp();
    await b.setUp();

    await seedAUser(a, 'user-a', 'alice');
    await seedAUser(b, 'user-b', 'alice');

    DatabaseManager.instance.setSessionUserId('user-b');
    addTearDown(() => DatabaseManager.instance.setSessionUserId(null));

    await a.start();
    a.manager.registerPairingSecret(b.id, secret);

    await b.manager.runPairingSession(
      peerId: a.id,
      deviceName: a.name,
      sharedSecret: secret,
      host: 'localhost',
      port: a.manager.serverPort!,
    );

    // The scanner (B) adopted the QR device's canonical user id, so the app
    // session filters against the id that now owns the merged data.
    expect(DatabaseManager.instance.userId, 'user-a');

    final aUsers = await a.query('SELECT id FROM users WHERE is_deleted = 0');
    expect(aUsers.single['id'], 'user-a');
  });
}
