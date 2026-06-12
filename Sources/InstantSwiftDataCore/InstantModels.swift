import Foundation

public struct InstantID<Entity>: Hashable, Codable, Sendable, CustomStringConvertible {
  public var rawValue: String

  public init(rawValue: String) {
    self.rawValue = rawValue
  }

  public var description: String {
    rawValue
  }
}

public struct AnyInstantID: Hashable, Codable, Sendable, CustomStringConvertible {
  public var rawValue: String

  public init(_ rawValue: String) {
    self.rawValue = rawValue
  }

  public var description: String {
    rawValue
  }
}

public struct InstantTimestamp: Hashable, Codable, Comparable, Sendable {
  public var milliseconds: Int64

  public init(milliseconds: Int64) {
    self.milliseconds = milliseconds
  }

  public static func < (lhs: Self, rhs: Self) -> Bool {
    lhs.milliseconds < rhs.milliseconds
  }
}

public indirect enum JSONValue: Hashable, Codable, Sendable {
  case null
  case bool(Bool)
  case number(Double)
  case string(String)
  case array([JSONValue])
  case object([String: JSONValue])
}

public enum InstantValue: Hashable, Codable, Sendable {
  case null
  case string(String)
  case number(Double)
  case bool(Bool)
  case date(Date)
  case json(JSONValue)
  case ref(String)
}

extension InstantValue {
  public var refValue: String? {
    guard case let .ref(value) = self else { return nil }
    return value
  }

  public var comparableKey: String {
    switch self {
    case .null:
      return "0:null"
    case let .bool(value):
      return "1:\(value ? 1 : 0)"
    case let .number(value):
      return "2:\(value)"
    case let .string(value):
      return "3:\(value)"
    case let .date(value):
      return "4:\(value.timeIntervalSince1970)"
    case let .ref(value):
      return "5:\(value)"
    case let .json(value):
      return "6:\(String(describing: value))"
    }
  }

  public func compare(to other: InstantValue) -> ComparisonResult {
    switch (self, other) {
    case (.null, .null):
      return .orderedSame
    case let (.bool(lhs), .bool(rhs)):
      return lhs == rhs ? .orderedSame : (lhs == false ? .orderedAscending : .orderedDescending)
    case let (.number(lhs), .number(rhs)):
      return lhs == rhs ? .orderedSame : (lhs < rhs ? .orderedAscending : .orderedDescending)
    case let (.string(lhs), .string(rhs)):
      return lhs.compare(rhs)
    case let (.date(lhs), .date(rhs)):
      return lhs == rhs ? .orderedSame : (lhs < rhs ? .orderedAscending : .orderedDescending)
    case let (.ref(lhs), .ref(rhs)):
      return lhs.compare(rhs)
    default:
      return comparableKey.compare(other.comparableKey)
    }
  }
}

public enum InstantValueType: String, Codable, Sendable {
  case string
  case number
  case boolean
  case date
  case json
  case ref
}

public enum InstantCardinality: String, Codable, Sendable {
  case one
  case many
}

public enum InstantDeleteRule: String, Codable, Sendable {
  case none
  case cascade
}

public struct InstantAttribute: Hashable, Codable, Sendable, Identifiable {
  public var id: String
  public var namespace: String
  public var name: String
  public var valueType: InstantValueType
  public var isRequired: Bool
  public var cardinality: InstantCardinality
  public var isIndexed: Bool
  public var isUnique: Bool
  public var forwardIdentity: String?
  public var reverseIdentity: String?
  public var primaryKey: Bool
  public var linkNamespace: String?
  public var onDelete: InstantDeleteRule
  public var onDeleteReverse: InstantDeleteRule

  public init(
    id: String,
    namespace: String,
    name: String,
    valueType: InstantValueType,
    isRequired: Bool = true,
    cardinality: InstantCardinality = .one,
    isIndexed: Bool = false,
    isUnique: Bool = false,
    forwardIdentity: String? = nil,
    reverseIdentity: String? = nil,
    primaryKey: Bool = false,
    linkNamespace: String? = nil,
    onDelete: InstantDeleteRule = .none,
    onDeleteReverse: InstantDeleteRule = .none
  ) {
    self.id = id
    self.namespace = namespace
    self.name = name
    self.valueType = valueType
    self.isRequired = isRequired
    self.cardinality = cardinality
    self.isIndexed = isIndexed
    self.isUnique = isUnique
    self.forwardIdentity = forwardIdentity
    self.reverseIdentity = reverseIdentity
    self.primaryKey = primaryKey
    self.linkNamespace = linkNamespace
    self.onDelete = onDelete
    self.onDeleteReverse = onDeleteReverse
  }
}

