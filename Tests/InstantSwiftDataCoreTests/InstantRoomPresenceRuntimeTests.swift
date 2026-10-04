import CustomDump
import Foundation
import Testing
@testable import InstantSwiftDataCore

/// Rooms and presence against `Reactor.js`, the TypeScript client (#461).
///
/// `Reactor.js` keeps a room's presence in memory (`_presence`), publishes it with one synchronous socket send
/// (`publishPresence`, `_trySetPresence`), applies `patch-presence` and `refresh-presence` in `_handleReceive` beside
/// every other frame, and calls a presence handler only when its slice changed (`hasPresenceResponseChanged`,
/// presence.ts). Topic broadcasts are handed to each subscriber once and never stored (`_notifyBroadcastSubs`).
/// These tests drive the runtime through a scripted socket; no network is involved.
@Suite(.serialized)
struct InstantRoomPresenceRuntimeTests {
  /// A presence publish must not queue behind the operation gate, which commits and server applies hold for hundreds
  /// of milliseconds on a phone (perf-040: p50 295 ms while dictating). `Reactor.js` takes no lock at all.
  @Test
  func aPresencePublishReturnsWhileTheOperationGateIsHeld() async throws {
    let room = InstantRoomHandle(type: "recording", id: "room-gate")
    let gateHolder = RoomTestGate()
    let session = LiveReactorParitySession(messages: [
      liveReactorInitOK(attrs: liveReactorTodoServerAttrs, sessionID: "session-self")
    ])
    var configuration = try roomConfiguration(appID: "room-presence-gate", transport: session.transport)
    configuration.onAuthSessionObservationHoldsOperationGateForTesting = { await gateHolder.parkIfArmed() }
    let runtime = try await InstantRuntime.bootstrap(configuration: configuration)
    try await withRoomCleanup({ await gateHolder.release() }) {
      _ = try await runtime.connect()
      _ = try await runtime.joinRoom(room)
      try await joinAndWaitForPeers(runtime: runtime, session: session, room: room)

      await gateHolder.arm()
      let observation = Task { try await runtime.observeAuthSession() }
      try await waitForRoom("observeAuthSession to hold the operation gate") { await gateHolder.parkedCount == 1 }

      _ = try await instantLiveWithTimeout(
        operation: "publish presence while the operation gate is held",
        timeoutMilliseconds: 5_000
      ) {
        try await runtime.setPresence(room: room, userID: "user-self", values: ["state": .string("working")])
      }
      try await waitForRoom("the set-presence to reach the socket while the gate is held") {
        await session.sentMessages().contains { $0.op == "set-presence" }
      }
      await gateHolder.release()
      _ = try await observation.value
      _ = try await runtime.closeConnection()
    }
  }

