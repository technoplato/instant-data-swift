import SwiftUI
import SyncUpsV3App

@main
struct SyncUpsV3Executable: App {
  @StateObject private var bootstrap = SyncUpsV3BootstrapModel(
    configuration: .environment()
  )

  var body: some Scene {
    WindowGroup {
      SyncUpsV3BootstrapScreen(model: bootstrap)
    }
  }
}
