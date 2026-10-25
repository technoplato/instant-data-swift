import Foundation

// History:
// - 2026-10-23: the store's text for a value and a fact goes through one seam, so the text it keeps can be written
//   without `JSONEncoder` and checked against it (#1007).
// - 2026-10-23: the seam writes the text of null, string, number, boolean, ref and date values and of a fact itself,
//   byte for byte as `JSONEncoder` writes it, and asks `JSONEncoder` for the rest (#1007).
// - 2026-10-25: a value's text can be appended to a caller's buffer, for the ownership diff's fingerprints (#1147).

/// The JSON text the local store keeps for a value and for a fact (#1007).
///
/// A stored fact keeps its value's text in `value_json`, part of the facts' key and of the lookups that find them, and
/// its own text in `json`. Both are `JSONEncoder`'s text with `.sortedKeys`, and both must stay exactly that: a lookup
/// compares the text byte for byte with the text an earlier version stored. Encoding them with `JSONEncoder` cost two
/// encoder runs per stored fact, 5% of a write replay's CPU, so the values a write stores are written here, as
/// `JSONEncoder` writes them, and every other value (a JSON value, a lookup ref) is still `JSONEncoder`'s to write.
enum InstantStoredJSON {
  /// The text the store keeps for `value`. Throws what `JSONEncoder` throws for it.
  static func stored(_ value: InstantValue, using encoder: JSONEncoder) throws -> String {
    var bytes: [UInt8] = []
    bytes.reserveCapacity(estimatedByteCount(value))
    if append(value, to: &bytes) {
      return String(decoding: bytes, as: UTF8.self)
    }
    return String(decoding: try encoder.encode(value), as: UTF8.self)
  }

  /// Appends the text the store keeps for `value` to `bytes`: `stored(_:using:)` without making a string, for a caller
  /// that only hashes or compares the text (#1147). Throws what `JSONEncoder` throws for it.
  static func appendStored(_ value: InstantValue, to bytes: inout [UInt8], using encoder: JSONEncoder) throws {
    if append(value, to: &bytes) { return }
    bytes.append(contentsOf: try encoder.encode(value))
  }

  /// The text the store keeps for `triple`. Throws what `JSONEncoder` throws for it.
  static func stored(_ triple: InstantTriple, using encoder: JSONEncoder) throws -> String {
    try storedTexts(triple, using: encoder).triple
  }

