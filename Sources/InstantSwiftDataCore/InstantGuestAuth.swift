import Foundation

public struct InstantGuestAuthRequest: Sendable {
  public var appID: String
  public var apiURI: URL
  public var signedInAt: InstantTimestamp
  public var makeID: @Sendable () -> String

  public init(
    appID: String,
    apiURI: URL = InstantRuntimeConfiguration.defaultAPIURI,
    signedInAt: InstantTimestamp,
    makeID: @escaping @Sendable () -> String
  ) {
    self.appID = appID
    self.apiURI = apiURI
    self.signedInAt = signedInAt
    self.makeID = makeID
  }
}

public struct InstantGuestAuthVerification: Hashable, Codable, Sendable {
  public var userID: String
  public var refreshToken: String?
  public var email: String?
  public var imageURL: String?
  public var type: InstantAuthUserType?

  public init(
    userID: String,
    refreshToken: String? = nil,
    email: String? = nil,
    imageURL: String? = nil,
    type: InstantAuthUserType? = .guest
  ) {
    self.userID = userID
    self.refreshToken = refreshToken
    self.email = email
    self.imageURL = imageURL
    self.type = type
  }
}

public struct InstantGuestAuthenticator: Sendable {
  public var signIn:
    @Sendable (InstantGuestAuthRequest) async throws -> InstantGuestAuthVerification

  public init(
    signIn: @escaping @Sendable (InstantGuestAuthRequest) async throws
      -> InstantGuestAuthVerification
  ) {
    self.signIn = signIn
  }
}

extension InstantGuestAuthenticator {
  public static let local = Self { request in
    let userID = request.makeID()
    return InstantGuestAuthVerification(
      userID: userID,
      refreshToken: "local-guest:\(request.appID):\(userID)"
    )
  }

  public static let live = live()

  public static func live(httpClient: InstantAuthHTTPClient = .live) -> Self {
    Self { request in
      let urlRequest = try instantAuthRequest(
        apiURI: request.apiURI,
        path: ["runtime", "auth", "sign_in_guest"],
        body: InstantGuestAuthBody(appID: request.appID)
      )
      let response = try await httpClient.send(urlRequest)
      try validateInstantAuthResponse(response, operation: "sign in as guest")
      do {
        let decoded = try JSONDecoder().decode(InstantGuestAuthResponse.self, from: response.data)
        return InstantGuestAuthVerification(
          userID: decoded.user.id,
          refreshToken: decoded.user.refreshToken,
          email: decoded.user.email,
          imageURL: decoded.user.imageURL,
          type: decoded.user.type ?? .guest
        )
      } catch let error as InstantError {
        throw error
      } catch {
        throw InstantError(
          code: .decodeFailed,
          operation: "sign in as guest",
          message: "Instant auth returned an invalid guest sign-in response.",
          recovery: "Inspect the canonical sign_in_guest response shape."
        )
      }
    }
  }
}

private struct InstantGuestAuthBody: Encodable {
  var appID: String

  private enum CodingKeys: String, CodingKey {
    case appID = "app-id"
  }
}

private struct InstantGuestAuthResponse: Decodable {
  struct User: Decodable {
    var id: String
    var refreshToken: String?
    var email: String?
    var imageURL: String?
    var type: InstantAuthUserType?

    private enum CodingKeys: String, CodingKey {
      case id
      case refreshToken = "refresh_token"
      case email
      case imageURL
      case type
    }
  }

  var user: User
}
