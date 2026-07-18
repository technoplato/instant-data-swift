import Foundation

public struct InstantRefreshTokenVerificationRequest: Sendable {
  public var appID: String
  public var refreshToken: String
  public var userID: String?
  public var signedInAt: InstantTimestamp
  public var makeID: @Sendable () -> String

  public init(
    appID: String,
    refreshToken: String,
    userID: String? = nil,
    signedInAt: InstantTimestamp,
    makeID: @escaping @Sendable () -> String
  ) {
    self.appID = appID
    self.refreshToken = refreshToken
    self.userID = userID
    self.signedInAt = signedInAt
    self.makeID = makeID
  }
}

public struct InstantRefreshTokenVerification: Hashable, Codable, Sendable {
  public var userID: String
  public var refreshToken: String

  public init(userID: String, refreshToken: String) {
    self.userID = userID
    self.refreshToken = refreshToken
  }
}

public struct InstantRefreshTokenVerifier: Sendable {
  public var verify:
    @Sendable (InstantRefreshTokenVerificationRequest) async throws
      -> InstantRefreshTokenVerification

  public init(
    verify: @escaping @Sendable (InstantRefreshTokenVerificationRequest) async throws
      -> InstantRefreshTokenVerification
  ) {
    self.verify = verify
  }
}

extension InstantRefreshTokenVerifier {
  public static let local = Self(
    verify: { request in
      InstantRefreshTokenVerification(
        userID: request.userID ?? "token-\(request.makeID())",
        refreshToken: request.refreshToken
      )
    }
  )

  public static func live(
    apiURI: URL = InstantRuntimeConfiguration.defaultAPIURI,
    httpClient: InstantAuthHTTPClient = .live
  ) -> Self {
    Self { request in
      let urlRequest = try instantAuthRequest(
        apiURI: apiURI,
        path: ["runtime", "auth", "verify_refresh_token"],
        body: InstantVerifyRefreshTokenBody(
          appID: request.appID,
          refreshToken: request.refreshToken
        )
      )
      let response = try await httpClient.send(urlRequest)
      try validateInstantAuthResponse(response, operation: "verify refresh token")
      do {
        let decoded = try JSONDecoder().decode(
          InstantVerifyRefreshTokenResponse.self,
          from: response.data
        )
        return InstantRefreshTokenVerification(
          userID: decoded.user.id,
          refreshToken: decoded.user.refreshToken
        )
      } catch let error as InstantError {
        throw error
      } catch {
        throw InstantError(
          code: .decodeFailed,
          operation: "verify refresh token",
          message: "Instant auth returned an invalid verification response.",
          recovery: "Inspect the canonical verify_refresh_token response shape."
        )
      }
    }
  }
}
