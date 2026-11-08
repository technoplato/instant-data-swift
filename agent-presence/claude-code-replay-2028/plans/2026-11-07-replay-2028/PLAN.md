# Plan 2026-11-07-replay-2028: an accepted write stays the evidence that an older write of its slots is moot

- planId: 2026-11-07-replay-2028
- agentId: claude-code/replay-2028@ld (tools/agent-run, claude/ld, opus)
- role: mower (a fix at the cause, in the watermark prune; no new API, no storage change)
- issues: #2028 (P0, this), library-78 item 3 (supersession by later accepted writes), #441 (held by the server's
  results), #296 and #376 (why a write is offered again after its first offer may have been applied)
- branch: agent/claude/replay-2028 (worktree ~/Sync/worktrees/replay-2028-ids), released per AGENTS.md
- written after the red and green steps: a P0 found on a device in use, fixed test first; the claims below name every
  path those steps touched

## Why (measured, before any change)

A consuming app's device, one build, 2026-11-07 17:47-19:24, on a cellular network that dropped every few minutes:
15 writes were refused for good as replays (`Permission denied: not perms-pass?`), and the app reported data as
refused. Each was older than a newer write of the same row that the server already held: an admin read of the server's
rows shows every refused write's row at a newer `updatedAtMs` (a route chunk refused at 52, 62 and 72 samples is held at
128 samples, sealed). The app's rules refuse a write that moves `updatedAtMs` back. Item 3 resolves such a refusal as
accepted when later accepted writes of this device cover every slot the refused write sets, but it reads those writes
from the outbox, and the server apply's watermark prune had already deleted them. In the same minute (19:24:49-52) four
other replay refusals resolved as superseded because their covering writes were still in the outbox.

## Steps

1. Red (`InstantCoveringWriteRetentionTests`, the scripted transport): a re-send refusal covered by a later write the
   watermark passed resolves as accepted; such a re-send is resolved without an offer on the next connection; a later
   write that covers it only in part does not make the refusal moot (guard).
2. Green: the watermark keeps an accepted write while an older write that sets one of its slots is open (neither failed
   nor proven); one guard in both prune predicates, so the reduction and the plan agree.
3. Measure: `InstantFlappingNetworkRefusalTests`, a scripted server with the forward-only rule and a row it always
   refuses, drops and timeouts with and without the write applied; false and true refusals before and after.
4. Release v1.9.81 (docs/releases, tag), CHANGELOG, PROGRESS, commit ledger; the consuming app pins it.

## Touching

- Sources/InstantSwiftDataCore/SQLitePersistenceStore.swift: `serverApplyReductionPrunablePredicate`,
  `serverApplyWatermarkPredicate`, the new `keepsEvidenceForAnOlderOpenWrite`
- Tests/InstantSwiftDataCoreTests/InstantCoveringWriteRetentionTests.swift (new)
- Tests/InstantSwiftDataCoreTests/InstantFlappingNetworkRefusalTests.swift (new)
- docs/releases/, CHANGELOG.md, PROGRESS.md, docs/audits/commit-changelog.md

## Conflict check

The last claims on the store file are the 11-04 perf lanes (landed) and #1942 (1.9.80, claim expiry; no overlap with the
prune). No library source change on main since v1.9.80. The branches past origin/main that touch the store file are
scratch and perf branches last committed 2026-11-05.
