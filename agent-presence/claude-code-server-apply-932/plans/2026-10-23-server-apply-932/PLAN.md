# Plan 2026-10-23-server-apply-932

- **planId:** 2026-10-23-server-apply-932
- **agentId:** claude-code/server-apply-932@halfjew22
- **role:** grower (user-ordered, issues #932, #998, #590 under the device performance lab #1005), kept to the server
  apply: no new public read API; one configuration property for the sync tasks' priority.
- **branch:** agent/claude/server-apply-932 (worktree ~/Sync/worktrees/instant-data-swift-server-apply-932), pushed to
  main after each green step, then released.

## Outcome (#932, #998, #590)

A server apply costs what its frame changes, not what the outbox holds, and holds the operation gate only for its commit:

1. The gate-held event names the apply's path (reduced, or why it peeled and replayed its whole component), its attempt,
   the writes it peeled and replayed, and where its commit spent its time (validation, facts, outbox, results, the
   SQLite `COMMIT`, and the wait for the persistence actor). Today the phone shows "commit 3,914 ms" and nothing more.
2. The work under the gate is bounded by the frame: the resident patch reads only the rows the in-memory outbox holds;
   a body page validates only its own rows; the commit updates changed outbox rows in one join.
3. A frame that restates a row a pending write deletes (a recording's live line, deleted by its final) is reduced
   instead of peeling and replaying every pending write.
4. Local writes that land between an attempt's seed and its plan no longer force an apply that holds the gate from seed
   to commit.
5. Steady-state sync tasks run at utility priority (#590); reads and writes a caller awaits keep the caller's priority;
   write -> acknowledgement latency is measured before and after and is no worse.

## Steps

1. Red tests (InstantServerApplyGateWorkTests) and a cost harness (InstantServerApplyCostTests: per frame wall time,
   gate hold and phases, longest read wait, CPU, instructions, logical bytes written; also against a copy of a real
   store), Scribe's live lines in the fast-drain fixture with reduced-versus-full differential seeds.
2. Green, one commit each: the gate-held event's path and commit timing; the resident patch; page-scoped validation;
   the commit's join and the staging table's column order; the live-line reduction; the stale-attempt retry; the sync
   tasks' priority.
3. The server-apply, gate, outbox and live-query suites after each green, on the Mac mini; the whole core suite
   against main's baseline; measurements before and after; CHANGELOG, PROGRESS, audit ledger; release.

## Touching

Sources/InstantSwiftDataCore/InstantRuntime.swift (performApplyServerTransaction, the reduction, the gate timeline, the
sync tasks' priority), Sources/InstantSwiftDataCore/SQLitePersistenceStore.swift (commitServerApplyPlan, the body page
and resident patch reads, the plan validation, the staging table, the reduction context),
Sources/InstantSwiftDataCore/Outbox.swift (resident ids and one-turn patch),
Sources/InstantSwiftDataCore/InstantRuntimeLiveSession.swift and
Sources/InstantSwiftDataCore/InstantRuntimeReconnectController.swift (task priority only),
Tests/InstantSwiftDataCoreTests/InstantServerApplyGateWorkTests.swift (new),
Tests/InstantSwiftDataCoreTests/InstantServerApplyCostTests.swift (new),
Tests/InstantSwiftDataCoreTests/InstantFastDrainTests.swift, Tests/InstantSwiftDataCoreTests/InstantBoundedServerApplyRebaseTests.swift,
CHANGELOG.md, PROGRESS.md, docs/audits/commit-changelog.md, docs/releases/ (the release document).

## Conflict check

#1006 (transcript-open-1006) adds one line before the server apply's "commit plan" phase and a gate write annotation;
agreed on #932 and #1006: it touches none of the functions above otherwise. #1007 (hotpath-1007) edits InstantStore's
publication path and TripleIndexes: this plan touches neither; the newest-stamp walk per replayed write
(TripleIndexes.newestTransactionTimeMilliseconds) is left to #1007. #1011 (telemetry-1011) put the staging and retraction
meter lines in 1.9.16: this plan keeps them. Channel: agent-presence/_channels/2026-10-23-server-apply-932.md.
