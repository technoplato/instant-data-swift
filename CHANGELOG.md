# Change Log

Newest entries appear first. Implementation commits and intent are recorded separately from ledger-only commits.

<!-- change-log:entries -->

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
