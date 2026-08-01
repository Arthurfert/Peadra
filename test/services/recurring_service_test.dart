import 'package:flutter_test/flutter_test.dart';
import 'package:peadra/core/models/recurring_transaction.dart';
import 'package:peadra/core/services/recurring_service.dart';

RecurringTransaction _make({
  String frequency = 'monthly',
  int interval = 1,
  int? dayOfWeek,
  int? dayOfMonth,
  String startDate = '2025-01-15',
  String? endDate,
  String nextDueDate = '2025-01-15',
  double amount = 100,
}) {
  return RecurringTransaction(
    userId: 1,
    amount: amount,
    transactionType: 'expense',
    currency: 'EUR',
    frequency: frequency,
    interval: interval,
    dayOfWeek: dayOfWeek,
    dayOfMonth: dayOfMonth,
    startDate: startDate,
    endDate: endDate,
    nextDueDate: nextDueDate,
  );
}

void main() {
  group('nextOccurrence', () {
    test('daily adds interval days', () {
      final rec = _make(frequency: 'daily', startDate: '2025-01-15');
      expect(
        RecurringService.nextOccurrence(rec, DateTime(2025, 1, 15)),
        DateTime(2025, 1, 16),
      );
      final rec2 = _make(frequency: 'daily', interval: 3, startDate: '2025-01-15');
      expect(
        RecurringService.nextOccurrence(rec2, DateTime(2025, 1, 15)),
        DateTime(2025, 1, 18),
      );
    });

    test('weekly keeps the same weekday', () {
      final rec = _make(frequency: 'weekly', startDate: '2025-01-15');
      expect(
        RecurringService.nextOccurrence(rec, DateTime(2025, 1, 15)),
        DateTime(2025, 1, 22),
      );
    });

    test('monthly keeps the same day of month', () {
      final rec = _make(frequency: 'monthly', startDate: '2025-01-15');
      expect(
        RecurringService.nextOccurrence(rec, DateTime(2025, 1, 15)),
        DateTime(2025, 2, 15),
      );
    });

    test('monthly clamps day 31 to February', () {
      final rec = _make(frequency: 'monthly', startDate: '2025-01-31');
      expect(
        RecurringService.nextOccurrence(rec, DateTime(2025, 1, 31)),
        DateTime(2025, 2, 28),
      );
    });

    test('monthly recovers from clamped February back to the 31st', () {
      final rec = _make(frequency: 'monthly', startDate: '2025-01-31');
      expect(
        RecurringService.nextOccurrence(rec, DateTime(2025, 2, 28)),
        DateTime(2025, 3, 31),
      );
    });

    test('monthly clamps to February 29 on leap years', () {
      final rec = _make(frequency: 'monthly', startDate: '2024-01-31');
      expect(
        RecurringService.nextOccurrence(rec, DateTime(2024, 1, 31)),
        DateTime(2024, 2, 29),
      );
    });

    test('monthly honors interval', () {
      final rec =
          _make(frequency: 'monthly', interval: 2, startDate: '2025-01-15');
      expect(
        RecurringService.nextOccurrence(rec, DateTime(2025, 1, 15)),
        DateTime(2025, 3, 15),
      );
    });

    test('yearly keeps month and clamps day', () {
      final rec = _make(frequency: 'yearly', startDate: '2025-02-28');
      expect(
        RecurringService.nextOccurrence(rec, DateTime(2025, 2, 28)),
        DateTime(2026, 2, 28),
      );
    });

    test('yearly with Feb 29 anchor clamps to Feb 28 on non-leap years', () {
      final rec = _make(frequency: 'yearly', startDate: '2024-02-29');
      expect(
        RecurringService.nextOccurrence(rec, DateTime(2024, 2, 29)),
        DateTime(2025, 2, 28),
      );
    });
  });

  group('firstOccurrenceOnOrAfter', () {
    test('returns start date when reference is before it', () {
      final rec = _make(frequency: 'monthly', startDate: '2025-06-15');
      final result = RecurringService.firstOccurrenceOnOrAfter(
          rec, DateTime(2025, 1, 1));
      expect(result, DateTime(2025, 6, 15));
    });

    test('returns the next monthly occurrence on or after reference', () {
      final rec = _make(frequency: 'monthly', startDate: '2025-01-15');
      final result = RecurringService.firstOccurrenceOnOrAfter(
          rec, DateTime(2025, 1, 20));
      expect(result, DateTime(2025, 2, 15));
    });

    test('returns reference day itself when it matches the schedule', () {
      final rec = _make(frequency: 'monthly', startDate: '2025-01-15');
      final result = RecurringService.firstOccurrenceOnOrAfter(
          rec, DateTime(2025, 3, 15));
      expect(result, DateTime(2025, 3, 15));
    });

    test('returns null when the schedule ended before the reference', () {
      final rec = _make(
          frequency: 'monthly',
          startDate: '2025-01-15',
          endDate: '2025-04-15');
      final result = RecurringService.firstOccurrenceOnOrAfter(
          rec, DateTime(2025, 9, 1));
      expect(result, isNull);
    });
  });

  group('planGeneration', () {
    test('returns due occurrence when next due date is today', () {
      final rec = _make(frequency: 'monthly', startDate: '2025-01-15');
      final plan = RecurringService.planGeneration(
        rec,
        existingDates: const {},
        exceptionDates: const {},
        today: DateTime(2025, 1, 15, 10),
      );
      expect(plan.dueDates, ['2025-01-15']);
      expect(plan.nextDueDate, '2025-02-15');
      expect(plan.ended, false);
    });

    test('backfills all missed occurrences up to today', () {
      final rec = _make(frequency: 'monthly', startDate: '2025-01-15');
      final plan = RecurringService.planGeneration(
        rec,
        existingDates: const {},
        exceptionDates: const {},
        today: DateTime(2025, 4, 20),
      );
      expect(plan.dueDates, [
        '2025-01-15',
        '2025-02-15',
        '2025-03-15',
        '2025-04-15',
      ]);
      expect(plan.nextDueDate, '2025-05-15');
    });

    test('is idempotent: existing occurrences are not regenerated', () {
      final rec = _make(frequency: 'monthly', startDate: '2025-01-15');
      final plan = RecurringService.planGeneration(
        rec,
        existingDates: {'2025-01-15', '2025-02-15'},
        exceptionDates: const {},
        today: DateTime(2025, 4, 20),
      );
      expect(plan.dueDates, ['2025-03-15', '2025-04-15']);
    });

    test('skips explicitly deleted (tombstoned) occurrences', () {
      final rec = _make(frequency: 'monthly', startDate: '2025-01-15');
      final plan = RecurringService.planGeneration(
        rec,
        existingDates: const {},
        exceptionDates: {'2025-02-15'},
        today: DateTime(2025, 3, 20),
      );
      expect(plan.dueDates, ['2025-01-15', '2025-03-15']);
    });

    test('does nothing when next due date is in the future', () {
      final rec = _make(
          frequency: 'monthly',
          startDate: '2025-01-15',
          nextDueDate: '2025-06-15');
      final plan = RecurringService.planGeneration(
        rec,
        existingDates: const {},
        exceptionDates: const {},
        today: DateTime(2025, 3, 20),
      );
      expect(plan.dueDates, isEmpty);
      expect(plan.nextDueDate, '2025-06-15');
    });

    test('clamps backfilled monthly occurrences at month end', () {
      final rec = _make(
          frequency: 'monthly',
          startDate: '2025-01-31',
          nextDueDate: '2025-01-31');
      final plan = RecurringService.planGeneration(
        rec,
        existingDates: const {},
        exceptionDates: const {},
        today: DateTime(2025, 3, 31),
      );
      expect(plan.dueDates, ['2025-01-31', '2025-02-28', '2025-03-31']);
    });

    test('marks the schedule as ended past the end date', () {
      final rec = _make(
          frequency: 'monthly',
          startDate: '2025-01-15',
          endDate: '2025-03-15',
          nextDueDate: '2025-01-15');
      final plan = RecurringService.planGeneration(
        rec,
        existingDates: const {},
        exceptionDates: const {},
        today: DateTime(2025, 9, 1),
      );
      expect(plan.dueDates, ['2025-01-15', '2025-02-15', '2025-03-15']);
      expect(plan.ended, true);
      expect(plan.nextDueDate, '2025-03-15');
    });

    test('ends without generating when the end date is already past', () {
      final rec = _make(
          frequency: 'monthly',
          startDate: '2025-01-15',
          endDate: '2025-02-15',
          nextDueDate: '2025-05-15');
      final plan = RecurringService.planGeneration(
        rec,
        existingDates: const {},
        exceptionDates: const {},
        today: DateTime(2025, 5, 1),
      );
      expect(plan.dueDates, isEmpty);
      expect(plan.ended, true);
    });

    test('weekly occurrence lands on the same weekday across weeks', () {
      final rec = _make(frequency: 'weekly', startDate: '2025-01-15');
      final plan = RecurringService.planGeneration(
        rec,
        existingDates: const {},
        exceptionDates: const {},
        today: DateTime(2025, 1, 22),
      );
      expect(plan.dueDates, ['2025-01-15', '2025-01-22']);
      expect(plan.nextDueDate, '2025-01-29');
    });
  });
}