  /// A live runtime's presence lives in memory, as `Reactor.js` keeps it in `_presence`: nothing is written to
  /// SQLite, so a relaunched runtime holds no presence from an earlier connection.
  @Test
  func aLivePresencePublishWritesNothingToSQLite() async throws {
    let room = InstantRoomHandle(type: "recording", id: "room-sqlite")
    let persistenceURL = try temporaryRoomCacheURL()
    let session = LiveReactorParitySession(messages: [
      liveReactorInitOK(attrs: liveReactorTodoServerAttrs, sessionID: "session-self")
    ])
    var configuration = try roomConfiguration(appID: "room-presence-sqlite", transport: session.transport)
    configuration.persistenceURL = persistenceURL
    let runtime = try await InstantRuntime.bootstrap(configuration: configuration)
    _ = try await runtime.connect()
    _ = try await runtime.joinRoom(room)
    try await joinAndWaitForPeers(runtime: runtime, session: session, room: room)
    _ = try await runtime.setPresence(room: room, userID: "user-self", values: ["state": .string("working")])
    _ = try await runtime.closeConnection()

    let relaunched = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "room-presence-sqlite",
        persistenceURL: persistenceURL,
        initialAttributes: TodoExample.attributes,
        now: { roomTestNow }
      )
    )
    let stored = try await relaunched.roomPresence(room: room)
    expectNoDifference(stored, [], "A live publish left a presence row in SQLite.")
  }

  /// `Reactor.js` applies a `patch-presence` in `_handleReceive` as it arrives. The runtime's applier applies query
  /// frames one at a time, each in about 300 ms on a phone; a presence frame must not wait behind them.
  @Test
  func aPresencePatchAppliesWhileAnEarlierFrameIsStillApplying() async throws {
    let room = InstantRoomHandle(type: "recording", id: "room-applier")
    let applier = RoomTestGate()
    let session = LiveReactorParitySession(messages: [
      liveReactorInitOK(attrs: liveReactorTodoServerAttrs, sessionID: "session-self")
    ])
    var configuration = try roomConfiguration(appID: "room-presence-applier", transport: session.transport)
    configuration.onLiveReceiverEventAcquiredForTesting = { await applier.parkIfArmed() }
    let runtime = try await InstantRuntime.bootstrap(configuration: configuration)
    try await withRoomCleanup({ await applier.release() }) {
      _ = try await runtime.connect()
      _ = try await runtime.joinRoom(room)
      let presence = try await RoomPresenceRecorder.start(runtime: runtime, room: room)
      defer { presence.stop() }
      try await joinAndWaitForPeers(runtime: runtime, session: session, room: room, recorder: presence)

      await applier.arm()
      await session.enqueue(roomTestLongFrame)
      try await waitForRoom("the applier to hold the earlier frame") { await applier.parkedCount == 1 }
      await session.enqueue(
        InstantLiveMessage(
          op: "patch-presence",
          fields: [
            "edits": .array([roomPresenceEdit(path: ["session-peer", "data", "status"], operation: "r", value: .string("away"))]),
            "room-id": .string(room.id),
          ]
        )
      )
      try await waitForRoom("the patch to reach observers while the earlier frame still applies") {
        await presence.last?.first { $0.userID == "user-peer" }?.values["status"] == .string("away")
      }
      await applier.release()
      _ = try await runtime.closeConnection()
    }
  }

  /// `Reactor.js` calls a presence handler only when its slice changed (`hasPresenceResponseChanged`). A frame that
  /// restates what an observer already has, and a `set-presence-ok`, must not wake it.
  @Test
  func aPresenceFrameThatChangesNothingDoesNotEmit() async throws {
    let room = InstantRoomHandle(type: "recording", id: "room-unchanged")
    let session = LiveReactorParitySession(messages: [
      liveReactorInitOK(attrs: liveReactorTodoServerAttrs, sessionID: "session-self")
    ])
    let runtime = try await InstantRuntime.bootstrap(
      configuration: try roomConfiguration(appID: "room-presence-unchanged", transport: session.transport)
    )
    _ = try await runtime.connect()
    _ = try await runtime.joinRoom(room)
    let presence = try await RoomPresenceRecorder.start(runtime: runtime, room: room)
    defer { presence.stop() }
    try await joinAndWaitForPeers(runtime: runtime, session: session, room: room, recorder: presence)
    let emissionsBefore = await presence.count

    await session.enqueue(roomPeersRefresh(room: room, status: "online"))
    await session.enqueue(InstantLiveMessage(op: "set-presence-ok", fields: ["room-id": .string(room.id)]))
    try await Task.sleep(nanoseconds: 300_000_000)
    let emissionsAfterRestatement = await presence.count
    expectNoDifference(
      emissionsAfterRestatement, emissionsBefore,
      "A refresh-presence that restated the room and a set-presence-ok emitted again."
    )

    await session.enqueue(roomPeersRefresh(room: room, status: "away"))
    try await waitForRoom("a real change to emit") {
      await presence.last?.first { $0.userID == "user-peer" }?.values["status"] == .string("away")
    }
    _ = try await runtime.closeConnection()
  }

  /// `Reactor.js` drops a room's presence only in `_cleanupRoom`, when its last subscriber leaves. One holder's
  /// leaveRoom must keep the presence every other holder still sees, and later patches must apply to it.
  @Test
  func oneHoldersLeaveRoomKeepsThePresenceTheOtherHolderSees() async throws {
    let room = InstantRoomHandle(type: "recording", id: "room-refcount")
    let session = LiveReactorParitySession(messages: [
      liveReactorInitOK(attrs: liveReactorTodoServerAttrs, sessionID: "session-self")
    ])
    let runtime = try await InstantRuntime.bootstrap(
      configuration: try roomConfiguration(appID: "room-presence-refcount", transport: session.transport)
    )
    _ = try await runtime.connect()
    _ = try await runtime.joinRoom(room)
    _ = try await runtime.joinRoom(room)
    let presence = try await RoomPresenceRecorder.start(runtime: runtime, room: room)
    defer { presence.stop() }
    try await joinAndWaitForPeers(runtime: runtime, session: session, room: room, recorder: presence)

    _ = try await runtime.leaveRoom(room)
    let opsAfterOneLeave = await session.sentMessages().map(\.op)
    #expect(!opsAfterOneLeave.contains("leave-room"), "One of two holders left, so the room stays joined.")
    await session.enqueue(
      InstantLiveMessage(
        op: "patch-presence",
        fields: [
          "edits": .array([roomPresenceEdit(path: ["session-peer", "data", "status"], operation: "r", value: .string("away"))]),
          "room-id": .string(room.id),
        ]
      )
    )
    try await waitForRoom("the patch to apply on top of the peer the other holder sees") {
      await presence.last?.contains { $0.values["status"] == .string("away") } == true
    }
    let peer = try #require(await presence.last?.first { $0.values["status"] == .string("away") })
    expectNoDifference(peer.userID, "user-peer")
    expectNoDifference(peer.values, ["status": .string("away"), "name": .string("Ada")])
    _ = try await runtime.closeConnection()
  }

  /// leavePresence stops publishing this device's presence. Peers must stop seeing it (the server only learns that
  /// through `set-presence`), and a rejoin after a dropped socket must not announce it again.
  @Test
  func leavePresenceClearsItForPeersAndForTheNextJoin() async throws {
    let room = InstantRoomHandle(type: "recording", id: "room-leave-presence")
    let first = LiveReactorParitySession(messages: [
      liveReactorInitOK(attrs: liveReactorTodoServerAttrs, sessionID: "session-before-drop")
    ])
    let second = LiveReactorParitySession(messages: [
      liveReactorInitOK(attrs: liveReactorTodoServerAttrs, sessionID: "session-after-drop")
    ])
    let transport = LiveReactorParityTransport(sessions: [first, second])
    let runtime = try await InstantRuntime.bootstrap(
      configuration: try roomConfiguration(appID: "room-leave-presence", transport: transport.transport)
    )
    _ = try await runtime.connect()
    _ = try await runtime.joinRoom(room)
    try await joinAndWaitForPeers(runtime: runtime, session: first, room: room)
    _ = try await runtime.setPresence(room: room, userID: "user-self", values: ["state": .string("working")])
    try await waitForRoom("the presence to reach the socket") {
      await first.sentMessages().contains { $0.op == "set-presence" }
    }

    _ = try await runtime.leavePresence(room: room, userID: "user-self")
    try await waitForRoom("a set-presence that clears this device's presence for its peers") {
      await first.sentMessages().contains { $0.op == "set-presence" && $0.fields["data"] == .object([:]) }
    }

    await first.failReceive(
      InstantError(
        code: .networkFailed,
        operation: "drop the room presence session",
        message: "transient drop",
        recovery: "Rejoin without the presence this device stopped publishing."
      )
    )
    try await instantLiveWithTimeout(operation: "wait for the room reconnect", timeoutMilliseconds: 5_000) {
      await transport.waitForConnectionCount(2)
    }
    await second.waitForSentMessageCount(2)
    let rejoin = try #require(await second.sentMessages().first { $0.op == "join-room" })
    #expect(
      rejoin.fields["data"] == nil || rejoin.fields["data"] == .object([:]),
      "The rejoin announced the presence leavePresence had cleared: \(String(describing: rejoin.fields["data"]))"
    )
    _ = try await runtime.closeConnection()
  }

  /// A presence set before joinRoom must reach the room, as `Reactor.js` sends `initialPresence` with `join-room`
  /// and again on `join-room-ok` (`_flushEnqueuedRoomData`). The typed `.presence` and `.instantRoom` modifiers run as
  /// separate tasks, so either can go first.
  @Test
  func aPresenceSetBeforeJoinRoomReachesTheRoom() async throws {
    let room = InstantRoomHandle(type: "recording", id: "room-early-presence")
    let session = LiveReactorParitySession(messages: [
      liveReactorInitOK(attrs: liveReactorTodoServerAttrs, sessionID: "session-self")
    ])
    let runtime = try await InstantRuntime.bootstrap(
      configuration: try roomConfiguration(appID: "room-early-presence", transport: session.transport)
    )
    _ = try await runtime.connect()
    _ = try await runtime.setPresence(room: room, userID: "user-self", values: ["state": .string("early")])
    _ = try await runtime.joinRoom(room)
    try await waitForRoom("the join to reach the socket") {
      await session.sentMessages().contains { $0.op == "join-room" }
    }
    let join = try #require(await session.sentMessages().first { $0.op == "join-room" })
    expectNoDifference(join.fields["data"], .object(["state": .string("early")]))
    await session.enqueue(InstantLiveMessage(op: "join-room-ok", fields: ["room-id": .string(room.id)]))
    try await waitForRoom("the presence to be sent again once the server confirms the join") {
      await session.sentMessages().contains {
        $0.op == "set-presence" && $0.fields["data"] == .object(["state": .string("early")])
      }
    }
    _ = try await runtime.closeConnection()
  }

  /// `Reactor.js` stores no topic messages; it hands each broadcast to the subscribers once (`_notifyBroadcastSubs`).
  /// A live publish must leave nothing in SQLite, and a burst that arrives before an observer reads must not lose all
  /// but the newest message.
  @Test
  func liveTopicMessagesAreNotStoredAndABurstIsNotLost() async throws {
    let room = InstantRoomHandle(type: "recording", id: "room-topics")
    let persistenceURL = try temporaryRoomCacheURL()
    let session = LiveReactorParitySession(messages: [
      liveReactorInitOK(attrs: liveReactorTodoServerAttrs, sessionID: "session-self")
    ])
    var configuration = try roomConfiguration(appID: "room-topics", transport: session.transport)
    configuration.persistenceURL = persistenceURL
    let runtime = try await InstantRuntime.bootstrap(configuration: configuration)
    _ = try await runtime.connect()
    _ = try await runtime.joinRoom(room)
    try await joinAndWaitForPeers(runtime: runtime, session: session, room: room)

    _ = try await runtime.publishTopicMessage(
      room: room, topic: "reaction", userID: "user-self", payload: .object(["emoji": .string("wave")])
    )
    let stream = try await runtime.observeRoomTopicMessages(room: room, topic: "reaction")
    for index in 0..<5 {
      await session.enqueue(
        InstantLiveMessage(
          op: "server-broadcast",
          clientEventID: "broadcast-\(index)",
          fields: [
            "data": .object([
              "data": .object(["index": .number(Double(index))]),
              "peer-id": .string("session-peer"),
              "user": .object(["id": .string("user-peer")]),
            ]),
            "room-id": .string(room.id),
            "topic": .string("reaction"),
          ]
        )
      )
    }
    let received = RoomTopicRecorder()
    let reader = Task {
      for await messages in stream { await received.record(messages) }
    }
    defer { reader.cancel() }
    try await waitForRoom("all five broadcasts to be readable after the burst", timeoutMilliseconds: 5_000) {
      let indexes = await received.last?.compactMap { message -> Double? in
        guard case let .object(payload) = message.payload, case let .number(index)? = payload["index"] else {
          return nil
        }
        return index
      }
      return indexes == [0, 1, 2, 3, 4]
    }
    _ = try await runtime.closeConnection()

    let relaunched = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "room-topics",
        persistenceURL: persistenceURL,
        initialAttributes: TodoExample.attributes,
        now: { roomTestNow }
      )
    )
    let stored = try await relaunched.roomTopicMessages(room: room, topic: "reaction")
    expectNoDifference(stored, [], "A live publish left a topic message in SQLite.")
  }
}

