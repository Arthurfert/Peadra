import 'package:decimal/decimal.dart';

/// One holding in the Stock Market account.
///
/// [quantity] is the number of shares bought; [soldQuantity] is the number
/// sold through [StockSale] rows, so the line stays for history after a full
/// sale.
class StockLine {
  final String? id;
  final String userId;
  final String accountId;
  final String ticker;
  final String name;
  final int quantity;
  final Decimal buyPrice;
  final String currency;
  final String boughtAt;

  /// Cash paid at purchase, in the account currency. Stored so the cash
  /// ledger does not move when exchange rates change later.
  final Decimal buyCost;
  final int soldQuantity;
  final String? createdAt;

  StockLine({
    this.id,
    required this.userId,
    required this.accountId,
    required this.ticker,
    required this.name,
    required this.quantity,
    required this.buyPrice,
    required this.currency,
    required this.boughtAt,
    required this.buyCost,
    this.soldQuantity = 0,
    this.createdAt,
  });

  int get remainingQuantity => quantity - soldQuantity;
  bool get isActive => remainingQuantity > 0;

  static Decimal parseDecimal(dynamic value) {
    if (value == null) return Decimal.zero;
    if (value is Decimal) return value;
    if (value is num) return Decimal.parse(value.toString());
    return Decimal.tryParse(value.toString()) ?? Decimal.zero;
  }
}

class StockSale {
  final String? id;
  final String userId;
  final String accountId;
  final String lineId;
  final String date;
  final int quantity;
  final Decimal sellPrice;

  /// Amount credited to the account cash balance, in the account currency.
  final Decimal proceeds;

  /// Realized gain (positive) or loss (negative), in the account currency.
  final Decimal realizedGain;
  final String? createdAt;

  StockSale({
    this.id,
    required this.userId,
    required this.accountId,
    required this.lineId,
    required this.date,
    required this.quantity,
    required this.sellPrice,
    required this.proceeds,
    required this.realizedGain,
    this.createdAt,
  });
}

/// Broker cash deposit (positive) or withdrawal (negative).
class StockCashFlow {
  final String? id;
  final String userId;
  final String accountId;
  final String date;
  final Decimal amount;
  final String? note;
  final String? createdAt;

  StockCashFlow({
    this.id,
    required this.userId,
    required this.accountId,
    required this.date,
    required this.amount,
    this.note,
    this.createdAt,
  });
}

class StockPricePoint {
  final String date;
  final double close;

  const StockPricePoint(this.date, this.close);
}

class StockQuote {
  final String ticker;
  final String name;
  final String currency;
  final Decimal price;
  final List<StockPricePoint> history;
  final String? updatedAt;

  StockQuote({
    required this.ticker,
    required this.name,
    required this.currency,
    required this.price,
    this.history = const [],
    this.updatedAt,
  });

  StockQuote copyWith({
    String? name,
    String? currency,
    Decimal? price,
    List<StockPricePoint>? history,
    String? updatedAt,
  }) {
    return StockQuote(
      ticker: ticker,
      name: name ?? this.name,
      currency: currency ?? this.currency,
      price: price ?? this.price,
      history: history ?? this.history,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
