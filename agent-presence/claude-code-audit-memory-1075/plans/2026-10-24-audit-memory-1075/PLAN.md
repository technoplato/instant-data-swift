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
