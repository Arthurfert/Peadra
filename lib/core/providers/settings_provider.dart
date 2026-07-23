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

  int get displayLimit => _displayLimit;
  int get maxPieCategories => _maxPieCategories;
  String get monthMode => _monthMode;
  String get currency => _currency;
  int get maxBackups => _maxBackups;

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
}
