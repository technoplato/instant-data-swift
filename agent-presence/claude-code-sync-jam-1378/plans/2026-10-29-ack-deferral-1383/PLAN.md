# Plan 2026-10-29-ack-deferral-1383: a slow server frame that keeps working keeps its acknowledgement claims

- planId: 2026-10-29-ack-deferral-1383
- agentId: claude-code/sync-jam-1378@halfjew22 (tools/agent-run, claude/halfjew22, opus)
- role: mower (a fix at the cause, in the acknowledgement deferral's stuck-frame bound)
- issues: #1383 (P1, this), #1378 (the jam that grew the queue), #296 (the deferral), #932 (the 120 s frame)
- branch: agent/claude/sync-jam-1378 (worktree ~/Sync/worktrees/sync-jam-1378-instant), released per AGENTS.md

## Why (measured, before any change)

One device's queue held 4,344 pending writes when the app relaunched (21:14:01); for ten minutes after, nothing was
accepted. Every frame the relaunch's query registrations brought back (`add-query-ok`) peeled and replayed the queue,
and 30 of them passed the 120 s acknowledgement deferral (`outbox.mutation.ack-deadline-deferral-exhausted`,
120,695 ms first). Each expiry reclaims the socket's delivery claims, replaces the live session, and the replacement
drops the frame being applied and what was queued behind it (acknowledgements and results), so the rebase never
finishes, nothing is pruned, and the next session starts the same rebase again. The bound exists to treat a stuck frame
as stuck; it was sized from a 22-25 s rebase (#296), and these frames were slow, not stuck.

## Steps

1. This plan and its claims (plan-only commit).
2. Red (`InstantBoundedOutboxDeliveryTests`): a frame held in the receive loop that keeps reporting server-apply
   progress past the 120 s limit keeps its claims and its connection; one that reports none is treated as stuck after the
   limit, as today.
3. Green: the server apply reports progress (each attempt, each staged body page, each commit); the deferral times the
   frame from its last progress instead of from its first sighting, and its warning says so.
4. Release with the release note; the consuming app pins it.

## Touching

- Sources/InstantSwiftDataCore/InstantRuntime.swift: `InstantRuntimeAcknowledgementDeferral`,
  `deferAcknowledgementDeadlinesWhileAFrameIsApplied`, `performApplyServerTransaction` (progress marks only)
- Tests/InstantSwiftDataCoreTests/InstantBoundedOutboxDeliveryTests.swift (one new test pair)
- docs/releases/, CHANGELOG.md, PROGRESS.md, docs/audits/commit-changelog.md

## Conflict check

InstantRuntime.swift: claimed by this agent for #1378 (released 1.9.51); no library branch past origin/main.
InstantBoundedOutboxDeliveryTests.swift: see its agents.txt.
