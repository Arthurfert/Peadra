import 'package:flutter/material.dart';
import '../database/database_manager.dart';
import '../services/log_service.dart';

class AuthProvider extends ChangeNotifier {
  String? _userId;
  String _username = '';

  String? get userId => _userId;
  String get username => _username;

  void login(String userId, String username, DatabaseManager db) {
    _userId = userId;
    _username = username;
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
    db.clearEncryptionKey();
    notifyListeners();
  }
}
