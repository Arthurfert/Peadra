import 'dart:async';
import 'dart:convert';
import 'dart:io';

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
  final String currency;
  final Decimal price;
  final bool primary;

  const StockSearchResult({
    required this.ticker,
    required this.name,
    required this.exchange,
    required this.currency,
    required this.price,
    this.primary = false,
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

/// Fetches and caches TradingView quotes and monthly history, and values the
/// Stock Market account. Cash lives inside the account: buys spend it, sells
/// credit it.
class StockService extends ChangeNotifier {
  StockService({
    http.Client? client,
    Future<Map<String, List<StockPricePoint>>> Function(Set<String>)?
    historyFetcher,
  }) : _client = client ?? http.Client(),
       _customHistoryFetcher = historyFetcher;

  static final StockService instance = StockService();

  static const _userAgent =
      'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/124 Safari/537.36';
  static const _timeout = Duration(seconds: 20);
  static const _historyTimeout = Duration(seconds: 15);
  static const _minRefreshInterval = Duration(minutes: 1);

  static const Map<String, String> _browserHeaders = {
    'User-Agent': _userAgent,
    'Accept': 'application/json, text/plain, */*',
    'Accept-Language': 'en-US,en;q=0.9',
    'Origin': 'https://www.tradingview.com',
    'Referer': 'https://www.tradingview.com/',
  };

  static const Set<String> _exchangeCodes = {
    'NASDAQ',
    'NYSE',
    'AMEX',
    'NYSEARCA',
    'BATS',
    'OTC',
    'CBOE',
    'CBOT',
    'CME',
    'COMEX',
    'NYMEX',
    'EURONEXT',
    'ENX',
    'PAR',
    'EPA',
    'AMS',
    'BRU',
    'EBR',
    'LIS',
    'MIL',
    'BIT',
    'BME',
    'MAD',
    'FRA',
    'XETRA',
    'ETR',
    'DUS',
    'BER',
    'MUN',
    'HAM',
    'STU',
    'GETTEX',
    'LSE',
    'LON',
    'LSIN',
    'AIM',
    'FIRSTNORTH',
    'NGM',
    'SWX',
    'SIX',
    'VTX',
    'VIE',
    'WBAG',
    'PRA',
    'BUD',
    'WAR',
    'WSE',
    'RSE',
    'BVB',
    'LUXSE',
    'LUX',
    'HKG',
    'TSE',
    'TYO',
    'TSX',
    'TSXV',
    'NEO',
    'ASX',
    'NZX',
    'NSE',
    'BOM',
    'BSE',
    'KRX',
    'TWSE',
    'TPE',
    'SGX',
    'SET',
    'BKK',
    'IDX',
    'JKSE',
    'KLSE',
    'MYX',
    'PSE',
    'UPCOM',
    'HNX',
    'HOSE',
    'STO',
    'CPH',
    'HEL',
    'OSL',
    'JSE',
    'BVMF',
    'B3',
    'BMV',
    'MEX',
    'BIVA',
    'BCBA',
    'IST',
    'BIST',
    'TLV',
    'ATH',
    'DFM',
    'ADX',
    'TADAWUL',
    'QSE',
    'KSE',
    'TASE',
    'EGX',
    'NGX',
    'DSE',
    'PSX',
    'MOEX',
    'INDEXSP',
    'INDEXDJX',
    'INDEXNASDAQ',
    'CRYPTOCAP',
    'BITSTAMP',
    'COINBASE',
    'BINANCE',
  };

  final http.Client _client;
  final Future<Map<String, List<StockPricePoint>>> Function(Set<String>)?
  _customHistoryFetcher;
  final Map<String, StockQuote> _quotes = {};
  final Map<String, Decimal> _rateCache = {};
  final Map<String, String> _resolvedSymbols = {};
  bool _cacheLoaded = false;
  DateTime? _lastRefresh;

  /// Latest known quote for [ticker], or null when it was never fetched.
  StockQuote? quoteFor(String ticker) => _quotes[ticker];

  /// The row label for a stored symbol: `NASDAQ:AAPL` and `AAPL:NASDAQ` both
  /// display as `AAPL`, while an old plain `AAPL` is unchanged.
  static String displayTicker(String ticker) {
    final index = ticker.indexOf(':');
    if (index < 0) return ticker;
    final first = ticker.substring(0, index).toUpperCase();
    final second = ticker.substring(index + 1);
    if (_exchangeCodes.contains(first)) return second;
    if (_exchangeCodes.contains(second.toUpperCase())) {
      return ticker.substring(0, index);
    }
    return second;
  }

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

      final resolved = <String, String>{};
      for (final ticker in unique) {
        final symbol = await _resolveTicker(ticker);
        if (symbol != null) resolved[ticker] = symbol;
      }
      if (resolved.isEmpty) {
        _lastRefresh = DateTime.now();
        return;
      }

      final symbols = resolved.values.toSet();
      final quotes = await _fetchScannerQuotes(symbols);
      final histories = await _historyFor(symbols);

      var changed = false;
      for (final entry in resolved.entries) {
        final original = entry.key;
        final symbol = entry.value;
        final scanned = quotes[symbol];
        if (scanned == null) continue;
        final existing = _quotes[original];
        final merged = StockQuote(
          ticker: original,
          symbol: symbol,
          exchange: scanned.exchange,
          name: scanned.name.isNotEmpty
              ? scanned.name
              : (existing?.name ?? symbol),
          currency: scanned.currency.isNotEmpty
              ? scanned.currency
              : (existing?.currency ?? 'USD'),
          price: scanned.price,
          history: _mergeHistory(
            existing?.history ?? const [],
            histories[symbol] ?? const [],
          ),
          updatedAt: DateTime.now().toIso8601String(),
        );
        _quotes[original] = merged;
        changed = true;
        try {
          await DatabaseManager.instance.upsertStockQuote(merged);
        } catch (_) {
          // Cache write failure only affects offline display.
        }
      }
      _lastRefresh = DateTime.now();
      if (changed) notifyListeners();
    }();
  }

  Future<Map<String, List<StockPricePoint>>> _historyFor(Set<String> symbols) {
    final custom = _customHistoryFetcher;
    if (custom != null) return custom(symbols);
    return _fetchTradingViewHistory(symbols);
  }

  Future<String?> _resolveTicker(String ticker) async {
    final cached = _resolvedSymbols[ticker];
    if (cached != null) return cached;
    final upper = ticker.trim().toUpperCase();
    if (upper.isEmpty) return null;
    final index = upper.indexOf(':');
    if (index >= 0) {
      final first = upper.substring(0, index);
      if (_exchangeCodes.contains(first)) {
        _resolvedSymbols[ticker] = upper;
        return upper;
      }
    }
    final base = index >= 0 ? upper.substring(0, index) : upper;
    final queries = <String>[upper];
    if (index >= 0) {
      queries.add(base);
      queries.add(upper.substring(index + 1));
    }
    List<StockSearchResult>? fallback;
    for (final query in queries.toSet()) {
      final results = await search(query);
      if (results.isEmpty) continue;
      fallback ??= results;
      final exact = results.where((r) {
        final i = r.ticker.indexOf(':');
        final symbol = i >= 0 ? r.ticker.substring(i + 1) : r.ticker;
        return symbol.toUpperCase() == base;
      }).toList();
      if (exact.isEmpty) continue;
      final primary = exact.where((r) => r.primary).toList();
      final pick = primary.isNotEmpty ? primary.first : exact.first;
      _resolvedSymbols[ticker] = pick.ticker;
      return pick.ticker;
    }
    if (fallback != null) {
      final primary = fallback.where((r) => r.primary).toList();
      final pick = primary.isNotEmpty ? primary.first : fallback.first;
      _resolvedSymbols[ticker] = pick.ticker;
      return pick.ticker;
    }
    return null;
  }

  /// TradingView symbol search. Returns stocks, funds and ETFs from every
  /// exchange covered by TradingView.
  Future<List<StockSearchResult>> search(String query) async {
    final q = query.trim();
    if (q.isEmpty) return const [];
    try {
      final url = Uri.parse(
        'https://symbol-search.tradingview.com/symbol_search/'
        '?text=${Uri.encodeQueryComponent(q)}'
        '&hl=1&exchange=&lang=en&type=&domain=production',
      );
      final response = await _client
          .get(url, headers: _browserHeaders)
          .timeout(_timeout);
      if (response.statusCode != 200) return const [];
      return parseSearchResults(jsonDecode(response.body));
    } catch (_) {
      return const [];
    }
  }

  /// Exposed for tests: parses the TradingView symbol-search JSON.
  static List<StockSearchResult> parseSearchResults(dynamic decoded) {
    if (decoded is! List) return const [];
    const allowedTypes = {
      'stock',
      'fund',
      'etf',
      'dr',
      'reit',
      'trust',
      'preferred',
      'closedend',
      'unit',
    };
    final results = <StockSearchResult>[];
    final seen = <String>{};
    for (final raw in decoded) {
      if (raw is! Map) continue;
      final type = (raw['type'] as String?)?.toLowerCase() ?? '';
      if (type.isNotEmpty && !allowedTypes.contains(type)) continue;
      final symbol = _stripTags((raw['symbol'] as String?) ?? '').toUpperCase();
      final source =
          ((raw['source_id'] as String?) ?? (raw['prefix'] as String?) ?? '')
              .toUpperCase();
      if (symbol.isEmpty || source.isEmpty) continue;
      final ticker = '$source:$symbol';
      if (!seen.add(ticker)) continue;
      results.add(
        StockSearchResult(
          ticker: ticker,
          name: _stripTags((raw['description'] as String?) ?? symbol),
          exchange:
              (raw['exchange'] as String?) ??
              (raw['source_id'] as String?) ??
              source,
          currency: (raw['currency_code'] as String?) ?? '',
          price: Decimal.zero,
          primary: raw['is_primary_listing'] == true,
        ),
      );
      if (results.length >= 15) break;
    }
    return results;
  }

  static String _stripTags(String value) {
    return value.replaceAll(RegExp(r'<[^>]*>'), '').trim();
  }

  Future<Map<String, StockQuote>> _fetchScannerQuotes(
    Set<String> symbols,
  ) async {
    if (symbols.isEmpty) return const {};
    try {
      final response = await _client
          .post(
            Uri.parse('https://scanner.tradingview.com/global/scan'),
            headers: {..._browserHeaders, 'Content-Type': 'application/json'},
            body: jsonEncode({
              'symbols': {
                'tickers': symbols.toList(),
                'query': {'types': []},
              },
              'columns': [
                'name',
                'close',
                'change',
                'currency',
                'description',
                'exchange',
                'type',
                'update_mode',
              ],
            }),
          )
          .timeout(_timeout);
      if (response.statusCode != 200) return const {};
      return parseScannerQuotes(jsonDecode(response.body));
    } catch (_) {
      return const {};
    }
  }

  /// Exposed for tests: parses the TradingView scanner JSON.
  static Map<String, StockQuote> parseScannerQuotes(dynamic decoded) {
    if (decoded is! Map) return const {};
    final data = decoded['data'];
    if (data is! List) return const {};
    final quotes = <String, StockQuote>{};
    for (final row in data) {
      if (row is! Map) continue;
      final symbol = row['s'] as String?;
      final values = row['d'];
      if (symbol == null || symbol.isEmpty || values is! List) continue;
      if (values.length < 5) continue;
      final close = values[1];
      if (close is! num || close <= 0) continue;
      final currency = values[3] is String ? values[3] as String : '';
      final name = values[4] is String && (values[4] as String).isNotEmpty
          ? values[4] as String
          : (values[0] is String ? values[0] as String : symbol);
      final exchange = values[5] is String ? values[5] as String : '';
      quotes[symbol] = StockQuote(
        ticker: symbol,
        symbol: symbol,
        exchange: exchange,
        name: name,
        currency: currency,
        price: Decimal.parse(close.toString()),
      );
    }
    return quotes;
  }

  Future<Map<String, List<StockPricePoint>>> _fetchTradingViewHistory(
    Set<String> symbols,
  ) async {
    if (symbols.isEmpty) return const {};
    WebSocket? socket;
    final chartSessions = <String, String>{};
    final history = <String, List<StockPricePoint>>{};
    final completed = <String>{};
    try {
      final date = DateTime.now().toIso8601String().substring(0, 10);
      socket = await WebSocket.connect(
        'wss://data.tradingview.com/socket.io/websocket'
        '?from=chart%2F&date=$date',
        headers: {
          'Origin': 'https://www.tradingview.com',
          'User-Agent': _userAgent,
        },
      ).timeout(_timeout);
      _send(socket, 'set_auth_token', ['unauthorized_user_token']);
      var index = 0;
      for (final symbol in symbols) {
        index++;
        // A free TradingView session allows one series per chart session.
        final chartId =
            'peadra_${DateTime.now().microsecondsSinceEpoch}_$index';
        chartSessions[chartId] = symbol;
        _send(socket, 'chart_create_session', [chartId, '']);
        _send(socket, 'resolve_symbol', [
          chartId,
          'symbol_1',
          '=${jsonEncode({'symbol': symbol, 'adjustment': 'splits'})}',
        ]);
        _send(socket, 'create_series', [
          chartId,
          's1',
          's1',
          'symbol_1',
          '1M',
          600,
          '',
        ]);
      }

      await for (final frame in socket.timeout(_historyTimeout)) {
        parseHistoryFrame(frame.toString(), chartSessions, history, completed);
        if (completed.length >= chartSessions.length) break;
      }
    } catch (_) {
      // Timeouts and protocol errors leave the cached history in place.
    } finally {
      try {
        await socket?.close();
      } catch (_) {}
    }
    return history;
  }

  static void _send(WebSocket socket, String method, List<dynamic> params) {
    final payload = jsonEncode({'m': method, 'p': params});
    socket.add('~m~${payload.length}~m~$payload');
  }

  /// Exposed for tests: consumes one `~m~`-framed TradingView message.
  /// [chartSessions] maps a chart session id to its symbol.
  static void parseHistoryFrame(
    String frame,
    Map<String, String> chartSessions,
    Map<String, List<StockPricePoint>> out,
    Set<String> completed,
  ) {
    for (final part in frame.split('~m~')) {
      if (!part.startsWith('{')) continue;
      dynamic decoded;
      try {
        decoded = jsonDecode(part);
      } catch (_) {
        continue;
      }
      if (decoded is! Map) continue;
      final method = decoded['m'];
      final params = decoded['p'];
      if (params is! List || params.isEmpty) continue;
      final chartId = params[0].toString();
      final symbol = chartSessions[chartId];
      if (symbol == null) continue;
      if (method == 'timescale_update' && params.length > 1) {
        final payload = params[1];
        if (payload is Map) {
          for (final entry in payload.entries) {
            final value = entry.value;
            final bars = value is Map ? value['s'] : null;
            if (bars is! List) continue;
            final byMonth = <String, double>{};
            for (final bar in bars) {
              if (bar is! Map) continue;
              final v = bar['v'];
              if (v is! List || v.length < 5) continue;
              final time = v[0];
              final close = v[4];
              if (time is! num || close is! num || close <= 0) continue;
              final date = DateTime.fromMillisecondsSinceEpoch(
                (time * 1000).toInt(),
                isUtc: true,
              ).toIso8601String().substring(0, 7);
              byMonth[date] = close.toDouble();
            }
            if (byMonth.isNotEmpty) {
              final dates = byMonth.keys.toList()..sort();
              out[symbol] = [
                for (final date in dates) StockPricePoint(date, byMonth[date]!),
              ];
            }
          }
        }
        completed.add(chartId);
      } else if (method == 'series_completed' ||
          method == 'series_error' ||
          method == 'symbol_error' ||
          method == 'critical_error') {
        completed.add(chartId);
      }
    }
  }

  static List<StockPricePoint> _mergeHistory(
    List<StockPricePoint> oldPoints,
    List<StockPricePoint> fresh,
  ) {
    // The chart is monthly. Normalize old daily Google points to one close per
    // month so a fresh monthly TradingView bar always wins.
    final byMonth = <String, double>{};
    for (final point in [...oldPoints, ...fresh]) {
      final month = point.date.length >= 7
          ? point.date.substring(0, 7)
          : point.date;
      byMonth[month] = point.close;
    }
    final months = byMonth.keys.toList()..sort();
    return [
      for (final month in months) StockPricePoint(month, byMonth[month]!),
    ];
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
    final transfers = await db.getStockTransfers(account.id!);

    final targetFx = await _rate(account.currency, targetCurrency);
    final salesByLine = <String, List<StockSale>>{};
    for (final sale in sales) {
      (salesByLine[sale.lineId] ??= []).add(sale);
    }

    var cashNative = account.startingAmount;
    for (final flow in flows) {
      cashNative += flow.amount;
    }
    for (final transfer in transfers) {
      cashNative += transfer.$2;
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

    final firstEvent = _firstDate(account, lines, flows, transfers);
    final earliestHistory = _earliestHistory(lines);
    var startDate = firstEvent;
    if (earliestHistory != null &&
        startDate != null &&
        earliestHistory.compareTo(startDate) > 0) {
      startDate = earliestHistory;
    }
    final history = <Map<String, dynamic>>[];
    final valueByMonth = <String, Decimal>{};
    if (startDate != null) {
      final first = DateTime.parse(startDate);
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
          transfers: transfers,
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
    for (final transfer in transfers) {
      netDeposits += transfer.$2;
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
    required List<(String, Decimal)> transfers,
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
    for (final transfer in transfers) {
      if (transfer.$1.compareTo(monthEnd) <= 0) cashNative += transfer.$2;
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
        final pointMonth = point.date.length >= 7
            ? point.date.substring(0, 7)
            : point.date;
        if (pointMonth.compareTo(month) <= 0) {
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

  String? _earliestHistory(List<StockLine> lines) {
    String? best;
    for (final line in lines) {
      final history = _quotes[line.ticker]?.history;
      if (history == null || history.isEmpty) continue;
      final date = history.first.date;
      if (best == null || date.compareTo(best) < 0) best = date;
    }
    return best;
  }

  String? _firstDate(
    Account account,
    List<StockLine> lines,
    List<StockCashFlow> flows,
    List<(String, Decimal)> transfers,
  ) {
    final dates = <String>[
      if (account.createdAt != null) account.createdAt!.substring(0, 10),
      for (final line in lines) line.boughtAt,
      for (final flow in flows) flow.date,
      for (final transfer in transfers) transfer.$1,
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
