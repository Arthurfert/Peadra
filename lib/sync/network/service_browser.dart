import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:mdns_dart/mdns_dart.dart';

import 'discovered_service.dart';

/// Browses the local network for Peadra sync services via mDNS.
abstract class SyncServiceBrowser {
  Stream<DiscoveredService> get services;

  Future<void> start();

  Future<void> stop();
}

class MDnsSyncServiceBrowser implements SyncServiceBrowser {
  MDnsSyncServiceBrowser({
    this.queryTimeout = const Duration(seconds: 15),
    this.requeryInterval = const Duration(seconds: 5),
  });

  /// How long each query session stays open. mDNS servers only answer the
  /// queries they hear, so a fresh query is issued again [requeryInterval]
  /// after each session expires; otherwise a peer that comes online after
  /// this browser started would never be discovered.
  final Duration queryTimeout;

  /// Pause between consecutive query sessions.
  final Duration requeryInterval;

  final StreamController<DiscoveredService> _controller =
      StreamController<DiscoveredService>.broadcast();
  StreamSubscription<ServiceEntry>? _subscription;
  Timer? _requeryTimer;
  bool _started = false;
  int _generation = 0;

  @override
  Stream<DiscoveredService> get services => _controller.stream;

  @override
  Future<void> start() async {
    if (_started) {
      return;
    }
    _started = true;
    _generation++;
    await _startQuery();
  }

  Future<void> _startQuery() async {
    final gen = _generation;
    debugPrint('[peadra-sync] browser: starting query session (timeout $queryTimeout)');
    final stream = await MDNSClient.query(QueryParams(
      service: syncServiceType,
      timeout: queryTimeout,
      // The Dart VM rejects reusePort on Android; there SO_REUSEADDR (default)
      // alone lets multiple sockets bind 5353 and receive the mDNS multicast.
      reusePort: !Platform.isAndroid,
      logger: (m) => debugPrint('[peadra-sync] browser: $m'),
    ));
    debugPrint('[peadra-sync] browser: query session ready');
    if (gen != _generation) {
      // Stopped while the query session was being set up. Let it expire on
      // its own; its onDone is guarded by the generation check and will not
      // schedule a re-query.
      stream.listen((_) {}, onError: (Object e, StackTrace st) {}, onDone: () {});
      return;
    }
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
          debugPrint('[peadra-sync] browser: discovered ${service.nodeId} '
              '(${service.deviceName}) @ ${service.host}:${service.port}');
          _controller.add(service);
        }
      },
      onError: (Object e, StackTrace st) {
        debugPrint('[peadra-sync] browser: query error: $e');
        _controller.addError(e, st);
      },
      onDone: () {
        _subscription = null;
        debugPrint('[peadra-sync] browser: query session ended');
        if (_started && gen == _generation) {
          _scheduleRequery();
        }
      },
    );
  }

  void _scheduleRequery() {
    _requeryTimer?.cancel();
    _requeryTimer = Timer(requeryInterval, () {
      _requeryTimer = null;
      _requery();
    });
  }

  Future<void> _requery() async {
    try {
      await _startQuery();
    } catch (e, st) {
      debugPrint('[peadra-sync] browser: requery failed: $e');
      _controller.addError(e, st);
      if (_started) {
        _scheduleRequery();
      }
    }
  }

  @override
  Future<void> stop() async {
    _started = false;
    _generation++;
    _requeryTimer?.cancel();
    _requeryTimer = null;
    // The active query session is bounded by queryTimeout; leave it alone so
    // its sockets close cleanly when it expires. Its onDone is guarded by
    // _started / the generation check and will not re-query.
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
