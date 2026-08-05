import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:uuid/uuid.dart';

/// Mutual-authentication primitives for the sync handshake.
///
/// Signatures are HMAC-SHA256 over the 256-bit pairing [sharedSecret]
/// (base64-encoded). Session keys are derived with HKDF-SHA256 from the
/// shared secret using both handshake nonces as the salt.
class AuthChallenge {
  static const int secretBytes = 32;
  static const int sessionKeyBytes = 32;
  static const String _info = 'peadra-sync-v1';

  static final Uuid _uuid = const Uuid();

  /// Generates a fresh 32-byte random pairing secret, base64-encoded.
  static String generateSharedSecret() {
    final random = Random.secure();
    final bytes = Uint8List.fromList(
      List<int>.generate(secretBytes, (_) => random.nextInt(256)),
    );
    return base64Encode(bytes);
  }

  /// Generates a random nonce for one side of the handshake.
  static String generateNonce() => _uuid.v4();

  /// HMAC-SHA256 signature of [message] under [sharedSecret], base64-encoded.
  static Future<String> sign(String sharedSecret, String message) async {
    final mac = await Hmac.sha256().calculateMac(
      utf8.encode(message),
      secretKey: SecretKey(_decodeSharedSecret(sharedSecret)),
    );
    return base64Encode(mac.bytes);
  }

  /// Constant-time verification that [signature] matches [message].
  /// Fails closed (returns false) for malformed signatures.
  static Future<bool> verify(
    String sharedSecret,
    String message,
    String signature,
  ) async {
    List<int> provided;
    try {
      provided = base64Decode(signature);
    } on FormatException {
      return false;
    }
    final mac = await Hmac.sha256().calculateMac(
      utf8.encode(message),
      secretKey: SecretKey(_decodeSharedSecret(sharedSecret)),
    );
    return _constantTimeEquals(mac.bytes, provided);
  }

  /// Derives a pair of 32-byte AES-256-GCM session keys
  /// (client->server, server->client) using HKDF-SHA256 over the shared
  /// secret, with both handshake nonces concatenated as the salt.
  static Future<(SecretKey, SecretKey)> deriveSessionKeys({
    required String sharedSecret,
    required String nonceA,
    required String nonceB,
  }) async {
    final hkdf = Hkdf(
      hmac: Hmac.sha256(),
      outputLength: sessionKeyBytes * 2,
    );
    final derived = await hkdf.deriveKey(
      secretKey: SecretKey(_decodeSharedSecret(sharedSecret)),
      nonce: utf8.encode('$nonceA$nonceB'),
      info: utf8.encode(_info),
    );
    final bytes = derived.bytes;
    return (
      SecretKey(bytes.sublist(0, sessionKeyBytes)),
      SecretKey(bytes.sublist(sessionKeyBytes)),
    );
  }

  static bool _constantTimeEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }

  /// Decodes a shared secret, accepting both standard padded base64 and the
  /// unpadded URL-safe variant used in pairing QR codes.
  static List<int> _decodeSharedSecret(String sharedSecret) {
    var encoded = sharedSecret
        .replaceAll('-', '+')
        .replaceAll('_', '/');
    while (encoded.length % 4 != 0) {
      encoded += '=';
    }
    return base64Decode(encoded);
  }
}
