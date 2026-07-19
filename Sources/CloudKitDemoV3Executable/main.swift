import CloudKitDemoV3App

#if canImport(SwiftUI)
  import SwiftUI

  @main
  struct CloudKitDemoV3Executable: App {
    var body: some Scene {
      WindowGroup {
        CloudKitDemoV3BootstrapScreen(
          model: CloudKitDemoV3BootstrapModel(
            configuration: .environment()
          )
        )
      }
    }
  }
#else
  @main
  enum CloudKitDemoV3Executable {
    static func main() {
      print("cloudkit-demo-v3 requires SwiftUI")
    }
  }
#endif
