import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import '../../core/services/log_service.dart';
import '../security/auth_challenge.dart';
import 'framing.dart';
import 'sync_messages.dart';

/// The device we are connected to, as resolved during the handshake.
class SessionPeer {
  const SessionPeer(this.nodeId, this.deviceName, this.protocolVersion);

  final String nodeId;
  final String deviceName;
  final int protocolVersion;
}

/// The outcome of a successful mutual-authentication handshake.
class HandshakeResult {
  const HandshakeResult({
    required this.peer,
    required this.clientToServerKey,
    required this.serverToClientKey,
  });

  final SessionPeer peer;
  final SecretKey clientToServerKey;
  final SecretKey serverToClientKey;
}

/// A single authenticated sync connection.
///
/// Runs the mutual HMAC handshake in either the responder ([SyncSession]
/// constructed server-side) or initiator ([SyncSession] constructed by the
/// client) role, then encrypts every subsequent payload with AES-256-GCM
/// under the per-direction session keys.
class SyncSession {
  SyncSession({
    required Socket socket,
    required String nodeId,
    required String deviceName,
    int protocolVersion = currentProtocolVersion,
    Future<String?> Function(String nodeId)? secretResolver,
    Duration timeout = const Duration(seconds: 30),
  })  : _socket = socket,
        _codec = FrameCodec(socket),
        _nodeId = nodeId,
        _deviceName = deviceName,
        _protocolVersion = protocolVersion,
        _secretResolver = secretResolver,
        _timeout = timeout;

  static const int currentProtocolVersion = 1;

  final Socket _socket;
  final FrameCodec _codec;
  final String _nodeId;
  final String _deviceName;
  final int _protocolVersion;
  final Future<String?> Function(String nodeId)? _secretResolver;
  final Duration _timeout;
  final AesGcm _aes = AesGcm.with256bits();

  SecretKey? _sendKey;
  SecretKey? _receiveKey;
  int _sendCounter = 0;

  /// The peer resolved during the handshake; null until one completes.
  SessionPeer? _peer;

  bool get authenticated => _sendKey != null && _receiveKey != null;

  /// The authenticated remote peer, or null before the handshake completes.
  SessionPeer? get peer => _peer;

  /// Responder role: validates the client's HELLO and its HMAC proof.
  Future<HandshakeResult> handshakeAsServer() async {
    final hello = await _readNext();
    if (hello == null) throw SyncProtocolException('EOF during handshake');
    if (hello['type'] != SyncMessageTypes.hello) {
      throw SyncProtocolException('Expected HELLO, got ${hello['type']}');
    }
    final peerNodeId = hello['node_id'] as String?;
    final peerDeviceName = hello['device_name'] as String? ?? 'unknown';
    final peerVersion = hello['protocol_version'] as int? ?? 0;
    if (peerNodeId == null || peerNodeId.isEmpty) {
      throw SyncProtocolException('HELLO missing node_id');
    }
    if (peerVersion != _protocolVersion) {
      await _send({
        'type': SyncMessageTypes.error,
        'code': 'unsupported_protocol_version',
      });
      throw SyncProtocolException('Unsupported protocol version $peerVersion');
    }
    final secret = await _secretResolver?.call(peerNodeId);
    if (secret == null) {
      LogService().warn('Sync: unknown peer $peerNodeId');
      await _send({'type': SyncMessageTypes.error, 'code': 'unknown_peer'});
      throw SyncAuthenticationException('Unknown peer node $peerNodeId');
    }
    final nonceA = AuthChallenge.generateNonce();
    await _send({'type': SyncMessageTypes.challengeA, 'nonce_a': nonceA});

    final responseA = await _readNext();
    if (responseA == null) throw SyncProtocolException('EOF during handshake');
    final hmacA = responseA['hmac_a'] as String?;
    final nonceB = responseA['nonce_b'] as String?;
    if (hmacA == null ||
        nonceB == null ||
        !await AuthChallenge.verify(secret, nonceA, hmacA)) {
      LogService().error('Sync: HMAC verification failed');
      await _send({'type': SyncMessageTypes.error, 'code': 'auth_failed'});
      throw SyncAuthenticationException('Invalid HMAC response');
    }

    final hmacB = await AuthChallenge.sign(secret, nonceB);
    await _send({'type': SyncMessageTypes.responseB, 'hmac_b': hmacB});
    await _send({
      'type': SyncMessageTypes.ok,
      'node_id': _nodeId,
      'device_name': _deviceName,
    });

    final (clientKey, serverKey) = await AuthChallenge.deriveSessionKeys(
      sharedSecret: secret,
      nonceA: nonceA,
      nonceB: nonceB,
    );
    _sendKey = serverKey;
    _receiveKey = clientKey;
    _peer = SessionPeer(peerNodeId, peerDeviceName, peerVersion);
    return HandshakeResult(
      peer: SessionPeer(peerNodeId, peerDeviceName, peerVersion),
      clientToServerKey: clientKey,
      serverToClientKey: serverKey,
    );
  }

