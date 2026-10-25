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
