import SwiftUI
import VoiceTrailV3App

@main
struct VoiceTrailV3Executable: App {
  @StateObject private var bootstrap = VoiceTrailBootstrapModel(
    configuration: .environment()
  )

  var body: some Scene {
    WindowGroup {
      VoiceTrailBootstrapScreen(model: bootstrap)
    }
  }
}
