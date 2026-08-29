import 'dart:io';

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
    final socket = await Socket.connect(host, port, timeout: timeout);
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
      return session;
    } catch (_) {
      try {
        await socket.close();
      } catch (_) {}
      rethrow;
    }
  }
}
