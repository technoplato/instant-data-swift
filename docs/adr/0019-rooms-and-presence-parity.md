# ADR 0019: Rooms and Presence Match Reactor.js: One Peer per Session, in Memory, Beside the Query Applier

- Status: Accepted (Michael's go-ahead through main, 2026-10-03); red then green on 2026-10-04 (see Evidence). The
  measurement before and after on a local self-hosted server (`/Users/laptop/Sync/audit/room-bench-2026-10-03`) is
  queued in the low lane and does not hold up the release (main, 2026-10-04).
- Date: 2026-10-03
- Issue: #461 (Scribe side: #462)
- Scope: `InstantRuntime`'s room entry points (`joinRoom`, `leaveRoom`, `setPresence`, `leavePresence`,
  `roomPresence`, `observeRoomPresence`, `publishTopicMessage`, `roomTopicMessages`, `observeRoomTopicMessages`, new
  `observeRoomTopicEvents`), the live session's room registration and its receive loop, `InstantRoomPresenceMember`,
  `InstantRoomTopicMessage`, and the typed `@Presence` wrapper

## Context

Michael, verbatim:
- Recording 185 #330-332: "And let's explore the, um, The abstraction of instant DB rooms and make sure the instant DB
  rooms abstraction is. matches the performance of tightscript."
- Recording 186 #32-33: "That sounds good to me for the, uh, rooms plan, so go ahead and knock that out with a
  subagent. Um, that you fire off?"
- Recording 186 #34-35: "Good plan. And let's get feature parody and performance parody with Swift and typescript,
  please."

