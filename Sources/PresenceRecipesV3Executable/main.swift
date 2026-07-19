import PresenceRecipesV3App

#if canImport(SwiftUI)
  import SwiftUI

  @main
  struct PresenceRecipesV3Executable: App {
    var body: some Scene {
      WindowGroup {
        NavigationStack {
          List {
            NavigationLink("Typing Indicator") {
              TypingIndicatorV3Screen(
                roomID: "1234",
                profileID: "presence-recipes-v3-user",
                options: TypingIndicatorV3Options(stopOnSubmit: true)
              )
            }
            NavigationLink("Reactions") {
              ReactionsV3Screen(roomID: "123")
            }
            NavigationLink("Avatar Stack") {
              AvatarStackV3Screen(
                roomID: AvatarStackV3Room.defaultRoomID,
                profileID: "abcdef123456"
              )
            }
            NavigationLink("Cursors") {
              CursorsV3Screen(
                roomID: CursorsV3Room.defaultRoomID,
                profileID: "cursors-v3-user",
                color: "#123456"
              )
            }
          }
          .navigationTitle("Presence Recipes")
        }
      }
    }
  }
#endif
