# Memory audit (#1075), 2026-10-24

What instant-data-swift allocates, keeps and peaks at while Scribe records, measured the way an allocation-counting
test measures it: heap allocations and bytes per operation at the phone's real size, what each operation leaves behind,
the transient high-water mark, and the process footprint over a two-hour recording at minutes 5, 60 and 120. Each
finding has its place in the code, how often it runs while recording, what it costs today (measured, or marked not
measured), a design, and the design's saving written as a hypothesis with the exercise that will measure it.

Asked for on 2026-10-24 (Claude chat, 15:52 EDT): "Can you actually dispatch some auditing agents to find any anti
patterns and design solutions with hypothesized savings and then write real exercises of the poor hot paths". Sibling
audits: #1072 (cost that grows with the store; it owns the shared real-size fixture and meter), #1074 (concurrency),
#1076 (storage, disk and network). Known before this audit: a 27 MB server result decoded whole on build 121; the
phone's footprint while recording is 1.15-1.32 GB, about 900 MB of it the speech model (not this library), and the rest
grew from 336 to 401 MB over 70 minutes on build 123.

## Bottom line

**The worst single event is reading the account's whole file list: one `$files` answer (9,455 files, 75,640 facts)
peaks at 249 MB of live heap, allocates 2.3 GB and leaves 107 MB resident** (E02), and `storedFiles()` peaks at 181 MB
and allocates 1.5 GB per call (E11). Build 123 sent that query from `deleteStoredFile(id:)` while recording (fixed in
v1.9.34, 607d64bf); no caller is known on v1.9.34, but both public calls stay unbounded. The phone's resident set jumped
to 148,700 facts at minute 75 of a two-hour recording; this answer's 75,640 facts are the likely cause (inference, not
measured on the phone).

**The steady cost is churn, not retention: per write and per refresh the library allocates tens of megabytes to
change a few facts.** A refresh of the 64-line live window allocates 21.9 MB (23,555 allocations) whatever changed in
it (E03; about 19 a minute while recording, ~420 MB a minute); an interim write 25.7 MB (E04; 14 a minute, ~365 MB a
minute, most of it reading every queued write's body, #1108); a new line shown in the window 45.8 MB end to end (E05).
Scribe's own diagnostics setup adds 2.6 MB per write (E09). None of this stays, but it is CPU and allocator pressure
on every line spoken, and freed pages do not all go back.

**Retention grows with what the recording writes: +12.1 MB of heap an hour in the two-hour replay**, while its
resident facts grew 56,109 -> 63,427 -> 71,211 at minutes 5, 60 and 120 (the phone measured 47,162 -> 60,273 ->
72,626). Each added fact costs about 1.5 KB of heap in the replay and each fact loaded at launch 737 B (E07): the hot
store keeps every row written in the session, gives each distinct indexed value a 64-slot set, and copies entity ids.
At the phone's write rate (213-238 facts a minute against the replay's 130) that would be about 20 MB an hour
(inference). The phone's 65 MB over 70 minutes is three times that; the rest is not attributed by this audit
(speech-side and app-side memory, fragmentation, the `$files` spike are candidates, none measured here).

**Fixed while this audit ran:** every upload re-read and decoded all 4,264 file records (E08: 106,947 allocations and
17.9 MB per upload on main d937ce43); #1072's f83e9448 took it to 118 allocations and 31 KB, measured by the same
exercise.

## Fixed since the audit

Each fix lands red then green on main; before and after come from the same exercise on the same day, Mac mini, release,
fixture version 3 (phone shape), the before on main as it stood when the fix started.

| Issue | Finding | Commits | Exercise | Before | After |
| --- | --- | --- | --- | --- | --- |
| #1152 | M13 | red `ccdbc47b`, green `33c5c042` | E04 final line on the 2,318-line recording vs a new recording | 7,255 vs 6,786 KB (+6.9%) | 6,636 vs 6,456 KB (+2.8%) |
| #1147 (steps 1-4) | M2, M9 | `79707ad5`/`a9751099`, `63b65c80`/`553cb332`, `40280360`/`3e787d2d`, `164131cd`/`560540fe` | E03 64-line refresh, one line changed | 23,947 allocations, 22,769 KB | 11,160 allocations, 11,411 KB |
| #1153 | M14 | red `6d765ee0`, green `0744cfb1` | E04 final line, store prepares per write | 2.0 | 1.0 |
| #1148 | M4 | red `9d4ca094`, green `97ed60bc`, E09 fix `63920cb0` | a dropped debug entry, allocations (calling thread) | 18 | 0 |

- **#1152:** a many-cardinality slot keeps its values in a `ShardedDictionary` (one plain dictionary up to 32 entries,
  then 64 shards), so a line linked to a long recording copies one shard of the link set; `insert` writes a derived
  index shape only when it changes. The cost test (`LinkSetWriteCostTests`, one thread, one line prepared on a copy):
  256,368 -> 31,842 bytes at 2,318 links (a new recording 28,687), 177,736 -> 12,250 bytes at 2,283 attributes (equal
  to 16).
- **#1147, three steps so far** (criterion not met yet): the nested-limit pass takes a shortcut for a query with no nested
  include (it built maps of the schema and the page twice per refresh, about 6.5 MB); hydration looks up only its
  configured attributes (three groupings of the schema per emission); the frame parser sizes arrays once, reuses its
  escape buffer and shares a frame's repeated ids (E01's 64-line frame 7,124 -> 2,339 allocations, the `$files`
  answer 548,414 -> 160,779). An allocation-site recording (`MemorySiteExercises`) attributes what remains.
