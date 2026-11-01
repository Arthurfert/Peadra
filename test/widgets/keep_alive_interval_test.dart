import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:peadra/features/dashboard/presentation/dashboard_shell.dart';

/// Regression: rapid navigation (two tab changes inside one frame interval)
/// used to fire several activation signal bumps — the interval guard skips
/// every change after the first instead of keeping only the latest, so the
/// refocus animation never fired. One bump per navigation must stay.
void main() {
  setUp(() {
    for (final signal in LazyKeepAliveStack.activationSignals) {
      signal.value = 0;
    }
  });

  Future<void> pumpShell(WidgetTester tester, int selected) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: LazyKeepAliveStack(
          views: const [Text('A'), Text('B'), Text('C'), Text('D')],
          selectedIndex: selected,
        ),
      ),
    ));
  }

  testWidgets('rapid navigation keeps exactly one bump per navigation',
      (tester) async {
    await pumpShell(tester, 0);

    // Navigate twice inside the same frame interval.
    await pumpShell(tester, 2);
    await pumpShell(tester, 3);
    await tester.pump();

    expect(LazyKeepAliveStack.activationSignals[2].value, 1,
        reason: 'slot 2 leaves, one bump');
    expect(LazyKeepAliveStack.activationSignals[3].value, 1,
        reason: 'slot 3 entered once, exactly one bump');
  });

  testWidgets(
      'navigation within an interval while already-active does not skip '
      'the entry bump', (tester) async {
    await pumpShell(tester, 3);
    await tester.pump();
    final before = LazyKeepAliveStack.activationSignals[3].value;

    // Leave and return immediately: two navigations, none sharing an
    // interval with a previous one.
    await pumpShell(tester, 1);
    await pumpShell(tester, 3);
    await tester.pump();

    expect(LazyKeepAliveStack.activationSignals[3].value, before + 1,
        reason: 'return trip replays the refocus signal exactly once');
  });
}
