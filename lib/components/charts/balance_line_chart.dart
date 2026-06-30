import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';

import '../../components/theme/paedra_colors.dart';
import '../../i18n/translator.dart';

class BalanceLineChart extends StatelessWidget {
  final List<FlSpot> spots;
  final PeadraColors colors;
  final String title;
  final bool showArea;

  const BalanceLineChart({
    super.key,
    required this.spots,
    required this.colors,
    this.title = '',
    this.showArea = true,
  });

  @override
  Widget build(BuildContext context) {
    if (spots.isEmpty) {
      return Center(
        child: Text(Translator.t('dashboard_no_data'),
            style: TextStyle(color: colors.textSecondary)),
      );
    }

    double minY = spots.first.y;
    double maxY = spots.first.y;
    for (final s in spots) {
      if (s.y < minY) minY = s.y;
      if (s.y > maxY) maxY = s.y;
    }

    // Pad Y axis
    final range = maxY - minY;
    if (range == 0) {
      minY -= 1;
      maxY += 1;
    } else {
      minY -= range * 0.1;
      maxY += range * 0.1;
    }

    final isPositive = maxY >= 0;
    final lineColor = isPositive ? colors.incomeIcon : colors.expenseIcon;

    return Column(
      children: [
        if (title.isNotEmpty) ...[
          Text(title,
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: colors.text)),
          const SizedBox(height: 8),
        ],
        Expanded(
          child: LineChart(
            LineChartData(
              minY: minY,
              maxY: maxY,
              lineTouchData: LineTouchData(
                touchTooltipData: LineTouchTooltipData(
                  getTooltipItems: (spots) {
                    return spots.map((s) {
                      return LineTooltipItem(
                        s.y.toStringAsFixed(2),
                        const TextStyle(color: Colors.white, fontSize: 12),
                      );
                    }).toList();
                  },
                ),
              ),
              titlesData: FlTitlesData(
                show: true,
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    getTitlesWidget: (value, meta) {
                      final idx = value.toInt();
                      if (idx >= 0 && idx < spots.length) {
                        return Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            spots[idx].x.toInt().toString(),
                            style: TextStyle(
                                color: colors.textSecondary, fontSize: 10),
                          ),
                        );
                      }
                      return const Text('');
                    },
                  ),
                ),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 50,
                    getTitlesWidget: (value, meta) {
                      if (value == 0) return const Text('');
                      return Text(
                        value >= 1000
                            ? '${(value / 1000).toStringAsFixed(1)}k'
                            : value.toStringAsFixed(0),
                        style: TextStyle(
                            color: colors.textSecondary, fontSize: 10),
                      );
                    },
                  ),
                ),
                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
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
                  spots: spots,
                  isCurved: true,
                  preventCurveOverShooting: true,
                  color: lineColor,
                  barWidth: 2,
                  isStrokeCapRound: true,
                  dotData: FlDotData(
                    show: spots.length <= 12,
                    getDotPainter: (spot, pct, bar, idx) => FlDotCirclePainter(
                      radius: 3,
                      color: lineColor,
                      strokeWidth: 1.5,
                      strokeColor: Colors.white,
                    ),
                  ),
                  belowBarData: showArea
                      ? BarAreaData(
                          show: true,
                          color: lineColor.withValues(alpha: 0.1),
                        )
                      : BarAreaData(show: false),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
