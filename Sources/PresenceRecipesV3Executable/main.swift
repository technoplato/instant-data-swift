import PresenceRecipesV3App

#if canImport(SwiftUI)
  import SwiftUI

  @main
  struct PresenceRecipesV3Executable: App {
    var body: some Scene {
      WindowGroup {
        NavigationStack {
          TypingIndicatorV3Screen(
            roomID: "main",
            profileID: "presence-recipes-v3-user",
            options: TypingIndicatorV3Options(stopOnSubmit: true)
          )
        }
      }
    }
  }
#endif
