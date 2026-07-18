import Dependencies
import Foundation
import InstantSwiftDataCore

public protocol InstantValueRepresentable: Sendable {
  var instantValue: InstantValue { get }
}

public protocol InstantValueDecodable: Sendable {
  static var acceptsMissingInstantValue: Bool { get }

  static func decodeInstantValue(
    _ value: InstantValue?,
    namespace: String,
    path: String,
    localID: String?,
    operation: String
  ) throws -> Self
}

public extension InstantValueDecodable {
  static var acceptsMissingInstantValue: Bool { false }
}

public protocol InstantComparableValue: InstantValueRepresentable {}

public protocol InstantWireValue: InstantValueRepresentable, InstantValueDecodable {
  static var instantValueType: InstantValueType { get }
}

public protocol InstantStringWireValue: InstantComparableValue, InstantWireValue {}

public extension InstantStringWireValue {
  static var instantValueType: InstantValueType { .string }
}

public protocol InstantNumberWireValue: InstantComparableValue, InstantWireValue {}

public extension InstantNumberWireValue {
  static var instantValueType: InstantValueType { .number }
}

public protocol InstantBooleanWireValue: InstantWireValue {}

public extension InstantBooleanWireValue {
  static var instantValueType: InstantValueType { .boolean }
}

public protocol InstantDateWireValue: InstantComparableValue, InstantWireValue {}

public extension InstantDateWireValue {
  static var instantValueType: InstantValueType { .date }
}

public protocol InstantJSONWireValue: InstantWireValue {}

public extension InstantJSONWireValue {
  static var instantValueType: InstantValueType { .json }
}

public protocol InstantStringEnum: InstantStringWireValue, RawRepresentable
where RawValue == String {}

public extension InstantStringEnum {
  var instantValue: InstantValue { .string(rawValue) }

  static func decodeInstantValue(
    _ value: InstantValue?,
    namespace: String,
    path: String,
    localID: String?,
    operation: String
  ) throws -> Self {
    let rawValue = try String.decodeInstantValue(
      value,
      namespace: namespace,
      path: path,
      localID: localID,
      operation: operation
    )
    guard let decoded = Self(rawValue: rawValue) else {
      throw instantValueDecodeError(
        value,
        expectedType: "valid \(Self.self) string case",
        namespace: namespace,
        path: path,
        localID: localID,
        operation: operation
      )
    }
    return decoded
  }
}

public protocol InstantNumberEnum: InstantNumberWireValue, RawRepresentable
where RawValue == Int {}

public extension InstantNumberEnum {
  var instantValue: InstantValue { .number(Double(rawValue)) }

  static func decodeInstantValue(
    _ value: InstantValue?,
    namespace: String,
    path: String,
    localID: String?,
    operation: String
  ) throws -> Self {
    let rawValue = try Int.decodeInstantValue(
      value,
      namespace: namespace,
      path: path,
      localID: localID,
      operation: operation
    )
    guard let decoded = Self(rawValue: rawValue) else {
      throw instantValueDecodeError(
        value,
        expectedType: "valid \(Self.self) integer case",
        namespace: namespace,
        path: path,
        localID: localID,
        operation: operation
      )
    }
    return decoded
  }
}

extension String: InstantStringWireValue {
  public var instantValue: InstantValue { .string(self) }
}

extension String: InstantValueDecodable {
  public static func decodeInstantValue(
    _ value: InstantValue?,
    namespace: String,
    path: String,
    localID: String?,
    operation: String
  ) throws -> Self {
    guard case let .string(value) = value else {
      throw instantValueDecodeError(
        value,
        expectedType: "string",
        namespace: namespace,
        path: path,
        localID: localID,
        operation: operation
      )
    }
    return value
  }
}

extension Bool: InstantBooleanWireValue {
  public var instantValue: InstantValue { .bool(self) }
}

extension Bool: InstantValueDecodable {
  public static func decodeInstantValue(
    _ value: InstantValue?,
    namespace: String,
    path: String,
    localID: String?,
    operation: String
  ) throws -> Self {
    guard case let .bool(value) = value else {
      throw instantValueDecodeError(
        value,
        expectedType: "boolean",
        namespace: namespace,
        path: path,
        localID: localID,
        operation: operation
      )
    }
    return value
  }
}

extension Date: InstantDateWireValue {
  public var instantValue: InstantValue { .date(self) }
}

extension Date: InstantValueDecodable {
  public static func decodeInstantValue(
    _ value: InstantValue?,
    namespace: String,
    path: String,
    localID: String?,
    operation: String
  ) throws -> Self {
    guard case let .date(value) = value else {
      throw instantValueDecodeError(
        value,
        expectedType: "date",
        namespace: namespace,
        path: path,
        localID: localID,
        operation: operation
      )
    }
    return value
  }
}

extension Double: InstantNumberWireValue {
  public var instantValue: InstantValue { .number(self) }
}

