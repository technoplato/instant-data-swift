#if canImport(SwiftUI)
  import InstantSwiftData
  import SwiftUI

  @MainActor
  @available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *)
  public struct CustomCursorsV3Screen: View {
    @Room private var room: InstantRoom<CustomCursorsV3Room>
    @Presence private var presence: [CustomCursorsV3Presence]
    @StateObject private var model: CustomCursorsV3Model

    #if os(tvOS)
      @State private var tvCursorX = 50.0
      @State private var tvCursorY = 50.0
    #endif

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
        pointerSurface(in: proxy)
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

    @ViewBuilder
    private func pointerSurface(in proxy: GeometryProxy) -> some View {
      let surface = ZStack(alignment: .topLeading) {
        Color.white
        Text("You can customize your cursors too!")
          .font(.caption)
          .foregroundStyle(.secondary)
          .italic()
          .frame(maxWidth: .infinity, maxHeight: .infinity)

        HStack(spacing: 10) {
          customCursor(name: model.presence.name, color: model.color)
          VStack(alignment: .leading, spacing: 2) {
            Text(model.presence.name)
              .font(.subheadline.bold())
            Text("Drag anywhere to move your cursor")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }
        .padding(10)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .padding(12)
        .allowsHitTesting(false)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Your custom cursor, \(model.presence.name)")
        .accessibilityHint("Drag anywhere to move it")

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

        #if os(iOS) || os(tvOS) || os(watchOS)
          if let localCursor = model.localCursor,
            let cursor = localCursor.cursor
          {
            customCursor(name: localCursor.name, color: cursor.color)
              .position(
                x: proxy.size.width * cursor.xPercent / 100,
                y: proxy.size.height * cursor.yPercent / 100
              )
          }
        #endif
      }
      .contentShape(Rectangle())
      .accessibilityLabel("Custom cursor canvas")
      .accessibilityHint("Drag anywhere to move your custom cursor")

      #if os(tvOS)
        surface.overlay(alignment: .bottom) { tvCursorControls }
      #elseif os(macOS)
        surface.onContinuousHover(coordinateSpace: .local) { phase in
          switch phase {
          case let .active(location):
            model.movePointer(
              clientX: location.x,
              clientY: location.y,
              frame: CursorsV3Frame(
                left: 0,
                top: 0,
                width: proxy.size.width,
                height: proxy.size.height
              )
            )
          case .ended:
            model.clearPointer()
          }
        }
      #else
        surface.gesture(
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
      #endif
    }

    #if os(tvOS)
      private var tvCursorControls: some View {
        HStack(spacing: 24) {
          Button { tvDirectionButtonTapped(x: -10, y: 0) } label: {
            Label("Left", systemImage: "arrow.left")
          }
          Button { tvDirectionButtonTapped(x: 0, y: -10) } label: {
            Label("Up", systemImage: "arrow.up")
          }
          Button("Clear", action: model.clearPointer)
          Button { tvDirectionButtonTapped(x: 0, y: 10) } label: {
            Label("Down", systemImage: "arrow.down")
          }
          Button { tvDirectionButtonTapped(x: 10, y: 0) } label: {
            Label("Right", systemImage: "arrow.right")
          }
        }
        .buttonStyle(.bordered)
        .padding(18)
        .background(.black.opacity(0.72), in: Capsule())
        .padding(.bottom, 24)
      }

      private func tvDirectionButtonTapped(x deltaX: Double, y deltaY: Double) {
        tvCursorX = min(max(tvCursorX + deltaX, 0), 100)
        tvCursorY = min(max(tvCursorY + deltaY, 0), 100)
        model.movePointer(
          clientX: tvCursorX,
          clientY: tvCursorY,
          frame: CursorsV3Frame(left: 0, top: 0, width: 100, height: 100)
        )
      }
    #endif
  }
#endif
