import RemindersV3App
import SwiftUI

@main
struct RemindersV3Executable: App {
  @StateObject private var bootstrap = RemindersV3BootstrapModel(
    configuration: .environment()
  )

  var body: some Scene {
    WindowGroup {
      RemindersV3BootstrapScreen(model: bootstrap)
    }
  }
}
