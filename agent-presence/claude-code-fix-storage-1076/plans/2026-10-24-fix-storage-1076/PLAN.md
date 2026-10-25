# Plan 2026-10-24-fix-storage-1076

- **planId:** 2026-10-24-fix-storage-1076
- **agentId:** claude-code/fix-storage-1076@ld
- **role:** mower: each fix makes a recording's writes cost the disk what they change, and keeps behaviour; ordered by
  the lab's 22:17 dispatch on #1076 (the storage audit's fixes, worst first).
- **branch:** agent/claude/fix-storage-1076 (worktree ~/Sync/worktrees/instant-fix-storage-1076), each red and green
  landed on main in turn; "ready for release" on `agent-presence/_channels/2026-10-24-lib-audit-1072.md` for each, to
  fix-gate-1074 (the release owner).

## Outcome (#1076's fixes, worst first)

1. #1118: the store's own writer checkpoints every 4,000 frames instead of Apple's 1,000, so an hour of recording asks
   for under 300 full fsyncs instead of 1,039, with no more bytes written; a crash loses no committed write, and a
   power loss loses only the writes since the last checkpoint, never the store's consistency.
2. #1115: a queued write's outbox row stops rewriting 14 b-trees four times: fewer indexes, the body in its own table.
3. #1120: a re-saved entity updates its facts in place, and skips a fact whose value and stamp are unchanged.
4. #1121: each fact is stored once (no `json` copy of the row), migrated on a copy of the phone's store first, the old
   file kept until the new one is verified.
5. #1124: the live session counts bytes and frames per op and direction, and the device log reports them.
6. Then #1119, #1122, #1123, #1125 as measured.

