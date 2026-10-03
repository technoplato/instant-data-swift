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
    await withKnownIssue("setPresence waits for the operation gate (#461)") {
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
          timeoutMilliseconds: 2_000
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
  }

  /// A live runtime's presence lives in memory, as `Reactor.js` keeps it in `_presence`: nothing is written to
  /// SQLite, so a relaunched runtime holds no presence from an earlier connection.
  @Test
  func aLivePresencePublishWritesNothingToSQLite() async throws {
    await withKnownIssue("setPresence saves the member to SQLite (#461)") {
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
  }

  /// `Reactor.js` applies a `patch-presence` in `_handleReceive` as it arrives. The runtime's applier applies query
  /// frames one at a time, each in about 300 ms on a phone; a presence frame must not wait behind them.
  @Test
  func aPresencePatchAppliesWhileAnEarlierFrameIsStillApplying() async throws {
    await withKnownIssue("room frames queue behind the query applier (#461)") {
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
  }

  /// `Reactor.js` calls a presence handler only when its slice changed (`hasPresenceResponseChanged`). A frame that
  /// restates what an observer already has, and a `set-presence-ok`, must not wake it.
  @Test
  func aPresenceFrameThatChangesNothingDoesNotEmit() async throws {
    await withKnownIssue("every presence frame emits, even an unchanged one (#461)") {
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
  }

  /// `Reactor.js` drops a room's presence only in `_cleanupRoom`, when its last subscriber leaves. One holder's
  /// leaveRoom must keep the presence every other holder still sees, and later patches must apply to it.
  @Test
  func oneHoldersLeaveRoomKeepsThePresenceTheOtherHolderSees() async throws {
    await withKnownIssue("leaveRoom wipes the room's presence while another holder remains (#461)") {
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
  }

  /// leavePresence stops publishing this device's presence. Peers must stop seeing it (the server only learns that
  /// through `set-presence`), and a rejoin after a dropped socket must not announce it again.
  @Test
  func leavePresenceClearsItForPeersAndForTheNextJoin() async throws {
    await withKnownIssue("leavePresence only deletes a local row and a rejoin re-announces it (#461)") {
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
      try await instantLiveWithTimeout(operation: "wait for the room reconnect", timeoutMilliseconds: 2_000) {
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
  }

  /// A presence set before joinRoom must reach the room, as `Reactor.js` sends `initialPresence` with `join-room`
  /// and again on `join-room-ok` (`_flushEnqueuedRoomData`). The typed `.presence` and `.instantRoom` modifiers run as
  /// separate tasks, so either can go first.
  @Test
  func aPresenceSetBeforeJoinRoomReachesTheRoom() async throws {
    await withKnownIssue("a presence published before joinRoom is dropped (#461)") {
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
  }

  /// `Reactor.js` stores no topic messages; it hands each broadcast to the subscribers once (`_notifyBroadcastSubs`).
  /// A live publish must leave nothing in SQLite, and a burst that arrives before an observer reads must not lose all
  /// but the newest message.
  @Test
  func liveTopicMessagesAreNotStoredAndABurstIsNotLost() async throws {
    await withKnownIssue("topics are stored forever and an observer sees only the newest received message (#461)") {
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
      try await waitForRoom("all five broadcasts to be readable after the burst", timeoutMilliseconds: 2_000) {
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

  static func start(runtime: InstantRuntime, room: InstantRoomHandle) async throws -> RoomPresenceRecorder {
    let recorder = RoomPresenceRecorder(stream: try await runtime.observeRoomPresence(room: room))
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
