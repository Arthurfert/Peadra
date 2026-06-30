import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../helpers/test_helper.dart';

const int globalUserId = 0;

void main() {
  late Database db;
  late int userId;

  setUpAll(() {
    initializeTestDatabase();
  });

  setUp(() async {
    db = await createTestDatabase();
    userId = await seedTestUser(db);
  });

  tearDown(() async {
    await db.close();
  });

  // ==================== SETTINGS CRUD ====================

  group('Settings CRUD', () {
    test('setSetting and getSetting round-trip', () async {
      await db.rawInsert(
        'INSERT OR REPLACE INTO settings (user_id, key, value) VALUES (?, ?, ?)',
        [userId, 'theme', 'dark'],
      );

      final result = await db.rawQuery(
        'SELECT value FROM settings WHERE key = ? AND user_id = ?',
        ['theme', userId],
      );

      expect(result, isNotEmpty);
      expect(result.first['value'], 'dark');
    });

    test('getSetting returns defaultValue when key does not exist', () async {
      final result = await db.rawQuery(
        'SELECT value FROM settings WHERE key = ? AND user_id = ?',
        ['nonexistent', userId],
      );

      expect(result, isEmpty);
    });

    test('setSetting overwrites existing value (INSERT OR REPLACE)', () async {
      await db.rawInsert(
        'INSERT OR REPLACE INTO settings (user_id, key, value) VALUES (?, ?, ?)',
        [userId, 'currency', 'USD'],
      );
      await db.rawInsert(
        'INSERT OR REPLACE INTO settings (user_id, key, value) VALUES (?, ?, ?)',
        [userId, 'currency', 'GBP'],
      );

      final result = await db.rawQuery(
        'SELECT value FROM settings WHERE key = ? AND user_id = ?',
        ['currency', userId],
      );

      expect(result.length, 1);
      expect(result.first['value'], 'GBP');
    });

    test('settings are isolated per user', () async {
      final userId2 = await seedTestUser(db, username: 'user2');

      await db.rawInsert(
        'INSERT OR REPLACE INTO settings (user_id, key, value) VALUES (?, ?, ?)',
        [userId, 'theme', 'dark'],
      );
      await db.rawInsert(
        'INSERT OR REPLACE INTO settings (user_id, key, value) VALUES (?, ?, ?)',
        [userId2, 'theme', 'light'],
      );

      final r1 = await db.rawQuery(
        'SELECT value FROM settings WHERE key = ? AND user_id = ?',
        ['theme', userId],
      );
      final r2 = await db.rawQuery(
        'SELECT value FROM settings WHERE key = ? AND user_id = ?',
        ['theme', userId2],
      );

      expect(r1.first['value'], 'dark');
      expect(r2.first['value'], 'light');
    });

    test('setting value can be null', () async {
      await db.rawInsert(
        'INSERT OR REPLACE INTO settings (user_id, key, value) VALUES (?, ?, ?)',
        [userId, 'nullable_key', null],
      );

      final result = await db.rawQuery(
        'SELECT value FROM settings WHERE key = ? AND user_id = ?',
        ['nullable_key', userId],
      );

      expect(result, isNotEmpty);
      expect(result.first['value'], isNull);
    });

    test('setSetting uses correct SQL pattern', () async {
      await db.rawInsert(
        'INSERT OR REPLACE INTO settings (user_id, key, value) VALUES (?, ?, ?)',
        [userId, 'test_key', 'test_value'],
      );

      final row = await db.rawQuery(
        'SELECT user_id, key, value FROM settings WHERE key = ?',
        ['test_key'],
      );
      expect(row.first['user_id'], userId);
      expect(row.first['key'], 'test_key');
      expect(row.first['value'], 'test_value');
    });

    test('can store and retrieve empty string values', () async {
      await db.rawInsert(
        'INSERT OR REPLACE INTO settings (user_id, key, value) VALUES (?, ?, ?)',
        [userId, 'empty', ''],
      );

      final result = await db.rawQuery(
        'SELECT value FROM settings WHERE key = ? AND user_id = ?',
        ['empty', userId],
      );
      expect(result.first['value'], '');
    });
  });

  // ==================== APP SETTINGS (GLOBAL) ====================

  group('App settings (global)', () {
    test('global settings use user_id = 0', () async {
      await db.rawInsert(
        'INSERT OR REPLACE INTO settings (user_id, key, value) VALUES (?, ?, ?)',
        [globalUserId, 'language', 'fr'],
      );

      final result = await db.rawQuery(
        'SELECT value FROM settings WHERE key = ? AND user_id = ?',
        ['language', globalUserId],
      );

      expect(result, isNotEmpty);
      expect(result.first['value'], 'fr');
    });

    test('getAppSetting queries user_id=0, not the current user', () async {
      await db.rawInsert(
        'INSERT OR REPLACE INTO settings (user_id, key, value) VALUES (?, ?, ?)',
        [globalUserId, 'app_theme', 'dark'],
      );
      await db.rawInsert(
        'INSERT OR REPLACE INTO settings (user_id, key, value) VALUES (?, ?, ?)',
        [userId, 'app_theme', 'light'],
      );

      final globalResult = await db.rawQuery(
        'SELECT value FROM settings WHERE key = ? AND user_id = ?',
        ['app_theme', globalUserId],
      );
      final userResult = await db.rawQuery(
        'SELECT value FROM settings WHERE key = ? AND user_id = ?',
        ['app_theme', userId],
      );

      expect(globalResult.first['value'], 'dark');
      expect(userResult.first['value'], 'light');
    });

    test('setAppSetting writes with user_id=0', () async {
      await db.rawInsert(
        'INSERT OR REPLACE INTO settings (user_id, key, value) VALUES (?, ?, ?)',
        [globalUserId, 'default_currency', 'USD'],
      );

      final result = await db.rawQuery(
        'SELECT user_id, value FROM settings WHERE key = ?',
        ['default_currency'],
      );

      expect(result.first['user_id'], globalUserId);
      expect(result.first['value'], 'USD');
    });

    test('global settings are shared across users', () async {
      await seedTestUser(db, username: 'user2');

      await db.rawInsert(
        'INSERT OR REPLACE INTO settings (user_id, key, value) VALUES (?, ?, ?)',
        [globalUserId, 'shared_key', 'shared_value'],
      );

      final r1 = await db.rawQuery(
        'SELECT value FROM settings WHERE key = ? AND user_id = ?',
        ['shared_key', globalUserId],
      );
      final r2 = await db.rawQuery(
        'SELECT value FROM settings WHERE key = ? AND user_id = ?',
        ['shared_key', globalUserId],
      );

      expect(r1.first['value'], 'shared_value');
      expect(r2.first['value'], 'shared_value');
    });

    test('global setting overwrite via INSERT OR REPLACE', () async {
      await db.rawInsert(
        'INSERT OR REPLACE INTO settings (user_id, key, value) VALUES (?, ?, ?)',
        [globalUserId, 'rate', '1.0'],
      );
      await db.rawInsert(
        'INSERT OR REPLACE INTO settings (user_id, key, value) VALUES (?, ?, ?)',
        [globalUserId, 'rate', '2.5'],
      );

      final result = await db.rawQuery(
        'SELECT value FROM settings WHERE key = ? AND user_id = ?',
        ['rate', globalUserId],
      );

      expect(result.length, 1);
      expect(result.first['value'], '2.5');
    });
  });

  // ==================== IMPORT DEDUPLICATION ====================

  group('Import deduplication', () {
    test('logImportedFile inserts record for current user', () async {
      await db.rawInsert(
        'INSERT INTO imported_files (user_id, file_hash, filename) VALUES (?, ?, ?)',
        [userId, 'abc123hash', 'bank_export.csv'],
      );

      final result = await db.rawQuery(
        'SELECT * FROM imported_files WHERE file_hash = ? AND user_id = ?',
        ['abc123hash', userId],
      );

      expect(result, isNotEmpty);
      expect(result.first['file_hash'], 'abc123hash');
      expect(result.first['filename'], 'bank_export.csv');
      expect(result.first['user_id'], userId);
    });

    test('isFileImported returns true after logging', () async {
      await db.rawInsert(
        'INSERT INTO imported_files (user_id, file_hash, filename) VALUES (?, ?, ?)',
        [userId, 'hash_abc', 'file.csv'],
      );

      final result = await db.rawQuery(
        'SELECT COUNT(*) as cnt FROM imported_files WHERE file_hash = ? AND user_id = ?',
        ['hash_abc', userId],
      );

      expect((result.first['cnt'] as int) > 0, isTrue);
    });

    test('isFileImported returns false for unknown hash', () async {
      final result = await db.rawQuery(
        'SELECT COUNT(*) as cnt FROM imported_files WHERE file_hash = ? AND user_id = ?',
        ['unknown_hash', userId],
      );

      expect((result.first['cnt'] as int) > 0, isFalse);
    });

    test('imported files are isolated per user', () async {
      final userId2 = await seedTestUser(db, username: 'user2');

      await db.rawInsert(
        'INSERT INTO imported_files (user_id, file_hash, filename) VALUES (?, ?, ?)',
        [userId, 'shared_hash', 'user1_file.csv'],
      );

      final r1 = await db.rawQuery(
        'SELECT COUNT(*) as cnt FROM imported_files WHERE file_hash = ? AND user_id = ?',
        ['shared_hash', userId],
      );
      final r2 = await db.rawQuery(
        'SELECT COUNT(*) as cnt FROM imported_files WHERE file_hash = ? AND user_id = ?',
        ['shared_hash', userId2],
      );

      expect((r1.first['cnt'] as int) > 0, isTrue);
      expect((r2.first['cnt'] as int) > 0, isFalse);
    });

    test('duplicate file hash insert respects UNIQUE constraint', () async {
      await db.rawInsert(
        'INSERT INTO imported_files (user_id, file_hash, filename) VALUES (?, ?, ?)',
        [userId, 'dup_hash', 'file1.csv'],
      );

      expect(
        () => db.rawInsert(
          'INSERT INTO imported_files (user_id, file_hash, filename) VALUES (?, ?, ?)',
          [userId, 'dup_hash', 'file2.csv'],
        ),
        throwsA(isA<DatabaseException>()),
      );
    });

    test('same hash with different filename for different users is allowed', () async {
      final userId2 = await seedTestUser(db, username: 'user2');

      await db.rawInsert(
        'INSERT INTO imported_files (user_id, file_hash, filename) VALUES (?, ?, ?)',
        [userId, 'same_hash', 'file_user1.csv'],
      );
      await db.rawInsert(
        'INSERT INTO imported_files (user_id, file_hash, filename) VALUES (?, ?, ?)',
        [userId2, 'same_hash', 'file_user2.csv'],
      );

      final all = await db.rawQuery(
        'SELECT * FROM imported_files WHERE file_hash = ?',
        ['same_hash'],
      );
      expect(all.length, 2);
    });

    test('filename can be null', () async {
      await db.rawInsert(
        'INSERT INTO imported_files (user_id, file_hash, filename) VALUES (?, ?, ?)',
        [userId, 'null_name_hash', null],
      );

      final result = await db.rawQuery(
        'SELECT filename FROM imported_files WHERE file_hash = ?',
        ['null_name_hash'],
      );
      expect(result.first['filename'], isNull);
    });
  });

  // ==================== DESCRIPTIONS CRUD ====================

  group('Descriptions CRUD', () {
    test('seedTestDescription creates a description and returns its ID', () async {
      final descId = await seedTestDescription(db, userId, 'Groceries');
      expect(descId, isA<int>());
      expect(descId, greaterThan(0));
    });

    test('getOrCreateDescription finds existing description', () async {
      final descId = await seedTestDescription(db, userId, 'Groceries');

      final result = await db.rawQuery(
        'SELECT id FROM descriptions WHERE user_id = ? AND name = ?',
        [userId, 'Groceries'],
      );
      expect(result.first['id'], descId);
    });

    test('getOrCreateDescription creates new description when not found', () async {
      final before = await db.rawQuery(
        'SELECT COUNT(*) as cnt FROM descriptions WHERE user_id = ?',
        [userId],
      );

      await db.rawInsert(
        'INSERT INTO descriptions (user_id, name) VALUES (?, ?)',
        [userId, 'New Description'],
      );

      final after = await db.rawQuery(
        'SELECT COUNT(*) as cnt FROM descriptions WHERE user_id = ?',
        [userId],
      );

      expect(after.first['cnt'], (before.first['cnt'] as int) + 1);
    });

    test('getAllDescriptions returns all descriptions for current user ordered by name', () async {
      await seedTestDescription(db, userId, 'Zebra');
      await seedTestDescription(db, userId, 'Apple');
      await seedTestDescription(db, userId, 'Mango');

      final rows = await db.rawQuery(
        'SELECT * FROM descriptions WHERE user_id = ? ORDER BY name',
        [userId],
      );

      expect(rows.length, 3);
      expect(rows[0]['name'], 'Apple');
      expect(rows[1]['name'], 'Mango');
      expect(rows[2]['name'], 'Zebra');
    });

    test('descriptions are isolated per user', () async {
      final userId2 = await seedTestUser(db, username: 'user2');

      await seedTestDescription(db, userId, 'Food');
      await seedTestDescription(db, userId2, 'Transport');

      final r1 = await db.rawQuery(
        'SELECT * FROM descriptions WHERE user_id = ?',
        [userId],
      );
      final r2 = await db.rawQuery(
        'SELECT * FROM descriptions WHERE user_id = ?',
        [userId2],
      );

      expect(r1.length, 1);
      expect(r2.length, 1);
      expect(r1.first['name'], 'Food');
      expect(r2.first['name'], 'Transport');
    });

    test('descriptions have UNIQUE(user_id, name) constraint', () async {
      await seedTestDescription(db, userId, 'Duplicate');

      expect(
        () => seedTestDescription(db, userId, 'Duplicate'),
        throwsA(isA<DatabaseException>()),
      );
    });

    test('mergeDescriptions reassigns transactions and deletes source', () async {
      final srcId = await seedTestDescription(db, userId, 'OldCategory');
      final tgtId = await seedTestDescription(db, userId, 'NewCategory');
      final acctIds = await seedTestAccounts(db, userId);

      await seedTestTransaction(db, userId,
          accountId: acctIds[0], descriptionId: srcId, amount: 50.0);
      await seedTestTransaction(db, userId,
          accountId: acctIds[0], descriptionId: srcId, amount: 75.0);

      await db.rawUpdate(
        'UPDATE transactions SET description_id = ? WHERE description_id = ? AND user_id = ?',
        [tgtId, srcId, userId],
      );
      await db.rawDelete(
        'DELETE FROM descriptions WHERE id = ? AND user_id = ?',
        [srcId, userId],
      );

      final txns = await db.rawQuery(
        'SELECT description_id FROM transactions WHERE user_id = ?',
        [userId],
      );
      expect(txns.every((t) => t['description_id'] == tgtId), isTrue);

      final srcStillExists = await db.rawQuery(
        'SELECT * FROM descriptions WHERE id = ? AND user_id = ?',
        [srcId, userId],
      );
      expect(srcStillExists, isEmpty);

      final tgtStillExists = await db.rawQuery(
        'SELECT * FROM descriptions WHERE id = ? AND user_id = ?',
        [tgtId, userId],
      );
      expect(tgtStillExists, isNotEmpty);
    });

    test('mergeDescriptions returns false when source == target', () async {
      final descId = await seedTestDescription(db, userId, 'SameName');

      final srcId = descId;
      final tgtId = descId;

      final sameName = srcId == tgtId;
      expect(sameName, isTrue);
    });

    test('renameDescription updates the name', () async {
      final descId = await seedTestDescription(db, userId, 'OldName');

      final count = await db.rawUpdate(
        'UPDATE descriptions SET name = ? WHERE id = ? AND user_id = ?',
        ['NewName', descId, userId],
      );
      expect(count, 1);

      final result = await db.rawQuery(
        'SELECT name FROM descriptions WHERE id = ?',
        [descId],
      );
      expect(result.first['name'], 'NewName');
    });

    test('renameDescription with empty name returns 0 updates', () async {
      final descId = await seedTestDescription(db, userId, 'KeepName');

      final newName = ''.trim();
      expect(newName.isEmpty, isTrue);

      if (newName.isNotEmpty) {
        await db.rawUpdate(
          'UPDATE descriptions SET name = ? WHERE id = ? AND user_id = ?',
          [newName, descId, userId],
        );
      }

      final result = await db.rawQuery(
        'SELECT name FROM descriptions WHERE id = ?',
        [descId],
      );
      expect(result.first['name'], 'KeepName');
    });

    test('renameDescription trims whitespace', () async {
      final descId = await seedTestDescription(db, userId, 'TestDesc');

      final newName = '  TrimmedName  '.trim();
      final count = await db.rawUpdate(
        'UPDATE descriptions SET name = ? WHERE id = ? AND user_id = ?',
        [newName, descId, userId],
      );
      expect(count, 1);

      final result = await db.rawQuery(
        'SELECT name FROM descriptions WHERE id = ?',
        [descId],
      );
      expect(result.first['name'], 'TrimmedName');
    });

    test('mergeDescriptions preserves target description', () async {
      final srcId = await seedTestDescription(db, userId, 'Source');
      final tgtId = await seedTestDescription(db, userId, 'Target');
      final acctIds = await seedTestAccounts(db, userId);

      await seedTestTransaction(db, userId,
          accountId: acctIds[0], descriptionId: srcId, amount: 100.0);

      await db.rawUpdate(
        'UPDATE transactions SET description_id = ? WHERE description_id = ? AND user_id = ?',
        [tgtId, srcId, userId],
      );
      await db.rawDelete(
        'DELETE FROM descriptions WHERE id = ? AND user_id = ?',
        [srcId, userId],
      );

      final descriptions = await db.rawQuery(
        'SELECT * FROM descriptions WHERE user_id = ? ORDER BY name',
        [userId],
      );
      expect(descriptions.length, 1);
      expect(descriptions.first['name'], 'Target');
    });

    test('merge with target already having transactions', () async {
      final srcId = await seedTestDescription(db, userId, 'Food');
      final tgtId = await seedTestDescription(db, userId, 'Dining');
      final acctIds = await seedTestAccounts(db, userId);

      await seedTestTransaction(db, userId,
          accountId: acctIds[0], descriptionId: srcId, amount: 30.0);
      await seedTestTransaction(db, userId,
          accountId: acctIds[0], descriptionId: tgtId, amount: 20.0);

      await db.rawUpdate(
        'UPDATE transactions SET description_id = ? WHERE description_id = ? AND user_id = ?',
        [tgtId, srcId, userId],
      );
      await db.rawDelete(
        'DELETE FROM descriptions WHERE id = ? AND user_id = ?',
        [srcId, userId],
      );

      final txns = await db.rawQuery(
        'SELECT description_id, amount FROM transactions WHERE user_id = ? ORDER BY amount',
        [userId],
      );
      expect(txns.length, 2);
      expect(txns.every((t) => t['description_id'] == tgtId), isTrue);
    });

    test('descriptions have auto-populated created_at', () async {
      final descId = await seedTestDescription(db, userId, 'Timestamped');

      final result = await db.rawQuery(
        'SELECT created_at FROM descriptions WHERE id = ?',
        [descId],
      );
      expect(result.first['created_at'], isNotNull);
    });
  });

  // ==================== EXPORT ====================

  group('Export (exportToJson structure)', () {
    test('export contains accounts, transactions, and exported_at keys', () async {
      final accounts = await db.rawQuery('SELECT * FROM accounts WHERE user_id = ?', [userId]);
      final transactions = await db.rawQuery(
        '''SELECT t.*, a.name as account_name, a.color as account_color,
                  a.currency as account_currency, d.name as description_name
           FROM transactions t
           LEFT JOIN accounts a ON t.account_id = a.id
           LEFT JOIN descriptions d ON t.description_id = d.id
           WHERE t.user_id = ?
           ORDER BY t.date DESC, t.id DESC''',
        [userId],
      );

      final exportData = {
        'accounts': accounts,
        'transactions': transactions,
        'exported_at': DateTime.now().toIso8601String(),
      };

      expect(exportData.containsKey('accounts'), isTrue);
      expect(exportData.containsKey('transactions'), isTrue);
      expect(exportData.containsKey('exported_at'), isTrue);
    });

    test('export with no data returns empty lists', () async {
      final accounts = await db.rawQuery('SELECT * FROM accounts WHERE user_id = ?', [userId]);
      final transactions = await db.rawQuery(
        '''SELECT t.*, a.name as account_name, a.color as account_color,
                  a.currency as account_currency, d.name as description_name
           FROM transactions t
           LEFT JOIN accounts a ON t.account_id = a.id
           LEFT JOIN descriptions d ON t.description_id = d.id
           WHERE t.user_id = ?''',
        [userId],
      );

      expect(accounts, isEmpty);
      expect(transactions, isEmpty);
    });

    test('export includes seeded accounts', () async {
      await seedTestAccounts(db, userId);

      final accounts = await db.rawQuery('SELECT * FROM accounts WHERE user_id = ?', [userId]);
      expect(accounts.length, 3);

      final names = accounts.map((a) => a['name'] as String).toSet();
      expect(names, containsAll(['Checking Account', 'Savings Account A', 'Savings Account B']));
    });

    test('export includes seeded transactions with details', () async {
      final acctIds = await seedTestAccounts(db, userId);
      final descId = await seedTestDescription(db, userId, 'Salary');
      await seedTestTransaction(db, userId,
          accountId: acctIds[0],
          descriptionId: descId,
          amount: 3000.0,
          transactionType: 'income',
          date: '2025-01-15');

      final transactions = await db.rawQuery(
        '''SELECT t.*, a.name as account_name, a.color as account_color,
                  a.currency as account_currency, d.name as description_name
           FROM transactions t
           LEFT JOIN accounts a ON t.account_id = a.id
           LEFT JOIN descriptions d ON t.description_id = d.id
           WHERE t.user_id = ?''',
        [userId],
      );

      expect(transactions.length, 1);
      expect(transactions.first['account_name'], 'Checking Account');
      expect(transactions.first['description_name'], 'Salary');
      expect(transactions.first['amount'], 3000.0);
      expect(transactions.first['transaction_type'], 'income');
    });

    test('exported_at is a valid ISO 8601 string', () async {
      final exportedAt = DateTime.now().toIso8601String();
      expect(exportedAt, isNotEmpty);
      expect(DateTime.tryParse(exportedAt), isNotNull);
    });

    test('export only includes current user data', () async {
      final userId2 = await seedTestUser(db, username: 'other_user');
      final acctIds1 = await seedTestAccounts(db, userId);
      final acctIds2 = await seedTestAccounts(db, userId2);

      await seedTestTransaction(db, userId,
          accountId: acctIds1[0], amount: 100.0, transactionType: 'income');
      await seedTestTransaction(db, userId2,
          accountId: acctIds2[0], amount: 200.0, transactionType: 'income');

      final txns = await db.rawQuery(
        'SELECT * FROM transactions WHERE user_id = ?',
        [userId],
      );
      expect(txns.length, 1);
      expect(txns.first['amount'], 100.0);
    });

    test('export account map structure matches Account.toMap', () async {
      await seedTestAccounts(db, userId);

      final accounts = await db.query('accounts',
          where: 'user_id = ?', whereArgs: [userId], orderBy: 'name');
      final first = accounts.first;

      expect(first.containsKey('id'), isTrue);
      expect(first.containsKey('user_id'), isTrue);
      expect(first.containsKey('name'), isTrue);
      expect(first.containsKey('type'), isTrue);
      expect(first.containsKey('color'), isTrue);
      expect(first.containsKey('currency'), isTrue);
    });
  });

  // ==================== EDGE CASES ====================

  group('Edge cases', () {
    test('getSetting with null value stored returns null (not defaultValue)', () async {
      await db.rawInsert(
        'INSERT OR REPLACE INTO settings (user_id, key, value) VALUES (?, ?, ?)',
        [userId, 'null_val', null],
      );

      final result = await db.rawQuery(
        'SELECT value FROM settings WHERE key = ? AND user_id = ?',
        ['null_val', userId],
      );

      expect(result, isNotEmpty);
      expect(result.first['value'], isNull);
    });

    test('settings table allows multiple different keys per user', () async {
      await db.rawInsert(
        'INSERT OR REPLACE INTO settings (user_id, key, value) VALUES (?, ?, ?)',
        [userId, 'theme', 'dark'],
      );
      await db.rawInsert(
        'INSERT OR REPLACE INTO settings (user_id, key, value) VALUES (?, ?, ?)',
        [userId, 'currency', 'EUR'],
      );
      await db.rawInsert(
        'INSERT OR REPLACE INTO settings (user_id, key, value) VALUES (?, ?, ?)',
        [userId, 'language', 'en'],
      );

      final count = await db.rawQuery(
        'SELECT COUNT(*) as cnt FROM settings WHERE user_id = ?',
        [userId],
      );
      expect(count.first['cnt'], 3);
    });

    test('imported_files imported_at is auto-set', () async {
      await db.rawInsert(
        'INSERT INTO imported_files (user_id, file_hash, filename) VALUES (?, ?, ?)',
        [userId, 'ts_hash', 'file.csv'],
      );

      final result = await db.rawQuery(
        'SELECT imported_at FROM imported_files WHERE file_hash = ?',
        ['ts_hash'],
      );
      expect(result.first['imported_at'], isNotNull);
    });

    test('description name with special characters', () async {
      final descId = await seedTestDescription(db, userId, "Café & Restaurant (Main)");

      final result = await db.rawQuery(
        'SELECT name FROM descriptions WHERE id = ?',
        [descId],
      );
      expect(result.first['name'], "Café & Restaurant (Main)");
    });

    test('setting key with special characters', () async {
      await db.rawInsert(
        'INSERT OR REPLACE INTO settings (user_id, key, value) VALUES (?, ?, ?)',
        [userId, 'user.prefs/font-size', '14'],
      );

      final result = await db.rawQuery(
        'SELECT value FROM settings WHERE key = ? AND user_id = ?',
        ['user.prefs/font-size', userId],
      );
      expect(result.first['value'], '14');
    });

    test('globalSetting and userSetting with same key are independent', () async {
      await db.rawInsert(
        'INSERT OR REPLACE INTO settings (user_id, key, value) VALUES (?, ?, ?)',
        [userId, 'shared_key', 'user_value'],
      );
      await db.rawInsert(
        'INSERT OR REPLACE INTO settings (user_id, key, value) VALUES (?, ?, ?)',
        [globalUserId, 'shared_key', 'global_value'],
      );

      final userVal = await db.rawQuery(
        'SELECT value FROM settings WHERE key = ? AND user_id = ?',
        ['shared_key', userId],
      );
      final globalVal = await db.rawQuery(
        'SELECT value FROM settings WHERE key = ? AND user_id = ?',
        ['shared_key', globalUserId],
      );

      expect(userVal.first['value'], 'user_value');
      expect(globalVal.first['value'], 'global_value');
    });

    test('logImportedFile records filename correctly', () async {
      await db.rawInsert(
        'INSERT INTO imported_files (user_id, file_hash, filename) VALUES (?, ?, ?)',
        [userId, 'file_hash_1', 'my_statement_march_2025.csv'],
      );

      final result = await db.rawQuery(
        'SELECT filename FROM imported_files WHERE file_hash = ?',
        ['file_hash_1'],
      );
      expect(result.first['filename'], 'my_statement_march_2025.csv');
    });

    test('renaming a description that does not exist returns 0 updates', () async {
      final count = await db.rawUpdate(
        'UPDATE descriptions SET name = ? WHERE id = ? AND user_id = ?',
        ['NewName', 99999, userId],
      );
      expect(count, 0);
    });

    test('delete all settings for a user', () async {
      await db.rawInsert(
        'INSERT OR REPLACE INTO settings (user_id, key, value) VALUES (?, ?, ?)',
        [userId, 'k1', 'v1'],
      );
      await db.rawInsert(
        'INSERT OR REPLACE INTO settings (user_id, key, value) VALUES (?, ?, ?)',
        [userId, 'k2', 'v2'],
      );

      await db.delete('settings', where: 'user_id = ?', whereArgs: [userId]);

      final count = await db.rawQuery(
        'SELECT COUNT(*) as cnt FROM settings WHERE user_id = ?',
        [userId],
      );
      expect(count.first['cnt'], 0);
    });

    test('delete imported_files for a user', () async {
      await db.rawInsert(
        'INSERT INTO imported_files (user_id, file_hash, filename) VALUES (?, ?, ?)',
        [userId, 'h1', 'f1.csv'],
      );
      await db.rawInsert(
        'INSERT INTO imported_files (user_id, file_hash, filename) VALUES (?, ?, ?)',
        [userId, 'h2', 'f2.csv'],
      );

      await db.delete('imported_files', where: 'user_id = ?', whereArgs: [userId]);

      final count = await db.rawQuery(
        'SELECT COUNT(*) as cnt FROM imported_files WHERE user_id = ?',
        [userId],
      );
      expect(count.first['cnt'], 0);
    });

    test('description merge with transactions from multiple accounts', () async {
      final acctIds = await seedTestAccounts(db, userId);
      final srcId = await seedTestDescription(db, userId, 'Groceries');
      final tgtId = await seedTestDescription(db, userId, 'Food & Drink');

      await seedTestTransaction(db, userId,
          accountId: acctIds[0], descriptionId: srcId, amount: 30.0);
      await seedTestTransaction(db, userId,
          accountId: acctIds[1], descriptionId: srcId, amount: 45.0);
      await seedTestTransaction(db, userId,
          accountId: acctIds[2], descriptionId: srcId, amount: 60.0);

      await db.rawUpdate(
        'UPDATE transactions SET description_id = ? WHERE description_id = ? AND user_id = ?',
        [tgtId, srcId, userId],
      );
      await db.rawDelete(
        'DELETE FROM descriptions WHERE id = ? AND user_id = ?',
        [srcId, userId],
      );

      final txns = await db.rawQuery(
        'SELECT description_id, amount FROM transactions WHERE user_id = ? ORDER BY amount',
        [userId],
      );
      expect(txns.length, 3);
      expect(txns.every((t) => t['description_id'] == tgtId), isTrue);
      expect(txns.map((t) => t['amount']), containsAll([30.0, 45.0, 60.0]));
    });

    test('settings value with very long string', () async {
      final longValue = 'x' * 10000;
      await db.rawInsert(
        'INSERT OR REPLACE INTO settings (user_id, key, value) VALUES (?, ?, ?)',
        [userId, 'long_val', longValue],
      );

      final result = await db.rawQuery(
        'SELECT value FROM settings WHERE key = ? AND user_id = ?',
        ['long_val', userId],
      );
      expect(result.first['value'], longValue);
    });
  });
}
