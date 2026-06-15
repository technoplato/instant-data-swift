import Foundation

public struct StroopwafelUserRecord: Hashable, Codable, Sendable, Identifiable {
  public var id: String
  public var email: String?
  public var handle: String?
  public var highScore: Int?
  public var createdAt: String?

  public init(
    id: String,
    email: String? = nil,
    handle: String? = nil,
    highScore: Int? = nil,
    createdAt: String? = nil
  ) {
    self.id = id
    self.email = email
    self.handle = handle
    self.highScore = highScore
    self.createdAt = createdAt
  }
}

public struct StroopwafelRoomRecord: Hashable, Codable, Sendable, Identifiable {
  public var id: String
  public var code: String?
  public var hostID: String
  public var readyIDs: [String]
  public var kickedIDs: [String]
  public var currentGameID: String?
  public var createdAt: String
  public var deletedAt: String?
  public var users: [StroopwafelUserRecord]

  public init(
    id: String,
    code: String?,
    hostID: String,
    readyIDs: [String],
    kickedIDs: [String],
    currentGameID: String? = nil,
    createdAt: String,
    deletedAt: String? = nil,
    users: [StroopwafelUserRecord] = []
  ) {
    self.id = id
    self.code = code
    self.hostID = hostID
    self.readyIDs = readyIDs
    self.kickedIDs = kickedIDs
    self.currentGameID = currentGameID
    self.createdAt = createdAt
    self.deletedAt = deletedAt
    self.users = users
  }
}

public struct StroopwafelColorPrompt: Hashable, Codable, Sendable {
  public var color: String
  public var label: String

  public init(color: String, label: String) {
    self.color = color
    self.label = label
  }
}

public struct StroopwafelPointRecord: Hashable, Codable, Sendable, Identifiable {
  public var id: String
  public var value: Int
  public var userID: String

  public init(id: String, value: Int, userID: String) {
    self.id = id
    self.value = value
    self.userID = userID
  }
}

public struct StroopwafelGameRecord: Hashable, Codable, Sendable, Identifiable {
  public var id: String
  public var status: String
  public var playerIDs: [String]
  public var colors: [StroopwafelColorPrompt]
  public var createdAt: String
  public var users: [StroopwafelUserRecord]
  public var rooms: [StroopwafelRoomRecord]
  public var points: [StroopwafelPointRecord]

  public init(
    id: String,
    status: String,
    playerIDs: [String],
    colors: [StroopwafelColorPrompt],
    createdAt: String,
    users: [StroopwafelUserRecord] = [],
    rooms: [StroopwafelRoomRecord] = [],
    points: [StroopwafelPointRecord] = []
  ) {
    self.id = id
    self.status = status
    self.playerIDs = playerIDs
    self.colors = colors
    self.createdAt = createdAt
    self.users = users
    self.rooms = rooms
    self.points = points
  }
}

public enum StroopwafelExample {
  public static let usersNamespace = "$users"
  public static let roomsNamespace = "rooms"
  public static let gamesNamespace = "games"
  public static let pointsNamespace = "points"

  public static let gameInProgress = "GAME_IN_PROGRESS"
  public static let gameCompleted = "GAME_COMPLETED"
  public static let multiplayerScoreToWin = 13
  public static let colorChoices = ["red", "green", "blue", "yellow"]

