import CustomDump
import Darwin
import Foundation
import Testing

@testable import InstantSwiftDataCore

/// #1007: a received frame was decoded through `JSONDecoder` into ``InstantLiveJSONValue``, whose decoder tried each JSON
/// kind in turn; each miss threw a `DecodingError` that recorded its coding path: three for every object, two for every
/// array, one for every number. A server result restates every triple of each query it refreshes, so one frame threw
/// thousands of errors, and decoding frames cost 3% of one core on a device while recording. A frame now decodes to
/// exactly what `JSONDecoder` decodes, without the errors.
@Suite
struct InstantLiveFrameDecodeTests {
  /// A server result restating 64 lines of 16 facts decodes at under a third of `JSONDecoder`'s cost.
  @Test
  func aServerResultDecodesAtAFractionOfJSONDecodersCost() throws {
    let frame = try JSONEncoder().encode(Self.refreshOK(lineCount: 64))
    let expected = try JSONDecoder().decode(InstantLiveMessage.self, from: frame)
    expectNoDifference(try InstantLiveMessage.decoded(fromFrame: frame), expected)
    let decoded = try Self.threadCPUNanoseconds {
      for _ in 0..<20 { _ = try InstantLiveMessage.decoded(fromFrame: frame) }
    }
    let decodedByJSONDecoder = try Self.threadCPUNanoseconds {
      for _ in 0..<20 { _ = try JSONDecoder().decode(InstantLiveMessage.self, from: frame) }
    }
    let ratio = Double(decoded) / Double(max(decodedByJSONDecoder, 1))
    print("frame of \(frame.count) bytes: decoded at \(ratio) times JSONDecoder's thread CPU")
    #expect(ratio < 0.33, "decoding the frame cost \(ratio) times JSONDecoder's")
  }

  /// A frame of any shape decodes to what `JSONDecoder` decodes from the same bytes, as data and as text: nested
  /// objects and arrays, every number form, strings with every escape and with characters outside the BMP, whitespace.
  @Test(arguments: [UInt64(61_007), 61_008, 61_009, 61_010, 61_011, 61_012])
  func aFrameDecodesToWhatJSONDecoderDecodes(seed: UInt64) throws {
    var random = InfiniteWindowRandom(seed: seed)
    for frameIndex in 0..<60 {
      var text = "{"
      text += Self.space(&random) + "\"op\"" + Self.space(&random) + ":" + Self.space(&random)
      text += Self.randomString(&random, value: ["refresh-ok", "add-query-ok", "transact-ok", "error"][random.int(0...3)])
      switch random.int(0...2) {
      case 0:
        text += ",\"client-event-id\":" + Self.randomString(&random, value: "event-\(frameIndex)")
      case 1:
        text += ",\"client-event-id\":null"
      default:
        break
      }
      for fieldIndex in 0..<random.int(0...4) {
        text += "," + Self.space(&random) + Self.randomString(&random, value: "field-\(fieldIndex)") + ":"
        text += Self.space(&random) + Self.randomJSON(&random, depth: 0) + Self.space(&random)
      }
      text += "}" + Self.space(&random)
      let data = Data(text.utf8)
      let expected = try JSONDecoder().decode(InstantLiveMessage.self, from: data)
      expectNoDifference(try InstantLiveMessage.decoded(fromFrame: data), expected, "seed \(seed) frame \(text)")
      expectNoDifference(try InstantLiveMessage.decoded(fromFrame: text), expected, "seed \(seed) frame \(text)")
    }
  }

