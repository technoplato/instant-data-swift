import CustomDump
import Foundation
import InstantSwiftDataCore
import Testing

/// Instant's TypeScript client sends the session's refresh token to `verify_magic_code` only while
/// the session is a guest (`Reactor.signInWithMagicCode`: `isGuest ? refresh_token : undefined`).
/// The server uses that token to upgrade the guest in place or link it to the email's user.
///
/// Measured on 2026-09-28 against Scribe's Instant app (#113): with a non-guest session whose
/// refresh token had been revoked, Swift forwarded the token and `verify_magic_code` failed with
/// `record-not-found` (HTTP 400); the TypeScript client, in the same state, signed in.
@Suite(.serialized)
struct InstantMagicCodeGuestTokenTests {
  @Test("magic-code sign-in forwards a guest session's refresh token so Instant can link the guest")
  func guestSessionTokenIsForwarded() async throws {
    let recorder = MagicCodeVerifyRecorder()
    let (runtime, cacheURL) = try await bootstrap(recorder: recorder, suffix: "guest")
    defer { try? FileManager.default.removeItem(at: cacheURL) }

    _ = try await runtime.signInAsGuest()
    _ = try await runtime.sendMagicCode(email: "person@example.com")
    _ = try await runtime.signInWithMagicCode(email: "person@example.com", code: "123456")

    let forwarded = await recorder.refreshTokens
    expectNoDifference(forwarded, ["guest-refresh-token"])
  }

  @Test("magic-code sign-in does not forward a non-guest session's refresh token")
  func nonGuestSessionTokenIsNotForwarded() async throws {
    let recorder = MagicCodeVerifyRecorder()
    let (runtime, cacheURL) = try await bootstrap(recorder: recorder, suffix: "user")
    defer { try? FileManager.default.removeItem(at: cacheURL) }

    let session = try await runtime.signInWithRefreshToken("revoked-user-token")
    #expect(session.isGuest == false)
    _ = try await runtime.sendMagicCode(email: "person@example.com")
    _ = try await runtime.signInWithMagicCode(email: "person@example.com", code: "123456")

    let forwarded = await recorder.refreshTokens
    expectNoDifference(forwarded, [nil])
  }

  @Test("an auth HTTP failure keeps Instant's error type and message, never the hint")
  func authFailureKeepsInstantErrorTypeAndMessage() async throws {
    let exchange = InstantMagicCodeExchange.live(
      httpClient: InstantAuthHTTPClient { _ in
        InstantAuthHTTPResponse(
          statusCode: 400,
          data: Data(
            #"{"type":"record-not-found","message":"Record not found: app-user","hint":{"args":[{"refresh-token":"secret-token"}],"record-type":"app-user"}}"#
              .utf8
          )
        )
      }
    )
    let now = InstantTimestamp(milliseconds: 1_700_000_000_000)
    do {
      _ = try await exchange.verify(
        InstantMagicCodeVerifyRequest(
          appID: "app-1",
          email: "person@example.com",
          code: "123456",
          challenge: InstantMagicCodeChallenge(
            appID: "app-1",
            email: "person@example.com",
            code: "",
            createdAt: now,
            expiresAt: InstantTimestamp(milliseconds: now.milliseconds + 600_000)
          ),
          refreshToken: "secret-token",
          verifiedAt: now
        )
      )
      Issue.record("Expected verify_magic_code to fail.")
    } catch let error as InstantError {
      expectNoDifference(error.code, .authFailed)
      expectNoDifference(error.operation, "sign in with magic code")
      #expect(error.message.contains("HTTP 400"))
      #expect(error.message.contains("record-not-found"))
      #expect(error.message.contains("Record not found: app-user"))
      #expect(!error.message.contains("secret-token"))
      #expect(!error.recovery.contains("secret-token"))
    }
  }
}

private actor MagicCodeVerifyRecorder {
  private(set) var refreshTokens: [String?] = []

  func record(_ refreshToken: String?) {
    refreshTokens.append(refreshToken)
  }
}

private func bootstrap(
  recorder: MagicCodeVerifyRecorder,
  suffix: String
) async throws -> (InstantRuntime, URL) {
  let cacheURL = FileManager.default.temporaryDirectory
    .appendingPathComponent("instant-magic-code-guest-token-\(suffix)-\(UUID().uuidString).sqlite")
  let runtime = try await InstantRuntime.bootstrap(
    configuration: InstantRuntimeConfiguration(
      appID: "magic-code-guest-token-\(suffix)",
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
      magicCodeExchange: InstantMagicCodeExchange(
        send: { request in
          InstantMagicCodeChallenge(
            appID: request.appID,
            email: request.email,
            code: "123456",
            createdAt: request.sentAt,
            expiresAt: InstantTimestamp(milliseconds: request.sentAt.milliseconds + 600_000)
          )
        },
        verify: { request in
          await recorder.record(request.refreshToken)
          return InstantMagicCodeVerification(
            userID: request.refreshToken == "guest-refresh-token" ? "guest-1" : "user-1",
            refreshToken: "new-refresh-token",
            created: false,
            email: request.email,
            type: .user
          )
        }
      )
    )
  )
  return (runtime, cacheURL)
}
