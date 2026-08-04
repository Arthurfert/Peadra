import 'dart:convert';

import 'package:crdt/crdt.dart';

import 'network/sync_messages.dart';
import 'network/sync_session.dart';
import 'security/user_reconciliation.dart';
import 'storage/crdt_database_service.dart';

/// Runs one bidirectional sync exchange over an authenticated [SyncSession].
///
/// A single session performs two half-exchanges so both devices push and pull:
///   initiator -> responder: SYNC_REQUEST(since) / SYNC_RESPONSE(changeset)
///   responder -> initiator: SYNC_REQUEST(since) / SYNC_RESPONSE(changeset)
/// Each side applies the changeset it receives and returns the new watermark
/// HLC for the peer (the `since` value to use on the next sync), or null when
/// the peer is empty and nothing has been applied yet.
Future<Hlc?> runSyncExchange({
  required SyncSession session,
  required CrdtDatabaseService db,
  required Hlc? since,
  required bool isInitiator,
}) async {
  if (isInitiator) {
    await session.send({
      'type': SyncMessageTypes.syncRequest,
      'since_hlc': since?.toString(),
    });
    final inbound = await _expect(session, SyncMessageTypes.syncResponse);
    final applied = await _applyInbound(db, inbound, since);
    final request = await _expect(session, SyncMessageTypes.syncRequest);
    await _sendOutbound(session, db, request);
    return applied;
  } else {
    final request = await _expect(session, SyncMessageTypes.syncRequest);
    await _sendOutbound(session, db, request);
    await session.send({
      'type': SyncMessageTypes.syncRequest,
      'since_hlc': since?.toString(),
    });
    final inbound = await _expect(session, SyncMessageTypes.syncResponse);
    return _applyInbound(db, inbound, since);
  }
}

Future<void> _sendOutbound(
  SyncSession session,
  CrdtDatabaseService db,
  Map<String, dynamic> request,
) async {
  final since = _parseSince(request['since_hlc']);
  final changeset = await db.getChangeset(since: since);
  await session.send({
    'type': SyncMessageTypes.syncResponse,
    'since_hlc': request['since_hlc'],
    'changeset': changeset,
  });
}

/// Applies a received changeset and returns the new watermark for the peer.
/// An empty changeset leaves the watermark unchanged (the peer simply had
/// nothing newer), so the requesting side never over-advances its watermark.
Future<Hlc?> _applyInbound(
  CrdtDatabaseService db,
  Map<String, dynamic> response,
  Hlc? previous,
) async {
  final changeset = response['changeset'] as Map<String, dynamic>;
  if (changeset.isEmpty) {
    return previous;
  }
  await db.applyChangeset(changeset);
  return db.lastModifiedHlc();
}

Hlc? _parseSince(dynamic value) =>
    value == null ? null : Hlc.parse(value as String);

/// Exchanges `(username -> user uuid)` maps. Only the initiator (the pairing
/// scanner) applies the resulting remap plan; the responder participates so
/// both sides agree on the same canonical ids.
Future<void> runUserReconciliation({
  required SyncSession session,
  required CrdtDatabaseService db,
  required bool isInitiator,
}) async {
  final local = await db.getUserIdentityMap();
  if (isInitiator) {
    await session.send({
      'type': SyncMessageTypes.userReconcile,
      'users': local,
    });
    final response = await _expect(
      session,
      SyncMessageTypes.userReconcileResponse,
    );
    final remote = (response['users'] as Map<String, dynamic>)
        .map((k, v) => MapEntry(k, v as String));
    final plan = UserReconciliation.plan(
      localUsers: local,
      remoteUsers: remote,
      preferRemote: true,
    );
    if (!plan.isEmpty) {
      await db.applyUserReconciliation(plan.remaps);
    }
  } else {
    await _expect(session, SyncMessageTypes.userReconcile);
    await session.send({
      'type': SyncMessageTypes.userReconcileResponse,
      'users': local,
    });
  }
}

/// Exchanges database encryption keys. The initiator sends its key first and
/// the responder replies with its own; each side hands the peer's key to
/// [onRemoteKey] (base64). A null key means that side is unencrypted.
Future<void> runEncryptionKeyExchange({
  required SyncSession session,
  required List<int>? localKey,
  required void Function(String? remoteKeyB64) onRemoteKey,
  required bool isInitiator,
}) async {
  final localB64 = localKey == null ? null : base64Encode(localKey);
  if (isInitiator) {
    await session.send({
      'type': SyncMessageTypes.keyExchange,
      'key_b64': localB64,
    });
    final ack = await _expect(session, SyncMessageTypes.keyExchangeAck);
    onRemoteKey(ack['key_b64'] as String?);
  } else {
    final request = await _expect(session, SyncMessageTypes.keyExchange);
    onRemoteKey(request['key_b64'] as String?);
    await session.send({
      'type': SyncMessageTypes.keyExchangeAck,
      'key_b64': localB64,
    });
  }
}

Future<Map<String, dynamic>> _expect(
  SyncSession session,
  String type,
) async {
  final message = await session.receive();
  if (message == null) {
    throw SyncProtocolException('Connection closed while waiting for $type');
  }
  if (message['type'] == SyncMessageTypes.error) {
    throw SyncProtocolException(
      'Peer rejected: ${message['code'] ?? 'unknown'}',
    );
  }
  if (message['type'] != type) {
    throw SyncProtocolException('Expected $type, got ${message['type']}');
  }
  return message;
}
