import Foundation

// History:
// - 2026-10-23: the store's text for a value and a fact goes through one seam, so the text it keeps can be written
//   without `JSONEncoder` and checked against it (#1007).
// - 2026-10-23: the seam writes the text of null, string, number, boolean, ref and date values and of a fact itself,
//   byte for byte as `JSONEncoder` writes it, and asks `JSONEncoder` for the rest (#1007).
// - 2026-10-25: a value's text can be appended to a caller's buffer, for the ownership diff's fingerprints (#1147).
// - 2026-10-25: the store writes only a value's text; a fact's JSON is computed by the fact table when read (#1121).
// - 2026-10-25: a value's text is read back here too, for the values the writer writes itself, so a fact read from its
//   columns needs no `JSONDecoder` (#1150).

/// The JSON text the local store keeps for a value and for a fact (#1007).
///
/// A stored fact keeps its value's text in `value_json`, part of the facts' key and of the lookups that find them. It is
/// `JSONEncoder`'s text with `.sortedKeys`, and must stay exactly that: a lookup compares the text byte for byte with
/// the text an earlier version stored. A fact's own text (`stored(_:using:)` for a triple) is no longer stored: the fact
/// table computes its `json` from the row when it is read (#1121). Encoding them with `JSONEncoder` cost two
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

  // MARK: - Reading

  /// The value whose stored text is `text`, read without `JSONDecoder` for the values this writer writes itself: null,
  /// string, number, boolean, ref and date (#1150).
  ///
  /// Nil for a JSON value or a lookup ref, and for any text it does not take apart byte for byte (an escape `JSONEncoder`
  /// does not write, a number outside JSON's grammar, text that is not UTF-8): the caller decodes those with
  /// `JSONDecoder`, which reads every text the store has kept. Before iOS 18 and macOS 15, which validate UTF-8 for it,
  /// it leaves every text to `JSONDecoder`.
  static func value(stored text: UnsafeBufferPointer<UInt8>) -> InstantValue? {
    var scratch: [UInt8] = []
    return value(stored: text, scratch: &scratch)
  }

  /// ``value(stored:)``, unescaping a string that has escapes into `scratch`, which a caller reading many values keeps:
  /// a transcript line's words are a string full of quotes, and growing a new buffer for each cost several allocations.
  static func value(stored text: UnsafeBufferPointer<UInt8>, scratch: inout [UInt8]) -> InstantValue? {
    guard #available(iOS 18, macOS 15, macCatalyst 18, tvOS 18, watchOS 11, *) else { return nil }
    var reader = StoredValueReader(text: text)
    return reader.value(scratch: &scratch)
  }
}

/// Takes apart the text `InstantStoredJSON` writes for a value: the case's name holding its value under `_0`.
@available(iOS 18, macOS 15, macCatalyst 18, tvOS 18, watchOS 11, *)
private struct StoredValueReader {
  let text: UnsafeBufferPointer<UInt8>
  var index = 0

