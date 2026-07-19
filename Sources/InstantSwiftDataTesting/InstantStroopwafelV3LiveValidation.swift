import Dependencies
import Foundation
import InstantSwiftData
import StroopwafelV3App

@MainActor
private final class StroopwafelV3MessageOutcome {
  var accepted = false
  var failure: InstantError?
}

public struct InstantStroopwafelV3LiveColorPromptEvidence:
  Codable, Equatable, Sendable
{
  public var color: String
  public var label: String

  public init(color: String, label: String) {
    self.color = color
    self.label = label
  }
}

public struct InstantStroopwafelV3LivePointEvidence:
  Codable, Equatable, Sendable
{
  public var id: String
  public var value: Int
  public var userID: String

  public init(id: String, value: Int, userID: String) {
    self.id = id
    self.value = value
    self.userID = userID
  }
}

public struct InstantStroopwafelV3LiveRoomEvidence:
  Codable, Equatable, Sendable
{
  public var id: String
  public var code: String?
  public var hostID: String
  public var readyIDs: [String]
  public var kickedIDs: [String]
  public var currentGameID: String?
  public var userIDs: [String]

  public init(
    id: String,
    code: String?,
    hostID: String,
    readyIDs: [String],
    kickedIDs: [String],
    currentGameID: String?,
    userIDs: [String]
  ) {
    self.id = id
    self.code = code
    self.hostID = hostID
    self.readyIDs = readyIDs
    self.kickedIDs = kickedIDs
    self.currentGameID = currentGameID
    self.userIDs = userIDs
  }
}

public struct InstantStroopwafelV3LiveGameEvidence:
  Codable, Equatable, Sendable
{
  public var id: String
  public var status: String
  public var playerIDs: [String]
  public var colors: [InstantStroopwafelV3LiveColorPromptEvidence]
  public var userIDs: [String]
  public var roomIDs: [String]
  public var points: [InstantStroopwafelV3LivePointEvidence]

  public init(
    id: String,
    status: String,
    playerIDs: [String],
    colors: [InstantStroopwafelV3LiveColorPromptEvidence],
    userIDs: [String],
    roomIDs: [String],
    points: [InstantStroopwafelV3LivePointEvidence]
  ) {
    self.id = id
    self.status = status
    self.playerIDs = playerIDs
    self.colors = colors
    self.userIDs = userIDs
    self.roomIDs = roomIDs
    self.points = points
  }
}

public struct InstantStroopwafelV3LiveValidationDetails:
  Codable, Equatable, Sendable
{
  public var room: InstantStroopwafelV3LiveRoomEvidence
  public var game: InstantStroopwafelV3LiveGameEvidence
  public var typeScriptPointObservedBySwift: InstantStroopwafelV3LivePointEvidence
  public var completedStatus: String
  public var winningPointValue: Int
  public var currentGameIDAfterCompletion: String?
  public var connectionState: String

  public init(
    room: InstantStroopwafelV3LiveRoomEvidence,
    game: InstantStroopwafelV3LiveGameEvidence,
    typeScriptPointObservedBySwift: InstantStroopwafelV3LivePointEvidence,
    completedStatus: String,
    winningPointValue: Int,
    currentGameIDAfterCompletion: String?,
    connectionState: String
  ) {
    self.room = room
    self.game = game
    self.typeScriptPointObservedBySwift = typeScriptPointObservedBySwift
    self.completedStatus = completedStatus
    self.winningPointValue = winningPointValue
    self.currentGameIDAfterCompletion = currentGameIDAfterCompletion
    self.connectionState = connectionState
  }
}

public enum InstantStroopwafelV3LiveValidation {
  public static let roomID = "00000000-0000-4000-8000-000000000301"
  public static let roomCode = "AB12"
  public static let gameID = "00000000-0000-4000-8000-000000000302"
  public static let swiftHostID = "swift-host"
  public static let typeScriptGuestID = "typescript-guest"
  public static let hostPointID = "00000000-0000-4000-8000-000000000303"
  public static let guestPointID = "00000000-0000-4000-8000-000000000304"
  public static let hostHandle = "SwiftHost"
  public static let guestHandle = "TypeScriptGuest"
  public static let createdAt = "2026-07-19T00:00:00.000Z"
  public static let deletedAt = "2026-07-19T00:01:00.000Z"

