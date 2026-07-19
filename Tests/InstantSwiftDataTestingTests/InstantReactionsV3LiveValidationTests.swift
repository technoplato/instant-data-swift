import CustomDump
import Foundation
import InstantSwiftDataTesting
import Testing

@Suite
struct InstantReactionsV3LiveValidationTests {
  @Test
  func exactCanonicalPayloadsEncodeAsPlainJSON() throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]

    expectNoDifference(
      String(
        decoding: try encoder.encode(InstantReactionsV3LiveValidation.swiftPayload),
        as: UTF8.self
      ),
      #"{"directionAngle":45,"name":"heart","rotationAngle":270}"#
    )
    expectNoDifference(
      String(
        decoding: try encoder.encode(InstantReactionsV3LiveValidation.typeScriptPayload),
        as: UTF8.self
      ),
      #"{"directionAngle":90,"name":"wave","rotationAngle":180}"#
    )
  }

  @Test
  func evidencePreservesBothDirectionsAndInvalidNameFiltering() throws {
    let details = InstantReactionsV3LiveValidationDetails(
      roomType: "topics-example",
      roomID: "123",
      topic: "emoji",
      publishedPayload: InstantReactionsV3LiveValidation.swiftPayload,
      observedPayload: InstantReactionsV3LiveValidation.typeScriptPayload,
      ignoredInvalidName: "sparkle",
      connectionState: "authenticated"
    )

    let encoded = try JSONEncoder().encode(details)
    let decoded = try JSONDecoder().decode(
      InstantReactionsV3LiveValidationDetails.self,
      from: encoded
    )

    expectNoDifference(decoded, details)
    expectNoDifference(decoded.roomType, "topics-example")
    expectNoDifference(decoded.roomID, "123")
    expectNoDifference(decoded.topic, "emoji")
    expectNoDifference(decoded.publishedPayload.name, "heart")
    expectNoDifference(decoded.observedPayload.name, "wave")
    expectNoDifference(decoded.ignoredInvalidName, "sparkle")
  }
}
