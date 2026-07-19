import Dependencies
import Foundation
import InstantSwiftData
import PresenceRecipesV3App

public struct InstantCursorsV3LiveValidationDetails: Codable, Equatable, Sendable {
  public var roomType: String
  public var roomID: String
  public var spaceID: String
  public var publishedCursor: CursorsV3Cursor
  public var observedCursor: CursorsV3Cursor
  public var observedPeerID: String
  public var remoteCursorCount: Int
  public var remoteCursorCountAfterClear: Int
  public var remotePeerCountAfterDisconnect: Int
  public var connectionState: String

  public init(
    roomType: String,
    roomID: String,
    spaceID: String,
    publishedCursor: CursorsV3Cursor,
    observedCursor: CursorsV3Cursor,
    observedPeerID: String,
    remoteCursorCount: Int,
    remoteCursorCountAfterClear: Int,
    remotePeerCountAfterDisconnect: Int,
    connectionState: String
  ) {
    self.roomType = roomType
    self.roomID = roomID
    self.spaceID = spaceID
    self.publishedCursor = publishedCursor
    self.observedCursor = observedCursor
    self.observedPeerID = observedPeerID
    self.remoteCursorCount = remoteCursorCount
    self.remoteCursorCountAfterClear = remoteCursorCountAfterClear
    self.remotePeerCountAfterDisconnect = remotePeerCountAfterDisconnect
    self.connectionState = connectionState
  }
}

public enum InstantCursorsV3LiveValidation {
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

  public static let swiftPresence = CursorsV3Presence(
    userID: "swift-session",
    cursor: swiftCursor
  )

  public static let typeScriptPresence = CursorsV3Presence(
    userID: "typescript-session",
    cursor: typeScriptCursor
  )

  public static func remoteCursorCount(
    in members: [InstantRoomPresenceMember],
    excludingUserID localUserID: String
  ) -> Int {
    members.count { member in
      member.userID != localUserID
        && member.values[CursorsV3Room.defaultSpaceID] != nil
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
  ) async throws -> ValidationEvidenceRow<InstantCursorsV3LiveValidationDetails> {
    let persistenceURL = persistenceURL ?? FileManager.default.temporaryDirectory
      .appendingPathComponent("instant-cursors-v3-live-\(UUID().uuidString).sqlite")
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
      userID: "untrusted-swift-cursors-user"
    )
    guard session.userID == expectedUserID else {
      throw failure("Server-verified Swift user did not match the expected cursors peer.")
    }

    let room = InstantRoomHandle(type: CursorsV3Room.roomType, id: roomID)
    let stream = try await client.observeRoomPresence(room: room)
    _ = try await client.connect()
    _ = try await client.joinRoom(room)
    _ = try await client.setRoomPresence(
      room: room,
      values: [CursorsV3Room.defaultSpaceID: encode(swiftCursor)]
    )

    let observed = try await withTimeout("observe TypeScript cursor") {
      try await matchingRemoteCursor(
        in: stream,
        excludingUserID: expectedUserID
      )
    }
    onCursorObserved()

    let cursorCountAfterClear = try await withTimeout("observe TypeScript cursor clear") {
      try await matchingRemoteCursorCount(
        0,
        in: stream,
        excludingUserID: expectedUserID
      )
    }
    onCursorCleared()

    let peerCountAfterDisconnect = try await withTimeout("observe TypeScript cursor disconnect") {
      try await matchingRemotePeerCount(
        0,
        in: stream,
        excludingUserID: expectedUserID
      )
    }
    let status = try await client.connectionStatus()
    _ = try await client.leaveRoom(room)
    _ = try await client.closeConnection()

    return ValidationEvidenceRow(
      caseID: "validation.live.cursors-v3",
      side: "swift",
      event: "cursor-publish-clear-disconnect-observed",
      appID: appID,
      entityID: roomID,
      timestampMs: Int64((Date().timeIntervalSince1970 * 1_000).rounded()),
      ok: true,
      details: InstantCursorsV3LiveValidationDetails(
        roomType: room.type,
        roomID: room.id,
        spaceID: CursorsV3Room.defaultSpaceID,
        publishedCursor: swiftCursor,
        observedCursor: observed.cursor,
        observedPeerID: observed.peerID,
        remoteCursorCount: observed.remoteCursorCount,
        remoteCursorCountAfterClear: cursorCountAfterClear,
        remotePeerCountAfterDisconnect: peerCountAfterDisconnect,
        connectionState: status.state.rawValue
      )
    )
  }

  private static func matchingRemoteCursor(
    in stream: AsyncStream<[InstantRoomPresenceMember]>,
    excludingUserID localUserID: String
  ) async throws -> (peerID: String, cursor: CursorsV3Cursor, remoteCursorCount: Int) {
    for await members in stream {
      try Task.checkCancellation()
      for member in members where member.userID != localUserID {
        guard let value = member.values[CursorsV3Room.defaultSpaceID],
          let cursor = decodeCursor(value),
          cursor == typeScriptCursor
        else { continue }
        return (
          member.userID,
          cursor,
          remoteCursorCount(in: members, excludingUserID: localUserID)
        )
      }
    }
    throw failure("Presence observation ended before the exact TypeScript cursor arrived.")
  }

  private static func matchingRemoteCursorCount(
    _ count: Int,
    in stream: AsyncStream<[InstantRoomPresenceMember]>,
    excludingUserID localUserID: String
  ) async throws -> Int {
    for await members in stream {
      try Task.checkCancellation()
      if remoteCursorCount(in: members, excludingUserID: localUserID) == count {
        return count
      }
    }
    throw failure("Presence observation ended before remote cursor count \(count).")
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
      operation: "validate Cursors V3 live presence",
      message: message,
      recovery: "Inspect the canonical TypeScript Cursors peer lifecycle."
    )
  }
}
