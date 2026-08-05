import 'package:flutter_test/flutter_test.dart';

import 'package:peadra/sync/security/node_identity.dart';

import '../helpers/in_memory_storage_backend.dart';

void main() {
  group('NodeIdentity', () {
    late InMemoryStorageBackend storage;

    setUp(() {
      storage = InMemoryStorageBackend();
    });

    test('generates and persists a stable node id', () async {
      final identity = NodeIdentity(storage: storage, deviceName: 'test');
      final id = await identity.nodeId;

      expect(id, isNotEmpty);
      expect(await storage.read('sync_local_node_id'), id);

      final reloaded = NodeIdentity(storage: storage, deviceName: 'test');
      expect(await reloaded.nodeId, id);
    });

    test('generates different node ids across independent stores', () async {
      final a = NodeIdentity(storage: storage, deviceName: 'a');
      final b = NodeIdentity(
        storage: InMemoryStorageBackend(),
        deviceName: 'b',
      );
      expect(await a.nodeId, isNot(await b.nodeId));
    });

    test('uses the configured device name', () async {
      final identity = NodeIdentity(storage: storage, deviceName: 'test-device');
      expect(await identity.deviceName, 'test-device');
    });

    test('persists the generated device name across instances', () async {
      final identity = NodeIdentity(storage: storage, deviceName: 'test-device');
      await identity.deviceName;

      final reloaded = NodeIdentity(storage: storage);
      expect(await reloaded.deviceName, 'test-device');
    });

    test('falls back to a non-empty default device name', () async {
      final identity = NodeIdentity(storage: storage);
      expect(await identity.deviceName, isNotEmpty);
    });

    test('reset forgets the stored identity', () async {
      final identity = NodeIdentity(storage: storage, deviceName: 'test');
      final id = await identity.nodeId;
      await identity.deviceName;

      await identity.reset();

      expect(await storage.read('sync_local_node_id'), isNull);
      expect(await storage.read('sync_device_name'), isNull);
      final regenerated = await identity.nodeId;
      expect(regenerated, isNot(id));
      expect(regenerated, isNotEmpty);
    });
  });
}
