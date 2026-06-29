import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../i18n/translator.dart';
import '../providers/auth_provider.dart';
import '../providers/theme_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/language_provider.dart';
import '../database/database_manager.dart';
import '../components/theme/paedra_colors.dart';
import '../services/auth_service.dart';
import '../services/currency_service.dart';
import '../services/export_service.dart';
import 'import_data_view.dart';
import 'login_view.dart';

class ParametersView extends StatefulWidget {
  const ParametersView({super.key});

  @override
  State<ParametersView> createState() => _ParametersViewState();
}

class _ParametersViewState extends State<ParametersView> {
  final _db = DatabaseManager.instance;
  final _authService = AuthService(DatabaseManager.instance);

  @override
  Widget build(BuildContext context) {
    final themeName = context.watch<ThemeProvider>().themeName;
    final colors = PeadraTheme.getColors(themeName);
    final settings = context.watch<SettingsProvider>();
    final lang = context.watch<LanguageProvider>();
    final auth = context.watch<AuthProvider>();

    return Scaffold(
      backgroundColor: colors.bg,
      appBar: AppBar(
        title: Text(Translator.t('param_title'),
            style: TextStyle(color: colors.text)),
        backgroundColor: colors.surface,
        iconTheme: IconThemeData(color: colors.text),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildSection(Translator.t('param_general'), colors, [
            _buildLanguageTile(lang, colors),
            _buildCurrencyTile(settings, colors),
            _buildThemeTile(colors),
          ]),
          const SizedBox(height: 16),
          _buildSection(Translator.t('param_transactions'), colors, [
            _buildDisplayLimitTile(settings, colors),
          ]),
          const SizedBox(height: 16),
          _buildSection(Translator.t('param_charts'), colors, [
            _buildMonthModeTile(settings, colors),
            _buildMaxPieCategoriesTile(settings, colors),
          ]),
          const SizedBox(height: 16),
          _buildSection(Translator.t('param_security'), colors, [
            _buildUsernameTile(auth, colors),
            _buildPasswordTile(colors),
          ]),
          const SizedBox(height: 16),
          _buildSection(Translator.t('param_import'), colors, [
            _buildImportTile(colors),
            _buildExportJsonTile(colors),
            _buildExportCsvTile(colors),
          ]),
          const SizedBox(height: 16),
          _buildSection(Translator.t('param_danger_zone'), colors, [
            _buildDeleteAccountTile(colors),
          ]),
        ],
      ),
    );
  }

  Widget _buildSection(
      String title, PeadraColors colors, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            if (title == Translator.t('param_security'))
              Icon(Icons.shield, color: colors.accent, size: 20),
            if (title == Translator.t('param_charts'))
              Icon(Icons.bar_chart, color: colors.accent, size: 20),
            if (title == Translator.t('param_danger_zone'))
              Icon(Icons.warning, color: colors.error, size: 20),
            if (title == Translator.t('param_security') ||
                title == Translator.t('param_charts') ||
                title == Translator.t('param_danger_zone'))
              const SizedBox(width: 8),
            Text(title,
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: title == Translator.t('param_danger_zone')
                        ? colors.error
                        : colors.accent)),
          ],
        ),
        const SizedBox(height: 8),
        Card(
          color: colors.surface,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Column(children: children),
        ),
      ],
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
            .take(10)
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

  Widget _buildMonthModeTile(SettingsProvider settings, PeadraColors colors) {
    final isStrict = settings.monthMode == 'strict';
    return ListTile(
      title: Text(Translator.t('param_month_mode'),
          style: TextStyle(color: colors.text)),
      subtitle: Text(Translator.t('param_month_mode_desc'),
          style: TextStyle(color: colors.placeholderColor, fontSize: 12)),
      trailing: Container(
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
      ),
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

  Widget _buildUsernameTile(AuthProvider auth, PeadraColors colors) {
    final controller = TextEditingController(text: auth.username);
    return ListTile(
      title: Text(Translator.t('param_username'),
          style: TextStyle(color: colors.text)),
      subtitle: Text(Translator.t('param_username_desc'),
          style: TextStyle(color: colors.placeholderColor, fontSize: 12)),
      trailing: SizedBox(
        width: 180,
        child: TextField(
          controller: controller,
          style: TextStyle(color: colors.text),
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
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                      content:
                          Text(Translator.t('param_username_saved'))),
                );
              }
            } catch (e) {
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(e.toString())),
                );
              }
            }
          },
        ),
      ),
    );
  }

  Widget _buildPasswordTile(PeadraColors colors) {
    return ListTile(
      title: Text(Translator.t('param_password'),
          style: TextStyle(color: colors.text)),
      subtitle: Text(Translator.t('param_password_desc'),
          style: TextStyle(color: colors.placeholderColor, fontSize: 12)),
      trailing: ElevatedButton.icon(
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
      ),
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
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                      content: Text(Translator.t('param_password_empty'))),
                );
                return;
              }
              if (newPass != confirmPass) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                      content:
                          Text(Translator.t('param_password_mismatch'))),
                );
                return;
              }

              try {
                final auth = context.read<AuthProvider>();
                final success = await _authService.updatePassword(
                    auth.userId!, oldPass, newPass);
                if (success && mounted) {
                  Navigator.of(ctx).pop();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                        content:
                            Text(Translator.t('param_password_saved'))),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                        content:
                            Text(Translator.t('param_old_password_incorrect'))),
                  );
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

  Widget _buildImportTile(PeadraColors colors) {
    return ListTile(
      leading: Icon(Icons.upload_file, color: colors.accent),
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

  Widget _buildExportJsonTile(PeadraColors colors) {
    return ListTile(
      leading: Icon(Icons.file_download, color: colors.accent),
      title: Text('${Translator.t('btn_export')} JSON',
          style: TextStyle(color: colors.text)),
      subtitle: Text('Export transactions as JSON',
          style: TextStyle(color: colors.placeholderColor, fontSize: 12)),
      onTap: () async {
        try {
          final exportService = ExportService();
          final content = await exportService.exportToJson();
          final path =
              await exportService.saveToFile(content: content, format: 'json');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                  content: Text(Translator.t('msg_export_success')
                      .replaceAll('{file_path}', path))),
            );
          }
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(Translator.t('msg_export_error'))),
            );
          }
        }
      },
    );
  }

  Widget _buildExportCsvTile(PeadraColors colors) {
    return ListTile(
      leading: Icon(Icons.table_chart, color: colors.accent),
      title: Text('${Translator.t('btn_export')} CSV',
          style: TextStyle(color: colors.text)),
      subtitle: Text('Export transactions as CSV',
          style: TextStyle(color: colors.placeholderColor, fontSize: 12)),
      onTap: () async {
        try {
          final exportService = ExportService();
          final content = await exportService.exportToCsv();
          final path =
              await exportService.saveToFile(content: content, format: 'csv');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                  content: Text(Translator.t('msg_export_success')
                      .replaceAll('{file_path}', path))),
            );
          }
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(Translator.t('msg_export_error'))),
            );
          }
        }
      },
    );
  }

  Widget _buildDeleteAccountTile(PeadraColors colors) {
    return ListTile(
      title: Text(Translator.t('param_delete_account'),
          style: TextStyle(color: colors.error)),
      subtitle: Text(Translator.t('param_delete_account_desc'),
          style: TextStyle(color: colors.placeholderColor, fontSize: 12)),
      trailing: ElevatedButton.icon(
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
      ),
    );
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
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                      content:
                          Text(Translator.t('param_delete_password_required'))),
                );
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
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                        content: Text(
                            Translator.t('param_delete_password_incorrect'))),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(e.toString())),
                  );
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
