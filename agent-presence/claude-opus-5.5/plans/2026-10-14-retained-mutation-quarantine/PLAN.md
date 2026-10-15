# Plan: a retained mutation with no preparation receipt is held aside, not a wall in front of every write (#696)

- **planId:** `2026-10-14-retained-mutation-quarantine`
- **agentId:** `claude-opus-5.5-receipt-quarantine-d417e89e`
- **Role:** grower, ordered by the user for a P0 (#696): a library change with a new table, a new read API and a
  changed startup contract; nothing a valid write does changes.
- **Branch:** `agent/claude/retained-mutation-quarantine`, from `main` at `efa4d285` (v1.9.9 and its audit ledger).
- **Outcome:** v1.9.10. A store opened by an older build can hold outbox rows whose optimistic effect has no SQLite-owned
  preparation receipt (`optimistic_overlay_active = 1 AND optimistic_effect_receipt_fingerprint IS NULL`). Today the
  first such row refuses every live connection forever (`persistenceFailed`, "Synchronization is blocked by N retained
  mutations"), so every later write, however valid, piles up unsent. After: at runtime bootstrap each such row moves
  whole into `instant_outbox_quarantined` (its original row and body bytes, the reason, the time; never deleted by the
  library), then the runtime opens and drains every other write in its order, as today.

## Steps (no code here)

1. Red: a store with receipt-less retained mutations plus later valid writes. Today `connect()` throws
   `persistenceFailed`; the test wants the connection open, the later writes sent in creation order and drained, and
   the receipt-less ones in the quarantine with their bytes intact. A guard test: a store with no receipt-less rows
   is untouched by the quarantine step (no new table, every table's rows identical before and after).
2. Green: the quarantine step in `SQLitePersistenceStore`, run by `InstantRuntime.bootstrap` before it derives the
   synchronization blocker; created lazily, so a store that never needs it never gets the table.
3. The ledger: `InstantQuarantinedMutation` (reason `noPreparationReceipt`) read through `quarantinedMutations(limit:)`
   and `quarantinedMutationCount()` on the runtime and the client, so an application can list and export them.
   Send Again is not part of this release.
4. Existing tests that pinned the old wall at startup are brought in line, each with the reason; a receipt revoked
   while a session runs still stops that session until the next launch (unchanged).
5. Full suite on a clean build; `docs/releases/v1.9.10.md`, CHANGELOG, the audit ledger, PROGRESS; tag `v1.9.10`.

Touching `Sources/InstantSwiftDataCore/SQLitePersistenceStore.swift`, `InstantRuntime.swift`, new
`Sources/InstantSwiftDataCore/InstantQuarantinedMutation.swift`, `Sources/InstantSwiftData/InstantSwiftData.swift`,
new `Tests/InstantSwiftDataCoreTests/InstantRetainedMutationQuarantineTests.swift`, and the existing tests that pinned
the startup wall (`InstantStoreTests.swift` and its neighbors), added 2026-10-14 22:03 EDT.

Conflict check: the files above were last claimed by the energy-98 plans (merged into v1.9.9, finished); no open
channel names them.

Touching also `Tests/InstantSwiftDataCoreTests/InstantOutboxDeliveryStallTests.swift`,
`InstantOutboxSupersessionIntegrationTests.swift`, `InstantPersistenceCacheResidencyTests.swift` and
`InstantStartupTraceTests.swift`: their tests seed receipt-less rows before launch to test 1.9.9's wall (or measure a
store that keeps 500 or 10,000 such rows), so they now ask for `.blockSynchronization`; added 2026-10-14 23:26 EDT.

Step 3 widened (2026-10-14 22:30): Scribe's feature contract (docs/FEATURES.md line 7, its main at 85ed45bd8) says a
held write shows in the sync screen with Send Again and Export, so 1.9.10 also gets `retryQuarantinedMutation(id:)`
(the held transaction becomes a new local write with the same ID and its own receipt; the quarantine row stays, marked
`sent-again`) and a quarantined mutation's lifecycle reports failed instead of waiting forever.
