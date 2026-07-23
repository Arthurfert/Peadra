class Account {
  final int? id;
  final int userId;
  final String name;
  final String type;
  final String color;
  final String currency;
  final double startingAmount;
  final String? createdAt;

  Account({
    this.id,
    required this.userId,
    required this.name,
    this.type = 'savings',
    this.color = '#1976D2',
    this.currency = 'EUR',
    this.startingAmount = 0.0,
    this.createdAt,
  });

  bool get isChecking => type == 'checking';
  bool get isSavings => type == 'savings';

  Account copyWith({
    int? id,
    int? userId,
    String? name,
    String? type,
    String? color,
    String? currency,
    double? startingAmount,
    String? createdAt,
  }) =>
      Account(
        id: id ?? this.id,
        userId: userId ?? this.userId,
        name: name ?? this.name,
        type: type ?? this.type,
        color: color ?? this.color,
        currency: currency ?? this.currency,
        startingAmount: startingAmount ?? this.startingAmount,
        createdAt: createdAt ?? this.createdAt,
      );

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'user_id': userId,
        'name': name,
        'type': type,
        'color': color,
        'currency': currency,
        'starting_amount': startingAmount,
        if (createdAt != null) 'created_at': createdAt,
      };

  factory Account.fromMap(Map<String, dynamic> map) => Account(
        id: map['id'] as int?,
        userId: map['user_id'] as int,
        name: map['name'] as String,
        type: map['type'] as String? ?? 'savings',
        color: map['color'] as String? ?? '#1976D2',
        currency: map['currency'] as String? ?? 'EUR',
        startingAmount: (map['starting_amount'] as num?)?.toDouble() ?? 0.0,
        createdAt: map['created_at'] as String?,
      );
}

class AccountWithBalance extends Account {
  final double balance;

  AccountWithBalance({
    required super.id,
    required super.userId,
    required super.name,
    required super.type,
    required super.color,
    required super.currency,
    super.startingAmount,
    super.createdAt,
    this.balance = 0.0,
  });

  factory AccountWithBalance.fromMap(Map<String, dynamic> map) =>
      AccountWithBalance(
        id: map['id'] as int?,
        userId: map['user_id'] as int,
        name: map['name'] as String,
        type: map['type'] as String? ?? 'savings',
        color: map['color'] as String? ?? '#1976D2',
        currency: map['currency'] as String? ?? 'EUR',
        startingAmount: (map['starting_amount'] as num?)?.toDouble() ?? 0.0,
        createdAt: map['created_at'] as String?,
        balance: (map['balance'] as num?)?.toDouble() ?? 0.0,
      );
}
