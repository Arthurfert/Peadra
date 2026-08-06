import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:peadra/sync/network/discovered_service.dart';
import 'package:peadra/sync/network/mdns_discovery_service.dart';
import 'package:peadra/sync/network/service_advertiser.dart';
import 'package:peadra/sync/network/service_browser.dart';

class _FakeAdvertiser implements SyncServiceAdvertiser {
  String? nodeId;
  String? deviceName;
  int? protocolVersion;
  int? port;
  int advertiseCount = 0;
  int stopCount = 0;

  @override
  Future<void> advertise({
    required String nodeId,
    required String deviceName,
    required int protocolVersion,
    required int port,
  }) async {
    this.nodeId = nodeId;
    this.deviceName = deviceName;
    this.protocolVersion = protocolVersion;
    this.port = port;
    advertiseCount++;
  }

  @override
  Future<void> stop() async {
    stopCount++;
  }
}

class _FakeBrowser implements SyncServiceBrowser {
  final StreamController<DiscoveredService> _controller =
      StreamController<DiscoveredService>.broadcast();
  int startCount = 0;
  int stopCount = 0;

  @override
  Stream<DiscoveredService> get services => _controller.stream;

  @override
  Future<void> start() async {
    startCount++;
  }

  @override
  Future<void> stop() async {
    stopCount++;
  }

  void emit(DiscoveredService service) => _controller.add(service);
}

DiscoveredService _service(
  String nodeId, {
  int port = 5555,
  String deviceName = 'device',
}) {
  return DiscoveredService(
    nodeId: nodeId,
    deviceName: deviceName,
    protocolVersion: 1,
    host: '192.168.1.5',
    port: port,
  );
}

