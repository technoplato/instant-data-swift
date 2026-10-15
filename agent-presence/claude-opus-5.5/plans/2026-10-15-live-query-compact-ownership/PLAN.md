# Plan: live-query ownership rows keyed by a compact query id, not the query's whole JSON key (#704)

- **planId:** `2026-10-15-live-query-compact-ownership`
- **agentId:** `claude-opus-5.5-live-query-704-d417e89e`
- **Role:** grower, ordered by the user for a P1 (#704): a storage-layout change with a one-time conversion of existing
  stores; no read, write or API changes what it returns.
- **Branch:** `agent/claude/live-query-table-704`, from `main` at `1e781d7c` (v1.9.10 and its audit ledger).
- **Outcome:** v1.9.11. `instant_live_query_triples` repeats each row's query key, the whole InstaQL JSON of its query
  (1,671 bytes a row on average, up to 4,306, on a real device), and both of its indexes contain that key, so every
  index entry spills to its own 4 KB overflow page: a device stored 32,555 ownership rows (3.7 MB of values) in
  328.9 MB. After: each stored result has an integer `query_id`; ownership rows carry that id instead of the key; the
  table is its own primary-key b-tree (`WITHOUT ROWID`), so the duplicate autoindex is gone; the identity index keeps
  `(entity_id, attribute_id, value_json, query_id)`. Same rows, same reads.

## Steps (no code here)

1. Design note: `docs/adr/0020-compact-live-query-ownership.md` (amends ADR 0008's table shape), with the measured
   numbers and the conversion's guarantees.
2. Red: the layout of a fresh store; an old-layout store converted on open with every ownership row and result row
   kept and every live-query read (ownership by key, owner lookups, #441's newest-result stamp, #445's newest values,
   the application-migration scan, the bootstrap's retained entities, prune's cascade) answering the same before and
   after; the bytes of a long-keyed result's ownership under a bound; the open path's time on a converted store and
   on a conversion. Read-only test hooks over the existing private reads, so the red commit compiles.
3. Green: the conversion in `SQLitePersistenceStore.bootstrap()` (detected from the table's columns, one transaction,
   so an interrupted conversion is redone whole on the next open), and every statement that named the key on an
   ownership row reads or binds the id instead.
4. Existing tests that read `instant_live_query_triples.query_key` directly join through the results table instead,
   each asserting the same rows.
5. Full suite on a clean build; the conversion measured on a copy of the real store (outside the repository);
   `docs/releases/v1.9.11.md`, CHANGELOG, the audit ledger, PROGRESS; tag `v1.9.11`.

Touching `Sources/InstantSwiftDataCore/SQLitePersistenceStore.swift`, new
`Tests/InstantSwiftDataCoreTests/InstantLiveQueryCompactOwnershipTests.swift`, the six test files that read the
ownership table by key (`InstantStoreTests.swift`, `AttributeStoreIdentityUpgradeTests.swift`,
`InstantOversizedCachedResultOpenTests.swift`, `InstantPartialEntityRepairTests.swift`,
`InstantLocalStampShadowsDeviceStoreTests.swift`, `InstantLiveQueryNestedLimitMemoryTests.swift`), the ADR, the release
document, `CHANGELOG.md`, `PROGRESS.md` and `docs/audits/commit-changelog.md`, added 2026-10-15 08:47 EDT.

Conflict check: the files above were last claimed by plans that have shipped (energy-98 in v1.9.9, the retained-mutation
quarantine in v1.9.10); no open channel names them.
