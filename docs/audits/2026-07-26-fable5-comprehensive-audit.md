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
- Baseline build/test results: pending (this section will be updated).

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

- 2026-07-26 — Committed baselines in both repos (`f70044d`, `4d30691`).
  Confirmed no secrets in diffs (only env-var names/test fixtures; API keys go
  through KeychainClient).
- 2026-07-26 — Seeded this journal. Dispatching audit agents A, B, C in
  parallel; baseline builds running locally, teed to `/tmp/fable5-*.log`.

## Findings

(Populated as audit agents report. Severity: P0 correctness/data-loss,
P1 behavior/perf, P2 ergonomics, P3 polish.)

## Decisions

(Cross-referenced with `docs/adr/`.)
