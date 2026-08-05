import '../storage/crdt_database_service.dart';

/// The outcome of a user identity reconciliation: zero or more local user
/// ids that must be repointed to the canonical id.
class UserReconciliationPlan {
  const UserReconciliationPlan({required this.remaps});

  final List<UserIdRemap> remaps;

  bool get isEmpty => remaps.isEmpty;
}

/// Pure decision logic for reconciling the `users` table across devices.
///
/// Both devices exchange their `(username -> user uuid)` map. Whenever the
/// same username exists on both sides with different ids, a canonical id is
/// picked; the device that runs [plan] with [preferRemote] rewrites its own
/// references to match the peer (this is the pairing *scanner* — the device
/// that scanned the QR keeps the other device's ids).
class UserReconciliation {
  /// Computes the remap plan for the local device.
  ///
  /// When [preferRemote] is true (scanner side), the peer's id wins for every
  /// conflicting username. Otherwise the lexicographically smaller id wins,
  /// which keeps the decision deterministic when both sides apply the plan —
  /// in practice only the scanner side applies it.
  static UserReconciliationPlan plan({
    required Map<String, String> localUsers,
    required Map<String, String> remoteUsers,
    bool preferRemote = true,
  }) {
    final remaps = <UserIdRemap>[];
    for (final entry in localUsers.entries) {
      final remoteId = remoteUsers[entry.key];
      if (remoteId == null || remoteId == entry.value) {
        continue;
      }
      final canonical = preferRemote
          ? remoteId
          : (entry.value.compareTo(remoteId) <= 0 ? entry.value : remoteId);
      if (entry.value != canonical) {
        remaps.add(
          UserIdRemap(localUserId: entry.value, canonicalUserId: canonical),
        );
      }
    }
    return UserReconciliationPlan(remaps: remaps);
  }
}
