# Plan 2026-10-24-fix-memory-1075

- **planId:** 2026-10-24-fix-memory-1075
- **agentId:** claude-code/fix-memory-1075@ld
- **role:** mower: each fix makes a write, refresh or read cost what it changes, not what the store or the recording
  holds, and keeps behaviour; ordered by the lab's 21:00 dispatch on #1075 (the memory audit's fixes, worst first).
- **branch:** agent/claude/fix-memory-1075 (worktree ~/Sync/worktrees/instant-fix-memory-1075), each red and green
  landed on main in turn; "ready for release" on `agent-presence/_channels/2026-10-24-lib-audit-1072.md` for each.

## Outcome (#1075's fixes, worst first)

1. #1152: a new line linked to a long recording allocates what one linked to a new recording does: a large
   many-cardinality slot keeps its values in shards, so a prepared write copies one shard, not the recording's whole
   link set; the insert path stops copying the schema-sized derived-shape map with an unchanged entry.
2. #1147: a refresh that changes one line of an open page costs that line, not the page.
3. #1145: the hot store stops keeping every row the session wrote once no result owns it.
4. #1150, #1153: a history page reads only its rows; a finished line is prepared once.
5. #1148, then #1144, #1149, #1151, #1146 as measured.

Each fix: a red commit (a focused allocation or peak-memory budget test that fails), then green; before and after
measured with the audit's exercises (`scripts/memory-exercises/run-memory-exercises.sh`, release, Mac mini, fixture
version 3) at the lines each issue names, and the two-hour replay at minutes 5, 60 and 120 where retention moves.

## Steps

1. #1152 red: a one-thread allocation count of a link prepared on a copy of the store's indexes, on a recording that
   holds 2,318 lines against one that holds none, and with 2,283 attributes against 16. Green: sharded collections
   keep one plain collection until they pass a threshold, then shards; a many-cardinality slot's values use one; the
   derived-shape write is guarded as `insertNewCardinalityOne`'s is.
2. E04 before and after on the mini; the audit's results section and #1152 get the numbers.
3. #1147, #1145, #1150, #1153, #1148, ... in order, each with an amendment here naming the functions it touches.

## Touching

