import 'package:flutter/material.dart';

/// A small tag pill that stays readable in both light and dark themes.
///
/// The tag color is blended over the [surface] background, so the pill
/// always stands out, and the label color is computed to guarantee contrast
/// against that effective background.
class TagChip extends StatelessWidget {
  final String label;
  final Color color;
  final Color surface;
  final double fontSize;
  final FontWeight fontWeight;
  final EdgeInsetsGeometry padding;
  final BorderRadius borderRadius;

  const TagChip({
    super.key,
    required this.label,
    required this.color,
    required this.surface,
    this.fontSize = 10,
    this.fontWeight = FontWeight.w600,
    this.padding = const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
    this.borderRadius = const BorderRadius.all(Radius.circular(4)),
  });

  @override
  Widget build(BuildContext context) {
    final pillColor =
        Color.alphaBlend(color.withValues(alpha: 0.85), surface);
    final textColor = _readableTextColor(pillColor);

    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: pillColor,
        borderRadius: borderRadius,
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: textColor,
          fontSize: fontSize,
          fontWeight: fontWeight,
        ),
      ),
    );
  }

  /// Returns black or white, whichever has a higher WCAG contrast ratio
  /// (>= 4.5:1) against [background].
  static Color _readableTextColor(Color background) {
    final lum = background.computeLuminance();
    final whiteRatio = (1.05) / (lum + 0.05);
    final blackRatio = (lum + 0.05) / 0.05;
    return whiteRatio >= blackRatio ? Colors.white : Colors.black;
  }
}
