# Plan 2026-10-31-perf-writes-1510: a recorder that names the pages each statement and each table writes; then a save's pages cut at their source

- planId: 2026-10-31-perf-writes-1510
- agentId: claude-code/perf-writes-1510@ld (tools/agent-run, claude/ld, Opus 5.5)
- role: grower for the recorder (Michael's order, typed 2026-10-31 13:30 on #1510: "a recorder in the library, simple
  and bounded under #1285, that reports per prepared statement and per table the pages written over time and the query
  shape behind each, read from the ledger; a fix ships only with those numbers"); mower for every fix after it
- issues: #1510 (P0, this), #1507 (a) (the ledger's path-attributed writers, agreed with perf-waste-fixes 13:45);
  related #1426 (a refresh's result rows), #1500 (closed results, perf-waste-fixes), #1429 (Core ML recompiles)
- branch: agent/claude/perf-writes-1510 (worktree ~/Sync/worktrees/perf-writes-1510), landed with ~/Scribe/tools/land;
  the app's half (the minute row's new sections, #1507 (a)) is a Scribe plan of its own

## Why (measured before any change)

The phone's write-ahead log, frame by frame (USB pulls 13:21 and 13:32, build 208 recording; each frame's page named
by `dbstat` on a clone of the store, a save told from a confirm by its body leaf gaining or losing a cell):