extension Double: InstantValueDecodable {
  public static func decodeInstantValue(
    _ value: InstantValue?,
    namespace: String,
    path: String,
    localID: String?,
    operation: String
  ) throws -> Self {
    guard case let .number(value) = value else {
      throw instantValueDecodeError(
        value,
        expectedType: "number",
        namespace: namespace,
        path: path,
        localID: localID,
        operation: operation
      )
    }
    return value
  }
}

extension Float: InstantNumberWireValue {
  public var instantValue: InstantValue { .number(Double(self)) }
}

extension Float: InstantValueDecodable {
  public static func decodeInstantValue(
    _ value: InstantValue?,
    namespace: String,
    path: String,
    localID: String?,
    operation: String
  ) throws -> Self {
    guard case let .number(value) = value,
      value.isFinite,
      value >= Double(-Float.greatestFiniteMagnitude),
      value <= Double(Float.greatestFiniteMagnitude)
    else {
      throw instantValueDecodeError(
        value,
        expectedType: "number",
        namespace: namespace,
        path: path,
        localID: localID,
        operation: operation
      )
    }
    return Float(value)
  }
}

extension Int: InstantNumberWireValue {
  public var instantValue: InstantValue { .number(Double(self)) }
}

extension Int: InstantValueDecodable {
  public static func decodeInstantValue(
    _ value: InstantValue?,
    namespace: String,
    path: String,
    localID: String?,
    operation: String
  ) throws -> Self {
    guard case let .number(value) = value,
      let integer = Int(exactly: value)
    else {
      throw instantValueDecodeError(
        value,
        expectedType: "integer",
        namespace: namespace,
        path: path,
        localID: localID,
        operation: operation
      )
    }
    return integer
  }
}

extension Int64: InstantNumberWireValue {
  public var instantValue: InstantValue { .number(Double(self)) }
}

extension Int64: InstantValueDecodable {
  public static func decodeInstantValue(
    _ value: InstantValue?,
    namespace: String,
    path: String,
    localID: String?,
    operation: String
  ) throws -> Self {
    guard case let .number(value) = value,
      let integer = Int64(exactly: value)
    else {
      throw instantValueDecodeError(
        value,
        expectedType: "integer",
        namespace: namespace,
        path: path,
        localID: localID,
        operation: operation
      )
    }
    return integer
  }
}

extension InstantTimestamp: InstantDateWireValue {
  public var instantValue: InstantValue {
    .date(Date(timeIntervalSince1970: Double(milliseconds) / 1000))
  }
}

extension InstantTimestamp: InstantValueDecodable {
  public static func decodeInstantValue(
    _ value: InstantValue?,
    namespace: String,
    path: String,
    localID: String?,
    operation: String
  ) throws -> Self {
    let date = try Date.decodeInstantValue(
      value,
      namespace: namespace,
      path: path,
      localID: localID,
      operation: operation
    )
    return InstantTimestamp(milliseconds: Int64((date.timeIntervalSince1970 * 1000).rounded()))
  }
}

extension InstantID: InstantValueRepresentable {
  public var instantValue: InstantValue { .ref(rawValue) }
}

extension InstantID: InstantValueDecodable {
  public static func decodeInstantValue(
    _ value: InstantValue?,
    namespace: String,
    path: String,
    localID: String?,
    operation: String
  ) throws -> Self {
    guard case let .ref(value) = value else {
      throw instantValueDecodeError(
        value,
        expectedType: "ref",
        namespace: namespace,
        path: path,
        localID: localID,
        operation: operation
      )
    }
    return Self(rawValue: value)
  }
}

extension AnyInstantID: InstantValueRepresentable {
  public var instantValue: InstantValue { .ref(rawValue) }
}

extension AnyInstantID: InstantValueDecodable {
  public static func decodeInstantValue(
    _ value: InstantValue?,
    namespace: String,
    path: String,
    localID: String?,
    operation: String
  ) throws -> Self {
    guard case let .ref(value) = value else {
      throw instantValueDecodeError(
        value,
        expectedType: "ref",
        namespace: namespace,
        path: path,
        localID: localID,
        operation: operation
      )
    }
    return Self(value)
  }
}

extension Optional: InstantValueRepresentable where Wrapped: InstantValueRepresentable {
  public var instantValue: InstantValue {
    switch self {
    case let .some(value):
      return value.instantValue
    case .none:
      return .null
    }
  }
}

extension Optional: InstantValueDecodable where Wrapped: InstantValueDecodable {
  public static var acceptsMissingInstantValue: Bool { true }

  public static func decodeInstantValue(
    _ value: InstantValue?,
    namespace: String,
    path: String,
    localID: String?,
    operation: String
  ) throws -> Self {
    guard let value, value != .null else { return nil }
    return try Wrapped.decodeInstantValue(
      value,
      namespace: namespace,
      path: path,
      localID: localID,
      operation: operation
    )
  }
}

