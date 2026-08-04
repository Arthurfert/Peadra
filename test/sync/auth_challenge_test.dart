import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:peadra/sync/security/auth_challenge.dart';

void main() {
  group('AuthChallenge', () {
    group('generateSharedSecret', () {
      test('returns 32 random bytes base64-encoded', () {
        final secret = AuthChallenge.generateSharedSecret();
        expect(base64Decode(secret).length, 32);
      });

      test('produces a different secret each call', () {
        expect(
          AuthChallenge.generateSharedSecret(),
          isNot(AuthChallenge.generateSharedSecret()),
        );
      });
    });

    group('generateNonce', () {
      test('produces a different nonce each call', () {
        expect(AuthChallenge.generateNonce(), isNot(AuthChallenge.generateNonce()));
      });

      test('returns a non-empty value', () {
        expect(AuthChallenge.generateNonce(), isNotEmpty);
      });
    });

    group('sign/verify', () {
      test('verifies a signature produced for the same message', () async {
        final secret = AuthChallenge.generateSharedSecret();
        final sig = await AuthChallenge.sign(secret, 'hello');
        expect(await AuthChallenge.verify(secret, 'hello', sig), isTrue);
      });

      test('signatures are deterministic', () async {
        final secret = AuthChallenge.generateSharedSecret();
        expect(
          await AuthChallenge.sign(secret, 'message'),
          await AuthChallenge.sign(secret, 'message'),
        );
      });

      test('rejects a tampered message', () async {
        final secret = AuthChallenge.generateSharedSecret();
        final sig = await AuthChallenge.sign(secret, 'hello');
        expect(await AuthChallenge.verify(secret, 'hell0', sig), isFalse);
      });

      test('rejects a signature from a different secret', () async {
        final secret = AuthChallenge.generateSharedSecret();
        final sig = await AuthChallenge.sign(
          AuthChallenge.generateSharedSecret(),
          'hello',
        );
        expect(await AuthChallenge.verify(secret, 'hello', sig), isFalse);
      });

      test('rejects a malformed signature', () async {
        final secret = AuthChallenge.generateSharedSecret();
        expect(await AuthChallenge.verify(secret, 'hello', 'not-base64!'), isFalse);
      });
    });

    group('deriveSessionKeys', () {
      test('returns two 32-byte keys', () async {
        final secret = AuthChallenge.generateSharedSecret();
        final (keyA, keyB) = await AuthChallenge.deriveSessionKeys(
          sharedSecret: secret,
          nonceA: 'nonce-a',
          nonceB: 'nonce-b',
        );
        expect((await keyA.extractBytes()).length, 32);
        expect((await keyB.extractBytes()).length, 32);
      });

      test('is deterministic for the same inputs', () async {
        final secret = AuthChallenge.generateSharedSecret();
        final (a1, b1) = await AuthChallenge.deriveSessionKeys(
          sharedSecret: secret,
          nonceA: 'nonce-a',
          nonceB: 'nonce-b',
        );
        final (a2, b2) = await AuthChallenge.deriveSessionKeys(
          sharedSecret: secret,
          nonceA: 'nonce-a',
          nonceB: 'nonce-b',
        );
        expect(await a1.extractBytes(), await a2.extractBytes());
        expect(await b1.extractBytes(), await b2.extractBytes());
      });

      test('changes when a nonce changes', () async {
        final secret = AuthChallenge.generateSharedSecret();
        final (a1, _) = await AuthChallenge.deriveSessionKeys(
          sharedSecret: secret,
          nonceA: 'nonce-a',
          nonceB: 'nonce-b',
        );
        final (a2, _) = await AuthChallenge.deriveSessionKeys(
          sharedSecret: secret,
          nonceA: 'nonce-a',
          nonceB: 'nonce-c',
        );
        expect(await a1.extractBytes(), isNot(await a2.extractBytes()));
      });

      test('differs from the raw shared secret', () async {
        final secret = AuthChallenge.generateSharedSecret();
        final (key, _) = await AuthChallenge.deriveSessionKeys(
          sharedSecret: secret,
          nonceA: 'nonce-a',
          nonceB: 'nonce-b',
        );
        expect(await key.extractBytes(), isNot(base64Decode(secret)));
      });
    });
  });
}
