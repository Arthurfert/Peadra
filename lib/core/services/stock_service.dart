import 'dart:async';
import 'dart:convert';

import 'package:decimal/decimal.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../database/database_manager.dart';
import '../i18n/translator.dart';
import '../models/account.dart';
import '../models/stock_line.dart';

class StockSearchResult {
  final String ticker;
  final String name;
  final String exchange;

  const StockSearchResult({
    required this.ticker,
    required this.name,
    required this.exchange,
  });
}

class StockHoldingView {
  final StockLine line;
  final int remainingQuantity;
  final Decimal latestPrice;
  final String currency;
  final Decimal value;
  final Decimal change;
  final double percent;
  final String displayName;

  const StockHoldingView({
    required this.line,
    required this.remainingQuantity,
    required this.latestPrice,
    required this.currency,
    required this.value,
    required this.change,
    required this.percent,
    required this.displayName,
  });
}

class StockSnapshot {
  final String accountId;
  final String currency;
  final String accountCurrency;
  final Decimal cash;
  final Decimal cashNative;
  final Decimal holdingsValue;
  final Decimal total;
  final Decimal netDeposits;
  final List<StockHoldingView> holdings;
  final List<Map<String, dynamic>> history;
  final Map<String, Decimal> valueByMonth;
  final bool hasQuotes;

  const StockSnapshot({
    required this.accountId,
    required this.currency,
    required this.accountCurrency,
    required this.cash,
    required this.cashNative,
    required this.holdingsValue,
    required this.total,
    required this.netDeposits,
    required this.holdings,
    required this.history,
    required this.valueByMonth,
    required this.hasQuotes,
  });

  /// Portfolio value strictly before [date]'s month. Used for the dashboard's
  /// month-ago baselines so the comparison never looks ahead.
  Decimal valueAt(String date) {
    if (date.length < 7) return Decimal.zero;
    final key = date.substring(0, 7);
    String? best;
    for (final month in valueByMonth.keys) {
      if (month.compareTo(key) >= 0) continue;
      if (best == null || month.compareTo(best) > 0) best = month;
    }
    return best == null ? Decimal.zero : valueByMonth[best]!;
  }
}

/// Fetches and caches Yahoo Finance quotes, and values the Stock Market
/// account. Cash lives inside the account: buys spend it, sells credit it.
class StockService extends ChangeNotifier {
  StockService({http.Client? client}) : _client = client ?? http.Client();

  static final StockService instance = StockService();

  static const _userAgent = 'Mozilla/5.0';
  static const _timeout = Duration(seconds: 10);
  static const _minRefreshInterval = Duration(minutes: 1);

  final http.Client _client;
  final Map<String, StockQuote> _quotes = {};
  final Map<String, Decimal> _rateCache = {};
  bool _cacheLoaded = false;
  DateTime? _lastRefresh;

  /// Latest known quote for [ticker], or null when it was never fetched.
  StockQuote? quoteFor(String ticker) => _quotes[ticker];

  Future<void> _loadCache() async {
    if (_cacheLoaded) return;
    _cacheLoaded = true;
    try {
      final cached = await DatabaseManager.instance.getStockQuotes();
      for (final entry in cached.entries) {
        _quotes.putIfAbsent(entry.key, () => entry.value);
      }
    } catch (_) {
      // A failed cache read must not prevent the network refresh.
    }
  }

  Future<void> refreshAll(Iterable<String> tickers, {bool force = false}) {
    final unique = tickers.map((t) => t.trim().toUpperCase()).toSet()
      ..removeWhere((t) => t.isEmpty);
    if (unique.isEmpty) return Future.value();
    final last = _lastRefresh;
    if (!force &&
        last != null &&
        DateTime.now().difference(last) < _minRefreshInterval) {
      return Future.value();
    }

    return () async {
      await _loadCache();
      _rateCache.clear();
      var changed = false;
      for (final ticker in unique) {
        try {
          final quote = await fetchQuote(ticker);
          if (quote == null) continue;
          _quotes[ticker] = quote;
          changed = true;
          try {
            await DatabaseManager.instance.upsertStockQuote(quote);
          } catch (_) {
            // Cache write failure only affects offline display.
          }
        } catch (_) {
          // A single failing ticker keeps its previous cached quote.
        }
      }
      _lastRefresh = DateTime.now();
      if (changed) notifyListeners();
    }();
  }

