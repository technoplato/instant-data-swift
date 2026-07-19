import Foundation
import InstantSwiftData

public struct StroopwafelV3Changed: Equatable, Sendable {
  public var entityID: String

  public init(entityID: String) {
    self.entityID = entityID
  }
}

public struct SetupStroopwafelV3Profile: InstantMessage {
  public var userID: InstantID<StroopwafelV3User>
  public var handle: String
  public var email: String?
  public var createdAt: String

  public init(
    userID: InstantID<StroopwafelV3User>,
    handle: String,
    email: String? = nil,
    createdAt: String
  ) {
    self.userID = userID
    self.handle = handle
    self.email = email
    self.createdAt = createdAt
  }

  public func prepare(using client: InstantSwiftDataClient) async throws
    -> InstantPreparedMessage<StroopwafelV3Changed>
  {
    _ = client
    return InstantPreparedMessage(change: .init(entityID: userID.rawValue)) {
      InstantMutation { transactionID, txTime in
        StroopwafelExample.setupProfileOperations(
          userID: userID.rawValue,
          handle: handle,
          email: email,
          highScore: 0,
          createdAt: createdAt,
          transactionID: transactionID,
          updatedAt: txTime
        )
      }
    }
  }
}

public struct CreateStroopwafelV3Room: InstantMessage {
  public var roomID: InstantID<StroopwafelV3Room>
  public var code: String
  public var hostID: InstantID<StroopwafelV3User>
  public var createdAt: String

  public init(
    roomID: InstantID<StroopwafelV3Room>,
    code: String,
    hostID: InstantID<StroopwafelV3User>,
    createdAt: String
  ) {
    self.roomID = roomID
    self.code = code
    self.hostID = hostID
    self.createdAt = createdAt
  }

  public func prepare(using client: InstantSwiftDataClient) async throws
    -> InstantPreparedMessage<StroopwafelV3Changed>
  {
    _ = client
    return InstantPreparedMessage(change: .init(entityID: roomID.rawValue)) {
      InstantMutation { transactionID, txTime in
        StroopwafelExample.createRoomOperations(
          id: roomID.rawValue,
          code: code,
          hostID: hostID.rawValue,
          createdAt: createdAt,
          transactionID: transactionID,
          updatedAt: txTime
        )
      }
    }
  }
}

public struct JoinStroopwafelV3Room: InstantMessage {
  public var room: StroopwafelV3Room
  public var userID: InstantID<StroopwafelV3User>

  public init(room: StroopwafelV3Room, userID: InstantID<StroopwafelV3User>) {
    self.room = room
    self.userID = userID
  }

  public func prepare(using client: InstantSwiftDataClient) async throws
    -> InstantPreparedMessage<StroopwafelV3Changed>
  {
    _ = client
    guard !room.kickedIDs.values.contains(userID.rawValue) else {
      throw StroopwafelV3MessageError.playerWasKicked(userID.rawValue)
    }
    return InstantPreparedMessage(change: .init(entityID: room.id.rawValue)) {
      InstantMutation { transactionID, txTime in
        StroopwafelExample.joinRoomOperations(
          room: room.coreRecord,
          userID: userID.rawValue,
          transactionID: transactionID,
          updatedAt: txTime
        )
      }
    }
  }
}

public struct SetStroopwafelV3Ready: InstantMessage {
  public var room: StroopwafelV3Room
  public var userID: InstantID<StroopwafelV3User>
  public var isReady: Bool

  public init(
    room: StroopwafelV3Room,
    userID: InstantID<StroopwafelV3User>,
    isReady: Bool
  ) {
    self.room = room
    self.userID = userID
    self.isReady = isReady
  }

  public func prepare(using client: InstantSwiftDataClient) async throws
    -> InstantPreparedMessage<StroopwafelV3Changed>
  {
    _ = client
    return InstantPreparedMessage(change: .init(entityID: room.id.rawValue)) {
      InstantMutation { transactionID, txTime in
        StroopwafelExample.readyRoomOperations(
          room: room.coreRecord,
          userID: userID.rawValue,
          isReady: isReady,
          transactionID: transactionID,
          updatedAt: txTime
        )
      }
    }
  }
}

public struct KickStroopwafelV3Player: InstantMessage {
  public var room: StroopwafelV3Room
  public var userID: InstantID<StroopwafelV3User>

  public init(room: StroopwafelV3Room, userID: InstantID<StroopwafelV3User>) {
    self.room = room
    self.userID = userID
  }

