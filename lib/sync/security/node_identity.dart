import 'dart:io';

import 'package:uuid/uuid.dart';

import '../storage/storage_backend.dart';

/// Device-local sync identity: a stable node id plus a device name.
///
/// The node id is generated once and persisted in secure storage so the
/// device is identified consistently across mDNS advertisement, pairing
/// and the sync handshake.
class NodeIdentity {
  NodeIdentity({StorageBackend? storage, String? deviceName})
      : _storage = storage ?? SecureStorageBackend(),
        _deviceName = deviceName;

  static final NodeIdentity _instance = NodeIdentity._();

  static NodeIdentity get instance => _instance;

  NodeIdentity._()
      : _storage = SecureStorageBackend(),
        _deviceName = null;

  static const String _keyNodeId = 'sync_local_node_id';
  static const String _keyDeviceName = 'sync_device_name';

  final StorageBackend _storage;
  final String? _deviceName;
  final Uuid _uuid = const Uuid();

  String? _nodeId;
  String? _deviceNameCache;

  /// The stable id for this device, generating and persisting one on first use.
  Future<String> get nodeId async {
    if (_nodeId != null) return _nodeId!;
    final stored = await _storage.read(_keyNodeId);
    if (stored != null && stored.isNotEmpty) {
      return _nodeId = stored;
    }
    final id = _uuid.v4();
    await _storage.write(_keyNodeId, id);
    return _nodeId = id;
  }

  /// The device name advertised to peers (e.g. `Peadra linux`).
  Future<String> get deviceName async {
    if (_deviceNameCache != null) return _deviceNameCache!;
    final override = _deviceName;
    if (override != null) {
      await _storage.write(_keyDeviceName, override);
      return _deviceNameCache = override;
    }
    final stored = await _storage.read(_keyDeviceName);
    if (stored != null && stored.isNotEmpty) {
      return _deviceNameCache = stored;
    }
    final name = _defaultDeviceName();
    await _storage.write(_keyDeviceName, name);
    return _deviceNameCache = name;
  }

  /// Forgets the stored identity so a fresh one is generated on next use.
  /// Intended for tests; not exposed through the UI.
  Future<void> reset() async {
    _nodeId = null;
    _deviceNameCache = null;
    await _storage.delete(_keyNodeId);
    await _storage.delete(_keyDeviceName);
  }

  String _defaultDeviceName() {
    try {
      final os = Platform.operatingSystem;
      return os.isEmpty ? 'Peadra Device' : 'Peadra $os';
    } catch (_) {
      return 'Peadra Device';
    }
  }
}
