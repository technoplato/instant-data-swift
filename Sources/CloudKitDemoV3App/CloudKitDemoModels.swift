import AuthV3App
import Foundation
import InstantSwiftData
import InstantSwiftDataSchema

public typealias CloudKitDemoV3User = AuthV3User
public typealias CloudKitDemoV3AuthProviders = AuthV3Providers

public enum CloudKitDemoV3Schema {
  public static let document = InstantSchemaExamples.sharingDocument
  public static let permissions = InstantSchemaExamples.sharingPermissions
  public static let attributes = document.attributes
}

@InstantEntity("v3_shared_lists")
public struct CloudKitDemoV3Counter: Codable, Hashable, InstantEntityModel {
  public static let identifier = InstantAttributePath<Self, String>("id")
  public static let title = InstantAttributePath<Self, String>("title")
  public static let value = InstantAttributePath<Self, Int>("value")
  public static let owner = InstantAttributePath<Self, InstantID<CloudKitDemoV3User>>("owner")
  public static let readers = InstantAttributePath<Self, InstantID<CloudKitDemoV3User>>("readers")
  public static let writers = InstantAttributePath<Self, InstantID<CloudKitDemoV3User>>("writers")
  public static let share = InstantReverseRelation<Self, CloudKitDemoV3Share>(
    attribute: CloudKitDemoV3Share.root
  )
  public static let instantAttributes = CloudKitDemoV3Schema.attributes.filter {
    $0.namespace == instantNamespace
  }

  public var id: InstantID<Self>
  public var title: String
  public var value: Int
  public var owner: InstantID<CloudKitDemoV3User>
  public var readers: [InstantID<CloudKitDemoV3User>]
  public var writers: [InstantID<CloudKitDemoV3User>]
  public var share: CloudKitDemoV3Share?

  public init(snapshot: InstantEntitySnapshot) throws {
    id = InstantID(rawValue: snapshot.id)
    title = try snapshot.cloudKitDemoV3String("title", operation: "decode shared counter")
    value = try snapshot.cloudKitDemoV3Integer("value", operation: "decode shared counter")
    owner = try snapshot.cloudKitDemoV3Ref("owner", operation: "decode shared counter")
    readers = snapshot.cloudKitDemoV3Refs("readers")
    writers = snapshot.cloudKitDemoV3Refs("writers")
    share = try snapshot.cloudKitDemoV3Linked("share").first.map {
      try CloudKitDemoV3Share(snapshot: InstantEntitySnapshot($0))
    }
  }

  public static func visible(to userID: InstantID<CloudKitDemoV3User>) -> InstantQuery<Self> {
    let memberships = CloudKitDemoV3ShareMembership.query
      .include(CloudKitDemoV3ShareMembership.user)
    let shares = CloudKitDemoV3Share.query
      .include(CloudKitDemoV3Share.owner)
      .include(CloudKitDemoV3Share.memberships, memberships)
    return
      query
      .where(.any(owner == userID, readers == userID, writers == userID))
      .include(owner)
      .include(readers)
      .include(writers)
      .include(share, shares)
      .order(title)
  }

  public static func byID(_ id: InstantID<Self>) -> InstantQuery<Self> {
    query.where(identifier == id.rawValue)
  }
}

@InstantEntity("v3_shares")
public struct CloudKitDemoV3Share: Codable, Hashable, InstantEntityModel {
  public static let token = InstantAttributePath<Self, String>("token")
  public static let rootNamespace = InstantAttributePath<Self, String>("rootNamespace")
  public static let rootID = InstantAttributePath<Self, String>("rootID")
  public static let createdAt = InstantAttributePath<Self, Date>("createdAt")
  public static let updatedAt = InstantAttributePath<Self, Date>("updatedAt")
  public static let revokedAt = InstantAttributePath<Self, Date?>("revokedAt")
  public static let owner = InstantAttributePath<Self, InstantID<CloudKitDemoV3User>>("owner")
  public static let root = InstantAttributePath<Self, InstantID<CloudKitDemoV3Counter>>("root")
  public static let memberships = InstantReverseRelation<Self, CloudKitDemoV3ShareMembership>(
    attribute: CloudKitDemoV3ShareMembership.share
  )
  public static let instantAttributes = CloudKitDemoV3Schema.attributes.filter {
    $0.namespace == instantNamespace
  }

  public var id: InstantID<Self>
  public var token: String
  public var rootNamespace: String
  public var rootID: String
  public var createdAt: Date
  public var updatedAt: Date
  public var revokedAt: Date?
  public var owner: InstantID<CloudKitDemoV3User>
  public var root: InstantID<CloudKitDemoV3Counter>
  public var memberships: [CloudKitDemoV3ShareMembership]

