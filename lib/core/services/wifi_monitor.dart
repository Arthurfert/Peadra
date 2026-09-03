import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';

import 'log_service.dart';

/// Monitors Wi-Fi connectivity and notifies when network availability changes.
class WifiMonitor {
  WifiMonitor({Connectivity? connectivity})
      : _connectivity = connectivity ?? Connectivity();

  final Connectivity _connectivity;
  StreamSubscription<List<ConnectivityResult>>? _subscription;

  final StreamController<bool> _controller =
      StreamController<bool>.broadcast();

  /// Emits `true` when Wi-Fi is available, `false` when lost.
  Stream<bool> get onWifiChanged => _controller.stream;

  bool _lastWifiState = false;

  bool get isWifiAvailable => _lastWifiState;

  /// Starts listening for connectivity changes.
  void start() {
    _subscription?.cancel();
    _subscription = _connectivity.onConnectivityChanged.listen((results) {
      final hasWifi = results.any((r) => r == ConnectivityResult.wifi);
      if (hasWifi != _lastWifiState) {
        _lastWifiState = hasWifi;
        LogService().log('Wi-Fi ${hasWifi ? "connected" : "disconnected"}');
        _controller.add(hasWifi);
      }
    });
  }

  /// Checks current connectivity state.
  Future<bool> checkWifi() async {
    final results = await _connectivity.checkConnectivity();
    final hasWifi = results.any((r) => r == ConnectivityResult.wifi);
    _lastWifiState = hasWifi;
    return hasWifi;
  }

  /// Stops listening.
  void stop() {
    _subscription?.cancel();
    _subscription = null;
  }

  void dispose() {
    stop();
    _controller.close();
  }
}
