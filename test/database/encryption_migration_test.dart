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