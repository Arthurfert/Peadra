import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:uuid/uuid.dart';

import '../database/database_manager.dart';
import 'encryption_service.dart';
import 'log_service.dart';

class AuthService {
  final DatabaseManager _db;
  final Uuid _uuid = const Uuid();

  AuthService(this._db);

  /// Legacy unsalted SHA-256 hash. Kept so existing users can still log in;
  /// [authenticateUser] upgrades them to [hashPasswordSalted] on success.
  static String hashPassword(String password) {
    return sha256.convert(utf8.encode(password)).toString();
  }

  /// Salted, slow hash for new/upgraded passwords.
  static Future<String> hashPasswordSalted(
      String password, String saltBase64) async {
    final key = await EncryptionService.deriveKey(
      password,
      base64Decode(saltBase64),
    );
    return base64Encode(await key.extractBytes());
  }

  /// Verifies a salted hash, or the legacy unsalted SHA-256 when [salt] is null.
  /// Comparison is constant-time so response latency does not leak the hash.
  static Future<bool> verifyPassword(
    String password,
    String hash, {
    String? salt,
  }) async {
    final computed = salt == null
        ? hashPassword(password)
        : await hashPasswordSalted(password, salt);
    return _constantTimeEquals(computed, hash);
  }

  static bool _constantTimeEquals(String a, String b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }

  Future<bool> userExists(String username) async {
    final db = await _db.database;
    final results = await db.query(
      'SELECT id FROM users WHERE username = ? AND is_deleted = 0',
      [username],
    );
    return results.isNotEmpty;
  }

  Future<String> registerUser(String username, String password) async {
    if (username.isEmpty || password.isEmpty) {
      throw ArgumentError('Username and password are required.');
    }
    if (await userExists(username)) {
      throw ArgumentError("Username '$username' already exists.");
    }
    final salt = base64Encode(EncryptionService.generateSalt());
    final passwordHash = await hashPasswordSalted(password, salt);
    final id = _uuid.v4();
    final db = await _db.database;
    await db.execute(
      'INSERT INTO users (id, username, password_hash, password_salt) '
      'VALUES (?1, ?2, ?3, ?4)',
      [id, username, passwordHash, salt],
    );
    LogService().log('User registered: $username (id $id)');
    return id;
  }

  Future<String?> authenticateUser(String username, String password) async {
    final db = await _db.database;
    final results = await db.query(
      'SELECT id, password_hash, password_salt FROM users '
      'WHERE username = ? AND is_deleted = 0',
      [username],
    );
    if (results.isEmpty) return null;
    final row = results.first;
    final storedHash = row['password_hash'] as String;
    final salt = row['password_salt'] as String?;
    if (await verifyPassword(password, storedHash, salt: salt)) {
      // Transparently upgrade a legacy unsalted SHA-256 hash on first login.
      if (salt == null) {
        final newSalt = base64Encode(EncryptionService.generateSalt());
        final upgraded = await hashPasswordSalted(password, newSalt);
        await db.execute(
          'UPDATE users SET password_hash = ?, password_salt = ? WHERE id = ?',
          [upgraded, newSalt, row['id']],
        );
        LogService().log('Password hash upgraded for: $username');
      }
      LogService().log('User authenticated: $username');
      return row['id'] as String;
    }
    LogService().warn('Failed login attempt for: $username');
    return null;
  }

  /// Returns the canonical user id for [userId].
  ///
  /// After sync reconciliation the local user row may have been remapped to a
  /// peer's canonical id, making [userId] stale.  When that happens the method
  /// falls back to looking up the id by [username].
  Future<String> resolveUserId(String userId, String username) async {
    final db = await _db.database;
    final rows = await db.query(
      'SELECT id FROM users WHERE id = ? AND is_deleted = 0',
      [userId],
    );
    if (rows.isNotEmpty) return userId;
    final canonical = await db.query(
      'SELECT id FROM users WHERE username = ? AND is_deleted = 0',
      [username],
    );
    if (canonical.isNotEmpty) {
      final resolved = canonical.first['id'] as String;
      LogService().log('User id resolved: $userId -> $resolved');
      return resolved;
    }
    return userId;
  }

  Future<List<String>> getAllUsernames() async {
    final db = await _db.database;
    final results = await db.query(
      'SELECT username FROM users WHERE is_deleted = 0 ORDER BY username',
    );
    return results.map((r) => r['username'] as String).toList();
  }

  Future<bool> updatePassword(String userId, String oldPassword, String newPassword) async {
    if (newPassword.isEmpty) {
      throw ArgumentError('New password cannot be empty.');
    }
    final db = await _db.database;
    final rows = await db.query(
      'SELECT password_hash, password_salt FROM users WHERE id = ? AND is_deleted = 0',
      [userId],
    );
    if (rows.isEmpty) return false;
    final storedHash = rows.first['password_hash'] as String;
    final oldSalt = rows.first['password_salt'] as String?;
    if (!await verifyPassword(oldPassword, storedHash, salt: oldSalt)) {
      throw ArgumentError('Old password is incorrect.');
    }

    final saltStr = await _db.getSetting('encryption_salt');
    if (saltStr != null && _db.isEncrypted) {
      final salt = base64Decode(saltStr);
      final newKey = await EncryptionService.deriveKey(newPassword, salt);
      await _db.reEncryptData(newKey);
    }

    final newSalt = base64Encode(EncryptionService.generateSalt());
    final newHash = await hashPasswordSalted(newPassword, newSalt);
    await db.execute(
      'UPDATE users SET password_hash = ?, password_salt = ? WHERE id = ?',
      [newHash, newSalt, userId],
    );
    LogService().log('Password changed for user $userId');
    return true;
  }

  Future<bool> updateUsername(String userId, String newUsername) async {
    if (newUsername.trim().isEmpty) {
      throw ArgumentError('Username cannot be empty.');
    }
    final db = await _db.database;
    final existing = await db.query(
      'SELECT id FROM users WHERE username = ? AND id != ? AND is_deleted = 0',
      [newUsername.trim(), userId],
    );
    if (existing.isNotEmpty) {
      throw ArgumentError("Username '${newUsername.trim()}' already exists.");
    }
    await db.execute(
      'UPDATE users SET username = ? WHERE id = ?',
      [newUsername.trim(), userId],
    );
    return true;
  }
}