  public static let attributes: [InstantAttribute] = [
    .primaryKey(namespace: usersNamespace),
    InstantAttribute(
      id: "$users/email",
      namespace: usersNamespace,
      name: "email",
      valueType: .any,
      isRequired: false,
      isIndexed: true,
      isUnique: true
    ),
    InstantAttribute(
      id: "$users/handle",
      namespace: usersNamespace,
      name: "handle",
      valueType: .string,
      isRequired: false
    ),
    InstantAttribute(
      id: "$users/highScore",
      namespace: usersNamespace,
      name: "highScore",
      valueType: .number,
      isRequired: false
    ),
    InstantAttribute(
      id: "$users/created_at",
      namespace: usersNamespace,
      name: "created_at",
      valueType: .string,
      isRequired: false
    ),

    .primaryKey(namespace: roomsNamespace),
    InstantAttribute(
      id: "rooms/code",
      namespace: roomsNamespace,
      name: "code",
      valueType: .string,
      isRequired: false,
      isIndexed: true
    ),
    InstantAttribute(
      id: "rooms/hostId",
      namespace: roomsNamespace,
      name: "hostId",
      valueType: .string
    ),
    InstantAttribute(
      id: "rooms/readyIds",
      namespace: roomsNamespace,
      name: "readyIds",
      valueType: .json
    ),
    InstantAttribute(
      id: "rooms/kickedIds",
      namespace: roomsNamespace,
      name: "kickedIds",
      valueType: .json
    ),
    InstantAttribute(
      id: "rooms/currentGameId",
      namespace: roomsNamespace,
      name: "currentGameId",
      valueType: .string,
      isRequired: false
    ),
    InstantAttribute(
      id: "rooms/created_at",
      namespace: roomsNamespace,
      name: "created_at",
      valueType: .string
    ),
    InstantAttribute(
      id: "rooms/deleted_at",
      namespace: roomsNamespace,
      name: "deleted_at",
      valueType: .string,
      isRequired: false
    ),
    InstantAttribute(
      id: "rooms/users",
      namespace: roomsNamespace,
      name: "users",
      valueType: .ref,
      isRequired: false,
      cardinality: .many,
      isIndexed: true,
      forwardIdentity: "rooms/users",
      reverseIdentity: "$users/rooms",
      linkNamespace: usersNamespace
    ),

    .primaryKey(namespace: gamesNamespace),
    InstantAttribute(
      id: "games/status",
      namespace: gamesNamespace,
      name: "status",
      valueType: .string
    ),
    InstantAttribute(
      id: "games/playerIds",
      namespace: gamesNamespace,
      name: "playerIds",
      valueType: .json
    ),
    InstantAttribute(
      id: "games/colors",
      namespace: gamesNamespace,
      name: "colors",
      valueType: .json
    ),
    InstantAttribute(
      id: "games/created_at",
      namespace: gamesNamespace,
      name: "created_at",
      valueType: .string
    ),
    InstantAttribute(
      id: "games/users",
      namespace: gamesNamespace,
      name: "users",
      valueType: .ref,
      isRequired: false,
      cardinality: .many,
      isIndexed: true,
      forwardIdentity: "games/users",
      reverseIdentity: "$users/games",
      linkNamespace: usersNamespace
    ),
    InstantAttribute(
      id: "games/rooms",
      namespace: gamesNamespace,
      name: "rooms",
      valueType: .ref,
      isRequired: false,
      cardinality: .many,
      isIndexed: true,
      forwardIdentity: "games/rooms",
      reverseIdentity: "rooms/games",
      linkNamespace: roomsNamespace
    ),
    InstantAttribute(
      id: "games/points",
      namespace: gamesNamespace,
      name: "points",
      valueType: .ref,
      isRequired: false,
      cardinality: .many,
      isIndexed: true,
      forwardIdentity: "games/points",
      reverseIdentity: "points/game",
      linkNamespace: pointsNamespace,
      onDeleteReverse: .cascade
    ),

    .primaryKey(namespace: pointsNamespace),
    InstantAttribute(
      id: "points/val",
      namespace: pointsNamespace,
      name: "val",
      valueType: .number
    ),
    InstantAttribute(
      id: "points/userId",
      namespace: pointsNamespace,
      name: "userId",
      valueType: .string
    ),
  ]

  public static let usersQuery = InstantQueryPlan(
    id: "examples.stroopwafel.users",
    namespace: usersNamespace,
    order: InstantQueryOrder("handle", .ascending)
  )

  public static let roomsQuery = InstantQueryPlan(
    id: "examples.stroopwafel.rooms",
    namespace: roomsNamespace,
    order: InstantQueryOrder("created_at", .ascending),
    includes: [roomUsersInclude(id: "examples.stroopwafel.rooms.users")]
  )

  public static func roomForCodeQuery(_ code: String) -> InstantQueryPlan {
    InstantQueryPlan(
      id: "examples.stroopwafel.rooms.code.\(code)",
      namespace: roomsNamespace,
      filters: [.equals(field: "code", value: .string(code))],
      includes: [roomUsersInclude(id: "examples.stroopwafel.rooms.code.\(code).users")]
    )
  }

  public static func roomForIDQuery(_ roomID: String) -> InstantQueryPlan {
    InstantQueryPlan(
      id: "examples.stroopwafel.rooms.id.\(roomID)",
      namespace: roomsNamespace,
      filters: [.equals(field: "id", value: .string(roomID))],
      includes: [roomUsersInclude(id: "examples.stroopwafel.rooms.id.\(roomID).users")]
    )
  }

  public static func userQuery(_ userID: String) -> InstantQueryPlan {
    InstantQueryPlan(
      id: "examples.stroopwafel.users.\(userID)",
      namespace: usersNamespace,
      filters: [.equals(field: "id", value: .string(userID))]
    )
  }

  public static let gamesQuery = InstantQueryPlan(
    id: "examples.stroopwafel.games",
    namespace: gamesNamespace,
    order: InstantQueryOrder("created_at", .ascending),
    includes: gameIncludes(id: "examples.stroopwafel.games")
  )

  public static func gameQuery(_ gameID: String) -> InstantQueryPlan {
    InstantQueryPlan(
      id: "examples.stroopwafel.games.\(gameID)",
      namespace: gamesNamespace,
      filters: [.equals(field: "id", value: .string(gameID))],
      includes: gameIncludes(id: "examples.stroopwafel.games.\(gameID)")
    )
  }

  public static let pointsQuery = InstantQueryPlan(
    id: "examples.stroopwafel.points",
    namespace: pointsNamespace
  )

