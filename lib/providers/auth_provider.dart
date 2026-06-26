import 'package:flutter/material.dart';
import '../database/database_manager.dart';
import '../utils/constants.dart';

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
    notifyListeners();
  }

  void logout(DatabaseManager db) {
    _userId = null;
    _username = '';
    _isAuthenticated = false;
    notifyListeners();
  }
}
