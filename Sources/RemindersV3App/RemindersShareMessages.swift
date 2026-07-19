import Foundation
import InstantSwiftData

public struct RemindersV3ShareChanged: Hashable, Sendable {
  public var shareID: InstantID<RemindersV3Share>
  public var listID: InstantID<RemindersV3List>
  public var userID: InstantID<RemindersV3User>
  public var role: InstantShareRole

  public init(
    shareID: InstantID<RemindersV3Share>,
    listID: InstantID<RemindersV3List>,
    userID: InstantID<RemindersV3User>,
    role: InstantShareRole
  ) {
    self.shareID = shareID
    self.listID = listID
    self.userID = userID
    self.role = role
  }
}

public struct CreateRemindersV3Share: InstantMessage {
  public var shareID: InstantID<RemindersV3Share>
  public var ownerMembershipID: InstantID<RemindersV3ShareMembership>
  public var listID: InstantID<RemindersV3List>
  public var ownerID: InstantID<RemindersV3User>
  public var token: String
  public var createdAt: Date

  public init(
    shareID: InstantID<RemindersV3Share>,
    ownerMembershipID: InstantID<RemindersV3ShareMembership>,
    listID: InstantID<RemindersV3List>,
    ownerID: InstantID<RemindersV3User>,
    token: String,
    createdAt: Date
  ) {
    self.shareID = shareID
    self.ownerMembershipID = ownerMembershipID
    self.listID = listID
    self.ownerID = ownerID
    self.token = token
    self.createdAt = createdAt
  }

  public func prepare(using client: InstantSwiftDataClient) async throws
    -> InstantPreparedMessage<RemindersV3ShareChanged>
  {
    _ = client
    return InstantPreparedMessage(
      change: .init(
        shareID: shareID,
        listID: listID,
        userID: ownerID,
        role: .owner
      )
    ) {
      RemindersV3Share.create(
        id: shareID,
        RemindersV3Share.token.set(token),
        RemindersV3Share.rootNamespace.set(RemindersV3List.instantNamespace),
        RemindersV3Share.rootID.set(listID.rawValue),
        RemindersV3Share.createdAt.set(createdAt),
        RemindersV3Share.updatedAt.set(createdAt),
        RemindersV3Share.revokedAt.set(nil),
        RemindersV3Share.owner.set(ownerID),
        RemindersV3Share.root.set(listID)
      )
      RemindersV3ShareMembership.create(
        id: ownerMembershipID,
        RemindersV3ShareMembership.role.set(InstantShareRole.owner.rawValue),
        RemindersV3ShareMembership.acceptedAt.set(createdAt),
        RemindersV3ShareMembership.revokedAt.set(nil),
        RemindersV3ShareMembership.share.set(shareID),
        RemindersV3ShareMembership.user.set(ownerID)
      )
    }
  }
}

public struct AcceptRemindersV3Share: InstantMessage {
  public var shareID: InstantID<RemindersV3Share>
  public var membershipID: InstantID<RemindersV3ShareMembership>
  public var listID: InstantID<RemindersV3List>
  public var userID: InstantID<RemindersV3User>
  public var role: InstantShareRole
  public var acceptedAt: Date

  public init(
    shareID: InstantID<RemindersV3Share>,
    membershipID: InstantID<RemindersV3ShareMembership>,
    listID: InstantID<RemindersV3List>,
    userID: InstantID<RemindersV3User>,
    role: InstantShareRole,
    acceptedAt: Date
  ) {
    self.shareID = shareID
    self.membershipID = membershipID
    self.listID = listID
    self.userID = userID
    self.role = role
    self.acceptedAt = acceptedAt
  }

  public func prepare(using client: InstantSwiftDataClient) async throws
    -> InstantPreparedMessage<RemindersV3ShareChanged>
  {
    _ = client
    try validateParticipantRole(role)
    return InstantPreparedMessage(
      change: .init(shareID: shareID, listID: listID, userID: userID, role: role)
    ) {
      RemindersV3ShareMembership.create(
        id: membershipID,
        RemindersV3ShareMembership.role.set(role.rawValue),
        RemindersV3ShareMembership.acceptedAt.set(acceptedAt),
        RemindersV3ShareMembership.revokedAt.set(nil),
        RemindersV3ShareMembership.share.set(shareID),
        RemindersV3ShareMembership.user.set(userID)
      )
      switch role {
      case .reader:
        RemindersV3List.readers.link(from: listID, to: userID)
      case .writer:
        RemindersV3List.writers.link(from: listID, to: userID)
      case .owner:
        RemindersV3List.owner.link(from: listID, to: userID)
      }
      RemindersV3Share.updateExisting(
        id: shareID,
        RemindersV3Share.updatedAt.set(acceptedAt)
      )
    }
  }
}

