import 'package:flutter_test/flutter_test.dart';

import 'package:peadra/features/sync/presentation/pairing_scan_controller.dart';
import 'package:peadra/sync/network/discovered_service.dart';

DiscoveredService _service(String nodeId,
        {String host = '192.168.1.50', int port = 4242}) =>
    DiscoveredService(
      nodeId: nodeId,
      deviceName: 'Peer',
      protocolVersion: 1,
      host: host,
      port: port,
    );

void main() {
  group('PairingScanController', () {
    test('accepts only valid peadra pairing URIs', () {
      final controller = PairingScanController(pair: ({required peerId, required deviceName, required sharedSecret, required host, required port}) async {});
      expect(
        controller.onQrScanned('https://example.com/pair?node=x'),
        isFalse,
      );
      expect(controller.phase, PairingScanPhase.idle);
      expect(
        controller.onQrScanned('peadra://pair?node=abc'),
        isFalse,
        reason: 'missing name/secret',
      );
      expect(
        controller.onQrScanned(
            'peadra://pair?node=abc&name=Peer&secret=topsecret'),
        isTrue,
      );
      expect(controller.phase, PairingScanPhase.discovering);
      expect(controller.expectedNodeId, 'abc');
    });

    test('pairs when the peer was already discovered before the scan', () async {
      var paired = false;
      final controller = PairingScanController(
        pair: ({required peerId, required deviceName, required sharedSecret, required host, required port}) async => paired = true,
      );
      controller.onDiscovered(_service('abc'));
      controller.onQrScanned('peadra://pair?node=abc&name=Peer&secret=s');
      await Future<void>.delayed(Duration.zero);
      expect(paired, isTrue);
      expect(controller.phase, PairingScanPhase.success);
    });

    test('pairs when the peer is discovered AFTER the scan', () async {
      var paired = false;
      String? capturedHost;
      int? capturedPort;
      final controller = PairingScanController(
        pair: ({required peerId, required deviceName, required sharedSecret, required host, required port}) async {
          paired = true;
          capturedHost = host;
          capturedPort = port;
        },
      );
      controller.onQrScanned('peadra://pair?node=abc&name=Peer&secret=s');
      expect(controller.phase, PairingScanPhase.discovering);
      controller.onDiscovered(_service('abc', host: '192.168.1.77', port: 36083));
      await Future<void>.delayed(Duration.zero);
      expect(paired, isTrue);
      expect(capturedHost, '192.168.1.77');
      expect(capturedPort, 36083);
      expect(controller.phase, PairingScanPhase.success);
    });

    test('ignores discoveries of other nodes while waiting', () async {
      var paired = false;
      final controller = PairingScanController(
        pair: ({required peerId, required deviceName, required sharedSecret, required host, required port}) async => paired = true,
      );
      controller.onQrScanned('peadra://pair?node=abc&name=Peer&secret=s');
      controller.onDiscovered(_service('other-node'));
      expect(paired, isFalse);
      expect(controller.phase, PairingScanPhase.discovering);
    });

    test('times out when the peer never shows up', () async {
      var paired = false;
      final controller = PairingScanController(
        pair: ({required peerId, required deviceName, required sharedSecret, required host, required port}) async => paired = true,
        timeout: const Duration(milliseconds: 20),
      );
      controller.onQrScanned('peadra://pair?node=abc&name=Peer&secret=s');
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(paired, isFalse);
      expect(controller.phase, PairingScanPhase.error);
      expect(controller.isTimeoutError, isTrue);
    });

    test('reports a pairing failure distinctly from a timeout', () async {
      final controller = PairingScanController(
        pair: ({required peerId, required deviceName, required sharedSecret, required host, required port}) async =>
            throw StateError('connection refused'),
      );
      controller.onDiscovered(_service('abc'));
      controller.onQrScanned('peadra://pair?node=abc&name=Peer&secret=s');
      await Future<void>.delayed(Duration.zero);
      expect(controller.phase, PairingScanPhase.error);
      expect(controller.isTimeoutError, isFalse);
    });

    test('reset returns to idle and clears expectations', () async {
      var paired = false;
      final controller = PairingScanController(
        pair: ({required peerId, required deviceName, required sharedSecret, required host, required port}) async => paired = true,
        timeout: const Duration(milliseconds: 20),
      );
      controller.onQrScanned('peadra://pair?node=abc&name=Peer&secret=s');
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(controller.phase, PairingScanPhase.error);
      controller.reset();
      expect(controller.phase, PairingScanPhase.idle);
      expect(controller.expectedNodeId, isNull);
    });
  });
}