extension InstantAttribute {
  private enum CodingKeys: String, CodingKey {
    case id
    case namespace
    case name
    case valueType
    case isRequired
    case cardinality
    case isIndexed
    case isUnique
    case forwardIdentity
    case reverseIdentity
    case primaryKey
    case linkNamespace
    case onDelete
    case onDeleteReverse
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      id: try container.decode(String.self, forKey: .id),
      namespace: try container.decode(String.self, forKey: .namespace),
      name: try container.decode(String.self, forKey: .name),
      valueType: try container.decode(InstantValueType.self, forKey: .valueType),
      isRequired: try container.decodeIfPresent(Bool.self, forKey: .isRequired) ?? true,
      cardinality: try container.decodeIfPresent(InstantCardinality.self, forKey: .cardinality)
        ?? .one,
      isIndexed: try container.decodeIfPresent(Bool.self, forKey: .isIndexed) ?? false,
      isUnique: try container.decodeIfPresent(Bool.self, forKey: .isUnique) ?? false,
      forwardIdentity: try container.decodeIfPresent(String.self, forKey: .forwardIdentity),
      reverseIdentity: try container.decodeIfPresent(String.self, forKey: .reverseIdentity),
      primaryKey: try container.decodeIfPresent(Bool.self, forKey: .primaryKey) ?? false,
      linkNamespace: try container.decodeIfPresent(String.self, forKey: .linkNamespace),
      onDelete: try container.decodeIfPresent(InstantDeleteRule.self, forKey: .onDelete) ?? .none,
      onDeleteReverse: try container.decodeIfPresent(InstantDeleteRule.self, forKey: .onDeleteReverse)
        ?? .none
    )
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(id, forKey: .id)
    try container.encode(namespace, forKey: .namespace)
    try container.encode(name, forKey: .name)
    try container.encode(valueType, forKey: .valueType)
    try container.encode(isRequired, forKey: .isRequired)
    try container.encode(cardinality, forKey: .cardinality)
    try container.encode(isIndexed, forKey: .isIndexed)
    try container.encode(isUnique, forKey: .isUnique)
    try container.encodeIfPresent(forwardIdentity, forKey: .forwardIdentity)
    try container.encodeIfPresent(reverseIdentity, forKey: .reverseIdentity)
    try container.encode(primaryKey, forKey: .primaryKey)
    try container.encodeIfPresent(linkNamespace, forKey: .linkNamespace)
    try container.encode(onDelete, forKey: .onDelete)
    try container.encode(onDeleteReverse, forKey: .onDeleteReverse)
  }
}

public struct InstantTriple: Hashable, Codable, Sendable {
  public var entityID: String
  public var attributeID: String
  public var value: InstantValue
  public var txID: String
  public var txTime: InstantTimestamp

  public init(
    entityID: String,
    attributeID: String,
    value: InstantValue,
    txID: String,
    txTime: InstantTimestamp
  ) {
    self.entityID = entityID
    self.attributeID = attributeID
    self.value = value
    self.txID = txID
    self.txTime = txTime
  }
}

public enum InstantTripleOperation: Hashable, Codable, Sendable {
  case insert(InstantTriple)
  case retract(InstantTriple)
  case deleteEntity(String)
}

public struct InstantStoreTransaction: Hashable, Codable, Sendable {
  public var id: String
  public var operations: [InstantTripleOperation]

  public init(id: String, operations: [InstantTripleOperation]) {
    self.id = id
    self.operations = operations
  }
}

public enum InstantMutationStatus: String, Codable, Sendable {
  case pending
  case confirmed
  case failed
}

public struct PendingMutation: Hashable, Codable, Sendable, Identifiable {
  public var id: String
  public var createdAt: InstantTimestamp
  public var transaction: InstantStoreTransaction
  public var status: InstantMutationStatus
  public var failureMessage: String?

  public init(
    id: String,
    createdAt: InstantTimestamp,
    transaction: InstantStoreTransaction,
    status: InstantMutationStatus = .pending,
    failureMessage: String? = nil
  ) {
    self.id = id
    self.createdAt = createdAt
    self.transaction = transaction
    self.status = status
    self.failureMessage = failureMessage
  }
}

public struct InstantAuthSession: Hashable, Codable, Sendable, Identifiable {
  public var id: String { userID }
  public var appID: String
  public var userID: String
  public var refreshToken: String?
  public var isGuest: Bool
  public var createdAt: InstantTimestamp
  public var updatedAt: InstantTimestamp

  public init(
    appID: String,
    userID: String,
    refreshToken: String? = nil,
    isGuest: Bool,
    createdAt: InstantTimestamp,
    updatedAt: InstantTimestamp
  ) {
    self.appID = appID
    self.userID = userID
    self.refreshToken = refreshToken
    self.isGuest = isGuest
    self.createdAt = createdAt
    self.updatedAt = updatedAt
  }
}

public struct InstantSyncState: Hashable, Codable, Sendable {
  public var processedTransactionID: String?

  public init(processedTransactionID: String? = nil) {
    self.processedTransactionID = processedTransactionID
  }
}

public enum InstantQuerySortDirection: String, Codable, Sendable {
  case ascending
  case descending
}

