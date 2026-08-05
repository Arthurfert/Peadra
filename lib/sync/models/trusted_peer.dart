import 'package:crdt/crdt.dart';

/// A device this node has successfully paired with.
class TrustedPeer {
  /// Remote node id (UUID), advertised via mDNS and used in the handshake.
  final String peerId;

  /// Human-readable device name reported by the peer.
  final String deviceName;

  /// 256-bit shared pairing secret, base64-encoded.
  final String sharedSecret;

  /// The peer's database encryption key bytes (base64), shared at pairing.
  /// Null when the peer runs unencrypted.
  final String? dbEncryptionKey;

  /// The most recent HLC merged from this peer; used as the `since`
  /// watermark for the next sync. Null until the first sync completes.
  final Hlc? lastSyncHlc;

  /// When this peer was first paired.
  final DateTime createdAt;

  /// When this peer was last seen / successfully reached.
  final DateTime? lastSeen;

  const TrustedPeer({
    required this.peerId,
    required this.deviceName,
    required this.sharedSecret,
    this.dbEncryptionKey,
    this.lastSyncHlc,
    required this.createdAt,
    this.lastSeen,
  });

  TrustedPeer copyWith({
    String? deviceName,
    String? sharedSecret,
    String? dbEncryptionKey,
    bool clearDbEncryptionKey = false,
    Hlc? lastSyncHlc,
    DateTime? lastSeen,
  }) =>
      TrustedPeer(
        peerId: peerId,
        deviceName: deviceName ?? this.deviceName,
        sharedSecret: sharedSecret ?? this.sharedSecret,
        dbEncryptionKey: clearDbEncryptionKey
            ? null
            : (dbEncryptionKey ?? this.dbEncryptionKey),
        lastSyncHlc: lastSyncHlc ?? this.lastSyncHlc,
        createdAt: createdAt,
        lastSeen: lastSeen ?? this.lastSeen,
      );

  Map<String, dynamic> toJson() => {
        'peer_id': peerId,
        'device_name': deviceName,
        'shared_secret': sharedSecret,
        if (dbEncryptionKey != null) 'db_encryption_key': dbEncryptionKey,
        if (lastSyncHlc != null) 'last_sync_hlc': lastSyncHlc!.toString(),
        'created_at': createdAt.toUtc().toIso8601String(),
        if (lastSeen != null) 'last_seen': lastSeen!.toUtc().toIso8601String(),
      };

  factory TrustedPeer.fromJson(Map<String, dynamic> json) => TrustedPeer(
        peerId: json['peer_id'] as String,
        deviceName: json['device_name'] as String,
        sharedSecret: json['shared_secret'] as String,
        dbEncryptionKey: json['db_encryption_key'] as String?,
        lastSyncHlc: json['last_sync_hlc'] == null
            ? null
            : Hlc.parse(json['last_sync_hlc'] as String),
        createdAt: DateTime.parse(json['created_at'] as String),
        lastSeen: json['last_seen'] == null
            ? null
            : DateTime.parse(json['last_seen'] as String),
      );

  @override
  String toString() => 'TrustedPeer($deviceName, $peerId)';
}