  Future<StockQuote?> fetchQuote(String ticker) async {
    final url = Uri.parse(
      'https://query1.finance.yahoo.com/v8/finance/chart/'
      '${Uri.encodeComponent(ticker)}?interval=1mo&range=max',
    );
    final response = await _client
        .get(url, headers: {'User-Agent': _userAgent})
        .timeout(_timeout);
    if (response.statusCode != 200) return null;
    return parseQuote(ticker, jsonDecode(response.body));
  }

  /// Exposed for tests: turns a Yahoo chart response into a quote.
  static StockQuote? parseQuote(String ticker, dynamic decoded) {
    try {
      final chart = (decoded as Map)['chart'] as Map?;
      final results = chart?['result'] as List?;
      if (results == null || results.isEmpty) return null;
      final data = results.first as Map;
      final meta = data['meta'] as Map? ?? const {};
      final indicators = data['indicators'] as Map?;
      final quotes = indicators?['quote'] as List?;
      final closes = quotes != null && quotes.isNotEmpty
          ? (quotes.first as Map)['close'] as List?
          : null;
      final timestamps = data['timestamp'] as List?;

      final history = <StockPricePoint>[];
      if (closes != null && timestamps != null) {
        final seen = <String>{};
        for (var i = 0; i < closes.length && i < timestamps.length; i++) {
          final close = closes[i];
          final ts = timestamps[i];
          if (close is! num || ts is! num) continue;
          final date = DateTime.fromMillisecondsSinceEpoch(
            (ts * 1000).toInt(),
            isUtc: true,
          ).toIso8601String().substring(0, 7);
          if (!seen.add(date)) {
            history[history.indexWhere((p) => p.date == date)] =
                StockPricePoint(date, close.toDouble());
          } else {
            history.add(StockPricePoint(date, close.toDouble()));
          }
        }
        history.sort((a, b) => a.date.compareTo(b.date));
      }

      final marketPrice = meta['regularMarketPrice'] as num?;
      final fallback = history.isEmpty ? 0.0 : history.last.close;
      final price = marketPrice?.toDouble() ?? fallback;
      final currency = meta['currency'] as String? ?? 'USD';
      final name =
          (meta['longName'] as String?) ??
          (meta['shortName'] as String?) ??
          ticker;

      return StockQuote(
        ticker: ticker.toUpperCase(),
        name: name,
        currency: currency,
        price: Decimal.parse(price.toString()),
        history: history,
        updatedAt: DateTime.now().toIso8601String(),
      );
    } catch (_) {
      return null;
    }
  }

  /// Yahoo symbol search used by the add-line autocomplete.
  Future<List<StockSearchResult>> search(String query) async {
    final q = query.trim();
    if (q.isEmpty) return const [];
    try {
      final url = Uri.parse(
        'https://query1.finance.yahoo.com/v1/finance/search'
        '?q=${Uri.encodeQueryComponent(q)}&quotesCount=10&newsCount=0',
      );
      final response = await _client
          .get(url, headers: {'User-Agent': _userAgent})
          .timeout(_timeout);
      if (response.statusCode != 200) return const [];
      return parseSearch(jsonDecode(response.body));
    } catch (_) {
      return const [];
    }
  }

  /// Exposed for tests: parses a Yahoo search response.
  static List<StockSearchResult> parseSearch(dynamic decoded) {
    try {
      final quotes = (decoded as Map)['quotes'] as List?;
      if (quotes == null) return const [];
      final results = <StockSearchResult>[];
      for (final raw in quotes) {
        if (raw is! Map) continue;
        final type = raw['quoteType'] as String?;
        if (type != 'EQUITY' && type != 'ETF' && type != 'MUTUALFUND') {
          continue;
        }
        final ticker = raw['symbol'] as String?;
        if (ticker == null || ticker.isEmpty) continue;
        results.add(
          StockSearchResult(
            ticker: ticker,
            name:
                (raw['longname'] as String?) ??
                (raw['shortname'] as String?) ??
                ticker,
            exchange: (raw['exchDisp'] as String?) ?? '',
          ),
        );
      }
      return results;
    } catch (_) {
      return const [];
    }
  }

