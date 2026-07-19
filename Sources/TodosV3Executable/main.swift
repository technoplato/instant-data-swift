import SwiftUI
import TodosV3App

@main
struct TodosV3Executable: App {
  @StateObject private var bootstrap = TodosBootstrapModel(
    configuration: .environment()
  )

  var body: some Scene {
    WindowGroup {
      TodosBootstrapScreen(model: bootstrap)
    }
  }
}
