import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite_crdt/sqlite_crdt.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:peadra/core/database/database_manager.dart';
import 'package:peadra/core/utils/constants.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test(
    'v12 -> v13 migration accepts stock accounts and keeps tombstones',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'peadra_stock_migration',
      );
      addTearDown(() => dir.delete(recursive: true));
      final path = p.join(dir.path, 'peadra.db');

      final before = await SqliteCrdt.open(
        path,
        version: 12,
        onCreate: (db, version) => _createSchema(db, 12),
      );
      await before.execute(
        'INSERT INTO users (id, username, password_hash, password_salt) '
        'VALUES (?1, ?2, ?3, ?4)',
        ['u1', 'Arthur', 'hash', null],
      );
      await before.execute(
        'INSERT INTO accounts (id, user_id, name, type, color, currency, '
        'starting_amount, deleted_at, is_deleted) '
        'VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9)',
        ['a1', 'u1', 'Checking', 'checking', '#4CAF50', 'EUR', 100.0, null, 0],
      );
      await before.execute(
        'INSERT INTO accounts (id, user_id, name, type, color, currency, '
        'starting_amount, deleted_at, is_deleted) '
        'VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9)',
        ['a2', 'u1', 'Old', 'savings', '#1976D2', 'EUR', 50.0, '2025-06-01', 1],
      );
      await before.execute(
        'INSERT INTO transactions (id, user_id, account_id, date, amount, '
        'transaction_type, currency) '
        'VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)',
        ['t1', 'u1', 'a1', '2025-01-15', 10.0, 'expense', 'EUR'],
      );
      final liveHlc =
          (await before.query('SELECT hlc FROM accounts WHERE id = ?', [
                'a1',
              ])).first['hlc']
              as String;
      await before.close();

      final upgraded = await SqliteCrdt.open(
        path,
        version: dbVersion,
        onUpgrade: DatabaseManager.instance.upgradeForTest,
      );
      addTearDown(upgraded.close);

      final accounts = await upgraded.query(
        'SELECT id, type, is_deleted, deleted_at, hlc FROM accounts ORDER BY id',
      );
      expect(accounts, hasLength(2));
      expect(accounts.first['type'], 'checking');
      expect(accounts.first['hlc'], liveHlc);
      expect(accounts.last['is_deleted'], 1);
      expect(accounts.last['deleted_at'], '2025-06-01');

      final txns = await upgraded.query('SELECT account_id FROM transactions');
      expect(txns.single['account_id'], 'a1');

      // The widened CHECK now accepts a Stock Market account.
      await upgraded.execute(
        'INSERT INTO accounts (id, user_id, name, type, color, currency, '
        'starting_amount) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)',
        ['a3', 'u1', 'Broker', 'stock', '#1976D2', 'EUR', 0.0],
      );
      expect(
        (await upgraded.query('SELECT type FROM accounts WHERE id = ?', [
          'a3',
        ])).single['type'],
        'stock',
      );

      // New tables exist and are writable.
      await upgraded.execute(
        'INSERT INTO stock_lines (id, user_id, account_id, ticker, name, '
        'quantity, buy_price, currency, bought_at, buy_cost) '
        'VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10)',
        [
          'l1',
          'u1',
          'a3',
          'AAPL',
          'Apple',
          1,
          100.0,
          'USD',
          '2026-01-01',
          100.0,
        ],
      );
      expect(await upgraded.query('SELECT * FROM stock_lines'), hasLength(1));

      final versionDb = await databaseFactoryFfi.openDatabase(
        path,
        options: OpenDatabaseOptions(readOnly: true, singleInstance: false),
      );
      addTearDown(versionDb.close);
      expect(await versionDb.getVersion(), dbVersion);
    },
  );

  test(
    'v7 -> v13 migration creates stock tables before index backfill',
    () async {
      final dir = await Directory.systemTemp.createTemp('peadra_stock_v7');
      addTearDown(() => dir.delete(recursive: true));
      final path = p.join(dir.path, 'peadra.db');

      final before = await SqliteCrdt.open(
        path,
        version: 7,
        onCreate: (db, version) => _createSchema(db, 7),
      );
      await before.execute(
        'INSERT INTO users (id, username, password_hash) '
        'VALUES (?1, ?2, ?3)',
        ['u1', 'Arthur', 'hash'],
      );
      await before.execute(
        'INSERT INTO accounts (id, user_id, name, type, color, currency, '
        'starting_amount, is_deleted) '
        'VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8)',
        ['a1', 'u1', 'Checking', 'checking', '#4CAF50', 'EUR', 100.0, 0],
      );
      await before.execute(
        'INSERT INTO transactions (id, user_id, account_id, date, amount, '
        'transaction_type, currency) '
        'VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)',
        ['t1', 'u1', 'a1', '2025-01-15', 10.0, 'expense', 'EUR'],
      );
      await before.close();

      final upgraded = await SqliteCrdt.open(
        path,
        version: dbVersion,
        onUpgrade: DatabaseManager.instance.upgradeForTest,
      );
      addTearDown(upgraded.close);

      expect(await upgraded.query('SELECT * FROM accounts'), hasLength(1));
      expect(await upgraded.query('SELECT * FROM stock_lines'), isEmpty);
      await upgraded.execute(
        'INSERT INTO accounts (id, user_id, name, type, color, currency, '
        'starting_amount) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)',
        ['a2', 'u1', 'Broker', 'stock', '#1976D2', 'EUR', 0.0],
      );
      expect(await upgraded.query('SELECT * FROM transactions'), hasLength(1));
    },
  );
}

