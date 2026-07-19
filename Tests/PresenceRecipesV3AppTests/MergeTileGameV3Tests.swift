import CustomDump
import Foundation
import PresenceRecipesV3App
import Testing

#if canImport(SwiftUI)
  import SwiftUI
#endif

// Canonical recipe source:
// upstream/instant/client/www/lib/recipes/merge-tile-game.tsx
@Suite
@MainActor
struct MergeTileGameV3Tests {
  #if canImport(SwiftUI)
    @Test
    func desiredEntityRoomPresenceAndMergeSyntaxCompiles() {
      let screen: any View = MergeTileGameV3Screen(
        profileID: "local-session",
        color: "#e76f51"
      )
      _ = screen

      expectNoDifference(
        MergeTileGameV3Board.boardID,
        "83c059e2-ed47-42e5-bdd9-6de88d26c521"
      )
      expectNoDifference(MergeTileGameV3Room.roomType, "tile-game-example")
      expectNoDifference(MergeTileGameV3Room.defaultRoomID, "_defaultRoomId")
    }
  #endif

  @Test
  func sourcePortPreservesTheExactBoardAndPalette() {
    expectNoDifference(MergeTileGameV3Board.boardSize, 4)
    expectNoDifference(MergeTileGameV3Board.emptyColor, "#f5f3f0")
    expectNoDifference(
      MergeTileGameV3Board.colors,
      ["#e76f51", "#2a9d8f", "#e9c46a", "#264653", "#f4a261", "#d4a0d0"]
    )
    expectNoDifference(
      MergeTileGameV3Board.empty.state,
      [
        "0-0": "#f5f3f0", "0-1": "#f5f3f0", "0-2": "#f5f3f0", "0-3": "#f5f3f0",
        "1-0": "#f5f3f0", "1-1": "#f5f3f0", "1-2": "#f5f3f0", "1-3": "#f5f3f0",
        "2-0": "#f5f3f0", "2-1": "#f5f3f0", "2-2": "#f5f3f0", "2-3": "#f5f3f0",
        "3-0": "#f5f3f0", "3-1": "#f5f3f0", "3-2": "#f5f3f0", "3-3": "#f5f3f0",
      ]
    )
  }

  @Test
  func tapProducesTheCanonicalSingleCellMergePatch() throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    expectNoDifference(
      String(
        decoding: try encoder.encode(
          MergeTileGameV3Board.mergePatch(row: 1, column: 2, color: "#2a9d8f")
        ),
        as: UTF8.self
      ),
      ##"{"state":{"1-2":"#2a9d8f"}}"##
    )
  }

  @Test
  func presenceEncodesOnlyTheCanonicalColorField() throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    expectNoDifference(
      String(
        decoding: try encoder.encode(
          MergeTileGameV3Presence(userID: "session-metadata", color: "#e76f51")
        ),
        as: UTF8.self
      ),
      ##"{"color":"#e76f51"}"##
    )
  }

  @Test
  func sourcePortSelectsAnUntakenColorAndProjectsOnlyPeers() {
    let model = MergeTileGameV3Model(profileID: "local-session")
    model.updatePresence([
      MergeTileGameV3Presence(userID: "local-session", color: "#e76f51"),
      MergeTileGameV3Presence(userID: "remote-a", color: "#2a9d8f"),
      MergeTileGameV3Presence(userID: "remote-b", color: "#e9c46a"),
    ])

    expectNoDifference(model.peers.map(\.userID), ["remote-a", "remote-b"])
    expectNoDifference(model.availableColors.first, "#264653")
    expectNoDifference(model.selectedColor, "#264653")
  }

  @Test
  func resetReplacesTheWholeBoardWithTheCanonicalEmptyState() {
    var board = MergeTileGameV3Board.empty
    board.state["0-0"] = "#e76f51"
    board.reset()

    expectNoDifference(board, .empty)
  }
}