Each fix: a red commit (a focused test, or the audit's exercise, failing), then green; before and after measured with
the audit's exercises (`StorageIOExercises`, `STORAGEIO_EXERCISES=1`, release, Mac mini) at the lines each issue
names, and `scripts/storage-io/phone-store-pages.sh` on the laptop's read-only copy of the phone's store where an issue
names it; every number names its store (synthetic, phone-shaped fixture and its version, or the phone's copy).

## Steps

1. #1118 red: the store's writer reports `wal_autocheckpoint` 1,000 (Apple's default) where the plan wants 4,000; a
   store whose process dies with more than 1,000 uncheckpointed frames in its log (impossible today) reopens with every
   committed write; a power-loss image (the files as their last full sync left them, and with a prefix of the writes
   after it) opens consistent with a prefix of the committed writes. Green: one setting at open, recorded in the
   durability log line.
2. `theStoreOverASimulatedHour` and `eachStepOfALiveWrite` before and after on the mini (main before the fix, then the
   fix), the audit's results, #1118 and the channel.
3. #1115, #1120, #1121, #1124, ... in that order, each with an amendment here naming the functions it touches.

## Touching

Changed, by function (amended per issue):
- `Sources/InstantSwiftDataCore/SQLitePersistenceStore.swift`: `openRawConnection` (the checkpoint setting),
  `recordDurabilitySettings` (logs it), a testing accessor beside `synchronousSettingForTesting`, the constant beside
  `sqlitePageCacheSizeKibibytes`, the file's history block.
- `Tests/InstantSwiftDataCoreTests/RealSize/StorageIOCounters.swift` (test-only; the audit's file, continued here): a
  journal of each watched file's writes since its last full sync, for power-loss images.
- `Tests/InstantSwiftDataCoreTests/RealSize/StorageIOExercises.swift` (test-only; the audit's file, continued here):
  the hour prints the store's own setting and the longest run of writes between log syncs (a power loss's reach).
New: `Tests/InstantSwiftDataCoreTests/SQLiteCheckpointCadenceTests.swift`.
Appended: `CHANGELOG.md`, `PROGRESS.md`, `docs/audits/commit-changelog.md`,
`docs/audits/2026-10-24-storage-disk-network-audit.md` (results after each fix), and a results file beside the
baseline, `docs/audits/2026-10-24-storage-io-fixes.txt`.
Read only: `Tests/InstantSwiftDataCoreTests/RealSize/` (#1072's fixture and meter), `scripts/storage-io/`.

## Conflict check

fix-gate-1074 (plan ed161097, amendment bc721340) holds, in `SQLitePersistenceStore.swift`, the closed-result reload
(`beginUnloadedLiveQueryResultReload`, `reloadUnloadedLiveQueryResultChunk`), the prune's batch helpers and its gate
phases as each starts; fix-memory-1075 (plan 03129234) names #1147's persisted-result build before it edits. #1118
touches none of them. #1115 is the outbox's functions (lib-audit-1072 released them at 20:55; #1115 names them here and
on the channel before editing). #1122 (the prune's unload copy) and #1123 (a changing result's JSON rewrite) sit in
fix-gate-1074's prune and fix-memory-1075's result build: each is split on the channel by function before either edits.

## Amendment 1 (2026-10-24 22:50 EDT, #1120)

A re-saved entity's facts are updated where their rows are. Claimed now:
- `Sources/InstantSwiftDataCore/SQLitePersistenceStore.swift`: `insertTripleWithoutTransaction` (an in-place upsert for
  `INSERT OR REPLACE`; a deferred attribute's other values deleted, not its own) and `saveTripleDiffWithoutTransaction`
  (the facts it rewrites). Leaf functions only: their callers (`saveLocalMutation`, `commitServerApplyPlan`,
  `commitClaimedTerminalFailure`, the closed-result reload, the snapshot diff) are unchanged.
- New, test-only: `Tests/InstantSwiftDataCoreTests/InstantFactInPlaceUpsertTests.swift` (in the `StorageIOExercises`
  suite: a re-saved entity keeps its rows and its keys, counted by the audit's VFS shim).

## Amendment 2 (2026-10-24 23:06 EDT, #1124)

The live socket counts its frames and bytes by op, each way, and the device log reports them once a minute. Claimed:
- New: `Sources/InstantSwiftDataCore/InstantWireMeter.swift` (the meter and its snapshot, public like
  `InstantEnergyMeter`'s so a host's energy ledger can read it).
- `Sources/InstantSwiftDataCore/InstantLiveTransport.swift`: `InstantURLSessionLiveWebSocket.send` and `receive`
  (each frame counted where its size is already known) and their codecs `encodedFrame` / `decodedFrame` (unchanged).
- New, test-only: `Tests/InstantSwiftDataCoreTests/InstantWireMeterTests.swift`.

## Amendment 3 (2026-10-25 00:05 EDT, #1115 slice 1)

#1118 and #1124 landed (`56538ac5`, `887f3bb2`); #1120 is held for #1121 (measured neutral on the hot path). #1115's first
slice cuts two of the outbox's b-trees from every write and one from every claim, without touching any statement's
columns: the write-key and effect-entity tables become WITHOUT ROWID (each kept its whole row twice, as the table and
as its primary key's index), and the delivery candidate partial index folds into the deadline index as one
`(delivery_claim_state, delivery_state, delivery_claim_deadline_ms, created_at_ms, mutation_id)` index. Claimed:
- `Sources/InstantSwiftDataCore/SQLitePersistenceStore.swift`: `bootstrap`'s migration list (two new migrations) and its
  re-assert of the delivery candidate index, `readyForDeliveryCondition`, `deliveryCandidateIndexSQL` (becomes the
  folded index), and the doc comments of `automaticDeliveryCandidatesSQL` and `automaticDeliveryCandidateExistsSQL`.
- `Tests/InstantSwiftDataCoreTests/InstantOutboxPageChurnTests.swift`: the rowid read in
  `anAcknowledgementUpdatesItsBookkeepingRowsInPlace` (a WITHOUT ROWID table has none) and the index list in
  `theOutboxKeepsNoIndexItsStatementsCannotUse`.
- `Tests/InstantSwiftDataCoreTests/RealSize/StorageIOCounters.swift`: whether a file is counted is decided at each call
  from the watched directory, not once at open, so a store another test left open is not counted.
- New, test-only: `Tests/InstantSwiftDataCoreTests/InstantOutboxBTreeWritesTests.swift` (in the `StorageIOExercises`
  suite: one write's save, claim, acknowledgement and echo, frames per outbox b-tree, through the audit's VFS shim).
Next slices, each amended here first: the bodies in their own table, then partial indexes on what that makes cheap.

## Amendment 4 (2026-10-25 00:15 EDT, #1121 with #1120)

Each fact is stored once. Migration 0032 rebuilds `instant_triples` WITHOUT ROWID on its natural key (entity_id,
attribute_id, value_json) with `json` a VIRTUAL generated column (the same text the store wrote, computed when read,
no storage), so every reader of `json` stays as it is; inside its transaction the new table is checked against the old
(row count and per-column checksums) before the old one is dropped, else the migration throws and the store keeps its
old layout. #1120's in-place upsert rides along (held since amendment 1: on the rowid table it measured neutral, on a
WITHOUT ROWID table an entity's facts share their own leaf and no separate key index exists). Proven first on a scratch
copy of the phone's store on the laptop (never in a repository, deleted after), with the library's own bootstrap.
Claimed:
- `Sources/InstantSwiftDataCore/SQLitePersistenceStore.swift`: `bootstrap`'s migration list (one new migration),
  `insertTripleWithoutTransaction` and `saveTripleDiffWithoutTransaction` (amendment 1),
  `upsertCanonicalRelationTripleWithoutTransaction` (no stored `json`), `reconcileDeclaredRelationStorageIfNeeded`'s
  removal by rowid and `nextApplicationMigrationTripleRowWithoutTransaction` (a key cursor),
  `applyLocalPersistenceMigration`'s fact update (by key), `InstantApplicationMigrationTripleRow`.
- `Sources/InstantSwiftDataCore/InstantStoredJSON.swift`: a value-only text for writes.
- Tests: `DeferredValueResidencyTests.swift` and `InstantStartupTraceTests.swift` (their corruption helpers write the
  value's text, since a fact's JSON is computed now), `InstantFactInPlaceUpsertTests.swift` (amendment 1's test, for the
  new layout); new `InstantFactLayoutTests.swift`; new `InstantFactLayoutDeviceStoreTests.swift` (skipped unless
  `INSTANT_1121_STORE` names a scratch copy of a device's store).

## Amendment 5 (2026-10-25 00:50 EDT, #1120)

Claimed: `Tests/InstantSwiftDataCoreTests/InstantStoreTests.swift`, the expected counts in
`transactionsPersistOnlyChangedRows` only: an update of a todo's text now inserts one fact row (the new text), where
INSERT OR REPLACE inserted two (the re-stamped id fact too); the in-place upsert updates the id fact in its row. Found by
comparing the release bundle's printed `expectNoDifference` differences before and after #1121.

## Amendment 6 (2026-10-25 01:20 EDT, #1123)

A changing query's whole result JSON is written at most every 5 minutes instead of every 30 s. The app's flush on
background and termination (Scribe's `ScribeLiveQueryResultFlush`), a query's unsubscribe and the connection's close
still write what waited, and a kill is repaired from ownership rows at the next launch (#566's design, unchanged), so the
interval only bounds how often a foreground session rewrites it. What-if (mini, release, synthetic store, main after
#1121): `instant_live_query_results` 3.90 -> 1.00 frames per write, all frames 54.9 -> 51.9; never writing it measures
the same 1.00, the row's count and time that each refresh keeps exact for the crash repair and #1131's reload check.
Claimed:
- `Sources/InstantSwiftDataCore/InstantRuntime.swift`: `InstantRuntimeConfiguration.liveQueryResultJSONWriteIntervalMilliseconds`'
  default and `flushPendingLiveQueryResults`' doc.
- `Sources/InstantSwiftDataCore/SQLitePersistenceStore.swift`: the store's default interval and `LiveQueryResultJSONState`'s
  doc.
- `Tests/InstantSwiftDataCoreTests/InstantLiveQueryResultWriteTests.swift`: the throttle test's window and a new
  ten-minute test.

## Amendment 7 (2026-10-25 01:35 EDT, #1125)

A stream file's resume asks only for the bytes it has not seen: each file the reader has seen whole is asked for past
its end and the one its seen offset falls in from that point, with an HTTP `Range` request, and a file is passed over
only when the server says so (a 206 whose `Content-Range` starts where the reader asked, or a 416 naming the file's
size). Any other answer, or a transport without ranged fetches, fetches the rest whole and drops what was seen, as
upstream's `Stream.ts` does (it fetches every file from its start); the divergence is the radio's cost of a resume
(Scribe reads shared recordings' media from streams). Claimed:
- `Sources/InstantSwiftDataCore/InstantStreamFileTransport.swift`: the whole file (the response's `Content-Range`, the
  client's ranged fetch and its live form, the materializer).
- `Tests/InstantSwiftDataCoreTests/InstantStreamFileTransportTests.swift`: new cases beside the existing ones.
