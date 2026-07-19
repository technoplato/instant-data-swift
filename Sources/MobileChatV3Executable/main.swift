import MobileChatV3App
import InstantSwiftData
import SwiftUI

@main
struct MobileChatV3Executable: App {
  var body: some Scene {
    WindowGroup {
      MobileChatV3Screen(
        channelID: InstantID(rawValue: "00000000-0000-4000-8000-000000000001")
      )
    }
  }
}
