import Foundation

public struct InstantTransportMutation: Hashable, Encodable, Sendable, Identifiable {
  public var id: String { mutationID }
  public var mutationID: String
  public var transactionID: String
  public var createdAt: InstantTimestamp
  public var status: InstantMutationStatus
  public var failureMessage: String?
  public var preconditions: [InstantTransportPrecondition]
  public var txSteps: [InstantTransportStep]

  public init(
    mutationID: String,
    transactionID: String,
    createdAt: InstantTimestamp,
    status: InstantMutationStatus,
    failureMessage: String? = nil,
    preconditions: [InstantTransportPrecondition],
    txSteps: [InstantTransportStep]
  ) {
    self.mutationID = mutationID
    self.transactionID = transactionID
    self.createdAt = createdAt
    self.status = status
    self.failureMessage = failureMessage
    self.preconditions = preconditions
    self.txSteps = txSteps
  }
}

extension InstantTransportMutation {
  public init(_ mutation: PendingMutation) {
    let lowered = mutation.transaction.loweredForTransport()
    self.init(
      mutationID: mutation.id,
      transactionID: mutation.transaction.id,
      createdAt: mutation.createdAt,
      status: mutation.status,
      failureMessage: mutation.failureMessage,
      preconditions: lowered.preconditions,
      txSteps: lowered.txSteps
    )
  }
}

enum InstantInstamlTransform {
  static func updateOperations(
    namespace: String,
    entityID: String,
    fields: [String: InstantValue?],
    txID: String,
    txTime: InstantTimestamp
  ) -> [InstantTripleOperation] {
    var operations: [InstantTripleOperation] = []
    for (field, value) in payloadFields(fields) {
      operations.append(
        .insert(
          InstantTriple(
            entityID: entityID,
            attributeID: "\(namespace)/\(field)",
            value: value,
            txID: txID,
            txTime: txTime
          )
        )
      )
    }
    operations.append(
      .insert(
        InstantTriple(
          entityID: entityID,
          attributeID: InstantAttribute.primaryKeyID(namespace: namespace),
          value: .string(entityID),
          txID: txID,
          txTime: txTime
        )
      )
    )
    return operations
  }

  static func updateOperations(
    namespace: String,
    entityLookup: InstantLookupRef,
    fields: [String: InstantValue?],
    txID: String,
    txTime: InstantTimestamp
  ) -> [InstantTripleOperation] {
    var operations: [InstantTripleOperation] = []
    for (field, value) in payloadFields(fields) {
      operations.append(
        .insertByLookup(
          entity: entityLookup,
          attributeID: "\(namespace)/\(field)",
          value: value,
          txID: txID,
          txTime: txTime
        )
      )
    }
    operations.append(
      .insertByLookup(
        entity: entityLookup,
        attributeID: InstantAttribute.primaryKeyID(namespace: namespace),
        value: .lookupRef(entityLookup),
        txID: txID,
        txTime: txTime
      )
    )
    return operations
  }

  private static func payloadFields(_ fields: [String: InstantValue?]) -> [(String, InstantValue)] {
    fields.keys.sorted().compactMap { field in
      guard field != "id", let value = fields[field] ?? nil else { return nil }
      return (field, value)
    }
  }
}

public struct InstantTransportPrecondition: Hashable, Encodable, Sendable {
  public enum Kind: String, Encodable, Sendable {
    case entityMissing = "entity-missing"
    case entityExists = "entity-exists"
    case tripleExists = "triple-exists"
  }

  public var kind: Kind
  public var entity: InstantTransportEntityRef
  public var namespace: String?
  public var attributeID: String?
  public var value: InstantTransportValue?

  public init(
    kind: Kind,
    entity: InstantTransportEntityRef,
    namespace: String?,
    attributeID: String? = nil,
    value: InstantTransportValue? = nil
  ) {
    self.kind = kind
    self.entity = entity
    self.namespace = namespace
    self.attributeID = attributeID
    self.value = value
  }
}

public enum InstantTransportEntityRef: Hashable, Encodable, Sendable {
  case id(String)
  case lookup(InstantLookupRef)

  public func encode(to encoder: Encoder) throws {
    switch self {
    case let .id(id):
      var container = encoder.singleValueContainer()
      try container.encode(id)

    case let .lookup(lookup):
      var container = encoder.unkeyedContainer()
      try container.encode(lookup.attributeID)
      try container.encode(InstantTransportValue(lookup.value))
    }
  }
}

public struct InstantTransportOptions: Hashable, Codable, Sendable {
  public enum Mode: String, Codable, Sendable {
    case create
    case update
  }

  public var mode: Mode

  public init(mode: Mode) {
    self.mode = mode
  }
}

