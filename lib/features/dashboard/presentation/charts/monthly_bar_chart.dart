import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';

import '../../../../core/theme/paedra_colors.dart';
import '../../../../core/i18n/translator.dart';

class MonthlyBarChart extends StatelessWidget {
  final List<Map<String, dynamic>> data;
  final PeadraColors colors;

  const MonthlyBarChart({
    super.key,
    required this.data,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) {
      return Center(
        child: Text(Translator.t('dashboard_no_data'),
            style: TextStyle(color: colors.textSecondary)),
      );
    }

    final expenseData = data.where((d) => d['type'] == 'expense').toList();
    final incomeData = data.where((d) => d['type'] == 'income').toList();

    final months = <String>{};
    for (final d in expenseData) {
      months.add(d['month'] ?? '');
    }
    for (final d in incomeData) {
      months.add(d['month'] ?? '');
    }

    final sortedMonths = months.toList()..sort();
    final displayMonths = sortedMonths.length > 6
        ? sortedMonths.sublist(sortedMonths.length - 6)
        : sortedMonths;

    final expenseByMonth = <String, double>{};
    for (final d in expenseData) {
      final m = d['month'] as String;
      expenseByMonth[m] = (expenseByMonth[m] ?? 0) + (d['amount'] as double);
    }

    final incomeByMonth = <String, double>{};
    for (final d in incomeData) {
      final m = d['month'] as String;
      incomeByMonth[m] = (incomeByMonth[m] ?? 0) + (d['amount'] as double);
    }

    double maxY = 0;
    for (final m in displayMonths) {
      final e = expenseByMonth[m] ?? 0;
      final i = incomeByMonth[m] ?? 0;
      if (e > maxY) maxY = e;
      if (i > maxY) maxY = i;
    }
    if (maxY == 0) maxY = 1;

    final barGroups = <BarChartGroupData>[];
    for (int i = 0; i < displayMonths.length; i++) {
      final m = displayMonths[i];
      final expense = expenseByMonth[m] ?? 0;
      final income = incomeByMonth[m] ?? 0;

      barGroups.add(
        BarChartGroupData(
          x: i,
          barRods: [
            BarChartRodData(
              toY: expense,
              color: colors.expenseIcon,
              width: 12,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(4)),
            ),
            BarChartRodData(
              toY: income,
              color: colors.incomeIcon,
              width: 12,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(4)),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _legendDot(colors.expenseIcon, Translator.t('chart_expenses')),
            const SizedBox(width: 16),
            _legendDot(colors.incomeIcon, Translator.t('chart_incomes')),
          ],
        ),
        const SizedBox(height: 12),
        Expanded(
          child: BarChart(
            BarChartData(
              alignment: BarChartAlignment.spaceAround,
              maxY: maxY * 1.2,
              minY: 0,
              barTouchData: BarTouchData(
                touchTooltipData: BarTouchTooltipData(
                  getTooltipItem: (group, groupIndex, rod, rodIndex) {
                    final m = displayMonths[group.x];
                    final label = rodIndex == 0
                        ? Translator.t('chart_expenses')
                        : Translator.t('chart_incomes');
                    return BarTooltipItem(
                      '$m\n$label: ${rod.toY.toStringAsFixed(2)}',
                      const TextStyle(color: Colors.white, fontSize: 12),
                    );
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
                      if (idx >= 0 && idx < displayMonths.length) {
                        final m = displayMonths[idx];
                        return Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            m.length > 3 ? m.substring(0, 3) : m,
                            style: TextStyle(
                                color: colors.textSecondary, fontSize: 11),
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
                topTitles:
                    const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles:
                    const AxisTitles(sideTitles: SideTitles(showTitles: false)),
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
              barGroups: barGroups,
            ),
          ),
        ),
      ],
    );
  }

  Widget _legendDot(Color color, String label) {
    return Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 12)),
      ],
    );
  }
}
