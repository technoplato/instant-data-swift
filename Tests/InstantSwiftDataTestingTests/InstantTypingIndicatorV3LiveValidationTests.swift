import CustomDump
import Foundation
import InstantSwiftDataCore
import InstantSwiftDataTesting
import Testing

@Suite
struct InstantTypingIndicatorV3LiveValidationTests {
  @Test
  func frameEvidenceEncodesAsPlainCanonicalJSON() throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let frames = InstantTypingIndicatorV3LiveValidation.frames(peerID: "swift-peer")
    let encoded = try frames.map {
      try #require(String(data: encoder.encode($0), encoding: .utf8))
    }

    expectNoDifference(encoded, [
      #"{"phase":"initial","presence":{"id":"swift-peer"}}"#,
      #"{"phase":"active","presence":{"chat-input":true,"id":"swift-peer"}}"#,
      #"{"phase":"inactive","presence":{"chat-input":false,"id":"swift-peer"}}"#,
      #"{"phase":"cleared","presence":{"chat-input":null,"id":"swift-peer"}}"#,
    ])
  }

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
    let details = InstantTypingIndicatorV3LiveValidationDetails(
      roomType: "typing-indicator-example",
      roomID: "1234",
      swiftUserID: "swift-user",
      typeScriptUserID: "typescript-user",
      publishedFrames: frames,
      observedFrames: frames,
      activePeerIDs: ["typescript-peer"],
      peerCountAfterDisconnect: 0,
      typeScriptPatchNormalizations: [],
      connectionState: "authenticated"
    )

    let encoded = try JSONEncoder().encode(details)
    let object = try #require(
      JSONSerialization.jsonObject(with: encoded) as? [String: Any]
    )
    let published = try #require(object["publishedFrames"] as? [[String: Any]])
    let initialPresence = try #require(published[0]["presence"] as? [String: Any])
    let activePresence = try #require(published[1]["presence"] as? [String: Any])
    let inactivePresence = try #require(published[2]["presence"] as? [String: Any])
    let clearedPresence = try #require(published[3]["presence"] as? [String: Any])
    expectNoDifference(initialPresence["id"] as? String, "swift-peer")
    expectNoDifference(activePresence["chat-input"] as? Bool, true)
    expectNoDifference(inactivePresence["chat-input"] as? Bool, false)
    #expect(clearedPresence["chat-input"] is NSNull)

    let decoded = try JSONDecoder().decode(
      InstantTypingIndicatorV3LiveValidationDetails.self,
      from: encoded
    )
    expectNoDifference(decoded, details)
    expectNoDifference(decoded.publishedFrames[0].presence, ["id": .string("swift-peer")])
    expectNoDifference(decoded.publishedFrames[1].presence["chat-input"], .bool(true))
    expectNoDifference(decoded.publishedFrames[2].presence["chat-input"], .bool(false))
    expectNoDifference(decoded.publishedFrames[3].presence["chat-input"], .null)
    expectNoDifference(decoded.observedFrames[3].presence["chat-input"], .null)
    expectNoDifference(decoded.activePeerIDs, ["typescript-peer"])
    expectNoDifference(decoded.peerCountAfterDisconnect, 0)
    expectNoDifference(
      decoded.typeScriptPatchNormalizations,
      []
    )
  }
}
