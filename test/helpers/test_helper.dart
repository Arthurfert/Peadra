import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqflite/sqflite.dart';

/// Initialize sqflite_ffi for desktop testing.
/// Must be called once before any database operations.
void initializeTestDatabase() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
}

/// Creates an in-memory database with the full Peadra schema.
/// Used for isolated unit tests that don't go through DatabaseManager.
Future<Database> createTestDatabase() async {
  return databaseFactoryFfi.openDatabase(
    inMemoryDatabasePath,
    options: OpenDatabaseOptions(
      version: 1,
      onCreate: _onCreate,
      singleInstance: false,
    ),
  );
}

Future<void> _onCreate(Database db, int version) async {
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
      type TEXT NOT NULL DEFAULT 'savings' CHECK(type IN ('checking', 'savings')),
      color TEXT DEFAULT '#1976D2',
      currency TEXT DEFAULT 'EUR',
      created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
      UNIQUE(user_id, name),
      FOREIGN KEY (user_id) REFERENCES users(id)
    )
  ''');

  await db.execute('''
    CREATE TABLE descriptions (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      user_id INTEGER NOT NULL,
      name TEXT NOT NULL,
      created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
      UNIQUE(user_id, name),
      FOREIGN KEY (user_id) REFERENCES users(id)
    )
  ''');

  await db.execute('''
    CREATE TABLE transactions (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      user_id INTEGER NOT NULL,
      account_id INTEGER,
      description_id INTEGER,
      date DATE NOT NULL,
      amount REAL NOT NULL,
      transaction_type TEXT NOT NULL CHECK(transaction_type IN ('income', 'expense', 'transfer')),
      currency TEXT DEFAULT 'EUR',
      notes TEXT,
      created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
      updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
      FOREIGN KEY (user_id) REFERENCES users(id),
      FOREIGN KEY (account_id) REFERENCES accounts(id),
      FOREIGN KEY (description_id) REFERENCES descriptions(id)
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
      UNIQUE(user_id, file_hash),
      FOREIGN KEY (user_id) REFERENCES users(id)
    )
  ''');

  await db.execute('''
    CREATE TABLE settings (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      user_id INTEGER NOT NULL,
      key TEXT NOT NULL,
      value TEXT,
      UNIQUE(user_id, key),
      FOREIGN KEY (user_id) REFERENCES users(id)
    )
  ''');
}

/// Seed the database with a test user and return the user ID.
Future<int> seedTestUser(Database db, {String username = 'testuser', String password = 'password123'}) async {
  final hash = _hashPassword(password);
  return await db.rawInsert(
    'INSERT INTO users (username, password_hash) VALUES (?, ?)',
    [username, hash],
  );
}

/// Simple SHA-256 hash for test passwords (mirrors AuthService.hashPassword).
String _hashPassword(String password) {
  // For testing, use a simple deterministic hash
  // In production, AuthService uses crypto:sha256
  var bytes = password.codeUnits;
  var hash = 0;
  for (var byte in bytes) {
    hash = ((hash << 5) - hash) + byte;
    hash = hash & hash;
  }
  return hash.toRadixString(16);
}

/// Seed test accounts for a user.
Future<List<int>> seedTestAccounts(Database db, int userId) async {
  final accounts = [
    {'user_id': userId, 'name': 'Checking Account', 'type': 'checking', 'color': '#4CAF50', 'currency': 'EUR'},
    {'user_id': userId, 'name': 'Savings Account A', 'type': 'savings', 'color': '#2196F3', 'currency': 'EUR'},
    {'user_id': userId, 'name': 'Savings Account B', 'type': 'savings', 'color': '#009688', 'currency': 'EUR'},
  ];
  final ids = <int>[];
  for (final acct in accounts) {
    final id = await db.insert('accounts', acct);
    ids.add(id);
  }
  return ids;
}

/// Seed a test description and return its ID.
Future<int> seedTestDescription(Database db, int userId, String name) async {
  return await db.insert('descriptions', {
    'user_id': userId,
    'name': name,
  });
}

/// Seed a test transaction and return its ID.
Future<int> seedTestTransaction(
  Database db,
  int userId, {
  int? accountId,
  int? descriptionId,
  String date = '2025-01-15',
  double amount = 100.0,
  String transactionType = 'income',
  String currency = 'EUR',
  String? notes,
}) async {
  return await db.insert('transactions', {
    'user_id': userId,
    'account_id': accountId,
    'description_id': descriptionId,
    'date': date,
    'amount': amount,
    'transaction_type': transactionType,
    'currency': currency,
    'notes': notes,
  });
}
