class Transaction {
  final int? id;
  final int userId;
  final int? accountId;
  final int? descriptionId;
  final String date;
  final double amount;
  final String transactionType;
  final String currency;
  final String? notes;
  final String? createdAt;
  final String? updatedAt;

  Transaction({
    this.id,
    required this.userId,
    this.accountId,
    this.descriptionId,
    required this.date,
    required this.amount,
    required this.transactionType,
    this.currency = 'EUR',
    this.notes,
    this.createdAt,
    this.updatedAt,
  });

  bool get isIncome => transactionType == 'income';
  bool get isExpense => transactionType == 'expense';
  bool get isTransfer => transactionType == 'transfer';

  Transaction copyWith({
    int? id,
    int? userId,
    int? accountId,
    int? descriptionId,
    String? date,
    double? amount,
    String? transactionType,
    String? currency,
    String? notes,
  }) =>
      Transaction(
        id: id ?? this.id,
        userId: userId ?? this.userId,
        accountId: accountId ?? this.accountId,
        descriptionId: descriptionId ?? this.descriptionId,
        date: date ?? this.date,
        amount: amount ?? this.amount,
        transactionType: transactionType ?? this.transactionType,
        currency: currency ?? this.currency,
        notes: notes ?? this.notes,
        createdAt: createdAt,
        updatedAt: updatedAt,
      );

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'user_id': userId,
        'account_id': accountId,
        'description_id': descriptionId,
        'date': date,
        'amount': amount,
        'transaction_type': transactionType,
        'currency': currency,
        'notes': notes,
      };

  factory Transaction.fromMap(Map<String, dynamic> map) => Transaction(
        id: map['id'] as int?,
        userId: map['user_id'] as int,
        accountId: map['account_id'] as int?,
        descriptionId: map['description_id'] as int?,
        date: map['date'] as String,
        amount: (map['amount'] as num).toDouble(),
        transactionType: map['transaction_type'] as String,
        currency: map['currency'] as String? ?? 'EUR',
        notes: map['notes'] as String?,
        createdAt: map['created_at'] as String?,
        updatedAt: map['updated_at'] as String?,
      );
}

class TransactionWithDetails extends Transaction {
  final String? accountName;
  final String? accountColor;
  final String? accountCurrency;
  final String? descriptionName;

  TransactionWithDetails({
    required super.id,
    required super.userId,
    super.accountId,
    super.descriptionId,
    required super.date,
    required super.amount,
    required super.transactionType,
    super.currency,
    super.notes,
    super.createdAt,
    super.updatedAt,
    this.accountName,
    this.accountColor,
    this.accountCurrency,
    this.descriptionName,
  });

  factory TransactionWithDetails.fromMap(Map<String, dynamic> map) =>
      TransactionWithDetails(
        id: map['id'] as int?,
        userId: map['user_id'] as int,
        accountId: map['account_id'] as int?,
        descriptionId: map['description_id'] as int?,
        date: map['date'] as String,
        amount: (map['amount'] as num).toDouble(),
        transactionType: map['transaction_type'] as String,
        currency: map['currency'] as String? ?? 'EUR',
        notes: map['notes'] as String?,
        createdAt: map['created_at'] as String?,
        updatedAt: map['updated_at'] as String?,
        accountName: map['account_name'] as String?,
        accountColor: map['account_color'] as String?,
        accountCurrency: map['account_currency'] as String?,
        descriptionName: map['description_name'] as String?,
      );
}
