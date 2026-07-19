import Foundation
import InstantSwiftData
import StroopwafelV3App

public struct InstantStroopwafelV3LiveColorPromptEvidence:
  Codable, Equatable, Sendable
{
  public var color: String
  public var label: String

  public init(color: String, label: String) {
    self.color = color
    self.label = label
  }
}

public struct InstantStroopwafelV3LivePointEvidence:
  Codable, Equatable, Sendable
{
  public var id: String
  public var value: Int
  public var userID: String

  public init(id: String, value: Int, userID: String) {
    self.id = id
    self.value = value
    self.userID = userID
  }
}

public struct InstantStroopwafelV3LiveRoomEvidence:
  Codable, Equatable, Sendable
{
  public var id: String
  public var code: String?
  public var hostID: String
  public var readyIDs: [String]
  public var kickedIDs: [String]
  public var currentGameID: String?
  public var userIDs: [String]

  public init(
    id: String,
    code: String?,
    hostID: String,
    readyIDs: [String],
    kickedIDs: [String],
    currentGameID: String?,
    userIDs: [String]
  ) {
    self.id = id
    self.code = code
    self.hostID = hostID
    self.readyIDs = readyIDs
    self.kickedIDs = kickedIDs
    self.currentGameID = currentGameID
    self.userIDs = userIDs
  }
}

public struct InstantStroopwafelV3LiveGameEvidence:
  Codable, Equatable, Sendable
{
  public var id: String
  public var status: String
  public var playerIDs: [String]
  public var colors: [InstantStroopwafelV3LiveColorPromptEvidence]
  public var userIDs: [String]
  public var roomIDs: [String]
  public var points: [InstantStroopwafelV3LivePointEvidence]

  public init(
    id: String,
    status: String,
    playerIDs: [String],
    colors: [InstantStroopwafelV3LiveColorPromptEvidence],
    userIDs: [String],
    roomIDs: [String],
    points: [InstantStroopwafelV3LivePointEvidence]
  ) {
    self.id = id
    self.status = status
    self.playerIDs = playerIDs
    self.colors = colors
    self.userIDs = userIDs
    self.roomIDs = roomIDs
    self.points = points
  }
}

public struct InstantStroopwafelV3LiveValidationDetails:
  Codable, Equatable, Sendable
{
  public var room: InstantStroopwafelV3LiveRoomEvidence
  public var game: InstantStroopwafelV3LiveGameEvidence
  public var typeScriptPointObservedBySwift: InstantStroopwafelV3LivePointEvidence
  public var completedStatus: String
  public var winningPointValue: Int
  public var currentGameIDAfterCompletion: String?
  public var connectionState: String

  public init(
    room: InstantStroopwafelV3LiveRoomEvidence,
    game: InstantStroopwafelV3LiveGameEvidence,
    typeScriptPointObservedBySwift: InstantStroopwafelV3LivePointEvidence,
    completedStatus: String,
    winningPointValue: Int,
    currentGameIDAfterCompletion: String?,
    connectionState: String
  ) {
    self.room = room
    self.game = game
    self.typeScriptPointObservedBySwift = typeScriptPointObservedBySwift
    self.completedStatus = completedStatus
    self.winningPointValue = winningPointValue
    self.currentGameIDAfterCompletion = currentGameIDAfterCompletion
    self.connectionState = connectionState
  }
}

public enum InstantStroopwafelV3LiveValidation {
  public static let roomID = "room-stroopwafel-v3"
  public static let roomCode = "AB12"
  public static let gameID = "game-stroopwafel-v3"
  public static let swiftHostID = "swift-host"
  public static let typeScriptGuestID = "typescript-guest"
  public static let hostPointID = "point-swift-host"
  public static let guestPointID = "point-typescript-guest"
  public static let hostHandle = "SwiftHost"
  public static let guestHandle = "TypeScriptGuest"
  public static let createdAt = "2026-07-19T00:00:00.000Z"
  public static let deletedAt = "2026-07-19T00:01:00.000Z"

  public static var colors: StroopwafelV3ColorSequence {
    StroopwafelV3ColorSequence(
      StroopwafelExample.generateGameColors(seed: gameID).map {
        StroopwafelV3ColorPrompt(color: $0.color, label: $0.label)
      }
    )
  }

  public static var prompts: [InstantStroopwafelV3LiveColorPromptEvidence] {
    colors.values.map { .init(color: $0.color, label: $0.label) }
  }

  public static func pointIDs(
    hostUserID: String,
    guestUserID: String
  ) -> [String: InstantID<StroopwafelV3Point>] {
    [
      hostUserID: InstantID(rawValue: hostPointID),
      guestUserID: InstantID(rawValue: guestPointID),
    ]
  }

  public static func expectedPlayerIDs(
    hostUserID: String,
    guestUserID: String
  ) -> [String] {
    [hostUserID, guestUserID].sorted()
  }
}
