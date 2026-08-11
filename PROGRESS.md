# InstantSwiftData progress log

Newest-first. This log tracks library-side work driven by the Scribe
production-readiness plan
(`/Users/laptop/Sync/tools/realtime-voice-sqlite-instant/docs/production-readiness-plan.md`).
Commit-level history stays in `docs/audits/commit-changelog.md`; this file is
the narrative of what the library must prove and why.

## 2026-08-11 13:38:57 EDT — ADR 0016 Q11 accepted (recordingActive.playbackPlaying)

- Clarified session vs schema (capture = process pointers for live capture).
- Dual timeline openers: openCaptureRecordingTimeline + openPlaybackRecordingTimeline.
- Expanded observe field lists; live speech tail explained.
- Next: Q12 recordingActive.playbackPaused.

## 2026-08-11 13:29:08 EDT — ADR 0016 Q10 accepted (recordingActive.playbackIdle)

- Pre-graph `04-uri-tree.md`: leaf reviewed; playRecording while capture kept; speechRecognized not injectSim.
- session.capture.* documented; schema refresh in overview.
- Next: Q11 `mode.recordingActive.playbackPlaying`.

## 2026-08-11 13:21:20 EDT — ADR 0016 resume: recordingActive leaf review

- Back on pre-graph `04-uri-tree.md` (not 04b message graph).
- Pick up: `mode.recordingActive.*` after captain-reviewed `recordingIdle.*`.
- Q10 open: accept/amend `recordingActive.playbackIdle` first.

## 2026-08-10 17:52:00 EDT — Message graph experiment (04b)

- Exploratory static graph: message catalog, schema-path→writers index, thin tree send lists, command side-effects.
- File: `docs/adr/0016-transcription-example-instant-first/overviews/04b-message-graph-experiment.md` (may discard).
- Goal later: static/runtime check that mutates only go through declared messages.

## 2026-08-10 17:15:17 EDT — ADR 0016 URI tree WIP (handoff)

- Wrote full nested app tree with observe/send/goesTo/mutate on leaves.
- File: `docs/adr/0016-transcription-example-instant-first/overviews/04-uri-tree.md` (**WIP**, needs more feedback).
- Captain reviewed through `mode.recordingIdle.*`; resume at `mode.recordingActive.*`.
- Linked create/finish mutations; goBack = navigation.previous (stack TBD); startRecording owned by mode not library.

## 2026-08-10 16:17:48 EDT — ADR 0016 app tree leaves (observe + send)

- Q09 shape accepted: screen ∥ exhaustive mode nesting; observe/send on leaves only.
- File: `docs/adr/0016-transcription-example-instant-first/overviews/04-uri-tree.md`
- Next: refine any leaf messages, then plan.md / implementation.

## 2026-08-10 15:38:17 EDT — #044 bounded terminal rejection and deferred residency green

- **Terminal rejection:** SQLite now proves and decodes only the rejected mutation's transitive optimistic component, with hard ceilings of 50 bodies and 8 MiB. The footprint conservatively includes forward and rollback writes, concrete entity preconditions, triple reference targets, lookup preconditions, and rule operations.
- **Deferred values:** configured large cardinality-one payloads stay out of the hot indexes at bootstrap, hydrate only for selected entity IDs, and preserve exact optimistic update, restart, rejection, and first-value deletion semantics.
- **Focused evidence:** `InstantTerminalFailureComponentTests` passed 11/11, including a 10,000-row disjoint queue; `DeferredValueResidencyTests` passed 4/4. These are structural tests, not physical memory acceptance.
- **Still open:** explicit-flush rejection still uses the legacy queue-wide path; local infinite queries must slice before deferred hydration and surface hydration failures; the clean physical iPad ReplayKit memory and five-second live-sync trial remains required.

## 2026-08-10 15:23:59 EDT — ADR 0016 URI tree draft (Q09)

- Schema: exclusive segment.body speech|event.
- Draft URI + floating toolbar session map: `docs/adr/0016-…/overviews/04-uri-tree.md`.
- Next: accept Q09, then plan.md / implementation slices.

## 2026-08-10 15:14:36 EDT — ADR 0016 Q08 homogeneous segments

- Schema: segment.body speech|event; responses on any segment; floating toolbar naming.
- Next still: session/URI tree for Transcription hosts.

## 2026-08-10 15:08:46 EDT — ADR 0016 Transcription example interview (schema lock)

- **What:** Opened ADR for a teachable multi-host **Transcription** Instant example (simulated speech, dual-client observe). Domain schema lives in the skills catalog (not forked fully in-repo).
- **Schema:** recording 1→* transcription → segment + event; segment responses (threaded, human|agent). Skill: https://github.com/technoplato/skills/blob/master/domain-as-tree/references/schemas/transcription.md
- **Local ADR:** `docs/adr/0016-transcription-example-instant-first/` · GitHub (main when pushed): https://github.com/technoplato/instant-data-swift/tree/main/docs/adr/0016-transcription-example-instant-first
- **Status:** Q01–Q07 decided (package, archetype, words, lifecycle, debug module, dual-lane session, schema, responses). Implementation not started.
- **Next:** session/URI tree overviews; plan.md + Instant issue when interview locks; then SPM core + hosts.

## 2026-08-09 18:00:47 EDT — #187 reverse relations and rebased writes fixed

