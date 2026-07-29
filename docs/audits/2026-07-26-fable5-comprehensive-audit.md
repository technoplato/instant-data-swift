# Fable 5 Comprehensive Audit — 2026-07-26

Working journal for the full-stack audit of `instant-data-swift` (the Instant
TypeScript → Swift port) and its flagship consumer
`realtime-voice-sqlite-instant` (Scribe). Maintained by the coordinating agent;
appended to as work proceeds. Findings are evidence-first: runtime logs and
persisted artifacts outrank code reading whenever they disagree.

## Ground rules (from the user, 2026-07-26)

- Breaking API changes are allowed when ergonomics clearly improve; update the
  app + examples + tests in the same pass.
- `INSTANT_DATA_API_DESIGN_PREFERENCES_V3.md` is canonical, but reviewer
  attention faded partway through; agents may go beyond it when an API reduces
  boilerplate — every such change needs a documented before/after + reasoning
  in `docs/adr/`.
- Platforms: verify Apple platforms now; keep the code Linux-clean (no
  unguarded OSLog/ObjC/URLSession assumptions). No Linux CI run this pass.
- Verification: targeted tests per fix, one commit per fix; full suites at the
  end.
- Live validation: use https://getadb.com to mint ephemeral Instant
  credentials; cache creds + usage in a local file. Ephemeral — spin up at
  will.
- Presence bug (PresenceRecipesV3): peers that leave are never dismissed.
  Low priority relative to the voice app, but should be fixed.
- Document thinking/changes/progress extensively (this file). Extend and use
  the logging infrastructure; read logs as source of truth vs. trusting code
  understanding.

## Baseline

- `instant-data-swift` baseline commit: `a9abe9d` — feat: add startup tracing
  and harden storage runtime
- `realtime-voice-sqlite-instant` baseline commit: `9d65fbb` — feat: checkpoint
  watch companion speech relay and diagnostics
- Fresh Scribe baseline on local `main`: 423 tests in 45 suites passed on
  2026-07-27 before the first new fix.
- Fresh `instant-data-swift` baseline: 1,184 tests ran, but the incremental
  build reported 121 issues. The failures include process-level CLI tests
  rejecting a stale executable and a benchmark binary asserting the previous
  11/5 actor-hop contract even though current source asserts 12/6. A clean
  scratch-path rerun is in progress before any product code or expectations
  change.

## Logging / evidence inventory

| Source | Where | Notes |
| --- | --- | --- |
| InstantDBLogger | app `Sources/InstantDBLogger/` | JSONL + ships `debugLogs` entities to a dedicated Instant logging app (`InstantLogging/instant.schema.ts`); redacts sensitive keys |
| Runtime logs | `/tmp/scribe-discrete.log`, `/tmp/scribe-continuous.log`, `/tmp/scribe-periodic.log` | canonical runtime evidence when enabled |
| Test/build logs | `/tmp/scribe-*-tests.log`, `/tmp/scribe-watch-*.log` | prior model's verification artifacts |
| Library diagnostics | `InstantDiagnostics` (env-configured), `InstantStartupTrace`, `InstantActorHopInstrumentation` | library-side tracing |
| Bug artifacts | app `bugs/crash1.txt`, `input/*` | user-filed evidence |
| Audit baseline logs (this pass) | `/tmp/fable5-*.log` | build/test output teed here |

## Workstreams

- **A — Reactor/core parity**: InstantSwiftDataCore vs
  `upstream/instant/client/packages/core` (Reactor, instaql, instaml,
  triple store, presence, offline persistence) + test-port coverage map.
