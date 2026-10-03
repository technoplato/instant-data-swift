# Plan: rooms and presence reach parity with the TypeScript SDK (#461)

- **planId:** `2026-10-03-rooms`
- **agentId:** `claude-opus-5.5-rooms` (issue workLog agentId `claude-code/claude-opus-5.5/rooms`)
- **Role:** grower, on Michael's order and a public issue (#461); compress where the old paths go away.
- **Branch:** `agent/claude-opus-5.5/rooms`, from v1.9.4 (`4da6f182`, the base library-79 named), rebased onto v1.9.5
  (`e7c6ffb3`) at library-79's request on 2026-10-03. Library-79 cuts the release.
- **Goal (Michael, verbatim):**
  - Recording 186 #32-33: "That sounds good to me for the, uh, rooms plan, so go ahead and knock that out with a
    subagent. Um, that you fire off?"
  - Recording 186 #34-35: "Good plan. And let's get feature parody and performance parody with Swift and typescript,
    please."
- **Issue:** https://issues.knophy.com/issues/461 (Scribe side: #462)
- **Evidence:** `/Users/laptop/Sync/audit/instant-rooms-2026-10-03/report.md` (read-only study of v1.9.3 against
  `@instantdb/core` 1.0.65, `Reactor.js` rooms code identical to the library's TS pin `e7101761`).

## Outcome

Room presence behaves and costs like `Reactor.js`: one peer per session, presence publish and receive in memory,
never on the operation gate or in SQLite, room frames applied beside the query applier rather than behind it, an
emission only when what an observer sees changed, topic messages delivered once each without storage, and leave
semantics that match TypeScript. Measured before and after on a local self-hosted server with spans on
(`/Users/laptop/Sync/audit/room-bench-2026-10-03`).

## Steps (no code here)

1. Red tests first, each in a small commit with `withKnownIssue`, so every commit stays green and each fix commit
   must remove its wrapper: two sessions of one user are two peers; a publish returns while the operation gate is
   held and writes no SQLite; a patch-presence applies while an earlier frame is still applying; identical frames
   do not emit again; one holder's leaveRoom keeps the shared state for the others; leavePresence clears the
   presence for peers and for the next join; a publish before joinRoom is not lost; topics are not stored and a
   burst is not lost.
2. Session-keyed peers (`peerID` on members).
3. Presence and topics in memory for live runtimes, off the operation gate; the signed-in user id from memory.
4. Room frames handled by the reader, around the applier (the exact functions go to library-79 first).
5. Emit on change only; a peer's `updatedAt` is when its values last changed.
6. leaveRoom refcount, leavePresence on the wire, publish before join.
7. Topics as events without storage.
8. ADR 0019, CHANGELOG and ledger entries, PROGRESS, #461 work log; hand the branch to library-79 for a release.

## Touching

- `Sources/InstantSwiftDataCore/InstantRoomModels.swift`
- `Sources/InstantSwiftDataCore/InstantRuntime.swift` (room entry points, presence state, frame handlers; not the
  operation gate's take or release sites in transact, server apply, hydration or the outbox, which are library-79's)
- `Sources/InstantSwiftDataCore/InstantRuntimeLiveSession.swift` (room registration and the reader's routing of room
  frames; coordinated with library-79, channel `agent-presence/_channels/2026-10-03-rooms.md`)
- `Sources/InstantSwiftDataCore/InstantRuntimeRoomPresence.swift` and
  `Sources/InstantSwiftDataCore/InstantRuntimeRoomTopics.swift` (new: presence and topics in memory)
- `Sources/InstantSwiftDataCore/InstantSnapshotObservers.swift`
- `Sources/InstantSwiftDataCore/InstantLiveTransport.swift`
- `Sources/InstantSwiftData/InstantPresence.swift`, `Sources/InstantSwiftData/InstantTopic.swift`,
  `Sources/InstantSwiftData/InstantSwiftData.swift`
- `Tests/InstantSwiftDataCoreTests/InstantReactorParityTests.swift`
- `Tests/InstantSwiftDataCoreTests/InstantRoomPresenceRuntimeTests.swift` (new)
- `Tests/InstantSwiftDataTests/InstantRoomPresenceSelectionClientTests.swift` (new)
- `README.md` (the rooms section's rules)
- `docs/adr/0019-rooms-and-presence-parity.md` (new; the number is the next free one, the integrator may move it)
- `CHANGELOG.md`, `PROGRESS.md`, `docs/audits/commit-changelog.md` (prepend only)

## Conflict check

- `InstantRuntime.swift` and `InstantRuntimeLiveSession.swift` are also claimed by library-79
  (`2026-10-02-library-79-hops`), which is fixing the operation gate's P1 (a transact held it 12 s behind a deferred
  query emission's hydration) and the reader/applier buffer after a socket reset. Split agreed on 2026-10-03: the
  room entry points leave the gate entirely; room frames route around the applier; library-79 owns the gate and the
  buffer. Function names and line ranges go to library-79 before any edit to the reader or the applier.
