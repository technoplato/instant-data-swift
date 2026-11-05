# Plan 2026-11-04-retired-cascade-1756: a restated unset field reduces on Scribe's schema too

- planId: 2026-11-04-retired-cascade-1756
- agentId: claude-code/b1104-1756@halfjew22 (tools/agent-run, claude/halfjew22, opus)
- role: mower (the same store as the full rebase leaves, without peeling and replaying the queue; no new public surface)
- issue: #1756 (on the iPad a long recording would not load until Scribe was force-closed; build 245, library 1.9.64)
- branch: agent/claude/retired-cascade-1756, worktree ~/Sync/worktrees/instant-retired-cascade-1756 cut from
  origin/main 98c1a576 (#1748's agent holds uncommitted work and queued jobs in the main checkout; his 2026-10-23
  words allow a worktree while several agents work: "But if we need multiple work trees, you know, whatever."); every
  green lands on main, rebased first

## Why (measured)

Recording 364 ran 7.4 h on the iPad (2026-11-04 01:13-08:50) and left 12,000 writes in its outbox. The Mac's
diagnostics collector holds 80 server applies over 1 s from that iPad that took the full rebase
`changesShadowedFact on transcriptionSegments/retiredAtMs`, each peeling and replaying about 7,600 writes
(plannedComponentBodyCount 7,590). With #1748's whole-store walk per replayed write, 37 of 38 CPU samples of
`Scribe Shared.cpu_resource-2026-11-04-103957.ips` (symbolicated with build 245's dSYM) sit in `applyLiveRefresh` ->
`performApplyServerTransaction`. The receive loop fell behind: Recording 365's detail pages answered in 5-minute
bursts (18 minutes to show its transcript), every `$files` lookup timed out (1,085 in 93 minutes), the outbox took
about 160 writes in 93 minutes, and a force-close did not clear it. Evidence: ~/Sync/audit/ipad-load-1756/.

The trigger is #1378's: the recording list's preview selects `retiredAtMs`, which no device writes, and the server
restates it as null on each new preview segment while that segment's writes are pending. #1378 (1.9.52) lets such a
frame reduce through `unwrittenEmptySlots`, but `emptyServerApplySlots` leaves out every namespace a delete can
cascade into, and Scribe's `recordings/segments` and `recordings/transcriptions` cascade into `transcriptionSegments`.
`InstantFastDrainTests` says so ("Without Scribe's links: their cascade ... keeps the reduction from proving a
segment's empty slot, so those frames take the full rebase there, as before"). On Scribe's real schema every such
frame still peels and replays the whole queue, and while a backlog drains nearly every accepted batch makes one.

## Steps

1. This plan and its claims (plan-only commit) on main.
2. Red (InstantFastDrainTests): the preview's unset field with Scribe's links rebases nothing and leaves what the
   whole-component rebase leaves (fails today: the frames decline `changesShadowedFact`); the measured frames against
   100, 1,000 and 2,000 pending writes plan no bodies with Scribe's links.
3. Green: the cascade rule becomes exact. A slot in a namespace a delete can cascade into qualifies as unwritten and
   empty when, beyond #1378's rules, no surviving write on the entity deletes an entity whose delete can cascade into
   it: an entity in a namespace that cascades into the slot's namespace, followed transitively through the schema's
   cascading links, or any entity deleted without a namespace. A write whose replay cascades into the entity already
   names it in its effect footprint (its rollback restores the entity), so the writes the context loads for the
   entity are the ones to read. Safety nets: the differential seeds with Scribe's links and the preview's unset field
   observe what the full rebase observes; a pending delete of the line's transcription or recording still declines
   and leaves what the full rebase leaves.
4. The focused suites (InstantFastDrainTests, the server-apply reduction and rebase suites) on the Mac mini through
   build.sh, then the whole InstantSwiftDataCoreTests bundle.
5. Release v1.9.67 (v1.9.65 is #1648's, v1.9.66 #1748's): docs/releases, CHANGELOG, PROGRESS, ledger, tag. Bump
   Scribe's exact pin on realtime-voice main, cut a build and install it, the iPhone first, then the iPad. Measure on
   the iPad: full rebases per minute and the outbox's drain (session.health) before and after.

## Touching

- `Sources/InstantSwiftDataCore/InstantRuntime.swift` (`emptyServerApplySlots` and the reduction context request it
  feeds; not the transact paths #1648 claims, not the gate timeline)
- `Sources/InstantSwiftDataCore/SQLitePersistenceStore.swift` (`loadServerApplyReductionContext`'s unwritten-empty-slot
  rule and the request type it reads; not the outbox body storage #1510 claims)
- `Tests/InstantSwiftDataCoreTests/InstantFastDrainTests.swift` (new tests; the fixture's options)
- `CHANGELOG.md`, `PROGRESS.md`, `docs/releases/v1.9.67.md`, `docs/audits/commit-changelog.md` (release and ledger)

## Conflict check

- #1748 (2026-11-04-newest-1748): TripleIndexes.swift and InstantStoreWriteScalingTests.swift; it does not touch
  InstantRuntime.swift. Both fixes cut the same jam: #1748 the cost of each replayed write, this one the replays.
- #1648 (order-1648): InstantTypedAPI.swift and InstantRuntime.swift's transact paths; this plan touches the server
  apply reduction only.
- #1510 (perf-writes-1510): SQLitePersistenceStore.swift's outbox body storage; this plan touches the reduction
  context's slot rule only. Channel: agent-presence/_channels/2026-11-04-retired-cascade-1756.md.

## Outcome (2026-11-04 19:15 EST)

Landed: merge `be720d8e` (red `831ee0bf`, green `dbc7d5d0`, guard `29a2837a`), released as v1.9.67 (`49780127`; checks
after the tag `9f31906d`: the bundle on the Mac mini, 3 failures none in this change). Scribe pinned it (`ba22b2e2c`)
and cut build 250 (`2e7aa7110`), installed 18:36-18:37 on the iPhone and the iPad (locked, so not launched) and the Mac.
Open: the iPad's full rebases and drain on 250, read the next time Scribe runs there (#1756).
