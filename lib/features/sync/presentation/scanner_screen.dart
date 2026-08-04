import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';

import '../../../core/i18n/translator.dart';
import '../../../core/providers/theme_provider.dart';
import '../../../core/responsive/responsive_layout.dart';
import '../../../core/theme/peadra_colors.dart';
import '../../../shared/widgets/peadra_notification.dart';
import '../../../sync/network/discovered_service.dart';
import '../../../sync/sync_service.dart';

/// Scans a device's pairing QR code and runs the pairing session once the
/// scanned device is found on the local network.
class ScannerScreen extends StatefulWidget {
  const ScannerScreen({super.key});

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

enum _ScanStatus { scanning, discovering, pairing, success, error }

class _ScannerScreenState extends State<ScannerScreen> {
  final Map<String, DiscoveredService> _seen = {};
  StreamSubscription<DiscoveredService>? _discoverySub;
  Timer? _timeout;

  _ScanStatus _status = _ScanStatus.scanning;
  String? _expectedNodeId;
  String? _expectedName;
  String? _expectedSecret;
  String? _error;

  @override
  void initState() {
    super.initState();
    _discoverySub = SyncService.instance.onPeerDiscovered.listen(_onDiscovered);
  }

  @override
  void dispose() {
    _discoverySub?.cancel();
    _timeout?.cancel();
    super.dispose();
  }

  void _onDiscovered(DiscoveredService service) {
    _seen[service.nodeId] = service;
    if (!_handled() && service.nodeId == _expectedNodeId) {
      _startPairing(service);
    }
  }

  bool _handled() => _status == _ScanStatus.discovering ||
      _status == _ScanStatus.pairing ||
      _status == _ScanStatus.success;

  void _onDetect(BarcodeCapture capture) {
    if (_handled()) return;
    String? raw;
    for (final barcode in capture.barcodes) {
      if (barcode.rawValue != null) {
        raw = barcode.rawValue;
        break;
      }
    }
    if (raw == null) return;

    final uri = Uri.tryParse(raw);
    if (uri == null ||
        uri.scheme != 'peadra' ||
        uri.host != 'pair' ||
        uri.path.isNotEmpty) {
      return;
    }
    final node = uri.queryParameters['node'];
    final name = uri.queryParameters['name'];
    final secret = uri.queryParameters['secret'];
    if (node == null || node.isEmpty || name == null || secret == null) return;

    setState(() {
      _expectedNodeId = node;
      _expectedName = name;
      _expectedSecret = secret;
      _status = _ScanStatus.discovering;
    });

    final known = _seen[node];
    if (known != null) {
      _startPairing(known);
    } else {
      _timeout = Timer(const Duration(seconds: 30), () {
        if (mounted && _status == _ScanStatus.discovering) {
          setState(() {
            _status = _ScanStatus.error;
            _error = Translator.t('sync_scan_timeout');
          });
        }
      });
    }
  }

  Future<void> _startPairing(DiscoveredService service) async {
    _timeout?.cancel();
    if (mounted) {
      setState(() => _status = _ScanStatus.pairing);
    }
    try {
      await SyncService.instance.runPairingSession(
        peerId: _expectedNodeId!,
        deviceName: _expectedName!,
        sharedSecret: _expectedSecret!,
        host: service.host,
        port: service.port,
      );
      if (!mounted) return;
      setState(() => _status = _ScanStatus.success);
      PeadraNotification.show(context,
          message: Translator.t('sync_pair_success',
              params: {'name': _expectedName ?? ''}));
      await Future<void>.delayed(const Duration(milliseconds: 900));
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _status = _ScanStatus.error;
          _error = Translator.t('sync_pair_failed');
        });
      }
    }
  }

  void _reset() {
    _timeout?.cancel();
    setState(() {
      _expectedNodeId = null;
      _expectedName = null;
      _expectedSecret = null;
      _error = null;
      _status = _ScanStatus.scanning;
    });
  }

  Widget _buildScannerArea(PeadraColors colors) {
    switch (_status) {
      case _ScanStatus.scanning:
        return MobileScanner(
          onDetect: _onDetect,
          fit: BoxFit.cover,
          errorBuilder: (context, error) => _buildCameraError(colors),
        );
      case _ScanStatus.discovering:
      case _ScanStatus.pairing:
        return _buildOverlayStatus(colors);
      case _ScanStatus.success:
        return _buildSuccess(colors);
      case _ScanStatus.error:
        return _buildError(colors);
    }
  }

  Widget _buildCameraError(PeadraColors colors) {
    return Container(
      color: colors.surface,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.no_photography, color: colors.placeholderColor, size: 40),
          const SizedBox(height: 12),
          Text(
            Translator.t('sync_scan_no_camera'),
            style: TextStyle(color: colors.text),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildOverlayStatus(PeadraColors colors) {
    final isPairing = _status == _ScanStatus.pairing;
    return Container(
      color: colors.surface,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 40,
            height: 40,
            child: CircularProgressIndicator(strokeWidth: 3, color: colors.accent),
          ),
          const SizedBox(height: 16),
          Text(
            isPairing
                ? Translator.t('sync_scan_pairing')
                : Translator.t('sync_scan_discovering'),
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: colors.text,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          Text(
            _expectedName ?? '',
            style: TextStyle(color: colors.placeholderColor),
          ),
        ],
      ),
    );
  }

  Widget _buildSuccess(PeadraColors colors) {
    return Container(
      color: colors.surface,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_circle, color: colors.success, size: 48),
          const SizedBox(height: 12),
          Text(
            Translator.t('sync_pair_success', params: {'name': _expectedName ?? ''}),
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: colors.text,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildError(PeadraColors colors) {
    return Container(
      color: colors.surface,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline, color: colors.error, size: 40),
          const SizedBox(height: 12),
          Text(
            _error ?? Translator.t('sync_pair_failed'),
            style: TextStyle(color: colors.text),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            icon: const Icon(Icons.refresh, color: Colors.white, size: 16),
            label: Text(
              Translator.t('sync_scan_retry'),
              style: const TextStyle(color: Colors.white, fontSize: 12),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: colors.accent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onPressed: _reset,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeName = context.watch<ThemeProvider>().themeName;
    final colors = PeadraTheme.getColors(themeName);
    final isPhone = ResponsiveLayout.isPhone(context);

    return Scaffold(
      backgroundColor: colors.bg,
      appBar: isPhone
          ? null
          : AppBar(
              title: Text(Translator.t('sync_scan_title'),
                  style: TextStyle(color: colors.text)),
              backgroundColor: colors.surface,
              iconTheme: IconThemeData(color: colors.text),
            ),
      body: SafeArea(
        child: Column(
          children: [
            if (isPhone)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  Translator.t('sync_scan_title'),
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: colors.text,
                  ),
                ),
              ),
            Expanded(child: _buildScannerArea(colors)),
            Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                Translator.t('sync_scan_prompt'),
                style: TextStyle(color: colors.placeholderColor, height: 1.4),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
