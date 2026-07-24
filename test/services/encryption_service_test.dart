import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:peadra/core/services/encryption_service.dart';

void main() {
  group('EncryptionService', () {
    group('generateSalt', () {
      test('returns 32 bytes', () {
        final salt = EncryptionService.generateSalt();
        expect(salt.length, 32);
      });

      test('produces different salts each call', () {
        final salt1 = EncryptionService.generateSalt();
        final salt2 = EncryptionService.generateSalt();
        expect(salt1, isNot(equals(salt2)));
      });

      test('returns valid Uint8List', () {
        final salt = EncryptionService.generateSalt();
        expect(salt, isA<Uint8List>());
        for (final byte in salt) {
          expect(byte, inInclusiveRange(0, 255));
        }
      });
    });

    group('deriveKey', () {
      test('produces consistent key from same password and salt', () async {
        final salt = Uint8List.fromList(List<int>.generate(32, (i) => i));
        final key1 = await EncryptionService.deriveKey('password', salt);
        final key2 = await EncryptionService.deriveKey('password', salt);

        final bytes1 = await key1.extractBytes();
        final bytes2 = await key2.extractBytes();
        expect(bytes1, equals(bytes2));
      });

      test('produces different key with different password', () async {
        final salt = Uint8List.fromList(List<int>.generate(32, (i) => i));
        final key1 = await EncryptionService.deriveKey('password1', salt);
        final key2 = await EncryptionService.deriveKey('password2', salt);

        final bytes1 = await key1.extractBytes();
        final bytes2 = await key2.extractBytes();
        expect(bytes1, isNot(equals(bytes2)));
      });

      test('produces different key with different salt', () async {
        final salt1 = Uint8List.fromList(List<int>.generate(32, (i) => i));
        final salt2 = Uint8List.fromList(List<int>.generate(32, (i) => i + 32));
        final key1 = await EncryptionService.deriveKey('password', salt1);
        final key2 = await EncryptionService.deriveKey('password', salt2);

        final bytes1 = await key1.extractBytes();
        final bytes2 = await key2.extractBytes();
        expect(bytes1, isNot(equals(bytes2)));
      });

      test('produces 32-byte key', () async {
        final salt = Uint8List.fromList(List<int>.generate(32, (i) => i));
        final key = await EncryptionService.deriveKey('password', salt);
        final bytes = await key.extractBytes();
        expect(bytes.length, 32);
      });
    });

    group('encrypt/decrypt round-trip', () {
      late SecretKey key;

      setUp(() async {
        key = await EncryptionService.deriveKey(
          'test_password',
          Uint8List.fromList(List<int>.generate(32, (i) => i)),
        );
      });

      test('round-trip works for simple string', () async {
        final plaintext = 'Hello, World!';
        final encrypted = await EncryptionService.encrypt(plaintext, key);
        final decrypted = await EncryptionService.decrypt(encrypted, key);
        expect(decrypted, equals(plaintext));
      });

      test('round-trip works for empty string', () async {
        final plaintext = '';
        final encrypted = await EncryptionService.encrypt(plaintext, key);
        final decrypted = await EncryptionService.decrypt(encrypted, key);
        expect(decrypted, equals(plaintext));
      });

      test('round-trip works for unicode string', () async {
        final plaintext = 'Café résumé 日本語 🎉 €100.00';
        final encrypted = await EncryptionService.encrypt(plaintext, key);
        final decrypted = await EncryptionService.decrypt(encrypted, key);
        expect(decrypted, equals(plaintext));
      });

      test('round-trip works for large string', () async {
        final plaintext = 'A' * 10000;
        final encrypted = await EncryptionService.encrypt(plaintext, key);
        final decrypted = await EncryptionService.decrypt(encrypted, key);
        expect(decrypted, equals(plaintext));
      });

      test('round-trip works for numeric string (amount)', () async {
        final plaintext = '12345.67';
        final encrypted = await EncryptionService.encrypt(plaintext, key);
        final decrypted = await EncryptionService.decrypt(encrypted, key);
        expect(decrypted, equals(plaintext));
        expect(double.parse(decrypted), equals(12345.67));
      });

      test('round-trip works for special characters', () async {
        final plaintext = "Test with 'quotes' and \"double quotes\" and \\backslash";
        final encrypted = await EncryptionService.encrypt(plaintext, key);
        final decrypted = await EncryptionService.decrypt(encrypted, key);
        expect(decrypted, equals(plaintext));
      });

      test('encrypted output is valid base64', () async {
        final encrypted = await EncryptionService.encrypt('test', key);
        expect(() => base64Decode(encrypted), returnsNormally);
      });

      test('encrypted output is not the same as plaintext', () async {
        final plaintext = 'sensitive_data_12345';
        final encrypted = await EncryptionService.encrypt(plaintext, key);
        expect(encrypted, isNot(equals(plaintext)));
        expect(encrypted.length, greaterThan(plaintext.length));
      });
    });

    group('encrypt semantic security', () {
      late SecretKey key;

      setUp(() async {
        key = await EncryptionService.deriveKey(
          'test_password',
          Uint8List.fromList(List<int>.generate(32, (i) => i)),
        );
      });

      test('encrypt produces different ciphertexts each time (random nonce)', () async {
        final plaintext = 'same input';
        final encrypted1 = await EncryptionService.encrypt(plaintext, key);
        final encrypted2 = await EncryptionService.encrypt(plaintext, key);
        expect(encrypted1, isNot(equals(encrypted2)));
      });

      test('different ciphertexts decrypt to same plaintext', () async {
        final plaintext = 'same input';
        final encrypted1 = await EncryptionService.encrypt(plaintext, key);
        final encrypted2 = await EncryptionService.encrypt(plaintext, key);

        final decrypted1 = await EncryptionService.decrypt(encrypted1, key);
        final decrypted2 = await EncryptionService.decrypt(encrypted2, key);

        expect(decrypted1, equals(plaintext));
        expect(decrypted2, equals(plaintext));
      });
    });

    group('decrypt error cases', () {
      test('throws with wrong key', () async {
        final key1 = await EncryptionService.deriveKey(
          'password1',
          Uint8List.fromList(List<int>.generate(32, (i) => i)),
        );
        final key2 = await EncryptionService.deriveKey(
          'password2',
          Uint8List.fromList(List<int>.generate(32, (i) => i)),
        );

        final encrypted = await EncryptionService.encrypt('secret', key1);
        expect(
          () => EncryptionService.decrypt(encrypted, key2),
          throwsA(isA<Exception>()),
        );
      });

      test('throws with corrupted ciphertext', () async {
        final key = await EncryptionService.deriveKey(
          'password',
          Uint8List.fromList(List<int>.generate(32, (i) => i)),
        );
        final encrypted = await EncryptionService.encrypt('secret', key);
        // Corrupt the base64 string
        final corrupted = '${encrypted.substring(0, encrypted.length - 2)}XX';
        expect(
          () => EncryptionService.decrypt(corrupted, key),
          throwsA(isA<Exception>()),
        );
      });

      test('throws with truncated ciphertext', () async {
        final key = await EncryptionService.deriveKey(
          'password',
          Uint8List.fromList(List<int>.generate(32, (i) => i)),
        );
        final encrypted = await EncryptionService.encrypt('secret', key);
        final truncated = encrypted.substring(0, 20);
        expect(
          () => EncryptionService.decrypt(truncated, key),
          throwsA(anything),
        );
      });
    });
  });
}
