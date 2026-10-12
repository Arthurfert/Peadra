import 'package:flutter/material.dart';

/// Lays out exactly four stat cards: one row of four on wide screens,
/// two rows of two on narrow screens.
///
/// Cards within a row are equalized with [IntrinsicHeight] +
/// [CrossAxisAlignment.stretch] combined: the height must come from
/// [IntrinsicHeight], because a bare stretch row inside the dashboard's
/// SingleChildScrollView (unbounded height) forces infinite-height
/// constraints onto the cards and crashes layout ("BoxConstraints forces
/// an infinite height", blank dashboard). [IntrinsicHeight] first gives
/// the row a finite tight height, which makes stretch safe.
class StatCardGrid extends StatelessWidget {
  final List<Widget> cards;

  const StatCardGrid({super.key, required this.cards})
      : assert(cards.length == 4);

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth > 600;
        if (isWide) {
          return IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (int i = 0; i < cards.length; i++) ...[
                  if (i > 0) const SizedBox(width: 12),
                  Expanded(child: cards[i]),
                ],
              ],
            ),
          );
        }
        return Column(
          children: [
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: cards[0]),
                  const SizedBox(width: 12),
                  Expanded(child: cards[1]),
                ],
              ),
            ),
            const SizedBox(height: 12),
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: cards[2]),
                  const SizedBox(width: 12),
                  Expanded(child: cards[3]),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
