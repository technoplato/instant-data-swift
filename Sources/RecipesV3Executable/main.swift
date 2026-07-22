import RecipesV3App
import SwiftUI

@main
struct RecipesV3Executable: App {
  @StateObject private var bootstrap = RecipesV3BootstrapModel(
    configuration: .environment()
  )

  var body: some Scene {
    WindowGroup {
      RecipesV3BootstrapScreen(model: bootstrap)
    }
  }
}