  public static func setupProfileOperations(
    userID: String,
    handle: String,
    email: String? = nil,
    highScore: Int? = 0,
    createdAt: String?,
    transactionID: String,
    updatedAt: InstantTimestamp
  ) -> [InstantTripleOperation] {
    upsertUserOperations(
      id: userID,
      email: email,
      handle: handle,
      highScore: highScore,
      createdAt: createdAt,
      transactionID: transactionID,
      updatedAt: updatedAt
    )
  }

  public static func updateHighScoreOperations(
    userID: String,
    score: Int,
    transactionID: String,
    updatedAt: InstantTimestamp
  ) -> [InstantTripleOperation] {
    [
      .requireEntityExists(entityID: userID, namespace: usersNamespace),
      scalarOperation(
        id: userID,
        attributeID: "$users/highScore",
        value: .number(Double(score)),
        transactionID: transactionID,
        updatedAt: updatedAt
      ),
    ]
  }

  public static func createRoomOperations(
    id: String,
    code: String,
    hostID: String,
    createdAt: String,
    transactionID: String,
    updatedAt: InstantTimestamp
  ) -> [InstantTripleOperation] {
    [
      .requireEntityMissing(entityID: id, namespace: roomsNamespace),
      .requireEntityExists(entityID: hostID, namespace: usersNamespace),
    ] + upsertRoomOperations(
      id: id,
      code: code,
      hostID: hostID,
      readyIDs: [],
      kickedIDs: [],
      currentGameID: nil,
      createdAt: createdAt,
      deletedAt: nil,
      transactionID: transactionID,
      updatedAt: updatedAt
    )
      + linkRoomUserOperations(
        roomID: id,
        userID: hostID,
        transactionID: transactionID,
        updatedAt: updatedAt
      )
  }

  public static func joinRoomOperations(
    room: StroopwafelRoomRecord,
    userID: String,
    transactionID: String,
    updatedAt: InstantTimestamp
  ) -> [InstantTripleOperation] {
    [
      .requireEntityExists(entityID: room.id, namespace: roomsNamespace),
      .requireEntityExists(entityID: userID, namespace: usersNamespace),
    ]
      + linkRoomUserOperations(
        roomID: room.id,
        userID: userID,
        transactionID: transactionID,
        updatedAt: updatedAt
      )
  }

  public static func readyRoomOperations(
    room: StroopwafelRoomRecord,
    userID: String,
    isReady: Bool,
    transactionID: String,
    updatedAt: InstantTimestamp
  ) -> [InstantTripleOperation] {
    let nextReadyIDs =
      isReady
      ? (room.readyIDs.contains(userID) ? room.readyIDs : room.readyIDs + [userID])
      : room.readyIDs.filter { $0 != userID }
    return [
      .requireEntityExists(entityID: room.id, namespace: roomsNamespace),
      scalarOperation(
        id: room.id,
        attributeID: "rooms/readyIds",
        value: .json(jsonArray(nextReadyIDs)),
        transactionID: transactionID,
        updatedAt: updatedAt
      ),
    ]
  }

  public static func kickRoomOperations(
    room: StroopwafelRoomRecord,
    userID: String,
    transactionID: String,
    updatedAt: InstantTimestamp
  ) -> [InstantTripleOperation] {
    let nextKickedIDs =
      room.kickedIDs.contains(userID) ? room.kickedIDs : room.kickedIDs + [userID]
    return [
      .requireEntityExists(entityID: room.id, namespace: roomsNamespace),
      scalarOperation(
        id: room.id,
        attributeID: "rooms/kickedIds",
        value: .json(jsonArray(nextKickedIDs)),
        transactionID: transactionID,
        updatedAt: updatedAt
      ),
      scalarOperation(
        id: room.id,
        attributeID: "rooms/readyIds",
        value: .json(jsonArray(room.readyIDs.filter { $0 != userID })),
        transactionID: transactionID,
        updatedAt: updatedAt
      ),
    ] + unlinkRoomUserOperations(
      roomID: room.id,
      userID: userID,
      transactionID: transactionID,
      updatedAt: updatedAt
    )
  }

  public static func leaveRoomOperations(
    room: StroopwafelRoomRecord,
    userID: String,
    deletedAt: String,
    transactionID: String,
    updatedAt: InstantTimestamp
  ) -> [InstantTripleOperation] {
    if room.hostID == userID {
      return [
        .requireEntityExists(entityID: room.id, namespace: roomsNamespace),
        scalarOperation(
          id: room.id,
          attributeID: "rooms/code",
          value: .null,
          transactionID: transactionID,
          updatedAt: updatedAt
        ),
        scalarOperation(
          id: room.id,
          attributeID: "rooms/deleted_at",
          value: .string(deletedAt),
          transactionID: transactionID,
          updatedAt: updatedAt
        ),
      ]
    }

    return [
      .requireEntityExists(entityID: room.id, namespace: roomsNamespace),
      scalarOperation(
        id: room.id,
        attributeID: "rooms/readyIds",
        value: .json(jsonArray(room.readyIDs.filter { $0 != userID })),
        transactionID: transactionID,
        updatedAt: updatedAt
      ),
    ] + unlinkRoomUserOperations(
      roomID: room.id,
      userID: userID,
      transactionID: transactionID,
      updatedAt: updatedAt
    )
  }

