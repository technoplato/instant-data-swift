import AuthV3App
import Dependencies
import Foundation
import InstantSwiftData

public struct InstantAuthV3AppLiveValidationDetails: Codable, Equatable, Sendable {
  public var userNamespace: String
  public var providerIDs: [String]
  public var signedInStatus: String
  public var relaunchedStatus: String
  public var signedOutStatus: String
  public var auth: InstantAuthLiveValidationDetails

  public init(
    userNamespace: String,
    providerIDs: [String],
    signedInStatus: String,
    relaunchedStatus: String,
    signedOutStatus: String,
    auth: InstantAuthLiveValidationDetails
  ) {
    self.userNamespace = userNamespace
    self.providerIDs = providerIDs
    self.signedInStatus = signedInStatus
    self.relaunchedStatus = relaunchedStatus
    self.signedOutStatus = signedOutStatus
    self.auth = auth
  }
}

#if canImport(SwiftUI)
  @MainActor
  public enum InstantAuthV3AppLiveValidation {
    public static func run(
      appID: String,
      apiURI: URL,
      refreshToken: String,
      expectedUserID: String,
      persistenceURL: URL? = nil
    ) async throws -> ValidationEvidenceRow<InstantAuthV3AppLiveValidationDetails> {
      let persistenceURL = persistenceURL ?? FileManager.default.temporaryDirectory
        .appendingPathComponent("instant-auth-v3-app-live-\(UUID().uuidString).sqlite")
      let now = InstantTimestamp(
        milliseconds: Int64((Date().timeIntervalSince1970 * 1_000).rounded())
      )

      let initialClient = try await client(
        appID: appID,
        apiURI: apiURI,
        persistenceURL: persistenceURL
      )
      let initialState = InstantAuthState<AuthV3User>(providers: AuthV3Providers.all)
      initialState.startObservationIfNeeded(using: initialClient)
      defer { initialState.stopObservation() }

      let signedIn = try await initialClient.signInWithRefreshToken(
        refreshToken,
        userID: "untrusted-auth-v3-user"
      )
      guard signedIn.userID == expectedUserID,
        signedIn.refreshToken == refreshToken,
        !signedIn.isGuest
      else {
        throw failure(
          operation: "validate Auth V3 server sign-in",
          message: "The server-verified session did not match the canonical user."
        )
      }
      try await waitForSession(signedIn, in: initialState, operation: "observe Auth V3 sign-in")
      let signedInStatus = try statusName(initialState.status, expected: signedIn)

      let relaunchedClient = try await client(
        appID: appID,
        apiURI: apiURI,
        persistenceURL: persistenceURL
      )
      let relaunchedState = InstantAuthState<AuthV3User>(providers: AuthV3Providers.all)
      relaunchedState.startObservationIfNeeded(using: relaunchedClient)
      defer { relaunchedState.stopObservation() }
      try await waitForSession(
        signedIn,
        in: relaunchedState,
        operation: "restore Auth V3 session after relaunch"
      )
      let relaunchedStatus = try statusName(relaunchedState.status, expected: signedIn)

      try await relaunchedClient.signOut()
      try await waitForSignedOut(
        relaunchedState,
        operation: "observe Auth V3 sign-out"
      )
      guard try await relaunchedClient.authSession() == nil else {
        throw failure(
          operation: "validate Auth V3 local sign-out",
          message: "The local app session remained after sign-out."
        )
      }

      let rejectionCode: String
      do {
        _ = try await InstantRefreshTokenVerifier.live.verify(
          InstantRefreshTokenVerificationRequest(
            appID: appID,
            apiURI: apiURI,
            refreshToken: refreshToken,
            signedInAt: now,
            makeID: { "unused-auth-v3-id" }
          )
        )
        throw failure(
          operation: "validate Auth V3 remote sign-out",
          message: "The refresh token still verified after sign-out."
        )
      } catch let error as InstantError where error.code == .authFailed {
        rejectionCode = error.code.rawValue
      }

      let auth = InstantAuthLiveValidationDetails(
        userID: expectedUserID,
        serverVerifiedSignIn: true,
        durableRelaunch: true,
        localSessionCleared: true,
        invalidatedTokenRejected: true,
        rejectionCode: rejectionCode
      )
      return ValidationEvidenceRow(
        caseID: "validation.live.auth-v3-app",
        side: "swift",
        event: "app-owned-auth-lifecycle-observed",
        appID: appID,
        entityID: expectedUserID,
        timestampMs: now.milliseconds,
        ok: true,
        details: InstantAuthV3AppLiveValidationDetails(
          userNamespace: AuthV3User.instantNamespace,
          providerIDs: AuthV3Providers.all.map(\.id.rawValue),
          signedInStatus: signedInStatus,
          relaunchedStatus: relaunchedStatus,
          signedOutStatus: "signedOut",
          auth: auth
        )
      )
    }

    private static func client(
      appID: String,
      apiURI: URL,
      persistenceURL: URL
    ) async throws -> InstantSwiftDataClient {
      try await withDependencies {
        $0.context = .live
        try await $0.bootstrapInstantSwiftData(
          appID: appID,
          apiURI: apiURI,
          persistenceURL: persistenceURL,
          context: .live,
          initialAttributes: AuthV3User.instantAttributes
        )
      } operation: {
        @Dependency(\.defaultInstantSwiftData) var client
        return client
      }
    }

    private static func waitForSession(
      _ session: InstantAuthSession,
      in state: InstantAuthState<AuthV3User>,
      operation: String
    ) async throws {
      let deadline = ContinuousClock.now + .seconds(10)
      while ContinuousClock.now < deadline {
        if state.session == session, state.user?.id.rawValue == session.userID { return }
        try await Task.sleep(for: .milliseconds(25))
      }
      throw failure(operation: operation, message: "The app auth state did not observe the session.")
    }

    private static func waitForSignedOut(
      _ state: InstantAuthState<AuthV3User>,
      operation: String
    ) async throws {
      let deadline = ContinuousClock.now + .seconds(10)
      while ContinuousClock.now < deadline {
        if state.session == nil, state.status == .signedOut { return }
        try await Task.sleep(for: .milliseconds(25))
      }
      throw failure(operation: operation, message: "The app auth state did not observe sign-out.")
    }

    private static func statusName(
      _ status: InstantAuthStatus,
      expected session: InstantAuthSession
    ) throws -> String {
      guard status == .signedIn(session) else {
        throw failure(
          operation: "validate Auth V3 app status",
          message: "Expected the app-owned status to be signed in."
        )
      }
      return "signedIn"
    }

    private static func failure(operation: String, message: String) -> InstantError {
      InstantError(
        code: .validationFailed,
        operation: operation,
        message: message,
        recovery: "Keep Auth V3 bound to the canonical app-scoped auth session lifecycle."
      )
    }
  }
#endif
