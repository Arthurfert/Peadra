import 'package:crdt/crdt.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:peadra/sync/models/trusted_peer.dart';
import 'package:peadra/sync/storage/secure_peer_storage.dart';

import '../helpers/in_memory_storage_backend.dart';

const String _secret =
    'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=';

TrustedPeer _peer(
  String id, {
  String name = 'peer',
  String? dbEncryptionKey,
  Hlc? lastSyncHlc,
  DateTime? lastSeen,
}) {
  return TrustedPeer(
    peerId: id,
    deviceName: name,
    sharedSecret: _secret,
    dbEncryptionKey: dbEncryptionKey,
    lastSyncHlc: lastSyncHlc,
    createdAt: DateTime.utc(2026, 1, 1),
    lastSeen: lastSeen,
  );
}

void main() {
  group('SecurePeerStorage', () {
    late InMemoryStorageBackend storage;
    late SecurePeerStorage peerStorage;

    setUp(() {
      storage = InMemoryStorageBackend();
      peerStorage = SecurePeerStorage(storage: storage);
    });

    test('starts empty', () async {
      expect(await peerStorage.getAll(), isEmpty);
    });

    test('upsert adds a peer', () async {
      await peerStorage.upsert(_peer('node-1', name: 'Desktop'));
      final peers = await peerStorage.getAll();
      expect(peers.length, 1);
      expect(peers.first.peerId, 'node-1');
      expect(peers.first.deviceName, 'Desktop');
    });

    test('upsert replaces an existing peer with the same id', () async {
      await peerStorage.upsert(_peer('node-1', name: 'Old name'));
      await peerStorage.upsert(_peer('node-1', name: 'New name'));
      final peers = await peerStorage.getAll();
      expect(peers.length, 1);
      expect(peers.first.deviceName, 'New name');
    });

    test('getById returns the matching peer or null', () async {
      await peerStorage.upsert(_peer('node-1', name: 'Desktop'));
      await peerStorage.upsert(_peer('node-2', name: 'Phone'));
      expect((await peerStorage.getById('node-2'))?.deviceName, 'Phone');
      expect(await peerStorage.getById('unknown'), isNull);
    });

    test('persists all fields including dbEncryptionKey and lastSyncHlc',
        () async {
      final hlc = Hlc.now('node-1');
      await peerStorage.upsert(_peer(
        'node-1',
        name: 'Desktop',
        dbEncryptionKey: 'c2VjcmV0IGtleQ==',
        lastSyncHlc: hlc,
        lastSeen: DateTime.utc(2026, 6, 1),
      ));

      final reloaded = SecurePeerStorage(storage: storage);
      final peer = await reloaded.getById('node-1');
      expect(peer, isNotNull);
      expect(peer!.dbEncryptionKey, 'c2VjcmV0IGtleQ==');
      expect(peer.lastSyncHlc?.toString(), hlc.toString());
      expect(peer.lastSeen, DateTime.utc(2026, 6, 1));
      expect(peer.createdAt, DateTime.utc(2026, 1, 1));
      expect(peer.sharedSecret, _secret);
    });

    test('copyWith updates lastSyncHlc and lastSeen without touching peers',
        () async {
      await peerStorage.upsert(_peer('node-1', name: 'Desktop'));
      final peer = await peerStorage.getById('node-1');
      final updated = peer!.copyWith(
        lastSyncHlc: Hlc.now('node-1'),
        lastSeen: DateTime.utc(2026, 6, 1),
      );
      await peerStorage.upsert(updated);

      final stored = await peerStorage.getById('node-1');
      expect(stored!.lastSyncHlc, isNotNull);
      expect(stored.lastSeen, DateTime.utc(2026, 6, 1));
      expect(stored.deviceName, 'Desktop');
      expect(stored.sharedSecret, _secret);
    });

    test('copyWith can clear dbEncryptionKey', () async {
      await peerStorage.upsert(_peer('node-1', dbEncryptionKey: 'c2VjcmV0IGtleQ=='));
      final peer = await peerStorage.getById('node-1');
      await peerStorage.upsert(peer!.copyWith(clearDbEncryptionKey: true));
      expect((await peerStorage.getById('node-1'))!.dbEncryptionKey, isNull);
    });

    test('delete removes a peer', () async {
      await peerStorage.upsert(_peer('node-1'));
      await peerStorage.upsert(_peer('node-2'));
      await peerStorage.delete('node-1');
      final peers = await peerStorage.getAll();
      expect(peers.length, 1);
      expect(peers.first.peerId, 'node-2');
    });

    test('delete is a no-op for an unknown id', () async {
      await peerStorage.upsert(_peer('node-1'));
      await peerStorage.delete('unknown');
      expect((await peerStorage.getAll()).length, 1);
    });

    test('clear removes all peers', () async {
      await peerStorage.upsert(_peer('node-1'));
      await peerStorage.upsert(_peer('node-2'));
      await peerStorage.clear();
      expect(await peerStorage.getAll(), isEmpty);
    });
  });

  group('TrustedPeer', () {
    test('toJson/fromJson round-trips without lastSyncHlc', () {
      final peer = _peer('node-1');
      final restored = TrustedPeer.fromJson(peer.toJson());
      expect(restored.peerId, peer.peerId);
      expect(restored.deviceName, peer.deviceName);
      expect(restored.sharedSecret, peer.sharedSecret);
      expect(restored.lastSyncHlc, isNull);
      expect(restored.createdAt, peer.createdAt);
    });
  });
}
