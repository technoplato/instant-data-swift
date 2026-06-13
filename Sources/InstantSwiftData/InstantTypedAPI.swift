import Dependencies
import Foundation
import InstantSwiftDataCore

public protocol InstantValueRepresentable: Sendable {
  var instantValue: InstantValue { get }
}

public protocol InstantComparableValue: InstantValueRepresentable {}

extension String: InstantComparableValue {
  public var instantValue: InstantValue { .string(self) }
}

extension Bool: InstantValueRepresentable {
  public var instantValue: InstantValue { .bool(self) }
}

extension Date: InstantComparableValue {
  public var instantValue: InstantValue { .date(self) }
}

extension Double: InstantComparableValue {
  public var instantValue: InstantValue { .number(self) }
}

extension Float: InstantComparableValue {
  public var instantValue: InstantValue { .number(Double(self)) }
}

extension Int: InstantComparableValue {
  public var instantValue: InstantValue { .number(Double(self)) }
}

extension Int64: InstantComparableValue {
  public var instantValue: InstantValue { .number(Double(self)) }
}

extension InstantTimestamp: InstantComparableValue {
  public var instantValue: InstantValue {
    .date(Date(timeIntervalSince1970: Double(milliseconds) / 1000))
  }
}

extension InstantID: InstantValueRepresentable {
  public var instantValue: InstantValue { .ref(rawValue) }
}

extension AnyInstantID: InstantValueRepresentable {
  public var instantValue: InstantValue { .ref(rawValue) }
}

extension JSONValue: InstantValueRepresentable {
  public var instantValue: InstantValue { .json(self) }
}

public protocol InstantEntityModel: Identifiable, Sendable where ID == InstantID<Self> {
  static var instantNamespace: String { get }
  static var instantAttributes: [InstantAttribute] { get }

  init(snapshot: InstantEntitySnapshot) throws
}

extension InstantEntityModel {
  public static var query: InstantEntityQuery<Self> {
    InstantEntityQuery()
  }

  public static func decode(_ snapshots: [InstantEntitySnapshot]) throws -> [Self] {
    try snapshots.map(Self.init(snapshot:))
  }

  public static func create(
    id: ID,
    _ assignments: InstantAttributeAssignment<Self>...
  ) -> InstantMutation {
    create(id: id, assignments)
  }

  public static func create(
    id: ID,
    _ assignments: [InstantAttributeAssignment<Self>]
  ) -> InstantMutation {
    InstantMutation { transactionID, txTime in
      assignments.map { assignment in
        .insert(
          InstantTriple(
            entityID: id.rawValue,
            attributeID: assignment.attributeID,
            value: assignment.value,
            txID: transactionID,
            txTime: txTime
          )
        )
      }
    }
  }

  public static func update(
    id: ID,
    _ assignments: InstantAttributeAssignment<Self>...
  ) -> InstantMutation {
    update(id: id, assignments)
  }

  public static func update(
    id: ID,
    _ assignments: [InstantAttributeAssignment<Self>]
  ) -> InstantMutation {
    create(id: id, assignments)
  }

  public static func delete(id: ID) -> InstantMutation {
    InstantMutation { _, _ in
      [.deleteEntity(id.rawValue)]
    }
  }
}

public struct InstantAttributePath<
  Entity: InstantEntityModel,
  Value: InstantValueRepresentable
>: Hashable, Sendable {
  public var name: String
  public var attributeID: String

  public init(_ name: String, attributeID: String? = nil) {
    self.name = name
    self.attributeID = attributeID ?? "\(Entity.instantNamespace)/\(name)"
  }

  public func set(_ value: Value) -> InstantAttributeAssignment<Entity> {
    InstantAttributeAssignment(
      name: name,
      attributeID: attributeID,
      value: value.instantValue
    )
  }
}

public struct InstantAttributeAssignment<Entity: InstantEntityModel>: Hashable, Sendable {
  public var name: String
  public var attributeID: String
  public var value: InstantValue

  public init(name: String, attributeID: String, value: InstantValue) {
    self.name = name
    self.attributeID = attributeID
    self.value = value
  }
}

public struct InstantPredicate<Entity: InstantEntityModel>: Hashable, Sendable {
  public var filter: InstantQueryFilter

  public init(_ filter: InstantQueryFilter) {
    self.filter = filter
  }
}

extension InstantPredicate {
  public static func all(_ predicates: Self...) -> Self {
    all(predicates)
  }