extension InstantRoomPresenceRuntimeTests {
  /// Publishes that race from separate tasks leave the newest one on the wire, as this runtime's own state has it: off
  /// the operation gate nothing orders them, so the live session refuses a publication older than one it already
  /// recorded. `Reactor.js` publishes synchronously, so its newest publish is always its last send.
  @Test
  func racingPresencePublishesLeaveTheNewestOnTheWire() async throws {
    let room = InstantRoomHandle(type: "recording", id: "room-race")
    let session = LiveReactorParitySession(messages: [
      liveReactorInitOK(attrs: liveReactorTodoServerAttrs, sessionID: "session-self")
    ])
    let runtime = try await InstantRuntime.bootstrap(
      configuration: try roomConfiguration(appID: "room-presence-race", transport: session.transport)
    )
    _ = try await runtime.connect()
    _ = try await runtime.joinRoom(room)
    try await joinAndWaitForPeers(runtime: runtime, session: session, room: room)
    await withTaskGroup(of: Void.self) { group in
      for index in 0..<50 {
        group.addTask {
          _ = try? await runtime.setPresence(room: room, userID: "user-self", values: ["n": .number(Double(index))])
        }
      }
    }
    let local = try #require(try await runtime.roomPresence(room: room).first { $0.isLocal })
    let expected = JSONValue.object(local.values)
    try await waitForRoom("the last set-presence on the wire to match the runtime's own presence") {
      await session.sentMessages().last { $0.op == "set-presence" }?.fields["data"]?.jsonValue == expected
    }
    _ = try await runtime.closeConnection()
  }

