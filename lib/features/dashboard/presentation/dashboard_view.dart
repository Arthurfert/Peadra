import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/i18n/translator.dart';
import '../../../core/providers/theme_provider.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/database/database_manager.dart';
import '../../../core/theme/peadra_colors.dart';
import '../../../core/services/currency_service.dart';
import 'charts/category_pie_chart.dart';
import 'dashboard_view_desktop.dart';
import 'dashboard_view_mobile.dart';

class DashboardView extends StatefulWidget {
  final int refreshSignal;

  const DashboardView({super.key, this.refreshSignal = 0});

  @override
  State<DashboardView> createState() => _DashboardViewState();
}

class _DashboardViewState extends State<DashboardView> {
  final _db = DatabaseManager.instance;
  double _balance = 0;
  double _savings = 0;
  double _totalAssets = 0;
  double _previousBalance = 0;
  double _previousIncome = 0;
  double _previousExpenses = 0;
  double _previousSavings = 0;
  Map<String, double> _monthlySummary = {};
  List<Map<String, dynamic>> _accountsDistribution = [];
  List<Map<String, dynamic>> _cashFlowData = [];
  List<Map<String, dynamic>> _assetsHistory = [];
  Map<String, double> _monthlyExpenses = {};
  Map<String, double> _monthlyIncomes = {};
  bool _loading = true;
  int _selectedMonths = 6;
  String _lastCurrency = '';
  String _lastMonthMode = '';
  String _lastDashboardPieView = '';

  @override
  void initState() {
    super.initState();
  }

  @override
  void didUpdateWidget(DashboardView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.refreshSignal != oldWidget.refreshSignal) {
      _loadData();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final currency = context.watch<SettingsProvider>().currency;
    final monthMode = context.watch<SettingsProvider>().monthMode;
    final categoriesView = context.watch<SettingsProvider>().dashboardPieView;
    if (currency != _lastCurrency ||
        monthMode != _lastMonthMode ||
        categoriesView != _lastDashboardPieView) {
      _lastCurrency = currency;
      _lastMonthMode = monthMode;
      _lastDashboardPieView = categoriesView;
      _loadData();
    }
  }

