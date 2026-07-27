# Change Log

Newest entries appear first. Implementation commits and intent are recorded separately from ledger-only commits.

<!-- change-log:entries -->

## July 27th, 2026 at 2:00:20 p.m. EDT — `c6f8e8404831` Record final delivery and device acceptance evidence

- **Implementation commit:** `c6f8e84048312857c195a1d1d9206d6bd8edfe0c`
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

## July 27th, 2026 at 1:55:58 p.m. EDT — `c211737939da` Gate mutation delivery wait by platform availability

- **Implementation commit:** `c211737939daaba1641dfce5b7cf700d3743778d`
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

## July 27th, 2026 at 1:42:56 p.m. EDT — `e228326c4059` Wait for server-acknowledged mutations

- **Implementation commit:** `e228326c4059227aa0171495cbe902110ebcf9c5`
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

## July 27th, 2026 at 1:05:29 p.m. EDT — `82b74dd2267d` Harden durable live query refreshes

- **Implementation commit:** `82b74dd2267d325c500852cb43a850d1c5783172`
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

## July 27th, 2026 at 12:39:13 p.m. EDT — `5f75dc984510` Bound live query result retention

- **Implementation commit:** `5f75dc984510e26fc80502b8550bee33b525e397`
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

## July 27th, 2026 at 12:10:17 p.m. EDT — `f9c5e9f12fc3` Persist live query result ownership

- **Implementation commit:** `f9c5e9f12fc34435659c6a7c6a6ca4fec1b248e5`
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

## July 27th, 2026 at 12:01:54 p.m. EDT — `f6041883ed4b` Bound live infinite query subscriptions

- **Implementation commit:** `f6041883ed4b5bae5324311d7c64baa279b8fcae`
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

## July 27th, 2026 at 11:35:57 a.m. EDT — `f5e0ce1724ee` Document live query cursor preservation

- **Implementation commit:** `f5e0ce1724ee1bee3f11f7e7c873cf5fcfc8dad6`
- **Change:** Document live query cursor preservation
- **Details:**
  - Record why server-provided four-value cursors remain private wire state beside typed public cursor fields and why locally constructed cursors cannot safely be guessed for live queries.
  - Document the before/after pagination flow, optimistic leading-page consequence, verification evidence, and bounded infinite-query follow-up boundary.
- **Files:**
  - `docs/adr/0006-preserve-live-query-cursors.md` — Preserve the accepted cursor and page-info design decision with compilable before/after syntax.
- **User context (verbatim):**
  > upstream mirroring of reactor
- **SpecStory:** unavailable — Codex desktop goal task; no durable SpecStory CLI capture URI is available.

## July 27th, 2026 at 11:34:55 a.m. EDT — `11edea370b20` Preserve live query pagination cursors

- **Implementation commit:** `11edea370b20bd273fa5e0cfa5de632ff7ffa224`
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

## July 27th, 2026 at 11:21:35 a.m. EDT — `f3e9fe041f1e` Expose direct composite fetch requests

- **Implementation commit:** `f3e9fe041f1e67e0410c3a585cf162f941cca08f`
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

## July 27th, 2026 at 11:02:24 a.m. EDT — `865ead6e6708` Record physical Watch transcription proof

- **Implementation commit:** `865ead6e670851aae223d3b61582dcbef2d9102f`
- **Change:** Record physical Watch transcription proof and the production policy port
- **Details:**
  - Replace prepared-only Watch evidence with the retained complete PCM, WAV, Deepgram, and final-transcript chronology from the clean physical probe.
  - Record production AudioCaptureClient authorization at 3fe73a0, a successful generic ScribeSharedWatch build, and the 447-test final Scribe suite.
  - Keep production persistence, repeated cold-start reliability, signed post-port deployment, and physical ReplayKit broadcast as explicit acceptance boundaries.
- **Files:**
  - `docs/audits/2026-07-26-fable5-comprehensive-audit.md` — Reconcile the durable cross-repository audit with the final physical and production Watch evidence.
- **User context (verbatim):**
  > maintain a human-readable timestamped commit audit journal and clean worktrees
  > Apple Watch reliability
- **SpecStory:** unavailable — Codex desktop task; no durable SpecStory CLI capture URI is available.

## July 27th, 2026 at 11:02:24 a.m. EDT — `5aa73734891a` Record final Watch and suite evidence

- **Implementation commit:** `5aa73734891a439075a1a3997d03818feaed2ace`
- **Change:** Record final Watch auto-run and 446-test suite evidence
- **Details:**
  - Update the audit after the active-only Watch auto-run timing fix and the final 446-test Scribe package pass.
- **Files:**
  - `docs/audits/2026-07-26-fable5-comprehensive-audit.md` — Preserve the then-current final Watch timing and package-suite evidence.
- **User context (verbatim):**
  > maintain a human-readable timestamped commit audit journal and clean worktrees
