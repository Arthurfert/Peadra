import 'package:material_ui/material_ui.dart';
import 'package:fl_chart/fl_chart.dart';

import '../../../../core/i18n/translator.dart';
import '../../../../core/theme/peadra_colors.dart';
import '../../../../core/utils/chart_utils.dart';

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

/// Precomputed data for the inflows/outflows bar chart.
class DashboardBarCache {
  final List<String> displayMonths;
  final Map<String, double> expenseByMonth;
  final Map<String, double> incomeByMonth;
  final Map<String, double> expenseFutureByMonth;
  final Map<String, double> incomeFutureByMonth;
  final double maxY;

  const DashboardBarCache({
    required this.displayMonths,
    required this.expenseByMonth,
    required this.incomeByMonth,
    required this.expenseFutureByMonth,
    required this.incomeFutureByMonth,
    required this.maxY,
  });
}

/// Precomputed data for the total-assets line chart.
class DashboardLineCache {
  final List<FlSpot> spots;
  final List<String> labels;
  final AxisScale axis;
  final int boundary;
  final bool hasFuture;
  final List<FlSpot> solidSpots;
  final List<FlSpot> futureSpots;
  final Set<int> showLabelIndices;

  const DashboardLineCache({
    required this.spots,
    required this.labels,
    required this.axis,
    required this.boundary,
    required this.hasFuture,
    required this.solidSpots,
    required this.futureSpots,
    required this.showLabelIndices,
  });
}

/// Memoises chart caches across rebuilds, rebuilding only when the query
/// result list instance changes.
class DashboardChartCache {
  DashboardChartCache({this.lineLabelLimit});

  /// When set, the line chart thins its bottom labels to at most this many.
  final int? lineLabelLimit;

  List<Map<String, dynamic>>? _cashFlowRef;
  DashboardBarCache? _barCache;
  List<Map<String, dynamic>>? _assetsRef;
  DashboardLineCache? _lineCache;

  DashboardBarCache? bar(List<Map<String, dynamic>> cashFlowData) {
    if (cashFlowData.isEmpty) return null;
    if (!identical(cashFlowData, _cashFlowRef) || _barCache == null) {
      _cashFlowRef = cashFlowData;
      _barCache = _buildBarCache(cashFlowData);
    }
    return _barCache;
  }

  DashboardLineCache? line(List<Map<String, dynamic>> assetsHistory) {
    if (assetsHistory.isEmpty) return null;
    if (!identical(assetsHistory, _assetsRef) || _lineCache == null) {
      _assetsRef = assetsHistory;
      _lineCache = _buildLineCache(assetsHistory);
    }
    return _lineCache;
  }

  DashboardBarCache _buildBarCache(List<Map<String, dynamic>> cashFlowData) {
    final expenseData = cashFlowData
        .where((d) => d['type'] == 'expense')
        .toList();
    final incomeData = cashFlowData
        .where((d) => d['type'] == 'income')
        .toList();

    final months = <String>{};
    final futureMonthSet = <String>{};
    for (final d in [...expenseData, ...incomeData]) {
      final m = d['month'] as String;
      months.add(m);
      if ((d['isFuture'] as bool?) ?? false) futureMonthSet.add(m);
    }

    final sortedMonths = months.toList()..sort();
    // Append every future month after the known ones, so upcoming
    // transactions continue the chart as a forecast.
    final pastMonths = sortedMonths
        .where((m) => !futureMonthSet.contains(m))
        .toList();
    final futureMonths = sortedMonths
        .where((m) => futureMonthSet.contains(m))
        .toList();
    final displayMonths = [...pastMonths, ...futureMonths];
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
        incomeFutureByMonth[m] = (incomeFutureByMonth[m] ?? 0.0) + futureOf(d);
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

    return DashboardBarCache(
      displayMonths: displayMonths,
      expenseByMonth: expenseByMonth,
      incomeByMonth: incomeByMonth,
      expenseFutureByMonth: expenseFutureByMonth,
      incomeFutureByMonth: incomeFutureByMonth,
      maxY: maxY,
    );
  }

