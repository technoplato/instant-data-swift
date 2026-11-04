# Plan 2026-11-04-perf-recv-1797: a server refresh costs what changed, not the whole result

- planId: 2026-11-04-perf-recv-1797
- agentId: claude-code/perf-recv-1797@pp (tools/agent-run, claude/pp, opus)
- role: mower (the same emissions, stored results and acknowledgements from less work per refresh; no new public
  surface)
- issues: #1109 (primary), #1513, #1147, #1480, #1116, #1127, #590; #1440 and #1123 to verify and close; epic #1797
  (trace audit 2026-11-04), #1783. #1122 and #1107 go to perf-mem-1797 (their #1500 step 7 and #1149 are the same
  code), as their channel proposes.
- branch: agent/claude/perf-recv-1797, worktree ~/Sync/worktrees/perf-recv-1797 cut from origin/main da175eb7; every
  green lands on main, rebased first

## Why (measured)

The phone's own energy ledger, build 248, 2026-11-04 16:02-17:30 (88 min recording, 352 finals, 3,811 refresh-ok
frames, 318 MB of refresh text; `refresh-cost.py --build 248 --json`), CPU-s by library operation on the receive side:
observerRefresh 41.8, frameDecode 16.2, serverApplyPlan 15.3, serverApplyRetractions 15.0, refreshTranslate 14.0,
serverApplyCommit 9.4, prune 5.3, deferredHydrate 3.3. One minute of it (17:29) per event: a refresh-ok decoded in
about 4.9 ms, translated 3.2, planned 3.9, its retractions 3.2, committed 1.4; a publication 6.2 ms. The 15:55
on-device trace (build 247) puts `handleLiveServerEvent` at 7.6% of Scribe's CPU, `applyLiveRefresh` 6.4%,
`publishCommittedChanges` 3.9%, `serverApplyPlanningReads` 2.1%, and `AttributeLookup.init`
(InstantLiveQueryNestedLimit.swift:172) among the top self symbols. 63% of the refresh bytes are the recordings list
(145 KB a computation, about 18 a minute); the query shapes are perf-queries-1423's, the per-refresh cost is mine.

Where the work goes per refresh (read at da175eb7, to be measured before each fix):
- Publication: a final adds a line that becomes the live recording's preview: the new line is shown by no row yet and
  the recording's order key moves, so `splicedEmission` declines and the whole list re-materializes, as do the
  transcript windows (#1513: 92% of the publication in `materializePage`, p50 18.4 ms a final on an M4).
- Planning reads: each restated result is diffed against its stored ownership rows twice, once for the retractions and
  once for the save, each pass encoding every restated value's stored text and reading every row (#1480, #1116); the
  save runs the nested limit a second time and the persisted result is deduplicated and sorted whole.

## Steps

1. This plan and its claims (plan-only commit) on main.
2. #1513/#1147/#1109 red: the publication of a final on Scribe's list shape re-materializes the list; a differential
   test holds every spliced emission equal to the materialized one (orders, windows, includes, links that move).
3. Green: the publication splices a changed root in place when every changed entity is shown, or reaches a shown root
   through an included link before or after the change, and no root's place in the ordered window can move (an order
   key that moves keeps its place among the shown rows and away from the window's edge); anything else re-materializes
   as today. Measured: PublishFanOutExercises (final publication p50) and the counted re-materializations.
4. #1480/#1116 red: a refresh reads each restated result's ownership rows and encodes its values twice.
5. Green: one diff per restated result: the retractions and the save share one read of the stored rows and one pass
   over the restated values; the save takes the translation's nested-limited facts instead of limiting again; the
   persisted result keeps the frame's order instead of a sort. Measured: rows read and values encoded per refresh,
   StorageIOExercises' echo (reads, CPU), E03.
6. Decode and translate: measure a list refresh's split, then remove the largest waste (the nested limit's attribute
   maps per call first).
7. #1127/#590: read the phone's applier waits and thread QoS first (ledger), then, if the evidence says so and after
   talking with perf-sync-1796, acknowledgements and one-shot answers on arrival. A QoS change ships only with
   frame-to-screen latency measured no worse (pre-plan check); otherwise it is a PROPOSAL on #590.
8. #1440, #1123: check against v1.9.67 (the header's update reads no JSON; no whole result is written) and close
   with the evidence.
9. Release each green step (next free v1.9.x), pin it in Scribe, cut and install; after an hour on the phone,
   `refresh-cost.py --build <new>` before/after on #1797.

## Touching

- `Sources/InstantSwiftDataCore/InstantStore.swift` (refreshDecision, splicedEmission, orderKeyChanged and the
  publication metrics only; not the residency perf-mem-1797 adds)
- `Sources/InstantSwiftDataCore/TripleIndexes.swift` (the read-only root membership and snapshot helpers the splice
  asks; not inserts, residency or the newest-time counts)
- `Sources/InstantSwiftDataCore/SQLitePersistenceStore.swift` (serverApplyPlanningReads, the retraction diff and the
  result saves' preparation only; not deferred loads, the prune, unload or reload)
- `Sources/InstantSwiftDataCore/LiveQueryOwnershipDiff.swift`, `InstantLiveRefreshApplication.swift`,
  `InstantLiveQueryNestedLimit.swift`, `InstantLiveJSONParser.swift`
- `Sources/InstantSwiftDataCore/InstantRuntime.swift` (applyLiveRefresh and performApplyServerTransaction's planning
  turn only; not transact, not the deferred loads perf-mem-1797 generalizes)
- `Sources/InstantSwiftDataCore/InstantRuntimeLiveSession.swift` (step 7 only, after perf-sync-1796 agrees)
- Tests: new `InstantRefreshSpliceTests.swift`, `InstantRefreshPlanningReadTests.swift`; `RealSize/PublishFanOutExercises.swift`,
  `RealSize/MemoryExercises.swift` (E03's budget), `RealSize/StorageIOExercises.swift`
- `CHANGELOG.md`, `PROGRESS.md`, `docs/releases/v1.9.*.md`, `docs/audits/commit-changelog.md` (release and ledger)

## Conflict check

- perf-mem-1797 (#1500, #1165, #1145): InstantStore/TripleIndexes residency and the server apply's deferred loads are
  theirs; my splice reads the indexes, never their residency. #1122 and #1107 are theirs (channel 2026-11-04-perf-mem-1797).
- perf-send-1797 (#653): transact, the outbox, #1434's ownership value text; my diff reads ownership rows through the
  existing statements and writes them through `applyLiveQueryOwnershipChangesWithoutTransaction`, unchanged.
- perf-sync-1796 (#1796, #1127's neighbours #1129/#1131): the applier and acknowledgements; step 7 waits for their word.
- Channel: agent-presence/_channels/2026-11-04-perf-recv-1797.md