  public static var colors: StroopwafelV3ColorSequence {
    StroopwafelV3ColorSequence(
      StroopwafelExample.generateGameColors(seed: gameID).map {
        StroopwafelV3ColorPrompt(color: $0.color, label: $0.label)
      }
    )
  }

  public static var prompts: [InstantStroopwafelV3LiveColorPromptEvidence] {
    colors.values.map { .init(color: $0.color, label: $0.label) }
  }

  public static func pointIDs(
    hostUserID: String,
    guestUserID: String
  ) -> [String: InstantID<StroopwafelV3Point>] {
    [
      hostUserID: InstantID(rawValue: hostPointID),
      guestUserID: InstantID(rawValue: guestPointID),
    ]
  }

  public static func expectedPlayerIDs(
    hostUserID: String,
    guestUserID: String
  ) -> [String] {
    [hostUserID, guestUserID].sorted()
  }

  public static func run(
    appID: String,
    apiURI: URL,
    websocketURI: URL,
    refreshToken: String,
    expectedHostUserID: String,
    expectedGuestUserID: String,
    persistenceURL: URL? = nil,
    onSwiftRoomReady: @escaping @Sendable () -> Void = {},
    onTypeScriptReadyObserved: @escaping @Sendable () -> Void = {},
    onSwiftGameStarted: @escaping @Sendable () -> Void = {},
    onTypeScriptPointObserved: @escaping @Sendable () -> Void = {},
    onSwiftCompleted: @escaping @Sendable () -> Void = {}
  ) async throws -> ValidationEvidenceRow<InstantStroopwafelV3LiveValidationDetails> {
    let client = try await liveClient(
      appID: appID,
      apiURI: apiURI,
      websocketURI: websocketURI,
      persistenceURL: persistenceURL
    )
    try await authenticate(
      client,
      refreshToken: refreshToken,
      expectedUserID: expectedHostUserID
    )

    let hostID = InstantID<StroopwafelV3User>(rawValue: expectedHostUserID)
    let roomRows = FetchOne<StroopwafelV3Room?>()
    let roomTask = Task {
      try await roomRows.task(StroopwafelV3Room.forCode(roomCode), using: client)
    }
    defer { roomTask.cancel() }

    try await requireServerAcceptance(
      SetupStroopwafelV3Profile(
        userID: hostID,
        handle: hostHandle,
        createdAt: createdAt
      ),
      using: client,
      operation: "set up Swift Stroopwafel profile"
    )
    try await requireServerAcceptance(
      CreateStroopwafelV3Room(
        roomID: InstantID(rawValue: roomID),
        code: roomCode,
        hostID: hostID,
        createdAt: createdAt
      ),
      using: client,
      operation: "create Swift Stroopwafel room"
    )
    _ = try await waitForRoom(roomRows) { room in
      room.id.rawValue == roomID
        && room.hostID == expectedHostUserID
        && room.users.contains { $0.id.rawValue == expectedHostUserID }
    }
    onSwiftRoomReady()

    var readyRoom = try await waitForRoom(roomRows) { room in
      room.readyIDs.values.contains(expectedGuestUserID)
        && room.users.contains { $0.id.rawValue == expectedGuestUserID }
    }
    onTypeScriptReadyObserved()

    let gameRows = FetchOne<StroopwafelV3Game?>()
    let gameTask = Task {
      try await gameRows.task(
        StroopwafelV3Game.byID(InstantID(rawValue: gameID)),
        using: client
      )
    }
    defer { gameTask.cancel() }
    try await requireServerAcceptance(
      StartStroopwafelV3Game(
        room: readyRoom,
        gameID: InstantID(rawValue: gameID),
        pointIDsByPlayerID: pointIDs(
          hostUserID: expectedHostUserID,
          guestUserID: expectedGuestUserID
        ),
        colors: colors,
        createdAt: createdAt
      ),
      using: client,
      operation: "start Swift Stroopwafel game"
    )
    _ = try await waitForGame(gameRows) { game in
      game.status == StroopwafelExample.gameInProgress
        && game.playerIDs.values.sorted()
          == expectedPlayerIDs(
            hostUserID: expectedHostUserID,
            guestUserID: expectedGuestUserID
          )
        && game.colors == colors
        && game.points.count == 2
    }
    readyRoom = try await waitForRoom(roomRows) { $0.currentGameID == gameID }
    let startedRoomEvidence = roomEvidence(readyRoom)
    onSwiftGameStarted()

    let gameWithGuestPoint = try await waitForGame(gameRows) { game in
      game.points.contains {
        $0.userID == expectedGuestUserID && $0.value == 1
      }
    }
    guard let typeScriptPoint = gameWithGuestPoint.points.first(where: {
      $0.userID == expectedGuestUserID && $0.value == 1
    }) else {
      throw failure("The TypeScript-owned Stroopwafel point was not available for evidence.")
    }
    let observedPointEvidence = pointEvidence(typeScriptPoint)
    let startedGameEvidence = gameEvidence(gameWithGuestPoint)
    onTypeScriptPointObserved()

    var currentGame = gameWithGuestPoint
    while currentGame.status == StroopwafelExample.gameInProgress {
      guard let hostPoint = currentGame.points.first(where: {
        $0.userID == expectedHostUserID
      }), currentGame.colors.values.indices.contains(hostPoint.value) else {
        throw failure("The Swift host point or canonical prompt was missing.")
      }
      let prompt = currentGame.colors.values[hostPoint.value]
      try await requireServerAcceptance(
        TapStroopwafelV3Color(
          game: currentGame,
          userID: hostID,
          selectedColor: prompt.label
        ),
        using: client,
        operation: "score Swift Stroopwafel point \(hostPoint.value + 1)"
      )
      currentGame = try await waitForGame(gameRows) { game in
        guard let nextPoint = game.points.first(where: {
          $0.userID == expectedHostUserID
        }) else { return false }
        return nextPoint.value > hostPoint.value
          || game.status == StroopwafelExample.gameCompleted
      }
    }

    guard let winningPoint = currentGame.points.first(where: {
      $0.userID == expectedHostUserID
    }) else {
      throw failure("The completed Stroopwafel game did not include the host point.")
    }
    let completedRoom = try await waitForRoom(roomRows) { $0.currentGameID == nil }
    onSwiftCompleted()
    let status = try await client.connectionStatus()
    guard await client.pendingMutations().isEmpty else {
      throw failure("The Stroopwafel live runner still had pending mutations.")
    }
    _ = try await client.closeConnection()

    return ValidationEvidenceRow(
      caseID: "validation.live.stroopwafel-v3",
      side: "swift",
      event: "typescript-point-and-swift-completion-observed",
      appID: appID,
      entityID: gameID,
      timestampMs: Int64((Date().timeIntervalSince1970 * 1_000).rounded()),
      ok: true,
      details: InstantStroopwafelV3LiveValidationDetails(
        room: startedRoomEvidence,
        game: startedGameEvidence,
        typeScriptPointObservedBySwift: observedPointEvidence,
        completedStatus: currentGame.status,
        winningPointValue: winningPoint.value,
        currentGameIDAfterCompletion: completedRoom.currentGameID,
        connectionState: status.state.rawValue
      )
    )
  }

