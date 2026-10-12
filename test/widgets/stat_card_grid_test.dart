import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:peadra/features/dashboard/presentation/widgets/stat_card_grid.dart';

/// Regression test: StatCardGrid lives inside the dashboard's
/// SingleChildScrollView (unbounded height). Using
/// CrossAxisAlignment.stretch on its rows crashed layout with
/// "BoxConstraints forces an infinite height" (blank dashboard), so the
/// grid equalizes with IntrinsicHeight instead. These tests pump the grid
/// in a scroll view with uneven cards and assert both survival and equal
/// heights.
Widget _stubCard(String title, {int extraLines = 0}) {
  return Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(title, maxLines: 2, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 4),
          const Text('123.45'),
          const SizedBox(height: 2),
          const Text(' ', maxLines: 1),
          for (int i = 0; i < extraLines; i++) Text('extra line $i'),
        ],
      ),
    ),
  );
}

Widget _app(List<Widget> cards) {
  return MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: StatCardGrid(cards: cards),
      ),
    ),
  );
}

List<Widget> _unevenCards() => [
      _stubCard('Short'),
      _stubCard('A much longer title that wraps', extraLines: 2),
      _stubCard('Mid', extraLines: 1),
      _stubCard('Another very long title here', extraLines: 3),
    ];

Future<void> _setSize(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
}

void main() {
  testWidgets('narrow layout builds with equal row heights', (tester) async {
    await _setSize(tester, const Size(390, 844));
    await tester.pumpWidget(_app(_unevenCards()));
    await tester.pump();
    expect(tester.takeException(), isNull);

    final heights = tester
        .widgetList<Card>(find.byType(Card))
        .map((c) => tester.getSize(find.byWidget(c)).height)
        .toList();
    expect(heights.length, 4);
    expect(heights[0], heights[1]);
    expect(heights[2], heights[3]);
  });

  testWidgets('wide layout builds with all four heights equal',
      (tester) async {
    await _setSize(tester, const Size(1280, 800));
    await tester.pumpWidget(_app(_unevenCards()));
    await tester.pump();
    expect(tester.takeException(), isNull);

    final heights = tester
        .widgetList<Card>(find.byType(Card))
        .map((c) => tester.getSize(find.byWidget(c)).height)
        .toList();
    expect(heights.length, 4);
    for (final h in heights) {
      expect(h, heights[0]);
    }
  });
}
