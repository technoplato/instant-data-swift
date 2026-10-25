# Storage, disk and network audit (#1076), 2026-10-24

What instant-data-swift writes to disk, reads back, syncs, and sends over the socket for each logical write while a
recording runs, measured the way SQLite's author would measure it: bytes and pages written per logical write, fsyncs
per hour, the store file after an hour, and bytes on the wire per change. Each finding has its place in the code, how
often it runs while recording, what it costs today (measured, or marked not measured), a design, and the design's
saving written as a hypothesis with the exercise that will measure it.

Asked for on 2026-10-24 (Claude chat, 15:52 EDT): "Can you actually dispatch some auditing agents to find any anti
patterns and design solutions with hypothesized savings and then write real exercises of the poor hot paths". Sibling
audits: #1072 (cost that grows with the store; it owns the shared real-size fixture), #1074 (concurrency), #1075
(memory), #1077 (the app). Earlier work this builds on: #653 (per-write cost on 1.9.8), #1015 (free pages, VACUUM).

## Bottom line

**One logical write (a transcript line's revision: 2.25 KB of facts) makes SQLite write 62.5 write-ahead-log pages
(251 KB) plus 29 KB of checkpoint into the database file: 125 times the data.** Over a simulated hour at 90 writes a
minute (#653 saw 90-145 a minute on the phone) SQLite wrote 1,540 MB for 11.8 MB of facts, 1,729 MB reached the
drive, it asked for 1,039 full fsyncs, and 759 MB came over the socket (decompressed) against 6.1 MB sent.

**The worst cost is not a write: on a phone-shaped store every claim reads the whole outbox.** The delivery columns
were added to `instant_outbox` after the transaction body, and 663 refused writes stay in the table forever, so the
claim's candidate query walks every row's overflow pages: 3,711 pages (14.5 MB) per claim on the phone's own store
copy, 33 pages if the bodies lived in their own table. Two claims run per write.

| # | Anti-pattern | Runs while recording | Cost now (measured) | Hypothesized saving | Issue |
| --- | --- | --- | --- | --- | --- |
| 1 | Every claim and echo reads every outbox row's body | 2 claims and 1 echo per write | phone copy: 14.5 MB read per claim; phone-shaped store: 416 MB read and 231 ms CPU per write | claim 3,711 -> 33 pages (measured at SQL level); CPU per write under 10 ms | #1114 |
| 2 | The outbox row's life rewrites up to 14 b-trees four times | save, claim, ack, echo | 34.0 of 62.5 frames per write (54%); on a 19.9 KB row a claim dirties 9 pages and an ack 11 | 34 -> about 22-24 frames per write; 1-2 pages per claim and ack | #1115 |
| 3 | The server restates the whole 256-line page on every write and the client re-reads its stored copy | 1 echo per write | 126 KB received, 895 triples restated, 257 KB read, 6.8 ms CPU per write for 9 changed facts | 16-line live page: 12.6 KB, 1.6 ms (measured in the exercise model) | #1116, #1117 |
| 4 | Checkpoints at Apple's defaults | about 6 a minute | 1,039 full fsyncs (2.0 s on the Mac mini), 347 log truncations and 159 MB of checkpoint copies an hour | fsyncs -76% (4,000 frames) to -94% (16,000) in a replay; bytes written -2% | #1118 |
| 5 | Server-apply staging tables in temp files | every echo | 207-224 KB of temp writes and 2.3 truncates per write on the phone-shaped store | none | #1119 |
| 6 | A re-saved entity rewrites every fact (`INSERT OR REPLACE`) | every save | 6.8 frames per write on the fact table and its key; 9-15 pages per line on the phone copy | 3 pages per line in place (measured at SQL level) | #1120 |
| 7 | Each fact is stored twice, in a rowid table with a separate key index | every fact | the phone's facts: 121 MB | 71 MB without the copy, 44 MB WITHOUT ROWID (measured at SQL level) | #1121 |
| 8 | Closing a query makes the next prune copy its whole result aside | the first prune after queries close | 61.7 MB of log, 141 MB read, 0.8-1.1 s CPU for 47 results (phone-shaped) | the copy, about 41% of it | #1122 |
| 9 | A changing query's whole result JSON is rewritten | about twice a minute | 49 pages (202 KB) per rewrite of a 186 KB result | rows only, no blob | #1123 |
| 10 | No production count of bytes on the wire | always | the phone's bytes per change cannot be read from its logs | a measurement, not a saving | #1124 |
| 11 | A stream file's resume fetches the whole file again | each stream resume | not measured | the unseen tail only | #1125 |

The rest (uploads, downloads, reconnects, free pages, compression) is under "Smaller, upstream parity, or ruled
out" at the end.

## How it was measured

**Counters.** `Tests/InstantSwiftDataCoreTests/RealSize/StorageIOCounters.swift` registers a pass-through SQLite VFS
in front of the system's `unix` VFS. Every call goes to the real file unchanged; the shim counts, per kind of file
(database, write-ahead log, temp, statement journal): write calls and bytes, reads, syncs and full syncs and the time
spent in them, truncates and deletes; the page behind every write-ahead-log frame (Apple's SQLite writes a frame's
24-byte header and its page in one 4,120-byte call, so frame boundaries are read inside each write); every page a
checkpoint copies into the database; and every whole page read from the database file. `dbstat`, read on a connection
of its own, maps each page to its table or index. The process's own `proc_pid_rusage` gives CPU time, logical bytes
written and the bytes its I/O wrote to the drive.

**Exercises.** `Tests/InstantSwiftDataCoreTests/RealSize/StorageIOExercises.swift`, run only with
`STORAGEIO_EXERCISES=1`; each prints `STORAGEIO <exercise> <step> key=value` lines in a fixed order, so a run before a
fix and a run after it diff line by line.

| Exercise | What it drives | Size |
| --- | --- | --- |
| `theCountersSeeWhatSQLiteWrites` | the counters' self-check (always runs) | 1,000 rows |
| `eachStepOfALiveWrite` | Scribe's line writes (3 interims, the final, the summary, the duration tick), each saved, claimed, acknowledged and echoed by `FastDrainServer`; each step measured on its own | 300 writes on a 7,000-line store (119,893 facts), a 256-line transcript page |
| `theStoreOverASimulatedHour` | the same writes at 90 a minute for 60 minutes, the prune once a minute; the file every 5 minutes | 5,400 writes |
| `liveWritesOnThePhoneShapedStore` | Scribe's writes delivered by the live session itself on #1072's phone-shaped store (`RealSizeFixture`: 9,455 files, 4,264 upload records, 663 refused writes, 48 open and 355 closed queries); every frame both ways | 250 writes |
| `checkpointSettingsOnALiveWritePattern` | a live write's four transactions replayed on a scratch store under each checkpoint setting (the store's own connection cannot be configured from a test) | 2,000 writes per setting |

`scripts/storage-io/phone-store-pages.sh <copy of a store> <scratch>` measures single writes at SQL level on a copy of
a real store (the copy is made inside the scratch directory; the input is never written). It was run on a local copy
of the phone's store pulled 2026-10-24 (174,817 facts, 119,413 pages, 47% free); that store is private and is not in
the repository, only the counts it produced.

**Where.** Mac mini, Apple M4, 16 GB, macOS 27.0, Xcode 27.0 beta (27A5194q), Apple SQLite 3.54.0, release build
(`swift build -c release -Xswiftc -enable-testing`, nice 10). Apple's SQLite build: `DEFAULT_WAL_SYNCHRONOUS=1`
(NORMAL in WAL mode), `DEFAULT_CKPTFULLFSYNC` (checkpoint syncs are `F_FULLFSYNC`), `DEFAULT_JOURNAL_SIZE_LIMIT=32768`,
`DEFAULT_WAL_AUTOCHECKPOINT=1000`, `TEMP_STORE=1` (temp tables in files), `DEFAULT_CACHE_SIZE=2000`. The iPhone was not
measured: every number here is the Mac mini's unless it says otherwise, and how the phone's flash and cores scale them
is not measured.

**Rule.** A number is either measured (with the exercise and the line that printed it) or labeled a hypothesis or an
inference. The raw lines are in `docs/audits/2026-10-24-storage-io-baseline.txt`.

**Noise.** Bytes, pages, frames and syncs repeat within 4% between runs. CPU time does not: the Mac mini was shared
with three other audits' builds, and the final run (1-minute load 13-60) measured CPU about 1.7 times the first run's
(load 2-9) for the same work. CPU figures below come from the first, quieter run unless they say otherwise; both runs
are in the baseline file.

**The phone-shaped store, after its first prune.** The exercise holds open 1 of the fixture's 48 open queries, so its
first prune unloads the other 47 and releases their facts (the store keeps 816 facts after it). The rest of that run
measures a store whose fact table is small; its outbox, finding 1's cost, is unchanged.

## Findings, worst first

Line numbers are at main `e06f54bf`. "S" is `Sources/InstantSwiftDataCore/SQLitePersistenceStore.swift`, "R" is
`Sources/InstantSwiftDataCore/InstantRuntime.swift`.

### 1. Every claim and echo reads every outbox row's body

**Where.** `instant_outbox` was created as `(mutation_id, status, created_at_ms, json)` (S:2113-2118); every delivery
column came later through `ALTER TABLE ... ADD COLUMN` (migrations 0012-0020: S:2452-2476, S:2553-2559, S:2648-2649,
S:2698, S:2708, S:2721-2731), so each is stored after the body. A body larger than a page spills into overflow pages,
and reading any column after it walks the whole chain (the store's own comment at S:14439-14441 says so for its staging
tables). Refused writes stay in the table by design, with no count or age cap (R:15614-15617; `maximumFailedOverlays` at
S:753 bounds a server apply's work, not the table).
The claim's candidate query (`loadAutomaticDeliveryCandidateRowsWithoutTransaction`, S:14627-14660) selects
`delivery_claim_state = 'ready'`, which every refused row also is, then tests `delivery_state` on each row and sorts in
a temp b-tree. The echo's plan reads each covered row's body size with `length(CAST(json AS BLOB))` (S:6644) and
copies late columns of outbox rows into its staging rows (S:6620).

**How often.** One claim per write and a second, normally empty, claim after each acknowledgement (R:2166, R:8848; the
phone-shaped run counted 2.00 claim transactions per write), one echo per write.

**Cost now (measured).**
- The phone's store copy (SQL level, `phone-store-pages.sh` E6, cold 2 MiB cache): the candidate query reads **3,711
  pages (14.5 MB)** of a 3,914-page outbox, for 666 ready rows (663 refused, 3 confirmed). The query plan:
  `SEARCH instant_outbox USING INDEX instant_outbox_delivery_deadline_idx (delivery_claim_state=?)`, `USE TEMP B-TREE
  FOR ORDER BY`.
- `liveWritesOnThePhoneShapedStore` (the fixture's outbox is 22,727 pages, 89 MB, for 1,446 rows, about six times the
  phone's): `phone-shaped-reads deliver btree=instant_outbox readKBPerWrite=354099.0` and `echo ... 61340.5`, so about
  416 MB of the database file read per write; `phone-shaped deliver cpuMs=61.88`, `echo cpuMs=169.03`.
- `eachStepOfALiveWrite` (no refused rows): the claim reads 4.2 KB per write. The cost grows with refused rows times
  body size.
- Inference, not measured on the phone: at two claims per write, about 29 MB of page reads per write on the phone's
  store, or 2.6 GB a minute at 90 writes a minute. Most of it should come from the file system's cache rather than the
  flash, so it is paid in CPU (a `pread` and a copy per page, then SQLite decoding each record).

**Design.** Move the bodies (`json`, `lifecycle_json`, `quarantine_json`, `quarantine_lifecycle_json`) into their own
write-once table keyed by `mutation_id`, read only when a write is sent, rebased or inspected. The outbox row becomes a
few hundred bytes with no overflow, so every delivery query reads only metadata. Then keep refused rows out of the
delivery queries' indexes (a partial index whose predicate names the deliverable states as literals; bound parameters
do not let SQLite use a partial index) or move them to an archive table. One migration copies the bodies once.

**Hypothesis.** The candidate query reads 33 pages instead of 3,711 on the phone's rows (measured at SQL level:
E6 `layout=split-body pagesRead=33`); on the phone-shaped store delivery reads under 1 MB per write instead of 354 MB,
the echo's outbox reads under 1 MB instead of 61 MB, and delivery plus echo CPU falls from 231 ms to under 10 ms per
write. **Measured by:** `liveWritesOnThePhoneShapedStore` (`phone-shaped-reads deliver|echo btree=instant_outbox`,
`phone-shaped deliver|echo cpuMs`) and `phone-store-pages.sh` E6 on a store copy.

**Issue.** #1114.

### 2. The outbox row's life rewrites up to fourteen b-trees four times per write

**Where.** Ten b-trees per row: the table, its key, and eight live indexes (S:2498-2507, S:2580-2597, S:2633-2641,
S:2673-2684, S:2754-2760), plus write keys (S:2479-2486, S:2512-2513) and effect entities (S:2563-2569, S:2620-2624).
The save inserts the row and its keys (S:17679-17733, S:16511-16522, S:16562-16569); the claim updates the row twice
(S:15794-15799, then S:15829-15833); the acknowledgement re-encodes the body and writes `json` again (S:10365,
S:10368-10383); the echo's commit deletes it (S:6245-6251; write keys and effect entities by cascade) and deletes and
re-inserts the effect entities of every row it keeps (S:6293-6306).

**How often.** Every write: save, claim, acknowledgement, echo.

**Cost now (measured).** `eachStepOfALiveWrite`: `steps-outbox all outboxFramesPerWrite=34.00 framesPerWrite=62.52
outboxBtrees=14`, so 54% of a write's log (about 140 of 251 KB) lands on the outbox's own 14 b-trees: the save 14
frames, the claim 2, the acknowledgement 4, the echo 14. On the phone-shaped store, `phone-shaped-outbox all
outboxFramesPerWrite=60.68 framesPerWrite=145.70`; leaving out the one-time prune, 59 of 84 frames per write (70%).
On a real 19.9 KB row (phone copy, E2): the claim's two updates dirty 9 pages, the acknowledgement 11, a same-size
update 2.

**Design.** With the body in its own write-once table (finding 1), the claim and acknowledgement update a small row
(1-2 pages each) and never rewrite the body. Keep only the indexes the hot queries use, checked with `EXPLAIN QUERY
PLAN` on each: one covering index in delivery order, the refused-retry partial index, the watermark index. Diff the
effect entities instead of deleting and re-inserting them.

**Hypothesis.** With three indexes instead of eight and the body in its own table, the save and the echo each touch
about 9 outbox b-trees instead of 14, so about 22-24 outbox frames per write instead of 34 on the synthetic store
(about 200 KB of log per write instead of 251, -20%); on the phone's 20 KB rows the claim and acknowledgement dirty
1-2 pages each instead of 9 and 11. #653 item 6 measured -30% of the log with similar changes on 1.9.8. **Measured
by:** `eachStepOfALiveWrite` (`steps-outbox all outboxFramesPerWrite`, `steps all walFrames`),
`liveWritesOnThePhoneShapedStore` (`phone-shaped-outbox`), `phone-store-pages.sh` E2.

**Issue.** #1115.

### 3. The server restates the whole live page on every write, and the client re-reads its own copy to compare

**Where.** `refresh-ok` carries each affected query's full `instaql-result` (InstantLiveTransport.swift:572-578,
R:8792-8799, InstantLiveRefreshApplication.swift:356-359); upstream does the same. Applying it, the store reads the
query's whole stored result JSON (S:11041 -> S:17200) and every ownership row of the query (S:18103-18104 ->
S:18246-18248) and encodes every triple's value (S:18094-18101), on every echo, before diffing. The diff itself is
sound: unchanged facts and ownership rows are not rewritten (TripleIndexes.swift:833-837, S:18119-18120, S:18203).

