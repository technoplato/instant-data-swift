import Dependencies
import Foundation
import InstantSwiftData
import PresenceRecipesV3App

public struct InstantMergeTileGameV3LiveCell: Codable, Equatable, Sendable {
  public var cell: String
  public var color: String

  public init(cell: String, color: String) {
    self.cell = cell
    self.color = color
  }
}

public struct InstantMergeTileGameV3LiveValidationDetails: Codable, Equatable, Sendable {
  public var boardID: String
  public var roomType: String
  public var roomID: String
  public var publishedCell: InstantMergeTileGameV3LiveCell
  public var observedCell: InstantMergeTileGameV3LiveCell
  public var boardStateAfterBothMerges: [String: String]
  public var boardStateAfterReset: [String: String]
  public var observedPeerID: String
  public var remoteColorPeerCount: Int
  public var remotePeerCountAfterDisconnect: Int
  public var connectionState: String

  public init(
    boardID: String,
    roomType: String,
    roomID: String,
    publishedCell: InstantMergeTileGameV3LiveCell,
    observedCell: InstantMergeTileGameV3LiveCell,
    boardStateAfterBothMerges: [String: String],
    boardStateAfterReset: [String: String],
    observedPeerID: String,
    remoteColorPeerCount: Int,
    remotePeerCountAfterDisconnect: Int,
    connectionState: String
  ) {
    self.boardID = boardID
    self.roomType = roomType
    self.roomID = roomID
    self.publishedCell = publishedCell
    self.observedCell = observedCell
    self.boardStateAfterBothMerges = boardStateAfterBothMerges
    self.boardStateAfterReset = boardStateAfterReset
    self.observedPeerID = observedPeerID
    self.remoteColorPeerCount = remoteColorPeerCount
    self.remotePeerCountAfterDisconnect = remotePeerCountAfterDisconnect
    self.connectionState = connectionState
  }
}

@MainActor
private final class MergeTileGameV3MessageOutcome {
  var accepted = false
  var failure: InstantError?
}

public enum InstantMergeTileGameV3LiveValidation {
  public static let swiftCell = InstantMergeTileGameV3LiveCell(
    cell: "0-0",
    color: "#e76f51"
  )
  public static let typeScriptCell = InstantMergeTileGameV3LiveCell(
    cell: "0-1",
    color: "#2a9d8f"
  )
  public static let swiftPresence = MergeTileGameV3Presence(
    userID: "swift-session",
    color: swiftCell.color
  )
  public static let typeScriptPresence = MergeTileGameV3Presence(
    userID: "typescript-session",
    color: typeScriptCell.color
  )

  public static func merge(
    _ cell: InstantMergeTileGameV3LiveCell,
    into state: inout [String: String]
  ) {
    state[cell.cell] = cell.color
  }

  public static func reset(_ state: inout [String: String]) {
    state = MergeTileGameV3Board.emptyState
  }

