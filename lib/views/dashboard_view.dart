import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:fl_chart/fl_chart.dart';

import '../i18n/translator.dart';
import '../providers/theme_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/auth_provider.dart';
import '../database/database_manager.dart';
import '../components/theme/paedra_colors.dart';
import '../services/currency_service.dart';
import '../components/charts/category_pie_chart.dart';
import '../responsive/responsive_layout.dart';

class DashboardView extends StatefulWidget {
  const DashboardView({super.key});

  @override
  State<DashboardView> createState() => _DashboardViewState();
}

class _DashboardViewState extends State<DashboardView> {
  final _db = DatabaseManager.instance;
  double _balance = 0;
  double _savings = 0;
  double _previousBalance = 0;
  double _previousIncome = 0;
  double _previousExpenses = 0;
  Map<String, double> _monthlySummary = {};
  List<Map<String, dynamic>> _accountsDistribution = [];
  List<Map<String, dynamic>> _cashFlowData = [];
  List<Map<String, dynamic>> _assetsHistory = [];
  Map<String, double> _monthlyExpenses = {};
  Map<String, double> _monthlyIncomes = {};
  bool _loading = true;
  int _selectedMonths = 6;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final results = await Future.wait([
      _db.getBalance(),
      _db.getSavingsTotal(),
      _db.getMonthlySummary(),
      _db.getAccountsDistribution(),
      _db.getCashFlowData(months: _selectedMonths),
      _db.getAssetsHistory(months: _selectedMonths),
      _db.getCurrentMonthDistribution(transactionType: 'expense'),
      _db.getCurrentMonthDistribution(transactionType: 'income'),
      _db.getMonthlySummary(year: DateTime.now().year, month: DateTime.now().month - 1),
    ]);

