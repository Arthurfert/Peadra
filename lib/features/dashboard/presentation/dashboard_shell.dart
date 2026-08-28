import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:decimal/decimal.dart';
import 'package:provider/provider.dart';

import '../../../core/i18n/translator.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../core/providers/update_provider.dart';
import '../../../core/providers/theme_provider.dart';
import '../../../core/theme/peadra_colors.dart';
import '../../../core/services/update_service.dart';
import '../../../core/responsive/responsive_layout.dart';
import '../../../core/database/database_manager.dart';
import '../../../sync/sync_service.dart';
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
  Decimal _totalPatrimony = Decimal.zero;
  int _dashboardRefreshSignal = 0;
  String _lastCurrency = '';
  bool _updateBannerDismissed = false;
  StreamSubscription<void>? _remoteDataSub;

  late final List<Widget> _staticViews = [
    TransactionsView(onDataChanged: _loadTotalPatrimony),
    const AccountsView(),
    const CategoriesView(),
    const ParametersView(showBackButton: false),
  ];

  List<Widget> get _views => [
        DashboardView(refreshSignal: _dashboardRefreshSignal),
        ..._staticViews,
      ];

  @override
  void initState() {
    super.initState();
    _checkForUpdate();
    _remoteDataSub =
        DatabaseManager.instance.onRemoteDataApplied.listen((_) {
      _loadTotalPatrimony();
    });
  }

  @override
  void dispose() {
    _remoteDataSub?.cancel();
    super.dispose();
  }

  void _checkForUpdate() {
    context.read<UpdateProvider>().checkForUpdate();
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
          _dashboardRefreshSignal++;
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
    unawaited(SyncService.instance.stop());
    auth.logout(db);
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const LoginView()),
    );
  }

  Widget _buildUpdateBanner(PeadraColors colors, UpdateInfo update) {
    final isPhone = ResponsiveLayout.isPhone(context);
    return Material(
      color: colors.success.withValues(alpha: 0.1),
      child: SafeArea(
        bottom: false,
        child: InkWell(
          onTap: isPhone ? () => _onNavTap(4) : null,
          child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              Icon(Icons.system_update, color: colors.success, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  Translator.t('param_update_status_available',
                      params: {'version': update.version}),
                  style: TextStyle(
                    color: colors.text,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              if (!isPhone) ...[
                TextButton(
                  onPressed: () => _showChangelogDialog(colors, update),
                  child: Text(
                    Translator.t('param_see_whats_new'),
                    style: TextStyle(
                      color: colors.success,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () => UpdateService().openDownloadUrl(update.downloadUrl),
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
      ),
    );
  }

  void _showChangelogDialog(PeadraColors colors, UpdateInfo update) {
    final notes = update.releaseNotes;
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
                        '${update.version} - ${Translator.t('param_changelog_title')}',
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
                    ? Markdown(
                        data: notes,
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                        selectable: true,
                        styleSheet: MarkdownStyleSheet(
                          p: TextStyle(color: colors.text, fontSize: 14, height: 1.5),
                          h1: TextStyle(color: colors.text, fontSize: 22, fontWeight: FontWeight.bold),
                          h2: TextStyle(color: colors.text, fontSize: 18, fontWeight: FontWeight.bold),
                          h3: TextStyle(color: colors.text, fontSize: 16, fontWeight: FontWeight.w600),
                          h4: TextStyle(color: colors.text, fontSize: 14, fontWeight: FontWeight.w600),
                          h5: TextStyle(color: colors.text, fontSize: 13, fontWeight: FontWeight.w600),
                          h6: TextStyle(color: colors.textSecondary, fontSize: 12, fontWeight: FontWeight.w600),
                          blockquote: TextStyle(color: colors.textSecondary, fontSize: 14, height: 1.5),
                          blockquoteDecoration: BoxDecoration(
                            border: Border(
                              left: BorderSide(color: colors.accent, width: 3),
                            ),
                          ),
                          code: TextStyle(
                            color: colors.textSecondary,
                            fontSize: 13,
                            fontFamily: 'monospace',
                            backgroundColor: colors.bg,
                          ),
                          codeblockDecoration: BoxDecoration(
                            color: colors.bg,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          listBullet: TextStyle(color: colors.text, fontSize: 14),
                          listIndent: 24,
                          horizontalRuleDecoration: BoxDecoration(
                            border: Border(
                              top: BorderSide(color: colors.borderColor, width: 1),
                            ),
                          ),
                          a: TextStyle(color: colors.accent, decoration: TextDecoration.underline),
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
    final showNavLabels = context.watch<SettingsProvider>().showNavLabels;
    final availableUpdate = context.watch<UpdateProvider>().availableUpdate;

    final updateBanner = (availableUpdate != null && !_updateBannerDismissed)
        ? _buildUpdateBanner(colors, availableUpdate)
        : null;

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth > 800) {
          return DashboardShellDesktop(
            selectedIndex: _selectedIndex,
            totalPatrimony: _totalPatrimony,
            updateBanner: updateBanner,
            views: _views,
            onNavTap: _onNavTap,
            onLogout: _logout,
            isDark: isDark,
            colors: colors,
          );
        } else {
          return DashboardShellMobile(
            selectedIndex: _selectedIndex,
            updateBanner: updateBanner,
            views: _views,
            onNavTap: _onNavTap,
            onLogout: _logout,
            showNavLabels: showNavLabels,
            colors: colors,
          );
        }
      },
    );
  }
}
