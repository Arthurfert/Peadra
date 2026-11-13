import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:peadra/features/dashboard/presentation/dashboard_shell.dart';

void main() {
  setUp(() {
    for (final signal in LazyKeepAliveStack.activationSignals) {
      signal.value = 0;
    }
  });

  testWidgets('views stay mounted across switches and refocus bumps the '
      'activation signal', (tester) async {
    Widget shell(int selected) => MaterialApp(
          home: Scaffold(
            body: LazyKeepAliveStack(
              views: const [Text('A'), Text('B')],
              selectedIndex: selected,
            ),
          ),
        );

    await tester.pumpWidget(shell(0));
    expect(LazyKeepAliveStack.activationSignals[0].value, 0);
    expect(find.text('B'), findsNothing,
        reason: 'unvisited views stay unbuilt (lazy)');

    await tester.pumpWidget(shell(1));
    await tester.pump();
    expect(LazyKeepAliveStack.activationSignals[1].value, 1);
    expect(LazyKeepAliveStack.activationSignals[0].value, 0,
        reason: 'leaving a view does not bump it');
    expect(find.text('A', skipOffstage: false), findsOneWidget,
        reason: 'visited views stay mounted, only hidden');

    await tester.pumpWidget(shell(0));
    await tester.pump();
    expect(LazyKeepAliveStack.activationSignals[0].value, 1);
    expect(LazyKeepAliveStack.activationSignals[1].value, 1);

    await tester.pumpWidget(shell(0));
    await tester.pump();
    expect(LazyKeepAliveStack.activationSignals[0].value, 1,
        reason: 'staying on the same view must not re-trigger the signal');
  });
}
