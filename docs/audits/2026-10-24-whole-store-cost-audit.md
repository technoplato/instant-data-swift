# Whole-store cost audit (#1072), 2026-10-24

Every operation on a hot path should cost what its change or its bounded answer costs, not what the store, a
namespace, or everything the account ever saved costs. Until this audit each case was found one at a time from a
phone's measurements (#654, #932, #1035, #1006, #653, #1015). This audit read the whole library for the class, measured
every hot-path operation at a phone's real size and at a quarter of it, fixed the worst one the consuming app calls
while recording (test first), filed the rest, and holds the class in CI with real-size budgets.

## Bottom line

- **Fixed:** every upload, read by id, delete and eviction read and decoded every file record the device keeps (4,264
  on the phone, about 3 MB of JSON), the upload holding the operation gate, only to publish them to observers the app
  never opens. At the phone's size an upload went from **16.8 ms, 107,142 allocations and 17.4 ms of gate to 0.07 ms,
  237 allocations and 0.04 ms**; an upload and its delete from 39.7 ms to 0.13 ms (red `347af4f6`, green `f83e9448`).
  One record that did not decode also failed every upload after its work was done and deleted the stored file.
- **Worst left, filed:** a discard of one refused write holds the gate for its whole run, **112 ms** on the store as
  launched and **1.7 s** once the whole `$files` list was loaded, 32 of them per recovery sweep (#1103); the whole
  `$files` list costs about **2 s and 1.5 GB allocated** per call (#1105, not called by the app); the refusal reads
  **218-241 ms** (#1106); launch grows with every stored result (#1107); every write scans the outbox for its supersession
  tail and its pump claim (#1108).
- **Held in CI:** `RealSizeBudgetTests` meters 18 operations at both sizes in the correctness job (release): a cost
  that grows four-fold with the store fails the build, and each known excess is a known issue that must be removed
  once fixed.
- **A fixture artifact, found and fixed:** the first fixture's scripted server sent text transaction ids, which the
  runtime's watermark never passes (it compares them as integers), so its stores kept every accepted write (783 rows,
  84 MB of bodies; the phone held 4) and every server apply re-read them. That made a one-shot query cost 0.7-0.9 s.
  Fixture version 3 sends growing integer ids, as Instant does.

## How it was measured

**Evidence kinds.** The costs below are deterministic local evidence: a generated store shaped like one iPhone's,
driven through the runtime's public and package API by an in-process scripted server and storage, with no network. The
"grows with" column and the paths are read from the code (nine read-only readers, cited by file and line in the
issues). Nothing here is measured on a device; the device check is the next build that carries 1.9.35.

**The store** (`Tests/InstantSwiftDataCoreTests/RealSize/RealSizeFixture.swift`, version 3): the phone's counts on
2026-10-24, counted, never copied: 352 recordings, 8,712 transcript lines (the eleven longest recordings 2,318 to 114
lines), 3,400 entities of other namespaces, 9,455 account files, 4,264 device file records, 663 refused writes, 48 open
and 355 closed queries, 2,283 attributes. Generated through `transact` and server answers, it holds 55,232 resident
facts at launch (the phone 45,369). The quarter size scales every count by 0.25. Generation takes 13.6 s (quarter) and
66.7 s (phone) on the Mac mini, cached by version, shape and schema migrations.

**The meter** (`RealSizeMeter.swift`): per call, the median wall time; process CPU and instructions retired
(`proc_pid_rusage`); heap allocations and bytes (libmalloc's `malloc_logger` hook, counted in a second pass); logical
bytes written; footprint and its peak; and the operation gate's longest hold, its holder, and its whole hold per call
(the #1074 timeline). Allocation and instruction counts barely move with the host's load, so the comparisons below lean
on them; the Mac mini was shared with other agents' builds during the runs (load 7 to 120), so wall times are noisy.

**Runs** (Mac mini M4, Xcode 27 beta, release with `-enable-testing`): report2 (fixture version 2, before the fix),
report3 (version 3, after the fix), the budget run (version 3, the whole-list calls left out, so later steps run on
the store as launched), and the recording minutes before and after; logs kept outside the repository under the
audit's evidence folder. The "before" rows of single calls are report2's: the upload touches no outbox row, and the
version 3 recording before the fix agrees (17 ms of gate per upload at minute 5).
`INSTANT_REAL_SIZE_REPORT=1` runs the report, `INSTANT_REAL_SIZE_RECORDING_MINUTES=120` the recording minutes.

## The table

Costs per call: median wall ms / heap allocations / MB allocated; "gate" is the operation gate's longest hold. Quarter =
a quarter of the phone's size; phone = its full size. The two rows that say "before" are report2's, on fixture version
2 (see the runs above); every other row is fixture version 3 and the fix: report3's numbers, or the budget run's where
report3 ran the call after the whole `$files` list had loaded.

| Operation | The app calls it | Quarter | Phone | Grows with | Fix or issue |
| --- | --- | --- | --- | --- | --- |
| `uploadFile`, before | ~11 a minute while recording (a 60 s audio chunk, ten 6 s media segments) | 6.5 / 27,190 / 4.5, gate 10.6 | 16.8 / 107,142 / 17.9, gate 17.4 | every file record | fixed: `347af4f6`, `f83e9448` |
| `uploadFile`, after | same | 0.22 / 111 / 0.1, gate 0.1 | 0.07 / 237 / 0.1, gate 0.04 | nothing | budget |
| `deleteStoredFile` (an upload, then its delete), before | a chunk whose row failed; each media file of a deleted recording | 8.6 / 54,612 / 9.1 | 39.7 / 214,519 / 35.8 | every file record | fixed: same |
| same, after | same | 0.11 / 210 / 0.0 | 0.13 / 213 / 0.1 | nothing | budget |
| `storedFileContents` (no copy) | never | not metered | not metered | every file record, read twice | fixed: same |
| `downloadStoredFile`, by id, with a record | playback media | 0.31 / 192 / 0.0 | 0.39 / 192 / 0.0 | nothing | budget |
| `downloadStoredFile`, by id, no record | another device's media | 5.5 / 2,498 / 3.2, gate 16 | 19.0 / 4,110 / 11.4, gate 52 | the schema (an attribute store per query, under the gate) | #1111 |
| `evictStoredFiles(ids:)`, 200 ids | once per launch, 200 at a time | 4.4 / 27,245 / 5.1 | 17.3 / 107,197 / 19.8 | every file record | #1104 (its publish fixed) |
| `storageSnapshot()` | never (storage status views, CLI) | 9.6 / 27,286 / 4.6, gate 11.6 | 17.7 / 107,238 / 17.9, gate 24.2 | every file record | #1104 |
| `localStoredFiles()` | once per launch (keeps the held copies) | 10.0 / 57,952 / 14.0 | 22.1 / 532,256 / 117.7 | every file record (a list, by design) | #1104 (page the held copies) |
| `storedFiles()` | never (CLI, `@StoredFiles`, `clearDownloadedFiles`) | 930 / 1.51M / 365, gate 140 | 2,008 / 6.08M / 1,480, gate 306 | every `$files` row of the account | #1105 |
| `observeStoredFiles()`, first emission | never | 949 / 1.57M / 375 | 1,750 / 6.27M / 1,525, gate 360 | every `$files` row, asked twice | #1105 |
| `transact`, a transcript line (16 values merged) | ~75 a minute while recording, plus heartbeats and live lines | 3.2 / 8,728 / 1.7, gate 11.5 | 1.3 / 10,120 / 2.7, gate 7.8 (2.5 ms of gate a write) | the schema (a map of every attribute a write), the outbox (tail read, pump claim) | #1108 |
| a refused write | refusal storms | 9.6 / 14,229 / 2.7, claim 3.3 ms | 14.2 / 15,887 / 3.9, claim 8.0 ms | the refused rows in the outbox (the pump claim) | #1108 |
| server apply: refresh of a 128-line page | every write's echo of the live window | 32.9 / 21,049 / 14.4, 52 KB written | 20.5 / 20,988 / 18.3, 51 KB written | the result, not the store | #1109 (per-refresh rebuild, rehydration, whole-tree decode) |
| prune, nothing closed | every 64th answer | 0.04 / 119 | 0.11 / 424 | nothing | budget |
| prune of one closed 32-line page | same | 7.8 / 23,448 / 5.6, gate 11.8 | 8.1 / 23,749 / 5.8, gate 12.7 | the closed result, not the store (#654 holds) | budget |
| `queryOnce`, first 32 lines (through the socket) | the media scan (~1 a minute, limit 16/100), each take's chunk check | 19.9 / 41,732 / 12.6, gate 6.2 a call | 18.3 / 43,459 / 20.9, gate 8.9 a call | the schema, a little (#1111) | budget |
| `queryOnce`, a 256-line page | timeline gaps, history | 131 / 277,354 / 69.6 | 87 / 314,272 / 84.4 | the answer (about 1,200 allocations a row) | #1109 |
| `queryLocally`, a 256-line page (local reader) | history pages, the playback device query | 5.2 / 2,289 / 3.2 | 11.3 / 5,635 / 12.3 | every line of the recording on disk | #1110 |
| `queryLocally`, 32 lines of the same recording at both sizes | same | 1.7 / 1,905 / 3.1 (28.6M instructions) | 5.6 / 5,136 / 12.2 (85.2M instructions) | the schema: a store of every attribute per call | #1111 |
| `observe`, first emission of a 256-line page | every screen open | 8.8 / 28,983 / 10.8, gate 12.5 | 11.8 / 50,011 / 21.4, gate 35.3 | the answer, and the background apply of the server's | #1110, #1109 |
| `observe`, first emission of 32 lines | same | 3.3 / 7,866 / 4.3 (81M instructions) | 8.3 / 15,272 / 14.3 (212M instructions) | the schema (validation per call) | #1111 |
| `observe`, the emission a write causes | the live window, every write | 17.5 / 44,903 / 11.6 | 17.2 / 58,581 / 15.8 | a little (1.3x): the write's own costs (#1108) | #1056, #1110 |
| launch (bootstrap, sign-in, connect) | every launch | 140 / 381,945 / 96.4, 4.1 MB written | 528 / 2.37M / 572, 22.7 MB written | every stored result | #1107 |
| `discardFailedMutation`, on the store as launched | the refused-write recovery, up to 32 per sweep (launch, after each Stop) | 57 / 278,745 / 67.5, gate 58.5 | 112 / 585,459 / 139.5, gate 111.7 | every resident fact and the outbox | #1103 |
| same, after the whole `$files` list was loaded (130k resident facts) | same | 712 / 1.33M / 318, gate 820, 16.9 MB written | 1,732 / 4.45M / 1,077, gate 1,746, 98.5 MB written | same | #1103 |
| `failedMutationSupersessions()` | after each refusal (at most one per 2 s), Sync view every 5 s | 54 / 170,672 / 92.9 | 218 / 682,225 / 367.7 | every later write of each refused write's slots | #1106 |
| `failedMutations(limit: 500)` | after each refusal | 22 / 96,698 / 17.8 | 50 / 291,737 / 53.7 | its limit (each row decoded whole) | #1106 |
| `failedMutations()` | CLI | 22 / 96,627 / 17.7, gate 38 | 63 / 386,811 / 70.9, gate 67 | every failed row | #1106 |
| `failedMutations(limit: 50)` | the Sync view (1,000) | 10.0 / 29,169 / 5.4 | 4.5 / 29,169 / 5.4 | its limit | budget |
| `pendingMutationCount()` | every 5 s, session health | 0.01 / 36 | 0.00 / 36 | pending rows only (an index count) | budget |
| `connectionStatus()` | status streams | 0.02 / 67 | 0.02 / 67 | nothing | budget |
| `compactLocalCache()` | daily while charging | 0.05 / 17 | 2.8 / 17 | no-op on the fixture (too few free pages); a VACUUM rewrites live pages by design | #1015, #1107 (interrupt) |

Read, not metered (each in its issue): frozen infinite-query pages re-sort and snapshot the whole namespace on each
new line (#1056); every hydrating emission re-reads every row's deferred values (#1110); unloading a closed result
copies its whole JSON and reloading rewrites it (#1107); the commit writes other queries' due result JSON under the
gate (#1109); streams reload every chunk per append and are never pruned, and the local-cache room topic loads the
whole topic before its limit (#1112); with a library share active every write copies the resident store (#1113; the
app holds none). App-side queries that grow with the account (Without Audio, title numbers, the unfinished sweep, the
media scan's unscoped reads) went to the app's own audit, #1077.

## The fix, in one paragraph

`publishStoredFileRecordsIfObserved()` reads and publishes the device's file records only while an observation of them
is open (`observeStoredFiles()` offline or local-only), after the change is written, as before; the upload still
publishes under the gate so uploads publish in the order they saved; a publish that fails is logged and leaves the
call's result alone. The red test inserts one record no reader can decode: on `347af4f6` the upload failed on it
(`DecodingError.keyNotFound`, the whole-table read); on `f83e9448` the upload, a read by id and the delete succeed, and an
open observation still receives every upload.

## Over a recording: minutes 5, 60 and 120

Each simulated minute on the phone-sized store (`RealSizeRecordingReport`, 120 minutes, the consuming app's
recording shape: 15 lines written 5 times each, every write answered by the server's refresh of the newest 64 lines,
11 uploads, one prune), Mac mini M4, release, run back to back before (`347af4f6`, the library before the fix) and
after (`f83e9448`) on a machine other agents' builds shared:

| Per recording minute | Minute 5 | Minute 60 | Minute 120 |
| --- | --- | --- | --- |
| The uploads' operation-gate time, before | 189 ms | 213 ms | 303 ms |
| after | 0.9 ms | 0.6 ms | 1.2 ms |
| The gate's whole hold, before | 910 ms | 851 ms | 1,526 ms |
| after | 815 ms | 717 ms | 649 ms |
| Process CPU, before | 2,262 ms | 2,147 ms | 3,272 ms |
| after | 2,308 ms | 2,057 ms | 1,961 ms |
| Peak footprint, before | 128 MB | 128 MB | 147 MB |
| after | 128 MB | 124 MB | 139 MB |

Before, the uploads' gate time grew with the recording (each minute adds 11 records, 5,584 by minute 120); after, it is
about a millisecond a minute. The CPU and footprint rows move within the shared machine's noise (the before run's
last ten minutes ran under other agents' load); the per-holder gate time is the direct measure. After the fix, the
largest holder is the outbox pump's claim: 402-524 ms of every minute, about 60% of the gate (#1108, #1114).

## After the audit: what shipped the same evening

Each red, then green, on the Mac mini M4, release unless the row says debug; each version pinned in the consuming app
and its Playback app on the app's main. Where each row's numbers come from: 1.9.35's "before" is report2's (fixture
version 2, as in the table above) and its "after" report3's (version 3); 1.9.36 is `OutboxClaimScaleTests` on version
3 at a hundredth of the phone's size; 1.9.37 is a race test, with no fixture; the tail check is
`OutboxSupersessionSchemaCostTests` on synthetic schemas of 16 and 2,283 attributes, with no fixture; the delivery row
is #1076's exercise and the discard row the budget run (report3 for the 1.7 s), all on version 3 at the phone's size.
(Labels corrected after the tags; the numbers are unchanged.)

| Version | Fix | Before | After |
| --- | --- | --- | --- |
| 1.9.35 | uploads, reads by id, deletes and evictions read the file records only while observed (#1072) | upload 16.8 ms, 107,142 allocations | 0.07 ms, 237 |
| 1.9.36 | the pump's candidate read and continuation check search a partial index of claimable rows (#1108) | 3,218 SQLite steps beside 400 refused writes | the same as beside 7 (74) |
| 1.9.37 | the transaction-id interner every index copy shares takes a lock (#1141, a data race) | segmentation fault in the race test | passes, 3 of 3 under Thread Sanitizer |
| 1.9.38 | a write's tail check reads only its own attributes (#1108) | 1.6 MB allocated per write (debug) | flat across schema sizes |
| 1.9.38 | the delivery's overlay check seeks its flag; the tail read finds the newest id in an index (#1108, #1114) | 1,866 KB of the outbox read per write in delivery | under the exercise's threshold |
| 1.9.38 | a refused write that left no effect is discarded by its row (#1103) | 112 ms on the launch-time store, 1.7 s after a whole `$files` load | 0.33 ms at both sizes |

Over a recording's first ten minutes the claim's share of the operation gate went from 569 ms a minute (1.9.35) to 90
ms (1.9.38), and the gate's whole hold from 898 to 306 ms. The partial index costs two log frames (8 KB) per write, a
page on the save and one on the claim (#1076's `eachStepOfALiveWrite`: 36 outbox frames per write, 34 before); #1115
proposes a layout that serves the claim without it.

## Next steps, as a performance and isolation expert would take them

Posted on #1072, measured where the numbers above allow:

1. **Split the one serial operation gate.** Today one gate orders every write, server apply, prune, discard and most
   reads. In a recording minute at the phone's size it is held 650-900 ms, and 402-524 ms of that is the outbox
   pump's claim, which visits all 663 refused writes after every write and acknowledgement (#1108, #1114); a discard
   holds it 112 ms to 1.7 s (#1103), and before #654 a prune held it 6 s. First take the claim off the whole outbox
   (its query plan searches by claim state alone and sorts: split it into its two indexed branches, or normalize the
   legacy rows so its `OR` goes away). Then give the store one writer and let readers run beside it where SQLite's WAL
   allows (the local reader already reads on its own connection, #1006): reads that only need a consistent snapshot
   (`failedMutations`, `storageSnapshot`, `localStoredFiles`, the refusal reads, `connectionStatus`) take no gate,
   and the writer holds the gate only for its commit.
2. **Chunk long work so it yields.** A prune, a discard, a compaction and a launch's result load each hold the gate
   for their whole run; batches of a bounded size (the prune already batches, #654) with a yield between them, and
   priority for interactive writes, bound the longest wait of a write to one batch.
3. **Use a small lock where an actor hop costs more than the work.** Counters, the gate's own bookkeeping, observer
   registries and status caches (`InstantSnapshotObservers.activeCount`, the pump's ready flag, the connection status)
   are a few loads and stores; an actor hop for each costs more than the work. `OSAllocatedUnfairLock` holds them
   without a suspension (the package's floor, macOS 14, is below `Mutex`'s). The upload fix is the pattern: the
   expensive read now happens only when an observation exists, behind one cheap check.
4. **Decode server results as a stream into compact storage.** A frame is parsed into one `InstantLiveJSONValue` tree,
   then operation arrays, then indexes: about three copies of a result's bytes at peak, and the 27 MB `$files` answer
   decoded whole (#1109). A streaming decoder over the frame's bytes that emits triples straight into the store's
   interned representation removes two copies and the tree's allocations (the fixture's 128-line refresh allocates
   18 MB at the phone's size).
5. **Pay for the schema once.** A 32-line local read retires 3x the instructions with 2,283 attributes than with 571,
   an observation's first emission 2.6x, a one-row `queryOnce` holds the gate about 3x longer: each builds an attribute
   store of the whole schema per call, each send a resolver, each refresh three nested-limit maps, each `transact` a
   2,283-entry map (#1111, #1108). One indexed attribute store per attribute revision, as upstream's `_setAttrs` keeps
   one per session.
6. **Swift 6 strict concurrency is already on.** The package declares `swift-tools-version: 6.0`, so every target
   compiles in the Swift 6 language mode with complete data-race checking, plus `NonisolatedNonsendingByDefault` and
   `InferIsolatedConformances`; keep `@unchecked Sendable` to types with a documented lock, as the fixture's are.
7. **Keep counting in CI.** The budgets fail on a four-fold growth; add an operation to them with every fix, and lower
   a ceiling when a fix lowers its cost, as an allocation-counting suite does.
