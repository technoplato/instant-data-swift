# Bound nested live-query triples before authoritative hot-store apply

- `planId`: `2026-08-14-preapply-nested-limit`
- `agentId`: `codex-desktop/01a00071-f1c1-7193-adcd-3bc9f30b5f95/root/preapply_nested_limit`
- `role`: `mower` — stop a bounded query from transiently materializing its full unbounded response in the shared hot store
- `issue`: `#155` (SQLiteData parity and ergonomics)
- `channel`: `agent-presence/_channels/01a00071-five-recording-sync-soak.md`

## Outcome

For an InstaQL computation with nested limits, derive one bounded insert-triple set from the
resolved local attribute set before the authoritative transaction is assembled. Use that same set
for both authoritative operations and the live-query replacement. Keep non-query computations,
non-insert operations, and queries without nested limits unchanged. This is Swift-specific
pre-authoritative-apply containment for the process-wide hot store, not upstream parity or true
server-side nested-limit pushdown.

## Steps

1. Add translator-level red tests proving a root plus ten children with `limit: 2` contributes only
   the root and newest two children to both transaction operations and replacement triples.
2. Add sequential-window, overlapping-query, optimistic-protection, unbounded/no-query, and
   repeated-refresh plateau coverage at the narrowest existing deterministic seam.
3. Reuse `InstantLiveQueryNestedLimit` with the refresh's resolved local attributes while preserving
   every non-insert operation and every non-query computation.
4. Correct only directly related misleading comments: upstream Instant limits nested query results
   client-side after constructing its raw query store; this containment intentionally acts earlier
   in Swift to bound the shared authoritative store.
5. Parse and diff-check the owned files, report files stable, then wait for the parent to release the
   serialized SwiftPM lane.

## Touching

- `Sources/InstantSwiftDataCore/InstantLiveRefreshApplication.swift`
- `Sources/InstantSwiftDataCore/InstantLiveQueryNestedLimit.swift` (comment correction only)
- `Tests/InstantSwiftDataCoreTests/InstantLiveQueryNestedLimitMemoryTests.swift`
- `agent-presence/_channels/01a00071-five-recording-sync-soak.md`

## Conflict check

The translator and nested-limit test carry historical claims from completed, committed work. Those
agents are not live. This mower appends its identity, records the scope split in the active soak
channel, and preserves the existing implementation. The terminal-disposition worker owns Runtime,
SQLite persistence, and separate terminal/live-transport tests; this plan touches none of them.
