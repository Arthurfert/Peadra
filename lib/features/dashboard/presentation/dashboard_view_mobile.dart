import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';

import '../../../core/i18n/translator.dart';
import '../../../core/theme/peadra_colors.dart';
import '../../../core/responsive/responsive_layout.dart';
import '../../../core/utils/chart_utils.dart';

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
      padding: ResponsiveLayout.pagePaddingAll(context),
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
    final hasFuture =
        assetsHistory.any((e) => (e['isFuture'] as bool?) ?? false);
    return Card(
      color: colors.surface,
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              runSpacing: 8,
              spacing: 12,
              children: [
                Text(
                  Translator.t('dash_total_assets'),
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: colors.text,
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildLegendDot(colors.chartAsset,
                        Translator.t('dash_total_assets')),
                    if (hasFuture) ...[
                      const SizedBox(width: 16),
                      _buildForecastLegendDot(
                          colors.chartAsset.withValues(alpha: 0.65),
                          Translator.t('dash_forecast')),
                    ],
                  ],
                ),
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
    final futureMonthSet = <String>{};
    for (final d in [...expenseData, ...incomeData]) {
      final m = d['month'] as String;
      months.add(m);
      if ((d['isFuture'] as bool?) ?? false) futureMonthSet.add(m);
    }

    final sortedMonths = months.toList()..sort();
    // Keep the last 6 known months and append every future month after
    // them, so upcoming transactions continue the chart as a forecast.
    final pastMonths =
        sortedMonths.where((m) => !futureMonthSet.contains(m)).toList();
    final futureMonths =
        sortedMonths.where((m) => futureMonthSet.contains(m)).toList();
    final displayPast = pastMonths.length > 6
        ? pastMonths.sublist(pastMonths.length - 6)
        : pastMonths;
    final displayMonths = [...displayPast, ...futureMonths];
    final displayMonthSet = displayMonths.toSet();

    double futureOf(Map<String, dynamic> d) =>
        (d['futureAmount'] as num?)?.toDouble() ?? 0.0;

    final expenseByMonth = <String, double>{};
    final expenseFutureByMonth = <String, double>{};
    for (final d in expenseData) {
      final m = d['month'] as String;
      if (displayMonthSet.contains(m)) {
        expenseByMonth[m] =
            (expenseByMonth[m] ?? 0.0) + (d['amount'] as num).toDouble();
        expenseFutureByMonth[m] =
            (expenseFutureByMonth[m] ?? 0.0) + futureOf(d);
      }
    }

    final incomeByMonth = <String, double>{};
    final incomeFutureByMonth = <String, double>{};
    for (final d in incomeData) {
      final m = d['month'] as String;
      if (displayMonthSet.contains(m)) {
        incomeByMonth[m] =
            (incomeByMonth[m] ?? 0.0) + (d['amount'] as num).toDouble();
        incomeFutureByMonth[m] =
            (incomeFutureByMonth[m] ?? 0.0) + futureOf(d);
      }
    }

    double maxY = 0.0;
    for (final m in displayMonths) {
      final e = expenseByMonth[m] ?? 0.0;
      final i = incomeByMonth[m] ?? 0.0;
      if (e > maxY) maxY = e;
      if (i > maxY) maxY = i;
    }
    if (maxY == 0.0) maxY = 1.0;

    final barGroups = <BarChartGroupData>[];
    for (int i = 0; i < displayMonths.length; i++) {
      final m = displayMonths[i];
      final expense = expenseByMonth[m] ?? 0.0;
      final income = incomeByMonth[m] ?? 0.0;

      barGroups.add(
        BarChartGroupData(
          x: i,
          barRods: [
            _buildFlowRod(
              total: income,
              future: incomeFutureByMonth[m] ?? 0.0,
              color: colors.success,
            ),
            _buildFlowRod(
              total: expense,
              future: expenseFutureByMonth[m] ?? 0.0,
              color: colors.error,
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
              final isIncome = rodIndex == 0;
              final label = isIncome
                  ? Translator.t('chart_incomes')
                  : Translator.t('chart_expenses');
              final total = isIncome
                  ? (incomeByMonth[m] ?? 0.0)
                  : (expenseByMonth[m] ?? 0.0);
              final future = isIncome
                  ? (incomeFutureByMonth[m] ?? 0.0)
                  : (expenseFutureByMonth[m] ?? 0.0);
              if (future > 0) {
                final current = total - future;
                return BarTooltipItem(
                  '$m (${Translator.t('dash_forecast')})\n'
                  '$label: ${current.toStringAsFixed(2)}\n'
                  '${Translator.t('dash_forecast')}: ${future.toStringAsFixed(2)}',
                  const TextStyle(color: Colors.white, fontSize: 12),
                );
              }
              return BarTooltipItem(
                '$m\n$label: ${total.toStringAsFixed(2)}',
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
    final futureFlags = <bool>[];

    for (int i = 0; i < assetsHistory.length; i++) {
      spots.add(FlSpot(
          i.toDouble(), (assetsHistory[i]['value'] as num).toDouble()));
      labels.add(assetsHistory[i]['label'] as String);
      futureFlags.add((assetsHistory[i]['isFuture'] as bool?) ?? false);
    }

    double minY = spots.first.y;
    double maxY = spots.first.y;
    for (final s in spots) {
      if (s.y < minY) minY = s.y;
      if (s.y > maxY) maxY = s.y;
    }
    final axis = niceAxisScale(minY, maxY);

    final lineColor = colors.chartAsset;
    final showLabelIndices = _computeLabelIndices(labels);

    // Split the series at the last known (non-future) point so future
    // transactions render as a dotted forecast continuation. The boundary
    // point belongs to both series to keep the line continuous.
    int boundary = -1;
    for (int i = 0; i < futureFlags.length; i++) {
      if (!futureFlags[i]) boundary = i;
    }
    final hasFuture = boundary >= 0 && boundary < spots.length - 1;
    final solidSpots = hasFuture ? spots.sublist(0, boundary + 1) : spots;
    final futureSpots = hasFuture ? spots.sublist(boundary) : <FlSpot>[];

    return LineChart(
      LineChartData(
        minX: 0,
        maxX: (spots.length - 1).toDouble(),
        minY: axis.min,
        maxY: axis.max,
        extraLinesData: hasFuture
            ? ExtraLinesData(
                verticalLines: [
                  VerticalLine(
                    x: boundary.toDouble(),
                    color: colors.textSecondary.withValues(alpha: 0.5),
                    strokeWidth: 1,
                    dashArray: [4, 4],
                  ),
                ],
              )
            : const ExtraLinesData(),
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
              interval: axis.interval,
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
            spots: solidSpots,
            isCurved: true,
            preventCurveOverShooting: true,
            color: lineColor,
            barWidth: 2,
            isStrokeCapRound: true,
            dotData: FlDotData(
              show: showLineDots && solidSpots.length <= 12,
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
          if (hasFuture)
            LineChartBarData(
              spots: futureSpots,
              isCurved: true,
              preventCurveOverShooting: true,
              color: lineColor.withValues(alpha: 0.65),
              barWidth: 2,
              isStrokeCapRound: true,
              dashArray: [6, 4],
              dotData: FlDotData(show: false),
              belowBarData: BarAreaData(show: false),
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

  /// Builds one inflow/outflow rod. When part of the month's amount comes
  /// from future transactions, the rod is a full-height outline (rounded
  /// corners, starting at the bottom) with the known portion repainted
  /// solid inside it — mirroring the budget projected bars, so there is no
  /// gap between the filled and outlined parts.
  BarChartRodData _buildFlowRod({
    required double total,
    required double future,
    required Color color,
  }) {
    const radius = BorderRadius.vertical(top: Radius.circular(4));
    if (future <= 0) {
      return BarChartRodData(
        toY: total,
        color: color,
        width: 12,
        borderRadius: radius,
      );
    }
    final past = total - future;
    return BarChartRodData(
      toY: total,
      color: Colors.transparent,
      width: 12,
      borderRadius: radius,
      borderSide: BorderSide(color: color, width: 1.5),
      rodStackItems: [
        if (past > 0) BarChartRodStackItem(0, past, color),
      ],
    );
  }

  Widget _buildForecastLegendDot(Color color, String label) {
    return Row(
      children: [
        SizedBox(
          width: 14,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (int i = 0; i < 3; i++)
                Container(
                  width: 3,
                  height: 3,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(1.5),
                  ),
                ),
            ],
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
