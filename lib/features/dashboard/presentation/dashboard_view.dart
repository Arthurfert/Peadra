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
import 'widgets/custom_range_dialog.dart';
import 'widgets/stat_card_grid.dart';
import '../../../shared/widgets/peadra_modal.dart';

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
  Map<String, dynamic> _lifetimeStats = {};
  String? _expenseDrillTag;
  String? _incomeDrillTag;
  bool _expenseShowAll = false;
  bool _incomeShowAll = false;
  String? _assetsDrillType;
  bool _assetsShowAll = false;
  Map<String, Decimal> _expenseDrillData = {};
  Map<String, Decimal> _incomeDrillData = {};
  bool _expenseDrillLoading = false;
  bool _incomeDrillLoading = false;
  bool _loading = true;
  int _selectedMonths = 6;
  String? _customStart;
  String? _customEnd;

  bool get _isCustomRange => _customStart != null && _customEnd != null;
  String _lastCurrency = '';
  String _lastMonthMode = '';
  String _lastDashboardPieView = '';
  String _lastAssetsGranularity = '';

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
    final currency =
        context.watch<SettingsProvider>().currency;
    final monthMode =
        context.watch<SettingsProvider>().monthMode;
    final categoriesView =
        context.watch<SettingsProvider>().dashboardPieView;
    final assetsGranularity =
        context.watch<SettingsProvider>().assetsGranularity;
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
      final isCustom = _isCustomRange;
      final customStart = _customStart;
      final customEnd = _customEnd;
      final results = await Future.wait([
        _safeQuery(() => _db.getBalance(targetCurrency: currency)),
        _safeQuery(() => _db.getSavingsTotal(targetCurrency: currency)),
        _safeQuery(() => _db.getTotalPatrimony(targetCurrency: currency)),
        _safeQuery(() => isRolling
            ? _db.getRollingSummary()
            : _db.getMonthlySummary(targetCurrency: currency)),
        _safeQuery(() => _db.getAccountsDistribution(
            targetCurrency: currency,
            endDate: isCustom ? customEnd : null)),
        _safeQuery(() => isCustom
            ? _db.getCashFlowDataForRange(
                startDate: customStart!,
                endDate: customEnd!,
                targetCurrency: currency)
            : _db.getCashFlowData(months: _selectedMonths, targetCurrency: currency)),
        _safeQuery(() => isCustom
            ? _db.getAssetsHistoryForRange(
                startDate: customStart!,
                endDate: customEnd!,
                targetCurrency: currency,
                granularity: assetsGranularity)
            : _db.getAssetsHistory(months: _selectedMonths, targetCurrency: currency, granularity: assetsGranularity)),
        _safeQuery(() => isCustom
            ? (isTagMode
                ? _db.getTagDistributionForRange(
                    transactionType: 'expense',
                    startDate: customStart!,
                    endDate: customEnd!,
                    targetCurrency: currency)
                : _db.getDistributionForRange(
                    transactionType: 'expense',
                    startDate: customStart!,
                    endDate: customEnd!,
                    targetCurrency: currency))
            : isRolling
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
        _safeQuery(() => isCustom
            ? (isTagMode
                ? _db.getTagDistributionForRange(
                    transactionType: 'income',
                    startDate: customStart!,
                    endDate: customEnd!,
                    targetCurrency: currency)
                : _db.getDistributionForRange(
                    transactionType: 'income',
                    startDate: customStart!,
                    endDate: customEnd!,
                    targetCurrency: currency))
            : isRolling
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
        _safeQuery(() {
          final prevMonth = now.month == 1 ? 12 : now.month - 1;
          final prevYear = now.month == 1 ? now.year - 1 : now.year;
          return _db.getMonthlySummary(
              year: prevYear,
              month: prevMonth,
              targetCurrency: currency);
        }),
        _safeQuery(() => _db.getSavingsTotal(
            targetCurrency: currency, before: thisMonthStart)),
        _safeQuery(() => isTagMode
            ? _db.getTagColors()
            : Future.value(<String, String>{})),
        _safeQuery(() =>
            _db.getBalance(targetCurrency: currency, before: thisMonthStart)),
        _safeQuery(() => _db.getLifetimeStats(targetCurrency: currency)),
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
          _lifetimeStats = (results[13] as Map<String, dynamic>?) ?? {};
          _expenseDrillTag = null;
          _incomeDrillTag = null;
          _expenseShowAll = false;
          _incomeShowAll = false;
          _assetsDrillType = null;
          _assetsShowAll = false;
          _expenseDrillData = {};
          _incomeDrillData = {};
          _expenseDrillLoading = false;
          _incomeDrillLoading = false;
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
      final isCustom = _isCustomRange;

      final results = await Future.wait([
        isCustom
            ? _db.getCashFlowDataForRange(
                startDate: _customStart!,
                endDate: _customEnd!,
                targetCurrency: currency)
            : _db.getCashFlowData(months: _selectedMonths, targetCurrency: currency),
        isCustom
            ? _db.getAssetsHistoryForRange(
                startDate: _customStart!,
                endDate: _customEnd!,
                targetCurrency: currency,
                granularity: assetsGranularity)
            : _db.getAssetsHistory(months: _selectedMonths, targetCurrency: currency, granularity: assetsGranularity),
      ]);

      if (mounted) {
        setState(() {
          _cashFlowData = results[0];
          _assetsHistory = results[1];
        });
      }
    } catch (_) {}
  }

  Future<void> _drillIntoPie({required bool isExpense, required String tag}) async {
    if (isExpense) {
      if (_expenseDrillTag == tag) return;
      setState(() {
        _expenseDrillTag = tag;
        _expenseDrillData = {};
        _expenseDrillLoading = true;
      });
    } else {
      if (_incomeDrillTag == tag) return;
      setState(() {
        _incomeDrillTag = tag;
        _incomeDrillData = {};
        _incomeDrillLoading = true;
      });
    }
    try {
      final currency = context.read<SettingsProvider>().currency;
      final isRolling = context.read<SettingsProvider>().monthMode == 'rolling';
      final transactionType = isExpense ? 'expense' : 'income';
      final customStart = _customStart;
      final customEnd = _customEnd;
      final Map<String, Decimal> data = (customStart != null && customEnd != null)
          ? await _db.getTagDescriptionBreakdown(
              transactionType: transactionType,
              tag: tag,
              startDate: customStart,
              endDate: customEnd,
              targetCurrency: currency)
          : isRolling
              ? await _db.getRollingMonthTagDescriptionBreakdown(
                  transactionType: transactionType, tag: tag, targetCurrency: currency)
              : await _db.getCurrentMonthTagDescriptionBreakdown(
                  transactionType: transactionType, tag: tag, targetCurrency: currency);
      if (!mounted) return;
      setState(() {
        if (isExpense) {
          if (_expenseDrillTag != tag) return;
          _expenseDrillData = data;
          _expenseDrillLoading = false;
        } else {
          if (_incomeDrillTag != tag) return;
          _incomeDrillData = data;
          _incomeDrillLoading = false;
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        if (isExpense) {
          _expenseDrillLoading = false;
        } else {
          _incomeDrillLoading = false;
        }
      });
    }
  }

  void _onPieSectionTap({required bool isExpense, required String tag}) {
    if (tag == Translator.t('dash_other')) {
      setState(() {
        if (isExpense) {
          _expenseShowAll = true;
        } else {
          _incomeShowAll = true;
        }
      });
      return;
    }
    _drillIntoPie(isExpense: isExpense, tag: tag);
  }

  void _onPieBack({required bool isExpense}) {
    final drilled = isExpense ? _expenseDrillTag != null : _incomeDrillTag != null;
    if (drilled) {
      _exitPieDrill(isExpense: isExpense);
      return;
    }
    setState(() {
      if (isExpense) {
        _expenseShowAll = false;
      } else {
        _incomeShowAll = false;
      }
    });
  }

  void _exitPieDrill({required bool isExpense}) {
    setState(() {
      if (isExpense) {
        _expenseDrillTag = null;
        _expenseDrillData = {};
        _expenseDrillLoading = false;
      } else {
        _incomeDrillTag = null;
        _incomeDrillData = {};
        _incomeDrillLoading = false;
      }
    });
  }

  Widget _buildStatCards(PeadraColors colors, String currency) {
    final currentIncome = _monthlySummary['income'] ?? Decimal.zero;
    final currentExpenses = _monthlySummary['expenses'] ?? Decimal.zero;
    final showSubtitles = context.read<SettingsProvider>().showStatSubtitles;

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
        showSubtitle: showSubtitles,
        subtitle: Translator.t('dash_as_of_today'),
      ),
      _buildStatCard(
        title: Translator.t('dash_income'),
        value: CurrencyService.formatAmount(currentIncome, currency),
        change: incomeChange,
        icon: Icons.trending_up,
        iconColor: colors.success,
        bgColor: colors.incomeBg,
        colors: colors,
        showSubtitle: showSubtitles,
        subtitle: Translator.t('dash_this_month'),
      ),
      _buildStatCard(
        title: Translator.t('dash_expenses'),
        value: CurrencyService.formatAmount(currentExpenses, currency),
        change: expensesChange,
        icon: Icons.trending_down,
        iconColor: colors.error,
        bgColor: colors.expenseBg,
        colors: colors,
        invertChange: true,
        showSubtitle: showSubtitles,
        subtitle: Translator.t('dash_this_month'),
      ),
      _buildStatCard(
        title: Translator.t('dash_savings_outside'),
        value: CurrencyService.formatAmount(_savings, currency),
        change: savingsChange,
        icon: Icons.savings,
        iconColor: colors.savingsIcon,
        bgColor: colors.savingsBg,
        colors: colors,
        showSubtitle: showSubtitles,
        subtitle: Translator.t('dash_as_of_today'),
      ),
    ];

    return _buildResponsiveCards(cards);
  }

  Decimal _avgPerMonth(Decimal total, int months) {
    if (months <= 0) return Decimal.zero;
    return Decimal.parse((total.toDouble() / months).toStringAsFixed(2));
  }

  Widget _buildAverageSection(PeadraColors colors, String currency) {
    final income = _lifetimeStats['income'] as Decimal? ?? Decimal.zero;
    final expenses = _lifetimeStats['expenses'] as Decimal? ?? Decimal.zero;
    final startingTotal =
        _lifetimeStats['startingTotal'] as Decimal? ?? Decimal.zero;
    final months = _lifetimeStats['months'] as int? ?? 1;
    final showSubtitles = context.read<SettingsProvider>().showStatSubtitles;

    final totalGrowth = _totalAssets - startingTotal;
    final hasStartingCapital = startingTotal > Decimal.zero;
    final growthPct = hasStartingCapital
        ? ((totalGrowth * Decimal.fromInt(100)) / startingTotal).toDouble()
        : 0.0;
    final avgGrowthPct = months > 0 ? growthPct / months : 0.0;
    final cards = [
      _buildStatCard(
        title: Translator.t('dash_avg_cost'),
        value: CurrencyService.formatAmount(
            _avgPerMonth(expenses, months), currency),
        change: 0,
        icon: Icons.receipt_long,
        iconColor: colors.error,
        bgColor: colors.expenseBg,
        colors: colors,
        hideChange: true,
        showSubtitle: showSubtitles,
        subtitle: Translator.t('dash_per_month'),
      ),
      _buildStatCard(
        title: Translator.t('dash_avg_income'),
        value: CurrencyService.formatAmount(
            _avgPerMonth(income, months), currency),
        change: 0,
        icon: Icons.trending_up,
        iconColor: colors.success,
        bgColor: colors.incomeBg,
        colors: colors,
        hideChange: true,
        showSubtitle: showSubtitles,
        subtitle: Translator.t('dash_per_month'),
      ),
      _buildStatCard(
        title: Translator.t('dash_avg_growth'),
        value: CurrencyService.formatAmount(
            _avgPerMonth(totalGrowth, months), currency),
        change: avgGrowthPct,
        icon: Icons.show_chart,
        iconColor: colors.chartAsset,
        bgColor: colors.chartAsset.withValues(alpha: 0.12),
        colors: colors,
        hideChange: !hasStartingCapital,
        showSubtitle: showSubtitles,
        subtitle: Translator.t('dash_per_month'),
      ),
      _buildStatCard(
        title: Translator.t('dash_total_growth'),
        value: CurrencyService.formatAmount(totalGrowth, currency),
        change: growthPct,
        icon: Icons.account_balance,
        iconColor: colors.info,
        bgColor: colors.info.withValues(alpha: 0.15),
        colors: colors,
        hideChange: !hasStartingCapital,
        showSubtitle: showSubtitles,
        subtitle: Translator.t('dash_since_start'),
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          Translator.t('dash_avg_section'),
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: colors.text,
          ),
        ),
        const SizedBox(height: 12),
        _buildResponsiveCards(cards),
      ],
    );
  }

  Widget _buildResponsiveCards(List<Widget> cards) {
    return StatCardGrid(cards: cards);
  }

  Widget _buildStatCard({
    required String title,
    required String value,
    required double change,
    required IconData icon,
    required Color iconColor,
    required Color bgColor,
    required PeadraColors colors,
    bool invertChange = false,
    bool hideChange = false,
    String? subtitle,
    bool showSubtitle = true,
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
                if (hideChange)
                  const SizedBox.shrink()
                else
                  _buildChangeIndicator(change, colors, invert: invertChange),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
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
            if (showSubtitle) ...[
              const SizedBox(height: 2),
              Text(
                // Always reserve the subtitle line (non-breaking space when
                // empty) so every card keeps the same height.
                subtitle ?? '\u00A0',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  color: colors.textSecondary,
                ),
              ),
            ],
            ],
            ),
        ),
    );
  }

  Widget _buildChangeIndicator(double change, PeadraColors colors, {bool invert = false}) {
    final isPositive = change >= 0;
    final isGood = invert ? change <= 0 : change >= 0;
    final color = isGood ? colors.success : colors.error;
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

  Future<void> _pickCustomRange() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    DateTime initialStart = today.subtract(const Duration(days: 30));
    DateTime initialEnd = today;
    if (_customStart != null) {
      final parsed = DateTime.tryParse(_customStart!);
      if (parsed != null && !parsed.isAfter(today)) initialStart = parsed;
    }
    if (_customEnd != null) {
      final parsed = DateTime.tryParse(_customEnd!);
      if (parsed != null && !parsed.isAfter(today)) initialEnd = parsed;
    }
    if (initialStart.isAfter(initialEnd)) initialStart = initialEnd;
    final themeName = context.read<ThemeProvider>().themeName;
    final colors = PeadraTheme.getColors(themeName);
    final firstTransaction = await _db.getFirstTransactionDate();
    if (!mounted) return;
    final picked = await showPeadraModal<DateTimeRange>(
      context: context,
      builder: (_) => CustomRangeDialog(
        initialStart: initialStart,
        initialEnd: initialEnd,
        lastDate: today,
        firstTransactionDate: firstTransaction,
        colors: colors,
      ),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _customStart = picked.start.toIso8601String().substring(0, 10);
      _customEnd = picked.end.toIso8601String().substring(0, 10);
    });
    _loadChartData();
  }

  void _clearCustomRange() {
    setState(() {
      _selectedMonths = 6;
      _customStart = null;
      _customEnd = null;
    });
    _loadChartData();
  }

  Widget _buildTimeFilterButtons(PeadraColors colors) {
    final options = [
      {'label': Translator.t('period_3m'), 'value': 3},
      {'label': Translator.t('period_6m'), 'value': 6},
      {'label': Translator.t('period_1y'), 'value': 12},
      {'label': Translator.t('segment_all'), 'value': 24},
      {'label': Translator.t('period_custom'), 'value': -1},
    ];

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Container(
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: options.map((option) {
              final value = option['value'] as int;
              final isCustomOption = value == -1;
              final isSelected = isCustomOption
                  ? _isCustomRange
                  : !_isCustomRange && _selectedMonths == value;
              return GestureDetector(
                onTap: () {
                  if (isCustomOption) {
                    _pickCustomRange();
                    return;
                  }
                  setState(() {
                    _selectedMonths = value;
                    _customStart = null;
                    _customEnd = null;
                  });
                  // Preset and custom-range switches only affect the
                  // cash-flow / assets-history charts, so reuse the light
                  // 2-query chart loader instead of the full _loadData.
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
          ),
        ),
        if (_isCustomRange)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.date_range,
                    size: 14, color: colors.textSecondary),
                const SizedBox(width: 6),
                GestureDetector(
                  onTap: _pickCustomRange,
                  child: Text(
                    '$_customStart → $_customEnd',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: colors.text,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: _clearCustomRange,
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(Icons.close,
                        size: 14, color: colors.textSecondary),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildPieChartCard(PeadraColors colors, String title,
      Map<String, Decimal> data, String currency, int maxCategories,
      {Map<String, String> itemColors = const {},
      String? drillTag,
      Map<String, Decimal>? drillData,
      bool drillLoading = false,
      bool showAll = false,
      ValueChanged<String>? onSectionTap,
      VoidCallback? onBack}) {
    final drilled = drillTag != null;
    final expanded = drilled || showAll;
    final effectiveData = drilled ? (drillData ?? <String, Decimal>{}) : data;
    final effectiveMax = showAll && !drilled ? effectiveData.length : maxCategories;
    final pieData = effectiveData.entries.map((e) {
      final entryColor = itemColors[e.key];
      return {
        'label': e.key,
        'amount': e.value,
        'color': ?entryColor,
      };
    }).toList();

    return Card(
      color: colors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: SizedBox(
          height: 220,
          child: drillLoading
              ? Center(
                  child: CircularProgressIndicator(color: colors.accent),
                )
              : AnimatedSwitcher(
                  duration: const Duration(milliseconds: 350),
                  switchInCurve: Curves.easeOut,
                  switchOutCurve: Curves.easeIn,
                  transitionBuilder: (child, animation) {
                    return FadeTransition(
                      opacity: animation,
                      child: ScaleTransition(
                        scale: Tween<double>(begin: 0.96, end: 1.0)
                            .animate(animation),
                        child: child,
                      ),
                    );
                  },
                    child: CategoryPieChart(
                      key: ValueKey<String>(drilled
                          ? 'drill:$drillTag'
                          : (showAll ? 'all' : 'tags')),
                      data: pieData,
                      colors: colors,
                      title: drilled ? drillTag : title,
                      onTitleBack: expanded ? onBack : null,
                      currency: currency,
                      maxCategories: effectiveMax,
                      onSectionTap: drilled ? null : onSectionTap,
                    ),
                ),
        ),
      ),
    );
  }

  void _onAssetsSectionTap({required String label}) {
    if (label == Translator.t('dash_other')) {
      setState(() => _assetsShowAll = true);
      return;
    }
    if (label == Translator.t('acc_type_checking') ||
        label == Translator.t('acc_type_savings')) {
      final type = label == Translator.t('acc_type_checking') ? 'checking' : 'savings';
      if (_assetsDrillType == type) return;
      setState(() {
        _assetsDrillType = type;
        _assetsShowAll = false;
      });
    }
  }

  void _onAssetsBack() {
    setState(() {
      if (_assetsDrillType != null) {
        _assetsDrillType = null;
        _assetsShowAll = false;
      } else {
        _assetsShowAll = false;
      }
    });
  }

  Widget _buildAssetsDistributionPieChart(
      PeadraColors colors, String currency, int maxCategories) {
    final checkingLabel = Translator.t('acc_type_checking');
    final savingsLabel = Translator.t('acc_type_savings');

    Decimal clampPositive(num v) =>
        Decimal.parse(v.clamp(0.0, double.infinity).toString());

    final Map<String, Decimal> typeData = {
      checkingLabel: Decimal.zero,
      savingsLabel: Decimal.zero,
    };
    for (final a in _accountsDistribution) {
      final t = a['type'] as String?;
      final amount = clampPositive((a['value'] as num?)?.toDouble() ?? 0.0);
      if (t == 'checking') {
        typeData[checkingLabel] = typeData[checkingLabel]! + amount;
      } else if (t == 'savings') {
        typeData[savingsLabel] = typeData[savingsLabel]! + amount;
      }
    }
    typeData.removeWhere((_, v) => v <= Decimal.zero);

    final drilled = _assetsDrillType != null;
    final drillLabel =
        _assetsDrillType == 'checking' ? checkingLabel : savingsLabel;
    final Map<String, Decimal> drillData = {};
    final Map<String, String> drillColors = {};
    if (drilled) {
      for (final a in _accountsDistribution) {
        if ((a['type'] as String?) != _assetsDrillType) continue;
        final name = a['name'] as String? ?? '';
        if (name.isEmpty) continue;
        drillData[name] =
            clampPositive((a['value'] as num?)?.toDouble() ?? 0.0);
        drillColors[name] = (a['color'] as String?) ?? '#1976D2';
      }
      drillData.removeWhere((_, v) => v <= Decimal.zero);
    }

    return _buildPieChartCard(
      colors,
      Translator.t('dash_assets_distribution'),
      typeData,
      currency,
      maxCategories,
      itemColors: drilled ? drillColors : const {},
      drillTag: drilled ? drillLabel : null,
      drillData: drillData,
      showAll: _assetsShowAll,
      onSectionTap: (label) => _onAssetsSectionTap(label: label),
      onBack: _onAssetsBack,
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeName =
        context.select<ThemeProvider, String>((t) => t.themeName);
    final colors = PeadraTheme.getColors(themeName);
    final currency = context.select<SettingsProvider, String>((s) => s.currency);
    final maxPieCategories =
        context.select<SettingsProvider, int>((s) => s.maxPieCategories);
    final lineChartDots =
        context.select<SettingsProvider, bool>((s) => s.lineChartDots);
    final isTagMode =
        context.select<SettingsProvider, bool>((s) => s.dashboardPieView == 'tags');
    final username = context.select<AuthProvider, String>((a) => a.username);

    if (_loading) {
      return Center(
        child: CircularProgressIndicator(color: colors.accent),
      );
    }

    final header = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          Translator.t('dash_title', params: {'user': username}),
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.bold,
            color: colors.text,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          Translator.t('dash_welcome'),
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
      _isCustomRange
          ? Translator.t('dash_expenses')
          : Translator.t('dash_this_month_expenses'),
      _monthlyExpenses,
      currency,
      maxPieCategories,
      itemColors: _tagColors,
      drillTag: _expenseDrillTag,
      drillData: _expenseDrillData,
      drillLoading: _expenseDrillLoading,
      showAll: _expenseShowAll,
      onSectionTap: isTagMode
          ? (tag) => _onPieSectionTap(isExpense: true, tag: tag)
          : null,
      onBack: () => _onPieBack(isExpense: true),
    );
    final incomePie = _buildPieChartCard(
      colors,
      _isCustomRange
          ? Translator.t('dash_income')
          : Translator.t('dash_this_month_incomes'),
      _monthlyIncomes,
      currency,
      maxPieCategories,
      itemColors: _tagColors,
      drillTag: _incomeDrillTag,
      drillData: _incomeDrillData,
      drillLoading: _incomeDrillLoading,
      showAll: _incomeShowAll,
      onSectionTap: isTagMode
          ? (tag) => _onPieSectionTap(isExpense: false, tag: tag)
          : null,
      onBack: () => _onPieBack(isExpense: false),
    );
    final assetsPie = _buildAssetsDistributionPieChart(
        colors, currency, maxPieCategories);

    final averageSection = _buildAverageSection(colors, currency);
    return LayoutBuilder(
      builder: (context, constraints) {
        // The total-assets card adapts to the layout that is actually
        // rendered (content width), not the window width: on a resized
        // desktop window the mobile layout is used, so the card must use
        // the mobile treatment too.
        final isNarrow = constraints.maxWidth <= 800;
        final totalAsset =
            _buildTotalAssetCard(colors, currency, isNarrow: isNarrow);
        if (constraints.maxWidth > 800) {
          return DashboardViewDesktop(
            header: header,
            totalAsset: totalAsset,
            statCards: statCards,
            cashFlowSection: cashFlowSection,
            expensePie: expensePie,
            incomePie: incomePie,
            assetsPie: assetsPie,
            averageSection: averageSection,
            colors: colors,
            cashFlowData: _cashFlowData,
            assetsHistory: _assetsHistory,
            showLineDots: lineChartDots,
          );
        } else {
          return DashboardViewMobile(
            header: header,
            totalAsset: totalAsset,
            statCards: statCards,
            cashFlowSection: cashFlowSection,
            expensePie: expensePie,
            incomePie: incomePie,
            assetsPie: assetsPie,
            averageSection: averageSection,
            colors: colors,
            cashFlowData: _cashFlowData,
            assetsHistory: _assetsHistory,
            showLineDots: lineChartDots,
          );
        }
      },
    );
  }

  /// Amount display for narrow layouts: horizontally scrollable when it
  /// does not fit, so a long amount can be swiped to be fully read.
  Widget _buildScrollableAssetAmount(PeadraColors colors, String amount) {
    return SizedBox(
      width: double.infinity,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Text(
          amount,
          maxLines: 1,
          softWrap: false,
          overflow: TextOverflow.visible,
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.bold,
            color: colors.accent,
          ),
        ),
      ),
    );
  }

  Widget _buildTotalAssetCard(PeadraColors colors, String currency,
      {required bool isNarrow}) {
    final previousTotal = _previousBalance + _previousSavings;
    final totalChange = previousTotal > Decimal.zero
        ? ((_totalAssets - previousTotal) * Decimal.fromInt(100) / previousTotal).toDouble()
        : 0.0;
    final formattedAmount = CurrencyService.formatAmount(_totalAssets, currency);
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
                Text(
                  Translator.t('dash_total_assets'),
                  style: TextStyle(
                    fontSize: 12,
                    color: colors.textSecondary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                _buildChangeIndicator(totalChange, colors),
              ],
            ),
            const SizedBox(height: 8),
            if (isNarrow) ...[
              _buildScrollableAssetAmount(colors, formattedAmount),
            ] else ...[
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  formattedAmount,
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: colors.accent,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
