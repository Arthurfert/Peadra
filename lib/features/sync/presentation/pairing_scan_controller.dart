import 'dart:async';

import '../../../sync/network/discovered_service.dart';

/// Marker for the 30s discovery timeout (distinct from a pairing failure).
class PairingTimeout {
  const PairingTimeout();

  @override
  String toString() => 'pairing timeout';
}

enum PairingScanPhase { idle, discovering, pairing, success, error }

/// Pure state machine for the QR-pairing scan flow.
///
/// Extracted from the scanner screen so the pairing logic can be unit-tested
/// without a camera. The screen feeds it QR detections via [onQrScanned] and
/// discovered services via [onDiscovered]; it drives the [pair] callback once
/// the scanned peer shows up on the local network.
class PairingScanController {
  PairingScanController({
    required this.pair,
    this.timeout = const Duration(seconds: 30),
    void Function()? onPhaseChanged,
  }) : _onPhaseChanged = onPhaseChanged;

  /// Invoked once the scanned peer is seen on the local network.
  final Future<void> Function({
    required String peerId,
    required String deviceName,
    required String sharedSecret,
    required String host,
    required int port,
  }) pair;

  final Duration timeout;

  final void Function()? _onPhaseChanged;

  final Map<String, DiscoveredService> _seen = {};
  Timer? _timeoutTimer;

  PairingScanPhase _phase = PairingScanPhase.idle;
  String? _expectedNodeId;
  String? _expectedName;
  String? _expectedSecret;
  Object? _error;

  PairingScanPhase get phase => _phase;
  String? get expectedNodeId => _expectedNodeId;
  String? get expectedName => _expectedName;
  Object? get error => _error;
  bool get isTimeoutError => _error is PairingTimeout;

  bool get busy => _phase == PairingScanPhase.discovering ||
      _phase == PairingScanPhase.pairing ||
      _phase == PairingScanPhase.success;

  /// Parses and accepts a scanned QR payload. Returns false when the payload
  /// is not a valid pairing URI.
  bool onQrScanned(String raw) {
    if (busy) return true;
    final uri = Uri.tryParse(raw);
    if (uri == null ||
        uri.scheme != 'peadra' ||
        uri.host != 'pair' ||
        uri.path.isNotEmpty) {
      return false;
    }
    final node = uri.queryParameters['node'];
    final name = uri.queryParameters['name'];
    final secret = uri.queryParameters['secret'];
    if (node == null || node.isEmpty || name == null || secret == null) {
      return false;
    }

    _expectedNodeId = node;
    _expectedName = name;
    _expectedSecret = secret;
    _error = null;
    _setPhase(PairingScanPhase.discovering);

    final known = _seen[node];
    if (known != null) {
      _startPairing(known);
    } else {
      _timeoutTimer = Timer(timeout, () {
        if (_phase == PairingScanPhase.discovering) {
          _error = const PairingTimeout();
          _setPhase(PairingScanPhase.error);
        }
      });
    }
    return true;
  }

  void onDiscovered(DiscoveredService service) {
    _seen[service.nodeId] = service;
    if (_phase == PairingScanPhase.discovering &&
        service.nodeId == _expectedNodeId) {
      _startPairing(service);
    }
  }

  Future<void> _startPairing(DiscoveredService service) async {
    _timeoutTimer?.cancel();
    if (_phase != PairingScanPhase.discovering) return;
    _setPhase(PairingScanPhase.pairing);
    try {
      await pair(
        peerId: _expectedNodeId!,
        deviceName: _expectedName!,
        sharedSecret: _expectedSecret!,
        host: service.host,
        port: service.port,
      );
      _setPhase(PairingScanPhase.success);
    } catch (e) {
      _error = e;
      _setPhase(PairingScanPhase.error);
    }
  }

  void reset() {
    _timeoutTimer?.cancel();
    _expectedNodeId = null;
    _expectedName = null;
    _expectedSecret = null;
    _error = null;
    _setPhase(PairingScanPhase.idle);
  }

  void dispose() {
    _timeoutTimer?.cancel();
  }

  void _setPhase(PairingScanPhase phase) {
    _phase = phase;
    _onPhaseChanged?.call();
  }
}
