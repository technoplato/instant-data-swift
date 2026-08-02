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
        ["magic-code", "apple", "google"]
      )
      expectNoDifference(
        AuthV3Providers.all.map(\.kind),
        [.magicCode, .idToken, .authorizationCode]
      )
      let auth = InstantAuthState<AuthV3User>(providers: AuthV3Providers.all)
      expectNoDifference(
        auth.credentialProviders.map(\.id.rawValue),
        ["apple", "google"]
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
          "INSTANT_APP_ID": "28c98cc4-e65b-41be-a5bc-204827f5d364",
          "INSTANT_PERSISTENCE_PATH": "/tmp/auth-v3.sqlite",
        ]),
        AuthV3AppConfiguration(
          appID: "28c98cc4-e65b-41be-a5bc-204827f5d364",
          persistenceURL: URL(fileURLWithPath: "/tmp/auth-v3.sqlite"),
          enablesLiveSync: true
        )
      )
    }

    @Test
    func providerConfigurationKeepsDashboardNamesAndCallbackAppOwned() throws {
      let redirectURL = try #require(URL(string: "scribe-auth://oauth-callback"))
      let providers = AuthV3Providers.providers(
        configuration: AuthV3ProviderConfiguration(
          appleClientName: "apple-scribe",
          applePresentation: .native,
          googleClientName: "google-scribe",
          googlePresentation: .externalBrowser,
          browserRedirectURL: redirectURL
        )
      )

      expectNoDifference(providers.map(\.clientName), [nil, "apple-scribe", "google-scribe"])
      expectNoDifference(providers.map(\.kind), [.magicCode, .idToken, .authorizationCode])
      expectNoDifference(providers.last?.redirectURL, redirectURL)
    }

    @Test
    func legacyProviderPropertiesRemainSourceCompatible() {
      expectNoDifference(
        [
          AuthV3Providers.apple.id.rawValue,
          AuthV3Providers.google.id.rawValue,
          AuthV3Providers.github.id.rawValue,
          AuthV3Providers.enterprise.id.rawValue,
        ],
        ["apple", "google", "github", "enterprise-oidc"]
      )
      expectNoDifference(
        [
          AuthV3Providers.apple.clientName,
          AuthV3Providers.google.clientName,
          AuthV3Providers.github.clientName,
          AuthV3Providers.enterprise.clientName,
        ],
        ["apple", "google-ios", "github-web", "enterprise-oidc"]
      )
    }
  }
#endif
