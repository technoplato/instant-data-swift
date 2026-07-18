import CustomDump
import Foundation
import InstantSwiftData
import Testing

@Suite
struct InstantAuthProviderTests {
  private let sourceReferences = [
    "upstream/instant/client/packages/core/src/authAPI.ts:8-27,122-184",
    "upstream/instant/client/packages/cli/__tests__/authClientAddApple.test.ts:213-228",
    "upstream/instant/client/packages/cli/__tests__/authClientAddGoogle.test.ts:352-371",
    "upstream/instant/client/packages/cli/__tests__/authClientAddGithub.test.ts:187-205",
    "screens/v3/auth-login.md:216-264",
  ]

  @Test
  func providerFactoriesPreserveCanonicalIDsClientsAndPresentation() {
    let magicCode = AuthProvider.magicCode(
      email: .instant,
      extraFields: AuthProviderSignupFixture.self
    )
    let apple = AuthProvider.apple(clientName: "apple-ios", presentation: .native)
    let google = AuthProvider.google(clientName: "google-ios", presentation: .native)
    let github = AuthProvider.github(
      clientName: "github-web",
      presentation: .externalBrowser
    )
    let enterprise = AuthProvider.authorizationCode(
      id: "enterprise-oidc",
      clientName: "enterprise-oidc"
    )

    expectNoDifference(magicCode.id, .magicCode)
    expectNoDifference(magicCode.kind, .magicCode)
    expectNoDifference(magicCode.clientName, nil)
    expectNoDifference(magicCode.presentation, nil)
    expectNoDifference(apple.id.rawValue, "apple")
    expectNoDifference(apple.kind, .idToken)
    expectNoDifference(apple.clientName, "apple-ios")
    expectNoDifference(apple.presentation, .native)
    expectNoDifference(google.id.rawValue, "google")
    expectNoDifference(google.kind, .idToken)
    expectNoDifference(google.clientName, "google-ios")
    expectNoDifference(google.presentation, .native)
    expectNoDifference(github.id.rawValue, "github")
    expectNoDifference(github.kind, .authorizationCode)
    expectNoDifference(github.clientName, "github-web")
    expectNoDifference(github.presentation, .externalBrowser)
    expectNoDifference(enterprise.id.rawValue, "enterprise-oidc")
    expectNoDifference(enterprise.kind, .authorizationCode)
    expectNoDifference(enterprise.clientName, "enterprise-oidc")
    expectNoDifference(enterprise.presentation, .externalBrowser)
    expectNoDifference(
      sourceReferences,
      [
        "upstream/instant/client/packages/core/src/authAPI.ts:8-27,122-184",
        "upstream/instant/client/packages/cli/__tests__/authClientAddApple.test.ts:213-228",
        "upstream/instant/client/packages/cli/__tests__/authClientAddGoogle.test.ts:352-371",
        "upstream/instant/client/packages/cli/__tests__/authClientAddGithub.test.ts:187-205",
        "screens/v3/auth-login.md:216-264",
      ]
    )
  }

  @Test
  func providerCredentialsRoundTripCanonicalTypedPayloads() throws {
    let credentials = [
      InstantAuthProviderCredential(
        providerID: InstantAuthProviderID(rawValue: "apple"),
        payload: .idToken(value: "signed-token", nonce: "nonce")
      ),
      InstantAuthProviderCredential(
        providerID: InstantAuthProviderID(rawValue: "github"),
        payload: .authorizationCode(value: "oauth-code", codeVerifier: "verifier")
      ),
    ]
    let data = try JSONEncoder().encode(credentials)
    expectNoDifference(
      try JSONDecoder().decode([InstantAuthProviderCredential].self, from: data),
      credentials
    )
  }
}

private struct AuthProviderSignupFixture: Sendable {}
