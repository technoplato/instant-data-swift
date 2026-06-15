import Foundation

public struct InstantPlatformAppCreateRequest: Sendable {
  public var title: String
  public var orgID: String
  public var createdAt: InstantTimestamp
  public var makeID: @Sendable () -> String

  public init(
    title: String,
    orgID: String,
    createdAt: InstantTimestamp,
    makeID: @escaping @Sendable () -> String
  ) {
    self.title = title
    self.orgID = orgID
    self.createdAt = createdAt
    self.makeID = makeID
  }
}

public struct InstantPlatformApp: Hashable, Codable, Sendable, Identifiable {
  public var id: String
  public var title: String
  public var orgID: String
  public var createdAt: InstantTimestamp

  public init(id: String, title: String, orgID: String, createdAt: InstantTimestamp) {
    self.id = id
    self.title = title
    self.orgID = orgID
    self.createdAt = createdAt
  }
}

public struct InstantPlatformAppClient: Sendable {
  public var createApp:
    @Sendable (InstantPlatformAppCreateRequest) async throws -> InstantPlatformApp

  public init(
    createApp: @escaping @Sendable (InstantPlatformAppCreateRequest) async throws
      -> InstantPlatformApp
  ) {
    self.createApp = createApp
  }
}

extension InstantPlatformAppClient {
  public static let local = Self { request in
    InstantPlatformApp(
      id: "local-platform-\(request.makeID())",
      title: request.title,
      orgID: request.orgID,
      createdAt: request.createdAt
    )
  }
}
