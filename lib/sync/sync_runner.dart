import 'dart:convert';

import 'package:crdt/crdt.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';

import '../../core/database/database_manager.dart';
import 'network/sync_messages.dart';
import 'network/sync_session.dart';
import 'security/changeset_rekey.dart';
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
///
/// [firstRequest] lets the responder resume a sync exchange whose initial
/// SYNC_REQUEST was already consumed (e.g. after a key refresh preamble).
///
/// [peerKey] is the peer's database encryption key (from the pairing key
/// exchange or the stored [TrustedPeer]). Every inbound changeset is re-keyed
/// to the local database key before it is merged, so remotely sourced rows
/// remain decryptable locally.
Future<Hlc?> runSyncExchange({
  required SyncSession session,
  required CrdtDatabaseService db,
  required Hlc? since,
  required bool isInitiator,
  SecretKey? peerKey,
  Map<String, dynamic>? firstRequest,
}) async {
  if (isInitiator) {
    await session.send({
      'type': SyncMessageTypes.syncRequest,
      'since_hlc': since?.toString(),
    });
    debugPrint('[peadra-sync] sync: initiator sent SYNC_REQUEST since=$since');
    final inbound = await _expect(session, SyncMessageTypes.syncResponse);
    debugPrint('[peadra-sync] sync: initiator got SYNC_RESPONSE '
        '(${_countChangeset(inbound['changeset'])} records)');
    final applied = await _applyInbound(db, inbound, since, peerKey);
    debugPrint('[peadra-sync] sync: initiator applied, watermark=$applied');
    final request = await _expect(session, SyncMessageTypes.syncRequest);
    await _sendOutbound(session, db, request);
    debugPrint('[peadra-sync] sync: initiator sent SYNC_RESPONSE');
    return applied;
  } else {
    final request = firstRequest ??
        await _expect(session, SyncMessageTypes.syncRequest);
    await _sendOutbound(session, db, request);
    debugPrint('[peadra-sync] sync: responder sent SYNC_RESPONSE for '
        'since=${request['since_hlc']}');
    await session.send({
      'type': SyncMessageTypes.syncRequest,
      'since_hlc': since?.toString(),
    });
    debugPrint('[peadra-sync] sync: responder sent SYNC_REQUEST since=$since');
    final inbound = await _expect(session, SyncMessageTypes.syncResponse);
    debugPrint('[peadra-sync] sync: responder got SYNC_RESPONSE '
        '(${_countChangeset(inbound['changeset'])} records)');
    return _applyInbound(db, inbound, since, peerKey);
  }
}

int _countChangeset(dynamic changeset) {
  if (changeset is! Map<String, dynamic>) return 0;
  return changeset.values.fold<int>(
    0,
    (sum, rows) => sum + ((rows as List<dynamic>?)?.length ?? 0),
  );
}

Future<void> _sendOutbound(
  SyncSession session,
  CrdtDatabaseService db,
  Map<String, dynamic> request,
) async {
  final since = _parseSince(request['since_hlc']);
  final changeset = await db.getChangeset(since: since);
  debugPrint('[peadra-sync] sync: building outbound changeset since=$since '
      '(${_countChangeset(changeset)} records)');
  await session.send({
    'type': SyncMessageTypes.syncResponse,
    'since_hlc': request['since_hlc'],
    'changeset': changeset,
  });
}

