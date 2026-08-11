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
  var sequence: Int64
  var attributes: AttributeStore
  var indexes: TripleIndexes
  var previousChangedEntityTriples: [String: [InstantTriple]]
  var deferredValueRemovalMetrics: TripleIndexes.DeferredValueRemovalMetrics
  private var preparedSnapshot: InstantStoreSnapshot?

  var snapshot: InstantStoreSnapshot {
    preparedSnapshot
      ?? InstantStoreSnapshot(attributes: attributes.attributes, triples: indexes.triples)
  }

  var changedEntityTriples: [String: [InstantTriple]] {
    Dictionary(
      uniqueKeysWithValues: result.changedEntityIDs.map { entityID in
        (entityID, indexes.triples(entityID: entityID))
      }
    )
  }

  init(
    result: InstantStoreMutationResult,
    snapshot: InstantStoreSnapshot,
    sequence: Int64
  ) {
    let attributes = AttributeStore(attributes: snapshot.attributes)
    self.init(
      result: result,
      sequence: sequence,
      attributes: attributes,
      indexes: TripleIndexes(triples: snapshot.triples, attributes: attributes),
      previousChangedEntityTriples: [:],
      snapshot: snapshot
    )
  }

  init(
    result: InstantStoreMutationResult,
    sequence: Int64,
    attributes: AttributeStore,
    indexes: TripleIndexes,
    previousChangedEntityTriples: [String: [InstantTriple]] = [:],
    deferredValueRemovalMetrics: TripleIndexes.DeferredValueRemovalMetrics = .init(),
    snapshot: InstantStoreSnapshot? = nil
  ) {
    self.result = result
    self.sequence = sequence
    self.attributes = attributes
    self.indexes = indexes
    self.previousChangedEntityTriples = previousChangedEntityTriples
    self.deferredValueRemovalMetrics = deferredValueRemovalMetrics
    self.preparedSnapshot = snapshot
  }
}

private struct StoreObserver: Sendable {
  var plan: InstantQueryPlan
  var remotePageInfo: InstantQueryRemotePageInfo?
  var liveQueryKey: String?
  var continuation: AsyncStream<InstantQueryEmission>.Continuation
}

private struct StoreObservationKey: Hashable {
  var plan: InstantQueryPlan
  var remotePageInfo: InstantQueryRemotePageInfo?
}

struct InstantStoreQueryObservationLease: Sendable {
  var stream: AsyncStream<InstantQueryEmission>
  var cancel: @Sendable () async -> Void
}

private final class InstantStoreObservationTermination: Sendable {
  private let owner: InstantAsyncCancellationOwner

  init(_ action: @escaping @Sendable () async -> Void) {
    self.owner = InstantAsyncCancellationOwner(cancelAndWait: action)
  }

  func run() async {
    owner.cancel()
    await owner.wait()
  }
}

