# Plan 2026-10-30-sqlite-writes-1426: a server refresh writes what changed, not the whole result

- planId: 2026-10-30-sqlite-writes-1426
- agentId: claude-code/sqlite-writes-1426@strangelearning (tools/agent-run, claude/strangelearning, opus)
- role: mower (fewer bytes written for the same results; no new surface)
- issues: #1426 (P1, this), #1425 (heat-trace), #1423 (the app's list shape, not touched here), #1123 and #566 (the
  result JSON's interval and repair), #1076 (the storage audit)
- branch: agent/claude/sqlite-writes-1426 (worktree ~/Sync/worktrees/sqlite-writes-1426), released per AGENTS.md and
  pinned by the consuming app

## Why (measured, before any change)

The phone's energy ledger (2026-10-30 12:00-17:14, 153 recording minutes without launch spikes): 2,553 server-apply
commits an hour at 131 KB each, 334 MB/h; the save, claim and acknowledgement about 375 MB/h; checkpoints about 290-360.

The brief's premise (a refresh rewrites the rows it restates) is ruled out, on the phone's store copy and in a harness:

- Store copy (counts only): the biggest list's 1,000 facts carry 120 distinct stamps; facts keep the stamp of the write
  that made them, so refreshes do not rewrite unchanged facts.
- Harness on main `2a6e6221` (`StorageIOExercises.aRefreshWritesWhatChangedNotWhatItRestates`): 50 todo rows with one
  changed write 9.0 log frames a refresh against 10.0 for one row; phone-shaped recordings held by three results, 12.0
  against 8.0.

What does follow the result instead of the change:

1. Each changed result's whole JSON, written again every 5 minutes (#1123): over five minutes of refreshes 6 s apart,
   50 rows wrote 85.4 KB a refresh against 33.7 KB for one row (9.7 of 20.7 frames in `instant_live_query_results`).
2. After a relaunch, the first answer that restates an unchanged stored result writes its whole JSON: the process does
   not know the stored JSON's page info yet (code reading; a red test measures it).

## Steps

1. This plan and its claims (plan-only commit).
2. Red: the refresh exercises (todos and phone-shaped recordings, 50 rows against 1; five minutes of list refreshes; a
   relaunch's unchanged and one-changed answers) with the brief's bound, twice the one-row refresh plus two log frames;
   a replay on a copy of the phone's store (laptop only, counts only); a live write's save, claim, acknowledgement and
   echo by b-tree.
3. Green: a stored result's JSON is written when the result is first stored and at the app's flush, an unsubscribe or
   the close, not every five minutes; the ownership rows stay exact on every refresh and a result whose JSON waits is
   rebuilt from them at the next launch (#566). The page info a waiting result holds is kept exact in its marker, so the
   rebuild needs nothing the JSON holds. A relaunch learns the stored JSON's page info, so an unchanged answer writes
   only its row's count and time.
4. Measure again with the same exercises and the replay; file the next levers with MB an hour (the identity index, the
   local save and its outbox row, the echo's outbox work, large values keyed in three b-trees, the launch catch-up, the
   refused rows scanned at launch); release; bump Scribe; build and install.

The write contract stays whole: a save waits for the local store and the durable outbox only; offline writes succeed
and replay; every result a reader sees is the newest one, from memory in this process and from the rebuilt rows after a
kill.

## Touching

- Sources/InstantSwiftDataCore/SQLitePersistenceStore.swift: the live-query result JSON's write decision, its flush, its
  marker, and the bootstrap rebuild (`repairDeferredLiveQueryResultJSON`)
- Sources/InstantSwiftDataCore/InstantRuntime.swift: the result JSON interval's configuration only
- Tests/InstantSwiftDataCoreTests/InstantServerRefreshWritesTests.swift (new)
- Tests/InstantSwiftDataCoreTests/InstantServerRefreshReplayTests.swift (new)
- Tests/InstantSwiftDataCoreTests/InstantLiveQueryResultWriteTests.swift (the interval's tests)
- docs/releases/ (the release), CHANGELOG.md, PROGRESS.md, docs/audits/commit-changelog.md

## Conflict check

SQLitePersistenceStore.swift and InstantRuntime.swift: the last claims (sync-jam-1378, ack-deferral-1383, vision-396)
are released slices; the other library worktrees (audio-1262, sqlite-1245 at 7a5a173a; vision-1404) have no commits on
these files past origin/main. InstantLiveQueryResultWriteTests.swift: last claimed by #1123's slice, released.
