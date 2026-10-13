import 'package:flutter/material.dart';
import '../database/database_manager.dart';
import '../services/log_service.dart';
import '../theme/peadra_colors.dart';

class ThemeProvider extends ChangeNotifier with WidgetsBindingObserver {
  String _themeName = PeadraTheme.systemThemeName;

  ThemeProvider() {
    // Rebuild listeners when the OS brightness changes while the
    // 'system' theme is active. Uses an observer (not the global
    // onPlatformBrightnessChanged setter) so other listeners are kept.
    try {
      WidgetsBinding.instance.addObserver(this);
    } catch (_) {
      // No binding (e.g. unit tests): themes still resolve with a fallback.
    }
  }

  @override
  void didChangePlatformBrightness() {
    if (_themeName == PeadraTheme.systemThemeName) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    try {
      WidgetsBinding.instance.removeObserver(this);
    } catch (_) {}
    super.dispose();
  }

  String get themeName => _themeName;

  bool get isDark => _themeName == PeadraTheme.systemThemeName
      ? PeadraTheme.isSystemDark
      : !_lightThemes.contains(_themeName);

  static const _lightThemes = {'light', 'summer', 'spring', 'sakura', 'high_contrast_light'};

  ThemeMode get themeMode => _themeName == PeadraTheme.systemThemeName
      ? ThemeMode.system
      : (isDark ? ThemeMode.dark : ThemeMode.light);

  void setTheme(String name) {
    if (_themeName == name) return;
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
