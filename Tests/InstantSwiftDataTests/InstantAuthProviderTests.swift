import CustomDump
import Foundation
import Testing

@testable import InstantSwiftData

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
    let redirectURL = URL(string: "auth-v3://oauth-callback")!
    let magicCode = AuthProvider.magicCode(
      email: .instant,
      extraFields: AuthProviderSignupFixture.self
    )
    let apple = AuthProvider.apple(clientName: "apple-ios", presentation: .native)
    let google = AuthProvider.google(clientName: "google-ios", presentation: .native)
    let browserApple = AuthProvider.apple(
      clientName: "apple-web",
      presentation: .externalBrowser,
      redirectURL: redirectURL
    )
    let browserGoogle = AuthProvider.google(
      clientName: "google-web",
      presentation: .externalBrowser,
      redirectURL: redirectURL
    )
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
    expectNoDifference(browserApple.kind, .authorizationCode)
    expectNoDifference(browserApple.clientName, "apple-web")
    expectNoDifference(browserApple.redirectURL, redirectURL)
    expectNoDifference(browserGoogle.kind, .authorizationCode)
    expectNoDifference(browserGoogle.clientName, "google-web")
    expectNoDifference(browserGoogle.redirectURL, redirectURL)
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

  @Test
  func browserPKCEMatchesRFC7636AndAppendsCanonicalChallenge() throws {
    let pkce = try InstantOAuthPKCE(
      verifier: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"
    )
    expectNoDifference(
      pkce.challenge,
      "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM"
    )

    let baseURL = try #require(
      URL(string: "https://api.instantdb.com/runtime/oauth/start?app_id=app-1")
    )
    let authorizationURL = try pkce.appendingChallenge(to: baseURL)
    let components = try #require(
      URLComponents(url: authorizationURL, resolvingAgainstBaseURL: false)
    )
    expectNoDifference(
      components.queryItems,
      [
        URLQueryItem(name: "app_id", value: "app-1"),
        URLQueryItem(name: "code_challenge", value: pkce.challenge),
        URLQueryItem(name: "code_challenge_method", value: "S256"),
      ]
    )
  }

  @Test
  func githubFactoryCarriesItsAppOwnedRedirectURL() throws {
    let redirectURL = try #require(URL(string: "sample-auth://oauth-callback"))

    let provider = AuthProvider.github(
      clientName: "github-web",
      presentation: .externalBrowser,
      redirectURL: redirectURL
    )

    expectNoDifference(provider.redirectURL, redirectURL)
  }

  @Test
  func staleAttemptCannotFinishTheReplacementAttempt() throws {
    var attempts = InstantAuthAttemptTracker()
    let first = try attempts.begin()

    let firstDidFinish = attempts.finish(first)
    #expect(firstDidFinish)
    let replacement = try attempts.begin()

    let staleDidFinish = attempts.finish(first)
    #expect(!staleDidFinish)
    #expect(attempts.matches(replacement))
  }

  @Test
  func oauthCallbackValidatesStateBeforeTrustingProviderError() throws {
    let redirectURL = try #require(URL(string: "sample-auth://oauth-callback"))
    let callbackURL = try #require(
      URL(
        string:
          "sample-auth://oauth-callback?state=attacker-state&error=access_denied&error_description=Injected"
      )
    )

    do {
      _ = try InstantOAuthCallbackValidator.validate(
        callbackURL,
        redirectURL: redirectURL,
        expectedState: "expected-state"
      )
      Issue.record("Expected the callback state mismatch to fail.")
    } catch let error as InstantError {
      #expect(error.message.contains("state did not match"))
      #expect(!error.message.contains("Injected"))
    }
  }

  @Test(
    arguments: [
      "state=expected&state=expected&code=code",
      "state=expected&code=first&code=second",
      "state=expected&error=first&error=second",
    ]
  )
  func oauthCallbackRejectsDuplicateSecurityFields(query: String) throws {
    let redirectURL = try #require(URL(string: "sample-auth://oauth-callback"))
    let callbackURL = try #require(URL(string: "sample-auth://oauth-callback?\(query)"))

    do {
      _ = try InstantOAuthCallbackValidator.validate(
        callbackURL,
        redirectURL: redirectURL,
        expectedState: "expected"
      )
      Issue.record("Expected duplicate OAuth response fields to fail.")
    } catch let error as InstantError {
      #expect(error.message.contains("duplicate"))
    }
  }

  @Test
  func oauthCallbackAcceptsOneMatchingStateAndOneCode() throws {
    let redirectURL = try #require(URL(string: "sample-auth://oauth-callback"))
    let callbackURL = try #require(
      URL(string: "sample-auth://oauth-callback?state=expected&code=authorization-code")
    )

    expectNoDifference(
      try InstantOAuthCallbackValidator.validate(
        callbackURL,
        redirectURL: redirectURL,
        expectedState: "expected"
      ),
      .authorizationCode("authorization-code")
    )
  }
}

private struct AuthProviderSignupFixture: Sendable {}
