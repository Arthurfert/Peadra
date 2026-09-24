import 'package:flutter/material.dart';
import '../database/database_manager.dart';
import '../services/log_service.dart';
import '../theme/peadra_colors.dart';

class ThemeProvider extends ChangeNotifier {
  String _themeName = PeadraTheme.systemThemeName;

  ThemeProvider() {
    // Rebuild listeners when the OS brightness changes while the
    // 'system' theme is active.
    try {
      WidgetsBinding.instance.platformDispatcher.onPlatformBrightnessChanged =
          () {
        if (_themeName == PeadraTheme.systemThemeName) {
          notifyListeners();
        }
      };
    } catch (_) {
      // No binding (e.g. unit tests): themes still resolve with a fallback.
    }
  }

  String get themeName => _themeName;

  bool get isDark => _themeName == PeadraTheme.systemThemeName
      ? PeadraTheme.isSystemDark
      : !_lightThemes.contains(_themeName);

  static const _lightThemes = {'light', 'summer', 'spring', 'high_contrast_light'};

  ThemeMode get themeMode => _themeName == PeadraTheme.systemThemeName
      ? ThemeMode.system
      : (isDark ? ThemeMode.dark : ThemeMode.light);

  void setTheme(String name) {
    LogService().log('Theme changed to $name');
    _themeName = name;
    notifyListeners();
  }

  Future<void> loadFromSettings(DatabaseManager db) async {
    final saved = await db.getSetting('theme_mode',
        defaultValue: PeadraTheme.systemThemeName);
    if (saved != null) {
      setTheme(saved);
    }
  }
}
