import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:peadra/core/services/encryption_service.dart';
import '../helpers/test_helper.dart';

void main() {
  late Database db;
  late int userId;
  late SecretKey key;

  setUpAll(() {
    initializeTestDatabase();
  });

  setUp(() async {
    db = await createTestDatabase();
    userId = await seedTestUser(db);
    key = await deriveTestKey();
  });

  tearDown(() async {
    await db.close();
  });

  group('Raw field encryption', () {
    test('encrypted account name is valid base64 and not plaintext', () async {
      final encName = await encryptTest('My Checking Account', key: key);

      // Verify it's valid base64
      expect(() => base64Decode(encName), returnsNormally);

      // Verify it's not the plaintext
      expect(encName, isNot(equals('My Checking Account')));
    });

    test('encrypted amount is valid base64 and not a number', () async {
      final encAmount = await encryptTest('12345.67', key: key);

      expect(() => base64Decode(encAmount), returnsNormally);
      expect(double.tryParse(encAmount), isNull);
    });

    test('encrypted description name is valid base64', () async {
      final encName = await encryptTest('Groceries', key: key);

      expect(() => base64Decode(encName), returnsNormally);
      expect(encName, isNot(equals('Groceries')));
    });

    test('encrypted notes is valid base64', () async {
      final encNotes = await encryptTest('Weekly shopping at the mall', key: key);

      expect(() => base64Decode(encNotes), returnsNormally);
      expect(encNotes, isNot(equals('Weekly shopping at the mall')));
    });

    test('different encryptions of same plaintext produce different ciphertexts', () async {
      final enc1 = await encryptTest('same_value', key: key);
      final enc2 = await encryptTest('same_value', key: key);

      expect(enc1, isNot(equals(enc2)));
    });
  });

  group('Encryption via seed helpers', () {
    test('seedEncryptedAccount stores encrypted data', () async {
      final accountId = await seedEncryptedAccount(
        db,
        userId,
        name: 'Test Checking',
        startingAmount: 5000.0,
        key: key,
      );

      final raw = await db.rawQuery(
        'SELECT name, starting_amount FROM accounts WHERE id = ?',
        [accountId],
      );
      expect(raw.length, 1);

      final rawName = raw.first['name'] as String;
      final rawAmount = raw.first['starting_amount'] as String;

      // Data in DB is NOT plaintext
      expect(rawName, isNot(equals('Test Checking')));
      expect(double.tryParse(rawAmount), isNull);

      // But decrypts correctly
      final decryptedName = await decryptTest(rawName, key: key);
      final decryptedAmount = await decryptTest(rawAmount, key: key);
      expect(decryptedName, equals('Test Checking'));
      expect(double.parse(decryptedAmount), equals(5000.0));
    });

    test('seedEncryptedDescription stores encrypted data', () async {
      final descId = await seedEncryptedDescription(
        db,
        userId,
        'Restaurant Expenses',
        key: key,
      );

      final raw = await db.rawQuery(
        'SELECT name FROM descriptions WHERE id = ?',
        [descId],
      );
      expect(raw.length, 1);

      final rawName = raw.first['name'] as String;
      expect(rawName, isNot(equals('Restaurant Expenses')));

      final decryptedName = await decryptTest(rawName, key: key);
      expect(decryptedName, equals('Restaurant Expenses'));
    });

    test('seedEncryptedTransaction stores encrypted amount and notes', () async {
      final txnId = await seedEncryptedTransaction(
        db,
        userId,
        amount: 42.50,
        notes: 'Lunch with team',
        key: key,
      );

      final raw = await db.rawQuery(
        'SELECT amount, notes FROM transactions WHERE id = ?',
        [txnId],
      );
      expect(raw.length, 1);

      final rawAmount = raw.first['amount'] as String;
      final rawNotes = raw.first['notes'] as String;

      expect(double.tryParse(rawAmount), isNull);
      expect(rawNotes, isNot(equals('Lunch with team')));

      final decryptedAmount = await decryptTest(rawAmount, key: key);
      final decryptedNotes = await decryptTest(rawNotes, key: key);
      expect(double.parse(decryptedAmount), equals(42.50));
      expect(decryptedNotes, equals('Lunch with team'));
    });

    test('seedEncryptedTransaction with null notes', () async {
      final txnId = await seedEncryptedTransaction(
        db,
        userId,
        amount: 100.0,
        notes: null,
        key: key,
      );

      final raw = await db.rawQuery(
        'SELECT notes FROM transactions WHERE id = ?',
        [txnId],
      );
      expect(raw.first['notes'], isNull);
    });
  });

  group('Migration simulation', () {
    test('migrateToEncryption encrypts account fields', () async {
      // Insert plaintext account
      final accountId = await db.insert('accounts', {
        'user_id': userId,
        'name': 'Plaintext Account',
        'type': 'checking',
        'currency': 'EUR',
        'starting_amount': 1000.0,
      });

      // Verify it's stored as a number
      final before = await db.rawQuery(
        'SELECT starting_amount FROM accounts WHERE id = ?',
        [accountId],
      );
      expect(before.first['starting_amount'], isA<num>());

      // Encrypt the fields manually (simulating what DatabaseManager._encryptAccounts does)
      final rows = await db.rawQuery(
        'SELECT id, name, starting_amount FROM accounts WHERE user_id = ?',
        [userId],
      );
      for (final row in rows) {
        final name = row['name'] as String?;
        final amount = row['starting_amount'] as num?;
        final encryptedName = await EncryptionService.encrypt(name!, key);
        final encryptedAmount = amount != null
            ? await EncryptionService.encrypt(amount.toString(), key)
            : null;
        await db.rawUpdate(
          'UPDATE accounts SET name = ?, starting_amount = ? WHERE id = ?',
          [encryptedName, encryptedAmount, row['id']],
        );
      }

      // Verify data is now encrypted
      final after = await db.rawQuery(
        'SELECT name, starting_amount FROM accounts WHERE id = ?',
        [accountId],
      );
      final rawName = after.first['name'] as String;
      final rawAmount = after.first['starting_amount'] as String;

      expect(rawName, isNot(equals('Plaintext Account')));
      expect(double.tryParse(rawAmount), isNull);

      // Verify decryption works
      final decryptedName = await EncryptionService.decrypt(rawName, key);
      final decryptedAmount = await EncryptionService.decrypt(rawAmount, key);
      expect(decryptedName, equals('Plaintext Account'));
      expect(double.parse(decryptedAmount), equals(1000.0));
    });

    test('migrateToEncryption encrypts description fields', () async {
      final descId = await db.insert('descriptions', {
        'user_id': userId,
        'name': 'Groceries',
      });

      // Encrypt
      final rows = await db.rawQuery(
        'SELECT id, name FROM descriptions WHERE user_id = ?',
        [userId],
      );
      for (final row in rows) {
        final name = row['name'] as String?;
        final encryptedName = await EncryptionService.encrypt(name!, key);
        await db.rawUpdate(
          'UPDATE descriptions SET name = ? WHERE id = ?',
          [encryptedName, row['id']],
        );
      }

      final after = await db.rawQuery(
        'SELECT name FROM descriptions WHERE id = ?',
        [descId],
      );
      final rawName = after.first['name'] as String;
      expect(rawName, isNot(equals('Groceries')));

      final decrypted = await EncryptionService.decrypt(rawName, key);
      expect(decrypted, equals('Groceries'));
    });

    test('migrateToEncryption encrypts transaction fields', () async {
      final acctId = await seedTestAccounts(db, userId);
      final txnId = await db.insert('transactions', {
        'user_id': userId,
        'account_id': acctId.first,
        'date': '2025-06-15',
        'amount': 75.25,
        'transaction_type': 'expense',
        'currency': 'EUR',
        'notes': 'Dinner at restaurant',
      });

      // Encrypt
      final rows = await db.rawQuery(
        'SELECT id, amount, notes FROM transactions WHERE user_id = ?',
        [userId],
      );
      for (final row in rows) {
        final amount = row['amount'] as num?;
        final notes = row['notes'] as String?;
        final encryptedAmount = amount != null
            ? await EncryptionService.encrypt(amount.toString(), key)
            : null;
        final encryptedNotes = notes != null
            ? await EncryptionService.encrypt(notes, key)
            : null;
        await db.rawUpdate(
          'UPDATE transactions SET amount = ?, notes = ? WHERE id = ?',
          [encryptedAmount, encryptedNotes, row['id']],
        );
      }

      final after = await db.rawQuery(
        'SELECT amount, notes FROM transactions WHERE id = ?',
        [txnId],
      );
      final rawAmount = after.first['amount'] as String;
      final rawNotes = after.first['notes'] as String;

      expect(double.tryParse(rawAmount), isNull);
      expect(rawNotes, isNot(equals('Dinner at restaurant')));

      final decryptedAmount = await EncryptionService.decrypt(rawAmount, key);
      final decryptedNotes = await EncryptionService.decrypt(rawNotes, key);
      expect(double.parse(decryptedAmount), equals(75.25));
      expect(decryptedNotes, equals('Dinner at restaurant'));
    });

    test('encryption_meta tracks migration version', () async {
      await db.rawInsert(
        "INSERT OR REPLACE INTO encryption_meta (key, value) VALUES (?, ?)",
        ['version', '1'],
      );

      final meta = await db.rawQuery(
        "SELECT value FROM encryption_meta WHERE key = ?",
        ['version'],
      );
      expect(meta.length, 1);
      expect(meta.first['value'], equals('1'));
    });
  });

  group('Re-encryption (password change)', () {
    test('data readable with new key after re-encrypt', () async {
      final oldKey = await deriveTestKey(password: 'old_password');
      final newKey = await deriveTestKey(password: 'new_password');

      // Insert encrypted with old key
      final acctId = await seedEncryptedAccount(
        db,
        userId,
        name: 'My Account',
        startingAmount: 5000.0,
        key: oldKey,
      );

      // Re-encrypt: decrypt with old key, encrypt with new key
      final rows = await db.rawQuery(
        'SELECT id, name, starting_amount FROM accounts WHERE user_id = ?',
        [userId],
      );
      for (final row in rows) {
        final name = row['name'] as String?;
        final amount = row['starting_amount'] as String?;
        if (name != null && name.isNotEmpty) {
          final decrypted = await EncryptionService.decrypt(name, oldKey);
          final reEncrypted = await EncryptionService.encrypt(decrypted, newKey);
          await db.rawUpdate(
            'UPDATE accounts SET name = ? WHERE id = ?',
            [reEncrypted, row['id']],
          );
        }
        if (amount != null && amount.isNotEmpty) {
          final decrypted = await EncryptionService.decrypt(amount, oldKey);
          final reEncrypted = await EncryptionService.encrypt(decrypted, newKey);
          await db.rawUpdate(
            'UPDATE accounts SET starting_amount = ? WHERE id = ?',
            [reEncrypted, row['id']],
          );
        }
      }

      // Read with new key
      final after = await db.rawQuery(
        'SELECT name, starting_amount FROM accounts WHERE id = ?',
        [acctId],
      );
      final rawName = after.first['name'] as String;
      final rawAmount = after.first['starting_amount'] as String;

      final decryptedName = await EncryptionService.decrypt(rawName, newKey);
      final decryptedAmount = await EncryptionService.decrypt(rawAmount, newKey);
      expect(decryptedName, equals('My Account'));
      expect(double.parse(decryptedAmount), equals(5000.0));
    });

    test('data NOT readable with old key after re-encrypt', () async {
      final oldKey = await deriveTestKey(password: 'old_password');
      final newKey = await deriveTestKey(password: 'new_password');

      final acctId = await seedEncryptedAccount(
        db,
        userId,
        name: 'My Account',
        key: oldKey,
      );

      // Re-encrypt with new key
      final rows = await db.rawQuery(
        'SELECT id, name FROM accounts WHERE user_id = ?',
        [userId],
      );
      for (final row in rows) {
        final name = row['name'] as String?;
        if (name != null && name.isNotEmpty) {
          final decrypted = await EncryptionService.decrypt(name, oldKey);
          final reEncrypted = await EncryptionService.encrypt(decrypted, newKey);
          await db.rawUpdate(
            'UPDATE accounts SET name = ? WHERE id = ?',
            [reEncrypted, row['id']],
          );
        }
      }

      // Try to read with old key — should fail
      final after = await db.rawQuery(
        'SELECT name FROM accounts WHERE id = ?',
        [acctId],
      );
      final rawName = after.first['name'] as String;

      expect(
        () => EncryptionService.decrypt(rawName, oldKey),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('Edge cases', () {
    test('empty account name round-trip', () async {
      final encName = await encryptTest('', key: key);
      final decName = await decryptTest(encName, key: key);
      expect(decName, equals(''));
    });

    test('very long account name round-trip', () async {
      final longName = 'A' * 500;
      final encName = await encryptTest(longName, key: key);
      final decName = await decryptTest(encName, key: key);
      expect(decName, equals(longName));
    });

    test('unicode account name round-trip', () async {
      final name = 'Compte Épargne € 日本語';
      final encName = await encryptTest(name, key: key);
      final decName = await decryptTest(encName, key: key);
      expect(decName, equals(name));
    });

    test('zero amount round-trip', () async {
      final encAmount = await encryptTest('0.0', key: key);
      final decAmount = await decryptTest(encAmount, key: key);
      expect(double.parse(decAmount), equals(0.0));
    });

    test('negative amount round-trip', () async {
      final encAmount = await encryptTest('-500.25', key: key);
      final decAmount = await decryptTest(encAmount, key: key);
      expect(double.parse(decAmount), equals(-500.25));
    });

    test('very large amount round-trip', () async {
      final encAmount = await encryptTest('999999999999.99', key: key);
      final decAmount = await decryptTest(encAmount, key: key);
      expect(double.parse(decAmount), equals(999999999999.99));
    });

    test('special characters in notes round-trip', () async {
      final notes = "Line1\nLine2\tTabbed 'quotes' \"dquotes\" \\back";
      final encNotes = await encryptTest(notes, key: key);
      final decNotes = await decryptTest(encNotes, key: key);
      expect(decNotes, equals(notes));
    });

    test('encrypted accounts with different keys are independent', () async {
      final key1 = await deriveTestKey(password: 'user1_pass');
      final key2 = await deriveTestKey(password: 'user2_pass');

      final acct1Id = await seedEncryptedAccount(
        db, userId, name: 'User1 Account', key: key1,
      );
      // Insert second account for same user with different key (simulating multi-user)
      // In reality each user has their own key, this just tests key isolation
      final rawName1 = (await db.rawQuery(
        'SELECT name FROM accounts WHERE id = ?', [acct1Id],
      )).first['name'] as String;

      // key1 can decrypt
      final dec1 = await EncryptionService.decrypt(rawName1, key1);
      expect(dec1, equals('User1 Account'));

      // key2 cannot decrypt
      expect(
        () => EncryptionService.decrypt(rawName1, key2),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('Multiple field encryption in single transaction', () {
    test('encrypt account + description + transaction together', () async {
      // Create account
      final acctId = await seedEncryptedAccount(
        db, userId, name: 'Main Checking', startingAmount: 1000.0, key: key,
      );

      // Create description
      final descId = await seedEncryptedDescription(
        db, userId, 'Groceries', key: key,
      );

      // Create transaction
      final txnId = await seedEncryptedTransaction(
        db, userId,
        accountId: acctId,
        descriptionId: descId,
        amount: 55.30,
        notes: 'Weekly groceries',
        key: key,
      );

      // Verify all fields are encrypted in DB
      final acctRaw = await db.rawQuery('SELECT name, starting_amount FROM accounts WHERE id = ?', [acctId]);
      final descRaw = await db.rawQuery('SELECT name FROM descriptions WHERE id = ?', [descId]);
      final txnRaw = await db.rawQuery('SELECT amount, notes FROM transactions WHERE id = ?', [txnId]);

      // None should be plaintext
      expect(acctRaw.first['name'], isNot(equals('Main Checking')));
      expect(double.tryParse(acctRaw.first['starting_amount'] as String), isNull);
      expect(descRaw.first['name'], isNot(equals('Groceries')));
      expect(double.tryParse(txnRaw.first['amount'] as String), isNull);
      expect(txnRaw.first['notes'], isNot(equals('Weekly groceries')));

      // All should decrypt correctly
      expect(await decryptTest(acctRaw.first['name'] as String, key: key), equals('Main Checking'));
      expect(double.parse(await decryptTest(acctRaw.first['starting_amount'] as String, key: key)), equals(1000.0));
      expect(await decryptTest(descRaw.first['name'] as String, key: key), equals('Groceries'));
      expect(double.parse(await decryptTest(txnRaw.first['amount'] as String, key: key)), equals(55.30));
      expect(await decryptTest(txnRaw.first['notes'] as String, key: key), equals('Weekly groceries'));
    });
  });
}
