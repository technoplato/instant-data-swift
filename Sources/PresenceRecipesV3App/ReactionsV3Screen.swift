#if canImport(SwiftUI)
  import InstantSwiftData
  import SwiftUI

  @MainActor
  public struct ReactionsV3Screen: View {
    @Room private var room: InstantRoom<ReactionsV3Room>
    @Topic(ReactionsV3Room.Topic.emoji)
    private var reactions: InstantTopic<ReactionsV3Payload>
    @StateObject private var model = ReactionsV3Model()

    private let roomID: String

    public init(roomID: String = "123") {
      self.roomID = roomID
    }

    public var body: some View {
      HStack(spacing: 16) {
        ForEach(ReactionsV3Name.allCases, id: \.self) { name in
          ZStack {
            Button(name.symbol) {
              reactionButtonTapped(name)
            }
            .font(.system(size: 32))
            .buttonStyle(.bordered)
            .disabled(!room.isJoined)

            ForEach(model.animations.filter { $0.name == name }) { animation in
              ReactionsV3Burst(animation: animation) {
                model.dismissAnimation(id: animation.id)
              }
            }
          }
        }
      }
      .padding()
      .navigationTitle("Reactions")
      .instantRoom(
        $room,
        InstantRoom<ReactionsV3Room>(
          type: ReactionsV3Room.roomType,
          id: roomID
        )
      )
      .instantTopic($reactions, in: room)
      .onChange(of: reactions.messages) { _, messages in
        model.observe(messages)
      }
    }

    private func reactionButtonTapped(_ name: ReactionsV3Name) {
      let payload = model.reactionButtonTapped(
        name,
        directionAngle: Double.random(in: 0..<360),
        rotationAngle: Double.random(in: 0..<360)
      )
      reactions.publish(payload)
    }
  }

  @MainActor
  private struct ReactionsV3Burst: View {
    let animation: ReactionsV3Animation
    let completed: @MainActor () -> Void

    @State private var isAnimating = false

    var body: some View {
      Text(animation.name.symbol)
        .font(.system(size: 40))
        .rotationEffect(.degrees(animation.payload.rotationAngle * 400))
        .offset(y: isAnimating ? 160 : 0)
        .scaleEffect(isAnimating ? 2 : 1)
        .opacity(isAnimating ? 0 : 1)
        .rotationEffect(.degrees(animation.payload.directionAngle * 360))
        .allowsHitTesting(false)
        .task {
          try? await Task.sleep(for: .milliseconds(20))
          withAnimation(.easeInOut(duration: 0.4)) {
            isAnimating = true
          }
          try? await Task.sleep(for: .milliseconds(780))
          completed()
        }
    }
  }
#endif
