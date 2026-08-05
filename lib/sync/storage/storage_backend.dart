import 'package:flutter_secure_storage/flutter_secure_storage.dart';

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
}

class SecureStorageBackend implements StorageBackend {
  SecureStorageBackend({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);

  @override
  Future<Map<String, String>> readAll() => _storage.readAll();
}
