import Darwin
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

// SAFETY: rollback capture owned by one PreparedStoreMutation inside a single
// InstantStore actor mutation; never crossed an executor while mutable. Copies
// of the owning value take uniqueness before writing, no shared executor.
private final class PreviousChangedEntityCapture: @unchecked Sendable {
  private var emptyIDs: Set<String> = []
  private var slots: [String: [String: AttrSlot]] = [:]
  private var materializer: TripleIndexes?
  private var materialized: [String: [InstantTriple]]?

  func contains(_ entityID: String) -> Bool {
    emptyIDs.contains(entityID) || slots[entityID] != nil || materialized?[entityID] != nil
  }

  func capture(entityID: String, from indexes: TripleIndexes) {
    guard !contains(entityID) else { return }
    if materializer == nil {
      materializer = indexes
    }
    if let copied = indexes.copiedAttributeSlots(entityID: entityID) {
      slots[entityID] = copied
    } else {
      emptyIDs.insert(entityID)
    }
  }

  var triplesByEntityID: [String: [InstantTriple]] {
    if let materialized {
      return materialized
    }
    var result: [String: [InstantTriple]] = [:]
    result.reserveCapacity(emptyIDs.count + slots.count)
    for entityID in emptyIDs {
      result[entityID] = []
    }
    if let materializer {
      for (entityID, attributesByID) in slots {
        result[entityID] = materializer.materializedTriples(
          entityID: entityID,
          attributesByID: attributesByID
        )
      }
    }
    materialized = result
    return result
  }

  func replaceAll(_ triples: [String: [InstantTriple]]) {
    emptyIDs = []
    slots = [:]
    materializer = nil
    materialized = triples
  }
}

struct PreparedStoreMutation: Sendable {
  var result: InstantStoreMutationResult
  var sequence: Int64
  var attributes: AttributeStore
  var indexes: TripleIndexes
  var deferredValueRemovalMetrics: TripleIndexes.DeferredValueRemovalMetrics
  private var previousCapture = PreviousChangedEntityCapture()
  private var preparedSnapshot: InstantStoreSnapshot?

  var previousChangedEntityTriples: [String: [InstantTriple]] {
    get { previousCapture.triplesByEntityID }
    set { previousCapture.replaceAll(newValue) }
  }

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
    self.deferredValueRemovalMetrics = deferredValueRemovalMetrics
    self.preparedSnapshot = snapshot
    previousCapture.replaceAll(previousChangedEntityTriples)
  }

  fileprivate init(
    result: InstantStoreMutationResult,
    sequence: Int64,
    attributes: AttributeStore,
    indexes: TripleIndexes,
    previousCapture: PreviousChangedEntityCapture,
    deferredValueRemovalMetrics: TripleIndexes.DeferredValueRemovalMetrics = .init()
  ) {
    self.result = result
    self.sequence = sequence
    self.attributes = attributes
    self.indexes = indexes
    self.deferredValueRemovalMetrics = deferredValueRemovalMetrics
    self.previousCapture = previousCapture
  }
}

package struct InstantStorePublishMetrics: Equatable, Sendable {
  package var skippedObserverCount = 0
  package var splicedObserverCount = 0
  package var rematerializedObserverCount = 0
  package var materializedSnapshotCount = 0
}