  /// Values the account in [targetCurrency] using cached quotes; never hits
  /// the network. Missing quotes fall back to the purchase price.
  Future<StockSnapshot?> buildSnapshot({
    required Account account,
    required String targetCurrency,
  }) async {
    if (account.id == null) return null;
    await _loadCache();
    final db = DatabaseManager.instance;
    final lines = await db.getStockLines(account.id!, includeSold: true);
    final sales = await db.getStockSales(account.id!);
    final flows = await db.getStockCashFlows(account.id!);

    final targetFx = await _rate(account.currency, targetCurrency);
    final salesByLine = <String, List<StockSale>>{};
    for (final sale in sales) {
      (salesByLine[sale.lineId] ??= []).add(sale);
    }

    var cashNative = account.startingAmount;
    for (final flow in flows) {
      cashNative += flow.amount;
    }
    for (final sale in sales) {
      cashNative += sale.proceeds;
    }
    for (final line in lines) {
      cashNative -= line.buyCost;
    }
    final cash = cashNative * targetFx;

    final holdings = <StockHoldingView>[];
    Decimal holdingsValue = Decimal.zero;
    for (final line in lines) {
      final remaining = line.remainingQuantity;
      if (remaining <= 0) continue;
      final quote = _quotes[line.ticker];
      final latest = _latestPrice(line, quote);
      final currency = quote?.currency ?? line.currency;
      final fx = await _rate(currency, targetCurrency);
      final value = Decimal.fromInt(remaining) * latest * fx;
      final change = Decimal.fromInt(remaining) * (latest - line.buyPrice) * fx;
      final percent = line.buyPrice == Decimal.zero
          ? 0.0
          : (latest - line.buyPrice).toDouble() /
                line.buyPrice.toDouble() *
                100;
      holdings.add(
        StockHoldingView(
          line: line,
          remainingQuantity: remaining,
          latestPrice: latest,
          currency: currency,
          value: value,
          change: change,
          percent: percent,
          displayName: (quote?.name.isNotEmpty ?? false)
              ? quote!.name
              : line.name,
        ),
      );
      holdingsValue += value;
    }

    final firstDate = _firstDate(account, lines, flows);
    final history = <Map<String, dynamic>>[];
    final valueByMonth = <String, Decimal>{};
    if (firstDate != null) {
      final first = DateTime.parse(firstDate);
      var month = DateTime(first.year, first.month, 1);
      final now = DateTime.now();
      final currentMonth = DateTime(now.year, now.month, 1);
      while (!month.isAfter(currentMonth)) {
        final isCurrent = month == currentMonth;
        final monthEnd = isCurrent
            ? now.toIso8601String().substring(0, 10)
            : DateTime(
                month.year,
                month.month + 1,
                0,
              ).toIso8601String().substring(0, 10);
        final value = await _valueAtMonth(
          monthEnd: monthEnd,
          account: account,
          lines: lines,
          flows: flows,
          sales: sales,
          salesByLine: salesByLine,
          targetCurrency: targetCurrency,
          targetFx: targetFx,
          live: isCurrent,
          currentTotal: cash + holdingsValue,
        );
        final key = month.toIso8601String().substring(0, 7);
        valueByMonth[key] = value;
        history.add({
          'month': month,
          'label': _monthLabel(month.month),
          'tooltipLabel': _monthLabel(month.month),
          'value': value.toDouble(),
          'isFuture': false,
        });
        month = DateTime(month.year, month.month + 1, 1);
      }
    }

    var netDeposits = account.startingAmount;
    for (final flow in flows) {
      netDeposits += flow.amount;
    }
    netDeposits *= targetFx;

    return StockSnapshot(
      accountId: account.id!,
      currency: targetCurrency,
      accountCurrency: account.currency,
      cash: cash,
      cashNative: cashNative,
      holdingsValue: holdingsValue,
      total: cash + holdingsValue,
      netDeposits: netDeposits,
      holdings: holdings,
      history: history,
      valueByMonth: valueByMonth,
      hasQuotes: lines.any((l) => _quotes.containsKey(l.ticker)),
    );
  }

