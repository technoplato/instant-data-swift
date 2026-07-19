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
}
