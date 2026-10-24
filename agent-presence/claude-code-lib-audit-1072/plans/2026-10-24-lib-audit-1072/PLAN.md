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

## Amendment 2 (2026-10-24 18:40 EDT, claude-code/lib-audit-1072@halfjew22): the outbox claim (#1108, #1114), as 1.9.36

After 1.9.35 the largest operation-gate holder while recording is the delivery pump's claim: 402-524 ms of every
recording minute on the phone-shaped store, about 60% of the gate. Its candidate read and its continuation check filter
`delivery_claim_state = ? AND (delivery_state = ? OR (status IN (?, ?) AND delivery_metadata_version < ?))`; the `OR`
leaves SQLite one plan, a search on the claim state alone (instant_outbox_delivery_deadline_idx) and a sort, so every
ready row is visited, the 663 refused writes included, each through its body's overflow pages. #1007 dropped the index
on (claim state, delivery state) because that `OR` kept any statement from using it. The fix splits each read into its
two branches (a UNION for the candidates, two EXISTS for the check) and adds that index back under a new name in a
migration; on a copy of the phone-shaped store the plans then search only needs-delivery rows and legacy rows. Claims:
`Sources/InstantSwiftDataCore/SQLitePersistenceStore.swift` (the two automatic candidate reads and their SQL, one
migration, one test hook counting a read's SQLite steps), `Tests/InstantSwiftDataCoreTests/RealSize/OutboxClaimScaleTests.swift`
(new: the red and green), `docs/releases/v1.9.36.md` (new). Then the Scribe pin moves to 1.9.36 (the same files as the
1.9.35 pin; Scribe plan amended there).

## Amendment 3 (2026-10-24 19:05 EDT, claude-code/lib-audit-1072@halfjew22): #1141, the interner data race, first

The lab's order of 18:45 puts #1141 first: every copy of `TripleIndexes` shares one `TxIDInterner` class box, and
`internTxID` appends to its array and dictionary with no uniqueness check, so a copy written off the store actor (a
refused claimed write's component hydrated between the gate's turns) races the store's own writes on the actor. Copy on
write would copy every interned transaction id into each prepared write, a whole-store cost; interning is append-only
and an index never changes, so the box stays shared and takes a small lock (`OSAllocatedUnfairLock`) around its state.
Claims: `Sources/InstantSwiftDataCore/TripleIndexes.swift` (the `TxIDInterner` class and its two call sites' comments
only), `Tests/InstantSwiftDataCoreTests/TripleIndexesInternerRaceTests.swift` (new: two copies interning on two threads,
a stress test that crashes or misreads without the lock, and a Thread Sanitizer run of it). Released with the next
version through this plan.

## Amendment 4 (2026-10-24 19:20 EDT, claude-code/lib-audit-1072@halfjew22): #1108's per-write attribute map

Every transact asks `OutboxSameEntitySupersession.isEligibleImmediateTailNewcomer` whether it may replace the outbox's
tail, and the check built a dictionary of every attribute (2,283 on the phone) before looking at the write's shape:
about 1 MB allocated per write, which most writes (merges, links) can never use. Claims:
`Sources/InstantSwiftDataCore/OutboxSameEntitySupersession.swift` (the two shape checks: the operations' shape first,
then only their own attribute ids looked up), `Tests/InstantSwiftDataCoreTests/RealSize/RealSizeMeter.swift` (already
this plan's: counting one thread's allocations), `Tests/InstantSwiftDataCoreTests/OutboxSupersessionSchemaCostTests.swift`
(new: the red and green).