  public static func startGameOperations(
    room: StroopwafelRoomRecord,
    gameID: String,
    pointIDsByPlayerID: [(pointID: String, playerID: String)],
    colors: [StroopwafelColorPrompt],
    createdAt: String,
    transactionID: String,
    updatedAt: InstantTimestamp
  ) -> [InstantTripleOperation] {
    let playerIDs = room.users
      .map(\.id)
      .filter { $0 == room.hostID || room.readyIDs.contains($0) }
    let pointOperations = pointIDsByPlayerID.flatMap { pointID, playerID in
      upsertPointOperations(
        id: pointID,
        value: 0,
        userID: playerID,
        transactionID: transactionID,
        updatedAt: updatedAt
      )
    }

    return [
      .requireEntityMissing(entityID: gameID, namespace: gamesNamespace),
      .requireEntityExists(entityID: room.id, namespace: roomsNamespace),
    ] + upsertGameOperations(
      id: gameID,
      status: gameInProgress,
      playerIDs: playerIDs,
      colors: colors,
      createdAt: createdAt,
      transactionID: transactionID,
      updatedAt: updatedAt
    )
      + pointOperations
      + playerIDs.flatMap {
        linkGameUserOperations(
          gameID: gameID,
          userID: $0,
          transactionID: transactionID,
          updatedAt: updatedAt
        )
      }
      + pointIDsByPlayerID.flatMap {
        linkGamePointOperations(
          gameID: gameID,
          pointID: $0.pointID,
          transactionID: transactionID,
          updatedAt: updatedAt
        )
      }
      + linkGameRoomOperations(
        gameID: gameID,
        roomID: room.id,
        transactionID: transactionID,
        updatedAt: updatedAt
      )
      + [
        scalarOperation(
          id: room.id,
          attributeID: "rooms/currentGameId",
          value: .string(gameID),
          transactionID: transactionID,
          updatedAt: updatedAt
        ),
        scalarOperation(
          id: room.id,
          attributeID: "rooms/readyIds",
          value: .json(jsonArray([])),
          transactionID: transactionID,
          updatedAt: updatedAt
        ),
      ]
  }

  public static func tapOperations(
    game: StroopwafelGameRecord,
    userID: String,
    selectedColor: String,
    transactionID: String,
    updatedAt: InstantTimestamp
  ) -> [InstantTripleOperation] {
    guard let point = game.points.first(where: { $0.userID == userID }) else { return [] }
    let prompt = game.colors[safe: point.value]
    let nextValue =
      selectedColor == prompt?.label
      ? point.value + 1
      : max(point.value - 2, 0)

    var operations: [InstantTripleOperation] = [
      .requireEntityExists(entityID: game.id, namespace: gamesNamespace),
      .requireEntityExists(entityID: point.id, namespace: pointsNamespace),
      scalarOperation(
        id: point.id,
        attributeID: "points/val",
        value: .number(Double(nextValue)),
        transactionID: transactionID,
        updatedAt: updatedAt
      ),
    ]

    if nextValue == multiplayerScoreToWin {
      operations.append(
        scalarOperation(
          id: game.id,
          attributeID: "games/status",
          value: .string(gameCompleted),
          transactionID: transactionID,
          updatedAt: updatedAt
        )
      )
      for room in game.rooms {
        operations.append(
          scalarOperation(
            id: room.id,
            attributeID: "rooms/currentGameId",
            value: .null,
            transactionID: transactionID,
            updatedAt: updatedAt
          )
        )
      }
    }

    return operations
  }

  public static func playAgainOperations(
    room: StroopwafelRoomRecord,
    transactionID: String,
    updatedAt: InstantTimestamp
  ) -> [InstantTripleOperation] {
    [
      .requireEntityExists(entityID: room.id, namespace: roomsNamespace),
      scalarOperation(
        id: room.id,
        attributeID: "rooms/currentGameId",
        value: .null,
        transactionID: transactionID,
        updatedAt: updatedAt
      ),
    ]
  }

  public static func deleteUserOperations(id: String) -> [InstantTripleOperation] {
    [
      .requireEntityExists(entityID: id, namespace: usersNamespace),
      .deleteEntityInNamespace(entityID: id, namespace: usersNamespace),
    ]
  }

  public static func deleteRoomOperations(id: String) -> [InstantTripleOperation] {
    [
      .requireEntityExists(entityID: id, namespace: roomsNamespace),
      .deleteEntityInNamespace(entityID: id, namespace: roomsNamespace),
    ]
  }

