# Plan: one actor turn per step on transact, relaunch, and outbox drain (#403)

- **planId:** `2026-10-02-library-79-hops`
- **agentId:** `claude-opus-5.5-library-79` (issue workLog agentId `claude-code/claude-opus-5.5/library-79`)
- **Role:** mower. Fewer actor calls and SQLite transactions for the same durable result; no new public surface.
- **Branch:** `agent/claude-opus-5.5/library-79-hops`, from library-78's head `d95c9625` (the v1.9.0 candidate).
  Main's release plan (2026-10-02) and Michael's authorization ("Publish the library once it's checked fast. Yes.")
  extended it: merge v1.9.0, run the release-gate hold, and publish v1.9.1 from main, with
  `docs/releases/v1.9.1.md` (new, claimed 2026-10-02 15:43 EDT).
- **Goal (Michael, verbatim, 2026-10-01):** "fix this please so it works efficiently as as well as the typescript
  core library"
- **Issue:** https://issues.knophy.com/issues/403 (related: #402, #155, #303)

## Outcome

The three cross-SDK runtime workloads make far fewer actor calls, each counted, with tests that pin the counts:
one transact runs its persistence work in two actor turns instead of about twelve. The write contract is unchanged:
`await transact` means local materialize plus a durable outbox row, offline writes succeed, and nothing assumes one
server answer per transaction (Instant's `combine-transact` merges same-shape queued writes).

## Steps (no code here)

1. Measure first: record every actor call on the three benchmark paths, so before and after are both measured.
2. Add a `run` entry point on `SQLitePersistenceStore` (Point-Free ep362@12:16): several synchronous calls in one
   actor turn, with no other persistence work interleaved between them.
3. Connection status: its six persistence reads in one turn, everywhere it is published.
4. transact: the reads before the save in one turn; the save and the status reads in a second.
5. The server-apply gate's held flag without a hop; no live-session hop when no live transport is configured.
6. Relaunch and drain: batch the persistence calls that sit next to each other.
7. Tests pin the hop counts; ABBA p50 against v1.8.0 and against the base, through `heavy.sh`.
8. Library ADR 0018 (design note and decisions), CHANGELOG and ledger entries, PROGRESS, #403 work log.

## Touching

- `Sources/InstantSwiftDataCore/InstantRuntime.swift`
- `Sources/InstantSwiftDataCore/SQLitePersistenceStore.swift`
- `Sources/InstantSwiftDataCore/AsyncSerialGate.swift`
- `Sources/InstantSwiftDataCore/InstantActorHopInstrumentation.swift`
- `Sources/InstantSwiftDataCore/Outbox.swift` (a one-turn batch replace) and
  `Sources/InstantSwiftDataCore/OutboxSameEntitySupersession.swift` (a transaction-level eligibility check), added
  2026-10-02 09:38 EDT
- `Tests/InstantSwiftDataCoreTests/AsyncSerialGateTests.swift` (the held-snapshot test), added 2026-10-02 10:20 EDT
- The shared transport-date formatter, at main's request (2026-10-02 about 09:50 EDT), as its own commit:
  `Sources/InstantSwiftDataCore/InstantTransportMutation.swift`, new
  `Tests/InstantSwiftDataCoreTests/InstantTransportDateFormatterTests.swift`, new
  `validation/fixtures/transport-date-encoding.json` and `validation/ts-runner/src/transport-date-encoding-fixture.ts`
- A prepared-statement cache on the persistence actor, at main's request (2026-10-02 about 12:05 EDT), as its own
  commit: `Sources/InstantSwiftDataCore/SQLitePersistenceStore.swift` (already claimed) and new
  `Tests/InstantSwiftDataCoreTests/SQLiteStatementCacheTests.swift`, added 2026-10-02 12:08 EDT
- The three next cuts main approved (2026-10-02 13:21 EDT, "do them after v1.9.1 ships, one commit and one ABBA arm
  each"), prepared on the local branch `agent/claude-opus-5.5/library-79-next` and measured by heavy job 4; they land
  here after v1.9.1 ships: `Sources/InstantSwiftDataCore/SQLitePersistenceStore.swift` and `InstantRuntime.swift`
  (already claimed), `Sources/InstantSwiftDataCore/InstantModels.swift` and `BoundedOutboxDelivery.swift` (one
  encoding per save), and new `Tests/InstantSwiftDataCoreTests/SQLiteTurnTransactionTests.swift`,
  `SQLiteBootstrapMigrationTests.swift`, and `InstantEncodedOutboxMutationTests.swift`, added 2026-10-02 14:32 EDT
- `Tests/InstantSwiftDataCoreTests/InstantCrossSDKRuntimeBenchmarkTests.swift`
- `Tests/InstantSwiftDataCoreTests/BenchmarkTests.swift` and `CLITests.swift` (hop pins only; CLITests added
  2026-10-02 11:38 EDT)
- `docs/adr/0018-one-actor-turn-per-step.md` (new)
- `CHANGELOG.md`, `PROGRESS.md`, `docs/audits/commit-changelog.md` (prepend only)

## Conflict check

- `claude-opus-5.5-library-78` claims `InstantRuntime.swift`, `SQLitePersistenceStore.swift`, and the three logs on
  `agent/claude-opus-5.5/library-78`, which is still running its final gates. This branch starts from its final head
  `d95c9625` and never pushes to it; when library-78 merges to main, this branch merges main and resolves there.
  Noted in `agent-presence/_channels/2026-10-02-library-79-hops.md`.
- `AsyncSerialGate.swift`'s last claim is triage-l's finished plan `2026-09-27-triage-l-operation-gate`.
- Library ADR 0017 is the highest number on every remote branch on 2026-10-02 at 09:05 EDT; Scribe's ADR 0018 is a
  different repository.

## #431 (P0, main, 2026-10-03 about 01:00 EDT)

A device that once wrote a single-value attribute never saw another device's later value of it: server facts carry the
triple's created_at, and the store resolved single-value facts last-write-wins by stamp. Fix: the server's facts are
authoritative and only surviving pending writes overlay them, as in Reactor.js; stores 1.9.1 persisted heal on the
first refresh that restates a shadowed slot. Published as v1.9.2 under the same authorization. Touching
`Sources/InstantSwiftDataCore/TripleIndexes.swift` and `InstantRuntime.swift` (already claimed),
`Tests/InstantSwiftDataCoreTests/InstantFastDrainTests.swift`, new `InstantLocalStampShadowsServerTests.swift`, and
new `docs/releases/v1.9.2.md`, added 2026-10-03 01:11 EDT. The speed cuts on
`agent/claude-opus-5.5/library-79-next3` wait and will be measured on the fixed code.

Main, 01:12 EDT: cover slots the server cleared too ("Match Reactor.js here: on a full refresh, a local fact that
isn't pending and that the server doesn't return goes away."), next to the overwritten one, and check the fix against
the pulled iPad store. A cleared slot loses a value no other stored result owns, and only a pending write of a slot (or
of the entity, for a link) protects a retraction, never a write pruned in the same apply. Touching
`Sources/InstantSwiftDataCore/SQLitePersistenceStore.swift` for #431 and new
`Tests/InstantSwiftDataCoreTests/InstantLocalStampShadowsDeviceStoreTests.swift` (skipped unless
`INSTANT_431_DEVICE_STORE` names a pulled store), added 2026-10-03 01:40 EDT.

Round 2 (02:08 EDT) showed slot-level protection for every retraction rebasing four fast-drain cases, so a cleared slot
alone gets it; and main's rule covers slots no result ever held, so a query's `fields` decide which slots a refreshed
result vouches for. New `Tests/InstantSwiftDataCoreTests/InstantLiveQuerySelectedAttributesTests.swift` pins that
reading of the query key, added 2026-10-03 02:15 EDT.

## #436 (P0, main, 2026-10-03 about 09:40 EDT)

Michael's iPad cannot open Scribe: the relation reconciliation at store open throws on a cached transcript result over
8 MiB (8,817,787 bytes in the iPad's pulled store), so every launch fails. Fix: an open-time pass drops a cached result
over its bound, with a warning, and the query refetches it; published as v1.9.3. Touching
`Sources/InstantSwiftDataCore/SQLitePersistenceStore.swift`, new
`Tests/InstantSwiftDataCoreTests/InstantOversizedCachedResultOpenTests.swift`, and new `docs/releases/v1.9.3.md`,
added 2026-10-03 09:48 EDT. The six queued speed and measurement jobs are paused until v1.9.3 is tagged.

## #441 (P1, main, 2026-10-03 about 12:00 EDT)

Recording 040's iPhone showed "Not synced / Instant refused one change": a re-sent write the server had most likely
already applied was refused by Scribe's monotonic updatedAtMs rule after a dropped connection. Production holds its
capture gaps (read only). Fix: a refused re-send resolves as accepted when every slot it sets is covered by a later
accepted write of this device or already holds the same value in a live-query result the server sent after the write
was created; one refused before such a result waits briefly for it. Published as v1.9.4. Touching
`Sources/InstantSwiftDataCore/SQLitePersistenceStore.swift`, `InstantRuntime.swift`, `BoundedOutboxDelivery.swift`,
`InstantModels.swift` (a doc comment), new `Tests/InstantSwiftDataCoreTests/InstantRefusalHeldByServerTests.swift`, and
new `docs/releases/v1.9.4.md`, added 2026-10-03 12:03 EDT.

Main added #445 to v1.9.4 at about 12:35 EDT: the superseded rule as read-only public API for Scribe's Sync view
(launch-recovery's "Clear Superseded Refusals"), shape agreed with launch-recovery:
`InstantSwiftDataClient.supersession(ofFailedMutation:)` and `failedMutationSupersessions()`, returning
`InstantMutationSupersession` with an `InstantSlotCoverage` per write operation. Also touching
`Sources/InstantSwiftData/InstantSwiftData.swift` (the two client methods), `InstantModels.swift` (the new public types),
and new `Tests/InstantSwiftDataCoreTests/InstantFailedMutationSupersessionTests.swift`, added 2026-10-03 13:00 EDT.

## #473 (P0 for 1.9.5, main, 2026-10-03 about 14:10 EDT)

A local write held the iPhone's operation gate for 12 s at 13:17:46 and the recording died; transcription stalled
behind gate backlogs twice. 1.9.5: the diagnostics log file written off the caller's thread, the gate's handoff before
its wait report, named transact phases without a hop, and `pendingMutations(limit:)`/`failedMutations(limit:)` reading
SQLite without the gate. 1.9.6: phone-perf's streaming file download, then hydration and observer materialization off
the gate (#473 items 3-4), then #474 (reconnect promptly after a socket reset). Touching `AsyncSerialGate.swift`,
`InstantDiagnostics.swift`, `InstantRuntime.swift`, `SQLitePersistenceStore.swift`, `InstantSwiftData.swift`,
`InstantDiagnosticsTests.swift` and `InstantInfiniteQueryParityTests.swift` (flushes before reading the log), new
`InstantOperationGateHoldTests.swift` and `InstantPendingMutationsPageTests.swift`, and new `docs/releases/v1.9.5.md`,
added 2026-10-03 14:25 EDT.

## v1.9.7 (main approved 2026-10-03 about 18:05 EDT; #473 items 3-4, freeze-185 items 2, 3, 5 and 7, #482 part C)

The operation gate gets priorities (a local write or an awaited read goes ahead of a server apply, a prune or an
unbounded listing; a waiter moves up one priority every 2 s it waits), a holder past the stall threshold is reported
once, and a snapshot of the gate reads without a hop. A deferred-value hydration reads SQLite without the gate and
checks afterwards that its emission is still current. A local write or server apply commits the store under the gate
and publishes to observers after leaving it, with commits made before a publication published together once; each
commit keeps its info `store.mutation-published` line (Scribe's memory fenceposts and soak sampler read it) and a
`store.publish-summary` line reports publications every 30 s. Apple's SQLite already commits a WAL connection with
`synchronous` NORMAL; the store logs its settings at open. For #482 part C: `InstantWriteFailureKind`,
`InstantWriteRejection`, `InstantWriteFailureClassifying`, `PendingMutation.failureKind`, and
`connectionHealth()` from in-memory counters. Touching `AsyncSerialGate.swift`, `InstantRuntime.swift`,
`InstantStore.swift`, `InstantDiagnostics.swift`, `InstantRuntimeLiveSession.swift`, `SQLitePersistenceStore.swift`,
`InstantSwiftData.swift`, new `InstantWriteFailureKind.swift` and `InstantConnectionHealth.swift`, new
`InstantWriteFailureKindTests.swift` and `InstantOperationGatePriorityTests.swift`, and new `docs/releases/v1.9.7.md`,
added 2026-10-03 19:41 EDT. Rooms (agent/claude-opus-5.5/rooms, 681a0ba9) merges in once its red-green and bench
pass.

## v1.9.8: #474 (P1, main, 2026-10-03; after 1.9.7)

After a socket reset the live session applied every buffered frame of the dead connection before it reconnected (the
Mac applied 125 frames over 18.5 minutes, offline). Fix: when the reader's error arrives, the receive buffer drops the
dead connection's query results (`add-query-ok`, `add-query-exists`, `refresh-ok`), which the next connection's
`add-query` answers replace, as `Reactor.js` drops a replaced transport's messages; the answers to this device's writes
and every other frame are still applied in order. Red test first. Touching
`Sources/InstantSwiftDataCore/InstantRuntimeLiveSession.swift`,
`Tests/InstantSwiftDataCoreTests/InstantLiveConnectionSurvivalTests.swift`, and new `docs/releases/v1.9.8.md`, added
2026-10-03 20:25 EDT.

## v1.9.8 after dev-198 (2026-10-04 14:46 EDT)

dev-198's red run on v1.9.7 failed #474's two tests and #522's as intended, but #516's passed: it read the window when
the model server was idle just after `connect()`, before the kickstart's add-query, so it saw the local window. The
test now waits for the window to show the server's pages. The green run failed `SwiftConcurrencyGuidanceTests`: #474's
`InstantLiveMessage` extension sat between `InstantLiveReceivedFrames`'s SAFETY comment and its `@unchecked Sendable`
declaration; it moves above the documentation. `racingPresencePublishesLeaveTheNewestOnTheWire` failed 1 of 3 runs:
each send writes from its own task, so an older set-presence could pass a newer one. Main's final call (2026-10-04,
after messages crossed): "your ordered send lane is the fix (it matches Reactor.js) ... The rooms agent has paused its
version and will review yours for two holes": no older write may follow the join-room-ok flush (never 6, 5, 6), and
writes still waiting when the room is left must return. Each room's presence writes take one lane in the order the live
session recorded them; the lane and its waiters live off `RegisteredRoom`; a write skips when a presence at least as
new was already written to the same socket; a registration carries an incarnation, so a write that waited across a
leave and a rejoin does not write. Red tests first. Touching
`Sources/InstantSwiftDataCore/InstantRuntimeLiveSession.swift`, `InstantRuntime.swift` (a test accessor),
`Tests/InstantSwiftDataCoreTests/InstantRoomPresenceRuntimeTests.swift` and
`InstantInfiniteQueryLeadingRowsTests.swift`, added 2026-10-04 15:00 EDT, the lane at 15:25 EDT.

## v1.9.9: #540 and #541 (build 91's performance release; main, 2026-10-04)

Main, verbatim: "1.9.9 carries skipping pages a write can't change (with the differential property test), the two map
bounds, and keeping the top row (check upstream first). #491 moves to 1.9.10. No coalescing without an ADR. Aim 1.9.9
at build 91, the performance build, with the soak's publish-summary comparison as its evidence." Upstream cuts every
non-leading page at both server cursors (instaql.ts 752-765; only leading queries are exempt, #2535), and main then
said: "leave #542 at parity with upstream", so #542 is an upstream candidate, not part of 1.9.9.

- #540: a write skips a page it cannot change. For a page whose rows depend only on their own fields, cut by the
  server's cursors (`.ready` page info on a plan with after, before or an offset), a changed row the page does not hold
  is checked against that cut with `boundedRangePosition`; a row outside it, or one that no longer exists or matches,
  cannot enter. A page waiting for the server's cursors, or one the server answered empty, is empty whatever the store
  holds. Pages that keep both ends (`first` or `limit` with `last`) still refresh. A differential property test
  rematerializes every page after each random write and requires each page to equal its last emission.
- #541: the TxIDInterner is rebuilt from the live triples when a prune finds it over twice the live count (a store
  replace already builds a new one), and a live query's acknowledgement revision and outcome are forgotten when the
  query unregisters; revisions come from one counter, so a wait that read a revision before the key was forgotten
  still ends at the next answer.

Touching `Sources/InstantSwiftDataCore/InstantStore.swift`, `TripleIndexes.swift`, `InstantRuntime.swift`, new
`Tests/InstantSwiftDataCoreTests/InstantStorePageSkipTests.swift` and `InstantSessionMapBoundsTests.swift`, new
`docs/releases/v1.9.9.md`, `CHANGELOG.md` and `docs/audits/commit-changelog.md`, added 2026-10-04 11:13 EDT. Red
tests first; branch agent/claude-opus-5.5/library-79-199 from library-79-198 at 07ce2e5d. Also
`InstantRuntimeLiveSession.swift` (an answer says whether a query still holds its key) and new
`InstantLiveQueryAcknowledgementStateTests.swift`, added 2026-10-04 12:05 EDT. Reading paginate, 1.9.8's skip also
misses rows that stop matching (an offset page's window, a limited page's next page), so a page not cut by the
server's cursors now refreshes when a changed row matched before the write or matches after it; the red run on
library-79-199's red commits is to confirm it.

## v1.9.8: #566, the live result JSON written once per 30 s (top library priority; main, 2026-10-04 16:10 EDT)

phone-perf's disk-writes report from Michael's iPhone on build 90 (1.9.7): 1,073.74 MB dirtied in 185 s after launch,
92 of 99 samples in commitServerApplyPlan, which upserts each refreshed query's whole result JSON. Main, verbatim:
"Ship the fix in whichever release can publish first. If adding it to 1.9.8 now (before dev-198b starts) delays 1.9.8
by less than cutting a separate 1.9.9 would, put it in 1.9.8." and "Yes, point 3 is required. Correctness first: a
crash must never leave a fact the server deleted." A refresh whose result did not change writes no JSON; a changed
result's JSON is written at most once per query per 30 s, the newest in memory for every in-session reader; pending
results are written when due, on unsubscribe and close, and through a public flush the app calls on background and
terminate; a result whose JSON waited is marked, and the next bootstrap rebuilds a marked result from its ownership
rows. Red tests first, with a kill between throttled writes. #567 files Reactor's per-key persistence for later.
Touching `Sources/InstantSwiftDataCore/SQLitePersistenceStore.swift`, `InstantRuntime.swift`,
`Sources/InstantSwiftData/InstantSwiftData.swift` (the client's flush) and new
`Tests/InstantSwiftDataCoreTests/InstantLiveQueryResultWriteTests.swift`, added 2026-10-04 16:45 EDT.

## v1.9.9: #563 and #570 (main, 2026-10-04 about 19:05 EDT)

Main, verbatim: "Put the sort fix in 1.9.9; it's the biggest CPU item from the phone. Do both (a) and (b): reuse the
interned many-value when the slot is unchanged, and an allocation-free comparator for when it isn't." and "#563, with
the rejoin case, is fine for 1.9.9 too. If 1.9.9 grows too big to gate tonight, tell me and we'll split it."

- #563: on an open socket, `join-room`, `leave-room` and the reconnect's rejoin take the room's lane, so a leave and a
  rejoin, or a write still in flight and a leave, reach the wire in call order, as `Reactor.js`'s synchronous
  `ws.send` writes them. The rejoin on a new socket went outside the lane too, so a leave made while it was written
  could pass it. Red tests first: a held leave-room and a rejoin, a held set-presence then a leave and a rejoin, and a
  held rejoin on a new socket then a leave.
- #570: a many-cardinality slot's sorted values are kept per entity and attribute and reused while the slot holds
  exactly those values, and a slot that must be sorted is sorted with a comparator that orders exactly as
  `comparableKey` without building strings. Build 88's CPU kill on Michael's iPhone (48 s of CPU in 55 s) spent 26%
  of its samples in this sort: every snapshot of a recording re-sorted all its segment refs. Red tests first: an
  order-equivalence property test and a timed re-materialization of 73 recordings with 1,190 refs each.

Touching `Sources/InstantSwiftDataCore/InstantRuntimeLiveSession.swift`, `InstantRuntime.swift` (a test accessor's
comment), `TripleIndexes.swift`, `InstantStore.swift` (a test accessor),
`Tests/InstantSwiftDataCoreTests/InstantRoomPresenceRuntimeTests.swift`, new
`Tests/InstantSwiftDataCoreTests/InstantManyCardinalityOrderTests.swift` and
`docs/adr/0019-rooms-and-presence-parity.md` (decision 9's open item), added 2026-10-04 19:01 EDT.
Also `Sources/InstantDomainAEVBench/main.swift` and new `ManyRefsBench.swift` (`--many-refs`, #570's measurement at -O), added
2026-10-04 19:40 EDT.

A three-minute time limit on the ten suites (main, 2026-10-05 about 02:10 EDT: "Put a suite-level .timeLimit(.minutes(1))
on the ten suites ... A test stuck on a continuation then fails by name instead of idling."): three minutes, because
`sameProcessOfflineTenThousandEnqueuesKeepResidentBarrierCacheBounded` took 114.6 s in one loaded run. Touching the ten
suites' files (nine in `Tests/InstantSwiftDataCoreTests`, `Tests/InstantSwiftDataTests/MutationDeliveryTests.swift`),
added 2026-10-05 02:15 EDT.

#577, found by #540's differential test in dev-199 (seed 15, step 29, all three green runs): a write that sets every
stored field of a row but one interned a snapshot without that field when the row stores no `id` slot, because the
completeness check counted one `id` slot for every row. Main, 2026-10-05: "Agreed: 1.9.9 waits on #540". The fix keeps
such a snapshot and completes it from the row's slots when the write finishes. Red tests first, in new
`Tests/InstantSwiftDataCoreTests/InstantInternedSnapshotCompletenessTests.swift`. Touching
`Sources/InstantSwiftDataCore/TripleIndexes.swift` (already claimed for #540 and #570), added 2026-10-05 03:40 EDT.