- **Physical root cause:** the iPad's first durable recording transaction contained every required field, but Swift resolved child-side reverse relations to the server's forward UUID without swapping endpoints. The server therefore treated transcription and segment IDs as recordings. The corrected swap also removes child-side create/update modes so they cannot be applied to an existing parent.
- **Reproduction:** canonical TypeScript full-create plus immediate update materialized recording/transcription/segment `1/1/1`; the old Swift-shaped reversed step reproduced the exact HTTP 400. Current Swift sent canonical parent-to-child links, acknowledged 30- and 12-step transactions as server transactions `1900` and `1901`, and independently materialized `1/1/1` rows.
- **Second fault:** refresh, terminal rejection, and retry rebased only optimistic triples. Durable operations retained older timestamps, so visible-write filtering stripped required non-primary scalar fields. Commit `71ddd401de9a329233e4175549ee5281e31353de` keeps both layers aligned while preserving true-stale suppression and same-ID idempotency.
- **Verification:** 9 focused transport/rejection/idempotency tests passed across 4 suites; all 20 hydration tests passed; independent review found no remaining priority-zero or priority-one defect. Exact artifacts are under `/tmp/scribe-187-swift-roundtrip.dyuZhU/`.
- **Next:** build/install Scribe against this clean Instant commit, create one fresh iPad recording, require production server acceptance plus exact admin rows within five seconds, then repeat the host/extension memory measurement. The prior 290–450 MB run remains invalid because it contained 322 failed mutations and a rejection/replay storm.

## 2026-08-05 17:57:36 EDT — Dual-write diagnostic thrash (idle multi-GB) fixed in 1.5.4

- **Field:** iPad idle home screen **2.7–4.3 GB** footprint; cold open 122 MB → multi‑GB; continuous `debug-log-batch` mutations 400–700 ops + HOL thrash.
- **Root:** InstantDiagnostics at info dual-written into Instant debugLogs → outbox feedback loop (not recording-path exclusive).
- **Fix:** demote high-frequency diagnostics to debug (`759c899a` / tag **v1.5.4**); `InstantDiagnosticFeedbackLoopTests` green.
- **Host:** InstantDBLogger bridge filters chatter; batch size 8 (`a3d415f`).
- **Device:** clean wipe + 1.5.4 install: **~205→432 MB** in 1 min (not multi-GB); `hol_oversize=0`. Poison outbox survives reinstall without uninstall.
- **Next:** rate-limit HOL diagnostics; companion status spam; absolute idle budget soak; remaining failMutation gate work.


## 2026-08-05 13:31:04 EDT — Production performance readiness plan (research quorum)

- **Evidence (iPad Tailnet):** physical footprint climbed ~88 MB → 880–945 MB (later ~1.3 GB) under 1.5.3; `failMutation` held operation gate 160+ s; permission-denied + missing required-attr storms; ack-timeout reclaim + receive-loop-failed.
- **Plan:** `docs/plans/2026-08-05-production-performance-readiness-plan.md` — Phase 0 thrash stop (error isolation, short gates, poison outbox); Phase 1 absolute budgets; Phase 2 structural efficiency under ADR.
- **Verdict:** not production-ready (~2.5/10 independent eval). Keep SQLite offline; do not re-open 1.5.1 Jetsam thrash.
- **Next:** implement Phase 0.1–0.4 tests-first; pin after 1.5.4/1.6; Scribe stop poison writers + photo coalesce.


## 2026-08-04 — Linked infinite + includes recipe (join-shaped paging)

- **Acceptance.** Typed test
  `typedInfiniteQueryPagesRootEntitiesWithLinkedChildrenOnEachPage` proves
  infinite pages root entities while reverse-included children ride on each
  page (no second infinite root). Core example
  `LinkedInfiniteExampleTests` seeds 7 recordings/transcriptions, pages size
  3, and asserts linked word counts survive `loadNextPage`.
- **API.** `InfiniteQueryPhase` ADT; `@InfiniteQuery(..., pageSize:)` maps to
  root `.limit` (page size, not “only N forever”).
- **Recipe.** `LinkedInfiniteV3App` + Recipes catalog entry `linked-infinite`.
  CLI: `examples linked-infinite seed|list|page` with seed data and Mac
  verification (local cache: first page 3 roots with words=280/240/200;
  page expands to 6).
- **Docs.** README infinite/include section; `Examples/RecipesV3/README.md`
  lists Linked Infinite and CLI commands.
- **Next.** Scribe dual-stream list deletion uses this pattern (single
  recordings infinite + transcriptions include).

## 2026-08-02 18:38:48 EDT — #117 cardinality-one retract follow-up is cleared for landing

- Implementation commit `8d02a7a8d6b7000dea42be0b534e96761e3b1daf`
  and ledger commit `4ca8d60f2a5022688ee73c3b88f3e8a1b5cd0476`
  landed the acknowledgement/rejection slice, but a delayed worker test exposed
  one sequencing error immediately afterward: the commit contains
  `serverAcceptedJSONMergeReconcilesAgainstAuthoritativeRetraction`, while the
  corresponding runtime rule arrived after that commit.
- The committed source was reproduced RED with that one selector: one test
  failed with two assertions because the accepted merge receipt remained in
  the outbox after a matching authoritative cardinality-one retract. The first
  broad fix made that positive case pass but was correctly rejected in review:
  upstream retracts one exact EAV value, not the whole cardinality-one key.
- The final rule now reconciles only when the exact retracted EAV value existed
  in `previousChangedEntityTriples` and the key is absent from the prepared
  final `changedEntityTriples`. A base-absent accepted insert plus unrelated
  retract remains retained across relaunch, while a matching-base retract
  reconciles without resurrecting the accepted merge. Focused proof passed 2/2
  in 0.045 seconds; a three-route insert/retract/merge table also stays green.
