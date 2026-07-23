import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../helpers/test_helper.dart';

Future<Database> _openTestDb() async {
  return databaseFactoryFfi.openDatabase(
    inMemoryDatabasePath,
    options: OpenDatabaseOptions(
      version: 1,
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
      },
    ),
  );
}

void main() {
  late Database db;
  late int userId;
  late List<int> accountIds;

  setUpAll(() {
    initializeTestDatabase();
  });

  setUp(() async {
    db = await _openTestDb();
    userId = await seedTestUser(db);
    accountIds = await seedTestAccounts(db, userId);
  });

  tearDown(() async {
    await db.close();
  });

  Future<int> getOrCreateDescription(String name) async {
    final existing = await db.query(
      'descriptions',
      where: 'user_id = ? AND name = ?',
      whereArgs: [userId, name],
    );
    if (existing.isNotEmpty) return existing.first['id'] as int;
    return await db.insert('descriptions', {
      'user_id': userId,
      'name': name,
    });
  }

  Future<String?> getAccountCurrency(int accountId) async {
    final result = await db.rawQuery(
      'SELECT currency FROM accounts WHERE id = ? AND user_id = ?',
      [accountId, userId],
    );
    if (result.isEmpty) return null;
    return result.first['currency'] as String?;
  }

  Future<int> addTransaction({
    required String date,
    required String description,
    required double amount,
    required String transactionType,
    int? accountId,
    String? notes,
    String? currency,
  }) async {
    final descId = await getOrCreateDescription(description);
    String effectiveCurrency = currency ?? 'EUR';
    if (accountId != null) {
      final acctCurrency = await getAccountCurrency(accountId);
      if (acctCurrency != null) effectiveCurrency = acctCurrency;
    }
    return await db.insert('transactions', {
      'user_id': userId,
      'account_id': accountId,
      'description_id': descId,
      'date': date,
      'amount': amount,
      'transaction_type': transactionType,
      'currency': effectiveCurrency,
      'notes': notes,
    });
  }

  Future<bool> updateTransaction(
    int transactionId, {
    String? date,
    String? description,
    double? amount,
    String? transactionType,
    int? accountId,
    String? notes,
    String? currency,
  }) async {
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
      whereArgs: [transactionId, userId],
    );
    return count > 0;
  }

  Future<bool> deleteTransaction(int transactionId) async {
    final count = await db.delete(
      'transactions',
      where: 'id = ? AND user_id = ?',
      whereArgs: [transactionId, userId],
    );
    return count > 0;
  }

  Future<List<Map<String, dynamic>>> getTransactions({
    int? limit,
    int offset = 0,
    String searchQuery = '',
    Set<int>? accountIds,
  }) async {
    final where = <String>['t.user_id = ?'];
    final args = <dynamic>[userId];
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
    return await db.rawQuery(query, args);
  }

  Future<List<Map<String, dynamic>>> getTransactionsByPeriod(
      String startDate, String endDate) async {
    return await db.rawQuery('''
      SELECT t.*, a.name as account_name, a.color as account_color,
             a.currency as account_currency, d.name as description_name
      FROM transactions t
      LEFT JOIN accounts a ON t.account_id = a.id
      LEFT JOIN descriptions d ON t.description_id = d.id
      WHERE t.date BETWEEN ? AND ? AND t.user_id = ?
      ORDER BY t.date DESC
    ''', [startDate, endDate, userId]);
  }

  Future<String?> getEarliestTransactionDate() async {
    final result = await db.rawQuery(
      'SELECT MIN(date) FROM transactions WHERE user_id = ?',
      [userId],
    );
    return result.first['MIN(date)'] as String?;
  }

  group('Adding transactions', () {
    test('adds an income transaction with account', () async {
      final id = await addTransaction(
        date: '2025-01-15',
        description: 'Salary',
        amount: 3000.0,
        transactionType: 'income',
        accountId: accountIds[0],
      );

      expect(id, greaterThan(0));
      final rows = await db.query('transactions', where: 'id = ?', whereArgs: [id]);
      expect(rows.length, 1);
      expect(rows.first['date'], '2025-01-15');
      expect(rows.first['amount'], 3000.0);
      expect(rows.first['transaction_type'], 'income');
      expect(rows.first['account_id'], accountIds[0]);
      expect(rows.first['currency'], 'EUR');
    });

    test('adds an expense transaction', () async {
      final id = await addTransaction(
        date: '2025-03-10',
        description: 'Groceries',
        amount: 55.75,
        transactionType: 'expense',
        accountId: accountIds[0],
      );

      final rows = await db.query('transactions', where: 'id = ?', whereArgs: [id]);
      expect(rows.first['transaction_type'], 'expense');
      expect(rows.first['amount'], 55.75);
    });

    test('adds a transfer transaction', () async {
      final id = await addTransaction(
        date: '2025-02-20',
        description: 'Transfer to Savings',
        amount: 500.0,
        transactionType: 'transfer',
        accountId: accountIds[1],
      );

      final rows = await db.query('transactions', where: 'id = ?', whereArgs: [id]);
      expect(rows.first['transaction_type'], 'transfer');
    });

    test('adds a transaction with null account', () async {
      final id = await addTransaction(
        date: '2025-01-20',
        description: 'Cash income',
        amount: 200.0,
        transactionType: 'income',
      );

      final rows = await db.query('transactions', where: 'id = ?', whereArgs: [id]);
      expect(rows.first['account_id'], isNull);
      expect(rows.first['currency'], 'EUR');
    });

    test('adds a transaction with notes', () async {
      final id = await addTransaction(
        date: '2025-01-25',
        description: 'Freelance work',
        amount: 1500.0,
        transactionType: 'income',
        accountId: accountIds[0],
        notes: 'Project ABC invoice',
      );

      final rows = await db.query('transactions', where: 'id = ?', whereArgs: [id]);
      expect(rows.first['notes'], 'Project ABC invoice');
    });

    test('adds a transaction with explicit currency', () async {
      final id = await addTransaction(
        date: '2025-01-25',
        description: 'USD Income',
        amount: 100.0,
        transactionType: 'income',
        currency: 'USD',
      );

      final rows = await db.query('transactions', where: 'id = ?', whereArgs: [id]);
      expect(rows.first['currency'], 'USD');
    });

    test('creates description record for the transaction', () async {
      final id = await addTransaction(
        date: '2025-01-15',
        description: 'New Description',
        amount: 100.0,
        transactionType: 'income',
      );

      final descs = await db.query(
        'descriptions',
        where: 'user_id = ? AND name = ?',
        whereArgs: [userId, 'New Description'],
      );
      expect(descs.length, 1);

      final rows = await db.query('transactions', where: 'id = ?', whereArgs: [id]);
      expect(rows.first['description_id'], descs.first['id']);
    });

    test('reuses existing description with same name', () async {
      final id1 = await addTransaction(
        date: '2025-01-15',
        description: 'Rent',
        amount: 1000.0,
        transactionType: 'expense',
      );
      final id2 = await addTransaction(
        date: '2025-02-15',
        description: 'Rent',
        amount: 1000.0,
        transactionType: 'expense',
      );

      final descs = await db.query(
        'descriptions',
        where: 'user_id = ? AND name = ?',
        whereArgs: [userId, 'Rent'],
      );
      expect(descs.length, 1);

      final t1 = await db.query('transactions', where: 'id = ?', whereArgs: [id1]);
      final t2 = await db.query('transactions', where: 'id = ?', whereArgs: [id2]);
      expect(t1.first['description_id'], t2.first['description_id']);
    });

    test('multiple transactions with same description share description_id',
        () async {
      await addTransaction(
        date: '2025-01-01',
        description: 'Coffee',
        amount: 5.0,
        transactionType: 'expense',
        accountId: accountIds[0],
      );
      await addTransaction(
        date: '2025-01-02',
        description: 'Coffee',
        amount: 4.5,
        transactionType: 'expense',
        accountId: accountIds[0],
      );

      final descs = await db.query(
        'descriptions',
        where: 'user_id = ? AND name = ?',
        whereArgs: [userId, 'Coffee'],
      );
      expect(descs.length, 1);

      final txns = await db.query('transactions',
          where: 'description_id = ?', whereArgs: [descs.first['id']]);
      expect(txns.length, 2);
    });
  });

  group('Updating transactions', () {
    late int txnId;

    setUp(() async {
      txnId = await addTransaction(
        date: '2025-01-15',
        description: 'Salary',
        amount: 3000.0,
        transactionType: 'income',
        accountId: accountIds[0],
        notes: 'January salary',
      );
    });

    test('updates date', () async {
      final result = await updateTransaction(txnId, date: '2025-02-01');
      expect(result, true);

      final rows = await db.query('transactions', where: 'id = ?', whereArgs: [txnId]);
      expect(rows.first['date'], '2025-02-01');
    });

    test('updates amount', () async {
      final result = await updateTransaction(txnId, amount: 3500.0);
      expect(result, true);

      final rows = await db.query('transactions', where: 'id = ?', whereArgs: [txnId]);
      expect(rows.first['amount'], 3500.0);
    });

    test('updates transaction type', () async {
      final result = await updateTransaction(txnId, transactionType: 'expense');
      expect(result, true);

      final rows = await db.query('transactions', where: 'id = ?', whereArgs: [txnId]);
      expect(rows.first['transaction_type'], 'expense');
    });

    test('updates description', () async {
      final result = await updateTransaction(txnId, description: 'Bonus');
      expect(result, true);

      final rows = await db.query('transactions', where: 'id = ?', whereArgs: [txnId]);
      final descId = rows.first['description_id'] as int;
      final desc = await db.query('descriptions', where: 'id = ?', whereArgs: [descId]);
      expect(desc.first['name'], 'Bonus');
    });

    test('updates notes', () async {
      final result = await updateTransaction(txnId, notes: 'Updated note');
      expect(result, true);

      final rows = await db.query('transactions', where: 'id = ?', whereArgs: [txnId]);
      expect(rows.first['notes'], 'Updated note');
    });

    test('updates account', () async {
      final result = await updateTransaction(txnId, accountId: accountIds[1]);
      expect(result, true);

      final rows = await db.query('transactions', where: 'id = ?', whereArgs: [txnId]);
      expect(rows.first['account_id'], accountIds[1]);
    });

    test('updates currency', () async {
      final result = await updateTransaction(txnId, currency: 'USD');
      expect(result, true);

      final rows = await db.query('transactions', where: 'id = ?', whereArgs: [txnId]);
      expect(rows.first['currency'], 'USD');
    });

    test('partial update with multiple fields', () async {
      final result = await updateTransaction(
        txnId,
        date: '2025-06-15',
        amount: 4000.0,
        notes: 'June bonus',
      );
      expect(result, true);

      final rows = await db.query('transactions', where: 'id = ?', whereArgs: [txnId]);
      expect(rows.first['date'], '2025-06-15');
      expect(rows.first['amount'], 4000.0);
      expect(rows.first['notes'], 'June bonus');
      expect(rows.first['transaction_type'], 'income');
      expect(rows.first['account_id'], accountIds[0]);
    });

    test('returns false when no fields provided', () async {
      final result = await updateTransaction(txnId);
      expect(result, false);
    });

    test('returns false for non-existent transaction', () async {
      final result = await updateTransaction(9999, amount: 100.0);
      expect(result, false);
    });

    test('updates description and creates new description record', () async {
      await updateTransaction(txnId, description: 'New Description');

      final rows = await db.query('transactions', where: 'id = ?', whereArgs: [txnId]);
      final descId = rows.first['description_id'] as int;
      final desc = await db.query('descriptions', where: 'id = ?', whereArgs: [descId]);
      expect(desc.first['name'], 'New Description');
    });

    test('sets updated_at timestamp on update', () async {
      final before = await db.query('transactions', where: 'id = ?', whereArgs: [txnId]);
      final oldUpdated = before.first['updated_at'] as String?;

      await Future.delayed(const Duration(milliseconds: 10));
      await updateTransaction(txnId, amount: 100.0);

      final after = await db.query('transactions', where: 'id = ?', whereArgs: [txnId]);
      final newUpdated = after.first['updated_at'] as String?;

      expect(newUpdated, isNotNull);
      if (oldUpdated != null) {
        expect(newUpdated != oldUpdated, true);
      }
    });
  });

  group('Deleting transactions', () {
    test('deletes an existing transaction', () async {
      final id = await addTransaction(
        date: '2025-01-15',
        description: 'To Delete',
        amount: 50.0,
        transactionType: 'expense',
      );

      final result = await deleteTransaction(id);
      expect(result, true);

      final rows = await db.query('transactions', where: 'id = ?', whereArgs: [id]);
      expect(rows.isEmpty, true);
    });

    test('returns false for non-existent transaction', () async {
      final result = await deleteTransaction(9999);
      expect(result, false);
    });

    test('does not affect other users transactions', () async {
      final otherUserId = await seedTestUser(db, username: 'otheruser');
      final otherId = await seedTestTransaction(
        db,
        otherUserId,
        date: '2025-01-15',
        amount: 100.0,
        transactionType: 'income',
      );

      final id = await addTransaction(
        date: '2025-01-15',
        description: 'My Transaction',
        amount: 100.0,
        transactionType: 'income',
      );

      await deleteTransaction(id);

      final otherRows =
          await db.query('transactions', where: 'id = ?', whereArgs: [otherId]);
      expect(otherRows.length, 1);
    });

    test('deletes multiple transactions independently', () async {
      final id1 = await addTransaction(
        date: '2025-01-01',
        description: 'T1',
        amount: 10.0,
        transactionType: 'expense',
      );
      final id2 = await addTransaction(
        date: '2025-01-02',
        description: 'T2',
        amount: 20.0,
        transactionType: 'expense',
      );

      await deleteTransaction(id1);

      final remaining = await db.query('transactions', orderBy: 'id');
      expect(remaining.length, 1);
      expect(remaining.first['id'], id2);
    });

    test('does not delete description record when transaction is deleted',
        () async {
      final id = await addTransaction(
        date: '2025-01-15',
        description: 'Keep Description',
        amount: 100.0,
        transactionType: 'income',
      );

      final txn = await db.query('transactions', where: 'id = ?', whereArgs: [id]);
      final descId = txn.first['description_id'] as int;

      await deleteTransaction(id);

      final desc =
          await db.query('descriptions', where: 'id = ?', whereArgs: [descId]);
      expect(desc.length, 1);
    });
  });

  group('Querying transactions with filters', () {
    setUp(() async {
      await addTransaction(
        date: '2025-01-10',
        description: 'Groceries',
        amount: 50.0,
        transactionType: 'expense',
        accountId: accountIds[0],
      );
      await addTransaction(
        date: '2025-01-15',
        description: 'Salary',
        amount: 3000.0,
        transactionType: 'income',
        accountId: accountIds[0],
      );
      await addTransaction(
        date: '2025-01-20',
        description: 'Groceries',
        amount: 30.0,
        transactionType: 'expense',
        accountId: accountIds[1],
      );
      await addTransaction(
        date: '2025-01-25',
        description: 'Transfer to Checking',
        amount: 200.0,
        transactionType: 'transfer',
        accountId: accountIds[2],
      );
    });

    test('returns all transactions without filters', () async {
      final results = await getTransactions();
      expect(results.length, 4);
    });

    test('searches by description name (case-insensitive)', () async {
      final results = await getTransactions(searchQuery: 'groceries');
      expect(results.length, 2);
      for (final r in results) {
        expect(
          (r['description_name'] as String).toLowerCase(),
          contains('groceries'),
        );
      }
    });

    test('searches by account name (case-insensitive)', () async {
      final results = await getTransactions(searchQuery: 'savings');
      expect(results.length, 2);
    });

    test('filters by single account ID', () async {
      final results = await getTransactions(accountIds: {accountIds[0]});
      expect(results.length, 2);
      for (final r in results) {
        expect(r['account_id'], accountIds[0]);
      }
    });

    test('filters by multiple account IDs', () async {
      final results =
          await getTransactions(accountIds: {accountIds[0], accountIds[1]});
      expect(results.length, 3);
    });

    test('applies limit', () async {
      final results = await getTransactions(limit: 2);
      expect(results.length, 2);
    });

    test('applies offset', () async {
      final all = await getTransactions();
      final offsetResults = await getTransactions(offset: 2, limit: 2);
      expect(offsetResults.length, 2);
      expect(offsetResults.first['id'], all[2]['id']);
    });

    test('search combined with account filter', () async {
      final results = await getTransactions(
        searchQuery: 'groceries',
        accountIds: {accountIds[0]},
      );
      expect(results.length, 1);
      expect(results.first['description_name'], 'Groceries');
      expect(results.first['account_id'], accountIds[0]);
    });

    test('returns empty list for non-matching search', () async {
      final results = await getTransactions(searchQuery: 'nonexistent');
      expect(results.isEmpty, true);
    });

    test('returns empty list for non-matching account IDs', () async {
      final results = await getTransactions(accountIds: {9999});
      expect(results.isEmpty, true);
    });

    test('includes joined account and description details', () async {
      final results = await getTransactions();
      final groceries =
          results.firstWhere((r) => r['description_name'] == 'Groceries');
      expect(groceries['account_name'], isNotNull);
      expect(groceries['account_color'], isNotNull);
      expect(groceries['account_currency'], isNotNull);
      expect(groceries['description_name'], 'Groceries');
    });

    test('results ordered by date descending, then id descending', () async {
      final results = await getTransactions();
      for (var i = 0; i < results.length - 1; i++) {
        final dateA = results[i]['date'] as String;
        final dateB = results[i + 1]['date'] as String;
        expect(dateA.compareTo(dateB) >= 0, true);
      }
    });

    test('returns transaction with null account details', () async {
      await addTransaction(
        date: '2025-02-01',
        description: 'No Account',
        amount: 10.0,
        transactionType: 'income',
      );

      final results = await getTransactions();
      final noAccount = results.firstWhere((r) => r['account_id'] == null);
      expect(noAccount['account_name'], isNull);
      expect(noAccount['account_color'], isNull);
    });
  });

  group('Period-based queries', () {
    setUp(() async {
      await addTransaction(
        date: '2025-01-05',
        description: 'Jan Income',
        amount: 100.0,
        transactionType: 'income',
      );
      await addTransaction(
        date: '2025-01-15',
        description: 'Jan Expense',
        amount: 200.0,
        transactionType: 'expense',
      );
      await addTransaction(
        date: '2025-02-10',
        description: 'Feb Income',
        amount: 300.0,
        transactionType: 'income',
      );
      await addTransaction(
        date: '2025-03-01',
        description: 'Mar Expense',
        amount: 50.0,
        transactionType: 'expense',
      );
    });

    test('returns transactions within date range (inclusive)', () async {
      final results =
          await getTransactionsByPeriod('2025-01-01', '2025-01-31');
      expect(results.length, 2);
    });

    test('returns transactions in February', () async {
      final results =
          await getTransactionsByPeriod('2025-02-01', '2025-02-28');
      expect(results.length, 1);
      expect(results.first['date'], '2025-02-10');
    });

    test('returns empty for range with no transactions', () async {
      final results =
          await getTransactionsByPeriod('2024-12-01', '2024-12-31');
      expect(results.isEmpty, true);
    });

    test('single-day range', () async {
      final results =
          await getTransactionsByPeriod('2025-01-15', '2025-01-15');
      expect(results.length, 1);
      expect(results.first['date'], '2025-01-15');
    });

    test('wide range captures all transactions', () async {
      final results =
          await getTransactionsByPeriod('2020-01-01', '2030-12-31');
      expect(results.length, 4);
    });

    test('results ordered by date descending', () async {
      final results =
          await getTransactionsByPeriod('2025-01-01', '2025-03-31');
      expect(results.length, 4);
      for (var i = 0; i < results.length - 1; i++) {
        final dateA = results[i]['date'] as String;
        final dateB = results[i + 1]['date'] as String;
        expect(dateA.compareTo(dateB) >= 0, true);
      }
    });

    test('does not return transactions from other users', () async {
      final otherUserId = await seedTestUser(db, username: 'otheruser');
      await seedTestTransaction(
        db,
        otherUserId,
        date: '2025-01-10',
        amount: 999.0,
        transactionType: 'income',
      );

      final results =
          await getTransactionsByPeriod('2025-01-01', '2025-01-31');
      expect(results.length, 2);
      for (final r in results) {
        expect(r['user_id'], userId);
      }
    });
  });

  group('Earliest transaction date', () {
    test('returns null when no transactions exist', () async {
      final result = await getEarliestTransactionDate();
      expect(result, isNull);
    });

    test('returns earliest date among transactions', () async {
      await addTransaction(
        date: '2025-06-01',
        description: 'D1',
        amount: 10.0,
        transactionType: 'income',
      );
      await addTransaction(
        date: '2025-01-15',
        description: 'D2',
        amount: 20.0,
        transactionType: 'expense',
      );
      await addTransaction(
        date: '2025-03-20',
        description: 'D3',
        amount: 30.0,
        transactionType: 'income',
      );

      final result = await getEarliestTransactionDate();
      expect(result, '2025-01-15');
    });

    test('returns single date when only one transaction exists', () async {
      await addTransaction(
        date: '2025-08-20',
        description: 'D1',
        amount: 50.0,
        transactionType: 'income',
      );

      final result = await getEarliestTransactionDate();
      expect(result, '2025-08-20');
    });

    test('only considers current user transactions', () async {
      final otherUserId = await seedTestUser(db, username: 'otheruser');
      await seedTestTransaction(
        db,
        otherUserId,
        date: '2020-01-01',
        amount: 10.0,
        transactionType: 'income',
      );
      await addTransaction(
        date: '2025-06-01',
        description: 'D1',
        amount: 20.0,
        transactionType: 'income',
      );

      final result = await getEarliestTransactionDate();
      expect(result, '2025-06-01');
    });
  });

  group('Currency resolution from accounts', () {
    test('returns EUR for checking account', () async {
      final result = await getAccountCurrency(accountIds[0]);
      expect(result, 'EUR');
    });

    test('returns EUR for savings account A', () async {
      final result = await getAccountCurrency(accountIds[1]);
      expect(result, 'EUR');
    });

    test('returns EUR for savings account B', () async {
      final result = await getAccountCurrency(accountIds[2]);
      expect(result, 'EUR');
    });

    test('returns null for non-existent account', () async {
      final result = await getAccountCurrency(9999);
      expect(result, isNull);
    });

    test('transaction inherits account currency when account provided',
        () async {
      await db.update(
        'accounts',
        {'currency': 'USD'},
        where: 'id = ?',
        whereArgs: [accountIds[0]],
      );

      final id = await addTransaction(
        date: '2025-01-15',
        description: 'USD Transaction',
        amount: 100.0,
        transactionType: 'income',
        accountId: accountIds[0],
      );

      final rows =
          await db.query('transactions', where: 'id = ?', whereArgs: [id]);
      expect(rows.first['currency'], 'USD');
    });

    test('transaction uses default EUR when no account provided', () async {
      final id = await addTransaction(
        date: '2025-01-15',
        description: 'No Account Transaction',
        amount: 100.0,
        transactionType: 'income',
      );

      final rows =
          await db.query('transactions', where: 'id = ?', whereArgs: [id]);
      expect(rows.first['currency'], 'EUR');
    });

    test('transaction uses explicit currency when no account provided',
        () async {
      final id = await addTransaction(
        date: '2025-01-15',
        description: 'Explicit Currency',
        amount: 100.0,
        transactionType: 'income',
        currency: 'GBP',
      );

      final rows =
          await db.query('transactions', where: 'id = ?', whereArgs: [id]);
      expect(rows.first['currency'], 'GBP');
    });

    test('account currency takes precedence over explicit currency', () async {
      await db.update(
        'accounts',
        {'currency': 'CHF'},
        where: 'id = ?',
        whereArgs: [accountIds[0]],
      );

      final id = await addTransaction(
        date: '2025-01-15',
        description: 'Currency Test',
        amount: 100.0,
        transactionType: 'income',
        accountId: accountIds[0],
        currency: 'GBP',
      );

      final rows =
          await db.query('transactions', where: 'id = ?', whereArgs: [id]);
      expect(rows.first['currency'], 'CHF');
    });
  });

  group('Edge cases', () {
    test('transaction with zero amount', () async {
      final id = await addTransaction(
        date: '2025-01-15',
        description: 'Zero Amount',
        amount: 0.0,
        transactionType: 'income',
      );

      final rows =
          await db.query('transactions', where: 'id = ?', whereArgs: [id]);
      expect(rows.first['amount'], 0.0);
    });

    test('transaction with very large amount', () async {
      final id = await addTransaction(
        date: '2025-01-15',
        description: 'Large Amount',
        amount: 999999999.99,
        transactionType: 'income',
      );

      final rows =
          await db.query('transactions', where: 'id = ?', whereArgs: [id]);
      expect(rows.first['amount'], closeTo(999999999.99, 0.01));
    });

    test('transaction with very small decimal amount', () async {
      final id = await addTransaction(
        date: '2025-01-15',
        description: 'Small Amount',
        amount: 0.01,
        transactionType: 'expense',
      );

      final rows =
          await db.query('transactions', where: 'id = ?', whereArgs: [id]);
      expect(rows.first['amount'], 0.01);
    });

    test('transaction with negative amount (allowed by schema)', () async {
      final id = await addTransaction(
        date: '2025-01-15',
        description: 'Negative Amount',
        amount: -50.0,
        transactionType: 'income',
      );

      final rows =
          await db.query('transactions', where: 'id = ?', whereArgs: [id]);
      expect(rows.first['amount'], -50.0);
    });

    test('transaction with empty description name', () async {
      final id = await addTransaction(
        date: '2025-01-15',
        description: '',
        amount: 10.0,
        transactionType: 'income',
      );

      final rows =
          await db.query('transactions', where: 'id = ?', whereArgs: [id]);
      final descId = rows.first['description_id'] as int;
      final desc =
          await db.query('descriptions', where: 'id = ?', whereArgs: [descId]);
      expect(desc.first['name'], '');
    });

    test('transaction with null notes', () async {
      final id = await addTransaction(
        date: '2025-01-15',
        description: 'No Notes',
        amount: 10.0,
        transactionType: 'income',
      );

      final rows =
          await db.query('transactions', where: 'id = ?', whereArgs: [id]);
      expect(rows.first['notes'], isNull);
    });

    test('transaction with special characters in notes', () async {
      final id = await addTransaction(
        date: '2025-01-15',
        description: 'Special Notes',
        amount: 10.0,
        transactionType: 'income',
        notes: 'Line1\nLine2\tTab "Quotes" \'Single\' <HTML>',
      );

      final rows =
          await db.query('transactions', where: 'id = ?', whereArgs: [id]);
      expect(rows.first['notes'], 'Line1\nLine2\tTab "Quotes" \'Single\' <HTML>');
    });

    test('transaction with unicode description', () async {
      final id = await addTransaction(
        date: '2025-01-15',
        description: 'Café Ñoño 日本語',
        amount: 10.0,
        transactionType: 'income',
      );

      final rows =
          await db.query('transactions', where: 'id = ?', whereArgs: [id]);
      final descId = rows.first['description_id'] as int;
      final desc =
          await db.query('descriptions', where: 'id = ?', whereArgs: [descId]);
      expect(desc.first['name'], 'Café Ñoño 日本語');
    });

    test('updating notes to empty string', () async {
      final id = await addTransaction(
        date: '2025-01-15',
        description: 'Notes Test',
        amount: 10.0,
        transactionType: 'income',
        notes: 'Has notes',
      );

      final result = await updateTransaction(id, notes: '');
      expect(result, true);

      final rows =
          await db.query('transactions', where: 'id = ?', whereArgs: [id]);
      expect(rows.first['notes'], '');
    });

    test('many transactions with same description do not create duplicate descriptions',
        () async {
      for (var i = 0; i < 10; i++) {
        await addTransaction(
          date: '2025-01-${(i + 1).toString().padLeft(2, '0')}',
          description: 'Recurring Expense',
          amount: (i + 1) * 10.0,
          transactionType: 'expense',
        );
      }

      final descs = await db.query(
        'descriptions',
        where: 'user_id = ? AND name = ?',
        whereArgs: [userId, 'Recurring Expense'],
      );
      expect(descs.length, 1);

      final allTxns = await db.query('transactions');
      expect(allTxns.length, 10);
    });

    test('description with different case creates separate records', () async {
      await addTransaction(
        date: '2025-01-15',
        description: 'Groceries',
        amount: 10.0,
        transactionType: 'expense',
      );
      await addTransaction(
        date: '2025-01-16',
        description: 'groceries',
        amount: 20.0,
        transactionType: 'expense',
      );

      final descs = await db.query(
        'descriptions',
        where: 'user_id = ? AND (name = ? OR name = ?)',
        whereArgs: [userId, 'Groceries', 'groceries'],
      );
      expect(descs.length, 2);
    });

    test('deleting transaction does not affect account', () async {
      final id = await addTransaction(
        date: '2025-01-15',
        description: 'Delete Me',
        amount: 100.0,
        transactionType: 'income',
        accountId: accountIds[0],
      );

      await deleteTransaction(id);

      final acct = await db
          .query('accounts', where: 'id = ?', whereArgs: [accountIds[0]]);
      expect(acct.length, 1);
    });

    test('deleting transaction does not affect other descriptions', () async {
      final descId = await getOrCreateDescription('Shared Desc');
      final id1 = await addTransaction(
        date: '2025-01-15',
        description: 'Shared Desc',
        amount: 100.0,
        transactionType: 'income',
      );
      final id2 = await addTransaction(
        date: '2025-01-20',
        description: 'Shared Desc',
        amount: 200.0,
        transactionType: 'income',
      );

      await deleteTransaction(id1);

      final remaining = await db.query('transactions',
          where: 'description_id = ?', whereArgs: [descId]);
      expect(remaining.length, 1);
      expect(remaining.first['id'], id2);
    });

    test('different users can have descriptions with same name', () async {
      final otherUserId = await seedTestUser(db, username: 'user2');
      await addTransaction(
        date: '2025-01-15',
        description: 'Shared Name',
        amount: 10.0,
        transactionType: 'income',
      );
      final otherDescId = await db.insert('descriptions', {
        'user_id': otherUserId,
        'name': 'Shared Name',
      });
      await seedTestTransaction(
        db,
        otherUserId,
        descriptionId: otherDescId,
        date: '2025-01-15',
        amount: 20.0,
        transactionType: 'income',
      );

      final userDescs = await db.query(
        'descriptions',
        where: 'user_id = ? AND name = ?',
        whereArgs: [userId, 'Shared Name'],
      );
      final otherDescs = await db.query(
        'descriptions',
        where: 'user_id = ? AND name = ?',
        whereArgs: [otherUserId, 'Shared Name'],
      );
      expect(userDescs.length, 1);
      expect(otherDescs.length, 1);
      expect(userDescs.first['id'] != otherDescs.first['id'], true);
    });

    test('multiple transactions across dates with mixed types', () async {
      await addTransaction(
        date: '2025-01-01',
        description: 'Income',
        amount: 5000.0,
        transactionType: 'income',
      );
      await addTransaction(
        date: '2025-01-05',
        description: 'Expense',
        amount: 200.0,
        transactionType: 'expense',
      );
      await addTransaction(
        date: '2025-01-10',
        description: 'Transfer',
        amount: 1000.0,
        transactionType: 'transfer',
      );
      await addTransaction(
        date: '2025-01-15',
        description: 'Income',
        amount: 500.0,
        transactionType: 'income',
      );

      final incomeTxns = await db.query(
        'transactions',
        where: 'user_id = ? AND transaction_type = ?',
        whereArgs: [userId, 'income'],
      );
      expect(incomeTxns.length, 2);

      final expenseTxns = await db.query(
        'transactions',
        where: 'user_id = ? AND transaction_type = ?',
        whereArgs: [userId, 'expense'],
      );
      expect(expenseTxns.length, 1);

      final transferTxns = await db.query(
        'transactions',
        where: 'user_id = ? AND transaction_type = ?',
        whereArgs: [userId, 'transfer'],
      );
      expect(transferTxns.length, 1);
    });

    test('update on description field creates description if needed', () async {
      final id = await addTransaction(
        date: '2025-01-15',
        description: 'Old Desc',
        amount: 100.0,
        transactionType: 'income',
      );

      await updateTransaction(id, description: 'Brand New Desc');

      final rows =
          await db.query('transactions', where: 'id = ?', whereArgs: [id]);
      final descId = rows.first['description_id'] as int;
      final desc =
          await db.query('descriptions', where: 'id = ?', whereArgs: [descId]);
      expect(desc.first['name'], 'Brand New Desc');
    });

    test('getTransactions returns correct joined data for transfer', () async {
      final id = await addTransaction(
        date: '2025-01-15',
        description: 'Transfer to Savings',
        amount: 500.0,
        transactionType: 'transfer',
        accountId: accountIds[1],
        notes: 'Monthly savings',
      );

      final results = await getTransactions();
      final transfer = results.firstWhere((r) => r['id'] == id);
      expect(transfer['account_name'], 'Savings Account A');
      expect(transfer['account_color'], '#2196F3');
      expect(transfer['description_name'], 'Transfer to Savings');
      expect(transfer['notes'], 'Monthly savings');
    });

    test('period query returns empty for swapped dates', () async {
      await addTransaction(
        date: '2025-01-15',
        description: 'Test',
        amount: 100.0,
        transactionType: 'income',
      );

      final results =
          await getTransactionsByPeriod('2025-01-31', '2025-01-01');
      expect(results.isEmpty, true);
    });

    test('getTransactions with empty account IDs set behaves as no filter',
        () async {
      await addTransaction(
        date: '2025-01-15',
        description: 'Test',
        amount: 100.0,
        transactionType: 'income',
      );

      final withEmpty = await getTransactions(accountIds: {});
      final without = await getTransactions();
      expect(withEmpty.length, without.length);
    });
  });
}