- **SpecStory:** unavailable — Codex desktop task; no durable SpecStory CLI capture URI is available.

## July 27th, 2026 at 10:41:17 a.m. EDT — `c399e0080ac8` Reconcile final verification evidence

- **Implementation commit:** `c399e0080ac882c641d032fc2d661bb7a088c8dd`
- **Change:** Reconcile final verification evidence
- **Details:**
  - Align the durable audit with the Watch probe recording-compatible asynchronous activation policy.
  - Point final Scribe, performance-safety, and artifact-sanitizer evidence at the authoritative passing logs.
- **Files:**
  - `docs/audits/2026-07-26-fable5-comprehensive-audit.md` — Reconcile the final acceptance record with the last code and verification evidence.
- **User context (verbatim):**
  > maintain a human-readable timestamped commit audit journal and clean worktrees
- **SpecStory:** unavailable — Codex desktop task; no durable SpecStory CLI capture URI is available.

## July 27th, 2026 at 10:40:22 a.m. EDT — `01782d294545` Record final cross-repository verification

- **Implementation commit:** `01782d2945459b0c382ebb7cd6476595fcae482b`
- **Change:** Record final cross-repository verification
- **Details:**
  - Record the exact passing Scribe, Instant, and performance-safety suite totals and their canonical local logs.
  - Separate verified physical Watch build, install, launch, and prepared-log evidence from the still-unperformed recording/transcription and ReplayKit broadcast interactions.
- **Files:**
  - `docs/audits/2026-07-26-fable5-comprehensive-audit.md` — Make the final acceptance boundary and verification evidence durable.
- **User context (verbatim):**
  > maintain a human-readable timestamped commit audit journal and clean worktrees
- **SpecStory:** unavailable — Codex desktop task; no durable SpecStory CLI capture URI is available.

## July 27th, 2026 at 10:35:33 a.m. EDT — `a4245d762055` Allow nonblocking cookie sync under suite load

- **Implementation commit:** `a4245d7620552df9aa272b22d8a6eca82f1ca9eb`
- **Change:** Allow nonblocking cookie sync under suite load
- **Details:**
  - Wait against a five-second monotonic deadline instead of one hundred scheduler-dependent sleeps for deliberately nonblocking utility-priority startup cookie sync.
  - Keep the production task off the bootstrap critical path while making parity assertions resilient under the full parallel suite.
- **Files:**
  - `Tests/InstantSwiftDataCoreTests/InstantCookieSyncParityTests.swift` — Use an elapsed-time deadline for asynchronous cookie-sync evidence.
- **User context (verbatim):**
  > ensure that all the test suite still passes.
- **SpecStory:** unavailable — Codex desktop sessions are not supported by the documented SpecStory CLI capture workflow, so no durable session URI is available.

## July 27th, 2026 at 10:35:29 a.m. EDT — `af4a545cd73c` Wait for composite fetch observations

- **Implementation commit:** `af4a545cd73c74750107520fe590eac98af92f73`
- **Change:** Wait for composite fetch observations
- **Details:**
  - Wait for all four automatic composite observations with the existing bounded typed-condition helper before asserting recorder totals.
  - Keep dynamic load values, exact query plans, and exact query and observation counts covered without sampling asynchronous registration prematurely.
- **Files:**
  - `Tests/InstantSwiftDataTests/TypedAPITests.swift` — Make the composite observation-count assertion deterministic under the full parallel suite.
- **User context (verbatim):**
  > with focused tests and passing full test suites.
- **SpecStory:** unavailable — Codex desktop task; no durable SpecStory CLI capture URI is available.

## July 27th, 2026 at 10:27:04 a.m. EDT — `b6f72262a5dd` Stabilize live transport bootstrap expectation

- **Implementation commit:** `b6f72262a5dd662dc2f17b6ce10442f669dcc0d5`
- **Change:** Stabilize live transport bootstrap expectation
- **Details:**
  - Stop asserting the transient pre-connect state when live transport bootstrap intentionally starts an asynchronous automatic connection.
  - Continue proving the injected WebSocket metadata plus explicit opened and closed states through connect and close operations.
- **Files:**
  - `Tests/InstantSwiftDataTests/BootstrapTests.swift` — Remove the race-prone initial state assertion while retaining behavior checks.
- **User context (verbatim):**
  > ensure that all the test suite still passes.
- **SpecStory:** unavailable — Codex desktop sessions are not supported by the documented SpecStory CLI capture workflow, so no durable session URI is available.

## July 27th, 2026 at 10:23:39 a.m. EDT — `b7eaceccec88` Stabilize concurrent composite fetch fixtures

- **Implementation commit:** `b7eaceccec880bdfbb6b747a9c0335bae9ca509f`
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

## July 27th, 2026 at 10:18:42 a.m. EDT — `25d6b9718b47` Stabilize query cache retention fixtures

- **Implementation commit:** `25d6b9718b475657af5d4553f1434c17a6342862`
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