- The exact eight-suite coupled selector from the next entry then passed 139
  tests in 0.976 seconds with zero unexpected failures and the same five
  asserted known diagnostics. This supersedes the earlier 136- and 137-test
  snapshots. Explicit cached target builds also passed for
  `InstantSwiftDataCore` in 1.82 seconds and `InstantSwiftData` in 1.28 seconds;
  `git diff --check` is clean.
- The follow-up implementation boundary is exactly
  `Sources/InstantSwiftDataCore/InstantRuntime.swift`,
  `Tests/InstantSwiftDataCoreTests/InstantFailedMutationDiscardTests.swift`,
  and this progress entry. It will land as a separate immutable
  implementation/ledger pair rather than rewriting the already published
  SHAs. Final independent read-only review explicitly found no remaining P0,
  P1, or P2 and confirmed the before/final transition matches upstream
  `retractTriple` semantics.

## 2026-08-02 18:28:43 EDT — #117 acknowledgement/rejection slice cleared for landing

- This is the cutoff-safe replacement for the older partial 15/15 and 39/39
  checkpoints. The acknowledgement/rejection contract is tracked by typed issue
  #117; issue #043 is the Scribe recording-title consumer and was named in some
  immutable older notes by mistake. Do not rewrite those historical commits:
  use #117 for this library slice and cross-reference #043 only when the title
  allocator consumes it.
- With all writers interrupted and the source snapshot frozen, the exact coupled
  selector
  `swift test --scratch-path /private/tmp/instant-ack-review-build --filter
  'InstantMessageServerAcceptanceTests|InstantFailedMutationDiscardTests|MutationDeliveryTests|InstantMutationLifecycleTests|V3RecordingActionFixtureTests|V3RecordingsListFixtureTests|InstantLiveTransportTests|rollbackPreparationIsScopedToChangedEntitiesInLargeStore|liveQueryResultPruningPreservesLookupBaselinesForOutstandingOrUnknownOptimism'`
  exited 0: 136 tests in 8 suites passed in 0.906 seconds with zero unexpected
  failures and exactly five asserted known issues. One is the intentional live
  schema-quarantine diagnostic; four are fail-loud diagnostics proving legacy
  unknown update/delete rows remain untouched in pending and failed states.
- The 50,000-row inverse-capture regression is included in that final gate and
  also passed independently in 0.188 seconds. Explicit cached target builds
  exited 0 for both
  `InstantSwiftDataCore` (1.59 seconds) and `InstantSwiftData` (2.30 seconds),
  and `git diff --check` is clean.
- The four independent-review blockers from 17:54 are now covered: every
  terminal failure route uses atomic overlay removal; discarding an older
  failed predecessor rebuilds and persists later inverses; local/manual/drain
  confirmation is durable but cannot satisfy the server-acceptance barrier;
  and overlapping same-ID automatic-retry reservations are reference counted.
  Root also corrected two final regressions: an older optimistic mutation cannot
  erase a newer local state even though all retained local receipts remain
  wire-sendable, and the encoding-quarantine test now updates an independent
  healthy entity rather than a create that rejection correctly removed.
- A post-review diagnostic edit deliberately forced a real Runtime recompile and
  superseded the earlier cached 126-test observation: Swift rejected `await` on
  the right side of an `||` autoclosure in the active-retry guard. The guard now
  awaits the reservation first and compares the local Boolean. The final 136-test
  gate above is after that compile fix. It also proves an externally refused
  retry/discard reports the exact durable `.retainedForRetry` state while the
  owning rejection disposition is suspended. Adjacent manual-confirmation logs
  now say local confirmation rather than falsely claiming server acceptance.
- The final review found two adjacent refresh/pruning gaps and both now have
  focused regressions. A generic server-accepted transport receipt without a
  transaction watermark is removed only when authoritative refresh operations
  cover every materialized effect: cardinality-many insert/retract operations
  require exact value evidence; cardinality-one replacement requires an
  authoritative insert; JSON merge requires the exact merge patch or a full
  replacement insert; entity and entity-plus-namespace deletes remain scoped;
  and lookup-based writes fail closed. An unrelated entity refresh retains and
  replays the receipt. The post-rebuild five-case operation-coverage selector
  passed 5/5 in 38.88 seconds. Live-query pruning
  protects every outbox row whose optimistic overlay is not explicitly
  `.removed`, including manual/drain/local transport, server transport, and a
  legacy failed row with unknown (`nil`) overlay metadata. The five-case lookup
  matrix failed before that semantic predicate and passes now.
- One first expanded run had 131/132 passing when the unrelated opaque-cursor
  live-query harness hit its 10-second timeout. The exact failure-only rerun
  passed 1/1 in 0.023 seconds, and the immediately following complete selector
  is superseded by the 136/136 green result above. This is recorded as timing
  evidence, not hidden or relabeled as a product failure.
- The complete current implementation boundary is 20 source/test files, not the
  earlier 18-file audit. The two additional V3 fixture suites are required
  contract migrations: their local `confirmMutation` shortcuts now inject an
  explicitly server-accepting transport and call `flushPendingMutations`.
  `PROGRESS.md` is the only documentation path to stage with that source set.
  Nothing is staged or committed yet. The independent reviewer completed a
  final read-only inspection and explicitly reported no remaining P0, P1, or
  P2 findings. No Scribe build, simulator install, or physical-device
  acceptance is claimed by this gate.

## 2026-08-02 17:54:11 EDT — P1 acknowledgement slice is no-ship pending four review blockers

- Independent source review found four correctness gaps after the earlier 39/39
  focused pass. That pass remains useful regression evidence, but it is
  explicitly insufficient for landing or shipping until all four gaps have
  focused tests and the complete acknowledgement gate is green.
