import 'package:flutter/material.dart';
import '../database/database_manager.dart';
import '../services/log_service.dart';

class AuthProvider extends ChangeNotifier {
  int? _userId;
  String _username = '';
  bool _isAuthenticated = false;

  int? get userId => _userId;
  String get username => _username;
  bool get isAuthenticated => _isAuthenticated;

  void login(int userId, String username, DatabaseManager db) {
    _userId = userId;
    _username = username;
    _isAuthenticated = true;
    db.setUserId(userId);
    LogService().log('User logged in: $username');
    notifyListeners();
  }

  void setUsername(String username) {
    _username = username;
    LogService().log('Username changed to: $username');
    notifyListeners();
  }

  void logout(DatabaseManager db) {
    LogService().log('User logged out: $_username');
    _userId = null;
    _username = '';
    _isAuthenticated = false;
    db.clearEncryptionKey();
    notifyListeners();
  }
}
