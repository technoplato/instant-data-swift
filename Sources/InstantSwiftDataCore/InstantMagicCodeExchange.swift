import Foundation

public struct InstantMagicCodeSendRequest: Sendable {
  public var appID: String
  public var apiURI: URL
  public var email: String
  public var sentAt: InstantTimestamp
  public var makeID: @Sendable () -> String

  public init(
    appID: String,
    apiURI: URL = InstantRuntimeConfiguration.defaultAPIURI,
    email: String,
    sentAt: InstantTimestamp,
    makeID: @escaping @Sendable () -> String
  ) {
    self.appID = appID
    self.apiURI = apiURI
    self.email = email
    self.sentAt = sentAt
    self.makeID = makeID
  }
}

public struct InstantMagicCodeVerifyRequest: Sendable {
  public var appID: String
  public var apiURI: URL
  public var email: String
  public var code: String
  public var challenge: InstantMagicCodeChallenge
  public var refreshToken: String?
  public var extraFields: [String: InstantValue]
  public var verifiedAt: InstantTimestamp

  public init(
    appID: String,
    apiURI: URL = InstantRuntimeConfiguration.defaultAPIURI,
    email: String,
    code: String,
    challenge: InstantMagicCodeChallenge,
    refreshToken: String? = nil,
    extraFields: [String: InstantValue] = [:],
    verifiedAt: InstantTimestamp
  ) {
    self.appID = appID
    self.apiURI = apiURI
    self.email = email
    self.code = code
    self.challenge = challenge
    self.refreshToken = refreshToken
    self.extraFields = extraFields
    self.verifiedAt = verifiedAt
  }
}

public struct InstantMagicCodeVerification: Hashable, Codable, Sendable {
  public var userID: String
  public var refreshToken: String?
  public var created: Bool?
  public var email: String?
  public var imageURL: String?
  public var type: InstantAuthUserType?

  public init(userID: String, refreshToken: String? = nil) {
    self.init(userID: userID, refreshToken: refreshToken, created: nil)
  }

  public init(
    userID: String,
    refreshToken: String?,
    created: Bool?,
    email: String? = nil,
    imageURL: String? = nil,
    type: InstantAuthUserType? = nil
  ) {
    self.userID = userID
    self.refreshToken = refreshToken
    self.created = created
    self.email = email
    self.imageURL = imageURL
    self.type = type
  }
}

public struct InstantMagicCodeSignInResult: Hashable, Codable, Sendable {
  public var session: InstantAuthSession
  public var created: Bool

  public init(session: InstantAuthSession, created: Bool) {
    self.session = session
    self.created = created
  }
}

public struct InstantMagicCodeExchange: Sendable {
  public var send:
    @Sendable (InstantMagicCodeSendRequest) async throws -> InstantMagicCodeChallenge
  public var verify:
    @Sendable (InstantMagicCodeVerifyRequest) async throws -> InstantMagicCodeVerification

  public init(
    send: @escaping @Sendable (InstantMagicCodeSendRequest) async throws
      -> InstantMagicCodeChallenge,
    verify: @escaping @Sendable (InstantMagicCodeVerifyRequest) async throws
      -> InstantMagicCodeVerification
  ) {
    self.send = send
    self.verify = verify
  }
}

extension InstantMagicCodeExchange {
  public static let local = Self(
    send: { request in
      let code = Self.makeLocalMagicCode(seed: request.makeID())
      return InstantMagicCodeChallenge(
        appID: request.appID,
        email: request.email,
        code: code,
        createdAt: request.sentAt,
        expiresAt: InstantTimestamp(
          milliseconds: request.sentAt.milliseconds + Self.localMagicCodeLifetimeMilliseconds
        )
      )
    },
    verify: { request in
      guard request.challenge.appID == request.appID, request.challenge.email == request.email else {
        throw Self.authFailed(
          message: "No pending magic code exists for '\(request.email)'.",
          recovery: "Run 'instant-swift-data auth magic-code send \(request.email)' before verifying."
        )
      }
      guard request.challenge.expiresAt >= request.verifiedAt else {
        throw Self.authFailed(
          message: "The magic code for '\(request.email)' has expired.",
          recovery: "Send a new magic code and verify it before it expires."
        )
      }
      guard request.challenge.code == request.code else {
        throw Self.authFailed(
          message: "The magic code for '\(request.email)' did not match.",
          recovery:
            "Enter the latest code returned by 'instant-swift-data auth magic-code send \(request.email)'."
        )
      }

      return InstantMagicCodeVerification(
        userID: "email:\(request.email)",
        refreshToken: "local-magic:\(request.appID):\(request.email)",
        created: nil,
        email: request.email,
        type: .user
      )
    }
  )

  public static let live = live()

  public static func live(httpClient: InstantAuthHTTPClient = .live) -> Self {
    Self(
      send: { request in
        let urlRequest = try instantAuthRequest(
          apiURI: request.apiURI,
          path: ["runtime", "auth", "send_magic_code"],
          body: InstantSendMagicCodeBody(appID: request.appID, email: request.email)
        )
        let response = try await httpClient.send(urlRequest)
        try validateInstantAuthResponse(response, operation: "send magic code")
        return InstantMagicCodeChallenge(
          appID: request.appID,
          email: request.email,
          code: "",
          createdAt: request.sentAt,
          expiresAt: InstantTimestamp(
            milliseconds: request.sentAt.milliseconds + Self.localMagicCodeLifetimeMilliseconds
          )
        )
      },
      verify: { request in
        let urlRequest = try instantAuthRequest(
          apiURI: request.apiURI,
          path: ["runtime", "auth", "verify_magic_code"],
          body: InstantVerifyMagicCodeBody(
            appID: request.appID,
            email: request.email,
            code: request.code,
            refreshToken: request.refreshToken,
            extraFields: request.extraFields
          )
        )
        let response = try await httpClient.send(urlRequest)
        try validateInstantAuthResponse(response, operation: "sign in with magic code")
        let decoded = try decodeInstantAuthUserResponse(
          response.data,
          operation: "sign in with magic code"
        )
        return InstantMagicCodeVerification(
          userID: decoded.user.id,
          refreshToken: decoded.user.refreshToken,
          created: decoded.created,
          email: decoded.user.email,
          imageURL: decoded.user.imageURL,
          type: decoded.user.type
        )
      }
    )
  }

  private static let localMagicCodeLifetimeMilliseconds: Int64 = 10 * 60 * 1000

  private static func makeLocalMagicCode(seed: String) -> String {
    let digits = seed.filter(\.isNumber)
    if digits.count >= 6 {
      return String(digits.prefix(6))
    }

    let checksum = seed.utf8.reduce(0) { partial, byte in
      (partial * 31 + Int(byte)) % 1_000_000
    }
    return String(format: "%06d", checksum)
  }

  private static func authFailed(message: String, recovery: String) -> InstantError {
    InstantError(
      code: .authFailed,
      operation: "sign in with magic code",
      message: message,
      recovery: recovery
    )
  }
}
