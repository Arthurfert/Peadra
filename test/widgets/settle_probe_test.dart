import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:peadra/shared/widgets/appear_animation.dart';

/// Regression: the entrance's settle tick must not remount the child
/// subtree. It used to flip the child slot to the raw child, re-inflating
/// the subtree and restarting any animation inside it, e.g. the accounts
/// view's odometer roll.
void main() {
  testWidgets('entrance does not recreate the child at settle',
      (tester) async {
    var creations = 0;
    void onCreate() => creations++;

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: AppearAnimation(
          key: const ValueKey('probe:0'),
          index: 0,
          child: _ProbeChild(onCreate),
        ),
      ),
    ));
    expect(creations, 1);

    await tester.pump(const Duration(milliseconds: 450));
    expect(creations, 1, reason: 'settle must not remount the child subtree');
  });
}

class _ProbeChild extends StatefulWidget {
  const _ProbeChild(this.onCreate);

  final VoidCallback onCreate;

  @override
  State<_ProbeChild> createState() => _ProbeChildState();
}

class _ProbeChildState extends State<_ProbeChild> {
  @override
  void initState() {
    super.initState();
    widget.onCreate();
  }

  @override
  Widget build(BuildContext context) => const Text('probe');
}