- **#1147 step 4:** a refreshed page's ownership diff compares 128-bit fingerprints of the rows' bytes and the values'
  stored text; only rows that leave or join become strings (a 64-line page's diff 5,137 -> under 300 allocations).
- **#1148:** a diagnostics entry the floor drops builds nothing, and redaction makes no string per ASCII key.
  **Correction to M4 (measured):** E09's "no sink" pass had a handler (every session registers `RealSizeApplyLog`), and
  the +2.6 MB a write for Scribe's setup does not reproduce on main in any exercise order, this audit's included (+4 to
  +81 KB, inside E09's run-to-run spread of about 700 allocations a write). What removed it is not traced.
- **#1153:** a delete in a namespace whose delete reaches no deferred attribute needs no throwaway preview, so a finished
  line (its delete of a `liveLines` row) is prepared once.
- **Harness corrections (#1147):** the apply waiter no longer polls inside a counted pass, E04, E05, E09 and E10 build
  each line before their passes, and one-thread cost tests take turns on the counter's tally.

## How it was measured

**Exercises.** `Tests/InstantSwiftDataCoreTests/RealSize/MemoryExercises.swift` (E00-E14, run only with
`INSTANT_MEMORY_EXERCISES=1`) and `MemoryLongRunReplay.swift` (the two-hour replay, `INSTANT_MEMORY_REPLAY=1`; a
three-minute smoke test on a tiny store always runs). Each prints `MEMORY <exercise> <label> key=value` (or
`MEMORY-REPLAY`) lines in a fixed order, so a run before a fix and a run after it diff line by line.
`scripts/memory-exercises/run-memory-exercises.sh --log <path>` builds in release and runs them.

**Counters** (#1072's `RealSizeMeter`): `allocations` and `allocatedKB` come from libmalloc's logger hook (every malloc,
calloc and realloc in the process while a pass is counted); `retainedKB` is the heap the zones hold after the counted
pass minus before it (`malloc_zone_statistics`), per iteration; `peakLiveKB` is the highest the pass's allocated-minus-
freed bytes rose above its start; `footprintPeakMB` is the process's `phys_footprint` high-water mark. A metered
operation runs a warm-up, a timed pass and a counted pass of the same iterations, and prints per-iteration values.
`op.<name>` and `opMs.<name>` are the library's own `InstantEnergyMeter` counts and wall time per iteration, so a cost
names the work behind it. The counts are process-wide, so the suites run serialized and alone.

**What runs.** A session copies #1072's generated store of the phone's shape (352 recordings, 8,712 transcript lines,
9,455 account files, 4,264 upload records, 663 refused writes, 48 open and 355 closed queries, 2,283 attributes) and
boots the runtime the way Scribe configures it: transcript `text` and `wordsJSON` deferred to disk until a selected page
hydrates them, a local lookup index of a recording's lines. The server is the audit's own (`MemoryReplayServer`): it
keeps no frame history (so a long run's growth is the library's) and hands the runtime JSON text frames, which the
production decoder parses. Writes have Scribe's shapes (`MemoryScribeWrites`): typed `update`/`updateExisting` inserts,
each finished line linked to its recording through `recordings.segments`, the line in progress deleted.

**Three harness effects found and removed on the way** (each measured the harness, not the library):
- #1072's fixture writes rows as `.merge`s. A merge onto a row the store does not hold changes nothing in memory
  (TripleIndexes.swift:4953-4960, as upstream `mergeTriple`), so a new line was never materialized until the server
  echoed it, and the link set, cascade preview and new index entries never ran. The exercises write inserts.
- Text transaction ids. The library covers a write by a refresh only when both ids are integers
  (`serverApplyWatermarkPredicate`, SQLitePersistenceStore.swift); with text ids every acknowledged write stayed an
  optimistic overlay that each apply peeled and replayed. On the first exercise server a new line shown in a 64-line
  window cost about 2.4 million allocations and 132 store prepares (0.05 scale); with integer ids, 112 thousand and 3.
  #1072 fixed its own server the same way in fixture version 3 (4dac9e18).
- The library's periodic prune releases every stored result nobody observes: a replay with only the three
  recording-screen queries open dropped the resident set from 54,738 facts to 2,883 by minute 5, where the phone keeps
  about 47,000. The replay keeps the store's 48 open queries observed, as Scribe's screens keep about 60 open.

**Where.** Mac mini, Apple M4, 16 GB, macOS 27.0, Xcode 27.0 beta, release build (`swift build -c release -Xswiftc
-enable-testing`, nice 10). The iPhone was not measured: every number is the Mac mini's, from the generated store, unless
it says otherwise. The replay compresses recording time (each minute's work runs as fast as the runtime takes it, while
the session clock moves 60 s a minute, so time-based policies act as on the phone); growth that depends on wall time
alone does not show.

**Rule.** A number is either measured (with the exercise that printed it) or labeled a hypothesis, an estimate or an
inference. Estimates from reading code are the auditors' and say so. The raw lines are at the end.

## The anti-patterns, worst first

Costs are per operation at the phone's size (E-numbers are the exercises), measured on the Mac mini; "a minute" is the
phone's measured rate over a two-hour recording times the measured cost (an estimate of the product, not a measurement
of the phone). Line numbers are on main 9b5107e3.

| # | Anti-pattern | Runs while recording | Cost now (measured) | Hypothesized saving | Issue |
| --- | --- | --- | --- | --- | --- |
| M1 | A whole `$files` answer is decoded, applied and kept resident whole | any whole-list read (build 123: once a minute from a delete; none known on v1.9.34) | E02: peak 249 MB, 2.3 GB allocated, 107 MB retained; E11: peak 181 MB, 1.5 GB per call | peak under 10 MB, under 1 MB left after the read | #1144 |
| M2 | Each refresh re-materializes, re-hydrates and re-diffs the whole page | every window refresh (~19/min) | E03: 21.9 MB, 23,555 allocations per 64-line refresh; ~333-434 allocations per row at any page size | under 5,000 allocations for a one-line change; flat in page size | #1147 |
| M3 | An interim write reads every queued write's body to test supersession | every interim (~14/min) | E04: 25.7 MB per interim against 3.7 MB per heartbeat; 29.4 ms in the claim | the heartbeat's cost | #1108, #1114 |
| M4 | Diagnostics build every message and metadata before the level check | every write, apply and emission | E09: +2.6 MB and +221 allocations per write at Scribe's `.info` with 5 handlers | within 5% of no sink | #1148 |
| M5 | A new line rebuilds the window instead of splicing it in | every finished line (~9.5/min) | E05: 45.8 MB, 119,787 allocations per line; ~17 MB beyond the write and the refresh | the write plus the refresh | #540 |
| M6 | Every resident fact costs ~737 B and every row written stays resident | every row-creating write | E07: 38.4 MB for 54,720 facts; replay: +12.1 MB heap an hour, ~1.5 KB per added fact | under 400 B per fact; resident set flat once the window fills | #1146, #1145 |
| M7 | Observing a query does schema-wide work and a closed one leaves state behind | 3 media-scan looks a minute, new query keys | E06: 14.1 MB and 5,144 allocations per observe (1.6 MB at 170 attributes); 3,151 B retained per closed lease | under 1 MB per observe; under 200 B retained | #1111, #541 |
| M8 | A live page's stored result is written whole and decoded back | once per 30 s per changing query | E12: +160k allocations and +32 MB per write of a 256-line result | under 10k allocations | #1123 |
| M9 | Refresh and emission work grows with the schema, not the data | every refresh and new line | E10: +8.0 MB per 64-line refresh and +10.6 MB per new line at 2,283 against 170 attributes | equal within 10% | #1111 |
| M10 | Launch decodes every loaded result and parses facts from JSON copies | every launch | E07: 579 MB allocated, peak 52.4 MB, 648 ms | under 150 MB | #1149 |
| M11 | A local read of history builds a full index per page | 10 pages when a long recording opens | E14: 24.0 MB per 256-line page, 240 MB per open | under 4 MB per page | #1150 |
| M12 | A reconnect re-adds every query whole and keeps the old attribute tree | ~3 per 2 hours, every foreground | E13: 64 MB and 155,730 allocations per reconnect (three queries) | proportional to the answers only | #1151 |
| M13 | Each new line copies the recording's whole link set | every finished line | E04: +523 KB per line on a recording with 2,318 linked lines (7.7 MB vs 7.2 MB) | within 5% of a new recording | #1152 |
| M14 | A finished line is prepared twice (a preview only to list what its delete reaches) | every finished line | E04: 2.0 store prepares per final line, 1.0 per heartbeat or interim | 1.0 | #1153 |
| M15 | Every upload re-read every file record | ~11 uploads/min | E08: 17.9 MB per upload before f83e9448, 31 KB after | fixed | #1072 |
| N1 | A live infinite query kept `.accumulated` rebuilds its frozen chunks over the whole namespace per new line | each line while a detail page is open | not measured (the scripted server has no cursor pages yet) | the bounded path for every chunk | #540 |

Smaller ones, not measured, under "Not measured yet" below.

## The findings

Each says where it is, how often it runs while recording, what it costs now, the design, and the saving as a
hypothesis with the exercise that measures it. Frequencies come from the phone's energy ledger over one 118.8-minute
recording (builds 121-122) unless marked inferred.

### M1. A whole `$files` answer is decoded, applied and kept resident whole

Issue: #1144.

- **Where.** `storedFiles()` (InstantRuntime.swift:11392-11404) and `observeStoredFiles()` (11543-11551) run a one-shot
  query of `storedFilesQuery` (12055), which has no filter and no limit. The answer is decoded into one tree
  (InstantLiveJSONParser.swift), translated into 75,640 facts, applied to the shared hot store, written whole as result
  JSON (SQLitePersistenceStore.swift:18814-18820; 22.8 MB in E02) and read back whole (16893-16921).
- **How often.** Build 123's `deleteStoredFile(id:)` sent it while recording, from the audio chunker's compensation
  delete (#654's log, 17:31-17:36 EDT; fixed in 607d64bf, v1.9.34). Scribe's launch storage cleanup reads through the
  local reader and does not send it (the lab's correction on #654). No caller is known on v1.9.34; `storedFiles()` and
  `observeStoredFiles()` stay public and unbounded. The phone's resident spike to 148,700 facts near minute 75 matches
  this answer's size (inference).
- **Cost now.** E02 (first observation): 5,152,939 allocations, 2.3 GB allocated, peak live 249 MB, 107 MB retained
  (1,485 B per added fact), 3.0 s. A cancel followed at once by a prune released nothing (130,360 facts resident
  after). E11 (`storedFiles()`): 6,445,932 allocations, 1.5 GB allocated per call, peak live 181 MB, 2.7 s. E01: the
  15.4 MB frame alone decodes into 548,414 allocations with a peak of 2.0 times the frame.
- **Design.** Never hold the account's whole list in memory: `storedFiles()` pages `$files` (or reads by id and path,
  #1072's claimed bounded form); a one-shot read's answer is not applied to the shared hot store, or is released when
  the read returns; a large answer is decoded row by row and the frame dropped after translation (the wire auditor's
  frame pinning, InstantRuntimeLiveSession.swift:993-1029).
- **Hypothesis:** one `storedFiles()` page of 256 files peaks under 10 MB and allocates under 50 MB, and no facts of
  the list stay resident after the read; **measured by:** E11 `peakLiveKB` and `allocatedKB`, E02 `retainedKB` and
  `residentFactsAfter`.

### M2. Each refresh re-materializes, re-hydrates and re-diffs the whole page

Issue: #1147.

- **Where.** On every `refresh-ok`: the translator and the nested-limit pass (InstantLiveRefreshApplication.swift:50-55,
  177-224; InstantLiveQueryNestedLimit.swift:25, 83-89); the persisted result built as an identity array, a dictionary
  and a sorted copy, and the previous and next results indexed again for retractions and ownership
  (SQLitePersistenceStore.swift:11041-11079, 18053-18126, 18240-18292); a throwaway store copy that hydrates every
  restated row's text and words only to classify the frame (InstantRuntime.swift:3993-4025); and the hydrated emission
  that re-reads, decodes and copies every row of the page (InstantRuntime.swift:5989-6032; SQLiteReadConnection.swift:
  48-77, 186-197; DeferredValueResidency.swift:205-214, 302-355).
- **How often.** Every refresh of an open page: the 64-line live window about 19 times a minute (about 35 while
  talking), the list and title queries about 31 more.
- **Cost now.** E03, one line changed per refresh: 32 lines 13,877 allocations and 17.9 MB; 64 lines 23,555 and 21.9
  MB (18.7 ms); 128 lines 43,159 and 30.7 MB; 256 lines 85,300 and 48.7 MB (71.9 ms). 333-434 allocations per row at
  every size: the cost follows the page, not the change. About 450,000 allocations and 420 MB a minute for the live
  window alone (rate times measured cost).
- **Design.** Index the next result once and reuse it for the stored order, the retractions and the ownership rows;
  classify the frame without a store copy (deferred attributes are payload-only, so compare their values in SQL); keep
  each row's last hydrated version and hydrate only the ids the publication changed. Upstream builds each query's store
  from the answer's triples and overlays pending writes at read time.
- **Hypothesis:** a refresh that changes one line of a 64-line page costs under 5,000 allocations and under 4 MB, and
  its cost stops growing with the page; **measured by:** E03 `allocations` and `allocationsPerRow` (under 50 at 256
  lines).

### M3. An interim write reads every queued write's body to test supersession (#1108, #1114)

- **Where.** `OutboxSameEntitySupersession` (OutboxSameEntitySupersession.swift:158-217) and the pump's claim
  (#1114). Read from the code (296-342): an `update`-shaped write (first operation an insert) passes the shape check
  and reads the outbox tail; an `updateExisting` write (heartbeats, finals) fails it at operation 0.
- **Cost now.** E04 at the phone's size (663 refused writes queued): interim 20,392 allocations and 25.7 MB per write;
  heartbeat 9,803 and 3.7 MB; both spend 29.4-29.8 ms in the outbox claim. Measured, not traced: which read makes the
  interim's extra 22 MB.
- Already filed as #1108 and #1114; the memory numbers are posted there.

### M4. Diagnostics build every message and metadata before the level check

Issue: #1148.

- **Where.** `InstantDiagnostics.record` takes an eager `message` and `metadata` (InstantDiagnostics.swift:271-335); the
  server apply's gate record builds a 21-plus-key dictionary and a long message for every apply, dropped below 250 ms
  at `.info` (InstantRuntime.swift:4658-4712).
- **How often.** About 18 records per write cycle (the files and diagnostics auditor's count, inferred), each apply,
  each emission.
- **Cost now.** E09 (interim writes at the phone's size): no sink 24,401 allocations and 11.8 MB per write; Scribe's
  `.info` floor with five handlers 24,622 and 14.4 MB; `.debug` with one handler 24,928 and 17.0 MB. Scribe's setup
  adds 221 allocations and 2.6 MB per write: few, large blocks. Which records make them is not traced.
- **Design.** `@autoclosure` message and metadata (or `isEnabled(at:)` before building), the floor in an atomic, the
  server-apply builder behind the check; cap with `utf8.count`, reserve capacity in `redacted`.
- **Hypothesis:** Scribe's configuration costs within 5% of no sink per write; **measured by:** E09
  `scribe-info-5-handlers` against `no-sink` (`allocatedKB`).

### M5. A new line rebuilds the window instead of splicing it in

Issue: #540.

- **Where.** A new id cannot be spliced into an observer's result, so each observer with the recording's filter is
  rematerialized (InstantStore.swift:2105-2117, 2289-2306; TripleIndexes.swift:3291-3346), and the emission hydrates
  every row again (M2).
- **How often.** Every finished line: 9.5 a minute, 14.2 while talking.
- **Cost now.** E05, the whole path Scribe sees (the final write, its acknowledgment, the server's refresh with the new
  line first, the emission that shows it) on the longest recording (2,318 lines linked): 64-line window 119,787
  allocations and 45.8 MB per line (44 ms); 256 lines 183,739 and 73.9 MB. The write alone is 22,690 and 7.2 MB
  (E04), the refresh 23,555 and 21.9 MB (E03): about 73,000 allocations and 17 MB per line are the new member's
  rematerialization (one rematerialized observer, 64 snapshots), 4.9 store prepares and 4 hydrations.
- **Design.** Splice a new member into an ordered, limited result at its place and drop the last row; hydrate only the
  new member. Re-land #540's window test (`unheldEntityCanEnterPage`), which never reached main.
- **Hypothesis:** a new line costs the write plus the refresh, about 46,000 allocations and 29 MB; **measured by:** E05
  `new-line-64`.

### M6. Every resident fact costs ~737 B, and every row written stays resident

Issue: #1146 (the set and ids), #1145 (eviction).

- **Where.** (a) Each distinct value of an indexed attribute owns a `ShardedSet` whose first insert allocates a 64-slot
  shard array (ShardedCollections.swift:22-47; TripleIndexes.swift:676-713, 4912-4928), and every namespace's `id` is
  forced indexed (TripleIndexes.swift:363-372): about 640 B for a set of one, where a plain set was about 96 B before
  #1007's 538de961. Entity ids are not interned: a row from the server or the disk keeps about 29 copies of its 36-byte
  id (TripleIndexes.swift:4202-4219, 4925-4927). (b) Nothing evicts a row this device wrote once no result owns it: the
  only release is the prune of removed results (InstantStore.swift:3313-3335; SQLitePersistenceStore.swift:
  11216-11236), so the resident set grows at the write rate until relaunch.
- **How often.** (a) every resident fact; (b) every row-creating write: lines, media segments, chunks, events.
- **Cost now.** E07 (launch): 38.4 MB retained for 54,720 resident facts, 736.8 B per fact. The replay: heap 113.3 MB
  at minute 5, 125.6 at 60, 136.5 at 120 (+12.1 MB an hour) while resident facts grew 56,109 -> 63,427 -> 71,211 (about
  130 a minute, the phone 213-238): about 1.5 KB of heap per added fact.
- **Design.** (a) a set type that is `.one(id)` or a small `Set` until it passes about 256 members, and only then
  sharded; intern entity ids (a canonical instance per resident entity, or dense integer handles as `TxIDInterner` does
  for transaction ids); don't index the primary key in the value map. (b) A residency rule: once the server
  acknowledged a row and no open result owns it, retract it from memory at the next prune batch (it stays on disk, and
  #1006's local lookup reads it from there). Upstream keeps one store per query result plus pending writes.
- **Hypothesis:** (a) under 400 B per resident fact at launch (E07 `retainedPerFactB`); (b) the replay's resident facts
  flat once the window is full and its heap growth under 3 MB an hour (MemoryLongRunReplay `triples`, `heapMB`).

### M7. Observing a query does schema-wide work, and a closed one leaves state behind

Issue: #541 (what stays), #1111 (the schema-wide work).

- **Where.** Allocation: per-call schema work (#1111: validation against a new `AttributeStore`), and a newly sorted
  copy of the whole schema per observation (TripleIndexes.swift:39-41; InstantStore.swift:616-618) that a deferred
  selection's hydration task holds for the observation's life (InstantRuntime.swift:5846-5911). Retention: the #541
  acknowledgement maps keep every query key (InstantRuntime.swift:1338-1416; the fix never reached main) and the
  transaction id interner never compacts (TripleIndexes.swift:578-623).
- **How often.** The media scan opens and closes three looks a minute; agent replies once registered about 380 new
  keys in 16 minutes.
- **Cost now.** E06 (300 distinct queries opened and closed): 1,543,224 allocations and 4.1 GB, so 5,144 allocations and
  14.1 MB per observation at 2,283 attributes (1.6 MB at 170); 3,151 B retained per closed lease.
- **Design.** Build schema lookups once per attribute revision and share them; forget a key's acknowledgement state
  when its last lease ends (re-land #541); compact the interner past the oldest live stamp.
- **Hypothesis:** under 1 MB per observation and under 200 B retained per closed lease; **measured by:** E06
  `allocatedKB` per lease and `retainedPerLeaseB`.

### M8. A live page's stored result is written whole and decoded back (#1123)

- **Where.** The deferred write (SQLitePersistenceStore.swift:1358, 18113, 18178) encodes the whole result; the next
  refresh decodes it back (17192-17203, 16915-16920).
- **Cost now.** E12 (256 lines): a refresh with nothing due 85,290 allocations and 49.0 MB; a refresh then the write
  245,305 and 81.7 MB: the write adds about 160,000 allocations and 32 MB; a refresh right after a write costs the same.
- Filed from the storage side as #1123; the memory numbers are posted there. **Hypothesis:** with results rebuilt from
  their ownership rows, a write adds under 10,000 allocations (E12 `refresh-then-write` against `refresh-nothing-due`).

### M9. Refresh and emission work grows with the schema, not the data (#1111)

- **Where.** The nested-limit pass (InstantLiveQueryNestedLimit.swift:25, 83-89), the deferred-residency maps rebuilt
  per hydrated emission (DeferredValueResidency.swift:99-203), the resolver per send (InstantLiveMutation.swift:74-98).
- **Cost now.** E10, the same work on a small store declaring 170 and 2,283 attributes: a 64-line refresh 21,917 ->
  23,469 allocations and 13.6 -> 21.6 MB (+8.0 MB); a new line in a 64-line window 108,954 -> 113,588 and 30.0 -> 40.6
  MB (+10.6 MB).
- Filed as #1111; the numbers are posted there. **Hypothesis:** E10's `allocatedKB` equal within 10% at both sizes.

### M10. Launch decodes every loaded result and parses facts from their JSON copies

Issue: #1149.

- **Where.** SQLitePersistenceStore.swift:10810-10885 -> 17158-17176 (every loaded result decoded to find retained
  entities), 10851-10871 (every retained id bound as a parameter), 16924-17019 (each fact parsed from its JSON copy),
  1417-1502 (repair).
- **How often.** Every launch, including relaunches after the system ends Scribe.
- **Cost now.** E07: 2,377,552 allocations, 579 MB allocated, peak 52.4 MB, 648 ms for 54,720 resident facts.
- **Design.** Compute the retained ids in SQL from the ownership rows; join a temporary table instead of binding ids;
  decode facts from their columns.
- **Hypothesis:** launch allocates under 150 MB; **measured by:** E07 `allocatedKB`.

### M11. A local read of history builds a full index per page

Issue: #1150.

- **Where.** `queryLocally` builds an index for each read (InstantRuntime.swift:6406-6451, 6497-6512, 6576-6591); the
  read connection re-prepares statements and copies each batch about four times (SQLiteReadConnection.swift:178,
  187-199, 215-244).
- **How often.** When a recording's screen opens, every 256-line page of its history, newest first.
- **Cost now.** E14 (the 2,318-line recording, 10 pages): 24,292 allocations and 24.0 MB per page (14 ms), 240 MB per
  open.
- **Design.** Read the page's rows through the lookup index into the page only; cache statements by batch size; append
  column bytes into one buffer.
- **Hypothesis:** under 4 MB per page; **measured by:** E14 `allocatedKB`.

### M12. A reconnect re-adds every query whole and keeps the old attribute tree

Issue: #1151.

- **Where.** InstantRuntimeLiveSession.swift:357, 824 (an equal attribute array keeps the old raw tree); every query's
  `add-query-ok` whole (InstantLiveRefreshApplication.swift:733-790).
- **How often.** About 3 in a two-hour recording, and each time the app comes back to the foreground.
- **Cost now.** E13 (three queries open): 155,730 allocations and 64 MB per reconnect, 340 ms; 5.4 KB of heap retained.
  In the first replay (three queries open, main d937ce43) the footprint stepped up 11.4 MB at the first reconnect.
- **Design.** Replace the cached attributes when they compare equal, parse them once into one shared index; bound the
  receive queue in bytes (InstantRuntimeLiveSession.swift:382).
- **Hypothesis:** a reconnect allocates no more than its answers' decode (E13 against E01 at the same rows).

### M13. Each new line copies the recording's whole link set

Issue: #1152.

- **Where.** The line's link to its recording is one cardinality-many slot on the recording; the prepare writes it on
  a copy shared with the installed store, so each write copies every sibling (TripleIndexes.swift:542-557, 4296-4298),
  and an unguarded write of the derived-shape map copies the schema-sized map too (TripleIndexes.swift:4316; the same
  write at 4222 is guarded).
- **How often.** Every finished line.
- **Cost now.** E04: a final line on a recording with 2,318 linked lines 22,557 allocations and 7.7 MB; on a new
  recording 22,690 and 7.2 MB: +523 KB per line, growing with the recording.
- **Design.** Guard 4316 as 4222 is (a one-line change); give large cardinality-many slots a structure whose copy unit
  is small (sharded past about 256 values).
- **Hypothesis:** `final-line-long-recording` within 5% of `final-line` (E04 `allocatedKB`).

### M14. A finished line is prepared twice

Issue: #1153.

- **Where.** A write with a delete (the final deletes the line in progress) runs a full throwaway prepare only to list
  the entities it changes (InstantRuntime.swift:2596-2621; DeferredValueResidency.swift:170-184).
- **Cost now.** E04: 2.0 store prepares per final line, 1.0 per heartbeat or interim.
- **Design.** A read-only walk of what the delete reaches over the installed indexes (the logic of
  `captureDeleteStep`, InstantStore.swift:1373-1419), or a schema check that skips it when no deferred attribute can be
  reached.
- **Hypothesis:** 1.0 prepare per final line and its allocations down by the prepare's share; **measured by:** E04
  `op.storePrepare` and `allocations` for `final-line`.

### M15. Every upload re-read every file record (fixed by #1072)

- E08 at the phone's size (4,264 records): main d937ce43, 106,947 allocations and 17.9 MB per upload; main 9b5107e3
  (with #1072's f83e9448), 118 allocations and 31 KB. The exercise measured the fix.

### N1. A live infinite query kept `.accumulated` rebuilds its frozen chunks per new line (not measured)

Issue: #540 (its exercise design is posted there).

- **Where.** Frozen chunks have no limit and cursor bounds, so they skip the bounded path and materialize every
  resident entity of the namespace before filtering (InstantInfiniteQuery.swift:1975-1988, 2021-2034;
  TripleIndexes.swift `materializeOrderedSnapshots`); the starter is kept and hydrated (InstantInfiniteQuery.swift:
  1340-1358). Scribe's recording detail pages subscribe `.accumulated` with 256-line pages (Scribe main
  ScribeRecordingDetailPages.swift:201-218).
- **Cost now.** Not measured: the memory exercises' server answers no cursor pages yet. The query auditor's estimate
  (reading code): 27-100 MB allocated per new line on a fully loaded two-hour recording.
- **Exercise to build.** Cursor pages (`first`, `after`, page info) in `MemoryReplayServer`; then
  `subscribeInfiniteQuery(.accumulated)` on the 2,318-line recording, every page loaded, one new line written.

## Not measured yet

Each was found by reading code; none has an exercise yet, and none is ranked:
- The public wrappers decode every row of every emission before the newest-one buffer (InstantSwiftData.swift:2228-2240,
  2633-2638, 3879-3895); the core exercises do not use the typed layer.
- The receive queue is bounded by frame count, not bytes (InstantRuntimeLiveSession.swift:382): on reconnect every
  query's answer tree can wait at once.
- A parsed frame stays alive through the whole server apply (InstantRuntimeLiveSession.swift:993-1029).
- A transact frame is encoded twice through Foundation objects (InstantLiveTransport.swift:1568-1597); inside E04, not
  isolated.
- `instant_files` gains a row per upload and never loses one (SQLitePersistenceStore.swift:11681-11713); after #1072's
  fix uploads no longer read them, but the table grows (E08: 4,264 -> 4,275 records over its uploads).
- `newestTransactionTimeMilliseconds` walks every slot of the store per replayed write (TripleIndexes.swift:1571-1588).
- The intern cache keeps new rows' deferred text and words and is cleared all at once (TripleIndexes.swift:4378-4445).
- The startup trace never stops recording (InstantStartupTrace.swift:184-215).

## Checked and bounded

From the auditors' reading, each with its bound: the statement cache (256 idle statements); the page cache (2 MiB per
connection, released on memory pressure); the in-memory outbox (compact shells of the claimed window, at most 50
rows; nothing in memory grows with the 663 refused writes); the live session's per-mutation state (cleared on
acknowledgement, cross-generation sets capped at 4,096); the observer registries (removed when their streams end); the
publication cache (32); one-shot query bookkeeping (256); the operation gate and its #1074 timeline (nil in production);
the energy meter (fixed arrays); URLSession (one shared session, no delegate per connection); the change-key memo (512
entries, about 1.3 MB at most). The eight auditors' full reports are kept outside the repository with the run logs.

## Today's baseline

**Official run:** main 9b5107e3 (the library with #1072's f83e9448) plus the exercises as committed, fixture version 3
(phone shape), Mac mini, release, 2026-10-24 18:08-18:15 EDT. Allocated, retained and peak are per operation (retained
in KB per iteration; peak for the whole counted pass). E02, E06 and E07 are one-shot (n=1): E06's row is all 300
leases together. The `op.` and `opMs.` fields are in the raw lines.

| Exercise | Store | n | Allocations | Allocated MB | Retained KB | Peak live MB | Wall ms |
| --- | --- | --- | --- | --- | --- | --- | --- |
| E00.harness.ack-wait-idle | phone | 50 | 36 | 0.0 | 0.0 | 0.0 | 0.00 |
| E00.harness.emission-wait-buffered | phone | 50 | 18 | 0.0 | 0.5 | 0.0 | 0.01 |
| E01.decode.files-answer | phone | 3 | 548,414 | 58.9 | 0.0 | 31.1 | 48.70 |
| E01.decode.page-refresh-64 | phone | 3 | 7,124 | 0.7 | 1.6 | 0.4 | 0.88 |
| E01.decode.page-refresh-256 | phone | 3 | 28,545 | 2.8 | -0.1 | 1.5 | 3.53 |
| E02.apply.files-answer.first-observe | phone | 1 | 5,152,939 | 2,296.1 | 109,686.0 | 249.3 | 3009.93 |
| E02.apply.files-answer.cancel-and-prune | phone | 1 | 14,591 | 1.8 | -9,136.3 | 0.0 | 4.04 |
| E03.apply.page-refresh-32 | phone | 8 | 13,877 | 17.9 | 64.5 | 2.7 | 11.12 |
| E03.apply.page-refresh-64 | phone | 8 | 23,555 | 21.9 | -68.6 | 2.6 | 18.68 |
| E03.apply.page-refresh-128 | phone | 8 | 43,159 | 30.7 | 107.2 | 4.1 | 37.60 |
| E03.apply.page-refresh-256 | phone | 8 | 85,300 | 48.7 | -272.0 | 4.9 | 71.88 |
| E04.transact.final-line | phone | 200 | 22,690 | 7.2 | 9.0 | 4.7 | 21.72 |
| E04.transact.final-line-long-recording | phone | 200 | 22,557 | 7.7 | 9.6 | 4.6 | 30.42 |
| E04.transact.heartbeat | phone | 200 | 9,803 | 3.7 | 0.7 | 3.0 | 36.93 |
| E04.transact.interim | phone | 200 | 20,392 | 25.7 | 4.6 | 3.9 | 46.69 |
| E05.window.new-line-64 | phone | 20 | 119,787 | 45.8 | 4.2 | 5.5 | 44.32 |
| E05.window.new-line-256 | phone | 20 | 183,739 | 73.9 | 10.2 | 10.2 | 90.15 |
| E06.observe.churn | phone | 1 | 1,543,224 | 4,239.9 | 923.1 | 5.8 | 2068.38 |
| E07.launch.resident | phone | 1 | 2,377,552 | 578.8 | 39,371.9 | 52.4 | 647.87 |
| E08.upload.chunk-wav | phone | 5 | 118 | 0.0 | 0.0 | 0.0 | 0.21 |
| E08.upload.segment-m4a | phone | 20 | 119 | 0.0 | 0.0 | 0.0 | 0.06 |
| E09.diagnostics.no-sink | phone | 100 | 24,401 | 11.8 | 1.6 | 2.1 | 22.49 |
| E09.diagnostics.scribe-info-5-handlers | phone | 100 | 24,622 | 14.4 | 0.7 | 1.9 | 26.33 |
| E09.diagnostics.debug-1-handler | phone | 100 | 24,928 | 17.0 | 1.4 | 1.9 | 29.33 |
| E10.schema.window-new-line | attributes170 | 20 | 108,954 | 30.0 | 23.4 | 5.7 | 23.32 |
| E10.schema.page-refresh-64 | attributes170 | 8 | 21,917 | 13.6 | 7.7 | 3.5 | 14.67 |
| E10.schema.window-new-line | attributes2283 | 20 | 113,588 | 40.6 | 26.8 | 5.8 | 26.86 |
| E10.schema.page-refresh-64 | attributes2283 | 8 | 23,469 | 21.6 | -16.7 | 3.0 | 17.64 |
| E11.files.storedFiles | phone | 2 | 6,445,932 | 1,556.0 | -2.7 | 181.2 | 2714.26 |
| E12.result.refresh-nothing-due | phone | 6 | 85,290 | 49.0 | 10.0 | 7.2 | 65.06 |
| E12.result.refresh-then-write | phone | 6 | 245,305 | 81.7 | -510.6 | 8.4 | 90.21 |
| E12.result.write-then-refresh | phone | 6 | 245,218 | 81.6 | 6.3 | 9.6 | 84.56 |
| E13.reconnect.three-queries | phone | 3 | 155,730 | 64.2 | 5.4 | 4.4 | 340.00 |
| E14.read.local-history-page | phone | 10 | 24,292 | 24.0 | -3.0 | 5.8 | 14.14 |

**The two-hour replay** (`MemoryLongRunReplay`, the phone's shape, 51 observers open: the window, the lines in
progress, the list and the store's 48 open queries; 7,465 writes, 1,224 uploads, 1.06 GB received over the recording):

| Minute | Footprint MB | Footprint peak MB | Heap MB | Resident facts | Observers | Writes | Uploads | Received MB | Result JSON written MB | Connections | Wall s |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 0 | 249.6 | 250.7 | 118.4 | 54,738 | 51 | 1 | 0 | 6.7 | 7.6 | 1 | 1.2 |
| 5 | 254.4 | 259.2 | 113.3 | 56,109 | 51 | 312 | 51 | 46.4 | 16.7 | 1 | 14.1 |
| 30 | 171.8 | 176.3 | 121.2 | 59,535 | 51 | 1,867 | 306 | 274.7 | 48.8 | 2 | 73.5 |
| 60 | 165.0 | 169.4 | 125.6 | 63,427 | 51 | 3,733 | 612 | 548.0 | 88.0 | 3 | 140.7 |
| 90 | 151.1 | 163.3 | 131.4 | 67,319 | 51 | 5,599 | 918 | 814.4 | 125.9 | 3 | 197.6 |
| 120 | 151.8 | 165.1 | 136.5 | 71,211 | 51 | 7,465 | 1,224 | 1087.6 | 165.1 | 4 | 246.2 |

`MEMORY-REPLAY-SUMMARY phone minutes=120 footprint0MB=249.6 footprint5MB=254.4 footprint60MB=165.0 footprint120MB=151.8 growth5to60MB=-89.4 growth60to120MB=-13.2 footprintPerHourMB=-53.5 heapPerHourMB=12.1 peakMB=260.6 triples5=56109 triples60=63427 triples120=71211 wallS=246`

The footprint falls after the first minutes while the heap grows: macOS reclaims pages the setup touched (opening 51
queries peaked at 260.6 MB), so on the Mac the heap is the honest measure of what the library keeps; on a phone the
footprint also counts compressed memory, which this run does not reproduce. The replay compresses two hours into 246
seconds of wall time; the time per recorded minute stays flat (about 2 s), so nothing in it slows down as the
recording grows.

**The earlier run** (main d937ce43, before #1072's upload fix; fixture version 2 with its 783 uncoverable writes
pruned first) agrees with the official one within a few percent on every exercise but E08, which measured the fix:

```
MEMORY E08.upload.chunk-wav phone n=5 allocations=106947 allocatedKB=18302 frees=106947 retainedKB=0.5 peakLiveKB=1649 footprintPeakMB=312 wallMs=17.06 fileKB=5625 recordsOnDisk=4264 allocationsPerRecord=25.1
MEMORY E08.upload.segment-m4a phone n=20 allocations=107784 allocatedKB=18434 frees=107785 retainedKB=-0.1 peakLiveKB=1649 footprintPeakMB=312 wallMs=16.91 fileKB=24 recordsOnDisk=4275 allocationsPerRecord=25.2
```

Its replay held only the three recording-screen queries open, so the library's prune released the store's results
(54,738 facts at minute 0, 2,883 at minute 5); with that much smaller resident set the heap still grew 11.1 MB an hour:

`MEMORY-REPLAY-SUMMARY phone minutes=120 footprint0MB=221.1 footprint5MB=108.2 footprint60MB=128.7 footprint120MB=138.8 growth5to60MB=20.5 growth60to120MB=10.1 footprintPerHourMB=15.9 heapPerHourMB=11.1 peakMB=240.5 triples5=2883 triples60=10201 triples120=17985 wallS=246`

## Real-size check on the phone's own store

A copy of one iPhone's store (pulled 2026-10-24 before build 121; private, read on this laptop only, never copied into
the repository) was read with read-only SQL, at three points:
- **Its outbox** holds 3 confirmed writes (integer server ids near 2.89 billion), 663 refused and 1 pending, against
  783 confirmed in #1072's version-2 generated store: the first harness effect above, measured on the real thing.
- **Its shape** (the audit's first run): 174,801 facts on disk, each row also storing a ~274-byte JSON copy of itself;
  43 loaded query results (6.5 MB of JSON) and 359 unloaded (61 MB, the largest the 24.8 MB `$files` answer, #1144).
- **Its resident set** (the write-path auditor's query): 1,355 entities and 45,379 facts owned by stored results and
  unsent writes (the phone reported 45,369); 1,098 of 2,283 attributes are indexed; the resident facts hold 13,341
  indexed values in 7,335 distinct value sets, 6,845 of them with one member (the largest 396). At 544 bytes of empty
  shards per set (layout arithmetic, an estimate) that is about 3.7 MB for #1146's sets alone. Its `recordings.segments`
  links: 49 recordings hold them, the largest 2,364 lines (average 358), the size #1152's copy grows with.

The launch exercise on that copy (`INSTANT_REAL_SIZE_STORE=<copy> INSTANT_MEMORY_EXERCISES=1`, filter
`e07LaunchResident`; the session copies the store read-only into a temporary directory it removes) was queued on this
laptop's heavy lane at 17:53 and cancelled unrun at 18:24: the laptop stayed saturated (CPU idle 0-3%, 5-minute load
200-300) while the Mac mini ran the official baseline. It is the first thing to run when the laptop is idle.

## Raw lines (official run)

```
MEMORY E00.harness.ack-wait-idle phone n=50 allocations=36 allocatedKB=4 frees=36 retainedKB=0.0 peakLiveKB=4 footprintPeakMB=209 wallMs=0.00
MEMORY E00.harness.emission-wait-buffered phone n=50 allocations=18 allocatedKB=4 frees=13 retainedKB=0.5 peakLiveKB=34 footprintPeakMB=20 wallMs=0.01
MEMORY E01.decode.files-answer phone n=3 allocations=548414 allocatedKB=60265 frees=548414 retainedKB=0.0 peakLiveKB=31872 footprintPeakMB=97 wallMs=48.70 rows=9455 frameKB=15736 allocationsPerRow=58.0 peakOverFrame=2.0
MEMORY E01.decode.page-refresh-64 phone n=3 allocations=7124 allocatedKB=685 frees=7124 retainedKB=1.6 peakLiveKB=377 footprintPeakMB=97 wallMs=0.88 rows=64 frameKB=154 allocationsPerRow=111.3 peakOverFrame=2.5
MEMORY E01.decode.page-refresh-256 phone n=3 allocations=28545 allocatedKB=2873 frees=28545 retainedKB=-0.1 peakLiveKB=1522 footprintPeakMB=97 wallMs=3.53 rows=256 frameKB=623 allocationsPerRow=111.5 peakOverFrame=2.4
MEMORY E02.apply.files-answer.first-observe phone n=1 allocations=5152939 allocatedKB=2351249 frees=4901466 retainedKB=109686.0 peakLiveKB=255269 footprintPeakMB=615 footprintGrowthMB=289.9 wallMs=3009.93 rows=9455 emitted=9455 residentFactsAdded=75640 retainedPerFactB=1484.9 resultJSONWrittenKB=23326
MEMORY E02.apply.files-answer.cancel-and-prune phone n=1 allocations=14591 allocatedKB=1795 frees=18108 retainedKB=-9136.3 peakLiveKB=20 footprintPeakMB=449 footprintGrowthMB=0.2 wallMs=4.04 residentFactsAfter=130360
MEMORY E03.apply.page-refresh-32 phone n=8 allocations=13877 allocatedKB=18307 frees=13864 retainedKB=64.5 peakLiveKB=2752 footprintPeakMB=478 wallMs=11.12 rows=32 frameKB=79 allocationsPerRow=433.7 allocatedPerRowB=585825.8 attributeContextBuilds=0 resultJSONWrites=0
MEMORY E03.apply.page-refresh-64 phone n=8 allocations=23555 allocatedKB=22463 frees=23291 retainedKB=-68.6 peakLiveKB=2711 footprintPeakMB=479 wallMs=18.68 rows=64 frameKB=159 allocationsPerRow=368.0 allocatedPerRowB=359409.5 attributeContextBuilds=0 resultJSONWrites=0
MEMORY E03.apply.page-refresh-128 phone n=8 allocations=43159 allocatedKB=31456 frees=42592 retainedKB=107.2 peakLiveKB=4150 footprintPeakMB=483 wallMs=37.60 rows=128 frameKB=317 allocationsPerRow=337.2 allocatedPerRowB=251654.4 attributeContextBuilds=0 resultJSONWrites=0
MEMORY E03.apply.page-refresh-256 phone n=8 allocations=85300 allocatedKB=49826 frees=86349 retainedKB=-272.0 peakLiveKB=5058 footprintPeakMB=494 wallMs=71.88 rows=256 frameKB=653 allocationsPerRow=333.2 allocatedPerRowB=199306.9 attributeContextBuilds=0 resultJSONWrites=0
MEMORY E04.transact.final-line phone n=200 allocations=22690 allocatedKB=7388 frees=22646 retainedKB=9.0 peakLiveKB=4855 footprintPeakMB=143 wallMs=21.72 linkedLinesBefore=0 factsPerWrite=19 op.localSave=1.0 opMs.localSave=2.55 op.storePrepare=2.0 opMs.storePrepare=1.05 op.outboxClaim=1.4 opMs.outboxClaim=14.61 op.mutationEncode=1.0 opMs.mutationEncode=1.58 op.acknowledgement=1.0 opMs.acknowledgement=1.74 op.deferredHydrate=1.0 opMs.deferredHydrate=0.13
MEMORY E04.transact.final-line-long-recording phone n=200 allocations=22557 allocatedKB=7911 frees=22518 retainedKB=9.6 peakLiveKB=4715 footprintPeakMB=145 wallMs=30.42 linkedLinesBefore=2318 factsPerWrite=19 op.localSave=1.0 opMs.localSave=2.62 op.storePrepare=2.0 opMs.storePrepare=1.34 op.outboxClaim=1.3 opMs.outboxClaim=21.32 op.mutationEncode=1.0 opMs.mutationEncode=1.55 op.acknowledgement=1.0 opMs.acknowledgement=1.99 op.deferredHydrate=1.0 opMs.deferredHydrate=0.13
MEMORY E04.transact.heartbeat phone n=200 allocations=9803 allocatedKB=3786 frees=9777 retainedKB=0.7 peakLiveKB=3113 footprintPeakMB=146 wallMs=36.93 factsPerWrite=3 op.localSave=1.0 opMs.localSave=1.16 op.storePrepare=1.0 opMs.storePrepare=0.13 op.outboxClaim=1.6 opMs.outboxClaim=29.78 op.mutationEncode=1.0 opMs.mutationEncode=1.53 op.acknowledgement=1.0 opMs.acknowledgement=0.97 op.deferredHydrate=1.0 opMs.deferredHydrate=0.09
MEMORY E04.transact.interim phone n=200 allocations=20392 allocatedKB=26267 frees=20348 retainedKB=4.6 peakLiveKB=3979 footprintPeakMB=162 wallMs=46.69 factsPerWrite=16 op.localSave=1.0 opMs.localSave=1.43 op.storePrepare=1.0 opMs.storePrepare=0.16 op.outboxClaim=1.6 opMs.outboxClaim=29.44 op.mutationEncode=1.0 opMs.mutationEncode=1.47 op.acknowledgement=1.0 opMs.acknowledgement=1.26 op.deferredHydrate=1.0 opMs.deferredHydrate=0.07
MEMORY E05.window.new-line-64 phone n=20 allocations=119787 allocatedKB=46916 frees=119738 retainedKB=4.2 peakLiveKB=5678 footprintPeakMB=255 wallMs=44.32 rows=64 allocationsPerRow=1871.7 linkedLinesBefore=2318 lastRematerialized=1 lastMaterializedSnapshots=64 op.localSave=1.0 opMs.localSave=1.88 op.storePrepare=4.9 opMs.storePrepare=1.41 op.observerRefresh=2.0 opMs.observerRefresh=2.52 op.outboxClaim=2.0 opMs.outboxClaim=10.54 op.mutationEncode=1.0 opMs.mutationEncode=1.38 op.acknowledgement=1.0 opMs.acknowledgement=1.01 op.refreshTranslate=1.0 opMs.refreshTranslate=4.92 op.serverApplyPlan=6.8 opMs.serverApplyPlan=6.59 op.serverApplyCommit=1.0 opMs.serverApplyCommit=1.46 op.deferredHydrate=4.0 opMs.deferredHydrate=4.23 op.serverApplyStage=1.0 opMs.serverApplyStage=1.51 op.serverApplyRetractions=1.0 opMs.serverApplyRetractions=2.32
MEMORY E05.window.new-line-256 phone n=20 allocations=183739 allocatedKB=75682 frees=183650 retainedKB=10.2 peakLiveKB=10426 footprintPeakMB=307 wallMs=90.15 rows=256 allocationsPerRow=717.7 linkedLinesBefore=2318 lastRematerialized=1 lastMaterializedSnapshots=256 op.localSave=1.0 opMs.localSave=2.19 op.storePrepare=4.9 opMs.storePrepare=2.98 op.observerRefresh=2.0 opMs.observerRefresh=7.18 op.outboxClaim=2.0 opMs.outboxClaim=11.97 op.mutationEncode=1.0 opMs.mutationEncode=1.66 op.acknowledgement=1.0 opMs.acknowledgement=1.13 op.refreshTranslate=1.0 opMs.refreshTranslate=13.60 op.serverApplyPlan=6.8 opMs.serverApplyPlan=15.94 op.serverApplyCommit=1.0 opMs.serverApplyCommit=2.09 op.deferredHydrate=4.0 opMs.deferredHydrate=12.20 op.serverApplyStage=1.0 opMs.serverApplyStage=1.37 op.serverApplyRetractions=1.0 opMs.serverApplyRetractions=8.67
MEMORY E06.observe.churn phone n=1 allocations=1543224 allocatedKB=4341682 frees=1534920 retainedKB=923.1 peakLiveKB=5973 footprintPeakMB=305 footprintGrowthMB=0.9 wallMs=2068.38 leases=300 retainedPerLeaseB=3150.8 activeQueryKeys=0->0 resultKeys=0->0 observers=0 op.storePrepare=1.0 opMs.storePrepare=0.01 op.observerRefresh=0.0 opMs.observerRefresh=0.00 op.refreshTranslate=1.0 opMs.refreshTranslate=1.95 op.serverApplyPlan=5.0 opMs.serverApplyPlan=1.63 op.serverApplyCommit=1.0 opMs.serverApplyCommit=0.29 op.serverApplyRetractions=1.0 opMs.serverApplyRetractions=0.50
MEMORY E07.launch.resident phone n=1 allocations=2377552 allocatedKB=592732 frees=2216372 retainedKB=39371.9 peakLiveKB=53654 footprintPeakMB=307 footprintGrowthMB=0.5 wallMs=647.87 residentFacts=54720 retainedPerFactB=736.8
MEMORY E08.upload.chunk-wav phone n=5 allocations=118 allocatedKB=31 frees=118 retainedKB=0.0 peakLiveKB=5 footprintPeakMB=305 wallMs=0.21 fileKB=5625 recordsOnDisk=4264 allocationsPerRecord=0.0
MEMORY E08.upload.segment-m4a phone n=20 allocations=119 allocatedKB=34 frees=119 retainedKB=0.0 peakLiveKB=11 footprintPeakMB=305 wallMs=0.06 fileKB=24 recordsOnDisk=4275 allocationsPerRecord=0.0
MEMORY E09.diagnostics.no-sink phone n=100 allocations=24401 allocatedKB=12124 frees=24365 retainedKB=1.6 peakLiveKB=2110 footprintPeakMB=307 wallMs=22.49 handlerCallsPerWrite=-
MEMORY E09.diagnostics.scribe-info-5-handlers phone n=100 allocations=24622 allocatedKB=14776 frees=24600 retainedKB=0.7 peakLiveKB=1958 footprintPeakMB=307 wallMs=26.33 handlerCallsPerWrite=10.0
MEMORY E09.diagnostics.debug-1-handler phone n=100 allocations=24928 allocatedKB=17436 frees=24908 retainedKB=1.4 peakLiveKB=1929 footprintPeakMB=307 wallMs=29.33 handlerCallsPerWrite=10.7
MEMORY E10.schema.window-new-line attributes170 n=20 allocations=108954 allocatedKB=30675 frees=108883 retainedKB=23.4 peakLiveKB=5864 footprintPeakMB=309 wallMs=23.32 op.localSave=1.0 opMs.localSave=1.89 op.storePrepare=3.0 opMs.storePrepare=0.59 op.observerRefresh=2.0 opMs.observerRefresh=0.75 op.outboxClaim=2.0 opMs.outboxClaim=2.46 op.mutationEncode=1.0 opMs.mutationEncode=0.12 op.acknowledgement=1.0 opMs.acknowledgement=1.01 op.refreshTranslate=1.0 opMs.refreshTranslate=2.49 op.serverApplyPlan=6.8 opMs.serverApplyPlan=4.12 op.serverApplyCommit=1.0 opMs.serverApplyCommit=0.81 op.deferredHydrate=3.0 opMs.deferredHydrate=2.45 op.serverApplyStage=1.0 opMs.serverApplyStage=1.60 op.serverApplyRetractions=1.0 opMs.serverApplyRetractions=1.42
MEMORY E10.schema.page-refresh-64 attributes170 n=8 allocations=21917 allocatedKB=13939 frees=21894 retainedKB=7.7 peakLiveKB=3580 footprintPeakMB=215 wallMs=14.67
MEMORY E10.schema.window-new-line attributes2283 n=20 allocations=113588 allocatedKB=41610 frees=113468 retainedKB=26.8 peakLiveKB=5889 footprintPeakMB=217 wallMs=26.86 op.localSave=1.0 opMs.localSave=1.53 op.storePrepare=3.0 opMs.storePrepare=0.54 op.observerRefresh=2.0 opMs.observerRefresh=0.65 op.outboxClaim=2.0 opMs.outboxClaim=2.45 op.mutationEncode=1.0 opMs.mutationEncode=1.39 op.acknowledgement=1.0 opMs.acknowledgement=1.00 op.refreshTranslate=1.0 opMs.refreshTranslate=3.84 op.serverApplyPlan=6.8 opMs.serverApplyPlan=4.66 op.serverApplyCommit=1.0 opMs.serverApplyCommit=0.63 op.deferredHydrate=3.0 opMs.deferredHydrate=2.22 op.serverApplyStage=1.0 opMs.serverApplyStage=1.57 op.serverApplyRetractions=1.0 opMs.serverApplyRetractions=1.20
MEMORY E10.schema.page-refresh-64 attributes2283 n=8 allocations=23469 allocatedKB=22085 frees=23158 retainedKB=-16.7 peakLiveKB=3047 footprintPeakMB=216 wallMs=17.64
MEMORY E11.files.storedFiles phone n=2 allocations=6445932 allocatedKB=1593378 frees=6445927 retainedKB=-2.7 peakLiveKB=185539 footprintPeakMB=681 wallMs=2714.26 files=9455 listed=9455 op.storePrepare=1.2 opMs.storePrepare=52.05 op.refreshTranslate=1.0 opMs.refreshTranslate=336.13 op.serverApplyPlan=5.0 opMs.serverApplyPlan=571.40 op.serverApplyCommit=1.0 opMs.serverApplyCommit=196.74 op.deferredHydrate=0.2 opMs.deferredHydrate=1.24 op.serverApplyRetractions=1.0 opMs.serverApplyRetractions=514.76
MEMORY E12.result.refresh-nothing-due phone n=6 allocations=85290 allocatedKB=50153 frees=85246 retainedKB=10.0 peakLiveKB=7418 footprintPeakMB=524 wallMs=65.06
MEMORY E12.result.refresh-then-write phone n=6 allocations=245305 allocatedKB=83612 frees=247591 retainedKB=-510.6 peakLiveKB=8563 footprintPeakMB=524 wallMs=90.21
MEMORY E12.result.write-then-refresh phone n=6 allocations=245218 allocatedKB=83522 frees=245195 retainedKB=6.3 peakLiveKB=9822 footprintPeakMB=526 wallMs=84.56
MEMORY E13.reconnect.three-queries phone n=3 allocations=155730 allocatedKB=65712 frees=155642 retainedKB=5.4 peakLiveKB=4547 footprintPeakMB=526 wallMs=340.00 connections=8 fullStoreLoads=0 storeReplacements=0 fullStoreCopies=0 op.storePrepare=4.0 opMs.storePrepare=0.67 op.observerRefresh=3.0 opMs.observerRefresh=0.02 op.outboxClaim=1.0 opMs.outboxClaim=3.25 op.refreshTranslate=3.0 opMs.refreshTranslate=8.98 op.serverApplyPlan=15.0 opMs.serverApplyPlan=10.76 op.serverApplyCommit=3.0 opMs.serverApplyCommit=0.71 op.deferredHydrate=1.0 opMs.deferredHydrate=1.09 op.connectAttempt=1.0 opMs.connectAttempt=32.02 op.serverApplyRetractions=3.0 opMs.serverApplyRetractions=12.13
MEMORY E14.read.local-history-page phone n=10 allocations=24292 allocatedKB=24621 frees=24288 retainedKB=-3.0 peakLiveKB=5926 footprintPeakMB=397 wallMs=14.14 pages=10 lines=2318 lastPageRows=256
MEMORY-REPLAY-START phone shape=[recordings=352 lines=8712 others=3400 files=9455 fileRecords=4264 refused=663 open=48 closed=355 attributes=2283] workload=[lines/min=10 interims=1,2 heartbeats/min=12 routes/min=3 wavEvery=5minx5760044B segments/min=10x24576B others/min=1 window=64 liveLines=8 list=84 polls/min=12 scans/min=1 reconnectEvery=40min pruneEvery=64] minutes=120
MEMORY-REPLAY phone minute=0 footprintMB=249.6 footprintPeakMB=250.7 heapMB=118.4 triples=54738 observers=51 pending=0 writes=1 uploads=0 emissions=0 framesIn=54 bytesInMB=6.7 largestFrameKB=979 resultWrites=30 resultWrittenMB=7.6 fullStoreLoads=1 storeReplacements=0 fullStoreCopies=1 connections=1 wallS=1.2 ms.op.storePrepare=3 ms.op.outboxClaim=14 ms.op.mutationEncode=1 ms.op.acknowledgement=1 ms.op.refreshTranslate=181 ms.op.serverApplyPlan=437 ms.op.serverApplyCommit=48 ms.op.deferredHydrate=10 ms.op.serverApplyRetractions=256
MEMORY-REPLAY phone minute=5 footprintMB=254.4 footprintPeakMB=259.2 heapMB=113.3 triples=56109 observers=51 pending=0 writes=312 uploads=51 emissions=495 framesIn=615 bytesInMB=46.4 largestFrameKB=979 resultWrites=88 resultWrittenMB=16.7 fullStoreLoads=1 storeReplacements=0 fullStoreCopies=1 connections=1 wallS=14.1 ms.chunkRow=72 ms.final=3298 ms.heartbeat=3309 ms.interim=2829 ms.other=24 ms.poll=38 ms.route=81 ms.scan=164 ms.segment=178 ms.speakers=2592 ms.wavUpload=3 ms.op.localSave=489 ms.op.storePrepare=75 ms.op.observerRefresh=1129 ms.op.outboxClaim=3534 ms.op.mutationEncode=449 ms.op.acknowledgement=357 ms.op.refreshTranslate=1473 ms.op.serverApplyPlan=1978 ms.op.serverApplyCommit=400 ms.op.deferredHydrate=98 ms.op.prune=1 ms.op.serverApplyRetractions=880
MEMORY-REPLAY phone minute=10 footprintMB=255.4 footprintPeakMB=260.0 heapMB=114.5 triples=56951 observers=51 pending=0 writes=623 uploads=102 emissions=1026 framesIn=1176 bytesInMB=90.4 largestFrameKB=979 resultWrites=126 resultWrittenMB=23.0 fullStoreLoads=1 storeReplacements=0 fullStoreCopies=1 connections=1 wallS=25.5 ms.chunkRow=53 ms.final=3523 ms.heartbeat=2712 ms.interim=2023 ms.other=18 ms.poll=80 ms.route=59 ms.scan=161 ms.segment=132 ms.speakers=2276 ms.wavUpload=1 ms.op.localSave=382 ms.op.storePrepare=100 ms.op.observerRefresh=1100 ms.op.outboxClaim=2970 ms.op.mutationEncode=390 ms.op.acknowledgement=285 ms.op.refreshTranslate=1328 ms.op.serverApplyPlan=1770 ms.op.serverApplyCommit=257 ms.op.deferredHydrate=245 ms.op.prune=3 ms.op.serverApplyRetractions=723
MEMORY-REPLAY phone minute=15 footprintMB=208.9 footprintPeakMB=260.6 heapMB=116.1 triples=57597 observers=51 pending=0 writes=934 uploads=153 emissions=1571 framesIn=1737 bytesInMB=134.7 largestFrameKB=979 resultWrites=165 resultWrittenMB=29.3 fullStoreLoads=1 storeReplacements=0 fullStoreCopies=1 connections=1 wallS=37.8 ms.chunkRow=57 ms.final=3981 ms.heartbeat=2902 ms.interim=2175 ms.other=19 ms.poll=65 ms.route=52 ms.scan=163 ms.segment=135 ms.speakers=2394 ms.wavUpload=9 ms.op.localSave=333 ms.op.storePrepare=117 ms.op.observerRefresh=1216 ms.op.outboxClaim=3286 ms.op.mutationEncode=437 ms.op.acknowledgement=307 ms.op.refreshTranslate=1406 ms.op.serverApplyPlan=1947 ms.op.serverApplyCommit=291 ms.op.deferredHydrate=289 ms.op.prune=2 ms.op.serverApplyRetractions=840
MEMORY-REPLAY phone minute=20 footprintMB=170.2 footprintPeakMB=213.4 heapMB=118.5 triples=58243 observers=51 pending=0 writes=1245 uploads=204 emissions=2116 framesIn=2350 bytesInMB=185.9 largestFrameKB=979 resultWrites=206 resultWrittenMB=36.2 fullStoreLoads=1 storeReplacements=0 fullStoreCopies=1 connections=2 wallS=51.2 ms.chunkRow=49 ms.final=3788 ms.heartbeat=2685 ms.interim=2133 ms.other=18 ms.poll=60 ms.reconnect=1616 ms.route=63 ms.scan=153 ms.segment=114 ms.speakers=2410 ms.wavUpload=10 ms.op.localSave=483 ms.op.storePrepare=112 ms.op.observerRefresh=1088 ms.op.outboxClaim=3330 ms.op.mutationEncode=432 ms.op.acknowledgement=296 ms.op.refreshTranslate=1547 ms.op.serverApplyPlan=2029 ms.op.serverApplyCommit=273 ms.op.deferredHydrate=398 ms.op.prune=2 ms.op.connectAttempt=175 ms.op.serverApplyRetractions=1061
MEMORY-REPLAY phone minute=25 footprintMB=170.8 footprintPeakMB=175.2 heapMB=119.4 triples=58889 observers=51 pending=0 writes=1556 uploads=255 emissions=2661 framesIn=2911 bytesInMB=230.3 largestFrameKB=979 resultWrites=244 resultWrittenMB=42.5 fullStoreLoads=1 storeReplacements=0 fullStoreCopies=1 connections=2 wallS=61.3 ms.chunkRow=48 ms.final=3188 ms.heartbeat=2378 ms.interim=1838 ms.other=16 ms.poll=64 ms.route=57 ms.scan=133 ms.segment=106 ms.speakers=1947 ms.wavUpload=0 ms.op.localSave=273 ms.op.storePrepare=101 ms.op.observerRefresh=982 ms.op.outboxClaim=2725 ms.op.mutationEncode=392 ms.op.acknowledgement=242 ms.op.refreshTranslate=1087 ms.op.serverApplyPlan=1473 ms.op.serverApplyCommit=218 ms.op.deferredHydrate=264 ms.op.prune=1 ms.op.serverApplyRetractions=609
MEMORY-REPLAY phone minute=30 footprintMB=171.8 footprintPeakMB=176.3 heapMB=121.2 triples=59535 observers=51 pending=0 writes=1867 uploads=306 emissions=3206 framesIn=3472 bytesInMB=274.7 largestFrameKB=979 resultWrites=282 resultWrittenMB=48.8 fullStoreLoads=1 storeReplacements=0 fullStoreCopies=1 connections=2 wallS=73.5 ms.chunkRow=68 ms.final=3719 ms.heartbeat=2977 ms.interim=2286 ms.other=24 ms.poll=60 ms.route=83 ms.scan=202 ms.segment=121 ms.speakers=2354 ms.wavUpload=17 ms.op.localSave=309 ms.op.storePrepare=114 ms.op.observerRefresh=1150 ms.op.outboxClaim=3575 ms.op.mutationEncode=528 ms.op.acknowledgement=319 ms.op.refreshTranslate=1299 ms.op.serverApplyPlan=1738 ms.op.serverApplyCommit=263 ms.op.deferredHydrate=283 ms.op.prune=2 ms.op.serverApplyRetractions=738
MEMORY-REPLAY phone minute=35 footprintMB=172.6 footprintPeakMB=177.2 heapMB=122.1 triples=60197 observers=51 pending=0 writes=2178 uploads=357 emissions=3751 framesIn=4033 bytesInMB=319.1 largestFrameKB=979 resultWrites=320 resultWrittenMB=55.2 fullStoreLoads=1 storeReplacements=0 fullStoreCopies=1 connections=2 wallS=86.0 ms.chunkRow=65 ms.final=3906 ms.heartbeat=2925 ms.interim=2373 ms.other=23 ms.poll=61 ms.route=67 ms.scan=174 ms.segment=127 ms.speakers=2457 ms.wavUpload=1 ms.op.localSave=316 ms.op.storePrepare=119 ms.op.observerRefresh=1059 ms.op.outboxClaim=3649 ms.op.mutationEncode=522 ms.op.acknowledgement=299 ms.op.refreshTranslate=1331 ms.op.serverApplyPlan=1783 ms.op.serverApplyCommit=259 ms.op.deferredHydrate=288 ms.op.prune=3 ms.op.serverApplyRetractions=755
MEMORY-REPLAY phone minute=40 footprintMB=173.3 footprintPeakMB=178.1 heapMB=122.7 triples=60843 observers=51 pending=0 writes=2489 uploads=408 emissions=4296 framesIn=4594 bytesInMB=363.5 largestFrameKB=979 resultWrites=359 resultWrittenMB=61.7 fullStoreLoads=1 storeReplacements=0 fullStoreCopies=1 connections=2 wallS=97.7 ms.chunkRow=73 ms.final=3729 ms.heartbeat=2769 ms.interim=2115 ms.other=16 ms.poll=63 ms.route=56 ms.scan=173 ms.segment=112 ms.speakers=2215 ms.wavUpload=1 ms.op.localSave=308 ms.op.storePrepare=110 ms.op.observerRefresh=1048 ms.op.outboxClaim=3202 ms.op.mutationEncode=501 ms.op.acknowledgement=267 ms.op.refreshTranslate=1251 ms.op.serverApplyPlan=1671 ms.op.serverApplyCommit=242 ms.op.deferredHydrate=275 ms.op.prune=1 ms.op.serverApplyRetractions=710
MEMORY-REPLAY phone minute=45 footprintMB=174.0 footprintPeakMB=179.0 heapMB=123.5 triples=61489 observers=51 pending=0 writes=2800 uploads=459 emissions=4841 framesIn=5155 bytesInMB=407.9 largestFrameKB=979 resultWrites=396 resultWrittenMB=68.0 fullStoreLoads=1 storeReplacements=0 fullStoreCopies=1 connections=2 wallS=108.3 ms.chunkRow=66 ms.final=3443 ms.heartbeat=2544 ms.interim=1875 ms.other=16 ms.poll=47 ms.route=70 ms.scan=164 ms.segment=105 ms.speakers=2007 ms.wavUpload=0 ms.op.localSave=293 ms.op.storePrepare=103 ms.op.observerRefresh=958 ms.op.outboxClaim=2803 ms.op.mutationEncode=455 ms.op.acknowledgement=237 ms.op.refreshTranslate=1160 ms.op.serverApplyPlan=1607 ms.op.serverApplyCommit=229 ms.op.deferredHydrate=260 ms.op.prune=1 ms.op.serverApplyRetractions=674
MEMORY-REPLAY phone minute=50 footprintMB=159.7 footprintPeakMB=179.4 heapMB=124.4 triples=62135 observers=51 pending=0 writes=3111 uploads=510 emissions=5386 framesIn=5716 bytesInMB=452.3 largestFrameKB=979 resultWrites=434 resultWrittenMB=74.3 fullStoreLoads=1 storeReplacements=0 fullStoreCopies=1 connections=2 wallS=118.8 ms.chunkRow=46 ms.final=3363 ms.heartbeat=2498 ms.interim=1849 ms.other=15 ms.poll=66 ms.route=62 ms.scan=159 ms.segment=104 ms.speakers=1966 ms.wavUpload=1 ms.op.localSave=292 ms.op.storePrepare=101 ms.op.observerRefresh=942 ms.op.outboxClaim=2658 ms.op.mutationEncode=437 ms.op.acknowledgement=269 ms.op.refreshTranslate=1152 ms.op.serverApplyPlan=1561 ms.op.serverApplyCommit=199 ms.op.deferredHydrate=255 ms.op.prune=4 ms.op.serverApplyRetractions=655
MEMORY-REPLAY phone minute=55 footprintMB=160.3 footprintPeakMB=165.2 heapMB=125.5 triples=62781 observers=51 pending=0 writes=3422 uploads=561 emissions=5931 framesIn=6277 bytesInMB=496.7 largestFrameKB=979 resultWrites=473 resultWrittenMB=81.0 fullStoreLoads=1 storeReplacements=0 fullStoreCopies=1 connections=2 wallS=128.8 ms.chunkRow=49 ms.final=3260 ms.heartbeat=2329 ms.interim=1766 ms.other=17 ms.poll=68 ms.route=65 ms.scan=147 ms.segment=108 ms.speakers=1903 ms.wavUpload=1 ms.op.localSave=297 ms.op.storePrepare=99 ms.op.observerRefresh=904 ms.op.outboxClaim=2565 ms.op.mutationEncode=425 ms.op.acknowledgement=244 ms.op.refreshTranslate=1108 ms.op.serverApplyPlan=1486 ms.op.serverApplyCommit=191 ms.op.deferredHydrate=255 ms.op.prune=1 ms.op.serverApplyRetractions=658
MEMORY-REPLAY phone minute=60 footprintMB=165.0 footprintPeakMB=169.4 heapMB=125.6 triples=63427 observers=51 pending=0 writes=3733 uploads=612 emissions=6476 framesIn=6890 bytesInMB=548.0 largestFrameKB=979 resultWrites=514 resultWrittenMB=88.0 fullStoreLoads=1 storeReplacements=0 fullStoreCopies=1 connections=3 wallS=140.7 ms.chunkRow=41 ms.final=3284 ms.heartbeat=2417 ms.interim=1872 ms.other=17 ms.poll=74 ms.reconnect=1512 ms.route=70 ms.scan=155 ms.segment=104 ms.speakers=2038 ms.wavUpload=0 ms.op.localSave=282 ms.op.storePrepare=109 ms.op.observerRefresh=973 ms.op.outboxClaim=2782 ms.op.mutationEncode=464 ms.op.acknowledgement=267 ms.op.refreshTranslate=1314 ms.op.serverApplyPlan=1776 ms.op.serverApplyCommit=229 ms.op.deferredHydrate=263 ms.op.prune=2 ms.op.connectAttempt=157 ms.op.serverApplyRetractions=907
MEMORY-REPLAY phone minute=65 footprintMB=165.5 footprintPeakMB=169.8 heapMB=126.5 triples=64073 observers=51 pending=0 writes=4044 uploads=663 emissions=7021 framesIn=7451 bytesInMB=592.4 largestFrameKB=979 resultWrites=552 resultWrittenMB=94.3 fullStoreLoads=1 storeReplacements=0 fullStoreCopies=1 connections=3 wallS=151.1 ms.chunkRow=44 ms.final=3261 ms.heartbeat=2539 ms.interim=1780 ms.other=14 ms.poll=53 ms.route=64 ms.scan=156 ms.segment=128 ms.speakers=2009 ms.wavUpload=0 ms.op.localSave=283 ms.op.storePrepare=105 ms.op.observerRefresh=937 ms.op.outboxClaim=2718 ms.op.mutationEncode=457 ms.op.acknowledgement=237 ms.op.refreshTranslate=1155 ms.op.serverApplyPlan=1498 ms.op.serverApplyCommit=233 ms.op.deferredHydrate=260 ms.op.prune=1 ms.op.serverApplyRetractions=621
MEMORY-REPLAY phone minute=70 footprintMB=166.1 footprintPeakMB=170.9 heapMB=128.0 triples=64735 observers=51 pending=0 writes=4355 uploads=714 emissions=7566 framesIn=8012 bytesInMB=636.8 largestFrameKB=979 resultWrites=590 resultWrittenMB=100.6 fullStoreLoads=1 storeReplacements=0 fullStoreCopies=1 connections=3 wallS=161.8 ms.chunkRow=59 ms.final=3440 ms.heartbeat=2525 ms.interim=1946 ms.other=18 ms.poll=47 ms.route=60 ms.scan=142 ms.segment=118 ms.speakers=2039 ms.wavUpload=1 ms.op.localSave=292 ms.op.storePrepare=111 ms.op.observerRefresh=967 ms.op.outboxClaim=2848 ms.op.mutationEncode=482 ms.op.acknowledgement=260 ms.op.refreshTranslate=1136 ms.op.serverApplyPlan=1530 ms.op.serverApplyCommit=240 ms.op.deferredHydrate=264 ms.op.prune=1 ms.op.serverApplyRetractions=641
MEMORY-REPLAY phone minute=75 footprintMB=166.9 footprintPeakMB=171.6 heapMB=128.9 triples=65381 observers=51 pending=0 writes=4666 uploads=765 emissions=8111 framesIn=8573 bytesInMB=681.2 largestFrameKB=979 resultWrites=628 resultWrittenMB=107.0 fullStoreLoads=1 storeReplacements=0 fullStoreCopies=1 connections=3 wallS=170.9 ms.chunkRow=45 ms.final=2935 ms.heartbeat=2106 ms.interim=1539 ms.other=14 ms.poll=61 ms.route=61 ms.scan=128 ms.segment=132 ms.speakers=1735 ms.wavUpload=0 ms.op.localSave=293 ms.op.storePrepare=98 ms.op.observerRefresh=871 ms.op.outboxClaim=2246 ms.op.mutationEncode=361 ms.op.acknowledgement=202 ms.op.refreshTranslate=994 ms.op.serverApplyPlan=1325 ms.op.serverApplyCommit=185 ms.op.deferredHydrate=230 ms.op.prune=1 ms.op.serverApplyRetractions=569
MEMORY-REPLAY phone minute=80 footprintMB=157.7 footprintPeakMB=171.6 heapMB=129.6 triples=66027 observers=51 pending=0 writes=4977 uploads=816 emissions=8656 framesIn=9134 bytesInMB=725.6 largestFrameKB=979 resultWrites=666 resultWrittenMB=113.3 fullStoreLoads=1 storeReplacements=0 fullStoreCopies=1 connections=3 wallS=181.0 ms.chunkRow=47 ms.final=3284 ms.heartbeat=2358 ms.interim=1804 ms.other=16 ms.poll=65 ms.route=59 ms.scan=172 ms.segment=113 ms.speakers=1835 ms.wavUpload=0 ms.op.localSave=277 ms.op.storePrepare=109 ms.op.observerRefresh=935 ms.op.outboxClaim=2659 ms.op.mutationEncode=422 ms.op.acknowledgement=244 ms.op.refreshTranslate=1073 ms.op.serverApplyPlan=1443 ms.op.serverApplyCommit=237 ms.op.deferredHydrate=262 ms.op.prune=1 ms.op.serverApplyRetractions=612
MEMORY-REPLAY phone minute=85 footprintMB=158.3 footprintPeakMB=162.8 heapMB=130.5 triples=66673 observers=51 pending=0 writes=5288 uploads=867 emissions=9201 framesIn=9695 bytesInMB=770.0 largestFrameKB=979 resultWrites=704 resultWrittenMB=119.6 fullStoreLoads=1 storeReplacements=0 fullStoreCopies=1 connections=3 wallS=189.7 ms.chunkRow=41 ms.final=2769 ms.heartbeat=2012 ms.interim=1434 ms.other=14 ms.poll=82 ms.route=57 ms.scan=144 ms.segment=122 ms.speakers=1715 ms.wavUpload=2 ms.op.localSave=276 ms.op.storePrepare=100 ms.op.observerRefresh=822 ms.op.outboxClaim=2083 ms.op.mutationEncode=345 ms.op.acknowledgement=208 ms.op.refreshTranslate=988 ms.op.serverApplyPlan=1273 ms.op.serverApplyCommit=190 ms.op.deferredHydrate=206 ms.op.prune=1 ms.op.serverApplyRetractions=549
MEMORY-REPLAY phone minute=90 footprintMB=151.1 footprintPeakMB=163.3 heapMB=131.4 triples=67319 observers=51 pending=0 writes=5599 uploads=918 emissions=9746 framesIn=10256 bytesInMB=814.4 largestFrameKB=979 resultWrites=742 resultWrittenMB=125.9 fullStoreLoads=1 storeReplacements=0 fullStoreCopies=1 connections=3 wallS=197.6 ms.chunkRow=26 ms.final=2558 ms.heartbeat=1779 ms.interim=1291 ms.other=19 ms.poll=76 ms.route=50 ms.scan=101 ms.segment=102 ms.speakers=1580 ms.wavUpload=0 ms.op.localSave=247 ms.op.storePrepare=95 ms.op.observerRefresh=781 ms.op.outboxClaim=1795 ms.op.mutationEncode=295 ms.op.acknowledgement=188 ms.op.refreshTranslate=909 ms.op.serverApplyPlan=1210 ms.op.serverApplyCommit=161 ms.op.deferredHydrate=181 ms.op.prune=1 ms.op.serverApplyRetractions=526
MEMORY-REPLAY phone minute=95 footprintMB=151.8 footprintPeakMB=156.6 heapMB=132.1 triples=67965 observers=51 pending=0 writes=5910 uploads=969 emissions=10291 framesIn=10817 bytesInMB=858.7 largestFrameKB=979 resultWrites=780 resultWrittenMB=132.2 fullStoreLoads=1 storeReplacements=0 fullStoreCopies=1 connections=3 wallS=206.1 ms.chunkRow=34 ms.final=2699 ms.heartbeat=1983 ms.interim=1413 ms.other=15 ms.poll=82 ms.route=60 ms.scan=138 ms.segment=103 ms.speakers=1687 ms.wavUpload=0 ms.op.localSave=255 ms.op.storePrepare=98 ms.op.observerRefresh=843 ms.op.outboxClaim=2035 ms.op.mutationEncode=340 ms.op.acknowledgement=194 ms.op.refreshTranslate=969 ms.op.serverApplyPlan=1289 ms.op.serverApplyCommit=200 ms.op.deferredHydrate=202 ms.op.prune=1 ms.op.serverApplyRetractions=543
MEMORY-REPLAY phone minute=100 footprintMB=161.3 footprintPeakMB=165.6 heapMB=132.4 triples=68627 observers=51 pending=0 writes=6221 uploads=1020 emissions=10836 framesIn=11430 bytesInMB=910.0 largestFrameKB=979 resultWrites=824 resultWrittenMB=139.8 fullStoreLoads=1 storeReplacements=0 fullStoreCopies=1 connections=4 wallS=216.5 ms.chunkRow=49 ms.final=2902 ms.heartbeat=2116 ms.interim=1555 ms.other=18 ms.poll=43 ms.reconnect=1315 ms.route=63 ms.scan=128 ms.segment=94 ms.speakers=1770 ms.wavUpload=0 ms.op.localSave=286 ms.op.storePrepare=107 ms.op.observerRefresh=865 ms.op.outboxClaim=2171 ms.op.mutationEncode=349 ms.op.acknowledgement=216 ms.op.refreshTranslate=1172 ms.op.serverApplyPlan=1601 ms.op.serverApplyCommit=216 ms.op.deferredHydrate=224 ms.op.prune=1 ms.op.connectAttempt=141 ms.op.serverApplyRetractions=816
MEMORY-REPLAY phone minute=105 footprintMB=162.0 footprintPeakMB=166.8 heapMB=133.3 triples=69273 observers=51 pending=0 writes=6532 uploads=1071 emissions=11381 framesIn=11991 bytesInMB=954.4 largestFrameKB=979 resultWrites=862 resultWrittenMB=146.1 fullStoreLoads=1 storeReplacements=0 fullStoreCopies=1 connections=4 wallS=224.1 ms.chunkRow=44 ms.final=2429 ms.heartbeat=1770 ms.interim=1178 ms.other=13 ms.poll=72 ms.route=59 ms.scan=100 ms.segment=98 ms.speakers=1474 ms.wavUpload=0 ms.op.localSave=252 ms.op.storePrepare=89 ms.op.observerRefresh=755 ms.op.outboxClaim=1586 ms.op.mutationEncode=274 ms.op.acknowledgement=162 ms.op.refreshTranslate=879 ms.op.serverApplyPlan=1171 ms.op.serverApplyCommit=200 ms.op.deferredHydrate=172 ms.op.prune=1 ms.op.serverApplyRetractions=503
MEMORY-REPLAY phone minute=110 footprintMB=158.8 footprintPeakMB=166.3 heapMB=134.2 triples=69919 observers=51 pending=0 writes=6843 uploads=1122 emissions=11926 framesIn=12552 bytesInMB=998.8 largestFrameKB=979 resultWrites=900 resultWrittenMB=152.5 fullStoreLoads=1 storeReplacements=0 fullStoreCopies=1 connections=4 wallS=231.5 ms.chunkRow=33 ms.final=2378 ms.heartbeat=1694 ms.interim=1218 ms.other=14 ms.poll=74 ms.route=45 ms.scan=101 ms.segment=97 ms.speakers=1433 ms.wavUpload=0 ms.op.localSave=237 ms.op.storePrepare=88 ms.op.observerRefresh=749 ms.op.outboxClaim=1561 ms.op.mutationEncode=271 ms.op.acknowledgement=159 ms.op.refreshTranslate=876 ms.op.serverApplyPlan=1169 ms.op.serverApplyCommit=168 ms.op.deferredHydrate=169 ms.op.prune=1 ms.op.serverApplyRetractions=501
MEMORY-REPLAY phone minute=115 footprintMB=159.6 footprintPeakMB=164.3 heapMB=135.0 triples=70565 observers=51 pending=0 writes=7154 uploads=1173 emissions=12471 framesIn=13113 bytesInMB=1043.2 largestFrameKB=979 resultWrites=938 resultWrittenMB=158.8 fullStoreLoads=1 storeReplacements=0 fullStoreCopies=1 connections=4 wallS=238.9 ms.chunkRow=37 ms.final=2375 ms.heartbeat=1719 ms.interim=1131 ms.other=13 ms.poll=79 ms.route=47 ms.scan=100 ms.segment=109 ms.speakers=1476 ms.wavUpload=0 ms.op.localSave=231 ms.op.storePrepare=88 ms.op.observerRefresh=751 ms.op.outboxClaim=1562 ms.op.mutationEncode=272 ms.op.acknowledgement=162 ms.op.refreshTranslate=871 ms.op.serverApplyPlan=1161 ms.op.serverApplyCommit=168 ms.op.deferredHydrate=169 ms.op.prune=1 ms.op.serverApplyRetractions=500
MEMORY-REPLAY phone minute=120 footprintMB=151.8 footprintPeakMB=165.1 heapMB=136.5 triples=71211 observers=51 pending=0 writes=7465 uploads=1224 emissions=13016 framesIn=13674 bytesInMB=1087.6 largestFrameKB=979 resultWrites=976 resultWrittenMB=165.1 fullStoreLoads=1 storeReplacements=0 fullStoreCopies=1 connections=4 wallS=246.2 ms.chunkRow=29 ms.final=2335 ms.heartbeat=1725 ms.interim=1157 ms.other=12 ms.poll=70 ms.route=56 ms.scan=98 ms.segment=100 ms.speakers=1400 ms.wavUpload=0 ms.op.localSave=249 ms.op.storePrepare=89 ms.op.observerRefresh=744 ms.op.outboxClaim=1485 ms.op.mutationEncode=262 ms.op.acknowledgement=170 ms.op.refreshTranslate=874 ms.op.serverApplyPlan=1156 ms.op.serverApplyCommit=151 ms.op.deferredHydrate=169 ms.op.prune=1 ms.op.serverApplyRetractions=511
MEMORY-REPLAY-SUMMARY phone minutes=120 footprint0MB=249.6 footprint5MB=254.4 footprint60MB=165.0 footprint120MB=151.8 growth5to60MB=-89.4 growth60to120MB=-13.2 footprintPerHourMB=-53.5 heapPerHourMB=12.1 peakMB=260.6 triples5=56109 triples60=63427 triples120=71211 wallS=246
```

