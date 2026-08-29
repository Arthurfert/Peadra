import 'dart:async';

import '../../core/services/log_service.dart';
import 'android_multicast_lock.dart';
import 'discovered_service.dart';
import 'service_advertiser.dart';
import 'service_browser.dart';

/// Orchestrates mDNS advertisement and browsing for the sync layer.
///
/// Advertises the `_peadra-sync._tcp` service so other devices can find this
/// one, and browses for the same service, emitting a [DiscoveredService] for
/// every reachable peer. The local node is filtered out and duplicate
/// discoveries are suppressed within [dedupWindow] to avoid reconnect storms.
class MDnsDiscoveryService {
  MDnsDiscoveryService({
    required this.advertiser,
    required this.browser,
    this.dedupWindow = const Duration(seconds: 30),
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final SyncServiceAdvertiser advertiser;
  final SyncServiceBrowser browser;
  final Duration dedupWindow;
  final DateTime Function() _now;
  final AndroidMulticastLock _multicastLock = AndroidMulticastLock();

  String? _localNodeId;
  final StreamController<DiscoveredService> _controller =
      StreamController<DiscoveredService>.broadcast();
  StreamSubscription<DiscoveredService>? _browserSubscription;
  final Map<String, DateTime> _lastEmitted = {};

  /// Emits peers discovered on the local network, minus the local node.
  Stream<DiscoveredService> get onServiceFound => _controller.stream;

  /// Advertises this device so trusted peers can find it. Passing a new
  /// [port] restarts the advertisement (e.g. after the sync server rebinds).
  Future<void> advertise({
    required String nodeId,
    required String deviceName,
    required int protocolVersion,
    required int port,
  }) async {
    // Without the WiFi multicast lock Android filters the mDNS multicast
    // traffic used for both responding to and hearing peer queries.
    await _multicastLock.acquire();
    try {
      await advertiser.advertise(
        nodeId: nodeId,
        deviceName: deviceName,
        protocolVersion: protocolVersion,
        port: port,
      );
    } catch (e) {
      LogService().error('mDNS advertise failed: $e');
    }
  }

  Future<void> stopAdvertising() => advertiser.stop();

  Future<void> startBrowsing({required String localNodeId}) async {
    _localNodeId = localNodeId;
    await browser.start();
    _browserSubscription ??= browser.services.listen(
      _onService,
      onError: (Object e, StackTrace st) {
        LogService().error('mDNS browsing error: $e', st.toString());
      },
    );
  }

  void _onService(DiscoveredService service) {
    if (service.nodeId == _localNodeId) {
      return;
    }
    final last = _lastEmitted[service.nodeId];
    if (last != null && _now().difference(last) < dedupWindow) {
      return;
    }
    _lastEmitted[service.nodeId] = _now();
    _controller.add(service);
  }

  Future<void> stopBrowsing() async {
    await _browserSubscription?.cancel();
    _browserSubscription = null;
    await browser.stop();
  }

  Future<void> stop() async {
    await stopBrowsing();
    await stopAdvertising();
    await _multicastLock.release();
    _lastEmitted.clear();
  }
}
