import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:peadra/core/database/database_manager.dart';
import 'package:peadra/core/models/goal.dart';

void main() {
  sqfliteFfiInit();

  String today() => DateTime.now().toIso8601String().substring(0, 10);

  setUp(() async {
    await DatabaseManager.instance
        .openInMemoryForTest(userId: 'user-${DateTime.now().microsecondsSinceEpoch}');
  });

  test('goal CRUD round-trip', () async {
    final db = DatabaseManager.instance;

    expect(await db.getGoals(), isEmpty);

    final id = await db.createGoal(
      kind: BudgetGoal.kindTotalAssets,
      targetAmount: Decimal.fromInt(1000),
      currency: 'EUR',
      period: BudgetGoal.periodMonthly,
    );
    expect(id, isNotNull);

    var goals = await db.getGoals();
    expect(goals, hasLength(1));
    expect(goals.single.targetAmount, Decimal.fromInt(1000));
    expect(goals.single.period, BudgetGoal.periodMonthly);

    // Zero target is rejected.
    expect(
      await db.createGoal(
        kind: BudgetGoal.kindTotalAssets,
        targetAmount: Decimal.zero,
      ),
      isNull,
    );

    final ok = await db.updateGoal(
      id!,
      targetAmount: Decimal.fromInt(2000),
      period: BudgetGoal.periodCustom,
      deadline: '2030-01-01',
      startDate: today(),
    );
    expect(ok, isTrue);
    goals = await db.getGoals();
    expect(goals.single.targetAmount, Decimal.fromInt(2000));
    expect(goals.single.deadline, '2030-01-01');

    expect(await db.deleteGoal(id), isTrue);
    expect(await db.getGoals(), isEmpty);
  });

  test('total assets goal tracks patrimony', () async {
    final db = DatabaseManager.instance;
    await db.addAccount('Cash', '#4CAF50', 'checking', 'EUR',
        startingAmount: Decimal.fromInt(100));
    await db.addTransaction(
      date: today(),
      description: 'Pay',
      amount: Decimal.fromInt(50),
      transactionType: 'income',
    );

    final id = await db.createGoal(
      kind: BudgetGoal.kindTotalAssets,
      targetAmount: Decimal.fromInt(1000),
      currency: 'EUR',
      period: BudgetGoal.periodMonthly,
    );
    final goal = (await db.getGoals()).singleWhere((g) => g.id == id);
    expect(await db.getGoalCurrentValue(goal), Decimal.fromInt(150));
  });

  test('account goal tracks that account only', () async {
    final db = DatabaseManager.instance;
    final a = await db.addAccount('A', '#4CAF50', 'checking', 'EUR',
        startingAmount: Decimal.fromInt(100));
    final b = await db.addAccount('B', '#2196F3', 'savings', 'EUR',
        startingAmount: Decimal.fromInt(500));
    await db.addTransaction(
      date: today(),
      description: 'Pay',
      amount: Decimal.fromInt(50),
      transactionType: 'income',
      accountId: b,
    );

    final id = await db.createGoal(
      kind: BudgetGoal.kindAccount,
      accountId: a,
      targetAmount: Decimal.fromInt(1000),
      currency: 'EUR',
      period: BudgetGoal.periodMonthly,
    );
    final goal = (await db.getGoals()).singleWhere((g) => g.id == id);
    expect(await db.getGoalCurrentValue(goal), Decimal.fromInt(100));
  });

  test('monthly tag goal counts current month only', () async {
    final db = DatabaseManager.instance;
    final tagId = await db.createTag(name: 'food');
    final now = DateTime.now();
    final thisMonth = today();
    final twoMonthsAgo = DateTime(now.year, now.month - 2, 15)
        .toIso8601String()
        .substring(0, 10);

    await db.addTransaction(
      date: thisMonth,
      description: 'Groceries',
      amount: Decimal.fromInt(30),
      transactionType: 'expense',
      tagId: tagId,
    );
    await db.addTransaction(
      date: twoMonthsAgo,
      description: 'Old groceries',
      amount: Decimal.fromInt(999),
      transactionType: 'expense',
      tagId: tagId,
    );

    final id = await db.createGoal(
      kind: BudgetGoal.kindTag,
      tagId: tagId,
      transactionType: 'expense',
      targetAmount: Decimal.fromInt(200),
      currency: 'EUR',
      period: BudgetGoal.periodMonthly,
    );
    final goal = (await db.getGoals()).singleWhere((g) => g.id == id);
    expect(await db.getGoalCurrentValue(goal), Decimal.fromInt(30));
  });

  test('upcoming tag value counts future transactions in window', () async {
    final db = DatabaseManager.instance;
    final tagId = await db.createTag(name: 'salary');
    final now = DateTime.now();
    final today = now.toIso8601String().substring(0, 10);
    final start =
        now.subtract(const Duration(days: 10)).toIso8601String().substring(0, 10);
    final soon =
        now.add(const Duration(days: 10)).toIso8601String().substring(0, 10);
    final deadline =
        now.add(const Duration(days: 300)).toIso8601String().substring(0, 10);
    final beyond = now
        .add(const Duration(days: 400))
        .toIso8601String()
        .substring(0, 10);

    await db.addTransaction(
      date: today,
      description: 'Pay',
      amount: Decimal.fromInt(100),
      transactionType: 'income',
      tagId: tagId,
    );
    await db.addTransaction(
      date: soon,
      description: 'Next pay',
      amount: Decimal.fromInt(50),
      transactionType: 'income',
      tagId: tagId,
    );
    await db.addTransaction(
      date: beyond,
      description: 'Far pay',
      amount: Decimal.fromInt(999),
      transactionType: 'income',
      tagId: tagId,
    );

    final id = await db.createGoal(
      kind: BudgetGoal.kindTag,
      tagId: tagId,
      transactionType: 'income',
      targetAmount: Decimal.fromInt(500),
      currency: 'EUR',
      period: BudgetGoal.periodCustom,
      deadline: deadline,
      startDate: start,
    );
    final goal = (await db.getGoals()).singleWhere((g) => g.id == id);
    expect(await db.getGoalCurrentValue(goal), Decimal.fromInt(100));
    expect(await db.getGoalUpcomingValue(goal), Decimal.fromInt(50));
  });

  test('upcoming total and account values', () async {
    final db = DatabaseManager.instance;
    final now = DateTime.now();
    final today = now.toIso8601String().substring(0, 10);
    final soon =
        now.add(const Duration(days: 5)).toIso8601String().substring(0, 10);
    final deadline =
        now.add(const Duration(days: 300)).toIso8601String().substring(0, 10);

    final a = await db.addAccount('A', '#4CAF50', 'checking', 'EUR',
        startingAmount: Decimal.fromInt(100));
    final b = await db.addAccount('B', '#2196F3', 'savings', 'EUR',
        startingAmount: Decimal.zero);
    await db.addTransaction(
      date: today,
      description: 'Pay',
      amount: Decimal.fromInt(20),
      transactionType: 'income',
      accountId: a,
    );
    await db.addTransaction(
      date: soon,
      description: 'Bonus',
      amount: Decimal.fromInt(25),
      transactionType: 'income',
      accountId: a,
    );
    await db.addTransaction(
      date: soon,
      description: 'Bill',
      amount: Decimal.fromInt(40),
      transactionType: 'expense',
      accountId: a,
    );
    await db.addTransaction(
      date: soon,
      description: 'Other',
      amount: Decimal.fromInt(777),
      transactionType: 'income',
      accountId: b,
    );

    final totalId = await db.createGoal(
      kind: BudgetGoal.kindTotalAssets,
      targetAmount: Decimal.fromInt(1000),
      currency: 'EUR',
      period: BudgetGoal.periodCustom,
      deadline: deadline,
    );
    final totalGoal =
        (await db.getGoals()).singleWhere((g) => g.id == totalId);
    // +25 -40 +777 ahead.
    expect(await db.getGoalUpcomingValue(totalGoal), Decimal.fromInt(762));

    final acctId = await db.createGoal(
      kind: BudgetGoal.kindAccount,
      accountId: a,
      targetAmount: Decimal.fromInt(1000),
      currency: 'EUR',
      period: BudgetGoal.periodCustom,
      deadline: deadline,
    );
    final acctGoal =
        (await db.getGoals()).singleWhere((g) => g.id == acctId);
    // +25 -40 ahead on A only.
    expect(await db.getGoalUpcomingValue(acctGoal), Decimal.fromInt(-15));
  });

  test('upcoming is zero once the deadline has passed', () async {
    final db = DatabaseManager.instance;
    final now = DateTime.now();
    final soon =
        now.add(const Duration(days: 5)).toIso8601String().substring(0, 10);
    final past =
        now.subtract(const Duration(days: 2)).toIso8601String().substring(0, 10);
    final tagId = await db.createTag(name: 'food');
    await db.addTransaction(
      date: soon,
      description: 'Groceries',
      amount: Decimal.fromInt(30),
      transactionType: 'expense',
      tagId: tagId,
    );

    final id = await db.createGoal(
      kind: BudgetGoal.kindTag,
      tagId: tagId,
      transactionType: 'expense',
      targetAmount: Decimal.fromInt(200),
      currency: 'EUR',
      period: BudgetGoal.periodCustom,
      deadline: past,
    );
    final goal = (await db.getGoals()).singleWhere((g) => g.id == id);
    expect(goal.isOverdue(now.toIso8601String().substring(0, 10)), isTrue);
    expect(await db.getGoalUpcomingValue(goal), Decimal.zero);
  });

  test('custom tag goal uses its start/deadline window', () async {
    final db = DatabaseManager.instance;
    final tagId = await db.createTag(name: 'salary');
    final now = DateTime.now();
    final start =
        now.subtract(const Duration(days: 10)).toIso8601String().substring(0, 10);
    final beforeStart =
        now.subtract(const Duration(days: 20)).toIso8601String().substring(0, 10);
    final deadline =
        now.add(const Duration(days: 300)).toIso8601String().substring(0, 10);

    await db.addTransaction(
      date: now.toIso8601String().substring(0, 10),
      description: 'Pay',
      amount: Decimal.fromInt(100),
      transactionType: 'income',
      tagId: tagId,
    );
    await db.addTransaction(
      date: beforeStart,
      description: 'Old pay',
      amount: Decimal.fromInt(777),
      transactionType: 'income',
      tagId: tagId,
    );

    final id = await db.createGoal(
      kind: BudgetGoal.kindTag,
      tagId: tagId,
      transactionType: 'income',
      targetAmount: Decimal.fromInt(500),
      currency: 'EUR',
      period: BudgetGoal.periodCustom,
      deadline: deadline,
      startDate: start,
    );
    final goal = (await db.getGoals()).singleWhere((g) => g.id == id);
    expect(goal.effectiveDeadline(today()), deadline);
    expect(goal.isOverdue(today()), isFalse);
    expect(await db.getGoalCurrentValue(goal), Decimal.fromInt(100));
  });
}
