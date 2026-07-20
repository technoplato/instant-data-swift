import Foundation

public struct InstantOAuthSignInRequest: Sendable {
  public var appID: String
  public var apiURI: URL
  public var code: String
  public var codeVerifier: String?
  public var refreshToken: String?
  public var signedInAt: InstantTimestamp
  public var makeID: @Sendable () -> String

  public init(
    appID: String,
    apiURI: URL = InstantRuntimeConfiguration.defaultAPIURI,
    code: String,
    codeVerifier: String? = nil,
    refreshToken: String? = nil,
    signedInAt: InstantTimestamp,
    makeID: @escaping @Sendable () -> String
  ) {
    self.appID = appID
    self.apiURI = apiURI
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

  public static let live = live()

  public static func live(httpClient: InstantAuthHTTPClient = .live) -> Self {
    Self { request in
      let urlRequest = try instantAuthRequest(
        apiURI: request.apiURI,
        path: ["runtime", "oauth", "token"],
        body: InstantOAuthTokenBody(
          appID: request.appID,
          code: request.code,
          codeVerifier: request.codeVerifier,
          refreshToken: request.refreshToken
        )
      )
      let response = try await httpClient.send(urlRequest)
      try validateInstantAuthResponse(response, operation: "sign in with oauth")
      let decoded = try decodeInstantAuthUserResponse(
        response.data,
        operation: "sign in with oauth"
      )
      return InstantOAuthVerification(
        userID: decoded.user.id,
        refreshToken: decoded.user.refreshToken
      )
    }
  }
}
