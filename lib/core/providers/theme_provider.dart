import 'package:flutter/material.dart';
import '../database/database_manager.dart';
import '../services/log_service.dart';

class ThemeProvider extends ChangeNotifier {
  String _themeName = 'dark';

  String get themeName => _themeName;

  bool get isDark => !_lightThemes.contains(_themeName);

  static const _lightThemes = {'light', 'summer', 'spring'};

  ThemeMode get themeMode => isDark ? ThemeMode.dark : ThemeMode.light;

  void setTheme(String name) {
    LogService().log('Theme changed to $name');
    _themeName = name;
    notifyListeners();
  }

  Future<void> loadFromSettings(DatabaseManager db) async {
    final saved = await db.getSetting('theme_mode', defaultValue: 'dark');
    if (saved != null) {
      setTheme(saved);
    }
  }
}
