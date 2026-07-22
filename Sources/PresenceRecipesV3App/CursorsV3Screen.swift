#if canImport(SwiftUI)
  import InstantSwiftData
  import SwiftUI

  @MainActor
  @available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *)
  public struct CursorsV3Screen: View {
    @Room private var room: InstantRoom<CursorsV3Room>
    @Presence private var presence: [CursorsV3Presence]
    @StateObject private var model: CursorsV3Model

    #if os(tvOS)
      @State private var tvCursorX = 50.0
      @State private var tvCursorY = 50.0
    #endif

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
        pointerSurface(in: proxy)
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

    @ViewBuilder
    private func pointerSurface(in proxy: GeometryProxy) -> some View {
      let surface = ZStack(alignment: .topLeading) {
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

        #if os(tvOS) || os(watchOS)
          if let cursor = model.presence.cursor {
            cursorView(color: cursor.color)
              .position(
                x: proxy.size.width * cursor.xPercent / 100,
                y: proxy.size.height * cursor.yPercent / 100
              )
          }
        #endif
      }
      .contentShape(Rectangle())

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
