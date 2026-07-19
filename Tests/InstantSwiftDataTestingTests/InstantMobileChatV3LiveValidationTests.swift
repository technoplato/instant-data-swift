import CustomDump
import Foundation
import InstantSwiftDataTesting
import MobileChatV3App
import Testing

@Suite
struct InstantMobileChatV3LiveValidationTests {
  @Test
  func entityEvidenceDecodesExactCanonicalRelations() throws {
    let data = Data(
      #"{"direction":"swift-to-typescript","userID":"00000000-0000-4000-8000-000000000001","profileID":"00000000-0000-4000-8000-000000000002","displayName":"Swift Chatter","channelID":"00000000-0000-4000-8000-000000000003","channelName":"Swift Channel","messageID":"00000000-0000-4000-8000-000000000004","messageChannelID":"00000000-0000-4000-8000-000000000003","authorProfileID":"00000000-0000-4000-8000-000000000002","content":"Swift live message","timestampMilliseconds":1700000010000,"connectionState":"authenticated","pendingMutationCount":0}"#.utf8
    )
    let details = try JSONDecoder().decode(
      InstantMobileChatV3LiveValidationDetails.self,
      from: data
    )

    expectNoDifference(details.direction, "swift-to-typescript")
    expectNoDifference(details.profileID, "00000000-0000-4000-8000-000000000002")
    expectNoDifference(details.messageChannelID, details.channelID)
    expectNoDifference(details.authorProfileID, details.profileID)
    expectNoDifference(details.content, "Swift live message")
    expectNoDifference(details.timestampMilliseconds, 1_700_000_010_000)
    expectNoDifference(details.connectionState, "authenticated")
    expectNoDifference(details.pendingMutationCount, 0)
  }

  @Test
  func roomEvidenceDecodesExactPresenceTypingEmojiAndCleanup() throws {
    let data = Data(
      #"{"roomType":"chat","roomID":"00000000-0000-4000-8000-000000000003","peerCount":2,"presence":{"profileId":"00000000-0000-4000-8000-000000000002","displayName":"Swift Chatter"},"typing":{"isTyping":true},"emoji":{"name":"wave","directionAngle":90,"rotationAngle":180},"peerCountAfterDisconnect":1}"#.utf8
    )
    let details = try JSONDecoder().decode(
      InstantMobileChatV3RoomValidationDetails.self,
      from: data
    )

    expectNoDifference(details.roomType, "chat")
    expectNoDifference(details.peerCount, 2)
    expectNoDifference(details.presence.profileID, "00000000-0000-4000-8000-000000000002")
    expectNoDifference(details.typing.isTyping, true)
    expectNoDifference(details.emoji.name.rawValue, "wave")
    expectNoDifference(details.emoji.directionAngle, 90)
    expectNoDifference(details.emoji.rotationAngle, 180)
    expectNoDifference(details.peerCountAfterDisconnect, 1)
  }

  @Test
  func sessionEvidenceContainsBothSDKDirectionsAndRoomTraffic() throws {
    let entity = InstantMobileChatV3LiveValidationDetails(
      direction: "swift-to-typescript",
      userID: "user",
      profileID: "profile",
      displayName: "Swift Chatter",
      channelID: "channel",
      channelName: "Swift Channel",
      messageID: "message",
      messageChannelID: "channel",
      authorProfileID: "profile",
      content: "Swift live message",
      timestampMilliseconds: 1_700_000_010_000,
      connectionState: "authenticated",
      pendingMutationCount: 0
    )
    let room = InstantMobileChatV3RoomValidationDetails(
      roomType: "chat",
      roomID: "channel",
      peerCount: 2,
      presence: MobileChatPresence(profileID: "profile", displayName: "TypeScript Chatter"),
      typing: MobileChatTypingEvent(isTyping: false),
      emoji: MobileChatReaction(name: .heart, directionAngle: 45, rotationAngle: 270),
      peerCountAfterDisconnect: 1
    )
    let session = InstantMobileChatV3SessionValidationDetails(
      swift: entity,
      observedTypeScript: entity,
      room: room
    )

    expectNoDifference(session.swift.messageChannelID, "channel")
    expectNoDifference(session.observedTypeScript.authorProfileID, "profile")
    expectNoDifference(session.room.presence.displayName, "TypeScript Chatter")
  }
}