  /// The texts the store keeps for a fact's value and for the fact, the value written once: the fact's text holds the
  /// value's text as it is. Throws what `JSONEncoder` throws for them.
  static func storedTexts(
    _ triple: InstantTriple,
    using encoder: JSONEncoder
  ) throws -> (value: String, triple: String) {
    var value: [UInt8] = []
    value.reserveCapacity(estimatedByteCount(triple.value))
    guard append(triple.value, to: &value) else {
      return (
        String(decoding: try encoder.encode(triple.value), as: UTF8.self),
        String(decoding: try encoder.encode(triple), as: UTF8.self)
      )
    }
    var bytes: [UInt8] = []
    bytes.reserveCapacity(value.count + triple.attributeID.utf8.count + triple.entityID.utf8.count + 96)
    bytes.append(contentsOf: #"{"attributeID":"#.utf8)
    appendString(triple.attributeID, to: &bytes)
    bytes.append(contentsOf: #","entityID":"#.utf8)
    appendString(triple.entityID, to: &bytes)
    bytes.append(contentsOf: #","txID":"#.utf8)
    appendString(triple.txID, to: &bytes)
    bytes.append(contentsOf: #","txTime":{"milliseconds":"#.utf8)
    bytes.append(contentsOf: String(triple.txTime.milliseconds).utf8)
    bytes.append(contentsOf: #"},"value":"#.utf8)
    bytes.append(contentsOf: value)
    bytes.append(UInt8(ascii: "}"))
    return (String(decoding: value, as: UTF8.self), String(decoding: bytes, as: UTF8.self))
  }

  // MARK: - Writing

  // Keys in the order `.sortedKeys` puts them, and the synthesized coding of an enum case: the case's name holding
  // its value under `_0`.

  /// Appends `value` as `JSONEncoder` writes it, or returns false for a value this writer leaves to `JSONEncoder`: a
  /// JSON value (its objects' keys sort as `JSONEncoder` sorts them), a lookup ref, and a number that is not finite
  /// (`JSONEncoder` throws for it).
  private static func append(_ value: InstantValue, to bytes: inout [UInt8]) -> Bool {
    switch value {
    case .null:
      bytes.append(contentsOf: #"{"null":{}}"#.utf8)
    case let .string(string):
      bytes.append(contentsOf: #"{"string":{"_0":"#.utf8)
      appendString(string, to: &bytes)
      bytes.append(contentsOf: "}}".utf8)
    case let .number(number):
      guard number.isFinite else { return false }
      bytes.append(contentsOf: #"{"number":{"_0":"#.utf8)
      appendNumber(number, to: &bytes)
      bytes.append(contentsOf: "}}".utf8)
    case let .bool(bool):
      bytes.append(contentsOf: (bool ? #"{"bool":{"_0":true}}"# : #"{"bool":{"_0":false}}"#).utf8)
    case let .ref(id):
      bytes.append(contentsOf: #"{"ref":{"_0":"#.utf8)
      appendString(id, to: &bytes)
      bytes.append(contentsOf: "}}".utf8)
    case let .date(date):
      // `Date` encodes its seconds since the reference date, `JSONEncoder`'s default date strategy.
      let seconds = date.timeIntervalSinceReferenceDate
      guard seconds.isFinite else { return false }
      bytes.append(contentsOf: #"{"date":{"_0":"#.utf8)
      appendNumber(seconds, to: &bytes)
      bytes.append(contentsOf: "}}".utf8)
    case .json, .lookupRef:
      return false
    }
    return true
  }

  /// A finite number as `JSONEncoder` writes it: its shortest round-trip description, without a trailing `.0`.
  private static func appendNumber(_ number: Double, to bytes: inout [UInt8]) {
    var text = number.description
    if text.hasSuffix(".0") {
      text.removeLast(2)
    }
    bytes.append(contentsOf: text.utf8)
  }

  /// A string as `JSONEncoder` writes it: quotes, backslashes and slashes escaped, the short escapes for backspace, form
  /// feed, newline, carriage return and tab, `\u00xx` for the other control characters, every other byte as it is.
  /// Runs of bytes that need no escape are copied in one append.
  private static func appendString(_ string: String, to bytes: inout [UInt8]) {
    bytes.append(UInt8(ascii: "\""))
    let copied: Void? = string.utf8.withContiguousStorageIfAvailable { utf8 in
      var runStart = 0
      var index = 0
      while index < utf8.count {
        let byte = utf8[index]
        if byte >= 0x20, byte != UInt8(ascii: "\""), byte != UInt8(ascii: "\\"), byte != UInt8(ascii: "/") {
          index += 1
          continue
        }
        if runStart < index {
          bytes.append(contentsOf: UnsafeBufferPointer(rebasing: utf8[runStart..<index]))
        }
        appendEscape(byte, to: &bytes)
        index += 1
        runStart = index
      }
      if runStart < utf8.count {
        bytes.append(contentsOf: UnsafeBufferPointer(rebasing: utf8[runStart..<utf8.count]))
      }
    }
    if copied == nil {
      for byte in string.utf8 {
        if byte >= 0x20, byte != UInt8(ascii: "\""), byte != UInt8(ascii: "\\"), byte != UInt8(ascii: "/") {
          bytes.append(byte)
        } else {
          appendEscape(byte, to: &bytes)
        }
      }
    }
    bytes.append(UInt8(ascii: "\""))
  }

  /// The escape `JSONEncoder` writes for a quote, a backslash, a slash or a control character.
  private static func appendEscape(_ byte: UInt8, to bytes: inout [UInt8]) {
    switch byte {
    case UInt8(ascii: "\""):
      bytes.append(contentsOf: #"\""#.utf8)
    case UInt8(ascii: "\\"):
      bytes.append(contentsOf: #"\\"#.utf8)
    case UInt8(ascii: "/"):
      bytes.append(contentsOf: #"\/"#.utf8)
    case 0x08:
      bytes.append(contentsOf: #"\b"#.utf8)
    case 0x0C:
      bytes.append(contentsOf: #"\f"#.utf8)
    case 0x0A:
      bytes.append(contentsOf: #"\n"#.utf8)
    case 0x0D:
      bytes.append(contentsOf: #"\r"#.utf8)
    case 0x09:
      bytes.append(contentsOf: #"\t"#.utf8)
    default:
      bytes.append(contentsOf: #"\u00"#.utf8)
      bytes.append(hexDigits[Int(byte >> 4)])
      bytes.append(hexDigits[Int(byte & 0x0F)])
    }
  }

  /// Room for `value`'s text, so a long string's text is not copied as it grows.
  private static func estimatedByteCount(_ value: InstantValue) -> Int {
    switch value {
    case let .string(string), let .ref(string):
      string.utf8.count + string.utf8.count / 8 + 32
    default:
      48
    }
  }

  private static let hexDigits: [UInt8] = Array("0123456789abcdef".utf8)
}
