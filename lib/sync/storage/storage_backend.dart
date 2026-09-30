import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../core/services/log_service.dart';

/// Abstraction over the secure key-value store used by the sync layer.
///
/// Production uses [SecureStorageBackend] backed by flutter_secure_storage;
/// tests inject an in-memory implementation so the sync components are
/// unit-testable without a platform implementation.
abstract class StorageBackend {
  Future<String?> read(String key);

  Future<void> write(String key, String value);

  Future<void> delete(String key);

  Future<Map<String, String>> readAll();

  /// True once if the backend had to reset unreadable state since the last
  /// call, so higher layers can tell the user to recreate it (e.g. re-pair).
  bool consumeRecoveryFlag() => false;
}

class SecureStorageBackend implements StorageBackend {
  SecureStorageBackend({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  bool _recoveredByReset = false;

  @override
  bool consumeRecoveryFlag() {
    final recovered = _recoveredByReset;
    _recoveredByReset = false;
    return recovered;
  }

  @override
  Future<String?> read(String key) async {
    try {
      return await _storage.read(key: key);
    } on PlatformException catch (e) {
      // The Android Keystore key backing an entry can be lost (OS update,
      // biometric/credential change, backup restore, OEM issue). Reads then
      // fail with a decrypt error and can NEVER succeed again: the entry is
      // cryptographically unrecoverable. Delete it so the app falls back to
      // its empty/regeneration path instead of bricking every caller.
      // Anything else (transient/lock errors) is rethrown untouched.
      if (!_isUnrecoverableDecryptFailure(e)) rethrow;
      LogService().error(
        'Secure storage entry "$key" is undecryptable '
        '(device keystore key lost); deleting it so the app can recover. '
        'Any data it held must be recreated (e.g. re-pair devices). ($e)',
      );
      try {
        await _storage.delete(key: key);
      } catch (deleteError) {
        LogService().warn(
          'Could not delete undecryptable entry "$key": $deleteError',
        );
      }
      _recoveredByReset = true;
      return null;
    }
  }

  /// True only for integrity/decrypt failures that retrying cannot fix.
  /// Deliberately narrow: transient errors (locked keystore, busy, auth
  /// timeouts) must keep propagating so callers can retry them.
  bool _isUnrecoverableDecryptFailure(PlatformException e) {
    final details =
        '${e.code} ${e.message ?? ''} ${e.details ?? ''}'.toLowerCase();
    return details.contains('badpaddingexception') ||
        details.contains('bad_decrypt') ||
        details.contains('aeadbadtag') ||
        details.contains('tag mismatch') ||
        details.contains('mac check failed') ||
        details.contains('integrity check failed') ||
        details.contains('failed to decrypt');
  }

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);

  @override
  Future<Map<String, String>> readAll() => _storage.readAll();
}
