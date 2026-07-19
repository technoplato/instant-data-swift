import CustomDump
import Foundation
import InstantSwiftDataTesting
import Testing

// Canonical live source:
// jsventures/stroopwafel@7f5e2379464d932c0e4681655cbf022f8d9c2614
@Suite
struct InstantStroopwafelV3LiveValidationTests {
  @Test
  func fixturesPinCanonicalCrossSDKIdentifiersAndPrompts() {
    expectNoDifference(InstantStroopwafelV3LiveValidation.roomID, "room-stroopwafel-v3")
    expectNoDifference(InstantStroopwafelV3LiveValidation.roomCode, "AB12")
    expectNoDifference(InstantStroopwafelV3LiveValidation.gameID, "game-stroopwafel-v3")
    expectNoDifference(InstantStroopwafelV3LiveValidation.swiftHostID, "swift-host")
    expectNoDifference(InstantStroopwafelV3LiveValidation.typeScriptGuestID, "typescript-guest")
    expectNoDifference(InstantStroopwafelV3LiveValidation.prompts.count, 14)
    expectNoDifference(
      Set(InstantStroopwafelV3LiveValidation.prompts.flatMap { [$0.color, $0.label] }),
      Set(["red", "green", "blue", "yellow"])
    )
  }

  @Test
  func evidenceRoundTripsExactDurableRoomGameAndPointShapes() throws {
    let details = InstantStroopwafelV3LiveValidationDetails(
      room: InstantStroopwafelV3LiveRoomEvidence(
        id: "room-stroopwafel-v3",
        code: "AB12",
        hostID: "swift-host",
        readyIDs: ["typescript-guest"],
        kickedIDs: [],
        currentGameID: "game-stroopwafel-v3",
        userIDs: ["swift-host", "typescript-guest"]
      ),
      game: InstantStroopwafelV3LiveGameEvidence(
        id: "game-stroopwafel-v3",
        status: "GAME_IN_PROGRESS",
        playerIDs: ["swift-host", "typescript-guest"],
        colors: InstantStroopwafelV3LiveValidation.prompts,
        userIDs: ["swift-host", "typescript-guest"],
        roomIDs: ["room-stroopwafel-v3"],
        points: [
          InstantStroopwafelV3LivePointEvidence(
            id: "point-swift-host",
            value: 0,
            userID: "swift-host"
          ),
          InstantStroopwafelV3LivePointEvidence(
            id: "point-typescript-guest",
            value: 1,
            userID: "typescript-guest"
          ),
        ]
      ),
      typeScriptPointObservedBySwift: InstantStroopwafelV3LivePointEvidence(
        id: "point-typescript-guest",
        value: 1,
        userID: "typescript-guest"
      ),
      completedStatus: "GAME_COMPLETED",
      winningPointValue: 13,
      currentGameIDAfterCompletion: nil,
      connectionState: "authenticated"
    )

    let encoded = try JSONEncoder().encode(details)
    expectNoDifference(
      try JSONDecoder().decode(InstantStroopwafelV3LiveValidationDetails.self, from: encoded),
      details
    )
  }
}