  DashboardLineCache _buildLineCache(List<Map<String, dynamic>> assetsHistory) {
    final spots = <FlSpot>[];
    final labels = <String>[];
    final futureFlags = <bool>[];

    for (int i = 0; i < assetsHistory.length; i++) {
      spots.add(
        FlSpot(i.toDouble(), (assetsHistory[i]['value'] as num).toDouble()),
      );
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

    return DashboardLineCache(
      spots: spots,
      labels: labels,
      axis: axis,
      boundary: boundary,
      hasFuture: hasFuture,
      solidSpots: solidSpots,
      futureSpots: futureSpots,
      showLabelIndices: _labelIndices(labels, lineLabelLimit),
    );
  }
}

/// Indices of the line chart's bottom labels: first, last, and every label
/// that changes. When [limit] is set, more candidates are thinned to at most
/// that many evenly spaced ticks.
Set<int> _labelIndices(List<String> labels, int? limit) {
  final candidates = <int>[];
  for (int i = 0; i < labels.length; i++) {
    final show =
        i == 0 ||
        i == labels.length - 1 ||
        (labels[i].isNotEmpty && labels[i] != labels[i - 1]);
    if (show) candidates.add(i);
  }

  if (limit == null || candidates.length <= limit) {
    return candidates.toSet();
  }

  final result = <int>{};
  final step = (candidates.length - 1) / (limit - 1);
  for (int j = 0; j < limit; j++) {
    result.add(candidates[(j * step).round()]);
  }
  return result;
}

/// Inflows/outflows card: title, income/expense legend and forecast bars.
class DashboardInflowsOutflowsCard extends StatelessWidget {
  final PeadraColors colors;
  final DashboardBarCache? cache;

  const DashboardInflowsOutflowsCard({
    super.key,
    required this.colors,
    required this.cache,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      color: colors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
                    _legendDot(colors.success, Translator.t('dash_inflows')),
                    const SizedBox(width: 16),
                    _legendDot(colors.error, Translator.t('dash_outflows')),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(height: 220, child: _buildChart()),
          ],
        ),
      ),
    );
  }

  Widget _buildChart() {
    final cache = this.cache;
    if (cache == null) {
      return Center(
        child: Text(
          Translator.t('dashboard_no_data'),
          style: TextStyle(color: colors.textSecondary),
        ),
      );
    }

    final displayMonths = cache.displayMonths;
    final expenseByMonth = cache.expenseByMonth;
    final incomeByMonth = cache.incomeByMonth;
    final expenseFutureByMonth = cache.expenseFutureByMonth;
    final incomeFutureByMonth = cache.incomeFutureByMonth;
    final maxY = cache.maxY;

    // Cache month-abbr labels once per build instead of per tick per frame.
    final monthAbbrs = List<String>.generate(
      12,
      (i) => Translator.t(_monthAbbrKeys[i]),
    );
    final bottomLabels = <String>[
      for (final m in displayMonths)
        monthAbbrs[((int.tryParse(m.split('-').last) ?? 1) - 1).clamp(0, 11)],
    ];

    final barGroups = <BarChartGroupData>[];
    for (int i = 0; i < displayMonths.length; i++) {
      final m = displayMonths[i];
      final expense = expenseByMonth[m] ?? 0.0;
      final income = incomeByMonth[m] ?? 0.0;

      barGroups.add(
        BarChartGroupData(
          x: i,
          barRods: [
            _flowRod(
              total: income,
              future: incomeFutureByMonth[m] ?? 0.0,
              color: colors.success,
            ),
            _flowRod(
              total: expense,
              future: expenseFutureByMonth[m] ?? 0.0,
              color: colors.error,
            ),
          ],
        ),
      );
    }

    return RepaintBoundary(
      child: BarChart(
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
                  if (idx >= 0 && idx < bottomLabels.length) {
                    return Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        bottomLabels[idx],
                        style: TextStyle(
                          color: colors.textSecondary,
                          fontSize: 11,
                        ),
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
                reservedSize: 32,
                getTitlesWidget: (value, meta) {
                  if (value == 0) return const Text('');
                  return Text(
                    compactAxisLabel(value),
                    style: TextStyle(color: colors.textSecondary, fontSize: 10),
                  );
                },
              ),
            ),
            topTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            rightTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
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
          barGroups: barGroups,
        ),
      ),
    );
  }
}

