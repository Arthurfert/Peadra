# Peadra P2P Synchronization — Implementation Plan

## Scope & agreed decisions

| Decision | Choice |
|---|---|
| Data layer | **Full `sqlite_crdt` adoption** — UUID TEXT PKs, HLC, tombstones, `getChangeset`/`merge` |
| Encryption | **Share the DB encryption key at pairing** over the authenticated session |
| Discovery | **`mdns_dart`** (pure Dart, Linux/Windows/Android/iOS/macOS, discover + advertise) |
| Transport | **Plain TCP + HMAC challenge + HKDF session keys + AES-GCM** (no TLS/PKI) |
| Sync scope | **All user data tables** (users, accounts, descriptions, tags, transactions, recurring_transactions, recurring_exceptions, imported_files, exchange_rates); exclude `settings` + `encryption_meta` |

Target flows: **mobile ↔ desktop** and **mobile ↔ mobile**, automatic re-sync after one manual QR pairing.

---

## 1. New dependencies (`pubspec.yaml`)

- `sqlite_crdt` ^2.x — CRDT layer on top of existing sqflite stack
- `sqlite3_flutter_libs` ^0.5.x — bundled recent SQLite for mobile
- `crdt` ^5.x — direct use of `Hlc` for serialization (transitive via sql_crdt)
- `uuid` ^4.x — v4 row/node IDs
- `mdns_dart` ^2.x — mDNS browse + advertise
- `qr_flutter` — render pairing QR
- `mobile_scanner` — scan pairing QR (Android/iOS/macOS/Windows/Linux)
- `flutter_secure_storage` ^9.x, `cryptography` ^2.x, `dart:io` — already present

## 2. Phase 0 — CRDT data migration (`lib/core/database`)

**Schema v7** (in `database_manager.dart`): every table gets the 3 auto columns from sql_crdt (`is_deleted`, `hlc`, `modified`) plus `TEXT PRIMARY KEY` UUIDs:
- `users`, `accounts`, `descriptions`, `tags`, `transactions`, `recurring_transactions`, `recurring_exceptions`, `imported_files` → `id TEXT PRIMARY KEY`
- All FK columns (`user_id`, `account_id`, `description_id`, `tag_id`, `recurring_id`) → `TEXT` referencing UUID PKs
- `exchange_rates` → composite PK `(from_currency, to_currency)` stays (valid CRDT key)
- `settings`, `encryption_meta` → local-only, PKs unchanged, excluded via `onlyTables` in `getChangeset`

**Migration path v6→v7** (one-time, in `_onUpgrade`):
1. Rename `peadra.db` → `peadra_pre_v7.db` on disk.
2. Open a fresh v7 CRDT DB (`SqliteCrdt.open`).
3. Copy rows in FK-safe order (users → accounts/descriptions/tags → transactions → recurring_* → imported_files), generating a UUID per row and remapping FKs through an in-memory `oldId → newUuid` map. Ciphertext values are copied verbatim.
4. On failure: restore the backup file and surface an error.

**`DatabaseManager` rewrite** (the bulk of this phase):
- Replace `Database` usage with `SqliteCrdt` (`crdt.execute`/`crdt.query`/`crdt.transaction`); IDs become `String` generated via `Uuid().v4()`.
- Adapt the ~40 CRUD methods; `execute` doesn't return row counts, so insert/update/delete success is verified by re-query (or returns `void` where callers tolerate).
- `_encrypt/_decrypt`/`reEncryptData`/`migrateToEncryption` unchanged in logic (still field-level AES-GCM), but routes through the new executor.
- `encryptionKey` accessor now also serves the sync layer.

**Model layer** (`lib/core/models/*`): all `int? id` / `int userId` / FK fields → `String`; update `fromMap`/`toMap`/`copyWith`. Cascade through every view that renders/uses ids (accounts, transactions, recurring, categories, import/export).

**main.dart**: open DB via the CRDT service (desktop still `sqfliteFfiInit`); wire `sqlite3_flutter_libs`.

**Tests**: rewrite `test/helpers/test_helper.dart` schema to v7 (UUID seeding helpers), fix all DB/model tests.

## 3. Phase 1 — Identity & Trusted Peers (`lib/sync/security`, `lib/sync/storage`)

