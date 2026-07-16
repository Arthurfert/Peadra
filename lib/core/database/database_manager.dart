import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../models/account.dart';
import '../models/description.dart';
import '../models/transaction.dart';

import '../utils/constants.dart';
import '../services/currency_service.dart';
import '../services/auth_service.dart';
import '../i18n/translator.dart';

class DatabaseManager {
  static Database? _database;
  int? _userId;
  final Map<String, String?> _settingCache = {};
  final Map<String, String?> _appSettingCache = {};

  DatabaseManager._();
  static final DatabaseManager instance = DatabaseManager._();

  int? get userId => _userId;

  Future<Database> get database async {
    _database ??= await _initDatabase();
    return _database!;
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
      final peadraDir = Directory(join(home, '.Peadra'));
      if (!peadraDir.existsSync()) {
        await peadraDir.create(recursive: true);
      }
      path = join(peadraDir.path, dbName);
    }

    return openDatabase(
      path,
      version: dbVersion,
      onCreate: _onCreate,
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
      orderBy: 'name',
    );
    return rows.map((r) => Account.fromMap(r)).toList();
  }

  Future<List<AccountWithBalance>> getAccountsWithBalances() async {
    final db = await database;
    final rows = await db.rawQuery('''
      SELECT a.*,
             COALESCE(SUM(CASE WHEN t.transaction_type = 'income' THEN t.amount
                                WHEN t.transaction_type = 'expense' THEN -t.amount
                                ELSE 0 END), 0) AS balance
      FROM accounts a
      LEFT JOIN transactions t ON t.account_id = a.id AND t.user_id = ?
      WHERE a.user_id = ?
      GROUP BY a.id
      ORDER BY a.name
    ''', [_userId, _userId]);

    return rows.map((r) {
      if (r['currency'] == null || (r['currency'] as String).isEmpty) {
        r['currency'] = defaultCurrency;
      }
      return AccountWithBalance.fromMap(r);
    }).toList();
  }

  Future<int?> addAccount(String name, String color, String type, String currency) async {
    final db = await database;
    try {
      return await db.insert('accounts', {
        'user_id': _userId,
        'name': name,
        'color': color,
        'type': type,
        'currency': currency,
      });
    } catch (_) {
      return -1;
    }
  }

  Future<bool> updateAccount(int accountId, String name, String color,
      {String? type, String? currency, bool updateNameInTransactions = false}) async {
    final db = await database;
    final existing = await db.query(
      'accounts',
      where: 'id = ? AND user_id = ?',
      whereArgs: [accountId, _userId],
    );
    if (existing.isEmpty) return false;

    final oldName = existing.first['name'] as String;
    final oldCurrency = (existing.first['currency'] as String?) ?? defaultCurrency;
    final effectiveCurrency = currency ?? oldCurrency;

    final updates = <String, dynamic>{
      'name': name,
      'color': color,
      'currency': effectiveCurrency,
    };
    if (type != null) updates['type'] = type;

    final count = await db.update(
      'accounts',
      updates,
      where: 'id = ? AND user_id = ?',
      whereArgs: [accountId, _userId],
    );

    if (count > 0 && updateNameInTransactions && oldName != name) {
      await db.rawUpdate(
        "UPDATE transactions SET notes = REPLACE(notes, ?, ?) WHERE notes LIKE ? AND user_id = ?",
        ['Transfer to $oldName', 'Transfer to $name', 'Transfer to %', _userId],
      );
      await db.rawUpdate(
        "UPDATE transactions SET notes = REPLACE(notes, ?, ?) WHERE notes LIKE ? AND user_id = ?",
        ['Transfer from $oldName', 'Transfer from $name', 'Transfer from %', _userId],
      );
      await db.rawUpdate(
        "UPDATE descriptions SET name = REPLACE(name, ?, ?) WHERE name LIKE ? AND user_id = ?",
        ['Transfer to $oldName', 'Transfer to $name', 'Transfer to %', _userId],
      );
      await db.rawUpdate(
        "UPDATE descriptions SET name = REPLACE(name, ?, ?) WHERE name LIKE ? AND user_id = ?",
        ['Transfer from $oldName', 'Transfer from $name', 'Transfer from %', _userId],
      );
    }

    return count > 0;
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
      orderBy: 'name',
    );
    return rows.map((r) => Description.fromMap(r)).toList();
  }

  Future<int> getOrCreateDescription(String name) async {
    final db = await database;
    final existing = await db.query(
      'descriptions',
      where: 'user_id = ? AND name = ?',
      whereArgs: [_userId, name],
    );
    if (existing.isNotEmpty) return existing.first['id'] as int;

    return await db.insert('descriptions', {
      'user_id': _userId,
      'name': name,
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
    final count = await db.rawUpdate(
      'UPDATE descriptions SET name = ? WHERE id = ? AND user_id = ?',
      [newName.trim(), descriptionId, _userId],
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

    return await db.insert('transactions', {
      'user_id': _userId,
      'account_id': accountId,
      'description_id': descId,
      'date': date,
      'amount': amount,
      'transaction_type': transactionType,
      'currency': effectiveCurrency,
      'notes': notes,
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
    if (amount != null) updates['amount'] = amount;
    if (transactionType != null) updates['transaction_type'] = transactionType;
    if (accountId != null) updates['account_id'] = accountId;
    if (notes != null) updates['notes'] = notes;
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
    final where = <String>['t.user_id = ?'];
    final args = <dynamic>[_userId];

    if (searchQuery.isNotEmpty) {
      where.add('(LOWER(d.name) LIKE ? OR LOWER(a.name) LIKE ?)');
      final sq = '%${searchQuery.toLowerCase()}%';
      args.addAll([sq, sq]);
    }

    if (accountIds != null && accountIds.isNotEmpty) {
      final placeholders = accountIds.map((_) => '?').join(',');
      where.add('t.account_id IN ($placeholders)');
      args.addAll(accountIds);
    }

    var query = '''
      SELECT t.*, a.name as account_name, a.color as account_color,
             a.currency as account_currency, d.name as description_name
      FROM transactions t
      LEFT JOIN accounts a ON t.account_id = a.id
      LEFT JOIN descriptions d ON t.description_id = d.id
      WHERE ${where.join(' AND ')}
      ORDER BY t.date DESC, t.id DESC
    ''';

    if (limit != null) {
      query += ' LIMIT ? OFFSET ?';
      args.addAll([limit, offset]);
    }

    final rows = await db.rawQuery(query, args);
    return rows.map((r) => TransactionWithDetails.fromMap(r)).toList();
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
    return rows.map((r) => TransactionWithDetails.fromMap(r)).toList();
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
    final result = await db.rawQuery('''
      SELECT COALESCE(SUM(CASE WHEN t.transaction_type = 'income' THEN t.amount
                               WHEN t.transaction_type = 'expense' THEN -t.amount
                               ELSE 0 END), 0) as total,
             COALESCE(NULLIF(t.currency, ''), 'EUR') as currency
      FROM transactions t WHERE t.user_id = ?
      GROUP BY currency
    ''', [_userId]);

    double total = 0.0;
    for (final row in result) {
      final amount = (row['total'] as num?)?.toDouble() ?? 0.0;
      final txnCurrency = (row['currency'] as String?) ?? 'EUR';
      if (txnCurrency == targetCurrency) {
        total += amount;
      } else {
        final rate = await getExchangeRate(txnCurrency, targetCurrency);
        total += amount * (rate ?? 1.0);
      }
    }
    return total;
  }

  Future<double> getBalance({String targetCurrency = 'EUR'}) async {
    final db = await database;
    final rows = await db.rawQuery('''
      SELECT COALESCE(SUM(CASE WHEN t.transaction_type = 'income' THEN t.amount
                               WHEN t.transaction_type = 'expense' THEN -t.amount
                               ELSE 0 END), 0) as total,
             COALESCE(NULLIF(a.currency, ''), 'EUR') as currency
      FROM transactions t
      LEFT JOIN accounts a ON t.account_id = a.id
      WHERE (a.type = 'checking' OR t.account_id IS NULL) AND t.user_id = ?
      GROUP BY a.currency
    ''', [_userId]);

    double total = 0.0;
    for (final row in rows) {
      final amount = (row['total'] as num?)?.toDouble() ?? 0.0;
      final txnCurrency = (row['currency'] as String?) ?? 'EUR';
      if (txnCurrency == targetCurrency) {
        total += amount;
      } else {
        final rate = await getExchangeRate(txnCurrency, targetCurrency);
        total += amount * (rate ?? 1.0);
      }
    }
    return total;
  }

  Future<double> getSavingsTotal({String targetCurrency = 'EUR'}) async {
    final db = await database;
    final rows = await db.rawQuery('''
      SELECT COALESCE(SUM(CASE WHEN t.transaction_type = 'income' THEN t.amount
                               WHEN t.transaction_type = 'expense' THEN -t.amount
                               ELSE 0 END), 0) as total,
             COALESCE(NULLIF(a.currency, ''), 'EUR') as currency
      FROM transactions t
      LEFT JOIN accounts a ON t.account_id = a.id
      WHERE a.type = 'savings' AND t.user_id = ?
      GROUP BY a.currency
    ''', [_userId]);

    double total = 0.0;
    for (final row in rows) {
      final amount = (row['total'] as num?)?.toDouble() ?? 0.0;
      final txnCurrency = (row['currency'] as String?) ?? 'EUR';
      if (txnCurrency == targetCurrency) {
        total += amount;
      } else {
        final rate = await getExchangeRate(txnCurrency, targetCurrency);
        total += amount * (rate ?? 1.0);
      }
    }
    return total;
  }

  Future<double> getHistoryPatrimony(String dateLimit, {String targetCurrency = 'EUR'}) async {
    final db = await database;
    final rows = await db.rawQuery('''
      SELECT COALESCE(SUM(CASE WHEN t.transaction_type = 'income' THEN t.amount
                               WHEN t.transaction_type = 'expense' THEN -t.amount
                               ELSE 0 END), 0) as total,
             COALESCE(NULLIF(t.currency, ''), 'EUR') as currency
      FROM transactions t WHERE t.date < ? AND t.user_id = ?
      GROUP BY currency
    ''', [dateLimit, _userId]);

    double total = 0.0;
    for (final row in rows) {
      final amount = (row['total'] as num?)?.toDouble() ?? 0.0;
      final txnCurrency = (row['currency'] as String?) ?? 'EUR';
      if (txnCurrency == targetCurrency) {
        total += amount;
      } else {
        final rate = await getExchangeRate(txnCurrency, targetCurrency);
        total += amount * (rate ?? 1.0);
      }
    }
    return total;
  }

  Future<double> getHistoryBalance(String dateLimit, {String targetCurrency = 'EUR'}) async {
    final db = await database;
    final rows = await db.rawQuery('''
      SELECT COALESCE(SUM(CASE WHEN t.transaction_type = 'income' THEN t.amount
                               WHEN t.transaction_type = 'expense' THEN -t.amount
                               ELSE 0 END), 0) as total,
             COALESCE(NULLIF(a.currency, ''), 'EUR') as currency
      FROM transactions t
      LEFT JOIN accounts a ON t.account_id = a.id
      WHERE t.date < ? AND (a.type = 'checking' OR t.account_id IS NULL) AND t.user_id = ?
      GROUP BY a.currency
    ''', [dateLimit, _userId]);

    double total = 0.0;
    for (final row in rows) {
      final amount = (row['total'] as num?)?.toDouble() ?? 0.0;
      final txnCurrency = (row['currency'] as String?) ?? 'EUR';
      if (txnCurrency == targetCurrency) {
        total += amount;
      } else {
        final rate = await getExchangeRate(txnCurrency, targetCurrency);
        total += amount * (rate ?? 1.0);
      }
    }
    return total;
  }

  Future<double> getHistorySavings(String dateLimit, {String targetCurrency = 'EUR'}) async {
    final db = await database;
    final rows = await db.rawQuery('''
      SELECT COALESCE(SUM(CASE WHEN t.transaction_type = 'income' THEN t.amount
                               WHEN t.transaction_type = 'expense' THEN -t.amount
                               ELSE 0 END), 0) as total,
             COALESCE(NULLIF(a.currency, ''), 'EUR') as currency
      FROM transactions t
      LEFT JOIN accounts a ON t.account_id = a.id
      WHERE t.date < ? AND a.type = 'savings' AND t.user_id = ?
      GROUP BY a.currency
    ''', [dateLimit, _userId]);

    double total = 0.0;
    for (final row in rows) {
      final amount = (row['total'] as num?)?.toDouble() ?? 0.0;
      final txnCurrency = (row['currency'] as String?) ?? 'EUR';
      if (txnCurrency == targetCurrency) {
        total += amount;
      } else {
        final rate = await getExchangeRate(txnCurrency, targetCurrency);
        total += amount * (rate ?? 1.0);
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
    final rows = await db.rawQuery('''
      SELECT
        COALESCE(SUM(CASE WHEN t.transaction_type = 'income' THEN t.amount ELSE 0 END), 0) as income,
        COALESCE(SUM(CASE WHEN t.transaction_type = 'expense' THEN t.amount ELSE 0 END), 0) as expenses,
        COALESCE(NULLIF(a.currency, ''), 'EUR') as currency
      FROM transactions t
      LEFT JOIN accounts a ON t.account_id = a.id
      WHERE (t.date >= ? AND t.date < ?) AND (a.type = 'checking' OR t.account_id IS NULL) AND t.user_id = ?
      GROUP BY a.currency
    ''', [startDate, endDate, _userId]);

    double income = 0.0;
    double expenses = 0.0;
    for (final row in rows) {
      final txnIncome = (row['income'] as num?)?.toDouble() ?? 0.0;
      final txnExpenses = (row['expenses'] as num?)?.toDouble() ?? 0.0;
      final txnCurrency = (row['currency'] as String?) ?? 'EUR';

      if (txnCurrency == targetCurrency) {
        income += txnIncome;
        expenses += txnExpenses;
      } else {
        final rate = await getExchangeRate(txnCurrency, targetCurrency);
        final factor = rate ?? 1.0;
        income += txnIncome * factor;
        expenses += txnExpenses * factor;
      }
    }
    return {'income': income, 'expenses': expenses, 'balance': income - expenses};
  }

  Future<Map<String, double>> getRollingSummary({int days = 30, String targetCurrency = 'EUR'}) async {
    final now = DateTime.now();
    final endDate = now.toIso8601String().substring(0, 10);
    final startDate = now.subtract(Duration(days: days)).toIso8601String().substring(0, 10);

    final db = await database;
    final rows = await db.rawQuery('''
      SELECT
        COALESCE(SUM(CASE WHEN t.transaction_type = 'income' THEN t.amount ELSE 0 END), 0) as income,
        COALESCE(SUM(CASE WHEN t.transaction_type = 'expense' THEN t.amount ELSE 0 END), 0) as expenses,
        COALESCE(NULLIF(a.currency, ''), 'EUR') as currency
      FROM transactions t
      LEFT JOIN accounts a ON t.account_id = a.id
      WHERE (t.date >= ? AND t.date <= ?) AND (a.type = 'checking' OR t.account_id IS NULL) AND t.user_id = ?
      GROUP BY a.currency
    ''', [startDate, endDate, _userId]);

    double income = 0.0;
    double expenses = 0.0;
    for (final row in rows) {
      final txnIncome = (row['income'] as num?)?.toDouble() ?? 0.0;
      final txnExpenses = (row['expenses'] as num?)?.toDouble() ?? 0.0;
      final txnCurrency = (row['currency'] as String?) ?? 'EUR';

      if (txnCurrency == targetCurrency) {
        income += txnIncome;
        expenses += txnExpenses;
      } else {
        final rate = await getExchangeRate(txnCurrency, targetCurrency);
        final factor = rate ?? 1.0;
        income += txnIncome * factor;
        expenses += txnExpenses * factor;
      }
    }
    return {'income': income, 'expenses': expenses, 'balance': income - expenses};
  }

  Future<List<Map<String, dynamic>>> getAccountsDistribution({String targetCurrency = 'EUR'}) async {
    final db = await database;
    final rows = await db.rawQuery('''
      SELECT a.name, a.color, a.currency as account_currency,
             COALESCE(SUM(CASE WHEN t.transaction_type = 'income' THEN t.amount
                               WHEN t.transaction_type = 'expense' THEN -t.amount
                               ELSE 0 END), 0) AS balance
      FROM accounts a
      LEFT JOIN transactions t ON t.account_id = a.id AND t.user_id = ?
      WHERE a.user_id = ?
      GROUP BY a.id
      ORDER BY a.name
    ''', [_userId, _userId]);

    final results = <Map<String, dynamic>>[];
    for (final row in rows) {
      final rawBalance = (row['balance'] as num?)?.toDouble() ?? 0.0;
      final acctCurrency = (row['account_currency'] as String?) ?? 'EUR';

      double convertedBalance;
      if (acctCurrency == targetCurrency) {
        convertedBalance = rawBalance;
      } else {
        final rate = await getExchangeRate(acctCurrency, targetCurrency);
        convertedBalance = rawBalance * (rate ?? 1.0);
      }

      results.add({
        'name': row['name'],
        'color': row['color'],
        'value': convertedBalance,
        'nativeValue': rawBalance,
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
      SELECT LOWER(COALESCE(d.name, 'Uncategorized')) as description,
             strftime('%Y-%m', t.date) as month,
             t.transaction_type as type,
             SUM(t.amount) as amount
      FROM transactions t
      LEFT JOIN descriptions d ON t.description_id = d.id
      WHERE t.transaction_type = ? AND t.date >= ? AND t.date <= ? AND t.user_id = ?
      GROUP BY description, month, t.transaction_type
      ORDER BY month, amount DESC
    ''', [transactionType, startDate, endDate, _userId]);

    final results = <Map<String, dynamic>>[];
    for (final row in rows) {
      final desc = (row['description'] as String?) ?? 'Uncategorized';
      if (_isTransferDescription(desc)) continue;
      results.add({
        'description': desc,
        'month': row['month'],
        'type': row['type'],
        'amount': (row['amount'] as num).toDouble(),
      });
    }

    // If limit is set, group and take top N
    if (limit > 0) {
      final byDesc = <String, double>{};
      for (final r in results) {
        final d = r['description'] as String;
        byDesc[d] = (byDesc[d] ?? 0) + (r['amount'] as double);
      }
      final sorted = byDesc.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      final topDescs = sorted.take(limit).map((e) => e.key).toSet();
      return results.where((r) => topDescs.contains(r['description'])).toList();
    }

    return results;
  }

  Future<Map<String, Map<String, Map<String, double>>>> getDescriptionMonthlyData(
      String startDate, String endDate) async {
    final db = await database;
    final rows = await db.rawQuery('''
      SELECT LOWER(COALESCE(d.name, 'Uncategorized')) as desc,
             strftime('%Y-%m', t.date) as month,
             t.transaction_type,
             SUM(t.amount) as total
      FROM transactions t
      LEFT JOIN descriptions d ON t.description_id = d.id
      WHERE t.date >= ? AND t.date <= ? AND t.user_id = ?
      GROUP BY desc, month, t.transaction_type
      ORDER BY desc, month
    ''', [startDate, endDate, _userId]);

    final result = <String, Map<String, Map<String, double>>>{};
    for (final row in rows) {
      final desc = (row['desc'] as String?) ?? 'uncategorized';
      final month = row['month'] as String;
      final type = row['transaction_type'] as String;
      final total = (row['total'] as num).toDouble();

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
      SELECT LOWER(COALESCE(d.name, 'Uncategorized')) as desc,
             SUM(t.amount) as total,
             COUNT(t.id) as count
      FROM transactions t
      LEFT JOIN descriptions d ON t.description_id = d.id
      WHERE t.transaction_type = ? AND t.date >= ? AND t.date <= ? AND t.user_id = ?
      GROUP BY desc
      HAVING count >= ?
      ORDER BY total DESC
    ''', [transactionType, startDate, endDate, _userId, minCount]);

    final results = <Map<String, dynamic>>[];
    for (final row in rows) {
      final desc = (row['desc'] as String?) ?? 'Uncategorized';
      if (!_isTransferDescription(desc)) {
        results.add({'description': desc, 'total': row['total'], 'count': row['count']});
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
    final rows = await db.rawQuery('''
      SELECT strftime('%m', t.date) as month,
             COALESCE(SUM(CASE WHEN t.transaction_type = 'income' THEN t.amount ELSE 0 END), 0) as income,
             COALESCE(SUM(CASE WHEN t.transaction_type = 'expense' THEN t.amount ELSE 0 END), 0) as expenses
      FROM transactions t
      LEFT JOIN accounts a ON t.account_id = a.id
      WHERE strftime('%Y', t.date) = ? AND (a.type = 'checking' OR t.account_id IS NULL) AND t.user_id = ?
      GROUP BY month
      ORDER BY month
    ''', [y.toString(), _userId]);

    final result = <Map<String, dynamic>>[];
    for (final row in rows) {
      result.add({
        'month': int.parse(row['month'] as String),
        'income': (row['income'] as num).toDouble(),
        'expenses': (row['expenses'] as num).toDouble(),
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

    final rows = await db.rawQuery('''
      SELECT strftime('%Y-%m', t.date) as month,
             t.transaction_type as type,
             SUM(t.amount) as amount,
             COALESCE(NULLIF(a.currency, ''), 'EUR') as currency
      FROM transactions t
      LEFT JOIN accounts a ON t.account_id = a.id
      LEFT JOIN descriptions d ON t.description_id = d.id
      WHERE t.date >= ? AND t.user_id = ?
        AND (d.name IS NULL OR LOWER(d.name) NOT LIKE 'transfer to %' AND LOWER(d.name) NOT LIKE 'transfer from %')
      GROUP BY month, t.transaction_type, a.currency
      ORDER BY month
    ''', [startDate, _userId]);

    final monthMap = <String, Map<String, double>>{};
    for (final r in rows) {
      final monthKey = r['month'] as String;
      final type = r['type'] as String;
      final amount = (r['amount'] as num).toDouble();
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
    final results = <Map<String, dynamic>>[];

    for (int i = months; i >= 1; i--) {
      final month = DateTime(now.year, now.month - i + 1, 1);
      final nextMonth = DateTime(month.year, month.month + 1, 1);
      final endDate = nextMonth.toIso8601String().substring(0, 10);

      final rows = await db.rawQuery('''
        SELECT COALESCE(SUM(CASE WHEN t.transaction_type = 'income' THEN t.amount
                                 WHEN t.transaction_type = 'expense' THEN -t.amount
                                 ELSE 0 END), 0) as total,
               COALESCE(NULLIF(a.currency, ''), 'EUR') as currency
        FROM transactions t
        LEFT JOIN accounts a ON t.account_id = a.id
        WHERE t.date < ? AND t.user_id = ?
        GROUP BY a.currency
      ''', [endDate, _userId]);

      double totalValue = 0.0;
      for (final row in rows) {
        final amount = (row['total'] as num?)?.toDouble() ?? 0.0;
        final txnCurrency = (row['currency'] as String?) ?? 'EUR';

        if (txnCurrency == targetCurrency) {
          totalValue += amount;
        } else {
          final rate = await getExchangeRate(txnCurrency, targetCurrency);
          totalValue += amount * (rate ?? 1.0);
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

    final rows = await db.rawQuery('''
      SELECT LOWER(COALESCE(d.name, 'Uncategorized')) as category,
             SUM(t.amount) as amount,
             COALESCE(NULLIF(t.currency, ''), 'EUR') as currency
      FROM transactions t
      LEFT JOIN descriptions d ON t.description_id = d.id
      WHERE t.transaction_type = ? AND t.date >= ? AND t.date <= ? AND t.user_id = ?
      GROUP BY category, t.currency
      ORDER BY amount DESC
    ''', [transactionType, startDate, endDate, _userId]);

    final result = <String, double>{};
    for (final row in rows) {
      final category = row['category'] as String;
      if (_isTransferDescription(category)) continue;
      final rawAmount = (row['amount'] as num).toDouble();
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

    final rows = await db.rawQuery('''
      SELECT LOWER(COALESCE(d.name, 'Uncategorized')) as category,
             SUM(t.amount) as amount,
             COALESCE(NULLIF(t.currency, ''), 'EUR') as currency
      FROM transactions t
      LEFT JOIN descriptions d ON t.description_id = d.id
      WHERE t.transaction_type = ? AND t.date >= ? AND t.date <= ? AND t.user_id = ?
      GROUP BY category, t.currency
      ORDER BY amount DESC
    ''', [transactionType, startDate, endDate, _userId]);

    final result = <String, double>{};
    for (final row in rows) {
      final category = row['category'] as String;
      if (_isTransferDescription(category)) continue;
      final rawAmount = (row['amount'] as num).toDouble();
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

    final result = await db.rawQuery('''
      SELECT COALESCE(SUM(CASE WHEN transaction_type = 'income' THEN amount
                               WHEN transaction_type = 'expense' THEN -amount
                               ELSE 0 END), 0) as total
      FROM transactions
      WHERE date >= ? AND date < ? AND user_id = ?
    ''', [startDate, endDate, _userId]);

    return (result.first['total'] as num?)?.toDouble() ?? 0.0;
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
