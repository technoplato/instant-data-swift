# Plan: build 73's library keeps up live and drains a Recording 023-sized backlog in minutes (#296)

- planId: 2026-09-30-fast-drain-2
- agentId: claude-opus-5.5-fast-drain
- role: mower (removes repeated peel-and-replay work from server apply; no new public surface)
- Issue: #296 (Recording 023), open item 2
- Branch: agent/claude-opus-5.5/fast-drain-2 from agent/claude-opus-5.5/fast-drain-revert (0078484f, build 72)

Evidence:
- The build-72 library (0078484f) does not drain a 2,580-write backlog on an iPhone simulator against bd40c50a:
  53 accepts in 10 minutes, one core pegged, 25 connections, 37 replay refusals.
- Every frame rebases the whole component of about 1,780 rows in 26-37 s. The socket closes during the frame
  (the server pings every 5 s and closes a client that stops reading for 45 s; 20 s survives).
- 8bee78eb's reduction drained 2,502 writes in the macOS harness, but it fell behind a live recording: nearly every
  pending row was rewritten on live frames.

Steps (no code here):

1. An instrumented, uncommitted bb88af72 live soak names each frame's decline reason and planned body count.
2. Reapply 8bee78eb, then fix it test-first:
   - F1: drop the redundant earlier-overlays cap, which declines every frame after a Stop.
   - F2: probe reverse-form writers for Scribe's forward link slots.
   - The live mechanism found in step 1.
   - The differential test runs in both link shapes (fake schema, and Scribe's forward links with a Stop).
3. Connection survival (the close threshold, the duplicate reconnect, reading while a frame applies) runs in
   parallel on agent/claude-opus-5.5/connection-survival (agent claude-opus-5.5-connection-survival). It is merged
   here before the gates. See the channel 2026-09-30-build-73-runtime.
4. Gates: the live soak (pending near 0, CPU about 30%); the Recording 023-shape backlog (drains to 0 in minutes,
   0-1 reconnects, CPU not pegged); the ten suites plus the differential test.
5. Record the refused-replay data (32 failed rows, all already superseded on the server) as an open item for N47.

Touching:

- Sources/InstantSwiftDataCore/InstantRuntime.swift (server apply: performApplyServerTransaction and the reduction only)
- Sources/InstantSwiftDataCore/SQLitePersistenceStore.swift (server-apply plan and reduction queries)
- Tests/InstantSwiftDataCoreTests/InstantFastDrainTests.swift
- Tests/InstantSwiftDataCoreTests/InstantBoundedServerApplyRebaseTests.swift (pin its runtime to the whole-component
  rebase it measures; added 2026-09-30 after the corrected reduction stopped declining its frames)
- docs/audits/recording-023-refused-replays/ (new: the open item's data)
- CHANGELOG.md, docs/audits/commit-changelog.md

Conflict check: claude-opus-5.5-connection-survival also claims InstantRuntime.swift, for the connection and
receive-loop region only. The split is recorded in agent-presence/_channels/2026-09-30-build-73-runtime.md.
