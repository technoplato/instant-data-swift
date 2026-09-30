import CustomDump
import Foundation
import InstantSwiftDataCore
import Testing

/// What an Instant auth refusal tells the user to do next.
///
/// Measured on 2026-09-29 (#113): Scribe's Google sign-in reached Google, came back with a code,
/// and the code exchange (`POST /runtime/oauth/token`) returned HTTP 400 `validation-failed`,
/// "Validation failed for shared-credentials: Shared dev credentials are limited to 100 users.
/// Please add your own client_id and client_secret in the dashboard." The app then showed
/// "fix: Verify the app ID and authentication credentials, then try again." The app ID was fine.
/// Instant refuses shared development credentials for new users once an app has 100 users
/// (upstream `instant.model.shared-oauth-client/assert-shared-credentials-allowed!`).
@Suite
struct InstantAuthFailureRecoveryTests {
  @Test("a shared-credentials refusal names the OAuth client's own credentials as the fix")
  func sharedCredentialsRefusalNamesTheClientsOwnCredentials() async throws {
    let error = try await oauthExchangeFailure(
      statusCode: 400,
      body: #"""
        {"type":"validation-failed","message":"Validation failed for shared-credentials: Shared dev credentials are limited to 100 users. Please add your own client_id and client_secret in the dashboard.","hint":{"data-type":"shared-credentials","input":"e7c49961-d702-46a1-82c1-fca9a61f6a4d","errors":[{"message":"Shared dev credentials are limited to 100 users. Please add your own client_id and client_secret in the dashboard."}]}}
        """#
    )

    expectNoDifference(error.code, .authFailed)
    expectNoDifference(error.operation, "sign in with oauth")
    expectNoDifference(
      error.message,
      "Instant auth returned HTTP 400 (validation-failed): Validation failed for shared-credentials: Shared dev credentials are limited to 100 users. Please add your own client_id and client_secret in the dashboard."
    )
    expectNoDifference(
      error.recovery,
      "This app's OAuth client uses Instant's shared development credentials, which Instant refuses for new users once the app has 100 users. Give that client its own client ID and client secret in the Instant dashboard or with `instant-cli auth client update`, then sign in again."
    )
  }

  @Test("other auth refusals point at Instant's reason, not at the app ID")
  func otherRefusalsPointAtInstantsReason() async throws {
    let error = try await oauthExchangeFailure(
      statusCode: 400,
      body: #"""
        {"type":"record-not-found","message":"Record not found: app-oauth-code","hint":{"record-type":"app-oauth-code","args":[{"code":"secret-code"}]}}
        """#
    )

    expectNoDifference(
      error.message,
      "Instant auth returned HTTP 400 (record-not-found): Record not found: app-oauth-code"
    )
    expectNoDifference(
      error.recovery,
      "Instant refused this request for the reason in the message above. Correct what it names, then try again."
    )
    #expect(!error.recovery.contains("secret-code"))
  }

  @Test("a hint that is not an object still keeps Instant's type and message")
  func unexpectedHintShapeKeepsTypeAndMessage() async throws {
    let error = try await oauthExchangeFailure(
      statusCode: 400,
      body: #"{"type":"param-missing","message":"Missing input: code","hint":"code"}"#
    )

    expectNoDifference(
      error.message,
      "Instant auth returned HTTP 400 (param-missing): Missing input: code"
    )
  }
}

private func oauthExchangeFailure(statusCode: Int, body: String) async throws -> InstantError {
  let exchange = InstantOAuthExchange.live(
    httpClient: InstantAuthHTTPClient { _ in
      InstantAuthHTTPResponse(statusCode: statusCode, data: Data(body.utf8))
    }
  )
  do {
    _ = try await exchange.signIn(
      InstantOAuthSignInRequest(
        appID: "e7c49961-d702-46a1-82c1-fca9a61f6a4d",
        code: "authorization-code",
        codeVerifier: "verifier",
        refreshToken: "guest-refresh-token",
        signedInAt: InstantTimestamp(milliseconds: 1_790_717_163_000),
        makeID: { "id-1" }
      )
    )
  } catch let error as InstantError {
    return error
  }
  Issue.record("Expected the OAuth code exchange to fail.")
  throw CancellationError()
}
