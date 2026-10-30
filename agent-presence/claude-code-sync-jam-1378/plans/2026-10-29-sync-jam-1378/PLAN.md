# Plan 2026-10-29-sync-jam-1378: a server fact on a slot no pending write sets and the store leaves empty is kept

- planId: 2026-10-29-sync-jam-1378
- agentId: claude-code/sync-jam-1378@halfjew22 (tools/agent-run, claude/halfjew22, opus)
- role: mower (a fix at the cause, in the reduction's no-writer branch)
- issues: #1378 (P0, this), #1270 (the same spiral, another trigger), #296 (the reduction), #431 (why the branch
  declines)
- branch: agent/claude/sync-jam-1378 (worktree ~/Sync/worktrees/sync-jam-1378-instant), released per AGENTS.md and
  pinned by the consuming app

## Why (measured, before any change)

One device's outbox grew from 29 to 524 pending writes in eight minutes after a relaunch during a live recording, with
about 50 writes a minute accepted against about 100 written. Every gate-held line of that time says `full rebase:
changesShadowedFact on transcriptionSegments/retiredAtMs`, peeling and replaying 139 to 395 pending writes for one
frame (304 to 1,964 ms), and two frames fell back to the exclusive apply after five optimistic attempts.

The frames come from the recording list's two has-one preview includes, which select an optional field
(`retiredAtMs`) that the app never writes. The server answers each preview segment with that field as `null`; a copy of
another device's store holds exactly those facts, on the two newest segments of each recording. While a recording is
live, every new line becomes a preview segment, and while the outbox still holds that segment's writes the entity is
shadowed. The field has no pending writer and the store holds nothing in it, so `reducedServerApplyOperations` takes
the no-writer branch and declines: it keeps a server fact only when the store already shows it. Its comment says the
full rebase runs once and the next frame's restatement holds; here each frame names a new segment, so each one
declines and costs the whole queue. With a short queue the segment is acknowledged before its frame arrives; past a
few hundred pending writes the drain falls below the write rate and does not recover.

## Steps

1. This plan and its claims (plan-only commit).
2. Red: `InstantFastDrainTests` gains the preview's unset field (an optional attribute no write names, restated as
   `null` on the preview segment, as the server does). A frame restating a preview segment whose writes are pending
   must not peel or replay them; measured at 100, 1,000 and 2,000 pending writes. Guards that must still rebase: a
   pending write that deletes the entity, and one that retracts the slot (the full rebase's replay would remove the
   server's fact there).
3. Green: the loader proves, for each such slot (no surviving writer, nothing in the store), that no surviving write on
   the entity deletes it or retracts the slot, from those writes' bodies (bounded; past the bound, the full rebase runs
   as today), and only where no delete can cascade into the entity's namespace. The reduction then keeps the server's
   fact, and when the entity's first pending write created it, patches that write's receipt with the fact, as the full
   rebase's replay would. A resident value in the slot still declines (#431). The differential against the
   whole-component rebase runs with the preview's unset field.
4. FOOTGUNS.md F65 gains this trigger; release; ledger.

The write contract stays whole: a save waits for the local store and the durable outbox only; offline writes succeed
and replay in order; the reduced apply leaves what the whole-component rebase leaves (the differential checks it).

## Touching

- Sources/InstantSwiftDataCore/InstantRuntime.swift: `reducedServerApplyOperations` (both)
- Sources/InstantSwiftDataCore/SQLitePersistenceStore.swift: `loadServerApplyReductionContext`,
  `InstantServerApplyReductionContext`
- Tests/InstantSwiftDataCoreTests/InstantFastDrainTests.swift
- docs/FOOTGUNS.md (F65 only), docs/releases/ (the release), CHANGELOG.md, PROGRESS.md, docs/audits/commit-changelog.md

## Conflict check

InstantRuntime.swift, SQLitePersistenceStore.swift and InstantFastDrainTests.swift: the last claims (sync-jam-1270,
gate-1319) are released slices; no library branch has commits past origin/main; the other library worktrees
(audio-1262, sqlite-1245) are clean at v1.9.47.
