import 'package:flutter/material.dart';
import '../database/database_manager.dart';
import '../services/log_service.dart';
import '../utils/constants.dart';
import '../utils/nav_views.dart';

class SettingsProvider extends ChangeNotifier {
  int _displayLimit = defaultDisplayLimit;
  int _maxPieCategories = defaultMaxPieCategories;
  String _monthMode = defaultMonthMode;
  String _currency = defaultCurrency;
  bool _biometricEnabled = defaultBiometricEnabled;
  String _categoriesView = defaultCategoriesView;
  String _dashboardPieView = defaultDashboardPieView;
  bool _lineChartDots = defaultLineChartDots;
  String _assetsGranularity = defaultAssetsGranularity;
  bool _showNavLabels = defaultShowNavLabels;
  bool _showStatSubtitles = defaultShowStatSubtitles;
  bool _showWorkHours = defaultShowWorkHours;
  double _hourlyRate = defaultHourlyRate;
  bool _hideUpdateNotifications = defaultHideUpdateNotifications;
  List<String> _navOrder = List.of(defaultNavOrder);

  int get displayLimit => _displayLimit;
  int get maxPieCategories => _maxPieCategories;
  String get monthMode => _monthMode;
  String get currency => _currency;
  bool get biometricEnabled => _biometricEnabled;
  String get categoriesView => _categoriesView;
  String get dashboardPieView => _dashboardPieView;
  bool get lineChartDots => _lineChartDots;
  String get assetsGranularity => _assetsGranularity;
  bool get showNavLabels => _showNavLabels;
  bool get showStatSubtitles => _showStatSubtitles;
  bool get showWorkHours => _showWorkHours;
  double get hourlyRate => _hourlyRate;
  bool get hideUpdateNotifications => _hideUpdateNotifications;

  /// Mobile navigation order: the first [mobileNavBarSlots] destinations
  /// sit in the bottom bar, the rest behind the burger menu.
  List<String> get navOrder => List.unmodifiable(_navOrder);

  Future<void> loadFromSettings(DatabaseManager db) async {
    final values = await Future.wait([
      db.getSetting('transactions_display_limit', defaultValue: defaultDisplayLimit.toString()),
      db.getSetting('max_categories_pie', defaultValue: defaultMaxPieCategories.toString()),
      db.getSetting('month_mode', defaultValue: defaultMonthMode),
      db.getSetting('currency', defaultValue: defaultCurrency),
      db.getSetting('biometric_enabled', defaultValue: defaultBiometricEnabled.toString()),
      db.getSetting('categories_view', defaultValue: defaultCategoriesView),
      db.getSetting('dashboard_pie_view', defaultValue: defaultDashboardPieView),
      db.getSetting('line_chart_dots', defaultValue: defaultLineChartDots.toString()),
      db.getSetting('assets_granularity', defaultValue: defaultAssetsGranularity),
      db.getSetting('show_nav_labels', defaultValue: defaultShowNavLabels.toString()),
      db.getSetting('show_stat_subtitles', defaultValue: defaultShowStatSubtitles.toString()),
      db.getSetting('show_work_hours', defaultValue: defaultShowWorkHours.toString()),
      db.getSetting('hourly_rate', defaultValue: defaultHourlyRate.toString()),
      db.getSetting('hide_update_notifications', defaultValue: defaultHideUpdateNotifications.toString()),
      db.getSetting('nav_order', defaultValue: encodeNavOrder(defaultNavOrder)),
    ]);
    _displayLimit = int.tryParse(values[0] ?? defaultDisplayLimit.toString()) ?? defaultDisplayLimit;
    _maxPieCategories = int.tryParse(values[1] ?? defaultMaxPieCategories.toString()) ?? defaultMaxPieCategories;
    _monthMode = values[2] ?? defaultMonthMode;
    _currency = values[3] ?? defaultCurrency;
    _biometricEnabled = values[4] == 'true';
    _categoriesView = values[5] ?? defaultCategoriesView;
    _dashboardPieView = values[6] ?? defaultDashboardPieView;
    _lineChartDots = values[7] == 'true';
    _assetsGranularity = values[8] ?? defaultAssetsGranularity;
    _showNavLabels = values[9] == 'true';
    _showStatSubtitles = values[10] == 'true';
    _showWorkHours = values[11] == 'true';
    _hourlyRate = double.tryParse(values[12] ?? '') ?? defaultHourlyRate;
    _hideUpdateNotifications = values[13] == 'true';
    _navOrder = parseNavOrder(values[14]);
    notifyListeners();
  }

