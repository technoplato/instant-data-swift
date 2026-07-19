import Dependencies
import Foundation
import InstantSwiftData
import PresenceRecipesV3App

public struct InstantCustomCursorsV3LiveValidationDetails: Codable, Equatable, Sendable {
  public var roomType: String
  public var roomID: String
  public var spaceID: String
  public var publishedName: String
  public var publishedCursor: CursorsV3Cursor
  public var observedName: String
  public var observedCursor: CursorsV3Cursor
  public var observedPeerID: String
  public var remoteCursorCount: Int
  public var remoteCursorCountAfterClear: Int
  public var remoteNamedPeerCountAfterClear: Int
  public var remotePeerCountAfterDisconnect: Int
  public var connectionState: String

  public init(
    roomType: String,
    roomID: String,
    spaceID: String,
    publishedName: String,
    publishedCursor: CursorsV3Cursor,
    observedName: String,
    observedCursor: CursorsV3Cursor,
    observedPeerID: String,
    remoteCursorCount: Int,
    remoteCursorCountAfterClear: Int,
    remoteNamedPeerCountAfterClear: Int,
    remotePeerCountAfterDisconnect: Int,
    connectionState: String
  ) {
    self.roomType = roomType
    self.roomID = roomID
    self.spaceID = spaceID
    self.publishedName = publishedName
    self.publishedCursor = publishedCursor
    self.observedName = observedName
    self.observedCursor = observedCursor
    self.observedPeerID = observedPeerID
    self.remoteCursorCount = remoteCursorCount
    self.remoteCursorCountAfterClear = remoteCursorCountAfterClear
    self.remoteNamedPeerCountAfterClear = remoteNamedPeerCountAfterClear
    self.remotePeerCountAfterDisconnect = remotePeerCountAfterDisconnect
    self.connectionState = connectionState
  }
}

public enum InstantCustomCursorsV3LiveValidation {
  public static let swiftName = "swift-custom-avatar"
  public static let typeScriptName = "typescript-custom-avatar"

  public static let swiftCursor = CursorsV3Cursor(
    x: 150,
    y: 90,
    xPercent: 25,
    yPercent: 40,
    color: "#123456"
  )

  public static let typeScriptCursor = CursorsV3Cursor(
    x: 300,
    y: 200,
    xPercent: 75,
    yPercent: 60,
    color: "#654321"
  )

  public static let swiftPresence = CustomCursorsV3Presence(
    userID: "swift-session",
    name: swiftName,
    cursor: swiftCursor
  )

  public static let typeScriptPresence = CustomCursorsV3Presence(
    userID: "typescript-session",
    name: typeScriptName,
    cursor: typeScriptCursor
  )

  public static func remoteCursorCount(
    in members: [InstantRoomPresenceMember],
    excludingUserID localUserID: String
  ) -> Int {
    members.count { member in
      member.userID != localUserID
        && member.values[CustomCursorsV3Room.defaultSpaceID] != nil
    }
  }

  public static func remoteNamedPeerCount(
    in members: [InstantRoomPresenceMember],
    excludingUserID localUserID: String
  ) -> Int {
    members.count { member in
      guard member.userID != localUserID else { return false }
      if case .string = member.values["name"] { return true }
      return false
    }
  }

  public static func remotePeerCount(
    in members: [InstantRoomPresenceMember],
    excludingUserID localUserID: String
  ) -> Int {
    members.count { $0.userID != localUserID }
  }

  public static func run(
    appID: String,
    apiURI: URL,
    websocketURI: URL,
    refreshToken: String,
    expectedUserID: String,
    roomID: String,
    persistenceURL: URL? = nil,
    onCursorObserved: @escaping @Sendable () -> Void = {},
    onCursorCleared: @escaping @Sendable () -> Void = {}
  ) async throws -> ValidationEvidenceRow<InstantCustomCursorsV3LiveValidationDetails> {
    let persistenceURL = persistenceURL ?? FileManager.default.temporaryDirectory
      .appendingPathComponent("instant-custom-cursors-v3-live-\(UUID().uuidString).sqlite")
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
      userID: "untrusted-swift-custom-cursors-user"
    )
    guard session.userID == expectedUserID else {
      throw failure("Server-verified Swift user did not match the expected custom cursor peer.")
    }

    let room = InstantRoomHandle(type: CustomCursorsV3Room.roomType, id: roomID)
    let stream = try await client.observeRoomPresence(room: room)
    _ = try await client.connect()
    _ = try await client.joinRoom(room)
    _ = try await client.setRoomPresence(
      room: room,
      values: [
        "name": .string(swiftName),
        CustomCursorsV3Room.defaultSpaceID: encode(swiftCursor),
      ]
    )

    let observed = try await withTimeout("observe TypeScript custom cursor") {
      try await matchingRemoteCursor(in: stream, excludingUserID: expectedUserID)
    }
    onCursorObserved()

    let cleared = try await withTimeout("observe TypeScript custom cursor clear") {
      try await matchingNameOnlyRemotePeer(in: stream, excludingUserID: expectedUserID)
    }
    onCursorCleared()

