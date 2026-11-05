import 'package:flutter_test/flutter_test.dart';

import 'package:peadra/sync/security/auth_challenge.dart';

import 'sync_test_helpers.dart';
import 'test_crdt_schema.dart';

void main() {
  initializeSyncTestDb();

  test('transfer legs keep the fields the UI pairs on after sync', () async {
    final secret = AuthChallenge.generateSharedSecret();
    final a = SyncTestDevice(id: 'device-a', name: 'A', secret: secret);
    final b = SyncTestDevice(id: 'device-b', name: 'B', secret: secret);
    addTearDown(a.dispose);
    addTearDown(b.dispose);
    await a.setUp();
    await b.setUp();

    await a.seedUser('user-a', 'alice');
    await a.crdt.execute(
      'INSERT INTO accounts (id, user_id, name) VALUES (?1, ?2, ?3)',
      ['src', 'user-a', 'Checking'],
    );
    await a.crdt.execute(
      'INSERT INTO accounts (id, user_id, name) VALUES (?1, ?2, ?3)',
      ['dst', 'user-a', 'Savings'],
    );
    await a.crdt.execute(
      'INSERT INTO transactions (id, user_id, account_id, date, amount, transaction_type, notes) '
      'VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)',
      [
        'leg1',
        'user-a',
        'src',
        '2026-11-01',
        10,
        'expense',
        'Transfer to Savings',
      ],
    );
    await a.crdt.execute(
      'INSERT INTO transactions (id, user_id, account_id, date, amount, transaction_type, notes) '
      'VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)',
      [
        'leg2',
        'user-a',
        'dst',
        '2026-11-01',
        10,
        'income',
        'Transfer from Checking',
      ],
    );

    a.manager.registerPairingSecret(b.id, secret);
    await a.start();
    await b.manager.runPairingSession(
      peerId: a.id,
      deviceName: a.name,
      sharedSecret: secret,
      host: 'localhost',
      port: a.manager.serverPort!,
    );

    final rows = await b.query(
      'SELECT t.id, t.date, t.transaction_type, t.notes, a.name AS account_name '
      'FROM transactions t LEFT JOIN accounts a ON t.account_id = a.id '
      'WHERE t.user_id = ? AND t.is_deleted = 0 ORDER BY t.id',
      ['user-a'],
    );
    expect(rows, hasLength(2));
    expect(
      rows
          .map(
            (r) => [
              r['id'],
              r['date'],
              r['transaction_type'],
              r['notes'],
              r['account_name'],
            ],
          )
          .toList(),
      [
        ['leg1', '2026-11-01', 'expense', 'Transfer to Savings', 'Checking'],
        ['leg2', '2026-11-01', 'income', 'Transfer from Checking', 'Savings'],
      ],
    );
  });
}
