import Foundation

public struct InstantOAuthSignInRequest: Sendable {
  public var appID: String
  public var code: String
  public var codeVerifier: String?
  public var refreshToken: String?
  public var signedInAt: InstantTimestamp
  public var makeID: @Sendable () -> String

  public init(
    appID: String,
    code: String,
    codeVerifier: String? = nil,
    refreshToken: String? = nil,
    signedInAt: InstantTimestamp,
    makeID: @escaping @Sendable () -> String
  ) {
    self.appID = appID
    self.code = code
    self.codeVerifier = codeVerifier
    self.refreshToken = refreshToken
    self.signedInAt = signedInAt
    self.makeID = makeID
  }
}

public struct InstantOAuthVerification: Hashable, Codable, Sendable {
  public var userID: String
  public var refreshToken: String?

  public init(userID: String, refreshToken: String? = nil) {
    self.userID = userID
    self.refreshToken = refreshToken
  }
}

public struct InstantOAuthExchange: Sendable {
  public var signIn:
    @Sendable (InstantOAuthSignInRequest) async throws -> InstantOAuthVerification

  public init(
    signIn: @escaping @Sendable (InstantOAuthSignInRequest) async throws
      -> InstantOAuthVerification
  ) {
    self.signIn = signIn
  }
}

extension InstantOAuthExchange {
  public static let local = Self(
    signIn: { request in
      let localID = request.makeID()
      return InstantOAuthVerification(
        userID: "oauth:\(localID)",
        refreshToken: "local-oauth:\(request.appID):\(localID)"
      )
    }
  )
}
