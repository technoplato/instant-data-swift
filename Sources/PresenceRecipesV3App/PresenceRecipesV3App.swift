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

public struct ReactionsV3Presence: Codable, Equatable, Sendable {
  public init() {}
}

public enum ReactionsV3Name: String, Codable, CaseIterable, Sendable {
  case fire
  case wave
  case confetti
  case heart

  public var symbol: String {
    switch self {
    case .fire: "🔥"
    case .wave: "👋"
    case .confetti: "🎉"
    case .heart: "❤️"
    }
  }
}

public struct ReactionsV3Payload: Codable, Equatable, Sendable {
  public var name: String
  public var directionAngle: Double
  public var rotationAngle: Double

  public init(
    name: String,
    directionAngle: Double,
    rotationAngle: Double
  ) {
    self.name = name
    self.directionAngle = directionAngle
    self.rotationAngle = rotationAngle
  }
}

public struct ReactionsV3Room: InstantRoomSchema {
  public typealias Presence = ReactionsV3Presence
  public static let roomType = "topics-example"

  public enum Topic: String, InstantRoomTopic {
    public typealias RoomSchema = ReactionsV3Room
    case emoji
  }
}

public struct ReactionsV3Animation: Equatable, Identifiable, Sendable {
  public var id: UUID
  public var name: ReactionsV3Name
  public var payload: ReactionsV3Payload

  public init(
    id: UUID = UUID(),
    name: ReactionsV3Name,
    payload: ReactionsV3Payload
  ) {
    self.id = id
    self.name = name
    self.payload = payload
  }
}

@MainActor
public final class ReactionsV3Model: ObservableObject {
  @Published public private(set) var animations: [ReactionsV3Animation] = []

  private var observedMessageCount = 0

  public init() {}

  @discardableResult
  public func reactionButtonTapped(
    _ name: ReactionsV3Name,
    directionAngle: Double,
    rotationAngle: Double
  ) -> ReactionsV3Payload {
    let payload = ReactionsV3Payload(
      name: name.rawValue,
      directionAngle: directionAngle,
      rotationAngle: rotationAngle
    )
    animate(payload)
    return payload
  }

  public func observe(_ payloads: [ReactionsV3Payload]) {
    if payloads.count < observedMessageCount {
      observedMessageCount = 0
    }
    let newPayloads = payloads.dropFirst(observedMessageCount)
    observedMessageCount = payloads.count
    for payload in newPayloads {
      animate(payload)
    }
  }

  public func dismissAnimation(id: ReactionsV3Animation.ID) {
    animations.removeAll { $0.id == id }
  }

  private func animate(_ payload: ReactionsV3Payload) {
    guard let name = ReactionsV3Name(rawValue: payload.name) else { return }
    animations.append(ReactionsV3Animation(name: name, payload: payload))
  }
}
