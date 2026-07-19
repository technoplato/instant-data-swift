import CustomDump
import Foundation
import InstantSwiftData
import MobileChatV3App
import Testing

#if canImport(SwiftUI)
  import SwiftUI

  @Suite
  struct MobileChatV3AppTests {
    @Test @MainActor
    func desiredPublicSyntaxCompilesWithAppOwnedModelsAndRoom() throws {
      let channelID = InstantID<MobileChatChannel>(
        rawValue: "00000000-0000-4000-8000-000000000001"
      )
      let screen: any View = MobileChatV3Screen(channelID: channelID)
      _ = screen

      expectNoDifference(
        [
          MobileChatProfile.instantNamespace,
          MobileChatChannel.instantNamespace,
          MobileChatMessage.instantNamespace,
        ],
        ["profiles", "channels", "messages"]
      )
      expectNoDifference(MobileChatRoom.roomType, "chat")
      expectNoDifference(
        MobileChatPresence(
          profileID: "00000000-0000-4000-8000-000000000002",
          displayName: "Swift Chatter"
        ),
        MobileChatPresence(
          profileID: "00000000-0000-4000-8000-000000000002",
          displayName: "Swift Chatter"
        )
      )

      let message = try MobileChatMessage(
        snapshot: InstantEntitySnapshot(
          id: "00000000-0000-4000-8000-000000000003",
          namespace: MobileChatMessage.instantNamespace,
          values: [
            "channel": .one(.ref(channelID.rawValue)),
            "author": .one(.ref("00000000-0000-4000-8000-000000000002")),
            "content": .one(.string("Exact mobile chat payload")),
            "timestamp": .one(.number(1_700_000_003_000)),
          ]
        )
      )
      expectNoDifference(message.channelID, channelID)
      expectNoDifference(message.content, "Exact mobile chat payload")
      expectNoDifference(message.timestampMilliseconds, 1_700_000_003_000)
    }

    @Test
    func environmentConfigurationSelectsLocalAndLiveModes() {
      expectNoDifference(
        MobileChatV3AppConfiguration.environment([:]),
        MobileChatV3AppConfiguration(
          appID: "mobile-chat-v3-local",
          enablesLiveSync: false
        )
      )
      expectNoDifference(
        MobileChatV3AppConfiguration.environment([
          "INSTANT_APP_ID": "mobile-chat-live",
          "INSTANT_PERSISTENCE_PATH": "/tmp/mobile-chat-v3.sqlite",
        ]),
        MobileChatV3AppConfiguration(
          appID: "mobile-chat-live",
          persistenceURL: URL(fileURLWithPath: "/tmp/mobile-chat-v3.sqlite"),
          enablesLiveSync: true
        )
      )
    }

    @Test
    func appOwnedEntitiesMatchTheCanonicalMobileChatSchema() throws {
      expectNoDifference(MobileChatProfile.instantNamespace, "profiles")
      expectNoDifference(MobileChatChannel.instantNamespace, "channels")
      expectNoDifference(MobileChatMessage.instantNamespace, "messages")

      let profileUser = try #require(
        MobileChatProfile.instantAttributes.first { $0.name == "user" }
      )
      expectNoDifference(profileUser.forwardIdentity, "profiles/user")
      expectNoDifference(profileUser.reverseIdentity, "$users/profile")
      expectNoDifference(profileUser.linkNamespace, "$users")
      expectNoDifference(profileUser.onDelete, .cascade)

      let messageAuthor = try #require(
        MobileChatMessage.instantAttributes.first { $0.name == "author" }
      )
      expectNoDifference(messageAuthor.forwardIdentity, "messages/author")
      expectNoDifference(messageAuthor.reverseIdentity, "profiles/messages")
      expectNoDifference(messageAuthor.linkNamespace, "profiles")
      expectNoDifference(messageAuthor.onDelete, .cascade)

      let messageChannel = try #require(
        MobileChatMessage.instantAttributes.first { $0.name == "channel" }
      )
      expectNoDifference(messageChannel.forwardIdentity, "messages/channel")
      expectNoDifference(messageChannel.reverseIdentity, "channels/messages")
      expectNoDifference(messageChannel.linkNamespace, "channels")
      expectNoDifference(messageChannel.onDelete, .cascade)
    }

    @Test @MainActor
    func roomTopicsUseTheCanonicalTypingAndEmojiPayloads() throws {
      let fixture: any View = MobileChatTopicsFixture()
      _ = fixture

      expectNoDifference(MobileChatRoom.Topic.typing.rawValue, "typing")
      expectNoDifference(MobileChatRoom.Topic.emoji.rawValue, "emoji")

      let encoder = JSONEncoder()
      encoder.outputFormatting = [.sortedKeys]
      expectNoDifference(
        String(
          decoding: try encoder.encode(
            MobileChatPresence(
              profileID: "00000000-0000-4000-8000-000000000002",
              displayName: "Swift Chatter"
            )
          ),
          as: UTF8.self
        ),
        #"{"displayName":"Swift Chatter","profileId":"00000000-0000-4000-8000-000000000002"}"#
      )
      expectNoDifference(
        String(
          decoding: try encoder.encode(MobileChatTypingEvent(isTyping: true)),
          as: UTF8.self
        ),
        #"{"isTyping":true}"#
      )
      expectNoDifference(
        String(
          decoding: try encoder.encode(
            MobileChatReaction(
              name: .wave,
              directionAngle: 90,
              rotationAngle: 180
            )
          ),
          as: UTF8.self
        ),
        #"{"directionAngle":90,"name":"wave","rotationAngle":180}"#
      )
    }
  }

  @MainActor
  private struct MobileChatTopicsFixture: View {
    @Room private var room: InstantRoom<MobileChatRoom>
    @Topic(MobileChatRoom.Topic.typing)
    private var typing: InstantTopic<MobileChatTypingEvent>
    @Topic(MobileChatRoom.Topic.emoji)
    private var reactions: InstantTopic<MobileChatReaction>

    var body: some View {
      Text("\(typing.messages.count):\(reactions.messages.count)")
        .instantRoom(
          $room,
          InstantRoom<MobileChatRoom>(type: MobileChatRoom.roomType, id: "source-contract")
        )
        .instantTopic($typing, in: room)
        .instantTopic($reactions, in: room)
    }
  }
#endif
