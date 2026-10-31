# Plan 2026-10-31-perf-waste-fixes-instant: temporary structures stay in memory; a closed result stops costing its writes twice

- planId: 2026-10-31-perf-waste-fixes-instant
- agentId: claude-code/perf-waste-fixes@ld (tools/agent-run, claude/ld, Opus 5.5 max)
- role: mower (the same rows, reads and answers, for fewer bytes written; no new surface)
- issues: #1504, #1500 (the wasted-work audit's library findings, queued on #1481); #1505 waits for #1500 (same tables)
- branch: agent/claude/perf-waste-fixes (worktree ~/Sync/worktrees/perf-waste-fixes-instant), landed with
  ~/Scribe/tools/land; the app's half (#1501 #1503) is the Scribe plan 2026-10-31-perf-waste-fixes

## Why

#1504: the phone's energy ledger names 34,124-36,677 writes an hour of recording to SQLite's temporary files
(`sqlite.temp`: the statement journal, a sort's or an ephemeral b-tree's spill, the temporary database's journal),
19-49 MB/h, and 470,007 (166 MB/h) across the 10-30 evening's eight launches. Every connection opens with SQLite's
default `temp_store` (FILE), so a statement journal past 64 KiB and a sort or `DISTINCT` past the 2 MiB page cache
(#653) spill to a file the system writes. The bytes are transient by definition: SQLite deletes the file when the
statement ends.

#1500: a closed query's stored result is moved into `instant_unloaded_live_query_results` as JSON and its ownership
rows and facts are released; its reopening writes them all back. On the phone this costs 145-308 MB/h of writes
(`applyReleasedLiveQueryResultChunk` 0.9 MB a call, the prune batch 1.1 MB, the reload 1.2 MB), and the table held
207 MB on 10-30. The audit's second fix (collect a result whose facts left `instant_triples`) would delete the only
local copy of those facts, which offline reopening reads (#1006; docs/FEATURES.md items 3 and 7 in Scribe), so this
plan does not do it. Upstream keeps a closed query's persisted copy unchanged (`PersistedObject.unloadKey`,
Reactor.js 463-485 and 1252) and pays a read, not two rewrites, on the next subscription: that is the direction
here. The design goes in an amendment once measured; nothing of #1500 lands before it.

## Steps (red, then green, each through build.sh)

1. #1504 red: the recording exercise (StorageIOExercises' write cycle: saves, claims, acknowledgements, echoes and a
   session prune) writes nothing to a temporary file of any kind, the statement journal included
   (InstantTemporaryStoreTests, new). Green: `PRAGMA temp_store = MEMORY` on the writer and on every read connection.
   What it costs: each spill's bytes in memory for the statement that made them, bounded by what the library already
   bounds (a prune batch 1,000 facts, a reload chunk 2,048, a server apply's body page 51 rows, the query cache 1 MB
   of JSON by its policy); the memory-pressure release (#653) still frees the page cache.
2. #1504 measure: the exercise's temporary bytes before and after; on the phone, `sqlite.temp` in the ledger after the
   next build (expect 0).
3. #1500: an amendment with the design, measured on a store copy and the exercise, before any code.

## Touching

Sources/InstantSwiftDataCore/SQLitePersistenceStore.swift (the writer's open settings only),
Sources/InstantSwiftDataCore/SQLiteReadConnection.swift (its open settings only),
Tests/InstantSwiftDataCoreTests/InstantTemporaryStoreTests.swift (new), CHANGELOG.md, PROGRESS.md,
docs/audits/commit-changelog.md (through land --prepend).

## Conflict check (origin/main 2026-10-31 13:20 EDT)

SQLitePersistenceStore.swift is claimed by perf-send-1492 (acceptOutboxMutation, the receipt digest), perf-read-1498
(the query cache), perf-observe-1493 and perf-gate-1491 (saveLocalMutation, the admission bound): none touches the
connection's open settings (`openRawConnection`, `configure`). SQLiteReadConnection.swift's claims are landed work
(#1150, #1245, #1426). Channel: agent-presence/_channels/2026-10-31-perf-waste-fixes-instant.md.