void main() {
  late _FakeAdvertiser advertiser;
  late _FakeBrowser browser;
  late DateTime now;
  late MDnsDiscoveryService discovery;

  setUp(() {
    advertiser = _FakeAdvertiser();
    browser = _FakeBrowser();
    now = DateTime(2026, 1, 1);
    discovery = MDnsDiscoveryService(
      advertiser: advertiser,
      browser: browser,
      dedupWindow: const Duration(seconds: 30),
      now: () => now,
    );
  });

  tearDown(() async {
    await discovery.stop();
  });

  group('advertise', () {
    test('forwards args to the advertiser', () async {
      await discovery.advertise(
        nodeId: 'local',
        deviceName: 'My Phone',
        protocolVersion: 2,
        port: 43210,
      );
      expect(advertiser.nodeId, 'local');
      expect(advertiser.deviceName, 'My Phone');
      expect(advertiser.protocolVersion, 2);
      expect(advertiser.port, 43210);
      expect(advertiser.advertiseCount, 1);
    });

    test('restarts advertisement on a new port', () async {
      await discovery.advertise(
        nodeId: 'local',
        deviceName: 'My Phone',
        protocolVersion: 2,
        port: 43210,
      );
      await discovery.advertise(
        nodeId: 'local',
        deviceName: 'My Phone',
        protocolVersion: 2,
        port: 43211,
      );
      expect(advertiser.advertiseCount, 2);
      expect(advertiser.port, 43211);
    });
  });

  group('browsing', () {
    test('forwards discovered peers to onServiceFound', () async {
      final seen = <DiscoveredService>[];
      final sub = discovery.onServiceFound.listen(seen.add);

      await discovery.startBrowsing(localNodeId: 'local');
      browser.emit(_service('peer-1'));
      await Future<void>.delayed(Duration.zero);

      expect(seen, hasLength(1));
      expect(seen.single.nodeId, 'peer-1');
      await sub.cancel();
    });

    test('ignores the local node', () async {
      final seen = <DiscoveredService>[];
      final sub = discovery.onServiceFound.listen(seen.add);

      await discovery.startBrowsing(localNodeId: 'local');
      browser.emit(_service('local'));
      browser.emit(_service('peer-1'));
      await Future<void>.delayed(Duration.zero);

      expect(seen.map((s) => s.nodeId), ['peer-1']);
      await sub.cancel();
    });

    test('suppresses duplicate discoveries within the dedup window', () async {
      final seen = <DiscoveredService>[];
      final sub = discovery.onServiceFound.listen(seen.add);

      await discovery.startBrowsing(localNodeId: 'local');
      browser.emit(_service('peer-1'));
      browser.emit(_service('peer-1'));
      await Future<void>.delayed(Duration.zero);

      expect(seen, hasLength(1));
      await sub.cancel();
    });

    test('re-emits a peer after the dedup window elapses', () async {
      final seen = <DiscoveredService>[];
      final sub = discovery.onServiceFound.listen(seen.add);

      await discovery.startBrowsing(localNodeId: 'local');
      browser.emit(_service('peer-1'));
      await Future<void>.delayed(Duration.zero);
      now = now.add(const Duration(seconds: 31));
      browser.emit(_service('peer-1'));
      await Future<void>.delayed(Duration.zero);

      expect(seen, hasLength(2));
      await sub.cancel();
    });

    test('does not de-duplicate distinct peers', () async {
      final seen = <DiscoveredService>[];
      final sub = discovery.onServiceFound.listen(seen.add);

      await discovery.startBrowsing(localNodeId: 'local');
      browser.emit(_service('peer-1'));
      browser.emit(_service('peer-2'));
      await Future<void>.delayed(Duration.zero);

      expect(seen, hasLength(2));
      await sub.cancel();
    });
  });

  group('stop', () {
    test('stops browsing and advertising', () async {
      await discovery.advertise(
        nodeId: 'local',
        deviceName: 'My Phone',
        protocolVersion: 2,
        port: 43210,
      );
      await discovery.startBrowsing(localNodeId: 'local');
      expect(browser.startCount, 1);

      await discovery.stop();
      expect(browser.stopCount, 1);
      expect(advertiser.stopCount, 1);

      await discovery.startBrowsing(localNodeId: 'local');
      expect(browser.startCount, 2);
    });
  });

  group('buildServiceInstanceName', () {
    test('differentiates devices that share a device name', () {
      final a = buildServiceInstanceName(
        deviceName: 'Peadra android',
        nodeId: 'aaaaaaaa-1111-2222-3333-444444444444',
      );
      final b = buildServiceInstanceName(
        deviceName: 'Peadra android',
        nodeId: 'bbbbbbbb-5555-6666-7777-888888888888',
      );
      expect(a, isNot(b));
    });

    test('is stable per node id', () {
      final first = buildServiceInstanceName(
        deviceName: 'Peadra android',
        nodeId: 'aaaaaaaa-1111-2222-3333-444444444444',
      );
      final second = buildServiceInstanceName(
        deviceName: 'Peadra android',
        nodeId: 'aaaaaaaa-1111-2222-3333-444444444444',
      );
      expect(first, second);
      expect(first, 'Peadra android-aaaaaaaa');
    });

    test('keeps the friendly name prefix', () {
      final name = buildServiceInstanceName(
        deviceName: 'My Phone',
        nodeId: 'aaaaaaaa-1111-2222-3333-444444444444',
      );
      expect(name, startsWith('My Phone-'));
    });
  });

  group('parseDiscoveredService', () {
    test('builds a service from TXT fields', () {
      final service = parseDiscoveredService(
        name: 'Phone._peadra-sync._tcp.local',
        host: 'Phone.local',
        address: InternetAddress('192.168.1.5'),
        port: 5555,
        infoFields: const [
          'node_id=peer-1',
          'device_name=My Phone',
          'protocol_version=2',
        ],
      );
      expect(service, isNotNull);
      expect(service!.nodeId, 'peer-1');
      expect(service.deviceName, 'My Phone');
      expect(service.protocolVersion, 2);
      expect(service.host, '192.168.1.5');
      expect(service.port, 5555);
    });

    test('falls back to the instance name for deviceName', () {
      final service = parseDiscoveredService(
        name: 'Phone._peadra-sync._tcp.local',
        host: 'Phone.local',
        address: InternetAddress('192.168.1.5'),
        port: 5555,
        infoFields: const ['node_id=peer-1'],
      );
      expect(service, isNotNull);
      expect(service!.deviceName, 'Phone._peadra-sync._tcp.local');
      expect(service.protocolVersion, 0);
    });

    test('returns null without a node_id TXT field', () {
      expect(
        parseDiscoveredService(
          name: 'Phone._peadra-sync._tcp.local',
          host: 'Phone.local',
          address: InternetAddress('192.168.1.5'),
          port: 5555,
          infoFields: const ['device_name=My Phone'],
        ),
        isNull,
      );
    });

    test('returns null without an IPv4 address', () {
      expect(
        parseDiscoveredService(
          name: 'Phone._peadra-sync._tcp.local',
          host: 'Phone.local',
          address: null,
          port: 5555,
          infoFields: const ['node_id=peer-1'],
        ),
        isNull,
      );
    });

    test('returns null for a zero port', () {
      expect(
        parseDiscoveredService(
          name: 'Phone._peadra-sync._tcp.local',
          host: 'Phone.local',
          address: InternetAddress('192.168.1.5'),
          port: 0,
          infoFields: const ['node_id=peer-1'],
        ),
        isNull,
      );
    });
  });
}