  public static func remoteColorPeerCount(
    in members: [InstantRoomPresenceMember],
    excludingUserID localUserID: String
  ) -> Int {
    members.count { member in
      guard member.userID != localUserID,
        case let .string(color)? = member.values["color"]
      else { return false }
      return MergeTileGameV3Board.colors.contains(color)
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
    persistenceURL: URL? = nil,
    onSwiftReady: @escaping @Sendable () -> Void = {},
    onTypeScriptMergeObserved: @escaping @Sendable () -> Void = {},
    onResetObserved: @escaping @Sendable () -> Void = {}
  ) async throws -> ValidationEvidenceRow<InstantMergeTileGameV3LiveValidationDetails> {
    let client = try await liveClient(
      appID: appID,
      apiURI: apiURI,
      websocketURI: websocketURI,
      persistenceURL: persistenceURL
    )
    try await authenticate(
      client,
      refreshToken: refreshToken,
      expectedUserID: expectedUserID
    )

    let rows = FetchOne(MergeTileGameV3Board.fixedQuery)
    let rowsTask = Task {
      try await rows.task(MergeTileGameV3Board.fixedQuery, using: client)
    }
    defer { rowsTask.cancel() }

    let room = InstantRoomHandle(
      type: MergeTileGameV3Room.roomType,
      id: MergeTileGameV3Room.defaultRoomID
    )
    let presence = try await client.observeRoomPresence(room: room)
    _ = try await client.joinRoom(room)
    _ = try await client.setRoomPresence(
      room: room,
      values: ["color": .string(swiftPresence.color)]
    )
    try await sendAndRequireServerAcceptance(
      InitializeMergeTileGameV3Board(),
      using: client,
      operation: "initialize Merge Tile Game board"
    )
    try await sendAndRequireServerAcceptance(
      PaintMergeTileGameV3Cell(row: 0, column: 0, color: swiftCell.color),
      using: client,
      operation: "merge Swift tile"
    )
    _ = try await waitForBoard(rows) { state in
      state[swiftCell.cell] == swiftCell.color
    }
    onSwiftReady()

    let peer = try await waitForTypeScriptPeer(
      in: presence,
      excludingUserID: expectedUserID
    )
    let mergedState = try await waitForBoard(rows) { state in
      state[swiftCell.cell] == swiftCell.color
        && state[typeScriptCell.cell] == typeScriptCell.color
    }
    onTypeScriptMergeObserved()

    let resetState = try await waitForBoard(rows) { $0 == MergeTileGameV3Board.emptyState }
    onResetObserved()
    let remotePeerCountAfterDisconnect = try await waitForRemotePeerCount(
      0,
      in: presence,
      excludingUserID: expectedUserID
    )
    let status = try await client.connectionStatus()
    _ = try await client.leaveRoom(room)
    _ = try await client.closeConnection()

    return ValidationEvidenceRow(
      caseID: "validation.live.merge-tile-game-v3",
      side: "swift",
      event: "independent-merges-reset-and-disconnect-observed",
      appID: appID,
      entityID: MergeTileGameV3Board.boardID,
      timestampMs: Int64((Date().timeIntervalSince1970 * 1_000).rounded()),
      ok: true,
      details: InstantMergeTileGameV3LiveValidationDetails(
        boardID: MergeTileGameV3Board.boardID,
        roomType: room.type,
        roomID: room.id,
        publishedCell: swiftCell,
        observedCell: typeScriptCell,
        boardStateAfterBothMerges: mergedState,
        boardStateAfterReset: resetState,
        observedPeerID: peer.peerID,
        remoteColorPeerCount: peer.remoteColorPeerCount,
        remotePeerCountAfterDisconnect: remotePeerCountAfterDisconnect,
        connectionState: status.state.rawValue
      )
    )
  }

  private static func liveClient(
    appID: String,
    apiURI: URL,
    websocketURI: URL,
    persistenceURL: URL?
  ) async throws -> InstantSwiftDataClient {
    try await withDependencies {
      $0.context = .live
      $0.instantLiveTransport = .live
      try await $0.bootstrapInstantSwiftData(
        appID: appID,
        apiURI: apiURI,
        websocketURI: websocketURI,
        persistenceURL: persistenceURL
          ?? FileManager.default.temporaryDirectory
          .appendingPathComponent("instant-merge-tile-v3-live-\(UUID().uuidString).sqlite"),
        context: .live,
        initialAttributes: MergeTileGameV3Board.instantAttributes
      )
    } operation: {
      @Dependency(\.defaultInstantSwiftData) var client
      return client
    }
  }

  private static func authenticate(
    _ client: InstantSwiftDataClient,
    refreshToken: String,
    expectedUserID: String
  ) async throws {
    let session = try await client.signInWithRefreshToken(
      refreshToken,
      userID: "untrusted-swift-merge-tile-user"
    )
    guard session.userID == expectedUserID else {
      throw failure("Server-verified Swift user did not match the expected merge tile peer.")
    }
    _ = try await client.connect()
    let deadline = ContinuousClock.now + .seconds(15)
    while ContinuousClock.now < deadline {
      if try await client.connectionStatus().state == .authenticated { return }
      try await Task.sleep(for: .milliseconds(25))
    }
    throw failure("The Merge Tile Game client did not reach authenticated state.")
  }

  private static func sendAndRequireServerAcceptance<Message: InstantMessage>(
    _ message: Message,
    using client: InstantSwiftDataClient,
    operation: String
  ) async throws {
    let outcome = await MainActor.run { MergeTileGameV3MessageOutcome() }
    let task = client.send(
      message,
      onServerAccepted: { _ in outcome.accepted = true },
      onFailure: { outcome.failure = $0 }
    )
    defer { task.cancel() }
    try await withTimeout(operation) { await task.value }
    let result = await MainActor.run { (outcome.accepted, outcome.failure) }
    if let error = result.1 { throw error }
    guard result.0 else { throw failure("\(operation) completed without server acceptance.") }
  }

  private static func waitForBoard(
    _ rows: FetchOne<MergeTileGameV3Board?>,
    matching predicate: @escaping @Sendable ([String: String]) -> Bool
  ) async throws -> [String: String] {
    try await withTimeout("observe Merge Tile Game board") {
      while true {
        if let state = rows.wrappedValue?.stateObject, predicate(state) { return state }
        try await Task.sleep(for: .milliseconds(25))
      }
    }
  }

  private static func waitForTypeScriptPeer(
    in stream: AsyncStream<[InstantRoomPresenceMember]>,
    excludingUserID localUserID: String
  ) async throws -> (peerID: String, remoteColorPeerCount: Int) {
    try await withTimeout("observe TypeScript Merge Tile Game peer") {
      for await members in stream {
        for member in members where member.userID != localUserID {
          guard case let .string(color)? = member.values["color"],
            color == typeScriptPresence.color
          else { continue }
          return (
            member.userID,
            remoteColorPeerCount(in: members, excludingUserID: localUserID)
          )
        }
      }
      throw failure("Presence ended before the TypeScript color peer arrived.")
    }
  }

  private static func waitForRemotePeerCount(
    _ count: Int,
    in stream: AsyncStream<[InstantRoomPresenceMember]>,
    excludingUserID localUserID: String
  ) async throws -> Int {
    try await withTimeout("observe Merge Tile Game disconnect") {
      for await members in stream {
        if remotePeerCount(in: members, excludingUserID: localUserID) == count {
          return count
        }
      }
      throw failure("Presence ended before remote peer count \(count).")
    }
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
      operation: "validate Merge Tile Game V3 live contract",
      message: message,
      recovery: "Inspect the canonical TypeScript board merge and room presence lifecycle."
    )
  }
}