  Future<Decimal> _valueAtMonth({
    required String monthEnd,
    required Account account,
    required List<StockLine> lines,
    required List<StockCashFlow> flows,
    required List<StockSale> sales,
    required Map<String, List<StockSale>> salesByLine,
    required String targetCurrency,
    required Decimal targetFx,
    required bool live,
    required Decimal currentTotal,
  }) async {
    if (live) return currentTotal;

    var cashNative = account.startingAmount;
    for (final flow in flows) {
      if (flow.date.compareTo(monthEnd) <= 0) cashNative += flow.amount;
    }
    for (final sale in sales) {
      if (sale.date.compareTo(monthEnd) <= 0) cashNative += sale.proceeds;
    }
    for (final line in lines) {
      if (line.boughtAt.compareTo(monthEnd) <= 0) cashNative -= line.buyCost;
    }
    var value = cashNative * targetFx;

    for (final line in lines) {
      if (line.boughtAt.compareTo(monthEnd) > 0) continue;
      var remaining = line.quantity;
      for (final sale in salesByLine[line.id] ?? const <StockSale>[]) {
        if (sale.date.compareTo(monthEnd) <= 0) remaining -= sale.quantity;
      }
      if (remaining <= 0) continue;
      final quote = _quotes[line.ticker];
      final price = _historyPrice(line, quote, monthEnd.substring(0, 7));
      final currency = quote?.currency ?? line.currency;
      final fx = await _rate(currency, targetCurrency);
      value += Decimal.fromInt(remaining) * price * fx;
    }
    return value;
  }

  Decimal _latestPrice(StockLine line, StockQuote? quote) {
    if (quote != null && quote.price > Decimal.zero) return quote.price;
    if (quote != null && quote.history.isNotEmpty) {
      return Decimal.parse(quote.history.last.close.toString());
    }
    return line.buyPrice;
  }

  Decimal _historyPrice(StockLine line, StockQuote? quote, String month) {
    if (quote != null) {
      StockPricePoint? best;
      for (final point in quote.history) {
        if (point.date.compareTo(month) <= 0) {
          best = point;
        } else {
          break;
        }
      }
      if (best != null) return Decimal.parse(best.close.toString());
    }
    return line.buyPrice;
  }

  Future<Decimal> _rate(String from, String to) async {
    if (from == to) return Decimal.one;
    final key = '$from|$to';
    final cached = _rateCache[key];
    if (cached != null) return cached;
    final rate = await DatabaseManager.instance.getExchangeRate(from, to);
    final value = Decimal.parse((rate ?? 1.0).toString());
    _rateCache[key] = value;
    return value;
  }

  String? _firstDate(
    Account account,
    List<StockLine> lines,
    List<StockCashFlow> flows,
  ) {
    final dates = <String>[
      if (account.createdAt != null) account.createdAt!.substring(0, 10),
      for (final line in lines) line.boughtAt,
      for (final flow in flows) flow.date,
    ];
    if (dates.isEmpty) return null;
    dates.sort();
    return dates.first;
  }

  static String _monthLabel(int month) {
    const keys = [
      'month_jan_abbr',
      'month_feb_abbr',
      'month_mar_abbr',
      'month_apr_abbr',
      'month_may_abbr',
      'month_jun_abbr',
      'month_jul_abbr',
      'month_aug_abbr',
      'month_sep_abbr',
      'month_oct_abbr',
      'month_nov_abbr',
      'month_dec_abbr',
    ];
    return Translator.t(keys[(month - 1).clamp(0, 11)]);
  }
}
