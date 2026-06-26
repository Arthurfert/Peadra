class RecurringTransaction {
  final int? id;
  final int userId;
  final String description;
  final double amount;
  final int? accountId;
  final String transactionType;
  final String frequency;
  final int interval;
  final String startDate;
  final String nextDueDate;
  final String? endDate;
  final String? lastGenerated;
  final bool active;

  RecurringTransaction({
    this.id,
    required this.userId,
    required this.description,
    required this.amount,
    this.accountId,
    required this.transactionType,
    required this.frequency,
    this.interval = 1,
    required this.startDate,
    required this.nextDueDate,
    this.endDate,
    this.lastGenerated,
    this.active = true,
  });

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'user_id': userId,
        'description': description,
        'amount': amount,
        'account_id': accountId,
        'transaction_type': transactionType,
        'frequency': frequency,
        'interval': interval,
        'start_date': startDate,
        'next_due_date': nextDueDate,
        'end_date': endDate,
        'last_generated': lastGenerated,
        'active': active ? 1 : 0,
      };

  factory RecurringTransaction.fromMap(Map<String, dynamic> map) =>
      RecurringTransaction(
        id: map['id'] as int?,
        userId: map['user_id'] as int,
        description: map['description'] as String,
        amount: (map['amount'] as num).toDouble(),
        accountId: map['account_id'] as int?,
        transactionType: map['transaction_type'] as String,
        frequency: map['frequency'] as String,
        interval: map['interval'] as int? ?? 1,
        startDate: map['start_date'] as String,
        nextDueDate: map['next_due_date'] as String,
        endDate: map['end_date'] as String?,
        lastGenerated: map['last_generated'] as String?,
        active: map['active'] == 1 || map['active'] == true,
      );

  RecurringTransaction copyWith({
    int? id,
    int? userId,
    String? description,
    double? amount,
    int? accountId,
    String? transactionType,
    String? frequency,
    int? interval,
    String? startDate,
    String? nextDueDate,
    String? endDate,
    bool? active,
  }) =>
      RecurringTransaction(
        id: id ?? this.id,
        userId: userId ?? this.userId,
        description: description ?? this.description,
        amount: amount ?? this.amount,
        accountId: accountId ?? this.accountId,
        transactionType: transactionType ?? this.transactionType,
        frequency: frequency ?? this.frequency,
        interval: interval ?? this.interval,
        startDate: startDate ?? this.startDate,
        nextDueDate: nextDueDate ?? this.nextDueDate,
        endDate: endDate ?? this.endDate,
        lastGenerated: lastGenerated,
        active: active ?? this.active,
      );
}
