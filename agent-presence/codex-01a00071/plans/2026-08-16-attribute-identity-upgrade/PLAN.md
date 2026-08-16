# Attribute identity upgrade

- `planId`: `2026-08-16-attribute-identity-upgrade`
- `agentId`: `codex-desktop/01a00071-f1c1-7193-adcd-3bc9f30b5f95/root/mac_segment_gap`
- `role`: `mower`
- `issue`: Scribe #073
- `channel`: `agent-presence/_channels/2026-08-16-attribute-identity-upgrade.md`

## Outcome

Preserve an existing durable server relation attribute and its triples when a later bootstrap
declares the same forward/reverse identity under a logical application ID. Make the logical ID an
exact alias for local reads and writes without persisting duplicate namespace/name rows.

## Steps

1. Add the focused existing-physical-ID reconciliation and logical-write regression.
2. Reconcile incoming declaration metadata onto one deterministically selected physical row.
3. Canonicalize logical attribute IDs at the store/runtime write boundary.
4. Add the Scribe SQLite relaunch regression and run only frontend parse/diff checks.

## Touching

- `Sources/InstantSwiftDataCore/TripleIndexes.swift`
- `Sources/InstantSwiftDataCore/InstantStore.swift`
- `Sources/InstantSwiftDataCore/InstantRuntime.swift` only if durable outbox canonicalization is required
- `Tests/InstantSwiftDataCoreTests/AttributeStoreIdentityUpgradeTests.swift`
- Scribe recording relation source/test already owned by the parent plan
- append-only coordination markers

## Conflict check

These core files have historical claims. The active collaboration tree has no agent editing the
same attribute seams. This follow-up is explicitly delegated by the root owner and preserves all
unrelated work. The root handoff forbids staging or commits, so these plan and claim markers remain
append-only working-tree evidence rather than a new plan-branch commit.
