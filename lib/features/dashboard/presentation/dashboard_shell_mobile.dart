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

  void _showMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: colors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.account_balance_wallet_outlined),
              title: Text(Translator.t('nav_accounts')),
              onTap: () {
                Navigator.pop(ctx);
                onNavTap(4);
              },
            ),
            ListTile(
              leading: const Icon(Icons.settings_outlined),
              title: Text(Translator.t('nav_settings')),
              onTap: () {
                Navigator.pop(ctx);
                onNavTap(5);
              },
            ),
          ],
        ),
      ),
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
            Translator.t('nav_budgets'),
            Translator.t('nav_categories'),
            Translator.t('nav_menu'),
          ]
        : List.filled(5, '');

    // Accounts (4) and settings (5) live behind the burger menu, which
    // stays highlighted while one of them is displayed.
    final currentIndex =
        selectedIndex <= 3 ? selectedIndex : 4;

    return Builder(
      builder: (context) => Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      clipBehavior: Clip.antiAlias,
      child: BottomNavigationBar(
        currentIndex: currentIndex,
        onTap: (index) {
          if (index == 4) {
            _showMenu(context);
          } else {
            onNavTap(index);
          }
        },
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
            icon: const Icon(Icons.flag_outlined),
            activeIcon: const Icon(Icons.flag),
            label: labels[2],
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.bubble_chart_outlined),
            activeIcon: const Icon(Icons.bubble_chart),
            label: labels[3],
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.menu),
            label: labels[4],
          ),
        ],
      ),
    ),
    );
  }
}
