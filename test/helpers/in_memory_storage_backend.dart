import 'package:peadra/sync/storage/storage_backend.dart';

/// In-memory [StorageBackend] for sync unit tests.
class InMemoryStorageBackend implements StorageBackend {
  final Map<String, String> _data = {};

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
  Future<Map<String, String>> readAll() async => Map.of(_data);
}