- **B — API ergonomics**: public surface vs V3 doc, screens/, sqlite-data +
  sharing-instant prior art; TanStack Query/Mutation feel; boilerplate hunts in
  Examples/*V3 and the Scribe app.
- **C — Flagship app audit**: TCA integration incompatibilities, memory,
  performance, obvious bugs in realtime-voice-sqlite-instant.
- **D — Fixes**: dispatched per triaged finding; one commit per fix.
- **E — Live validation**: getadb.com ephemeral app; presence + realtime
  transcript flows against a real backend.

## Progress log

- 2026-07-27 at 2:13:24 PM EDT — Repeated the final physical acceptance gate
  from clean Scribe commit `fe1fe820bd04f855042c00acf4ca40a641b8473e`
  with embedded `dirty=false` provenance generated at 2:03:47 PM EDT. The
  paired Series 9 reported Developer Mode enabled, DDI services available, and
  a connected tunnel. A serialized physical `ScribeSharedWatch` build compiled
  the iOS app, iOS widget, ReplayKit broadcast upload extension, Watch app, and
  Watch widget and resolved their development provisioning profiles. All five
  products then failed exclusively at private-key use with
  `errSecInternalComponent`; `security show-keychain-info` independently
  reported `User interaction is not allowed`. The protected Instant observer's
  newest 200 rows ended at 9:43:00 AM EDT on older clean commit `82d3c48` and
  contained zero rows from `fe1fe82`, so there is no current-head remote runtime
  evidence to substitute for installation. No current-head bundle was signed,
  installed, launched, or exercised.
- 2026-07-27 — Closed deterministic short-lived writer data loss in
  `27b6534` and adopted the boundary in Scribe `864f541`. The default injected
  flush transport is local, so the former Scribe waiter could confirm and
  remove durable outbox rows before the background WebSocket opened. The new
  `waitForAllPendingMutations` observes actual live acknowledgements without
  invoking that transport, reconnects closed sessions, and fails on timeout or
  live connection error. Ordered replay also retains an older scalar write
  while a queued successor writes the same entity/attribute, preserving valid
  initial upserts without permitting isolated stale retries. `9814279` gates
  the Duration-based API to macOS 13, iOS 16, tvOS 16, and watchOS 9 so the
  package still compiles for iOS 15 and watchOS 8. Final verification passed:
  Instant ran 28 macro XCTest tests plus 1,220 Swift Testing tests in 103
  suites, and Scribe ran 471 tests in 48 suites.
- 2026-07-27 — Rebuilt the Scribe CLI from clean commit
  `fe1fe820bd04f855042c00acf4ca40a641b8473e` with embedded `dirty=false`
  provenance, local/ISO build time, host, source root, configuration,
  architecture, and resolved artifact path. The sanitized live report
  `.perf-runs/2026-07-27T17-44-46-324Z/report.json` completed all six configured
  TypeScript/Swift writer-observer lanes with 5/5 rows and no failures. Average
  latency ranged from 165 ms to 1,530 ms and maximum latency from 234 ms to
  1,743 ms, within the two-second budget. Swift short-run resource gates
  passed; Node lanes showed 47–52 MiB launch growth and exceeded the 32 MiB
  short-run growth threshold. That launch sample is not a sustained leak or
  day-scale slope measurement.
- 2026-07-27 — Rechecked the current physical Watch build boundary after the
  keychain identity became discoverable. A serialized, no-sign physical
  `ScribeSharedWatch` scheme build completed for the clean Scribe/Instant code
  after the availability fix. The corresponding reproducible signed build
  reached code signing but every application/extension failed private-key use
  with `errSecInternalComponent`. No new current-head bundle was installed or
  launched, and no production spoken recording was started; private-key
  authorization remains a user-controlled prerequisite.
- 2026-07-27 — Closed durable live-query reachability in `6386abc`.
  Canonical Reactor query results now use the upstream 52-week, 1,000-entry,
  and 1,000,000-owned-triple bounds at bootstrap and every 64 successful live
  writes. Active registrations and optimistic mutation baselines remain
  protected; final observer cancellation unloads the in-memory result; and a
  single SQLite transaction removes unloaded ownership plus only global
  triples whose final entity/attribute/value owner disappeared. The focused
  retention regressions and the complete 439-test store, live-transport, store
  parity, and Reactor parity selection pass. ADR 0009 records the collection
  and semantic-identity boundary, closing R-A8.
- 2026-07-27 — Persisted authoritative live-query ownership in `cb1b721`.
  Canonical query results and page information now update atomically with the
  global store, outbox reconciliation, and processed server checkpoint. A
  relaunched runtime retracts rows removed by a replacement, while the
  normalized ownership index preserves triples still held by another durable
  query without preloading the retained corpus. All 57 live-transport tests
  pass, including focused relaunch, shared-owner, and persisted-cursor cases.
  ADR 0008 records the crash-consistency boundary; bounded retention and
  orphan-only collection remain the next R-A8 slice.
- 2026-07-27 — Closed live infinite-query transport windowing in `c5667b4`.
  The live runtime now registers only a limited starter, limited forward and
  reverse chunks, or frozen inclusive cursor intervals; forward paging and
  automatic reverse advancement replace subscriptions without leaving broad
  namespace queries behind. Matching server page info is installed on the
  store observer before its refresh emission, while locally persisted starter
  rows remain immediately visible. All 17 infinite-query tests, 55 live
  transport tests, and 27 Reactor parity tests pass. The 330-test store/CLI run
  passed the affected remote-page-window case; its two unrelated empty-stderr
  CLI flakes passed when rerun individually. ADR 0007 records the accepted
  coordinator and R-A8 ownership boundary.
- 2026-07-27 — Preserved canonical live query pagination metadata in
  `2c2117a`. Per-namespace server page info and opaque four-value cursors now
  survive refresh translation, per-query state, Codable persistence, one-shot
  materialization, and exact `after`/`before` re-encoding, including inclusive
  options. Hand-built local cursors still fail live encoding with the existing
  actionable error. The complete 55-test live transport suite and the focused
  remote-page-window regression passed. ADR 0006 records the accepted private
  wire-state design and before/after syntax. This closes the cursor
  prerequisite; bounded forward/reverse infinite-query subscriptions remain
  the next port.
- 2026-07-27 — Exposed direct composite request execution in `c429e81`.
  `InstantFetchRequest.load` and `subscribe` now let actors and TCA effects use
  the same library-owned multi-query transformation, combination, and
  cancellation path as `@Fetch`; ADR 0005 records the accepted before/after
  syntax. Both focused red/green tests and all 140 `TypedAPITests` passed.
- 2026-07-27 — Fast-forwarded both local `main` branches after creating
  timestamped backup branches. Added cross-repository commit discipline and a
  newest-first SHA journal. Both worktrees were clean before new fixes.
- 2026-07-27 — Recovered and read the full OpenCode export
  `realtime-voice-sqlite-instant/session-ses_05fd.md`. The original Reactor,
  API ergonomics, and Scribe performance agents returned substantive reports;
  the original Watch and ReplayKit agents returned empty results and were
  relaunched.
- 2026-07-27 — Queried the newest 200 remote Instant diagnostic rows through
  the protected observer. They cover only 2026-07-26 20:08:51–20:09:58 EDT,
  iOS, Scribe commit `9d65fbb`; they are useful baseline evidence but are too
  old to validate today's Watch relay or `main` behavior.
- 2026-07-27 — Closed the remaining off-main pasteboard crash seam in Scribe.
  Commit `386a9b4` makes `ClipboardClient.currentContent` async, performs live
  reads through `MainActor.run`, and adds a focused compile-enforced test.
- 2026-07-27 — Wired persisted query-cache pruning into the production
  one-shot materialization path in `a488b43`. Active observation keys and the
  completing query remain protected; unloaded rows are bounded by the
  Reactor-compatible age, entry-count, and adapted encoded-size policy.
  `d1066e8` moved the scan to bootstrap plus every 64 successful writes so
  ordinary one-shot reads retain their prior actor-hop contract; `0a1129f`
  corrected the deterministic relaunch fixture to the measured 11 hops.
- 2026-07-27 — Scoped store observer invalidation by namespace in `b812a2c`.
  Flat query plans no longer re-materialize for clearly unrelated commits;
  relationship includes and paths, schema changes, and unresolved entities
  retain conservative invalidation.
- 2026-07-27 — Routed Scribe's explicitly local projection reads through an
  injected local-only Instant client in `94cd84a`. The live and local clients
  share one resolved SQLite file, preserving the strict public one-shot API
  while removing server-acknowledgement waits from startup and capture writes.
- 2026-07-27 — Replaced the need for a second local-only runtime with a
  read-only client facet in `96cc068`. Composition roots can now inject local
  reads and observations over the already bootstrapped runtime while ordinary
  live one-shot APIs retain their freshness contract; Scribe adopted that
  single-runtime composition in `ee8a81d`.
- 2026-07-27 — Fixed the five highest-priority Reactor correctness gaps with
  focused parity tests: isolated rejected queries (`3a0c2c5`), rebased later
  optimistic writes (`8f43f3f`), reference-counted room joins (`fdd4c1e`),
  preserved same-millisecond mutation order (`43b65ee`), and isolated malformed
  outbox rows (`657a74a`).
- 2026-07-27 — Bounded both unbounded live-audio collections. Microphone
  buffering retains the newest 256 buffers and diagnoses drops (`95c4b31`);
  Watch relay correlation retains the newest 4,096 timings without falsely
  attributing evicted audio (`0d107b4`).
- 2026-07-27 — Reduced cumulative transcript work in Scribe. Live projection
  no longer rewrites complete joined text (`a43a126`), finalization still
  persists the fallback transcript, and overlapping snapshot writes now run in
  submission order (`84c4162`).
- 2026-07-27 — Hardened the Watch credential and observability path. The phone
  relay can restore and persist validated Deepgram credentials without making
  remote logging a prerequisite (`4f6c9a9`); the standalone Watch probe embeds
  clean-build provenance (`02f8a08`); and relay diagnostics use the logger
  configured during Instant bootstrap (`09e1c4c`). The Watch recorder now also
  activates its recording session asynchronously before opening Deepgram,
  keeps the recording-compatible default route policy, and treats constrained
  or expensive socket failures as immediate evidence (`b7fc411`, `18d5493`).
  The eight-second auto-run window now begins only after capture, WAV append,
  and Deepgram streaming are active (`1c5500a`).
- 2026-07-27 — Ported the physically proven Watch audio policy into the
  production capture client (`ac50d0d`). Production now selects asynchronous
  watchOS activation, removes `.mixWithOthers`, and keeps the default
  microphone-compatible route; the existing TCA readiness gates still order
  capture activation, Deepgram connection/receiver readiness, and PCM delivery.
  Focused policy/transport tests, the 447-test package suite, a generic no-sign
  `ScribeSharedWatch` build, and a clean signing-enabled generic Watch build
  passed. The final signed bundle contains arm64/arm64_32 executables and passes
  strict deep code-sign verification; it has not been installed or launched.
- 2026-07-27 — Completed the revised ReplayKit code scope. Scribe already
  embeds `RPSystemBroadcastPickerView` from `a12ca89`; `4a30f63` now correlates
  transcript attribution to the audio-frame source span and uses the exact
  `System Audio` fallback when application metadata is unavailable.
- 2026-07-27 — Completed clean-head physical Watch transcription evidence. The
  signed `Scribe Audio Probe` built from clean Scribe commit `0197d9c`, embedded
  that full commit plus dirty=false and its local/ISO build time, installed on
  the paired Series 9, and launched successfully. The retained device-local log
  records one cancelled startup followed by a complete attempt: asynchronous
  default-route activation, 48 kHz mono PCM, 77 sent buffers / 739,200 sent
  bytes, a 739,244-byte local WAV, an open Deepgram socket, 14 provider
  messages, and a final speech-final transcript. The matching final-result
  latencies were 991 ms from PCM send and 2,649 ms from audio end. This proves
  the focused direct-capture diagnostic path, not a reliability soak or the
  production app's recording persistence and Instant projection.
- 2026-07-27 — Final package verification passed after stabilizing only
  asynchronous test evidence: Scribe ran 447 tests in 47 suites
  (`/tmp/fable5-scribe-full-final-6.log`), and Instant ran 1,193 tests in 102
  suites (`/tmp/fable5-instant-full-final-9.log`). The performance-safety suite
  also remained green at 10 tests (`/tmp/fable5-scribe-final-perf.log`), and two
  final sanitizer passes each inspected 19 artifacts without requiring a
  change (`/tmp/fable5-scribe-final-sanitize-{1,2}.log`).
- 2026-07-26 — Committed baselines in both repos (`a9abe9d`, `9d65fbb`).
  Confirmed no secrets in diffs (only env-var names/test fixtures; API keys go
  through KeychainClient).
- 2026-07-26 — Seeded this journal. Dispatching audit agents A, B, C in
  parallel; baseline builds running locally, teed to `/tmp/fable5-*.log`.

## Findings

Severity: P0 correctness/data-loss, P1 behavior/perf, P2 ergonomics, P3 polish.

| ID | Severity | Status | Finding |
| --- | --- | --- | --- |
| S-C1 | P0 | Fixed `386a9b4` | `bugs/crash1.txt` proves AppKit pasteboard access crashed off-main; `currentContent` was the last synchronous live entry point. |
| R-B1 | P1 | Fixed `fdd4c1e` | Room registrations are reference-counted; only the final local observer sends `leave-room`. |
| R-A1 | P1 | Fixed `43b65ee` | Implicit mutation timestamps advance monotonically above the newest durable outbox row, preserving insertion order across relaunch. |
| R-A2 | P1 | Fixed `657a74a` | Attribute-resolution failures are persisted per mutation while the delivery loop continues with later healthy rows. |
| R-A3 | P1 | Fixed `3a0c2c5` | A rejected `add-query` retires only the correlated registration and leaves the shared socket and healthy observations intact. |
| R-A4 | P1 | Fixed `8f43f3f` | Remaining optimistic mutations are rebased above the authoritative server snapshot so later local writes stay visible. |
| R-A9 | P0 | Fixed `27b6534`, `9814279` | Explicit durability waits observe live server acknowledgement without locally confirming the outbox; ordered replay preserves causally required earlier writes, and the API retains older-platform package compatibility. |
| S-C12 | P0 | Fixed `864f541` | Scribe logger and replay durability boundaries no longer invoke the local flush transport, preventing deterministic 0/5 and 3/5 remote row loss in short-lived writers. |
| S-C2/C11 | P1 | Fixed `a43a126`, `84c4162` | Live projection omits cumulative joined-text rewrites, finalization writes the fallback text once, and snapshot mutations are serialized in submission order. |
| S-C3/C4 | P1 | Fixed `b812a2c`, `2c2117a`, `c5667b4` | Commits skip flat observers in untouched namespaces, canonical server page info and opaque cursors survive the live path, and live infinite queries use limited or cursor-bounded forward/reverse subscriptions with atomic observer windows. |
| S-C5 | P1 | Fixed `94cd84a`, `96cc068`, `ee8a81d` | Scribe's local startup and capture projection loaders use a read-only facet of the already bootstrapped live runtime; live one-shot queries remain freshness-sensitive and no second SQLite runtime or public `queryLocal` was added. |
| S-C6/C7 | P1/P2 | Fixed `95c4b31`, `0d107b4` | Microphone PCM retains 256 newest buffers with drop diagnostics; Watch relay timing uses a 4,096-entry circular buffer and refuses false attribution after eviction. |
| R-A8 | P2 | Fixed `a488b43`, `d1066e8`, `cb1b721`, `6386abc` | Materialized query rows and authoritative live results have production retention. Durable normalized ownership preserves replacement correctness across relaunch and shared queries, protects active and optimistic baselines, and transactionally collects unloaded ownership plus only newly orphaned semantic triples. |
| API-B1/B2/B3 | P2 | Partial `870a408` | Typed schema-owned snapshot decoding now removes string keys for cardinality-one values; macro-generated whole-model upserts remain a separate ergonomic follow-up. |
| API-B5/B6/B7 | P2 | Partial `c429e81` | Dynamic `FetchOne` and composite `Fetch` replacement plus decoded subscriptions already exist; direct `InstantFetchRequest` load/subscription now exposes library-owned composite observation to TCA and actors. A general composite SwiftUI modifier remains intentionally separate because request keys are not globally `Hashable`. |
| API-B8/B10/B13 | P2 | Partial `e965771`, `96cc068` | Dependency-controlled typed IDs and a read-only local client facet are implemented with ADRs; broader DocC and unified fetch-status work remain. |

## Acceptance boundaries and retained follow-ups

- **Global triple reachability:** closed within `R-A8`. Durable normalized
  query ownership makes replacement and shared-owner decisions correct across
  relaunch; Reactor-aligned age, entry, and owned-triple bounds prune unloaded
  rows at bootstrap and on a bounded write cadence; and transactional
  semantic-identity collection protects active queries and optimistic writes
  while deleting only triples whose final owner disappeared.
- **Ergonomic breadth:** typed snapshot values, dependency-controlled IDs, the
  local-reader facet, and direct composite request execution are accepted,
  ADR-backed increments. Dynamic `FetchOne` and composite `Fetch` replacement
  already exist through their public `load`/`subscribe`/`task` operations.
  Whole-model upserts, a general composite SwiftUI modifier with explicit task
  identity, broader DocC, and a unified fetch status remain proposed rather
  than being claimed complete.
- **Cross-SDK live latency:** the final six-lane CLI/TypeScript matrix delivered
  every one of five rows in every configured lane inside two seconds. The
  macOS-app and iOS-simulator placeholders remain honestly `not_run` because
  those hosts do not yet expose a headless benchmark role. Short Node launch
  growth above 32 MiB remains a resource follow-up; it is not evidence of a
  sustained leak without a longer soak.
- **Device evidence:** Watch credential recovery, relay timing, diagnostic
  logger handoff, production asynchronous recording activation, the
  recording-compatible audio policy, Watch-probe provenance/timestamp,
  ReplayKit source correlation, the clear fallback label, and the embedded
  broadcast picker are covered by focused tests. The final clean Watch probe
  also built, installed, launched, and completed local PCM/WAV capture plus a
  final Deepgram transcript on the physical paired Series 9. The post-port
  production `ScribeSharedWatch` target now compiles, signs, installs, launches,
  and settles its UI on that Watch, but no production spoken recording was
  started. Production capture/transcript/save, Instant projection/media
  delivery, repeated Watch cold-start reliability, and an iPhone ReplayKit
  broadcast remain device acceptance work. That install/launch evidence belongs
  to the earlier clean production checkpoint. The latest Scribe/Instant heads
  compile for the physical target without signing, but their new signed build
  is blocked at private-key authorization with `errSecInternalComponent`; no
  current-head install or launch is claimed.

## Decisions

(Cross-referenced with `docs/adr/`.)
