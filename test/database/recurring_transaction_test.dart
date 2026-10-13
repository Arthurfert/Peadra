import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:peadra/core/database/database_manager.dart';
import 'package:peadra/core/models/recurring_transaction.dart';
import 'package:peadra/core/services/recurring_service.dart';

import '../helpers/test_helper.dart';

DatabaseManager get _db => DatabaseManager.instance;

String _dateOnly(DateTime date) => date.toIso8601String().substring(0, 10);

/// Creates a template through the production API.
Future<String> _createTemplate({
  double amount = 100,
  String frequency = 'monthly',
  required String startDate,
  String? endDate,
  String description = 'Recurring test',
  String transactionType = 'expense',
}) async {
  final id = await _db.addRecurringTransaction(
    description: description,
    amount: Decimal.parse(amount.toString()),
    transactionType: transactionType,
    frequency: frequency,
    startDate: startDate,
    endDate: endDate,
  );
  return id!;
}

/// Expected generation plan for [rec], computed with the same pure production
/// logic and look-ahead window that [DatabaseManager.generateDueRecurring]
/// applies. Only used for expectations; all writes go through prod APIs.
Future<RecurringPlan> _expectedPlan(RecurringTransaction rec) async {
  final crdt = await _db.database;
  final existing = await crdt.query(
    'SELECT date FROM transactions WHERE recurring_id = ? AND user_id = ? AND is_deleted = 0',
    [rec.id, _db.userId],
  );
  final exceptions = await crdt.query(
    'SELECT date FROM recurring_exceptions WHERE recurring_id = ? AND is_deleted = 0',
    [rec.id],
  );
  return RecurringService.planGeneration(
    rec,
    existingDates: existing.map((r) => r['date'] as String).toSet(),
    exceptionDates: exceptions.map((r) => r['date'] as String).toSet(),
    today: DateTime.now(),
    lookAheadDays: 5,
  );
}

/// Dates of the transactions generated for [templateId], oldest first.
Future<List<String>> _generatedDates(String templateId) async {
  final txns = await _db.getTransactions();
  final dates = txns
      .where((t) => t.recurringId == templateId)
      .map((t) => t.date)
      .toList()
    ..sort();
  return dates;
}

