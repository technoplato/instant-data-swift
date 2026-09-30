# Plan: build 73's live connection survives long server frames and reconnects once (#296)

- planId: 2026-09-30-connection-survival
- agentId: claude-opus-5.5-connection-survival
- role: mower (fixes two defects in existing connection code; no new public surface)
- Issue: #296 (Recording 023)
- Branch: agent/claude-opus-5.5/connection-survival from 0078484f (build 72's library). The parent,
  claude-opus-5.5-fast-drain, merges it into agent/claude-opus-5.5/fast-drain-2 before build 73's gates.

Evidence:
- Build 72 on an iPhone simulator against bd40c50a (2,580 pending writes, 10 minutes): 25 connections, 15
  receive-loop failures, 53 accepts. Each connection's first query result applies for 26-37 s. After it, the socket
  is already closed (POSIX 57 on the next send and receive).
- Every socket death opened more than one replacement: `connection.open-started` from the pump (isReconnect=false)
  and from the reconnect controller (isReconnect=true) within 1 ms, then a third `open-started`.
- The server closes a client that sends nothing (no text, binary, or pong frame) for more than 15 s, checked every
  5 s (upstream `server/src/instant/lib/ring/websocket.clj`, `straight-jacket-run-ping-job`, pinned e7101761).
- A local 127.0.0.1 experiment with the library's URLSession configuration: with no `receive()` outstanding, 30
  server pings got 0 pongs in 30 s; with a `receive()` pending, all 30 got pongs within about 10 ms.

Steps (no code here):

1. Prove the cause with the library's own URLSession transport. Add a credentialed live test (bd40c50a only, opt-in
   variable, skips cleanly without it): withhold `receive()` for 10 s (alive) and 28 s (closed), and hold 28 s with
   a `receive()` pending (alive).
2. Duplicate reconnect, test-first with a fake transport. A receive-loop failure plus a pump pass must open exactly
   one replacement. The pump must not start a connection or cancel the controller while a reconnect is scheduled. A
   scheduled reconnect must reuse a session that opened after its failure. Cite `Reactor.js` `_scheduleReconnect`,
   `_transportOnClose`, `_trySend`, and `_startSocket`.
3. Keep reading while a frame applies, test-first with a fake transport that observes `receive()` during a long
   apply. The receiver becomes a reader that keeps one `receive()` outstanding, plus the one sequential applier.
   Frames stay in arrival order. The buffer is bounded, with backpressure when full. Generation checks, close and
   replace semantics, in-flight and claim-token bookkeeping, `frameBeingApplied()`, and the 120 s deferral cap stay.
   A frame buffered for an old generation is never applied. Cite `Reactor.js` `_handleReceive`.
4. Validate: build, the new tests, and the ten suites against the 0078484f baseline, with load averages. Delete
   this worktree's `.build` at the end.

Touching:

- Sources/InstantSwiftDataCore/InstantRuntimeLiveSession.swift (receiver: reader, applier, receive buffer)
- Sources/InstantSwiftDataCore/InstantRuntime.swift (connection region only: `ensureLiveConnectionIfNeeded`,
  `scheduleReconnect`, the reconnect controller)
- Tests/InstantSwiftDataCoreTests/InstantLiveConnectionSurvivalTests.swift (new, deterministic)
- Tests/InstantSwiftDataCoreTests/InstantURLSessionKeepaliveLiveTests.swift (new, credentialed, opt-in)
- CHANGELOG.md, docs/audits/commit-changelog.md

Conflict check: claude-opus-5.5-fast-drain also claims InstantRuntime.swift, for server apply only
(`performApplyServerTransaction`, the server-apply reduction and plan, `performTransact`'s stamp guard) and
SQLitePersistenceStore.swift's server-apply code. This plan edits none of those. The split is recorded in
agent-presence/_channels/2026-09-30-build-73-runtime.md, copied unchanged from the parent's branch.
