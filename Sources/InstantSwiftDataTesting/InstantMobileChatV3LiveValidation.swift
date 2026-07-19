import Foundation
import MobileChatV3App

public struct InstantMobileChatV3LiveValidationDetails: Codable, Equatable, Sendable {
  public var direction: String
  public var userID: String
  public var profileID: String
  public var displayName: String
  public var channelID: String
  public var channelName: String
  public var messageID: String
  public var messageChannelID: String
  public var authorProfileID: String
  public var content: String
  public var timestampMilliseconds: Int64
  public var connectionState: String
  public var pendingMutationCount: Int

  public init(
    direction: String,
    userID: String,
    profileID: String,
    displayName: String,
    channelID: String,
    channelName: String,
    messageID: String,
    messageChannelID: String,
    authorProfileID: String,
    content: String,
    timestampMilliseconds: Int64,
    connectionState: String,
    pendingMutationCount: Int
  ) {
    self.direction = direction
    self.userID = userID
    self.profileID = profileID
    self.displayName = displayName
    self.channelID = channelID
    self.channelName = channelName
    self.messageID = messageID
    self.messageChannelID = messageChannelID
    self.authorProfileID = authorProfileID
    self.content = content
    self.timestampMilliseconds = timestampMilliseconds
    self.connectionState = connectionState
    self.pendingMutationCount = pendingMutationCount
  }
}

public struct InstantMobileChatV3RoomValidationDetails: Codable, Equatable, Sendable {
  public var roomType: String
  public var roomID: String
  public var peerCount: Int
  public var presence: MobileChatPresence
  public var typing: MobileChatTypingEvent
  public var emoji: MobileChatReaction
  public var peerCountAfterDisconnect: Int

  public init(
    roomType: String,
    roomID: String,
    peerCount: Int,
    presence: MobileChatPresence,
    typing: MobileChatTypingEvent,
    emoji: MobileChatReaction,
    peerCountAfterDisconnect: Int
  ) {
    self.roomType = roomType
    self.roomID = roomID
    self.peerCount = peerCount
    self.presence = presence
    self.typing = typing
    self.emoji = emoji
    self.peerCountAfterDisconnect = peerCountAfterDisconnect
  }
}