    if (mounted) {
      setState(() {
        _balance = results[0] as double;
        _savings = results[1] as double;
        _monthlySummary = results[2] as Map<String, double>;
        _accountsDistribution = results[3] as List<Map<String, dynamic>>;
        _cashFlowData = results[4] as List<Map<String, dynamic>>;
        _assetsHistory = results[5] as List<Map<String, dynamic>>;
        _monthlyExpenses = results[6] as Map<String, double>;
        _monthlyIncomes = results[7] as Map<String, double>;
        final prevSummary = results[8] as Map<String, double>;
        _previousBalance = prevSummary['balance'] ?? 0;
        _previousIncome = prevSummary['income'] ?? 0;
        _previousExpenses = prevSummary['expenses'] ?? 0;
        _loading = false;
      });
    }
  }

  Future<void> _loadChartData() async {
    final results = await Future.wait([
      _db.getCashFlowData(months: _selectedMonths),
      _db.getAssetsHistory(months: _selectedMonths),
    ]);

    if (mounted) {
      setState(() {
        _cashFlowData = results[0] as List<Map<String, dynamic>>;
        _assetsHistory = results[1] as List<Map<String, dynamic>>;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeName = context.watch<ThemeProvider>().themeName;
    final colors = PeadraTheme.getColors(themeName);
    final currency = context.watch<SettingsProvider>().currency;
    final username = context.watch<AuthProvider>().username;

    if (_loading) {
      return Center(
        child: CircularProgressIndicator(color: colors.accent),
      );
    }

    final isPhone = ResponsiveLayout.isPhone(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
              // Header
              Text(
                Translator.t('dash_title'),
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: colors.text,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${Translator.t("dash_welcome")}$username${Translator.t("dash_overview")}',
                style: TextStyle(
                  fontSize: 14,
                  color: colors.textSecondary,
                ),
              ),
              const SizedBox(height: 24),

              // Stat cards
              _buildStatCards(colors, currency),
              const SizedBox(height: 24),

              // Cash Flow section
              _buildCashFlowSection(colors),
              const SizedBox(height: 24),

              // Charts row
              if (isPhone) ...[
                _buildInflowsOutflowsChart(colors),
                const SizedBox(height: 16),
                _buildTotalAssetsChart(colors),
              ] else ...[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 1, child: _buildInflowsOutflowsChart(colors)),
                    const SizedBox(width: 16),
                    Expanded(flex: 1, child: _buildTotalAssetsChart(colors)),
                  ],
                ),
              ],
              const SizedBox(height: 24),

              // Pie charts
              if (isPhone) ...[
                _buildPieChartCard(colors, 'This Month Expenses', _monthlyExpenses),
                const SizedBox(height: 16),
                _buildPieChartCard(colors, 'This Month Incomes', _monthlyIncomes),
                const SizedBox(height: 16),
                _buildAssetsDistributionPieChart(colors),
              ] else ...[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: _buildPieChartCard(colors, 'This Month Expenses', _monthlyExpenses)),
                    const SizedBox(width: 16),
                    Expanded(child: _buildPieChartCard(colors, 'This Month Incomes', _monthlyIncomes)),
                    const SizedBox(width: 16),
                    Expanded(child: _buildAssetsDistributionPieChart(colors)),
                  ],
                ),
              ],
              const SizedBox(height: 80),
        ],
      ),
    );
  }

  Widget _buildStatCards(PeadraColors colors, String currency) {
    final currentIncome = _monthlySummary['income'] ?? 0;
    final currentExpenses = _monthlySummary['expenses'] ?? 0;

    final balanceChange = _previousBalance > 0
        ? ((_balance - _previousBalance) / _previousBalance * 100)
        : 0.0;
    final incomeChange = _previousIncome > 0
        ? ((currentIncome - _previousIncome) / _previousIncome * 100)
        : 0.0;
    final expensesChange = _previousExpenses > 0
        ? ((currentExpenses - _previousExpenses) / _previousExpenses * 100)
        : 0.0;

    final cards = [
      _buildStatCard(
        title: 'Current Balance',
        value: CurrencyService.formatAmount(_balance, currency),
        change: balanceChange,
        icon: Icons.account_balance_wallet,
        iconColor: colors.info,
        bgColor: colors.info.withValues(alpha: 0.15),
        colors: colors,
      ),
      _buildStatCard(
        title: 'Income',
        value: CurrencyService.formatAmount(currentIncome, currency),
        change: incomeChange,
        icon: Icons.trending_up,
        iconColor: colors.success,
        bgColor: colors.incomeBg,
        colors: colors,
      ),
      _buildStatCard(
        title: 'Expenses',
        value: CurrencyService.formatAmount(currentExpenses, currency),
        change: expensesChange,
        icon: Icons.trending_down,
        iconColor: colors.error,
        bgColor: colors.expenseBg,
        colors: colors,
      ),
      _buildStatCard(
        title: 'Savings Outside',
        value: CurrencyService.formatAmount(_savings, currency),
        change: 0,
        icon: Icons.savings,
        iconColor: colors.savingsIcon,
        bgColor: colors.savingsBg,
        colors: colors,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth > 600;
        if (isWide) {
          return Row(
            children: [
              for (int i = 0; i < cards.length; i++) ...[
                if (i > 0) const SizedBox(width: 12),
                Expanded(child: cards[i]),
              ],
            ],
          );
        }
        return Column(
          children: [
            Row(
              children: [
                Expanded(child: cards[0]),
                const SizedBox(width: 12),
                Expanded(child: cards[1]),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: cards[2]),
                const SizedBox(width: 12),
                Expanded(child: cards[3]),
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _buildStatCard({
    required String title,
    required String value,
    required double change,
    required IconData icon,
    required Color iconColor,
    required Color bgColor,
    required PeadraColors colors,
  }) {
    return Card(
      color: colors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: bgColor,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: iconColor, size: 20),
                ),
                _buildChangeIndicator(change, colors),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              title,
              style: TextStyle(
                fontSize: 12,
                color: colors.textSecondary,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                value,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: colors.text,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChangeIndicator(double change, PeadraColors colors) {
    final isPositive = change >= 0;
    final color = isPositive ? colors.success : colors.error;
    final icon = isPositive ? Icons.arrow_upward : Icons.arrow_downward;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 14),
        Text(
          '${change >= 0 ? '+' : ''}${change.toStringAsFixed(1)}%',
          style: TextStyle(
            fontSize: 12,
            color: color,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _buildCashFlowSection(PeadraColors colors) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              Translator.t('dash_cash_flow'),
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: colors.text,
              ),
            ),
            _buildTimeFilterButtons(colors),
          ],
        ),
      ],
    );
  }

  Widget _buildTimeFilterButtons(PeadraColors colors) {
    final options = [
      {'label': '3M', 'value': 3},
      {'label': '6M', 'value': 6},
      {'label': '1Y', 'value': 12},
      {'label': 'All', 'value': 24},
    ];

    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: options.map((option) {
          final isSelected = _selectedMonths == option['value'];
          return GestureDetector(
            onTap: () {
              setState(() {
                _selectedMonths = option['value'] as int;
              });
              _loadChartData();
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: isSelected ? colors.accent : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                option['label'] as String,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                  color: isSelected ? colors.text : colors.textSecondary,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildInflowsOutflowsChart(PeadraColors colors) {
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
                  'Inflows / Outflows',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: colors.text,
                  ),
                ),
                Row(
                  children: [
                    _buildLegendDot(colors.success, 'Inflows'),
                    const SizedBox(width: 16),
                    _buildLegendDot(colors.error, 'Outflows'),
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

  Widget _buildBarChart(PeadraColors colors) {
    if (_cashFlowData.isEmpty) {
      return Center(
        child: Text(Translator.t('dashboard_no_data'),
            style: TextStyle(color: colors.textSecondary)),
      );
    }

    final expenseData = _cashFlowData.where((d) => d['type'] == 'expense').toList();
    final incomeData = _cashFlowData.where((d) => d['type'] == 'income').toList();

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

    final expenseByMonth = <String, double>{};
    for (final d in expenseData) {
      final m = d['month'] as String;
      if (displayMonths.contains(m)) {
        expenseByMonth[m] = (expenseByMonth[m] ?? 0) + (d['amount'] as double);
      }
    }

    final incomeByMonth = <String, double>{};
    for (final d in incomeData) {
      final m = d['month'] as String;
      if (displayMonths.contains(m)) {
        incomeByMonth[m] = (incomeByMonth[m] ?? 0) + (d['amount'] as double);
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
              borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
            ),
            BarChartRodData(
              toY: expense,
              color: colors.error,
              width: 12,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
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
                  final monthNames = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
                                     'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
                  final monthNum = int.tryParse(m.split('-').last) ?? 1;
                  final label = monthNames[(monthNum - 1).clamp(0, 11)];
                  return Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      label,
                      style: TextStyle(color: colors.textSecondary, fontSize: 11),
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
                  style: TextStyle(color: colors.textSecondary, fontSize: 10),
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
        barGroups: barGroups,
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
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
      ],
    );
  }

  Widget _buildTotalAssetsChart(PeadraColors colors) {
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
                  'Total Assets',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: colors.text,
                  ),
                ),
                _buildLegendDot(colors.chartAsset, 'Total Assets'),
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

  Widget _buildLineChart(PeadraColors colors) {
    if (_assetsHistory.isEmpty) {
      return Center(
        child: Text(Translator.t('dashboard_no_data'),
            style: TextStyle(color: colors.textSecondary)),
      );
    }

    final firstValue = _assetsHistory.first['value'] as double;
    int startIndex = 0;
    for (int i = 1; i < _assetsHistory.length; i++) {
      if ((_assetsHistory[i]['value'] as double) != firstValue) {
        startIndex = i > 0 ? i - 1 : 0;
        break;
      }
      if (i == _assetsHistory.length - 1) {
        startIndex = 0;
      }
    }

    final trimmedHistory = _assetsHistory.sublist(startIndex);

    final spots = <FlSpot>[];
    final labels = <String>[];

    for (int i = 0; i < trimmedHistory.length; i++) {
      spots.add(FlSpot(i.toDouble(), trimmedHistory[i]['value'] as double));
      labels.add(trimmedHistory[i]['label'] as String);
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
                final label = idx < labels.length ? labels[idx] : '';
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
                if (idx >= 0 && idx < labels.length) {
                  final label = labels[idx];
                  final showLabel = idx == 0 ||
                      idx == labels.length - 1 ||
                      label != labels[idx - 1];
                  if (!showLabel) return const Text('');
                  return Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      label,
                      style: TextStyle(color: colors.textSecondary, fontSize: 10),
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
                  style: TextStyle(color: colors.textSecondary, fontSize: 10),
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
            belowBarData: BarAreaData(
              show: true,
              color: lineColor.withValues(alpha: 0.1),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPieChartCard(PeadraColors colors, String title, Map<String, double> data) {
    final pieData = data.entries.map((e) => {
      'label': e.key,
      'amount': e.value,
    }).toList();

    return Card(
      color: colors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: SizedBox(
          height: 220,
          child: CategoryPieChart(
            data: pieData,
            colors: colors,
            title: title,
          ),
        ),
      ),
    );
  }

  Widget _buildAssetsDistributionPieChart(PeadraColors colors) {
    final pieData = _accountsDistribution.map((a) => {
      'label': a['name'] as String,
      'amount': (a['value'] as num).toDouble(),
      'color': a['color'] as String,
    }).toList();

    return Card(
      color: colors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: SizedBox(
          height: 220,
          child: CategoryPieChart(
            data: pieData,
            colors: colors,
            title: Translator.t('dash_assets_distribution'),
          ),
        ),
      ),
    );
  }

}
