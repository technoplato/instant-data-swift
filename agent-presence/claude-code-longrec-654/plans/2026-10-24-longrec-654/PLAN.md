# Plan 2026-10-24-longrec-654

- **planId:** 2026-10-24-longrec-654
- **agentId:** claude-code/longrec-654@ld
- **role:** mower (energy fix ordered for the device performance lab #1005; issues #654 and #932): a stored file looked
  up by id costs one file's work, whatever the account has uploaded, so the prune and the server-apply commit stop
  re-loading and re-dropping every file once a minute while a recording runs.
- **branch:** agent/claude/longrec-654 (worktree ~/Sync/worktrees/instant-longrec-654), rebased on main and pushed after
  each green; released as the next free tag (v1.9.33 after v1.9.32).

## Outcome (#654, #932)

Build 121, both devices (the collector's rows, 2026-10-24): a download of a file the device has no record of, by id and
without a name, ran a one-shot query of every `$files` row (`instant.storage.files`: 9,455 files, 75,640 facts,
24.8 MB of result on the phone's store; about 10,400 files by 10:30). The query timed out at 5 s, its late answer was
applied anyway (server apply 2.3-5.8 s under the operation gate, about 27 MB of result JSON, about 10,300 changed
entities), and the next session prune unloaded the closed result again (3.8-6.0 s under the gate): once a minute while
the media scan ran, every 10-20 s on the Mac. The lookup now asks storage for that one file by id.

## Steps

1. Red: a download by id with no name and no record sends a `$files` query on that id, and stores that one file's
   facts however many files the account holds (InstantStoredFileLookupTests, new).
2. Green: `remoteStoredFile(id:)` (one row) for storedFileContents(id:name:) and downloadStoredFile(id:name:to:);
   storedFiles() and observeStoredFiles() keep the list, which is what they return.
3. Measure on a copy of the phone's store (never committed, never sent anywhere, deleted after): the lookup's apply and
   the prune after it, gate hold, CPU and memory, before and after, at the real 9,455 files and at 2x.
4. Possibly a second slice, upstream parity: an add-query-ok for a query no longer registered is not applied
   (Reactor.js drops it: no querySubs entry), with its own red test.
5. Whole core bundle against Tests/known-failing.txt; CHANGELOG, PROGRESS, audit ledger, docs/releases/v1.9.33.md; tag;
   Scribe and Scribe Playback pin it exactly (pin files only).

## Touching

Sources/InstantSwiftDataCore/InstantRuntime.swift (storedFileContents, downloadStoredFile, remoteStoredFiles and a new
remoteStoredFile(id:); for step 4 only the .addQueryOK case of handleLiveServerEvent),
Tests/InstantSwiftDataCoreTests/InstantStoredFileLookupTests.swift (new), CHANGELOG.md, PROGRESS.md,
docs/audits/commit-changelog.md, docs/releases/v1.9.33.md.

## Conflict check

InstantRuntime.swift carries earlier claims (#990, #959, #1006, #1007, #932, #654's prune); all have landed. The running
agents today are this one and stamp-412 (Scribe's recording screen, not the library). #959 (storage-959) last changed
the stored-file functions and has landed; nothing else is on a branch in them.

## Amendment, 2026-10-24 13:40 (build 123's first minutes)

The device lab saw one whole-`$files` query left on build 123: `deleteStoredFile(id:)` finds its file through
`storedFiles()`, every file the account holds; Scribe calls it to remove a chunk it uploaded when the chunk's row could
not be written, and it timed out at 5 s (the chunk then stayed in storage). Step 6: red, then green, for
`deleteStoredFile(id:)`: the device's own record (an upload always leaves one), else a `$files` query on that id;
release v1.9.34 and pin it. Touching adds: `deleteStoredFile(id:)` in InstantRuntime.swift, docs/releases/v1.9.34.md.
