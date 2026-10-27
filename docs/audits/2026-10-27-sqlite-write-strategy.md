# Where the store's writes go, read from its own write-ahead log (#1245), 2026-10-27

## Bottom line

**About 69% of the frames a recording's writes put in the write-ahead log are the outbox row's own life; 8% are the
facts.** Measured on a read-only copy of one device's store (1.9.45): 1,313 valid frames in 91 commits, 72 s of a
recording. In the consuming app's energy ledger for a 58-minute recording on the same build, the four write calls
behind a live write wrote about 63 pages (259 KB) of log per write and 1.71 GB an hour; 0.80 GB an hour of the process's
writes had no meter. 1.9.46 meters the rest (`InstantSQLiteFileMeter`) and gives every store call SQLite's own counters.

## How it was measured

- **The log, frame by frame.** A frame is valid while its salts match the log header's and its cumulative checksum
  holds. Each frame's page number maps to its table or index with `dbstat` on a scratch copy (log applied); each frame
  is also classified by its own bytes: a b-tree page by its flag byte, an overflow page, a freelist trunk, page 1. A page
  `dbstat` no longer places was freed after the frame was written. Commits are grouped by the b-trees they touch.
- **SQLite's catalog** on the copy: `pragma foreign_key_list`, `index_list`, `index_info`, row counts.
- The scripts are the consuming app's audit's (`wal_frames.py`, `wal_content.py`); the copy is private and is not in
  the repository, only the counts it produced.

## What one live write costs, by transaction

| Transaction | Commits | Frames each | Where the frames go |
| --- | --- | --- | --- |
| Local save | 22 | 25.4 | facts 100, write keys 62 and their lookup index 72, overflow pages freed later 53, b-tree pages freed later 47, `instant_sync_metadata` 25 |
| Server apply | 13 | 26.2 | `instant_live_query_results` 66, write keys 46 and lookup 34, the result triples' identity index 36, result triples 18 |
| Claim or acceptance | 40 | 8.2 | overflow pages rewritten then freed 108, watermark index 44, delivery index 40, page 1 36, freelist trunk 36, `instant_sync_metadata` 28 |
| Files | 13 | 4.6 | `instant_files` and its two indexes |

The consuming app's ledger agrees per call: 23.4 pages a save, 26.3 an apply, 7.7 a claim, 10.6 an acceptance.

## Findings

1. **A claim or acceptance rewrites the body's overflow chain** (#1115's next slice). The delivery columns sit after
   the body, and the acceptance re-encodes `json` and `lifecycle_json`; SQLite overwrites a record in place only when
   its payload keeps its size, so each state change frees and reallocates every overflow page, and the allocation
   rewrites the freelist trunk and page 1. 55% of the claim and acceptance frames. Keep the body in its own row (or the
   changing state in columns read over a body that is written once).
2. **Full-row writes multiply every b-tree** (#1253, #1255). A progressive media stream's row restates 13 fields every
   segment where 3 change (59% of the fact records the log held); each field is a retract and an insert in the outbox
   body, a write-key row in two b-trees, and a fact in the echo. A partial write is never eligible for immediate-tail
   supersession, so offline it keeps one outbox row per write.
3. **The server apply rewrites live result rows that hold their JSON** (#1123): live results and their triples are
   35% of an apply's frames.
4. **A revision counter's page is rewritten by nearly every write transaction** (#1254): `instant_sync_metadata`,
   5.5% of the frames, 0.8 per commit, for counters only the writer reads.
5. **Allocation churn**: page 1 and the freelist trunk are 11.8% of the frames, from the overflow pages of findings 1
   and 2.

SQLite's catalog: `instant_outbox` carries nine indexes besides its primary key; refused writes stay (59 write keys
each on that copy); three foreign keys have a child column no index leads (`instant_outbox_lifecycle_aliases
.lifecycle_id`, `instant_stream_content_chunks.stream_id`, `instant_stream_writers.stream_id`), so a parent delete
scans the child (FOOTGUNS.md F59-F64).

## What 1.9.46 measures

- `InstantSQLiteFileMeter` (red `3332dc8a`, green `b4ee694b`): per kind of file, the bytes and calls written and read,
  syncs, full syncs and their time, truncates. In WAL mode only a checkpoint writes the database file, so its bytes are
  the checkpoints' copies; the temporary database's own pages are also in the store calls' pages
  (`SQLITE_DBSTATUS_CACHE_WRITE` sums every attached database), its journal and the transient sort files are not.
- `InstantStorageWriteSnapshot.Measure.sqlite`: per store call, VM steps, full-scan steps, sorts, automatic-index rows,
  re-prepares, cache hits, misses and spills.

## Not measured yet

- The file meter's split on a device (the consuming app's ledger names `sqlite.checkpoint`, `sqlite.temp` and
  `sqlite.wal-other` from its next build).
- Bytes per write after findings 1 to 4 (each issue names its measurement).
