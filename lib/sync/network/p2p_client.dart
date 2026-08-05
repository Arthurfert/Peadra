import 'dart:io';

import 'package:flutter/foundation.dart';

import 'sync_session.dart';

/// Connects to a remote [P2pServer] and performs the initiator role of the
/// mutual-authentication handshake.
class P2pClient {
  Future<SyncSession> connect({
    required String host,
    required int port,
    required String nodeId,
    required String deviceName,
    required String peerNodeId,
    required String sharedSecret,
    Duration timeout = const Duration(seconds: 15),
  }) async {
    debugPrint('[peadra-sync] client: TCP connect to $host:$port '
        '(expecting peer $peerNodeId)');
    final socket = await Socket.connect(host, port, timeout: timeout);
    debugPrint('[peadra-sync] client: TCP connected to $host:$port');
    try {
      final session = SyncSession(
        socket: socket,
        nodeId: nodeId,
        deviceName: deviceName,
      );
      await session.handshakeAsClient(
        sharedSecret: sharedSecret,
        expectedPeerNodeId: peerNodeId,
      );
      debugPrint('[peadra-sync] client: handshake OK with $peerNodeId');
      return session;
    } catch (_) {
      try {
        await socket.close();
      } catch (_) {}
      rethrow;
    }
  }
}
