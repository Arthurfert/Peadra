import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../core/i18n/translator.dart';
import '../../../core/providers/theme_provider.dart';
import '../../../core/responsive/responsive_layout.dart';
import '../../../core/theme/peadra_colors.dart';
import '../../../sync/models/sync_session_status.dart';
import '../../../sync/sync_service.dart';

/// Shows a QR code another device can scan to pair with this one.
///
/// A fresh shared secret is generated per pairing attempt and registered with
/// the [SyncService] so the other device can authenticate once it connects.
/// Live [SyncSessionStatus] events update the waiting indicator, so the device
/// displaying the code gives the same feedback the scanner sees.
class QrPairingScreen extends StatefulWidget {
  const QrPairingScreen({super.key});

  @override
  State<QrPairingScreen> createState() => _QrPairingScreenState();
}

class _QrPairingScreenState extends State<QrPairingScreen> {
  final Random _random = Random.secure();
  String? _nodeId;
  String? _deviceName;
  String? _pairingUri;
  SyncSessionStatus? _status;
  StreamSubscription<SyncSessionStatus>? _statusSub;

  @override
  void initState() {
    super.initState();
    _preparePairing();
    _statusSub = SyncService.instance.onSyncStatus.listen((status) {
      if (mounted) setState(() => _status = status);
    });
  }

  @override
  void dispose() {
    _statusSub?.cancel();
    super.dispose();
  }

  Future<void> _preparePairing() async {
    final service = SyncService.instance;
    final nodeId = await service.nodeId;
    final deviceName = await service.deviceName;
    final secret = base64UrlEncode(
      List<int>.generate(32, (_) => _random.nextInt(256)),
    ).replaceAll('=', '');
    final uri = 'peadra://pair?node=$nodeId&name='
        '${Uri.encodeComponent(deviceName)}&secret=$secret';
    service.registerPairingSecret(nodeId, secret);
    if (mounted) {
      setState(() {
        _nodeId = nodeId;
        _deviceName = deviceName;
        _pairingUri = uri;
        _status = null;
      });
    }
  }

  void _regenerate() {
    _preparePairing();
  }

  bool get _isActive => _status == SyncSessionStatus.connecting ||
      _status == SyncSessionStatus.exchangingKeys ||
      _status == SyncSessionStatus.reconcilingUsers ||
      _status == SyncSessionStatus.syncing;

  String? _statusLabel(SyncSessionStatus? status) {
    switch (status) {
      case SyncSessionStatus.connecting:
        return Translator.t('sync_qr_connecting');
      case SyncSessionStatus.exchangingKeys:
        return Translator.t('sync_step_keys');
      case SyncSessionStatus.reconcilingUsers:
        return Translator.t('sync_step_users');
      case SyncSessionStatus.syncing:
        return Translator.t('sync_step_sync');
      case SyncSessionStatus.completed:
        return Translator.t('sync_qr_paired');
      case SyncSessionStatus.failed:
        return Translator.t('sync_pair_failed');
      case null:
        return null;
    }
  }

  Widget _buildStatusArea(PeadraColors colors) {
    if (_status == SyncSessionStatus.completed) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_circle, color: colors.success, size: 40),
          const SizedBox(height: 12),
          Text(
            _statusLabel(_status)!,
            style: TextStyle(
              color: colors.text,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              OutlinedButton.icon(
                icon: Icon(Icons.add_link,
                    color: colors.accent, size: 18),
                label: Text(
                  Translator.t('sync_qr_pair_another'),
                  style: TextStyle(color: colors.accent),
                ),
                onPressed: _regenerate,
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                icon: const Icon(Icons.check, color: Colors.white, size: 18),
                label: Text(
                  Translator.t('btn_done'),
                  style: const TextStyle(color: Colors.white),
                ),
                style: FilledButton.styleFrom(backgroundColor: colors.accent),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ],
      );
    }

    if (_status == SyncSessionStatus.failed) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline, color: colors.error, size: 40),
          const SizedBox(height: 12),
          Text(
            _statusLabel(_status)!,
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
            onPressed: _regenerate,
          ),
        ],
      );
    }

    final label = _isActive ? _statusLabel(_status) : null;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: colors.accent,
          ),
        ),
        const SizedBox(width: 12),
        Flexible(
          child: Text(
            label ?? Translator.t('sync_qr_waiting'),
            style: TextStyle(color: colors.text),
          ),
        ),
      ],
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
              title: Text(Translator.t('sync_qr_title'),
                  style: TextStyle(color: colors.text)),
              backgroundColor: colors.surface,
              iconTheme: IconThemeData(color: colors.text),
            ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isPhone) ...[
                  Text(
                    Translator.t('sync_qr_title'),
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: colors.text,
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
                Card(
                  color: colors.surface,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(color: colors.borderColor),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: _pairingUri == null
                        ? SizedBox(
                            width: 220,
                            height: 220,
                            child: Center(
                              child: CircularProgressIndicator(
                                color: colors.accent,
                              ),
                            ),
                          )
                        : QrImageView(
                            data: _pairingUri!,
                            version: QrVersions.auto,
                            size: 220,
                            backgroundColor: Colors.white,
                            padding: const EdgeInsets.all(8),
                          ),
                  ),
                ),
                const SizedBox(height: 24),
                if (_deviceName != null)
                  Text(
                    Translator.t('sync_qr_device', params: {'name': _deviceName!}),
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: colors.text,
                    ),
                    textAlign: TextAlign.center,
                  ),
                if (_nodeId != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    _nodeId!.split('-').first,
                    style: TextStyle(
                      fontSize: 12,
                      color: colors.placeholderColor,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
                const SizedBox(height: 16),
                Text(
                  Translator.t('sync_qr_instructions'),
                  style: TextStyle(color: colors.placeholderColor, height: 1.4),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                _buildStatusArea(colors),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