extension JSONValue: InstantJSONWireValue {
  public var instantValue: InstantValue { .json(self) }
}

extension JSONValue: InstantValueDecodable {
  public static func decodeInstantValue(
    _ value: InstantValue?,
    namespace: String,
    path: String,
    localID: String?,
    operation: String
  ) throws -> Self {
    guard case let .json(value) = value else {
      throw instantValueDecodeError(
        value,
        expectedType: "json",
        namespace: namespace,
        path: path,
        localID: localID,
        operation: operation
      )
    }
    return value
  }
}

private func instantValueDecodeError(
  _ value: InstantValue?,
  expectedType: String,
  namespace: String,
  path: String,
  localID: String?,
  operation: String
) -> InstantError {
  InstantError(
    code: .decodeFailed,
    operation: operation,
    namespace: namespace,
    path: path,
    localID: localID,
    message: "Expected \(expectedType) for selected Instant field '\(path)'.",
    recovery: "Check the Instant entity schema and server value for '\(namespace).\(path)'."
  )
}

public protocol InstantEntityModel: Identifiable, Sendable where ID == InstantID<Self> {
  static var instantNamespace: String { get }
  static var instantAttributes: [InstantAttribute] { get }

  init(snapshot: InstantEntitySnapshot) throws
}

public protocol InstantEntityDraft: Sendable {
  associatedtype Entity: InstantEntityModel

  var id: Entity.ID? { get set }
  var instantAssignments: [InstantAttributeAssignment<Entity>] { get }

  init(_ entity: Entity)
}

public struct InstantPreparedDraftSave<Entity: InstantEntityModel>: Sendable {
  public var id: Entity.ID
  public var mutation: InstantMutation

  public init(id: Entity.ID, mutation: InstantMutation) {
    self.id = id
    self.mutation = mutation
  }
}

public struct InstantDraftSaveTransactionResult<Entity: InstantEntityModel>: Sendable {
  public var id: Entity.ID
  public var transaction: InstantStoreMutationResult

