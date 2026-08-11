import SwiftUI
import TranscriptionApp

@main
struct TranscriptionExecutable: App {
  @StateObject private var bootstrap = TranscriptionBootstrapModel(
    configuration: .environment()
  )

  var body: some Scene {
    WindowGroup {
      TranscriptionBootstrapScreen(model: bootstrap)
    }
  }
}
