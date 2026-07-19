import CustomDump
import Foundation
import InstantSwiftDataCore
import InstantSwiftDataTesting
import Testing

@Suite
struct InstantTypingIndicatorV3LiveValidationTests {
  @Test
  func evidencePreservesAbsentBooleanAndNullFramesExactly() throws {
    let frames = [
      InstantTypingIndicatorPresenceFrame(
        phase: "initial",
        presence: ["id": .string("swift-peer")]
      ),
      InstantTypingIndicatorPresenceFrame(
        phase: "active",
        presence: ["id": .string("swift-peer"), "chat-input": .bool(true)]
      ),
      InstantTypingIndicatorPresenceFrame(
        phase: "inactive",
        presence: ["id": .string("swift-peer"), "chat-input": .bool(false)]
      ),
      InstantTypingIndicatorPresenceFrame(
        phase: "cleared",
        presence: ["id": .string("swift-peer"), "chat-input": .null]
      ),
    ]
    let observedFrames = Array(frames.dropLast()) + [
      InstantTypingIndicatorPresenceFrame(
        phase: "cleared",
        presence: ["id": .string("swift-peer")]
      )
    ]
    let details = InstantTypingIndicatorV3LiveValidationDetails(
      roomType: "typing-indicator-example",
      roomID: "1234",
      swiftUserID: "swift-user",
      typeScriptUserID: "typescript-user",
      publishedFrames: frames,
      observedFrames: observedFrames,
      activePeerIDs: ["typescript-peer"],
      peerCountAfterDisconnect: 0,
      typeScriptPatchNormalizations: ["chat-input:null-to-absent"],
      connectionState: "authenticated"
    )

    let decoded = try JSONDecoder().decode(
      InstantTypingIndicatorV3LiveValidationDetails.self,
      from: JSONEncoder().encode(details)
    )
    expectNoDifference(decoded, details)
    expectNoDifference(decoded.publishedFrames[0].presence, ["id": .string("swift-peer")])
    expectNoDifference(decoded.publishedFrames[1].presence["chat-input"], .bool(true))
    expectNoDifference(decoded.publishedFrames[2].presence["chat-input"], .bool(false))
    expectNoDifference(decoded.publishedFrames[3].presence["chat-input"], .null)
    expectNoDifference(decoded.observedFrames[3].presence, ["id": .string("swift-peer")])
    expectNoDifference(decoded.activePeerIDs, ["typescript-peer"])
    expectNoDifference(decoded.peerCountAfterDisconnect, 0)
    expectNoDifference(
      decoded.typeScriptPatchNormalizations,
      ["chat-input:null-to-absent"]
    )
  }
}
