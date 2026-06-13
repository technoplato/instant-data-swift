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
  case lookupRef(InstantLookupRef)
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
    case let .lookupRef(lookup):
      return "7:\(lookup.attributeID)=\(lookup.value.comparableKey)"
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

public enum InstantLookupValue: Hashable, Codable, Sendable {
  case null
  case string(String)
  case number(Double)
  case bool(Bool)
  case date(Date)
  case json(JSONValue)
  case ref(String)
}

extension InstantLookupValue {
  public init(_ value: InstantValue) {
    switch value {
    case .null:
      self = .null
    case let .bool(value):
      self = .bool(value)
    case let .number(value):
      self = .number(value)
    case let .string(value):
      self = .string(value)
    case let .date(value):
      self = .date(value)
    case let .json(value):
      self = .json(value)
    case let .ref(value):
      self = .ref(value)
    case .lookupRef:
      preconditionFailure("Instant lookup values cannot contain nested lookup refs.")
    }
  }

  public var instantValue: InstantValue {
    switch self {
    case .null:
      return .null
    case let .bool(value):
      return .bool(value)
    case let .number(value):
      return .number(value)
    case let .string(value):
      return .string(value)
    case let .date(value):
      return .date(value)
    case let .json(value):
      return .json(value)
    case let .ref(value):
      return .ref(value)
    }
  }

  public var comparableKey: String {
    instantValue.comparableKey
  }
}

public struct InstantLookupRef: Hashable, Codable, Sendable, CustomStringConvertible {
  public var attributeID: String
  public var value: InstantLookupValue

  public init(attributeID: String, value: InstantLookupValue) {
    self.attributeID = attributeID
    self.value = value
  }

