import 'package:decimal/decimal.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:peadra/core/database/database_manager.dart';
import 'package:peadra/core/providers/settings_provider.dart';
import 'package:peadra/core/providers/theme_provider.dart';
import 'package:peadra/features/transactions/presentation/transactions_view.dart';

void main() {
  sqfliteFfiInit();

  testWidgets('fetches a transfer counterpart outside the visible page', (
    tester,
  ) async {
    final db = DatabaseManager.instance;
    final settings = SettingsProvider();

    // sqflite FFI does real I/O, which needs the real event loop in widget
    // tests rather than the fake-async zone.
    await tester.runAsync(() async {
      await db.openInMemoryForTest(
        userId: 'user-${DateTime.now().microsecondsSinceEpoch}',
      );
      final checking = (await db.addAccount(
        'Checking',
        '#4CAF50',
        'checking',
        'EUR',
      ))!;
      final savings = (await db.addAccount(
        'Savings',
        '#2196F3',
        'savings',
        'EUR',
      ))!;
      await db.setSetting('transactions_display_limit', '3');
      await settings.loadFromSettings(db);

      // Two newer plain rows fill the first page, pushing the transfer's
      // second leg past the display limit.
      for (var i = 0; i < 2; i++) {
        await db.addTransaction(
          date: '2020-01-02',
          description: 'Salary $i',
          amount: Decimal.fromInt(100),
          transactionType: 'income',
          accountId: checking,
        );
      }
      // Destination leg first so the source leg sorts above it (same date).
      await db.addTransaction(
        date: '2020-01-01',
        description: 'Transfer from Checking',
        amount: Decimal.fromInt(50),
        transactionType: 'income',
        accountId: savings,
        notes: 'Transfer from Checking',
      );
      await db.addTransaction(
        date: '2020-01-01',
        description: 'Transfer to Savings',
        amount: Decimal.fromInt(50),
        transactionType: 'expense',
        accountId: checking,
        notes: 'Transfer to Savings',
      );
    });

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: settings),
          ChangeNotifierProvider.value(value: ThemeProvider()),
        ],
        child: const MaterialApp(home: Scaffold(body: TransactionsView())),
      ),
    );

    // Let the initial async load settle, then let the reload triggered by the
    // display limit (and its counterpart lookup) settle too.
    for (var i = 0; i < 3; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 300)),
      );
      await tester.pump();
    }
    await tester.pump(const Duration(milliseconds: 500));

    // A merged transfer uses the swap icon. Without the counterpart fetch the
    // visible source leg renders as a plain expense (south-east) instead.
    expect(find.byIcon(Icons.swap_horiz), findsOneWidget);
  });
}
