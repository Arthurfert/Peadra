import 'package:mdns_dart/mdns_dart.dart';

import 'discovered_service.dart';

/// Advertises the Peadra sync service on the local network via mDNS.
abstract class SyncServiceAdvertiser {
  Future<void> advertise({
    required String nodeId,
    required String deviceName,
    required int protocolVersion,
    required int port,
  });

  Future<void> stop();
}

class MDnsSyncServiceAdvertiser implements SyncServiceAdvertiser {
  MDNSServer? _server;
  bool _advertising = false;

  @override
  Future<void> advertise({
    required String nodeId,
    required String deviceName,
    required int protocolVersion,
    required int port,
  }) async {
    if (_advertising) {
      await stop();
    }
    final service = await MDNSService.create(
      instance: deviceName,
      service: syncServiceType,
      port: port,
      txt: MDNSService.createTXTRecords({
        'node_id': nodeId,
        'device_name': deviceName,
        'protocol_version': '$protocolVersion',
      }),
    );
    final zone = MultiServiceZone()..addService(service);
    final server = MDNSServer(MDNSServerConfig(zone: zone));
    await server.start();
    _server = server;
    _advertising = true;
  }

  @override
  Future<void> stop() async {
    await _server?.stop();
    _server = null;
    _advertising = false;
  }
}
