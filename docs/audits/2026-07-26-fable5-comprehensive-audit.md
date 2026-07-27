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
| R-B1 | P1 | Open | Room registration is not observer-reference-counted; one consumer leaving can unregister a room still used by another and freeze presence. |
| R-A1 | P1 | Open | Pending mutations created in the same millisecond are tie-broken by random UUID, so replay/rebase order can invert. |
| R-A2 | P1 | Open | One mutation with an unresolvable attribute aborts the delivery loop and can poison every reconnect. |
| R-A3 | P1 | Open | One rejected `add-query` can tear down the shared socket instead of failing only its observation. |
| R-A4 | P1 | Open | Failed optimistic cardinality-one writes or deletes can leave holes until a server refresh because rollback removes failed triples without restoring overwritten server triples. |
| S-C2/C11 | P1 | Open | Every interim transcript can trigger full projection, diffing, persistence, and full joined-text rewriting, creating out-of-order saves and roughly quadratic cumulative work. |
| S-C3/C4 | P1 | Open | Commits re-materialize unrelated observers, while infinite observations remove limits before client-side windowing. |
| S-C5 | P1 | Open | Live one-shot queries can wait ten seconds and fail despite valid local state; the fix must preserve ordinary query APIs or use an injected local-only client, never public `queryLocal`. |
| S-C6/C7 | P1/P2 | Open | Microphone PCM and Watch relay timing collections need explicit bounds and drop diagnostics. |
| R-A8 | P2 | Open | Global triples and per-query tracking lack a complete garbage-collection policy. |
| API-B1/B2/B3 | P2 | Proposed | Generate or centralize entity snapshot decoding and whole-model upserts to remove repeated stringly application boilerplate. |
| API-B5/B6/B7 | P2 | Proposed | Complete dynamic fetch parity and expose library-owned decoded/composite observation for TCA and actor consumers. |
| API-B8/B10/B13 | P2 | Proposed | Add dependency-controlled IDs, faceted clients, DocC, and unified fetch status without broadening the application/library sync boundary. |

## Decisions

(Cross-referenced with `docs/adr/`.)
