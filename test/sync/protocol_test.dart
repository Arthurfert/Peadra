import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:peadra/sync/network/framing.dart';
import 'package:peadra/sync/network/p2p_client.dart';
import 'package:peadra/sync/network/p2p_server.dart';
import 'package:peadra/sync/network/sync_messages.dart';
import 'package:peadra/sync/network/sync_session.dart';

void main() {
  const serverNodeId = 'server-node-11111111';
  const serverDeviceName = 'Server Device';
  const clientNodeId = 'client-node-22222222';
  const clientDeviceName = 'Client Device';
  const secret = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=';
  const wrongSecret = '/////////////////////////////w==';

  late P2pServer server;
  late int port;
  final serverSessions = <SyncSession>[];

  Future<void> echoHandler(SyncSession session) async {
    serverSessions.add(session);
    while (true) {
      final message = await session.receive();
      if (message == null) break;
      if (message['type'] == SyncMessageTypes.syncRequest) {
        await session.send({
          'type': SyncMessageTypes.syncResponse,
          'since_hlc': message['since_hlc'],
          'changeset': {'rows': const []},
        });
      } else if (message['type'] == SyncMessageTypes.close) {
        await session.send({'type': SyncMessageTypes.close});
        break;
      }
    }
  }

  setUp(() async {
    serverSessions.clear();
    server = P2pServer();
    port = await server.start(
      nodeId: serverNodeId,
      deviceName: serverDeviceName,
      secretResolver: (nodeId) async =>
          nodeId == clientNodeId ? secret : null,
      onSession: echoHandler,
    );
  });

  tearDown(() async {
    await server.stop();
  });

  test('handshake succeeds and encrypted messages round-trip', () async {
    final client = P2pClient();
    final session = await client.connect(
      host: 'localhost',
      port: port,
      nodeId: clientNodeId,
      deviceName: clientDeviceName,
      peerNodeId: serverNodeId,
      sharedSecret: secret,
    );
    expect(session.authenticated, isTrue);

    await session.send({'type': SyncMessageTypes.syncRequest, 'since_hlc': 'x'});
    final response = await session.receive();
    expect(response?['type'], SyncMessageTypes.syncResponse);
    expect(response?['since_hlc'], 'x');

    expect(serverSessions, hasLength(1));
    expect(serverSessions.first.authenticated, isTrue);

    await session.send({'type': SyncMessageTypes.close});
    final closeReply = await session.receive();
    expect(closeReply?['type'], SyncMessageTypes.close);
    await session.close();
  });

  test('the wire carries length-prefixed JSON frames', () async {
    final socket = await Socket.connect('localhost', port);
    final codec = FrameCodec(socket);
    await codec.send({
      'type': SyncMessageTypes.hello,
      'node_id': clientNodeId,
      'device_name': clientDeviceName,
      'protocol_version': SyncSession.currentProtocolVersion,
    });
    final challenge = await codec.readNext();
    expect(challenge?['type'], SyncMessageTypes.challengeA);
    expect(challenge?['nonce_a'], isNotEmpty);
    await socket.close();
  });

  test('forged HMAC is rejected with ERROR', () async {
    final socket = await Socket.connect('localhost', port);
    final codec = FrameCodec(socket);
    await codec.send({
      'type': SyncMessageTypes.hello,
      'node_id': clientNodeId,
      'device_name': clientDeviceName,
      'protocol_version': SyncSession.currentProtocolVersion,
    });
    final challenge = await codec.readNext();
    expect(challenge?['type'], SyncMessageTypes.challengeA);

    await codec.send({
      'type': SyncMessageTypes.responseA,
      'hmac_a': base64Encode(const [1, 2, 3, 4]),
      'nonce_b': 'nonce-b',
    });
    final reply = await codec.readNext();
    expect(reply?['type'], SyncMessageTypes.error);
    expect(reply?['code'], 'auth_failed');
    await socket.close();
  });

  test('unknown peer node is rejected with ERROR', () async {
    final socket = await Socket.connect('localhost', port);
    final codec = FrameCodec(socket);
    await codec.send({
      'type': SyncMessageTypes.hello,
      'node_id': 'unknown-node',
      'device_name': 'x',
      'protocol_version': SyncSession.currentProtocolVersion,
    });
    final reply = await codec.readNext();
    expect(reply?['type'], SyncMessageTypes.error);
    expect(reply?['code'], 'unknown_peer');
    await socket.close();
  });

  test('client with a wrong shared secret is rejected', () async {
    final client = P2pClient();
    await expectLater(
      client.connect(
        host: 'localhost',
        port: port,
        nodeId: clientNodeId,
        deviceName: clientDeviceName,
        peerNodeId: serverNodeId,
        sharedSecret: wrongSecret,
      ),
      throwsA(isA<SyncAuthenticationException>()),
    );
  });
}
