import Foundation

extension InstantLiveMessage {
  /// The message a received frame holds (#1007).
  static func decoded(fromFrame data: Data) throws -> InstantLiveMessage {
    try JSONDecoder().decode(InstantLiveMessage.self, from: data)
  }

  /// The message a received text frame holds (#1007).
  static func decoded(fromFrame string: String) throws -> InstantLiveMessage {
    try JSONDecoder().decode(InstantLiveMessage.self, from: Data(string.utf8))
  }
}
