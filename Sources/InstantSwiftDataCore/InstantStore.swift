import Foundation

public struct InstantStoreMutationResult: Hashable, Codable, Sendable {
  public var transactionID: String
  public var changedEntityIDs: Set<String>
  public var tripleCount: Int
  public var emissions: [InstantQueryEmission]

  public init(
    transactionID: String,
    changedEntityIDs: Set<String>,
    tripleCount: Int,
    emissions: [InstantQueryEmission]
  ) {
    self.transactionID = transactionID
    self.changedEntityIDs = changedEntityIDs
    self.tripleCount = tripleCount
    self.emissions = emissions
  }
}

struct PreparedStoreMutation: Sendable {
  var result: InstantStoreMutationResult
  var snapshot: InstantStoreSnapshot
  var sequence: Int64
}

private struct StoreObserver: Sendable {
  var plan: InstantQueryPlan
  var continuation: AsyncStream<InstantQueryEmission>.Continuation
}

public actor InstantStore {
  private var attributes: AttributeStore
  private var indexes: TripleIndexes
  private var observers: [UUID: StoreObserver] = [:]
  private var sequence: Int64 = 0

  public init(snapshot: InstantStoreSnapshot = InstantStoreSnapshot()) {
    self.attributes = AttributeStore(attributes: snapshot.attributes)
    self.indexes = TripleIndexes(triples: snapshot.triples, attributes: self.attributes)
  }

  public func replaceAttributes(_ attributes: [InstantAttribute]) -> InstantStoreSnapshot {
    self.attributes.replaceAll(attributes)
    self.indexes = TripleIndexes(triples: self.indexes.triples, attributes: self.attributes)
    return snapshot()
  }

  public func replaceSnapshot(_ snapshot: InstantStoreSnapshot) {
    let changed = snapshot != self.snapshot()
    self.attributes = AttributeStore(attributes: snapshot.attributes)
    self.indexes = TripleIndexes(triples: snapshot.triples, attributes: self.attributes)
    if changed {
      sequence += 1
    }
  }

  public func mergeAttributes(_ attributes: [InstantAttribute]) -> InstantStoreSnapshot {
    self.attributes.merge(attributes)
    self.indexes = TripleIndexes(triples: self.indexes.triples, attributes: self.attributes)
    return snapshot()
  }

  public func snapshot() -> InstantStoreSnapshot {
    InstantStoreSnapshot(attributes: attributes.attributes, triples: indexes.triples)
  }

  public func materialize(_ plan: InstantQueryPlan) -> [InstantEntitySnapshot] {
    indexes.materialize(plan, attributes: attributes)
  }

  public func materializePage(_ plan: InstantQueryPlan) -> InstantQueryPage {
    indexes.materializePage(plan, attributes: attributes)
  }

  public func materializeEmission(_ plan: InstantQueryPlan) -> InstantQueryEmission {
    let page = indexes.materializePage(plan, attributes: attributes)
    return InstantQueryEmission(
      queryID: plan.id,
      sequence: sequence,
      values: page.values,
      pageInfo: page.pageInfo
    )
  }

  public func observe(_ plan: InstantQueryPlan) -> AsyncStream<InstantQueryEmission> {
    let observerID = UUID()
    let stream = AsyncStream<InstantQueryEmission>.makeStream(
      bufferingPolicy: .bufferingNewest(1)
    )
    registerObserver(id: observerID, plan: plan, continuation: stream.continuation)
    stream.continuation.onTermination = { @Sendable _ in
      Task {
        await self.cancelObservation(id: observerID)
      }
    }
    return stream.stream
  }

  func prepare(_ transaction: InstantStoreTransaction) throws -> PreparedStoreMutation {
    let prepared = try prepare(transaction, applyingTo: snapshot())
    return commit(prepared)
  }

  func prepare(
    _ transaction: InstantStoreTransaction,
    applyingTo snapshot: InstantStoreSnapshot
  ) throws -> PreparedStoreMutation {
    let attributes = AttributeStore(attributes: snapshot.attributes)
    var indexes = TripleIndexes(triples: snapshot.triples, attributes: attributes)
    var changedEntityIDs: Set<String> = []

    for operation in transaction.operations {
      switch operation {
      case let .requireEntityMissing(entityID, namespace):
        guard !indexes.containsEntity(entityID, namespace: namespace, attributes: attributes) else {
          throw Self.duplicateEntityError(entityID: entityID, namespace: namespace)
        }

      case let .requireEntityMissingByLookup(lookup, namespace):
        let attribute = try Self.validateLookup(
          lookup,
          expectedNamespace: namespace,
          attributes: attributes
        )
        let entityIDs = try Self.entityIDs(matching: lookup, in: indexes, attribute: attribute)
        if let entityID = entityIDs.first {
          throw Self.duplicateEntityError(
            lookup: lookup,
            entityID: entityID,
            attribute: attribute
          )
        }

      case let .requireEntityExists(entityID, namespace):
        guard indexes.containsEntity(entityID, namespace: namespace, attributes: attributes) else {
          throw Self.missingEntityError(entityID: entityID, namespace: namespace)
        }

      case let .requireEntityExistsByLookup(lookup, namespace):
        let attribute = try Self.validateLookup(
          lookup,
          expectedNamespace: namespace,
          attributes: attributes
        )
        let entityIDs = try Self.entityIDs(matching: lookup, in: indexes, attribute: attribute)
        guard !entityIDs.isEmpty else {
          throw Self.missingEntityError(lookup: lookup, attribute: attribute)
        }

      case .ruleParams:
        break

      case let .ruleParamsByLookup(lookup, namespace, _):
        _ = try Self.validateLookup(
          lookup,
          expectedNamespace: namespace,
          attributes: attributes
        )

      case .merge, .mergeByLookup, .insert, .insertByLookup, .retract, .retractByLookup,
        .deleteEntity, .deleteEntityByLookup:
        var resolvedLookups: [InstantLookupRef: String] = [:]
        let concreteOperations = try Self.concreteOperations(
          for: operation,
          indexes: indexes,
          attributes: attributes,
          resolvedLookups: &resolvedLookups
        )
        for concreteOperation in concreteOperations {
          switch concreteOperation {
          case let .merge(triple):
            if attributes[triple.attributeID]?.valueType == .ref {
              throw Self.unsupportedMergeError(triple: triple, attributes: attributes)
            }
            changedEntityIDs.formUnion(indexes.apply(concreteOperation, attributes: attributes))

          case .insert, .retract, .deleteEntity:
            changedEntityIDs.formUnion(indexes.apply(concreteOperation, attributes: attributes))

          case .requireEntityMissing, .requireEntityMissingByLookup,
            .requireEntityExists, .requireEntityExistsByLookup,
            .mergeByLookup, .insertByLookup, .retractByLookup,
            .deleteEntityByLookup, .ruleParams, .ruleParamsByLookup:
            break
          }
        }
      }
    }

    let nextSequence = sequence + 1
    let result = InstantStoreMutationResult(
      transactionID: transaction.id,
      changedEntityIDs: changedEntityIDs,
      tripleCount: indexes.triples.count,
      emissions: []
    )
    return PreparedStoreMutation(
      result: result,
      snapshot: InstantStoreSnapshot(attributes: attributes.attributes, triples: indexes.triples),
      sequence: nextSequence
    )
  }

  func commit(_ prepared: PreparedStoreMutation) -> PreparedStoreMutation {
    commit(prepared, shouldPublish: false)
  }

  func commitAndPublish(_ prepared: PreparedStoreMutation) -> PreparedStoreMutation {
    commit(prepared, shouldPublish: true)
  }

  private func commit(
    _ prepared: PreparedStoreMutation,
    shouldPublish: Bool
  ) -> PreparedStoreMutation {
    self.attributes = AttributeStore(attributes: prepared.snapshot.attributes)
    self.indexes = TripleIndexes(triples: prepared.snapshot.triples, attributes: self.attributes)
    self.sequence = prepared.sequence

    var emissionsByPlan: [InstantQueryPlan: InstantQueryEmission] = [:]
    for observer in observers.values {
      let emission: InstantQueryEmission
      if let existing = emissionsByPlan[observer.plan] {
        emission = existing
      } else {
        let page = indexes.materializePage(observer.plan, attributes: attributes)
        emission = InstantQueryEmission(
          queryID: observer.plan.id,
          sequence: sequence,
          values: page.values,
          pageInfo: page.pageInfo
        )
        emissionsByPlan[observer.plan] = emission
      }
      if shouldPublish {
        observer.continuation.yield(emission)
      }
    }
    var result = prepared.result
    result.emissions = emissionsByPlan
      .sorted { lhs, rhs in Self.emissionSortKey(lhs.key) < Self.emissionSortKey(rhs.key) }
      .map(\.value)
    return PreparedStoreMutation(result: result, snapshot: prepared.snapshot, sequence: sequence)
  }

  private static func emissionSortKey(_ plan: InstantQueryPlan) -> String {
    plan.cacheKey
  }

  private static func duplicateEntityError(entityID: String, namespace: String?) -> InstantError {
    InstantError(
      code: .validationFailed,
      operation: "strict create entity",
      namespace: namespace,
      localID: entityID,
      message: "An entity already exists for '\(entityID)'.",
      recovery: "Use update for upsert-style writes, or choose a fresh id before creating."
    )
  }

  private static func missingEntityError(entityID: String, namespace: String?) -> InstantError {
    InstantError(
      code: .validationFailed,
      operation: "strict update entity",
      namespace: namespace,
      localID: entityID,
      message: "No existing entity was found for '\(entityID)'.",
      recovery: "Create the entity before using a strict update, or use merge for upsert-style writes."
    )
  }

  private static func concreteOperations(
    for operation: InstantTripleOperation,
    indexes: TripleIndexes,
    attributes: AttributeStore,
    resolvedLookups: inout [InstantLookupRef: String]
  ) throws -> [InstantTripleOperation] {
    switch operation {
    case let .insert(triple):
      guard
        let value = try resolveLookupValue(
          triple.value,
          forAttributeID: triple.attributeID,
          indexes: indexes,
          attributes: attributes,
          resolvedLookups: &resolvedLookups
        )
      else { return [] }
      var triple = triple
      triple.value = value
      return [.insert(triple)]

    case let .merge(triple):
      guard
        let value = try resolveLookupValue(
          triple.value,
          forAttributeID: triple.attributeID,
          indexes: indexes,
          attributes: attributes,
          resolvedLookups: &resolvedLookups
        )
      else { return [] }
      var triple = triple
      triple.value = value
      return [.merge(triple)]

    case let .retract(triple):
      guard
        let value = try resolveLookupValue(
          triple.value,
          forAttributeID: triple.attributeID,
          indexes: indexes,
          attributes: attributes,
          resolvedLookups: &resolvedLookups
        )
      else { return [] }
      var triple = triple
      triple.value = value
      return [.retract(triple)]

    case .deleteEntity:
      return [operation]

    case let .insertByLookup(entity, attributeID, value, txID, txTime):
      guard
        let entityID = try resolveEntityID(
          entity,
          expectedNamespace: attributes[attributeID]?.namespace,
          indexes: indexes,
          attributes: attributes,
          resolvedLookups: &resolvedLookups
        ),
        let value = try resolveLookupValue(
          value,
          forAttributeID: attributeID,
          indexes: indexes,
          attributes: attributes,
          resolvedLookups: &resolvedLookups
        )
      else { return [] }
      return [
        .insert(
          InstantTriple(
            entityID: entityID,
            attributeID: attributeID,
            value: value,
            txID: txID,
            txTime: txTime
          )
        )
      ]

    case let .mergeByLookup(entity, attributeID, value, txID, txTime):
      if attributes[attributeID]?.valueType == .ref {
        throw unsupportedMergeError(
          triple: InstantTriple(
            entityID: entity.description,
            attributeID: attributeID,
            value: value,
            txID: txID,
            txTime: txTime
          ),
          attributes: attributes
        )
      }
      guard
        let entityID = try resolveEntityID(
          entity,
          expectedNamespace: attributes[attributeID]?.namespace,
          indexes: indexes,
          attributes: attributes,
          resolvedLookups: &resolvedLookups
        ),
        let value = try resolveLookupValue(
          value,
          forAttributeID: attributeID,
          indexes: indexes,
          attributes: attributes,
          resolvedLookups: &resolvedLookups
        )
      else { return [] }
      return [
        .merge(
          InstantTriple(
            entityID: entityID,
            attributeID: attributeID,
            value: value,
            txID: txID,
            txTime: txTime
          )
        )
      ]

    case let .retractByLookup(entity, attributeID, value, txID, txTime):
      guard
        let entityID = try resolveEntityID(
          entity,
          expectedNamespace: attributes[attributeID]?.namespace,
          indexes: indexes,
          attributes: attributes,
          resolvedLookups: &resolvedLookups
        ),
        let value = try resolveLookupValue(
          value,
          forAttributeID: attributeID,
          indexes: indexes,
          attributes: attributes,
          resolvedLookups: &resolvedLookups
        )
      else { return [] }
      return [
        .retract(
          InstantTriple(
            entityID: entityID,
            attributeID: attributeID,
            value: value,
            txID: txID,
            txTime: txTime
          )
        )
      ]

    case let .deleteEntityByLookup(lookup):
      guard
        let entityID = try resolveEntityID(
          lookup,
          expectedNamespace: nil,
          indexes: indexes,
          attributes: attributes,
          resolvedLookups: &resolvedLookups
        )
      else { return [] }
      return [.deleteEntity(entityID)]

    case .requireEntityMissing, .requireEntityMissingByLookup,
      .requireEntityExists, .requireEntityExistsByLookup,
      .ruleParams, .ruleParamsByLookup:
      return []
    }
  }

  private static func resolveLookupValue(
    _ value: InstantValue,
    forAttributeID attributeID: String,
    indexes: TripleIndexes,
    attributes: AttributeStore,
    resolvedLookups: inout [InstantLookupRef: String]
  ) throws -> InstantValue? {
    guard case let .lookupRef(lookup) = value else { return value }

    guard let attribute = attributes[attributeID] else {
      throw InstantError(
        code: .validationFailed,
        operation: "resolve lookup ref",
        path: attributeID,
        localID: lookup.description,
        message: "Lookup ref values require a declared destination attribute.",
        recovery: "Declare '\(attributeID)' before using a lookup ref as a triple value."
      )
    }

    let expectedNamespace = attribute.valueType == .ref ? attribute.linkNamespace : attribute.namespace
    guard
      let entityID = try resolveEntityID(
        lookup,
        expectedNamespace: expectedNamespace,
        indexes: indexes,
        attributes: attributes,
        resolvedLookups: &resolvedLookups
      )
    else { return nil }

    switch attribute.valueType {
    case .ref:
      return .ref(entityID)

    case .string where attribute.primaryKey || attribute.name == "id":
      return .string(entityID)

    case .string, .number, .boolean, .date, .json:
      throw InstantError(
        code: .validationFailed,
        operation: "resolve lookup ref",
        namespace: attribute.namespace,
        path: attribute.name,
        localID: lookup.description,
        message: "Lookup ref values can only fill id and ref attributes.",
        recovery: "Use lookup refs to identify the entity being written or to link to another entity."
      )
    }
  }

  private static func resolveEntityID(
    _ lookup: InstantLookupRef,
    expectedNamespace: String?,
    indexes: TripleIndexes,
    attributes: AttributeStore,
    resolvedLookups: inout [InstantLookupRef: String]
  ) throws -> String? {
    let attribute = try validateLookup(
      lookup,
      expectedNamespace: expectedNamespace,
      attributes: attributes
    )
    if let entityID = resolvedLookups[lookup] {
      return entityID
    }
    let entityIDs = try entityIDs(matching: lookup, in: indexes, attribute: attribute)
    guard let entityID = entityIDs.first else { return nil }
    resolvedLookups[lookup] = entityID
    return entityID
  }

  private static func validateLookup(
    _ lookup: InstantLookupRef,
    expectedNamespace: String?,
    attributes: AttributeStore
  ) throws -> InstantAttribute {
    guard let attribute = attributes[lookup.attributeID] else {
      throw InstantError(
        code: .validationFailed,
        operation: "lookup entity",
        path: lookup.attributeID,
        localID: lookup.description,
        message: "No attribute named '\(lookup.attributeID)' is declared for this lookup ref.",
        recovery: "Declare the lookup attribute in the schema before writing by lookup ref."
      )
    }

    if let expectedNamespace, attribute.namespace != expectedNamespace {
      throw InstantError(
        code: .validationFailed,
        operation: "lookup entity",
        namespace: expectedNamespace,
        path: attribute.name,
        localID: lookup.description,
        message:
          "Lookup attribute '\(attribute.id)' belongs to '\(attribute.namespace)', not '\(expectedNamespace)'.",
        recovery: "Use a lookup attribute from the same namespace as the entity being written."
      )
    }

    guard attribute.isUnique || attribute.primaryKey else {
      throw InstantError(
        code: .validationFailed,
        operation: "lookup entity",
        namespace: attribute.namespace,
        path: attribute.name,
        localID: lookup.description,
        message: "Attribute '\(attribute.id)' is not unique, so it cannot be used as a lookup ref.",
        recovery: "Mark the attribute unique in the schema, or write the entity by id."
      )
    }

    guard isLookupValue(lookup.value, compatibleWith: attribute) else {
      throw InstantError(
        code: .validationFailed,
        operation: "lookup entity",
        namespace: attribute.namespace,
        path: attribute.name,
        localID: lookup.description,
        message: "Lookup value does not match the declared type of '\(attribute.id)'.",
        recovery: "Use a lookup value whose Swift type matches the unique attribute."
      )
    }

    return attribute
  }

  private static func entityIDs(
    matching lookup: InstantLookupRef,
    in indexes: TripleIndexes,
    attribute: InstantAttribute
  ) throws -> [String] {
    let entityIDs = indexes.entityIDs(matching: lookup)
    guard entityIDs.count < 2 else {
      throw InstantError(
        code: .validationFailed,
        operation: "lookup entity",
        namespace: attribute.namespace,
        path: attribute.name,
        localID: lookup.description,
        message: "Lookup ref '\(lookup.description)' matched more than one local entity.",
        recovery: "Repair the local cache so unique attributes map to one entity before writing by lookup ref."
      )
    }
    return entityIDs
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

  private static func duplicateEntityError(
    lookup: InstantLookupRef,
    entityID: String,
    attribute: InstantAttribute
  ) -> InstantError {
    InstantError(
      code: .validationFailed,
      operation: "strict create entity",
      namespace: attribute.namespace,
      path: attribute.name,
      localID: entityID,
      message: "An entity already exists for lookup '\(lookup.description)'.",
      recovery: "Use update for upsert-style writes, or choose a fresh unique lookup value before creating."
    )
  }

  private static func missingEntityError(
    lookup: InstantLookupRef,
    attribute: InstantAttribute
  ) -> InstantError {
    InstantError(
      code: .validationFailed,
      operation: "strict update entity",
      namespace: attribute.namespace,
      path: attribute.name,
      localID: lookup.description,
      message: "No existing entity was found for lookup '\(lookup.description)'.",
      recovery: "Create the entity before using a strict update, or use update/merge for server-resolved upserts."
    )
  }

  private static func unsupportedMergeError(
    triple: InstantTriple,
    attributes: AttributeStore
  ) -> InstantError {
    let attribute = attributes[triple.attributeID]
    return InstantError(
      code: .validationFailed,
      operation: "merge entity attribute",
      namespace: attribute?.namespace,
      path: attribute?.name ?? triple.attributeID,
      localID: triple.entityID,
      message: "Merge is not supported for ref attributes.",
      recovery: "Use link/unlink for relationships, or merge only scalar and JSON attributes."
    )
  }

  private func registerObserver(
    id: UUID,
    plan: InstantQueryPlan,
    continuation: AsyncStream<InstantQueryEmission>.Continuation
  ) {
    observers[id] = StoreObserver(plan: plan, continuation: continuation)
    continuation.yield(materializeEmission(plan))
  }

  private func cancelObservation(id: UUID) {
    observers[id] = nil
  }
}
