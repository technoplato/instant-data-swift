#if canImport(SwiftUI)
  import InstantSwiftData
  import SwiftUI

  @MainActor
  public struct CustomCursorsV3Screen: View {
    @Room private var room: InstantRoom<CustomCursorsV3Room>
    @Presence private var presence: [CustomCursorsV3Presence]
    @StateObject private var model: CustomCursorsV3Model

    private let roomID: String

    public init(
      roomID: String = CustomCursorsV3Room.defaultRoomID,
      profileID: String = UUID().uuidString,
      name: String = UUID().uuidString,
      color: String? = nil
    ) {
      self.roomID = roomID
      let resolvedColor = color ?? CursorsV3Model.color(
        red: .random(in: 0..<200),
        green: .random(in: 0..<200),
        blue: .random(in: 0..<200)
      )
      _model = StateObject(
        wrappedValue: CustomCursorsV3Model(
          profileID: profileID,
          name: name,
          color: resolvedColor
        )
      )
    }

    public var body: some View {
      GeometryReader { proxy in
        ZStack(alignment: .topLeading) {
          Color.white
          Text("You can customize your cursors too!")
            .font(.caption)
            .foregroundStyle(.secondary)
            .italic()
            .frame(maxWidth: .infinity, maxHeight: .infinity)

          ForEach(model.peers) { peer in
            if let cursor = peer.cursor {
              customCursor(name: peer.name, color: cursor.color)
                .position(
                  x: proxy.size.width * cursor.xPercent / 100,
                  y: proxy.size.height * cursor.yPercent / 100
                )
                .animation(.linear(duration: 0.1), value: cursor.xPercent)
                .animation(.linear(duration: 0.1), value: cursor.yPercent)
            }
          }
        }
        .contentShape(Rectangle())
        .gesture(
          DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
              model.movePointer(
                clientX: value.location.x,
                clientY: value.location.y,
                frame: CursorsV3Frame(
                  left: 0,
                  top: 0,
                  width: proxy.size.width,
                  height: proxy.size.height
                )
              )
            }
            .onEnded { _ in model.clearPointer() }
        )
      }
      .instantRoom(
        $room,
        InstantRoom<CustomCursorsV3Room>(
          type: CustomCursorsV3Room.roomType,
          id: roomID
        )
      )
      .presence($presence, in: room, publishing: model.presence)
      .onChange(of: presence) { _, values in
        model.updatePresence(values)
      }
      .navigationTitle("Custom Cursors")
    }

    private func customCursor(name: String, color: String) -> some View {
      Circle()
        .fill(customCursorColor(color).gradient)
        .frame(width: 40, height: 40)
        .overlay {
          Text(String(name.prefix(1)).uppercased())
            .font(.headline.bold())
            .foregroundStyle(.white)
        }
        .overlay(Circle().stroke(.white, lineWidth: 2))
        .shadow(radius: 2)
    }

    private func customCursorColor(_ hex: String) -> Color {
      let value = UInt64(hex.dropFirst(), radix: 16) ?? 0
      return Color(
        red: Double((value >> 16) & 0xff) / 255,
        green: Double((value >> 8) & 0xff) / 255,
        blue: Double(value & 0xff) / 255
      )
    }
  }
#endif
