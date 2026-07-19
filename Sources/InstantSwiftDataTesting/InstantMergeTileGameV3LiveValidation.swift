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
}
