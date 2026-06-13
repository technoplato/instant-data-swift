import Foundation

public enum InstantShareRole: String, Hashable, Codable, Sendable {
  case owner
  case writer
  case reader

  public var canWriteSharedRoot: Bool {
    switch self {
    case .owner, .writer:
      return true

    case .reader:
      return false
    }
  }
}

public struct InstantShare: Hashable, Codable, Sendable, Identifiable {
  public var id: String
  public var appID: String
  public var rootNamespace: String
  public var rootID: String
  public var ownerUserID: String
  public var token: String
  public var createdAt: InstantTimestamp
  public var updatedAt: InstantTimestamp
  public var revokedAt: InstantTimestamp?

  public var isRevoked: Bool {
    revokedAt != nil
  }

  public init(
    id: String,
    appID: String,
    rootNamespace: String,
    rootID: String,
    ownerUserID: String,
    token: String,
    createdAt: InstantTimestamp,
    updatedAt: InstantTimestamp,
    revokedAt: InstantTimestamp? = nil
  ) {
    self.id = id
    self.appID = appID
    self.rootNamespace = rootNamespace
    self.rootID = rootID
    self.ownerUserID = ownerUserID
    self.token = token
    self.createdAt = createdAt
    self.updatedAt = updatedAt
    self.revokedAt = revokedAt
  }
}

public struct InstantShareMembership: Hashable, Codable, Sendable, Identifiable {
  public var id: String { "\(appID):\(shareID):\(userID)" }
  public var appID: String
  public var shareID: String
  public var userID: String
  public var role: InstantShareRole
  public var acceptedAt: InstantTimestamp
  public var revokedAt: InstantTimestamp?

  public var isRevoked: Bool {
    revokedAt != nil
  }

  public init(
    appID: String,
    shareID: String,
    userID: String,
    role: InstantShareRole,
    acceptedAt: InstantTimestamp,
    revokedAt: InstantTimestamp? = nil
  ) {
    self.appID = appID
    self.shareID = shareID
    self.userID = userID
    self.role = role
    self.acceptedAt = acceptedAt
    self.revokedAt = revokedAt
  }
}

public struct InstantShareSnapshot: Hashable, Codable, Sendable, Identifiable {
  public var id: String { share.id }
  public var share: InstantShare
  public var memberships: [InstantShareMembership]

  public init(share: InstantShare, memberships: [InstantShareMembership]) {
    self.share = share
    self.memberships = memberships
  }
}