private struct StoreObserver: Sendable {
  var plan: InstantQueryPlan
  var remotePageInfo: InstantQueryRemotePageInfo?
  var liveQueryKey: String?
  var lastValues: [InstantEntitySnapshot]
  var lastPageInfo: InstantQueryPageInfo?
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
  package private(set) var lastPublishMetrics = InstantStorePublishMetrics()

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
    _ = indexes.reconcileRelationStorage(
      previousAttributes: self.attributes,
      mergedAttributes: mergedAttributes
    )
    self.attributes = mergedAttributes
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
      newestVisibleWrite: newestVisibleWrite,
      // The hot store includes optimistic overlays but has no outbox provenance.
      // Conservatively retain required scalars instead of importing an
      // unconfirmed value into an older mutation.
      newestVisibleRequiredScalar: [:],
      newestVisibleRequiredScalarEncodedValueByteCount: [:]
    )
  }

  public func materialize(
    _ plan: InstantQueryPlan,
    remotePageInfo: InstantQueryRemotePageInfo? = nil
  ) -> [InstantEntitySnapshot] {
    indexes.materialize(plan, attributes: attributes, remotePageInfo: remotePageInfo)
  }

  func internedCardinalityOneEntityCount() -> Int {
    indexes.internedCardinalityOneEntityCount
  }

  /// In-actor microbench: iterations of materialize without inter-call actor hops.
  /// Used to compare pure store latency to TypeScript `@instantdb/core` store scans.
  ///
  /// Wall time includes host preemption. Thread CPU is the work itself. The
  /// DomainAEV ship gate keeps the 0.069 ms TypeScript InstaQL floor on both.
  package func measureMaterializeAverageNanoseconds(
    _ plan: InstantQueryPlan,
    iterations: Int
  ) -> (averageNanoseconds: Double, lastCount: Int) {
    let measured = measureMaterializeAverages(plan, iterations: iterations)
    return (measured.averageWallNanoseconds, measured.lastCount)
  }

  package func measureMaterializeAverages(
    _ plan: InstantQueryPlan,
    iterations: Int
  ) -> (
    averageWallNanoseconds: Double,
    averageThreadCPUNanoseconds: Double,
    lastCount: Int
  ) {
    precondition(iterations > 0)
    var wallTotal: UInt64 = 0
    var cpuTotal: UInt64 = 0
    var lastCount = 0
    var cpuSamples = 0
    for _ in 0..<iterations {
      let wall0 = DispatchTime.now().uptimeNanoseconds
      let cpu0 = Self.currentThreadCPUNanoseconds()
      let rows = indexes.materialize(plan, attributes: attributes)
      let cpu1 = Self.currentThreadCPUNanoseconds()
      let wall1 = DispatchTime.now().uptimeNanoseconds
      wallTotal += wall1 &- wall0
      lastCount = rows.count
      if let cpu0, let cpu1, cpu1 >= cpu0 {
        cpuTotal += cpu1 - cpu0
        cpuSamples += 1
      }
    }
    let averageCPU: Double
    if cpuSamples == iterations {
      averageCPU = Double(cpuTotal) / Double(iterations)
    } else {
      averageCPU = 0
    }
    return (Double(wallTotal) / Double(iterations), averageCPU, lastCount)
  }

  private static func currentThreadCPUNanoseconds() -> UInt64? {
    var ts = timespec()
    let result = clock_gettime(CLOCK_THREAD_CPUTIME_ID, &ts)
    guard result == 0, ts.tv_sec >= 0, ts.tv_nsec >= 0 else {
      return nil
    }
    return UInt64(ts.tv_sec) * 1_000_000_000 + UInt64(ts.tv_nsec)
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

  @discardableResult
  func installLiveQueryPageInfo(
    _ replacements: [InstantLiveQueryResultReplacement],
    publishing: Bool
  ) -> [InstantQueryEmission] {
    let pageInfoByKey = Self.liveQueryPageInfoByKey(replacements)
    guard !pageInfoByKey.isEmpty else { return [] }
    var metrics = InstantStorePublishMetrics()
    var emissionsByObservation: [StoreObservationKey: InstantQueryEmission] = [:]
    for observerID in Array(observers.keys) {
      guard var observer = observers[observerID],
        let liveQueryKey = observer.liveQueryKey,
        let remotePageInfo = pageInfoByKey[liveQueryKey]
      else {
        continue
      }
      guard observer.remotePageInfo != remotePageInfo else {
        metrics.skippedObserverCount += 1
        continue
      }
      observer.remotePageInfo = remotePageInfo
      let key = StoreObservationKey(
        plan: observer.plan,
        remotePageInfo: observer.remotePageInfo
      )
      let emission: InstantQueryEmission
      if let existing = emissionsByObservation[key] {
        emission = existing
      } else {
        let page = indexes.materializePageWithMetrics(
          observer.plan,
          attributes: attributes,
          remotePageInfo: observer.remotePageInfo
        )
        metrics.rematerializedObserverCount += 1
        metrics.materializedSnapshotCount += page.metrics.materializedSnapshotCount
        emission = InstantQueryEmission(
          queryID: observer.plan.id,
          sequence: sequence,
          values: page.page.values,
          pageInfo: page.page.pageInfo
        )
        emissionsByObservation[key] = emission
      }
      observer.apply(emission)
      observers[observerID] = observer
      guard publishing else { continue }
      observer.continuation.yield(emission)
    }
    lastPublishMetrics = metrics
    return emissionsByObservation
      .sorted { lhs, rhs in Self.emissionSortKey(lhs.key) < Self.emissionSortKey(rhs.key) }
      .map(\.value)
  }

  private static func liveQueryPageInfoByKey(
    _ replacements: [InstantLiveQueryResultReplacement]
  ) -> [String: InstantQueryRemotePageInfo] {
    Dictionary(
      replacements.map {
        (
          $0.key,
          $0.pageInfo.map(InstantQueryRemotePageInfo.ready) ?? .waiting
        )
      },
      uniquingKeysWith: { _, latest in latest }
    )
  }

  func prepare(_ transaction: InstantStoreTransaction) throws -> PreparedStoreMutation {
    let prepared = try prepare(
      transaction,
      attributes: attributes,
      indexes: indexes
    )
    return commit(prepared)
  }

  func prepareSequential(
    count: Int,
    transactionAtIndex: (Int) throws -> InstantStoreTransaction
  ) throws {
    for index in 0..<count {
      let prepared = try prepareMutating(
        transactionAtIndex(index),
        attributes: &attributes,
        indexes: &indexes,
        capturePreviousChangedEntityTriples: false
      )
      sequence = prepared.sequence
    }
  }

  func prepareCurrent(
    _ transaction: InstantStoreTransaction,
    insertReplayPolicy: InstantTripleInsertReplayPolicy = .replaceAndInvalidate
  ) throws -> PreparedStoreMutation {
    try prepare(
      transaction,
      attributes: attributes,
      indexes: indexes,
      insertReplayPolicy: insertReplayPolicy
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
    applyingTo prepared: PreparedStoreMutation,
    insertReplayPolicy: InstantTripleInsertReplayPolicy = .replaceAndInvalidate
  ) throws -> PreparedStoreMutation {
    try prepare(
      transaction,
      attributes: prepared.attributes,
      indexes: prepared.indexes,
      insertReplayPolicy: insertReplayPolicy
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
    var indexes = self.indexes
    // Optimistic inverses were authored against the resident schema. Peel them before a
    // many-to-one schema transition can discard sibling facts that belong to the authoritative
    // base. Upstream likewise rebuilds the server store first, then reapplies optimistic writes.
    indexes.hydrateDeferredValues(deferredTriples, attributes: attributes)
    for rollback in rollbacks {
      _ = try prepareMutating(
        rollback,
        attributes: &attributes,
        indexes: &indexes,
        capturePreviousChangedEntityTriples: false
      )
    }
    let previousAttributes = attributes
    attributes.merge(attributesToMerge)
    let indexesBeforeSchemaReconciliation = indexes
    let schemaReconciledEntityIDs: Set<String>
    if attributesToMerge.isEmpty {
      schemaReconciledEntityIDs = []
    } else {
      let reconciliation = Self.schemaReconciledIndexes(
        indexes,
        previousAttributes: previousAttributes,
        mergedAttributes: attributes
      )
      indexes = reconciliation.indexes
      schemaReconciledEntityIDs = reconciliation.changedEntityIDs
    }
    var prepared = try prepareMutating(
      serverTransaction,
      attributes: &attributes,
      indexes: &indexes,
      capturePreviousChangedEntityTriples: true
    )
    prepared.result.changedEntityIDs.formUnion(schemaReconciledEntityIDs)
    for entityID in schemaReconciledEntityIDs
    where prepared.previousChangedEntityTriples[entityID] == nil {
      prepared.previousChangedEntityTriples[entityID] =
        indexesBeforeSchemaReconciliation.triples(entityID: entityID)
    }
    return prepared
  }

  /// Merge schema into an already-peeled server-apply base, then reconcile its derived indexes.
  ///
  /// Runtime peels durable optimistic components in bounded SQLite pages, so it cannot pass every
  /// inverse to the array-based seam above. This phase boundary keeps canonicalization after the
  /// final peel and before the authoritative transaction or optimistic replay.
  func prepareMergingAttributes(
    _ attributesToMerge: [InstantAttribute],
    applyingTo prepared: PreparedStoreMutation
  ) -> PreparedStoreMutation {
    guard !attributesToMerge.isEmpty else { return prepared }
    var attributes = prepared.attributes
    let previousAttributes = attributes
    attributes.merge(attributesToMerge)
    let indexesBeforeSchemaReconciliation = prepared.indexes
    let reconciliation = Self.schemaReconciledIndexes(
      prepared.indexes,
      previousAttributes: previousAttributes,
      mergedAttributes: attributes
    )
    let indexes = reconciliation.indexes
    let changedEntityIDs = reconciliation.changedEntityIDs
    let previousChangedEntityTriples = Dictionary(
      uniqueKeysWithValues: changedEntityIDs.map { entityID in
        (entityID, indexesBeforeSchemaReconciliation.triples(entityID: entityID))
      }
    )
    return PreparedStoreMutation(
      result: InstantStoreMutationResult(
        transactionID: prepared.result.transactionID,
        changedEntityIDs: changedEntityIDs,
        tripleCount: indexes.tripleCount,
        emissions: []
      ),
      sequence: prepared.sequence,
      attributes: attributes,
      indexes: indexes,
      previousChangedEntityTriples: previousChangedEntityTriples
    )
  }

  private func prepare(
    _ transaction: InstantStoreTransaction,
    attributes: AttributeStore,
    indexes initialIndexes: TripleIndexes,
    insertReplayPolicy: InstantTripleInsertReplayPolicy = .replaceAndInvalidate
  ) throws -> PreparedStoreMutation {
    var attributes = attributes
    var indexes = initialIndexes
    return try prepareMutating(
      transaction,
      attributes: &attributes,
      indexes: &indexes,
      capturePreviousChangedEntityTriples: true,
      insertReplayPolicy: insertReplayPolicy
    )
  }

  private func prepareMutating(
    _ transaction: InstantStoreTransaction,
    attributes: inout AttributeStore,
    indexes: inout TripleIndexes,
    capturePreviousChangedEntityTriples: Bool,
    insertReplayPolicy: InstantTripleInsertReplayPolicy = .replaceAndInvalidate
  ) throws -> PreparedStoreMutation {
    indexes.discardInternedQueryResultsBeforeWrite()
    indexes.reserveCapacity(
      entityCapacity: transaction.operations.count,
      attributeCapacity: attributes.count
    )
    var changedEntityIDs: Set<String> = []
    let previousCapture = PreviousChangedEntityCapture()
    let shouldMarkDeferred = !deferredValueResidency.attributeIDs.isEmpty

    var lastCapturedEntityID: String?
    func capturePrevious(of entityID: String) {
      guard capturePreviousChangedEntityTriples else { return }
      if lastCapturedEntityID == entityID {
        return
      }
      lastCapturedEntityID = entityID
      previousCapture.capture(entityID: entityID, from: indexes)
    }

    func captureDeletePrevious(of entityID: String) {
      guard capturePreviousChangedEntityTriples else { return }
      capturePrevious(of: entityID)
      if indexes.hasIncomingReferences(entityID) {
        for triple in indexes.reverseRefTriples(targetEntityID: entityID) {
          capturePrevious(of: triple.entityID)
        }
      }
      for targetEntityID in indexes.outgoingRefTargetIDs(entityID) {
        capturePrevious(of: targetEntityID)
      }
    }

    func markDeferred(of triple: InstantTriple) {
      if deferredValueResidency.attributeIDs.contains(triple.attributeID) {
        indexes.markDeferredValue(
          entityID: triple.entityID,
          attributeID: triple.attributeID
        )
      }
    }

    func applyDirectInsert(_ triple: InstantTriple) throws {
      var canonical = triple
      var attribute = attributes[triple.attributeID]
      if attribute?.id != triple.attributeID {
        canonical = try Self.canonicalizedTripleIfNeeded(triple, attributes: attributes)
        attribute = attributes[canonical.attributeID]
      }
      capturePrevious(of: canonical.entityID)
      if case let .ref(targetEntityID) = canonical.value {
        capturePrevious(of: targetEntityID)
      }
      if shouldMarkDeferred {
        markDeferred(of: canonical)
      }
      try Self.validateWriteValue(
        canonical.value,
        triple: canonical,
        attribute: attribute,
        attributes: attributes
      )
      indexes.applyInsert(
        canonical,
        attribute: attribute,
        attributes: attributes,
        insertReplayPolicy: insertReplayPolicy,
        into: &changedEntityIDs
      )
    }

    func applyDirectMerge(_ triple: InstantTriple) throws {
      let canonical = try Self.canonicalizedTripleIfNeeded(triple, attributes: attributes)
      capturePrevious(of: canonical.entityID)
      if shouldMarkDeferred {
        markDeferred(of: canonical)
      }
      try Self.validateWriteValue(
        canonical.value,
        triple: canonical,
        attribute: attributes[canonical.attributeID],
        attributes: attributes
      )
      if attributes[canonical.attributeID]?.valueType == .ref {
        throw Self.unsupportedMergeError(triple: canonical, attributes: attributes)
      }
      indexes.apply(.merge(canonical), attributes: attributes, into: &changedEntityIDs)
    }

    func applyDirectRetract(_ triple: InstantTriple) throws {
      let canonical = try Self.canonicalizedTripleIfNeeded(triple, attributes: attributes)
      capturePrevious(of: canonical.entityID)
      if case let .ref(targetEntityID) = canonical.value {
        capturePrevious(of: targetEntityID)
      }
      if shouldMarkDeferred {
        markDeferred(of: canonical)
      }
      try Self.validateWriteValue(
        canonical.value,
        triple: canonical,
        attribute: attributes[canonical.attributeID],
        attributes: attributes
      )
      indexes.apply(
        .retract(canonical),
        attributes: attributes,
        insertReplayPolicy: insertReplayPolicy,
        into: &changedEntityIDs
      )
    }

    func applyResolved(_ operation: InstantTripleOperation) throws {
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
          capturePrevious(of: triple.entityID)
          markDeferred(of: triple)
          try Self.validateWriteValue(triple.value, triple: triple, attributes: attributes)
          if attributes[triple.attributeID]?.valueType == .ref {
            throw Self.unsupportedMergeError(triple: triple, attributes: attributes)
          }
          indexes.apply(concreteOperation, attributes: attributes, into: &changedEntityIDs)

        case let .insert(triple), let .retract(triple):
          capturePrevious(of: triple.entityID)
          if case let .ref(targetEntityID) = triple.value {
            capturePrevious(of: targetEntityID)
          }
          markDeferred(of: triple)
          try Self.validateWriteValue(triple.value, triple: triple, attributes: attributes)
          indexes.apply(
            concreteOperation,
            attributes: attributes,
            insertReplayPolicy: insertReplayPolicy,
            into: &changedEntityIDs
          )

        case let .deleteEntity(entityID):
          captureDeletePrevious(of: entityID)
          indexes.apply(concreteOperation, attributes: attributes, into: &changedEntityIDs)

        case let .deleteEntityInNamespace(entityID, _):
          captureDeletePrevious(of: entityID)
          indexes.apply(concreteOperation, attributes: attributes, into: &changedEntityIDs)

        case .requireEntityMissing, .requireEntityMissingByLookup,
          .requireEntityExists, .requireEntityExistsByLookup,
          .requireTripleExists,
          .mergeByLookup, .insertByLookup, .retractByLookup,
          .deleteEntityByLookup, .ruleParams, .ruleParamsByLookup:
          break
        }
      }
    }

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
        let canonical = try Self.canonicalTripleIdentity(
          entityID: entityID,
          attributeID: attributeID,
          value: value,
          attributes: attributes
        )
        guard
          indexes.containsTriple(
            entityID: canonical.entityID,
            attributeID: canonical.attributeID,
            value: canonical.value,
            attribute: attributes[canonical.attributeID]
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

      case let .insert(triple):
        if case .lookupRef = triple.value {
          try applyResolved(operation)
        } else {
          try applyDirectInsert(triple)
        }

      case let .merge(triple):
        if case .lookupRef = triple.value {
          try applyResolved(operation)
        } else {
          try applyDirectMerge(triple)
        }

      case let .retract(triple):
        if case .lookupRef = triple.value {
          try applyResolved(operation)
        } else {
          try applyDirectRetract(triple)
        }

      case let .deleteEntity(entityID):
        captureDeletePrevious(of: entityID)
        indexes.apply(
          operation,
          attributes: attributes,
          insertReplayPolicy: insertReplayPolicy,
          into: &changedEntityIDs
        )

      case let .deleteEntityInNamespace(entityID, _):
        captureDeletePrevious(of: entityID)
        indexes.apply(
          operation,
          attributes: attributes,
          insertReplayPolicy: insertReplayPolicy,
          into: &changedEntityIDs
        )

      case .mergeByLookup, .insertByLookup, .retractByLookup, .deleteEntityByLookup:
        try applyResolved(operation)
      }
    }

    indexes.finishInternCachesAfterWrite(
      invalidating: changedEntityIDs,
      attributes: attributes
    )

    let nextSequence = sequence + 1
    let result = InstantStoreMutationResult(
      transactionID: transaction.id,
      changedEntityIDs: changedEntityIDs,
      tripleCount: indexes.tripleCount,
      emissions: []
    )
    if capturePreviousChangedEntityTriples {
      for entityID in changedEntityIDs where !previousCapture.contains(entityID) {
        previousCapture.capture(entityID: entityID, from: indexes)
      }
    }
    return PreparedStoreMutation(
      result: result,
      sequence: nextSequence,
      attributes: attributes,
      indexes: indexes,
      previousCapture: previousCapture
    )
  }

  func commit(_ prepared: consuming PreparedStoreMutation) -> PreparedStoreMutation {
    commit(prepared, shouldPublish: false, installingLiveQueryPageInfo: [])
  }

  func commitAndPublish(_ prepared: consuming PreparedStoreMutation) -> PreparedStoreMutation {
    commit(prepared, shouldPublish: true, installingLiveQueryPageInfo: [])
  }

  func commitAndPublish(
    _ prepared: consuming PreparedStoreMutation,
    installingLiveQueryPageInfo replacements: [InstantLiveQueryResultReplacement]
  ) -> PreparedStoreMutation {
    commit(
      prepared,
      shouldPublish: true,
      installingLiveQueryPageInfo: replacements
    )
  }

  private func commit(
    _ prepared: consuming PreparedStoreMutation,
    shouldPublish: Bool,
    installingLiveQueryPageInfo replacements: [InstantLiveQueryResultReplacement]
  ) -> PreparedStoreMutation {
    var prepared = prepared
    prepared.deferredValueRemovalMetrics = prepared.indexes.removeMarkedDeferredValues(
      attributes: prepared.attributes
    )
    if observers.isEmpty {
      self.attributes = prepared.attributes
      self.indexes = prepared.indexes
      self.sequence = prepared.sequence
      lastPublishMetrics = InstantStorePublishMetrics()
      if InstantDiagnostics.shared.isEnabled {
        InstantDiagnostics.shared.record(
          .info,
          subsystem: "instant-swift-data-core",
          category: "store",
          event: shouldPublish ? "store.mutation-published" : "store.mutation-committed",
          message: shouldPublish
            ? "Committed a store mutation and published query emissions."
            : "Committed a store mutation without publishing query emissions.",
          metadata: [
            "changedEntityCount": String(prepared.result.changedEntityIDs.count),
            "emissionCount": "0",
            "observerCount": "0",
            "skippedObserverCount": "0",
            "splicedObserverCount": "0",
            "rematerializedObserverCount": "0",
            "materializedSnapshotCount": "0",
            "sequence": String(sequence),
            "tripleCount": String(prepared.result.tripleCount),
          ],
          correlationID: prepared.result.transactionID
        )
      }
      return prepared
    }

    let previousIndexes = indexes
    let previousAttributes = attributes
    self.attributes = prepared.attributes
    self.indexes = prepared.indexes
    self.sequence = prepared.sequence

    let pageInfoByKey = Self.liveQueryPageInfoByKey(replacements)
    let changedNamespaces: Set<String>?
    if previousAttributes != prepared.attributes {
      changedNamespaces = nil
    } else {
      var resolvedNamespaces: Set<String> = []
      var resolvedEveryEntity = true
      for entityID in prepared.result.changedEntityIDs {
        let entityNamespaces = previousIndexes.namespaces(
          entityID: entityID,
          attributes: previousAttributes
        )
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

    var metrics = InstantStorePublishMetrics()
    var emissionsByObservation: [StoreObservationKey: InstantQueryEmission] = [:]
    for observerID in Array(observers.keys) {
      guard var observer = observers[observerID] else { continue }
      let pageInfoChanged: Bool
      if let liveQueryKey = observer.liveQueryKey,
        let replacementPageInfo = pageInfoByKey[liveQueryKey],
        replacementPageInfo != observer.remotePageInfo
      {
        observer.remotePageInfo = replacementPageInfo
        pageInfoChanged = true
      } else {
        pageInfoChanged = false
      }
      guard
        pageInfoChanged
          || Self.shouldRefresh(
            observer,
            changedNamespaces: changedNamespaces,
            changedEntityIDs: prepared.result.changedEntityIDs,
            indexes: indexes,
            attributes: attributes
          )
      else {
        metrics.skippedObserverCount += 1
        continue
      }
      let key = StoreObservationKey(
        plan: observer.plan,
        remotePageInfo: observer.remotePageInfo
      )
      let emission: InstantQueryEmission
      if let existing = emissionsByObservation[key] {
        emission = existing
      } else if !pageInfoChanged,
        let spliced = Self.splicedEmission(
          observer,
          changedEntityIDs: prepared.result.changedEntityIDs,
          indexes: indexes,
          attributes: attributes,
          sequence: sequence
        ) {
        metrics.splicedObserverCount += 1
        metrics.materializedSnapshotCount += prepared.result.changedEntityIDs.count
        emission = spliced
        emissionsByObservation[key] = emission
      } else {
        let page = indexes.materializePageWithMetrics(
          observer.plan,
          attributes: attributes,
          remotePageInfo: observer.remotePageInfo
        )
        metrics.rematerializedObserverCount += 1
        metrics.materializedSnapshotCount += page.metrics.materializedSnapshotCount
        emission = InstantQueryEmission(
          queryID: observer.plan.id,
          sequence: sequence,
          values: page.page.values,
          pageInfo: page.page.pageInfo
        )
        emissionsByObservation[key] = emission
      }
      observer.apply(emission)
      observers[observerID] = observer
      if shouldPublish {
        observer.continuation.yield(emission)
      }
    }
    lastPublishMetrics = metrics
    var result = prepared.result
    result.emissions =
      emissionsByObservation
      .sorted { lhs, rhs in Self.emissionSortKey(lhs.key) < Self.emissionSortKey(rhs.key) }
      .map(\.value)
    if InstantDiagnostics.shared.isEnabled {
      InstantDiagnostics.shared.record(
        .info,
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
          "skippedObserverCount": String(metrics.skippedObserverCount),
          "splicedObserverCount": String(metrics.splicedObserverCount),
          "rematerializedObserverCount": String(metrics.rematerializedObserverCount),
          "materializedSnapshotCount": String(metrics.materializedSnapshotCount),
          "sequence": String(sequence),
          "tripleCount": String(result.tripleCount),
        ],
        correlationID: result.transactionID
      )
    }
    prepared.result = result
    return prepared
  }

  private static func shouldRefresh(
    _ observer: StoreObserver,
    changedNamespaces: Set<String>?,
    changedEntityIDs: Set<String>,
    indexes: TripleIndexes,
    attributes: AttributeStore
  ) -> Bool {
    guard let changedNamespaces else { return true }
    if let observerNamespaces = observer.plan.dependentNamespaces {
      if observerNamespaces.isDisjoint(with: changedNamespaces) {
        return false
      }
    } else if observer.plan.hasOnlyNamespaceLocalDependencies {
      guard changedNamespaces.contains(observer.plan.namespace) else { return false }
    } else {
      return true
    }
    if observer.plan.filters.isEmpty && (observer.plan.includes?.isEmpty ?? true) {
      return true
    }
    if observer.lastValues.contains(anyEntityID: changedEntityIDs) {
      return true
    }
    if observer.plan.hasOnlyNamespaceLocalDependencies {
      for entityID in changedEntityIDs {
        if indexes.entityMatches(entityID, plan: observer.plan, attributes: attributes) {
          return true
        }
      }
      return false
    }
    return true
  }

  private static func splicedEmission(
    _ observer: StoreObserver,
    changedEntityIDs: Set<String>,
    indexes: TripleIndexes,
    attributes: AttributeStore,
    sequence: Int64
  ) -> InstantQueryEmission? {
    let representedIDs = observer.lastValues.allEntityIDs()
    guard changedEntityIDs.isSubset(of: representedIDs) else { return nil }
    var parentIDsToReplace = Set<String>()
    for snapshot in observer.lastValues {
      if changedEntityIDs.contains(snapshot.id)
        || snapshot.contains(anyEntityID: changedEntityIDs)
      {
        parentIDsToReplace.insert(snapshot.id)
      }
    }
    guard !parentIDsToReplace.isEmpty else { return nil }
    var values = observer.lastValues
    for index in values.indices where parentIDsToReplace.contains(values[index].id) {
      let previous = values[index]
      guard
        let replacement = indexes.entitySnapshot(
          previous.id,
          plan: observer.plan,
          attributes: attributes
        )
      else { return nil }
      if Self.orderKeyChanged(from: previous, to: replacement, plan: observer.plan) {
        return nil
      }
      values[index] = replacement
    }
    return InstantQueryEmission(
      queryID: observer.plan.id,
      sequence: sequence,
      values: values,
      pageInfo: observer.lastPageInfo
    )
  }

  private static func orderKeyChanged(
    from previous: InstantEntitySnapshot,
    to replacement: InstantEntitySnapshot,
    plan: InstantQueryPlan
  ) -> Bool {
    guard let field = plan.order?.field else { return false }
    guard
      let previousValue = previous.values[field],
      let replacementValue = replacement.values[field]
    else {
      // A projection can omit the order field. Without both values an in-place splice cannot
      // prove that the entity stayed at the same position, so rematerialize the ordered result.
      return true
    }
    return previousValue != replacementValue
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
    let attribute = attributes.lookupAttribute(id: attributeID)
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

  private struct CanonicalTripleIdentity: Hashable {
    var entityID: String
    var attributeID: String
    var value: InstantValue
  }

  private static func schemaReconciledIndexes(
    _ indexes: TripleIndexes,
    previousAttributes: AttributeStore,
    mergedAttributes: AttributeStore
  ) -> (indexes: TripleIndexes, changedEntityIDs: Set<String>) {
    var indexes = indexes
    let result = indexes.reconcileRelationStorage(
      previousAttributes: previousAttributes,
      mergedAttributes: mergedAttributes
    )
    return (indexes, result.changedEntityIDs)
  }

  /// Converts a logical reverse relation write into the single physical forward triple.
  ///
  /// The transaction retained in the outbox stays in the caller's logical direction. Only the
  /// optimistic/local-store operation is transposed here, after lookup refs have been resolved.
  private static func canonicalTripleIdentity(
    entityID: String,
    attributeID: String,
    value: InstantValue,
    attributes: AttributeStore
  ) throws -> CanonicalTripleIdentity {
    guard let resolvedAttribute = attributes.lookupAttribute(id: attributeID) else {
      return CanonicalTripleIdentity(
        entityID: entityID,
        attributeID: attributeID,
        value: value
      )
    }

    guard resolvedAttribute.direction == .reverse else {
      return CanonicalTripleIdentity(
        entityID: entityID,
        attributeID: resolvedAttribute.attribute.id,
        value: value
      )
    }

    guard case let .ref(forwardEntityID) = value else {
      throw InstantError(
        code: .validationFailed,
        operation: "write reverse relation",
        namespace: resolvedAttribute.namespace,
        path: resolvedAttribute.name,
        localID: entityID,
        message:
          "Reverse relation '\(attributeID)' requires a reference value before it can be stored.",
        recovery: "Link the related entity by id or by a lookup ref."
      )
    }

    return CanonicalTripleIdentity(
      entityID: forwardEntityID,
      attributeID: resolvedAttribute.attribute.id,
      value: .ref(entityID)
    )
  }

  private static func canonicalizedTripleIfNeeded(
    _ triple: InstantTriple,
    attributes: AttributeStore
  ) throws -> InstantTriple {
    guard let resolved = attributes.lookupAttribute(id: triple.attributeID) else {
      return triple
    }
    if resolved.direction == .forward, resolved.attribute.id == triple.attributeID {
      return triple
    }
    return try canonicalizedTriple(triple, attributes: attributes)
  }

  private static func canonicalizedTriple(
    _ triple: InstantTriple,
    attributes: AttributeStore
  ) throws -> InstantTriple {
    let canonical = try canonicalTripleIdentity(
      entityID: triple.entityID,
      attributeID: triple.attributeID,
      value: triple.value,
      attributes: attributes
    )
    var triple = triple
    triple.entityID = canonical.entityID
    triple.attributeID = canonical.attributeID
    triple.value = canonical.value
    return triple
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
      return [.insert(try canonicalizedTriple(triple, attributes: attributes))]

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
      return [.merge(try canonicalizedTriple(triple, attributes: attributes))]

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
      return [.retract(try canonicalizedTriple(triple, attributes: attributes))]

    case .deleteEntity, .deleteEntityInNamespace:
      return [operation]

    case let .insertByLookup(entity, attributeID, value, txID, txTime):
      guard
        let entityID = try resolveEntityID(
          entity,
          expectedNamespace: attributes.lookupAttribute(id: attributeID)?.namespace,
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
          try canonicalizedTriple(
            InstantTriple(
              entityID: entityID,
              attributeID: attributeID,
              value: value,
              txID: txID,
              txTime: txTime
            ),
            attributes: attributes
          )
        )
      ]

    case let .mergeByLookup(entity, attributeID, value, txID, txTime):
      if attributes.lookupAttribute(id: attributeID)?.attribute.valueType == .ref {
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
          expectedNamespace: attributes.lookupAttribute(id: attributeID)?.namespace,
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
          try canonicalizedTriple(
            InstantTriple(
              entityID: entityID,
              attributeID: attributeID,
              value: value,
              txID: txID,
              txTime: txTime
            ),
            attributes: attributes
          )
        )
      ]

    case let .retractByLookup(entity, attributeID, value, txID, txTime):
      guard
        let entityID = try resolveEntityID(
          entity,
          expectedNamespace: attributes.lookupAttribute(id: attributeID)?.namespace,
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
          try canonicalizedTriple(
            InstantTriple(
              entityID: entityID,
              attributeID: attributeID,
              value: value,
              txID: txID,
              txTime: txTime
            ),
            attributes: attributes
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

    guard let resolvedAttribute = attributes.lookupAttribute(id: attributeID) else {
      throw InstantError(
        code: .validationFailed,
        operation: "resolve lookup ref",
        path: attributeID,
        localID: lookup.description,
        message: "Lookup ref values require a declared destination attribute.",
        recovery: "Declare '\(attributeID)' before using a lookup ref as a triple value."
      )
    }
    let attribute = resolvedAttribute.attribute

    let expectedNamespace: String?
    if attribute.valueType == .ref {
      switch resolvedAttribute.direction {
      case .forward:
        expectedNamespace = attribute.linkNamespace
      case .reverse:
        expectedNamespace = attribute.namespace
      }
    } else {
      expectedNamespace = resolvedAttribute.namespace
    }
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
    try validateWriteValue(
      value,
      triple: triple,
      attribute: attributes[triple.attributeID],
      attributes: attributes
    )
  }

  private static func validateWriteValue(
    _ value: InstantValue,
    triple: InstantTriple,
    attribute: InstantAttribute?,
    attributes: AttributeStore
  ) throws {
    // Namespace existence must be checked before any declared-attribute fast
    // path: forwardAttribute synthesizes primary keys for unknown "<ns>/id"
    // lookups, so a non-nil attribute does not imply a declared namespace.
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

    if let attribute {
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
      return
    }

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
    let initialEmission = materializeEmission(plan, remotePageInfo: remotePageInfo)
    observers[id] = StoreObserver(
      plan: plan,
      remotePageInfo: remotePageInfo,
      liveQueryKey: liveQueryKey,
      lastValues: initialEmission.values,
      lastPageInfo: initialEmission.pageInfo,
      continuation: continuation
    )
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

private extension StoreObserver {
  mutating func apply(_ emission: InstantQueryEmission) {
    lastValues = emission.values
    lastPageInfo = emission.pageInfo
  }
}

extension InstantEntitySnapshot {
  fileprivate func contains(anyEntityID ids: Set<String>) -> Bool {
    if ids.contains(id) { return true }
    return links?.values.contains { children in
      children.contains { $0.contains(anyEntityID: ids) }
    } ?? false
  }

  fileprivate func collectEntityIDs(into ids: inout Set<String>) {
    ids.insert(id)
    for children in (links ?? [:]).values {
      for child in children {
        child.collectEntityIDs(into: &ids)
      }
    }
  }
}

extension InstantLinkedEntitySnapshot {
  fileprivate func contains(anyEntityID ids: Set<String>) -> Bool {
    if ids.contains(id) { return true }
    return links?.values.contains { children in
      children.contains { $0.contains(anyEntityID: ids) }
    } ?? false
  }

  fileprivate func collectEntityIDs(into ids: inout Set<String>) {
    ids.insert(id)
    for children in (links ?? [:]).values {
      for child in children {
        child.collectEntityIDs(into: &ids)
      }
    }
  }
}

extension Array where Element == InstantEntitySnapshot {
  fileprivate func contains(anyEntityID ids: Set<String>) -> Bool {
    contains { $0.contains(anyEntityID: ids) }
  }

  fileprivate func allEntityIDs() -> Set<String> {
    var ids: Set<String> = []
    for snapshot in self {
      snapshot.collectEntityIDs(into: &ids)
    }
    return ids
  }
}

private extension InstantQueryPlan {
  var hasOnlyNamespaceLocalDependencies: Bool {
    (includes?.isEmpty ?? true)
      && hasOnlyNamespaceLocalFieldPaths
  }

  var hasOnlyNamespaceLocalFieldPaths: Bool {
    filters.allSatisfy(\.hasOnlyNamespaceLocalDependencies)
      && !(order?.field.contains(".") ?? false)
      && (selectedFields?.allSatisfy { !$0.contains(".") } ?? true)
  }

  var dependentNamespaces: Set<String>? {
    var namespaces: Set<String> = []
    func walk(_ plan: InstantQueryPlan) -> Bool {
      guard plan.hasOnlyNamespaceLocalFieldPaths else { return false }
      namespaces.insert(plan.namespace)
      for include in plan.includes ?? [] {
        guard let query = include.query else { return false }
        if !walk(query.queryPlan) { return false }
      }
      return true
    }
    guard walk(self) else { return nil }
    return namespaces
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
