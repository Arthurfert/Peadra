import 'dart:convert';

import '../../core/services/log_service.dart';
import '../models/trusted_peer.dart';
import 'storage_backend.dart';

/// Persists the [TrustedPeer] list in secure storage as a single JSON blob.
///
/// A blob that no longer parses (truncated write, schema drift) is treated
/// as lost: it is deleted, an empty list is returned, and
/// [consumeRecoveryFlag] reports the reset once so the UI can tell the user
/// to pair their devices again. Storage-layer throws (e.g. a locked
/// keystore) still propagate so callers can retry them.
class SecurePeerStorage {
  SecurePeerStorage({StorageBackend? storage})
      : _storage = storage ?? SecureStorageBackend();

  static const String _key = 'sync_trusted_peers';

  final StorageBackend _storage;

  bool _recoveredFromCorruptData = false;

  /// True once if corrupt peer data was reset since the last call.
  bool consumeRecoveryFlag() {
    final recovered = _recoveredFromCorruptData;
    _recoveredFromCorruptData = false;
    return recovered;
  }

  Future<List<TrustedPeer>> getAll() async {
    final raw = await _storage.read(_key);
    if (_storage.consumeRecoveryFlag()) {
      // The backend deleted an undecryptable entry (device keystore key
      // lost): the pairings it held are gone and must be recreated.
      _recoveredFromCorruptData = true;
    }
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded
          .map((e) => TrustedPeer.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      LogService().error(
        'Saved paired devices are corrupt and unreadable; resetting the '
        'device list. Re-pairing will be required. ($e)',
      );
      _recoveredFromCorruptData = true;
      try {
        await _storage.delete(_key);
      } catch (deleteError) {
        LogService()
            .warn('Could not delete corrupt peer data: $deleteError');
      }
      return [];
    }
  }

  Future<TrustedPeer?> getById(String peerId) async {
    for (final peer in await getAll()) {
      if (peer.peerId == peerId) return peer;
    }
    return null;
  }

  Future<void> upsert(TrustedPeer peer) async {
    final peers = await getAll();
    peers.removeWhere((p) => p.peerId == peer.peerId);
    peers.add(peer);
    await _writeAll(peers);
  }

  Future<void> delete(String peerId) async {
    final peers = await getAll();
    peers.removeWhere((p) => p.peerId == peerId);
    await _writeAll(peers);
  }

  Future<void> clear() async {
    await _storage.delete(_key);
  }

  Future<void> _writeAll(List<TrustedPeer> peers) async {
    await _storage.write(
      _key,
      jsonEncode(peers.map((p) => p.toJson()).toList()),
    );
  }
}
