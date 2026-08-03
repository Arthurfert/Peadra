import 'package:flutter/material.dart';

import '../../../core/i18n/translator.dart';
import '../../../core/theme/peadra_colors.dart';

class DashboardShellMobile extends StatelessWidget {
  final int selectedIndex;
  final Widget? updateBanner;
  final List<Widget> views;
  final ValueChanged<int> onNavTap;
  final VoidCallback onLogout;
  final bool showNavLabels;
  final PeadraColors colors;

  const DashboardShellMobile({
    super.key,
    required this.selectedIndex,
    this.updateBanner,
    required this.views,
    required this.onNavTap,
    required this.onLogout,
    this.showNavLabels = false,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: colors.bg,
      body: SafeArea(
        child: Column(
          children: [
            if (updateBanner != null) updateBanner!,
            Expanded(child: _buildContent()),
          ],
        ),
      ),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  Widget _buildContent() {
    return views[selectedIndex.clamp(0, views.length - 1)];
  }

  Widget _buildBottomNav() {
    final labels = showNavLabels
        ? [
            Translator.t('nav_dashboard'),
            Translator.t('nav_transactions'),
            Translator.t('nav_accounts'),
            Translator.t('nav_categories'),
            Translator.t('nav_settings'),
          ]
        : List.filled(5, '');

    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      clipBehavior: Clip.antiAlias,
      child: BottomNavigationBar(
        currentIndex: selectedIndex.clamp(0, 4),
        onTap: onNavTap,
        type: BottomNavigationBarType.fixed,
        backgroundColor: colors.surface,
        selectedItemColor: colors.accent,
        unselectedItemColor: colors.placeholderColor,
        selectedFontSize: showNavLabels ? 11 : 0,
        unselectedFontSize: showNavLabels ? 11 : 0,
        items: [
          BottomNavigationBarItem(
            icon: const Icon(Icons.dashboard_outlined),
            activeIcon: const Icon(Icons.dashboard),
            label: labels[0],
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.receipt_long_outlined),
            activeIcon: const Icon(Icons.receipt_long),
            label: labels[1],
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.account_balance_wallet_outlined),
            activeIcon: const Icon(Icons.account_balance_wallet),
            label: labels[2],
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.bubble_chart_outlined),
            activeIcon: const Icon(Icons.bubble_chart),
            label: labels[3],
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.settings_outlined),
            activeIcon: const Icon(Icons.settings),
            label: labels[4],
          ),
        ],
      ),
    );
  }
}
