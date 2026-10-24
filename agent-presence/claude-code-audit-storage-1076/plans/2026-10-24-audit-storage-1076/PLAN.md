# Plan 2026-10-24-audit-storage-1076

- **planId:** 2026-10-24-audit-storage-1076
- **agentId:** claude-code/audit-storage-1076@ld
- **role:** grower for the exercises and the counters (test-only code, ordered on #1076: "write real exercises of the
  poor hot paths"); no library fix in this plan unless it is one line with a passing exercise (an amendment names it
  first). The lab dispatches the fixes from the issues this audit files.
- **branch:** agent/claude/audit-storage-1076 (worktree ~/Sync/worktrees/instant-audit-storage-1076), rebased on main
  and pushed when the audit and its exercises are green.

## Outcome (#1076)

An audit of what the library writes to disk and sends over the socket for each logical write (save, claim, send,
acknowledgement, echo, prune), its SQLite settings (journal mode, synchronous, auto_vacuum, page reuse, checkpoints,
indexes, statements), its transaction batching, the outbox, and the upload and download paths. Each anti-pattern has a
file and line, how often it runs while a recording runs, its cost now (measured, or "not measured yet"), a design, and
its saving written as a hypothesis with how it is measured. Committed exercises measure each at real size and print
stable lines, so the same exercise measures the fix later; today's baseline is recorded from them.

## Steps

1. Read the code paths (the store's write calls, the outbox lifecycle, the server apply and result writes, the prune,
   storage uploads and downloads, the live transport's frames) and list the candidates.
2. Counters (`StorageIOCounters.swift`): a SQLite VFS shim that counts write calls and bytes, syncs, reads and
   truncates per file kind (database, write-ahead log, temporary files); the store's own per-call page meter
   (`InstantStorageWriteMeter`); bytes on the wire per direction. Plugs into #1072's `RealSizeMeter` as a counter.
3. Exercises (`StorageIOExercises.swift`), gated by an environment variable so the normal bundle skips them: bytes,
   syncs and pages per logical write at the phone's size (#1072's fixture), the store file's growth and free pages
   over a simulated hour of recording, and bytes sent and received per change. Each prints `STORAGEIO <exercise>
   key=value ...` lines. Baseline recorded in `docs/audits/2026-10-24-storage-io-baseline.txt`.
4. One issue per fix (linked to #1076 and #1072), worst first by measured cost, each naming its exercise and baseline.
5. The audit (`docs/audits/2026-10-24-storage-disk-network-audit.md`); CHANGELOG, PROGRESS, the audit ledger.

## Touching

New: `Tests/InstantSwiftDataCoreTests/RealSize/StorageIOCounters.swift`,
`Tests/InstantSwiftDataCoreTests/RealSize/StorageIOExercises.swift`,
`docs/audits/2026-10-24-storage-disk-network-audit.md`, `docs/audits/2026-10-24-storage-io-baseline.txt`.
Appended: `CHANGELOG.md`, `PROGRESS.md`, `docs/audits/commit-changelog.md`.
Read only: #1072's `RealSizeFixture.swift` and `RealSizeMeter.swift` (requests through
`agent-presence/_channels/2026-10-24-lib-audit-1072.md`).

## Conflict check

#1072 (lib-audit-1072) owns `Tests/InstantSwiftDataCoreTests/RealSize/RealSizeFixture.swift`, `RealSizeMeter.swift`,
`RealSizeBudgetTests.swift`, `RealSizeReport.swift` and `InstantRuntime.swift`'s stored-file calls; this plan adds its
own files beside them and edits none of theirs (agreed by message 2026-10-24 16:00 EDT: no second generator; the VFS
shim, the store's page meter and wire bytes are this plan's). #1074 (concurrency) and #1075 (memory) hold no claims on
these files. No library source is claimed.
