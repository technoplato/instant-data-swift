# Plan 2026-10-31-perf-observe-1493: one stream per observation, fewer turns per server frame

- planId: 2026-10-31-perf-observe-1493
- agentId: claude-code/perf-observe-1493@ld (tools/agent-run, claude/ld, opus)
- role: mower (the same emissions, errors, frames and writes, in the same order, for fewer tasks, streams and turns;
  no new public surface)
- issues: #1493 (first), #1494 (second); from the #1482 audit, findings F2 and F3
- branch: agent/claude/perf-observe-1493 (worktree ~/Sync/worktrees/perf-observe-1493), landed with ~/Scribe/tools/land

## Why (read from source at 5d772e41, measured by the #1482 audit)

#1493: a live observation with a live transport reaches its consumer through two `liveObservationLease` forwarders
(a task and a stream each), `reportingLiveQueryErrors` (three tasks, an unbounded events stream and an output stream)
and, on the typed path, the `fetchSubscription` bridge task and `map`'s task, before the wrapper's own task: five
runtime tasks per live query and up to three more on the typed path, every emission resumed by each. #1494: a frame's
apply plans in five to eight persistence turns (retractions, saves, protection, the plan's begin, a body page each way)
and the applier hops onto the live session four times per frame. M1d (mini, release, the recording exercise): 149 frames
a minute, "catch up server apply" p50 1.46 ms, "plan server apply" 22 holds p50 2.65 ms.

## Steps

1. This plan and its claims (plan-only commit), landed on main.
2. #1493 red: a focused test counts the library tasks alive per open observation (raw `observe`, typed `subscribe`,
   `FetchAll`) through one counted entry point every observation-path task starts from, and pins 0 runtime tasks per
   observation and 1 per `FetchAll` (the wrapper's own consumer); today 5 and 7. The #360 tests
   (InstantLiveQueryErrorRecoveryTests, InstantLiveQueryErrorSubscriptionTests) and the #394 release tests stay as they
   are.
3. #1493 green: the store yields into the observation's output, which also takes the query's server error under the
   same lock (the latest emission re-stamped when the error changes; a new emission carries the current error), so the
   error stage's three tasks and both forwarders go; the release-on-drop token stays on the consumer stream (#394);
   deferred hydration runs in the consumer's pull; the typed decode and `map` run in the consumer's pull too
   (`FetchSubscription` keeps its `AsyncThrowingStream` iterator). The wrapper publishes each member's mutation only
   when that member changed (a guard, not a filter). Whether `objectWillChange` can go is decided by reading the
   `publisher` API and Sharing's prior art; if it cannot, the finding is logged on #1493, not dropped.
4. #1493 measurement: an exercise with 48 live observers, release, on the mini: alive tasks (xctrace Swift
   Concurrency, SwiftAliveTaskCountAll) and the wall time from `publishCommittedChanges` to each wrapper's value,
   before and after on the same machine, recorded on #1493.
5. #1494 red: `runtimeWorkloadsPinEveryActorHop` gains a server-refresh workload (one refresh-ok restating a 50-row
   list) with every persistence call of the server apply recorded first, so today's count is complete; pinned at the
   target. Green: the store-free planning reads in one persistence read turn, the plan's begin with its first body
   page in one turn, and in the applier the admission, the record and the delivery check in one live-session turn
   (two hops a frame: admit, finish). Same reads, same order, same revision checks. The server-apply exercise's
   attempts per frame under write load before and after, recorded on #1494.
6. After each green: land, ledger with land --prepend, "READY FOR BUILD" on #1482. No build cut, tagged or installed.

Write contract unchanged: transact/save is local materialize and durable outbox only. Nothing is batched, delayed,
throttled, sampled, dropped or limited.

## Touching

