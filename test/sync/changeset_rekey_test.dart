import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:peadra/core/services/encryption_service.dart';
import 'package:peadra/sync/security/changeset_rekey.dart';

void main() {
  final peerKey = SecretKey(List<int>.filled(32, 1));
  final localKey = SecretKey(List<int>.filled(32, 2));

  Future<String> enc(String plaintext, SecretKey key) =>
      EncryptionService.encrypt(plaintext, key);

  Future<String?> dec(String ciphertext, SecretKey key) async {
    try {
      return await EncryptionService.decrypt(ciphertext, key);
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic> changesetWith(Map<String, dynamic> account) => {
        'accounts': [
          {
            'id': 'acct-1',
            'user_id': 'user-1',
            'name': 'My account',
            'starting_amount': 42.5,
            'hlc': '2026-01-01T00:00:00.000Z-0000-00000000-0000-0000-0000-000000000000',
            ...account,
          }
        ],
      };

  test('re-keys peer-encrypted fields to the local key', () async {
    final changeset = changesetWith({
      'name': await enc('Groceries', peerKey),
      'starting_amount': await enc('42.5', peerKey),
    });

    final rekeyed = await rekeyInboundChangeset(
      changeset,
      localKey: localKey,
      peerKey: peerKey,
    );

    final row = (rekeyed['accounts'] as List).single as Map<String, dynamic>;
    expect(await dec(row['name'] as String, localKey), 'Groceries');
    expect(await dec(row['starting_amount'] as String, localKey), '42.5');
    // Plain columns are untouched.
    expect(row['id'], 'acct-1');
    expect(row['user_id'], 'user-1');
    expect(row['hlc'], isA<String>());
  });

  test('stores plaintext when there is no local key', () async {
    final changeset = changesetWith({
      'name': await enc('Groceries', peerKey),
      'starting_amount': await enc('42.5', peerKey),
    });

    final rekeyed = await rekeyInboundChangeset(
      changeset,
      localKey: null,
      peerKey: peerKey,
    );

    final row = (rekeyed['accounts'] as List).single as Map<String, dynamic>;
    expect(row['name'], 'Groceries');
    expect(row['starting_amount'], '42.5');
  });

  test('encrypts plaintext from an unencrypted peer', () async {
    final rekeyed = await rekeyInboundChangeset(
      changesetWith({
        'name': 'Groceries',
        'starting_amount': 42.5,
      }),
      localKey: localKey,
      peerKey: null,
    );

    final row = (rekeyed['accounts'] as List).single as Map<String, dynamic>;
    expect(await dec(row['name'] as String, localKey), 'Groceries');
    expect(await dec(row['starting_amount'] as String, localKey), '42.5');
  });

  test('leaves everything untouched when both sides are unencrypted', () async {
    final changeset = changesetWith({'name': 'Groceries'});
    final rekeyed = await rekeyInboundChangeset(
      changeset,
      localKey: null,
      peerKey: null,
    );
    expect(rekeyed, same(changeset));
  });

  test('does not re-encrypt values already held under the local key', () async {
    final alreadyLocal = await enc('Groceries', localKey);
    final rekeyed = await rekeyInboundChangeset(
      changesetWith({'name': alreadyLocal}),
      localKey: localKey,
      peerKey: null,
    );
    final row = (rekeyed['accounts'] as List).single as Map<String, dynamic>;
    expect(row['name'], alreadyLocal);
  });

  test('leaves non-peer-encrypted values untouched when the peer is encrypted',
      () async {
    final changeset = changesetWith({
      'name': 'Already plaintext',
      // A value encrypted under the local key (our own echo) must not be
      // re-encrypted with the peer key.
      'starting_amount': await enc('42.5', localKey),
    });
    final rekeyed = await rekeyInboundChangeset(
      changeset,
      localKey: localKey,
      peerKey: peerKey,
    );
    final row = (rekeyed['accounts'] as List).single as Map<String, dynamic>;
    expect(row['name'], 'Already plaintext');
    expect(await dec(row['starting_amount'] as String, localKey), '42.5');
  });

  test('only touches tables that carry encrypted fields', () async {
    final changeset = {
      'users': [
        {
          'id': 'user-1',
          'username': 'alice',
          'password_hash': 'hash',
          'hlc': '2026-01-01T00:00:00.000Z-0000-00000000-0000-0000-0000-000000000000',
        }
      ],
      'exchange_rates': [
        {
          'from_currency': 'EUR',
          'to_currency': 'USD',
          'rate': 1.1,
          'hlc': '2026-01-01T00:00:00.000Z-0000-00000000-0000-0000-0000-000000000000',
        }
      ],
    };

    final rekeyed = await rekeyInboundChangeset(
      changeset,
      localKey: localKey,
      peerKey: peerKey,
    );

    expect(rekeyed['users'], same(changeset['users']));
    expect(rekeyed['exchange_rates'], same(changeset['exchange_rates']));
  });
}
