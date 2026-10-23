# Plan 2026-10-23-hotpath-1007

- **planId:** 2026-10-23-hotpath-1007
- **agentId:** claude-code/hotpath-1007@halfjew22 (before: @ld, @strangelearning; F1, F2 in v1.9.13 and D3 in v1.9.15)
- **role:** mower (user-ordered energy fixes, issue #1007, part of the device performance lab #1005): every change keeps
  what each observer holds and what reaches the server, and costs less CPU or fewer disk bytes.
- **branch:** agent/claude/hotpath-1005 (worktree ~/Sync/worktrees/instant-data-swift-hotpath-1005), pushed to main
  after each green step, then released (the maintainer's instruction of 2026-10-23 12:04).

## Outcome (#1007)

1. A verified page of a list with includes skips a change it cannot show (a heartbeat, a line or an attachment of a
   recording another page shows), and the placement check behind every skip reads only the fields its plan names
   instead of the entity's whole snapshot (a recording's whole snapshot materializes thousands of refs). Release 1.9.17.
2. The live-query prune (#654) stops copying the whole store on every call, and removes a closed query's orphaned facts
   from the hot store and SQLite by identity instead of rewriting and re-indexing the whole store (which un-verifies
   every observer, so the next publication re-materializes them all).

## Steps

1. Red then green for each outcome; the write harness (wbench1007, Recording 211's replay with the recordings list's
   pages, a heartbeat and bystanders) before and after on the Mac mini; the core suite against main's baseline.
2. CHANGELOG, PROGRESS, audit ledger, release document; tag; the consuming app pins exactly the tag.

## Touching

Sources/InstantSwiftDataCore/InstantStore.swift (refreshDecision only), Sources/InstantSwiftDataCore/TripleIndexes.swift
(hasLink, resultSetMembership, and read helpers for the prune), Sources/InstantSwiftDataCore/InstantRuntime.swift
(pruneLiveQueryResults and performPruneLiveQueryResults only), Sources/InstantSwiftDataCore/SQLitePersistenceStore.swift
(pruneLiveQueryResults and its helpers only), Tests/InstantSwiftDataCoreTests/InstantIncludePlanSkipTests.swift,
Tests/InstantSwiftDataCoreTests/InstantResultSetMembershipCostTests.swift, Tests/InstantSwiftDataCoreTests/ (new prune
tests), CHANGELOG.md, PROGRESS.md, docs/audits/commit-changelog.md, docs/releases/ (the release documents).

## Conflict check

#1006 (local-reads-1006, claimed 14:44) adds local reads, a read connection and one line in the server apply; it reads
TripleIndexes and adds a read-only InstantStore helper: no shared function. #932 (server-apply-932) edits the server
apply's attempt loop, resident patch, gate timeline and SQLite server-apply functions: no shared function. #1011
(telemetry-1011) edits InstantEnergyMeter and two meter lines in SQLitePersistenceStore: no shared function. The prune
changed last in 1.9.13 (#1006's unload); #1006 says its library part is done.
