# Plan 2026-08-12-live-revision-cardinality

- `planId`: `2026-08-12-live-revision-cardinality`
- `agentId`: `grok-4.6-live-revision`
- `role`: `mower`
- `issues`: [#044](https://issues.knophy.com/issues/044), [#155](https://issues.knophy.com/issues/155)
- `outcome`: Prove that Instant Swift Data rematerializes the full in-memory namespace on every same-entity live put, then change observation and persistence so 10,000 speech revisions of one segment stay one live row, send every revision on the wire, and prune the operation journal after ack.

## User invariant (do not weaken)

Do not reduce, debounce, or coalesce the live synchronization path. Every recognizer revision is accepted immediately and a connected peer can receive every ordered revision. Transient partials must not become permanent domain history.

## Why this is library-owned

SQLite Data observes a `FetchKeyRequest` that runs SQL against SQLite and invalidates by table. Instant TypeScript keeps per-query `querySubs` plus an in-memory EAV store. Instant Swift Data keeps the full corpus in `InstantStore` TripleIndexes (EAV+AEV+VAE) and rematerializes every namespace-local observer from those maps on each commit. That is the 4 GB recording balloon: query result size and copy work grow with recording history, not with the one live segment.

User explicitly allowed a claim steal of InstantStore/Runtime at `2026-08-12T12:36:00-0400` for this live-put rematerialize memory slice only. Steal is allowed only with that explicit user allow. Prior `codex-desktop/019fe994` ids stay in `agents.txt`.

## Steps

1. Add `InstantSameEntityLiveRevisionTests` that feeds 10,000 cardinality-one puts into one entity and records triple count, unbounded observation size, and rematerialize cost beside sibling history.
2. Add `InstantSameEntityLiveRevisionMemoryTests` that mirrors retained UTF-8 bytes and physical footprint: a live screen and a history screen, cancel on close, live put must not copy finalized history.
3. Change InstantStore observation so a live put rematerializes only observers whose result includes the changed entity. Do not debounce or drop live revisions.
4. Treat Instant operations as a durable-until-ack transport journal. Connected peers still receive every revision. After ack, prune. Reconnect uses current snapshot plus the unacked tail.
5. Do not use same-entity outbox supersession to drop unsent live revisions. A no-drop queue may grow when the producer outruns disk or network; it must not become permanent duplicated domain state.

## Touching

- `Tests/InstantSwiftDataCoreTests/InstantSameEntityLiveRevisionTests.swift`
- `Tests/InstantSwiftDataCoreTests/InstantSameEntityLiveRevisionMemoryTests.swift` (new)
- `Sources/InstantSwiftDataCore/InstantStore.swift` (steal, rematerialize skip only)
- `Sources/InstantSwiftDataCore/TripleIndexes.swift` (entity-matches helper)
- `Sources/InstantSwiftDataCore/InstantRuntime.swift` (steal claim; no edit unless publish contract requires it)

## Conflict check

- User-authorized steal at `2026-08-12T12:36:00-0400`. Preserve every prior InstantStore/Runtime hunk (deferred values, outbox, bounded query, leases).
- Scribe recording sources stay with the existing bounded-memory plan. This slice is Instant-library observation memory.
