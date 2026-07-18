import Foundation
import InstantSwiftDataCore

public struct InstantAuthLiveValidationDetails: Codable, Equatable, Sendable {
  public var userID: String
  public var serverVerifiedSignIn: Bool
  public var durableRelaunch: Bool
  public var localSessionCleared: Bool
  public var invalidatedTokenRejected: Bool
  public var rejectionCode: String

  public init(
    userID: String,
    serverVerifiedSignIn: Bool,
    durableRelaunch: Bool,
    localSessionCleared: Bool,
    invalidatedTokenRejected: Bool,
    rejectionCode: String
  ) {
    self.userID = userID
    self.serverVerifiedSignIn = serverVerifiedSignIn
    self.durableRelaunch = durableRelaunch
    self.localSessionCleared = localSessionCleared
    self.invalidatedTokenRejected = invalidatedTokenRejected
    self.rejectionCode = rejectionCode
  }
}

public enum InstantAuthLiveValidation {
  public static func run(
    appID: String,
    apiURI: URL,
    refreshToken: String,
    expectedUserID: String,
    persistenceURL: URL? = nil
  ) async throws -> ValidationEvidenceRow<InstantAuthLiveValidationDetails> {
    let persistenceURL = persistenceURL ?? FileManager.default.temporaryDirectory
      .appendingPathComponent("instant-auth-live-\(UUID().uuidString).sqlite")
    let now = InstantTimestamp(milliseconds: Int64((Date().timeIntervalSince1970 * 1000).rounded()))
    let verifier = InstantRefreshTokenVerifier.live(apiURI: apiURI)
    let invalidator = InstantAuthTokenInvalidator.live(apiURI: apiURI)
    func configuration() -> InstantRuntimeConfiguration {
      InstantRuntimeConfiguration(
        appID: appID,
        apiURI: apiURI,
        persistenceURL: persistenceURL,
        refreshTokenVerifier: verifier,
        authTokenInvalidator: invalidator
      )
    }

    let runtime = try await InstantRuntime.bootstrap(configuration: configuration())
    let signedIn = try await runtime.signInWithRefreshToken(
      refreshToken,
      userID: "untrusted-swift-user-id"
    )
    guard signedIn.userID == expectedUserID,
      signedIn.refreshToken == refreshToken,
      !signedIn.isGuest
    else {
      throw InstantError(
        code: .validationFailed,
        operation: "validate live refresh-token sign-in",
        message: "The server-verified auth session did not match the canonical user.",
        recovery: "Decode the verify_refresh_token user and ignore caller-supplied identity."
      )
    }

    let relaunched = try await InstantRuntime.bootstrap(configuration: configuration())
    let persisted = try await relaunched.authSession()
    guard persisted == signedIn else {
      throw InstantError(
        code: .validationFailed,
        operation: "validate live auth relaunch",
        message: "The verified auth session did not survive relaunch.",
        recovery: "Persist the verified refresh-token session by app ID."
      )
    }

    try await relaunched.signOut()
    let signedOut = try await relaunched.authSession()
    guard signedOut == nil else {
      throw InstantError(
        code: .validationFailed,
        operation: "validate live auth sign-out",
        message: "The local auth session remained after sign-out.",
        recovery: "Clear local auth state before invalidating the remote token."
      )
    }

    let afterSignOut = try await InstantRuntime.bootstrap(configuration: configuration())
    guard try await afterSignOut.authSession() == nil else {
      throw InstantError(
        code: .validationFailed,
        operation: "validate durable live auth sign-out",
        message: "The signed-out session returned after relaunch.",
        recovery: "Persist removal of the app-scoped auth session."
      )
    }

    let rejectionCode: String
    do {
      _ = try await verifier.verify(
        InstantRefreshTokenVerificationRequest(
          appID: appID,
          refreshToken: refreshToken,
          signedInAt: now,
          makeID: { "unused-live-auth-id" }
        )
      )
      throw InstantError(
        code: .validationFailed,
        operation: "validate remote refresh-token invalidation",
        message: "The refresh token still verified after sign-out.",
        recovery: "POST the canonical app_id and refresh_token body to /runtime/signout."
      )
    } catch let error as InstantError where error.code == .authFailed {
      rejectionCode = error.code.rawValue
    }

    return ValidationEvidenceRow(
      caseID: "validation.live.auth-invalidation",
      side: "swift",
      event: "refresh-token-invalidated",
      appID: appID,
      entityID: expectedUserID,
      timestampMs: now.milliseconds,
      ok: true,
      details: InstantAuthLiveValidationDetails(
        userID: expectedUserID,
        serverVerifiedSignIn: true,
        durableRelaunch: true,
        localSessionCleared: true,
        invalidatedTokenRejected: true,
        rejectionCode: rejectionCode
      )
    )
  }
}
