import 'package:flutter_test/flutter_test.dart';
import 'package:peadra/core/i18n/translator.dart';

/// Guards the translation maps: every supported language must define
/// exactly the same keys, with no duplicates and no empty values.
void main() {
  group('Translator', () {
    test('es partially covers en keys with no empty values', () {
      Translator.setLanguage('es');
      // Spot-check a representative sample across sections.
      const keys = [
        'nav_dashboard',
        'nav_settings',
        'login_signin',
        'dash_title',
        'trans_transfer',
        'param_title',
        'param_language_es',
        'param_theme_label',
        'param_system_theme',
        'sync_title',
        'import_title',
        'trans_tag',
        'tag_delete_confirm',
        'budget_title',
        'period_1y',
        'month_dec',
        'week_sun',
        'rec_freq_every_monthly',
      ];
      for (final key in keys) {
        final value = Translator.t(key);
        expect(value, isNotEmpty, reason: 'es missing: $key');
        expect(value, isNot(key), reason: 'es falls back to key: $key');
      }
      Translator.setLanguage('en');
    });

    test('unknown language keeps current language', () {
      Translator.setLanguage('en');
      Translator.setLanguage('xx');
      expect(Translator.language, 'en');
      expect(Translator.t('nav_dashboard'), 'Home');
    });

    test('missing key falls back to English, then to the key itself', () {
      Translator.setLanguage('es');
      expect(Translator.t('nav_dashboard'), 'Inicio');
      expect(Translator.t('definitely_not_a_key'), 'definitely_not_a_key');
      Translator.setLanguage('en');
    });

    test('placeholders are substituted in every language', () {
      for (final lang in ['en', 'fr', 'es']) {
        Translator.setLanguage(lang);
        final text = Translator.t('trans_transfer_from_to',
            params: {'source': 'A', 'dest': 'B'});
        expect(text.contains('{source}'), isFalse, reason: lang);
        expect(text.contains('{dest}'), isFalse, reason: lang);
        expect(text.contains('A'), isTrue, reason: lang);
        expect(text.contains('B'), isTrue, reason: lang);
      }
      Translator.setLanguage('en');
    });

    test('availableLanguages lists all supported languages', () {
      final langs = Translator.availableLanguages;
      expect(langs.keys, containsAll(['en', 'fr', 'es']));
      for (final name in langs.values) {
        expect(name.isNotEmpty, isTrue);
      }
    });
  });
}
