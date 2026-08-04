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
import 'pairing_scan_controller.dart';

/// Scans a device's pairing QR code and runs the pairing session once the
/// scanned device is found on the local network.
class ScannerScreen extends StatefulWidget {
  const ScannerScreen({super.key});

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> {
  StreamSubscription<DiscoveredService>? _discoverySub;
  late final PairingScanController _controller;

  @override
  void initState() {
    super.initState();
    _controller = PairingScanController(
      pair: SyncService.instance.runPairingSession,
      onPhaseChanged: () {
        if (!mounted) return;
        setState(() {});
        if (_controller.phase == PairingScanPhase.success) {
          _showSuccess();
        }
      },
    );
    _discoverySub = SyncService.instance.onPeerDiscovered.listen(
      _controller.onDiscovered,
    );
  }

  @override
  void dispose() {
    _discoverySub?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    String? raw;
    for (final barcode in capture.barcodes) {
      if (barcode.rawValue != null) {
        raw = barcode.rawValue;
        break;
      }
    }
    if (raw == null) return;
    _controller.onQrScanned(raw);
  }

  Future<void> _showSuccess() async {
    PeadraNotification.show(context,
        message: Translator.t('sync_pair_success',
            params: {'name': _controller.expectedName ?? ''}));
    await Future<void>.delayed(const Duration(milliseconds: 900));
    if (mounted) Navigator.of(context).pop(true);
  }

  void _reset() {
    _controller.reset();
    if (mounted) setState(() {});
  }

  Widget _buildScannerArea(PeadraColors colors) {
    switch (_controller.phase) {
      case PairingScanPhase.idle:
      case PairingScanPhase.discovering:
      case PairingScanPhase.pairing:
      case PairingScanPhase.success:
      case PairingScanPhase.error:
        if (_controller.phase == PairingScanPhase.idle) {
          return MobileScanner(
            onDetect: _onDetect,
            fit: BoxFit.cover,
            errorBuilder: (context, error) => _buildCameraError(colors),
          );
        }
        if (_controller.phase == PairingScanPhase.success) {
          return _buildSuccess(colors);
        }
        if (_controller.phase == PairingScanPhase.error) {
          return _buildError(colors);
        }
        return _buildOverlayStatus(colors);
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
    final isPairing = _controller.phase == PairingScanPhase.pairing;
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
            _controller.expectedName ?? '',
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
            Translator.t('sync_pair_success',
                params: {'name': _controller.expectedName ?? ''}),
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
    final isTimeout = _controller.isTimeoutError;
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
            isTimeout
                ? Translator.t('sync_scan_timeout')
                : Translator.t('sync_pair_failed'),
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