**How often.** One `refresh-ok` per write (`steps wire receivedFrames=2.00`: the `transact-ok` and the `refresh-ok`).

**Cost now (measured).** `eachStepOfALiveWrite`, a 256-line transcript page: `receivedKB=126.07` per write (13.51 KB
when each frame is compressed alone), `refreshTriples=894.9` for `changedTriples=9.0`; the echo reads 257 KB of the
database file per write (`steps-reads echo`: instant_triples 118.7 KB, its key 52.5, instant_live_query_triples 34.9,
instant_live_query_results 28.7) and costs 6.3-6.8 ms of CPU (`cpuMs`, the two quieter runs). Over the hour:
`receivedMB=758.85`, `sentMB=6.08`. On the phone-shaped store the `refresh-ok` is 51 KB per write (largest 123 KB).

**What-if (measured in the same model).** With the live page holding the newest 16 lines (`STORAGEIO_PAGE_LINES=16`):
`receivedKB=12.60` per write (1.58 compressed), `refreshTriples=93.3`, the echo reads 0.2 KB and costs 1.59 ms against
6.83 ms in the same build at the same load. Disk
writes barely move (62.5 -> 59.6 frames per write): the outbox's life, not the page, dominates them (finding 2).

**Design.** Two independent changes. (a) Library: keep each live query's last applied result and ownership set in
memory, keyed by value, diff the frame against it, and touch SQLite only for what changed (#653 item 2). (b) App: the
recording screen observes a short tail of the transcript (the newest 16 lines) as its live query, and older lines as
pages that stop changing once written, so the server restates 16 lines per write instead of 256. (b) is Scribe's
query shape (#1077); every line still shows, and nothing in Scribe's FEATURES.md changes.

**Hypothesis.** (a) The echo reads about 0 KB instead of 257 KB per write and costs about 2 ms instead of 6.8. (b) About
12.6 KB received per write instead of 126 (measured in the exercise model; the real server's frame for a 16-line page
is not measured), so about 68 MB an hour decompressed instead of 759. **Measured by:** `eachStepOfALiveWrite`
(`steps wire receivedKB`, `steps echo cpuMs`, `steps-reads echo`), `theStoreOverASimulatedHour` (`receivedMB`).

**Issue.** #1116 (the library's in-memory diff) and #1117 (Scribe's live tail).

### 4. Checkpoints run at Apple's defaults

**Where.** The store sets no `wal_autocheckpoint` or `journal_size_limit` (S:1940-1994 at open, S:2074 sets WAL; the
values are only logged at S:18849-18851), so Apple's build decides: a checkpoint inside the commit that takes the log
past 1,000 frames, the log cut back to 32 KB after it restarts, and `F_FULLFSYNC` for every checkpoint sync.

**How often.** At 62.5 frames a write, a checkpoint every 16 writes: about 6 a minute.

**Cost now (measured).** `theStoreOverASimulatedHour`: `fullSyncs=1039` (three per checkpoint: the log before
copying, the database after, the new log header) taking `syncSeconds=2.01` on the Mac mini's SSD (about 1.9 ms each;
the iPhone's is not measured), `walRestarts=347`, each a log truncation and regrowth, and `dbWrittenMB=158.8` of
checkpoint copies. The process's I/O put `processDiskWriteMB=1729.4` on the drive for `sqliteWrittenMB=1540.2` of
SQLite's writes: the file system's own metadata and flushes on top.

**Design.** Raise `wal_autocheckpoint` (one line at open) so a checkpoint copies each hot page once per many writes:
the steps run touches only 1.7 distinct pages per write, so fewer checkpoints copy far fewer pages in total. Keep
`synchronous = NORMAL`. The lab applies it; this audit fixes nothing in the library.

**Hypothesis.** Measured in the replay (`checkpointSettingsOnALiveWritePattern`, 38 frames per write, 2,000
writes per setting, scaled to 5,400 an hour): with `wal_autocheckpoint = 4000` full fsyncs fall from 610 to 148 an
hour (-76%) and checkpoint copies from 1.0 to 0.4 pages per write (-60%); with 16,000, to 35 (-94%) and 0.2 (-80%).
Total bytes written barely move (828 -> 815 and 812 MB an hour, -2%; the drive's -5% and -6%), because the log's
appends dominate: this is a fsync fix, not a bytes fix. Not cutting the log back (`journal_size_limit = -1`)
changed nothing measurable (the same 610 fsyncs, the same drive bytes on APFS), so that half is dropped unless the
phone shows otherwise. Hypothesis for the library's own hour: about 260 full fsyncs instead of 1,039 at 4,000
frames, and fewer checkpoint copies than the replay's -60% suggests, since the library dirties 1.7 distinct pages
per write where the replay dirties 0.2 (its 158.8 MB an hour of copies is mostly pages copied again and again). **Measured by:** `checkpointSettingsOnALiveWritePattern` now (a replay: the store's own
connection cannot be configured from a test), and after the change `theStoreOverASimulatedHour` (`syncs`,
`syncSeconds`, `walRestarts`, `dbWrittenMB`). Costs to weigh: a log file of 16-64 MB stays on disk, readers search a
longer log index, and recovery after a crash replays more frames.

**Issue.** #1118.

### 5. Server-apply staging tables live in temp files

**Where.** The plan's staging tables are `CREATE TEMP TABLE` (S:14403-14525, created at every bootstrap, S:2843) and
`temp_store` is never set, so with Apple's `TEMP_STORE=1` they live in a temp file.

**How often.** Every echo: begin, stage, extend and finish each write them.

**Cost now (measured).** `liveWritesOnThePhoneShapedStore`: `phone-shaped echo tempWriteKB=223.4 tempWrites=168.3
tempTruncates=2.348` per write (207-224 KB across four runs). The synthetic steps store wrote none. Whether these writes reach
the flash on iOS (the files are deleted and may never be written back) is not measured.

**Design.** `PRAGMA temp_store = MEMORY` on the writer, if the memory audit (#1075) confirms the staging rows stay
bounded, or keep the staging in Swift memory.

**Hypothesis.** No temp-file writes or truncates per echo instead of 207 KB and 2.3. **Measured by:**
`liveWritesOnThePhoneShapedStore` (`phone-shaped echo tempWriteKB`, `tempTruncates`).

**Issue.** #1119.

### 6. A re-saved entity rewrites every fact

**Where.** `saveTripleDiffWithoutTransaction` (S:17334-17353) compares whole triples, transaction stamp included, so
every fact a write names again is "changed" (the in-memory side stamps it too, TripleIndexes.swift:842-850), and
`insertTripleWithoutTransaction` deletes a deferred attribute's row (S:17264-17267) and runs `INSERT OR REPLACE`
(S:17274-17276). On a rowid table `REPLACE` deletes the row and inserts it under a new rowid, so its key index entry
moves too. Scribe's open-segment writes name every attribute on every write (OpenSegmentWriteRecipe.swift:400-435).
#653 item 7.

**How often.** Every save: 7-21 facts per write in Scribe's line script.

**Cost now (measured).** `eachStepOfALiveWrite`: the save writes 4.15 frames on `instant_triples` and 2.69 on its key
index per write. Phone copy (E1): one line's 16 facts re-saved as today dirty 15 pages the first time and 9 after; the
same write as `INSERT ... ON CONFLICT ... DO UPDATE` (which the server path already uses, S:3391-3414) dirties 3.

**Design.** Upsert in place, and skip a fact whose value and stamp are both unchanged.

**Hypothesis.** About 2.5 frames per write on the fact table and its key instead of 6.84. **Measured by:**
`eachStepOfALiveWrite` (`steps-btrees save btree=instant_triples` and `sqlite_autoindex_instant_triples_1`), E1.

**Issue.** #1120.

### 7. Each fact is stored twice, in a rowid table with a separate key index

**Where.** `instant_triples` (S:2100-2109) keeps the fact's columns and a `json` column that repeats the whole row
(InstantStoredJSON.swift:48-58); reads select only `json` (SQLiteReadConnection.swift:62, :119). It is a rowid table
with a text primary key, so the key is stored a third time in its own index.

**How often.** Every fact written and read.

**Cost now (measured, phone copy E4 and E5).** The phone's 174,817 facts take 85.4 MB plus 35.6 MB of key index
(121 MB); without `json` 35.3 + 35.6 MB (71 MB); without `json` and WITHOUT ROWID 43.9 MB. One line's in-place upsert
dirties 3 pages today and 1 without `json`.

**Design.** Decode facts from their columns and drop `json`; consider WITHOUT ROWID on the natural key. One migration
rewrites the table once (44-71 MB written).

**Hypothesis.** The phone's fact storage falls from 121 MB to 44-71 MB, and the save's fact-table frames by half or
more. **Measured by:** `phone-store-pages.sh` E4 and E5, `eachStepOfALiveWrite` (`steps-btrees`, `steps-store`).

**Issue.** #1121.

### 8. Closing a query makes the next prune copy its whole result aside

**Where.** During a session every result that is not active is unloaded on the next prune (R:6939, S:12675-12676):
copied whole with `INSERT OR REPLACE INTO instant_unloaded_live_query_results ... SELECT ... FROM
instant_live_query_results` (S:12873-12875), deleted (S:12761; ownership rows by cascade), and the facts no remaining
result owns deleted (S:12802). The prune runs once per 64 result-carrying applies (R:1426-1428, R:4815-4821), in
batches of about 5,000 triples (R:434).

**How often.** The first prune after a screen's queries close; later prunes find nothing to unload.

**Cost now (measured).** `liveWritesOnThePhoneShapedStore` holds open 1 of the fixture's 48 results, so its first prune
unloads 47: `phone-shaped-prune line15 walFrames=15335 walWriteKB=61699.7 dbReadKB=141025.5 cpuMs=816.79`; the
prunes at lines 30 and 45 wrote nothing and took 0.5-1.1 ms. In the first run about 6,370 of those frames (41%) landed
on `instant_unloaded_live_query_results`, the copy. On the phone: not measured.

**Design.** Unload in place: keep the result's JSON where it is and mark the row unloaded (a state column), so an
unload writes the row's first page instead of copying its overflow chain. Releasing the facts is the residency model's
(#654) and stays.

**Hypothesis.** The copy, about 41% of the unloading prune's frames, goes. **Measured by:**
`liveWritesOnThePhoneShapedStore` (`phone-shaped-prune line15 walFrames`).

**Issue.** #1122.

### 9. A changing query's whole result JSON is rewritten

**Where.** `instant_live_query_results.json` holds the whole result (S:2931-2940); it is written whole at the first
save of each query after launch and then at most every 30 s while the result changes (S:18139-18146, S:18178-18187,
S:1358-1364; interval R:437 and S:1172), though its rows also live in `instant_live_query_triples` and `instant_triples`.

**How often.** About twice a minute for each query the recording changes (the live page).

**Cost now (measured).** Phone copy (E3): rewriting one 186 KB result dirties 49 pages (202 KB of log); its time-only
update dirties 1. `eachStepOfALiveWrite`: 3.52 frames per write on `instant_live_query_results` in the echo.

**Design.** Keep page info and counts in the result row and load a result from its rows, or write the JSON only when
the app goes to the background or the query closes.

**Hypothesis.** About 0.4 MB a minute less log per changing query, and its share of checkpoints. **Measured by:**
`eachStepOfALiveWrite` (`steps-btrees echo btree=instant_live_query_results`), E3.

**Issue.** #1123.

### 10. No production count of bytes on the wire

**Where.** Each frame's size is logged only at trace level (InstantLiveTransport.swift:1930-1940, :1969) and nothing
adds them up (InstantConnectionHealth.swift:14-20 keeps times and a pending count).

**Cost now.** The phone's bytes per change cannot be read from its logs, so finding 3's wire bytes cannot be measured on
the device.

**Design.** Count frames and bytes per op and direction in the session's health, and report them with the energy
summary. **Hypothesis:** none; it is the measurement. **Measured by:** a unit test of the counts.

**Issue.** #1124.

### 11. A stream file's resume fetches the whole file again

**Where.** InstantStreamFileTransport.swift:106 discards the bytes already seen after fetching from the start; up to
11 attempts, each a reconnect (InstantLiveStreamState.swift:151). **How often:** each resume of a stream file. **Cost
now:** not measured. **Design:** a `Range` request from the offset already seen. **Hypothesis:** a resume fetches only
the unseen tail. **Measured by:** not yet; it needs an exercise with a scripted file server.

**Issue.** #1125.

## Smaller, upstream parity, or ruled out

- **Reconnect receives every subscribed query's result again.** After `init-ok` the session sends a bare `add-query`
  per registered query (InstantRuntimeLiveSession.swift:869-875, InstantLiveTransport.swift:185), as upstream does
  (Reactor.js `_flushPendingMessages`, 1635-1649); the protocol has no position to resume from. Not measured. The
  levers are fewer reconnects and fewer open queries while recording, not a library change.
- **Uploads are sound.** One PUT streamed from the file (InstantStorageTransport.swift:486-488, :612-630). A failed
  upload is retried by the caller from byte 0 (no resume), and a progressive-media segment, about 24 KB, is re-sent
  whole with no attempt limit while the network is up (InstantProgressiveMediaWriter.swift:77-83, :325-337). Small;
  not measured.
- **Downloads cost two requests and are not reused.** Every authenticated download asks for a signed URL first
  (InstantStorageTransport.swift:757, :779), and `downloadStoredFile` downloads again unless the library holds its own
  copy (R:11735-11736, :11755). Not measured.
- **Whole-list file reads.** `storedFiles()` and `observeStoredFiles()` read the whole `$files` list
  (R:12063-12066, :11395, :11550), and the whole `instant_files` table is read after every file operation
  (S:11769). These grow with the account, so #1072 owns them.
- **`waitForAllPendingMutations` polls five outbox queries every 50 ms** (InstantSwiftData.swift:1461, S:7508-7550);
  each tests `delivery_state`, stored after the body, so on a store with refused rows each likely walks every body
  (inference from the schema, not measured). It is an explicit wait for the CLI, tests and diagnostics, not the
  recording path; finding 1's design fixes it too.
- **Per-write work that costs CPU, not bytes.** A write's steps are encoded, parsed back and encoded again before they
  are sent (InstantLiveTransport.swift:204-209); the reader prepares and finalizes every query and runs `BEGIN`/`COMMIT`
  through `sqlite3_exec` (SQLiteReadConnection.swift:150-155, :221-224); the same-id replay check before each save
  takes the write lock and writes nothing (S:10532).
- **Compression is on (ruled out as a finding).** `URLSessionWebSocketTask` offers `permessage-deflate` and Instant's
  server accepts it (measured 2026-10-24 on macOS 27.0 against the throwaway app, nothing sent; iOS not measured).
  The exercises' `receivedKB` is the decompressed size; `receivedDeflatedKB` compresses each frame alone, so the radio
  carries at most about that.
- **Free pages belong to #1015 (ruled out here).** Over the simulated hour the free list stayed between 92 and 620 pages
  (0.4-2.4 MB) of 17,400-20,508, so the recording's own writes reuse pages. The phone's 47% free pages are history that
  `compactLocalCache`'s VACUUM (#1015) gives back.
- **Not attributed.** The process's logical writes in the hour were 32 MB more than SQLite's write calls
  (`processLogicalWriteMB=1572.5` against `sqliteWrittenMB=1540.2`; 36 MB in the first run). The library's diagnostics
  file is off in these runs (`INSTANT_SWIFT_DATA_LOG_PATH` unset), so it is not that; what it is was not looked into.

## Exercises and today's baseline

Run on the Mac mini from a checkout of main, release (the raw lines, with the commands, are in
`docs/audits/2026-10-24-storage-io-baseline.txt`):

    swift build -c release -Xswiftc -enable-testing --product InstantSwiftDataCoreTests
    STORAGEIO_EXERCISES=1 swift test -c release -Xswiftc -enable-testing --filter StorageIOExercises
    scripts/storage-io/phone-store-pages.sh <copy of a store> <scratch directory>

Environment knobs: `STORAGEIO_STEP_LINES` (50), `STORAGEIO_RECORDING_LINES` (7,000), `STORAGEIO_PAGE_LINES` (256),
`STORAGEIO_MINUTES` (60), `STORAGEIO_LINES_PER_MINUTE` (15), `STORAGEIO_FIXTURE_SCALE` (1),
`STORAGEIO_SETTINGS_WRITES` (2,000).

Today's baseline (final run unless noted; per logical write unless noted):

| Exercise | Line | Today |
| --- | --- | --- |
| `eachStepOfALiveWrite` | `steps all` | `walFrames=62.5 walWriteKB=251.5 dbWriteKB=29.2 amplification=125.0 walFullSyncs=0.127 dbFullSyncs=0.063` |
| | `steps save`, `claim`, `ack`, `echo` | `walFrames` 23.8, 4.5, 7.6, 26.6; echo `dbReadKB=269.7` |
| | `steps-outbox all` | `outboxFramesPerWrite=34.00 framesPerWrite=62.52 outboxBtrees=14` (save 14, claim 2, ack 4, echo 14) |
| | `steps wire` | `receivedKB=126.07 receivedDeflatedKB=13.51 sentKB=1.15 refreshTriples=894.9 changedTriples=9.0` |
| same, `STORAGEIO_PAGE_LINES=16` | `steps wire`, `steps all` | `receivedKB=12.60 refreshTriples=93.3`; `walFrames=59.5`; echo `dbReadKB=0.2` |
| `theStoreOverASimulatedHour` | `hour total` | `sqliteWrittenMB=1540.2 processDiskWriteMB=1729.4 fullSyncs=1039 syncSeconds=2.01 walRestarts=347 dbWrittenMB=158.8 fileGrowthMB=12.14 freePagesEnd=178 receivedMB=758.85 sentMB=6.08` |
| `liveWritesOnThePhoneShapedStore` | `phone-shaped-reads ... btree=instant_outbox` | deliver 339-355 MB, echo 61-79 MB, save 0.7 MB (four runs) |
| | `phone-shaped-outbox all` | `outboxFramesPerWrite=60.68 framesPerWrite=145.70` |
| | `phone-shaped deliver`, `echo` | `cpuMs` 61.9 and 169.0 (quiet run), 90.5 and 208.1 (final run), 103.5 and 312.8 (load 45-60) |
| | `phone-shaped echo` | `tempWriteKB=223.4 tempTruncates=2.348` |
| | `phone-shaped-prune line15` | `walFrames=15335 walWriteKB=61699.7 dbReadKB=141025.5`; lines 30 and 45: `walFrames=0` |
| `checkpointSettingsOnALiveWritePattern` | `settings <setting>` | `fullSyncsPerHour` 610, 610, 148, 35; `checkpointPages` 1.0, 1.0, 0.4, 0.2; `writtenMBPerHour` 828, 828, 815, 812; `processDiskWriteKB` 159.8, 159.6, 151.7, 150.4 (Apple's defaults, no truncate, 4,000, 16,000) |
| `phone-store-pages.sh` (phone copy) | `e6-claim-candidates` | today `pagesRead=3711` of 3,914; split body `pagesRead=33` |
| | `e1-replace-*`, `e1-upsert-*` | 15, 12, 9 frames; in place 3 |
| | `e2-outbox-claim`, `-ack`, `-same-size` | 9, 11, 2 frames |
| | `e3-result-json`, `-time-only` | 49 frames (186 KB result), 1 |
| | `layout` | today 85.4 + 35.6 MB; no `json` 35.3 + 35.6 MB; WITHOUT ROWID 43.9 MB |

## Not measured yet

- Anything on the iPhone: its flash, `F_FULLFSYNC` latency, cores and cache sizes. Each issue's check on the device is
  the lab's.
- The real server's `refresh-ok` for a 16-line page (finding 3's what-if is the exercise's model of the frame).
- Reconnect bytes, download and stream-resume bytes (no exercise yet).
- Whether temp-file writes (finding 5) reach the flash.
- The phone-shaped exercise with all 48 of the fixture's open queries held open, as Scribe holds its screens' queries
  (the fixture builds those plans inside its generator; exposing them is a request for #1072).
- The 32-36 MB an hour the process writes beside SQLite.

## Fixes and what they measured (fix-storage-1076)

Each row is measured on the Mac mini (M4, release) with this audit's exercises on the synthetic 7,000-line store,
before (main) and after (the fix) in the same session; the raw lines are in
`docs/audits/2026-10-24-storage-io-fixes.txt`. Nothing here is measured on the iPhone.

| Issue | Change | Before | After | Status |
| --- | --- | --- | --- | --- |
| #1118 | the writer checkpoints every 4,000 frames (`56538ac5`) | `hour total fullSyncs=1069 checkpoints=356 syncSeconds=1.58 sqliteWrittenMB=1577.3 processDiskWriteMB=1773.8 powerLossReachLines=3` | `fullSyncs=268 checkpoints=89 syncSeconds=0.47 sqliteWrittenMB=1514.3 processDiskWriteMB=1573.6 powerLossReachLines=11` | landed; criterion (under 300, no more bytes) met |
| #1124 | the live socket counts frames and bytes by op and direction, a minute's summary in the log (`887f3bb2`) | no count | `InstantWireMeterTests` (a loopback WebSocket round trip) | landed |
| #1115 slice 1 | the write-key and effect-entity tables WITHOUT ROWID; one delivery index for the deadline and candidate ones (`c343c563`) | `steps-outbox all outboxFramesPerWrite=36.00` (save 15, claim 3, ack 4, echo 14); `steps all walFrames=64.5` | `30.00` (12, 2, 4, 12); `58.5` | landed; the criterion (24) needs the bodies' own table and partial indexes |
| #1121 with #1120 | each fact stored once: WITHOUT ROWID on its key, `json` computed when read; re-saved facts upserted in place (`c9403d9e`) | phone copy: `instant_triples` 87.0 MB + key index 40.1 MB = 127.1 MB; mini: save `instant_triples 4.16` + key `2.66`; `walFrames=58.5`; store 68.0 MB | phone copy (the library's bootstrap): 40.7 MB, 174,817 facts identical; mini: `2.87`, no key index; `54.9`; 22.4 MB | landed; #1121's criterion (75 MB) and #1120's (3 frames) met |
| #1123 | a changing result's JSON written at most every 5 minutes, not 30 s (`ea51a8d8`) | `steps-btrees echo btree=instant_live_query_results framesPerWrite=3.90`; `walFrames=54.9`; hour `sqliteWrittenMB=1268.8 dbWrittenMB=82.8` | `1.00`; `51.9`; `1157.7`, `40.2` | landed; criterion (under 1) not met: each refresh's count and time update stays |
| #1125 | a resumed stream append asks only for the unseen bytes, Range requests the server confirms (`76ef174a`) | a resume fetches every file whole (`InstantStreamFileTransportTests`: 10 bytes for 2 unseen) | 2 bytes | landed; not measured against a real server |
| #1119 | measured; tests only (`375beb42`): the baseline's echo temp writes were the temporary database's rollback journal; on main no measured echo stages or writes a temporary file | `phone-shaped echo tempjournalWriteKB=222.3 tempjournalTruncates=2.324` (baseline tree with the temp kinds, laptop) | none: p1 (phone-shaped, mini); an echo with the next write saved and a backlog's first echo (t1119o, mini) | criterion met on main; the commit that stopped the staging is not identified; no source change |
| #1115 slice 2 | the blocker, effect normalization and delivery metadata indexes partial on the rare states they find, their queries naming the same literal predicates (`12f487e1`) | laptop: `steps-outbox all outboxFramesPerWrite=30.00` (save 12, claim 2, ack 4, echo 12); `steps all walFrames=51.9`; hour `sqliteWrittenMB=1157.8 fullSyncs=211`; phone-shaped outbox `32.33` | `23.00` (save 9, claim 2, ack 3, echo 9); `44.9`; `1006.5`, `184`; `24.93` | landed; criterion (at most 24) met |
| #1120 alone | the upsert on the old rowid table | `4.16`, `2.67`; echo `1.76`; `64.5` | `4.38`, `2.67`; echo `1.32`; `64.9` | not landed alone: the recording's hot rows sat on the table's last page under REPLACE |

The simulated hour with #1118, #1115's slice 1 and #1121 together, against main before them (mini, synthetic store):
SQLite bytes 1,577 -> 1,269 MB (-20%), drive bytes 1,774 -> 1,281 MB (-28%), full fsyncs 1,069 -> 226 (-79%), checkpoint
copies 159.8 -> 82.8 MB, the store's growth 12.0 -> 3.5 MB an hour, a power loss's reach 3 -> 13 lines.
With #1123 as well: SQLite bytes 1,158 MB (-27% against main), drive bytes 1,170 MB (-34%), full fsyncs 211 (-80%),
checkpoint copies 40.2 MB (-75%), log frames per write 51.9 (64.5 on main).
With #1115's slice 2 as well (the laptop, whose run of the tree before it matched the mini's within 0.1 MB): SQLite
bytes 1,006.5 MB (-36% against main's 1,577), full fsyncs 184 (-83% against 1,069), log frames per write 44.9 (64.5).

What the power-loss reach means: `synchronous = NORMAL` syncs the log only at a checkpoint, so a power loss (not an app
crash) can take the commits since the last one; the store opens consistent either way
(`StorageIOExercises/aPowerLossWithALongLogKeepsEveryWriteTheLastCheckpointSynced`, power-loss images built from the
VFS shim's journal of unsynced writes). At the recording's 15 lines a minute that is 44 s of writes instead of 12.
