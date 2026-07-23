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

  setUpAll(() {
    initializeTestDatabase();
  });

  setUp(() async {
    db = await _openTestDb();
    userId = await seedTestUser(db);
  });

  tearDown(() async {
    await db.close();
  });

  group('Account CRUD with starting_amount', () {
    test('insert account with starting_amount stores it', () async {
      final id = await db.insert('accounts', {
        'user_id': userId,
        'name': 'My Account',
        'type': 'checking',
        'currency': 'EUR',
        'starting_amount': 5000.0,
      });

      final rows = await db.query('accounts', where: 'id = ?', whereArgs: [id]);
      expect(rows.first['starting_amount'], 5000.0);
    });

    test('insert account without starting_amount defaults to 0', () async {
      final id = await db.insert('accounts', {
        'user_id': userId,
        'name': 'Default Account',
        'type': 'savings',
        'currency': 'EUR',
      });

      final rows = await db.query('accounts', where: 'id = ?', whereArgs: [id]);
      expect(rows.first['starting_amount'], 0.0);
    });

    test('update account starting_amount', () async {
      final id = await db.insert('accounts', {
        'user_id': userId,
        'name': 'Update Test',
        'type': 'checking',
        'currency': 'EUR',
        'starting_amount': 1000.0,
      });

      await db.update('accounts', {'starting_amount': 2500.0},
          where: 'id = ?', whereArgs: [id]);

      final rows = await db.query('accounts', where: 'id = ?', whereArgs: [id]);
      expect(rows.first['starting_amount'], 2500.0);
    });

    test('negative starting_amount is stored correctly', () async {
      final id = await db.insert('accounts', {
        'user_id': userId,
        'name': 'Overdrawn',
        'type': 'checking',
        'currency': 'EUR',
        'starting_amount': -500.0,
      });

      final rows = await db.query('accounts', where: 'id = ?', whereArgs: [id]);
      expect(rows.first['starting_amount'], -500.0);
    });
  });

  group('getAccountsWithBalances includes starting_amount', () {
    test('balance = starting_amount when no transactions', () async {
      final accountIds = await seedTestAccounts(db, userId, startingAmounts: [1000.0, 2000.0, 3000.0]);

      final rows = await db.rawQuery('''
        SELECT a.*,
               a.starting_amount + COALESCE(SUM(CASE WHEN t.transaction_type = 'income' THEN t.amount
                                  WHEN t.transaction_type = 'expense' THEN -t.amount
                                  ELSE 0 END), 0) AS balance
        FROM accounts a
        LEFT JOIN transactions t ON t.account_id = a.id AND t.user_id = ?
        WHERE a.user_id = ?
        GROUP BY a.id
        ORDER BY a.name
      ''', [userId, userId]);

      final checking = rows.firstWhere((r) => r['name'] == 'Checking Account');
      final savingsA = rows.firstWhere((r) => r['name'] == 'Savings Account A');
      final savingsB = rows.firstWhere((r) => r['name'] == 'Savings Account B');

      expect(checking['balance'], 1000.0);
      expect(savingsA['balance'], 2000.0);
      expect(savingsB['balance'], 3000.0);
    });

    test('balance = starting_amount + transactions', () async {
      final accountIds = await seedTestAccounts(db, userId, startingAmounts: [1000.0, 0.0, 0.0]);

      await seedTestTransaction(db, userId, accountId: accountIds[0], amount: 500.0, transactionType: 'income');
      await seedTestTransaction(db, userId, accountId: accountIds[0], amount: 200.0, transactionType: 'expense');

      final rows = await db.rawQuery('''
        SELECT a.*,
               a.starting_amount + COALESCE(SUM(CASE WHEN t.transaction_type = 'income' THEN t.amount
                                  WHEN t.transaction_type = 'expense' THEN -t.amount
                                  ELSE 0 END), 0) AS balance
        FROM accounts a
        LEFT JOIN transactions t ON t.account_id = a.id AND t.user_id = ?
        WHERE a.user_id = ?
        GROUP BY a.id
        ORDER BY a.name
      ''', [userId, userId]);

      final checking = rows.firstWhere((r) => r['name'] == 'Checking Account');
      expect(checking['balance'], 1300.0); // 1000 + 500 - 200
    });

    test('zero starting_amount with transactions', () async {
      final accountIds = await seedTestAccounts(db, userId);

      await seedTestTransaction(db, userId, accountId: accountIds[0], amount: 300.0, transactionType: 'income');

      final rows = await db.rawQuery('''
        SELECT a.*,
               a.starting_amount + COALESCE(SUM(CASE WHEN t.transaction_type = 'income' THEN t.amount
                                  WHEN t.transaction_type = 'expense' THEN -t.amount
                                  ELSE 0 END), 0) AS balance
        FROM accounts a
        LEFT JOIN transactions t ON t.account_id = a.id AND t.user_id = ?
        WHERE a.user_id = ?
        GROUP BY a.id
        ORDER BY a.name
      ''', [userId, userId]);

      final checking = rows.firstWhere((r) => r['name'] == 'Checking Account');
      expect(checking['balance'], 300.0);
    });
  });

  group('getAccountsDistribution includes starting_amount', () {
    test('distribution uses starting_amount in balance', () async {
      final accountIds = await seedTestAccounts(db, userId, startingAmounts: [500.0, 1500.0, 0.0]);

      await db.insert('exchange_rates', {
        'from_currency': 'EUR',
        'to_currency': 'EUR',
        'rate': 1.0,
      });

      final rows = await db.rawQuery('''
        SELECT a.name, a.color, a.currency as account_currency,
               a.starting_amount + COALESCE(SUM(CASE WHEN t.transaction_type = 'income' THEN t.amount
                                 WHEN t.transaction_type = 'expense' THEN -t.amount
                                 ELSE 0 END), 0) AS balance
        FROM accounts a
        LEFT JOIN transactions t ON t.account_id = a.id AND t.user_id = ?
        WHERE a.user_id = ?
        GROUP BY a.id
        ORDER BY a.name
      ''', [userId, userId]);

      final checking = rows.firstWhere((r) => r['name'] == 'Checking Account');
      final savingsA = rows.firstWhere((r) => r['name'] == 'Savings Account A');

      expect(checking['balance'], 500.0);
      expect(savingsA['balance'], 1500.0);
    });
  });

  group('getBalance includes starting_amount from checking accounts', () {
    test('balance sums starting_amounts of checking accounts', () async {
      final accountIds = await seedTestAccounts(db, userId, startingAmounts: [1000.0, 2000.0, 3000.0]);

      final acctRows = await db.rawQuery('''
        SELECT COALESCE(a.starting_amount, 0) as starting_amount,
               COALESCE(NULLIF(a.currency, ''), 'EUR') as currency
        FROM accounts a
        WHERE a.type = 'checking' AND a.user_id = ?
      ''', [userId]);

      double total = 0.0;
      for (final row in acctRows) {
        total += (row['starting_amount'] as num?)?.toDouble() ?? 0.0;
      }

      expect(total, 1000.0); // Only checking account
    });

    test('balance = starting_amount + transactions for checking', () async {
      final accountIds = await seedTestAccounts(db, userId, startingAmounts: [1000.0, 2000.0, 3000.0]);

      await seedTestTransaction(db, userId, accountId: accountIds[0], amount: 500.0, transactionType: 'income');
      await seedTestTransaction(db, userId, accountId: accountIds[1], amount: 800.0, transactionType: 'income');

      final acctRows = await db.rawQuery('''
        SELECT COALESCE(a.starting_amount, 0) as starting_amount,
               COALESCE(NULLIF(a.currency, ''), 'EUR') as currency
        FROM accounts a
        WHERE a.type = 'checking' AND a.user_id = ?
      ''', [userId]);

      double total = 0.0;
      for (final row in acctRows) {
        total += (row['starting_amount'] as num?)?.toDouble() ?? 0.0;
      }

      final txnRows = await db.rawQuery('''
        SELECT COALESCE(SUM(CASE WHEN t.transaction_type = 'income' THEN t.amount
                                 WHEN t.transaction_type = 'expense' THEN -t.amount
                                 ELSE 0 END), 0) as total,
               COALESCE(NULLIF(a.currency, ''), 'EUR') as currency
        FROM transactions t
        LEFT JOIN accounts a ON t.account_id = a.id
        WHERE (a.type = 'checking' OR t.account_id IS NULL) AND t.user_id = ?
        GROUP BY a.currency
      ''', [userId]);

      for (final row in txnRows) {
        total += (row['total'] as num?)?.toDouble() ?? 0.0;
      }

      expect(total, 1500.0); // 1000 starting + 500 income
    });
  });

  group('getSavingsTotal includes starting_amount from savings accounts', () {
    test('savings total sums starting_amounts of savings accounts', () async {
      final accountIds = await seedTestAccounts(db, userId, startingAmounts: [1000.0, 2000.0, 3000.0]);

      final acctRows = await db.rawQuery('''
        SELECT COALESCE(a.starting_amount, 0) as starting_amount,
               COALESCE(NULLIF(a.currency, ''), 'EUR') as currency
        FROM accounts a
        WHERE a.type = 'savings' AND a.user_id = ?
      ''', [userId]);

      double total = 0.0;
      for (final row in acctRows) {
        total += (row['starting_amount'] as num?)?.toDouble() ?? 0.0;
      }

      expect(total, 5000.0); // 2000 + 3000
    });

    test('savings total = starting_amounts + transactions', () async {
      final accountIds = await seedTestAccounts(db, userId, startingAmounts: [1000.0, 2000.0, 3000.0]);

      await seedTestTransaction(db, userId, accountId: accountIds[1], amount: 400.0, transactionType: 'income');
      await seedTestTransaction(db, userId, accountId: accountIds[2], amount: 100.0, transactionType: 'expense');

      final acctRows = await db.rawQuery('''
        SELECT COALESCE(a.starting_amount, 0) as starting_amount,
               COALESCE(NULLIF(a.currency, ''), 'EUR') as currency
        FROM accounts a
        WHERE a.type = 'savings' AND a.user_id = ?
      ''', [userId]);

      double total = 0.0;
      for (final row in acctRows) {
        total += (row['starting_amount'] as num?)?.toDouble() ?? 0.0;
      }

      final txnRows = await db.rawQuery('''
        SELECT COALESCE(SUM(CASE WHEN t.transaction_type = 'income' THEN t.amount
                                 WHEN t.transaction_type = 'expense' THEN -t.amount
                                 ELSE 0 END), 0) as total,
               COALESCE(NULLIF(a.currency, ''), 'EUR') as currency
        FROM transactions t
        LEFT JOIN accounts a ON t.account_id = a.id
        WHERE a.type = 'savings' AND t.user_id = ?
        GROUP BY a.currency
      ''', [userId]);

      for (final row in txnRows) {
        total += (row['total'] as num?)?.toDouble() ?? 0.0;
      }

      expect(total, 5300.0); // 2000 + 3000 + 400 - 100
    });
  });

  group('getTotalPatrimony includes starting_amount', () {
    test('patrimony sums all starting_amounts + transactions', () async {
      final accountIds = await seedTestAccounts(db, userId, startingAmounts: [1000.0, 2000.0, 3000.0]);

      await seedTestTransaction(db, userId, accountId: accountIds[0], amount: 500.0, transactionType: 'income');
      await seedTestTransaction(db, userId, accountId: accountIds[1], amount: 300.0, transactionType: 'expense');

      final acctRows = await db.rawQuery('''
        SELECT COALESCE(a.starting_amount, 0) as starting_amount,
               COALESCE(NULLIF(a.currency, ''), 'EUR') as currency
        FROM accounts a WHERE a.user_id = ?
      ''', [userId]);

      double total = 0.0;
      for (final row in acctRows) {
        final amount = (row['starting_amount'] as num?)?.toDouble() ?? 0.0;
        total += amount;
      }

      final txnRows = await db.rawQuery('''
        SELECT COALESCE(SUM(CASE WHEN t.transaction_type = 'income' THEN t.amount
                                 WHEN t.transaction_type = 'expense' THEN -t.amount
                                 ELSE 0 END), 0) as total,
               COALESCE(NULLIF(a.currency, ''), 'EUR') as currency
        FROM transactions t
        LEFT JOIN accounts a ON t.account_id = a.id
        WHERE t.user_id = ?
        GROUP BY a.currency
      ''', [userId]);

      for (final row in txnRows) {
        total += (row['total'] as num?)?.toDouble() ?? 0.0;
      }

      expect(total, 6200.0); // 6000 starting + 500 - 300
    });

    test('patrimony with zero starting_amounts', () async {
      final accountIds = await seedTestAccounts(db, userId);

      await seedTestTransaction(db, userId, accountId: accountIds[0], amount: 100.0, transactionType: 'income');

      final acctRows = await db.rawQuery('''
        SELECT COALESCE(a.starting_amount, 0) as starting_amount,
               COALESCE(NULLIF(a.currency, ''), 'EUR') as currency
        FROM accounts a WHERE a.user_id = ?
      ''', [userId]);

      double total = 0.0;
      for (final row in acctRows) {
        total += (row['starting_amount'] as num?)?.toDouble() ?? 0.0;
      }

      final txnRows = await db.rawQuery('''
        SELECT COALESCE(SUM(CASE WHEN t.transaction_type = 'income' THEN t.amount
                                 WHEN t.transaction_type = 'expense' THEN -t.amount
                                 ELSE 0 END), 0) as total,
               COALESCE(NULLIF(a.currency, ''), 'EUR') as currency
        FROM transactions t
        LEFT JOIN accounts a ON t.account_id = a.id
        WHERE t.user_id = ?
        GROUP BY a.currency
      ''', [userId]);

      for (final row in txnRows) {
        total += (row['total'] as num?)?.toDouble() ?? 0.0;
      }

      expect(total, 100.0);
    });
  });

  group('getAssetsHistory includes starting_amount', () {
    test('each month total starts from starting_total', () async {
      final accountIds = await seedTestAccounts(db, userId, startingAmounts: [1000.0, 500.0, 0.0]);

      await seedTestTransaction(db, userId, accountId: accountIds[0],
          date: '2025-01-10', amount: 200.0, transactionType: 'income');

      final acctRows = await db.rawQuery('''
        SELECT COALESCE(a.starting_amount, 0) as starting_amount,
               COALESCE(NULLIF(a.currency, ''), 'EUR') as currency
        FROM accounts a WHERE a.user_id = ?
      ''', [userId]);

      double startingTotal = 0.0;
      for (final row in acctRows) {
        startingTotal += (row['starting_amount'] as num?)?.toDouble() ?? 0.0;
      }

      final historyRows = await db.rawQuery('''
        SELECT COALESCE(SUM(CASE WHEN t.transaction_type = 'income' THEN t.amount
                                 WHEN t.transaction_type = 'expense' THEN -t.amount
                                 ELSE 0 END), 0) as total,
               COALESCE(NULLIF(a.currency, ''), 'EUR') as currency
        FROM transactions t
        LEFT JOIN accounts a ON t.account_id = a.id
        WHERE t.date < ? AND t.user_id = ?
        GROUP BY a.currency
      ''', ['2025-02-01', userId]);

      double totalValue = startingTotal;
      for (final row in historyRows) {
        totalValue += (row['total'] as num?)?.toDouble() ?? 0.0;
      }

      expect(startingTotal, 1500.0);
      expect(totalValue, 1700.0); // 1500 starting + 200 income
    });
  });

  group('getHistoryBalance and getHistorySavings include starting_amount', () {
    test('history balance includes checking starting_amount', () async {
      final accountIds = await seedTestAccounts(db, userId, startingAmounts: [1000.0, 2000.0, 3000.0]);

      final acctRows = await db.rawQuery('''
        SELECT COALESCE(a.starting_amount, 0) as starting_amount,
               COALESCE(NULLIF(a.currency, ''), 'EUR') as currency
        FROM accounts a
        WHERE a.type = 'checking' AND a.user_id = ?
      ''', [userId]);

      double total = 0.0;
      for (final row in acctRows) {
        total += (row['starting_amount'] as num?)?.toDouble() ?? 0.0;
      }

      expect(total, 1000.0); // Only checking
    });

    test('history savings includes savings starting_amounts', () async {
      final accountIds = await seedTestAccounts(db, userId, startingAmounts: [1000.0, 2000.0, 3000.0]);

      final acctRows = await db.rawQuery('''
        SELECT COALESCE(a.starting_amount, 0) as starting_amount,
               COALESCE(NULLIF(a.currency, ''), 'EUR') as currency
        FROM accounts a
        WHERE a.type = 'savings' AND a.user_id = ?
      ''', [userId]);

      double total = 0.0;
      for (final row in acctRows) {
        total += (row['starting_amount'] as num?)?.toDouble() ?? 0.0;
      }

      expect(total, 5000.0); // 2000 + 3000
    });

    test('history balance with transactions before date limit', () async {
      final accountIds = await seedTestAccounts(db, userId, startingAmounts: [1000.0, 0.0, 0.0]);

      await seedTestTransaction(db, userId, accountId: accountIds[0],
          date: '2024-12-15', amount: 300.0, transactionType: 'income');
      await seedTestTransaction(db, userId, accountId: accountIds[0],
          date: '2025-02-15', amount: 500.0, transactionType: 'income');

      final acctRows = await db.rawQuery('''
        SELECT COALESCE(a.starting_amount, 0) as starting_amount,
               COALESCE(NULLIF(a.currency, ''), 'EUR') as currency
        FROM accounts a
        WHERE a.type = 'checking' AND a.user_id = ?
      ''', [userId]);

      double total = 0.0;
      for (final row in acctRows) {
        total += (row['starting_amount'] as num?)?.toDouble() ?? 0.0;
      }

      final txnRows = await db.rawQuery('''
        SELECT COALESCE(SUM(CASE WHEN t.transaction_type = 'income' THEN t.amount
                                 WHEN t.transaction_type = 'expense' THEN -t.amount
                                 ELSE 0 END), 0) as total,
               COALESCE(NULLIF(a.currency, ''), 'EUR') as currency
        FROM transactions t
        LEFT JOIN accounts a ON t.account_id = a.id
        WHERE t.date < ? AND (a.type = 'checking' OR t.account_id IS NULL) AND t.user_id = ?
        GROUP BY a.currency
      ''', ['2025-01-01', userId]);

      for (final row in txnRows) {
        total += (row['total'] as num?)?.toDouble() ?? 0.0;
      }

      expect(total, 1300.0); // 1000 starting + 300 (Dec transaction only)
    });
  });

  group('Edge cases', () {
    test('all accounts with zero starting_amount', () async {
      final accountIds = await seedTestAccounts(db, userId, startingAmounts: [0.0, 0.0, 0.0]);

      await seedTestTransaction(db, userId, accountId: accountIds[0], amount: 100.0, transactionType: 'income');

      final rows = await db.rawQuery('''
        SELECT a.starting_amount + COALESCE(SUM(CASE WHEN t.transaction_type = 'income' THEN t.amount
                                WHEN t.transaction_type = 'expense' THEN -t.amount
                                ELSE 0 END), 0) AS balance
        FROM accounts a
        LEFT JOIN transactions t ON t.account_id = a.id AND t.user_id = ?
        WHERE a.user_id = ?
        GROUP BY a.id
      ''', [userId, userId]);

      final totalBalance = rows.fold<double>(0, (sum, r) => sum + ((r['balance'] as num?)?.toDouble() ?? 0.0));
      expect(totalBalance, 100.0);
    });

    test('negative starting_amount reduces balance', () async {
      final accountIds = await seedTestAccounts(db, userId, startingAmounts: [-500.0, 0.0, 0.0]);

      await seedTestTransaction(db, userId, accountId: accountIds[0], amount: 200.0, transactionType: 'income');

      final rows = await db.rawQuery('''
        SELECT a.starting_amount + COALESCE(SUM(CASE WHEN t.transaction_type = 'income' THEN t.amount
                                WHEN t.transaction_type = 'expense' THEN -t.amount
                                ELSE 0 END), 0) AS balance
        FROM accounts a
        LEFT JOIN transactions t ON t.account_id = a.id AND t.user_id = ?
        WHERE a.id = ?
        GROUP BY a.id
      ''', [userId, accountIds[0]]);

      expect(rows.first['balance'], -300.0); // -500 + 200
    });

    test('starting_amount does not affect monthly summary', () async {
      final accountIds = await seedTestAccounts(db, userId, startingAmounts: [5000.0, 0.0, 0.0]);

      await seedTestTransaction(db, userId, accountId: accountIds[0],
          date: '2025-01-15', amount: 300.0, transactionType: 'income');
      await seedTestTransaction(db, userId, accountId: accountIds[0],
          date: '2025-01-20', amount: 100.0, transactionType: 'expense');

      final rows = await db.rawQuery('''
        SELECT
          COALESCE(SUM(CASE WHEN t.transaction_type = 'income' THEN t.amount ELSE 0 END), 0) as income,
          COALESCE(SUM(CASE WHEN t.transaction_type = 'expense' THEN t.amount ELSE 0 END), 0) as expenses
        FROM transactions t
        LEFT JOIN accounts a ON t.account_id = a.id
        WHERE (t.date >= ? AND t.date < ?) AND (a.type = 'checking' OR t.account_id IS NULL) AND t.user_id = ?
      ''', ['2025-01-01', '2025-02-01', userId]);

      final income = (rows.first['income'] as num).toDouble();
      final expenses = (rows.first['expenses'] as num).toDouble();

      expect(income, 300.0); // Starting amount NOT included
      expect(expenses, 100.0);
    });

    test('starting_amount does not affect cash flow data', () async {
      final accountIds = await seedTestAccounts(db, userId, startingAmounts: [5000.0, 0.0, 0.0]);

      await seedTestTransaction(db, userId, accountId: accountIds[0],
          date: '2025-01-15', amount: 200.0, transactionType: 'income');

      final rows = await db.rawQuery('''
        SELECT strftime('%Y-%m', t.date) as month,
               t.transaction_type as type,
               SUM(t.amount) as amount
        FROM transactions t
        LEFT JOIN accounts a ON t.account_id = a.id
        LEFT JOIN descriptions d ON t.description_id = d.id
        WHERE t.date >= ? AND t.user_id = ?
          AND (d.name IS NULL OR LOWER(d.name) NOT LIKE 'transfer to %' AND LOWER(d.name) NOT LIKE 'transfer from %')
        GROUP BY month, t.transaction_type
        ORDER BY month
      ''', ['2025-01-01', userId]);

      expect(rows.length, 1);
      expect(rows.first['amount'], 200.0); // Starting amount NOT included
    });
  });

  group('Multi-currency with starting_amount', () {
    test('starting_amount is converted using exchange rates', () async {
      await db.insert('accounts', {
        'user_id': userId,
        'name': 'USD Account',
        'type': 'checking',
        'currency': 'USD',
        'starting_amount': 1000.0,
      });
      await db.insert('accounts', {
        'user_id': userId,
        'name': 'EUR Account',
        'type': 'checking',
        'currency': 'EUR',
        'starting_amount': 500.0,
      });

      await db.insert('exchange_rates', {'from_currency': 'USD', 'to_currency': 'EUR', 'rate': 0.92});
      await db.insert('exchange_rates', {'from_currency': 'EUR', 'to_currency': 'USD', 'rate': 1.087});

      final acctRows = await db.rawQuery('''
        SELECT COALESCE(a.starting_amount, 0) as starting_amount,
               COALESCE(NULLIF(a.currency, ''), 'EUR') as currency
        FROM accounts a WHERE a.user_id = ?
      ''', [userId]);

      double total = 0.0;
      for (final row in acctRows) {
        final amount = (row['starting_amount'] as num?)?.toDouble() ?? 0.0;
        final acctCurrency = (row['currency'] as String?) ?? 'EUR';
        if (acctCurrency == 'EUR') {
          total += amount;
        } else {
          final rateRow = await db.rawQuery(
            'SELECT rate FROM exchange_rates WHERE from_currency = ? AND to_currency = ?',
            [acctCurrency, 'EUR'],
          );
          final rate = (rateRow.first['rate'] as num?)?.toDouble() ?? 1.0;
          total += amount * rate;
        }
      }

      expect(total, closeTo(1420.0, 0.01)); // 1000*0.92 + 500 = 920 + 500
    });
  });
}
