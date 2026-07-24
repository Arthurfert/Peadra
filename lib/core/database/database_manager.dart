import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../models/account.dart';
import '../models/description.dart';
import '../models/transaction.dart';

import '../utils/constants.dart';
import '../services/currency_service.dart';
import '../services/auth_service.dart';
import '../services/encryption_service.dart';
import '../i18n/translator.dart';

class DatabaseManager {
  static Database? _database;
  int? _userId;
  final Map<String, String?> _settingCache = {};
  final Map<String, String?> _appSettingCache = {};
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

  // ==================== USER ====================

  void setUserId(int userId) {
    _userId = userId;
    _insertDefaultAccounts();
    cleanupUnusedDescriptions();
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

    final results = <AccountWithBalance>[];
    for (final acctRow in acctRows) {
      final startingAmount = await _decryptAmount(acctRow['starting_amount'] as String?);

      final txnRows = await db.rawQuery('''
        SELECT transaction_type, amount FROM transactions
        WHERE account_id = ? AND user_id = ?
      ''', [acctRow['id'], _userId]);

      double balance = startingAmount;
      for (final txn in txnRows) {
        final amount = await _decryptAmount(txn['amount'] as String?);
        final type = txn['transaction_type'] as String;
        if (type == 'income') {
          balance += amount;
        } else if (type == 'expense') {
          balance -= amount;
        }
      }

      if (acctRow['currency'] == null || (acctRow['currency'] as String).isEmpty) {
        acctRow['currency'] = defaultCurrency;
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
      final newTransferFrom = 'Transfer from $oldName';
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
      await db.delete('transactions',
          where: 'account_id = ? AND user_id = ?', whereArgs: [accountId, _userId]);
    } else {
      await db.rawUpdate(
        'UPDATE transactions SET account_id = NULL WHERE account_id = ? AND user_id = ?',
        [accountId, _userId],
      );
    }

    await db.delete('accounts',
        where: 'id = ? AND user_id = ?', whereArgs: [accountId, _userId]);
    return true;
  }

  Future<int> mergeAccounts(int sourceId, int targetId) async {
    final db = await database;
    return await db.rawUpdate(
      'UPDATE transactions SET account_id = ? WHERE account_id = ? AND user_id = ?',
      [targetId, sourceId, _userId],
    );
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
    final db = await database;
    final normalized = name.trim();

    final allDescs = await db.rawQuery(
      'SELECT id, name FROM descriptions WHERE user_id = ?',
      [_userId],
    );
    for (final row in allDescs) {
      final decrypted = await _decrypt(row['name'] as String?);
      if (decrypted != null && decrypted.toLowerCase() == normalized.toLowerCase()) {
        return row['id'] as int;
      }
    }

    final encryptedName = await _encrypt(normalized);
    return await db.insert('descriptions', {
      'user_id': _userId,
      'name': encryptedName,
    });
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
    await db.delete('descriptions',
        where: 'id = ? AND user_id = ?', whereArgs: [sourceId, _userId]);
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
    return count > 0;
  }

  Future<void> cleanupUnusedDescriptions() async {
    if (_userId == null) return;
    final db = await database;
    await db.rawDelete('''
      DELETE FROM descriptions
      WHERE user_id = ?
        AND id NOT IN (SELECT DISTINCT description_id FROM transactions WHERE user_id = ?)
    ''', [_userId, _userId]);
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
    String? notes,
    String? currency,
  }) async {
    final db = await database;
    final updates = <String, dynamic>{};
    if (date != null) updates['date'] = date;
    if (amount != null) updates['amount'] = await _encrypt(amount.toString());
    if (transactionType != null) updates['transaction_type'] = transactionType;
    if (accountId != null) updates['account_id'] = accountId;
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
  }) async {
    final db = await database;
    var query = '''
      SELECT t.*, a.name as account_name, a.color as account_color,
             a.currency as account_currency, d.name as description_name
      FROM transactions t
      LEFT JOIN accounts a ON t.account_id = a.id
      LEFT JOIN descriptions d ON t.description_id = d.id
      WHERE t.user_id = ?
      ORDER BY t.date DESC, t.id DESC
    ''';

    final rows = await db.rawQuery(query, [_userId]);

    final results = <TransactionWithDetails>[];
    for (final r in rows) {
      final amount = await _decryptAmount(r['amount'] as String?);
      final notes = await _decrypt(r['notes'] as String?);
      final accountName = await _decrypt(r['account_name'] as String?);
      final descriptionName = await _decrypt(r['description_name'] as String?);

      if (accountIds != null && accountIds.isNotEmpty) {
        final acctId = r['account_id'] as int?;
        if (acctId == null || !accountIds.contains(acctId)) continue;
      }

      if (searchQuery.isNotEmpty) {
        final sq = searchQuery.toLowerCase();
        final descMatch = descriptionName?.toLowerCase().contains(sq) ?? false;
        final acctMatch = accountName?.toLowerCase().contains(sq) ?? false;
        if (!descMatch && !acctMatch) continue;
      }

      results.add(TransactionWithDetails(
        id: r['id'] as int?,
        userId: r['user_id'] as int,
        accountId: r['account_id'] as int?,
        descriptionId: r['description_id'] as int?,
        date: r['date'] as String,
        amount: amount,
        transactionType: r['transaction_type'] as String,
        currency: r['currency'] as String? ?? 'EUR',
        notes: notes,
        createdAt: r['created_at'] as String?,
        updatedAt: r['updated_at'] as String?,
        accountName: accountName,
        accountColor: r['account_color'] as String?,
        accountCurrency: r['account_currency'] as String?,
        descriptionName: descriptionName,
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
             a.currency as account_currency, d.name as description_name
      FROM transactions t
      LEFT JOIN accounts a ON t.account_id = a.id
      LEFT JOIN descriptions d ON t.description_id = d.id
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
        date: r['date'] as String,
        amount: await _decryptAmount(r['amount'] as String?),
        transactionType: r['transaction_type'] as String,
        currency: r['currency'] as String? ?? 'EUR',
        notes: await _decrypt(r['notes'] as String?),
        createdAt: r['created_at'] as String?,
        updatedAt: r['updated_at'] as String?,
        accountName: await _decrypt(r['account_name'] as String?),
        accountColor: r['account_color'] as String?,
        accountCurrency: r['account_currency'] as String?,
        descriptionName: await _decrypt(r['description_name'] as String?),
      ));
    }
    return results;
  }

  Future<String?> getEarliestTransactionDate() async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT MIN(date) FROM transactions WHERE user_id = ?',
      [_userId],
    );
    return result.first['MIN(date)'] as String?;
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

  Future<double> getSavingsTotal({String targetCurrency = 'EUR'}) async {
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
      'WHERE a.type = ? AND t.user_id = ?',
      ['savings', _userId],
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

  Future<double> getHistoryPatrimony(String dateLimit, {String targetCurrency = 'EUR'}) async {
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
      'SELECT t.amount, t.transaction_type, '
      'COALESCE(NULLIF(a.currency, \'\'), \'EUR\') as currency '
      'FROM transactions t LEFT JOIN accounts a ON t.account_id = a.id '
      'WHERE t.date < ? AND t.user_id = ?',
      [dateLimit, _userId],
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

  Future<double> getHistoryBalance(String dateLimit, {String targetCurrency = 'EUR'}) async {
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
      'FROM transactions t LEFT JOIN accounts a ON t.account_id = a.id '
      'WHERE t.date < ? AND t.user_id = ?',
      [dateLimit, _userId],
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

  Future<double> getHistorySavings(String dateLimit, {String targetCurrency = 'EUR'}) async {
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
      'WHERE t.date < ? AND a.type = ? AND t.user_id = ?',
      [dateLimit, 'savings', _userId],
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
      'SELECT t.amount, t.transaction_type, '
      'COALESCE(NULLIF(a.currency, \'\'), \'EUR\') as currency, a.type as account_type '
      'FROM transactions t LEFT JOIN accounts a ON t.account_id = a.id '
      'WHERE t.date >= ? AND t.date < ? AND t.user_id = ?',
      [startDate, endDate, _userId],
    );

    double income = 0.0;
    double expenses = 0.0;
    for (final row in txnRows) {
      final accountType = row['account_type'] as String?;
      final hasAccount = row['account_id'] != null;
      if (accountType != 'checking' && hasAccount) continue;

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
      'SELECT t.amount, t.transaction_type, '
      'COALESCE(NULLIF(a.currency, \'\'), \'EUR\') as currency, a.type as account_type '
      'FROM transactions t LEFT JOIN accounts a ON t.account_id = a.id '
      'WHERE t.date >= ? AND t.date <= ? AND t.user_id = ?',
      [startDate, endDate, _userId],
    );

    double income = 0.0;
    double expenses = 0.0;
    for (final row in txnRows) {
      final accountType = row['account_type'] as String?;
      final hasAccount = row['account_id'] != null;
      if (accountType != 'checking' && hasAccount) continue;

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

    final results = <Map<String, dynamic>>[];
    for (final acctRow in acctRows) {
      final startingAmount = await _decryptAmount(acctRow['starting_amount'] as String?);

      final txnRows = await db.rawQuery(
        'SELECT transaction_type, amount FROM transactions WHERE account_id = ? AND user_id = ?',
        [acctRow['id'], _userId],
      );

      double balance = startingAmount;
      for (final txn in txnRows) {
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

  Future<List<Map<String, dynamic>>> getCategoryDistribution({
    String transactionType = 'expense',
    int limit = 8,
  }) async {
    final db = await database;
    final now = DateTime.now();
    final startDate = now.subtract(const Duration(days: 180)).toIso8601String().substring(0, 10);
    final endDate = now.toIso8601String().substring(0, 10);

    final rows = await db.rawQuery('''
      SELECT t.amount, t.transaction_type, t.date,
             d.name as description_name
      FROM transactions t
      LEFT JOIN descriptions d ON t.description_id = d.id
      WHERE t.transaction_type = ? AND t.date >= ? AND t.date <= ? AND t.user_id = ?
    ''', [transactionType, startDate, endDate, _userId]);

    final byDesc = <String, double>{};
    for (final row in rows) {
      final desc = await _decrypt(row['description_name'] as String?) ?? 'Uncategorized';
      if (_isTransferDescription(desc)) continue;
      final amount = await _decryptAmount(row['amount'] as String?);
      final month = (row['date'] as String).substring(0, 7);
      byDesc[desc] = (byDesc[desc] ?? 0) + amount;
    }

    final sorted = byDesc.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final topDescs = sorted.take(limit > 0 ? limit : sorted.length).map((e) => e.key).toSet();

    final results = <Map<String, dynamic>>[];
    for (final row in rows) {
      final desc = await _decrypt(row['description_name'] as String?) ?? 'Uncategorized';
      if (_isTransferDescription(desc)) continue;
      if (!topDescs.contains(desc)) continue;
      final amount = await _decryptAmount(row['amount'] as String?);
      final month = (row['date'] as String).substring(0, 7);
      results.add({
        'description': desc,
        'month': month,
        'type': row['transaction_type'],
        'amount': amount,
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

  Future<List<Map<String, dynamic>>> getMonthlyChartData({int? year}) async {
    final db = await database;
    final y = year ?? DateTime.now().year;
    final rows = await db.rawQuery(
      'SELECT t.amount, t.transaction_type, t.date, '
      'a.type as account_type '
      'FROM transactions t LEFT JOIN accounts a ON t.account_id = a.id '
      'WHERE strftime("%Y", t.date) = ? AND t.user_id = ?',
      [y.toString(), _userId],
    );

    final monthMap = <int, Map<String, double>>{};
    for (final row in rows) {
      final accountType = row['account_type'] as String?;
      final hasAccount = row['account_id'] != null;
      if (accountType != 'checking' && hasAccount) continue;

      final month = int.parse((row['date'] as String).substring(5, 7));
      final amount = await _decryptAmount(row['amount'] as String?);
      final type = row['transaction_type'] as String;

      monthMap.putIfAbsent(month, () => {'income': 0.0, 'expenses': 0.0});
      if (type == 'income') {
        monthMap[month]!['income'] = monthMap[month]!['income']! + amount;
      } else if (type == 'expense') {
        monthMap[month]!['expenses'] = monthMap[month]!['expenses']! + amount;
      }
    }

    final result = <Map<String, dynamic>>[];
    for (final entry in monthMap.entries) {
      result.add({
        'month': entry.key,
        'income': entry.value['income']!,
        'expenses': entry.value['expenses']!,
      });
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

    final results = <Map<String, dynamic>>[];

    for (int i = effectiveMonths; i >= 1; i--) {
      final month = DateTime(now.year, now.month - i + 1, 1);
      final nextMonth = DateTime(month.year, month.month + 1, 1);
      final endDate = nextMonth.toIso8601String().substring(0, 10);

      final txnRows = await db.rawQuery(
        'SELECT t.amount, t.transaction_type, '
        'COALESCE(NULLIF(a.currency, \'\'), \'EUR\') as currency '
        'FROM transactions t LEFT JOIN accounts a ON t.account_id = a.id '
        'WHERE t.date < ? AND t.user_id = ?',
        [endDate, _userId],
      );

      double totalValue = startingTotal;
      for (final row in txnRows) {
        final amount = await _decryptAmount(row['amount'] as String?);
        final type = row['transaction_type'] as String;
        final txnCurrency = (row['currency'] as String?) ?? 'EUR';
        final signedAmount = type == 'income' ? amount : (type == 'expense' ? -amount : 0.0);

        if (txnCurrency == targetCurrency) {
          totalValue += signedAmount;
        } else {
          final rate = await getExchangeRate(txnCurrency, targetCurrency);
          totalValue += signedAmount * (rate ?? 1.0);
        }
      }

      results.add({
        'month': month,
        'label': _getMonthLabel(month.month),
        'value': totalValue,
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

  Future<double> getPreviousMonthTotal() async {
    final db = await database;
    final now = DateTime.now();
    final previousMonth = DateTime(now.year, now.month - 1, 1);
    final startDate = previousMonth.toIso8601String().substring(0, 10);
    final endMonth = DateTime(now.year, now.month, 1);
    final endDate = endMonth.toIso8601String().substring(0, 10);

    final rows = await db.rawQuery(
      'SELECT amount, transaction_type FROM transactions '
      'WHERE date >= ? AND date < ? AND user_id = ?',
      [startDate, endDate, _userId],
    );

    double total = 0.0;
    for (final row in rows) {
      final amount = await _decryptAmount(row['amount'] as String?);
      final type = row['transaction_type'] as String;
      if (type == 'income') {
        total += amount;
      } else if (type == 'expense') {
        total -= amount;
      }
    }
    return total;
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

  // ==================== IMPORT ====================

  Future<bool> isFileImported(String fileHash) async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) as cnt FROM imported_files WHERE file_hash = ? AND user_id = ?',
      [fileHash, _userId],
    );
    return (result.first['cnt'] as int) > 0;
  }

  Future<void> logImportedFile(String fileHash, String filename) async {
    final db = await database;
    await db.rawInsert(
      'INSERT INTO imported_files (user_id, file_hash, filename) VALUES (?, ?, ?)',
      [_userId, fileHash, filename],
    );
  }

  // ==================== EXPORT ====================

  Future<Map<String, dynamic>> exportToJson() async {
    final accounts = await getAllAccounts();
    final transactions = await getTransactions();
    return {
      'accounts': accounts.map((a) => a.toMap()).toList(),
      'transactions': transactions.map((t) => t.toMap()).toList(),
      'exported_at': DateTime.now().toIso8601String(),
    };
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
    final db = await database;

    // Direct rate
    var result = await db.rawQuery(
      'SELECT rate FROM exchange_rates WHERE from_currency = ? AND to_currency = ?',
      [fromCurrency, toCurrency],
    );
    if (result.isNotEmpty) return (result.first['rate'] as num).toDouble();

    // Via base
    if (fromCurrency == 'EUR') {
      result = await db.rawQuery(
        'SELECT rate FROM exchange_rates WHERE from_currency = ? AND to_currency = ?',
        ['EUR', toCurrency],
      );
      if (result.isNotEmpty) return (result.first['rate'] as num).toDouble();
      return null;
    }

    // Inverse
    result = await db.rawQuery(
      'SELECT rate FROM exchange_rates WHERE from_currency = ? AND to_currency = ?',
      [toCurrency, fromCurrency],
    );
    if (result.isNotEmpty) return 1.0 / (result.first['rate'] as num).toDouble();

    // Via EUR
    final fromEur = await getExchangeRate('EUR', fromCurrency);
    final toEur = await getExchangeRate('EUR', toCurrency);
    if (fromEur != null && toEur != null) return toEur / fromEur;

    return null;
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
