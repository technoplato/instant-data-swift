import Foundation

public struct InstantIDTokenSignInRequest: Sendable {
  public var appID: String
  public var clientName: String
  public var idToken: String
  public var nonce: String?
  public var refreshToken: String?
  public var signedInAt: InstantTimestamp
  public var makeID: @Sendable () -> String

  public init(
    appID: String,
    clientName: String,
    idToken: String,
    nonce: String? = nil,
    refreshToken: String? = nil,
    signedInAt: InstantTimestamp,
    makeID: @escaping @Sendable () -> String
  ) {
    self.appID = appID
    self.clientName = clientName
    self.idToken = idToken
    self.nonce = nonce
    self.refreshToken = refreshToken
    self.signedInAt = signedInAt
    self.makeID = makeID
  }
}

public struct InstantIDTokenVerification: Hashable, Codable, Sendable {
  public var userID: String
  public var refreshToken: String?

  public init(userID: String, refreshToken: String? = nil) {
    self.userID = userID
    self.refreshToken = refreshToken
  }
}

public struct InstantIDTokenExchange: Sendable {
  public var signIn:
    @Sendable (InstantIDTokenSignInRequest) async throws -> InstantIDTokenVerification

  public init(
    signIn: @escaping @Sendable (InstantIDTokenSignInRequest) async throws
      -> InstantIDTokenVerification
  ) {
    self.signIn = signIn
  }
}

extension InstantIDTokenExchange {
  public static let local = Self(
    signIn: { request in
      let localID = request.makeID()
      return InstantIDTokenVerification(
        userID: "id-token:\(request.clientName):\(localID)",
        refreshToken: "local-id-token:\(request.appID):\(request.clientName):\(localID)"
      )
    }
  )
}