- First, generic mutation-transport failures and live mutation-encoding
  failures must use the same atomic optimistic-overlay removal as WebSocket
  rejection; merely marking their outbox rows failed can leave rejected data
  visible in the cache. Second, explicit discard of an older applied failed
  mutation must rebuild and persist every later successor's inverse so a later
  rejection restores the true server base.
- Third, manual confirmation, local drain, and the default local mutation
  transport must not make `waitForAllPendingMutations` return success. Those
  local-only confirmations now require durable provenance that the delivery
  barrier can inspect and reject as not proving server acknowledgement. Fourth,
  automatic-retry reservations for the same mutation need reference counts so
  one overlapping owner cannot release another owner's protection.
- `/root/instant_ack_blockers` owns the acknowledgement/rejection sources and
  focused tests through final verification, independent rereview, task-owned
  commits, and immutable ledgers. Required supporting paths include
  `InstantLiveTransport.swift`, `InstantStore.swift`, `TripleIndexes.swift`,
  `InstantMutationLifecycleTests.swift`, `InstantStoreTests.swift`, and
  `MutationDeliveryTests.swift` in addition to the implementation and focused
  test paths listed in the 17:46 checkpoint. Recipes/presence commits
  `671e3705` and `f64d6a38` are concurrent committed work and must remain
  untouched.
- Current next boundary: finish the four RED/GREEN regressions, replace stale V3
  fixture calls that treat manual confirmation as server proof, rerun focused
  acknowledgement/rejection/live-transport/lifecycle suites plus a clean core
  build and diff checks, then obtain the reviewer's line-precise reread. Nothing
  in this slice is staged or committed yet.

## 2026-08-02 17:46:11 EDT — P1 acknowledgement and rollback candidate is cutoff-safe

- The upstream-backed acceptance boundary tracked under issue #043 is now a
  coherent unstaged landing candidate. Only WebSocket `transact-ok` or an
  explicitly server-accepted mutation transport result releases a waiting
  typed message. Local transport flush, manual confirmation, local drain, and
  generic refresh remain non-accepting. The three former refresh-confirmation
  tests now prove that matching server checkpoints rebase and retain local
  optimism without resolving the transaction.
- Terminal rejection no longer depends on an active query. In one SQLite
  transaction it strips later optimistic successors in reverse, applies the
  rejected mutation's exact inverse, replays successors with rebuilt durable
  inverses, marks the failed overlay removed with its obsolete inverse cleared,
  and persists the failed row plus errored connection metadata. Focused proof
  covers immediate local query state, relaunch, exactly one retry, a second
  rejection, explicit discard, and a successor that is itself later rejected.
- Legacy rows missing both inverse and overlay-state metadata are never changed
  by a transaction-ID heuristic. Retry and discard throw
  `localMutationDisposition = retainedUnknown`; server refresh reports the
  issue and fails closed before touching the cache. Future-skewed update and
  delete fixtures prove the visible local state stays unchanged through all
  three refused paths. The reportIssue emissions are asserted as two expected
  known issues, so the loud development diagnostic is itself test evidence.
- Exact decisive gate:
  `swift test --scratch-path /private/tmp/instant-ack-review-build --filter 'InstantMessageServerAcceptanceTests|InstantFailedMutationDiscardTests|liveRefreshDoesNotConfirmMatchingLocalMutationWithoutTransactOK|liveRefreshRebasesAllOptimisticMutationsWithoutConfirmingThem|emptyLiveRefreshDoesNotConfirmMatchingMutationOrDropOptimisticRows'`.
  Result: 39/39 tests in three suites passed, 0 unexpected failures, 0.573
  seconds, with exactly two expected known issues for the legacy refresh
  warnings. `git diff --check` passes. Strict Swift format lint passes for the
  two new focused suites and the small public API/error/message transport files.
- Owned implementation surface for independent review:
  `InstantMessage.swift`, `InstantSwiftData.swift`, `InstantError.swift`,
  `InstantLiveRefreshApplication.swift`, `InstantModels.swift`,
  `InstantMutationTransport.swift`, `InstantRuntime.swift`, `Outbox.swift`, and
  `SQLitePersistenceStore.swift`; owned tests are
  `InstantMessageServerAcceptanceTests.swift`,
  `InstantFailedMutationDiscardTests.swift`, and the three renamed refresh
  cases in `InstantLiveTransportTests.swift`. Other dirty source/test files are
  concurrent work and remain untouched. Nothing in this slice is staged or
  committed; the only remaining boundary is root's independent source review,
  followed by a task-owned commit and immutable ledgers if approved.

## 2026-08-02 17:39:10 EDT — Recipes reaction, touch cursor, and logical presence fixes green

- The bounded upstream-parity implementation for #127–#129 is now source
  complete and independently rerun from scratch
  `/private/tmp/instant-ack-review-build`. Exact selector:
  `swift test --scratch-path /private/tmp/instant-ack-review-build --jobs 1 --filter 'ReactionsV3Tests|CustomCursorsV3Tests|AvatarStackV3Tests|V3PlaybackFixtureTests'`.
  It exited 0: 25 tests in 4 suites passed in 0.101 seconds after a 51.90-second
  incremental build.
- `InstantTopic` now preserves a bounded 128-event typed window with server
  event ID and local-source identity while keeping the existing `messages`
  projection source-compatible. `ReactionsV3Model` uses a bounded 256-ID
  replay guard, animates distinct identical-payload events, ignores replay of
  the same ID, and suppresses the persisted local echo because the sender
  already animates immediately.
