# Plan 2026-10-31-perf-read-1498: a one-shot read writes its answer only when it changed; an observer keeps its ids

- planId: 2026-10-31-perf-read-1498
- agentId: claude-code/perf-read-1498@ld (tools/agent-run, claude/ld, opus)
- role: mower (the same answers, emissions and hand-overs, for less CPU; no new surface)
- issues: #1498 (first), #1495 (second); from the #1482 audit, findings F12 and F4
- branch: agent/claude/perf-read-1498 (worktree ~/Sync/worktrees/perf-read-1498), landed with ~/Scribe/tools/land

## Why (measured before any change, by the #1482 audit)

Mac mini M4, release, the `recording` contention exercise sampled for 60 s at 1 ms (M6, library code identical to this
plan's base `90582dbd`): `queryOnce` 795 ms of CPU a minute for 60 reads of one unchanged past transcript page, of which
`saveQueryCache` 431 ms (54%), about 7 ms a read, JSON-encoding the whole answer on the persistence actor; the
persistence actor's JSON encoding overall (793-907 ms) costs more than `sqlite3_step` (347 ms). Phone energy ledger:
observerRefresh 0.69-1.05% of a core while recording, the third of the library's costs.

Read in the code before planning (#1498):

- No read answers from `instant_query_cache`, after a relaunch or otherwise. Its readers are the closed connection's
  error (`InstantError.cachedQuery`, checked against the store first) and the public `cachedQuery(_:)` /
  `cachedQueries()` diagnostics. Scribe reads neither. The row must stay what it is today in every field a reader sees:
  the last read's answer, time, revisions and sequence.
- The cache key holds the whole plan (its id included), so one key always names one plan: only the answer, the time,
  the revisions and the sequence can differ between two reads of a key.

## Steps

1. This plan and its claims (plan-only commit), landed on main.
2. #1498 red: a package counter of the answers the query cache encodes (beside `decodedOutboxBodyCount`); a repeated
   read whose answer is unchanged encodes 0; the row a reader then reads equals the one a full write would have left
   (answer, time, store and attribute revisions, sequence); a changed answer, another process's row, a legacy row and
   the closed-connection error behave as today.
3. #1498 green: the answer is stored with a digest of what it shows (SHA-256 over its values and page info, computed on
   the reader's task, not the persistence actor); the time, the revisions and the sequence move to columns. An
   unchanged answer updates those columns only, in one statement conditioned on the stored digest; a changed one is
   encoded on the reader's task and written whole. Readers lay the columns over the stored JSON. A migration adds the
   columns; a legacy row is written whole at its next read. The prune counts the same bytes.
4. Mini, release: M6 before and after (`queryOnce` and `saveQueryCache` per minute); the #1131 and #300 suites and the
   query-cache tests unchanged.
5. #1495 red: `InstantStorePublishMetrics` counts entity-id set builds; a phone-shaped publish exercise (48 observers,
   three 50-row recordings lists with five includes each) prints each publication's time and metrics.
6. #1495 green: the shown entity ids are kept on the observer, built once per installed result, invalidated with it;
   the decision, the splice and the absent-entity check read them. `wasLastHanded`: measured first; a per-emission
   fingerprint goes in only if the exercise shows the equality costing; otherwise the finding is logged with its number.
7. After each green: land, ledger with land --prepend, CHANGELOG, PROGRESS, "READY FOR BUILD" on #1482. No build cut,
   tagged or installed.

Write contract unchanged: transact/save is local materialize and durable outbox only. Nothing is batched, delayed,
throttled, sampled, dropped or limited: every read still answers from the store and leaves its row current before it
returns; every observer is still handed every changed result in the same publication.

## Touching

- Sources/InstantSwiftDataCore/SQLitePersistenceStore.swift (#1498: the query cache's table, save, readers and prune,
  and its counter; not the outbox, the acknowledgement or the live results)
- Sources/InstantSwiftDataCore/InstantRuntime.swift (#1498: the cache write of `materializeLocalQueryOnce` and
  `materializeLocalQueryOnceUnderTheGate` only)
- Sources/InstantSwiftDataCore/InstantQueryAnswerDigest.swift (new, #1498)
- Sources/InstantSwiftDataCore/InstantStore.swift (#1495: `StoreObserver`, `refreshObservers`, `refreshDecision`,
  `splicedEmission`, `wasLastHanded`, `InstantStorePublishMetrics`; not the observation leases or continuations)
- Tests/InstantSwiftDataCoreTests/InstantQueryCacheAnswerWriteTests.swift (new, #1498)
- Tests/InstantSwiftDataCoreTests/InstantPageRefreshEnergyTests.swift (#1495)
- Tests/InstantSwiftDataCoreTests/RealSize/PublishFanOutExercises.swift (new, #1495)
- CHANGELOG.md, PROGRESS.md, docs/audits/commit-changelog.md

## Conflict check

Main at `90582dbd`: perf-send-1492 holds SQLitePersistenceStore.swift's `acceptOutboxMutation` and receipt digest only,
and InstantModels.swift's receipt fingerprint only (this plan changes neither). perf-gate-1491 (#1491, the transact
path) and perf-observe-1493 (#1493 the observation chain, #1494 the server apply) may share InstantRuntime.swift,
InstantStore.swift and SQLitePersistenceStore.swift in other regions: channel 2026-10-31-perf-read-1498. Rebase onto
each landing before a land.

## Amendment 1 (2026-10-31T12:45:57-0400): the hop pins a first or changed answer moves

A first or changed answer is encoded on the reader's task between two persistence turns (the first finds the row does
not hold it; the second writes it), so the persistence actor never encodes a query-cache answer. That is one more
persistence call for those reads: `runtimeWorkloadsPinEveryActorHop`'s relaunch (persistence 6 to 7) and
BenchmarkTests' `query-materialization.todos` (persistence 2 to 3), each a first read on a fresh store, and ADR 0018's
consequence log. Touching (added): Tests/InstantSwiftDataCoreTests/BenchmarkTests.swift and
InstantCrossSDKRuntimeBenchmarkTests.swift (those pins only), docs/adr/0018-one-actor-turn-per-step.md (one line).
