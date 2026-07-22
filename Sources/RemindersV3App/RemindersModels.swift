import AuthV3App
import Foundation
import InstantSwiftData
import InstantSwiftDataSchema

public typealias RemindersV3User = AuthV3User
public typealias RemindersV3AuthProviders = AuthV3Providers

extension AuthV3User {
  public static func remindersUser(
    id: InstantID<Self>
  ) -> InstantQuery<Self> {
    query.where(identifier == id.rawValue)
  }

  public static func remindersUsers(
    ids: [InstantID<Self>]
  ) -> InstantQuery<Self>? {
    let values = Array(Set(ids.map(\.rawValue))).sorted()
    guard !values.isEmpty else { return nil }
    return query.where(identifier.isIn(values))
  }

  public static func remindersUsers(
    matchingEmail rawSearch: String,
    limit: UInt = 8
  ) -> InstantQuery<Self>? {
    let search = rawSearch
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .filter { $0 != "%" && $0 != "_" }
    guard search.count >= 2 else { return nil }
    return InstantQuery(
      filters: [.iLike(field: "email", pattern: "%\(search)%")],
      order: InstantQueryOrder("email", .ascending),
      limit: limit
    )
  }

  public var remindersIdentityTitle: String {
    nonempty(displayName)
      ?? nonempty(username).map { "@\($0)" }
      ?? nonempty(email)
      ?? "Guest account"
  }

  public var remindersIdentitySubtitle: String? {
    guard remindersIdentityTitle != email else { return nil }
    return nonempty(email)
  }

  private func nonempty(_ value: String?) -> String? {
    value?
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .remindersNonempty
  }
}

extension String {
  var remindersNonempty: String? { isEmpty ? nil : self }
}

public enum RemindersV3Priority: Int, Codable, CaseIterable, Hashable, InstantNumberEnum,
  Sendable
{
  case low = 1
  case medium
  case high
}

public enum RemindersV3Schema {
  public static let attributes = InstantSchemaExamples.remindersV3Document.attributes
}

@InstantEntity("remindersLists")
public struct RemindersV3List: Codable, Hashable, InstantEntityModel {
  public static let identifier = InstantAttributePath<Self, String>("id")
  public static let title = InstantAttributePath<Self, String>("title")
  public static let color = InstantAttributePath<Self, String>("color")
  public static let coverFileID = InstantAttributePath<Self, String?>("coverFileID")
  public static let position = InstantAttributePath<Self, Int>("position")
  public static let createdAt = InstantAttributePath<Self, Date>("createdAt")
  public static let owner = InstantAttributePath<Self, InstantID<RemindersV3User>>("owner")
  public static let readers = InstantAttributePath<Self, InstantID<RemindersV3User>>("readers")
  public static let writers = InstantAttributePath<Self, InstantID<RemindersV3User>>("writers")
  public static let reminders = InstantReverseRelation<Self, RemindersV3Reminder>(
    attribute: RemindersV3Reminder.list
  )
  public static let share = InstantReverseRelation<Self, RemindersV3Share>(
    attribute: RemindersV3Share.root
  )
  public static let instantAttributes = RemindersV3Schema.attributes.filter {
    $0.namespace == instantNamespace
  }

  public var id: InstantID<Self>
  public var title: String
  public var color: String
  public var coverFileID: String?
  public var position: Int
  public var createdAt: Date
  public var owner: InstantID<RemindersV3User>
  public var readers: [InstantID<RemindersV3User>]
  public var writers: [InstantID<RemindersV3User>]
  public var reminders: [RemindersV3Reminder]
  public var share: RemindersV3Share?

  public init(
    id: InstantID<Self>,
    title: String,
    color: String,
    coverFileID: String? = nil,
    position: Int,
    createdAt: Date,
    owner: InstantID<RemindersV3User>,
    readers: [InstantID<RemindersV3User>] = [],
    writers: [InstantID<RemindersV3User>] = [],
    reminders: [RemindersV3Reminder] = [],
    share: RemindersV3Share? = nil
  ) {
    self.id = id
    self.title = title
    self.color = color
    self.coverFileID = coverFileID
    self.position = position
    self.createdAt = createdAt
    self.owner = owner
    self.readers = readers
    self.writers = writers
    self.reminders = reminders
    self.share = share
  }

