# InstantSwiftData progress log

Newest-first. This log tracks library-side work driven by the Scribe
production-readiness plan
(`/Users/laptop/Sync/tools/realtime-voice-sqlite-instant/docs/production-readiness-plan.md`).
Commit-level history stays in `docs/audits/commit-changelog.md`; this file is
the narrative of what the library must prove and why.

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
