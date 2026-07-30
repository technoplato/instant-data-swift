import Foundation
import RecipesV3App
import SwiftUI

@main
struct RecipesV3Executable: App {
  @StateObject private var bootstrap: RecipesV3BootstrapModel

  init() {
    Self.logBuildProvenance()
    do {
      let configuration = try RecipesV3AppConfiguration.validatedEnvironment()
      _bootstrap = StateObject(
        wrappedValue: RecipesV3BootstrapModel(
          configuration: configuration
        )
      )
    } catch {
      _bootstrap = StateObject(
        wrappedValue: RecipesV3BootstrapModel(configurationError: error)
      )
    }
  }

  var body: some Scene {
    WindowGroup {
      RecipesV3BootstrapScreen(model: bootstrap)
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