- Custom Cursors now renders explicit touch-device local feedback and an
  accessible draggable local cursor on iPhone/iPad. Avatar Stack projects one
  row per logical `userID` in first-seen order instead of exposing every stale
  authenticated session. The focused app and wrapper tests cover both paths.
- Root reviewed the complete task-owned diff and `git diff --check` passes.
  Existing strict-format debt remains in larger pre-existing files, while the
  newly changed focused test files and Reactions screen lint clean; no unrelated
  broad formatting rewrite was performed.
- #130's per-mount color change remains documented as canonical upstream
  behavior, not a defect. Its initial board asymmetry remains open. No physical
  iPhone/iPad post-fix behavior pass is claimed; that requires a clean committed
  build after the separate acknowledgement slice lands.

## 2026-08-02 17:37:24 EDT — Genuine server acceptance is 15/15 green

- The source-compatible acknowledgement contract now records confirmation
  provenance and emits `.serverAccepted` only for transaction-specific proof:
  a WebSocket `transact-ok` correlated by client event ID, or a mutation
  transport result that explicitly declares equivalent server acceptance.
  Manual confirmation, the default local transport, local drain, and a generic
  query refresh can still update their existing local bookkeeping but cannot
  release `sendAwaitingServerAcceptance`. This is the exact upstream
  `Reactor.js` refresh-versus-`transact-ok` distinction tracked under issue
  #043, rather than a new Swift-only acceptance policy.
- `InstantSwiftDataClient` now exposes runtime-backed failed-mutation listing,
  retry, and discard. `InstantError` and the recovery result carry a
  machine-readable local-state disposition: retained for retry, discarded, or
  retained unknown. Legacy `InstantError` JSON without the optional field still
  decodes.
- Exact GREEN command:
  `swift test --scratch-path /private/tmp/instant-ack-review-build --filter InstantMessageServerAcceptanceTests`.
  Result: 15/15 Swift Testing tests passed, 0 failures, 0.497 seconds. The gate
  includes four false-acceptance regressions, both genuine acceptance sources,
  retained/discarded rejection state, structured server metadata, disposition
  race prevention, timeout/cancellation durability, runtime-less fail-fast,
  and legacy error decoding.
- Terminal rejection implementation is now source-compiling: a known rejected
  optimistic layer and its later successors are stripped in reverse, the
  rejected inverse is applied, successors are replayed with rebuilt inverses,
  and store/outbox/errored connection metadata persist in one SQLite
  transaction. Exact compile gate:
  `swift build --scratch-path /private/tmp/instant-ack-review-build --target InstantSwiftDataCore`;
  result: exit 0, target build complete in 13.33 seconds. Heuristic removal by
  matching transaction IDs has been deleted; direct retry/discard of a legacy
  row missing both inverse and overlay state now fails loud with
  `retainedUnknown`.
- This remains an unstaged, uncommitted landing candidate while regressions are
  added for zero-query rejection, relaunch, retry-once/discard, successor
  replay, and future-skewed legacy update/delete rows. Generic live-refresh
  tests that previously treated a matching checkpoint as acceptance must also
  be updated to the upstream contract before the broader acceptance sweep.

## 2026-08-02 17:27:43 EDT — Recipes topic, cursor, and presence defects reach upstream-backed RED boundary

- `/root/recipes_presence` claimed typed issues #127–#130 and owns only the
  Recipes presence/event files plus an explicitly approved clean
  `Sources/InstantSwiftData/InstantTopic.swift` extension and focused wrapper
  test. The acknowledgement/rejection slice and its concurrent dirty files
  remain untouched; nothing from this lane is staged or committed.
- Canonical `reactions.tsx` handles every broadcast through `useTopicEffect`.
  Swift currently publishes replacement payload arrays and the Recipes model
  deduplicates only by array count, so distinct one-message broadcasts produce
  the observed `1 -> 1` drop. The approved TDD shape keeps `messages`
  source-compatible, exposes only a bounded ID-preserving typed event window,
  and proves distinct-ID delivery, same-ID replay suppression, and no duplicate
  sender animation from a local persisted/echo event.
- `CustomCursorsV3Screen` publishes drag presence on iOS but compiles local
  cursor rendering only for tvOS/watchOS. React's native-mouse assumption does
  not give touch devices visible local feedback, so #128 needs an explicit
  SwiftUI touch adaptation with accessibility coverage.
- `AvatarStackV3Model` currently keeps every member row, including repeated
  authenticated sessions sharing one `userID`; #129 needs stable first-seen
  logical-identity projection and deterministic count tests. This does not yet
  prove server leave/reconnect cleanup or cross-device count convergence.
- Canonical Merge Tiles intentionally selects an available random color from
  component-local state on each mount; #130's color change is therefore
  upstream-compatible. Initial board asymmetry remains unreproduced. No focused
  test, package build, install, launch, or physical iPhone/iPad pass is claimed.

## 2026-08-02 17:25:59 EDT — Server-acceptance contract RED checkpoint

- Ownership remains the uncommitted InstantSwiftData acknowledgement/rejection
  slice only; no source, test, or ledger file has been staged or committed, and
  concurrent dirty work is preserved. The immediate cutoff-safe target is the
  independently reviewed P1/P2 acceptance gap, not optional retry-scan or
  reservation-refcount polish.
- Canonical upstream evidence was reread before changing Swift: `Reactor.js`
  refresh replaces the authoritative query store and reapplies outstanding
  optimistic mutations, while only the transaction-specific `transact-ok`
  path resolves that mutation as synced. Consequently, generic refresh, local
  transport flush, manual confirmation, and local drain must never release
  `sendAwaitingServerAcceptance`; an explicitly server-accepted transport
  result or WebSocket transaction acknowledgement may. This follows durable
  Instant guidance tracked under issue #043.
