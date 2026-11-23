import 'dart:convert';

import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:peadra/core/database/database_manager.dart';
import 'package:peadra/core/models/stock_line.dart';
import 'package:peadra/core/services/stock_service.dart';

import '../helpers/test_helper.dart';

const _searchBody = '''
[
  {"symbol":"<em>TTE</em>","description":"TotalEnergies SE","type":"stock","exchange":"Euronext Paris","source_id":"EURONEXT","currency_code":"EUR","is_primary_listing":true},
  {"symbol":"<em>TTE</em>","description":"TotalEnergies SE","type":"stock","exchange":"NYSE","source_id":"NYSE","currency_code":"USD"}
]
''';

const _scannerBody = '''
{"totalCount":2,"data":[
  {"s":"NASDAQ:AAPL","d":["AAPL",150,-1.0,"USD","Apple Inc","NASDAQ","stock","delayed_streaming_900"]},
  {"s":"EURONEXT:TTE","d":["TTE",78.19,-1.2,"EUR","TotalEnergies SE","EURONEXT","stock","delayed_streaming_900"]}
]}
''';

String _historyFrame() {
  final jan = DateTime.utc(2025, 1, 1).millisecondsSinceEpoch ~/ 1000;
  final feb = DateTime.utc(2025, 2, 1).millisecondsSinceEpoch ~/ 1000;
  final payload = jsonEncode({
    'm': 'timescale_update',
    'p': [
      'cs',
      {
        's1': {
          's': [
            {
              'v': [jan, 100, 110, 90, 120, 1000],
            },
            {
              'v': [feb, 100, 160, 90, 150, 1000],
            },
          ],
        },
      },
    ],
  });
  return '~m~${payload.length}~m~$payload';
}

MockClient _mockClient() {
  return MockClient((request) async {
    if (request.url.host == 'scanner.tradingview.com') {
      return http.Response(_scannerBody, 200);
    }
    if (request.url.host == 'symbol-search.tradingview.com') {
      return http.Response(_searchBody, 200);
    }
    return http.Response('{}', 404);
  });
}

Future<Map<String, List<StockPricePoint>>> _fakeHistory(Set<String> symbols) {
  return Future.value({
    'NASDAQ:AAPL': [
      const StockPricePoint('2025-01', 120),
      const StockPricePoint('2025-02', 150),
    ],
  });
}

