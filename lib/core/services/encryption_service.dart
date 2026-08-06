import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' hide Hmac;
import 'package:cryptography/cryptography.dart';

class EncryptionService {
  static const int _pbkdf2Iterations = 100000;
  static const int _saltLength = 32;
  static const int _keyLength = 32;

  static final SecretKey _algorithmKey = SecretKey([]);

  /// Generate a random salt for key derivation.
  static Uint8List generateSalt() {
    final random = Random();
    return Uint8List.fromList(
      List<int>.generate(_saltLength, (_) => random.nextInt(256)),
    );
  }

  /// Deterministic per-account salt derived from the account's username, so the
  /// same account derives the same key on every device without needing the salt
  /// to be synced first.
  static Uint8List saltForUsername(String username) {
    return Uint8List.fromList(
      sha256.convert(utf8.encode(username)).bytes,
    );
  }

  /// Derives the account's encryption key from its password and username.
  static Future<SecretKey> deriveKeyForUser(
    String password,
    String username,
  ) {
    return deriveKey(password, saltForUsername(username));
  }

  /// Derive an encryption key from a password and salt using PBKDF2.
  static Future<SecretKey> deriveKey(String password, Uint8List salt) async {
    final pbkdf2 = Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: _pbkdf2Iterations,
      bits: _keyLength * 8,
    );
    final secretKey = await pbkdf2.deriveKey(
      secretKey: SecretKey(utf8.encode(password)),
      nonce: salt,
    );
    return secretKey;
  }

  /// Encrypt a plaintext string using AES-256-GCM.
  /// Returns a base64-encoded string containing IV + ciphertext + MAC.
  static Future<String> encrypt(String plaintext, SecretKey key) async {
    final aesGcm = AesGcm.with256bits();
    final secretBox = await aesGcm.encrypt(
      utf8.encode(plaintext),
      secretKey: key,
    );

    final combined = Uint8List.fromList([
      ...secretBox.nonce,
      ...secretBox.cipherText,
      ...secretBox.mac.bytes,
    ]);
    return base64Encode(combined);
  }

  /// Decrypt a base64-encoded string using AES-256-GCM.
  static Future<String> decrypt(String ciphertext, SecretKey key) async {
    final aesGcm = AesGcm.with256bits();
    final combined = base64Decode(ciphertext);

    const nonceLength = 12;
    const macLength = 16;

    final nonce = combined.sublist(0, nonceLength);
    final mac = combined.sublist(combined.length - macLength);
    final cipherText = combined.sublist(nonceLength, combined.length - macLength);

    final secretBox = SecretBox(
      cipherText,
      nonce: nonce,
      mac: Mac(mac),
    );

    final decrypted = await aesGcm.decrypt(secretBox, secretKey: key);
    return utf8.decode(decrypted);
  }
}
