import 'package:cryptography/cryptography.dart';

import '../../../core/services/encryption_service.dart';

/// Per-table columns that are field-encrypted on the wire as base64 AES-256-GCM
/// ciphertext. Every other column (ids, dates, enums, numeric rate fields, ...)
/// travels in plaintext and must not be re-keyed.
const Map<String, Set<String>> encryptedFieldsByTable = {
  'accounts': {'name', 'starting_amount'},
  'descriptions': {'name'},
  'transactions': {'amount', 'notes'},
  'recurring_transactions': {'amount', 'notes'},
};

/// Re-keys an inbound changeset from the peer's encryption key to the local
/// one so that locally stored rows are always readable with the local key.
///
/// Each encrypted field is decrypted with [peerKey] and re-encrypted with
/// [localKey] when the peer is encrypted. When the peer is unencrypted
/// ([peerKey] is null) plaintext fields are encrypted with [localKey] instead,
/// and values already encrypted with [localKey] are left untouched. A null
/// [localKey] stores the decrypted plaintext as-is.
///
/// Returns a new changeset map; the input is never mutated.
Future<Map<String, dynamic>> rekeyInboundChangeset(
  Map<String, dynamic> changeset, {
  required SecretKey? localKey,
  required SecretKey? peerKey,
}) async {
  if (localKey == null && peerKey == null) {
    return changeset;
  }
  final result = <String, dynamic>{};
  for (final entry in changeset.entries) {
    final rows = entry.value;
    if (rows is! List) {
      result[entry.key] = rows;
      continue;
    }
    final fields = encryptedFieldsByTable[entry.key];
    if (fields == null) {
      result[entry.key] = rows;
      continue;
    }
    result[entry.key] = await Future.wait(rows.map((dynamic row) async {
      final record = row is Map
          ? Map<String, dynamic>.from(row)
          : <String, dynamic>{};
      for (final field in fields) {
        final value = record[field];
        if (value == null) {
          continue;
        }
        record[field] = await _rekeyValue(
          value,
          localKey: localKey,
          peerKey: peerKey,
        );
      }
      return record;
    }));
  }
  return result;
}

Future<dynamic> _rekeyValue(
  dynamic value, {
  required SecretKey? localKey,
  required SecretKey? peerKey,
}) async {
  if (value is! String) {
    // Numeric field (amount / starting_amount) sent by an unencrypted peer:
    // plaintext number, encrypt it when we keep an encrypted database.
    if (peerKey == null && localKey != null) {
      return _encrypt(value.toString(), localKey);
    }
    return value;
  }

  if (peerKey != null) {
    // Encrypted peer: re-key only what the peer actually encrypted. Anything
    // else (plaintext or already local-encrypted) is left untouched.
    final plaintext = await _tryDecrypt(value, peerKey);
    if (plaintext == null) {
      return value;
    }
    return localKey == null ? plaintext : _encrypt(plaintext, localKey);
  }

  if (localKey != null) {
    // Unencrypted peer, encrypted local DB: encrypt plaintext fields, but
    // never double-encrypt values we already hold under the local key.
    final alreadyLocal = await _tryDecrypt(value, localKey);
    if (alreadyLocal != null) {
      return value;
    }
    return _encrypt(value, localKey);
  }

  return value;
}

Future<String?> _tryDecrypt(String ciphertext, SecretKey key) async {
  try {
    return await EncryptionService.decrypt(ciphertext, key);
  } catch (_) {
    return null;
  }
}

Future<String> _encrypt(String plaintext, SecretKey key) async {
  try {
    return await EncryptionService.encrypt(plaintext, key);
  } catch (_) {
    return plaintext;
  }
}