  public var description: String {
    "\(attributeID)=\(value.comparableKey)"
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
  public static func primaryKey(namespace: String) -> Self {
    Self(
      id: primaryKeyID(namespace: namespace),
      namespace: namespace,
      name: "id",
      valueType: .string,
      isIndexed: true,
      isUnique: true,
      primaryKey: true
    )
  }

  public static func primaryKeyID(namespace: String) -> String {
    "\(namespace)/id"
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
  case requireEntityMissing(entityID: String, namespace: String?)
  case requireEntityMissingByLookup(InstantLookupRef, namespace: String?)
  case requireEntityExists(entityID: String, namespace: String?)
  case requireEntityExistsByLookup(InstantLookupRef, namespace: String?)
  case merge(InstantTriple)
  case mergeByLookup(
    entity: InstantLookupRef,
    attributeID: String,
    value: InstantValue,
    txID: String,
    txTime: InstantTimestamp
  )
  case insert(InstantTriple)
  case insertByLookup(
    entity: InstantLookupRef,
    attributeID: String,
    value: InstantValue,
    txID: String,
    txTime: InstantTimestamp
  )
  case retract(InstantTriple)
  case retractByLookup(
    entity: InstantLookupRef,
    attributeID: String,
    value: InstantValue,
    txID: String,
    txTime: InstantTimestamp
  )
  case deleteEntity(String)
  case deleteEntityByLookup(InstantLookupRef)
  case ruleParams(entityID: String, namespace: String, params: JSONValue)
  case ruleParamsByLookup(entity: InstantLookupRef, namespace: String, params: JSONValue)
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

  static func creationOrder(_ lhs: Self, _ rhs: Self) -> Bool {
    if lhs.createdAt == rhs.createdAt {
      return lhs.id < rhs.id
    }
    return lhs.createdAt < rhs.createdAt
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

public struct InstantMagicCodeChallenge: Hashable, Codable, Sendable, Identifiable {
  public var id: String { "\(appID):\(email)" }
  public var appID: String
  public var email: String
  public var code: String
  public var createdAt: InstantTimestamp
  public var expiresAt: InstantTimestamp

  public init(
    appID: String,
    email: String,
    code: String,
    createdAt: InstantTimestamp,
    expiresAt: InstantTimestamp
  ) {
    self.appID = appID
    self.email = email
    self.code = code
    self.createdAt = createdAt
    self.expiresAt = expiresAt
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

public struct InstantQueryCursor: Hashable, Codable, Sendable {
  public var entityID: String
  public var sortValue: InstantValue?
  public var inclusive: Bool

  public init(entityID: String, sortValue: InstantValue? = nil, inclusive: Bool = false) {
    precondition(
      !entityID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      "InstantQueryCursor entityID must not be empty."
    )
    self.entityID = entityID
    self.sortValue = sortValue
    self.inclusive = inclusive
  }
}

public struct InstantQueryPageInfo: Hashable, Codable, Sendable {
  public var startCursor: InstantQueryCursor?
  public var endCursor: InstantQueryCursor?
  public var hasPreviousPage: Bool
  public var hasNextPage: Bool

  public init(
    startCursor: InstantQueryCursor?,
    endCursor: InstantQueryCursor?,
    hasPreviousPage: Bool,
    hasNextPage: Bool
  ) {
    self.startCursor = startCursor
    self.endCursor = endCursor
    self.hasPreviousPage = hasPreviousPage
    self.hasNextPage = hasNextPage
  }
}

public enum InstantQueryIncludeDirection: String, Codable, Sendable {
  case forward
  case reverse
}

public struct InstantQueryIncludePlan: Hashable, Codable, Sendable, Identifiable {
  public var id: String
  public var namespace: String
  public var filters: [InstantQueryFilter]
  public var order: InstantQueryOrder?
  public var selectedFields: [String]?

  public init(
    id: String,
    namespace: String,
    filters: [InstantQueryFilter] = [],
    order: InstantQueryOrder? = nil,
    selectedFields: [String]? = nil
  ) {
    precondition(
      selectedFields?.allSatisfy { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        ?? true,
      "InstantQueryIncludePlan selected fields must not be empty strings."
    )
    self.id = id
    self.namespace = namespace
    self.filters = filters
    self.order = order
    self.selectedFields = selectedFields.map { Array(Set($0)).sorted() }
  }
}

public struct InstantQueryInclude: Hashable, Codable, Sendable {
  public var name: String
  public var direction: InstantQueryIncludeDirection
  public var query: InstantQueryIncludePlan?

  public init(
    _ name: String,
    direction: InstantQueryIncludeDirection = .forward,
    query: InstantQueryIncludePlan? = nil
  ) {
    precondition(
      !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      "InstantQueryInclude name must not be empty."
    )
    self.name = name
    self.direction = direction
    self.query = query
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
  public var first: Int?
  public var after: InstantQueryCursor?
  public var last: Int?
  public var before: InstantQueryCursor?
  public var selectedFields: [String]?
  public var includes: [InstantQueryInclude]?

  public var cacheKey: String {
    Self.cacheKey(for: self)
  }

  public init(
    id: String,
    namespace: String,
    filters: [InstantQueryFilter] = [],
    order: InstantQueryOrder? = nil,
    offset: Int? = nil,
    limit: Int? = nil,
    first: Int? = nil,
    after: InstantQueryCursor? = nil,
    last: Int? = nil,
    before: InstantQueryCursor? = nil,
    selectedFields: [String]? = nil,
    includes: [InstantQueryInclude] = []
  ) {
    precondition(
      offset == nil || offset! >= 0,
      "InstantQueryPlan offset must be greater than or equal to 0."
    )
    precondition(
      limit == nil || limit! >= 0,
      "InstantQueryPlan limit must be greater than or equal to 0."
    )
    precondition(
      first == nil || first! >= 0,
      "InstantQueryPlan first must be greater than or equal to 0."
    )
    precondition(
      last == nil || last! >= 0,
      "InstantQueryPlan last must be greater than or equal to 0."
    )
    precondition(
      selectedFields?.allSatisfy { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        ?? true,
      "InstantQueryPlan selected fields must not be empty strings."
    )
    self.id = id
    self.namespace = namespace
    self.filters = filters
    self.order = order
    self.offset = offset
    self.limit = limit
    self.first = first
    self.after = after
    self.last = last
    self.before = before
    self.selectedFields = selectedFields.map { Array(Set($0)).sorted() }
    self.includes = includes.isEmpty ? nil : includes
  }

  public static func cacheKey(for plan: Self) -> String {
    let data = Data(plan.canonicalCacheKeyPayload.utf8)
    return "plan:\(data.base64EncodedString())"
  }
}

public extension InstantQueryInclude {
  init?(
    _ name: String,
    direction: InstantQueryIncludeDirection = .forward,
    query: InstantQueryPlan
  ) {
    guard query.isSupportedIncludeQuery else { return nil }
    self.init(name, direction: direction, query: InstantQueryIncludePlan(query))
  }
}

extension InstantQueryIncludePlan {
  init(_ plan: InstantQueryPlan) {
    self.init(
      id: plan.id,
      namespace: plan.namespace,
      filters: plan.filters,
      order: plan.order,
      selectedFields: plan.selectedFields
    )
  }

  var queryPlan: InstantQueryPlan {
    InstantQueryPlan(
      id: id,
      namespace: namespace,
      filters: filters,
      order: order,
      selectedFields: selectedFields
    )
  }
}

private extension InstantQueryPlan {
  var isSupportedIncludeQuery: Bool {
    offset == nil
      && limit == nil
      && first == nil
      && after == nil
      && last == nil
      && before == nil
      && (includes == nil || includes?.isEmpty == true)
  }
}

private extension InstantQueryPlan {
  var canonicalCacheKeyPayload: String {
    [
      "id:\(id.cacheKeyEncodedString)",
      "namespace:\(namespace.cacheKeyEncodedString)",
      "filters:[\(filters.map(\.canonicalCacheKeyPayload).joined(separator: ","))]",
      "order:\(order?.canonicalCacheKeyPayload ?? "nil")",
      "offset:\(offset.map(String.init) ?? "nil")",
      "limit:\(limit.map(String.init) ?? "nil")",
      "first:\(first.map(String.init) ?? "nil")",
      "after:\(after?.canonicalCacheKeyPayload ?? "nil")",
      "last:\(last.map(String.init) ?? "nil")",
      "before:\(before?.canonicalCacheKeyPayload ?? "nil")",
      "selectedFields:\(selectedFields.map { $0.joined(separator: ",").cacheKeyEncodedString } ?? "nil")",
      "includes:[\((includes ?? []).map(\.canonicalCacheKeyPayload).joined(separator: ","))]",
    ]
    .joined(separator: "|")
  }
}

private extension InstantQueryOrder {
  var canonicalCacheKeyPayload: String {
    "field:\(field.cacheKeyEncodedString)|direction:\(direction.rawValue)"
  }
}

private extension InstantQueryIncludePlan {
  var canonicalCacheKeyPayload: String {
    [
      "id:\(id.cacheKeyEncodedString)",
      "namespace:\(namespace.cacheKeyEncodedString)",
      "filters:[\(filters.map(\.canonicalCacheKeyPayload).joined(separator: ","))]",
      "order:\(order?.canonicalCacheKeyPayload ?? "nil")",
      "selectedFields:\(selectedFields.map { $0.joined(separator: ",").cacheKeyEncodedString } ?? "nil")",
    ]
    .joined(separator: "|")
  }
}

private extension InstantQueryInclude {
  var canonicalCacheKeyPayload: String {
    [
      "name:\(name.cacheKeyEncodedString)",
      "direction:\(direction.rawValue)",
      "query:\(query?.canonicalCacheKeyPayload ?? "nil")",
    ]
    .joined(separator: "|")
  }
}

private extension InstantQueryCursor {
  var canonicalCacheKeyPayload: String {
    [
      "entityID:\(entityID.cacheKeyEncodedString)",
      "sortValue:\(sortValue?.canonicalCacheKeyPayload ?? "nil")",
      "inclusive:\(inclusive)",
    ]
    .joined(separator: "|")
  }
}

private extension InstantQueryFilter {
  var canonicalCacheKeyPayload: String {
    switch self {
    case let .equals(field, value):
      return "equals(\(field.cacheKeyEncodedString),\(value.canonicalCacheKeyPayload))"
    case let .notEquals(field, value):
      return "notEquals(\(field.cacheKeyEncodedString),\(value.canonicalCacheKeyPayload))"
    case let .greaterThan(field, value):
      return "greaterThan(\(field.cacheKeyEncodedString),\(value.canonicalCacheKeyPayload))"
    case let .greaterThanOrEqual(field, value):
      return "greaterThanOrEqual(\(field.cacheKeyEncodedString),\(value.canonicalCacheKeyPayload))"
    case let .lessThan(field, value):
      return "lessThan(\(field.cacheKeyEncodedString),\(value.canonicalCacheKeyPayload))"
    case let .lessThanOrEqual(field, value):
      return "lessThanOrEqual(\(field.cacheKeyEncodedString),\(value.canonicalCacheKeyPayload))"
    case let .in(field, values):
      return
        "in(\(field.cacheKeyEncodedString),[\(values.map(\.canonicalCacheKeyPayload).joined(separator: ","))])"
    case let .like(field, pattern):
      return "like(\(field.cacheKeyEncodedString),\(pattern.cacheKeyEncodedString))"
    case let .iLike(field, pattern):
      return "iLike(\(field.cacheKeyEncodedString),\(pattern.cacheKeyEncodedString))"
    case let .isNull(field):
      return "isNull(\(field.cacheKeyEncodedString))"
    case let .isNotNull(field):
      return "isNotNull(\(field.cacheKeyEncodedString))"
    case let .and(filters):
      return "and(\(filters.map(\.canonicalCacheKeyPayload).joined(separator: ",")))"
    case let .or(filters):
      return "or(\(filters.map(\.canonicalCacheKeyPayload).joined(separator: ",")))"
    }
  }
}

private extension InstantValue {
  var canonicalCacheKeyPayload: String {
    switch self {
    case .null:
      return "null"
    case let .string(value):
      return "string:\(value.cacheKeyEncodedString)"
    case let .number(value):
      return "number:\(value.bitPattern)"
    case let .bool(value):
      return "bool:\(value)"
    case let .date(value):
      return "date:\(value.timeIntervalSinceReferenceDate.bitPattern)"
    case let .json(value):
      return "json:\(value.canonicalCacheKeyPayload)"
    case let .ref(value):
      return "ref:\(value.cacheKeyEncodedString)"
    case let .lookupRef(lookup):
      return "lookupRef:\(lookup.attributeID.cacheKeyEncodedString)=\(lookup.value.canonicalCacheKeyPayload)"
    }
  }
}

private extension InstantLookupValue {
  var canonicalCacheKeyPayload: String {
    switch self {
    case .null:
      return "null"
    case let .string(value):
      return "string:\(value.cacheKeyEncodedString)"
    case let .number(value):
      return "number:\(value.bitPattern)"
    case let .bool(value):
      return "bool:\(value)"
    case let .date(value):
      return "date:\(value.timeIntervalSinceReferenceDate.bitPattern)"
    case let .json(value):
      return "json:\(value.canonicalCacheKeyPayload)"
    case let .ref(value):
      return "ref:\(value.cacheKeyEncodedString)"
    }
  }
}

private extension JSONValue {
  var canonicalCacheKeyPayload: String {
    switch self {
    case .null:
      return "null"
    case let .bool(value):
      return "bool:\(value)"
    case let .number(value):
      return "number:\(value.bitPattern)"
    case let .string(value):
      return "string:\(value.cacheKeyEncodedString)"
    case let .array(values):
      return "array:[\(values.map(\.canonicalCacheKeyPayload).joined(separator: ","))]"
    case let .object(fields):
      let payload = fields.keys.sorted().map { key in
        "\(key.cacheKeyEncodedString):\(fields[key]?.canonicalCacheKeyPayload ?? "nil")"
      }
      .joined(separator: ",")
      return "object:{\(payload)}"
    }
  }
}

private extension String {
  var cacheKeyEncodedString: String {
    Data(utf8).base64EncodedString()
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

public struct InstantLinkedEntitySnapshot: Hashable, Codable, Sendable, Identifiable {
  public var id: String
  public var namespace: String
  public var values: [String: InstantMaterializedValue]

  public init(id: String, namespace: String, values: [String: InstantMaterializedValue]) {
    self.id = id
    self.namespace = namespace
    self.values = values
  }

  public init(_ snapshot: InstantEntitySnapshot) {
    self.init(id: snapshot.id, namespace: snapshot.namespace, values: snapshot.values)
  }
}

public struct InstantEntitySnapshot: Hashable, Codable, Sendable, Identifiable {
  public var id: String
  public var namespace: String
  public var values: [String: InstantMaterializedValue]
  public var links: [String: [InstantLinkedEntitySnapshot]]?

  public init(id: String, namespace: String, values: [String: InstantMaterializedValue]) {
    self.id = id
    self.namespace = namespace
    self.values = values
    self.links = nil
  }

  public init(
    id: String,
    namespace: String,
    values: [String: InstantMaterializedValue],
    links: [String: [InstantLinkedEntitySnapshot]]?
  ) {
    self.id = id
    self.namespace = namespace
    self.values = values
    self.links = links
  }
}

public struct InstantQueryPage: Hashable, Codable, Sendable {
  public var values: [InstantEntitySnapshot]
  public var pageInfo: InstantQueryPageInfo?

  public init(values: [InstantEntitySnapshot], pageInfo: InstantQueryPageInfo? = nil) {
    self.values = values
    self.pageInfo = pageInfo
  }
}

public struct InstantQueryEmission: Hashable, Codable, Sendable {
  public var queryID: String
  public var sequence: Int64
  public var values: [InstantEntitySnapshot]
  public var pageInfo: InstantQueryPageInfo?

  public init(
    queryID: String,
    sequence: Int64,
    values: [InstantEntitySnapshot],
    pageInfo: InstantQueryPageInfo? = nil
  ) {
    self.queryID = queryID
    self.sequence = sequence
    self.values = values
    self.pageInfo = pageInfo
  }
}

public struct InstantCachedQuery: Hashable, Codable, Sendable, Identifiable {
  public var id: String { cacheKey }
  public var cacheKey: String
  public var queryID: String
  public var plan: InstantQueryPlan
  public var emission: InstantQueryEmission
  public var updatedAt: InstantTimestamp
  public var storeRevision: Int64

  public init(
    cacheKey: String? = nil,
    queryID: String,
    plan: InstantQueryPlan,
    emission: InstantQueryEmission,
    updatedAt: InstantTimestamp,
    storeRevision: Int64
  ) {
    self.cacheKey = cacheKey ?? plan.cacheKey
    self.queryID = queryID
    self.plan = plan
    self.emission = emission
    self.updatedAt = updatedAt
    self.storeRevision = storeRevision
  }

  private enum CodingKeys: String, CodingKey {
    case cacheKey
    case queryID
    case plan
    case emission
    case updatedAt
    case storeRevision
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let plan = try container.decode(InstantQueryPlan.self, forKey: .plan)
    self.init(
      cacheKey: try container.decodeIfPresent(String.self, forKey: .cacheKey) ?? plan.cacheKey,
      queryID: try container.decode(String.self, forKey: .queryID),
      plan: plan,
      emission: try container.decode(InstantQueryEmission.self, forKey: .emission),
      updatedAt: try container.decode(InstantTimestamp.self, forKey: .updatedAt),
      storeRevision: try container.decodeIfPresent(Int64.self, forKey: .storeRevision) ?? 0
    )
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(cacheKey, forKey: .cacheKey)
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
