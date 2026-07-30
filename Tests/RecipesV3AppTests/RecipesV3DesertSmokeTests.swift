import AuthV3App
import CustomDump
import Dependencies
import Foundation
import InstantSwiftData
import PresenceRecipesV3App
import RecipesV3App
import Testing
import TodosV3App

@Suite(.serialized)
struct RecipesV3DesertSmokeTests {
  @Test(arguments: InstantRecipeV3.allCases)
  func twoClientDesertSmoke(recipe: InstantRecipeV3) async throws {
    let appID = "recipes-desert-\(recipe.rawValue)-\(UUID().uuidString)"
    let coordinator = InstantDesertCoordinator(
      appID: appID,
      initialAttributes: RecipesV3AppConfiguration.initialAttributes
    )
    let hostDirectory = try temporaryDirectory(named: "\(recipe.rawValue)-host")
    let peerDirectory = try temporaryDirectory(named: "\(recipe.rawValue)-peer")
    defer {
      try? FileManager.default.removeItem(at: hostDirectory)
      try? FileManager.default.removeItem(at: peerDirectory)
    }

    let host = try await desertClient(
      appID: appID,
      persistenceURL: hostDirectory.appendingPathComponent("cache.sqlite"),
      coordinator: coordinator,
      adapter: "recipe-smoke-host"
    )
    let peer = try await desertClient(
      appID: appID,
      persistenceURL: peerDirectory.appendingPathComponent("cache.sqlite"),
      coordinator: coordinator,
      adapter: "recipe-smoke-peer"
    )

    let hostStatus = try await host.connect()
    let peerStatus = try await peer.connect()
    expectNoDifference(hostStatus.syncRoute.route, .desert)
    expectNoDifference(hostStatus.transport, .inProcess)
    expectNoDifference(peerStatus.syncRoute.route, .desert)
    expectNoDifference(peerStatus.transport, .inProcess)

    let phase: String
    switch recipe {
    case .todos:
      try await smokeTodos(host: host, peer: peer)
      phase = "bidirectional-durable-mutation"

    case .cursors:
      try await smokePresence(
        host: host,
        peer: peer,
        room: InstantRoomHandle(type: CursorsV3Room.roomType, id: CursorsV3Room.defaultRoomID),
        published: [
          CursorsV3Room.defaultSpaceID: cursorValue(
            CursorsV3Cursor(
              x: 150,
              y: 90,
              xPercent: 25,
              yPercent: 40,
              color: "#123456"
            )
          )
        ],
        cleared: [:]
      )
      phase = "presence-publish-clear-disconnect"

    case .customCursors:
      try await smokePresence(
        host: host,
        peer: peer,
        room: InstantRoomHandle(
          type: CustomCursorsV3Room.roomType,
          id: CustomCursorsV3Room.defaultRoomID
        ),
        published: [
          "name": .string("desert-host"),
          CustomCursorsV3Room.defaultSpaceID: cursorValue(
            CursorsV3Cursor(
              x: 300,
              y: 200,
              xPercent: 75,
              yPercent: 60,
              color: "#654321"
            )
          ),
        ],
        cleared: ["name": .string("desert-host")]
      )
      phase = "named-presence-publish-clear-disconnect"

    case .reactions:
      try await smokeReactions(host: host, peer: peer)
      phase = "bidirectional-topic-publish"

    case .typingIndicator:
      try await smokeTypingIndicator(host: host, peer: peer)
      phase = "presence-frame-sequence"

    case .avatarStack:
      try await smokeAvatarStack(host: host, peer: peer)
      phase = "bidirectional-roster-disconnect"

    case .mergeTileGame:
      try await smokeMergeTileGame(host: host, peer: peer)
      phase = "filtered-query-merge-reset-presence"

    case .auth:
      try await smokeAuth(host: host, peer: peer)
      phase = "independent-local-auth-sessions"
    }

    _ = try await host.closeConnection()
    _ = try await peer.closeConnection()

    let evidence = RecipesV3DesertSmokeEvidence(
      recipe: recipe.rawValue,
      appID: appID,
      route: hostStatus.syncRoute.route.rawValue,
      hostAdapter: hostStatus.syncRoute.adapter,
      peerAdapter: peerStatus.syncRoute.adapter,
      transport: hostStatus.transport.rawValue,
      phase: phase,
      ok: true
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    print("INSTANT_RECIPES_DESERT_SMOKE \(String(decoding: try encoder.encode(evidence), as: UTF8.self))")
  }
}

private struct RecipesV3DesertSmokeEvidence: Codable, Sendable {
  var recipe: String
  var appID: String
  var route: String
  var hostAdapter: String
  var peerAdapter: String
  var transport: String
  var phase: String
  var ok: Bool
}

private func desertClient(
  appID: String,
  persistenceURL: URL,
  coordinator: InstantDesertCoordinator,
  adapter: String
) async throws -> InstantSwiftDataClient {
  var dependencies = DependencyValues()
  let incrementingUUID = UUIDGenerator.incrementing
  let uuidPrefix = adapter.hasSuffix("host") ? "10000000" : "20000000"
  dependencies.date = .constant(Date(timeIntervalSince1970: 1_800_000_000))
  dependencies.uuid = UUIDGenerator {
    let suffix = incrementingUUID().uuidString.dropFirst(8)
    return UUID(uuidString: uuidPrefix + suffix)!
  }
  dependencies.instantSyncRoutePolicy = .desertRequired
  dependencies.instantCloudSyncTransportFactory = InstantSyncTransportFactory(
    adapter: "cloud-trap",
    transport: .webSocket,
    makeTransport: {
      throw InstantError(
        code: .implementationFailed,
        operation: "run Recipes V3 desert smoke",
        message: "The forced desert smoke selected the cloud transport.",
        recovery: "Keep cloud transport resolution outside the forced desert route."
      )
    }
  )
  dependencies.instantDesertSyncTransportFactory = InstantSyncTransportFactory(
    adapter: adapter,
    transport: .inProcess,
    makeTransport: { coordinator.transport }
  )
  try await dependencies.bootstrapInstantSwiftData(
    appID: appID,
    persistenceURL: persistenceURL,
    context: .test,
    initialAttributes: RecipesV3AppConfiguration.initialAttributes
  )
  return dependencies.defaultInstantSwiftData
}

private func smokeTodos(
  host: InstantSwiftDataClient,
  peer: InstantSwiftDataClient
) async throws {
  let id = InstantID<Todo>(rawValue: "desert-smoke-todo")
  let peerCreated = await peer.subscribe(Todo.query.order(.serverCreatedAt, .descending))
  let create = try await CreateTodo(
    id: id,
    text: "All recipes cross the desert",
    createdAt: Date(timeIntervalSince1970: 1_800_000_000)
  ).prepare(using: host)
  _ = try await host.transact {
    for mutation in create.mutations { mutation }
  }
  try await requireEmission("peer observe desert todo") {
    for try await todos in peerCreated {
      if todos.contains(where: { $0.id == id && !$0.isCompleted }) { return true }
    }
    return false
  }
  peerCreated.cancel()

  let hostCompleted = await host.subscribe(Todo.query.order(.serverCreatedAt, .descending))
  let complete = try await SetTodoCompletion(id: id, isCompleted: true).prepare(using: peer)
  _ = try await peer.transact {
    for mutation in complete.mutations { mutation }
  }
  try await requireEmission("host observe completed desert todo") {
    for try await todos in hostCompleted {
      if todos.contains(where: { $0.id == id && $0.isCompleted }) { return true }
    }
    return false
  }
  hostCompleted.cancel()
}

private func smokePresence(
  host: InstantSwiftDataClient,
  peer: InstantSwiftDataClient,
  room: InstantRoomHandle,
  published: [String: JSONValue],
  cleared: [String: JSONValue]
) async throws {
  _ = try await host.joinRoom(room)
  _ = try await peer.joinRoom(room)
  _ = try await host.setRoomPresence(
    room: room,
    userID: "desert-host",
    values: published
  )
  try await eventually("peer observe published presence") {
    try await peer.roomPresence(room: room).contains { $0.values == published }
  }

  _ = try await host.setRoomPresence(
    room: room,
    userID: "desert-host",
    values: cleared
  )
  try await eventually("peer observe cleared presence") {
    try await peer.roomPresence(room: room).contains { $0.values == cleared }
  }

  _ = try await host.leaveRoom(room)
  try await eventually("peer observe presence disconnect") {
    try await peer.roomPresence(room: room).allSatisfy { $0.values != cleared }
  }
  _ = try await peer.leaveRoom(room)
}

private func smokeReactions(
  host: InstantSwiftDataClient,
  peer: InstantSwiftDataClient
) async throws {
  let room = InstantRoomHandle(type: ReactionsV3Room.roomType, id: "123")
  _ = try await host.joinRoom(room)
  _ = try await peer.joinRoom(room)

  let hostPayload = JSONValue.object([
    "name": .string(ReactionsV3Name.heart.rawValue),
    "directionAngle": .number(45),
    "rotationAngle": .number(270),
  ])
  let peerMessages = try await peer.observeRoomTopicMessages(
    room: room,
    topic: ReactionsV3Room.Topic.emoji.rawValue
  )
  _ = try await host.publishRoomTopicMessage(
    room: room,
    topic: ReactionsV3Room.Topic.emoji.rawValue,
    userID: "desert-host",
    payload: hostPayload
  )
  try await requireEmission("peer observe desert reaction") {
    for await messages in peerMessages {
      if messages.contains(where: { $0.payload == hostPayload }) { return true }
    }
    return false
  }

  let peerPayload = JSONValue.object([
    "name": .string(ReactionsV3Name.wave.rawValue),
    "directionAngle": .number(90),
    "rotationAngle": .number(180),
  ])
  let hostMessages = try await host.observeRoomTopicMessages(
    room: room,
    topic: ReactionsV3Room.Topic.emoji.rawValue
  )
  _ = try await peer.publishRoomTopicMessage(
    room: room,
    topic: ReactionsV3Room.Topic.emoji.rawValue,
    userID: "desert-peer",
    payload: peerPayload
  )
  try await requireEmission("host observe desert reaction") {
    for await messages in hostMessages {
      if messages.contains(where: { $0.payload == peerPayload }) { return true }
    }
    return false
  }

  _ = try await host.leaveRoom(room)
  _ = try await peer.leaveRoom(room)
}

private func smokeTypingIndicator(
  host: InstantSwiftDataClient,
  peer: InstantSwiftDataClient
) async throws {
  let room = InstantRoomHandle(type: TypingIndicatorV3Room.roomType, id: "1234")
  _ = try await host.joinRoom(room)
  _ = try await peer.joinRoom(room)
  let frames: [[String: JSONValue]] = [
    ["id": .string("desert-host")],
    ["id": .string("desert-host"), "chat-input": .bool(true)],
    ["id": .string("desert-host"), "chat-input": .bool(false)],
    ["id": .string("desert-host"), "chat-input": .null],
  ]
  for frame in frames {
    _ = try await host.setRoomPresence(
      room: room,
      userID: "desert-host",
      values: frame
    )
    try await eventually("peer observe typing frame") {
      try await peer.roomPresence(room: room).contains { $0.values == frame }
    }
  }
  _ = try await host.leaveRoom(room)
  _ = try await peer.leaveRoom(room)
}

private func smokeAvatarStack(
  host: InstantSwiftDataClient,
  peer: InstantSwiftDataClient
) async throws {
  let room = InstantRoomHandle(
    type: AvatarStackV3Room.roomType,
    id: AvatarStackV3Room.defaultRoomID
  )
  _ = try await host.joinRoom(room)
  _ = try await peer.joinRoom(room)
  _ = try await host.setRoomPresence(
    room: room,
    userID: "desert-host",
    values: ["name": .string("host")]
  )
  _ = try await peer.setRoomPresence(
    room: room,
    userID: "desert-peer",
    values: ["name": .string("peer")]
  )
  try await eventually("peer observe host avatar") {
    try await peer.roomPresence(room: room).contains { $0.values["name"] == .string("host") }
  }
  try await eventually("host observe peer avatar") {
    try await host.roomPresence(room: room).contains { $0.values["name"] == .string("peer") }
  }
  _ = try await host.leaveRoom(room)
  try await eventually("peer observe avatar disconnect") {
    try await peer.roomPresence(room: room).allSatisfy { $0.values["name"] != .string("host") }
  }
  _ = try await peer.leaveRoom(room)
}

private func smokeMergeTileGame(
  host: InstantSwiftDataClient,
  peer: InstantSwiftDataClient
) async throws {
  let room = InstantRoomHandle(
    type: MergeTileGameV3Room.roomType,
    id: MergeTileGameV3Room.defaultRoomID
  )
  _ = try await host.joinRoom(room)
  _ = try await peer.joinRoom(room)
  _ = try await host.setRoomPresence(
    room: room,
    userID: "desert-host",
    values: ["color": .string("#e76f51")]
  )
  try await eventually("peer observe Merge Tile presence") {
    try await peer.roomPresence(room: room).contains {
      $0.values["color"] == .string("#e76f51")
    }
  }

  let peerInitialized = await peer.subscribe(MergeTileGameV3Board.fixedQuery)
  try await transact(InitializeMergeTileGameV3Board(), using: host)
  try await requireEmission("peer observe initialized Merge Tile board") {
    for try await boards in peerInitialized {
      if boards.first?.stateObject == MergeTileGameV3Board.emptyState { return true }
    }
    return false
  }
  peerInitialized.cancel()

  let peerPainted = await peer.subscribe(MergeTileGameV3Board.fixedQuery)
  try await transact(
    PaintMergeTileGameV3Cell(row: 0, column: 0, color: "#e76f51"),
    using: host
  )
  try await requireEmission("peer observe host Merge Tile paint") {
    for try await boards in peerPainted {
      if boards.first?.color(row: 0, column: 0) == "#e76f51" { return true }
    }
    return false
  }
  peerPainted.cancel()

  let hostMerged = await host.subscribe(MergeTileGameV3Board.fixedQuery)
  try await transact(
    PaintMergeTileGameV3Cell(row: 0, column: 1, color: "#2a9d8f"),
    using: peer
  )
  try await requireEmission("host observe merged independent cells") {
    for try await boards in hostMerged {
      if let board = boards.first,
        board.color(row: 0, column: 0) == "#e76f51",
        board.color(row: 0, column: 1) == "#2a9d8f"
      {
        return true
      }
    }
    return false
  }
  hostMerged.cancel()

  let peerReset = await peer.subscribe(MergeTileGameV3Board.fixedQuery)
  try await transact(ResetMergeTileGameV3Board(), using: host)
  try await requireEmission("peer observe Merge Tile reset") {
    for try await boards in peerReset {
      if boards.first?.stateObject == MergeTileGameV3Board.emptyState { return true }
    }
    return false
  }
  peerReset.cancel()

  _ = try await host.leaveRoom(room)
  _ = try await peer.leaveRoom(room)
}

private func smokeAuth(
  host: InstantSwiftDataClient,
  peer: InstantSwiftDataClient
) async throws {
  let hostSession = try await host.signInAsGuest()
  let peerSession = try await peer.signInAsGuest()
  #expect(hostSession.userID != peerSession.userID)
  let restoredHostSession = try await host.authSession()
  let restoredPeerSession = try await peer.authSession()
  expectNoDifference(restoredHostSession?.userID, hostSession.userID)
  expectNoDifference(restoredPeerSession?.userID, peerSession.userID)

  try await host.signOut(invalidateToken: true)
  let signedOutHostSession = try await host.authSession()
  let preservedPeerSession = try await peer.authSession()
  expectNoDifference(signedOutHostSession, nil)
  expectNoDifference(preservedPeerSession?.userID, peerSession.userID)
}

private func transact<Message: InstantMessage>(
  _ message: Message,
  using client: InstantSwiftDataClient
) async throws {
  let prepared = try await message.prepare(using: client)
  _ = try await client.transact {
    for mutation in prepared.mutations { mutation }
  }
}

private func cursorValue(_ cursor: CursorsV3Cursor) -> JSONValue {
  .object([
    "x": .number(cursor.x),
    "y": .number(cursor.y),
    "xPercent": .number(cursor.xPercent),
    "yPercent": .number(cursor.yPercent),
    "color": .string(cursor.color),
  ])
}

private func eventually(
  _ operation: String,
  timeout: Duration = .seconds(3),
  condition: @escaping @Sendable () async throws -> Bool
) async throws {
  let clock = ContinuousClock()
  let deadline = clock.now.advanced(by: timeout)
  while clock.now < deadline {
    if try await condition() { return }
    try await clock.sleep(for: .milliseconds(20))
  }
  throw smokeFailure("Timed out waiting to \(operation).")
}

private func requireEmission(
  _ operation: String,
  timeout: Duration = .seconds(3),
  body: @escaping @Sendable () async throws -> Bool
) async throws {
  let result = try await withThrowingTaskGroup(of: Bool.self) { group in
    group.addTask { try await body() }
    group.addTask {
      try await Task.sleep(for: timeout)
      throw smokeFailure("Timed out waiting to \(operation).")
    }
    guard let value = try await group.next() else {
      throw smokeFailure("The \(operation) observation ended without a value.")
    }
    group.cancelAll()
    return value
  }
  guard result else {
    throw smokeFailure("The \(operation) observation ended before the expected value.")
  }
}

private func smokeFailure(_ message: String) -> InstantError {
  InstantError(
    code: .implementationFailed,
    operation: "run Recipes V3 desert smoke",
    message: message,
    recovery: "Inspect the failing recipe contract and forced desert transport logs."
  )
}

private func temporaryDirectory(named name: String) throws -> URL {
  let directory = FileManager.default.temporaryDirectory
    .appendingPathComponent("RecipesV3DesertSmokeTests-\(name)-\(UUID().uuidString)")
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  return directory
}
