import CustomDump
import Foundation
import InstantSwiftData
import Testing

@Suite(.serialized)
struct InstantGuestPromotionTests {
  @Test
  func idTokenPromotionUpgradesNewIdentityInPlaceAndForwardsGuestToken() async throws {
    let cacheURL = temporaryGuestPromotionCacheURL("id-token")
    defer { try? FileManager.default.removeItem(at: cacheURL) }
    let requests = GuestPromotionIDTokenRecorder()
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "guest-promotion-id-token",
        persistenceURL: cacheURL,
        makeID: { "guest-user" },
        guestAuthenticator: InstantGuestAuthenticator { request in
          InstantGuestAuthVerification(
            userID: "guest-user",
            refreshToken: "guest-refresh-token"
          )
        },
        idTokenExchange: InstantIDTokenExchange { request in
          await requests.record(request)
          return InstantIDTokenVerification(
            userID: "guest-user",
            refreshToken: "promoted-refresh-token",
            email: "person@example.com",
            type: .user
          )
        }
      )
    )
    let client = InstantSwiftDataClient(runtime: runtime)
    _ = try await client.signInAsGuest()

    let result = try await client.promoteGuestWithIDToken(
      clientName: "apple",
      idToken: "apple-id-token",
      nonce: "nonce"
    )

    expectNoDifference(result.guestUserID, "guest-user")
    expectNoDifference(result.session.userID, "guest-user")
    expectNoDifference(result.disposition, .upgradedInPlace)
    expectNoDifference(result.requiresLinkedGuestAccess, false)
    let request = try #require(await requests.onlyRequest())
    expectNoDifference(request.refreshToken, "guest-refresh-token")
  }

  @Test
  func authorizationCodePromotionReportsCanonicalLinkedGuestConflict() async throws {
    let cacheURL = temporaryGuestPromotionCacheURL("oauth")
    defer { try? FileManager.default.removeItem(at: cacheURL) }
    let requests = GuestPromotionOAuthRecorder()
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "guest-promotion-oauth",
        persistenceURL: cacheURL,
        makeID: { "guest-user" },
        guestAuthenticator: InstantGuestAuthenticator { _ in
          InstantGuestAuthVerification(
            userID: "guest-user",
            refreshToken: "guest-refresh-token"
          )
        },
        oauthExchange: InstantOAuthExchange { request in
          await requests.record(request)
          return InstantOAuthVerification(
            userID: "existing-primary-user",
            refreshToken: "primary-refresh-token",
            email: "existing@example.com",
            type: .user,
            guestPromotionLinkEvidence: .instantServerAcceptedGuestToken
          )
        }
      )
    )
    let client = InstantSwiftDataClient(runtime: runtime)
    _ = try await client.signInAsGuest()

    let result = try await client.promoteGuestWithOAuth(
      code: "authorization-code",
      codeVerifier: "pkce-verifier"
    )

    expectNoDifference(result.guestUserID, "guest-user")
    expectNoDifference(result.session.userID, "existing-primary-user")
    expectNoDifference(result.disposition, .linkedToExistingUser)
    expectNoDifference(result.requiresLinkedGuestAccess, true)
    let request = try #require(await requests.onlyRequest())
    expectNoDifference(request.refreshToken, "guest-refresh-token")
  }

  @Test
  func customExchangeDoesNotClaimAnUnverifiedGuestLink() async throws {
    let cacheURL = temporaryGuestPromotionCacheURL("unverified-link")
    defer { try? FileManager.default.removeItem(at: cacheURL) }
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "guest-promotion-unverified-link",
        persistenceURL: cacheURL,
        makeID: { "guest-user" },
        guestAuthenticator: InstantGuestAuthenticator { _ in
          InstantGuestAuthVerification(
            userID: "guest-user",
            refreshToken: "guest-refresh-token"
          )
        },
        oauthExchange: InstantOAuthExchange { _ in
          InstantOAuthVerification(
            userID: "different-user",
            refreshToken: "different-refresh-token",
            type: .user
          )
        }
      )
    )
    let client = InstantSwiftDataClient(runtime: runtime)
    _ = try await client.signInAsGuest()

    let result = try await client.promoteGuestWithOAuth(code: "authorization-code")

    expectNoDifference(result.disposition, .identityChangedWithoutVerifiedLink)
    expectNoDifference(result.requiresLinkedGuestAccess, nil)
  }

  @Test
  func cancellationAfterSuccessfulExchangeCommitsWhenGuestSessionStillMatches() async throws {
    let cacheURL = temporaryGuestPromotionCacheURL("cancel-after-success")
    defer { try? FileManager.default.removeItem(at: cacheURL) }
    let gate = GuestPromotionExchangeGate()
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "guest-promotion-cancel-after-success",
        persistenceURL: cacheURL,
        makeID: { "guest-user" },
        guestAuthenticator: InstantGuestAuthenticator { _ in
          InstantGuestAuthVerification(
            userID: "guest-user",
            refreshToken: "guest-refresh-token"
          )
        },
        oauthExchange: InstantOAuthExchange { _ in
          await gate.serverAccepted()
          await gate.waitForRelease()
          return InstantOAuthVerification(
            userID: "promoted-user",
            refreshToken: "promoted-refresh-token",
            type: .user,
            guestPromotionLinkEvidence: .instantServerAcceptedGuestToken
          )
        }
      )
    )
    let client = InstantSwiftDataClient(runtime: runtime)
    _ = try await client.signInAsGuest()

    let promotion = Task {
      try await client.promoteGuestWithOAuth(code: "authorization-code")
    }
    await gate.waitUntilServerAccepted()
    promotion.cancel()
    await gate.release()

    let result = try await promotion.value
    expectNoDifference(result.session.userID, "promoted-user")
    expectNoDifference(result.disposition, .linkedToExistingUser)
    let currentSession = try await client.authSession()
    expectNoDifference(currentSession, result.session)
  }

  @Test
  func promotionRefusesToOverwriteAuthChangedDuringExchange() async throws {
    let cacheURL = temporaryGuestPromotionCacheURL("compare-and-swap")
    defer { try? FileManager.default.removeItem(at: cacheURL) }
    let gate = GuestPromotionExchangeGate()
    let requests = GuestPromotionOAuthRecorder()
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "guest-promotion-compare-and-swap",
        persistenceURL: cacheURL,
        makeID: { "guest-user" },
        guestAuthenticator: InstantGuestAuthenticator { _ in
          InstantGuestAuthVerification(
            userID: "guest-user",
            refreshToken: "guest-refresh-token"
          )
        },
        oauthExchange: InstantOAuthExchange { request in
          await requests.record(request)
          await gate.serverAccepted()
          await gate.waitForRelease()
          return InstantOAuthVerification(
            userID: "promoted-user",
            refreshToken: "promoted-refresh-token",
            type: .user,
            guestPromotionLinkEvidence: .instantServerAcceptedGuestToken
          )
        }
      )
    )
    let client = InstantSwiftDataClient(runtime: runtime)
    _ = try await client.signInAsGuest()

    let promotion = Task {
      try await client.promoteGuestWithOAuth(code: "authorization-code")
    }
    await gate.waitUntilServerAccepted()
    try await client.signOut(invalidateToken: false)
    promotion.cancel()
    await gate.release()

    do {
      _ = try await promotion.value
      Issue.record("Expected promotion to reject the changed local auth session.")
    } catch let error as InstantError {
      expectNoDifference(error.code, .authFailed)
      #expect(error.message.contains("Provider exchange succeeded"))
      #expect(error.message.contains("local auth session changed"))
      #expect(error.recovery.contains("credential may already be consumed"))
    }
    let currentSession = try await client.authSession()
    expectNoDifference(currentSession, nil)
    let request = try #require(await requests.onlyRequest())
    expectNoDifference(request.refreshToken, "guest-refresh-token")
  }

  @Test
  func promotionFailsBeforeExchangeWithoutGuestSession() async throws {
    let cacheURL = temporaryGuestPromotionCacheURL("signed-out")
    defer { try? FileManager.default.removeItem(at: cacheURL) }
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "guest-promotion-signed-out",
        persistenceURL: cacheURL
      )
    )
    let client = InstantSwiftDataClient(runtime: runtime)

    do {
      _ = try await client.promoteGuestWithOAuth(code: "code")
      Issue.record("Expected guest promotion to require a guest session.")
    } catch let error as InstantError {
      expectNoDifference(error.code, .authFailed)
      expectNoDifference(error.operation, "promote guest account")
      #expect(error.message.contains("guest session"))
    }
  }
}

