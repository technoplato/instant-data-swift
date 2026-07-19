import CustomDump
import Foundation
import InstantSwiftData
import StroopwafelV3App
import Testing

@Suite
struct StroopwafelV3LifecycleTests {
  @Test
  func messagesRunTheCanonicalMultiplayerLifecycleThroughTypedQueries() async throws {
    let persistenceURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("stroopwafel-v3-lifecycle-\(UUID().uuidString).sqlite")
    defer { try? FileManager.default.removeItem(at: persistenceURL) }

    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "stroopwafel-v3-lifecycle",
        persistenceURL: persistenceURL,
        initialAttributes: StroopwafelV3Schema.attributes
      )
    )
    let client = InstantSwiftDataClient(runtime: runtime)
    let hostID = InstantID<StroopwafelV3User>(rawValue: "user-host")
    let guestID = InstantID<StroopwafelV3User>(rawValue: "user-guest")
    let roomID = InstantID<StroopwafelV3Room>(rawValue: "room-1")
    let gameID = InstantID<StroopwafelV3Game>(rawValue: "game-1")

    try await send(
      SetupStroopwafelV3Profile(
        userID: hostID,
        handle: "Host123",
        createdAt: "2026-07-19T00:00:00.000Z"
      ),
      using: client
    )
    try await send(
      SetupStroopwafelV3Profile(
        userID: guestID,
        handle: "Guest123",
        createdAt: "2026-07-19T00:00:00.001Z"
      ),
      using: client
    )
    let host = try await client.query(
      InstantQuery<StroopwafelV3User>(
        filters: [.equals(field: "id", value: .string(hostID.rawValue))]
      )
    )
    expectNoDifference(host.first?.handle, "Host123")

    try await send(
      CreateStroopwafelV3Room(
        roomID: roomID,
        code: "AB12",
        hostID: hostID,
        createdAt: "2026-07-19T00:00:00.010Z"
      ),
      using: client
    )
    var room = try #require(try await client.query(StroopwafelV3Room.forCode("AB12")).first)
    expectNoDifference(room.users.map(\.id), [hostID])

    try await send(JoinStroopwafelV3Room(room: room, userID: guestID), using: client)
    room = try #require(try await client.query(StroopwafelV3Room.forCode("AB12")).first)
    expectNoDifference(room.users.map(\.id.rawValue).sorted(), [guestID.rawValue, hostID.rawValue])

    try await send(
      SetStroopwafelV3Ready(room: room, userID: guestID, isReady: true),
      using: client
    )
    room = try #require(try await client.query(StroopwafelV3Room.forCode("AB12")).first)
    expectNoDifference(room.readyIDs.values, [guestID.rawValue])

    let colors = StroopwafelV3ColorSequence(
      StroopwafelExample.generateGameColors(seed: gameID.rawValue).map {
        StroopwafelV3ColorPrompt(color: $0.color, label: $0.label)
      }
    )
    expectNoDifference(colors.values.count, StroopwafelExample.multiplayerScoreToWin + 1)
    try await send(
      StartStroopwafelV3Game(
        room: room,
        gameID: gameID,
        pointIDsByPlayerID: [
          hostID.rawValue: InstantID(rawValue: "point-host"),
          guestID.rawValue: InstantID(rawValue: "point-guest"),
        ],
        colors: colors,
        createdAt: "2026-07-19T00:00:00.020Z"
      ),
      using: client
    )

    var game = try #require(try await client.query(StroopwafelV3Game.byID(gameID)).first)
    expectNoDifference(game.status, StroopwafelExample.gameInProgress)
    expectNoDifference(game.playerIDs.values.sorted(), [guestID.rawValue, hostID.rawValue])
    expectNoDifference(game.points.map(\.value), [0, 0])
    expectNoDifference(game.rooms.first?.currentGameID, gameID.rawValue)

    let firstPrompt = try #require(game.colors.values.first)
    let wrongColor = try #require(
      StroopwafelExample.colorChoices.first { $0 != firstPrompt.label }
    )
    try await send(
      TapStroopwafelV3Color(game: game, userID: hostID, selectedColor: wrongColor),
      using: client
    )
    game = try #require(try await client.query(StroopwafelV3Game.byID(gameID)).first)
    expectNoDifference(game.points.first { $0.userID == hostID.rawValue }?.value, 0)

    while game.status == StroopwafelExample.gameInProgress {
      let point = try #require(game.points.first { $0.userID == hostID.rawValue })
      let prompt = try #require(game.colors.values[safe: point.value])
      try await send(
        TapStroopwafelV3Color(
          game: game,
          userID: hostID,
          selectedColor: prompt.label
        ),
        using: client
      )
      game = try #require(try await client.query(StroopwafelV3Game.byID(gameID)).first)
    }
    expectNoDifference(game.status, StroopwafelExample.gameCompleted)
    expectNoDifference(
      game.points.first { $0.userID == hostID.rawValue }?.value,
      StroopwafelExample.multiplayerScoreToWin
    )
    expectNoDifference(game.rooms.first?.currentGameID, nil)

    room = try #require(game.rooms.first)
    try await send(
      LeaveStroopwafelV3Room(
        room: room,
        userID: hostID,
        deletedAt: "2026-07-19T00:00:00.090Z"
      ),
      using: client
    )
    let activeRooms = try await client.query(StroopwafelV3Room.forCode("AB12"))
    expectNoDifference(activeRooms, [])
  }

  private func send<Message: InstantMessage>(
    _ message: Message,
    using client: InstantSwiftDataClient
  ) async throws {
    let prepared = try await message.prepare(using: client)
    _ = try await client.transact {
      for mutation in prepared.mutations {
        mutation
      }
    }
  }
}

private extension Collection {
  subscript(safe index: Index) -> Element? {
    indices.contains(index) ? self[index] : nil
  }
}