- **Node identity** (`node_identity.dart`): lazy singleton generating/storing `local_node_id` (UUID) + `device_name` (e.g. `Platform.operatingSystem`) in `flutter_secure_storage`.
- **`TrustedPeer` model** (`models/trusted_peer.dart`): `peerId`, `deviceName`, `sharedSecret` (256-bit b64), `dbEncryptionKey` (b64, from pairing), `lastSyncHlc` (serialized `Hlc`), `createdAt`, `lastSeen`.
- **`SecurePeerStorage`** (`storage/secure_peer_storage.dart`): wrapper over `FlutterSecureStorage` with CRUD. Backed by a `StorageBackend` interface so tests can inject an in-memory store (flutter_secure_storage has no unit-test platform).
- **Auth/challenge** (`security/auth_challenge.dart`): HMAC-SHA256 sign/verify over `sharedSecret`, plus HKDF session-key derivation (helper over `cryptography`).

## 4. Phase 2 — Transport & protocol (`lib/sync/network`)

**Framing**: 4-byte big-endian length + JSON payload (changesets are large; no newline ambiguity).

**Mutual-authentication handshake**:
1. Client → server: `HELLO {node_id, device_name, protocol_version}`
2. Server → client: `CHALLENGE_A {nonce_a}` (server looks up `sharedSecret` by client node_id; abort if unknown)
3. Client → server: `RESPONSE_A {hmac(secret, nonce_a)}` + `CHALLENGE_B {nonce_b}`
4. Server verifies A, → client: `RESPONSE_B {hmac(secret, nonce_b)}` + `OK`
5. Both derive keys: `HKDF(shared_secret, salt=nonce_a‖nonce_b)` → two AES-256-GCM keys (client→server, server→client).

**Message layer**: every payload after handshake is `{iv(12), ct, mac(16)}` b64 over AES-GCM with per-message nonce tracking; close on MAC failure. Message types: `SYNC_REQUEST {since_hlc}`, `SYNC_RESPONSE {changeset}`, `USER_RECONCILE`/`USER_RECONCILE_RESPONSE` (see §6), `ERROR`, `CLOSE`.

- `p2p_server.dart`: `ServerSocket` bound to ephemeral port, accepts one connection per peer, runs the responder role.
- `p2p_client.dart`: `Socket.connect` + initiator role.
- Both roles share a common `SyncSession` state machine (`session.dart`) — handshake, per-direction keyed encryption, and message dispatch — so client/server logic stays symmetric.

## 5. Phase 3 — Discovery (`lib/sync/network/mdns_discovery_service.dart`)

- **Advertise** `_peadra-sync._tcp` with TXT `{node_id, device_name, protocol_version}` on the server port.
- **Browse** the same type; on service found, extract `node_id`; if present in `TrustedPeer` list → auto-initiate connection. De-duplicate/ignore self (`node_id == local_node_id`), throttle reconnects per peer.
- Restart advertisement whenever the server port changes; expose a `Stream<DiscoveredService>`.

