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
          type TEXT NOT NULL DEFAULT 'savings' CHECK(type IN ('checking', 'savings')),
          color TEXT DEFAULT '#1976D2',
          currency TEXT DEFAULT 'EUR',
          starting_amount REAL DEFAULT 0,
          created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
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
          date TEXT NOT NULL,
          amount REAL NOT NULL,
          transaction_type TEXT NOT NULL CHECK(transaction_type IN ('income', 'expense', 'transfer')),
          currency TEXT DEFAULT 'EUR',
          notes TEXT,
          recurring_id TEXT,
          created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
          updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
          FOREIGN KEY (user_id) REFERENCES users(id),
          FOREIGN KEY (account_id) REFERENCES accounts(id),
          FOREIGN KEY (description_id) REFERENCES descriptions(id),
          FOREIGN KEY (tag_id) REFERENCES tags(id),
          FOREIGN KEY (recurring_id) REFERENCES recurring_transactions(id)
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
          start_date TEXT NOT NULL,
          end_date TEXT,
          next_due_date TEXT NOT NULL,
          active INTEGER DEFAULT 1,
          created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
          updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
          FOREIGN KEY (user_id) REFERENCES users(id),
          FOREIGN KEY (account_id) REFERENCES accounts(id),
          FOREIGN KEY (description_id) REFERENCES descriptions(id),
          FOREIGN KEY (tag_id) REFERENCES tags(id)
        )
      ''');

      await db.execute('''
        CREATE TABLE recurring_exceptions (
          id TEXT PRIMARY KEY,
          recurring_id TEXT NOT NULL,
          date TEXT NOT NULL,
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
        CREATE TABLE settings (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          user_id TEXT NOT NULL,
          "key" TEXT NOT NULL,
          value TEXT,
          UNIQUE(user_id, "key"),
          FOREIGN KEY (user_id) REFERENCES users(id)
        )
      ''');

      await db.execute('''
        CREATE TABLE encryption_meta (
          "key" TEXT PRIMARY KEY,
          value TEXT
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
          deadline TEXT,
          start_date TEXT,
          created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
          FOREIGN KEY (user_id) REFERENCES users(id),
          FOREIGN KEY (account_id) REFERENCES accounts(id),
          FOREIGN KEY (tag_id) REFERENCES tags(id)
        )
      ''');

      // Mirrors DatabaseManager._createIndexes so sync tests exercise the
      // same query plans as production.
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_transactions_user_date ON transactions(user_id, date)',
      );
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_transactions_account ON transactions(account_id)',
      );
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_transactions_description ON transactions(description_id)',
      );
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_transactions_tag ON transactions(tag_id)',
      );
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_recurring_user ON recurring_transactions(user_id)',
      );
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_recurring_exception ON recurring_exceptions(recurring_id)',
      );
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_goals_user ON goals(user_id)',
      );
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_transactions_recurring ON transactions(recurring_id)',
      );
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_recurring_account ON recurring_transactions(account_id)',
      );
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_goals_account ON goals(account_id)',
      );
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_goals_tag ON goals(tag_id)',
      );
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_accounts_type_user ON accounts(type, user_id)',
      );
    },
  );
}
