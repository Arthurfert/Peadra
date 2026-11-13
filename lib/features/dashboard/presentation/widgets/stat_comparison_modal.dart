import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../../core/database/database_manager.dart';
import '../../../../core/i18n/translator.dart';
import '../../../../core/responsive/responsive_layout.dart';
import '../../../../core/services/currency_service.dart';
import '../../../../core/theme/peadra_colors.dart';
import 'package:decimal/decimal.dart';

/// Body of the stat-card comparison modal: the plain-language sentence
/// explaining the card percentage, then last month (grey, full month) and
/// this month (accent, up to today) drawn on top of each other.
class StatComparisonContent extends StatefulWidget {
  final String kind;
  final String sentence;
  final String currency;
  final PeadraColors colors;

  const StatComparisonContent({
    super.key,
    required this.kind,
    required this.sentence,
    required this.currency,
    required this.colors,
  });

  @override
  State<StatComparisonContent> createState() => _StatComparisonContentState();
}

class _StatComparisonContentState extends State<StatComparisonContent> {
  late final Future<Map<String, dynamic>> _series =
      DatabaseManager.instance.getStatComparisonSeries(kind: widget.kind);

  @override
  Widget build(BuildContext context) {
    final colors = widget.colors;
    // On desktop the host AlertDialog measures its content with
    // IntrinsicWidth, while fl_chart's LayoutBuilder cannot report intrinsic
    // dimensions (the dialog would lay out blank). Pinning a finite width
    // stops the intrinsic query before it reaches the chart. The phone sheet
    // already provides a bounded width, so it keeps the full width.
    final width = ResponsiveLayout.isPhone(context)
        ? null
        : math.min(420.0, MediaQuery.sizeOf(context).width - 96);
    return SizedBox(
      width: width,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.sentence,
            style: TextStyle(fontSize: 14, height: 1.4, color: colors.text),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 200,
            child: FutureBuilder<Map<String, dynamic>>(
              future: _series,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(
                    child: Text(
                      Translator.t('dashboard_no_data'),
                      style: TextStyle(color: colors.textSecondary),
                    ),
                  );
                }
                if (!snapshot.hasData) {
                  return Center(
                    child: SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: colors.accent,
                      ),
                    ),
                  );
                }
                final previous =
                    (snapshot.data!['previous'] as List).cast<double>();
                final current =
                    (snapshot.data!['current'] as List).cast<double>();
                final isBalance = snapshot.data!['isBalance'] as bool;
                return _buildChart(previous, current, isBalance);
              },
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildLegendDot(colors.textSecondary.withValues(alpha: 0.55),
                  Translator.t('stat_cmp_prev_month')),
              const SizedBox(width: 16),
              _buildLegendDot(
                  colors.accent, Translator.t('stat_cmp_this_month')),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildChart(
      List<double> previous, List<double> current, bool isBalance) {
    final colors = widget.colors;
    final maxDays =
        previous.length > current.length ? previous.length : current.length;
    double maxValue = previous.isEmpty ? 0 : previous.reduce((a, b) => a > b ? a : b);
    for (final v in current) {
      if (v > maxValue) maxValue = v;
    }
    double minValue = previous.isEmpty ? 0 : previous.reduce((a, b) => a < b ? a : b);
    for (final v in current) {
      if (v < minValue) minValue = v;
    }

    // Balances animate around their own level, flows grow from zero.
    final double minY;
    final double maxY;
    if (isBalance) {
      final range = maxValue - minValue;
      final padding = range == 0 ? 1.0 : range * 0.15;
      minY = minValue - padding;
      maxY = maxValue + padding;
    } else {
      minY = 0;
      maxY = maxValue == 0 ? 1.0 : maxValue * 1.15;
    }

    return LineChart(
      LineChartData(
        minX: 0,
        maxX: (maxDays - 1).toDouble(),
        minY: minY,
        maxY: maxY,
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipItems: (spots) => spots.map((s) {
              return LineTooltipItem(
                '${s.x.toInt() + 1} : ${CurrencyService.formatAmount(Decimal.parse(s.y.toStringAsFixed(2)), widget.currency)}',
                const TextStyle(color: Colors.white, fontSize: 12),
              );
            }).toList(),
          ),
        ),
        titlesData: FlTitlesData(
          leftTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              interval: 1,
              reservedSize: 22,
              getTitlesWidget: (value, meta) {
                final day = value.toInt();
                // Day labels every week keep the axis readable.
                if (day % 7 != 0 || day >= maxDays) {
                  return const SizedBox.shrink();
                }
                return Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    '${day + 1}',
                    style: TextStyle(color: colors.textSecondary, fontSize: 10),
                  ),
                );
              },
            ),
          ),
        ),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          getDrawingHorizontalLine: (value) => FlLine(
            color: colors.borderColor.withValues(alpha: 0.3),
            strokeWidth: 1,
          ),
        ),
        borderData: FlBorderData(show: false),
        lineBarsData: [
          LineChartBarData(
            spots: [
              for (var i = 0; i < previous.length; i++)
                FlSpot(i.toDouble(), previous[i]),
            ],
            isCurved: true,
            preventCurveOverShooting: true,
            color: colors.textSecondary.withValues(alpha: 0.55),
            barWidth: 2,
            dotData: const FlDotData(show: false),
          ),
          LineChartBarData(
            spots: [
              for (var i = 0; i < current.length; i++)
                FlSpot(i.toDouble(), current[i]),
            ],
            isCurved: true,
            preventCurveOverShooting: true,
            color: colors.accent,
            barWidth: 2.5,
            isStrokeCapRound: true,
            dotData: const FlDotData(show: false),
          ),
        ],
      ),
    );
  }

  Widget _buildLegendDot(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(label,
            style: const TextStyle(fontSize: 12, color: Colors.grey)),
      ],
    );
  }
}