public struct ChangeRemindersV3ShareRole: InstantMessage {
  public var shareID: InstantID<RemindersV3Share>
  public var membershipID: InstantID<RemindersV3ShareMembership>
  public var listID: InstantID<RemindersV3List>
  public var userID: InstantID<RemindersV3User>
  public var previousRole: InstantShareRole
  public var role: InstantShareRole
  public var updatedAt: Date

  public init(
    shareID: InstantID<RemindersV3Share>,
    membershipID: InstantID<RemindersV3ShareMembership>,
    listID: InstantID<RemindersV3List>,
    userID: InstantID<RemindersV3User>,
    previousRole: InstantShareRole,
    role: InstantShareRole,
    updatedAt: Date
  ) {
    self.shareID = shareID
    self.membershipID = membershipID
    self.listID = listID
    self.userID = userID
    self.previousRole = previousRole
    self.role = role
    self.updatedAt = updatedAt
  }

  public func prepare(using client: InstantSwiftDataClient) async throws
    -> InstantPreparedMessage<RemindersV3ShareChanged>
  {
    _ = client
    try validateParticipantRole(previousRole)
    try validateParticipantRole(role)
    return InstantPreparedMessage(
      change: .init(shareID: shareID, listID: listID, userID: userID, role: role)
    ) {
      switch previousRole {
      case .reader:
        RemindersV3List.readers.unlink(from: listID, to: userID)
      case .writer:
        RemindersV3List.writers.unlink(from: listID, to: userID)
      case .owner:
        RemindersV3List.owner.unlink(from: listID, to: userID)
      }
      switch role {
      case .reader:
        RemindersV3List.readers.link(from: listID, to: userID)
      case .writer:
        RemindersV3List.writers.link(from: listID, to: userID)
      case .owner:
        RemindersV3List.owner.link(from: listID, to: userID)
      }
      RemindersV3ShareMembership.updateExisting(
        id: membershipID,
        RemindersV3ShareMembership.role.set(role.rawValue),
        RemindersV3ShareMembership.revokedAt.set(nil)
      )
      RemindersV3Share.updateExisting(
        id: shareID,
        RemindersV3Share.updatedAt.set(updatedAt)
      )
    }
  }
}

public struct RevokeRemindersV3Share: InstantMessage {
  public var shareID: InstantID<RemindersV3Share>
  public var membershipID: InstantID<RemindersV3ShareMembership>
  public var listID: InstantID<RemindersV3List>
  public var userID: InstantID<RemindersV3User>
  public var role: InstantShareRole
  public var revokedAt: Date

  public init(
    shareID: InstantID<RemindersV3Share>,
    membershipID: InstantID<RemindersV3ShareMembership>,
    listID: InstantID<RemindersV3List>,
    userID: InstantID<RemindersV3User>,
    role: InstantShareRole,
    revokedAt: Date
  ) {
    self.shareID = shareID
    self.membershipID = membershipID
    self.listID = listID
    self.userID = userID
    self.role = role
    self.revokedAt = revokedAt
  }

  public func prepare(using client: InstantSwiftDataClient) async throws
    -> InstantPreparedMessage<RemindersV3ShareChanged>
  {
    _ = client
    try validateParticipantRole(role)
    return InstantPreparedMessage(
      change: .init(shareID: shareID, listID: listID, userID: userID, role: role)
    ) {
      switch role {
      case .reader:
        RemindersV3List.readers.unlink(from: listID, to: userID)
      case .writer:
        RemindersV3List.writers.unlink(from: listID, to: userID)
      case .owner:
        RemindersV3List.owner.unlink(from: listID, to: userID)
      }
      RemindersV3ShareMembership.updateExisting(
        id: membershipID,
        RemindersV3ShareMembership.revokedAt.set(revokedAt)
      )
      RemindersV3Share.updateExisting(
        id: shareID,
        RemindersV3Share.updatedAt.set(revokedAt),
        RemindersV3Share.revokedAt.set(revokedAt)
      )
    }
  }
}

public enum RemindersV3ShareMessageError: Error, Equatable, Sendable {
  case participantRoleRequired(InstantShareRole)
}

private func validateParticipantRole(_ role: InstantShareRole) throws {
  guard role != .owner else {
    throw RemindersV3ShareMessageError.participantRoleRequired(role)
  }
}
