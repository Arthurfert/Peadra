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

  /// The most recently heard advertisement per node, including sightings
  /// swallowed by the dedup window below. Dialers use it to refresh a cached
  /// address (the peer may have a new IP/port) without triggering a new sync.
  final Map<String, DiscoveredService> _latestByNode = {};
  final Map<String, DateTime> _latestSeen = {};

  /// Sightings older than this are dropped so offline/rogue nodeIds can't
  /// accumulate forever. Kept well above [dedupWindow].
  static const Duration sightingTtl = Duration(minutes: 10);

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

  Future<void> _stopAdvertising() => advertiser.stop();

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

  /// The latest advertisement heard for [nodeId], or null if never seen.
  /// Includes sightings suppressed by the dedup window.
  DiscoveredService? latestFor(String nodeId) => _latestByNode[nodeId];

  void _onService(DiscoveredService service) {
    final now = _now();
    _latestByNode[service.nodeId] = service;
    _latestSeen[service.nodeId] = now;
    _evictStaleSightings(now);
    if (service.nodeId == _localNodeId) {
      return;
    }
    final last = _lastEmitted[service.nodeId];
    if (last != null && now.difference(last) < dedupWindow) {
      return;
    }
    _lastEmitted[service.nodeId] = now;
    _controller.add(service);
  }

  void _evictStaleSightings(DateTime now) {
    final cutoff = now.subtract(sightingTtl);
    final stale = [
      for (final entry in _latestSeen.entries)
        if (entry.value.isBefore(cutoff)) entry.key,
    ];
    for (final nodeId in stale) {
      _latestByNode.remove(nodeId);
      _latestSeen.remove(nodeId);
      _lastEmitted.remove(nodeId);
    }
  }

  Future<void> _stopBrowsing() async {
    await _browserSubscription?.cancel();
    _browserSubscription = null;
    await browser.stop();
  }

  Future<void> stop() async {
    await _stopBrowsing();
    await _stopAdvertising();
    await _multicastLock.release();
    _lastEmitted.clear();
    _latestByNode.clear();
    _latestSeen.clear();
  }
}
