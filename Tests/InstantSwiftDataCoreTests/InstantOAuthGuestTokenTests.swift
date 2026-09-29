import CustomDump
import Foundation
import InstantSwiftDataCore
import Testing

/// Instant's TypeScript client sends the session's refresh token to the OAuth code exchange only
/// while the session is a guest (`Reactor.exchangeCodeForToken`, `Reactor.js` 2381-2394:
/// `refreshToken: isGuest ? currentUser?.user?.refresh_token : undefined`), the same rule it applies
/// to magic codes (`InstantMagicCodeGuestTokenTests`). The server uses a guest's token to upgrade
/// the guest in place or link it to the provider's existing user. Forwarding a non-guest token has
/// no upstream counterpart; on the magic-code path it made a revoked token fail sign-in (measured
/// 2026-09-28, #113).
///
/// The ID-token exchange is different upstream: `Reactor.signInWithIdToken` (`Reactor.js` 2408-2423)
/// sends any current refresh token, and Swift matches that.
@Suite(.serialized)
struct InstantOAuthGuestTokenTests {
  @Test("OAuth sign-in forwards a guest session's refresh token so Instant can link the guest")
  func guestSessionTokenIsForwardedToOAuth() async throws {
    let recorder = AuthExchangeRefreshTokenRecorder()
    let (runtime, cacheURL) = try await bootstrap(recorder: recorder, suffix: "oauth-guest")
    defer { try? FileManager.default.removeItem(at: cacheURL) }

    _ = try await runtime.signInAsGuest()
    _ = try await runtime.signInWithOAuth(code: "authorization-code", codeVerifier: "verifier")

    let forwarded = await recorder.oauthRefreshTokens
    expectNoDifference(forwarded, ["guest-refresh-token"])
  }

  @Test("OAuth sign-in does not forward a non-guest session's refresh token")
  func nonGuestSessionTokenIsNotForwardedToOAuth() async throws {
    let recorder = AuthExchangeRefreshTokenRecorder()
    let (runtime, cacheURL) = try await bootstrap(recorder: recorder, suffix: "oauth-user")
    defer { try? FileManager.default.removeItem(at: cacheURL) }

    let session = try await runtime.signInWithRefreshToken("user-refresh-token")
    #expect(session.isGuest == false)
    _ = try await runtime.signInWithOAuth(code: "authorization-code", codeVerifier: "verifier")

    let forwarded = await recorder.oauthRefreshTokens
    expectNoDifference(forwarded, [nil])
  }

  @Test("ID-token sign-in forwards a non-guest session's refresh token, as upstream does")
  func idTokenSignInForwardsNonGuestSessionToken() async throws {
    let recorder = AuthExchangeRefreshTokenRecorder()
    let (runtime, cacheURL) = try await bootstrap(recorder: recorder, suffix: "id-token-user")
    defer { try? FileManager.default.removeItem(at: cacheURL) }

    let session = try await runtime.signInWithRefreshToken("user-refresh-token")
    #expect(session.isGuest == false)
    _ = try await runtime.signInWithIDToken(clientName: "google-ios", idToken: "id-token")

    let forwarded = await recorder.idTokenRefreshTokens
    expectNoDifference(forwarded, ["user-refresh-token"])
  }
}

private actor AuthExchangeRefreshTokenRecorder {
  private(set) var oauthRefreshTokens: [String?] = []
  private(set) var idTokenRefreshTokens: [String?] = []

  func recordOAuth(_ refreshToken: String?) {
    oauthRefreshTokens.append(refreshToken)
  }

  func recordIDToken(_ refreshToken: String?) {
    idTokenRefreshTokens.append(refreshToken)
  }
}

private func bootstrap(
  recorder: AuthExchangeRefreshTokenRecorder,
  suffix: String
) async throws -> (InstantRuntime, URL) {
  let cacheURL = FileManager.default.temporaryDirectory
    .appendingPathComponent("instant-oauth-guest-token-\(suffix)-\(UUID().uuidString).sqlite")
  let runtime = try await InstantRuntime.bootstrap(
    configuration: InstantRuntimeConfiguration(
      appID: "oauth-guest-token-\(suffix)",
      persistenceURL: cacheURL,
      refreshTokenVerifier: InstantRefreshTokenVerifier { request in
        InstantRefreshTokenVerification(
          userID: "user-1",
          refreshToken: request.refreshToken,
          email: "person@example.com",
          type: .user
        )
      },
      guestAuthenticator: InstantGuestAuthenticator { _ in
        InstantGuestAuthVerification(userID: "guest-1", refreshToken: "guest-refresh-token")
      },
      idTokenExchange: InstantIDTokenExchange { request in
        await recorder.recordIDToken(request.refreshToken)
        return InstantIDTokenVerification(
          userID: "user-1",
          refreshToken: "id-token-refresh-token",
          email: "person@example.com",
          type: .user
        )
      },
      oauthExchange: InstantOAuthExchange { request in
        await recorder.recordOAuth(request.refreshToken)
        return InstantOAuthVerification(
          userID: request.refreshToken == "guest-refresh-token" ? "guest-1" : "user-1",
          refreshToken: "oauth-refresh-token",
          email: "person@example.com",
          type: .user
        )
      }
    )
  )
  return (runtime, cacheURL)
}
