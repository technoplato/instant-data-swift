import CustomDump
import Foundation
import InstantSwiftData
import StroopwafelV3App
import Testing

#if canImport(SwiftUI)
  import SwiftUI
#endif

// Canonical source:
// jsventures/stroopwafel@7f5e2379464d932c0e4681655cbf022f8d9c2614
// - instant.schema.ts
// - src/game.ts
// - src/components/scenes/WaitingRoom.tsx
@Suite
struct StroopwafelV3SourceContractTests {
  #if canImport(SwiftUI)
    @Test @MainActor
    func desiredWrapperOwnedScreenSyntaxCompiles() {
      let screen: any View = StroopwafelV3Screen()
      _ = screen
    }
  #endif

  @Test
  func desiredTypedEntityQueryAndMessageSyntaxCompiles() {
    let rooms = FetchOne(StroopwafelV3Room.forCode("ABCD"))
    let game = FetchOne(
      StroopwafelV3Game.byID(InstantID<StroopwafelV3Game>(rawValue: "game-1"))
    )
    let users = FetchAll(StroopwafelV3User.query)
    let roomDraft = StroopwafelV3Room.Draft(
      code: "ABCD",
      hostID: "host",
      readyIDs: [],
      kickedIDs: [],
      createdAt: "2026-07-19T00:00:00.000Z"
    )

    _ = rooms
    _ = game
    _ = users
    _ = roomDraft
    _ = SetupStroopwafelV3Profile(
      userID: InstantID(rawValue: "user-1"),
      handle: "PlayerOne",
      createdAt: "2026-07-19T00:00:00.000Z"
    )
  }

  @Test
  func typedEntitiesPreserveCanonicalNamespacesAndWireAttributes() {
    expectNoDifference(StroopwafelV3User.instantNamespace, "$users")
    expectNoDifference(StroopwafelV3Room.instantNamespace, "rooms")
    expectNoDifference(StroopwafelV3Game.instantNamespace, "games")
    expectNoDifference(StroopwafelV3Point.instantNamespace, "points")
    expectNoDifference(
      StroopwafelV3Room.instantAttributes.map(\.name),
      ["id", "code", "hostId", "readyIds", "kickedIds", "currentGameId", "created_at", "deleted_at", "users"]
    )
    expectNoDifference(
      StroopwafelV3Game.instantAttributes.map(\.name),
      ["id", "status", "playerIds", "colors", "created_at", "users", "rooms", "points"]
    )
  }

  @Test
  func JSONWireValuesMatchCanonicalTypeScriptShapesExactly() throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]

    expectNoDifference(
      String(decoding: try encoder.encode(StroopwafelV3StringList(["host", "guest"])), as: UTF8.self),
      #"["host","guest"]"#
    )
    expectNoDifference(
      String(
        decoding: try encoder.encode(
          StroopwafelV3ColorSequence([
            StroopwafelV3ColorPrompt(color: "red", label: "blue"),
            StroopwafelV3ColorPrompt(color: "yellow", label: "green"),
          ])
        ),
        as: UTF8.self
      ),
      #"[{"color":"red","label":"blue"},{"color":"yellow","label":"green"}]"#
    )
  }

  @Test
  func kickedPlayerCannotPrepareAJoinMessage() async throws {
    let room = StroopwafelV3Room(
      id: InstantID(rawValue: "room-1"),
      code: "ABCD",
      hostID: "host",
      readyIDs: [],
      kickedIDs: ["guest"],
      createdAt: "2026-07-19T00:00:00.000Z"
    )
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "stroopwafel-v3-source-contract",
        persistenceURL: FileManager.default.temporaryDirectory
          .appendingPathComponent("stroopwafel-v3-source-contract-\(UUID().uuidString).sqlite"),
        initialAttributes: StroopwafelV3Schema.attributes
      )
    )
    let client = InstantSwiftDataClient(runtime: runtime)

    await #expect(throws: StroopwafelV3MessageError.playerWasKicked("guest")) {
      _ = try await JoinStroopwafelV3Room(
        room: room,
        userID: InstantID(rawValue: "guest")
      ).prepare(using: client)
    }
  }
}
