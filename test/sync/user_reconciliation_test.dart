import 'package:flutter_test/flutter_test.dart';

import 'package:peadra/sync/security/user_reconciliation.dart';
import 'package:peadra/sync/storage/crdt_database_service.dart';

import 'test_crdt_schema.dart';

void main() {
  initializeSyncTestDb();

  group('UserReconciliation.plan', () {
    test('is empty when usernames do not collide', () {
      final plan = UserReconciliation.plan(
        localUsers: {'alice': 'local-a', 'bob': 'local-b'},
        remoteUsers: {'carol': 'remote-c'},
      );
      expect(plan.isEmpty, isTrue);
    });

    test('is empty when matching usernames already share an id', () {
      final plan = UserReconciliation.plan(
        localUsers: {'alice': 'same'},
        remoteUsers: {'alice': 'same'},
      );
      expect(plan.isEmpty, isTrue);
    });

    test('prefers the remote id when preferRemote is true', () {
      final plan = UserReconciliation.plan(
        localUsers: {'alice': 'local-a'},
        remoteUsers: {'alice': 'remote-a'},
        preferRemote: true,
      );
      expect(plan.remaps, hasLength(1));
      expect(plan.remaps.single.localUserId, 'local-a');
      expect(plan.remaps.single.canonicalUserId, 'remote-a');
    });

    test('picks the lexicographically smaller id when preferRemote is false', () {
      final plan = UserReconciliation.plan(
        localUsers: {'alice': 'zzz-local'},
        remoteUsers: {'alice': 'aaa-remote'},
        preferRemote: false,
      );
      expect(plan.remaps.single.canonicalUserId, 'aaa-remote');
    });

    test('ignores usernames that only exist locally', () {
      final plan = UserReconciliation.plan(
        localUsers: {'alice': 'local-a', 'only-me': 'local-b'},
        remoteUsers: {'alice': 'remote-a'},
      );
      expect(plan.remaps, hasLength(1));
      expect(plan.remaps.single.localUserId, 'local-a');
    });
  });

  group('applyUserReconciliation', () {
    test('repoints child references and rewrites the user primary key', () async {
      final db = await createCrdtDatabase();
      addTearDown(() => db.close());
      final service = CrdtDatabaseService(db);

      await db.execute(
        'INSERT INTO users (id, username, password_hash) VALUES (?1, ?2, ?3)',
        ['user-b', 'alice', 'h'],
      );
      await db.execute(
        'INSERT INTO accounts (id, user_id, name) VALUES (?1, ?2, ?3)',
        ['acct-b', 'user-b', 'B account'],
      );
      await db.execute(
        'INSERT INTO descriptions (id, user_id, name) VALUES (?1, ?2, ?3)',
        ['desc-b', 'user-b', 'B description'],
      );

      await service.applyUserReconciliation(const [
        UserIdRemap(localUserId: 'user-b', canonicalUserId: 'user-a'),
      ]);

      final users = await db.query('SELECT id FROM users');
      expect(users.single['id'], 'user-a');
      expect(
        (await db.query('SELECT user_id FROM accounts')).single['user_id'],
        'user-a',
      );
      expect(
        (await db.query('SELECT user_id FROM descriptions')).single['user_id'],
        'user-a',
      );
    });

    test('is a no-op for an empty plan', () async {
      final db = await createCrdtDatabase();
      addTearDown(() => db.close());
      final service = CrdtDatabaseService(db);
      await service.applyUserReconciliation(const []);
      expect(await db.query('SELECT * FROM users'), isEmpty);
    });
  });
}
