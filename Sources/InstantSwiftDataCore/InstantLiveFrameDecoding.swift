import Foundation

// History:
// - 2026-10-23: a frame is parsed straight from its bytes (#1007).
// - 2026-10-26: decoding a frame also counts each query's answer in the wire meter, under its shape (#1117): a refresh's
//   computations each with their own bytes, a query's first answer with its frame's.
// - 2026-11-04: a text frame bridged from the socket's NSString takes its UTF-8 from CoreFoundation in one pass instead
//   of a copy one character at a time (#1109).

extension InstantLiveMessage {
  /// The message a received frame holds (#1007): parsed straight from its bytes, or, when the parser declines them,
  /// decoded by `JSONDecoder` as before, which also throws the same error for a frame it rejects. Each query it answers
  /// is counted in ``InstantWireMeter`` (#1117).
  static func decoded(fromFrame data: Data) throws -> InstantLiveMessage {
    try decoded(fromFrame: data, meter: InstantWireMeter.shared)
  }

  /// The message a received text frame holds, read from the string's own UTF-8 (#1007), its queries counted in
  /// ``InstantWireMeter`` (#1117).
  static func decoded(fromFrame string: String) throws -> InstantLiveMessage {
    try decoded(fromFrame: string, meter: InstantWireMeter.shared)
  }

  /// The message a received frame holds, each query it answers counted in `meter` (#1117).
  static func decoded(fromFrame data: Data, meter: InstantWireMeterStorage) throws -> InstantLiveMessage {
    if let parsed = data.withUnsafeBytes({
      InstantLiveJSONParser.messageAndComputationSizes($0.bindMemory(to: UInt8.self))
    }) {
      meter.recordQueries(parsed.message.queryAnswers(computationByteCounts: parsed.computationByteCounts, frameBytes: data.count))
      return parsed.message
    }
    let message = try JSONDecoder().decode(InstantLiveMessage.self, from: data)
    meter.recordQueries(message.queryAnswers(computationByteCounts: [], frameBytes: data.count))
    return message
  }

  /// The message a received text frame holds, each query it answers counted in `meter` (#1117).
  static func decoded(fromFrame string: String, meter: InstantWireMeterStorage) throws -> InstantLiveMessage {
    // #1109: a text frame arrives as the socket's NSString, which holds UTF-16 once the frame has any character outside
    // ASCII. The String bridged from it is not native, and `withUTF8` below copied it one character at a time through
    // the NSString: 84 of the frame decode's 155 ms in a 90 s trace of the phone transcribing speech (build 251).
    if string.utf8.withContiguousStorageIfAvailable({ _ in () }) == nil, let data = utf8Data(ofBridged: string) {
      return try decoded(fromFrame: data, meter: meter)
    }
    var string = string
    let frameBytes = string.utf8.count
    if let parsed = string.withUTF8({ InstantLiveJSONParser.messageAndComputationSizes($0) }) {
      meter.recordQueries(parsed.message.queryAnswers(computationByteCounts: parsed.computationByteCounts, frameBytes: frameBytes))
      return parsed.message
    }
    let message = try JSONDecoder().decode(InstantLiveMessage.self, from: Data(string.utf8))
    meter.recordQueries(message.queryAnswers(computationByteCounts: [], frameBytes: frameBytes))
    return message
  }

  /// The UTF-8 of `string`, a String bridged from an NSString, transcoded by CoreFoundation in bulk (#1109); nil when a
  /// character does not convert (an unpaired surrogate), so the caller's own error-corrected copy reads it as before.
  private static func utf8Data(ofBridged string: String) -> Data? {
    let text = string as CFString
    let range = CFRange(location: 0, length: CFStringGetLength(text))
    let encoding = CFStringBuiltInEncodings.UTF8.rawValue
    var byteCount: CFIndex = 0
    guard CFStringGetBytes(text, range, encoding, 0, false, nil, 0, &byteCount) == range.length else { return nil }
    var data = Data(count: byteCount)
    let converted = data.withUnsafeMutableBytes { buffer in
      CFStringGetBytes(text, range, encoding, 0, false, buffer.bindMemory(to: UInt8.self).baseAddress, byteCount, nil)
    }
    return converted == range.length ? data : nil
  }

  /// Each query this message answers and the bytes its answer took (#1117): a refresh's computations, each with its
  /// own bytes when the parser measured them (a frame `JSONDecoder` read counts none, its op still counts it whole), and
  /// a query's first answer with the whole frame.
  func queryAnswers(computationByteCounts: [Int], frameBytes: Int) -> [(shape: String, bytes: Int)] {
    switch op {
    case "refresh-ok":
      guard case .array(let computations)? = fields["computations"],
        computations.count == computationByteCounts.count
      else { return [] }
      return zip(computations, computationByteCounts).map { computation, bytes in
        let query: InstantLiveJSONValue =
          if case .object(let object) = computation, let query = object["instaql-query"] { query } else { .null }
        return (InstantWireMeter.queryShape(of: query), bytes)
      }
    case "add-query-ok", "add-query-exists":
      return [(InstantWireMeter.queryShape(of: fields["q"] ?? .null), frameBytes)]
    default:
      return []
    }
  }
}
