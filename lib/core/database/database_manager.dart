import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqlite_crdt/sqlite_crdt.dart';
import 'package:uuid/uuid.dart';

import '../models/account.dart';
import '../models/description.dart';
import '../models/tag.dart';
import '../models/transaction.dart';
import '../models/recurring_transaction.dart';

import '../utils/constants.dart';
import '../services/currency_service.dart';
import '../services/auth_service.dart';
import '../services/encryption_service.dart';
import '../services/recurring_service.dart';
import '../i18n/translator.dart';

class DatabaseManager {
  static SqliteCrdt? _database;
  String? _dbPath;
  String? _userId;
  final Map<String, String?> _settingCache = {};
  final Map<String, String?> _appSettingCache = {};
  final Map<String, String> _descriptionCache = {};
  final Map<String, double?> _exchangeRateCache = {};
  SecretKey? _encryptionKey;
  final Uuid _uuid = const Uuid();

  // Notifies UI that a changeset received from a paired device has been applied
  // to the local database, so mounted views can reload freshly synced data.
  final StreamController<void> _remoteDataController =
      StreamController<void>.broadcast();

  DatabaseManager._();
  static final DatabaseManager instance = DatabaseManager._();

  String? get userId => _userId;
  bool get isEncrypted => _encryptionKey != null;
  String? get dbPath => _dbPath;

  /// Fires after a remote changeset (from a sync) is applied locally.
  Stream<void> get onRemoteDataApplied => _remoteDataController.stream;

  /// Notifies listeners that remote data just landed (called by the sync layer).
  void notifyRemoteDataApplied() {
    _remoteDataController.add(null);
  }

  /// The CRDT-backed database. Every write is timestamped with an HLC so that
  /// changesets can later be exchanged between devices.
  Future<SqliteCrdt> get database async {
    _database ??= await _openDatabase();
    return _database!;
  }

  // ==================== ENCRYPTION ====================

  SecretKey? get encryptionKey => _encryptionKey;

  Future<void> setEncryptionKey(SecretKey key) async {
    _encryptionKey = key;
  }

  void clearEncryptionKey() {
    _encryptionKey = null;
  }

  Future<String?> _encrypt(String? plaintext) async {
    if (plaintext == null || plaintext.isEmpty || _encryptionKey == null) {
      return plaintext;
    }
    try {
      return await EncryptionService.encrypt(plaintext, _encryptionKey!);
    } catch (_) {
      return plaintext;
    }
  }

  Future<String?> _decrypt(String? ciphertext) async {
    if (ciphertext == null || ciphertext.isEmpty || _encryptionKey == null) {
      return ciphertext;
    }
    try {
      return await EncryptionService.decrypt(ciphertext, _encryptionKey!);
    } catch (_) {
      return ciphertext;
    }
  }

  Future<String?> _decryptValue(dynamic value) async {
    if (value == null) return null;
    if (value is num) return value.toString();
    return _decrypt(value.toString());
  }

  Future<double> _decryptAmount(dynamic encrypted) async {
    if (encrypted == null) return 0.0;
    if (encrypted is num) return encrypted.toDouble();
    final s = encrypted.toString();
    if (s.isEmpty || _encryptionKey == null) {
      return double.tryParse(s) ?? 0.0;
    }
    try {
      final decrypted = await _decrypt(s);
      return double.tryParse(decrypted ?? '') ?? 0.0;
    } catch (_) {
      return double.tryParse(s) ?? 0.0;
    }
  }

  String _newId() => _uuid.v4();

  // ==================== DATABASE OPEN / MIGRATION ====================

  @visibleForTesting
  Future<void> migrateDatabaseForTest(String path) => _migrateToV7(path);

  /// Binds an in-memory production-schema CRDT for isolated tests, re-pointing
  /// the singleton's [database] so `migrateEncryptionKey` etc. can be driven.
  @visibleForTesting
  Future<SqliteCrdt> openInMemoryForTest({String? userId}) async {
    final crdt = await SqliteCrdt.openInMemory(
      singleInstance: false,
      version: dbVersion,
      onCreate: _onCreate,
    );
    _database = crdt;
    if (userId != null) _userId = userId;
    return crdt;
  }

  Future<SqliteCrdt> _openDatabase() async {
    final path = await _resolveDbPath();
    _dbPath = path;

    final file = File(path);
    if (file.existsSync() && await _needsMigration(path)) {
      await _migrateToV7(path);
    }

    final crdt = await SqliteCrdt.open(
      path,
      version: dbVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
    return crdt;
  }

  Future<String> _resolveDbPath() async {
    if (Platform.isAndroid || Platform.isIOS) {
      final dir = await getApplicationDocumentsDirectory();
      return join(dir.path, dbName);
    }
    final home = Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ??
        Directory.current.path;
    final oldDir = Directory(join(home, '.Peadra'));
    final peadraDir = Directory(join(home, '.peadra'));
    if (oldDir.existsSync() && !peadraDir.existsSync()) {
      await oldDir.rename(peadraDir.path);
    }
    if (!peadraDir.existsSync()) {
      await peadraDir.create(recursive: true);
    }
    return join(peadraDir.path, dbName);
  }

  Future<bool> _needsMigration(String path) async {
    try {
      final db = await databaseFactoryFfi.openDatabase(
        path,
        options: OpenDatabaseOptions(readOnly: true, singleInstance: false),
      );
      final version = await db.getVersion();
      await db.close();
      return version < 7;
    } catch (_) {
      return false;
    }
  }

  /// One-time migration from the pre-CRDT schema (v1-v6) to v7.
  /// The old file is left untouched until the new database is fully built, then
  /// swapped in place.
  Future<void> _migrateToV7(String path) async {
    final srcPath = '$path.migrate_src';
    final tmpPath = '$path.migrate_tmp';

    await File(path).copy(srcPath);
    final tmpFile = File(tmpPath);
    if (tmpFile.existsSync()) await tmpFile.delete();

    try {
      final crdt = await SqliteCrdt.open(
        tmpPath,
        version: dbVersion,
        onCreate: _onCreate,
      );
      try {
        await _copyLegacyData(srcPath, crdt);
      } finally {
        await crdt.close();
      }

      final oldFile = File(path);
      if (oldFile.existsSync()) await oldFile.delete();
      await File(tmpPath).rename(path);
    } finally {
      final src = File(srcPath);
      if (src.existsSync()) await src.delete();
    }
  }

  Future<void> _copyLegacyData(String srcPath, SqliteCrdt crdt) async {
    final src = await databaseFactoryFfi.openDatabase(
      srcPath,
      options: OpenDatabaseOptions(readOnly: true, singleInstance: false),
    );
    try {
      final tables = (await src.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%'",
      )).map((r) => r['name'] as String).toSet();

      // users: old int id -> new uuid
      final userMap = <int, String>{};
      if (tables.contains('users')) {
        final rows = await src.query('users', orderBy: 'id');
        for (final r in rows) {
          final newId = _newId();
          userMap[r['id'] as int] = newId;
          await crdt.execute(
            'INSERT INTO users (id, username, password_hash, created_at) '
            'VALUES (?1, ?2, ?3, ?4)',
            [
              newId,
              r['username'] as String,
              r['password_hash'] as String,
              r['created_at'] as String?,
            ],
          );
        }
      }

      String? uid(dynamic oldId) => userMap[oldId];

      // Each table is remapped to fresh UUIDs, so foreign keys must be
      // translated through the owning table's map (not the user map).
      final accountMap = <int, String>{};
      if (tables.contains('accounts')) {
        final rows = await src.query('accounts', orderBy: 'id');
        for (final r in rows) {
          final newUserId = uid(r['user_id']);
          if (newUserId == null) continue;
          final newId = _newId();
          accountMap[r['id'] as int] = newId;
          await crdt.execute(
            'INSERT INTO accounts (id, user_id, name, type, color, currency, starting_amount, created_at) '
            'VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8)',
            [
              newId,
              newUserId,
              r['name'],
              r['type'],
              r['color'],
              r['currency'],
              r['starting_amount'],
              r['created_at'],
            ],
          );
        }
      }

      final descriptionMap = <int, String>{};
      if (tables.contains('descriptions')) {
        final rows = await src.query('descriptions', orderBy: 'id');
        for (final r in rows) {
          final newUserId = uid(r['user_id']);
          if (newUserId == null) continue;
          final newId = _newId();
          descriptionMap[r['id'] as int] = newId;
          await crdt.execute(
            'INSERT INTO descriptions (id, user_id, name, created_at) '
            'VALUES (?1, ?2, ?3, ?4)',
            [newId, newUserId, r['name'], r['created_at']],
          );
        }
      }

      final tagMap = <int, String>{};
      if (tables.contains('tags')) {
        final rows = await src.query('tags', orderBy: 'id');
        for (final r in rows) {
          final newUserId = uid(r['user_id']);
          if (newUserId == null) continue;
          final newId = _newId();
          tagMap[r['id'] as int] = newId;
          await crdt.execute(
            'INSERT INTO tags (id, user_id, name, color, created_at) '
            'VALUES (?1, ?2, ?3, ?4, ?5)',
            [newId, newUserId, r['name'], r['color'], r['created_at']],
          );
        }
      }

      final recurringMap = <int, String>{};
      if (tables.contains('recurring_transactions')) {
        final rows = await src.query('recurring_transactions', orderBy: 'id');
        for (final r in rows) {
          final newUserId = uid(r['user_id']);
          if (newUserId == null) continue;
          final newId = _newId();
          recurringMap[r['id'] as int] = newId;
          await crdt.execute(
            'INSERT INTO recurring_transactions (id, user_id, account_id, description_id, tag_id, amount, transaction_type, currency, notes, frequency, interval, day_of_week, day_of_month, start_date, end_date, next_due_date, active, created_at, updated_at) '
            'VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13, ?14, ?15, ?16, ?17, ?18, ?19)',
            [
              newId,
              newUserId,
              r['account_id'] != null ? accountMap[r['account_id']] : null,
              r['description_id'] != null ? descriptionMap[r['description_id']] : null,
              r['tag_id'] != null ? tagMap[r['tag_id']] : null,
              r['amount'],
              r['transaction_type'],
              r['currency'],
              r['notes'],
              r['frequency'],
              r['interval'],
              r['day_of_week'],
              r['day_of_month'],
              r['start_date'],
              r['end_date'],
              r['next_due_date'],
              r['active'],
              r['created_at'],
              r['updated_at'],
            ],
          );
        }
      }

      if (tables.contains('transactions')) {
        final rows = await src.query('transactions', orderBy: 'id');
        for (final r in rows) {
          final newUserId = uid(r['user_id']);
          if (newUserId == null) continue;
          await crdt.execute(
            'INSERT INTO transactions (id, user_id, account_id, description_id, tag_id, date, amount, transaction_type, currency, notes, recurring_id, created_at, updated_at) '
            'VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13)',
            [
              _newId(),
              newUserId,
              r['account_id'] != null ? accountMap[r['account_id']] : null,
              r['description_id'] != null ? descriptionMap[r['description_id']] : null,
              r['tag_id'] != null ? tagMap[r['tag_id']] : null,
              r['date'],
              r['amount'],
              r['transaction_type'],
              r['currency'],
              r['notes'],
              r['recurring_id'] != null ? recurringMap[r['recurring_id']] : null,
              r['created_at'],
              r['updated_at'],
            ],
          );
        }
      }

      if (tables.contains('recurring_exceptions')) {
        final rows = await src.query('recurring_exceptions', orderBy: 'id');
        for (final r in rows) {
          final newRecurringId = recurringMap[r['recurring_id']];
          if (newRecurringId == null) continue;
          await crdt.execute(
            'INSERT INTO recurring_exceptions (id, recurring_id, date, created_at) '
            'VALUES (?1, ?2, ?3, ?4)',
            [_newId(), newRecurringId, r['date'], r['created_at']],
          );
        }
      }

      if (tables.contains('imported_files')) {
        final rows = await src.query('imported_files', orderBy: 'id');
        for (final r in rows) {
          final newUserId = uid(r['user_id']);
          if (newUserId == null) continue;
          await crdt.execute(
            'INSERT INTO imported_files (id, user_id, file_hash, filename, imported_at) '
            'VALUES (?1, ?2, ?3, ?4, ?5)',
            [_newId(), newUserId, r['file_hash'], r['filename'], r['imported_at']],
          );
        }
      }

      if (tables.contains('settings')) {
        final rows = await src.query('settings', orderBy: 'id');
        for (final r in rows) {
          // Pre-v7 stored app-global settings (e.g. last_username) under
          // user_id 0; keep them as global settings in v7. Rows belonging to
          // users that did not migrate are dropped.
          final oldUserId = r['user_id'] as int?;
          final newUserId =
              (oldUserId == null || oldUserId == globalSettingsUserId)
                  ? globalSettingsUserId
                  : uid(oldUserId);
          if (newUserId == null) continue;
          await crdt.execute(
            'INSERT INTO settings (user_id, "key", value) VALUES (?1, ?2, ?3)',
            [newUserId, r['key'], r['value']],
          );
        }
      }

      if (tables.contains('encryption_meta')) {
        final rows = await src.query('encryption_meta');
        for (final r in rows) {
          await crdt.execute(
            'INSERT INTO encryption_meta ("key", value) VALUES (?1, ?2)',
            [r['key'], r['value']],
          );
        }
      }

      if (tables.contains('exchange_rates')) {
        final rows = await src.query('exchange_rates');
        for (final r in rows) {
          await crdt.execute(
            'INSERT INTO exchange_rates (from_currency, to_currency, rate, updated_at) '
            'VALUES (?1, ?2, ?3, ?4)',
            [r['from_currency'], r['to_currency'], r['rate'], r['updated_at']],
          );
        }
      }
    } finally {
      await src.close();
    }
  }