  public static func deleteGameOperations(id: String) -> [InstantTripleOperation] {
    [
      .requireEntityExists(entityID: id, namespace: gamesNamespace),
      .deleteEntityInNamespace(entityID: id, namespace: gamesNamespace),
    ]
  }

  public static func deletePointOperations(id: String) -> [InstantTripleOperation] {
    [
      .requireEntityExists(entityID: id, namespace: pointsNamespace),
      .deleteEntityInNamespace(entityID: id, namespace: pointsNamespace),
    ]
  }

  public static func generateGameColors(
    seed: String,
    length: Int = multiplayerScoreToWin + 1
  ) -> [StroopwafelColorPrompt] {
    var generator = DeterministicColorGenerator(seed: seed)
    return (0..<length).map { _ in
      StroopwafelColorPrompt(
        color: generator.nextColor(),
        label: generator.nextColor()
      )
    }
  }

  public static func normalizeRoomCode(_ value: String) -> String {
    String(
      value
        .uppercased()
        .filter { $0.isLetter || $0.isNumber }
        .prefix(8)
    )
  }

  public static func isValidHandle(_ handle: String) -> Bool {
    handle.count > 2
      && handle.count < 17
      && handle.allSatisfy { $0.isLetter || $0.isNumber }
  }

  public static func decodeUsers(_ snapshots: [InstantEntitySnapshot]) throws
    -> [StroopwafelUserRecord]
  {
    try snapshots.map(decodeUser)
  }

  public static func decodeRooms(_ snapshots: [InstantEntitySnapshot]) throws
    -> [StroopwafelRoomRecord]
  {
    try snapshots.map(decodeRoom)
  }

  public static func decodeGames(_ snapshots: [InstantEntitySnapshot]) throws
    -> [StroopwafelGameRecord]
  {
    try snapshots.map(decodeGame)
  }

  public static func decodePoints(_ snapshots: [InstantEntitySnapshot]) throws
    -> [StroopwafelPointRecord]
  {
    try snapshots.map(decodePoint)
  }

  private static func upsertUserOperations(
    id: String,
    email: String?,
    handle: String?,
    highScore: Int?,
    createdAt: String?,
    transactionID: String,
    updatedAt: InstantTimestamp
  ) -> [InstantTripleOperation] {
    var operations = [
      identityOperation(
        id: id,
        namespace: usersNamespace,
        transactionID: transactionID,
        updatedAt: updatedAt
      )
    ]
    if let email {
      operations.append(
        scalarOperation(
          id: id,
          attributeID: "$users/email",
          value: .string(email),
          transactionID: transactionID,
          updatedAt: updatedAt
        )
      )
    }
    if let handle {
      operations.append(
        scalarOperation(
          id: id,
          attributeID: "$users/handle",
          value: .string(handle),
          transactionID: transactionID,
          updatedAt: updatedAt
        )
      )
    }
    if let highScore {
      operations.append(
        scalarOperation(
          id: id,
          attributeID: "$users/highScore",
          value: .number(Double(highScore)),
          transactionID: transactionID,
          updatedAt: updatedAt
        )
      )
    }
    if let createdAt {
      operations.append(
        scalarOperation(
          id: id,
          attributeID: "$users/created_at",
          value: .string(createdAt),
          transactionID: transactionID,
          updatedAt: updatedAt
        )
      )
    }
    return operations
  }

  private static func upsertRoomOperations(
    id: String,
    code: String?,
    hostID: String,
    readyIDs: [String],
    kickedIDs: [String],
    currentGameID: String?,
    createdAt: String,
    deletedAt: String?,
    transactionID: String,
    updatedAt: InstantTimestamp
  ) -> [InstantTripleOperation] {
    var operations = [
      identityOperation(
        id: id,
        namespace: roomsNamespace,
        transactionID: transactionID,
        updatedAt: updatedAt
      ),
      scalarOperation(
        id: id,
        attributeID: "rooms/hostId",
        value: .string(hostID),
        transactionID: transactionID,
        updatedAt: updatedAt
      ),
      scalarOperation(
        id: id,
        attributeID: "rooms/readyIds",
        value: .json(jsonArray(readyIDs)),
        transactionID: transactionID,
        updatedAt: updatedAt
      ),
      scalarOperation(
        id: id,
        attributeID: "rooms/kickedIds",
        value: .json(jsonArray(kickedIDs)),
        transactionID: transactionID,
        updatedAt: updatedAt
      ),
      scalarOperation(
        id: id,
        attributeID: "rooms/created_at",
        value: .string(createdAt),
        transactionID: transactionID,
        updatedAt: updatedAt
      ),
    ]
    if let code {
      operations.append(
        scalarOperation(
          id: id,
          attributeID: "rooms/code",
          value: .string(code),
          transactionID: transactionID,
          updatedAt: updatedAt
        )
      )
    }
    if let currentGameID {
      operations.append(
        scalarOperation(
          id: id,
          attributeID: "rooms/currentGameId",
          value: .string(currentGameID),
          transactionID: transactionID,
          updatedAt: updatedAt
        )
      )
    }
    if let deletedAt {
      operations.append(
        scalarOperation(
          id: id,
          attributeID: "rooms/deleted_at",
          value: .string(deletedAt),
          transactionID: transactionID,
          updatedAt: updatedAt
        )
      )
    }
    return operations
  }