  public init(id: Entity.ID, transaction: InstantStoreMutationResult) {
    self.id = id
    self.transaction = transaction
  }
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
      let assignments = try validateAssignments(assignments)
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
      let assignments = try validateAssignments(assignments)
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
      let assignments = try validateAssignments(assignments)
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
      let assignments = try validateAssignments(assignments, allowRefs: false)
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
      let assignments = try validateAssignments(assignments, allowRefs: false)
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
      let assignments = try validateAssignments(assignments)
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
      let assignments = try validateAssignments(assignments)
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
      [
        .requireEntityExists(entityID: id.rawValue, namespace: Self.instantNamespace),
        .deleteEntityInNamespace(entityID: id.rawValue, namespace: Self.instantNamespace),
      ]
    }
  }

  public static func delete(lookup: InstantEntityLookup<Self>) -> InstantMutation {
    InstantMutation(throwing: { _, _ in
      try validateLookup(lookup)
      return [
        .requireEntityExistsByLookup(lookup.lookupRef, namespace: Self.instantNamespace),
        .deleteEntityByLookup(lookup.lookupRef),
      ]
    })
  }

  public static func ruleParams(id: ID, _ params: JSONValue) -> InstantMutation {
    InstantMutation { _, _ in
      [
        .ruleParams(
          entityID: id.rawValue,
          namespace: Self.instantNamespace,
          params: params
        )
      ]
    }
  }

  public static func ruleParams(
    lookup: InstantEntityLookup<Self>,
    _ params: JSONValue
  ) -> InstantMutation {
    InstantMutation(throwing: { _, _ in
      try validateLookup(lookup)
      return [
        .ruleParamsByLookup(
          entity: lookup.lookupRef,
          namespace: Self.instantNamespace,
          params: params
        )
      ]
    })
  }

  private static func validateAssignments(
    _ assignments: [InstantAttributeAssignment<Self>],
    allowRefs: Bool = true
  ) throws -> [InstantAttributeAssignment<Self>] {
    try assignments.map { assignment in
      try validateAssignment(assignment, allowRefs: allowRefs)
    }
  }

  private static func validateAssignment(
    _ assignment: InstantAttributeAssignment<Self>,
    allowRefs: Bool
  ) throws -> InstantAttributeAssignment<Self> {
    guard !isReservedMetadataPath(assignment.name) else {
      throw reservedMetadataAttributeError(
        operation: "write entity attribute",
        path: assignment.name
      )
    }

    guard !isPrimaryKeyAssignment(assignment) else {
      throw primaryKeyAssignmentError(path: assignment.name)
    }

    let attributeByID = instantAttributes.first { $0.id == assignment.attributeID }
    let attributeByName = instantAttributes.first { $0.name == assignment.name }
    guard let attribute = attributeByID ?? attributeByName else {
      throw InstantError(
        code: .validationFailed,
        operation: "write entity attribute",
        namespace: instantNamespace,
        path: assignment.name,
        message: "No attribute named '\(assignment.name)' is declared for '\(instantNamespace)'.",
        recovery: "Declare '\(assignment.attributeID)' in \(Self.self).instantAttributes before writing this field."
      )
    }

    if let attributeByID, attributeByID.name != assignment.name {
      throw InstantError(
        code: .validationFailed,
        operation: "write entity attribute",
        namespace: instantNamespace,
        path: assignment.name,
        message:
          "Assignment path '\(assignment.name)' uses attribute id '\(assignment.attributeID)', but the schema declares that id as '\(attributeByID.name)'.",
        recovery: "Use the schema field name that belongs to the assignment attribute id."
      )
    }

    try validateUsableAttribute(
      attribute,
      operation: "write entity attribute",
      path: assignment.name
    )
    try validateAssignmentValue(assignment.value, compatibleWith: attribute, path: assignment.name)

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

    return InstantAttributeAssignment(
      name: assignment.name,
      attributeID: attribute.id,
      value: assignment.value
    )
  }

  private static func validateAssignmentValue(
    _ value: InstantValue,
    compatibleWith attribute: InstantAttribute,
    path: String
  ) throws {
    switch (value, attribute.valueType) {
    case (.null, _) where !attribute.isRequired,
      (.string, .string),
      (.number, .number),
      (.bool, .boolean),
      (.date, .date),
      (.json, .json),
      (.string, .any),
      (.number, .any),
      (.bool, .any),
      (.date, .any),
      (.json, .any),
      (.ref, .ref),
      (.lookupRef, .ref):
      return

    case (.null, _):
      throw InstantError(
        code: .validationFailed,
        operation: "write entity attribute",
        namespace: instantNamespace,
        path: path,
        message: "Required attribute '\(attribute.id)' cannot be set to null.",
        recovery: "Make the schema attribute optional, or provide a non-nil value."
      )

    default:
      throw InstantError(
        code: .validationFailed,
        operation: "write entity attribute",
        namespace: instantNamespace,
        path: path,
        message: "Value does not match the declared type of '\(attribute.id)'.",
        recovery: "Use a Swift value whose type matches the Instant schema attribute."
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
    guard !isReservedMetadataPath(lookup.name) else {
      throw reservedMetadataAttributeError(
        operation: "lookup entity",
        path: lookup.name,
        localID: lookup.lookupRef.description
      )
    }

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
      try validateUsableAttribute(
        attribute,
        operation: "lookup entity",
        path: lookup.name,
        localID: lookup.lookupRef.description
      )

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

    try validateUsableAttribute(
      attribute,
      operation: "lookup entity",
      path: lookup.name,
      localID: lookup.lookupRef.description
    )

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

  fileprivate static func validateUsableAttribute(
    _ attribute: InstantAttribute,
    operation: String,
    path: String,
    localID: String? = nil
  ) throws {
    guard !isReservedMetadataPath(attribute.name) else {
      throw reservedMetadataAttributeError(
        operation: operation,
        path: path,
        localID: localID
      )
    }
  }

  private static func isReservedMetadataPath(_ path: String) -> Bool {
    path == InstantQueryOrder.serverCreatedAtField
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
      (.string, .any),
      (.number, .any),
      (.bool, .any),
      (.date, .any),
      (.json, .any),
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

  private static func reservedMetadataAttributeError(
    operation: String,
    path: String,
    localID: String? = nil
  ) -> InstantError {
    InstantError(
      code: .validationFailed,
      operation: operation,
      namespace: instantNamespace,
      path: path,
      localID: localID,
      message: "'\(InstantQueryOrder.serverCreatedAtField)' is reserved for order-only metadata.",
      recovery:
        "Rename the schema field, and use .order(.serverCreatedAt) when ordering by server creation time."
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

    try Entity.validateUsableAttribute(
      attribute,
      operation: "build link mutation",
      path: name
    )

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

  fileprivate func validateIncludeAttribute<Target: InstantEntityModel>(
    target: Target.Type
  ) where Value == InstantID<Target> {
    do {
      _ = try linkAttribute(target: target)
    } catch {
      preconditionFailure("Invalid Instant include relation '\(name)': \(error)")
    }
  }
}

public struct InstantReverseRelation<
  Entity: InstantEntityModel,
  Target: InstantEntityModel
>: Hashable, Sendable {
  public var name: String
  public var attributeID: String?

  public init(_ name: String, attributeID: String? = nil) {
    precondition(
      !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      "InstantReverseRelation name must not be empty."
    )
    self.name = name
    self.attributeID = attributeID
  }

  public init(
    _ name: String,
    attribute: InstantAttributePath<Target, InstantID<Entity>>
  ) {
    self.init(name, attributeID: attribute.attributeID)
  }

  public init(validating attribute: InstantAttributePath<Target, InstantID<Entity>>) throws {
    self = try Self.derived(attribute: attribute)
  }

  public init(validating attribute: InstantAttributePath<Target, InstantID<Entity>?>) throws {
    self = try Self.derived(name: attribute.name, attributeID: attribute.attributeID)
  }

  public init(attribute: InstantAttributePath<Target, InstantID<Entity>>) {
    do {
      self = try Self.derived(attribute: attribute)
    } catch {
      preconditionFailure("Invalid Instant reverse relation '\(attribute.name)': \(error)")
    }
  }

  public init(attribute: InstantAttributePath<Target, InstantID<Entity>?>) {
    do {
      self = try Self.derived(name: attribute.name, attributeID: attribute.attributeID)
    } catch {
      preconditionFailure("Invalid Instant reverse relation '\(attribute.name)': \(error)")
    }
  }

  private static func derived(
    attribute: InstantAttributePath<Target, InstantID<Entity>>
  ) throws -> Self {
    try derived(name: attribute.name, attributeID: attribute.attributeID)
  }

  private static func derived(name: String, attributeID: String) throws -> Self {
    let attributeByID = Target.instantAttributes.first { $0.id == attributeID }
    let attributeByName = Target.instantAttributes.first { $0.name == name }
    guard
      let linkAttribute = attributeByID ?? attributeByName
    else {
      throw derivationError(
        path: name,
        message:
          "No attribute named '\(name)' is declared for '\(Target.instantNamespace)'.",
        recovery:
          "Declare '\(attributeID)' in \(Target.self).instantAttributes before deriving a reverse relation."
      )
    }

    guard linkAttribute.id == attributeID else {
      throw derivationError(
        path: name,
        message:
          "Reverse relation path '\(name)' uses attribute id '\(attributeID)', but the schema declares '\(name)' as attribute id '\(linkAttribute.id)'.",
        recovery: "Use the schema attribute id that belongs to the relation path."
      )
    }

    guard linkAttribute.name == name else {
      throw derivationError(
        path: name,
        message:
          "Reverse relation path '\(name)' uses attribute id '\(attributeID)', but the schema declares that id as '\(linkAttribute.name)'.",
        recovery: "Use the schema field name that belongs to the relation attribute id."
      )
    }

    guard linkAttribute.valueType == .ref else {
      throw derivationError(
        path: name,
        message: "Attribute '\(linkAttribute.id)' is not a ref attribute.",
        recovery: "Derive reverse relations only from Instant ref attributes."
      )
    }

    guard linkAttribute.linkNamespace == Entity.instantNamespace else {
      throw derivationError(
        path: name,
        message:
          "Attribute '\(linkAttribute.id)' links to '\(linkAttribute.linkNamespace ?? "")', not '\(Entity.instantNamespace)'.",
        recovery: "Use an InstantAttributePath whose ID type matches the link namespace."
      )
    }

    guard let reverseIdentity = linkAttribute.reverseIdentity else {
      throw derivationError(
        path: name,
        message: "Attribute '\(linkAttribute.id)' has no reverse identity.",
        recovery: "Declare reverseIdentity on the ref attribute before deriving a reverse relation."
      )
    }

    let prefix = Entity.instantNamespace + "/"
    guard reverseIdentity.hasPrefix(prefix) else {
      throw derivationError(
        path: name,
        message: "Reverse identity '\(reverseIdentity)' does not start with '\(prefix)'.",
        recovery:
          "Declare the reverse identity as '\(Entity.instantNamespace)/<relation-name>'."
      )
    }

    let relationName = String(reverseIdentity.dropFirst(prefix.count))
    guard !relationName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw derivationError(
        path: name,
        message: "Reverse identity '\(reverseIdentity)' does not contain a relation name.",
        recovery:
          "Declare the reverse identity as '\(Entity.instantNamespace)/<relation-name>'."
      )
    }

    return Self(relationName, attributeID: linkAttribute.id)
  }

  private static func derivationError(
    path: String,
    message: String,
    recovery: String
  ) -> InstantError {
    InstantError(
      code: .validationFailed,
      operation: "derive reverse include",
      namespace: Entity.instantNamespace,
      path: path,
      message: message,
      recovery: recovery
    )
  }

  fileprivate func validateIncludeRelation() {
    do {
      _ = try reverseAttribute()
    } catch {
      preconditionFailure("Invalid Instant reverse include relation '\(name)': \(error)")
    }
  }

  private func reverseAttribute() throws -> InstantAttribute {
    let reverseIdentity = "\(Entity.instantNamespace)/\(name)"
    guard
      let attribute = Target.instantAttributes.first(where: { attribute in
        attribute.valueType == .ref
          && attribute.linkNamespace == Entity.instantNamespace
          && attribute.reverseIdentity == reverseIdentity
          && (attributeID == nil || attribute.id == attributeID)
      })
    else {
      let attributeQualifier =
        attributeID.map { " with attribute id '\($0)'" } ?? ""
      throw InstantError(
        code: .validationFailed,
        operation: "build reverse include",
        namespace: Entity.instantNamespace,
        path: name,
        message:
          "No reverse relation '\(name)'\(attributeQualifier) links '\(Entity.instantNamespace)' to '\(Target.instantNamespace)'.",
        recovery:
          "Declare a ref attribute on \(Target.self) that links to '\(Entity.instantNamespace)' with reverse identity '\(reverseIdentity)'."
      )
    }

    try Target.validateUsableAttribute(
      attribute,
      operation: "build reverse include",
      path: name
    )
    return attribute
  }
}

public struct InstantReservedOrder<Entity: InstantEntityModel>: Hashable, Sendable {
  /// Orders by Instant's server-created metadata instead of a schema attribute.
  public static var serverCreatedAt: Self {
    Self(field: InstantQueryOrder.serverCreatedAtField)
  }

  let field: String

  private init(field: String) {
    self.field = field
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
    updatingPlan { $0.filters.append(predicate.filter) }
  }

  public func order<Value>(
    _ field: InstantAttributePath<Entity, Value>,
    _ direction: InstantQuerySortDirection = .ascending
  ) -> Self {
    updatingPlan { $0.order = InstantQueryOrder(field.name, direction) }
  }

  public func order(
    _ reserved: InstantReservedOrder<Entity>,
    _ direction: InstantQuerySortDirection = .ascending
  ) -> Self {
    updatingPlan { $0.order = InstantQueryOrder(reserved.field, direction) }
  }

  public func offset(_ offset: UInt) -> Self {
    updatingPlan { $0.offset = Int(clamping: offset) }
  }

  public func limit(_ limit: UInt) -> Self {
    updatingPlan { $0.limit = Int(clamping: limit) }
  }

  public func first(_ first: UInt) -> Self {
    updatingPlan {
      $0.first = Int(clamping: first)
      $0.last = nil
    }
  }

  public func after(_ cursor: InstantQueryCursor) -> Self {
    updatingPlan { $0.after = cursor }
  }

  public func last(_ last: UInt) -> Self {
    updatingPlan {
      $0.first = nil
      $0.last = Int(clamping: last)
    }
  }

  public func before(_ cursor: InstantQueryCursor) -> Self {
    updatingPlan { $0.before = cursor }
  }

  private func updatingPlan(_ update: (inout InstantQueryPlan) -> Void) -> Self {
    var copy = self
    update(&copy.plan)
    copy.plan.id = Self.queryID(
      filters: copy.plan.filters,
      order: copy.plan.order,
      offset: copy.plan.offset,
      limit: copy.plan.limit,
      first: copy.plan.first,
      after: copy.plan.after,
      last: copy.plan.last,
      before: copy.plan.before,
      selectedFields: copy.plan.selectedFields,
      includes: copy.plan.includes
    )
    return copy
  }

  public func select<Value>(
    _ field: InstantAttributePath<Entity, Value>
  ) -> Self {
    selecting([field.name])
  }

  public func select<Value>(
    _ fields: [InstantAttributePath<Entity, Value>]
  ) -> Self {
    selecting(fields.map(\.name))
  }

  public func select<Value0, Value1>(
    _ field0: InstantAttributePath<Entity, Value0>,
    _ field1: InstantAttributePath<Entity, Value1>
  ) -> Self {
    selecting([field0.name, field1.name])
  }

  public func select<Value0, Value1, Value2>(
    _ field0: InstantAttributePath<Entity, Value0>,
    _ field1: InstantAttributePath<Entity, Value1>,
    _ field2: InstantAttributePath<Entity, Value2>
  ) -> Self {
    selecting([field0.name, field1.name, field2.name])
  }

  public func select<Value0, Value1, Value2, Value3>(
    _ field0: InstantAttributePath<Entity, Value0>,
    _ field1: InstantAttributePath<Entity, Value1>,
    _ field2: InstantAttributePath<Entity, Value2>,
    _ field3: InstantAttributePath<Entity, Value3>
  ) -> Self {
    selecting([field0.name, field1.name, field2.name, field3.name])
  }

  public func select<Value0, Value1, Value2, Value3, Value4>(
    _ field0: InstantAttributePath<Entity, Value0>,
    _ field1: InstantAttributePath<Entity, Value1>,
    _ field2: InstantAttributePath<Entity, Value2>,
    _ field3: InstantAttributePath<Entity, Value3>,
    _ field4: InstantAttributePath<Entity, Value4>
  ) -> Self {
    selecting([field0.name, field1.name, field2.name, field3.name, field4.name])
  }

  public func select<Value0, Value1, Value2, Value3, Value4, Value5>(
    _ field0: InstantAttributePath<Entity, Value0>,
    _ field1: InstantAttributePath<Entity, Value1>,
    _ field2: InstantAttributePath<Entity, Value2>,
    _ field3: InstantAttributePath<Entity, Value3>,
    _ field4: InstantAttributePath<Entity, Value4>,
    _ field5: InstantAttributePath<Entity, Value5>
  ) -> Self {
    selecting([field0.name, field1.name, field2.name, field3.name, field4.name, field5.name])
  }

  public func include<Target: InstantEntityModel>(
    _ relation: InstantAttributePath<Entity, InstantID<Target>>,
    _ query: InstantEntityQuery<Target> = Target.query
  ) -> Self {
    relation.validateIncludeAttribute(target: Target.self)
    return including(relation.name, direction: .forward, query: query)
  }

  public func include<Target: InstantEntityModel>(
    _ relation: InstantReverseRelation<Entity, Target>,
    _ query: InstantEntityQuery<Target> = Target.query
  ) -> Self {
    relation.validateIncludeRelation()
    return including(relation.name, direction: .reverse, query: query)
  }

  private func including<Target: InstantEntityModel>(
    _ name: String,
    direction: InstantQueryIncludeDirection,
    query: InstantEntityQuery<Target>
  ) -> Self {
    let includePlan = query.plan
    precondition(
      includePlan.offset == nil
        && includePlan.limit == nil
        && includePlan.first == nil
        && includePlan.after == nil
        && includePlan.last == nil
        && includePlan.before == nil,
      "InstantEntityQuery.include does not support nested pagination."
    )

    var includes = (plan.includes ?? []).filter { $0.name != name }
    includes.append(
      InstantQueryInclude(
        name,
        direction: direction,
        query: InstantQueryIncludePlan(
          id: includePlan.id,
          namespace: includePlan.namespace,
          filters: includePlan.filters,
          order: includePlan.order,
          selectedFields: includePlan.selectedFields,
          includes: includePlan.includes ?? []
        )
      )
    )

    var copy = self
    copy.plan = InstantQueryPlan(
      id: Self.queryID(
        filters: copy.plan.filters,
        order: copy.plan.order,
        offset: copy.plan.offset,
        limit: copy.plan.limit,
        first: copy.plan.first,
        after: copy.plan.after,
        last: copy.plan.last,
        before: copy.plan.before,
        selectedFields: copy.plan.selectedFields,
        includes: includes
      ),
      namespace: copy.plan.namespace,
      filters: copy.plan.filters,
      order: copy.plan.order,
      offset: copy.plan.offset,
      limit: copy.plan.limit,
      first: copy.plan.first,
      after: copy.plan.after,
      last: copy.plan.last,
      before: copy.plan.before,
      selectedFields: copy.plan.selectedFields,
      includes: includes
    )
    return copy
  }

  private func selecting(_ fieldNames: [String]) -> Self {
    precondition(!fieldNames.isEmpty, "InstantEntityQuery.select requires at least one field.")
    let selectedFields = Array(Set(fieldNames)).sorted()
    var copy = self
    copy.plan = InstantQueryPlan(
      id: Self.queryID(
        filters: copy.plan.filters,
        order: copy.plan.order,
        offset: copy.plan.offset,
        limit: copy.plan.limit,
        first: copy.plan.first,
        after: copy.plan.after,
        last: copy.plan.last,
        before: copy.plan.before,
        selectedFields: selectedFields,
        includes: copy.plan.includes
      ),
      namespace: copy.plan.namespace,
      filters: copy.plan.filters,
      order: copy.plan.order,
      offset: copy.plan.offset,
      limit: copy.plan.limit,
      first: copy.plan.first,
      after: copy.plan.after,
      last: copy.plan.last,
      before: copy.plan.before,
      selectedFields: selectedFields,
      includes: copy.plan.includes ?? []
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
    selectedFields: [String]?,
    includes: [InstantQueryInclude]? = nil
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
      selectedFields: selectedFields,
      includes: includes
    )
    return "instant-query:" + payload.canonicalBase64ID()
  }
}

public typealias InstantQuery<Entity: InstantEntityModel> = InstantEntityQuery<Entity>

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
  var includes: [InstantQueryInclude]?

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

  public func queryOnce<Entity: InstantEntityModel>(
    _ query: InstantEntityQuery<Entity>
  ) async throws -> InstantQueryEmission {
    try await queryOnce(query.plan)
  }

  public func queryOnceDecoded<Entity: InstantEntityModel>(
    _ query: InstantEntityQuery<Entity>
  ) async throws -> (values: [Entity], pageInfo: InstantQueryPageInfo?) {
    let emission = try await queryOnce(query)
    return (try Entity.decode(emission.values), emission.pageInfo)
  }

  public func infiniteQueryInitialSnapshot<Entity: InstantEntityModel>(
    _ query: InstantEntityQuery<Entity>
  ) async throws -> InfiniteQuerySnapshot<Entity> {
    let snapshot = try await infiniteQueryInitialSnapshot(query.plan)
    return InfiniteQuerySnapshot(
      queryID: snapshot.queryID,
      sequence: snapshot.sequence,
      values: snapshot.error == nil ? try Entity.decode(snapshot.values) : [],
      pageInfo: snapshot.pageInfo,
      canLoadNextPage: snapshot.canLoadNextPage,
      error: snapshot.error
    )
  }

  public func subscribeInfiniteQuery<Entity: InstantEntityModel>(
    _ query: InstantEntityQuery<Entity>
  ) async -> InfiniteQuerySubscription<Entity> {
    let subscription = await subscribeInfiniteQuery(query.plan)
    let stream = AsyncThrowingStream<InfiniteQuerySnapshot<Entity>, Error>.makeStream(
      bufferingPolicy: .bufferingNewest(1)
    )
    let task = Task {
      for await snapshot in subscription.snapshots {
        do {
          try Task.checkCancellation()
          if let error = snapshot.error {
            stream.continuation.yield(
              InfiniteQuerySnapshot(
                queryID: snapshot.queryID,
                sequence: snapshot.sequence,
                values: [],
                pageInfo: snapshot.pageInfo,
                canLoadNextPage: snapshot.canLoadNextPage,
                error: error
              )
            )
            continue
          }
          stream.continuation.yield(
            InfiniteQuerySnapshot(
              queryID: snapshot.queryID,
              sequence: snapshot.sequence,
              values: try Entity.decode(snapshot.values),
              pageInfo: snapshot.pageInfo,
              canLoadNextPage: snapshot.canLoadNextPage,
              error: nil
            )
          )
        } catch {
          stream.continuation.finish(throwing: error)
          return
        }
      }
      stream.continuation.finish()
    }
    let upstreamCancellation = FetchSubscriptionCancellation {
      task.cancel()
      subscription.unsubscribe()
    }
    stream.continuation.onTermination = { @Sendable _ in
      upstreamCancellation.cancel()
    }
    return InfiniteQuerySubscription(
      stream: stream.stream,
      loadNextPage: {
        upstreamCancellation.unlessCancelled {
          subscription.loadNextPage()
        }
      },
      cancel: {
        upstreamCancellation.cancel()
        stream.continuation.finish()
      }
    )
  }

  @discardableResult
  public func save<Draft: InstantEntityDraft>(
    _ draft: Draft,
    localIDName: String? = nil,
    transactionID: String? = nil,
    createdAt: InstantTimestamp? = nil
  ) async throws -> Draft.Entity.ID {
    let prepared = try await prepareSave(draft, localIDName: localIDName)
    try await transact(id: transactionID, createdAt: createdAt) {
      prepared.mutation
    }
    return prepared.id
  }

  public func prepareSave<Draft: InstantEntityDraft>(
    _ draft: Draft,
    localIDName: String? = nil
  ) async throws -> InstantPreparedDraftSave<Draft.Entity> {
    let entityID: Draft.Entity.ID
    let mutation: InstantMutation
    if let id = draft.id {
      entityID = id
      mutation = Draft.Entity.update(id: id, draft.instantAssignments)
    } else {
      let rawID: String
      if let localIDName {
        rawID = try await localID(named: localIDName)
      } else if let runtime {
        rawID = runtime.configuration.makeID()
      } else {
        @Dependency(\.uuid) var uuid
        rawID = uuid().uuidString.lowercased()
      }
      entityID = InstantID<Draft.Entity>(rawValue: rawID)
      mutation = Draft.Entity.create(id: entityID, draft.instantAssignments)
    }

    return InstantPreparedDraftSave(id: entityID, mutation: mutation)
  }

  @discardableResult
  public func transact<Draft: InstantEntityDraft>(
    saving draft: Draft,
    localIDName: String? = nil,
    id explicitID: String? = nil,
    createdAt explicitCreatedAt: InstantTimestamp? = nil
  ) async throws -> InstantDraftSaveTransactionResult<Draft.Entity> {
    try await transact(
      saving: draft,
      localIDName: localIDName,
      id: explicitID,
      createdAt: explicitCreatedAt
    ) { _ in }
  }

  @discardableResult
  public func transact<Draft: InstantEntityDraft>(
    saving draft: Draft,
    localIDName: String? = nil,
    id explicitID: String? = nil,
    createdAt explicitCreatedAt: InstantTimestamp? = nil,
    @InstantMutationBuilder _ build: @Sendable (Draft.Entity.ID) throws -> [InstantMutation]
  ) async throws -> InstantDraftSaveTransactionResult<Draft.Entity> {
    let prepared = try await prepareSave(draft, localIDName: localIDName)
    let mutations = [prepared.mutation] + (try build(prepared.id))
    let transaction = try await transact(id: explicitID, createdAt: explicitCreatedAt) {
      for mutation in mutations {
        mutation
      }
    }
    return InstantDraftSaveTransactionResult(id: prepared.id, transaction: transaction)
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
