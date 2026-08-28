import 'package:flutter/material.dart';
import 'package:decimal/decimal.dart';
import 'package:provider/provider.dart';

import '../../../core/i18n/translator.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../core/theme/peadra_colors.dart';
import '../../../core/services/currency_service.dart';
import '../../../core/responsive/responsive_layout.dart';

class DashboardShellDesktop extends StatelessWidget {
  final int selectedIndex;
  final Decimal totalPatrimony;
  final Widget? updateBanner;
  final List<Widget> views;
  final ValueChanged<int> onNavTap;
  final VoidCallback onLogout;
  final bool isDark;
  final PeadraColors colors;

  const DashboardShellDesktop({
    super.key,
    required this.selectedIndex,
    required this.totalPatrimony,
    this.updateBanner,
    required this.views,
    required this.onNavTap,
    required this.onLogout,
    required this.isDark,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    final screenSize = ResponsiveLayout.getScreenSize(context);
    final isCompact = screenSize == ScreenSize.tablet;

    return Scaffold(
      backgroundColor: colors.surface,
      body: Column(
        children: [
          if (updateBanner != null) updateBanner!,
          _buildTopBar(context),
          Expanded(
            child: Row(
              children: [
                _buildSidebar(context, isCompact),
                Expanded(child: _buildContent()),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopBar(BuildContext context) {
    return Container(
      height: 72,
      color: colors.surface,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        children: [
          Image.asset(
            isDark ? 'assets/Peadra_white.png' : 'assets/Peadra.png',
            height: 40,
            errorBuilder: (context, error, stackTrace) => Icon(
              Icons.pets,
              color: colors.accent,
              size: 32,
            ),
          ),
          const SizedBox(width: 12),
          Text(
            'Peadra',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: colors.text,
            ),
          ),
          const Spacer(),
          IconButton(
            icon: Icon(Icons.settings, color: colors.textSecondary),
            onPressed: () => onNavTap(5),
            tooltip: Translator.t('tooltip_settings'),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: Icon(Icons.logout, color: colors.textSecondary),
            onPressed: onLogout,
            tooltip: Translator.t('tooltip_logout'),
          ),
        ],
      ),
    );
  }

  Widget _buildSidebar(BuildContext context, bool isCompact) {
    final width = isCompact ? 72.0 : 280.0;

    final items = [
      (Icons.dashboard_outlined, Icons.dashboard,
          Translator.t('nav_dashboard')),
      (Icons.receipt_long_outlined, Icons.receipt_long,
          Translator.t('nav_transactions')),
      (Icons.account_balance_wallet_outlined, Icons.account_balance_wallet,
          Translator.t('nav_accounts')),
      (Icons.bubble_chart_outlined, Icons.bubble_chart,
          Translator.t('nav_categories')),
    ];

    return Container(
      width: width,
      color: colors.surface,
      child: Column(
        children: [
          const SizedBox(height: 8),
          ...items.asMap().entries.map((entry) {
            final i = entry.key;
            final item = entry.value;
            final isSelected = selectedIndex == i;
            return _buildNavItem(
              iconOff: item.$1,
              iconOn: item.$2,
              label: item.$3,
              isSelected: isSelected,
              colors: colors,
              isCompact: isCompact,
              onTap: () => onNavTap(i),
            );
          }),
          const Spacer(),
          _buildTotalAssets(context, isCompact),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildTotalAssets(BuildContext context, bool isCompact) {
    final currency = context.watch<SettingsProvider>().currency;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: isCompact ? 8 : 20,
        vertical: 16,
      ),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: const BorderRadius.only(
          topRight: Radius.circular(12),
        ),
      ),
      child: isCompact
          ? Column(
              children: [
                Icon(Icons.account_balance_wallet,
                    color: colors.accent, size: 24),
                const SizedBox(height: 6),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    CurrencyService.formatAmount(totalPatrimony, currency),
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: colors.text,
                    ),
                  ),
                ),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  Translator.t('dash_total_assets'),
                  style: TextStyle(
                    fontSize: 14,
                    color: colors.textSecondary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 6),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    CurrencyService.formatAmount(totalPatrimony, currency),
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: colors.text,
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildContent() {
    return Container(
      margin: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.bg,
        borderRadius: BorderRadius.circular(20),
      ),
      clipBehavior: Clip.antiAlias,
      child: views[selectedIndex.clamp(0, views.length - 1)],
    );
  }

  Widget _buildNavItem({
    required IconData iconOff,
    required IconData iconOn,
    required String label,
    required bool isSelected,
    required PeadraColors colors,
    required bool isCompact,
    required VoidCallback onTap,
  }) {
    final iconColor = isSelected ? colors.navSelectedFg : colors.textSecondary;
    final bgColor = isSelected ? colors.navSelectedBg : Colors.transparent;
    final textColor = isSelected ? colors.navSelectedFg : colors.text;

    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: isCompact ? 8 : 16,
        vertical: 2,
      ),
      child: Material(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: isCompact ? 12 : 16,
              vertical: 12,
            ),
            child: isCompact
                ? Icon(
                    isSelected ? iconOn : iconOff,
                    color: iconColor,
                    size: 24,
                  )
                : Row(
                    children: [
                      Icon(
                        isSelected ? iconOn : iconOff,
                        color: iconColor,
                        size: 24,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          label,
                          style: TextStyle(
                            color: textColor,
                            fontWeight: isSelected
                                ? FontWeight.w600
                                : FontWeight.normal,
                            fontSize: 15,
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}
