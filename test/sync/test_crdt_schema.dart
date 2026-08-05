import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqlite_crdt/sqlite_crdt.dart';

/// Initializes the FFI sqlite stack (desktop/CI). Call once per test process.
void initializeSyncTestDb() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
}

/// Creates an in-memory CRDT database with the Peadra v7 sync schema (all
/// tables exchanged by the sync layer).
Future<SqliteCrdt> createCrdtDatabase() {
  return SqliteCrdt.openInMemory(
    version: 1,
    singleInstance: false,
    onCreate: (CrdtTableExecutor db, int version) async {
      await db.execute('''
        CREATE TABLE users (
          id TEXT PRIMARY KEY,
          username TEXT NOT NULL UNIQUE,
          password_hash TEXT NOT NULL,
          created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
      ''');

      await db.execute('''
        CREATE TABLE accounts (
          id TEXT PRIMARY KEY,
          user_id TEXT NOT NULL,
          name TEXT NOT NULL,
          type TEXT DEFAULT 'savings',
          color TEXT DEFAULT '#1976D2',
          currency TEXT DEFAULT 'EUR',
          starting_amount REAL DEFAULT 0,
          created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
          UNIQUE(user_id, name)
        )
      ''');

      await db.execute('''
        CREATE TABLE descriptions (
          id TEXT PRIMARY KEY,
          user_id TEXT NOT NULL,
          name TEXT NOT NULL,
          created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
          UNIQUE(user_id, name)
        )
      ''');

      await db.execute('''
        CREATE TABLE tags (
          id TEXT PRIMARY KEY,
          user_id TEXT NOT NULL,
          name TEXT NOT NULL,
          color TEXT DEFAULT '#1976D2',
          UNIQUE(user_id, name)
        )
      ''');

      await db.execute('''
        CREATE TABLE transactions (
          id TEXT PRIMARY KEY,
          user_id TEXT NOT NULL,
          account_id TEXT,
          description_id TEXT,
          tag_id TEXT,
          date TEXT NOT NULL,
          amount REAL NOT NULL,
          transaction_type TEXT NOT NULL,
          currency TEXT DEFAULT 'EUR',
          notes TEXT,
          recurring_id TEXT,
          created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
          updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
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
          transaction_type TEXT NOT NULL,
          currency TEXT DEFAULT 'EUR',
          notes TEXT,
          frequency TEXT NOT NULL,
          interval INTEGER DEFAULT 1,
          day_of_week INTEGER,
          day_of_month INTEGER,
          start_date TEXT NOT NULL,
          end_date TEXT,
          next_due_date TEXT NOT NULL,
          active INTEGER DEFAULT 1,
          created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
          updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
      ''');

      await db.execute('''
        CREATE TABLE recurring_exceptions (
          id TEXT PRIMARY KEY,
          recurring_id TEXT NOT NULL,
          date TEXT NOT NULL,
          created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
          UNIQUE(recurring_id, date)
        )
      ''');

      await db.execute('''
        CREATE TABLE imported_files (
          id TEXT PRIMARY KEY,
          user_id TEXT NOT NULL,
          file_hash TEXT NOT NULL,
          filename TEXT,
          imported_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
          UNIQUE(user_id, file_hash)
        )
      ''');

      await db.execute('''
        CREATE TABLE settings (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          user_id TEXT NOT NULL,
          "key" TEXT NOT NULL,
          value TEXT,
          UNIQUE(user_id, "key")
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
    },
  );
}