  public init(snapshot: InstantEntitySnapshot) throws {
    id = InstantID(rawValue: snapshot.id)
    token = try snapshot.cloudKitDemoV3String("token", operation: "decode counter share")
    rootNamespace = try snapshot.cloudKitDemoV3String(
      "rootNamespace", operation: "decode counter share"
    )
    rootID = try snapshot.cloudKitDemoV3String("rootID", operation: "decode counter share")
    createdAt = try snapshot.cloudKitDemoV3Date("createdAt", operation: "decode counter share")
    updatedAt = try snapshot.cloudKitDemoV3Date("updatedAt", operation: "decode counter share")
    revokedAt = try snapshot.cloudKitDemoV3OptionalDate(
      "revokedAt", operation: "decode counter share"
    )
    owner = try snapshot.cloudKitDemoV3Ref("owner", operation: "decode counter share")
    root = try snapshot.cloudKitDemoV3Ref("root", operation: "decode counter share")
    memberships = try snapshot.cloudKitDemoV3Linked("memberships").map {
      try CloudKitDemoV3ShareMembership(snapshot: InstantEntitySnapshot($0))
    }
  }

  public static func matching(token value: String) -> InstantQuery<Self> {
    query
      .where(token == value)
      .include(root)
      .include(owner)
      .include(
        memberships, CloudKitDemoV3ShareMembership.query.include(CloudKitDemoV3ShareMembership.user)
      )
  }
}

@InstantEntity("v3_share_memberships")
public struct CloudKitDemoV3ShareMembership: Codable, Hashable, InstantEntityModel {
  public static let role = InstantAttributePath<Self, String>("role")
  public static let acceptedAt = InstantAttributePath<Self, Date>("acceptedAt")
  public static let revokedAt = InstantAttributePath<Self, Date?>("revokedAt")
  public static let share = InstantAttributePath<Self, InstantID<CloudKitDemoV3Share>>("share")
  public static let user = InstantAttributePath<Self, InstantID<CloudKitDemoV3User>>("user")
  public static let instantAttributes = CloudKitDemoV3Schema.attributes.filter {
    $0.namespace == instantNamespace
  }

  public var id: InstantID<Self>
  public var role: String
  public var acceptedAt: Date
  public var revokedAt: Date?
  public var share: InstantID<CloudKitDemoV3Share>
  public var user: InstantID<CloudKitDemoV3User>

  public init(snapshot: InstantEntitySnapshot) throws {
    id = InstantID(rawValue: snapshot.id)
    role = try snapshot.cloudKitDemoV3String("role", operation: "decode counter membership")
    acceptedAt = try snapshot.cloudKitDemoV3Date(
      "acceptedAt", operation: "decode counter membership"
    )
    revokedAt = try snapshot.cloudKitDemoV3OptionalDate(
      "revokedAt", operation: "decode counter membership"
    )
    share = try snapshot.cloudKitDemoV3Ref("share", operation: "decode counter membership")
    user = try snapshot.cloudKitDemoV3Ref("user", operation: "decode counter membership")
  }

  public var shareRole: InstantShareRole? { InstantShareRole(rawValue: role) }
}

extension InstantEntitySnapshot {
  fileprivate init(_ linked: InstantLinkedEntitySnapshot) {
    self.init(
      id: linked.id, namespace: linked.namespace, values: linked.values, links: linked.links)
  }

  fileprivate func cloudKitDemoV3Linked(_ name: String) -> [InstantLinkedEntitySnapshot] {
    links?[name] ?? []
  }

  fileprivate func cloudKitDemoV3String(_ path: String, operation: String) throws -> String {
    guard case let .string(value) = values[path]?.first else {
      throw cloudKitDemoV3DecodeError(self, path: path, operation: operation, expected: "a string")
    }
    return value
  }

  fileprivate func cloudKitDemoV3Integer(_ path: String, operation: String) throws -> Int {
    guard case let .number(value) = values[path]?.first, value.rounded() == value else {
      throw cloudKitDemoV3DecodeError(
        self, path: path, operation: operation, expected: "an integer")
    }
    return Int(value)
  }

  fileprivate func cloudKitDemoV3Date(_ path: String, operation: String) throws -> Date {
    guard case let .date(value) = values[path]?.first else {
      throw cloudKitDemoV3DecodeError(self, path: path, operation: operation, expected: "a date")
    }
    return value
  }

  fileprivate func cloudKitDemoV3OptionalDate(_ path: String, operation: String) throws -> Date? {
    guard let value = values[path]?.first, value != .null else { return nil }
    guard case let .date(date) = value else {
      throw cloudKitDemoV3DecodeError(
        self, path: path, operation: operation, expected: "a date or null")
    }
    return date
  }

  fileprivate func cloudKitDemoV3Ref<Entity>(
    _ path: String,
    operation: String
  ) throws -> InstantID<Entity> {
    guard case let .ref(value) = values[path]?.first else {
      throw cloudKitDemoV3DecodeError(
        self, path: path, operation: operation, expected: "an entity ref")
    }
    return InstantID(rawValue: value)
  }

  fileprivate func cloudKitDemoV3Refs<Entity>(_ path: String) -> [InstantID<Entity>] {
    (values[path]?.values ?? []).compactMap {
      guard case let .ref(value) = $0 else { return nil }
      return InstantID(rawValue: value)
    }
  }
}

private func cloudKitDemoV3DecodeError(
  _ snapshot: InstantEntitySnapshot,
  path: String,
  operation: String,
  expected: String
) -> InstantError {
  InstantError(
    code: .decodeFailed,
    operation: operation,
    namespace: snapshot.namespace,
    path: path,
    localID: snapshot.id,
    message: "Expected \(expected) at '\(path)'.",
    recovery: "Keep CloudKitDemo V3 decoding aligned with the settled sharing schema."
  )
}
