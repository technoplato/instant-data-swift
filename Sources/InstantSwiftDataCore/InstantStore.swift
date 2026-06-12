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

  func prepare(_ transaction: InstantStoreTransaction) -> PreparedStoreMutation {
    var changedEntityIDs: Set<String> = []

    for operation in transaction.operations {
      changedEntityIDs.formUnion(indexes.apply(operation, attributes: attributes))
    }

    sequence += 1
    let emissions = observers.values.map { observer in
      InstantQueryEmission(
        queryID: observer.plan.id,
        sequence: sequence,
        values: indexes.materialize(observer.plan, attributes: attributes)
      )
    }

    let result = InstantStoreMutationResult(
      transactionID: transaction.id,
      changedEntityIDs: changedEntityIDs,
      tripleCount: indexes.triples.count,
      emissions: emissions
    )
    return PreparedStoreMutation(result: result, snapshot: snapshot())
  }

  func publish(_ emissions: [InstantQueryEmission]) {
    for emission in emissions {
      for observer in observers.values where observer.plan.id == emission.queryID {
        observer.continuation.yield(emission)
      }
    }
  }

  private func registerObserver(
    id: UUID,
    plan: InstantQueryPlan,
    continuation: AsyncStream<InstantQueryEmission>.Continuation
  ) {
    observers[id] = StoreObserver(plan: plan, continuation: continuation)
    continuation.yield(
      InstantQueryEmission(
        queryID: plan.id,
        sequence: sequence,
        values: indexes.materialize(plan, attributes: attributes)
      )
    )
  }

  private func cancelObservation(id: UUID) {
    observers[id] = nil
  }
}
