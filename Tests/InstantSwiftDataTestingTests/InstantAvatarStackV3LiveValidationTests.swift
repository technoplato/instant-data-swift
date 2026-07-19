import CustomDump
import Foundation
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
    let decoded = try JSONDecoder().decode(
      InstantAvatarStackV3LiveValidationDetails.self,
      from: encoded
    )
    expectNoDifference(decoded.publishedPresence.name, "abcdef")
    expectNoDifference(decoded.publishedPresence.userID, "")
    expectNoDifference(decoded.observedPresence.name, "uvwxyz")
    expectNoDifference(decoded.observedPresence.userID, "")
    expectNoDifference(decoded.observedPeerID, "typescript-session")
    expectNoDifference(decoded.peerCountAfterDisconnect, 0)
  }
}