  public static func all(_ predicates: [Self]) -> Self {
    Self(.and(predicates.map(\.filter)))
  }

  public static func any(_ predicates: Self...) -> Self {
    any(predicates)
  }

  public static func any(_ predicates: [Self]) -> Self {
    Self(.or(predicates.map(\.filter)))
  }
}

public func == <Entity, Value>(
  lhs: InstantAttributePath<Entity, Value>,
  rhs: Value
) -> InstantPredicate<Entity> {
  InstantPredicate(.equals(field: lhs.name, value: rhs.instantValue))
}

public func != <Entity, Value>(
  lhs: InstantAttributePath<Entity, Value>,
  rhs: Value
) -> InstantPredicate<Entity> {
  InstantPredicate(.notEquals(field: lhs.name, value: rhs.instantValue))
}

public func > <Entity, Value: InstantComparableValue>(
  lhs: InstantAttributePath<Entity, Value>,
  rhs: Value
) -> InstantPredicate<Entity> {
  InstantPredicate(.greaterThan(field: lhs.name, value: rhs.instantValue))
}

public func >= <Entity, Value: InstantComparableValue>(
  lhs: InstantAttributePath<Entity, Value>,
  rhs: Value
) -> InstantPredicate<Entity> {
  InstantPredicate(.greaterThanOrEqual(field: lhs.name, value: rhs.instantValue))
}

public func < <Entity, Value: InstantComparableValue>(
  lhs: InstantAttributePath<Entity, Value>,
  rhs: Value
) -> InstantPredicate<Entity> {
  InstantPredicate(.lessThan(field: lhs.name, value: rhs.instantValue))
}

public func <= <Entity, Value: InstantComparableValue>(
  lhs: InstantAttributePath<Entity, Value>,
  rhs: Value
) -> InstantPredicate<Entity> {
  InstantPredicate(.lessThanOrEqual(field: lhs.name, value: rhs.instantValue))
}

extension InstantAttributePath {
  public var isNull: InstantPredicate<Entity> {
    InstantPredicate(.isNull(field: name))
  }

  public var isNotNull: InstantPredicate<Entity> {
    InstantPredicate(.isNotNull(field: name))
  }

  public func isIn(_ values: [Value]) -> InstantPredicate<Entity> {
    InstantPredicate(.in(field: name, values: values.map(\.instantValue)))
  }
}

extension InstantAttributePath where Value == String {
  public func like(_ pattern: String) -> InstantPredicate<Entity> {
    InstantPredicate(.like(field: name, pattern: pattern))
  }

  public func iLike(_ pattern: String) -> InstantPredicate<Entity> {
    InstantPredicate(.iLike(field: name, pattern: pattern))
  }
}

public struct InstantEntityQuery<Entity: InstantEntityModel>: Hashable, Sendable {
  public private(set) var plan: InstantQueryPlan

  public init(
    filters: [InstantQueryFilter] = [],
    order: InstantQueryOrder? = nil,
    offset: UInt? = nil,
    limit: UInt? = nil
  ) {
    let offset = offset.map { Int(clamping: $0) }
    let limit = limit.map { Int(clamping: $0) }
    self.plan = InstantQueryPlan(
      id: Self.queryID(
        filters: filters,
        order: order,
        offset: offset,
        limit: limit,
        selectedFields: nil
      ),
      namespace: Entity.instantNamespace,
      filters: filters,
      order: order,
      offset: offset,
      limit: limit
    )
  }

  public func `where`(_ predicate: InstantPredicate<Entity>) -> Self {
    var copy = self
    copy.plan.filters.append(predicate.filter)
    copy.plan.id = Self.queryID(
      filters: copy.plan.filters,
      order: copy.plan.order,
      offset: copy.plan.offset,
      limit: copy.plan.limit,
      selectedFields: copy.plan.selectedFields
    )
    return copy
  }

  public func order<Value>(
    _ field: InstantAttributePath<Entity, Value>,
    _ direction: InstantQuerySortDirection = .ascending
  ) -> Self {
    var copy = self
    copy.plan.order = InstantQueryOrder(field.name, direction)
    copy.plan.id = Self.queryID(
      filters: copy.plan.filters,
      order: copy.plan.order,
      offset: copy.plan.offset,
      limit: copy.plan.limit,
      selectedFields: copy.plan.selectedFields
    )
    return copy
  }

  public func offset(_ offset: UInt) -> Self {
    var copy = self
    copy.plan.offset = Int(clamping: offset)
    copy.plan.id = Self.queryID(
      filters: copy.plan.filters,
      order: copy.plan.order,
      offset: copy.plan.offset,
      limit: copy.plan.limit,
      selectedFields: copy.plan.selectedFields
    )
    return copy
  }

