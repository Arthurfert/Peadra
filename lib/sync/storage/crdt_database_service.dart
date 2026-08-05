import 'package:sqlite_crdt/sqlite_crdt.dart';

/// Tables exchanged between devices. `settings` and `encryption_meta` stay
/// local-only.
const List<String> syncTables = [
  'users',
  'accounts',
  'descriptions',
  'tags',
  'transactions',
  'recurring_transactions',
  'recurring_exceptions',
  'imported_files',
  'exchange_rates',
];

/// A user identity remap produced by reconciliation: every reference to
/// [localUserId] is repointed to [canonicalUserId] and the superseded row's
/// primary key is rewritten.
class UserIdRemap {
  const UserIdRemap({required this.localUserId, required this.canonicalUserId});

  final String localUserId;
  final String canonicalUserId;
}

/// Sync-facing wrapper over the CRDT [SqliteCrdt].
///
/// Exposes the two primitives the sync layer needs — changeset extraction and
/// merge — plus identity reconciliation helpers. Remote merges bump
/// [lastAppliedHlc] so local change watchers can ignore echo events produced
/// by applying the peer's data.
class CrdtDatabaseService {
  CrdtDatabaseService(this._crdt);

  final SqliteCrdt _crdt;

  /// The most recent HLC written by a remote merge; null before the first one.
  Hlc? lastAppliedHlc;

  Future<CrdtChangeset> getChangeset({Hlc? since}) => _crdt.getChangeset(
        onlyTables: syncTables,
        modifiedAfter: since,
      );

  /// Applies a changeset received from a peer (wire format: `hlc` as a raw
  /// TEXT string). Parses the timestamps before merging.
  Future<void> applyChangeset(Map<String, dynamic> changeset) async {
    final parsed = parseCrdtChangeset(changeset);
    if (parsed.recordCount == 0) {
      return;
    }
    await _crdt.merge(parsed);
    lastAppliedHlc = await _crdt.getLastModified();
  }

  Future<Hlc> lastModifiedHlc() => _crdt.getLastModified();

  /// Emits local dataset changes (tables + the HLC they were written at).
  Stream<({Hlc hlc, Iterable<String> tables})> get onTablesChanged =>
      _crdt.onTablesChanged;

  /// Whether a change event at [hlc] originated from a local write rather
  /// than a remote merge (used to skip scheduling syncs for our own applies).
  bool isSyncSelfChange({required Hlc hlc}) =>
      lastAppliedHlc == null || hlc > lastAppliedHlc!;

  /// The (username -> user uuid) map used for identity reconciliation.
  Future<Map<String, String>> getUserIdentityMap() async {
    final rows = await _crdt.query(
      'SELECT username, id FROM users WHERE is_deleted = 0',
    );
    return {for (final row in rows) row['username'] as String: row['id'] as String};
  }

  /// Applies a user-id remap plan: repoints every child table's `user_id`
  /// column to the canonical id, then rewrites the superseded user row's
  /// primary key. Rewriting the key (rather than tombstoning) keeps the
  /// `UNIQUE(username)` constraint satisfied when the canonical row merges in
  /// from the peer.
  Future<void> applyUserReconciliation(List<UserIdRemap> remaps) async {
    if (remaps.isEmpty) {
      return;
    }
    await _crdt.transaction((txn) async {
      for (final remap in remaps) {
        for (final table in const [
          'accounts',
          'descriptions',
          'tags',
          'transactions',
          'recurring_transactions',
          'imported_files',
          'settings',
        ]) {
          await txn.execute(
            'UPDATE $table SET user_id = ? WHERE user_id = ?',
            [remap.canonicalUserId, remap.localUserId],
          );
        }
        await txn.execute(
          'UPDATE users SET id = ? WHERE id = ?',
          [remap.canonicalUserId, remap.localUserId],
        );
      }
    });
  }
}
