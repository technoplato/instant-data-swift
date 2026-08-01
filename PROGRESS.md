# InstantSwiftData progress log

Newest-first. This log tracks library-side work driven by the Scribe
production-readiness plan
(`/Users/laptop/Sync/tools/realtime-voice-sqlite-instant/docs/production-readiness-plan.md`).
Commit-level history stays in `docs/audits/commit-changelog.md`; this file is
the narrative of what the library must prove and why.

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
