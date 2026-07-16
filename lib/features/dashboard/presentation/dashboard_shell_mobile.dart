import 'package:flutter/material.dart';

import '../../../core/i18n/translator.dart';
import '../../../core/theme/paedra_colors.dart';
import '../../../core/services/update_service.dart';

class DashboardShellMobile extends StatelessWidget {
  final int selectedIndex;
  final double totalPatrimony;
  final UpdateInfo? availableUpdate;
  final bool updateBannerDismissed;
  final Widget? updateBanner;
  final List<Widget> views;
  final ValueChanged<int> onNavTap;
  final VoidCallback onLogout;
  final VoidCallback onDismissUpdate;
  final PeadraColors colors;

  const DashboardShellMobile({
    super.key,
    required this.selectedIndex,
    required this.totalPatrimony,
    this.availableUpdate,
    required this.updateBannerDismissed,
    this.updateBanner,
    required this.views,
    required this.onNavTap,
    required this.onLogout,
    required this.onDismissUpdate,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: colors.surface,
      body: Column(
        children: [
          if (updateBanner != null) updateBanner!,
          Expanded(child: _buildContent()),
        ],
      ),
      bottomNavigationBar: _buildBottomNav(),
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

  Widget _buildBottomNav() {
    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(top: BorderSide(color: colors.borderColor)),
      ),
      child: BottomNavigationBar(
        currentIndex: selectedIndex.clamp(0, 3),
        onTap: onNavTap,
        type: BottomNavigationBarType.fixed,
        backgroundColor: colors.surface,
        selectedItemColor: colors.accent,
        unselectedItemColor: colors.placeholderColor,
        selectedFontSize: 12,
        unselectedFontSize: 12,
        items: [
          BottomNavigationBarItem(
            icon: const Icon(Icons.dashboard_outlined),
            activeIcon: const Icon(Icons.dashboard),
            label: Translator.t('nav_dashboard'),
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.receipt_long_outlined),
            activeIcon: const Icon(Icons.receipt_long),
            label: Translator.t('nav_transactions'),
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.account_balance_wallet_outlined),
            activeIcon: const Icon(Icons.account_balance_wallet),
            label: Translator.t('nav_accounts'),
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.bubble_chart_outlined),
            activeIcon: const Icon(Icons.bubble_chart),
            label: Translator.t('nav_categories'),
          ),
        ],
      ),
    );
  }
}