void main() {
  setUpAll(initializeTestDatabase);
  setUp(() async {
    await DatabaseManager.instance.openInMemoryForTest(userId: 'user-1');
  });

  group('TradingView parsing', () {
    test('search keeps exchange listings and strips highlight tags', () {
      final results = StockService.parseSearchResults(jsonDecode(_searchBody));
      expect(results, hasLength(2));
      expect(results.first.ticker, 'EURONEXT:TTE');
      expect(results.first.name, 'TotalEnergies SE');
      expect(results.first.currency, 'EUR');
      expect(results.first.primary, isTrue);
      expect(results.last.ticker, 'NYSE:TTE');
      expect(results.last.primary, isFalse);
    });

    test('scanner reads price, currency and exchange', () {
      final quotes = StockService.parseScannerQuotes(jsonDecode(_scannerBody));
      final aapl = quotes['NASDAQ:AAPL'];
      expect(aapl, isNotNull);
      expect(aapl!.name, 'Apple Inc');
      expect(aapl.exchange, 'NASDAQ');
      expect(aapl.currency, 'USD');
      expect(aapl.price, Decimal.fromInt(150));
    });

    test('history frame becomes daily closes', () {
      final out = <String, List<StockPricePoint>>{};
      final completed = <String>{};
      StockService.parseHistoryFrame(
        _historyFrame(),
        {'cs': 'NASDAQ:AAPL'},
        out,
        completed,
      );
      expect(completed, contains('cs'));
      expect(out['NASDAQ:AAPL'], isNotNull);
      expect(out['NASDAQ:AAPL']!.first.date, '2025-01-01');
      expect(out['NASDAQ:AAPL']!.last.close, 150);
    });

    test('displayTicker handles TradingView, Google and plain symbols', () {
      expect(StockService.displayTicker('NASDAQ:AAPL'), 'AAPL');
      expect(StockService.displayTicker('AAPL:NASDAQ'), 'AAPL');
      expect(StockService.displayTicker('EURONEXT:TTE'), 'TTE');
      expect(StockService.displayTicker('AAPL'), 'AAPL');
    });
  });

  group('Stock account valuation', () {
    test('cash, holdings and history use TradingView data', () async {
      final db = DatabaseManager.instance;
      final accountId = await db.addAccount(
        'Broker',
        '#1976D2',
        'stock',
        'EUR',
        startingAmount: Decimal.fromInt(1000),
      );
      await db.addStockLine(
        accountId: accountId!,
        ticker: 'NASDAQ:AAPL',
        name: 'Apple Inc.',
        quantity: 2,
        buyPrice: Decimal.fromInt(100),
        currency: 'EUR',
        boughtAt: '2026-01-02',
        buyCost: Decimal.fromInt(200),
      );

      final service = StockService(
        client: _mockClient(),
        historyFetcher: _fakeHistory,
      );
      await service.refreshAll(['NASDAQ:AAPL'], force: true);

      final account = (await db.getStockAccount())!;
      final snapshot = await service.buildSnapshot(
        account: account,
        targetCurrency: 'EUR',
      );

      expect(snapshot, isNotNull);
      expect(snapshot!.cash, Decimal.fromInt(800));
      expect(snapshot.holdingsValue, Decimal.fromInt(300));
      expect(snapshot.total, Decimal.fromInt(1100));
      expect(snapshot.netDeposits, Decimal.fromInt(1000));
      expect(snapshot.holdings.single.percent, closeTo(50, 0.0001));
      expect(snapshot.history, isNotEmpty);
      expect(snapshot.valueByMonth.containsKey('2026-01'), isTrue);
    });

    test('holdings are ordered by decreasing added value', () async {
      final db = DatabaseManager.instance;
      final accountId = await db.addAccount(
        'Broker',
        '#1976D2',
        'stock',
        'EUR',
      );
      await db.addStockLine(
        accountId: accountId!,
        ticker: 'EURONEXT:TTE',
        name: 'TotalEnergies SE',
        quantity: 1,
        buyPrice: Decimal.fromInt(100),
        currency: 'EUR',
        boughtAt: '2026-01-02',
        buyCost: Decimal.fromInt(100),
      );
      await db.addStockLine(
        accountId: accountId,
        ticker: 'NASDAQ:AAPL',
        name: 'Apple Inc.',
        quantity: 1,
        buyPrice: Decimal.fromInt(100),
        currency: 'EUR',
        boughtAt: '2026-01-03',
        buyCost: Decimal.fromInt(100),
      );

      final service = StockService(
        client: _mockClient(),
        historyFetcher: _fakeHistory,
      );
      await service.refreshAll(['EURONEXT:TTE', 'NASDAQ:AAPL'], force: true);
      final account = (await db.getStockAccount())!;
      final snapshot = await service.buildSnapshot(
        account: account,
        targetCurrency: 'EUR',
      );

      expect(snapshot, isNotNull);
      expect(snapshot!.holdings, hasLength(2));
      expect(snapshot.holdings.first.line.ticker, 'NASDAQ:AAPL');
      expect(snapshot.holdings.last.line.ticker, 'EURONEXT:TTE');
    });

    test('search returns all matching listings', () async {
      final service = StockService(client: _mockClient());
      final results = await service.search('TotalEnergies');
      expect(results, hasLength(2));
      expect(results.first.ticker, 'EURONEXT:TTE');
      expect(results.first.primary, isTrue);
    });

    test(
      'selling books realized gain and hides the stock transaction',
      () async {
        final db = DatabaseManager.instance;
        final accountId = await db.addAccount(
          'Broker',
          '#1976D2',
          'stock',
          'EUR',
          startingAmount: Decimal.fromInt(1000),
        );
        final lineId = await db.addStockLine(
          accountId: accountId!,
          ticker: 'NASDAQ:AAPL',
          name: 'Apple Inc.',
          quantity: 2,
          buyPrice: Decimal.fromInt(100),
          currency: 'EUR',
          boughtAt: '2026-01-02',
          buyCost: Decimal.fromInt(200),
        );

        final service = StockService(
          client: _mockClient(),
          historyFetcher: _fakeHistory,
        );
        await service.refreshAll(['NASDAQ:AAPL'], force: true);

        final today = DateTime.now().toIso8601String().substring(0, 10);
        final sale = await db.sellStockLine(
          lineId: lineId!,
          quantity: 1,
          sellPrice: Decimal.fromInt(150),
          date: today,
          accountCurrency: 'EUR',
        );
        expect(sale, isNotNull);
        expect(sale!.realizedGain, Decimal.fromInt(50));

        final account = (await db.getStockAccount())!;
        final snapshot = await service.buildSnapshot(
          account: account,
          targetCurrency: 'EUR',
        );
        expect(snapshot!.cash, Decimal.fromInt(950));
        expect(snapshot.holdingsValue, Decimal.fromInt(150));
        expect(snapshot.total, Decimal.fromInt(1100));

        expect(await db.getTransactions(), isEmpty);
        expect(await db.getTotalPatrimony(), Decimal.zero);

        final summary = await db.getMonthlySummary();
        expect(summary['income'], Decimal.fromInt(50));

        final lines = await db.getStockLines(accountId);
        expect(lines.single.remainingQuantity, 1);
        final allLines = await db.getStockLines(accountId, includeSold: true);
        expect(allLines.single.soldQuantity, 1);
      },
    );

    test(
      'cash deposits and withdrawals are standard visible transfers',
      () async {
        final db = DatabaseManager.instance;
        final checkingId = await db.addAccount(
          'Checking',
          '#4CAF50',
          'checking',
          'EUR',
          startingAmount: Decimal.fromInt(1000),
        );
        final stockId = await db.addAccount(
          'Broker',
          '#1976D2',
          'stock',
          'EUR',
        );
        final today = DateTime.now().toIso8601String().substring(0, 10);

        expect(
          await db.addTransfer(
            sourceId: checkingId!,
            destId: stockId!,
            amount: Decimal.fromInt(500),
            date: today,
          ),
          isTrue,
        );

        final txns = await db.getTransactions();
        expect(txns, hasLength(2));
        expect(
          txns.any(
            (t) => t.transactionType == 'expense' && t.accountId == checkingId,
          ),
          isTrue,
        );
        expect(
          txns.any(
            (t) => t.transactionType == 'income' && t.accountId == stockId,
          ),
          isTrue,
        );
        final transfers = await db.getStockTransfers(stockId);
        expect(transfers, hasLength(1));
        expect(transfers.single.$2, Decimal.fromInt(500));

        final service = StockService(
          client: _mockClient(),
          historyFetcher: _fakeHistory,
        );
        final account = (await db.getStockAccount())!;
        var snapshot = await service.buildSnapshot(
          account: account,
          targetCurrency: 'EUR',
        );
        expect(snapshot!.cashNative, Decimal.fromInt(500));
        expect(snapshot.netDeposits, Decimal.fromInt(500));
        expect(await db.getTotalPatrimony(), Decimal.fromInt(500));

        expect(
          await db.addTransfer(
            sourceId: stockId,
            destId: checkingId,
            amount: Decimal.fromInt(200),
            date: today,
          ),
          isTrue,
        );
        snapshot = await service.buildSnapshot(
          account: account,
          targetCurrency: 'EUR',
        );
        expect(snapshot!.cashNative, Decimal.fromInt(300));
        expect(snapshot.netDeposits, Decimal.fromInt(300));
        expect(await db.getTotalPatrimony(), Decimal.fromInt(700));
        expect(await db.getTransactions(), hasLength(4));
      },
    );

    test('deleting an unsold line refunds its cash', () async {
      final db = DatabaseManager.instance;
      final accountId = await db.addAccount(
        'Broker',
        '#1976D2',
        'stock',
        'EUR',
        startingAmount: Decimal.fromInt(1000),
      );
      final lineId = await db.addStockLine(
        accountId: accountId!,
        ticker: 'NASDAQ:AAPL',
        name: 'Apple Inc.',
        quantity: 1,
        buyPrice: Decimal.fromInt(100),
        currency: 'EUR',
        boughtAt: '2026-01-02',
        buyCost: Decimal.fromInt(100),
      );

      final service = StockService(
        client: _mockClient(),
        historyFetcher: _fakeHistory,
      );
      await service.refreshAll(['NASDAQ:AAPL'], force: true);
      final account = (await db.getStockAccount())!;
      expect(
        (await service.buildSnapshot(
          account: account,
          targetCurrency: 'EUR',
        ))!.cash,
        Decimal.fromInt(900),
      );

      expect(await db.deleteStockLine(lineId!), isTrue);
      expect(
        (await service.buildSnapshot(
          account: account,
          targetCurrency: 'EUR',
        ))!.cash,
        Decimal.fromInt(1000),
      );
      expect(await db.getStockLines(accountId), isEmpty);
    });
  });

  group('accounts', () {
    test(
      'stock accounts are excluded from the standard account list',
      () async {
        final db = DatabaseManager.instance;
        await db.addAccount('Broker', '#1976D2', 'stock', 'EUR');
        await db.addAccount('Checking', '#4CAF50', 'checking', 'EUR');

        final standard = await db.getAllAccounts();
        expect(standard.map((a) => a.type), ['checking']);
        final all = await db.getAllAccounts(includeStock: true);
        expect(all.map((a) => a.type).toSet(), {'checking', 'stock'});
      },
    );

    test('only one active stock account can exist', () async {
      final db = DatabaseManager.instance;
      expect(
        await db.addAccount('Broker', '#1976D2', 'stock', 'EUR'),
        isNotNull,
      );
      expect(
        await db.addAccount('Broker 2', '#1976D2', 'stock', 'EUR'),
        isNull,
      );
    });
  });
}
