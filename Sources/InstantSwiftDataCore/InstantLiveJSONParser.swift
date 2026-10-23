import Foundation

// History:
// - 2026-10-23: a received frame is parsed straight into `InstantLiveJSONValue` (#1007). Through `JSONDecoder`, every
//   value tried each JSON kind in turn and each miss threw a `DecodingError` that recorded its coding path: three for
//   every object, two for every array, one for every number. A server result restates each query's triples, so a frame
//   threw thousands of errors, and decoding frames was 3% of one core on a device while recording.

/// Parses one received frame's JSON into ``InstantLiveJSONValue`` directly from its UTF-8 bytes (#1007).
///
/// It takes strict JSON (RFC 8259) only. Anything it does not take whole, it declines (nil), and the caller decodes the
/// frame with `JSONDecoder` as before, so every frame `JSONDecoder` rejects is still rejected with the same error, and
/// every frame this parser takes yields the value `JSONDecoder` yields: a number `Double` cannot hold or that underflows
/// to zero, a string that is not valid UTF-8 or holds a lone surrogate, a repeated key in one object, or nesting deeper
/// than 256 is declined, and `JSONDecoder` answers it.
struct InstantLiveJSONParser {
  /// Below `JSONDecoder`'s own limit (512), so `JSONDecoder` decides every deeper nest. Server frames nest about ten deep.
  static let maximumDepth = 256

  private let bytes: UnsafeBufferPointer<UInt8>
  private var index = 0

  private init(_ bytes: UnsafeBufferPointer<UInt8>) {
    self.bytes = bytes
  }

  /// The value `bytes` holds, or nil when the parser declines them.
  static func value(_ bytes: UnsafeBufferPointer<UInt8>) -> InstantLiveJSONValue? {
    var parser = InstantLiveJSONParser(bytes)
    parser.skipWhitespace()
    guard let value = parser.parseValue(depth: 0) else { return nil }
    parser.skipWhitespace()
    return parser.index == bytes.count ? value : nil
  }

  /// The message `bytes` holds, as `InstantLiveMessage.init(from:)` decodes it, or nil when the parser declines them
  /// or the message is not one that decoder takes (no string `op`, a `client-event-id` that is neither a string nor
  /// null).
  static func message(_ bytes: UnsafeBufferPointer<UInt8>) -> InstantLiveMessage? {
    guard case var .object(fields)? = value(bytes),
      case let .string(op)? = fields.removeValue(forKey: "op")
    else { return nil }
    let clientEventID: String?
    switch fields.removeValue(forKey: "client-event-id") {
    case nil, .null?:
      clientEventID = nil
    case let .string(value)?:
      clientEventID = value
    default:
      return nil
    }
    return InstantLiveMessage(op: op, clientEventID: clientEventID, fields: fields)
  }

  // MARK: - Values

  private mutating func parseValue(depth: Int) -> InstantLiveJSONValue? {
    guard index < bytes.count else { return nil }
    switch bytes[index] {
    case UInt8(ascii: "\""):
      return parseString().map(InstantLiveJSONValue.string)
    case UInt8(ascii: "{"):
      return parseObject(depth: depth + 1)
    case UInt8(ascii: "["):
      return parseArray(depth: depth + 1)
    case UInt8(ascii: "t"):
      return consume("true") ? .bool(true) : nil
    case UInt8(ascii: "f"):
      return consume("false") ? .bool(false) : nil
    case UInt8(ascii: "n"):
      return consume("null") ? .null : nil
    case UInt8(ascii: "-"), UInt8(ascii: "0")...UInt8(ascii: "9"):
      return parseNumber().map(InstantLiveJSONValue.number)
    default:
      return nil
    }
  }

  private mutating func parseObject(depth: Int) -> InstantLiveJSONValue? {
    guard depth <= Self.maximumDepth else { return nil }
    index += 1
    var object: [String: InstantLiveJSONValue] = [:]
    skipWhitespace()
    if index < bytes.count, bytes[index] == UInt8(ascii: "}") {
      index += 1
      return .object(object)
    }
    while true {
      skipWhitespace()
      guard index < bytes.count, bytes[index] == UInt8(ascii: "\""), let key = parseString() else { return nil }
      skipWhitespace()
      guard index < bytes.count, bytes[index] == UInt8(ascii: ":") else { return nil }
      index += 1
      skipWhitespace()
      guard let value = parseValue(depth: depth) else { return nil }
      // A repeated key is declined: `JSONDecoder` decides which occurrence counts.
      guard object.updateValue(value, forKey: key) == nil else { return nil }
      skipWhitespace()
      guard index < bytes.count else { return nil }
      switch bytes[index] {
      case UInt8(ascii: ","):
        index += 1
      case UInt8(ascii: "}"):
        index += 1
        return .object(object)
      default:
        return nil
      }
    }
  }

