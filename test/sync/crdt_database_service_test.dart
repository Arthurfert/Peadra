import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite_crdt/sqlite_crdt.dart';

import 'package:peadra/sync/storage/crdt_database_service.dart';

import 'test_crdt_schema.dart';

void main() {
  initializeSyncTestDb();

  Future<void> seedUser(SqliteCrdt db, String id, String username) {
    return db.execute(
      'INSERT INTO users (id, username, password_hash) VALUES (?1, ?2, ?3)',
      [id, username, 'hash'],
    );
  }

  Future<void> seedAccount(
    SqliteCrdt db,
    String id,
    String userId,
    String name,
  ) {
    return db.execute(
      'INSERT INTO accounts (id, user_id, name) VALUES (?1, ?2, ?3)',
      [id, userId, name],
    );
  }

  test('getChangeset returns local rows', () async {
    final db = await createCrdtDatabase();
    addTearDown(() => db.close());
    final service = CrdtDatabaseService(db);

    await seedUser(db, 'user-a', 'alice');
    final changeset = await service.getChangeset();

    expect(changeset['users'], hasLength(1));
    final row = changeset['users']!.single;
    expect(row['id'], 'user-a');
    expect(row['username'], 'alice');
    expect(row['hlc'], isA<String>());
    expect(Hlc.parse(row['hlc'] as String), isA<Hlc>());
  });

  test('applyChangeset merges rows from another database', () async {
    final dbA = await createCrdtDatabase();
    final dbB = await createCrdtDatabase();
    addTearDown(() async {
      await dbA.close();
      await dbB.close();
    });
    final serviceA = CrdtDatabaseService(dbA);
    final serviceB = CrdtDatabaseService(dbB);

    await seedUser(dbA, 'user-a', 'alice');
    await seedAccount(dbA, 'acct-a', 'user-a', 'A account');

    final changeset = await serviceA.getChangeset();
    await serviceB.applyChangeset(changeset);

    final rows = await dbB.query('SELECT * FROM accounts WHERE is_deleted = 0');
    expect(rows, hasLength(1));
    expect(rows.single['name'], 'A account');
  });

  test('lastModifiedHlc advances after applying a changeset', () async {
    final dbA = await createCrdtDatabase();
    final dbB = await createCrdtDatabase();
    addTearDown(() async {
      await dbA.close();
      await dbB.close();
    });
    final serviceA = CrdtDatabaseService(dbA);
    final serviceB = CrdtDatabaseService(dbB);

    final before = await serviceB.lastModifiedHlc();
    await seedUser(dbA, 'user-a', 'alice');
    await serviceB.applyChangeset(await serviceA.getChangeset());
    final after = await serviceB.lastModifiedHlc();

    expect(after > before, isTrue);
  });

  test('isSyncSelfChange filters out events produced by remote merges', () async {
    final dbA = await createCrdtDatabase();
    final dbB = await createCrdtDatabase();
    addTearDown(() async {
      await dbA.close();
      await dbB.close();
    });
    final serviceA = CrdtDatabaseService(dbA);
    final serviceB = CrdtDatabaseService(dbB);

    final events = <({Hlc hlc, Iterable<String> tables})>[];
    final sub = serviceB.onTablesChanged.listen(events.add);

    await seedUser(dbB, 'user-b', 'bob');
    await Future<void>.delayed(Duration.zero);
    final localEvent = events.single;
    expect(serviceB.isSyncSelfChange(hlc: localEvent.hlc), isTrue);

    await seedUser(dbA, 'user-a', 'alice');
    await serviceB.applyChangeset(await serviceA.getChangeset());
    await Future<void>.delayed(Duration.zero);

    final applied = events.last;
    expect(serviceB.isSyncSelfChange(hlc: applied.hlc), isFalse);
    expect(serviceB.lastAppliedHlc, isNotNull);
    expect(
      serviceB.isSyncSelfChange(hlc: serviceB.lastAppliedHlc!.increment()),
      isTrue,
    );
    await sub.cancel();
  });
}
