import CustomDump
import Foundation
import InstantSwiftData
import Testing

@Suite
struct InstantAuthProviderTests {
  @Test
  func providerFactoriesPreserveCanonicalIDsClientsAndPresentation() {
    let apple = AuthProvider.apple(clientName: "apple-ios", presentation: .native)
    let github = AuthProvider.github(
      clientName: "github-web",
      presentation: .externalBrowser
    )
    let enterprise = AuthProvider.authorizationCode(
      id: "enterprise-oidc",
      clientName: "enterprise-oidc"
    )

    expectNoDifference(apple.id.rawValue, "apple")
    expectNoDifference(apple.kind, .idToken)
    expectNoDifference(apple.clientName, "apple-ios")
    expectNoDifference(apple.presentation, .native)
    expectNoDifference(github.id.rawValue, "github")
    expectNoDifference(github.kind, .authorizationCode)
    expectNoDifference(github.clientName, "github-web")
    expectNoDifference(github.presentation, .externalBrowser)
    expectNoDifference(enterprise.id.rawValue, "enterprise-oidc")
    expectNoDifference(enterprise.clientName, "enterprise-oidc")
  }

  @Test
  func providerCredentialRoundTripsTypedPayload() throws {
    let credential = InstantAuthProviderCredential(
      providerID: InstantAuthProviderID(rawValue: "apple"),
      payload: .idToken(value: "signed-token", nonce: "nonce")
    )
    let data = try JSONEncoder().encode(credential)
    expectNoDifference(
      try JSONDecoder().decode(InstantAuthProviderCredential.self, from: data),
      credential
    )
  }
}
