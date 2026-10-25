# Plan 2026-10-24-fix-gate-1074

- **planId:** 2026-10-24-fix-gate-1074
- **agentId:** claude-code/fix-gate-1074@ld
- **role:** mower: each fix moves work out of the operation gate or the frame applier and keeps behaviour; ordered by
  the lab's 21:00 dispatch on #1074 ("nothing waits behind work it does not need").
- **branch:** agent/claude/fix-gate-1074 (worktree ~/Sync/worktrees/instant-fix-gate-1074), each red and green landed on
  main in turn; lib-audit-1072's channel hears "ready for release" for each.

## Outcome (#1074's fixes, worst first)

1. #1131: registering an observer records its registration under the operation gate and sends its `add-query` after
   leaving; the reload of a closed query's stored result reads and decodes outside the gate and commits in a short hold.
2. #1128, #1129: server applies and prunes hold the gate for work in proportion to what they change, not to the whole
   result; the cadence prune leaves the frame applier.
3. #1127: acknowledgements and one-shot answers stop waiting behind long frames ahead of them.
4. #1132, #1133: auth and connection-status reads leave the gate; holders that write no store facts say so.
5. Then #1130, #1134-#1140, #1142, #1143 as measured. Not #1141 (lib-audit-1072's, released in 1.9.37).

Each fix: a red commit (a focused test, or the audit's exercise, failing), then green; before and after measured with
`scripts/contention-exercises/run-contention-exercises.sh` on the Mac mini (fixture version 3), the lines each issue
names; numbers name their store and fixture version.

## Steps

1. #1131 red: a focused test where an observer's `add-query` send stalls and a write must finish meanwhile, and one
   where a closed result's reload must not hold the gate across its read. Green: split the live session's registration
   into a record (under the gate) and a send (after); read the unloaded result before entering.
2. Measure `observers`, `server-apply`, `launch` before and after on the mini.
3. #1129, #1128, #1127, #1132, #1133 in that order, each with an amendment here naming the functions it touches.

## Touching

Changed, by function (amended per issue):
- `Sources/InstantSwiftDataCore/InstantRuntime.swift`: `prepareObservation` (its live registration),
  `observeLiveInfiniteQueryChunk`, `reloadUnloadedLiveQueryResult`, `queryOnceThroughLive`'s registration.
- `Sources/InstantSwiftDataCore/InstantRuntimeLiveSession.swift`: `registerQuery` and a send-after-record entry beside
  it.
- `Sources/InstantSwiftDataCore/SQLitePersistenceStore.swift`: `unloadedLiveQueryResult`,
  `reloadUnloadedLiveQueryResult`.
New: `Tests/InstantSwiftDataCoreTests/InstantObserverRegistrationGateTests.swift`.
Appended: `CHANGELOG.md`, `PROGRESS.md`, `docs/audits/commit-changelog.md`.
Read only: `Tests/InstantSwiftDataCoreTests/RealSize/` (#1072's fixture and meter, #1074's exercises).

## Conflict check

lib-audit-1072 released its holds at 20:55 (TxIDInterner, the outbox functions, `discardFailedMutation`).
fix-memory-1075 (same start commit, 21:05) begins with #1152 in `TripleIndexes.swift`; its later issues (#1147 the
refresh's re-materialization, #1151 reconnect, #1153 transact's double prepare, #1149 launch) may reach
`InstantRuntime.swift`, `InstantStore.swift` and `SQLitePersistenceStore.swift`. Split asked on
`agent-presence/_channels/2026-10-24-lib-audit-1072.md`: this plan names functions, not files, and neither edits the
other's named functions without asking there first.

## Amendment 1 (2026-10-24 21:55 EDT, #1131)

The reload's read moved out of the gate (12dc38bc), but its commit still held the gate about 1.3 s for the `$files`
list's 75,640 facts (1,068 ms in SQLite, 208 ms in the store, measured on the Mac mini at fixture v3). The reload now
commits in bounded chunks, each its own hold, under a per-key registration lease the prune honours. Also touching:
- `Sources/InstantSwiftDataCore/SQLiteReadConnection.swift`: `unloadedLiveQueryResult(key:)` (new).
- `Sources/InstantSwiftDataCore/InstantRuntime.swift`: `InstantLiveQueryRegistrations` (new), the active keys read in
  `performPruneLiveQueryResults`, `readUnloadedLiveQueryResult`, `reloadChunks`.
- `Sources/InstantSwiftDataCore/SQLitePersistenceStore.swift`: `beginUnloadedLiveQueryResultReload`,
  `reloadUnloadedLiveQueryResultChunk` and their result types, replacing `reloadUnloadedLiveQueryResult`.