  public init(snapshot: InstantEntitySnapshot) throws {
    id = InstantID(rawValue: snapshot.id)
    title = try snapshot.remindersV3String("title", operation: "decode Reminders V3 list")
    color = try snapshot.remindersV3String("color", operation: "decode Reminders V3 list")
    coverFileID = try snapshot.remindersV3OptionalString(
      "coverFileID",
      operation: "decode Reminders V3 list"
    )
    position = try snapshot.remindersV3Integer(
      "position",
      operation: "decode Reminders V3 list"
    )
    createdAt = try snapshot.remindersV3Date(
      "createdAt",
      operation: "decode Reminders V3 list"
    )
    owner = try snapshot.remindersV3Ref("owner", operation: "decode Reminders V3 list")
    readers = snapshot.remindersV3Refs("readers")
    writers = snapshot.remindersV3Refs("writers")
    reminders = try snapshot.remindersV3Linked("reminders").map {
      try RemindersV3Reminder(snapshot: InstantEntitySnapshot($0))
    }
    share = try snapshot.remindersV3Linked("share").first.map {
      try RemindersV3Share(snapshot: InstantEntitySnapshot($0))
    }
  }

  public static func visible(to userID: InstantID<RemindersV3User>) -> InstantQuery<Self> {
    let membershipQuery = RemindersV3ShareMembership.query
      .include(RemindersV3ShareMembership.user)
    let shareQuery = RemindersV3Share.query
      .include(RemindersV3Share.owner)
      .include(RemindersV3Share.memberships, membershipQuery)
    let reminderQuery = RemindersV3Reminder.query
      .include(RemindersV3Reminder.tags)
      .order(RemindersV3Reminder.position)
    return query
      .where(.any(owner == userID, readers == userID, writers == userID))
      .include(owner)
      .include(readers)
      .include(writers)
      .include(reminders, reminderQuery)
      .include(share, shareQuery)
      .order(position)
  }

  public static func byID(
    _ listID: InstantID<Self>,
    visibleTo userID: InstantID<RemindersV3User>
  ) -> InstantQuery<Self> {
    visible(to: userID).where(identifier == listID.rawValue)
  }
}

extension RemindersV3List {
  public func isOwned(by userID: InstantID<RemindersV3User>) -> Bool {
    owner == userID
  }

  public func canWrite(as userID: InstantID<RemindersV3User>) -> Bool {
    isOwned(by: userID) || writers.contains(userID)
  }
}

@InstantEntity("reminders")
public struct RemindersV3Reminder: Codable, Hashable, InstantEntityModel {
  public static let title = InstantAttributePath<Self, String>("title")
  public static let notes = InstantAttributePath<Self, String>("notes")
  public static let isCompleted = InstantAttributePath<Self, Bool>("isCompleted")
  public static let isFlagged = InstantAttributePath<Self, Bool>("isFlagged")
  public static let dueDate = InstantAttributePath<Self, Date?>("dueDate")
  public static let priority = InstantAttributePath<Self, RemindersV3Priority?>("priority")
  public static let position = InstantAttributePath<Self, Int>("position")
  public static let createdAt = InstantAttributePath<Self, Date>("createdAt")
  public static let list = InstantAttributePath<Self, InstantID<RemindersV3List>>("list")
  public static let tags = InstantAttributePath<Self, InstantID<RemindersV3Tag>>("tags")
  public static let instantAttributes = RemindersV3Schema.attributes.filter {
    $0.namespace == instantNamespace
  }

  public var id: InstantID<Self>
  public var title: String
  public var notes: String
  public var isCompleted: Bool
  public var isFlagged: Bool
  public var dueDate: Date?
  @InstantWire(.number)
  public var priority: RemindersV3Priority?
  public var position: Int
  public var createdAt: Date
  public var list: InstantID<RemindersV3List>
  public var tags: [RemindersV3Tag]

  public init(
    id: InstantID<Self>,
    title: String,
    notes: String,
    isCompleted: Bool,
    isFlagged: Bool,
    dueDate: Date? = nil,
    priority: RemindersV3Priority? = nil,
    position: Int,
    createdAt: Date,
    list: InstantID<RemindersV3List>,
    tags: [RemindersV3Tag] = []
  ) {
    self.id = id
    self.title = title
    self.notes = notes
    self.isCompleted = isCompleted
    self.isFlagged = isFlagged
    self.dueDate = dueDate
    self.priority = priority
    self.position = position
    self.createdAt = createdAt
    self.list = list
    self.tags = tags
  }

