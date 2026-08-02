# InstantSwiftData progress log

Newest-first. This log tracks library-side work driven by the Scribe
production-readiness plan
(`/Users/laptop/Sync/tools/realtime-voice-sqlite-instant/docs/production-readiness-plan.md`).
Commit-level history stays in `docs/audits/commit-changelog.md`; this file is
the narrative of what the library must prove and why.

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
