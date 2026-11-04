# Plan 2026-11-04-perf-mem-1797: memory in proportion to what is on screen

- planId: 2026-11-04-perf-mem-1797
- agentId: claude-code/perf-mem-1797@pp (tools/agent-run, claude/pp, opus)
- role: mower (the same answers and the same offline reads with less held in memory and less written; no new public
  surface)
- issues: #1500 (primary), #1165 (the write path every residency step needs), #1145, #1149, #1151, #1251/#1505, #1111,
  #1104/#1105/#1144, #1110, #541, #1512; epic #1797 (trace audit 2026-11-04), #1783
- branch: agent/claude/perf-mem-1797, worktree ~/Sync/worktrees/perf-mem-1797 cut from origin/main da175eb7; every
  green lands on main, rebased first

## Why (measured)

The phone's own memory samples (process.memory.sample, iPhone only, ~/Library/Logs/Scribe/diagnostics.jsonl,
2026-11-04): while recording, the store's resident facts grow about 13,000 an hour and the heap in use with them.
Build 245, 09:26-13:15: storeTriples 84,047 -> 135,584, mallocInUse 271 -> 314 MB, mallocFree 655-723 MB. Build 248,
16:05-17:40: 44,127 -> 64,874 facts, mallocInUse 135.8 -> 187.3 MB (+32.5 MB an hour). Each relaunch starts again near
44,000. Nothing evicts a row this device wrote once no open result shows it (#1145): the hot store keeps every row a
session writes. The parked sweep (bdf17ef8, 2026-10-25) failed because a write prepares against memory only (#1165): a
strict update of a disk-only entity throws, and a non-strict one erases the entity's other facts from SQLite (a
whole-entity save diffs memory's picture against every row on disk; confirmed red on 2026-10-31). A server refresh that
restates part of an entity memory lacks takes the same whole-entity save (read, not yet tested). #1500's closed results
kept on disk depend on the same fix.

## Steps

1. This plan and its claims (plan-only commit) on main.
2. #1165 red (`InstantNonResidentWriteTests`): a one-attribute write to a line kept on disk only keeps the line's other
   facts; a strict update of it succeeds and a strict create of it fails, as with the line in memory; a server refresh
   that restates part of a disk-only entity keeps its other facts on disk and memory holds the whole entity.
3. #1165 green: memory never holds part of an entity. Before a local write or a server apply prepares, the facts of
   each entity it touches that memory lacks are read from SQLite (one read, beside the deferred values the write
   already loads) into the prepared indexes, and stay resident after the commit. Upstream keeps one store per query
   result, so it has no disk-only entity; this is the adaptation for one shared store over SQLite.
4. #1145 red: `MemoryLongRunReplay` holds the criterion (resident facts within 2,000 of minute 5, heap under 3 MB a
   recorded hour); the sweep's unit tests (`InstantResidencySweepTests`, from bdf17ef8).
5. #1145 green: the residency sweep. An entity this device wrote leaves memory, not SQLite, once the server has
   proved its write, no stored result owns it and no open observer shows it; at most 500 entities a background gate
   hold, never during a prune.
6. Release (the next free v1.9.x), pin in Scribe, cut and install; measure the phone's storeTriples and mallocInUse
   over an hour of recording, before and after, on #1145, #1797.
7. #1500: a closed result keeps its rows where they are (no copy into instant_unloaded_live_query_results); the prune
   releases its facts from memory only; reopening reads them back without writing. Coordinated with #1122 (perf-recv).
8. #1251/#1505: a stored value without Swift's synthesized enum wrapper, with a migration that reads both forms;
   measured on a copy of the phone's store.
9. As time allows, each red then green with a before/after: #1111 (queryOnce's and the send's per-call schema work),
   #541 (the transaction-id interner and acknowledgement maps), #1151 (a reconnect keeps the old attribute tree),
   #1104/#1105/#1144 ($files whole-list reads), #1512 (the free list: an Allocations capture names the transient).

## Touching

- `Sources/InstantSwiftDataCore/InstantRuntime.swift` (the deferred-value loads before a local write prepares and
  before a server apply prepares, generalized to load non-resident entities; the residency sweep's scheduling; not the
  transact bookkeeping #1648/#653 own, not the refresh splice #1109 owns)
- `Sources/InstantSwiftDataCore/InstantStore.swift` (a residency query for entity ids, loading non-resident facts into
  prepared indexes, the sweep's release)
- `Sources/InstantSwiftDataCore/TripleIndexes.swift` (inserting loaded facts into prepared indexes, kept resident)
- `Sources/InstantSwiftDataCore/SQLitePersistenceStore.swift`, `SQLiteReadConnection.swift` (one read of the deferred
  values and of non-resident entities' facts; the sweep's ownership read; later #1500's prune and reload)
- `Sources/InstantSwiftDataCore/InstantResidencySweep.swift` (new, #1145)
- `Tests/InstantSwiftDataCoreTests/InstantNonResidentWriteTests.swift` (new), `InstantResidencySweepTests.swift` (new),
  `RealSize/MemoryLongRunReplay.swift`, `RealSize/RealSizeFixture.swift`
- `CHANGELOG.md`, `PROGRESS.md`, `docs/releases/v1.9.*.md`, `docs/audits/commit-changelog.md` (release and ledger)

## Conflict check

- perf-recv-1797 (#1109): the refresh splice, observers, the applier; #1122 (closing a query copies its result) is the
  same fix as #1500 step 7, and #1107 (launch decodes every stored result) overlaps #1149. Channel
  agent-presence/_channels/2026-11-04-perf-mem-1797.md proposes the split before either edits the prune or reload.
- perf-send-1797 (#653): transact bookkeeping, encode once, the pump; #1434 (ownership rows hold whole values) touches
  the ownership rows #1251/#1505's value encoding also rewrites. Step 3 touches only the deferred-value load before
  `prepareLocalWrite`.
- perf-sync-1796 (#1796): delivery and acknowledgements; step 5's sweep reads acknowledgements (outbox rows gone),
  never changes them.

## Amendment 1 (2026-11-04 19:00 EST): what #1165 and #1145 became; how to resume

Commits on `agent/claude/perf-mem-1797` (pushed to origin; not yet on main): #1165 red 20b88d9a, green f66f726f;
#1145 red 6ab10a4b, green c14aa08d and 67515e53. One mini job checks all of it: `1797-1165-redgreen`
(`.runs-1797/1165-redgreen.sh`, untracked in the worktree): #1165 red on main's sources, the two-hour replay without and
with the sweep (release), the focused suites, the whole bundle against `Tests/known-failing.txt`. Logs land in
`.runs-1797/` (`1165-red.log`, `1145-red-replay.log*`, `1145-green-replay.log*`, `1145-focused.log`, `bundle-*`).

- #1165, the invariant: memory never holds part of an entity. A local write (and the retry and refused-write rebases)
  reads, in the persistence turn that already read its deferred values, every fact SQLite keeps of each entity it
  names that memory holds no fact of; they join the prepared indexes and stay (`TripleIndexes.loadFactsKeptOnDisk`,
  unlike `hydrateDeferredValues`, marks nothing for removal). A server apply does the same for an entity absent from
  both its own prepared store and memory: an entity a pending write created is absent from the prepared store once its
  overlay is peeled, and its rows on disk are that write's, so memory decides. The residency check rides the store
  turn that already resolved the write's lookups (`entityIDsForPreparing`); with deferred values configured, as in
  Scribe, a write takes no new turn. Lookups still resolve against memory (Scribe writes none). Known gap left as it
  was: a delete's cascade reaches only resident children.
- #1145, the sweep: candidates are the entities each committed local write changed and the entities a result's save
  stopped owning (a value change keeps its row, so it is not named). Every 64 local writes or result-carrying frames a
  background task reads them once without a gate (owned ones leave, ones an outbox row touches wait), then holds the
  server-apply and operation gates at background priority for at most 500 at a time, reads them again and releases from
  memory, never from disk, those no observer shows. No batch while a prune releases a result; a maintenance activity
  stops it before a suspension; a close stops it. Observers stay verified (none shows a released entity), unlike a
  prune's retraction. The sweep records no actor hops, so the benchmarks' foreground counts stay exact.
- Expected bundle movement: `BenchmarkTests` (localTodoBenchmarkProducesDeterministicMetrics) asserts actor hops
  exactly; without deferred values a write now takes one more store turn, and one more persistence turn when it names an
  entity memory lacks (a create). Update those numbers from the run's diff, with this reason.
- #1512, read from the phone's own samples (iPhone, 17:55, build 249): footprint 203 MB, malloc in use 143 MB, malloc
  free 174 MB, graphics 27 MB. Footprint bounds the dirty part of the free list at about 33 MB: most of "free and never
  returned" is clean, purgeable or compressed, not footprint. The trace's 960 purgable-control traps a second (from
  scribe-f3) fit SQLite's page cache: each ephemeral b-tree (an IN list, a DISTINCT, an ORDER BY without an index) takes
  a bulk allocation of about 20 pages (~88 KB), freed at the statement's reset, which libmalloc's large cache marks
  volatile and non-volatile again on reuse. Next: count allocations of 32 KB and more per refresh and per write with
  `MemoryAllocationSites` and cut the ephemeral tables at their statements.
- To resume: read the job's logs; fix what the bundle names; then rebase on origin/main, push to main, release the first
  free v1.9.N (`git fetch --tags`; four lanes release tonight), pin it in Scribe, cut and install, and compare the
  phone's storeTriples and mallocInUse over an hour of recording with build 248's (44,127 -> 64,874 facts, 135.8 ->
  187.3 MB in 95 minutes).
