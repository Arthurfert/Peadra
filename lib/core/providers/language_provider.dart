import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../i18n/translator.dart';
import '../database/database_manager.dart';
import '../services/log_service.dart';

class LanguageProvider extends ChangeNotifier {
  static const String defaultLanguage = 'en';

  String _language = defaultLanguage;

  String get language => _language;

  LanguageProvider() {
    _language = Translator.language;
    Intl.defaultLocale = _language;
  }

  void setLanguage(String lang) {
    if (_language == lang) return;
    LogService().log('Language changed to $lang');
    _language = lang;
    // Localizes DateFormat output (intl) app-wide.
    Intl.defaultLocale = lang;
    Translator.setLanguage(lang);
    notifyListeners();
  }

  Future<void> loadFromSettings(DatabaseManager db) async {
    final saved = await db.getSetting('language', defaultValue: defaultLanguage);
    if (saved != null) {
      setLanguage(saved);
    }
  }
}