  private static func liveClient(
    appID: String,
    apiURI: URL,
    websocketURI: URL,
    persistenceURL: URL?
  ) async throws -> InstantSwiftDataClient {
    try await withDependencies {
      $0.context = .live
      $0.instantLiveTransport = .live
      try await $0.bootstrapInstantSwiftData(
        appID: appID,
        apiURI: apiURI,
        websocketURI: websocketURI,
        persistenceURL: persistenceURL
          ?? FileManager.default.temporaryDirectory
          .appendingPathComponent("instant-stroopwafel-v3-live-\(UUID().uuidString).sqlite"),
        context: .live,
        initialAttributes: StroopwafelV3Schema.attributes
      )
    } operation: {
      @Dependency(\.defaultInstantSwiftData) var client
      return client
    }
  }

  private static func authenticate(
    _ client: InstantSwiftDataClient,
    refreshToken: String,
    expectedUserID: String
  ) async throws {
    let session = try await client.signInWithRefreshToken(
      refreshToken,
      userID: "untrusted-swift-stroopwafel-user"
    )
    guard session.userID == expectedUserID else {
      throw failure("Server-verified Swift Stroopwafel user did not match the expected host.")
    }
    _ = try await client.connect()
    try await withTimeout("authenticate Swift Stroopwafel client") {
      while try await client.connectionStatus().state != .authenticated {
        try await Task.sleep(for: .milliseconds(25))
      }
    }
  }

