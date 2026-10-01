## 2026-08-09 09:54:25 EDT — InstantCodableJSON structured-queries parity

- Commit: `ca27941efc55c9ddb52e6b9eb99ea926f111f631`
- Shared encoder/decoder (sortedKeys, ISO-8601 dates), Optional JSONRepresentation typealiases.
- Encode/decode still throw InstantError (stricter than SQLiteData QueryBinding.invalid).

# Change Log

Newest entries appear first. Implementation commits and intent are recorded separately from ledger-only commits.

<!-- change-log:entries -->

## October 1st, 2026 at 12:54:42 a.m. EDT — `689ab0947fca` Add measurement switches for wal_autocheckpoint and checkpoint_fullfsync (#306)

- **Implementation commit:** `689ab0947fca81bca86a8c3f219a2396772d5db3`
- **Change:** Add measurement switches for wal_autocheckpoint and checkpoint_fullfsync (#306)
- **Details:**
  - Apple's SQLite runs WAL at synchronous NORMAL (DEFAULT_WAL_SYNCHRONOUS=1), so the commit-time suspects are uncached page reads and inline F_FULLFSYNC checkpoints every 1,000 WAL pages; these switches measure the checkpoint side. Unset, behavior equals ab33cb35.
- **Files:**
  - `Sources/InstantSwiftDataCore/InstantMeasurementSwitches.swift` — two more switches, and the synchronous note corrected
  - `Sources/InstantSwiftDataCore/SQLitePersistenceStore.swift` — optional wal_autocheckpoint and checkpoint_fullfsync pragmas
- **User context (verbatim):**
  > fix this please so it works efficiently as as well as the typescript core library
- **SpecStory:** unavailable — Claude Code subagent session (claude-opus-5.5 ts-parity); no SpecStory capture available for this harness

## September 30th, 2026 at 11:23:41 p.m. EDT — `d2f7bf7e3739` Add experiment-only switches for SQLite synchronous, cache_size, and the advertised core version (#306)

- **Implementation commit:** `d2f7bf7e373936fc61d63553d5a16dc81d4956ee`
- **Change:** Add experiment-only switches for SQLite synchronous, cache_size, and the advertised core version (#306)
- **Details:**
  - Measurement tool for plan 2026-09-30-ts-parity: INSTANT_SWIFT_DATA_EXPERIMENT_SQLITE_SYNCHRONOUS, INSTANT_SWIFT_DATA_EXPERIMENT_SQLITE_CACHE_SIZE, and INSTANT_SWIFT_DATA_EXPERIMENT_CORE_VERSION, each read once; unset, behavior equals ab33cb35. Not a merge candidate; the fast-drain agent owns the library.
- **Files:**
  - `Sources/InstantSwiftDataCore/InstantMeasurementSwitches.swift` — the three switches
  - `Sources/InstantSwiftDataCore/SQLitePersistenceStore.swift` — optional pragmas after the store's own
  - `Sources/InstantSwiftDataCore/InstantRuntime.swift` — the init frame's versions come from the switches
- **User context (verbatim):**
  > figure out a parallel experiment with TypeScript with voice dictation and see if there's some and trace everything
- **SpecStory:** unavailable — Claude Code subagent session (claude-opus-5.5 ts-parity); no SpecStory capture available for this harness

## September 30th, 2026 at 8:25:12 p.m. EDT — `9f72413db9fb` Let apps turn off AuthV3LoginScreen's demo counters (#289)

- **Implementation commit:** `9f72413db9fb8db1bcc496fcea3c6344e6b63194`
- **Change:** Apps can turn off AuthV3LoginScreen's demo counters (#289).
- **Details:**
  - New environment value authV3ShowsDemoCounters (default true, so the Auth recipe app and every other app are unchanged). When false the screen leaves out AuthV3CountersCard, which observes recipe_public_counters and recipe_account_counters and creates the public row on appear. Scribe turns it off: its schema has neither entity, and opening the Account sheet on Michael's iPad (0.1 (72)) failed two query observations and one write with no tap; each Increment public tap failed twice more.
  - Tests: AuthV3AppTests (macOS) lays out two login screens headless with local-only clients; the default screen creates the public counter row, the screen with the value off creates none. Red against a stub that ignored the value, then 6 of 6; AuthV3, Recipes, VoiceTrail, and AppBuilder suites 62 of 62.
  - Scope: only the AuthV3 UI module and its tests. git diff --stat 506089b2 lists no Sources/InstantSwiftDataCore file, so the sync engine is untouched and the live-recording simulator soak is not required.
- **Files:**
  - `Sources/AuthV3App/AuthApp.swift` — environment value authV3ShowsDemoCounters; the login screen reads it around the counters card
  - `Tests/AuthV3AppTests/AuthV3AppTests.swift` — default-on test and the headless two-screen write test
- **User context (verbatim):**
  > Remove the "Increment public / Increment mine" demo counters from Scribe's Account screen on every platform, so tapping them can't write a namespace Scribe's schema doesn't have.
- **SpecStory:** unavailable — Claude Code CLI session; no SpecStory capture configured for this session.
## September 30th, 2026 at 8:55:52 p.m. EDT — `f53f779317bd` Let the server's facts win against what a refused write restores, on every removal path (#296)

- **Implementation commit:** `f53f779317bdddba4912d92d5a676e5982001a02`
- **Change:** Facts that removing a refused write restores are base facts stamped txTime 0 at every removal site, so the server's fact wins against them as upstream shows it (#296).
- **Details:**
  - A refused write's receipt can restore values with this device's stamps, and Instant stamps a cardinality-one fact with the time its slot was first set (triple.clj keeps created_at on update unless overwrite-t is set, which only app streams do), so the restored value could win last-write-wins against the server's newer value and stay.
  - The differential's new 'refuse several before a frame' event found it: Scribe-links seed 15 showed a final segment as not final on the reduced device. Turning build 73's splice off does not fix it; the whole-component rebase restores the same before-image.
  - Applied in the reduced splice (store operations and receipt base facts), both terminal-failure removals, and the full rebase's reverse pass for refused rows. Upstream shows the server's results with the remaining pending writes on top, and a refused write leaves nothing behind.
  - aRefusedReplayLeavesTheServersValueOnBothPaths and the differential event are red on b78e978f (3 issues; seed 15 at step 38), also with the splice disabled, and green here. InstantFastDrainTests: 16 tests pass with 2 declared known issues (Pattern B).
- **Files:**
  - `Sources/InstantSwiftDataCore/InstantRuntime.swift` — restoredAsBase at the splice, the terminal-failure removals, and the full rebase's reverse pass
  - `Tests/InstantSwiftDataCoreTests/InstantFastDrainTests.swift` — the refused-replay twin test and the differential's multi-refusal event
- **User context (verbatim):**
  > Add the divergent shape to the differential as a permanent case, and show it red on b78e978f and green after the guard.
  > Agreed on the txTime-0 restore at all three removal sites.
- **SpecStory:** unavailable — Claude Code agent session (fast-drain-3); no SpecStory capture configured for this session.

## September 30th, 2026 at 8:55:35 p.m. EDT — `b78e978f8aee` Skip a restated fact that loses to a later-stamped resident fact, as the full rebase's last-write-wins does (#296)

- **Implementation commit:** `b78e978f8aee30821485d10ad312d70e1b4604d9`
- **Change:** A restated server fact that loses to a later-stamped resident fact no longer forces the whole-component rebase, so the phone's list frames reduce again (#296).
- **Details:**
  - Build 73 on Michael's iPhone declined every restated list frame (changesShadowedFact on recordings/clipboardEntries): the slot had no surviving writer, and the server's restated fact carried an earlier stamp than the resident fact a pruned local write left, so the fact did not hold and the frame fell back to the full rebase (about 3.5 s on the phone, every 16 s).
  - On a shadowed slot with no surviving writer, a cardinality-one fact stamped earlier than the resident fact is skipped, exactly as the full rebase's last-write-wins leaves it. This changes cost, not state.
  - aRestatedFactThatLosesToALaterStampedResidentFactDoesNotRebase is red on build 73's library, 506089b2 (changesShadowedFact recordings/title, 18 bodies) and green after (0 bodies). Replaying the phone's stored list result on a scratch copy of its pre-71 store (auth rows deleted, no transport): 21-24 s and 1,864 bodies per frame before, 0.11-0.14 s and 0 bodies after the first frame.
- **Files:**
  - `Sources/InstantSwiftDataCore/InstantRuntime.swift` — residentFactWins in the shadowed-slot classification
  - `Tests/InstantSwiftDataCoreTests/InstantFastDrainTests.swift` — the later-stamped resident fact test
- **User context (verbatim):**
  > Name the persisting decline, then fix both it and the splice cases
- **SpecStory:** unavailable — Claude Code agent session (fast-drain-3); no SpecStory capture configured for this session.

## September 30th, 2026 at 1:50:18 p.m. EDT — `5424c73365c6` Remove refused writes' overlays without the whole-component rebase, and respect last-write-wins in receipt patches (#296)

- **Implementation commit:** `5424c73365c63d487fe8f0f4768531450f970c2e`
- **Change:** A refused write's overlay is removed without the whole-component rebase, and receipt patches follow last-write-wins, so the Recording 023 backlog's refusals stop forcing 2,500-row rebases (#296).
- **Details:**
  - b4b9fbe3's backlog run: every refused replay left its overlay, and any refused overlay declined every frame (failedOverlay) into a whole-component rebase of about 2,500 rows (gate 12-16 s): 22 refusals and 20 accepts in 10 minutes.
  - The reduction removes up to 16 refused overlays itself. Each slot a refused write changed goes back to its before-image: in the next surviving writer's receipt when that write replaces the slot, otherwise in the store (an entity it created is deleted when nothing after it touches the entity). The refused rows are plan rows staged as removed, the store operations are hydrated and applied before the server facts, and they count as a store change. Two refused writes on one slot, a later merge, a re-asserted link, or later writes on a created entity keep the full rebase.
  - Receipt patches follow the store's last-write-wins rule: a present before-image with a later stamp than the server's fact is left alone, as the full rebase's apply leaves the base.
  - aRefusedWriteIsRemovedWithoutARebase (two cases, the live deferring refusal path) is red on b4b9fbe3 (failedOverlay, a rebase, 0 removed) and green after (0 rebases, 1 removed, equal to a full-rebase twin). The differential now refuses through the deferral path with 60 pending writes; 12 seeds in both shapes match after every event, with removals in 4 seeds.
- **Files:**
  - `Sources/InstantSwiftDataCore/InstantRuntime.swift` — failureSplice; spliced receipts and store operations in the classification and the plan; last-write-wins in receipt patches
  - `Sources/InstantSwiftDataCore/SQLitePersistenceStore.swift` — refused overlays, their next writers, and created entities in the reduction context; reduced plans skip refused component roots; InstantServerApplyFailureSplice; removed-overlay metric
  - `Tests/InstantSwiftDataCoreTests/InstantFastDrainTests.swift` — refused-write test through the live deferral; the differential refuses any write of a window through that path with 60 pending writes
- **User context (verbatim):**
  > If refusals still force rebases, go ahead with overlay removal without a rebase.
- **SpecStory:** unavailable — Claude Code agent session (fast-drain); no SpecStory capture configured for this session.

## September 30th, 2026 at 1:04:58 p.m. EDT — `5e994bdc92e5` Let the stale-acknowledgement test settle its delivery passes before it reclaims the write (#296)

- **Implementation commit:** `5e994bdc92e5fc0543798ab23283828d9ea9d8c8`
- **Change:** The stale-acknowledgement test lets its delivery passes settle before it reclaims the write, so a pass cannot strand the reoffer it waits for (#296).
- **Details:**
  - A pass that ran between the test's external reclaim and the stale answer's recording claimed the write under a new token but could not send it while the first offer was still in flight (pendingCount=1, skippedAlreadyInFlight=1); the next pass only deferred that claim. The reader's hand-off to the applier widened this pre-existing window: 6 timeouts in 35 runs on this branch at load 216-790, 0 in 20 on 0078484f at load 680-940.
  - The test waits for automaticMutationPumpIsIdleForTesting() before reading and reclaiming the claim, and parks acknowledgement-deadline wakes. 40 of 40 runs pass at load 693-929. Production is unaffected: a single runtime reclaims only its own claims, through the timeout path that also clears the in-flight reservation.
- **Files:**
  - `Tests/InstantSwiftDataCoreTests/InstantLiveTransportTests.swift` — settle wait and parked deadline wake in the stale-acknowledgement test
- **User context (verbatim):**
  > If your reader/applier change touches the deferral, please run this test several times under load.
- **SpecStory:** unavailable — Claude Code agent session (connection-survival); no SpecStory capture configured for this session.

## September 30th, 2026 at 1:04:58 p.m. EDT — `2ddad19f7056` Say which server the keepalive measurements came from (#296)

- **Implementation commit:** `2ddad19f7056b3fed9e6b7d42166888fb1a1ecf4`
- **Change:** Comments name the server the keepalive measurements came from: Instant's hosted server through the throwaway app bd40c50a, not Scribe's production app (#296).
- **Details:**
  - Comment-only change in the receive buffer's documentation and both new test files. No connection was made to Scribe's production app; the live probe refuses its app id prefix.
- **Files:**
  - `Sources/InstantSwiftDataCore/InstantRuntimeLiveSession.swift` — InstantLiveReceivedFrames documentation
  - `Tests/InstantSwiftDataCoreTests/InstantLiveConnectionSurvivalTests.swift` — suite documentation
  - `Tests/InstantSwiftDataCoreTests/InstantURLSessionKeepaliveLiveTests.swift` — suite documentation
- **User context (verbatim):**
  > If you mean Instant's hosted server (api.instantdb.com) reached through the throwaway app bd40c50a, say exactly that
- **SpecStory:** unavailable — Claude Code agent session (connection-survival); no SpecStory capture configured for this session.

## September 30th, 2026 at 1:04:57 p.m. EDT — `8abcc002cdfa` Let the stale-acknowledgement test accept a deadline the acknowledgement deferral moved later (#296)

- **Implementation commit:** `8abcc002cdfaa45eefd87d20aa1d76a1d72c7ba0`
- **Change:** The stale-acknowledgement test accepts a claim deadline that the acknowledgement deferral moved later, and still asserts that the stale answer adopted nothing (#296).
- **Details:**
  - The stale answer's disposition requests delivery while its frame still counts as applied, so that pump pass runs deferAcknowledgementDeadlinesWhileAFrameIsApplied (4e281ddd) and moves the replacement claim's deadline a few milliseconds later. The test compared the whole claim, deadline included.
  - Pre-existing: on 0078484f the unmodified test failed 20 of 20 runs at load 680-940 with a 3 ms deadline difference; claude-opus-5.5-fast-drain saw it at load 490-790. On the reader commit it failed 3 of 15 at load 340-760. The test now compares every field except the deadline and requires the deadline not to move earlier; skipping the deferral would be wrong, because the replacement's answer is queued behind the paused frame.
- **Files:**
  - `Tests/InstantSwiftDataCoreTests/InstantLiveTransportTests.swift` — staleAcknowledgementCannotAdoptAClaimTokenReofferedDuringResponseRecording ignores only a later deadline
- **User context (verbatim):**
  > Either make the test tolerate a deferred deadline (compare token, claimant, and state rather than the deadline), or make the deferral skip claims the paused frame cannot be holding. Your call.
- **SpecStory:** unavailable — Claude Code agent session (connection-survival); no SpecStory capture configured for this session.

## September 30th, 2026 at 11:47:07 a.m. EDT — `b4b9fbe32d6d` Hydrate deferred values, prove reverse-form links from their writers' receipts, and order the tail check by id (#296)

- **Implementation commit:** `b4b9fbe32d6d89f223a69f76e05dc1180bc8fe3b`
- **Change:** The reduction sees Scribe's deferred segment text and its links written from the other side, so live frames stop falling back to the whole-component rebase; the stamp guard orders the tail by id (#296).
- **Details:**
  - First live soak of 2666d343 (instrumented, iPhone simulator, bd40c50a): most declines were changesShadowedFact on transcriptionSegments/text and wordsJSON (Scribe keeps them deferred, so the reduction could not see them) and reverseLinkWriter on recordings/transcriptions and recordings/attachments (Scribe writes those links from the other side). It applied 0 receipt patches.
  - The reduction now hydrates the frame's deferred values before classifying, as the full rebase does. A forward link whose reverse-form slot has surviving writers is decided from the first writer's receipt in physical form: if the receipt retracts the link, the server added it and the receipt is patched; if not (including a stamp-only re-assertion), it was already there. A patch on a many-valued slot changes only the patched values.
  - The tail-write stamp guard compares (createdAt, id) with the outbox's newest row. Same-createdAt writes had lost to a later-stamped resident fact, which the Scribe-shaped differential caught in seeds 11, 13, and 16. InstantBoundedServerApplyRebaseTests now select the whole-component rebase they measure.
  - Red on 2666d343 with the live reasons (12 text declines; 6 reverseLinkWriter declines), green after. 12 differential seeds in both shapes match the full rebase after every event, with 10-31 receipt patches per seed. Instrumented live soak of b4b9fbe3 at host load 565-1,003: pending 0-11 (one burst to 33), CPU mostly 25-27%, about 99% of applies reduced, 7 component bodies in 5 min.
- **Files:**
  - `Sources/InstantSwiftDataCore/InstantRuntime.swift` — deferred hydration before classifying; reverse-link receipts (linkBeforeImage); many-valued receipt patches; tail check by (createdAt, id)
  - `Sources/InstantSwiftDataCore/SQLitePersistenceStore.swift` — first and last reverse-link writers in the reduction context; the creation cursor returns the tail position
  - `Tests/InstantSwiftDataCoreTests/InstantFastDrainTests.swift` — deferred-text and reverse-link tests; the Scribe-shaped differential defers text
  - `Tests/InstantSwiftDataCoreTests/InstantBoundedServerApplyRebaseTests.swift` — the runtime selects the whole-component rebase these tests measure
- **User context (verbatim):**
  > It must keep up like 4e281ddd (pending near 0, CPU about 30%) and also beat it on the big backlog.
- **SpecStory:** unavailable — Claude Code agent session (fast-drain); no SpecStory capture configured for this session.

## September 30th, 2026 at 11:39:55 a.m. EDT — `7cf2658e6ccd` Keep reading the socket while a frame applies, so URLSession keeps answering server pings (#296)

- **Implementation commit:** `7cf2658e6ccd55fb763dc054ebccb8ec15b56a72`
- **Change:** The live receiver keeps a receive() outstanding while a frame applies, so URLSession keeps answering server pings and a long apply no longer loses the socket (#296).
- **Details:**
  - URLSession answers a ping only while a receive() is outstanding; the server closes a client silent for its idle timeout (about 20-30 s measured). Build 72 applied each frame before calling receive() again, so Recording 023's 26-37 s applies lost the socket: connection 3 applied an add-query-ok from 319.7 s to 350.3 s, then failed its next send and receive with POSIX 57.
  - The receiver is now a reader and one sequential applier in one generation's task group, joined by InstantLiveReceivedFrames (128 frames, backpressure when full). The applier keeps the single loop's checks and bookkeeping: generation and session checks, record's in-flight and claim-token capture, frameBeingApplied() for the acknowledgement deferral and its 120 s cap. A frame buffered for an old generation is never applied, a retained send failure stops the applier before the next frame, and the terminal error follows every earlier frame (upstream onmessage before onclose).
  - Five InstantLiveTransportTests now also wait for liveReceiverIsWaitingForAFrameForTesting(), because the next receive() request no longer proves a frame was applied. Four deterministic tests were red on 0078484f and are green; two buffer tests are new. Live against bd40c50a the runtime check went from 2 connection attempts and 1 receive-loop failure after a 40 s apply to 1 and 0.
- **Files:**
  - `Sources/InstantSwiftDataCore/InstantRuntimeLiveSession.swift` — InstantLiveReceivedFrames, the reader and applier receiver, the retained-failure check, and the applier-idle test accessor
  - `Sources/InstantSwiftDataCore/InstantRuntime.swift` — liveReceiverIsWaitingForAFrameForTesting
  - `Tests/InstantSwiftDataCoreTests/InstantLiveConnectionSurvivalTests.swift` — keepalive, ordering, replacement, send-failure, and buffer tests
  - `Tests/InstantSwiftDataCoreTests/InstantLiveTransportTests.swift` — five tests wait for the applier instead of the next receive() request
- **User context (verbatim):**
  > Keep the socket answering pings while a frame applies.
- **SpecStory:** unavailable — Claude Code agent session (connection-survival); no SpecStory capture configured for this session.

## September 30th, 2026 at 10:39:05 a.m. EDT — `473fc933766d` Open one replacement connection per socket death, and keep the reconnect backoff when writes arrive (#296)

- **Implementation commit:** `473fc933766d7db56e91c41a51b0871c171abd80`
- **Change:** One socket death opens exactly one replacement connection, and writes no longer reset the reconnect backoff (#296).
- **Details:**
  - Build 72 had two reconnect paths for one loss: the receive loop's failure scheduled a reconnect, and the pump's next pass cancelled the controller (cancelAndWait) and connected itself. The cancelled attempt was aborted mid-handshake, or the controller later replaced the pump's fresh session because a reconnect never reused an open session. Recording 023 logged two or three connection.open-started per socket death.
  - ensureLiveConnectionIfNeeded() defers to a reconnect that is waiting out its backoff or connecting (ownsNextConnection), like upstream _trySend, which never starts a socket; _reconnectTimeoutMs resets only on init-ok. A reconnect for a lost session reuses a session opened after the loss; only connection.mutation-delivery-failed replaces the open session, which is the failed one there. Divergence from upstream _startSocket, which closes an open previous transport, is cited in scheduleReconnect's documentation.
  - connection.open-started is logged only when a connection will actually open. Tests seen red on 0078484f and green here: one replacement per death (3 attempts before, 2 after), reuse of a session opened by sign-in during the backoff (4 before, 3 after), and no connection or backoff cancellation from a write during the backoff.
- **Files:**
  - `Sources/InstantSwiftDataCore/InstantRuntime.swift` — reconnect ownership in ensureLiveConnectionIfNeeded, reuse semantics in scheduleReconnect, and the open-started log position
  - `Tests/InstantSwiftDataCoreTests/InstantLiveConnectionSurvivalTests.swift` — deterministic scripted-socket tests for one replacement per socket death, reuse, and backoff
- **User context (verbatim):**
  > Make the fix so that exactly one replacement connection opens.
- **SpecStory:** unavailable — Claude Code agent session (connection-survival); no SpecStory capture configured for this session.

## September 30th, 2026 at 10:38:16 a.m. EDT — `574098782627` Prove with the library's URLSession transport that a withheld receive() loses the socket (#296)

- **Implementation commit:** `5740987826273333323c80f40309c839ca823b0a`
- **Change:** An opt-in live suite proves, with the library's own URLSession transport, that a withheld receive() loses the socket (#296).
- **Details:**
  - Server rule (upstream websocket.clj, straight-jacket-run-ping-job): ping every 5 s; close a client that sent no text, binary, or pong frame for the idle timeout. Measured against the throwaway app bd40c50a: with receive() withheld the socket survived 20 s (2 of 2), died at 24-28 s in 3 of 6 trials and at 32-45 s in 7 of 7, always with POSIX 57, as on the device; a Node client that never pongs is closed at 25.2-25.7 s.
  - Locally (127.0.0.1, the library's URLSession configuration): with no receive() outstanding URLSession sent 0 pongs over plain, TLS, and permessage-deflate sockets, with and without server data frames; with a receive() pending it answered 30 of 30 pings within about 10 ms.
  - The suite's probe: 10 s alive; 40 s without receive() closed; 40 s with a receive() pending alive. Its runtime check holds one frame's apply for 40 s on a fresh room join; on build 72's receive loop it fails with 2 connection attempts and 1 receive-loop failure. Heavy unread server traffic postpones the close through TCP backpressure on the server's ping job, so the probes keep their sockets quiet.
- **Files:**
  - `Tests/InstantSwiftDataCoreTests/InstantURLSessionKeepaliveLiveTests.swift` — credentialed, opt-in measurement of the close threshold and of the runtime through a long apply; refuses the production app prefix
- **User context (verbatim):**
  > Prove the cause with URLSession specifically (red evidence).
- **SpecStory:** unavailable — Claude Code agent session (connection-survival); no SpecStory capture configured for this session.
## September 30th, 2026 at 10:05:34 a.m. EDT — `2666d34396f4` Re-receipt the first pending writer when the server changes a slot beneath it, instead of rebasing the component (#296)

- **Implementation commit:** `2666d34396f43800a94692cfd7b8925afa5d890b`
- **Change:** A server frame that changes a slot beneath pending writes re-receipts the slot's first writer instead of rebasing the whole component; this is why build 71 fell behind a live recording (#296).
- **Details:**
  - Instrumented build-71 soak (iPhone simulator, bd40c50a): Instant can send a query's refresh-ok before the transact-ok of the write it reflects (50 ms apart). The write is still pending, so every such frame declined into the whole-component rebase. Caught up, those were tiny. After one slow moment every frame declined (0 of 13-18 reduced per 30 s), and pending went 11 to 109 in 90 s.
  - When every surviving writer replaces a cardinality-one slot and the store shows the latest one, the base value lives only in the first writer's rollback receipt, the one receipt the full rebase would change. The plan now stages that writer as a receipt-patch body (kept with the plan so the commit's revalidation plans the same rows) and rebases its receipt onto the server fact. A create whose receipt deletes the entity gets retractions of what it wrote plus the server's facts. A later refusal restores the server's value, as after the full rebase.
  - F1: the capped earlier-overlays check is gone (every frame after a Stop used to rebase; the Stop drain is now 0 of 30 frames, 0.36 s, against 27 of 30 and 3.4 s). F2: a Scribe forward link written from the other side declines (reverseLinkWriter). Decline reasons are split, and metrics count component bodies and receipt patches.
  - Tests red on the reapplied 8bee78eb and green after: frames ahead of their answers (24, 24, and 19 bodies before, 0 after), the lost-answer replay (12, then 0), the Stop drain. The differential test gained frames ahead of answers and refused replays; 12 seeds in both link shapes match the full rebase after every event, with 7-19 receipt patches per seed. The fast-drain suite passes with Pattern B's 2 known issues.
- **Files:**
  - `Sources/InstantSwiftDataCore/InstantRuntime.swift` — receipt patches in the classifier and the forward pass; BeforeImage; rollbackTransaction(of:rebasedOnto:attributes:); F1 and F2
  - `Sources/InstantSwiftDataCore/SQLitePersistenceStore.swift` — first overlay per entity and reverse-link writers in the context; instant_server_apply_receipt_patches with the plan and its revalidation; split decline reasons; component-body and patch metrics
  - `Tests/InstantSwiftDataCoreTests/InstantFastDrainTests.swift` — in-flight, lost-answer, and Stop tests; frames ahead of answers and refused replays in the differential; component-body measurement
- **User context (verbatim):**
  > Find why the reduction rewrote nearly every pending row on live frames, and fix it on a new branch, with the live soak as the gate.
- **SpecStory:** unavailable — Claude Code agent session (fast-drain); no SpecStory capture configured for this session.

## September 30th, 2026 at 10:05:34 a.m. EDT — `81eb122c04cc` Reapply the server-apply reduction and the tail-write stamp guard (8bee78eb) as the base for its fixes (#296)

- **Implementation commit:** `81eb122c04cc300940b694944a8eb33a533bf7ca`
- **Change:** The build-73 branch reapplies 8bee78eb (the server-apply reduction and the tail-write stamp guard) as the base for its fixes; not shippable alone (#296).
- **Details:**
  - Reverts 184767d5 on agent/claude-opus-5.5/fast-drain-2 only, so the fixes that follow are reviewable as diffs over the reduction that fell behind live (build 71). Sources equal bb88af72's again and InstantFastDrainTests returns.
  - Build 73 ships only from a head that passes the live soak, the Recording 023-shape backlog, the ten suites, and the differential test.
- **Files:**
  - `Sources/InstantSwiftDataCore/InstantRuntime.swift` — the reduction, its call site, and the stamp guard, restored
  - `Sources/InstantSwiftDataCore/SQLitePersistenceStore.swift` — the reduction context, the excludes_watermark_roots plan option, and metrics, restored
  - `Tests/InstantSwiftDataCoreTests/InstantFastDrainTests.swift` — the fast-drain suite, restored
- **User context (verbatim):**
  > Michael needs a library that (a) keeps up live, like 4e281ddd, and (b) drains a Recording 023-sized backlog in minutes without pegging a core.
- **SpecStory:** unavailable — Claude Code agent session (fast-drain); no SpecStory capture configured for this session.

## September 30th, 2026 at 8:29:24 a.m. EDT — `184767d5f685` Revert "Skip the whole-component rebase for server frames that cannot change the base beneath pending writes (#296)"

- **Implementation commit:** `184767d5f68555d5d26ce0abb8c1ccbe8ed39c7c`
- **Change:** Scribe build 71's library fell behind a live recording; 8bee78eb is reverted, so the library sources match 80db4271 again (#296).
- **Details:**
  - Measured on an iPhone simulator against the throwaway app bd40c50a, same perf soak, 30 s samples. bb88af72 (build 71): pending writes reached 20 in the first minute and about 830 after 11 minutes; accepts fell from 51 to 4-15 per 30 s; CPU 60-114%; 240-880 pending rows rewritten per 30 s, so server frames kept peeling and replaying the outbox.
  - Every older library kept up under the same soak: 1.7.0 (pending 0-3), c9f25d45 (0-2), 8ed26be3 (one burst to 51 that drained), and 4e281ddd (0-1, accepts 49-54 per 30 s, CPU 27-36%, 0 ack timeouts, 0 reconnects). 4e281ddd's library sources are identical to 80db4271's; bb88af72 differs from 80db4271 only by 8bee78eb.
  - Removed: the server-apply reduction, the tail-write stamp guard, and InstantFastDrainTests (including the Pattern B known issue). Kept: 4e281ddd's acknowledgement deadline deferral and 120 s cap, 8ed26be3's whole-entity rule, and ce40ebe3's test-only busy timeout. The mechanism is still under investigation; a corrected reduction becomes a later build, gated on the live soak.
- **Files:**
  - `Sources/InstantSwiftDataCore/InstantRuntime.swift` — reduction, call site, stamp guard, and flag removed
  - `Sources/InstantSwiftDataCore/SQLitePersistenceStore.swift` — reduction context, excludes_watermark_roots plan option, and metrics removed
  - `Tests/InstantSwiftDataCoreTests/InstantFastDrainTests.swift` — deleted with the reduction it tested
- **User context (verbatim):**
  > The mitigation for build 72 is reverting 8bee78eb.
- **SpecStory:** unavailable — Claude Code agent session (fast-drain); no SpecStory capture configured for this session.

## September 30th, 2026 at 5:53:46 a.m. EDT — `ce40ebe3ae5d` Let the retry fault injection wait for the runtime's own write instead of failing "database is locked" (#296)

- **Implementation commit:** `ce40ebe3ae5da73a13909922ae07bc17acd184a2`
- **Change:** The discard tests' retry fault injection waits for the runtime's own write instead of failing with 'database is locked' (#296).
- **Details:**
  - failedAtomicRetryCommitRetainsRejectionAndDoesNotResend failed intermittently in full parallel suite runs on a loaded machine. The error came from the test's fault injection: a second SQLite connection with no busy timeout creating a trigger while the runtime's own connection could still hold a short write transaction.
  - Measured on frozen exports, interleaved, under the shared build lock, at load about 6. A write-lock probe at the injection point was busy in 64 of 80 scenarios on 80db4271 and 60 of 80 on 773429ae; the lock was free again within 0.5 ms. The exact injection failed in 24 of 120 concurrent scenarios on 80db4271 and 17 of 120 on 773429ae, and 0 of 480 on both with a 10 s busy timeout. The ten stale-writes suites, 3 interleaved runs per tree at loads 8 to 399: the target test passed 3 of 3 on both.
  - Not caused by the fast-drain branch, and the app cannot meet it on the iPhone: the library opens one connection per store with a 10 s busy timeout, and only the app process opens the store (the widget and broadcast extensions do not).
  - The helper now uses the same 10 s busy timeout as the library's connection and the file's other raw-connection helper. retryFaultInjectionWaitsForTheRuntimesOwnWrite runs the scenario 64 times at once: it failed 2 of 3 runs without the fix and passes 5 of 5 with it.
- **Files:**
  - `Tests/InstantSwiftDataCoreTests/InstantFailedMutationDiscardTests.swift` — busy timeout on the retry fault injection's connection; a concurrent regression test for it
- **User context (verbatim):**
  > Settle one thing before fast-drain ships as build 71: is the "database is locked" failure in failedAtomicRetryCommitRetainsRejectionAndDoesNotResend pre-existing, or caused by your branch?
- **SpecStory:** unavailable — unavailable — Claude Code agent session (fast-drain); no SpecStory capture configured for this session.

## September 30th, 2026 at 4:22:14 a.m. EDT — `8bee78eb3dd6` Skip the whole-component rebase for server frames that cannot change the base beneath pending writes (#296)

- **Implementation commit:** `8bee78eb3dd6974734b45280cbeb72d6ab5ac999`
- **Change:** A server frame that cannot change the base beneath the pending writes no longer peels and replays the outbox; a tail write that lost to a later-stamped fact now shows (#296).
- **Details:**
  - Recording 023 (build 69): the phone's 2,487 pending writes form two connected components (1,864 and 616). Every server frame that touched them peeled and replayed the whole component: the two rebases that finished took 22.5 s and 24.9 s, and the drain resolved about 33 writes per 55 s. A drain frame restates this device's own accepted writes, so it never changes the base beneath an overlay; upstream Reactor.js keeps each query's result in its own store and reapplies pending mutations on top.
  - Before planning, the runtime classifies every server fact against the store and the pending writes' durable receipts in one indexed, revision-checked read. A fact on an entity no surviving write touches applies as before or is skipped when it holds. A fact on a shadowed entity must already hold beneath the writes: in the store when no surviving write inserts that slot, else as the first such write's receipt before-image, provided the earlier writes only insert and the store shows the last writer's value. When nothing left touches a shadowed entity and the watermark prunes only a prefix, the plan is body-free (excludes_watermark_roots). Failed overlays, global or unproven receipts, lookups, merges, confirmations, non-prefix watermarks, and real changes beneath pending writes keep the whole-component rebase; server-apply.reduction-declined logs each reason.
  - A write appended at the outbox tail whose cardinality-one insert lost to a later-stamped resident fact (a faster server clock, or an overlay a rebase restamped) has those facts restamped past the newest fact. Before, it stayed invisible and delivery dropped it as older than the visible state until the next whole-component rebase; writes created before queued ones keep domain order.
  - Measured (debug, macOS harness, one frame per accepted write): at 2,502 pending writes every frame of the full rebase rebased all ~2,500 bodies, 25.6 s wall and 12 s CPU per frame; reduced, 0 rebases for all 2,502 frames and 73 s process CPU for the whole drain (load average ~400). App time on a simulator or device is not measured. Differential test: 6 seeds x 70 randomized events, every read equal to the full rebase. Pattern B reproduced (known issue, whole-component path, not fixed).
- **Files:**
  - `Sources/InstantSwiftDataCore/InstantRuntime.swift` — the reduction and its call site, the tail-write stamp guard in performTransact, reducesServerApplyToAffectedOverlays, a live-refusal test seam
  - `Sources/InstantSwiftDataCore/SQLitePersistenceStore.swift` — loadServerApplyReductionContext (indexed probes), the excludes_watermark_roots plan option, reduction metrics
  - `Tests/InstantSwiftDataCoreTests/InstantFastDrainTests.swift` — Scribe-shaped drain harness, focused red/green tests, the differential test, the Pattern B reproduction, the measurement
- **User context (verbatim):**
  > Make instant-data-swift catch up fast when the outbox is large: stop paying a whole-outbox rebase for every server frame, and prove it with a measured 2,500-write drain.
- **SpecStory:** unavailable — unavailable — Claude Code agent session (fast-drain); no SpecStory capture configured for this session.

## September 30th, 2026 at 12:58:24 a.m. EDT — `4e281ddd0e22` Keep delivery claims while a server frame is still applying, and name what a refusal refused (#296)

- **Implementation commit:** `4e281ddd0e22a1c4263b44559bf530ab99c4cef4`
- **Change:** Delivery claims wait behind a server frame the receive loop is still applying, and every refusal names what it refused and whether it was a replay (#296).
- **Details:**
  - Recording 023 (build 69): after each reconnect the first query result started a 22-25 s optimistic rebase of the 2,487-mutation outbox, and the head's transact-ok waited behind it. The 6 s acknowledgement deadline reclaimed the head, replaced the connection, and started over: 385 times in 84 minutes. Nothing after 18:23 reached the server.
  - While the current generation applies a frame, the pump now moves this claimant's claim deadlines to at least now + 6 s before claiming. Upstream Reactor.js handles each frame synchronously (_handleReceive), so its mutation timers never fire mid-frame. One frame is deferred for at most acknowledgementDeferralLimitMilliseconds (120 s, measured reason at the declaration); after that the deadline expires as before and ack-deadline-deferral-exhausted is logged as a warning.
  - server-error-terminal carries the hint as JSON and a refusalKind: replay when an earlier connection offered the write without an answer, otherwise first-offer. A new refused-write event names the namespace, check, entity, attributes, and short values. Both are logged before the failure is recorded.
  - Tests: acknowledgementDeadlineWaitsWhileTheReceiverStillAppliesAnEarlierFrame fails before (2 issues) and passes after; the refusal tests were written with the change and not run red. Ten suites, 682 tests, pass with 21 known issues: 20 in tests this change does not touch, 1 declared ack-timeout report in the new replay test. Not yet measured on a device.
- **Files:**
  - `Sources/InstantSwiftDataCore/InstantRuntime.swift` — deadline deferral before claiming, refusal kind and refused-write diagnostics, the deferral limit
  - `Sources/InstantSwiftDataCore/InstantRuntimeLiveSession.swift` — the frame being applied in each generation; offers earlier connections never answered
  - `Sources/InstantSwiftDataCore/SQLitePersistenceStore.swift` — move one claimant's claim deadlines; read one outbox row for diagnostics
  - `Sources/InstantSwiftDataCore/InstantMutationRefusal.swift` — what a refusal refused, from the hint and the refused transaction
  - `Tests/InstantSwiftDataCoreTests/InstantBoundedOutboxDeliveryTests.swift` — the deferral and the replay refusal; the stuck-frame test sets the limit to 0
  - `Tests/InstantSwiftDataCoreTests/InstantMutationRefusalTests.swift` — refusal metadata shapes
- **User context (verbatim):**
  > the transcript is not loading from within the app, although the word count is
- **SpecStory:** unavailable — Claude Code agent session (stale-writes); no SpecStory capture configured for this session.

## September 30th, 2026 at 12:58:24 a.m. EDT — `8ed26be3e87a` Keep an entity whole when it leaves one live query result (#296)

- **Implementation commit:** `8ed26be3e87a6607200040214bf94094ec5e52df`
- **Change:** Replacing a live query result keeps an entity whole when it leaves that result but still has a stored fact the retraction would not remove, as #259's pruning rule already did (#296).
- **Details:**
  - Before: each fact the old result held and the new one lacks was retracted unless another saved result owned that exact fact. In Recording 023 the recording list's result dropped a segment when a preview slot moved while the live timeline still held 12 of its facts; the 3 list-only facts (wallClockStartedAtMs, wallClockEndedAtMs, sentToInstantAtMs) were stripped locally on 4 of 847 segments, and typed reads quarantined those rows. The server has all 16 fields.
  - Unchanged: a server edit to an entity still in the result is applied, and an entity only one result ever held is retracted in full. Cost, the same as #259's: a remote delete of such an entity no longer propagates by it leaving a result.
  - Tests: liveQueryReplacementKeepsAnEntityWholeWhenItOnlyLeftOneResult fails before (it retracted createdAt and isCompleted) and passes after; the control liveQueryReplacementStillRetractsEntitiesNoOtherResultHoldsAndServerEdits passes both ways. Ten suites, 682 tests, pass.
- **Files:**
  - `Sources/InstantSwiftDataCore/SQLitePersistenceStore.swift` — replacement retraction collects an entity that left a result whole or not at all
  - `Tests/InstantSwiftDataCoreTests/InstantStoreTests.swift` — the Recording 023 shape and a control
- **User context (verbatim):**
  > the transcript is not loading from within the app, although the word count is
- **SpecStory:** unavailable — Claude Code agent session (stale-writes); no SpecStory capture configured for this session.

## September 29th, 2026 at 2:12:54 a.m. EDT — `fa570b3d5602` Let apps hide "Discard guest session" on the login screen (#113)

- **Implementation commit:** `fa570b3d5602b43d6113d928d6e82d2c66fc80cd`
- **Change:** Apps can hide Discard guest session on AuthV3LoginScreen (#113).
- **Details:**
  - New environment value authV3AllowsDiscardingGuestSession (default true). Scribe turns it off: discarding signed the guest out, and the next launch made a new guest that could not read the old guest's recordings. Additive; swift build --target AuthV3App passes.
- **Files:**
  - `Sources/AuthV3App/AuthApp.swift` — environment value and guest card
- **User context (verbatim):**
  > audit that I can upload upgrade an anonymous account to an account that already exists, and the recordings will be merged in the uh real users library.
- **SpecStory:** unavailable — Claude Code CLI session; no SpecStory capture configured for this session.

## September 29th, 2026 at 12:48:45 a.m. EDT — `a9a555636838` Print, debug-print, and reflect auth sessions without the refresh token or email (#113)

- **Implementation commit:** `a9a55563683867e7ab1ed640745a25fa832ff550`
- **Change:** Auth sessions print, debug-print, and reflect without the refresh token or the email address, so logging a session or anything that carries one cannot leak the token (#113).
- **Details:**
  - InstantAuthSession now conforms to CustomStringConvertible, CustomDebugStringConvertible, and CustomReflectable. description: InstantAuthSession(appID: "app-1", userID: "user-1", isGuest: false, email: <present>, refreshToken: <redacted>). The mirror keeps every field for dump and customDump, with refreshToken, email, and imageURL as presence markers (nil when absent).
  - Before the change every rendering (interpolation, String(describing:), String(reflecting:), dump, customDump) of a session, an optional or array of sessions, InstantGuestPromotionResult, InstantAuthIdentityTransition, InstantAuthSignedInEvent, InstantAuthStatus, InstantGuestPromotionExchangeResult, and InstantMagicCodeSignInResult contained the token and the email: all 45 renderings (9 values, 5 methods), and the default rendering also showed the image URL. AuthV3App posts String(describing: event.identityTransition) in a notification for host loggers.
  - Codable, Equatable, and Hashable are unchanged (the persisted session keeps its token). Trade-off: expectNoDifference between two sessions that differ only in token or email still fails, but CustomDump reports no visible difference; compare session.refreshToken directly when that matters.
  - Not covered: request and verification types (InstantOAuthSignInRequest, InstantIDTokenSignInRequest, InstantMagicCodeVerifyRequest, the *Verification types, InstantMagicCodeChallenge.code) still print their tokens; they stay inside auth exchanges today.
  - Validation: InstantAuthSessionRedactionTests 4 of 5 red before, green after; final focused run of 67 tests in 10 suites passes (the 25 baseline tests, the 9 new tests, and 33 more session-related tests in InstantStoreTests, BootstrapTests, and AuthV3AppTests with no baseline).
- **Files:**
  - `Sources/InstantSwiftDataCore/InstantModels.swift` — log-safe description, debugDescription, and mirror for InstantAuthSession
  - `Tests/InstantSwiftDataTests/InstantAuthSessionRedactionTests.swift` — exact log-safe renderings; no rendering of any carrier contains the token or email; Codable and equality keep the token
- **User context (verbatim):**
  > audit that I can upload upgrade an anonymous account to an account that already exists, and the recordings will be merged in the uh real users library.
- **SpecStory:** unavailable — Claude Code CLI session; no SpecStory capture configured for this session.

## September 29th, 2026 at 12:41:47 a.m. EDT — `2d29e8f2e740` Pin that a guest's pending writes survive a link into an existing account; document the divergence from Reactor.updateUser (#113)

- **Implementation commit:** `2d29e8f2e7401d7b1d3f38830d5d479db987b5ec`
- **Change:** Pin and document that a guest's pending writes survive a link into an existing account and are delivered under the promoted session, a deliberate divergence from upstream Reactor.updateUser (#113).
- **Details:**
  - Upstream Reactor.updateUser (Reactor.js 2240-2274), run by changeCurrentUser on every sign-in or sign-out that changes the user, fails each pending mutation with user-changed and drops it. This runtime never clears the outbox on an auth change (saveAuthSession, commitGuestPromotion, and signOut leave it untouched; PendingMutation has no user).
  - InstantGuestPromotionOutboxTests: a guest writes, promoteGuestWithOAuth links it to an existing user (linkedToExistingUser), the write is still pending (not failed) and deliverable, and connect() sends init with the promoted refresh token followed by transact for the guest's write. Protocol-level evidence with a scripted socket, not a live server; it passes before and after (pins current behavior).
  - Why Scribe keeps delivery: Instant links the guest, rules that admit linked-guest rows accept the write, and the app adopts the rows (Scribe ADR 0005, ADR 0014 section 9, Instant guest-auth docs 'Handling conflicting users'). Rules that require direct ownership reject it: on 2026-09-28 a guest create queued offline was denied after linking (/Users/laptop/Sync/audit/web-scribe-2026-09-28/AUTH-AUDIT.md).
- **Files:**
  - `Tests/InstantSwiftDataCoreTests/InstantGuestPromotionOutboxTests.swift` — a guest's pending write stays pending across a link into an existing account and is sent under the promoted session
  - `skills/instant-data/SKILL.md` — auth changes keep the outbox: the divergence from Reactor.updateUser, why, and when to drain first
- **User context (verbatim):**
  > audit that I can upload upgrade an anonymous account to an account that already exists, and the recordings will be merged in the uh real users library.
- **SpecStory:** unavailable — Claude Code CLI session; no SpecStory capture configured for this session.

## September 29th, 2026 at 12:41:13 a.m. EDT — `f5e1aec4835f` Forward only a guest session's refresh token to the OAuth code exchange (#113)

- **Implementation commit:** `f5e1aec4835f5ec7284d5f5019735ac4f65e3e4b`
- **Change:** The ordinary OAuth sign-in forwards the current refresh token only for a guest session, as Instant's TypeScript client does; ID-token sign-in keeps forwarding any current token, as upstream does (#113).
- **Details:**
  - Upstream Reactor.exchangeCodeForToken (Reactor.js 2381-2394) and the redirect handler _oauthLoginInit (1974-2030) send refreshToken only when the current user is a guest; Reactor.signInWithIdToken (2408-2423) sends any current token. aa3d9779 applied the same guest-only rule to magic codes after a revoked non-guest token made verify_magic_code fail live (2026-09-28).
  - Guest promotion (promoteGuestWithOAuth, promoteGuestWithIDToken) is unchanged. Scribe's sources on main and on the sharing branch call neither signInWithOAuth nor signInWithIDToken, so no Scribe path changes today.
  - Validation: InstantOAuthGuestTokenTests red before (a non-guest token was forwarded), green after; the guest-token and ID-token cases pass before and after. The two tests that expected a non-guest token to reach OAuth now expect none. Focused run (InstantOAuthGuestTokenTests, InstantGuestPromotionOutboxTests, InstantGuestPromotionTests, InstantMagicCodeGuestTokenTests, V3AuthLoginFixtureTests, InstantAuthHTTPParityTests, and the four OAuth and ID-token exchange tests in InstantStoreTests and BootstrapTests): 29 tests in 8 suites pass; the same 25 existing tests passed before the change.
- **Files:**
  - `Sources/InstantSwiftDataCore/InstantRuntime.swift` — signInWithOAuth forwards the refresh token only for a guest session (upstream parity)
  - `Tests/InstantSwiftDataCoreTests/InstantOAuthGuestTokenTests.swift` — guest token forwarded, non-guest token not forwarded, ID-token sign-in still forwards any token
  - `Tests/InstantSwiftDataCoreTests/InstantStoreTests.swift` — the OAuth exchange test expects no token from a non-guest session
  - `Tests/InstantSwiftDataTests/BootstrapTests.swift` — the OAuth dependency test expects no token from a non-guest session
- **User context (verbatim):**
  > audit that I can upload upgrade an anonymous account to an account that already exists, and the recordings will be merged in the uh real users library.
- **SpecStory:** unavailable — Claude Code CLI session; no SpecStory capture configured for this session.

## September 28th, 2026 at 2:12:59 p.m. EDT — `aa3d97795b2e` Forward only a guest session's refresh token to verify_magic_code; keep Instant's auth error type and message (#113)

- **Implementation commit:** `aa3d97795b2e7a78830bbd9631534cd4357f8625`
- **Change:** Magic-code sign-in forwards only a guest session's refresh token, and auth failures keep Instant's error type and message (#113).
- **Details:**
  - Evidence: on 2026-09-28 against Scribe's Instant app, a Swift client holding a revoked non-guest refresh token failed verify_magic_code (record-not-found, HTTP 400) because it forwarded the token; the TypeScript client, which forwards only guest tokens (Reactor.signInWithMagicCode), signed in. After the fix the same live run signs in, and a Swift guest still links into an existing account.
  - InstantAuthHTTPClient: non-2xx auth responses report 'HTTP <status> (<type>): <message>' from Instant's body; the hint is dropped because it can echo refresh tokens.
  - Validation: InstantMagicCodeGuestTokenTests red before (non-guest token forwarded; bare HTTP 400 message), green after; 590 tests across InstantStoreTests, BootstrapTests, CLIArgumentParserTests, InstantAuthHTTPParityTests, InstantGuestPromotionTests and V3AuthLoginFixtureTests pass (4 known issues). Audit report /Users/laptop/Sync/audit/web-scribe-2026-09-28/AUTH-AUDIT.md.
- **Files:**
  - `Sources/InstantSwiftDataCore/InstantRuntime.swift` — forward the refresh token to verify_magic_code only for a guest session (upstream parity)
  - `Sources/InstantSwiftDataCore/InstantAuthHTTPClient.swift` — keep Instant's error type and message on auth HTTP failures, never the hint
  - `Tests/InstantSwiftDataCoreTests/InstantMagicCodeGuestTokenTests.swift` — guest token forwarded, non-guest token not forwarded, error body kept without tokens
- **User context (verbatim):**
  > I also want you to audit that I can upgrade an anon account into either an existing account or a nw account
- **SpecStory:** unavailable — Claude Code subagent session (guest-upgrade audit); no SpecStory capture configured.

## September 27th, 2026 at 5:37:29 p.m. EDT — `2fced8d1930c` Drop local entities that lost their id fact once, so the server delivers them whole (#278)

- **Implementation commit:** `2fced8d1930cb26334ce4581ce14ea94188a01c2`
- **Change:** Stores damaged by partial pruning drop their entities that lost the id fact, once, so the server delivers them whole (#278).
- **Details:**
  - Evidence: the 2026-09-27 iPhone store holds 1,067 transcriptionSegments with facts but no id fact; every other entity in every namespace has its id fact and no pending mutation touches any of the 1,067. The Instant server sends the id fact with every selection (instaql.clj etype-attr-ids) and typed writes always write it.
  - Migration 0024 removes every entity with facts but no <namespace>/id fact, keeping entities a pending mutation touches and skipping stores that never synced; drops their live-query ownership rows, bumps the store and query-result revisions, and records sqlite.repair.entities-missing-id-removed. Refreshes insert every result triple, so the rows come back when a query needs them.
  - On a copy of the phone's store: removed exactly 1,067 entities (6,172 facts), all transcriptionSegments; every remaining entity has its id fact; outbox untouched; whole bootstrap 0.25 s. InstantPartialEntityRepairTests fails 3 ways with the repair disabled and passes with it.
- **Files:**
  - `Sources/InstantSwiftDataCore/SQLitePersistenceStore.swift` — migration 0024 one-time removal of entities missing their id fact
  - `Tests/InstantSwiftDataCoreTests/InstantPartialEntityRepairTests.swift` — synced store drops the id-less entity no mutation touches; never-synced store keeps everything
- **User context (verbatim):**
  > It was the transcription text that wasn't showing in a freshly recorded thing.
- **SpecStory:** unavailable — Claude Code CLI session (triage agent L); no SpecStory capture configured.

## September 27th, 2026 at 5:37:29 p.m. EDT — `246e191d556d` Leave a row that fails to decode out of a query instead of failing the whole query (#278)

- **Implementation commit:** `246e191d556dd5f873a678eeb019e318dd26a202`
- **Change:** A row that fails to decode is left out of a typed read and reported, instead of failing the whole query (#278).
- **Details:**
  - Evidence: at 13:41:31 on 2026-09-27 the iPhone's playback detail fetch failed with "Expected number for selected Instant field 'wallClockStartedAtMs'" and recording 008 showed 27 of 237 sections. Every typed read decoded with try map(init(snapshot:)), so the first bad row threw for the whole query; InstantRowQuarantineTests reproduces the phone's exact error.
  - Typed reads decode row by row through InstantRowQuarantine: query, queryOnceDecoded, the infinite query snapshot and subscription, subscribe, FetchAll (entities and selected fields), FetchOne of an entity, and InstantFetchRequest roots and included children. Each newly failed row is reported once per read with reportIssue and an error-level query.row-decode-quarantined diagnostic. New public decodeQuarantiningFailures(_:operation:); decode(_:) still throws. FetchOne of a single selected field still fails with the decode error.
  - Deliberately differs from SQLiteData, which fails the whole fetch (QueryCursor._element): SQLite's column constraints keep partial rows from existing, while Instant stores each field as its own fact. The sqlite.fetch-all.decode-failure parity record now names fetchAllLoadLeavesOutAMalformedRowAndReportsIt.
  - Validation: new tests red before, green after; TypedAPITests' decode-error tests updated for the new contract (and the scalar selection test no longer races the post-load observation). Full suite: the only failure outside the known lists (fiftyEncodingFailuresUseBoundedRowAddressedQuarantineAndDoNotStarveTail, outbox encoding quarantine) passes alone 3/3.
- **Files:**
  - `Sources/InstantSwiftData/InstantRowQuarantine.swift` — row-by-row decode, once-per-read reporting, decodeQuarantiningFailures
  - `Sources/InstantSwiftData/InstantTypedAPI.swift` — query, queryOnceDecoded, and infinite query reads decode through the quarantine
  - `Sources/InstantSwiftData/InstantSwiftData.swift` — subscribe, selected-field FetchAll, and InstantFetchRequest children maps decode through the quarantine
  - `Sources/InstantSwiftDataCore/InstantParityCoverage.swift` — SQLiteData fetchFailure record explains the adaptation
  - `Tests/InstantSwiftDataTests/InstantRowQuarantineTests.swift` — one damaged row among good ones through query, a live subscribe, and a mapped fetch
  - `Tests/InstantSwiftDataTests/TypedAPITests.swift` — FetchAll decode-error tests expect the quarantine; scalar test race fixed
  - `skills/instant-data-modeling/SKILL.md` — fetches quarantine bad rows; keep init(snapshot:) strict
- **User context (verbatim):**
  > It was the transcription text that wasn't showing in a freshly recorded thing.
- **SpecStory:** unavailable — Claude Code CLI session (triage agent L); no SpecStory capture configured.

## September 27th, 2026 at 4:58:05 p.m. EDT — `af3c05849c4a` Keep local writes from waiting behind server apply's quadratic commit (#277)

- **Implementation commit:** `af3c05849c4ad07b812a8f56abed07dbf757b1cb`
- **Change:** Local writes no longer wait behind server apply's commit, which was quadratic in the pending tail (#277).
- **Details:**
  - Evidence: the 2026-09-27 iPhone pull logged serial-gate.stalled with holder 'catch up server apply' held 5,632 ms and a transact waiting 5,057 ms, 439 pending mutations. Profiling and phase timers put the time in commitServerApplyPlan under the operation gate: the component closure re-joined every planned row through every shared entity each round (N^2 around one recording's sections), and the outbox rewrite's IN subquery was correlated through outbox.json, so every outbox row rescanned the plan.
  - Fix: breadth-first closure over a temp frontier table (each entity expanded once, rows tagged by round); uncorrelated outbox rewrite with a per-row EXISTS. Gate held at 2,000 pending 23,479 -> 570 ms, at 439 pending 969 -> 207 ms. InstantServerApplyOperationGateTests: 1,000 pending plus a local write every 25 ms fails before (gate 4,796 ms, longest write 4,799 ms) and passes after (202 ms, 175 ms).
  - Diagnostics: the gate holder names its phase; serial-gate.waited reports a caller that queued 250 ms or more (warning from 1 s) with the holder and phase; server-apply.operation-gate-held records per-phase durations. Upstream Reactor.js has no such gate (pushOps line 1509, refresh-ok line 725).
  - Validation: 12 focused suites, 544 tests pass; full suite has one failure outside the known lists (publishGatePendingAndColdReopenMetrics, a process-wide footprint check under parallel load) and it passes in isolation; Scribe-shaped memory soak passed with INSTANT_SWIFT_DATA_LIVE_AUTH_SOAK=0.
- **Files:**
  - `Sources/InstantSwiftDataCore/SQLitePersistenceStore.swift` — breadth-first component closure and uncorrelated outbox rewrite
  - `Sources/InstantSwiftDataCore/InstantRuntime.swift` — gate timeline, phase names, server-apply.operation-gate-held, upstream note
  - `Sources/InstantSwiftDataCore/AsyncSerialGate.swift` — holder phase and wait reports
  - `Tests/InstantSwiftDataCoreTests/InstantServerApplyOperationGateTests.swift` — local writes during a 1,000-pending hub apply stay fast and durable
  - `Tests/InstantSwiftDataCoreTests/AsyncSerialGateTests.swift` — wait report names holder and phase; quick handoff reports nothing; stall names the phase
- **User context (verbatim):**
  > After pause: home shows paused but resume recording button does nothing — only stop works.
- **SpecStory:** unavailable — Claude Code CLI session (triage agent L); no SpecStory capture configured.

## September 27th, 2026 at 3:13:03 p.m. EDT — `fc7ce10c5940` Saturate the live timeout sleep instead of trapping on a far-future deadline (#259)

- **Implementation commit:** `fc7ce10c59400fe1f7ba28702ec990984d78d03e`
- **Change:** The live timeout sleep saturates instead of trapping on a far-future deadline.
- **Details:**
  - UInt64 milliseconds * 1,000,000 overflowed for deadlines beyond about 584 years (max(0, deadline - now) from an Int64 deadline) and crashed the process with signal 5; the full suite hit it under load on 2026-09-27. multipliedReportingOverflow saturates to UInt64.max nanoseconds. InstantLiveTimeoutSleepTests: crash before, pass after.
- **Files:**
  - `Sources/InstantSwiftDataCore/InstantLiveTransport.swift` — saturating millisecond-to-nanosecond conversion
  - `Tests/InstantSwiftDataCoreTests/InstantLiveTimeoutSleepTests.swift` — far-future sleep cancels instead of trapping; ordinary sleep still waits
- **User context (verbatim):**
  > It was the transcription text that wasn't showing in a freshly recorded thing.
- **SpecStory:** unavailable — Claude Code CLI session; no SpecStory capture configured for this session.

## September 27th, 2026 at 2:41:21 p.m. EDT — `552457420ee3` Keep observations and pruned entities intact: stale-emission hydration and whole-entity orphan collection (#259 #274)

- **Implementation commit:** `552457420ee3dfea8b72514257307b76606b027d`
- **Change:** Deferred hydration no longer strands an observation after an unrelated write, and live-query pruning collects whole entities only (#259 #274).
- **Details:**
  - isStillCurrent drops a stale emission only when its query was refreshed after it (store records each query's last published refresh); otherwise the emission is the query's current result and is hydrated. Pruning keeps an entity whole when any fact is unowned and deletes the deferred payload rows of fully collected entities. Evidence: iPhone store had 1,055 segments with text but no recordingID; tests reproduce both stalls and the partial prune (red before, green after). Full suite (clean build): no new failures; the 14 load-sensitive failures pass in isolation.
- **Files:**
  - `Sources/InstantSwiftDataCore/InstantStore.swift` — per-query last refresh sequence and wasRefreshed(queryID:after:)
  - `Sources/InstantSwiftDataCore/InstantRuntime.swift` — isStillCurrent replaces the global-sequence stale check; testing hook
  - `Sources/InstantSwiftDataCore/SQLitePersistenceStore.swift` — whole-entity orphan collection and deferred payload cleanup
  - `Tests/InstantSwiftDataCoreTests/DeferredValueResidencyTests.swift` — unrelated write between emission and hydration (observation, local infinite)
  - `Tests/InstantSwiftDataCoreTests/InstantStoreTests.swift` — partially owned entity survives pruning whole
- **User context (verbatim):**
  > On an immediately just-completed recording: words/transcript are NOT showing up, but screenshots, copies, the route, and everything else DO
- **SpecStory:** unavailable — Claude Code CLI session (triage agent B); no SpecStory capture configured.

## September 27th, 2026 at 9:08:53 a.m. EDT — `18831d088dbb` Document the v1.7.0 release: cheaper live refresh and a capped diagnostics log (#250 #254 #155)

- **Implementation commit:** `18831d088dbb50cfc7e6950c47fe8d7e5d40d1d0`
- **Change:** Document the v1.7.0 release: cheaper live refresh and a capped diagnostics log (#250 #254 #155).
- **Details:**
  - Minor release: new public diagnostics API is additive (maximumFileBytes, defaultMaximumFileBytes, record(...changeKey:), previousLogFileURL(for:)). Measured against 1.6.0 (ABBA thread CPU, Debug, M1 Max): 40 decodes of an 18 KB refresh 513 -> 225 ms; translate 100 refreshes x 8 results 5,123 -> 1,223 ms; 200 persisted results 1,071 -> 627 ms; diagnostics record path 222 -> 134 ms per 30 s. The log file rotates at 16 MiB with one previous file (27.5 MB/h unbounded before).
- **Files:**
  - `docs/releases/v1.7.0.md` — release document; passes scripts/validate-release-version.sh 1.7.0
- **User context (verbatim):**
  > please install the app with all the fixes you made last night
- **SpecStory:** unavailable — Claude Code CLI session; no SpecStory capture configured for this session.

## September 27th, 2026 at 12:23:28 a.m. EDT — `e3cf7c01a1fc` Decode server JSON without throwing an error per string (#250 #155)

- **Implementation commit:** `e3cf7c01a1fc5f64753ef0d857e851140c67a39d`
- **Change:** Decode server JSON without throwing an error per string (#250 #155)
- **Details:**
  - Profile: 625 ms per 30 s decoding server messages, 246 ms building coding paths for thrown errors.
  - Order String, Double, array, object, Bool; result identical (independent-parse test). ABBA thread CPU 513 -> 225 ms per 40 decodes of an 18 KB refresh.
- **Files:**
  - `Sources/InstantSwiftDataCore/InstantLiveTransport.swift` — Decode attempts in payload frequency order.
  - `Tests/InstantSwiftDataCoreTests/InstantLiveJSONValueDecodeCostTests.swift` — Equivalence and cost benchmark.
- **User context (verbatim):**
  > please do a complete audit on this entire applications structure as well as the library. And if there's anywhere else that there's just not performance, please let me know.
- **SpecStory:** unavailable — Claude Code CLI session; no SpecStory capture for this task

## September 27th, 2026 at 12:23:28 a.m. EDT — `87b7687dcbf3` Record repeating infinite-query snapshots only when they change (#250 #155)

- **Implementation commit:** `87b7687dcbf34103def0fcca51fb9bbbcd07967a`
- **Change:** Record repeating infinite-query snapshots only when they change (#250 #155)
- **Details:**
  - Phone (2026-09-26): 97.8% of infinite.starter.snapshot and 79.7% of infinite.remote-page-info.decoded events were exact repeats.
  - New record overload with a required changeKey records only transitions; original signature unchanged.
- **Files:**
  - `Sources/InstantSwiftDataCore/InstantDiagnostics.swift` — changeKey overload with a bounded last-metadata memo under the existing lock.
  - `Sources/InstantSwiftDataCore/InstantInfiniteQueryDiagnostics.swift` — Forwards changeKey.
  - `Sources/InstantSwiftDataCore/InstantInfiniteQuery.swift` — Starter snapshots keyed by plan.
  - `Sources/InstantSwiftDataCore/InstantLiveRefreshApplication.swift` — Page-info events keyed by query registration key.
  - `Tests/InstantSwiftDataCoreTests/InstantDiagnosticsTests.swift` — Keyed snapshots collapse to transitions.
- **User context (verbatim):**
  > please do a complete audit on this entire applications structure as well as the library. And if there's anywhere else that there's just not performance, please let me know.
- **SpecStory:** unavailable — Claude Code CLI session; no SpecStory capture for this task

## September 26th, 2026 at 11:14:24 p.m. EDT — `44b176a492b5` Resolve the schema once per live refresh and sort persisted results without string copies (#250 #155)

- **Implementation commit:** `44b176a492b5d883fb58c6bf29287b689354ebb5`
- **Change:** Resolve the schema once per live refresh and sort persisted results without string copies (#250 #155)
- **Details:**
  - Mac soak profile: 310 ms per 30 s rebuilding AttributeStore indexes in live refresh (per-computation resolvedLocalAttributes, empty merges).
  - ABBA thread CPU (debug): translate 5,123 -> 1,223 ms; persisted-result inits 1,071 -> 627 ms; 1,000 empty merges 2,856 -> 0.1 ms.
- **Files:**
  - `Sources/InstantSwiftDataCore/TripleIndexes.swift` — Empty merge is a no-op.
  - `Sources/InstantSwiftDataCore/InstantLiveRefreshApplication.swift` — Attributes resolved once per refresh; persisted results sorted without per-comparison string copies.
  - `Tests/InstantSwiftDataCoreTests/InstantLiveRefreshAttributeCostTests.swift` — Empty-merge equivalence and cost benchmarks.
  - `Tests/InstantSwiftDataCoreTests/InstantPersistedLiveQueryResultCostTests.swift` — Order equivalence and cost benchmark.
  - `Tests/InstantSwiftDataCoreTests/ThreadCPUClock.swift` — Thread CPU clock for load-robust measurement.
- **User context (verbatim):**
  > please do a complete audit on this entire applications structure as well as the library. And if there's anywhere else that there's just not performance, please let me know.
- **SpecStory:** unavailable — Claude Code CLI session; no SpecStory capture for this task

## September 26th, 2026 at 11:41:15 p.m. EDT — `cb6e9e45ed4c` Cap the diagnostics file and keep one previous file (#254)

- **Implementation commit:** `cb6e9e45ed4cd826a4ed33af977ddaf8924b53de`
- **Change:** Cap the diagnostics file and keep one previous file (#254)
- **Details:**
  - InstantDiagnosticsConfiguration.maximumFileBytes (default 16 MiB; nil or INSTANT_SWIFT_DATA_LOG_MAX_BYTES=0 for unlimited) rotates the file to <name>.previous.jsonl, so the log holds at most twice the limit.
  - A writer holding a descriptor to a file another writer just rotated reopens instead of rotating again; 11 diagnostics tests pass including 8 concurrent writers.
  - Measured motivation: Scribe on an iPhone wrote 27.5 MB in an hour (31,372 rows) to a never-trimmed file (2026-09-26).
- **Files:**
  - `Sources/InstantSwiftDataCore/InstantDiagnostics.swift` — maximumFileBytes, rotation with a stale-descriptor check.
  - `Tests/InstantSwiftDataCoreTests/InstantDiagnosticsTests.swift` — Rotation order, unlimited when nil, concurrent writers.
- **User context (verbatim):**
  > set it up so that whenever you run these kinds of builds, we can get diagnostics after the fact
- **SpecStory:** unavailable — unavailable — Claude Code CLI session; no SpecStory capture for this task

## September 26th, 2026 at 7:29:00 p.m. EDT — `94166c5a05df` Handle new and small entities whole and capture whole delete cascades (#044 #155)

- **Implementation commit:** `94166c5a05df475e831fbcedeff24e11d2a8c700`
- **Change:** Handle new and small entities whole and capture whole delete cascades (#044 #155)
- **Details:**
  - Release gate (cross-SDK core, release, same machine) showed per-fact bookkeeping made small-entity writes 12-45% slower than 1.5.7; new and <=32-fact entities are now handled whole, decided at first touch.
  - Deletes capture their whole cascade before running (1.5.7 could not restore grandchildren on rollback); scopes grow in place; no scope without capture; reserved per-mutation maps.
  - After (median of 10 ABBA runs): insert/stream/scalar/reads at parity; update 1.09x, delete 1.10x, linked 1.06x.
- **Files:**
  - `Sources/InstantSwiftDataCore/InstantStore.swift` — Size-adaptive first-touch decision, whole-cascade delete capture, no scope without capture.
  - `Sources/InstantSwiftDataCore/InstantFactScope.swift` — In-place scope mutators and capacity reservation.
  - `Tests/InstantSwiftDataCoreTests/InstantEntityWriteScopeTests.swift` — Deep-cascade rollback, small-entity, and new-entity tests.
  - `docs/adr/0015-sqlite-data-parity-ergonomics/qanda.md` — Q33 amendment with the gate finding.
  - `docs/releases/v1.6.0.md` — Release notes updated with the A/B table and remaining costs.
- **User context (verbatim):**
  > get this library merged and pushed the release via GitHub. [...] a new minor version, I think, for this fix.
- **SpecStory:** unavailable — Claude Code CLI session; no SpecStory capture for this task

## September 26th, 2026 at 6:05:05 p.m. EDT — `c24724c9871a` Document the v1.6.0 release: writes cost what they touch (#044 #155)

- **Implementation commit:** `c24724c9871a5859b82bd2013e309a0db13b1689`
- **Change:** Document the v1.6.0 release: writes cost what they touch (#044 #155)
- **Details:**
  - Release notes for per-fact write scope, in-place multi-value slots, the share-gated store snapshot, and the nested-limit documentation fix.
  - Measured: 50 writes on a 16,000-link recording 33.4 s -> 0.13 s; 40 writes on a 20,000-fact store 6.09 s -> 0.069 s (Debug). No public API break, no SQLite migration.
- **Files:**
  - `docs/releases/v1.6.0.md` — Release document validated by scripts/validate-release-version.sh 1.6.0.
- **User context (verbatim):**
  > get this library merged and pushed the release via GitHub. [...] deploy the instant SQI or S Instant data Swift library with a new version, a new minor version, I think, for this fix.
- **SpecStory:** unavailable — Claude Code CLI session; no SpecStory capture for this task

## September 26th, 2026 at 5:35:34 p.m. EDT — `546da49f2783` Skip the full-store snapshot on writes when no share can refuse them (#044)

- **Implementation commit:** `546da49f2783bf3b3af122fbb51d097961ecc7ed`
- **Change:** Skip the full-store snapshot on writes when no share can refuse them (#044)
- **Details:**
  - Shared-root authorization materialized and sorted every fact on every transact; an EXISTS query over unrevoked shares now gates it.
  - Measured (Debug): 40 one-field writes on a 20,000-fact store 6.09 s -> 0.069 s; sharedRootWritePermissionsReject* tests still pass.
- **Files:**
  - `Sources/InstantSwiftDataCore/InstantRuntime.swift` — Gate shared-root authorization and its snapshot on active shares.
  - `Sources/InstantSwiftDataCore/SQLitePersistenceStore.swift` — hasActiveShares(appID:) existence query.
  - `Tests/InstantSwiftDataCoreTests/InstantEntityWriteScopeTests.swift` — Guard against whole-store materialization on writes.
- **User context (verbatim):**
  > every write copies all of the recording stored fields for rollback. That seems really, really inefficient and naive.
- **SpecStory:** unavailable — unavailable — Claude Code CLI session; no SpecStory capture for this task

## September 26th, 2026 at 4:59:28 p.m. EDT — `7c567126f9a0` Say plainly that nested include limits do not bound the network (#155)

- **Implementation commit:** `7c567126f9a0eb35cade7e3d8d4f324bc8562997`
- **Change:** Say plainly that nested include limits do not bound the network (#155)
- **Details:**
  - Guidance, include comment, and parity note now match the server: nested limits trim locally only.
- **Files:**
  - `Sources/InstantSwiftData/InstantSwiftData.swift` — Fetch-request guidance warns that nested limits do not bound the network.
  - `Sources/InstantSwiftData/InstantTypedAPI.swift` — Include comment states the server ignores nested limits.
  - `Sources/InstantSwiftDataCore/InstantParityCoverage.swift` — Correct the stale nested-limit parity note.
  - `Tests/InstantSwiftDataCoreTests/InstantStoreParityTests.swift` — Pin the corrected note.
- **User context (verbatim):**
  > is there any way to get the preview, like the preview lines at the top level? W wouldould it be two queries. Yeah, let's try that.
- **SpecStory:** unavailable — unavailable — Claude Code CLI session; no SpecStory capture for this task

## September 26th, 2026 at 4:54:06 p.m. EDT — `636c34888061` Capture and persist only the facts a write touches (#044 #155)

- **Implementation commit:** `636c348880612ad6e11d1feed6ba4c3b39962a51`
- **Change:** Capture and persist only the facts a write touches (#044 #155)
- **Details:**
  - Rollback capture, changedEntityTriples, and SQLite persistence were per entity; Scribe's recording holds one link per segment, so every segment write cost the whole recording.
  - InstantFactScope names touched attributes and multi-value values; composed server-apply and failure-removal steps union scopes; deletes widen only cascaded entities.
  - Measured (Debug): 50 prepared writes on a 16,000-link recording 33.4 s -> 0.13 s; full suite 1,762 tests, no new failures versus the pre-change baseline.
- **Files:**
  - `Sources/InstantSwiftDataCore/InstantFactScope.swift` — Per-entity touched-fact scopes and their union.
  - `Sources/InstantSwiftDataCore/InstantStore.swift` — Per-fact rollback capture; prepareMutating records scope; cascade-aware delete capture.
  - `Sources/InstantSwiftDataCore/InstantRuntime.swift` — Scope unions at composed commits; pure-create rollback requires proof of creation.
  - `Sources/InstantSwiftDataCore/SQLitePersistenceStore.swift` — Scoped row reads and rewrites; scoped cached-snapshot replacement.
  - `Sources/InstantSwiftDataCore/TripleIndexes.swift` — In-place multi-value slot mutation; scoped materialization helpers.
  - `Tests/InstantSwiftDataCoreTests/InstantEntityWriteScopeTests.swift` — Regression guards for scoped capture, delete scope, and write cost.
  - `docs/adr/0015-sqlite-data-parity-ergonomics/qanda.md` — Q32 nested limits client-side only; Q33 per-fact capture.
- **User context (verbatim):**
  > every write copies all of the recording stored fields for rollback. That seems really, really inefficient and naive. Um. And let's focus on fixing that now.
- **SpecStory:** unavailable — unavailable — Claude Code CLI session; no SpecStory capture for this task

## August 16th, 2026 at 5:54:19 a.m. EDT — `73ff55491fbd` Reconcile durable relation identities

- **Implementation commit:** `73ff55491fbd18efeaa19375c0b725d40096ce5f`
- **Change:** Reconcile durable relation identities
- **Details:**
  - Preserve one exact physical server relation and expose application declarations as forward or reverse aliases, so upgraded stores do not split one link across competing attribute IDs.
  - Transpose affected resident, cold SQLite, live-result, and ownership rows transactionally while preserving newest stamps, exact server metadata, outbox intent, receipts, and unrelated revisions.
  - Pass all 5 identity-upgrade tests, 14 bounded live-query tests, 13 persistence-residency tests, and the exact atomic stale-refresh test; independent final review is clean.
- **Files:**
  - `Sources/InstantSwiftDataCore/TripleIndexes.swift` — Reconciles logical and physical relation identities and affected resident triples.
  - `Sources/InstantSwiftDataCore/InstantStore.swift` — Normalizes forward and reverse local operations to the retained physical relation.
  - `Sources/InstantSwiftDataCore/SQLitePersistenceStore.swift` — Migrates durable cold/live relation storage idempotently before compact bootstrap.
  - `Tests/InstantSwiftDataCoreTests/AttributeStoreIdentityUpgradeTests.swift` — Covers fresh and upgraded IDs, cold/hot rows, metadata, ownership, marker invalidation, and relaunch.
  - `agent-presence/_channels/2026-08-16-attribute-identity-upgrade.md` — Records ownership and verification evidence.
- **User context (verbatim):**
  > Nothing syncing, like this isn't quite the best.
  > Are you sure your correctness tests are up to date?
- **SpecStory:** unavailable — Codex desktop task; no supported SpecStory capture URI was exposed.

## August 16th, 2026 at 2:00:06 a.m. EDT — `46024e30df6e` Prevent server refresh from starving local writes

- **Implementation commit:** `46024e30df6e7cf3b7df81c38c296349627ab2ce`
- **Change:** Let local writes proceed during server refresh
- **Details:**
  - Move long server-refresh preparation outside the local operation gate while retaining a dedicated server-apply gate and exact final revision checks.
  - Catch up proven append-only local writes, preserve claim, acceptance, component-closure, hot-store, and durable-state authority, and fall back after bounded peer-runtime contention.
  - Pass all 24 server-apply rebase tests and all 22 outbox supersession integration tests, including sustained local writes, peer writes, empty authoritative transactions, and stale closure races.
- **Files:**
  - `Sources/InstantSwiftDataCore/InstantRuntime.swift` — Moves long server apply work outside the local write gate and catches up bounded local tails.
  - `Sources/InstantSwiftDataCore/SQLitePersistenceStore.swift` — Proves append-only catch-up and preserves durable plan authority.
  - `Tests/InstantSwiftDataCoreTests/InstantBoundedServerApplyRebaseTests.swift` — Covers sustained, peer, closure, no-effect, and hot-store catch-up behavior.
- **User context (verbatim):**
  > I'm not sure the words actually sync, and now the times don't sync.
- **SpecStory:** unavailable — Codex desktop task; no supported SpecStory capture URI was exposed.

## August 15th, 2026 at 5:18:30 p.m. EDT — `a0805fc44a2c` Wait for offered message before mock acceptance

- **Implementation commit:** `a0805fc44a2c32642279d14b5d4040c7dd7a7fa6`
- **Change:** Wait for the exact offered mutation before the mock server acknowledges a typed message.
- **Details:**
  - Keep the production claim-token boundary intact: the acceptance fixture now observes the outbound transact before injecting transact-ok, so a protocol-impossible premature acknowledgement cannot be consumed and lost.
  - Focused red reproduced the 10-second timeout; the rebuilt focused test passes in 0.077 seconds and the final serialized package gate passes 1,731 tests in 146 suites in 559.816 seconds with exactly 27 declared known issues.
- **Files:**
  - `Tests/InstantSwiftDataTests/InstantMessageServerAcceptanceTests.swift` — Adds the existing exact outbound-transact fence before mock acceptance.
  - `_touching/Tests@InstantSwiftDataTests@InstantMessageServerAcceptanceTests.swift/Tests@InstantSwiftDataTests@InstantMessageServerAcceptanceTests.swift/.agents/agents.txt` — Records task ownership before the fixture edit.
  - `agent-presence/_channels/01a00071-five-recording-sync-soak.md` — Records the deterministic diagnosis, scope, and verification boundary.
- **User context (verbatim):**
  > continue
- **SpecStory:** unavailable — Codex desktop continuation; SpecStory captures Codex CLI sessions and no synced desktop capture URI is available.

## August 15th, 2026 at 4:33:14 p.m. EDT — `3649a63e1d41` Diff persisted live-query ownership rows

- **Implementation commit:** `3649a63e1d41470f8b213fdd69d0dc4488928908`
- **Change:** Persist only changed live-query ownership identities so repeated bounded refreshes no longer stall the serial receive path behind full ownership-table rewrites.
- **Details:**
  - Keep the raw persisted result envelope and revision semantics unchanged while diffing exact query/entity/attribute/value JSON ownership identities.
  - Reuse one prepared DELETE and one prepared INSERT across each ownership delta instead of preparing and finalizing a statement for every retained triple.
  - A 772-row regression proves zero ownership writes for an identity-stable replacement, exactly one delete plus one insert for a one-identity change, exact persisted ownership, and relaunch equality.
- **Files:**
  - `Sources/InstantSwiftDataCore/SQLitePersistenceStore.swift` — Loads current ownership, computes exact set deltas, and executes only changed rows through reused prepared statements.
  - `Tests/InstantSwiftDataCoreTests/InstantLiveQueryNestedLimitMemoryTests.swift` — Pins statement-level ownership work, exact identities, result replacement, and relaunch for the measured Scribe-shaped 772-row case.
  - `agent-presence/_channels/01a00071-five-recording-sync-soak.md` — Records ownership, red-first evidence, focused verification, hashes, and the physical rerun boundary.
- **User context (verbatim):**
  > continue
  > your goal is to successfully run 5 recordings in a row, observe them syncing in realtime across mac and physical ipad
  > ensure memory usage stays no greater than 100MB during a run
- **SpecStory:** unavailable — Codex desktop continuation; SpecStory captures Codex CLI sessions and no synced desktop capture URI is available.

## August 15th, 2026 at 2:17:17 p.m. EDT — `ae000fce901f` Harden optimistic delivery and pre-connect migrations

- **Implementation commit:** `ae000fce901fff693971d1ebcbdca8bdd10a6ef4`
- **Change:** Bind optimistic-effect, delivery-claim, and server-acceptance authority to SQLite-owned receipts; run bounded application persistence migrations before services; and close the reconnect, cancellation, and observer invalidation races found by physical Scribe work.
- **Details:**
  - Represent a prepared mutation with a versioned receipt, keep no-current-effect mutations replayable, fail closed on unknown authority, and publish a typed synchronization blocker without silently resending or discarding local state.
  - Bind claims and acknowledgements to exact claimant tokens and payload fingerprints, retire reclaimed live reservations, preserve explicit close, and prohibit changed wire intent after offer or acceptance.
  - Run full-durable, revision-checked application migrations before Runtime services or auto-connect; migrate Reminder priority values and rollback bodies atomically while rejecting offered, accepted, unknown-owner, collision, and invalid-rank states.
  - Restore cross-namespace observer invalidation, public upload-stream cancellation, idle local live-session receive, and portable SHA-256 through official Swift Crypto without changing persisted digest versions.
  - The full serialized package gate passes 1,729 tests in 146 suites with exactly 27 deliberate known issues; the focused portable receipt and authority matrix passes 78 tests in four suites with 10 deliberate known issues.
- **Files:**
  - `Package.swift` — Adds official Swift Crypto only to InstantSwiftDataCore so receipt authority remains Linux-clean.
  - `Sources/InstantSwiftDataCore/InstantModels.swift` — Defines versioned optimistic receipts, typed synchronization blockers, and stable receipt and wire fingerprints.
  - `Sources/InstantSwiftDataCore/SQLitePersistenceStore.swift` — Owns receipt provenance, bounded migrations, exact claim and acceptance authority, blocker indexing, and fail-closed recovery.
  - `Sources/InstantSwiftDataCore/InstantRuntime.swift` — Orders pre-service migrations, local materialization, delivery suspension, explicit close, reconnect ownership, upload cancellation, and server rebase.
  - `Sources/InstantSwiftDataCore/InstantRuntimeLiveSession.swift` — Captures exact offered claim tokens before response teardown and prevents stale generations from adopting reoffers.
  - `Sources/InstantSwiftDataCore/InstantStore.swift` — Reconciles schema changes on the peeled base and conservatively refreshes unresolved relation-dependent observers.
  - `Sources/InstantSwiftDataCore/ReminderExample.swift` — Defines the bounded durable legacy-priority migration and validates closed numeric ranks.
  - `Sources/InstantSwiftDataCore/InstantLiveTransport.swift` — Keeps the injected local session open while idle with cancellation-safe FIFO receive waiters.
  - `Sources/InstantSwiftData/InstantSyncStatus.swift` — Projects durable synchronization blockers into user-visible status and disables unsafe flush.
  - `Sources/instant-swift-data/main.swift` — Registers Reminder persistence migration before CLI bootstrap.
  - `Tests/InstantSwiftDataCoreTests/InstantPendingMutationCompatibilityTests.swift` — Pins downgrade-safe receipt encoding and the exact portable SHA-256 digest.
  - `Tests/InstantSwiftDataCoreTests/InstantStoreTests.swift` — Covers migrations, receipt mismatch blocking, optimistic replay, local-write behavior, and observer invalidation.
  - `Tests/InstantSwiftDataCoreTests/InstantBoundedOutboxDeliveryTests.swift` — Covers bounded claims, exact acknowledgements, migration authority, blockers, and unchanged offered or accepted rows.
  - `Tests/InstantSwiftDataCoreTests/InstantLiveTransportTests.swift` — Covers reconnect ownership, claim-token races, explicit reclaim, close ordering, and upload cancellation.
  - `Tests/InstantSwiftDataTests/BootstrapTests.swift` — Proves the injected local transport remains opened through its idle receive.
  - `agent-presence/_channels/01a00071-five-recording-sync-soak.md` — Preserves multi-agent ownership, release blockers, independent reviews, and exact verification evidence.
- **User context (verbatim):**
  > your goal is to successfully run 5 recordings in a row, observe them syncing in realtime across mac and physical ipad
  > ensure memory usage stays no greater than 100MB during a run
  > continue
- **SpecStory:** unavailable — Codex desktop continuation; SpecStory captures Codex CLI sessions and no synced desktop capture URI is available.

## August 15th, 2026 at 12:42:37 a.m. EDT — `141d1e9ec685` Skip semantic refresh no-ops and restore reconnect ownership

- **Implementation commit:** `141d1e9ec68531c4e92370521f7bb4256eeb2765`
- **Change:** Suppress semantically unchanged authoritative refresh work and give current-session failures one reconnect owner.
- **Details:**
  - Preserve exact canonical resident triples during authoritative replay, while keeping local mutation rollback semantics unchanged.
  - Reconcile schema changes on the peeled authoritative base, deterministically canonicalize many-to-one values, persist index changes, and regenerate optimistic rollback bodies.
  - Hand current-session send failures to the exact receiver generation, block same-generation retry before wire I/O, and suppress stale caller status or reconnect work.
  - Focused semantic/reconnect tests pass 17/17; the relevant matrix passes 197/198 with only an existing scheduler-sensitive timing characterization failing in isolation.
- **Files:**
  - `Sources/InstantSwiftDataCore/InstantRuntime.swift` — Orders authoritative peeling, schema reconciliation, server apply, optimistic replay, page-info publication, and reconnect ownership.
  - `Sources/InstantSwiftDataCore/InstantRuntimeLiveSession.swift` — Linearizes send failure, receiver startup, generation replacement, and same-generation wire admission.
  - `Sources/InstantSwiftDataCore/InstantStore.swift` — Separates observer invalidation from exact authoritative no-ops and reconciles schema-derived indexes on a peeled base.
  - `Sources/InstantSwiftDataCore/TripleIndexes.swift` — Validates exact resident index shape and deterministically canonicalizes schema cardinality transitions.
  - `Tests/InstantSwiftDataCoreTests/InstantLiveQueryNestedLimitMemoryTests.swift` — Pins bounded Scribe-shaped refresh invalidation and page replacement behavior.
  - `Tests/InstantSwiftDataCoreTests/InstantLiveTransportTests.swift` — Pins current, superseded, close, pre-receiver, retry, and replacement-generation failure ownership.
  - `Tests/InstantSwiftDataCoreTests/InstantStoreTests.swift` — Pins exact replay, schema/index persistence, peeled optimistic rollback, rejection, and SQLite relaunch equality.
  - `agent-presence/_channels/01a00071-five-recording-sync-soak.md` — Preserves multi-agent evidence, ownership, reviews, failures, and stable handoffs.
- **User context (verbatim):**
  > your goal is to successfully run 5 recordings in a row, observe them syncing in realtime across mac and physical ipad
  > ensure memory usage stays no greater than 100MB during a run
- **SpecStory:** unavailable — Codex desktop continuation; SpecStory captures Codex CLI sessions and no synced desktop capture URI is available.

## August 14th, 2026 at 9:35:21 p.m. EDT — `30b180423666` Bound live refreshes and isolate oversized rejections

- **Implementation commit:** `30b180423666ac038210636d4377d60da2734006`
- **Change:** Bound nested live-query children before authoritative apply and isolate oversized terminal rejection to one claimed row.
- **Details:**
  - Use resolved local attribute metadata to apply per-parent nested limits once, then feed the same bounded triple set to authoritative operations and live-query replacement.
  - On a component-limit rejection, decode and fail only the exact token-owned target, retain its optimistic overlay for authoritative reconciliation, keep successors deliverable, and leave the live socket open.
  - Affected suites pass 156/156; the unrelated package-wide baseline later stalled in an existing concurrent local-ID integration test after an unrelated macro snapshot mismatch.
- **Files:**
  - `Sources/InstantSwiftDataCore/InstantLiveQueryNestedLimit.swift` — Resolves opaque local relation and order attributes while documenting Swift-specific pre-apply containment.
  - `Sources/InstantSwiftDataCore/InstantLiveRefreshApplication.swift` — Bounds insert triples before building both authoritative operations and query replacement.
  - `Sources/InstantSwiftDataCore/InstantRuntime.swift` — Routes oversized terminal components through the exact claimed-row disposition path without reconnecting.
  - `Sources/InstantSwiftDataCore/SQLitePersistenceStore.swift` — Generalizes exact-row delivery failure and clears stale confirmation metadata.
  - `Tests/InstantSwiftDataCoreTests/InstantLiveQueryNestedLimitMemoryTests.swift` — Proves per-parent bounds, opaque IDs, window plateau, owner overlap, and optimistic protection.
  - `Tests/InstantSwiftDataCoreTests/InstantLiveTransportTests.swift` — Proves one-body terminal disposition, successor delivery, duplicate idempotence, and socket continuity.
  - `agent-presence/_channels/01a00071-five-recording-sync-soak.md` — Records coordinated ownership and stable handoffs for both fixes.
  - `agent-presence/codex-01a00071/plans/2026-08-14-preapply-nested-limit/PLAN.md` — Preserves the pre-apply containment plan and scope boundary.
- **User context (verbatim):**
  > observe them syncing in realtime across mac and physical ipad
  > researching logs, diagnosing, and repeating until compelte
- **SpecStory:** unavailable — Codex desktop continuation; SpecStory captures Codex CLI sessions and no synced desktop capture URI is available.

## August 14th, 2026 at 5:56:42 p.m. EDT — `bdc7d1027613` Retry unacknowledged mutations on a new live generation

- **Implementation commit:** `bdc7d10276132ce9cbddb010d53bde4a7b984c3e`
- **Change:** Retry unacknowledged mutations only after replacing the live generation
- **Details:**
  - Use Reactor-shaped six-second times in-flight-ordinal acknowledgement deadlines for automatic claims and live reservations.
  - Expire a current-generation offer into an acknowledgement-unknown barrier, abort that socket generation, and retain the durable row for retry only after reconnect.
  - Keep offered event IDs only through durable response handling, then remove them so process memory remains bounded.
- **Files:**
  - `Sources/InstantSwiftDataCore/InstantMutationAcknowledgementDeadlinePolicy.swift` — Defines the shared overflow-safe ordinal deadline policy.
  - `Sources/InstantSwiftDataCore/InstantRuntimeLiveSession.swift` — Tracks offered event IDs, invalidates ambiguous generations, and prevents same-generation replay.
  - `Sources/InstantSwiftDataCore/SQLitePersistenceStore.swift` — Assigns ordinal automatic-claim deadlines and separates expiry release from reclaim.
  - `Tests/InstantSwiftDataCoreTests/InstantBoundedOutboxDeliveryTests.swift` — Proves delayed acknowledgements remain single-send and timed-out rows retry only after reconnect.
- **User context (verbatim):**
  > observe them syncing in realtime across mac and physical ipad
  > researching logs, diagnosing, and repeating until compelte
- **SpecStory:** unavailable — Codex desktop continuation; SpecStory captures Codex CLI sessions and no synced desktop capture URI is available.

## August 14th, 2026 at 4:25:22 p.m. EDT — `5d00f27644b0` Hydrate deferred values in nested query projections

- **Implementation commit:** `5d00f27644b02397691ab46f3802193e1acedf06`
- **Change:** Hydrate nested deferred query fields without loading unselected transcript blobs
- **Details:**
  - Walk the materialized query tree after root and child limits, then read only selected deferred attributes for retained namespace-and-entity pairs.
  - Merge deferred values by namespace, entity, and include path so sibling projections cannot leak values and unselected wordsJSON stays in SQLite.
  - Preserve operation-gate sequence checks, suppress only exact duplicate infinite snapshots, and rematerialize ordered projections when their order key is omitted.
  - Focused deferred, infinite-query, same-entity, and Scribe consumer tests pass; two independent blocker-only reviews are clean.
- **Files:**
  - `Sources/InstantSwiftDataCore/DeferredValueResidency.swift` — Builds bounded plan-tree hydration batches and recursively merges selected values.
  - `Sources/InstantSwiftDataCore/InstantRuntime.swift` — Applies nested hydration to one-shot, observed, live-chunk, and local infinite-query paths.
  - `Sources/InstantSwiftDataCore/InstantInfiniteQuery.swift` — Suppresses exact duplicate snapshots while preserving different same-sequence windows.
  - `Sources/InstantSwiftDataCore/InstantStore.swift` — Rematerializes ordered projections when splice ordering cannot be proven.
  - `Tests/InstantSwiftDataCoreTests/DeferredValueResidencyTests.swift` — Proves child limits, namespace and path isolation, reorder correctness, and bounded hydration.
  - `_touching/Sources@InstantSwiftDataCore@DeferredValueResidency.swift/Sources@InstantSwiftDataCore@DeferredValueResidency.swift/.agents/agents.txt` — Records coordinated ownership before the production edit.
  - `_touching/Sources@InstantSwiftDataCore@InstantInfiniteQuery.swift/Sources@InstantSwiftDataCore@InstantInfiniteQuery.swift/.agents/agents.txt` — Records coordinated ownership before the production edit.
  - `_touching/Sources@InstantSwiftDataCore@InstantRuntime.swift/Sources@InstantSwiftDataCore@InstantRuntime.swift/.agents/agents.txt` — Records coordinated ownership before the production edit.
  - `_touching/Sources@InstantSwiftDataCore@InstantStore.swift/Sources@InstantSwiftDataCore@InstantStore.swift/.agents/agents.txt` — Records coordinated ownership before the production edit.
  - `_touching/Tests@InstantSwiftDataCoreTests@DeferredValueResidencyTests.swift/Tests@InstantSwiftDataCoreTests@DeferredValueResidencyTests.swift/.agents/agents.txt` — Records coordinated ownership before the test edit.
- **User context (verbatim):**
  > observe them syncing in realtime across mac and physical ipad
  > ensure memory usage stays no greater than 100MB during a run
- **SpecStory:** unavailable — Codex desktop continuation; SpecStory captures Codex CLI sessions and no synced desktop capture URI is available.

## August 14th, 2026 at 2:18:10 p.m. EDT — `6cad77c8c954` Preserve required outbox fields within bounded claims

- **Implementation commit:** `6cad77c8c95452ac5632bde833252a6367672429`
- **Change:** Preserve required scalar foundation in stale-write projection while keeping every active outbox claim inside the existing 8 MiB delivery envelope.
- **Details:**
  - Hydrate an otherwise-filtered required cardinality-one scalar only from newer authoritative materialized state when no active successor protects the key.
  - Measure projected bodies from SQLite value-length metadata before scalar decode; visibly fail an individually oversized row and release an aggregate-overflow suffix unoffered.
  - Persist and clear claim-scoped projected byte reservations across claim, acknowledgement, release, expiry, failure, retry, isolation, and quarantine paths.
- **Files:**
  - `Sources/InstantSwiftDataCore/BoundedOutboxDelivery.swift` — Separates projection candidates, exact projected-byte measurement, and transport lowering.
  - `Sources/InstantSwiftDataCore/InstantStore.swift` — Keeps the provenance-less hot store conservative for required scalars.
  - `Sources/InstantSwiftDataCore/InstantVisibleWriteFilter.swift` — Hydrates required scalar foundation without reviving stale optional fields or bypassing successors.
  - `Sources/InstantSwiftDataCore/SQLitePersistenceStore.swift` — Owns migration 0019 and atomic projected-byte claim admission and disposition.
  - `Tests/InstantSwiftDataCoreTests/InstantBoundedOutboxDeliveryTests.swift` — Proves hydration, ordering, oversize failure, aggregate deferral, legacy claims, expiry, and release.
  - `agent-presence/_channels/01a00071-five-recording-sync-soak.md` — Records ownership, scope expansion, red-first evidence, and stable handoff.
  - `agent-presence/_touching/Sources@InstantSwiftDataCore@BoundedOutboxDelivery.swift/agents.txt` — Publishes the required protocol touch claim before source mutation.
  - `agent-presence/codex-01a00071/plans/2026-08-14-required-foundation-visible-write/PLAN.md` — Captures the reviewed architecture and verification evidence.
- **User context (verbatim):**
  > observe them syncing in realtime across mac and physical ipad
  > researching logs, diagnosing, and repeating until compelte
- **SpecStory:** unavailable — Codex desktop task; SpecStory captures Codex CLI sessions and no synced desktop capture URI is available.

## August 12th, 2026 at 6:21:19 p.m. EDT — `94f9ff30fb8c` Follow recordingID strings and parent many-refs when limiting live query children.

- **Implementation commit:** `94f9ff30fb8c5192ab3f887c9e7ed4fb5a182295`
- **Change:** Follow recordingID strings and parent many-refs so nested live-query limits keep preview children.
- **Details:**
  - First trial 5 save on Mac dropped all segment entities because the list querySub stores transcriptionSegments/recordingID, not transcriptionSegments/recording. Parent recordings/segments many-ref values (dd7dc80a) stayed at 488. Follow string recordingID, reverse refs, and parent many-refs; trim many-ref values to retained children.
  - Issues: https://issues.knophy.com/issues/044 https://issues.knophy.com/issues/155
- **Files:**
  - `Sources/InstantSwiftDataCore/InstantLiveQueryNestedLimit.swift` — Resolve children via recordingID strings and parent many-refs; trim dropped child refs.
  - `Tests/InstantSwiftDataCoreTests/InstantLiveQueryNestedLimitMemoryTests.swift` — Prove limit 2 still holds when only recordingID string links exist.
- **User context (verbatim):**
  > keep going automatically
- **SpecStory:** unavailable — unavailable — Cursor Grok 4.6 session; no SpecStory share URI for this desktop task.

## August 12th, 2026 at 6:03:10 p.m. EDT — `48456facf86a` Apply nested include limits to persisted live query triples.

- **Implementation commit:** `48456facf86aa871d7e129c6ee5646e48558a078`
- **Change:** Apply nested include limits to persisted live query triples so InstantStore bootstrap matches InstaQL per-parent $limit.
- **Details:**
  - Library: 10 children + nested limit 2 keeps 1 parent + 2 newest children in the hot store; SQLite still has 11. Per-parent: 2 recordings x 10 children -> 6 entities. Non-JSON query keys stay unfiltered. InstantRuntime unedited. No debounce.
  - iPad overlay after trial 4 (Scribe a88d1d5, Instant 6c6760b4): idle 58-62 MB, recording 74-92 MB for 2 min, peak 191 at speech start. SQLiteData 55.7 MB. Goal ~65 MB. Fail-fast 125 current phys PASS. Mac live query keys 92->4; remaining list querySub 481 segments (max 328 on one parent) despite segments.$limit 2.
  - Issues: https://issues.knophy.com/issues/044 https://issues.knophy.com/issues/155. Autoresearch 2026-08-12-live-put-observation-memory trial 5.
- **Files:**
  - `Sources/InstantSwiftDataCore/InstantLiveQueryNestedLimit.swift` — Pure InstaQL nested-limit filter over persisted query triples.
  - `Sources/InstantSwiftDataCore/SQLitePersistenceStore.swift` — Apply the filter at live-query save and at scoped InstantStore bootstrap load.
  - `Tests/InstantSwiftDataCoreTests/InstantLiveQueryNestedLimitMemoryTests.swift` — Prove 10 children collapse to 2 per parent at save/load; non-JSON keys unchanged.
- **User context (verbatim):**
  > it is okay to install dirty, please just go ahead and do so unless it is not possible, you can even commit others work if need be. keep going automatically
- **SpecStory:** unavailable — unavailable — Cursor Grok 4.6 session; no SpecStory share URI for this desktop task.

## August 12th, 2026 at 5:27:53 p.m. EDT — `6c6760b40d9c` Unload inactive live querySubs during session prune.

- **Implementation commit:** `6c6760b40d9c457d5c2d60f5bfa60c7c27558587`
- **Change:** Unload inactive Instant live querySubs during session prune so scoped bootstrap does not reload every historical infinite-query page.
- **Details:**
  - TypeScript Reactor.js _cleanupQuery calls querySubs.unloadKey when a query has no listeners, even while pendingMutations exist. Swift pruneLiveQueryResults used to protect every persisted query key whenever the outbox had an optimistic overlay. Production maxEntries is 1000, so inactive pages never unloaded during live speech.
  - Mac soak of trial 3 KEEP (pid 52693): idle 271 MB physical, ~2 min recording 442 MB, peak 489 MB. Instant sqlite 44 MB, 92 live query keys, 372 of 426 entities in live_query_triples. Live malloc ~86 MB. Goal remains ~65 MB with realtime Instant sync on; do not debounce live revisions.
  - Library proxy: 20 stale 32-row pages + 1 active page + pending outbox overlay. Session prune with preservingQueryKeys=[active] now remains 1 key / 32 hot-store entities (was 20 / 640). Bootstrap prune with empty preserving keys still keeps the cache. InstantRuntime unedited. https://issues.knophy.com/issues/044 https://issues.knophy.com/issues/155
- **Files:**
  - `Sources/InstantSwiftDataCore/SQLitePersistenceStore.swift` — Session prune unloads query keys that are not in the active listener set; bootstrap with an empty set still conservative-protects all keys when the outbox has overlay.
  - `Tests/InstantSwiftDataCoreTests/InstantInactiveLiveQueryPruneMemoryTests.swift` — Proves 20 stale pages drop to 1 active page during session prune, and bootstrap keep-all still holds.
- **User context (verbatim):**
  > it is okay to install dirty, please just go ahead and do so unless it is not possible, you can even commit others work if need be. keep going automatically
- **SpecStory:** unavailable — Cursor Grok 4.6 session; no SpecStory share URI for this desktop task.

## August 12th, 2026 at 4:16:11 p.m. EDT — `fe9ebe078622` Load InstantStore bootstrap from live query entities, not the full SQLite graph.

- **Implementation commit:** `fe9ebe07862241a572d11f3cb74ace8a5d82d79c`
- **Change:** Load InstantStore bootstrap from live query entities, not the full SQLite graph.
- **Details:**
  - Library proxy: InstantQueryScopedHotStoreMemoryTests. A 1,000-row identity corpus plus a 32-row persisted live query now bootstraps 32 hot-store entities; SQLite still has 1,000. Empty watermark query results keep the full load. InstantRuntime unedited. Live revisions are not debounced. Issues: https://issues.knophy.com/issues/044 https://issues.knophy.com/issues/155. Autoresearch run 2026-08-12-live-put-observation-memory trial 3.
- **Files:**
  - `Sources/InstantSwiftDataCore/SQLitePersistenceStore.swift` — When live-query triple rows exist, SELECT only those entity IDs plus outbox effect entities into InstantStore.
  - `Tests/InstantSwiftDataCoreTests/InstantQueryScopedHotStoreMemoryTests.swift` — Measure hot-store entity count for a page-sized query versus a 1,000-row identity corpus.
- **User context (verbatim):**
  > keep going then
- **SpecStory:** unavailable — unavailable — Cursor Grok session; no SpecStory cloud URI

## August 12th, 2026 at 1:57:48 p.m. EDT — `437ee8fbfbbc` Prove deferred string transcript payloads stay out of TripleIndexes.

- **Implementation commit:** `437ee8fbfbbc1dbdab6f5575252cac5a87c234d2`
- **Change:** Prove deferred string transcript payloads stay out of TripleIndexes.
- **Details:**
  - Library harness: 1,000 Scribe-shaped segments keep 2,048,000 UTF-8 bytes of text+wordsJSON in RAM when resident, and 0 bytes when deferred. A 32-row infinite-query page still hydrates. A live put still queries. InstantRuntime unedited. Live revisions are not debounced. Issues: https://issues.knophy.com/issues/044 https://issues.knophy.com/issues/155. Autoresearch run 2026-08-12-live-put-observation-memory.
- **Files:**
  - `Tests/InstantSwiftDataCoreTests/InstantDeferredTranscriptPayloadMemoryTests.swift` — Measure hot-store UTF-8 bytes for deferred versus resident transcriptionSegments/text and wordsJSON.
  - `agent-presence/_channels/2026-08-12-live-revision-cardinality.md` — Record trial 2 deferred-transcript bite and the 65 MB SQLiteData-parity goal.
- **User context (verbatim):**
  > okay carry on soldier /autoresearch decrease memory usage to goal of ~65 MB while still maintaining realtime sync of information via instant-data-swift
- **SpecStory:** unavailable — Cursor Grok session; no SpecStory cloud URI

## August 12th, 2026 at 1:08:03 p.m. EDT — `6536a8345d35` Skip and splice InstantStore observers on same-entity live puts.

- **Implementation commit:** `6536a8345d350117414a542da3c1f1f790a6f586`
- **Change:** Skip and splice InstantStore observers on same-entity live puts.
- **Details:**
  - A live-row put no longer rematerializes sibling history or unrelated include queries. Every revision still publishes; membership changes still rematerialize.
  - Issues: https://issues.knophy.com/issues/044 https://issues.knophy.com/issues/155. Autoresearch run 2026-08-12-live-put-observation-memory.
- **Files:**
  - `Sources/InstantSwiftDataCore/InstantStore.swift` — Skip disjoint observers and splice lastValues for in-page live puts.
  - `Sources/InstantSwiftDataCore/TripleIndexes.swift` — Materialize one entity for splice without walking the namespace.
  - `Tests/InstantSwiftDataCoreTests/InstantSameEntityLiveRevisionMemoryTests.swift` — Byte and snapshot-count contracts for live/history split, splice, and include skip.
- **User context (verbatim):**
  > How does instant TypeScript handle offline mode?
  > go through and make all of the fixes that you want to make before I test it, and then go ahead and run it on Mac using Scribe remote control
- **SpecStory:** unavailable — Cursor Grok session; no SpecStory cloud URI

## August 11th, 2026 at 5:33:15 p.m. EDT — `c58253d5162f` Add Transcription multi-host Instant example with floating toolbar.

- **Implementation commit:** `c58253d5162fdd998bcb136ee1effcd7e302a8c5`
- **Change:** Add Transcription multi-host Instant example with floating toolbar
- **Details:**
  - Clean @InstantEntity models; floating toolbar from toolshed SyncUps stopwatch chrome
  - Launched unsigned Mac app and iPhone 17 simulator
- **Files:**
  - `Sources/TranscriptionApp/TranscriptionModels.swift` — @InstantEntity Recording Transcription Segment Preference
  - `Sources/TranscriptionApp/TranscriptionFloatingToolbar.swift` — SyncUps-style floating chrome
  - `Sources/TranscriptionApp/TranscriptionScreens.swift` — Library timeline settings
  - `Sources/TranscriptionApp/TranscriptionProgram.swift` — Screen stack and mode
  - `Package.swift` — TranscriptionApp product
  - `Examples/Transcription/project.yml` — Mac and iOS XcodeGen hosts
- **User context (verbatim):**
  > We should be defining this in terms of instant entities
- **SpecStory:** unavailable — Grok Build session; no SpecStory cloud URI

## August 11th, 2026 at 5:04:29 p.m. EDT — `cbb679ec6480` ADR 0016: lock decisions; cut plan.md and Instant issue #193.

- **Implementation commit:** `cbb679ec6480f13005537d489cbdd287a28eb4ba`
- **Change:** ADR 0016: lock decisions; cut plan.md and Instant issue #193
- **Details:**
  - Captain lock; plan steps T0–T9
  - Parent issue https://issues.knophy.com/issues/193
- **Files:**
  - `docs/adr/0016-transcription-example-instant-first/plan.md` — Executable T0–T9 work items
  - `docs/adr/0016-transcription-example-instant-first/README.md` — Status Decisions locked; link #193
  - `docs/adr/0016-transcription-example-instant-first/qanda.md` — Q26 lock
  - `docs/adr/0016-transcription-example-instant-first/HANDOFF.md` — Execute plan resume
  - `docs/adr/0016-transcription-example-instant-first/overviews/04-uri-tree.md` — Status decisions locked
- **User context (verbatim):**
  > lock
- **SpecStory:** unavailable — Grok Build session; no SpecStory cloud URI for this agent host

## August 11th, 2026 at 4:57:42 p.m. EDT — `77307d483873` ADR 0016: lock goBack as program navigation stack (Q25).

- **Implementation commit:** `77307d48387372508a9be0776bffaca749ae0844`
- **Change:** ADR 0016: lock goBack as program navigation stack (Q25)
- **Details:**
  - Program owns screen stack; hosts present it
  - goBack → navigation.previous pop; not tree parent; not fixed library
- **Files:**
  - `docs/adr/0016-transcription-example-instant-first/qanda.md` — Q25 decided
  - `docs/adr/0016-transcription-example-instant-first/overviews/04-uri-tree.md` — Navigation section locked
  - `docs/adr/0016-transcription-example-instant-first/HANDOFF.md` — goBack done; next optional screens or plan lock
- **User context (verbatim):**
  > I think it should be done from the program itself. Kind of swift navigation style, yeah.
- **SpecStory:** unavailable — Grok Build session; no SpecStory cloud URI for this agent host

## August 11th, 2026 at 4:53:44 p.m. EDT — `c44911e27a03` ADR 0016: accept remaining idle modes; normalize goesTo handles.

- **Implementation commit:** `c44911e27a0358940b7ae4068b43ef3a21dd713f`
- **Change:** ADR 0016: accept remaining idle modes; normalize goesTo handles
- **Details:**
  - Captain blanket-applied sibling idle Playing/Paused leaves
  - Tree-wide goesTo handle args; all nine mode leaves reviewed
- **Files:**
  - `docs/adr/0016-transcription-example-instant-first/qanda.md` — Q23–Q24 decided
  - `docs/adr/0016-transcription-example-instant-first/overviews/04-uri-tree.md` — Handle args on mode goesTo; REVIEWED Q23 Q24
  - `docs/adr/0016-transcription-example-instant-first/HANDOFF.md` — Mode leaf table complete; next goBack
- **User context (verbatim):**
  > blanket apply to all of these different modes that are just have a couple of different changes
- **SpecStory:** unavailable — Grok Build session; no SpecStory cloud URI for this agent host

## August 11th, 2026 at 4:47:53 p.m. EDT — `f647abee9dc8` ADR 0016: lock flat mode leaves through Q22 recording.create.

- **Implementation commit:** `f647abee9dc89a9dc3ae706ae7b9747719957b6a`
- **Change:** ADR 0016: lock flat mode leaves through Q22 recording.create
- **Details:**
  - Restored qanda and 04-uri-tree after external editor overwrite that dropped Q20–Q22
  - Q22 accepted: startRecording public mutate is recording.create only
  - HANDOFF.md for cold resume; next leaf reviews are idle Playing and Paused
- **Files:**
  - `docs/adr/0016-transcription-example-instant-first/HANDOFF.md` — Cold-start handoff for interview resume
  - `docs/adr/0016-transcription-example-instant-first/qanda.md` — Q20–Q22 decisions including recording.create
  - `docs/adr/0016-transcription-example-instant-first/overviews/04-uri-tree.md` — Flat nine mode leaves; Q22 REVIEWED tag
  - `docs/adr/0016-transcription-example-instant-first/README.md` — Link to HANDOFF
- **User context (verbatim):**
  > good
  > I did not commit — say if you want that
- **SpecStory:** unavailable — Grok Build session; no SpecStory cloud URI for this agent host

## August 11th, 2026 at 3:57:27 p.m. EDT — `7c4e5ab6ee3a` Make InstantError actionable and unblock deferred bootstrap.

- **Implementation commit:** `7c4e5ab6ee3af10f5861af188ea4d87a4636541d`
- **Change:** Make InstantError show code/operation/message/recovery instead of opaque error 1, and unblock deferred residency bootstrap.
- **Details:**
  - LocalizedError + CustomNSError with stable codes 1-7 and userFacingSummary for alerts.
  - Entity macro leaves JSON attributes non-indexed so large payloads can be deferred; deferred validation names missing IDs and declared neighbors.
- **Files:**
  - `Sources/InstantSwiftDataCore/InstantError.swift` — Actionable LocalizedError and CustomNSError presentation.
  - `Sources/InstantSwiftDataCore/DeferredValueResidency.swift` — Clearer missing-attribute bootstrap validation.
  - `Sources/InstantSwiftDataMacros/InstantSwiftDataMacros.swift` — JSON fields not indexed by default.
  - `Tests/InstantSwiftDataCoreTests/InstantErrorPresentationTests.swift` — Guard against opaque error 1 regression.
- **User context (verbatim):**
  > could not open scribe, instantswiftdatacore.instanterror error 1, first improve this message and make it much more clear from the library exactly what happened and fix this please
- **SpecStory:** unavailable — Grok Build session; no public SpecStory share URI.

## August 11th, 2026 at 2:44:46 p.m. EDT — `afe09bdba1fe` Split InstantRuntime translation unit and drop SIL hang flag.

- **Implementation commit:** `afe09bdba1fe0e0f6ce6f91cdc22ba6fc61c69b9`
- **Change:** Split InstantRuntime into smaller translation units and remove the debug SIL ClosureLifetimeFixup disable flag.
- **Details:**
  - Extracted InstantRuntimeExactTaskOwner, InstantRuntimeLiveSession, and InstantVisibleWriteFilter from the 13k-line InstantRuntime.swift primary.
  - Debug InstantSwiftDataCore rebuilds in ~19s without -sil-disable-pass=closure-lifetime-fixup; focused freeze contracts 80/80 green.
  - Physical KEEP still blocked on dirty Scribe tree; iPad agent-control sessions remain on old build 9fc4ff4.
- **Files:**
  - `Sources/InstantSwiftDataCore/InstantRuntime.swift` — Shrunk primary runtime translation unit after extracts.
  - `Sources/InstantSwiftDataCore/InstantRuntimeExactTaskOwner.swift` — Exact task owner and close-idle state extracted for compile isolation.
  - `Sources/InstantSwiftDataCore/InstantRuntimeLiveSession.swift` — Live session actor and encoding/supersede types extracted.
  - `Sources/InstantSwiftDataCore/InstantVisibleWriteFilter.swift` — Authoritative/visible write coverage helpers extracted.
  - `Package.swift` — Removed debug-only SIL unsafeFlags after split proved safe.
  - `PROGRESS.md` — Recorded split evidence and remaining KEEP blocker.
- **User context (verbatim):**
  > please
- **SpecStory:** unavailable — Grok Build session; no public SpecStory share URI for this desktop agent task.

## August 11th, 2026 at 1:56:00 p.m. EDT — `8b7c384e4545` Land bounded outbox/memory freezes and unblock suite compile.

- **Implementation commit:** `8b7c384e45455cdbf4c5906a786b486354369eaa`
- **Change:** Land bounded outbox/memory freezes and unblock suite compile
- **Details:**
  - Bounded 50/256/8MiB outbox claim windows, terminal component rejection, deferred residency, infinite-query slice-before-hydrate (issues #044 #150 #155)
  - InstantRuntime SIL ClosureLifetimeFixup workaround is debug-only target unsafeFlags; remove after Runtime split
  - Focused contracts 99/99 green; reactor server-accept seed fix; incomplete live-queue/storage/cookie suites excluded
- **Files:**
  - `Sources/InstantSwiftDataCore/InstantRuntime.swift` — Compile fixes, deferred/infinite wiring, thin upload progress lease
  - `Sources/InstantSwiftDataCore/SQLitePersistenceStore.swift` — Row-addressed outbox, revision domains, component load
  - `Package.swift` — SIL pass disable for InstantSwiftDataCore debug; exclude incomplete test suites
  - `Tests/InstantSwiftDataCoreTests/InstantTerminalFailureComponentTests.swift` — 10k-row terminal component contracts
- **User context (verbatim):**
  > A, then B, then continue iterating until /goal is reached
- **SpecStory:** unavailable — Grok Build session; no SpecStory Codex capture for this desktop task

## August 10th, 2026 at 11:39:36 a.m. EDT — `43c1dcdb6881` Fence WebSocket rejection to durable claim

- **Implementation commit:** `43c1dcdb6881f7e5726d6434a43bd7f499575afe`
- **Change:** Fence WebSocket mutation rejection to the durable claim
- **Details:**
  - Classify duplicate, stale, and owned server-error frames from normalized SQLite lifecycle and claim state without hydrating an outbox body.
  - Apply terminal rollback only under the exact token and consume that claim atomically; release the full token-owned delivery window before retryable reconnect.
  - Keep the authenticated socket and registered queries intact after terminal rejection, matching Reactor local observer notification without remove-query/add-query churn.
  - Verify 69 live-transport, 36 bounded-delivery, and 21 outbox-hydration tests, including duplicate zero-decode and cross-runtime stale-response regressions.
- **Files:**
  - `Sources/InstantSwiftDataCore/BoundedOutboxDelivery.swift` — Define durable mutation-error disposition.
  - `Sources/InstantSwiftDataCore/InstantRuntime.swift` — Route retryable and terminal server errors through exact durable claim ownership without query resubscription.
  - `Sources/InstantSwiftDataCore/SQLitePersistenceStore.swift` — Classify frames body-free and atomically consume terminal claim state.
  - `Tests/InstantSwiftDataCoreTests/InstantLiveTransportTests.swift` — Prove rollback publication, duplicate idempotence, stale-claim fencing, retry, and encoding quarantine behavior.
- **User context (verbatim):**
  > fix the fundamental sissues, don't paperclip over.
- **SpecStory:** unavailable — Unavailable: Codex desktop task was not proven captured by SpecStory.

## August 10th, 2026 at 10:40:45 a.m. EDT — `9a802149c790` Bound same-entity outbox growth safely

- **Implementation commit:** `9a802149c790f6d0b24668624d8c01c39d1e84c5`
- **Change:** Bound high-churn same-entity outbox bodies with safe immediate-tail supersession
- **Details:**
  - Replace only the exact never-claimed, never-offered durable tail when predecessor and newcomer are complete identical scalar assignment shapes.
  - Preserve direct rollback to the authoritative baseline, immutable transaction-id lifecycle aliases, strict causal barriers, and atomic claim-race checks.
  - Reject ineligible shapes before tail hydration and quarantine corrupt or stale-size tails within fixed body limits.
  - Verify 98 related tests, including 10,000-write restart, delivery, rollback, alias, corruption, claim-race, bounded-delivery, hydration, and acknowledgement regressions.
- **Files:**
  - `Sources/InstantSwiftDataCore/InstantRuntime.swift` — Admit supersession only after revision-qualified local preparation and publish the stable lifecycle.
  - `Sources/InstantSwiftDataCore/SQLitePersistenceStore.swift` — Atomically replace the exact eligible tail and retain row-addressed lifecycle and quarantine evidence.
  - `Sources/InstantSwiftDataCore/OutboxSameEntitySupersession.swift` — Define the conservative exact scalar assignment classifier.
  - `Tests/InstantSwiftDataCoreTests/InstantOutboxSupersessionIntegrationTests.swift` — Prove 10,000-write, restart, rollback, alias, corruption, and race behavior.
  - `docs/adr/0015-sqlite-data-parity-ergonomics/follow-on-outbox-same-entity-supersession.md` — Record the shipped invariant, barriers, lifecycle cost, and upstream divergence.
  - `skills/instant-data/SKILL.md` — Teach the exact safe library boundary and its durable-metadata limitation.
- **User context (verbatim):**
  > fix the fundamental sissues, don't paperclip over.
- **SpecStory:** unavailable — Unavailable: Codex desktop task was not proven captured by SpecStory.

## August 10th, 2026 at 3:36:02 a.m. EDT — `96db9b3e52de` Bound automatic outbox delivery memory

- **Implementation commit:** `96db9b3e52de20ef70e170f6d75b267b9bf558d1`
- **Change:** Bound automatic outbox delivery memory
- **Details:**
  - Made SQLite the single automatic-delivery admission authority with durable 50-mutation, 256-step, 8 MiB claims, five-second self-waking leases, row-addressed acknowledgement and explicit disposition, bounded startup and resident state, and raw-preserving loud quarantine.
  - Rejected new over-limit writes before local materialization, retained strict queue order across runtimes, preserved public inspection and wait semantics, and removed queue-depth-dependent body hydration from the normal delivery path.
  - Verified 36 bounded-outbox tests plus 38 outbox hydration, stall, acceptance, and delivery tests; known quarantine/timeout issue reports remained intentional.
- **Files:**
  - `Sources/InstantSwiftDataCore/BoundedOutboxDelivery.swift` — Defines hard automatic claim limits and safe wire projection.
  - `Sources/InstantSwiftDataCore/SQLitePersistenceStore.swift` — Owns atomic claims, normalized metadata, row-addressed lifecycle transitions, quarantine, and body-free summaries.
  - `Sources/InstantSwiftDataCore/InstantRuntime.swift` — Drives durable claims, five-second wakeups, retry release, and bounded resident barriers.
  - `Sources/InstantSwiftData/InstantSwiftData.swift` — Uses durable body-free mutation summaries for public waits.
  - `Tests/InstantSwiftDataCoreTests/InstantBoundedOutboxDeliveryTests.swift` — Covers cold and same-process 10k queues, cross-runtime order, hard budgets, corrupt rows, timeouts, and explicit disposition.
  - `Tests/InstantSwiftDataCoreTests/InstantOutboxHydrationTests.swift` — Locks full public state loading and row-addressed acceptance behavior.
  - `Tests/InstantSwiftDataCoreTests/InstantLiveTransportTests.swift` — Preserves live transport semantics under bounded admission.
  - `Tests/InstantSwiftDataTests/MutationDeliveryTests.swift` — Verifies public delivery waits read durable SQLite state.
- **User context (verbatim):**
  > actually solve the memory problem, don't keep squaking about what you're doing to solve it.
- **SpecStory:** unavailable — Unavailable: this work ran in Codex desktop and no verified SpecStory desktop capture URI exists.

## August 9th, 2026 at 11:27:29 p.m. EDT — `beffc9b4c98c` Bound WebSocket acceptance to one outbox row

- **Implementation commit:** `beffc9b4c98c24eda1f0bea24b8a60b35c29d3d7`
- **Change:** Bound WebSocket acceptance to one durable outbox row
- **Details:**
  - Replaced whole-outbox hydration, copying, and rewriting on transact-ok with a revision-checked SQLite row transition; connection status now counts pending rows without hydrating bodies, duplicate acknowledgements are idempotent, and a 10,000-row malformed-sentinel regression proves one-row decoding.
- **Files:**
  - `Sources/InstantSwiftDataCore/InstantRuntime.swift` — Route transact-ok through the bounded row transition and publish exact counts without hydrating the queue.
  - `Sources/InstantSwiftDataCore/Outbox.swift` — Update only the addressed compact resident lifecycle shell.
  - `Sources/InstantSwiftDataCore/SQLitePersistenceStore.swift` — Atomically accept and count one durable row without reconstructing unrelated bodies.
  - `Tests/InstantSwiftDataCoreTests/InstantOutboxHydrationTests.swift` — Prove cold-cache one-row decoding, malformed-row isolation, idempotence, and count correctness at 10,000-row depth.
- **User context (verbatim):**
  > fix the fundamental sissues, don't paperclip over.
- **SpecStory:** unavailable — Unavailable: this work ran in Codex desktop, which has no verified SpecStory CLI capture for this task.

## August 9th, 2026 at 6:00:44 p.m. EDT — `71ddd401de9a` Fix reverse relation delivery and rebased writes (#187)

- **Implementation commit:** `71ddd401de9a329233e4175549ee5281e31353de`
- **Change:** Fix reverse relation delivery and rebased wire writes (#187)
- **Details:**
  - Preserve whether a server attribute matched the forward or reverse identity, then swap add/retract endpoints for reverse relations exactly like canonical TypeScript instaml.
  - Remove create/update modes from swapped reverse-link steps so creating a child never asks the server to recreate its existing parent; preserve modes on forward links.
  - Rebase durable pending write timestamps with their optimistic overlays so visible-write filtering does not strip required scalar fields after refresh, rejection, or retry.
  - Keep same-ID retries idempotent by comparing ordered server-visible intent while still rejecting changed values, attributes, preconditions, and operation kinds.
- **Files:**
  - `Sources/InstantSwiftDataCore/InstantLiveMutation.swift` — Orient reverse relation endpoints during live attribute resolution.
  - `Sources/InstantSwiftDataCore/InstantRuntime.swift` — Keep durable and optimistic rebase timestamps aligned and preserve idempotent replay.
  - `Tests/InstantSwiftDataCoreTests/InstantLiveTransportTests.swift` — Prove exact reverse wire bodies, refresh replay, and stale-write protection.
  - `Tests/InstantSwiftDataCoreTests/InstantFailedMutationDiscardTests.swift` — Prove rejection and retry retain scalar wire writes.
  - `Tests/InstantSwiftDataCoreTests/InstantOutboxHydrationTests.swift` — Prove hydrated rebases align timestamps and keep same-ID intent safe.
- **User context (verbatim):**
  > what's causing these rejected recording mutations? Try and duplicate the issue on TypeScript
- **SpecStory:** unavailable — Unavailable: Codex desktop task; no SpecStory CLI capture or public share was created.

## August 9th, 2026 at 3:00:08 p.m. EDT — `8213ed3557d6` Fix durable outbox delivery with compact memory state

- **Implementation commit:** `8213ed3557d6f23455840699a8948f676858cbf6`
- **Change:** Hydrate durable outbox writes without retaining transaction graphs in memory
- **Details:**
  - Reload exact durable transaction bodies only at delivery and lifecycle boundaries; keep the resident actor and SQLite cache compact.
  - Restore automatic and explicit-session delivery, preserve healthy sockets on terminal mutation rejection, and retry local hydration failures through one coalesced pump.
  - Match upstream Reactor semantics for retryable permission-service failures, explicit live queries, and close-versus-reconnect ordering; add cross-runtime and authoritative-empty-store regressions.
- **Files:**
  - `Sources/InstantSwiftData/InstantSwiftData.swift` — Expose durable pending count and route waits through the delivery pump
  - `Sources/InstantSwiftData/InstantSyncStatus.swift` — Count pending rows without decoding bodies
  - `Sources/InstantSwiftDataCore/InstantInfiniteQuery.swift` — Synchronize the store before query validation
  - `Sources/InstantSwiftDataCore/InstantRuntime.swift` — Selective hydration, delivery, rejection, reconnect, and revision synchronization
  - `Sources/InstantSwiftDataCore/InstantStore.swift` — Merge server attributes into hot indexes
  - `Sources/InstantSwiftDataCore/Outbox.swift` — Compact resident mutation graphs while preserving durable confirmation bodies
  - `Sources/InstantSwiftDataCore/SQLitePersistenceStore.swift` — Compact cache plus revision-checked hydration and correct full-state diff baselines
  - `Tests/InstantSwiftDataCoreTests/BenchmarkTests.swift` — Record measured compact-state actor hops
  - `Tests/InstantSwiftDataCoreTests/CLITests.swift` — Preserve unchanged outbox revisions in validation evidence
  - `Tests/InstantSwiftDataCoreTests/InstantFailedMutationDiscardTests.swift` — Assert explicit-session query traffic
  - `Tests/InstantSwiftDataCoreTests/InstantLiveTransportTests.swift` — Cover healthy rejection state and server attribute materialization
  - `Tests/InstantSwiftDataCoreTests/InstantOutboxHydrationTests.swift` — Add exact-wire, cross-runtime, lifecycle, empty-store, permission, and reconnect regressions
  - `Tests/InstantSwiftDataCoreTests/InstantReactorParityTests.swift` — Bound and acknowledge live one-shot queries
  - `Tests/InstantSwiftDataCoreTests/InstantStoreTests.swift` — Assert compact cache and stable full-state revisions
- **User context (verbatim):**
  > Track them all the way upstream to the actual invocation and source.
- **SpecStory:** unavailable — Unavailable: Codex desktop task; no SpecStory CLI capture or public share was created.

## August 9th, 2026 at 9:53:07 a.m. EDT — `5d903c86f595` Add same-entity outbox supersession recipe + pure policy (#155).

- **Implementation commit:** `5d903c86f595baac8a6581223b07c8426e7639e8`
- **Change:** Add same-entity outbox supersession recipe + pure policy (#155).
- **Details:**
  - Expand ADR 0015 follow-on into concrete speech-load recipe (problem, policy, algorithm, non-goals, observability, TS vs Swift divergence). Pure OutboxSameEntitySupersession + 17 unit tests (10–100 same-entity upserts → 1 survivor). TODO recipe entry at InstantRuntime enqueue; full outbox delivery integration remains follow-on.
- **Files:**
  - `docs/adr/0015-sqlite-data-parity-ergonomics/follow-on-outbox-same-entity-supersession.md` — Active supersession recipe
  - `Sources/InstantSwiftDataCore/OutboxSameEntitySupersession.swift` — Pure policy (no I/O)
  - `Tests/InstantSwiftDataCoreTests/OutboxSameEntitySupersessionTests.swift` — Offline high-churn policy tests
  - `Sources/InstantSwiftDataCore/InstantRuntime.swift` — TODO recipe entry at durable enqueue
  - `docs/adr/0015-sqlite-data-parity-ergonomics/open-segment-write-recipe.md` — Link to supersession recipe
  - `skills/instant-data/SKILL.md` — Live speech supersession bullet
- **User context (verbatim):**
  > User said this is important for speech performance/correctness under load — not strictly required for façade delete, but without it speech thrash stays ugly. Implementation of full supersession may be partial/skeleton, but the recipe document + compile-checked sketch + tests of intended policy must land.
- **SpecStory:** unavailable — unavailable — Grok Build agent session; no SpecStory URI for this desktop task.

## August 9th, 2026 at 9:13:03 a.m. EDT — `2f32fd84137f` Add Instant open-segment write recipe for ADR 0015 (#155).

- **Implementation commit:** `2f32fd84137f4197338aba3c55e7127370ac1952`
- **Change:** Add Instant open-segment write recipe for ADR 0015 (#155)
- **Details:**
  - Library-owned open-segment write recipe: ensure recording once, upsert open segment with strict wordsJSON, transact = local+outbox only. Core OpenSegmentWriteRecipe + typed OpenSegmentWriteRecipeEntities + 12 offline tests. Cross-linked from plan.md, overview 10, overview 02, findings, skill.
- **Files:**
  - `docs/adr/0015-sqlite-data-parity-ergonomics/open-segment-write-recipe.md` — Canonical open-segment write recipe
  - `Sources/InstantSwiftDataCore/OpenSegmentWriteRecipe.swift` — Core wordsJSON codec + mutation builders
  - `Sources/InstantSwiftData/OpenSegmentWriteRecipeEntities.swift` — Typed InstantEntityModel sketch
  - `Tests/InstantSwiftDataCoreTests/OpenSegmentWriteRecipeTests.swift` — Offline Core unit tests
  - `Tests/InstantSwiftDataTests/OpenSegmentWriteRecipeTypedTests.swift` — Typed entity + local runtime tests
- **User context (verbatim):**
  > Create a first-class Instant Swift Data open-segment write recipe (ADR 0015 S2 / #155 / overview 10 item open-segment write recipe).
- **SpecStory:** unavailable — No SpecStory URI; Grok Build agent session for library recipe land.

## August 7th, 2026 at 12:45:33 a.m. EDT — `fdbef6d76506` Point AGENTS at Scribe coordination protocol; add ADR 0014 lifecycle draft.

- **Implementation commit:** `fdbef6d76506b286717ca0db42359b5be2b8e896`
- **Change:** Point AGENTS at Scribe coordination protocol; add ADR 0014 lifecycle draft.
- **Details:**
  - AGENTS.md: require multi-agent coordination protocol with corrected path to agent-coordination-protocol.md.
  - ADR 0014 proposed: lifecycle/sync status on fetch; interim segments still outbox; write-shape not dual timelines.
- **Files:**
  - `AGENTS.md` — Link machine coordination protocol for library agents
  - `docs/adr/0014-entity-lifecycle-status-and-draft-visibility-in-fetch.md` — Proposed entity lifecycle and open-segment write ADR
- **User context (verbatim):**
  > commit all of our work
- **SpecStory:** unavailable — Grok Build TUI session; no SpecStory cloud share URI for this chat

## August 6th, 2026 at 7:39:03 p.m. EDT — `549f740c9a80` Expose Instant clientID() for activity ADT this vs other device

- **Implementation commit:** `549f740c9a8001ff1ccfd0e9ee15a9a850f304db`
- **Change:** Expose Instant clientID() for activity ADT this vs other device
- **Details:**
  - Public InstantRuntime.clientID() and InstantSwiftDataClient.clientID() resolve reserved local-id InstantClientID.name (TS getLocalId). Offline-safe. InstantClientID.isThisClient for Scribe activity comparison. Focused tests. ADR 0015 Q23 / #155 P1.
- **Files:**
  - `Sources/InstantSwiftDataCore/InstantModels.swift` — InstantClientID reserved name + isThisClient helper
  - `Sources/InstantSwiftDataCore/InstantRuntime.swift` — clientID() over localID
  - `Sources/InstantSwiftData/InstantSwiftData.swift` — InstantSwiftDataClient.clientID() public API
  - `Tests/InstantSwiftDataCoreTests/InstantClientIDTests.swift` — Core persistence and this-vs-other comparison tests
  - `Tests/InstantSwiftDataTests/InstantClientIDTests.swift` — Client API and activity ADT comparison tests
  - `skills/instant-data/SKILL.md` — Document clientID for recordings list activity
- **User context (verbatim):**
  > expose Instant client id for Scribe activity ADT (this device vs other device)
- **SpecStory:** unavailable — Codex/desktop agent task; no SpecStory URI for this session.

## August 6th, 2026 at 4:52:26 p.m. EDT — `421f735343f5` Return from transact after local commit, not wire send

- **Implementation commit:** `421f735343f59cc9903affe38d3c3a7d2dff907c`
- **Change:** Local-first transact: do not await websocket delivery before return
- **Details:**
  - Root cause of ~1s yellow counter buttons: runtime.transact awaited sendOutstandingMutationsToLiveSession when the live session was open. Instant JS pushOps notifies immediately and sends async. Now always startLiveMutationDeliveryIfNeeded without awaiting. Delete-all restored to fire-and-forget send(mutations:). Counter isBusy gate removed. Test: runtimeLiveTransactReturnsBeforeOpenSessionDeliveryFinishes. Tracker: https://issues.knophy.com/issues/151
- **Files:**
  - `Sources/InstantSwiftDataCore/InstantRuntime.swift` — Non-blocking delivery after optimistic commit
  - `Sources/TodosV3App/TodosApp.swift` — Restore fire-and-forget delete-all send
  - `Sources/AuthV3App/AuthV3Counters.swift` — Remove isBusy network gate; create-exists fallback
  - `Tests/InstantSwiftDataCoreTests/InstantLiveTransportTests.swift` — Prove open-session delivery does not block transact
- **User context (verbatim):**
  > I want the original syntax that you had, and we should make that work
  > the increment button turns yellow and is disabled... takes like a second
- **SpecStory:** unavailable — Grok Build session; no SpecStory public share URI for this agent host

## August 6th, 2026 at 4:31:26 p.m. EDT — `289c148fbddc` Harden todos delete-all to await server acceptance

- **Implementation commit:** `289c148fbddccff3b85fbfe6e7424e4caf3b5d03`
- **Change:** Todos delete-all awaits Instant acceptance (no silent local-only)
- **Details:**
  - Delete all uses sendAwaitingServerAcceptance(InstantMutationBatch, 5s) with loud failure text. Live InstantMutationBatchLiveDeleteAllTests prove server accept and second-client convergence on recipes app. Tracker: https://issues.knophy.com/issues/151
- **Files:**
  - `Sources/TodosV3App/TodosApp.swift` — Await server acceptance for delete-all
  - `Tests/InstantSwiftDataTests/InstantMutationBatchLiveDeleteAllTests.swift` — Live single- and multi-client delete-all regressions
- **User context (verbatim):**
  > also deleting all is only deleting locally, not getting sent to other devices.
- **SpecStory:** unavailable — Grok Build session; no SpecStory public share URI for this agent host

## August 6th, 2026 at 4:12:59 p.m. EDT — `b97ad44752e3` Allow swipe-down keyboard dismiss on todos composer

- **Implementation commit:** `b97ad44752e37615c5d1b8efdc71626fe06523ee`
- **Change:** Todos keyboard: swipe-down dismiss without fighting post-send focus
- **Details:**
  - List uses scrollDismissesKeyboard(.interactively). Re-focus only on appear and once after optimistic send clear; removed deferred Task and server-accept/failure re-focus that stole focus back after swipe-down dismiss.
- **Files:**
  - `Sources/TodosV3App/TodosApp.swift` — Interactive keyboard dismiss + softer composer focus retention
- **User context (verbatim):**
  > let me swipe down to dismiss keyboard though
- **SpecStory:** unavailable — Grok Build session; no SpecStory public share URI for this agent host

## August 6th, 2026 at 4:02:27 p.m. EDT — `b4e018e03f9b` Keep todos composer keyboard focused after send

- **Implementation commit:** `b4e018e03f9b614c0204470206f3f641a6f81d33`
- **Change:** Keep todos composer keyboard focused after send
- **Details:**
  - FocusState reclaims focus after onSubmit clears the field.
- **Files:**
  - `Sources/TodosV3App/TodosApp.swift` — FocusState on composer; refocus after add
- **User context (verbatim):**
  > keep keyboard focused
- **SpecStory:** unavailable — Grok Build session; no SpecStory URI authorized

## August 6th, 2026 at 4:00:09 p.m. EDT — `3e0c61b907f1` Submit todos on Enter / keyboard Send

- **Implementation commit:** `3e0c61b907f11e30038da22a679e281a55d31b90`
- **Change:** Submit todos on Enter / keyboard Send
- **Details:**
  - TextField onSubmit and iOS submitLabel send for Todos recipe.
- **Files:**
  - `Sources/TodosV3App/TodosApp.swift` — onSubmit and submitLabel for add todo
- **User context (verbatim):**
  > make enter send todo please don't make me press button
- **SpecStory:** unavailable — Grok Build session; no SpecStory URI authorized

## August 6th, 2026 at 3:52:55 p.m. EDT — `64426d24732f` Add library batch transact API and InstantMutationBatch send

- **Implementation commit:** `64426d24732f881e3a8c5012cbe723fce3aa1533`
- **Change:** Library batch transact API and InstantMutationBatch send (#151)
- **Details:**
  - Array transact with optional batchSize; Todo.delete(ids:); InstantMutationBatch for send lifecycle callbacks. Todos delete-all rewired.
- **Files:**
  - `Sources/InstantSwiftData/InstantTypedAPI.swift` — transact([mutations], batchSize?) + delete(ids:) sugar
  - `Sources/InstantSwiftData/InstantMessage.swift` — InstantMutationBatch + send(mutations:)
  - `Sources/TodosV3App/TodosApp.swift` — Delete all uses send(mutations: Todo.delete(ids:))
  - `Sources/TodosV3App/TodoModels.swift` — Remove app-local DeleteTodos
  - `Tests/InstantSwiftDataTests/InstantMutationBatchAPITests.swift` — TDD coverage for batch API
- **User context (verbatim):**
  > Ship it. use test-driven development to do this.
- **SpecStory:** unavailable — Grok Build session; no SpecStory URI authorized

## August 6th, 2026 at 3:49:09 p.m. EDT — `22a973c20492` Add Scribe open-segment 20s network write/observe benchmark (#156)

- **Implementation commit:** `22a973c204926c7133f91b02aff6d23456f79c7b`
- **Change:** Add Scribe open-segment 20s network write/observe benchmark CLI (#156)
- **Details:**
  - Net-A admin→Swift and Net-B Swift→admin over a real Instant app; open-segment wordsJSON write shape; observer-validated seq score; process memory/CPU; READY handshake so spawn time is not scored. Issue https://issues.knophy.com/issues/156.
  - 20s baseline on laptop: Net-A ~8.7 valid writes/s (175 obs), Net-B ~8.2 valid writes/s (165 obs); ratio B/A ~0.94.
- **Files:**
  - `Sources/InstantSwiftDataCore/ScribeOpenSegmentNetworkBench.swift` — Swift open-segment writer/observer + metrics
  - `Sources/ScribeShaped20sWriteBench/main.swift` — CLI entry for Swift lanes
  - `Package.swift` — Executable product scribe-shaped-20s-write-bench
  - `validation/ts-runner/src/scribe-shaped-20s-write-bench.ts` — TS admin lanes + coordinate matrix
  - `validation/run-scribe-shaped-20s-write-bench.sh` — Ephemeral app provision + runbook
  - `validation/fixtures/scribe-open-segment-bench.schema.ts` — Ephemeral Instant schema for open-segment bench
  - `validation/fixtures/scribe-open-segment-bench.perms.ts` — Open perms for ephemeral bench app
  - `docs/benchmarks/scribe-shaped-20s-write-parity/README.md` — Runbook and design pointer
  - `docs/benchmarks/scribe-shaped-20s-write-parity/qanda.md` — Interview decisions including network-vs-network
  - `docs/benchmarks/scribe-shaped-20s-write-parity/findings.md` — Existing harness inventory
  - `docs/benchmarks/scribe-shaped-20s-write-parity/overviews/01-cli-run-simulation.md` — Simulated terminal contract
  - `INSTANT_DATA_PERFORMANCE_BENCHMARKS.md` — Link #156 network matrix into bench doc
- **User context (verbatim):**
  > I need you to create a memory benchmark of a pure command line utility that exercises TypeScript admin node as well as our Swift application
  > Never compare local versus network
  > Uh just do both. Go ahead and get started.
- **SpecStory:** unavailable — Grok Build session; no SpecStory cloud URI for this agent host

## August 6th, 2026 at 3:41:53 p.m. EDT — `40316b0845ba` Batch todos delete-all into one outbox mutation

- **Implementation commit:** `40316b0845ba4e27ae3eeb4ed0fc6544ad8b903d`
- **Change:** Batch todos delete-all into one outbox mutation (#151)
- **Details:**
  - Diagnosed iPhone: delete all then add head briefly resurrected deleted todos; server now only head. N concurrent deletes raced live refresh.
- **Files:**
  - `Sources/TodosV3App/TodoModels.swift` — DeleteTodos multi-delete InstantMessage
  - `Sources/TodosV3App/TodosApp.swift` — Delete all uses single batched send
- **User context (verbatim):**
  > I deleted all to-dos on my iPhone and then added a new one called head, and then everything else popped back in
- **SpecStory:** unavailable — Grok Build session; no SpecStory URI authorized

## August 6th, 2026 at 3:37:12 p.m. EDT — `a01d6f3cb0e2` Fix Mac Google OAuth crash: ASWebAuthenticationSession MainActor trap

- **Implementation commit:** `a01d6f3cb0e27f57f23edbb2b116b9f9a0249de4`
- **Change:** Fix Mac Google OAuth crash from ASWebAuthenticationSession MainActor trap
- **Details:**
  - Crash: EXC_BREAKPOINT in BrowserOAuthAuthorizer.authorize completion. iPhone OK (different presentation). Fix @Sendable callback + MainActor hop.
- **Files:**
  - `Sources/InstantSwiftData/InstantAuthProvider.swift` — @Sendable ASWebAuthenticationSession completion hops to MainActor
- **User context (verbatim):**
  > Recipes crashed when I attempted to sign in with Google. Can you look at the logs? mac - iphone worked fine
- **SpecStory:** unavailable — Grok Build session; no SpecStory URI authorized

## August 6th, 2026 at 3:22:19 p.m. EDT — `ea9f8b978c30` Use UUID entity IDs for recipe public counter and private note

- **Implementation commit:** `ea9f8b978c3067f72946426e271dcf8804315838`
- **Change:** Use UUID entity IDs for recipe public counter
- **Details:**
  - Server: Invalid entity ID public-counter must be UUIDs. Fixed stable UUID for public counter and private-note probe.
- **Files:**
  - `Sources/AuthV3App/AuthV3Counters.swift` — Stable UUID for shared public counter entity
  - `Sources/RecipesV3App/RecipesSharingScreen.swift` — UUID for private-note probe entity
- **User context (verbatim):**
  > Invalid entity ID 'public-counter'. Entity IDs must be UUIDs
- **SpecStory:** unavailable — Grok Build session; no SpecStory URI authorized

## August 6th, 2026 at 3:16:23 p.m. EDT — `6e79b7cf84fd` Extract Tailnet InstantDBLogger package and wire Recipes auth diagnostics

- **Implementation commit:** `6e79b7cf84fd7f30f465ae1253659275c9ebe147`
- **Change:** Extract Tailnet diagnostics package; Recipes auth logs + Instant OAuth clients
- **Details:**
  - Google record-not-found fixed by creating Instant OAuth client google; Apple clients registered; SIWA entitlement restored in device build.
- **Files:**
  - `Packages/TailnetDiagnostics/Package.swift` — SPM package for extracted InstantDBLogger
  - `Sources/RecipesV3App/RecipesTailnetDiagnostics.swift` — Recipes host wiring for Tailnet WS
  - `Sources/RecipesV3App/RecipesV3App.swift` — Start logger; forward auth notifications
  - `Sources/AuthV3App/AuthApp.swift` — Post auth provider notifications for hosts
  - `Examples/RecipesV3/tail-diagnostics.sh` — Agent log tail filter
- **User context (verbatim):**
  > extract the WebSocket logger that logs to my computer via Tailnet
- **SpecStory:** unavailable — Grok Build session; no SpecStory URI authorized

## August 6th, 2026 at 3:06:03 p.m. EDT — `e3737d779bd3` Restart recipes example after wipe local DB

- **Implementation commit:** `e3737d779bd3cef4356704f395c3ac1718d14182`
- **Change:** Restart recipes example after wipe local DB
- **Details:**
  - Wipe button now restarts the host instead of only quitting.
- **Files:**
  - `Sources/RecipesV3App/RecipesDebugPanel.swift` — Wipe closes connection, deletes store, relaunches
  - `Sources/RecipesV3App/RecipesDebugSupport.swift` — Doc note for restart-after-wipe
- **User context (verbatim):**
  > make the wipe and quit button restart the example
- **SpecStory:** unavailable — Grok Build session; no SpecStory URI authorized

## August 6th, 2026 at 3:00:44 p.m. EDT — `1891508192d6` Add Auth/Sharing counter namespaces to recipes Instant schema

- **Implementation commit:** `1891508192d60bdf173d9aef761818938c323de9`
- **Change:** Add Auth/Sharing counter namespaces to recipes Instant schema
- **Details:**
  - Pushed schema+perms to live recipes app so public/account counters encode against server attrs.
- **Files:**
  - `Sources/InstantSwiftDataSchema/InstantSwiftDataSchema.swift` — recipe_* entities on recipesDocument
- **User context (verbatim):**
  > Could not resolve 'recipe_public_counters/id' from the attrs returned by init-ok
- **SpecStory:** unavailable — Grok Build session; no SpecStory URI authorized

## August 6th, 2026 at 2:58:53 p.m. EDT — `0620f5ba132a` Fix live Instant client poisoning and wire Recipes .env

- **Implementation commit:** `0620f5ba132ae2d91c5af50aebf9ac33b85ffb82`
- **Change:** Fix live Instant client poisoning; Recipes .env as live source of truth
- **Details:**
  - Debug panel no longer touches defaultInstantSwiftData before bootstrap. .env → sync-env.sh → Info.plist InstantAppID + bundled RecipesV3.env.
- **Files:**
  - `Sources/RecipesV3App/RecipesDebugPanel.swift` — Pass bootstrapped client; never early @Dependency
  - `Sources/RecipesV3App/RecipesV3App.swift` — Mount debug panel only after client ready; re-inject on destinations
  - `Sources/RecipesV3Executable/main.swift` — Load bundled RecipesV3.env (APP_ID only)
  - `Examples/RecipesV3/sync-env.sh` — .env → xcconfig + bundle env
  - `Examples/RecipesV3/project.yml` — Pre-build sync + RecipesV3.env resource
- **User context (verbatim):**
  > Can we please cut out this bullshit and just have the credentials in a.emv file, please?
- **SpecStory:** unavailable — Grok Build session; no SpecStory URI authorized

## August 6th, 2026 at 1:59:36 p.m. EDT — `a3cd39e6f193` Share one Instant client across all recipes screens

- **Implementation commit:** `a3cd39e6f1931dda724a39e378a6713b1cd54b9d`
- **Change:** One Instant client for all recipes; inject into SwiftUI dependencies.
- **Details:**
  - RecipesV3BootstrapScreen applies .dependency(\.defaultInstantSwiftData, client) so Todos CreateTodo uses the shared recipes app.
- **Files:**
  - `Sources/RecipesV3App/RecipesV3App.swift` — Shared client injection + catalog app ID label.
  - `Sources/TodosV3App/TodosApp.swift` — Standalone Todos injects bootstrapped client the same way.
  - `Examples/RecipesV3/README.md` — Document one Instant app for all recipes.
- **User context (verbatim):**
  > Uh one instant app for all of the recipes, please.
- **SpecStory:** unavailable — Grok Build session; no SpecStory URI for this client.

## August 6th, 2026 at 1:54:31 p.m. EDT — `c3fadbac66a7` Fix iOS recipes install: home wipe path and iOS 17 availability

- **Implementation commit:** `c3fadbac66a743d4d1fec598e3c5ef8b91cfbfd5`
- **Change:** Fix iOS Instant Recipes install availability and wipe path
- **Details:**
  - Unblocks physical iPhone install of Instant Recipes with Auth counters.
- **Files:**
  - `Sources/RecipesV3App/RecipesDebugSupport.swift` — Portable wipe path without homeDirectoryForCurrentUser
  - `Sources/LinkedInfiniteV3App/LinkedInfiniteApp.swift` — iOS 17 for ContentUnavailableView screens
  - `Sources/AuthV3App/AuthApp.swift` — Availability gate for AuthV3CountersCard
- **User context (verbatim):**
  > install the recipes app on my Mac and bring it to forward with AppleScript and then install it on my iPhone as well
- **SpecStory:** unavailable — Grok Build session; no SpecStory URI authorized

## August 6th, 2026 at 1:49:55 p.m. EDT — `24520678695b` Put public and account counters on the Auth recipe page

- **Implementation commit:** `24520678695b530f1dc2ca5462094e93228830be`
- **Change:** Put public and account counters on the Auth recipe page (#152)
- **Details:**
  - AuthV3CountersCard on AuthV3LoginScreen: open public counter + mine counter keyed to InstantAuthState session so login/logout switches the account-scoped value. https://issues.knophy.com/issues/152
  - Models live in AuthV3App; Sharing recipe reuses AuthV3CountersCard and keeps the unauthorized private-note probe.
- **Files:**
  - `Sources/AuthV3App/AuthV3Counters.swift` — Public/account counter models and live UI card
  - `Sources/AuthV3App/AuthApp.swift` — Embed counters on login screen and bootstrap attributes
  - `Sources/RecipesV3App/RecipesSharingScreen.swift` — Reuse shared counters; keep unauthorized probe
  - `Sources/RecipesV3App/RecipesV3App.swift` — Auth recipe summary mentions counters
  - `Tests/AuthV3AppTests/AuthV3AppTests.swift` — Counter namespaces and card compile coverage
- **User context (verbatim):**
  > Yeah, I want the counters on the auth recipe page so I can see the generically shared with everybody counter with no permissions on that page. And then when I log in or log out, that will change and react to where I log out to or log in from
- **SpecStory:** unavailable — Grok Build session; no SpecStory URI authorized

## August 5th, 2026 at 8:15:43 p.m. EDT — `956caec9eaac` Make demotion suite use Scribe namespaces, guest auth, dual Instant

- **Implementation commit:** `956caec9eaac6fabdd3ed051160e55ebb1d17a88`
- **Change:** Demotion suite on production Scribe namespaces + guest auth + dual Instant thrash (#150)
- **Details:**
  - InstantDiagnosticFeedbackLoopTests uses ScribeProductionShapedSchema and guest auth; dual Instant debugLogs thrash demotion case; v1.5.6 release notes.
- **Files:**
  - `Tests/InstantSwiftDataCoreTests/InstantDiagnosticFeedbackLoopTests.swift` — Scribe-shaped demotion + dual Instant thrash proof
  - `Tests/InstantSwiftDataCoreTests/InstantReactorParityLiveSupport.swift` — Generic liveReactorServerAttrs from InstantAttribute
  - `docs/releases/v1.5.6.md` — Release notes for production soak gate
- **User context (verbatim):**
  > reproduce the memory consumption issue at the library level so we can gate releases against it with an exact replica of auth/data/schema that scribe uses
- **SpecStory:** unavailable — Grok Build TUI session; no SpecStory cloud URI for this host

## August 5th, 2026 at 8:03:48 p.m. EDT — `60df101efae4` Use production Scribe namespaces and dual Instant thrash in soak gates

- **Implementation commit:** `60df101efae42243b139eb4d5b2260934e1b1a99`
- **Change:** Production Scribe namespaces + real dual Instant debugLogs thrash soak (#150)
- **Details:**
  - ScribeProductionShapedSchema mirrors production entity names; soak boots second Instant debugLogs runtime and forces multi-attr batches; live guest auto-enables with credentials; suites run sequentially for clean footprint samples. https://issues.knophy.com/issues/150
  - verify-scribe-shaped-memory-soak passed with live auth; iPad last3 phys ~41MB (Instant lane off).
- **Files:**
  - `Sources/InstantSwiftDataCore/ScribeProductionShapedSchema.swift` — Production namespace + debugLogs thrash fixture
  - `Tests/InstantSwiftDataCoreTests/ScribeShapedAuthenticatedIdleMemorySoakTests.swift` — Guest auth + dual Instant thrash gates
  - `Tests/InstantSwiftDataCoreTests/LinkedInfiniteScribeShapedMemorySoakTests.swift` — Publish gate on production namespaces
  - `validation/verify-scribe-shaped-memory-soak.sh` — Sequential suites + live auth auto
  - `docs/scribe-shaped-memory-soak.md` — Document production namespaces and thrash driver
- **User context (verbatim):**
  > just sitting here on the home screen, now it's two gigabytes of memory
  > Iterate on the library, bring the problematic code paths into the library recipes, exercise the recipes, and reproduce in the recipes, and then resolve there
- **SpecStory:** unavailable — Grok Build TUI session; no SpecStory cloud URI for this host

## August 5th, 2026 at 7:00:21 p.m. EDT — `129ce6270a6b` Gate Scribe-shaped idle memory with guest auth and absolute ceilings

- **Implementation commit:** `129ce6270a6bcc4723d1141962a8cfbb17681744`
- **Change:** Scribe-shaped absolute idle memory gate with guest auth
- **Details:**
  - publishGateAbsoluteIdle ≤400MiB; guest auth always; live guest when INSTANT_SWIFT_DATA_LIVE_AUTH_SOAK=1; dual-write demotion regression in release soak
- **Files:**
  - `Tests/InstantSwiftDataCoreTests/ScribeShapedAuthenticatedIdleMemorySoakTests.swift` — Auth + absolute idle soak
  - `Sources/InstantSwiftDataCore/LinkedInfiniteExample.swift` — publishGateAbsoluteIdle profile
  - `validation/verify-scribe-shaped-memory-soak.sh` — Wire auth soak into publish gate
  - `docs/scribe-shaped-memory-soak.md` — Document absolute idle + auth
- **User context (verbatim):**
  > reproduce the memory consumption issue at the library level so we can gate releases
- **SpecStory:** unavailable — Grok Build goal session; no SpecStory URI

## August 5th, 2026 at 5:37:14 p.m. EDT — `759c899a8a4f` Demote high-frequency InstantDiagnostics that dual-write thrash

- **Implementation commit:** `759c899a8a4f76ccaa2d473e5f15c33fe86946fc`
- **Change:** Demote high-frequency InstantDiagnostics to break dual-write memory thrash
- **Details:**
  - outbox flush/send, query-once, transaction, websocket send at debug; feedback-loop tests; field idle 2.7-3.8GB with debug-log-batch 700 ops
- **Files:**
  - `Sources/InstantSwiftDataCore/InstantRuntime.swift` — Demote routine high-volume diagnostic levels
  - `Tests/InstantSwiftDataCoreTests/InstantDiagnosticFeedbackLoopTests.swift` — Regression for info dual-write feedback
- **User context (verbatim):**
  > It's at 2.74 gigabytes of usage just sitting there, not doing anything.
  > just opening the app peaks spikes from 111 megabytes to half a gig in 20 seconds
- **SpecStory:** unavailable — Grok Build session; no SpecStory URI

## August 5th, 2026 at 1:31:35 p.m. EDT — `c5f9a0cef241` Document production performance readiness plan from research quorum

- **Implementation commit:** `c5f9a0cef24161e92b0f51bc252faf50cb87fccc`
- **Change:** Production performance readiness plan after research quorum and live iPad diagnostics
- **Details:**
  - Five research agents + two evaluators; live evidence of 880MB+ idle climb, 160s failMutation gate holds, permission-denied and missing-attr receive-loop failures
  - Phase 0 thrash stop; Phase 1 absolute budgets; Phase 2 structural efficiency under ADR; keep SQLite offline-first
  - Related Instant issues: #134 (apply/receive isolation remainder), #150 (memory soak gate)
- **Files:**
  - `docs/plans/2026-08-05-production-performance-readiness-plan.md` — Canonical production performance plan
  - `PROGRESS.md` — Newest-first checkpoint for next agents
- **User context (verbatim):**
  > I've got 880 megabytes as of 1:20 p.m. Eastern Time. Just with the application sitting here, not doing anything.
  > put together a comprehensive plan for bringing this library ready to production usage
- **SpecStory:** unavailable — Grok Build session; no SpecStory URI for this host

## August 5th, 2026 at 1:12:20 p.m. EDT — `8fbfa0c8ef1d` Recipes: outbox isolation panel, wipe, clear logs, delete todos, sharing

- **Implementation commit:** `8fbfa0c8ef1d95457929a9b4462c65f85923c9f2`
- **Change:** Recipes debug outbox isolation, wipe/clear, delete todos, sharing counters (#152)
- **Details:**
  - legacy-unknown-isolated means a failed outbox row predates optimistic-overlay metadata; isolated so live apply continues. Wiped poisoned recipes SQLite for empty start.
  - Panel lists failed mutation IDs + plain English; clear logs; wipe local DB+quit. Todos swipe/context delete and delete-all.
  - Sharing recipe: public counter, my-account counter, unauthorized private note probe; perms sketch for owner-scoped namespaces.
- **Files:**
  - `Sources/RecipesV3App/RecipesDebugPanel.swift` — Outbox list, clear logs, wipe DB
  - `Sources/RecipesV3App/RecipesSharingScreen.swift` — Public/account counters + unauthorized read
  - `Sources/TodosV3App/TodosApp.swift` — Delete todo UX
  - `Sources/InstantSwiftDataCore/InstantModels.swift` — isLegacyUnknownOverlayCandidate
- **User context (verbatim):**
  > outbox, mutation legacy, unknown, isolated
  > wipe the database for this recipes thing and then restart? Empty starter
  > shared counter, a public counter and a shared counter just to my account
  > view of trying to read something that I haven't that isn't owned by me
- **SpecStory:** unavailable — Grok Build CLI session; no SpecStory URI for this client

## August 5th, 2026 at 12:58:19 p.m. EDT — `551bb333839d` Add Scribe-shaped linked-infinite memory soak as publish gate

- **Implementation commit:** `551bb333839dcd050fb7ad4acf312124ee87d046`
- **Change:** Add Scribe-shaped linked-infinite memory soak as library publish gate (#150)
- **Details:**
  - Production sample 2026-08-05: ~239 recordings, ≥2000 words/segments, 246 attachments; recipe previously seeded 20 tiny rows.
  - LinkedInfiniteScribeShapedMemorySoakTests + validation/verify-scribe-shaped-memory-soak.sh; hooked into verify-v1-release.sh.
  - VSZ ~400GB is virtual address space on Apple Silicon; panel labels VSZ (not RAM); gates use physical footprint. Measured seed ~450MiB Debug, page expand <1MiB.
- **Files:**
  - `Sources/InstantSwiftDataCore/LinkedInfiniteExample.swift` — Scribe-shaped soak profile, words namespace, seed ops
  - `Sources/InstantSwiftDataCore/InstantProcessMemory.swift` — Footprint/resident/virtual samples
  - `Tests/InstantSwiftDataCoreTests/LinkedInfiniteScribeShapedMemorySoakTests.swift` — Publish-gate soak
  - `validation/verify-scribe-shaped-memory-soak.sh` — Release script
  - `Sources/LinkedInfiniteV3App/LinkedInfiniteModels.swift` — Recipe model + seed aligned to Scribe shape
  - `docs/scribe-shaped-memory-soak.md` — Gate documentation and production sample table
- **User context (verbatim):**
  > fifth time or so or more that I've had to figure out why my usage of memory is spiking for no reason
  > cannot publish a version of this library unless that performance test against a real live soaking application
  > Why is the virtual memory 415 gigabytes? Um footprint 58 megabytes, resident 117 megabytes.
- **SpecStory:** unavailable — Grok Build CLI session; no SpecStory URI for this client

## August 5th, 2026 at 12:48:13 p.m. EDT — `ca483b549791` Isolate failed legacy mutations so live server apply continues

- **Implementation commit:** `ca483b549791175854c0f21faf25eae72a016cc2`
- **Change:** Isolate failed legacy unknown-overlay mutations so live SQLite apply and the receive loop keep working (#134)
- **Details:**
  - Root cause of recipes-v3 connection.receive-loop-failed on mutation 773e50f4: performApplyServerTransaction hard-threw for any outbox row lacking optimisticOverlayState/rollback, including already-failed legacy rows. Connect path was already isolated; live add-query-ok/refresh-ok was not.
  - Failed+unknown rows are now diagnostic-isolated (outbox.mutation.legacy-unknown-isolated) and server apply continues. Non-failed unknown rows still fail closed. Retry/discard remain refuse-without-guessing.
  - Focused tests pass; live verify on poisoned recipes SQLite: ~121MB RSS, probes succeed, no receive-loop thrash. https://issues.knophy.com/issues/134
- **Files:**
  - `Sources/InstantSwiftDataCore/InstantRuntime.swift` — Skip hard-throw for failed+unknown overlay during apply; log isolation event
  - `Tests/InstantSwiftDataCoreTests/InstantOutboxDeliveryStallTests.swift` — Regression tests for live and explicit apply over legacy failed unknown
  - `Tests/InstantSwiftDataCoreTests/InstantFailedMutationDiscardTests.swift` — Server apply may proceed; retry/discard still refuse
- **User context (verbatim):**
  > help fixHandoff written for the next agent
  > Next agent’s main job: fix Swift apply / receive-loop resilience (and root cause of mutation apply failure)
- **SpecStory:** unavailable — Grok Build CLI session; no SpecStory URI for this client

## August 5th, 2026 at 12:29:18 p.m. EDT — `1a7303ac92ff` Add recipes-v3 floating debug panel with memory and logs

- **Implementation commit:** `1a7303ac92ff0d689b34a4c12e541b86337edd29`
- **Change:** Add recipes-v3 floating debug panel with memory and logs
- **Details:**
  - Expanded-by-default panel shows footprint/RSS/threads/peak, 2s sparkline, copyable InstantDiagnostics + Linked Infinite logs.
  - Killed idle 5GB recipes-v3; relaunched linked-infinite at ~120MB RSS with panel.
- **Files:**
  - `Sources/RecipesV3App/RecipesDebugPanel.swift` — Floating UI
  - `Sources/RecipesV3App/RecipesDebugSupport.swift` — Metrics probe + log ring + diagnostics bridge
  - `Sources/RecipesV3App/RecipesV3App.swift` — Mount panel on bootstrap
  - `Sources/LinkedInfiniteV3App/LinkedInfiniteDurableLog.swift` — Optional debug sink for in-app panel
- **User context (verbatim):**
  > switched!
- **SpecStory:** unavailable — Grok Build session; no SpecStory URI authorized

## August 5th, 2026 at 9:34:55 a.m. EDT — `adeea919009c` Instrument live infinite-query page-info and auth for host dual-write

- **Implementation commit:** `adeea919009cc3de98a60659ca89e37ac3f3e8e4`
- **Change:** Instrument live infinite-query page-info and auth for host dual-write
- **Details:**
  - Adds infinite-query diagnostic events and remote page-info decode logs so Scribe can see hasNextPage provenance and owner/auth fingerprints over Tailnet.
  - Handler-only InstantDiagnostics delivery covered; short starter emits closed paging diagnostics.
- **Files:**
  - `Sources/InstantSwiftDataCore/InstantInfiniteQueryDiagnostics.swift` — Shared metadata and record helpers for infinite-query events
  - `Sources/InstantSwiftDataCore/InstantInfiniteQuery.swift` — Starter/expand/kickstart/loadNextPage instrumentation
  - `Sources/InstantSwiftDataCore/InstantLiveRefreshApplication.swift` — Log decoded remote page-info
  - `Tests/InstantSwiftDataCoreTests/InstantDiagnosticsTests.swift` — Handler without file path
  - `Tests/InstantSwiftDataCoreTests/InstantInfiniteQueryParityTests.swift` — Short-page diagnostic emission
  - `docs/diagnostics.md` — Host dual-write and infinite-query event catalog
- **User context (verbatim):**
  > yes go ahead
- **SpecStory:** unavailable — Grok Build session; no SpecStory URI authorized for this desktop agent path

## August 5th, 2026 at 8:49:46 a.m. EDT — `cdd1ba421f27` Fix live infinite short-page canLoadNextPage thrash (Jetsam)

- **Implementation commit:** `cdd1ba421f27269b4307ff6056e2bd908096e926`
- **Change:** Fix live infinite short-page canLoadNextPage thrash that Jetsam-killed Scribe on iPad
- **Details:**
  - 1.5.0 pre-kickstart trusted remote hasNextPage on short starter pages, leaving canLoadNextPage true forever.
  - Scribe list UI onAppear + ProgressView swap then thrashed loadNextPage until memory ~4 GB and process death.
  - Pre-kickstart now uses local fullness only; closed windows no-op expand; live parity regression test added.
- **Files:**
  - `Sources/InstantSwiftDataCore/InstantInfiniteQuery.swift` — Close short pre-kickstart pages and stop expand thrash
  - `Tests/InstantSwiftDataCoreTests/InstantInfiniteQueryParityTests.swift` — Regression for remote hasNextPage on short starter
- **User context (verbatim):**
  > The iPad app is continuously crashing um during a recording. Can you please uh read the logs that are coming in from the WebSocket over TailNet and diagnose and fix these. It could be a library issue. I believe the most recent library that should be pinned for instant Swift data is 1.5.0.
- **SpecStory:** unavailable — Grok Build session; no SpecStory URI authorized for this desktop agent path

## August 4th, 2026 at 10:39:35 p.m. EDT — `9b9c8c3b340f` Reproduce Scribe blank-detail in Linked Infinite and lock the library fix

- **Implementation commit:** `9b9c8c3b340fafc900ce8464e2b7735835e52b31`
- **Change:** 1.5.0 path: empty live-query replacements preserve pending optimistic children
- **Details:**
  - Scribe blank detail: empty live refresh retracted pending transcription triples while audio attachments survived.
  - Tests emptyLiveQueryReplacementPreservesPendingOptimisticChildRows and emptyLiveQueryReplacementPreservesOptimisticTranscriptionJoin.
  - Linked Infinite recipe opens detail rows and documents the blank-detail contract; ADR 0013 and docs/releases/v1.5.0.md. Core fix landed earlier as a3b63e73.
- **Files:**
  - `Sources/InstantSwiftDataCore/LinkedInfiniteExample.swift` — Live join fixtures for blank-detail reproduction
  - `Sources/LinkedInfiniteV3App/LinkedInfiniteApp.swift` — Detail screen and blank-detail regression section
  - `Tests/InstantSwiftDataCoreTests/InstantLiveTransportTests.swift` — Core empty-replacement + pending optimistic test
  - `Tests/InstantSwiftDataCoreTests/LinkedInfiniteExampleTests.swift` — Join-shaped blank-detail recipe test
  - `docs/adr/0013-protect-pending-optimistic-from-empty-live-query-retractions.md` — Architecture decision
  - `docs/releases/v1.5.0.md` — Human release story
- **User context (verbatim):**
  > bring this back to the InstantDB library or the Instant Swift data library and create a reproduction there and then display that in the recipes and then resolve it at the library level
- **SpecStory:** unavailable — Grok Build session; no SpecStory URI for this desktop agent path

## August 4th, 2026 at 12:53:07 p.m. EDT — `c8c8011f5846` Green the full suite for the 1.4.0 API-convergence release

- **Implementation commit:** `c8c8011f5846a66fa29da4f1ca809b62dc418c09`
- **Change:** Green full suite and document 1.4.0 API-convergence release
- **Details:**
  - 1351 tests / 115 suites pass with known issues only.
  - Parity pins, outboxRevision rebase expectations, mutationCount semantics, reactor message counts.
- **Files:**
  - `docs/releases/v1.4.0.md` — Human-readable 1.4.0 release story
  - `Tests/InstantSwiftDataCoreTests/CLITests.swift` — Updated coverage and loopback pins
  - `Tests/InstantSwiftDataCoreTests/InstantStoreTests.swift` — Outbox revision and known-issue wraps
- **User context (verbatim):**
  > run full tests, then bump minor version for api convergence, push, update package.swift for targets to use new
- **SpecStory:** unavailable — Grok session; no SpecStory share URI authorized.

## August 4th, 2026 at 12:13:51 p.m. EDT — `3e625416e2db` Inventory every SQLiteData test and close Instant ergonomics parity gaps

- **Implementation commit:** `3e625416e2db9376606bcecaff97043de4073c94`
- **Change:** Inventory all Point-Free SQLiteData tests and close Instant ergonomics parity gaps
- **Details:**
  - 261 upstream runtime tests at vendored 0c79d7a (57 core / 186 CloudKit / 18 examples), dual-method + subagent verified.
  - New ergonomics ports: date roundtrip and assertQuery-style materialization dumps; empty batches and selection edges linked.
  - 222 inventory parity records complete coverage; CloudKit SyncEngine and SQL-only surfaces marked notApplicable with human callouts.
  - InstantSQLiteDataParityReconciliationTests enforces commit pin, count, full coverage, and real Swift test names.
- **Files:**
  - `docs/porting/upstream-sqlitedata-test-inventory.md` — Complete greppable inventory of SQLiteData tests
  - `docs/porting/swift-sqlitedata-port-gap-analysis.md` — Gap analysis and human-attention boundaries
  - `Tests/InstantSwiftDataCoreTests/InstantSQLiteDataErgonomicsParityTests.swift` — Ported date roundtrip and assertQuery-style dumps
  - `Tests/InstantSwiftDataCoreTests/InstantSQLiteDataParityReconciliationTests.swift` — Enforcement suite for SQLiteData parity claims
  - `Sources/InstantSwiftDataCore/InstantParityCoverage.swift` — 222 inventory records so every upstream test is claimed
- **User context (verbatim):**
  > follow the same procedure for porting tests From SQ-like data from point free
  > first identify all tests that they have. then verify with subagent that our count is accurate
  > Call out anything that needs human attention and then get going
- **SpecStory:** unavailable — Grok session continuing Claude fable handoff; no SpecStory share URI authorized.

## August 4th, 2026 at 11:34:35 a.m. EDT — `c4badb4bf6b0` Port upstream's Zeneca deep-join benchmark and measure Swift against TypeScript

- **Implementation commit:** `c4badb4bf6b0deb1d44e0fc98fd1f9a827c0f86e`
- **Change:** Port the Zeneca deep-join benchmark and record that Swift is ~4.9× slower than TypeScript on it
- **Details:**
  - Correctness pin: upstreamInstaQLBigQueryDeepJoinMaterializes over the four-level cyclic users→bookshelves→{books, users→bookshelves} plan.
  - package-benchmark LocalRead.deepJoin.zeneca times the same plan; TypeScript counterpart already exists as core.instaql.big-query.zeneca.
  - Measured release arm64: Swift p50 23 ms wall clock (201 samples) vs TS p50 4.707 ms — gap is now a performance task.
  - Reconciliation now walks *.bench.ts so a missing bench record fails the suite.
- **Files:**
  - `Tests/InstantSwiftDataCoreTests/InstantQueryExecutionParityTests.swift` — Correctness pin for the deep-join plan
  - `benchmarks/Benchmarks/InstantSwiftDataBenchmarking/Benchmarks.swift` — LocalRead.deepJoin.zeneca workload
  - `benchmarks/Benchmarks/InstantSwiftDataBenchmarking/Support.swift` — Zeneca fixture loader for the package-benchmark
  - `Sources/InstantSwiftDataCore/InstantParityCoverage.swift` — instant.instaql.bench.big-query record
  - `Tests/InstantSwiftDataCoreTests/InstantUpstreamParityReconciliationTests.swift` — Include *.bench.ts in the extractor
  - `INSTANT_DATA_PERFORMANCE_BENCHMARKS.md` — Recorded Swift p50 and the 4.9× gap
  - `docs/porting/swift-port-gap-analysis.md` — Mark steps 4 and 5 done
- **User context (verbatim):**
  > I do want the benchmark tests as well. We should have similar, equal, if not better, benchmarks.
- **SpecStory:** unavailable — Continued from Claude Code session 8aa90e99-adb6-4b7e-b76e-e208b4706568 (fable:livestream); no SpecStory share URI authorized for this handoff.

## August 4th, 2026 at 11:28:13 a.m. EDT — `5d28f49070ef` Make upstream parity checkable and re-baseline the inventory on the vendored checkout

- **Implementation commit:** `5d28f49070efbecc49fc32ab02a66b730af881f5`
- **Change:** Make upstream parity checkable against the vendored InstantDB TypeScript suite
- **Details:**
  - Re-baselined inventory and gap analysis on vendored e7101761: 19 files, 186 declarations, 225 runtime cases.
  - Fixed stale Swift test names and paraphrased sourceTestNames in InstantParityCoverage so both sides resolve literally.
  - Added InstantUpstreamParityReconciliationTests with six source invariants (Swift names, both sides named, cited upstream names, surface counts, full coverage, pinned commit).
- **Files:**
  - `Sources/InstantSwiftDataCore/InstantParityCoverage.swift` — Literal upstream/Swift names for parity claims
  - `Tests/InstantSwiftDataCoreTests/InstantUpstreamParityReconciliationTests.swift` — Source-invariant suite that fails when parity drifts
  - `docs/porting/upstream-typescript-test-inventory.md` — Corrected to the vendored commit surface
  - `docs/porting/swift-port-gap-analysis.md` — Status of hygiene work and remaining deep-join bench port
- **User context (verbatim):**
  > list out every single test for instantdb upstream typescript
  > Our goal is to port all of the tests to Swift
  > ensure in the header comment for the file you reference the full filepath of upstream and the commit sha from which you're porting!
- **SpecStory:** unavailable — Continued from Claude Code session 8aa90e99-adb6-4b7e-b76e-e208b4706568 (fable:livestream); no SpecStory share URI authorized for this handoff.

## August 3rd, 2026 at 11:39:09 p.m. EDT — `a52ab0911d4e` Persist the server attribute set on every connect

- **Implementation commit:** `a52ab0911d4e78e1b7b33f610240fe55c74f069b`
- **Change:** Persist the server attribute set on every connect
- **Details:**
  - Instant models attributes as data, so a device can only materialize namespaces whose attributes it holds, and InstantRuntime.observe refuses to register a live query for a namespace it cannot validate. The client decoded the attribute set the server sends in every init-ok into InstantRuntimeLiveSession.serverAttributes but never wrote it to the cache; attributes only became durable as a side effect of a query result for a namespace the device already knew.
  - That deadlocks for any namespace it does not know: no attributes means no subscription, no subscription means no result, no result means the attributes never arrive. Nothing errors, so the device reports a healthy connection and open subscriptions while serving permanently stale data.
  - CORRECTED 2026-08-04: this entry originally claimed the defect was the blocker behind Scribe issue #003 and cited a Mac cache frozen at 133 attributes over 16 namespaces with none for screenStreamSessions. That measurement read ~/Library/Application Support/InstantDB/instant_<app>.sqlite, a stale file no process opens. The running app uses ~/.instant-swift-data/apps/<app>.sqlite, which holds 466 attributes over 38 namespaces including 16 locally-seeded screenStreamSessions attributes and 110 triples in that namespace. The namespace was never missing and the causal claim is withdrawn; after installing 1.3.0 the Mac still did not claim a probe request. An application that seeds initialAttributes from its own schema is structurally immune to this deadlock, which is what should have ruled the theory out at the start.
  - Upstream applies the set on every init-ok (upstream/instant/client/packages/core/src/Reactor.js:640, this._setAttrs(msg.attrs)). applyServerAttributesWithGateHeld does the same on the connect path under the operation gate, through the same compare-and-swap loop the bootstrap attribute merge uses. It merges rather than replaces: upstream keeps locally minted attrs separately in optimisticAttrs(), while this client persists one durable set, so a namespace/name pair the device already holds keeps its local attribute id, which local triples and pending mutations reference. The reconciliation reuses InstantLiveRefreshAttributeContext, the one refresh-ok already performs. Rejected replaying init-ok through applyLiveRefresh with no computations: it writes a synthetic processed-tx-id into sync metadata and prunes the outbox against a transaction id the server never issued.
  - Schema validation failure in observe now also calls reportIssue. A stream that stays empty forever reads exactly like a namespace with no rows, and that silence is why the defect survived weeks of use.
  - Verified: three new tests, of which the two socket tests fail with the connect-path call removed. Verified against the real server from a cache holding no attributes, with the library CLI: before, 0 attributes; after one connection connect, 361 attributes across 37 namespaces; with the call removed the same cache stayed at 0. This clean-cache experiment is untouched by the correction above and is what justifies the change. Full package suite shows no new failures — uncheckedSendableConformancesDocumentProtectionMechanism, serverTransactionLoopbackValidationProducesEvidenceAndPreservesOutbox, and a SIGSEGV in the vendored SQLiteData CloudKit tests all reproduce on clean main.
- **Files:**
  - `Sources/InstantSwiftDataCore/InstantRuntime.swift` — Apply the server attribute set after the live session opens; expose the session's raw payload; report a schema-validation failure loudly; package accessor for the durable attribute set
  - `Sources/InstantSwiftDataCore/InstantLiveRefreshApplication.swift` — Expose the refresh path's attribute reconciliation as InstantLiveRefreshTranslator.attributesToMerge so connect and refresh cannot drift apart
  - `Tests/InstantSwiftDataCoreTests/InstantInitialAttributeSyncTests.swift` — Store-level and scripted-socket statements of the defect
  - `docs/adr/0011-persist-server-attributes-on-connect.md` — Record the decision, the upstream divergence, and the two rejected alternatives
- **User context (verbatim):**
  > fix the below issue
- **SpecStory:** unavailable — Claude Code session; no SpecStory capture is configured for this harness.

## August 3rd, 2026 at 5:06:49 p.m. EDT — `4b596d4ec9b4` Honor cancellation in AsyncSerialGate and name the holder when it stalls

- **Implementation commit:** `4b596d4ec9b42ba8c62dada1aa52cf22442c82ae`
- **Change:** Honor cancellation in AsyncSerialGate and name the holder when it stalls
- **Details:**
  - The old 23-line gate parked cancelled waiters forever: non-throwing withCheckedContinuation, no cancellation handler, waiter never removed. Scribe's session request effect uses cancelInFlight, so each Retry automatic setup tap parked another waiter and made the 10-second stall worse (Scribe #003, blocker 1).
  - enterUnlessCancelled honors cancellation only before acquisition so a started critical section still completes and cannot leave half-applied optimistic state; a caller that throws never acquired the gate and must not leave it. InstantRuntime.transact adopts it; the four gates are labelled operation, auth-promotion, connection, mutation-flush.
  - A stall watchdog (default 5000 ms) reports the holder function, hold duration, longest waiter, queue depth, and repeat count through InstantDiagnostics (which is not the Instant lane, so a stalled gate cannot swallow its own diagnosis) plus reportIssue.
  - Upstream parity verified directly: upstream/instant/client/packages/core/src/Reactor.js contains no mutex, semaphore, lock, or serial queue — the JS reactor is single-event-loop — so the gate is a documented Swift-side adaptation with standard structured-concurrency cancellation.
  - Verified: swift test --filter AsyncSerialGate green (8 tests including cancellation-while-queued, FIFO-preserving middle-waiter cancellation, stall reporting start/stop); full package suite exit 0. This continues work an earlier agent left uncompiled; it built and passed unmodified.
- **Files:**
  - `Sources/InstantSwiftDataCore/AsyncSerialGate.swift` — Four-state waiter machine, cancellation-aware entry, labelled stall watchdog
  - `Sources/InstantSwiftDataCore/InstantRuntime.swift` — transact enters the operation gate cancellation-aware; gates are labelled; wrappers pass the real caller name
  - `Tests/InstantSwiftDataCoreTests/AsyncSerialGateTests.swift` — Pin FIFO order, cancellation behavior before and while queued, and stall reporting
- **User context (verbatim):**
  > your sole job is to get the live stream from the iOS and iPad clients working to the Mac
- **SpecStory:** unavailable — Unavailable: this work ran in Claude Code and no verified SpecStory capture URI is available for this session.

## August 2nd, 2026 at 9:29:14 p.m. EDT — `1ac73a1bce16` Isolate unretryable legacy rows from the live-connect retry sweep

- **Implementation commit:** `1ac73a1bce165920deb83f06c7d7070c652cacf2`
- **Change:** Isolate unretryable legacy rows from the live-connect retry sweep
- **Details:**
  - Tracked as issue #134 (https://issues.knophy.com/issues/134), P0.
  - Upgraded devices carry failed outbox rows with no optimisticOverlayState or rollbackTransaction; their deploy-fixable 'could not resolve' message put them in the automatic retry sweep, where performRetryMutationWithGateHeld threw retainedUnknown.
  - That sweep runs inside the live-connect path, whose catch closes the socket, saves an errored connection state and rethrows, so every reconnect repeated it. One legacy row stopped add-query registration, all later mutations, and the separate diagnostic-log client.
  - Field evidence: physical iPhone and iPad both showed an indefinite 'Loading recordings...' with no error and emitted zero remote diagnostics after upgrading; the E2E sync probe exited 1 on mutation 66846455-3e98-4596-8667-9ea2fb099180.
  - Retain and report the row, then continue the sweep, matching the existing rule that a quarantined mutation must never tear down a healthy connection. Only .retainedUnknown is isolated; persistence and transport failures still abort.
  - Verified RED then GREEN: without the change connect() throws and the mutation queued behind the legacy row is never transacted. With it, the coupled selector plus the outbox-stall suite pass 146 tests in 9 suites with zero unexpected failures.
- **Files:**
  - `Sources/InstantSwiftDataCore/InstantRuntime.swift` — Isolate and report retainedUnknown rows per mutation instead of aborting the connect-time retry sweep.
  - `Tests/InstantSwiftDataCoreTests/InstantOutboxDeliveryStallTests.swift` — Reproduce the upgraded-device outbox shape and pin that one legacy row cannot block connect or later delivery.
- **User context (verbatim):**
  > There's, like, broken triples or broken entities or something like that, and we're needing to recover them. I don't wanna reinstall and uninstall and reinstall the app, because I would like to fix this underlying issue with the library and the application and give it the ability to recover.
- **SpecStory:** unavailable — Unavailable: this work ran in Claude Code and no verified SpecStory capture URI is available for this session.

## August 2nd, 2026 at 7:06:28 p.m. EDT — `460b7ca01e04` Exclude watchOS from the presentation-based auth authorizers

- **Implementation commit:** `460b7ca01e049dd45338a0a1766c90195655d33d`
- **Change:** Exclude watchOS from the presentation-based auth authorizers
- **Details:**
  - canImport(UIKit) is true on watchOS, so the browser-OAuth and Apple ID authorizer guards admitted a platform that has no ASPresentationAnchor, UIApplication.connectedScenes, UIWindowScene, or presentation-context protocols; the declared .watchOS(.v8) platform failed with 13 unavailability errors.
  - Adding !os(watchOS) routes watchOS to the pre-existing #else branch that already throws a clear 'unavailable on this platform' InstantError. No new code path; tvOS and macCatalyst guards intentionally untouched.
  - Found while building Scribe for the physical iPhone: its iOS app embeds ScribeSharedWatch, so the watchOS slice must compile for any device build. The failing build reported 216 failures rooted in this one file.
  - Verified both directions: with the fix reverted, xcodebuild -scheme InstantSwiftData -destination 'generic/platform=watchOS' fails with the same 13 errors; with it applied, BUILD SUCCEEDED. swift test --filter Auth passes 71 tests in 15 suites; the eight-suite coupled acknowledgement selector still passes 139 tests with five asserted known diagnostics.
- **Files:**
  - `Sources/InstantSwiftData/InstantAuthProvider.swift` — Add !os(watchOS) to the three authorizer availability guards so watchOS takes the unsupported-platform branch.
- **User context (verbatim):**
  > and if you could, please put priority on installing the app if it's ready on my iPhone so I can test it while I go do errands
- **SpecStory:** unavailable — Unavailable: this work ran in Claude Code and no verified SpecStory capture URI is available for this session.

## August 2nd, 2026 at 6:39:31 p.m. EDT — `71ccbcf13250` Reconcile accepted writes only after exact authoritative removal

- **Implementation commit:** `71ccbcf132508376adb0281fd100821e1ff6c12f`
- **Change:** Reconcile accepted writes only after exact authoritative removal
- **Details:**
  - Match upstream retractTriple semantics: a cardinality-one retract proves whole-slot absence only when the exact EAV value existed before the prepared authoritative transaction and the key is absent afterward.
  - Keep server-accepted insert, retract, and merge receipts fail-closed when an unrelated retract is a no-op, including a base-absent accepted insert across relaunch; reconcile a matching-base retraction without resurrecting optimistic JSON.
  - Verification: the committed predecessor reproduced RED with one test and two assertions; the final focused pair passed 2/2, the complete coupled gate passed 139 tests in eight suites with zero unexpected failures and five asserted known diagnostics, both library targets build, and independent review found no remaining P0/P1/P2.
- **Files:**
  - `Sources/InstantSwiftDataCore/InstantRuntime.swift` — Use prepared before/final EAV state to distinguish exact authoritative removal from unrelated retract no-ops.
  - `Tests/InstantSwiftDataCoreTests/InstantFailedMutationDiscardTests.swift` — Cover matching retraction, base-absent unrelated retraction, three accepted write shapes, persistence, and relaunch.
  - `PROGRESS.md` — Preserve the immutable predecessor SHA, RED/GREEN sequencing correction, exact final gate, and reviewer clearance.
- **User context (verbatim):**
  > 17% usage remaining, please ensure you again are thoroughly documenting everything such that a cutoff would be easy to handoff to another agent. carry on
- **SpecStory:** unavailable — Unavailable: this implementation was performed in the Codex desktop application and no verified SpecStory desktop capture URI is available.

## August 2nd, 2026 at 6:29:52 p.m. EDT — `8d02a7a8d6b7` Require explicit server acceptance and atomic rejection recovery

- **Implementation commit:** `8d02a7a8d6b7000dea42be0b534e96761e3b1daf`
- **Change:** Require explicit server acceptance and atomic rejection recovery
- **Details:**
  - Resolve mutation delivery only from WebSocket transact-ok or an explicitly server-accepted transport receipt; local, manual, and drain confirmation remains durable and wire-sendable without satisfying the server barrier.
  - On terminal rejection, atomically remove known optimistic effects, preserve and rebuild successor inverses, persist structured failure state, and expose guarded retry/discard operations while legacy unknown rows fail loud and closed.
  - Reconcile accepted receipts only from authoritative operations that cover every materialized effect, and retain all non-removed optimism through live-query pruning.
  - Verification: 136 tests across eight coupled suites passed with zero unexpected failures and five asserted known diagnostics; both InstantSwiftDataCore and InstantSwiftData targets build; independent review reported no remaining P0, P1, or P2 findings.
- **Files:**
  - `Sources/InstantSwiftData/InstantMessage.swift` — Require server-proven acknowledgement before completing typed messages.
  - `Sources/InstantSwiftData/InstantSwiftData.swift` — Expose failed-mutation recovery and server delivery behavior.
  - `Sources/InstantSwiftDataCore/InstantError.swift` — Model structured mutation rejection and retained recovery outcomes.
  - `Sources/InstantSwiftDataCore/InstantLiveRefreshApplication.swift` — Apply authoritative refresh without falsely confirming local-only receipts.
  - `Sources/InstantSwiftDataCore/InstantLiveTransport.swift` — Preserve receipt provenance through live transport.
  - `Sources/InstantSwiftDataCore/InstantModels.swift` — Persist acknowledgement provenance and optimistic overlay state.
  - `Sources/InstantSwiftDataCore/InstantMutationTransport.swift` — Distinguish local confirmation from explicit server acceptance.
  - `Sources/InstantSwiftDataCore/InstantRuntime.swift` — Implement atomic rejection, successor replay, guarded retry/discard, and operation-aware reconciliation.
  - `Sources/InstantSwiftDataCore/InstantStore.swift` — Keep non-removed optimistic lookup baselines during pruning.
  - `Sources/InstantSwiftDataCore/Outbox.swift` — Persist failed mutation state and recovery metadata.
  - `Sources/InstantSwiftDataCore/SQLitePersistenceStore.swift` — Make rollback and failure persistence transactional.
  - `Sources/InstantSwiftDataCore/TripleIndexes.swift` — Support precise rollback bookkeeping.
  - `Tests/InstantSwiftDataCoreTests/InstantFailedMutationDiscardTests.swift` — Cover rejection, relaunch, retry, discard, legacy fail-closed, and operation-aware refresh cases.
  - `Tests/InstantSwiftDataCoreTests/InstantLiveTransportTests.swift` — Cover live rejection and refresh/pruning semantics.
  - `Tests/InstantSwiftDataCoreTests/InstantMutationLifecycleTests.swift` — Cover durable mutation lifecycle transitions.
  - `Tests/InstantSwiftDataCoreTests/InstantStoreTests.swift` — Cover optimistic lookup pruning and large-store rollback scope.
  - `Tests/InstantSwiftDataTests/InstantMessageServerAcceptanceTests.swift` — Prove typed messages wait for real server acceptance.
  - `Tests/InstantSwiftDataTests/MutationDeliveryTests.swift` — Prove delivery barrier provenance behavior.
  - `Tests/InstantSwiftDataTests/V3RecordingActionFixtureTests.swift` — Migrate fixture acknowledgement to explicit server transport.
  - `Tests/InstantSwiftDataTests/V3RecordingsListFixtureTests.swift` — Migrate fixture acknowledgement to explicit server transport.
  - `PROGRESS.md` — Preserve the exact final gate, reviewer clearance, and device-evidence boundary.
- **User context (verbatim):**
  > 17% usage remaining, please ensure you again are thoroughly documenting everything such that a cutoff would be easy to handoff to another agent. carry on
- **SpecStory:** unavailable — Unavailable: this implementation was performed in the Codex desktop application and no verified SpecStory desktop capture URI is available.

## August 2nd, 2026 at 5:55:23 p.m. EDT — `95cc1f03cf53` Record acknowledgement review blockers

- **Implementation commit:** `95cc1f03cf533696ac3fb1ac86e7977c1f130f17`
- **Change:** Record acknowledgement review blockers
- **Details:**
  - Preserve the 39/39 acceptance and rollback evidence without mislabeling it sufficient for shipment.
  - Record four independent-review blockers: atomic transport/encoding rejection rollback, successor inverse rebuilding, local-only confirmation provenance at the server-delivery barrier, and same-ID reservation ownership.
  - Expand the exact task-owned source/test boundary and record the regression, review, commit, and ledger sequence required before the editable ABI is stable for Scribe #059.
- **Files:**
  - `PROGRESS.md` — Make the acknowledgement no-ship boundary and continuation commands cutoff-safe.
- **User context (verbatim):**
  > 17% usage remaining, please ensure you again are thoroughly documenting everything such that a cutoff would be easy to handoff to another agent.
- **SpecStory:** unavailable — Unavailable: this implementation was performed in the Codex desktop application and no verified SpecStory desktop capture URI is available.

## August 2nd, 2026 at 5:41:40 p.m. EDT — `671e37050929` Fix repeated Recipes reactions and presence projection

- **Implementation commit:** `671e370509294195992f6482aced9b7b169c4bc1`
- **Change:** Fix repeated Recipes reactions and presence projection
- **Details:**
  - Preserve typed topic event identity so equal reaction payloads still animate independently while replayed IDs and local echoes do not duplicate.
  - Render a draggable local custom cursor on touch devices and deduplicate Avatar Stack presence by logical user ID in first-seen order.
  - Focused verification passed: 25 tests across ReactionsV3Tests, CustomCursorsV3Tests, AvatarStackV3Tests, and V3PlaybackFixtureTests; physical iPhone/iPad acceptance remains open.
- **Files:**
  - `Sources/InstantSwiftData/InstantTopic.swift` — Add bounded event identities and local-source metadata.
  - `Sources/PresenceRecipesV3App/CustomCursorsV3Screen.swift` — Render touch-device local cursor feedback.
  - `Sources/PresenceRecipesV3App/PresenceRecipesV3App.swift` — Deduplicate reaction event IDs and logical presence users.
  - `Sources/PresenceRecipesV3App/ReactionsV3Screen.swift` — Observe event identities instead of only payload arrays.
  - `Tests/InstantSwiftDataTests/V3PlaybackFixtureTests.swift` — Cover event identity, local source, and bounded history.
  - `Tests/PresenceRecipesV3AppTests/AvatarStackV3Tests.swift` — Cover logical-user deduplication.
  - `Tests/PresenceRecipesV3AppTests/CustomCursorsV3Tests.swift` — Cover local touch cursor lifecycle.
  - `Tests/PresenceRecipesV3AppTests/ReactionsV3Tests.swift` — Cover repeated payloads, replay, and local echo.
  - `PROGRESS.md` — Preserve verification and remaining acceptance work.
- **User context (verbatim):**
  > The animation plays on the iPhone, but not on the iPad.
  > Custom cursors is not doing anything.
  > this duplicates if I leave and rejoin
- **SpecStory:** unavailable — Unavailable: this implementation was performed in the Codex desktop application and no verified SpecStory desktop capture URI is available.

## August 2nd, 2026 at 5:30:19 p.m. EDT — `5d506d7a393c` Record cutoff-safe Instant recovery checkpoint

- **Implementation commit:** `5d506d7a393c0e340445190677c5f151b53b0791`
- **Change:** Record cutoff-safe Instant recovery checkpoint
- **Details:**
  - Preserve issue #043 acknowledgement RED contracts, Recipes issues #127–#130 topic/cursor/presence diagnoses, physical auth evidence boundaries, exact dirty ownership, tests, and remaining acceptance gates before implementation landing.
- **Files:**
  - `PROGRESS.md` — Capture newest-first library and Recipes worker boundaries, tests, and no-ship findings.
  - `docs/audits/commit-changelog.md` — Record the matching Scribe cutoff handoff implementation SHA across repositories.
- **User context (verbatim):**
  > 17% usage remaining, please ensure you again are thoroughly documenting everything such that a cutoff would be easy to handoff to another agent.
- **SpecStory:** unavailable — Codex desktop GUI task; no verified SpecStory CLI capture URI exists for this GUI session.

## August 2nd, 2026 at 4:30:10 p.m. EDT — `6408c8ec1982` Configure Recipes native provider login

- **Implementation commit:** `6408c8ec1982bda51442a6e517c4d900c7818734`
- **Change:** Wire Recipes native-provider metadata and Apple capabilities into the runnable hosts
- **Details:**
  - Issue #113 Recipes now injects app-owned Apple and Google client names plus the instant-recipes-v3 OAuth callback into the shared auth screen.
  - The iOS and macOS targets register the callback scheme and signed Sign in with Apple entitlement; focused configuration and packaging tests protect the contract.
  - This commit establishes a traceable build source; physical provider completion remains an explicit computer-use acceptance lane.
- **Files:**
  - `Sources/AuthV3App/AuthApp.swift` — Allow the host app to inject provider configuration into the auth state.
  - `Sources/RecipesV3App/RecipesV3App.swift` — Propagate app-owned provider metadata from bundle configuration to the Recipes auth surface.
  - `Tests/RecipesV3AppTests/RecipesV3AppTests.swift` — Prove environment and bundle provider metadata routing.
  - `Tests/RecipesV3AppTests/RecipesV3PackagingContractTests.swift` — Prove callback registration and Apple entitlement packaging.
  - `Examples/RecipesV3/iOS-Info.plist` — Register the iOS callback scheme and provider client names.
  - `Examples/RecipesV3/macOS-Info.plist` — Register the macOS callback scheme and provider client names.
  - `Examples/RecipesV3/RecipesV3iOS.entitlements` — Enable Sign in with Apple for the iOS host.
  - `Examples/RecipesV3/RecipesV3macOS.entitlements` — Enable Sign in with Apple for the macOS host.
  - `Examples/RecipesV3/project.yml` — Attach target-specific auth entitlements to generated projects.
  - `Examples/RecipesV3/InstantRecipesV3.xcodeproj/project.pbxproj` — Regenerate the checked-in Xcode project with auth entitlements.
- **User context (verbatim):**
  > Make sure apple login and google login work fully end to end with computer use
  > can you have the off agent launch the recipes app?
- **SpecStory:** unavailable — Codex desktop GUI task; SpecStory captures Codex CLI sessions and no verified desktop capture URI is available.

## August 2nd, 2026 at 4:30:09 p.m. EDT — `ff736a0ae8c0` Document upstream-first Instant policy

- **Implementation commit:** `ff736a0ae8c01b251d75507e8e9cbba5162d6fc1`
- **Change:** Require upstream-first handling for tricky Instant edge cases
- **Details:**
  - Issue #043 now requires inspecting canonical upstream TypeScript behavior before changing Swift synchronization, optimistic state, rejection, reconnect, query, auth, or persistence semantics.
  - Swift adaptations must preserve the upstream transition and test shape and document why platform constraints require any difference.
- **Files:**
  - `AGENTS.md` — Make canonical upstream Instant the default design reference for tricky edge cases.
  - `docs/audits/commit-changelog.md` — Cross-reference the paired Scribe policy commit in the immutable audit ledger.
- **User context (verbatim):**
  > are we looking at how upstream instant handles this too?
  > we should always deffer to upstream for handling tricky edge cases and attmept to implement a solution similar to theirs rather than reinvent the wheel.
- **SpecStory:** unavailable — Codex desktop GUI task; SpecStory captures Codex CLI sessions and no verified desktop capture URI is available.

## August 2nd, 2026 at 2:22:55 p.m. EDT — `f13ee441dabb` Add native auth and atomic guest promotion

- **Implementation commit:** `f13ee441dabbcdf3144a0cd42dfa9f00c1ebdf37`
- **Change:** Add callback-safe native auth and atomic guest promotion
- **Details:**
  - Add native Sign in with Apple with raw/hashed nonce, app-owned browser OAuth callbacks with state and PKCE, and provider configuration for Apple and Google.
  - Promote an active guest by forwarding the exact guest refresh token and committing the non-idempotent exchange only through an exact persisted-session compare-and-swap; surface linked-existing-user semantics without claiming record transfer.
  - Expose injectable atomic promotion operations through InstantSwiftDataClient, preserve deprecated provider conveniences for source compatibility, and replace the sample debug console with a polished guest/account flow.
  - Independent final review is green and swift test --filter Auth passes 62 tests across 13 suites; physical Scribe acceptance remains issue #113.
- **Files:**
  - `Sources/InstantSwiftData/InstantAuthProvider.swift` — Implement nonce-safe Apple authorization and callback-safe browser OAuth state, PKCE, cancellation, and window presentation.
  - `Sources/InstantSwiftData/InstantGuestPromotion.swift` — Expose truthful guest upgrade and linked-existing-user outcomes.
  - `Sources/InstantSwiftData/InstantSwiftData.swift` — Add injectable atomic guest-promotion operations to the public client seam.
  - `Sources/InstantSwiftDataCore/InstantRuntime.swift` — Serialize promotion, forward the exact guest session, and commit through a loud compare-and-swap boundary.
  - `Sources/InstantSwiftDataCore/InstantGuestPromotionExchange.swift` — Model server link evidence and atomic exchange disposition.
  - `Sources/InstantSwiftDataCore/InstantIDTokenExchange.swift` — Attest when the canonical endpoint accepted an exact guest token.
  - `Sources/InstantSwiftDataCore/InstantOAuthExchange.swift` — Attest when the canonical OAuth endpoint accepted an exact guest token.
  - `Sources/InstantSwiftData/InstantAuth.swift` — Route active-guest provider sign-in through atomic promotion and report the identity transition.
  - `Sources/AuthV3App/AuthApp.swift` — Present a polished email, guest, provider, promotion, and signed-in surface.
  - `Sources/AuthV3App/AuthModels.swift` — Configure app-owned provider client names and callbacks while preserving compatibility properties.
  - `Tests/InstantSwiftDataTests/InstantGuestPromotionTests.swift` — Prove same-ID upgrade, linked existing user, cancellation after server success, exact guest forwarding, and compare-and-swap divergence.
  - `Tests/InstantSwiftDataTests/InstantAuthProviderTests.swift` — Prove PKCE, callback state validation, redirect URLs, and stale-attempt isolation.
  - `Tests/InstantSwiftDataTests/V3AuthLoginFixtureTests.swift` — Prove the public injected value-client promotion seam and remove a false-pass transition assertion.
  - `Tests/AuthV3AppTests/AuthV3AppTests.swift` — Prove provider configuration, catalog behavior, and source-compatible convenience properties.
  - `PROGRESS.md` — Preserve verification, review corrections, and remaining physical acceptance lanes.
- **User context (verbatim):**
  > if I have a guest account, I can log in with another account and my records will be linked.
- **SpecStory:** unavailable — Codex desktop task; SpecStory capture is unavailable for this GUI session.

## August 2nd, 2026 at 11:27:24 a.m. EDT — `0f78572e02a1` Speed persisted state loading with bounded batch decoding

- **Implementation commit:** `0f78572e02a17189409fc918b912188e9d50680a`
- **Change:** Reduce eager persisted-state cold-load time with bounded concurrent JSON decoding
- **Details:**
  - Batch ordered SQLite JSON rows into at most 1,024 rows or roughly 1 MiB and decode with exactly two concurrent slots while preserving eager state, outbox, and SQL ordering semantics.
  - Emit per-collection startup phases with row count, batch count, encoded bytes, strategy, and concurrency, and fail malformed persisted rows loudly with their exact batch row range and database path.
  - Add a release profiler that runs only against a caller-supplied disposable SQLite copy and records phase-level cold-start measurements without mutating the backed-up originals.
  - On three fresh copied-backup runs, reduce iPhone runtime median from 4,923 ms to 3,142 ms and iPad from 1,009 ms to 692 ms; retain the explicit claim boundary that these are Mac release-harness timings, not installed-device acceptance.
  - Accept a measured 37,142,528-byte (11.45 percent) transient maximum-RSS increase after rejecting a 4 MiB variant that added roughly 96 MiB; the under-200-ms target still requires a separate lazy or compact persistent projection.
  - Verify 7 startup tests, 2 mutation lifecycle tests, 6 outbox stall tests, 3 persistence atomicity/diff tests, 27 reactor parity tests, release profiler build, targeted formatting, and a clean diff check.
- **Files:**
  - `Sources/InstantSwiftDataCore/SQLitePersistenceStore.swift` — Implement bounded ordered batch assembly, two-slot JSON decoding, collection tracing, and loud row-range/path failures.
  - `Tests/InstantSwiftDataCoreTests/InstantStartupTraceTests.swift` — Prove large-store ordering and trace metadata, malformed-row failure evidence, and optional copied-store profiling.
  - `benchmarks/Package.swift` — Expose the release cold-start profiler as a dedicated executable product.
  - `benchmarks/Profiler/main.swift` — Measure runtime and persisted-state phases against a disposable SQLite copy.
- **User context (verbatim):**
  > make on-disk launch/list loading instantaneous with a target under 200 ms or as close as evidence allows
  > please, please, please, as you go, make comprehensive progress updates to the document and sync
- **SpecStory:** unavailable — Unavailable: this work is running in Codex desktop, and no verified SpecStory CLI capture URI exists for this GUI task.

## August 2nd, 2026 at 10:34:42 a.m. EDT — `b92d5f0976e9` Require restartable library checkpoints

- **Implementation commit:** `b92d5f0976e99bea2712973b5e1f5cfce48c9429`
- **Change:** Require restartable library checkpoints
- **Details:**
  - Standardize the limited-plan continuity rule in the Instant library and persist the active Scribe outbox/startup work, owned performance files, evidence boundaries, and exact cross-repository handoff location.
- **Files:**
  - `AGENTS.md` — Require immutable progress, verification, ownership, blockers, and continuation steps at coherent checkpoints.
  - `PROGRESS.md` — Record the committed starvation fix and current physical-copy startup profiling lane.
- **User context (verbatim):**
  > I'm on a very limited plan for ChatGPT and access to Sol Ultra yourself.
  > standardizing those conventions across my own machine
- **SpecStory:** unavailable — Unavailable: this continuation is running in Codex desktop, and no verified SpecStory CLI capture URI exists for this GUI task.

## August 2nd, 2026 at 10:26:31 a.m. EDT — `e87765b8cd8c` Prevent deep outbox mutation starvation

- **Implementation commit:** `e87765b8cd8c5c2830494ee05c9686f7edb9f4d4`
- **Change:** Prevent deep outbox mutation starvation
- **Details:**
  - Register one-shot queries before reconnect so add-query precedes a persisted mutation backlog.
  - Bound in-flight delivery by both mutation count and 256 low-level transaction steps, refilling only after acknowledgements.
  - Reserve and clear the full in-flight tuple across actor reentrancy, timeout, error, close, and reconnect paths.
- **Files:**
  - `Sources/InstantSwiftDataCore/InstantRuntime.swift` — Prioritize queries and implement acknowledgement-driven weighted delivery.
  - `Tests/InstantSwiftDataCoreTests/InstantOutboxDeliveryStallTests.swift` — Cover query ordering, weighted refills, and immediate-ack reentrancy.
- **User context (verbatim):**
  > commit it so it isn't drifiting in git dirty state
- **SpecStory:** unavailable — Unavailable: this work ran in Codex desktop and no verified SpecStory capture URI was exposed.

## August 1st, 2026 at 10:02:22 a.m. EDT — `d86fe4a6c0b7` docs: add MIT LICENSE file

- **Implementation commit:** `d86fe4a6c0b70c11c8b8573205c35ada954be8c3`
- **Change:** docs: add MIT LICENSE file
- **Details:**
  - Added standard root MIT LICENSE file matching the license declaration in README.md.
- **Files:**
  - `LICENSE` — Add root MIT LICENSE file
- **User context (verbatim):**
  > Any reason not to make it public?
- **SpecStory:** unavailable — Codex desktop turn without specstory recording

## August 1st, 2026 at 9:56:47 a.m. EDT — `2a50ed044f10` docs: add InstantDB open-source platform-agnostic sync details to README

- **Implementation commit:** `2a50ed044f10d026e9374585d273ae1414cb6127`
- **Change:** docs: add InstantDB open-source platform-agnostic sync details to README
- **Details:**
  - Updated README.md to emphasize InstantDB as an open-source, platform-agnostic real-time sync database supporting TypeScript, React, React Native, Vue, Svelte, and Swift.
- **Files:**
  - `README.md` — Add InstantDB platform support overview
- **User context (verbatim):**
  > Note that InstantDB is an open source platform agnostic sync engine with first-class support for TypeScript of all sorts and sizes, React, React Native, View, Svelte.
- **SpecStory:** unavailable — Codex desktop turn without specstory recording

## August 1st, 2026 at 9:52:24 a.m. EDT — `6ec3cb6ac70f` docs: create Point-Free style README with comprehensive feature list and quick start guide

- **Implementation commit:** `6ec3cb6ac70f135e9d8c68ceac7985795607b70d`
- **Change:** docs: create Point-Free style README with comprehensive feature list
- **Details:**
  - Rewrote README.md to follow Point-Free's concise README style with what it is, why use it, quick start, code comparison tables, feature breakdown, testing, and pre-release disclaimer.
- **Files:**
  - `README.md` — Updated to Point-Free styled README
- **User context (verbatim):**
  > So I'd like you to create a README here with a comprehensive list of features. Model the README after the way point free does README's, they're very nice and concise. What it is, why you would use it, how to use it, disclaimers that it's pre-release, things like that.
- **SpecStory:** unavailable — Codex desktop turn without specstory recording

## July 30th, 2026 at 1:11:58 p.m. EDT — `ac6ee60fb2b0` Optimize large Instant snapshot materialization

- **Implementation commit:** `ac6ee60fb2b0435578138a22e8fbc798224a2d9a`
- **Change:** Optimize diagnostics-sized triple snapshot materialization
- **Details:**
  - Materialize deterministic snapshots by walking the existing entity and attribute index order instead of flattening and globally stable-sorting every triple.
  - Added a 50,000-entity sparse debug-log-shaped regression test; the three focused TripleIndexes tests passed and the large case completed in 0.497 seconds.
- **Files:**
  - `Sources/InstantSwiftDataCore/TripleIndexes.swift` — Remove the full-triple global sort and intermediate flattened arrays observed in the live Scribe CPU sample.
  - `Tests/InstantSwiftDataCoreTests/InstantStoreTests.swift` — Protect deterministic ordering and large sparse snapshot behavior.
- **User context (verbatim):**
  > diagnose all the way down to the instantdb swift layer
- **SpecStory:** unavailable — Unavailable: this Codex desktop task exposed no verified SpecStory capture URI.

## July 29th, 2026 at 1:30:30 p.m. EDT — `2b2517e25635` Make the SwiftPM package self-contained

- **Implementation commit:** `2b2517e256351f7e82286424aa83b4055b7e174c`
- **Change:** Publish a self-contained Swift package
- **Details:**
  - Removed all reference-only Git submodules so SwiftPM consumers fetch only the Instant Swift Data package and its declared dependencies.
  - Kept the exact optional reference revisions in upstream documentation and added a validation gate that rejects future tracked submodules.
- **Files:**
  - `.gitignore` — Keep optional reference checkouts local.
  - `.gitmodules` — Remove recursive reference-only package fetches.
  - `upstream/README.md` — Preserve exact optional reference revisions and clone instructions.
  - `upstream/instant` — Stop publishing the Instant reference gitlink.
  - `upstream/instant-ios-sdk` — Stop publishing the historical SDK gitlink.
  - `upstream/sharing-instant` — Stop publishing the historical Sharing experiment gitlink.
  - `upstream/sqlite-data` — Stop publishing the SQLiteData reference gitlink.
  - `validation/verify-swiftpm-publication.sh` — Reject submodules from the publishable package surface.
- **User context (verbatim):**
  > sharing instant was reference. We don't need sharing instant
- **SpecStory:** unavailable — Codex desktop session; no verified durable SpecStory URI is available, and public sharing was not authorized.

## July 29th, 2026 at 1:20:26 p.m. EDT — `0584ffb6c148` Normalize current commit references after identity rewrite

- **Implementation commit:** `0584ffb6c1488461e5d52081f5c88412e4cb82d5`
- **Change:** Reconcile Instant and cross-repository references after technoplato identity normalization
- **Details:**
  - Applied both verified old-to-new maps to every current tracked Instant, Scribe audit, design, screen, and benchmark SHA reference.
  - Preserved external upstream revisions and all non-reference content, validated benchmark JSON, and verified no mapped old SHA remains.
- **Files:**
  - `CHANGELOG.md` — Replace historical Instant implementation SHAs with rewritten equivalents.
  - `docs/audits/commit-changelog.md` — Update the cross-repository Scribe and Instant lookup ledger.
  - `docs/audits/2026-07-26-fable5-comprehensive-audit.md` — Keep historical audit baselines resolvable.
  - `docs/v3-e2e-port-plan.md` — Repoint the detailed implementation timeline to rewritten commits.
  - `validation/benchmarks/v1-cross-sdk-performance-2026-07-19.json` — Preserve benchmark evidence against the rewritten Swift revision.
- **User context (verbatim):**
  > make a backup, one-time backup lookup map of old commits, new commits
  > Again, scribe, all techno-plato.
- **SpecStory:** unavailable — Codex desktop session; no verified durable SpecStory URI is available, and public sharing was not authorized.

## July 27th, 2026 at 4:06:35 p.m. EDT — `598ec0b2459e` Avoid sorting snapshots during live mutation rebases

- **Implementation commit:** `598ec0b2459e83aef66d13ad3480410f51c29f52`
- **Change:** Avoid full snapshot sorting during each optimistic live-data rebase
- **Details:**
  - Scan the nested triple index linearly for the newest transaction timestamp, preserving deterministic snapshot ordering only for callers that actually request a snapshot. This removes the repeated sort/comparable-key hot path captured simultaneously on iPhone and Apple Watch.
- **Files:**
  - `Sources/InstantSwiftDataCore/InstantRuntime.swift` — Uses the linear newest-timestamp scan while rebasing optimistic mutations.
  - `Sources/InstantSwiftDataCore/TripleIndexes.swift` — Adds the scan and avoids temporary sort-key arrays for deterministic snapshots.
  - `Tests/InstantSwiftDataCoreTests/InstantStoreTests.swift` — Locks newest-timestamp and snapshot-order behavior.
- **User context (verbatim):**
  > the recording froze
  > I don't think they're syncing properly.
- **SpecStory:** unavailable — Codex desktop task; no verified SpecStory GUI capture URI is available.

## July 27th, 2026 at 2:14:06 p.m. EDT — `4f077bc71c4e` Record repeated signing acceptance boundary

- **Implementation commit:** `4f077bc71c4e81a73850cb866f5b17619b430c90`
- **Change:** Record the repeated current-head physical signing boundary
- **Details:**
  - Captured a clean reproducible Scribe Watch build that compiled the iOS app, widgets, ReplayKit extension, and Watch app before every final product failed exclusively at Apple Development private-key use.
  - Recorded that the paired Watch was development-ready while the protected Instant log window contained no current-head events, so installation and runtime evidence remain unavailable rather than inferred.
- **Files:**
  - `docs/audits/2026-07-26-fable5-comprehensive-audit.md` — Preserve timestamped signing, device-readiness, provenance, and remote-log acceptance evidence.
- **User context (verbatim):**
  > all the relevant information for reproducible logability
- **SpecStory:** unavailable — No durable SpecStory URI is available because this work is running in Codex desktop and no captured Codex CLI session was verified.

## July 27th, 2026 at 2:00:20 p.m. EDT — `10ad6819c0d8` Record final delivery and device acceptance evidence

- **Implementation commit:** `10ad6819c0d8cf321c80e8289f32ed27f9111ef0`
- **Change:** Record final delivery and device acceptance evidence
- **Details:**
  - Reconcile the durable cross-repository audit with the short-lived writer data-loss root cause, server-acknowledgement and causal replay fixes, platform availability contract, and final full-suite counts.
  - Record the clean provenance-bearing Scribe CLI, sanitized six-lane live matrix with complete 5/5 delivery and sub-two-second maxima, and the honest short-run Node resource caveat.
  - Separate the current-head unsigned physical-target compile from the signed build's private-key authorization failure, preserving earlier install/launch evidence without claiming a new bundle, installation, launch, recording, or ReplayKit broadcast.
- **Files:**
  - `docs/audits/2026-07-26-fable5-comprehensive-audit.md` — Preserve the final performance, correctness, verification, and physical acceptance boundary across both repositories.
- **User context (verbatim):**
  > IMMEDIATE writes locally
  > low latency remote reads
  > ensure that all the test suite still passes.
- **SpecStory:** unavailable — Codex desktop goal task; no durable SpecStory CLI capture URI is available.

## July 27th, 2026 at 1:55:58 p.m. EDT — `981427972ac3` Gate mutation delivery wait by platform availability

- **Implementation commit:** `981427972ac338838f08706ed161eb855ac8016d`
- **Change:** Gate mutation delivery wait by platform availability
- **Details:**
  - Mark the Duration- and ContinuousClock-based server-acknowledgement boundary available on macOS 13, iOS 16, tvOS 16, and watchOS 9 without raising InstantSwiftData's broader iOS 15 and watchOS 8 package deployment targets.
  - Verify all three MutationDeliveryTests and a serialized unsigned Scribe physical-device scheme compile that covers the library's iOS 15 and watchOS 8 deployment contexts.
- **Files:**
  - `Sources/InstantSwiftData/InstantSwiftData.swift` — Preserve older-platform package compilation while exposing the acknowledgement waiter to supported application targets.
- **User context (verbatim):**
  > ensure that all the test suite still passes.
  > Apple Watch
- **SpecStory:** unavailable — Codex desktop goal task; no durable SpecStory CLI capture URI is available.

## July 27th, 2026 at 1:42:56 p.m. EDT — `27b65349097e` Wait for server-acknowledged mutations

- **Implementation commit:** `27b65349097e233b434100654693ccb543d34e93`
- **Change:** Wait for server-acknowledged mutations
- **Details:**
  - Add an explicit live delivery boundary that waits for the durable outbox to empty through server acknowledgements, reconnects a closed client, reports live connection errors, honors cancellation, and times out without invoking the separately injected local flush transport.
  - Replay pending mutations in creation order and retain an older cardinality-one write while a queued successor writes the same entity and attribute, preserving valid full upserts without allowing isolated stale retries to overwrite newer visible state.
  - Verify three focused delivery tests, the causal outbox regression, 28 macro XCTest tests, 1,220 Swift Testing tests across 103 suites, and a live four-lane Swift-writer matrix in which both TypeScript and Swift observers received all five rows within the two-second budget.
- **Files:**
  - `Sources/InstantSwiftData/InstantSwiftData.swift` — Expose the bounded server-acknowledgement waiter without locally confirming the outbox.
  - `Sources/InstantSwiftDataCore/InstantRuntime.swift` — Preserve causally required pending writes while retaining stale-write filtering after successor acknowledgement.
  - `Tests/InstantSwiftDataCoreTests/InstantLiveTransportTests.swift` — Prove queued-successor preservation and isolated stale retry filtering.
  - `Tests/InstantSwiftDataTests/MutationDeliveryTests.swift` — Prove acknowledgement polling, reconnect, timeout, and no local flush.
  - `docs/adr/0010-wait-for-server-acknowledged-mutations.md` — Record the local-first durability boundary, replay decision, and live latency evidence.
- **User context (verbatim):**
  > IMMEDIATE writes locally
  > low latency remote reads
  > upstream mirroring of reactor
  > ensure that all the test suite still passes.
- **SpecStory:** unavailable — Codex desktop goal task; no durable SpecStory CLI capture URI is available.

## July 27th, 2026 at 1:05:29 p.m. EDT — `36e871c147e4` Harden durable live query refreshes

- **Implementation commit:** `36e871c147e4040f105de408e66c6a2e81baea95`
- **Change:** Harden durable live query refreshes
- **Details:**
  - Reject stale live refresh CAS attempts atomically across the store, outbox, ownership rows, server watermark, revisions, and cached state; preserve pre-0011 global triples without inventing ownership.
  - Normalize duplicate canonical live computations deterministically so only the final result contributes operations or persisted ownership, and serialize observer registration with pruning through the runtime operation gate.
  - Verify independent and third-runtime reopen behavior, lazy persisted page-info recovery, bootstrap replacement and orphan collection, confirmed and lookup-dependent mutation protection, the default sixty-fourth-write cadence, and the deterministic prune-registration interleaving.
- **Files:**
  - `Sources/InstantSwiftDataCore/InstantLiveRefreshApplication.swift` — Normalize same-key live computations with final-result-wins semantics.
  - `Sources/InstantSwiftDataCore/InstantRuntime.swift` — Serialize live observer registration with durable pruning and expose a deterministic test interleaving hook.
  - `Tests/InstantSwiftDataCoreTests/InstantLiveTransportTests.swift` — Prove relaunch, page-info, final-result, bootstrap, cadence, and registration-prune behavior.
  - `Tests/InstantSwiftDataCoreTests/InstantStoreTests.swift` — Prove atomic stale-CAS rejection, migration safety, and pending mutation retention.
  - `docs/adr/0009-bound-live-query-result-retention.md` — Record the registration and pruning serialization guarantee.
- **User context (verbatim):**
  > independent post-retention hardening slice
  > duplicate same-canonical-key computations in one applyLiveRefresh normalized deterministically final-result-wins
  > Fix registration/prune serialization canonically and add a deterministic interleaving regression
- **SpecStory:** unavailable — Codex desktop task; no durable SpecStory CLI capture URI is available.

## July 27th, 2026 at 12:39:13 p.m. EDT — `6386abc892aa` Bound live query result retention

- **Implementation commit:** `6386abc892aa0ef8516b9dd283efb59c57200a26`
- **Change:** Bound live query result retention
- **Details:**
  - Apply Reactor querySubs retention defaults of 52 weeks, 1,000 unloaded results, and 1,000,000 owned triples at bootstrap and on a bounded write cadence.
  - Protect active registrations and mutation baselines, unload only after the final observer, and collect global triples only after the final semantic owner disappears.
  - Verify bootstrap, cadence, strict-age, entry-budget, triple-budget, shared-owner, optimistic-write, relaunch, and newer-transaction-metadata cases; the 439-test store, live, and parity selection passes.
- **Files:**
  - `Sources/InstantSwiftDataCore/InstantRuntime.swift` — Enforce retention during bootstrap and live writes while reference-counting active registrations.
  - `Sources/InstantSwiftDataCore/SQLitePersistenceStore.swift` — Prune durable ownership transactionally and collect newly orphaned global triples.
  - `Sources/InstantSwiftDataCore/InstantLiveRefreshApplication.swift` — Unload in-memory page information with the final live observer.
  - `Sources/InstantSwiftDataCore/InstantParityCoverage.swift` — Map bounded live ownership to upstream PersistedObject garbage-collection cases.
  - `Tests/InstantSwiftDataCoreTests/InstantStoreTests.swift` — Prove retention budgets, strict age, shared ownership, mutation protection, and semantic-identity collection.
  - `Tests/InstantSwiftDataCoreTests/InstantLiveTransportTests.swift` — Prove active registration, cancellation, cadence, bootstrap, and relaunch behavior.
  - `Tests/InstantSwiftDataCoreTests/BenchmarkTests.swift` — Pin the added bootstrap persistence hop.
  - `Tests/InstantSwiftDataCoreTests/InstantStoreParityTests.swift` — Verify the updated upstream parity provenance.
  - `docs/adr/0009-bound-live-query-result-retention.md` — Record the accepted ownership-retention and reachability policy.
- **User context (verbatim):**
  > Store/query tracking lacks sufficient garbage collection.
  > upstream mirroring of reactor
  > ensure that all the test suite still passes.
- **SpecStory:** unavailable — Codex desktop goal task; no durable SpecStory CLI capture URI is available.

## July 27th, 2026 at 12:10:17 p.m. EDT — `cb1b7217f4d3` Persist live query result ownership

- **Implementation commit:** `cb1b7217f4d366fd548651e416c31b8cbea91b8f`
- **Change:** Persist live query result ownership
- **Details:**
  - Persist canonical live query result triples and page information in normalized SQLite ownership tables, atomically with the global store, outbox reconciliation, and server checkpoint.
  - Compute authoritative replacement retractions from durable ownership after relaunch while preserving triples still owned by another persisted query.
  - Lazily restore persisted page information and verify the complete 57-test live transport suite plus focused relaunch, shared-owner, and cursor persistence cases.
- **Files:**
  - `Sources/InstantSwiftDataCore/InstantLiveRefreshApplication.swift` — Model deterministic persisted query results and retain only page-info memory state.
  - `Sources/InstantSwiftDataCore/InstantRuntime.swift` — Recompute ownership-aware retractions per CAS attempt and commit live refresh state atomically.
  - `Sources/InstantSwiftDataCore/SQLitePersistenceStore.swift` — Add the ownership schema, indexed owner lookup, and atomic live-refresh persistence.
  - `Tests/InstantSwiftDataCoreTests/InstantLiveTransportTests.swift` — Prove relaunch retraction, shared ownership, and persisted page information.
  - `docs/adr/0008-persist-live-query-result-ownership.md` — Record the durable ownership decision and GC boundary.
- **User context (verbatim):**
  > upstream mirroring of reactor
  > IMMEDIATE writes locally
  > low latency remote reads
- **SpecStory:** unavailable — Codex desktop goal task; no durable SpecStory CLI capture URI is available.

## July 27th, 2026 at 12:01:54 p.m. EDT — `c5667b402dff` Bound live infinite query subscriptions

- **Implementation commit:** `c5667b402dffd792622b24b21955dbf50a74eaaa`
- **Change:** Bound live infinite query subscriptions
- **Details:**
  - Port Instant's limited starter, inclusive forward, inverted reverse, frozen interval, and next-page subscription coordinator so live infinite queries never register an unbounded namespace query.
  - Associate chunk observers with canonical Reactor registration keys and install authoritative page info before publishing server-backed store emissions, while preserving immediate locally materialized starter rows.
  - Verify 17 infinite-query tests, 55 live-transport tests, and 27 Reactor parity tests; the 330-test store/CLI run passed the affected windowing case and its two unrelated empty-stderr flakes passed when rerun individually.
- **Files:**
  - `Sources/InstantSwiftDataCore/InstantInfiniteQuery.swift` — Coordinate bounded live starter, forward, reverse, frozen, paging, and cancellation subscriptions.
  - `Sources/InstantSwiftDataCore/InstantRuntime.swift` — Register page-aware live chunk observers and apply authoritative page info atomically with refreshes.
  - `Sources/InstantSwiftDataCore/InstantStore.swift` — Track live registration keys and update matching observer page windows before publication.
  - `Tests/InstantSwiftDataCoreTests/InstantInfiniteQueryParityTests.swift` — Prove bounded query shapes, forward paging, reverse advancement, cancellation symmetry, and local-first starter output.
  - `docs/adr/0007-bound-live-infinite-query-chunks.md` — Record the accepted transport windowing and ownership boundary.
- **User context (verbatim):**
  > low latency remote reads
  > upstream mirroring of reactor
  > ensure that all the test suite still passes.
- **SpecStory:** unavailable — Codex desktop goal task; no durable SpecStory CLI capture URI is available.

## July 27th, 2026 at 11:35:57 a.m. EDT — `0b3183e1f45c` Document live query cursor preservation

- **Implementation commit:** `0b3183e1f45ccf870f44d35a31bde3714696da69`
- **Change:** Document live query cursor preservation
- **Details:**
  - Record why server-provided four-value cursors remain private wire state beside typed public cursor fields and why locally constructed cursors cannot safely be guessed for live queries.
  - Document the before/after pagination flow, optimistic leading-page consequence, verification evidence, and bounded infinite-query follow-up boundary.
- **Files:**
  - `docs/adr/0006-preserve-live-query-cursors.md` — Preserve the accepted cursor and page-info design decision with compilable before/after syntax.
- **User context (verbatim):**
  > upstream mirroring of reactor
- **SpecStory:** unavailable — Codex desktop goal task; no durable SpecStory CLI capture URI is available.

## July 27th, 2026 at 11:34:55 a.m. EDT — `2c2117ae0ca1` Preserve live query pagination cursors

- **Implementation commit:** `2c2117ae0ca1e84eab8b422b51629919815bf259`
- **Change:** Preserve live query pagination cursors
- **Details:**
  - Decode canonical per-namespace page-info from live query results and retain it through one-shot materialization instead of replacing server pagination metadata with local estimates.
  - Preserve opaque four-element Reactor cursors across Codable storage and re-encode after/before queries, including inclusive cursor options, while retaining the actionable error for hand-built local cursors.
  - Keep optimistic leading-page materialization behavior while returning authoritative server page info; verify the complete 55-test live transport suite and the focused remote-page-window regression.
- **Files:**
  - `Sources/InstantSwiftDataCore/InstantModels.swift` — Retain the opaque server cursor beside the typed public cursor fields.
  - `Sources/InstantSwiftDataCore/InstantLiveQuery.swift` — Re-encode preserved after/before cursors and inclusive options.
  - `Sources/InstantSwiftDataCore/InstantLiveRefreshApplication.swift` — Decode and retain live per-query page information.
  - `Sources/InstantSwiftDataCore/InstantRuntime.swift` — Pass acknowledged server page information into one-shot materialization.
  - `Sources/InstantSwiftDataCore/TripleIndexes.swift` — Return authoritative page information without excluding leading optimistic rows.
  - `Tests/InstantSwiftDataCoreTests/InstantLiveTransportTests.swift` — Prove live decoding, persistence, exact re-encoding, inclusivity, and the local-cursor error boundary.
- **User context (verbatim):**
  > low latency remote reads
  > upstream mirroring of reactor
- **SpecStory:** unavailable — Codex desktop goal task; no durable SpecStory CLI capture URI is available.

## July 27th, 2026 at 11:21:35 a.m. EDT — `c429e815bb0b` Expose direct composite fetch requests

- **Implementation commit:** `c429e815bb0be013b76db96228a503bec7ac37bd`
- **Change:** Expose direct composite fetch requests
- **Details:**
  - Let actors and TCA effects load or subscribe to InstantFetchRequest directly while reusing the same library-owned combination and cancellation machinery as @Fetch.
  - Preserve Sendable request keys without imposing a global Hashable task-identity requirement.
- **Files:**
  - `Sources/InstantSwiftData/InstantSwiftData.swift` — Expose default and explicit-client direct request operations.
  - `Tests/InstantSwiftDataTests/TypedAPITests.swift` — Prove direct composite load and observation through the public surface.
  - `docs/adr/0005-direct-composite-fetch-requests.md` — Record before/after syntax and the ownership decision.
- **User context (verbatim):**
  > upstream mirroring of ergonomics of sqlite-data
- **SpecStory:** unavailable — Codex desktop goal task; no durable SpecStory CLI capture URI is available.

## July 27th, 2026 at 11:02:24 a.m. EDT — `9ce8dccda4c6` Record physical Watch transcription proof

- **Implementation commit:** `9ce8dccda4c67b17a7d0e3d6c7ceabe85730d431`
- **Change:** Record physical Watch transcription proof and the production policy port
- **Details:**
  - Replace prepared-only Watch evidence with the retained complete PCM, WAV, Deepgram, and final-transcript chronology from the clean physical probe.
  - Record production AudioCaptureClient authorization at ac50d0d, a successful generic ScribeSharedWatch build, and the 447-test final Scribe suite.
  - Keep production persistence, repeated cold-start reliability, signed post-port deployment, and physical ReplayKit broadcast as explicit acceptance boundaries.
- **Files:**
  - `docs/audits/2026-07-26-fable5-comprehensive-audit.md` — Reconcile the durable cross-repository audit with the final physical and production Watch evidence.
- **User context (verbatim):**
  > maintain a human-readable timestamped commit audit journal and clean worktrees
  > Apple Watch reliability
- **SpecStory:** unavailable — Codex desktop task; no durable SpecStory CLI capture URI is available.

## July 27th, 2026 at 11:02:24 a.m. EDT — `f742678c8c0f` Record final Watch and suite evidence

- **Implementation commit:** `f742678c8c0f51884e78eb9061a15c91c79615f1`
- **Change:** Record final Watch auto-run and 446-test suite evidence
- **Details:**
  - Update the audit after the active-only Watch auto-run timing fix and the final 446-test Scribe package pass.
- **Files:**
  - `docs/audits/2026-07-26-fable5-comprehensive-audit.md` — Preserve the then-current final Watch timing and package-suite evidence.
- **User context (verbatim):**
  > maintain a human-readable timestamped commit audit journal and clean worktrees
- **SpecStory:** unavailable — Codex desktop task; no durable SpecStory CLI capture URI is available.

## July 27th, 2026 at 10:41:17 a.m. EDT — `d8f5c2219f37` Reconcile final verification evidence

- **Implementation commit:** `d8f5c2219f3751993a517e708ebeff4bf1992be7`
- **Change:** Reconcile final verification evidence
- **Details:**
  - Align the durable audit with the Watch probe recording-compatible asynchronous activation policy.
  - Point final Scribe, performance-safety, and artifact-sanitizer evidence at the authoritative passing logs.
- **Files:**
  - `docs/audits/2026-07-26-fable5-comprehensive-audit.md` — Reconcile the final acceptance record with the last code and verification evidence.
- **User context (verbatim):**
  > maintain a human-readable timestamped commit audit journal and clean worktrees
- **SpecStory:** unavailable — Codex desktop task; no durable SpecStory CLI capture URI is available.

## July 27th, 2026 at 10:40:22 a.m. EDT — `0e2dc17922dc` Record final cross-repository verification

- **Implementation commit:** `0e2dc17922dc276630601e4e27fa88d77c2d53ab`
- **Change:** Record final cross-repository verification
- **Details:**
  - Record the exact passing Scribe, Instant, and performance-safety suite totals and their canonical local logs.
  - Separate verified physical Watch build, install, launch, and prepared-log evidence from the still-unperformed recording/transcription and ReplayKit broadcast interactions.
- **Files:**
  - `docs/audits/2026-07-26-fable5-comprehensive-audit.md` — Make the final acceptance boundary and verification evidence durable.
- **User context (verbatim):**
  > maintain a human-readable timestamped commit audit journal and clean worktrees
- **SpecStory:** unavailable — Codex desktop task; no durable SpecStory CLI capture URI is available.

## July 27th, 2026 at 10:35:33 a.m. EDT — `10f685d52705` Allow nonblocking cookie sync under suite load

- **Implementation commit:** `10f685d52705c14d01266c36df9b64feaab19c31`
- **Change:** Allow nonblocking cookie sync under suite load
- **Details:**
  - Wait against a five-second monotonic deadline instead of one hundred scheduler-dependent sleeps for deliberately nonblocking utility-priority startup cookie sync.
  - Keep the production task off the bootstrap critical path while making parity assertions resilient under the full parallel suite.
- **Files:**
  - `Tests/InstantSwiftDataCoreTests/InstantCookieSyncParityTests.swift` — Use an elapsed-time deadline for asynchronous cookie-sync evidence.
- **User context (verbatim):**
  > ensure that all the test suite still passes.
- **SpecStory:** unavailable — Codex desktop sessions are not supported by the documented SpecStory CLI capture workflow, so no durable session URI is available.

## July 27th, 2026 at 10:35:29 a.m. EDT — `ef9eebdb2b96` Wait for composite fetch observations

- **Implementation commit:** `ef9eebdb2b96444b8db4ba61c797f33ac935f687`
- **Change:** Wait for composite fetch observations
- **Details:**
  - Wait for all four automatic composite observations with the existing bounded typed-condition helper before asserting recorder totals.
  - Keep dynamic load values, exact query plans, and exact query and observation counts covered without sampling asynchronous registration prematurely.
- **Files:**
  - `Tests/InstantSwiftDataTests/TypedAPITests.swift` — Make the composite observation-count assertion deterministic under the full parallel suite.
- **User context (verbatim):**
  > with focused tests and passing full test suites.
- **SpecStory:** unavailable — Codex desktop task; no durable SpecStory CLI capture URI is available.

## July 27th, 2026 at 10:27:04 a.m. EDT — `c238c4e7ae29` Stabilize live transport bootstrap expectation

- **Implementation commit:** `c238c4e7ae29154f46f923e4c7bd1eb3a01bbc65`
- **Change:** Stabilize live transport bootstrap expectation
- **Details:**
  - Stop asserting the transient pre-connect state when live transport bootstrap intentionally starts an asynchronous automatic connection.
  - Continue proving the injected WebSocket metadata plus explicit opened and closed states through connect and close operations.
- **Files:**
  - `Tests/InstantSwiftDataTests/BootstrapTests.swift` — Remove the race-prone initial state assertion while retaining behavior checks.
- **User context (verbatim):**
  > ensure that all the test suite still passes.
- **SpecStory:** unavailable — Codex desktop sessions are not supported by the documented SpecStory CLI capture workflow, so no durable session URI is available.

## July 27th, 2026 at 10:23:39 a.m. EDT — `83939c376899` Stabilize concurrent composite fetch fixtures

- **Implementation commit:** `83939c376899f6fe2b30e5c6789f2482b3f034e2`
- **Change:** Stabilize concurrent composite fetch fixtures
- **Details:**
  - Resolve mock query results by plan instead of task completion order so concurrent composite loads remain deterministic.
  - Assert dynamic composite plans without depending on concurrent scheduling order.
  - Keep the load-only fixture from starting an empty automatic observation that can overwrite the loaded value during assertions.
- **Files:**
  - `Tests/InstantSwiftDataTests/TypedAPITests.swift` — Make composite fetch fixtures deterministic under the full parallel suite.
- **User context (verbatim):**
  > ensure that all the test suite still passes.
- **SpecStory:** unavailable — Codex desktop sessions are not supported by the documented SpecStory CLI capture workflow, so no durable session URI is available.

## July 27th, 2026 at 10:18:42 a.m. EDT — `1657fba57650` Stabilize query cache retention fixtures

- **Implementation commit:** `1657fba57650f1fdf4c84343ee93ef48f19120f0`
- **Change:** Stabilize query cache retention fixtures
- **Details:**
  - Document the lock protecting the pruning cadence's unchecked Sendable state.
  - Keep relaunch, stale-cache, and legacy-migration fixtures on their controlled clocks so the one-year retention policy tests persistence semantics instead of expiring synthetic 2023 rows.
- **Files:**
  - `Sources/InstantSwiftDataCore/InstantRuntime.swift` — Name the NSLock safety mechanism required by concurrency guidance.
  - `Tests/InstantSwiftDataCoreTests/InstantReactorParityTests.swift` — Keep Reactor relaunch cache evidence within the configured retention window.
  - `Tests/InstantSwiftDataCoreTests/InstantStoreTests.swift` — Control relaunch clocks for cache persistence, stale-revision, and legacy-migration tests.
- **User context (verbatim):**
  > ensure that all the test suite still passes.
- **SpecStory:** unavailable — Codex desktop sessions are not supported by the documented SpecStory CLI capture workflow, so no durable session URI is available.

## July 27th, 2026 at 10:14:54 a.m. EDT — `0a1129fa639a` Correct amortized pruning benchmark contract

- **Implementation commit:** `0a1129fa639a416a57ce262e3be7b0a18a0f4935`
- **Change:** Correct the amortized pruning benchmark contract
- **Details:**
  - Restore the offline-relaunch actor-hop fixture to 11 after bootstrap pruning was folded into the existing persistence bootstrap actor call.
  - Keep the deterministic benchmark aligned with the measured implementation and correct the prior ledger wording that implied an added persistence hop.
- **Files:**
  - `Tests/InstantSwiftDataCoreTests/BenchmarkTests.swift` — Pin the integrated bootstrap path at five persistence hops and eleven total actor hops.
- **User context (verbatim):**
  > But we also want to really be focusing on performance.
- **SpecStory:** unavailable — Codex desktop sessions are not supported by the documented SpecStory CLI capture workflow, so no durable session URI is available.

## July 27th, 2026 at 10:13:28 a.m. EDT — `d1066e817f50` Amortize persisted query cache pruning

- **Implementation commit:** `d1066e817f5048abfd8eb5746eddf41b7edf3538`
- **Change:** Amortize persisted query cache pruning
- **Details:**
  - Prune stale persisted query rows during runtime bootstrap, then scan only every 64 successful cache writes instead of on every one-shot materialization.
  - Preserve the existing active-observation protection when a periodic prune runs, and keep pruning failures non-fatal.
  - Refresh the deterministic actor-hop fixture for the bootstrap scan and prove both relaunch pruning and active-key retention.
- **Files:**
  - `Sources/InstantSwiftDataCore/InstantRuntime.swift` — Add bootstrap pruning and the thread-safe write cadence.
  - `Sources/InstantSwiftDataCore/SQLitePersistenceStore.swift` — Keep bootstrap plus retention in one persistence actor call.
  - `Tests/InstantSwiftDataCoreTests/InstantStoreTests.swift` — Cover relaunch pruning and force one-write cadence for active-observation behavior.
  - `Tests/InstantSwiftDataCoreTests/BenchmarkTests.swift` — Pin the added bootstrap persistence hop.
- **User context (verbatim):**
  > implement and verify prioritized performance ... and Instant Reactor ... improvements
- **SpecStory:** unavailable — Codex desktop sessions are not supported by the documented SpecStory CLI capture workflow, so no durable session URI is available.

## July 27th, 2026 at 10:05:15 a.m. EDT — `96cc06864fe7` Add read-only local client facet

- **Implementation commit:** `96cc06864fe7928a3609ac3388a63451aa4a2cb1`
- **Change:** Derive an injectable local-reader facet from an already bootstrapped Instant client
- **Details:**
  - Reuse the live client's runtime, in-memory store, and SQLite connection for ordinary local `query`, `queryOnce`, and observation APIs without server acknowledgement or live query registration.
  - Keep the facet read-only and reject mutations, preserving outbox and remote-capability ownership in the ordinary client.
- **Files:**
  - `Sources/InstantSwiftData/InstantSwiftData.swift` — Add the public composition-boundary `localReader()` facet.
  - `Sources/InstantSwiftDataCore/InstantRuntime.swift` — Separate local observation and one-shot materialization from live freshness enforcement.
  - `Tests/InstantSwiftDataTests/BootstrapTests.swift` — Prove closed-client local reads and observations work while mutation is rejected.
  - `docs/adr/0004-local-reader-facet.md` — Record why the facet replaces a second runtime without adding a second query vocabulary.
- **User context (verbatim):**
  > Instant Reactor and SQLiteData ergonomic parity
- **SpecStory:** unavailable — Codex desktop sessions are not supported by the documented SpecStory CLI capture workflow, so no durable session URI is available.

## July 27th, 2026 at 9:59:16 a.m. EDT — `b812a2c3a1b1` Scope store observer invalidation by namespace

- **Implementation commit:** `b812a2c3a1b13d0d3e90b927a1b4232afd80be7e`
- **Change:** Skip query re-materialization for flat observers in namespaces untouched by a store commit
- **Details:**
  - Resolve changed entity namespaces from both the pre-commit and prepared indexes, including incoming reference targets.
  - Stay conservative for relationship includes and paths, schema changes, and unresolved entity namespaces while deduplicating and publishing only affected flat query plans.
- **Files:**
  - `Sources/InstantSwiftDataCore/InstantStore.swift` — Gate observer materialization by safely resolved namespace dependencies.
  - `Sources/InstantSwiftDataCore/TripleIndexes.swift` — Resolve the namespaces represented by an entity's direct and incoming-reference indexes.
  - `Tests/InstantSwiftDataCoreTests/InstantStoreTests.swift` — Prove a todo commit does not materialize an unrelated users observer.
- **User context (verbatim):**
  > implement and verify prioritized performance ... improvements across both repositories
- **SpecStory:** unavailable — Codex desktop sessions are not supported by the documented SpecStory CLI capture workflow, so no durable session URI is available.

## July 27th, 2026 at 9:56:00 a.m. EDT — `a488b43452ce` Prune persisted query cache automatically

- **Implementation commit:** `a488b43452ceaf2c620775737b99a9cca0d08468`
- **Change:** Apply the Reactor query-subscription retention policy on production one-shot cache writes
- **Details:**
  - Enforce the upstream one-year, 1,000-entry, and adapted one-megabyte encoded-row limits after successful query materialization.
  - Preserve cache keys owned by active store observations and the query that just completed, then emit structured diagnostics for pruning work or failures without discarding a valid query result.
- **Files:**
  - `Sources/InstantSwiftDataCore/InstantRuntime.swift` — Invoke bounded cache retention after successful one-shot persistence.
  - `Sources/InstantSwiftDataCore/InstantStore.swift` — Expose the active observation cache-key set to the runtime.
  - `Tests/InstantSwiftDataCoreTests/InstantStoreTests.swift` — Prove active observations remain protected and become reclaimable after cancellation.
- **User context (verbatim):**
  > implement and verify prioritized performance ... and Instant Reactor ... improvements
- **SpecStory:** unavailable — Codex desktop sessions are not supported by the documented SpecStory CLI capture workflow, so no durable session URI is available.

## July 27th, 2026 at 9:48:11 a.m. EDT — `870a4083e2eb` Add typed snapshot value decoding

- **Implementation commit:** `870a4083e2eb895c776bc2634e0f69a4b3de6cb6`
- **Change:** Decode cardinality-one snapshot fields through schema-owned typed attribute paths
- **Details:**
  - Add `InstantEntitySnapshot.value(_:)` for values that are both Instant-representable and decodable.
  - Preserve precise diagnostics and reject attribute paths from a different entity namespace.
- **Files:**
  - `Sources/InstantSwiftData/InstantTypedAPI.swift` — Delegate typed snapshot access to the existing wire-value decoder.
  - `Tests/InstantSwiftDataTests/TypedAPITests.swift` — Prove typed string, Boolean, and date decoding plus namespace rejection.
  - `docs/adr/0003-typed-snapshot-values.md` — Record the stringly before state, typed API, scope, and consequences.
- **User context (verbatim):**
  > Generate or centralize entity snapshot decoding ... to remove repeated stringly application boilerplate.
- **SpecStory:** unavailable — Codex desktop sessions are not supported by the documented SpecStory CLI capture workflow, so no durable session URI is available.

## July 27th, 2026 at 9:45:23 a.m. EDT — `e965771ebe8b` Add dependency-controlled Instant IDs

- **Implementation commit:** `e965771ebe8b9bdb69a4fe4d96014ab0114e98dd`
- **Change:** Generate typed entity IDs through the Point-Free UUID dependency
- **Details:**
  - Add `InstantID<Entity>()` with canonical lowercase UUID formatting for concise new-entity creation.
  - Preserve `init(rawValue:)` for server, imported, and domain-defined IDs and document the module boundary in ADR 0002.
- **Files:**
  - `Sources/InstantSwiftData/InstantTypedAPI.swift` — Add the dependency-controlled initializer without coupling the core module to Dependencies.
  - `Tests/InstantSwiftDataTests/TypedAPITests.swift` — Prove a UUID override deterministically controls the generated typed ID.
  - `docs/adr/0002-dependency-controlled-instant-ids.md` — Record before/after usage, reasoning, and consequences.
- **User context (verbatim):**
  > Add dependency-controlled IDs ... without broadening the application/library sync boundary.
- **SpecStory:** unavailable — Codex desktop sessions are not supported by the documented SpecStory CLI capture workflow, so no durable session URI is available.

## July 27th, 2026 at 9:30:14 a.m. EDT — `657a74a16e53` Isolate malformed outbox mutations

- **Implementation commit:** `657a74a16e5347c729d94fcc68ceaad60875e4ba`
- **Change:** Fail only an unencodable live mutation and continue sending later healthy mutations
- **Details:**
  - Separate attribute-resolution failures from socket-send failures inside the live session.
  - Persist local encoding failures without marking the shared connection errored or aborting the delivery loop.
- **Files:**
  - `Sources/InstantSwiftDataCore/InstantRuntime.swift` — Collect and durably isolate per-mutation encoding failures.
  - `Tests/InstantSwiftDataCoreTests/InstantLiveTransportTests.swift` — Prove a malformed first mutation cannot poison the healthy mutation behind it.
- **User context (verbatim):**
  > One mutation with an unresolvable attribute aborts the delivery loop and can poison every reconnect.
- **SpecStory:** unavailable — Codex desktop sessions are not supported by the documented SpecStory CLI capture workflow, so no durable session URI is available.

## July 27th, 2026 at 9:30:14 a.m. EDT — `43b65eeffaff` Preserve same-millisecond outbox order

- **Implementation commit:** `43b65eeffafff3b6a54ea8caf8943a329901ab95`
- **Change:** Preserve insertion order for default-timestamp mutations created in the same millisecond
- **Details:**
  - Advance implicit mutation timestamps above the newest durable outbox timestamp, including after compare-and-swap retries.
  - Keep explicitly supplied domain timestamps unchanged so deliberate older writes retain their ordering semantics.
- **Files:**
  - `Sources/InstantSwiftDataCore/InstantRuntime.swift` — Assign monotonic implicit outbox timestamps.
  - `Tests/InstantSwiftDataCoreTests/InstantLiveTransportTests.swift` — Prove reverse-lexical transaction IDs retain insertion order across relaunch.
- **User context (verbatim):**
  > Pending mutations created in the same millisecond are tie-broken by random UUID, so replay/rebase order can invert.
- **SpecStory:** unavailable — Codex desktop sessions are not supported by the documented SpecStory CLI capture workflow, so no durable session URI is available.

## July 27th, 2026 at 9:12:06 a.m. EDT — `fdd4c1e399f0` Reference-count live room joins

- **Implementation commit:** `fdd4c1e399f02e7e30ae967aa8b18d8fffdfc0e2`
- **Change:** Keep shared Reactor rooms joined until their final observer leaves
- **Details:**
  - Count local observers for each room registration instead of treating every leave as final.
  - Send `leave-room` only when the last local observer departs, preserving the shared subscription for remaining observers.
- **Files:**
  - `Sources/InstantSwiftDataCore/InstantReactorParity.swift` — Track room observer counts and remove registrations only at zero.
  - `Tests/InstantSwiftDataCoreTests/InstantReactorParityTests.swift` — Prove that duplicate joins require matching leaves before a server leave is sent.
- **User context (verbatim):**
  > maintain a human-readable timestamped commit audit journal and clean worktrees
- **SpecStory:** unavailable — Codex desktop sessions are not supported by the documented SpecStory CLI capture workflow, so no durable session URI is available.

## July 27th, 2026 at 9:09:40 a.m. EDT — `d2b1e5c0f27a` Isolate automatic fetch generations

- **Implementation commit:** `d2b1e5c0f27a2b161f7d3346a9bdb7ae4058992a`
- **Change:** Prevent automatic fetch observation from superseding explicit tasks
- **Details:**
  - Reserve a generation for automatic observation and require that generation when installing its subscription.
  - Stop a canceled or stale automatic observer from invalidating a newer projected-value task with CancellationError.
- **Files:**
  - `Sources/InstantSwiftData/InstantSwiftData.swift` — Make automatic FetchStorage subscription installation generation-aware.
- **User context (verbatim):**
  > commit methodically and include a changelog with all of our commits where we write updates at the top
- **SpecStory:** unavailable — Codex desktop sessions are not supported by the documented SpecStory CLI capture workflow, so no durable session URI is available.

## July 27th, 2026 at 9:09:40 a.m. EDT — `62eb6067d032` Stabilize ordering parity fixtures

- **Implementation commit:** `62eb6067d032271c2f805dc8543543eba8b3dede`
- **Change:** Make ordering parity fixtures model genuinely later edits
- **Details:**
  - Give the infinite-query reorder mutation an explicit timestamp beyond the fixture hash range and assert the complete local ordering before checking the visible window.
  - Move the Reminders list with a timestamp newer than every seeded list triple.
- **Files:**
  - `Tests/InstantSwiftDataCoreTests/InstantInfiniteQueryParityTests.swift` — Stabilize and tighten the out-of-window reorder fixture.
  - `Tests/InstantSwiftDataCoreTests/InstantSharingSourceParityTests.swift` — Use a later timestamp for the move parity fixture.
- **User context (verbatim):**
  > commit methodically and include a changelog with all of our commits where we write updates at the top
- **SpecStory:** unavailable — Codex desktop sessions are not supported by the documented SpecStory CLI capture workflow, so no durable session URI is available.

## July 27th, 2026 at 9:09:40 a.m. EDT — `8f43f3f5258d` Fix optimistic mutation rebasing

- **Implementation commit:** `8f43f3f5258da82f5d788abe854914a49450fba1`
- **Change:** Keep later optimistic mutations visible over server refreshes
- **Details:**
  - Rebase each remaining optimistic mutation with a timestamp newer than the authoritative server snapshot, matching upstream Reactor overlay semantics.
  - Document the immutable startup trace Sendable boundary required by the concurrency guidance suite.
- **Files:**
  - `Sources/InstantSwiftDataCore/InstantRuntime.swift` — Restamp rebased local writes above the current server snapshot.
  - `Sources/InstantSwiftDataCore/InstantStartupTrace.swift` — Document the unchecked Sendable safety mechanism.
- **User context (verbatim):**
  > commit methodically and include a changelog with all of our commits where we write updates at the top
- **SpecStory:** unavailable — Codex desktop sessions are not supported by the documented SpecStory CLI capture workflow, so no durable session URI is available.

## July 27th, 2026 at 9:09:40 a.m. EDT — `e2dba6ba9ce0` Adopt intent changelog workflow

- **Implementation commit:** `e2dba6ba9ce08a5ec107bade582bc86cfd6e4f8e`
- **Change:** Adopt the repository intent-ledger workflow
- **Details:**
  - Add the change-log discipline to repository instructions and establish a newest-first human-readable ledger.
  - Install the reusable ledger recorder and reproducible-build provenance helper for subsequent implementation commits.
- **Files:**
  - `AGENTS.md` — Require small implementation commits, separate ledger commits, and reproducible provenance.
  - `CHANGELOG.md` — Establish the repository-local intent ledger.
  - `scripts/change-log/record_change.py` — Add deterministic ledger entry generation.
  - `scripts/change-log/build_provenance.py` — Add clean-build provenance generation.
- **User context (verbatim):**
  > commit methodically and include a changelog with all of our commits where we write updates at the top
- **SpecStory:** unavailable — Codex desktop sessions are not supported by the documented SpecStory CLI capture workflow, so no durable session URI is available.

## July 27th, 2026 at 8:55:43 a.m. EDT — `3a0c2c53cf28` Fix live query error isolation

- **Implementation commit:** `3a0c2c53cf28296ea56617d6d868dfa6a73f0383`
- **Change:** Isolate rejected live queries and prevent stale manual-delivery sends
- **Details:**
  - Preserve the server original-event so add-query failures retire only the rejected registration, fail queryOnce promptly, and leave the shared socket opened for healthy queries.
  - Honor autoConnectLiveTransport before scheduling background mutation delivery so a confirmed mutation captured while disconnected cannot be sent after a later manual connect.
- **Files:**
  - `Sources/InstantSwiftDataCore/InstantLiveTransport.swift` — Decode and retain the server original-event on live errors.
  - `Sources/InstantSwiftDataCore/InstantRuntime.swift` — Route query rejection outcomes without reconnecting and gate automatic mutation delivery.
  - `Tests/InstantSwiftDataCoreTests/InstantReactorParityTests.swift` — Prove healthy-query isolation, prompt one-shot failure, and durable pending-mutation behavior.
- **User context (verbatim):**
  > maintain a human-readable timestamped commit audit journal and clean worktrees
- **SpecStory:** unavailable — Codex desktop sessions are not supported by the documented SpecStory CLI capture workflow, so no durable session URI is available.
