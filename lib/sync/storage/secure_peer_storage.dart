import 'dart:convert';

import '../models/trusted_peer.dart';
import 'storage_backend.dart';

/// Persists the [TrustedPeer] list in secure storage as a single JSON blob.
class SecurePeerStorage {
  SecurePeerStorage({StorageBackend? storage})
      : _storage = storage ?? SecureStorageBackend();

  static const String _key = 'sync_trusted_peers';

  final StorageBackend _storage;

  Future<List<TrustedPeer>> getAll() async {
    final raw = await _storage.read(_key);
    if (raw == null || raw.isEmpty) return [];
    final decoded = jsonDecode(raw) as List<dynamic>;
    return decoded
        .map((e) => TrustedPeer.fromJson(e as Map<String, dynamic>))
        .toList();
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
