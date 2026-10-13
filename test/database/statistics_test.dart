import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:peadra/core/database/database_manager.dart';

void main() {
  sqfliteFfiInit();

  late DatabaseManager db;
  late String checkingId;
  late String savingsAId;
  late String savingsBId;

  String today() => DateTime.now().toIso8601String().substring(0, 10);

  setUp(() async {
    db = DatabaseManager.instance;
    db.clearEncryptionKey();
    await db.openInMemoryForTest(
        userId: 'user-${DateTime.now().microsecondsSinceEpoch}');
    checkingId =
        (await db.addAccount('Checking Account', '#4CAF50', 'checking', 'EUR'))!;
    savingsAId =
        (await db.addAccount('Savings Account A', '#2196F3', 'savings', 'EUR'))!;
    savingsBId =
        (await db.addAccount('Savings Account B', '#009688', 'savings', 'EUR'))!;
  });

  // Concise seed helpers over the production addTransaction API.
  Future<void> cTxn(String date, String description, int amount, String type,
      {String? tagId}) {
    return db
        .addTransaction(
          date: date,
          description: description,
          amount: Decimal.fromInt(amount),
          transactionType: type,
          accountId: checkingId,
          tagId: tagId,
        )
        .then((_) {});
  }

  Future<void> sATxn(String date, String description, int amount, String type,
      {String? tagId}) {
    return db
        .addTransaction(
          date: date,
          description: description,
          amount: Decimal.fromInt(amount),
          transactionType: type,
          accountId: savingsAId,
          tagId: tagId,
        )
        .then((_) {});
  }

  Future<void> oTxn(String date, String description, int amount, String type) {
    return db
        .addTransaction(
          date: date,
          description: description,
          amount: Decimal.fromInt(amount),
          transactionType: type,
        )
        .then((_) {});
  }

  /// Seeds a USD->EUR rate directly in the prod rates table.
  /// LAST-RESORT raw SQL (flagged): production offers no offline API to set
  /// rates (only network fetchExchangeRates), and getExchangeRate recurses
  /// forever on an empty table for cross-currency pairs, so conversion tests
  /// must pre-seed exactly one rate row.
  Future<void> seedUsdEurRate() async {
    final crdt = await db.database;
    await crdt.execute(
      'INSERT OR REPLACE INTO exchange_rates '
      '(from_currency, to_currency, rate, updated_at) VALUES (?1, ?2, ?3, ?4)',
      ['USD', 'EUR', 0.9, today()],
    );
  }

  /// Production has no getHistoryPatrimony; the closest is
  /// getAccountsDistribution(endDate:) summed across accounts.
  /// [exclusiveDate] is exclusive (mirrors `date < ?`); converted via the
  /// day-before date because the prod API is `date <= endDate`.
  Future<Decimal> patrimonyBefore(String exclusiveDate) async {
    final inclusive = DateTime.parse(exclusiveDate)
        .subtract(const Duration(days: 1))
        .toIso8601String()
        .substring(0, 10);
    final dist = await db.getAccountsDistribution(endDate: inclusive);
    var total = Decimal.zero;
    for (final row in dist) {
      total += Decimal.parse((row['value'] as double).toString());
    }
    return total;
  }

  // =========================================================================
  // getTotalPatrimony
  // =========================================================================
  group('getTotalPatrimony', () {
    test('returns 0 when no transactions exist', () async {
      expect(await db.getTotalPatrimony(), Decimal.zero);
    });

    test('calculates total across all accounts with same currency', () async {
      await cTxn('2025-06-01', 'Salary', 3000, 'income');
      await sATxn('2025-06-05', 'Salary', 500, 'income');
      await cTxn('2025-06-10', 'Salary', 200, 'expense');

      expect(await db.getTotalPatrimony(), Decimal.fromInt(3300));
    });

    test('groups by currency correctly', () async {
      // Production converts to a single target currency (no per-currency
      // grouping API); per-currency intent is covered via
      // getAccountsDistribution below, converted total asserted here.
      await seedUsdEurRate();
      final usdId =
          (await db.addAccount('USD Account', '#FF9800', 'checking', 'USD'))!;
      await cTxn('2025-06-01', 'Food', 1000, 'income');
      await db.addTransaction(
        date: '2025-06-02',
        description: 'Food',
        amount: Decimal.fromInt(500),
        transactionType: 'income',
        accountId: usdId,
      );

      final dist = await db.getAccountsDistribution();
      final eurRow =
          dist.firstWhere((r) => r['currency'] == 'EUR' && r['name'] == 'Checking Account');
      final usdRow = dist.firstWhere((r) => r['currency'] == 'USD');
      expect(eurRow['nativeValue'], 1000.0);
      expect(usdRow['nativeValue'], 500.0);
      // Seeded USD->EUR 0.9 conversion: 1000 + 500*0.9.
      expect(await db.getTotalPatrimony(), Decimal.fromInt(1450));
    });

    test('treats transfer as 0 in calculation', () async {
      await cTxn('2025-06-01', 'Transfer', 500, 'transfer');
      await cTxn('2025-06-02', 'Salary', 1000, 'income');

      expect(await db.getTotalPatrimony(), Decimal.fromInt(1000));
    });
  });

  // =========================================================================
  // getBalance (checking accounts only)
  // =========================================================================
  group('getBalance', () {
    test('returns 0 when no transactions exist', () async {
      expect(await db.getBalance(), Decimal.zero);
    });

    test('only counts checking account transactions', () async {
      await cTxn('2025-06-01', 'Income', 2000, 'income');
      await sATxn('2025-06-02', 'Income', 5000, 'income');

      expect(await db.getBalance(), Decimal.fromInt(2000));
    });

    test('orphan transactions without account are excluded (prod behavior)',
        () async {
      // GAP: legacy inline SQL counted `t.account_id IS NULL` orphans in the
      // checking balance; production getBalance only sums rows whose joined
      // account type is 'checking', so orphans are excluded.
      await oTxn('2025-06-01', 'Cash', 300, 'income');

      expect(await db.getBalance(), Decimal.zero);
    });

    test('subtracts expenses from checking balance', () async {
      await cTxn('2025-06-01', 'Shopping', 1000, 'income');
      await cTxn('2025-06-05', 'Shopping', 400, 'expense');

      expect(await db.getBalance(), Decimal.fromInt(600));
    });

    test('only includes checking transactions strictly before the date limit',
        () async {
      await cTxn('2025-05-31', 'Salary', 1000, 'income');
      await cTxn('2025-06-01', 'Salary', 2000, 'income');

      expect(
          await db.getBalance(before: '2025-06-01'), Decimal.fromInt(1000));
    });
  });

  // =========================================================================
  // getSavingsTotal (savings accounts only)
  // =========================================================================
  group('getSavingsTotal', () {
    test('returns 0 when no transactions exist', () async {
      expect(await db.getSavingsTotal(), Decimal.zero);
    });

    test('only counts savings account transactions', () async {
      await cTxn('2025-06-01', 'Deposit', 2000, 'income');
      await sATxn('2025-06-02', 'Deposit', 5000, 'income');

      expect(await db.getSavingsTotal(), Decimal.fromInt(5000));
    });

    test('combines both savings accounts', () async {
      await sATxn('2025-06-01', 'Interest', 100, 'income');
      await db.addTransaction(
        date: '2025-06-02',
        description: 'Interest',
        amount: Decimal.fromInt(200),
        transactionType: 'income',
        accountId: savingsBId,
      );

      expect(await db.getSavingsTotal(), Decimal.fromInt(300));
    });
  });

  // =========================================================================
  // getHistoryPatrimony -> getAccountsDistribution(endDate:) sum
  // =========================================================================
  group('getHistoryPatrimony', () {
    test('returns 0 when no transactions before date limit', () async {
      expect(await patrimonyBefore('2025-01-01'), Decimal.zero);
    });

    test('only includes transactions strictly before the date limit',
        () async {
      await cTxn('2025-05-31', 'Salary', 1000, 'income');
      await cTxn('2025-06-01', 'Salary', 2000, 'income');

      expect(await patrimonyBefore('2025-06-01'), Decimal.fromInt(1000));
    });

    test('includes expenses as negatives in history', () async {
      await cTxn('2025-03-01', 'Rent', 3000, 'income');
      await cTxn('2025-04-01', 'Rent', 1500, 'expense');

      expect(await patrimonyBefore('2025-05-01'), Decimal.fromInt(1500));
    });
  });

  // =========================================================================
  // getHistoryBalance (checking only, before date) -> getBalance(before:)
  // =========================================================================
  group('getHistoryBalance', () {
    test('returns 0 when no transactions', () async {
      expect(await db.getBalance(before: '2025-06-01'), Decimal.zero);
    });

    test('only includes checking account transactions before date', () async {
      await cTxn('2025-05-01', 'Income', 1000, 'income');
      await sATxn('2025-05-01', 'Income', 5000, 'income');

      expect(
          await db.getBalance(before: '2025-06-01'), Decimal.fromInt(1000));
    });
  });

  // =========================================================================
  // getHistorySavings (savings only, before date) -> getSavingsTotal(before:)
  // =========================================================================
  group('getHistorySavings', () {
    test('returns 0 when no transactions', () async {
      expect(await db.getSavingsTotal(before: '2025-06-01'), Decimal.zero);
    });

    test('only includes savings account transactions before date', () async {
      await cTxn('2025-05-01', 'Deposit', 1000, 'income');
      await sATxn('2025-05-01', 'Deposit', 5000, 'income');

      expect(await db.getSavingsTotal(before: '2025-06-01'),
          Decimal.fromInt(5000));
    });
  });

  // =========================================================================
  // getMonthlySummary
  // =========================================================================
  group('getMonthlySummary', () {
    test('returns zero map when no transactions in month', () async {
      final summary = await db.getMonthlySummary(year: 2025, month: 6);
      expect(summary['income'], Decimal.zero);
      expect(summary['expenses'], Decimal.zero);
      expect(summary['balance'], Decimal.zero);
    });

    test('calculates income and expenses for a specific month', () async {
      // In June
      await cTxn('2025-06-01', 'Food', 3000, 'income');
      await cTxn('2025-06-15', 'Food', 800, 'expense');
      // In July (should not count)
      await cTxn('2025-07-01', 'Food', 1000, 'income');

      final summary = await db.getMonthlySummary(year: 2025, month: 6);
      expect(summary['income'], Decimal.fromInt(3000));
      expect(summary['expenses'], Decimal.fromInt(800));
      expect(summary['balance'], Decimal.fromInt(2200));
    });

    test('excludes savings accounts from monthly summary', () async {
      await cTxn('2025-06-01', 'Deposit', 1000, 'income');
      await sATxn('2025-06-01', 'Deposit', 5000, 'income');

      final summary = await db.getMonthlySummary(year: 2025, month: 6);
      expect(summary['income'], Decimal.fromInt(1000));
    });
  });

  // =========================================================================
  // getRollingSummary
  // =========================================================================
  group('getRollingSummary', () {
    test('returns zeros when no transactions in window', () async {
      final summary = await db.getRollingSummary();
      expect(summary['income'], Decimal.zero);
      expect(summary['expenses'], Decimal.zero);
    });

    test('captures transactions within the rolling window', () async {
      final now = DateTime.now();
      final endDate = now.toIso8601String().substring(0, 10);
      final startDate =
          now.subtract(const Duration(days: 30)).toIso8601String().substring(0, 10);

      await cTxn(startDate, 'Lunch', 150, 'expense');
      await cTxn(endDate, 'Lunch', 500, 'income');

      final summary = await db.getRollingSummary();
      expect(summary['income'], Decimal.fromInt(500));
      expect(summary['expenses'], Decimal.fromInt(150));
    });

    test('excludes transactions outside the rolling window', () async {
      final now = DateTime.now();
      final outsideDate = now
          .subtract(const Duration(days: 60))
          .toIso8601String()
          .substring(0, 10);
      await cTxn(outsideDate, 'Old Purchase', 9999, 'income');

      final summary = await db.getRollingSummary();
      expect(summary['income'], Decimal.zero);
    });
  });

  // =========================================================================
  // getAccountsDistribution
  // =========================================================================
  group('getAccountsDistribution', () {
    test('returns all accounts with zero balance when no transactions',
        () async {
      final rows = await db.getAccountsDistribution();
      expect(rows.length, 3);
      for (final row in rows) {
        expect(row['value'], 0.0);
      }
    });

    test('calculates per-account balances correctly', () async {
      await cTxn('2025-06-01', 'Income', 2000, 'income');
      await cTxn('2025-06-02', 'Income', 500, 'expense');
      await sATxn('2025-06-03', 'Income', 10000, 'income');

      final rows = await db.getAccountsDistribution();
      final checking =
          rows.firstWhere((r) => r['name'] == 'Checking Account');
      final savingsA =
          rows.firstWhere((r) => r['name'] == 'Savings Account A');
      final savingsB =
          rows.firstWhere((r) => r['name'] == 'Savings Account B');

      expect(checking['value'], 1500.0);
      expect(savingsA['value'], 10000.0);
      expect(savingsB['value'], 0.0);
    });

    test('orders accounts by name', () async {
      final rows = await db.getAccountsDistribution();
      final names = rows.map((r) => r['name'] as String).toList();
      expect(names,
          ['Checking Account', 'Savings Account A', 'Savings Account B']);
    });
  });

  // =========================================================================
  // getCategoryDistribution -> getDescriptionMonthlyData / getTopDescriptions
  // (no dedicated prod method; closest coverage)
  // =========================================================================
  group('getCategoryDistribution', () {
    test('returns empty when no transactions', () async {
      expect(await db.getTopDescriptions(), isEmpty);
    });

    test('groups expenses by category and month', () async {
      final now = DateTime.now();
      final startDate = now
          .subtract(const Duration(days: 180))
          .toIso8601String()
          .substring(0, 10);
      final endDate = now.toIso8601String().substring(0, 10);
      final monthKey = endDate.substring(0, 7);

      // Keep all dates within the current month so the transactions always
      // fall into a single month bucket regardless of today's day of month.
      String currentMonthDate(int daysAgo) {
        final dt = now.subtract(Duration(days: daysAgo));
        final clamped = dt.isBefore(DateTime(now.year, now.month, 1))
            ? DateTime(now.year, now.month, 1)
            : dt;
        return clamped.toIso8601String().substring(0, 10);
      }

      await cTxn(currentMonthDate(3), 'Food', 50, 'expense');
      await cTxn(currentMonthDate(2), 'Food', 75, 'expense');
      await cTxn(currentMonthDate(1), 'Rent', 1200, 'expense');

      final data =
          await db.getDescriptionMonthlyData(startDate, endDate);
      expect(data.length, 2);
      expect(data['Food']![monthKey]!['expense'], 125.0);
      expect(data['Rent']![monthKey]!['expense'], 1200.0);
    });

    test('limits results to top N categories', () async {
      final txnDate = DateTime.now()
          .subtract(const Duration(days: 10))
          .toIso8601String()
          .substring(0, 10);

      await cTxn(txnDate, 'Food', 100, 'expense');
      await cTxn(txnDate, 'Rent', 500, 'expense');
      await cTxn(txnDate, 'Transport', 200, 'expense');
      await cTxn(txnDate, 'Entertainment', 300, 'expense');

      final top = await db.getTopDescriptions(limit: 2);
      expect(top.length, 2);
      final names = top.map((r) => r['description'] as String).toSet();
      expect(names, {'Rent', 'Entertainment'});
    });
  });

  // =========================================================================
  // getDescriptionMonthlyData
  // =========================================================================
  group('getDescriptionMonthlyData', () {
    test('returns empty map when no transactions', () async {
      final data =
          await db.getDescriptionMonthlyData('2025-01-01', '2025-12-31');
      expect(data, isEmpty);
    });

    test('builds description -> month -> type breakdown', () async {
      await cTxn('2025-06-01', 'Food', 50, 'expense');
      await cTxn('2025-06-15', 'Food', 75, 'expense');
      await cTxn('2025-07-01', 'Food', 100, 'expense');

      final result =
          await db.getDescriptionMonthlyData('2025-01-01', '2025-12-31');

      expect(result.containsKey('Food'), true);
      expect(result['Food']!['2025-06']!['expense'], 125.0);
      expect(result['Food']!['2025-06']!['total'], 125.0);
      expect(result['Food']!['2025-07']!['expense'], 100.0);
      expect(result['Food']!['2025-07']!['total'], 100.0);
    });
  });

  // =========================================================================
  // getTopDescriptions
  // =========================================================================
  group('getTopDescriptions', () {
    test('returns empty when no transactions', () async {
      expect(await db.getTopDescriptions(), isEmpty);
    });

    test('returns top descriptions ordered by total amount', () async {
      final txnDate = DateTime.now()
          .subtract(const Duration(days: 10))
          .toIso8601String()
          .substring(0, 10);

      await cTxn(txnDate, 'Cheap Item', 10, 'expense');
      await cTxn(txnDate, 'Expensive Item', 500, 'expense');
      await cTxn(txnDate, 'Medium Item', 100, 'expense');

      final rows = await db.getTopDescriptions();
      expect(rows.length, 3);
      expect(rows[0]['description'], 'Expensive Item');
      expect(rows[1]['description'], 'Medium Item');
      expect(rows[2]['description'], 'Cheap Item');
    });

    test('respects minCount filter', () async {
      final now = DateTime.now();
      final txnDate1 = now
          .subtract(const Duration(days: 10))
          .toIso8601String()
          .substring(0, 10);
      final txnDate2 =
          now.subtract(const Duration(days: 5)).toIso8601String().substring(0, 10);
      final txnDate3 =
          now.subtract(const Duration(days: 1)).toIso8601String().substring(0, 10);

      await cTxn(txnDate1, 'Single Purchase', 100, 'expense');
      await cTxn(txnDate1, 'Repeated Purchase', 50, 'expense');
      await cTxn(txnDate2, 'Repeated Purchase', 50, 'expense');
      await cTxn(txnDate3, 'Repeated Purchase', 50, 'expense');

      final rows = await db.getTopDescriptions(minCount: 2);
      expect(rows.length, 1);
      expect(rows[0]['description'], 'Repeated Purchase');
    });
  });

  // =========================================================================
  // getMonthlyChartData -> getCashFlowDataForRange (closest; no exact prod
  // method) + getMonthlySummary for the checking-only case
  // =========================================================================
  group('getMonthlyChartData', () {
    test('returns empty when no transactions', () async {
      final rows = await db.getCashFlowDataForRange(
          startDate: '2025-01-01', endDate: '2025-12-31');
      expect(rows, isEmpty);
    });

    test('groups income/expenses by month for a given year', () async {
      await cTxn('2025-03-10', 'Income', 2000, 'income');
      await cTxn('2025-03-15', 'Income', 300, 'expense');
      await cTxn('2025-05-20', 'Income', 2500, 'income');
      // Different year should not count
      await cTxn('2024-06-01', 'Income', 9999, 'income');

      final rows = await db.getCashFlowDataForRange(
          startDate: '2025-01-01', endDate: '2025-12-31');
      final byMonthType = <String, double>{};
      for (final r in rows) {
        byMonthType["${r['month']}/${r['type']}"] =
            (r['amount'] as double);
      }
      expect(byMonthType.keys.toSet(),
          {'2025-03/income', '2025-03/expense', '2025-05/income'});
      expect(byMonthType['2025-03/income'], 2000.0);
      expect(byMonthType['2025-03/expense'], 300.0);
      expect(byMonthType['2025-05/income'], 2500.0);
    });

    test('excludes savings accounts from monthly chart', () async {
      // GAP: prod cash-flow ranges include all accounts; the checking-only
      // monthly view is getMonthlySummary, used here.
      await cTxn('2025-06-01', 'Deposit', 1000, 'income');
      await sATxn('2025-06-01', 'Deposit', 5000, 'income');

      final summary = await db.getMonthlySummary(year: 2025, month: 6);
      expect(summary['income'], Decimal.fromInt(1000));
    });
  });

  // =========================================================================
  // getCashFlowData
  // =========================================================================
  group('getCashFlowData', () {
    test('returns empty when no transactions', () async {
      expect(await db.getCashFlowData(), isEmpty);
    });

    test('groups cash flow by month and type', () async {
      final now = DateTime.now();
      final monthKey =
          '${now.year}-${now.month.toString().padLeft(2, '0')}';

      await cTxn('$monthKey-01', 'Salary', 3000, 'income');
      await cTxn('$monthKey-05', 'Groceries', 500, 'expense');

      final rows = await db.getCashFlowData();
      expect(rows.isNotEmpty, true);
      final incomeRow = rows.firstWhere((r) =>
          r['month'] == monthKey && r['type'] == 'income');
      final expenseRow = rows.firstWhere((r) =>
          r['month'] == monthKey && r['type'] == 'expense');
      expect(incomeRow['amount'], 3000.0);
      expect(expenseRow['amount'], 500.0);
    });

    test('detects future months beyond today', () async {
      final now = DateTime.now();
      final futureDate = DateTime(now.year, now.month + 1, 10)
          .toIso8601String()
          .substring(0, 10);
      final futureMonthKey = futureDate.substring(0, 7);
      await cTxn(futureDate, 'Salary', 750, 'income');

      expect(await db.getFirstTransactionDate(), isNotNull);
      final rows = await db.getCashFlowData();
      final futureRows =
          rows.where((r) => r['month'] == futureMonthKey).toList();
      expect(futureRows.isNotEmpty, true);
      expect(futureRows.any((r) => r['isFuture'] == true), true);
      expect(
          futureRows
              .firstWhere((r) => r['type'] == 'income')['amount'],
          750.0);
    });

    test('future month bucket accumulates only future transactions', () async {
      final now = DateTime.now();
      final pastDate = DateTime(now.year, now.month - 1, 15)
          .toIso8601String()
          .substring(0, 10);
      final futureDate = DateTime(now.year, now.month + 1, 10)
          .toIso8601String()
          .substring(0, 10);
      final futureMonthKey = futureDate.substring(0, 7);
      final pastMonthKey = pastDate.substring(0, 7);
      await cTxn(pastDate, 'Salary', 3000, 'income');
      await cTxn(futureDate, 'Salary', 750, 'income');

      final rows = await db.getCashFlowData();
      final pastRow = rows.firstWhere(
          (r) => r['month'] == pastMonthKey && r['type'] == 'income');
      final futureRow = rows.firstWhere(
          (r) => r['month'] == futureMonthKey && r['type'] == 'income');
      expect(pastRow['amount'], 3000.0);
      expect(pastRow['futureAmount'], 0.0);
      expect(futureRow['amount'], 750.0);
      expect(futureRow['futureAmount'], 750.0);
    });

    test('splits same-month past and future portions', () async {
      final now = DateTime.now();
      final pastDate = now
          .subtract(const Duration(days: 2))
          .toIso8601String()
          .substring(0, 10);
      final futureDate =
          now.add(const Duration(days: 2)).toIso8601String().substring(0, 10);
      await cTxn(pastDate, 'Salary', 1000, 'income');
      await cTxn(futureDate, 'Salary', 250, 'income');

      final rows = await db.getCashFlowData();
      double past = 0.0;
      double future = 0.0;
      for (final r in rows) {
        if (r['type'] != 'income') continue;
        past += (r['amount'] as double) - (r['futureAmount'] as double);
        future += r['futureAmount'] as double;
      }
      expect(past, 1000.0);
      expect(future, 250.0);
    });

    test('excludes transfer descriptions from cash flow', () async {
      final now = DateTime.now();
      final monthKey =
          '${now.year}-${now.month.toString().padLeft(2, '0')}';

      await cTxn('$monthKey-01', 'Transfer to Savings', 1000, 'transfer');
      await sATxn('$monthKey-02', 'Transfer from Checking', 1000, 'transfer');
      await cTxn('$monthKey-03', 'Salary', 2000, 'income');

      final rows = await db.getCashFlowData();
      final monthRows =
          rows.where((r) => r['month'] == monthKey).toList();
      expect(monthRows.any((r) => r['type'] == 'transfer'), false);
      double total = 0.0;
      for (final r in monthRows) {
        total += r['amount'] as double;
      }
      expect(total, 2000.0);
    });
  });

  // =========================================================================
  // getAssetsHistory
  // =========================================================================
  group('getAssetsHistory', () {
    test('returns all zero months when no transactions', () async {
      final results = await db.getAssetsHistory(months: 3);
      expect(results.length, 3);
      expect(results.every((r) => r['value'] == 0.0), true);
    });

    test('accumulates transactions chronologically across months', () async {
      final now = DateTime.now();

      // Transaction 3 months ago
      final threeMonthsAgo = DateTime(now.year, now.month - 2, 1);
      await cTxn(
          threeMonthsAgo.toIso8601String().substring(0, 10), 'Income', 1000, 'income');

      // Transaction 1 month ago
      final oneMonthAgo = DateTime(now.year, now.month, 1);
      await cTxn(oneMonthAgo.toIso8601String().substring(0, 10), 'Income', 500,
          'income');

      final results = await db.getAssetsHistory(months: 3);
      expect(results.length, 3);
      final values =
          results.map((r) => r['value'] as double).toList();
      // Each subsequent month should have >= previous month's value (since we only add income)
      for (int i = 1; i < values.length; i++) {
        expect(values[i] >= values[i - 1], true);
      }
    });

    test('daily granularity yields one point per day with cumulative values',
        () async {
      final now = DateTime.now();

      // Both transactions within the window and always in the past.
      final incomeMonth = DateTime(now.year, now.month - 2, 1);
      final incomeDate = DateTime(incomeMonth.year, incomeMonth.month, 15)
          .toIso8601String()
          .substring(0, 10);
      final expenseDate = DateTime(incomeMonth.year, incomeMonth.month, 20)
          .toIso8601String()
          .substring(0, 10);

      await cTxn(incomeDate, 'Income', 500, 'income');
      await cTxn(expenseDate, 'Expense', 100, 'expense');

      // Daily window starts on the first of the earliest effective month (3 months ago
      // requested, but data only spans the last 2 full months + current month).
      final startDate = DateTime(now.year, now.month - 2, 1);
      final todayDate = DateTime(now.year, now.month, now.day);
      final totalDays = todayDate.difference(startDate).inDays + 1;

      final values = await db.getAssetsHistory(months: 3, granularity: 'daily');

      expect(values.length, totalDays);
      expect(values.first['value'], 0.0); // no transactions before the income date
      expect(values.last['value'], 400.0); // +500 income, -100 expense
    });
  });

  group('getAssetsHistory future forecast', () {
    test('detects future transactions beyond today', () async {
      final now = DateTime.now();
      final futureDate = DateTime(now.year, now.month + 1, 10)
          .toIso8601String()
          .substring(0, 10);
      await cTxn(futureDate, 'Income', 250, 'income');

      final results = await db.getAssetsHistory(months: 3);
      expect(results.any((r) => r['isFuture'] == true), true);
    });

    test('returns no future transactions when all dates are past', () async {
      await cTxn(today(), 'Income', 100, 'income');

      final results = await db.getAssetsHistory(months: 3);
      expect(results.any((r) => r['isFuture'] == true), false);
    });

    test('future bucket accumulates future transactions only', () async {
      final now = DateTime.now();
      final pastDate = DateTime(now.year, now.month - 1, 15)
          .toIso8601String()
          .substring(0, 10);
      final futureDate = DateTime(now.year, now.month + 1, 10)
          .toIso8601String()
          .substring(0, 10);
      await cTxn(pastDate, 'Income', 1000, 'income');
      await cTxn(futureDate, 'Income', 250, 'income');

      // Production always forecasts (no capped mode): the extended series
      // includes the future transaction.
      final results = await db.getAssetsHistory(months: 3);
      expect(results.last['value'], 1250.0);
      expect(results.last['isFuture'], true);
    });
  });

  // =========================================================================
  // getCurrentMonthDistribution
  // =========================================================================
  group('getCurrentMonthDistribution', () {
    test('returns empty when no transactions in current month', () async {
      final dist =
          await db.getCurrentMonthDistribution(transactionType: 'expense');
      expect(dist, isEmpty);
    });

    test('groups current month expenses by category', () async {
      final now = DateTime.now();

      String monthDate(int daysAgo) {
        final dt = now.subtract(Duration(days: daysAgo));
        final clamped = dt.isBefore(DateTime(now.year, now.month, 1))
            ? DateTime(now.year, now.month, 1)
            : dt;
        return clamped.toIso8601String().substring(0, 10);
      }

      await cTxn(monthDate(1), 'Food', 80, 'expense');
      await cTxn(now.toIso8601String().substring(0, 10), 'Food', 120, 'expense');
      await cTxn(monthDate(2), 'Rent', 1000, 'expense');

      final dist =
          await db.getCurrentMonthDistribution(transactionType: 'expense');
      expect(dist.length, 2);
      expect(dist['Food'], Decimal.fromInt(200));
      expect(dist['Rent'], Decimal.fromInt(1000));
    });
  });

  // =========================================================================
  // getRollingMonthDistribution
  // =========================================================================
  group('getRollingMonthDistribution', () {
    test('returns empty when no transactions in window', () async {
      final dist = await db.getRollingMonthDistribution(
          transactionType: 'expense');
      expect(dist, isEmpty);
    });

    test('captures transactions within rolling window', () async {
      final now = DateTime.now();
      final endDate = now.toIso8601String().substring(0, 10);
      final startDate =
          now.subtract(const Duration(days: 30)).toIso8601String().substring(0, 10);

      await cTxn(startDate, 'Food', 25, 'expense');
      await cTxn(endDate, 'Food', 35, 'expense');

      final dist = await db.getRollingMonthDistribution(
          transactionType: 'expense');
      expect(dist.length, 1);
      expect(dist['Food'], Decimal.fromInt(60));
    });

    test('excludes transactions outside the rolling window', () async {
      final now = DateTime.now();
      final outsideDate = now
          .subtract(const Duration(days: 60))
          .toIso8601String()
          .substring(0, 10);
      await cTxn(outsideDate, 'Food', 999, 'expense');

      final dist = await db.getRollingMonthDistribution(
          transactionType: 'expense');
      expect(dist, isEmpty);
    });
  });

  // =========================================================================
  // Tag description breakdown (pie drill-down) ->
  // getCurrentMonthTagDescriptionBreakdown
  // =========================================================================
  group('Tag description breakdown', () {
    test('returns only descriptions for the requested tag', () async {
      final endDate = today();
      final tagA = (await db.createTag(name: 'TagA'))!;
      final tagB = (await db.createTag(name: 'TagB'))!;

      await cTxn(endDate, 'Food', 80, 'expense', tagId: tagA);
      await cTxn(endDate, 'Rent', 120, 'expense', tagId: tagA);
      await cTxn(endDate, 'Food', 999, 'expense', tagId: tagB);

      final breakdown =
          await db.getCurrentMonthTagDescriptionBreakdown(
              transactionType: 'expense', tag: 'TagA');

      expect(breakdown.length, 2);
      expect(breakdown['Food'], Decimal.fromInt(80));
      expect(breakdown['Rent'], Decimal.fromInt(120));
    });

    test('excludes transfer descriptions from breakdown', () async {
      final endDate = today();
      final tagA = (await db.createTag(name: 'TagA'))!;

      await cTxn(endDate, 'Transfer to Savings', 500, 'expense', tagId: tagA);
      await cTxn(endDate, 'Food', 50, 'expense', tagId: tagA);

      final breakdown =
          await db.getCurrentMonthTagDescriptionBreakdown(
              transactionType: 'expense', tag: 'TagA');

      expect(breakdown.length, 1);
      expect(breakdown['Food'], Decimal.fromInt(50));
    });
  });

  // =========================================================================
  // getPreviousMonthTotal -> getMonthlySummary(previous month).balance
  // (no dedicated prod method; closest coverage)
  // =========================================================================
  group('getPreviousMonthTotal', () {
    test('returns 0 when no transactions in previous month', () async {
      final now = DateTime.now();
      final previousMonth = DateTime(now.year, now.month - 1, 1);

      final summary = await db.getMonthlySummary(
          year: previousMonth.year, month: previousMonth.month);
      expect(summary['balance'], Decimal.zero);
    });

    test('calculates net total for previous calendar month', () async {
      final now = DateTime.now();
      final previousMonth = DateTime(now.year, now.month - 1, 1);
      final prevYear = previousMonth.year;
      final prevMonthNum = previousMonth.month;

      await cTxn(
          '$prevYear-${prevMonthNum.toString().padLeft(2, '0')}-05',
          'Income',
          3000,
          'income');
      await cTxn(
          '$prevYear-${prevMonthNum.toString().padLeft(2, '0')}-15',
          'Income',
          800,
          'expense');

      final summary = await db.getMonthlySummary(
          year: previousMonth.year, month: previousMonth.month);
      expect(summary['balance'], Decimal.fromInt(2200));
    });

    test('excludes current month transactions', () async {
      final now = DateTime.now();
      final previousMonth = DateTime(now.year, now.month - 1, 1);

      await cTxn(
          '${now.year}-${now.month.toString().padLeft(2, '0')}-01',
          'Income',
          99999,
          'income');

      final summary = await db.getMonthlySummary(
          year: previousMonth.year, month: previousMonth.month);
      expect(summary['balance'], Decimal.zero);
    });
  });

  // =========================================================================
  // Cross-cutting concerns: transfer descriptions filtering
  // =========================================================================
  group('Transfer description filtering', () {
    test('transfer descriptions are filtered out in category distribution',
        () async {
      final txnDate = DateTime.now()
          .subtract(const Duration(days: 10))
          .toIso8601String()
          .substring(0, 10);

      await cTxn(txnDate, 'Food', 50, 'expense');
      await cTxn(txnDate, 'Transfer to Savings', 500, 'transfer');

      final top = await db.getTopDescriptions();
      expect(top.length, 1);
      expect(top[0]['description'], 'Food');
    });

    test('transfer descriptions are filtered out in cash flow', () async {
      final now = DateTime.now();
      final monthKey =
          '${now.year}-${now.month.toString().padLeft(2, '0')}';

      await cTxn('$monthKey-01', 'Salary', 2000, 'income');
      await cTxn('$monthKey-02', 'Transfer to Savings', 500, 'transfer');
      await sATxn('$monthKey-03', 'Transfer from Checking', 500, 'transfer');

      final rows = await db.getCashFlowData();
      final monthRows =
          rows.where((r) => r['month'] == monthKey).toList();
      double total = 0.0;
      for (final r in monthRows) {
        total += r['amount'] as double;
      }
      expect(total, 2000.0);
    });
  });

  // =========================================================================
  // Multi-currency aggregation
  // =========================================================================
  group('Multi-currency aggregation', () {
    test('total patrimony groups by currency correctly', () async {
      // GAP: no per-currency grouping API on totals; production converts to
      // a single target currency. Per-account native values preserve the
      // grouping intent.
      await seedUsdEurRate();
      final usdId =
          (await db.addAccount('USD Account', '#FF9800', 'checking', 'USD'))!;
      await cTxn('2025-06-01', 'Income', 1000, 'income');
      await db.addTransaction(
        date: '2025-06-02',
        description: 'Income',
        amount: Decimal.fromInt(500),
        transactionType: 'income',
        accountId: usdId,
      );
      await cTxn('2025-06-03', 'Income', 200, 'expense');

      final dist = await db.getAccountsDistribution();
      final eurValue = dist
          .where((r) => r['currency'] == 'EUR')
          .fold<double>(0.0, (s, r) => s + (r['nativeValue'] as double));
      final usdValue = dist
          .where((r) => r['currency'] == 'USD')
          .fold<double>(0.0, (s, r) => s + (r['nativeValue'] as double));
      expect(eurValue, 800.0);
      expect(usdValue, 500.0);
      final usdRow = dist.firstWhere((r) => r['currency'] == 'USD');
      expect(usdRow['value'], 450.0); // 500 * seeded 0.9 rate
    });

    test('accounts distribution groups by account currency', () async {
      await cTxn('2025-06-01', 'Income', 1000, 'income');
      await cTxn('2025-06-02', 'Income', 200, 'expense');

      final rows = await db.getAccountsDistribution();
      final checking =
          rows.firstWhere((r) => r['name'] == 'Checking Account');
      expect(checking['nativeValue'], 800.0);
      expect(checking['currency'], 'EUR');
    });
  });

  // =========================================================================
  // Edge cases
  // =========================================================================
  group('Edge cases', () {
    test('transactions with null account_id are included in patrimony',
        () async {
      await oTxn('2025-06-01', 'Cash', 500, 'income');

      expect(await db.getTotalPatrimony(), Decimal.fromInt(500));
    });

    test('null account_id transactions use prod balance semantics', () async {
      // GAP: see getBalance orphan test above; production excludes orphans.
      await oTxn('2025-06-01', 'Cash', 300, 'income');

      expect(await db.getBalance(), Decimal.zero);
    });

    test('default currency normalizes to EUR', () async {
      // GAP: no per-currency grouping API; production normalizes blank/
      // missing currencies to EUR and converts totals.
      await oTxn('2025-06-01', 'Cash', 100, 'income');

      expect(await db.getTotalPatrimony(), Decimal.fromInt(100));
      final dist = await db.getAccountsDistribution();
      expect(dist.length, 3);
    });

    test('multiple transactions on same date are aggregated', () async {
      await cTxn('2025-06-15', 'Food', 10, 'expense');
      await cTxn('2025-06-15', 'Food', 20, 'expense');
      await cTxn('2025-06-15', 'Food', 30, 'expense');

      final dist = await db.getDistributionForRange(
          transactionType: 'expense',
          startDate: '2025-06-01',
          endDate: '2025-06-30');
      expect(dist.length, 1);
      expect(dist['Food'], Decimal.fromInt(60));
    });
  });

  // =========================================================================
  // Full scenario: income, expenses, savings across multiple months
  // =========================================================================
  group('Full scenario tests', () {
    test('complex multi-month scenario with all statistics queries', () async {
      // Month 1 (March): income 3000, expense 1200+300=1500
      await cTxn('2025-03-01', 'Salary', 3000, 'income');
      await cTxn('2025-03-05', 'Rent', 1200, 'expense');
      await cTxn('2025-03-10', 'Food', 300, 'expense');

      // Month 2 (April): income 3000, expense 1200+400=1600
      await cTxn('2025-04-01', 'Salary', 3000, 'income');
      await cTxn('2025-04-05', 'Rent', 1200, 'expense');
      await cTxn('2025-04-10', 'Food', 400, 'expense');

      // Month 3 (May): income 3000, expense 1200+250=1450
      await cTxn('2025-05-01', 'Salary', 3000, 'income');
      await cTxn('2025-05-05', 'Rent', 1200, 'expense');
      await cTxn('2025-05-10', 'Food', 250, 'expense');

      // Month 4 (June): income 3000, expense 1200+500=1700
      await cTxn('2025-06-01', 'Salary', 3000, 'income');
      await cTxn('2025-06-05', 'Rent', 1200, 'expense');
      await cTxn('2025-06-15', 'Food', 500, 'expense');

      // --- getTotalPatrimony ---
      // 12000 income - 6250 expenses = 5750
      expect(await db.getTotalPatrimony(), Decimal.fromInt(5750));

      // --- getBalance (checking only) ---
      expect(await db.getBalance(), Decimal.fromInt(5750));

      // --- history patrimony (before May) via getAccountsDistribution ---
      // March + April: (3000-1500) + (3000-1600) = 1500 + 1400 = 2900
      expect(await patrimonyBefore('2025-05-01'), Decimal.fromInt(2900));

      // --- getMonthlySummary for April ---
      final april = await db.getMonthlySummary(year: 2025, month: 4);
      expect(april['income'], Decimal.fromInt(3000));
      expect(april['expenses'], Decimal.fromInt(1600));
      expect(april['balance'], Decimal.fromInt(1400));

      // --- monthly income/expense breakdown for 2025 via cash-flow range ---
      final chart = await db.getCashFlowDataForRange(
          startDate: '2025-01-01', endDate: '2025-12-31');
      final chartMonths = chart.map((r) => r['month'] as String).toSet();
      expect(chartMonths, {'2025-03', '2025-04', '2025-05', '2025-06'});
      final marchIncome = chart.firstWhere(
          (r) => r['month'] == '2025-03' && r['type'] == 'income');
      final marchExpense = chart.firstWhere(
          (r) => r['month'] == '2025-03' && r['type'] == 'expense');
      expect(marchIncome['amount'], 3000.0);
      expect(marchExpense['amount'], 1500.0);

      // --- top descriptions via monthly data (no fixed-range top-N API) ---
      // Rent: 4800 total, Food: 1450 total
      final monthly = await db.getDescriptionMonthlyData(
          '2025-01-01', '2025-12-31');
      double rentTotal = 0.0;
      double foodTotal = 0.0;
      for (final entry in monthly['Rent']!.values) {
        rentTotal += entry['expense']!;
      }
      for (final entry in monthly['Food']!.values) {
        foodTotal += entry['expense']!;
      }
      expect(rentTotal, 4800.0);
      expect(foodTotal, 1450.0);
      expect(rentTotal > foodTotal, true);
    });
  });

  group('getTopTags', () {
    test('returns empty when no tagged transactions', () async {
      expect(await db.getTopTags(), isEmpty);
    });

    test('returns tags ordered by total amount', () async {
      final txnDate = DateTime.now()
          .subtract(const Duration(days: 10))
          .toIso8601String()
          .substring(0, 10);
      final tag1 = (await db.createTag(name: 'Groceries'))!;
      final tag2 = (await db.createTag(name: 'Trip'))!;

      await cTxn(txnDate, 'Food', 100, 'expense', tagId: tag1);
      await cTxn(txnDate, 'Food', 50, 'expense', tagId: tag1);
      await cTxn(txnDate, 'Food', 200, 'expense', tagId: tag2);

      final rows = await db.getTopTags();
      expect(rows.length, 2);
      expect(rows[0]['tag'], 'Trip');
      expect(rows[0]['total'], 200.0);
      expect(rows[1]['tag'], 'Groceries');
      expect(rows[1]['total'], 150.0);
    });

    test('respects minCount filter', () async {
      final txnDate = DateTime.now()
          .subtract(const Duration(days: 10))
          .toIso8601String()
          .substring(0, 10);
      final tagId = (await db.createTag(name: 'Rare'))!;

      await cTxn(txnDate, 'Food', 10, 'expense', tagId: tagId);

      expect(await db.getTopTags(minCount: 2), isEmpty);
    });

    test('excludes untagged transactions', () async {
      final txnDate = DateTime.now()
          .subtract(const Duration(days: 10))
          .toIso8601String()
          .substring(0, 10);

      await cTxn(txnDate, 'Food', 100, 'expense');

      expect(await db.getTopTags(), isEmpty);
    });
  });

  group('getTagMonthlyData', () {
    test('returns empty when no tagged transactions', () async {
      expect(
          await db.getTagMonthlyData('2025-01-01', '2025-12-31'), isEmpty);
    });

    test('returns monthly breakdown per tag', () async {
      final tagId = (await db.createTag(name: 'Groceries'))!;

      await cTxn('2025-06-01', 'Food', 100, 'expense', tagId: tagId);
      await cTxn('2025-06-15', 'Food', 50, 'income', tagId: tagId);
      await cTxn('2025-07-01', 'Food', 75, 'expense', tagId: tagId);

      final data =
          await db.getTagMonthlyData('2025-01-01', '2025-12-31');
      expect(data.containsKey('Groceries'), true);
      expect(data['Groceries']!.length, 2);
      expect(data['Groceries']!['2025-06']!['expense'], 100.0);
      expect(data['Groceries']!['2025-06']!['income'], 50.0);
      expect(data['Groceries']!['2025-07']!['expense'], 75.0);
    });

    test('excludes untagged transactions', () async {
      await cTxn('2025-06-01', 'Food', 100, 'expense');

      expect(
          await db.getTagMonthlyData('2025-01-01', '2025-12-31'), isEmpty);
    });

    test('separates data by tag name', () async {
      final tag1 = (await db.createTag(name: 'Groceries'))!;
      final tag2 = (await db.createTag(name: 'Trip'))!;

      await cTxn('2025-06-01', 'Food', 100, 'expense', tagId: tag1);
      await cTxn('2025-06-01', 'Food', 200, 'expense', tagId: tag2);

      final data =
          await db.getTagMonthlyData('2025-01-01', '2025-12-31');
      expect(data.length, 2);
      double groceriesTotal = 0.0;
      double tripTotal = 0.0;
      for (final entry in data['Groceries']!.values) {
        groceriesTotal += entry['expense']!;
      }
      for (final entry in data['Trip']!.values) {
        tripTotal += entry['expense']!;
      }
      expect(groceriesTotal, 100.0);
      expect(tripTotal, 200.0);
    });
  });

  // =========================================================================
  // Custom range queries (dashboard custom period)
  // =========================================================================
  group('Custom range queries', () {
    test('range distribution only includes transactions within bounds',
        () async {
      await cTxn('2025-03-10', 'Food', 100, 'expense');
      await cTxn('2025-05-10', 'Food', 200, 'expense');
      await cTxn('2025-08-10', 'Food', 400, 'expense');

      final dist = await db.getDistributionForRange(
          transactionType: 'expense',
          startDate: '2025-04-01',
          endDate: '2025-06-30');
      expect(dist['Food'], Decimal.fromInt(200));
    });

    test('range tag distribution only includes the requested tag', () async {
      final tagA = (await db.createTag(name: 'TagA'))!;
      final tagB = (await db.createTag(name: 'TagB'))!;

      await cTxn('2025-04-10', 'Food', 80, 'expense', tagId: tagA);
      await cTxn('2025-04-10', 'Food', 999, 'expense', tagId: tagB);
      await cTxn('2025-09-10', 'Food', 777, 'expense', tagId: tagA);

      final breakdown = await db.getTagDescriptionBreakdown(
          transactionType: 'expense',
          tag: 'TagA',
          startDate: '2025-04-01',
          endDate: '2025-06-30');
      expect(breakdown.length, 1);
      expect(breakdown['Food'], Decimal.fromInt(80));
    });

    test('earliest transaction date returns the minimum date', () async {
      await cTxn('2025-02-10', 'Food', 100, 'expense');
      await cTxn('2025-01-05', 'Food', 50, 'expense');

      expect(await db.getFirstTransactionDate(), '2025-01-05');
    });

    test('range cash flow groups by month within bounds', () async {
      await cTxn('2025-04-15', 'Salary', 1000, 'income');
      await cTxn('2025-05-15', 'Salary', 500, 'income');

      final rows = await db.getCashFlowDataForRange(
          startDate: '2025-04-01', endDate: '2025-06-30');
      final sorted = rows.toList()
        ..sort((a, b) =>
            (a['month'] as String).compareTo(b['month'] as String));
      expect(sorted.length, 2);
      expect(sorted[0]['month'], '2025-04');
      expect(sorted[0]['amount'], 1000.0);
      expect(sorted[1]['month'], '2025-05');
      expect(sorted[1]['amount'], 500.0);
    });
  });

  // =========================================================================
  // Lifetime stats (dashboard averages section)
  // =========================================================================
  group('Lifetime stats', () {
    test('lifetime totals exclude future-dated transactions', () async {
      final now = DateTime.now();
      final pastDate = now
          .subtract(const Duration(days: 10))
          .toIso8601String()
          .substring(0, 10);
      final futureDate =
          now.add(const Duration(days: 10)).toIso8601String().substring(0, 10);
      await cTxn(pastDate, 'Salary', 1000, 'income');
      await cTxn(futureDate, 'Salary', 9999, 'income');

      final stats = await db.getLifetimeStats();
      expect(stats['income'], Decimal.fromInt(1000));
    });

    test('lifetime totals only count checking accounts and orphans', () async {
      final txnDate = DateTime.now()
          .subtract(const Duration(days: 5))
          .toIso8601String()
          .substring(0, 10);

      // checkingId = checking, savingsAId = savings.
      await cTxn(txnDate, 'Food', 100, 'expense');
      await sATxn(txnDate, 'Food', 500, 'expense');
      await oTxn(txnDate, 'Food', 50, 'expense');

      final stats = await db.getLifetimeStats();
      expect(stats['expenses'], Decimal.fromInt(150));
    });
  });
}
