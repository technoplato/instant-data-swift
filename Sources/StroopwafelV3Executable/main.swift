import StroopwafelV3App
import SwiftUI

@main
struct StroopwafelV3Executable: App {
  @StateObject private var bootstrap = StroopwafelV3BootstrapModel(
    configuration: .environment()
  )

  var body: some Scene {
    WindowGroup {
      StroopwafelV3BootstrapScreen(model: bootstrap)
    }
  }
}
