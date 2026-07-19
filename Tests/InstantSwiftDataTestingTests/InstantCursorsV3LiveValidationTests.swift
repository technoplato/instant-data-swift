import CustomDump
import Foundation
import InstantSwiftData
import InstantSwiftDataTesting
import PresenceRecipesV3App
import Testing

@Suite
struct InstantCursorsV3LiveValidationTests {
  @Test
  func canonicalPresenceEvidenceEncodesTheExactDynamicCursorShape() throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]

    expectNoDifference(
      String(
        decoding: try encoder.encode(InstantCursorsV3LiveValidation.swiftPresence),
        as: UTF8.self
      ),
      ##"{"cursors-space-default--cursors-example-123":{"color":"#123456","x":150,"xPercent":25,"y":90,"yPercent":40}}"##
    )
    expectNoDifference(
      String(
        decoding: try encoder.encode(InstantCursorsV3LiveValidation.typeScriptPresence),
        as: UTF8.self
      ),
      ##"{"cursors-space-default--cursors-example-123":{"color":"#654321","x":300,"xPercent":75,"y":200,"yPercent":60}}"##
    )
  }

  @Test
  func evidencePreservesExactCursorAndCleanupCounts() throws {
    let details = InstantCursorsV3LiveValidationDetails(
      roomType: "cursors-example",
      roomID: "123",
      spaceID: "cursors-space-default--cursors-example-123",
      publishedCursor: InstantCursorsV3LiveValidation.swiftCursor,
      observedCursor: InstantCursorsV3LiveValidation.typeScriptCursor,
      observedPeerID: "typescript-session",
      remoteCursorCount: 1,
      remoteCursorCountAfterClear: 0,
      remotePeerCountAfterDisconnect: 0,
      connectionState: "authenticated"
    )
    let encoded = try JSONEncoder().encode(details)
    expectNoDifference(
      try JSONDecoder().decode(InstantCursorsV3LiveValidationDetails.self, from: encoded),
      details
    )
  }

  @Test
  func remoteCountsExcludeTheLocalPeerAndDistinguishClearFromDisconnect() {
    let room = InstantRoomHandle(type: "cursors-example", id: "123")
    let local = member(
      room: room,
      userID: "swift-user",
      cursor: InstantCursorsV3LiveValidation.swiftCursor
    )
    let remote = member(
      room: room,
      userID: "typescript-user",
      cursor: InstantCursorsV3LiveValidation.typeScriptCursor
    )
    let clearedRemote = member(room: room, userID: "typescript-user", cursor: nil)

    expectNoDifference(
      InstantCursorsV3LiveValidation.remoteCursorCount(
        in: [local, remote],
        excludingUserID: "swift-user"
      ),
      1
    )
    expectNoDifference(
      InstantCursorsV3LiveValidation.remoteCursorCount(
        in: [local, clearedRemote],
        excludingUserID: "swift-user"
      ),
      0
    )
    expectNoDifference(
      InstantCursorsV3LiveValidation.remotePeerCount(
        in: [local],
        excludingUserID: "swift-user"
      ),
      0
    )
  }

  private func member(
    room: InstantRoomHandle,
    userID: String,
    cursor: CursorsV3Cursor?
  ) -> InstantRoomPresenceMember {
    let values: [String: JSONValue]
    if let cursor {
      values = [
        CursorsV3Room.defaultSpaceID: .object([
          "x": .number(cursor.x),
          "y": .number(cursor.y),
          "xPercent": .number(cursor.xPercent),
          "yPercent": .number(cursor.yPercent),
          "color": .string(cursor.color),
        ])
      ]
    } else {
      values = [:]
    }
    return InstantRoomPresenceMember(
      appID: "cursors-app",
      room: room,
      userID: userID,
      values: values,
      updatedAt: InstantTimestamp(milliseconds: 1)
    )
  }
}