- Focused tests now encode those four negative paths, the two valid positive
  paths, the public failed-mutation list/disposition contract, and legacy error
  decoding in
  `Tests/InstantSwiftDataTests/InstantMessageServerAcceptanceTests.swift`.
  Exact RED command:
  `swift test --scratch-path /private/tmp/instant-ack-review-build --filter InstantMessageServerAcceptanceTests`.
  It exited 1 at compile time, as intended, because production has no explicit
  transport `acceptance`, no `InstantError.localMutationDisposition`, and no
  `InstantSwiftDataClient.failedMutations()` yet. The test helper also used the
  wrong existing live-message case name (`transactOK`), which must be corrected
  to the repository's actual transaction-acknowledgement case before counting
  the next RED/GREEN result.
- Next exact implementation boundary: add source-compatible, Codable
  confirmation-source metadata; publish `.serverAccepted` only for genuine
  transaction-specific server proof; remove generic-refresh confirmation;
  expose failed-list/retry/discard plus machine-readable retained/discarded/
  retained-unknown disposition. Then rerun the same selector from its isolated
  scratch path. Remaining no-ship blocker after that boundary: terminal live
  rejection must atomically remove known optimism and persist errored metadata,
  while legacy rows missing inverse/overlay state must remain loud and unknown
  without heuristic cache mutation.

## 2026-08-02 17:07:28 EDT — Physical Apple login passes; acknowledgement review finds no-ship gaps

- The exact clean Recipes implementation commit `6408c8ec1982bda51442a6e517c4d900c7818734`
  was exported with embedded `dirty=false` provenance, built with Apple
  Development team `4EC72DECN9`, installed, launched, and observed connected to
  InstantDB on both the physical iPhone 17 Pro (iOS 27.0) and physical iPad.
- The user completed the native Apple account sheet on the iPhone. Instant
  returned the connected Apple provider account and the app rendered `Account
  connected successfully.` The supplied screenshot's SHA-256 is
  `adec054d1968a444e17bfc216cd8e949b6033ff02757fe0f0fa74d0bdf5c10c1`;
  typed issue #113 stores it as attachment
  `3275257f-8b58-4550-910b-bd137c99a93e` and log
  `issue-113-recipes-iphone-apple-e2e-pass-20260802T165750`. This is physical
  end-to-end Apple acceptance, not merely build or sheet-presentation proof.
- The same signed build installs and launches on iPad, visibly connects to
  InstantDB, and presents the native Apple sheet. The iPad account was not
  changed. Earlier simulator evidence remains split correctly: Google completed
  end to end, the unsigned Apple build failed with AuthorizationError 1000, and
  a development-signed build cleared that entitlement error before reaching the
  simulator's missing-Apple-account boundary.
- Scribe auth integration is now delegated with a narrow host boundary: reuse
  `AuthV3App` for Apple, Google, magic code, and atomic guest promotion; add one
  TCA account presentation route shared by iPhone, iPad, and Mac; do not copy
  provider token or promotion transitions into the application.
- The upstream-aligned acknowledgement/rejection slice now passes 35/35 tests
  across five suites from fresh scratch path
  `/private/tmp/instant-ack-swift-build` (0 failures, 0.443 seconds). The gate
  covers exact rollback, successor replay, retry after refresh/relaunch,
  dual-trace preservation, 50,000-row entity-scoped preparation, and atomic
  retry metadata with SQLite trigger fault injection. `git diff --check` and
  strict lint of all new/small task-owned files pass.
- A separate Sol Ultra reviewer reran the same 35 tests from isolated scratch
  (35/35) but returned **NO-SHIP** because those tests omitted three P1 paths:
  local flush/manual confirm/drain can emit `.serverAccepted` without a real
  server acknowledgement; a terminal rejection leaves its optimistic cache
  visible across relaunch when no query is registered; and legacy rows without
  inverse/overlay metadata can reapply or discard updates/deletes with cache
  corruption. It also found a P2 public-API gap: default retention has no client
  retry/discard surface and the thrown error does not name the local-state
  disposition.
- The original library worker has resumed TDD ownership of those exact four
  findings. No acknowledgement implementation is staged or committed. The
  shared `.build` directory remains non-evidence because concurrent incremental
  jobs left stale ABI products after `InstantError` changed; all acceptance
  reruns use isolated scratch builds.

## 2026-08-02 16:23:13 EDT — Upstream-aligned rejection rollback is green, review pending

- The repository rule is now explicit in `AGENTS.md`: tricky Instant edge
  cases start with the canonical vendored TypeScript client, reuse its state
  transition and test shape, and document any Swift-only adaptation instead of
  inventing a competing policy. Typed Scribe preference
  `defer-tricky-instant-edge-cases-to-upstream` records the same durable
  direction under issue #043.
- Canonical `Reactor.dataForQuery` / `_applyOptimisticUpdates` keep server query
  state separate from pending optimistic mutations; `_handleMutationError`
  removes a rejected mutation. Swift persists one materialized SQLite store,
  so the equivalent implementation records each optimistic transaction's exact
  inverse, removes those layers in reverse order before a server refresh,
  reapplies surviving outbox mutations in order, and refreshes their durable
  inverse images against the newest server base.
- Explicit `.discard` now atomically removes only the handled failed outbox row,
  rolls back creates/updates/deletes/relationship cascades, replays later
  optimistic writes or deletes, publishes the restored query state, and
  survives relaunch. A server refresh clears obsolete failed inverse images so
  a later discard cannot overwrite newer server values or resurrect a
  server-deleted entity.
