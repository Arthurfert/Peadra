import 'package:decimal/decimal.dart';

class Transaction {
  final String? id;
  final String userId;
  final String? accountId;
  final String? descriptionId;
  final String? tagId;
  final String date;
  final Decimal amount;
  final String transactionType;
  final String currency;
  final String? notes;
  final String? recurringId;
  final String? createdAt;
  final String? updatedAt;
  final bool pinned;

  /// Internal stock rows (realized gains/losses) are kept out of the normal
  /// transaction list while still counting in dashboard income/expense.
  final bool isHidden;

  Transaction({
    this.id,
    required this.userId,
    this.accountId,
    this.descriptionId,
    this.tagId,
    required this.date,
    required this.amount,
    required this.transactionType,
    this.currency = 'EUR',
    this.notes,
    this.recurringId,
    this.createdAt,
    this.updatedAt,
    this.pinned = false,
    this.isHidden = false,
  });
}

class TransactionWithDetails extends Transaction {
  final String? accountName;
  final String? accountColor;
  final String? accountCurrency;
  final String? descriptionName;
  final String? tagName;
  final String? tagColor;
  final String? recurringFrequency;

  TransactionWithDetails({
    required super.id,
    required super.userId,
    super.accountId,
    super.descriptionId,
    super.tagId,
    required super.date,
    required super.amount,
    required super.transactionType,
    super.currency,
    super.notes,
    super.recurringId,
    super.createdAt,
    super.updatedAt,
    super.pinned,
    super.isHidden,
    this.accountName,
    this.accountColor,
    this.accountCurrency,
    this.descriptionName,
    this.tagName,
    this.tagColor,
    this.recurringFrequency,
  });
}