**Platform config**:
- Android: add `CHANGE_WIFI_MULTICAST_STATE` to the manifest; mDNS receive on Android requires a `WifiManager.MulticastLock` — implement via a minimal MethodChannel helper (verify `mdns_dart` doesn't already acquire it).
- Windows: firewall prompt on first run (documented; `internetClient` capability already set).
- iOS/macOS (future): `NSBonjourServices` + `NSLocalNetworkUsageDescription` in Info.plist.

## 6. Phase 4 — Sync orchestration (`lib/sync/sync_manager.dart`, `lib/sync/storage/crdt_database_service.dart`)

`CrdtDatabaseService` wraps `SqliteCrdt` and exposes the two primitives used by sync:
- `getChangeset(since: Hlc?)` → `crdt.getChangeset(onlyTables: syncTables, modifiedAfter: since)`
- `applyChangeset(changeset)` → `crdt.merge(changeset)`
- `lastModifiedHlc()` → `crdt.getLastModified()`

**User identity reconciliation (critical detail)**: before the first sync, both sides exchange `(username, user_uuid)` pairs. Because `users.username` is `UNIQUE`, two devices with the same username but different UUIDs would break merge. Resolution: the pair session picks a canonical UUID for matching usernames (the peer that scanned, i.e. device B, remaps its local `user_id` references to device A's UUID in a transaction, tombstones its old user row). Runs once at pairing; typically a no-op since pairing precedes data entry. Usernames present on only one side are kept as-is.

**`SyncManager`** (singleton, started after login — the DB key is in memory — stopped at logout):
- On local change: subscribe to `crdt.onTablesChanged`, mark dirty, debounce ~2 s, then sync with all currently-reachable trusted peers.
- On mDNS discovery of a trusted peer: run one sync session (outbound changes, then inbound), update `peer.lastSyncHlc`, persist, close.
- One session per peer guarded by a mutex; failures logged via `LogService` and retried on the next mDNS event; never crashes the UI.
- `syncNow(peerId)` for manual trigger from the peers list.
- Logout clears nothing persistent (peer list is stored), but stops the server/advertisement and cancels in-flight sessions.

**Encryption key sharing** (during the first authenticated session): A sends its current `SecretKey` bytes (encrypted under the session key); B stores it as `peer.dbEncryptionKey`. If B is unencrypted, B enables encryption with the shared key (`migrateToEncryption`). If B is already encrypted with a different key, surface a confirm dialog: on accept, B re-encrypts local data with the shared key (`reEncryptData`). Documented side effect: password change re-derives a new key and requires re-sharing (re-pair or "update key" action in the peers list).

## 7. Phase 5 — Pairing & UI (`lib/features/sync/`)

- **`qr_pairing_screen.dart`**: shows a QR encoding `peadra://pair?node=<node_id>&name=<device_name>&secret=<shared_secret>` (fresh `shared_secret` per pairing attempt, kept in memory until first successful session). Device also advertises during pairing so the scanner can discover it.
- **Scanner** (`mobile_scanner`): scans QR → stores device A as `TrustedPeer` → triggers the reconciliation + encryption-key exchange session → both sides end up trusting each other.
- **`peers_list_screen.dart`**: list of `TrustedPeer`s, last sync time, manual "Sync now", forget (removes peer + secret).
- **Settings section** in `parameters_view.dart`: "Sync" section with Pair (QR), Scan, and Manage devices tiles.
- **i18n**: new keys in `translator.dart` (en + fr).

## 8. Tests (`test/`)

- `sync/crdt_test.dart`: two in-memory `SqliteCrdt` DBs; A inserts → `getChangeset` → B `merge` → equal; concurrent conflicting edits resolve by LWW; tombstones propagate.
- `sync/secure_peer_storage_test.dart`: CRUD with injected in-memory backend.
- `sync/protocol_test.dart`: real `ServerSocket`/`Socket` on localhost — full mutual handshake (success + forged-HMAC rejection), encrypted round-trip, SYNC_REQUEST/RESPONSE exchange.
- `sync/sync_manager_test.dart`: simulated discovery + two in-memory DBs → end-to-end delta exchange; disconnect/retry behavior.
- Migrate existing DB/model/widget tests to the v7 UUID schema.

## 9. Risks & mitigations

- **sqlite version on desktop**: `sqflite_common_ffi` uses the system `libsqlite3`; verify it's ≥ what sql_crdt needs (check at M1; fall back to a bundled sqlite3 for the CRDT layer on Linux if needed).
- **`mdns_dart` maturity** (22 likes, unverified uploader): port of HashiCorp's implementation; covered by protocol/E2E tests; fallback is `multicast_dns` + a custom responder if issues surface.
- **Android multicast lock**: verify receive path on a real device; add MethodChannel helper if `mdns_dart` doesn't handle it.
- **Users-table UNIQUE merge**: handled by reconciliation in §6; keep an explicit error path if username+uuid mismatch can't be resolved.
- **AUTOINCREMENT-era duplicates**: fresh pairings start from the v7 schema, so legacy collision risk is limited to the migration itself.

## 10. Suggested milestone order

1. **M1 — CRDT migration**: schema v7, UUIDs everywhere, `DatabaseManager` rewrite, tests green. (Landable alone; zero user-facing change.)
2. **M2 — Identity + peer storage** (no network yet).
3. **M3 — Transport/protocol** with unit tests.
4. **M4 — mDNS discovery** + auto-connect.
5. **M5 — SyncManager** + encryption-key sharing + user reconciliation.
6. **M6 — Pairing UI + peers list + i18n + settings tiles.**
7. **M7 — E2E validation** mobile↔desktop and mobile↔mobile: pair, edit offline on both, reconnect, verify convergence; password-change re-share; sudden disconnect/retry.

Estimated effort: M1 is the largest single chunk (schema + ~40 methods + all views/tests).