import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:peadra/sync/models/trusted_peer.dart';
import 'package:peadra/sync/storage/secure_peer_storage.dart';

import '../helpers/in_memory_storage_backend.dart';

TrustedPeer testPeer() => TrustedPeer(
      peerId: 'peer-1',
      deviceName: 'Phone',
      sharedSecret: 'secret',
      createdAt: DateTime.utc(2024, 1, 1),
    );

/// A backend that reports a recovery (e.g. it deleted an undecryptable
/// entry) so [SecurePeerStorage] can surface it to the UI.
class RecoveredBackend extends InMemoryStorageBackend {
  bool reportRecovery = false;

  @override
  bool consumeRecoveryFlag() {
    final value = reportRecovery;
    reportRecovery = false;
    return value;
  }
}

void main() {
  test('round-trips peers through upsert and getAll', () async {
    final storage = SecurePeerStorage(storage: InMemoryStorageBackend());
    await storage.upsert(testPeer());

    final peers = await storage.getAll();
    expect(peers, hasLength(1));
    expect(peers.single.peerId, 'peer-1');
    expect(storage.consumeRecoveryFlag(), isFalse);
  });

  test('corrupt blob is reset and reported once', () async {
    final backend = InMemoryStorageBackend();
    await backend.write('sync_trusted_peers', 'truncated-json{{{');
    final storage = SecurePeerStorage(storage: backend);

    expect(await storage.getAll(), isEmpty);
    expect(storage.consumeRecoveryFlag(), isTrue);
    expect(storage.consumeRecoveryFlag(), isFalse);

    // The corrupt entry was quarantined: later reads stay empty, and the
    // store is usable again.
    expect(await storage.getAll(), isEmpty);
    expect(await backend.read('sync_trusted_peers'), isNull);
    await storage.upsert(testPeer());
    expect((await storage.getAll()).single.peerId, 'peer-1');
  });

  test('backend-level recovery is surfaced to the UI flag', () async {
    final backend = RecoveredBackend()..reportRecovery = true;
    final storage = SecurePeerStorage(storage: backend);

    expect(await storage.getAll(), isEmpty);
    expect(storage.consumeRecoveryFlag(), isTrue);
  });

  test('wrong-typed JSON values are treated as corrupt, not fatal', () async {
    final backend = InMemoryStorageBackend();
    await backend.write(
      'sync_trusted_peers',
      jsonEncode([
        {'peer_id': 42}
      ]),
    );
    final storage = SecurePeerStorage(storage: backend);

    expect(await storage.getAll(), isEmpty);
    expect(storage.consumeRecoveryFlag(), isTrue);
  });
}