  public init(snapshot: InstantEntitySnapshot) throws {
    id = InstantID(rawValue: snapshot.id)
    title = try snapshot.remindersV3String("title", operation: "decode Reminders V3 reminder")
    notes = try snapshot.remindersV3String("notes", operation: "decode Reminders V3 reminder")
    isCompleted = try snapshot.remindersV3Boolean(
      "isCompleted",
      operation: "decode Reminders V3 reminder"
    )
    isFlagged = try snapshot.remindersV3Boolean(
      "isFlagged",
      operation: "decode Reminders V3 reminder"
    )
    dueDate = try snapshot.remindersV3OptionalDate(
      "dueDate",
      operation: "decode Reminders V3 reminder"
    )
    priority = try snapshot.remindersV3OptionalInteger(
      "priority",
      operation: "decode Reminders V3 reminder"
    ).flatMap(RemindersV3Priority.init(rawValue:))
    position = try snapshot.remindersV3Integer(
      "position",
      operation: "decode Reminders V3 reminder"
    )
    createdAt = try snapshot.remindersV3Date(
      "createdAt",
      operation: "decode Reminders V3 reminder"
    )
    list = try snapshot.remindersV3Ref(
      "list",
      operation: "decode Reminders V3 reminder"
    )
    tags = try snapshot.remindersV3Linked("tags").map {
      try RemindersV3Tag(snapshot: InstantEntitySnapshot($0))
    }
  }

  public static func forList(
    _ listID: InstantID<RemindersV3List>,
    includeCompleted: Bool = false
  ) -> InstantQuery<Self> {
    var query = query
      .where(list == listID)
      .include(tags)
      .order(position)
    if !includeCompleted {
      query = query.where(isCompleted == false)
    }
    return query
  }
}

@InstantEntity("tags")
public struct RemindersV3Tag: Codable, Hashable, InstantEntityModel {
  public static let title = InstantAttributePath<Self, String>("title")
  public static let instantAttributes = RemindersV3Schema.attributes.filter {
    $0.namespace == instantNamespace
  }

  public var id: InstantID<Self>
  public var title: String

  public init(id: InstantID<Self>, title: String) {
    self.id = id
    self.title = title
  }

  public init(snapshot: InstantEntitySnapshot) throws {
    id = InstantID(rawValue: snapshot.id)
    title = try snapshot.remindersV3String("title", operation: "decode Reminders V3 tag")
  }
}

@InstantEntity("v3_shares")
public struct RemindersV3Share: Codable, Hashable, InstantEntityModel {
  public static let token = InstantAttributePath<Self, String>("token")
  public static let rootNamespace = InstantAttributePath<Self, String>("rootNamespace")
  public static let rootID = InstantAttributePath<Self, String>("rootID")
  public static let createdAt = InstantAttributePath<Self, Date>("createdAt")
  public static let updatedAt = InstantAttributePath<Self, Date>("updatedAt")
  public static let revokedAt = InstantAttributePath<Self, Date?>("revokedAt")
  public static let owner = InstantAttributePath<Self, InstantID<RemindersV3User>>("owner")
  public static let root = InstantAttributePath<Self, InstantID<RemindersV3List>>("root")
  public static let memberships = InstantReverseRelation<Self, RemindersV3ShareMembership>(
    attribute: RemindersV3ShareMembership.share
  )
  public static let instantAttributes = RemindersV3Schema.attributes.filter {
    $0.namespace == instantNamespace
  }

  public var id: InstantID<Self>
  public var token: String
  public var rootNamespace: String
  public var rootID: String
  public var createdAt: Date
  public var updatedAt: Date
  public var revokedAt: Date?
  public var owner: InstantID<RemindersV3User>
  public var root: InstantID<RemindersV3List>
  public var memberships: [RemindersV3ShareMembership]

  public init(snapshot: InstantEntitySnapshot) throws {
    id = InstantID(rawValue: snapshot.id)
    token = try snapshot.remindersV3String("token", operation: "decode Reminders V3 share")
    rootNamespace = try snapshot.remindersV3String(
      "rootNamespace",
      operation: "decode Reminders V3 share"
    )
    rootID = try snapshot.remindersV3String("rootID", operation: "decode Reminders V3 share")
    createdAt = try snapshot.remindersV3Date(
      "createdAt",
      operation: "decode Reminders V3 share"
    )
    updatedAt = try snapshot.remindersV3Date(
      "updatedAt",
      operation: "decode Reminders V3 share"
    )
    revokedAt = try snapshot.remindersV3OptionalDate(
      "revokedAt",
      operation: "decode Reminders V3 share"
    )
    owner = try snapshot.remindersV3Ref("owner", operation: "decode Reminders V3 share")
    root = try snapshot.remindersV3Ref("root", operation: "decode Reminders V3 share")
    memberships = try snapshot.remindersV3Linked("memberships").map {
      try RemindersV3ShareMembership(snapshot: InstantEntitySnapshot($0))
    }
  }
}

@InstantEntity("v3_share_memberships")
public struct RemindersV3ShareMembership: Codable, Hashable, InstantEntityModel {
  public static let role = InstantAttributePath<Self, String>("role")
  public static let acceptedAt = InstantAttributePath<Self, Date>("acceptedAt")
  public static let revokedAt = InstantAttributePath<Self, Date?>("revokedAt")
  public static let share = InstantAttributePath<Self, InstantID<RemindersV3Share>>("share")
  public static let user = InstantAttributePath<Self, InstantID<RemindersV3User>>("user")
  public static let instantAttributes = RemindersV3Schema.attributes.filter {
    $0.namespace == instantNamespace
  }