- Sources/InstantSwiftDataCore/InstantRuntime.swift (#1493: `prepareObservation`, `observeLiveInfiniteQueryChunk`'s
  observation wiring, `reportingLiveQueryErrors`, `hydratingDeferredValues`, `liveObservationLease`,
  `liveObservation`, `InstantObservationConsumerStream`, `liveInfiniteQueryChunkObservation`; #1494:
  `performApplyServerTransaction`'s planning reads and plan begin, `recordActorHop` calls of the server apply)
- Sources/InstantSwiftDataCore/InstantLiveQueryErrors.swift (#1493: the registry writes into each observation's output)
- Sources/InstantSwiftDataCore/InstantStore.swift (#1493: `observeLease`, `registerObserver`'s yield, `StoreObserver`'s
  continuation field and `handOver`'s yield line only; not `refreshDecision`, `splicedEmission` or `wasLastHanded`,
  which perf-read-1498's #1495 owns)
- Sources/InstantSwiftDataCore/InstantObservationOutput.swift (new, #1493)
- Sources/InstantSwiftData/InstantSwiftData.swift (#1493: `fetchSubscription(from:...)`, `FetchSubscription.map`,
  `subscribeQueryEmissions`, `FetchStorage`'s publish, `runFetchStorageSubscriptionTask`)
- Sources/InstantSwiftDataCore/InstantRuntimeLiveSession.swift (#1494: `startReceiving`'s applier loop,
  `applierMayApplyNextFrame`, `record`, `canDeliverReceiverEvent`; not the send path, which perf-send-1492 owns)
- Sources/InstantSwiftDataCore/SQLitePersistenceStore.swift (#1494: the server apply's planning reads and
  `beginServerApplyPlan` only)
- Sources/InstantSwiftDataCore/InstantCrossSDKRuntimeBenchmark.swift (#1494: the server-refresh workload)
- Tests/InstantSwiftDataCoreTests/InstantObservationTaskCountTests.swift (new),
  Tests/InstantSwiftDataTests/InstantFetchObservationTaskCountTests.swift (new),
  Tests/InstantSwiftDataCoreTests/InstantCrossSDKRuntimeBenchmarkTests.swift (the new pin),
  Tests/InstantSwiftDataCoreTests/RealSize/ObservationChainExercises.swift (new, the 48-observer exercise)
- scripts/contention-exercises/ (a runner for the observation exercise under xctrace, new file)
- CHANGELOG.md, PROGRESS.md, docs/audits/commit-changelog.md

## Conflict check

Main at 7d54c13a. perf-send-1492 owns the live session's send path and left `startReceiving`, `record` and
`canDeliverReceiverEvent` to #1494 (its channel). perf-read-1498 (#1495, its plan on main) edits InstantStore's per-publish decision
(`refreshDecision`, `splicedEmission`, `wasLastHanded`, a cached id set on `StoreObserver`): this plan changes only the
type of `StoreObserver.continuation` and the two lines that yield through it, so the two meet on `StoreObserver`'s
field list only. perf-gate-1491 (#1491) edits the transact path: disjoint. Channel:
agent-presence/_channels/2026-10-31-perf-observe-1493.md. Rebase onto each landing before a land.

## Amendment 1 (2026-10-31, claude-code/perf-observe-1493@strangelearning): #1494 part 2

Why: #1494's first green (4f2e76e9) did F3's steps 1 and 3. Step 2, the plan's begin with its first body page in one
turn, became "no body page when the plan holds no body", which leaves a plan that holds a body as it was. Reading the
passes for step 2 shows more of the same split: each body pass reads one more page after its last row (a page reports
its last row's position, not whether it was the last, and a page with no rows checks nothing), the resident patch pass
does the same under the operation gate, the reduction's context is a store-free planning read in a turn of its own
after the other three, and the plan's end and the connection status read are two gate-held turns after the commit.
The exercises report which frames retried but not where their attempts went stale, so a before and after cannot say
whether fewer turns meant fewer stale attempts.

Steps (no code here):

7. Red: a server apply's gate-held event names the stage at which each earlier attempt went stale; a focused test makes
   the first attempt stale with a local write after its seed and expects the stage.
8. Green: the stage names in that event and in the exclusive fallback's; the contention exercise's server.apply line
   counts them per path.
9. Red: `runtimeWorkloadsPinEveryActorHop`: the server-refresh workload pinned at six persistence turns (the seed; the
   planning reads with the reduction's context; the plan's begin; the catch-up; the commit; the plan's end with the
   status read), and the same refresh over a pending local write in its component pinned at its target.
10. Green: the reduction's context read rides the planning reads' turn; the plan's begin returns its first reverse body
   page when the plan holds a body and its revisions are the seed's; a body or resident-patch page that read its last
   row says so and no pass reads past it; the plan's end and the status read share one turn. The same reads less the
   empty pages, in the same order, with the same revision and row checks.
11. Measured on the mini, one interleaved job (before #1494, part 1, part 2): attempts per frame, the stale stages, the
   gate holds and write.line, recorded on #1494; then land, ledger, READY FOR BUILD on #1482.

Touching (amendment 1):

- Sources/InstantSwiftDataCore/SQLitePersistenceStore.swift: `beginServerApplyPlan`'s first page,
  `loadServerApplyBodyPage(WithoutTransaction)`, `loadServerApplyResidentPatchPage` and the last-page flag of their
  page types only
- Sources/InstantSwiftDataCore/InstantRuntime.swift: `performApplyServerTransaction` (its passes, the plan's end and
  status read, the stale stages), `reducedServerApplyOperations`' context read, `recordServerApplyGateTimeline`'s
  metadata only
- Tests/InstantSwiftDataCoreTests/RealSize/ContentionExercises.swift: `reportApplies`' stale stages only (perf-send-1492
  holds the recording exercise's energy line; disjoint)
- Tests/InstantSwiftDataCoreTests/InstantServerApplyGateWorkTests.swift: one test, the stale stage
- Tests/InstantSwiftDataCoreTests/InstantBoundedServerApplyRebaseTests.swift and InstantEnergyMeterTests.swift: call
  sites of the plan's begin only, if its result's shape changes

## Amendment 2 (2026-10-31, claude-code/perf-observe-1493@strangelearning): #1494's docs

12. docs/swift-concurrency-guidance.md, Performance Rules: one paragraph, a step's reads share one persistence turn
   and a paged read says when it held its last row (#1494). docs/adr/0018-one-actor-turn-per-step.md: one consequence
   line with #1494's measured turns.
