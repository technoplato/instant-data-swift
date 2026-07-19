import CustomDump
import Foundation
import PresenceRecipesV3App
import Testing

#if canImport(SwiftUI)
  import SwiftUI
#endif

// Canonical recipe source:
// upstream/instant/client/www/lib/recipes/custom-cursors.tsx
//
// Canonical cursor behavior source:
// upstream/instant/client/packages/react/src/Cursors.tsx
@Suite
@MainActor
struct CustomCursorsV3Tests {
  #if canImport(SwiftUI)
    @Test
    func desiredRoomPresenceAndCustomRenderingSyntaxCompiles() {
      let screen: any View = CustomCursorsV3Screen(
        roomID: "124",
        profileID: "local-session",
        name: "custom-avatar-name",
        color: "#123456"
      )
      _ = screen

      expectNoDifference(CustomCursorsV3Room.roomType, "cursors-example")
      expectNoDifference(CustomCursorsV3Room.defaultRoomID, "124")
      expectNoDifference(
        CustomCursorsV3Room.defaultSpaceID,
        "cursors-space-default--cursors-example-124"
      )
    }
  #endif

  @Test
  func publishedPresenceMatchesNamePlusExactDynamicCursorShape() throws {
    let presence = CustomCursorsV3Presence(
      userID: "session-metadata",
      name: "custom-avatar-name",
      cursor: CursorsV3Cursor(
        x: 150,
        y: 90,
        xPercent: 25,
        yPercent: 40,
        color: "#123456"
      )
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]

    expectNoDifference(
      String(decoding: try encoder.encode(presence), as: UTF8.self),
      ##"{"cursors-space-default--cursors-example-124":{"color":"#123456","x":150,"xPercent":25,"y":90,"yPercent":40},"name":"custom-avatar-name"}"##
    )
  }

  @Test
  func clearingTheCursorRetainsTheNamePresenceUsedByCustomRendering() throws {
    let model = CustomCursorsV3Model(
      profileID: "local-session",
      name: "custom-avatar-name",
      color: "#123456"
    )
    model.movePointer(
      clientX: 150,
      clientY: 90,
      frame: CursorsV3Frame(left: 100, top: 50, width: 200, height: 100)
    )
    model.clearPointer()

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    expectNoDifference(
      String(decoding: try encoder.encode(model.presence), as: UTF8.self),
      #"{"name":"custom-avatar-name"}"#
    )
  }

  @Test
  func sourcePortProjectsOnlyRemoteNamedPeersWithActiveCursors() {
    let model = CustomCursorsV3Model(
      profileID: "local-session",
      name: "local-avatar",
      color: "#123456"
    )
    model.updatePresence([
      CustomCursorsV3Presence(
        userID: "local-session",
        name: "local-avatar",
        cursor: cursor(x: 1, color: "#123456")
      ),
      CustomCursorsV3Presence(
        userID: "remote-session",
        name: "remote-avatar",
        cursor: cursor(x: 2, color: "#654321")
      ),
      CustomCursorsV3Presence(
        userID: "idle-session",
        name: "idle-avatar",
        cursor: nil
      ),
    ])

    expectNoDifference(model.peers.map(\.userID), ["remote-session"])
    expectNoDifference(model.peers.map(\.name), ["remote-avatar"])
  }

  private func cursor(x: Double, color: String) -> CursorsV3Cursor {
    CursorsV3Cursor(
      x: x,
      y: x,
      xPercent: x,
      yPercent: x,
      color: color
    )
  }
}