void main() {
  setUpAll(() {
    initializeTestDatabase();
  });

  setUp(() async {
    await _db.openInMemoryForTest(userId: 'user-test');
    await _db.setEncryptionKey(await deriveTestKey());
  });

  group('Schema', () {
    test('transactions table has recurring_id column', () async {
      final crdt = await _db.database;
      final rows = await crdt.query(
        "SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'transactions'",
      );
      expect(rows, hasLength(1));
      expect(rows.first['sql'] as String, contains('recurring_id'));
    });

    test('recurring and goals tables exist', () async {
      final crdt = await _db.database;
      final tables = await crdt.query(
        "SELECT name FROM sqlite_master WHERE type = 'table'",
      );
      final names = tables.map((t) => t['name']).toSet();
      expect(names, contains('recurring_transactions'));
      expect(names, contains('recurring_exceptions'));
      expect(names, contains('goals'));
    });
  });

  group('Recurring template CRUD', () {
    test('inserts a template with default next_due_date = start_date', () async {
      final start = _dateOnly(DateTime.now());
      final id = await _createTemplate(
        amount: 500,
        frequency: 'monthly',
        startDate: start,
      );
      final rec = await _db.getRecurringTransaction(id);
      expect(rec, isNotNull);
      expect(rec!.amount, Decimal.fromInt(500));
      expect(rec.frequency, 'monthly');
      expect(rec.nextDueDate, start);
      expect(rec.active, isTrue);
    });

    test('rejects unsupported transaction types via CHECK constraint', () async {
      final crdt = await _db.database;
      expect(
        () => crdt.execute(
          'INSERT INTO recurring_transactions (id, user_id, amount, transaction_type, frequency, start_date, next_due_date) '
          'VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)',
          [
            'tmpl-bad',
            _db.userId,
            100,
            'transfer',
            'monthly',
            '2025-01-01',
            '2025-01-01',
          ],
        ),
        throwsA(anything),
      );
    });

    test('updates a template and marks it inactive', () async {
      final start = _dateOnly(DateTime.now());
      final id = await _createTemplate(
        amount: 500,
        frequency: 'monthly',
        startDate: start,
      );
      expect(
        await _db.updateRecurringTransaction(id, amount: Decimal.fromInt(600)),
        isTrue,
      );
      expect(await _db.toggleRecurringActive(id, false), isTrue);
      final rec = await _db.getRecurringTransaction(id);
      expect(rec, isNotNull);
      expect(rec!.active, isFalse);
      expect(rec.amount, Decimal.fromInt(600));
    });

    test('delete template removes occurrences and exceptions', () async {
      final start = _dateOnly(DateTime.now());
      final id = await _createTemplate(
        amount: 100,
        frequency: 'monthly',
        startDate: start,
      );
      await _db.generateDueRecurring();
      expect(await _generatedDates(id), isNotEmpty);
      await _db.markRecurringOccurrenceDeleted(id, start);

      expect(await _db.deleteRecurringTransaction(id), isTrue);

      expect(await _db.getRecurringTransactions(), isEmpty);
      expect(await _generatedDates(id), isEmpty);
      final crdt = await _db.database;
      final exceptions = await crdt.query(
        'SELECT date FROM recurring_exceptions WHERE recurring_id = ? AND is_deleted = 0',
        [id],
      );
      expect(exceptions, isEmpty);
    });
  });

  group('Generation flow', () {
    test('generates due occurrences and links them via recurring_id', () async {
      final today = DateTime.now();
      final start = _dateOnly(today);
      final id = await _createTemplate(
        amount: 500,
        frequency: 'monthly',
        startDate: start,
      );

      await _db.generateDueRecurring();

      final txns = await _db.getTransactions();
      final generated = txns.where((t) => t.recurringId == id).toList();
      expect(generated, hasLength(1));
      expect(generated.single.date, start);
      expect(generated.single.amount, Decimal.fromInt(500));

      // Next monthly anniversary of the anchor day, clamped to month length.
      final maxDay = DateTime(today.year, today.month + 2, 0).day;
      final clampedDay = today.day > maxDay ? maxDay : today.day;
      final expectedNext =
          _dateOnly(DateTime(today.year, today.month + 1, clampedDay));
      final updated = await _db.getRecurringTransaction(id);
      expect(updated, isNotNull);
      expect(updated!.nextDueDate, expectedNext);
      expect(updated.active, isTrue);
    });

    test('is idempotent across multiple generation runs', () async {
      final now = DateTime.now();
      final start = _dateOnly(DateTime(now.year, now.month - 2, 15));
      final id = await _createTemplate(
        amount: 100,
        frequency: 'monthly',
        startDate: start,
      );
      final plan =
          await _expectedPlan((await _db.getRecurringTransaction(id))!);
      expect(plan.dueDates.length, greaterThan(1));

      await _db.generateDueRecurring();
      expect(await _generatedDates(id), plan.dueDates);

      await _db.generateDueRecurring();
      expect(await _generatedDates(id), plan.dueDates);
    });

    test('backfills missed occurrences when the app was closed', () async {
      final now = DateTime.now();
      final start = _dateOnly(DateTime(now.year, now.month - 3, 15));
      final id = await _createTemplate(
        amount: 100,
        frequency: 'monthly',
        startDate: start,
      );
      final plan =
          await _expectedPlan((await _db.getRecurringTransaction(id))!);
      expect(plan.dueDates.length, greaterThan(2));

      await _db.generateDueRecurring();

      expect(await _generatedDates(id), plan.dueDates);
    });

    test('clamps monthly occurrences to month end', () async {
      final now = DateTime.now();
      final anchorYear = now.month >= 3 ? now.year : now.year - 1;
      final start = '$anchorYear-01-31';
      final id = await _createTemplate(
        amount: 100,
        frequency: 'monthly',
        startDate: start,
      );
      final plan =
          await _expectedPlan((await _db.getRecurringTransaction(id))!);

      await _db.generateDueRecurring();

      final dates = await _generatedDates(id);
      expect(dates, plan.dueDates);
      expect(dates.first, start);
      for (final date in dates) {
        final dt = DateTime.parse(date);
        final maxDay = DateTime(dt.year, dt.month + 1, 0).day;
        expect(dt.day, lessThanOrEqualTo(maxDay));
      }
      // The February occurrence proves clamping: it cannot land on the 31st.
      expect(
        dates.any((date) {
          final dt = DateTime.parse(date);
          return dt.month == 2 && dt.day < 31;
        }),
        isTrue,
      );
    });

    test('does not regenerate deleted (tombstoned) occurrences', () async {
      final now = DateTime.now();
      final start = _dateOnly(DateTime(now.year, now.month - 2, 15));
      final tombstone = _dateOnly(DateTime(now.year, now.month - 1, 15));
      final id = await _createTemplate(
        amount: 100,
        frequency: 'monthly',
        startDate: start,
      );

      await _db.generateDueRecurring();
      expect(await _generatedDates(id), contains(tombstone));

      // Simulate "delete this occurrence only": remove the row and tombstone it.
      final txns = await _db.getTransactions();
      final occurrence =
          txns.singleWhere((t) => t.recurringId == id && t.date == tombstone);
      expect(await _db.deleteTransaction(occurrence.id!), isTrue);
      await _db.markRecurringOccurrenceDeleted(id, tombstone);

      await _db.generateDueRecurring();

      final dates = await _generatedDates(id);
      expect(dates, contains(start));
      expect(dates, isNot(contains(tombstone)));
      // Everything else is stable: no duplicates, nothing else missing.
      final plan =
          await _expectedPlan((await _db.getRecurringTransaction(id))!);
      expect(plan.dueDates, isEmpty);
      expect(dates.toSet(), hasLength(dates.length));
    });

    test('deactivates the template once the end date is reached', () async {
      final now = DateTime.now();
      String anniversary(int monthOffset) =>
          _dateOnly(DateTime(now.year, now.month + monthOffset, 15));
      final id = await _createTemplate(
        amount: 100,
        frequency: 'monthly',
        startDate: anniversary(-3),
        endDate: anniversary(-1),
      );

      await _db.generateDueRecurring();

      expect(
        await _generatedDates(id),
        [anniversary(-3), anniversary(-2), anniversary(-1)],
      );
      final updated = await _db.getRecurringTransaction(id);
      expect(updated, isNotNull);
      expect(updated!.active, isFalse);
      expect(updated.nextDueDate, anniversary(-1));
    });

    test('does nothing for future-dated templates', () async {
      final start =
          _dateOnly(DateTime.now().add(const Duration(days: 30)));
      final id = await _createTemplate(
        amount: 100,
        frequency: 'monthly',
        startDate: start,
      );

      await _db.generateDueRecurring();

      expect(await _generatedDates(id), isEmpty);
      final updated = await _db.getRecurringTransaction(id);
      expect(updated, isNotNull);
      expect(updated!.nextDueDate, start);
      expect(updated.active, isTrue);
    });

    test('generated transactions flow through the transactions JOIN with frequency',
        () async {
      final start = _dateOnly(DateTime.now());
      final id = await _createTemplate(
        amount: 100,
        frequency: 'weekly',
        startDate: start,
      );
      await _db.generateDueRecurring();

      final txns = await _db.getTransactions();
      final generated = txns.where((t) => t.recurringId == id).toList();
      expect(generated, hasLength(1));
      expect(generated.single.recurringFrequency, 'weekly');
    });
  });
}
