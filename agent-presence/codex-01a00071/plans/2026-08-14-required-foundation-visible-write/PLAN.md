# Preserve required entity foundation through visible-write filtering

- `planId`: `2026-08-14-required-foundation-visible-write`
- `agentId`: `codex-desktop/01a00071-f1c1-7193-adcd-3bc9f30b5f95/root`
- `role`: `mower` — prevent a Swift-only stale-write optimization from emitting a server-invalid partial entity body
- `issue`: `#155` (SQLiteData parity and ergonomics)
- `channel`: `agent-presence/_channels/01a00071-five-recording-sync-soak.md`

## Outcome

Keep Instant's per-attribute stale-write protection without allowing an older relation-bearing
mutation to lose required scalar foundation on its final wire body. When a required cardinality-one
scalar is newer in materialized state and no active successor transaction protects that write, the
visible-write filter must substitute the newest materialized value instead of omitting the field or
sending the stale original. Active successors must retain ordered original bodies, matching the
upstream JavaScript reactor's transaction ordering.

## Steps

1. Add a bounded delivery regression whose older full entity mutation has a stale required text
   field and an unfiltered relation, with no active successor; require one valid wire transaction
   containing the relation and the newest required text, never the stale text.
2. Preserve the existing successor invariant with a companion test: an active newer scalar
   successor sends the older body first and the newer body second.
3. Extend the visible-write snapshot with newest materialized values and substitute only required
   cardinality-one inserts that would otherwise be removed.
4. Verify focused filter/delivery/persistence tests, parser and whitespace checks, then run a
   credentialed Scribe physical preflight that proves no terminal required-text rejection.

## Touching

- `Sources/InstantSwiftDataCore/InstantVisibleWriteFilter.swift`
- `Sources/InstantSwiftDataCore/SQLitePersistenceStore.swift`
- `Sources/InstantSwiftDataCore/InstantStore.swift`
- `Tests/InstantSwiftDataCoreTests/InstantBoundedOutboxDeliveryTests.swift`
- `agent-presence/_channels/01a00071-five-recording-sync-soak.md`

## Conflict check

The persistence and in-memory store paths retain historical 019fe75c/019fe994 claims; their work is
committed on the current autoresearch branch. This mower appends its identity, preserves those
changes, and confines implementation to visible-write snapshot construction and the exact delivery
regressions. No runtime, transport, schema, query, public API, or Scribe source is claimed here.
