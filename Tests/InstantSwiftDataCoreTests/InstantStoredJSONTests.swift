import CustomDump
import Foundation
import Testing

@testable import InstantSwiftDataCore

/// #1007: every fact a write stores encoded its value and itself with `JSONEncoder`, two encoder runs per fact and 5%
/// of a write replay's CPU. A lookup compares the stored text byte for byte with the text an earlier version stored, so
/// the store must keep writing exactly `JSONEncoder`'s text.
@Suite
struct InstantStoredJSONTests {
  /// The store keeps exactly `JSONEncoder`'s text for random values and facts, unusual strings and numbers included.
  @Test(arguments: [UInt64(81_007), 81_008, 81_009, 81_010])
  func theStoredTextIsJSONEncodersText(seed: UInt64) throws {
    var random = InfiniteWindowRandom(seed: seed)
    for step in 0..<3_000 {
      let value = Self.randomValue(&random, depth: 0)
      expectNoDifference(
        try InstantStoredJSON.stored(value, using: Self.encoder),
        String(decoding: try Self.encoder.encode(value), as: UTF8.self),
        "step \(step)"
      )
      let triple = InstantTriple(
        entityID: Self.randomString(&random),
        attributeID: "segments/" + Self.randomString(&random),
        value: value,
        txID: random.chance(50) ? String(random.int(0...99_999)) : Self.randomString(&random),
        txTime: InstantTimestamp(milliseconds: Int64(random.int(-1_000...1_000)) * 1_790_700_000_123)
      )
      let expectedTriple = String(decoding: try Self.encoder.encode(triple), as: UTF8.self)
      expectNoDifference(try InstantStoredJSON.stored(triple, using: Self.encoder), expectedTriple, "step \(step)")
      let texts = try InstantStoredJSON.storedTexts(triple, using: Self.encoder)
      expectNoDifference(texts.value, String(decoding: try Self.encoder.encode(value), as: UTF8.self), "step \(step)")
      expectNoDifference(texts.triple, expectedTriple, "step \(step)")
    }
  }

  /// A number `JSONEncoder` refuses is refused, in a value and in a fact.
  @Test
  func aNumberJSONEncoderRefusesIsRefused() {
    for number in [Double.nan, .infinity, -.infinity] {
      #expect(throws: EncodingError.self) { try InstantStoredJSON.stored(.number(number), using: Self.encoder) }
      let triple = InstantTriple(
        entityID: "e",
        attributeID: "a",
        value: .number(number),
        txID: "1",
        txTime: InstantTimestamp(milliseconds: 1)
      )
      #expect(throws: EncodingError.self) { try InstantStoredJSON.stored(triple, using: Self.encoder) }
      #expect(throws: EncodingError.self) { try InstantStoredJSON.storedTexts(triple, using: Self.encoder) }
    }
  }

  /// A transcript line's facts are written without `JSONEncoder` (#1007). It ran twice for every fact a write stores,
  /// and in a Time Profiler trace of a release build of the write replay nine tenths of its time under the store's fact
  /// insert went to its containers, type casts, metadata lookups and allocations, not to the text.
  @Test
  func aLinesFactsAreWrittenWithoutJSONEncoder() throws {
    let encoder = CountingJSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    for triple in Self.lineFacts() {
      let texts = try InstantStoredJSON.storedTexts(triple, using: encoder)
      expectNoDifference(texts.value, String(decoding: try Self.encoder.encode(triple.value), as: UTF8.self))
      expectNoDifference(texts.triple, String(decoding: try Self.encoder.encode(triple), as: UTF8.self))
      _ = try InstantStoredJSON.stored(triple.value, using: encoder)
      _ = try InstantStoredJSON.stored(triple, using: encoder)
    }
    expectNoDifference(encoder.encodeCount, 0)
  }

  // MARK: - Helpers

  /// Counts the values it is asked to encode.
  final class CountingJSONEncoder: JSONEncoder, @unchecked Sendable {
    var encodeCount = 0

    override func encode<T: Encodable>(_ value: T) throws -> Data {
      encodeCount += 1
      return try super.encode(value)
    }
  }

  static let encoder: JSONEncoder = {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    return encoder
  }()

