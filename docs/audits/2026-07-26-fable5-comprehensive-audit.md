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

- `instant-data-swift` baseline commit: `f70044d` — feat: add startup tracing
  and harden storage runtime
- `realtime-voice-sqlite-instant` baseline commit: `4d30691` — feat: checkpoint
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
  iOS, Scribe commit `4d30691`; they are useful baseline evidence but are too
  old to validate today's Watch relay or `main` behavior.
- 2026-07-27 — Closed the remaining off-main pasteboard crash seam in Scribe.
  Commit `7f4ce7e` makes `ClipboardClient.currentContent` async, performs live
  reads through `MainActor.run`, and adds a focused compile-enforced test.
- 2026-07-27 — Wired persisted query-cache pruning into the production
  one-shot materialization path in `c0a0304`. Active observation keys and the
  completing query remain protected; unloaded rows are bounded by the
  Reactor-compatible age, entry-count, and adapted encoded-size policy.
  `0ba57bd` moved the scan to bootstrap plus every 64 successful writes so
  ordinary one-shot reads retain their prior actor-hop contract; `91578fe`
  corrected the deterministic relaunch fixture to the measured 11 hops.
- 2026-07-27 — Scoped store observer invalidation by namespace in `da5010d`.
  Flat query plans no longer re-materialize for clearly unrelated commits;
  relationship includes and paths, schema changes, and unresolved entities
  retain conservative invalidation.
- 2026-07-27 — Routed Scribe's explicitly local projection reads through an
  injected local-only Instant client in `21be1b8`. The live and local clients
  share one resolved SQLite file, preserving the strict public one-shot API
  while removing server-acknowledgement waits from startup and capture writes.
- 2026-07-27 — Replaced the need for a second local-only runtime with a
  read-only client facet in `760afdb`. Composition roots can now inject local
  reads and observations over the already bootstrapped runtime while ordinary
  live one-shot APIs retain their freshness contract.
- 2026-07-27 — Fixed the five highest-priority Reactor correctness gaps with
  focused parity tests: isolated rejected queries (`d7dd19d`), rebased later
  optimistic writes (`cabc467`), reference-counted room joins (`ac10cb3`),
  preserved same-millisecond mutation order (`ea1ca27`), and isolated malformed
  outbox rows (`0bda5d5`).
- 2026-07-27 — Bounded both unbounded live-audio collections. Microphone
  buffering retains the newest 256 buffers and diagnoses drops (`e12be12`);
  Watch relay correlation retains the newest 4,096 timings without falsely
  attributing evicted audio (`1d8db69`).
- 2026-07-27 — Reduced cumulative transcript work in Scribe. Live projection
  no longer rewrites complete joined text (`fa2210b`), finalization still
  persists the fallback transcript, and overlapping snapshot writes now run in
  submission order (`17c2d62`).
- 2026-07-27 — Hardened the Watch credential and observability path. The phone
  relay can restore and persist validated Deepgram credentials without making
  remote logging a prerequisite (`d3969e7`); the standalone Watch probe embeds
  clean-build provenance (`e15d6f9`); and relay diagnostics use the logger
  configured during Instant bootstrap (`2f9d947`). The Watch recorder now also
  authorizes long-form audio streaming before opening Deepgram and treats
  constrained or expensive socket failures as immediate evidence (`bb6ca86`).
- 2026-07-27 — Completed the revised ReplayKit code scope. Scribe already
  embeds `RPSystemBroadcastPickerView` from `a888ec9`; `62157d2` now correlates
  transcript attribution to the audio-frame source span and uses the exact
  `System Audio` fallback when application metadata is unavailable.
- 2026-07-26 — Committed baselines in both repos (`f70044d`, `4d30691`).
  Confirmed no secrets in diffs (only env-var names/test fixtures; API keys go
  through KeychainClient).
- 2026-07-26 — Seeded this journal. Dispatching audit agents A, B, C in
  parallel; baseline builds running locally, teed to `/tmp/fable5-*.log`.

## Findings

Severity: P0 correctness/data-loss, P1 behavior/perf, P2 ergonomics, P3 polish.