public struct InstantQueryOrder: Hashable, Codable, Sendable {
  public var field: String
  public var direction: InstantQuerySortDirection

  public init(_ field: String, _ direction: InstantQuerySortDirection = .ascending) {
    self.field = field
    self.direction = direction
  }
}

public enum InstantQueryFilter: Hashable, Codable, Sendable {
  case equals(field: String, value: InstantValue)
  case notEquals(field: String, value: InstantValue)
  case greaterThan(field: String, value: InstantValue)
  case greaterThanOrEqual(field: String, value: InstantValue)
  case lessThan(field: String, value: InstantValue)
  case lessThanOrEqual(field: String, value: InstantValue)
  case `in`(field: String, values: [InstantValue])
  case like(field: String, pattern: String)
  case iLike(field: String, pattern: String)
  case isNull(field: String)
  case isNotNull(field: String)
  case and([InstantQueryFilter])
  case or([InstantQueryFilter])
}

public struct InstantQueryPlan: Hashable, Codable, Sendable, Identifiable {
  public var id: String
  public var namespace: String
  public var filters: [InstantQueryFilter]
  public var order: InstantQueryOrder?
  public var offset: Int?
  public var limit: Int?

  public init(
    id: String,
    namespace: String,
    filters: [InstantQueryFilter] = [],
    order: InstantQueryOrder? = nil,
    offset: Int? = nil,
    limit: Int? = nil
  ) {
    precondition(
      offset == nil || offset! >= 0,
      "InstantQueryPlan offset must be greater than or equal to 0."
    )
    precondition(
      limit == nil || limit! >= 0,
      "InstantQueryPlan limit must be greater than or equal to 0."
    )
    self.id = id
    self.namespace = namespace
    self.filters = filters
    self.order = order
    self.offset = offset
    self.limit = limit
  }
}

public enum InstantMaterializedValue: Hashable, Codable, Sendable {
  case one(InstantValue)
  case many([InstantValue])

  public var first: InstantValue? {
    switch self {
    case let .one(value):
      return value
    case let .many(values):
      return values.first
    }
  }

  public var values: [InstantValue] {
    switch self {
    case let .one(value):
      return [value]
    case let .many(values):
      return values
    }
  }

  public func contains(_ value: InstantValue) -> Bool {
    switch self {
    case let .one(current):
      return current == value
    case let .many(values):
      return values.contains(value)
    }
  }
}

public struct InstantEntitySnapshot: Hashable, Codable, Sendable, Identifiable {
  public var id: String
  public var namespace: String
  public var values: [String: InstantMaterializedValue]

  public init(id: String, namespace: String, values: [String: InstantMaterializedValue]) {
    self.id = id
    self.namespace = namespace
    self.values = values
  }
}

public struct InstantQueryEmission: Hashable, Codable, Sendable {
  public var queryID: String
  public var sequence: Int64
  public var values: [InstantEntitySnapshot]

  public init(queryID: String, sequence: Int64, values: [InstantEntitySnapshot]) {
    self.queryID = queryID
    self.sequence = sequence
    self.values = values
  }
}

public struct InstantCachedQuery: Hashable, Codable, Sendable, Identifiable {
  public var id: String { queryID }
  public var queryID: String
  public var plan: InstantQueryPlan
  public var emission: InstantQueryEmission
  public var updatedAt: InstantTimestamp
  public var storeRevision: Int64

  public init(
    queryID: String,
    plan: InstantQueryPlan,
    emission: InstantQueryEmission,
    updatedAt: InstantTimestamp,
    storeRevision: Int64
  ) {
    self.queryID = queryID
    self.plan = plan
    self.emission = emission
    self.updatedAt = updatedAt
    self.storeRevision = storeRevision
  }

  private enum CodingKeys: String, CodingKey {
    case queryID
    case plan
    case emission
    case updatedAt
    case storeRevision
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      queryID: try container.decode(String.self, forKey: .queryID),
      plan: try container.decode(InstantQueryPlan.self, forKey: .plan),
      emission: try container.decode(InstantQueryEmission.self, forKey: .emission),
      updatedAt: try container.decode(InstantTimestamp.self, forKey: .updatedAt),
      storeRevision: try container.decodeIfPresent(Int64.self, forKey: .storeRevision) ?? 0
    )
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(queryID, forKey: .queryID)
    try container.encode(plan, forKey: .plan)
    try container.encode(emission, forKey: .emission)
    try container.encode(updatedAt, forKey: .updatedAt)
    try container.encode(storeRevision, forKey: .storeRevision)
  }
}

public struct InstantStoreSnapshot: Hashable, Codable, Sendable {
  public var attributes: [InstantAttribute]
  public var triples: [InstantTriple]

  public init(attributes: [InstantAttribute] = [], triples: [InstantTriple] = []) {
    self.attributes = attributes
    self.triples = triples
  }
}
