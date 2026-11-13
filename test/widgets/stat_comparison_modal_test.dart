import 'package:decimal/decimal.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:peadra/core/database/database_manager.dart';
import 'package:peadra/core/providers/theme_provider.dart';
import 'package:peadra/core/theme/peadra_colors.dart';
import 'package:peadra/features/dashboard/presentation/widgets/stat_comparison_modal.dart';
import 'package:peadra/shared/widgets/peadra_modal.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  testWidgets('stat comparison dialog renders on desktop', (tester) async {
    final db = DatabaseManager.instance;
    await tester.runAsync(() async {
      db.clearEncryptionKey();
      await db.openInMemoryForTest(
          userId: 'user-${DateTime.now().microsecondsSinceEpoch}');
      final checkingId =
          (await db.addAccount('Checking', '#4CAF50', 'checking', 'EUR'))!;
      await db.addTransaction(
        date: DateTime.now().toIso8601String().substring(0, 10),
        description: 'Salary',
        amount: Decimal.fromInt(100),
        transactionType: 'income',
        accountId: checkingId,
      );
    });

    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final colors = PeadraTheme.getColors('dark');

    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => ThemeProvider(),
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => showPeadraModal(
                    context: context,
                    builder: (ctx) => PeadraModal(
                      title: Text('Income'),
                      content: StatComparisonContent(
                        kind: 'income',
                        sentence: 'You have earned 100 EUR',
                        currency: 'EUR',
                        colors: colors,
                      ),
                    ),
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pump();
    // The in-memory query needs real async, which the widget-test zone
    // suspends unless runAsync is used.
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('You have earned 100 EUR'), findsOneWidget);
    expect(find.byType(LineChart), findsOneWidget);
  });
}
