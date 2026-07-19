import CustomDump
import Foundation
import InstantSwiftData
import InstantSwiftDataTesting
import PresenceRecipesV3App
import Testing

@Suite
struct InstantCustomCursorsV3LiveValidationTests {
  @Test
  func canonicalPresenceEvidenceEncodesNameBesideTheExactDynamicCursorShape() throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]

    expectNoDifference(
      String(
        decoding: try encoder.encode(InstantCustomCursorsV3LiveValidation.swiftPresence),
        as: UTF8.self
      ),
      ##"{"cursors-space-default--cursors-example-124":{"color":"#123456","x":150,"xPercent":25,"y":90,"yPercent":40},"name":"swift-custom-avatar"}"##
    )
    expectNoDifference(
      String(
        decoding: try encoder.encode(InstantCustomCursorsV3LiveValidation.typeScriptPresence),
        as: UTF8.self
      ),
      ##"{"cursors-space-default--cursors-example-124":{"color":"#654321","x":300,"xPercent":75,"y":200,"yPercent":60},"name":"typescript-custom-avatar"}"##
    )
  }

  @Test
  func evidencePreservesNamesExactCursorsAndCleanupCounts() throws {
    let details = InstantCustomCursorsV3LiveValidationDetails(
      roomType: "cursors-example",
      roomID: "124",
      spaceID: "cursors-space-default--cursors-example-124",
      publishedName: "swift-custom-avatar",
      publishedCursor: InstantCustomCursorsV3LiveValidation.swiftCursor,
      observedName: "typescript-custom-avatar",
      observedCursor: InstantCustomCursorsV3LiveValidation.typeScriptCursor,
      observedPeerID: "typescript-session",
      remoteCursorCount: 1,
      remoteCursorCountAfterClear: 0,
      remoteNamedPeerCountAfterClear: 1,
      remotePeerCountAfterDisconnect: 0,
      connectionState: "authenticated"
    )
    let encoded = try JSONEncoder().encode(details)
    expectNoDifference(
      try JSONDecoder().decode(
        InstantCustomCursorsV3LiveValidationDetails.self,
        from: encoded
      ),
      details
    )
  }

  @Test
  func remoteCountsExcludeLocalPeerAndDistinguishNameOnlyClearFromDisconnect() {
    let room = InstantRoomHandle(type: "cursors-example", id: "124")
    let local = member(
      room: room,
      userID: "swift-user",
      name: "swift-custom-avatar",
      cursor: InstantCustomCursorsV3LiveValidation.swiftCursor
    )
    let remote = member(
      room: room,
      userID: "typescript-user",
      name: "typescript-custom-avatar",
      cursor: InstantCustomCursorsV3LiveValidation.typeScriptCursor
    )
    let clearedRemote = member(
      room: room,
      userID: "typescript-user",
      name: "typescript-custom-avatar",
      cursor: nil
    )

    expectNoDifference(
      InstantCustomCursorsV3LiveValidation.remoteCursorCount(
        in: [local, remote],
        excludingUserID: "swift-user"
      ),
      1
    )
    expectNoDifference(
      InstantCustomCursorsV3LiveValidation.remoteCursorCount(
        in: [local, clearedRemote],
        excludingUserID: "swift-user"
      ),
      0
    )
    expectNoDifference(
      InstantCustomCursorsV3LiveValidation.remoteNamedPeerCount(
        in: [local, clearedRemote],
        excludingUserID: "swift-user"
      ),
      1
    )
    expectNoDifference(
      InstantCustomCursorsV3LiveValidation.remotePeerCount(
        in: [local],
        excludingUserID: "swift-user"
      ),
      0
    )
  }

  private func member(
    room: InstantRoomHandle,
    userID: String,
    name: String,
    cursor: CursorsV3Cursor?
  ) -> InstantRoomPresenceMember {
    var values: [String: JSONValue] = ["name": .string(name)]
    if let cursor {
      values[CustomCursorsV3Room.defaultSpaceID] = .object([
        "x": .number(cursor.x),
        "y": .number(cursor.y),
        "xPercent": .number(cursor.xPercent),
        "yPercent": .number(cursor.yPercent),
        "color": .string(cursor.color),
      ])
    }
    return InstantRoomPresenceMember(
      appID: "custom-cursors-app",
      room: room,
      userID: userID,
      values: values,
      updatedAt: InstantTimestamp(milliseconds: 1)
    )
  }
}
