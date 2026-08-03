import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/i18n/translator.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/providers/theme_provider.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../core/providers/language_provider.dart';
import '../../../core/database/database_manager.dart';
import '../../../core/theme/peadra_colors.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/services/biometric_service.dart';
import '../../../core/services/currency_service.dart';
import '../../../core/services/export_service.dart';
import '../../../core/services/update_service.dart';
import '../../../shared/widgets/peadra_notification.dart';
import '../../../core/services/log_service.dart';
import '../../import_data/presentation/import_data_view.dart';
import '../../auth/presentation/login_view.dart';
import '../../../core/responsive/responsive_layout.dart';

class ParametersView extends StatefulWidget {
  final bool showBackButton;

  const ParametersView({super.key, this.showBackButton = true});

  @override
  State<ParametersView> createState() => _ParametersViewState();
}

class _ParametersViewState extends State<ParametersView> {
  final _db = DatabaseManager.instance;
  final _authService = AuthService(DatabaseManager.instance);
  final _biometricService = BiometricService();
  final _updateService = UpdateService();

  String _currentVersion = '';
  UpdateInfo? _availableUpdate;
  _UpdateStatus _updateStatus = _UpdateStatus.idle;
  bool _biometricAvailable = false;

  @override
  void initState() {
    super.initState();
    _loadVersion();
    _checkBiometricAvailability();
  }

  Future<void> _checkBiometricAvailability() async {
    final available = await _biometricService.isAvailable();
    if (mounted) setState(() => _biometricAvailable = available);
  }

  Future<void> _loadVersion() async {
    final version = await _updateService.getCurrentVersion();
    if (mounted) setState(() => _currentVersion = version);
  }

