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
}