  /// An older presence whose write is slow must not land after a newer one. Each send writes from its own task, so
  /// without one ordered lane per room the newer set-presence passed the slow one and the wire ended on the older
  /// presence: `racingPresencePublishesLeaveTheNewestOnTheWire` failed 1 of 3 runs under load in library-79's 1.9.8
  /// dev run. `Reactor.js` writes with a synchronous `ws.send`, in call order.
  @Test
  func anOlderPresenceWhoseWriteIsSlowNeverLandsAfterANewerOne() async throws {
    let room = InstantRoomHandle(type: "recording", id: "room-slow-write")
    let session = LiveReactorParitySession(messages: [
      liveReactorInitOK(attrs: liveReactorTodoServerAttrs, sessionID: "session-self")
    ])
    let writes = SlowFirstPresenceWrite()
    let inner = session.webSocketSession
    let slowFirstWrite = InstantLiveWebSocketSession(
      send: { message in
        guard message.op == "set-presence" else {
          try await inner.send(message)
          return
        }
        let order = await writes.arrive()
        if order == 1 {
          await writes.holdTheFirstWrite()
        }
        try await inner.send(message)
        if order == 2 {
          await writes.secondWriteReturned()
        }
      },
      receive: { try await inner.receive() },
      close: { await inner.close() },
      abort: { inner.abort() }
    )
    let runtime = try await InstantRuntime.bootstrap(
      configuration: try roomConfiguration(
        appID: "room-presence-slow-write",
        transport: .immediate { _ in slowFirstWrite }
      )
    )
    _ = try await runtime.connect()
    _ = try await runtime.joinRoom(room)
    try await joinAndWaitForPeers(runtime: runtime, session: session, room: room)

    let first = Task {
      _ = try await runtime.setPresence(room: room, userID: "user-self", values: ["n": .number(1)])
    }
    try await waitForRoom("the first set-presence to reach the socket") { await writes.arrivals >= 1 }
    _ = try await runtime.setPresence(room: room, userID: "user-self", values: ["n": .number(2)])
    try await first.value
    let presenceOnTheWire = await session.sentMessages()
      .filter { $0.op == "set-presence" }
      .compactMap { $0.fields["data"]?.jsonValue }
    expectNoDifference(
      presenceOnTheWire,
      [.object(["n": .number(1)]), .object(["n": .number(2)])],
      "set-presence in the order the runtime published it"
    )
    _ = try await runtime.closeConnection()
  }

  /// The `join-room-ok` flush writes the room's newest presence. A write queued behind it with an older publication
  /// must not follow it, or peers see 3, 2, 3. Here the flush waits behind a write the dropped socket never finished,
  /// and two newer publications queue behind the flush.
  @Test
  func noOlderPresenceFollowsTheJoinFlushOnANewSocket() async throws {
    let room = InstantRoomHandle(type: "recording", id: "room-join-flush")
    let first = LiveReactorParitySession(messages: [
      liveReactorInitOK(attrs: liveReactorTodoServerAttrs, sessionID: "session-before-drop")
    ])
    let second = LiveReactorParitySession(messages: [
      liveReactorInitOK(attrs: liveReactorTodoServerAttrs, sessionID: "session-after-drop")
    ])
    let held = HeldPresenceWrite()
    let sessions = ScriptedRoomSessions([held.wrapping(first.webSocketSession), second.webSocketSession])
    var configuration = try roomConfiguration(appID: "room-join-flush", transport: .immediate { _ in try sessions.next() })
    configuration.liveReconnectSleep = { _ in }
    let runtime = try await InstantRuntime.bootstrap(configuration: configuration)
    _ = try await runtime.connect()
    _ = try await runtime.joinRoom(room)
    try await joinAndWaitForPeers(runtime: runtime, session: first, room: room)

    // A write to the first socket that never finishes, holding the room's lane.
    let stuck = Task { _ = try? await runtime.setPresence(room: room, userID: "user-self", values: ["n": .number(1)]) }
    try await waitForRoom("the first write to reach the first socket") { await held.arrivals >= 1 }
    await first.failReceive(
      InstantError(
        code: .networkFailed,
        operation: "drop the room's socket",
        message: "transient drop",
        recovery: "Rejoin on the next socket."
      )
    )
    try await waitForRoom("the room's rejoin on the second socket") {
      await second.sentMessages().contains { $0.op == "join-room" }
    }
    await second.enqueue(InstantLiveMessage(op: "join-room-ok", fields: ["room-id": .string(room.id)]))
    try await waitForRoom("the join flush to queue behind the stuck write") {
      await runtime.roomPresenceLaneWaiterCountForTesting(room) == 1
    }
    let older = Task { _ = try? await runtime.setPresence(room: room, userID: "user-self", values: ["n": .number(2)]) }
    try await waitForRoom("the second publication to queue") {
      await runtime.roomPresenceLaneWaiterCountForTesting(room) == 2
    }
    let newest = Task { _ = try? await runtime.setPresence(room: room, userID: "user-self", values: ["n": .number(3)]) }
    try await waitForRoom("the third publication to queue") {
      await runtime.roomPresenceLaneWaiterCountForTesting(room) == 3
    }

    await held.release()
    _ = await (stuck.value, older.value, newest.value)
    let presenceOnTheSecondSocket = await second.sentMessages()
      .filter { $0.op == "set-presence" }
      .compactMap { $0.fields["data"]?.jsonValue }
    expectNoDifference(
      presenceOnTheSecondSocket,
      [.object(["n": .number(3)])],
      "the flush writes the newest presence and the older writes behind it are skipped"
    )
    _ = try await runtime.closeConnection()
  }

