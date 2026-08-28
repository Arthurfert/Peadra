import 'package:decimal/decimal.dart';

class Account {
  final String? id;
  final String userId;
  final String name;
  final String type;
  final String color;
  final String currency;
  final Decimal startingAmount;
  final String? createdAt;

  Account({
    this.id,
    required this.userId,
    required this.name,
    this.type = 'savings',
    this.color = '#1976D2',
    this.currency = 'EUR',
    Decimal? startingAmount,
    this.createdAt,
  }) : startingAmount = startingAmount ?? Decimal.zero;

  bool get isChecking => type == 'checking';
  bool get isSavings => type == 'savings';

  Account copyWith({
    String? id,
    String? userId,
    String? name,
    String? type,
    String? color,
    String? currency,
    Decimal? startingAmount,
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
        id: map['id'] as String?,
        userId: map['user_id'] as String,
        name: map['name'] as String,
        type: map['type'] as String? ?? 'savings',
        color: map['color'] as String? ?? '#1976D2',
        currency: map['currency'] as String? ?? 'EUR',
        startingAmount: parseDecimal(map['starting_amount']),
        createdAt: map['created_at'] as String?,
      );

  static Decimal parseDecimal(dynamic value) {
    if (value == null) return Decimal.zero;
    if (value is Decimal) return value;
    if (value is num) return Decimal.parse(value.toString());
    return Decimal.tryParse(value.toString()) ?? Decimal.zero;
  }
}

class AccountWithBalance extends Account {
  final Decimal balance;

  AccountWithBalance({
    required super.id,
    required super.userId,
    required super.name,
    required super.type,
    required super.color,
    required super.currency,
    super.startingAmount,
    super.createdAt,
    Decimal? balance,
  }) : balance = balance ?? Decimal.zero;

  factory AccountWithBalance.fromMap(Map<String, dynamic> map) =>
      AccountWithBalance(
        id: map['id'] as String?,
        userId: map['user_id'] as String,
        name: map['name'] as String,
        type: map['type'] as String? ?? 'savings',
        color: map['color'] as String? ?? '#1976D2',
        currency: map['currency'] as String? ?? 'EUR',
        startingAmount: Account.parseDecimal(map['starting_amount']),
        createdAt: map['created_at'] as String?,
        balance: Account.parseDecimal(map['balance']),
      );
}
