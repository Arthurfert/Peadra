import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../i18n/translator.dart';
import '../providers/theme_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/language_provider.dart';
import '../database/database_manager.dart';
import '../components/theme/paedra_colors.dart';
import '../services/currency_service.dart';
import '../utils/constants.dart';

class ParametersView extends StatefulWidget {
  const ParametersView({super.key});

  @override
  State<ParametersView> createState() => _ParametersViewState();
}

class _ParametersViewState extends State<ParametersView> {
  final _db = DatabaseManager.instance;

  @override
  Widget build(BuildContext context) {
    final themeName = context.watch<ThemeProvider>().themeName;
    final colors = PeadraTheme.getColors(themeName);
    final settings = context.watch<SettingsProvider>();
    final lang = context.watch<LanguageProvider>();

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
        ],
      ),
    );
  }

  Widget _buildSection(
      String title, PeadraColors colors, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title,
            style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: colors.accent)),
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
          DropdownMenuItem(value: 'light', child: Text(Translator.t('param_light_theme'))),
          DropdownMenuItem(value: 'dark', child: Text(Translator.t('param_dark_theme'))),
          DropdownMenuItem(value: 'autumn', child: Text(Translator.t('param_autumn_theme'))),
          DropdownMenuItem(value: 'summer', child: Text(Translator.t('param_summer_theme'))),
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
}