  /// Writes waiting in a room's presence lane when the room is left must return, not wait forever, and must not
  /// write: the lane is handed on whether or not the room is still registered.
  @Test
  func presenceWritesWaitingWhenTheRoomIsLeftReturnWithoutWriting() async throws {
    let room = InstantRoomHandle(type: "recording", id: "room-left-while-waiting")
    let session = LiveReactorParitySession(messages: [
      liveReactorInitOK(attrs: liveReactorTodoServerAttrs, sessionID: "session-self")
    ])
    let held = HeldPresenceWrite()
    let heldSession = held.wrapping(session.webSocketSession)
    let runtime = try await InstantRuntime.bootstrap(
      configuration: try roomConfiguration(
        appID: "room-left-while-waiting",
        transport: .immediate { _ in heldSession }
      )
    )
    _ = try await runtime.connect()
    _ = try await runtime.joinRoom(room)
    try await joinAndWaitForPeers(runtime: runtime, session: session, room: room)

    let writing = Task { _ = try? await runtime.setPresence(room: room, userID: "user-self", values: ["n": .number(1)]) }
    try await waitForRoom("the first write to reach the socket") { await held.arrivals >= 1 }
    let second = Task { _ = try? await runtime.setPresence(room: room, userID: "user-self", values: ["n": .number(2)]) }
    try await waitForRoom("the second write to queue") { await runtime.roomPresenceLaneWaiterCountForTesting(room) == 1 }
    let third = Task { _ = try? await runtime.setPresence(room: room, userID: "user-self", values: ["n": .number(3)]) }
    try await waitForRoom("the third write to queue") { await runtime.roomPresenceLaneWaiterCountForTesting(room) == 2 }

    _ = try await runtime.leaveRoom(room)
    await held.release()
    let finished = RoomTaskCompletion()
    let waiters = Task {
      _ = await (writing.value, second.value, third.value)
      await finished.mark()
    }
    try await waitForRoom("every presence write to return after the room was left") { await finished.isDone }
    waiters.cancel()
    let written = await session.sentMessages()
      .filter { $0.op == "set-presence" }
      .compactMap { $0.fields["data"]?.jsonValue }
    #expect(
      !written.contains(.object(["n": .number(2)])) && !written.contains(.object(["n": .number(3)])),
      "writes that waited past the leave did not write: \(written)"
    )
    #expect(await runtime.roomPresenceLaneWaiterCountForTesting(room) == 0)
    _ = try await runtime.closeConnection()
  }

  /// Two topic publishes in a row reach the socket in the order they were published, as `Reactor.js`'s `publishTopic`
  /// writes synchronously. v1.9.5 held the operation gate across each publish; off the gate each write runs on its own
  /// task, so a slow first write let the second pass it (the rooms agent's review of 8dc4321d).
  @Test
  func topicPublishesReachTheSocketInPublicationOrderWhenTheFirstWriteIsSlow() async throws {
    let room = InstantRoomHandle(type: "recording", id: "room-slow-broadcast")
    let session = LiveReactorParitySession(messages: [
      liveReactorInitOK(attrs: liveReactorTodoServerAttrs, sessionID: "session-self")
    ])
    let writes = SlowFirstPresenceWrite()
    let inner = session.webSocketSession
    let slowFirstBroadcast = InstantLiveWebSocketSession(
      send: { message in
        guard message.op == "client-broadcast" else {
          try await inner.send(message)
          return
        }
        let order = await writes.arrive()
        if order == 1 {
          await writes.holdTheFirstWrite()
        }
        try await inner.send(message)
        if order == 2 {
          await writes.secondWriteReturned()
        }
      },
      receive: { try await inner.receive() },
      close: { await inner.close() },
      abort: { inner.abort() }
    )
    let runtime = try await InstantRuntime.bootstrap(
      configuration: try roomConfiguration(
        appID: "room-slow-broadcast",
        transport: .immediate { _ in slowFirstBroadcast }
      )
    )
    _ = try await runtime.connect()
    _ = try await runtime.joinRoom(room)
    try await joinAndWaitForPeers(runtime: runtime, session: session, room: room)

    let first = Task {
      _ = try await runtime.publishTopicMessage(room: room, topic: "reaction", userID: "user-self", payload: .string("first"))
    }
    try await waitForRoom("the first broadcast to reach the socket") { await writes.arrivals >= 1 }
    _ = try await runtime.publishTopicMessage(room: room, topic: "reaction", userID: "user-self", payload: .string("second"))
    try await first.value
    let broadcasts = await session.sentMessages()
      .filter { $0.op == "client-broadcast" }
      .compactMap { $0.fields["data"]?.jsonValue }
    expectNoDifference(broadcasts, [.string("first"), .string("second")], "client-broadcast in publication order")
    _ = try await runtime.closeConnection()
  }

  /// The broadcasts queued before `join-room-ok` go out before any published after it. The flush waits behind a write
  /// the dropped socket never finished; a publish made while it waits must not pass the queued broadcast.
  @Test
  func aBroadcastPublishedWhileTheJoinFlushWaitsFollowsTheQueuedOnes() async throws {
    let room = InstantRoomHandle(type: "recording", id: "room-flush-broadcasts")
    let first = LiveReactorParitySession(messages: [
      liveReactorInitOK(attrs: liveReactorTodoServerAttrs, sessionID: "session-before-drop")
    ])
    let second = LiveReactorParitySession(messages: [
      liveReactorInitOK(attrs: liveReactorTodoServerAttrs, sessionID: "session-after-drop")
    ])
    let held = HeldPresenceWrite()
    let sessions = ScriptedRoomSessions([held.wrapping(first.webSocketSession), second.webSocketSession])
    var configuration = try roomConfiguration(
      appID: "room-flush-broadcasts",
      transport: .immediate { _ in try sessions.next() }
    )
    configuration.liveReconnectSleep = { _ in }
    let runtime = try await InstantRuntime.bootstrap(configuration: configuration)
    _ = try await runtime.connect()
    _ = try await runtime.joinRoom(room)
    try await joinAndWaitForPeers(runtime: runtime, session: first, room: room)

    // A presence write to the first socket that never finishes, holding the room's lane.
    let stuck = Task { _ = try? await runtime.setPresence(room: room, userID: "user-self", values: ["n": .number(1)]) }
    try await waitForRoom("the presence write to reach the first socket") { await held.arrivals >= 1 }
    await first.failReceive(
      InstantError(
        code: .networkFailed,
        operation: "drop the room's socket",
        message: "transient drop",
        recovery: "Rejoin on the next socket."
      )
    )
    try await waitForRoom("the room's rejoin on the second socket") {
      await second.sentMessages().contains { $0.op == "join-room" }
    }
    // Published while the room waits for the server's join-room-ok: queued for the flush.
    _ = try await runtime.publishTopicMessage(room: room, topic: "reaction", userID: "user-self", payload: .string("queued"))
    await second.enqueue(InstantLiveMessage(op: "join-room-ok", fields: ["room-id": .string(room.id)]))
    try await waitForRoom("the join to be confirmed") { await runtime.isRoomJoined(room) }
    // Published after the join is confirmed, while the flush waits behind the stuck write.
    let later = Task {
      _ = try? await runtime.publishTopicMessage(room: room, topic: "reaction", userID: "user-self", payload: .string("later"))
    }
    try await waitForRoom("the later broadcast to queue behind the flush, or to be written") {
      let waiting = await runtime.roomPresenceLaneWaiterCountForTesting(room)
      let written = await second.sentMessages().contains { $0.op == "client-broadcast" }
      return waiting >= 2 || written
    }

    await held.release()
    _ = await (stuck.value, later.value)
    try await waitForRoom("both broadcasts on the second socket") {
      await second.sentMessages().filter { $0.op == "client-broadcast" }.count >= 2
    }
    let broadcasts = await second.sentMessages()
      .filter { $0.op == "client-broadcast" }
      .compactMap { $0.fields["data"]?.jsonValue }
    expectNoDifference(broadcasts, [.string("queued"), .string("later")], "the queued broadcast first")
    _ = try await runtime.closeConnection()
  }

  /// `Reactor.js` reports `isLoading: !room.isConnected`: false until `join-room-ok`, and again from a dropped socket
  /// until the rejoin is confirmed. While a room is not joined, its presence says nothing about who is there.
  @Test
  func aRoomIsJoinedOnlyOnceTheServerConfirmsItOnTheCurrentConnection() async throws {
    let room = InstantRoomHandle(type: "recording", id: "room-joined")
    let first = LiveReactorParitySession(messages: [
      liveReactorInitOK(attrs: liveReactorTodoServerAttrs, sessionID: "session-before-drop")
    ])
    let second = LiveReactorParitySession(messages: [
      liveReactorInitOK(attrs: liveReactorTodoServerAttrs, sessionID: "session-after-drop")
    ])
    let transport = LiveReactorParityTransport(sessions: [first, second])
    let runtime = try await InstantRuntime.bootstrap(
      configuration: try roomConfiguration(appID: "room-joined", transport: transport.transport)
    )
    _ = try await runtime.connect()
    _ = try await runtime.joinRoom(room)
    let joinedBeforeAnswer = await runtime.isRoomJoined(room)
    #expect(!joinedBeforeAnswer, "The join was only sent.")
    await first.enqueue(InstantLiveMessage(op: "join-room-ok", fields: ["room-id": .string(room.id)]))
    try await waitForRoom("the server's join-room-ok to mark the room joined") { await runtime.isRoomJoined(room) }

    await first.failReceive(
      InstantError(
        code: .networkFailed,
        operation: "drop the joined-room session",
        message: "transient drop",
        recovery: "Rejoin and wait for the server to confirm it."
      )
    )
    try await instantLiveWithTimeout(operation: "wait for the room reconnect", timeoutMilliseconds: 5_000) {
      await transport.waitForConnectionCount(2)
    }
    await second.waitForSentMessageCount(2)
    let joinedAfterDrop = await runtime.isRoomJoined(room)
    #expect(!joinedAfterDrop, "The rejoin was only sent on the new socket.")
    await second.enqueue(InstantLiveMessage(op: "join-room-ok", fields: ["room-id": .string(room.id)]))
    try await waitForRoom("the rejoin's join-room-ok to mark the room joined again") { await runtime.isRoomJoined(room) }

    _ = try await runtime.leaveRoom(room)
    let joinedAfterLeave = await runtime.isRoomJoined(room)
    #expect(!joinedAfterLeave)
    _ = try await runtime.closeConnection()
  }

  /// `Reactor.js`'s `subscribePresence` options pick keys and peers (`buildPresenceSlice`), and its handler wakes only
  /// when that slice changed (`hasPresenceResponseChanged`).
  @Test
  func aPresenceSelectionSeesOnlyItsKeysAndPeersAndWakesOnlyForThem() async throws {
    let room = InstantRoomHandle(type: "recording", id: "room-selection")
    let session = LiveReactorParitySession(messages: [
      liveReactorInitOK(attrs: liveReactorTodoServerAttrs, sessionID: "session-self")
    ])
    let runtime = try await InstantRuntime.bootstrap(
      configuration: try roomConfiguration(appID: "room-presence-selection", transport: session.transport)
    )
    _ = try await runtime.connect()
    _ = try await runtime.joinRoom(room)
    _ = try await runtime.setPresence(room: room, userID: "user-self", values: ["status": .string("here")])
    let presence = try await RoomPresenceRecorder.start(
      runtime: runtime,
      room: room,
      selection: InstantRoomPresenceSelection(keys: ["status"], peerIDs: ["session-peer"], includesLocal: false)
    )
    defer { presence.stop() }
    try await joinAndWaitForPeers(runtime: runtime, session: session, room: room, recorder: presence)
    let first = try #require(await presence.last)
    expectNoDifference(first.map(\.peerID), ["session-peer"])
    expectNoDifference(first.map(\.values), [["status": .string("online")]])
    let emissionsBefore = await presence.count

    await session.enqueue(
      InstantLiveMessage(
        op: "patch-presence",
        fields: [
          "edits": .array([roomPresenceEdit(path: ["session-peer", "data", "name"], operation: "r", value: .string("Grace"))]),
          "room-id": .string(room.id),
        ]
      )
    )
    try await Task.sleep(nanoseconds: 300_000_000)
    let emissionsAfterUnselectedChange = await presence.count
    expectNoDifference(emissionsAfterUnselectedChange, emissionsBefore, "A change to an unselected key woke the observer.")

    await session.enqueue(
      InstantLiveMessage(
        op: "patch-presence",
        fields: [
          "edits": .array([roomPresenceEdit(path: ["session-peer", "data", "status"], operation: "r", value: .string("away"))]),
          "room-id": .string(room.id),
        ]
      )
    )
    try await waitForRoom("the selected key's change to emit") {
      await presence.last?.first?.values == ["status": .string("away")]
    }
    _ = try await runtime.closeConnection()
  }

  /// #461's acceptance run: 10,000 broadcasts reach an event observer exactly once each, in order, and the runtime holds
  /// a bounded number of messages however many arrive, so the last message costs what the first did. `Reactor.js`
  /// hands each broadcast to the subscribers once and stores none (`_notifyBroadcastSubs`).
  @Test
  func everyMessageOfATenThousandBroadcastRunReachesAnEventObserverOnce() async throws {
    let room = InstantRoomHandle(type: "recording", id: "room-topic-run")
    let session = LiveReactorParitySession(messages: [
      liveReactorInitOK(attrs: liveReactorTodoServerAttrs, sessionID: "session-self")
    ])
    let runtime = try await InstantRuntime.bootstrap(
      configuration: try roomConfiguration(appID: "room-topic-run", transport: session.transport)
    )
    _ = try await runtime.connect()
    _ = try await runtime.joinRoom(room)
    try await joinAndWaitForPeers(runtime: runtime, session: session, room: room)
    let events = try await runtime.observeRoomTopicEvents(room: room, topic: "progress")
    let messageCount = 10_000
    // Each 100 messages are timed as one batch. The check compares the median batch of the first 1,000 with the median
    // batch of the last 1,000, so one stall (a demoted or paused test process) moves no median.
    let batchSize = 100
    let reader = Task { () -> (indexes: [Int], batchMs: [Double]) in
      var indexes: [Int] = []
      indexes.reserveCapacity(messageCount)
      var batchMs: [Double] = []
      let clock = ContinuousClock()
      var batchStarted = clock.now
      for await message in events {
        guard case let .object(payload) = message.payload, case let .number(index)? = payload["index"] else { continue }
        indexes.append(Int(index))
        if indexes.count.isMultiple(of: batchSize) {
          let now = clock.now
          let batch = now - batchStarted
          batchMs.append(Double(batch.components.seconds) * 1_000 + Double(batch.components.attoseconds) / 1e15)
          batchStarted = now
        }
        if indexes.count == messageCount { break }
      }
      return (indexes, batchMs)
    }
    for index in 0..<messageCount {
      await session.enqueue(
        InstantLiveMessage(
          op: "server-broadcast",
          fields: [
            "data": .object([
              "data": .object(["index": .number(Double(index))]),
              "peer-id": .string("session-peer"),
              "user": .object(["id": .string("user-peer")]),
            ]),
            "room-id": .string(room.id),
            "topic": .string("progress"),
          ]
        )
      )
    }
    let run = try await instantLiveWithTimeout(operation: "read 10,000 broadcasts", timeoutMilliseconds: 60_000) {
      await reader.value
    }
    expectNoDifference(run.indexes.count, messageCount, "A broadcast was dropped.")
    #expect(run.indexes == Array(0..<messageCount), "Broadcasts arrived out of order or more than once.")
    let held = await runtime.heldRoomTopicMessageCountForTesting(room: room, topic: "progress")
    #expect(
      held <= InstantRuntimeRoomTopics.recentMessageLimit,
      "The runtime held \(held) messages after 10,000; it must hold a bounded window."
    )
    // A generous bound that only a cost growing with the messages before it would break (stored topics re-read every
    // message on each one). The durations are in the test log for the issue's performance evidence.
    func median(_ values: some Collection<Double>) -> Double {
      let sorted = values.sorted()
      return sorted.isEmpty ? 0 : sorted[sorted.count / 2]
    }
    let batchesPerThousand = 1_000 / batchSize
    let firstMedianMs = median(run.batchMs.prefix(batchesPerThousand))
    let lastMedianMs = median(run.batchMs.suffix(batchesPerThousand))
    print(
      "room-topic-run: \(run.batchMs.count) batches of \(batchSize), median batch \(firstMedianMs) ms in the first 1,000 "
        + "and \(lastMedianMs) ms in the last 1,000, all 10,000 in \(run.batchMs.reduce(0, +)) ms, held \(held)"
    )
    #expect(run.batchMs.count == messageCount / batchSize)
    #expect(lastMedianMs <= max(firstMedianMs * 10, 25))
    _ = try await runtime.closeConnection()
  }
}

