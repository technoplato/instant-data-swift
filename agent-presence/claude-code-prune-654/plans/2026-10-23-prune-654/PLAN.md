# Plan 2026-10-23-prune-654

- **planId:** 2026-10-23-prune-654
- **agentId:** claude-code/prune-654@strangelearning
- **role:** mower (energy fix ordered for the device performance lab #1005; issue #654): the live-query prune keeps and
  drops exactly what it did, at a cost in proportion to what it drops instead of to the store.
- **branch:** agent/claude/prune-654 (worktree ~/Sync/worktrees/instant-data-swift-prune-654), red ad72e068 and green
  fe1f2821 pushed; merged to main after the whole core bundle compares clean with Tests/known-failing.txt, then
  released as the next free tag (v1.9.31 after #1012's v1.9.30).

## Outcome (#654)

Each prune batch copied the hot store (`InstantStore.snapshot()`), built a dictionary of every fact, diffed the whole
store into SQLite and replaced and re-indexed the hot store (`replaceSnapshot`); build 118 held the operation gate
1,385 ms and 4,168 ms in it on an iPhone. A batch now chooses its results from their rows, reads the hot store's facts
of only the entities those results held, drops the results and the unowned entities in one SQLite transaction, and
retracts those facts in place. The bootstrap prune runs the same batch, unbounded.

## Steps

1. Red (InstantPruneCostTests: 40,002 kept facts, 24 closed results; zero full copies and replacements, same kept and
   dropped sets, indexes equal to a rebuild; a measurement test for the longest gate hold at 4k and 40k facts).
2. Green; the prune suites; the whole core bundle against Tests/known-failing.txt on the Mac mini.
3. Release-build harness at 10k/40k/100k facts before and after (longest gate hold, CPU, malloc peak).
4. CHANGELOG, PROGRESS, audit ledger, docs/releases/v1.9.31.md; tag; Scribe and Scribe Playback pin it exactly.

## Touching

Sources/InstantSwiftDataCore/InstantRuntime.swift (pruneLiveQueryResults, performPruneLiveQueryResults, the new
pruneLiveQueryResultsBatch, and the bootstrap prune call only), Sources/InstantSwiftDataCore/SQLitePersistenceStore.swift
(pruneLiveQueryResults, the new liveQueryResultPruneBatch / applyLiveQueryResultPruneBatch and their helpers,
unloadLiveQueryResultWithoutTransaction), Sources/InstantSwiftDataCore/InstantStore.swift (facts(of:) comment and the
new retractFactsReleasedByPrune), Tests/InstantSwiftDataCoreTests/InstantPruneCostTests.swift (new), CHANGELOG.md,
PROGRESS.md, docs/audits/commit-changelog.md, docs/releases/v1.9.31.md.

## Conflict check

The three source files carry earlier claims (#990, #959, #1006, #1007, #932, #653, #669). #1007 (hotpath-1007) listed
"later: the live-query prune" in its plan and deprioritized it (its #1007 log, 19:30); its last state is v1.9.28
shipped, waiting on device data, with no prune change on a branch. #1006 changed the prune last (the unload into
instant_unloaded_live_query_results), which this keeps as it is. #1012 (audio-stream-1012b, tonight's other library
agent) works in InstantSwiftDataMedia and released v1.9.30. No shared function is edited by a running agent.
