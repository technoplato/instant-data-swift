import Dependencies
import Foundation
import InstantSwiftData

public struct InstantTypingIndicatorPresenceFrame: Codable, Equatable, Sendable {
  public var phase: String
  public var presence: [String: JSONValue]

  public init(phase: String, presence: [String: JSONValue]) {
    self.phase = phase
    self.presence = presence
  }
}

public struct InstantTypingIndicatorV3LiveValidationDetails: Codable, Equatable, Sendable {
  public var roomType: String
  public var roomID: String
  public var swiftUserID: String
  public var typeScriptUserID: String
  public var publishedFrames: [InstantTypingIndicatorPresenceFrame]
  public var observedFrames: [InstantTypingIndicatorPresenceFrame]
  public var activePeerIDs: [String]
  public var peerCountAfterDisconnect: Int
  public var typeScriptPatchNormalizations: [String]
  public var connectionState: String

  public init(
    roomType: String,
    roomID: String,
    swiftUserID: String,
    typeScriptUserID: String,
    publishedFrames: [InstantTypingIndicatorPresenceFrame],
    observedFrames: [InstantTypingIndicatorPresenceFrame],
    activePeerIDs: [String],
    peerCountAfterDisconnect: Int,
    typeScriptPatchNormalizations: [String],
    connectionState: String
  ) {
    self.roomType = roomType
    self.roomID = roomID
    self.swiftUserID = swiftUserID
    self.typeScriptUserID = typeScriptUserID
    self.publishedFrames = publishedFrames
    self.observedFrames = observedFrames
    self.activePeerIDs = activePeerIDs
    self.peerCountAfterDisconnect = peerCountAfterDisconnect
    self.typeScriptPatchNormalizations = typeScriptPatchNormalizations
    self.connectionState = connectionState
  }
}

public enum InstantTypingIndicatorV3LiveValidation {
  public static func run(
    appID: String,
    apiURI: URL,
    websocketURI: URL,
    refreshToken: String,
    swiftUserID: String,
    typeScriptUserID: String,
    roomID: String,
    persistenceURL: URL? = nil,
    onFramesObserved: @escaping @Sendable () -> Void = {}
  ) async throws -> ValidationEvidenceRow<InstantTypingIndicatorV3LiveValidationDetails> {
    let persistenceURL = persistenceURL ?? FileManager.default.temporaryDirectory
      .appendingPathComponent("instant-typing-indicator-live-\(UUID().uuidString).sqlite")
    let client = try await withDependencies {
      $0.context = .live
      $0.instantLiveTransport = .live
      try await $0.bootstrapInstantSwiftData(
        appID: appID,
        apiURI: apiURI,
        websocketURI: websocketURI,
        persistenceURL: persistenceURL,
        context: .live
      )
    } operation: {
      @Dependency(\.defaultInstantSwiftData) var client
      return client
    }

    let session = try await client.signInWithRefreshToken(
      refreshToken,
      userID: "untrusted-swift-typing-user"
    )
    guard session.userID == swiftUserID else {
      throw validationFailure(
        operation: "validate typing indicator auth",
        message: "Server-verified Swift user did not match the expected typing peer."
      )
    }

    let room = InstantRoomHandle(type: "typing-indicator-example", id: roomID)
    let presenceStream = try await client.observeRoomPresence(room: room)
    _ = try await client.connect()
    _ = try await client.joinRoom(room)

    let publishedFrames = frames(peerID: "swift-peer")
    let expectedFrames = frames(peerID: "typescript-peer")
    var observedFrames: [InstantTypingIndicatorPresenceFrame] = []

    for (published, expected) in zip(publishedFrames, expectedFrames) {
      let observation = Task {
        try await withTimeout(operation: "observe TypeScript typing frame \(expected.phase)") {
          try await matchingFrame(expected, in: presenceStream)
        }
      }
      _ = try await client.setRoomPresence(room: room, values: published.presence)
      observedFrames.append(try await observation.value)
    }

    let activePeerIDs = observedFrames.compactMap { frame -> String? in
      guard frame.phase == "active",
        frame.presence["chat-input"] == .bool(true),
        case let .string(peerID)? = frame.presence["id"]
      else { return nil }
      return peerID
    }
    onFramesObserved()
    let peerCountAfterDisconnect = try await withTimeout(
      operation: "observe TypeScript typing peer disconnect"
    ) {
      try await matchingPeerCount(0, excludingPeerID: "swift-peer", in: presenceStream)
    }

    let status = try await client.connectionStatus()
    _ = try await client.leaveRoom(room)
    _ = try await client.closeConnection()

    return ValidationEvidenceRow(
      caseID: "validation.live.typing-indicator-v3",
      side: "swift",
      event: "bidirectional-presence-frames-observed",
      appID: appID,
      entityID: roomID,
      timestampMs: Int64((Date().timeIntervalSince1970 * 1_000).rounded()),
      ok: true,
      details: InstantTypingIndicatorV3LiveValidationDetails(
        roomType: room.type,
        roomID: room.id,
        swiftUserID: swiftUserID,
        typeScriptUserID: typeScriptUserID,
        publishedFrames: publishedFrames,
        observedFrames: observedFrames,
        activePeerIDs: activePeerIDs,
        peerCountAfterDisconnect: peerCountAfterDisconnect,
        typeScriptPatchNormalizations: ["chat-input:null-to-absent"],
        connectionState: status.state.rawValue
      )
    )
  }

