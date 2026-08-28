import 'package:flutter/material.dart';
import 'package:decimal/decimal.dart';
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
  Decimal _balance = Decimal.zero;
  Decimal _savings = Decimal.zero;
  Decimal _totalAssets = Decimal.zero;
  Decimal _previousBalance = Decimal.zero;
  Decimal _previousIncome = Decimal.zero;
  Decimal _previousExpenses = Decimal.zero;
  Decimal _previousSavings = Decimal.zero;
  Map<String, Decimal> _monthlySummary = {};
  List<Map<String, dynamic>> _accountsDistribution = [];
  List<Map<String, dynamic>> _cashFlowData = [];
  List<Map<String, dynamic>> _assetsHistory = [];
  Map<String, Decimal> _monthlyExpenses = {};
  Map<String, Decimal> _monthlyIncomes = {};
  Map<String, String> _tagColors = {};
  bool _loading = true;
  int _selectedMonths = 6;
  String _lastCurrency = '';
  String _lastMonthMode = '';
  String _lastDashboardPieView = '';
  String _lastAssetsGranularity = '';

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
    final assetsGranularity = context.watch<SettingsProvider>().assetsGranularity;
    if (currency != _lastCurrency ||
        monthMode != _lastMonthMode ||
        categoriesView != _lastDashboardPieView ||
        assetsGranularity != _lastAssetsGranularity) {
      _lastCurrency = currency;
      _lastMonthMode = monthMode;
      _lastDashboardPieView = categoriesView;
      _lastAssetsGranularity = assetsGranularity;
      _loadData();
    }
  }

  Future<void> _loadData() async {
    try {
      final currency = context.read<SettingsProvider>().currency;
      final monthMode = context.read<SettingsProvider>().monthMode;
      final isRolling = monthMode == 'rolling';
      final isTagMode = context.read<SettingsProvider>().dashboardPieView == 'tags';
      final assetsGranularity = context.read<SettingsProvider>().assetsGranularity;

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
        _safeQuery(() => _db.getAssetsHistory(months: _selectedMonths, targetCurrency: currency, granularity: assetsGranularity)),
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
        _safeQuery(() => isTagMode
            ? _db.getTagColors()
            : Future.value(<String, String>{})),
        _safeQuery(() =>
            _db.getBalance(targetCurrency: currency, before: thisMonthStart)),
      ]);

      if (mounted) {
        setState(() {
          _balance = (results[0] as Decimal?) ?? Decimal.zero;
          _savings = (results[1] as Decimal?) ?? Decimal.zero;
          _totalAssets = (results[2] as Decimal?) ?? Decimal.zero;
          _monthlySummary = (results[3] as Map<String, Decimal>?) ?? {};
          _accountsDistribution = (results[4] as List<Map<String, dynamic>>?) ?? [];
          _cashFlowData = (results[5] as List<Map<String, dynamic>>?) ?? [];
          _assetsHistory = (results[6] as List<Map<String, dynamic>>?) ?? [];
          _monthlyExpenses = (results[7] as Map<String, Decimal>?) ?? {};
          _monthlyIncomes = (results[8] as Map<String, Decimal>?) ?? {};
          final prevSummary = (results[9] as Map<String, Decimal>?) ?? {};
          _previousIncome = prevSummary['income'] ?? Decimal.zero;
          _previousExpenses = prevSummary['expenses'] ?? Decimal.zero;
          _previousBalance = (results[12] as Decimal?) ?? Decimal.zero;
          _previousSavings = (results[10] as Decimal?) ?? Decimal.zero;
          _tagColors = (results[11] as Map<String, String>?) ?? {};
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
      final assetsGranularity = context.read<SettingsProvider>().assetsGranularity;

      final results = await Future.wait([
        _db.getCashFlowData(months: _selectedMonths, targetCurrency: currency),
        _db.getAssetsHistory(months: _selectedMonths, targetCurrency: currency, granularity: assetsGranularity),
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
    final currentIncome = _monthlySummary['income'] ?? Decimal.zero;
    final currentExpenses = _monthlySummary['expenses'] ?? Decimal.zero;

    final balanceChange = _previousBalance > Decimal.zero
        ? (((_balance - _previousBalance) * Decimal.fromInt(100)) / _previousBalance).toDouble()
        : 0.0;
    final incomeChange = _previousIncome > Decimal.zero
        ? (((currentIncome - _previousIncome) * Decimal.fromInt(100)) / _previousIncome).toDouble()
        : 0.0;
    final expensesChange = _previousExpenses > Decimal.zero
        ? (((currentExpenses - _previousExpenses) * Decimal.fromInt(100)) / _previousExpenses).toDouble()
        : 0.0;
    final savingsChange = _previousSavings > Decimal.zero
        ? (((_savings - _previousSavings) * Decimal.fromInt(100)) / _previousSavings).toDouble()
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
      Map<String, Decimal> data, String currency, int maxCategories,
      {Map<String, String> itemColors = const {}}) {
    final pieData = data.entries.map((e) {
      final entryColor = itemColors[e.key];
      return {
        'label': e.key,
        'amount': e.value,
        if (entryColor != null) 'color': entryColor,
      };
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
        maxPieCategories,
        itemColors: _tagColors);
    final incomePie = _buildPieChartCard(
        colors,
        Translator.t('dash_this_month_incomes'),
        _monthlyIncomes,
        currency,
        maxPieCategories,
        itemColors: _tagColors);
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
