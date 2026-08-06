import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:mdns_dart/mdns_dart.dart';

import 'discovered_service.dart';

/// Builds a unique mDNS service instance name for this device.
///
/// mDNS keys service entries by their full instance name, so two devices
/// advertising the same name (e.g. "Peadra android" on every Android phone)
/// collapse into a single entry and never discover each other. Appending a
/// short, stable suffix derived from the unique node id keeps each instance
/// distinct; the friendly name still travels in the TXT `device_name` record
/// and is what the UI displays.
String buildServiceInstanceName({
  required String deviceName,
  required String nodeId,
}) {
  final suffix = nodeId.length >= 8 ? nodeId.substring(0, 8) : nodeId;
  return '$deviceName-$suffix';
}

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
      instance: buildServiceInstanceName(
        deviceName: deviceName,
        nodeId: nodeId,
      ),
      service: syncServiceType,
      port: port,
      txt: MDNSService.createTXTRecords({
        'node_id': nodeId,
        'device_name': deviceName,
        'protocol_version': '$protocolVersion',
      }),
    );
    final zone = MultiServiceZone()..addService(service);
    // Both the advertiser and the browser bind UDP 5353 on this device, so
    // the sockets must share the port. The Dart VM rejects reusePort on
    // Android; there SO_REUSEADDR alone still lets multiple sockets bind 5353
    // and receive the mDNS multicast.
    final server = MDNSServer(MDNSServerConfig(
      zone: zone,
      reusePort: !Platform.isAndroid,
      reuseAddress: true,
      logger: (m) => debugPrint('[peadra-sync] advertiser: $m'),
    ));
    try {
      await server.start();
    } catch (e) {
      debugPrint('[peadra-sync] advertiser FAILED to start: $e');
      rethrow;
    }
    _server = server;
    _advertising = true;
    debugPrint('[peadra-sync] advertiser up on port 5353 (service $syncServiceType, port $port)');
  }

  @override
  Future<void> stop() async {
    await _server?.stop();
    _server = null;
    _advertising = false;
  }
}
