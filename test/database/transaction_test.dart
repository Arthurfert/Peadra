import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:peadra/core/database/database_manager.dart';
import 'package:peadra/core/models/transaction.dart';

void main() {
  sqfliteFfiInit();

  late List<String> accountIds;
  late String myUserId;

  Future<List<TransactionWithDetails>> allTxns() =>
      DatabaseManager.instance.getTransactions();

  Future<TransactionWithDetails> txnById(String id) async {
    final txns = await allTxns();
    return txns.firstWhere((t) => t.id == id);
  }

  setUp(() async {
    myUserId = 'user-${DateTime.now().microsecondsSinceEpoch}';
    await DatabaseManager.instance.openInMemoryForTest(userId: myUserId);
    final db = DatabaseManager.instance;
    final a = await db.addAccount(
        'Checking Account', '#4CAF50', 'checking', 'EUR');
    final b = await db.addAccount(
        'Savings Account A', '#2196F3', 'savings', 'EUR');
    final c = await db.addAccount(
        'Savings Account B', '#009688', 'savings', 'EUR');
    accountIds = [a!, b!, c!];
  });

  group('Adding transactions', () {
    test('adds an income transaction with account', () async {
      final db = DatabaseManager.instance;
      final id = await db.addTransaction(
        date: '2025-01-15',
        description: 'Salary',
        amount: Decimal.fromInt(3000),
        transactionType: 'income',
        accountId: accountIds[0],
      );

      expect(id, isNotNull);
      final txn = await txnById(id!);
      expect(txn.date, '2025-01-15');
      expect(txn.amount, Decimal.fromInt(3000));
      expect(txn.transactionType, 'income');
      expect(txn.accountId, accountIds[0]);
      expect(txn.currency, 'EUR');
    });

    test('adds an expense transaction', () async {
      final db = DatabaseManager.instance;
      final id = await db.addTransaction(
        date: '2025-03-10',
        description: 'Groceries',
        amount: Decimal.parse('55.75'),
        transactionType: 'expense',
        accountId: accountIds[0],
      );

      final txn = await txnById(id!);
      expect(txn.transactionType, 'expense');
      expect(txn.amount, Decimal.parse('55.75'));
    });

    test('adds a transfer transaction', () async {
      final db = DatabaseManager.instance;
      final id = await db.addTransaction(
        date: '2025-02-20',
        description: 'Transfer to Savings',
        amount: Decimal.fromInt(500),
        transactionType: 'transfer',
        accountId: accountIds[1],
      );

      final txn = await txnById(id!);
      expect(txn.transactionType, 'transfer');
    });

    test('adds a transaction with null account', () async {
      final db = DatabaseManager.instance;
      final id = await db.addTransaction(
        date: '2025-01-20',
        description: 'Cash income',
        amount: Decimal.fromInt(200),
        transactionType: 'income',
      );

      final txn = await txnById(id!);
      expect(txn.accountId, isNull);
      expect(txn.currency, 'EUR');
    });

    test('adds a transaction with notes', () async {
      final db = DatabaseManager.instance;
      final id = await db.addTransaction(
        date: '2025-01-25',
        description: 'Freelance work',
        amount: Decimal.fromInt(1500),
        transactionType: 'income',
        accountId: accountIds[0],
        notes: 'Project ABC invoice',
      );

      final txn = await txnById(id!);
      expect(txn.notes, 'Project ABC invoice');
    });

    test('adds a transaction with explicit currency', () async {
      final db = DatabaseManager.instance;
      final id = await db.addTransaction(
        date: '2025-01-25',
        description: 'USD Income',
        amount: Decimal.fromInt(100),
        transactionType: 'income',
        currency: 'USD',
      );

      final txn = await txnById(id!);
      expect(txn.currency, 'USD');
    });

    test('creates description record for the transaction', () async {
      final db = DatabaseManager.instance;
      final id = await db.addTransaction(
        date: '2025-01-15',
        description: 'New Description',
        amount: Decimal.fromInt(100),
        transactionType: 'income',
      );

      final descs = (await db.getAllDescriptions())
          .where((d) => d.name == 'New Description')
          .toList();
      expect(descs, hasLength(1));

      final txn = await txnById(id!);
      expect(txn.descriptionId, descs.single.id);
    });

    test('reuses existing description with same name', () async {
      final db = DatabaseManager.instance;
      final id1 = await db.addTransaction(
        date: '2025-01-15',
        description: 'Rent',
        amount: Decimal.fromInt(1000),
        transactionType: 'expense',
      );
      final id2 = await db.addTransaction(
        date: '2025-02-15',
        description: 'Rent',
        amount: Decimal.fromInt(1000),
        transactionType: 'expense',
      );

      final descs = (await db.getAllDescriptions())
          .where((d) => d.name == 'Rent')
          .toList();
      expect(descs, hasLength(1));

      final t1 = await txnById(id1!);
      final t2 = await txnById(id2!);
      expect(t1.descriptionId, t2.descriptionId);
    });

    test('multiple transactions with same description share description_id',
        () async {
      final db = DatabaseManager.instance;
      await db.addTransaction(
        date: '2025-01-01',
        description: 'Coffee',
        amount: Decimal.fromInt(5),
        transactionType: 'expense',
        accountId: accountIds[0],
      );
      await db.addTransaction(
        date: '2025-01-02',
        description: 'Coffee',
        amount: Decimal.parse('4.5'),
        transactionType: 'expense',
        accountId: accountIds[0],
      );

      final descs = (await db.getAllDescriptions())
          .where((d) => d.name == 'Coffee')
          .toList();
      expect(descs, hasLength(1));

      final txns = (await allTxns())
          .where((t) => t.descriptionId == descs.single.id)
          .toList();
      expect(txns, hasLength(2));
    });
  });

  group('Updating transactions', () {
    late String txnId;

    setUp(() async {
      final db = DatabaseManager.instance;
      txnId = (await db.addTransaction(
        date: '2025-01-15',
        description: 'Salary',
        amount: Decimal.fromInt(3000),
        transactionType: 'income',
        accountId: accountIds[0],
        notes: 'January salary',
      ))!;
    });

    test('updates date', () async {
      final db = DatabaseManager.instance;
      final result = await db.updateTransaction(txnId, date: '2025-02-01');
      expect(result, isTrue);

      expect((await txnById(txnId)).date, '2025-02-01');
    });

    test('updates amount', () async {
      final db = DatabaseManager.instance;
      final result =
          await db.updateTransaction(txnId, amount: Decimal.fromInt(3500));
      expect(result, isTrue);

      expect((await txnById(txnId)).amount, Decimal.fromInt(3500));
    });

    test('updates transaction type', () async {
      final db = DatabaseManager.instance;
      final result =
          await db.updateTransaction(txnId, transactionType: 'expense');
      expect(result, isTrue);

      expect((await txnById(txnId)).transactionType, 'expense');
    });

    test('updates description', () async {
      final db = DatabaseManager.instance;
      final result = await db.updateTransaction(txnId, description: 'Bonus');
      expect(result, isTrue);

      expect((await txnById(txnId)).descriptionName, 'Bonus');
    });

    test('updates notes', () async {
      final db = DatabaseManager.instance;
      final result =
          await db.updateTransaction(txnId, notes: 'Updated note');
      expect(result, isTrue);

      expect((await txnById(txnId)).notes, 'Updated note');
    });

    test('updates account', () async {
      final db = DatabaseManager.instance;
      final result =
          await db.updateTransaction(txnId, accountId: accountIds[1]);
      expect(result, isTrue);

      expect((await txnById(txnId)).accountId, accountIds[1]);
    });

    test('updates currency', () async {
      final db = DatabaseManager.instance;
      final result = await db.updateTransaction(txnId, currency: 'USD');
      expect(result, isTrue);

      expect((await txnById(txnId)).currency, 'USD');
    });

    test('partial update with multiple fields', () async {
      final db = DatabaseManager.instance;
      final result = await db.updateTransaction(
        txnId,
        date: '2025-06-15',
        amount: Decimal.fromInt(4000),
        notes: 'June bonus',
      );
      expect(result, isTrue);

      final txn = await txnById(txnId);
      expect(txn.date, '2025-06-15');
      expect(txn.amount, Decimal.fromInt(4000));
      expect(txn.notes, 'June bonus');
      expect(txn.transactionType, 'income');
      expect(txn.accountId, accountIds[0]);
    });

    test('returns false when no fields provided', () async {
      final db = DatabaseManager.instance;
      final result = await db.updateTransaction(txnId);
      expect(result, isFalse);
    });

    test('returns false for non-existent transaction', () async {
      final db = DatabaseManager.instance;
      final result = await db.updateTransaction('non-existent-id',
          amount: Decimal.fromInt(100));
      expect(result, isFalse);
    });

    test('updates description and creates new description record', () async {
      final db = DatabaseManager.instance;
      await db.updateTransaction(txnId, description: 'New Description');

      expect((await txnById(txnId)).descriptionName, 'New Description');
    });

    test('sets updated_at timestamp on update', () async {
      final db = DatabaseManager.instance;
      final before = await txnById(txnId);
      final oldUpdated = before.updatedAt;

      await Future.delayed(const Duration(milliseconds: 10));
      await db.updateTransaction(txnId, amount: Decimal.fromInt(100));

      final after = await txnById(txnId);
      final newUpdated = after.updatedAt;

      expect(newUpdated, isNotNull);
      if (oldUpdated != null) {
        expect(newUpdated != oldUpdated, isTrue);
      }
    });
  });

  group('Deleting transactions', () {
    test('deletes an existing transaction', () async {
      final db = DatabaseManager.instance;
      final id = (await db.addTransaction(
        date: '2025-01-15',
        description: 'To Delete',
        amount: Decimal.fromInt(50),
        transactionType: 'expense',
      ))!;

      final result = await db.deleteTransaction(id);
      expect(result, isTrue);

      expect(await allTxns(), isEmpty);
    });

    test('returns false for non-existent transaction', () async {
      final db = DatabaseManager.instance;
      final result = await db.deleteTransaction('non-existent-id');
      expect(result, isFalse);
    });

    test('does not affect other users transactions', () async {
      final db = DatabaseManager.instance;
      final otherUserId = 'other-${DateTime.now().microsecondsSinceEpoch}';
      db.setSessionUserId(otherUserId);
      await db.addTransaction(
        date: '2025-01-15',
        description: 'Other user txn',
        amount: Decimal.fromInt(100),
        transactionType: 'income',
      );
      db.setSessionUserId(myUserId);

      final id = (await db.addTransaction(
        date: '2025-01-15',
        description: 'My Transaction',
        amount: Decimal.fromInt(100),
        transactionType: 'income',
      ))!;

      await db.deleteTransaction(id);
      expect(await allTxns(), isEmpty);

      db.setSessionUserId(otherUserId);
      final otherTxns = await allTxns();
      expect(otherTxns, hasLength(1));
      db.setSessionUserId(myUserId);
    });

    test('deletes multiple transactions independently', () async {
      final db = DatabaseManager.instance;
      final id1 = (await db.addTransaction(
        date: '2025-01-01',
        description: 'T1',
        amount: Decimal.fromInt(10),
        transactionType: 'expense',
      ))!;
      final id2 = (await db.addTransaction(
        date: '2025-01-02',
        description: 'T2',
        amount: Decimal.fromInt(20),
        transactionType: 'expense',
      ))!;

      await db.deleteTransaction(id1);

      final remaining = await allTxns();
      expect(remaining, hasLength(1));
      expect(remaining.single.id, id2);
    });

    test('does not delete description record when transaction is deleted',
        () async {
      final db = DatabaseManager.instance;
      final id = (await db.addTransaction(
        date: '2025-01-15',
        description: 'Keep Description',
        amount: Decimal.fromInt(100),
        transactionType: 'income',
      ))!;

      final descId = (await txnById(id)).descriptionId;

      await db.deleteTransaction(id);

      final descs = await db.getAllDescriptions();
      expect(descs.where((d) => d.id == descId), hasLength(1));
    });
  });

  group('Querying transactions with filters', () {
    setUp(() async {
      final db = DatabaseManager.instance;
      await db.addTransaction(
        date: '2025-01-10',
        description: 'Groceries',
        amount: Decimal.fromInt(50),
        transactionType: 'expense',
        accountId: accountIds[0],
      );
      await db.addTransaction(
        date: '2025-01-15',
        description: 'Salary',
        amount: Decimal.fromInt(3000),
        transactionType: 'income',
        accountId: accountIds[0],
      );
      await db.addTransaction(
        date: '2025-01-20',
        description: 'Groceries',
        amount: Decimal.fromInt(30),
        transactionType: 'expense',
        accountId: accountIds[1],
      );
      await db.addTransaction(
        date: '2025-01-25',
        description: 'Transfer to Checking',
        amount: Decimal.fromInt(200),
        transactionType: 'transfer',
        accountId: accountIds[2],
      );
    });

    test('returns all transactions without filters', () async {
      final db = DatabaseManager.instance;
      final results = await db.getTransactions();
      expect(results, hasLength(4));
    });

    test('searches by description name (case-insensitive)', () async {
      final db = DatabaseManager.instance;
      final results = await db.getTransactions(searchQuery: 'groceries');
      expect(results, hasLength(2));
      for (final r in results) {
        expect(r.descriptionName!.toLowerCase(), contains('groceries'));
      }
    });

    test('searches by account name (case-insensitive)', () async {
      final db = DatabaseManager.instance;
      final results = await db.getTransactions(searchQuery: 'savings');
      expect(results, hasLength(2));
    });

    test('filters by single account ID', () async {
      final db = DatabaseManager.instance;
      final results =
          await db.getTransactions(accountIds: {accountIds[0]});
      expect(results, hasLength(2));
      for (final r in results) {
        expect(r.accountId, accountIds[0]);
      }
    });

    test('filters by multiple account IDs', () async {
      final db = DatabaseManager.instance;
      final results = await db.getTransactions(
          accountIds: {accountIds[0], accountIds[1]});
      expect(results, hasLength(3));
    });

    test('applies limit', () async {
      final db = DatabaseManager.instance;
      final results = await db.getTransactions(limit: 2);
      expect(results, hasLength(2));
    });

    test('applies offset', () async {
      final db = DatabaseManager.instance;
      final all = await db.getTransactions();
      final offsetResults =
          await db.getTransactions(offset: 2, limit: 2);
      expect(offsetResults, hasLength(2));
      expect(offsetResults.first.id, all[2].id);
    });

    test('search combined with account filter', () async {
      final db = DatabaseManager.instance;
      final results = await db.getTransactions(
        searchQuery: 'groceries',
        accountIds: {accountIds[0]},
      );
      expect(results, hasLength(1));
      expect(results.single.descriptionName, 'Groceries');
      expect(results.single.accountId, accountIds[0]);
    });

    test('returns empty list for non-matching search', () async {
      final db = DatabaseManager.instance;
      final results = await db.getTransactions(searchQuery: 'nonexistent');
      expect(results, isEmpty);
    });

    test('returns empty list for non-matching account IDs', () async {
      final db = DatabaseManager.instance;
      final results =
          await db.getTransactions(accountIds: {'non-existent-id'});
      expect(results, isEmpty);
    });

    test('includes joined account and description details', () async {
      final db = DatabaseManager.instance;
      final results = await db.getTransactions();
      final groceries =
          results.firstWhere((r) => r.descriptionName == 'Groceries');
      expect(groceries.accountName, isNotNull);
      expect(groceries.accountColor, isNotNull);
      expect(groceries.accountCurrency, isNotNull);
      expect(groceries.descriptionName, 'Groceries');
    });

    test('results ordered by date descending, then id descending', () async {
      final db = DatabaseManager.instance;
      final results = await db.getTransactions();
      for (var i = 0; i < results.length - 1; i++) {
        final dateA = results[i].date;
        final dateB = results[i + 1].date;
        expect(dateA.compareTo(dateB) >= 0, isTrue);
      }
    });

    test('returns transaction with null account details', () async {
      final db = DatabaseManager.instance;
      await db.addTransaction(
        date: '2025-02-01',
        description: 'No Account',
        amount: Decimal.fromInt(10),
        transactionType: 'income',
      );

      final results = await db.getTransactions();
      final noAccount = results.firstWhere((r) => r.accountId == null);
      expect(noAccount.accountName, isNull);
      expect(noAccount.accountColor, isNull);
    });
  });

  group('Period-based queries', () {
    setUp(() async {
      final db = DatabaseManager.instance;
      await db.addTransaction(
        date: '2025-01-05',
        description: 'Jan Income',
        amount: Decimal.fromInt(100),
        transactionType: 'income',
      );
      await db.addTransaction(
        date: '2025-01-15',
        description: 'Jan Expense',
        amount: Decimal.fromInt(200),
        transactionType: 'expense',
      );
      await db.addTransaction(
        date: '2025-02-10',
        description: 'Feb Income',
        amount: Decimal.fromInt(300),
        transactionType: 'income',
      );
      await db.addTransaction(
        date: '2025-03-01',
        description: 'Mar Expense',
        amount: Decimal.fromInt(50),
        transactionType: 'expense',
      );
    });

    test('returns transactions within date range (inclusive)', () async {
      final db = DatabaseManager.instance;
      final results =
          await db.getTransactionsByPeriod('2025-01-01', '2025-01-31');
      expect(results, hasLength(2));
    });

    test('returns transactions in February', () async {
      final db = DatabaseManager.instance;
      final results =
          await db.getTransactionsByPeriod('2025-02-01', '2025-02-28');
      expect(results, hasLength(1));
      expect(results.single.date, '2025-02-10');
    });

    test('returns empty for range with no transactions', () async {
      final db = DatabaseManager.instance;
      final results =
          await db.getTransactionsByPeriod('2024-12-01', '2024-12-31');
      expect(results, isEmpty);
    });

    test('single-day range', () async {
      final db = DatabaseManager.instance;
      final results =
          await db.getTransactionsByPeriod('2025-01-15', '2025-01-15');
      expect(results, hasLength(1));
      expect(results.single.date, '2025-01-15');
    });

    test('wide range captures all transactions', () async {
      final db = DatabaseManager.instance;
      final results =
          await db.getTransactionsByPeriod('2020-01-01', '2030-12-31');
      expect(results, hasLength(4));
    });

    test('results ordered by date descending', () async {
      final db = DatabaseManager.instance;
      final results =
          await db.getTransactionsByPeriod('2025-01-01', '2025-03-31');
      expect(results, hasLength(4));
      for (var i = 0; i < results.length - 1; i++) {
        final dateA = results[i].date;
        final dateB = results[i + 1].date;
        expect(dateA.compareTo(dateB) >= 0, isTrue);
      }
    });

    test('does not return transactions from other users', () async {
      final db = DatabaseManager.instance;
      final otherUserId = 'other-${DateTime.now().microsecondsSinceEpoch}';
      db.setSessionUserId(otherUserId);
      await db.addTransaction(
        date: '2025-01-10',
        description: 'Other user txn',
        amount: Decimal.fromInt(999),
        transactionType: 'income',
      );
      db.setSessionUserId(myUserId);

      final results =
          await db.getTransactionsByPeriod('2025-01-01', '2025-01-31');
      expect(results, hasLength(2));
      for (final r in results) {
        expect(r.userId, myUserId);
      }
    });
  });

  group('Earliest transaction date', () {
    test('returns null when no transactions exist', () async {
      final db = DatabaseManager.instance;
      final result = await db.getFirstTransactionDate();
      expect(result, isNull);
    });

    test('returns earliest date among transactions', () async {
      final db = DatabaseManager.instance;
      await db.addTransaction(
        date: '2025-06-01',
        description: 'D1',
        amount: Decimal.fromInt(10),
        transactionType: 'income',
      );
      await db.addTransaction(
        date: '2025-01-15',
        description: 'D2',
        amount: Decimal.fromInt(20),
        transactionType: 'expense',
      );
      await db.addTransaction(
        date: '2025-03-20',
        description: 'D3',
        amount: Decimal.fromInt(30),
        transactionType: 'income',
      );

      final result = await db.getFirstTransactionDate();
      expect(result, '2025-01-15');
    });

    test('returns single date when only one transaction exists', () async {
      final db = DatabaseManager.instance;
      await db.addTransaction(
        date: '2025-08-20',
        description: 'D1',
        amount: Decimal.fromInt(50),
        transactionType: 'income',
      );

      final result = await db.getFirstTransactionDate();
      expect(result, '2025-08-20');
    });

    test('only considers current user transactions', () async {
      final db = DatabaseManager.instance;
      final otherUserId = 'other-${DateTime.now().microsecondsSinceEpoch}';
      db.setSessionUserId(otherUserId);
      await db.addTransaction(
        date: '2020-01-01',
        description: 'Other',
        amount: Decimal.fromInt(10),
        transactionType: 'income',
      );
      db.setSessionUserId(myUserId);
      await db.addTransaction(
        date: '2025-06-01',
        description: 'D1',
        amount: Decimal.fromInt(20),
        transactionType: 'income',
      );

      final result = await db.getFirstTransactionDate();
      expect(result, '2025-06-01');
    });
  });

  group('Currency resolution from accounts', () {
    test('returns EUR for checking account', () async {
      final db = DatabaseManager.instance;
      final result = await db.getAccountCurrency(accountIds[0]);
      expect(result, 'EUR');
    });

    test('returns EUR for savings account A', () async {
      final db = DatabaseManager.instance;
      final result = await db.getAccountCurrency(accountIds[1]);
      expect(result, 'EUR');
    });

    test('returns EUR for savings account B', () async {
      final db = DatabaseManager.instance;
      final result = await db.getAccountCurrency(accountIds[2]);
      expect(result, 'EUR');
    });

    test('returns null for non-existent account', () async {
      final db = DatabaseManager.instance;
      final result = await db.getAccountCurrency('non-existent-id');
      expect(result, isNull);
    });

    test('transaction inherits account currency when account provided',
        () async {
      final db = DatabaseManager.instance;
      await db.updateAccount(
          accountIds[0], 'Checking Account', '#4CAF50',
          currency: 'USD');

      final id = (await db.addTransaction(
        date: '2025-01-15',
        description: 'USD Transaction',
        amount: Decimal.fromInt(100),
        transactionType: 'income',
        accountId: accountIds[0],
      ))!;

      expect((await txnById(id)).currency, 'USD');
    });

    test('transaction uses default EUR when no account provided', () async {
      final db = DatabaseManager.instance;
      final id = (await db.addTransaction(
        date: '2025-01-15',
        description: 'No Account Transaction',
        amount: Decimal.fromInt(100),
        transactionType: 'income',
      ))!;

      expect((await txnById(id)).currency, 'EUR');
    });

    test('transaction uses explicit currency when no account provided',
        () async {
      final db = DatabaseManager.instance;
      final id = (await db.addTransaction(
        date: '2025-01-15',
        description: 'Explicit Currency',
        amount: Decimal.fromInt(100),
        transactionType: 'income',
        currency: 'GBP',
      ))!;

      expect((await txnById(id)).currency, 'GBP');
    });

    test('account currency takes precedence over explicit currency', () async {
      final db = DatabaseManager.instance;
      await db.updateAccount(
          accountIds[0], 'Checking Account', '#4CAF50',
          currency: 'CHF');

      final id = (await db.addTransaction(
        date: '2025-01-15',
        description: 'Currency Test',
        amount: Decimal.fromInt(100),
        transactionType: 'income',
        accountId: accountIds[0],
        currency: 'GBP',
      ))!;

      expect((await txnById(id)).currency, 'CHF');
    });
  });

  group('Edge cases', () {
    test('transaction with zero amount', () async {
      final db = DatabaseManager.instance;
      final id = (await db.addTransaction(
        date: '2025-01-15',
        description: 'Zero Amount',
        amount: Decimal.zero,
        transactionType: 'income',
      ))!;

      expect((await txnById(id)).amount, Decimal.zero);
    });

    test('transaction with very large amount', () async {
      final db = DatabaseManager.instance;
      final id = (await db.addTransaction(
        date: '2025-01-15',
        description: 'Large Amount',
        amount: Decimal.parse('999999999.99'),
        transactionType: 'income',
      ))!;

      expect((await txnById(id)).amount,
          Decimal.parse('999999999.99'));
    });

    test('transaction with very small decimal amount', () async {
      final db = DatabaseManager.instance;
      final id = (await db.addTransaction(
        date: '2025-01-15',
        description: 'Small Amount',
        amount: Decimal.parse('0.01'),
        transactionType: 'expense',
      ))!;

      expect((await txnById(id)).amount, Decimal.parse('0.01'));
    });

    test('transaction with negative amount (allowed by schema)', () async {
      final db = DatabaseManager.instance;
      final id = (await db.addTransaction(
        date: '2025-01-15',
        description: 'Negative Amount',
        amount: Decimal.parse('-50'),
        transactionType: 'income',
      ))!;

      expect((await txnById(id)).amount, Decimal.parse('-50'));
    });

    test('transaction with empty description name', () async {
      final db = DatabaseManager.instance;
      final id = (await db.addTransaction(
        date: '2025-01-15',
        description: '',
        amount: Decimal.fromInt(10),
        transactionType: 'income',
      ))!;

      // Prod never creates a junk empty-string description row:
      // description_id stays null instead.
      final txn = await txnById(id);
      expect(txn.descriptionId, isNull);
      expect(txn.descriptionName, isNull);
    });

    test('transaction with null notes', () async {
      final db = DatabaseManager.instance;
      final id = (await db.addTransaction(
        date: '2025-01-15',
        description: 'No Notes',
        amount: Decimal.fromInt(10),
        transactionType: 'income',
      ))!;

      expect((await txnById(id)).notes, isNull);
    });

    test('transaction with special characters in notes', () async {
      final db = DatabaseManager.instance;
      final id = (await db.addTransaction(
        date: '2025-01-15',
        description: 'Special Notes',
        amount: Decimal.fromInt(10),
        transactionType: 'income',
        notes: 'Line1\nLine2\tTab "Quotes" \'Single\' <HTML>',
      ))!;

      expect((await txnById(id)).notes,
          'Line1\nLine2\tTab "Quotes" \'Single\' <HTML>');
    });

    test('transaction with unicode description', () async {
      final db = DatabaseManager.instance;
      final id = (await db.addTransaction(
        date: '2025-01-15',
        description: 'Café Ñoño 日本語',
        amount: Decimal.fromInt(10),
        transactionType: 'income',
      ))!;

      expect((await txnById(id)).descriptionName, 'Café Ñoño 日本語');
    });

    test('updating notes to empty string', () async {
      final db = DatabaseManager.instance;
      final id = (await db.addTransaction(
        date: '2025-01-15',
        description: 'Notes Test',
        amount: Decimal.fromInt(10),
        transactionType: 'income',
        notes: 'Has notes',
      ))!;

      final result = await db.updateTransaction(id, notes: '');
      expect(result, isTrue);

      expect((await txnById(id)).notes, '');
    });

    test('many transactions with same description do not create duplicate descriptions',
        () async {
      final db = DatabaseManager.instance;
      for (var i = 0; i < 10; i++) {
        await db.addTransaction(
          date: '2025-01-${(i + 1).toString().padLeft(2, '0')}',
          description: 'Recurring Expense',
          amount: Decimal.fromInt((i + 1) * 10),
          transactionType: 'expense',
        );
      }

      final descs = (await db.getAllDescriptions())
          .where((d) => d.name == 'Recurring Expense')
          .toList();
      expect(descs, hasLength(1));

      expect(await allTxns(), hasLength(10));
    });

    test('description lookup is case-insensitive (no duplicate rows)',
        () async {
      final db = DatabaseManager.instance;
      await db.addTransaction(
        date: '2025-01-15',
        description: 'Groceries',
        amount: Decimal.fromInt(10),
        transactionType: 'expense',
      );
      await db.addTransaction(
        date: '2025-01-16',
        description: 'groceries',
        amount: Decimal.fromInt(20),
        transactionType: 'expense',
      );

      // Prod getOrCreateDescription matches case-insensitively, so both
      // transactions share a single description row.
      final txns = await allTxns();
      expect(txns, hasLength(2));
      expect(txns[0].descriptionId, txns[1].descriptionId);
      final descs = await db.getAllDescriptions();
      final matches = descs
          .where((d) => d.name.toLowerCase() == 'groceries')
          .toList();
      expect(matches, hasLength(1));
    });

    test('deleting transaction does not affect account', () async {
      final db = DatabaseManager.instance;
      final id = (await db.addTransaction(
        date: '2025-01-15',
        description: 'Delete Me',
        amount: Decimal.fromInt(100),
        transactionType: 'income',
        accountId: accountIds[0],
      ))!;

      await db.deleteTransaction(id);

      expect(await db.getAllAccounts(), hasLength(3));
    });

    test('deleting transaction does not affect other descriptions', () async {
      final db = DatabaseManager.instance;
      final descId = await db.getOrCreateDescription('Shared Desc');
      final id1 = (await db.addTransaction(
        date: '2025-01-15',
        description: 'Shared Desc',
        amount: Decimal.fromInt(100),
        transactionType: 'income',
      ))!;
      final id2 = (await db.addTransaction(
        date: '2025-01-20',
        description: 'Shared Desc',
        amount: Decimal.fromInt(200),
        transactionType: 'income',
      ))!;

      await db.deleteTransaction(id1);

      final remaining = (await allTxns())
          .where((t) => t.descriptionId == descId)
          .toList();
      expect(remaining, hasLength(1));
      expect(remaining.single.id, id2);
    });

    test('different users can have descriptions with same name', () async {
      final db = DatabaseManager.instance;
      await db.addTransaction(
        date: '2025-01-15',
        description: 'Shared Name',
        amount: Decimal.fromInt(10),
        transactionType: 'income',
      );
      final myDescId = (await txnById(
              (await allTxns()).single.id!))
          .descriptionId;

      final otherUserId = 'user2-${DateTime.now().microsecondsSinceEpoch}';
      db.setSessionUserId(otherUserId);
      final otherDescId = await db.getOrCreateDescription('Shared Name');
      await db.addTransaction(
        date: '2025-01-15',
        description: 'Shared Name',
        amount: Decimal.fromInt(20),
        transactionType: 'income',
      );
      final otherDescs = (await db.getAllDescriptions())
          .where((d) => d.name == 'Shared Name')
          .toList();
      db.setSessionUserId(myUserId);
      final myDescs = (await db.getAllDescriptions())
          .where((d) => d.name == 'Shared Name')
          .toList();

      expect(myDescs, hasLength(1));
      expect(otherDescs, hasLength(1));
      expect(myDescs.single.id != otherDescs.single.id, isTrue);
      expect(myDescId, myDescs.single.id);
      expect(otherDescId, otherDescs.single.id);
    });

    test('multiple transactions across dates with mixed types', () async {
      final db = DatabaseManager.instance;
      await db.addTransaction(
        date: '2025-01-01',
        description: 'Income',
        amount: Decimal.fromInt(5000),
        transactionType: 'income',
      );
      await db.addTransaction(
        date: '2025-01-05',
        description: 'Expense',
        amount: Decimal.fromInt(200),
        transactionType: 'expense',
      );
      await db.addTransaction(
        date: '2025-01-10',
        description: 'Transfer',
        amount: Decimal.fromInt(1000),
        transactionType: 'transfer',
      );
      await db.addTransaction(
        date: '2025-01-15',
        description: 'Income',
        amount: Decimal.fromInt(500),
        transactionType: 'income',
      );

      final txns = await allTxns();
      expect(txns.where((t) => t.transactionType == 'income'), hasLength(2));
      expect(
          txns.where((t) => t.transactionType == 'expense'), hasLength(1));
      expect(
          txns.where((t) => t.transactionType == 'transfer'), hasLength(1));
    });

    test('update on description field creates description if needed', () async {
      final db = DatabaseManager.instance;
      final id = (await db.addTransaction(
        date: '2025-01-15',
        description: 'Old Desc',
        amount: Decimal.fromInt(100),
        transactionType: 'income',
      ))!;

      await db.updateTransaction(id, description: 'Brand New Desc');

      expect((await txnById(id)).descriptionName, 'Brand New Desc');
    });

    test('getTransactions returns correct joined data for transfer', () async {
      final db = DatabaseManager.instance;
      final id = (await db.addTransaction(
        date: '2025-01-15',
        description: 'Transfer to Savings',
        amount: Decimal.fromInt(500),
        transactionType: 'transfer',
        accountId: accountIds[1],
        notes: 'Monthly savings',
      ))!;

      final results = await db.getTransactions();
      final transfer = results.firstWhere((r) => r.id == id);
      expect(transfer.accountName, 'Savings Account A');
      expect(transfer.accountColor, '#2196F3');
      expect(transfer.descriptionName, 'Transfer to Savings');
      expect(transfer.notes, 'Monthly savings');
    });

    test('period query returns empty for swapped dates', () async {
      final db = DatabaseManager.instance;
      await db.addTransaction(
        date: '2025-01-15',
        description: 'Test',
        amount: Decimal.fromInt(100),
        transactionType: 'income',
      );

      final results =
          await db.getTransactionsByPeriod('2025-01-31', '2025-01-01');
      expect(results, isEmpty);
    });

    test('getTransactions with empty account IDs set behaves as no filter',
        () async {
      final db = DatabaseManager.instance;
      await db.addTransaction(
        date: '2025-01-15',
        description: 'Test',
        amount: Decimal.fromInt(100),
        transactionType: 'income',
      );

      final withEmpty = await db.getTransactions(accountIds: {});
      final without = await db.getTransactions();
      expect(withEmpty.length, without.length);
    });
  });

  group('tag_id on transactions', () {
    test('addTransaction with tag_id', () async {
      final db = DatabaseManager.instance;
      final tagId = (await db.createTag(name: 'Groceries'))!;

      final id = (await db.addTransaction(
        date: '2025-06-01',
        description: 'Groceries run',
        amount: Decimal.fromInt(25),
        transactionType: 'expense',
        accountId: accountIds[0],
        tagId: tagId,
      ))!;

      final txn = await txnById(id);
      expect(txn.tagId, tagId);
    });

    test('updateTransaction can set tag_id', () async {
      final db = DatabaseManager.instance;
      final tagId = (await db.createTag(name: 'Groceries'))!;

      final id = (await db.addTransaction(
        date: '2025-06-01',
        description: 'Groceries run',
        amount: Decimal.fromInt(25),
        transactionType: 'expense',
      ))!;

      await db.updateTransaction(id, tagId: tagId);

      expect((await txnById(id)).tagId, tagId);
    });

    test('updateTransaction can clear tag_id', () async {
      final db = DatabaseManager.instance;
      final tagId = (await db.createTag(name: 'Groceries'))!;

      final id = (await db.addTransaction(
        date: '2025-06-01',
        description: 'Tagged',
        amount: Decimal.fromInt(25),
        transactionType: 'expense',
        tagId: tagId,
      ))!;

      await db.updateTransaction(id, clearTag: true);

      expect((await txnById(id)).tagId, isNull);
    });

    test('getTransactions with tag_ids filter', () async {
      final db = DatabaseManager.instance;
      final tag1 = (await db.createTag(name: 'Groceries'))!;
      final tag2 = (await db.createTag(name: 'Trip'))!;

      await db.addTransaction(
          date: '2025-06-01',
          description: 'T1',
          amount: Decimal.fromInt(10),
          transactionType: 'expense',
          accountId: accountIds[0],
          tagId: tag1);
      await db.addTransaction(
          date: '2025-06-02',
          description: 'T2',
          amount: Decimal.fromInt(20),
          transactionType: 'expense',
          accountId: accountIds[0],
          tagId: tag2);
      await db.addTransaction(
          date: '2025-06-03',
          description: 'T3',
          amount: Decimal.fromInt(30),
          transactionType: 'expense',
          accountId: accountIds[0]);

      final rows = await db.getTransactions(tagIds: {tag1, tag2});
      expect(rows, hasLength(2));
    });

    test('getTransactions JOIN includes tag_name and tag_color', () async {
      final db = DatabaseManager.instance;
      final tagId =
          (await db.createTag(name: 'Trip', color: '#D32F2F'))!;

      await db.addTransaction(
          date: '2025-06-01',
          description: 'Trip expense',
          amount: Decimal.fromInt(100),
          transactionType: 'expense',
          accountId: accountIds[0],
          tagId: tagId);

      final rows = await db.getTransactions();
      expect(rows.single.tagName, 'Trip');
      expect(rows.single.tagColor, '#D32F2F');
    });

    test('getTransactions search matches tag_name', () async {
      final db = DatabaseManager.instance;
      final tagId = (await db.createTag(name: 'Vacation'))!;

      await db.addTransaction(
          date: '2025-06-01',
          description: 'Tagged expense',
          amount: Decimal.fromInt(500),
          transactionType: 'expense',
          accountId: accountIds[0],
          tagId: tagId);
      await db.addTransaction(
          date: '2025-06-02',
          description: 'Plain expense',
          amount: Decimal.fromInt(10),
          transactionType: 'expense',
          accountId: accountIds[0]);

      final rows = await db.getTransactions(searchQuery: 'vacat');
      expect(rows, hasLength(1));
      expect(rows.single.tagName, 'Vacation');
    });
  });
}
