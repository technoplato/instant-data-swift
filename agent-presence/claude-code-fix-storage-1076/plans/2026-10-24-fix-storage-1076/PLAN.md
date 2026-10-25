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
