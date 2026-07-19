import CustomDump
import Foundation
import InstantSwiftData
import InstantSwiftDataTesting
import Testing

@Suite
struct InstantAvatarStackV3LiveValidationTests {
  @Test
  func canonicalPresenceEvidenceEncodesNameOnly() throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]

    expectNoDifference(
      String(
        decoding: try encoder.encode(InstantAvatarStackV3LiveValidation.swiftPresence),
        as: UTF8.self
      ),
      #"{"name":"abcdef"}"#
    )
    expectNoDifference(
      String(
        decoding: try encoder.encode(InstantAvatarStackV3LiveValidation.typeScriptPresence),
        as: UTF8.self
      ),
      #"{"name":"uvwxyz"}"#
    )
  }

  @Test
  func evidencePreservesPeerMetadataAndDisconnectCleanup() throws {
    let details = InstantAvatarStackV3LiveValidationDetails(
      roomType: "avatars-example",
      roomID: "avatars-example-1234",
      publishedPresence: InstantAvatarStackV3LiveValidation.swiftPresence,
      observedPresence: InstantAvatarStackV3LiveValidation.typeScriptPresence,
      observedPeerID: "typescript-session",
      peerCount: 1,
      peerCountAfterDisconnect: 0,
      connectionState: "authenticated"
    )
    let encoded = try JSONEncoder().encode(details)
    expectNoDifference(
      try JSONDecoder().decode(InstantAvatarStackV3LiveValidationDetails.self, from: encoded),
      details
    )
  }

  @Test
  func remotePeerCountExcludesTheLocalCanonicalPresence() {
    let room = InstantRoomHandle(type: "avatars-example", id: "avatars-example-1234")
    let local = InstantRoomPresenceMember(
      appID: "avatar-stack-app",
      room: room,
      userID: "swift-session",
      values: ["name": .string("abcdef")],
      updatedAt: InstantTimestamp(milliseconds: 1)
    )
    let remote = InstantRoomPresenceMember(
      appID: "avatar-stack-app",
      room: room,
      userID: "typescript-session",
      values: ["name": .string("uvwxyz")],
      updatedAt: InstantTimestamp(milliseconds: 2)
    )

    expectNoDifference(
      InstantAvatarStackV3LiveValidation.remotePeerCount(
        in: [local, remote],
        excludingName: "abcdef"
      ),
      1
    )
    expectNoDifference(
      InstantAvatarStackV3LiveValidation.remotePeerCount(
        in: [local],
        excludingName: "abcdef"
      ),
      0
    )
  }
}
