import Foundation

public struct InstantUserCookieSyncUser: Hashable, Encodable, Sendable {
  public var id: String
  public var refreshToken: String?
  public var isGuest: Bool

  public init(id: String, refreshToken: String?, isGuest: Bool) {
    self.id = id
    self.refreshToken = refreshToken
    self.isGuest = isGuest
  }

  public init(_ session: InstantAuthSession) {
    self.init(
      id: session.userID,
      refreshToken: session.refreshToken,
      isGuest: session.isGuest
    )
  }

  private enum CodingKeys: String, CodingKey {
    case id
    case refreshToken = "refresh_token"
    case isGuest
  }
}

public struct InstantUserCookieSyncRequest: Hashable, Encodable, Sendable {
  public var type: String
  public var appID: String
  public var firstPartyURL: URL
  public var user: InstantUserCookieSyncUser?
  public var syncedAt: InstantTimestamp

  public init(
    appID: String,
    firstPartyURL: URL,
    user: InstantUserCookieSyncUser?,
    syncedAt: InstantTimestamp
  ) {
    self.type = "sync-user"
    self.appID = appID
    self.firstPartyURL = firstPartyURL
    self.user = user
    self.syncedAt = syncedAt
  }

  private enum CodingKeys: String, CodingKey {
    case type
    case appID = "appId"
    case user
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(type, forKey: .type)
    try container.encode(appID, forKey: .appID)
    if let user {
      try container.encode(user, forKey: .user)
    } else {
      try container.encodeNil(forKey: .user)
    }
  }
}

public struct InstantUserCookieSyncClient: Sendable {
  public var sync:
    @Sendable (InstantUserCookieSyncRequest) async throws -> Void

  public init(
    sync: @escaping @Sendable (InstantUserCookieSyncRequest) async throws -> Void
  ) {
    self.sync = sync
  }
}

extension InstantUserCookieSyncClient {
  public static let live = Self { request in
    let data = try JSONEncoder().encode(request)
    var urlRequest = URLRequest(url: Self.firstPartySyncURL(for: request.firstPartyURL))
    urlRequest.httpMethod = "POST"
    urlRequest.httpBody = data
    urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")

    let (_, response) = try await URLSession.shared.data(for: urlRequest)
    guard let httpResponse = response as? HTTPURLResponse,
      (200..<300).contains(httpResponse.statusCode)
    else {
      throw URLError(.badServerResponse)
    }
  }

  public static let local = Self { _ in }

  private static func firstPartySyncURL(for firstPartyURL: URL) -> URL {
    let absoluteString = firstPartyURL.absoluteString
    guard !absoluteString.hasSuffix("/") else { return firstPartyURL }
    return URL(string: absoluteString + "/") ?? firstPartyURL
  }
}