  Future<void> _loadData() async {
    try {
      final currency = context.read<SettingsProvider>().currency;
      final monthMode = context.read<SettingsProvider>().monthMode;
      final isRolling = monthMode == 'rolling';
      final isTagMode = context.read<SettingsProvider>().dashboardPieView == 'tags';

      final now = DateTime.now();
      final thisMonthStart = DateTime(now.year, now.month, 1).toIso8601String().substring(0, 10);
      final results = await Future.wait([
        _safeQuery(() => _db.getBalance(targetCurrency: currency)),
        _safeQuery(() => _db.getSavingsTotal(targetCurrency: currency)),
        _safeQuery(() => _db.getTotalPatrimony(targetCurrency: currency)),
        _safeQuery(() => isRolling
            ? _db.getRollingSummary()
            : _db.getMonthlySummary(targetCurrency: currency)),
        _safeQuery(() => _db.getAccountsDistribution(targetCurrency: currency)),
        _safeQuery(() => _db.getCashFlowData(months: _selectedMonths, targetCurrency: currency)),
        _safeQuery(() => _db.getAssetsHistory(months: _selectedMonths, targetCurrency: currency)),
        _safeQuery(() => isRolling
            ? (isTagMode
                ? _db.getRollingMonthTagDistribution(
                    transactionType: 'expense', targetCurrency: currency)
                : _db.getRollingMonthDistribution(
                    transactionType: 'expense', targetCurrency: currency))
            : (isTagMode
                ? _db.getCurrentMonthTagDistribution(
                    transactionType: 'expense', targetCurrency: currency)
                : _db.getCurrentMonthDistribution(
                    transactionType: 'expense', targetCurrency: currency))),
        _safeQuery(() => isRolling
            ? (isTagMode
                ? _db.getRollingMonthTagDistribution(
                    transactionType: 'income', targetCurrency: currency)
                : _db.getRollingMonthDistribution(
                    transactionType: 'income', targetCurrency: currency))
            : (isTagMode
                ? _db.getCurrentMonthTagDistribution(
                    transactionType: 'income', targetCurrency: currency)
                : _db.getCurrentMonthDistribution(
                    transactionType: 'income', targetCurrency: currency))),
        _safeQuery(() => _db.getMonthlySummary(
            year: now.year,
            month: now.month - 1,
            targetCurrency: currency)),
        _safeQuery(() => _db.getSavingsTotal(
            targetCurrency: currency, before: thisMonthStart)),
      ]);

      if (mounted) {
        setState(() {
          _balance = (results[0] as double?) ?? 0;
          _savings = (results[1] as double?) ?? 0;
          _totalAssets = (results[2] as double?) ?? 0;
          _monthlySummary = (results[3] as Map<String, double>?) ?? {};
          _accountsDistribution = (results[4] as List<Map<String, dynamic>>?) ?? [];
          _cashFlowData = (results[5] as List<Map<String, dynamic>>?) ?? [];
          _assetsHistory = (results[6] as List<Map<String, dynamic>>?) ?? [];
          _monthlyExpenses = (results[7] as Map<String, double>?) ?? {};
          _monthlyIncomes = (results[8] as Map<String, double>?) ?? {};
          final prevSummary = (results[9] as Map<String, double>?) ?? {};
          _previousBalance = prevSummary['balance'] ?? 0;
          _previousIncome = prevSummary['income'] ?? 0;
          _previousExpenses = prevSummary['expenses'] ?? 0;
          _previousSavings = (results[10] as double?) ?? 0;
          _loading = false;
        });
      }
    } catch (e, stack) {
      debugPrint('[DashboardView] _loadData error: $e\n$stack');
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<dynamic> _safeQuery<T>(Future<T> Function() query) async {
    try {
      return await query();
    } catch (e, stack) {
      debugPrint('[DashboardView] query failed: $e\n$stack');
      return null;
    }
  }

  Future<void> _loadChartData() async {
    try {
      final currency = context.read<SettingsProvider>().currency;

      final results = await Future.wait([
        _db.getCashFlowData(months: _selectedMonths, targetCurrency: currency),
        _db.getAssetsHistory(months: _selectedMonths, targetCurrency: currency),
      ]);

      if (mounted) {
        setState(() {
          _cashFlowData = results[0];
          _assetsHistory = results[1];
        });
      }
    } catch (_) {}
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
    final savingsChange = _previousSavings > 0
        ? ((_savings - _previousSavings) / _previousSavings * 100)
        : 0.0;

    final cards = [
      _buildStatCard(
        title: Translator.t('dash_current_balance'),
        value: CurrencyService.formatAmount(_balance, currency),
        change: balanceChange,
        icon: Icons.account_balance_wallet,
        iconColor: colors.info,
        bgColor: colors.info.withValues(alpha: 0.15),
        colors: colors,
      ),
      _buildStatCard(
        title: Translator.t('dash_income'),
        value: CurrencyService.formatAmount(currentIncome, currency),
        change: incomeChange,
        icon: Icons.trending_up,
        iconColor: colors.success,
        bgColor: colors.incomeBg,
        colors: colors,
      ),
      _buildStatCard(
        title: Translator.t('dash_expenses'),
        value: CurrencyService.formatAmount(currentExpenses, currency),
        change: expensesChange,
        icon: Icons.trending_down,
        iconColor: colors.error,
        bgColor: colors.expenseBg,
        colors: colors,
      ),
      _buildStatCard(
        title: Translator.t('dash_savings_outside'),
        value: CurrencyService.formatAmount(_savings, currency),
        change: savingsChange,
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
        Text(
          Translator.t('dash_cash_flow'),
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: colors.text,
          ),
        ),
        const SizedBox(height: 12),
        _buildTimeFilterButtons(colors),
      ],
    );
  }

  Widget _buildTimeFilterButtons(PeadraColors colors) {
    final options = [
      {'label': Translator.t('period_3m'), 'value': 3},
      {'label': Translator.t('period_6m'), 'value': 6},
      {'label': Translator.t('period_1y'), 'value': 12},
      {'label': Translator.t('segment_all'), 'value': 24},
    ];

    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
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
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: isSelected ? colors.accent : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                option['label'] as String,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight:
                      isSelected ? FontWeight.w600 : FontWeight.w500,
                  color:
                      isSelected ? Colors.white : colors.textSecondary,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildPieChartCard(PeadraColors colors, String title,
      Map<String, double> data, String currency, int maxCategories) {
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
            currency: currency,
            maxCategories: maxCategories,
          ),
        ),
      ),
    );
  }

  Widget _buildAssetsDistributionPieChart(
      PeadraColors colors, String currency, int maxCategories) {
    final pieData = _accountsDistribution.map((a) => {
      'label': a['name'] as String,
      'amount': ((a['value'] as num).toDouble()).clamp(0.0, double.infinity),
      'nativeValue': (a['nativeValue'] as num?)?.toDouble(),
      'currency': a['currency'] as String?,
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
            currency: currency,
            maxCategories: maxCategories,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeName = context.watch<ThemeProvider>().themeName;
    final colors = PeadraTheme.getColors(themeName);
    final currency = context.watch<SettingsProvider>().currency;
    final maxPieCategories =
        context.watch<SettingsProvider>().maxPieCategories;
    final lineChartDots = context.watch<SettingsProvider>().lineChartDots;
    final username = context.watch<AuthProvider>().username;

    if (_loading) {
      return Center(
        child: CircularProgressIndicator(color: colors.accent),
      );
    }

    final header = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
      ],
    );

    final statCards = _buildStatCards(colors, currency);

    final cashFlowSection = _buildCashFlowSection(colors);
    final expensePie = _buildPieChartCard(
        colors,
        Translator.t('dash_this_month_expenses'),
        _monthlyExpenses,
        currency,
        maxPieCategories);
    final incomePie = _buildPieChartCard(
        colors,
        Translator.t('dash_this_month_incomes'),
        _monthlyIncomes,
        currency,
        maxPieCategories);
    final assetsPie = _buildAssetsDistributionPieChart(
        colors, currency, maxPieCategories);

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth > 800) {
          return DashboardViewDesktop(
            header: header,
            statCards: statCards,
            cashFlowSection: cashFlowSection,
            expensePie: expensePie,
            incomePie: incomePie,
            assetsPie: assetsPie,
            colors: colors,
            cashFlowData: _cashFlowData,
            assetsHistory: _assetsHistory,
            showLineDots: lineChartDots,
          );
        } else {
          return DashboardViewMobile(
            header: header,
            totalAsset: _buildTotalAssetCard(colors, currency),
            statCards: statCards,
            cashFlowSection: cashFlowSection,
            expensePie: expensePie,
            incomePie: incomePie,
            assetsPie: assetsPie,
            colors: colors,
            cashFlowData: _cashFlowData,
            assetsHistory: _assetsHistory,
            showLineDots: lineChartDots,
          );
        }
      },
    );
  }

  Widget _buildTotalAssetCard(PeadraColors colors, String currency) {
    return Card(
      color: colors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: colors.surface,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 22),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colors.chartAsset.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(Icons.account_balance_rounded,
                  color: colors.chartAsset, size: 28),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    Translator.t('dash_total_assets'),
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: colors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      CurrencyService.formatAmount(_totalAssets, currency),
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w700,
                        color: colors.text,
                        height: 1.1,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
