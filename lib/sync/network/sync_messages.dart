/// Message type identifiers used on the sync wire.
abstract final class SyncMessageTypes {
  static const String hello = 'HELLO';
  static const String challengeA = 'CHALLENGE_A';
  static const String responseA = 'RESPONSE_A';
  static const String responseB = 'RESPONSE_B';
  static const String ok = 'OK';
  static const String syncRequest = 'SYNC_REQUEST';
  static const String syncResponse = 'SYNC_RESPONSE';
  static const String userReconcile = 'USER_RECONCILE';
  static const String userReconcileResponse = 'USER_RECONCILE_RESPONSE';
  static const String keyExchange = 'KEY_EXCHANGE';
  static const String keyExchangeAck = 'KEY_EXCHANGE_ACK';
  static const String keyRefresh = 'KEY_REFRESH';
  static const String error = 'ERROR';
  static const String close = 'CLOSE';
}

/// Thrown on malformed framing, unexpected messages or protocol violations.
class SyncProtocolException implements Exception {
  SyncProtocolException(this.message);

  final String message;

  @override
  String toString() => 'SyncProtocolException: $message';
}

/// Thrown when an HMAC proof or a message MAC fails to verify.
class SyncAuthenticationException implements Exception {
  SyncAuthenticationException(this.message);

  final String message;

  @override
  String toString() => 'SyncAuthenticationException: $message';
}
