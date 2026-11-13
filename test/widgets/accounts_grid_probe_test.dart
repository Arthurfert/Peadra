import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:peadra/features/dashboard/presentation/dashboard_shell.dart';
import 'package:peadra/shared/widgets/appear_animation.dart';

/// A view shaped like AccountsView: signal listener -> epoch -> keyed items
/// in a GridView inside the keep-alive stack.
class GridViewProbe extends StatefulWidget {
  const GridViewProbe({super.key});

  @override
  State<GridViewProbe> createState() => _GridViewProbeState();
}

class _GridViewProbeState extends State<GridViewProbe> {
  int epoch = 0;
  final ValueNotifier<int> signal = LazyKeepAliveStack.activationSignals[3];

  @override
  void initState() {
    super.initState();
    signal.addListener(_bump);
  }

  void _bump() => setState(() => epoch++);

  @override
  void dispose() {
    signal.removeListener(_bump);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 1,
        childAspectRatio: 2.4,
      ),
      itemCount: 3,
      itemBuilder: (context, i) => AppearAnimation(
        key: ValueKey('probe:$i:$epoch'),
        index: i,
        child: Text('card $i'),
      ),
    );
  }
}

class Harness extends StatefulWidget {
  const Harness({super.key});

  @override
  State<Harness> createState() => HarnessState();
}

class HarnessState extends State<Harness> {
  int selected = 0;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Column(
          children: [
            Row(
              children: [
                for (final i in [0, 1, 3])
                  TextButton(
                    onPressed: () => setState(() => selected = i),
                    child: Text('go $i'),
                  ),
              ],
            ),
            Expanded(
              child: LazyKeepAliveStack(
                views: const [
                  Text('dash'),
                  Text('txn'),
                  Text('budget'),
                  GridViewProbe(),
                ],
                selectedIndex: selected,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

void main() {
  setUp(AppearAnimation.resetCreatedCount);

  testWidgets('refocus plays exactly once per activation', (tester) async {
    await tester.pumpWidget(const Harness());

    await tester.tap(find.text('go 3'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(AppearAnimation.createdCount, 3, reason: 'first visit');

    // Leave to a numerically smaller slot and come back.
    await tester.tap(find.text('go 1'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(AppearAnimation.createdCount, 3, reason: 'hidden view must not replay');

    await tester.tap(find.text('go 3'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(AppearAnimation.createdCount, 6, reason: 'exactly one replay');

    // Second round, also through the dashboard slot behind it.
    await tester.tap(find.text('go 0'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text('go 3'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(AppearAnimation.createdCount, 9, reason: 'exactly one replay');
  });
}