  public var id: InstantID<Self>
  public var role: String
  public var acceptedAt: Date
  public var revokedAt: Date?
  public var share: InstantID<RemindersV3Share>
  public var user: InstantID<RemindersV3User>

  public init(snapshot: InstantEntitySnapshot) throws {
    id = InstantID(rawValue: snapshot.id)
    role = try snapshot.remindersV3String(
      "role",
      operation: "decode Reminders V3 share membership"
    )
    acceptedAt = try snapshot.remindersV3Date(
      "acceptedAt",
      operation: "decode Reminders V3 share membership"
    )
    revokedAt = try snapshot.remindersV3OptionalDate(
      "revokedAt",
      operation: "decode Reminders V3 share membership"
    )
    share = try snapshot.remindersV3Ref(
      "share",
      operation: "decode Reminders V3 share membership"
    )
    user = try snapshot.remindersV3Ref(
      "user",
      operation: "decode Reminders V3 share membership"
    )
  }

  public var shareRole: InstantShareRole? {
    InstantShareRole(rawValue: role)
  }
}

extension InstantEntitySnapshot {
  fileprivate init(_ linked: InstantLinkedEntitySnapshot) {
    self.init(
      id: linked.id,
      namespace: linked.namespace,
      values: linked.values,
      links: linked.links
    )
  }

  fileprivate func remindersV3Linked(_ name: String) -> [InstantLinkedEntitySnapshot] {
    links?[name] ?? []
  }

  fileprivate func remindersV3String(_ path: String, operation: String) throws -> String {
    guard case let .string(value) = values[path]?.first else {
      throw remindersV3DecodeError(self, path: path, operation: operation, expected: "a string")
    }
    return value
  }

  fileprivate func remindersV3OptionalString(
    _ path: String,
    operation: String
  ) throws -> String? {
    guard let value = values[path]?.first, value != .null else { return nil }
    guard case let .string(string) = value else {
      throw remindersV3DecodeError(
        self,
        path: path,
        operation: operation,
        expected: "a string or null"
      )
    }
    return string
  }

  fileprivate func remindersV3Boolean(_ path: String, operation: String) throws -> Bool {
    guard case let .bool(value) = values[path]?.first else {
      throw remindersV3DecodeError(self, path: path, operation: operation, expected: "a boolean")
    }
    return value
  }

  fileprivate func remindersV3Integer(_ path: String, operation: String) throws -> Int {
    guard case let .number(value) = values[path]?.first, value.rounded() == value else {
      throw remindersV3DecodeError(self, path: path, operation: operation, expected: "an integer")
    }
    return Int(value)
  }

  fileprivate func remindersV3OptionalInteger(
    _ path: String,
    operation: String
  ) throws -> Int? {
    guard let value = values[path]?.first, value != .null else { return nil }
    guard case let .number(number) = value, number.rounded() == number else {
      throw remindersV3DecodeError(
        self,
        path: path,
        operation: operation,
        expected: "an integer or null"
      )
    }
    return Int(number)
  }

  fileprivate func remindersV3Date(_ path: String, operation: String) throws -> Date {
    guard case let .date(value) = values[path]?.first else {
      throw remindersV3DecodeError(self, path: path, operation: operation, expected: "a date")
    }
    return value
  }

  fileprivate func remindersV3OptionalDate(_ path: String, operation: String) throws -> Date? {
    guard let value = values[path]?.first, value != .null else { return nil }
    guard case let .date(date) = value else {
      throw remindersV3DecodeError(
        self,
        path: path,
        operation: operation,
        expected: "a date or null"
      )
    }
    return date
  }

  fileprivate func remindersV3Ref<Entity>(
    _ path: String,
    operation: String
  ) throws -> InstantID<Entity> {
    guard case let .ref(value) = values[path]?.first else {
      throw remindersV3DecodeError(
        self,
        path: path,
        operation: operation,
        expected: "an entity reference"
      )
    }
    return InstantID(rawValue: value)
  }

  fileprivate func remindersV3Refs<Entity>(_ path: String) -> [InstantID<Entity>] {
    (values[path]?.values ?? []).compactMap { value in
      guard case let .ref(id) = value else { return nil }
      return InstantID(rawValue: id)
    }
  }
}

private func remindersV3DecodeError(
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
    message: "Expected \(expected), received \(String(describing: snapshot.values[path]?.first)).",
    recovery: "Keep the Reminders V3 app model aligned with its generated schema."
  )
}
