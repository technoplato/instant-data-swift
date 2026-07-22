#if canImport(SwiftUI)
  import InstantSwiftData
  import SwiftUI

  @MainActor
  @available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *)
  public struct AvatarStackV3Screen: View {
    @Room private var room: InstantRoom<AvatarStackV3Room>
    @Presence private var presence: [AvatarStackV3Presence]
    @StateObject private var model: AvatarStackV3Model

    private let roomID: String

    public init(
      roomID: String = AvatarStackV3Room.defaultRoomID,
      profileID: String
    ) {
      self.roomID = roomID
      _model = StateObject(wrappedValue: AvatarStackV3Model(profileID: profileID))
    }

    public var body: some View {
      List {
        Section("Online — \(model.onlineCount)") {
          if let currentUser = model.currentUser {
            avatarRow(currentUser)
          }
          ForEach(model.peers) { peer in
            avatarRow(peer)
          }
        }

        Text("Add more previews to see more avatars!")
          .font(.caption)
          .foregroundStyle(.secondary)
          .italic()
      }
      .navigationTitle("Avatar Stack")
      .instantRoom(
        $room,
        InstantRoom<AvatarStackV3Room>(
          type: AvatarStackV3Room.roomType,
          id: roomID
        )
      )
      .presence($presence, in: room, publishing: model.presence)
      .onChange(of: presence) { _, presence in
        model.updatePresence(presence)
      }
    }

    private func avatarRow(_ presence: AvatarStackV3Presence) -> some View {
      HStack(spacing: 10) {
        ZStack(alignment: .bottomTrailing) {
          Circle()
            .fill(.blue.gradient)
            .frame(width: 32, height: 32)
            .overlay {
              Text(String(presence.name.prefix(1)).uppercased())
                .font(.caption.bold())
                .foregroundStyle(.white)
            }
          Circle()
            .fill(.green)
            .frame(width: 10, height: 10)
            .overlay(Circle().stroke(.white, lineWidth: 2))
        }
        Text(presence.name)
      }
    }
  }
#endif