  private static func upsertGameOperations(
    id: String,
    status: String,
    playerIDs: [String],
    colors: [StroopwafelColorPrompt],
    createdAt: String,
    transactionID: String,
    updatedAt: InstantTimestamp
  ) -> [InstantTripleOperation] {
    [
      identityOperation(
        id: id,
        namespace: gamesNamespace,
        transactionID: transactionID,
        updatedAt: updatedAt
      ),
      scalarOperation(
        id: id,
        attributeID: "games/status",
        value: .string(status),
        transactionID: transactionID,
        updatedAt: updatedAt
      ),
      scalarOperation(
        id: id,
        attributeID: "games/playerIds",
        value: .json(jsonArray(playerIDs)),
        transactionID: transactionID,
        updatedAt: updatedAt
      ),
      scalarOperation(
        id: id,
        attributeID: "games/colors",
        value: .json(colors.jsonValue),
        transactionID: transactionID,
        updatedAt: updatedAt
      ),
      scalarOperation(
        id: id,
        attributeID: "games/created_at",
        value: .string(createdAt),
        transactionID: transactionID,
        updatedAt: updatedAt
      ),
    ]
  }

  private static func upsertPointOperations(
    id: String,
    value: Int,
    userID: String,
    transactionID: String,
    updatedAt: InstantTimestamp
  ) -> [InstantTripleOperation] {
    [
      identityOperation(
        id: id,
        namespace: pointsNamespace,
        transactionID: transactionID,
        updatedAt: updatedAt
      ),
      scalarOperation(
        id: id,
        attributeID: "points/val",
        value: .number(Double(value)),
        transactionID: transactionID,
        updatedAt: updatedAt
      ),
      scalarOperation(
        id: id,
        attributeID: "points/userId",
        value: .string(userID),
        transactionID: transactionID,
        updatedAt: updatedAt
      ),
    ]
  }

  private static func linkRoomUserOperations(
    roomID: String,
    userID: String,
    transactionID: String,
    updatedAt: InstantTimestamp
  ) -> [InstantTripleOperation] {
    [
      scalarOperation(
        id: roomID,
        attributeID: "rooms/users",
        value: .ref(userID),
        transactionID: transactionID,
        updatedAt: updatedAt
      )
    ]
  }

  private static func unlinkRoomUserOperations(
    roomID: String,
    userID: String,
    transactionID: String,
    updatedAt: InstantTimestamp
  ) -> [InstantTripleOperation] {
    [
      retractOperation(
        id: roomID,
        attributeID: "rooms/users",
        value: .ref(userID),
        transactionID: transactionID,
        updatedAt: updatedAt
      )
    ]
  }

  private static func linkGameUserOperations(
    gameID: String,
    userID: String,
    transactionID: String,
    updatedAt: InstantTimestamp
  ) -> [InstantTripleOperation] {
    [
      scalarOperation(
        id: gameID,
        attributeID: "games/users",
        value: .ref(userID),
        transactionID: transactionID,
        updatedAt: updatedAt
      )
    ]
  }

  private static func linkGameRoomOperations(
    gameID: String,
    roomID: String,
    transactionID: String,
    updatedAt: InstantTimestamp
  ) -> [InstantTripleOperation] {
    [
      scalarOperation(
        id: gameID,
        attributeID: "games/rooms",
        value: .ref(roomID),
        transactionID: transactionID,
        updatedAt: updatedAt
      )
    ]
  }

  private static func linkGamePointOperations(
    gameID: String,
    pointID: String,
    transactionID: String,
    updatedAt: InstantTimestamp
  ) -> [InstantTripleOperation] {
    [
      scalarOperation(
        id: gameID,
        attributeID: "games/points",
        value: .ref(pointID),
        transactionID: transactionID,
        updatedAt: updatedAt
      )
    ]
  }

  private static func roomUsersInclude(id: String) -> InstantQueryInclude {
    InstantQueryInclude(
      "users",
      query: InstantQueryIncludePlan(
        id: id,
        namespace: usersNamespace,
        order: InstantQueryOrder("handle", .ascending),
        selectedFields: ["email", "handle", "highScore", "created_at"]
      )
    )
  }

