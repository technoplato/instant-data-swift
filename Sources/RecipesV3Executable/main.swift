import Foundation
import RecipesV3App
import SwiftUI

@main
struct RecipesV3Executable: App {
  @State private var demo: RecipesV3DemoModel

  init() {
    Self.logBuildProvenance()
    do {
      let configuration = try RecipesV3DemoConfiguration.validatedEnvironment()
      _demo = State(
        initialValue: RecipesV3DemoModel(
          configuration: configuration
        )
      )
    } catch {
      _demo = State(
        initialValue: RecipesV3DemoModel(configurationError: error)
      )
    }
  }

  var body: some Scene {
    WindowGroup {
      RecipesV3DemoScreen(model: demo)
    }
  }

  private static func logBuildProvenance() {
    guard let url = Bundle.main.url(forResource: "BuildProvenance", withExtension: "json"),
      let data = try? Data(contentsOf: url),
      let object = try? JSONSerialization.jsonObject(with: data),
      let compactData = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
      let json = String(data: compactData, encoding: .utf8)
    else {
      print("Instant Recipes build provenance unavailable")
      return
    }
    print("Instant Recipes build provenance \(json)")
  }
}
