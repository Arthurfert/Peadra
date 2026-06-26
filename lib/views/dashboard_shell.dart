import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../i18n/translator.dart';
import '../providers/auth_provider.dart';
import '../providers/theme_provider.dart';
import '../providers/settings_provider.dart';
import '../components/theme/paedra_colors.dart';
import '../responsive/responsive_layout.dart';
import '../database/database_manager.dart';
import 'login_view.dart';
import 'dashboard_view.dart';
import 'transactions_view.dart';
import 'accounts_view.dart';
import 'subscriptions_view.dart';
import 'categories_view.dart';
import 'parameters_view.dart';

class DashboardShell extends StatefulWidget {
  const DashboardShell({super.key});

  @override
  State<DashboardShell> createState() => _DashboardShellState();
}

class _DashboardShellState extends State<DashboardShell> {
  int _selectedIndex = 0;

  final _views = const [
    DashboardView(),
    TransactionsView(),
    AccountsView(),
    SubscriptionsView(),
    CategoriesView(),
  ];

  void _onNavTap(int index) {
    if (index == 5) {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const ParametersView()),
      );
      return;
    }
    setState(() => _selectedIndex = index);
  }

  void _logout() {
    final auth = context.read<AuthProvider>();
    final db = DatabaseManager.instance;
    auth.logout(db);
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const LoginView()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeName = context.watch<ThemeProvider>().themeName;
    final colors = PeadraTheme.getColors(themeName);
    final screenSize = ResponsiveLayout.getScreenSize(context);

    return Scaffold(
      backgroundColor: colors.bg,
      body: Row(
        children: [
          if (screenSize != ScreenSize.phone)
            _buildSidebar(colors, screenSize),
          Expanded(child: _views[_selectedIndex]),
        ],
      ),
      bottomNavigationBar:
          screenSize == ScreenSize.phone ? _buildBottomNav(colors) : null,
    );
  }

  Widget _buildSidebar(PeadraColors colors, ScreenSize screenSize) {
    final isCompact = screenSize == ScreenSize.tablet;
    final width = isCompact ? 72.0 : 280.0;

    final items = [
      (Icons.dashboard_outlined, Icons.dashboard, Translator.t('nav_dashboard')),
      (Icons.receipt_long_outlined, Icons.receipt_long, Translator.t('nav_transactions')),
      (Icons.account_balance_wallet_outlined, Icons.account_balance_wallet, Translator.t('nav_accounts')),
      (Icons.calendar_month_outlined, Icons.calendar_month, Translator.t('nav_subscriptions')),
      (Icons.bubble_chart_outlined, Icons.bubble_chart, Translator.t('nav_categories')),
    ];

    return Container(
      width: width,
      color: colors.surface,
      child: Column(
        children: [
          const SizedBox(height: 24),
          ...items.asMap().entries.map((entry) {
            final i = entry.key;
            final item = entry.value;
            final isSelected = _selectedIndex == i;
            return _buildNavItem(
              iconOff: item.$1,
              iconOn: item.$2,
              label: item.$3,
              isSelected: isSelected,
              colors: colors,
              isCompact: isCompact,
              onTap: () => _onNavTap(i),
            );
          }),
          const Spacer(),
          _buildNavItem(
            iconOff: Icons.settings_outlined,
            iconOn: Icons.settings,
            label: Translator.t('nav_parameters'),
            isSelected: false,
            colors: colors,
            isCompact: isCompact,
            onTap: () => _onNavTap(5),
          ),
          _buildNavItem(
            iconOff: Icons.logout_outlined,
            iconOn: Icons.logout,
            label: Translator.t('btn_logout'),
            isSelected: false,
            colors: colors,
            isCompact: isCompact,
            onTap: _logout,
          ),
          const SizedBox(height: 16),
        ],
      ),
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
                            fontWeight:
                                isSelected ? FontWeight.w600 : FontWeight.normal,
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

  Widget _buildBottomNav(PeadraColors colors) {
    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(top: BorderSide(color: colors.borderColor)),
      ),
      child: BottomNavigationBar(
        currentIndex: _selectedIndex.clamp(0, 4),
        onTap: _onNavTap,
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
            icon: const Icon(Icons.calendar_month_outlined),
            activeIcon: const Icon(Icons.calendar_month),
            label: Translator.t('nav_subscriptions'),
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
