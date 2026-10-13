import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:peadra/core/theme/peadra_colors.dart';
import 'package:peadra/core/utils/nav_views.dart';
import 'package:peadra/features/dashboard/presentation/dashboard_shell_mobile.dart';

Widget buildShell({
  required int selectedIndex,
  required List<NavView> navViews,
  bool showNavLabels = false,
  ValueChanged<int>? onNavTap,
}) {
  return MaterialApp(
    home: DashboardShellMobile(
      selectedIndex: selectedIndex,
      views: List.generate(
        6,
        (i) => Text('view $i', textDirection: TextDirection.ltr),
      ),
      onNavTap: onNavTap ?? (_) {},
      onLogout: () {},
      showNavLabels: showNavLabels,
      navViews: navViews,
      colors: PeadraTheme.getColors('dark'),
    ),
  );
}

void main() {
  testWidgets('default order fills the bar and keeps the rest in the menu',
      (tester) async {
    final taps = <int>[];
    await tester.pumpWidget(buildShell(
      selectedIndex: 0,
      navViews: navViewsFor(defaultNavOrder),
      onNavTap: taps.add,
    ));

    // Bar destinations (accounts and settings are in the burger menu).
    expect(find.byIcon(Icons.dashboard), findsOneWidget); // active icon
    expect(find.byIcon(Icons.receipt_long_outlined), findsOneWidget);
    expect(find.byIcon(Icons.flag_outlined), findsOneWidget);
    expect(find.byIcon(Icons.bubble_chart_outlined), findsOneWidget);
    expect(find.byIcon(Icons.menu), findsOneWidget);

    // Opening the menu lists the destinations in the user's order.
    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();
    expect(find.text('Accounts'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);

    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    expect(taps, [5]);
  });

  testWidgets('a custom order changes which views are in the bar',
      (tester) async {
    final taps = <int>[];
    await tester.pumpWidget(buildShell(
      // 1 = transactions, which lives in the menu with this order, so the
      // burger stays highlighted.
      selectedIndex: 1,
      navViews: navViewsFor(
          'settings,accounts,categories,budgets,transactions,dashboard'
              .split(',')),
      onNavTap: taps.add,
    ));

    // Settings promoted into the first bar slot, while transactions and the
    // dashboard moved behind the burger menu.
    expect(find.byIcon(Icons.settings_outlined), findsOneWidget);
    expect(find.byIcon(Icons.flag_outlined), findsOneWidget);
    expect(find.byIcon(Icons.receipt_long_outlined), findsNothing);
    expect(find.byIcon(Icons.dashboard_outlined), findsNothing);
    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();
    expect(taps, [5]);
  });

  testWidgets('the burger item is highlighted while a menu view is shown',
      (tester) async {
    await tester.pumpWidget(buildShell(
      selectedIndex: 3, // accounts, behind the menu by default
      navViews: navViewsFor(defaultNavOrder),
    ));

    // The menu item is the selected one of the five bar entries.
    final bar = tester.widget<BottomNavigationBar>(
        find.byType(BottomNavigationBar));
    expect(bar.currentIndex, 4);
    expect(bar.items.length, 5);
  });

  testWidgets('labels are shown when the setting is on', (tester) async {
    await tester.pumpWidget(buildShell(
      selectedIndex: 0,
      navViews: navViewsFor(defaultNavOrder),
      showNavLabels: true,
    ));

    expect(find.text('Home'), findsOneWidget); // nav_dashboard
    expect(find.text('Transactions'), findsOneWidget);
    expect(find.text('Budgets'), findsOneWidget);
    expect(find.text('Categories'), findsOneWidget);
    expect(find.text('Menu'), findsOneWidget);
    // No labels by default elsewhere in the bar.
    final bar = tester.widget<BottomNavigationBar>(
        find.byType(BottomNavigationBar));
    expect(bar.items.every((i) => i.label!.isNotEmpty), isTrue);
  });

  testWidgets('a bar destination selects its view', (tester) async {
    final taps = <int>[];
    await tester.pumpWidget(buildShell(
      selectedIndex: 0,
      navViews: navViewsFor(defaultNavOrder),
      onNavTap: taps.add,
    ));

    await tester.tap(find.byIcon(Icons.receipt_long_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.bubble_chart_outlined));
    await tester.pumpAndSettle();
    expect(taps, [1, 4]); // transactions, then categories
  });
}