  private mutating func parseArray(depth: Int) -> InstantLiveJSONValue? {
    guard depth <= Self.maximumDepth else { return nil }
    index += 1
    var array: [InstantLiveJSONValue] = []
    skipWhitespace()
    if index < bytes.count, bytes[index] == UInt8(ascii: "]") {
      index += 1
      return .array(array)
    }
    while true {
      skipWhitespace()
      guard let value = parseValue(depth: depth) else { return nil }
      array.append(value)
      skipWhitespace()
      guard index < bytes.count else { return nil }
      switch bytes[index] {
      case UInt8(ascii: ","):
        index += 1
      case UInt8(ascii: "]"):
        index += 1
        return .array(array)
      default:
        return nil
      }
    }
  }

  // MARK: - Strings

  /// The string at `index` (an opening quote), or nil for an unescaped control character, a bad escape, a lone
  /// surrogate or bytes that are not UTF-8.
  private mutating func parseString() -> String? {
    index += 1
    let start = index
    // Most strings hold no escape: take their bytes as they are.
    while index < bytes.count {
      let byte = bytes[index]
      if byte == UInt8(ascii: "\"") {
        let run = UnsafeBufferPointer(rebasing: bytes[start..<index])
        index += 1
        return Self.isValidUTF8(run) ? String(decoding: run, as: UTF8.self) : nil
      }
      if byte == UInt8(ascii: "\\") { break }
      if byte < 0x20 { return nil }
      index += 1
    }
    guard index < bytes.count else { return nil }
    var utf8: [UInt8] = []
    utf8.reserveCapacity(index - start + 16)
    let leading = UnsafeBufferPointer(rebasing: bytes[start..<index])
    guard Self.isValidUTF8(leading) else { return nil }
    utf8.append(contentsOf: leading)
    var runStart = index
    while index < bytes.count {
      let byte = bytes[index]
      switch byte {
      case UInt8(ascii: "\""):
        let run = UnsafeBufferPointer(rebasing: bytes[runStart..<index])
        guard Self.isValidUTF8(run) else { return nil }
        utf8.append(contentsOf: run)
        index += 1
        return String(decoding: utf8, as: UTF8.self)
      case UInt8(ascii: "\\"):
        let run = UnsafeBufferPointer(rebasing: bytes[runStart..<index])
        guard Self.isValidUTF8(run) else { return nil }
        utf8.append(contentsOf: run)
        guard parseEscape(into: &utf8) else { return nil }
        runStart = index
      case 0..<0x20:
        return nil
      default:
        index += 1
      }
    }
    return nil
  }

  /// Appends the escape at `index` (a backslash) as UTF-8.
  private mutating func parseEscape(into utf8: inout [UInt8]) -> Bool {
    index += 1
    guard index < bytes.count else { return false }
    let escaped = bytes[index]
    index += 1
    switch escaped {
    case UInt8(ascii: "\""): utf8.append(UInt8(ascii: "\""))
    case UInt8(ascii: "\\"): utf8.append(UInt8(ascii: "\\"))
    case UInt8(ascii: "/"): utf8.append(UInt8(ascii: "/"))
    case UInt8(ascii: "b"): utf8.append(0x08)
    case UInt8(ascii: "f"): utf8.append(0x0C)
    case UInt8(ascii: "n"): utf8.append(0x0A)
    case UInt8(ascii: "r"): utf8.append(0x0D)
    case UInt8(ascii: "t"): utf8.append(0x09)
    case UInt8(ascii: "u"):
      guard let unit = parseHexUnit() else { return false }
      let scalarValue: UInt32
      switch unit {
      case 0xD800...0xDBFF:
        // A high surrogate must be followed by an escaped low one.
        guard index + 1 < bytes.count, bytes[index] == UInt8(ascii: "\\"), bytes[index + 1] == UInt8(ascii: "u")
        else { return false }
        index += 2
        guard let low = parseHexUnit(), (0xDC00...0xDFFF).contains(low) else { return false }
        scalarValue = 0x10000 + ((UInt32(unit) - 0xD800) << 10) + (UInt32(low) - 0xDC00)
      case 0xDC00...0xDFFF:
        return false
      default:
        scalarValue = UInt32(unit)
      }
      guard let scalar = Unicode.Scalar(scalarValue) else { return false }
      utf8.append(contentsOf: UTF8.encode(scalar)!)
    default:
      return false
    }
    return true
  }