  Future<void> _onCreate(CrdtTableExecutor db, int version) async {
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
        date DATE NOT NULL,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        UNIQUE(recurring_id, date),
        FOREIGN KEY (recurring_id) REFERENCES recurring_transactions(id)
      )
    ''');

    await _createIndexes(db);
  }

  Future<void> _onUpgrade(CrdtTableExecutor db, int oldVersion, int newVersion) async {
    // Pre-v7 databases are migrated outside of the CRDT layer by
    // [_migrateToV7]; nothing to do here.
  }

  Future<void> _createIndexes(CrdtTableExecutor db) async {
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
  }

  /// Encrypt all existing unencrypted data. Called after login when encryption is first enabled.
  Future<void> migrateToEncryption() async {
    if (_encryptionKey == null) return;
    final db = await database;

    final meta = await db.query(
      'SELECT value FROM encryption_meta WHERE "key" = ?',
      ['version'],
    );
    if (meta.isNotEmpty && meta.first['value'] == '1') return;

    await _encryptAccounts(db);
    await _encryptDescriptions(db);
    await _encryptTransactions(db);
    await _encryptRecurring(db);

    await db.execute(
      'INSERT OR REPLACE INTO encryption_meta ("key", value) VALUES (?, ?)',
      ['version', '1'],
    );
  }

  Future<void> reEncryptData(SecretKey newKey) async {
    if (_encryptionKey == null) return;
    await migrateEncryptionKey(_encryptionKey!, newKey);
  }

  /// Re-encrypts the current user's encrypted fields from [oldKey] to [newKey].
  ///
  /// Fields that cannot be decrypted with [oldKey] — plaintext or rows synced
  /// from another device under a different key — are left untouched, so this is
  /// safe on devices holding mixed-key data.
  Future<void> migrateEncryptionKey(SecretKey oldKey, SecretKey newKey) async {
    final db = await database;
    _encryptionKey = newKey;

    Future<void> updateRow(
      String table,
      Object? id,
      Map<String, String> fields,
    ) async {
      final sets = fields.keys.map((k) => '$k = ?').join(', ');
      await db.execute(
        'UPDATE $table SET $sets WHERE id = ? AND user_id = ?',
        [...fields.values, id, _userId],
      );
    }

    Future<String?> reencrypt(dynamic value) async {
      if (value == null || value.toString().isEmpty) return null;
      try {
        final decrypted =
            await EncryptionService.decrypt(value.toString(), oldKey);
        return await _encrypt(decrypted);
      } catch (_) {
        return null;
      }
    }

    final acctRows = await db.query(
      'SELECT id, name, starting_amount FROM accounts WHERE user_id = ? AND is_deleted = 0',
      [_userId],
    );
    for (final row in acctRows) {
      final fields = <String, String>{};
      final name = await reencrypt(row['name']);
      final amount = await reencrypt(row['starting_amount']);
      if (name != null) fields['name'] = name;
      if (amount != null) fields['starting_amount'] = amount;
      if (fields.isNotEmpty) await updateRow('accounts', row['id'], fields);
    }

    final descRows = await db.query(
      'SELECT id, name FROM descriptions WHERE user_id = ? AND is_deleted = 0',
      [_userId],
    );
    for (final row in descRows) {
      final name = await reencrypt(row['name']);
      if (name != null) {
        await updateRow('descriptions', row['id'], {'name': name});
      }
    }

    final txnRows = await db.query(
      'SELECT id, amount, notes FROM transactions WHERE user_id = ? AND is_deleted = 0',
      [_userId],
    );
    for (final row in txnRows) {
      final fields = <String, String>{};
      final amount = await reencrypt(row['amount']);
      final notes = await reencrypt(row['notes']);
      if (amount != null) fields['amount'] = amount;
      if (notes != null) fields['notes'] = notes;
      if (fields.isNotEmpty) {
        await updateRow('transactions', row['id'], fields);
      }
    }

    final recRows = await db.query(
      'SELECT id, amount, notes FROM recurring_transactions WHERE user_id = ? AND is_deleted = 0',
      [_userId],
    );
    for (final row in recRows) {
      final fields = <String, String>{};
      final amount = await reencrypt(row['amount']);
      final notes = await reencrypt(row['notes']);
      if (amount != null) fields['amount'] = amount;
      if (notes != null) fields['notes'] = notes;
      if (fields.isNotEmpty) {
        await updateRow('recurring_transactions', row['id'], fields);
      }
    }
  }

  Future<void> _encryptAccounts(SqliteCrdt db) async {
    final rows = await db.query(
      'SELECT id, name, starting_amount FROM accounts WHERE user_id = ? AND is_deleted = 0',
      [_userId],
    );
    for (final row in rows) {
      final name = row['name'] as String?;
      final amount = row['starting_amount'] as dynamic;
      final encryptedName = await _encrypt(name);
      final encryptedAmount = amount != null ? await _encrypt(amount.toString()) : null;
      await db.execute(
        'UPDATE accounts SET name = ?, starting_amount = ? WHERE id = ? AND user_id = ?',
        [encryptedName, encryptedAmount, row['id'], _userId],
      );
    }
  }

  Future<void> _encryptDescriptions(SqliteCrdt db) async {
    final rows = await db.query(
      'SELECT id, name FROM descriptions WHERE user_id = ? AND is_deleted = 0',
      [_userId],
    );
    for (final row in rows) {
      final name = row['name'] as String?;
      final encryptedName = await _encrypt(name);
      await db.execute(
        'UPDATE descriptions SET name = ? WHERE id = ? AND user_id = ?',
        [encryptedName, row['id'], _userId],
      );
    }
  }

  Future<void> _encryptTransactions(SqliteCrdt db) async {
    final rows = await db.query(
      'SELECT id, amount, notes FROM transactions WHERE user_id = ? AND is_deleted = 0',
      [_userId],
    );
    for (final row in rows) {
      final amount = row['amount'] as dynamic;
      final notes = row['notes'] as String?;
      final encryptedAmount = amount != null ? await _encrypt(amount.toString()) : null;
      final encryptedNotes = await _encrypt(notes);
      await db.execute(
        'UPDATE transactions SET amount = ?, notes = ? WHERE id = ? AND user_id = ?',
        [encryptedAmount, encryptedNotes, row['id'], _userId],
      );
    }
  }

  Future<void> _encryptRecurring(SqliteCrdt db) async {
    final rows = await db.query(
      'SELECT id, amount, notes FROM recurring_transactions WHERE user_id = ? AND is_deleted = 0',
      [_userId],
    );
    for (final row in rows) {
      final amount = row['amount'] as dynamic;
      final notes = row['notes'] as String?;
      final encryptedAmount = amount != null ? await _encrypt(amount.toString()) : null;
      final encryptedNotes = await _encrypt(notes);
      await db.execute(
        'UPDATE recurring_transactions SET amount = ?, notes = ? WHERE id = ? AND user_id = ?',
        [encryptedAmount, encryptedNotes, row['id'], _userId],
      );
    }
  }

  // ==================== USER ====================

void setUserId(String userId) {
    _userId = userId;
    _descriptionCache.clear();
    _exchangeRateCache.clear();
    _insertDefaultAccounts();
    cleanupUnusedDescriptions();
  }

  /// Updates the session user id without seeding defaults or generating
  /// recurring transactions. Used after sync user reconciliation may have
  /// rewritten this user's id to the peer's canonical id, so queries continue
  /// filtering against the id that now owns the data.
  void setSessionUserId(String? userId) {
    if (userId == _userId) return;
    _userId = userId;
    _descriptionCache.clear();
    _exchangeRateCache.clear();
  }

  Future<void> _insertDefaultAccounts() async {
    if (_userId == null) return;
    final db = await database;
    final countRows = await db.query(
      'SELECT COUNT(*) as count FROM accounts WHERE user_id = ? AND is_deleted = 0',
      [_userId],
    );
    if (countRows.isNotEmpty && (countRows.first['count'] as num? ?? 0) > 0) {
      return;
    }

    final currency = await getSetting('currency', defaultValue: defaultCurrency);
    final defaults = [
      {'name': 'Checking Account', 'color': '#4CAF50', 'type': 'checking', 'currency': currency},
      {'name': 'Savings Account A', 'color': '#2196F3', 'type': 'savings', 'currency': currency},
      {'name': 'Savings Account B', 'color': '#009688', 'type': 'savings', 'currency': currency},
    ];

    for (final acct in defaults) {
      await db.execute(
        'INSERT INTO accounts (id, user_id, name, color, type, currency) '
        'VALUES (?1, ?2, ?3, ?4, ?5, ?6)',
        [_newId(), _userId, acct['name'], acct['color'], acct['type'], acct['currency']],
      );
    }
  }

  // ==================== ACCOUNTS ====================

  Future<List<Account>> getAllAccounts() async {
    final db = await database;
    final rows = await db.query(
      'SELECT * FROM accounts WHERE user_id = ? AND is_deleted = 0',
      [_userId],
    );
    final accounts = <Account>[];
    for (final r in rows) {
      accounts.add(Account(
        id: r['id'] as String?,
        userId: r['user_id'] as String,
        name: await _decryptValue(r['name']) ?? '',
        type: r['type'] as String? ?? 'savings',
        color: r['color'] as String? ?? '#1976D2',
        currency: r['currency'] as String? ?? 'EUR',
        startingAmount: await _decryptAmount(r['starting_amount']),
        createdAt: r['created_at'] as String?,
      ));
    }
    accounts.sort((a, b) => a.name.compareTo(b.name));
    return accounts;
  }

  Future<List<AccountWithBalance>> getAccountsWithBalances() async {
    final db = await database;
    final acctRows = await db.query(
      'SELECT * FROM accounts WHERE user_id = ? AND is_deleted = 0 ORDER BY name',
      [_userId],
    );

    final txnRows = await db.query(
      'SELECT transaction_type, amount, account_id FROM transactions WHERE user_id = ? AND is_deleted = 0',
      [_userId],
    );
    final txnByAccount = <String, List<Map<String, Object?>>>{};
    for (final t in txnRows) {
      final acctId = t['account_id'] as String?;
      if (acctId == null) continue;
      (txnByAccount[acctId] ??= []).add(t);
    }

    final results = <AccountWithBalance>[];
    for (final acctRow in acctRows) {
      final startingAmount = await _decryptAmount(acctRow['starting_amount']);

      double balance = startingAmount;
      for (final txn in txnByAccount[acctRow['id']] ?? const <Map<String, Object?>>[]) {
        final amount = await _decryptAmount(txn['amount']);
        final type = txn['transaction_type'] as String;
        if (type == 'income') {
          balance += amount;
        } else if (type == 'expense') {
          balance -= amount;
        }
      }

      results.add(AccountWithBalance(
        id: acctRow['id'] as String?,
        userId: acctRow['user_id'] as String,
        name: await _decryptValue(acctRow['name']) ?? '',
        type: acctRow['type'] as String? ?? 'savings',
        color: acctRow['color'] as String? ?? '#1976D2',
        currency: acctRow['currency'] as String? ?? 'EUR',
        startingAmount: startingAmount,
        createdAt: acctRow['created_at'] as String?,
        balance: balance,
      ));
    }
    return results;
  }

  Future<String?> addAccount(String name, String color, String type, String currency, {double startingAmount = 0.0}) async {
    final db = await database;
    try {
      final encryptedName = await _encrypt(name);
      final encryptedAmount = await _encrypt(startingAmount.toString());
      final id = _newId();
      await db.execute(
        'INSERT INTO accounts (id, user_id, name, color, type, currency, starting_amount) '
        'VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)',
        [id, _userId, encryptedName, color, type, currency, encryptedAmount],
      );
      return id;
    } catch (_) {
      return null;
    }
  }

  Future<bool> updateAccount(String accountId, String name, String color,
      {String? type, String? currency, double? startingAmount, bool updateNameInTransactions = false}) async {
    final db = await database;
    final existing = await db.query(
      'SELECT * FROM accounts WHERE id = ? AND user_id = ? AND is_deleted = 0',
      [accountId, _userId],
    );
    if (existing.isEmpty) return false;

    final oldNameEncrypted = existing.first['name'] as String;
    final oldName = await _decrypt(oldNameEncrypted) ?? '';
    final oldCurrency = (existing.first['currency'] as String?) ?? defaultCurrency;
    final effectiveCurrency = currency ?? oldCurrency;

    final encryptedName = await _encrypt(name);
    var sql = 'UPDATE accounts SET name = ?, color = ?, currency = ?';
    final args = <Object?>[encryptedName, color, effectiveCurrency];
    if (type != null) {
      sql += ', type = ?';
      args.add(type);
    }
    if (startingAmount != null) {
      sql += ', starting_amount = ?';
      args.add(await _encrypt(startingAmount.toString()));
    }
    sql += ' WHERE id = ? AND user_id = ?';
    args.add(accountId);
    args.add(_userId);
    await db.execute(sql, args);

    if (updateNameInTransactions && oldName != name) {
      await _updateTransferNames(db, oldName, name);
    }

    return true;
  }

  Future<void> _updateTransferNames(SqliteCrdt db, String oldName, String newName) async {
    final txnRows = await db.query(
      'SELECT id, notes FROM transactions WHERE user_id = ? AND is_deleted = 0 AND notes IS NOT NULL',
      [_userId],
    );
    for (final row in txnRows) {
      final notes = row['notes'] as String?;
      if (notes == null || notes.isEmpty) continue;
      final decrypted = await _decrypt(notes);
      if (decrypted == null) continue;
      final oldTransferTo = 'Transfer to $oldName';
      final newTransferTo = 'Transfer to $newName';
      final oldTransferFrom = 'Transfer from $oldName';
      final newTransferFrom = 'Transfer from $newName';
      String updated = decrypted;
      if (updated.contains(oldTransferTo)) {
        updated = updated.replaceAll(oldTransferTo, newTransferTo);
      }
      if (updated.contains(oldTransferFrom)) {
        updated = updated.replaceAll(oldTransferFrom, newTransferFrom);
      }
      if (updated != decrypted) {
        final reEncrypted = await _encrypt(updated);
        await db.execute(
          'UPDATE transactions SET notes = ? WHERE id = ? AND user_id = ?',
          [reEncrypted, row['id'], _userId],
        );
      }
    }

    final descRows = await db.query(
      'SELECT id, name FROM descriptions WHERE user_id = ? AND is_deleted = 0',
      [_userId],
    );
    for (final row in descRows) {
      final name = row['name'] as String?;
      if (name == null || name.isEmpty) continue;
      final decrypted = await _decrypt(name);
      if (decrypted == null) continue;
      final oldTransferTo = 'Transfer to $oldName';
      final newTransferTo = 'Transfer to $newName';
      final oldTransferFrom = 'Transfer from $oldName';
      final newTransferFrom = 'Transfer from $newName';
      String updated = decrypted;
      if (updated.contains(oldTransferTo)) {
        updated = updated.replaceAll(oldTransferTo, newTransferTo);
      }
      if (updated.contains(oldTransferFrom)) {
        updated = updated.replaceAll(oldTransferFrom, newTransferFrom);
      }
      if (updated != decrypted) {
        final reEncrypted = await _encrypt(updated);
        await db.execute(
          'UPDATE descriptions SET name = ? WHERE id = ? AND user_id = ?',
          [reEncrypted, row['id'], _userId],
        );
      }
    }
  }

  Future<bool> deleteAccount(String accountId, {bool deleteTransactions = false}) async {
    final db = await database;
    final existing = await db.query(
      'SELECT * FROM accounts WHERE id = ? AND user_id = ? AND is_deleted = 0',
      [accountId, _userId],
    );
    if (existing.isEmpty) return false;

    if (deleteTransactions) {
      final recIds = await db.query(
        'SELECT id FROM recurring_transactions WHERE account_id = ? AND user_id = ? AND is_deleted = 0',
        [accountId, _userId],
      );
      await db.execute(
        'DELETE FROM transactions WHERE account_id = ? AND user_id = ?',
        [accountId, _userId],
      );
      for (final rec in recIds) {
        await _deleteRecurringWithChildren(db, rec['id'] as String);
      }
    } else {
      await db.execute(
        'UPDATE transactions SET account_id = NULL WHERE account_id = ? AND user_id = ?',
        [accountId, _userId],
      );
      await db.execute(
        'UPDATE recurring_transactions SET account_id = NULL WHERE account_id = ? AND user_id = ?',
        [accountId, _userId],
      );
    }

    await db.execute(
      'DELETE FROM accounts WHERE id = ? AND user_id = ?',
      [accountId, _userId],
    );
    return true;
  }

  // ==================== DESCRIPTIONS ====================

  Future<List<Description>> getAllDescriptions() async {
    final db = await database;
    final rows = await db.query(
      'SELECT * FROM descriptions WHERE user_id = ? AND is_deleted = 0',
      [_userId],
    );
    final descriptions = <Description>[];
    for (final r in rows) {
      descriptions.add(Description(
        id: r['id'] as String?,
        userId: r['user_id'] as String,
        name: await _decryptValue(r['name']) ?? '',
        createdAt: r['created_at'] as String?,
      ));
    }
    descriptions.sort((a, b) => a.name.compareTo(b.name));
    return descriptions;
  }

  Future<String> getOrCreateDescription(String name) async {
    final normalized = name.trim();
    final cacheKey = normalized.toLowerCase();
    final cached = _descriptionCache[cacheKey];
    if (cached != null) return cached;

    final db = await database;
    final allDescs = await db.query(
      'SELECT id, name FROM descriptions WHERE user_id = ? AND is_deleted = 0',
      [_userId],
    );
    for (final row in allDescs) {
      final decrypted = await _decryptValue(row['name']);
      if (decrypted != null && decrypted.toLowerCase() == cacheKey) {
        final id = row['id'] as String;
        _descriptionCache[cacheKey] = id;
        return id;
      }
    }

    final id = _newId();
    final encryptedName = await _encrypt(normalized);
    await db.execute(
      'INSERT INTO descriptions (id, user_id, name) VALUES (?1, ?2, ?3)',
      [id, _userId, encryptedName],
    );
    _descriptionCache[cacheKey] = id;
    return id;
  }

  Future<bool> mergeDescriptions(String sourceName, String targetName) async {
    if (sourceName == targetName) return false;
    final db = await database;
    final sourceId = await getOrCreateDescription(sourceName);
    final targetId = await getOrCreateDescription(targetName);
    await db.execute(
      'UPDATE transactions SET description_id = ? WHERE description_id = ? AND user_id = ?',
      [targetId, sourceId, _userId],
    );
    await db.execute(
      'UPDATE recurring_transactions SET description_id = ? WHERE description_id = ? AND user_id = ?',
      [targetId, sourceId, _userId],
    );
    await db.execute(
      'DELETE FROM descriptions WHERE id = ? AND user_id = ?',
      [sourceId, _userId],
    );
    _descriptionCache.clear();
    return true;
  }

  Future<bool> renameDescription(String descriptionId, String newName) async {
    if (newName.trim().isEmpty) return false;
    final db = await database;
    final encryptedName = await _encrypt(newName.trim());
    final existing = await db.query(
      'SELECT id FROM descriptions WHERE id = ? AND user_id = ? AND is_deleted = 0',
      [descriptionId, _userId],
    );
    if (existing.isEmpty) return false;
    await db.execute(
      'UPDATE descriptions SET name = ? WHERE id = ? AND user_id = ?',
      [encryptedName, descriptionId, _userId],
    );
    _descriptionCache.clear();
    return true;
  }

  Future<void> cleanupUnusedDescriptions() async {
    if (_userId == null) return;
    final db = await database;
    await db.execute('''
      DELETE FROM descriptions
      WHERE user_id = ?
        AND is_deleted = 0
        AND id NOT IN (SELECT DISTINCT description_id FROM transactions WHERE user_id = ? AND is_deleted = 0)
        AND id NOT IN (SELECT DISTINCT description_id FROM recurring_transactions WHERE user_id = ? AND is_deleted = 0)
    ''', [_userId, _userId, _userId]);
    _descriptionCache.clear();
  }

  // ==================== TAGS ====================

  Future<String?> createTag({required String name, String color = '#1976D2'}) async {
    if (_userId == null) return null;
    final db = await database;
    final id = _newId();
    await db.execute(
      'INSERT INTO tags (id, user_id, name, color) VALUES (?1, ?2, ?3, ?4)',
      [id, _userId, name, color],
    );
    return id;
  }

  Future<List<Tag>> getAllTags() async {
    if (_userId == null) return [];
    final db = await database;
    final rows = await db.query(
      'SELECT * FROM tags WHERE user_id = ? AND is_deleted = 0 ORDER BY name ASC',
      [_userId],
    );
    return rows.map((r) => Tag.fromMap(r)).toList();
  }

  Future<bool> updateTag(String tagId, {String? name, String? color}) async {
    if (_userId == null) return false;
    final db = await database;
    final existing = await db.query(
      'SELECT id FROM tags WHERE id = ? AND user_id = ? AND is_deleted = 0',
      [tagId, _userId],
    );
    if (existing.isEmpty) return false;
    var sql = 'UPDATE tags SET';
    final args = <Object?>[];
    if (name != null) {
      sql += ' name = ?';
      args.add(name);
    }
    if (color != null) {
      if (args.isNotEmpty) sql += ',';
      sql += ' color = ?';
      args.add(color);
    }
    if (args.isEmpty) return false;
    sql += ' WHERE id = ? AND user_id = ?';
    args.add(tagId);
    args.add(_userId);
    await db.execute(sql, args);
    return true;
  }

  Future<bool> deleteTag(String tagId) async {
    if (_userId == null) return false;
    final db = await database;
    final existing = await db.query(
      'SELECT id FROM tags WHERE id = ? AND user_id = ? AND is_deleted = 0',
      [tagId, _userId],
    );
    if (existing.isEmpty) return false;
    await db.execute(
      'UPDATE transactions SET tag_id = NULL WHERE tag_id = ? AND user_id = ?',
      [tagId, _userId],
    );
    await db.execute('DELETE FROM tags WHERE id = ? AND user_id = ?', [tagId, _userId]);
    return true;
  }

  // ==================== TRANSACTIONS ====================

  Future<String?> getAccountCurrency(String accountId) async {
    final db = await database;
    final result = await db.query(
      'SELECT currency FROM accounts WHERE id = ? AND user_id = ? AND is_deleted = 0',
      [accountId, _userId],
    );
    if (result.isEmpty) return null;
    final curr = result.first['currency'] as String?;
    if (curr != null && CurrencyService.isValid(curr)) return curr;
    return null;
  }

  Future<String?> addTransaction({
    required String date,
    required String description,
    required double amount,
    required String transactionType,
    String? accountId,
    String? tagId,
    String? notes,
    String? currency,
  }) async {
    final db = await database;
    final descId = await getOrCreateDescription(description);

    String effectiveCurrency = currency ?? defaultCurrency;
    if (accountId != null) {
      final acctCurrency = await getAccountCurrency(accountId);
      if (acctCurrency != null) effectiveCurrency = acctCurrency;
    }

    final id = _newId();
    final encryptedAmount = await _encrypt(amount.toString());
    final encryptedNotes = await _encrypt(notes);

    await db.execute(
      'INSERT INTO transactions (id, user_id, account_id, description_id, tag_id, date, amount, transaction_type, currency, notes) '
      'VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10)',
      [id, _userId, accountId, descId, tagId, date, encryptedAmount, transactionType, effectiveCurrency, encryptedNotes],
    );
    return id;
  }

  Future<bool> updateTransaction(String transactionId, {
    String? date,
    String? description,
    double? amount,
    String? transactionType,
    String? accountId,
    String? tagId,
    bool clearTag = false,
    String? notes,
    String? currency,
  }) async {
    final db = await database;
    final existing = await db.query(
      'SELECT id FROM transactions WHERE id = ? AND user_id = ? AND is_deleted = 0',
      [transactionId, _userId],
    );
    if (existing.isEmpty) return false;

    final updates = <String, dynamic>{};
    if (date != null) updates['date'] = date;
    if (amount != null) updates['amount'] = await _encrypt(amount.toString());
    if (transactionType != null) updates['transaction_type'] = transactionType;
    if (accountId != null) updates['account_id'] = accountId;
    if (tagId != null) updates['tag_id'] = tagId;
    if (clearTag) updates['tag_id'] = null;
    if (notes != null) updates['notes'] = await _encrypt(notes);
    if (currency != null) updates['currency'] = currency;
    if (description != null) {
      updates['description_id'] = await getOrCreateDescription(description);
    }
    if (updates.isEmpty) return false;

    updates['updated_at'] = DateTime.now().toIso8601String();

    var sql = 'UPDATE transactions SET';
    final args = <Object?>[];
    var first = true;
    for (final entry in updates.entries) {
      if (!first) sql += ',';
      sql += ' ${entry.key} = ?';
      args.add(entry.value);
      first = false;
    }
    sql += ' WHERE id = ? AND user_id = ?';
    args.add(transactionId);
    args.add(_userId);
    await db.execute(sql, args);
    return true;
  }

  Future<bool> deleteTransaction(String transactionId) async {
    final db = await database;
    final existing = await db.query(
      'SELECT id FROM transactions WHERE id = ? AND user_id = ? AND is_deleted = 0',
      [transactionId, _userId],
    );
    if (existing.isEmpty) return false;
    await db.execute(
      'DELETE FROM transactions WHERE id = ? AND user_id = ?',
      [transactionId, _userId],
    );
    return true;
  }

  Future<List<TransactionWithDetails>> getTransactions({
    int? limit,
    int offset = 0,
    String searchQuery = '',
    Set<String>? accountIds,
    Set<String>? tagIds,
  }) async {
    final db = await database;
    var query = '''
      SELECT t.*, a.name as account_name, a.color as account_color,
             a.currency as account_currency, d.name as description_name,
             tg.name as tag_name, tg.color as tag_color,
             rt.frequency as recurring_frequency
      FROM transactions t
      LEFT JOIN accounts a ON t.account_id = a.id AND a.is_deleted = 0
      LEFT JOIN descriptions d ON t.description_id = d.id AND d.is_deleted = 0
      LEFT JOIN tags tg ON t.tag_id = tg.id AND tg.is_deleted = 0
      LEFT JOIN recurring_transactions rt ON t.recurring_id = rt.id AND rt.is_deleted = 0
      WHERE t.user_id = ? AND t.is_deleted = 0
      ORDER BY t.date DESC, t.id DESC
    ''';

    final rows = await db.query(query, [_userId]);

    final results = <TransactionWithDetails>[];
    final sq = searchQuery.toLowerCase();
    for (final r in rows) {
      final amount = await _decryptAmount(r['amount']);
      final notes = await _decryptValue(r['notes']);
      final accountName = await _decryptValue(r['account_name']);
      final descriptionName = await _decryptValue(r['description_name']);

      if (accountIds != null && accountIds.isNotEmpty) {
        final acctId = r['account_id'] as String?;
        if (acctId == null || !accountIds.contains(acctId)) continue;
      }

      if (tagIds != null && tagIds.isNotEmpty) {
        final txnTagId = r['tag_id'] as String?;
        if (txnTagId == null || !tagIds.contains(txnTagId)) continue;
      }

      if (searchQuery.isNotEmpty) {
        final descMatch = descriptionName?.toLowerCase().contains(sq) ?? false;
        final acctMatch = accountName?.toLowerCase().contains(sq) ?? false;
        final tagName = r['tag_name'] as String?;
        final tagMatch = tagName?.toLowerCase().contains(sq) ?? false;
        if (!descMatch && !acctMatch && !tagMatch) continue;
      }

      results.add(TransactionWithDetails(
        id: r['id'] as String?,
        userId: r['user_id'] as String,
        accountId: r['account_id'] as String?,
        descriptionId: r['description_id'] as String?,
        tagId: r['tag_id'] as String?,
        date: r['date'] as String,
        amount: amount,
        transactionType: r['transaction_type'] as String,
        currency: r['currency'] as String? ?? 'EUR',
        notes: notes,
        recurringId: r['recurring_id'] as String?,
        createdAt: r['created_at'] as String?,
        updatedAt: r['updated_at'] as String?,
        accountName: accountName,
        accountColor: r['account_color'] as String?,
        accountCurrency: r['account_currency'] as String?,
        descriptionName: descriptionName,
        tagName: r['tag_name'] as String?,
        tagColor: r['tag_color'] as String?,
        recurringFrequency: r['recurring_frequency'] as String?,
      ));

      if (limit != null && results.length >= limit + offset) break;
    }

    if (limit != null) {
      return results.skip(offset).take(limit).toList();
    }
    return results;
  }

  Future<List<TransactionWithDetails>> getTransactionsByPeriod(
      String startDate, String endDate) async {
    final db = await database;
    final rows = await db.query('''
      SELECT t.*, a.name as account_name, a.color as account_color,
             a.currency as account_currency, d.name as description_name,
             tg.name as tag_name, tg.color as tag_color,
             rt.frequency as recurring_frequency
      FROM transactions t
      LEFT JOIN accounts a ON t.account_id = a.id AND a.is_deleted = 0
      LEFT JOIN descriptions d ON t.description_id = d.id AND d.is_deleted = 0
      LEFT JOIN tags tg ON t.tag_id = tg.id AND tg.is_deleted = 0
      LEFT JOIN recurring_transactions rt ON t.recurring_id = rt.id AND rt.is_deleted = 0
      WHERE t.date BETWEEN ? AND ? AND t.user_id = ? AND t.is_deleted = 0
      ORDER BY t.date DESC
    ''', [startDate, endDate, _userId]);

    final results = <TransactionWithDetails>[];
    for (final r in rows) {
      results.add(TransactionWithDetails(
        id: r['id'] as String?,
        userId: r['user_id'] as String,
        accountId: r['account_id'] as String?,
        descriptionId: r['description_id'] as String?,
        tagId: r['tag_id'] as String?,
        date: r['date'] as String,
        amount: await _decryptAmount(r['amount']),
        transactionType: r['transaction_type'] as String,
        currency: r['currency'] as String? ?? 'EUR',
        notes: await _decryptValue(r['notes']),
        recurringId: r['recurring_id'] as String?,
        createdAt: r['created_at'] as String?,
        updatedAt: r['updated_at'] as String?,
        accountName: await _decryptValue(r['account_name']),
        accountColor: r['account_color'] as String?,
        accountCurrency: r['account_currency'] as String?,
        descriptionName: await _decryptValue(r['description_name']),
        tagName: r['tag_name'] as String?,
        tagColor: r['tag_color'] as String?,
        recurringFrequency: r['recurring_frequency'] as String?,
      ));
    }
    return results;
  }

  // ==================== RECURRING TRANSACTIONS ====================

  Future<String?> addRecurringTransaction({
    required String description,
    required double amount,
    required String transactionType,
    required String frequency,
    required String startDate,
    String? accountId,
    String? tagId,
    String? notes,
    String? currency,
    int interval = 1,
    int? dayOfWeek,
    int? dayOfMonth,
    String? endDate,
  }) async {
    final db = await database;
    final descId = await getOrCreateDescription(description);

    String effectiveCurrency = currency ?? defaultCurrency;
    if (accountId != null) {
      final acctCurrency = await getAccountCurrency(accountId);
      if (acctCurrency != null) effectiveCurrency = acctCurrency;
    }

    final start = DateTime.parse(startDate);
    final anchorDay = start.day;
    final computedDow = dayOfWeek ?? RecurringService.isoWeekday(start);
    final computedDom = dayOfMonth ?? anchorDay;

    final id = _newId();
    await db.execute(
      'INSERT INTO recurring_transactions (id, user_id, account_id, description_id, tag_id, amount, transaction_type, currency, notes, frequency, interval, day_of_week, day_of_month, start_date, end_date, next_due_date, active) '
      'VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13, ?14, ?15, ?16, ?17)',
      [
        id,
        _userId,
        accountId,
        descId,
        tagId,
        await _encrypt(amount.toString()),
        transactionType,
        effectiveCurrency,
        await _encrypt(notes),
        frequency,
        interval,
        frequency == 'weekly' ? computedDow : dayOfWeek,
        (frequency == 'monthly' || frequency == 'yearly') ? computedDom : dayOfMonth,
        startDate,
        endDate,
        startDate,
        1,
      ],
    );
    return id;
  }

  Future<bool> updateRecurringTransaction(String recurringId, {
    String? description,
    double? amount,
    String? transactionType,
    String? frequency,
    String? startDate,
    String? endDate,
    bool clearEndDate = false,
    String? accountId,
    String? tagId,
    bool clearTag = false,
    String? notes,
    String? currency,
    int? interval,
    int? dayOfWeek,
    int? dayOfMonth,
    bool? active,
  }) async {
    final db = await database;
    final existing = await db.query(
      'SELECT * FROM recurring_transactions WHERE id = ? AND user_id = ? AND is_deleted = 0',
      [recurringId, _userId],
    );
    if (existing.isEmpty) return false;
    final row = existing.first;

    final updates = <String, dynamic>{};
    if (amount != null) updates['amount'] = await _encrypt(amount.toString());
    if (transactionType != null) updates['transaction_type'] = transactionType;
    if (notes != null) updates['notes'] = await _encrypt(notes);
    if (currency != null) updates['currency'] = currency;
    if (accountId != null) updates['account_id'] = accountId;
    if (tagId != null) updates['tag_id'] = tagId;
    if (clearTag) updates['tag_id'] = null;
    if (endDate != null) updates['end_date'] = endDate;
    if (clearEndDate) updates['end_date'] = null;
    if (active != null) updates['active'] = active ? 1 : 0;
    if (description != null) {
      updates['description_id'] = await getOrCreateDescription(description);
    }

    final scheduleChanged = frequency != null ||
        interval != null ||
        dayOfWeek != null ||
        dayOfMonth != null ||
        startDate != null;

    if (frequency != null) updates['frequency'] = frequency;
    if (interval != null) updates['interval'] = interval;
    if (dayOfWeek != null) updates['day_of_week'] = dayOfWeek;
    if (dayOfMonth != null) updates['day_of_month'] = dayOfMonth;
    if (startDate != null) updates['start_date'] = startDate;

    if (scheduleChanged) {
      final rec = _recurringFromRow(row);
      final effective = RecurringTransaction(
        userId: rec.userId,
        accountId: rec.accountId,
        descriptionId: rec.descriptionId,
        tagId: rec.tagId,
        amount: rec.amount,
        transactionType: transactionType ?? rec.transactionType,
        currency: rec.currency,
        notes: rec.notes,
        frequency: frequency ?? rec.frequency,
        interval: interval ?? rec.interval,
        dayOfWeek: dayOfWeek ?? rec.dayOfWeek,
        dayOfMonth: dayOfMonth ?? rec.dayOfMonth,
        startDate: startDate ?? rec.startDate,
        endDate: clearEndDate ? null : (endDate ?? rec.endDate),
        nextDueDate: rec.nextDueDate,
        active: rec.active,
      );
      final nextDue = RecurringService.firstOccurrenceOnOrAfter(
          effective, DateTime.now());
      if (nextDue != null) {
        updates['next_due_date'] = RecurringService.dateOnly(nextDue);
        updates['active'] = 1;
      }
    }

    if (updates.isEmpty) return false;
    updates['updated_at'] = DateTime.now().toIso8601String();

    var sql = 'UPDATE recurring_transactions SET';
    final args = <Object?>[];
    var first = true;
    for (final entry in updates.entries) {
      if (!first) sql += ',';
      sql += ' ${entry.key} = ?';
      args.add(entry.value);
      first = false;
    }
    sql += ' WHERE id = ? AND user_id = ?';
    args.add(recurringId);
    args.add(_userId);
    await db.execute(sql, args);
    return true;
  }

  Future<bool> toggleRecurringActive(String recurringId, bool active) async {
    final db = await database;
    final existing = await db.query(
      'SELECT id FROM recurring_transactions WHERE id = ? AND user_id = ? AND is_deleted = 0',
      [recurringId, _userId],
    );
    if (existing.isEmpty) return false;
    await db.execute(
      'UPDATE recurring_transactions SET active = ?, updated_at = ? WHERE id = ? AND user_id = ?',
      [active ? 1 : 0, DateTime.now().toIso8601String(), recurringId, _userId],
    );
    return true;
  }

  Future<bool> deleteRecurringTransaction(String recurringId,
      {bool deleteOccurrences = true}) async {
    final db = await database;
    final existing = await db.query(
      'SELECT id FROM recurring_transactions WHERE id = ? AND user_id = ? AND is_deleted = 0',
      [recurringId, _userId],
    );
    if (existing.isEmpty) return false;
    if (deleteOccurrences) {
      await db.execute(
        'DELETE FROM transactions WHERE recurring_id = ? AND user_id = ?',
        [recurringId, _userId],
      );
    }
    await db.execute('DELETE FROM recurring_exceptions WHERE recurring_id = ?', [recurringId]);
    await db.execute(
      'DELETE FROM recurring_transactions WHERE id = ? AND user_id = ?',
      [recurringId, _userId],
    );
    return true;
  }

  Future<void> _deleteRecurringWithChildren(SqliteCrdt db, String recurringId) async {
    await db.execute(
      'DELETE FROM transactions WHERE recurring_id = ? AND user_id = ?',
      [recurringId, _userId],
    );
    await db.execute('DELETE FROM recurring_exceptions WHERE recurring_id = ?', [recurringId]);
    await db.execute(
      'DELETE FROM recurring_transactions WHERE id = ? AND user_id = ?',
      [recurringId, _userId],
    );
  }

  Future<void> markRecurringOccurrenceDeleted(String recurringId, String date) async {
    final db = await database;
    await db.execute(
      'INSERT OR REPLACE INTO recurring_exceptions (id, recurring_id, date) VALUES (?1, ?2, ?3)',
      [_newId(), recurringId, date],
    );
  }

  Future<void> clearRecurringOccurrenceDeleted(String recurringId, String date) async {
    final db = await database;
    await db.execute(
      'DELETE FROM recurring_exceptions WHERE recurring_id = ? AND date = ?',
      [recurringId, date],
    );
  }

  RecurringTransaction _recurringFromRow(Map<String, Object?> row) {
    return RecurringTransaction(
      id: row['id'] as String?,
      userId: row['user_id'] as String,
      accountId: row['account_id'] as String?,
      descriptionId: row['description_id'] as String?,
      tagId: row['tag_id'] as String?,
      amount: (row['amount'] is num) ? (row['amount'] as num).toDouble() : 0,
      transactionType: row['transaction_type'] as String,
      currency: row['currency'] as String? ?? 'EUR',
      notes: row['notes'] is String ? (row['notes'] as String) : null,
      frequency: row['frequency'] as String,
      interval: row['interval'] as int? ?? 1,
      dayOfWeek: row['day_of_week'] as int?,
      dayOfMonth: row['day_of_month'] as int?,
      startDate: row['start_date'] as String,
      endDate: row['end_date'] as String?,
      nextDueDate: row['next_due_date'] as String,
      active: (row['active'] as int? ?? 1) == 1,
      createdAt: row['created_at'] as String?,
      updatedAt: row['updated_at'] as String?,
    );
  }

  Future<RecurringTransactionWithDetails?> getRecurringTransaction(
      String recurringId) async {
    final db = await database;
    final rows = await db.query('''
      SELECT r.*, a.name as account_name, a.color as account_color,
             a.currency as account_currency, d.name as description_name,
             tg.name as tag_name, tg.color as tag_color,
             (SELECT COUNT(*) FROM transactions t WHERE t.recurring_id = r.id AND t.is_deleted = 0) as generated_count
      FROM recurring_transactions r
      LEFT JOIN accounts a ON r.account_id = a.id AND a.is_deleted = 0
      LEFT JOIN descriptions d ON r.description_id = d.id AND d.is_deleted = 0
      LEFT JOIN tags tg ON r.tag_id = tg.id AND tg.is_deleted = 0
      WHERE r.id = ? AND r.user_id = ? AND r.is_deleted = 0
    ''', [recurringId, _userId]);
    if (rows.isEmpty) return null;
    final r = rows.first;
    return RecurringTransactionWithDetails(
      id: r['id'] as String?,
      userId: r['user_id'] as String,
      accountId: r['account_id'] as String?,
      descriptionId: r['description_id'] as String?,
      tagId: r['tag_id'] as String?,
      amount: await _decryptAmount(r['amount']),
      transactionType: r['transaction_type'] as String,
      currency: r['currency'] as String? ?? 'EUR',
      notes: await _decryptValue(r['notes']),
      frequency: r['frequency'] as String,
      interval: r['interval'] as int? ?? 1,
      dayOfWeek: r['day_of_week'] as int?,
      dayOfMonth: r['day_of_month'] as int?,
      startDate: r['start_date'] as String,
      endDate: r['end_date'] as String?,
      nextDueDate: r['next_due_date'] as String,
      active: (r['active'] as int? ?? 1) == 1,
      createdAt: r['created_at'] as String?,
      updatedAt: r['updated_at'] as String?,
      accountName: await _decryptValue(r['account_name']),
      accountColor: r['account_color'] as String?,
      accountCurrency: r['account_currency'] as String?,
      descriptionName: await _decryptValue(r['description_name']),
      tagName: r['tag_name'] as String?,
      tagColor: r['tag_color'] as String?,
      generatedCount: r['generated_count'] as int? ?? 0,
    );
  }

  Future<List<RecurringTransactionWithDetails>> getRecurringTransactions() async {
    final db = await database;
    final rows = await db.query('''
      SELECT r.*, a.name as account_name, a.color as account_color,
             a.currency as account_currency, d.name as description_name,
             tg.name as tag_name, tg.color as tag_color,
             (SELECT COUNT(*) FROM transactions t WHERE t.recurring_id = r.id AND t.is_deleted = 0) as generated_count
      FROM recurring_transactions r
      LEFT JOIN accounts a ON r.account_id = a.id AND a.is_deleted = 0
      LEFT JOIN descriptions d ON r.description_id = d.id AND d.is_deleted = 0
      LEFT JOIN tags tg ON r.tag_id = tg.id AND tg.is_deleted = 0
      WHERE r.user_id = ? AND r.is_deleted = 0
      ORDER BY r.next_due_date ASC, r.id DESC
    ''', [_userId]);

    final results = <RecurringTransactionWithDetails>[];
    for (final r in rows) {
      results.add(RecurringTransactionWithDetails(
        id: r['id'] as String?,
        userId: r['user_id'] as String,
        accountId: r['account_id'] as String?,
        descriptionId: r['description_id'] as String?,
        tagId: r['tag_id'] as String?,
        amount: await _decryptAmount(r['amount']),
        transactionType: r['transaction_type'] as String,
        currency: r['currency'] as String? ?? 'EUR',
        notes: await _decryptValue(r['notes']),
        frequency: r['frequency'] as String,
        interval: r['interval'] as int? ?? 1,
        dayOfWeek: r['day_of_week'] as int?,
        dayOfMonth: r['day_of_month'] as int?,
        startDate: r['start_date'] as String,
        endDate: r['end_date'] as String?,
        nextDueDate: r['next_due_date'] as String,
        active: (r['active'] as int? ?? 1) == 1,
        createdAt: r['created_at'] as String?,
        updatedAt: r['updated_at'] as String?,
        accountName: await _decryptValue(r['account_name']),
        accountColor: r['account_color'] as String?,
        accountCurrency: r['account_currency'] as String?,
        descriptionName: await _decryptValue(r['description_name']),
        tagName: r['tag_name'] as String?,
        tagColor: r['tag_color'] as String?,
        generatedCount: r['generated_count'] as int? ?? 0,
      ));
    }
    return results;
  }

  /// Generates due occurrences for all active recurring templates of the
  /// current user. Idempotent: occurrences that already exist (or were
  /// explicitly deleted) are never recreated.
  Future<void> generateDueRecurring() async {
    if (_userId == null) return;
    if (_encryptionKey == null) return;
    final db = await database;
    final rows = await db.query(
      'SELECT * FROM recurring_transactions WHERE user_id = ? AND active = 1 AND is_deleted = 0',
      [_userId],
    );
    for (final row in rows) {
      final base = _recurringFromRow(row);
      final rec = RecurringTransaction(
        id: base.id,
        userId: base.userId,
        accountId: base.accountId,
        descriptionId: base.descriptionId,
        tagId: base.tagId,
        amount: await _decryptAmount(row['amount']),
        transactionType: base.transactionType,
        currency: base.currency,
        notes: await _decryptValue(row['notes']),
        frequency: base.frequency,
        interval: base.interval,
        dayOfWeek: base.dayOfWeek,
        dayOfMonth: base.dayOfMonth,
        startDate: base.startDate,
        endDate: base.endDate,
        nextDueDate: base.nextDueDate,
        active: base.active,
      );
      await _generateForTemplate(db, rec);
    }
  }

  Future<void> _generateForTemplate(
      SqliteCrdt db, RecurringTransaction rec) async {
    final id = rec.id;
    if (id == null) return;

    final existingRows = await db.query(
      'SELECT id, date, amount FROM transactions WHERE recurring_id = ? AND user_id = ? AND is_deleted = 0',
      [id, _userId],
    );
    final existingDates = existingRows.map((r) => r['date'] as String).toSet();

    // Repair occurrences whose amount was written while the encryption key was
    // unavailable (the null-key generation bug stored an unencrypted 0). Only
    // rewrite when the stored value is a plaintext zero that does not decrypt,
    // so legitimately edited occurrences are left untouched.
    final correctAmount = await _encrypt(rec.amount.toString());
    for (final existing in existingRows) {
      if (await _isUnencryptedZeroAmount(existing['amount'])) {
        await db.execute(
          'UPDATE transactions SET amount = ?, updated_at = CURRENT_TIMESTAMP WHERE id = ? AND user_id = ?',
          [correctAmount, existing['id'], _userId],
        );
      }
    }

    final exceptionRows = await db.query(
      'SELECT date FROM recurring_exceptions WHERE recurring_id = ? AND is_deleted = 0',
      [id],
    );
    final exceptionDates = exceptionRows.map((r) => r['date'] as String).toSet();

    final plan = RecurringService.planGeneration(
      rec,
      existingDates: existingDates,
      exceptionDates: exceptionDates,
      today: DateTime.now(),
    );

    for (final dateStr in plan.dueDates) {
      await db.execute(
        'INSERT INTO transactions (id, user_id, account_id, description_id, tag_id, date, amount, transaction_type, currency, notes, recurring_id) '
        'VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11)',
        [
          _newId(),
          rec.userId,
          rec.accountId,
          rec.descriptionId,
          rec.tagId,
          dateStr,
          await _encrypt(rec.amount.toString()),
          rec.transactionType,
          rec.currency,
          await _encrypt(rec.notes),
          id,
        ],
      );
    }

    if (plan.ended) {
      await db.execute(
        'UPDATE recurring_transactions SET active = 0, next_due_date = ? WHERE id = ?',
        [plan.nextDueDate, id],
      );
    } else {
      await db.execute(
        'UPDATE recurring_transactions SET next_due_date = ? WHERE id = ?',
        [plan.nextDueDate, id],
      );
    }
  }

  /// True when [raw] is the null-key generation corruption: a plaintext zero
  /// that does not decrypt under the current key.
  Future<bool> _isUnencryptedZeroAmount(dynamic raw) async {
    if (_encryptionKey == null) return false;
    if (raw is num) return raw.toDouble() == 0.0;
    final s = raw?.toString() ?? '';
    if (s.isEmpty) return false;
    final decrypted = await _decrypt(s);
    if (decrypted != null && decrypted != s) return false;
    final v = double.tryParse(s);
    return v != null && v == 0.0;
  }

  // ==================== STATISTICS ====================

  Future<double> getTotalPatrimony({String targetCurrency = 'EUR'}) async {
    final db = await database;
    final acctRows = await db.query(
      'SELECT starting_amount, currency FROM accounts WHERE user_id = ? AND is_deleted = 0',
      [_userId],
    );

    double total = 0.0;
    for (final row in acctRows) {
      final amount = await _decryptAmount(row['starting_amount']);
      final acctCurrency = (row['currency'] as String?) ?? 'EUR';
      if (amount == 0) continue;
      if (acctCurrency == targetCurrency) {
        total += amount;
      } else {
        final rate = await getExchangeRate(acctCurrency, targetCurrency);
        total += amount * (rate ?? 1.0);
      }
    }

    final txnRows = await db.query(
      'SELECT t.amount, t.transaction_type, COALESCE(NULLIF(a.currency, \'\'), \'EUR\') as currency '
      'FROM transactions t LEFT JOIN accounts a ON t.account_id = a.id AND a.is_deleted = 0 '
      'WHERE t.user_id = ? AND t.is_deleted = 0',
      [_userId],
    );

    for (final row in txnRows) {
      final amount = await _decryptAmount(row['amount']);
      final type = row['transaction_type'] as String;
      final txnCurrency = (row['currency'] as String?) ?? 'EUR';
      final signedAmount = type == 'income' ? amount : (type == 'expense' ? -amount : 0.0);
      if (signedAmount == 0) continue;
      if (txnCurrency == targetCurrency) {
        total += signedAmount;
      } else {
        final rate = await getExchangeRate(txnCurrency, targetCurrency);
        total += signedAmount * (rate ?? 1.0);
      }
    }
    return total;
  }

  Future<double> getBalance({String targetCurrency = 'EUR', String? before}) async {
    final db = await database;

    final acctRows = await db.query(
      'SELECT starting_amount, currency FROM accounts WHERE type = ? AND user_id = ? AND is_deleted = 0',
      ['checking', _userId],
    );

    double total = 0.0;
    for (final row in acctRows) {
      final amount = await _decryptAmount(row['starting_amount']);
      final acctCurrency = (row['currency'] as String?) ?? 'EUR';
      if (amount == 0) continue;
      if (acctCurrency == targetCurrency) {
        total += amount;
      } else {
        final rate = await getExchangeRate(acctCurrency, targetCurrency);
        total += amount * (rate ?? 1.0);
      }
    }

    final txnRows = await db.query(
      'SELECT t.amount, t.transaction_type, t.account_id, '
      'COALESCE(NULLIF(a.currency, \'\'), \'EUR\') as currency, a.type as account_type '
      'FROM transactions t LEFT JOIN accounts a ON t.account_id = a.id AND a.is_deleted = 0 '
      'WHERE t.user_id = ? AND t.is_deleted = 0'
      '${before != null ? ' AND t.date < ?' : ''}',
      before != null ? [_userId, before] : [_userId],
    );

    for (final row in txnRows) {
      final accountType = row['account_type'] as String?;
      final hasAccount = row['account_id'] != null;
      if (accountType != 'checking' && hasAccount) continue;

      final amount = await _decryptAmount(row['amount']);
      final type = row['transaction_type'] as String;
      final txnCurrency = (row['currency'] as String?) ?? 'EUR';
      final signedAmount = type == 'income' ? amount : (type == 'expense' ? -amount : 0.0);
      if (signedAmount == 0) continue;
      if (txnCurrency == targetCurrency) {
        total += signedAmount;
      } else {
        final rate = await getExchangeRate(txnCurrency, targetCurrency);
        total += signedAmount * (rate ?? 1.0);
      }
    }
    return total;
  }

  Future<double> getSavingsTotal({String targetCurrency = 'EUR', String? before}) async {
    final db = await database;

    final acctRows = await db.query(
      'SELECT starting_amount, currency FROM accounts WHERE type = ? AND user_id = ? AND is_deleted = 0',
      ['savings', _userId],
    );

    double total = 0.0;
    for (final row in acctRows) {
      final amount = await _decryptAmount(row['starting_amount']);
      final acctCurrency = (row['currency'] as String?) ?? 'EUR';
      if (amount == 0) continue;
      if (acctCurrency == targetCurrency) {
        total += amount;
      } else {
        final rate = await getExchangeRate(acctCurrency, targetCurrency);
        total += amount * (rate ?? 1.0);
      }
    }

    final txnRows = await db.query(
      'SELECT t.amount, t.transaction_type, '
      'COALESCE(NULLIF(a.currency, \'\'), \'EUR\') as currency '
      'FROM transactions t LEFT JOIN accounts a ON t.account_id = a.id AND a.is_deleted = 0 '
      'WHERE a.type = ? AND t.user_id = ? AND t.is_deleted = 0'
      '${before != null ? ' AND t.date < ?' : ''}',
      before != null ? ['savings', _userId, before] : ['savings', _userId],
    );

    for (final row in txnRows) {
      final amount = await _decryptAmount(row['amount']);
      final type = row['transaction_type'] as String;
      final txnCurrency = (row['currency'] as String?) ?? 'EUR';
      final signedAmount = type == 'income' ? amount : (type == 'expense' ? -amount : 0.0);
      if (signedAmount == 0) continue;
      if (txnCurrency == targetCurrency) {
        total += signedAmount;
      } else {
        final rate = await getExchangeRate(txnCurrency, targetCurrency);
        total += signedAmount * (rate ?? 1.0);
      }
    }
    return total;
  }

  Future<Map<String, double>> getMonthlySummary({int? year, int? month, String targetCurrency = 'EUR'}) async {
    final now = DateTime.now();
    final y = year ?? now.year;
    final m = month ?? now.month;
    final startDate = '$y-${m.toString().padLeft(2, '0')}-01';
    final endMonth = m == 12 ? 1 : m + 1;
    final endYear = m == 12 ? y + 1 : y;
    final endDate = '$endYear-${endMonth.toString().padLeft(2, '0')}-01';

    final db = await database;
    final txnRows = await db.query(
      'SELECT t.amount, t.transaction_type, t.account_id, '
      'COALESCE(NULLIF(a.currency, \'\'), \'EUR\') as currency, a.type as account_type, '
      'd.name as description_name '
      'FROM transactions t LEFT JOIN accounts a ON t.account_id = a.id AND a.is_deleted = 0 '
      'LEFT JOIN descriptions d ON t.description_id = d.id AND d.is_deleted = 0 '
      'WHERE t.date >= ? AND t.date < ? AND t.user_id = ? AND t.is_deleted = 0',
      [startDate, endDate, _userId],
    );

    double income = 0.0;
    double expenses = 0.0;
    for (final row in txnRows) {
      final accountType = row['account_type'] as String?;
      final hasAccount = row['account_id'] != null;
      if (accountType != 'checking' && hasAccount) continue;

      final desc = await _decryptValue(row['description_name']);
      if (desc != null && _isTransferDescription(desc)) continue;

      final amount = await _decryptAmount(row['amount']);
      final type = row['transaction_type'] as String;
      final txnCurrency = (row['currency'] as String?) ?? 'EUR';

      double convertedAmount;
      if (txnCurrency == targetCurrency) {
        convertedAmount = amount;
      } else {
        final rate = await getExchangeRate(txnCurrency, targetCurrency);
        convertedAmount = amount * (rate ?? 1.0);
      }

      if (type == 'income') {
        income += convertedAmount;
      } else if (type == 'expense') {
        expenses += convertedAmount;
      }
    }
    return {'income': income, 'expenses': expenses, 'balance': income - expenses};
  }

  Future<Map<String, double>> getRollingSummary({int days = 30, String targetCurrency = 'EUR'}) async {
    final now = DateTime.now();
    final endDate = now.toIso8601String().substring(0, 10);
    final startDate = now.subtract(Duration(days: days)).toIso8601String().substring(0, 10);

    final db = await database;
    final txnRows = await db.query(
      'SELECT t.amount, t.transaction_type, t.account_id, '
      'COALESCE(NULLIF(a.currency, \'\'), \'EUR\') as currency, a.type as account_type, '
      'd.name as description_name '
      'FROM transactions t LEFT JOIN accounts a ON t.account_id = a.id AND a.is_deleted = 0 '
      'LEFT JOIN descriptions d ON t.description_id = d.id AND d.is_deleted = 0 '
      'WHERE t.date >= ? AND t.date <= ? AND t.user_id = ? AND t.is_deleted = 0',
      [startDate, endDate, _userId],
    );

    double income = 0.0;
    double expenses = 0.0;
    for (final row in txnRows) {
      final accountType = row['account_type'] as String?;
      final hasAccount = row['account_id'] != null;
      if (accountType != 'checking' && hasAccount) continue;

      final desc = await _decryptValue(row['description_name']);
      if (desc != null && _isTransferDescription(desc)) continue;

      final amount = await _decryptAmount(row['amount']);
      final type = row['transaction_type'] as String;
      final txnCurrency = (row['currency'] as String?) ?? 'EUR';

      double convertedAmount;
      if (txnCurrency == targetCurrency) {
        convertedAmount = amount;
      } else {
        final rate = await getExchangeRate(txnCurrency, targetCurrency);
        convertedAmount = amount * (rate ?? 1.0);
      }

      if (type == 'income') {
        income += convertedAmount;
      } else if (type == 'expense') {
        expenses += convertedAmount;
      }
    }
    return {'income': income, 'expenses': expenses, 'balance': income - expenses};
  }

  Future<List<Map<String, dynamic>>> getAccountsDistribution({String targetCurrency = 'EUR'}) async {
    final db = await database;
    final acctRows = await db.query(
      'SELECT * FROM accounts WHERE user_id = ? AND is_deleted = 0 ORDER BY name',
      [_userId],
    );

    final txnRows = await db.query(
      'SELECT transaction_type, amount, account_id FROM transactions WHERE user_id = ? AND is_deleted = 0',
      [_userId],
    );
    final txnByAccount = <String, List<Map<String, Object?>>>{};
    for (final t in txnRows) {
      final acctId = t['account_id'] as String?;
      if (acctId == null) continue;
      (txnByAccount[acctId] ??= []).add(t);
    }

    final results = <Map<String, dynamic>>[];
    for (final acctRow in acctRows) {
      final startingAmount = await _decryptAmount(acctRow['starting_amount']);

      double balance = startingAmount;
      for (final txn in txnByAccount[acctRow['id']] ?? const <Map<String, Object?>>[]) {
        final amount = await _decryptAmount(txn['amount']);
        final type = txn['transaction_type'] as String;
        if (type == 'income') {
          balance += amount;
        } else if (type == 'expense') {
          balance -= amount;
        }
      }

      final acctCurrency = (acctRow['currency'] as String?) ?? 'EUR';

      double convertedBalance;
      if (acctCurrency == targetCurrency) {
        convertedBalance = balance;
      } else {
        final rate = await getExchangeRate(acctCurrency, targetCurrency);
        convertedBalance = balance * (rate ?? 1.0);
      }

      results.add({
        'name': await _decryptValue(acctRow['name']),
        'color': acctRow['color'],
        'value': convertedBalance,
        'nativeValue': balance,
        'currency': acctCurrency,
      });
    }
    return results;
  }

  Future<Map<String, Map<String, Map<String, double>>>> getDescriptionMonthlyData(
      String startDate, String endDate) async {
    final db = await database;
    final rows = await db.query('''
      SELECT t.amount, t.transaction_type, t.date,
             d.name as description_name
      FROM transactions t
      LEFT JOIN descriptions d ON t.description_id = d.id AND d.is_deleted = 0
      WHERE t.date >= ? AND t.date <= ? AND t.user_id = ? AND t.is_deleted = 0
    ''', [startDate, endDate, _userId]);

    final result = <String, Map<String, Map<String, double>>>{};
    for (final row in rows) {
      final desc = await _decryptValue(row['description_name']) ?? 'uncategorized';
      final month = (row['date'] as String).substring(0, 7);
      final type = row['transaction_type'] as String;
      final total = await _decryptAmount(row['amount']);

      if (_isTransferDescription(desc)) continue;

      result.putIfAbsent(desc, () => {});
      result[desc]!.putIfAbsent(month, () => {'income': 0, 'expense': 0, 'total': 0});

      if (type == 'income') {
        result[desc]![month]!['income'] = result[desc]![month]!['income']! + total;
      } else if (type == 'expense') {
        result[desc]![month]!['expense'] = result[desc]![month]!['expense']! + total;
      }
      result[desc]![month]!['total'] = result[desc]![month]!['total']! + total;
    }
    return result;
  }

  Future<List<Map<String, dynamic>>> getTopDescriptions({
    String transactionType = 'expense',
    int numMonths = 6,
    int limit = 5,
    int minCount = 1,
  }) async {
    final db = await database;
    final now = DateTime.now();
    final startDate = now.subtract(Duration(days: numMonths * 30)).toIso8601String().substring(0, 10);
    final endDate = now.toIso8601String().substring(0, 10);

    final rows = await db.query('''
      SELECT t.amount, d.name as description_name
      FROM transactions t
      LEFT JOIN descriptions d ON t.description_id = d.id AND d.is_deleted = 0
      WHERE t.transaction_type = ? AND t.date >= ? AND t.date <= ? AND t.user_id = ? AND t.is_deleted = 0
    ''', [transactionType, startDate, endDate, _userId]);

    final byDesc = <String, Map<String, dynamic>>{};
    for (final row in rows) {
      final desc = await _decryptValue(row['description_name']) ?? 'Uncategorized';
      if (_isTransferDescription(desc)) continue;
      final amount = await _decryptAmount(row['amount']);

      if (!byDesc.containsKey(desc)) {
        byDesc[desc] = {'total': 0.0, 'count': 0};
      }
      byDesc[desc]!['total'] = (byDesc[desc]!['total'] as double) + amount;
      byDesc[desc]!['count'] = (byDesc[desc]!['count'] as int) + 1;
    }

    final sorted = byDesc.entries.toList()
      ..sort((a, b) => (b.value['total'] as double).compareTo(a.value['total'] as double));

    final results = <Map<String, dynamic>>[];
    for (final entry in sorted) {
      if ((entry.value['count'] as int) >= minCount) {
        results.add({'description': entry.key, 'total': entry.value['total'], 'count': entry.value['count']});
        if (limit > 0 && results.length >= limit) break;
      }
    }
    return results;
  }

  bool _isTransferDescription(String? description) {
    final desc = (description ?? '').trim().toLowerCase();
    const prefixes = ['transfer to ', 'transfer from '];
    return prefixes.any((p) => desc.startsWith(p));
  }

  Future<List<Map<String, dynamic>>> getTopTags({
    String transactionType = 'expense',
    int numMonths = 6,
    int limit = 5,
    int minCount = 1,
  }) async {
    final db = await database;
    final now = DateTime.now();
    final startDate = now.subtract(Duration(days: numMonths * 30)).toIso8601String().substring(0, 10);
    final endDate = now.toIso8601String().substring(0, 10);

    final rows = await db.query('''
      SELECT t.amount, tg.name as tag_name
      FROM transactions t
      LEFT JOIN tags tg ON t.tag_id = tg.id AND tg.is_deleted = 0
      WHERE t.transaction_type = ? AND t.date >= ? AND t.date <= ? AND t.user_id = ?
        AND t.tag_id IS NOT NULL AND t.is_deleted = 0
    ''', [transactionType, startDate, endDate, _userId]);

    final byTag = <String, Map<String, dynamic>>{};
    for (final row in rows) {
      final tag = row['tag_name'] as String? ?? 'Untagged';
      final amount = await _decryptAmount(row['amount']);

      if (!byTag.containsKey(tag)) {
        byTag[tag] = {'total': 0.0, 'count': 0};
      }
      byTag[tag]!['total'] = (byTag[tag]!['total'] as double) + amount;
      byTag[tag]!['count'] = (byTag[tag]!['count'] as int) + 1;
    }

    final sorted = byTag.entries.toList()
      ..sort((a, b) => (b.value['total'] as double).compareTo(a.value['total'] as double));

    final results = <Map<String, dynamic>>[];
    for (final entry in sorted) {
      if ((entry.value['count'] as int) >= minCount) {
        results.add({'tag': entry.key, 'total': entry.value['total'], 'count': entry.value['count']});
        if (limit > 0 && results.length >= limit) break;
      }
    }
    return results;
  }

  Future<Map<String, Map<String, Map<String, double>>>> getTagMonthlyData(
      String startDate, String endDate) async {
    final db = await database;
    final rows = await db.query('''
      SELECT t.amount, t.transaction_type, t.date,
             tg.name as tag_name
      FROM transactions t
      LEFT JOIN tags tg ON t.tag_id = tg.id AND tg.is_deleted = 0
      WHERE t.date >= ? AND t.date <= ? AND t.user_id = ? AND t.is_deleted = 0
        AND t.tag_id IS NOT NULL
    ''', [startDate, endDate, _userId]);

    final result = <String, Map<String, Map<String, double>>>{};
    for (final row in rows) {
      final tag = row['tag_name'] as String? ?? 'Untagged';
      final month = (row['date'] as String).substring(0, 7);
      final type = row['transaction_type'] as String;
      final total = await _decryptAmount(row['amount']);

      result.putIfAbsent(tag, () => {});
      result[tag]!.putIfAbsent(month, () => {'income': 0, 'expense': 0, 'total': 0});

      if (type == 'income') {
        result[tag]![month]!['income'] = result[tag]![month]!['income']! + total;
      } else if (type == 'expense') {
        result[tag]![month]!['expense'] = result[tag]![month]!['expense']! + total;
      }
      result[tag]![month]!['total'] = result[tag]![month]!['total']! + total;
    }
    return result;
  }

  // ==================== DASHBOARD DATA ====================

  Future<List<Map<String, dynamic>>> getCashFlowData({int months = 6, String targetCurrency = 'EUR'}) async {
    final db = await database;
    final now = DateTime.now();
    final startDate = DateTime(now.year, now.month - months + 1, 1)
        .toIso8601String()
        .substring(0, 10);

    final rows = await db.query(
      'SELECT t.amount, t.transaction_type, t.date, '
      'd.name as description_name, '
      'COALESCE(NULLIF(a.currency, \'\'), \'EUR\') as currency '
      'FROM transactions t '
      'LEFT JOIN accounts a ON t.account_id = a.id AND a.is_deleted = 0 '
      'LEFT JOIN descriptions d ON t.description_id = d.id AND d.is_deleted = 0 '
      'WHERE t.date >= ? AND t.user_id = ? AND t.is_deleted = 0',
      [startDate, _userId],
    );

    final monthMap = <String, Map<String, double>>{};
    for (final r in rows) {
      final desc = await _decryptValue(r['description_name']);
      if (desc != null && _isTransferDescription(desc)) continue;

      final monthKey = (r['date'] as String).substring(0, 7);
      final type = r['transaction_type'] as String;
      final amount = await _decryptAmount(r['amount']);
      final txnCurrency = (r['currency'] as String?) ?? 'EUR';

      double convertedAmount;
      if (txnCurrency == targetCurrency) {
        convertedAmount = amount;
      } else {
        final rate = await getExchangeRate(txnCurrency, targetCurrency);
        convertedAmount = amount * (rate ?? 1.0);
      }

      monthMap.putIfAbsent(monthKey, () => {});
      monthMap[monthKey]![type] = (monthMap[monthKey]![type] ?? 0) + convertedAmount;
    }

    final results = <Map<String, dynamic>>[];
    for (final entry in monthMap.entries) {
      for (final typeEntry in entry.value.entries) {
        results.add({
          'month': entry.key,
          'type': typeEntry.key,
          'amount': typeEntry.value,
        });
      }
    }
    return results;
  }

  Future<List<Map<String, dynamic>>> getAssetsHistory({
    int months = 6,
    String targetCurrency = 'EUR',
    String granularity = 'monthly',
  }) async {
    final db = await database;
    final now = DateTime.now();

    final earliestResult = await db.query(
      'SELECT MIN(date) as earliest FROM transactions WHERE user_id = ? AND is_deleted = 0',
      [_userId],
    );
    final earliestDate = earliestResult.first['earliest'] as String?;

    int effectiveMonths = months;
    if (earliestDate != null) {
      final earliest = DateTime.parse(earliestDate);
      final earliestMonth = DateTime(earliest.year, earliest.month, 1);
      final requestedStart = DateTime(now.year, now.month - months + 1, 1);
      if (earliestMonth.isAfter(requestedStart)) {
        final diff = (now.year - earliestMonth.year) * 12 + (now.month - earliestMonth.month) + 1;
        effectiveMonths = diff.clamp(1, months);
      }
    }

    final acctRows = await db.query(
      'SELECT starting_amount, currency FROM accounts WHERE user_id = ? AND is_deleted = 0',
      [_userId],
    );

    double startingTotal = 0.0;
    for (final row in acctRows) {
      final amount = await _decryptAmount(row['starting_amount']);
      final acctCurrency = (row['currency'] as String?) ?? 'EUR';
      if (amount == 0) continue;
      if (acctCurrency == targetCurrency) {
        startingTotal += amount;
      } else {
        final rate = await getExchangeRate(acctCurrency, targetCurrency);
        startingTotal += amount * (rate ?? 1.0);
      }
    }

    final nowNextMonth = DateTime(now.year, now.month + 1, 1)
        .toIso8601String()
        .substring(0, 10);
    final txnRows = await db.query(
      'SELECT t.amount, t.transaction_type, t.date, '
      'COALESCE(NULLIF(a.currency, \'\'), \'EUR\') as currency '
      'FROM transactions t LEFT JOIN accounts a ON t.account_id = a.id AND a.is_deleted = 0 '
      'WHERE t.date < ? AND t.user_id = ? AND t.is_deleted = 0',
      [nowNextMonth, _userId],
    );

    final contributions = <(String, double)>[];
    for (final row in txnRows) {
      final amount = await _decryptAmount(row['amount']);
      final type = row['transaction_type'] as String;
      final txnCurrency = (row['currency'] as String?) ?? 'EUR';
      final signedAmount = type == 'income' ? amount : (type == 'expense' ? -amount : 0.0);
      if (signedAmount == 0) continue;

      double converted;
      if (txnCurrency == targetCurrency) {
        converted = signedAmount;
      } else {
        final rate = await getExchangeRate(txnCurrency, targetCurrency);
        converted = signedAmount * (rate ?? 1.0);
      }
      contributions.add((row['date'] as String, converted));
    }
    contributions.sort((a, b) => a.$1.compareTo(b.$1));

    if (granularity == 'daily') {
      return _buildDailyAssetsHistory(
          now, effectiveMonths, startingTotal, contributions);
    }

    final monthStarts = <DateTime>[];
    for (int i = effectiveMonths; i >= 1; i--) {
      monthStarts.add(DateTime(now.year, now.month - i + 1, 1));
    }

    final results = <Map<String, dynamic>>[];
    double cumulative = startingTotal;
    int idx = 0;
    for (int m = 0; m < monthStarts.length; m++) {
      final month = monthStarts[m];
      final endDate = DateTime(month.year, month.month + 1, 1)
          .toIso8601String()
          .substring(0, 10);
      while (idx < contributions.length &&
          contributions[idx].$1.compareTo(endDate) < 0) {
        cumulative += contributions[idx].$2;
        idx++;
      }
      results.add({
        'month': month,
        'label': _getMonthLabel(month.month),
        'value': cumulative,
      });
    }

    return results;
  }

  List<Map<String, dynamic>> _buildDailyAssetsHistory(
      DateTime now, int effectiveMonths, double startingTotal,
      List<(String, double)> contributions) {
    final startDate = DateTime(now.year, now.month - effectiveMonths + 1, 1);
    final todayEnd = DateTime(now.year, now.month, now.day + 1);

    final results = <Map<String, dynamic>>[];
    double cumulative = startingTotal;
    int idx = 0;
    var day = startDate;
    while (day.isBefore(todayEnd)) {
      final nextDay = DateTime(day.year, day.month, day.day + 1);
      final nextDayIso = nextDay.toIso8601String().substring(0, 10);
      while (idx < contributions.length &&
          contributions[idx].$1.compareTo(nextDayIso) < 0) {
        cumulative += contributions[idx].$2;
        idx++;
      }
      results.add({
        'date': day.toIso8601String().substring(0, 10),
        'label': day.day == 1 ? _getMonthLabel(day.month) : '',
        'tooltipLabel': '${day.day} ${_getMonthLabel(day.month)}',
        'value': cumulative,
      });
      day = nextDay;
    }
    return results;
  }

  String _getMonthLabel(int month) {
    const keys = ['month_jan_abbr', 'month_feb_abbr', 'month_mar_abbr', 'month_apr_abbr',
                  'month_may_abbr', 'month_jun_abbr', 'month_jul_abbr', 'month_aug_abbr',
                  'month_sep_abbr', 'month_oct_abbr', 'month_nov_abbr', 'month_dec_abbr'];
    return Translator.t(keys[(month - 1).clamp(0, 11)]);
  }

  Future<Map<String, double>> getCurrentMonthDistribution({
    required String transactionType,
    String targetCurrency = 'EUR',
  }) async {
    final db = await database;
    final now = DateTime.now();
    final startDate = DateTime(now.year, now.month, 1)
        .toIso8601String()
        .substring(0, 10);
    final endDate = now.toIso8601String().substring(0, 10);

    final rows = await db.query(
      'SELECT t.amount, t.currency, d.name as description_name '
      'FROM transactions t LEFT JOIN descriptions d ON t.description_id = d.id AND d.is_deleted = 0 '
      'WHERE t.transaction_type = ? AND t.date >= ? AND t.date <= ? AND t.user_id = ? AND t.is_deleted = 0',
      [transactionType, startDate, endDate, _userId],
    );

    final result = <String, double>{};
    for (final row in rows) {
      final category = await _decryptValue(row['description_name']) ?? 'Uncategorized';
      if (_isTransferDescription(category)) continue;
      final rawAmount = await _decryptAmount(row['amount']);
      final txnCurrency = (row['currency'] as String?) ?? 'EUR';

      double convertedAmount;
      if (txnCurrency == targetCurrency) {
        convertedAmount = rawAmount;
      } else {
        final rate = await getExchangeRate(txnCurrency, targetCurrency);
        convertedAmount = rawAmount * (rate ?? 1.0);
      }

      result[category] = (result[category] ?? 0) + convertedAmount;
    }
    return result;
  }

  Future<Map<String, double>> getRollingMonthDistribution({
    required String transactionType,
    int days = 30,
    String targetCurrency = 'EUR',
  }) async {
    final db = await database;
    final now = DateTime.now();
    final endDate = now.toIso8601String().substring(0, 10);
    final startDate = now.subtract(Duration(days: days)).toIso8601String().substring(0, 10);

    final rows = await db.query(
      'SELECT t.amount, t.currency, d.name as description_name '
      'FROM transactions t LEFT JOIN descriptions d ON t.description_id = d.id AND d.is_deleted = 0 '
      'WHERE t.transaction_type = ? AND t.date >= ? AND t.date <= ? AND t.user_id = ? AND t.is_deleted = 0',
      [transactionType, startDate, endDate, _userId],
    );

    final result = <String, double>{};
    for (final row in rows) {
      final category = await _decryptValue(row['description_name']) ?? 'Uncategorized';
      if (_isTransferDescription(category)) continue;
      final rawAmount = await _decryptAmount(row['amount']);
      final txnCurrency = (row['currency'] as String?) ?? 'EUR';

      double convertedAmount;
      if (txnCurrency == targetCurrency) {
        convertedAmount = rawAmount;
      } else {
        final rate = await getExchangeRate(txnCurrency, targetCurrency);
        convertedAmount = rawAmount * (rate ?? 1.0);
      }

      result[category] = (result[category] ?? 0) + convertedAmount;
    }
    return result;
  }

  Future<Map<String, double>> getCurrentMonthTagDistribution({
    required String transactionType,
    String targetCurrency = 'EUR',
  }) async {
    final db = await database;
    final now = DateTime.now();
    final startDate = DateTime(now.year, now.month, 1)
        .toIso8601String()
        .substring(0, 10);
    final endDate = now.toIso8601String().substring(0, 10);

    final rows = await db.query(
      'SELECT t.amount, t.currency, tg.name as tag_name '
      'FROM transactions t LEFT JOIN tags tg ON t.tag_id = tg.id AND tg.is_deleted = 0 '
      'WHERE t.transaction_type = ? AND t.date >= ? AND t.date <= ? AND t.user_id = ? AND t.is_deleted = 0',
      [transactionType, startDate, endDate, _userId],
    );

    final result = <String, double>{};
    for (final row in rows) {
      final tag = row['tag_name'] as String? ?? 'Untagged';
      final rawAmount = await _decryptAmount(row['amount']);
      final txnCurrency = (row['currency'] as String?) ?? 'EUR';

      double convertedAmount;
      if (txnCurrency == targetCurrency) {
        convertedAmount = rawAmount;
      } else {
        final rate = await getExchangeRate(txnCurrency, targetCurrency);
        convertedAmount = rawAmount * (rate ?? 1.0);
      }

      result[tag] = (result[tag] ?? 0) + convertedAmount;
    }
    return result;
  }

  Future<Map<String, double>> getRollingMonthTagDistribution({
    required String transactionType,
    int days = 30,
    String targetCurrency = 'EUR',
  }) async {
    final db = await database;
    final now = DateTime.now();
    final endDate = now.toIso8601String().substring(0, 10);
    final startDate = now.subtract(Duration(days: days)).toIso8601String().substring(0, 10);

    final rows = await db.query(
      'SELECT t.amount, t.currency, tg.name as tag_name '
      'FROM transactions t LEFT JOIN tags tg ON t.tag_id = tg.id AND tg.is_deleted = 0 '
      'WHERE t.transaction_type = ? AND t.date >= ? AND t.date <= ? AND t.user_id = ? AND t.is_deleted = 0',
      [transactionType, startDate, endDate, _userId],
    );

    final result = <String, double>{};
    for (final row in rows) {
      final tag = row['tag_name'] as String? ?? 'Untagged';
      final rawAmount = await _decryptAmount(row['amount']);
      final txnCurrency = (row['currency'] as String?) ?? 'EUR';

      double convertedAmount;
      if (txnCurrency == targetCurrency) {
        convertedAmount = rawAmount;
      } else {
        final rate = await getExchangeRate(txnCurrency, targetCurrency);
        convertedAmount = rawAmount * (rate ?? 1.0);
      }

      result[tag] = (result[tag] ?? 0) + convertedAmount;
    }
    return result;
  }

  Future<Map<String, String>> getTagColors() async {
    if (_userId == null) return {};
    final db = await database;
    final rows = await db.query(
      'SELECT name, color FROM tags WHERE user_id = ? AND is_deleted = 0',
      [_userId],
    );
    return {
      for (final r in rows)
        (r['name'] as String): (r['color'] as String? ?? '#1976D2'),
    };
  }

  // ==================== SETTINGS ====================

  Future<String?> getSetting(String key, {String? defaultValue}) async {
    final cacheKey = '${_userId}_$key';
    if (_settingCache.containsKey(cacheKey)) return _settingCache[cacheKey];

    final db = await database;
    final result = await db.query(
      'SELECT value FROM settings WHERE "key" = ? AND user_id = ? AND is_deleted = 0',
      [key, _userId],
    );
    if (result.isNotEmpty) {
      final value = result.first['value'] as String?;
      _settingCache[cacheKey] = value;
      return value;
    }
    return defaultValue;
  }

  Future<String?> getThemeForUser(String username, {String? defaultValue}) async {
    final db = await database;
    final result = await db.query(
      'SELECT s.value FROM settings s JOIN users u ON u.id = s.user_id '
      'WHERE u.username = ? AND s."key" = ? AND s.is_deleted = 0 AND u.is_deleted = 0',
      [username, 'theme_mode'],
    );
    if (result.isNotEmpty) {
      return result.first['value'] as String?;
    }
    return defaultValue;
  }

  Future<void> setSetting(String key, String value) async {
    final db = await database;
    await db.execute(
      'INSERT OR REPLACE INTO settings (user_id, "key", value) VALUES (?, ?, ?)',
      [_userId, key, value],
    );
    _settingCache['${_userId}_$key'] = value;
  }

  Future<String?> getAppSetting(String key, {String? defaultValue}) async {
    if (_appSettingCache.containsKey(key)) return _appSettingCache[key];

    final db = await database;
    final result = await db.query(
      'SELECT value FROM settings WHERE "key" = ? AND user_id = ? AND is_deleted = 0',
      [key, globalSettingsUserId],
    );
    if (result.isNotEmpty) {
      final value = result.first['value'] as String?;
      _appSettingCache[key] = value;
      return value;
    }
    return defaultValue;
  }

  Future<void> setAppSetting(String key, String value) async {
    final db = await database;
    await db.execute(
      'INSERT OR REPLACE INTO settings (user_id, "key", value) VALUES (?, ?, ?)',
      [globalSettingsUserId, key, value],
    );
    _appSettingCache[key] = value;
  }

  // ==================== EXCHANGE RATES ====================

  Future<bool> fetchExchangeRates({String baseCurrency = 'EUR'}) async {
    if (!CurrencyService.isValid(baseCurrency)) baseCurrency = 'EUR';
    final url = 'https://open.er-api.com/v6/latest/$baseCurrency';
    try {
      final client = HttpClient();
      final request = await client.getUrl(Uri.parse(url));
      request.headers.set('User-Agent', 'Peadra/2.0');
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      client.close();

      final data = json.decode(body) as Map<String, dynamic>;
      final apiRates = (data['rates'] as Map<String, dynamic>?) ?? {};

      final db = await database;
      final now = DateTime.now().toIso8601String();
      for (final entry in apiRates.entries) {
        if (CurrencyService.isValid(entry.key) && entry.key != baseCurrency) {
          await db.execute(
            'INSERT OR REPLACE INTO exchange_rates (from_currency, to_currency, rate, updated_at) VALUES (?1, ?2, ?3, ?4)',
            [baseCurrency, entry.key, (entry.value as num).toDouble(), now],
          );
        }
      }
      _exchangeRateCache.clear();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<double?> getExchangeRate(String fromCurrency, String toCurrency) async {
    if (fromCurrency == toCurrency) return 1.0;
    if (!CurrencyService.isValid(fromCurrency) || !CurrencyService.isValid(toCurrency)) {
      return null;
    }
    final cacheKey = '$fromCurrency|$toCurrency';
    if (_exchangeRateCache.containsKey(cacheKey)) return _exchangeRateCache[cacheKey];
    final db = await database;

    double? rate;

    // Direct rate
    var result = await db.query(
      'SELECT rate FROM exchange_rates WHERE from_currency = ? AND to_currency = ? AND is_deleted = 0',
      [fromCurrency, toCurrency],
    );
    if (result.isNotEmpty) rate = (result.first['rate'] as num).toDouble();

    if (rate == null && fromCurrency == 'EUR') {
      result = await db.query(
        'SELECT rate FROM exchange_rates WHERE from_currency = ? AND to_currency = ? AND is_deleted = 0',
        ['EUR', toCurrency],
      );
      if (result.isNotEmpty) rate = (result.first['rate'] as num).toDouble();
    }

    if (rate == null) {
      // Inverse
      result = await db.query(
        'SELECT rate FROM exchange_rates WHERE from_currency = ? AND to_currency = ? AND is_deleted = 0',
        [toCurrency, fromCurrency],
      );
      if (result.isNotEmpty) rate = 1.0 / (result.first['rate'] as num).toDouble();
    }

    if (rate == null) {
      // Via EUR
      final fromEur = await getExchangeRate('EUR', fromCurrency);
      final toEur = await getExchangeRate('EUR', toCurrency);
      if (fromEur != null && toEur != null) rate = toEur / fromEur;
    }

    _exchangeRateCache[cacheKey] = rate;
    return rate;
  }

  // ==================== ACCOUNT DELETION ====================

  Future<bool> deleteUserAccount(String password) async {
    if (_userId == null) return false;
    final db = await database;

    final rows = await db.query(
      'SELECT password_hash FROM users WHERE id = ? AND is_deleted = 0',
      [_userId],
    );
    if (rows.isEmpty) return false;

    if (!AuthService.verifyPassword(password, rows.first['password_hash'] as String)) {
      return false;
    }

    await db.execute('DELETE FROM transactions WHERE user_id = ?', [_userId]);
    await db.execute('DELETE FROM recurring_exceptions WHERE recurring_id IN (SELECT id FROM recurring_transactions WHERE user_id = ?)', [_userId]);
    await db.execute('DELETE FROM recurring_transactions WHERE user_id = ?', [_userId]);
    await db.execute('DELETE FROM accounts WHERE user_id = ?', [_userId]);
    await db.execute('DELETE FROM descriptions WHERE user_id = ?', [_userId]);
    await db.execute('DELETE FROM imported_files WHERE user_id = ?', [_userId]);
    await db.execute('DELETE FROM settings WHERE user_id = ?', [_userId]);
    await db.execute('DELETE FROM users WHERE id = ?', [_userId]);
    _userId = null;
    return true;
  }

  // ==================== CRDT (SYNC) HELPERS ====================

  /// Changes this node's CRDT identity. Safe to call after opening the
  /// database; used when the node id is first provisioned.
  Future<void> resetCrdtNodeId(String nodeId) async {
    final crdt = await database;
    await crdt.resetNodeId(nodeId);
  }

  String? get crdtNodeId => _database?.nodeId;

  /// Generates a changeset of all rows modified after [since]. Used by the
  /// sync layer.
  Future<CrdtChangeset> getChangeset({String? since, Iterable<String>? onlyTables}) async {
    final crdt = await database;
    return crdt.getChangeset(
      onlyTables: onlyTables,
      modifiedAfter: since != null ? Hlc.parse(since) : null,
    );
  }

  /// Applies a remote changeset.
  Future<void> applyChangeset(CrdtChangeset changeset) async {
    final crdt = await database;
    await crdt.merge(parseCrdtChangeset(changeset));
    _descriptionCache.clear();
    _settingCache.clear();
    _appSettingCache.clear();
    _exchangeRateCache.clear();
  }

  // ==================== CLOSE ====================

  Future<void> close() async {
    final db = await database;
    await db.close();
    _database = null;
  }

  // ==================== BACKUP ====================

  Future<void> backup({int maxBackups = 5}) async {
    final path = _dbPath;
    if (path == null) return;
    final dbFile = File(path);
    if (!dbFile.existsSync()) return;

    final timestamp = DateTime.now().toIso8601String().substring(0, 19).replaceAll(':', '-');
    final backupPath = join(dbFile.parent.path, 'peadra_$timestamp.db');
    await dbFile.copy(backupPath);

    _cleanupOldBackups(dbFile.parent.path, maxBackups);
  }

  void _cleanupOldBackups(String dirPath, int maxBackups) {
    final dir = Directory(dirPath);
    final backups = dir.listSync().whereType<File>().where((f) {
      final name = f.path.split(Platform.pathSeparator).last;
      return name.startsWith('peadra_') && name.endsWith('.db');
    }).toList();

    if (backups.length <= maxBackups) return;

    backups.sort((a, b) => a.path.compareTo(b.path));
    final toDelete = backups.sublist(0, backups.length - maxBackups);
    for (final file in toDelete) {
      file.deleteSync();
    }
  }
}
