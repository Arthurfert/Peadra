import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:peadra/core/database/database_manager.dart';

void main() {
  sqfliteFfiInit();

  String today() => DateTime.now().toIso8601String().substring(0, 10);

  setUp(() async {
    await DatabaseManager.instance
        .openInMemoryForTest(userId: 'user-${DateTime.now().microsecondsSinceEpoch}');
  });

  Future<(String, String, String)> seedThreeAccounts(
    DatabaseManager db, {
    Decimal? checking,
    Decimal? savingsA,
    Decimal? savingsB,
  }) async {
    final c = await db.addAccount('Checking Account', '#4CAF50', 'checking',
        'EUR',
        startingAmount: checking ?? Decimal.zero);
    final a = await db.addAccount('Savings Account A', '#2196F3', 'savings',
        'EUR',
        startingAmount: savingsA ?? Decimal.zero);
    final b = await db.addAccount('Savings Account B', '#009688', 'savings',
        'EUR',
        startingAmount: savingsB ?? Decimal.zero);
    return (c!, a!, b!);
  }

  Future<void> addTxn(
    DatabaseManager db, {
    String? accountId,
    String date = '2025-01-15',
    required int amount,
    String transactionType = 'income',
  }) =>
      db.addTransaction(
        date: date,
        description: 'Pay',
        amount: Decimal.fromInt(amount),
        transactionType: transactionType,
        accountId: accountId,
      );

  group('Account CRUD with starting_amount', () {
    test('insert account with starting_amount stores it', () async {
      final db = DatabaseManager.instance;
      await db.addAccount('My Account', '#4CAF50', 'checking', 'EUR',
          startingAmount: Decimal.fromInt(5000));

      final accounts = await db.getAllAccounts();
      expect(accounts, hasLength(1));
      expect(accounts.single.startingAmount, Decimal.fromInt(5000));
    });

    test('insert account without starting_amount defaults to 0', () async {
      final db = DatabaseManager.instance;
      await db.addAccount('Default Account', '#4CAF50', 'savings', 'EUR');

      final accounts = await db.getAllAccounts();
      expect(accounts.single.startingAmount, Decimal.zero);
    });

    test('update account starting_amount', () async {
      final db = DatabaseManager.instance;
      final id = await db.addAccount('Update Test', '#4CAF50', 'checking',
          'EUR',
          startingAmount: Decimal.fromInt(1000));

      expect(
        await db.updateAccount(id!, 'Update Test', '#4CAF50',
            startingAmount: Decimal.fromInt(2500)),
        isTrue,
      );

      final accounts = await db.getAllAccounts();
      expect(accounts.single.startingAmount, Decimal.fromInt(2500));
    });

    test('negative starting_amount is stored correctly', () async {
      final db = DatabaseManager.instance;
      await db.addAccount('Overdrawn', '#4CAF50', 'checking', 'EUR',
          startingAmount: Decimal.fromInt(-500));

      final accounts = await db.getAllAccounts();
      expect(accounts.single.startingAmount, Decimal.fromInt(-500));
    });
  });

  group('getAccountsWithBalances includes starting_amount', () {
    test('balance = starting_amount when no transactions', () async {
      final db = DatabaseManager.instance;
      await seedThreeAccounts(db,
          checking: Decimal.fromInt(1000),
          savingsA: Decimal.fromInt(2000),
          savingsB: Decimal.fromInt(3000));

      final accounts = await db.getAccountsWithBalances();
      final byName = {for (final a in accounts) a.name: a};

      expect(byName['Checking Account']!.balance, Decimal.fromInt(1000));
      expect(byName['Savings Account A']!.balance, Decimal.fromInt(2000));
      expect(byName['Savings Account B']!.balance, Decimal.fromInt(3000));
    });

    test('balance = starting_amount + transactions', () async {
      final db = DatabaseManager.instance;
      final ids = await seedThreeAccounts(db,
          checking: Decimal.fromInt(1000),
          savingsA: Decimal.zero,
          savingsB: Decimal.zero);

      await addTxn(db, accountId: ids.$1, amount: 500, transactionType: 'income');
      await addTxn(db,
          accountId: ids.$1, amount: 200, transactionType: 'expense');

      final accounts = await db.getAccountsWithBalances();
      final checking =
          accounts.singleWhere((a) => a.name == 'Checking Account');
      expect(checking.balance, Decimal.fromInt(1300)); // 1000 + 500 - 200
    });

    test('zero starting_amount with transactions', () async {
      final db = DatabaseManager.instance;
      final ids = await seedThreeAccounts(db);

      await addTxn(db, accountId: ids.$1, amount: 300, transactionType: 'income');

      final accounts = await db.getAccountsWithBalances();
      final checking =
          accounts.singleWhere((a) => a.name == 'Checking Account');
      expect(checking.balance, Decimal.fromInt(300));
    });
  });

  group('getAccountsDistribution includes starting_amount', () {
    test('distribution uses starting_amount in balance', () async {
      final db = DatabaseManager.instance;
      await seedThreeAccounts(db,
          checking: Decimal.fromInt(500),
          savingsA: Decimal.fromInt(1500),
          savingsB: Decimal.zero);

      final rows = await db.getAccountsDistribution();
      final byName = {for (final r in rows) r['name'] as String: r};

      expect(byName['Checking Account']!['value'], 500.0);
      expect(byName['Savings Account A']!['value'], 1500.0);
    });
  });

  group('getBalance includes starting_amount from checking accounts', () {
    test('balance sums starting_amounts of checking accounts', () async {
      final db = DatabaseManager.instance;
      await seedThreeAccounts(db,
          checking: Decimal.fromInt(1000),
          savingsA: Decimal.fromInt(2000),
          savingsB: Decimal.fromInt(3000));

      expect(await db.getBalance(), Decimal.fromInt(1000)); // Only checking
    });

    test('balance = starting_amount + transactions for checking', () async {
      final db = DatabaseManager.instance;
      final ids = await seedThreeAccounts(db,
          checking: Decimal.fromInt(1000),
          savingsA: Decimal.fromInt(2000),
          savingsB: Decimal.fromInt(3000));

      await addTxn(db, accountId: ids.$1, amount: 500, transactionType: 'income');
      // Savings income must not leak into the checking balance.
      await addTxn(db, accountId: ids.$2, amount: 800, transactionType: 'income');

      expect(await db.getBalance(), Decimal.fromInt(1500)); // 1000 + 500
    });
  });

  group('getSavingsTotal includes starting_amount from savings accounts', () {
    test('savings total sums starting_amounts of savings accounts', () async {
      final db = DatabaseManager.instance;
      await seedThreeAccounts(db,
          checking: Decimal.fromInt(1000),
          savingsA: Decimal.fromInt(2000),
          savingsB: Decimal.fromInt(3000));

      expect(await db.getSavingsTotal(), Decimal.fromInt(5000)); // 2000 + 3000
    });

    test('savings total = starting_amounts + transactions', () async {
      final db = DatabaseManager.instance;
      final ids = await seedThreeAccounts(db,
          checking: Decimal.fromInt(1000),
          savingsA: Decimal.fromInt(2000),
          savingsB: Decimal.fromInt(3000));

      await addTxn(db, accountId: ids.$2, amount: 400, transactionType: 'income');
      await addTxn(db,
          accountId: ids.$3, amount: 100, transactionType: 'expense');

      expect(
          await db.getSavingsTotal(), Decimal.fromInt(5300)); // 5000 + 400 - 100
    });
  });

  group('getTotalPatrimony includes starting_amount', () {
    test('patrimony sums all starting_amounts + transactions', () async {
      final db = DatabaseManager.instance;
      final ids = await seedThreeAccounts(db,
          checking: Decimal.fromInt(1000),
          savingsA: Decimal.fromInt(2000),
          savingsB: Decimal.fromInt(3000));

      await addTxn(db, accountId: ids.$1, amount: 500, transactionType: 'income');
      await addTxn(db,
          accountId: ids.$2, amount: 300, transactionType: 'expense');

      expect(await db.getTotalPatrimony(),
          Decimal.fromInt(6200)); // 6000 + 500 - 300
    });

    test('patrimony with zero starting_amounts', () async {
      final db = DatabaseManager.instance;
      final ids = await seedThreeAccounts(db);

      await addTxn(db, accountId: ids.$1, amount: 100, transactionType: 'income');

      expect(await db.getTotalPatrimony(), Decimal.fromInt(100));
    });
  });

  group('getAssetsHistory includes starting_amount', () {
    test('each month total starts from starting_total', () async {
      final db = DatabaseManager.instance;
      final ids = await seedThreeAccounts(db,
          checking: Decimal.fromInt(1000),
          savingsA: Decimal.fromInt(500),
          savingsB: Decimal.zero);

      await addTxn(db,
          accountId: ids.$1, date: today(), amount: 200, transactionType: 'income');

      final history = await db.getAssetsHistory();
      expect(history, isNotEmpty);
      // 1500 starting + 200 income.
      expect(history.last['value'], 1700.0);
    });
  });

  group('getHistoryBalance and getHistorySavings include starting_amount', () {
    test('history balance includes checking starting_amount', () async {
      final db = DatabaseManager.instance;
      await seedThreeAccounts(db,
          checking: Decimal.fromInt(1000),
          savingsA: Decimal.fromInt(2000),
          savingsB: Decimal.fromInt(3000));

      expect(await db.getBalance(), Decimal.fromInt(1000)); // Only checking
    });

    test('history savings includes savings starting_amounts', () async {
      final db = DatabaseManager.instance;
      await seedThreeAccounts(db,
          checking: Decimal.fromInt(1000),
          savingsA: Decimal.fromInt(2000),
          savingsB: Decimal.fromInt(3000));

      expect(
          await db.getSavingsTotal(), Decimal.fromInt(5000)); // 2000 + 3000
    });

    test('history balance with transactions before date limit', () async {
      final db = DatabaseManager.instance;
      final ids = await seedThreeAccounts(db,
          checking: Decimal.fromInt(1000),
          savingsA: Decimal.zero,
          savingsB: Decimal.zero);

      await addTxn(db,
          accountId: ids.$1,
          date: '2024-12-15',
          amount: 300,
          transactionType: 'income');
      await addTxn(db,
          accountId: ids.$1,
          date: '2025-02-15',
          amount: 500,
          transactionType: 'income');

      // 1000 starting + 300 (December only; February is past the limit).
      expect(
          await db.getBalance(before: '2025-01-01'), Decimal.fromInt(1300));
    });
  });

  group('Edge cases', () {
    test('all accounts with zero starting_amount', () async {
      final db = DatabaseManager.instance;
      final ids = await seedThreeAccounts(db);

      await addTxn(db, accountId: ids.$1, amount: 100, transactionType: 'income');

      expect(await db.getTotalPatrimony(), Decimal.fromInt(100));
    });

    test('negative starting_amount reduces balance', () async {
      final db = DatabaseManager.instance;
      final ids = await seedThreeAccounts(db,
          checking: Decimal.fromInt(-500),
          savingsA: Decimal.zero,
          savingsB: Decimal.zero);

      await addTxn(db, accountId: ids.$1, amount: 200, transactionType: 'income');

      final accounts = await db.getAccountsWithBalances();
      final checking =
          accounts.singleWhere((a) => a.name == 'Checking Account');
      expect(checking.balance, Decimal.fromInt(-300)); // -500 + 200
    });

    test('starting_amount does not affect monthly summary', () async {
      final db = DatabaseManager.instance;
      final ids = await seedThreeAccounts(db,
          checking: Decimal.fromInt(5000),
          savingsA: Decimal.zero,
          savingsB: Decimal.zero);

      await addTxn(db,
          accountId: ids.$1,
          date: today(),
          amount: 300,
          transactionType: 'income');
      await addTxn(db,
          accountId: ids.$1,
          date: today(),
          amount: 100,
          transactionType: 'expense');

      final summary = await db.getMonthlySummary();
      expect(summary['income'], Decimal.fromInt(300)); // Starting NOT included
      expect(summary['expenses'], Decimal.fromInt(100));
    });

    test('starting_amount does not affect cash flow data', () async {
      final db = DatabaseManager.instance;
      final ids = await seedThreeAccounts(db,
          checking: Decimal.fromInt(5000),
          savingsA: Decimal.zero,
          savingsB: Decimal.zero);

      await addTxn(db,
          accountId: ids.$1,
          date: today(),
          amount: 200,
          transactionType: 'income');

      final startDate = DateTime.now()
          .subtract(const Duration(days: 30))
          .toIso8601String()
          .substring(0, 10);
      final rows = await db.getCashFlowDataForRange(
          startDate: startDate, endDate: today());

      expect(rows, hasLength(1));
      expect(rows.single['amount'], 200.0); // Starting NOT included
      expect(rows.single['type'], 'income');
    });
  });

  group('Multi-currency with starting_amount', () {
    test('starting_amount is converted using exchange rates', () async {
      final db = DatabaseManager.instance;
      await db.addAccount('USD Account', '#4CAF50', 'checking', 'USD',
          startingAmount: Decimal.fromInt(1000));
      await db.addAccount('EUR Account', '#4CAF50', 'checking', 'EUR',
          startingAmount: Decimal.fromInt(500));

      // DatabaseManager has no rate setter (rates come from fetchExchangeRates),
      // so seed the production exchange_rates table directly.
      final handle = await db.database;
      final now = DateTime.now().toIso8601String();
      await handle.execute(
        'INSERT OR REPLACE INTO exchange_rates (from_currency, to_currency, rate, updated_at) VALUES (?1, ?2, ?3, ?4)',
        ['USD', 'EUR', 0.92, now],
      );
      await handle.execute(
        'INSERT OR REPLACE INTO exchange_rates (from_currency, to_currency, rate, updated_at) VALUES (?1, ?2, ?3, ?4)',
        ['EUR', 'USD', 1.087, now],
      );

      // 1000*0.92 + 500 = 920 + 500.
      expect(
        await db.getTotalPatrimony(targetCurrency: 'EUR'),
        Decimal.fromInt(1420),
      );
    });
  });
}