  /// A malformed or unusual frame has the outcome `JSONDecoder` gives it: the same message, or an error. (`JSONDecoder`
  /// takes a trailing comma, for one.)
  @Test
  func anUnusualFrameHasTheOutcomeJSONDecoderGivesIt() {
    let frames = [
      "", "{", "[]", "{\"op\":1}", "{\"client-event-id\":\"e\"}", "{\"op\":\"x\",\"client-event-id\":7}",
      "{\"op\":\"x\",\"f\":01}", "{\"op\":\"x\",\"f\":1.}", "{\"op\":\"x\",\"f\":.5}", "{\"op\":\"x\",\"f\":-}",
      "{\"op\":\"x\",\"f\":+1}", "{\"op\":\"x\",\"f\":[1,]}", "{\"op\":\"x\",\"f\":{\"a\":1,}}",
      "{\"op\":\"x\",\"f\":\"\\x\"}", "{\"op\":\"x\",\"f\":\"\u{01}\"}", "{\"op\":\"x\",\"f\":[1}",
      "{\"op\":\"x\",\"f\":tru}", "{\"op\":\"x\",\"f\":nul}", "{\"op\":\"x\"} 2", "{\"op\":\"x\",\"f\":1e400}",
      "{\"op\":\"x\",\"f\":1e-400}", "{\"op\":\"x\",\"f\":\"\\uD800\"}", "{\"op\":\"x\",\"f\":\"\\uDC00x\"}",
      "{\"op\":\"x\",\"f\":\"\\u12\"}", "{'op':\"x\"}", "{\"op\":\"x\",}", "{\"op\":\"x\",\"f\":1,\"f\":2}",
      "\u{FEFF}{\"op\":\"x\"}", "{\"op\":\"x\",\"f\":" + String(repeating: "[", count: 40) + String(repeating: "]", count: 40) + "}",
    ]
    var invalidUTF8 = Data("{\"op\":\"x\",\"f\":\"".utf8)
    invalidUTF8.append(contentsOf: [0xC3, 0x28])
    invalidUTF8.append(contentsOf: Data("\"}".utf8))
    for data in (frames.map { Data($0.utf8) } + [invalidUTF8]) {
      let label = String(decoding: data, as: UTF8.self)
      let expected = Result { try JSONDecoder().decode(InstantLiveMessage.self, from: data) }
      let decoded = Result { try InstantLiveMessage.decoded(fromFrame: data) }
      switch (expected, decoded) {
      case let (.success(expectedMessage), .success(message)):
        expectNoDifference(message, expectedMessage, "\(label)")
      case (.failure, .failure):
        break
      default:
        Issue.record("\(label): JSONDecoder gave \(expected), the frame decoder \(decoded)")
      }
      if let text = String(data: data, encoding: .utf8) {
        let decodedText = Result { try InstantLiveMessage.decoded(fromFrame: text) }
        switch (expected, decodedText) {
        case let (.success(expectedMessage), .success(message)):
          expectNoDifference(message, expectedMessage, "\(label)")
        case (.failure, .failure):
          break
        default:
          Issue.record("\(label) as text: JSONDecoder gave \(expected), the frame decoder \(decodedText)")
        }
      }
    }
  }

  // MARK: - Helpers

  /// A `refresh-ok` restating `lineCount` lines of one recording, each as 16 facts, as the server sends a window.
  static func refreshOK(lineCount: Int) -> InstantLiveMessage {
    let attributes = (0..<16).map { "attr-segment-\($0)" }
    var rows: [InstantLiveJSONValue] = []
    for line in 0..<lineCount {
      let entityID = InstantManyCardinalitySortCostTests.uuidString(seed: 3, index: line)
      var triples: [InstantLiveJSONValue] = []
      for (index, attribute) in attributes.enumerated() {
        let value: InstantLiveJSONValue = switch index % 4 {
        case 0: .string("line \(line) says something worth keeping, word \(index)")
        case 1: .number(Double(line * 1_000 + index) + 0.25)
        case 2: .bool(line % 2 == 0)
        default: .number(Double(1_791_700_000_000 + line))
        }
        triples.append(.array([.string(entityID), .string(attribute), value, .number(1_791_700_000_000)]))
      }
      rows.append(.array(triples))
    }
    let computation = InstantLiveJSONValue.object([
      "instaql-query": .object(["transcriptionSegments": .object(["$": .object(["limit": .number(64)])])]),
      "instaql-result": .array([
        .object(["data": .object(["datalog-result": .object(["join-rows": .array(rows)])])])
      ]),
    ])
    return InstantLiveMessage(
      op: "refresh-ok",
      clientEventID: "event-refresh",
      fields: [
        "attrs": .array(attributes.map { .object(["id": .string($0), "forward-identity": .array([.string($0)])]) }),
        "computations": .array([computation]),
        "processed-tx-id": .string("1234"),
      ]
    )
  }