  private static func gameIncludes(id: String) -> [InstantQueryInclude] {
    [
      InstantQueryInclude(
        "users",
        query: InstantQueryIncludePlan(
          id: "\(id).users",
          namespace: usersNamespace,
          order: InstantQueryOrder("handle", .ascending),
          selectedFields: ["email", "handle", "highScore", "created_at"]
        )
      ),
      InstantQueryInclude(
        "rooms",
        query: InstantQueryIncludePlan(
          id: "\(id).rooms",
          namespace: roomsNamespace,
          selectedFields: [
            "code", "hostId", "readyIds", "kickedIds", "currentGameId", "created_at",
            "deleted_at",
          ],
          includes: [roomUsersInclude(id: "\(id).rooms.users")]
        )
      ),
      InstantQueryInclude(
        "points",
        query: InstantQueryIncludePlan(
          id: "\(id).points",
          namespace: pointsNamespace,
          selectedFields: ["val", "userId"]
        )
      ),
    ]
  }

  private static func decodeUser(_ snapshot: InstantEntitySnapshot) throws
    -> StroopwafelUserRecord
  {
    try decodeUser(InstantLinkedEntitySnapshot(snapshot))
  }

  private static func decodeUser(_ snapshot: InstantLinkedEntitySnapshot) throws
    -> StroopwafelUserRecord
  {
    StroopwafelUserRecord(
      id: snapshot.id,
      email: try optionalString("email", from: snapshot, namespace: usersNamespace),
      handle: try optionalString("handle", from: snapshot, namespace: usersNamespace),
      highScore: try optionalInt("highScore", from: snapshot, namespace: usersNamespace),
      createdAt: try optionalString("created_at", from: snapshot, namespace: usersNamespace)
    )
  }

  private static func decodeRoom(_ snapshot: InstantEntitySnapshot) throws
    -> StroopwafelRoomRecord
  {
    try decodeRoom(InstantLinkedEntitySnapshot(snapshot))
  }

  private static func decodeRoom(_ snapshot: InstantLinkedEntitySnapshot) throws
    -> StroopwafelRoomRecord
  {
    StroopwafelRoomRecord(
      id: snapshot.id,
      code: try optionalString("code", from: snapshot, namespace: roomsNamespace),
      hostID: try stringField("hostId", from: snapshot, namespace: roomsNamespace),
      readyIDs: try stringArrayJSONField("readyIds", from: snapshot, namespace: roomsNamespace),
      kickedIDs: try stringArrayJSONField("kickedIds", from: snapshot, namespace: roomsNamespace),
      currentGameID: try optionalString("currentGameId", from: snapshot, namespace: roomsNamespace),
      createdAt: try stringField("created_at", from: snapshot, namespace: roomsNamespace),
      deletedAt: try optionalString("deleted_at", from: snapshot, namespace: roomsNamespace),
      users: try (snapshot.links?["users"] ?? []).map(decodeUser)
    )
  }

  private static func decodeGame(_ snapshot: InstantEntitySnapshot) throws
    -> StroopwafelGameRecord
  {
    StroopwafelGameRecord(
      id: snapshot.id,
      status: try stringField("status", from: snapshot, namespace: gamesNamespace),
      playerIDs: try stringArrayJSONField("playerIds", from: snapshot, namespace: gamesNamespace),
      colors: try colorPromptArrayJSONField("colors", from: snapshot, namespace: gamesNamespace),
      createdAt: try stringField("created_at", from: snapshot, namespace: gamesNamespace),
      users: try (snapshot.links?["users"] ?? []).map(decodeUser),
      rooms: try (snapshot.links?["rooms"] ?? []).map(decodeRoom),
      points: try (snapshot.links?["points"] ?? []).map(decodePoint)
    )
  }

  private static func decodePoint(_ snapshot: InstantEntitySnapshot) throws
    -> StroopwafelPointRecord
  {
    try decodePoint(InstantLinkedEntitySnapshot(snapshot))
  }

  private static func decodePoint(_ snapshot: InstantLinkedEntitySnapshot) throws
    -> StroopwafelPointRecord
  {
    StroopwafelPointRecord(
      id: snapshot.id,
      value: try intField("val", from: snapshot, namespace: pointsNamespace),
      userID: try stringField("userId", from: snapshot, namespace: pointsNamespace)
    )
  }

  private static func identityOperation(
    id: String,
    namespace: String,
    transactionID: String,
    updatedAt: InstantTimestamp
  ) -> InstantTripleOperation {
    scalarOperation(
      id: id,
      attributeID: InstantAttribute.primaryKeyID(namespace: namespace),
      value: .string(id),
      transactionID: transactionID,
      updatedAt: updatedAt
    )
  }

  private static func scalarOperation(
    id: String,
    attributeID: String,
    value: InstantValue,
    transactionID: String,
    updatedAt: InstantTimestamp
  ) -> InstantTripleOperation {
    .insert(
      InstantTriple(
        entityID: id,
        attributeID: attributeID,
        value: value,
        txID: transactionID,
        txTime: updatedAt
      )
    )
  }

  private static func retractOperation(
    id: String,
    attributeID: String,
    value: InstantValue,
    transactionID: String,
    updatedAt: InstantTimestamp
  ) -> InstantTripleOperation {
    .retract(
      InstantTriple(
        entityID: id,
        attributeID: attributeID,
        value: value,
        txID: transactionID,
        txTime: updatedAt
      )
    )
  }

