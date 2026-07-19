import CustomDump
import Foundation
import PresenceRecipesV3App
import Testing

#if canImport(SwiftUI)
  import SwiftUI
#endif

// Canonical implementation source:
// upstream/instant/client/www/lib/recipes/avatar-stack.tsx
//
// Canonical presence lifecycle sources:
// upstream/instant/client/packages/react-common/src/InstantReactRoom.ts
// upstream/instant/client/packages/vue/src/tests/InstantVueDatabase.test.ts
@Suite
@MainActor
struct AvatarStackV3Tests {
  #if canImport(SwiftUI)
    @Test
    func desiredRoomPresenceSyntaxCompiles() {
      let screen: any View = AvatarStackV3Screen(
        roomID: "avatars-example-1234",
        profileID: "abcdef123456"
      )
      _ = screen

      expectNoDifference(AvatarStackV3Room.roomType, "avatars-example")
      expectNoDifference(AvatarStackV3Room.defaultRoomID, "avatars-example-1234")
    }
  #endif

  @Test
  func publishedPresenceMatchesCanonicalNameOnlyShape() throws {
    let presence = AvatarStackV3Presence(
      userID: "peer-session-metadata",
      name: "abcdef"
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]

    expectNoDifference(
      String(decoding: try encoder.encode(presence), as: UTF8.self),
      #"{"name":"abcdef"}"#
    )
  }

  @Test
  func sourcePortUsesFirstSixUserIDCharactersAsTheDefaultName() {
    expectNoDifference(
      AvatarStackV3Model.defaultName(profileID: "abcdef123456"),
      "abcdef"
    )
    expectNoDifference(
      AvatarStackV3Model.defaultName(profileID: "tiny"),
      "tiny"
    )
  }

  @Test
  func sourcePortProjectsCurrentUserPeersAndOnlineCount() {
    let model = AvatarStackV3Model(profileID: "self-session")
    model.updatePresence([
      AvatarStackV3Presence(userID: "peer-b", name: "Betty"),
      AvatarStackV3Presence(userID: "self-session", name: "self-s"),
      AvatarStackV3Presence(userID: "peer-a", name: "Alice"),
    ])

    expectNoDifference(model.currentUser?.name, "self-s")
    expectNoDifference(model.peers.map(\.userID), ["peer-b", "peer-a"])
    expectNoDifference(model.peers.map(\.name), ["Betty", "Alice"])
    expectNoDifference(model.onlineCount, 3)
  }

  @Test
  func sourcePortCountsTheLocalUserEvenBeforeItsEchoArrives() {
    let model = AvatarStackV3Model(profileID: "self-session")
    model.updatePresence([
      AvatarStackV3Presence(userID: "peer-a", name: "Alice"),
      AvatarStackV3Presence(userID: "peer-b", name: "Betty"),
    ])

    expectNoDifference(model.currentUser?.name, "self-s")
    expectNoDifference(model.peers.map(\.name), ["Alice", "Betty"])
    expectNoDifference(model.onlineCount, 3)
  }
}