  /// One transcript line's facts as the consuming app writes them: ids, times, its text and its words as JSON.
  static func lineFacts() -> [InstantTriple] {
    let line = "4f0c8a52-3b1e-4c8e-9a6f-0d2c7b9e1a33"
    let words = (0..<24).map { index in
      #"{"text":"word\#(index)","start":\#(Double(index) * 0.42),"end":\#(Double(index) * 0.42 + 0.31),"isFinal":true}"#
    }
    let values: [(String, InstantValue)] = [
      ("id", .string(line)),
      ("recordingID", .string("9b7a1e40-5c2d-4f6b-8e3a-2d1c0b9a8f77")),
      ("segmentIndex", .number(412)),
      ("startTimeSeconds", .number(1_284.37)),
      ("endTimeSeconds", .number(1_296.12)),
      ("text", .string("So the goal, and add this to the notes: the recording screen should stay cool while it records.")),
      ("wordsJSON", .string("[" + words.joined(separator: ",") + "]")),
      ("isFinal", .bool(true)),
      ("updatedAtMs", .number(1_792_796_244_634)),
      ("recording", .ref("9b7a1e40-5c2d-4f6b-8e3a-2d1c0b9a8f77")),
    ]
    return values.map { name, value in
      InstantTriple(
        entityID: line,
        attributeID: "transcriptionSegments/\(name)",
        value: value,
        txID: "tx-412",
        txTime: InstantTimestamp(milliseconds: 1_792_796_244_634)
      )
    }
  }

  /// Characters `JSONEncoder` escapes, characters it copies, and characters whose bytes are easy to get wrong.
  static let characters: [String] = [
    "a", "Z", "0", " ", "-", ":", "\"", "\\", "/", "\u{00}", "\u{07}", "\u{08}", "\t", "\n", "\u{0B}", "\u{0C}",
    "\r", "\u{1B}", "\u{1F}", "\u{7F}", "\u{80}", "\u{E9}", "e\u{301}", "\u{2028}", "\u{2029}", "\u{FEFF}",
    "\u{4E2D}", "\u{1F600}", "\u{1F469}\u{200D}\u{1F4BB}", "{", "}", "[", "]", ",",
  ]

  static func randomString(_ random: inout InfiniteWindowRandom) -> String {
    let length = random.chance(10) ? 0 : random.int(1...24)
    return (0..<length).map { _ in characters[random.int(0...characters.count - 1)] }.joined()
  }

  static func randomNumber(_ random: inout InfiniteWindowRandom) -> Double {
    switch random.int(0...9) {
    case 0: return Double(random.int(-1_000...1_000))
    case 1: return [0.0, -0.0, 0.1, 0.5, 1.0 / 3.0, 2.0 / 3.0, 1e-7, 1e-6, 1e-5, 1e-4][random.int(0...9)]
    case 2: return Double(sign: random.chance(50) ? .plus : .minus, exponent: random.int(-1_074...1_023), significand: 1)
    case 3: return [9_007_199_254_740_992, 9_007_199_254_740_993, 1e15, 1e16, 1e17, 1e21, 1e22, 1e23][random.int(0...7)]
    case 4: return [.leastNonzeroMagnitude, .leastNormalMagnitude, .greatestFiniteMagnitude, -.greatestFiniteMagnitude][random.int(0...3)]
    case 5: return Double(random.int(0...2_000_000_000)) * 1_000 + Double(random.int(0...999))
    case 6: return Double(random.int(-100_000...100_000)) / 100
    default:
      while true {
        let number = Double(bitPattern: random.next())
        if number.isFinite { return number }
      }
    }
  }

  static func randomJSON(_ random: inout InfiniteWindowRandom, depth: Int) -> JSONValue {
    switch random.int(0...(depth < 3 ? 5 : 3)) {
    case 0: return .null
    case 1: return .bool(random.chance(50))
    case 2: return .number(randomNumber(&random))
    case 3: return .string(randomString(&random))
    case 4: return .array((0..<random.int(0...3)).map { _ in randomJSON(&random, depth: depth + 1) })
    default:
      var object: [String: JSONValue] = [:]
      for _ in 0..<random.int(0...3) { object[randomString(&random)] = randomJSON(&random, depth: depth + 1) }
      return .object(object)
    }
  }

  static func randomValue(_ random: inout InfiniteWindowRandom, depth: Int) -> InstantValue {
    switch random.int(0...9) {
    case 0: return .null
    case 1, 2: return .string(randomString(&random))
    case 3, 4: return .number(randomNumber(&random))
    case 5: return .bool(random.chance(50))
    case 6: return .ref(randomString(&random))
    case 7: return .date(Date(timeIntervalSinceReferenceDate: randomNumber(&random)))
    case 8: return .json(randomJSON(&random, depth: depth))
    default:
      return .lookupRef(InstantLookupRef(attributeID: randomString(&random), value: .string(randomString(&random))))
    }
  }
}
