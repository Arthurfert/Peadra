import 'dart:async';
import 'dart:io';

import 'package:mdns_dart/mdns_dart.dart';

import 'discovered_service.dart';

/// Browses the local network for Peadra sync services via mDNS.
abstract class SyncServiceBrowser {
  Stream<DiscoveredService> get services;

  Future<void> start();

  Future<void> stop();
}

class MDnsSyncServiceBrowser implements SyncServiceBrowser {
  MDnsSyncServiceBrowser({this.queryTimeout = Duration.zero});

  final Duration queryTimeout;

  final StreamController<DiscoveredService> _controller =
      StreamController<DiscoveredService>.broadcast();
  StreamSubscription<ServiceEntry>? _subscription;

  @override
  Stream<DiscoveredService> get services => _controller.stream;

  @override
  Future<void> start() async {
    if (_subscription != null) {
      return;
    }
    final stream = await MDNSClient.query(QueryParams(
      service: syncServiceType,
      timeout: queryTimeout,
      reusePort: true,
    ));
    _subscription = stream.listen(
      (entry) {
        final service = parseDiscoveredService(
          name: entry.name,
          host: entry.host,
          address: entry.primaryAddress,
          port: entry.port,
          infoFields: entry.infoFields,
        );
        if (service != null) {
          _controller.add(service);
        }
      },
      onError: (Object e, StackTrace st) {
        _controller.addError(e, st);
      },
      onDone: () {
        _subscription = null;
      },
    );
  }

  @override
  Future<void> stop() async {
    await _subscription?.cancel();
    _subscription = null;
  }
}

/// Builds a [DiscoveredService] from raw mDNS records, or returns null when
/// the entry lacks a TXT node id, a usable address, or a valid port.
DiscoveredService? parseDiscoveredService({
  required String name,
  required String host,
  required InternetAddress? address,
  required int port,
  required List<String> infoFields,
}) {
  final txt = MDNSService.parseTXTRecords(infoFields);
  final nodeId = txt['node_id'];
  if (nodeId == null || nodeId.isEmpty) {
    return null;
  }
  if (address == null || address.type != InternetAddressType.IPv4 || port == 0) {
    return null;
  }
  return DiscoveredService(
    nodeId: nodeId,
    deviceName: txt['device_name'] ?? name,
    protocolVersion: int.tryParse(txt['protocol_version'] ?? '') ?? 0,
    host: address.address,
    port: port,
  );
}
