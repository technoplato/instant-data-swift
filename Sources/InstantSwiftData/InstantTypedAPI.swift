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

public struct InstantEntityLookup<Entity: InstantEntityModel>: Hashable, Sendable {
  public var name: String
  public var attributeID: String
  public var value: InstantLookupValue

  public init(name: String, attributeID: String, value: InstantLookupValue) {
    self.name = name
    self.attributeID = attributeID
    self.value = value
  }

  public var lookupRef: InstantLookupRef {
    InstantLookupRef(attributeID: attributeID, value: value)
  }
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
    InstantMutation(throwing: { transactionID, txTime in
      try validateAssignments(assignments)
      return [
        .requireEntityMissing(entityID: id.rawValue, namespace: Self.instantNamespace),
        identityOperation(id: id, transactionID: transactionID, txTime: txTime),
      ] + assignments.map { assignment in
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
    })
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
    InstantMutation(throwing: { transactionID, txTime in
      try validateAssignments(assignments)
      return [
        identityOperation(id: id, transactionID: transactionID, txTime: txTime)
      ] + assignments.map { assignment in
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
    })
  }

  public static func update(
    lookup: InstantEntityLookup<Self>,
    _ assignments: InstantAttributeAssignment<Self>...
  ) -> InstantMutation {
    update(lookup: lookup, assignments)
  }

  public static func update(
    lookup: InstantEntityLookup<Self>,
    _ assignments: [InstantAttributeAssignment<Self>]
  ) -> InstantMutation {
    InstantMutation(throwing: { transactionID, txTime in
      try validateLookup(lookup)
      try validateAssignments(assignments)
      return [
        identityOperation(lookup: lookup, transactionID: transactionID, txTime: txTime)
      ] + assignments.map { assignment in
        .insertByLookup(
          entity: lookup.lookupRef,
          attributeID: assignment.attributeID,
          value: assignment.value,
          txID: transactionID,
          txTime: txTime
        )
      }
    })
  }

  public static func merge(
    id: ID,
    _ assignments: InstantAttributeAssignment<Self>...
  ) -> InstantMutation {
    merge(id: id, assignments)
  }

  public static func merge(
    id: ID,
    _ assignments: [InstantAttributeAssignment<Self>]
  ) -> InstantMutation {
    InstantMutation(throwing: { transactionID, txTime in
      try validateAssignments(assignments, allowRefs: false)
      let operations: [InstantTripleOperation] = [
        identityOperation(id: id, transactionID: transactionID, txTime: txTime)
      ] + assignments.map { assignment in
        InstantTripleOperation.merge(
          InstantTriple(
            entityID: id.rawValue,
            attributeID: assignment.attributeID,
            value: assignment.value,
            txID: transactionID,
            txTime: txTime
          )
        )
      }
      return operations
    })
  }

  public static func merge(
    lookup: InstantEntityLookup<Self>,
    _ assignments: InstantAttributeAssignment<Self>...
  ) -> InstantMutation {
    merge(lookup: lookup, assignments)
  }

  public static func merge(
    lookup: InstantEntityLookup<Self>,
    _ assignments: [InstantAttributeAssignment<Self>]
  ) -> InstantMutation {
    InstantMutation(throwing: { transactionID, txTime in
      try validateLookup(lookup)
      try validateAssignments(assignments, allowRefs: false)
      let operations: [InstantTripleOperation] = [
        identityOperation(lookup: lookup, transactionID: transactionID, txTime: txTime)
      ] + assignments.map { assignment in
        InstantTripleOperation.mergeByLookup(
          entity: lookup.lookupRef,
          attributeID: assignment.attributeID,
          value: assignment.value,
          txID: transactionID,
          txTime: txTime
        )
      }
      return operations
    })
  }

  public static func updateExisting(
    id: ID,
    _ assignments: InstantAttributeAssignment<Self>...
  ) -> InstantMutation {
    updateExisting(id: id, assignments)
  }

  public static func updateExisting(
    id: ID,
    _ assignments: [InstantAttributeAssignment<Self>]
  ) -> InstantMutation {
    InstantMutation(throwing: { transactionID, txTime in
      try validateAssignments(assignments)
      return [
        .requireEntityExists(entityID: id.rawValue, namespace: Self.instantNamespace),
        identityOperation(id: id, transactionID: transactionID, txTime: txTime),
      ] + assignments.map { assignment in
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
    })
  }

  public static func updateExisting(
    lookup: InstantEntityLookup<Self>,
    _ assignments: InstantAttributeAssignment<Self>...
  ) -> InstantMutation {
    updateExisting(lookup: lookup, assignments)
  }

  public static func updateExisting(
    lookup: InstantEntityLookup<Self>,
    _ assignments: [InstantAttributeAssignment<Self>]
  ) -> InstantMutation {
    InstantMutation(throwing: { transactionID, txTime in
      try validateLookup(lookup)
      try validateAssignments(assignments)
      return [
        .requireEntityExistsByLookup(lookup.lookupRef, namespace: Self.instantNamespace),
        identityOperation(lookup: lookup, transactionID: transactionID, txTime: txTime),
      ] + assignments.map { assignment in
        .insertByLookup(
          entity: lookup.lookupRef,
          attributeID: assignment.attributeID,
          value: assignment.value,
          txID: transactionID,
          txTime: txTime
        )
      }
    })
  }

  fileprivate static func identityOperation(
    id: ID,
    transactionID: String,
    txTime: InstantTimestamp
  ) -> InstantTripleOperation {
    .insert(
      InstantTriple(
        entityID: id.rawValue,
        attributeID: InstantAttribute.primaryKeyID(namespace: Self.instantNamespace),
        value: .string(id.rawValue),
        txID: transactionID,
        txTime: txTime
      )
    )
  }

  fileprivate static func identityOperation(
    lookup: InstantEntityLookup<Self>,
    transactionID: String,
    txTime: InstantTimestamp
  ) -> InstantTripleOperation {
    .insertByLookup(
      entity: lookup.lookupRef,
      attributeID: InstantAttribute.primaryKeyID(namespace: Self.instantNamespace),
      value: .lookupRef(lookup.lookupRef),
      txID: transactionID,
      txTime: txTime
    )
  }

  public static func delete(id: ID) -> InstantMutation {
    InstantMutation { _, _ in
      [.deleteEntity(id.rawValue)]
    }
  }

  public static func delete(lookup: InstantEntityLookup<Self>) -> InstantMutation {
    InstantMutation(throwing: { _, _ in
      try validateLookup(lookup)
      return [.deleteEntityByLookup(lookup.lookupRef)]
    })
  }

  private static func validateAssignments(
    _ assignments: [InstantAttributeAssignment<Self>],
    allowRefs: Bool = true
  ) throws {
    for assignment in assignments {
      try validateAssignment(assignment, allowRefs: allowRefs)
    }
  }

  private static func validateAssignment(
    _ assignment: InstantAttributeAssignment<Self>,
    allowRefs: Bool
  ) throws {
    guard !isPrimaryKeyAssignment(assignment) else {
      throw primaryKeyAssignmentError(path: assignment.name)
    }

    guard
      let attribute = instantAttributes.first(where: { $0.id == assignment.attributeID })
        ?? instantAttributes.first(where: { $0.name == assignment.name })
    else {
      return
    }

    guard !attribute.primaryKey else {
      throw primaryKeyAssignmentError(path: assignment.name)
    }

    guard allowRefs || attribute.valueType != .ref else {
      throw InstantError(
        code: .validationFailed,
        operation: "merge entity attribute",
        namespace: instantNamespace,
        path: assignment.name,
        message: "Merge is not supported for ref attributes.",
        recovery: "Use link/unlink for relationships, or merge only scalar and JSON attributes."
      )
    }
  }

  private static func isPrimaryKeyAssignment(
    _ assignment: InstantAttributeAssignment<Self>
  ) -> Bool {
    assignment.name == "id"
      || assignment.attributeID == InstantAttribute.primaryKeyID(namespace: instantNamespace)
  }

  fileprivate static func validateLookup(_ lookup: InstantEntityLookup<Self>) throws {
    let attribute = try lookupAttribute(lookup)
    guard attribute.isUnique || attribute.primaryKey else {
      throw lookupError(
        lookup,
        attribute: attribute,
        message: "Attribute '\(attribute.id)' is not unique, so it cannot be used as a lookup ref.",
        recovery: "Mark the attribute unique in the schema, or write the entity by id."
      )
    }

    guard isLookupValue(lookup.value, compatibleWith: attribute) else {
      throw lookupError(
        lookup,
        attribute: attribute,
        message: "Lookup value does not match the declared type of '\(attribute.id)'.",
        recovery: "Use a lookup value whose Swift type matches the unique attribute."
      )
    }
  }

  private static func lookupAttribute(
    _ lookup: InstantEntityLookup<Self>
  ) throws -> InstantAttribute {
    if lookup.name == "id"
      || lookup.attributeID == InstantAttribute.primaryKeyID(namespace: instantNamespace)
    {
      guard lookup.name == "id"
        && lookup.attributeID == InstantAttribute.primaryKeyID(namespace: instantNamespace)
      else {
        throw InstantError(
          code: .validationFailed,
          operation: "lookup entity",
          namespace: instantNamespace,
          path: lookup.name,
          localID: lookup.lookupRef.description,
          message:
            "Lookup path '\(lookup.name)' does not match the managed id attribute '\(InstantAttribute.primaryKeyID(namespace: instantNamespace))'.",
          recovery: "Use an id lookup path named 'id', or use a unique attribute from the entity schema."
        )
      }
      return .primaryKey(namespace: instantNamespace)
    }

    if let attribute = instantAttributes.first(where: { $0.id == lookup.attributeID }) {
      guard attribute.name == lookup.name else {
        throw lookupError(
          lookup,
          attribute: attribute,
          message:
            "Lookup path '\(lookup.name)' does not match attribute '\(attribute.id)' named '\(attribute.name)'.",
          recovery: "Use the schema field name that belongs to the lookup attribute id."
        )
      }
      guard attribute.namespace == instantNamespace else {
        throw lookupError(
          lookup,
          attribute: attribute,
          message:
            "Lookup attribute '\(attribute.id)' belongs to '\(attribute.namespace)', not '\(instantNamespace)'.",
          recovery: "Use a lookup attribute from the same namespace as the entity being written."
        )
      }
      return attribute
    }

    guard let attribute = instantAttributes.first(where: { $0.name == lookup.name }) else {
      throw InstantError(
        code: .validationFailed,
        operation: "lookup entity",
        namespace: instantNamespace,
        path: lookup.name,
        localID: lookup.lookupRef.description,
        message: "No attribute named '\(lookup.name)' is declared for '\(instantNamespace)'.",
        recovery: "Declare '\(lookup.attributeID)' in \(Self.self).instantAttributes before writing by lookup ref."
      )
    }

    guard attribute.id == lookup.attributeID else {
      throw lookupError(
        lookup,
        attribute: attribute,
        message:
          "Lookup path '\(lookup.name)' uses attribute id '\(lookup.attributeID)', but the schema declares '\(attribute.id)'.",
        recovery: "Use the schema attribute id for the lookup path, or construct the path without overriding it."
      )
    }

    guard attribute.namespace == instantNamespace else {
      throw lookupError(
        lookup,
        attribute: attribute,
        message:
          "Lookup attribute '\(attribute.id)' belongs to '\(attribute.namespace)', not '\(instantNamespace)'.",
        recovery: "Use a lookup attribute from the same namespace as the entity being written."
      )
    }

    return attribute
  }

  private static func isLookupValue(
    _ value: InstantLookupValue,
    compatibleWith attribute: InstantAttribute
  ) -> Bool {
    switch (value, attribute.valueType) {
    case (.null, _),
      (.string, .string),
      (.number, .number),
      (.bool, .boolean),
      (.date, .date),
      (.json, .json),
      (.ref, .ref):
      return true

    default:
      return false
    }
  }

  private static func lookupError(
    _ lookup: InstantEntityLookup<Self>,
    attribute: InstantAttribute,
    message: String,
    recovery: String
  ) -> InstantError {
    InstantError(
      code: .validationFailed,
      operation: "lookup entity",
      namespace: instantNamespace,
      path: attribute.name,
      localID: lookup.lookupRef.description,
      message: message,
      recovery: recovery
    )
  }

  private static func primaryKeyAssignmentError(path: String) -> InstantError {
    InstantError(
      code: .validationFailed,
      operation: "write entity attribute",
      namespace: instantNamespace,
      path: path,
      message: "The 'id' attribute is managed by Instant Swift Data.",
      recovery: "Pass the entity id to create/update/merge instead of assigning the id attribute directly."
    )
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

  public func lookup(_ value: Value) -> InstantEntityLookup<Entity> {
    InstantEntityLookup(
      name: name,
      attributeID: attributeID,
      value: InstantLookupValue(value.instantValue)
    )
  }

  public func link<Target: InstantEntityModel>(
    from sourceID: Entity.ID,
    to targetID: InstantID<Target>
  ) -> InstantMutation where Value == InstantID<Target> {
    InstantMutation(throwing: { transactionID, txTime in
      let attribute = try linkAttribute(target: Target.self)
      return [
        .insert(
          InstantTriple(
            entityID: sourceID.rawValue,
            attributeID: attribute.id,
            value: .ref(targetID.rawValue),
            txID: transactionID,
            txTime: txTime
          )
        )
      ]
    })
  }

  public func link<Target: InstantEntityModel>(
    from sourceLookup: InstantEntityLookup<Entity>,
    to targetID: InstantID<Target>
  ) -> InstantMutation where Value == InstantID<Target> {
    InstantMutation(throwing: { transactionID, txTime in
      try Entity.validateLookup(sourceLookup)
      let attribute = try linkAttribute(target: Target.self)
      return [
        Entity.identityOperation(
          lookup: sourceLookup,
          transactionID: transactionID,
          txTime: txTime
        ),
        .insertByLookup(
          entity: sourceLookup.lookupRef,
          attributeID: attribute.id,
          value: .ref(targetID.rawValue),
          txID: transactionID,
          txTime: txTime
        ),
      ]
    })
  }

  public func link<Target: InstantEntityModel>(
    from sourceID: Entity.ID,
    to targetLookup: InstantEntityLookup<Target>
  ) -> InstantMutation where Value == InstantID<Target> {
    InstantMutation(throwing: { transactionID, txTime in
      try Target.validateLookup(targetLookup)
      let attribute = try linkAttribute(target: Target.self)
      return [
        .insert(
          InstantTriple(
            entityID: sourceID.rawValue,
            attributeID: attribute.id,
            value: .lookupRef(targetLookup.lookupRef),
            txID: transactionID,
            txTime: txTime
          )
        )
      ]
    })
  }

  public func link<Target: InstantEntityModel>(
    from sourceLookup: InstantEntityLookup<Entity>,
    to targetLookup: InstantEntityLookup<Target>
  ) -> InstantMutation where Value == InstantID<Target> {
    InstantMutation(throwing: { transactionID, txTime in
      try Entity.validateLookup(sourceLookup)
      try Target.validateLookup(targetLookup)
      let attribute = try linkAttribute(target: Target.self)
      return [
        Entity.identityOperation(
          lookup: sourceLookup,
          transactionID: transactionID,
          txTime: txTime
        ),
        .insertByLookup(
          entity: sourceLookup.lookupRef,
          attributeID: attribute.id,
          value: .lookupRef(targetLookup.lookupRef),
          txID: transactionID,
          txTime: txTime
        ),
      ]
    })
  }

  public func unlink<Target: InstantEntityModel>(
    from sourceID: Entity.ID,
    to targetID: InstantID<Target>
  ) -> InstantMutation where Value == InstantID<Target> {
    InstantMutation(throwing: { transactionID, txTime in
      let attribute = try linkAttribute(target: Target.self)
      return [
        .retract(
          InstantTriple(
            entityID: sourceID.rawValue,
            attributeID: attribute.id,
            value: .ref(targetID.rawValue),
            txID: transactionID,
            txTime: txTime
          )
        )
      ]
    })
  }

  public func unlink<Target: InstantEntityModel>(
    from sourceLookup: InstantEntityLookup<Entity>,
    to targetID: InstantID<Target>
  ) -> InstantMutation where Value == InstantID<Target> {
    InstantMutation(throwing: { transactionID, txTime in
      try Entity.validateLookup(sourceLookup)
      let attribute = try linkAttribute(target: Target.self)
      return [
        Entity.identityOperation(
          lookup: sourceLookup,
          transactionID: transactionID,
          txTime: txTime
        ),
        .retractByLookup(
          entity: sourceLookup.lookupRef,
          attributeID: attribute.id,
          value: .ref(targetID.rawValue),
          txID: transactionID,
          txTime: txTime
        ),
      ]
    })
  }

  public func unlink<Target: InstantEntityModel>(
    from sourceID: Entity.ID,
    to targetLookup: InstantEntityLookup<Target>
  ) -> InstantMutation where Value == InstantID<Target> {
    InstantMutation(throwing: { transactionID, txTime in
      try Target.validateLookup(targetLookup)
      let attribute = try linkAttribute(target: Target.self)
      return [
        .retract(
          InstantTriple(
            entityID: sourceID.rawValue,
            attributeID: attribute.id,
            value: .lookupRef(targetLookup.lookupRef),
            txID: transactionID,
            txTime: txTime
          )
        )
      ]
    })
  }

  public func unlink<Target: InstantEntityModel>(
    from sourceLookup: InstantEntityLookup<Entity>,
    to targetLookup: InstantEntityLookup<Target>
  ) -> InstantMutation where Value == InstantID<Target> {
    InstantMutation(throwing: { transactionID, txTime in
      try Entity.validateLookup(sourceLookup)
      try Target.validateLookup(targetLookup)
      let attribute = try linkAttribute(target: Target.self)
      return [
        Entity.identityOperation(
          lookup: sourceLookup,
          transactionID: transactionID,
          txTime: txTime
        ),
        .retractByLookup(
          entity: sourceLookup.lookupRef,
          attributeID: attribute.id,
          value: .lookupRef(targetLookup.lookupRef),
          txID: transactionID,
          txTime: txTime
        ),
      ]
    })
  }

  private func linkAttribute<Target: InstantEntityModel>(
    target: Target.Type
  ) throws -> InstantAttribute {
    guard
      let attribute = Entity.instantAttributes.first(where: { $0.id == attributeID })
        ?? Entity.instantAttributes.first(where: { $0.name == name })
    else {
      throw InstantError(
        code: .validationFailed,
        operation: "build link mutation",
        namespace: Entity.instantNamespace,
        path: name,
        message: "No attribute named '\(name)' is declared for '\(Entity.instantNamespace)'.",
        recovery: "Declare '\(attributeID)' in \(Entity.self).instantAttributes before linking."
      )
    }

    guard attribute.valueType == .ref else {
      throw InstantError(
        code: .validationFailed,
        operation: "build link mutation",
        namespace: Entity.instantNamespace,
        path: name,
        message: "Attribute '\(attribute.id)' is not a ref attribute.",
        recovery: "Use link/unlink only with Instant ref attributes."
      )
    }

    guard attribute.linkNamespace == nil || attribute.linkNamespace == Target.instantNamespace else {
      throw InstantError(
        code: .validationFailed,
        operation: "build link mutation",
        namespace: Entity.instantNamespace,
        path: name,
        message:
          "Attribute '\(attribute.id)' links to '\(attribute.linkNamespace ?? "")', not '\(Target.instantNamespace)'.",
        recovery: "Use an InstantID whose entity type matches the link namespace."
      )
    }

    return attribute
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
    limit: UInt? = nil,
    first: UInt? = nil,
    after: InstantQueryCursor? = nil,
    last: UInt? = nil,
    before: InstantQueryCursor? = nil
  ) {
    let offset = offset.map { Int(clamping: $0) }
    let limit = limit.map { Int(clamping: $0) }
    let first = first.map { Int(clamping: $0) }
    let last = last.map { Int(clamping: $0) }
    self.plan = InstantQueryPlan(
      id: Self.queryID(
        filters: filters,
        order: order,
        offset: offset,
        limit: limit,
        first: first,
        after: after,
        last: last,
        before: before,
        selectedFields: nil
      ),
      namespace: Entity.instantNamespace,
      filters: filters,
      order: order,
      offset: offset,
      limit: limit,
      first: first,
      after: after,
      last: last,
      before: before
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
      first: copy.plan.first,
      after: copy.plan.after,
      last: copy.plan.last,
      before: copy.plan.before,
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
      first: copy.plan.first,
      after: copy.plan.after,
      last: copy.plan.last,
      before: copy.plan.before,
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
      first: copy.plan.first,
      after: copy.plan.after,
      last: copy.plan.last,
      before: copy.plan.before,
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
      first: copy.plan.first,
      after: copy.plan.after,
      last: copy.plan.last,
      before: copy.plan.before,
      selectedFields: copy.plan.selectedFields
    )
    return copy
  }

  public func first(_ first: UInt) -> Self {
    var copy = self
    copy.plan.first = Int(clamping: first)
    copy.plan.last = nil
    copy.plan.id = Self.queryID(
      filters: copy.plan.filters,
      order: copy.plan.order,
      offset: copy.plan.offset,
      limit: copy.plan.limit,
      first: copy.plan.first,
      after: copy.plan.after,
      last: copy.plan.last,
      before: copy.plan.before,
      selectedFields: copy.plan.selectedFields
    )
    return copy
  }

  public func after(_ cursor: InstantQueryCursor) -> Self {
    var copy = self
    copy.plan.after = cursor
    copy.plan.id = Self.queryID(
      filters: copy.plan.filters,
      order: copy.plan.order,
      offset: copy.plan.offset,
      limit: copy.plan.limit,
      first: copy.plan.first,
      after: copy.plan.after,
      last: copy.plan.last,
      before: copy.plan.before,
      selectedFields: copy.plan.selectedFields
    )
    return copy
  }

  public func last(_ last: UInt) -> Self {
    var copy = self
    copy.plan.first = nil
    copy.plan.last = Int(clamping: last)
    copy.plan.id = Self.queryID(
      filters: copy.plan.filters,
      order: copy.plan.order,
      offset: copy.plan.offset,
      limit: copy.plan.limit,
      first: copy.plan.first,
      after: copy.plan.after,
      last: copy.plan.last,
      before: copy.plan.before,
      selectedFields: copy.plan.selectedFields
    )
    return copy
  }

  public func before(_ cursor: InstantQueryCursor) -> Self {
    var copy = self
    copy.plan.before = cursor
    copy.plan.id = Self.queryID(
      filters: copy.plan.filters,
      order: copy.plan.order,
      offset: copy.plan.offset,
      limit: copy.plan.limit,
      first: copy.plan.first,
      after: copy.plan.after,
      last: copy.plan.last,
      before: copy.plan.before,
      selectedFields: copy.plan.selectedFields
    )
    return copy
  }

  private static func queryID(
    filters: [InstantQueryFilter],
    order: InstantQueryOrder?,
    offset: Int?,
    limit: Int?,
    first: Int?,
    after: InstantQueryCursor?,
    last: Int?,
    before: InstantQueryCursor?,
    selectedFields: [String]?
  ) -> String {
    let payload = QueryIDPayload(
      namespace: Entity.instantNamespace,
      filters: filters,
      order: order,
      offset: offset,
      limit: limit,
      first: first,
      after: after,
      last: last,
      before: before,
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
  var first: Int?
  var after: InstantQueryCursor?
  var last: Int?
  var before: InstantQueryCursor?
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
  fileprivate var makeOperations:
    @Sendable (String, InstantTimestamp) throws -> [InstantTripleOperation]

  public init(
    makeOperations: @escaping @Sendable (String, InstantTimestamp) -> [InstantTripleOperation]
  ) {
    self.makeOperations = { transactionID, txTime in
      makeOperations(transactionID, txTime)
    }
  }

  fileprivate init(
    throwing makeOperations: @escaping @Sendable (String, InstantTimestamp) throws
      -> [InstantTripleOperation]
  ) {
    self.makeOperations = makeOperations
  }

  fileprivate func operations(
    transactionID: String,
    txTime: InstantTimestamp
  ) throws -> [InstantTripleOperation] {
    try makeOperations(transactionID, txTime)
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
      try $0.operations(transactionID: transactionID, txTime: createdAt)
    }
    let transaction = InstantStoreTransaction(id: transactionID, operations: operations)

    if let runtime {
      return try await runtime.transact(transaction, createdAt: createdAt)
    } else {
      return try await transact(transaction)
    }
  }
}