// MARK: - Fixtures

let roomTestNow = InstantTimestamp(milliseconds: 1_700_000_100_000)

/// An unknown op: the runtime's applier takes it as the frame being applied and ignores it otherwise. A parked
/// `RoomTestGate` holds it, standing in for a long refresh-ok apply.
let roomTestLongFrame = InstantLiveMessage(op: "room-test-long-frame", clientEventID: nil, fields: [:])

func roomPresenceSession(
  peerID: String,
  userID: String,
  values: [String: InstantLiveJSONValue]
) -> InstantLiveJSONValue {
  .object([
    "data": .object(values),
    "peer-id": .string(peerID),
    "user": .object(["id": .string(userID)]),
  ])
}

func roomPresenceEdit(
  path: [String],
  operation: String,
  value: InstantLiveJSONValue? = nil
) -> InstantLiveJSONValue {
  var parts: [InstantLiveJSONValue] = [.array(path.map(InstantLiveJSONValue.string)), .string(operation)]
  if let value { parts.append(value) }
  return .array(parts)
}

/// The server's view of the room: this runtime's own session (which the runtime must leave out) and one peer.
func roomPeersRefresh(room: InstantRoomHandle, status: String) -> InstantLiveMessage {
  InstantLiveMessage(
    op: "refresh-presence",
    fields: [
      "data": .object([
        "session-self": roomPresenceSession(peerID: "session-self", userID: "user-self", values: [:]),
        "session-peer": roomPresenceSession(
          peerID: "session-peer",
          userID: "user-peer",
          values: ["status": .string(status), "name": .string("Ada")]
        ),
      ]),
      "room-id": .string(room.id),
    ]
  )
}

