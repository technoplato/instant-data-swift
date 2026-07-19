import Combine
import Dependencies
import Foundation

public struct TypingIndicatorPresence: Codable, Equatable, Sendable, Identifiable {
  public var id: String
  public var displayName: String
  public var chatInput: Bool?

  public init(id: String, displayName: String, chatInput: Bool?) {
    self.id = id
    self.displayName = displayName
    self.chatInput = chatInput
  }

  private enum CodingKeys: String, CodingKey {
    case id
    case displayName
    case chatInput = "chat-input"
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(String.self, forKey: .id)
    displayName = try container.decode(String.self, forKey: .displayName)
    chatInput = try container.decodeIfPresent(Bool.self, forKey: .chatInput)
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(id, forKey: .id)
    try container.encode(displayName, forKey: .displayName)
    if let chatInput {
      try container.encode(chatInput, forKey: .chatInput)
    } else {
      try container.encodeNil(forKey: .chatInput)
    }
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

@MainActor
public final class TypingIndicatorV3Model: ObservableObject {
  @Published public private(set) var presence: TypingIndicatorPresence
  @Published public private(set) var activePeers: [TypingIndicatorPresence] = []

  public let options: TypingIndicatorV3Options

  @Dependency(\.continuousClock) private var clock
  private var timeoutTask: Task<Void, Never>?

  public init(
    profileID: String,
    displayName: String,
    options: TypingIndicatorV3Options = TypingIndicatorV3Options()
  ) {
    presence = TypingIndicatorPresence(
      id: profileID,
      displayName: displayName,
      chatInput: nil
    )
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
    setActive(false)
  }

  public func setActive(_ isActive: Bool) {
    timeoutTask?.cancel()
    timeoutTask = nil
    presence.chatInput = isActive ? true : nil

    guard
      isActive,
      let timeout = options.timeout,
      timeout != .zero
    else { return }

    timeoutTask = Task { @MainActor [weak self, clock] in
      do {
        try await clock.sleep(for: timeout)
        try Task.checkCancellation()
        self?.presence.chatInput = nil
        self?.timeoutTask = nil
      } catch {
        // Cancellation is the normal result of another key event or cleanup.
      }
    }
  }
}
