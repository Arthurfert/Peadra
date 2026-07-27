import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:cryptography/cryptography.dart';

class BiometricService {
  final LocalAuthentication _auth = LocalAuthentication();
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  static const String _keyUserId = 'biometric_user_id';
  static const String _keyUsername = 'biometric_username';
  static const String _keyEncryption = 'biometric_encryption_key';

  Future<bool> isAvailable() async {
    if (Platform.isLinux) return false;
    try {
      return await _auth.isDeviceSupported();
    } on PlatformException {
      return false;
    }
  }

  Future<bool> authenticate({String? reason}) async {
    try {
      return await _auth.authenticate(
        localizedReason: reason ?? 'Authenticate to continue',
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: true,
        ),
      );
    } on PlatformException {
      return false;
    }
  }

  Future<void> saveCredentials(int userId, String username, {SecretKey? encryptionKey}) async {
    await _storage.write(key: _keyUserId, value: userId.toString());
    await _storage.write(key: _keyUsername, value: username);
    if (encryptionKey != null) {
      final keyBytes = (await encryptionKey.extract()).bytes;
      await _storage.write(key: _keyEncryption, value: base64Encode(keyBytes));
    }
  }

  Future<Map<String, dynamic>?> loadCredentials() async {
    final userId = await _storage.read(key: _keyUserId);
    final username = await _storage.read(key: _keyUsername);
    if (userId != null && username != null) {
      return {
        'userId': userId,
        'username': username,
        'encryptionKey': await _storage.read(key: _keyEncryption),
      };
    }
    return null;
  }

  Future<void> clearCredentials() async {
    await _storage.delete(key: _keyUserId);
    await _storage.delete(key: _keyUsername);
    await _storage.delete(key: _keyEncryption);
  }

  Future<bool> hasStoredCredentials() async {
    final userId = await _storage.read(key: _keyUserId);
    return userId != null;
  }
}
