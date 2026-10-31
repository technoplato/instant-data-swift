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

## Amendment 1 (2026-10-31): #1500's design, measured before code

What the store copy (10-30 17:15, read only, counts and lengths) says closes and reopens: 90 transcriptionSegments/256
pages (80 MB, 359,181 facts: a timeline's pages, the offline scroll-back cache of docs/FEATURES.md item 3), 28
whole-recording segment results (30 MB), 50 + 32 list pages (40 MB), and five copies of one voice-learner query
(`lineSpeakers/265000` to `/285000`, 2.6 MB each: its key changes with every new recording, an app-side source filed on
#1506). A page's close and reopen today writes about 7 MB, estimated from the ledger's averages per call (its 0.9 MB
JSON copy, four release chunks of 0.94 MB, two reload chunks of 1.2 MB); 308 MB/h on 10-31 is about forty such cycles
an hour.

The design (upstream's shape: `PersistedObject.unloadKey` keeps the persisted copy as it is and the next subscription
reads it, Reactor.js 463-485 and 1252):
1. A closed result keeps its header, its ownership rows and its facts. The header gains `closed_at_ms` (NULL while a
   query holds it; ALTER TABLE ADD COLUMN, no rewrite). Closing is one header update. Its facts leave the hot store
   (memory) when no open result owns them, and stay in SQLite.
2. Reopening finds the header closed, clears it, and loads the result's entities into the hot store from SQLite, a
   bounded chunk at a time as the reload does now (#1131): reads, no ownership or fact writes.
3. The policy (upstream's 1 year, 1,000 entries, 1,000,000 facts) collects closed results oldest first: the header, its
   ownership rows (released-row chunks for a large one, #1129) and the facts no stored result owns. That is today's
   release, run only past the policy.
4. Bootstrap loads the entities of open results and of the outbox's effects only.
5. `instant_unloaded_live_query_results` takes no new row. A legacy row reloads through today's path once (becoming
   rows) and the policy collects the rest as now, so the 207 MB drains without a migration's write burst at launch.
6. Expect: the unload, release and reload writers (145-308 MB/h) fall to the policy's collections; a page's reopen reads
   about 1 MB instead of writing about 7 MB; offline reopening answers from the same rows (Scribe FEATURES 3 and 7).

Red tests when it is built: a 4,000-fact result's close and reopen writes at most a few pages; after close its facts are
out of the hot store and still in SQLite, after reopen back in it; an offline reopen answers from the store before any
server frame; the policy past its limits releases the oldest closed result's facts. #1006's, #1131's, #1129's and
#1319's tests that assert the unloaded table or released facts change with it.

Not built in this session: it changes the prune, the registration, the bootstrap's residency and about forty tests in
SQLitePersistenceStore.swift while four lanes (#1491 #1492 #1493 #1498) edit that file. It is the next library step
after their landings, on this plan, by one agent in this worktree.

## Amendment 2 (2026-10-31): #1504 as built

- Where: the writer sets `PRAGMA temp_store = MEMORY` at the end of `bootstrap()`, after the one-time migrations (one
  copies every fact's key into a temporary table: 647,723 keys on the 10-30 iPhone store, which stay on SQLite's file)
  and before `ensureServerApplyStagingSchema()`, because a change of the setting drops every temporary table that
  exists. A writer that reopens its connection sets it again (today only a test closes the writer). Every read
  connection sets it at open, beside its 2 MiB cache.
- Red: `InstantTemporaryStoreTests.everyConnectionKeepsItsTemporaryStructuresInMemory` reads `PRAGMA temp_store` on the
  writer, on a read connection and on the writer after it reopens (two test accessors, `temporaryStoreForTesting()`):
  0 (a file) on all three before the fix (build.sh pwf-1504-redgreen, 2026-10-31 17:12). Two behavioral tests stay as guards
  (the recording exercise, and closing a 300-todo query): both wrote no temporary file before the fix either, because
  their statement journals stay under SQLite's 64 KiB in-memory limit; which phone statement spills is not reproduced
  at test sizes, so the phone's ledger after the build is the measure (`sqlite.temp` expected 0).
- Claims: SQLitePersistenceStore.swift also gets one test accessor beside `releasedLiveQueryResultCountForTesting`.

## Conflict check (origin/main 2026-10-31 13:13 EDT; the first version of this line said 13:20, a typed clock time)

SQLitePersistenceStore.swift is claimed by perf-send-1492 (acceptOutboxMutation, the receipt digest), perf-read-1498
(the query cache), perf-observe-1493 and perf-gate-1491 (saveLocalMutation, the admission bound): none touches the
connection's open settings (`openRawConnection`, `configure`). SQLiteReadConnection.swift's claims are landed work
(#1150, #1245, #1426). Channel: agent-presence/_channels/2026-10-31-perf-waste-fixes-instant.md.
