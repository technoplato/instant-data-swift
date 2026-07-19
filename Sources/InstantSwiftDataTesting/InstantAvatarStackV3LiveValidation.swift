import Dependencies
import Foundation
import InstantSwiftData
import PresenceRecipesV3App

public struct InstantAvatarStackV3LiveValidationDetails: Codable, Equatable, Sendable {
  public var roomType: String
  public var roomID: String
  public var publishedPresence: AvatarStackV3Presence
  public var observedPresence: AvatarStackV3Presence
  public var observedPeerID: String
  public var peerCount: Int
  public var peerCountAfterDisconnect: Int
  public var connectionState: String

  public init(
    roomType: String,
    roomID: String,
    publishedPresence: AvatarStackV3Presence,
    observedPresence: AvatarStackV3Presence,
    observedPeerID: String,
    peerCount: Int,
    peerCountAfterDisconnect: Int,
    connectionState: String
  ) {
    self.roomType = roomType
    self.roomID = roomID
    self.publishedPresence = publishedPresence
    self.observedPresence = observedPresence
    self.observedPeerID = observedPeerID
    self.peerCount = peerCount
    self.peerCountAfterDisconnect = peerCountAfterDisconnect
    self.connectionState = connectionState
  }

  private enum CodingKeys: String, CodingKey {
    case roomType
    case roomID
    case publishedPresence
    case publishedUserID
    case observedPresence
    case observedUserID
    case observedPeerID
    case peerCount
    case peerCountAfterDisconnect
    case connectionState
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    roomType = try container.decode(String.self, forKey: .roomType)
    roomID = try container.decode(String.self, forKey: .roomID)
    publishedPresence = try container.decode(AvatarStackV3Presence.self, forKey: .publishedPresence)
    publishedPresence.userID = try container.decode(String.self, forKey: .publishedUserID)
    observedPresence = try container.decode(AvatarStackV3Presence.self, forKey: .observedPresence)
    observedPresence.userID = try container.decode(String.self, forKey: .observedUserID)
    observedPeerID = try container.decode(String.self, forKey: .observedPeerID)
    peerCount = try container.decode(Int.self, forKey: .peerCount)
    peerCountAfterDisconnect = try container.decode(Int.self, forKey: .peerCountAfterDisconnect)
    connectionState = try container.decode(String.self, forKey: .connectionState)
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(roomType, forKey: .roomType)
    try container.encode(roomID, forKey: .roomID)
    try container.encode(publishedPresence, forKey: .publishedPresence)
    try container.encode(publishedPresence.userID, forKey: .publishedUserID)
    try container.encode(observedPresence, forKey: .observedPresence)
    try container.encode(observedPresence.userID, forKey: .observedUserID)
    try container.encode(observedPeerID, forKey: .observedPeerID)
    try container.encode(peerCount, forKey: .peerCount)
    try container.encode(peerCountAfterDisconnect, forKey: .peerCountAfterDisconnect)
    try container.encode(connectionState, forKey: .connectionState)
  }
}

public enum InstantAvatarStackV3LiveValidation {
  public static let swiftPresence = AvatarStackV3Presence(
    userID: "abcdef123456",
    name: "abcdef"
  )
  public static let typeScriptPresence = AvatarStackV3Presence(
    userID: "uvwxyz123456",
    name: "uvwxyz"
  )

  public static func run(
    appID: String,
    apiURI: URL,
    websocketURI: URL,
    refreshToken: String,
    expectedUserID: String,
    roomID: String,
    persistenceURL: URL? = nil,
    onPresenceObserved: @escaping @Sendable () -> Void = {}
  ) async throws -> ValidationEvidenceRow<InstantAvatarStackV3LiveValidationDetails> {
    let persistenceURL = persistenceURL ?? FileManager.default.temporaryDirectory
      .appendingPathComponent("instant-avatar-stack-v3-live-\(UUID().uuidString).sqlite")
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
      userID: "untrusted-swift-avatar-user"
    )
    guard session.userID == expectedUserID else {
      throw failure("Server-verified Swift user did not match the expected avatar peer.")
    }

    let room = InstantRoomHandle(type: AvatarStackV3Room.roomType, id: roomID)
    let stream = try await client.observeRoomPresence(room: room)
    _ = try await client.connect()
    _ = try await client.joinRoom(room)
    _ = try await client.setRoomPresence(
      room: room,
      values: ["name": .string(swiftPresence.name)]
    )

    let observed = try await withTimeout("observe TypeScript avatar presence") {
      try await matchingPresence(name: typeScriptPresence.name, in: stream)
    }
    onPresenceObserved()
    let peerCountAfterDisconnect = try await withTimeout("observe avatar peer disconnect") {
      try await matchingPeerCount(0, in: stream)
    }
    let status = try await client.connectionStatus()
    _ = try await client.leaveRoom(room)
    _ = try await client.closeConnection()

    return ValidationEvidenceRow(
      caseID: "validation.live.avatar-stack-v3",
      side: "swift",
      event: "bidirectional-presence-observed",
      appID: appID,
      entityID: roomID,
      timestampMs: Int64((Date().timeIntervalSince1970 * 1_000).rounded()),
      ok: true,
      details: InstantAvatarStackV3LiveValidationDetails(
        roomType: room.type,
        roomID: room.id,
        publishedPresence: swiftPresence,
        observedPresence: AvatarStackV3Presence(
          userID: observed.peerID,
          name: observed.name
        ),
        observedPeerID: observed.peerID,
        peerCount: observed.peerCount,
        peerCountAfterDisconnect: peerCountAfterDisconnect,
        connectionState: status.state.rawValue
      )
    )
  }

  private static func matchingPresence(
    name: String,
    in stream: AsyncStream<[InstantRoomPresenceMember]>
  ) async throws -> (peerID: String, name: String, peerCount: Int) {
    for await members in stream {
      try Task.checkCancellation()
      if let member = members.first(where: { $0.values["name"] == .string(name) }) {
        return (member.userID, name, members.count)
      }
    }
    throw failure("Presence observation ended before the exact peer joined.")
  }

  private static func matchingPeerCount(
    _ count: Int,
    in stream: AsyncStream<[InstantRoomPresenceMember]>
  ) async throws -> Int {
    for await members in stream {
      try Task.checkCancellation()
      if members.count == count { return count }
    }
    throw failure("Presence observation ended before peer count \(count).")
  }

  private static func withTimeout<Value: Sendable>(
    _ operation: String,
    _ body: @escaping @Sendable () async throws -> Value
  ) async throws -> Value {
    try await withThrowingTaskGroup(of: Value.self) { group in
      group.addTask { try await body() }
      group.addTask {
        try await Task.sleep(for: .seconds(30))
        throw failure("Timed out: \(operation).")
      }
      guard let value = try await group.next() else { throw failure("No result produced.") }
      group.cancelAll()
      return value
    }
  }

  private static func failure(_ message: String) -> InstantError {
    InstantError(
      code: .implementationFailed,
      operation: "validate Avatar Stack V3 live presence",
      message: message,
      recovery: "Inspect the canonical TypeScript avatar-stack peer lifecycle."
    )
  }
}
