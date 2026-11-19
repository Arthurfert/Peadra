import 'dart:convert';

import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:peadra/core/database/database_manager.dart';
import 'package:peadra/core/services/stock_service.dart';

import '../helpers/test_helper.dart';

String _chartBody({double price = 150}) => jsonEncode({
  'chart': {
    'result': [
      {
        'meta': {
          'currency': 'EUR',
          'regularMarketPrice': price,
          'longName': 'Apple Inc.',
        },
        'timestamp': [1767225600, 1769904000],
        'indicators': {
          'quote': [
            {
              'close': [120.0, price],
            },
          ],
        },
      },
    ],
  },
});

void main() {
  setUpAll(initializeTestDatabase);
  setUp(() async {
    await DatabaseManager.instance.openInMemoryForTest(userId: 'user-1');
  });

  group('Yahoo parsing', () {
    test('parseQuote reads price, currency and monthly history', () {
      final quote = StockService.parseQuote('AAPL', jsonDecode(_chartBody()));
      expect(quote, isNotNull);
      expect(quote!.ticker, 'AAPL');
      expect(quote.name, 'Apple Inc.');
      expect(quote.currency, 'EUR');
      expect(quote.price, Decimal.fromInt(150));
      expect(quote.history.map((p) => p.date).toList(), ['2026-01', '2026-02']);
      expect(quote.history.last.close, 150);
    });

    test('parseSearch keeps equities and drops other quote types', () {
      final results = StockService.parseSearch({
        'quotes': [
          {
            'symbol': 'AAPL',
            'longname': 'Apple Inc.',
            'quoteType': 'EQUITY',
            'exchDisp': 'NASDAQ',
          },
          {'symbol': '^GSPC', 'shortname': 'S&P 500', 'quoteType': 'INDEX'},
        ],
      });
      expect(results, hasLength(1));
      expect(results.single.ticker, 'AAPL');
      expect(results.single.exchange, 'NASDAQ');
    });
  });

  group('Stock account valuation', () {
    test('cash, holdings and history use cached quotes', () async {
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
        ticker: 'AAPL',
        name: 'Apple Inc.',
        quantity: 2,
        buyPrice: Decimal.fromInt(100),
        currency: 'EUR',
        boughtAt: '2026-01-02',
        buyCost: Decimal.fromInt(200),
      );

      final service = StockService(
        client: MockClient((request) async {
          if (request.url.path.contains('/v8/finance/chart/')) {
            return http.Response(_chartBody(), 200);
          }
          return http.Response('{}', 404);
        }),
      );
      await service.refreshAll(['AAPL'], force: true);

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
          ticker: 'AAPL',
          name: 'Apple Inc.',
          quantity: 2,
          buyPrice: Decimal.fromInt(100),
          currency: 'EUR',
          boughtAt: '2026-01-02',
          buyCost: Decimal.fromInt(200),
        );

        final service = StockService(
          client: MockClient((request) async {
            return http.Response(_chartBody(), 200);
          }),
        );
        await service.refreshAll(['AAPL'], force: true);

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

        // Stock transactions never leak into the normal transaction list nor
        // into patrimony (the dashboard adds the portfolio value itself).
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
        ticker: 'AAPL',
        name: 'Apple Inc.',
        quantity: 1,
        buyPrice: Decimal.fromInt(100),
        currency: 'EUR',
        boughtAt: '2026-01-02',
        buyCost: Decimal.fromInt(100),
      );

      final service = StockService(
        client: MockClient((request) async => http.Response(_chartBody(), 200)),
      );
      await service.refreshAll(['AAPL'], force: true);
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
