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
          namespace: AuthV3User.instantNamespace,
          values: ["email": .one(.string("person@example.com"))]
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

    @Test @MainActor
    func localMagicCodeChallengeIsVisibleAndReadyForManualVerification() {
      let localChallenge = InstantMagicCodeChallenge(
        appID: "auth-local",
        email: "desert@example.com",
        code: "246810",
        createdAt: InstantTimestamp(milliseconds: 1_000),
        expiresAt: InstantTimestamp(milliseconds: 61_000)
      )
      expectNoDifference(
        AuthV3LoginScreen.challengeMessage(localChallenge),
        "Code sent to desert@example.com. Local code: 246810"
      )
      expectNoDifference(AuthV3LoginScreen.autofillCode(localChallenge), "246810")

      var remoteChallenge = localChallenge
      remoteChallenge.code = ""
      expectNoDifference(
        AuthV3LoginScreen.challengeMessage(remoteChallenge),
        "Code sent to desert@example.com"
      )
      expectNoDifference(AuthV3LoginScreen.autofillCode(remoteChallenge), nil)
    }

    @Test @MainActor
    func externalProviderAvailabilityIsExplicitForOfflineConfigurations() {
      expectNoDifference(
        AuthV3LoginScreen.externalProvidersNotice(allowsExternalProviders: true),
        nil
      )
      expectNoDifference(
        AuthV3LoginScreen.externalProvidersNotice(allowsExternalProviders: false),
        """
        External providers are unavailable in this offline configuration. \
        Use guest or local magic code.
        """
      )

      let screen = AuthV3LoginScreen(allowsExternalProviders: false)
      let view: any View = screen
      _ = view
    }
  }
#endif
