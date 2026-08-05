import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';

import '../../../core/i18n/translator.dart';
import '../../../core/theme/peadra_colors.dart';

const _monthAbbrKeys = [
  'month_jan_abbr',
  'month_feb_abbr',
  'month_mar_abbr',
  'month_apr_abbr',
  'month_may_abbr',
  'month_jun_abbr',
  'month_jul_abbr',
  'month_aug_abbr',
  'month_sep_abbr',
  'month_oct_abbr',
  'month_nov_abbr',
  'month_dec_abbr',
];

class DashboardViewMobile extends StatelessWidget {
  final Widget header;
  final Widget totalAsset;
  final Widget statCards;
  final Widget cashFlowSection;
  final Widget expensePie;
  final Widget incomePie;
  final Widget assetsPie;
  final PeadraColors colors;
  final List<Map<String, dynamic>> cashFlowData;
  final List<Map<String, dynamic>> assetsHistory;
  final bool showLineDots;

  const DashboardViewMobile({
    super.key,
    required this.header,
    required this.totalAsset,
    required this.statCards,
    required this.cashFlowSection,
    required this.expensePie,
    required this.incomePie,
    required this.assetsPie,
    required this.colors,
    required this.cashFlowData,
    required this.assetsHistory,
    this.showLineDots = true,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          header,
          const SizedBox(height: 24),
          totalAsset,
          const SizedBox(height: 16),
          statCards,
          const SizedBox(height: 24),
          cashFlowSection,
          const SizedBox(height: 24),
          _buildInflowsOutflowsChart(colors),
          const SizedBox(height: 16),
          _buildTotalAssetsChart(colors),
          const SizedBox(height: 24),
          expensePie,
          const SizedBox(height: 16),
          incomePie,
          const SizedBox(height: 16),
          assetsPie,
          const SizedBox(height: 80),
        ],
      ),
    );
  }

  Widget _buildInflowsOutflowsChart(PeadraColors colors) {
    return Card(
      color: colors.surface,
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  Translator.t('dash_inflows_outflows'),
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: colors.text,
                  ),
                ),
                Row(
                  children: [
                    _buildLegendDot(colors.success,
                        Translator.t('dash_inflows')),
                    const SizedBox(width: 16),
                    _buildLegendDot(colors.error,
                        Translator.t('dash_outflows')),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 220,
              child: _buildBarChart(colors),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTotalAssetsChart(PeadraColors colors) {
    return Card(
      color: colors.surface,
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  Translator.t('dash_total_assets'),
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: colors.text,
                  ),
                ),
                _buildLegendDot(colors.chartAsset,
                    Translator.t('dash_total_assets')),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 220,
              child: _buildLineChart(colors),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBarChart(PeadraColors colors) {
    if (cashFlowData.isEmpty) {
      return Center(
        child: Text(Translator.t('dashboard_no_data'),
            style: TextStyle(color: colors.textSecondary)),
      );
    }

    final expenseData =
        cashFlowData.where((d) => d['type'] == 'expense').toList();
    final incomeData =
        cashFlowData.where((d) => d['type'] == 'income').toList();

    final months = <String>{};
    for (final d in expenseData) {
      months.add(d['month'] as String);
    }
    for (final d in incomeData) {
      months.add(d['month'] as String);
    }

    final sortedMonths = months.toList()..sort();
    final displayMonths = sortedMonths.length > 6
        ? sortedMonths.sublist(sortedMonths.length - 6)
        : sortedMonths;
    final displayMonthSet = displayMonths.toSet();

    final expenseByMonth = <String, double>{};
    for (final d in expenseData) {
      final m = d['month'] as String;
      if (displayMonthSet.contains(m)) {
        expenseByMonth[m] =
            (expenseByMonth[m] ?? 0) + (d['amount'] as double);
      }
    }

    final incomeByMonth = <String, double>{};
    for (final d in incomeData) {
      final m = d['month'] as String;
      if (displayMonthSet.contains(m)) {
        incomeByMonth[m] =
            (incomeByMonth[m] ?? 0) + (d['amount'] as double);
      }
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
              toY: income,
              color: colors.success,
              width: 12,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(4)),
            ),
            BarChartRodData(
              toY: expense,
              color: colors.error,
              width: 12,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(4)),
            ),
          ],
        ),
      );
    }

    return BarChart(
      BarChartData(
        alignment: BarChartAlignment.spaceAround,
        maxY: maxY * 1.2,
        minY: 0,
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipItem: (group, groupIndex, rod, rodIndex) {
              final m = displayMonths[group.x];
              final label = rodIndex == 0
                  ? Translator.t('chart_incomes')
                  : Translator.t('chart_expenses');
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
                  final monthNum =
                      int.tryParse(m.split('-').last) ?? 1;
                  final label = Translator.t(
                      _monthAbbrKeys[(monthNum - 1).clamp(0, 11)]);
                  return Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      label,
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
    );
  }

  Widget _buildLineChart(PeadraColors colors) {
    if (assetsHistory.isEmpty) {
      return Center(
        child: Text(Translator.t('dashboard_no_data'),
            style: TextStyle(color: colors.textSecondary)),
      );
    }

    final spots = <FlSpot>[];
    final labels = <String>[];

    for (int i = 0; i < assetsHistory.length; i++) {
      spots.add(FlSpot(
          i.toDouble(), assetsHistory[i]['value'] as double));
      labels.add(assetsHistory[i]['label'] as String);
    }

    double minY = spots.first.y;
    double maxY = spots.first.y;
    for (final s in spots) {
      if (s.y < minY) minY = s.y;
      if (s.y > maxY) maxY = s.y;
    }

    final range = maxY - minY;
    if (range == 0) {
      minY -= 1;
      maxY += 1;
    } else {
      minY -= range * 0.1;
      maxY += range * 0.1;
    }

    final lineColor = colors.chartAsset;
    final showLabelIndices = _computeLabelIndices(labels);

    return LineChart(
      LineChartData(
        minX: 0,
        maxX: (spots.length - 1).toDouble(),
        minY: minY,
        maxY: maxY,
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipItems: (spots) {
              return spots.map((s) {
                final idx = s.x.toInt();
                String label;
                if (idx < assetsHistory.length) {
                  label = (assetsHistory[idx]['tooltipLabel'] as String?) ??
                      (assetsHistory[idx]['label'] as String? ?? '');
                } else {
                  label = idx < labels.length ? labels[idx] : '';
                }
                return LineTooltipItem(
                  '$label\n${s.y.toStringAsFixed(2)}',
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
              interval: 1,
              getTitlesWidget: (value, meta) {
                final idx = value.toInt();
                if (idx >= 0 && idx < labels.length && showLabelIndices.contains(idx)) {
                  return Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      labels[idx],
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
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            preventCurveOverShooting: true,
            color: lineColor,
            barWidth: 2,
            isStrokeCapRound: true,
            dotData: FlDotData(
              show: showLineDots && spots.length <= 12,
              getDotPainter: (spot, pct, bar, idx) =>
                  FlDotCirclePainter(
                radius: 3,
                color: lineColor,
                strokeWidth: 1.5,
                strokeColor: Colors.white,
              ),
            ),
            belowBarData: BarAreaData(
              show: true,
              color: lineColor.withValues(alpha: 0.1),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLegendDot(Color color, String label) {
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
        Text(label,
            style:
                const TextStyle(fontSize: 12, color: Colors.grey)),
      ],
    );
  }

  static const int _maxAxisLabels = 5;

  Set<int> _computeLabelIndices(List<String> labels) {
    final candidates = <int>[];
    for (int i = 0; i < labels.length; i++) {
      final label = labels[i];
      final show = i == 0 ||
          i == labels.length - 1 ||
          (label.isNotEmpty && label != labels[i - 1]);
      if (show) candidates.add(i);
    }

    if (candidates.length <= _maxAxisLabels) {
      return candidates.toSet();
    }

    final result = <int>{};
    final step = (candidates.length - 1) / (_maxAxisLabels - 1);
    for (int j = 0; j < _maxAxisLabels; j++) {
      result.add(candidates[(j * step).round()]);
    }
    return result;
  }
}
