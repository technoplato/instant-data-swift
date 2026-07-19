#if canImport(SwiftUI)
  import InstantSwiftData
  import SwiftUI

  @MainActor
  public struct CursorsV3Screen: View {
    @Room private var room: InstantRoom<CursorsV3Room>
    @Presence private var presence: [CursorsV3Presence]
    @StateObject private var model: CursorsV3Model

    private let roomID: String

    public init(
      roomID: String = CursorsV3Room.defaultRoomID,
      profileID: String = UUID().uuidString,
      color: String? = nil
    ) {
      self.roomID = roomID
      let resolvedColor = color ?? CursorsV3Model.color(
        red: .random(in: 0..<200),
        green: .random(in: 0..<200),
        blue: .random(in: 0..<200)
      )
      _model = StateObject(
        wrappedValue: CursorsV3Model(profileID: profileID, color: resolvedColor)
      )
    }

    public var body: some View {
      GeometryReader { proxy in
        ZStack(alignment: .topLeading) {
          Color.white
          Text("Move your cursor around!")
            .font(.caption)
            .foregroundStyle(.secondary)
            .italic()
            .frame(maxWidth: .infinity, maxHeight: .infinity)

          ForEach(model.peers) { peer in
            if let cursor = peer.cursor {
              cursorView(color: cursor.color)
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
        InstantRoom<CursorsV3Room>(type: CursorsV3Room.roomType, id: roomID)
      )
      .presence($presence, in: room, publishing: model.presence)
      .onChange(of: presence) { _, values in
        model.updatePresence(values)
      }
      .navigationTitle("Cursors")
    }

    private func cursorView(color: String) -> some View {
      Image(systemName: "cursorarrow")
        .font(.system(size: 28, weight: .bold))
        .foregroundStyle(Color(hex: color))
        .shadow(radius: 1)
    }
  }

  private extension Color {
    init(hex: String) {
      let value = UInt64(hex.dropFirst(), radix: 16) ?? 0
      self.init(
        red: Double((value >> 16) & 0xff) / 255,
        green: Double((value >> 8) & 0xff) / 255,
        blue: Double(value & 0xff) / 255
      )
    }
  }
#endif
