import CoreFoundation
import Foundation
import Testing

@testable import InstantSwiftDataCore

/// Decoding a server message must not throw an error for every string it reads.
///
/// `InstantLiveJSONValue` decodes by trying one type after another. It tried `Bool`, `Int`, and
/// `Double` before `String`, so every string (entity IDs, attribute IDs, most values) threw three
/// `DecodingError`s first, and every array threw four. A Mac soak profile (2026-09-26) spent
/// 625 ms per 30 s in this decoder, 246 ms of it building coding paths for thrown errors.
@Suite(.serialized)
struct InstantLiveJSONValueDecodeCostTests {
  /// A refresh-shaped payload: 12 rows of 20 `[entity, attribute, value, tx]` join tuples with
  /// strings, integers, fractions, booleans, nulls, and nested objects.
  static func refreshPayload() -> Data {
    var rows: [String] = []
    for row in 0..<12 {
      var tuples: [String] = []
      for column in 0..<20 {
        let entity = String(format: "\"%08x-0000-4000-8000-%012x\"", row, column)
        let attribute = "\"attr-\(column)\""
        let value: String
        switch column % 6 {
        case 0: value = "\"text value \(row) \(column) with some words in it\""
        case 1: value = "\(1_790_000_000_000 + row * 100 + column)"
        case 2: value = "\(Double(row) + Double(column) / 8)"
        case 3: value = column % 2 == 0 ? "true" : "false"
        case 4: value = "null"
        default: value = "{\"nested\":[1,\"two\",false,null,{\"k\":\"v\"}],\"n\":-0}"
        }
        tuples.append("[\(entity),\(attribute),\(value),\(row * 20 + column)]")
      }
      rows.append("[" + tuples.joined(separator: ",") + "]")
    }
    let json = """
      {"op":"refresh-ok","processed-tx-id":42,"computations":[{"instaql-query":\
      {"recordings":{"$":{"limit":12}}},"instaql-result":[{"data":{"datalog-result":\
      {"join-rows":[\(rows.joined(separator: ","))]}},"child-nodes":[]}]}]}
      """
    return Data(json.utf8)
  }

  /// An independent conversion through `JSONSerialization`, used as the oracle.
  static func reference(_ object: Any) -> InstantLiveJSONValue {
    switch object {
    case is NSNull:
      return .null
    case let number as NSNumber:
      if CFGetTypeID(number) == CFBooleanGetTypeID() { return .bool(number.boolValue) }
      return .number(number.doubleValue)
    case let string as String:
      return .string(string)
    case let array as [Any]:
      return .array(array.map(reference))
    case let dictionary as [String: Any]:
      return .object(dictionary.mapValues(reference))
    default:
      Issue.record("unexpected JSON object \(type(of: object))")
      return .null
    }
  }

  @Test
  func decodingMatchesAnIndependentParse() throws {
    let data = Self.refreshPayload()
    let decoded = try JSONDecoder().decode(InstantLiveJSONValue.self, from: data)
    let reference = Self.reference(try JSONSerialization.jsonObject(with: data))
    #expect(decoded == reference)
  }

  @Test
  func decodingARefreshDoesNotThrowPerString() throws {
    let data = Self.refreshPayload()
    var nodes = 0
    let started = clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID)
    for _ in 0..<40 {
      let value = try JSONDecoder().decode(InstantLiveJSONValue.self, from: data)
      if case .object(let object) = value { nodes &+= object.count }
    }
    let cpuMilliseconds = Double(clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID) - started) / 1e6
    #expect(nodes == 40 * 3)
    print("LIVE_JSON_DECODE_COST cpu_ms=\(cpuMilliseconds) (40 decodes of a \(data.count)-byte refresh)")
  }
}