  mutating func value(scratch: inout [UInt8]) -> InstantValue? {
    guard consume(#"{""#) else { return nil }
    if consume(#"string":{"_0":"#) {
      guard let string = string(scratch: &scratch), consumeEnd() else { return nil }
      return .string(string)
    }
    if consume(#"number":{"_0":"#) {
      guard let number = number(), consumeEnd() else { return nil }
      return .number(number)
    }
    if consume(#"ref":{"_0":"#) {
      guard let id = string(scratch: &scratch), consumeEnd() else { return nil }
      return .ref(id)
    }
    if consume(#"bool":{"_0":"#) {
      let bool: Bool
      if consume("true") {
        bool = true
      } else if consume("false") {
        bool = false
      } else {
        return nil
      }
      return consumeEnd() ? .bool(bool) : nil
    }
    if consume(#"null":{}}"#) {
      return index == text.count ? .null : nil
    }
    if consume(#"date":{"_0":"#) {
      guard let seconds = number(), consumeEnd() else { return nil }
      return .date(Date(timeIntervalSinceReferenceDate: seconds))
    }
    return nil
  }

  /// The value's closing braces, and nothing after them.
  private mutating func consumeEnd() -> Bool {
    consume("}}") && index == text.count
  }

  private mutating func consume(_ literal: StaticString) -> Bool {
    let count = literal.utf8CodeUnitCount
    guard text.count - index >= count,
      memcmp(text.baseAddress! + index, literal.utf8Start, count) == 0
    else { return false }
    index += count
    return true
  }

  /// A JSON string. A string with no escape is made from its bytes in one step; one with escapes is unescaped into
  /// `scratch` first.
  private mutating func string(scratch: inout [UInt8]) -> String? {
    guard index < text.count, text[index] == UInt8(ascii: "\"") else { return nil }
    index += 1
    let start = index
    while index < text.count {
      let byte = text[index]
      if byte == UInt8(ascii: "\"") {
        let string = String(validating: UnsafeBufferPointer(rebasing: text[start..<index]), as: UTF8.self)
        index += 1
        return string
      }
      if byte == UInt8(ascii: "\\") { break }
      // JSON allows no raw control character in a string.
      guard byte >= 0x20 else { return nil }
      index += 1
    }
    scratch.removeAll(keepingCapacity: true)
    scratch.append(contentsOf: UnsafeBufferPointer(rebasing: text[start..<index]))
    while index < text.count {
      let byte = text[index]
      index += 1
      switch byte {
      case UInt8(ascii: "\""):
        return String(validating: scratch, as: UTF8.self)
      case UInt8(ascii: "\\"):
        guard index < text.count else { return nil }
        let escape = text[index]
        index += 1
        switch escape {
        case UInt8(ascii: "\""), UInt8(ascii: "\\"), UInt8(ascii: "/"): scratch.append(escape)
        case UInt8(ascii: "b"): scratch.append(0x08)
        case UInt8(ascii: "f"): scratch.append(0x0C)
        case UInt8(ascii: "n"): scratch.append(0x0A)
        case UInt8(ascii: "r"): scratch.append(0x0D)
        case UInt8(ascii: "t"): scratch.append(0x09)
        case UInt8(ascii: "u"):
          guard let scalar = escapedScalar() else { return nil }
          UTF8.encode(scalar) { scratch.append($0) }
        default:
          return nil
        }
      default:
        guard byte >= 0x20 else { return nil }
        scratch.append(byte)
      }
    }
    return nil
  }

  /// The scalar of a `\u` escape, after its `u`: four hex digits, or a surrogate pair's two escapes.
  private mutating func escapedScalar() -> Unicode.Scalar? {
    guard let unit = hexUnit() else { return nil }
    if UTF16.isLeadSurrogate(unit) {
      guard consume(#"\u"#), let trail = hexUnit(), UTF16.isTrailSurrogate(trail) else { return nil }
      return Unicode.Scalar(0x10000 + ((UInt32(unit) - 0xD800) << 10) + (UInt32(trail) - 0xDC00))
    }
    return Unicode.Scalar(unit)
  }

  private mutating func hexUnit() -> UInt16? {
    guard text.count - index >= 4 else { return nil }
    var unit: UInt16 = 0
    for _ in 0..<4 {
      let byte = text[index]
      let digit: UInt8
      switch byte {
      case UInt8(ascii: "0")...UInt8(ascii: "9"): digit = byte - UInt8(ascii: "0")
      case UInt8(ascii: "a")...UInt8(ascii: "f"): digit = byte - UInt8(ascii: "a") + 10
      case UInt8(ascii: "A")...UInt8(ascii: "F"): digit = byte - UInt8(ascii: "A") + 10
      default: return nil
      }
      unit = unit << 4 | UInt16(digit)
      index += 1
    }
    return unit
  }

  /// A finite number in JSON's grammar, read as `Double` reads its text.
  private mutating func number() -> Double? {
    let start = index
    _ = consume("-")
    // A leading zero stands alone; what follows it fails the closing braces.
    if !consume("0"), digits() == 0 { return nil }
    if consume("."), digits() == 0 { return nil }
    if consume("e") || consume("E") {
      if !consume("+") { _ = consume("-") }
      if digits() == 0 { return nil }
    }
    guard let number = Double(String(decoding: UnsafeBufferPointer(rebasing: text[start..<index]), as: UTF8.self)),
      number.isFinite
    else { return nil }
    return number
  }

  private mutating func digits() -> Int {
    let start = index
    while index < text.count, (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(text[index]) { index += 1 }
    return index - start
  }
}
