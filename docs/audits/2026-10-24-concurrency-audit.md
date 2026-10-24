# Concurrency audit (#1074): one operation gate, one frame applier, and the actors behind them

2026-10-24. Library at `main` after #1072's `4dac9e18` (fixture version 3). The exercises are
`Tests/InstantSwiftDataCoreTests/RealSize/Contention{Exercises,Instruments}.swift`, run by
`scripts/contention-exercises/run-contention-exercises.sh`; every number they print is a `CONTENTION` line, and the
baseline's lines are in `docs/audits/2026-10-24-concurrency-baseline.txt`. Sibling audits: #1072 (cost that grows with
the store), #1075 (memory), #1076 (storage).

## Bottom line

Almost everything the library does passes through one serial `AsyncSerialGate`, the operation gate
(`InstantRuntime.swift:1550`): local writes, local and server reads, observer registration, status and auth reads,
acknowledgements, server applies, prunes and compaction. Every server frame then passes through one serial applier
(`InstantRuntimeLiveSession.swift`). Between long holds both run fast; during one, everything behind it waits the whole
hold, and the long holds are maintenance and server applies that work in proportion to a whole result, and network
sends made while holding the gate.

Measured by the exercises on the generated real-size store (Mac mini, release, two runs: the first run's number, the
second's in brackets):

- **A prune of the closed 75,640-fact `$files` list is one batch holding the gate 1,721 ms [1,757 ms]**, and while it
  runs writes wait 1.5-1.9 s for the gate, their server acknowledgements 1.8-2.5 s, a past transcript read through the
  server 2.7-2.9 s, the status probe 1.8-1.9 s, and local reads 0.56-0.76 s though they take no gate (the batch also
  holds the store and persistence actors). The refresh queued behind the cadence prune applies after 1,815 ms
  [1,844 ms]; the one before it, 45 ms.
- **Between prunes a recording runs fast**: each write's acknowledgement is recorded in 35 ms [40 ms] at the median and
  145 ms [154 ms] at p99, and a past transcript read through the server takes 107 ms at the median, 162 ms [171 ms] at
  p99. Over the 60 s recording the gate is held 7.3 s [7.8 s], 2.7 s [3.0 s] of it by the prune.
- **Registering an observer holds the gate for its socket send** (153 ms per observer over a 150 ms socket, while each
  write's acknowledgement waits 1,259 ms [1,220 ms] at the median) **and for reloading its unloaded result** (1,718 ms
  [1,766 ms] for the `$files` list).
- **The `$files` list's first answer holds the gate 746 ms [726 ms] to plan**, and acknowledgements wait up to
  3,275 ms [3,298 ms] behind it.
- A line written while recording reaches the open page's observer in 15 ms [16 ms] at the median, 782 ms [821 ms] at
  p99. The slow ones are the exercise's own doing, not the library's: its writes are merges (as the shared fixture's
  are), and a merge onto a row the store does not hold yet changes nothing in memory (`TripleIndexes.swift:4953`, as
  upstream's `mergeTriple`), so a new line appears with the server's next echo (#1075 found this).

Measured on the phone (its own `serial-gate.waited` reports, which name only waits of 250 ms or more): a plan of a
server apply held the gate 13,029 ms (build 118) and one catch-up 436,054 ms (build 122, cause unknown); a 6 s prune made
every write wait 5.0 s (build 121); on builds 121, 122, 123, 124 and 126 an observer registration held the gate
5,010-7,821 ms, and `observeAuthSession()` waited a median of 1,679-5,331 ms (10,696 ms on 122).

## Evidence, and what it can and cannot say

- **phone**: the app's own diagnostics. `serial-gate.waited` names a wait of 250 ms or more, its caller, and the whole
  hold of the holder before it, under the phase that holder named last; holds that made nobody wait 250 ms are
  invisible. Sources: a device pull of build 118's run (2026-10-23) and the diagnostics collector for builds 121-126
  (iPhone and Mac, 2026-10-24).
- **exercise**: the committed exercises on #1072's generated store (fixture version 3), shaped like the phone's (352
  recordings, 8,712 transcript lines, 9,455 files or 75,640 `$files` facts, 4,264 device file records, 663 refused
  writes, 48 open and 355 closed results, 2,283 attributes); release build; Mac mini (M4, 10 cores); every wait and
  hold. The phone is slower, so these are lower bounds there; their use is before and after on one machine.
- **code**: read from source and not measured, written "not measured yet". Line numbers are this commit's.
- A first baseline ran on fixture version 2, whose scripted server sent text transaction ids that never passed the
  runtime's integer watermark, so its store held 783 accepted writes with live overlays that every server apply decoded
  (#1072). It measured steady acknowledgements about fifteen times slower and the delivery claim seven times slower than
  this one. It is withdrawn; the issues were corrected to these numbers.

## The anti-patterns, by measured cost while recording

Ranked by how often each runs while Scribe records times what it costs, measured; unmeasured items last. Rates while
recording come from Scribe's energy ledger (builds 113-114, 5.5 h): one sequential writer at 90 transacts a minute while
talking with the live preview, about 63 live observers, three status probes every 5 s, about eleven uploads a minute.

| # | Anti-pattern | Where | While recording | Cost now | Issue |
|---|---|---|---|---|---|
| A1 | A prune batch is a whole result checked one fact at a time, and the cadence prune runs inside the frame applier | `InstantRuntime.swift:4820`, `:6904`; `SQLitePersistenceStore.swift:12777` | every 64th refresh with results (`:434`) | exercise: one 75,640-fact batch 1,721 ms; writes wait 1.5-1.9 s; acknowledgements 1.8-2.5 s. phone: a 6 s prune, every write waited 5.0 s (121); holds 1,385 and 4,168 ms (118) | #1129 |
| A2 | Server applies do O(result + component) work holding the gate | `InstantRuntime.swift:2907`, `:2966`, `:3025`, `:3422`, `:3715`, `:2838` | every refresh and answer | exercise: the `$files` answer's plan 746 ms; echo plans p50 6.6 ms, worst 36 ms. phone: plan 13,029 ms (118); catch-up 3,821-5,151 ms (118, 121); 436,054 ms (122) | #1128 |
| A3 | Observer registration holds the gate across its socket send and an O(result) reload | `InstantRuntime.swift:5379`, `:5391`, `:5512`, `:5664` | every screen; 62 at launch | exercise: 153 ms per send over a 150 ms socket; 1,718 ms for `$files`. phone: 5,010-7,821 ms holds (121-126) | #1131 |
| A4 | One applier for every server frame: acknowledgements and one-shot answers wait out every hold ahead of them | `InstantRuntimeLiveSession.swift:382`; `InstantRuntime.swift:6333` | 2+ frames per write (its `transact-ok`, the echo) | exercise: acknowledgements 1.8-2.5 s in a prune, 1.26 s p50 during registrations, 3.3 s p99 behind the `$files` answer, 145 ms p99 otherwise. phone: one-shot reads waited up to 5,892 ms (123-126) | #1127 |
| A5 | Reads that need no exclusion queue on the gate: the auth session, the connection status | `InstantRuntime.swift:9933`, `:7429`, `:7445` | status every 5 s from 3 callers; ~25 auth observers | exercise: `connectionStatus()` waited 1.8-1.9 s behind the prune. phone: `observeAuthSession()` median 4,206 ms (118), 3,499-5,331 ms (123-126); `observeConnectionStatus()` 2,773-10,697 ms | #1132 |
| A6 | Delivery: two passes per write, each starting with a background retry turn | `InstantRuntime.swift:7135`, `:9286`, `:14097`, `:4890` | 2 passes per write | exercise: 176 claims a minute, 1,151 ms of gate, the largest holder after the prune; 176 retry turns. phone: retry turn waited 8,732 ms (118); claim held 588 ms (118); acceptance waited 2,599-10,921 ms (121-122) | #1130 |
| A7 | Holders that write no store facts never say so, so gate-free hydration (#1006) waits for all of them | `AsyncSerialGate.swift:375`; `InstantRuntime.swift:6135` | every emission with deferred values | exercise: not driven (no deferred attributes in the generated store). phone: 5,282 ms worst (118), 1,450-2,909 ms (121-124) | #1133 |
| A8 | A local one-shot read materializes and writes the query cache holding the gate | `InstantRuntime.swift:6739` | every one-shot read | exercise: 58 holds a minute, p50 16 ms, 965 ms of gate. phone: holds p50 702 ms, worst 1,186 ms (121) | #1134 |
| A9 | Network waits holding the gate: stream create and close wait for the server, appends send 256 KB, a server read sends its query | `InstantRuntime.swift:12317`, `:12444`, `:12494`, `:6269` | per media stream; per server read | exercise: a server read's registration holds p50 12.8 ms (747 ms a minute) on a socket that never waits. phone: held 567 ms (118). `createStream` not measured yet | #1135 |
| A10 | Compaction runs `VACUUM` at background priority and awaits the app's `hold` closure, holding the gate | `InstantRuntime.swift:11436`, `:11484`, `:11511` | after a recording stops; daily while charging | exercise: 175 ms hold, a write waited 150 ms. phone: 7,596 ms (118) | #1136 |
| A11 | Connect takes the operation gate three times inside the connection gate, and nothing receives between init-ok and install | `InstantRuntime.swift:7478`, `:7562`, `:7591` | every launch and reconnect | exercise: not reproduced (connect 104 ms). phone: connection gate held 5,465-6,844 ms (121-126); install waited 3,742-7,432 ms | #1137 |
| A12 | The SQLite actors run on the default executor: blocking SQL holds cooperative threads, and one writer actor serves gated and ungated work | `SQLitePersistenceStore.swift:1075`, `:16954` | every operation | exercise: probes of the persistence and store actors wait 682-793 ms during prune batches and 1.2 s during the `$files` answer (p99 12-17 ms otherwise) | #1138 |
| A13 | No priority donation through the gate; rank comes from the call site, not the task | `AsyncSerialGate.swift:511`, `:455` | every hand-off | not measured yet | #1139 |
| A14 | Cancellation never reaches a server apply's loops; a reconnect and a close wait for the old applier | `InstantRuntime.swift:3422`; `InstantRuntimeLiveSession.swift:792` | every drop, close and auth change | not measured yet | #1140 |
| A15 | Data race: the triple index's transaction-id interner is one box shared by every copy, written off the store actor | `TripleIndexes.swift:746` | a refused write with deferred values | not measured yet (correctness) | #1141 |
| A16 | Per-write task churn and polling waits | `InstantRuntimeLiveSession.swift:2165`; `InstantSwiftData.swift:1461`; `InstantAudioSegmenter.swift:120`; `InstantSyncStatus.swift:125` | every write; explicit waits | not measured yet | #1142 |
| A17 | Diagnostic handlers and status publication inside actor turns and the gate; typed one-shot reads decode on the caller's actor | `InstantDiagnostics.swift:386`; `InstantRuntime.swift:3715` | every write and acknowledgement | not measured yet | #1143 |

Already filed and linked, not filed again: a discard of one refused write copies and reloads the whole store under
the gate (#1103, 2.9 s at the phone's size); the claim's and the supersession tail's scans of the outbox (#1108); the
upload's reload of every file record (#1072, fixed for uploads, reads by id, deletes and evictions in `f83e9448`, which
this baseline includes).

## Designs and hypotheses

Every saving below is a hypothesis; none is measured yet. Each names the baseline lines that will measure it.

### A1. Prunes

`applyLiveRefresh` runs the cadence prune (every 64th refresh with results, `InstantRuntime.swift:4820`) while it still
holds the server-apply gate, so every later frame, acknowledgements included, waits for it. Each batch enters the
operation gate at background priority without cancellation (`:6904`); a batch always takes at least one whole result,
so the 75,640-fact `$files` list is one hold; applying a batch runs one ownership `SELECT` per released fact
(`SQLitePersistenceStore.swift:12777`). The batch also holds the store and persistence actors (both probes waited
682-758 ms during `prune`), which is why a local read, which takes no gate, waited 672 ms. Related: #654, #1011.

Design: run the cadence prune in a coalesced task of its own, started after the server-apply gate leaves; check
ownership once per batch as a set (the released identities in a temporary table, one `NOT EXISTS` join); split a result
larger than the batch budget by entity, so no hold is in proportion to the largest result.

Hypothesis: the worst prune hold at full size falls from 1,789 ms to under 250 ms, a write's wait during a prune from
1,789 ms to under 300 ms, and frames stop waiting for maintenance. Measured by: `prune.during gate.hold
holder=pruneLiveQueryResults(policy:now:)`, `prune.during gate.wait caller=transact(_:createdAt:source:)`,
`prune-inline.during call caller=server.refresh.second.applied` against `...first.applied`.

### A2. Server applies hold the gate in proportion to the result

From its second attempt, a plan holds the gate from seed to plan (`InstantRuntime.swift:2907`), and in that hold it
decodes every replaced result's stored JSON, encodes every restated fact (`:2966`) and fills the plan rows for the
pending-write component (`:3025`). The catch-up (`:3422`, entered without cancellation) commits, then still holds the
gate to delete the plan's rows, publish the connection status and run the app's diagnostic handlers for its own
gate-held record (`:3715`). The echo of a recording's open page is cheap on the generated store (plans p50 6.6 ms,
worst 36 ms; 60 of 144 echoes still peel and replay their component), but the `$files` list's first answer plans for
746 ms, and the phone's plans and catch-ups held the gate for seconds. The phone's 436 s hold is reported under its last
phase, "finish plan", which says nothing about where the time went. Related: #932.

Design: compute the retractions and prepared result saves once, before the first seed, on the read connection (local
writes never move the query-result revision, and the commit checks it); take the seed and the plan in one short hold on
every attempt; leave the gate after the store install and the outbox patch, and finish the plan, publish and record
afterwards; call `markHolderWrites([])` in phases that write no facts; time each phase on a monotonic clock and report
the longest phase, not the last.

Hypothesis: a plan holds the gate in proportion to its pending-write component, not its result: the `$files` answer's
plan falls from 746 ms to under 100 ms. Measured by: `server-apply.files gate.hold holder="plan server apply"`, and
`recording.all gate.hold holder="plan server apply"` staying under 40 ms at worst.

### A3. Observer registration

`observe` holds the gate while it reloads an unloaded result from SQLite (`InstantRuntime.swift:5391`), installs the
observer (which publishes the previous writer's deferred refresh), and sends `add-query` on the socket with a 5 s
timeout (`:5512`). Over a 150 ms socket each registration held the gate 153 ms, and acknowledgements waited 1.26 s at
the median meanwhile. On the phone each long hold came in the same run as a connect that held the connection gate
5.5-6.8 s, which suggests launch; the `launch` exercise, which registers 62 observers while the socket connects, does not
reproduce them (its worst is 41 ms; the in-process socket never stalls a send). Four of the phone's five builds sit just
above 5 s, the send timeout: an inference, not a measurement.

Design: under the gate, record the registration only (the prune keeps `activeQueryKeys`, so the record must land before
the gate is released) and send after leaving; read the unloaded result on the read connection before entering, and
commit it under the gate with `markHolderWrites` naming the restored entities.

Hypothesis: a registration holds the gate under 5 ms whatever the socket does, and the `$files` registration under
100 ms. Measured by: `observers.opening gate.hold holder="observe standard live query"`, `server-apply.files gate.hold
holder="observe standard live query"`.

### A4. One applier for every server frame

The receiver's reader buffers up to 128 frames (`InstantRuntimeLiveSession.swift:382`) and one applier applies them in
arrival order. A `refresh-ok` takes the server-apply gate and two or three operation-gate turns; a `transact-ok` takes
the operation gate; an `add-query-exists` applies nothing but waits its turn; a one-shot read's acknowledgement is
recorded only after its frame's whole apply, and the caller gives up at 5 s (`InstantRuntime.swift:6333`; upstream
`Reactor.js` waits 30 s and resolves `add-query-exists` on arrival). So every long hold anywhere stops acknowledgements
too. When the buffer fills, the reader stops calling `receive()`, and URLSession stops answering pings (#296, in the
file's comment). Related: #998, #307, #653.

Design: an acceptance changes no store fact (the overlay stays until the server's watermark passes it), so accept on
arrival in an ordered lane of its own instead of behind refresh applies; check that ordering against #441 and upstream
`_handleReceive` first. Before applying, drop a queued refresh that a later queued frame restates for the same query (a
refresh carries the whole result; #474 already does this for a dead connection). Resolve `add-query-exists` on arrival,
and take upstream's 30 s or write down why 5 s.

Hypothesis: acknowledgements stop waiting for other holders: their p99 over the whole recording falls from 2,504 ms to
under 300 ms, and during registrations from 1,427 ms to under 300 ms. Measured by: `recording.all call
caller=write.accepted`, `observers.opening call caller=write.accepted`, `server-apply.files call caller=write.accepted`.

### A5. Reads that need no exclusion

`observeAuthSession()` (`InstantRuntime.swift:9933`) takes the gate, without cancellation, only so a reader cannot load
the session, lose a race to a writer and register late; `connectionStatus()` and `observeConnectionStatus()` (`:7429`,
`:7445`) take it for six SQLite reads. Scribe has about 25 auth observers and three status probes every 5 s, and
`waitForAllPendingMutations` polls `connectionStatus()` every 50 ms.

Design: the observer registry owns the latest auth session and connection status (seeded at bootstrap, set by every
writer, returned in the same actor turn as the registration); status reads come from a lock-protected snapshot.

Hypothesis: these calls leave the gate and return in under 5 ms in every exercise. Measured by: no `gate.wait
caller=connectionStatus()` lines, and `recording.all call caller=status.connectionStatus` p99 under 5 ms (now
1,815 ms).

### A6. Delivery

Every write and every `transact-ok` requests a pass (`InstantRuntime.swift:7135`): 176 passes for 88 writes. Each pass
first takes the gate at background priority to look for retryable failures (`:9286`), even when there are none, and
only then claims (`:14097`): a fresh write's time to the network includes that background turn, and a background waiter
ties with a new interactive one only after 4 s in the queue. The acceptance waits at standard priority (`:4890`). The
claim's own scan of the outbox is #1108.

Design: skip the retry turn unless a retryable failure exists (an in-memory flag seeded at connect from
`hasAutomaticFailedMutationRetryCandidate`); claim and accept at interactive priority; after a `transact-ok`, request a
pass only when the last claim stopped at its limit or a write is unclaimed.

Hypothesis: claims fall from two per write to at most one (176 to 88 a minute), and retry turns to none without
failures. Measured by: `recording.all gate.hold holder="claim automatic outbox transport mutations for delivery"` (n)
and `recording.all gate.wait caller="retry one persisted transient mutation failure window"` (n).

### A7. Holders that never declare their writes

Only `transact` and the catch-up call `markHolderWrites`; any other holder counts as writing every entity
(`AsyncSerialGate.swift:375`), so the gate-free hydration of a transcript's deferred text (#1006,
`InstantRuntime.swift:6135`) re-checks behind plans, snapshots, registrations, prunes, claims and VACUUM.

Design: `markHolderWrites([])` on entry in the holders that never commit store facts (about 60), a named set in the
few that do.

Hypothesis: hydration re-checks during a prune or an apply wait about nothing. Measured by: an exercise not written
yet; it needs the generated store's transcript text and words to be deferred, as Scribe's are (asked of #1072).

### A8. Local one-shot reads

`materializeLocalQueryOnce` holds the gate through the state load, the emission, hydration and a JSON write of the whole
emission to the query cache (`InstantRuntime.swift:6739`); every server read ends here too.

Design: answer through the gate-free reader path (#1006) and write the cache row afterwards with its revision check, or
not at all.

Hypothesis: these holds leave the gate (965 ms a minute in `recording`). Measured by: `recording.all gate.hold
holder=materializeLocalQueryOnce(_:enforcesConnectionFreshness:remotePageInfo:)`.

### A9. Network waits holding the gate

`createStream` (`InstantRuntime.swift:12317`) holds the gate while it waits up to 5 s for `start-stream-ok`, which the
applier delivers only after every frame ahead of it, and those frames need the gate: under write load it can wait the
full 5 s and fail (inference from code). `closeStream` (`:12494`) waits for the server's flush the same way;
`appendStreamContent` (`:12444`) sends up to 256 KB under the gate; `queryOnceThroughLive` (`:6269`) registers and sends
its `add-query` under it (p50 12.8 ms a call in `recording`, on a socket that never waits). Related: #329.

Design: commit durably under the gate, leave, then send or wait (the writer's catch-up already re-sends a durable
close, #329); never wait under the gate for an answer the applier delivers.

Hypothesis: opening or closing a stream holds the gate under 20 ms, and a server read's registration under 1 ms.
Measured by: `recording.all gate.hold holder=queryOnceThroughLive(_:)`; for streams, an exercise not written yet (the
scripted server does not answer stream frames).

### A10. Compaction

Scribe starts compaction from `Task(priority: .background)`; the runtime takes the gate at background priority
(`InstantRuntime.swift:11436`), awaits the app's `hold` closure under it (`:11511`; Scribe's hops to the main actor), and
runs `VACUUM` as one uncancellable turn (`:11484`) that never declares its writes. Related: #1015.

Design: run `hold()` and the device checks before taking the gate, and under it re-check only a synchronous flag; run
the gate-held part at utility priority or higher; `markHolderWrites([])` around `VACUUM`.

Hypothesis: the gate hold loses the `hold` closure's time, and hydration stops waiting for `VACUUM`. Measured by:
`compaction.during gate.hold holder=compactLocalCache(policy:holdingWhile:)` with a `hold` that hops to a busy main
actor (a variant not written yet).

### A11. Connect

A connect takes the connection gate (`InstantRuntime.swift:7478`) and, inside it, the operation gate three times at
standard priority; it installs the session (`:7562`) and only then starts receiving (`:7591`), so between `init-ok` and
`startReceiving` no `receive()` is outstanding.

Design: release claims and write `.errored` in one turn; read connect's state without the operation gate; install the
receiver and attributes in one interactive turn right after `init-ok`.

Hypothesis: the connection gate's hold at launch falls to the handshake. Measured by: `launch call
caller=launch.connect` and the phone's `connect live session` holds; the exercise does not yet reproduce the phone's.

### A12. Executors

`SQLitePersistenceStore` (`SQLitePersistenceStore.swift:1075`), `SQLiteReadConnection` and `InstantStore` use the
default executor: every SQLite statement blocks a cooperative-pool thread for its whole turn, and `selectBatchedJSON`
blocks one on a semaphore while a GCD queue decodes (`:16954`). Work moved "off the gate" onto these actors (the #473
observer refresh, #932 planning) still delays the next holder's hops and every gate-free reader. Related: #590.

Design: give the persistence actor and its readers custom serial executors on dedicated dispatch queues (the
GRDB/SQLiteData writer-and-readers shape); split long actor turns; decode small results inline.

Hypothesis: a trivial call on either actor waits under 50 ms at worst during a prune (now 682-758 ms) and the `$files`
answer (now 1,173 ms). Measured by: `prune.during probe executor=persistence`, `prune.during probe executor=store`,
`server-apply.files probe executor=persistence`.

### A13. Priority

Gate waiters park in continuations (`AsyncSerialGate.swift:511`), so a user-initiated caller never raises a background
holder (Swift escalates awaited tasks and actors with queued jobs; a gate holder is neither), and the gate ranks by the
call site's priority (`:455`), not `Task.currentPriority`. Related: #590.

Design: record each holder's task and raise it (`Task.escalatePriority`, SE-0462, where available) when a higher waiter
queues; run long gate-held maintenance at utility priority or higher.

Hypothesis: interactive waits behind background holders shrink on a loaded CPU. Measured by: `compaction` and `prune`
under CPU load (a variant not written yet).

### A14. Cancellation

The undo, replay and catch-up loops of a server apply never check cancellation, and the catch-up enters the gate with
`enter()` (`InstantRuntime.swift:3422`); a session replacement waits for the old receiver's whole tail
(`InstantRuntimeLiveSession.swift:792`), and `closeConnection()` waits on both gates before closing the socket.

Design: check cancellation between pre-commit pages (nothing reaches the store before the commit, and the next
connection restates every result, #474); schedule the reconnect from the reader's error; abort the socket first on
close.

Hypothesis: a reconnect after a drop mid-apply costs backoff plus handshake. Measured by: an exercise not written yet
(drop the socket 1 s into a long apply).

### A15. The interner race

Copies of `TripleIndexes` share one `TxIDInterner` box; `internTxID` (`TripleIndexes.swift:746`) mutates it with no
uniqueness check, and the hydration in `failClaimedMutation`'s path interns into a copy off the store actor while
`transact` interns into the store's own.

Design: copy-on-write for the interner, as the other boxes have, or value-type fields. Measured by: a Thread Sanitizer
test (not written yet) looping `transact` while a refusal of a write with deferred values is handled.

### A16. Task churn and polling

About five `Task`s and two timers per write (`InstantRuntimeLiveSession.swift:2165`, the transport's two per send, the
pump, the deadline wake); six to eight forwarding tasks per emission per live `@Fetch`; `waitForAllPendingMutations`
polls every 50 ms (`InstantSwiftData.swift:1461`); `InstantAudioSegmenter.append` polls readiness every 5 ms while
recording (`InstantAudioSegmenter.swift:120`); the progressive media loader polls the server every 2 s and can outlive
its owner; `InstantSyncStatusState`'s observation task never ends (`InstantSyncStatus.swift:125`).

Design: one writer task per socket draining a send mailbox; event-driven waits on the lifecycle the runtime already
publishes; `requestMediaDataWhenReady` for the segmenter; a `deinit` that cancels.

Hypothesis: task creations per write fall from about 5 to about 0. Measured by: a task count per `transact` (not
written yet).

### A17. Diagnostics, status publication and the main actor

App diagnostic handlers run inline inside library actor turns (`InstantDiagnostics.swift:386`), one of them under the
gate (the server apply's gate-held record, `InstantRuntime.swift:3715`); a connection status is published per write and
per acknowledgement without de-duplication, and `InstantSyncStatusState` sets six `@Published` fields each time; typed
one-shot reads decode every row on the caller's actor, the main actor from a view.

Design: hand accepted entries to one utility-priority consumer; publish only changed statuses; decode typed reads in a
`@concurrent` function.

Hypothesis: not sized yet. Measured by: `recording.all probe executor=store` with five no-op handlers against none (a
variant not written yet).

## The exercises

Each runs one real-size session under a load of its own: either Scribe's recording load, or the focused load (a line
write and a local read every 100 ms, the status probe every 250 ms). All run with
`scripts/contention-exercises/run-contention-exercises.sh` (release, `INSTANT_CONTENTION=1`; `--only` picks some).

| Exercise | Drives | Measures |
|---|---|---|
| `recording` | 60 s of Scribe's recording at the ledger's rates: one writer at 90 transacts a minute (the duration every 8th slot), the server's echo of the open page, a past transcript read through the server and one read locally every second, status probes every 2.5 s, an upload every 5.5 s, 62 open observers; a prune a quarter of the way in | A1, A2, A4-A6, A8, A9, A12 |
| `prune` | the prune of every closed result, the 75,640-fact `$files` list among them | A1, A12 |
| `prune-inline` | the cadence prune as production runs it: the `$files` list closes and two refreshes are queued; the first one's prune runs in the applier | A1, A4 |
| `server-apply` | the `$files` list's first answer (75,640 facts), then a 256-line refresh | A2, A3, A4, A12 |
| `observers` | 12 observers opened one after another over a socket whose every send takes 150 ms | A3, A4 |
| `compaction` | `VACUUM` of the real-size store from a background task | A10 |
| `launch` | 62 observers, 7 auth-session and 5 connection-status streams registered while the socket connects | A3, A5, A11 |

Each exercise prints, per window: `gate.wait` per caller kind and priority; `gate.hold` per holder, and by the phase it
named last; `gate.behind`, each caller's wait split among the holds it spanned; a `probe` per executor (persistence,
store, main); `call` per caller kind, the wall time the app sees, including `write.accepted` (until a write's server
acknowledgement is recorded) and `observer.lag` (until the open page's observer shows a write); `prune.batches`, what the
window's prunes removed, so a run whose prune removed nothing is visible.

## Baseline

`docs/audits/2026-10-24-concurrency-baseline.txt` holds every line of two runs back to back (2026-10-24 18:01 and 18:03
EDT, Mac mini M4, one-minute load 14.7 and 12.4 from other jobs), on fixture version 3. The exercises ran at commit
`287f77d1`; the exercises' commit on `main` adds only `@discardableResult` to their timing helper. Worst cases and medians of tens of milliseconds or
more agree within about 15% between the runs; medians of a few milliseconds vary more (a line write's, 4.1 against
7.6 ms):

| Line | Run 1 | Run 2 |
|---|---|---|
| `prune.during gate.hold holder=pruneLiveQueryResults(policy:now:)` worst | 1,789 ms | 1,874 ms |
| `prune.during gate.wait caller=transact(_:createdAt:source:)` worst | 1,789 ms | 1,874 ms |
| `prune-inline.during call caller=server.refresh.second.applied` (first) | 1,815 (45) ms | 1,844 (46) ms |
| `recording.all call caller=write.accepted` p50 / p99 | 34 / 2,504 ms | 37 / 2,394 ms |
| `recording.steady call caller=write.accepted` p50 / p99 | 35 / 145 ms | 40 / 154 ms |
| `recording.all call caller=read.queryOnce` p50 / p99 | 108 / 2,856 ms | 112 / 2,736 ms |
| `recording.all call caller=observer.lag` p50 / p99 | 10 / 782 ms | 9 / 821 ms |
| `recording.all gate.hold` claim n, p50, total | 176, 5.3, 1,151 ms | 176, 4.7, 1,200 ms |
| `server-apply.files gate.hold holder="plan server apply"` | 746 ms | 726 ms |
| `server-apply.files gate.hold holder="observe standard live query"` | 1,718 ms | 1,766 ms |
| `observers.opening gate.hold holder="observe standard live query"` p50 | 153 ms | 153 ms |
| `observers.opening call caller=write.accepted` p50 | 1,259 ms | 1,220 ms |
| `compaction.during gate.hold holder=compactLocalCache(policy:holdingWhile:)` | 175 ms | 181 ms |

## Not reproduced, not explained, not covered

- The phone's 5,010-7,821 ms observer holds and 5,465-6,844 ms connection-gate holds, which came together in each run:
  on the generated store the `launch` exercise holds 41 ms and connects in 104 ms. Its socket never stalls a send, and
  Scribe's own observers include about twenty `$users` access queries with nested includes the generated account does
  not have.
- The phone's 13,029 ms plan and 436,054 ms catch-up: the generated store's echo plans hold under 40 ms. What the
  phone's applies restated, and where the 436 s went, was not captured.
- Writes as Scribe makes them: the write lane merges each line, as the shared fixture's helpers do, and a merge onto a
  row the store does not hold changes nothing in memory, so a new line waits for the server's echo (that is the
  `observer.lag` p99 of 782-821 ms) and the link set, cascade preview and index work of Scribe's typed inserts never
  run (#1075). Transact's own costs here are therefore lower bounds; the exercise's writes should become Scribe's
  (an insert linked to its recording, the in-progress line deleted), with a new baseline.
- The hydration path (A7): the generated store has no deferred attributes, so neither the gate-free re-check nor
  transact's deferred-value load runs.
- Stream creation and close (A9): the scripted server does not answer stream frames.
- The instruments add four diagnostic handlers (Scribe installs five or more); they run in every exercise, before and
  after a fix alike.

## Issues

One per anti-pattern, #1127-#1143, linked to #1074 and #1072; each names its exercise and its baseline lines. They were
filed in the version 2 ranking and corrected to this one: A1 #1129, A2 #1128, A3 #1131, A4 #1127, A5 #1132, A6 #1130,
A7 #1133, A8 #1134, A9 #1135, A10 #1136, A11 #1137, A12 #1138, A13-A17 #1139-#1143. Related, filed before: #1103 (a
discard reloads the whole store), #1108 (the claim's outbox scan), #998 (writes reaching the server late), #932 (server
applies wedging delivery), #653 (the cost of one write's round trip), #1006 (gate-free transcript reads).
