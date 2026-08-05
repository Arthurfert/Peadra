import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../core/i18n/translator.dart';
import '../../../core/providers/theme_provider.dart';
import '../../../core/responsive/responsive_layout.dart';
import '../../../core/theme/peadra_colors.dart';
import '../../../shared/widgets/peadra_notification.dart';
import '../../../sync/models/trusted_peer.dart';
import '../../../sync/sync_service.dart';

/// Lists the paired devices with a manual sync trigger and a forget action.
class PeersListScreen extends StatefulWidget {
  const PeersListScreen({
    super.key,
    this.loadPeers,
    this.syncPeer,
    this.forgetPeer,
    this.updatePeerKey,
  });

  /// Injectable data sources, defaulting to the live [SyncService].
  final Future<List<TrustedPeer>> Function()? loadPeers;
  final Future<void> Function(String peerId)? syncPeer;
  final Future<void> Function(String peerId)? forgetPeer;
  final Future<void> Function(String peerId)? updatePeerKey;

  @override
  State<PeersListScreen> createState() => _PeersListScreenState();
}

class _PeersListScreenState extends State<PeersListScreen> {
  List<TrustedPeer> _peers = [];
  bool _loading = true;
  String? _syncingPeerId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final peers =
        await (widget.loadPeers?.call() ?? SyncService.instance.getPeers());
    if (mounted) {
      setState(() {
        _peers = peers;
        _loading = false;
      });
    }
  }

  Future<void> _syncPeer(TrustedPeer peer) async {
    setState(() => _syncingPeerId = peer.peerId);
    try {
      await (widget.syncPeer?.call(peer.peerId) ??
          SyncService.instance.syncNow(peer.peerId));
      if (mounted) {
        PeadraNotification.show(context,
            message: Translator.t('sync_sync_success'));
        await _load();
      }
    } catch (e) {
      if (mounted) {
        PeadraNotification.show(context,
            message: Translator.t('sync_sync_failed'),
            type: NotificationType.error);
      }
    } finally {
      if (mounted) setState(() => _syncingPeerId = null);
    }
  }

  Future<void> _reshareKey(TrustedPeer peer) async {
    setState(() => _syncingPeerId = peer.peerId);
    try {
      await (widget.updatePeerKey?.call(peer.peerId) ??
          SyncService.instance.updatePeerKey(peer.peerId));
      if (mounted) {
        PeadraNotification.show(context,
            message: Translator.t('sync_reshare_success'));
        await _load();
      }
    } catch (e) {
      if (mounted) {
        PeadraNotification.show(context,
            message: Translator.t('sync_reshare_failed'),
            type: NotificationType.error);
      }
    } finally {
      if (mounted) setState(() => _syncingPeerId = null);
    }
  }

  Future<void> _forgetPeer(TrustedPeer peer) async {
    final colors =
        PeadraTheme.getColors(context.read<ThemeProvider>().themeName);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: colors.surface,
        title: Text(Translator.t('sync_forget'),
            style: TextStyle(color: colors.error)),
        content: Text(Translator.t('sync_forget_confirm',
            params: {'name': peer.deviceName})),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(Translator.t('btn_cancel'),
                style: TextStyle(color: colors.placeholderColor)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(Translator.t('sync_forget'),
                style: TextStyle(color: colors.error)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await (widget.forgetPeer?.call(peer.peerId) ??
        SyncService.instance.forgetPeer(peer.peerId));
    if (mounted) {
      PeadraNotification.show(context,
          message: Translator.t('sync_peer_forgotten'));
      await _load();
    }
  }

  String _formatLastSeen(TrustedPeer peer) {
    final lastSeen = peer.lastSeen;
    if (lastSeen == null) return Translator.t('sync_never_synced');
    final format = DateFormat('d MMM yyyy, HH:mm');
    return Translator.t('sync_last_seen',
        params: {'time': format.format(lastSeen.toLocal())});
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
              title: Text(Translator.t('sync_manage'),
                  style: TextStyle(color: colors.text)),
              backgroundColor: colors.surface,
              iconTheme: IconThemeData(color: colors.text),
            ),
      body: SafeArea(
        child: isPhone
            ? _buildContent(colors, isPhone: true)
            : Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 720),
                  child: _buildContent(colors, isPhone: false),
                ),
              ),
      ),
    );
  }

  Widget _buildContent(PeadraColors colors, {required bool isPhone}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (isPhone)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              Translator.t('sync_manage'),
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: colors.text,
              ),
            ),
          ),
        Expanded(
          child: _loading
              ? Center(
                  child: CircularProgressIndicator(color: colors.accent),
                )
              : _peers.isEmpty
                  ? _buildEmpty(colors)
                  : ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: _peers.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, index) =>
                          _buildPeerTile(colors, _peers[index]),
                    ),
        ),
      ],
    );
  }

  Widget _buildEmpty(PeadraColors colors) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.devices_other, color: colors.placeholderColor, size: 48),
            const SizedBox(height: 16),
            Text(
              Translator.t('sync_peers_empty'),
              style: TextStyle(color: colors.placeholderColor, height: 1.4),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPeerTile(PeadraColors colors, TrustedPeer peer) {
    final syncing = _syncingPeerId == peer.peerId;
    return Card(
      color: colors.surface,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: colors.accent.withValues(alpha: 0.12),
          child: Icon(Icons.devices, color: colors.accent, size: 20),
        ),
        title: Text(peer.deviceName, style: TextStyle(color: colors.text)),
        subtitle: Text(
          _formatLastSeen(peer),
          style: TextStyle(color: colors.placeholderColor, fontSize: 12),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: Translator.t('sync_reshare'),
              icon: Icon(Icons.vpn_key_outlined, color: colors.textSecondary),
              onPressed: syncing ? null : () => _reshareKey(peer),
            ),
            IconButton(
              tooltip: Translator.t('sync_sync_now'),
              icon: syncing
                  ? SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: colors.accent,
                      ),
                    )
                  : Icon(Icons.sync, color: colors.accent),
              onPressed: syncing ? null : () => _syncPeer(peer),
            ),
            IconButton(
              tooltip: Translator.t('sync_forget'),
              icon: Icon(Icons.delete_outline, color: colors.deleteColor),
              onPressed: syncing ? null : () => _forgetPeer(peer),
            ),
          ],
        ),
      ),
    );
  }
}