## July 27th, 2026 at 10:14:54 a.m. EDT — `91578fe1e6b3` Correct amortized pruning benchmark contract

- **Implementation commit:** `91578fe1e6b3da54b52939f0d8736da99b68343f`
- **Change:** Correct the amortized pruning benchmark contract
- **Details:**
  - Restore the offline-relaunch actor-hop fixture to 11 after bootstrap pruning was folded into the existing persistence bootstrap actor call.
  - Keep the deterministic benchmark aligned with the measured implementation and correct the prior ledger wording that implied an added persistence hop.
- **Files:**
  - `Tests/InstantSwiftDataCoreTests/BenchmarkTests.swift` — Pin the integrated bootstrap path at five persistence hops and eleven total actor hops.
- **User context (verbatim):**
  > But we also want to really be focusing on performance.
- **SpecStory:** unavailable — Codex desktop sessions are not supported by the documented SpecStory CLI capture workflow, so no durable session URI is available.

## July 27th, 2026 at 10:13:28 a.m. EDT — `0ba57bdbdc5e` Amortize persisted query cache pruning

- **Implementation commit:** `0ba57bdbdc5e4375e91189c9b1fe40cb69bb7a4a`
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

## July 27th, 2026 at 10:05:15 a.m. EDT — `760afdb4dee3` Add read-only local client facet

- **Implementation commit:** `760afdb4dee3ce23408d48b233bb8501bf481181`
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

## July 27th, 2026 at 9:59:16 a.m. EDT — `da5010dee7b7` Scope store observer invalidation by namespace

- **Implementation commit:** `da5010dee7b70a0ee65891b2859ebc4fd8e3d2f2`
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

## July 27th, 2026 at 9:56:00 a.m. EDT — `c0a030425a31` Prune persisted query cache automatically

- **Implementation commit:** `c0a030425a3191d600649fd8e69740d32ff21f7c`
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

## July 27th, 2026 at 9:48:11 a.m. EDT — `7ec460ab9d76` Add typed snapshot value decoding

- **Implementation commit:** `7ec460ab9d76362209c8a5b0e76e9664a6740cfb`
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

## July 27th, 2026 at 9:45:23 a.m. EDT — `d3e6e704121d` Add dependency-controlled Instant IDs

- **Implementation commit:** `d3e6e704121d0c4c4431a7b346a6c1d49f6e5312`
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

## July 27th, 2026 at 9:30:14 a.m. EDT — `0bda5d56651a` Isolate malformed outbox mutations

- **Implementation commit:** `0bda5d56651ac8e1b5e107b7a5a74ccc4f6c7a68`
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

## July 27th, 2026 at 9:30:14 a.m. EDT — `ea1ca27e3cd0` Preserve same-millisecond outbox order

- **Implementation commit:** `ea1ca27e3cd0be0414ea328ef9e1ab1e10f7278d`
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

## July 27th, 2026 at 9:12:06 a.m. EDT — `ac10cb376523` Reference-count live room joins

- **Implementation commit:** `ac10cb37652315a4d81d488de1848ebd2cc8af9d`
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

## July 27th, 2026 at 9:09:40 a.m. EDT — `2739e7e52982` Isolate automatic fetch generations

- **Implementation commit:** `2739e7e5298215af04768d2b2ddcf6c1f0340b62`
- **Change:** Prevent automatic fetch observation from superseding explicit tasks
- **Details:**
  - Reserve a generation for automatic observation and require that generation when installing its subscription.
  - Stop a canceled or stale automatic observer from invalidating a newer projected-value task with CancellationError.
- **Files:**
  - `Sources/InstantSwiftData/InstantSwiftData.swift` — Make automatic FetchStorage subscription installation generation-aware.
- **User context (verbatim):**
  > commit methodically and include a changelog with all of our commits where we write updates at the top
- **SpecStory:** unavailable — Codex desktop sessions are not supported by the documented SpecStory CLI capture workflow, so no durable session URI is available.

## July 27th, 2026 at 9:09:40 a.m. EDT — `aab5dec69a27` Stabilize ordering parity fixtures

- **Implementation commit:** `aab5dec69a27493df3df5b8b54ed5c417405f0f5`
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

## July 27th, 2026 at 9:09:40 a.m. EDT — `cabc4677fbb4` Fix optimistic mutation rebasing

- **Implementation commit:** `cabc4677fbb4f81741669d919c818b9d86762fd7`
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

## July 27th, 2026 at 9:09:40 a.m. EDT — `6a185835b571` Adopt intent changelog workflow

- **Implementation commit:** `6a185835b57162af967880f93ea8731f7ad20242`
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

## July 27th, 2026 at 8:55:43 a.m. EDT — `d7dd19d499ce` Fix live query error isolation

- **Implementation commit:** `d7dd19d499ce8bf3643c5cbb2967fab7746963ed`
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
