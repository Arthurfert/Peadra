import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:cryptography/cryptography.dart';

import 'log_service.dart';

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
      final result = await _auth.authenticate(
        localizedReason: reason ?? 'Authenticate to continue',
      );
      LogService().log('Biometric authenticate result: $result');
      return result;
    } on PlatformException catch (e) {
      LogService().log('Biometric PlatformException: ${e.code} ${e.message}');
      return false;
    } catch (e) {
      LogService().log('Biometric unexpected error: $e');
      return false;
    }
  }

  Future<void> saveCredentials(String userId, String username, {SecretKey? encryptionKey}) async {
    final keyB64 = encryptionKey == null
        ? null
        : base64Encode((await encryptionKey.extract()).bytes);
    await Future.wait([
      _storage.write(key: _keyUserId, value: userId),
      _storage.write(key: _keyUsername, value: username),
      if (keyB64 != null)
        _storage.write(key: _keyEncryption, value: keyB64),
    ]);
  }

  Future<Map<String, dynamic>?> loadCredentials() async {
    final values = await Future.wait([
      _storage.read(key: _keyUserId),
      _storage.read(key: _keyUsername),
      _storage.read(key: _keyEncryption),
    ]);
    final userId = values[0];
    final username = values[1];
    if (userId != null && username != null) {
      return {
        'userId': userId,
        'username': username,
        'encryptionKey': values[2],
      };
    }
    return null;
  }

  Future<void> clearCredentials() async {
    await _storage.delete(key: _keyUserId);
    await _storage.delete(key: _keyUsername);
    await _storage.delete(key: _keyEncryption);
  }

}
