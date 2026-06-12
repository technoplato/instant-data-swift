import Dependencies
import Foundation
import InstantSwiftDataCore

public protocol InstantValueRepresentable: Sendable {
  var instantValue: InstantValue { get }
}

extension String: InstantValueRepresentable {
  public var instantValue: InstantValue { .string(self) }
}

extension Bool: InstantValueRepresentable {
  public var instantValue: InstantValue { .bool(self) }
}

extension Date: InstantValueRepresentable {
  public var instantValue: InstantValue { .date(self) }
}

extension Double: InstantValueRepresentable {
  public var instantValue: InstantValue { .number(self) }
}

extension Float: InstantValueRepresentable {
  public var instantValue: InstantValue { .number(Double(self)) }
}

extension Int: InstantValueRepresentable {
  public var instantValue: InstantValue { .number(Double(self)) }
}

extension Int64: InstantValueRepresentable {
  public var instantValue: InstantValue { .number(Double(self)) }
}

extension InstantTimestamp: InstantValueRepresentable {
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

public func == <Entity, Value>(
  lhs: InstantAttributePath<Entity, Value>,
  rhs: Value
) -> InstantPredicate<Entity> {
  InstantPredicate(.equals(field: lhs.name, value: rhs.instantValue))
}

public struct InstantEntityQuery<Entity: InstantEntityModel>: Hashable, Sendable {
  public private(set) var plan: InstantQueryPlan

  public init(
    filters: [InstantQueryFilter] = [],
    order: InstantQueryOrder? = nil,
    limit: UInt? = nil
  ) {
    let limit = limit.map { Int(clamping: $0) }
    self.plan = InstantQueryPlan(
      id: Self.queryID(filters: filters, order: order, limit: limit),
      namespace: Entity.instantNamespace,
      filters: filters,
      order: order,
      limit: limit
    )
  }

  public func `where`(_ predicate: InstantPredicate<Entity>) -> Self {
    var copy = self
    copy.plan.filters.append(predicate.filter)
    copy.plan.id = Self.queryID(
      filters: copy.plan.filters,
      order: copy.plan.order,
      limit: copy.plan.limit
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
      limit: copy.plan.limit
    )
    return copy
  }

  public func limit(_ limit: UInt) -> Self {
    var copy = self
    copy.plan.limit = Int(clamping: limit)
    copy.plan.id = Self.queryID(
      filters: copy.plan.filters,
      order: copy.plan.order,
      limit: copy.plan.limit
    )
    return copy
  }

  private static func queryID(
    filters: [InstantQueryFilter],
    order: InstantQueryOrder?,
    limit: Int?
  ) -> String {
    var parts = [Entity.instantNamespace]
    if !filters.isEmpty {
      parts.append("where:" + filters.map(filterID).joined(separator: ","))
    }
    if let order {
      parts.append("order:\(order.field):\(order.direction.rawValue)")
    }
    if let limit {
      parts.append("limit:\(limit)")
    }
    return parts.joined(separator: "|")
  }

  private static func filterID(_ filter: InstantQueryFilter) -> String {
    switch filter {
    case let .equals(field, value):
      return "\(field)==\(valueID(value))"
    case let .isNull(field):
      return "\(field)==null"
    }
  }

  private static func valueID(_ value: InstantValue) -> String {
    switch value {
    case .null:
      return "null"
    case let .string(value):
      return "string:\(value)"
    case let .number(value):
      return "number:\(value)"
    case let .bool(value):
      return "bool:\(value)"
    case let .date(value):
      return "date:\(Int64((value.timeIntervalSince1970 * 1000).rounded()))"
    case let .json(value):
      return "json:\(String(describing: value))"
    case let .ref(value):
      return "ref:\(value)"
    }
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