  private static func jsonArray(_ values: [String]) -> JSONValue {
    .array(values.map(JSONValue.string))
  }

  private static func stringField(
    _ field: String,
    from snapshot: InstantEntitySnapshot,
    namespace: String
  ) throws -> String {
    try stringField(field, from: InstantLinkedEntitySnapshot(snapshot), namespace: namespace)
  }

  private static func stringField(
    _ field: String,
    from snapshot: InstantLinkedEntitySnapshot,
    namespace: String
  ) throws -> String {
    guard case let .string(value) = snapshot.values[field]?.first else {
      throw decodeError(namespace: namespace, id: snapshot.id, field: field, expected: "string")
    }
    return value
  }

  private static func optionalString(
    _ field: String,
    from snapshot: InstantLinkedEntitySnapshot,
    namespace: String
  ) throws -> String? {
    guard let value = snapshot.values[field]?.first else { return nil }
    switch value {
    case .null:
      return nil
    case let .string(string):
      return string
    default:
      throw decodeError(namespace: namespace, id: snapshot.id, field: field, expected: "string")
    }
  }

  private static func intField(
    _ field: String,
    from snapshot: InstantLinkedEntitySnapshot,
    namespace: String
  ) throws -> Int {
    guard case let .number(value) = snapshot.values[field]?.first,
      value.rounded() == value
    else {
      throw decodeError(namespace: namespace, id: snapshot.id, field: field, expected: "integer")
    }
    return Int(value)
  }

  private static func optionalInt(
    _ field: String,
    from snapshot: InstantLinkedEntitySnapshot,
    namespace: String
  ) throws -> Int? {
    guard let value = snapshot.values[field]?.first else { return nil }
    switch value {
    case .null:
      return nil
    case let .number(number) where number.rounded() == number:
      return Int(number)
    default:
      throw decodeError(namespace: namespace, id: snapshot.id, field: field, expected: "integer")
    }
  }

  private static func stringArrayJSONField(
    _ field: String,
    from snapshot: InstantEntitySnapshot,
    namespace: String
  ) throws -> [String] {
    try stringArrayJSONField(field, from: InstantLinkedEntitySnapshot(snapshot), namespace: namespace)
  }

  private static func stringArrayJSONField(
    _ field: String,
    from snapshot: InstantLinkedEntitySnapshot,
    namespace: String
  ) throws -> [String] {
    guard case let .json(.array(values)) = snapshot.values[field]?.first else {
      throw decodeError(namespace: namespace, id: snapshot.id, field: field, expected: "JSON array")
    }
    return try values.map { value in
      guard case let .string(string) = value else {
        throw decodeError(
          namespace: namespace,
          id: snapshot.id,
          field: field,
          expected: "JSON string array"
        )
      }
      return string
    }
  }

  private static func colorPromptArrayJSONField(
    _ field: String,
    from snapshot: InstantEntitySnapshot,
    namespace: String
  ) throws -> [StroopwafelColorPrompt] {
    guard case let .json(.array(values)) = snapshot.values[field]?.first else {
      throw decodeError(namespace: namespace, id: snapshot.id, field: field, expected: "JSON array")
    }
    return try values.map { value in
      guard case let .object(object) = value,
        case let .string(color)? = object["color"],
        case let .string(label)? = object["label"]
      else {
        throw decodeError(
          namespace: namespace,
          id: snapshot.id,
          field: field,
          expected: "JSON color prompt array"
        )
      }
      return StroopwafelColorPrompt(color: color, label: label)
    }
  }

  private static func decodeError(
    namespace: String,
    id: String,
    field: String,
    expected: String
  ) -> InstantError {
    InstantError(
      code: .decodeFailed,
      operation: "decode stroopwafel example",
      namespace: namespace,
      path: field,
      localID: id,
      message: "Expected \(expected) for Stroopwafel field '\(field)'.",
      recovery: "Inspect the local Stroopwafel example triples and attributes."
    )
  }
}

extension StroopwafelColorPrompt {
  fileprivate var jsonValue: JSONValue {
    .object([
      "color": .string(color),
      "label": .string(label),
    ])
  }
}

extension [StroopwafelColorPrompt] {
  fileprivate var jsonValue: JSONValue {
    .array(map(\.jsonValue))
  }
}

private struct DeterministicColorGenerator: Sendable {
  private var state: UInt64

  init(seed: String) {
    self.state = seed.unicodeScalars.reduce(0xcbf29ce484222325) { partial, scalar in
      (partial ^ UInt64(scalar.value)) &* 0x100000001b3
    }
  }

  mutating func nextColor() -> String {
    state = state &* 6364136223846793005 &+ 1442695040888963407
    return StroopwafelExample.colorChoices[Int(state % UInt64(StroopwafelExample.colorChoices.count))]
  }
}

private extension Array {
  subscript(safe index: Int) -> Element? {
    indices.contains(index) ? self[index] : nil
  }
}
