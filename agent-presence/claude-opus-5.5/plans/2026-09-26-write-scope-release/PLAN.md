# Write scope and v1.6.0 release plan

- **planId:** `2026-09-26-write-scope-release`
- **agentId:** `claude-opus-5.5`
- **Role:** mower — shrink per-write work from "every fact on the entity" to "the facts the write touches"; no new public surface.
- **Started:** 2026-09-26 (implementation drafted on `agent/claude-opus-5.5/scribe-perf-2026-09-24`; this plan lands before it on `main`).
- **Instant issues:** #044 (Scribe memory/CPU growth while recording), #155 (library fundamentals).
- **User order (2026-09-26):** fix whole-entity rollback copying; merge the library; publish a new minor version.

## Outcome

A write to an entity with many facts (Scribe: one `recordings/segments` link per segment) costs what it touches. Rollback capture, `changedEntityTriples`, and SQLite persistence become per fact; a local write stops materializing the whole store when no share can refuse it. Publish as `v1.6.0` with release notes.

## Steps

1. Record touched facts per entity (`InstantFactScope`) while preparing a mutation; capture rollback state per fact.
2. Scope SQLite reads and rewrites to those facts; union scopes when server apply and failure removal compose commits.
3. Mutate multi-value slots in place instead of copying them.
4. Gate the shared-root authorization snapshot on the existence of an active share.
5. Document that nested include limits trim locally only (the server paginates top level only).
6. Guard with absolute-bound tests; run the release gate; publish `v1.6.0`.

## Touching

Claims appended under `_touching/` for: `CHANGELOG.md`, `PROGRESS.md`, `Sources/InstantSwiftData/InstantSwiftData.swift`, `Sources/InstantSwiftData/InstantTypedAPI.swift`, `Sources/InstantSwiftDataCore/InstantFactScope.swift` (new), `Sources/InstantSwiftDataCore/InstantParityCoverage.swift`, `Sources/InstantSwiftDataCore/InstantRuntime.swift`, `Sources/InstantSwiftDataCore/InstantStore.swift`, `Sources/InstantSwiftDataCore/SQLitePersistenceStore.swift`, `Sources/InstantSwiftDataCore/TripleIndexes.swift`, `Tests/InstantSwiftDataCoreTests/InstantEntityWriteScopeTests.swift` (new), `Tests/InstantSwiftDataCoreTests/InstantStoreParityTests.swift`, `docs/adr/0015-sqlite-data-parity-ergonomics/qanda.md`, `docs/audits/commit-changelog.md`, `docs/releases/v1.6.0.md` (new).

## Conflict check

Every earlier claim on these paths dates from 2026-08-09 to 2026-08-22, and that work is on `main`. The main checkout's `autoresearch/2026-08-12-live-put-observation-memory` branch (`grok-4.6-live-revision`) holds uncommitted documentation edits only and none of these source files. Channel: `agent-presence/_channels/2026-09-26-write-scope-release.md`.
