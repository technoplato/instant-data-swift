import Foundation

public struct MergeTileGameBoard: Hashable, Codable, Sendable, Identifiable {
  public var id: String
  public var state: [String: String]
  public var filledCount: Int

  public init(id: String, state: [String: String], filledCount: Int) {
    self.id = id
    self.state = state
    self.filledCount = filledCount
  }
}

public struct MergeTileGamePlayer: Hashable, Codable, Sendable, Identifiable {
  public var id: String { userID }
  public var userID: String
  public var color: String
  public var isViewer: Bool
  public var updatedAt: InstantTimestamp

  public init(
    userID: String,
    color: String,
    isViewer: Bool,
    updatedAt: InstantTimestamp
  ) {
    self.userID = userID
    self.color = color
    self.isViewer = isViewer
    self.updatedAt = updatedAt
  }
}

public struct MergeTileGameSnapshot: Hashable, Codable, Sendable {
  public var viewerUserID: String?
  public var board: MergeTileGameBoard?
  public var playerCount: Int
  public var currentPlayer: MergeTileGamePlayer?
  public var peers: [MergeTileGamePlayer]
  public var players: [MergeTileGamePlayer]
  public var availableColors: [String]

  public init(
    viewerUserID: String?,
    board: MergeTileGameBoard?,
    playerCount: Int,
    currentPlayer: MergeTileGamePlayer?,
    peers: [MergeTileGamePlayer],
    players: [MergeTileGamePlayer],
    availableColors: [String]
  ) {
    self.viewerUserID = viewerUserID
    self.board = board
    self.playerCount = playerCount
    self.currentPlayer = currentPlayer
    self.peers = peers
    self.players = players
    self.availableColors = availableColors
  }
}

public enum MergeTileGameRecipeExample {
  public static let namespace = "boards"
  public static let boardID = "83c059e2-ed47-42e5-bdd9-6de88d26c521"
  public static let boardSize = 4
  public static let emptyColor = "#f5f3f0"
  public static let colorKey = "color"
  public static let room = InstantRoomHandle(
    type: "tile-game-example",
    id: "_defaultRoomId"
  )
  public static let colors = [
    "#e76f51",
    "#2a9d8f",
    "#e9c46a",
    "#264653",
    "#f4a261",
    "#d4a0d0",
  ]

  public static let attributes: [InstantAttribute] = [
    .primaryKey(namespace: namespace),
    InstantAttribute(
      id: "boards/state",
      namespace: namespace,
      name: "state",
      valueType: .json,
      isIndexed: true
    ),
  ]

  public static let boardQuery = InstantQueryPlan(
    id: "examples.merge-tile-game.board",
    namespace: namespace,
    filters: [.equals(field: "id", value: .string(boardID))]
  )

  public static func cellKey(row: Int, column: Int) -> String {
    "\(row)-\(column)"
  }

  public static func isValidCell(row: Int, column: Int) -> Bool {
    (0..<boardSize).contains(row) && (0..<boardSize).contains(column)
  }

  public static func makeEmptyBoardState() -> [String: String] {
    Dictionary(
      uniqueKeysWithValues: (0..<boardSize).flatMap { row in
        (0..<boardSize).map { column in
          (cellKey(row: row, column: column), emptyColor)
        }
      }
    )
  }

  public static func makeEmptyBoardJSON() -> [String: JSONValue] {
    makeEmptyBoardState().mapValues(JSONValue.string)
  }

  public static func presenceValues(color: String) -> [String: JSONValue] {
    [colorKey: .string(color)]
  }

  public static func availableColors(from players: [MergeTileGamePlayer]) -> [String] {
    let takenColors = Set(players.map(\.color))
    return colors.filter { !takenColors.contains($0) }
  }

  public static func selectedColor(
    requestedColor: String?,
    players: [MergeTileGamePlayer]
  ) -> String {
    if let requestedColor {
      return requestedColor
    }
    return availableColors(from: players).first ?? colors[0]
  }

  public static func createBoardOperations(
    transactionID: String,
    createdAt: InstantTimestamp
  ) -> [InstantTripleOperation] {
    [
      .requireEntityMissing(entityID: boardID, namespace: namespace),
      identityOperation(updatedAt: createdAt, transactionID: transactionID),
      stateInsertOperation(state: makeEmptyBoardJSON(), updatedAt: createdAt, transactionID: transactionID),
    ]
  }

