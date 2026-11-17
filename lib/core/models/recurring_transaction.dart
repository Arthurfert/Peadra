import 'package:decimal/decimal.dart';

class RecurringTransaction {
  final String? id;
  final String userId;
  final String? accountId;
  final String? descriptionId;
  final String? tagId;
  final Decimal amount;
  final String transactionType;
  final String currency;
  final String? notes;
  final String frequency;
  final int interval;
  final int? dayOfWeek;
  final int? dayOfMonth;
  final String startDate;
  final String? endDate;
  final String nextDueDate;
  final bool active;
  final String? createdAt;
  final String? updatedAt;

  const RecurringTransaction({
    this.id,
    required this.userId,
    this.accountId,
    this.descriptionId,
    this.tagId,
    required this.amount,
    required this.transactionType,
    this.currency = 'EUR',
    this.notes,
    required this.frequency,
    this.interval = 1,
    this.dayOfWeek,
    this.dayOfMonth,
    required this.startDate,
    this.endDate,
    required this.nextDueDate,
    this.active = true,
    this.createdAt,
    this.updatedAt,
  });
}

class RecurringTransactionWithDetails extends RecurringTransaction {
  final String? accountName;
  final String? accountColor;
  final String? accountCurrency;
  final String? descriptionName;
  final String? tagName;
  final String? tagColor;
  final int generatedCount;

  RecurringTransactionWithDetails({
    required super.id,
    required super.userId,
    super.accountId,
    super.descriptionId,
    super.tagId,
    required super.amount,
    required super.transactionType,
    super.currency,
    super.notes,
    required super.frequency,
    super.interval,
    super.dayOfWeek,
    super.dayOfMonth,
    required super.startDate,
    super.endDate,
    required super.nextDueDate,
    super.active,
    super.createdAt,
    super.updatedAt,
    this.accountName,
    this.accountColor,
    this.accountCurrency,
    this.descriptionName,
    this.tagName,
    this.tagColor,
    this.generatedCount = 0,
  });
}
