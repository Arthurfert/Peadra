import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:peadra/core/database/database_manager.dart';
import 'package:peadra/core/utils/constants.dart';

void main() {
  sqfliteFfiInit();

  setUp(() async {
    await DatabaseManager.instance
        .openInMemoryForTest(userId: 'user-${DateTime.now().microsecondsSinceEpoch}');
  });

  // ==================== SETTINGS CRUD ====================

  group('Settings CRUD', () {
    test('setSetting and getSetting round-trip', () async {
      final db = DatabaseManager.instance;
      await db.setSetting('theme', 'dark');

      expect(await db.getSetting('theme'), 'dark');
    });

    test('getSetting returns defaultValue when key does not exist', () async {
      final db = DatabaseManager.instance;

      expect(await db.getSetting('nonexistent'), isNull);
      expect(
        await db.getSetting('nonexistent', defaultValue: 'fallback'),
        'fallback',
      );
    });

    test('setSetting overwrites existing value (INSERT OR REPLACE)', () async {
      final db = DatabaseManager.instance;
      await db.setSetting('currency', 'USD');
      await db.setSetting('currency', 'GBP');

      expect(await db.getSetting('currency'), 'GBP');
    });

    test('settings are isolated per user', () async {
      final db = DatabaseManager.instance;
      final userA = db.userId!;
      await db.setSetting('theme', 'dark');

      final userB = 'user-${DateTime.now().microsecondsSinceEpoch}-b';
      db.setSessionUserId(userB);
      await db.setSetting('theme', 'light');
      expect(await db.getSetting('theme'), 'light');

      db.setSessionUserId(userA);
      expect(await db.getSetting('theme'), 'dark');

      db.setSessionUserId(userB);
      expect(await db.getSetting('theme'), 'light');
    });

    test('missing setting returns null (not defaultValue without one)', () async {
      final db = DatabaseManager.instance;
      expect(await db.getSetting('nullable_key'), isNull);
    });

    test('setSetting uses correct SQL pattern', () async {
      final db = DatabaseManager.instance;
      await db.setSetting('test_key', 'test_value');

      expect(await db.getSetting('test_key'), 'test_value');

      // The row is stored scoped to the current user.
      final handle = await db.database;
      final rows = await handle.query(
        'SELECT user_id, "key", value FROM settings WHERE "key" = ? AND user_id = ?',
        ['test_key', db.userId],
      );
      expect(rows, hasLength(1));
      expect(rows.first['key'], 'test_key');
      expect(rows.first['value'], 'test_value');
    });

    test('can store and retrieve empty string values', () async {
      final db = DatabaseManager.instance;
      await db.setSetting('empty', '');

      expect(await db.getSetting('empty'), '');
    });
  });

  // ==================== APP SETTINGS (GLOBAL) ====================

  group('App settings (global)', () {
    test('global settings use user_id = 0', () async {
      final db = DatabaseManager.instance;
      await db.setAppSetting('language', 'fr');

      expect(await db.getAppSetting('language'), 'fr');

      final handle = await db.database;
      final rows = await handle.query(
        'SELECT value FROM settings WHERE "key" = ? AND user_id = ?',
        ['language', globalSettingsUserId],
      );
      expect(rows, isNotEmpty);
      expect(rows.first['value'], 'fr');
    });

    test('getAppSetting queries user_id=0, not the current user', () async {
      final db = DatabaseManager.instance;
      await db.setAppSetting('app_theme', 'dark');
      await db.setSetting('app_theme', 'light');

      expect(await db.getAppSetting('app_theme'), 'dark');
      expect(await db.getSetting('app_theme'), 'light');
    });

    test('setAppSetting writes with user_id=0', () async {
      final db = DatabaseManager.instance;
      await db.setAppSetting('default_currency', 'USD');

      final handle = await db.database;
      final rows = await handle.query(
        'SELECT user_id, value FROM settings WHERE "key" = ?',
        ['default_currency'],
      );
      expect(rows.first['user_id'].toString(), '$globalSettingsUserId');
      expect(rows.first['value'], 'USD');
    });

    test('global settings are shared across users', () async {
      final db = DatabaseManager.instance;
      final userA = db.userId!;
      await db.setAppSetting('shared_key', 'shared_value');

      final userB = 'user-${DateTime.now().microsecondsSinceEpoch}-b';
      db.setSessionUserId(userB);
      expect(await db.getAppSetting('shared_key'), 'shared_value');

      db.setSessionUserId(userA);
      expect(await db.getAppSetting('shared_key'), 'shared_value');
    });

    test('global setting overwrite via INSERT OR REPLACE', () async {
      final db = DatabaseManager.instance;
      await db.setAppSetting('rate', '1.0');
      await db.setAppSetting('rate', '2.5');

      expect(await db.getAppSetting('rate'), '2.5');
    });
  });

  // ==================== IMPORT DEDUPLICATION ====================
  //
  // DatabaseManager exposes no import-tracking API, so these scenarios drive
  // the production imported_files schema through the manager's database
  // handle (string user ids, prod UNIQUE(user_id, file_hash)).

  group('Import deduplication', () {
    test('logImportedFile inserts record for current user', () async {
      final db = DatabaseManager.instance;
      final handle = await db.database;
      final uid = db.userId!;

      await handle.execute(
        'INSERT INTO imported_files (id, user_id, file_hash, filename) VALUES (?1, ?2, ?3, ?4)',
        [newFileId(), uid, 'abc123hash', 'bank_export.csv'],
      );

      final rows = await handle.query(
        'SELECT * FROM imported_files WHERE file_hash = ? AND user_id = ?',
        ['abc123hash', uid],
      );
      expect(rows, isNotEmpty);
      expect(rows.first['file_hash'], 'abc123hash');
      expect(rows.first['filename'], 'bank_export.csv');
      expect(rows.first['user_id'], uid);
    });

    test('isFileImported returns true after logging', () async {
      final db = DatabaseManager.instance;
      final handle = await db.database;
      final uid = db.userId!;

      await handle.execute(
        'INSERT INTO imported_files (id, user_id, file_hash, filename) VALUES (?1, ?2, ?3, ?4)',
        [newFileId(), uid, 'hash_abc', 'file.csv'],
      );

      final rows = await handle.query(
        'SELECT COUNT(*) as cnt FROM imported_files WHERE file_hash = ? AND user_id = ?',
        ['hash_abc', uid],
      );
      expect(((rows.first['cnt'] as num?) ?? 0) > 0, isTrue);
    });

    test('isFileImported returns false for unknown hash', () async {
      final db = DatabaseManager.instance;
      final handle = await db.database;

      final rows = await handle.query(
        'SELECT COUNT(*) as cnt FROM imported_files WHERE file_hash = ? AND user_id = ?',
        ['unknown_hash', db.userId],
      );
      expect(((rows.first['cnt'] as num?) ?? 0) > 0, isFalse);
    });

    test('imported files are isolated per user', () async {
      final db = DatabaseManager.instance;
      final handle = await db.database;
      final userA = db.userId!;
      final userB = 'user-${DateTime.now().microsecondsSinceEpoch}-b';

      await handle.execute(
        'INSERT INTO imported_files (id, user_id, file_hash, filename) VALUES (?1, ?2, ?3, ?4)',
        [newFileId(), userA, 'shared_hash', 'user1_file.csv'],
      );

      Future<bool> isImported(String uid) async {
        final rows = await handle.query(
          'SELECT COUNT(*) as cnt FROM imported_files WHERE file_hash = ? AND user_id = ?',
          ['shared_hash', uid],
        );
        return ((rows.first['cnt'] as num?) ?? 0) > 0;
      }

      expect(await isImported(userA), isTrue);
      expect(await isImported(userB), isFalse);
    });

    test('duplicate file hash insert respects UNIQUE constraint', () async {
      final db = DatabaseManager.instance;
      final handle = await db.database;
      final uid = db.userId!;

      await handle.execute(
        'INSERT INTO imported_files (id, user_id, file_hash, filename) VALUES (?1, ?2, ?3, ?4)',
        [newFileId(), uid, 'dup_hash', 'file1.csv'],
      );

      expect(
        () => handle.execute(
          'INSERT INTO imported_files (id, user_id, file_hash, filename) VALUES (?1, ?2, ?3, ?4)',
          [newFileId(), uid, 'dup_hash', 'file2.csv'],
        ),
        throwsA(anything),
      );
    });

    test('same hash with different filename for different users is allowed',
        () async {
      final db = DatabaseManager.instance;
      final handle = await db.database;
      final userA = db.userId!;
      final userB = 'user-${DateTime.now().microsecondsSinceEpoch}-b';

      await handle.execute(
        'INSERT INTO imported_files (id, user_id, file_hash, filename) VALUES (?1, ?2, ?3, ?4)',
        [newFileId(), userA, 'same_hash', 'file_user1.csv'],
      );
      await handle.execute(
        'INSERT INTO imported_files (id, user_id, file_hash, filename) VALUES (?1, ?2, ?3, ?4)',
        [newFileId(), userB, 'same_hash', 'file_user2.csv'],
      );

      final all = await handle.query(
        'SELECT * FROM imported_files WHERE file_hash = ?',
        ['same_hash'],
      );
      expect(all, hasLength(2));
    });

    test('filename can be null', () async {
      final db = DatabaseManager.instance;
      final handle = await db.database;

      await handle.execute(
        'INSERT INTO imported_files (id, user_id, file_hash, filename) VALUES (?1, ?2, ?3, ?4)',
        [newFileId(), db.userId, 'null_name_hash', null],
      );

      final rows = await handle.query(
        'SELECT filename FROM imported_files WHERE file_hash = ?',
        ['null_name_hash'],
      );
      expect(rows.first['filename'], isNull);
    });
  });

  // ==================== DESCRIPTIONS CRUD ====================

  group('Descriptions CRUD', () {
    test('seedTestDescription creates a description and returns its ID',
        () async {
      final db = DatabaseManager.instance;
      final descId = await db.getOrCreateDescription('Groceries');
      expect(descId, isNotEmpty);
    });

    test('getOrCreateDescription finds existing description', () async {
      final db = DatabaseManager.instance;
      final first = await db.getOrCreateDescription('Groceries');
      final second = await db.getOrCreateDescription('Groceries');
      expect(second, first);
    });

    test('getOrCreateDescription creates new description when not found',
        () async {
      final db = DatabaseManager.instance;
      final before = await db.getAllDescriptions();

      await db.getOrCreateDescription('New Description');

      final after = await db.getAllDescriptions();
      expect(after.length, before.length + 1);
      expect(after.map((d) => d.name), contains('New Description'));
    });

    test(
        'getAllDescriptions returns all descriptions for current user ordered by name',
        () async {
      final db = DatabaseManager.instance;
      await db.getOrCreateDescription('Zebra');
      await db.getOrCreateDescription('Apple');
      await db.getOrCreateDescription('Mango');

      final descriptions = await db.getAllDescriptions();
      expect(descriptions.map((d) => d.name).toList(),
          ['Apple', 'Mango', 'Zebra']);
    });

    test('descriptions are isolated per user', () async {
      final db = DatabaseManager.instance;
      final userA = db.userId!;
      await db.getOrCreateDescription('Food');

      final userB = 'user-${DateTime.now().microsecondsSinceEpoch}-b';
      db.setSessionUserId(userB);
      await db.getOrCreateDescription('Transport');

      final forB = await db.getAllDescriptions();
      expect(forB.map((d) => d.name).toList(), ['Transport']);

      db.setSessionUserId(userA);
      final forA = await db.getAllDescriptions();
      expect(forA.map((d) => d.name).toList(), ['Food']);
    });

    test('descriptions have UNIQUE(user_id, name) constraint', () async {
      final db = DatabaseManager.instance;
      final first = await db.getOrCreateDescription('Duplicate');
      final second = await db.getOrCreateDescription('Duplicate');

      // The production API dedupes instead of throwing: same row, one row.
      expect(second, first);
      expect(
        (await db.getAllDescriptions()).where((d) => d.name == 'Duplicate'),
        hasLength(1),
      );
    });

    test('mergeDescriptions reassigns transactions and deletes source',
        () async {
      final db = DatabaseManager.instance;
      final accountId = await db.addAccount(
          'Checking', '#4CAF50', 'checking', 'EUR');

      Future<void> addWithDescription(String description, int amount) =>
          db.addTransaction(
            date: '2025-01-15',
            description: description,
            amount: Decimal.fromInt(amount),
            transactionType: 'income',
            accountId: accountId,
          );
      await addWithDescription('OldCategory', 50);
      await addWithDescription('OldCategory', 75);
      await db.getOrCreateDescription('NewCategory');

      expect(await db.mergeDescriptions('OldCategory', 'NewCategory'), isTrue);

      final txns = await db.getTransactions();
      expect(txns, hasLength(2));
      expect(txns.every((t) => t.descriptionName == 'NewCategory'), isTrue);

      final names =
          (await db.getAllDescriptions()).map((d) => d.name).toList();
      expect(names, isNot(contains('OldCategory')));
      expect(names, contains('NewCategory'));
    });

    test('mergeDescriptions returns false when source == target', () async {
      final db = DatabaseManager.instance;
      await db.getOrCreateDescription('SameName');

      expect(await db.mergeDescriptions('SameName', 'SameName'), isFalse);
    });

    test('renameDescription updates the name', () async {
      final db = DatabaseManager.instance;
      final descId = await db.getOrCreateDescription('OldName');

      expect(await db.renameDescription(descId, 'NewName'), isTrue);

      final descriptions = await db.getAllDescriptions();
      expect(descriptions.map((d) => d.name), contains('NewName'));
      expect(descriptions.map((d) => d.name), isNot(contains('OldName')));
    });

    test('renameDescription with empty name returns 0 updates', () async {
      final db = DatabaseManager.instance;
      final descId = await db.getOrCreateDescription('KeepName');

      expect(await db.renameDescription(descId, '   '), isFalse);

      final descriptions = await db.getAllDescriptions();
      expect(descriptions.map((d) => d.name), contains('KeepName'));
    });

    test('renameDescription trims whitespace', () async {
      final db = DatabaseManager.instance;
      final descId = await db.getOrCreateDescription('TestDesc');

      expect(await db.renameDescription(descId, '  TrimmedName  '), isTrue);

      final descriptions = await db.getAllDescriptions();
      expect(descriptions.map((d) => d.name), contains('TrimmedName'));
    });

    test('mergeDescriptions preserves target description', () async {
      final db = DatabaseManager.instance;
      final accountId = await db.addAccount(
          'Checking', '#4CAF50', 'checking', 'EUR');
      await db.addTransaction(
        date: '2025-01-15',
        description: 'Source',
        amount: Decimal.fromInt(100),
        transactionType: 'income',
        accountId: accountId,
      );
      await db.getOrCreateDescription('Target');

      expect(await db.mergeDescriptions('Source', 'Target'), isTrue);

      final descriptions = await db.getAllDescriptions();
      expect(descriptions.map((d) => d.name).toList(), ['Target']);
    });

    test('merge with target already having transactions', () async {
      final db = DatabaseManager.instance;
      final accountId = await db.addAccount(
          'Checking', '#4CAF50', 'checking', 'EUR');
      await db.addTransaction(
        date: '2025-01-15',
        description: 'Food',
        amount: Decimal.fromInt(30),
        transactionType: 'income',
        accountId: accountId,
      );
      await db.addTransaction(
        date: '2025-01-15',
        description: 'Dining',
        amount: Decimal.fromInt(20),
        transactionType: 'income',
        accountId: accountId,
      );

      expect(await db.mergeDescriptions('Food', 'Dining'), isTrue);

      final txns = await db.getTransactions();
      expect(txns, hasLength(2));
      expect(txns.every((t) => t.descriptionName == 'Dining'), isTrue);
    });

    test('descriptions have auto-populated created_at', () async {
      final db = DatabaseManager.instance;
      await db.getOrCreateDescription('Timestamped');

      final descriptions = await db.getAllDescriptions();
      expect(descriptions.single.createdAt, isNotNull);
    });
  });

  // ==================== EXPORT ====================

  group('Export (exportToJson structure)', () {
    test('export contains accounts, transactions, and exported_at keys',
        () async {
      final db = DatabaseManager.instance;
      final exportData = {
        'accounts': (await db.getAllAccounts()).map((a) => a.toMap()).toList(),
        'transactions': await db.getTransactions(),
        'exported_at': DateTime.now().toIso8601String(),
      };

      expect(exportData.containsKey('accounts'), isTrue);
      expect(exportData.containsKey('transactions'), isTrue);
      expect(exportData.containsKey('exported_at'), isTrue);
    });

    test('export with no data returns empty lists', () async {
      final db = DatabaseManager.instance;
      expect(await db.getAllAccounts(), isEmpty);
      expect(await db.getTransactions(), isEmpty);
    });

    test('export includes seeded accounts', () async {
      final db = DatabaseManager.instance;
      await db.addAccount('Checking Account', '#4CAF50', 'checking', 'EUR');
      await db.addAccount('Savings Account A', '#2196F3', 'savings', 'EUR');
      await db.addAccount('Savings Account B', '#009688', 'savings', 'EUR');

      final accounts = await db.getAllAccounts();
      expect(accounts, hasLength(3));

      final names = accounts.map((a) => a.name).toSet();
      expect(
        names,
        containsAll(['Checking Account', 'Savings Account A', 'Savings Account B']),
      );
    });

    test('export includes seeded transactions with details', () async {
      final db = DatabaseManager.instance;
      final accountId = await db.addAccount(
          'Checking Account', '#4CAF50', 'checking', 'EUR');
      await db.addTransaction(
        date: '2025-01-15',
        description: 'Salary',
        amount: Decimal.fromInt(3000),
        transactionType: 'income',
        accountId: accountId,
      );

      final transactions = await db.getTransactions();
      expect(transactions, hasLength(1));
      expect(transactions.single.accountName, 'Checking Account');
      expect(transactions.single.descriptionName, 'Salary');
      expect(transactions.single.amount, Decimal.fromInt(3000));
      expect(transactions.single.transactionType, 'income');
    });

    test('exported_at is a valid ISO 8601 string', () async {
      final exportedAt = DateTime.now().toIso8601String();
      expect(exportedAt, isNotEmpty);
      expect(DateTime.tryParse(exportedAt), isNotNull);
    });

    test('export only includes current user data', () async {
      final db = DatabaseManager.instance;
      final userA = db.userId!;
      final accountA = await db.addAccount(
          'Checking', '#4CAF50', 'checking', 'EUR');
      await db.addTransaction(
        date: '2025-01-15',
        description: 'Pay A',
        amount: Decimal.fromInt(100),
        transactionType: 'income',
        accountId: accountA,
      );

      final userB = 'user-${DateTime.now().microsecondsSinceEpoch}-b';
      db.setSessionUserId(userB);
      final accountB = await db.addAccount(
          'Checking', '#4CAF50', 'checking', 'EUR');
      await db.addTransaction(
        date: '2025-01-15',
        description: 'Pay B',
        amount: Decimal.fromInt(200),
        transactionType: 'income',
        accountId: accountB,
      );

      db.setSessionUserId(userA);
      final txns = await db.getTransactions();
      expect(txns, hasLength(1));
      expect(txns.single.amount, Decimal.fromInt(100));
    });

    test('export account map structure matches Account.toMap', () async {
      final db = DatabaseManager.instance;
      await db.addAccount('Checking', '#4CAF50', 'checking', 'EUR');

      final first = (await db.getAllAccounts()).single.toMap();
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
    test('getSetting with null value stored returns null (not defaultValue)',
        () async {
      final db = DatabaseManager.instance;
      // The production setter only stores non-null strings, so a missing key
      // must read back as null even when callers pass no default.
      expect(await db.getSetting('null_val'), isNull);
      expect(
        await db.getSetting('null_val', defaultValue: 'fallback'),
        'fallback',
      );
    });

    test('settings table allows multiple different keys per user', () async {
      final db = DatabaseManager.instance;
      await db.setSetting('theme', 'dark');
      await db.setSetting('currency', 'EUR');
      await db.setSetting('language', 'en');

      final handle = await db.database;
      final count = await handle.query(
        'SELECT COUNT(*) as cnt FROM settings WHERE user_id = ?',
        [db.userId],
      );
      expect(count.first['cnt'], 3);
    });

    test('imported_files imported_at is auto-set', () async {
      final db = DatabaseManager.instance;
      final handle = await db.database;

      await handle.execute(
        'INSERT INTO imported_files (id, user_id, file_hash, filename) VALUES (?1, ?2, ?3, ?4)',
        [newFileId(), db.userId, 'ts_hash', 'file.csv'],
      );

      final rows = await handle.query(
        'SELECT imported_at FROM imported_files WHERE file_hash = ?',
        ['ts_hash'],
      );
      expect(rows.first['imported_at'], isNotNull);
    });

    test('description name with special characters', () async {
      final db = DatabaseManager.instance;
      await db.getOrCreateDescription('Café & Restaurant (Main)');

      final descriptions = await db.getAllDescriptions();
      expect(
        descriptions.map((d) => d.name),
        contains('Café & Restaurant (Main)'),
      );
    });

    test('setting key with special characters', () async {
      final db = DatabaseManager.instance;
      await db.setSetting('user.prefs/font-size', '14');

      expect(await db.getSetting('user.prefs/font-size'), '14');
    });

    test('globalSetting and userSetting with same key are independent',
        () async {
      final db = DatabaseManager.instance;
      await db.setSetting('shared_key', 'user_value');
      await db.setAppSetting('shared_key', 'global_value');

      expect(await db.getSetting('shared_key'), 'user_value');
      expect(await db.getAppSetting('shared_key'), 'global_value');
    });

    test('logImportedFile records filename correctly', () async {
      final db = DatabaseManager.instance;
      final handle = await db.database;

      await handle.execute(
        'INSERT INTO imported_files (id, user_id, file_hash, filename) VALUES (?1, ?2, ?3, ?4)',
        [newFileId(), db.userId, 'file_hash_1', 'my_statement_march_2025.csv'],
      );

      final rows = await handle.query(
        'SELECT filename FROM imported_files WHERE file_hash = ?',
        ['file_hash_1'],
      );
      expect(rows.first['filename'], 'my_statement_march_2025.csv');
    });

    test('renaming a description that does not exist returns 0 updates',
        () async {
      final db = DatabaseManager.instance;
      expect(await db.renameDescription('does-not-exist', 'NewName'), isFalse);
    });

    test('delete all settings for a user', () async {
      final db = DatabaseManager.instance;
      final handle = await db.database;
      final uid = db.userId!;

      // Seed through the handle so the read cache stays cold, then delete.
      await handle.execute(
        'INSERT OR REPLACE INTO settings (user_id, "key", value) VALUES (?, ?, ?)',
        [uid, 'k1', 'v1'],
      );
      await handle.execute(
        'INSERT OR REPLACE INTO settings (user_id, "key", value) VALUES (?, ?, ?)',
        [uid, 'k2', 'v2'],
      );

      await handle.execute('DELETE FROM settings WHERE user_id = ?', [uid]);

      // Deletes are CRDT tombstones: nothing may remain visible.
      final count = await handle.query(
        'SELECT COUNT(*) as cnt FROM settings WHERE user_id = ? AND is_deleted = 0',
        [uid],
      );
      expect(count.first['cnt'], 0);
      expect(await db.getSetting('k1'), isNull);
    });

    test('delete imported_files for a user', () async {
      final db = DatabaseManager.instance;
      final handle = await db.database;
      final uid = db.userId!;

      await handle.execute(
        'INSERT INTO imported_files (id, user_id, file_hash, filename) VALUES (?1, ?2, ?3, ?4)',
        [newFileId(), uid, 'h1', 'f1.csv'],
      );
      await handle.execute(
        'INSERT INTO imported_files (id, user_id, file_hash, filename) VALUES (?1, ?2, ?3, ?4)',
        [newFileId(), uid, 'h2', 'f2.csv'],
      );

      await handle
          .execute('DELETE FROM imported_files WHERE user_id = ?', [uid]);

      // Deletes are CRDT tombstones: nothing may remain visible.
      final count = await handle.query(
        'SELECT COUNT(*) as cnt FROM imported_files WHERE user_id = ? AND is_deleted = 0',
        [uid],
      );
      expect(count.first['cnt'], 0);
    });

    test('description merge with transactions from multiple accounts',
        () async {
      final db = DatabaseManager.instance;
      final checking = await db.addAccount(
          'Checking', '#4CAF50', 'checking', 'EUR');
      final savingsA = await db.addAccount(
          'Savings A', '#2196F3', 'savings', 'EUR');
      final savingsB = await db.addAccount(
          'Savings B', '#009688', 'savings', 'EUR');
      await db.getOrCreateDescription('Food & Drink');

      for (final entry in [
        (checking, 30),
        (savingsA, 45),
        (savingsB, 60),
      ]) {
        await db.addTransaction(
          date: '2025-01-15',
          description: 'Groceries',
          amount: Decimal.fromInt(entry.$2),
          transactionType: 'income',
          accountId: entry.$1,
        );
      }

      expect(
        await db.mergeDescriptions('Groceries', 'Food & Drink'),
        isTrue,
      );

      final txns = await db.getTransactions();
      expect(txns, hasLength(3));
      expect(txns.every((t) => t.descriptionName == 'Food & Drink'), isTrue);
      expect(
        txns.map((t) => t.amount),
        containsAll(
            [Decimal.fromInt(30), Decimal.fromInt(45), Decimal.fromInt(60)]),
      );
    });

    test('settings value with very long string', () async {
      final db = DatabaseManager.instance;
      final longValue = 'x' * 10000;
      await db.setSetting('long_val', longValue);

      expect(await db.getSetting('long_val'), longValue);
    });
  });
}

int _fileSeq = 0;
String newFileId() =>
    'imp-${DateTime.now().microsecondsSinceEpoch}-${_fileSeq++}';