  Future<void> setDisplayLimit(int limit, DatabaseManager db) async {
    if (_displayLimit == limit) return;
    _displayLimit = limit;
    await db.setSetting('transactions_display_limit', limit.toString());
    LogService().log('Display limit set to $limit');
    notifyListeners();
  }

  Future<void> setMaxPieCategories(int max, DatabaseManager db) async {
    if (_maxPieCategories == max) return;
    _maxPieCategories = max;
    await db.setSetting('max_categories_pie', max.toString());
    LogService().log('Max pie categories set to $max');
    notifyListeners();
  }

  Future<void> setMonthMode(String mode, DatabaseManager db) async {
    if (_monthMode == mode) return;
    _monthMode = mode;
    await db.setSetting('month_mode', mode);
    LogService().log('Month mode set to $mode');
    notifyListeners();
  }

  Future<void> setCurrency(String currency, DatabaseManager db) async {
    if (_currency == currency) return;
    _currency = currency;
    await db.setSetting('currency', currency);
    LogService().log('Currency set to $currency');
    notifyListeners();
  }

  Future<void> setBiometricEnabled(bool enabled, DatabaseManager db) async {
    if (_biometricEnabled == enabled) return;
    _biometricEnabled = enabled;
    await db.setSetting('biometric_enabled', enabled.toString());
    LogService().log('Biometric login set to $enabled');
    notifyListeners();
  }

  Future<void> setCategoriesView(String view, DatabaseManager db) async {
    if (_categoriesView == view) return;
    _categoriesView = view;
    await db.setSetting('categories_view', view);
    LogService().log('Categories view set to $view');
    notifyListeners();
  }

  Future<void> setDashboardPieView(String view, DatabaseManager db) async {
    if (_dashboardPieView == view) return;
    _dashboardPieView = view;
    await db.setSetting('dashboard_pie_view', view);
    LogService().log('Dashboard pie view set to $view');
    notifyListeners();
  }

  Future<void> setLineChartDots(bool show, DatabaseManager db) async {
    if (_lineChartDots == show) return;
    _lineChartDots = show;
    await db.setSetting('line_chart_dots', show.toString());
    LogService().log('Line chart dots set to $show');
    notifyListeners();
  }

  Future<void> setAssetsGranularity(String granularity, DatabaseManager db) async {
    if (_assetsGranularity == granularity) return;
    _assetsGranularity = granularity;
    await db.setSetting('assets_granularity', granularity);
    LogService().log('Assets chart granularity set to $granularity');
    notifyListeners();
  }

  Future<void> setShowNavLabels(bool show, DatabaseManager db) async {
    if (_showNavLabels == show) return;
    _showNavLabels = show;
    await db.setSetting('show_nav_labels', show.toString());
    LogService().log('Show nav labels set to $show');
    notifyListeners();
  }

  Future<void> setShowStatSubtitles(bool show, DatabaseManager db) async {
    if (_showStatSubtitles == show) return;
    _showStatSubtitles = show;
    await db.setSetting('show_stat_subtitles', show.toString());
    LogService().log('Show stat subtitles set to $show');
    notifyListeners();
  }

  Future<void> setShowWorkHours(bool show, DatabaseManager db) async {
    if (_showWorkHours == show) return;
    _showWorkHours = show;
    await db.setSetting('show_work_hours', show.toString());
    LogService().log('Show work hours set to $show');
    notifyListeners();
  }

  Future<void> setHourlyRate(double rate, DatabaseManager db) async {
    if (_hourlyRate == rate) return;
    _hourlyRate = rate;
    await db.setSetting('hourly_rate', rate.toString());
    LogService().log('Hourly rate set to $rate');
    notifyListeners();
  }

  Future<void> setHideUpdateNotifications(bool hide, DatabaseManager db) async {
    if (_hideUpdateNotifications == hide) return;
    _hideUpdateNotifications = hide;
    await db.setSetting('hide_update_notifications', hide.toString());
    LogService().log('Hide update notifications set to $hide');
    notifyListeners();
  }

  /// Stores the mobile navigation order. An order that does not cover every
  /// destination exactly once is ignored (the current order is kept).
  Future<bool> setNavOrder(List<String> order, DatabaseManager db) async {
    if (!isValidNavOrder(order)) {
      LogService().warn('Ignoring incomplete navigation order: $order');
      return false;
    }
    _navOrder = List.of(order);
    await db.setSetting('nav_order', encodeNavOrder(order));
    LogService().log('Navigation order set to ${_navOrder.join(',')}');
    notifyListeners();
    return true;
  }
}
