import CustomDump
import Foundation
import PresenceRecipesV3App
import Testing

#if canImport(SwiftUI)
  import SwiftUI
#endif

// Canonical recipe source:
// upstream/instant/client/www/lib/recipes/cursors.tsx
//
// Canonical cursor behavior source:
// upstream/instant/client/packages/react/src/Cursors.tsx
@Suite
@MainActor
struct CursorsV3Tests {
  #if canImport(SwiftUI)
    @Test
    func desiredRoomPresenceSyntaxCompiles() {
      let screen: any View = CursorsV3Screen(roomID: "123")
      _ = screen

      expectNoDifference(CursorsV3Room.roomType, "cursors-example")
      expectNoDifference(CursorsV3Room.defaultRoomID, "123")
      expectNoDifference(
        CursorsV3Room.defaultSpaceID,
        "cursors-space-default--cursors-example-123"
      )
    }
  #endif

  @Test
  func publishedPresenceMatchesTheExactDynamicCursorShape() throws {
    let presence = CursorsV3Presence(
      userID: "session-metadata",
      cursor: CursorsV3Cursor(
        x: 150,
        y: 90,
        xPercent: 25,
        yPercent: 40,
        color: "#000fc7"
      )
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]

    expectNoDifference(
      String(decoding: try encoder.encode(presence), as: UTF8.self),
      ##"{"cursors-space-default--cursors-example-123":{"color":"#000fc7","x":150,"xPercent":25,"y":90,"yPercent":40}}"##
    )
  }

  @Test
  func sourcePortNormalizesAgainstTheContainerOriginAndSize() {
    let cursor = CursorsV3Model.cursor(
      clientX: 150,
      clientY: 90,
      frame: CursorsV3Frame(left: 100, top: 50, width: 200, height: 100),
      color: "#123456"
    )

    expectNoDifference(
      cursor,
      CursorsV3Cursor(
        x: 150,
        y: 90,
        xPercent: 25,
        yPercent: 40,
        color: "#123456"
      )
    )
  }

  @Test
  func sourcePortUsesTwoDigitDarkHexComponents() {
    expectNoDifference(
      CursorsV3Model.color(red: 0, green: 15, blue: 199),
      "#000fc7"
    )
  }

  @Test
  func sourcePortProjectsOnlyRemoteCursorsAndClearsTheLocalCursor() {
    let model = CursorsV3Model(profileID: "self-session", color: "#123456")
    model.updatePresence([
      CursorsV3Presence(
        userID: "self-session",
        cursor: CursorsV3Cursor(
          x: 1,
          y: 2,
          xPercent: 3,
          yPercent: 4,
          color: "#123456"
        )
      ),
      CursorsV3Presence(
        userID: "peer-session",
        cursor: CursorsV3Cursor(
          x: 5,
          y: 6,
          xPercent: 7,
          yPercent: 8,
          color: "#654321"
        )
      ),
      CursorsV3Presence(userID: "idle-peer", cursor: nil),
    ])

    expectNoDifference(model.peers.map(\.userID), ["peer-session"])
    model.clearPointer()
    expectNoDifference(model.presence.cursor, nil)
  }
}
