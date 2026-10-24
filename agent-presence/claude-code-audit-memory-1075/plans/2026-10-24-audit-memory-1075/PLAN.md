# Plan 2026-10-24-audit-memory-1075

- **planId:** 2026-10-24-audit-memory-1075
- **agentId:** claude-code/audit-memory-1075@ld
- **role:** grower (ordered on #1075: "find any anti patterns and design solutions with hypothesized savings and then
  write real exercises of the poor hot paths"); no library source change unless a fix is one line with a passing
  exercise, named here by amendment before it is made.
- **branch:** agent/claude/audit-memory-1075 (worktree ~/Sync/worktrees/instant-audit-memory-1075), rebased on main and
  pushed to main with the exercises and the audit.

## Outcome (#1075)

An audit of the library's memory: every anti-pattern found on a hot path (allocations per operation, whole results
decoded at once, boxing, copy-on-write copies of large values, caches without bounds, strings not interned, retain
cycles and leaks, footprint that grows over hours), each with its file and line, how often it runs while Scribe
records, and what it costs (measured, or "not measured yet"); a design for each, its saving written as a hypothesis
with what measures it; committed exercises that drive each poor path at real size and print stable numbers
(allocations and bytes per operation; a long-run replay of a two-hour recording's writes and reads reporting footprint
at minutes 5, 60 and 120); today's baseline from them; one issue per fix, worst first, linked to #1075 and #1072.

## Steps

1. Read the library's hot paths for the anti-patterns (parallel read-only readers), and map Scribe's recording workload.
2. Exercises under `Tests/InstantSwiftDataCoreTests/RealSize/`, built on #1072's `RealSizeFixture` and `RealSizeMeter`
   (owned by #1072; changes asked for on its channel), measurement-only (`.measurement` trait), printing stable lines.
3. Baseline runs through `~/Sync/tools/safe-heavy/heavy.sh`; a real-size check on a local copy of the phone's store
   (never committed, never copied into the repo).
4. One issue per fix, worst first by measured cost, each naming its exercise and baseline.
5. `docs/audits/2026-10-24-memory-audit.md`; CHANGELOG, PROGRESS, the audit ledger; push to main.

## Touching

New: `Tests/InstantSwiftDataCoreTests/RealSize/MemoryExercises.swift`, `MemoryLongRunReplay.swift`,
`MemoryAllocationCounter.swift` (only if #1072's meter lacks a counter the exercises need),
`docs/audits/2026-10-24-memory-audit.md`, `scripts/memory-exercises/run-memory-exercises.sh`.
Changed: `CHANGELOG.md`, `PROGRESS.md`, `docs/audits/commit-changelog.md`.

## Conflict check

#1072 (lib-audit-1072) owns `RealSizeFixture.swift`, `RealSizeMeter.swift`, `RealSizeBudgetTests.swift` and
`RealSizeReport.swift` beside these files; this plan only calls them and asks on
`agent-presence/_channels/2026-10-24-lib-audit-1072.md` for any change. #1074 (concurrency) and #1076 (storage) hold no
claims on these paths. No library source file is claimed.

## Amendment 1 (2026-10-24 16:50 EDT, claude-code/audit-memory-1075@strangelearning)

Continued on another account after the first stopped on quota at 16:22; nothing it committed is redone. #1072's
fixture, meter and report landed on main (0f404f0b), and its meter already counts what the exercises need (allocations,
bytes, net live bytes, peak live bytes, footprint peak), so `MemoryAllocationCounter.swift` is dropped. Added:
`Tests/InstantSwiftDataCoreTests/RealSize/MemoryReplayServer.swift`, a scripted server for the memory exercises that
keeps no frame history (#1072's `RealSizeServer.sent` and `RealSizeApplyLog` grow by every frame and apply, which a
two-hour replay would read as the library's growth) and hands the runtime JSON text frames through the production
decoder (`InstantLiveMessage.decoded(fromFrame:)`), so a frame's decode is in the measurement. It plugs into the
fixture through `RealSizeFixture.open(configure:)`; no change to #1072's files. Still no library source change.

## Amendment 2 (2026-10-24 17:56 EDT, claude-code/audit-memory-1075@halfjew22)

Continued on a third account after the second stopped on quota at 16:54; nothing committed is redone. Same claimed
files, no new ones. Three harness corrections, each found by the exercises themselves and each kept to this audit's own
files (#1072's fixture files are unchanged; the notes for #1072 and #1076 are on #1072's channel):
- The exercises write Scribe's shapes (`MemoryScribeWrites` in `MemoryExercises.swift`: typed `update`/`updateExisting`
  inserts, each finished line linked to its recording, the line in progress deleted). #1072's `.merge` writes never
  materialize a new row in memory, so the first exercises missed the link set, the cascade preview and new index
  entries. The `recordings/segments` link is added to the exercise sessions' schema only.
- `MemoryReplayServer.swift` sends integer transaction ids (`MemoryTransactionIDs`), as Instant's server does: the
  library covers a write by a refresh only when both ids are integers, so string ids kept every acknowledged write as
  an overlay that each apply replayed (the first numbers measured that, not the library). #1072 fixed its own server
  the same way in fixture version 3 (4dac9e18).
- On a version-2 store, each session's own copy has the generator's 783 uncoverable confirmed writes re-pointed to id
  1 (`MemoryStoreCopy`), so the session's first apply prunes them through the library's watermark path before anything
  is measured (the phone's copy keeps 3); a version-3 store has none.
The real-size check on the phone's own store runs on this laptop only (the heavy lane), launch exercise only; the store
is opened read-only and copied only into a temporary session directory the exercise removes. Still no library source
change.
