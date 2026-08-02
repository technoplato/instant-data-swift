import Foundation

public struct InstantIDTokenSignInRequest: Sendable {
  public var appID: String
  public var apiURI: URL
  public var clientName: String
  public var idToken: String
  public var nonce: String?
  public var refreshToken: String?
  public var signedInAt: InstantTimestamp
  public var makeID: @Sendable () -> String

  public init(
    appID: String,
    apiURI: URL = InstantRuntimeConfiguration.defaultAPIURI,
    clientName: String,
    idToken: String,
    nonce: String? = nil,
    refreshToken: String? = nil,
    signedInAt: InstantTimestamp,
    makeID: @escaping @Sendable () -> String
  ) {
    self.appID = appID
    self.apiURI = apiURI
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
  public var email: String?
  public var imageURL: String?
  public var type: InstantAuthUserType?
  public var guestPromotionLinkEvidence: InstantGuestPromotionLinkEvidence?

  public init(
    userID: String,
    refreshToken: String? = nil,
    email: String? = nil,
    imageURL: String? = nil,
    type: InstantAuthUserType? = nil,
    guestPromotionLinkEvidence: InstantGuestPromotionLinkEvidence? = nil
  ) {
    self.userID = userID
    self.refreshToken = refreshToken
    self.email = email
    self.imageURL = imageURL
    self.type = type
    self.guestPromotionLinkEvidence = guestPromotionLinkEvidence
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

  public static let live = live()

  public static func live(httpClient: InstantAuthHTTPClient = .live) -> Self {
    Self { request in
      let urlRequest = try instantAuthRequest(
        apiURI: request.apiURI,
        path: ["runtime", "oauth", "id_token"],
        body: InstantIDTokenBody(
          appID: request.appID,
          nonce: request.nonce,
          idToken: request.idToken,
          clientName: request.clientName,
          refreshToken: request.refreshToken
        )
      )
      let response = try await httpClient.send(urlRequest)
      try validateInstantAuthResponse(response, operation: "sign in with id token")
      let decoded = try decodeInstantAuthUserResponse(
        response.data,
        operation: "sign in with id token"
      )
      return InstantIDTokenVerification(
        userID: decoded.user.id,
        refreshToken: decoded.user.refreshToken,
        email: decoded.user.email,
        imageURL: decoded.user.imageURL,
        type: decoded.user.type,
        guestPromotionLinkEvidence: request.refreshToken == nil
          ? nil
          : .instantServerAcceptedGuestToken
      )
    }
  }
}