  Future<void> _checkForUpdate() async {
    setState(() => _updateStatus = _UpdateStatus.checking);
    try {
      final update = await _updateService.checkForUpdate();
      if (!mounted) return;
      setState(() {
        if (update != null) {
          _availableUpdate = update;
          _updateStatus = _UpdateStatus.available;
        } else {
          _updateStatus = _UpdateStatus.upToDate;
        }
      });
    } catch (e) {
      if (mounted) setState(() => _updateStatus = _UpdateStatus.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeName = context.watch<ThemeProvider>().themeName;
    final colors = PeadraTheme.getColors(themeName);
    final settings = context.watch<SettingsProvider>();
    final lang = context.watch<LanguageProvider>();
    final auth = context.watch<AuthProvider>();

    final isPhone = ResponsiveLayout.isPhone(context);

    return Scaffold(
      backgroundColor: colors.bg,
      appBar: isPhone ? null : AppBar(
        title: Text(Translator.t('param_title'),
            style: TextStyle(color: colors.text)),
        backgroundColor: colors.surface,
        iconTheme: IconThemeData(color: colors.text),
        automaticallyImplyLeading: widget.showBackButton,
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          if (isPhone) ...[
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Text(
                Translator.t('param_title'),
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: colors.text,
                ),
              ),
            ),
          ],
          _buildSection(Translator.t('param_general'), colors, [
            _buildLanguageTile(lang, colors),
            _buildCurrencyTile(settings, colors),
            _buildThemeTile(colors),
            if (isPhone) _buildNavLabelsTile(settings, colors),
          ], icon: Icons.settings),
          const SizedBox(height: 8),
          _buildSection(Translator.t('param_transactions'), colors, [
            _buildDisplayLimitTile(settings, colors),
          ], icon: Icons.receipt_long),
          const SizedBox(height: 8),
          _buildSection(Translator.t('param_charts'), colors, [
            _buildCategoriesViewTile(settings, colors),
            _buildDashboardPieViewTile(settings, colors),
            _buildLineChartDotsTile(settings, colors),
            _buildAssetsGranularityTile(settings, colors),
            _buildMonthModeTile(settings, colors),
            _buildMaxPieCategoriesTile(settings, colors),
          ], icon: Icons.bar_chart),
          const SizedBox(height: 8),
          _buildSection(Translator.t('param_database'), colors, [
            _buildMaxBackupsTile(settings, colors),
            if (!Platform.isAndroid && !Platform.isIOS)
              _buildLocateDatabaseTile(colors),
          ], icon: Icons.storage),
          const SizedBox(height: 8),
          _buildSection(Translator.t('param_security'), colors, [
            _buildUsernameTile(auth, colors),
            _buildPasswordTile(colors),
            if (_biometricAvailable) _buildBiometricTile(settings, colors),
          ], icon: Icons.shield),
          const SizedBox(height: 8),
          _buildSection(Translator.t('param_import'), colors, [
            _buildImportTile(colors),
            _buildExportCsvTile(colors),
            _buildExportLogsTile(colors),
          ], icon: Icons.import_export),
          const SizedBox(height: 8),
          _buildSection(Translator.t('param_updates'), colors, [
            _buildVersionTile(colors),
            _buildCheckUpdateTile(colors),
            if (_updateStatus == _UpdateStatus.available && _availableUpdate != null)
              _buildUpdateAvailableTile(colors),
          ], icon: Icons.system_update),
          const SizedBox(height: 8),
          _buildSection(Translator.t('param_danger_zone'), colors, [
            _buildDeleteAccountTile(colors),
          ], icon: Icons.warning_amber, iconColor: colors.error),
        ],
      ),
    );
  }

  Widget _buildSection(
      String title, PeadraColors colors, List<Widget> children, {
      IconData? icon, Color? iconColor}) {
    final isPhone = ResponsiveLayout.isPhone(context);
    final sectionColor = iconColor ?? colors.accent;

    return Card(
      color: colors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias,
      child: isPhone
          ? _buildSectionVertical(title, colors, children, sectionColor, icon)
          : _buildSectionHorizontal(title, colors, children, sectionColor, icon),
    );
  }

  Widget _buildSectionVertical(
      String title, PeadraColors colors, List<Widget> children,
      Color sectionColor, IconData? icon) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: sectionColor.withValues(alpha: 0.1),
          ),
          child: Row(
            children: [
              if (icon != null) ...[
                Icon(icon, color: sectionColor, size: 16),
                const SizedBox(width: 6),
              ],
              Text(title,
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: sectionColor)),
            ],
          ),
        ),
        Column(children: children),
      ],
    );
  }

  Widget _buildSectionHorizontal(
      String title, PeadraColors colors, List<Widget> children,
      Color sectionColor, IconData? icon) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            width: 110,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
            decoration: BoxDecoration(
              color: sectionColor.withValues(alpha: 0.1),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (icon != null) ...[
                  Icon(icon, color: sectionColor, size: 20),
                  const SizedBox(height: 6),
                ],
                Text(title,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: sectionColor)),
              ],
            ),
          ),
          VerticalDivider(width: 1, color: colors.borderColor),
          Expanded(
            child: Column(children: children),
          ),
        ],
      ),
    );
  }

  Widget _buildLanguageTile(LanguageProvider lang, PeadraColors colors) {
    return ListTile(
      title: Text(Translator.t('param_language_label'),
          style: TextStyle(color: colors.text)),
      subtitle: Text(Translator.t('param_language_desc'),
          style: TextStyle(color: colors.placeholderColor, fontSize: 12)),
      trailing: DropdownButton<String>(
        value: lang.language,
        dropdownColor: colors.surface,
        style: TextStyle(color: colors.text),
        items: const [
          DropdownMenuItem(value: 'en', child: Text('English')),
          DropdownMenuItem(value: 'fr', child: Text('Fran\u00e7ais')),
        ],
        onChanged: (v) async {
          if (v != null) {
            lang.setLanguage(v);
            await _db.setSetting('language', v);
          }
        },
      ),
    );
  }

  Widget _buildCurrencyTile(SettingsProvider settings, PeadraColors colors) {
    return ListTile(
      title: Text(Translator.t('param_currency'),
          style: TextStyle(color: colors.text)),
      subtitle: Text(Translator.t('param_currency_desc'),
          style: TextStyle(color: colors.placeholderColor, fontSize: 12)),
      trailing: DropdownButton<String>(
        value: settings.currency,
        dropdownColor: colors.surface,
        style: TextStyle(color: colors.text),
        items: CurrencyService.allCodes
            .map((c) => DropdownMenuItem(
                  value: c,
                  child: Text('$c ${CurrencyService.getSymbol(c)}'),
                ))
            .toList(),
        onChanged: (v) async {
          if (v != null) settings.setCurrency(v, _db);
        },
      ),
    );
  }

  Widget _buildThemeTile(PeadraColors colors) {
    final themeProvider = context.watch<ThemeProvider>();
    return ListTile(
      title: Text(Translator.t('param_theme_label'),
          style: TextStyle(color: colors.text)),
      subtitle: Text(Translator.t('param_theme_desc'),
          style: TextStyle(color: colors.placeholderColor, fontSize: 12)),
      trailing: DropdownButton<String>(
        value: themeProvider.themeName,
        dropdownColor: colors.surface,
        style: TextStyle(color: colors.text),
        items: [
          DropdownMenuItem(
              value: 'light',
              child: Text(Translator.t('param_light_theme'))),
          DropdownMenuItem(
              value: 'dark',
              child: Text(Translator.t('param_dark_theme'))),
          DropdownMenuItem(
              value: 'autumn',
              child: Text(Translator.t('param_autumn_theme'))),
          DropdownMenuItem(
              value: 'summer',
              child: Text(Translator.t('param_summer_theme'))),
        ],
        onChanged: (v) async {
          if (v != null) {
            themeProvider.setTheme(v);
            await _db.setSetting('theme_mode', v);
          }
        },
      ),
    );
  }

  Widget _buildNavLabelsTile(SettingsProvider settings, PeadraColors colors) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(Translator.t('param_nav_labels'),
              style: TextStyle(color: colors.text)),
          const SizedBox(height: 4),
          Text(Translator.t('param_nav_labels_desc'),
              style: TextStyle(color: colors.placeholderColor, fontSize: 12)),
          const SizedBox(height: 12),
          Switch(
            value: settings.showNavLabels,
            onChanged: (value) => settings.setShowNavLabels(value, _db),
            activeThumbColor: colors.accent,
          ),
        ],
      ),
    );
  }

  Widget _buildDisplayLimitTile(SettingsProvider settings, PeadraColors colors) {
    return ListTile(
      title: Text(Translator.t('param_display_limit'),
          style: TextStyle(color: colors.text)),
      subtitle: Text(Translator.t('param_display_limit_desc'),
          style: TextStyle(color: colors.placeholderColor, fontSize: 12)),
      trailing: DropdownButton<int>(
        value: settings.displayLimit,
        dropdownColor: colors.surface,
        style: TextStyle(color: colors.text),
        items: [15, 30, 50, 100]
            .map((n) => DropdownMenuItem(value: n, child: Text('$n')))
            .toList(),
        onChanged: (v) async {
          if (v != null) settings.setDisplayLimit(v, _db);
        },
      ),
    );
  }

  Widget _buildCategoriesViewTile(SettingsProvider settings, PeadraColors colors) {
    return ListTile(
      title: Text(Translator.t('param_categories_view'),
          style: TextStyle(color: colors.text)),
      subtitle: Text(Translator.t('param_categories_view_desc'),
          style: TextStyle(color: colors.placeholderColor, fontSize: 12)),
      trailing: DropdownButton<String>(
        value: settings.categoriesView,
        dropdownColor: colors.surface,
        style: TextStyle(color: colors.text),
        items: [
          DropdownMenuItem(
              value: 'descriptions',
              child: Text(Translator.t('param_categories_descriptions'))),
          DropdownMenuItem(
              value: 'tags',
              child: Text(Translator.t('param_categories_tags'))),
        ],
        onChanged: (v) async {
          if (v != null) settings.setCategoriesView(v, _db);
        },
      ),
    );
  }

  Widget _buildDashboardPieViewTile(SettingsProvider settings, PeadraColors colors) {
    return ListTile(
      title: Text(Translator.t('param_dashboard_pie_view'),
          style: TextStyle(color: colors.text)),
      subtitle: Text(Translator.t('param_dashboard_pie_view_desc'),
          style: TextStyle(color: colors.placeholderColor, fontSize: 12)),
      trailing: DropdownButton<String>(
        value: settings.dashboardPieView,
        dropdownColor: colors.surface,
        style: TextStyle(color: colors.text),
        items: [
          DropdownMenuItem(
              value: 'descriptions',
              child: Text(Translator.t('param_categories_descriptions'))),
          DropdownMenuItem(
              value: 'tags',
              child: Text(Translator.t('param_categories_tags'))),
        ],
        onChanged: (v) async {
          if (v != null) settings.setDashboardPieView(v, _db);
        },
      ),
    );
  }

  Widget _buildLineChartDotsTile(SettingsProvider settings, PeadraColors colors) {
    final isPhone = ResponsiveLayout.isPhone(context);

    final toggle = Switch(
      value: settings.lineChartDots,
      onChanged: (value) => settings.setLineChartDots(value, _db),
      activeThumbColor: colors.accent,
    );

    if (isPhone) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(Translator.t('param_line_chart_dots'),
                style: TextStyle(color: colors.text)),
            const SizedBox(height: 4),
            Text(Translator.t('param_line_chart_dots_desc'),
                style: TextStyle(color: colors.placeholderColor, fontSize: 12)),
            const SizedBox(height: 12),
            toggle,
          ],
        ),
      );
    }

    return ListTile(
      title: Text(Translator.t('param_line_chart_dots'),
          style: TextStyle(color: colors.text)),
      subtitle: Text(Translator.t('param_line_chart_dots_desc'),
          style: TextStyle(color: colors.placeholderColor, fontSize: 12)),
      trailing: toggle,
    );
  }

  Widget _buildAssetsGranularityTile(
      SettingsProvider settings, PeadraColors colors) {
    return ListTile(
      title: Text(Translator.t('param_assets_granularity'),
          style: TextStyle(color: colors.text)),
      subtitle: Text(Translator.t('param_assets_granularity_desc'),
          style: TextStyle(color: colors.placeholderColor, fontSize: 12)),
      trailing: DropdownButton<String>(
        value: settings.assetsGranularity,
        dropdownColor: colors.surface,
        style: TextStyle(color: colors.text),
        items: [
          DropdownMenuItem(
              value: 'monthly',
              child: Text(Translator.t('param_assets_monthly'))),
          DropdownMenuItem(
              value: 'daily',
              child: Text(Translator.t('param_assets_daily'))),
        ],
        onChanged: (v) async {
          if (v != null) settings.setAssetsGranularity(v, _db);
        },
      ),
    );
  }

  Widget _buildMonthModeTile(SettingsProvider settings, PeadraColors colors) {
    final isStrict = settings.monthMode == 'strict';
    final isPhone = ResponsiveLayout.isPhone(context);

    final modeButtons = Container(
      decoration: BoxDecoration(
        color: colors.bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildMonthModeButton(
            label: Translator.t('param_calendar_month'),
            icon: Icons.calendar_month,
            isSelected: isStrict,
            colors: colors,
            onTap: () => settings.setMonthMode('strict', _db),
          ),
          _buildMonthModeButton(
            label: Translator.t('param_rolling_30'),
            icon: Icons.update,
            isSelected: !isStrict,
            colors: colors,
            onTap: () => settings.setMonthMode('rolling', _db),
          ),
        ],
      ),
    );

    if (isPhone) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(Translator.t('param_month_mode'),
                style: TextStyle(color: colors.text)),
            const SizedBox(height: 4),
            Text(Translator.t('param_month_mode_desc'),
                style: TextStyle(color: colors.placeholderColor, fontSize: 12)),
            const SizedBox(height: 12),
            modeButtons,
          ],
        ),
      );
    }

    return ListTile(
      title: Text(Translator.t('param_month_mode'),
          style: TextStyle(color: colors.text)),
      subtitle: Text(Translator.t('param_month_mode_desc'),
          style: TextStyle(color: colors.placeholderColor, fontSize: 12)),
      trailing: modeButtons,
    );
  }

  Widget _buildMonthModeButton({
    required String label,
    required IconData icon,
    required bool isSelected,
    required PeadraColors colors,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? colors.accent : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                size: 14,
                color: isSelected ? Colors.white : colors.placeholderColor),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: isSelected ? Colors.white : colors.placeholderColor,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMaxPieCategoriesTile(
      SettingsProvider settings, PeadraColors colors) {
    return ListTile(
      title: Text(Translator.t('param_max_categories'),
          style: TextStyle(color: colors.text)),
      subtitle: Text(Translator.t('param_max_categories_desc'),
          style: TextStyle(color: colors.placeholderColor, fontSize: 12)),
      trailing: DropdownButton<int>(
        value: settings.maxPieCategories,
        dropdownColor: colors.surface,
        style: TextStyle(color: colors.text),
        items: [3, 5, 7, 10]
            .map((n) => DropdownMenuItem(value: n, child: Text('$n')))
            .toList(),
        onChanged: (v) async {
          if (v != null) settings.setMaxPieCategories(v, _db);
        },
      ),
    );
  }

  Widget _buildMaxBackupsTile(SettingsProvider settings, PeadraColors colors) {
    return ListTile(
      title: Text(Translator.t('param_max_backups'),
          style: TextStyle(color: colors.text)),
      subtitle: Text(Translator.t('param_max_backups_desc'),
          style: TextStyle(color: colors.placeholderColor, fontSize: 12)),
      trailing: DropdownButton<int>(
        value: settings.maxBackups,
        dropdownColor: colors.surface,
        style: TextStyle(color: colors.text),
        items: [1, 2, 3, 5, 10, 15, 20]
            .map((n) => DropdownMenuItem(value: n, child: Text(n.toString())))
            .toList(),
        onChanged: (v) async {
          if (v != null) settings.setMaxBackups(v, _db);
        },
      ),
    );
  }

  Widget _buildLocateDatabaseTile(PeadraColors colors) {
    return ListTile(
      title: Text(Translator.t('param_locate_database'),
          style: TextStyle(color: colors.text)),
      subtitle: Text(Translator.t('param_locate_database_desc'),
          style: TextStyle(color: colors.placeholderColor, fontSize: 12)),
      trailing: ElevatedButton.icon(
        icon: const Icon(Icons.folder_open, color: Colors.white, size: 16),
        label: Text(Translator.t('param_locate_database'),
            style: const TextStyle(color: Colors.white, fontSize: 12)),
        style: ElevatedButton.styleFrom(
          backgroundColor: colors.accent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
        onPressed: () async {
          final db = await _db.database;
          final path = db.path;
          final dir = File(path).parent.path;
          if (Platform.isLinux) {
            await Process.run('xdg-open', [dir]);
          } else if (Platform.isMacOS) {
            await Process.run('open', [dir]);
          } else if (Platform.isWindows) {
            await Process.run('explorer', [dir]);
          }
        },
      ),
    );
  }

  Widget _buildUsernameTile(AuthProvider auth, PeadraColors colors) {
    final controller = TextEditingController(text: auth.username);
    final isPhone = ResponsiveLayout.isPhone(context);

    final usernameField = SizedBox(
      width: isPhone ? double.infinity : 180,
      child: TextField(
        controller: controller,
        style: TextStyle(color: colors.text),
        maxLength: 50,
        decoration: InputDecoration(
          isDense: true,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: colors.borderColor),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: colors.borderColor),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: colors.accent),
          ),
          filled: true,
          fillColor: colors.bg,
        ),
        onSubmitted: (value) async {
          if (value.trim().isEmpty || value.trim() == auth.username) return;
          try {
            final success =
                await _authService.updateUsername(auth.userId!, value.trim());
            if (success && mounted) {
              auth.setUsername(value.trim());
              PeadraNotification.show(context, message: Translator.t('param_username_saved'));
            }
          } catch (e) {
            if (mounted) {
              PeadraNotification.show(context, message: e.toString(), type: NotificationType.error);
            }
          }
        },
      ),
    );

    if (isPhone) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(Translator.t('param_username'),
                style: TextStyle(color: colors.text)),
            const SizedBox(height: 4),
            Text(Translator.t('param_username_desc'),
                style: TextStyle(color: colors.placeholderColor, fontSize: 12)),
            const SizedBox(height: 12),
            usernameField,
          ],
        ),
      );
    }

    return ListTile(
      title: Text(Translator.t('param_username'),
          style: TextStyle(color: colors.text)),
      subtitle: Text(Translator.t('param_username_desc'),
          style: TextStyle(color: colors.placeholderColor, fontSize: 12)),
      trailing: usernameField,
    );
  }

  Widget _buildPasswordTile(PeadraColors colors) {
    final isPhone = ResponsiveLayout.isPhone(context);

    final changeButton = ElevatedButton.icon(
      icon: const Icon(Icons.lock, color: Colors.white, size: 16),
      label: Text(Translator.t('param_change_password'),
          style: const TextStyle(color: Colors.white, fontSize: 12)),
      style: ElevatedButton.styleFrom(
        backgroundColor: colors.accent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
      onPressed: () => _showChangePasswordDialog(colors),
    );

    if (isPhone) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(Translator.t('param_password'),
                style: TextStyle(color: colors.text)),
            const SizedBox(height: 4),
            Text(Translator.t('param_password_desc'),
                style: TextStyle(color: colors.placeholderColor, fontSize: 12)),
            const SizedBox(height: 12),
            changeButton,
          ],
        ),
      );
    }

    return ListTile(
      title: Text(Translator.t('param_password'),
          style: TextStyle(color: colors.text)),
      subtitle: Text(Translator.t('param_password_desc'),
          style: TextStyle(color: colors.placeholderColor, fontSize: 12)),
      trailing: changeButton,
    );
  }

  void _showChangePasswordDialog(PeadraColors colors) {
    final oldPasswordController = TextEditingController();
    final newPasswordController = TextEditingController();
    final confirmPasswordController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: colors.surface,
        title: Text(Translator.t('param_change_password'),
            style: TextStyle(color: colors.text)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: oldPasswordController,
                obscureText: true,
                maxLength: 128,
                style: TextStyle(color: colors.text),
                decoration: InputDecoration(
                  labelText: Translator.t('param_old_password'),
                  labelStyle: TextStyle(color: colors.placeholderColor),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  filled: true,
                  fillColor: colors.bg,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: newPasswordController,
                obscureText: true,
                maxLength: 128,
                style: TextStyle(color: colors.text),
                decoration: InputDecoration(
                  labelText: Translator.t('param_new_password'),
                  labelStyle: TextStyle(color: colors.placeholderColor),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  filled: true,
                  fillColor: colors.bg,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: confirmPasswordController,
                obscureText: true,
                maxLength: 128,
                style: TextStyle(color: colors.text),
                decoration: InputDecoration(
                  labelText: Translator.t('param_password_confirm'),
                  labelStyle: TextStyle(color: colors.placeholderColor),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  filled: true,
                  fillColor: colors.bg,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(Translator.t('btn_cancel'),
                style: TextStyle(color: colors.placeholderColor)),
          ),
          ElevatedButton(
            onPressed: () async {
              final oldPass = oldPasswordController.text;
              final newPass = newPasswordController.text;
              final confirmPass = confirmPasswordController.text;

              if (oldPass.isEmpty || newPass.isEmpty) {
                PeadraNotification.show(context, message: Translator.t('param_password_empty'), type: NotificationType.warning);
                return;
              }
              if (newPass != confirmPass) {
                PeadraNotification.show(context, message: Translator.t('param_password_mismatch'), type: NotificationType.warning);
                return;
              }

              try {
                final auth = context.read<AuthProvider>();
                final settings = context.read<SettingsProvider>();
                final success = await _authService.updatePassword(
                    auth.userId!, oldPass, newPass);
                if (success && mounted) {
                  await _biometricService.clearCredentials();
                  await settings.setBiometricEnabled(false, _db);
                  Navigator.of(ctx).pop();
                  PeadraNotification.show(context, message: Translator.t('param_biometric_re_enable'), type: NotificationType.warning);
                }
              } catch (e) {
                if (mounted) {
                  PeadraNotification.show(context, message: Translator.t('param_old_password_incorrect'), type: NotificationType.error);
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: colors.accent,
              foregroundColor: Colors.white,
            ),
            child: Text(Translator.t('param_btn_save')),
          ),
        ],
      ),
    );
  }

  Widget _buildBiometricTile(SettingsProvider settings, PeadraColors colors) {
    final isPhone = ResponsiveLayout.isPhone(context);

    final toggle = Switch(
      value: settings.biometricEnabled,
      onChanged: (value) async {
        if (value) {
          final authenticated = await _biometricService.authenticate(
            reason: Translator.t('param_biometric_desc'),
          );
          if (!authenticated) {
            if (mounted) {
              PeadraNotification.show(context,
                  message: Translator.t('param_biometric_failed'),
                  type: NotificationType.error);
            }
            return;
          }
          final auth = context.read<AuthProvider>();
          await _biometricService.saveCredentials(auth.userId!, auth.username, encryptionKey: _db.encryptionKey);
          await settings.setBiometricEnabled(true, _db);
          if (mounted) {
            PeadraNotification.show(context,
                message: Translator.t('param_biometric_enabled'));
          }
        } else {
          await _biometricService.clearCredentials();
          await settings.setBiometricEnabled(false, _db);
          if (mounted) {
            PeadraNotification.show(context,
                message: Translator.t('param_biometric_disabled'));
          }
        }
      },
      activeThumbColor: colors.accent,
    );

    if (isPhone) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(Translator.t('param_biometric'),
                style: TextStyle(color: colors.text)),
            const SizedBox(height: 4),
            Text(Translator.t('param_biometric_desc'),
                style: TextStyle(color: colors.placeholderColor, fontSize: 12)),
            const SizedBox(height: 12),
            toggle,
          ],
        ),
      );
    }

    return ListTile(
      title: Text(Translator.t('param_biometric'),
          style: TextStyle(color: colors.text)),
      subtitle: Text(Translator.t('param_biometric_desc'),
          style: TextStyle(color: colors.placeholderColor, fontSize: 12)),
      trailing: toggle,
    );
  }

  Widget _buildImportTile(PeadraColors colors) {
    return ListTile(
      title: Text(Translator.t('btn_import'),
          style: TextStyle(color: colors.text)),
      subtitle: Text(Translator.t('import_select_csv_desc'),
          style: TextStyle(color: colors.placeholderColor, fontSize: 12)),
      trailing: Icon(Icons.chevron_right, color: colors.placeholderColor),
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const ImportDataView()),
        );
      },
    );
  }

  Widget _buildExportCsvTile(PeadraColors colors) {
    return ListTile(
      title: Text('${Translator.t('btn_export')} CSV',
          style: TextStyle(color: colors.text)),
      subtitle: Text(Translator.t('btn_export_desc'),
          style: TextStyle(color: colors.placeholderColor, fontSize: 12)),
      onTap: () async {
        try {
          final exportService = ExportService();
          final content = await exportService.exportToCsv();
          final path =
              await exportService.saveToFile(content: content, format: 'csv');
          if (mounted && path != null) {
            LogService().log('CSV exported to: $path');
            final isMobile = Platform.isAndroid || Platform.isIOS;
            final message = isMobile
                ? Translator.t('msg_export_success_mobile')
                : Translator.t('msg_export_success').replaceAll('{file_path}', path);
            PeadraNotification.show(context, message: message);
          }
        } catch (e) {
          if (mounted) {
            PeadraNotification.show(context, message: Translator.t('msg_export_error'), type: NotificationType.error);
          }
        }
      },
    );
  }

  Widget _buildExportLogsTile(PeadraColors colors) {
    return ListTile(
      title: Text(Translator.t('param_export_logs'),
          style: TextStyle(color: colors.text)),
      subtitle: Text(Translator.t('param_export_logs_desc'),
          style: TextStyle(color: colors.placeholderColor, fontSize: 12)),
      onTap: () async {
        try {
          final isMobile = Platform.isAndroid || Platform.isIOS;
          final content = LogService().buildContent();

          if (isMobile) {
            final path = await LogService().export();
            LogService().log('Session logs exported to: $path');
            if (mounted) {
              PeadraNotification.show(context, message: Translator.t('msg_export_success_mobile').replaceAll('CSV', 'logs'));
            }
          } else {
            final exportService = ExportService();
            final path = await exportService.saveToFile(content: content, format: 'txt', fileName: 'peadra_log.txt');
            if (mounted && path != null) {
              LogService().log('Session logs exported to: $path');
              PeadraNotification.show(context, message: Translator.t('msg_export_success').replaceAll('{file_path}', path));
            }
          }
        } catch (e) {
          if (mounted) {
            PeadraNotification.show(context, message: Translator.t('msg_export_error'), type: NotificationType.error);
          }
        }
      },
    );
  }

  Widget _buildDeleteAccountTile(PeadraColors colors) {
    final isPhone = ResponsiveLayout.isPhone(context);

    final deleteButton = ElevatedButton.icon(
      icon: const Icon(Icons.delete, color: Colors.white, size: 16),
      label: Text(Translator.t('param_delete_account'),
          style: const TextStyle(color: Colors.white, fontSize: 12)),
      style: ElevatedButton.styleFrom(
        backgroundColor: colors.deleteColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
      onPressed: () => _showDeleteAccountDialog(colors),
    );

    if (isPhone) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(Translator.t('param_delete_account'),
                style: TextStyle(color: colors.error)),
            const SizedBox(height: 4),
            Text(Translator.t('param_delete_account_desc'),
                style: TextStyle(color: colors.placeholderColor, fontSize: 12)),
            const SizedBox(height: 12),
            deleteButton,
          ],
        ),
      );
    }

    return ListTile(
      title: Text(Translator.t('param_delete_account'),
          style: TextStyle(color: colors.error)),
      subtitle: Text(Translator.t('param_delete_account_desc'),
          style: TextStyle(color: colors.placeholderColor, fontSize: 12)),
      trailing: deleteButton,
    );
  }

  Widget _buildVersionTile(PeadraColors colors) {
    return ListTile(
      title: Text(Translator.t('param_version'),
          style: TextStyle(color: colors.text)),
      trailing: Text(
        _currentVersion.isNotEmpty ? 'v$_currentVersion' : '...',
        style: TextStyle(
          color: colors.textSecondary,
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _buildCheckUpdateTile(PeadraColors colors) {
    final isChecking = _updateStatus == _UpdateStatus.checking;
    return ListTile(
      title: Text(Translator.t('param_check_updates'),
          style: TextStyle(color: colors.text)),
      subtitle: Text(_updateStatusText(colors),
          style: TextStyle(color: colors.placeholderColor, fontSize: 12)),
      trailing: isChecking
          ? SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: colors.accent,
              ),
            )
          : IconButton(
              icon: Icon(Icons.refresh, color: colors.accent),
              onPressed: _checkForUpdate,
            ),
    );
  }

  Widget _buildUpdateAvailableTile(PeadraColors colors) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.download, color: colors.success, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  Translator.t('param_update_status_available', params: {'version': _availableUpdate!.version}),
                  style: TextStyle(color: colors.success, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              TextButton(
                onPressed: () => _showChangelogDialog(colors),
                child: Text(
                  Translator.t('param_see_whats_new'),
                  style: TextStyle(color: colors.success, fontSize: 12),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                icon: const Icon(Icons.open_in_new, color: Colors.white, size: 16),
                label: Text(Translator.t('param_install_update'),
                    style: const TextStyle(color: Colors.white, fontSize: 12)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: colors.success,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                onPressed: () => _updateService.openDownloadUrl(_availableUpdate!.downloadUrl),
              ),
            ],
          ),
        ],
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

  String _updateStatusText(PeadraColors colors) {
    switch (_updateStatus) {
      case _UpdateStatus.idle:
        return Translator.t('param_update_status_idle');
      case _UpdateStatus.checking:
        return Translator.t('param_update_status_checking');
      case _UpdateStatus.available:
        return '';
      case _UpdateStatus.upToDate:
        return Translator.t('param_update_status_up_to_date');
      case _UpdateStatus.error:
        return Translator.t('param_update_status_error', params: {'error': ''});
    }
  }

  void _showDeleteAccountDialog(PeadraColors colors) {
    final passwordController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: colors.surface,
        title: Row(
          children: [
            Icon(Icons.warning, color: colors.error),
            const SizedBox(width: 8),
            Text(Translator.t('param_delete_confirm'),
                style: TextStyle(color: colors.error)),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(Translator.t('param_delete_warning'),
                  style: TextStyle(color: colors.text)),
              const SizedBox(height: 16),
              Text(Translator.t('param_delete_password_prompt'),
                  style: TextStyle(color: colors.text)),
              const SizedBox(height: 8),
              TextField(
                controller: passwordController,
                obscureText: true,
                maxLength: 128,
                style: TextStyle(color: colors.text),
                decoration: InputDecoration(
                  labelText: Translator.t('param_password'),
                  labelStyle: TextStyle(color: colors.placeholderColor),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  filled: true,
                  fillColor: colors.bg,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(Translator.t('btn_cancel'),
                style: TextStyle(color: colors.placeholderColor)),
          ),
          ElevatedButton(
            onPressed: () async {
              final password = passwordController.text;
              if (password.isEmpty) {
                PeadraNotification.show(context, message: Translator.t('param_delete_password_required'), type: NotificationType.warning);
                return;
              }

              try {
                final success = await _db.deleteUserAccount(password);
                if (success && mounted) {
                  Navigator.of(ctx).pop();
                  final auth = context.read<AuthProvider>();
                  auth.logout(_db);
                  Navigator.of(context).pushAndRemoveUntil(
                    MaterialPageRoute(builder: (_) => const LoginView()),
                    (route) => false,
                  );
                } else if (mounted) {
                  PeadraNotification.show(context, message: Translator.t('param_delete_password_incorrect'), type: NotificationType.error);
                }
              } catch (e) {
                if (mounted) {
                  PeadraNotification.show(context, message: e.toString(), type: NotificationType.error);
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: colors.deleteColor,
              foregroundColor: Colors.white,
            ),
            child: Text(Translator.t('param_delete_confirm')),
          ),
        ],
      ),
    );
  }
}

enum _UpdateStatus { idle, checking, available, upToDate, error }
