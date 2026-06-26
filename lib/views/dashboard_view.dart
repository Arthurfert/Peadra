import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../i18n/translator.dart';
import '../providers/theme_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/auth_provider.dart';
import '../database/database_manager.dart';
import '../components/theme/paedra_colors.dart';
import '../services/currency_service.dart';
import '../components/charts/monthly_bar_chart.dart';
import '../components/charts/category_pie_chart.dart';
import '../responsive/responsive_layout.dart';

class DashboardView extends StatefulWidget {
  const DashboardView({super.key});

  @override
  State<DashboardView> createState() => _DashboardViewState();
}

class _DashboardViewState extends State<DashboardView> {
  final _db = DatabaseManager.instance;
  double _totalPatrimony = 0;
  double _balance = 0;
  double _savings = 0;
  Map<String, double> _monthlySummary = {};
  List<Map<String, dynamic>> _accountsDistribution = [];
  List<Map<String, dynamic>> _categoryDistribution = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final results = await Future.wait([
      _db.getTotalPatrimony(),
      _db.getBalance(),
      _db.getSavingsTotal(),
      _db.getMonthlySummary(),
      _db.getAccountsDistribution(),
      _db.getCategoryDistribution(transactionType: 'expense', limit: 8),
    ]);

    if (mounted) {
      setState(() {
        _totalPatrimony = results[0] as double;
        _balance = results[1] as double;
        _savings = results[2] as double;
        _monthlySummary = results[3] as Map<String, double>;
        _accountsDistribution = results[4] as List<Map<String, dynamic>>;
        _categoryDistribution = results[5] as List<Map<String, dynamic>>;
        _loading = false;
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
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${Translator.t("dash_welcome")}, $username',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: colors.text,
            ),
          ),
          const SizedBox(height: 24),
          _buildStatCards(colors, currency),
          const SizedBox(height: 24),

          // Charts row
          if (isPhone) ...[
            _buildBarChartCard(colors),
            const SizedBox(height: 16),
            _buildPieChartCard(colors),
          ] else ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 3, child: _buildBarChartCard(colors)),
                const SizedBox(width: 16),
                Expanded(flex: 2, child: _buildPieChartCard(colors)),
              ],
            ),
          ],
          const SizedBox(height: 24),

          // Monthly summary
          _buildMonthlySummary(colors, currency),
          const SizedBox(height: 24),

          if (_accountsDistribution.isNotEmpty)
            _buildAccountDistribution(colors, currency),
        ],
      ),
    );
  }

  Widget _buildStatCards(PeadraColors colors, String currency) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final crossCount = constraints.maxWidth > 600 ? 4 : 2;
        return GridView.count(
          crossAxisCount: crossCount,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 1.5,
          children: [
            _buildStatCard(
              Translator.t('dash_total_assets'),
              CurrencyService.formatAmount(_totalPatrimony, currency),
              colors.chartAsset,
              colors.chartAssetBg,
            ),
            _buildStatCard(
              Translator.t('dash_monthly_income'),
              CurrencyService.formatAmount(
                  _monthlySummary['income'] ?? 0, currency),
              colors.success,
              colors.incomeBg,
            ),
            _buildStatCard(
              Translator.t('dash_monthly_expenses'),
              CurrencyService.formatAmount(
                  _monthlySummary['expenses'] ?? 0, currency),
              colors.error,
              colors.expenseBg,
            ),
            _buildStatCard(
              Translator.t('dash_savings'),
              CurrencyService.formatAmount(_savings, currency),
              colors.savingsIcon,
              colors.savingsBg,
            ),
          ],
        );
      },
    );
  }

  Widget _buildStatCard(
      String title, String value, Color iconColor, Color bgColor) {
    return Card(
      color: bgColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              title,
              style: TextStyle(
                fontSize: 12,
                color: iconColor.withOpacity(0.8),
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
                  color: iconColor,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBarChartCard(PeadraColors colors) {
    return Card(
      color: colors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: SizedBox(
          height: 220,
          child: MonthlyBarChart(
            data: _categoryDistribution,
            colors: colors,
          ),
        ),
      ),
    );
  }

  Widget _buildPieChartCard(PeadraColors colors) {
    // Convert category distribution for pie chart
    final pieData = _categoryDistribution
        .where((d) => d['type'] == 'expense')
        .map((d) => {
              'label': d['description'] ?? d['name'] ?? '',
              'amount': d['amount'] as double,
            })
        .toList();

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
            title: Translator.t('chart_top_expenses'),
          ),
        ),
      ),
    );
  }

  Widget _buildMonthlySummary(PeadraColors colors, String currency) {
    final income = _monthlySummary['income'] ?? 0;
    final expenses = _monthlySummary['expenses'] ?? 0;

    return Card(
      color: colors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              Translator.t('dash_inflows_outflows'),
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: colors.text,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _buildFlowItem(
                    Translator.t('dash_inflows'),
                    CurrencyService.formatAmount(income, currency),
                    colors.success,
                    colors.incomeBg,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildFlowItem(
                    Translator.t('dash_outflows'),
                    CurrencyService.formatAmount(expenses, currency),
                    colors.error,
                    colors.expenseBg,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFlowItem(
      String label, String amount, Color color, Color bgColor) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: TextStyle(fontSize: 12, color: color.withOpacity(0.8))),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              amount,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAccountDistribution(PeadraColors colors, String currency) {
    return Card(
      color: colors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              Translator.t('dash_assets_distribution'),
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: colors.text,
              ),
            ),
            const SizedBox(height: 16),
            ..._accountsDistribution.map((acct) {
              final color = PeadraTheme.hexToColor(acct['color'] as String);
              final value = (acct['value'] as num).toDouble();
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        acct['name'] as String,
                        style: TextStyle(color: colors.text, fontSize: 14),
                      ),
                    ),
                    Text(
                      CurrencyService.formatAmount(value, currency),
                      style: TextStyle(
                        color: value >= 0 ? colors.success : colors.error,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}
