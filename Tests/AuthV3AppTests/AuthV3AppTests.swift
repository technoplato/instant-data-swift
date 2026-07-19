import CustomDump
import Foundation
import InstantSwiftData
import Testing
@testable import AuthV3App

#if canImport(SwiftUI)
  import SwiftUI

  @Suite
  struct AuthV3AppTests {
    @Test @MainActor
    func desiredPublicSyntaxCompilesWithAppOwnedUserAndProviders() throws {
      let screen = AuthV3LoginScreen()
      let view: any View = screen
      _ = view

      expectNoDifference(
        AuthV3Providers.all.map(\.id.rawValue),
        ["magic-code", "apple", "google", "github", "enterprise-oidc"]
      )
      expectNoDifference(
        AuthV3Providers.all.map(\.kind),
        [.magicCode, .idToken, .idToken, .authorizationCode, .authorizationCode]
      )
      expectNoDifference(AuthV3User.instantNamespace, "$users")

      let user = try AuthV3User(
        snapshot: InstantEntitySnapshot(
          id: "auth-v3-user",
          values: ["email": [.string("person@example.com")]]
        )
      )
      expectNoDifference(user.id.rawValue, "auth-v3-user")
      expectNoDifference(user.email, "person@example.com")
    }

    @Test
    func environmentConfigurationSelectsLocalAndLiveModes() {
      expectNoDifference(
        AuthV3AppConfiguration.environment([:]),
        AuthV3AppConfiguration(appID: "auth-v3-local", enablesLiveSync: false)
      )
      expectNoDifference(
        AuthV3AppConfiguration.environment([
          "INSTANT_APP_ID": "auth-live",
          "INSTANT_PERSISTENCE_PATH": "/tmp/auth-v3.sqlite",
        ]),
        AuthV3AppConfiguration(
          appID: "auth-live",
          persistenceURL: URL(fileURLWithPath: "/tmp/auth-v3.sqlite"),
          enablesLiveSync: true
        )
      )
    }
  }
#endif
