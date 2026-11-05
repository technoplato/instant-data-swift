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

## Amendment 2 (2026-11-04 19:05 EST): #1500's design, unload in place; red test waiting

Red test written, not committed while `1797-1165-redgreen` waits (a job ships the worktree as it is when it starts,
and a red test would read as a new bundle failure): `~/Sync/audit/perf-mem-1797/pending/InstantUnloadInPlaceTests.swift`
(`aClosedResultIsUnloadedWhereItIsWithoutACopy`: after the session prune, no row in
`instant_unloaded_live_query_results`, the closed result keeps its row and its 12 ownership rows, its 12 facts stay in
`instant_triples`, memory holds only the open query's row, and the reopened list answers from disk first). Commit it
as `red(#1500)` once that job has started.

Green, in this order (perf-recv-1797 agreed #1122 and #1107 are mine with #1500 and #1149):
1. Schema: `instant_live_query_results.unloaded_at_ms INTEGER` (nullable; one `ALTER TABLE ... ADD COLUMN` migration).
2. Unload = mark: the cadence prune sets `unloaded_at_ms` on each stored result no open or registering query holds
   (one row's page), instead of copying it, deleting its rows and releasing its facts. Its entities become residency
   sweep candidates; the sweep's ownership check counts loaded results only (`JOIN instant_live_query_results r ON
   r.query_id = o.query_id WHERE r.unloaded_at_ms IS NULL`), so memory lets a closed result's rows go while SQLite
   keeps them.
3. Collection: the policy (1 year, 1,000 results, 1,000,000 facts; upstream's) counts loaded and unloaded results, and
   collects unloaded ones oldest first: their row and ownership rows go (the cascade, in bounded chunks as #1129's
   released rows do), then the facts no remaining result owns and no outbox row touches, whole entities only (#259),
   from SQLite and, if resident and unshown, memory. The released-row machinery (`released-result:`) is reused for this.
4. Reopen: a marked result clears its mark (one row) and loads its entities whole from `instant_triples` (entities
   memory lacks, in bounded chunks under gate holds, as #1131's reload does) without writing them. A legacy JSON copy
   (`instant_unloaded_live_query_results`, older builds) reloads as today, which turns it into rows; the policy collects
   the rest; no new copy is ever written.
5. Readers: retraction ownership checks and the policy's counts include unloaded results (their facts stay on disk for
   an offline reopen); the refusal resolution's newest server values (#441) and the launch residency read count loaded
   results only, as they counted no copy before.
6. Launch (#1149, #1107): the retained entities come from SQL over loaded results' ownership rows (they are already
   nested-limited at save), not from decoding every result.
Measure: the unloaded table's bytes on a copy of the phone's store, the four writers' MB/h (applyReleasedLiveQuery...,
applyLiveQueryResultPruneBatch, reloadUnloadedLiveQueryResultChunk, beginUnloadedLiveQueryResultReload) from the
phone's ledger files before and after, and `StorageIOExercises/liveWritesOnThePhoneShapedStore`'s first prune frames.

## Amendment 3 (2026-11-04 19:10 EST): one folded job; #541; the launch's next step

- Build capacity is tonight's bottleneck (the coordinator, scribe-f3): both jobs were cancelled and folded into one,
  `1797-perf-mem-focused`, shipped from `~/Sync/worktrees/perf-mem-1797-unload` (branch
  `agent/claude/perf-mem-1797-unload` = this lane's branch plus #1500's WIP, pushed): #1165 red; the sources at
  #541's red with every test at HEAD (#1165/#1145 green, #541 and #1500 red) over 23 suites; HEAD (#1500 and #541
  green); the two-hour replay at HEAD (#1145's criterion); S05's large-allocation sites (#1512). Logs in that worktree's
  `.runs-1500/`. The whole bundle runs once, at release.
- #541: red abb8ead1 (twelve answered and unregistered live queries leave twelve acknowledgement keys), green ebc6890d
  (forgotten when the last registration ends; one revision counter). The interner half (about 100-150 B a local
  transaction, ~0.3 MB an hour on the phone's write rate) needs every stored fact's transaction index remapped; left.
- #1149/#1107 next, on top of #1500: a launch marks every stored result unloaded and loads only the outbox's entities;
  each query that subscribes again reloads its own result from disk (upstream `querySubs.waitForKeyToLoad`). Red test
  waiting: `~/Sync/audit/perf-mem-1797/pending/InstantLaunchResidencyTests.swift`. Tests that read memory right after a
  launch (InstantLocalReadTests, InstantNonResidentWriteTests' relaunched store) will need a subscription first.

## Amendment 4 (2026-11-04 22:55 EST): a launch preloads the newest ten results, as upstream does (#1107, #1149)

- Amendment 3 planned to unload every stored result at a launch. Upstream does not: `PersistedObject` preloads the
  `preloadEntryCount` most recently updated entries (`Reactor.js` passes 10 for `querySubs`; `PersistedObject.ts`
  `_preloadEntries` sorts by `updatedAt`) and loads any other when its query subscribes (`waitForKeyToLoad`). So, at
  the runtime's bootstrap, before the store's state loads, every stored result past the newest
  `InstantRuntimeConfiguration.preloadedLiveQueryResultCount` (10) by `updated_at_ms` is unloaded where it is (one
  `UPDATE` of `unloaded_at_ms`, #1500); the launch then loads only the loaded results' entities and the outbox's. A
  query that subscribes again reloads its result from disk before it registers (#1131, #1500), offline included.
- Measured on a read-only copy of the phone's store (2026-11-04 21:20, the consuming app's build 253): a launch holds
  1,915 entities and 48,202 facts (46 loaded results); with the newest ten, 677 entities and 31,070 facts (-36%).
  Tests with ten stored results or fewer see no change.
- Touching: `SQLitePersistenceStore.swift` (the bootstrap's mark), `InstantRuntime.swift` (the configuration's count,
  the two bootstrap calls), a new `InstantLaunchResidencyTests.swift`. Red, then green, in one mini job after this
  lane's merge lands.
- Next (design first, #1149): residency per entity and link attribute, for the 23,314 launch-resident link facts no
  stored result owns (`recordings.segments` 12,139, `.attachments` 6,324, `.runtimeEvents` 3,787, `.sounds` 987).

## Amendment 5 (2026-11-05 01:50 EST): the launch read by SQL (#1149, built); link residency designed, not built

- Built: red `44fc0c03`, green `518b7418` (on top of #1107's `83446b22`): a launch read each loaded stored result whole
  (header and every ownership row decoded into facts), ran the query's nested limits over them again and bound every
  entity id it found. A save keeps ownership of only the facts the nested limits keep, so the facts' read now selects the
  entities with one subquery over the loaded, unreleased results' ownership rows and the outbox's; the check for any
  ownership row is `EXISTS`, not a `COUNT(*)` over every row (unloaded results' too, since #1500). It rides the gate
  `1797-1500-land-green` (bundle at `518b7418`; E07 at M2 before, at `518b7418` after).
- Measured, not built: #1251/#1505's wrapper on the same store copy (2026-11-04 21:20, build 253): `instant_triples`
  value text 20.30 MB, 13.63 MB in a compact tagged form (-33%); ownership rows 1.09 -> 0.64 MB. About 7 MB of a 251 MB
  file plus its index copies, against a migration that rewrites two primary keys, and 14 readers that decode the fact
  table's generated `json` (which embeds `value_json`) with the synthesized Codable. Ranked below residency.
- Measured, corrects amendment 1: Apple's SQLite (macOS 3.51.0, memory status on) builds an ephemeral table for
  `IN (?,?)` with page-sized allocations (largest 4,104 B, peak 22 KB a step), not a 20-page bulk allocation, so
  ephemeral tables are unlikely to be the 960 large-cache traps a second; S05's sites decide (#1512).

### Link residency (#1149, next; design)

Why: with the newest ten results loaded, a launch holds 31,070 facts on the phone's store copy, and 19,686 of them are
recordings' cardinality-many links no loaded result owns (`recordings.segments` 10,075, `.attachments` 6,140,
`.runtimeEvents` 2,687, `.sounds` 784): memory holds an entity whole (#1165) and the recordings list owns each
recording's id, start and title. Holding only what loaded results own would take the launch to about 11,400 facts
(-63%), about 10 MB of heap at E07's 540 B a fact, for the whole session (the list keeps its recordings). Upstream holds
less still: `Reactor.js` builds one store per query result from that result's triples (`createStore(attrs,
result.triples)`), so an entity is never more than what a result selected.

Design (the shape of deferred values, generalized to an entity's facts):
1. Launch: load the facts of each (entity, attribute) a loaded result owns any fact of, and the outbox's entities whole;
   every loaded entity outside the outbox is marked partial in the store (`InstantStore.partialEntityIDs`), a
   conservative mark that costs one primary-key range read at its first write.
2. Writes: `entityIDsForPreparing` names, beside the entities memory holds no fact of, the partial ones; the write's
   persistence turn reads them whole (`loadFactsBesideMemory`, #1165), they join the prepared indexes whole and the mark
   goes. A server apply does the same for a partial entity it changes (`hydrateDeferredValuesForServerApply`'s turn).
   So no save ever diffs a partial picture against the rows on disk (the #1165 data loss).
   Refinement to weigh first: a whole read of a recording at its first write brings its 10,000 links back for the
   session, and the current recording is written every few seconds. Instead a write to a partial entity can take the
   per-fact scope `InstantStore.usesWholeEntityScope` already gives entities of more than 32 facts (scoped to the
   attributes and link values it touches), reading only those (entity, attribute) pairs from disk first, so its
   before-image (the rollback of a refused write) holds the disk's values and its save diffs only what it touched.
3. Reads: a local read's disk merge (`mergingEntitiesOnDisk`, #1006) reads partial entities from disk with the
   disk-only ones; a reopened result (#1500's reload) completes the partial entities it owns.
4. Release: the residency sweep (#1145) and the prune release a partial entity whole, as any entity, and drop its mark.
5. Not changed: lookups resolve against memory (the consuming app writes none); a delete's cascade reaches resident
   children only (as before #1165).
Found while writing the red (`48f10a63`, `InstantPartialResidencyTests`): what "owned" loads must differ by attribute.
- A many-valued link loads the values a result owns, not the attribute's every value: the recordings list owns two
  segment links per recording under its nested limit, and loading the (recording, segments) pair would bring all
  10,000 back. So exact facts for `.ref` + `.many` attributes (the ownership row's value, a primary-key probe each).
- A single-valued attribute loads per (entity, attribute): the owned value can be stale (a local write changed the
  title since the save), and the current one is the fact on disk.
- The outbox's entities load whole, as now.
- Partial marking: precise (an entity with a non-deferred fact on disk outside what loaded) costs a scan of the loaded
  entities' rows in SQLite at launch, links included, without materializing them; conservative (every loaded entity
  outside the outbox) costs a disk merge of each in every local read by lookup (history pages) and a whole read at its
  first write. Prefer precise, measured on the store copy first.
- Sized (store copy 2026-11-04 21:20, newest ten loaded, `~/Sync/audit/perf-mem-1797/scripts/partial_launch.py`):
  31,161 launch facts today, 16,181 partial (-48%); 52 entities held in part. A NOT EXISTS per fact found them in
  341 ms on a Mac, too slow for a launch: compare per-entity counts (one GROUP BY over the loaded entities' primary-key
  ranges, deferred attributes left out) against the facts loaded.
- Plumbing: `loadStoreSnapshotWithoutTransaction` has ten callers (the launch, state reconstruction, another
  connection's adoption, snapshot replacement, the reconcile and repair paths), and `InstantStoreSnapshot` is public
  and Codable. Carry the partial set beside it (the internal `InstantPersistenceStateLoad` / `.snapshot` adoption),
  not in it; every path that installs a snapshot installs its set; a full load (no ownership rows) has none.
- `TripleIndexes.insert` keeps a resident fact's stamp and counts only new values, so reading a partial entity whole
  over its resident facts is idempotent.
Red tests first: a relaunch holds a loaded result's owned attributes of an entity, not its unowned links; a write to it
keeps its links on disk and leaves it whole in memory; a server apply to it keeps its disk-only facts; a local read
with a lookup over it answers with its disk facts; reopening an unloaded result completes it. Measure: E07 (resident
facts, allocations) and the store copy's launch count, then the phone's storeTriples after install.

## Amendment 6 (2026-11-05 04:00 EST): what the landing gate found; how to land

- Gate `1797-1500-land-green` (mini, 02:46-03:35): the whole bundle at M2 `f504ed51` had 22 new failures, at
  `518b7418` 24. None lost data. 20 tests still expected #1500's copy; #1165 makes a fact adopted from another
  runtime's write keep that write's own time (as upstream's `getCreatedAt` keeps a resident fact's time); a by-id file
  lookup's prune now unloads in place; at `518b7418` one more prune test read a store's open from memory (#1107) and a
  frame-decode timing ratio read 0.374 against 0.33 (load; passed at M2). The four reds failed as written. Release
  numbers in the same job: the two-hour replay +15,102 -> +1,380 resident facts, heap +9.2 -> +2.7 MB an hour; E07's
  launch 54,720 -> 9,728 facts, 24.9 -> 9.0 MB retained, 234 -> 59 ms.
- Three source gaps the triage found, fixed with reds first on `agent/claude/perf-mem-1797-fixtests` (on 518b7418):
  a session prune unloaded every closed result in one gate hold (#303's shape: red `708ded11`, green `74e65b56`, a
  bounded batch unloads within its triple budget); the store's own prune never marked a closed result, and a collection
  after an unload neither counted nor announced the facts it deleted from disk (red `cb0e8578`, green `6779994f`).
  Expectation-only commits: `caf33f20` (#1500 prune tests: collection is the path that still deletes, so #654, #1129
  and #1319 are tested there), `b6a80186` (#1165), `7982385d` (E07's bound: 5 MB plus 540 B a resident fact).
- Known still to do in this landing: `InstantLiveQueryCompactOwnershipTests`' pinned digest (v1.9.10's
  "e5f08f8f40ae0900 over 22178 answers") covers the answers after a prune, which #1500 changes in both stores alike; it
  is re-pinned from the next bundle's output, with this reason.
- To land: job `1797-1500-fixtests` (mini only, place 03:06, runs only on the trees `.runs-1797/READY` names) runs the
  whole bundle; on its compare (new failures: the digest alone, or none), re-pin, then
  `~/Sync/audit/perf-mem-1797/scripts/land.sh <tip>`, `WITH_1107=1 WITH_LAUNCH_READ=1 WITH_FIXTESTS=1
  ledger-v1.9.71.sh`, the release record (`release-v1.9.71.md`: LANDED_SHA, FIXBUNDLE), tag v1.9.71, pin in Scribe
  (`pin.sh`), cut, install; the phone's after needs his next recording (Scribe has not run on the iPhone since 00:00).
- Next in this lane after the release: link residency (amendment 5; red `48f10a63` on `agent/claude/perf-mem-1797-links`,
  not landed), then #1251/#1505's wrapper. #1151 measured transient (64 MB allocated, 5.4 KB retained a reconnect) and
  #1111's refresh context is already reused; both rank below residency.
