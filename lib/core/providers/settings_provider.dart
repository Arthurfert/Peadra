import 'package:flutter/material.dart';
import '../database/database_manager.dart';
import '../services/log_service.dart';
import '../utils/constants.dart';

class SettingsProvider extends ChangeNotifier {
  int _displayLimit = defaultDisplayLimit;
  int _maxPieCategories = defaultMaxPieCategories;
  String _monthMode = defaultMonthMode;
  String _currency = defaultCurrency;
  int _maxBackups = defaultMaxBackups;
  bool _biometricEnabled = defaultBiometricEnabled;
  String _categoriesView = defaultCategoriesView;
  String _dashboardPieView = defaultDashboardPieView;
  bool _lineChartDots = defaultLineChartDots;
  String _assetsGranularity = defaultAssetsGranularity;

  int get displayLimit => _displayLimit;
  int get maxPieCategories => _maxPieCategories;
  String get monthMode => _monthMode;
  String get currency => _currency;
  int get maxBackups => _maxBackups;
  bool get biometricEnabled => _biometricEnabled;
  String get categoriesView => _categoriesView;
  String get dashboardPieView => _dashboardPieView;
  bool get lineChartDots => _lineChartDots;
  String get assetsGranularity => _assetsGranularity;

  Future<void> loadFromSettings(DatabaseManager db) async {
    _displayLimit = int.tryParse(
          await db.getSetting('transactions_display_limit', defaultValue: defaultDisplayLimit.toString()) ?? defaultDisplayLimit.toString(),
        ) ??
        defaultDisplayLimit;
    _maxPieCategories = int.tryParse(
          await db.getSetting('max_categories_pie', defaultValue: defaultMaxPieCategories.toString()) ?? defaultMaxPieCategories.toString(),
        ) ??
        defaultMaxPieCategories;
    _monthMode = await db.getSetting('month_mode', defaultValue: defaultMonthMode) ?? defaultMonthMode;
    _currency = await db.getSetting('currency', defaultValue: defaultCurrency) ?? defaultCurrency;
    _maxBackups = int.tryParse(
          await db.getSetting('max_backups', defaultValue: defaultMaxBackups.toString()) ?? defaultMaxBackups.toString(),
        ) ??
        defaultMaxBackups;
    _biometricEnabled = (await db.getSetting('biometric_enabled', defaultValue: defaultBiometricEnabled.toString())) == 'true';
    _categoriesView = await db.getSetting('categories_view', defaultValue: defaultCategoriesView) ?? defaultCategoriesView;
    _dashboardPieView = await db.getSetting('dashboard_pie_view', defaultValue: defaultDashboardPieView) ?? defaultDashboardPieView;
    _lineChartDots = (await db.getSetting('line_chart_dots', defaultValue: defaultLineChartDots.toString())) == 'true';
    _assetsGranularity = await db.getSetting('assets_granularity', defaultValue: defaultAssetsGranularity) ?? defaultAssetsGranularity;
    notifyListeners();
  }

  Future<void> setDisplayLimit(int limit, DatabaseManager db) async {
    _displayLimit = limit;
    await db.setSetting('transactions_display_limit', limit.toString());
    LogService().log('Display limit set to $limit');
    notifyListeners();
  }

  Future<void> setMaxPieCategories(int max, DatabaseManager db) async {
    _maxPieCategories = max;
    await db.setSetting('max_categories_pie', max.toString());
    LogService().log('Max pie categories set to $max');
    notifyListeners();
  }

  Future<void> setMonthMode(String mode, DatabaseManager db) async {
    _monthMode = mode;
    await db.setSetting('month_mode', mode);
    LogService().log('Month mode set to $mode');
    notifyListeners();
  }

  Future<void> setCurrency(String currency, DatabaseManager db) async {
    _currency = currency;
    await db.setSetting('currency', currency);
    LogService().log('Currency set to $currency');
    notifyListeners();
  }

  Future<void> setMaxBackups(int max, DatabaseManager db) async {
    _maxBackups = max;
    await db.setSetting('max_backups', max.toString());
    LogService().log('Backups limit set to $max');
    notifyListeners();
  }

  Future<void> setBiometricEnabled(bool enabled, DatabaseManager db) async {
    _biometricEnabled = enabled;
    await db.setSetting('biometric_enabled', enabled.toString());
    LogService().log('Biometric login set to $enabled');
    notifyListeners();
  }

  Future<void> setCategoriesView(String view, DatabaseManager db) async {
    _categoriesView = view;
    await db.setSetting('categories_view', view);
    LogService().log('Categories view set to $view');
    notifyListeners();
  }

  Future<void> setDashboardPieView(String view, DatabaseManager db) async {
    _dashboardPieView = view;
    await db.setSetting('dashboard_pie_view', view);
    LogService().log('Dashboard pie view set to $view');
    notifyListeners();
  }

  Future<void> setLineChartDots(bool show, DatabaseManager db) async {
    _lineChartDots = show;
    await db.setSetting('line_chart_dots', show.toString());
    LogService().log('Line chart dots set to $show');
    notifyListeners();
  }

  Future<void> setAssetsGranularity(String granularity, DatabaseManager db) async {
    _assetsGranularity = granularity;
    await db.setSetting('assets_granularity', granularity);
    LogService().log('Assets chart granularity set to $granularity');
    notifyListeners();
  }
}
