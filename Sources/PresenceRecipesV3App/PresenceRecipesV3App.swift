import Combine
import Dependencies
import Foundation
import InstantSwiftData

public struct TypingIndicatorPresence: Codable, Equatable, Sendable, Identifiable {
  public var id: String

  private var chatInputState: ChatInputState

  public var chatInput: Bool? {
    guard case let .value(value) = chatInputState else { return nil }
    return value
  }

  public init(id: String) {
    self.id = id
    self.chatInputState = .omitted
  }

  public init(id: String, chatInput: Bool?) {
    self.id = id
    self.chatInputState = chatInput.map(ChatInputState.value) ?? .null
  }

  private enum CodingKeys: String, CodingKey {
    case id
    case chatInput = "chat-input"
  }

  private enum ChatInputState: Equatable, Sendable {
    case omitted
    case value(Bool)
    case null
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(String.self, forKey: .id)
    if !container.contains(.chatInput) {
      chatInputState = .omitted
    } else if try container.decodeNil(forKey: .chatInput) {
      chatInputState = .null
    } else {
      chatInputState = .value(try container.decode(Bool.self, forKey: .chatInput))
    }
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(id, forKey: .id)
    switch chatInputState {
    case .omitted:
      break
    case let .value(value):
      try container.encode(value, forKey: .chatInput)
    case .null:
      try container.encodeNil(forKey: .chatInput)
    }
  }

  mutating func setChatInput(_ value: Bool) {
    chatInputState = .value(value)
  }

  mutating func clearChatInput() {
    chatInputState = .null
  }
}

public struct TypingIndicatorV3Options: Equatable, Sendable {
  public var timeout: Duration?
  public var stopOnSubmit: Bool
  public var writeOnly: Bool

  public init(
    timeout: Duration? = .seconds(1),
    stopOnSubmit: Bool = false,
    writeOnly: Bool = false
  ) {
    self.timeout = timeout
    self.stopOnSubmit = stopOnSubmit
    self.writeOnly = writeOnly
  }
}

public enum TypingIndicatorV3Key: Equatable, Sendable {
  case character
  case submit
}

public struct TypingIndicatorV3Room: InstantRoomSchema {
  public typealias Presence = TypingIndicatorPresence
  public static let roomType = "typing-indicator-example"

  public struct Topic: InstantRoomTopic {
    public typealias RoomSchema = TypingIndicatorV3Room

    public let rawValue: String

    public init?(rawValue: String) {
      return nil
    }
  }
}

@MainActor
public final class TypingIndicatorV3Model: ObservableObject {
  @Published public private(set) var presence: TypingIndicatorPresence
  @Published public private(set) var activePeers: [TypingIndicatorPresence] = []

  public let options: TypingIndicatorV3Options

  @Dependency(\.continuousClock) private var clock
  private var timeoutTask: Task<Void, Never>?

  public init(
    profileID: String,
    options: TypingIndicatorV3Options = TypingIndicatorV3Options()
  ) {
    presence = TypingIndicatorPresence(id: profileID)
    self.options = options
  }

  public func updatePeers(_ peers: [TypingIndicatorPresence]) {
    activePeers = options.writeOnly
      ? []
      : peers.filter { $0.id != presence.id && $0.chatInput == true }
  }

  public func keyDown(_ key: TypingIndicatorV3Key) {
    setActive(!(options.stopOnSubmit && key == .submit))
  }

  public func blur() {
    setActive(false)
  }

  public func stop() {
    timeoutTask?.cancel()
    timeoutTask = nil
    presence.clearChatInput()
  }

  public func setActive(_ isActive: Bool) {
    timeoutTask?.cancel()
    timeoutTask = nil
    presence.setChatInput(isActive)

    guard
      isActive,
      let timeout = options.timeout,
      timeout != .zero
    else { return }

    timeoutTask = Task { @MainActor [weak self, clock] in
      do {
        try await clock.sleep(for: timeout)
        try Task.checkCancellation()
        self?.presence.clearChatInput()
        self?.timeoutTask = nil
      } catch {
        // Cancellation is the normal result of another key event or cleanup.
      }
    }
  }
}
