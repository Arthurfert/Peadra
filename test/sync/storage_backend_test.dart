import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:peadra/sync/storage/storage_backend.dart';

/// A [FlutterSecureStorage] whose reads fail like the Android Keystore does
/// when its key is lost (BAD_DECRYPT), or with a transient error.
class FailingSecureStorage extends FlutterSecureStorage {
  FailingSecureStorage({this.readFailure});

  final PlatformException? readFailure;
  final List<String> deletedKeys = [];

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (readFailure != null) throw readFailure!;
    return null;
  }

  @override
  Future<void> delete({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    deletedKeys.add(key);
  }
}

PlatformException badDecrypt() => PlatformException(
      code: 'Exception encountered',
      message: 'read',
      details:
          'javax.crypto.BadPaddingException: error:1e000065:Cipher functions:OPENSSL_internal:BAD_DECRYPT',
    );

void main() {
  test('undecryptable entry is deleted and reads as null', () async {
    final fake = FailingSecureStorage(readFailure: badDecrypt());
    final backend = SecureStorageBackend(storage: fake);

    expect(await backend.read('sync_trusted_peers'), isNull);
    expect(fake.deletedKeys, ['sync_trusted_peers']);
    expect(backend.consumeRecoveryFlag(), isTrue);
    expect(backend.consumeRecoveryFlag(), isFalse);
  });

  test('transient failures are rethrown untouched', () async {
    final fake = FailingSecureStorage(
      readFailure: PlatformException(code: 'error', message: 'locked'),
    );
    final backend = SecureStorageBackend(storage: fake);

    await expectLater(
      backend.read('sync_trusted_peers'),
      throwsA(isA<PlatformException>()),
    );
    expect(fake.deletedKeys, isEmpty);
    expect(backend.consumeRecoveryFlag(), isFalse);
  });

  test('healthy reads pass through', () async {
    final backend = SecureStorageBackend(storage: FailingSecureStorage());
    expect(await backend.read('missing'), isNull);
    expect(backend.consumeRecoveryFlag(), isFalse);
  });
}