Future<void> _createSchema(CrdtTableExecutor db, int version) async {
  await db.execute('''
    CREATE TABLE users (
      id TEXT PRIMARY KEY,
      username TEXT NOT NULL UNIQUE,
      password_hash TEXT NOT NULL,
      ${version >= 12 ? 'password_salt TEXT,' : ''}
      created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    )
  ''');
  await db.execute('''
    CREATE TABLE accounts (
      id TEXT PRIMARY KEY,
      user_id TEXT NOT NULL,
      name TEXT NOT NULL,
      type TEXT NOT NULL DEFAULT 'savings' CHECK(type IN ('checking', 'savings')),
      color TEXT DEFAULT '#1976D2',
      currency TEXT DEFAULT 'EUR',
      starting_amount REAL DEFAULT 0,
      created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
      ${version >= 11 ? 'deleted_at DATE,' : ''}
      UNIQUE(user_id, name),
      FOREIGN KEY (user_id) REFERENCES users(id)
    )
  ''');
  await db.execute('''
    CREATE TABLE descriptions (
      id TEXT PRIMARY KEY,
      user_id TEXT NOT NULL,
      name TEXT NOT NULL,
      created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
      UNIQUE(user_id, name),
      FOREIGN KEY (user_id) REFERENCES users(id)
    )
  ''');
  await db.execute('''
    CREATE TABLE tags (
      id TEXT PRIMARY KEY,
      user_id TEXT NOT NULL,
      name TEXT NOT NULL,
      color TEXT DEFAULT '#1976D2',
      created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
      UNIQUE(user_id, name),
      FOREIGN KEY (user_id) REFERENCES users(id)
    )
  ''');
  await db.execute('''
    CREATE TABLE transactions (
      id TEXT PRIMARY KEY,
      user_id TEXT NOT NULL,
      account_id TEXT,
      description_id TEXT,
      tag_id TEXT,
      date DATE NOT NULL,
      amount REAL NOT NULL,
      transaction_type TEXT NOT NULL CHECK(transaction_type IN ('income', 'expense', 'transfer')),
      currency TEXT DEFAULT 'EUR',
      notes TEXT,
      recurring_id TEXT,
      ${version >= 10 ? 'pinned INTEGER NOT NULL DEFAULT 0,' : ''}
      created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
      updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
      FOREIGN KEY (user_id) REFERENCES users(id)
    )
  ''');
  await db.execute('''
    CREATE TABLE recurring_transactions (
      id TEXT PRIMARY KEY,
      user_id TEXT NOT NULL,
      account_id TEXT,
      description_id TEXT,
      tag_id TEXT,
      amount REAL NOT NULL,
      transaction_type TEXT NOT NULL CHECK(transaction_type IN ('income', 'expense')),
      currency TEXT DEFAULT 'EUR',
      notes TEXT,
      frequency TEXT NOT NULL CHECK(frequency IN ('daily', 'weekly', 'monthly', 'yearly')),
      interval INTEGER DEFAULT 1,
      day_of_week INTEGER,
      day_of_month INTEGER,
      start_date DATE NOT NULL,
      end_date DATE,
      next_due_date DATE NOT NULL,
      active INTEGER DEFAULT 1,
      created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
      updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
      FOREIGN KEY (user_id) REFERENCES users(id)
    )
  ''');
  await db.execute('''
    CREATE TABLE recurring_exceptions (
      id TEXT PRIMARY KEY,
      recurring_id TEXT NOT NULL,
      date DATE NOT NULL,
      created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
      UNIQUE(recurring_id, date),
      FOREIGN KEY (recurring_id) REFERENCES recurring_transactions(id)
    )
  ''');
  await db.execute('''
    CREATE TABLE imported_files (
      id TEXT PRIMARY KEY,
      user_id TEXT NOT NULL,
      file_hash TEXT NOT NULL,
      filename TEXT,
      imported_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
      UNIQUE(user_id, file_hash),
      FOREIGN KEY (user_id) REFERENCES users(id)
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
  if (version >= 8) {
    await db.execute('''
      CREATE TABLE goals (
        id TEXT PRIMARY KEY,
        user_id TEXT NOT NULL,
        kind TEXT NOT NULL DEFAULT 'total_assets' CHECK(kind IN ('total_assets', 'account', 'tag')),
        account_id TEXT,
        tag_id TEXT,
        transaction_type TEXT NOT NULL DEFAULT '',
        target_amount REAL NOT NULL DEFAULT 0,
        currency TEXT DEFAULT 'EUR',
        period TEXT NOT NULL DEFAULT 'monthly' CHECK(period IN ('monthly', 'custom')),
        deadline DATE,
        start_date DATE,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        FOREIGN KEY (user_id) REFERENCES users(id)
      )
    ''');
  }
}
