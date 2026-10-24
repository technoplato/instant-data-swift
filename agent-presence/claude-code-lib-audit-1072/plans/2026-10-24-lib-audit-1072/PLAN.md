# Plan 2026-10-24-lib-audit-1072

- **planId:** 2026-10-24-lib-audit-1072
- **agentId:** claude-code/lib-audit-1072@ld
- **role:** mower for the fixes (cost that grows with the whole store or account, cut to the cost of the change), grower
  for the real-size fixture and its benchmarks (ordered on #1072: "Hold it in CI").
- **branch:** agent/claude/lib-audit-whole-set (worktree ~/Sync/worktrees/instant-lib-audit), rebased on main and
  pushed after each green; released as the next free tag (v1.9.35 after v1.9.34 unless a sibling takes it first).

## Outcome (#1072)

No operation on a hot path costs more because the store, a namespace, or everything the account ever saved is large:
write, server apply, prune, query, observe, upload, download, delete, lookup and launch cost what their change or their
bounded result costs. Each case found so far (#654, #932, #1035, #1006, #653, #1015, the one gate behind a 6 s prune)
was found one at a time from the phone's measurements; this audit finds the rest in one pass, measures each at the
phone's real size, fixes the worst test first, files the others, and holds the class in CI.

## Steps

1. The shared real-size fixture and meter, on main early (the sibling audits #1074 concurrency, #1075 memory, #1076
   storage build on them): a generated store shaped like the phone's (about 45,000 resident facts, 175,000 facts on
   disk, 9,455 `$files` the account holds, 4,264 local file records, 663 refused writes, 355 unloaded results), driven
   through the runtime's own API with a scripted server; a meter of time, CPU, instructions, allocations (libmalloc's
   logger hook), bytes written, footprint and the longest operation-gate hold per operation.
2. The audit table (`docs/audits/2026-10-24-whole-store-cost-audit.md`): every hot-path operation, who calls it from
   Scribe, its cost at real size (on a copy of the phone's store, never committed, deleted after, and on the fixture),
   and its fix or issue.
3. Red, then green, for the worst, starting with what Scribe calls while recording; `storedFiles()` and
   `observeStoredFiles()` still load every `$files` row. Every other finding filed and linked to #1072.
4. Budgets at real size that fail CI on a regression: allocations and time for transact, server apply, prune, query,
   observe and the file calls, plus a scale check (the same operation on a store four times larger costs the same).
5. Next steps as an expert would write them, on #1072, measured where possible (the one serial gate, one writer and
   concurrent WAL readers, chunked work that yields, small locks where a hop costs more than the work, streamed decode).
6. CHANGELOG, PROGRESS, the audit ledger, the release document, the tag; Scribe and Scribe Playback pin it on Scribe's
   main (pin files only).

## Touching

New: `Tests/InstantSwiftDataCoreTests/RealSize/RealSizeFixture.swift`, `RealSizeMeter.swift`, `RealSizeBudgetTests.swift`,
`RealSizeReport.swift`; `docs/audits/2026-10-24-whole-store-cost-audit.md`; `docs/releases/v1.9.35.md`.
Changed: `Sources/InstantSwiftDataCore/InstantRuntime.swift` (the worst finding's fix, first `storedFiles()` and
`observeStoredFiles()`; an amendment names any other function before it is edited),
`Sources/InstantSwiftData/InstantSwiftData.swift` (the stored-file calls' doc comments),
`Tests/InstantSwiftDataCoreTests/InstantStoredFileLookupTests.swift`, `CHANGELOG.md`, `PROGRESS.md`,
`docs/audits/commit-changelog.md`.

## Conflict check

InstantRuntime.swift's earlier claims (#1007, #932, #654's prune, longrec-654's stored-file lookups) have all landed
(v1.9.34). The sibling audits started at 15:55 (#1074, #1075, #1076, #1077) hold no claims yet; they add their own files
under `Tests/InstantSwiftDataCoreTests/RealSize/` and call the fixture and meter, whose files this plan owns (changes to
them through the channel `agent-presence/_channels/2026-10-24-lib-audit-1072.md`).

## Amendment 1 (2026-10-24 17:08 EDT, claude-code/lib-audit-1072@halfjew22)

The worst file call Scribe makes while recording is not `storedFiles()` (Scribe never calls it, nor
`observeStoredFiles()`) but the upload: every `uploadFile` read and decoded every `instant_files` record under the
operation gate to hand them to stored-file observers, whether one was open or not (4,264 records, about 3 MB of JSON, on
the phone; about eleven uploads a minute while recording). Deletes, reads by id and evictions read them all again the
same way, and one record that does not decode fails each of them after its work is done. This amendment names the
functions of `Sources/InstantSwiftDataCore/InstantRuntime.swift` before they are edited: `savePreparedStoredFile`,
`storedFileContents(id:name:)`, `deleteStoredFile(id:)`, the publish at the end of `evictStoredFiles(ids:)`, and one new
private helper that reads and publishes the records only while an observation is open. The red and green go in
`Tests/InstantSwiftDataCoreTests/InstantStoredFileLookupTests.swift` (already claimed). `storedFiles()` and
`observeStoredFiles()` stay claimed for their bounded form or their issue.