  public static func frames(peerID: String) -> [InstantTypingIndicatorPresenceFrame] {
    [
      InstantTypingIndicatorPresenceFrame(
        phase: "initial",
        presence: ["id": .string(peerID)]
      ),
      InstantTypingIndicatorPresenceFrame(
        phase: "active",
        presence: ["id": .string(peerID), "chat-input": .bool(true)]
      ),
      InstantTypingIndicatorPresenceFrame(
        phase: "inactive",
        presence: ["id": .string(peerID), "chat-input": .bool(false)]
      ),
      InstantTypingIndicatorPresenceFrame(
        phase: "cleared",
        presence: ["id": .string(peerID), "chat-input": .null]
      ),
    ]
  }

  private static func matchingFrame(
    _ expected: InstantTypingIndicatorPresenceFrame,
    in stream: AsyncStream<[InstantRoomPresenceMember]>
  ) async throws -> InstantTypingIndicatorPresenceFrame {
    guard case let .string(expectedPeerID)? = expected.presence["id"] else {
      throw validationFailure(
        operation: "match typing indicator frame",
        message: "Expected typing frame is missing its peer id."
      )
    }

    for await members in stream {
      try Task.checkCancellation()
      guard let member = members.first(where: { member in
        member.values["id"] == .string(expectedPeerID)
      }) else { continue }
      let presence = member.values.filter { key, _ in
        key == "id" || key == "chat-input"
      }
      let serverNormalizedClear = expected.phase == "cleared"
        && presence["id"] == expected.presence["id"]
        && presence["chat-input"] == nil
      if presence == expected.presence || serverNormalizedClear {
        return InstantTypingIndicatorPresenceFrame(
          phase: expected.phase,
          presence: presence
        )
      }
    }
    throw validationFailure(
      operation: "match typing indicator frame",
      message: "Presence observation ended before frame \(expected.phase)."
    )
  }

  private static func matchingPeerCount(
    _ expectedCount: Int,
    excludingPeerID: String,
    in stream: AsyncStream<[InstantRoomPresenceMember]>
  ) async throws -> Int {
    for await members in stream {
      try Task.checkCancellation()
      let remoteCount = members.filter {
        $0.values["id"] != .string(excludingPeerID)
      }.count
      if remoteCount == expectedCount { return remoteCount }
    }
    throw validationFailure(
      operation: "match typing indicator peer count",
      message: "Presence observation ended before peer count \(expectedCount)."
    )
  }

  private static func withTimeout<Value: Sendable>(
    operation: String,
    _ body: @escaping @Sendable () async throws -> Value
  ) async throws -> Value {
    try await withThrowingTaskGroup(of: Value.self) { group in
      group.addTask { try await body() }
      group.addTask {
        try await Task.sleep(for: .seconds(30))
        throw validationFailure(
          operation: operation,
          message: "Timed out after 30 seconds."
        )
      }
      guard let value = try await group.next() else {
        throw validationFailure(operation: operation, message: "No result was produced.")
      }
      group.cancelAll()
      return value
    }
  }

  private static func validationFailure(
    operation: String,
    message: String
  ) -> InstantError {
    InstantError(
      code: .implementationFailed,
      operation: operation,
      message: message,
      recovery: "Inspect the canonical TypeScript typing-indicator peer and room lifecycle."
    )
  }
}