/// Total-assets card: title, solid/forecast legend and the history line.
class DashboardTotalAssetsCard extends StatelessWidget {
  final PeadraColors colors;
  final List<Map<String, dynamic>> assetsHistory;
  final DashboardLineCache? cache;
  final bool showLineDots;
  final String? title;
  final String? legendLabel;

  const DashboardTotalAssetsCard({
    super.key,
    required this.colors,
    required this.assetsHistory,
    required this.cache,
    required this.showLineDots,
    this.title,
    this.legendLabel,
  });

  @override
  Widget build(BuildContext context) {
    final hasFuture = assetsHistory.any(
      (e) => (e['isFuture'] as bool?) ?? false,
    );
    return Card(
      color: colors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
                  title ?? Translator.t('dash_total_assets'),
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: colors.text,
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _legendDot(
                      colors.chartAsset,
                      legendLabel ?? Translator.t('dash_total_assets'),
                    ),
                    if (hasFuture) ...[
                      const SizedBox(width: 16),
                      _forecastLegendDot(
                        colors.chartAsset.withValues(alpha: 0.65),
                        Translator.t('dash_forecast'),
                      ),
                    ],
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(height: 220, child: _buildChart()),
          ],
        ),
      ),
    );
  }

  Widget _buildChart() {
    final cache = this.cache;
    if (cache == null) {
      return Center(
        child: Text(
          Translator.t('dashboard_no_data'),
          style: TextStyle(color: colors.textSecondary),
        ),
      );
    }

    final spots = cache.spots;
    final labels = cache.labels;
    final axis = cache.axis;
    final boundary = cache.boundary;
    final hasFuture = cache.hasFuture;
    final solidSpots = cache.solidSpots;
    final futureSpots = cache.futureSpots;
    final showLabelIndices = cache.showLabelIndices;

    final lineColor = colors.chartAsset;

    return RepaintBoundary(
      child: LineChart(
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
                    label =
                        (assetsHistory[idx]['tooltipLabel'] as String?) ??
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
                  if (idx >= 0 &&
                      idx < labels.length &&
                      showLabelIndices.contains(idx)) {
                    return Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        labels[idx],
                        style: TextStyle(
                          color: colors.textSecondary,
                          fontSize: 10,
                        ),
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
                reservedSize: 32,
                interval: axis.interval,
                getTitlesWidget: (value, meta) {
                  if (value == 0) return const Text('');
                  return Text(
                    compactAxisLabel(value),
                    style: TextStyle(color: colors.textSecondary, fontSize: 10),
                  );
                },
              ),
            ),
            topTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            rightTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
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
              spots: solidSpots,
              isCurved: true,
              preventCurveOverShooting: true,
              color: lineColor,
              barWidth: 2,
              isStrokeCapRound: true,
              dotData: FlDotData(
                show: showLineDots && solidSpots.length <= 12,
                getDotPainter: (spot, pct, bar, idx) => FlDotCirclePainter(
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
                dotData: const FlDotData(show: false),
                belowBarData: BarAreaData(show: false),
              ),
          ],
        ),
      ),
    );
  }
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
      Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
    ],
  );
}

Widget _forecastLegendDot(Color color, String label) {
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
      Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
    ],
  );
}

/// Builds one inflow/outflow rod. When part of the month's amount comes
/// from future transactions, the rod is a full-height outline (rounded
/// corners, starting at the bottom) with the known portion repainted
/// solid inside it — mirroring the budget projected bars, so there is no
/// gap between the filled and outlined parts.
BarChartRodData _flowRod({
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
    rodStackItems: [if (past > 0) BarChartRodStackItem(0, past, color)],
  );
}