  /// Initiator role: proves knowledge of [sharedSecret] and validates the
  /// server's identity against [expectedPeerNodeId].
  Future<HandshakeResult> handshakeAsClient({
    required String sharedSecret,
    String? expectedPeerNodeId,
  }) async {
    await _send({
      'type': SyncMessageTypes.hello,
      'node_id': _nodeId,
      'device_name': _deviceName,
      'protocol_version': _protocolVersion,
    });

    final challengeA = await _readNext();
    if (challengeA == null) throw SyncProtocolException('EOF during handshake');
    if (challengeA['type'] == SyncMessageTypes.error) {
      throw SyncAuthenticationException(
        'Server rejected: ${challengeA['code'] ?? 'unknown'}',
      );
    }
    if (challengeA['type'] != SyncMessageTypes.challengeA) {
      throw SyncProtocolException('Expected CHALLENGE_A');
    }
    final nonceA = challengeA['nonce_a'] as String?;
    if (nonceA == null) throw SyncProtocolException('Missing nonce_a');

    final nonceB = AuthChallenge.generateNonce();
    final hmacA = await AuthChallenge.sign(sharedSecret, nonceA);
    await _send({
      'type': SyncMessageTypes.responseA,
      'hmac_a': hmacA,
      'nonce_b': nonceB,
    });

    final responseB = await _readNext();
    if (responseB == null) throw SyncProtocolException('EOF during handshake');
    if (responseB['type'] == SyncMessageTypes.error) {
      throw SyncAuthenticationException(
        'Server rejected: ${responseB['code'] ?? 'auth_failed'}',
      );
    }
    final hmacB = responseB['hmac_b'] as String?;
    if (hmacB == null ||
        !await AuthChallenge.verify(sharedSecret, nonceB, hmacB)) {
      LogService().error('Sync: peer HMAC verification failed');
      throw SyncAuthenticationException('Invalid HMAC response from server');
    }

    final ok = await _readNext();
    if (ok == null || ok['type'] != SyncMessageTypes.ok) {
      throw SyncProtocolException('Expected OK');
    }
    final serverNodeId = ok['node_id'] as String?;
    final serverDeviceName = ok['device_name'] as String? ?? 'unknown';
    if (expectedPeerNodeId != null && serverNodeId != expectedPeerNodeId) {
      LogService().warn('Sync: peer identity mismatch '
          'expected $expectedPeerNodeId, got $serverNodeId');
      throw SyncAuthenticationException(
        'Peer identity mismatch: expected $expectedPeerNodeId, got $serverNodeId',
      );
    }

    final (clientKey, serverKey) = await AuthChallenge.deriveSessionKeys(
      sharedSecret: sharedSecret,
      nonceA: nonceA,
      nonceB: nonceB,
    );
    _sendKey = clientKey;
    _receiveKey = serverKey;
    _peer = SessionPeer(
      serverNodeId ?? expectedPeerNodeId ?? '',
      serverDeviceName,
      _protocolVersion,
    );
    return HandshakeResult(
      peer: SessionPeer(
        serverNodeId ?? expectedPeerNodeId ?? '',
        serverDeviceName,
        _protocolVersion,
      ),
      clientToServerKey: clientKey,
      serverToClientKey: serverKey,
    );
  }

  /// Sends an encrypted message. Must be called after a successful handshake.
  Future<void> send(Map<String, dynamic> message) async {
    final key = _sendKey;
    if (key == null) throw StateError('Session is not authenticated');
    final plaintext = utf8.encode(jsonEncode(message));
    final nonce = _nextNonce();
    final box = await _aes.encrypt(plaintext, secretKey: key, nonce: nonce);
    await _send({
      'iv': base64Encode(box.nonce),
      'ct': base64Encode(box.cipherText),
      'mac': base64Encode(box.mac.bytes),
    });
  }

  /// Receives and decrypts the next message, or null on a clean close.
  Future<Map<String, dynamic>?> receive() async {
    final key = _receiveKey;
    if (key == null) throw StateError('Session is not authenticated');
    final envelope = await _readNext();
    if (envelope == null) return null;

    List<int> nonce;
    List<int> cipherText;
    List<int> mac;
    try {
      nonce = base64Decode(envelope['iv'] as String);
      cipherText = base64Decode(envelope['ct'] as String);
      mac = base64Decode(envelope['mac'] as String);
    } on FormatException {
      throw SyncProtocolException('Malformed encrypted envelope');
    }
    try {
      final plaintext = await _aes.decrypt(
        SecretBox(cipherText, nonce: nonce, mac: Mac(mac)),
        secretKey: key,
      );
      return jsonDecode(utf8.decode(plaintext)) as Map<String, dynamic>;
    } on SecretBoxAuthenticationError {
      throw SyncAuthenticationException('MAC verification failed');
    } on FormatException {
      throw SyncProtocolException('Invalid JSON in decrypted payload');
    }
  }

  Future<void> close() async {
    try {
      await _socket.close();
    } catch (_) {}
  }

  /// 12-byte nonce: 8 zero bytes + a per-direction 32-bit counter.
  Uint8List _nextNonce() {
    final nonce = Uint8List(12);
    ByteData.sublistView(nonce).setUint32(8, _sendCounter++);
    return nonce;
  }

  Future<Map<String, dynamic>?> _readNext() =>
      _codec.readNext().timeout(_timeout);

  Future<void> _send(Map<String, dynamic> message) =>
      _codec.send(message).timeout(_timeout);
}