  static func space(_ random: inout InfiniteWindowRandom) -> String {
    guard random.chance(30) else { return "" }
    return [" ", "\n", "\t", "\r\n", "  "][random.int(0...4)]
  }

  /// `value` as a JSON string, each character written as itself or escaped.
  static func randomString(_ random: inout InfiniteWindowRandom, value: String) -> String {
    var text = "\""
    for scalar in value.unicodeScalars {
      switch scalar {
      case "\"": text += "\\\""
      case "\\": text += "\\\\"
      case "\n": text += random.chance(50) ? "\\n" : "\\u000a"
      case "\t": text += "\\t"
      case "\r": text += "\\r"
      case "/": text += random.chance(50) ? "\\/" : "/"
      case _ where scalar.value < 0x20:
        text += String(format: "\\u%04x", scalar.value)
      case _ where scalar.value > 0xFFFF && random.chance(50):
        let offset = scalar.value - 0x10000
        text += String(format: "\\u%04X\\u%04x", 0xD800 + (offset >> 10), 0xDC00 + (offset & 0x3FF))
      case _ where scalar.value > 0x7F && random.chance(30):
        text += String(format: "\\u%04x", scalar.value)
      default:
        text.unicodeScalars.append(scalar)
      }
    }
    return text + "\""
  }

  static let stringPieces = [
    "a", "Z", "0", " ", "\"", "\\", "/", "\n", "\t", "\r", "\u{08}", "\u{0C}", "\u{00}", "\u{1F}", "é", "ß", "中", "日本",
    "😀", "👩🏽‍💻", "\u{10FFFF}", "e\u{301}", "line", "segment",
  ]

  static func randomJSON(_ random: inout InfiniteWindowRandom, depth: Int) -> String {
    switch random.int(0...(depth < 4 ? 9 : 6)) {
    case 0:
      return "null"
    case 1:
      return random.chance(50) ? "true" : "false"
    case 2, 3:
      let numbers = [
        "0", "-0", "1", "-1", "7", "42", "-17", "123456789012345", "1234567890123456789", "99999999999999999999",
        "0.5", "-0.25", "3.14159", "1e3", "1E3", "1e+3", "1e-3", "-2.5E-7", "6.02214076e23", "1.0", "100.000",
        "0.1", "9007199254740993", "1.7976931348623157e308", "5e-324", "2.2250738585072014e-308",
      ]
      return numbers[random.int(0...(numbers.count - 1))]
    case 4, 5, 6:
      var value = ""
      for _ in 0..<random.int(0...6) {
        value += stringPieces[random.int(0...(stringPieces.count - 1))]
      }
      return randomString(&random, value: value)
    case 7:
      let elements = (0..<random.int(0...4)).map { _ in space(&random) + randomJSON(&random, depth: depth + 1) + space(&random) }
      return "[" + elements.joined(separator: ",") + "]"
    default:
      var keys: Set<String> = []
      var members: [String] = []
      for index in 0..<random.int(0...4) {
        let key = random.chance(50) ? "key\(index)" : "k" + stringPieces[random.int(0...(stringPieces.count - 1))] + "\(index)"
        guard keys.insert(key).inserted else { continue }
        members.append(space(&random) + randomString(&random, value: key) + space(&random) + ":" + space(&random) + randomJSON(&random, depth: depth + 1))
      }
      return "{" + members.joined(separator: ",") + "}"
    }
  }

  static func threadCPUNanoseconds(_ work: () throws -> Void) rethrows -> UInt64 {
    let start = clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID)
    try work()
    return clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID) - start
  }
}