    let peerCountAfterDisconnect = try await withTimeout(
      "observe TypeScript custom cursor disconnect"
    ) {
      try await matchingRemotePeerCount(0, in: stream, excludingUserID: expectedUserID)
    }
    let status = try await client.connectionStatus()
    _ = try await client.leaveRoom(room)
    _ = try await client.closeConnection()

    return ValidationEvidenceRow(
      caseID: "validation.live.custom-cursors-v3",
      side: "swift",
      event: "named-cursor-publish-clear-disconnect-observed",
      appID: appID,
      entityID: roomID,
      timestampMs: Int64((Date().timeIntervalSince1970 * 1_000).rounded()),
      ok: true,
      details: InstantCustomCursorsV3LiveValidationDetails(
        roomType: room.type,
        roomID: room.id,
        spaceID: CustomCursorsV3Room.defaultSpaceID,
        publishedName: swiftName,
        publishedCursor: swiftCursor,
        observedName: observed.name,
        observedCursor: observed.cursor,
        observedPeerID: observed.peerID,
        remoteCursorCount: observed.remoteCursorCount,
        remoteCursorCountAfterClear: cleared.remoteCursorCount,
        remoteNamedPeerCountAfterClear: cleared.remoteNamedPeerCount,
        remotePeerCountAfterDisconnect: peerCountAfterDisconnect,
        connectionState: status.state.rawValue
      )
    )
  }

  private static func matchingRemoteCursor(
    in stream: AsyncStream<[InstantRoomPresenceMember]>,
    excludingUserID localUserID: String
  ) async throws -> (
    peerID: String,
    name: String,
    cursor: CursorsV3Cursor,
    remoteCursorCount: Int
  ) {
    for await members in stream {
      try Task.checkCancellation()
      for member in members where member.userID != localUserID {
        guard case let .string(name)? = member.values["name"],
          name == typeScriptName,
          let value = member.values[CustomCursorsV3Room.defaultSpaceID],
          let cursor = decodeCursor(value),
          cursor == typeScriptCursor
        else { continue }
        return (
          member.userID,
          name,
          cursor,
          remoteCursorCount(in: members, excludingUserID: localUserID)
        )
      }
    }
    throw failure("Presence observation ended before the exact TypeScript custom cursor arrived.")
  }

  private static func matchingNameOnlyRemotePeer(
    in stream: AsyncStream<[InstantRoomPresenceMember]>,
    excludingUserID localUserID: String
  ) async throws -> (remoteCursorCount: Int, remoteNamedPeerCount: Int) {
    for await members in stream {
      try Task.checkCancellation()
      let cursorCount = remoteCursorCount(in: members, excludingUserID: localUserID)
      let namedPeerCount = remoteNamedPeerCount(in: members, excludingUserID: localUserID)
      let hasExpectedName = members.contains { member in
        guard member.userID != localUserID,
          case let .string(name)? = member.values["name"]
        else { return false }
        return name == typeScriptName
          && member.values[CustomCursorsV3Room.defaultSpaceID] == nil
      }
      if cursorCount == 0, namedPeerCount == 1, hasExpectedName {
        return (cursorCount, namedPeerCount)
      }
    }
    throw failure("Presence observation ended before the TypeScript peer retained name-only presence.")
  }

  private static func matchingRemotePeerCount(
    _ count: Int,
    in stream: AsyncStream<[InstantRoomPresenceMember]>,
    excludingUserID localUserID: String
  ) async throws -> Int {
    for await members in stream {
      try Task.checkCancellation()
      if remotePeerCount(in: members, excludingUserID: localUserID) == count {
        return count
      }
    }
    throw failure("Presence observation ended before remote peer count \(count).")
  }

  private static func encode(_ cursor: CursorsV3Cursor) -> JSONValue {
    .object([
      "x": .number(cursor.x),
      "y": .number(cursor.y),
      "xPercent": .number(cursor.xPercent),
      "yPercent": .number(cursor.yPercent),
      "color": .string(cursor.color),
    ])
  }

  private static func decodeCursor(_ value: JSONValue) -> CursorsV3Cursor? {
    guard case let .object(object) = value,
      object.count == 5,
      case let .number(x)? = object["x"],
      case let .number(y)? = object["y"],
      case let .number(xPercent)? = object["xPercent"],
      case let .number(yPercent)? = object["yPercent"],
      case let .string(color)? = object["color"],
      x.isFinite,
      y.isFinite,
      xPercent.isFinite,
      yPercent.isFinite
    else { return nil }
    return CursorsV3Cursor(
      x: x,
      y: y,
      xPercent: xPercent,
      yPercent: yPercent,
      color: color
    )
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
      guard let value = try await group.next() else {
        throw failure("No result produced: \(operation).")
      }
      group.cancelAll()
      return value
    }
  }

  private static func failure(_ message: String) -> InstantError {
    InstantError(
      code: .implementationFailed,
      operation: "validate Custom Cursors V3 live presence",
      message: message,
      recovery: "Inspect the canonical TypeScript Custom Cursors peer lifecycle."
    )
  }
}
