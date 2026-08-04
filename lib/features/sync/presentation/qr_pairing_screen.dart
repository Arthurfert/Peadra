import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../core/i18n/translator.dart';
import '../../../core/providers/theme_provider.dart';
import '../../../core/responsive/responsive_layout.dart';
import '../../../core/theme/peadra_colors.dart';
import '../../../sync/sync_service.dart';

/// Shows a QR code another device can scan to pair with this one.
///
/// A fresh shared secret is generated per pairing attempt and registered with
/// the [SyncService] so the other device can authenticate once it connects.
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

  @override
  void initState() {
    super.initState();
    _preparePairing();
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
      });
    }
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
                Row(
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
                        Translator.t('sync_qr_waiting'),
                        style: TextStyle(color: colors.text),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
