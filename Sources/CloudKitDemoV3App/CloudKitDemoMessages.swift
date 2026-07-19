import Foundation
import InstantSwiftData

public struct CloudKitDemoV3CounterChange: Hashable, Sendable {
  public var counterID: InstantID<CloudKitDemoV3Counter>
  public var value: Int

  public init(counterID: InstantID<CloudKitDemoV3Counter>, value: Int) {
    self.counterID = counterID
    self.value = value
  }
}

public struct CreateCloudKitDemoV3SharedCounter: InstantMessage {
  public var counterID: InstantID<CloudKitDemoV3Counter>
  public var shareID: InstantID<CloudKitDemoV3Share>
  public var ownerMembershipID: InstantID<CloudKitDemoV3ShareMembership>
  public var ownerID: InstantID<CloudKitDemoV3User>
  public var title: String
  public var value: Int
  public var token: String
  public var createdAt: Date

  public init(
    counterID: InstantID<CloudKitDemoV3Counter>,
    shareID: InstantID<CloudKitDemoV3Share>,
    ownerMembershipID: InstantID<CloudKitDemoV3ShareMembership>,
    ownerID: InstantID<CloudKitDemoV3User>,
    title: String,
    value: Int = 0,
    token: String,
    createdAt: Date
  ) {
    self.counterID = counterID
    self.shareID = shareID
    self.ownerMembershipID = ownerMembershipID
    self.ownerID = ownerID
    self.title = title
    self.value = value
    self.token = token
    self.createdAt = createdAt
  }

  public func prepare(using client: InstantSwiftDataClient) async throws
    -> InstantPreparedMessage<CloudKitDemoV3CounterChange>
  {
    _ = client
    return InstantPreparedMessage(change: .init(counterID: counterID, value: value)) {
      CloudKitDemoV3Counter.create(
        id: counterID,
        CloudKitDemoV3Counter.title.set(title),
        CloudKitDemoV3Counter.value.set(value),
        CloudKitDemoV3Counter.owner.set(ownerID)
      )
      CloudKitDemoV3Share.create(
        id: shareID,
        CloudKitDemoV3Share.token.set(token),
        CloudKitDemoV3Share.rootNamespace.set(CloudKitDemoV3Counter.instantNamespace),
        CloudKitDemoV3Share.rootID.set(counterID.rawValue),
        CloudKitDemoV3Share.createdAt.set(createdAt),
        CloudKitDemoV3Share.updatedAt.set(createdAt),
        CloudKitDemoV3Share.revokedAt.set(nil),
        CloudKitDemoV3Share.owner.set(ownerID),
        CloudKitDemoV3Share.root.set(counterID)
      )
      CloudKitDemoV3ShareMembership.create(
        id: ownerMembershipID,
        CloudKitDemoV3ShareMembership.role.set(InstantShareRole.owner.rawValue),
        CloudKitDemoV3ShareMembership.acceptedAt.set(createdAt),
        CloudKitDemoV3ShareMembership.revokedAt.set(nil),
        CloudKitDemoV3ShareMembership.share.set(shareID),
        CloudKitDemoV3ShareMembership.user.set(ownerID)
      )
    }
  }
}

public struct IncrementCloudKitDemoV3Counter: InstantMessage {
  public var counterID: InstantID<CloudKitDemoV3Counter>
  public var delta: Int

  public init(counterID: InstantID<CloudKitDemoV3Counter>, delta: Int = 1) {
    self.counterID = counterID
    self.delta = delta
  }

  public func prepare(using client: InstantSwiftDataClient) async throws
    -> InstantPreparedMessage<CloudKitDemoV3CounterChange>
  {
    guard let counter = try await client.query(CloudKitDemoV3Counter.byID(counterID)).first else {
      throw InstantError(
        code: .validationFailed,
        operation: "increment shared counter",
        namespace: CloudKitDemoV3Counter.instantNamespace,
        localID: counterID.rawValue,
        message: "The shared counter was not found.",
        recovery: "Refresh visible counters and retry the increment."
      )
    }
    let nextValue = counter.value + delta
    return InstantPreparedMessage(change: .init(counterID: counterID, value: nextValue)) {
      CloudKitDemoV3Counter.updateExisting(
        id: counterID,
        CloudKitDemoV3Counter.value.set(nextValue)
      )
    }
  }
}

public struct CloudKitDemoV3ShareChange: Hashable, Sendable {
  public var shareID: InstantID<CloudKitDemoV3Share>
  public var counterID: InstantID<CloudKitDemoV3Counter>
  public var userID: InstantID<CloudKitDemoV3User>
  public var role: InstantShareRole?

  public init(
    shareID: InstantID<CloudKitDemoV3Share>,
    counterID: InstantID<CloudKitDemoV3Counter>,
    userID: InstantID<CloudKitDemoV3User>,
    role: InstantShareRole?
  ) {
    self.shareID = shareID
    self.counterID = counterID
    self.userID = userID
    self.role = role
  }
}

public struct AcceptCloudKitDemoV3Share: InstantMessage {
  public var token: String
  public var membershipID: InstantID<CloudKitDemoV3ShareMembership>
  public var userID: InstantID<CloudKitDemoV3User>
  public var acceptedAt: Date

  public init(
    token: String,
    membershipID: InstantID<CloudKitDemoV3ShareMembership>,
    userID: InstantID<CloudKitDemoV3User>,
    acceptedAt: Date
  ) {
    self.token = token
    self.membershipID = membershipID
    self.userID = userID
    self.acceptedAt = acceptedAt
  }

