class Transaction {
  final String? id;
  final String userId;
  final String? accountId;
  final String? descriptionId;
  final String? tagId;
  final String date;
  final double amount;
  final String transactionType;
  final String currency;
  final String? notes;
  final String? recurringId;
  final String? createdAt;
  final String? updatedAt;

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
  });

  bool get isIncome => transactionType == 'income';
  bool get isExpense => transactionType == 'expense';
  bool get isTransfer => transactionType == 'transfer';

  Transaction copyWith({
    String? id,
    String? userId,
    String? accountId,
    String? descriptionId,
    String? tagId,
    bool clearTag = false,
    String? date,
    double? amount,
    String? transactionType,
    String? currency,
    String? notes,
    String? recurringId,
    bool clearRecurring = false,
  }) =>
      Transaction(
        id: id ?? this.id,
        userId: userId ?? this.userId,
        accountId: accountId ?? this.accountId,
        descriptionId: descriptionId ?? this.descriptionId,
        tagId: clearTag ? null : (tagId ?? this.tagId),
        date: date ?? this.date,
        amount: amount ?? this.amount,
        transactionType: transactionType ?? this.transactionType,
        currency: currency ?? this.currency,
        notes: notes ?? this.notes,
        recurringId:
            clearRecurring ? null : (recurringId ?? this.recurringId),
        createdAt: createdAt,
        updatedAt: updatedAt,
      );

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'user_id': userId,
        'account_id': accountId,
        'description_id': descriptionId,
        'tag_id': tagId,
        'date': date,
        'amount': amount,
        'transaction_type': transactionType,
        'currency': currency,
        'notes': notes,
        'recurring_id': recurringId,
      };

  factory Transaction.fromMap(Map<String, dynamic> map) => Transaction(
        id: map['id'] as String?,
        userId: map['user_id'] as String,
        accountId: map['account_id'] as String?,
        descriptionId: map['description_id'] as String?,
        tagId: map['tag_id'] as String?,
        date: map['date'] as String,
        amount: (map['amount'] as num).toDouble(),
        transactionType: map['transaction_type'] as String,
        currency: map['currency'] as String? ?? 'EUR',
        notes: map['notes'] as String?,
        recurringId: map['recurring_id'] as String?,
        createdAt: map['created_at'] as String?,
        updatedAt: map['updated_at'] as String?,
      );
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
    this.accountName,
    this.accountColor,
    this.accountCurrency,
    this.descriptionName,
    this.tagName,
    this.tagColor,
    this.recurringFrequency,
  });

  factory TransactionWithDetails.fromMap(Map<String, dynamic> map) =>
      TransactionWithDetails(
        id: map['id'] as String?,
        userId: map['user_id'] as String,
        accountId: map['account_id'] as String?,
        descriptionId: map['description_id'] as String?,
        tagId: map['tag_id'] as String?,
        date: map['date'] as String,
        amount: (map['amount'] as num).toDouble(),
        transactionType: map['transaction_type'] as String,
        currency: map['currency'] as String? ?? 'EUR',
        notes: map['notes'] as String?,
        recurringId: map['recurring_id'] as String?,
        createdAt: map['created_at'] as String?,
        updatedAt: map['updated_at'] as String?,
        accountName: map['account_name'] as String?,
        accountColor: map['account_color'] as String?,
        accountCurrency: map['account_currency'] as String?,
        descriptionName: map['description_name'] as String?,
        tagName: map['tag_name'] as String?,
        tagColor: map['tag_color'] as String?,
        recurringFrequency: map['recurring_frequency'] as String?,
      );
}
