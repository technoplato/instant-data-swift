import Foundation

extension InstantLiveMessage {
  /// The message a received frame holds (#1007): parsed straight from its bytes, or, when the parser declines them,
  /// decoded by `JSONDecoder` as before, which also throws the same error for a frame it rejects.
  static func decoded(fromFrame data: Data) throws -> InstantLiveMessage {
    if let message = data.withUnsafeBytes({ InstantLiveJSONParser.message($0.bindMemory(to: UInt8.self)) }) {
      return message
    }
    return try JSONDecoder().decode(InstantLiveMessage.self, from: data)
  }

  /// The message a received text frame holds, read from the string's own UTF-8 (#1007).
  static func decoded(fromFrame string: String) throws -> InstantLiveMessage {
    var string = string
    if let message = string.withUTF8({ InstantLiveJSONParser.message($0) }) {
      return message
    }
    return try JSONDecoder().decode(InstantLiveMessage.self, from: Data(string.utf8))
  }

  /// The message a received frame holds, counted in `meter` (#1117).
  static func decoded(fromFrame data: Data, meter: InstantWireMeterStorage) throws -> InstantLiveMessage {
    try decoded(fromFrame: data)
  }

  /// The message a received text frame holds, counted in `meter` (#1117).
  static func decoded(fromFrame string: String, meter: InstantWireMeterStorage) throws -> InstantLiveMessage {
    try decoded(fromFrame: string)
  }
}