public actor InstantStore {
  private var attributes: AttributeStore
  private var indexes: TripleIndexes
  private let deferredValueResidency: InstantDeferredValueResidencyPolicy
  private var observers: [UUID: StoreObserver] = [:]
  private var sequence: Int64 = 0

  public init(
    snapshot: InstantStoreSnapshot = InstantStoreSnapshot(),
    deferredValueResidency: InstantDeferredValueResidencyPolicy = .none
  ) {
    self.deferredValueResidency = deferredValueResidency
    self.attributes = AttributeStore(attributes: snapshot.attributes)
    self.indexes = TripleIndexes(
      triples: snapshot.triples,
      attributes: self.attributes,
      excludingAttributeIDs: deferredValueResidency.attributeIDs
    )
  }

  public func replaceAttributes(_ attributes: [InstantAttribute]) -> InstantStoreSnapshot {
    self.attributes.replaceAll(attributes)
    self.indexes = TripleIndexes(triples: self.indexes.triples, attributes: self.attributes)
    return snapshot()
  }

  public func replaceSnapshot(_ snapshot: InstantStoreSnapshot) {
    let changed = snapshot != self.snapshot()
    self.attributes = AttributeStore(attributes: snapshot.attributes)
    self.indexes = TripleIndexes(
      triples: snapshot.triples,
      attributes: self.attributes,
      excludingAttributeIDs: deferredValueResidency.attributeIDs
    )
    if changed {
      sequence += 1
    }
  }

  public func mergeAttributes(_ attributes: [InstantAttribute]) -> InstantStoreSnapshot {
    mergeAttributesIfChanged(attributes) ?? snapshot()
  }

  func mergeAttributesIfChanged(
    _ attributes: [InstantAttribute]
  ) -> InstantStoreSnapshot? {
    var mergedAttributes = self.attributes
    mergedAttributes.merge(attributes)
    guard mergedAttributes != self.attributes else { return nil }
    self.attributes = mergedAttributes
    self.indexes = TripleIndexes(triples: self.indexes.triples, attributes: self.attributes)
    return snapshot()
  }

  func attributeSnapshot() -> [InstantAttribute] {
    attributes.attributes
  }

  func currentSequence() -> Int64 {
    sequence
  }

  public func snapshot() -> InstantStoreSnapshot {
    InstantStoreSnapshot(attributes: attributes.attributes, triples: indexes.triples)
  }

  func visibleWriteFilter(
    for keys: Set<InstantVisibleWriteKey>
  ) -> InstantVisibleWriteFilter {
    var attributesByID: [String: InstantAttribute] = [:]
    var newestVisibleWrite: [InstantVisibleWriteKey: InstantTimestamp] = [:]
    attributesByID.reserveCapacity(keys.count)
    newestVisibleWrite.reserveCapacity(keys.count)
    for key in keys {
      if let attribute = attributes[key.attributeID] {
        attributesByID[key.attributeID] = attribute
      }
      if let timestamp = indexes.newestWriteTime(
        entityID: key.entityID,
        attributeID: key.attributeID
      ) {
        newestVisibleWrite[key] = timestamp
      }
    }
    return InstantVisibleWriteFilter(
      attributesByID: attributesByID,
      newestVisibleWrite: newestVisibleWrite
    )
  }

  public func materialize(
    _ plan: InstantQueryPlan,
    remotePageInfo: InstantQueryRemotePageInfo? = nil
  ) -> [InstantEntitySnapshot] {
    indexes.materialize(plan, attributes: attributes, remotePageInfo: remotePageInfo)
  }

  /// In-actor microbench: iterations of materialize without inter-call actor hops.
  /// Used to compare pure store latency to TypeScript `@instantdb/core` store scans.
  package func measureMaterializeAverageNanoseconds(
    _ plan: InstantQueryPlan,
    iterations: Int
  ) -> (averageNanoseconds: Double, lastCount: Int) {
    precondition(iterations > 0)
    var total: UInt64 = 0
    var lastCount = 0
    for _ in 0..<iterations {
      let t0 = DispatchTime.now().uptimeNanoseconds
      let rows = indexes.materialize(plan, attributes: attributes)
      let t1 = DispatchTime.now().uptimeNanoseconds
      total += t1 - t0
      lastCount = rows.count
    }
    return (Double(total) / Double(iterations), lastCount)
  }

  public func materializeInstaQL(
    _ plan: InstantQueryPlan,
    remotePageInfo: InstantQueryRemotePageInfo? = nil,
    cardinalityInference: Bool = true
  ) -> [InstantInstaQLObject] {
    InstantInstaQLProjection.project(
      indexes.materialize(plan, attributes: attributes, remotePageInfo: remotePageInfo),
      plan: plan,
      attributes: attributes,
      cardinalityInference: cardinalityInference
    )
  }

  public func materializePage(
    _ plan: InstantQueryPlan,
    remotePageInfo: InstantQueryRemotePageInfo? = nil
  ) -> InstantQueryPage {
    indexes.materializePage(plan, attributes: attributes, remotePageInfo: remotePageInfo)
  }

  func materializePageWithMetrics(
    _ plan: InstantQueryPlan,
    remotePageInfo: InstantQueryRemotePageInfo? = nil
  ) -> (page: InstantQueryPage, metrics: TripleIndexes.QueryMaterializationMetrics) {
    indexes.materializePageWithMetrics(
      plan,
      attributes: attributes,
      remotePageInfo: remotePageInfo
    )
  }

  public func materializeEmission(
    _ plan: InstantQueryPlan,
    remotePageInfo: InstantQueryRemotePageInfo? = nil
  ) -> InstantQueryEmission {
    let page = indexes.materializePage(plan, attributes: attributes, remotePageInfo: remotePageInfo)
    return InstantQueryEmission(
      queryID: plan.id,
      sequence: sequence,
      values: page.values,
      pageInfo: page.pageInfo
    )
  }

  public func observe(
    _ plan: InstantQueryPlan,
    remotePageInfo: InstantQueryRemotePageInfo? = nil
  ) -> AsyncStream<InstantQueryEmission> {
    observeQueryLease(
      plan,
      remotePageInfo: remotePageInfo
    ).stream
  }

  func observeQueryLease(
    _ plan: InstantQueryPlan,
    remotePageInfo: InstantQueryRemotePageInfo? = nil,
    onCancellationStarted: (@Sendable () async -> Void)? = nil
  ) -> InstantStoreQueryObservationLease {
    observeLease(
      plan,
      remotePageInfo: remotePageInfo,
      liveQueryKey: nil,
      onCancellationStarted: onCancellationStarted
    )
  }

  func observeInfiniteQueryLease(
    _ plan: InstantQueryPlan,
    onCancellationStarted: (@Sendable () async -> Void)? = nil
  ) -> InstantStoreQueryObservationLease {
    observeLease(
      plan,
      remotePageInfo: nil,
      liveQueryKey: nil,
      onCancellationStarted: onCancellationStarted
    )
  }

  func observeLiveQueryLease(
    _ plan: InstantQueryPlan,
    registrationKey: String,
    remotePageInfo: InstantQueryRemotePageInfo?,
    onCancellationStarted: (@Sendable () async -> Void)? = nil
  ) -> InstantStoreQueryObservationLease {
    observeLease(
      plan,
      remotePageInfo: remotePageInfo,
      liveQueryKey: registrationKey,
      onCancellationStarted: onCancellationStarted
    )
  }

  private func observeLease(
    _ plan: InstantQueryPlan,
    remotePageInfo: InstantQueryRemotePageInfo?,
    liveQueryKey: String?,
    onCancellationStarted: (@Sendable () async -> Void)? = nil
  ) -> InstantStoreQueryObservationLease {
    let observerID = UUID()
    let stream = AsyncStream<InstantQueryEmission>.makeStream(
      bufferingPolicy: .bufferingNewest(1)
    )
    registerObserver(
      id: observerID,
      plan: plan,
      remotePageInfo: remotePageInfo,
      liveQueryKey: liveQueryKey,
      continuation: stream.continuation
    )
    let termination = InstantStoreObservationTermination { [weak self] in
      await onCancellationStarted?()
      guard let self else { return }
      await self.cancelObservation(id: observerID)
    }
    stream.continuation.onTermination = { @Sendable _ in
      Task {
        await termination.run()
      }
    }
    return InstantStoreQueryObservationLease(
      stream: stream.stream,
      cancel: {
        stream.continuation.finish()
        await termination.run()
      }
    )
  }

  func installLiveQueryPageInfo(
    _ replacements: [InstantLiveQueryResultReplacement],
    publishing: Bool
  ) {
    guard !replacements.isEmpty else { return }
    let replacementsByKey = Dictionary(
      replacements.map { ($0.key, $0) },
      uniquingKeysWith: { _, latest in latest }
    )
    for observerID in Array(observers.keys) {
      guard var observer = observers[observerID],
        let liveQueryKey = observer.liveQueryKey,
        let replacement = replacementsByKey[liveQueryKey]
      else {
        continue
      }
      observer.remotePageInfo =
        replacement.pageInfo.map(InstantQueryRemotePageInfo.ready) ?? .waiting
      observers[observerID] = observer
      guard publishing else { continue }
      observer.continuation.yield(
        materializeEmission(
          observer.plan,
          remotePageInfo: observer.remotePageInfo
        )
      )
    }
  }

  func prepare(_ transaction: InstantStoreTransaction) throws -> PreparedStoreMutation {
    let prepared = try prepare(
      transaction,
      attributes: attributes,
      indexes: indexes
    )
    return commit(prepared)
  }

  func prepareCurrent(_ transaction: InstantStoreTransaction) throws -> PreparedStoreMutation {
    try prepare(
      transaction,
      attributes: attributes,
      indexes: indexes
    )
  }

  func prepareCurrent(
    _ transaction: InstantStoreTransaction,
    hydratingDeferredValues deferredTriples: [InstantTriple]
  ) throws -> PreparedStoreMutation {
    var indexes = indexes
    indexes.hydrateDeferredValues(deferredTriples, attributes: attributes)
    return try prepare(
      transaction,
      attributes: attributes,
      indexes: indexes
    )
  }

  func resolvedMutationEntityIDs(
    in transaction: InstantStoreTransaction
  ) throws -> Set<String> {
    var entityIDs: Set<String> = []
    var resolvedLookups: [InstantLookupRef: String] = [:]
    for operation in transaction.operations {
      for concreteOperation in try Self.concreteOperations(
        for: operation,
        indexes: indexes,
        attributes: attributes,
        resolvedLookups: &resolvedLookups
      ) {
        switch concreteOperation {
        case let .merge(triple), let .insert(triple), let .retract(triple):
          entityIDs.insert(triple.entityID)
        case let .deleteEntity(entityID), let .deleteEntityInNamespace(entityID, _):
          entityIDs.insert(entityID)
        case .requireEntityMissing, .requireEntityMissingByLookup,
          .requireEntityExists, .requireEntityExistsByLookup,
          .requireTripleExists, .mergeByLookup, .insertByLookup, .retractByLookup,
          .deleteEntityByLookup, .ruleParams, .ruleParamsByLookup:
          break
        }
      }
    }
    return entityIDs
  }

  func prepare(
    _ transaction: InstantStoreTransaction,
    applyingTo snapshot: InstantStoreSnapshot
  ) throws -> PreparedStoreMutation {
    let attributes = AttributeStore(attributes: snapshot.attributes)
    let indexes = TripleIndexes(
      triples: snapshot.triples,
      attributes: attributes,
      markingDeferredAttributeIDs: deferredValueResidency.attributeIDs
    )
    return try prepare(
      transaction,
      attributes: attributes,
      indexes: indexes
    )
  }

  func prepare(
    _ transaction: InstantStoreTransaction,
    applyingTo prepared: PreparedStoreMutation
  ) throws -> PreparedStoreMutation {
    try prepare(
      transaction,
      attributes: prepared.attributes,
      indexes: prepared.indexes
    )
  }

  /// Peel durable optimistic overlays, then apply a server transaction, without
  /// re-materializing `InstantStoreSnapshot.triples` or re-entering the actor
  /// between steps.
  ///
  /// Live apply used to call `prepare(_:applyingTo: InstantStoreSnapshot)` once
  /// per pending mutation. Each call rebuilt `TripleIndexes` from every triple,
  /// and even the prepared-chain form paid an O(store) Dictionary CoW copy on
  /// every actor hop. Upstream Instant mutates eav/aev/vae in place via
  /// `transact` / `addTriple`
  /// (`upstream/instant/client/packages/core/src/store.ts`). Keeping indexes in
  /// a single uniquely-owned local value for the whole peel+apply matches that
  /// shape and is what stops multi-core thrash on Mac Scribe (#044).
  func prepare(
    peelingOverlays rollbacks: [InstantStoreTransaction],
    thenApplying serverTransaction: InstantStoreTransaction,
    to snapshot: InstantStoreSnapshot
  ) throws -> PreparedStoreMutation {
    var attributes = AttributeStore(attributes: snapshot.attributes)
    var indexes = TripleIndexes(
      triples: snapshot.triples,
      attributes: attributes,
      markingDeferredAttributeIDs: deferredValueResidency.attributeIDs
    )
    for rollback in rollbacks {
      _ = try prepareMutating(
        rollback,
        attributes: &attributes,
        indexes: &indexes,
        capturePreviousChangedEntityTriples: false
      )
    }
    return try prepareMutating(
      serverTransaction,
      attributes: &attributes,
      indexes: &indexes,
      capturePreviousChangedEntityTriples: true
    )
  }

  /// Peel overlays + apply server tx starting from the **already-hot** indexes.
  ///
  /// Prefer this over `to: InstantStoreSnapshot` so live apply does not rebuild
  /// `TripleIndexes` from a second full triples array. That second array is the
  /// dual-residency floor (`SQLitePersistenceStore.cachedState` + InstantStore)
  /// called out in production readiness P2.1 / #044.
  ///
  /// Upstream: `Reactor` mutates one in-memory store (`store.ts` addTriple /
  /// transact) — not snapshot rebuilds.
  func prepare(
    peelingOverlays rollbacks: [InstantStoreTransaction],
    thenApplying serverTransaction: InstantStoreTransaction,
    mergingAttributes attributesToMerge: [InstantAttribute] = []
  ) throws -> PreparedStoreMutation {
    try prepare(
      peelingOverlays: rollbacks,
      thenApplying: serverTransaction,
      mergingAttributes: attributesToMerge,
      hydratingDeferredValues: []
    )
  }

  func prepare(
    peelingOverlays rollbacks: [InstantStoreTransaction],
    thenApplying serverTransaction: InstantStoreTransaction,
    mergingAttributes attributesToMerge: [InstantAttribute] = [],
    hydratingDeferredValues deferredTriples: [InstantTriple]
  ) throws -> PreparedStoreMutation {
    var attributes = self.attributes
    attributes.merge(attributesToMerge)
    var indexes = self.indexes
    indexes.hydrateDeferredValues(deferredTriples, attributes: attributes)
    for rollback in rollbacks {
      _ = try prepareMutating(
        rollback,
        attributes: &attributes,
        indexes: &indexes,
        capturePreviousChangedEntityTriples: false
      )
    }
    return try prepareMutating(
      serverTransaction,
      attributes: &attributes,
      indexes: &indexes,
      capturePreviousChangedEntityTriples: true
    )
  }

  private func prepare(
    _ transaction: InstantStoreTransaction,
    attributes: AttributeStore,
    indexes initialIndexes: TripleIndexes
  ) throws -> PreparedStoreMutation {
    var attributes = attributes
    var indexes = initialIndexes
    return try prepareMutating(
      transaction,
      attributes: &attributes,
      indexes: &indexes,
      capturePreviousChangedEntityTriples: true
    )
  }

  private func prepareMutating(
    _ transaction: InstantStoreTransaction,
    attributes: inout AttributeStore,
    indexes: inout TripleIndexes,
    capturePreviousChangedEntityTriples: Bool
  ) throws -> PreparedStoreMutation {
    let previousChangedEntityTriplesBase: TripleIndexes? =
      capturePreviousChangedEntityTriples ? indexes : nil
    indexes.reserveCapacity(
      entityCapacity: transaction.operations.count,
      attributeCapacity: attributes.count
    )
    var changedEntityIDs: Set<String> = []

    for operation in transaction.operations {
      switch operation {
      case let .requireEntityMissing(entityID, namespace):
        guard !indexes.containsEntity(entityID, namespace: namespace, attributes: attributes) else {
          throw Self.duplicateEntityError(entityID: entityID, namespace: namespace)
        }

      case let .requireEntityMissingByLookup(lookup, namespace):
        let lookupAttribute = try Self.validateLookup(
          lookup,
          expectedNamespace: namespace,
          attributes: attributes
        )
        let entityIDs = try Self.entityIDs(
          matching: lookup,
          in: indexes,
          lookupAttribute: lookupAttribute
        )
        if let entityID = entityIDs.first {
          throw Self.duplicateEntityError(
            lookup: lookup,
            entityID: entityID,
            attribute: lookupAttribute.attribute
          )
        }

      case let .requireEntityExists(entityID, namespace):
        guard indexes.containsEntity(entityID, namespace: namespace, attributes: attributes) else {
          throw Self.missingEntityError(entityID: entityID, namespace: namespace)
        }

      case let .requireTripleExists(entityID, attributeID, value):
        guard
          indexes.containsTriple(
            entityID: entityID,
            attributeID: attributeID,
            value: value,
            attribute: attributes[attributeID]
          )
        else {
          throw Self.missingTripleError(
            entityID: entityID,
            attributeID: attributeID,
            value: value,
            attributes: attributes
          )
        }

      case let .requireEntityExistsByLookup(lookup, namespace):
        let lookupAttribute = try Self.validateLookup(
          lookup,
          expectedNamespace: namespace,
          attributes: attributes
        )
        let entityIDs = try Self.entityIDs(
          matching: lookup,
          in: indexes,
          lookupAttribute: lookupAttribute
        )
        guard !entityIDs.isEmpty else {
          throw Self.missingEntityError(lookup: lookup, attribute: lookupAttribute.attribute)
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
        .deleteEntity, .deleteEntityInNamespace, .deleteEntityByLookup:
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
            if deferredValueResidency.attributeIDs.contains(triple.attributeID) {
              indexes.markDeferredValue(
                entityID: triple.entityID,
                attributeID: triple.attributeID
              )
            }
            try Self.validateWriteValue(triple.value, triple: triple, attributes: attributes)
            if attributes[triple.attributeID]?.valueType == .ref {
              throw Self.unsupportedMergeError(triple: triple, attributes: attributes)
            }
            changedEntityIDs.formUnion(indexes.apply(concreteOperation, attributes: attributes))

          case let .insert(triple), let .retract(triple):
            if deferredValueResidency.attributeIDs.contains(triple.attributeID) {
              indexes.markDeferredValue(
                entityID: triple.entityID,
                attributeID: triple.attributeID
              )
            }
            try Self.validateWriteValue(triple.value, triple: triple, attributes: attributes)
            changedEntityIDs.formUnion(indexes.apply(concreteOperation, attributes: attributes))

          case .deleteEntity:
            changedEntityIDs.formUnion(indexes.apply(concreteOperation, attributes: attributes))

          case .deleteEntityInNamespace:
            changedEntityIDs.formUnion(indexes.apply(concreteOperation, attributes: attributes))

          case .requireEntityMissing, .requireEntityMissingByLookup,
            .requireEntityExists, .requireEntityExistsByLookup,
            .requireTripleExists,
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
      tripleCount: indexes.tripleCount,
      emissions: []
    )
    let previousChangedEntityTriples: [String: [InstantTriple]]
    if capturePreviousChangedEntityTriples, let base = previousChangedEntityTriplesBase {
      previousChangedEntityTriples = Dictionary(
        uniqueKeysWithValues: changedEntityIDs.map { entityID in
          (entityID, base.triples(entityID: entityID))
        }
      )
    } else {
      previousChangedEntityTriples = [:]
    }
    return PreparedStoreMutation(
      result: result,
      sequence: nextSequence,
      attributes: attributes,
      indexes: indexes,
      previousChangedEntityTriples: previousChangedEntityTriples
    )
  }

  func commit(_ prepared: consuming PreparedStoreMutation) -> PreparedStoreMutation {
    commit(prepared, shouldPublish: false)
  }

  func commitAndPublish(_ prepared: consuming PreparedStoreMutation) -> PreparedStoreMutation {
    commit(prepared, shouldPublish: true)
  }

  private func commit(
    _ prepared: consuming PreparedStoreMutation,
    shouldPublish: Bool
  ) -> PreparedStoreMutation {
    var prepared = prepared
    let changedNamespaces: Set<String>?
    if attributes != prepared.attributes {
      changedNamespaces = nil
    } else {
      var resolvedNamespaces: Set<String> = []
      var resolvedEveryEntity = true
      for entityID in prepared.result.changedEntityIDs {
        let entityNamespaces = indexes.namespaces(entityID: entityID, attributes: attributes)
          .union(
            prepared.indexes.namespaces(
              entityID: entityID,
              attributes: prepared.attributes
            )
          )
        if entityNamespaces.isEmpty {
          resolvedEveryEntity = false
        }
        resolvedNamespaces.formUnion(entityNamespaces)
      }
      changedNamespaces = resolvedEveryEntity ? resolvedNamespaces : nil
    }
    prepared.deferredValueRemovalMetrics = prepared.indexes.removeMarkedDeferredValues(
      attributes: prepared.attributes
    )
    self.attributes = prepared.attributes
    self.indexes = prepared.indexes
    self.sequence = prepared.sequence

    var emissionsByObservation: [StoreObservationKey: InstantQueryEmission] = [:]
    for observer in observers.values
    where Self.shouldRematerialize(observer, changedNamespaces: changedNamespaces)
    {
      let key = StoreObservationKey(
        plan: observer.plan,
        remotePageInfo: observer.remotePageInfo
      )
      let emission: InstantQueryEmission
      if let existing = emissionsByObservation[key] {
        emission = existing
      } else {
        let page = indexes.materializePage(
          observer.plan,
          attributes: attributes,
          remotePageInfo: observer.remotePageInfo
        )
        emission = InstantQueryEmission(
          queryID: observer.plan.id,
          sequence: sequence,
          values: page.values,
          pageInfo: page.pageInfo
        )
        emissionsByObservation[key] = emission
      }
      if shouldPublish {
        observer.continuation.yield(emission)
      }
    }
    var result = prepared.result
    result.emissions =
      emissionsByObservation
      .sorted { lhs, rhs in Self.emissionSortKey(lhs.key) < Self.emissionSortKey(rhs.key) }
      .map(\.value)
    InstantDiagnostics.shared.record(
      .trace,
      subsystem: "instant-swift-data-core",
      category: "store",
      event: shouldPublish ? "store.mutation-published" : "store.mutation-committed",
      message: shouldPublish
        ? "Committed a store mutation and published query emissions."
        : "Committed a store mutation without publishing query emissions.",
      metadata: [
        "changedEntityCount": String(result.changedEntityIDs.count),
        "emissionCount": String(result.emissions.count),
        "observerCount": String(observers.count),
        "sequence": String(sequence),
        "tripleCount": String(result.tripleCount),
      ],
      correlationID: result.transactionID
    )
    prepared.result = result
    return prepared
  }

  private static func shouldRematerialize(
    _ observer: StoreObserver,
    changedNamespaces: Set<String>?
  ) -> Bool {
    guard let changedNamespaces else { return true }
    guard observer.plan.hasOnlyNamespaceLocalDependencies else { return true }
    return changedNamespaces.contains(observer.plan.namespace)
  }

  private static func emissionSortKey(_ key: StoreObservationKey) -> String {
    [
      key.plan.cacheKey,
      remotePageInfoSortKey(key.remotePageInfo),
    ]
    .joined(separator: "|")
  }

  private static func remotePageInfoSortKey(
    _ remotePageInfo: InstantQueryRemotePageInfo?
  ) -> String {
    switch remotePageInfo {
    case nil:
      return "local"
    case .waiting?:
      return "waiting"
    case let .ready(pageInfo)?:
      return [
        "ready",
        cursorSortKey(pageInfo.startCursor),
        cursorSortKey(pageInfo.endCursor),
        "previous:\(pageInfo.hasPreviousPage)",
        "next:\(pageInfo.hasNextPage)",
      ]
      .joined(separator: "|")
    }
  }

  private static func cursorSortKey(_ cursor: InstantQueryCursor?) -> String {
    guard let cursor else { return "nil" }
    return [
      cursor.entityID,
      cursor.sortValue?.comparableKey ?? "nil",
      "inclusive:\(cursor.inclusive)",
    ]
    .joined(separator: "|")
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
      recovery:
        "Create the entity before using a strict update, or use merge for upsert-style writes."
    )
  }

  private static func missingTripleError(
    entityID: String,
    attributeID: String,
    value: InstantValue,
    attributes: AttributeStore
  ) -> InstantError {
    let attribute = attributes[attributeID]
    return InstantError(
      code: .validationFailed,
      operation: "require triple",
      namespace: attribute?.namespace,
      path: attribute?.name ?? attributeID,
      localID: entityID,
      message:
        "No existing triple was found for '\(entityID)' at '\(attributeID)' with value '\(value)'.",
      recovery: "Refresh the local cache and retry with the current relationship value."
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

    case .deleteEntity, .deleteEntityInNamespace:
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
      let lookupAttribute = try validateLookup(
        lookup,
        expectedNamespace: nil,
        attributes: attributes
      )
      let namespace = lookupAttribute.namespace
      guard
        let entityID = try resolveEntityID(
          lookup,
          expectedNamespace: namespace,
          indexes: indexes,
          attributes: attributes,
          resolvedLookups: &resolvedLookups
        )
      else { return [] }
      return [.deleteEntityInNamespace(entityID: entityID, namespace: namespace)]

    case .requireEntityMissing, .requireEntityMissingByLookup,
      .requireEntityExists, .requireEntityExistsByLookup,
      .requireTripleExists,
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

    let expectedNamespace =
      attribute.valueType == .ref ? attribute.linkNamespace : attribute.namespace
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

    case .string, .number, .boolean, .date, .json, .any:
      throw InstantError(
        code: .validationFailed,
        operation: "resolve lookup ref",
        namespace: attribute.namespace,
        path: attribute.name,
        localID: lookup.description,
        message: "Lookup ref values can only fill id and ref attributes.",
        recovery:
          "Use lookup refs to identify the entity being written or to link to another entity."
      )
    }
  }

  private static func validateWriteValue(
    _ value: InstantValue,
    triple: InstantTriple,
    attributes: AttributeStore
  ) throws {
    let attributeNamespace = namespace(in: triple.attributeID)
    if !attributes.namespaces.isEmpty,
      let attributeNamespace,
      !attributes.namespaces.contains(attributeNamespace)
    {
      throw InstantError(
        code: .validationFailed,
        operation: "write entity attribute",
        namespace: attributeNamespace,
        localID: triple.entityID,
        message: "Entity namespace '\(attributeNamespace)' does not exist in the local schema.",
        recovery: "Declare the entity namespace before writing attributes for it."
      )
    }

    guard let attribute = attributes[triple.attributeID] else {
      guard isFinitePayload(value) else {
        throw InstantError(
          code: .validationFailed,
          operation: "write entity attribute",
          namespace: attributeNamespace,
          path: triple.attributeID,
          localID: triple.entityID,
          message: "Invalid non-finite number in attribute '\(triple.attributeID)'.",
          recovery: "Use only finite numbers in local writes."
        )
      }

      switch value {
      case .ref where attributes.namespaces.isEmpty:
        return

      case .ref, .lookupRef:
        throw InstantError(
          code: .validationFailed,
          operation: "write entity attribute",
          path: triple.attributeID,
          localID: triple.entityID,
          message: "No ref attribute named '\(triple.attributeID)' is declared.",
          recovery: "Declare the link in the schema before writing ref values."
        )

      case .null, .string, .number, .bool, .date, .json:
        return
      }
    }

    guard isFinitePayload(value) else {
      throw InstantError(
        code: .validationFailed,
        operation: "write entity attribute",
        namespace: attribute.namespace,
        path: attribute.name,
        localID: triple.entityID,
        message: "Invalid non-finite number in attribute '\(attribute.id)'.",
        recovery: "Use only finite numbers in local writes."
      )
    }

    guard isWriteValue(value, compatibleWith: attribute) else {
      throw InstantError(
        code: .validationFailed,
        operation: "write entity attribute",
        namespace: attribute.namespace,
        path: attribute.name,
        localID: triple.entityID,
        message:
          "Invalid value for attribute '\(attribute.id)'. Expected \(attribute.valueType.storeValidationDescription), but received \(value.storeValidationTypeDescription).",
        recovery: "Use a value that matches the declared schema attribute type."
      )
    }
  }

  private static func isWriteValue(
    _ value: InstantValue,
    compatibleWith attribute: InstantAttribute
  ) -> Bool {
    if case .null = value { return true }

    switch (value, attribute.valueType) {
    case (.string, .string),
      (.bool, .boolean),
      (.date, .date),
      (.json, .json),
      (.ref, .ref):
      return true

    case let (.number(value), .number):
      return value.isFinite

    case (.string, .any),
      (.bool, .any),
      (.date, .any),
      (.json, .any):
      return true

    case let (.number(value), .any):
      return value.isFinite

    case (.string, .date), (.number, .date):
      return InstantDateCoercion.coerce(value) != nil

    case (.null, _),
      (.string, _),
      (.number, _),
      (.bool, _),
      (.date, _),
      (.json, _),
      (.ref, _),
      (.lookupRef, _):
      return false
    }
  }

  private static func resolveEntityID(
    _ lookup: InstantLookupRef,
    expectedNamespace: String?,
    indexes: TripleIndexes,
    attributes: AttributeStore,
    resolvedLookups: inout [InstantLookupRef: String]
  ) throws -> String? {
    let lookupAttribute = try validateLookup(
      lookup,
      expectedNamespace: expectedNamespace,
      attributes: attributes
    )
    if let entityID = resolvedLookups[lookup] {
      return entityID
    }
    let entityIDs = try entityIDs(
      matching: lookup,
      in: indexes,
      lookupAttribute: lookupAttribute
    )
    guard let entityID = entityIDs.first else { return nil }
    resolvedLookups[lookup] = entityID
    return entityID
  }

  private static func namespace(in attributeID: String) -> String? {
    guard let separator = attributeID.firstIndex(of: "/"), separator != attributeID.startIndex
    else { return nil }
    return String(attributeID[..<separator])
  }

  private static func isFinitePayload(_ value: InstantValue) -> Bool {
    switch value {
    case .null, .string, .bool, .ref, .lookupRef:
      return true
    case let .number(number):
      return number.isFinite
    case let .date(date):
      return date.timeIntervalSince1970.isFinite
    case let .json(json):
      return isFinitePayload(json)
    }
  }

  private static func isFinitePayload(_ value: InstantLookupValue) -> Bool {
    switch value {
    case .null, .string, .bool, .ref:
      return true
    case let .number(number):
      return number.isFinite
    case let .date(date):
      return date.timeIntervalSince1970.isFinite
    case let .json(json):
      return isFinitePayload(json)
    }
  }

  private static func isFinitePayload(_ value: JSONValue) -> Bool {
    switch value {
    case .null, .bool, .string:
      return true
    case let .number(number):
      return number.isFinite
    case let .array(values):
      return values.allSatisfy(isFinitePayload)
    case let .object(fields):
      return fields.values.allSatisfy(isFinitePayload)
    }
  }

  private static func validateLookup(
    _ lookup: InstantLookupRef,
    expectedNamespace: String?,
    attributes: AttributeStore
  ) throws -> InstantResolvedLookupAttribute {
    guard let lookupAttribute = attributes.lookupAttribute(id: lookup.attributeID) else {
      throw InstantError(
        code: .validationFailed,
        operation: "lookup entity",
        path: lookup.attributeID,
        localID: lookup.description,
        message: "No attribute named '\(lookup.attributeID)' is declared for this lookup ref.",
        recovery: "Declare the lookup attribute in the schema before writing by lookup ref."
      )
    }
    let attribute = lookupAttribute.attribute

    if let expectedNamespace, lookupAttribute.namespace != expectedNamespace {
      throw InstantError(
        code: .validationFailed,
        operation: "lookup entity",
        namespace: expectedNamespace,
        path: lookupAttribute.name,
        localID: lookup.description,
        message:
          "Lookup attribute '\(lookup.attributeID)' belongs to '\(lookupAttribute.namespace)', not '\(expectedNamespace)'.",
        recovery: "Use a lookup attribute from the same namespace as the entity being written."
      )
    }

    guard attribute.isUnique || attribute.primaryKey else {
      throw InstantError(
        code: .validationFailed,
        operation: "lookup entity",
        namespace: lookupAttribute.namespace,
        path: lookupAttribute.name,
        localID: lookup.description,
        message:
          "Attribute '\(lookup.attributeID)' is not unique, so it cannot be used as a lookup ref.",
        recovery: "Mark the attribute unique in the schema, or write the entity by id."
      )
    }

    guard isFinitePayload(lookup.value) else {
      throw InstantError(
        code: .validationFailed,
        operation: "lookup entity",
        namespace: lookupAttribute.namespace,
        path: lookupAttribute.name,
        localID: lookup.description,
        message: "Lookup value contains a non-finite number.",
        recovery: "Use only finite numbers in lookup refs."
      )
    }

    guard isLookupValue(lookup.value, compatibleWith: attribute) else {
      throw InstantError(
        code: .validationFailed,
        operation: "lookup entity",
        namespace: lookupAttribute.namespace,
        path: lookupAttribute.name,
        localID: lookup.description,
        message: "Lookup value does not match the declared type of '\(lookup.attributeID)'.",
        recovery: "Use a lookup value whose Swift type matches the unique attribute."
      )
    }

    return lookupAttribute
  }

  private static func entityIDs(
    matching lookup: InstantLookupRef,
    in indexes: TripleIndexes,
    lookupAttribute: InstantResolvedLookupAttribute
  ) throws -> [String] {
    let entityIDs = indexes.entityIDs(matching: lookup, lookupAttribute: lookupAttribute)
    guard entityIDs.count < 2 else {
      throw InstantError(
        code: .validationFailed,
        operation: "lookup entity",
        namespace: lookupAttribute.namespace,
        path: lookupAttribute.name,
        localID: lookup.description,
        message: "Lookup ref '\(lookup.description)' matched more than one local entity.",
        recovery:
          "Repair the local cache so unique attributes map to one entity before writing by lookup ref."
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
      (.bool, .boolean),
      (.date, .date),
      (.json, .json),
      (.ref, .ref):
      return true

    case let (.number(value), .number):
      return value.isFinite

    case (.string, .any),
      (.bool, .any),
      (.date, .any),
      (.json, .any):
      return true

    case let (.number(value), .any):
      return value.isFinite

    case (.string, .date), (.number, .date):
      return InstantDateCoercion.coerce(value.instantValue) != nil

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
      recovery:
        "Use update for upsert-style writes, or choose a fresh unique lookup value before creating."
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
      recovery:
        "Create the entity before using a strict update, or use update/merge for server-resolved upserts."
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
    remotePageInfo: InstantQueryRemotePageInfo? = nil,
    liveQueryKey: String? = nil,
    continuation: AsyncStream<InstantQueryEmission>.Continuation
  ) {
    observers[id] = StoreObserver(
      plan: plan,
      remotePageInfo: remotePageInfo,
      liveQueryKey: liveQueryKey,
      continuation: continuation
    )
    let initialEmission = materializeEmission(plan, remotePageInfo: remotePageInfo)
    continuation.yield(initialEmission)
    InstantDiagnostics.shared.record(
      .trace,
      subsystem: "instant-swift-data-core",
      category: "store",
      event: "store.observer-registered",
      message: "Registered a query observer and emitted its initial snapshot.",
      metadata: [
        "namespace": plan.namespace,
        "observerCount": String(observers.count),
        "resultCount": String(initialEmission.values.count),
        "sequence": String(initialEmission.sequence),
      ],
      correlationID: plan.id
    )
  }

  private func cancelObservation(id: UUID) {
    let observer = observers.removeValue(forKey: id)
    InstantDiagnostics.shared.record(
      .trace,
      subsystem: "instant-swift-data-core",
      category: "store",
      event: "store.observer-cancelled",
      message: "Cancelled a query observer.",
      metadata: [
        "namespace": observer?.plan.namespace ?? "unknown",
        "observerCount": String(observers.count),
      ],
      correlationID: observer?.plan.id
    )
  }

  package func activeObservationCount() -> Int {
    observers.count
  }

  func currentTripleCount() -> Int {
    indexes.tripleCount
  }

  func activeQueryCacheKeys() -> Set<String> {
    Set(observers.values.map(\.plan.cacheKey))
  }
}

private extension InstantQueryPlan {
  var hasOnlyNamespaceLocalDependencies: Bool {
    (includes?.isEmpty ?? true)
      && filters.allSatisfy(\.hasOnlyNamespaceLocalDependencies)
      && !(order?.field.contains(".") ?? false)
      && (selectedFields?.allSatisfy { !$0.contains(".") } ?? true)
  }
}

private extension InstantQueryFilter {
  var hasOnlyNamespaceLocalDependencies: Bool {
    switch self {
    case let .equals(field, _), let .notEquals(field, _),
      let .greaterThan(field, _), let .greaterThanOrEqual(field, _),
      let .lessThan(field, _), let .lessThanOrEqual(field, _),
      let .in(field, _), let .like(field, _), let .iLike(field, _),
      let .isNull(field), let .isNotNull(field):
      return !field.contains(".")
    case let .and(filters), let .or(filters):
      return filters.allSatisfy(\.hasOnlyNamespaceLocalDependencies)
    }
  }
}

extension InstantValue {
  fileprivate var storeValidationTypeDescription: String {
    switch self {
    case .null:
      return "null"
    case .string:
      return "string"
    case .number:
      return "number"
    case .bool:
      return "boolean"
    case .date:
      return "date"
    case .json:
      return "json"
    case .ref:
      return "ref"
    case .lookupRef:
      return "lookup ref"
    }
  }
}

extension InstantValueType {
  fileprivate var storeValidationDescription: String {
    switch self {
    case .string:
      return "string"
    case .number:
      return "number"
    case .boolean:
      return "boolean"
    case .date:
      return "date"
    case .json:
      return "json"
    case .any:
      return "any"
    case .ref:
      return "ref"
    }
  }
}