  public func prepare(using client: InstantSwiftDataClient) async throws
    -> InstantPreparedMessage<CloudKitDemoV3ShareChange>
  {
    guard let share = try await client.query(CloudKitDemoV3Share.matching(token: token)).first
    else {
      throw InstantError(
        code: .validationFailed,
        operation: "accept counter share",
        message: "No active counter share matches this token.",
        recovery: "Ask the owner for a current share token and retry."
      )
    }
    return InstantPreparedMessage(
      change: .init(shareID: share.id, counterID: share.root, userID: userID, role: .reader)
    ) {
      CloudKitDemoV3ShareMembership.create(
        id: membershipID,
        CloudKitDemoV3ShareMembership.role.set(InstantShareRole.reader.rawValue),
        CloudKitDemoV3ShareMembership.acceptedAt.set(acceptedAt),
        CloudKitDemoV3ShareMembership.revokedAt.set(nil),
        CloudKitDemoV3ShareMembership.share.set(share.id),
        CloudKitDemoV3ShareMembership.user.set(userID)
      )
      CloudKitDemoV3Counter.readers.link(from: share.root, to: userID)
      CloudKitDemoV3Share.updateExisting(
        id: share.id,
        CloudKitDemoV3Share.updatedAt.set(acceptedAt)
      )
    }
  }
}

public struct ChangeCloudKitDemoV3ShareRole: InstantMessage {
  public var shareID: InstantID<CloudKitDemoV3Share>
  public var membershipID: InstantID<CloudKitDemoV3ShareMembership>
  public var counterID: InstantID<CloudKitDemoV3Counter>
  public var userID: InstantID<CloudKitDemoV3User>
  public var previousRole: InstantShareRole
  public var role: InstantShareRole
  public var updatedAt: Date

  public init(
    shareID: InstantID<CloudKitDemoV3Share>,
    membershipID: InstantID<CloudKitDemoV3ShareMembership>,
    counterID: InstantID<CloudKitDemoV3Counter>,
    userID: InstantID<CloudKitDemoV3User>,
    previousRole: InstantShareRole,
    role: InstantShareRole,
    updatedAt: Date
  ) {
    self.shareID = shareID
    self.membershipID = membershipID
    self.counterID = counterID
    self.userID = userID
    self.previousRole = previousRole
    self.role = role
    self.updatedAt = updatedAt
  }

  public func prepare(using client: InstantSwiftDataClient) async throws
    -> InstantPreparedMessage<CloudKitDemoV3ShareChange>
  {
    _ = client
    try validateParticipantRole(previousRole)
    try validateParticipantRole(role)
    return InstantPreparedMessage(
      change: .init(shareID: shareID, counterID: counterID, userID: userID, role: role)
    ) {
      roleLink(previousRole).unlink(from: counterID, to: userID)
      roleLink(role).link(from: counterID, to: userID)
      CloudKitDemoV3ShareMembership.updateExisting(
        id: membershipID,
        CloudKitDemoV3ShareMembership.role.set(role.rawValue),
        CloudKitDemoV3ShareMembership.revokedAt.set(nil)
      )
      CloudKitDemoV3Share.updateExisting(
        id: shareID,
        CloudKitDemoV3Share.updatedAt.set(updatedAt)
      )
    }
  }
}

public struct RevokeCloudKitDemoV3Participant: InstantMessage {
  public var shareID: InstantID<CloudKitDemoV3Share>
  public var membershipID: InstantID<CloudKitDemoV3ShareMembership>
  public var counterID: InstantID<CloudKitDemoV3Counter>
  public var userID: InstantID<CloudKitDemoV3User>
  public var role: InstantShareRole
  public var revokedAt: Date

  public init(
    shareID: InstantID<CloudKitDemoV3Share>,
    membershipID: InstantID<CloudKitDemoV3ShareMembership>,
    counterID: InstantID<CloudKitDemoV3Counter>,
    userID: InstantID<CloudKitDemoV3User>,
    role: InstantShareRole,
    revokedAt: Date
  ) {
    self.shareID = shareID
    self.membershipID = membershipID
    self.counterID = counterID
    self.userID = userID
    self.role = role
    self.revokedAt = revokedAt
  }

  public func prepare(using client: InstantSwiftDataClient) async throws
    -> InstantPreparedMessage<CloudKitDemoV3ShareChange>
  {
    _ = client
    try validateParticipantRole(role)
    return InstantPreparedMessage(
      change: .init(shareID: shareID, counterID: counterID, userID: userID, role: nil)
    ) {
      roleLink(role).unlink(from: counterID, to: userID)
      CloudKitDemoV3ShareMembership.delete(id: membershipID)
      CloudKitDemoV3Share.updateExisting(
        id: shareID,
        CloudKitDemoV3Share.updatedAt.set(revokedAt)
      )
    }
  }
}

public enum CloudKitDemoV3ShareMessageError: Error, Equatable, Sendable {
  case participantRoleRequired(InstantShareRole)
}

private func validateParticipantRole(_ role: InstantShareRole) throws {
  guard role != .owner else {
    throw CloudKitDemoV3ShareMessageError.participantRoleRequired(role)
  }
}

private func roleLink(
  _ role: InstantShareRole
) -> InstantAttributePath<CloudKitDemoV3Counter, InstantID<CloudKitDemoV3User>> {
  switch role {
  case .reader:
    CloudKitDemoV3Counter.readers
  case .writer:
    CloudKitDemoV3Counter.writers
  case .owner:
    CloudKitDemoV3Counter.owner
  }
}