  private mutating func parseHexUnit() -> UInt16? {
    guard index + 4 <= bytes.count else { return nil }
    var unit: UInt16 = 0
    for _ in 0..<4 {
      let byte = bytes[index]
      let digit: UInt16
      switch byte {
      case UInt8(ascii: "0")...UInt8(ascii: "9"): digit = UInt16(byte - UInt8(ascii: "0"))
      case UInt8(ascii: "a")...UInt8(ascii: "f"): digit = UInt16(byte - UInt8(ascii: "a") + 10)
      case UInt8(ascii: "A")...UInt8(ascii: "F"): digit = UInt16(byte - UInt8(ascii: "A") + 10)
      default: return nil
      }
      unit = unit << 4 | digit
      index += 1
    }
    return unit
  }

  /// Whether `bytes` are well-formed UTF-8 (Unicode table 3-7): no overlong form, no surrogate, nothing past U+10FFFF.
  static func isValidUTF8(_ bytes: UnsafeBufferPointer<UInt8>) -> Bool {
    var index = 0
    while index < bytes.count {
      let lead = bytes[index]
      if lead < 0x80 {
        index += 1
        continue
      }
      let length: Int
      var lower: UInt8 = 0x80
      var upper: UInt8 = 0xBF
      switch lead {
      case 0xC2...0xDF:
        length = 2
      case 0xE0:
        length = 3
        lower = 0xA0
      case 0xE1...0xEC, 0xEE...0xEF:
        length = 3
      case 0xED:
        length = 3
        upper = 0x9F
      case 0xF0:
        length = 4
        lower = 0x90
      case 0xF1...0xF3:
        length = 4
      case 0xF4:
        length = 4
        upper = 0x8F
      default:
        return false
      }
      guard index + length <= bytes.count else { return false }
      let second = bytes[index + 1]
      guard second >= lower, second <= upper else { return false }
      for offset in 2..<length where !(0x80...0xBF).contains(bytes[index + offset]) {
        return false
      }
      index += length
    }
    return true
  }

  // MARK: - Numbers

  /// The number at `index` in JSON's grammar, or nil for any other form or a value `Double` cannot hold.
  private mutating func parseNumber() -> Double? {
    let start = index
    let isNegative = bytes[index] == UInt8(ascii: "-")
    if isNegative { index += 1 }
    guard index < bytes.count else { return nil }
    var integer: Int64 = 0
    var digitCount = 0
    var hasNonZeroDigit = false
    if bytes[index] == UInt8(ascii: "0") {
      index += 1
      digitCount = 1
    } else if (UInt8(ascii: "1")...UInt8(ascii: "9")).contains(bytes[index]) {
      hasNonZeroDigit = true
      while index < bytes.count, (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(bytes[index]) {
        if digitCount < 18 { integer = integer * 10 + Int64(bytes[index] - UInt8(ascii: "0")) }
        digitCount += 1
        index += 1
      }
    } else {
      return nil
    }
    var isInteger = true
    if index < bytes.count, bytes[index] == UInt8(ascii: ".") {
      isInteger = false
      index += 1
      guard index < bytes.count, (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(bytes[index]) else { return nil }
      while index < bytes.count, (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(bytes[index]) {
        if bytes[index] != UInt8(ascii: "0") { hasNonZeroDigit = true }
        index += 1
      }
    }
    if index < bytes.count, bytes[index] == UInt8(ascii: "e") || bytes[index] == UInt8(ascii: "E") {
      isInteger = false
      index += 1
      if index < bytes.count, bytes[index] == UInt8(ascii: "+") || bytes[index] == UInt8(ascii: "-") { index += 1 }
      guard index < bytes.count, (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(bytes[index]) else { return nil }
      while index < bytes.count, (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(bytes[index]) { index += 1 }
    }
    // An integer of at most 15 digits is exact as a Double; every other form goes through the correctly rounded
    // conversion `JSONDecoder` uses.
    if isInteger, digitCount <= 15 {
      if isNegative, integer == 0 { return -0.0 }
      return Double(isNegative ? -integer : integer)
    }
    let text = String(decoding: UnsafeBufferPointer(rebasing: bytes[start..<index]), as: UTF8.self)
    // A value past Double's range, or one that underflows to zero, is `JSONDecoder`'s to judge.
    guard let value = Double(text), value.isFinite, value != 0 || !hasNonZeroDigit else { return nil }
    return value
  }

  // MARK: - Lexing

  private mutating func skipWhitespace() {
    while index < bytes.count {
      switch bytes[index] {
      case UInt8(ascii: " "), UInt8(ascii: "\t"), UInt8(ascii: "\n"), UInt8(ascii: "\r"):
        index += 1
      default:
        return
      }
    }
  }

  private mutating func consume(_ literal: StaticString) -> Bool {
    let count = literal.utf8CodeUnitCount
    guard index + count <= bytes.count else { return false }
    let matches = literal.withUTF8Buffer { expected in
      (0..<count).allSatisfy { bytes[index + $0] == expected[$0] }
    }
    guard matches else { return false }
    index += count
    return true
  }
}
