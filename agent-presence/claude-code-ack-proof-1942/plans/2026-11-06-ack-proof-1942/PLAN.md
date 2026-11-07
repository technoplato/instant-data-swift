# Plan 2026-11-06-ack-proof-1942: prove 1.9.80's late keep, and the quiet session's replacement, on both releases

- planId: 2026-11-06-ack-proof-1942
- agentId: claude-code/ack-proof-1942@pp (tools/agent-run, claude/pp, opus)
- role: mower (tests only: no source change, no release, no Scribe pin)
- issues: #1942 (P1, this), #1916 (the Mac's long recordings), #296 (the frame deferral that kept build 294's late write)
- branch: agent/claude/ack-proof-1942 (worktree ~/Sync/worktrees/ack-proof-1942)

## Why (measured)

The after-measurement on the Mac (build 294, instant-data-swift 1.9.80, 2026-11-06 21:54-21:59) had one write past its
6 s deadline, and #296's frame deferral kept it (`outbox.mutation.ack-deadline-deferred`: a frame was being applied at
that instant); 1.9.80's keep (`outbox.mutation.ack-late-kept`) ran 0 times. 1.9.80's red tests (7a8f53c5) use a test
hook that v1.9.79 lacks, so they ran on 1.9.79's code plus that hook, and none of them shows which path kept the session.

## Steps

1. This plan and its claim (plan-only commit).
2. One new test file, built only on API v1.9.79 also has, with a controlled clock, held deadline and reconnect sleeps
   and scripted sessions. A: a write passes its deadline with no frame being applied while the session took a frame 3 s
   before it: kept by `ack-late-kept` and answered on the same connection. B: the same history without that frame: the
   session is replaced and the write answered on the next one.
3. The same file on the Mac mini against v1.9.79 (ae2c6b99's tree plus the file) and v1.9.80 (main plus the file): A
   must fail on 1.9.79 and pass on 1.9.80; B is expected to pass on both (1.9.79 already replaced a quiet session).
4. Land the test on main, then CHANGELOG and the commit ledger. No source change, so no tag and no Scribe pin.

## Touching

- Tests/InstantSwiftDataCoreTests/InstantLateAcknowledgementTests.swift (new)
- CHANGELOG.md and docs/audits/commit-changelog.md (ledger entries only)

## Conflict check

No claim on the new file's path. InstantBoundedOutboxDeliveryTests.swift (1.9.80's tests) and every source file are left
as they are. No other agent has a library branch past origin/main on these paths.