- Live rejection records preserve the server status, type, hint, and trace ID;
  the failed outbox transition and errored connection metadata commit together.
  HTTP 401/403 and permission/unauthorized/forbidden types are terminal server
  rejections, not reconnect noise. Schema-resolution failures can still retry
  after reconnect, but permission failures remain loud and retained until an
  explicit caller retry/discard.
- `sendAwaitingServerAcceptance` registers lifecycle observation before the
  optimistic transaction, prepares once, returns only after `transact-ok`, and
  retains pending work on timeout/cancellation. Automatic reconnect and manual
  retry cannot race an asynchronous rejection disposition; focused tests now
  prove both timeout and cancellation release that reservation afterward.
- Current evidence: 31/31 rejection/rollback/live-retry/delivery tests pass;
  12/12 existing mutation-lifecycle and recording fixture tests pass. The
  formerly unbounded
  `runtimeLiveMutationErrorPersistsFailureAndRetryResends` proof now uses a
  bounded outbox observer and passes together with rejected-query refresh.
  Legacy `PendingMutation` and `InstantError` payloads without the new optional
  fields decode successfully. Strict format lint passes for the two new focused
  suites and touched delivery test; `git diff --check` passes.
- This slice is still uncommitted while an independent Sol review inspects the
  upstream parity, concurrency, persistence, and backward-compatibility
  boundaries. No Recipes or Scribe binary may be installed from this dirty
  checkout; the next boundary is review approval, coherent source/test commit,
  immutable ledgers, then the separate Recipes host commit and clean rebuild.

## 2026-08-02 15:42:43 EDT — Recipes auth host acceptance (uncommitted)

- The user correctly identified that implementation `f13ee441` changed the
  shared `AuthV3App` and library but did not modify, rebuild, or relaunch the
  native Recipes application. Typed Issue #113 now preserves that correction
  and exact quote; its Apple/Google/guest-promotion application criteria remain
  unsatisfied.
- Recipes now owns its provider boundary. `RecipesV3AppConfiguration` derives
  the Apple and Google client names plus
  `instant-recipes-v3://oauth-callback` from environment or bundle metadata
  and passes that exact configuration into `AuthV3LoginScreen`. The shared
  screen accepts app-owned provider configuration without duplicating the auth
  UI.
- The iOS and macOS hosts now register the callback URL and declare the Default
  Sign in with Apple entitlement in both `project.yml` and the generated Xcode
  project. Focused configuration/callback/entitlement/Auth syntax selectors pass
  7/7, including the real bundle-metadata fallback used at launch; all four
  plists lint clean. The broad target selector ran the focused
  tests successfully but the package test process later exited with signal 11,
  so only the six independently green selectors count as evidence.
- Disposable unsigned Xcode builds of `InstantRecipesV3macOS` and
  `InstantRecipesV3iOS` (generic iOS Simulator) both succeeded from the dirty
  working tree. They prove the host configuration compiles, but are explicitly
  not install, launch, provenance, or provider-interaction acceptance. The
  current iOS and macOS `-showBuildSettings` output resolves app ID
  `0fd66535-c296-4d76-9324-a6b7fe51d95e`, the expected platform bundle IDs,
  and the new entitlement files; the disposable products predate that local
  app-ID switch and still contain the old app ID, so they must not be deployed.
- A permanent account-owned Instant app titled `Instant Recipes V3` was
  created at app ID `0fd66535-c296-4d76-9324-a6b7fe51d95e`. Its aggregate
  Recipes schema and permissions are deployed; read-only CLI verification shows
  an empty guest-visible Todos/Boards query, Google development client
  `google`, native Apple clients `apple` (iOS bundle ID) and `apple-mac`
  (macOS bundle ID), and authorized origin `instant-recipes-v3://`. The admin
  token is private at
  `../private/credentials/swift-instant-data/recipes-v3-owned.env`; the ignored
  `Examples/RecipesV3/RecipesV3.local.xcconfig` now embeds the public app ID
  and local Apple development-team identifier needed for a signed physical
  build.
- No deployable acceptance build exists yet. Concurrent uncommitted
  acknowledgement/rollback work still owns
  `InstantRuntime.swift`, `InstantMessage.swift`, `Outbox.swift`, and
  related tests. Per clean-build policy, do not install or call Recipes auth
  verified until those files and this Recipes slice are reviewed and committed,
  the real checkout is clean, and fresh Mac/iPhone/iPad builds are relaunched
  and exercised through guest creation, Apple, Google, and guest promotion.

## 2026-08-02 15:15:35 EDT — Server-acknowledged typed messages (uncommitted review checkpoint)

- A task-owned library slice adds
  `InstantSwiftDataClient.sendAwaitingServerAcceptance`, which prepares once,
  registers the transaction lifecycle before the optimistic transaction, and
  returns its typed change only after `serverAccepted`. Runtime-less clients
  fail before transacting; timeout and cancellation leave the pending mutation
  durable.
- `InstantMessageFailureDisposition` makes server rejection explicit:
  `.retainForRetry` preserves the failed outbox row, while `.discard` removes
  only that failed mutation after the caller handles it. The package-scoped
  runtime removal is SQLite revision-checked, updates the in-memory outbox,
  survives relaunch, heals connection status only after the last failure is
  gone, and never emits a synthetic acceptance lifecycle event.
