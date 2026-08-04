import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:peadra/sync/security/auth_challenge.dart';

import 'sync_test_helpers.dart';
import 'test_crdt_schema.dart';

/// M7 — end-to-end validation of the offline pairing & sync flows using the
/// real transport (loopback TCP) and real in-memory CRDT databases, mirroring
/// the mobile <-> desktop scenarios from the implementation plan.
void main() {
  initializeSyncTestDb();

  late String secret;

  setUp(() {
    secret = AuthChallenge.generateSharedSecret();
  });

  Future<void> pair(SyncTestDevice a, SyncTestDevice b) async {
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
    await waitUntil(() async => (await b.peers.getById(a.id)) != null);
  }

  test('pair -> edit offline on both -> reconnect -> converge', () async {
    final a = SyncTestDevice(id: 'device-a', name: 'Device A', secret: secret);
    final b = SyncTestDevice(id: 'device-b', name: 'Device B', secret: secret);
    addTearDown(a.dispose);
    addTearDown(b.dispose);
    await a.setUp();
    await b.setUp();

    await a.seedUser('user-a', 'alice');
    await a.crdt.execute(
      'INSERT INTO accounts (id, user_id, name) VALUES (?1, ?2, ?3)',
      ['acct-a1', 'user-a', 'A account 1'],
    );
    await b.seedUser('user-b', 'alice');
    await b.crdt.execute(
      'INSERT INTO accounts (id, user_id, name) VALUES (?1, ?2, ?3)',
      ['acct-b1', 'user-b', 'B account 1'],
    );

    await pair(a, b);
    await b.start();

    // After pairing both sides converge on the same user and data set.
    final postPairUsers = await a.crdt.query('SELECT id FROM users WHERE is_deleted = 0');
    expect(postPairUsers, hasLength(1));
    expect(postPairUsers.single['id'], 'user-a');
    final postPairA = await a.crdt.query('SELECT id FROM accounts WHERE is_deleted = 0');
    final postPairB = await b.crdt.query('SELECT id FROM accounts WHERE is_deleted = 0');
    expect(postPairA.map((r) => r['id']).toSet(), {'acct-a1', 'acct-b1'});
    expect(postPairB.map((r) => r['id']).toSet(), {'acct-a1', 'acct-b1'});

    // "Offline" edits on both devices without syncing.
    await a.crdt.execute(
      'INSERT INTO accounts (id, user_id, name) VALUES (?1, ?2, ?3)',
      ['acct-a2', 'user-a', 'A account 2'],
    );
    await b.crdt.execute(
      'INSERT INTO accounts (id, user_id, name) VALUES (?1, ?2, ?3)',
      ['acct-b2', 'user-a', 'B account 2'],
    );

    // Reconnect: one sync exchange and both devices have everything.
    await b.manager.syncNow(a.id, host: 'localhost', port: a.manager.serverPort!);

    final expected = {'acct-a1', 'acct-b1', 'acct-a2', 'acct-b2'};
    await waitUntil(
      () async =>
          (await a.crdt.query('SELECT id FROM accounts WHERE is_deleted = 0'))
              .map((r) => r['id'])
              .toSet()
              .containsAll(expected),
    );
    final rowsA = await a.crdt.query('SELECT id FROM accounts WHERE is_deleted = 0');
    final rowsB = await b.crdt.query('SELECT id FROM accounts WHERE is_deleted = 0');
    expect(rowsA.map((r) => r['id']).toSet(), expected);
    expect(rowsB.map((r) => r['id']).toSet(), expected);
  });

  test('password change re-shares the encryption key to paired devices',
      () async {
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

    await a.seedUser('user-a', 'alice');
    await b.seedUser('user-b', 'bob');

    await pair(a, b);
    await b.start();

    expect((await b.peers.getById(a.id))?.dbEncryptionKey,
        base64Encode(const [1, 2, 3]));
    expect((await a.peers.getById(b.id))?.dbEncryptionKey,
        base64Encode(const [4, 5, 6]));

    // Device A changes its password: the derived DB key changes.
    a.key = SecretKey([9, 9, 9]);

    await a.manager.updatePeerKey(b.id,
        host: 'localhost', port: b.manager.serverPort!);

    // B learned A's new key; A kept B's unchanged key.
    await waitUntil(
      () async => (await b.peers.getById(a.id))?.dbEncryptionKey ==
          base64Encode(const [9, 9, 9]),
    );
    expect((await b.peers.getById(a.id))?.dbEncryptionKey,
        base64Encode(const [9, 9, 9]));
    expect((await a.peers.getById(b.id))?.dbEncryptionKey,
        base64Encode(const [4, 5, 6]));

    // A subsequent sync still works after the re-share.
    await a.crdt.execute(
      'INSERT INTO accounts (id, user_id, name) VALUES (?1, ?2, ?3)',
      ['acct-a', 'user-a', 'A account'],
    );
    await b.manager.syncNow(a.id, host: 'localhost', port: a.manager.serverPort!);
    await waitUntil(
      () async =>
          (await b.crdt.query('SELECT id FROM accounts WHERE is_deleted = 0'))
              .isNotEmpty,
    );
    final bAccounts =
        await b.crdt.query('SELECT id FROM accounts WHERE is_deleted = 0');
    expect(bAccounts.map((r) => r['id']).toSet(), {'acct-a'});
  });

  test('sudden disconnect is handled; device rejoins and converges', () async {
    final a = SyncTestDevice(id: 'device-a', name: 'Device A', secret: secret);
    final b = SyncTestDevice(id: 'device-b', name: 'Device B', secret: secret);
    addTearDown(a.dispose);
    addTearDown(b.dispose);
    await a.setUp();
    await b.setUp();

    await a.seedUser('user-a', 'alice');
    await a.trust(b);
    await b.trust(a);
    await a.start();
    await b.start();

    await b.manager.syncNow(a.id, host: 'localhost', port: a.manager.serverPort!);
    final portA = a.manager.serverPort!;

    // Device A "goes offline": server stops, sessions are cancelled.
    await a.stop();

    // B keeps working and edits offline; a sync attempt is a clean no-op.
    await b.crdt.execute(
      'INSERT INTO accounts (id, user_id, name) VALUES (?1, ?2, ?3)',
      ['acct-b', 'user-a', 'B offline account'],
    );
    final connectionsBefore = b.client.connectCount;
    await expectLater(
      b.manager.syncNow(a.id, host: 'localhost', port: portA),
      completes,
    );
    expect(b.client.connectCount, connectionsBefore + 1);
    expect(
      (await b.crdt.query('SELECT id FROM accounts WHERE is_deleted = 0')).length,
      1,
    );

    // Device A rejoins on a fresh port; one sync and B's offline edit lands.
    await a.start();
    await b.manager.syncNow(a.id,
        host: 'localhost', port: a.manager.serverPort!);

    await waitUntil(
      () async =>
          (await a.crdt.query('SELECT id FROM accounts WHERE is_deleted = 0')).isNotEmpty,
    );
    final rowsA = await a.crdt.query('SELECT id FROM accounts WHERE is_deleted = 0');
    expect(rowsA.map((r) => r['id']).toSet(), {'acct-b'});
  });
}
