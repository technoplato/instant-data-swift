import AppBuilderV3App
import SwiftUI

@main
struct AppBuilderV3Executable: App {
  @StateObject private var bootstrap = AppBuilderV3BootstrapModel(
    configuration: .environment()
  )

  var body: some Scene {
    WindowGroup {
      AppBuilderV3BootstrapScreen(model: bootstrap)
    }
  }
}
