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

## Amendment 2 (2026-10-24 23:00 EDT, #1131 then #1129)

#1131: the deferred add-query let an observation that ended first put remove-query alone on the wire; the live session
records the generation whose add-query a registration owes, and `unregisterQuery` sends it first. Also touching, in
`InstantRuntimeLiveSession.swift`: `unregisterQuery`, `reconcileQueryMembership` (clears the owed generation),
`RegisteredQuery`.

#1129 (next): the cadence prune leaves the frame applier for a coalesced task of its own; a prune batch checks ownership
once per batch, and a result larger than the batch budget is released over several batches. Touching:
- `Sources/InstantSwiftDataCore/InstantRuntime.swift`: `applyLiveRefresh`'s cadence call, a new task owner for the
  cadence prune and its close latch (`closeConnection`, `exactCloseBackgroundTaskIdleState`), `pruneLiveQueryResults`,
  `performPruneLiveQueryResults`, `pruneLiveQueryResultsBatch`.
- `Sources/InstantSwiftDataCore/SQLitePersistenceStore.swift`: `liveQueryResultPruneBatch`,
  `applyLiveQueryResultPruneBatch` and their `WithoutTransaction` bodies, `liveQueryTripleHasOwnerWithoutTransaction`
  or a set-based check beside it, `InstantLiveQueryResultPruneBatch` and its application type.
- `Sources/InstantSwiftDataCore/InstantRuntimeExactTaskOwner.swift`: `InstantRuntimeExactCloseIdleState` (one owner).
- New: `Tests/InstantSwiftDataCoreTests/InstantPruneOffTheApplierTests.swift`.

## Amendment 3 (2026-10-24 23:00 EDT): release ownership

The lab made fix-gate-1074 the library's release owner from 1.9.39 (lib-audit-1072 finished at 20:28): versions, their
release documents and tags, and the Scribe and Playback pins on Scribe's main (pin files only, then a changelog line).
Also touching then: `docs/releases/v1.9.39.md` (new) and later versions' documents.

## Amendment 4 (2026-10-25 00:47 EDT, #1129's second slice)

A prune batch checks at most a batch of its released facts (whole entities) and leaves the rest to the next batches;
ownership is read once per 500 entities; the results a batch may drop are decoded on the read connection first. A
release spread over batches is crash-safe: only unloaded results are spread, the batch marks them in
`instant_sync_metadata` with their removal, the batch that checks the last of their facts clears the marks, and
opening the store finishes a marked release from the results' stored copies. Also touching:
- `Sources/InstantSwiftDataCore/SQLitePersistenceStore.swift`: `bootstrap(queryCachePruningPolicy:now:)` (one call),
  `collectUnloadedLiveQueryResultsWithoutTransaction` (keeps a marked copy), `releaseLiveQueryResultFactsWithoutTransaction`,
  `liveQueryOwnershipWithoutTransaction(entityIDs:)`, `applyReleasedLiveQueryResultFacts`,
  `liveQueryResultPruneCandidates`, `finishInterruptedLiveQueryResultRelease` and the marker helpers (new),
  `deferredLiveQueryResultJSONMarkerPrefix` (no longer private).
- `Sources/InstantSwiftDataCore/SQLiteReadConnection.swift`: `storedLiveQueryResults(keys:)` (new).

## Amendment 5 (2026-10-25 01:16 EDT, #1128's first slice)

