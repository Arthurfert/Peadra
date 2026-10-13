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

  /// In-memory copy of the blob. Peer lookups happen on every mDNS event
  /// and handshake, so caching avoids a secure-storage read + full JSON
  /// parse per call. Write-through: every mutation rewrites the blob and
  /// refreshes the cache, so the cache never diverges.
  List<TrustedPeer>? _cache;

  /// True once if corrupt peer data was reset since the last call.
  bool consumeRecoveryFlag() {
    final recovered = _recoveredFromCorruptData;
    _recoveredFromCorruptData = false;
    return recovered;
  }

  /// Drops the in-memory copy; the next read reloads from storage.
  void invalidateCache() {
    _cache = null;
  }

  Future<List<TrustedPeer>> getAll() async {
    final cached = _cache;
    if (cached != null) return [...cached];
    final raw = await _storage.read(_key);
    if (_storage.consumeRecoveryFlag()) {
      // The backend deleted an undecryptable entry (device keystore key
      // lost): the pairings it held are gone and must be recreated.
      _recoveredFromCorruptData = true;
      _cache = const [];
      return [];
    }
    if (raw == null || raw.isEmpty) {
      _cache = const [];
      return [];
    }
    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      final peers = decoded
          .map((e) => TrustedPeer.fromJson(e as Map<String, dynamic>))
          .toList();
      _cache = peers;
      return [...peers];
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
      _cache = const [];
      return [];
    }
  }

  Future<TrustedPeer?> getById(String peerId) async {
    // Fast path avoids even the list copy when the cache is warm.
    final cached = _cache;
    if (cached != null) {
      for (final peer in cached) {
        if (peer.peerId == peerId) return peer;
      }
      return null;
    }
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

  Future<void> _writeAll(List<TrustedPeer> peers) async {
    await _storage.write(
      _key,
      jsonEncode(peers.map((p) => p.toJson()).toList()),
    );
    _cache = [...peers];
  }
}
