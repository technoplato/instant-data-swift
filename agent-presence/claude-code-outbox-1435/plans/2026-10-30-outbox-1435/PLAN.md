# Plan 2026-10-30-outbox-1435: a narrow outbox row and fewer outbox b-trees

- planId: 2026-10-30-outbox-1435
- agentId: claude-code/outbox-1435@strangelearning (tools/agent-run, claude/strangelearning, opus)
- role: mower (fewer pages written for the same writes; no new surface)
- issues: #1435 (P1, first), #1436 (P1, second), #1425 (heat-trace), #1426 (sqlite-writes, same file, other regions),
  #1115 and #1108 (the outbox's earlier b-tree work), #1383 (claim and acknowledgement invariants)
- branch: agent/claude/outbox-1435 (worktree ~/Sync/worktrees/outbox-1435), released per AGENTS.md and pinned by the
  consuming app

## Why (measured before any change)

Phone energy ledger 2026-10-30 12:00-17:14 (153 recording minutes): save 363 MB/h, acknowledgement 154, claim 108,
server-apply commits 334. Harness on main 2a6e6221 plus #1426's red (`aLiveWritesStepsByBTree`): claim 4.2 log frames,
acknowledgement 6.2, save 16.5, echo commit 19.7. The claim and acknowledgement change the size of a row that also holds
the body (`json`, `lifecycle_json`, `quarantine_json`), so SQLite rewrites the whole cell with every overflow page; the
acknowledgement also re-encodes the body, because status, serverTransactionID and confirmationSource live in it as well
as in columns.

Layout check (synthetic bytes, Python's SQLite 3.49, 400 overlapping writes after 728 refused rows of 19.2 KB as on the
phone's store copy, the three hot indexes): frames per write at a 6.6 KB body, current layout save 8.1, claim 5.0,
ack 7.0, echo 9.0 (29.1); narrow row and body table both WITHOUT ROWID keyed by mutation_id 8.6, 2.0, 4.0, 7.0 (21.6).
A rowid body keyed by an integer was worse on the echo (9.0: one body per leaf, so each delete rebalances).

## Steps

1. This plan and its claims (plan-only commit). List on #1435 every statement that reads or writes the body columns.
2. Red (#1435): a claim and an acknowledgement write no page of the body and no freed page; a migration test on a
   phone-shaped store with pending, claimed and acknowledged rows mid-flight.
3. Green (#1435): `instant_outbox` becomes a narrow WITHOUT ROWID row keyed by mutation_id; the body (`json`,
   `lifecycle_json`, `quarantine_json`, `quarantine_lifecycle_json`) moves to `instant_outbox_bodies`, WITHOUT ROWID,
   keyed by mutation_id, deleted with its row by its foreign key. The body is written at save and stops carrying status,
   serverTransactionID and confirmationSource, which decode from the row's columns; a claim and an acknowledgement
   update the narrow row only. The store converts once at open, decided by the table's columns (as #704's conversion),
   with SQLite's twelve-step rebuild, so a restore that rebuilds the old shape converts again.
4. Measure (#1435): frames per save, claim, acknowledgement and echo before and after with `aLiveWritesStepsByBTree`
   once #1426's harness is on main, and the migration's time on a clone of the phone's store (counts only).
5. #1436: for each outbox-side b-tree the hot-path read it serves (`EXPLAIN QUERY PLAN`); drop or make partial the ones
   no hot read needs (the autoindex goes with step 3; then the global-effect and watermark indexes, the effect entities'
   delete and re-insert on every staged row, the key tables' lookups); red then green, frames per save and per echo
   before and after.
6. Release, bump Scribe, cut and install a build per scribe-builds; the ledger's save, claim and acknowledgement MB an
   hour before and after.

The write contract stays whole: a save waits for the local store and the durable outbox only; offline writes succeed
and replay in order; refused writes keep their bodies; nothing a reader decodes changes.

## Touching

- Sources/InstantSwiftDataCore/SQLitePersistenceStore.swift: the outbox's schema and conversion, the statements on
  `instant_outbox` and its body, the body's encode and decode. Not the live-query result regions #1426 owns.
- Tests/InstantSwiftDataCoreTests/InstantOutboxNarrowRowTests.swift (new)
- Tests/InstantSwiftDataCoreTests/InstantOutboxBodyConversionTests.swift (new)
- Raw outbox SQL in test fixtures only: InstantStoreTests.swift, InstantBoundedOutboxDeliveryTests.swift,
  InstantOutboxSupersessionIntegrationTests.swift, InstantOutboxHydrationTests.swift,
  InstantFailedMutationRetryWindowTests.swift, InstantOutboxPageChurnTests.swift,
  InstantTerminalFailureComponentTests.swift, InstantOutboxBTreeWritesTests.swift, InstantOutboxRareStateIndexTests.swift
- docs/releases/ (the release), CHANGELOG.md, PROGRESS.md, docs/audits/commit-changelog.md

## Conflict check

SQLitePersistenceStore.swift: sqlite-writes-1426 holds it tonight for the live-query result JSON (write decision,
flush, marker, bootstrap rebuild); this plan stays in the outbox's regions and rebases onto its release before each
push. The test files' last claims are released slices (#1115, #1383, #696, #704, older).
