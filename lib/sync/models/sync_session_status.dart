/// Progress of a pairing/sync session this device participates in, emitted on
/// [SyncManager.onSyncStatus] so the UI can show what is happening (both on the
/// scanner side and on the device displaying the pairing QR code).
enum SyncSessionStatus {
  /// The session socket is being established with the peer.
  connecting,

  /// The encryption keys are being exchanged over the authenticated channel.
  exchangingKeys,

  /// User identities are being reconciled across both devices.
  reconcilingUsers,

  /// The initial full data exchange is running.
  syncing,

  /// The session finished successfully and the peer is trusted.
  completed,

  /// The session failed; pairing/sync should be retried.
  failed,
}
