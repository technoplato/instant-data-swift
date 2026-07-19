import AuthV3App
import SwiftUI

@main
struct AuthV3Executable: App {
  @StateObject private var bootstrap = AuthV3BootstrapModel(
    configuration: .environment()
  )

  var body: some Scene {
    WindowGroup {
      AuthV3BootstrapScreen(model: bootstrap)
    }
  }
}