func temporaryRoomCacheURL() throws -> URL {
  let directory = FileManager.default.temporaryDirectory
    .appendingPathComponent("InstantRoomPresenceRuntimeTests-\(UUID().uuidString)")
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  return directory.appendingPathComponent("state.sqlite")
}

func roomConfiguration(
  appID: String,
  transport: InstantLiveTransportClient
) throws -> InstantRuntimeConfiguration {
  var configuration = InstantRuntimeConfiguration(
    appID: appID,
    persistenceURL: try temporaryRoomCacheURL(),
    initialAttributes: TodoExample.attributes,
    now: { roomTestNow },
    liveTransport: transport
  )
  configuration.autoConnectLiveTransport = false
  return configuration
}

/// Confirms the join and waits until the runtime has applied the room's first `refresh-presence` (one peer, online),
/// so every later frame meets a joined room.
func joinAndWaitForPeers(
  runtime: InstantRuntime,
  session: LiveReactorParitySession,
  room: InstantRoomHandle,
  recorder: RoomPresenceRecorder? = nil
) async throws {
  await session.enqueue(InstantLiveMessage(op: "join-room-ok", fields: ["room-id": .string(room.id)]))
  await session.enqueue(roomPeersRefresh(room: room, status: "online"))
  try await waitForRoom("the room's first refresh-presence to apply") {
    if let recorder {
      return await recorder.last?.contains { $0.userID == "user-peer" } == true
    }
    return try await runtime.roomPresence(room: room).contains { $0.userID == "user-peer" }
  }
}

// MARK: - Helpers

