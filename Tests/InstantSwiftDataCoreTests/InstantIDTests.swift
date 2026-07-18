import CustomDump
import Foundation
@testable import InstantSwiftDataCore
import Testing

@Suite
struct InstantIDTests {
  @Test
  func typedAndErasedIDsEncodeAsCanonicalStrings() throws {
    let encoder = JSONEncoder()

    expectNoDifference(
      String(decoding: try encoder.encode(InstantID<FixtureEntity>(rawValue: "typed-id")), as: UTF8.self),
      #""typed-id""#
    )
    expectNoDifference(
      String(decoding: try encoder.encode(AnyInstantID("erased-id")), as: UTF8.self),
      #""erased-id""#
    )
  }

  @Test
  func typedAndErasedIDsDecodeCanonicalAndLegacyShapes() throws {
    let decoder = JSONDecoder()

    expectNoDifference(
      try decoder.decode(InstantID<FixtureEntity>.self, from: Data(#""typed-id""#.utf8)),
      InstantID(rawValue: "typed-id")
    )
    expectNoDifference(
      try decoder.decode(
        InstantID<FixtureEntity>.self,
        from: Data(#"{"rawValue":"legacy-typed-id"}"#.utf8)
      ),
      InstantID(rawValue: "legacy-typed-id")
    )
    expectNoDifference(
      try decoder.decode(AnyInstantID.self, from: Data(#""erased-id""#.utf8)),
      AnyInstantID("erased-id")
    )
    expectNoDifference(
      try decoder.decode(
        AnyInstantID.self,
        from: Data(#"{"rawValue":"legacy-erased-id"}"#.utf8)
      ),
      AnyInstantID("legacy-erased-id")
    )
  }
}

private enum FixtureEntity {}
