class RecurringTransaction {
  final int? id;
  final int userId;
  final int? accountId;
  final int? descriptionId;
  final int? tagId;
  final double amount;
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

  bool get isIncome => transactionType == 'income';
  bool get isExpense => transactionType == 'expense';

  RecurringTransaction copyWith({
    int? id,
    int? userId,
    int? accountId,
    int? descriptionId,
    int? tagId,
    bool clearTag = false,
    double? amount,
    String? transactionType,
    String? currency,
    String? notes,
    String? frequency,
    int? interval,
    int? dayOfWeek,
    int? dayOfMonth,
    String? startDate,
    String? endDate,
    bool clearEndDate = false,
    String? nextDueDate,
    bool? active,
  }) =>
      RecurringTransaction(
        id: id ?? this.id,
        userId: userId ?? this.userId,
        accountId: accountId ?? this.accountId,
        descriptionId: descriptionId ?? this.descriptionId,
        tagId: clearTag ? null : (tagId ?? this.tagId),
        amount: amount ?? this.amount,
        transactionType: transactionType ?? this.transactionType,
        currency: currency ?? this.currency,
        notes: notes ?? this.notes,
        frequency: frequency ?? this.frequency,
        interval: interval ?? this.interval,
        dayOfWeek: dayOfWeek ?? this.dayOfWeek,
        dayOfMonth: dayOfMonth ?? this.dayOfMonth,
        startDate: startDate ?? this.startDate,
        endDate: clearEndDate ? null : (endDate ?? this.endDate),
        nextDueDate: nextDueDate ?? this.nextDueDate,
        active: active ?? this.active,
        createdAt: createdAt,
        updatedAt: updatedAt,
      );

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'user_id': userId,
        'account_id': accountId,
        'description_id': descriptionId,
        'tag_id': tagId,
        'amount': amount,
        'transaction_type': transactionType,
        'currency': currency,
        'notes': notes,
        'frequency': frequency,
        'interval': interval,
        'day_of_week': dayOfWeek,
        'day_of_month': dayOfMonth,
        'start_date': startDate,
        'end_date': endDate,
        'next_due_date': nextDueDate,
        'active': active ? 1 : 0,
      };

  factory RecurringTransaction.fromMap(Map<String, dynamic> map) =>
      RecurringTransaction(
        id: map['id'] as int?,
        userId: map['user_id'] as int,
        accountId: map['account_id'] as int?,
        descriptionId: map['description_id'] as int?,
        tagId: map['tag_id'] as int?,
        amount: (map['amount'] as num).toDouble(),
        transactionType: map['transaction_type'] as String,
        currency: map['currency'] as String? ?? 'EUR',
        notes: map['notes'] as String?,
        frequency: map['frequency'] as String,
        interval: map['interval'] as int? ?? 1,
        dayOfWeek: map['day_of_week'] as int?,
        dayOfMonth: map['day_of_month'] as int?,
        startDate: map['start_date'] as String,
        endDate: map['end_date'] as String?,
        nextDueDate: map['next_due_date'] as String,
        active: (map['active'] as int? ?? 1) == 1,
        createdAt: map['created_at'] as String?,
        updatedAt: map['updated_at'] as String?,
      );
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

  factory RecurringTransactionWithDetails.fromMap(Map<String, dynamic> map) =>
      RecurringTransactionWithDetails(
        id: map['id'] as int?,
        userId: map['user_id'] as int,
        accountId: map['account_id'] as int?,
        descriptionId: map['description_id'] as int?,
        tagId: map['tag_id'] as int?,
        amount: (map['amount'] as num).toDouble(),
        transactionType: map['transaction_type'] as String,
        currency: map['currency'] as String? ?? 'EUR',
        notes: map['notes'] as String?,
        frequency: map['frequency'] as String,
        interval: map['interval'] as int? ?? 1,
        dayOfWeek: map['day_of_week'] as int?,
        dayOfMonth: map['day_of_month'] as int?,
        startDate: map['start_date'] as String,
        endDate: map['end_date'] as String?,
        nextDueDate: map['next_due_date'] as String,
        active: (map['active'] as int? ?? 1) == 1,
        createdAt: map['created_at'] as String?,
        updatedAt: map['updated_at'] as String?,
        accountName: map['account_name'] as String?,
        accountColor: map['account_color'] as String?,
        accountCurrency: map['account_currency'] as String?,
        descriptionName: map['description_name'] as String?,
        tagName: map['tag_name'] as String?,
        tagColor: map['tag_color'] as String?,
        generatedCount: map['generated_count'] as int? ?? 0,
      );
}