A server apply's retry plans holding the operation gate (#932); it decoded each restated result's stored copy for its
retractions and encoded each fact for its save again there (746 ms for the `$files` list's first answer). The first
attempt now works out the saves before the retractions' protection (which a local write's outbox revision makes
stale), and a retry at the same query-result and attribute revisions reuses both. Touching
`Sources/InstantSwiftDataCore/InstantRuntime.swift`: `performApplyServerTransaction` (its attempt loop's planning),
a new `InstantServerApplyRestatedRevisions`, and a testing hook in `InstantRuntimeConfiguration`
(`onServerApplyRestatedResultsWorkedOutForTesting`); `Tests/InstantSwiftDataCoreTests/InstantServerApplyGateWorkTests.swift`
(one test and a helper actor). Branch `agent/claude/fix-gate-1128`; red `8bb9785d` (local).

## Amendment 6 (2026-10-25 02:27 EDT, #1129's third slice)

What is left of the `$files` batch's 397 ms is the cascade delete of its 75,640 ownership rows (149.72 ms) and its
commit (96.28 ms). A closed result larger than a batch is no longer deleted from `instant_live_query_results`: after
its copy goes to `instant_unloaded_live_query_results` (7 ms, as today), its row is re-keyed out of its query key's way
(`released-result:<query_id>`, its JSON emptied) and keeps its ownership rows. Each later batch deletes the next whole
entities of that row's ownership rows (up to the budget), checks those facts in the same transaction, and drops the
row once none are left. The released row is its own durable record, so a crash leaves it for the next prune (the
bootstrap prune dismantles it whole); a save, a reload or the collector of the same key works as today, against a key
the released row no longer holds; and every ownership check counts the released row's rows until they are checked.
The release marker of amendment 4 is no longer written; opening the store still finishes one an earlier build left.
No schema change. Touching `Sources/InstantSwiftDataCore/SQLitePersistenceStore.swift`: `applyLiveQueryResultPruneBatchWithoutTransaction`,
`liveQueryResultPruneBatchWithoutTransaction` and `loadLiveQueryResultRowsWithoutTransaction` (released rows apart),
the readers that list every stored result (the JSON size listing, the result counts), new released-row helpers, and the
bootstrap step; `Sources/InstantSwiftDataCore/InstantRuntime.swift`: `pruneLiveQueryResults`,
`pruneLiveQueryResultsBatch`, `pruneReleasedLiveQueryResultFacts`, the bootstrap prune's call; tests in
`InstantPruneOffTheApplierTests.swift`. #1122 (the copy's own log frames) goes back to fix-storage-1076.

## Amendment 7 (2026-10-25 04:11 EDT, #1132)

`connectionStatus()`, `observeConnectionStatus()` and `observeAuthSession()` stop taking the operation gate. The status
and session observer registries keep the latest value they published (seeded at bootstrap), so a registration takes it
in the same actor turn as any publish and can neither miss one nor register late; `connectionStatus()` returns that
latest status, and falls back to today's read (and republishes) when no status was published yet or the last publish
failed (`try?` today). A test holds every status change to "the published status equals a fresh read". Touching
`Sources/InstantSwiftDataCore/InstantRuntime.swift` (the three calls, `publishConnectionStatus*`, bootstrap's first
publish, the auth publishers), `Sources/InstantSwiftDataCore/InstantSnapshotObservers.swift` (a latest value per key)
and the auth session observers' type; the tests that hold the gate through
`onAuthSessionObservationHoldsOperationGateForTesting` move to a holder that still takes the gate.

## Amendment 8 (2026-10-25 05:40 EDT, #1133)

A hydration's re-check waits for the operation gate's holder unless the holder named what it writes, and only transact,
the server apply's commit and a closed result's reload name theirs, after they enter: so it waits for prunes, claims,
plans and the cache's VACUUM, which write no store facts it read. A holder now says what it writes as it takes the gate
(`AsyncSerialGate.enter(...writes:)`, set on handoff, so no holder reads as writing everything between its entry and its
first mark), and these say none: the server apply's snapshot, plan and catch-up holds, the acknowledgement, a standard
observation's registration, the two local reads, the transient-retry window, an upload's record, the VACUUM, the
delivery claim, the status and session reads' fallbacks and bootstrap's seed. A prune batch names the entities whose
facts it releases, then none after its store commit. Adopting another connection's SQLite writes into the hot store reads
as writing anything, whatever its holder named. Touching `Sources/InstantSwiftDataCore/AsyncSerialGate.swift` (enter,
leave, acquire, waiters), `Sources/InstantSwiftDataCore/InstantRuntime.swift` (those holders' entries, the gate helpers,
`adoptPersistedStoreIfNeeded`, the prune batch functions and a test hook in the prune loop), a new
`Tests/InstantSwiftDataCoreTests/InstantHydrationRecheckHolderTests.swift`, and
`Tests/InstantSwiftDataCoreTests/RealSize/ContentionExercises.swift` (a `recording-deferred` exercise: `recording` with
Scribe's configuration, segment text and words deferred). Measured by `recording-deferred`'s
`gate.wait caller="check hydrated deferred query emission"` on the Mac mini, before and after.

## Amendment 9 (2026-10-25 06:05 EDT, #1130)

A write's delivery takes two pump passes, each opening with a retry turn under the operation gate at background
priority: its own pass, and the one its `transact-ok` asks for, which finds nothing to claim. A pass now asks whether a
retryable failure exists before it takes the gate for the retry window (`hasAutomaticFailedMutationRetryCandidate`,
read without the gate, as the connection's opening already does), and a `transact-ok` asks for a pass only when a row
waits to be claimed (a read-only `hasAutomaticDeliveryCandidate()` beside the claim's own
`hasAutomaticDeliveryCandidateWithoutTransaction()`, the same query). The deadline wake, a connection's first pass, a
write's own pass and a refusal's pass are unchanged, so an expired claim is still reclaimed at its deadline. Touching
`Sources/InstantSwiftDataCore/InstantRuntime.swift` (`runAutomaticMutationPumpPass`, the `transactOK` case of the live
event handler), `Sources/InstantSwiftDataCore/SQLitePersistenceStore.swift` (that read-only wrapper only, in the outbox
reads: noted for fix-storage-1076 on the channel) and a new `Tests/InstantSwiftDataCoreTests/InstantDeliveryPassTests.swift`.
Measured by `recording`'s delivery claim and retry-window counts on the Mac mini, before and after.

## Amendment 10 (2026-10-25 06:45 EDT, #1134)

A one-shot read (`queryOnce`, local or through the server) ends in `materializeLocalQueryOnce`, which holds the
operation gate through the state load, the emission, its hydration and the query-cache write. It now answers as the
local read does (#1006): a local observation's first answer from the in-memory store, hydrated with the gate-free
re-check, validated against the store's own attribute index; the cache row is written afterwards, tagged with the
installed revisions read before the answer, and the save's revision check skips it when a write landed meanwhile (a
writer saves SQLite before it commits the store, so a row whose revisions still match pairs with its answer). It adopts
no other connection's writes, as the local read does not; the closed-connection error path keeps its gated read of
the stored result. Touching `Sources/InstantSwiftDataCore/InstantRuntime.swift` (`materializeLocalQueryOnce`,
`firstLocalAnswer`) and a new `Tests/InstantSwiftDataCoreTests/InstantOneShotReadGateTests.swift`. Measured by
`recording`'s `gate.hold holder=materializeLocalQueryOnce(...)` and its reads' latencies on the Mac mini.

## Amendment 11 (2026-10-25 07:30 EDT, #1136)

Compaction asks the app's hold closure twice, the second time under the operation gate, so the gate is held while the
closure runs (the consuming app's hops to the main actor) as well as during the VACUUM. It now asks the app once,
before the gate; under the gate it re-checks only what it can read at once: cancellation, the device's heat and power,
and the volume's room. Touching `Sources/InstantSwiftDataCore/InstantRuntime.swift` (`compactLocalCache(policy:holdingWhile:)`
and `localCacheCompactionHold`), a new `Tests/InstantSwiftDataCoreTests/InstantCompactionHoldTests.swift`, and
`Tests/InstantSwiftDataCoreTests/RealSize/ContentionExercises.swift` (a `compaction-main-hop` exercise: the same
VACUUM with a hold closure that hops to a main actor kept busy in 30 ms slices). Measured by its
`gate.hold holder=compactLocalCache(policy:holdingWhile:)` against `vacuum_ms` on the Mac mini, before and after.