| ID | Severity | Status | Finding |
| --- | --- | --- | --- |
| S-C1 | P0 | Fixed `7f4ce7e` | `bugs/crash1.txt` proves AppKit pasteboard access crashed off-main; `currentContent` was the last synchronous live entry point. |
| R-B1 | P1 | Fixed `ac10cb3` | Room registrations are reference-counted; only the final local observer sends `leave-room`. |
| R-A1 | P1 | Fixed `ea1ca27` | Implicit mutation timestamps advance monotonically above the newest durable outbox row, preserving insertion order across relaunch. |
| R-A2 | P1 | Fixed `0bda5d5` | Attribute-resolution failures are persisted per mutation while the delivery loop continues with later healthy rows. |
| R-A3 | P1 | Fixed `d7dd19d` | A rejected `add-query` retires only the correlated registration and leaves the shared socket and healthy observations intact. |
| R-A4 | P1 | Fixed `cabc467` | Remaining optimistic mutations are rebased above the authoritative server snapshot so later local writes stay visible. |
| S-C2/C11 | P1 | Fixed `fa2210b`, `17c2d62` | Live projection omits cumulative joined-text rewrites, finalization writes the fallback text once, and snapshot mutations are serialized in submission order. |
| S-C3/C4 | P1 | Partial `da5010d` | Commits now skip flat observers in untouched namespaces while relationship-dependent plans remain conservative; infinite-query windowing still needs separate review. |
| S-C5 | P1 | Fixed `21be1b8` | Scribe's local startup and capture projection loaders now use an injected local-only client over the shared SQLite file; live one-shot queries remain freshness-sensitive and no public `queryLocal` was added. |
| S-C6/C7 | P1/P2 | Fixed `e12be12`, `1d8db69` | Microphone PCM retains 256 newest buffers with drop diagnostics; Watch relay timing uses a 4,096-entry circular buffer and refuses false attribution after eviction. |
| R-A8 | P2 | Partial `c0a0304`, `0ba57bd` | Persisted per-query results are pruned at bootstrap and every 64 successful writes while active observations remain protected; global triple retention still needs a separate reachability policy. |
| API-B1/B2/B3 | P2 | Partial `7ec460a` | Typed schema-owned snapshot decoding now removes string keys for cardinality-one values; macro-generated whole-model upserts remain a separate ergonomic follow-up. |
| API-B5/B6/B7 | P2 | Proposed | Complete dynamic fetch parity and expose library-owned decoded/composite observation for TCA and actor consumers. |
| API-B8/B10/B13 | P2 | Partial `d3e6e70`, `760afdb` | Dependency-controlled typed IDs and a read-only local client facet are implemented with ADRs; broader DocC and unified fetch-status work remain. |

## Acceptance boundaries and retained follow-ups

- **Infinite query transport windowing:** still open within `S-C3/C4`.
  Namespace-scoped invalidation removes unrelated re-materialization, but the
  Swift infinite-query observer still subscribes to an unbounded namespace and
  applies its visible window locally. Correct upstream-style forward/reverse
  cursor subscriptions require a dedicated behavioral port; this audit does
  not disguise that work with a larger arbitrary limit.
- **Global triple reachability:** still open within `R-A8`. Persisted per-query
  cache rows now have production retention, but deleting triples that are no
  longer reachable from any active or cached query needs a separate ownership
  and offline-retention policy.
- **Ergonomic breadth:** typed snapshot values, dependency-controlled IDs, and
  the local-reader facet are accepted, ADR-backed increments. Whole-model
  upserts, the remaining dynamic/composite fetch surface, broader DocC, and a
  unified fetch status remain proposed rather than being claimed complete.
- **Device evidence:** Watch credential recovery, relay timing, diagnostic
  logger handoff, streaming authorization, Watch-probe provenance, ReplayKit
  source correlation, the clear fallback label, and the embedded broadcast
  picker are covered by focused tests. A physical paired-Watch
  recording/transcription run and an iPhone ReplayKit broadcast remain device
  acceptance work; package tests alone are not presented as proof of those
  physical paths.

## Decisions

(Cross-referenced with `docs/adr/`.)
