import 'package:flutter/material.dart';

import '../../../core/theme/peadra_colors.dart';
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
      backgroundColor: colors.bg,
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
    return views[selectedIndex.clamp(0, views.length - 1)];
  }

  Widget _buildBottomNav() {
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
        selectedFontSize: 0,
        unselectedFontSize: 0,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.dashboard_outlined),
            activeIcon: Icon(Icons.dashboard),
            label: '',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.receipt_long_outlined),
            activeIcon: Icon(Icons.receipt_long),
            label: '',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.account_balance_wallet_outlined),
            activeIcon: Icon(Icons.account_balance_wallet),
            label: '',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.bubble_chart_outlined),
            activeIcon: Icon(Icons.bubble_chart),
            label: '',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.settings_outlined),
            activeIcon: Icon(Icons.settings),
            label: '',
          ),
        ],
      ),
    );
  }
}