/// A socket whose first set-presence write is slow: it waits until a second set-presence has been written, or 300 ms.
/// Through one ordered lane the second waits for the first, so the first's wait ends by time and the writes keep their
/// order; with each send on its own task, the second is written first.
actor SlowFirstPresenceWrite {
  private(set) var arrivals = 0
  private var heldFirstWrite: CheckedContinuation<Void, Never>?
  private var secondWriteDone = false

  /// Counts a set-presence reaching the socket and returns its place: 1 for the first.
  func arrive() -> Int {
    arrivals += 1
    return arrivals
  }

  func holdTheFirstWrite() async {
    guard !secondWriteDone else { return }
    await withCheckedContinuation { continuation in
      heldFirstWrite = continuation
      Task {
        try? await Task.sleep(for: .milliseconds(300))
        self.releaseTheFirstWrite()
      }
    }
  }

  func secondWriteReturned() {
    secondWriteDone = true
    releaseTheFirstWrite()
  }

  private func releaseTheFirstWrite() {
    heldFirstWrite?.resume()
    heldFirstWrite = nil
  }
}


/// A socket whose first set-presence write waits until the test releases it: a write the socket never finished.
actor HeldPresenceWrite {
  private(set) var arrivals = 0
  private var heldWrite: CheckedContinuation<Void, Never>?
  private var isReleased = false

  /// The session that holds its first set-presence write, then writes through `inner`.
  nonisolated func wrapping(_ inner: InstantLiveWebSocketSession) -> InstantLiveWebSocketSession {
    InstantLiveWebSocketSession(
      send: { message in
        if message.op == "set-presence", await self.arrive() == 1 {
          await self.hold()
        }
        try await inner.send(message)
      },
      receive: { try await inner.receive() },
      close: { await inner.close() },
      abort: { inner.abort() }
    )
  }

  private func arrive() -> Int {
    arrivals += 1
    return arrivals
  }

  private func hold() async {
    guard !isReleased else { return }
    await withCheckedContinuation { continuation in
      heldWrite = continuation
    }
  }

  func release() {
    isReleased = true
    heldWrite?.resume()
    heldWrite = nil
  }
}

/// Live sessions handed out one per connection attempt, in order.
// SAFETY: `lock` protects `remaining`, the only mutable state.
final class ScriptedRoomSessions: @unchecked Sendable {
  private let lock = NSLock()
  private var remaining: [InstantLiveWebSocketSession]

  init(_ sessions: [InstantLiveWebSocketSession]) {
    remaining = sessions
  }

  func next() throws -> InstantLiveWebSocketSession {
    lock.lock()
    defer { lock.unlock() }
    guard !remaining.isEmpty else {
      throw InstantError(
        code: .networkFailed,
        operation: "connect the scripted room sessions",
        message: "No scripted live session remains.",
        recovery: "Add one scripted session for every expected connection."
      )
    }
    return remaining.removeFirst()
  }
}

/// Whether a group of tasks has finished.
actor RoomTaskCompletion {
  private(set) var isDone = false

  func mark() {
    isDone = true
  }
}

/// Every emission of one room's presence observation, read as soon as it is published.
struct RoomPresenceRecorder: Sendable {
  private actor Emissions {
    private(set) var values: [[InstantRoomPresenceMember]] = []

    func record(_ members: [InstantRoomPresenceMember]) {
      values.append(members)
    }
  }

  private let emissions: Emissions
  private let reader: Task<Void, Never>

  private init(stream: AsyncStream<[InstantRoomPresenceMember]>) {
    let emissions = Emissions()
    self.emissions = emissions
    reader = Task {
      for await members in stream { await emissions.record(members) }
    }
  }

  var count: Int {
    get async { await emissions.values.count }
  }

  var last: [InstantRoomPresenceMember]? {
    get async { await emissions.values.last }
  }

  static func start(
    runtime: InstantRuntime,
    room: InstantRoomHandle,
    selection: InstantRoomPresenceSelection = .all
  ) async throws -> RoomPresenceRecorder {
    let recorder = RoomPresenceRecorder(
      stream: try await runtime.observeRoomPresence(room: room, selection: selection)
    )
    try await waitForRoom("the observation's first emission") { await recorder.count > 0 }
    return recorder
  }

  func stop() {
    reader.cancel()
  }
}

actor RoomTopicRecorder {
  private(set) var last: [InstantRoomTopicMessage]?

  func record(_ messages: [InstantRoomTopicMessage]) {
    last = messages
  }
}

/// Parks whoever enters it while armed, until `release()`. Through `onAuthSessionObservationHoldsOperationGateForTesting`
/// it holds the operation gate; through `onLiveReceiverEventAcquiredForTesting` it holds the applier on a frame.
actor RoomTestGate {
  private var isArmed = false
  private var isReleased = false
  private var parked: [CheckedContinuation<Void, Never>] = []
  private(set) var parkedCount = 0

  func arm() {
    isArmed = true
  }

  func parkIfArmed() async {
    guard isArmed, !isReleased else { return }
    parkedCount += 1
    await withCheckedContinuation { parked.append($0) }
  }

  func release() {
    isReleased = true
    let parked = parked
    self.parked.removeAll()
    for continuation in parked { continuation.resume() }
  }
}

struct RoomWaitTimedOut: Error, CustomStringConvertible {
  var description: String
}

/// Polls `condition` every 2 ms for at most `timeoutMilliseconds` (5 s by default, the codebase's timeout rule).
func waitForRoom(
  _ description: String,
  timeoutMilliseconds: Int = 5_000,
  _ condition: @Sendable () async throws -> Bool
) async throws {
  let deadline = ContinuousClock.now + .milliseconds(timeoutMilliseconds)
  while !(try await condition()) {
    guard ContinuousClock.now < deadline else {
      throw RoomWaitTimedOut(description: "Timed out after \(timeoutMilliseconds) ms waiting for \(description).")
    }
    try await Task.sleep(nanoseconds: 2_000_000)
  }
}

/// Runs `cleanup` after `body`, including when `body` throws, so a failed wait never leaves a parked task behind.
func withRoomCleanup(
  _ cleanup: @Sendable () async -> Void,
  _ body: () async throws -> Void
) async throws {
  do {
    try await body()
  } catch {
    await cleanup()
    throw error
  }
  await cleanup()
}
