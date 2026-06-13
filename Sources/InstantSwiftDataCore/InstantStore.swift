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
      case let .requireEntityExists(entityID, namespace):
        guard indexes.containsEntity(entityID, namespace: namespace, attributes: attributes) else {
          throw Self.missingEntityError(entityID: entityID, namespace: namespace)
        }

      case let .merge(triple):
        if attributes[triple.attributeID]?.valueType == .ref {
          throw Self.unsupportedMergeError(triple: triple, attributes: attributes)
        }
        changedEntityIDs.formUnion(indexes.apply(operation, attributes: attributes))

      case .insert, .retract, .deleteEntity:
        changedEntityIDs.formUnion(indexes.apply(operation, attributes: attributes))
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
