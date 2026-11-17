import '../models/recurring_transaction.dart';

/// Pure date-scheduling logic for recurring transactions.
///
/// Kept free of any database access so it can be unit tested in isolation.
class RecurringService {
  RecurringService._();

  static const String freqDaily = 'daily';
  static const String freqWeekly = 'weekly';
  static const String freqMonthly = 'monthly';
  static const String freqYearly = 'yearly';

  /// Returns the occurrence following [current] for the given template.
  ///
  /// The anchor day (from `start_date`) is used for monthly/yearly schedules so
  /// that a monthly recurrence starting on the 31st keeps targeting the 31st,
  /// clamped to month length (Feb -> 28/29 -> back to 31 in March).
  static DateTime nextOccurrence(RecurringTransaction rec, DateTime current) {
    switch (rec.frequency) {
      case freqDaily:
        // Calendar arithmetic, not +24h: across a DST change the latter can
        // land on the same calendar day and emit a duplicate occurrence.
        return DateTime(current.year, current.month, current.day + rec.interval);
      case freqWeekly:
        final target = rec.dayOfWeek ?? current.weekday;
        var daysToAdd = (target - current.weekday) % 7;
        if (daysToAdd == 0) daysToAdd = 7;
        final first =
            DateTime(current.year, current.month, current.day + daysToAdd);
        return DateTime(
            first.year, first.month, first.day + 7 * (rec.interval - 1));
      case freqMonthly:
        // Prefer the day picked in the UI; fall back to the start date's day.
        final anchorDay =
            rec.dayOfMonth ?? DateTime.parse(rec.startDate).day;
        final dom = clampDay(anchorDay, current.year, current.month + rec.interval);
        return DateTime(current.year, current.month + rec.interval, dom);
      case freqYearly:
        final anchor = DateTime.parse(rec.startDate);
        final anchorDay = rec.dayOfMonth ?? anchor.day;
        final dom = clampDay(anchorDay, current.year + rec.interval, anchor.month);
        return DateTime(current.year + rec.interval, anchor.month, dom);
      default:
        return DateTime(current.year, current.month, current.day + rec.interval);
    }
  }

  /// Moves [start] forward to the first date that matches the schedule's
  /// anchor day/weekday, so a template created on the 3rd but scheduled for
  /// the 15th does not fire on the 3rd.
  static DateTime _alignToSchedule(RecurringTransaction rec, DateTime start) {
    switch (rec.frequency) {
      case freqMonthly:
        final anchorDay = rec.dayOfMonth ?? start.day;
        final sameMonth = DateTime(
            start.year, start.month, clampDay(anchorDay, start.year, start.month));
        if (!sameMonth.isBefore(start)) return sameMonth;
        final nextMonth = start.month + 1;
        return DateTime(start.year, nextMonth,
            clampDay(anchorDay, start.year, nextMonth));
      case freqYearly:
        final anchor = DateTime.parse(rec.startDate);
        final anchorDay = rec.dayOfMonth ?? anchor.day;
        final sameYear = DateTime(
            start.year, anchor.month, clampDay(anchorDay, start.year, anchor.month));
        if (!sameYear.isBefore(start)) return sameYear;
        final nextYear = start.year + 1;
        return DateTime(nextYear, anchor.month,
            clampDay(anchorDay, nextYear, anchor.month));
      case freqWeekly:
        final target = rec.dayOfWeek ?? start.weekday;
        final delta = (target - start.weekday) % 7;
        return DateTime(start.year, start.month, start.day + delta);
      default:
        return start;
    }
  }

  /// Returns the first occurrence of the schedule on or after [reference],
  /// or null if the schedule has no such occurrence (e.g. ended before it).
  static DateTime? firstOccurrenceOnOrAfter(
      RecurringTransaction rec, DateTime reference) {
    final start = DateTime.parse(rec.startDate);
    final end = rec.endDate != null ? DateTime.parse(rec.endDate!) : null;
    if (end != null && start.isAfter(end)) return null;
    var cursor = _alignToSchedule(rec, start);
    var guard = 0;
    while (cursor.isBefore(reference)) {
      final next = nextOccurrence(rec, cursor);
      if (!next.isAfter(cursor)) return null;
      cursor = next;
      if (end != null && cursor.isAfter(end)) return null;
      if (++guard > 100000) return null;
    }
    return cursor;
  }

  /// Clamps [day] to the number of days in the given month/year.
  static int clampDay(int day, int year, int month) {
    final maxDay = DateTime(year, month + 1, 0).day;
    return day > maxDay ? maxDay : day;
  }

  static String dateOnly(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  /// Plans the next batch of occurrences for [rec].
  ///
  /// Returns the list of dates (in order) that should be created, and the
  /// template's next `next_due_date` to persist. If the schedule has reached
  /// its end date, [ended] is true and the caller should deactivate it.
  ///
  /// When [lookAheadDays] is > 0, dates up to that many days into the future
  /// are also included (used to pre-generate upcoming recurring transactions
  /// so they appear in the "To come" section of the transaction view).
  static RecurringPlan planGeneration(
    RecurringTransaction rec, {
    required Set<String> existingDates,
    required Set<String> exceptionDates,
    required DateTime today,
    int lookAheadDays = 0,
  }) {
    final endDate = rec.endDate != null ? DateTime.parse(rec.endDate!) : null;
    var cursor =
        _alignToSchedule(rec, DateTime.parse(rec.nextDueDate));
    final cutoff = today.add(Duration(days: lookAheadDays));

    if (endDate != null && cursor.isAfter(endDate)) {
      return RecurringPlan(dueDates: const [], nextDueDate: dateOnly(cursor), ended: true);
    }
    if (cursor.isAfter(cutoff)) {
      return RecurringPlan(dueDates: const [], nextDueDate: dateOnly(cursor), ended: false);
    }

    final due = <String>[];
    final seen = <String>{};
    var guard = 0;
    while (!cursor.isAfter(cutoff)) {
      if (endDate != null && cursor.isAfter(endDate)) break;
      final dateStr = dateOnly(cursor);
      if (!existingDates.contains(dateStr) &&
          !exceptionDates.contains(dateStr) &&
          seen.add(dateStr)) {
        due.add(dateStr);
      }
      final next = nextOccurrence(rec, cursor);
      if (!next.isAfter(cursor)) break;
      cursor = next;
      if (++guard > 100000) break;
    }

    if (endDate != null && cursor.isAfter(endDate)) {
      return RecurringPlan(dueDates: due, nextDueDate: dateOnly(endDate), ended: true);
    }
    return RecurringPlan(dueDates: due, nextDueDate: dateOnly(cursor), ended: false);
  }
}

class RecurringPlan {
  final List<String> dueDates;
  final String nextDueDate;
  final bool ended;

  const RecurringPlan({
    required this.dueDates,
    required this.nextDueDate,
    required this.ended,
  });
}
