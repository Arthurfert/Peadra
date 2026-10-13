import 'package:peadra/sync/storage/storage_backend.dart';

/// In-memory [StorageBackend] for sync unit tests.
class InMemoryStorageBackend implements StorageBackend {
  final Map<String, String> _data = {};
  bool _recoveryFlag = false;

  /// Test-only hook to simulate a backend reset (e.g. an undecryptable entry
  /// that had to be deleted). The next [consumeRecoveryFlag] call reports it.
  void setRecoveryFlag([bool value = true]) => _recoveryFlag = value;

  @override
  Future<String?> read(String key) async => _data[key];

  @override
  Future<void> write(String key, String value) async {
    _data[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    _data.remove(key);
  }

  @override
  bool consumeRecoveryFlag() {
    final value = _recoveryFlag;
    _recoveryFlag = false;
    return value;
  }
}