- This is an explicit Swift adaptation of
  `upstream/instant/client/packages/core/src/Reactor.js`:
  `_handleMutationError` deletes the rejected pending mutation immediately,
  whereas Swift retains diagnostic/retry state by default and deletes only on
  the typed caller's `.discard`. Reconnect proof confirms a discarded
  `permission denied` row cannot be automatically retried by the existing
  deployment-fix retry path.
- `waitForAllPendingMutations` now inspects retained failed rows before
  returning; a failed mutation throws its exact failure message and mutation
  ID instead of looking like completed delivery merely because it is no longer
  `.pending`.
- Verification at this checkpoint: 14/14 tests pass in
  `InstantFailedMutationDiscardTests`,
  `InstantMessageServerAcceptanceTests`, and `MutationDeliveryTests`; 12/12
  existing lifecycle/recording-message tests pass in
  `InstantMutationLifecycleTests`, `V3RecordingActionFixtureTests`, and
  `V3RecordingsListFixtureTests`. Strict Swift format lint passes for the two
  new test files, the touched delivery test, and `InstantMessage.swift`;
  `git diff --check` passes. The much larger pre-existing runtime/outbox/client
  files still report unrelated baseline format findings outside this diff.
- The existing
  `observeConnectionStatusPublishesRuntimeStatusChanges` regression passes
  1/1. The separate legacy
  `runtimeLiveMutationErrorPersistsFailureAndRetryResends` selector builds but
  produced no test-runner output and was stopped after a bounded wait; it is not
  counted as passing evidence and should be rerun independently during review.
- Ownership/handoff: these seven source/test paths plus this checkpoint are
  intentionally uncommitted for the coordinating agent's review. Re-run:
  `swift test --filter 'InstantFailedMutationDiscardTests|InstantMessageServerAcceptanceTests|MutationDeliveryTests'`,
  then
  `swift test --filter 'InstantMutationLifecycleTests|V3RecordingActionFixtureTests|V3RecordingsListFixtureTests'`.

## 2026-08-02 — Native provider auth and atomic guest promotion

- The reviewed auth slice adds native Sign in with Apple token exchange with a
  raw/hashed nonce pair, callback-safe OAuth with state and PKCE, Google/GitHub/
  enterprise provider configuration, and explicit actionable configuration
  failures instead of guessing a browser fallback.
- Guest promotion is atomic across the provider exchange and exact persisted
  guest-session compare-and-swap. Cancellation before exchange remains
  cancellable; after a successful non-idempotent exchange, the returned server
  state is committed only when the exact guest still owns local auth. A
  divergence fails loudly and records that the provider credential may already
  have been consumed.
- `InstantSwiftDataClient` exposes injectable ID-token and OAuth promotion
  operations, so reducers, previews, and deterministic tests use the same
  public dependency seam as the live runtime. Legacy provider convenience
  properties remain source-compatible under deprecation.
- Independent review is green after fixing late singleton callbacks, missing
  callback URLs, pre-state OAuth error trust, cancellation-after-success, the
  injectable value-client seam, compatibility properties, and a false-pass
  fixture. `swift test --filter Auth` passes 62 tests across 13 suites; focused
  promotion/provider/UI coverage passes as part of that gate.
- This is library and test acceptance only. A clean Scribe build still must
  complete Apple, Google, guest-to-new-identity, and linked-existing-user flows
  on physical iPhone, physical iPad, and Mac with before/after Instant evidence.

## 2026-08-02 — Scribe recovery continuation

- Implementation `e87765b8cd8c5c2830494ee05c9686f7edb9f4d4` prevents a
  deep persisted outbox from starving reconnecting live queries: query
  registration now precedes mutation replay, and replay uses a reentrancy-safe,
  acknowledgement-driven window capped at 50 mutations / 256 low-level steps.
  Focused outbox tests pass 6/6; the library ledger is `14c18af9`.
- A Sol worker currently owns only `SQLitePersistenceStore.swift`,
  `InstantStartupTraceTests.swift`, and its explicitly added benchmark-profiler
  files. It is profiling copies of the backed-up physical iPhone/iPad SQLite
  stores, adding a deterministic red gate, and targeting local startup/list
  readiness under 200 ms or the closest evidence-backed bound.
- Scribe's device backup counts, physical launch/memory evidence, simulator
  real-audio E2E contract, worker ownership, and exact restart order live in
  `/Users/laptop/Sync/tools/realtime-voice-sqlite-instant/handoffs/2026-08-02-sync-startup-and-e2e.md`.
- Because premium-model access is limited, every subsequent verified slice
  must leave immutable SHAs, test/benchmark output, blockers, and exact next
  steps here and in the applicable ledgers before another workstream begins.

## 2026-08-01 — Scribe production-readiness driver

- Scribe (the library's flagship consumer) reports defects that implicate the
  app↔library seam: recording list stuck loading forever on Mac while data
  exists locally in SQLite, infinite-query paging that never completes,
  word-count projections rendering 0, and a noticeable spinner when opening a
  local recording. Root causes may land on either side of the ADR-0001
  boundary; library-side fixes will be documented here and in CHANGELOG.md.
- Planned validation ground (workstream E of the plan): first-class
  `Examples/RecipesV3` recipes that continuously prove the quirky behaviors —
  a latency recipe (message bursts at adjustable rate carrying
  `publishedAtMs`/per-device `receivedAtMs`, live round-trip latency display)
  and a large-list recipe (continuous appends, streaming loads, paging that
  never wedges). Library bugs fixed under the Scribe push each get recipe or
  `validation/` coverage.
- A dedicated test InstantDB app now exists for cross-device E2E and latency
  work (credentials in Scribe's `.env.test`); the suite adds an Instant-room
  presence-based semaphore so concurrent runners serialize against the shared
  test database.
