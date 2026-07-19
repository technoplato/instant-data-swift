import CustomDump
import Foundation
import InstantSwiftData
import InstantSwiftDataTesting
import PresenceRecipesV3App
import Testing

@Suite
struct InstantMergeTileGameV3LiveValidationTests {
  @Test
  func canonicalFixturesPinIndependentCellsAndExactColorPresence() throws {
    expectNoDifference(
      InstantMergeTileGameV3LiveValidation.swiftCell,
      InstantMergeTileGameV3LiveCell(cell: "0-0", color: "#e76f51")
    )
    expectNoDifference(
      InstantMergeTileGameV3LiveValidation.typeScriptCell,
      InstantMergeTileGameV3LiveCell(cell: "0-1", color: "#2a9d8f")
    )

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    expectNoDifference(
      String(
        decoding: try encoder.encode(InstantMergeTileGameV3LiveValidation.swiftPresence),
        as: UTF8.self
      ),
      ##"{"color":"#e76f51"}"##
    )
    expectNoDifference(
      String(
        decoding: try encoder.encode(InstantMergeTileGameV3LiveValidation.typeScriptPresence),
        as: UTF8.self
      ),
      ##"{"color":"#2a9d8f"}"##
    )
  }

  @Test
  func independentCellMergeAndResetPreserveCanonicalBoardShape() {
    var state = MergeTileGameV3Board.emptyState
    InstantMergeTileGameV3LiveValidation.merge(
      InstantMergeTileGameV3LiveValidation.swiftCell,
      into: &state
    )
    InstantMergeTileGameV3LiveValidation.merge(
      InstantMergeTileGameV3LiveValidation.typeScriptCell,
      into: &state
    )

    expectNoDifference(state["0-0"], "#e76f51")
    expectNoDifference(state["0-1"], "#2a9d8f")
    expectNoDifference(state.count, 16)

    InstantMergeTileGameV3LiveValidation.reset(&state)
    expectNoDifference(state, MergeTileGameV3Board.emptyState)
  }

  @Test
  func remoteCountsExcludeTheLocalPeerAndReachZeroAfterDisconnect() {
    let room = InstantRoomHandle(
      type: MergeTileGameV3Room.roomType,
      id: MergeTileGameV3Room.defaultRoomID
    )
    let local = member(room: room, userID: "swift-user", color: "#e76f51")
    let remote = member(room: room, userID: "typescript-user", color: "#2a9d8f")

    expectNoDifference(
      InstantMergeTileGameV3LiveValidation.remoteColorPeerCount(
        in: [local, remote],
        excludingUserID: "swift-user"
      ),
      1
    )
    expectNoDifference(
      InstantMergeTileGameV3LiveValidation.remotePeerCount(
        in: [local],
        excludingUserID: "swift-user"
      ),
      0
    )
  }

  @Test
  func evidenceRoundTripsExactBoardPresenceAndCleanupValues() throws {
    var state = MergeTileGameV3Board.emptyState
    state["0-0"] = "#e76f51"
    state["0-1"] = "#2a9d8f"
    let details = InstantMergeTileGameV3LiveValidationDetails(
      boardID: MergeTileGameV3Board.boardID,
      roomType: MergeTileGameV3Room.roomType,
      roomID: MergeTileGameV3Room.defaultRoomID,
      publishedCell: InstantMergeTileGameV3LiveValidation.swiftCell,
      observedCell: InstantMergeTileGameV3LiveValidation.typeScriptCell,
      boardStateAfterBothMerges: state,
      boardStateAfterReset: MergeTileGameV3Board.emptyState,
      observedPeerID: "typescript-session",
      remoteColorPeerCount: 1,
      remotePeerCountAfterDisconnect: 0,
      connectionState: "authenticated"
    )
    let encoded = try JSONEncoder().encode(details)
    expectNoDifference(
      try JSONDecoder().decode(
        InstantMergeTileGameV3LiveValidationDetails.self,
        from: encoded
      ),
      details
    )
  }

  private func member(
    room: InstantRoomHandle,
    userID: String,
    color: String
  ) -> InstantRoomPresenceMember {
    InstantRoomPresenceMember(
      appID: "merge-tile-app",
      room: room,
      userID: userID,
      values: ["color": .string(color)],
      updatedAt: InstantTimestamp(milliseconds: 1)
    )
  }
}
