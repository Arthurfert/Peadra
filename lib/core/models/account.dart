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
  bool get isStock => type == 'stock';

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
}
