# Plan 2026-10-28-gate-1319: a prune batch stays short, never spans a suspension, and the gate measures running time

- planId: 2026-10-28-gate-1319
- agentId: claude-code/gate-1319@al (in-session subagent of claude-code/battery-301@al, opus 5.5 max)
- role: mower (fixes at the cause in the prune's batch, the gate's clock, and the prune's lifetime)
- issues: #1319 (P1, this); related #1129 (prune off the applier), #654 (proportional batches), #259 (whole-entity
  rule), #1131, #1134, #1136, #1139, #1143 (gate holds), #1285 (diagnostics rule)
- branch: agent/claude/gate-1319 (worktree ~/Sync/worktrees/instant-gate-1319), released per AGENTS.md and pinned by the
  consuming app

## Why (measured, before any change)

A device's operation gate reported a live-query prune batch holding it 2,236,773 ms, with an outbox release waiting
391,652 ms behind it. The batch took the gate 3 s after the app left the front; the process was then suspended (its
watchdog, on CLOCK_UPTIME_RAW: 1,327.0 + 4.6 + 224.3 + 7.9 s) and the device slept (about 681 s), and the gate times
holds on the wall clock. Its batches cost 1.0-3.5 s each in the background. On a copy of that device's store (46 stored
results, 973 unloaded results of 167 MB, 514,406 facts), with every stored result closed, the prune took 30 holds on a
Mac (Debug), 28 over 250 ms, longest 660 ms: each batch materialized 31,000-57,000 facts for 100-500 entities, because
the whole-entity rule (#259) reads every fact of each entity it might drop, a recording keeps its has-many links on itself
(2,888 attachment links on one), and every entity an earlier batch kept is read again in each later batch.

## Steps

1. This plan and its claims (plan-only commit).
2. Red, with stubs so it compiles: InstantPruneResidencyCostTests (a hub entity of 5,000 unowned facts released by every
   result: facts materialized must not exceed the facts released), AsyncSerialGateSuspensionTests (a hold across a
   recorded suspension reports its running time with the suspension beside it; a suspension alone is no stall; a
   background caller ages only while the process runs; the suspension record, with a million-call stress), and
   InstantPruneMaintenanceActivityTests (a prune whose activity expires stops before its next batch and holds no gate;
   one refused an activity runs no batch). PhonePruneHoldTests measures a device store's copy hold by hold (opt-in).
3. Green: (a) a kept entity is checked again only in a batch that releases another of its facts; (b) the hot store
   answers which released facts it holds and each entity's fact count without materializing them, and materializes only
   entities whose every held fact was released, the only ones the rule can drop; the decisions stay the rule's; (c) the
   gate's waits and holds, its stall threshold and its aging run on CLOCK_UPTIME_RAW minus the suspensions an app's
   watchdog records (InstantProcessSuspensions), and report the suspended time beside them in added fields; (d) the
   prune runs inside an InstantMaintenanceActivity (the system's expiring activity on iOS, watchOS, tvOS and visionOS)
   and stops between batches when it expires.
4. Before and after on the device's store copy; release; ledger.

The write contract stays whole: no write waits for the server; the prune's end state equals one prune's (the existing
prune suites and the new hub test check it).

## Touching

- Sources/InstantSwiftDataCore/AsyncSerialGate.swift (its clock, reports, aging, stall check)
- Sources/InstantSwiftDataCore/InstantRuntime.swift (the prune loop, its batch and chunk functions, configuration)
- Sources/InstantSwiftDataCore/InstantStore.swift and TripleIndexes.swift (a prune residency read)
- Sources/InstantSwiftDataCore/SQLitePersistenceStore.swift (the release decision's inputs, the chunk's decoded facts)
- new Sources/InstantSwiftDataCore/InstantProcessSuspensions.swift, InstantMaintenanceActivity.swift
- Tests: the four files above (new), AsyncSerialGateTests.swift (its recorders become internal)
- docs/releases/, CHANGELOG.md, PROGRESS.md, docs/audits/commit-changelog.md

## Conflict check

No library branch has commits past origin/main (c38c46ea) except old worktrees at 7a5a173a (audio-1262, sqlite-1245);
the last claims on these files are released slices (sync-jam-1270, cellular-1231, fix-memory-1075). The #1315/#1316
agent (watch-list-1315@halfjew22) released 1.9.49 and removed its worktree; its #1316 follow-up is in the app.