Changed, by function (amended per issue):
- `Sources/InstantSwiftDataCore/ShardedCollections.swift`: the whole file (a small mode below the threshold, coding).
- `Sources/InstantSwiftDataCore/TripleIndexes.swift`: `AttrSlot` (its many-cardinality storage), `insert(_:attribute:
  replacingWhateverTheStamps:)`'s derived-shape write, and the sites that build a many slot (`triples(entityID:
  attributeIDs:values:)`'s scoped slots, `hasLink`, `normalizedSlot`). Not the `TxIDInterner`.
- `Sources/InstantSwiftDataCore/InstantStore.swift`: `PreviousChangedEntityCapture` (its restored many slots) only.
New: `Tests/InstantSwiftDataCoreTests/LinkSetWriteCostTests.swift`. Extended:
`Tests/InstantSwiftDataCoreTests/ShardedCollectionsTests.swift`.
Appended: `CHANGELOG.md`, `PROGRESS.md`, `docs/audits/commit-changelog.md`, `docs/audits/2026-10-24-memory-audit.md`
(results after each fix).
Read only: `Tests/InstantSwiftDataCoreTests/RealSize/` (#1072's fixture and meter, #1075's exercises).

## Conflict check

fix-gate-1074 (plan ed161097, same start) claims by function in `InstantRuntime.swift`, `InstantRuntimeLiveSession.swift`
and `SQLitePersistenceStore.swift` and will not edit `TripleIndexes.swift` or `InstantStore.swift` without asking on the
channel. #1152 touches neither of its functions. #1147's refresh path and #1151's reconnect are next to its #1128 and
#1131 work: each is named on the channel and split by function before either edits. lib-audit-1072 released its holds
at 20:55 (`TxIDInterner`, the outbox functions, `discardFailedMutation`).

## Amendment 1 (2026-10-24 22:07 EDT, claude-code/fix-memory-1075@ld)

#1152 landed (red `ccdbc47b`, green `33c5c042`, ledger `b2d4c262`). Claimed now:
- `Tests/InstantSwiftDataCoreTests/RealSize/MemoryLongRunReplay.swift`: `MemoryLongRunReplaySmokeTests` only, which moves
  into the measurement pass (`.measurement`, #1021): its apply waiter listens on the process-wide diagnostics hub and
  timed out in whole-bundle runs (lib-audit-1072's report of 22:52 on #1075; again on 2947d348), passing alone.
- New, test-only: `Tests/InstantSwiftDataCoreTests/RealSize/MemoryAllocationSites.swift` (an allocation-site sampler:
  libmalloc's logger hook records each allocation's return addresses, named afterwards with `atos`) and
  `Tests/InstantSwiftDataCoreTests/RealSize/MemorySiteExercises.swift` (E03's refresh and E04's final line, printed
  by call site, `INSTANT_MEMORY_SITES=1`), so #1147 and the fixes after it start from measured call sites.
#1147's library functions are named in the next amendment, once the sites are in, before any edit.

## Amendment 2 (2026-10-24 22:37 EDT, claude-code/fix-memory-1075@ld)

The allocation-site recording (`MemorySiteExercises` S03, Mac mini, release, fixture v3) splits one 64-line refresh
(about 22,400 allocations, 21.7 MB) into: the frame's JSON parse about 7,000 allocations; the nested-limit pass about
700 allocations but about 6.5 MB, for a plan with no nested include; three schema-wide groupings per hydrated emission
about 1,670 allocations and 2.2 MB; the persisted result's per-fact value encoding (1,024) and ownership re-read
(3,072); the classification's deferred-value loads about 3.8 MB. #1147 goes step by step, each red then green:
1. `Sources/InstantSwiftDataCore/InstantLiveQueryNestedLimit.swift` (whole file): a query with no nested include whose
   rows fit its limits passes through unchanged, and attributes are looked up only for the triples' own attribute ids.
2. `Sources/InstantSwiftDataCore/DeferredValueResidency.swift` (`hydrationRequests`, `hydrating`,
   `requestedAttributes`, and the per-namespace lookups they rebuild) and `InstantRuntime.swift`
   `hydratingDeferredValues(in:plan:attributes:onFailure:)` only: the schema-wide maps once per attribute revision.
3. Later amendments: the persisted result's build (`SQLitePersistenceStore.swift`, after agreeing with
   fix-storage-1076), the classification's deferred loads (after agreeing with fix-gate-1074), the frame parser.
New: `Tests/InstantSwiftDataCoreTests/RefreshCostTests.swift` (each step's one-thread cost test).
Test harness (no library change): `MemoryExercises.swift` (E04, E05, E09 and E10 build each line's entity before the
counted passes; `MemoryExerciseSession.waitUntilAcknowledged` waits on the apply waiter) and `MemoryReplayServer.swift`
(`MemoryApplyWaiter` parks waits on continuations the runtime's events resume, instead of polling).

## Amendment 3 (2026-10-24 22:59 EDT, claude-code/fix-memory-1075@ld)

#1147 step 1 landed (red `79707ad5`, green `a9751099`). Claimed now: `Tests/InstantSwiftDataCoreTests/RealSize/RealSizeMeter.swift`,
`RealSizeAllocations.start` and `stop` only (#1072's meter, its holds released at 20:55): one-thread counts take turns
on a lock. The cost tests of a parallel bundle (`LinkSetWriteCostTests`, `RefreshCostTests`,
`OutboxSupersessionSchemaCostTests`) share the one tally, and a second test's `start` reset the first's counts
mid-measurement: `RefreshCostTests`' nested-limit test failed on the Mac mini whenever its hydration test measured at
the same moment, passing alone.

## Amendment 4 (2026-10-24 23:20 EDT, claude-code/fix-memory-1075@ld)

#1147 step 2 landed (red `63b65c80`, green `553cb332`; E03 64-line refresh 22,769 -> 12,671 KB). Step 3 claims
`Sources/InstantSwiftDataCore/InstantLiveJSONParser.swift` (whole file): a received frame's arrays are sized once from a
shared element stack instead of growing by doubling, an escaped string reuses one byte buffer, and the short strings a
frame repeats (entity and attribute ids) share one copy per frame. The frame's parse was about 7,000 of a 64-line
refresh's 21,000 allocations (E01: 111 a line). fix-gate-1074 agreed `reducedServerApplyOperations`' deferred loads
are mine (23:02); that step waits for fix-storage-1076's answer on the fact rows #1121 changes.

## Amendment 5 (2026-10-24 23:40 EDT, claude-code/fix-memory-1075@ld)

#1147 step 3 landed (red `40280360`, green `3e787d2d`). #1153 (a finished line is prepared twice) claims:
- `Sources/InstantSwiftDataCore/InstantRuntime.swift`: `deferredValuesForPreparing` (both overloads) only: a
  `deleteEntityInNamespace` whose namespace's delete can reach no configured deferred attribute needs no throwaway
  preview to find the entities to hydrate (Scribe's final deletes a `liveLines` row, which links to nothing).
- `Sources/InstantSwiftDataCore/TripleIndexes.swift`: `AttributeStore`, one new read-only method (the namespaces a
  delete reaches: its cascades and the entities that lose a link to it).
- `Sources/InstantSwiftDataCore/InstantStore.swift`: a testing counter of prepares in `prepareMutating` only.
New: `Tests/InstantSwiftDataCoreTests/FinalLinePrepareTests.swift`.
#1145 waits: its eviction reads result ownership beside the prune fix-gate-1074 is changing (#1129); proposed on the channel.

## Amendment 6 (2026-10-25 00:02 EDT, claude-code/fix-memory-1075@ld)

#1153 green (red `d85ab9f4`, green `7cabeabf`), pushed after its debug bundle passes. #1147 step 4, agreed with
fix-storage-1076 (channel 23:58: the result build's re-encode and ownership re-read are mine; it keeps #1123):
- `Sources/InstantSwiftDataCore/SQLitePersistenceStore.swift`: `preparedLiveQueryResultSaveWithoutTransaction`,
  `liveQueryOwnershipWithoutTransaction`, `prepareLiveQueryResultSaves`' previous-ownership bookkeeping, and
  `LiveQueryOwnershipIdentity` (private -> internal) only. A refresh's ownership diff compares 128-bit fingerprints
  hashed from the rows' column bytes and from each value's stored text written into one reused buffer; only rows that
  leave or join are made into strings. SQLite's rows stay the truth; no cache.
- `Sources/InstantSwiftDataCore/InstantStoredJSON.swift`: one internal entry that appends a value's stored text to a
  caller's buffer.
- New: `Sources/InstantSwiftDataCore/LiveQueryOwnershipDiff.swift` (the diff, pure, testable on one thread),
  `Tests/InstantSwiftDataCoreTests/LiveQueryOwnershipDiffTests.swift`.
Order: an extraction commit that keeps today's algorithm, a red cost test on it, then the fingerprint green.

## Amendment 7 (2026-10-25 00:23 EDT, claude-code/fix-memory-1075@ld)

#1147 step 4 green (refactor `05242f85`, red `5a0ebe9e`, green `865ad0db`; E03 64-line refresh 16,280 -> 11,160
allocations). #1148 claims `Sources/InstantSwiftDataCore/InstantDiagnostics.swift`: the `record` overloads take
`message` and `metadata` as `@autoclosure` and build them only once the entry will be recorded (outside the lock); a
public `isRecording(_:)` for callers that build metadata ahead; bounding by UTF-8 length first; redaction without a
string per ASCII key. New: `Tests/InstantSwiftDataCoreTests/InstantDiagnosticsCostTests.swift`. Call sites are not
edited; `recordServerApplyGateTimeline` (fix-gate-1074's) builds its metadata ahead, so `isRecording` is offered to it
on the channel.

## Amendment 8 (2026-10-25 01:02 EDT, claude-code/fix-memory-1075@ld)

#1148: red `f1bb302e`; the green passes on the Mac mini. Two changes to amendment 7: the green adds no public
`isRecording(_:)`, because `isEnabled(at:)` (#473) already answers it; and E09's "no sink" pass was never sink-free:
every session's boot registers `RealSizeApplyLog`, a diagnostics handler, so the pass ran at the `.debug` floor with
one handler. Claims `Tests/InstantSwiftDataCoreTests/RealSize/MemoryExercises.swift` (E09 only): the passes stop the
session's apply log, a pass with no sink checks that none is active, and each pass reports whether one was.

## Amendment 9 (2026-10-25 01:33 EDT, claude-code/fix-memory-1075@ld)

#1148 landed (red `9d4ca094`, green `97ed60bc`, E09 fix `63920cb0`). Fresh breakdown on main with #1121's fact table
(Mac mini, release, fixture v3): E03 64-line refresh 11,030 allocations / 11.4 MB; E14 history page 23,979 / 19.5 MB.
S14 puts about 8 MB of a history page in `queryLocally` rebuilding an `AttributeStore` from a sorted copy of all 2,283
attributes, and about 17,000 allocations in the read connection's deferred loads (each row's computed `json`,
`String(cString:)`, one joined batch string, `JSONDecoder`); S03 puts about 3,000 of a refresh's allocations and 4.3 MB
in the store's deferred loads (the same JSON path).

#1150 step 1 claims: `Sources/InstantSwiftDataCore/InstantRuntime.swift` (`queryLocally(_:)` and
`mergingEntitiesOnDisk(into:plan:lookup:attributes:attributeStore:)` only): the read takes the store's own
`AttributeStore` (a copy-on-write value) and hands hydration only the configured attributes;
`Sources/InstantSwiftDataCore/InstantStore.swift` (a new `attributeStoreSnapshot()` only);
`Tests/InstantSwiftDataCoreTests/RealSize/MemoryExercises.swift` (E14's per-page budget, tightened per step toward
#1150's 4 MB). Step 2 (named here before editing): the read connection reads a fact's columns instead of its computed
`json`, with a value reader that inverts `InstantStoredJSON` and falls back to `JSONDecoder`; the store's deferred
loads (#1147) after agreeing their part with fix-storage-1076.