/// Applies a received changeset and returns the new watermark for the peer.
/// An empty changeset leaves the watermark unchanged (the peer simply had
/// nothing newer), so the requesting side never over-advances its watermark.
///
/// Inbound rows are re-keyed from [peerKey] to the local database key before
/// merging so they remain decryptable with the local encryption key.
Future<Hlc?> _applyInbound(
  CrdtDatabaseService db,
  Map<String, dynamic> response,
  Hlc? previous,
  SecretKey? peerKey,
) async {
  final changeset = response['changeset'] as Map<String, dynamic>;
  if (changeset.isEmpty) {
    return previous;
  }
  final rekeyed = await rekeyInboundChangeset(
    changeset,
    localKey: DatabaseManager.instance.encryptionKey,
    peerKey: peerKey,
  );
  await db.applyChangeset(rekeyed);
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

/// Re-shares the database encryption key with an already-paired peer (e.g.
/// after a local password change re-derived the key). The initiator opens the
/// session with a `KEY_REFRESH` preamble so the responder knows to run the key
/// exchange before the ordinary sync. Returns the peer's current key (base64).
///
/// A separate sync exchange is expected to follow in the same session; callers
/// run [runSyncExchange] afterwards.
Future<String?> runKeyRefresh({
  required SyncSession session,
  required List<int>? localKey,
  required bool isInitiator,
}) async {
  final localB64 = localKey == null ? null : base64Encode(localKey);
  if (isInitiator) {
    await session.send({'type': SyncMessageTypes.keyRefresh});
    await session.send({
      'type': SyncMessageTypes.keyExchange,
      'key_b64': localB64,
    });
    final ack = await _expect(session, SyncMessageTypes.keyExchangeAck);
    return ack['key_b64'] as String?;
  }
  final request = await _expect(session, SyncMessageTypes.keyExchange);
  await session.send({
    'type': SyncMessageTypes.keyExchangeAck,
    'key_b64': localB64,
  });
  return request['key_b64'] as String?;
}

/// Runs the responder side of a server session. Returns the peer's encryption
/// key when the initiator requested a key refresh (password re-share), and the
/// new watermark for the peer.
///
/// [peerKey] is the initiator's database encryption key, used to re-key the
/// inbound changeset to the local key. On a key-refresh session the freshly
/// exchanged [runKeyRefresh] key takes precedence over the (possibly stale)
/// stored [peerKey], so rows the peer re-encrypted after a password change
/// remain decryptable.
Future<({String? remoteKey, Hlc? watermark})> runServerSession({
  required SyncSession session,
  required CrdtDatabaseService db,
  required Hlc? since,
  required List<int>? localKey,
  required void Function(String? remoteKeyB64) onRemoteKey,
  SecretKey? peerKey,
}) async {
  final first = await _expectAny(session, [
    SyncMessageTypes.syncRequest,
    SyncMessageTypes.keyRefresh,
  ]);
  if (first['type'] == SyncMessageTypes.keyRefresh) {
    final remoteKey = await runKeyRefresh(
      session: session,
      localKey: localKey,
      isInitiator: false,
    );
    onRemoteKey(remoteKey);
    final watermark = await runSyncExchange(
      session: session,
      db: db,
      since: since,
      isInitiator: false,
      peerKey: _peerKeyFromB64(remoteKey) ?? peerKey,
    );
    return (remoteKey: remoteKey, watermark: watermark);
  }
  final watermark = await runSyncExchange(
    session: session,
    db: db,
    since: since,
    isInitiator: false,
    peerKey: peerKey,
    firstRequest: first,
  );
  return (remoteKey: null, watermark: watermark);
}

SecretKey? _peerKeyFromB64(String? keyB64) {
  if (keyB64 == null || keyB64.isEmpty) {
    return null;
  }
  return SecretKey(base64Decode(keyB64));
}

Future<Map<String, dynamic>> _expectAny(
  SyncSession session,
  List<String> types,
) async {
  final message = await session.receive();
  if (message == null) {
    throw SyncProtocolException(
      'Connection closed while waiting for ${types.join(' or ')}',
    );
  }
  if (message['type'] == SyncMessageTypes.error) {
    throw SyncProtocolException(
      'Peer rejected: ${message['code'] ?? 'unknown'}',
    );
  }
  if (!types.contains(message['type'])) {
    throw SyncProtocolException(
      'Expected ${types.join(' or ')}, got ${message['type']}',
    );
  }
  return message;
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
