# Plan 2026-10-27-sqlite-1245: SQLite's own counters per store call and per file kind, and a cheaper write per live line

- planId: 2026-10-27-sqlite-1245
- agentId: claude-code/sqlite-1245@halfjew22 (tools/agent-run, claude/halfjew22, opus)
- role: grower for the counters (#1245 orders them: "let's do SQ Lite's own tools as well and figure out how to
  optimize our writing strategies"); mower for the write fixes
- issues: #1245 (this), #1241, #1214 (parent), #1115 (the outbox's b-trees), #1119 (temp files)
- branch: agent/claude/sqlite-1245 (worktree ~/Sync/worktrees/sqlite-1245-instant); released per AGENTS.md, pinned by
  the consuming app; no build is cut

## Why (measured, before any change)

The phone's own write-ahead log, read frame by frame on a copy pulled 2026-10-27 11:16-11:19 (build 144, 1.9.45, 91
commits, 1,313 frames, each frame's page mapped to its b-tree by `dbstat` and classified by its own bytes): about 69% of
the frames are the outbox row's life (its body's overflow pages, freed again within a second; the freelist trunk and
page 1 the allocations rewrite; the write keys and their lookup index; the delivery, watermark, primary-key and effect
indexes), 8% are the facts themselves. The consuming app's ledger over a 58-minute recording: the four write calls
1.71 GB/h of log pages, and 0.80 GB/h no meter names (checkpoint copies, temp files and journals are not counted).

## Steps

1. This plan and its claims (plan-only commit).
2. Red, then green: `InstantSQLiteFileMeter`, a pass-through VFS in front of the system's that every connection of the
   store opens through; per kind of file (database: a checkpoint's copies; write-ahead log; temporary database and its
   journal; statement journal; transient sort files) it counts bytes written, write calls, syncs and full syncs, with
   atomic adds only (no allocation, no I/O, no lock per write).
3. Red, then green: `InstantStorageWriteMeter` per store call also carries SQLite's own counters: the page cache's hits,
   misses and spills (`sqlite3_db_status`), and its statements' VM steps, full-scan steps, sorts, automatic indexes and
   re-prepares (`sqlite3_stmt_status`, read with reset where the statement cache takes each statement back).
4. EXPLAIN QUERY PLAN of the write calls' statements on the phone copy; the real-size exercises
   (`STORAGEIO_EXERCISES=1`) per b-tree before and after each fix.
5. Fixes, each red then green with frames per write before and after: chosen from steps 2-4 (candidates: the
   revision counters' page rewritten each commit; outbox indexes rewritten on states the queries never read; the
   write keys' two b-trees). The write contract (a save waits for the local store and the durable outbox only;
   offline writes succeed) and the consuming app's feature list stay whole. Each choice is an amendment here naming
   its functions before they are edited.
6. Audit docs/audits/2026-10-27-sqlite-write-strategy.md; release; ledger; footguns to toolbox-1244 through #1214.

## Touching

- Sources/InstantSwiftDataCore/InstantSQLiteFileMeter.swift (new)
- Sources/InstantSwiftDataCore/InstantStorageWriteMeter.swift
- Sources/InstantSwiftDataCore/SQLitePersistenceStore.swift: openRawConnection, transaction, cacheWritePages,
  recordStorageWrites, SQLiteStatementCache.checkIn (amendments name any other function first)
- Sources/InstantSwiftDataCore/SQLiteReadConnection.swift (its open only)
- Tests/InstantSwiftDataCoreTests/InstantSQLiteFileMeterTests.swift (new),
  Tests/InstantSwiftDataCoreTests/InstantStorageWriteMeterTests.swift
- docs/audits/2026-10-27-sqlite-write-strategy.md (new), docs/releases/ (the release), CHANGELOG.md, PROGRESS.md,
  docs/audits/commit-changelog.md

## Conflict check

SQLitePersistenceStore.swift: the last claims are landed slices (fix-storage-1076, fix-memory-1075, b301-disk). toolbox-1244
claims docs/FOOTGUNS.md and FootgunGuardTests.swift: I do not edit them; footguns go to them through #1214's log.
