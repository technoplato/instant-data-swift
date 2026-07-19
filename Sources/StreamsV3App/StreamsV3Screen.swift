import SwiftUI

public struct StreamsV3Screen: View {
  @State private var model: StreamsV3Model
  @State private var draft = "Hello from Swift 🚀"

  public init(model: StreamsV3Model = StreamsV3Model()) {
    _model = State(initialValue: model)
  }

  public var body: some View {
    NavigationStack {
      Form {
        Section("Writer") {
          TextField("Client ID", text: $model.clientID)
          TextField("Content", text: $draft, axis: .vertical)
          Button("Write stream") {
            let chunks = draft.split(separator: " ", omittingEmptySubsequences: false)
              .enumerated()
              .map { index, part in index == 0 ? String(part) : " " + part }
            Task { await model.write(chunks) }
          }
        }
        Section("Reader") {
          Button("Resume by client ID") { model.resume() }
          Button("Cancel reader", role: .cancel) { model.cancelReader() }
          Text(model.content).textSelection(.enabled)
        }
        Section("State") {
          LabeledContent("Status", value: model.status)
          LabeledContent("Bytes", value: String(model.byteCount))
          if let streamID = model.streamID {
            LabeledContent("Stream ID", value: streamID)
          }
          if let error = model.errorMessage {
            Text(error).foregroundStyle(.red)
          }
        }
      }
      .navigationTitle("Resumable Stream")
    }
  }
}
