import 'package:decimal/decimal.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:peadra/core/database/database_manager.dart';
import 'package:peadra/core/models/goal.dart';
import 'package:peadra/core/providers/theme_provider.dart';
import 'package:peadra/features/budgets/presentation/budgets_view.dart';

void main() {
  sqfliteFfiInit();

  testWidgets('outdated custom goals show Delete and Edit footer actions',
      (tester) async {
    final db = DatabaseManager.instance;
    final now = DateTime.now();
    String day(int offset) =>
        now.add(Duration(days: offset)).toIso8601String().substring(0, 10);

    await tester.runAsync(() async {
      await db.openInMemoryForTest(
        userId: 'user-${DateTime.now().microsecondsSinceEpoch}',
      );
      await db.addAccount(
        'Cash',
        '#4CAF50',
        'checking',
        'EUR',
        startingAmount: Decimal.fromInt(100),
      );
      // Overdue and already completed (current 100 >= target 10).
      await db.createGoal(
        kind: BudgetGoal.kindTotalAssets,
        targetAmount: Decimal.fromInt(10),
        period: BudgetGoal.periodCustom,
        startDate: day(-30),
        deadline: day(-1),
      );
      // Still running: no footer actions.
      await db.createGoal(
        kind: BudgetGoal.kindTotalAssets,
        targetAmount: Decimal.fromInt(1000),
        period: BudgetGoal.periodCustom,
        startDate: day(0),
        deadline: day(30),
      );
    });

    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => ThemeProvider(),
        child: const MaterialApp(home: Scaffold(body: BudgetsView())),
      ),
    );

    // Let the initial async load settle.
    for (var i = 0; i < 3; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 300)),
      );
      await tester.pump();
    }
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Delete'), findsOneWidget);
    expect(find.text('Edit'), findsOneWidget);
  });
}
