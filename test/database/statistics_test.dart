import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../helpers/test_helper.dart';

void main() {
  late Database db;
  late int userId;
  late List<int> accountIds;

  setUpAll(() {
    initializeTestDatabase();
  });

  setUp(() async {
    db = await createTestDatabase();
    userId = await seedTestUser(db);
    accountIds = await seedTestAccounts(db, userId);
  });

  tearDown(() async {
    await db.close();
  });

  // accountIds[0] = checking, accountIds[1] = savingsA, accountIds[2] = savingsB

  // =========================================================================
  // getTotalPatrimony
  // =========================================================================
  group('getTotalPatrimony SQL', () {
    test('returns 0 when no transactions exist', () async {
      final result = await db.rawQuery('''
        SELECT COALESCE(SUM(CASE WHEN t.transaction_type = 'income' THEN t.amount
                                 WHEN t.transaction_type = 'expense' THEN -t.amount
                                 ELSE 0 END), 0) as total,
               COALESCE(NULLIF(t.currency, ''), 'EUR') as currency
        FROM transactions t WHERE t.user_id = ?
        GROUP BY currency
      ''', [userId]);

      final total = result.fold<double>(0.0, (sum, row) {
        return sum + ((row['total'] as num?)?.toDouble() ?? 0.0);
      });
      expect(total, 0.0);
    });

    test('calculates total across all accounts with same currency', () async {
      final descId = await seedTestDescription(db, userId, 'Salary');
      await seedTestTransaction(db, userId,
          accountId: accountIds[0], descriptionId: descId,
          date: '2025-06-01', amount: 3000, transactionType: 'income', currency: 'EUR');
      await seedTestTransaction(db, userId,
          accountId: accountIds[1], descriptionId: descId,
          date: '2025-06-05', amount: 500, transactionType: 'income', currency: 'EUR');
      await seedTestTransaction(db, userId,
          accountId: accountIds[0], descriptionId: descId,
          date: '2025-06-10', amount: 200, transactionType: 'expense', currency: 'EUR');

      final result = await db.rawQuery('''
        SELECT COALESCE(SUM(CASE WHEN t.transaction_type = 'income' THEN t.amount
                                 WHEN t.transaction_type = 'expense' THEN -t.amount
                                 ELSE 0 END), 0) as total,
               COALESCE(NULLIF(t.currency, ''), 'EUR') as currency
        FROM transactions t WHERE t.user_id = ?
        GROUP BY currency
      ''', [userId]);

      final total = result.fold<double>(0.0, (sum, row) {
        return sum + ((row['total'] as num?)?.toDouble() ?? 0.0);
      });
      expect(total, 3300.0);
    });

    test('groups by currency correctly', () async {
      final descId = await seedTestDescription(db, userId, 'Food');
      await seedTestTransaction(db, userId,
          accountId: accountIds[0], descriptionId: descId,
          date: '2025-06-01', amount: 1000, transactionType: 'income', currency: 'EUR');
      await seedTestTransaction(db, userId,
          accountId: accountIds[0], descriptionId: descId,
          date: '2025-06-02', amount: 500, transactionType: 'income', currency: 'USD');

      final result = await db.rawQuery('''
        SELECT COALESCE(SUM(CASE WHEN t.transaction_type = 'income' THEN t.amount
                                 WHEN t.transaction_type = 'expense' THEN -t.amount
                                 ELSE 0 END), 0) as total,
               COALESCE(NULLIF(t.currency, ''), 'EUR') as currency
        FROM transactions t WHERE t.user_id = ?
        GROUP BY currency
      ''', [userId]);

      expect(result.length, 2);
      final eurRow = result.firstWhere((r) => r['currency'] == 'EUR');
      final usdRow = result.firstWhere((r) => r['currency'] == 'USD');
      expect(eurRow['total'], 1000.0);
      expect(usdRow['total'], 500.0);
    });

    test('treats transfer as 0 in calculation', () async {
      final descId = await seedTestDescription(db, userId, 'Transfer');
      await seedTestTransaction(db, userId,
          accountId: accountIds[0], descriptionId: descId,
          date: '2025-06-01', amount: 500, transactionType: 'transfer', currency: 'EUR');
      await seedTestTransaction(db, userId,
          accountId: accountIds[0], descriptionId: descId,
          date: '2025-06-02', amount: 1000, transactionType: 'income', currency: 'EUR');

      final result = await db.rawQuery('''
        SELECT COALESCE(SUM(CASE WHEN t.transaction_type = 'income' THEN t.amount
                                 WHEN t.transaction_type = 'expense' THEN -t.amount
                                 ELSE 0 END), 0) as total,
               COALESCE(NULLIF(t.currency, ''), 'EUR') as currency
        FROM transactions t WHERE t.user_id = ?
        GROUP BY currency
      ''', [userId]);

      final total = result.fold<double>(0.0, (sum, row) {
        return sum + ((row['total'] as num?)?.toDouble() ?? 0.0);
      });
      expect(total, 1000.0);
    });
  });

  // =========================================================================
  // getBalance (checking accounts only)
  // =========================================================================
  group('getBalance SQL', () {
    test('returns 0 when no transactions exist', () async {
      final rows = await db.rawQuery('''
        SELECT COALESCE(SUM(CASE WHEN t.transaction_type = 'income' THEN t.amount
                                 WHEN t.transaction_type = 'expense' THEN -t.amount
                                 ELSE 0 END), 0) as total,
               COALESCE(NULLIF(a.currency, ''), 'EUR') as currency
        FROM transactions t
        LEFT JOIN accounts a ON t.account_id = a.id
        WHERE (a.type = 'checking' OR t.account_id IS NULL) AND t.user_id = ?
        GROUP BY a.currency
      ''', [userId]);

      final total = rows.fold<double>(0.0, (sum, row) {
        return sum + ((row['total'] as num?)?.toDouble() ?? 0.0);
      });
      expect(total, 0.0);
    });

    test('only counts checking account transactions', () async {
      final descId = await seedTestDescription(db, userId, 'Income');
      await seedTestTransaction(db, userId,
          accountId: accountIds[0], descriptionId: descId,
          date: '2025-06-01', amount: 2000, transactionType: 'income', currency: 'EUR');
      await seedTestTransaction(db, userId,
          accountId: accountIds[1], descriptionId: descId,
          date: '2025-06-02', amount: 5000, transactionType: 'income', currency: 'EUR');

      final rows = await db.rawQuery('''
        SELECT COALESCE(SUM(CASE WHEN t.transaction_type = 'income' THEN t.amount
                                 WHEN t.transaction_type = 'expense' THEN -t.amount
                                 ELSE 0 END), 0) as total,
               COALESCE(NULLIF(a.currency, ''), 'EUR') as currency
        FROM transactions t
        LEFT JOIN accounts a ON t.account_id = a.id
        WHERE (a.type = 'checking' OR t.account_id IS NULL) AND t.user_id = ?
        GROUP BY a.currency
      ''', [userId]);

      final total = rows.fold<double>(0.0, (sum, row) {
        return sum + ((row['total'] as num?)?.toDouble() ?? 0.0);
      });
      expect(total, 2000.0);
    });

    test('includes transactions with null account_id', () async {
      final descId = await seedTestDescription(db, userId, 'Cash');
      await seedTestTransaction(db, userId,
          accountId: null, descriptionId: descId,
          date: '2025-06-01', amount: 300, transactionType: 'income', currency: 'EUR');

      final rows = await db.rawQuery('''
        SELECT COALESCE(SUM(CASE WHEN t.transaction_type = 'income' THEN t.amount
                                 WHEN t.transaction_type = 'expense' THEN -t.amount
                                 ELSE 0 END), 0) as total,
               COALESCE(NULLIF(a.currency, ''), 'EUR') as currency
        FROM transactions t
        LEFT JOIN accounts a ON t.account_id = a.id
        WHERE (a.type = 'checking' OR t.account_id IS NULL) AND t.user_id = ?
        GROUP BY a.currency
      ''', [userId]);

      final total = rows.fold<double>(0.0, (sum, row) {
        return sum + ((row['total'] as num?)?.toDouble() ?? 0.0);
      });
      expect(total, 300.0);
    });

    test('subtracts expenses from checking balance', () async {
      final descId = await seedTestDescription(db, userId, 'Shopping');
      await seedTestTransaction(db, userId,
          accountId: accountIds[0], descriptionId: descId,
          date: '2025-06-01', amount: 1000, transactionType: 'income', currency: 'EUR');
      await seedTestTransaction(db, userId,
          accountId: accountIds[0], descriptionId: descId,
          date: '2025-06-05', amount: 400, transactionType: 'expense', currency: 'EUR');

      final rows = await db.rawQuery('''
        SELECT COALESCE(SUM(CASE WHEN t.transaction_type = 'income' THEN t.amount
                                 WHEN t.transaction_type = 'expense' THEN -t.amount
                                 ELSE 0 END), 0) as total,
               COALESCE(NULLIF(a.currency, ''), 'EUR') as currency
        FROM transactions t
        LEFT JOIN accounts a ON t.account_id = a.id
        WHERE (a.type = 'checking' OR t.account_id IS NULL) AND t.user_id = ?
        GROUP BY a.currency
      ''', [userId]);

      final total = rows.fold<double>(0.0, (sum, row) {
        return sum + ((row['total'] as num?)?.toDouble() ?? 0.0);
      });
      expect(total, 600.0);
    });
  });

  // =========================================================================
  // getSavingsTotal (savings accounts only)
  // =========================================================================
  group('getSavingsTotal SQL', () {
    test('returns 0 when no transactions exist', () async {
      final rows = await db.rawQuery('''
        SELECT COALESCE(SUM(CASE WHEN t.transaction_type = 'income' THEN t.amount
                                 WHEN t.transaction_type = 'expense' THEN -t.amount
                                 ELSE 0 END), 0) as total,
               COALESCE(NULLIF(a.currency, ''), 'EUR') as currency
        FROM transactions t
        LEFT JOIN accounts a ON t.account_id = a.id
        WHERE a.type = 'savings' AND t.user_id = ?
        GROUP BY a.currency
      ''', [userId]);

      final total = rows.fold<double>(0.0, (sum, row) {
        return sum + ((row['total'] as num?)?.toDouble() ?? 0.0);
      });
      expect(total, 0.0);
    });

    test('only counts savings account transactions', () async {
      final descId = await seedTestDescription(db, userId, 'Deposit');
      await seedTestTransaction(db, userId,
          accountId: accountIds[0], descriptionId: descId,
          date: '2025-06-01', amount: 2000, transactionType: 'income', currency: 'EUR');
      await seedTestTransaction(db, userId,
          accountId: accountIds[1], descriptionId: descId,
          date: '2025-06-02', amount: 5000, transactionType: 'income', currency: 'EUR');

      final rows = await db.rawQuery('''
        SELECT COALESCE(SUM(CASE WHEN t.transaction_type = 'income' THEN t.amount
                                 WHEN t.transaction_type = 'expense' THEN -t.amount
                                 ELSE 0 END), 0) as total,
               COALESCE(NULLIF(a.currency, ''), 'EUR') as currency
        FROM transactions t
        LEFT JOIN accounts a ON t.account_id = a.id
        WHERE a.type = 'savings' AND t.user_id = ?
        GROUP BY a.currency
      ''', [userId]);

      final total = rows.fold<double>(0.0, (sum, row) {
        return sum + ((row['total'] as num?)?.toDouble() ?? 0.0);
      });
      expect(total, 5000.0);
    });

    test('combines both savings accounts', () async {
      final descId = await seedTestDescription(db, userId, 'Interest');
      await seedTestTransaction(db, userId,
          accountId: accountIds[1], descriptionId: descId,
          date: '2025-06-01', amount: 100, transactionType: 'income', currency: 'EUR');
      await seedTestTransaction(db, userId,
          accountId: accountIds[2], descriptionId: descId,
          date: '2025-06-02', amount: 200, transactionType: 'income', currency: 'EUR');

      final rows = await db.rawQuery('''
        SELECT COALESCE(SUM(CASE WHEN t.transaction_type = 'income' THEN t.amount
                                 WHEN t.transaction_type = 'expense' THEN -t.amount
                                 ELSE 0 END), 0) as total,
               COALESCE(NULLIF(a.currency, ''), 'EUR') as currency
        FROM transactions t
        LEFT JOIN accounts a ON t.account_id = a.id
        WHERE a.type = 'savings' AND t.user_id = ?
        GROUP BY a.currency
      ''', [userId]);

      final total = rows.fold<double>(0.0, (sum, row) {
        return sum + ((row['total'] as num?)?.toDouble() ?? 0.0);
      });
      expect(total, 300.0);
    });
  });

  // =========================================================================
  // getHistoryPatrimony
  // =========================================================================
  group('getHistoryPatrimony SQL', () {
    test('returns 0 when no transactions before date limit', () async {
      final result = await db.rawQuery('''
        SELECT COALESCE(SUM(CASE WHEN t.transaction_type = 'income' THEN t.amount
                                 WHEN t.transaction_type = 'expense' THEN -t.amount
                                 ELSE 0 END), 0) as total,
               COALESCE(NULLIF(t.currency, ''), 'EUR') as currency
        FROM transactions t WHERE t.date < ? AND t.user_id = ?
        GROUP BY currency
      ''', ['2025-01-01', userId]);

      final total = result.fold<double>(0.0, (sum, row) {
        return sum + ((row['total'] as num?)?.toDouble() ?? 0.0);
      });
      expect(total, 0.0);
    });

    test('only includes transactions strictly before the date limit', () async {
      final descId = await seedTestDescription(db, userId, 'Salary');
      await seedTestTransaction(db, userId,
          accountId: accountIds[0], descriptionId: descId,
          date: '2025-05-31', amount: 1000, transactionType: 'income', currency: 'EUR');
      await seedTestTransaction(db, userId,
          accountId: accountIds[0], descriptionId: descId,
          date: '2025-06-01', amount: 2000, transactionType: 'income', currency: 'EUR');

      final result = await db.rawQuery('''
        SELECT COALESCE(SUM(CASE WHEN t.transaction_type = 'income' THEN t.amount
                                 WHEN t.transaction_type = 'expense' THEN -t.amount
                                 ELSE 0 END), 0) as total,
               COALESCE(NULLIF(t.currency, ''), 'EUR') as currency
        FROM transactions t WHERE t.date < ? AND t.user_id = ?
        GROUP BY currency
      ''', ['2025-06-01', userId]);

      final total = result.fold<double>(0.0, (sum, row) {
        return sum + ((row['total'] as num?)?.toDouble() ?? 0.0);
      });
      expect(total, 1000.0);
    });

    test('includes expenses as negatives in history', () async {
      final descId = await seedTestDescription(db, userId, 'Rent');
      await seedTestTransaction(db, userId,
          accountId: accountIds[0], descriptionId: descId,
          date: '2025-03-01', amount: 3000, transactionType: 'income', currency: 'EUR');
      await seedTestTransaction(db, userId,
          accountId: accountIds[0], descriptionId: descId,
          date: '2025-04-01', amount: 1500, transactionType: 'expense', currency: 'EUR');

      final result = await db.rawQuery('''
        SELECT COALESCE(SUM(CASE WHEN t.transaction_type = 'income' THEN t.amount
                                 WHEN t.transaction_type = 'expense' THEN -t.amount
                                 ELSE 0 END), 0) as total,
               COALESCE(NULLIF(t.currency, ''), 'EUR') as currency
        FROM transactions t WHERE t.date < ? AND t.user_id = ?
        GROUP BY currency
      ''', ['2025-05-01', userId]);

      final total = result.fold<double>(0.0, (sum, row) {
        return sum + ((row['total'] as num?)?.toDouble() ?? 0.0);
      });
      expect(total, 1500.0);
    });
  });

  // =========================================================================
  // getHistoryBalance (checking only, before date)
  // =========================================================================
  group('getHistoryBalance SQL', () {
    test('returns 0 when no transactions', () async {
      final rows = await db.rawQuery('''
        SELECT COALESCE(SUM(CASE WHEN t.transaction_type = 'income' THEN t.amount
                                 WHEN t.transaction_type = 'expense' THEN -t.amount
                                 ELSE 0 END), 0) as total,
               COALESCE(NULLIF(a.currency, ''), 'EUR') as currency
        FROM transactions t
        LEFT JOIN accounts a ON t.account_id = a.id
        WHERE t.date < ? AND (a.type = 'checking' OR t.account_id IS NULL) AND t.user_id = ?
        GROUP BY a.currency
      ''', ['2025-06-01', userId]);

      final total = rows.fold<double>(0.0, (sum, row) {
        return sum + ((row['total'] as num?)?.toDouble() ?? 0.0);
      });
      expect(total, 0.0);
    });

    test('only includes checking account transactions before date', () async {
      final descId = await seedTestDescription(db, userId, 'Income');
      await seedTestTransaction(db, userId,
          accountId: accountIds[0], descriptionId: descId,
          date: '2025-05-01', amount: 1000, transactionType: 'income', currency: 'EUR');
      await seedTestTransaction(db, userId,
          accountId: accountIds[1], descriptionId: descId,
          date: '2025-05-01', amount: 5000, transactionType: 'income', currency: 'EUR');

      final rows = await db.rawQuery('''
        SELECT COALESCE(SUM(CASE WHEN t.transaction_type = 'income' THEN t.amount
                                 WHEN t.transaction_type = 'expense' THEN -t.amount
                                 ELSE 0 END), 0) as total,
               COALESCE(NULLIF(a.currency, ''), 'EUR') as currency
        FROM transactions t
        LEFT JOIN accounts a ON t.account_id = a.id
        WHERE t.date < ? AND (a.type = 'checking' OR t.account_id IS NULL) AND t.user_id = ?
        GROUP BY a.currency
      ''', ['2025-06-01', userId]);

      final total = rows.fold<double>(0.0, (sum, row) {
        return sum + ((row['total'] as num?)?.toDouble() ?? 0.0);
      });
      expect(total, 1000.0);
    });
  });

  // =========================================================================
  // getHistorySavings (savings only, before date)
  // =========================================================================
  group('getHistorySavings SQL', () {
    test('returns 0 when no transactions', () async {
      final rows = await db.rawQuery('''
        SELECT COALESCE(SUM(CASE WHEN t.transaction_type = 'income' THEN t.amount
                                 WHEN t.transaction_type = 'expense' THEN -t.amount
                                 ELSE 0 END), 0) as total,
               COALESCE(NULLIF(a.currency, ''), 'EUR') as currency
        FROM transactions t
        LEFT JOIN accounts a ON t.account_id = a.id
        WHERE t.date < ? AND a.type = 'savings' AND t.user_id = ?
        GROUP BY a.currency
      ''', ['2025-06-01', userId]);

      final total = rows.fold<double>(0.0, (sum, row) {
        return sum + ((row['total'] as num?)?.toDouble() ?? 0.0);
      });
      expect(total, 0.0);
    });

    test('only includes savings account transactions before date', () async {
      final descId = await seedTestDescription(db, userId, 'Deposit');
      await seedTestTransaction(db, userId,
          accountId: accountIds[0], descriptionId: descId,
          date: '2025-05-01', amount: 1000, transactionType: 'income', currency: 'EUR');
      await seedTestTransaction(db, userId,
          accountId: accountIds[1], descriptionId: descId,
          date: '2025-05-01', amount: 5000, transactionType: 'income', currency: 'EUR');

      final rows = await db.rawQuery('''
        SELECT COALESCE(SUM(CASE WHEN t.transaction_type = 'income' THEN t.amount
                                 WHEN t.transaction_type = 'expense' THEN -t.amount
                                 ELSE 0 END), 0) as total,
               COALESCE(NULLIF(a.currency, ''), 'EUR') as currency
        FROM transactions t
        LEFT JOIN accounts a ON t.account_id = a.id
        WHERE t.date < ? AND a.type = 'savings' AND t.user_id = ?
        GROUP BY a.currency
      ''', ['2025-06-01', userId]);

      final total = rows.fold<double>(0.0, (sum, row) {
        return sum + ((row['total'] as num?)?.toDouble() ?? 0.0);
      });
      expect(total, 5000.0);
    });
  });

  // =========================================================================
  // getMonthlySummary
  // =========================================================================
  group('getMonthlySummary SQL', () {
    test('returns zero map when no transactions in month', () async {
      final startDate = '2025-06-01';
      final endDate = '2025-07-01';

      final rows = await db.rawQuery('''
        SELECT
          COALESCE(SUM(CASE WHEN t.transaction_type = 'income' THEN t.amount ELSE 0 END), 0) as income,
          COALESCE(SUM(CASE WHEN t.transaction_type = 'expense' THEN t.amount ELSE 0 END), 0) as expenses,
          COALESCE(NULLIF(a.currency, ''), 'EUR') as currency
        FROM transactions t
        LEFT JOIN accounts a ON t.account_id = a.id
        WHERE (t.date >= ? AND t.date < ?) AND (a.type = 'checking' OR t.account_id IS NULL) AND t.user_id = ?
        GROUP BY a.currency
      ''', [startDate, endDate, userId]);

      double income = 0.0;
      double expenses = 0.0;
      for (final row in rows) {
        income += (row['income'] as num?)?.toDouble() ?? 0.0;
        expenses += (row['expenses'] as num?)?.toDouble() ?? 0.0;
      }
      expect(income, 0.0);
      expect(expenses, 0.0);
      expect(income - expenses, 0.0);
    });

    test('calculates income and expenses for a specific month', () async {
      final descId = await seedTestDescription(db, userId, 'Food');
      // In June
      await seedTestTransaction(db, userId,
          accountId: accountIds[0], descriptionId: descId,
          date: '2025-06-01', amount: 3000, transactionType: 'income', currency: 'EUR');
      await seedTestTransaction(db, userId,
          accountId: accountIds[0], descriptionId: descId,
          date: '2025-06-15', amount: 800, transactionType: 'expense', currency: 'EUR');
      // In July (should not count)
      await seedTestTransaction(db, userId,
          accountId: accountIds[0], descriptionId: descId,
          date: '2025-07-01', amount: 1000, transactionType: 'income', currency: 'EUR');

      final startDate = '2025-06-01';
      final endDate = '2025-07-01';

      final rows = await db.rawQuery('''
        SELECT
          COALESCE(SUM(CASE WHEN t.transaction_type = 'income' THEN t.amount ELSE 0 END), 0) as income,
          COALESCE(SUM(CASE WHEN t.transaction_type = 'expense' THEN t.amount ELSE 0 END), 0) as expenses,
          COALESCE(NULLIF(a.currency, ''), 'EUR') as currency
        FROM transactions t
        LEFT JOIN accounts a ON t.account_id = a.id
        WHERE (t.date >= ? AND t.date < ?) AND (a.type = 'checking' OR t.account_id IS NULL) AND t.user_id = ?
        GROUP BY a.currency
      ''', [startDate, endDate, userId]);

      double income = 0.0;
      double expenses = 0.0;
      for (final row in rows) {
        income += (row['income'] as num?)?.toDouble() ?? 0.0;
        expenses += (row['expenses'] as num?)?.toDouble() ?? 0.0;
      }
      expect(income, 3000.0);
      expect(expenses, 800.0);
      expect(income - expenses, 2200.0);
    });

    test('excludes savings accounts from monthly summary', () async {
      final descId = await seedTestDescription(db, userId, 'Deposit');
      await seedTestTransaction(db, userId,
          accountId: accountIds[0], descriptionId: descId,
          date: '2025-06-01', amount: 1000, transactionType: 'income', currency: 'EUR');
      await seedTestTransaction(db, userId,
          accountId: accountIds[1], descriptionId: descId,
          date: '2025-06-01', amount: 5000, transactionType: 'income', currency: 'EUR');

      final startDate = '2025-06-01';
      final endDate = '2025-07-01';

      final rows = await db.rawQuery('''
        SELECT
          COALESCE(SUM(CASE WHEN t.transaction_type = 'income' THEN t.amount ELSE 0 END), 0) as income,
          COALESCE(SUM(CASE WHEN t.transaction_type = 'expense' THEN t.amount ELSE 0 END), 0) as expenses,
          COALESCE(NULLIF(a.currency, ''), 'EUR') as currency
        FROM transactions t
        LEFT JOIN accounts a ON t.account_id = a.id
        WHERE (t.date >= ? AND t.date < ?) AND (a.type = 'checking' OR t.account_id IS NULL) AND t.user_id = ?
        GROUP BY a.currency
      ''', [startDate, endDate, userId]);

      double income = 0.0;
      for (final row in rows) {
        income += (row['income'] as num?)?.toDouble() ?? 0.0;
      }
      expect(income, 1000.0);
    });
  });

  // =========================================================================
  // getRollingSummary
  // =========================================================================
  group('getRollingSummary SQL', () {
    test('returns zeros when no transactions in window', () async {
      final now = DateTime.now();
      final endDate = now.toIso8601String().substring(0, 10);
      final startDate = now.subtract(const Duration(days: 30)).toIso8601String().substring(0, 10);

      final rows = await db.rawQuery('''
        SELECT
          COALESCE(SUM(CASE WHEN t.transaction_type = 'income' THEN t.amount ELSE 0 END), 0) as income,
          COALESCE(SUM(CASE WHEN t.transaction_type = 'expense' THEN t.amount ELSE 0 END), 0) as expenses,
          COALESCE(NULLIF(a.currency, ''), 'EUR') as currency
        FROM transactions t
        LEFT JOIN accounts a ON t.account_id = a.id
        WHERE (t.date >= ? AND t.date <= ?) AND (a.type = 'checking' OR t.account_id IS NULL) AND t.user_id = ?
        GROUP BY a.currency
      ''', [startDate, endDate, userId]);

      double income = 0.0;
      double expenses = 0.0;
      for (final row in rows) {
        income += (row['income'] as num?)?.toDouble() ?? 0.0;
        expenses += (row['expenses'] as num?)?.toDouble() ?? 0.0;
      }
      expect(income, 0.0);
      expect(expenses, 0.0);
    });

    test('captures transactions within the rolling window', () async {
      final now = DateTime.now();
      final endDate = now.toIso8601String().substring(0, 10);
      final startDate = now.subtract(const Duration(days: 30)).toIso8601String().substring(0, 10);

      final descId = await seedTestDescription(db, userId, 'Lunch');
      await seedTestTransaction(db, userId,
          accountId: accountIds[0], descriptionId: descId,
          date: startDate, amount: 150, transactionType: 'expense', currency: 'EUR');
      await seedTestTransaction(db, userId,
          accountId: accountIds[0], descriptionId: descId,
          date: endDate, amount: 500, transactionType: 'income', currency: 'EUR');

      final rows = await db.rawQuery('''
        SELECT
          COALESCE(SUM(CASE WHEN t.transaction_type = 'income' THEN t.amount ELSE 0 END), 0) as income,
          COALESCE(SUM(CASE WHEN t.transaction_type = 'expense' THEN t.amount ELSE 0 END), 0) as expenses,
          COALESCE(NULLIF(a.currency, ''), 'EUR') as currency
        FROM transactions t
        LEFT JOIN accounts a ON t.account_id = a.id
        WHERE (t.date >= ? AND t.date <= ?) AND (a.type = 'checking' OR t.account_id IS NULL) AND t.user_id = ?
        GROUP BY a.currency
      ''', [startDate, endDate, userId]);

      double income = 0.0;
      double expenses = 0.0;
      for (final row in rows) {
        income += (row['income'] as num?)?.toDouble() ?? 0.0;
        expenses += (row['expenses'] as num?)?.toDouble() ?? 0.0;
      }
      expect(income, 500.0);
      expect(expenses, 150.0);
    });

    test('excludes transactions outside the rolling window', () async {
      final now = DateTime.now();
      final endDate = now.toIso8601String().substring(0, 10);
      final startDate = now.subtract(const Duration(days: 30)).toIso8601String().substring(0, 10);

      final descId = await seedTestDescription(db, userId, 'Old Purchase');
      final outsideDate = now.subtract(const Duration(days: 60)).toIso8601String().substring(0, 10);
      await seedTestTransaction(db, userId,
          accountId: accountIds[0], descriptionId: descId,
          date: outsideDate, amount: 9999, transactionType: 'income', currency: 'EUR');

      final rows = await db.rawQuery('''
        SELECT
          COALESCE(SUM(CASE WHEN t.transaction_type = 'income' THEN t.amount ELSE 0 END), 0) as income,
          COALESCE(SUM(CASE WHEN t.transaction_type = 'expense' THEN t.amount ELSE 0 END), 0) as expenses,
          COALESCE(NULLIF(a.currency, ''), 'EUR') as currency
        FROM transactions t
        LEFT JOIN accounts a ON t.account_id = a.id
        WHERE (t.date >= ? AND t.date <= ?) AND (a.type = 'checking' OR t.account_id IS NULL) AND t.user_id = ?
        GROUP BY a.currency
      ''', [startDate, endDate, userId]);

      double income = 0.0;
      for (final row in rows) {
        income += (row['income'] as num?)?.toDouble() ?? 0.0;
      }
      expect(income, 0.0);
    });
  });

  // =========================================================================
  // getAccountsDistribution
  // =========================================================================
  group('getAccountsDistribution SQL', () {
    test('returns all accounts with zero balance when no transactions', () async {
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
      ''', [userId, userId]);

      expect(rows.length, 3);
      for (final row in rows) {
        expect(row['balance'], 0.0);
      }
    });

    test('calculates per-account balances correctly', () async {
      final descId = await seedTestDescription(db, userId, 'Income');
      await seedTestTransaction(db, userId,
          accountId: accountIds[0], descriptionId: descId,
          date: '2025-06-01', amount: 2000, transactionType: 'income', currency: 'EUR');
      await seedTestTransaction(db, userId,
          accountId: accountIds[0], descriptionId: descId,
          date: '2025-06-02', amount: 500, transactionType: 'expense', currency: 'EUR');
      await seedTestTransaction(db, userId,
          accountId: accountIds[1], descriptionId: descId,
          date: '2025-06-03', amount: 10000, transactionType: 'income', currency: 'EUR');

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
      ''', [userId, userId]);

      final checking = rows.firstWhere((r) => r['name'] == 'Checking Account');
      final savingsA = rows.firstWhere((r) => r['name'] == 'Savings Account A');
      final savingsB = rows.firstWhere((r) => r['name'] == 'Savings Account B');

      expect(checking['balance'], 1500.0);
      expect(savingsA['balance'], 10000.0);
      expect(savingsB['balance'], 0.0);
    });

    test('orders accounts by name', () async {
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
      ''', [userId, userId]);

      final names = rows.map((r) => r['name'] as String).toList();
      expect(names, ['Checking Account', 'Savings Account A', 'Savings Account B']);
    });
  });

  // =========================================================================
  // getCategoryDistribution
  // =========================================================================
  group('getCategoryDistribution SQL', () {
    test('returns empty when no transactions', () async {
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
      ''', ['expense', startDate, endDate, userId]);

      expect(rows, isEmpty);
    });

    test('groups expenses by category and month', () async {
      final now = DateTime.now();
      final startDate = now.subtract(const Duration(days: 180)).toIso8601String().substring(0, 10);
      final endDate = now.toIso8601String().substring(0, 10);
      final sameMonthDate1 = DateTime(now.year, now.month, 5).toIso8601String().substring(0, 10);
      final sameMonthDate2 = DateTime(now.year, now.month, 15).toIso8601String().substring(0, 10);
      final sameMonthDate3 = DateTime(now.year, now.month, 1).toIso8601String().substring(0, 10);

      final foodId = await seedTestDescription(db, userId, 'Food');
      final rentId = await seedTestDescription(db, userId, 'Rent');
      await seedTestTransaction(db, userId,
          accountId: accountIds[0], descriptionId: foodId,
          date: sameMonthDate1, amount: 50, transactionType: 'expense', currency: 'EUR');
      await seedTestTransaction(db, userId,
          accountId: accountIds[0], descriptionId: foodId,
          date: sameMonthDate2, amount: 75, transactionType: 'expense', currency: 'EUR');
      await seedTestTransaction(db, userId,
          accountId: accountIds[0], descriptionId: rentId,
          date: sameMonthDate3, amount: 1200, transactionType: 'expense', currency: 'EUR');

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
      ''', ['expense', startDate, endDate, userId]);

      expect(rows.length, 2);
      final foodRow = rows.firstWhere((r) => r['description'] == 'food');
      final rentRow = rows.firstWhere((r) => r['description'] == 'rent');
      expect(foodRow['amount'], 125.0);
      expect(rentRow['amount'], 1200.0);
    });

    test('limits results to top N categories', () async {
      final now = DateTime.now();
      final startDate = now.subtract(const Duration(days: 180)).toIso8601String().substring(0, 10);
      final endDate = now.toIso8601String().substring(0, 10);
      final txnDate = DateTime(now.year, now.month, 5).toIso8601String().substring(0, 10);

      final d1 = await seedTestDescription(db, userId, 'Food');
      final d2 = await seedTestDescription(db, userId, 'Rent');
      final d3 = await seedTestDescription(db, userId, 'Transport');
      final d4 = await seedTestDescription(db, userId, 'Entertainment');
      await seedTestTransaction(db, userId,
          accountId: accountIds[0], descriptionId: d1,
          date: txnDate, amount: 100, transactionType: 'expense', currency: 'EUR');
      await seedTestTransaction(db, userId,
          accountId: accountIds[0], descriptionId: d2,
          date: txnDate, amount: 500, transactionType: 'expense', currency: 'EUR');
      await seedTestTransaction(db, userId,
          accountId: accountIds[0], descriptionId: d3,
          date: txnDate, amount: 200, transactionType: 'expense', currency: 'EUR');
      await seedTestTransaction(db, userId,
          accountId: accountIds[0], descriptionId: d4,
          date: txnDate, amount: 300, transactionType: 'expense', currency: 'EUR');

      final allRows = await db.rawQuery('''
        SELECT LOWER(COALESCE(d.name, 'Uncategorized')) as description,
               strftime('%Y-%m', t.date) as month,
               t.transaction_type as type,
               SUM(t.amount) as amount
        FROM transactions t
        LEFT JOIN descriptions d ON t.description_id = d.id
        WHERE t.transaction_type = ? AND t.date >= ? AND t.date <= ? AND t.user_id = ?
        GROUP BY description, month, t.transaction_type
        ORDER BY month, amount DESC
      ''', ['expense', startDate, endDate, userId]);

      // Apply the same top-N limit logic as DatabaseManager
      final byDesc = <String, double>{};
      for (final r in allRows) {
        final d = r['description'] as String;
        byDesc[d] = (byDesc[d] ?? 0) + (r['amount'] as num).toDouble();
      }
      final sorted = byDesc.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      final limit = 2;
      final topDescs = sorted.take(limit).map((e) => e.key).toSet();
      final results = allRows.where((r) => topDescs.contains(r['description'])).toList();

      expect(results.length, 2);
      expect(results.every((r) => topDescs.contains(r['description'])), true);
    });
  });

  // =========================================================================
  // getDescriptionMonthlyData
  // =========================================================================
  group('getDescriptionMonthlyData SQL', () {
    test('returns empty map when no transactions', () async {
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
      ''', ['2025-01-01', '2025-12-31', userId]);

      expect(rows, isEmpty);
    });

    test('builds description -> month -> type breakdown', () async {
      final foodId = await seedTestDescription(db, userId, 'Food');
      await seedTestTransaction(db, userId,
          accountId: accountIds[0], descriptionId: foodId,
          date: '2025-06-01', amount: 50, transactionType: 'expense', currency: 'EUR');
      await seedTestTransaction(db, userId,
          accountId: accountIds[0], descriptionId: foodId,
          date: '2025-06-15', amount: 75, transactionType: 'expense', currency: 'EUR');
      await seedTestTransaction(db, userId,
          accountId: accountIds[0], descriptionId: foodId,
          date: '2025-07-01', amount: 100, transactionType: 'expense', currency: 'EUR');

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
      ''', ['2025-01-01', '2025-12-31', userId]);

      // Build the same structure as DatabaseManager
      final result = <String, Map<String, Map<String, double>>>{};
      for (final row in rows) {
        final desc = (row['desc'] as String?) ?? 'uncategorized';
        final month = row['month'] as String;
        final type = row['transaction_type'] as String;
        final total = (row['total'] as num).toDouble();
        result.putIfAbsent(desc, () => {});
        result[desc]!.putIfAbsent(month, () => {'income': 0, 'expense': 0, 'total': 0});
        if (type == 'income') {
          result[desc]![month]!['income'] = result[desc]![month]!['income']! + total;
        } else if (type == 'expense') {
          result[desc]![month]!['expense'] = result[desc]![month]!['expense']! + total;
        }
        result[desc]![month]!['total'] = result[desc]![month]!['total']! + total;
      }

      expect(result.containsKey('food'), true);
      expect(result['food']!['2025-06']!['expense'], 125.0);
      expect(result['food']!['2025-06']!['total'], 125.0);
      expect(result['food']!['2025-07']!['expense'], 100.0);
      expect(result['food']!['2025-07']!['total'], 100.0);
    });
  });

  // =========================================================================
  // getTopDescriptions
  // =========================================================================
  group('getTopDescriptions SQL', () {
    test('returns empty when no transactions', () async {
      final now = DateTime.now();
      final startDate = now.subtract(const Duration(days: 180)).toIso8601String().substring(0, 10);
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
      ''', ['expense', startDate, endDate, userId, 1]);

      expect(rows, isEmpty);
    });

    test('returns top descriptions ordered by total amount', () async {
      final now = DateTime.now();
      final startDate = now.subtract(const Duration(days: 180)).toIso8601String().substring(0, 10);
      final endDate = now.toIso8601String().substring(0, 10);
      final txnDate = DateTime(now.year, now.month, 5).toIso8601String().substring(0, 10);

      final d1 = await seedTestDescription(db, userId, 'Cheap Item');
      final d2 = await seedTestDescription(db, userId, 'Expensive Item');
      final d3 = await seedTestDescription(db, userId, 'Medium Item');
      await seedTestTransaction(db, userId,
          accountId: accountIds[0], descriptionId: d1,
          date: txnDate, amount: 10, transactionType: 'expense', currency: 'EUR');
      await seedTestTransaction(db, userId,
          accountId: accountIds[0], descriptionId: d2,
          date: txnDate, amount: 500, transactionType: 'expense', currency: 'EUR');
      await seedTestTransaction(db, userId,
          accountId: accountIds[0], descriptionId: d3,
          date: txnDate, amount: 100, transactionType: 'expense', currency: 'EUR');

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
      ''', ['expense', startDate, endDate, userId, 1]);

      expect(rows.length, 3);
      expect(rows[0]['desc'], 'expensive item');
      expect(rows[1]['desc'], 'medium item');
      expect(rows[2]['desc'], 'cheap item');
    });

    test('respects minCount filter', () async {
      final now = DateTime.now();
      final startDate = now.subtract(const Duration(days: 180)).toIso8601String().substring(0, 10);
      final endDate = now.toIso8601String().substring(0, 10);
      final txnDate1 = DateTime(now.year, now.month, 5).toIso8601String().substring(0, 10);
      final txnDate2 = DateTime(now.year, now.month, 10).toIso8601String().substring(0, 10);
      final txnDate3 = DateTime(now.year, now.month, 15).toIso8601String().substring(0, 10);

      final d1 = await seedTestDescription(db, userId, 'Single Purchase');
      final d2 = await seedTestDescription(db, userId, 'Repeated Purchase');
      await seedTestTransaction(db, userId,
          accountId: accountIds[0], descriptionId: d1,
          date: txnDate1, amount: 100, transactionType: 'expense', currency: 'EUR');
      await seedTestTransaction(db, userId,
          accountId: accountIds[0], descriptionId: d2,
          date: txnDate1, amount: 50, transactionType: 'expense', currency: 'EUR');
      await seedTestTransaction(db, userId,
          accountId: accountIds[0], descriptionId: d2,
          date: txnDate2, amount: 50, transactionType: 'expense', currency: 'EUR');
      await seedTestTransaction(db, userId,
          accountId: accountIds[0], descriptionId: d2,
          date: txnDate3, amount: 50, transactionType: 'expense', currency: 'EUR');

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
      ''', ['expense', startDate, endDate, userId, 2]);

      expect(rows.length, 1);
      expect(rows[0]['desc'], 'repeated purchase');
    });
  });

  // =========================================================================
  // getMonthlyChartData
  // =========================================================================
  group('getMonthlyChartData SQL', () {
    test('returns empty when no transactions', () async {
      final rows = await db.rawQuery('''
        SELECT strftime('%m', t.date) as month,
               COALESCE(SUM(CASE WHEN t.transaction_type = 'income' THEN t.amount ELSE 0 END), 0) as income,
               COALESCE(SUM(CASE WHEN t.transaction_type = 'expense' THEN t.amount ELSE 0 END), 0) as expenses
        FROM transactions t
        LEFT JOIN accounts a ON t.account_id = a.id
        WHERE strftime('%Y', t.date) = ? AND (a.type = 'checking' OR t.account_id IS NULL) AND t.user_id = ?
        GROUP BY month
        ORDER BY month
      ''', ['2025', userId]);

      expect(rows, isEmpty);
    });

    test('groups income/expenses by month for a given year', () async {
      final descId = await seedTestDescription(db, userId, 'Income');
      await seedTestTransaction(db, userId,
          accountId: accountIds[0], descriptionId: descId,
          date: '2025-03-10', amount: 2000, transactionType: 'income', currency: 'EUR');
      await seedTestTransaction(db, userId,
          accountId: accountIds[0], descriptionId: descId,
          date: '2025-03-15', amount: 300, transactionType: 'expense', currency: 'EUR');
      await seedTestTransaction(db, userId,
          accountId: accountIds[0], descriptionId: descId,
          date: '2025-05-20', amount: 2500, transactionType: 'income', currency: 'EUR');
      // Different year should not count
      await seedTestTransaction(db, userId,
          accountId: accountIds[0], descriptionId: descId,
          date: '2024-06-01', amount: 9999, transactionType: 'income', currency: 'EUR');

      final rows = await db.rawQuery('''
        SELECT strftime('%m', t.date) as month,
               COALESCE(SUM(CASE WHEN t.transaction_type = 'income' THEN t.amount ELSE 0 END), 0) as income,
               COALESCE(SUM(CASE WHEN t.transaction_type = 'expense' THEN t.amount ELSE 0 END), 0) as expenses
        FROM transactions t
        LEFT JOIN accounts a ON t.account_id = a.id
        WHERE strftime('%Y', t.date) = ? AND (a.type = 'checking' OR t.account_id IS NULL) AND t.user_id = ?
        GROUP BY month
        ORDER BY month
      ''', ['2025', userId]);

      expect(rows.length, 2);
      final march = rows.firstWhere((r) => r['month'] == '03');
      final may = rows.firstWhere((r) => r['month'] == '05');
      expect(march['income'], 2000.0);
      expect(march['expenses'], 300.0);
      expect(may['income'], 2500.0);
      expect(may['expenses'], 0.0);
    });

    test('excludes savings accounts from monthly chart', () async {
      final descId = await seedTestDescription(db, userId, 'Deposit');
      await seedTestTransaction(db, userId,
          accountId: accountIds[0], descriptionId: descId,
          date: '2025-06-01', amount: 1000, transactionType: 'income', currency: 'EUR');
      await seedTestTransaction(db, userId,
          accountId: accountIds[1], descriptionId: descId,
          date: '2025-06-01', amount: 5000, transactionType: 'income', currency: 'EUR');

      final rows = await db.rawQuery('''
        SELECT strftime('%m', t.date) as month,
               COALESCE(SUM(CASE WHEN t.transaction_type = 'income' THEN t.amount ELSE 0 END), 0) as income,
               COALESCE(SUM(CASE WHEN t.transaction_type = 'expense' THEN t.amount ELSE 0 END), 0) as expenses
        FROM transactions t
        LEFT JOIN accounts a ON t.account_id = a.id
        WHERE strftime('%Y', t.date) = ? AND (a.type = 'checking' OR t.account_id IS NULL) AND t.user_id = ?
        GROUP BY month
        ORDER BY month
      ''', ['2025', userId]);

      final june = rows.firstWhere((r) => r['month'] == '06');
      expect(june['income'], 1000.0);
    });
  });

  // =========================================================================
  // getCashFlowData
  // =========================================================================
  group('getCashFlowData SQL', () {
    test('returns empty when no transactions', () async {
      final now = DateTime.now();
      final startDate = DateTime(now.year, now.month - 5, 1)
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
      ''', [startDate, userId]);

      expect(rows, isEmpty);
    });

    test('groups cash flow by month and type', () async {
      final now = DateTime.now();
      final startDate = DateTime(now.year, now.month - 5, 1)
          .toIso8601String()
          .substring(0, 10);

      final incomeId = await seedTestDescription(db, userId, 'Salary');
      final expenseId = await seedTestDescription(db, userId, 'Groceries');
      await seedTestTransaction(db, userId,
          accountId: accountIds[0], descriptionId: incomeId,
          date: '${now.year}-${now.month.toString().padLeft(2, '0')}-01',
          amount: 3000, transactionType: 'income', currency: 'EUR');
      await seedTestTransaction(db, userId,
          accountId: accountIds[0], descriptionId: expenseId,
          date: '${now.year}-${now.month.toString().padLeft(2, '0')}-05',
          amount: 500, transactionType: 'expense', currency: 'EUR');

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
      ''', [startDate, userId]);

      expect(rows.isNotEmpty, true);
      final incomeRow = rows.firstWhere((r) => r['type'] == 'income');
      expect(incomeRow['amount'], 3000.0);
    });

    test('excludes transfer descriptions from cash flow', () async {
      final now = DateTime.now();
      final startDate = DateTime(now.year, now.month - 5, 1)
          .toIso8601String()
          .substring(0, 10);

      final transferToId = await seedTestDescription(db, userId, 'Transfer to Savings');
      final transferFromId = await seedTestDescription(db, userId, 'Transfer from Checking');
      final incomeId = await seedTestDescription(db, userId, 'Salary');
      await seedTestTransaction(db, userId,
          accountId: accountIds[0], descriptionId: transferToId,
          date: '${now.year}-${now.month.toString().padLeft(2, '0')}-01',
          amount: 1000, transactionType: 'transfer', currency: 'EUR');
      await seedTestTransaction(db, userId,
          accountId: accountIds[1], descriptionId: transferFromId,
          date: '${now.year}-${now.month.toString().padLeft(2, '0')}-02',
          amount: 1000, transactionType: 'transfer', currency: 'EUR');
      await seedTestTransaction(db, userId,
          accountId: accountIds[0], descriptionId: incomeId,
          date: '${now.year}-${now.month.toString().padLeft(2, '0')}-03',
          amount: 2000, transactionType: 'income', currency: 'EUR');

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
      ''', [startDate, userId]);

      final currentMonthKey = '${now.year}-${now.month.toString().padLeft(2, '0')}';
      final monthRows = rows.where((r) => r['month'] == currentMonthKey).toList();
      final totalAmount = monthRows.fold<double>(0.0, (sum, r) {
        return sum + ((r['amount'] as num?)?.toDouble() ?? 0.0);
      });
      expect(totalAmount, 2000.0);
    });
  });

  // =========================================================================
  // getAssetsHistory
  // =========================================================================
  group('getAssetsHistory SQL', () {
    test('returns all zero months when no transactions', () async {
      final now = DateTime.now();
      final months = 3;
      final results = <double>[];

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
        ''', [endDate, userId]);

        double totalValue = 0.0;
        for (final row in rows) {
          totalValue += (row['total'] as num?)?.toDouble() ?? 0.0;
        }
        results.add(totalValue);
      }

      expect(results.length, months);
      expect(results.every((v) => v == 0.0), true);
    });

    test('accumulates transactions chronologically across months', () async {
      final now = DateTime.now();
      final descId = await seedTestDescription(db, userId, 'Income');

      // Transaction 3 months ago
      final threeMonthsAgo = DateTime(now.year, now.month - 2, 1);
      await seedTestTransaction(db, userId,
          accountId: accountIds[0], descriptionId: descId,
          date: threeMonthsAgo.toIso8601String().substring(0, 10),
          amount: 1000, transactionType: 'income', currency: 'EUR');

      // Transaction 1 month ago
      final oneMonthAgo = DateTime(now.year, now.month, 1);
      await seedTestTransaction(db, userId,
          accountId: accountIds[0], descriptionId: descId,
          date: oneMonthAgo.toIso8601String().substring(0, 10),
          amount: 500, transactionType: 'income', currency: 'EUR');

      final months = 3;
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
        ''', [endDate, userId]);

        double totalValue = 0.0;
        for (final row in rows) {
          totalValue += (row['total'] as num?)?.toDouble() ?? 0.0;
        }
        results.add({'month': month, 'value': totalValue});
      }

      // The values should be non-decreasing as we add more months
      expect(results.length, months);
      final values = results.map((r) => r['value'] as double).toList();
      // Each subsequent month should have >= previous month's value (since we only add income)
      for (int i = 1; i < values.length; i++) {
        expect(values[i] >= values[i - 1], true);
      }
    });
  });

  // =========================================================================
  // getCurrentMonthDistribution
  // =========================================================================
  group('getCurrentMonthDistribution SQL', () {
    test('returns empty when no transactions in current month', () async {
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
      ''', ['expense', startDate, endDate, userId]);

      expect(rows, isEmpty);
    });

    test('groups current month expenses by category', () async {
      final now = DateTime.now();
      final startDate = DateTime(now.year, now.month, 1)
          .toIso8601String()
          .substring(0, 10);
      final endDate = now.toIso8601String().substring(0, 10);

      final foodId = await seedTestDescription(db, userId, 'Food');
      final rentId = await seedTestDescription(db, userId, 'Rent');
      await seedTestTransaction(db, userId,
          accountId: accountIds[0], descriptionId: foodId,
          date: '${now.year}-${now.month.toString().padLeft(2, '0')}-05',
          amount: 80, transactionType: 'expense', currency: 'EUR');
      await seedTestTransaction(db, userId,
          accountId: accountIds[0], descriptionId: foodId,
          date: '${now.year}-${now.month.toString().padLeft(2, '0')}-15',
          amount: 120, transactionType: 'expense', currency: 'EUR');
      await seedTestTransaction(db, userId,
          accountId: accountIds[0], descriptionId: rentId,
          date: '${now.year}-${now.month.toString().padLeft(2, '0')}-01',
          amount: 1000, transactionType: 'expense', currency: 'EUR');

      final rows = await db.rawQuery('''
        SELECT LOWER(COALESCE(d.name, 'Uncategorized')) as category,
               SUM(t.amount) as amount,
               COALESCE(NULLIF(t.currency, ''), 'EUR') as currency
        FROM transactions t
        LEFT JOIN descriptions d ON t.description_id = d.id
        WHERE t.transaction_type = ? AND t.date >= ? AND t.date <= ? AND t.user_id = ?
        GROUP BY category, t.currency
        ORDER BY amount DESC
      ''', ['expense', startDate, endDate, userId]);

      expect(rows.length, 2);
      final foodRow = rows.firstWhere((r) => r['category'] == 'food');
      final rentRow = rows.firstWhere((r) => r['category'] == 'rent');
      expect(foodRow['amount'], 200.0);
      expect(rentRow['amount'], 1000.0);
    });
  });

  // =========================================================================
  // getRollingMonthDistribution
  // =========================================================================
  group('getRollingMonthDistribution SQL', () {
    test('returns empty when no transactions in window', () async {
      final now = DateTime.now();
      final endDate = now.toIso8601String().substring(0, 10);
      final startDate = now.subtract(const Duration(days: 30)).toIso8601String().substring(0, 10);

      final rows = await db.rawQuery('''
        SELECT LOWER(COALESCE(d.name, 'Uncategorized')) as category,
               SUM(t.amount) as amount,
               COALESCE(NULLIF(t.currency, ''), 'EUR') as currency
        FROM transactions t
        LEFT JOIN descriptions d ON t.description_id = d.id
        WHERE t.transaction_type = ? AND t.date >= ? AND t.date <= ? AND t.user_id = ?
        GROUP BY category, t.currency
        ORDER BY amount DESC
      ''', ['expense', startDate, endDate, userId]);

      expect(rows, isEmpty);
    });

    test('captures transactions within rolling window', () async {
      final now = DateTime.now();
      final endDate = now.toIso8601String().substring(0, 10);
      final startDate = now.subtract(const Duration(days: 30)).toIso8601String().substring(0, 10);

      final foodId = await seedTestDescription(db, userId, 'Food');
      await seedTestTransaction(db, userId,
          accountId: accountIds[0], descriptionId: foodId,
          date: startDate, amount: 25, transactionType: 'expense', currency: 'EUR');
      await seedTestTransaction(db, userId,
          accountId: accountIds[0], descriptionId: foodId,
          date: endDate, amount: 35, transactionType: 'expense', currency: 'EUR');

      final rows = await db.rawQuery('''
        SELECT LOWER(COALESCE(d.name, 'Uncategorized')) as category,
               SUM(t.amount) as amount,
               COALESCE(NULLIF(t.currency, ''), 'EUR') as currency
        FROM transactions t
        LEFT JOIN descriptions d ON t.description_id = d.id
        WHERE t.transaction_type = ? AND t.date >= ? AND t.date <= ? AND t.user_id = ?
        GROUP BY category, t.currency
        ORDER BY amount DESC
      ''', ['expense', startDate, endDate, userId]);

      expect(rows.length, 1);
      expect(rows[0]['amount'], 60.0);
    });

    test('excludes transactions outside the rolling window', () async {
      final now = DateTime.now();
      final endDate = now.toIso8601String().substring(0, 10);
      final startDate = now.subtract(const Duration(days: 30)).toIso8601String().substring(0, 10);

      final foodId = await seedTestDescription(db, userId, 'Food');
      final outsideDate = now.subtract(const Duration(days: 60)).toIso8601String().substring(0, 10);
      await seedTestTransaction(db, userId,
          accountId: accountIds[0], descriptionId: foodId,
          date: outsideDate, amount: 999, transactionType: 'expense', currency: 'EUR');

      final rows = await db.rawQuery('''
        SELECT LOWER(COALESCE(d.name, 'Uncategorized')) as category,
               SUM(t.amount) as amount,
               COALESCE(NULLIF(t.currency, ''), 'EUR') as currency
        FROM transactions t
        LEFT JOIN descriptions d ON t.description_id = d.id
        WHERE t.transaction_type = ? AND t.date >= ? AND t.date <= ? AND t.user_id = ?
        GROUP BY category, t.currency
        ORDER BY amount DESC
      ''', ['expense', startDate, endDate, userId]);

      expect(rows, isEmpty);
    });
  });

  // =========================================================================
  // getPreviousMonthTotal
  // =========================================================================
  group('getPreviousMonthTotal SQL', () {
    test('returns 0 when no transactions in previous month', () async {
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
      ''', [startDate, endDate, userId]);

      final total = (result.first['total'] as num?)?.toDouble() ?? 0.0;
      expect(total, 0.0);
    });

    test('calculates net total for previous calendar month', () async {
      final now = DateTime.now();
      final previousMonth = DateTime(now.year, now.month - 1, 1);
      final startDate = previousMonth.toIso8601String().substring(0, 10);
      final endMonth = DateTime(now.year, now.month, 1);
      final endDate = endMonth.toIso8601String().substring(0, 10);

      final descId = await seedTestDescription(db, userId, 'Income');
      final prevYear = previousMonth.year;
      final prevMonthNum = previousMonth.month;
      await seedTestTransaction(db, userId,
          accountId: accountIds[0], descriptionId: descId,
          date: '$prevYear-${prevMonthNum.toString().padLeft(2, '0')}-05',
          amount: 3000, transactionType: 'income', currency: 'EUR');
      await seedTestTransaction(db, userId,
          accountId: accountIds[0], descriptionId: descId,
          date: '$prevYear-${prevMonthNum.toString().padLeft(2, '0')}-15',
          amount: 800, transactionType: 'expense', currency: 'EUR');

      final result = await db.rawQuery('''
        SELECT COALESCE(SUM(CASE WHEN transaction_type = 'income' THEN amount
                                 WHEN transaction_type = 'expense' THEN -amount
                                 ELSE 0 END), 0) as total
        FROM transactions
        WHERE date >= ? AND date < ? AND user_id = ?
      ''', [startDate, endDate, userId]);

      final total = (result.first['total'] as num?)?.toDouble() ?? 0.0;
      expect(total, 2200.0);
    });

    test('excludes current month transactions', () async {
      final now = DateTime.now();
      final previousMonth = DateTime(now.year, now.month - 1, 1);
      final startDate = previousMonth.toIso8601String().substring(0, 10);
      final endMonth = DateTime(now.year, now.month, 1);
      final endDate = endMonth.toIso8601String().substring(0, 10);

      final descId = await seedTestDescription(db, userId, 'Income');
      await seedTestTransaction(db, userId,
          accountId: accountIds[0], descriptionId: descId,
          date: '${now.year}-${now.month.toString().padLeft(2, '0')}-01',
          amount: 99999, transactionType: 'income', currency: 'EUR');

      final result = await db.rawQuery('''
        SELECT COALESCE(SUM(CASE WHEN transaction_type = 'income' THEN amount
                                 WHEN transaction_type = 'expense' THEN -amount
                                 ELSE 0 END), 0) as total
        FROM transactions
        WHERE date >= ? AND date < ? AND user_id = ?
      ''', [startDate, endDate, userId]);

      final total = (result.first['total'] as num?)?.toDouble() ?? 0.0;
      expect(total, 0.0);
    });
  });

  // =========================================================================
  // Cross-cutting concerns: transfer descriptions filtering
  // =========================================================================
  group('Transfer description filtering', () {
    test('transfer descriptions are filtered out in category distribution', () async {
      final now = DateTime.now();
      final startDate = now.subtract(const Duration(days: 180)).toIso8601String().substring(0, 10);
      final endDate = now.toIso8601String().substring(0, 10);
      final txnDate = DateTime(now.year, now.month, 5).toIso8601String().substring(0, 10);

      final foodId = await seedTestDescription(db, userId, 'Food');
      final transferId = await seedTestDescription(db, userId, 'Transfer to Savings');
      await seedTestTransaction(db, userId,
          accountId: accountIds[0], descriptionId: foodId,
          date: txnDate, amount: 50, transactionType: 'expense', currency: 'EUR');
      await seedTestTransaction(db, userId,
          accountId: accountIds[0], descriptionId: transferId,
          date: txnDate, amount: 500, transactionType: 'transfer', currency: 'EUR');

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
      ''', ['expense', startDate, endDate, userId]);

      // Apply transfer filter
      bool isTransfer(String? description) {
        final desc = (description ?? '').trim().toLowerCase();
        return desc.startsWith('transfer to ') || desc.startsWith('transfer from ');
      }

      final filtered = rows.where((r) => !isTransfer(r['description'] as String?)).toList();
      expect(filtered.length, 1);
      expect(filtered[0]['description'], 'food');
    });

    test('transfer descriptions are filtered out in cash flow', () async {
      final now = DateTime.now();
      final startDate = DateTime(now.year, now.month - 2, 1)
          .toIso8601String()
          .substring(0, 10);

      final incomeId = await seedTestDescription(db, userId, 'Salary');
      final transferToId = await seedTestDescription(db, userId, 'Transfer to Savings');
      final transferFromId = await seedTestDescription(db, userId, 'Transfer from Checking');
      await seedTestTransaction(db, userId,
          accountId: accountIds[0], descriptionId: incomeId,
          date: '${now.year}-${now.month.toString().padLeft(2, '0')}-01',
          amount: 2000, transactionType: 'income', currency: 'EUR');
      await seedTestTransaction(db, userId,
          accountId: accountIds[0], descriptionId: transferToId,
          date: '${now.year}-${now.month.toString().padLeft(2, '0')}-02',
          amount: 500, transactionType: 'transfer', currency: 'EUR');
      await seedTestTransaction(db, userId,
          accountId: accountIds[1], descriptionId: transferFromId,
          date: '${now.year}-${now.month.toString().padLeft(2, '0')}-03',
          amount: 500, transactionType: 'transfer', currency: 'EUR');

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
      ''', [startDate, userId]);

      final currentMonthKey = '${now.year}-${now.month.toString().padLeft(2, '0')}';
      final monthRows = rows.where((r) => r['month'] == currentMonthKey).toList();
      final totalAmount = monthRows.fold<double>(0.0, (sum, r) {
        return sum + ((r['amount'] as num?)?.toDouble() ?? 0.0);
      });
      expect(totalAmount, 2000.0);
    });
  });

  // =========================================================================
  // Multi-currency aggregation
  // =========================================================================
  group('Multi-currency aggregation', () {
    test('total patrimony groups by currency correctly', () async {
      final descId = await seedTestDescription(db, userId, 'Income');
      await seedTestTransaction(db, userId,
          accountId: accountIds[0], descriptionId: descId,
          date: '2025-06-01', amount: 1000, transactionType: 'income', currency: 'EUR');
      await seedTestTransaction(db, userId,
          accountId: accountIds[0], descriptionId: descId,
          date: '2025-06-02', amount: 500, transactionType: 'income', currency: 'USD');
      await seedTestTransaction(db, userId,
          accountId: accountIds[0], descriptionId: descId,
          date: '2025-06-03', amount: 200, transactionType: 'expense', currency: 'EUR');

      final result = await db.rawQuery('''
        SELECT COALESCE(SUM(CASE WHEN t.transaction_type = 'income' THEN t.amount
                                 WHEN t.transaction_type = 'expense' THEN -t.amount
                                 ELSE 0 END), 0) as total,
               COALESCE(NULLIF(t.currency, ''), 'EUR') as currency
        FROM transactions t WHERE t.user_id = ?
        GROUP BY currency
      ''', [userId]);

      expect(result.length, 2);
      final eurRow = result.firstWhere((r) => r['currency'] == 'EUR');
      final usdRow = result.firstWhere((r) => r['currency'] == 'USD');
      expect(eurRow['total'], 800.0);
      expect(usdRow['total'], 500.0);
    });

    test('accounts distribution groups by account currency', () async {
      final descId = await seedTestDescription(db, userId, 'Income');
      await seedTestTransaction(db, userId,
          accountId: accountIds[0], descriptionId: descId,
          date: '2025-06-01', amount: 1000, transactionType: 'income', currency: 'EUR');
      await seedTestTransaction(db, userId,
          accountId: accountIds[0], descriptionId: descId,
          date: '2025-06-02', amount: 200, transactionType: 'expense', currency: 'EUR');

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
      ''', [userId, userId]);

      final checking = rows.firstWhere((r) => r['name'] == 'Checking Account');
      expect(checking['balance'], 800.0);
      expect(checking['account_currency'], 'EUR');
    });
  });

  // =========================================================================
  // Edge cases
  // =========================================================================
  group('Edge cases', () {
    test('transactions with null account_id are included in patrimony', () async {
      final descId = await seedTestDescription(db, userId, 'Cash');
      await seedTestTransaction(db, userId,
          accountId: null, descriptionId: descId,
          date: '2025-06-01', amount: 500, transactionType: 'income', currency: 'EUR');

      final result = await db.rawQuery('''
        SELECT COALESCE(SUM(CASE WHEN t.transaction_type = 'income' THEN t.amount
                                 WHEN t.transaction_type = 'expense' THEN -t.amount
                                 ELSE 0 END), 0) as total,
               COALESCE(NULLIF(t.currency, ''), 'EUR') as currency
        FROM transactions t WHERE t.user_id = ?
        GROUP BY currency
      ''', [userId]);

      final total = result.fold<double>(0.0, (sum, row) {
        return sum + ((row['total'] as num?)?.toDouble() ?? 0.0);
      });
      expect(total, 500.0);
    });

    test('null account_id transactions are included in checking balance', () async {
      final descId = await seedTestDescription(db, userId, 'Cash');
      await seedTestTransaction(db, userId,
          accountId: null, descriptionId: descId,
          date: '2025-06-01', amount: 300, transactionType: 'income', currency: 'EUR');

      final rows = await db.rawQuery('''
        SELECT COALESCE(SUM(CASE WHEN t.transaction_type = 'income' THEN t.amount
                                 WHEN t.transaction_type = 'expense' THEN -t.amount
                                 ELSE 0 END), 0) as total,
               COALESCE(NULLIF(a.currency, ''), 'EUR') as currency
        FROM transactions t
        LEFT JOIN accounts a ON t.account_id = a.id
        WHERE (a.type = 'checking' OR t.account_id IS NULL) AND t.user_id = ?
        GROUP BY a.currency
      ''', [userId]);

      final total = rows.fold<double>(0.0, (sum, row) {
        return sum + ((row['total'] as num?)?.toDouble() ?? 0.0);
      });
      expect(total, 300.0);
    });

    test('empty currency defaults to EUR', () async {
      final descId = await seedTestDescription(db, userId, 'Cash');
      await seedTestTransaction(db, userId,
          accountId: null, descriptionId: descId,
          date: '2025-06-01', amount: 100, transactionType: 'income', currency: '');

      final result = await db.rawQuery('''
        SELECT COALESCE(SUM(CASE WHEN t.transaction_type = 'income' THEN t.amount
                                 WHEN t.transaction_type = 'expense' THEN -t.amount
                                 ELSE 0 END), 0) as total,
               COALESCE(NULLIF(t.currency, ''), 'EUR') as currency
        FROM transactions t WHERE t.user_id = ?
        GROUP BY currency
      ''', [userId]);

      expect(result.length, 1);
      expect(result.first['currency'], 'EUR');
    });

    test('multiple transactions on same date are aggregated', () async {
      final descId = await seedTestDescription(db, userId, 'Food');
      await seedTestTransaction(db, userId,
          accountId: accountIds[0], descriptionId: descId,
          date: '2025-06-15', amount: 10, transactionType: 'expense', currency: 'EUR');
      await seedTestTransaction(db, userId,
          accountId: accountIds[0], descriptionId: descId,
          date: '2025-06-15', amount: 20, transactionType: 'expense', currency: 'EUR');
      await seedTestTransaction(db, userId,
          accountId: accountIds[0], descriptionId: descId,
          date: '2025-06-15', amount: 30, transactionType: 'expense', currency: 'EUR');

      final rows = await db.rawQuery('''
        SELECT LOWER(COALESCE(d.name, 'Uncategorized')) as category,
               SUM(t.amount) as amount,
               COALESCE(NULLIF(t.currency, ''), 'EUR') as currency
        FROM transactions t
        LEFT JOIN descriptions d ON t.description_id = d.id
        WHERE t.transaction_type = ? AND t.date >= ? AND t.date <= ? AND t.user_id = ?
        GROUP BY category, t.currency
        ORDER BY amount DESC
      ''', ['expense', '2025-06-01', '2025-06-30', userId]);

      expect(rows.length, 1);
      expect(rows[0]['amount'], 60.0);
    });
  });

  // =========================================================================
  // Full scenario: income, expenses, savings across multiple months
  // =========================================================================
  group('Full scenario tests', () {
    test('complex multi-month scenario with all statistics queries', () async {
      final descIncome = await seedTestDescription(db, userId, 'Salary');
      final descFood = await seedTestDescription(db, userId, 'Food');
      final descRent = await seedTestDescription(db, userId, 'Rent');

      // Month 1 (March): income 3000, expense 1200+300=1500
      await seedTestTransaction(db, userId,
          accountId: accountIds[0], descriptionId: descIncome,
          date: '2025-03-01', amount: 3000, transactionType: 'income', currency: 'EUR');
      await seedTestTransaction(db, userId,
          accountId: accountIds[0], descriptionId: descRent,
          date: '2025-03-05', amount: 1200, transactionType: 'expense', currency: 'EUR');
      await seedTestTransaction(db, userId,
          accountId: accountIds[0], descriptionId: descFood,
          date: '2025-03-10', amount: 300, transactionType: 'expense', currency: 'EUR');

      // Month 2 (April): income 3000, expense 1200+400=1600
      await seedTestTransaction(db, userId,
          accountId: accountIds[0], descriptionId: descIncome,
          date: '2025-04-01', amount: 3000, transactionType: 'income', currency: 'EUR');
      await seedTestTransaction(db, userId,
          accountId: accountIds[0], descriptionId: descRent,
          date: '2025-04-05', amount: 1200, transactionType: 'expense', currency: 'EUR');
      await seedTestTransaction(db, userId,
          accountId: accountIds[0], descriptionId: descFood,
          date: '2025-04-10', amount: 400, transactionType: 'expense', currency: 'EUR');

      // Month 3 (May): income 3000, expense 1200+250=1450
      await seedTestTransaction(db, userId,
          accountId: accountIds[0], descriptionId: descIncome,
          date: '2025-05-01', amount: 3000, transactionType: 'income', currency: 'EUR');
      await seedTestTransaction(db, userId,
          accountId: accountIds[0], descriptionId: descRent,
          date: '2025-05-05', amount: 1200, transactionType: 'expense', currency: 'EUR');
      await seedTestTransaction(db, userId,
          accountId: accountIds[0], descriptionId: descFood,
          date: '2025-05-10', amount: 250, transactionType: 'expense', currency: 'EUR');

      // Month 4 (June): income 3000, expense 1200+500=1700
      await seedTestTransaction(db, userId,
          accountId: accountIds[0], descriptionId: descIncome,
          date: '2025-06-01', amount: 3000, transactionType: 'income', currency: 'EUR');
      await seedTestTransaction(db, userId,
          accountId: accountIds[0], descriptionId: descRent,
          date: '2025-06-05', amount: 1200, transactionType: 'expense', currency: 'EUR');
      await seedTestTransaction(db, userId,
          accountId: accountIds[0], descriptionId: descFood,
          date: '2025-06-15', amount: 500, transactionType: 'expense', currency: 'EUR');

      // --- Test getTotalPatrimony ---
      final patrimonyResult = await db.rawQuery('''
        SELECT COALESCE(SUM(CASE WHEN t.transaction_type = 'income' THEN t.amount
                                 WHEN t.transaction_type = 'expense' THEN -t.amount
                                 ELSE 0 END), 0) as total,
               COALESCE(NULLIF(t.currency, ''), 'EUR') as currency
        FROM transactions t WHERE t.user_id = ?
        GROUP BY currency
      ''', [userId]);
      final totalPatrimony = patrimonyResult.fold<double>(0.0, (sum, row) {
        return sum + ((row['total'] as num?)?.toDouble() ?? 0.0);
      });
      // 12000 income - 6250 expenses = 5750
      expect(totalPatrimony, 5750.0);

      // --- Test getBalance (checking only) ---
      final balanceRows = await db.rawQuery('''
        SELECT COALESCE(SUM(CASE WHEN t.transaction_type = 'income' THEN t.amount
                                 WHEN t.transaction_type = 'expense' THEN -t.amount
                                 ELSE 0 END), 0) as total,
               COALESCE(NULLIF(a.currency, ''), 'EUR') as currency
        FROM transactions t
        LEFT JOIN accounts a ON t.account_id = a.id
        WHERE (a.type = 'checking' OR t.account_id IS NULL) AND t.user_id = ?
        GROUP BY a.currency
      ''', [userId]);
      final balance = balanceRows.fold<double>(0.0, (sum, row) {
        return sum + ((row['total'] as num?)?.toDouble() ?? 0.0);
      });
      expect(balance, 5750.0);

      // --- Test getHistoryPatrimony (before May) ---
      final historyPatResult = await db.rawQuery('''
        SELECT COALESCE(SUM(CASE WHEN t.transaction_type = 'income' THEN t.amount
                                 WHEN t.transaction_type = 'expense' THEN -t.amount
                                 ELSE 0 END), 0) as total,
               COALESCE(NULLIF(t.currency, ''), 'EUR') as currency
        FROM transactions t WHERE t.date < ? AND t.user_id = ?
        GROUP BY currency
      ''', ['2025-05-01', userId]);
      final historyPatrimony = historyPatResult.fold<double>(0.0, (sum, row) {
        return sum + ((row['total'] as num?)?.toDouble() ?? 0.0);
      });
      // March + April: (3000-1500) + (3000-1600) = 1500 + 1400 = 2900
      expect(historyPatrimony, 2900.0);

      // --- Test getMonthlySummary for April ---
      final aprStart = '2025-04-01';
      final aprEnd = '2025-05-01';
      final aprRows = await db.rawQuery('''
        SELECT
          COALESCE(SUM(CASE WHEN t.transaction_type = 'income' THEN t.amount ELSE 0 END), 0) as income,
          COALESCE(SUM(CASE WHEN t.transaction_type = 'expense' THEN t.amount ELSE 0 END), 0) as expenses,
          COALESCE(NULLIF(a.currency, ''), 'EUR') as currency
        FROM transactions t
        LEFT JOIN accounts a ON t.account_id = a.id
        WHERE (t.date >= ? AND t.date < ?) AND (a.type = 'checking' OR t.account_id IS NULL) AND t.user_id = ?
        GROUP BY a.currency
      ''', [aprStart, aprEnd, userId]);
      double aprIncome = 0.0;
      double aprExpenses = 0.0;
      for (final row in aprRows) {
        aprIncome += (row['income'] as num?)?.toDouble() ?? 0.0;
        aprExpenses += (row['expenses'] as num?)?.toDouble() ?? 0.0;
      }
      expect(aprIncome, 3000.0);
      expect(aprExpenses, 1600.0);
      expect(aprIncome - aprExpenses, 1400.0);

      // --- Test getMonthlyChartData for 2025 ---
      final chartRows = await db.rawQuery('''
        SELECT strftime('%m', t.date) as month,
               COALESCE(SUM(CASE WHEN t.transaction_type = 'income' THEN t.amount ELSE 0 END), 0) as income,
               COALESCE(SUM(CASE WHEN t.transaction_type = 'expense' THEN t.amount ELSE 0 END), 0) as expenses
        FROM transactions t
        LEFT JOIN accounts a ON t.account_id = a.id
        WHERE strftime('%Y', t.date) = ? AND (a.type = 'checking' OR t.account_id IS NULL) AND t.user_id = ?
        GROUP BY month
        ORDER BY month
      ''', ['2025', userId]);
      expect(chartRows.length, 4);
      final marchChart = chartRows.firstWhere((r) => r['month'] == '03');
      expect(marchChart['income'], 3000.0);
      expect(marchChart['expenses'], 1500.0);

      // --- Test getTopDescriptions ---
      final topRows = await db.rawQuery('''
        SELECT LOWER(COALESCE(d.name, 'Uncategorized')) as desc,
               SUM(t.amount) as total,
               COUNT(t.id) as count
        FROM transactions t
        LEFT JOIN descriptions d ON t.description_id = d.id
        WHERE t.transaction_type = ? AND t.date >= ? AND t.date <= ? AND t.user_id = ?
        GROUP BY desc
        HAVING count >= ?
        ORDER BY total DESC
      ''', ['expense', '2025-01-01', '2025-12-31', userId, 1]);
      expect(topRows.isNotEmpty, true);
      // Rent: 4800 total, Food: 1450 total
      expect(topRows[0]['desc'], 'rent');
      expect(topRows[1]['desc'], 'food');
    });
  });
}