  public func prepare(using client: InstantSwiftDataClient) async throws
    -> InstantPreparedMessage<StroopwafelV3Changed>
  {
    _ = client
    return InstantPreparedMessage(change: .init(entityID: room.id.rawValue)) {
      InstantMutation { transactionID, txTime in
        StroopwafelExample.kickRoomOperations(
          room: room.coreRecord,
          userID: userID.rawValue,
          transactionID: transactionID,
          updatedAt: txTime
        )
      }
    }
  }
}

public struct StartStroopwafelV3Game: InstantMessage {
  public var room: StroopwafelV3Room
  public var gameID: InstantID<StroopwafelV3Game>
  public var pointIDsByPlayerID: [String: InstantID<StroopwafelV3Point>]
  public var colors: StroopwafelV3ColorSequence
  public var createdAt: String

  public init(
    room: StroopwafelV3Room,
    gameID: InstantID<StroopwafelV3Game>,
    pointIDsByPlayerID: [String: InstantID<StroopwafelV3Point>],
    colors: StroopwafelV3ColorSequence,
    createdAt: String
  ) {
    self.room = room
    self.gameID = gameID
    self.pointIDsByPlayerID = pointIDsByPlayerID
    self.colors = colors
    self.createdAt = createdAt
  }

  public func prepare(using client: InstantSwiftDataClient) async throws
    -> InstantPreparedMessage<StroopwafelV3Changed>
  {
    _ = client
    let points = pointIDsByPlayerID
      .map { (pointID: $0.value.rawValue, playerID: $0.key) }
      .sorted { $0.playerID < $1.playerID }
    return InstantPreparedMessage(change: .init(entityID: gameID.rawValue)) {
      InstantMutation { transactionID, txTime in
        StroopwafelExample.startGameOperations(
          room: room.coreRecord,
          gameID: gameID.rawValue,
          pointIDsByPlayerID: points,
          colors: colors.values.map { .init(color: $0.color, label: $0.label) },
          createdAt: createdAt,
          transactionID: transactionID,
          updatedAt: txTime
        )
      }
    }
  }
}

public struct TapStroopwafelV3Color: InstantMessage {
  public var game: StroopwafelV3Game
  public var userID: InstantID<StroopwafelV3User>
  public var selectedColor: String

  public init(
    game: StroopwafelV3Game,
    userID: InstantID<StroopwafelV3User>,
    selectedColor: String
  ) {
    self.game = game
    self.userID = userID
    self.selectedColor = selectedColor
  }

  public func prepare(using client: InstantSwiftDataClient) async throws
    -> InstantPreparedMessage<StroopwafelV3Changed>
  {
    _ = client
    return InstantPreparedMessage(change: .init(entityID: game.id.rawValue)) {
      InstantMutation { transactionID, txTime in
        StroopwafelExample.tapOperations(
          game: game.coreRecord,
          userID: userID.rawValue,
          selectedColor: selectedColor,
          transactionID: transactionID,
          updatedAt: txTime
        )
      }
    }
  }
}

public struct LeaveStroopwafelV3Room: InstantMessage {
  public var room: StroopwafelV3Room
  public var userID: InstantID<StroopwafelV3User>
  public var deletedAt: String

  public init(
    room: StroopwafelV3Room,
    userID: InstantID<StroopwafelV3User>,
    deletedAt: String
  ) {
    self.room = room
    self.userID = userID
    self.deletedAt = deletedAt
  }

  public func prepare(using client: InstantSwiftDataClient) async throws
    -> InstantPreparedMessage<StroopwafelV3Changed>
  {
    _ = client
    return InstantPreparedMessage(change: .init(entityID: room.id.rawValue)) {
      InstantMutation { transactionID, txTime in
        StroopwafelExample.leaveRoomOperations(
          room: room.coreRecord,
          userID: userID.rawValue,
          deletedAt: deletedAt,
          transactionID: transactionID,
          updatedAt: txTime
        )
      }
    }
  }
}

public struct PlayAgainStroopwafelV3: InstantMessage {
  public var room: StroopwafelV3Room

  public init(room: StroopwafelV3Room) {
    self.room = room
  }

  public func prepare(using client: InstantSwiftDataClient) async throws
    -> InstantPreparedMessage<StroopwafelV3Changed>
  {
    _ = client
    return InstantPreparedMessage(change: .init(entityID: room.id.rawValue)) {
      InstantMutation { transactionID, txTime in
        StroopwafelExample.playAgainOperations(
          room: room.coreRecord,
          transactionID: transactionID,
          updatedAt: txTime
        )
      }
    }
  }
}

public enum StroopwafelV3MessageError: Error, Equatable, Sendable {
  case playerWasKicked(String)
}
