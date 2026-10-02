import CustomDump
import Dependencies
import Foundation
import InstantSwiftData
import Testing

@testable import AuthV3App

#if canImport(SwiftUI)
  import SwiftUI

  #if os(macOS)
    import AppKit
  #endif

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
      expectNoDifference(AuthPublicCounter.instantNamespace, "recipe_public_counters")
      expectNoDifference(AuthAccountCounter.instantNamespace, "recipe_account_counters")
      #expect(
        Set(AuthV3CounterAttributes.all.map(\.namespace)).isSuperset(
          of: ["recipe_public_counters", "recipe_account_counters"]
        )
      )
      let countersCard = AuthV3CountersCard(session: nil)
      let countersView: any View = countersCard
      _ = countersView

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

    @Test @MainActor
    func demoCountersShowUnlessTheAppTurnsThemOff() {
      #expect(EnvironmentValues().authV3ShowsDemoCounters)
    }

    /// Linked sign-ins read and write `accountLinks`, which only apps that declare account links have (#361).
    @Test @MainActor
    func linkedSignInsStayHiddenUnlessTheAppTurnsThemOn() {
      #expect(EnvironmentValues().authV3ShowsLinkedSignIns == false)
      let screen: any View = AuthV3LoginScreen().environment(\.authV3ShowsLinkedSignIns, true)
      _ = screen
    }

    /// Hosts log `recipes.auth.link.failed`, and an auth message can name the email address a sign-in used.
    @Test @MainActor
    func linkFailureNotificationsCarryNoEmailAddress() {
      expectNoDifference(
        AuthV3LoginScreen.redactingEmailAddresses(
          "No pending magic code exists for 'b.person+scribe@example.co.uk'; retry b@x.io."
        ),
        "No pending magic code exists for '<email>'; retry <email>."
      )
    }

    #if os(macOS)
      /// The counters card creates the demo's public counter row when it appears.
      ///
      /// Two login screens appear together, each with its own local-only client on the Auth recipe's schema. The
      /// default screen's row shows that both screens' appearance work ran, so the screen with the counters turned
      /// off must have written nothing by then.
      @Test @MainActor
      func loginScreenWritesTheDemoCounterOnlyWhileItShowsTheCounters() async throws {
        let directory = URL.temporaryDirectory.appending(path: "auth-v3-counters-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let shown = try await Self.localClient(persistenceURL: directory.appending(path: "shown.sqlite"))
        let hidden = try await Self.localClient(persistenceURL: directory.appending(path: "hidden.sqlite"))

        let screens = [
          Self.render(AuthV3LoginScreen(), client: shown),
          Self.render(AuthV3LoginScreen().environment(\.authV3ShowsDemoCounters, false), client: hidden),
        ]
        let deadline = ContinuousClock.now + .seconds(5)
        while try await shown.query(AuthPublicCounter.query).isEmpty {
          guard ContinuousClock.now < deadline else {
            Issue.record("The default login screen created no public counter row within 5 seconds.")
            return
          }
          Self.runMainRunLoop(for: .milliseconds(50))
        }

        let hiddenScreenCounters = try await hidden.query(AuthPublicCounter.query)
        expectNoDifference(hiddenScreenCounters, [])
        withExtendedLifetime(screens) {}
      }

      private static func localClient(persistenceURL: URL) async throws -> InstantSwiftDataClient {
        try await withDependencies {
          try await $0.bootstrapInstantSwiftData(
            appID: "auth-v3-counters-\(UUID().uuidString)",
            persistenceURL: persistenceURL,
            context: .test,
            initialAttributes: AuthV3User.instantAttributes + AuthV3CounterAttributes.all
          )
        } operation: {
          @Dependency(\.defaultInstantSwiftData) var client
          return client
        }
      }

      /// Lays out `view` in a window-less hosting view. SwiftUI starts the view's tasks from this layout pass, and
      /// they keep the dependencies in effect here.
      @MainActor
      private static func render(_ view: some View, client: InstantSwiftDataClient) -> NSView {
        withDependencies {
          $0.defaultInstantSwiftData = client
        } operation: {
          let host = NSHostingView(rootView: view)
          host.frame = CGRect(x: 0, y: 0, width: 520, height: 1_400)
          host.layoutSubtreeIfNeeded()
          return host
        }
      }

      /// Lets AppKit and SwiftUI finish pending view updates on the main run loop.
      @MainActor
      private static func runMainRunLoop(for duration: Duration) {
        let seconds = Double(duration.components.seconds)
          + Double(duration.components.attoseconds) / 1e18
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
      }
    #endif

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
