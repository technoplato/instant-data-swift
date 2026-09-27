# Performance and concurrency audit, library side (#250)

- **planId:** `2026-09-26-perf-concurrency-audit` · **agentId:** `claude-opus-5.5` (fork D) · **Role:** mower
- **Issues:** #250 (this audit), #155. **User order (2026-09-26):** "please do a complete audit on this entire applications structure as well as the library ... set that up so we can continue to evolve the performance".

## Outcome

Measured CPU/concurrency costs ranked; top safe wins land with before/after numbers from thread CPU time and ABBA runs against v1.6.0.

## Steps

1. Live refresh: resolve the schema once per refresh, not once per query result; make an empty attribute merge a no-op; reuse the translator's attribute store while the attribute revision is unchanged.
2. Persisted live-query results: sort without copying values into strings per comparison.
3. Hot-path diagnostics: measure the cost of per-refresh info-level events; demote only what the profile shows to be hot. Retention and rotation of diagnostic files stay with the memory/diagnostics workstream (fork A).

## Touching

`TripleIndexes.swift`, `InstantLiveRefreshApplication.swift`, `InstantRuntime.swift`, `InstantInfiniteQueryDiagnostics.swift`, three new cost tests, `CHANGELOG.md`, `PROGRESS.md`, `docs/audits/commit-changelog.md`.

## Conflict check

Last claims on these files are from 2026-08-09..09-26 and landed on `main`. No other fork claims library files today.
