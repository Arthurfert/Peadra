import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/i18n/translator.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../core/providers/theme_provider.dart';
import '../../../core/theme/peadra_colors.dart';
import '../../../core/services/update_service.dart';
import '../../../core/responsive/responsive_layout.dart';
import '../../../core/database/database_manager.dart';
import '../../auth/presentation/login_view.dart';
import '../../transactions/presentation/transactions_view.dart';
import '../../accounts/presentation/accounts_view.dart';
import '../../categories/presentation/categories_view.dart';
import '../../parameters/presentation/parameters_view.dart';
import 'dashboard_view.dart';
import 'dashboard_shell_desktop.dart';
import 'dashboard_shell_mobile.dart';

class DashboardShell extends StatefulWidget {
  const DashboardShell({super.key});

  @override
  State<DashboardShell> createState() => _DashboardShellState();
}

class _DashboardShellState extends State<DashboardShell> {
  int _selectedIndex = 0;
  double _totalPatrimony = 0;
  String _lastCurrency = '';
  UpdateInfo? _availableUpdate;
  late final List<Widget> _views;
  bool _updateBannerDismissed = false;

  @override
  void initState() {
    super.initState();
    _views = [
      const DashboardView(),
      TransactionsView(onDataChanged: _loadTotalPatrimony),
      const AccountsView(),
      const CategoriesView(),
      const ParametersView(showBackButton: false),
    ];
    _checkForUpdate();
  }

  Future<void> _checkForUpdate() async {
    final update = await UpdateService().checkForUpdate();
    if (mounted && update != null) {
      setState(() => _availableUpdate = update);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final currency = context.watch<SettingsProvider>().currency;
    if (currency != _lastCurrency) {
      _lastCurrency = currency;
      _loadTotalPatrimony();
    }
  }

  Future<void> _loadTotalPatrimony() async {
    try {
      final db = DatabaseManager.instance;
      if (db.userId == null) return;
      final currency = context.read<SettingsProvider>().currency;
      final total = await db.getTotalPatrimony(targetCurrency: currency);
      if (mounted) {
        setState(() {
          _totalPatrimony = total;
        });
      }
    } catch (_) {}
  }

  void _onNavTap(int index) {
    if (index == 4 || index == 5) {
      if (ResponsiveLayout.isPhone(context)) {
        setState(() => _selectedIndex = 4);
        _loadTotalPatrimony();
      } else {
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const ParametersView()),
        ).then((_) => _loadTotalPatrimony());
      }
      return;
    }
    setState(() => _selectedIndex = index);
    if (index == 0) {
      _loadTotalPatrimony();
    }
  }

  void _logout() {
    final auth = context.read<AuthProvider>();
    final db = DatabaseManager.instance;
    auth.logout(db);
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const LoginView()),
    );
  }

  Widget _buildUpdateBanner(PeadraColors colors) {
    final isPhone = ResponsiveLayout.isPhone(context);
    return Material(
      color: colors.success.withValues(alpha: 0.1),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              Icon(Icons.system_update, color: colors.success, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  Translator.t('param_update_status_available',
                      params: {'version': _availableUpdate!.version}),
                  style: TextStyle(
                    color: colors.text,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              if (!isPhone) ...[
                TextButton(
                  onPressed: () => _showChangelogDialog(colors),
                  child: Text(
                    Translator.t('param_see_whats_new'),
                    style: TextStyle(
                      color: colors.success,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () => UpdateService().openDownloadUrl(_availableUpdate!.downloadUrl),
                  child: Text(
                    Translator.t('param_install_update'),
                    style: TextStyle(
                      color: colors.success,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
              IconButton(
                icon:
                    Icon(Icons.close, color: colors.placeholderColor, size: 18),
                onPressed: () =>
                    setState(() => _updateBannerDismissed = true),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showChangelogDialog(PeadraColors colors) {
    final notes = _availableUpdate!.releaseNotes;
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: colors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 500, maxHeight: 500),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 8, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${_availableUpdate!.version} - ${Translator.t('param_changelog_title')}',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: colors.text,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.close, color: colors.placeholderColor, size: 20),
                      onPressed: () => Navigator.of(ctx).pop(),
                    ),
                  ],
                ),
              ),
              const Divider(),
              Flexible(
                child: notes.isNotEmpty
                    ? SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                        child: SelectableText(
                          notes,
                          style: TextStyle(color: colors.text, fontSize: 14, height: 1.5),
                        ),
                      )
                    : Padding(
                        padding: const EdgeInsets.all(20),
                        child: Text(
                          Translator.t('param_changelog_empty'),
                          style: TextStyle(color: colors.placeholderColor),
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeName = context.watch<ThemeProvider>().themeName;
    final colors = PeadraTheme.getColors(themeName);
    final isDark = context.watch<ThemeProvider>().isDark;

    final updateBanner = (_availableUpdate != null && !_updateBannerDismissed)
        ? _buildUpdateBanner(colors)
        : null;

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth > 800) {
          return DashboardShellDesktop(
            selectedIndex: _selectedIndex,
            totalPatrimony: _totalPatrimony,
            availableUpdate: _availableUpdate,
            updateBannerDismissed: _updateBannerDismissed,
            updateBanner: updateBanner,
            views: _views,
            onNavTap: _onNavTap,
            onLogout: _logout,
            onDismissUpdate: () =>
                setState(() => _updateBannerDismissed = true),
            isDark: isDark,
            colors: colors,
          );
        } else {
          return DashboardShellMobile(
            selectedIndex: _selectedIndex,
            totalPatrimony: _totalPatrimony,
            availableUpdate: _availableUpdate,
            updateBannerDismissed: _updateBannerDismissed,
            updateBanner: updateBanner,
            views: _views,
            onNavTap: _onNavTap,
            onLogout: _logout,
            onDismissUpdate: () =>
                setState(() => _updateBannerDismissed = true),
            colors: colors,
          );
        }
      },
    );
  }
}