public enum InstantTransportStep: Hashable, Encodable, Sendable {
  case addTriple(
    entity: InstantTransportEntityRef,
    attributeID: String,
    value: InstantTransportValue,
    options: InstantTransportOptions? = nil
  )
  case deepMergeTriple(
    entity: InstantTransportEntityRef,
    attributeID: String,
    value: InstantTransportValue,
    options: InstantTransportOptions? = nil
  )
  case retractTriple(
    entity: InstantTransportEntityRef,
    attributeID: String,
    value: InstantTransportValue
  )
  case deleteEntity(entity: InstantTransportEntityRef, namespace: String?)
  case ruleParams(entity: InstantTransportEntityRef, namespace: String, params: InstantTransportValue)

  public func encode(to encoder: Encoder) throws {
    var container = encoder.unkeyedContainer()

    switch self {
    case let .addTriple(entity, attributeID, value, options):
      try container.encode("add-triple")
      try container.encode(entity)
      try container.encode(attributeID)
      try container.encode(value)
      if let options {
        try container.encode(options)
      }

    case let .deepMergeTriple(entity, attributeID, value, options):
      try container.encode("deep-merge-triple")
      try container.encode(entity)
      try container.encode(attributeID)
      try container.encode(value)
      if let options {
        try container.encode(options)
      }

    case let .retractTriple(entity, attributeID, value):
      try container.encode("retract-triple")
      try container.encode(entity)
      try container.encode(attributeID)
      try container.encode(value)

    case let .deleteEntity(entity, namespace):
      try container.encode("delete-entity")
      try container.encode(entity)
      if let namespace {
        try container.encode(namespace)
      }

    case let .ruleParams(entity, namespace, params):
      try container.encode("rule-params")
      try container.encode(entity)
      try container.encode(namespace)
      try container.encode(params)
    }
  }
}

public indirect enum InstantTransportValue: Hashable, Encodable, Sendable {
  case null
  case bool(Bool)
  case number(Double)
  case string(String)
  case array([Self])
  case object([String: Self])
  case lookupRef(attributeID: String, value: Self)

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
      self = .string(Self.iso8601String(from: value))
    case let .json(value):
      self.init(value)
    case let .ref(value):
      self = .string(value)
    case let .lookupRef(lookup):
      self = .lookupRef(attributeID: lookup.attributeID, value: Self(lookup.value))
    }
  }

  public init(_ value: InstantLookupValue) {
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
      self = .string(Self.iso8601String(from: value))
    case let .json(value):
      self.init(value)
    case let .ref(value):
      self = .string(value)
    }
  }

  public init(_ value: JSONValue) {
    switch value {
    case .null:
      self = .null
    case let .bool(value):
      self = .bool(value)
    case let .number(value):
      self = .number(value)
    case let .string(value):
      self = .string(value)
    case let .array(values):
      self = .array(values.map(Self.init))
    case let .object(values):
      self = .object(values.mapValues(Self.init))
    }
  }

  public func encode(to encoder: Encoder) throws {
    switch self {
    case .null:
      var container = encoder.singleValueContainer()
      try container.encodeNil()

    case let .bool(value):
      var container = encoder.singleValueContainer()
      try container.encode(value)

    case let .number(value):
      var container = encoder.singleValueContainer()
      try container.encode(value)

    case let .string(value):
      var container = encoder.singleValueContainer()
      try container.encode(value)

    case let .array(values):
      var container = encoder.unkeyedContainer()
      for value in values {
        try container.encode(value)
      }

    case let .object(values):
      var container = encoder.container(keyedBy: DynamicCodingKey.self)
      for key in values.keys.sorted() {
        try container.encode(values[key], forKey: DynamicCodingKey(key))
      }

    case let .lookupRef(attributeID, value):
      var container = encoder.unkeyedContainer()
      try container.encode(attributeID)
      try container.encode(value)
    }
  }

  private static func iso8601String(from date: Date) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.string(from: date)
  }
}

