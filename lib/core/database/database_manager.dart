import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

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
  static Database? _database;
  int? _userId;
  final Map<String, String?> _settingCache = {};
  final Map<String, String?> _appSettingCache = {};
  final Map<String, int> _descriptionCache = {};
  final Map<String, double?> _exchangeRateCache = {};
  SecretKey? _encryptionKey;

  DatabaseManager._();
  static final DatabaseManager instance = DatabaseManager._();

  int? get userId => _userId;
  bool get isEncrypted => _encryptionKey != null;

  Future<Database> get database async {
    _database ??= await _initDatabase();
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
    if (plaintext == null || plaintext.isEmpty || _encryptionKey == null) return plaintext;
    try {
      return await EncryptionService.encrypt(plaintext, _encryptionKey!);
    } catch (_) {
      return plaintext;
    }
  }

  Future<String?> _decrypt(String? ciphertext) async {
    if (ciphertext == null || ciphertext.isEmpty || _encryptionKey == null) return ciphertext;
    try {
      return await EncryptionService.decrypt(ciphertext, _encryptionKey!);
    } catch (_) {
      return ciphertext;
    }
  }

  Future<double> _decryptAmount(String? encrypted) async {
    if (encrypted == null || encrypted.isEmpty || _encryptionKey == null) {
      return double.tryParse(encrypted ?? '') ?? 0.0;
    }
    final decrypted = await _decrypt(encrypted);
    return double.tryParse(decrypted ?? '') ?? 0.0;
  }

  Future<Database> _initDatabase() async {
    String path;
    if (Platform.isAndroid || Platform.isIOS) {
      final dir = await getApplicationDocumentsDirectory();
      path = join(dir.path, dbName);
    } else {
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
      path = join(peadraDir.path, dbName);
    }

    return openDatabase(
      path,
      version: dbVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
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
        starting_amount REAL DEFAULT 0,
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

    await db.execute('''
      CREATE TABLE IF NOT EXISTS encryption_meta (
        key TEXT PRIMARY KEY,
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
        UNIQUE(user_id, name),
        FOREIGN KEY (user_id) REFERENCES users(id)
      )
    ''');

    await db.execute('''
      CREATE TABLE recurring_transactions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id INTEGER NOT NULL,
        account_id INTEGER,
        description_id INTEGER,
        tag_id INTEGER,
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
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        recurring_id INTEGER NOT NULL,
        date DATE NOT NULL,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        UNIQUE(recurring_id, date),
        FOREIGN KEY (recurring_id) REFERENCES recurring_transactions(id)
      )
    ''');

    await _createIndexes(db);
  }

  Future<void> _createIndexes(Database db) async {
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

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      try {
        await db.execute('ALTER TABLE accounts ADD COLUMN starting_amount REAL DEFAULT 0');
      } catch (_) {}
    }
    if (oldVersion < 3) {
      try {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS encryption_meta (
            key TEXT PRIMARY KEY,
            value TEXT
          )
        ''');
      } catch (_) {}
    }
    if (oldVersion < 4) {
      try {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS tags (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            user_id INTEGER NOT NULL,
            name TEXT NOT NULL,
            color TEXT DEFAULT '#1976D2',
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            UNIQUE(user_id, name),
            FOREIGN KEY (user_id) REFERENCES users(id)
          )
        ''');
        await db.execute('ALTER TABLE transactions ADD COLUMN tag_id INTEGER REFERENCES tags(id)');
      } catch (_) {}
    }
    if (oldVersion < 5) {
      try {
        await _createIndexes(db);
      } catch (_) {}
    }
    if (oldVersion < 6) {
      try {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS recurring_transactions (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            user_id INTEGER NOT NULL,
            account_id INTEGER,
            description_id INTEGER,
            tag_id INTEGER,
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
          CREATE TABLE IF NOT EXISTS recurring_exceptions (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            recurring_id INTEGER NOT NULL,
            date DATE NOT NULL,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            UNIQUE(recurring_id, date),
            FOREIGN KEY (recurring_id) REFERENCES recurring_transactions(id)
          )
        ''');
        await db.execute('ALTER TABLE transactions ADD COLUMN recurring_id INTEGER REFERENCES recurring_transactions(id)');
      } catch (_) {}
    }
  }

  /// Encrypt all existing unencrypted data. Called after login when encryption is first enabled.
  Future<void> migrateToEncryption() async {
    if (_encryptionKey == null) return;
    final db = await database;

    final meta = await db.rawQuery('SELECT value FROM encryption_meta WHERE key = ?', ['version']);
    if (meta.isNotEmpty && meta.first['value'] == '1') return;

    await _encryptAccounts(db);
    await _encryptDescriptions(db);
    await _encryptTransactions(db);
    await _encryptRecurring(db);

    await db.rawInsert(
      'INSERT OR REPLACE INTO encryption_meta (key, value) VALUES (?, ?)',
      ['version', '1'],
    );
  }

  Future<void> reEncryptData(SecretKey newKey) async {
    if (_encryptionKey == null) return;
    final db = await database;
    final oldKey = _encryptionKey!;
    _encryptionKey = newKey;

    final acctRows = await db.rawQuery('SELECT id, name, starting_amount FROM accounts WHERE user_id = ?', [_userId]);
    for (final row in acctRows) {
      final name = row['name'] as String?;
      final amount = row['starting_amount'] as String?;
      if (name != null && name.isNotEmpty) {
        final decrypted = await EncryptionService.decrypt(name, oldKey);
        final reEncrypted = await _encrypt(decrypted);
        await db.rawUpdate('UPDATE accounts SET name = ? WHERE id = ?', [reEncrypted, row['id']]);
      }
      if (amount != null && amount.isNotEmpty) {
        final decrypted = await EncryptionService.decrypt(amount, oldKey);
        final reEncrypted = await _encrypt(decrypted);
        await db.rawUpdate('UPDATE accounts SET starting_amount = ? WHERE id = ?', [reEncrypted, row['id']]);
      }
    }

    final descRows = await db.rawQuery('SELECT id, name FROM descriptions WHERE user_id = ?', [_userId]);
    for (final row in descRows) {
      final name = row['name'] as String?;
      if (name != null && name.isNotEmpty) {
        final decrypted = await EncryptionService.decrypt(name, oldKey);
        final reEncrypted = await _encrypt(decrypted);
        await db.rawUpdate('UPDATE descriptions SET name = ? WHERE id = ?', [reEncrypted, row['id']]);
      }
    }

    final txnRows = await db.rawQuery('SELECT id, amount, notes FROM transactions WHERE user_id = ?', [_userId]);
    for (final row in txnRows) {
      final amount = row['amount'] as String?;
      final notes = row['notes'] as String?;
      if (amount != null && amount.isNotEmpty) {
        final decrypted = await EncryptionService.decrypt(amount, oldKey);
        final reEncrypted = await _encrypt(decrypted);
        await db.rawUpdate('UPDATE transactions SET amount = ? WHERE id = ?', [reEncrypted, row['id']]);
      }
      if (notes != null && notes.isNotEmpty) {
        final decrypted = await EncryptionService.decrypt(notes, oldKey);
        final reEncrypted = await _encrypt(decrypted);
        await db.rawUpdate('UPDATE transactions SET notes = ? WHERE id = ?', [reEncrypted, row['id']]);
      }
    }

    final recRows = await db.rawQuery('SELECT id, amount, notes FROM recurring_transactions WHERE user_id = ?', [_userId]);
    for (final row in recRows) {
      final amount = row['amount'] as String?;
      final notes = row['notes'] as String?;
      if (amount != null && amount.isNotEmpty) {
        final decrypted = await EncryptionService.decrypt(amount, oldKey);
        final reEncrypted = await _encrypt(decrypted);
        await db.rawUpdate('UPDATE recurring_transactions SET amount = ? WHERE id = ?', [reEncrypted, row['id']]);
      }
      if (notes != null && notes.isNotEmpty) {
        final decrypted = await EncryptionService.decrypt(notes, oldKey);
        final reEncrypted = await _encrypt(decrypted);
        await db.rawUpdate('UPDATE recurring_transactions SET notes = ? WHERE id = ?', [reEncrypted, row['id']]);
      }
    }
  }

  Future<void> _encryptAccounts(Database db) async {
    final rows = await db.rawQuery('SELECT id, name, starting_amount FROM accounts WHERE user_id = ?', [_userId]);
    for (final row in rows) {
      final name = row['name'] as String?;
      final amount = row['starting_amount'] as num?;
      final encryptedName = await _encrypt(name);
      final encryptedAmount = amount != null ? await _encrypt(amount.toString()) : null;
      await db.rawUpdate(
        'UPDATE accounts SET name = ?, starting_amount = ? WHERE id = ?',
        [encryptedName, encryptedAmount, row['id']],
      );
    }
  }

  Future<void> _encryptDescriptions(Database db) async {
    final rows = await db.rawQuery('SELECT id, name FROM descriptions WHERE user_id = ?', [_userId]);
    for (final row in rows) {
      final name = row['name'] as String?;
      final encryptedName = await _encrypt(name);
      await db.rawUpdate(
        'UPDATE descriptions SET name = ? WHERE id = ?',
        [encryptedName, row['id']],
      );
    }
  }

  Future<void> _encryptTransactions(Database db) async {
    final rows = await db.rawQuery('SELECT id, amount, notes FROM transactions WHERE user_id = ?', [_userId]);
    for (final row in rows) {
      final amount = row['amount'] as num?;
      final notes = row['notes'] as String?;
      final encryptedAmount = amount != null ? await _encrypt(amount.toString()) : null;
      final encryptedNotes = await _encrypt(notes);
      await db.rawUpdate(
        'UPDATE transactions SET amount = ?, notes = ? WHERE id = ?',
        [encryptedAmount, encryptedNotes, row['id']],
      );
    }
  }

  Future<void> _encryptRecurring(Database db) async {
    final rows = await db.rawQuery('SELECT id, amount, notes FROM recurring_transactions WHERE user_id = ?', [_userId]);
    for (final row in rows) {
      final amount = row['amount'] as num?;
      final notes = row['notes'] as String?;
      final encryptedAmount = amount != null ? await _encrypt(amount.toString()) : null;
      final encryptedNotes = await _encrypt(notes);
      await db.rawUpdate(
        'UPDATE recurring_transactions SET amount = ?, notes = ? WHERE id = ?',
        [encryptedAmount, encryptedNotes, row['id']],
      );
    }
  }

  // ==================== USER ====================

  void setUserId(int userId) {
    _userId = userId;
    _descriptionCache.clear();
    _exchangeRateCache.clear();
    _insertDefaultAccounts();
    cleanupUnusedDescriptions();
    unawaited(generateDueRecurring());
  }

  Future<void> _insertDefaultAccounts() async {
    if (_userId == null) return;
    final db = await database;
    final count = Sqflite.firstIntValue(await db.rawQuery(
      'SELECT COUNT(*) FROM accounts WHERE user_id = ?',
      [_userId],
    ));
    if (count != null && count > 0) return;

    final currency = await getSetting('currency', defaultValue: defaultCurrency);
    final defaults = [
      {'name': 'Checking Account', 'color': '#4CAF50', 'type': 'checking', 'currency': currency},
      {'name': 'Savings Account A', 'color': '#2196F3', 'type': 'savings', 'currency': currency},
      {'name': 'Savings Account B', 'color': '#009688', 'type': 'savings', 'currency': currency},
    ];

    for (final acct in defaults) {
      await db.insert('accounts', {
        'user_id': _userId,
        'name': acct['name'],
        'color': acct['color'],
        'type': acct['type'],
        'currency': acct['currency'],
      });
    }
  }

  // ==================== ACCOUNTS ====================

  Future<List<Account>> getAllAccounts() async {
    final db = await database;
    final rows = await db.query(
      'accounts',
      where: 'user_id = ?',
      whereArgs: [_userId],
    );
    final accounts = <Account>[];
    for (final r in rows) {
      accounts.add(Account(
        id: r['id'] as int?,
        userId: r['user_id'] as int,
        name: await _decrypt(r['name'] as String?) ?? '',
        type: r['type'] as String? ?? 'savings',
        color: r['color'] as String? ?? '#1976D2',
        currency: r['currency'] as String? ?? 'EUR',
        startingAmount: await _decryptAmount(r['starting_amount'] as String?),
        createdAt: r['created_at'] as String?,
      ));
    }
    accounts.sort((a, b) => a.name.compareTo(b.name));
    return accounts;
  }

  Future<List<AccountWithBalance>> getAccountsWithBalances() async {
    final db = await database;
    final acctRows = await db.rawQuery(
      'SELECT * FROM accounts WHERE user_id = ? ORDER BY name',
      [_userId],
    );

    final txnRows = await db.rawQuery(
      'SELECT transaction_type, amount, account_id FROM transactions WHERE user_id = ?',
      [_userId],
    );
    final txnByAccount = <int, List<Map<String, dynamic>>>{};
    for (final t in txnRows) {
      final acctId = t['account_id'] as int?;
      if (acctId == null) continue;
      (txnByAccount[acctId] ??= []).add(t);
    }

    final results = <AccountWithBalance>[];
    for (final acctRow in acctRows) {
      final startingAmount = await _decryptAmount(acctRow['starting_amount'] as String?);

      double balance = startingAmount;
      for (final txn in txnByAccount[acctRow['id']] ?? const <Map<String, dynamic>>[]) {
        final amount = await _decryptAmount(txn['amount'] as String?);
        final type = txn['transaction_type'] as String;
        if (type == 'income') {
          balance += amount;
        } else if (type == 'expense') {
          balance -= amount;
        }
      }

      results.add(AccountWithBalance(
        id: acctRow['id'] as int?,
        userId: acctRow['user_id'] as int,
        name: await _decrypt(acctRow['name'] as String?) ?? '',
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

  Future<int?> addAccount(String name, String color, String type, String currency, {double startingAmount = 0.0}) async {
    final db = await database;
    try {
      final encryptedName = await _encrypt(name);
      final encryptedAmount = await _encrypt(startingAmount.toString());
      return await db.insert('accounts', {
        'user_id': _userId,
        'name': encryptedName,
        'color': color,
        'type': type,
        'currency': currency,
        'starting_amount': encryptedAmount,
      });
    } catch (_) {
      return -1;
    }
  }

  Future<bool> updateAccount(int accountId, String name, String color,
      {String? type, String? currency, double? startingAmount, bool updateNameInTransactions = false}) async {
    final db = await database;
    final existing = await db.query(
      'accounts',
      where: 'id = ? AND user_id = ?',
      whereArgs: [accountId, _userId],
    );
    if (existing.isEmpty) return false;

    final oldNameEncrypted = existing.first['name'] as String;
    final oldName = await _decrypt(oldNameEncrypted) ?? '';
    final oldCurrency = (existing.first['currency'] as String?) ?? defaultCurrency;
    final effectiveCurrency = currency ?? oldCurrency;

    final encryptedName = await _encrypt(name);
    final updates = <String, dynamic>{
      'name': encryptedName,
      'color': color,
      'currency': effectiveCurrency,
    };
    if (type != null) updates['type'] = type;
    if (startingAmount != null) {
      updates['starting_amount'] = await _encrypt(startingAmount.toString());
    }

    final count = await db.update(
      'accounts',
      updates,
      where: 'id = ? AND user_id = ?',
      whereArgs: [accountId, _userId],
    );

    if (count > 0 && updateNameInTransactions && oldName != name) {
      await _updateTransferNames(db, oldName, name);
    }

    return count > 0;
  }

  Future<void> _updateTransferNames(Database db, String oldName, String newName) async {
    final txnRows = await db.rawQuery(
      'SELECT id, notes FROM transactions WHERE user_id = ? AND notes IS NOT NULL',
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
        await db.rawUpdate(
          'UPDATE transactions SET notes = ? WHERE id = ?',
          [reEncrypted, row['id']],
        );
      }
    }

    final descRows = await db.rawQuery(
      'SELECT id, name FROM descriptions WHERE user_id = ?',
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
        await db.rawUpdate(
          'UPDATE descriptions SET name = ? WHERE id = ?',
          [reEncrypted, row['id']],
        );
      }
    }
  }

  Future<bool> deleteAccount(int accountId, {bool deleteTransactions = false}) async {
    final db = await database;
    final existing = await db.query(
      'accounts',
      where: 'id = ? AND user_id = ?',
      whereArgs: [accountId, _userId],
    );
    if (existing.isEmpty) return false;

    if (deleteTransactions) {
      final recIds = await db.query(
        'recurring_transactions',
        columns: ['id'],
        where: 'account_id = ? AND user_id = ?',
        whereArgs: [accountId, _userId],
      );
      await db.delete('transactions',
          where: 'account_id = ? AND user_id = ?', whereArgs: [accountId, _userId]);
      for (final rec in recIds) {
        await _deleteRecurringWithChildren(db, rec['id'] as int);
      }
    } else {
      await db.rawUpdate(
        'UPDATE transactions SET account_id = NULL WHERE account_id = ? AND user_id = ?',
        [accountId, _userId],
      );
      await db.rawUpdate(
        'UPDATE recurring_transactions SET account_id = NULL WHERE account_id = ? AND user_id = ?',
        [accountId, _userId],
      );
    }

    await db.delete('accounts',
        where: 'id = ? AND user_id = ?', whereArgs: [accountId, _userId]);
    return true;
  }

  // ==================== DESCRIPTIONS ====================

  Future<List<Description>> getAllDescriptions() async {
    final db = await database;
    final rows = await db.query(
      'descriptions',
      where: 'user_id = ?',
      whereArgs: [_userId],
    );
    final descriptions = <Description>[];
    for (final r in rows) {
      descriptions.add(Description(
        id: r['id'] as int?,
        userId: r['user_id'] as int,
        name: await _decrypt(r['name'] as String?) ?? '',
        createdAt: r['created_at'] as String?,
      ));
    }
    descriptions.sort((a, b) => a.name.compareTo(b.name));
    return descriptions;
  }

  Future<int> getOrCreateDescription(String name) async {
    final normalized = name.trim();
    final cacheKey = normalized.toLowerCase();
    final cached = _descriptionCache[cacheKey];
    if (cached != null) return cached;

    final db = await database;
    final allDescs = await db.rawQuery(
      'SELECT id, name FROM descriptions WHERE user_id = ?',
      [_userId],
    );
    for (final row in allDescs) {
      final decrypted = await _decrypt(row['name'] as String?);
      if (decrypted != null && decrypted.toLowerCase() == cacheKey) {
        _descriptionCache[cacheKey] = row['id'] as int;
        return row['id'] as int;
      }
    }

    final encryptedName = await _encrypt(normalized);
    final id = await db.insert('descriptions', {
      'user_id': _userId,
      'name': encryptedName,
    });
    _descriptionCache[cacheKey] = id;
    return id;
  }

  Future<bool> mergeDescriptions(String sourceName, String targetName) async {
    if (sourceName == targetName) return false;
    final db = await database;
    final sourceId = await getOrCreateDescription(sourceName);
    final targetId = await getOrCreateDescription(targetName);
    await db.rawUpdate(
      'UPDATE transactions SET description_id = ? WHERE description_id = ? AND user_id = ?',
      [targetId, sourceId, _userId],
    );
    await db.rawUpdate(
      'UPDATE recurring_transactions SET description_id = ? WHERE description_id = ? AND user_id = ?',
      [targetId, sourceId, _userId],
    );
    await db.delete('descriptions',
        where: 'id = ? AND user_id = ?', whereArgs: [sourceId, _userId]);
    _descriptionCache.clear();
    return true;
  }

  Future<bool> renameDescription(int descriptionId, String newName) async {
    if (newName.trim().isEmpty) return false;
    final db = await database;
    final encryptedName = await _encrypt(newName.trim());
    final count = await db.rawUpdate(
      'UPDATE descriptions SET name = ? WHERE id = ? AND user_id = ?',
      [encryptedName, descriptionId, _userId],
    );
    _descriptionCache.clear();
    return count > 0;
  }

  Future<void> cleanupUnusedDescriptions() async {
    if (_userId == null) return;
    final db = await database;
    await db.rawDelete('''
      DELETE FROM descriptions
      WHERE user_id = ?
        AND id NOT IN (SELECT DISTINCT description_id FROM transactions WHERE user_id = ?)
        AND id NOT IN (SELECT DISTINCT description_id FROM recurring_transactions WHERE user_id = ?)
    ''', [_userId, _userId, _userId]);
    _descriptionCache.clear();
  }

  // ==================== TAGS ====================

  Future<int?> createTag({required String name, String color = '#1976D2'}) async {
    if (_userId == null) return null;
    final db = await database;
    return await db.insert('tags', {
      'user_id': _userId,
      'name': name,
      'color': color,
    });
  }

  Future<List<Tag>> getAllTags() async {
    if (_userId == null) return [];
    final db = await database;
    final rows = await db.query(
      'tags',
      where: 'user_id = ?',
      whereArgs: [_userId],
      orderBy: 'name ASC',
    );
    return rows.map((r) => Tag.fromMap(r)).toList();
  }

  Future<bool> updateTag(int tagId, {String? name, String? color}) async {
    if (_userId == null) return false;
    final db = await database;
    final updates = <String, dynamic>{};
    if (name != null) updates['name'] = name;
    if (color != null) updates['color'] = color;
    if (updates.isEmpty) return false;
    final count = await db.update(
      'tags',
      updates,
      where: 'id = ? AND user_id = ?',
      whereArgs: [tagId, _userId],
    );
    return count > 0;
  }

  Future<bool> deleteTag(int tagId) async {
    if (_userId == null) return false;
    final db = await database;
    // Unassign tag from transactions before deleting
    await db.rawUpdate(
      'UPDATE transactions SET tag_id = NULL WHERE tag_id = ? AND user_id = ?',
      [tagId, _userId],
    );
    final count = await db.delete(
      'tags',
      where: 'id = ? AND user_id = ?',
      whereArgs: [tagId, _userId],
    );
    return count > 0;
  }

  // ==================== TRANSACTIONS ====================

  Future<String?> getAccountCurrency(int accountId) async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT currency FROM accounts WHERE id = ? AND user_id = ?',
      [accountId, _userId],
    );
    if (result.isEmpty) return null;
    final curr = result.first['currency'] as String?;
    if (curr != null && CurrencyService.isValid(curr)) return curr;
    return null;
  }

  Future<int?> addTransaction({
    required String date,
    required String description,
    required double amount,
    required String transactionType,
    int? accountId,
    int? tagId,
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

    final encryptedAmount = await _encrypt(amount.toString());
    final encryptedNotes = await _encrypt(notes);

    return await db.insert('transactions', {
      'user_id': _userId,
      'account_id': accountId,
      'description_id': descId,
      'tag_id': tagId,
      'date': date,
      'amount': encryptedAmount,
      'transaction_type': transactionType,
      'currency': effectiveCurrency,
      'notes': encryptedNotes,
    });
  }

  Future<bool> updateTransaction(int transactionId, {
    String? date,
    String? description,
    double? amount,
    String? transactionType,
    int? accountId,
    int? tagId,
    bool clearTag = false,
    String? notes,
    String? currency,
  }) async {
    final db = await database;
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
    final count = await db.update(
      'transactions',
      updates,
      where: 'id = ? AND user_id = ?',
      whereArgs: [transactionId, _userId],
    );
    return count > 0;
  }

  Future<bool> deleteTransaction(int transactionId) async {
    final db = await database;
    final count = await db.delete(
      'transactions',
      where: 'id = ? AND user_id = ?',
      whereArgs: [transactionId, _userId],
    );
    return count > 0;
  }

  Future<List<TransactionWithDetails>> getTransactions({
    int? limit,
    int offset = 0,
    String searchQuery = '',
    Set<int>? accountIds,
    Set<int>? tagIds,
  }) async {
    final db = await database;
    var query = '''
      SELECT t.*, a.name as account_name, a.color as account_color,
             a.currency as account_currency, d.name as description_name,
             tg.name as tag_name, tg.color as tag_color,
             rt.frequency as recurring_frequency
      FROM transactions t
      LEFT JOIN accounts a ON t.account_id = a.id
      LEFT JOIN descriptions d ON t.description_id = d.id
      LEFT JOIN tags tg ON t.tag_id = tg.id
      LEFT JOIN recurring_transactions rt ON t.recurring_id = rt.id
      WHERE t.user_id = ?
      ORDER BY t.date DESC, t.id DESC
    ''';

    final rows = await db.rawQuery(query, [_userId]);

    final results = <TransactionWithDetails>[];
    final sq = searchQuery.toLowerCase();
    for (final r in rows) {
      final amount = await _decryptAmount(r['amount'] as String?);
      final notes = await _decrypt(r['notes'] as String?);
      final accountName = await _decrypt(r['account_name'] as String?);
      final descriptionName = await _decrypt(r['description_name'] as String?);

      if (accountIds != null && accountIds.isNotEmpty) {
        final acctId = r['account_id'] as int?;
        if (acctId == null || !accountIds.contains(acctId)) continue;
      }

      if (tagIds != null && tagIds.isNotEmpty) {
        final txnTagId = r['tag_id'] as int?;
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
        id: r['id'] as int?,
        userId: r['user_id'] as int,
        accountId: r['account_id'] as int?,
        descriptionId: r['description_id'] as int?,
        tagId: r['tag_id'] as int?,
        date: r['date'] as String,
        amount: amount,
        transactionType: r['transaction_type'] as String,
        currency: r['currency'] as String? ?? 'EUR',
        notes: notes,
        recurringId: r['recurring_id'] as int?,
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
    final rows = await db.rawQuery('''
      SELECT t.*, a.name as account_name, a.color as account_color,
             a.currency as account_currency, d.name as description_name,
             tg.name as tag_name, tg.color as tag_color,
             rt.frequency as recurring_frequency
      FROM transactions t
      LEFT JOIN accounts a ON t.account_id = a.id
      LEFT JOIN descriptions d ON t.description_id = d.id
      LEFT JOIN tags tg ON t.tag_id = tg.id
      LEFT JOIN recurring_transactions rt ON t.recurring_id = rt.id
      WHERE t.date BETWEEN ? AND ? AND t.user_id = ?
      ORDER BY t.date DESC
    ''', [startDate, endDate, _userId]);

    final results = <TransactionWithDetails>[];
    for (final r in rows) {
      results.add(TransactionWithDetails(
        id: r['id'] as int?,
        userId: r['user_id'] as int,
        accountId: r['account_id'] as int?,
        descriptionId: r['description_id'] as int?,
        tagId: r['tag_id'] as int?,
        date: r['date'] as String,
        amount: await _decryptAmount(r['amount'] as String?),
        transactionType: r['transaction_type'] as String,
        currency: r['currency'] as String? ?? 'EUR',
        notes: await _decrypt(r['notes'] as String?),
        recurringId: r['recurring_id'] as int?,
        createdAt: r['created_at'] as String?,
        updatedAt: r['updated_at'] as String?,
        accountName: await _decrypt(r['account_name'] as String?),
        accountColor: r['account_color'] as String?,
        accountCurrency: r['account_currency'] as String?,
        descriptionName: await _decrypt(r['description_name'] as String?),
        tagName: r['tag_name'] as String?,
        tagColor: r['tag_color'] as String?,
        recurringFrequency: r['recurring_frequency'] as String?,
      ));
    }
    return results;
  }

  // ==================== RECURRING TRANSACTIONS ====================

  Future<int?> addRecurringTransaction({
    required String description,
    required double amount,
    required String transactionType,
    required String frequency,
    required String startDate,
    int? accountId,
    int? tagId,
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

    return await db.insert('recurring_transactions', {
      'user_id': _userId,
      'account_id': accountId,
      'description_id': descId,
      'tag_id': tagId,
      'amount': await _encrypt(amount.toString()),
      'transaction_type': transactionType,
      'currency': effectiveCurrency,
      'notes': await _encrypt(notes),
      'frequency': frequency,
      'interval': interval,
      'day_of_week': frequency == 'weekly' ? computedDow : dayOfWeek,
      'day_of_month': (frequency == 'monthly' || frequency == 'yearly') ? computedDom : dayOfMonth,
      'start_date': startDate,
      'end_date': endDate,
      'next_due_date': startDate,
      'active': 1,
    });
  }

  Future<bool> updateRecurringTransaction(int recurringId, {
    String? description,
    double? amount,
    String? transactionType,
    String? frequency,
    String? startDate,
    String? endDate,
    bool clearEndDate = false,
    int? accountId,
    int? tagId,
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
      'recurring_transactions',
      where: 'id = ? AND user_id = ?',
      whereArgs: [recurringId, _userId],
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
    final count = await db.update(
      'recurring_transactions',
      updates,
      where: 'id = ? AND user_id = ?',
      whereArgs: [recurringId, _userId],
    );
    return count > 0;
  }

  Future<bool> toggleRecurringActive(int recurringId, bool active) async {
    final db = await database;
    final count = await db.update(
      'recurring_transactions',
      {'active': active ? 1 : 0, 'updated_at': DateTime.now().toIso8601String()},
      where: 'id = ? AND user_id = ?',
      whereArgs: [recurringId, _userId],
    );
    return count > 0;
  }

  Future<bool> deleteRecurringTransaction(int recurringId,
      {bool deleteOccurrences = true}) async {
    final db = await database;
    final count = await db.delete(
      'recurring_transactions',
      where: 'id = ? AND user_id = ?',
      whereArgs: [recurringId, _userId],
    );
    if (count > 0) {
      if (deleteOccurrences) {
        await db.delete('transactions',
            where: 'recurring_id = ? AND user_id = ?',
            whereArgs: [recurringId, _userId]);
      }
      await db.delete('recurring_exceptions',
          where: 'recurring_id = ?', whereArgs: [recurringId]);
    }
    return count > 0;
  }

  Future<void> _deleteRecurringWithChildren(Database db, int recurringId) async {
    await db.delete('transactions',
        where: 'recurring_id = ? AND user_id = ?', whereArgs: [recurringId, _userId]);
    await db.delete('recurring_exceptions',
        where: 'recurring_id = ?', whereArgs: [recurringId]);
    await db.delete('recurring_transactions',
        where: 'id = ? AND user_id = ?', whereArgs: [recurringId, _userId]);
  }

  Future<void> markRecurringOccurrenceDeleted(int recurringId, String date) async {
    final db = await database;
    await db.rawInsert(
      'INSERT OR REPLACE INTO recurring_exceptions (recurring_id, date) VALUES (?, ?)',
      [recurringId, date],
    );
  }

  Future<void> clearRecurringOccurrenceDeleted(int recurringId, String date) async {
    final db = await database;
    await db.delete('recurring_exceptions',
        where: 'recurring_id = ? AND date = ?', whereArgs: [recurringId, date]);
  }

  RecurringTransaction _recurringFromRow(Map<String, dynamic> row) {
    return RecurringTransaction(
      id: row['id'] as int?,
      userId: row['user_id'] as int,
      accountId: row['account_id'] as int?,
      descriptionId: row['description_id'] as int?,
      tagId: row['tag_id'] as int?,
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
      int recurringId) async {
    final db = await database;
    final rows = await db.rawQuery('''
      SELECT r.*, a.name as account_name, a.color as account_color,
             a.currency as account_currency, d.name as description_name,
             tg.name as tag_name, tg.color as tag_color,
             (SELECT COUNT(*) FROM transactions t WHERE t.recurring_id = r.id) as generated_count
      FROM recurring_transactions r
      LEFT JOIN accounts a ON r.account_id = a.id
      LEFT JOIN descriptions d ON r.description_id = d.id
      LEFT JOIN tags tg ON r.tag_id = tg.id
      WHERE r.id = ? AND r.user_id = ?
    ''', [recurringId, _userId]);
    if (rows.isEmpty) return null;
    final r = rows.first;
    return RecurringTransactionWithDetails(
      id: r['id'] as int?,
      userId: r['user_id'] as int,
      accountId: r['account_id'] as int?,
      descriptionId: r['description_id'] as int?,
      tagId: r['tag_id'] as int?,
      amount: await _decryptAmount(r['amount'] as String?),
      transactionType: r['transaction_type'] as String,
      currency: r['currency'] as String? ?? 'EUR',
      notes: await _decrypt(r['notes'] as String?),
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
      accountName: await _decrypt(r['account_name'] as String?),
      accountColor: r['account_color'] as String?,
      accountCurrency: r['account_currency'] as String?,
      descriptionName: await _decrypt(r['description_name'] as String?),
      tagName: r['tag_name'] as String?,
      tagColor: r['tag_color'] as String?,
      generatedCount: r['generated_count'] as int? ?? 0,
    );
  }

  Future<List<RecurringTransactionWithDetails>> getRecurringTransactions() async {
    final db = await database;
    final rows = await db.rawQuery('''
      SELECT r.*, a.name as account_name, a.color as account_color,
             a.currency as account_currency, d.name as description_name,
             tg.name as tag_name, tg.color as tag_color,
             (SELECT COUNT(*) FROM transactions t WHERE t.recurring_id = r.id) as generated_count
      FROM recurring_transactions r
      LEFT JOIN accounts a ON r.account_id = a.id
      LEFT JOIN descriptions d ON r.description_id = d.id
      LEFT JOIN tags tg ON r.tag_id = tg.id
      WHERE r.user_id = ?
      ORDER BY r.next_due_date ASC, r.id DESC
    ''', [_userId]);

    final results = <RecurringTransactionWithDetails>[];
    for (final r in rows) {
      results.add(RecurringTransactionWithDetails(
        id: r['id'] as int?,
        userId: r['user_id'] as int,
        accountId: r['account_id'] as int?,
        descriptionId: r['description_id'] as int?,
        tagId: r['tag_id'] as int?,
        amount: await _decryptAmount(r['amount'] as String?),
        transactionType: r['transaction_type'] as String,
        currency: r['currency'] as String? ?? 'EUR',
        notes: await _decrypt(r['notes'] as String?),
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
        accountName: await _decrypt(r['account_name'] as String?),
        accountColor: r['account_color'] as String?,
        accountCurrency: r['account_currency'] as String?,
        descriptionName: await _decrypt(r['description_name'] as String?),
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
    final db = await database;
    final rows = await db.query(
      'recurring_transactions',
      where: 'user_id = ? AND active = 1',
      whereArgs: [_userId],
    );
    for (final row in rows) {
      final base = _recurringFromRow(row);
      final rec = RecurringTransaction(
        id: base.id,
        userId: base.userId,
        accountId: base.accountId,
        descriptionId: base.descriptionId,
        tagId: base.tagId,
        amount: await _decryptAmount(row['amount'] as String?),
        transactionType: base.transactionType,
        currency: base.currency,
        notes: await _decrypt(row['notes'] as String?),
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
      Database db, RecurringTransaction rec) async {
    final id = rec.id;
    if (id == null) return;

    final existingRows = await db.query(
      'transactions',
      columns: ['date'],
      where: 'recurring_id = ? AND user_id = ?',
      whereArgs: [id, _userId],
    );
    final existingDates =
        existingRows.map((r) => r['date'] as String).toSet();

    final exceptionRows = await db.query(
      'recurring_exceptions',
      columns: ['date'],
      where: 'recurring_id = ?',
      whereArgs: [id],
    );
    final exceptionDates =
        exceptionRows.map((r) => r['date'] as String).toSet();

    final plan = RecurringService.planGeneration(
      rec,
      existingDates: existingDates,
      exceptionDates: exceptionDates,
      today: DateTime.now(),
    );

    for (final dateStr in plan.dueDates) {
      await db.insert('transactions', {
        'user_id': rec.userId,
        'account_id': rec.accountId,
        'description_id': rec.descriptionId,
        'tag_id': rec.tagId,
        'date': dateStr,
        'amount': await _encrypt(rec.amount.toString()),
        'transaction_type': rec.transactionType,
        'currency': rec.currency,
        'notes': await _encrypt(rec.notes),
        'recurring_id': id,
      });
    }

    if (plan.ended) {
      await db.update(
        'recurring_transactions',
        {'active': 0, 'next_due_date': plan.nextDueDate},
        where: 'id = ?',
        whereArgs: [id],
      );
    } else {
      await db.update(
        'recurring_transactions',
        {'next_due_date': plan.nextDueDate},
        where: 'id = ?',
        whereArgs: [id],
      );
    }
  }

  // ==================== STATISTICS ====================

  Future<double> getTotalPatrimony({String targetCurrency = 'EUR'}) async {
    final db = await database;
    final acctRows = await db.rawQuery(
      'SELECT starting_amount, currency FROM accounts WHERE user_id = ?',
      [_userId],
    );

    double total = 0.0;
    for (final row in acctRows) {
      final amount = await _decryptAmount(row['starting_amount'] as String?);
      final acctCurrency = (row['currency'] as String?) ?? 'EUR';
      if (amount == 0) continue;
      if (acctCurrency == targetCurrency) {
        total += amount;
      } else {
        final rate = await getExchangeRate(acctCurrency, targetCurrency);
        total += amount * (rate ?? 1.0);
      }
    }

    final txnRows = await db.rawQuery(
      'SELECT t.amount, t.transaction_type, COALESCE(NULLIF(a.currency, \'\'), \'EUR\') as currency '
      'FROM transactions t LEFT JOIN accounts a ON t.account_id = a.id WHERE t.user_id = ?',
      [_userId],
    );

    for (final row in txnRows) {
      final amount = await _decryptAmount(row['amount'] as String?);
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

  Future<double> getBalance({String targetCurrency = 'EUR'}) async {
    final db = await database;

    final acctRows = await db.rawQuery(
      'SELECT starting_amount, currency FROM accounts WHERE type = ? AND user_id = ?',
      ['checking', _userId],
    );

    double total = 0.0;
    for (final row in acctRows) {
      final amount = await _decryptAmount(row['starting_amount'] as String?);
      final acctCurrency = (row['currency'] as String?) ?? 'EUR';
      if (amount == 0) continue;
      if (acctCurrency == targetCurrency) {
        total += amount;
      } else {
        final rate = await getExchangeRate(acctCurrency, targetCurrency);
        total += amount * (rate ?? 1.0);
      }
    }

    final txnRows = await db.rawQuery(
      'SELECT t.amount, t.transaction_type, t.account_id, '
      'COALESCE(NULLIF(a.currency, \'\'), \'EUR\') as currency, a.type as account_type '
      'FROM transactions t LEFT JOIN accounts a ON t.account_id = a.id WHERE t.user_id = ?',
      [_userId],
    );

    for (final row in txnRows) {
      final accountType = row['account_type'] as String?;
      final hasAccount = row['account_id'] != null;
      if (accountType != 'checking' && hasAccount) continue;

      final amount = await _decryptAmount(row['amount'] as String?);
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

    final acctRows = await db.rawQuery(
      'SELECT starting_amount, currency FROM accounts WHERE type = ? AND user_id = ?',
      ['savings', _userId],
    );

    double total = 0.0;
    for (final row in acctRows) {
      final amount = await _decryptAmount(row['starting_amount'] as String?);
      final acctCurrency = (row['currency'] as String?) ?? 'EUR';
      if (amount == 0) continue;
      if (acctCurrency == targetCurrency) {
        total += amount;
      } else {
        final rate = await getExchangeRate(acctCurrency, targetCurrency);
        total += amount * (rate ?? 1.0);
      }
    }

    final txnRows = await db.rawQuery(
      'SELECT t.amount, t.transaction_type, '
      'COALESCE(NULLIF(a.currency, \'\'), \'EUR\') as currency '
      'FROM transactions t LEFT JOIN accounts a ON t.account_id = a.id '
      'WHERE a.type = ? AND t.user_id = ?'
      '${before != null ? ' AND t.date < ?' : ''}',
      before != null ? ['savings', _userId, before] : ['savings', _userId],
    );

    for (final row in txnRows) {
      final amount = await _decryptAmount(row['amount'] as String?);
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
    final txnRows = await db.rawQuery(
      'SELECT t.amount, t.transaction_type, t.account_id, '
      'COALESCE(NULLIF(a.currency, \'\'), \'EUR\') as currency, a.type as account_type, '
      'd.name as description_name '
      'FROM transactions t LEFT JOIN accounts a ON t.account_id = a.id '
      'LEFT JOIN descriptions d ON t.description_id = d.id '
      'WHERE t.date >= ? AND t.date < ? AND t.user_id = ?',
      [startDate, endDate, _userId],
    );

    double income = 0.0;
    double expenses = 0.0;
    for (final row in txnRows) {
      final accountType = row['account_type'] as String?;
      final hasAccount = row['account_id'] != null;
      if (accountType != 'checking' && hasAccount) continue;

      final desc = await _decrypt(row['description_name'] as String?);
      if (desc != null && _isTransferDescription(desc)) continue;

      final amount = await _decryptAmount(row['amount'] as String?);
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
    final txnRows = await db.rawQuery(
      'SELECT t.amount, t.transaction_type, t.account_id, '
      'COALESCE(NULLIF(a.currency, \'\'), \'EUR\') as currency, a.type as account_type, '
      'd.name as description_name '
      'FROM transactions t LEFT JOIN accounts a ON t.account_id = a.id '
      'LEFT JOIN descriptions d ON t.description_id = d.id '
      'WHERE t.date >= ? AND t.date <= ? AND t.user_id = ?',
      [startDate, endDate, _userId],
    );

    double income = 0.0;
    double expenses = 0.0;
    for (final row in txnRows) {
      final accountType = row['account_type'] as String?;
      final hasAccount = row['account_id'] != null;
      if (accountType != 'checking' && hasAccount) continue;

      final desc = await _decrypt(row['description_name'] as String?);
      if (desc != null && _isTransferDescription(desc)) continue;

      final amount = await _decryptAmount(row['amount'] as String?);
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
    final acctRows = await db.rawQuery(
      'SELECT * FROM accounts WHERE user_id = ? ORDER BY name',
      [_userId],
    );

    final txnRows = await db.rawQuery(
      'SELECT transaction_type, amount, account_id FROM transactions WHERE user_id = ?',
      [_userId],
    );
    final txnByAccount = <int, List<Map<String, dynamic>>>{};
    for (final t in txnRows) {
      final acctId = t['account_id'] as int?;
      if (acctId == null) continue;
      (txnByAccount[acctId] ??= []).add(t);
    }

    final results = <Map<String, dynamic>>[];
    for (final acctRow in acctRows) {
      final startingAmount = await _decryptAmount(acctRow['starting_amount'] as String?);

      double balance = startingAmount;
      for (final txn in txnByAccount[acctRow['id']] ?? const <Map<String, dynamic>>[]) {
        final amount = await _decryptAmount(txn['amount'] as String?);
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
        'name': await _decrypt(acctRow['name'] as String?),
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
    final rows = await db.rawQuery('''
      SELECT t.amount, t.transaction_type, t.date,
             d.name as description_name
      FROM transactions t
      LEFT JOIN descriptions d ON t.description_id = d.id
      WHERE t.date >= ? AND t.date <= ? AND t.user_id = ?
    ''', [startDate, endDate, _userId]);

    final result = <String, Map<String, Map<String, double>>>{};
    for (final row in rows) {
      final desc = await _decrypt(row['description_name'] as String?) ?? 'uncategorized';
      final month = (row['date'] as String).substring(0, 7);
      final type = row['transaction_type'] as String;
      final total = await _decryptAmount(row['amount'] as String?);

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

    final rows = await db.rawQuery('''
      SELECT t.amount, d.name as description_name
      FROM transactions t
      LEFT JOIN descriptions d ON t.description_id = d.id
      WHERE t.transaction_type = ? AND t.date >= ? AND t.date <= ? AND t.user_id = ?
    ''', [transactionType, startDate, endDate, _userId]);

    final byDesc = <String, Map<String, dynamic>>{};
    for (final row in rows) {
      final desc = await _decrypt(row['description_name'] as String?) ?? 'Uncategorized';
      if (_isTransferDescription(desc)) continue;
      final amount = await _decryptAmount(row['amount'] as String?);

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

    final rows = await db.rawQuery('''
      SELECT t.amount, tg.name as tag_name
      FROM transactions t
      LEFT JOIN tags tg ON t.tag_id = tg.id
      WHERE t.transaction_type = ? AND t.date >= ? AND t.date <= ? AND t.user_id = ?
        AND t.tag_id IS NOT NULL
    ''', [transactionType, startDate, endDate, _userId]);

    final byTag = <String, Map<String, dynamic>>{};
    for (final row in rows) {
      final tag = row['tag_name'] as String? ?? 'Untagged';
      final amount = await _decryptAmount(row['amount'] as String?);

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
    final rows = await db.rawQuery('''
      SELECT t.amount, t.transaction_type, t.date,
             tg.name as tag_name
      FROM transactions t
      LEFT JOIN tags tg ON t.tag_id = tg.id
      WHERE t.date >= ? AND t.date <= ? AND t.user_id = ?
        AND t.tag_id IS NOT NULL
    ''', [startDate, endDate, _userId]);

    final result = <String, Map<String, Map<String, double>>>{};
    for (final row in rows) {
      final tag = row['tag_name'] as String? ?? 'Untagged';
      final month = (row['date'] as String).substring(0, 7);
      final type = row['transaction_type'] as String;
      final total = await _decryptAmount(row['amount'] as String?);

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

    final rows = await db.rawQuery(
      'SELECT t.amount, t.transaction_type, t.date, '
      'd.name as description_name, '
      'COALESCE(NULLIF(a.currency, \'\'), \'EUR\') as currency '
      'FROM transactions t '
      'LEFT JOIN accounts a ON t.account_id = a.id '
      'LEFT JOIN descriptions d ON t.description_id = d.id '
      'WHERE t.date >= ? AND t.user_id = ?',
      [startDate, _userId],
    );

    final monthMap = <String, Map<String, double>>{};
    for (final r in rows) {
      final desc = await _decrypt(r['description_name'] as String?);
      if (desc != null && _isTransferDescription(desc)) continue;

      final monthKey = (r['date'] as String).substring(0, 7);
      final type = r['transaction_type'] as String;
      final amount = await _decryptAmount(r['amount'] as String?);
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

  Future<List<Map<String, dynamic>>> getAssetsHistory({int months = 6, String targetCurrency = 'EUR'}) async {
    final db = await database;
    final now = DateTime.now();

    final earliestResult = await db.rawQuery(
      'SELECT MIN(date) as earliest FROM transactions WHERE user_id = ?',
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

    final acctRows = await db.rawQuery(
      'SELECT starting_amount, currency FROM accounts WHERE user_id = ?',
      [_userId],
    );

    double startingTotal = 0.0;
    for (final row in acctRows) {
      final amount = await _decryptAmount(row['starting_amount'] as String?);
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
    final txnRows = await db.rawQuery(
      'SELECT t.amount, t.transaction_type, t.date, '
      'COALESCE(NULLIF(a.currency, \'\'), \'EUR\') as currency '
      'FROM transactions t LEFT JOIN accounts a ON t.account_id = a.id '
      'WHERE t.date < ? AND t.user_id = ?',
      [nowNextMonth, _userId],
    );

    final contributions = <(String, double)>[];
    for (final row in txnRows) {
      final amount = await _decryptAmount(row['amount'] as String?);
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

    final rows = await db.rawQuery(
      'SELECT t.amount, t.currency, d.name as description_name '
      'FROM transactions t LEFT JOIN descriptions d ON t.description_id = d.id '
      'WHERE t.transaction_type = ? AND t.date >= ? AND t.date <= ? AND t.user_id = ?',
      [transactionType, startDate, endDate, _userId],
    );

    final result = <String, double>{};
    for (final row in rows) {
      final category = await _decrypt(row['description_name'] as String?) ?? 'Uncategorized';
      if (_isTransferDescription(category)) continue;
      final rawAmount = await _decryptAmount(row['amount'] as String?);
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

    final rows = await db.rawQuery(
      'SELECT t.amount, t.currency, d.name as description_name '
      'FROM transactions t LEFT JOIN descriptions d ON t.description_id = d.id '
      'WHERE t.transaction_type = ? AND t.date >= ? AND t.date <= ? AND t.user_id = ?',
      [transactionType, startDate, endDate, _userId],
    );

    final result = <String, double>{};
    for (final row in rows) {
      final category = await _decrypt(row['description_name'] as String?) ?? 'Uncategorized';
      if (_isTransferDescription(category)) continue;
      final rawAmount = await _decryptAmount(row['amount'] as String?);
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

    final rows = await db.rawQuery(
      'SELECT t.amount, t.currency, tg.name as tag_name '
      'FROM transactions t LEFT JOIN tags tg ON t.tag_id = tg.id '
      'WHERE t.transaction_type = ? AND t.date >= ? AND t.date <= ? AND t.user_id = ?',
      [transactionType, startDate, endDate, _userId],
    );

    final result = <String, double>{};
    for (final row in rows) {
      final tag = row['tag_name'] as String? ?? 'Untagged';
      final rawAmount = await _decryptAmount(row['amount'] as String?);
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

    final rows = await db.rawQuery(
      'SELECT t.amount, t.currency, tg.name as tag_name '
      'FROM transactions t LEFT JOIN tags tg ON t.tag_id = tg.id '
      'WHERE t.transaction_type = ? AND t.date >= ? AND t.date <= ? AND t.user_id = ?',
      [transactionType, startDate, endDate, _userId],
    );

    final result = <String, double>{};
    for (final row in rows) {
      final tag = row['tag_name'] as String? ?? 'Untagged';
      final rawAmount = await _decryptAmount(row['amount'] as String?);
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

  // ==================== SETTINGS ====================

  Future<String?> getSetting(String key, {String? defaultValue}) async {
    final cacheKey = '${_userId}_$key';
    if (_settingCache.containsKey(cacheKey)) return _settingCache[cacheKey];

    final db = await database;
    final result = await db.rawQuery(
      'SELECT value FROM settings WHERE key = ? AND user_id = ?',
      [key, _userId],
    );
    if (result.isNotEmpty) {
      final value = result.first['value'] as String?;
      _settingCache[cacheKey] = value;
      return value;
    }
    return defaultValue;
  }

  Future<void> setSetting(String key, String value) async {
    final db = await database;
    await db.rawInsert(
      'INSERT OR REPLACE INTO settings (user_id, key, value) VALUES (?, ?, ?)',
      [_userId, key, value],
    );
    _settingCache['${_userId}_$key'] = value;
  }

  Future<String?> getAppSetting(String key, {String? defaultValue}) async {
    if (_appSettingCache.containsKey(key)) return _appSettingCache[key];

    final db = await database;
    final result = await db.rawQuery(
      'SELECT value FROM settings WHERE key = ? AND user_id = ?',
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
    await db.rawInsert(
      'INSERT OR REPLACE INTO settings (user_id, key, value) VALUES (?, ?, ?)',
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
          await db.rawInsert(
            'INSERT OR REPLACE INTO exchange_rates (from_currency, to_currency, rate, updated_at) VALUES (?, ?, ?, ?)',
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
    var result = await db.rawQuery(
      'SELECT rate FROM exchange_rates WHERE from_currency = ? AND to_currency = ?',
      [fromCurrency, toCurrency],
    );
    if (result.isNotEmpty) rate = (result.first['rate'] as num).toDouble();

    if (rate == null && fromCurrency == 'EUR') {
      result = await db.rawQuery(
        'SELECT rate FROM exchange_rates WHERE from_currency = ? AND to_currency = ?',
        ['EUR', toCurrency],
      );
      if (result.isNotEmpty) rate = (result.first['rate'] as num).toDouble();
    }

    if (rate == null) {
      // Inverse
      result = await db.rawQuery(
        'SELECT rate FROM exchange_rates WHERE from_currency = ? AND to_currency = ?',
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

    final rows = await db.rawQuery(
      'SELECT password_hash FROM users WHERE id = ?',
      [_userId],
    );
    if (rows.isEmpty) return false;

    if (!AuthService.verifyPassword(password, rows.first['password_hash'] as String)) {
      return false;
    }

    await db.delete('transactions', where: 'user_id = ?', whereArgs: [_userId]);
    await db.delete('recurring_exceptions', where: 'recurring_id IN (SELECT id FROM recurring_transactions WHERE user_id = ?)', whereArgs: [_userId]);
    await db.delete('recurring_transactions', where: 'user_id = ?', whereArgs: [_userId]);
    await db.delete('accounts', where: 'user_id = ?', whereArgs: [_userId]);
    await db.delete('descriptions', where: 'user_id = ?', whereArgs: [_userId]);
    await db.delete('imported_files', where: 'user_id = ?', whereArgs: [_userId]);
    await db.delete('settings', where: 'user_id = ?', whereArgs: [_userId]);
    await db.delete('users', where: 'id = ?', whereArgs: [_userId]);
    _userId = null;
    return true;
  }

  // ==================== CLOSE ====================

  Future<void> close() async {
    final db = await database;
    await db.close();
    _database = null;
  }

  // ==================== BACKUP ====================

  Future<void> backup({int maxBackups = 5}) async {
    final db = await database;
    final path = db.path;
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
