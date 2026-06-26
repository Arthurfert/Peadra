import 'package:flutter/material.dart';
import '../i18n/translator.dart';
import '../database/database_manager.dart';

class LanguageProvider extends ChangeNotifier {
  static const String defaultLanguage = 'en';

  String _language = defaultLanguage;

  String get language => _language;

  LanguageProvider() {
    _language = Translator.language;
  }

  void setLanguage(String lang) {
    _language = lang;
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
