import 'package:flutter_test/flutter_test.dart';

import 'package:peadra/core/database/database_manager.dart';
import 'package:peadra/core/services/encryption_service.dart';
import '../helpers/test_helper.dart';

void main() {
  setUpAll(() {
    initializeTestDatabase();
  });

  tearDown(() {
    DatabaseManager.instance.clearEncryptionKey();
  });

  test(
    'migrateEncryptionKey re-encrypts legacy random-salt data to the new key',
    () async {
      final dm = DatabaseManager.instance;
      final crdt = await dm.openInMemoryForTest(userId: 'user-legacy');
      addTearDown(crdt.close);

      final legacyKey = await deriveTestKey();
      final newKey = await deriveTestKey(password: 'new-password');

      await crdt.execute(
        'INSERT INTO users (id, username, password_hash) VALUES (?, ?, ?)',
        ['user-legacy', 'alice', 'hash'],
      );

      final encName = await EncryptionService.encrypt('Groceries', legacyKey);
      final encAmount = await EncryptionService.encrypt('7.25', legacyKey);
      await crdt.execute(
        'INSERT INTO accounts (id, user_id, name, type, starting_amount) '
        'VALUES (?, ?, ?, ?, ?)',
        ['acct-1', 'user-legacy', encName, 'checking', encAmount],
      );

      await dm.migrateEncryptionKey(legacyKey, newKey);

      final rows = await crdt.query(
        'SELECT name, starting_amount FROM accounts WHERE id = ?',
        ['acct-1'],
      );
      final storedName = rows.single['name'] as String;
      final storedAmount = rows.single['starting_amount'] as String;

      expect(
        await EncryptionService.decrypt(storedName, newKey),
        'Groceries',
      );
      expect(
        await EncryptionService.decrypt(storedAmount, newKey),
        '7.25',
      );
      await expectLater(
        () => EncryptionService.decrypt(storedName, legacyKey),
        throwsA(anything),
      );
    },
  );

  test(
    'migrateEncryptionKey re-encrypts transaction amounts and notes, '
    'including future-dated rows',
    () async {
      final dm = DatabaseManager.instance;
      final crdt = await dm.openInMemoryForTest(userId: 'user-txn');
      addTearDown(crdt.close);

      final legacyKey = await deriveTestKey();
      final newKey = await deriveTestKey(password: 'new-password');

      await crdt.execute(
        'INSERT INTO users (id, username, password_hash) VALUES (?, ?, ?)',
        ['user-txn', 'alice', 'hash'],
      );

      final encAmount = await EncryptionService.encrypt('12.50', legacyKey);
      final encNotes = await EncryptionService.encrypt('lunch', legacyKey);
      final futureDate = DateTime.now()
          .add(const Duration(days: 30))
          .toIso8601String()
          .substring(0, 10);
      // Past row.
      await crdt.execute(
        'INSERT INTO transactions (id, user_id, date, amount, transaction_type, notes) '
        'VALUES (?, ?, ?, ?, ?, ?)',
        ['txn-past', 'user-txn', '2025-01-15', encAmount, 'expense', encNotes],
      );
      // Future pre-generated occurrence must migrate too.
      await crdt.execute(
        'INSERT INTO transactions (id, user_id, date, amount, transaction_type, notes) '
        'VALUES (?, ?, ?, ?, ?, ?)',
        ['txn-future', 'user-txn', futureDate, encAmount, 'expense', encNotes],
      );

      await dm.migrateEncryptionKey(legacyKey, newKey);

      for (final id in ['txn-past', 'txn-future']) {
        final rows = await crdt.query(
          'SELECT amount, notes FROM transactions WHERE id = ?',
          [id],
        );
        expect(
          await EncryptionService.decrypt(rows.single['amount'] as String, newKey),
          '12.50',
        );
        expect(
          await EncryptionService.decrypt(rows.single['notes'] as String, newKey),
          'lunch',
        );
      }
    },
  );

  test(
    'mergeDescriptions with a case-only difference keeps the live row',
    () async {
      final dm = DatabaseManager.instance;
      final crdt = await dm.openInMemoryForTest(userId: 'user-merge');
      addTearDown(crdt.close);
      await dm.setEncryptionKey(await deriveTestKey());

      await crdt.execute(
        'INSERT INTO users (id, username, password_hash) VALUES (?, ?, ?)',
        ['user-merge', 'alice', 'hash'],
      );
      final descId = await dm.getOrCreateDescription('Coffee');
      await crdt.execute(
        'INSERT INTO transactions (id, user_id, date, amount, transaction_type, description_id) '
        'VALUES (?, ?, ?, ?, ?, ?)',
        ['txn-1', 'user-merge', '2025-01-15', '3.00', 'expense', descId],
      );

      final merged = await dm.mergeDescriptions('Coffee', 'coffee');
      expect(merged, isFalse);

      final rows = await crdt.query(
        'SELECT id FROM descriptions WHERE id = ? AND is_deleted = 0',
        [descId],
      );
      expect(rows, isNotEmpty);
      final txns = await crdt.query(
        'SELECT description_id FROM transactions WHERE id = ?',
        ['txn-1'],
      );
      expect(txns.single['description_id'], descId);
    },
  );

  test(
    'getOrCreateDescription does not reuse a deleted cached id',
    () async {
      final dm = DatabaseManager.instance;
      final crdt = await dm.openInMemoryForTest(userId: 'user-cache');
      addTearDown(crdt.close);
      await dm.setEncryptionKey(await deriveTestKey());

      await crdt.execute(
        'INSERT INTO users (id, username, password_hash) VALUES (?, ?, ?)',
        ['user-cache', 'alice', 'hash'],
      );
      final firstId = await dm.getOrCreateDescription('Coffee');
      await crdt.execute(
        'DELETE FROM descriptions WHERE id = ?',
        [firstId],
      );

      final secondId = await dm.getOrCreateDescription('Coffee');
      expect(secondId, isNot(firstId));
      final rows = await crdt.query(
        'SELECT id FROM descriptions WHERE id = ? AND is_deleted = 0',
        [secondId],
      );
      expect(rows, isNotEmpty);
    },
  );

  test(
    'repairDanglingDescriptionRefs repoints tombstoned refs and reports '
    'undecryptable rows',
    () async {
      final dm = DatabaseManager.instance;
      final crdt = await dm.openInMemoryForTest(userId: 'user-repair');
      addTearDown(crdt.close);
      final ownerKey = await deriveTestKey();
      await dm.setEncryptionKey(ownerKey);

      await crdt.execute(
        'INSERT INTO users (id, username, password_hash) VALUES (?, ?, ?)',
        ['user-repair', 'alice', 'hash'],
      );

      // Live "coffee" row (lowercase duplicate of the deleted "Coffee").
      // Inserted directly to bypass the in-memory description cache.
      final liveName = await EncryptionService.encrypt('coffee', ownerKey);
      await crdt.execute(
        'INSERT INTO descriptions (id, user_id, name) VALUES (?, ?, ?)',
        ['desc-live', 'user-repair', liveName],
      );
      const liveId = 'desc-live';
      // Dead row whose name is still readable + a transaction pinned to it.
      final deadName =
          await EncryptionService.encrypt('Coffee', ownerKey);
      await crdt.execute(
        'INSERT INTO descriptions (id, user_id, name) VALUES (?, ?, ?)',
        ['desc-dead', 'user-repair', deadName],
      );
      await crdt.execute(
        'INSERT INTO transactions (id, user_id, date, amount, transaction_type, description_id) '
        'VALUES (?, ?, ?, ?, ?, ?)',
        ['txn-dangling', 'user-repair', '2025-01-15', '3.00', 'expense', 'desc-dead'],
      );
      await crdt.execute(
        'DELETE FROM descriptions WHERE id = ?',
        ['desc-dead'],
      );
      // Live row encrypted under a foreign key: unrecoverable, must be counted.
      final foreignKey = await deriveTestKey(password: 'foreign-pass');
      final foreignName =
          await EncryptionService.encrypt('Mystery', foreignKey);
      await crdt.execute(
        'INSERT INTO descriptions (id, user_id, name) VALUES (?, ?, ?)',
        ['desc-foreign', 'user-repair', foreignName],
      );

      final result = await dm.repairDanglingDescriptionRefs();
      expect(result.repointed, 1);

      final txns = await crdt.query(
        'SELECT description_id FROM transactions WHERE id = ?',
        ['txn-dangling'],
      );
      expect(txns.single['description_id'], liveId);
      expect(result.undecryptable, 1);
    },
  );

  test(
    'repairDanglingDescriptionRefs resurrects a dead row when no live '
    'same-name row exists',
    () async {
      final dm = DatabaseManager.instance;
      final crdt = await dm.openInMemoryForTest(userId: 'user-resurrect');
      addTearDown(crdt.close);
      final ownerKey = await deriveTestKey();
      await dm.setEncryptionKey(ownerKey);

      await crdt.execute(
        'INSERT INTO users (id, username, password_hash) VALUES (?, ?, ?)',
        ['user-resurrect', 'alice', 'hash'],
      );
      final name = await EncryptionService.encrypt('Bakery', ownerKey);
      await crdt.execute(
        'INSERT INTO descriptions (id, user_id, name) VALUES (?, ?, ?)',
        ['desc-gone', 'user-resurrect', name],
      );
      await crdt.execute(
        'INSERT INTO transactions (id, user_id, date, amount, transaction_type, description_id) '
        'VALUES (?, ?, ?, ?, ?, ?)',
        ['txn-orphan', 'user-resurrect', '2025-02-01', '4.00', 'expense', 'desc-gone'],
      );
      await crdt.execute(
        'DELETE FROM descriptions WHERE id = ?',
        ['desc-gone'],
      );

      final result = await dm.repairDanglingDescriptionRefs();
      expect(result.repointed, 1);

      final rows = await crdt.query(
        'SELECT id FROM descriptions WHERE id = ? AND is_deleted = 0',
        ['desc-gone'],
      );
      expect(rows, isNotEmpty);
      final txns = await dm.getTransactions(searchQuery: 'Bakery');
      expect(txns.map((t) => t.id), contains('txn-orphan'));
      expect(txns.firstWhere((t) => t.id == 'txn-orphan').descriptionName,
          'Bakery');
    },
  );

  test('migrateEncryptionKey leaves foreign-key and plaintext rows untouched',
      () async {
    final dm = DatabaseManager.instance;
    final crdt = await dm.openInMemoryForTest(userId: 'user-owner');
    addTearDown(crdt.close);

    final ownerKey = await deriveTestKey();
    final foreignKey = await deriveTestKey(password: 'foreign-pass');
    final newKey = await deriveTestKey(password: 'new-password');

    await crdt.execute(
      'INSERT INTO users (id, username, password_hash) VALUES (?, ?, ?)',
      ['user-owner', 'alice', 'hash'],
    );
    await crdt.execute(
      'INSERT INTO users (id, username, password_hash) VALUES (?, ?, ?)',
      ['user-foreign', 'bob', 'hash'],
    );

    final ownerName = await EncryptionService.encrypt('Groceries', ownerKey);
    await crdt.execute(
      'INSERT INTO accounts (id, user_id, name, type, starting_amount) '
      'VALUES (?, ?, ?, ?, ?)',
      ['acct-owner', 'user-owner', ownerName, 'checking', null],
    );

    final foreignName = await EncryptionService.encrypt('Bobs Stuff', foreignKey);
    await crdt.execute(
      'INSERT INTO accounts (id, user_id, name, type, starting_amount) '
      'VALUES (?, ?, ?, ?, ?)',
      ['acct-foreign', 'user-foreign', foreignName, 'checking', null],
    );

    // Plaintext row owned by the current user must remain plaintext.
    await crdt.execute(
      'INSERT INTO accounts (id, user_id, name, type, starting_amount) '
      'VALUES (?, ?, ?, ?, ?)',
      ['acct-plain', 'user-owner', 'Plain Text', 'checking', null],
    );

    await dm.migrateEncryptionKey(ownerKey, newKey);

    final owner = (await crdt.query(
      'SELECT name FROM accounts WHERE id = ?',
      ['acct-owner'],
    ))
        .single;
    expect(
      await EncryptionService.decrypt(owner['name'] as String, newKey),
      'Groceries',
    );

    final foreign = (await crdt.query(
      'SELECT name FROM accounts WHERE id = ?',
      ['acct-foreign'],
    ))
        .single;
    expect(
      await EncryptionService.decrypt(foreign['name'] as String, foreignKey),
      'Bobs Stuff',
    );

    final plain = (await crdt.query(
      'SELECT name FROM accounts WHERE id = ?',
      ['acct-plain'],
    ))
        .single;
    expect(plain['name'], 'Plain Text');
  });
}