The study (`/Users/laptop/Sync/audit/instant-rooms-2026-10-03/report.md`, v1.9.3 against `@instantdb/core` 1.0.65;
the rooms code in `Reactor.js` is identical to the library's pin `e7101761`) found:
1. Members were keyed `appID:room:userID`, so every session of one user (agents, devices) merged into one member,
   and a session of this device's own user replaced this device's entry. `Reactor.js` keys peers by session id.
2. `setPresence` held the operation gate across an auth-session read, a SQLite write and read, the observer publish
   and the awaited socket send; every incoming presence frame read SQLite on the persistence actor commits use.
   `Reactor.js` publishes with one synchronous send and stores nothing.
3. Room frames went through the one query applier, so a `patch-presence` waited behind each `refresh-ok` apply
   (about 300 ms on the phone while dictating).
4. Every frame emitted to every observer; the typed wrapper then reassigned `@Published`.
5. Topic messages a live runtime published were stored forever, every message re-read all of them, and an observer
   saw only the newest received message.
6. `leaveRoom` wiped the room's presence while another holder remained; `leavePresence` sent nothing and a rejoin
   re-announced it; a presence set before `joinRoom` was dropped.

## Decisions

1. **A peer is its session.** `InstantRoomPresenceMember` gains `peerID` (the server's session id; `nil` for this
   runtime's own presence) and `isLocal`; a peer's `id` is its session. Lists keep their order: by user id, this
   runtime's presence first, then peers by session. (`Reactor.js` `_setPresencePeers`; presence.ts
   `buildPresenceSlice` sets `peerId` to the session key.)
2. **A live runtime's presence lives in memory, off the operation gate.** One actor, `InstantRuntimeRoomPresence`,
   holds each room's peers (the server's sessions map, patched in place), this runtime's own presence, and the room's
   observers; a publish or a frame is one turn there. The signed-in user id comes from memory
   (`InstantRoomAuthUserIDCache`, set wherever the auth session changes). A per-room publication sequence keeps the
   newer of two racing publishes on the wire. Runtimes without a live transport (the CLI's local cache) keep their
   SQLite presence, so a later launch lists it.
3. **Room frames apply beside the query applier.** The receiver's reader hands join and leave answers, presence and
   broadcasts to a third task in the same generation's group, which applies them in arrival order; the reader still
   awaits nothing but `receive()`, so pings stay answered (#296). The room stream finishes beside `frames.close()`.
   (`Reactor.js` handles each frame in `_handleReceive` as it arrives.) Agreed with library-79, whose #474 change
   builds on it.
4. **An emission only when what an observer sees changed.** Each observer keeps what it last received; a peer's
   `updatedAt` moves only when its values change. (`hasPresenceResponseChanged`, presence.ts.)
5. **Leaving matches Reactor.js.** Only the last holder's `leaveRoom` forgets the room (`_cleanupRoom`).
   `leavePresence` makes the session carry this device's newest remaining publication, or `{}` (what a session that
   joined without presence holds on the server, `JoinRoomMergeV3`), so peers stop seeing it and a rejoin carries
   nothing. A presence set before `joinRoom` goes out with `join-room` and again on `join-room-ok` (`_tryJoinRoom`,
   `_flushEnqueuedRoomData`).
6. **Topics are not stored.** `InstantRuntimeRoomTopics` records each message once: `observeRoomTopicEvents` delivers
   every later message exactly once and in order (`_notifyBroadcastSubs`), `observeRoomTopicMessages` emits the
   topic's most recent 128, `roomTopicMessages` lists this runtime's own recent publications, and messages carry the
   sender's `peerID`. A final leave forgets the room's messages.
7. **An observation can select its part.** `observeRoomPresence(room:selection:)` (runtime and client) takes
   `InstantRoomPresenceSelection` (keys, peer ids, own presence), as `subscribePresence`'s `keys`, `peers` and `user`
   options; each observer keeps what it last received and wakes only when its part changed.
8. **Whether a join is confirmed.** `isRoomJoined(_:)` (runtime and client) is true from `join-room-ok` on the current
   connection, as `Reactor.js` reports `isLoading: !room.isConnected`; until then an empty presence says nothing.
9. **Room writes keep their order** (added 2026-10-04, in 1.9.8). Off the operation gate, two room writes that overlap
   could reach the socket in either order, because `send(_:through:)` writes each message from its own task:
   library-79's 1.9.8 dev run caught an older `set-presence` landing after a newer one
   (`racingPresencePublishesLeaveTheNewestOnTheWire`, 1 of 3 runs), and two topic publishes could invert the same way
   (v1.9.5 had held the operation gate across each publish). Each room now has one lane in the live session: a
   presence or broadcast write takes it in the actor turn that records the publication and holds it until its write
   returns, and the writes waiting for it go first in, first out, as `Reactor.js` writes with a synchronous `ws.send`
   in call order. The `join-room-ok` flush takes the lane in the turn that marks the room joined and holds it across
   the room's newest presence and the broadcasts queued before the join. Adapted: a presence write queued behind that
   flush whose publication is no newer than what the flush wrote is skipped, so the wire never goes back to an older
   presence; `Reactor.js` has no such queue (its writes are synchronous), so it never needs the rule. Broadcasts are
   never skipped: one that waited for a socket that closed goes back among the queued broadcasts in publication order,
   and only a broadcast whose room was left is dropped, as `Reactor.js`'s `publishTopic` returns for a room it no longer
   has. Open: `join-room` and `leave-room` still go outside the lane (#563, planned for 1.9.9), and after a rejoin with
   queued broadcasts the room-frame task waits for the flush. Library-79 implemented it on the 1.9.8 branch: red tests
   `410b28ca` and `0998556f`, the lane `8dc4321d` and `1b4dcf0a`; the rooms agent reviewed both.

## Parity with Reactor.js after this ADR (the study's section 1)

| Row | Now |
|---|---|
| Join | Parity: a presence set before the join goes in `join-room`, and again on `join-room-ok`. |
| Refcount, leave on last | Parity, with Swift's explicit refcount; only the last holder's leave forgets the room. |
| Leave while join pending | Swift sends `leave-room` at once; `Reactor.js` waits for `join-room-ok`. Same result (the server keeps order). |
| Publish presence | Swift replaces the values (`setPresence`); `Reactor.js` merges partial data. Kept: Swift's typed values are whole objects. Writes keep call order (decision 9). |
| Presence before join | Parity (decision 5). |
| Subscribe joins implicitly | Not adopted: Swift joins explicitly (`joinRoom`), as before. |
| Peer identity | Parity (decision 1). |
| Self vs peers | Adapted: one list with `isLocal`, instead of `user` and `peers` slots. |
| Selection (`keys`, `peers`, `user`) | Parity: `observeRoomPresence(room:selection:)` on the runtime and the client; each observer wakes only when its part changed. |
| Change detection | Parity per room (decision 4). |
| Loading and error | Loading: `isRoomJoined(_:)` on the runtime and the client, true from `join-room-ok` on the current connection (`isLoading: !room.isConnected`); it is a read, not an observation. **Open:** a room error state (the server no longer sends `join-room-error`), and the typed `InstantRoom.isJoined`, which still turns true when the join is sent. |
| patch-presence / refresh-presence in | Parity in cost shape: one actor turn, no SQLite. |
| Reconnect, socket close | Parity, as before. |
| Leave presence | Adapted (decision 5); `Reactor.js` has none. |
| Topic publish, delivery | Parity (decisions 6 and 9): in publication order, once each; the sender's presence is reachable through `peerID`. |
| Own broadcasts | Adapted: delivered locally with `peerID` nil; the server never echoes them. |
| Version advert | Unchanged: `v0.22.75`, so no batched `server-broadcast`s. |
| Server-side presence read | Not in a client SDK (admin `rooms.getPresence`). |

## Consequences

- Presence and topics of a live runtime vanish with the process, as in TypeScript. The CLI's local-cache mode keeps
  its durable presence and topics.
- Apps that filtered their own presence by user id now also see their other sessions as peers, which is what
  `Reactor.js` shows. The typed `@Presence` wrapper leaves out only its own publication.
- `observeRoomTopicMessages` emits the most recent 128 messages, not the stored list plus the newest; use
  `observeRoomTopicEvents` to see every message once.

## Evidence

- Red tests first, each in `withKnownIssue` until its fix removed it: `runtimeKeepsEverySessionOfOneUserAsItsOwnPeer`
  (InstantReactorParityTests) and `InstantRoomPresenceRuntimeTests` (the gate, SQLite, the applier, emissions,
  leaving, presence before join, topics), plus the 10,000-message topic run.
- The red-then-green run, 2026-10-04 01:19-02:12 in the heavy.sh normal lane (records:
  `/Users/laptop/Sync/audit/room-bench-2026-10-03/gate/`):
  - Red, on `186d2f74` (v1.9.5 plus the red tests): all 9 red tests recorded their known issues (13 in all), so each
    fails on v1.9.5 as intended; the three existing room tests passed.
  - Green, on `681a0ba9`: the room suites 51 of 51 (one known issue,
    `anAttributeARefreshAddsIsUsedByTheNextAttrLessFrame`, which v1.9.5 has too); the CLI, recipe, wrapper and
    playback-room tests 67 of 67; fast drain, connection survival and live transport 139 of 140. The one miss,
    `liveTimeoutDoesNotAwaitCancellationInsensitiveWork` (0.314 s against its 0.25 s bound), is a wall-clock check that
    also missed under load in library-79's v1.9.5 and v1.9.6 gates; alone, five times on this build at load 250-330
    (2026-10-04 09:20), it passed 5 of 5.
  - The 10,000-broadcast run delivered every message once and in order in 182 ms: the median 100-message batch took
    2.35 ms in the first 1,000 and 1.40 ms in the last 1,000, and the runtime held 128 messages.
- The room-bench, before (v1.9.5) and after, on a local self-hosted server with spans on: queued; its numbers go here
  and in #461's work log.
