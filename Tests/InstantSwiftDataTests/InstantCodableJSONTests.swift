import Foundation
import InstantSwiftData
import InstantSwiftDataCore
import Testing

private struct Word: Codable, Equatable, Sendable {
  var text: String
  var start: Double
  var end: Double
}

@Suite struct InstantCodableJSONTests {
  @Test func jsonRepresentationRoundTrip() throws {
    let words = [
      Word(text: "hello", start: 0, end: 0.4),
      Word(text: "world", start: 0.4, end: 0.9),
    ]
    let encoded = try [Word].JSONRepresentation(queryOutput: words)
    guard case let .json(json) = encoded.instantValue else {
      Issue.record("expected InstantValue.json")
      return
    }
    let decodedArray = try InstantCodableJSON.decode([Word].self, from: json)
    #expect(decodedArray == words)
  }

  @Test func jsonStringRepresentationRoundTrip() throws {
    let words = [Word(text: "a", start: 0, end: 0.1)]
    let encoded = try [Word].JSONStringRepresentation(queryOutput: words)
    guard case let .string(text) = encoded.instantValue else {
      Issue.record("expected InstantValue.string")
      return
    }
    #expect(text.contains("\"text\":\"a\""))
    let decoded = try InstantCodableJSON.decodeFlexible(
      [Word].self,
      from: .string(text)
    )
    #expect(decoded == words)
  }

  @Test func decodeFlexibleAcceptsJSONAndString() throws {
    let words = [Word(text: "x", start: 1, end: 2)]
    let asJSON = try InstantCodableJSON.encode(words)
    let asText = String(
      data: try JSONEncoder().encode(words),
      encoding: .utf8
    )!
    let fromJSON = try InstantCodableJSON.decodeFlexible(
      [Word].self,
      from: .json(asJSON)
    )
    let fromString = try InstantCodableJSON.decodeFlexible(
      [Word].self,
      from: .string(asText)
    )
    #expect(fromJSON == words)
    #expect(fromString == words)
  }

  @Test func decodeFailureIsLoud() {
    #expect(throws: InstantError.self) {
      try InstantCodableJSON.decodeFlexible(
        [Word].self,
        from: .string("not-json")
      )
    }
    #expect(throws: InstantError.self) {
      try InstantCodableJSON.decodeFlexible(
        [Word].self,
        from: .number(3)
      )
    }
  }

  @Test func representationInstantValueMatchesEncode() throws {
    let words = [Word(text: "y", start: 0, end: 1)]
    let rep = try [Word].JSONRepresentation(queryOutput: words)
    let encoded = try InstantCodableJSON.encode(words)
    #expect(rep.instantValue == InstantValue.json(encoded))
  }
}
