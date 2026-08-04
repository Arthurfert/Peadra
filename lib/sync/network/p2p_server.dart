import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../core/services/log_service.dart';
import 'sync_session.dart';

/// Listens for incoming sync connections and performs the responder role of
/// the mutual-authentication handshake before handing the authenticated
/// session to [onSession].
class P2pServer {
  ServerSocket? _server;
  int? _port;

  /// The port the server is bound to, or null before [start].
  int? get port => _port;

  Future<int> start({
    required String nodeId,
    required String deviceName,
    required Future<String?> Function(String nodeId) secretResolver,
    required Future<void> Function(SyncSession session) onSession,
  }) async {
    _server = await ServerSocket.bind(InternetAddress.anyIPv4, 0);
    _port = _server!.port;
    debugPrint('[peadra-sync] server: listening on 0.0.0.0:$_port');
    _server!.listen(
      (socket) {
        _handleConnection(
          socket,
          nodeId: nodeId,
          deviceName: deviceName,
          secretResolver: secretResolver,
          onSession: onSession,
        );
      },
      onError: (Object e, StackTrace st) {
        LogService().error('P2pServer listen error: $e', st.toString());
      },
    );
    LogService().log('P2pServer listening on port $_port');
    return _port!;
  }

  Future<void> _handleConnection(
    Socket socket, {
    required String nodeId,
    required String deviceName,
    required Future<String?> Function(String nodeId) secretResolver,
    required Future<void> Function(SyncSession session) onSession,
  }) async {
    final session = SyncSession(
      socket: socket,
      nodeId: nodeId,
      deviceName: deviceName,
      secretResolver: secretResolver,
    );
    try {
      debugPrint('[peadra-sync] server: incoming connection from '
          '${socket.remoteAddress.address}:${socket.remotePort}');
      final result = await session.handshakeAsServer();
      debugPrint('[peadra-sync] server: handshake OK with '
          '${result.peer.deviceName} (${result.peer.nodeId})');
      LogService().log(
        'Sync peer authenticated: '
        '${result.peer.deviceName} (${result.peer.nodeId})',
      );
      await onSession(session);
    } catch (e) {
      debugPrint('[peadra-sync] server: session error: $e');
      LogService().warn('Sync session error: $e');
    } finally {
      try {
        await socket.close();
      } catch (_) {}
    }
  }

  Future<void> stop() async {
    await _server?.close();
    _server = null;
    _port = null;
  }
}