  public func limit(_ limit: UInt) -> Self {
    var copy = self
    copy.plan.limit = Int(clamping: limit)
    copy.plan.id = Self.queryID(
      filters: copy.plan.filters,
      order: copy.plan.order,
      offset: copy.plan.offset,
      limit: copy.plan.limit,
      selectedFields: copy.plan.selectedFields
    )
    return copy
  }

  private static func queryID(
    filters: [InstantQueryFilter],
    order: InstantQueryOrder?,
    offset: Int?,
    limit: Int?,
    selectedFields: [String]?
  ) -> String {
    let payload = QueryIDPayload(
      namespace: Entity.instantNamespace,
      filters: filters,
      order: order,
      offset: offset,
      limit: limit,
      selectedFields: selectedFields
    )
    return "instant-query:" + payload.canonicalBase64ID()
  }
}

private struct QueryIDPayload: Encodable {
  var namespace: String
  var filters: [InstantQueryFilter]
  var order: InstantQueryOrder?
  var offset: Int?
  var limit: Int?
  var selectedFields: [String]?

  func canonicalBase64ID() -> String {
    let encoder = JSONEncoder()
    encoder.nonConformingFloatEncodingStrategy = .convertToString(
      positiveInfinity: "Infinity",
      negativeInfinity: "-Infinity",
      nan: "NaN"
    )
    encoder.outputFormatting = [.sortedKeys]
    let data: Data
    do {
      data = try encoder.encode(self)
    } catch {
      preconditionFailure("Instant typed query IDs must be canonically encodable: \(error)")
    }
    return data.base64EncodedString()
      .replacingOccurrences(of: "+", with: "-")
      .replacingOccurrences(of: "/", with: "_")
      .replacingOccurrences(of: "=", with: "")
  }
}

public struct InstantMutation: Sendable {
  fileprivate var makeOperations: @Sendable (String, InstantTimestamp) -> [InstantTripleOperation]

  public init(
    makeOperations: @escaping @Sendable (String, InstantTimestamp) -> [InstantTripleOperation]
  ) {
    self.makeOperations = makeOperations
  }

  fileprivate func operations(
    transactionID: String,
    txTime: InstantTimestamp
  ) -> [InstantTripleOperation] {
    makeOperations(transactionID, txTime)
  }
}

@resultBuilder
public enum InstantMutationBuilder {
  public static func buildBlock(_ components: [InstantMutation]...) -> [InstantMutation] {
    components.flatMap { $0 }
  }

  public static func buildExpression(_ expression: InstantMutation) -> [InstantMutation] {
    [expression]
  }

  public static func buildOptional(_ component: [InstantMutation]?) -> [InstantMutation] {
    component ?? []
  }

  public static func buildEither(first component: [InstantMutation]) -> [InstantMutation] {
    component
  }

  public static func buildEither(second component: [InstantMutation]) -> [InstantMutation] {
    component
  }

  public static func buildArray(_ components: [[InstantMutation]]) -> [InstantMutation] {
    components.flatMap { $0 }
  }
}

extension InstantSwiftDataClient {
  public func query<Entity: InstantEntityModel>(
    _ query: InstantEntityQuery<Entity>
  ) async throws -> [Entity] {
    try Entity.decode(try await self.query(query.plan))
  }

  @discardableResult
  public func transact(
    id explicitID: String? = nil,
    createdAt explicitCreatedAt: InstantTimestamp? = nil,
    @InstantMutationBuilder _ build: @Sendable () throws -> [InstantMutation]
  ) async throws -> InstantStoreMutationResult {
    @Dependency(\.date) var date
    @Dependency(\.uuid) var uuid

    let transactionID =
      explicitID
      ?? runtime?.configuration.makeID()
      ?? uuid().uuidString.lowercased()
    let createdAt =
      explicitCreatedAt
      ?? runtime?.configuration.now()
      ?? InstantTimestamp(milliseconds: Int64((date().timeIntervalSince1970 * 1000).rounded()))
    let operations = try build().flatMap {
      $0.operations(transactionID: transactionID, txTime: createdAt)
    }
    let transaction = InstantStoreTransaction(id: transactionID, operations: operations)

    if let runtime {
      return try await runtime.transact(transaction, createdAt: createdAt)
    } else {
      return try await transact(transaction)
    }
  }
}