  private static func requireServerAcceptance<Message: InstantMessage>(
    _ message: Message,
    using client: InstantSwiftDataClient,
    operation: String
  ) async throws {
    let outcome = await MainActor.run { StroopwafelV3MessageOutcome() }
    let task = client.send(
      message,
      onServerAccepted: { _ in outcome.accepted = true },
      onFailure: { outcome.failure = $0 }
    )
    defer { task.cancel() }
    let deadline = ContinuousClock.now + .seconds(30)
    while ContinuousClock.now < deadline {
      let result = await MainActor.run { (outcome.accepted, outcome.failure) }
      if let error = result.1 { throw error }
      if result.0 { return }
      try await Task.sleep(for: .milliseconds(25))
    }
    throw failure("Timed out waiting for server acceptance: \(operation).")
  }

  private static func waitForRoom(
    _ rows: FetchOne<StroopwafelV3Room?>,
    matching predicate: @escaping @Sendable (StroopwafelV3Room) -> Bool
  ) async throws -> StroopwafelV3Room {
    try await withTimeout("observe canonical Stroopwafel room") {
      while true {
        if let room = rows.wrappedValue, predicate(room) { return room }
        try await Task.sleep(for: .milliseconds(25))
      }
    }
  }

  private static func waitForGame(
    _ rows: FetchOne<StroopwafelV3Game?>,
    matching predicate: @escaping @Sendable (StroopwafelV3Game) -> Bool
  ) async throws -> StroopwafelV3Game {
    try await withTimeout("observe canonical Stroopwafel game") {
      while true {
        if let game = rows.wrappedValue, predicate(game) { return game }
        try await Task.sleep(for: .milliseconds(25))
      }
    }
  }

  private static func roomEvidence(
    _ room: StroopwafelV3Room
  ) -> InstantStroopwafelV3LiveRoomEvidence {
    InstantStroopwafelV3LiveRoomEvidence(
      id: room.id.rawValue,
      code: room.code,
      hostID: room.hostID,
      readyIDs: room.readyIDs.values.sorted(),
      kickedIDs: room.kickedIDs.values.sorted(),
      currentGameID: room.currentGameID,
      userIDs: room.users.map(\.id.rawValue).sorted()
    )
  }

  private static func pointEvidence(
    _ point: StroopwafelV3Point
  ) -> InstantStroopwafelV3LivePointEvidence {
    InstantStroopwafelV3LivePointEvidence(
      id: point.id.rawValue,
      value: point.value,
      userID: point.userID
    )
  }

  private static func gameEvidence(
    _ game: StroopwafelV3Game
  ) -> InstantStroopwafelV3LiveGameEvidence {
    InstantStroopwafelV3LiveGameEvidence(
      id: game.id.rawValue,
      status: game.status,
      playerIDs: game.playerIDs.values.sorted(),
      colors: game.colors.values.map { .init(color: $0.color, label: $0.label) },
      userIDs: game.users.map(\.id.rawValue).sorted(),
      roomIDs: game.rooms.map(\.id.rawValue).sorted(),
      points: game.points.map(pointEvidence).sorted { $0.id < $1.id }
    )
  }

  private static func withTimeout<Value: Sendable>(
    _ operation: String,
    _ body: @escaping @Sendable () async throws -> Value
  ) async throws -> Value {
    try await withThrowingTaskGroup(of: Value.self) { group in
      group.addTask { try await body() }
      group.addTask {
        try await Task.sleep(for: .seconds(30))
        throw failure("Timed out: \(operation).")
      }
      guard let value = try await group.next() else {
        throw failure("No result produced: \(operation).")
      }
      group.cancelAll()
      return value
    }
  }

  private static func failure(_ message: String) -> InstantError {
    InstantError(
      code: .implementationFailed,
      operation: "validate Stroopwafel V3 live contract",
      message: message,
      recovery: "Inspect the canonical durable room, game, point, schema, and permission lifecycle."
    )
  }
}
