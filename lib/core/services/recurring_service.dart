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
    final anchor = DateTime.parse(rec.startDate);
    switch (rec.frequency) {
      case freqDaily:
        return current.add(Duration(days: rec.interval));
      case freqWeekly:
        return current.add(Duration(days: 7 * rec.interval));
      case freqMonthly:
        final dom = clampDay(anchor.day, current.year, current.month + rec.interval);
        return DateTime(current.year, current.month + rec.interval, dom);
      case freqYearly:
        final dom = clampDay(anchor.day, current.year + rec.interval, anchor.month);
        return DateTime(current.year + rec.interval, anchor.month, dom);
      default:
        return current.add(Duration(days: rec.interval));
    }
  }

  /// Returns the first occurrence of the schedule on or after [reference],
  /// or null if the schedule has no such occurrence (e.g. ended before it).
  static DateTime? firstOccurrenceOnOrAfter(
      RecurringTransaction rec, DateTime reference) {
    final start = DateTime.parse(rec.startDate);
    final end = rec.endDate != null ? DateTime.parse(rec.endDate!) : null;
    if (end != null && start.isAfter(end)) return null;
    var cursor = start;
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

  static int isoWeekday(DateTime date) => date.weekday;

  static String dateOnly(DateTime date) =>
      date.toIso8601String().substring(0, 10);

  /// Plans the next batch of occurrences for [rec].
  ///
  /// Returns the list of dates (in order) that should be created, and the
  /// template's next `next_due_date` to persist. If the schedule has reached
  /// its end date, [ended] is true and the caller should deactivate it.
  static RecurringPlan planGeneration(
    RecurringTransaction rec, {
    required Set<String> existingDates,
    required Set<String> exceptionDates,
    required DateTime today,
  }) {
    final endDate = rec.endDate != null ? DateTime.parse(rec.endDate!) : null;
    var cursor = DateTime.parse(rec.nextDueDate);

    if (endDate != null && cursor.isAfter(endDate)) {
      return RecurringPlan(dueDates: const [], nextDueDate: dateOnly(cursor), ended: true);
    }
    if (cursor.isAfter(today)) {
      return RecurringPlan(dueDates: const [], nextDueDate: dateOnly(cursor), ended: false);
    }

    final due = <String>[];
    var guard = 0;
    while (!cursor.isAfter(today)) {
      if (endDate != null && cursor.isAfter(endDate)) break;
      final dateStr = dateOnly(cursor);
      if (!existingDates.contains(dateStr) && !exceptionDates.contains(dateStr)) {
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
