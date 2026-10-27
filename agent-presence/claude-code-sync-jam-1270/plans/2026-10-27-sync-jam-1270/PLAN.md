# Plan 2026-10-27-sync-jam-1270: a server apply finds a link's pending writers under the link's written name

- planId: 2026-10-27-sync-jam-1270
- agentId: claude-code/sync-jam-1270@al (tools/agent-run, claude/al, opus)
- role: mower (a fix at the cause, in the reduction's slot lookup); the outbox coalescing the brief also names is an
  amendment here first, only if the measurements after this fix still show the queue growing
- issues: #1270 (P0, this), #296 (the reduction), #932 (its gate-held line), #1244 (FOOTGUNS.md)
- branch: agent/claude/sync-jam-1270 (worktree ~/Sync/worktrees/sync-jam-1270-instant), released per AGENTS.md and
  pinned by the consuming app; no app build is cut or installed

## Why (measured, before any change)

One device's outbox grew from 0-1 to 2,316 pending writes in two hours while it recorded. Its library's own gate-held
lines, 16:47-19:00: 49 of 51 say `full rebase: changesShadowedFact`, peeling and replaying 1,073-2,093 pending writes for
one server frame and holding the operation gate 700-5,347 ms; 2-14 writes accepted a minute against about 45 written.

A copy of that device's store (1,241 pending, 690 refused) shows why the reduction declines: 123 pending writes set the
recording's `previewImage` link under its written name `recordings/previewImage`, and the outbox keeps their write keys
under that name, while the store and every server frame hold the slot under the attribute's id (a server-issued id, kept
as the physical relation id). `loadServerApplyReductionContext` looks for the slot's surviving writers by the frame's
attribute id, finds none, and the store does not show the server's value (it shows the newest pending link), so the
frame declines with `changesShadowedFact` and the whole component (nearly every pending write links to the recording)
is peeled and replayed. The replay puts the pending value back, so the next frame declines the same way: every frame
that restates the recording costs the whole queue while any such write is pending. Scalar slots (`updatedAtMs` and the
summary counts) carry the same name in the write and the frame and take the reduced path.

## Steps

1. This plan and its claims (plan-only commit).
2. Red: `InstantFastDrainTests` gains the device's attachment write (a forward link whose attribute id is not its
   written name, and the reverse link to the recording); a frame restating the recording while such writes are pending
   must not peel or replay them. Measured in the measurement pass at 100, 1,000 and 2,000 pending writes (apply ms,
   bodies replayed per frame, decline reasons) and for a drain with no new writes (frames, rebases, apply ms). The
   phone-replay gate's model server resolves a forward link's written name to the attribute, as Instant's server
   does, so a replay of the device's copy shows the same declines.
3. Green: the reduction looks a slot's writers up under every name a write can give it (the attribute's id and its
   forward identity) and reads a writer's value under either; the differential against the whole-component rebase runs
   with the attachment shape. Before and after: the step-2 measurements and the phone-replay gate on the device's copy.
4. If the queue still cannot shrink at the device's write rate after step 3: an amendment here for the outbox
   coalescing (a pending, never-offered write whose every assignment a later pending write replaces) with its red test
   first, and for a refused write never holding other writes.
5. FOOTGUNS.md entry (the queue-length spiral); release; ledger.

The write contract stays whole: a save waits for the local store and the durable outbox only; offline writes succeed
and replay in order; the reduced apply leaves what the whole-component rebase leaves (the differential checks it).

## Touching

- Sources/InstantSwiftDataCore/InstantRuntime.swift: `reducedServerApplyOperations` (both), `insertedValue`,
  `deletedEntityReceiptPatch`
- Sources/InstantSwiftDataCore/SQLitePersistenceStore.swift: `loadServerApplyReductionContext` (its `writer` lookup)
- Sources/InstantSwiftDataCore/TripleIndexes.swift: `AttributeStore` (a lookup of the names a forward write may use)
- Tests/InstantSwiftDataCoreTests/InstantFastDrainTests.swift, Tests/InstantSwiftDataCoreTests/PhoneReplayGateTests.swift
- docs/FOOTGUNS.md (one new entry and its index row; toolbox-1244's entries untouched), docs/releases/ (the release),
  docs/audits/2026-10-27-sync-jam-1270.md (new), CHANGELOG.md, PROGRESS.md, docs/audits/commit-changelog.md

## Conflict check

InstantRuntime.swift and SQLitePersistenceStore.swift: the last claims (sqlite-1245, cellular-1231, b301-disk,
fix-memory-1075) are released slices; no library branch has commits past origin/main since v1.9.47 (13:40). The
fast-drain tests: server-apply-932's claim is released. FOOTGUNS.md: toolbox-1244 landed the page at 12:20; this plan
appends one entry (channel `agent-presence/_channels/2026-10-27-sync-jam-1270.md`).