  public static func resetBoardOperations(
    transactionID: String,
    updatedAt: InstantTimestamp
  ) -> [InstantTripleOperation] {
    [
      identityOperation(updatedAt: updatedAt, transactionID: transactionID),
      stateInsertOperation(state: makeEmptyBoardJSON(), updatedAt: updatedAt, transactionID: transactionID),
    ]
  }

  public static func tapOperations(
    row: Int,
    column: Int,
    color: String,
    transactionID: String,
    updatedAt: InstantTimestamp
  ) -> [InstantTripleOperation] {
    [
      .requireEntityExists(entityID: boardID, namespace: namespace),
      identityOperation(updatedAt: updatedAt, transactionID: transactionID),
      .merge(
        InstantTriple(
          entityID: boardID,
          attributeID: "boards/state",
          value: .json(.object([cellKey(row: row, column: column): .string(color)])),
          txID: transactionID,
          txTime: updatedAt
        )
      ),
    ]
  }

  public static func decodeBoards(
    _ snapshots: [InstantEntitySnapshot]
  ) throws -> [MergeTileGameBoard] {
    try snapshots.map(decodeBoard)
  }

  public static func decodeBoard(_ snapshot: InstantEntitySnapshot) throws -> MergeTileGameBoard {
    guard case let .json(.object(rawState)) = snapshot.values["state"]?.first else {
      throw decodeError(snapshot: snapshot, field: "state", expected: "JSON object")
    }

    var state: [String: String] = [:]
    for (key, value) in rawState {
      guard case let .string(color) = value else {
        throw decodeError(snapshot: snapshot, field: "state.\(key)", expected: "string")
      }
      state[key] = color
    }

    return MergeTileGameBoard(
      id: snapshot.id,
      state: state,
      filledCount: state.values.filter { $0 != emptyColor }.count
    )
  }

  public static func player(
    from presence: InstantRoomPresenceMember,
    viewerUserID: String? = nil
  ) -> MergeTileGamePlayer? {
    guard presence.room == room,
      case let .string(color)? = presence.values[colorKey]
    else {
      return nil
    }
    return MergeTileGamePlayer(
      userID: presence.userID,
      color: color,
      isViewer: presence.userID == viewerUserID,
      updatedAt: presence.updatedAt
    )
  }

  public static func players(
    from presence: [InstantRoomPresenceMember],
    viewerUserID: String? = nil
  ) -> [MergeTileGamePlayer] {
    presence.compactMap { player(from: $0, viewerUserID: viewerUserID) }
  }

  public static func snapshot(
    board: MergeTileGameBoard?,
    presence: [InstantRoomPresenceMember],
    viewerUserID: String? = nil
  ) -> MergeTileGameSnapshot {
    let players = players(from: presence, viewerUserID: viewerUserID)
    let currentPlayer = players.first { $0.isViewer }
    let peers = players.filter { player in
      guard let currentPlayer else {
        return true
      }
      return player.userID != currentPlayer.userID
    }
    return MergeTileGameSnapshot(
      viewerUserID: viewerUserID,
      board: board,
      playerCount: players.count,
      currentPlayer: currentPlayer,
      peers: peers,
      players: players,
      availableColors: availableColors(from: players)
    )
  }

  private static func identityOperation(
    updatedAt: InstantTimestamp,
    transactionID: String
  ) -> InstantTripleOperation {
    .insert(
      InstantTriple(
        entityID: boardID,
        attributeID: InstantAttribute.primaryKeyID(namespace: namespace),
        value: .string(boardID),
        txID: transactionID,
        txTime: updatedAt
      )
    )
  }

  private static func stateInsertOperation(
    state: [String: JSONValue],
    updatedAt: InstantTimestamp,
    transactionID: String
  ) -> InstantTripleOperation {
    .insert(
      InstantTriple(
        entityID: boardID,
        attributeID: "boards/state",
        value: .json(.object(state)),
        txID: transactionID,
        txTime: updatedAt
      )
    )
  }

  private static func decodeError(
    snapshot: InstantEntitySnapshot,
    field: String,
    expected: String
  ) -> InstantError {
    InstantError(
      code: .decodeFailed,
      operation: "decode merge tile game example",
      namespace: namespace,
      path: field,
      localID: snapshot.id,
      message: "Expected \(expected) for merge tile game field '\(field)'.",
      recovery: "Inspect the local merge tile game board triples and attributes."
    )
  }
}
