#if canImport(SwiftUI)
  import Dependencies
  import InstantSwiftData
  import SwiftUI

  @MainActor
  public struct TypingIndicatorV3Screen: View {
    @Room private var room: InstantRoom<TypingIndicatorV3Room>
    @Presence private var peers: [TypingIndicatorPresence]
    @StateObject private var model: TypingIndicatorV3Model
    @State private var draft = ""
    @FocusState private var isInputFocused: Bool

    private let roomID: String

    public init(
      roomID: String,
      profileID: String,
      options: TypingIndicatorV3Options = TypingIndicatorV3Options()
    ) {
      self.roomID = roomID
      _model = StateObject(
        wrappedValue: TypingIndicatorV3Model(
          profileID: profileID,
          options: options
        )
      )
    }

    public var body: some View {
      Form {
        Section("Message") {
          TextField("Write a message", text: $draft)
            .focused($isInputFocused)
            .onChange(of: draft) { _, _ in keyPressed() }
            .onSubmit(submitButtonTapped)
        }

        Section("Typing") {
          if model.activePeers.isEmpty {
            Text("No one is typing")
          } else {
            ForEach(model.activePeers) { peer in
              Text("\(peer.id) is typing…")
            }
          }
        }
      }
      .navigationTitle("Typing Indicator")
      .instantRoom(
        $room,
        InstantRoom<TypingIndicatorV3Room>(
          type: TypingIndicatorV3Room.roomType,
          id: roomID
        )
      )
      .presence($peers, in: room, publishing: model.presence)
      .onChange(of: peers) { _, peers in peersChanged(peers) }
      .onChange(of: isInputFocused) { _, isFocused in focusChanged(isFocused) }
      .onDisappear(perform: screenDisappeared)
    }

    private func keyPressed() {
      model.keyDown(.character)
    }

    private func submitButtonTapped() {
      model.keyDown(.submit)
    }

    private func peersChanged(_ peers: [TypingIndicatorPresence]) {
      model.updatePeers(peers)
    }

    private func focusChanged(_ isFocused: Bool) {
      if !isFocused { model.blur() }
    }

    private func screenDisappeared() {
      model.stop()
    }
  }
#endif