private actor GuestPromotionIDTokenRecorder {
  private var requests: [InstantIDTokenSignInRequest] = []

  func record(_ request: InstantIDTokenSignInRequest) {
    requests.append(request)
  }

  func onlyRequest() -> InstantIDTokenSignInRequest? {
    requests.count == 1 ? requests[0] : nil
  }
}

private actor GuestPromotionOAuthRecorder {
  private var requests: [InstantOAuthSignInRequest] = []

  func record(_ request: InstantOAuthSignInRequest) {
    requests.append(request)
  }

  func onlyRequest() -> InstantOAuthSignInRequest? {
    requests.count == 1 ? requests[0] : nil
  }
}

private actor GuestPromotionExchangeGate {
  private var didAccept = false
  private var isReleased = false
  private var acceptanceWaiters: [CheckedContinuation<Void, Never>] = []
  private var releaseWaiters: [CheckedContinuation<Void, Never>] = []

  func serverAccepted() {
    didAccept = true
    let waiters = acceptanceWaiters
    acceptanceWaiters.removeAll()
    for waiter in waiters { waiter.resume() }
  }

  func waitUntilServerAccepted() async {
    guard !didAccept else { return }
    await withCheckedContinuation { acceptanceWaiters.append($0) }
  }

  func waitForRelease() async {
    guard !isReleased else { return }
    await withCheckedContinuation { releaseWaiters.append($0) }
  }

  func release() {
    isReleased = true
    let waiters = releaseWaiters
    releaseWaiters.removeAll()
    for waiter in waiters { waiter.resume() }
  }
}

private func temporaryGuestPromotionCacheURL(_ suffix: String) -> URL {
  FileManager.default.temporaryDirectory
    .appendingPathComponent("instant-guest-promotion-\(suffix)-\(UUID().uuidString).sqlite")
}
