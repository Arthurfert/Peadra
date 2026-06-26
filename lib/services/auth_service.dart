import 'package:crypto/crypto.dart';
import 'dart:convert';
import '../database/database_manager.dart';

class AuthService {
  final DatabaseManager _db;

  AuthService(this._db);

  static String hashPassword(String password) {
    return sha256.convert(utf8.encode(password)).toString();
  }

  static bool verifyPassword(String password, String hash) {
    return hashPassword(password) == hash;
  }

  Future<bool> userExists(String username) async {
    final db = await _db.database;
    final results = await db.rawQuery(
      'SELECT id FROM users WHERE username = ?',
      [username],
    );
    return results.isNotEmpty;
  }

  Future<int> registerUser(String username, String password) async {
    if (username.isEmpty || password.isEmpty) {
      throw ArgumentError('Username and password are required.');
    }
    if (await userExists(username)) {
      throw ArgumentError("Username '$username' already exists.");
    }
    final passwordHash = hashPassword(password);
    final db = await _db.database;
    final id = await db.rawInsert(
      'INSERT INTO users (username, password_hash) VALUES (?, ?)',
      [username, passwordHash],
    );
    return id;
  }

  Future<int?> authenticateUser(String username, String password) async {
    final db = await _db.database;
    final results = await db.rawQuery(
      'SELECT id, password_hash FROM users WHERE username = ?',
      [username],
    );
    if (results.isEmpty) return null;
    final row = results.first;
    if (verifyPassword(password, row['password_hash'] as String)) {
      return row['id'] as int;
    }
    return null;
  }

  Future<List<String>> getAllUsernames() async {
    final db = await _db.database;
    final results = await db.rawQuery(
      'SELECT username FROM users ORDER BY username',
    );
    return results.map((r) => r['username'] as String).toList();
  }

  Future<String> getCurrentUsername(int userId) async {
    final db = await _db.database;
    final results = await db.rawQuery(
      'SELECT username FROM users WHERE id = ?',
      [userId],
    );
    if (results.isEmpty) return '';
    return results.first['username'] as String;
  }

  Future<bool> updateUsername(int userId, String newUsername) async {
    if (newUsername.trim().isEmpty) {
      throw ArgumentError('Username cannot be empty.');
    }
    final db = await _db.database;
    final existing = await db.rawQuery(
      'SELECT id FROM users WHERE username = ? AND id != ?',
      [newUsername.trim(), userId],
    );
    if (existing.isNotEmpty) {
      throw ArgumentError("Username '${newUsername.trim()}' already exists.");
    }
    final count = await db.rawUpdate(
      'UPDATE users SET username = ? WHERE id = ?',
      [newUsername.trim(), userId],
    );
    return count > 0;
  }
}