extension InstantStoreTransaction {
  fileprivate func loweredForTransport() -> (
    preconditions: [InstantTransportPrecondition],
    txSteps: [InstantTransportStep]
  ) {
    var preconditions: [InstantTransportPrecondition] = []
    var modes: [InstantTransportEntityRef: InstantTransportOptions.Mode] = [:]
    var namespaces: [InstantTransportEntityRef: String] = [:]
    var txSteps: [InstantTransportStep] = []

    for operation in operations {
      switch operation {
      case let .requireEntityMissing(entityID, namespace):
        let entity = InstantTransportEntityRef.id(entityID)
        preconditions.append(
          InstantTransportPrecondition(kind: .entityMissing, entity: entity, namespace: namespace)
        )
        modes[entity] = .create
        namespaces[entity] = namespace

      case let .requireEntityMissingByLookup(lookup, namespace):
        let entity = InstantTransportEntityRef.lookup(lookup)
        preconditions.append(
          InstantTransportPrecondition(kind: .entityMissing, entity: entity, namespace: namespace)
        )
        modes[entity] = .create
        namespaces[entity] = namespace

      case let .requireEntityExists(entityID, namespace):
        let entity = InstantTransportEntityRef.id(entityID)
        guard modes[entity] != .create || namespaces[entity] != namespace else {
          continue
        }
        preconditions.append(
          InstantTransportPrecondition(kind: .entityExists, entity: entity, namespace: namespace)
        )
        modes[entity] = .update
        namespaces[entity] = namespace

      case let .requireEntityExistsByLookup(lookup, namespace):
        let entity = InstantTransportEntityRef.lookup(lookup)
        guard modes[entity] != .create || namespaces[entity] != namespace else {
          continue
        }
        preconditions.append(
          InstantTransportPrecondition(kind: .entityExists, entity: entity, namespace: namespace)
        )
        modes[entity] = .update
        namespaces[entity] = namespace

      case let .requireTripleExists(entityID, attributeID, value):
        preconditions.append(
          InstantTransportPrecondition(
            kind: .tripleExists,
            entity: .id(entityID),
            namespace: nil,
            attributeID: attributeID,
            value: InstantTransportValue(value)
          )
        )

      case let .merge(triple):
        let entity = InstantTransportEntityRef.id(triple.entityID)
        txSteps.append(
          .deepMergeTriple(
            entity: entity,
            attributeID: triple.attributeID,
            value: InstantTransportValue(triple.value),
            options: modes[entity].map(InstantTransportOptions.init(mode:))
          )
        )

      case let .mergeByLookup(entityLookup, attributeID, value, _, _):
        let entity = InstantTransportEntityRef.lookup(entityLookup)
        txSteps.append(
          .deepMergeTriple(
            entity: entity,
            attributeID: attributeID,
            value: InstantTransportValue(value),
            options: modes[entity].map(InstantTransportOptions.init(mode:))
          )
        )

      case let .insert(triple):
        let entity = InstantTransportEntityRef.id(triple.entityID)
        txSteps.append(
          .addTriple(
            entity: entity,
            attributeID: triple.attributeID,
            value: InstantTransportValue(triple.value),
            options: modes[entity].map(InstantTransportOptions.init(mode:))
          )
        )

      case let .insertByLookup(entityLookup, attributeID, value, _, _):
        let entity = InstantTransportEntityRef.lookup(entityLookup)
        txSteps.append(
          .addTriple(
            entity: entity,
            attributeID: attributeID,
            value: InstantTransportValue(value),
            options: modes[entity].map(InstantTransportOptions.init(mode:))
          )
        )

      case let .retract(triple):
        txSteps.append(
          .retractTriple(
            entity: .id(triple.entityID),
            attributeID: triple.attributeID,
            value: InstantTransportValue(triple.value)
          )
        )

      case let .retractByLookup(entityLookup, attributeID, value, _, _):
        txSteps.append(
          .retractTriple(
            entity: .lookup(entityLookup),
            attributeID: attributeID,
            value: InstantTransportValue(value)
          )
        )

      case let .deleteEntity(entityID):
        let entity = InstantTransportEntityRef.id(entityID)
        txSteps.append(.deleteEntity(entity: entity, namespace: namespaces[entity]))

      case let .deleteEntityInNamespace(entityID, namespace):
        txSteps.append(.deleteEntity(entity: .id(entityID), namespace: namespace))

      case let .deleteEntityByLookup(lookup):
        let entity = InstantTransportEntityRef.lookup(lookup)
        txSteps.append(
          .deleteEntity(
            entity: entity,
            namespace: namespaces[entity] ?? Self.namespace(in: lookup.attributeID)
          )
        )

      case let .ruleParams(entityID, namespace, params):
        txSteps.append(
          .ruleParams(
            entity: .id(entityID),
            namespace: namespace,
            params: InstantTransportValue(params)
          )
        )

      case let .ruleParamsByLookup(entityLookup, namespace, params):
        txSteps.append(
          .ruleParams(
            entity: .lookup(entityLookup),
            namespace: namespace,
            params: InstantTransportValue(params)
          )
        )
      }
    }

    return (preconditions, txSteps)
  }

  private static func namespace(in attributeID: String) -> String? {
    guard let separator = attributeID.firstIndex(of: "/"), separator != attributeID.startIndex
    else { return nil }
    return String(attributeID[..<separator])
  }
}

private struct DynamicCodingKey: CodingKey {
  var stringValue: String
  var intValue: Int?

  init(_ stringValue: String) {
    self.stringValue = stringValue
    self.intValue = nil
  }

  init?(stringValue: String) {
    self.init(stringValue)
  }

  init?(intValue: Int) {
    self.stringValue = "\(intValue)"
    self.intValue = intValue
  }
}