| transaction | pages | KB | where the pages go |
| --- | --- | --- | --- |
| save (81) | 24.4 | 98 | triples 5.9, outbox write keys and their index 5.3, the body's overflow 2.7, the body 2.1, page 1 (1 byte: the free-page count), sync metadata (6 bytes: two revision counters), the outbox row and 3 of its 8 indexes, effect entities and their index |
| server apply + confirm (26) | 35.5 | 143 | live-query ownership 12.9 (#1426's rows), the confirmed write keys' deletes 8.0, outbox row and body 5.4 |
| accept (84) | 5 | 20 | the outbox row, its watermark index (2), delivery index, sync metadata (3 bytes) |
| claim (80) | 2 | 8 | the outbox row and its delivery index |

Bodies (89 new in the 13:32 log): audio-segment records 6.9 KB (14 operations), transcript segments 11.8 KB, recording
updates 57 KB (37 KB of it the rollback); every operation repeats its transaction id and time.

Apple's File Activity on the phone (13:27, 60 s, recording): 27.0 MB written; SQLite 17.5 MB (saveLocalMutation 6.48,
commitServerApplyPlan 5.46, a checkpoint 3.43 on a save's call path, acceptOutboxMutation 1.28, the claim 0.51).

The 10-31 launch catch-up (about 7 GB in 17 minutes): about 5.9 GB is five 1.2 GB bursts, each in the same minute as a
"#1057 models compile again once: container changed" line (Core ML after an install, #1429); the library's own share
is the catch-up after it, up to 1.07 GB a minute (checkpoint, server apply, released live-query chunks).

What none of this shows (Michael, 13:30): how the store evolves minute by minute, by statement and by table.

## Steps (red, then green, each through build.sh)

1. This plan and its claims (plan-only commit).
2. Red: `InstantSQLiteWriteRecorderTests`: a store's write cycle (save, claim, accept, a server apply) records the
   write-ahead log's pages by b-tree, every page named (table, index, an overflow chain, page 1, the free list), their
   sum equal to SQLite's own count (`SQLITE_DBSTATUS_CACHE_WRITE`); each write statement's runs, rows and pages, with
   the b-trees it writes as its query shape; a checkpoint's copies by b-tree; the store call by b-tree; the bounds
   (#1285 rule 5: a million calls at a constant stack depth, bounded time and memory).
3. Green: the recorder. The meter's VFS already sees every frame: each frame's page number, and from each b-tree page
   it reads or writes, its children, so a page's b-tree is learned from its parent (the roots from `sqlite_schema`),
   with no extra read and no per-page map beyond one byte a page. The statement cache's check-in counts each write
   statement's rows (`sqlite3_total_changes64`) and its b-trees (its `EXPLAIN`'s `OpenWrite`, once per statement).
   Counts only, values in a lock, nothing recursive, every collection bounded; a page it cannot name counts as
   unnamed, never a crash. Read once a minute with `snapshot()`, like the other two meters.
4. Measure the recorder's own cost with the recording exercise (ab-commits.sh, this branch against main, one job):
   the transact hold and CPU per write, stated on #1510.
5. The app (Scribe plan): the minute row carries the tables and statements (bounded, most pages first), and #1507 (a).
6. Fixes, each an amendment with the recorder's before and after, red then green; candidates measured above, none
   decided: the body's size, the free-page churn its overflow causes, the per-write revision counters, the write keys
   and effect entities a confirm deletes, the outbox's index moves, the live-query ownership a confirm rewrites
   (#1426's lane first), the library's launch catch-up.
7. After each green: land, ledger with land --prepend, "READY FOR BUILD" on #1482. No build cut, tagged or installed.

The write contract stands: transact/save is local materialize and durable outbox only. Nothing is batched, delayed,
throttled, sampled, dropped or limited; the recorder counts every page.

## Touching

- Sources/InstantSwiftDataCore/InstantSQLiteWriteRecorder.swift (new)
- Sources/InstantSwiftDataCore/InstantSQLiteFileMeter.swift (the VFS hands frames, checkpoint pages and b-tree page
  reads to the recorder of the database a file belongs to)
- Sources/InstantSwiftDataCore/SQLitePersistenceStore.swift: `SQLiteStatementCache` (`checkOut`, `checkIn`),
  `transaction(operation:_:)` (the store call around `COMMIT`), and one line after the writer opens (the database's
  recorder, its schema's roots); not the open settings (perf-waste-fixes), `saveLocalMutation` (perf-gate-1491),
  `acceptOutboxMutation` (perf-send-1492), the query cache (perf-read-1498) or the server apply (perf-observe-1493)
- Tests/InstantSwiftDataCoreTests/InstantSQLiteWriteRecorderTests.swift (new)
- docs/audits/2026-10-31-writes-1510.md (new: the page-by-page reading, the recorder's numbers before and after)
- CHANGELOG.md, PROGRESS.md, docs/audits/commit-changelog.md (through land --prepend)

## Conflict check (origin/main 203b1ef7, 2026-10-31 13:45 EDT)

InstantSQLiteFileMeter.swift and its test: last claim sqlite-1245 (#1245), landed. SQLitePersistenceStore.swift: the
five live claims above name other regions; the statement cache and the transaction wrapper are unclaimed. The one
line after the writer opens sits near perf-waste-fixes' `temp_store` line: said in their channel and in mine,
agent-presence/_channels/2026-10-31-perf-writes-1510.md. Rebase onto each landing before a land.

## Amendment 1 (2026-10-31 16:15): a stored body that says each fact once

Measured (13:32 log, build 208): a transcript segment save's body is 11.7-17.9 KB for about 1.3 KB of values; every
operation repeats its transaction's id and time and wraps each value twice (`{"insert":{"_0":{... "value":{"number":
{"_0":..}}}}}`), and the rollback doubles it. Past about 1 KB a body spills into overflow pages of this `WITHOUT ROWID`
table, allocated from the free list (page 1 and its trunk rewritten) at the save and freed at the confirm. perf-send-1492
handed this region over (16:05): its receipt reuse no longer keys on the stored bytes.

What changes: `instant_outbox_bodies.json` is written in a compact form, version 2: the write's other fields encoded as
today, and its operations and rollback as short arrays (a tag, the entity, the attribute, the value, and the operation's
own transaction id and time only where they differ from the write's). A version-1 body still decodes, so a store opened
by an older build and a row written before stay readable; `lifecycle_json` is unchanged. Decoding a version-2 body gives
the same `PendingMutation`, field for field (the six fields the receipt reads among them; the receipt's digest and its
payload do not change).

The one decision, made here: the stored bytes are the write's encoded size everywhere they are counted today
(`encoded_body_bytes`, the claim's projected bytes, the 8 MiB memory and transport envelope), so a save still encodes its
body once (#1491's test stays) and every budget measures what is decoded. A write's version-2 size is about half its
version-1 size, so the envelope admits a write about twice the size it did; said in the release notes, and on #1510.

Steps: red (a round trip of every operation and value kind, version 1 and 2 decoding to the same write, a segment-shaped
body under 6 KB, a version-1 row still read, the recorder's pages for the body and its overflow in the save exercise);
green; the recorder's before and after on the recording exercise and the phone-shaped save; Scribe's
`scripts/recovery/recover-recording-from-outbox.mjs` reads version 2 (a Scribe commit, with its test).

Touching (added): Sources/InstantSwiftDataCore/InstantOutboxBodyCodec.swift (new), SQLitePersistenceStore.swift
(`encodeOutboxBody`, `decodeOutboxBody`, `storedOutboxBody` only), BoundedOutboxDelivery.swift
(`encodedProjectedBodyByteCount` only; not `validateNewMutation`, perf-gate-1491's),
Tests/InstantSwiftDataCoreTests/InstantOutboxBodyCodecTests.swift (new); in Scribe,
scripts/recovery/recover-recording-from-outbox.mjs and its test.

## Amendment 2 (2026-10-31 16:50): a live write's body kept in its leaf, compressed; its lifecycle derived from it (#1463)

Replaces amendment 1's compact re-encoding, which measured too small: on the pulled store's 738 bodies it takes the
median from 8,389 B to 2,595 B and leaves every live body in overflow, where raw deflate alone takes it to 944 B. A
`WITHOUT ROWID` cell keeps at most 1,002 bytes on its leaf, and the cell also holds the body's lifecycle (346 B for a live
write), so a compressed body fits only without it: median cell 856 B, 6 of 8 live bodies and 371 of 738 in their leaf
(docs/audits/2026-10-31-writes-1510.md, "Which levers hold"). A lifecycle is exactly the body with its operations emptied
(`encodeOutboxBody` writes `encode(body.compactedForMemory)`), so a reader can derive it.

What changes, in `instant_outbox_bodies` only:

- `json` holds the stored body's JSON compressed (raw deflate, Apple's Compression framework, `COMPRESSION_ZLIB`) as a
  BLOB. A TEXT value is a body an older version wrote, read as today, and rewritten compressed at its next change.
- `lifecycle_json` is NULL for a compressed body, and a new `lifecycle_bytes` column holds the lifecycle's JSON size; a
  reader of a lifecycle decodes the body and empties its operations. "No lifecycle" (the legacy row a failed-lifecycle
  pass picks up) stays `lifecycle_json IS NULL AND lifecycle_bytes IS NULL`.
- Every budget keeps counting JSON bytes, as today: `encoded_body_bytes`, a lifecycle's bytes, a plan row's staged
  bytes, the claim's projected bytes and the 8 MiB envelope admit exactly the writes they admit today. Only the stored
  length shrinks.
- A comparison of stored bodies compares stored bytes with stored bytes (the same encoder writes both); a check that a
  body is unchanged since it was read binds what was read.

Nothing else changes: the same rows, the same JSON inside them, the same write contract (a save is local materialize and
durable outbox; the compressed body is in the same transaction).

Steps:

1. Red (`InstantOutboxStoredBodyTests`): a live write's save writes no overflow page of `instant_outbox_bodies`, no page 1
   and no free-list page, and its echo frees none (StorageIOWriteCycle, pages by b-tree); a compressed body and its
   derived lifecycle decode to the same write, field for field, for every operation and value kind, a rollback and a
   failure; a TEXT body and lifecycle written by an older version read the same and are rewritten compressed at their
   next change; the claim's projected bytes, the lifecycle admission bytes and `encoded_body_bytes` equal today's.
2. Green: the stored-body codec (new file), one reader for a body column (TEXT as today, BLOB inflated), the writers,
   the sizes, the migration (`ALTER TABLE ... ADD COLUMN lifecycle_bytes`; no rewrite of existing rows).
3. Measure: StorageIOWriteCycle's save and echo frames by b-tree, and the recording exercise (ab-commits.sh, main
   against this branch, one job) for the hold and CPU per write; on the phone after its release, the recorder's
   `instant_outbox_bodies`, page 1 and free-list pages per save.
4. Scribe: `scripts/recovery/recover-recording-from-outbox.mjs` inflates a BLOB body (Node's `zlib.inflateRawSync`),
   with its test; `scripts/perf/query-plans.py` unchanged (it reads plans, not bodies).

Touching (added): Sources/InstantSwiftDataCore/InstantOutboxStoredBody.swift (new); SQLitePersistenceStore.swift: the
body codec (`encodeOutboxBody`, `decodeOutboxBody`, `loadStoredBodyWithDeliveryWithoutTransaction`,
`saveOutboxBodyWithoutTransaction`), every statement that reads or writes `instant_outbox_bodies.json`,
`lifecycle_json` or a body's length (about 45 lines across the store), the server apply's staged body columns
(`staged_json`, `staged_lifecycle_json`: perf-observe-1493's region, said in their channel), one migration;
Tests/InstantSwiftDataCoreTests/InstantOutboxStoredBodyTests.swift (new). Amendment 1's touching list is withdrawn.

Findings recorded on their issues, not built here: the revision counters (#1254) cannot move into memory as filed,
because `instant_query_cache` keeps each answer's `store_revision` across launches; the key rows and effect entities
(#1464) cannot move into `TEMP` tables until every path that deletes them on purpose is an invariant on the row; the
terminal failures' key rows cost disk space, not log pages.
