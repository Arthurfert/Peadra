import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:peadra/core/database/database_manager.dart';

void main() {
  setUpAll(initializeTestMigrationDb);

  test('v6 -> v7 migration keeps app-global settings under user_id 0', () async {
    final dir = await Directory.systemTemp.createTemp('peadra_migration_test');
    addTearDown(() => dir.delete(recursive: true));
    final path = p.join(dir.path, 'peadra.db');

    await _createV6Database(path);

    await DatabaseManager.instance.migrateDatabaseForTest(path);

    final migrated = await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        readOnly: true,
        singleInstance: false,
      ),
    );
    addTearDown(() => migrated.close());
    try {
      expect(await migrated.getVersion(), 7);

      final users = await migrated.query('users');
      expect(users, hasLength(1));
      final userId = users.first['id'] as String;

      // App-global settings (old user_id 0) are preserved as global settings.
      final globalSettings = await migrated.rawQuery(
        'SELECT "key", value FROM settings WHERE user_id = 0',
      );
      expect(globalSettings.map((r) => r['key']).toSet(),
          {'last_username', 'last_language'});

      // User settings now point at the remapped uuid user.
      final userSettings = await migrated.rawQuery(
        'SELECT "key", value FROM settings WHERE user_id = ?',
        [userId],
      );
      expect(userSettings.map((r) => r['key']).toSet(),
          {'theme_mode', 'currency'});

      // Per-table data preserved.
      final accounts = await migrated.query('accounts');
      final descriptions = await migrated.query('descriptions');
      final tags = await migrated.query('tags');
      final transactions = await migrated.query('transactions');
      expect(accounts, hasLength(1));
      expect(descriptions, hasLength(1));
      expect(tags, hasLength(1));
      expect(transactions, hasLength(1));
      expect(await migrated.query('exchange_rates'), hasLength(1));
      expect(await migrated.query('encryption_meta'), hasLength(1));

      // Foreign keys must reference the remapped rows, not the user uuid.
      final txn = transactions.first;
      expect(accounts.map((r) => r['id']),
          contains(txn['account_id']));
      expect(descriptions.map((r) => r['id']),
          contains(txn['description_id']));
      expect(tags.map((r) => r['id']), contains(txn['tag_id']));
      expect(txn['account_id'], isNot(userId));
      expect(txn['description_id'], isNot(userId));
      expect(txn['tag_id'], isNot(userId));
    } finally {
      await migrated.close();
    }
  });

  test('v6 -> v7 migration drops settings rows without any migrated user',
      () async {
    final dir = await Directory.systemTemp.createTemp('peadra_migration_test2');
    addTearDown(() => dir.delete(recursive: true));
    final path = p.join(dir.path, 'peadra.db');

    await _createV6Database(path);
    final db = await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(singleInstance: false),
    );
    await db.delete('users');
    await db.delete('settings');
    await db.insert('settings', {'user_id': 5, 'key': 'orphan', 'value': 'x'});
    await db.close();

    await DatabaseManager.instance.migrateDatabaseForTest(path);

    final migrated = await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        readOnly: true,
        singleInstance: false,
      ),
    );
    addTearDown(() => migrated.close());
    try {
      expect(await migrated.getVersion(), 7);
      expect(await migrated.query('users'), isEmpty);
      expect(await migrated.query('settings'), isEmpty);
      expect(await migrated.query('accounts'), isEmpty);
    } finally {
      await migrated.close();
    }
  });
}

void initializeTestMigrationDb() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
}

Future<void> _createV6Database(String path) async {
  final db = await databaseFactoryFfi.openDatabase(
    path,
    options: OpenDatabaseOptions(
      version: 6,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE users (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            username TEXT NOT NULL UNIQUE,
            password_hash TEXT NOT NULL,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
          )
        ''');
        await db.execute('''
          CREATE TABLE accounts (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            user_id INTEGER NOT NULL,
            name TEXT NOT NULL,
            type TEXT NOT NULL DEFAULT 'savings',
            color TEXT DEFAULT '#1976D2',
            currency TEXT DEFAULT 'EUR',
            starting_amount REAL DEFAULT 0,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            UNIQUE(user_id, name)
          )
        ''');
        await db.execute('''
          CREATE TABLE descriptions (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            user_id INTEGER NOT NULL,
            name TEXT NOT NULL,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            UNIQUE(user_id, name)
          )
        ''');
        await db.execute('''
          CREATE TABLE transactions (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            user_id INTEGER NOT NULL,
            account_id INTEGER,
            description_id INTEGER,
            tag_id INTEGER,
            date DATE NOT NULL,
            amount REAL NOT NULL,
            transaction_type TEXT NOT NULL,
            currency TEXT DEFAULT 'EUR',
            notes TEXT,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
          )
        ''');
        await db.execute('''
          CREATE TABLE exchange_rates (
            from_currency TEXT NOT NULL,
            to_currency TEXT NOT NULL,
            rate REAL NOT NULL,
            updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (from_currency, to_currency)
          )
        ''');
        await db.execute('''
          CREATE TABLE imported_files (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            user_id INTEGER NOT NULL,
            file_hash TEXT NOT NULL,
            filename TEXT,
            imported_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            UNIQUE(user_id, file_hash)
          )
        ''');
        await db.execute('''
          CREATE TABLE settings (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            user_id INTEGER NOT NULL,
            "key" TEXT NOT NULL,
            value TEXT,
            UNIQUE(user_id, "key")
          )
        ''');
        await db.execute('''
          CREATE TABLE encryption_meta (
            "key" TEXT PRIMARY KEY,
            value TEXT
          )
        ''');
        await db.execute('''
          CREATE TABLE tags (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            user_id INTEGER NOT NULL,
            name TEXT NOT NULL,
            color TEXT DEFAULT '#1976D2',
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            UNIQUE(user_id, name)
          )
        ''');
      },
    ),
  );

  final userId = await db.insert('users', {
    'username': 'Arthur',
    'password_hash': 'hash',
  });

  await db.insert('accounts', {
    'user_id': userId,
    'name': 'Checking',
    'type': 'checking',
  });
  await db.insert('descriptions', {'user_id': userId, 'name': 'Coffee'});
  await db.insert('tags', {'user_id': userId, 'name': 'food'});
  await db.insert('transactions', {
    'user_id': userId,
    'account_id': 1,
    'description_id': 1,
    'tag_id': 1,
    'date': '2025-01-15',
    'amount': 10.0,
    'transaction_type': 'expense',
  });
  await db.insert('exchange_rates', {
    'from_currency': 'EUR',
    'to_currency': 'USD',
    'rate': 1.1,
  });
  await db.insert('encryption_meta', {'key': 'version', 'value': '1'});
  await db.insert('settings', {'user_id': userId, 'key': 'theme_mode', 'value': 'dark'});
  await db.insert('settings', {'user_id': userId, 'key': 'currency', 'value': 'EUR'});
  await db.insert('settings', {'user_id': 0, 'key': 'last_username', 'value': 'Arthur'});
  await db.insert('settings', {'user_id': 0, 'key': 'last_language', 'value': 'fr'});
  await db.setVersion(6);
  await db.close();
}
