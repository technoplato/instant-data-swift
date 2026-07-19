import AuthV3App
import Dependencies
import Foundation
import InstantSwiftData

public struct MobileChatV3AppConfiguration: Hashable, Sendable {
  public var appID: String
  public var persistenceURL: URL?
  public var enablesLiveSync: Bool

  public init(appID: String, persistenceURL: URL? = nil, enablesLiveSync: Bool) {
    self.appID = appID
    self.persistenceURL = persistenceURL
    self.enablesLiveSync = enablesLiveSync
  }

  public static func environment(
    _ environment: [String: String] = ProcessInfo.processInfo.environment
  ) -> Self {
    let configuredAppID = environment["INSTANT_APP_ID"]?
      .trimmingCharacters(in: .whitespacesAndNewlines)
    return Self(
      appID: configuredAppID.flatMap { $0.isEmpty ? nil : $0 } ?? "mobile-chat-v3-local",
      persistenceURL: environment["INSTANT_PERSISTENCE_PATH"].map(URL.init(fileURLWithPath:)),
      enablesLiveSync: configuredAppID?.isEmpty == false
    )
  }
}

#if canImport(SwiftUI)
  import SwiftUI

  @MainActor
  public struct MobileChatV3Screen: View {
    @InstantAuth(AuthV3User.self, providers: AuthV3Providers.self) private var auth
    @FetchAll private var messages: [MobileChatMessage]
    @Room private var room: InstantRoom<MobileChatRoom>
    @Presence private var peers: [MobileChatPresence]
    @Topic(MobileChatRoom.Topic.typing)
    private var typing: InstantTopic<MobileChatTypingEvent>
    @Topic(MobileChatRoom.Topic.emoji)
    private var reactions: InstantTopic<MobileChatReaction>
    @Dependency(\.defaultInstantSwiftData) private var db
    @Dependency(\.date.now) private var now
    @Dependency(\.uuid) private var uuid

    @State private var content = ""
    @State private var status = "Ready"

    private let channelID: InstantID<MobileChatChannel>
    private let profile: MobileChatProfile?

    public init(
      channelID: InstantID<MobileChatChannel>,
      profile: MobileChatProfile? = nil
    ) {
      self.channelID = channelID
      self.profile = profile
    }

    public var body: some View {
      VStack {
        Text("\(peers.count + 1) in channel")
        List(messages) { message in
          Text(message.content)
        }
        TextField("Message", text: $content)
          .onChange(of: content, typingChanged)
        Button("Send", action: sendButtonTapped)
          .disabled(content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        Button("Send 👋", action: reactionButtonTapped)
          .disabled(!room.isJoined)
        Text("Typing events: \(typing.messages.count)")
        Text("Reactions: \(reactions.messages.count)")
        Text(status)
      }
      .instantFetch($messages, messagesQuery)
      .instantRoom(
        $room,
        InstantRoom<MobileChatRoom>(type: MobileChatRoom.roomType, id: channelID.rawValue)
      )
      .presence($peers, in: room, publishing: presence)
      .instantTopic($typing, in: room)
      .instantTopic($reactions, in: room)
    }

    private var messagesQuery: InstantQuery<MobileChatMessage> {
      MobileChatMessage.query
        .where(MobileChatMessage.channelID == channelID)
        .order(MobileChatMessage.timestampMilliseconds, .ascending)
    }

    private var presence: MobileChatPresence {
      MobileChatPresence(
        profileID: profile?.id.rawValue ?? auth.user?.id.rawValue ?? "anonymous",
        displayName: profile?.displayName ?? "Guest"
      )
    }

    private func sendButtonTapped() {
      let value = content.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !value.isEmpty else { return }
      db.send(
        SendMobileChatMessage(
          id: InstantID(rawValue: uuid().uuidString.lowercased()),
          channelID: channelID,
          authorProfileID: profile?.id,
          content: value,
          timestampMilliseconds: Int64((now.timeIntervalSince1970 * 1_000).rounded())
        ),
        onOptimisticCommit: { _ in content = "" },
        onServerAccepted: { _ in status = "Message synced" },
        onFailure: { error in status = error.recoveryMessage }
      )
    }

    private func typingChanged(_ oldValue: String, _ newValue: String) {
      let wasTyping = !oldValue.isEmpty
      let isTyping = !newValue.isEmpty
      guard wasTyping != isTyping else { return }
      typing.publish(MobileChatTypingEvent(isTyping: isTyping))
    }

    private func reactionButtonTapped() {
      reactions.publish(
        MobileChatReaction(
          name: .wave,
          directionAngle: 0,
          rotationAngle: 0
        ),
        onPublished: { _ in status = "Reaction sent" },
        onFailure: { error in status = error.recoveryMessage }
      )
    }
  }
#endif
