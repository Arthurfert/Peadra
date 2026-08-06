import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:peadra/core/database/database_manager.dart';
import 'package:peadra/core/services/encryption_service.dart';
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

  test('peer-encrypted data is re-keyed and readable on the receiving device',
      () async {
    final keyA = SecretKey(List<int>.filled(32, 7));
    final keyB = SecretKey(List<int>.filled(32, 8));
    final a = SyncTestDevice(
      id: 'device-a',
      name: 'Device A',
      secret: secret,
      key: keyA,
    );
    final b = SyncTestDevice(
      id: 'device-b',
      name: 'Device B',
      secret: secret,
      key: keyB,
    );
    addTearDown(a.dispose);
    addTearDown(b.dispose);
    await a.setUp();
    await b.setUp();

    // Each device stores its own data field-encrypted with its own key.
    await a.seedUser('user-a', 'alice');
    await a.crdt.execute(
      'INSERT INTO accounts (id, user_id, name, starting_amount) VALUES (?1, ?2, ?3, ?4)',
      [
        'acct-a',
        'user-a',
        await EncryptionService.encrypt('Groceries', keyA),
        await EncryptionService.encrypt('100.0', keyA),
      ],
    );
    await b.seedUser('user-b', 'alice');
    await b.crdt.execute(
      'INSERT INTO accounts (id, user_id, name, starting_amount) VALUES (?1, ?2, ?3, ?4)',
      [
        'acct-b',
        'user-b',
        await EncryptionService.encrypt('Rent', keyB),
        await EncryptionService.encrypt('900.0', keyB),
      ],
    );

    await pair(a, b);
    await b.start();

    // Every row from the peer must be decryptable (stored plaintext here,
    // since the re-keyed target key is only used when the app has one loaded).
    final aRows = await waitForAccounts(a);
    final bRows = await waitForAccounts(b);
    expect(aRows.map((r) => r['id']).toSet(), {'acct-a', 'acct-b'});
    expect(bRows.map((r) => r['id']).toSet(), {'acct-a', 'acct-b'});

    final aName = aRows.singleWhere((r) => r['id'] == 'acct-b')['name'] as String;
    final bName = bRows.singleWhere((r) => r['id'] == 'acct-a')['name'] as String;
    final aAmount = aRows.singleWhere((r) => r['id'] == 'acct-b')['starting_amount'];
    final bAmount = bRows.singleWhere((r) => r['id'] == 'acct-a')['starting_amount'];
    expect(aName, 'Rent');
    expect(bName, 'Groceries');
    expect(double.parse(aAmount.toString()), 900.0);
    expect(double.parse(bAmount.toString()), 100.0);
  });

  test('regular sync re-keys amounts so they do not arrive zeroed', () async {
    final keyA = SecretKey(List<int>.filled(32, 21));
    final keyB = SecretKey(List<int>.filled(32, 22));
    final a = SyncTestDevice(
      id: 'device-a',
      name: 'Device A',
      secret: secret,
      key: keyA,
    );
    final b = SyncTestDevice(
      id: 'device-b',
      name: 'Device B',
      secret: secret,
      key: keyB,
    );
    addTearDown(a.dispose);
    addTearDown(b.dispose);
    await a.setUp();
    await b.setUp();

    // Simulate B being logged in (holding its live encryption key), which the
    // sync layer uses as the re-keying target for inbound rows.
    DatabaseManager.instance.setEncryptionKey(keyB);
    addTearDown(() => DatabaseManager.instance.clearEncryptionKey());

    await a.seedUser('user-a', 'alice');
    await b.seedUser('user-b', 'alice');
    await a.crdt.execute(
      'INSERT INTO accounts (id, user_id, name, starting_amount) VALUES '
      '(?1, ?2, ?3, ?4)',
      [
        'acct-a',
        'user-a',
        await EncryptionService.encrypt('Groceries', keyA),
        await EncryptionService.encrypt('42.5', keyA),
      ],
    );

    await pair(a, b);
    await b.start();

    // Pairing already established B's stored peer key (A's db key). A later
    // adds a new account, and a *regular* sync initiated by B must re-key it
    // to B's key. Regression: _doSync used to apply A's rows with a null peer
    // key, double-encrypting the amount so it decrypted to 0 on B.
    await a.crdt.execute(
      'INSERT INTO accounts (id, user_id, name, starting_amount) VALUES '
      '(?1, ?2, ?3, ?4)',
      [
        'acct-a2',
        'user-a',
        await EncryptionService.encrypt('Rent', keyA),
        await EncryptionService.encrypt('7.25', keyA),
      ],
    );

    await b.manager.syncNow(a.id,
        host: 'localhost', port: a.manager.serverPort!);

    await waitUntil(
      () async =>
          (await b.crdt.query(
                    'SELECT id FROM accounts WHERE id = ? AND is_deleted = 0',
                    ['acct-a2'],
                  ))
              .isNotEmpty,
    );
    final rows = await b.crdt.query(
      'SELECT starting_amount FROM accounts WHERE id = ?',
      ['acct-a2'],
    );
    expect(
      await EncryptionService.decrypt(
        rows.single['starting_amount'] as String,
        keyB,
      ),
      '7.25',
    );
  });

  test('password change keeps re-encrypted peer data readable after re-share',
      () async {
    final keyA0 = SecretKey(List<int>.filled(32, 11));
    final keyA1 = SecretKey(List<int>.filled(32, 12));
    final keyB = SecretKey(List<int>.filled(32, 13));
    final a = SyncTestDevice(
      id: 'device-a',
      name: 'Device A',
      secret: secret,
      key: keyA0,
    );
    final b = SyncTestDevice(
      id: 'device-b',
      name: 'Device B',
      secret: secret,
      key: keyB,
    );
    addTearDown(a.dispose);
    addTearDown(b.dispose);
    await a.setUp();
    await b.setUp();

    await a.seedUser('user-a', 'alice');
    await a.crdt.execute(
      'INSERT INTO accounts (id, user_id, name) VALUES (?1, ?2, ?3)',
      ['acct-a', 'user-a', await EncryptionService.encrypt('Groceries', keyA0)],
    );
    await b.seedUser('user-b', 'alice');
    await b.crdt.execute(
      'INSERT INTO accounts (id, user_id, name) VALUES (?1, ?2, ?3)',
      ['acct-b', 'user-b', await EncryptionService.encrypt('Rent', keyB)],
    );

    await pair(a, b);
    await b.start();

    // Baseline: peer data was re-keyed on first contact.
    final bRows0 = await waitForAccounts(b);
    expect(
      bRows0.singleWhere((r) => r['id'] == 'acct-a')['name'],
      'Groceries',
    );

    // Device A changes its password: the DB is re-encrypted under a new key
    // (rewriting rows bumps their HLC so they are pushed on the next sync).
    a.key = keyA1;
    await a.crdt.execute(
      'UPDATE accounts SET name = ? WHERE id = ?',
      [await EncryptionService.encrypt('Groceries', keyA1), 'acct-a'],
    );

    final bHlc0 =
        (await b.query('SELECT hlc FROM accounts WHERE id = ?', ['acct-a']))
            .single['hlc'];

    await a.manager.updatePeerKey(b.id,
        host: 'localhost', port: b.manager.serverPort!);

    // Wait for B to actually apply the re-encrypted row (B already had the row
    // from pairing, so wait for its HLC to advance past the pre-sync value).
    await waitUntil(() async {
      final row =
          (await b.query('SELECT hlc FROM accounts WHERE id = ?', ['acct-a']))
              .single;
      return row['hlc'] != bHlc0;
    });

    // B re-keys A's re-encrypted rows with the *freshly* exchanged key, so the
    // account name stays readable on B.
    final bName1 =
        (await b.query('SELECT name FROM accounts WHERE id = ?', ['acct-a']))
            .single['name'];
    expect(bName1, 'Groceries');
  });

  test('applying a remote changeset notifies onRemoteDataApplied', () async {
    final a = SyncTestDevice(id: 'device-a', name: 'Device A', secret: secret);
    final b = SyncTestDevice(id: 'device-b', name: 'Device B', secret: secret);
    addTearDown(a.dispose);
    addTearDown(b.dispose);
    await a.setUp();
    await b.setUp();

    await a.seedUser('user-a', 'alice');
    await a.crdt.execute(
      'INSERT INTO accounts (id, user_id, name) VALUES (?1, ?2, ?3)',
      ['acct-a', 'user-a', 'A account'],
    );

    final remoteEvents = <void>[];
    final sub = DatabaseManager.instance.onRemoteDataApplied.listen(remoteEvents.add);
    addTearDown(sub.cancel);

    await pair(a, b);

    // The device that received A's data (the scanner B) fired the event so its
    // mounted views know to reload.
    await waitUntil(() async => remoteEvents.isNotEmpty);
    expect(remoteEvents, isNotEmpty);
  });
}

Future<List<Map<String, Object?>>> waitForAccounts(SyncTestDevice device) async {
  List<Map<String, Object?>> rows = [];
  await waitUntil(() async {
    rows = await device.query('SELECT id, name, starting_amount FROM accounts WHERE is_deleted = 0');
    return rows.length >= 2;
  });
  return rows;
}
