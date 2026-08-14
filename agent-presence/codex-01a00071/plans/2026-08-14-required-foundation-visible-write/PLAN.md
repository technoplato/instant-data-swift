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
upstream JavaScript reactor's transaction ordering. Metadata-first hydration and a durable
claim-scoped projected-byte reservation keep both each mutation and all active claims inside the
existing 8 MiB envelope after required values are substituted.

## Steps

1. Add a bounded delivery regression whose older full entity mutation has a stale required text
   field and an unfiltered relation, with no active successor; require one valid wire transaction
   containing the relation and the newest required text, never the stale text.
2. Preserve the existing successor invariant with a companion test: an active newer scalar
   successor sends the older body first and the newer body second.
3. Extend the visible-write snapshot with newest materialized values and substitute only required
   cardinality-one inserts that would otherwise be removed.
4. Add protocol regressions for an individually oversized projected body and for two individually
   valid projected bodies whose aggregate exceeds 8 MiB. Prove visible failure or ordered deferral,
   exact claim release/reservation, no stale fallback, and no oversized send.
5. Move projected-body admission into the atomic SQLite claim transaction. Read authoritative
   scalar byte lengths before values, retain only the admitted hydrated prefix, and persist a
   nullable claim-scoped projected-byte count that is cleared on every claim disposition.
6. Verify the focused serialized delivery tests, the bounded-outbox suite, parser checks, and the
   complete task-owned diff. Physical/device acceptance remains a separate parent-owned lane.

## Touching

- `Sources/InstantSwiftDataCore/InstantVisibleWriteFilter.swift`
- `Sources/InstantSwiftDataCore/SQLitePersistenceStore.swift`
- `Sources/InstantSwiftDataCore/InstantStore.swift`
- `Sources/InstantSwiftDataCore/BoundedOutboxDelivery.swift`
- `Tests/InstantSwiftDataCoreTests/InstantBoundedOutboxDeliveryTests.swift`
- `agent-presence/_channels/01a00071-five-recording-sync-soak.md`

## Conflict check

The persistence and in-memory store paths retain historical 019fe75c/019fe994 claims; their work is
committed on the current autoresearch branch. This mower appends its identity, preserves those
changes, and confines implementation to visible-write snapshot construction and the exact delivery
regressions. Scope agreement includes one additive SQLite migration for nullable claim-scoped
projected bytes inside the already-claimed persistence file. No runtime, transport, query, public
API, or Scribe source is claimed here.

## Verification

- Red-first protocol failures proved the pre-fix behavior: the oversized
  authoritative replacement had no visible failure and the second 5 MiB
  replacement was claimed instead of remaining ready/unoffered.
- The exact two-test projected-envelope filter passes 2 tests in 0.641 seconds.
- The ACK/release/legacy-NULL/expiry lifecycle filter passes 3 tests in 0.063
  seconds.
- The complete serialized `InstantBoundedOutboxDeliveryTests` suite passes all
  48 tests in 21.161 seconds with 12 expected recorded issues.
- `InstantTerminalFailureComponentTests` passes all 14 tests in 2.416 seconds.
- `swiftc -parse` on all five owned source/test files and `git diff --check`
  pass. No Runtime/public API file, commit, stage, ledger, or `PROGRESS.md`
  mutation was made.
