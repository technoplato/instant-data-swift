import Foundation
import IssueReporting
import SQLite3

public struct InstantPersistenceSnapshot: Hashable, Codable, Sendable {
  public var store: InstantStoreSnapshot
  public var outbox: [PendingMutation]

  public init(store: InstantStoreSnapshot = InstantStoreSnapshot(), outbox: [PendingMutation] = [])
  {
    self.store = store
    self.outbox = outbox
  }
}

public struct InstantPersistenceState: Hashable, Sendable {
  public var snapshot: InstantPersistenceSnapshot
  public var storeRevision: Int64
  public var attributeRevision: Int64
  public var outboxRevision: Int64
  public var queryResultRevision: Int64

  public init(
    snapshot: InstantPersistenceSnapshot,
    storeRevision: Int64,
    outboxRevision: Int64,
    attributeRevision: Int64? = nil,
    queryResultRevision: Int64 = 0
  ) {
    self.snapshot = snapshot
    self.storeRevision = storeRevision
    self.attributeRevision = attributeRevision ?? storeRevision
    self.outboxRevision = outboxRevision
    self.queryResultRevision = queryResultRevision
  }
}

enum InstantPersistenceStateSource: Equatable, Sendable {
  case memory
  case sqlite
}

struct InstantPersistenceStateLoad: Sendable {
  var state: InstantPersistenceState
  var source: InstantPersistenceStateSource
  var storeAdoption: InstantPersistenceStoreAdoption
}

enum InstantPersistenceStoreAdoption: Sendable {
  case none
  case attributes([InstantAttribute])
  case snapshot(InstantStoreSnapshot)
}

package struct InstantPersistenceCacheResidencyMetrics: Equatable, Sendable {
  package var fullStoreSnapshotLoadCount = 0
  package var fullStateReconstructionCount = 0
  package var storeSnapshotReplacementCount = 0

  package init(
    fullStoreSnapshotLoadCount: Int = 0,
    fullStateReconstructionCount: Int = 0,
    storeSnapshotReplacementCount: Int = 0
  ) {
    self.fullStoreSnapshotLoadCount = fullStoreSnapshotLoadCount
    self.fullStateReconstructionCount = fullStateReconstructionCount
    self.storeSnapshotReplacementCount = storeSnapshotReplacementCount
  }
}

private struct InstantCachedMaterializedStore: Sendable {
  var snapshot: InstantStoreSnapshot
  var storeRevision: Int64
  var attributeRevision: Int64
}

private struct InstantOutboxQuarantineIssueBatch {
  var count = 0
  var exampleMutationIDs: [String] = []
  var firstMessage: String?
  var firstRecovery: String?

  mutating func record(
    mutationID: String,
    message: String,
    recovery: String
  ) {
    count += 1
    if exampleMutationIDs.count < 8 {
      exampleMutationIDs.append(mutationID)
    }
    if firstMessage == nil {
      firstMessage = message
      firstRecovery = recovery
    }
  }
}

struct InstantPersistenceMetadataEntry: Sendable {
  var key: String
  var value: String
  var updatedAt: InstantTimestamp
}

private struct StoredTripleKey: Hashable {
  var entityID: String
  var attributeID: String
  var value: InstantValue

  init(_ triple: InstantTriple) {
    self.entityID = triple.entityID
    self.attributeID = triple.attributeID
    self.value = triple.value
  }
}

private struct LiveQueryOwnershipIdentity: Hashable {
  var entityID: String
  var attributeID: String
  var valueJSON: String
}

private struct InstantApplicationMigrationOutboxRow {
  var mutation: PendingMutation
  var deliveryStarted: Bool
  var confirmationProven: Bool
  var optimisticOverlayActive: Bool
  var optimisticEffectReceiptFingerprint: String?
  var serverAcceptancePayloadFingerprint: String?
}

private struct InstantApplicationMigrationTripleRow {
  var rowID: Int64
  var triple: InstantTriple
}

public struct InstantQueryCachePruningPolicy: Hashable, Codable, Sendable {
  public var maxAgeMilliseconds: Int64?
  public var maxEntries: Int?
  public var maxEncodedJSONBytes: Int?

  public init(
    maxAgeMilliseconds: Int64? = nil,
    maxEntries: Int? = nil,
    maxEncodedJSONBytes: Int? = nil
  ) {
    self.maxAgeMilliseconds = maxAgeMilliseconds
    self.maxEntries = maxEntries
    self.maxEncodedJSONBytes = maxEncodedJSONBytes
  }
}

public struct InstantQueryCachePruningResult: Hashable, Codable, Sendable {
  public var removedCacheKeys: [String]
  public var remainingCacheKeys: [String]
  public var remainingEntryCount: Int
  public var remainingEncodedJSONByteCount: Int

  public init(
    removedCacheKeys: [String],
    remainingCacheKeys: [String],
    remainingEntryCount: Int,
    remainingEncodedJSONByteCount: Int
  ) {
    self.removedCacheKeys = removedCacheKeys
    self.remainingCacheKeys = remainingCacheKeys
    self.remainingEntryCount = remainingEntryCount
    self.remainingEncodedJSONByteCount = remainingEncodedJSONByteCount
  }
}

public struct InstantLiveQueryResultPruningPolicy: Hashable, Codable, Sendable {
  public var maxAgeMilliseconds: Int64?
  public var maxEntries: Int?
  public var maxTripleCount: Int?

  public init(
    maxAgeMilliseconds: Int64? = nil,
    maxEntries: Int? = nil,
    maxTripleCount: Int? = nil
  ) {
    self.maxAgeMilliseconds = maxAgeMilliseconds
    self.maxEntries = maxEntries
    self.maxTripleCount = maxTripleCount
  }
}

public struct InstantLiveQueryResultPruningResult: Hashable, Codable, Sendable {
  public var removedQueryKeys: [String]
  public var remainingQueryKeys: [String]
  public var removedOrphanedTripleCount: Int
  public var remainingEntryCount: Int
  public var remainingTripleCount: Int

  public init(
    removedQueryKeys: [String],
    remainingQueryKeys: [String],
    removedOrphanedTripleCount: Int,
    remainingEntryCount: Int,
    remainingTripleCount: Int
  ) {
    self.removedQueryKeys = removedQueryKeys
    self.remainingQueryKeys = remainingQueryKeys
    self.removedOrphanedTripleCount = removedOrphanedTripleCount
    self.remainingEntryCount = remainingEntryCount
    self.remainingTripleCount = remainingTripleCount
  }
}

struct InstantLiveQueryResultPruningApplication: Sendable {
  var result: InstantLiveQueryResultPruningResult
  var state: InstantPersistenceState
}

private struct LiveQueryResultStorageRow: Sendable {
  var queryKey: String
  var updatedAtMilliseconds: Int64
  var tripleCount: Int
}

private let instantPersistenceDecodeQueue = DispatchQueue(
  label: "com.instantdb.swift.persistence-decode",
  qos: .userInitiated,
  attributes: .concurrent
)

// SAFETY: storage is only read/written under `lock` (NSLock); callers never
// touch `storage` except through store/joined which take the lock.
private final class JSONBatchDecodeResults<Value: Sendable>: @unchecked Sendable {
  private let lock = NSLock()
  private var storage: [Int: Result<[Value], InstantError>] = [:]

  func store(_ result: Result<[Value], InstantError>, at index: Int) {
    lock.withLock { storage[index] = result }
  }

  func joined(batchCount: Int) throws -> [Value] {
    try lock.withLock {
      var values: [Value]?
      for index in 0..<batchCount {
        guard let result = storage.removeValue(forKey: index) else {
          throw InstantError(
            code: .implementationFailed,
            operation: "assemble persisted JSON rows",
            message: "Decoded SQLite JSON batch \(index) was missing.",
            recovery: "Report this missing persistence batch to the Instant Swift maintainer."
          )
        }
        let batch = try result.get()
        if values == nil {
          values = batch
        } else {
          values?.append(contentsOf: batch)
        }
      }
      return values ?? []
    }
  }
}

struct InstantOutboxRowAcceptance: Sendable {
  var mutation: PendingMutation?
  var pendingMutationCount: Int
  var didChange: Bool
  var nextClaimDeadlineMilliseconds: Int64?
}

struct InstantAutomaticOutboxClaimRelease: Sendable {
  var mutationIDs: Set<String>
  var nextClaimDeadlineMilliseconds: Int64?
}

struct InstantOutboxImmediateTailLoad: Sendable {
  var matchesRevisions: Bool
  var mutation: PendingMutation?
}

struct InstantOutboxAliasReplayLoad: Sendable {
  struct Alias: Sendable {
    var currentMutationID: String
    var isPending: Bool
  }

  var matchesRevisions: Bool
  var alias: Alias?
}

struct InstantMutationLifecycleResolution: Sendable {
  var observationID: String
  var event: InstantMutationLifecycleEvent
}

private struct InstantOutboxBodyRow: Sendable {
  var mutationID: String
  var createdAtMilliseconds: Int64
  var json: String
  var optimisticEffectReceiptFingerprint: String?
  var deliveryClaimPayloadFingerprint: String?
  var serverAcceptancePayloadFingerprint: String?
}

private struct InstantTerminalLifecycleRecord: Sendable {
  var json: String
  var optimisticEffectReceiptFingerprint: String?
  var serverAcceptancePayloadFingerprint: String?
}

private enum InstantOutboxInvalidImmediateTail: Sendable {
  case bounded(row: InstantOutboxBodyRow, reason: String)
  case oversized(
    mutationID: String,
    createdAtMilliseconds: Int64,
    metadataByteCount: Int64,
    actualByteCount: Int64
  )

  var mutationID: String {
    switch self {
    case let .bounded(row, _): row.mutationID
    case let .oversized(mutationID, _, _, _): mutationID
    }
  }
}

private struct InstantOutboxDeliveryCandidateRow: Sendable {
  var mutationID: String
  var createdAtMilliseconds: Int64
  var metadataVersion: Int
  var transportStepCount: Int?
  var encodedBodyByteCount: Int
  var status: InstantMutationStatus
  var deliveryStarted: Bool
}

private struct InstantFailedOutboxLifecycleCandidateRow: Sendable {
  var mutationID: String
  var createdAtMilliseconds: Int64
  var lifecycleByteCount: Int?
  var bodyByteCount: Int
  var hasReceiptFingerprint: Bool
}

private struct InstantFailedMutationRetryCandidateRow: Sendable {
  var mutationID: String
  var position: InstantOutboxDeliveryPosition
  var mutationRevision: Int64
  var deliveryState: String?
  var actualBodyByteCount: Int
}

private enum InstantFailedMutationRetryDisposition: Sendable {
  case retry(
    candidate: InstantFailedMutationRetryCandidateRow,
    originalJSON: String,
    mutation: PendingMutation
  )
  case isolate(
    candidate: InstantFailedMutationRetryCandidateRow,
    originalJSON: String,
    mutation: PendingMutation,
    reason: String
  )
  case quarantineCorrupt(
    candidate: InstantFailedMutationRetryCandidateRow,
    row: InstantOutboxBodyRow,
    reason: String
  )
  case quarantineOversized(candidate: InstantFailedMutationRetryCandidateRow)

  var candidate: InstantFailedMutationRetryCandidateRow {
    switch self {
    case let .retry(candidate, _, _),
      let .isolate(candidate, _, _, _),
      let .quarantineCorrupt(candidate, _, _),
      let .quarantineOversized(candidate):
      candidate
    }
  }

  var originalJSON: String? {
    switch self {
    case let .retry(_, originalJSON, _),
      let .isolate(_, originalJSON, _, _):
      originalJSON
    case let .quarantineCorrupt(_, row, _):
      row.json
    case .quarantineOversized:
      nil
    }
  }
}

private struct InstantFailedMutationRetryPlan: Sendable {
  var dispositions: [InstantFailedMutationRetryDisposition]
  var decodedBodyCount: Int
  var decodedBodyByteCount: Int
  var expectedAttributeRevision: Int64

  var nextPosition: InstantOutboxDeliveryPosition? {
    dispositions.last?.candidate.position
  }
}

struct InstantAutomaticFailedMutationRetryApplication: Sendable {
  var retriedMutations: [PendingMutation]
  var isolatedMutations: [PendingMutation]
  var quarantinedMutations: [PendingMutation]
  var decodedBodyCount: Int
  var decodedBodyByteCount: Int
  var nextPosition: InstantOutboxDeliveryPosition?
  var hasMoreCandidates: Bool
}

private struct InstantOptimisticEffectRow: Sendable {
  var mutationID: String
  var position: InstantOutboxDeliveryPosition
  var mutationRevision: Int64
  var metadataVersion: Int
  var isGlobal: Bool
  var encodedBodyByteCount: Int
}

private enum InstantOptimisticEffectReceiptWriteAuthority {
  case runtimePrepared
  case publicPersistence
}

package struct InstantOptimisticEffectReceiptValidation: Sendable {
  package var matchesOutboxRevision: Bool
  package var firstUntrustedMutationID: String?
}

private struct InstantOptimisticEffectComponentRows: Sendable {
  var target: InstantOptimisticEffectRow
  var successors: [InstantOptimisticEffectRow]

  var all: [InstantOptimisticEffectRow] {
    [target] + successors
  }

  var ids: Set<String> {
    Set(all.map(\.mutationID))
  }
}

private struct InstantTerminalFailureTargetControl: Sendable {
  var effect: InstantOptimisticEffectRow
  var status: InstantMutationStatus
  var confirmationProven: Bool
  var deliveryState: InstantOutboxDeliveryState
  var claimState: InstantOutboxDeliveryClaimState
  var claimToken: String?
}

private enum InstantOptimisticEffectComponentRowsResolution: Sendable {
  case ready(InstantOptimisticEffectComponentRows)
  case normalizationRequired(mutationID: String)
}

struct InstantServerApplyFootprint: Sendable {
  var entityIDs: Set<String>
  var isGlobal: Bool
}

struct InstantServerApplyPlan: Sendable {
  var id: String
  var expectedStoreRevision: Int64
  var expectedAttributeRevision: Int64
  var expectedOutboxRevision: Int64
  var expectedQueryResultRevision: Int64
  var baselineOutboxRowCount: Int
  var baselineOutboxTail: InstantOutboxDeliveryPosition?
  var plannedBodyCount: Int
  var plannedBodyByteCount: Int
}

struct InstantServerApplyCatchUp: Sendable {
  var previousTail: InstantOutboxDeliveryPosition?
  var currentTail: InstantOutboxDeliveryPosition?
  var currentOutboxRowCount: Int
  var appendedBodyCount: Int
  var appendedBodyByteCount: Int
}

enum InstantServerApplyCatchUpLoad: Sendable {
  case ready(InstantServerApplyCatchUp)
  case stale
}

enum InstantServerApplyPlanLoad: Sendable {
  case ready(InstantServerApplyPlan)
  case normalizationRequired(firstMutationID: String)
}

enum InstantServerApplyBodyDirection: Sendable, Equatable {
  case reverse
  case forward
}

struct InstantServerApplyBodyEntry: Sendable {
  var mutation: PendingMutation
  var isComponentBody: Bool
  var shouldPruneAtWatermark: Bool
  var shouldConfirm: Bool
}

struct InstantServerApplyBodyPage: Sendable {
  var isStale: Bool
  var entries: [InstantServerApplyBodyEntry]
  var nextPosition: InstantOutboxDeliveryPosition?
  var decodedBodyByteCount: Int
  var synchronizationBlocker: InstantSynchronizationBlocker? = nil
}

enum InstantServerApplyStagedDisposition: Sendable {
  case update(PendingMutation)
  case remove(mutationID: String)

  var mutationID: String {
    switch self {
    case let .update(mutation): mutation.id
    case let .remove(mutationID): mutationID
    }
  }
}

struct InstantServerApplyCommit: Sendable {
  var pendingMutationCount: Int
  var expectedStoreRevision: Int64
  var expectedAttributeRevision: Int64
  var expectedOutboxRevision: Int64
  var expectedQueryResultRevision: Int64
  var didChangeStore: Bool
  var didChangeAttributes: Bool
  var didChangeOutbox: Bool
  var didChangeQueryResults: Bool
}

struct InstantServerApplyResidentPatchPage: Sendable {
  var removedMutationIDs: [String]
  var replacementMutations: [PendingMutation]
  var nextPosition: InstantOutboxDeliveryPosition?
}

private struct InstantServerApplyPlanControl: Sendable {
  var expectedStoreRevision: Int64
  var expectedAttributeRevision: Int64
  var expectedOutboxRevision: Int64
  var expectedQueryResultRevision: Int64
  var processedTransactionID: String
  var processedTransactionNumber: Int64?
  var hasServerOperations: Bool
  var rootIsGlobal: Bool
  var confirmingMutationID: String?
  var confirmingClaimantID: String?
}

private struct InstantServerApplyBodyCandidate: Sendable {
  var mutationID: String
  var position: InstantOutboxDeliveryPosition
  var actualBodyByteCount: Int
  var shouldPruneAtWatermark: Bool
  var shouldConfirm: Bool
}

private struct InstantServerApplyResidentPatchCandidate: Sendable {
  var mutationID: String
  var position: InstantOutboxDeliveryPosition
  var isDeletion: Bool
  var actualLifecycleByteCount: Int
}

package struct InstantTerminalFailureMetadataMetrics: Equatable, Sendable {
  var outboxRowCount = 0
  var effectEntityRowCount = 0
  var maximumEntityFrontierRowCount = 0
  var entityFrontierSortCount = 0
  var entityFrontierFullScanStepCount = 0
}

package struct InstantFailedMutationRetryMetrics: Equatable, Sendable {
  package var completedWindowCount = 0
  package var totalCandidateRowCount = 0
  package var totalDecodedBodyCount = 0
  package var totalDecodedBodyByteCount = 0
  package var maximumCandidateRowCount = 0
  package var maximumDecodedBodyCount = 0
  package var maximumDecodedBodyByteCount = 0
  package var lastDecodedBodyCount = 0
  package var candidateSortCount = 0
  package var candidateFullScanStepCount = 0
}

package struct InstantServerApplyMetrics: Equatable, Sendable {
  package var planCount = 0
  package var plannedBodyCount = 0
  package var plannedBodyByteCount = 0
  package var decodedBodyCount = 0
  package var decodedBodyByteCount = 0
  package var reverseBodyPageCount = 0
  package var forwardBodyPageCount = 0
  package var reverseBodyRowCount = 0
  package var forwardBodyRowCount = 0
  package var reverseMaximumBodyPageCount = 0
  package var forwardMaximumBodyPageCount = 0
  package var reverseLastBodyPageCount = 0
  package var forwardLastBodyPageCount = 0
  package var maximumBodyPageCount = 0
  package var maximumBodyPageByteCount = 0
  package var residentPatchPageCount = 0
  package var residentPatchRowCount = 0
  package var maximumResidentPatchPageCount = 0
  package var maximumResidentPatchPageByteCount = 0
  package var commitAttemptCount = 0
  package var staleCommitCount = 0

  mutating func recordBodyPage(
    direction: InstantServerApplyBodyDirection,
    bodyCount: Int,
    bodyByteCount: Int
  ) {
    decodedBodyCount += bodyCount
    decodedBodyByteCount += bodyByteCount
    maximumBodyPageCount = max(maximumBodyPageCount, bodyCount)
    maximumBodyPageByteCount = max(maximumBodyPageByteCount, bodyByteCount)
    guard bodyCount > 0 else { return }
    switch direction {
    case .reverse:
      reverseBodyPageCount += 1
      reverseBodyRowCount += bodyCount
      reverseMaximumBodyPageCount = max(reverseMaximumBodyPageCount, bodyCount)
      reverseLastBodyPageCount = bodyCount
    case .forward:
      forwardBodyPageCount += 1
      forwardBodyRowCount += bodyCount
      forwardMaximumBodyPageCount = max(forwardMaximumBodyPageCount, bodyCount)
      forwardLastBodyPageCount = bodyCount
    }
  }

  mutating func recordResidentPatchPage(rowCount: Int, lifecycleByteCount: Int) {
    guard rowCount > 0 else { return }
    residentPatchPageCount += 1
    residentPatchRowCount += rowCount
    maximumResidentPatchPageCount = max(maximumResidentPatchPageCount, rowCount)
    maximumResidentPatchPageByteCount = max(
      maximumResidentPatchPageByteCount,
      lifecycleByteCount
    )
  }
}

enum InstantAutomaticFailedMutationRetryPolicy {
  static func isIndependentlyRetryableFailureMessage(_ rawMessage: String) -> Bool {
    let message = rawMessage.lowercased()
    return message.contains("operation timed out")
      || message.contains("transaction timed out")
      || message.contains("service unavailable")
      || message.contains("temporarily unavailable")
  }

  static func awaitsAttributeRevisionChange(_ rawMessage: String) -> Bool {
    rawMessage.lowercased().contains("could not resolve")
  }

  static func isRetryableFailureMessage(_ rawMessage: String) -> Bool {
    isIndependentlyRetryableFailureMessage(rawMessage)
      || awaitsAttributeRevisionChange(rawMessage)
  }
}

public actor SQLitePersistenceStore {
  private static let automaticFailedMutationRetryEligibilitySQL =
    """
    status = 'failed'
    AND optimistic_overlay_active = 1
    AND delivery_claim_state = 'ready'
    AND COALESCE(delivery_state, '') != 'invalid'
    AND (
      instr(lower(COALESCE(failure_message, '')), 'operation timed out') > 0
      OR instr(lower(COALESCE(failure_message, '')), 'transaction timed out') > 0
      OR instr(lower(COALESCE(failure_message, '')), 'service unavailable') > 0
      OR instr(lower(COALESCE(failure_message, '')), 'temporarily unavailable') > 0
      OR instr(lower(COALESCE(failure_message, '')), 'could not resolve') > 0
    )
    """
  private static let automaticFailedMutationRetryAttributeRevisionSQL =
    """
    AND (
      instr(lower(COALESCE(failure_message, '')), 'could not resolve') = 0
      OR failure_attribute_revision IS NULL
      OR failure_attribute_revision != ?
    )
    """
  private let fileURL: URL
  private let startupTrace: InstantStartupTrace
  private let deferredValueResidency: InstantDeferredValueResidencyPolicy
  private let declaredAttributes: [InstantAttribute]
  private let connection: SQLiteConnection
  private let encoder: JSONEncoder
  private let decoder: JSONDecoder
  private var cachedState: InstantPersistenceState?
  private var cachedMaterializedStore: InstantCachedMaterializedStore?
  private var activeOutboxQuarantineIssueBatch: InstantOutboxQuarantineIssueBatch?
  private var didTraceInitialStateLoad = false
  private var cacheResidencyMetrics = InstantPersistenceCacheResidencyMetrics()
  /// Test-visible count of durable outbox JSON bodies decoded by this actor.
  /// This pins acknowledgement and delivery complexity to their selected rows.
  private var decodedOutboxBodyCount = 0
  private var decodedOutboxBodyByteCount = 0
  private var materializedOutboxBodyCount = 0
  private var materializedOutboxBodyByteCount = 0
  private var decodedOutboxLifecycleCount = 0
  private var decodedOutboxLifecycleByteCount = 0
  private var maximumAutomaticOutboxWindowBodyCount = 0
  private var maximumAutomaticOutboxWindowBodyByteCount = 0
  private var decodedVisibleRequiredScalarCount = 0
  private var decodedVisibleRequiredScalarValueByteCount = 0
  private var onInvalidImmediateSupersessionTailReadForTesting:
    (@Sendable (_ mutationID: String) async -> Void)?
  /// A regression sentinel: row-addressed local enqueue must never reconstruct
  /// the durable queue. Public/full-state APIs increment this when they do.
  private var localMutationQueueWideReadCount = 0
  private var deferredValueDecodeMetrics = InstantDeferredValueDecodeMetrics()
  private var terminalFailureMetadataMetrics = InstantTerminalFailureMetadataMetrics()
  private var failedMutationRetryMetrics = InstantFailedMutationRetryMetrics()
  private var serverApplyMetrics = InstantServerApplyMetrics()
  private var declaredRelationReconciliationLiveResultScanCount = 0
  private var installedDeclaredRelationStorageMarker:
    DeclaredRelationStorageReconciliationMarker?
  private var installedDeclaredRelationStorageObsoleteAttributeIDs: Set<String> = []
  private var didLoadDeclaredRelationStorageMarker = false
  private var onFailedMutationRetryWindowLoadedForTesting:
    (@Sendable (_ mutationIDs: [String]) async throws -> Void)?

  package func deferredValueDecodeMetricsForTesting() -> InstantDeferredValueDecodeMetrics {
    deferredValueDecodeMetrics
  }

  package func declaredRelationReconciliationLiveResultScanCountForTesting() -> Int {
    declaredRelationReconciliationLiveResultScanCount
  }

  package func resetCacheResidencyMetricsForTesting() {
    cacheResidencyMetrics = InstantPersistenceCacheResidencyMetrics()
  }

  package func cacheResidencyMetricsForTesting() -> InstantPersistenceCacheResidencyMetrics {
    cacheResidencyMetrics
  }

  /// Distinct `instant_triples.entity_id` rows on disk, including entities the
  /// hot store snapshot omitted after a query-scoped bootstrap load.
  package func storedTripleEntityCountForTesting() throws -> Int {
    try readTransaction {
      Int(try selectInt64("SELECT COUNT(DISTINCT entity_id) FROM instant_triples"))
    }
  }

  package func resetDecodedOutboxBodyCount() {
    decodedOutboxBodyCount = 0
    decodedOutboxBodyByteCount = 0
    materializedOutboxBodyCount = 0
    materializedOutboxBodyByteCount = 0
    decodedOutboxLifecycleCount = 0
    decodedOutboxLifecycleByteCount = 0
    maximumAutomaticOutboxWindowBodyCount = 0
    maximumAutomaticOutboxWindowBodyByteCount = 0
  }

  package func resetVisibleRequiredScalarDecodeMetricsForTesting() {
    decodedVisibleRequiredScalarCount = 0
    decodedVisibleRequiredScalarValueByteCount = 0
  }

  package func decodedVisibleRequiredScalarCountForTesting() -> Int {
    decodedVisibleRequiredScalarCount
  }

  package func decodedVisibleRequiredScalarValueByteCountForTesting() -> Int {
    decodedVisibleRequiredScalarValueByteCount
  }

  package func currentDecodedOutboxBodyCount() -> Int {
    decodedOutboxBodyCount
  }

  package func resetTerminalFailureMetadataMetricsForTesting() {
    terminalFailureMetadataMetrics = InstantTerminalFailureMetadataMetrics()
  }

  package func terminalFailureMetadataMetricsForTesting()
    -> InstantTerminalFailureMetadataMetrics
  {
    terminalFailureMetadataMetrics
  }

  package func resetFailedMutationRetryMetricsForTesting() {
    failedMutationRetryMetrics = InstantFailedMutationRetryMetrics()
  }

  package func failedMutationRetryMetricsForTesting() -> InstantFailedMutationRetryMetrics {
    failedMutationRetryMetrics
  }

  package func resetServerApplyMetricsForTesting() {
    serverApplyMetrics = InstantServerApplyMetrics()
  }

  package func serverApplyMetricsForTesting() -> InstantServerApplyMetrics {
    serverApplyMetrics
  }

  package func setFailedMutationRetryWindowLoadedHookForTesting(
    _ hook: (@Sendable (_ mutationIDs: [String]) async throws -> Void)?
  ) {
    onFailedMutationRetryWindowLoadedForTesting = hook
  }

  package func currentDecodedOutboxBodyByteCount() -> Int {
    decodedOutboxBodyByteCount
  }

  package func currentMaterializedOutboxBodyCount() -> Int {
    materializedOutboxBodyCount
  }

  package func currentMaterializedOutboxBodyByteCount() -> Int {
    materializedOutboxBodyByteCount
  }

  package func currentDecodedOutboxLifecycleCount() -> Int {
    decodedOutboxLifecycleCount
  }

  package func currentDecodedOutboxLifecycleByteCount() -> Int {
    decodedOutboxLifecycleByteCount
  }

  package func maximumAutomaticOutboxWindowBodyCountForTesting() -> Int {
    maximumAutomaticOutboxWindowBodyCount
  }

  package func maximumAutomaticOutboxWindowBodyByteCountForTesting() -> Int {
    maximumAutomaticOutboxWindowBodyByteCount
  }

  package func setInvalidImmediateSupersessionTailReadHookForTesting(
    _ hook: (@Sendable (_ mutationID: String) async -> Void)?
  ) {
    onInvalidImmediateSupersessionTailReadForTesting = hook
  }

  package func outboxDeliveryStartedForTesting(id: String) throws -> Bool {
    try selectInt64(
      "SELECT delivery_started FROM instant_outbox WHERE mutation_id = ? LIMIT 1",
      [.text(id)]
    ) != 0
  }

  package func outboxMutationRevisionForTesting(id: String) throws -> Int64 {
    try selectInt64(
      "SELECT mutation_revision FROM instant_outbox WHERE mutation_id = ? LIMIT 1",
      [.text(id)]
    )
  }

  package func fileURLForTesting() -> URL {
    fileURL
  }

  package func quarantinedOutboxBodyForTesting(id: String) throws -> String? {
    try selectScalar(
      "SELECT quarantine_json FROM instant_outbox WHERE mutation_id = ? LIMIT 1",
      [.text(id)]
    )
  }

  package func quarantinedOutboxBodyByteCountForTesting(id: String) throws -> Int {
    Int(try selectInt64(
      """
      SELECT COALESCE(length(CAST(quarantine_json AS BLOB)), 0)
      FROM instant_outbox
      WHERE mutation_id = ?
      LIMIT 1
      """,
      [.text(id)]
    ))
  }

  package func localMutationQueueWideReadCountForTesting() -> Int {
    localMutationQueueWideReadCount
  }

  package func outboxLifecycleCountsForTesting() throws
    -> (lifecycles: Int, aliases: Int)
  {
    (
      lifecycles: Int(try selectInt64("SELECT COUNT(*) FROM instant_outbox_lifecycles")),
      aliases: Int(try selectInt64("SELECT COUNT(*) FROM instant_outbox_lifecycle_aliases"))
    )
  }

  package func maximumOutboxLifecycleAliasMetadataByteCountForTesting() throws -> Int {
    Int(try selectInt64(
      """
      SELECT COALESCE(MAX(
        length(CAST(mutation_id AS BLOB)) + length(CAST(lifecycle_id AS BLOB))
      ), 0)
      FROM instant_outbox_lifecycle_aliases
      """
    ))
  }

  package func removeMutationLifecycleMetadataForTesting(id: String) throws {
    try transaction {
      let lifecycleID = try lifecycleIDWithoutTransaction(for: id) ?? id
      try execute(
        "DELETE FROM instant_outbox_lifecycle_aliases WHERE lifecycle_id = ?",
        [.text(lifecycleID)]
      )
      try execute(
        "DELETE FROM instant_outbox_lifecycles WHERE lifecycle_id = ?",
        [.text(lifecycleID)]
      )
    }
  }

  func outboxDeliveryClaimForTesting(id: String) throws
    -> InstantOutboxDeliveryClaim?
  {
    var statement: OpaquePointer?
    try prepare(
      """
      SELECT delivery_claim_state, delivery_claim_token, delivery_claimant_id,
             delivery_claim_deadline_ms, delivery_claim_projected_body_bytes,
             delivery_started
      FROM instant_outbox
      WHERE mutation_id = ?
      LIMIT 1
      """,
      statement: &statement
    )
    defer { sqlite3_finalize(statement) }
    try bind([.text(id)], to: statement)
    guard sqlite3_step(statement) == SQLITE_ROW,
      let stateBytes = sqlite3_column_text(statement, 0),
      let state = InstantOutboxDeliveryClaimState(rawValue: String(cString: stateBytes))
    else { return nil }
    return InstantOutboxDeliveryClaim(
      state: state,
      claimToken: sqlite3_column_text(statement, 1).map(String.init(cString:)),
      claimantID: sqlite3_column_text(statement, 2).map(String.init(cString:)),
      deadlineMilliseconds: sqlite3_column_type(statement, 3) == SQLITE_NULL
        ? nil
        : sqlite3_column_int64(statement, 3),
      projectedBodyByteCount: sqlite3_column_type(statement, 4) == SQLITE_NULL
        ? nil
        : Int(sqlite3_column_int64(statement, 4)),
      deliveryStarted: sqlite3_column_int64(statement, 5) != 0
    )
  }

  package func claimOutboxMutationWithoutHydrationForTesting(
    id: String,
    claimantID: String,
    claimToken: String,
    deadlineMilliseconds: Int64
  ) throws -> Bool {
    try transaction {
      guard let row = try loadOutboxBodyRowWithoutTransaction(id: id),
        let mutation: PendingMutation = try? decodeOutboxBody(row.json),
        try hasStoredPreparedOptimisticEffectReceipt(mutation, in: row)
      else { return false }
      let projectedBodyByteCount = Int(try selectInt64(
        """
        SELECT COALESCE(encoded_body_bytes, length(CAST(json AS BLOB)))
        FROM instant_outbox
        WHERE mutation_id = ?
        LIMIT 1
        """,
        [.text(id)]
      ))
      try claimOutboxMutationWithoutTransaction(
        id: id,
        claimantID: claimantID,
        claimToken: claimToken,
        deadlineMilliseconds: deadlineMilliseconds,
        projectedBodyByteCount: projectedBodyByteCount,
        payloadFingerprint: try mutation.mutationWireIntentFingerprint()
      )
      return sqlite3_changes(connection.raw) == 1
    }
  }

  /// Drop the full triples array from the in-memory persistence cache.
  ///
  /// InstantStore already holds the hot corpus as TripleIndexes (EAV/AEV/VAE).
  /// Keeping a second full `InstantStoreSnapshot.triples` in `cachedState` is the
  /// dual-residency floor (production readiness P2.1). Attributes + outbox +
  /// revisions stay resident; triples reload from SQLite on cache miss.
  ///
  /// Autoresearch: 2026-08-07-scribe-list-memory / #044.
  /// When true, keep the second full triples array in memory (legacy dual residency).
  /// Default false (P2.1 thin cache). Autoresearch A/B uses this toggle.
  nonisolated(unsafe) package static var retainFullTriplesInMemoryForTesting = false


  public func invalidateMemoryCache() {
    cachedState = nil
    cachedMaterializedStore = nil
  }

  private func adoptCachedState(
    _ state: InstantPersistenceState,
    shrinkingSQLiteMemory: Bool = true
  ) {
    var thin = state
    // Durable outbox rows are cursor-addressed in SQLite. Keeping even compact
    // lifecycle shells here makes cold-start memory proportional to queue depth.
    thin.snapshot.outbox = []
    if !Self.retainFullTriplesInMemoryForTesting {
      if !thin.snapshot.store.triples.isEmpty {
        thin.snapshot.store = InstantStoreSnapshot(
          attributes: thin.snapshot.store.attributes,
          triples: []
        )
      }
    }
    cachedState = thin
    cachedMaterializedStore = InstantCachedMaterializedStore(
      snapshot: thin.snapshot.store,
      storeRevision: thin.storeRevision,
      attributeRevision: thin.attributeRevision
    )
    if shrinkingSQLiteMemory {
      try? execute("PRAGMA shrink_memory")
    }
  }

  private func advanceCachedRevisionDomains(
    expectedStoreRevision: Int64,
    expectedAttributeRevision: Int64,
    expectedOutboxRevision: Int64,
    expectedQueryResultRevision: Int64,
    changedEntityTriples: [String: [InstantTriple]],
    mergingAttributes attributes: [InstantAttribute],
    storeChanged: Bool,
    attributesChanged: Bool,
    outboxChanged: Bool,
    queryResultsChanged: Bool
  ) {
    let resultingStoreRevision = expectedStoreRevision + (storeChanged ? 1 : 0)
    let resultingAttributeRevision =
      expectedAttributeRevision + (attributesChanged ? 1 : 0)
    let resultingOutboxRevision = expectedOutboxRevision + (outboxChanged ? 1 : 0)
    let resultingQueryResultRevision =
      expectedQueryResultRevision + (queryResultsChanged ? 1 : 0)

    func advanceStore(_ snapshot: inout InstantStoreSnapshot) {
      if storeChanged, !snapshot.triples.isEmpty {
        replaceCachedTriples(
          in: &snapshot.triples,
          with: changedEntityTriples
        )
      }
      if attributesChanged {
        var attributeStore = AttributeStore(attributes: snapshot.attributes)
        attributeStore.merge(attributes)
        snapshot.attributes = attributeStore.attributes
      }
    }

    if var state = cachedState,
      state.storeRevision == expectedStoreRevision,
      state.attributeRevision == expectedAttributeRevision,
      state.outboxRevision == expectedOutboxRevision,
      state.queryResultRevision == expectedQueryResultRevision
    {
      advanceStore(&state.snapshot.store)
      state.snapshot.outbox = []
      state.storeRevision = resultingStoreRevision
      state.attributeRevision = resultingAttributeRevision
      state.outboxRevision = resultingOutboxRevision
      state.queryResultRevision = resultingQueryResultRevision
      adoptCachedState(state, shrinkingSQLiteMemory: false)
      return
    }

    cachedState = nil
    if var materializedStore = cachedMaterializedStore,
      materializedStore.storeRevision == expectedStoreRevision,
      materializedStore.attributeRevision == expectedAttributeRevision
    {
      advanceStore(&materializedStore.snapshot)
      materializedStore.storeRevision = resultingStoreRevision
      materializedStore.attributeRevision = resultingAttributeRevision
      cachedMaterializedStore = materializedStore
    }
  }



  public init(
    fileURL: URL,
    startupTrace: InstantStartupTrace = .disabled,
    deferredValueResidency: InstantDeferredValueResidencyPolicy = .none,
    declaredAttributes: [InstantAttribute] = []
  ) throws {
    self.fileURL = fileURL
    self.startupTrace = startupTrace
    self.deferredValueResidency = deferredValueResidency
    self.declaredAttributes = declaredAttributes
    self.encoder = JSONEncoder()
    self.encoder.outputFormatting = [.sortedKeys]
    self.decoder = JSONDecoder()
    let stopwatch = startupTrace.started(
      "sqlite.open",
      metadata: ["file": fileURL.lastPathComponent]
    )
    InstantDiagnostics.shared.record(
      .debug,
      subsystem: "instant-swift-data-core",
      category: "persistence",
      event: "sqlite.open-started",
      message: "Opening the Instant SQLite cache.",
      metadata: ["path": fileURL.path]
    )
    do {
      self.connection = SQLiteConnection(try Self.openRawConnection(fileURL: fileURL))
      startupTrace.completed(
        "sqlite.open",
        since: stopwatch,
        metadata: ["file": fileURL.lastPathComponent]
      )
      InstantDiagnostics.shared.record(
        .notice,
        subsystem: "instant-swift-data-core",
        category: "persistence",
        event: "sqlite.open-completed",
        message: "Opened the Instant SQLite cache.",
        metadata: ["path": fileURL.path]
      )
    } catch {
      startupTrace.failed(
        "sqlite.open",
        error: error,
        since: stopwatch,
        metadata: ["file": fileURL.lastPathComponent]
      )
      InstantDiagnostics.shared.record(
        error: error,
        subsystem: "instant-swift-data-core",
        category: "persistence",
        event: "sqlite.open-failed",
        message: "Failed to open the Instant SQLite cache.",
        metadata: ["path": fileURL.path]
      )
      throw error
    }
  }

  private static func openRawConnection(fileURL: URL) throws -> OpaquePointer? {
    let directory = fileURL.deletingLastPathComponent()
    let fileManager = FileManager.default
    if !fileManager.fileExists(atPath: directory.path) {
      try fileManager.createDirectory(
        at: directory,
        withIntermediateDirectories: true,
        attributes: [.posixPermissions: 0o700]
      )
    }

    var opened: OpaquePointer?
    let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
    guard sqlite3_open_v2(fileURL.path, &opened, flags, nil) == SQLITE_OK
    else {
      let message =
        opened.flatMap { sqlite3_errmsg($0) }.map { String(cString: $0) }
        ?? "SQLite could not open \(fileURL.path)."
      sqlite3_close(opened)
      throw InstantError(
        code: .persistenceFailed,
        operation: "open local cache",
        message: message,
        recovery: "Check that the cache directory is writable, or choose another persistence path."
      )
    }
    do {
      try securePersistenceFile(at: fileURL)
    } catch {
      sqlite3_close(opened)
      throw InstantError(
        code: .persistenceFailed,
        operation: "secure local cache",
        message: "SQLite opened the local cache but could not restrict its file permissions: \(error)",
        recovery: "Choose a persistence path whose file permissions can be changed."
      )
    }
    guard sqlite3_busy_timeout(opened, 10_000) == SQLITE_OK else {
      let message =
        opened.flatMap { sqlite3_errmsg($0) }.map { String(cString: $0) }
        ?? "SQLite could not configure a busy timeout for \(fileURL.path)."
      sqlite3_close(opened)
      throw InstantError(
        code: .persistenceFailed,
        operation: "configure local cache",
        message: message,
        recovery: "Check that the cache directory is writable, or choose another persistence path."
      )
    }
    guard sqlite3_exec(opened, "PRAGMA foreign_keys = ON", nil, nil, nil) == SQLITE_OK else {
      let message =
        opened.flatMap { sqlite3_errmsg($0) }.map { String(cString: $0) }
        ?? "SQLite could not enable foreign keys for \(fileURL.path)."
      sqlite3_close(opened)
      throw InstantError(
        code: .persistenceFailed,
        operation: "configure local cache",
        message: message,
        recovery: "Check that the cache directory is writable, or choose another persistence path."
      )
    }
    return opened
  }

  private static func securePersistenceFile(at fileURL: URL) throws {
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o600],
      ofItemAtPath: fileURL.path
    )
  }

  private static func securePersistenceFiles(at fileURL: URL) throws {
    let fileManager = FileManager.default
    for url in [
      fileURL,
      URL(fileURLWithPath: fileURL.path + "-wal"),
      URL(fileURLWithPath: fileURL.path + "-shm"),
    ] where fileManager.fileExists(atPath: url.path) {
      try securePersistenceFile(at: url)
    }
  }

  public func bootstrap() throws {
    let stopwatch = startupTrace.started(
      "sqlite.schema",
      metadata: ["file": fileURL.lastPathComponent]
    )
    do {
    try Self.securePersistenceFiles(at: fileURL)
    InstantDiagnostics.shared.record(
      .debug,
      subsystem: "instant-swift-data-core",
      category: "persistence",
      event: "sqlite.bootstrap-started",
      message: "Bootstrapping the Instant SQLite schema.",
      metadata: ["path": fileURL.path]
    )
    startupTrace.completed(
      "sqlite.schema",
      since: stopwatch,
      metadata: ["file": fileURL.lastPathComponent]
    )
    } catch {
      startupTrace.failed(
        "sqlite.schema",
        error: error,
        since: stopwatch,
        metadata: ["file": fileURL.lastPathComponent]
      )
      throw error
    }
    try withSQLiteBusyRetry {
      try execute("PRAGMA journal_mode = WAL")
    // Keep SQLite page cache tiny once InstantStore holds the hot corpus.
    try execute("PRAGMA cache_size = 0")  // ~2MiB

    }
    try execute("PRAGMA foreign_keys = ON")
    try withSQLiteBusyRetry {
      try execute(
        """
        CREATE TABLE IF NOT EXISTS instant_schema_migrations (
          name TEXT PRIMARY KEY NOT NULL,
          applied_at_ms INTEGER NOT NULL
        )
        """
      )
    }
    try withSQLiteBusyRetry {
      try migrate(name: "0001_initial_cache") {
        try execute(
          """
          CREATE TABLE IF NOT EXISTS instant_attributes (
            id TEXT PRIMARY KEY NOT NULL,
            json TEXT NOT NULL
          )
          """
        )
        try execute(
          """
          CREATE TABLE IF NOT EXISTS instant_triples (
            entity_id TEXT NOT NULL,
            attribute_id TEXT NOT NULL,
            value_json TEXT NOT NULL,
            tx_id TEXT NOT NULL,
            tx_time_ms INTEGER NOT NULL,
            json TEXT NOT NULL,
            PRIMARY KEY (entity_id, attribute_id, value_json)
          )
          """
        )
        try execute(
          """
          CREATE TABLE IF NOT EXISTS instant_outbox (
            mutation_id TEXT PRIMARY KEY NOT NULL,
            status TEXT NOT NULL,
            created_at_ms INTEGER NOT NULL,
            json TEXT NOT NULL
          )
          """
        )
        try execute(
          """
          CREATE TABLE IF NOT EXISTS instant_local_ids (
            name TEXT PRIMARY KEY NOT NULL,
            entity_id TEXT NOT NULL
          )
          """
        )
        try execute(
          """
          CREATE TABLE IF NOT EXISTS instant_auth_sessions (
            key TEXT PRIMARY KEY NOT NULL,
            json TEXT NOT NULL,
            updated_at_ms INTEGER NOT NULL
          )
          """
        )
        try execute(
          """
          CREATE TABLE IF NOT EXISTS instant_query_cache (
            query_id TEXT PRIMARY KEY NOT NULL,
            json TEXT NOT NULL,
            updated_at_ms INTEGER NOT NULL
          )
          """
        )
        try execute(
          """
          CREATE TABLE IF NOT EXISTS instant_sync_metadata (
            key TEXT PRIMARY KEY NOT NULL,
            value TEXT NOT NULL,
            updated_at_ms INTEGER NOT NULL
          )
          """
        )
      }
    }
    try withSQLiteBusyRetry {
      try migrate(name: "0002_magic_code_challenges") {
        try execute(
          """
          CREATE TABLE IF NOT EXISTS instant_magic_code_challenges (
            key TEXT PRIMARY KEY NOT NULL,
            email TEXT NOT NULL,
            expires_at_ms INTEGER NOT NULL,
            json TEXT NOT NULL,
            updated_at_ms INTEGER NOT NULL
          )
          """
        )
      }
    }
    try withSQLiteBusyRetry {
      try migrate(name: "0003_plan_aware_query_cache") {
        let entries: [InstantCachedQuery] = try selectJSON(
          "SELECT json FROM instant_query_cache ORDER BY updated_at_ms, query_id"
        )
        try execute("DROP TABLE IF EXISTS instant_query_cache_v2")
        try execute(
          """
          CREATE TABLE instant_query_cache_v2 (
            cache_key TEXT PRIMARY KEY NOT NULL,
            query_id TEXT NOT NULL,
            json TEXT NOT NULL,
            updated_at_ms INTEGER NOT NULL
          )
          """
        )
        for entry in entries {
          try saveQueryCacheEntryWithoutTransaction(entry, tableName: "instant_query_cache_v2")
        }
        try execute("DROP TABLE instant_query_cache")
        try execute("ALTER TABLE instant_query_cache_v2 RENAME TO instant_query_cache")
        try execute(
          """
          CREATE INDEX IF NOT EXISTS instant_query_cache_query_id_idx
          ON instant_query_cache (query_id)
          """
        )
      }
    }
    try withSQLiteBusyRetry {
      try migrate(name: "0004_room_presence_and_topics") {
        try execute(
          """
          CREATE TABLE IF NOT EXISTS instant_room_presence (
            app_id TEXT NOT NULL,
            room_type TEXT NOT NULL,
            room_id TEXT NOT NULL,
            user_id TEXT NOT NULL,
            json TEXT NOT NULL,
            updated_at_ms INTEGER NOT NULL,
            PRIMARY KEY (app_id, room_type, room_id, user_id)
          )
          """
        )
        try execute(
          """
          CREATE TABLE IF NOT EXISTS instant_room_topic_messages (
            message_id TEXT NOT NULL,
            app_id TEXT NOT NULL,
            room_type TEXT NOT NULL,
            room_id TEXT NOT NULL,
            topic TEXT NOT NULL,
            created_at_ms INTEGER NOT NULL,
            json TEXT NOT NULL,
            PRIMARY KEY (app_id, message_id)
          )
          """
        )
        try execute(
          """
          CREATE INDEX IF NOT EXISTS instant_room_topic_messages_room_idx
          ON instant_room_topic_messages (app_id, room_type, room_id, topic, created_at_ms, message_id)
          """
        )
      }
    }
    try withSQLiteBusyRetry {
      try migrate(name: "0005_app_scoped_room_topic_messages") {
        let messages: [InstantRoomTopicMessage] = try selectJSON(
          "SELECT json FROM instant_room_topic_messages ORDER BY created_at_ms, message_id"
        )
        try execute("DROP TABLE IF EXISTS instant_room_topic_messages_v2")
        try execute(
          """
          CREATE TABLE instant_room_topic_messages_v2 (
            message_id TEXT NOT NULL,
            app_id TEXT NOT NULL,
            room_type TEXT NOT NULL,
            room_id TEXT NOT NULL,
            topic TEXT NOT NULL,
            created_at_ms INTEGER NOT NULL,
            json TEXT NOT NULL,
            PRIMARY KEY (app_id, message_id)
          )
          """
        )
        for message in messages {
          try saveRoomTopicMessageWithoutTransaction(
            message,
            tableName: "instant_room_topic_messages_v2"
          )
        }
        try execute("DROP TABLE instant_room_topic_messages")
        try execute(
          "ALTER TABLE instant_room_topic_messages_v2 RENAME TO instant_room_topic_messages")
        try execute(
          """
          CREATE INDEX IF NOT EXISTS instant_room_topic_messages_room_idx
          ON instant_room_topic_messages (app_id, room_type, room_id, topic, created_at_ms, message_id)
          """
        )
      }
    }
    try withSQLiteBusyRetry {
      try migrate(name: "0006_local_files") {
        try execute(
          """
          CREATE TABLE IF NOT EXISTS instant_files (
            app_id TEXT NOT NULL,
            file_id TEXT NOT NULL,
            name TEXT NOT NULL,
            created_at_ms INTEGER NOT NULL,
            updated_at_ms INTEGER NOT NULL,
            json TEXT NOT NULL,
            PRIMARY KEY (app_id, file_id)
          )
          """
        )
        try execute(
          """
          CREATE INDEX IF NOT EXISTS instant_files_app_idx
          ON instant_files (app_id, created_at_ms, file_id)
          """
        )
      }
    }
    try withSQLiteBusyRetry {
      try migrate(name: "0007_local_stream_chunks") {
        try execute(
          """
          CREATE TABLE IF NOT EXISTS instant_stream_chunks (
            app_id TEXT NOT NULL,
            stream_id TEXT NOT NULL,
            chunk_id TEXT NOT NULL,
            chunk_index INTEGER NOT NULL,
            created_at_ms INTEGER NOT NULL,
            json TEXT NOT NULL,
            PRIMARY KEY (app_id, stream_id, chunk_id)
          )
          """
        )
        try execute(
          """
          CREATE INDEX IF NOT EXISTS instant_stream_chunks_stream_idx
          ON instant_stream_chunks (app_id, stream_id, chunk_index, chunk_id)
          """
        )
      }
    }
    try withSQLiteBusyRetry {
      try migrate(name: "0008_local_shares") {
        try execute(
          """
          CREATE TABLE IF NOT EXISTS instant_shares (
            app_id TEXT NOT NULL,
            share_id TEXT NOT NULL,
            root_namespace TEXT NOT NULL,
            root_id TEXT NOT NULL,
            owner_user_id TEXT NOT NULL,
            token TEXT NOT NULL,
            created_at_ms INTEGER NOT NULL,
            updated_at_ms INTEGER NOT NULL,
            revoked_at_ms INTEGER,
            json TEXT NOT NULL,
            PRIMARY KEY (app_id, share_id)
          )
          """
        )
        try execute(
          """
          CREATE UNIQUE INDEX IF NOT EXISTS instant_shares_token_idx
          ON instant_shares (app_id, token)
          """
        )
        try execute(
          """
          CREATE INDEX IF NOT EXISTS instant_shares_owner_idx
          ON instant_shares (app_id, owner_user_id, created_at_ms, share_id)
          """
        )
        try execute(
          """
          CREATE INDEX IF NOT EXISTS instant_shares_root_idx
          ON instant_shares (app_id, root_id, root_namespace, revoked_at_ms, created_at_ms, share_id)
          """
        )
        try execute(
          """
          CREATE TABLE IF NOT EXISTS instant_share_memberships (
            app_id TEXT NOT NULL,
            share_id TEXT NOT NULL,
            user_id TEXT NOT NULL,
            role TEXT NOT NULL,
            accepted_at_ms INTEGER NOT NULL,
            revoked_at_ms INTEGER,
            json TEXT NOT NULL,
            PRIMARY KEY (app_id, share_id, user_id)
          )
          """
        )
        try execute(
          """
          CREATE INDEX IF NOT EXISTS instant_share_memberships_user_idx
          ON instant_share_memberships (app_id, user_id, revoked_at_ms, accepted_at_ms, share_id)
          """
        )
      }
    }
    try withSQLiteBusyRetry {
      try migrate(name: "0009_local_share_root_index") {
        try execute(
          """
          CREATE INDEX IF NOT EXISTS instant_shares_root_idx
          ON instant_shares (app_id, root_id, root_namespace, revoked_at_ms, created_at_ms, share_id)
          """
        )
      }
    }
    try withSQLiteBusyRetry {
      try migrate(name: "0010_local_byte_streams") {
        try execute(
          """
          CREATE TABLE IF NOT EXISTS instant_streams (
            app_id TEXT NOT NULL,
            stream_id TEXT NOT NULL,
            client_id TEXT NOT NULL,
            user_id TEXT NOT NULL,
            done INTEGER NOT NULL,
            size INTEGER,
            abort_reason TEXT,
            created_at_ms INTEGER NOT NULL,
            updated_at_ms INTEGER NOT NULL,
            json TEXT NOT NULL,
            PRIMARY KEY (app_id, stream_id),
            UNIQUE (app_id, client_id)
          )
          """
        )
        try execute(
          """
          CREATE INDEX IF NOT EXISTS instant_streams_client_idx
          ON instant_streams (app_id, client_id)
          """
        )
        try execute(
          """
          CREATE TABLE IF NOT EXISTS instant_stream_content_chunks (
            app_id TEXT NOT NULL,
            stream_id TEXT NOT NULL,
            chunk_id TEXT NOT NULL,
            offset INTEGER NOT NULL,
            byte_count INTEGER NOT NULL,
            created_at_ms INTEGER NOT NULL,
            json TEXT NOT NULL,
            PRIMARY KEY (app_id, stream_id, chunk_id),
            FOREIGN KEY (app_id, stream_id) REFERENCES instant_streams (app_id, stream_id)
              ON DELETE CASCADE
          )
          """
        )
        try execute(
          """
          CREATE INDEX IF NOT EXISTS instant_stream_content_chunks_stream_idx
          ON instant_stream_content_chunks (app_id, stream_id, offset, chunk_id)
          """
        )
      }
    }
    try withSQLiteBusyRetry {
      try migrate(name: "0011_live_query_result_ownership") {
        try execute(
          """
          CREATE TABLE IF NOT EXISTS instant_live_query_results (
            query_key TEXT PRIMARY KEY NOT NULL,
            triple_count INTEGER NOT NULL,
            updated_at_ms INTEGER NOT NULL,
            json TEXT NOT NULL
          )
          """
        )
        try execute(
          """
          CREATE TABLE IF NOT EXISTS instant_live_query_triples (
            query_key TEXT NOT NULL,
            entity_id TEXT NOT NULL,
            attribute_id TEXT NOT NULL,
            value_json TEXT NOT NULL,
            PRIMARY KEY (query_key, entity_id, attribute_id, value_json),
            FOREIGN KEY (query_key) REFERENCES instant_live_query_results (query_key)
              ON DELETE CASCADE
          )
          """
        )
        try execute(
          """
          CREATE INDEX IF NOT EXISTS instant_live_query_triples_identity_idx
          ON instant_live_query_triples (entity_id, attribute_id, value_json, query_key)
          """
        )
      }
    }
    try withSQLiteBusyRetry {
      try migrate(name: "0012_bounded_outbox_delivery") {
        try execute("ALTER TABLE instant_outbox ADD COLUMN delivery_state TEXT")
        try execute(
          "ALTER TABLE instant_outbox ADD COLUMN delivery_metadata_version INTEGER NOT NULL DEFAULT 0"
        )
        try execute("ALTER TABLE instant_outbox ADD COLUMN transport_step_count INTEGER")
        try execute("ALTER TABLE instant_outbox ADD COLUMN lifecycle_json TEXT")
        try execute("ALTER TABLE instant_outbox ADD COLUMN quarantine_json TEXT")
        try execute("ALTER TABLE instant_outbox ADD COLUMN quarantine_lifecycle_json TEXT")
        try execute("ALTER TABLE instant_outbox ADD COLUMN encoded_body_bytes INTEGER")
        try execute("ALTER TABLE instant_outbox ADD COLUMN failure_message TEXT")
        try execute("ALTER TABLE instant_outbox ADD COLUMN confirmation_proven INTEGER")
        try execute(
          "ALTER TABLE instant_outbox ADD COLUMN optimistic_overlay_active INTEGER NOT NULL DEFAULT 1"
        )
        // Existing rows predate durable offer tracking and must be treated as
        // already offered. Only rows inserted by this version start false.
        try execute(
          "ALTER TABLE instant_outbox ADD COLUMN delivery_started INTEGER NOT NULL DEFAULT 1"
        )
        try execute(
          "ALTER TABLE instant_outbox ADD COLUMN delivery_claim_state TEXT NOT NULL DEFAULT 'ready'"
        )
        try execute("ALTER TABLE instant_outbox ADD COLUMN delivery_claim_token TEXT")
        try execute("ALTER TABLE instant_outbox ADD COLUMN delivery_claimant_id TEXT")
        try execute("ALTER TABLE instant_outbox ADD COLUMN delivery_claim_deadline_ms INTEGER")
        try execute(
          """
          CREATE TABLE IF NOT EXISTS instant_outbox_write_keys (
            mutation_id TEXT NOT NULL,
            entity_id TEXT NOT NULL,
            attribute_id TEXT NOT NULL,
            PRIMARY KEY (mutation_id, entity_id, attribute_id),
            FOREIGN KEY (mutation_id) REFERENCES instant_outbox (mutation_id)
              ON DELETE CASCADE
          )
          """
        )
        try execute(
          """
          CREATE INDEX IF NOT EXISTS instant_outbox_delivery_window_idx
          ON instant_outbox
            (delivery_claim_state, delivery_state, created_at_ms, mutation_id)
          """
        )
        try execute(
          """
          CREATE INDEX IF NOT EXISTS instant_outbox_delivery_deadline_idx
          ON instant_outbox
            (delivery_claim_state, delivery_claim_deadline_ms, created_at_ms, mutation_id)
          """
        )
        try execute(
          """
          CREATE INDEX IF NOT EXISTS instant_outbox_delivery_metadata_idx
          ON instant_outbox
            (status, delivery_metadata_version, created_at_ms, mutation_id)
          """
        )
        try execute(
          """
          CREATE INDEX IF NOT EXISTS instant_outbox_write_keys_lookup_idx
          ON instant_outbox_write_keys (entity_id, attribute_id, mutation_id)
          """
        )
      }
    }
    try withSQLiteBusyRetry {
      try migrate(name: "0013_outbox_supersession_lifecycle") {
        // A lifecycle id is stable while the physical durable tail row is
        // replaced repeatedly. Aliases are append-only and let every returned
        // transaction id observe the one survivor after restart and pruning.
        try execute(
          """
          CREATE TABLE IF NOT EXISTS instant_outbox_lifecycles (
            lifecycle_id TEXT PRIMARY KEY NOT NULL,
            current_mutation_id TEXT NOT NULL,
            terminal_json TEXT
          )
          """
        )
        try execute(
          """
          CREATE TABLE IF NOT EXISTS instant_outbox_lifecycle_aliases (
            mutation_id TEXT PRIMARY KEY NOT NULL,
            lifecycle_id TEXT NOT NULL,
            FOREIGN KEY (lifecycle_id) REFERENCES instant_outbox_lifecycles (lifecycle_id)
              ON DELETE CASCADE
          )
          """
        )
        try execute(
          """
          CREATE INDEX IF NOT EXISTS instant_outbox_lifecycle_current_idx
          ON instant_outbox_lifecycles (current_mutation_id)
          """
        )
      }
    }
    try withSQLiteBusyRetry {
      try migrate(name: "0014_outbox_optimistic_effects") {
        try execute(
          "ALTER TABLE instant_outbox ADD COLUMN mutation_revision INTEGER NOT NULL DEFAULT 0"
        )
        try execute(
          "ALTER TABLE instant_outbox ADD COLUMN optimistic_effect_metadata_version INTEGER NOT NULL DEFAULT 0"
        )
        try execute(
          "ALTER TABLE instant_outbox ADD COLUMN optimistic_effect_is_global INTEGER NOT NULL DEFAULT 0"
        )
        try execute(
          """
          CREATE TABLE IF NOT EXISTS instant_outbox_effect_entities (
            mutation_id TEXT NOT NULL,
            entity_id TEXT NOT NULL,
            PRIMARY KEY (mutation_id, entity_id),
            FOREIGN KEY (mutation_id) REFERENCES instant_outbox (mutation_id)
              ON DELETE CASCADE
          )
          """
        )
        try execute(
          """
          CREATE INDEX IF NOT EXISTS instant_outbox_effect_entities_lookup_idx
          ON instant_outbox_effect_entities (entity_id, mutation_id)
          """
        )
        try execute(
          """
          CREATE INDEX IF NOT EXISTS instant_outbox_effect_normalization_idx
          ON instant_outbox (
            optimistic_overlay_active,
            optimistic_effect_metadata_version,
            created_at_ms,
            mutation_id
          )
          """
        )
        try execute(
          """
          CREATE INDEX IF NOT EXISTS instant_outbox_global_effect_order_idx
          ON instant_outbox (
            optimistic_overlay_active,
            optimistic_effect_is_global,
            created_at_ms,
            mutation_id
          )
          """
        )
      }
    }
    try withSQLiteBusyRetry {
      try migrate(name: "0015_outbox_effect_entity_order") {
        try execute(
          "ALTER TABLE instant_outbox_effect_entities ADD COLUMN created_at_ms INTEGER NOT NULL DEFAULT 0"
        )
        try execute(
          """
          UPDATE instant_outbox_effect_entities
          SET created_at_ms = COALESCE(
            (
              SELECT outbox.created_at_ms
              FROM instant_outbox AS outbox
              WHERE outbox.mutation_id = instant_outbox_effect_entities.mutation_id
            ),
            0
          )
          """
        )
        try execute("DROP INDEX IF EXISTS instant_outbox_effect_entities_lookup_idx")
        try execute(
          """
          CREATE INDEX instant_outbox_effect_entities_lookup_idx
          ON instant_outbox_effect_entities (entity_id, created_at_ms, mutation_id)
          """
        )
      }
    }
    try withSQLiteBusyRetry {
      try migrate(name: "0016_failed_mutation_retry_window") {
        try execute(
          """
          CREATE INDEX instant_outbox_failed_retry_window_idx
          ON instant_outbox (
            created_at_ms,
            mutation_id,
            mutation_revision,
            delivery_state,
            encoded_body_bytes
          )
          WHERE \(Self.automaticFailedMutationRetryEligibilitySQL)
          """
        )
      }
    }
    try withSQLiteBusyRetry {
      try migrate(name: "0017_bounded_server_apply") {
        try execute("ALTER TABLE instant_outbox ADD COLUMN server_transaction_id TEXT")
        try execute("ALTER TABLE instant_outbox ADD COLUMN confirmation_source TEXT")
        // JSON1 is already required by the row-addressed lifecycle writers in
        // this store. Backfill only the two compact control scalars; server
        // apply never needs to parse a durable mutation body to find a
        // watermark-pruned or server-proven row.
        try execute(
          """
          UPDATE instant_outbox
          SET server_transaction_id = CASE
                WHEN length(CAST(json AS BLOB)) <=
                  \(InstantAutomaticOutboxClaimLimits.maximumEncodedBodyBytes)
                THEN CASE WHEN json_valid(json)
                  THEN json_extract(json, '$.serverTransactionID') END
              END,
              confirmation_source = CASE
                WHEN length(CAST(json AS BLOB)) <=
                  \(InstantAutomaticOutboxClaimLimits.maximumEncodedBodyBytes)
                THEN CASE WHEN json_valid(json)
                  THEN json_extract(json, '$.confirmationSource') END
              END
          """
        )
        try execute(
          """
          CREATE INDEX instant_outbox_server_apply_watermark_idx
          ON instant_outbox (
            status, confirmation_proven, server_transaction_id,
            optimistic_overlay_active, created_at_ms, mutation_id
          )
          """
        )
        try execute(
          """
          CREATE INDEX instant_outbox_server_apply_failed_idx
          ON instant_outbox (status, optimistic_overlay_active, created_at_ms, mutation_id)
          WHERE status = 'failed' AND optimistic_overlay_active = 1
          """
        )
      }
    }
    try withSQLiteBusyRetry {
      try migrate(name: "0018_schema_failure_attribute_revision") {
        // Upstream Reactor removes a pending mutation when a non-timeout
        // mutation error is handled. Swift can discover missing server schema
        // while encoding its durable optimistic row, so remember the attribute
        // revision that could not encode it and retry only after durable schema
        // knowledge changes. A nullable scalar keeps pre-migration rows
        // eligible once.
        try execute(
          "ALTER TABLE instant_outbox ADD COLUMN failure_attribute_revision INTEGER"
        )
      }
    }
    try withSQLiteBusyRetry {
      try migrate(name: "0019_projected_outbox_claim_bytes") {
        // A filtered required scalar can be much larger than the durable body
        // that was admitted before projection. Keep the exact active-claim
        // reservation separate from the immutable durable-body byte count.
        try execute(
          "ALTER TABLE instant_outbox ADD COLUMN delivery_claim_projected_body_bytes INTEGER"
        )
      }
    }
    try withSQLiteBusyRetry {
      try migrate(name: "0020_outbox_optimistic_effect_receipt_fingerprint") {
        // The public PendingMutation body is Codable and caller-controlled.
        // Keep Runtime preparation provenance outside that body and leave
        // ambiguous historical rows nil so every unproven receipt fails closed.
        // The bounded one-time compatibility backfill below grandfathers only
        // the exact applied/rollback and no-current-effect shapes deployed
        // Runtime versions already trusted before this external marker existed.
        try execute(
          "ALTER TABLE instant_outbox ADD COLUMN optimistic_effect_receipt_fingerprint TEXT"
        )
        // The materialized-effect receipt above is intentionally independent
        // from the forward payload offered to the server. A Runtime rebase may
        // regenerate rollback data without changing the wire intent, while a
        // public forward-body edit must never inherit an in-flight ACK.
        try execute(
          "ALTER TABLE instant_outbox ADD COLUMN delivery_claim_payload_fingerprint TEXT"
        )
        try execute(
          "ALTER TABLE instant_outbox ADD COLUMN server_acceptance_payload_fingerprint TEXT"
        )
        try backfillPreexistingRuntimePreparedReceiptFingerprintsWithoutTransaction()
      }
    }
    try withSQLiteBusyRetry {
      try migrate(name: "0021_outbox_lifecycle_receipt_authority") {
        // Terminal lifecycle JSON is a bounded projection, not authority. Keep
        // separate SQLite-owned markers so a pre-0021 or caller-shaped body
        // cannot report server acceptance or a trusted rollback after its
        // physical outbox row has been pruned.
        try execute(
          "ALTER TABLE instant_outbox_lifecycles ADD COLUMN terminal_optimistic_effect_receipt_fingerprint TEXT"
        )
        try execute(
          "ALTER TABLE instant_outbox_lifecycles ADD COLUMN terminal_server_acceptance_payload_fingerprint TEXT"
        )
      }
    }
    try withSQLiteBusyRetry {
      try migrate(name: "0022_outbox_synchronization_blocker_index") {
        try execute(
          """
          CREATE INDEX instant_outbox_synchronization_blocker_idx
          ON instant_outbox (
            optimistic_overlay_active,
            optimistic_effect_receipt_fingerprint,
            created_at_ms,
            mutation_id
          )
          """
        )
      }
    }
    try withSQLiteBusyRetry {
      try migrate(name: "0023_application_persistence_migrations") {
        try execute(
          """
          CREATE TABLE instant_application_persistence_migrations (
            name TEXT PRIMARY KEY NOT NULL,
            applied_at_ms INTEGER NOT NULL
          )
          """
        )
      }
    }
    // Test fixtures and app-owned restores can reconstruct `instant_outbox`
    // while retaining newer migration ledger rows. Reassert this column-free
    // index so the body-free blocker query never falls back to a scan/sort.
    try execute(
      """
      CREATE INDEX IF NOT EXISTS instant_outbox_synchronization_blocker_idx
      ON instant_outbox (
        optimistic_overlay_active,
        optimistic_effect_receipt_fingerprint,
        created_at_ms,
        mutation_id
      )
      """
    )
    try ensureServerApplyStagingSchema()
    try Self.securePersistenceFiles(at: fileURL)
    InstantDiagnostics.shared.record(
      .notice,
      subsystem: "instant-swift-data-core",
      category: "persistence",
      event: "sqlite.bootstrap-completed",
      message: "Instant SQLite schema is ready.",
      metadata: ["path": fileURL.path]
    )
  }

  package func bootstrap(
    queryCachePruningPolicy: InstantQueryCachePruningPolicy,
    now: InstantTimestamp
  ) throws -> InstantQueryCachePruningResult? {
    try bootstrap()
    try reconcileDeclaredRelationStorageIfNeeded()
    do {
      return try pruneQueryCache(policy: queryCachePruningPolicy, now: now)
    } catch {
      InstantDiagnostics.shared.record(
        error: error,
        subsystem: "instant-swift-data-core",
        category: "query",
        event: "query-cache.bootstrap-prune-failed",
        message: "Could not prune persisted query results during runtime bootstrap."
      )
      return nil
    }
  }

  /// Reconciles reciprocal application declarations with the server's durable physical link.
  ///
  /// Runtime bootstrap normally hydrates only live-query and outbox-owned entities. Performing
  /// this transition in SQLite before that compact load keeps cold triples queryable after the
  /// duplicate attribute metadata is removed. The original outbox remains the caller's logical
  /// intent; only materialized storage and persisted query ownership use the canonical direction.
  private func reconcileDeclaredRelationStorageIfNeeded() throws {
    guard !declaredAttributes.isEmpty else { return }
    let didChange = try transaction {
      let durableAttributes = try loadAttributesWithoutTransaction(
        tracesStartupCollection: false
      )
      guard
        let reconciliation = AttributeStore.relationStorageReconciliation(
          durableAttributes: durableAttributes,
          declaredAttributes: declaredAttributes
        )
      else { return false }

      let marker = try encode(
        DeclaredRelationStorageReconciliationMarker(
          retainedAttributes: reconciliation.markerAttributes,
          declaredAttributes: reconciliation.declaredRelationAttributes,
          obsoleteAttributeIDs: reconciliation.obsoleteAttributeIDs.sorted()
        )
      )
      let installedMarkerJSON: String? = try selectScalar(
        "SELECT value FROM instant_sync_metadata WHERE key = ? LIMIT 1",
        [.text(Self.declaredRelationStorageReconciliationMarkerKey)]
      )
      installedDeclaredRelationStorageMarker = try installedMarkerJSON.map {
        try decoder.decode(
          DeclaredRelationStorageReconciliationMarker.self,
          from: Data($0.utf8)
        )
      }
      installedDeclaredRelationStorageObsoleteAttributeIDs = Set(
        installedDeclaredRelationStorageMarker?.obsoleteAttributeIDs ?? []
      )
      didLoadDeclaredRelationStorageMarker = true
      guard installedMarkerJSON != marker else { return false }

      let obsoleteAttributeIDs = reconciliation.obsoleteAttributeIDs
      var triplesChanged = false
      var tripleRowID: Int64 = 0
      while let row = try nextApplicationMigrationTripleRowWithoutTransaction(
        after: tripleRowID,
        affectedAttributeIDs: obsoleteAttributeIDs
      ) {
        tripleRowID = row.rowID
        let canonical = reconciliation.canonicalized(row.triple)
        guard !obsoleteAttributeIDs.contains(canonical.attributeID) else {
          throw persistenceError(
            operation: "reconcile declared relation storage",
            message:
              "Relation triple '\(row.triple.entityID)/\(row.triple.attributeID)' did not resolve to the retained physical attribute."
          )
        }
        try upsertCanonicalRelationTripleWithoutTransaction(canonical)
        try execute("DELETE FROM instant_triples WHERE rowid = ?", [.int(row.rowID)])
        guard sqlite3_changes(connection.raw) == 1 else {
          throw persistenceError(
            operation: "reconcile declared relation storage",
            message: "An obsolete relation triple disappeared before it could be removed."
          )
        }
        triplesChanged = true
      }

      var liveQueryResultsChanged = false
      var liveQueryCursor: String?
      while let result = try nextDeclaredRelationLiveQueryResultWithoutTransaction(
        after: liveQueryCursor
      ) {
        liveQueryCursor = result.key
        var canonicalByIdentity: [InstantLiveTripleIdentity: InstantTriple] = [:]
        canonicalByIdentity.reserveCapacity(result.triples.count)
        for triple in result.triples {
          let canonical = obsoleteAttributeIDs.contains(triple.attributeID)
            ? reconciliation.canonicalized(triple)
            : triple
          guard !obsoleteAttributeIDs.contains(canonical.attributeID) else {
            throw persistenceError(
              operation: "reconcile declared relation storage",
              message:
                "Live-query relation triple '\(triple.entityID)/\(triple.attributeID)' did not resolve to the retained physical attribute."
            )
          }
          let identity = InstantLiveTripleIdentity(canonical)
          if let existing = canonicalByIdentity[identity] {
            if Self.relationTripleStampPrecedes(existing, canonical) {
              canonicalByIdentity[identity] = canonical
            }
          } else {
            canonicalByIdentity[identity] = canonical
          }
        }
        var canonicalResult = result
        canonicalResult.triples = canonicalByIdentity.values.sorted(by: Self.relationTriplePrecedes)
        let expectedOwnership = try Set(
          canonicalResult.triples.map { triple in
            LiveQueryOwnershipIdentity(
              entityID: triple.entityID,
              attributeID: triple.attributeID,
              valueJSON: try encode(triple.value)
            )
          }
        )
        let currentOwnership = try liveQueryOwnershipWithoutTransaction(queryKey: result.key)
        guard canonicalResult != result || expectedOwnership != currentOwnership else { continue }
        try replaceReconciledLiveQueryResultWithoutTransaction(
          canonicalResult,
          ownership: expectedOwnership
        )
        liveQueryResultsChanged = true
      }

      let reconciledAttributes = reconciliation.attributes
      let attributesChanged = reconciledAttributes != durableAttributes.sorted { $0.id < $1.id }
      if attributesChanged {
        let durableByID = Dictionary(uniqueKeysWithValues: durableAttributes.map { ($0.id, $0) })
        let reconciledByID = Dictionary(
          uniqueKeysWithValues: reconciledAttributes.map { ($0.id, $0) }
        )
        // Install retained metadata before deleting obsolete rows. All triple and live-query rows
        // have already moved, so no durable fact can be orphaned by the following deletes.
        for attribute in reconciledAttributes where durableByID[attribute.id] != attribute {
          try execute(
            "INSERT OR REPLACE INTO instant_attributes (id, json) VALUES (?, ?)",
            [.text(attribute.id), .text(try encode(attribute))]
          )
        }
        for attributeID in durableByID.keys.sorted() where reconciledByID[attributeID] == nil {
          try execute("DELETE FROM instant_attributes WHERE id = ?", [.text(attributeID)])
        }
      }

      let didChange = attributesChanged || triplesChanged || liveQueryResultsChanged
      if didChange {
        try execute("DELETE FROM instant_query_cache")
      }
      if triplesChanged || liveQueryResultsChanged {
        _ = try bumpMetadataRevisionWithoutTransaction(Self.storeRevisionKey)
      }
      if attributesChanged {
        _ = try bumpMetadataRevisionWithoutTransaction(Self.attributeRevisionKey)
      }
      if liveQueryResultsChanged {
        _ = try bumpMetadataRevisionWithoutTransaction(Self.queryResultRevisionKey)
      }
      try saveMetadataValueWithoutTransaction(
        marker,
        key: Self.declaredRelationStorageReconciliationMarkerKey,
        updatedAt: InstantTimestamp(milliseconds: Self.nowMilliseconds())
      )
      installedDeclaredRelationStorageMarker = DeclaredRelationStorageReconciliationMarker(
        retainedAttributes: reconciliation.markerAttributes,
        declaredAttributes: reconciliation.declaredRelationAttributes,
        obsoleteAttributeIDs: reconciliation.obsoleteAttributeIDs.sorted()
      )
      installedDeclaredRelationStorageObsoleteAttributeIDs = reconciliation.obsoleteAttributeIDs
      didLoadDeclaredRelationStorageMarker = true
      return didChange
    }
    guard didChange else { return }
    cachedState = nil
    cachedMaterializedStore = nil
  }

  /// Reads every persisted result through a one-row keyset cursor.
  ///
  /// Ownership is an index of the encoded result, but an interrupted older build or imported
  /// fixture can drift on either side. Scanning all bounded result bodies lets reconciliation heal
  /// both an obsolete triple that exists only in JSON and obsolete ownership whose JSON is already
  /// canonical.
  private func nextDeclaredRelationLiveQueryResultWithoutTransaction(
    after queryKey: String?
  ) throws -> InstantPersistedLiveQueryResult? {
    var statement: OpaquePointer?
    let sql: String
    let bindings: [SQLiteBinding]
    if let queryKey {
      sql =
        "SELECT query_key, length(CAST(json AS BLOB)) FROM instant_live_query_results WHERE query_key > ? ORDER BY query_key LIMIT 1"
      bindings = [.text(queryKey)]
    } else {
      sql =
        "SELECT query_key, length(CAST(json AS BLOB)) FROM instant_live_query_results ORDER BY query_key LIMIT 1"
      bindings = []
    }
    try prepare(sql, statement: &statement)
    defer { sqlite3_finalize(statement) }
    try bind(bindings, to: statement)
    let code = sqlite3_step(statement)
    if code == SQLITE_DONE { return nil }
    guard code == SQLITE_ROW,
      let queryKeyBytes = sqlite3_column_text(statement, 0)
    else {
      throw persistenceError(
        operation: "read declared relation live-query result",
        message: lastErrorMessage()
      )
    }
    let rowQueryKey = String(cString: queryKeyBytes)
    let bodyByteCount = sqlite3_column_int64(statement, 1)
    guard bodyByteCount >= 0,
      bodyByteCount <= Int64(InstantAutomaticOutboxClaimLimits.maximumEncodedBodyBytes)
    else {
      throw persistenceError(
        operation: "read declared relation live-query result",
        message:
          "Live-query result '\(rowQueryKey)' exceeds the bounded reconciliation row limit."
      )
    }
    guard let json: String = try selectScalar(
      "SELECT json FROM instant_live_query_results WHERE query_key = ? LIMIT 1",
      [.text(rowQueryKey)]
    ),
      let data = json.data(using: .utf8)
    else {
      throw persistenceError(
        operation: "read declared relation live-query result",
        message: "Live-query result '\(rowQueryKey)' disappeared before it could be decoded."
      )
    }
    let result = try decoder.decode(InstantPersistedLiveQueryResult.self, from: data)
    guard result.key == rowQueryKey else {
      throw persistenceError(
        operation: "read declared relation live-query result",
        message: "The decoded live-query result did not match its SQLite identity."
      )
    }
    declaredRelationReconciliationLiveResultScanCount += 1
    return result
  }

  private func upsertCanonicalRelationTripleWithoutTransaction(
    _ triple: InstantTriple
  ) throws {
    try execute(
      """
      INSERT INTO instant_triples
        (entity_id, attribute_id, value_json, tx_id, tx_time_ms, json)
      VALUES (?, ?, ?, ?, ?, ?)
      ON CONFLICT(entity_id, attribute_id, value_json) DO UPDATE SET
        tx_id = excluded.tx_id,
        tx_time_ms = excluded.tx_time_ms,
        json = excluded.json
      WHERE excluded.tx_time_ms > instant_triples.tx_time_ms
         OR (
           excluded.tx_time_ms = instant_triples.tx_time_ms
           AND excluded.tx_id > instant_triples.tx_id
         )
      """,
      [
        .text(triple.entityID),
        .text(triple.attributeID),
        .text(try encode(triple.value)),
        .text(triple.txID),
        .int(triple.txTime.milliseconds),
        .text(try encode(triple)),
      ]
    )
  }

  private func replaceReconciledLiveQueryResultWithoutTransaction(
    _ result: InstantPersistedLiveQueryResult,
    ownership: Set<LiveQueryOwnershipIdentity>
  ) throws {
    try execute(
      """
      UPDATE instant_live_query_results
      SET triple_count = ?, json = ?
      WHERE query_key = ?
      """,
      [
        .int(Int64(result.triples.count)),
        .text(try encode(result)),
        .text(result.key),
      ]
    )
    guard sqlite3_changes(connection.raw) == 1 else {
      throw persistenceError(
        operation: "reconcile declared relation storage",
        message: "Persisted live-query result '\(result.key)' disappeared during reconciliation."
      )
    }
    try execute(
      "DELETE FROM instant_live_query_triples WHERE query_key = ?",
      [.text(result.key)]
    )
    try executeRepeated(
      """
      INSERT INTO instant_live_query_triples
        (query_key, entity_id, attribute_id, value_json)
      VALUES (?, ?, ?, ?)
      """,
      bindings: ownership.sorted(by: Self.liveQueryOwnershipOrder).map { identity in
        [
          .text(result.key),
          .text(identity.entityID),
          .text(identity.attributeID),
          .text(identity.valueJSON),
        ]
      }
    )
  }

  private static func relationTripleStampPrecedes(
    _ lhs: InstantTriple,
    _ rhs: InstantTriple
  ) -> Bool {
    if lhs.txTime != rhs.txTime { return lhs.txTime < rhs.txTime }
    return lhs.txID < rhs.txID
  }

  private static func relationTriplePrecedes(_ lhs: InstantTriple, _ rhs: InstantTriple) -> Bool {
    if lhs.entityID != rhs.entityID { return lhs.entityID < rhs.entityID }
    if lhs.attributeID != rhs.attributeID { return lhs.attributeID < rhs.attributeID }
    return lhs.value.comparableKey < rhs.value.comparableKey
  }

  private func declaredRelationStorageMarkerWithoutTransaction() throws
    -> DeclaredRelationStorageReconciliationMarker?
  {
    if didLoadDeclaredRelationStorageMarker {
      return installedDeclaredRelationStorageMarker
    }
    let markerJSON: String? = try selectScalar(
      "SELECT value FROM instant_sync_metadata WHERE key = ? LIMIT 1",
      [.text(Self.declaredRelationStorageReconciliationMarkerKey)]
    )
    installedDeclaredRelationStorageMarker = try markerJSON.map {
      try decoder.decode(
        DeclaredRelationStorageReconciliationMarker.self,
        from: Data($0.utf8)
      )
    }
    installedDeclaredRelationStorageObsoleteAttributeIDs = Set(
      installedDeclaredRelationStorageMarker?.obsoleteAttributeIDs ?? []
    )
    didLoadDeclaredRelationStorageMarker = true
    return installedDeclaredRelationStorageMarker
  }

  private func invalidateDeclaredRelationStorageMarkerWithoutTransaction() throws {
    try deleteMetadataValueWithoutTransaction(
      key: Self.declaredRelationStorageReconciliationMarkerKey
    )
    installedDeclaredRelationStorageMarker = nil
    installedDeclaredRelationStorageObsoleteAttributeIDs = []
    didLoadDeclaredRelationStorageMarker = true
  }

  private func invalidateDeclaredRelationStorageMarkerIfNeeded(
    forAttributeIDs attributeIDs: Set<String>
  ) throws {
    guard !attributeIDs.isEmpty,
      try declaredRelationStorageMarkerWithoutTransaction() != nil,
      !installedDeclaredRelationStorageObsoleteAttributeIDs.isDisjoint(with: attributeIDs)
    else { return }
    try invalidateDeclaredRelationStorageMarkerWithoutTransaction()
  }

  private func invalidateDeclaredRelationStorageMarkerIfNeeded(
    forIncomingAttributes attributes: [InstantAttribute]
  ) throws {
    guard !attributes.isEmpty,
      let marker = try declaredRelationStorageMarkerWithoutTransaction()
    else { return }
    let obsoleteAttributeIDs = installedDeclaredRelationStorageObsoleteAttributeIDs
    let logicalIdentities = Set(
      marker.declaredAttributes.flatMap { attribute in
        [attribute.forwardIdentity, attribute.reverseIdentity].compactMap { $0 }
      }
    )
    let retainedAttributes = Set(marker.retainedAttributes)
    let invalidatesMarker = attributes.contains { attribute in
      if obsoleteAttributeIDs.contains(attribute.id) { return true }
      guard attribute.valueType == .ref,
        let forwardIdentity = attribute.forwardIdentity,
        let reverseIdentity = attribute.reverseIdentity,
        logicalIdentities.contains(forwardIdentity) || logicalIdentities.contains(reverseIdentity)
      else { return false }
      return !retainedAttributes.contains(attribute)
    }
    if invalidatesMarker {
      try invalidateDeclaredRelationStorageMarkerWithoutTransaction()
    }
  }

  private func invalidateDeclaredRelationStorageMarkerIfNeeded(
    replacingAttributes attributes: [InstantAttribute]
  ) throws {
    guard let marker = try declaredRelationStorageMarkerWithoutTransaction() else { return }
    let logicalIdentities = Set(
      marker.declaredAttributes.flatMap { attribute in
        [attribute.forwardIdentity, attribute.reverseIdentity].compactMap { $0 }
      }
    )
    let relevantAttributes = attributes.filter { attribute in
      guard attribute.valueType == .ref else { return false }
      return [attribute.forwardIdentity, attribute.reverseIdentity]
        .compactMap { $0 }
        .contains { logicalIdentities.contains($0) }
    }
    guard Set(relevantAttributes) != Set(marker.retainedAttributes)
      || !Set(marker.obsoleteAttributeIDs).isDisjoint(with: Set(attributes.map(\.id)))
    else { return }
    try invalidateDeclaredRelationStorageMarkerWithoutTransaction()
  }

  @discardableResult
  package func applyLocalPersistenceMigration(
    _ migration: InstantLocalPersistenceMigration
  ) throws -> Bool {
    guard !migration.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw persistenceError(
        operation: "apply local persistence migration",
        message: "An application persistence migration must have a nonempty name."
      )
    }
    guard !migration.affectedAttributeIDs.isEmpty,
      migration.affectedAttributeIDs.allSatisfy({
        !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      })
    else {
      throw persistenceError(
        operation: "apply local persistence migration",
        message:
          "Application persistence migration '\(migration.name)' must declare at least one nonempty affected attribute id."
      )
    }
    let didChange = try transaction {
      let alreadyApplied: String? = try selectScalar(
        """
        SELECT name FROM instant_application_persistence_migrations
        WHERE name = ?
        LIMIT 1
        """,
        [.text(migration.name)]
      )
      guard alreadyApplied == nil else { return false }

      var outboxCursor: String?
      var firstUnprovenActiveMutationID: String?
      while let row = try nextApplicationMigrationOutboxRowWithoutTransaction(
        after: outboxCursor
      ) {
        outboxCursor = row.mutation.id
        if (row.optimisticOverlayActive
          || row.optimisticEffectReceiptFingerprint != nil),
          !(try applicationMigrationReceiptMatches(row))
        {
          firstUnprovenActiveMutationID = firstUnprovenActiveMutationID ?? row.mutation.id
        }
        let migrated = try migration.transformMutation(row.mutation)
        try validateApplicationMigrationIdentity(
          original: row.mutation,
          migrated: migrated,
          migrationName: migration.name,
          affectedAttributeIDs: migration.affectedAttributeIDs
        )
        guard migrated != row.mutation else { continue }
        try validateApplicationMigrationOutboxBounds(
          migrated,
          migrationName: migration.name
        )
        try validateApplicationMigrationOutboxRewrite(
          row: row,
          migrationName: migration.name
        )
      }

      var attributesChanged = false
      var attributeCursor: String?
      while let attribute = try nextApplicationMigrationAttributeWithoutTransaction(
        after: attributeCursor,
        affectedAttributeIDs: migration.affectedAttributeIDs
      ) {
        attributeCursor = attribute.id
        let migrated = try migration.transformAttribute(attribute)
        guard migrated.id == attribute.id else {
          throw persistenceError(
            operation: "apply local persistence migration",
            message:
              "Application migration '\(migration.name)' changed durable attribute identity '\(attribute.id)'."
          )
        }
        var migratedWithoutValueType = migrated
        migratedWithoutValueType.valueType = attribute.valueType
        guard migratedWithoutValueType == attribute else {
          throw persistenceError(
            operation: "apply local persistence migration",
            message:
              "Application migration '\(migration.name)' changed attribute metadata other than valueType for '\(attribute.id)'."
          )
        }
        guard migrated != attribute else { continue }
        attributesChanged = true
        try execute(
          "UPDATE instant_attributes SET json = ? WHERE id = ?",
          [.text(try encode(migrated)), .text(attribute.id)]
        )
        guard sqlite3_changes(connection.raw) == 1 else {
          throw persistenceError(
            operation: "apply local persistence migration",
            message:
              "Application migration '\(migration.name)' did not update attribute '\(attribute.id)' exactly once."
          )
        }
      }

      var triplesChanged = false
      var tripleRowID: Int64 = 0
      while let row = try nextApplicationMigrationTripleRowWithoutTransaction(
        after: tripleRowID,
        affectedAttributeIDs: migration.affectedAttributeIDs
      ) {
        tripleRowID = row.rowID
        let migrated = try migration.transformTriple(row.triple)
        guard migrated.entityID == row.triple.entityID,
          migrated.attributeID == row.triple.attributeID,
          migrated.txID == row.triple.txID,
          migrated.txTime == row.triple.txTime
        else {
          throw persistenceError(
            operation: "apply local persistence migration",
            message:
              "Application migration '\(migration.name)' changed durable triple identity for entity '\(row.triple.entityID)'."
          )
        }
        guard migrated != row.triple else { continue }
        let encodedMigratedTriple = try encode(migrated)
        guard encodedMigratedTriple.utf8.count
          <= InstantAutomaticOutboxClaimLimits.maximumEncodedBodyBytes
        else {
          throw persistenceError(
            operation: "apply local persistence migration",
            message:
              "Application migration '\(migration.name)' expanded a canonical triple beyond the bounded migration row limit."
          )
        }
        triplesChanged = true
        try execute(
          """
          UPDATE instant_triples
          SET value_json = ?, tx_id = ?, tx_time_ms = ?, json = ?
          WHERE rowid = ?
          """,
          [
            .text(try encode(migrated.value)),
            .text(migrated.txID),
            .int(migrated.txTime.milliseconds),
            .text(encodedMigratedTriple),
            .int(row.rowID),
          ]
        )
        guard sqlite3_changes(connection.raw) == 1 else {
          throw persistenceError(
            operation: "apply local persistence migration",
            message:
              "Application migration '\(migration.name)' did not update one durable triple exactly once."
          )
        }
      }

      var outboxChanged = false
      outboxCursor = nil
      while let row = try nextApplicationMigrationOutboxRowWithoutTransaction(
        after: outboxCursor
      ) {
        outboxCursor = row.mutation.id
        let migrated = try migration.transformMutation(row.mutation)
        try validateApplicationMigrationIdentity(
          original: row.mutation,
          migrated: migrated,
          migrationName: migration.name,
          affectedAttributeIDs: migration.affectedAttributeIDs
        )
        guard migrated != row.mutation else { continue }
        try validateApplicationMigrationOutboxBounds(
          migrated,
          migrationName: migration.name
        )
        try validateApplicationMigrationOutboxRewrite(
          row: row,
          migrationName: migration.name
        )
        outboxChanged = true
        try saveOutboxMutationWithoutTransaction(
          migrated,
          receiptWriteAuthority: .runtimePrepared
        )
      }

      var liveQueryResultsChanged = false
      var liveQueryCursor: String?
      while let result = try nextApplicationMigrationLiveQueryResultWithoutTransaction(
        after: liveQueryCursor,
        affectedAttributeIDs: migration.affectedAttributeIDs
      ) {
        liveQueryCursor = result.key
        var migrated = result
        var transformedTriples: [InstantLiveTripleIdentity: InstantTriple] = [:]
        transformedTriples.reserveCapacity(result.triples.count)
        for triple in result.triples {
          let transformed = migration.affectedAttributeIDs.contains(triple.attributeID)
            ? try migration.transformTriple(triple)
            : triple
          guard transformed.entityID == triple.entityID,
            transformed.attributeID == triple.attributeID,
            transformed.txID == triple.txID,
            transformed.txTime == triple.txTime
          else {
            throw persistenceError(
              operation: "apply local persistence migration",
              message:
                "Application migration '\(migration.name)' changed persisted live-query triple identity for query '\(result.key)'."
            )
          }
          let identity = InstantLiveTripleIdentity(transformed)
          if transformedTriples.updateValue(transformed, forKey: identity) != nil {
            throw persistenceError(
              operation: "apply local persistence migration",
              message:
                "Application migration '\(migration.name)' collapsed two persisted live-query triples for query '\(result.key)' without an explicit collision policy."
            )
          }
        }
        migrated.triples = transformedTriples.values.sorted {
          ($0.entityID, $0.attributeID, $0.value.comparableKey)
            < ($1.entityID, $1.attributeID, $1.value.comparableKey)
        }
        guard migrated != result else { continue }
        let encodedMigratedResult = try encode(migrated)
        guard encodedMigratedResult.utf8.count
          <= InstantAutomaticOutboxClaimLimits.maximumEncodedBodyBytes
        else {
          throw persistenceError(
            operation: "apply local persistence migration",
            message:
              "Application migration '\(migration.name)' expanded live-query result '\(result.key)' beyond the bounded migration row limit."
          )
        }
        liveQueryResultsChanged = true
        try saveLiveQueryResultWithoutTransaction(migrated)
      }

      let didChangeAny =
        attributesChanged || triplesChanged || outboxChanged || liveQueryResultsChanged
      if didChangeAny, let firstUnprovenActiveMutationID {
        throw InstantError(
          code: .persistenceFailed,
          operation: "apply local persistence migration",
          localID: firstUnprovenActiveMutationID,
          message:
            "Application migration '\(migration.name)' cannot change durable state while active mutation '\(firstUnprovenActiveMutationID)' has no matching SQLite optimistic-effect receipt.",
          recovery:
            "Preserve the state and use an app-owned persistence reset or authoritative recovery instead of guessing the mutation's inverse."
        )
      }

      if triplesChanged || attributesChanged || liveQueryResultsChanged {
        try execute("DELETE FROM instant_query_cache")
      }
      if triplesChanged || liveQueryResultsChanged {
        _ = try bumpMetadataRevisionWithoutTransaction(Self.storeRevisionKey)
      }
      if attributesChanged {
        _ = try bumpMetadataRevisionWithoutTransaction(Self.attributeRevisionKey)
      }
      if outboxChanged {
        _ = try bumpMetadataRevisionWithoutTransaction(Self.outboxRevisionKey)
      }
      if liveQueryResultsChanged {
        _ = try bumpMetadataRevisionWithoutTransaction(Self.queryResultRevisionKey)
      }
      try execute(
        """
        INSERT INTO instant_application_persistence_migrations (name, applied_at_ms)
        VALUES (?, ?)
        """,
        [.text(migration.name), .int(Self.nowMilliseconds())]
      )
      return didChangeAny
    }
    cachedState = nil
    cachedMaterializedStore = nil
    return didChange
  }

  private func nextApplicationMigrationOutboxRowWithoutTransaction(
    after mutationID: String?
  ) throws -> InstantApplicationMigrationOutboxRow? {
    var statement: OpaquePointer?
    let sql: String
    let bindings: [SQLiteBinding]
    if let mutationID {
      sql =
        """
        SELECT mutation_id, created_at_ms, length(CAST(json AS BLOB)), json,
               delivery_started, confirmation_proven,
               optimistic_overlay_active,
               optimistic_effect_receipt_fingerprint,
               server_acceptance_payload_fingerprint
        FROM instant_outbox
        WHERE mutation_id > ?
        ORDER BY mutation_id
        LIMIT 1
        """
      bindings = [.text(mutationID)]
    } else {
      sql =
        """
        SELECT mutation_id, created_at_ms, length(CAST(json AS BLOB)), json,
               delivery_started, confirmation_proven,
               optimistic_overlay_active,
               optimistic_effect_receipt_fingerprint,
               server_acceptance_payload_fingerprint
        FROM instant_outbox
        ORDER BY mutation_id
        LIMIT 1
        """
      bindings = []
    }
    try prepare(sql, statement: &statement)
    defer { sqlite3_finalize(statement) }
    try bind(bindings, to: statement)
    let code = sqlite3_step(statement)
    if code == SQLITE_DONE { return nil }
    guard code == SQLITE_ROW,
      let mutationIDBytes = sqlite3_column_text(statement, 0),
      let jsonBytes = sqlite3_column_text(statement, 3)
    else {
      throw persistenceError(
        operation: "read local persistence migration outbox row",
        message: lastErrorMessage()
      )
    }
    let rowMutationID = String(cString: mutationIDBytes)
    let createdAtMilliseconds = sqlite3_column_int64(statement, 1)
    let bodyByteCount = sqlite3_column_int64(statement, 2)
    guard bodyByteCount >= 0,
      bodyByteCount <= Int64(InstantAutomaticOutboxClaimLimits.maximumEncodedBodyBytes)
    else {
      throw persistenceError(
        operation: "read local persistence migration outbox row",
        message:
          "Mutation '\(rowMutationID)' exceeds the bounded outbox body limit and cannot be migrated safely."
      )
    }
    let json = String(cString: jsonBytes)
    let mutation: PendingMutation = try decodeOutboxBody(json)
    guard mutation.id == rowMutationID,
      mutation.createdAt.milliseconds == createdAtMilliseconds
    else {
      throw persistenceError(
        operation: "read local persistence migration outbox row",
        message: "The decoded durable mutation did not match its SQLite identity."
      )
    }
    decodedOutboxBodyCount += 1
    decodedOutboxBodyByteCount += Int(bodyByteCount)
    return InstantApplicationMigrationOutboxRow(
      mutation: mutation,
      deliveryStarted: sqlite3_column_int64(statement, 4) != 0,
      confirmationProven: sqlite3_column_int64(statement, 5) != 0,
      optimisticOverlayActive: sqlite3_column_int64(statement, 6) != 0,
      optimisticEffectReceiptFingerprint: sqlite3_column_text(statement, 7)
        .map(String.init(cString:)),
      serverAcceptancePayloadFingerprint: sqlite3_column_text(statement, 8)
        .map(String.init(cString:))
    )
  }

  private func nextApplicationMigrationAttributeWithoutTransaction(
    after attributeID: String?,
    affectedAttributeIDs: Set<String>
  ) throws -> InstantAttribute? {
    let sortedAttributeIDs = affectedAttributeIDs.sorted()
    let placeholders = Array(repeating: "?", count: sortedAttributeIDs.count).joined(
      separator: ", "
    )
    let cursorClause = attributeID == nil ? "" : "AND id > ?"
    var bindings = sortedAttributeIDs.map(SQLiteBinding.text)
    if let attributeID {
      bindings.append(.text(attributeID))
    }
    let attributes: [InstantAttribute] = try selectJSON(
      """
      SELECT json FROM instant_attributes
      WHERE id IN (\(placeholders)) \(cursorClause)
      ORDER BY id
      LIMIT 1
      """,
      bindings
    )
    return attributes.first
  }

  private func nextApplicationMigrationTripleRowWithoutTransaction(
    after rowID: Int64,
    affectedAttributeIDs: Set<String>
  ) throws -> InstantApplicationMigrationTripleRow? {
    var statement: OpaquePointer?
    let sortedAttributeIDs = affectedAttributeIDs.sorted()
    let placeholders = Array(repeating: "?", count: sortedAttributeIDs.count).joined(
      separator: ", "
    )
    try prepare(
      """
      SELECT rowid, length(CAST(json AS BLOB)) FROM instant_triples
      WHERE rowid > ? AND attribute_id IN (\(placeholders))
      ORDER BY rowid
      LIMIT 1
      """,
      statement: &statement
    )
    defer { sqlite3_finalize(statement) }
    try bind([.int(rowID)] + sortedAttributeIDs.map(SQLiteBinding.text), to: statement)
    let code = sqlite3_step(statement)
    if code == SQLITE_DONE { return nil }
    guard code == SQLITE_ROW else {
      throw persistenceError(
        operation: "read local persistence migration triple",
        message: lastErrorMessage()
      )
    }
    let matchingRowID = sqlite3_column_int64(statement, 0)
    let bodyByteCount = sqlite3_column_int64(statement, 1)
    guard bodyByteCount >= 0,
      bodyByteCount <= Int64(InstantAutomaticOutboxClaimLimits.maximumEncodedBodyBytes)
    else {
      throw persistenceError(
        operation: "read local persistence migration triple",
        message:
          "A matching canonical triple exceeds the bounded migration row limit and cannot be migrated safely."
      )
    }
    guard let json: String = try selectScalar(
      "SELECT json FROM instant_triples WHERE rowid = ? LIMIT 1",
      [.int(matchingRowID)]
    ),
      let data = json.data(using: .utf8)
    else {
      throw persistenceError(
        operation: "read local persistence migration triple",
        message: "The matching canonical triple disappeared before it could be decoded."
      )
    }
    return InstantApplicationMigrationTripleRow(
      rowID: matchingRowID,
      triple: try decoder.decode(InstantTriple.self, from: data)
    )
  }

  private func nextApplicationMigrationLiveQueryResultWithoutTransaction(
    after queryKey: String?,
    affectedAttributeIDs: Set<String>
  ) throws -> InstantPersistedLiveQueryResult? {
    var statement: OpaquePointer?
    let sortedAttributeIDs = affectedAttributeIDs.sorted()
    let placeholders = Array(repeating: "?", count: sortedAttributeIDs.count).joined(
      separator: ", "
    )
    let cursorClause = queryKey == nil ? "" : "AND result.query_key > ?"
    var bindings = sortedAttributeIDs.map(SQLiteBinding.text)
    if let queryKey {
      bindings.append(.text(queryKey))
    }
    let sql =
      """
      SELECT result.query_key, length(CAST(result.json AS BLOB))
      FROM instant_live_query_results AS result
      WHERE EXISTS (
        SELECT 1 FROM instant_live_query_triples AS owned
        WHERE owned.query_key = result.query_key
          AND owned.attribute_id IN (\(placeholders))
      )
      \(cursorClause)
      ORDER BY result.query_key
      LIMIT 1
      """
    try prepare(sql, statement: &statement)
    defer { sqlite3_finalize(statement) }
    try bind(bindings, to: statement)
    let code = sqlite3_step(statement)
    if code == SQLITE_DONE { return nil }
    guard code == SQLITE_ROW,
      let queryKeyBytes = sqlite3_column_text(statement, 0)
    else {
      throw persistenceError(
        operation: "read local persistence migration live-query result",
        message: lastErrorMessage()
      )
    }
    let rowQueryKey = String(cString: queryKeyBytes)
    let bodyByteCount = sqlite3_column_int64(statement, 1)
    guard bodyByteCount >= 0,
      bodyByteCount <= Int64(InstantAutomaticOutboxClaimLimits.maximumEncodedBodyBytes)
    else {
      throw persistenceError(
        operation: "read local persistence migration live-query result",
        message:
          "Live-query result '\(rowQueryKey)' exceeds the bounded migration row limit and cannot be migrated safely."
      )
    }
    guard let json: String = try selectScalar(
      "SELECT json FROM instant_live_query_results WHERE query_key = ? LIMIT 1",
      [.text(rowQueryKey)]
    ),
      let data = json.data(using: .utf8)
    else {
      throw persistenceError(
        operation: "read local persistence migration live-query result",
        message: "Live-query result '\(rowQueryKey)' disappeared before it could be decoded."
      )
    }
    let result = try decoder.decode(InstantPersistedLiveQueryResult.self, from: data)
    guard result.key == rowQueryKey else {
      throw persistenceError(
        operation: "read local persistence migration live-query result",
        message: "The decoded live-query result did not match its SQLite identity."
      )
    }
    return result
  }

  private func validateApplicationMigrationIdentity(
    original: PendingMutation,
    migrated: PendingMutation,
    migrationName: String,
    affectedAttributeIDs: Set<String>
  ) throws {
    let normalizedOriginalTransaction = normalizedApplicationMigrationTransaction(
      original.transaction,
      affectedAttributeIDs: affectedAttributeIDs
    )
    let normalizedMigratedTransaction = normalizedApplicationMigrationTransaction(
      migrated.transaction,
      affectedAttributeIDs: affectedAttributeIDs
    )
    let normalizedOriginalRollback = original.rollbackTransaction.map { transaction in
      normalizedApplicationMigrationTransaction(
        transaction,
        affectedAttributeIDs: affectedAttributeIDs
      )
    }
    let normalizedMigratedRollback = migrated.rollbackTransaction.map { transaction in
      normalizedApplicationMigrationTransaction(
        transaction,
        affectedAttributeIDs: affectedAttributeIDs
      )
    }
    guard migrated.id == original.id,
      migrated.createdAt == original.createdAt,
      migrated.transaction.id == original.transaction.id,
      migrated.rollbackTransaction?.id == original.rollbackTransaction?.id,
      migrated.status == original.status,
      migrated.failureMessage == original.failureMessage,
      migrated.failure == original.failure,
      migrated.serverTransactionID == original.serverTransactionID,
      migrated.confirmationSource == original.confirmationSource,
      migrated.optimisticOverlayState == original.optimisticOverlayState,
      migrated.optimisticEffectReceiptVersion == original.optimisticEffectReceiptVersion,
      normalizedMigratedTransaction == normalizedOriginalTransaction,
      normalizedMigratedRollback == normalizedOriginalRollback
    else {
      throw persistenceError(
        operation: "apply local persistence migration",
        message:
          "Application migration '\(migrationName)' changed durable outbox identity or lifecycle metadata for '\(original.id)'; only forward and rollback operations may be value-transformed."
      )
    }
  }

  private func normalizedApplicationMigrationTransaction(
    _ transaction: InstantStoreTransaction,
    affectedAttributeIDs: Set<String>
  ) -> InstantStoreTransaction {
    InstantStoreTransaction(
      id: transaction.id,
      operations: transaction.operations.map { operation in
        normalizedApplicationMigrationOperation(
          operation,
          affectedAttributeIDs: affectedAttributeIDs
        )
      }
    )
  }

  private func normalizedApplicationMigrationOperation(
    _ operation: InstantTripleOperation,
    affectedAttributeIDs: Set<String>
  ) -> InstantTripleOperation {
    func value(_ value: InstantValue, attributeID: String) -> InstantValue {
      affectedAttributeIDs.contains(attributeID) ? .null : value
    }
    func lookup(_ lookup: InstantLookupRef) -> InstantLookupRef {
      guard affectedAttributeIDs.contains(lookup.attributeID) else { return lookup }
      return InstantLookupRef(attributeID: lookup.attributeID, value: .null)
    }
    func triple(_ triple: InstantTriple) -> InstantTriple {
      var triple = triple
      triple.value = value(triple.value, attributeID: triple.attributeID)
      return triple
    }

    return switch operation {
    case .requireEntityMissing, .requireEntityExists,
      .deleteEntity, .deleteEntityInNamespace, .ruleParams:
      operation
    case let .requireEntityMissingByLookup(entity, namespace):
      .requireEntityMissingByLookup(lookup(entity), namespace: namespace)
    case let .requireEntityExistsByLookup(entity, namespace):
      .requireEntityExistsByLookup(lookup(entity), namespace: namespace)
    case let .requireTripleExists(entityID, attributeID, requiredValue):
      .requireTripleExists(
        entityID: entityID,
        attributeID: attributeID,
        value: value(requiredValue, attributeID: attributeID)
      )
    case let .merge(merged):
      .merge(triple(merged))
    case let .mergeByLookup(entity, attributeID, mergedValue, txID, txTime):
      .mergeByLookup(
        entity: lookup(entity),
        attributeID: attributeID,
        value: value(mergedValue, attributeID: attributeID),
        txID: txID,
        txTime: txTime
      )
    case let .insert(inserted):
      .insert(triple(inserted))
    case let .insertByLookup(entity, attributeID, insertedValue, txID, txTime):
      .insertByLookup(
        entity: lookup(entity),
        attributeID: attributeID,
        value: value(insertedValue, attributeID: attributeID),
        txID: txID,
        txTime: txTime
      )
    case let .retract(retracted):
      .retract(triple(retracted))
    case let .retractByLookup(entity, attributeID, retractedValue, txID, txTime):
      .retractByLookup(
        entity: lookup(entity),
        attributeID: attributeID,
        value: value(retractedValue, attributeID: attributeID),
        txID: txID,
        txTime: txTime
      )
    case let .deleteEntityByLookup(entity):
      .deleteEntityByLookup(lookup(entity))
    case let .ruleParamsByLookup(entity, namespace, params):
      .ruleParamsByLookup(
        entity: lookup(entity),
        namespace: namespace,
        params: params
      )
    }
  }

  private func validateApplicationMigrationOutboxRewrite(
    row: InstantApplicationMigrationOutboxRow,
    migrationName: String
  ) throws {
    guard !row.deliveryStarted,
      !row.confirmationProven,
      row.serverAcceptancePayloadFingerprint == nil
    else {
      throw InstantError(
        code: .persistenceFailed,
        operation: "apply local persistence migration",
        localID: row.mutation.id,
        message:
          "Application migration '\(migrationName)' cannot rewrite mutation '\(row.mutation.id)' after its payload was offered to delivery or accepted by the server.",
        recovery:
          "Preserve the existing mutation body and submit any changed wire intent under a new transaction id."
      )
    }
    guard try applicationMigrationReceiptMatches(row) else {
      throw InstantError(
        code: .persistenceFailed,
        operation: "apply local persistence migration",
        localID: row.mutation.id,
        message:
          "Application migration '\(migrationName)' cannot prove the durable optimistic effect owned by mutation '\(row.mutation.id)'.",
        recovery:
          "Preserve the row and use an app-owned persistence reset or authoritative recovery instead of guessing its inverse."
      )
    }
  }

  private func validateApplicationMigrationOutboxBounds(
    _ mutation: PendingMutation,
    migrationName: String
  ) throws {
    let stepCount = InstantOutboxDeliveryMetadata.stepCount(in: mutation)
    guard stepCount <= InstantAutomaticOutboxClaimLimits.maximumStepCount else {
      throw InstantError(
        code: .persistenceFailed,
        operation: "apply local persistence migration",
        localID: mutation.id,
        message:
          "Application migration '\(migrationName)' expanded mutation '\(mutation.id)' to \(stepCount) transport steps, beyond the automatic-delivery limit.",
        recovery: "Keep the original row and submit smaller compensating transactions instead."
      )
    }
    let encodedBodyByteCount = try encode(mutation).utf8.count
    guard encodedBodyByteCount <= InstantAutomaticOutboxClaimLimits.maximumEncodedBodyBytes
    else {
      throw InstantError(
        code: .persistenceFailed,
        operation: "apply local persistence migration",
        localID: mutation.id,
        message:
          "Application migration '\(migrationName)' expanded mutation '\(mutation.id)' to \(encodedBodyByteCount) bytes, beyond the durable delivery limit.",
        recovery: "Keep the original row and submit smaller compensating transactions instead."
      )
    }
  }

  private func applicationMigrationReceiptMatches(
    _ row: InstantApplicationMigrationOutboxRow
  ) throws -> Bool {
    guard let durableReceipt = row.optimisticEffectReceiptFingerprint,
      let computedReceipt = try row.mutation.optimisticEffectReceiptFingerprint()
    else { return false }
    guard durableReceipt == computedReceipt else { return false }
    return switch row.mutation.optimisticOverlayState {
    case .applied:
      row.optimisticOverlayActive
    case .removed:
      !row.optimisticOverlayActive
    case nil:
      false
    }
  }

  func simulateUnexpectedConnectionCloseForTesting() {
    sqlite3_close(connection.raw)
    connection.raw = nil
  }

  public func loadSnapshot() throws -> InstantPersistenceSnapshot {
    try loadState().snapshot
  }

  public func loadState() throws -> InstantPersistenceState {
    for _ in 0..<5 {
      let loaded = try loadStateWithSource()
      let store: InstantStoreSnapshot
      if case .snapshot = loaded.storeAdoption {
        store = loaded.state.snapshot.store
      } else {
        guard let reloadedStore = try loadStoreSnapshot(
          expectedStoreRevision: loaded.state.storeRevision,
          expectedAttributeRevision: loaded.state.attributeRevision,
          expectedOutboxRevision: loaded.state.outboxRevision
        ) else { continue }
        store = reloadedStore
      }
      guard let outbox = try loadOutboxMutations(
        statuses: [.pending, .confirmed, .failed],
        expectedStoreRevision: loaded.state.storeRevision,
        expectedOutboxRevision: loaded.state.outboxRevision
      ) else { continue }
      var state = loaded.state
      state.snapshot.store = store
      state.snapshot.outbox = outbox
      return state
    }
    throw persistenceError(
      operation: "load persisted state",
      message: "The Instant store or outbox changed repeatedly while reconstructing durable state."
    )
  }

  /// Loads the memory-thinned cache view used by runtime paths that need only
  /// store data, revisions, or outbox identity/status metadata. Call `loadState()`
  /// when transaction and rollback operation bodies are part of the contract.
  func loadCompactState() throws -> InstantPersistenceState {
    try loadStateWithSource().state
  }

  private func loadStoreSnapshot(
    expectedStoreRevision: Int64,
    expectedAttributeRevision: Int64,
    expectedOutboxRevision: Int64
  ) throws -> InstantStoreSnapshot? {
    try readTransaction {
      guard
        try loadMetadataRevisionWithoutTransaction(Self.storeRevisionKey)
          == expectedStoreRevision,
        try loadMetadataRevisionWithoutTransaction(Self.attributeRevisionKey)
          == expectedAttributeRevision,
        try loadMetadataRevisionWithoutTransaction(Self.outboxRevisionKey)
          == expectedOutboxRevision
      else { return nil }
      return try loadStoreSnapshotWithoutTransaction(
        tracesStartupCollections: false
      )
    }
  }

  func loadStateWithDurableOutbox() throws -> InstantPersistenceState {
    for _ in 0..<5 {
      let loaded = try loadStateWithSource()
      guard let outbox = try loadOutboxMutations(
        statuses: [.pending, .confirmed, .failed],
        expectedStoreRevision: loaded.state.storeRevision,
        expectedOutboxRevision: loaded.state.outboxRevision
      ) else { continue }
      var state = loaded.state
      state.snapshot.outbox = outbox
      return state
    }
    throw persistenceError(
      operation: "load durable outbox state",
      message: "The Instant outbox changed repeatedly while reconstructing durable mutations."
    )
  }

  func countOutboxMutations(status: InstantMutationStatus) throws -> Int {
    Int(try selectInt64(
      "SELECT COUNT(*) FROM instant_outbox WHERE status = ?",
      [.text(status.rawValue)]
    ))
  }

  func countOutboxMutations() throws -> Int {
    Int(try selectInt64("SELECT COUNT(*) FROM instant_outbox"))
  }

  /// Resolves one live mutation-error frame without decoding a mutation body.
  ///
  /// The delivery claim, not a process-resident shell or lifecycle alias, is
  /// the server-event ownership proof. This makes duplicate terminal frames
  /// cheap and prevents a late frame from failing work reclaimed by another
  /// runtime after the five-second claim deadline.
  func liveMutationErrorDisposition(
    id: String,
    claimantID: String,
    claimToken: String?
  ) throws -> InstantLiveMutationErrorDisposition {
    guard !id.isEmpty else { return .missing }
    guard let claimToken, !claimToken.isEmpty else { return .stale }
    let value = try selectScalar(
      """
      SELECT CASE
        WHEN status = ? OR (status = ? AND confirmation_proven = 1)
          THEN 'terminal'
        WHEN status IN (?, ?) AND confirmation_proven = 0
          AND delivery_state = ? AND delivery_claim_state = ?
          AND COALESCE(delivery_claimant_id, '') = ?
          AND COALESCE(delivery_claim_token, '') = ?
          THEN 'owned:' || delivery_claim_token
        ELSE 'stale'
      END
      FROM instant_outbox
      WHERE mutation_id = ?
      LIMIT 1
      """,
      [
        .text(InstantMutationStatus.failed.rawValue),
        .text(InstantMutationStatus.confirmed.rawValue),
        .text(InstantMutationStatus.pending.rawValue),
        .text(InstantMutationStatus.confirmed.rawValue),
        .text(InstantOutboxDeliveryState.needsDelivery.rawValue),
        .text(InstantOutboxDeliveryClaimState.claimed.rawValue),
        .text(claimantID),
        .text(claimToken),
        .text(id),
      ]
    )
    guard let value else { return .missing }
    if value == "terminal" { return .alreadyTerminal }
    if value == "stale" { return .stale }
    let prefix = "owned:"
    guard value.hasPrefix(prefix) else { return .stale }
    let token = String(value.dropFirst(prefix.count))
    return token.isEmpty ? .stale : .owned(claimToken: token)
  }

  /// Loads only the rejected mutation and the transitive optimistic component
  /// that can observe its removal. Component membership is proven from scalar
  /// metadata before any durable JSON body enters Swift memory.
  func loadClaimedTerminalFailureComponent(
    id: String,
    claimToken: String,
    expectedStoreRevision: Int64,
    expectedAttributeRevision: Int64
  ) throws -> InstantTerminalFailureComponentLoad {
    try readTransaction {
      guard
        try loadMetadataRevisionWithoutTransaction(Self.storeRevisionKey)
          == expectedStoreRevision,
        try loadMetadataRevisionWithoutTransaction(Self.attributeRevisionKey)
          == expectedAttributeRevision,
        let target = try loadTerminalFailureTargetControlWithoutTransaction(id: id)
      else { return .staleClaim }

      if target.status == .failed
        || (target.status == .confirmed && target.confirmationProven)
      {
        return .alreadyTerminal
      }
      guard target.status == .pending || target.status == .confirmed,
        !target.confirmationProven,
        target.deliveryState == .needsDelivery,
        target.claimState == .claimed,
        target.claimToken == claimToken
      else { return .staleClaim }

      let resolution = try resolveOptimisticEffectComponentRowsWithoutTransaction(
        target: target.effect
      )
      let rows: InstantOptimisticEffectComponentRows
      switch resolution {
      case let .normalizationRequired(mutationID):
        return .normalizationRequired(firstMutationID: mutationID)
      case let .ready(readyRows):
        rows = readyRows
      }

      let encodedBodyByteCount = rows.all.reduce(into: 0) { partialResult, row in
        partialResult += row.encodedBodyByteCount
      }
      guard
        rows.all.count <= InstantAutomaticOutboxClaimLimits.maximumBodyDecodeCount,
        encodedBodyByteCount <= InstantAutomaticOutboxClaimLimits.maximumEncodedBodyBytes
      else {
        return .componentLimitExceeded(
          mutationCountAtLeast: rows.all.count,
          encodedBodyByteCountAtLeast: encodedBodyByteCount
        )
      }

      var mutations: [PendingMutation] = []
      mutations.reserveCapacity(rows.all.count)
      var decodedByteCount = 0
      for row in rows.all {
        guard let body = try loadOutboxBodyRowWithoutTransaction(id: row.mutationID) else {
          return .staleClaim
        }
        let bodyByteCount = body.json.utf8.count
        guard
          decodedByteCount <= InstantAutomaticOutboxClaimLimits.maximumEncodedBodyBytes
            - bodyByteCount
        else {
          return .componentLimitExceeded(
            mutationCountAtLeast: rows.all.count,
            encodedBodyByteCountAtLeast: decodedByteCount + bodyByteCount
          )
        }
        let mutation: PendingMutation = try decodeOutboxBody(body.json)
        decodedOutboxBodyCount += 1
        decodedOutboxBodyByteCount += bodyByteCount
        decodedByteCount += bodyByteCount
        guard mutation.id == row.mutationID,
          mutation.createdAt.milliseconds == row.position.createdAtMilliseconds,
          try hasStoredPreparedOptimisticEffectReceiptWithoutTransaction(mutation)
        else {
          throw persistenceError(
            operation: "load terminal failure component",
            message:
              "The durable mutation body did not match its indexed, SQLite-owned Runtime-prepared component row."
          )
        }
        mutations.append(mutation)
      }

      guard let targetMutation = mutations.first else { return .staleClaim }
      return .ready(
        InstantTerminalFailureComponent(
          target: targetMutation,
          successors: Array(mutations.dropFirst()),
          targetPosition: rows.target.position,
          expectedStoreRevision: expectedStoreRevision,
          rowRevisions: Dictionary(
            uniqueKeysWithValues: rows.all.map { ($0.mutationID, $0.mutationRevision) }
          ),
          decodedBodyCount: mutations.count,
          decodedBodyByteCount: decodedByteCount
        )
      )
    }
  }

  /// Backfills normalized optimistic-effect metadata in one bounded body
  /// window. A body that cannot prove its overlay state stops normalization so
  /// terminal rejection fails closed rather than guessing an inverse.
  func normalizeOptimisticEffectMetadata(
    startingAtMutationID mutationID: String
  ) throws -> InstantOptimisticEffectNormalizationResult {
    let result = try transaction {
      guard let startingPosition = try loadOutboxPositionWithoutTransaction(id: mutationID) else {
        return InstantOptimisticEffectNormalizationResult(
          normalizedMutationIDs: [],
          blockedMutationID: mutationID,
          decodedBodyCount: 0,
          decodedBodyByteCount: 0
        )
      }
      let candidates = try loadUnknownOptimisticEffectRowsWithoutTransaction(
        atOrAfter: startingPosition,
        limit: InstantAutomaticOutboxClaimLimits.maximumBodyDecodeCount + 1
      )
      var normalizedMutationIDs: [String] = []
      var blockedMutationID: String?
      var decodedBodyCount = 0
      var decodedBodyByteCount = 0

      for candidate in candidates {
        guard decodedBodyCount < InstantAutomaticOutboxClaimLimits.maximumBodyDecodeCount,
          candidate.encodedBodyByteCount
            <= InstantAutomaticOutboxClaimLimits.maximumEncodedBodyBytes
              - decodedBodyByteCount
        else {
          blockedMutationID = candidate.mutationID
          break
        }
        guard let row = try loadOutboxBodyRowWithoutTransaction(id: candidate.mutationID) else {
          blockedMutationID = candidate.mutationID
          break
        }
        let bodyByteCount = row.json.utf8.count
        guard bodyByteCount <= InstantAutomaticOutboxClaimLimits.maximumEncodedBodyBytes
          - decodedBodyByteCount
        else {
          blockedMutationID = candidate.mutationID
          break
        }
        let mutation: PendingMutation = try decodeOutboxBody(row.json)
        decodedOutboxBodyCount += 1
        decodedOutboxBodyByteCount += bodyByteCount
        decodedBodyCount += 1
        decodedBodyByteCount += bodyByteCount
        guard mutation.id == candidate.mutationID,
          try hasStoredPreparedOptimisticEffectReceiptWithoutTransaction(mutation),
          let footprint = InstantOptimisticEffectFootprint.normalized(for: mutation)
        else {
          blockedMutationID = candidate.mutationID
          break
        }

        try execute(
          """
          UPDATE instant_outbox
          SET optimistic_effect_metadata_version = ?, optimistic_effect_is_global = ?,
              mutation_revision = mutation_revision + 1
          WHERE mutation_id = ? AND mutation_revision = ?
          """,
          [
            .int(Int64(InstantOptimisticEffectFootprint.currentVersion)),
            .int(footprint.isGlobal ? 1 : 0),
            .text(candidate.mutationID),
            .int(candidate.mutationRevision),
          ]
        )
        guard sqlite3_changes(connection.raw) == 1 else {
          blockedMutationID = candidate.mutationID
          break
        }
        try replaceOutboxEffectEntitiesWithoutTransaction(
          mutationID: candidate.mutationID,
          createdAtMilliseconds: candidate.position.createdAtMilliseconds,
          entityIDs: footprint.entityIDs
        )
        normalizedMutationIDs.append(candidate.mutationID)
      }

      if !normalizedMutationIDs.isEmpty {
        _ = try bumpMetadataRevisionWithoutTransaction(Self.outboxRevisionKey)
      }
      return InstantOptimisticEffectNormalizationResult(
        normalizedMutationIDs: normalizedMutationIDs,
        blockedMutationID: blockedMutationID,
        decodedBodyCount: decodedBodyCount,
        decodedBodyByteCount: decodedBodyByteCount
      )
    }
    if !result.normalizedMutationIDs.isEmpty {
      cachedState = nil
    }
    return result
  }

  /// Builds a body-free, indexed plan for one authoritative server apply.
  ///
  /// Upstream Reactor creates a fresh server query store and then reapplies
  /// optimistic mutations (`Reactor.js` 725-805, 1398-1431). Swift keeps one
  /// materialized store, so the equivalent component must be peeled and
  /// replayed. Only mutations connected to the authoritative footprint (plus
  /// failed-active and watermark roots) enter this plan.
  func beginServerApplyPlan(
    id planID: String,
    footprint: InstantServerApplyFootprint,
    hasServerOperations: Bool,
    processedTransactionID: String,
    confirmingMutationID: String?,
    confirmingClaimantID: String?
  ) throws -> InstantServerApplyPlanLoad {
    precondition(
      (confirmingMutationID == nil) == (confirmingClaimantID == nil),
      "A confirming server apply must identify both its mutation and durable claimant."
    )
    let result: InstantServerApplyPlanLoad = try transaction {
      try deleteServerApplyPlanWithoutTransaction(id: planID)
      let expectedStoreRevision = try loadMetadataRevisionWithoutTransaction(
        Self.storeRevisionKey
      )
      let expectedAttributeRevision = try loadMetadataRevisionWithoutTransaction(
        Self.attributeRevisionKey
      )
      let expectedOutboxRevision = try loadMetadataRevisionWithoutTransaction(
        Self.outboxRevisionKey
      )
      let expectedQueryResultRevision = try loadMetadataRevisionWithoutTransaction(
        Self.queryResultRevisionKey
      )
      let baselineOutboxRowCount = Int(try selectInt64(
        "SELECT COUNT(*) FROM instant_outbox"
      ))
      let baselineOutboxTail = try latestOutboxPositionWithoutTransaction()

      if hasServerOperations,
        let unknownMutationID = try firstUnknownActiveServerApplyMutationIDWithoutTransaction()
      {
        return .normalizationRequired(firstMutationID: unknownMutationID)
      }

      try execute(
        """
        INSERT INTO instant_server_apply_plans (
          plan_id, expected_store_revision, expected_attribute_revision,
          expected_outbox_revision, expected_query_result_revision,
          processed_transaction_id, processed_transaction_number,
          server_has_operations, root_is_global, confirming_mutation_id,
          confirming_claimant_id
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """,
        [
          .text(planID),
          .int(expectedStoreRevision),
          .int(expectedAttributeRevision),
          .int(expectedOutboxRevision),
          .int(expectedQueryResultRevision),
          .text(processedTransactionID),
          Int64(processedTransactionID).map(SQLiteBinding.int) ?? .null,
          .int(hasServerOperations ? 1 : 0),
          .int(footprint.isGlobal ? 1 : 0),
          confirmingMutationID.map(SQLiteBinding.text) ?? .null,
          confirmingClaimantID.map(SQLiteBinding.text) ?? .null,
        ]
      )
      for entityID in footprint.entityIDs.sorted() {
        try execute(
          """
          INSERT INTO instant_server_apply_roots (plan_id, entity_id)
          VALUES (?, ?)
          """,
          [.text(planID), .text(entityID)]
        )
      }
      try populateServerApplyPlanRowsWithoutTransaction(id: planID)
      let bodyCount = Int(try selectInt64(
        """
        SELECT COUNT(*) FROM instant_server_apply_rows
        WHERE plan_id = ? AND requires_body = 1
        """,
        [.text(planID)]
      ))
      let bodyByteCount = Int(try selectInt64(
        """
        SELECT COALESCE(SUM(expected_body_bytes), 0)
        FROM instant_server_apply_rows
        WHERE plan_id = ? AND requires_body = 1
        """,
        [.text(planID)]
      ))
      return .ready(
        InstantServerApplyPlan(
          id: planID,
          expectedStoreRevision: expectedStoreRevision,
          expectedAttributeRevision: expectedAttributeRevision,
          expectedOutboxRevision: expectedOutboxRevision,
          expectedQueryResultRevision: expectedQueryResultRevision,
          baselineOutboxRowCount: baselineOutboxRowCount,
          baselineOutboxTail: baselineOutboxTail,
          plannedBodyCount: bodyCount,
          plannedBodyByteCount: bodyByteCount
        )
      )
    }
    if case let .ready(plan) = result {
      serverApplyMetrics.planCount += 1
      serverApplyMetrics.plannedBodyCount += plan.plannedBodyCount
      serverApplyMetrics.plannedBodyByteCount += plan.plannedBodyByteCount
    }
    return result
  }

  /// Returns the first active optimistic row that has no SQLite-owned Runtime
  /// preparation receipt. The check is body-free and intentionally includes
  /// failed rows: without a proven inverse, even a terminal row can own local
  /// triples and must block a new live connection rather than silently suppress
  /// authoritative retractions forever.
  func firstActiveMutationMissingPreparedReceiptFingerprint() throws -> String? {
    try synchronizationBlocker()?.firstMutationID
  }

  /// Derives the durable synchronization blocker without reading a mutation
  /// body. A nil SQLite receipt is the post-migration authority boundary; an
  /// older metadata version alone is not a blocker because bounded
  /// normalization may still repair it.
  func synchronizationBlocker() throws -> InstantSynchronizationBlocker? {
    try readTransaction {
      try synchronizationBlockerWithoutTransaction()
    }
  }

  /// Refuses to isolate an unknown-effect row during an incremental server apply.
  ///
  /// Neither caller-visible rollback bytes nor caller-visible acceptance fields
  /// prove what is currently materialized. Inactivating such a row could leave
  /// an ownerless optimistic value, even when a server watermark appears to
  /// cover it. The active owner therefore remains as a surfaced manual-repair
  /// barrier, and this apply stays fail-closed. Runtime stops the current live
  /// generation rather than reconnecting through the same unsafe row.
  func isolateUnknownServerApplyMutation(
    id: String,
    processedTransactionID: String
  ) throws -> Bool {
    _ = id
    _ = processedTransactionID
    return false
  }

  private static func transactionID(
    _ transactionID: String,
    isCoveredBy processedTransactionID: String
  ) -> Bool {
    if transactionID == processedTransactionID { return true }
    guard let transactionNumber = Int64(transactionID),
      let processedTransactionNumber = Int64(processedTransactionID)
    else { return false }
    return transactionNumber <= processedTransactionNumber
  }

  /// Filters live-query retractions using normalized optimistic-effect indexes.
  /// Upstream keeps server and optimistic stores separate; this is the Swift
  /// one-store equivalent of reapplying the overlay after `refresh-ok`.
  func protectingServerRetractions(
    _ operations: [InstantTripleOperation]
  ) throws -> [InstantTripleOperation] {
    try readTransaction {
      try protectingServerRetractionsWithoutTransaction(operations)
    }
  }

  func protectingServerRetractions(
    _ operations: [InstantTripleOperation],
    expectedOutboxRevision: Int64
  ) throws -> [InstantTripleOperation]? {
    try readTransaction {
      guard try loadMetadataRevisionWithoutTransaction(Self.outboxRevisionKey)
        == expectedOutboxRevision
      else { return nil }
      return try protectingServerRetractionsWithoutTransaction(operations)
    }
  }

  private func protectingServerRetractionsWithoutTransaction(
    _ operations: [InstantTripleOperation]
  ) throws -> [InstantTripleOperation] {
    guard operations.contains(where: {
      if case .retract = $0 { return true }
      return false
    }) else { return operations }
    let protectsEveryRetraction = try selectInt64(
      """
      SELECT EXISTS(
        SELECT 1
        FROM instant_outbox
        WHERE optimistic_overlay_active = 1
          AND (
            (
              status != ? AND (
                optimistic_effect_is_global = 1
                OR optimistic_effect_metadata_version != ?
                OR optimistic_effect_receipt_fingerprint IS NULL
              )
            )
            OR (
              status = ?
              AND optimistic_effect_receipt_fingerprint IS NULL
            )
          )
        LIMIT 1
      )
      """,
      [
        .text(InstantMutationStatus.failed.rawValue),
        .int(Int64(InstantOptimisticEffectFootprint.currentVersion)),
        .text(InstantMutationStatus.failed.rawValue),
      ]
    ) != 0
    if protectsEveryRetraction {
      return operations.filter {
        if case .retract = $0 { return false }
        return true
      }
    }
    var protected: [InstantTripleOperation] = []
    protected.reserveCapacity(operations.count)
    for operation in operations {
      guard case let .retract(triple) = operation else {
        protected.append(operation)
        continue
      }
      let hasOwner = try selectInt64(
        """
        SELECT EXISTS(
          SELECT 1
          FROM instant_outbox_effect_entities AS effects
            INDEXED BY instant_outbox_effect_entities_lookup_idx
          JOIN instant_outbox AS outbox
            ON outbox.mutation_id = effects.mutation_id
          WHERE effects.entity_id = ?
            AND outbox.optimistic_overlay_active = 1
            AND outbox.status != ?
          LIMIT 1
        )
        """,
        [.text(triple.entityID), .text(InstantMutationStatus.failed.rawValue)]
      ) != 0
      if !hasOwner { protected.append(operation) }
    }
    return protected
  }

  func loadServerApplyBodyPage(
    planID: String,
    direction: InstantServerApplyBodyDirection,
    after position: InstantOutboxDeliveryPosition?
  ) throws -> InstantServerApplyBodyPage {
    let page = try transaction {
      try loadServerApplyBodyPageWithoutTransaction(
        planID: planID,
        direction: direction,
        after: position
      )
    }
    if let blocker = page.synchronizationBlocker {
      cachedState = nil
      throw blocker.error(operation: "apply server transaction")
    }
    serverApplyMetrics.recordBodyPage(
      direction: direction,
      bodyCount: page.entries.count,
      bodyByteCount: page.decodedBodyByteCount
    )
    return page
  }

  func stageServerApplyBodyPage(
    planID: String,
    dispositions: [InstantServerApplyStagedDisposition]
  ) throws {
    guard !dispositions.isEmpty else { return }
    try transaction {
      for disposition in dispositions {
        let mutationID = disposition.mutationID
        guard try selectInt64(
          """
          SELECT COUNT(*) FROM instant_server_apply_rows
          WHERE plan_id = ? AND mutation_id = ? AND requires_body = 1
          """,
          [.text(planID), .text(mutationID)]
        ) == 1 else {
          throw persistenceError(
            operation: "stage bounded server apply",
            message: "Mutation '\(mutationID)' is not an addressed body in plan '\(planID)'."
          )
        }
        switch disposition {
        case let .remove(mutationID):
          try execute(
            """
            UPDATE instant_server_apply_rows
            SET staged = 1, staged_delete = 1, staged_json = NULL,
                staged_lifecycle_json = NULL
            WHERE plan_id = ? AND mutation_id = ?
            """,
            [.text(planID), .text(mutationID)]
          )

        case let .update(mutation):
          let body = try encode(mutation)
          let lifecycle = try encode(mutation.compactedForMemory)
          let lifecycleByteCount = lifecycle.utf8.count
          guard lifecycleByteCount <= InstantAutomaticOutboxClaimLimits.maximumEncodedBodyBytes
          else {
            throw persistenceError(
              operation: "stage bounded server-apply resident patch",
              message:
                "Mutation '\(mutation.id)' has a \(lifecycleByteCount)-byte compact lifecycle body, beyond the 8 MiB resident-patch limit."
            )
          }
          guard let receiptFingerprint = try mutation.optimisticEffectReceiptFingerprint() else {
            throw persistenceError(
              operation: "stage bounded server apply",
              message:
                "Mutation '\(mutation.id)' was not Runtime-prepared before authoritative replay staging."
            )
          }
          let footprint = InstantOptimisticEffectFootprint.normalized(for: mutation)
          let wireFingerprint = try mutation.mutationWireIntentFingerprint()
          let acceptanceContext: (
            existing: String?, claim: String?, claimant: String?, confirms: Bool,
            originalJSON: String?, expectedDeliveryStarted: Bool,
            currentDeliveryStarted: Bool
          ) = try {
            var statement: OpaquePointer?
            try prepare(
              """
              SELECT planned.expected_server_acceptance_payload_fingerprint,
                     planned.expected_delivery_claim_payload_fingerprint,
                     planned.expected_delivery_claimant_id,
                     planned.confirm_at_apply, planned.original_json,
                     planned.expected_delivery_started, outbox.delivery_started
              FROM instant_server_apply_rows AS planned
              JOIN instant_outbox AS outbox
                ON outbox.mutation_id = planned.mutation_id
              WHERE planned.plan_id = ? AND planned.mutation_id = ?
              LIMIT 1
              """,
              statement: &statement
            )
            defer { sqlite3_finalize(statement) }
            try bind([.text(planID), .text(mutation.id)], to: statement)
            guard sqlite3_step(statement) == SQLITE_ROW else {
              throw persistenceError(
                operation: "stage bounded server apply",
                message: "Mutation '\(mutation.id)' lost its planned acceptance row."
              )
            }
            return (
              sqlite3_column_text(statement, 0).map(String.init(cString:)),
              sqlite3_column_text(statement, 1).map(String.init(cString:)),
              sqlite3_column_text(statement, 2).map(String.init(cString:)),
              sqlite3_column_int64(statement, 3) != 0,
              sqlite3_column_text(statement, 4).map(String.init(cString:)),
              sqlite3_column_int64(statement, 5) != 0,
              sqlite3_column_int64(statement, 6) != 0
            )
          }()
          let originalWireFingerprint: String? = try acceptanceContext.originalJSON.flatMap {
            json in
            let originalMutation: PendingMutation = try decodeOutboxBody(json)
            guard originalMutation.id == mutation.id else { return nil }
            return try originalMutation.mutationWireIntentFingerprint()
          }
          if originalWireFingerprint != wireFingerprint,
            acceptanceContext.expectedDeliveryStarted
              || acceptanceContext.currentDeliveryStarted
          {
            throw persistenceError(
              operation: "persist offered outbox mutation",
              message:
                "Mutation '\(mutation.id)' was already offered to delivery, so a staged server rebase cannot change its forward wire intent. Use a new mutation id for compensating work."
            )
          }
          let acceptanceFingerprint: String?
          if acceptanceContext.confirms {
            let control = try loadServerApplyPlanControlWithoutTransaction(id: planID)
            guard mutation.status == .confirmed,
              let claimedPayloadFingerprint = acceptanceContext.claim,
              acceptanceContext.claimant == control?.confirmingClaimantID
            else {
              throw persistenceError(
                operation: "stage bounded server apply",
                message:
                  "Mutation '\(mutation.id)' did not carry the confirmed lifecycle and exact claim required by its server ACK."
              )
            }
            acceptanceFingerprint = claimedPayloadFingerprint
          } else {
            acceptanceFingerprint = originalWireFingerprint == wireFingerprint
              ? acceptanceContext.existing
              : nil
          }
          let deliveryState = durableDeliveryState(
            for: mutation,
            hasServerAcceptance: acceptanceFingerprint != nil
          )
          try execute(
            """
            UPDATE instant_server_apply_rows
            SET staged = 1, staged_delete = 0, staged_json = ?,
                staged_lifecycle_json = ?, staged_status = ?,
                staged_delivery_state = ?, staged_transport_step_count = ?,
                staged_failure_message = ?, staged_confirmation_proven = ?,
                staged_overlay_active = ?, staged_effect_metadata_version = ?,
                staged_effect_is_global = ?, staged_effect_receipt_fingerprint = ?,
                staged_server_acceptance_payload_fingerprint = ?,
                staged_server_transaction_id = ?,
                staged_confirmation_source = ?
            WHERE plan_id = ? AND mutation_id = ?
            """,
            [
              .text(body),
              .text(lifecycle),
              .text(mutation.status.rawValue),
              .text(deliveryState.rawValue),
              .int(Int64(InstantOutboxDeliveryMetadata.stepCount(in: mutation))),
              mutation.failureMessage.map(SQLiteBinding.text) ?? .null,
              .int(acceptanceFingerprint == nil ? 0 : 1),
              .int(mutation.optimisticOverlayState == .removed ? 0 : 1),
              .int(Int64(
                footprint == nil ? 0 : InstantOptimisticEffectFootprint.currentVersion
              )),
              .int(footprint?.isGlobal == true ? 1 : 0),
              .text(receiptFingerprint),
              acceptanceFingerprint.map(SQLiteBinding.text) ?? .null,
              mutation.serverTransactionID.map(SQLiteBinding.text) ?? .null,
              mutation.confirmationSource.map { .text($0.rawValue) } ?? .null,
              .text(planID),
              .text(mutation.id),
            ]
          )
          try execute(
            """
            DELETE FROM instant_server_apply_effect_entities
            WHERE plan_id = ? AND mutation_id = ?
            """,
            [.text(planID), .text(mutation.id)]
          )
          for entityID in (footprint?.entityIDs ?? []).sorted() {
            try execute(
              """
              INSERT INTO instant_server_apply_effect_entities (
                plan_id, mutation_id, entity_id, created_at_ms
              ) VALUES (?, ?, ?, ?)
              """,
              [
                .text(planID),
                .text(mutation.id),
                .text(entityID),
                .int(mutation.createdAt.milliseconds),
              ]
            )
          }
        }
      }
    }
  }

  /// Extends an already prepared server plan with local mutations that were
  /// durably appended while Runtime performed the long peel/replay work.
  ///
  /// This is deliberately narrower than a general revision merge. It accepts
  /// only one Runtime admission per store/outbox revision, no deletion or
  /// replacement of the preexisting queue, and only prepared pending rows
  /// strictly after the prior durable tail. Any other concurrent change makes
  /// the plan stale and falls back to a fresh authoritative plan.
  func extendServerApplyPlanWithAppendedLocalMutations(
    planID: String,
    after previousTail: InstantOutboxDeliveryPosition?,
    baselineOutboxRowCount: Int
  ) throws -> InstantServerApplyCatchUpLoad {
    try transaction {
      guard let control = try loadServerApplyPlanControlWithoutTransaction(id: planID),
        try serverApplyPlanRowsStillMatchWithoutTransaction(id: planID)
      else { return .stale }

      let currentStoreRevision = try loadMetadataRevisionWithoutTransaction(
        Self.storeRevisionKey
      )
      let currentAttributeRevision = try loadMetadataRevisionWithoutTransaction(
        Self.attributeRevisionKey
      )
      let currentOutboxRevision = try loadMetadataRevisionWithoutTransaction(
        Self.outboxRevisionKey
      )
      let currentQueryResultRevision = try loadMetadataRevisionWithoutTransaction(
        Self.queryResultRevisionKey
      )
      guard currentAttributeRevision == control.expectedAttributeRevision,
        currentQueryResultRevision == control.expectedQueryResultRevision,
        currentStoreRevision >= control.expectedStoreRevision,
        currentOutboxRevision >= control.expectedOutboxRevision
      else { return .stale }

      let currentOutboxRowCount = Int(try selectInt64(
        "SELECT COUNT(*) FROM instant_outbox"
      ))
      guard currentOutboxRowCount >= baselineOutboxRowCount else { return .stale }
      let appendedCount = currentOutboxRowCount - baselineOutboxRowCount
      let storeRevisionDelta = currentStoreRevision - control.expectedStoreRevision
      let outboxRevisionDelta = currentOutboxRevision - control.expectedOutboxRevision
      guard storeRevisionDelta == Int64(appendedCount),
        outboxRevisionDelta == Int64(appendedCount)
      else { return .stale }

      let positionPredicate: String
      let positionBindings: [SQLiteBinding]
      if let previousTail {
        positionPredicate =
          """
          (outbox.created_at_ms > ? OR (
            outbox.created_at_ms = ? AND outbox.mutation_id > ?
          ))
          """
        positionBindings = [
          .int(previousTail.createdAtMilliseconds),
          .int(previousTail.createdAtMilliseconds),
          .text(previousTail.mutationID),
        ]
      } else {
        positionPredicate = "1 = 1"
        positionBindings = []
      }
      let selectedCount = Int(try selectInt64(
        "SELECT COUNT(*) FROM instant_outbox AS outbox WHERE \(positionPredicate)",
        positionBindings
      ))
      guard selectedCount == appendedCount else { return .stale }

      let currentTail = try latestOutboxPositionWithoutTransaction()
      guard appendedCount > 0 else {
        guard currentTail == previousTail else { return .stale }
        return .ready(
          InstantServerApplyCatchUp(
            previousTail: previousTail,
            currentTail: currentTail,
            currentOutboxRowCount: currentOutboxRowCount,
            appendedBodyCount: 0,
            appendedBodyByteCount: 0
          )
        )
      }

      let invalidCount = try selectInt64(
        """
        SELECT COUNT(*)
        FROM instant_outbox AS outbox
        WHERE \(positionPredicate) AND (
          outbox.status != ?
          OR outbox.optimistic_overlay_active != 1
          OR outbox.optimistic_effect_metadata_version != ?
          OR outbox.optimistic_effect_receipt_fingerprint IS NULL
        )
        """,
        positionBindings + [
          .text(InstantMutationStatus.pending.rawValue),
          .int(Int64(InstantOptimisticEffectFootprint.currentVersion)),
        ]
      )
      guard invalidCount == 0 else { return .stale }

      let appendedBodyByteCount = Int(try selectInt64(
        """
        SELECT COALESCE(SUM(length(CAST(outbox.json AS BLOB))), 0)
        FROM instant_outbox AS outbox
        WHERE \(positionPredicate)
        """,
        positionBindings
      ))
      try execute(
        """
        INSERT INTO instant_server_apply_rows (
          plan_id, mutation_id, created_at_ms, expected_mutation_revision,
          expected_status, expected_confirmation_proven, expected_overlay_active,
          expected_effect_metadata_version, expected_effect_is_global,
          expected_effect_receipt_fingerprint,
          expected_delivery_started,
          expected_delivery_claim_payload_fingerprint,
          expected_delivery_claimant_id,
          expected_server_acceptance_payload_fingerprint,
          expected_body_bytes, is_component_body, requires_body,
          is_catch_up, prune_at_watermark, confirm_at_apply, original_json,
          staged_delete, staged
        )
        SELECT ?, outbox.mutation_id, outbox.created_at_ms,
               outbox.mutation_revision, outbox.status,
               COALESCE(outbox.confirmation_proven, 0),
               outbox.optimistic_overlay_active,
               outbox.optimistic_effect_metadata_version,
               outbox.optimistic_effect_is_global,
               outbox.optimistic_effect_receipt_fingerprint,
               outbox.delivery_started,
               outbox.delivery_claim_payload_fingerprint,
               outbox.delivery_claimant_id,
               outbox.server_acceptance_payload_fingerprint,
               MAX(
                 COALESCE(outbox.encoded_body_bytes, 0),
                 length(CAST(outbox.json AS BLOB))
               ),
               1, 1, 1, 0, 0, outbox.json, 0, 0
        FROM instant_outbox AS outbox
        WHERE \(positionPredicate)
        ORDER BY outbox.created_at_ms, outbox.mutation_id
        """,
        [.text(planID)] + positionBindings
      )
      guard sqlite3_changes(connection.raw) == appendedCount else {
        throw persistenceError(
          operation: "extend bounded server apply",
          message:
            "The appended outbox tail did not copy atomically into server-apply staging."
        )
      }
      try execute(
        """
        UPDATE instant_server_apply_plans
        SET expected_store_revision = ?, expected_outbox_revision = ?
        WHERE plan_id = ?
          AND expected_store_revision = ?
          AND expected_outbox_revision = ?
        """,
        [
          .int(currentStoreRevision),
          .int(currentOutboxRevision),
          .text(planID),
          .int(control.expectedStoreRevision),
          .int(control.expectedOutboxRevision),
        ]
      )
      guard sqlite3_changes(connection.raw) == 1 else {
        throw persistenceError(
          operation: "extend bounded server apply",
          message: "The server-apply revision boundary changed during tail staging."
        )
      }
      return .ready(
        InstantServerApplyCatchUp(
          previousTail: previousTail,
          currentTail: currentTail,
          currentOutboxRowCount: currentOutboxRowCount,
          appendedBodyCount: appendedCount,
          appendedBodyByteCount: appendedBodyByteCount
        )
      )
    }
  }

  func commitServerApplyPlan(
    planID: String,
    changedEntityTriples: [String: [InstantTriple]],
    mergingAttributes attributes: [InstantAttribute],
    queryResults: [InstantPersistedLiveQueryResult],
    storeChanged: Bool,
    metadataKey: String,
    metadataValue: String,
    metadataUpdatedAt: InstantTimestamp
  ) throws -> InstantServerApplyCommit? {
    serverApplyMetrics.commitAttemptCount += 1
    let commit: InstantServerApplyCommit? = try transaction {
      guard let plan = try loadServerApplyPlanControlWithoutTransaction(id: planID),
        try loadMetadataRevisionWithoutTransaction(Self.storeRevisionKey)
          == plan.expectedStoreRevision,
        try loadMetadataRevisionWithoutTransaction(Self.attributeRevisionKey)
          == plan.expectedAttributeRevision,
        try loadMetadataRevisionWithoutTransaction(Self.outboxRevisionKey)
          == plan.expectedOutboxRevision,
        try loadMetadataRevisionWithoutTransaction(Self.queryResultRevisionKey)
          == plan.expectedQueryResultRevision,
        try serverApplyPlanRowsStillMatchWithoutTransaction(id: planID),
        try serverApplyPlanClosureStillMatchesWithoutTransaction(id: planID),
        try selectInt64(
          """
          SELECT COUNT(*) FROM instant_server_apply_rows
          WHERE plan_id = ? AND requires_body = 1 AND staged = 0
          """,
          [.text(planID)]
        ) == 0
      else { return nil }

      let didChangeOutbox = try selectInt64(
        """
        SELECT EXISTS(
          SELECT 1
          FROM instant_server_apply_rows AS planned
          LEFT JOIN instant_outbox AS outbox
            ON outbox.mutation_id = planned.mutation_id
          WHERE planned.plan_id = ? AND planned.staged = 1
            AND (
              planned.staged_delete = 1
              OR outbox.mutation_id IS NULL
              OR planned.staged_json != outbox.json
              OR planned.staged_effect_receipt_fingerprint
                IS NOT outbox.optimistic_effect_receipt_fingerprint
              OR planned.staged_server_acceptance_payload_fingerprint
                IS NOT outbox.server_acceptance_payload_fingerprint
            )
          LIMIT 1
        )
        """,
        [.text(planID)]
      ) != 0
      let didChangeStore = storeChanged && !changedEntityTriples.isEmpty
      let didChangeAttributes = !attributes.isEmpty
      let didChangeQueryResults = !queryResults.isEmpty

      if didChangeStore {
        for entityID in changedEntityTriples.keys.sorted() {
          let previousTriples: [InstantTriple] = try selectJSON(
            "SELECT json FROM instant_triples WHERE entity_id = ? ORDER BY attribute_id, value_json",
            [.text(entityID)]
          )
          try saveTripleDiffWithoutTransaction(
            from: previousTriples,
            to: changedEntityTriples[entityID, default: []]
          )
        }
      }
      if didChangeAttributes {
        try invalidateDeclaredRelationStorageMarkerIfNeeded(
          forIncomingAttributes: attributes
        )
        for attribute in attributes {
          try execute(
            "INSERT OR REPLACE INTO instant_attributes (id, json) VALUES (?, ?)",
            [.text(attribute.id), .text(try encode(attribute))]
          )
        }
      }

      if didChangeOutbox {
        try execute(
          """
          DELETE FROM instant_outbox
          WHERE mutation_id IN (
            SELECT mutation_id FROM instant_server_apply_rows
            WHERE plan_id = ? AND staged = 1 AND staged_delete = 1
          )
          """,
          [.text(planID)]
        )
        try execute(
          """
          UPDATE instant_outbox AS outbox
          SET status = (
                SELECT staged_status FROM instant_server_apply_rows
                WHERE plan_id = ? AND mutation_id = outbox.mutation_id
              ),
              delivery_state = (
                SELECT staged_delivery_state FROM instant_server_apply_rows
                WHERE plan_id = ? AND mutation_id = outbox.mutation_id
              ),
              delivery_metadata_version = ?,
              transport_step_count = (
                SELECT staged_transport_step_count FROM instant_server_apply_rows
                WHERE plan_id = ? AND mutation_id = outbox.mutation_id
              ),
              encoded_body_bytes = length(CAST((
                SELECT staged_json FROM instant_server_apply_rows
                WHERE plan_id = ? AND mutation_id = outbox.mutation_id
              ) AS BLOB)),
              lifecycle_json = (
                SELECT staged_lifecycle_json FROM instant_server_apply_rows
                WHERE plan_id = ? AND mutation_id = outbox.mutation_id
              ),
              failure_message = (
                SELECT staged_failure_message FROM instant_server_apply_rows
                WHERE plan_id = ? AND mutation_id = outbox.mutation_id
              ),
              confirmation_proven = (
                SELECT staged_confirmation_proven FROM instant_server_apply_rows
                WHERE plan_id = ? AND mutation_id = outbox.mutation_id
              ),
              optimistic_overlay_active = (
                SELECT staged_overlay_active FROM instant_server_apply_rows
                WHERE plan_id = ? AND mutation_id = outbox.mutation_id
              ),
              mutation_revision = mutation_revision + 1,
              optimistic_effect_metadata_version = (
                SELECT staged_effect_metadata_version FROM instant_server_apply_rows
                WHERE plan_id = ? AND mutation_id = outbox.mutation_id
              ),
              optimistic_effect_is_global = (
                SELECT staged_effect_is_global FROM instant_server_apply_rows
                WHERE plan_id = ? AND mutation_id = outbox.mutation_id
              ),
              optimistic_effect_receipt_fingerprint = (
                SELECT staged_effect_receipt_fingerprint FROM instant_server_apply_rows
                WHERE plan_id = ? AND mutation_id = outbox.mutation_id
              ),
              server_acceptance_payload_fingerprint = (
                SELECT staged_server_acceptance_payload_fingerprint
                FROM instant_server_apply_rows
                WHERE plan_id = ? AND mutation_id = outbox.mutation_id
              ),
              server_transaction_id = (
                SELECT staged_server_transaction_id FROM instant_server_apply_rows
                WHERE plan_id = ? AND mutation_id = outbox.mutation_id
              ),
              confirmation_source = (
                SELECT staged_confirmation_source FROM instant_server_apply_rows
                WHERE plan_id = ? AND mutation_id = outbox.mutation_id
              ),
              json = (
                SELECT staged_json FROM instant_server_apply_rows
                WHERE plan_id = ? AND mutation_id = outbox.mutation_id
              )
          WHERE mutation_id IN (
            SELECT mutation_id FROM instant_server_apply_rows
            WHERE plan_id = ? AND staged = 1 AND staged_delete = 0
              AND (
                staged_json != outbox.json
                OR staged_effect_receipt_fingerprint
                  IS NOT outbox.optimistic_effect_receipt_fingerprint
                OR staged_server_acceptance_payload_fingerprint
                  IS NOT outbox.server_acceptance_payload_fingerprint
              )
          )
          """,
          Array(repeating: SQLiteBinding.text(planID), count: 2)
            + [.int(Int64(InstantOutboxDeliveryMetadata.currentVersion))]
            + Array(repeating: SQLiteBinding.text(planID), count: 14)
        )
        try execute(
          """
          DELETE FROM instant_outbox_effect_entities
          WHERE mutation_id IN (
            SELECT mutation_id FROM instant_server_apply_rows
            WHERE plan_id = ? AND staged = 1 AND staged_delete = 0
          )
          """,
          [.text(planID)]
        )
        try execute(
          """
          INSERT INTO instant_outbox_effect_entities (mutation_id, entity_id, created_at_ms)
          SELECT mutation_id, entity_id, created_at_ms
          FROM instant_server_apply_effect_entities
          WHERE plan_id = ?
          """,
          [.text(planID)]
        )
      }

      for result in queryResults {
        try saveLiveQueryResultWithoutTransaction(result)
      }
      try saveMetadataValueWithoutTransaction(
        metadataValue,
        key: metadataKey,
        updatedAt: metadataUpdatedAt
      )
      if didChangeStore {
        _ = try bumpMetadataRevisionWithoutTransaction(Self.storeRevisionKey)
      }
      if didChangeAttributes {
        _ = try bumpMetadataRevisionWithoutTransaction(Self.attributeRevisionKey)
      }
      if didChangeOutbox {
        _ = try bumpMetadataRevisionWithoutTransaction(Self.outboxRevisionKey)
      }
      if didChangeQueryResults {
        _ = try bumpMetadataRevisionWithoutTransaction(Self.queryResultRevisionKey)
      }
      return InstantServerApplyCommit(
        pendingMutationCount: Int(try selectInt64(
          "SELECT COUNT(*) FROM instant_outbox WHERE status = ?",
          [.text(InstantMutationStatus.pending.rawValue)]
        )),
        expectedStoreRevision: plan.expectedStoreRevision,
        expectedAttributeRevision: plan.expectedAttributeRevision,
        expectedOutboxRevision: plan.expectedOutboxRevision,
        expectedQueryResultRevision: plan.expectedQueryResultRevision,
        didChangeStore: didChangeStore,
        didChangeAttributes: didChangeAttributes,
        didChangeOutbox: didChangeOutbox,
        didChangeQueryResults: didChangeQueryResults
      )
    }
    if commit == nil {
      serverApplyMetrics.staleCommitCount += 1
    } else if let commit {
      advanceCachedRevisionDomains(
        expectedStoreRevision: commit.expectedStoreRevision,
        expectedAttributeRevision: commit.expectedAttributeRevision,
        expectedOutboxRevision: commit.expectedOutboxRevision,
        expectedQueryResultRevision: commit.expectedQueryResultRevision,
        changedEntityTriples: changedEntityTriples,
        mergingAttributes: attributes,
        storeChanged: commit.didChangeStore,
        attributesChanged: commit.didChangeAttributes,
        outboxChanged: commit.didChangeOutbox,
        queryResultsChanged: commit.didChangeQueryResults
      )
    }
    return commit
  }

  func loadServerApplyResidentPatchPage(
    planID: String,
    after position: InstantOutboxDeliveryPosition?
  ) throws -> InstantServerApplyResidentPatchPage {
    var sql =
      """
      SELECT mutation_id, created_at_ms, staged_delete,
             CASE WHEN staged_delete = 1 THEN 0
                  ELSE length(CAST(staged_lifecycle_json AS BLOB)) END
      FROM instant_server_apply_rows
      WHERE plan_id = ? AND staged = 1
      """
    var bindings: [SQLiteBinding] = [.text(planID)]
    if let position {
      sql +=
        """
         AND (created_at_ms > ? OR (created_at_ms = ? AND mutation_id > ?))
        """
      bindings += [
        .int(position.createdAtMilliseconds),
        .int(position.createdAtMilliseconds),
        .text(position.mutationID),
      ]
    }
    sql += " ORDER BY created_at_ms, mutation_id LIMIT 51"
    var statement: OpaquePointer?
    try prepare(sql, statement: &statement)
    defer { sqlite3_finalize(statement) }
    try bind(bindings, to: statement)
    var candidates: [InstantServerApplyResidentPatchCandidate] = []
    var totalLifecycleByteCount = 0
    while sqlite3_step(statement) == SQLITE_ROW,
      candidates.count < InstantAutomaticOutboxClaimLimits.maximumBodyDecodeCount
    {
      guard let mutationIDBytes = sqlite3_column_text(statement, 0) else { continue }
      let mutationID = String(cString: mutationIDBytes)
      let isDeletion = sqlite3_column_int64(statement, 2) != 0
      guard isDeletion || sqlite3_column_type(statement, 3) != SQLITE_NULL else {
        throw persistenceError(
          operation: "load bounded server-apply resident patch",
          message:
            "Mutation '\(mutationID)' has no compact lifecycle body after its durable server apply."
        )
      }
      let lifecycleByteCount = isDeletion ? 0 : Int(sqlite3_column_int64(statement, 3))
      guard lifecycleByteCount <= InstantAutomaticOutboxClaimLimits.maximumEncodedBodyBytes
      else {
        throw persistenceError(
          operation: "load bounded server-apply resident patch",
          message:
            "Mutation '\(mutationID)' has a \(lifecycleByteCount)-byte compact lifecycle body, beyond the 8 MiB resident-patch limit."
        )
      }
      guard
        lifecycleByteCount
          <= InstantAutomaticOutboxClaimLimits.maximumEncodedBodyBytes
            - totalLifecycleByteCount
      else { break }
      candidates.append(
        InstantServerApplyResidentPatchCandidate(
          mutationID: mutationID,
          position: InstantOutboxDeliveryPosition(
            createdAtMilliseconds: sqlite3_column_int64(statement, 1),
            mutationID: mutationID
          ),
          isDeletion: isDeletion,
          actualLifecycleByteCount: lifecycleByteCount
        )
      )
      totalLifecycleByteCount += lifecycleByteCount
    }

    var removedMutationIDs: [String] = []
    var replacementMutations: [PendingMutation] = []
    for candidate in candidates {
      if candidate.isDeletion {
        removedMutationIDs.append(candidate.mutationID)
        continue
      }
      let lifecycleJSON: String? = try selectScalar(
        """
        SELECT staged_lifecycle_json
        FROM instant_server_apply_rows
        WHERE plan_id = ? AND mutation_id = ? AND staged_delete = 0
        LIMIT 1
        """,
        [.text(planID), .text(candidate.mutationID)]
      )
      guard let lifecycleJSON,
        lifecycleJSON.utf8.count == candidate.actualLifecycleByteCount
      else {
        throw persistenceError(
          operation: "load bounded server-apply resident patch",
          message:
            "Mutation '\(candidate.mutationID)' changed while loading its compact lifecycle body."
        )
      }
      let mutation: PendingMutation = try decodeOutboxBody(lifecycleJSON)
      guard mutation.id == candidate.mutationID,
        mutation.createdAt.milliseconds == candidate.position.createdAtMilliseconds
      else {
        throw persistenceError(
          operation: "load bounded server-apply resident patch",
          message:
            "Compact lifecycle body '\(mutation.id)' did not match planned row '\(candidate.mutationID)'."
        )
      }
      replacementMutations.append(mutation)
    }
    serverApplyMetrics.recordResidentPatchPage(
      rowCount: candidates.count,
      lifecycleByteCount: totalLifecycleByteCount
    )
    return InstantServerApplyResidentPatchPage(
      removedMutationIDs: removedMutationIDs,
      replacementMutations: replacementMutations,
      nextPosition: candidates.last?.position
    )
  }

  func finishServerApplyPlan(id: String) throws {
    try transaction {
      try deleteServerApplyPlanWithoutTransaction(id: id)
    }
  }

  private func firstUnknownActiveServerApplyMutationIDWithoutTransaction() throws -> String? {
    try selectScalar(
      """
      SELECT mutation_id
      FROM instant_outbox INDEXED BY instant_outbox_effect_normalization_idx
      WHERE optimistic_overlay_active = 1
        AND (
          optimistic_effect_metadata_version != ?
          OR optimistic_effect_receipt_fingerprint IS NULL
        )
      ORDER BY created_at_ms, mutation_id
      LIMIT 1
      """,
      [
        .int(Int64(InstantOptimisticEffectFootprint.currentVersion)),
      ]
    )
  }

  private func synchronizationBlockerWithoutTransaction() throws
    -> InstantSynchronizationBlocker?
  {
    let predicate =
      "optimistic_overlay_active = 1 AND optimistic_effect_receipt_fingerprint IS NULL"
    guard let firstMutationID = try selectScalar(
      """
      SELECT mutation_id
      FROM instant_outbox INDEXED BY instant_outbox_synchronization_blocker_idx
      WHERE \(predicate)
      ORDER BY created_at_ms, mutation_id
      LIMIT 1
      """
    ) else { return nil }
    let blockedMutationCount = Int(try selectInt64(
      """
      SELECT COUNT(*)
      FROM instant_outbox INDEXED BY instant_outbox_synchronization_blocker_idx
      WHERE \(predicate)
      """
    ))
    return InstantSynchronizationBlocker(
      reason: .unknownOptimisticEffectReceipt,
      firstMutationID: firstMutationID,
      blockedMutationCount: blockedMutationCount
    )
  }

  private func loadServerApplyPlanControlWithoutTransaction(
    id: String
  ) throws -> InstantServerApplyPlanControl? {
    var statement: OpaquePointer?
    try prepare(
      """
      SELECT expected_store_revision, expected_attribute_revision,
             expected_outbox_revision, expected_query_result_revision,
             processed_transaction_id, processed_transaction_number,
             server_has_operations, root_is_global, confirming_mutation_id,
             confirming_claimant_id
      FROM instant_server_apply_plans
      WHERE plan_id = ?
      LIMIT 1
      """,
      statement: &statement
    )
    defer { sqlite3_finalize(statement) }
    try bind([.text(id)], to: statement)
    guard sqlite3_step(statement) == SQLITE_ROW,
      let processedTransactionIDBytes = sqlite3_column_text(statement, 4)
    else { return nil }
    return InstantServerApplyPlanControl(
      expectedStoreRevision: sqlite3_column_int64(statement, 0),
      expectedAttributeRevision: sqlite3_column_int64(statement, 1),
      expectedOutboxRevision: sqlite3_column_int64(statement, 2),
      expectedQueryResultRevision: sqlite3_column_int64(statement, 3),
      processedTransactionID: String(cString: processedTransactionIDBytes),
      processedTransactionNumber: sqlite3_column_type(statement, 5) == SQLITE_NULL
        ? nil
        : sqlite3_column_int64(statement, 5),
      hasServerOperations: sqlite3_column_int64(statement, 6) != 0,
      rootIsGlobal: sqlite3_column_int64(statement, 7) != 0,
      confirmingMutationID: sqlite3_column_text(statement, 8).map(String.init(cString:)),
      confirmingClaimantID: sqlite3_column_text(statement, 9).map(String.init(cString:))
    )
  }

  @discardableResult
  private func insertServerApplyRowsWithoutTransaction(
    planID: String,
    componentBody: Bool,
    requiresBody: Bool,
    selectionSQL: String,
    bindings selectionBindings: [SQLiteBinding]
  ) throws -> Int {
    try execute(
      """
      INSERT OR IGNORE INTO instant_server_apply_rows (
        plan_id, mutation_id, created_at_ms, expected_mutation_revision,
        expected_status, expected_confirmation_proven, expected_overlay_active,
        expected_effect_metadata_version, expected_effect_is_global,
        expected_effect_receipt_fingerprint,
        expected_delivery_started,
        expected_delivery_claim_payload_fingerprint,
        expected_delivery_claimant_id,
        expected_server_acceptance_payload_fingerprint,
        expected_body_bytes, is_component_body, requires_body,
        is_catch_up, prune_at_watermark, confirm_at_apply, staged_delete, staged
      )
      SELECT ?, outbox.mutation_id, outbox.created_at_ms, outbox.mutation_revision,
             outbox.status, COALESCE(outbox.confirmation_proven, 0),
             outbox.optimistic_overlay_active,
             outbox.optimistic_effect_metadata_version,
             outbox.optimistic_effect_is_global,
             outbox.optimistic_effect_receipt_fingerprint,
             outbox.delivery_started,
             outbox.delivery_claim_payload_fingerprint,
             outbox.delivery_claimant_id,
             outbox.server_acceptance_payload_fingerprint,
             MAX(
               COALESCE(outbox.encoded_body_bytes, 0),
               length(CAST(outbox.json AS BLOB))
             ),
             ?, ?, 0, 0, 0, 0, 0
      \(selectionSQL)
      """,
      [
        .text(planID),
        .int(componentBody ? 1 : 0),
        .int(requiresBody ? 1 : 0),
      ] + selectionBindings
    )
    return Int(try selectInt64("SELECT changes()"))
  }

  private func serverApplyWatermarkPredicate(
    _ control: InstantServerApplyPlanControl,
    alias: String
  ) -> (sql: String, bindings: [SQLiteBinding]) {
    let serverTransactionID = "\(alias).server_transaction_id"
    if let processedNumber = control.processedTransactionNumber {
      return (
        """
        (\(serverTransactionID) = ? OR (
          \(serverTransactionID) != ''
          AND \(serverTransactionID) NOT GLOB '*[^0-9]*'
          AND CAST(\(serverTransactionID) AS INTEGER) <= ?
        ))
        """,
        [.text(control.processedTransactionID), .int(processedNumber)]
      )
    }
    return ("\(serverTransactionID) = ?", [.text(control.processedTransactionID)])
  }

  private func populateServerApplyPlanRowsWithoutTransaction(id planID: String) throws {
    guard let control = try loadServerApplyPlanControlWithoutTransaction(id: planID) else {
      throw persistenceError(
        operation: "plan bounded server apply",
        message: "Server-apply plan '\(planID)' disappeared during indexed planning."
      )
    }
    let watermark = serverApplyWatermarkPredicate(control, alias: "outbox")
    if control.hasServerOperations {
      let hasActiveGlobal = try selectInt64(
        """
        SELECT EXISTS(
          SELECT 1
          FROM instant_outbox INDEXED BY instant_outbox_global_effect_order_idx
          WHERE optimistic_overlay_active = 1
            AND optimistic_effect_is_global = 1
            AND optimistic_effect_receipt_fingerprint IS NOT NULL
          LIMIT 1
        )
        """
      ) != 0
      if control.rootIsGlobal || hasActiveGlobal {
        try insertServerApplyRowsWithoutTransaction(
          planID: planID,
          componentBody: true,
          requiresBody: true,
          selectionSQL:
            """
            FROM instant_outbox AS outbox
            WHERE outbox.optimistic_overlay_active = 1
              AND outbox.optimistic_effect_receipt_fingerprint IS NOT NULL
            """,
          bindings: []
        )
      } else {
        try insertServerApplyRowsWithoutTransaction(
          planID: planID,
          componentBody: true,
          requiresBody: true,
          selectionSQL:
            """
            FROM instant_server_apply_roots AS roots
            JOIN instant_outbox_effect_entities AS effects
              INDEXED BY instant_outbox_effect_entities_lookup_idx
              ON effects.entity_id = roots.entity_id
            JOIN instant_outbox AS outbox
              ON outbox.mutation_id = effects.mutation_id
            WHERE roots.plan_id = ? AND outbox.optimistic_overlay_active = 1
              AND outbox.optimistic_effect_receipt_fingerprint IS NOT NULL
            """,
          bindings: [.text(planID)]
        )
        try insertServerApplyRowsWithoutTransaction(
          planID: planID,
          componentBody: true,
          requiresBody: true,
          selectionSQL:
            """
            FROM instant_outbox AS outbox INDEXED BY instant_outbox_server_apply_failed_idx
            WHERE outbox.status = 'failed' AND outbox.optimistic_overlay_active = 1
              AND outbox.optimistic_effect_receipt_fingerprint IS NOT NULL
            """,
          bindings: []
        )
        try insertServerApplyRowsWithoutTransaction(
          planID: planID,
          componentBody: true,
          requiresBody: true,
          selectionSQL:
            """
            FROM instant_outbox AS outbox INDEXED BY instant_outbox_server_apply_watermark_idx
            WHERE outbox.status = ? AND outbox.confirmation_proven = 1
              AND outbox.optimistic_overlay_active = 1
              AND outbox.optimistic_effect_receipt_fingerprint IS NOT NULL
              AND \(watermark.sql)
            """,
          bindings: [.text(InstantMutationStatus.confirmed.rawValue)] + watermark.bindings
        )
        if let confirmingMutationID = control.confirmingMutationID {
          try insertServerApplyRowsWithoutTransaction(
            planID: planID,
            componentBody: true,
            requiresBody: true,
            selectionSQL:
              """
              FROM instant_outbox AS outbox
              WHERE outbox.mutation_id = ? AND outbox.optimistic_overlay_active = 1
                AND outbox.optimistic_effect_receipt_fingerprint IS NOT NULL
              """,
            bindings: [.text(confirmingMutationID)]
          )
        }

        while true {
          let inserted = try insertServerApplyRowsWithoutTransaction(
            planID: planID,
            componentBody: true,
            requiresBody: true,
            selectionSQL:
              """
              FROM instant_server_apply_rows AS planned
              JOIN instant_outbox_effect_entities AS source_effect
                ON source_effect.mutation_id = planned.mutation_id
              JOIN instant_outbox_effect_entities AS connected_effect
                INDEXED BY instant_outbox_effect_entities_lookup_idx
                ON connected_effect.entity_id = source_effect.entity_id
              JOIN instant_outbox AS outbox
                ON outbox.mutation_id = connected_effect.mutation_id
              WHERE planned.plan_id = ? AND planned.is_component_body = 1
                AND outbox.optimistic_overlay_active = 1
                AND outbox.optimistic_effect_receipt_fingerprint IS NOT NULL
              """,
            bindings: [.text(planID)]
          )
          if inserted == 0 { break }
        }
      }
    }

    try insertServerApplyRowsWithoutTransaction(
      planID: planID,
      componentBody: false,
      requiresBody: false,
      selectionSQL:
        """
        FROM instant_outbox AS outbox INDEXED BY instant_outbox_server_apply_watermark_idx
        WHERE outbox.status = ? AND outbox.confirmation_proven = 1
          AND \(watermark.sql)
        """,
      bindings: [.text(InstantMutationStatus.confirmed.rawValue)] + watermark.bindings
    )
    try execute(
      """
      UPDATE instant_server_apply_rows
      SET prune_at_watermark = 1
      WHERE plan_id = ? AND mutation_id IN (
        SELECT outbox.mutation_id
        FROM instant_outbox AS outbox INDEXED BY instant_outbox_server_apply_watermark_idx
        WHERE outbox.status = ? AND outbox.confirmation_proven = 1
          AND \(watermark.sql)
      )
      """,
      [
        .text(planID),
        .text(InstantMutationStatus.confirmed.rawValue),
      ] + watermark.bindings
    )
    try execute(
      """
      UPDATE instant_server_apply_rows
      SET staged = 1, staged_delete = 1
      WHERE plan_id = ? AND prune_at_watermark = 1 AND requires_body = 0
      """,
      [.text(planID)]
    )

    if let confirmingMutationID = control.confirmingMutationID {
      try insertServerApplyRowsWithoutTransaction(
        planID: planID,
        componentBody: false,
        requiresBody: true,
        selectionSQL:
          """
          FROM instant_outbox AS outbox
          WHERE outbox.mutation_id = ?
            AND outbox.optimistic_effect_receipt_fingerprint IS NOT NULL
          """,
        bindings: [.text(confirmingMutationID)]
      )
      try execute(
        """
        UPDATE instant_server_apply_rows
        SET confirm_at_apply = 1, requires_body = 1, staged = 0, staged_delete = 0
        WHERE plan_id = ? AND mutation_id = ? AND prune_at_watermark = 0
        """,
        [.text(planID), .text(confirmingMutationID)]
      )
    }
  }

  private func loadServerApplyBodyPageWithoutTransaction(
    planID: String,
    direction: InstantServerApplyBodyDirection,
    after position: InstantOutboxDeliveryPosition?
  ) throws -> InstantServerApplyBodyPage {
    guard try serverApplyPlanRowsStillMatchWithoutTransaction(id: planID) else {
      return InstantServerApplyBodyPage(
        isStale: true,
        entries: [],
        nextPosition: nil,
        decodedBodyByteCount: 0
      )
    }
    let sourceJSON: String
    let sourceJoin: String
    switch direction {
    case .reverse:
      sourceJSON = "outbox.json"
      sourceJoin =
        "JOIN instant_outbox AS outbox ON outbox.mutation_id = planned.mutation_id"
    case .forward:
      sourceJSON = "planned.original_json"
      sourceJoin = ""
    }
    var sql =
      """
      SELECT planned.mutation_id, planned.created_at_ms,
             length(CAST(\(sourceJSON) AS BLOB)),
             planned.is_component_body, planned.prune_at_watermark,
             planned.confirm_at_apply
      FROM instant_server_apply_rows AS planned
      \(sourceJoin)
      WHERE planned.plan_id = ? AND planned.requires_body = 1
      """
    var bindings: [SQLiteBinding] = [.text(planID)]
    if let position {
      switch direction {
      case .reverse:
        sql +=
          """
           AND (
             planned.created_at_ms < ?
             OR (planned.created_at_ms = ? AND planned.mutation_id < ?)
           )
          """
      case .forward:
        sql +=
          """
           AND (
             planned.created_at_ms > ?
             OR (planned.created_at_ms = ? AND planned.mutation_id > ?)
           )
          """
      }
      bindings += [
        .int(position.createdAtMilliseconds),
        .int(position.createdAtMilliseconds),
        .text(position.mutationID),
      ]
    }
    sql += direction == .reverse
      ? " ORDER BY planned.created_at_ms DESC, planned.mutation_id DESC LIMIT 51"
      : " ORDER BY planned.created_at_ms, planned.mutation_id LIMIT 51"

    var statement: OpaquePointer?
    try prepare(sql, statement: &statement)
    defer { sqlite3_finalize(statement) }
    try bind(bindings, to: statement)
    var candidates: [InstantServerApplyBodyCandidate] = []
    var componentFlags: [String: Bool] = [:]
    var totalByteCount = 0
    var oversizedMutationID: String?
    while sqlite3_step(statement) == SQLITE_ROW,
      candidates.count < InstantAutomaticOutboxClaimLimits.maximumBodyDecodeCount
    {
      guard let mutationIDBytes = sqlite3_column_text(statement, 0) else { continue }
      let mutationID = String(cString: mutationIDBytes)
      let byteCount = Int(sqlite3_column_int64(statement, 2))
      guard byteCount <= InstantAutomaticOutboxClaimLimits.maximumEncodedBodyBytes else {
        oversizedMutationID = mutationID
        break
      }
      guard byteCount <= InstantAutomaticOutboxClaimLimits.maximumEncodedBodyBytes - totalByteCount
      else { break }
      let candidate = InstantServerApplyBodyCandidate(
        mutationID: mutationID,
        position: InstantOutboxDeliveryPosition(
          createdAtMilliseconds: sqlite3_column_int64(statement, 1),
          mutationID: mutationID
        ),
        actualBodyByteCount: byteCount,
        shouldPruneAtWatermark: sqlite3_column_int64(statement, 4) != 0,
        shouldConfirm: sqlite3_column_int64(statement, 5) != 0
      )
      candidates.append(candidate)
      componentFlags[mutationID] = sqlite3_column_int64(statement, 3) != 0
      totalByteCount += byteCount
    }
    sqlite3_finalize(statement)
    statement = nil
    if let oversizedMutationID {
      let blocker = try revokeMismatchedPreparedReceiptWithoutTransaction(
        mutationID: oversizedMutationID
      )
      return InstantServerApplyBodyPage(
        isStale: false,
        entries: [],
        nextPosition: nil,
        decodedBodyByteCount: totalByteCount,
        synchronizationBlocker: blocker
      )
    }

    var entries: [InstantServerApplyBodyEntry] = []
    entries.reserveCapacity(candidates.count)
    for candidate in candidates {
      let json: String?
      switch direction {
      case .reverse:
        json = try selectScalar(
          "SELECT json FROM instant_outbox WHERE mutation_id = ? LIMIT 1",
          [.text(candidate.mutationID)]
        )
      case .forward:
        json = try selectScalar(
          """
          SELECT original_json FROM instant_server_apply_rows
          WHERE plan_id = ? AND mutation_id = ? LIMIT 1
          """,
          [.text(planID), .text(candidate.mutationID)]
        )
      }
      guard let json, json.utf8.count == candidate.actualBodyByteCount else {
        return InstantServerApplyBodyPage(
          isStale: true,
          entries: [],
          nextPosition: nil,
          decodedBodyByteCount: 0
        )
      }
      let mutation: PendingMutation
      do {
        mutation = try decodeOutboxBody(json)
      } catch {
        let blocker = try revokeMismatchedPreparedReceiptWithoutTransaction(
          mutationID: candidate.mutationID
        )
        return InstantServerApplyBodyPage(
          isStale: false,
          entries: [],
          nextPosition: nil,
          decodedBodyByteCount: totalByteCount,
          synchronizationBlocker: blocker
        )
      }
      decodedOutboxBodyCount += 1
      decodedOutboxBodyByteCount += candidate.actualBodyByteCount
      guard mutation.id == candidate.mutationID,
        mutation.createdAt.milliseconds == candidate.position.createdAtMilliseconds
      else {
        let blocker = try revokeMismatchedPreparedReceiptWithoutTransaction(
          mutationID: candidate.mutationID
        )
        return InstantServerApplyBodyPage(
          isStale: false,
          entries: [],
          nextPosition: nil,
          decodedBodyByteCount: totalByteCount,
          synchronizationBlocker: blocker
        )
      }
      if !(try hasStoredPreparedOptimisticEffectReceiptWithoutTransaction(mutation)) {
        let blocker = try revokeMismatchedPreparedReceiptWithoutTransaction(
          mutationID: candidate.mutationID
        )
        return InstantServerApplyBodyPage(
          isStale: false,
          entries: [],
          nextPosition: nil,
          decodedBodyByteCount: totalByteCount,
          synchronizationBlocker: blocker
        )
      }
      if direction == .reverse {
        try execute(
          """
          UPDATE instant_server_apply_rows
          SET original_json = ?
          WHERE plan_id = ? AND mutation_id = ? AND original_json IS NULL
          """,
          [.text(json), .text(planID), .text(candidate.mutationID)]
        )
      }
      entries.append(
        InstantServerApplyBodyEntry(
          mutation: mutation,
          isComponentBody: componentFlags[candidate.mutationID] == true,
          shouldPruneAtWatermark: candidate.shouldPruneAtWatermark,
          shouldConfirm: candidate.shouldConfirm
        )
      )
    }
    return InstantServerApplyBodyPage(
      isStale: false,
      entries: entries,
      nextPosition: candidates.last?.position,
      decodedBodyByteCount: totalByteCount
    )
  }

  /// Converts a decoded body/receipt mismatch into the same durable authority
  /// boundary used for migrated unknown rows. The body and active local owner
  /// remain intact; only caller-unsafe indexes, claims, and proof markers are
  /// revoked. The enclosing SQLite transaction commits this demotion before
  /// `loadServerApplyBodyPage` throws the structured blocker to Runtime.
  private func revokeMismatchedPreparedReceiptWithoutTransaction(
    mutationID: String
  ) throws -> InstantSynchronizationBlocker {
    try execute(
      """
      UPDATE instant_outbox
      SET delivery_claim_state = ?,
          delivery_claim_token = NULL,
          delivery_claimant_id = NULL,
          delivery_claim_deadline_ms = NULL,
          delivery_claim_projected_body_bytes = NULL,
          delivery_claim_payload_fingerprint = NULL,
          server_acceptance_payload_fingerprint = NULL,
          confirmation_proven = 0,
          delivery_state = ?,
          optimistic_overlay_active = 1,
          optimistic_effect_metadata_version = 0,
          optimistic_effect_is_global = 0,
          optimistic_effect_receipt_fingerprint = NULL,
          mutation_revision = mutation_revision + 1
      WHERE mutation_id = ?
      """,
      [
        .text(InstantOutboxDeliveryClaimState.ready.rawValue),
        .text(InstantOutboxDeliveryState.invalid.rawValue),
        .text(mutationID),
      ]
    )
    try execute(
      "DELETE FROM instant_outbox_effect_entities WHERE mutation_id = ?",
      [.text(mutationID)]
    )
    try execute(
      "DELETE FROM instant_outbox_write_keys WHERE mutation_id = ?",
      [.text(mutationID)]
    )
    _ = try bumpMetadataRevisionWithoutTransaction(Self.outboxRevisionKey)
    return try synchronizationBlockerWithoutTransaction()
      ?? InstantSynchronizationBlocker(
        reason: .unknownOptimisticEffectReceipt,
        firstMutationID: mutationID,
        blockedMutationCount: 1
      )
  }

  private func serverApplyPlanRowsStillMatchWithoutTransaction(id planID: String) throws -> Bool {
    try selectInt64(
      """
      SELECT COUNT(*)
      FROM instant_server_apply_rows AS planned
      LEFT JOIN instant_outbox AS outbox
        ON outbox.mutation_id = planned.mutation_id
      WHERE planned.plan_id = ? AND (
        outbox.mutation_id IS NULL
        OR outbox.created_at_ms != planned.created_at_ms
        OR outbox.mutation_revision != planned.expected_mutation_revision
        OR outbox.status != planned.expected_status
        OR COALESCE(outbox.confirmation_proven, 0)
          != planned.expected_confirmation_proven
        OR outbox.optimistic_overlay_active != planned.expected_overlay_active
        OR outbox.optimistic_effect_metadata_version
          != planned.expected_effect_metadata_version
        OR outbox.optimistic_effect_is_global != planned.expected_effect_is_global
        OR outbox.optimistic_effect_receipt_fingerprint
          IS NOT planned.expected_effect_receipt_fingerprint
        OR outbox.delivery_started != planned.expected_delivery_started
        OR outbox.delivery_claim_payload_fingerprint
          IS NOT planned.expected_delivery_claim_payload_fingerprint
        OR outbox.delivery_claimant_id
          IS NOT planned.expected_delivery_claimant_id
        OR outbox.server_acceptance_payload_fingerprint
          IS NOT planned.expected_server_acceptance_payload_fingerprint
      )
      """,
      [.text(planID)]
    ) == 0
  }

  private func serverApplyPlanClosureStillMatchesWithoutTransaction(
    id planID: String
  ) throws -> Bool {
    guard try loadServerApplyPlanControlWithoutTransaction(id: planID) != nil else {
      return false
    }
    let validationID = "\(planID).closure-validation"
    try deleteServerApplyPlanWithoutTransaction(id: validationID)
    defer { try? deleteServerApplyPlanWithoutTransaction(id: validationID) }
    try execute(
      """
      INSERT INTO instant_server_apply_plans
      SELECT ?, expected_store_revision, expected_attribute_revision,
             expected_outbox_revision, expected_query_result_revision,
             processed_transaction_id, processed_transaction_number,
             server_has_operations, root_is_global, confirming_mutation_id,
             confirming_claimant_id
      FROM instant_server_apply_plans
      WHERE plan_id = ?
      """,
      [.text(validationID), .text(planID)]
    )
    try execute(
      """
      INSERT INTO instant_server_apply_roots (plan_id, entity_id)
      SELECT ?, entity_id
      FROM instant_server_apply_roots
      WHERE plan_id = ?
      """,
      [.text(validationID), .text(planID)]
    )
    try populateServerApplyPlanRowsWithoutTransaction(id: validationID)
    let originalMinusValidation = try selectInt64(
      """
      SELECT COUNT(*) FROM (
        SELECT mutation_id, is_component_body, requires_body,
               prune_at_watermark, confirm_at_apply
        FROM instant_server_apply_rows
        WHERE plan_id = ? AND is_catch_up = 0
        EXCEPT
        SELECT mutation_id, is_component_body, requires_body,
               prune_at_watermark, confirm_at_apply
        FROM instant_server_apply_rows WHERE plan_id = ?
      )
      """,
      [.text(planID), .text(validationID)]
    )
    let validationMinusOriginal = try selectInt64(
      """
      SELECT COUNT(*) FROM (
        SELECT mutation_id, is_component_body, requires_body,
               prune_at_watermark, confirm_at_apply
        FROM instant_server_apply_rows WHERE plan_id = ?
        EXCEPT
        SELECT mutation_id, is_component_body, requires_body,
               prune_at_watermark, confirm_at_apply
        FROM instant_server_apply_rows WHERE plan_id = ?
      )
      """,
      [.text(validationID), .text(planID)]
    )
    return originalMinusValidation == 0 && validationMinusOriginal == 0
  }

  private func deleteServerApplyPlanWithoutTransaction(id: String) throws {
    try execute(
      "DELETE FROM instant_server_apply_effect_entities WHERE plan_id = ?",
      [.text(id)]
    )
    try execute(
      "DELETE FROM instant_server_apply_rows WHERE plan_id = ?",
      [.text(id)]
    )
    try execute(
      "DELETE FROM instant_server_apply_roots WHERE plan_id = ?",
      [.text(id)]
    )
    try execute(
      "DELETE FROM instant_server_apply_plans WHERE plan_id = ?",
      [.text(id)]
    )
  }

  /// Persists one prepared terminal rejection with exact store, claim, status,
  /// component-closure, and per-row revision predicates. Only affected entity
  /// triples and component rows are rewritten.
  func commitClaimedTerminalFailure(
    targetID: String,
    claimToken: String,
    expectedStoreRevision: Int64,
    expectedAttributeRevision: Int64,
    expectedComponentRowRevisions: [String: Int64],
    expectedComponentIDs: Set<String>,
    failedMutation: PendingMutation,
    rebasedSuccessors: [PendingMutation],
    changedEntityTriples: [String: [InstantTriple]],
    metadataEntries: [InstantPersistenceMetadataEntry]
  ) throws -> InstantTerminalFailureCommit? {
    let result: InstantTerminalFailureCommit? = try transaction {
      guard
        try loadMetadataRevisionWithoutTransaction(Self.storeRevisionKey)
          == expectedStoreRevision,
        try loadMetadataRevisionWithoutTransaction(Self.attributeRevisionKey)
          == expectedAttributeRevision,
        let target = try loadTerminalFailureTargetControlWithoutTransaction(id: targetID)
      else { return nil }

      if target.status == .failed
        || (target.status == .confirmed && target.confirmationProven)
      {
        return InstantTerminalFailureCommit(
          failedMutation: nil,
          rebasedSuccessors: [],
          pendingMutationCount: Int(try selectInt64(
            "SELECT COUNT(*) FROM instant_outbox WHERE status = ?",
            [.text(InstantMutationStatus.pending.rawValue)]
          )),
          didChange: false
        )
      }
      guard target.status == .pending || target.status == .confirmed,
        !target.confirmationProven,
        target.deliveryState == .needsDelivery,
        target.claimState == .claimed,
        target.claimToken == claimToken
      else { return nil }

      let resolution = try resolveOptimisticEffectComponentRowsWithoutTransaction(
        target: target.effect
      )
      guard case let .ready(rows) = resolution,
        rows.ids == expectedComponentIDs,
        Set(expectedComponentRowRevisions.keys) == expectedComponentIDs,
        rows.all.allSatisfy({ row in
          expectedComponentRowRevisions[row.mutationID] == row.mutationRevision
        })
      else { return nil }

      let successorIDs = rows.successors.map(\.mutationID)
      guard failedMutation.id == targetID,
        failedMutation.createdAt.milliseconds == target.effect.position.createdAtMilliseconds,
        failedMutation.status == .failed,
        failedMutation.failure != nil,
        failedMutation.optimisticOverlayState == .removed,
        failedMutation.rollbackTransaction == nil,
        !failedMutation.provesServerAcceptance,
        rebasedSuccessors.map(\.id) == successorIDs
      else {
        throw persistenceError(
          operation: "commit terminal failure component",
          message: "The prepared terminal failure did not match its proven component."
        )
      }

      for entityID in changedEntityTriples.keys.sorted() {
        let previousTriples: [InstantTriple] = try selectJSON(
          "SELECT json FROM instant_triples WHERE entity_id = ? ORDER BY attribute_id, value_json",
          [.text(entityID)]
        )
        try saveTripleDiffWithoutTransaction(
          from: previousTriples,
          to: changedEntityTriples[entityID, default: []]
        )
      }
      try saveOutboxMutationWithoutTransaction(
        failedMutation,
        receiptWriteAuthority: .runtimePrepared
      )
      for successor in rebasedSuccessors {
        try saveOutboxMutationWithoutTransaction(
          successor,
          receiptWriteAuthority: .runtimePrepared
        )
      }
      try execute(
        """
        UPDATE instant_outbox
        SET delivery_claim_state = ?, delivery_claim_token = NULL,
            delivery_claimant_id = NULL, delivery_claim_deadline_ms = NULL,
            delivery_claim_projected_body_bytes = NULL,
            delivery_claim_payload_fingerprint = NULL
        WHERE mutation_id = ? AND delivery_claim_state = ?
          AND delivery_claim_token = ?
        """,
        [
          .text(InstantOutboxDeliveryClaimState.ready.rawValue),
          .text(targetID),
          .text(InstantOutboxDeliveryClaimState.claimed.rawValue),
          .text(claimToken),
        ]
      )
      guard sqlite3_changes(connection.raw) == 1 else {
        throw persistenceError(
          operation: "commit terminal failure component",
          message: "The exact durable delivery claim changed during terminal rejection."
        )
      }
      for entry in metadataEntries {
        try saveMetadataValueWithoutTransaction(
          entry.value,
          key: entry.key,
          updatedAt: entry.updatedAt
        )
      }
      _ = try bumpMetadataRevisionWithoutTransaction(Self.storeRevisionKey)
      _ = try bumpMetadataRevisionWithoutTransaction(Self.outboxRevisionKey)
      return InstantTerminalFailureCommit(
        failedMutation: failedMutation,
        rebasedSuccessors: rebasedSuccessors,
        pendingMutationCount: Int(try selectInt64(
          "SELECT COUNT(*) FROM instant_outbox WHERE status = ?",
          [.text(InstantMutationStatus.pending.rawValue)]
        )),
        didChange: true
      )
    }
    if result?.didChange == true {
      cachedState = nil
    }
    return result
  }

  func mutationDeliveryBarrierSummary() throws
    -> InstantMutationDeliveryBarrierSummary
  {
    try readTransaction {
      let outstandingPredicate =
        """
        (delivery_state = ? OR
          (delivery_metadata_version < ? AND status IN (?, ?)))
        """
      let outstandingBindings: [SQLiteBinding] = [
        .text(InstantOutboxDeliveryState.needsDelivery.rawValue),
        .int(Int64(InstantOutboxDeliveryMetadata.currentVersion)),
        .text(InstantMutationStatus.pending.rawValue),
        .text(InstantMutationStatus.confirmed.rawValue),
      ]
      let outstandingMutationCount = Int(try selectInt64(
        "SELECT COUNT(*) FROM instant_outbox WHERE \(outstandingPredicate)",
        outstandingBindings
      ))
      let firstOutstandingMutationID = try selectScalar(
        """
        SELECT mutation_id FROM instant_outbox
        WHERE \(outstandingPredicate)
        ORDER BY created_at_ms, mutation_id
        LIMIT 1
        """,
        outstandingBindings
      )
      let firstOutstandingStatus = try selectScalar(
        """
        SELECT status FROM instant_outbox
        WHERE \(outstandingPredicate)
        ORDER BY created_at_ms, mutation_id
        LIMIT 1
        """,
        outstandingBindings
      )
      let firstOutstandingConfirmationSource = try selectScalar(
        """
        SELECT confirmation_source FROM instant_outbox
        WHERE \(outstandingPredicate)
        ORDER BY created_at_ms, mutation_id
        LIMIT 1
        """,
        outstandingBindings
      ).flatMap(InstantMutationConfirmationSource.init(rawValue:))
      let sampleOutstandingMutationIDs = try selectStrings(
        """
        SELECT mutation_id FROM instant_outbox
        WHERE \(outstandingPredicate)
        ORDER BY created_at_ms, mutation_id
        LIMIT 8
        """,
        outstandingBindings
      )
      return InstantMutationDeliveryBarrierSummary(
        outstandingMutationCount: outstandingMutationCount,
        firstOutstandingMutationID: firstOutstandingMutationID,
        firstOutstandingIsLocalOnlyConfirmation:
          firstOutstandingStatus == InstantMutationStatus.confirmed.rawValue,
        firstOutstandingConfirmationSource: firstOutstandingConfirmationSource,
        sampleOutstandingMutationIDs: sampleOutstandingMutationIDs,
        firstFailedMutation: try firstFailedMutationShellWithoutTransaction()
      )
    }
  }

  func loadFailedMutationLifecycles(
    limit: Int,
    maximumEncodedByteCount: Int = InstantAutomaticOutboxClaimLimits.maximumEncodedBodyBytes
  ) throws -> [PendingMutation] {
    precondition(limit >= 0)
    precondition(maximumEncodedByteCount >= 0)
    guard limit > 0 else { return [] }
    return try transaction {
      let candidates = try loadFailedOutboxLifecycleCandidatesWithoutTransaction(limit: limit)
      var mutations: [PendingMutation] = []
      var admittedByteCount = 0
      mutations.reserveCapacity(candidates.count)
      for candidate in candidates {
        let preferredByteCount = candidate.lifecycleByteCount ?? candidate.bodyByteCount
        if preferredByteCount > maximumEncodedByteCount {
          let quarantined = try quarantineOversizedOutboxMutationWithoutTransaction(
            id: candidate.mutationID,
            createdAtMilliseconds: candidate.createdAtMilliseconds,
            encodedBodyByteCount: max(candidate.bodyByteCount, preferredByteCount),
            maximumEncodedBodyByteCount: maximumEncodedByteCount
          )
          mutations.append(quarantined.compactedForMemory)
          continue
        }
        guard preferredByteCount <= maximumEncodedByteCount - admittedByteCount else { break }

        if let lifecycleByteCount = candidate.lifecycleByteCount,
          let lifecycleJSON = try selectScalar(
            "SELECT lifecycle_json FROM instant_outbox WHERE mutation_id = ? LIMIT 1",
            [.text(candidate.mutationID)]
          )
        {
          admittedByteCount += lifecycleByteCount
          decodedOutboxLifecycleCount += 1
          decodedOutboxLifecycleByteCount += lifecycleByteCount
          do {
            let mutation: PendingMutation = try decodeOutboxBody(lifecycleJSON)
            guard mutation.id == candidate.mutationID else {
              throw persistenceError(
                operation: "decode failed mutation lifecycle",
                message: "The lifecycle mutation id did not match its SQLite row id."
              )
            }
            mutations.append(compactedLifecycleForInspection(
              mutation,
              hasStoredReceiptFingerprint: candidate.hasReceiptFingerprint
            ))
            continue
          } catch {
            reportIssue(
              "Instant found invalid lifecycle metadata for failed mutation '\(candidate.mutationID)': \(error)"
            )
          }
        }

        if candidate.bodyByteCount > maximumEncodedByteCount {
          let quarantined = try quarantineOversizedOutboxMutationWithoutTransaction(
            id: candidate.mutationID,
            createdAtMilliseconds: candidate.createdAtMilliseconds,
            encodedBodyByteCount: candidate.bodyByteCount,
            maximumEncodedBodyByteCount: maximumEncodedByteCount
          )
          mutations.append(quarantined.compactedForMemory)
          continue
        }
        guard candidate.bodyByteCount <= maximumEncodedByteCount - admittedByteCount else { break }
        guard let row = try loadOutboxBodyRowWithoutTransaction(id: candidate.mutationID) else {
          continue
        }
        admittedByteCount += candidate.bodyByteCount
        decodedOutboxBodyCount += 1
        decodedOutboxBodyByteCount += candidate.bodyByteCount
        do {
          var mutation: PendingMutation = try decodeOutboxBody(row.json)
          guard mutation.id == candidate.mutationID else {
            throw persistenceError(
              operation: "repair failed mutation lifecycle",
              message: "The durable mutation id did not match its SQLite row id."
            )
          }
          mutation.status = .failed
          try saveOutboxMutationWithoutTransaction(
            mutation,
            receiptWriteAuthority: .publicPersistence
          )
          mutations.append(compactedLifecycleForInspection(
            mutation,
            hasStoredReceiptFingerprint:
              try hasStoredPreparedOptimisticEffectReceiptWithoutTransaction(mutation)
          ))
        } catch {
          let quarantined = try quarantineInvalidOutboxMutationWithoutTransaction(
            row,
            reason: "Neither the failed lifecycle nor durable body could be decoded: \(error)"
          )
          mutations.append(quarantined.compactedForMemory)
        }
      }
      return mutations
    }
  }

  /// Returns whether an indexed automatic-retry candidate exists without
  /// reading or decoding any durable mutation body.
  func hasAutomaticFailedMutationRetryCandidate(
    excludingMutationIDs: Set<String>
  ) throws -> Bool {
    try readTransaction {
      let attributeRevision = try loadMetadataRevisionWithoutTransaction(
        Self.attributeRevisionKey
      )
      let exclusion = automaticFailedMutationRetryExclusion(
        excludingMutationIDs: excludingMutationIDs
      )
      return try selectInt64(
        """
        SELECT EXISTS(
          SELECT 1
          FROM instant_outbox INDEXED BY instant_outbox_failed_retry_window_idx
          WHERE \(Self.automaticFailedMutationRetryEligibilitySQL)
            \(Self.automaticFailedMutationRetryAttributeRevisionSQL)
            \(exclusion.sql)
          LIMIT 1
        )
        """,
        [.int(attributeRevision)] + exclusion.bindings
      ) != 0
    }
  }

  /// Moves one bounded keyset window of already-applied transient failures
  /// back to pending without reconstructing the durable queue.
  ///
  /// The read phase materializes at most 50 actual SQLite bodies and at most
  /// 8 MiB of their actual blob bytes. The write phase then proves every row's
  /// revision, failed status, active optimistic overlay, claim state, and body
  /// before changing any row. A lost race returns `nil` and changes nothing.
  func retryAutomaticFailedMutationWindow(
    after position: InstantOutboxDeliveryPosition?,
    excludingMutationIDs: Set<String>,
    maximumBodyCount: Int = InstantAutomaticOutboxClaimLimits.maximumBodyDecodeCount,
    maximumEncodedBodyByteCount: Int =
      InstantAutomaticOutboxClaimLimits.maximumEncodedBodyBytes
  ) async throws -> InstantAutomaticFailedMutationRetryApplication? {
    precondition(maximumBodyCount >= 0)
    precondition(
      maximumBodyCount <= InstantAutomaticOutboxClaimLimits.maximumBodyDecodeCount
    )
    precondition(maximumEncodedBodyByteCount >= 0)
    precondition(
      maximumEncodedBodyByteCount
        <= InstantAutomaticOutboxClaimLimits.maximumEncodedBodyBytes
    )
    guard maximumBodyCount > 0 else {
      return InstantAutomaticFailedMutationRetryApplication(
        retriedMutations: [],
        isolatedMutations: [],
        quarantinedMutations: [],
        decodedBodyCount: 0,
        decodedBodyByteCount: 0,
        nextPosition: position,
        hasMoreCandidates: false
      )
    }

    let plan = try readTransaction {
      if let blocker = try synchronizationBlockerWithoutTransaction() {
        throw blocker.error(operation: "admit automatic failed-mutation retry")
      }
      let attributeRevision = try loadMetadataRevisionWithoutTransaction(
        Self.attributeRevisionKey
      )
      return try loadAutomaticFailedMutationRetryPlanWithoutTransaction(
        after: position,
        excludingMutationIDs: excludingMutationIDs,
        maximumBodyCount: maximumBodyCount,
        maximumEncodedBodyByteCount: maximumEncodedBodyByteCount,
        expectedAttributeRevision: attributeRevision
      )
    }
    guard !plan.dispositions.isEmpty else {
      return InstantAutomaticFailedMutationRetryApplication(
        retriedMutations: [],
        isolatedMutations: [],
        quarantinedMutations: [],
        decodedBodyCount: 0,
        decodedBodyByteCount: 0,
        nextPosition: position,
        hasMoreCandidates: false
      )
    }

    try await onFailedMutationRetryWindowLoadedForTesting?(
      plan.dispositions.map { $0.candidate.mutationID }
    )

    let application: InstantAutomaticFailedMutationRetryApplication? = try transaction {
      if let blocker = try synchronizationBlockerWithoutTransaction() {
        throw blocker.error(operation: "commit automatic failed-mutation retry")
      }
      guard
        try loadMetadataRevisionWithoutTransaction(Self.attributeRevisionKey)
          == plan.expectedAttributeRevision,
        try plan.dispositions.allSatisfy({ disposition in
          try automaticFailedMutationRetryCandidateStillMatchesWithoutTransaction(
            disposition.candidate,
            originalJSON: disposition.originalJSON,
            expectedAttributeRevision: plan.expectedAttributeRevision
          )
        })
      else { return nil }

      var retriedMutations: [PendingMutation] = []
      var isolatedMutations: [PendingMutation] = []
      var quarantinedMutations: [PendingMutation] = []
      retriedMutations.reserveCapacity(plan.dispositions.count)

      for disposition in plan.dispositions {
        switch disposition {
        case let .retry(candidate, originalJSON, mutation):
          try retryFailedMutationWithoutTransaction(
            mutation,
            candidate: candidate,
            originalJSON: originalJSON,
            expectedAttributeRevision: plan.expectedAttributeRevision
          )
          retriedMutations.append(mutation)

        case let .isolate(candidate, originalJSON, mutation, reason):
          try isolateAutomaticFailedMutationRetryWithoutTransaction(
            mutation,
            candidate: candidate,
            originalJSON: originalJSON,
            reason: reason,
            expectedAttributeRevision: plan.expectedAttributeRevision
          )
          isolatedMutations.append(mutation)

        case let .quarantineCorrupt(candidate, row, reason):
          let mutation = try quarantineInvalidOutboxMutationWithoutTransaction(
            row,
            reason: reason
          )
          try advanceQuarantinedMutationRevisionWithoutTransaction(candidate)
          quarantinedMutations.append(mutation)

        case let .quarantineOversized(candidate):
          let mutation = try quarantineOversizedOutboxMutationWithoutTransaction(
            id: candidate.mutationID,
            createdAtMilliseconds: candidate.position.createdAtMilliseconds,
            encodedBodyByteCount: candidate.actualBodyByteCount,
            maximumEncodedBodyByteCount: maximumEncodedBodyByteCount
          )
          try advanceQuarantinedMutationRevisionWithoutTransaction(candidate)
          quarantinedMutations.append(mutation)
        }
      }

      _ = try bumpMetadataRevisionWithoutTransaction(Self.outboxRevisionKey)
      let nextPosition = plan.nextPosition
      let hasMoreCandidates = try nextPosition.map {
        try hasAutomaticFailedMutationRetryCandidateWithoutTransaction(
          after: $0,
          excludingMutationIDs: excludingMutationIDs,
          expectedAttributeRevision: plan.expectedAttributeRevision
        )
      } ?? false
      failedMutationRetryMetrics.completedWindowCount += 1
      failedMutationRetryMetrics.totalDecodedBodyCount += plan.decodedBodyCount
      failedMutationRetryMetrics.totalDecodedBodyByteCount += plan.decodedBodyByteCount
      failedMutationRetryMetrics.maximumDecodedBodyCount = max(
        failedMutationRetryMetrics.maximumDecodedBodyCount,
        plan.decodedBodyCount
      )
      failedMutationRetryMetrics.maximumDecodedBodyByteCount = max(
        failedMutationRetryMetrics.maximumDecodedBodyByteCount,
        plan.decodedBodyByteCount
      )
      failedMutationRetryMetrics.lastDecodedBodyCount = plan.decodedBodyCount
      return InstantAutomaticFailedMutationRetryApplication(
        retriedMutations: retriedMutations,
        isolatedMutations: isolatedMutations,
        quarantinedMutations: quarantinedMutations,
        decodedBodyCount: plan.decodedBodyCount,
        decodedBodyByteCount: plan.decodedBodyByteCount,
        nextPosition: nextPosition,
        hasMoreCandidates: hasMoreCandidates
      )
    }
    if application != nil {
      cachedState = nil
    }
    return application
  }

  func latestOutboxCreationTimestamp(expectedOutboxRevision: Int64) throws
    -> (matchesRevision: Bool, timestamp: InstantTimestamp?)
  {
    try readTransaction {
      guard
        try loadMetadataRevisionWithoutTransaction(Self.outboxRevisionKey)
          == expectedOutboxRevision
      else { return (false, nil) }
      let timestamp = try selectScalar(
        "SELECT CAST(MAX(created_at_ms) AS TEXT) FROM instant_outbox"
      ).flatMap(Int64.init).map(InstantTimestamp.init(milliseconds:))
      return (true, timestamp)
    }
  }

  private func immediateOutboxTailIDWithoutTransaction() throws -> String? {
    try selectScalar(
      """
      SELECT mutation_id
      FROM instant_outbox
      ORDER BY created_at_ms DESC, mutation_id DESC
      LIMIT 1
      """
    )
  }

  /// Reproves the scalar ordering/claim boundary before quarantining a tail.
  ///
  /// A matching Runtime receipt is intentionally not required: its absence is
  /// one of the invalid-tail conditions this guarded transition repairs.
  private func isImmediateSupersessionTailQuarantineCandidateWithoutTransaction(
    id mutationID: String
  ) throws -> Bool {
    try selectInt64(
      """
      SELECT EXISTS(
        SELECT 1 FROM instant_outbox
        WHERE mutation_id = ? AND status = ?
          AND optimistic_overlay_active = 1
          AND delivery_state = ?
          AND delivery_metadata_version = ?
          AND encoded_body_bytes IS NOT NULL
          AND delivery_claim_state = ?
          AND delivery_started = 0
      )
      """,
      [
        .text(mutationID),
        .text(InstantMutationStatus.pending.rawValue),
        .text(InstantOutboxDeliveryState.needsDelivery.rawValue),
        .int(Int64(InstantOutboxDeliveryMetadata.currentVersion)),
        .text(InstantOutboxDeliveryClaimState.ready.rawValue),
      ]
    ) == 1
  }

  /// Reproves that a tail remains Runtime-prepared before atomically replacing
  /// it with a same-entity successor.
  private func isImmediateSupersessionTailEligibleWithoutTransaction(
    id mutationID: String
  ) throws -> Bool {
    try selectInt64(
      """
      SELECT EXISTS(
        SELECT 1 FROM instant_outbox
        WHERE mutation_id = ? AND status = ?
          AND optimistic_overlay_active = 1
          AND optimistic_effect_receipt_fingerprint IS NOT NULL
          AND delivery_state = ?
          AND delivery_metadata_version = ?
          AND encoded_body_bytes IS NOT NULL
          AND delivery_claim_state = ?
          AND delivery_started = 0
      )
      """,
      [
        .text(mutationID),
        .text(InstantMutationStatus.pending.rawValue),
        .text(InstantOutboxDeliveryState.needsDelivery.rawValue),
        .int(Int64(InstantOutboxDeliveryMetadata.currentVersion)),
        .text(InstantOutboxDeliveryClaimState.ready.rawValue),
      ]
    ) == 1
  }

  /// Loads at most the one exact durable queue tail when it remains eligible
  /// for immediate supersession. Any other tail is an ordering barrier and is
  /// returned as `nil` without decoding its body.
  func loadImmediateSupersessionTail(
    expectedStoreRevision: Int64,
    expectedOutboxRevision: Int64
  ) async throws -> InstantOutboxImmediateTailLoad {
    var invalidTail: InstantOutboxInvalidImmediateTail?
    let load = try readTransaction {
      guard
        try loadMetadataRevisionWithoutTransaction(Self.storeRevisionKey)
          == expectedStoreRevision,
        try loadMetadataRevisionWithoutTransaction(Self.outboxRevisionKey)
          == expectedOutboxRevision
      else {
        return InstantOutboxImmediateTailLoad(matchesRevisions: false, mutation: nil)
      }

      var statement: OpaquePointer?
      try prepare(
        """
        SELECT mutation_id, status, optimistic_overlay_active,
               delivery_claim_state, delivery_started, delivery_state,
               delivery_metadata_version, encoded_body_bytes,
               created_at_ms, length(CAST(json AS BLOB))
        FROM instant_outbox
        ORDER BY created_at_ms DESC, mutation_id DESC
        LIMIT 1
        """,
        statement: &statement
      )
      defer { sqlite3_finalize(statement) }
      let code = sqlite3_step(statement)
      if code == SQLITE_DONE {
        return InstantOutboxImmediateTailLoad(matchesRevisions: true, mutation: nil)
      }
      guard code == SQLITE_ROW,
        let mutationIDBytes = sqlite3_column_text(statement, 0),
        let statusBytes = sqlite3_column_text(statement, 1),
        let claimStateBytes = sqlite3_column_text(statement, 3)
      else {
        throw persistenceError(
          operation: "read immediate supersession tail",
          message: lastErrorMessage()
        )
      }
      let mutationID = String(cString: mutationIDBytes)
      let status = String(cString: statusBytes)
      let claimState = String(cString: claimStateBytes)
      let deliveryState = sqlite3_column_text(statement, 5).map(String.init(cString:))
      guard status == InstantMutationStatus.pending.rawValue,
        sqlite3_column_int64(statement, 2) != 0,
        claimState == InstantOutboxDeliveryClaimState.ready.rawValue,
        sqlite3_column_int64(statement, 4) == 0,
        deliveryState == InstantOutboxDeliveryState.needsDelivery.rawValue,
        sqlite3_column_int64(statement, 6)
          == Int64(InstantOutboxDeliveryMetadata.currentVersion),
        sqlite3_column_type(statement, 7) != SQLITE_NULL,
        sqlite3_column_type(statement, 9) != SQLITE_NULL
      else {
        return InstantOutboxImmediateTailLoad(matchesRevisions: true, mutation: nil)
      }

      let metadataByteCount = sqlite3_column_int64(statement, 7)
      let createdAtMilliseconds = sqlite3_column_int64(statement, 8)
      let actualByteCount = sqlite3_column_int64(statement, 9)
      let maximumByteCount = Int64(
        InstantAutomaticOutboxClaimLimits.maximumEncodedBodyBytes
      )
      if actualByteCount > maximumByteCount,
        metadataByteCount >= 0,
        metadataByteCount == actualByteCount
      {
        // A consistently normalized oversized row is a durable ordering
        // barrier. Delivery owns its existing SQLite-only quarantine policy;
        // enqueue neither materializes nor mutates it.
        return InstantOutboxImmediateTailLoad(matchesRevisions: true, mutation: nil)
      }
      if actualByteCount < 0 || actualByteCount > maximumByteCount {
        invalidTail = .oversized(
          mutationID: mutationID,
          createdAtMilliseconds: createdAtMilliseconds,
          metadataByteCount: metadataByteCount,
          actualByteCount: actualByteCount
        )
        return InstantOutboxImmediateTailLoad(matchesRevisions: false, mutation: nil)
      }

      guard let row = try loadOutboxBodyRowWithoutTransaction(id: mutationID) else {
        return InstantOutboxImmediateTailLoad(matchesRevisions: false, mutation: nil)
      }
      guard metadataByteCount >= 0,
        metadataByteCount == actualByteCount,
        row.json.utf8.count == Int(actualByteCount)
      else {
        invalidTail = .bounded(
          row: row,
          reason:
            "The normalized encoded_body_bytes value (\(metadataByteCount)) did not match the bounded SQLite body length (\(actualByteCount))."
        )
        return InstantOutboxImmediateTailLoad(matchesRevisions: false, mutation: nil)
      }

      decodedOutboxBodyCount += 1
      decodedOutboxBodyByteCount += row.json.utf8.count
      do {
        let mutation: PendingMutation = try decodeOutboxBody(row.json)
        guard mutation.id == mutationID,
          mutation.status == .pending,
          mutation.provesReplayableOptimisticEffectReceipt,
          try hasStoredPreparedOptimisticEffectReceiptWithoutTransaction(mutation)
        else {
          throw persistenceError(
            operation: "validate immediate supersession tail",
            message:
              "The normalized durable body disagreed with its pending, SQLite-owned Runtime-prepared active-overlay row."
          )
        }
        // A lookup or precondition can be a valid active optimistic write even
        // when the current local snapshot produces no inverse operations. The
        // caller already requires a rollback before superseding this tail; the
        // durable row itself must remain deliverable and replayable.
        return InstantOutboxImmediateTailLoad(matchesRevisions: true, mutation: mutation)
      } catch {
        invalidTail = .bounded(
          row: row,
          reason: "The immediate supersession tail could not be decoded and validated: \(error)"
        )
        return InstantOutboxImmediateTailLoad(matchesRevisions: false, mutation: nil)
      }
    }
    guard let invalidTail else { return load }

    await onInvalidImmediateSupersessionTailReadForTesting?(invalidTail.mutationID)

    let didQuarantine = try transaction {
      guard
        try loadMetadataRevisionWithoutTransaction(Self.storeRevisionKey)
          == expectedStoreRevision,
        try loadMetadataRevisionWithoutTransaction(Self.outboxRevisionKey)
          == expectedOutboxRevision,
        try immediateOutboxTailIDWithoutTransaction() == invalidTail.mutationID,
        try isImmediateSupersessionTailQuarantineCandidateWithoutTransaction(
          id: invalidTail.mutationID
        )
      else { return false }

      switch invalidTail {
      case let .bounded(row, reason):
        guard
          try selectScalar(
            "SELECT json FROM instant_outbox WHERE mutation_id = ? LIMIT 1",
            [.text(row.mutationID)]
          ) == row.json
        else { return false }
        _ = try quarantineInvalidOutboxMutationWithoutTransaction(row, reason: reason)

      case let .oversized(
        mutationID,
        createdAtMilliseconds,
        metadataByteCount,
        actualByteCount
      ):
        guard actualByteCount >= 0,
          try selectInt64(
            """
            SELECT EXISTS(
              SELECT 1 FROM instant_outbox
              WHERE mutation_id = ? AND created_at_ms = ?
                AND encoded_body_bytes = ?
                AND length(CAST(json AS BLOB)) = ?
            )
            """,
            [
              .text(mutationID),
              .int(createdAtMilliseconds),
              .int(metadataByteCount),
              .int(actualByteCount),
            ]
          ) == 1
        else { return false }
        _ = try quarantineOversizedOutboxMutationWithoutTransaction(
          id: mutationID,
          createdAtMilliseconds: createdAtMilliseconds,
          encodedBodyByteCount: Int(actualByteCount),
          maximumEncodedBodyByteCount:
            InstantAutomaticOutboxClaimLimits.maximumEncodedBodyBytes
        )
      }
      _ = try bumpMetadataRevisionWithoutTransaction(Self.outboxRevisionKey)
      return true
    }
    if didQuarantine {
      cachedState = nil
    }
    // A quarantine changes the outbox revision; a lost race also invalidates
    // this caller's revision pair. In both cases the runtime must reload before
    // preparing the new local mutation.
    return InstantOutboxImmediateTailLoad(matchesRevisions: false, mutation: nil)
  }

  /// Resolves a transaction id that no longer has a physical outbox row.
  /// Supersession aliases remain idempotence keys, so callers must consult
  /// this row-addressed lookup before admitting a same-id mutation as new.
  func loadOutboxAliasReplay(
    id mutationID: String,
    expectedStoreRevision: Int64,
    expectedOutboxRevision: Int64
  ) throws -> InstantOutboxAliasReplayLoad {
    try readTransaction {
      guard
        try loadMetadataRevisionWithoutTransaction(Self.storeRevisionKey)
          == expectedStoreRevision,
        try loadMetadataRevisionWithoutTransaction(Self.outboxRevisionKey)
          == expectedOutboxRevision
      else {
        return InstantOutboxAliasReplayLoad(matchesRevisions: false, alias: nil)
      }

      var statement: OpaquePointer?
      try prepare(
        """
        SELECT lifecycles.current_mutation_id,
               lifecycles.terminal_json IS NOT NULL,
               current.status
        FROM instant_outbox_lifecycle_aliases AS aliases
        JOIN instant_outbox_lifecycles AS lifecycles
          ON lifecycles.lifecycle_id = aliases.lifecycle_id
        LEFT JOIN instant_outbox AS current
          ON current.mutation_id = lifecycles.current_mutation_id
        WHERE aliases.mutation_id = ?
        LIMIT 1
        """,
        statement: &statement
      )
      defer { sqlite3_finalize(statement) }
      try bind([.text(mutationID)], to: statement)
      let code = sqlite3_step(statement)
      if code == SQLITE_DONE {
        return InstantOutboxAliasReplayLoad(matchesRevisions: true, alias: nil)
      }
      guard code == SQLITE_ROW,
        let currentMutationIDBytes = sqlite3_column_text(statement, 0)
      else {
        throw persistenceError(
          operation: "resolve superseded transaction id",
          message: lastErrorMessage()
        )
      }
      let isTerminal = sqlite3_column_int64(statement, 1) != 0
      let currentStatus = sqlite3_column_text(statement, 2).map(String.init(cString:))
      return InstantOutboxAliasReplayLoad(
        matchesRevisions: true,
        alias: InstantOutboxAliasReplayLoad.Alias(
          currentMutationID: String(cString: currentMutationIDBytes),
          isPending: !isTerminal && currentStatus == InstantMutationStatus.pending.rawValue
        )
      )
    }
  }

  /// Returns the observer key for a terminal event only while that event
  /// belongs to the current physical survivor. A delayed event for any
  /// superseded alias returns `nil` and must not wake the survivor's observers.
  func mutationLifecyclePublicationIdentity(for mutationID: String) throws -> String? {
    try readTransaction {
      guard let lifecycleID = try lifecycleIDWithoutTransaction(for: mutationID) else {
        return mutationID
      }
      let currentMutationID = try currentMutationIDWithoutTransaction(
        lifecycleID: lifecycleID
      )
      return currentMutationID == mutationID ? lifecycleID : nil
    }
  }

  func resolveMutationLifecycle(
    id mutationID: String
  ) throws -> InstantMutationLifecycleResolution {
    try readTransaction {
      let lifecycleID = try lifecycleIDWithoutTransaction(for: mutationID) ?? mutationID
      var currentMutationID = mutationID
      var terminalJSON: String?
      var terminalReceiptFingerprint: String?
      var terminalAcceptanceFingerprint: String?
      var statement: OpaquePointer?
      try prepare(
        """
        SELECT current_mutation_id, terminal_json,
               terminal_optimistic_effect_receipt_fingerprint,
               terminal_server_acceptance_payload_fingerprint
        FROM instant_outbox_lifecycles
        WHERE lifecycle_id = ?
        LIMIT 1
        """,
        statement: &statement
      )
      defer { sqlite3_finalize(statement) }
      try bind([.text(lifecycleID)], to: statement)
      if sqlite3_step(statement) == SQLITE_ROW {
        if let currentBytes = sqlite3_column_text(statement, 0) {
          currentMutationID = String(cString: currentBytes)
        }
        terminalJSON = sqlite3_column_text(statement, 1).map(String.init(cString:))
        terminalReceiptFingerprint = sqlite3_column_text(statement, 2)
          .map(String.init(cString:))
        terminalAcceptanceFingerprint = sqlite3_column_text(statement, 3)
          .map(String.init(cString:))
      }

      if let terminalJSON {
        decodedOutboxLifecycleCount += 1
        decodedOutboxLifecycleByteCount += terminalJSON.utf8.count
        let mutation: PendingMutation = try decodeOutboxBody(terminalJSON)
        let lifecycleMutation = lifecycleMutationForInspection(
          mutation,
          hasStoredReceiptFingerprint: terminalReceiptFingerprint != nil
        )
        if let event = lifecycleEvent(
          for: lifecycleMutation,
          hasServerAcceptance: terminalAcceptanceFingerprint != nil
        ) {
          return InstantMutationLifecycleResolution(
            observationID: lifecycleID,
            event: event
          )
        }
      }

      guard let row = try loadOutboxBodyRowWithoutTransaction(id: currentMutationID) else {
        return InstantMutationLifecycleResolution(
          observationID: lifecycleID,
          event: .waiting
        )
      }
      decodedOutboxBodyCount += 1
      decodedOutboxBodyByteCount += row.json.utf8.count
      let mutation: PendingMutation = try decodeOutboxBody(row.json)
      let hasPreparedReceipt = try hasStoredPreparedOptimisticEffectReceipt(
        mutation,
        in: row
      )
      let lifecycleMutation = lifecycleMutationForInspection(
        mutation,
        hasStoredReceiptFingerprint: hasPreparedReceipt
      )
      return InstantMutationLifecycleResolution(
        observationID: lifecycleID,
        event: lifecycleEvent(
          for: lifecycleMutation,
          hasServerAcceptance: try hasStoredServerAcceptance(mutation, in: row)
        ) ?? .waiting
      )
    }
  }

  func currentOutboxRevision() throws -> Int64 {
    try readTransaction {
      try loadMetadataRevisionWithoutTransaction(Self.outboxRevisionKey)
    }
  }

  func currentAttributeRevision() throws -> Int64 {
    try readTransaction {
      try loadMetadataRevisionWithoutTransaction(Self.attributeRevisionKey)
    }
  }

  /// Claims one bounded explicit-flush window before external transport I/O.
  ///
  /// A nil limit means the fixed delivery envelope, not the entire durable
  /// queue. The selector is the same metadata-first, body-at-a-time transaction
  /// used by automatic delivery; explicit mode additionally stops at a
  /// non-pending queue barrier and requires exclusive delivery-lane ownership.
  func claimPendingOutboxMutationsForExplicitFlush(
    limit: Int?,
    claimantID: String,
    claimToken: String,
    now: InstantTimestamp
  ) throws -> [PendingMutation] {
    try claimExplicitOutboxDeliveryWindow(
      limit: limit,
      claimantID: claimantID,
      claimToken: claimToken,
      now: now
    ).mutations
  }

  /// Runtime form of the explicit selector. It retains the shared window's
  /// bounded quarantine results so the hot actor and public lifecycle can be
  /// updated alongside the durable transaction.
  func claimExplicitOutboxDeliveryWindow(
    limit: Int?,
    claimantID: String,
    claimToken: String,
    now: InstantTimestamp
  ) throws -> InstantAutomaticOutboxClaimWindow {
    precondition(limit.map { $0 >= 0 } ?? true)
    let maximumMutationCount = min(
      limit ?? InstantOutboxClaimLimits.maximumMutationCount,
      InstantOutboxClaimLimits.maximumMutationCount
    )
    return try claimAutomaticOutboxDeliveryWindow(
      InstantAutomaticOutboxClaimRequest(
        claimantID: claimantID,
        claimToken: claimToken,
        now: now,
        maximumMutationCount: maximumMutationCount,
        requiresExclusiveLane: true
      )
    )
  }

  /// Fails only the token-owned offered rows without loading their optimistic
  /// components. Their optimistic overlays remain applied until a later
  /// authoritative refresh can peel and replay them in bounded pages.
  ///
  /// Live-encoding failures pass the attribute revision used for projection so
  /// a later schema deployment can make them retryable. Terminal transport
  /// rejections pass `nil` because their retry policy is independent of schema.
  func failOutboxMutationsForDelivery(
    _ failuresByMutationID: [String: InstantMutationFailure],
    failureAttributeRevision: Int64?,
    claimToken: String,
    expectedOutboxRevision: Int64,
    metadataEntries: [InstantPersistenceMetadataEntry] = []
  ) throws -> InstantOutboxBatchFailureApplication? {
    guard !failuresByMutationID.isEmpty else {
      return InstantOutboxBatchFailureApplication(
        mutations: [],
        resultingOutboxRevision: expectedOutboxRevision,
        decodedBodyCount: 0,
        decodedBodyByteCount: 0
      )
    }
    return try transaction {
      guard
        try loadMetadataRevisionWithoutTransaction(Self.outboxRevisionKey)
          == expectedOutboxRevision
      else { return nil }

      var failedMutations: [PendingMutation] = []
      var bodyCount = 0
      var bodyByteCount = 0
      for mutationID in failuresByMutationID.keys.sorted() {
        guard try selectScalar(
          """
          SELECT delivery_claim_token FROM instant_outbox
          WHERE mutation_id = ? AND delivery_claim_state = ?
          LIMIT 1
          """,
          [
            .text(mutationID),
            .text(InstantOutboxDeliveryClaimState.claimed.rawValue),
          ]
        ) == claimToken else { continue }
        guard let row = try loadOutboxBodyRowWithoutTransaction(id: mutationID) else { continue }
        bodyCount += 1
        bodyByteCount += row.json.utf8.count
        decodedOutboxBodyCount += 1
        decodedOutboxBodyByteCount += row.json.utf8.count
        do {
          let mutation: PendingMutation = try decodeOutboxBody(row.json)
          guard mutation.id == mutationID else {
            failedMutations.append(
              try quarantineInvalidOutboxMutationWithoutTransaction(
                row,
                reason: "The durable mutation id did not match its SQLite row id."
              )
            )
            continue
          }
          guard try hasStoredPreparedOptimisticEffectReceipt(mutation, in: row),
            row.deliveryClaimPayloadFingerprint != nil
          else {
            failedMutations.append(
              try quarantineInvalidOutboxMutationWithoutTransaction(
                row,
                reason:
                  "The token-owned mutation body no longer matches its SQLite-owned materialization and wire-claim receipts."
              )
            )
            continue
          }
          guard durableDeliveryState(
            for: mutation,
            hasServerAcceptance: try hasStoredServerAcceptance(mutation, in: row)
          ) == .needsDelivery else {
            continue
          }
          failedMutations.append(
            try failClaimedOutboxMutationWithoutTransaction(
              mutation,
              failure: failuresByMutationID[mutationID]!,
              failureAttributeRevision: failureAttributeRevision,
              claimToken: claimToken
            )
          )
        } catch {
          failedMutations.append(
            try quarantineInvalidOutboxMutationWithoutTransaction(
              row,
              reason: "The durable mutation body could not be decoded while recording a delivery failure: \(error)"
            )
          )
        }
      }
      let resultingRevision: Int64
      if failedMutations.isEmpty {
        resultingRevision = expectedOutboxRevision
      } else {
        for entry in metadataEntries {
          try saveMetadataValueWithoutTransaction(
            entry.value,
            key: entry.key,
            updatedAt: entry.updatedAt
          )
        }
        resultingRevision = try bumpMetadataRevisionWithoutTransaction(Self.outboxRevisionKey)
      }
      return InstantOutboxBatchFailureApplication(
        mutations: failedMutations.sorted(by: PendingMutation.creationOrder),
        resultingOutboxRevision: resultingRevision,
        decodedBodyCount: bodyCount,
        decodedBodyByteCount: bodyByteCount
      )
    }
  }

  private func failClaimedOutboxMutationWithoutTransaction(
    _ selectedMutation: PendingMutation,
    failure: InstantMutationFailure,
    failureAttributeRevision: Int64?,
    claimToken: String
  ) throws -> PendingMutation {
    var mutation = selectedMutation
    mutation.status = .failed
    mutation.failureMessage = failure.message
    mutation.failure = failure
    mutation.serverTransactionID = nil
    mutation.confirmationSource = nil
    // Retaining the known optimistic layer keeps ordinary retry and discard
    // truthful until an authoritative refresh can peel it in bounded pages.
    try saveOutboxMutationWithoutTransaction(
      mutation,
      failureAttributeRevision: failureAttributeRevision,
      receiptWriteAuthority: .publicPersistence
    )
    try execute(
      """
      UPDATE instant_outbox
      SET delivery_claim_state = ?, delivery_claim_token = NULL,
          delivery_claimant_id = NULL, delivery_claim_deadline_ms = NULL,
          delivery_claim_projected_body_bytes = NULL,
          delivery_claim_payload_fingerprint = NULL
      WHERE mutation_id = ? AND delivery_claim_state = ?
        AND delivery_claim_token = ?
      """,
      [
        .text(InstantOutboxDeliveryClaimState.ready.rawValue),
        .text(mutation.id),
        .text(InstantOutboxDeliveryClaimState.claimed.rawValue),
        .text(claimToken),
      ]
    )
    guard sqlite3_changes(connection.raw) == 1 else {
      throw persistenceError(
        operation: "fail claimed outbox mutation",
        message: "The exact projected mutation claim changed before failure disposition."
      )
    }
    return mutation
  }

  /// Applies explicit-transport confirmations to only the token-owned rows.
  /// The claim remains held until the caller finishes the whole response
  /// disposition and releases unaddressed rows.
  func confirmExplicitlyFlushedOutboxMutations(
    _ results: [InstantMutationTransportResult],
    selectedMutations: [PendingMutation],
    claimToken: String
  ) throws -> [PendingMutation] {
    let confirmations = results.filter { $0.outcome == .confirmed }
    guard !confirmations.isEmpty else { return [] }
    let selectedByID = Dictionary(
      uniqueKeysWithValues: selectedMutations.map { ($0.id, $0) }
    )
    return try transaction {
      var confirmed: [PendingMutation] = []
      confirmed.reserveCapacity(confirmations.count)
      for result in confirmations {
        guard let selectedMutation = selectedByID[result.mutationID],
          selectedMutation.status == .pending,
          let row = try loadOutboxBodyRowWithoutTransaction(id: result.mutationID)
        else { continue }
        let selectedReceiptFingerprint = try selectedMutation
          .optimisticEffectReceiptFingerprint()
        var mutation: PendingMutation
        if selectedReceiptFingerprint != nil,
          selectedReceiptFingerprint == row.optimisticEffectReceiptFingerprint
        {
          // The selector already decoded this exact durable body. Reuse it for
          // the ordinary disposition path so a maximum-sized row is never
          // decoded twice. A rollback-only rebase changes the material receipt
          // and takes the bounded current-body decode below instead.
          mutation = selectedMutation
        } else {
          mutation = try decodeOutboxBody(row.json)
          decodedOutboxBodyCount += 1
          decodedOutboxBodyByteCount += row.json.utf8.count
        }
        guard mutation.id == result.mutationID,
          mutation.status == .pending,
          try hasStoredPreparedOptimisticEffectReceipt(mutation, in: row)
        else { continue }
        guard let claimPayloadFingerprint = row.deliveryClaimPayloadFingerprint else {
          continue
        }

        mutation.status = .confirmed
        mutation.failureMessage = nil
        mutation.failure = nil
        mutation.confirmationSource = result.acceptance == .serverAccepted
          ? .serverTransport
          : .localTransport
        let confirmationSource = mutation.confirmationSource!.rawValue
        let deliveryState = result.acceptance == .serverAccepted
          ? InstantOutboxDeliveryState.serverAccepted
          : .needsDelivery
        let encodedBody = try encode(mutation)
        try execute(
          """
          UPDATE instant_outbox
          SET status = ?, delivery_state = ?, failure_message = NULL,
              confirmation_proven = ?, server_transaction_id = NULL,
              confirmation_source = ?, mutation_revision = mutation_revision + 1,
              encoded_body_bytes = ?, json = ?, lifecycle_json = ?,
              server_acceptance_payload_fingerprint = ?
          WHERE mutation_id = ? AND status = ? AND delivery_claim_state = ?
            AND delivery_claim_token = ?
            AND delivery_claim_payload_fingerprint = ?
            AND optimistic_effect_receipt_fingerprint = ?
          """,
          [
            .text(InstantMutationStatus.confirmed.rawValue),
            .text(deliveryState.rawValue),
            .int(result.acceptance == .serverAccepted ? 1 : 0),
            .text(confirmationSource),
            .int(Int64(encodedBody.utf8.count)),
            .text(encodedBody),
            .text(try encode(mutation.compactedForMemory)),
            result.acceptance == .serverAccepted ? .text(claimPayloadFingerprint) : .null,
            .text(result.mutationID),
            .text(InstantMutationStatus.pending.rawValue),
            .text(InstantOutboxDeliveryClaimState.claimed.rawValue),
            .text(claimToken),
            .text(claimPayloadFingerprint),
            row.optimisticEffectReceiptFingerprint.map(SQLiteBinding.text) ?? .null,
          ]
        )
        guard sqlite3_changes(connection.raw) == 1 else { continue }
        try saveMutationLifecycleWithoutTransaction(mutation)
        confirmed.append(mutation)
      }
      if !confirmed.isEmpty {
        _ = try bumpMetadataRevisionWithoutTransaction(Self.outboxRevisionKey)
        cachedState = nil
      }
      return confirmed.sorted(by: PendingMutation.creationOrder)
    }
  }

  func renewOutboxClaim(
    token: String,
    claimantID: String,
    deadlineMilliseconds: Int64
  ) throws -> Bool {
    try transaction {
      try execute(
        """
        UPDATE instant_outbox
        SET delivery_claim_deadline_ms = ?
        WHERE delivery_claim_state = ? AND delivery_claim_token = ?
          AND delivery_claimant_id = ?
        """,
        [
          .int(deadlineMilliseconds),
          .text(InstantOutboxDeliveryClaimState.claimed.rawValue),
          .text(token),
          .text(claimantID),
        ]
      )
      return sqlite3_changes(connection.raw) > 0
    }
  }

  func outboxClaimMatches(id: String, token: String) throws -> Bool {
    try selectScalar(
      """
      SELECT delivery_claim_token FROM instant_outbox
      WHERE mutation_id = ? AND delivery_claim_state = ?
      LIMIT 1
      """,
      [
        .text(id),
        .text(InstantOutboxDeliveryClaimState.claimed.rawValue),
      ]
    ) == token
  }

  /// Atomically admits one automatic-delivery window.
  ///
  /// This `BEGIN IMMEDIATE` transition is the sole automatic admission
  /// authority. It reclaims expired durable claims, walks ready rows in strict
  /// queue order, normalizes legacy rows one body at a time, quarantines corrupt
  /// rows locally, and claims only the exact rows that fit all fixed budgets.
  /// A quarantine-created synchronization blocker commits before this method
  /// throws, after releasing only the claims acquired by this request token.
  /// `delivery_started` means "ever offered to the encoder/delivery path" and
  /// deliberately remains true after a claim is released or expires.
  func claimAutomaticOutboxDeliveryWindow(
    _ request: InstantAutomaticOutboxClaimRequest
  ) throws -> InstantAutomaticOutboxClaimWindow {
    precondition(request.maximumMutationCount >= 0)
    precondition(request.maximumStepCount >= 0)
    precondition(request.maximumBodyDecodeCount >= 0)
    precondition(request.maximumEncodedBodyByteCount >= 0)
    precondition(!request.claimantID.isEmpty)
    precondition(!request.claimToken.isEmpty)

    let operation = request.requiresExclusiveLane
      ? "claim explicit outbox flush"
      : "claim automatic outbox delivery"
    let window = try transaction {
      if let blocker = try synchronizationBlockerWithoutTransaction() {
        throw blocker.error(operation: operation)
      }
      let startingRevisions = InstantPersistenceRevisions(
        store: try loadMetadataRevisionWithoutTransaction(Self.storeRevisionKey),
        outbox: try loadMetadataRevisionWithoutTransaction(Self.outboxRevisionKey)
      )
      let reclaimedMutationIDs = try reclaimExpiredOutboxClaimsWithoutTransaction(
        nowMilliseconds: request.now.milliseconds
      )
      // One claimant owns the queue-level delivery lane at a time. A claimant
      // may fill its own bounded window across pump passes, but another runtime
      // or the explicit mutation transport must wait for release/ACK/expiry so
      // two sockets cannot deliver same-key successors out of order.
      let hasForeignActiveClaim = try hasActiveOutboxClaimWithoutTransaction(
        excludingClaimantID: request.claimantID
      )
      let hasUnmeasuredActiveClaim = try selectInt64(
        """
        SELECT EXISTS(
          SELECT 1 FROM instant_outbox
          WHERE delivery_claim_state = ?
            AND delivery_claim_projected_body_bytes IS NULL
          LIMIT 1
        )
        """,
        [.text(InstantOutboxDeliveryClaimState.claimed.rawValue)]
      ) != 0
      let claimedCount = Int(try selectInt64(
        """
        SELECT COUNT(*) FROM instant_outbox
        WHERE delivery_claim_state = ?
        """,
        [.text(InstantOutboxDeliveryClaimState.claimed.rawValue)]
      ))
      let claimedStepCount = Int(try selectInt64(
        """
        SELECT COALESCE(SUM(transport_step_count), 0) FROM instant_outbox
        WHERE delivery_claim_state = ?
        """,
        [.text(InstantOutboxDeliveryClaimState.claimed.rawValue)]
      ))
      let claimedBodyByteCount = Int(try selectInt64(
        """
        SELECT COALESCE(
          SUM(COALESCE(delivery_claim_projected_body_bytes, encoded_body_bytes)),
          0
        ) FROM instant_outbox
        WHERE delivery_claim_state = ?
        """,
        [.text(InstantOutboxDeliveryClaimState.claimed.rawValue)]
      ))
      if request.requiresExclusiveLane, claimedCount > 0 {
        throw InstantError(
          code: .networkFailed,
          operation: "claim explicit outbox flush",
          message: "Another delivery lane already owns the ordered Instant outbox head.",
          recovery: "Wait for that five-second durable claim to finish or expire, then flush again."
        )
      }
      let cannotAdmitNewClaim =
        hasForeignActiveClaim || hasUnmeasuredActiveClaim || !reclaimedMutationIDs.isEmpty
      let remainingMutationCount = cannotAdmitNewClaim
        ? 0
        : max(0, request.maximumMutationCount - claimedCount)
      let remainingStepCount = cannotAdmitNewClaim
        ? 0
        : max(0, request.maximumStepCount - claimedStepCount)
      let remainingBodyByteCount = cannotAdmitNewClaim
        ? 0
        : max(0, request.maximumEncodedBodyByteCount - claimedBodyByteCount)

      var bodyDecodeCount = 0
      var bodyByteCount = 0
      var failedMutations: [PendingMutation] = []
      var mutations: [PendingMutation] = []
      var admittedStepCount = 0
      var admittedBodyByteCount = 0
      var deliveryStartedBeforeClaimByMutationID: [String: Bool] = [:]
      var firstSelectedPosition: InstantOutboxDeliveryPosition?
      var didMakeNonSendingProgress = !reclaimedMutationIDs.isEmpty
      var didChangeLifecycle = false
      var didCreateSynchronizationBlocker = false

      if remainingMutationCount > 0, request.maximumBodyDecodeCount > 0 {
        let candidates = try loadAutomaticDeliveryCandidateRowsWithoutTransaction(
          limit: request.maximumBodyDecodeCount
        )
        mutations.reserveCapacity(min(remainingMutationCount, candidates.count))
        candidateLoop: for candidate in candidates {
          guard mutations.count < remainingMutationCount else { break }
          if request.requiresExclusiveLane, candidate.status != .pending {
            // A locally confirmed but not server-proven row remains the ordered
            // automatic-delivery barrier. Explicit flush cannot leapfrog it.
            break
          }
          if candidate.metadataVersion >= InstantOutboxDeliveryMetadata.currentVersion,
            let transportStepCount = candidate.transportStepCount
          {
            if transportStepCount > InstantAutomaticOutboxClaimLimits.maximumStepCount {
              failedMutations.append(
                try quarantineOverLimitStepOutboxMutationWithoutTransaction(
                  id: candidate.mutationID,
                  createdAtMilliseconds: candidate.createdAtMilliseconds,
                  transportStepCount: transportStepCount
                )
              )
              didChangeLifecycle = true
              didMakeNonSendingProgress = true
              didCreateSynchronizationBlocker = true
              break candidateLoop
            }
            guard automaticDeliveryStepCountFits(
              transportStepCount,
              admittedStepCount: admittedStepCount,
              remainingStepCount: remainingStepCount
            ) else { break }
          }
          guard bodyDecodeCount < request.maximumBodyDecodeCount else { break }
          if candidate.encodedBodyByteCount > request.maximumEncodedBodyByteCount {
            failedMutations.append(
              try quarantineOversizedOutboxMutationWithoutTransaction(
                id: candidate.mutationID,
                createdAtMilliseconds: candidate.createdAtMilliseconds,
                encodedBodyByteCount: candidate.encodedBodyByteCount,
                maximumEncodedBodyByteCount: request.maximumEncodedBodyByteCount
              )
            )
            didChangeLifecycle = true
            didMakeNonSendingProgress = true
            didCreateSynchronizationBlocker = true
            break candidateLoop
          }
          let fitsByteBudget =
            bodyByteCount <= remainingBodyByteCount
            && candidate.encodedBodyByteCount
              <= remainingBodyByteCount - bodyByteCount
          guard fitsByteBudget else { break }
          guard let row = try loadOutboxBodyRowWithoutTransaction(id: candidate.mutationID)
          else { continue }

          bodyDecodeCount += 1
          bodyByteCount += candidate.encodedBodyByteCount
          decodedOutboxBodyCount += 1
          decodedOutboxBodyByteCount += candidate.encodedBodyByteCount
          let candidatePosition = InstantOutboxDeliveryPosition(
            createdAtMilliseconds: row.createdAtMilliseconds,
            mutationID: row.mutationID
          )
          do {
            let mutation: PendingMutation = try decodeOutboxBody(row.json)
            guard mutation.id == row.mutationID else {
              failedMutations.append(
                try quarantineInvalidOutboxMutationWithoutTransaction(
                  row,
                  reason: "The durable mutation id did not match its SQLite row id."
                )
              )
              didChangeLifecycle = true
              didMakeNonSendingProgress = true
              didCreateSynchronizationBlocker = true
              break candidateLoop
            }
            let deliveryState = durableDeliveryState(
              for: mutation,
              hasServerAcceptance: try hasStoredServerAcceptance(mutation, in: row)
            )
            if deliveryState != .needsDelivery {
              if candidate.metadataVersion < InstantOutboxDeliveryMetadata.currentVersion {
                try saveOutboxDeliveryMetadataWithoutTransaction(mutation)
              }
              // Server acceptance is authoritative for delivery. A legacy
              // accepted row with an ambiguous local-effect receipt must stay
              // unsent and must not be rewritten as a failed mutation.
              didMakeNonSendingProgress = true
              continue
            }
            guard mutation.provesReplayableOptimisticEffectReceipt,
              try hasStoredPreparedOptimisticEffectReceipt(mutation, in: row)
            else {
              failedMutations.append(
                try quarantineInvalidOutboxMutationWithoutTransaction(
                  row,
                  reason:
                    "The durable mutation has no SQLite-owned Runtime-prepared optimistic-effect receipt and cannot enter a network-delivery claim."
                )
              )
              didChangeLifecycle = true
              didMakeNonSendingProgress = true
              didCreateSynchronizationBlocker = true
              break candidateLoop
            }
            if candidate.metadataVersion < InstantOutboxDeliveryMetadata.currentVersion {
              try saveOutboxDeliveryMetadataWithoutTransaction(mutation)
              didMakeNonSendingProgress = true
            }
            let transportStepCount = InstantOutboxDeliveryMetadata.stepCount(in: mutation)
            if transportStepCount > InstantAutomaticOutboxClaimLimits.maximumStepCount {
              failedMutations.append(
                try quarantineOverLimitStepOutboxMutationWithoutTransaction(
                  id: candidate.mutationID,
                  createdAtMilliseconds: candidate.createdAtMilliseconds,
                  transportStepCount: transportStepCount
                )
              )
              didChangeLifecycle = true
              didMakeNonSendingProgress = true
              didCreateSynchronizationBlocker = true
              break candidateLoop
            }
            guard automaticDeliveryStepCountFits(
              transportStepCount,
              admittedStepCount: admittedStepCount,
              remainingStepCount: remainingStepCount
            ) else {
              // This normalized row remains the ordered ready barrier. Because
              // it is outside the current claim, active-overlay successor proof
              // below includes its write keys.
              break
            }
            try claimOutboxMutationWithoutTransaction(
              id: mutation.id,
              claimantID: request.claimantID,
              claimToken: request.claimToken,
              deadlineMilliseconds: request.requiresExclusiveLane
                ? request.now.milliseconds
                  + InstantAutomaticOutboxClaimLimits.claimTimeoutMilliseconds
                : InstantMutationAcknowledgementDeadlinePolicy.deadlineMilliseconds(
                  after: request.now,
                  inFlightOrdinal: claimedCount + mutations.count + 1
                ),
              projectedBodyByteCount: candidate.encodedBodyByteCount,
              payloadFingerprint: try mutation.mutationWireIntentFingerprint()
            )
            mutations.append(mutation)
            deliveryStartedBeforeClaimByMutationID[mutation.id] = candidate.deliveryStarted
            admittedStepCount += transportStepCount
            admittedBodyByteCount += candidate.encodedBodyByteCount
            if firstSelectedPosition == nil {
              firstSelectedPosition = candidatePosition
            }
          } catch {
            failedMutations.append(
              try quarantineInvalidOutboxMutationWithoutTransaction(
                row,
                reason: "The durable mutation body could not be decoded: \(error)"
              )
            )
            didChangeLifecycle = true
            didMakeNonSendingProgress = true
            didCreateSynchronizationBlocker = true
            InstantDiagnostics.shared.record(
              error: error,
              subsystem: "instant-swift-data-core",
              category: "outbox",
              event: "outbox.mutation.body-invalid",
              message: "Skipped one malformed durable mutation body while claiming a bounded delivery window.",
              metadata: ["mutationID": row.mutationID],
              correlationID: row.mutationID
            )
            break candidateLoop
          }
        }
      }

      if didCreateSynchronizationBlocker {
        // Quarantine retained an active local owner but revoked the receipt
        // needed to peel it safely. No row admitted by this request may escape
        // to transport after that boundary is created. Restore each exact
        // preclaim offer bit while leaving older/foreign claims untouched.
        for mutation in mutations {
          try releaseUnofferedOutboxClaimWithoutTransaction(
            id: mutation.id,
            claimToken: request.claimToken,
            deliveryStarted: deliveryStartedBeforeClaimByMutationID[
              mutation.id,
              default: true
            ]
          )
        }
        mutations.removeAll(keepingCapacity: true)
        firstSelectedPosition = nil
      }

      let selectedWriteKeys = InstantVisibleWriteFilter.writeKeys(in: mutations)
      var visibleWriteFilter = try loadVisibleWriteFilterWithoutTransaction(
        for: selectedWriteKeys
      )
      let hasUnknownSuccessorWriteKeys = try firstSelectedPosition.map {
        try hasUnknownActiveOverlayAfterWithoutTransaction(
          $0,
          excludingClaimToken: request.claimToken
        )
      } ?? false
      var successorWriteKeys: Set<InstantVisibleWriteKey> = []
      if let firstSelectedPosition, !hasUnknownSuccessorWriteKeys {
        for key in selectedWriteKeys
        where try hasActiveOverlayWriteKeyAfterWithoutTransaction(
          key,
          position: firstSelectedPosition,
          excludingClaimToken: request.claimToken
        ) {
          successorWriteKeys.insert(key)
        }
      }

      let projectionCandidates = InstantBoundedOutboxDelivery.projectionCandidates(
        mutations: mutations,
        successorWriteKeys: successorWriteKeys,
        hasUnknownSuccessorWriteKeys: hasUnknownSuccessorWriteKeys
      )
      var admittedMutations: [PendingMutation] = []
      var projectedMutations: [PendingMutation] = []
      var didDeferProjectedSuffix = false
      admittedMutations.reserveCapacity(projectionCandidates.count)
      projectedMutations.reserveCapacity(projectionCandidates.count)
      admittedBodyByteCount = 0

      for candidate in projectionCandidates {
        if didDeferProjectedSuffix {
          try releaseUnofferedOutboxClaimWithoutTransaction(
            id: candidate.mutation.id,
            claimToken: request.claimToken,
            deliveryStarted: deliveryStartedBeforeClaimByMutationID[
              candidate.mutation.id,
              default: true
            ]
          )
          continue
        }

        let metadata = try InstantBoundedOutboxDelivery.projectionMetadata(
          for: candidate,
          visibleWriteFilter: visibleWriteFilter
        )
        guard metadata.encodedBodyByteCount >= 0 else {
          throw persistenceError(
            operation: "measure projected outbox mutation",
            message: "Projected mutation bytes cannot be negative."
          )
        }
        if metadata.encodedBodyByteCount > request.maximumEncodedBodyByteCount {
          let message =
            "Instant could not deliver mutation '\(candidate.mutation.id)' because its projected pending body encodes to \(metadata.encodedBodyByteCount) bytes, exceeding the \(request.maximumEncodedBodyByteCount)-byte automatic-delivery limit."
          failedMutations.append(
            try failClaimedOutboxMutationWithoutTransaction(
              candidate.mutation,
              failure: InstantMutationFailure(code: .validationFailed, message: message),
              failureAttributeRevision: nil,
              claimToken: request.claimToken
            )
          )
          didChangeLifecycle = true
          didMakeNonSendingProgress = true
          InstantDiagnostics.shared.record(
            .error,
            subsystem: "instant-swift-data-core",
            category: "outbox",
            event: "outbox.mutation.projected-body-oversized",
            message: message,
            metadata: [
              "mutationID": candidate.mutation.id,
              "projectedBodyByteCount": String(metadata.encodedBodyByteCount),
              "maximumEncodedBodyByteCount": String(
                request.maximumEncodedBodyByteCount
              ),
            ],
            correlationID: candidate.mutation.id
          )
          continue
        }

        let fitsProjectedWindow =
          admittedBodyByteCount <= remainingBodyByteCount
          && metadata.encodedBodyByteCount
            <= remainingBodyByteCount - admittedBodyByteCount
        guard fitsProjectedWindow else {
          didDeferProjectedSuffix = true
          try releaseUnofferedOutboxClaimWithoutTransaction(
            id: candidate.mutation.id,
            claimToken: request.claimToken,
            deliveryStarted: deliveryStartedBeforeClaimByMutationID[
              candidate.mutation.id,
              default: true
            ]
          )
          continue
        }

        var hydratedScalars: [InstantVisibleWriteKey: InstantTriple] = [:]
        hydratedScalars.reserveCapacity(metadata.requiredScalarKeys.count)
        for key in metadata.requiredScalarKeys.sorted(by: {
          if $0.entityID != $1.entityID { return $0.entityID < $1.entityID }
          return $0.attributeID < $1.attributeID
        }) {
          guard
            let timestamp = visibleWriteFilter.requiredScalarTimestamp(for: key),
            let encodedValueByteCount =
              visibleWriteFilter.requiredScalarEncodedValueByteCount(for: key)
          else {
            throw persistenceError(
              operation: "hydrate projected outbox mutation",
              message: "Required-scalar metadata disappeared inside one claim."
            )
          }
          hydratedScalars[key] = try loadVisibleRequiredScalarWithoutTransaction(
            for: key,
            timestamp: timestamp,
            encodedValueByteCount: encodedValueByteCount
          )
        }
        let hydratedFilter = visibleWriteFilter.hydratingRequiredScalars(hydratedScalars)
        let projectedMutation = InstantBoundedOutboxDelivery.projectedPendingMutation(
          candidate,
          visibleWriteFilter: hydratedFilter
        )
        let encodedProjectedBodyByteCount = try InstantBoundedOutboxDelivery
          .encodedProjectedBodyByteCount(projectedMutation)
        guard encodedProjectedBodyByteCount == metadata.encodedBodyByteCount else {
          throw persistenceError(
            operation: "measure projected outbox mutation",
            message:
              "Metadata-first projected bytes did not match exact sorted-key encoding."
          )
        }
        try updateProjectedOutboxClaimByteCountWithoutTransaction(
          id: candidate.mutation.id,
          claimToken: request.claimToken,
          projectedBodyByteCount: encodedProjectedBodyByteCount,
          payloadFingerprint: try projectedMutation.mutationWireIntentFingerprint()
        )
        visibleWriteFilter = hydratedFilter
        admittedMutations.append(candidate.mutation)
        projectedMutations.append(projectedMutation)
        admittedBodyByteCount += encodedProjectedBodyByteCount
      }

      mutations = admittedMutations
      admittedStepCount = mutations.reduce(into: 0) { count, mutation in
        count += InstantOutboxDeliveryMetadata.stepCount(in: mutation)
      }
      let resultingOutboxRevision = didChangeLifecycle
        ? try bumpMetadataRevisionWithoutTransaction(Self.outboxRevisionKey)
        : startingRevisions.outbox
      let resultingRevisions = InstantPersistenceRevisions(
        store: startingRevisions.store,
        outbox: resultingOutboxRevision
      )
      let hasContinuationCandidate = try hasAutomaticDeliveryCandidateWithoutTransaction()
      let claimedAfterThisPass = claimedCount + mutations.count
      let claimedStepsAfterThisPass = claimedStepCount + admittedStepCount
      let claimedBodyBytesAfterThisPass = claimedBodyByteCount + admittedBodyByteCount
      let hasRemainingClaimCapacity =
        claimedAfterThisPass < request.maximumMutationCount
        && claimedStepsAfterThisPass < request.maximumStepCount
        && claimedBodyBytesAfterThisPass < request.maximumEncodedBodyByteCount
      let shouldContinueImmediately =
        !didCreateSynchronizationBlocker
        && didMakeNonSendingProgress && !didDeferProjectedSuffix
        && hasRemainingClaimCapacity && hasContinuationCandidate
      let nextClaimDeadlineMilliseconds = try minimumOutboxClaimDeadlineWithoutTransaction()
      let synchronizationBlocker: InstantSynchronizationBlocker? =
        if didCreateSynchronizationBlocker {
          try synchronizationBlockerWithoutTransaction()
            ?? InstantSynchronizationBlocker(
              reason: .unknownOptimisticEffectReceipt,
              firstMutationID: failedMutations.last?.id ?? "unknown",
              blockedMutationCount: 1
            )
        } else {
          nil
        }

      maximumAutomaticOutboxWindowBodyCount = max(
        maximumAutomaticOutboxWindowBodyCount,
        bodyDecodeCount
      )
      maximumAutomaticOutboxWindowBodyByteCount = max(
        maximumAutomaticOutboxWindowBodyByteCount,
        bodyByteCount
      )
      InstantDiagnostics.shared.record(
        .trace,
        subsystem: "instant-swift-data-core",
        category: "outbox",
        event: "outbox.automatic-claim.completed",
        message: "Instant completed one bounded durable automatic-delivery claim.",
        metadata: [
          "decodedBodyCount": String(bodyDecodeCount),
          "decodedBodyByteCount": String(bodyByteCount),
          "claimedMutationCount": String(mutations.count),
          "claimedStepCount": String(admittedStepCount),
          "claimedEncodedBodyByteCount": String(admittedBodyByteCount),
          "alreadyClaimedMutationCount": String(claimedCount),
          "alreadyClaimedStepCount": String(claimedStepCount),
          "alreadyClaimedEncodedBodyByteCount": String(claimedBodyByteCount),
          "quarantinedMutationCount": String(failedMutations.count),
          "shouldContinueImmediately": String(shouldContinueImmediately),
          "nextClaimDeadlineMilliseconds": nextClaimDeadlineMilliseconds.map(String.init)
            ?? "none",
        ]
      )
      return InstantAutomaticOutboxClaimWindow(
        mutations: mutations.sorted(by: PendingMutation.creationOrder),
        projectedMutations: projectedMutations.sorted(by: PendingMutation.creationOrder),
        failedMutations: failedMutations.sorted(by: PendingMutation.creationOrder),
        successorWriteKeys: successorWriteKeys,
        hasUnknownSuccessorWriteKeys: hasUnknownSuccessorWriteKeys,
        visibleWriteFilter: visibleWriteFilter,
        resultingRevisions: resultingRevisions,
        claimToken: mutations.isEmpty ? nil : request.claimToken,
        reclaimedMutationIDs: reclaimedMutationIDs,
        nextClaimDeadlineMilliseconds: nextClaimDeadlineMilliseconds,
        shouldContinueImmediately: shouldContinueImmediately,
        decodedBodyCount: bodyDecodeCount,
        decodedBodyByteCount: bodyByteCount,
        synchronizationBlocker: synchronizationBlocker
      )
    }
    if let blocker = window.synchronizationBlocker {
      cachedState = nil
      throw blocker.error(operation: operation)
    }
    return window
  }

  @discardableResult
  func releaseAutomaticOutboxClaim(token: String) throws -> Set<String> {
    guard !token.isEmpty else { return [] }
    return try transaction {
      let ids = Set(try selectStrings(
        """
        SELECT mutation_id FROM instant_outbox
        WHERE delivery_claim_state = ? AND delivery_claim_token = ?
        ORDER BY created_at_ms, mutation_id
        """,
        [
          .text(InstantOutboxDeliveryClaimState.claimed.rawValue),
          .text(token),
        ]
      ))
      try execute(
        """
        UPDATE instant_outbox
        SET delivery_claim_state = ?, delivery_claim_token = NULL,
            delivery_claimant_id = NULL, delivery_claim_deadline_ms = NULL,
            delivery_claim_projected_body_bytes = NULL,
            delivery_claim_payload_fingerprint = NULL
        WHERE delivery_claim_state = ? AND delivery_claim_token = ?
        """,
        [
          .text(InstantOutboxDeliveryClaimState.ready.rawValue),
          .text(InstantOutboxDeliveryClaimState.claimed.rawValue),
          .text(token),
        ]
      )
      return ids
    }
  }

  /// Releases every automatic-delivery claim owned by one runtime after its
  /// socket closes. A durable claim belongs to the socket that admitted it:
  /// carrying that claim across reconnect would make an already-known dead
  /// session block delivery until the five-second lease expires.
  func releaseAutomaticOutboxClaims(
    claimantID: String
  ) throws -> InstantAutomaticOutboxClaimRelease {
    guard !claimantID.isEmpty else {
      return InstantAutomaticOutboxClaimRelease(
        mutationIDs: [],
        nextClaimDeadlineMilliseconds: try readTransaction {
          try minimumOutboxClaimDeadlineWithoutTransaction()
        }
      )
    }
    return try transaction {
      let mutationIDs = Set(try selectStrings(
        """
        SELECT mutation_id FROM instant_outbox
        WHERE delivery_claim_state = ? AND delivery_claimant_id = ?
        ORDER BY created_at_ms, mutation_id
        """,
        [
          .text(InstantOutboxDeliveryClaimState.claimed.rawValue),
          .text(claimantID),
        ]
      ))
      try execute(
        """
        UPDATE instant_outbox
        SET delivery_claim_state = ?, delivery_claim_token = NULL,
            delivery_claimant_id = NULL, delivery_claim_deadline_ms = NULL,
            delivery_claim_projected_body_bytes = NULL,
            delivery_claim_payload_fingerprint = NULL
        WHERE delivery_claim_state = ? AND delivery_claimant_id = ?
        """,
        [
          .text(InstantOutboxDeliveryClaimState.ready.rawValue),
          .text(InstantOutboxDeliveryClaimState.claimed.rawValue),
          .text(claimantID),
        ]
      )
      return InstantAutomaticOutboxClaimRelease(
        mutationIDs: mutationIDs,
        nextClaimDeadlineMilliseconds: try minimumOutboxClaimDeadlineWithoutTransaction()
      )
    }
  }

  /// Releases one retryable server response only while this runtime still owns
  /// the durable claim. The claimant predicate prevents a late socket event
  /// from releasing a row another runtime reclaimed after the five-second
  /// deadline.
  @discardableResult
  func releaseAutomaticOutboxClaim(
    id: String,
    claimantID: String
  ) throws -> Bool {
    guard !id.isEmpty, !claimantID.isEmpty else { return false }
    return try transaction {
      try execute(
        """
        UPDATE instant_outbox
        SET delivery_claim_state = ?, delivery_claim_token = NULL,
            delivery_claimant_id = NULL, delivery_claim_deadline_ms = NULL,
            delivery_claim_projected_body_bytes = NULL,
            delivery_claim_payload_fingerprint = NULL
        WHERE mutation_id = ? AND delivery_claim_state = ?
          AND delivery_claimant_id = ?
        """,
        [
          .text(InstantOutboxDeliveryClaimState.ready.rawValue),
          .text(id),
          .text(InstantOutboxDeliveryClaimState.claimed.rawValue),
          .text(claimantID),
        ]
      )
      return sqlite3_changes(connection.raw) == 1
    }
  }

  /// Applies one WebSocket `transact-ok` receipt with a revision-checked row
  /// update. Only the addressed mutation body is decoded; the remaining outbox
  /// stays as compact identity/status metadata in memory and untouched JSON in
  /// SQLite.
  func acceptOutboxMutation(
    id: String,
    serverTransactionID: String,
    claimantID: String,
    claimToken: String?,
    expectedOutboxRevision: Int64
  ) throws -> InstantOutboxRowAcceptance? {
    let previousState = cachedState
    let acceptance: InstantOutboxRowAcceptance? = try transaction {
      guard
        try loadMetadataRevisionWithoutTransaction(Self.outboxRevisionKey)
          == expectedOutboxRevision
      else { return nil }

      guard let row = try loadOutboxBodyRowWithoutTransaction(id: id) else {
        return InstantOutboxRowAcceptance(
          mutation: nil,
          pendingMutationCount: Int(try selectInt64(
            "SELECT COUNT(*) FROM instant_outbox WHERE status = ?",
            [.text(InstantMutationStatus.pending.rawValue)]
          )),
          didChange: false,
          nextClaimDeadlineMilliseconds: try minimumOutboxClaimDeadlineWithoutTransaction()
        )
      }
      var mutation: PendingMutation = try decodeOutboxBody(row.json)
      decodedOutboxBodyCount += 1
      decodedOutboxBodyByteCount += row.json.utf8.count
      guard mutation.id == id else {
        throw persistenceError(
          operation: "accept outbox mutation",
          message: "The durable mutation id did not match row '\(id)'."
        )
      }

      let hasPreparedMaterializedEffect = try hasStoredPreparedOptimisticEffectReceipt(
        mutation,
        in: row
      )
      let alreadyAccepted = try hasStoredServerAcceptance(mutation, in: row)
      if !alreadyAccepted {
        guard let claimPayloadFingerprint = row.deliveryClaimPayloadFingerprint,
          let claimToken,
          let materializedEffectFingerprint = try mutation.optimisticEffectReceiptFingerprint()
        else {
          return InstantOutboxRowAcceptance(
            mutation: mutation,
            pendingMutationCount: Int(try selectInt64(
              "SELECT COUNT(*) FROM instant_outbox WHERE status = ?",
              [.text(InstantMutationStatus.pending.rawValue)]
            )),
            didChange: false,
            nextClaimDeadlineMilliseconds: try minimumOutboxClaimDeadlineWithoutTransaction()
          )
        }
        let ownsExactClaim: Bool
        if hasPreparedMaterializedEffect {
          ownsExactClaim = try selectInt64(
            """
            SELECT EXISTS(
              SELECT 1 FROM instant_outbox
              WHERE mutation_id = ? AND delivery_claim_state = ?
                AND delivery_claim_payload_fingerprint = ?
                AND delivery_claimant_id = ?
                AND delivery_claim_token = ?
                AND optimistic_effect_receipt_fingerprint = ?
              LIMIT 1
            )
            """,
            [
              .text(id),
              .text(InstantOutboxDeliveryClaimState.claimed.rawValue),
              .text(claimPayloadFingerprint),
              .text(claimantID),
              .text(claimToken),
              .text(materializedEffectFingerprint),
            ]
          ) != 0
        } else {
          ownsExactClaim = false
        }
        guard ownsExactClaim else {
          return InstantOutboxRowAcceptance(
            mutation: mutation,
            pendingMutationCount: Int(try selectInt64(
              "SELECT COUNT(*) FROM instant_outbox WHERE status = ?",
              [.text(InstantMutationStatus.pending.rawValue)]
            )),
            didChange: false,
            nextClaimDeadlineMilliseconds: try minimumOutboxClaimDeadlineWithoutTransaction()
          )
        }
        mutation.status = .confirmed
        mutation.failureMessage = nil
        mutation.failure = nil
        mutation.serverTransactionID = serverTransactionID
        mutation.confirmationSource = .webSocketTransactOK
        let encodedBody = try encode(mutation)
        try execute(
          """
          UPDATE instant_outbox
          SET status = ?, delivery_state = ?, delivery_metadata_version = ?,
              transport_step_count = ?, encoded_body_bytes = ?, delivery_started = 1,
              lifecycle_json = ?, failure_message = NULL, confirmation_proven = 1,
              optimistic_overlay_active = ?, delivery_claim_state = ?,
              server_transaction_id = ?, confirmation_source = ?,
              mutation_revision = mutation_revision + 1,
              delivery_claim_token = NULL, delivery_claimant_id = NULL,
              delivery_claim_deadline_ms = NULL,
              delivery_claim_projected_body_bytes = NULL,
              delivery_claim_payload_fingerprint = NULL,
              server_acceptance_payload_fingerprint = ?, json = ?
          WHERE mutation_id = ? AND delivery_claim_state = ?
            AND delivery_claim_payload_fingerprint = ?
            AND delivery_claimant_id = ?
            AND delivery_claim_token = ?
          """,
          [
            .text(mutation.status.rawValue),
            .text(InstantOutboxDeliveryState.serverAccepted.rawValue),
            .int(Int64(InstantOutboxDeliveryMetadata.currentVersion)),
            .int(Int64(InstantOutboxDeliveryMetadata.stepCount(in: mutation))),
            .int(Int64(encodedBody.utf8.count)),
            .text(try encode(mutation.compactedForMemory)),
            .int(mutation.optimisticOverlayState == .removed ? 0 : 1),
            .text(InstantOutboxDeliveryClaimState.ready.rawValue),
            .text(serverTransactionID),
            .text(InstantMutationConfirmationSource.webSocketTransactOK.rawValue),
            .text(claimPayloadFingerprint),
            .text(encodedBody),
            .text(mutation.id),
            .text(InstantOutboxDeliveryClaimState.claimed.rawValue),
            .text(claimPayloadFingerprint),
            .text(claimantID),
            .text(claimToken),
          ]
        )
        guard sqlite3_changes(connection.raw) == 1 else { return nil }
        try replaceOutboxWriteKeysWithoutTransaction(for: mutation)
        try saveMutationLifecycleWithoutTransaction(mutation)
        _ = try bumpMetadataRevisionWithoutTransaction(Self.outboxRevisionKey)
      }
      return InstantOutboxRowAcceptance(
        mutation: mutation,
        pendingMutationCount: Int(try selectInt64(
          "SELECT COUNT(*) FROM instant_outbox WHERE status = ?",
          [.text(InstantMutationStatus.pending.rawValue)]
        )),
        didChange: !alreadyAccepted,
        nextClaimDeadlineMilliseconds: try minimumOutboxClaimDeadlineWithoutTransaction()
      )
    }

    guard let acceptance else { return nil }
    if acceptance.didChange, var previousState,
      previousState.outboxRevision == expectedOutboxRevision,
      acceptance.mutation != nil
    {
      previousState.snapshot.outbox = []
      previousState.outboxRevision += 1
      // `previousState` is already the actor's memory-thinned cache, and the
      // addressed mutation was compacted above. Avoid forcing SQLite to shrink
      // its page cache once per acknowledgement while a receipt burst drains.
      cachedState = previousState
    } else if acceptance.didChange {
      cachedState = nil
    }
    return acceptance
  }

  /// Applies a caller's local confirmation to one addressed row. This is the
  /// normal receive-path counterpart to `acceptOutboxMutation`; it must never
  /// reconstruct unrelated durable mutation bodies.
  func confirmOutboxMutationIfPresent(
    id: String,
    expectedOutboxRevision: Int64
  ) throws -> InstantOutboxRowAcceptance? {
    let previousState = cachedState
    let confirmation: InstantOutboxRowAcceptance? = try transaction {
      guard try loadMetadataRevisionWithoutTransaction(Self.outboxRevisionKey)
        == expectedOutboxRevision
      else { return nil }
      guard let row = try loadOutboxBodyRowWithoutTransaction(id: id) else {
        return InstantOutboxRowAcceptance(
          mutation: nil,
          pendingMutationCount: Int(try selectInt64(
            "SELECT COUNT(*) FROM instant_outbox WHERE status = ?",
            [.text(InstantMutationStatus.pending.rawValue)]
          )),
          didChange: false,
          nextClaimDeadlineMilliseconds: try minimumOutboxClaimDeadlineWithoutTransaction()
        )
      }
      let mutation: PendingMutation = try decodeOutboxBody(row.json)
      decodedOutboxBodyCount += 1
      decodedOutboxBodyByteCount += row.json.utf8.count
      guard mutation.id == id,
        let update = InstantOutbox.confirming(id: id, in: [mutation])
      else {
        throw persistenceError(
          operation: "confirm addressed outbox mutation",
          message: "The durable confirmation body did not match row '\(id)'."
        )
      }
      try saveOutboxMutationWithoutTransaction(
        update.mutation,
        receiptWriteAuthority: .publicPersistence
      )
      _ = try bumpMetadataRevisionWithoutTransaction(Self.outboxRevisionKey)
      return InstantOutboxRowAcceptance(
        mutation: update.mutation,
        pendingMutationCount: Int(try selectInt64(
          "SELECT COUNT(*) FROM instant_outbox WHERE status = ?",
          [.text(InstantMutationStatus.pending.rawValue)]
        )),
        didChange: true,
        nextClaimDeadlineMilliseconds: try minimumOutboxClaimDeadlineWithoutTransaction()
      )
    }
    guard let confirmation else { return nil }
    if confirmation.didChange, var previousState,
      previousState.outboxRevision == expectedOutboxRevision
    {
      previousState.snapshot.outbox = []
      previousState.outboxRevision += 1
      // `previousState` is already the body-free compact cache. Keep the
      // separately materialized store resident and avoid shrinking SQLite for
      // every addressed local acknowledgement.
      cachedState = previousState
    } else if confirmation.didChange {
      cachedState = nil
    }
    return confirmation
  }

  func loadOutboxMutations(
    statuses: [InstantMutationStatus],
    ids: [String]? = nil,
    limit: Int? = nil,
    expectedStoreRevision: Int64? = nil,
    expectedOutboxRevision: Int64
  ) throws -> [PendingMutation]? {
    let statuses = Array(Set(statuses.map(\.rawValue))).sorted()
    let ids = ids.map { Array(Set($0)).sorted() }
    if ids == nil, limit == nil {
      localMutationQueueWideReadCount += 1
    }
    let loaded: (mutations: [PendingMutation], didQuarantine: Bool)? = try transaction {
      if let expectedStoreRevision,
        try loadMetadataRevisionWithoutTransaction(Self.storeRevisionKey)
          != expectedStoreRevision
      {
        return nil
      }
      guard try loadMetadataRevisionWithoutTransaction(Self.outboxRevisionKey)
        == expectedOutboxRevision
      else {
        return nil
      }
      guard !statuses.isEmpty, ids?.isEmpty != true, limit != 0 else {
        return ([], false)
      }
      let statusPlaceholders = Array(repeating: "?", count: statuses.count)
        .joined(separator: ", ")
      var sql =
        "SELECT mutation_id FROM instant_outbox WHERE status IN (\(statusPlaceholders))"
      var bindings = statuses.map(SQLiteBinding.text)
      if let ids {
        let idPlaceholders = Array(repeating: "?", count: ids.count).joined(separator: ", ")
        sql += " AND mutation_id IN (\(idPlaceholders))"
        bindings.append(contentsOf: ids.map(SQLiteBinding.text))
      }
      sql += " ORDER BY created_at_ms, mutation_id"
      if let limit {
        sql += " LIMIT ?"
        bindings.append(.int(Int64(limit)))
      }
      let mutationIDs = try selectStrings(sql, bindings)
      var mutations: [PendingMutation] = []
      mutations.reserveCapacity(mutationIDs.count)
      var didQuarantine = false
      for mutationID in mutationIDs {
        guard let row = try loadOutboxBodyRowWithoutTransaction(id: mutationID) else { continue }
        decodedOutboxBodyCount += 1
        decodedOutboxBodyByteCount += row.json.utf8.count
        do {
          let mutation: PendingMutation = try decodeOutboxBody(row.json)
          guard mutation.id == row.mutationID else {
            throw persistenceError(
              operation: "inspect durable outbox mutation",
              message: "The durable mutation id did not match its SQLite row id."
            )
          }
          mutations.append(mutation)
        } catch {
          let quarantined = try quarantineInvalidOutboxMutationWithoutTransaction(
            row,
            reason: "The durable mutation body could not be decoded during public inspection: \(error)"
          )
          didQuarantine = true
          if statuses.contains(InstantMutationStatus.failed.rawValue) {
            mutations.append(quarantined)
          }
        }
      }
      if didQuarantine {
        _ = try bumpMetadataRevisionWithoutTransaction(Self.outboxRevisionKey)
      }
      return (mutations, didQuarantine)
    }
    if loaded?.didQuarantine == true {
      cachedState = nil
    }
    return loaded?.mutations
  }

  func loadStateWithSource(
    installedStoreRevision: Int64? = nil,
    installedAttributeRevision: Int64? = nil
  ) throws -> InstantPersistenceStateLoad {
    let startupStopwatch = didTraceInitialStateLoad
      ? nil
      : startupTrace.started(
        "sqlite.state-load",
        metadata: ["file": fileURL.lastPathComponent]
      )
    let startedAt = Date()
    do {
      let loaded = try readTransaction {
        let storeRevision = try loadMetadataRevisionWithoutTransaction(Self.storeRevisionKey)
        let attributeRevision = try loadMetadataRevisionWithoutTransaction(
          Self.attributeRevisionKey
        )
        let outboxRevision = try loadMetadataRevisionWithoutTransaction(Self.outboxRevisionKey)
        let queryResultRevision = try loadMetadataRevisionWithoutTransaction(
          Self.queryResultRevisionKey
        )
        if let cachedState,
          cachedState.storeRevision == storeRevision,
          cachedState.attributeRevision == attributeRevision,
          cachedState.outboxRevision == outboxRevision,
          cachedState.queryResultRevision == queryResultRevision
        {
          let storeAdoption: InstantPersistenceStoreAdoption
          if let installedStoreRevision, installedStoreRevision != storeRevision {
            // A public persistence inspection may have advanced this actor's
            // compact cache without updating its owning runtime's hot store.
            // Re-read the materialized store exactly once for that runtime;
            // returning `.none` here would let a closed query validate stale
            // cached rows against stale indexes.
            cacheResidencyMetrics.fullStateReconstructionCount += 1
            storeAdoption = .snapshot(try loadStoreSnapshotWithoutTransaction())
          } else if let installedAttributeRevision,
            installedAttributeRevision != attributeRevision
          {
            storeAdoption = .attributes(cachedState.snapshot.store.attributes)
          } else {
            storeAdoption = .none
          }
          // The RAM cache holds the materialized store only. SQLite remains the
          // outbox authority; callers that need mutation bodies load addressed rows.
          return InstantPersistenceStateLoad(
            state: cachedState,
            source: .memory,
            storeAdoption: storeAdoption
          )
        }

        let store: InstantStoreSnapshot
        let source: InstantPersistenceStateSource
        let storeAdoption: InstantPersistenceStoreAdoption
        if var cachedMaterializedStore,
          cachedMaterializedStore.storeRevision == storeRevision
        {
          if let installedStoreRevision, installedStoreRevision != storeRevision {
            // `cachedMaterializedStore` is revision metadata plus a deliberately
            // thinned snapshot in normal operation. A direct persistence read
            // can advance it without advancing the owning runtime's hot
            // TripleIndexes, so matching the SQLite revision here does not
            // prove that the runtime has installed this store.
            cacheResidencyMetrics.fullStateReconstructionCount += 1
            store = try loadStoreSnapshotWithoutTransaction()
            source = .sqlite
            storeAdoption = .snapshot(store)
          } else if cachedMaterializedStore.attributeRevision == attributeRevision {
            store = cachedMaterializedStore.snapshot
            source = .memory
            if let installedAttributeRevision,
              installedAttributeRevision != attributeRevision
            {
              storeAdoption = .attributes(cachedMaterializedStore.snapshot.attributes)
            } else {
              storeAdoption = .none
            }
          } else {
            let attributes = try loadAttributesWithoutTransaction(
              tracesStartupCollection: false
            )
            cachedMaterializedStore.snapshot.attributes = attributes
            cachedMaterializedStore.attributeRevision = attributeRevision
            self.cachedMaterializedStore = cachedMaterializedStore
            store = cachedMaterializedStore.snapshot
            source = .sqlite
            storeAdoption = .attributes(attributes)
          }
        } else {
          cacheResidencyMetrics.fullStateReconstructionCount += 1
          store = try loadStoreSnapshotWithoutTransaction()
          source = .sqlite
          storeAdoption = .snapshot(store)
        }
        return InstantPersistenceStateLoad(
          state: InstantPersistenceState(
            snapshot: InstantPersistenceSnapshot(store: store, outbox: []),
            storeRevision: storeRevision,
            outboxRevision: outboxRevision,
            attributeRevision: attributeRevision,
            queryResultRevision: queryResultRevision
          ),
          source: source,
          storeAdoption: storeAdoption
        )
      }
      let state = loaded.state
      if loaded.source != .memory || cachedState != state {
        adoptCachedState(
          state,
          shrinkingSQLiteMemory: loaded.source == .sqlite
        )
      }
      InstantDiagnostics.shared.record(
        .trace,
        subsystem: "instant-swift-data-core",
        category: "persistence",
        event: "sqlite.state-loaded",
        message: "Loaded the Instant cache state.",
        metadata: [
          "attributeCount": String(state.snapshot.store.attributes.count),
          "tripleCount": String(state.snapshot.store.triples.count),
          "outboxCount": String(state.snapshot.outbox.count),
          "storeRevision": String(state.storeRevision),
          "attributeRevision": String(state.attributeRevision),
          "outboxRevision": String(state.outboxRevision),
          "queryResultRevision": String(state.queryResultRevision),
          "source": loaded.source == .memory ? "memory" : "sqlite",
          "durationMilliseconds": String(
            Int64((Date().timeIntervalSince(startedAt) * 1_000).rounded())
          ),
        ]
      )
      if let startupStopwatch {
        didTraceInitialStateLoad = true
        startupTrace.completed(
          "sqlite.state-load",
          since: startupStopwatch,
          metadata: [
            "attributeCount": String(state.snapshot.store.attributes.count),
            "tripleCount": String(state.snapshot.store.triples.count),
            "outboxCount": String(state.snapshot.outbox.count),
            "source": loaded.source == .memory ? "memory" : "sqlite",
          ]
        )
      }
      return loaded
    } catch {
      if let startupStopwatch {
        startupTrace.failed(
          "sqlite.state-load",
          error: error,
          since: startupStopwatch,
          metadata: ["file": fileURL.lastPathComponent]
        )
      }
      InstantDiagnostics.shared.record(
        error: error,
        subsystem: "instant-swift-data-core",
        category: "persistence",
        event: "sqlite.state-load-failed",
        message: "Failed to load the Instant cache state.",
        metadata: ["path": fileURL.path]
      )
      throw error
    }
  }

  private func loadSnapshotWithoutTransaction(
    tracesStartupCollections: Bool = true
  ) throws -> InstantPersistenceSnapshot {
    InstantPersistenceSnapshot(
      store: try loadStoreSnapshotWithoutTransaction(
        tracesStartupCollections: tracesStartupCollections
      ),
      outbox: try loadOutboxWithoutTransaction(
        tracesStartupCollections: tracesStartupCollections
      )
    )
  }

  private func loadCompactSnapshotWithoutTransaction() throws -> InstantPersistenceSnapshot {
    cacheResidencyMetrics.fullStateReconstructionCount += 1
    return InstantPersistenceSnapshot(
      store: try loadStoreSnapshotWithoutTransaction(),
      outbox: []
    )
  }

  private func loadStoreSnapshotWithoutTransaction(
    tracesStartupCollections: Bool = true
  ) throws -> InstantStoreSnapshot {
    cacheResidencyMetrics.fullStoreSnapshotLoadCount += 1
    let attributes = try loadAttributesWithoutTransaction(
      tracesStartupCollection: tracesStartupCollections
    )
    var triplesSQL = "SELECT json FROM instant_triples"
    var tripleBindings: [SQLiteBinding] = []
    var whereClauses: [String] = []
    if deferredValueResidency.isEnabled {
      whereClauses.append(
        "attribute_id NOT IN ("
          + Array(
            repeating: "?",
            count: deferredValueResidency.attributeIDs.count
          ).joined(separator: ", ")
          + ")"
      )
      tripleBindings = deferredValueResidency.attributeIDs.sorted().map(SQLiteBinding.text)
    }
    // TypeScript Reactor.js keeps one `result.store` per querySub, built from
    // that query's triples (`createStore(attrs, result.triples)`), plus pending
    // mutations. IndexedDB has no second full graph. SQLite Data keeps the
    // corpus on disk and SQL-selects the visible page.
    // When live-query ownership rows exist, InstantStore bootstrap loads only
    // those entity IDs plus pending outbox effect entities, after applying
    // nested include limits from the query JSON (InstaQL `$limit` per parent).
    // Empty watermark query results (zero triple rows) keep the legacy full load.
    let liveQueryTripleCount = try selectInt64(
      "SELECT COUNT(*) FROM instant_live_query_triples"
    )
    if liveQueryTripleCount > 0 {
      let retainedLiveQueryEntityIDs = try retainedLiveQueryEntityIDsWithoutTransaction(
        attributes: attributes
      )
      if retainedLiveQueryEntityIDs.isEmpty {
        whereClauses.append(
          """
          entity_id IN (
            SELECT DISTINCT entity_id FROM instant_live_query_triples
            UNION
            SELECT entity_id FROM instant_outbox_effect_entities
          )
          """
        )
      } else {
        let placeholders = Array(
          repeating: "?",
          count: retainedLiveQueryEntityIDs.count
        ).joined(separator: ", ")
        whereClauses.append(
          """
          (
            entity_id IN (\(placeholders))
            OR entity_id IN (SELECT entity_id FROM instant_outbox_effect_entities)
          )
          """
        )
        tripleBindings.append(
          contentsOf: retainedLiveQueryEntityIDs.sorted().map(SQLiteBinding.text)
        )
      }
    }
    if !whereClauses.isEmpty {
      triplesSQL += " WHERE " + whereClauses.joined(separator: " AND ")
    }
    triplesSQL += " ORDER BY entity_id, attribute_id, value_json"
    let triples: [InstantTriple] = try loadStateCollection(
      phase: "sqlite.state-load.triples",
      sql: triplesSQL,
      bindings: tripleBindings,
      tracesStartupCollection: tracesStartupCollections
    )
    return InstantStoreSnapshot(attributes: attributes, triples: triples)
  }

  private func loadAttributesWithoutTransaction(
    tracesStartupCollection: Bool
  ) throws -> [InstantAttribute] {
    let attributes: [InstantAttribute] = try loadStateCollection(
      phase: "sqlite.state-load.attributes",
      sql: "SELECT json FROM instant_attributes ORDER BY id",
      tracesStartupCollection: tracesStartupCollection
    )
    var validationAttributes = Dictionary(
      uniqueKeysWithValues: attributes.map { ($0.id, $0) }
    )
    for attribute in declaredAttributes {
      validationAttributes[attribute.id] = attribute
    }
    try deferredValueResidency.validate(attributes: Array(validationAttributes.values))
    return attributes
  }

  func loadDeferredValues(
    attributeIDs: Set<String>,
    entityIDs: Set<String>
  ) throws -> [InstantTriple] {
    let attributeIDs = attributeIDs.intersection(deferredValueResidency.attributeIDs)
    guard !attributeIDs.isEmpty, !entityIDs.isEmpty else { return [] }
    let attributePlaceholders = Array(
      repeating: "?",
      count: attributeIDs.count
    ).joined(separator: ", ")
    let entityPlaceholders = Array(
      repeating: "?",
      count: entityIDs.count
    ).joined(separator: ", ")
    let bindings = attributeIDs.sorted().map(SQLiteBinding.text)
      + entityIDs.sorted().map(SQLiteBinding.text)
    let selection: (values: [InstantTriple], batchCount: Int, encodedByteCount: Int) =
      try selectBatchedJSON(
        """
        SELECT json
        FROM instant_triples
        WHERE attribute_id IN (\(attributePlaceholders))
          AND entity_id IN (\(entityPlaceholders))
        ORDER BY entity_id, attribute_id, value_json
        """,
        bindings
      )
    deferredValueDecodeMetrics.valueCount += selection.values.count
    deferredValueDecodeMetrics.encodedByteCount += selection.encodedByteCount
    return selection.values
  }

  private func loadOutboxWithoutTransaction(
    tracesStartupCollections: Bool = true
  ) throws -> [PendingMutation] {
    localMutationQueueWideReadCount += 1
    let mutations: [PendingMutation] = try loadStateCollection(
      phase: "sqlite.state-load.outbox",
      sql: "SELECT json FROM instant_outbox ORDER BY created_at_ms, mutation_id",
      tracesStartupCollection: tracesStartupCollections
    )
    decodedOutboxBodyCount += mutations.count
    return mutations
  }

  private func loadStateCollection<Value: Decodable & Sendable>(
    phase: String,
    sql: String,
    bindings: [SQLiteBinding] = [],
    tracesStartupCollection: Bool = true
  ) throws -> [Value] {
    let stopwatch = startupTrace.stopwatch()
    do {
      let selection: (values: [Value], batchCount: Int, encodedByteCount: Int) =
        try selectBatchedJSON(sql, bindings)
      if tracesStartupCollection {
        startupTrace.completed(
          phase,
          since: stopwatch,
          metadata: [
            "count": String(selection.values.count),
            "decodeBatchCount": String(selection.batchCount),
            "decodeConcurrency": "2",
            "decodeStrategy": "batched-json-array",
            "encodedByteCount": String(selection.encodedByteCount),
          ]
        )
      }
      return selection.values
    } catch {
      if tracesStartupCollection {
        startupTrace.failed(phase, error: error, since: stopwatch)
      }
      throw error
    }
  }

  public func loadQueryCache() throws -> [InstantCachedQuery] {
    try selectJSON(
      "SELECT json FROM instant_query_cache ORDER BY updated_at_ms, query_id, cache_key"
    )
  }

  public func cachedQuery(cacheKey: String) throws -> InstantCachedQuery? {
    let rows: [InstantCachedQuery] = try selectJSON(
      "SELECT json FROM instant_query_cache WHERE cache_key = ? LIMIT 1",
      [.text(cacheKey)]
    )
    return rows.first
  }

  public func cachedQueries(queryID: String) throws -> [InstantCachedQuery] {
    try selectJSON(
      "SELECT json FROM instant_query_cache WHERE query_id = ? ORDER BY updated_at_ms, cache_key",
      [.text(queryID)]
    )
  }

  func liveQueryResult(key: String) throws -> InstantPersistedLiveQueryResult? {
    try liveQueryResultWithoutTransaction(key: key)
  }

  func liveQueryReplacementRetractions(
    for replacements: [InstantLiveQueryResultReplacement]
  ) throws -> [InstantTripleOperation] {
    guard !replacements.isEmpty else { return [] }
    return try readTransaction {
      try liveQueryReplacementRetractionsWithoutTransaction(for: replacements)
    }
  }

  func liveQueryReplacementRetractions(
    for replacements: [InstantLiveQueryResultReplacement],
    expectedQueryResultRevision: Int64
  ) throws -> [InstantTripleOperation]? {
    guard !replacements.isEmpty else { return [] }
    return try readTransaction {
      guard try loadMetadataRevisionWithoutTransaction(Self.queryResultRevisionKey)
        == expectedQueryResultRevision
      else { return nil }
      return try liveQueryReplacementRetractionsWithoutTransaction(for: replacements)
    }
  }

  private func liveQueryReplacementRetractionsWithoutTransaction(
    for replacements: [InstantLiveQueryResultReplacement]
  ) throws -> [InstantTripleOperation] {
    let replacementKeys = Set(replacements.map(\.key))
    var prospective: [String: [InstantLiveTripleIdentity: InstantTriple]] = [:]
    for key in replacementKeys {
      let triples = try liveQueryResultWithoutTransaction(key: key)?.triples ?? []
      prospective[key] = Self.indexLiveTriples(triples)
    }

    var removed: [InstantLiveTripleIdentity: InstantTriple] = [:]
    for replacement in replacements {
      let next = Self.indexLiveTriples(replacement.triples)
      let previous = prospective[replacement.key] ?? [:]
      for (identity, triple) in previous where next[identity] == nil {
        removed[identity] = triple
      }
      prospective[replacement.key] = next
    }

    let retainedByReplacements = Set(prospective.values.flatMap(\.keys))
    var retractions: [InstantTriple] = []
    for identity in removed.keys where !retainedByReplacements.contains(identity) {
      if try liveQueryTripleHasOwnerWithoutTransaction(
        identity,
        excludingQueryKeys: replacementKeys
      ) {
        continue
      }
      if let triple = removed[identity] {
        retractions.append(triple)
      }
    }
    return retractions
      .sorted {
        ($0.entityID, $0.attributeID, $0.value.comparableKey)
          < ($1.entityID, $1.attributeID, $1.value.comparableKey)
      }
      .map(InstantTripleOperation.retract)
  }

  public func pruneQueryCache(
    policy: InstantQueryCachePruningPolicy,
    preservingCacheKeys: Set<String> = []
  ) throws -> InstantQueryCachePruningResult {
    try pruneQueryCache(
      policy: policy,
      now: InstantTimestamp(milliseconds: Self.nowMilliseconds()),
      preservingCacheKeys: preservingCacheKeys
    )
  }

  public func pruneQueryCache(
    policy: InstantQueryCachePruningPolicy,
    now: InstantTimestamp,
    preservingCacheKeys: Set<String> = []
  ) throws -> InstantQueryCachePruningResult {
    try transaction {
      var rows = try loadQueryCacheRowsWithoutTransaction()
      var removedCacheKeys: [String] = []

      func remove(_ row: QueryCacheStorageRow) throws -> Bool {
        guard !preservingCacheKeys.contains(row.cacheKey) else { return false }
        try execute(
          "DELETE FROM instant_query_cache WHERE cache_key = ?",
          [.text(row.cacheKey)]
        )
        rows.removeAll { $0.cacheKey == row.cacheKey }
        removedCacheKeys.append(row.cacheKey)
        return true
      }

      if let maxAgeMilliseconds = policy.maxAgeMilliseconds {
        let cutoff = now.milliseconds - Swift.max(0, maxAgeMilliseconds)
        for row in rows.filter({ $0.updatedAtMilliseconds < cutoff }) {
          _ = try remove(row)
        }
      }

      if let maxEntries = policy.maxEntries {
        let entryLimit = Swift.max(0, maxEntries)
        while rows.count > entryLimit {
          guard let candidate = rows.first(where: { !preservingCacheKeys.contains($0.cacheKey) })
          else { break }
          _ = try remove(candidate)
        }
      }

      if let maxEncodedJSONBytes = policy.maxEncodedJSONBytes {
        let byteLimit = Swift.max(0, maxEncodedJSONBytes)
        var byteCount = rows.reduce(0) { $0 + $1.byteCount }
        while byteCount > byteLimit {
          guard let candidate = rows.first(where: { !preservingCacheKeys.contains($0.cacheKey) })
          else { break }
          if try remove(candidate) {
            byteCount = rows.reduce(0) { $0 + $1.byteCount }
          } else {
            break
          }
        }
      }

      return InstantQueryCachePruningResult(
        removedCacheKeys: removedCacheKeys,
        remainingCacheKeys: rows.map(\.cacheKey),
        remainingEntryCount: rows.count,
        remainingEncodedJSONByteCount: rows.reduce(0) { $0 + $1.byteCount }
      )
    }
  }

  public func saveStoreSnapshot(_ snapshot: InstantStoreSnapshot) throws {
    try transaction {
      let previousSnapshot = try loadStoreSnapshotWithoutTransaction(
        tracesStartupCollections: false
      )
      try requireNoActiveOptimisticOwnerForPublicStoreChangeWithoutTransaction(
        from: previousSnapshot,
        to: snapshot
      )
      try saveStoreSnapshotWithoutTransaction(snapshot)
      _ = try bumpMetadataRevisionWithoutTransaction(Self.storeRevisionKey)
      _ = try bumpMetadataRevisionWithoutTransaction(Self.attributeRevisionKey)
    }
    cachedState = nil
  }

  public func saveOutbox(_ mutations: [PendingMutation]) throws {
    try transaction {
      try saveOutboxWithoutTransaction(
        mutations,
        receiptWriteAuthority: .publicPersistence
      )
      _ = try bumpMetadataRevisionWithoutTransaction(Self.outboxRevisionKey)
    }
    cachedState = nil
  }

  public func saveOutbox(
    _ mutations: [PendingMutation],
    replacing previousMutations: [PendingMutation]? = nil,
    expectedOutboxRevision: Int64
  ) throws -> Bool {
    let didSave = try transaction {
      guard
        try loadMetadataRevisionWithoutTransaction(Self.outboxRevisionKey)
          == expectedOutboxRevision
      else {
        return false
      }
      let previousMutations = try previousMutations
        ?? loadOutboxWithoutTransaction(tracesStartupCollections: false)
      try saveOutboxDiffWithoutTransaction(
        from: previousMutations,
        to: mutations,
        receiptWriteAuthority: .publicPersistence
      )
      _ = try bumpMetadataRevisionWithoutTransaction(Self.outboxRevisionKey)
      return true
    }
    if didSave { cachedState = nil }
    return didSave
  }

  func saveOutbox(
    _ mutations: [PendingMutation],
    replacing previousMutations: [PendingMutation]? = nil,
    metadataEntries: [InstantPersistenceMetadataEntry],
    deletingMetadataKeys: [String] = [],
    expectedStoreRevision: Int64,
    expectedOutboxRevision: Int64
  ) throws -> Bool {
    let previousState = cachedState
    let didSave = try transaction {
      guard
        try loadMetadataRevisionWithoutTransaction(Self.storeRevisionKey) == expectedStoreRevision,
        try loadMetadataRevisionWithoutTransaction(Self.outboxRevisionKey) == expectedOutboxRevision
      else {
        return false
      }
      let previousMutations = try previousMutations
        ?? loadOutboxWithoutTransaction(tracesStartupCollections: false)
      try saveOutboxDiffWithoutTransaction(
        from: previousMutations,
        to: mutations,
        receiptWriteAuthority: .runtimePrepared
      )
      for entry in metadataEntries {
        try saveMetadataValueWithoutTransaction(
          entry.value,
          key: entry.key,
          updatedAt: entry.updatedAt
        )
      }
      for key in deletingMetadataKeys {
        try deleteMetadataValueWithoutTransaction(key: key)
      }
      _ = try bumpMetadataRevisionWithoutTransaction(Self.outboxRevisionKey)
      return true
    }
    if didSave, var previousState,
      previousState.storeRevision == expectedStoreRevision,
      previousState.outboxRevision == expectedOutboxRevision
    {
      previousState.snapshot.outbox = mutations
      previousState.outboxRevision += 1
      adoptCachedState(previousState)
    } else if didSave {
      cachedState = nil
    }
    return didSave
  }

  public func loadAuthSession(key: String) throws -> InstantAuthSession? {
    let rows: [InstantAuthSession] = try selectJSON(
      "SELECT json FROM instant_auth_sessions WHERE key = ? LIMIT 1",
      [.text(key)]
    )
    return rows.first
  }

  public func saveAuthSession(_ session: InstantAuthSession, key: String) throws {
    try execute(
      """
      INSERT OR REPLACE INTO instant_auth_sessions (key, json, updated_at_ms)
      VALUES (?, ?, ?)
      """,
      [
        .text(key),
        .text(try encode(session)),
        .int(session.updatedAt.milliseconds),
      ]
    )
  }

  public func deleteAuthSession(key: String) throws {
    try execute(
      "DELETE FROM instant_auth_sessions WHERE key = ?",
      [.text(key)]
    )
  }

  public func loadRoomPresence(
    appID: String,
    room: InstantRoomHandle
  ) throws -> [InstantRoomPresenceMember] {
    try selectJSON(
      """
      SELECT json FROM instant_room_presence
      WHERE app_id = ? AND room_type = ? AND room_id = ?
      ORDER BY updated_at_ms, user_id
      """,
      [.text(appID), .text(room.type), .text(room.id)]
    )
  }

  public func saveRoomPresence(_ member: InstantRoomPresenceMember) throws {
    try execute(
      """
      INSERT OR REPLACE INTO instant_room_presence
        (app_id, room_type, room_id, user_id, json, updated_at_ms)
      VALUES (?, ?, ?, ?, ?, ?)
      """,
      [
        .text(member.appID),
        .text(member.room.type),
        .text(member.room.id),
        .text(member.userID),
        .text(try encode(member)),
        .int(member.updatedAt.milliseconds),
      ]
    )
  }

  public func deleteRoomPresence(
    appID: String,
    room: InstantRoomHandle,
    userID: String
  ) throws {
    try execute(
      """
      DELETE FROM instant_room_presence
      WHERE app_id = ? AND room_type = ? AND room_id = ? AND user_id = ?
      """,
      [.text(appID), .text(room.type), .text(room.id), .text(userID)]
    )
  }

  public func saveRoomTopicMessage(_ message: InstantRoomTopicMessage) throws {
    try saveRoomTopicMessageWithoutTransaction(message)
  }

  private func saveRoomTopicMessageWithoutTransaction(
    _ message: InstantRoomTopicMessage,
    tableName: String = "instant_room_topic_messages"
  ) throws {
    try execute(
      """
      INSERT OR REPLACE INTO \(tableName)
        (message_id, app_id, room_type, room_id, topic, created_at_ms, json)
      VALUES (?, ?, ?, ?, ?, ?, ?)
      """,
      [
        .text(message.id),
        .text(message.appID),
        .text(message.room.type),
        .text(message.room.id),
        .text(message.topic),
        .int(message.createdAt.milliseconds),
        .text(try encode(message)),
      ]
    )
  }

  public func loadRoomTopicMessages(
    appID: String,
    room: InstantRoomHandle,
    topic: String,
    limit: Int? = nil
  ) throws -> [InstantRoomTopicMessage] {
    let messages: [InstantRoomTopicMessage] = try selectJSON(
      """
      SELECT json FROM instant_room_topic_messages
      WHERE app_id = ? AND room_type = ? AND room_id = ? AND topic = ?
      ORDER BY created_at_ms, rowid
      """,
      [.text(appID), .text(room.type), .text(room.id), .text(topic)]
    )
    if let limit {
      return Array(messages.prefix(limit))
    }
    return messages
  }

  public func saveStoredFile(
    _ file: InstantStoredFile,
    contentsOf sourceURL: URL
  ) throws -> InstantStoredFile {
    _ = try regularFileByteCount(at: sourceURL, operation: "upload file")

    let directory =
      localFilesRootURL
      .appendingPathComponent(sanitizedFileComponent(file.appID), isDirectory: true)
      .appendingPathComponent(sanitizedFileComponent(file.id), isDirectory: true)
    let targetURL = directory.appendingPathComponent(sanitizedFileComponent(file.name))
    do {
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      if FileManager.default.fileExists(atPath: targetURL.path) {
        try FileManager.default.removeItem(at: targetURL)
      }
      try FileManager.default.copyItem(at: sourceURL, to: targetURL)
    } catch {
      throw persistenceError(
        operation: "upload file",
        message:
          "Could not copy source path '\(sourceURL.path)' into local file storage: \(error.localizedDescription)"
      )
    }

    var savedFile = file
    savedFile.byteCount = try regularFileByteCount(at: targetURL, operation: "upload file")
    savedFile.localPath = targetURL.path
    do {
      try execute(
        """
        INSERT OR REPLACE INTO instant_files
          (app_id, file_id, name, created_at_ms, updated_at_ms, json)
        VALUES (?, ?, ?, ?, ?, ?)
        """,
        [
          .text(savedFile.appID),
          .text(savedFile.id),
          .text(savedFile.name),
          .int(savedFile.createdAt.milliseconds),
          .int(savedFile.updatedAt.milliseconds),
          .text(try encode(savedFile)),
        ]
      )
    } catch {
      try? FileManager.default.removeItem(at: targetURL)
      throw error
    }
    return savedFile
  }

  public func saveDownloadedFile(
    _ file: InstantStoredFile,
    data: Data
  ) throws -> InstantStoredFile {
    let directory =
      localFilesRootURL
      .appendingPathComponent(sanitizedFileComponent(file.appID), isDirectory: true)
      .appendingPathComponent(sanitizedFileComponent(file.id), isDirectory: true)
    let targetURL = directory.appendingPathComponent(sanitizedFileComponent(file.name))
    do {
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      try data.write(to: targetURL, options: .atomic)
    } catch {
      throw persistenceError(
        operation: "download file",
        message:
          "Could not cache downloaded file '\(file.name)' locally: \(error.localizedDescription)"
      )
    }

    var savedFile = file
    savedFile.byteCount = Int64(data.count)
    savedFile.localPath = targetURL.path
    do {
      try execute(
        """
        INSERT OR REPLACE INTO instant_files
          (app_id, file_id, name, created_at_ms, updated_at_ms, json)
        VALUES (?, ?, ?, ?, ?, ?)
        """,
        [
          .text(savedFile.appID),
          .text(savedFile.id),
          .text(savedFile.name),
          .int(savedFile.createdAt.milliseconds),
          .int(savedFile.updatedAt.milliseconds),
          .text(try encode(savedFile)),
        ]
      )
    } catch {
      try? FileManager.default.removeItem(at: targetURL)
      throw error
    }
    return savedFile
  }

  public func regularFileByteCount(at sourceURL: URL, operation: String) throws -> Int64 {
    let attributes: [FileAttributeKey: Any]
    do {
      attributes = try FileManager.default.attributesOfItem(atPath: sourceURL.path)
    } catch {
      throw persistenceError(
        operation: operation,
        message: "Could not read source path '\(sourceURL.path)': \(error.localizedDescription)"
      )
    }
    guard attributes[.type] as? FileAttributeType == .typeRegular else {
      throw persistenceError(
        operation: operation,
        message: "Source path '\(sourceURL.path)' is not a regular file."
      )
    }
    return (attributes[.size] as? NSNumber)?.int64Value ?? 0
  }

  public func loadStoredFiles(appID: String) throws -> [InstantStoredFile] {
    try selectJSON(
      """
      SELECT json FROM instant_files
      WHERE app_id = ?
      ORDER BY created_at_ms, file_id
      """,
      [.text(appID)]
    )
  }

  public func storageSnapshot(appID: String) throws -> InstantStorageSnapshot {
    let files = try loadStoredFiles(appID: appID)
    let streamCacheSize = try selectInt64(
      """
      SELECT COALESCE(SUM(byte_count), 0)
      FROM instant_stream_content_chunks
      WHERE app_id = ?
      """,
      [.text(appID)]
    )
    return InstantStorageSnapshot(
      localCacheSize: localCacheFileSize(),
      streamCacheSize: streamCacheSize,
      downloadedFileSize: files.reduce(0) { $0 + $1.byteCount },
      downloadedFileCount: files.count
    )
  }

  public func loadStoredFile(appID: String, fileID: String) throws -> InstantStoredFile? {
    let rows: [InstantStoredFile] = try selectJSON(
      """
      SELECT json FROM instant_files
      WHERE app_id = ? AND file_id = ?
      LIMIT 1
      """,
      [.text(appID), .text(fileID)]
    )
    return rows.first
  }

  public func readStoredFileContents(
    appID: String,
    fileID: String
  ) throws -> InstantStoredFileContents? {
    guard let file = try loadStoredFile(appID: appID, fileID: fileID) else {
      return nil
    }
    do {
      let data = try Data(contentsOf: URL(fileURLWithPath: file.localPath))
      return InstantStoredFileContents(file: file, data: data)
    } catch {
      throw persistenceError(
        operation: "read file",
        message: "Could not read stored file '\(file.localPath)': \(error.localizedDescription)"
      )
    }
  }

  public func deleteStoredFile(appID: String, fileID: String) throws -> InstantStoredFile? {
    guard let file = try loadStoredFile(appID: appID, fileID: fileID) else { return nil }

    try execute(
      "DELETE FROM instant_files WHERE app_id = ? AND file_id = ?",
      [.text(appID), .text(fileID)]
    )
    if FileManager.default.fileExists(atPath: file.localPath) {
      do {
        try FileManager.default.removeItem(atPath: file.localPath)
      } catch {
        throw persistenceError(
          operation: "delete file",
          message: "Could not remove stored file '\(file.localPath)': \(error.localizedDescription)"
        )
      }
    }
    return file
  }

  public func appendStreamChunk(
    appID: String,
    streamID: String,
    chunkID: String,
    payload: JSONValue,
    userID: String,
    createdAt: InstantTimestamp
  ) throws -> InstantStreamChunk {
    try transaction {
      let nextIndex = try nextStreamChunkIndexWithoutTransaction(appID: appID, streamID: streamID)
      let chunk = InstantStreamChunk(
        id: chunkID,
        appID: appID,
        streamID: streamID,
        index: nextIndex,
        payload: payload,
        userID: userID,
        createdAt: createdAt
      )
      try execute(
        """
        INSERT INTO instant_stream_chunks
          (app_id, stream_id, chunk_id, chunk_index, created_at_ms, json)
        VALUES (?, ?, ?, ?, ?, ?)
        """,
        [
          .text(chunk.appID),
          .text(chunk.streamID),
          .text(chunk.id),
          .int(chunk.index),
          .int(chunk.createdAt.milliseconds),
          .text(try encode(chunk)),
        ]
      )
      return chunk
    }
  }

  public func loadStreamChunks(
    appID: String,
    streamID: String,
    limit: Int? = nil,
    afterIndex: Int64? = nil
  ) throws -> [InstantStreamChunk] {
    var sql =
      """
      SELECT json FROM instant_stream_chunks
      WHERE app_id = ? AND stream_id = ?
      ORDER BY chunk_index, chunk_id
      """
    var bindings: [SQLiteBinding] = [.text(appID), .text(streamID)]
    if let afterIndex {
      sql =
        """
        SELECT json FROM instant_stream_chunks
        WHERE app_id = ? AND stream_id = ? AND chunk_index > ?
        ORDER BY chunk_index, chunk_id
        """
      bindings.append(.int(afterIndex))
    }
    if let limit {
      sql.append("\nLIMIT ?")
      bindings.append(.int(Int64(limit)))
    }
    return try selectJSON(sql, bindings)
  }

  public func createStream(
    appID: String,
    streamID: String,
    clientID: String,
    userID: String,
    createdAt: InstantTimestamp
  ) throws -> InstantStreamMetadata {
    try transaction {
      if let existing = try streamMetadataWithoutTransaction(appID: appID, clientID: clientID) {
        throw streamValidationError(
          operation: "create stream",
          localID: clientID,
          message:
            "Stream client id '\(clientID)' already belongs to stream '\(existing.id)'.",
          recovery: "Choose a unique client id before creating another stream."
        )
      }
      if try streamMetadataWithoutTransaction(appID: appID, streamID: streamID) != nil {
        throw streamValidationError(
          operation: "create stream",
          localID: streamID,
          message: "Stream id '\(streamID)' already exists.",
          recovery: "Retry stream creation with a freshly generated stream id."
        )
      }
      let metadata = InstantStreamMetadata(
        id: streamID,
        appID: appID,
        clientID: clientID,
        userID: userID,
        createdAt: createdAt,
        updatedAt: createdAt
      )
      try insertStreamMetadataWithoutTransaction(metadata)
      return metadata
    }
  }

  public func loadStreamMetadata(
    appID: String,
    streamID: String
  ) throws -> InstantStreamMetadata? {
    try readTransaction {
      try streamMetadataWithoutTransaction(appID: appID, streamID: streamID)
    }
  }

  public func loadStreamMetadata(
    appID: String,
    clientID: String
  ) throws -> InstantStreamMetadata? {
    try readTransaction {
      try streamMetadataWithoutTransaction(appID: appID, clientID: clientID)
    }
  }

  public func loadStreamMetadata(appID: String) throws -> [InstantStreamMetadata] {
    try readTransaction {
      try selectJSON(
        """
        SELECT json FROM instant_streams
        WHERE app_id = ?
        ORDER BY created_at_ms, stream_id
        """,
        [.text(appID)]
      )
    }
  }

  public func ensureStreamMetadata(
    appID: String,
    streamID: String,
    clientID: String,
    userID: String,
    createdAt: InstantTimestamp
  ) throws -> InstantStreamMetadata {
    try transaction {
      if let existing = try streamMetadataWithoutTransaction(appID: appID, streamID: streamID) {
        guard existing.clientID == clientID else {
          throw streamValidationError(
            operation: "bootstrap stream metadata",
            localID: streamID,
            message:
              "Stream '\(streamID)' is already associated with client id '\(existing.clientID)', not '\(clientID)'.",
            recovery: "Reconnect using the client id returned by the canonical stream append."
          )
        }
        return existing
      }
      if let existing = try streamMetadataWithoutTransaction(appID: appID, clientID: clientID) {
        throw streamValidationError(
          operation: "bootstrap stream metadata",
          localID: clientID,
          message:
            "Stream client id '\(clientID)' already belongs to stream '\(existing.id)', not '\(streamID)'.",
          recovery: "Reconnect the client-id reader and inspect the canonical stream id."
        )
      }
      let metadata = InstantStreamMetadata(
        id: streamID,
        appID: appID,
        clientID: clientID,
        userID: userID,
        createdAt: createdAt,
        updatedAt: createdAt
      )
      try insertStreamMetadataWithoutTransaction(metadata)
      return metadata
    }
  }

  public func appendStreamContent(
    appID: String,
    streamID: String,
    chunkID: String,
    content: String,
    expectedOffset: Int64?,
    userID: String,
    createdAt: InstantTimestamp
  ) throws -> InstantStreamContentAppend? {
    try transaction {
      guard var metadata = try streamMetadataWithoutTransaction(appID: appID, streamID: streamID)
      else { return nil }
      guard metadata.done == false else {
        throw streamValidationError(
          operation: "append stream content",
          localID: streamID,
          message: "Stream '\(streamID)' is already closed.",
          recovery: "Create a new stream before appending more content."
        )
      }

      let offset = try streamContentSizeWithoutTransaction(appID: appID, streamID: streamID)
      if let expectedOffset, expectedOffset != offset {
        throw streamValidationError(
          operation: "append stream content",
          localID: streamID,
          message:
            "Stream '\(streamID)' is at byte offset \(offset), not expected offset \(expectedOffset).",
          recovery: "Read the stream metadata and retry with the current offset."
        )
      }

      let chunk = InstantStreamContentChunk(
        id: chunkID,
        appID: appID,
        streamID: streamID,
        offset: offset,
        byteCount: Int64(content.utf8.count),
        content: content,
        userID: userID,
        createdAt: createdAt
      )
      try execute(
        """
        INSERT INTO instant_stream_content_chunks
          (app_id, stream_id, chunk_id, offset, byte_count, created_at_ms, json)
        VALUES (?, ?, ?, ?, ?, ?, ?)
        """,
        [
          .text(chunk.appID),
          .text(chunk.streamID),
          .text(chunk.id),
          .int(chunk.offset),
          .int(chunk.byteCount),
          .int(chunk.createdAt.milliseconds),
          .text(try encode(chunk)),
        ]
      )

      metadata.updatedAt = createdAt
      try saveStreamMetadataWithoutTransaction(metadata)
      return InstantStreamContentAppend(metadata: metadata, chunk: chunk, offset: offset)
    }
  }

  public func closeStream(
    appID: String,
    streamID: String,
    abortReason: String?,
    updatedAt: InstantTimestamp
  ) throws -> InstantStreamMetadata? {
    try transaction {
      guard var metadata = try streamMetadataWithoutTransaction(appID: appID, streamID: streamID)
      else { return nil }
      guard metadata.done == false else { return metadata }
      metadata.done = true
      metadata.size = try streamContentSizeWithoutTransaction(appID: appID, streamID: streamID)
      metadata.abortReason = abortReason
      metadata.updatedAt = updatedAt
      try saveStreamMetadataWithoutTransaction(metadata)
      return metadata
    }
  }

  public func loadStreamContent(
    appID: String,
    streamID: String,
    byteOffset: Int64
  ) throws -> InstantStreamContentRead? {
    try readTransaction {
      guard let metadata = try streamMetadataWithoutTransaction(appID: appID, streamID: streamID)
      else { return nil }
      return try streamContentReadWithoutTransaction(metadata: metadata, byteOffset: byteOffset)
    }
  }

  public func loadStreamContent(
    appID: String,
    clientID: String,
    byteOffset: Int64
  ) throws -> InstantStreamContentRead? {
    try readTransaction {
      guard let metadata = try streamMetadataWithoutTransaction(appID: appID, clientID: clientID)
      else { return nil }
      return try streamContentReadWithoutTransaction(metadata: metadata, byteOffset: byteOffset)
    }
  }

  public func createShare(
    _ share: InstantShare,
    ownerMembership: InstantShareMembership
  ) throws -> InstantShareSnapshot {
    try transaction {
      try saveShareWithoutTransaction(share)
      try saveShareMembershipWithoutTransaction(ownerMembership)
      return try shareSnapshotWithoutTransaction(appID: share.appID, shareID: share.id)
    }
  }

  public func acceptShare(
    appID: String,
    token: String,
    userID: String,
    acceptedAt: InstantTimestamp
  ) throws -> InstantShareSnapshot? {
    try transaction {
      guard let share = try shareWithoutTransaction(appID: appID, token: token),
        share.revokedAt == nil
      else {
        return nil
      }
      let existingMembership = try shareMembershipWithoutTransaction(
        appID: appID,
        shareID: share.id,
        userID: userID
      )
      if let existingMembership, existingMembership.revokedAt == nil {
        return try shareSnapshotWithoutTransaction(appID: appID, shareID: share.id)
      }
      try saveShareMembershipWithoutTransaction(
        InstantShareMembership(
          appID: appID,
          shareID: share.id,
          userID: userID,
          role: .reader,
          acceptedAt: acceptedAt
        )
      )
      return try shareSnapshotWithoutTransaction(appID: appID, shareID: share.id)
    }
  }

  public func loadShareSnapshot(appID: String, shareID: String) throws -> InstantShareSnapshot? {
    try readTransaction {
      guard try shareWithoutTransaction(appID: appID, shareID: shareID) != nil else { return nil }
      return try shareSnapshotWithoutTransaction(appID: appID, shareID: shareID)
    }
  }

  public func loadShareSnapshots(appID: String, userID: String) throws -> [InstantShareSnapshot] {
    try readTransaction {
      let shares: [InstantShare] = try selectJSON(
        """
        SELECT s.json FROM instant_shares s
        INNER JOIN instant_share_memberships m
          ON m.app_id = s.app_id AND m.share_id = s.share_id
        WHERE s.app_id = ? AND m.user_id = ?
          AND s.revoked_at_ms IS NULL AND m.revoked_at_ms IS NULL
        ORDER BY s.created_at_ms, s.share_id
        """,
        [.text(appID), .text(userID)]
      )
      return try shares.map {
        try shareSnapshotWithoutTransaction(
          appID: appID, shareID: $0.id, activeMembershipsOnly: true)
      }
    }
  }

  func pruneLiveQueryResults(
    policy: InstantLiveQueryResultPruningPolicy,
    now: InstantTimestamp,
    preservingQueryKeys: Set<String> = [],
    currentStoreSnapshot: InstantStoreSnapshot? = nil
  ) throws -> InstantLiveQueryResultPruningApplication {
    let application = try transaction {
      let storeRevision = try loadMetadataRevisionWithoutTransaction(Self.storeRevisionKey)
      let attributeRevision = try loadMetadataRevisionWithoutTransaction(
        Self.attributeRevisionKey
      )
      let outboxRevision = try loadMetadataRevisionWithoutTransaction(Self.outboxRevisionKey)
      let queryResultRevision = try loadMetadataRevisionWithoutTransaction(
        Self.queryResultRevisionKey
      )
      let currentState: InstantPersistenceState
      if var cachedState,
        cachedState.storeRevision == storeRevision,
        cachedState.attributeRevision == attributeRevision,
        cachedState.outboxRevision == outboxRevision
      {
        cachedState.queryResultRevision = queryResultRevision
        if cachedState.snapshot.store.triples.isEmpty {
          if let currentStoreSnapshot {
            cachedState.snapshot.store = currentStoreSnapshot
          } else {
            cachedState.snapshot.store = try loadStoreSnapshotWithoutTransaction(
              tracesStartupCollections: false
            )
          }
        }
        currentState = cachedState
      } else {
        currentState = try InstantPersistenceState(
          snapshot: loadCompactSnapshotWithoutTransaction(),
          storeRevision: storeRevision,
          outboxRevision: outboxRevision,
          attributeRevision: attributeRevision,
          queryResultRevision: queryResultRevision
        )
      }
      var rows = try loadLiveQueryResultRowsWithoutTransaction()
      var protectedQueryKeys = preservingQueryKeys
      // Compact lifecycle rows deliberately omit transaction bodies. While any
      // mutation may still own optimistic state, preserve all persisted live
      // results instead of hydrating the complete durable queue just to derive
      // a narrower entity set. Pruning resumes once those lifecycle shells are
      // server-accepted or have a proven removed overlay.
      //
      // TypeScript Reactor.js `_cleanupQuery` still calls `querySubs.unloadKey`
      // when a query has no listeners, even while `pendingMutations` exist.
      // Optimistic state lives on the outbox, not on stale infinite-query pages.
      // Session prune passes the live listener set as `preservingQueryKeys`.
      // Bootstrap prune passes an empty set and must keep today's protect-all
      // so offline cache survives until the app resubscribes.
      if preservingQueryKeys.isEmpty,
        try outboxRequiresConservativeLiveQueryPruningWithoutTransaction()
      {
        protectedQueryKeys.formUnion(rows.map(\.queryKey))
      }

      var removedRows: [LiveQueryResultStorageRow] = []
      func remove(_ row: LiveQueryResultStorageRow) -> Bool {
        guard !protectedQueryKeys.contains(row.queryKey) else { return false }
        rows.removeAll { $0.queryKey == row.queryKey }
        removedRows.append(row)
        return true
      }

      if !preservingQueryKeys.isEmpty {
        for row in Array(rows) where !preservingQueryKeys.contains(row.queryKey) {
          _ = remove(row)
        }
      }

      if let maxAgeMilliseconds = policy.maxAgeMilliseconds {
        let cutoff = now.milliseconds - Swift.max(0, maxAgeMilliseconds)
        for row in rows where row.updatedAtMilliseconds < cutoff {
          _ = remove(row)
        }
      }
      if let maxEntries = policy.maxEntries {
        let limit = Swift.max(0, maxEntries)
        while rows.count > limit {
          guard let row = rows.first(where: { !protectedQueryKeys.contains($0.queryKey) })
          else { break }
          _ = remove(row)
        }
      }
      if let maxTripleCount = policy.maxTripleCount {
        let limit = Swift.max(0, maxTripleCount)
        var tripleCount = rows.reduce(0) { $0 + $1.tripleCount }
        while tripleCount > limit {
          guard let row = rows.first(where: { !protectedQueryKeys.contains($0.queryKey) })
          else { break }
          guard remove(row) else { continue }
          tripleCount -= row.tripleCount
        }
      }

      guard !removedRows.isEmpty else {
        return InstantLiveQueryResultPruningApplication(
          result: InstantLiveQueryResultPruningResult(
            removedQueryKeys: [],
            remainingQueryKeys: rows.map(\.queryKey),
            removedOrphanedTripleCount: 0,
            remainingEntryCount: rows.count,
            remainingTripleCount: rows.reduce(0) { $0 + $1.tripleCount }
          ),
          state: currentState
        )
      }

      var snapshot = currentState.snapshot
      var removedIdentities: Set<InstantLiveTripleIdentity> = []
      for row in removedRows {
        guard let result = try liveQueryResultWithoutTransaction(key: row.queryKey) else {
          continue
        }
        for triple in result.triples {
          removedIdentities.insert(InstantLiveTripleIdentity(triple))
        }
        try execute(
          "DELETE FROM instant_live_query_results WHERE query_key = ?",
          [.text(row.queryKey)]
        )
      }

      let previousStore = snapshot.store
      let currentTriples = Dictionary(
        snapshot.store.triples.map { (InstantLiveTripleIdentity($0), $0) },
        uniquingKeysWith: { _, latest in latest }
      )
      var orphanedIdentities: Set<InstantLiveTripleIdentity> = []
      for identity in removedIdentities {
        guard
          !(try liveQueryTripleHasOwnerWithoutTransaction(
            identity,
            excludingQueryKeys: []
          )),
          currentTriples[identity] != nil
        else { continue }
        orphanedIdentities.insert(identity)
      }
      snapshot.store.triples.removeAll {
        orphanedIdentities.contains(InstantLiveTripleIdentity($0))
      }
      if snapshot.store != previousStore {
        try saveStoreSnapshotDiffWithoutTransaction(
          from: previousStore,
          to: snapshot.store
        )
      }
      let nextStoreRevision = if orphanedIdentities.isEmpty {
        storeRevision
      } else {
        try bumpMetadataRevisionWithoutTransaction(Self.storeRevisionKey)
      }
      let nextQueryResultRevision = try bumpMetadataRevisionWithoutTransaction(
        Self.queryResultRevisionKey
      )
      return InstantLiveQueryResultPruningApplication(
        result: InstantLiveQueryResultPruningResult(
          removedQueryKeys: removedRows.map(\.queryKey),
          remainingQueryKeys: rows.map(\.queryKey),
          removedOrphanedTripleCount: orphanedIdentities.count,
          remainingEntryCount: rows.count,
          remainingTripleCount: rows.reduce(0) { $0 + $1.tripleCount }
        ),
        state: InstantPersistenceState(
          snapshot: snapshot,
          storeRevision: nextStoreRevision,
          outboxRevision: outboxRevision,
          attributeRevision: attributeRevision,
          queryResultRevision: nextQueryResultRevision
        )
      )
    }
    adoptCachedState(application.state)
    return application
  }

  public func loadActiveShareSnapshots(
    appID: String,
    rootNamespace: String?,
    rootID: String
  ) throws -> [InstantShareSnapshot] {
    try readTransaction {
      var sql =
        """
        SELECT json FROM instant_shares
        WHERE app_id = ? AND root_id = ? AND revoked_at_ms IS NULL
        """
      var bindings: [SQLiteBinding] = [.text(appID), .text(rootID)]
      if let rootNamespace {
        sql.append("\nAND root_namespace = ?")
        bindings.append(.text(rootNamespace))
      }
      sql.append("\nORDER BY created_at_ms, share_id")
      let shares: [InstantShare] = try selectJSON(sql, bindings)
      return try shares.map {
        try shareSnapshotWithoutTransaction(
          appID: appID, shareID: $0.id, activeMembershipsOnly: true)
      }
    }
  }

  public func updateShareMembershipRole(
    appID: String,
    shareID: String,
    userID: String,
    role: InstantShareRole,
    updatedAt: InstantTimestamp
  ) throws -> InstantShareSnapshot? {
    try transaction {
      guard var share = try shareWithoutTransaction(appID: appID, shareID: shareID),
        share.revokedAt == nil,
        var membership = try shareMembershipWithoutTransaction(
          appID: appID,
          shareID: shareID,
          userID: userID
        ),
        membership.revokedAt == nil
      else {
        return nil
      }

      if membership.role != role {
        membership.role = role
        try saveShareMembershipWithoutTransaction(membership)
        share.updatedAt = updatedAt
        try saveShareWithoutTransaction(share)
      }
      return try shareSnapshotWithoutTransaction(
        appID: appID,
        shareID: shareID,
        activeMembershipsOnly: true
      )
    }
  }

  public func revokeShare(
    appID: String,
    shareID: String,
    revokedAt: InstantTimestamp
  ) throws -> InstantShareSnapshot? {
    try transaction {
      guard var share = try shareWithoutTransaction(appID: appID, shareID: shareID) else {
        return nil
      }
      if share.revokedAt != nil {
        return try shareSnapshotWithoutTransaction(appID: appID, shareID: shareID)
      }
      share.revokedAt = revokedAt
      share.updatedAt = revokedAt
      try saveShareWithoutTransaction(share)

      let memberships = try shareMembershipsWithoutTransaction(
        appID: appID,
        shareID: shareID,
        activeOnly: false
      )
      for var membership in memberships where membership.revokedAt == nil {
        membership.revokedAt = revokedAt
        try saveShareMembershipWithoutTransaction(membership)
      }
      return try shareSnapshotWithoutTransaction(appID: appID, shareID: shareID)
    }
  }

  public func loadMagicCodeChallenge(key: String) throws -> InstantMagicCodeChallenge? {
    let rows: [InstantMagicCodeChallenge] = try selectJSON(
      "SELECT json FROM instant_magic_code_challenges WHERE key = ? LIMIT 1",
      [.text(key)]
    )
    return rows.first
  }

  public func saveMagicCodeChallenge(_ challenge: InstantMagicCodeChallenge, key: String) throws {
    try execute(
      """
      INSERT OR REPLACE INTO instant_magic_code_challenges
        (key, email, expires_at_ms, json, updated_at_ms)
      VALUES (?, ?, ?, ?, ?)
      """,
      [
        .text(key),
        .text(challenge.email),
        .int(challenge.expiresAt.milliseconds),
        .text(try encode(challenge)),
        .int(challenge.createdAt.milliseconds),
      ]
    )
  }

  public func deleteMagicCodeChallenge(key: String) throws {
    try execute(
      "DELETE FROM instant_magic_code_challenges WHERE key = ?",
      [.text(key)]
    )
  }

  public func loadMetadataValue(key: String) throws -> String? {
    try selectScalar(
      "SELECT value FROM instant_sync_metadata WHERE key = ? LIMIT 1",
      [.text(key)]
    )
  }

  public func saveMetadataValue(
    _ value: String,
    key: String,
    updatedAt: InstantTimestamp
  ) throws {
    try saveMetadataValueWithoutTransaction(value, key: key, updatedAt: updatedAt)
  }

  public func saveMetadataValue(
    _ value: String,
    key: String,
    updatedAt: InstantTimestamp,
    expectedStoreRevision: Int64,
    expectedOutboxRevision: Int64
  ) throws -> Bool {
    try transaction {
      guard
        try loadMetadataRevisionWithoutTransaction(Self.storeRevisionKey) == expectedStoreRevision,
        try loadMetadataRevisionWithoutTransaction(Self.outboxRevisionKey) == expectedOutboxRevision
      else {
        return false
      }
      try saveMetadataValueWithoutTransaction(value, key: key, updatedAt: updatedAt)
      return true
    }
  }

  public func deleteMetadataValue(key: String) throws {
    try execute(
      "DELETE FROM instant_sync_metadata WHERE key = ?",
      [.text(key)]
    )
  }

  public func saveSnapshot(_ snapshot: InstantPersistenceSnapshot) throws {
    _ = try transaction {
      let previousStore = try loadStoreSnapshotWithoutTransaction(
        tracesStartupCollections: false
      )
      try requireNoActiveOptimisticOwnerForPublicStoreChangeWithoutTransaction(
        from: previousStore,
        to: snapshot.store
      )
      try saveStoreSnapshotWithoutTransaction(snapshot.store)
      try saveOutboxWithoutTransaction(
        snapshot.outbox,
        receiptWriteAuthority: .publicPersistence
      )
      return (
        store: try bumpMetadataRevisionWithoutTransaction(Self.storeRevisionKey),
        attributes: try bumpMetadataRevisionWithoutTransaction(Self.attributeRevisionKey),
        outbox: try bumpMetadataRevisionWithoutTransaction(Self.outboxRevisionKey)
      )
    }
    cachedState = nil
    InstantDiagnostics.shared.record(
      .trace,
      subsystem: "instant-swift-data-core",
      category: "persistence",
      event: "sqlite.snapshot-saved",
      message: "Saved an Instant cache snapshot.",
      metadata: [
        "attributeCount": String(snapshot.store.attributes.count),
        "tripleCount": String(snapshot.store.triples.count),
        "outboxCount": String(snapshot.outbox.count),
      ]
    )
  }

  public func saveSnapshot(
    _ snapshot: InstantPersistenceSnapshot,
    expectedStoreRevision: Int64,
    expectedAttributeRevision: Int64,
    expectedOutboxRevision: Int64
  ) throws -> Bool {
    let revisions: (store: Int64, attributes: Int64, outbox: Int64)? = try transaction {
      () -> (store: Int64, attributes: Int64, outbox: Int64)? in
      guard
        try loadMetadataRevisionWithoutTransaction(Self.storeRevisionKey) == expectedStoreRevision,
        try loadMetadataRevisionWithoutTransaction(Self.attributeRevisionKey)
          == expectedAttributeRevision,
        try loadMetadataRevisionWithoutTransaction(Self.outboxRevisionKey) == expectedOutboxRevision
      else {
        return nil
      }
      let previousStore = try loadStoreSnapshotWithoutTransaction(
        tracesStartupCollections: false
      )
      try requireNoActiveOptimisticOwnerForPublicStoreChangeWithoutTransaction(
        from: previousStore,
        to: snapshot.store
      )
      try saveStoreSnapshotWithoutTransaction(snapshot.store)
      try saveOutboxWithoutTransaction(
        snapshot.outbox,
        receiptWriteAuthority: .publicPersistence
      )
      return (
        store: try bumpMetadataRevisionWithoutTransaction(Self.storeRevisionKey),
        attributes: try bumpMetadataRevisionWithoutTransaction(Self.attributeRevisionKey),
        outbox: try bumpMetadataRevisionWithoutTransaction(Self.outboxRevisionKey)
      )
    }
    if let revisions {
      adoptCachedState(InstantPersistenceState(
        snapshot: snapshot,
        storeRevision: revisions.store,
        outboxRevision: revisions.outbox,
        attributeRevision: revisions.attributes
      ))
    }
    return revisions != nil
  }

  public func saveSnapshot(
    _ snapshot: InstantPersistenceSnapshot,
    replacing previousSnapshot: InstantPersistenceSnapshot,
    expectedStoreRevision: Int64,
    expectedAttributeRevision: Int64,
    expectedOutboxRevision: Int64
  ) throws -> Bool {
    let revisions: (store: Int64, attributes: Int64, outbox: Int64)? = try transaction {
      () -> (store: Int64, attributes: Int64, outbox: Int64)? in
      guard
        try loadMetadataRevisionWithoutTransaction(Self.storeRevisionKey) == expectedStoreRevision,
        try loadMetadataRevisionWithoutTransaction(Self.attributeRevisionKey)
          == expectedAttributeRevision,
        try loadMetadataRevisionWithoutTransaction(Self.outboxRevisionKey) == expectedOutboxRevision
      else {
        return nil
      }
      try requireNoActiveOptimisticOwnerForPublicStoreChangeWithoutTransaction(
        from: previousSnapshot.store,
        to: snapshot.store
      )
      try saveStoreSnapshotDiffWithoutTransaction(
        from: previousSnapshot.store,
        to: snapshot.store
      )
      try saveOutboxDiffWithoutTransaction(
        from: previousSnapshot.outbox,
        to: snapshot.outbox,
        receiptWriteAuthority: .publicPersistence
      )
      return (
        store: try bumpMetadataRevisionWithoutTransaction(Self.storeRevisionKey),
        attributes: try bumpMetadataRevisionWithoutTransaction(Self.attributeRevisionKey),
        outbox: try bumpMetadataRevisionWithoutTransaction(Self.outboxRevisionKey)
      )
    }
    if revisions != nil { cachedState = nil }
    return revisions != nil
  }

  func saveSnapshot(
    _ snapshot: InstantPersistenceSnapshot,
    replacing previousSnapshot: InstantPersistenceSnapshot,
    metadataEntries: [InstantPersistenceMetadataEntry],
    deletingMetadataKeys: [String] = [],
    requiredOutboxClaimMutationID: String? = nil,
    requiredOutboxClaimToken: String? = nil,
    expectedStoreRevision: Int64,
    expectedAttributeRevision: Int64,
    expectedOutboxRevision: Int64
  ) throws -> Bool {
    precondition(
      (requiredOutboxClaimMutationID == nil) == (requiredOutboxClaimToken == nil),
      "A required outbox claim must include both its mutation id and token."
    )
    let revisions: (store: Int64, attributes: Int64, outbox: Int64)? = try transaction {
      () -> (store: Int64, attributes: Int64, outbox: Int64)? in
      guard
        try loadMetadataRevisionWithoutTransaction(Self.storeRevisionKey) == expectedStoreRevision,
        try loadMetadataRevisionWithoutTransaction(Self.attributeRevisionKey)
          == expectedAttributeRevision,
        try loadMetadataRevisionWithoutTransaction(Self.outboxRevisionKey) == expectedOutboxRevision
      else {
        return nil
      }
      if let requiredOutboxClaimMutationID, let requiredOutboxClaimToken {
        guard try selectScalar(
          """
          SELECT delivery_claim_token FROM instant_outbox
          WHERE mutation_id = ? AND status IN (?, ?)
            AND confirmation_proven = 0 AND delivery_state = ?
            AND delivery_claim_state = ?
          LIMIT 1
          """,
          [
            .text(requiredOutboxClaimMutationID),
            .text(InstantMutationStatus.pending.rawValue),
            .text(InstantMutationStatus.confirmed.rawValue),
            .text(InstantOutboxDeliveryState.needsDelivery.rawValue),
            .text(InstantOutboxDeliveryClaimState.claimed.rawValue),
          ]
        ) == requiredOutboxClaimToken else { return nil }
      }
      try saveStoreSnapshotDiffWithoutTransaction(
        from: previousSnapshot.store,
        to: snapshot.store
      )
      try saveOutboxDiffWithoutTransaction(
        from: previousSnapshot.outbox,
        to: snapshot.outbox,
        receiptWriteAuthority: .runtimePrepared
      )
      if let requiredOutboxClaimMutationID, let requiredOutboxClaimToken {
        // The terminal disposition consumes this exact delivery claim. Leaving
        // it attached to the retained failed row strands an immediate retry
        // until the five-second lease expires and emits a false ACK timeout.
        try execute(
          """
          UPDATE instant_outbox
          SET delivery_claim_state = ?, delivery_claim_token = NULL,
              delivery_claimant_id = NULL, delivery_claim_deadline_ms = NULL,
              delivery_claim_projected_body_bytes = NULL,
              delivery_claim_payload_fingerprint = NULL
          WHERE mutation_id = ? AND delivery_claim_state = ?
            AND delivery_claim_token = ?
          """,
          [
            .text(InstantOutboxDeliveryClaimState.ready.rawValue),
            .text(requiredOutboxClaimMutationID),
            .text(InstantOutboxDeliveryClaimState.claimed.rawValue),
            .text(requiredOutboxClaimToken),
          ]
        )
        guard sqlite3_changes(connection.raw) == 1 else {
          throw persistenceError(
            operation: "consume rejected outbox claim",
            message:
              "SQLite did not release the token-owned terminal mutation '\(requiredOutboxClaimMutationID)' exactly once."
          )
        }
      }
      for entry in metadataEntries {
        try saveMetadataValueWithoutTransaction(
          entry.value,
          key: entry.key,
          updatedAt: entry.updatedAt
        )
      }
      for key in deletingMetadataKeys {
        try deleteMetadataValueWithoutTransaction(key: key)
      }
      return (
        store: try bumpMetadataRevisionWithoutTransaction(Self.storeRevisionKey),
        attributes: try bumpMetadataRevisionWithoutTransaction(Self.attributeRevisionKey),
        outbox: try bumpMetadataRevisionWithoutTransaction(Self.outboxRevisionKey)
      )
    }
    if revisions != nil { cachedState = nil }
    return revisions != nil
  }

  func saveLocalMutation(
    changedEntityTriples: [String: [InstantTriple]],
    outbox: [PendingMutation]? = nil,
    pendingMutation: PendingMutation,
    supersedingImmediateTail: PendingMutation? = nil,
    metadataEntries: [InstantPersistenceMetadataEntry] = [],
    deletingMetadataKeys: [String] = [],
    expectedStoreRevision: Int64,
    expectedAttributeRevision: Int64,
    expectedOutboxRevision: Int64
  ) throws -> Bool {
    guard try pendingMutation.optimisticEffectReceiptFingerprint() != nil else {
      throw persistenceError(
        operation: "persist local mutation",
        message:
          "Mutation '\(pendingMutation.id)' was not prepared by Runtime before local admission."
      )
    }
    // Dual-residency thin cache keeps attributes/outbox/revisions only. Empty
    // triples must not be treated as "entity has no triples" — fall back to SQLite.
    let cachedChangedEntityTriples: [String: [InstantTriple]]?
    if let cachedState,
      cachedState.storeRevision == expectedStoreRevision,
      cachedState.attributeRevision == expectedAttributeRevision,
      cachedState.outboxRevision == expectedOutboxRevision,
      !cachedState.snapshot.store.triples.isEmpty
    {
      cachedChangedEntityTriples = Dictionary(
        uniqueKeysWithValues: changedEntityTriples.keys.map { entityID in
          (entityID, cachedTriples(in: cachedState.snapshot.store.triples, entityID: entityID))
        }
      )
    } else {
      cachedChangedEntityTriples = nil
    }

    let didSave = try transaction {
      guard
        try loadMetadataRevisionWithoutTransaction(Self.storeRevisionKey) == expectedStoreRevision,
        try loadMetadataRevisionWithoutTransaction(Self.attributeRevisionKey)
          == expectedAttributeRevision,
        try loadMetadataRevisionWithoutTransaction(Self.outboxRevisionKey) == expectedOutboxRevision
      else {
        return false
      }

      var supersessionLifecycleID: String?
      if let supersedingImmediateTail {
        let supersedingImmediateTailID = supersedingImmediateTail.id
        // Claim/offered transitions intentionally do not bump the outbox
        // revision. Re-prove the exact physical tail and every eligibility
        // scalar under this write transaction before replacing evidence.
        guard
          try immediateOutboxTailIDWithoutTransaction() == supersedingImmediateTailID,
          try isImmediateSupersessionTailEligibleWithoutTransaction(
            id: supersedingImmediateTailID
          ),
          try hasStoredPreparedOptimisticEffectReceiptWithoutTransaction(
            supersedingImmediateTail
          )
        else { return false }
        let lifecycleID =
          try lifecycleIDWithoutTransaction(for: supersedingImmediateTailID)
          ?? supersedingImmediateTailID
        supersessionLifecycleID = lifecycleID
        try execute(
          "DELETE FROM instant_outbox WHERE mutation_id = ?",
          [.text(supersedingImmediateTailID)]
        )
      }

      for entityID in changedEntityTriples.keys.sorted() {
        let previousTriples = try cachedChangedEntityTriples?[entityID]
          ?? selectJSON(
            "SELECT json FROM instant_triples WHERE entity_id = ? ORDER BY attribute_id, value_json",
            [.text(entityID)]
          )
        try saveTripleDiffWithoutTransaction(
          from: previousTriples,
          to: changedEntityTriples[entityID, default: []]
        )
      }
      try saveOutboxMutationWithoutTransaction(
        pendingMutation,
        lifecycleID: supersessionLifecycleID,
        advancingFromMutationID: supersedingImmediateTail?.id,
        receiptWriteAuthority: .runtimePrepared
      )
      if let supersedingImmediateTail, let supersessionLifecycleID {
        try saveMutationLifecycleAliasWithoutTransaction(
          mutationID: supersedingImmediateTail.id,
          lifecycleID: supersessionLifecycleID
        )
      }
      for entry in metadataEntries {
        try saveMetadataValueWithoutTransaction(
          entry.value,
          key: entry.key,
          updatedAt: entry.updatedAt
        )
      }
      for key in deletingMetadataKeys {
        try deleteMetadataValueWithoutTransaction(key: key)
      }
      _ = try bumpMetadataRevisionWithoutTransaction(Self.storeRevisionKey)
      _ = try bumpMetadataRevisionWithoutTransaction(Self.outboxRevisionKey)
      return true
    }

    if didSave, var cachedState,
      cachedState.storeRevision == expectedStoreRevision,
      cachedState.attributeRevision == expectedAttributeRevision,
      cachedState.outboxRevision == expectedOutboxRevision
    {
      if !cachedState.snapshot.store.triples.isEmpty {
        replaceCachedTriples(
          in: &cachedState.snapshot.store.triples,
          with: changedEntityTriples
        )
      }
      // SQLite is the queue authority. Runtime callers may pass a hydrated
      // snapshot for legacy retry/rebase work, but ordinary enqueue never
      // installs or copies it into the compact cache.
      cachedState.snapshot.outbox = outbox ?? []
      cachedState.storeRevision += 1
      cachedState.outboxRevision += 1
      adoptCachedState(cachedState)
    } else if didSave {
      cachedState = nil
    }
    return didSave
  }

  public func saveStoreSnapshot(
    _ snapshot: InstantStoreSnapshot,
    replacing previousSnapshot: InstantStoreSnapshot,
    expectedStoreRevision: Int64,
    expectedOutboxRevision: Int64,
    expectedAttributeRevision: Int64
  ) throws -> Bool {
    try saveStoreSnapshot(
      snapshot,
      replacing: previousSnapshot,
      expectedStoreRevision: expectedStoreRevision,
      expectedOutboxRevision: expectedOutboxRevision,
      expectedAttributeRevision: expectedAttributeRevision,
      allowsActiveOptimisticOwners: false
    )
  }

  package func saveRuntimePreparedStoreSnapshot(
    _ snapshot: InstantStoreSnapshot,
    replacing previousSnapshot: InstantStoreSnapshot,
    expectedStoreRevision: Int64,
    expectedOutboxRevision: Int64,
    expectedAttributeRevision: Int64
  ) throws -> Bool {
    try saveStoreSnapshot(
      snapshot,
      replacing: previousSnapshot,
      expectedStoreRevision: expectedStoreRevision,
      expectedOutboxRevision: expectedOutboxRevision,
      expectedAttributeRevision: expectedAttributeRevision,
      allowsActiveOptimisticOwners: true
    )
  }

  private func saveStoreSnapshot(
    _ snapshot: InstantStoreSnapshot,
    replacing previousSnapshot: InstantStoreSnapshot,
    expectedStoreRevision: Int64,
    expectedOutboxRevision: Int64,
    expectedAttributeRevision: Int64,
    allowsActiveOptimisticOwners: Bool
  ) throws -> Bool {
    let triplesChanged = snapshot.triples != previousSnapshot.triples
    let attributesChanged = snapshot.attributes != previousSnapshot.attributes
    let didSave = try transaction {
      guard
        try loadMetadataRevisionWithoutTransaction(Self.storeRevisionKey) == expectedStoreRevision,
        try loadMetadataRevisionWithoutTransaction(Self.outboxRevisionKey) == expectedOutboxRevision,
        try loadMetadataRevisionWithoutTransaction(Self.attributeRevisionKey)
          == expectedAttributeRevision
      else {
        return false
      }
      if !allowsActiveOptimisticOwners {
        try requireNoActiveOptimisticOwnerForPublicStoreChangeWithoutTransaction(
          from: previousSnapshot,
          to: snapshot
        )
      }
      try saveStoreSnapshotDiffWithoutTransaction(from: previousSnapshot, to: snapshot)
      if triplesChanged {
        _ = try bumpMetadataRevisionWithoutTransaction(Self.storeRevisionKey)
      }
      if attributesChanged {
        _ = try bumpMetadataRevisionWithoutTransaction(Self.attributeRevisionKey)
      }
      return true
    }
    if didSave, var cachedState,
      cachedState.storeRevision == expectedStoreRevision,
      cachedState.attributeRevision == expectedAttributeRevision,
      cachedState.outboxRevision == expectedOutboxRevision
    {
      cachedState.snapshot.store = snapshot
      cachedState.storeRevision += triplesChanged ? 1 : 0
      cachedState.attributeRevision += attributesChanged ? 1 : 0
      adoptCachedState(cachedState)
    } else if didSave {
      cachedState = nil
    }
    return didSave
  }

  public func saveSnapshot(
    _ snapshot: InstantPersistenceSnapshot,
    replacing previousSnapshot: InstantPersistenceSnapshot? = nil,
    metadataKey: String,
    metadataValue: String,
    metadataUpdatedAt: InstantTimestamp,
    expectedStoreRevision: Int64,
    expectedAttributeRevision: Int64,
    expectedOutboxRevision: Int64
  ) throws -> Bool {
    let revisions: (store: Int64, attributes: Int64, outbox: Int64)? = try transaction {
      () -> (store: Int64, attributes: Int64, outbox: Int64)? in
      guard
        try loadMetadataRevisionWithoutTransaction(Self.storeRevisionKey) == expectedStoreRevision,
        try loadMetadataRevisionWithoutTransaction(Self.attributeRevisionKey)
          == expectedAttributeRevision,
        try loadMetadataRevisionWithoutTransaction(Self.outboxRevisionKey) == expectedOutboxRevision
      else {
        return nil
      }
      // `cachedState` is intentionally memory compacted: it may omit every
      // triple and every transaction body. It therefore cannot be the previous
      // side of a durable diff. Runtime callers pass the already-hydrated state;
      // direct callers fall back to one atomic SQLite read.
      let previousSnapshot = try previousSnapshot
        ?? loadSnapshotWithoutTransaction(tracesStartupCollections: false)
      try requireNoActiveOptimisticOwnerForPublicStoreChangeWithoutTransaction(
        from: previousSnapshot.store,
        to: snapshot.store
      )
      try saveStoreSnapshotDiffWithoutTransaction(
        from: previousSnapshot.store,
        to: snapshot.store
      )
      try saveOutboxDiffWithoutTransaction(
        from: previousSnapshot.outbox,
        to: snapshot.outbox,
        receiptWriteAuthority: .publicPersistence
      )
      try saveMetadataValueWithoutTransaction(
        metadataValue,
        key: metadataKey,
        updatedAt: metadataUpdatedAt
      )
      return (
        store: try bumpMetadataRevisionWithoutTransaction(Self.storeRevisionKey),
        attributes: try bumpMetadataRevisionWithoutTransaction(Self.attributeRevisionKey),
        outbox: try bumpMetadataRevisionWithoutTransaction(Self.outboxRevisionKey)
      )
    }
    if let revisions {
      adoptCachedState(InstantPersistenceState(
        snapshot: snapshot,
        storeRevision: revisions.store,
        outboxRevision: revisions.outbox,
        attributeRevision: revisions.attributes
      ))
    }
    return revisions != nil
  }

  public func saveOutbox(
    _ mutations: [PendingMutation],
    replacing previousMutations: [PendingMutation]? = nil,
    metadataKey: String,
    metadataValue: String,
    metadataUpdatedAt: InstantTimestamp,
    expectedStoreRevision: Int64,
    expectedOutboxRevision: Int64
  ) throws -> Bool {
    let didSave = try transaction {
      guard
        try loadMetadataRevisionWithoutTransaction(Self.storeRevisionKey) == expectedStoreRevision,
        try loadMetadataRevisionWithoutTransaction(Self.outboxRevisionKey) == expectedOutboxRevision
      else {
        return false
      }
      let previousMutations = try previousMutations
        ?? loadOutboxWithoutTransaction(tracesStartupCollections: false)
      try saveOutboxDiffWithoutTransaction(
        from: previousMutations,
        to: mutations,
        receiptWriteAuthority: .publicPersistence
      )
      try saveMetadataValueWithoutTransaction(
        metadataValue,
        key: metadataKey,
        updatedAt: metadataUpdatedAt
      )
      _ = try bumpMetadataRevisionWithoutTransaction(Self.outboxRevisionKey)
      return true
    }
    if didSave { cachedState = nil }
    return didSave
  }

  public func saveStoreSnapshot(
    _ snapshot: InstantStoreSnapshot,
    replacing previousSnapshot: InstantStoreSnapshot? = nil,
    metadataKey: String,
    metadataValue: String,
    metadataUpdatedAt: InstantTimestamp,
    expectedStoreRevision: Int64,
    expectedOutboxRevision: Int64,
    expectedAttributeRevision: Int64
  ) throws -> Bool {
    let previousState = cachedState
    let revisions: (store: Int64, attributes: Int64)? = try transaction {
      () -> (store: Int64, attributes: Int64)? in
      guard
        try loadMetadataRevisionWithoutTransaction(Self.storeRevisionKey) == expectedStoreRevision,
        try loadMetadataRevisionWithoutTransaction(Self.outboxRevisionKey) == expectedOutboxRevision,
        try loadMetadataRevisionWithoutTransaction(Self.attributeRevisionKey)
          == expectedAttributeRevision
      else {
        return nil
      }
      let previousSnapshot = try previousSnapshot
        ?? loadStoreSnapshotWithoutTransaction(tracesStartupCollections: false)
      let triplesChanged = snapshot.triples != previousSnapshot.triples
      let attributesChanged = snapshot.attributes != previousSnapshot.attributes
      try requireNoActiveOptimisticOwnerForPublicStoreChangeWithoutTransaction(
        from: previousSnapshot,
        to: snapshot
      )
      try saveStoreSnapshotDiffWithoutTransaction(
        from: previousSnapshot,
        to: snapshot
      )
      try saveMetadataValueWithoutTransaction(
        metadataValue,
        key: metadataKey,
        updatedAt: metadataUpdatedAt
      )
      return (
        store: triplesChanged
          ? try bumpMetadataRevisionWithoutTransaction(Self.storeRevisionKey)
          : expectedStoreRevision,
        attributes: attributesChanged
          ? try bumpMetadataRevisionWithoutTransaction(Self.attributeRevisionKey)
          : expectedAttributeRevision
      )
    }
    if let revisions, var previousState,
      previousState.storeRevision == expectedStoreRevision,
      previousState.outboxRevision == expectedOutboxRevision,
      previousState.attributeRevision == expectedAttributeRevision
    {
      previousState.snapshot.store = snapshot
      previousState.storeRevision = revisions.store
      previousState.attributeRevision = revisions.attributes
      adoptCachedState(previousState)
    } else if revisions != nil {
      cachedState = nil
    }
    return revisions != nil
  }

  func saveLiveRefresh(
    _ snapshot: InstantPersistenceSnapshot,
    replacing previousSnapshot: InstantPersistenceSnapshot? = nil,
    queryResults: [InstantPersistedLiveQueryResult],
    storeChanged: Bool,
    outboxChanged: Bool,
    metadataKey: String,
    metadataValue: String,
    metadataUpdatedAt: InstantTimestamp,
    expectedStoreRevision: Int64,
    expectedOutboxRevision: Int64,
    expectedAttributeRevision: Int64
  ) throws -> Bool {
    let revisions: (
      store: Int64,
      attributes: Int64,
      outbox: Int64,
      queryResults: Int64
    )? = try transaction {
      () -> (store: Int64, attributes: Int64, outbox: Int64, queryResults: Int64)? in
      guard
        try loadMetadataRevisionWithoutTransaction(Self.storeRevisionKey) == expectedStoreRevision,
        try loadMetadataRevisionWithoutTransaction(Self.outboxRevisionKey) == expectedOutboxRevision,
        try loadMetadataRevisionWithoutTransaction(Self.attributeRevisionKey)
          == expectedAttributeRevision
      else {
        return nil
      }
      var triplesChanged = false
      var attributesChanged = false
      if storeChanged {
        let previousStoreSnapshot = try previousSnapshot?.store
          ?? loadStoreSnapshotWithoutTransaction(tracesStartupCollections: false)
        triplesChanged = snapshot.store.triples != previousStoreSnapshot.triples
        attributesChanged = snapshot.store.attributes != previousStoreSnapshot.attributes
        try saveStoreSnapshotDiffWithoutTransaction(
          from: previousStoreSnapshot,
          to: snapshot.store
        )
      }
      if outboxChanged {
        let previousOutbox = try previousSnapshot?.outbox
          ?? loadOutboxWithoutTransaction(tracesStartupCollections: false)
        try saveOutboxDiffWithoutTransaction(
          from: previousOutbox,
          to: snapshot.outbox,
          receiptWriteAuthority: .publicPersistence
        )
      }
      for result in queryResults {
        try saveLiveQueryResultWithoutTransaction(result)
      }
      try saveMetadataValueWithoutTransaction(
        metadataValue,
        key: metadataKey,
        updatedAt: metadataUpdatedAt
      )
      return (
        store: triplesChanged
          ? try bumpMetadataRevisionWithoutTransaction(Self.storeRevisionKey)
          : expectedStoreRevision,
        attributes: attributesChanged
          ? try bumpMetadataRevisionWithoutTransaction(Self.attributeRevisionKey)
          : expectedAttributeRevision,
        outbox: outboxChanged
          ? try bumpMetadataRevisionWithoutTransaction(Self.outboxRevisionKey)
          : expectedOutboxRevision,
        queryResults: queryResults.isEmpty
          ? try loadMetadataRevisionWithoutTransaction(Self.queryResultRevisionKey)
          : try bumpMetadataRevisionWithoutTransaction(Self.queryResultRevisionKey)
      )
    }
    if outboxChanged, revisions != nil {
      cachedState = nil
    } else if let revisions, var cachedState,
      cachedState.storeRevision == expectedStoreRevision,
      cachedState.outboxRevision == expectedOutboxRevision,
      cachedState.attributeRevision == expectedAttributeRevision
    {
      if storeChanged {
        cachedState.snapshot.store = snapshot.store
      }
      if outboxChanged {
        cachedState.snapshot.outbox = snapshot.outbox
      }
      cachedState.storeRevision = revisions.store
      cachedState.attributeRevision = revisions.attributes
      cachedState.outboxRevision = revisions.outbox
      cachedState.queryResultRevision = revisions.queryResults
      adoptCachedState(cachedState)
    } else if revisions != nil {
      cachedState = nil
    }
    return revisions != nil
  }

  public func saveQueryCache(
    _ entry: InstantCachedQuery,
    expectedStoreRevision: Int64,
    expectedAttributeRevision: Int64? = nil
  ) throws -> Bool {
    try transaction {
      let attributeRevisionMatches = if let expectedAttributeRevision {
        try loadMetadataRevisionWithoutTransaction(Self.attributeRevisionKey)
          == expectedAttributeRevision
      } else {
        true
      }
      guard
        try loadMetadataRevisionWithoutTransaction(Self.storeRevisionKey) == expectedStoreRevision,
        attributeRevisionMatches
      else {
        return false
      }

      try saveQueryCacheEntryWithoutTransaction(entry)
      return true
    }
  }

  func saveQueryCache(
    _ entries: [InstantCachedQuery],
    expectedStoreRevision: Int64,
    expectedAttributeRevision: Int64? = nil
  ) throws -> Bool {
    try transaction {
      let attributeRevisionMatches = if let expectedAttributeRevision {
        try loadMetadataRevisionWithoutTransaction(Self.attributeRevisionKey)
          == expectedAttributeRevision
      } else {
        true
      }
      guard
        try loadMetadataRevisionWithoutTransaction(Self.storeRevisionKey) == expectedStoreRevision,
        attributeRevisionMatches
      else {
        return false
      }

      for entry in entries {
        try saveQueryCacheEntryWithoutTransaction(entry)
      }
      return true
    }
  }

  func deleteQueryCache(cacheKey: String) throws {
    try execute(
      "DELETE FROM instant_query_cache WHERE cache_key = ?",
      [.text(cacheKey)]
    )
  }

  public func localID(named name: String, makeID: @Sendable () -> String) throws -> String {
    if let existing = try selectScalar(
      "SELECT entity_id FROM instant_local_ids WHERE name = ? LIMIT 1",
      [.text(name)]
    ) {
      return existing
    }

    let id = makeID()
    try execute(
      "INSERT OR IGNORE INTO instant_local_ids (name, entity_id) VALUES (?, ?)",
      [.text(name), .text(id)]
    )
    if let persisted = try selectScalar(
      "SELECT entity_id FROM instant_local_ids WHERE name = ? LIMIT 1",
      [.text(name)]
    ) {
      return persisted
    }

    throw persistenceError(
      operation: "resolve local id",
      message: "SQLite did not return a local id for name '\(name)' after inserting it."
    )
  }

  public func loadLocalIDs() throws -> [InstantLocalID] {
    var statement: OpaquePointer?
    try prepare(
      """
      SELECT name, entity_id FROM instant_local_ids
      ORDER BY name
      """,
      statement: &statement
    )
    defer { sqlite3_finalize(statement) }

    var localIDs: [InstantLocalID] = []
    while true {
      let code = sqlite3_step(statement)
      if code == SQLITE_DONE {
        return localIDs
      }
      guard code == SQLITE_ROW else {
        throw persistenceError(operation: "list local ids", message: lastErrorMessage())
      }
      guard let name = sqlite3_column_text(statement, 0),
        let entityID = sqlite3_column_text(statement, 1)
      else {
        throw persistenceError(
          operation: "list local ids",
          message: "SQLite returned a NULL local id row."
        )
      }
      localIDs.append(
        InstantLocalID(
          name: String(cString: name),
          entityID: String(cString: entityID)
        )
      )
    }
  }

  private func migrate(name: String, body: () throws -> Void) throws {
    try transaction {
      let alreadyApplied: String? = try selectScalar(
        "SELECT name FROM instant_schema_migrations WHERE name = ? LIMIT 1",
        [.text(name)]
      )
      guard alreadyApplied == nil else { return }
      try body()
      try execute(
        "INSERT OR IGNORE INTO instant_schema_migrations (name, applied_at_ms) VALUES (?, ?)",
        [.text(name), .int(Self.nowMilliseconds())]
      )
    }
  }

  /// Grandfathers only receipt shapes that deployed Runtime versions could
  /// durably prepare before migration 0020. This is a one-time compatibility
  /// trust decision, not a proof callers can recreate after the column exists.
  /// Public writes after 0020 can only preserve a matching database-owned
  /// fingerprint.
  ///
  /// The cursor reads one scalar row at a time and decodes at most one bounded
  /// 8-MiB body, so migration memory is independent of total outbox depth.
  private func backfillPreexistingRuntimePreparedReceiptFingerprintsWithoutTransaction() throws {
    var cursorMutationID: String?
    var didBackfill = false
    while true {
      var statement: OpaquePointer?
      let sql: String
      let bindings: [SQLiteBinding]
      if let cursorMutationID {
        sql =
          """
          SELECT mutation_id, created_at_ms, length(CAST(json AS BLOB)),
                 status, server_transaction_id, confirmation_source,
                 optimistic_overlay_active, confirmation_proven,
                 delivery_metadata_version
          FROM instant_outbox
          WHERE mutation_id > ?
          ORDER BY mutation_id
          LIMIT 1
          """
        bindings = [.text(cursorMutationID)]
      } else {
        sql =
          """
          SELECT mutation_id, created_at_ms, length(CAST(json AS BLOB)),
                 status, server_transaction_id, confirmation_source,
                 optimistic_overlay_active, confirmation_proven,
                 delivery_metadata_version
          FROM instant_outbox
          ORDER BY mutation_id
          LIMIT 1
          """
        bindings = []
      }
      try prepare(
        sql,
        statement: &statement
      )
      defer { sqlite3_finalize(statement) }
      try bind(bindings, to: statement)
      let code = sqlite3_step(statement)
      if code == SQLITE_DONE { break }
      guard code == SQLITE_ROW,
        let mutationIDBytes = sqlite3_column_text(statement, 0),
        let statusBytes = sqlite3_column_text(statement, 3),
        sqlite3_column_type(statement, 2) != SQLITE_NULL
      else {
        throw persistenceError(
          operation: "backfill optimistic-effect receipt fingerprints",
          message: lastErrorMessage()
        )
      }
      let mutationID = String(cString: mutationIDBytes)
      cursorMutationID = mutationID
      let createdAtMilliseconds = sqlite3_column_int64(statement, 1)
      let bodyByteCount = sqlite3_column_int64(statement, 2)
      let scalarStatus = String(cString: statusBytes)
      let scalarServerTransactionID = sqlite3_column_text(statement, 4)
        .map(String.init(cString:))
      let scalarConfirmationSource = sqlite3_column_text(statement, 5)
        .map(String.init(cString:))
      let scalarOverlayIsActive = sqlite3_column_int64(statement, 6) != 0
      let scalarConfirmationIsProven: Bool? =
        sqlite3_column_type(statement, 7) == SQLITE_NULL
        ? nil
        : sqlite3_column_int64(statement, 7) != 0
      let predatesBoundedDeliveryMetadata = sqlite3_column_int64(statement, 8) == 0
      guard bodyByteCount >= 0,
        bodyByteCount <= Int64(InstantAutomaticOutboxClaimLimits.maximumEncodedBodyBytes),
        let row = try loadOutboxBodyRowWithoutTransaction(id: mutationID),
        row.createdAtMilliseconds == createdAtMilliseconds,
        row.json.utf8.count == Int(bodyByteCount),
        var mutation: PendingMutation = try? decodeOutboxBody(row.json),
        mutation.id == mutationID,
        mutation.transaction.id == mutation.id,
        mutation.createdAt.milliseconds == createdAtMilliseconds,
        mutation.status.rawValue == scalarStatus,
        mutation.serverTransactionID == scalarServerTransactionID,
        mutation.confirmationSource?.rawValue == scalarConfirmationSource,
        mutation.optimisticOverlayState != nil,
        mutation.optimisticEffectReceiptVersion == nil,
        (
          (mutation.optimisticOverlayState != .removed) == scalarOverlayIsActive
            || (predatesBoundedDeliveryMetadata && scalarOverlayIsActive)
        ),
        !mutation.transaction.operations.isEmpty,
        InstantOutboxDeliveryMetadata.stepCount(in: mutation)
          <= InstantAutomaticOutboxClaimLimits.maximumStepCount
      else { continue }

      switch mutation.optimisticOverlayState {
      case .applied:
        if let rollback = mutation.rollbackTransaction {
          guard rollback.id == "rollback-\(mutation.id)",
            !rollback.operations.isEmpty,
            rollback.operations.allSatisfy(Self.isPreReceiptRuntimeRollbackOperation)
          else { continue }
        } else {
          // Pre-receipt Runtime used `.applied` plus a nil inverse when semantic
          // preparation or a forward replay produced no current store diff.
          // Keep the old-decoder-safe `.applied` value and add the explicit
          // receipt version introduced alongside this external authority column.
        }

      case .removed:
        guard mutation.status == .failed, mutation.rollbackTransaction == nil else {
          continue
        }

      case nil:
        continue
      }
      mutation.optimisticEffectReceiptVersion =
        PendingMutation.currentOptimisticEffectReceiptVersion

      guard let fingerprint = try? mutation.optimisticEffectReceiptFingerprint(),
        let effectFootprint = InstantOptimisticEffectFootprint.normalized(for: mutation)
      else { continue }
      let encodedBody = try encode(mutation)
      guard encodedBody.utf8.count
        <= InstantAutomaticOutboxClaimLimits.maximumEncodedBodyBytes
      else { continue }
      let acceptanceFingerprint = mutation.status == .confirmed
        && mutation.provesServerAcceptance
        && (
          scalarConfirmationIsProven == true
            || (predatesBoundedDeliveryMetadata && scalarConfirmationIsProven == nil)
        )
        ? try mutation.mutationWireIntentFingerprint()
        : nil
      let deliveryState = durableDeliveryState(
        for: mutation,
        hasServerAcceptance: acceptanceFingerprint != nil
      )
      try execute(
        """
        UPDATE instant_outbox
        SET json = ?, lifecycle_json = ?, encoded_body_bytes = ?,
            delivery_metadata_version = ?, transport_step_count = ?,
            optimistic_effect_receipt_fingerprint = ?,
            server_acceptance_payload_fingerprint = ?,
            confirmation_proven = ?, delivery_state = ?,
            optimistic_overlay_active = ?,
            optimistic_effect_metadata_version = ?,
            optimistic_effect_is_global = ?,
            mutation_revision = mutation_revision + 1
        WHERE mutation_id = ?
          AND created_at_ms = ?
          AND optimistic_effect_receipt_fingerprint IS NULL
          AND json = ?
        """,
        [
          .text(encodedBody),
          .text(try encode(mutation.compactedForMemory)),
          .int(Int64(encodedBody.utf8.count)),
          .int(Int64(InstantOutboxDeliveryMetadata.currentVersion)),
          .int(Int64(InstantOutboxDeliveryMetadata.stepCount(in: mutation))),
          .text(fingerprint),
          acceptanceFingerprint.map(SQLiteBinding.text) ?? .null,
          .int(acceptanceFingerprint == nil ? 0 : 1),
          .text(deliveryState.rawValue),
          .int(mutation.optimisticOverlayState == .removed ? 0 : 1),
          .int(Int64(InstantOptimisticEffectFootprint.currentVersion)),
          .int(effectFootprint.isGlobal ? 1 : 0),
          .text(mutationID),
          .int(createdAtMilliseconds),
          .text(row.json),
        ]
      )
      guard sqlite3_changes(connection.raw) == 1 else { continue }
      try replaceOutboxEffectEntitiesWithoutTransaction(
        mutationID: mutationID,
        createdAtMilliseconds: createdAtMilliseconds,
        entityIDs: effectFootprint.entityIDs
      )
      try replaceOutboxWriteKeysWithoutTransaction(for: mutation)
      didBackfill = true
    }
    // A pre-0020 body that merely *says* it was accepted or removed has no
    // SQLite-owned binding to the accepted payload or local materialization.
    // Keep it retained and globally conservative, but neither resend nor prune
    // it as an explicit manual-repair barrier rather than guessing the state.
    try execute(
      """
      UPDATE instant_outbox
      SET confirmation_proven = 0,
          delivery_state = CASE
            WHEN status = 'confirmed'
              AND (server_transaction_id IS NOT NULL OR confirmation_source IN (?, ?))
            THEN ?
            ELSE delivery_state
          END,
          optimistic_overlay_active = 1,
          optimistic_effect_metadata_version = 0,
          optimistic_effect_is_global = 0
      WHERE optimistic_effect_receipt_fingerprint IS NULL
      """,
      [
        .text(InstantMutationConfirmationSource.webSocketTransactOK.rawValue),
        .text(InstantMutationConfirmationSource.serverTransport.rawValue),
        .text(InstantOutboxDeliveryState.invalid.rawValue),
      ]
    )
    if sqlite3_changes(connection.raw) > 0 {
      didBackfill = true
    }
    // Version-zero rows are deliberately global and fail closed. Remove any
    // stale pre-migration indexes so no future bounded selector can mistake a
    // caller-shaped receipt for SQLite-owned entity or write-key authority.
    try execute(
      """
      DELETE FROM instant_outbox_effect_entities
      WHERE mutation_id IN (
        SELECT mutation_id
        FROM instant_outbox
        WHERE optimistic_effect_receipt_fingerprint IS NULL
      )
      """
    )
    if sqlite3_changes(connection.raw) > 0 {
      didBackfill = true
    }
    try execute(
      """
      DELETE FROM instant_outbox_write_keys
      WHERE mutation_id IN (
        SELECT mutation_id
        FROM instant_outbox
        WHERE optimistic_effect_receipt_fingerprint IS NULL
      )
      """
    )
    if sqlite3_changes(connection.raw) > 0 {
      didBackfill = true
    }
    if didBackfill {
      _ = try bumpMetadataRevisionWithoutTransaction(Self.outboxRevisionKey)
    }
  }

  private static func isPreReceiptRuntimeRollbackOperation(
    _ operation: InstantTripleOperation
  ) -> Bool {
    switch operation {
    case .insert, .retract, .deleteEntity:
      true
    case .requireEntityMissing,
      .requireEntityMissingByLookup,
      .requireEntityExists,
      .requireEntityExistsByLookup,
      .requireTripleExists,
      .merge,
      .mergeByLookup,
      .insertByLookup,
      .retractByLookup,
      .deleteEntityInNamespace,
      .deleteEntityByLookup,
      .ruleParams,
      .ruleParamsByLookup:
      false
    }
  }

  /// Server rebase uses the connection-local SQLite temp database as a bounded
  /// spool. A component may contain thousands of durable mutation bodies, but
  /// Runtime holds at most one 50-body / 8-MiB page while this table preserves
  /// the one atomic final store-and-outbox transition.
  private func ensureServerApplyStagingSchema() throws {
    try execute(
      """
      CREATE TEMP TABLE IF NOT EXISTS instant_server_apply_plans (
        plan_id TEXT PRIMARY KEY NOT NULL,
        expected_store_revision INTEGER NOT NULL,
        expected_attribute_revision INTEGER NOT NULL,
        expected_outbox_revision INTEGER NOT NULL,
        expected_query_result_revision INTEGER NOT NULL,
        processed_transaction_id TEXT NOT NULL,
        processed_transaction_number INTEGER,
        server_has_operations INTEGER NOT NULL,
        root_is_global INTEGER NOT NULL,
        confirming_mutation_id TEXT,
        confirming_claimant_id TEXT
      )
      """
    )
    try execute(
      """
      CREATE TEMP TABLE IF NOT EXISTS instant_server_apply_roots (
        plan_id TEXT NOT NULL,
        entity_id TEXT NOT NULL,
        PRIMARY KEY (plan_id, entity_id)
      ) WITHOUT ROWID
      """
    )
    try execute(
      """
      CREATE TEMP TABLE IF NOT EXISTS instant_server_apply_rows (
        plan_id TEXT NOT NULL,
        mutation_id TEXT NOT NULL,
        created_at_ms INTEGER NOT NULL,
        expected_mutation_revision INTEGER NOT NULL,
        expected_status TEXT NOT NULL,
        expected_confirmation_proven INTEGER NOT NULL,
        expected_overlay_active INTEGER NOT NULL,
        expected_effect_metadata_version INTEGER NOT NULL,
        expected_effect_is_global INTEGER NOT NULL,
        expected_effect_receipt_fingerprint TEXT,
        expected_delivery_started INTEGER NOT NULL,
        expected_delivery_claim_payload_fingerprint TEXT,
        expected_delivery_claimant_id TEXT,
        expected_server_acceptance_payload_fingerprint TEXT,
        expected_body_bytes INTEGER NOT NULL,
        is_component_body INTEGER NOT NULL DEFAULT 0,
        requires_body INTEGER NOT NULL DEFAULT 0,
        is_catch_up INTEGER NOT NULL DEFAULT 0,
        prune_at_watermark INTEGER NOT NULL DEFAULT 0,
        confirm_at_apply INTEGER NOT NULL DEFAULT 0,
        original_json TEXT,
        staged_json TEXT,
        staged_lifecycle_json TEXT,
        staged_status TEXT,
        staged_delivery_state TEXT,
        staged_transport_step_count INTEGER,
        staged_failure_message TEXT,
        staged_confirmation_proven INTEGER,
        staged_overlay_active INTEGER,
        staged_effect_metadata_version INTEGER,
        staged_effect_is_global INTEGER,
        staged_effect_receipt_fingerprint TEXT,
        staged_server_acceptance_payload_fingerprint TEXT,
        staged_server_transaction_id TEXT,
        staged_confirmation_source TEXT,
        staged_delete INTEGER NOT NULL DEFAULT 0,
        staged INTEGER NOT NULL DEFAULT 0,
        PRIMARY KEY (plan_id, mutation_id)
      ) WITHOUT ROWID
      """
    )
    try execute(
      """
      CREATE TEMP TABLE IF NOT EXISTS instant_server_apply_effect_entities (
        plan_id TEXT NOT NULL,
        mutation_id TEXT NOT NULL,
        entity_id TEXT NOT NULL,
        created_at_ms INTEGER NOT NULL,
        PRIMARY KEY (plan_id, mutation_id, entity_id)
      ) WITHOUT ROWID
      """
    )
    try execute(
      """
      CREATE INDEX IF NOT EXISTS instant_server_apply_rows_order_idx
      ON instant_server_apply_rows (plan_id, requires_body, created_at_ms, mutation_id)
      """
    )
  }

  private func withSQLiteBusyRetry<Value>(_ operation: () throws -> Value) throws -> Value {
    var lastError: Error?
    for attempt in 0..<6 {
      do {
        return try operation()
      } catch let error as InstantError where error.code == .persistenceFailed && error.isSQLiteBusy
      {
        lastError = error
        Thread.sleep(forTimeInterval: 0.025 * Double(attempt + 1))
      }
    }

    if let lastError {
      throw lastError
    }
    return try operation()
  }

  @discardableResult
  private func transaction<Value>(_ body: () throws -> Value) throws -> Value {
    precondition(
      activeOutboxQuarantineIssueBatch == nil,
      "SQLite persistence transactions must not be nested."
    )
    try execute("BEGIN IMMEDIATE TRANSACTION")
    activeOutboxQuarantineIssueBatch = InstantOutboxQuarantineIssueBatch()
    do {
      let value = try body()
      try execute("COMMIT")
      let issueBatch = activeOutboxQuarantineIssueBatch
      activeOutboxQuarantineIssueBatch = nil
      reportOutboxQuarantineIssueBatch(issueBatch)
      return value
    } catch {
      try? execute("ROLLBACK")
      activeOutboxQuarantineIssueBatch = nil
      // Marker helpers participate in the same transaction but live on the actor. A rollback must
      // discard their speculative cache so the next writer reloads the durable marker instead of
      // trusting state that SQLite did not commit.
      installedDeclaredRelationStorageMarker = nil
      installedDeclaredRelationStorageObsoleteAttributeIDs = []
      didLoadDeclaredRelationStorageMarker = false
      throw error
    }
  }

  @discardableResult
  private func readTransaction<Value>(_ body: () throws -> Value) throws -> Value {
    try execute("BEGIN DEFERRED TRANSACTION")
    do {
      let value = try body()
      try execute("COMMIT")
      return value
    } catch {
      try? execute("ROLLBACK")
      throw error
    }
  }

  private func loadAutomaticDeliveryCandidateRowsWithoutTransaction(
    limit: Int
  ) throws -> [InstantOutboxDeliveryCandidateRow] {
    let sql =
      """
      SELECT
        mutation_id,
        created_at_ms,
        delivery_metadata_version,
        transport_step_count,
        COALESCE(encoded_body_bytes, length(CAST(json AS BLOB))),
        status,
        delivery_started
      FROM instant_outbox
      WHERE delivery_claim_state = ?
        AND (
          delivery_state = ?
          OR (status IN (?, ?) AND delivery_metadata_version < ?)
        )
      ORDER BY created_at_ms, mutation_id
      LIMIT ?
      """
    let bindings: [SQLiteBinding] = [
      .text(InstantOutboxDeliveryClaimState.ready.rawValue),
      .text(InstantOutboxDeliveryState.needsDelivery.rawValue),
      .text(InstantMutationStatus.pending.rawValue),
      .text(InstantMutationStatus.confirmed.rawValue),
      .int(Int64(InstantOutboxDeliveryMetadata.currentVersion)),
      .int(Int64(limit)),
    ]
    return try loadOutboxDeliveryCandidateRowsWithoutTransaction(sql, bindings)
  }

  private func loadFailedOutboxLifecycleCandidatesWithoutTransaction(
    limit: Int
  ) throws -> [InstantFailedOutboxLifecycleCandidateRow] {
    var statement: OpaquePointer?
    try prepare(
      """
      SELECT mutation_id, created_at_ms,
             CASE WHEN lifecycle_json IS NULL
               THEN NULL ELSE length(CAST(lifecycle_json AS BLOB)) END,
             COALESCE(encoded_body_bytes, length(CAST(json AS BLOB))),
             optimistic_effect_receipt_fingerprint IS NOT NULL
      FROM instant_outbox
      WHERE status = ? AND (
        delivery_metadata_version < ? OR lifecycle_json IS NULL OR
        LOWER(COALESCE(failure_message, '')) LIKE '%operation timed out%' OR
        LOWER(COALESCE(failure_message, '')) LIKE '%transaction timed out%' OR
        LOWER(COALESCE(failure_message, '')) LIKE '%service unavailable%' OR
        LOWER(COALESCE(failure_message, '')) LIKE '%temporarily unavailable%' OR
        LOWER(COALESCE(failure_message, '')) LIKE '%could not resolve%'
      )
      ORDER BY CASE
        WHEN LOWER(COALESCE(failure_message, '')) LIKE '%operation timed out%'
          OR LOWER(COALESCE(failure_message, '')) LIKE '%transaction timed out%'
          OR LOWER(COALESCE(failure_message, '')) LIKE '%service unavailable%'
          OR LOWER(COALESCE(failure_message, '')) LIKE '%temporarily unavailable%'
          OR LOWER(COALESCE(failure_message, '')) LIKE '%could not resolve%'
        THEN 0 ELSE 1 END,
        created_at_ms, mutation_id
      LIMIT ?
      """,
      statement: &statement
    )
    defer { sqlite3_finalize(statement) }
    try bind(
      [
        .text(InstantMutationStatus.failed.rawValue),
        .int(Int64(InstantOutboxDeliveryMetadata.currentVersion)),
        .int(Int64(limit)),
      ],
      to: statement
    )
    var rows: [InstantFailedOutboxLifecycleCandidateRow] = []
    rows.reserveCapacity(limit)
    while true {
      let code = sqlite3_step(statement)
      if code == SQLITE_DONE { return rows }
      guard code == SQLITE_ROW,
        let mutationIDBytes = sqlite3_column_text(statement, 0)
      else {
        throw persistenceError(
          operation: "read failed mutation lifecycle candidates",
          message: lastErrorMessage()
        )
      }
      rows.append(
        InstantFailedOutboxLifecycleCandidateRow(
          mutationID: String(cString: mutationIDBytes),
          createdAtMilliseconds: sqlite3_column_int64(statement, 1),
          lifecycleByteCount: sqlite3_column_type(statement, 2) == SQLITE_NULL
            ? nil
            : Int(sqlite3_column_int64(statement, 2)),
          bodyByteCount: Int(sqlite3_column_int64(statement, 3)),
          hasReceiptFingerprint: sqlite3_column_int64(statement, 4) != 0
        )
      )
    }
  }

  private func loadAutomaticFailedMutationRetryPlanWithoutTransaction(
    after position: InstantOutboxDeliveryPosition?,
    excludingMutationIDs: Set<String>,
    maximumBodyCount: Int,
    maximumEncodedBodyByteCount: Int,
    expectedAttributeRevision: Int64
  ) throws -> InstantFailedMutationRetryPlan {
    let candidates = try loadAutomaticFailedMutationRetryCandidatesWithoutTransaction(
      after: position,
      excludingMutationIDs: excludingMutationIDs,
      limit: maximumBodyCount + 1,
      expectedAttributeRevision: expectedAttributeRevision
    )
    var dispositions: [InstantFailedMutationRetryDisposition] = []
    var decodedBodyCount = 0
    var decodedBodyByteCount = 0
    dispositions.reserveCapacity(min(maximumBodyCount, candidates.count))

    for candidate in candidates {
      guard dispositions.count < maximumBodyCount else { break }
      if candidate.actualBodyByteCount > maximumEncodedBodyByteCount {
        dispositions.append(.quarantineOversized(candidate: candidate))
        continue
      }
      guard candidate.actualBodyByteCount >= 0 else {
        throw persistenceError(
          operation: "load automatic failed-mutation retry window",
          message: "SQLite returned a negative mutation body length for '\(candidate.mutationID)'."
        )
      }
      guard candidate.actualBodyByteCount <= maximumEncodedBodyByteCount - decodedBodyByteCount
      else { break }
      guard let row = try loadOutboxBodyRowWithoutTransaction(id: candidate.mutationID) else {
        throw persistenceError(
          operation: "load automatic failed-mutation retry window",
          message: "Retry candidate '\(candidate.mutationID)' disappeared inside one SQLite snapshot."
        )
      }
      guard row.json.utf8.count == candidate.actualBodyByteCount else {
        throw persistenceError(
          operation: "load automatic failed-mutation retry window",
          message: "Retry candidate '\(candidate.mutationID)' changed length inside one SQLite snapshot."
        )
      }

      decodedBodyCount += 1
      decodedBodyByteCount += candidate.actualBodyByteCount
      decodedOutboxBodyCount += 1
      decodedOutboxBodyByteCount += candidate.actualBodyByteCount
      do {
        var mutation: PendingMutation = try decodeOutboxBody(row.json)
        guard mutation.id == candidate.mutationID,
          mutation.status == .failed,
          mutation.failureMessage.map(
            InstantAutomaticFailedMutationRetryPolicy.isRetryableFailureMessage
          ) == true
        else {
          dispositions.append(
            .quarantineCorrupt(
              candidate: candidate,
              row: row,
              reason:
                "The durable body disagreed with its indexed transient-failure lifecycle metadata."
            )
          )
          continue
        }
        guard mutation.provesReplayableOptimisticEffectReceipt,
          try hasStoredPreparedOptimisticEffectReceiptWithoutTransaction(mutation)
        else {
          let reason =
            "Its durable body does not have a matching SQLite-owned Runtime-prepared optimistic-effect receipt."
          let message =
            "Instant isolated failed mutation '\(mutation.id)' from automatic retry. \(reason)"
          mutation.failureMessage = message
          mutation.failure = InstantMutationFailure(code: .persistenceFailed, message: message)
          dispositions.append(
            .isolate(
              candidate: candidate,
              originalJSON: row.json,
              mutation: mutation,
              reason: reason
            )
          )
          continue
        }

        mutation.status = .pending
        mutation.failureMessage = nil
        mutation.failure = nil
        mutation.serverTransactionID = nil
        mutation.confirmationSource = nil
        dispositions.append(
          .retry(
            candidate: candidate,
            originalJSON: row.json,
            mutation: mutation
          )
        )
      } catch {
        dispositions.append(
          .quarantineCorrupt(
            candidate: candidate,
            row: row,
            reason: "The indexed transient-failure body could not be decoded: \(error)"
          )
        )
      }
    }
    return InstantFailedMutationRetryPlan(
      dispositions: dispositions,
      decodedBodyCount: decodedBodyCount,
      decodedBodyByteCount: decodedBodyByteCount,
      expectedAttributeRevision: expectedAttributeRevision
    )
  }

  private func loadAutomaticFailedMutationRetryCandidatesWithoutTransaction(
    after position: InstantOutboxDeliveryPosition?,
    excludingMutationIDs: Set<String>,
    limit: Int,
    expectedAttributeRevision: Int64
  ) throws -> [InstantFailedMutationRetryCandidateRow] {
    guard limit > 0 else { return [] }
    let exclusion = automaticFailedMutationRetryExclusion(
      excludingMutationIDs: excludingMutationIDs
    )
    let start = position ?? InstantOutboxDeliveryPosition(
      createdAtMilliseconds: Int64.min,
      mutationID: ""
    )
    var statement: OpaquePointer?
    try prepare(
      """
      SELECT mutation_id, created_at_ms, mutation_revision, delivery_state,
             length(CAST(json AS BLOB))
      FROM instant_outbox INDEXED BY instant_outbox_failed_retry_window_idx
      WHERE \(Self.automaticFailedMutationRetryEligibilitySQL)
        \(Self.automaticFailedMutationRetryAttributeRevisionSQL)
        AND (created_at_ms, mutation_id) > (?, ?)
        \(exclusion.sql)
      ORDER BY created_at_ms, mutation_id
      LIMIT ?
      """,
      statement: &statement
    )
    defer { sqlite3_finalize(statement) }
    try bind(
      [
        .int(expectedAttributeRevision),
        .int(start.createdAtMilliseconds),
        .text(start.mutationID),
      ]
        + exclusion.bindings
        + [.int(Int64(limit))],
      to: statement
    )
    var rows: [InstantFailedMutationRetryCandidateRow] = []
    rows.reserveCapacity(limit)
    while true {
      let code = sqlite3_step(statement)
      if code == SQLITE_DONE {
        failedMutationRetryMetrics.totalCandidateRowCount += rows.count
        failedMutationRetryMetrics.maximumCandidateRowCount = max(
          failedMutationRetryMetrics.maximumCandidateRowCount,
          rows.count
        )
        failedMutationRetryMetrics.candidateSortCount += Int(
          sqlite3_stmt_status(statement, SQLITE_STMTSTATUS_SORT, 0)
        )
        failedMutationRetryMetrics.candidateFullScanStepCount += Int(
          sqlite3_stmt_status(statement, SQLITE_STMTSTATUS_FULLSCAN_STEP, 0)
        )
        return rows
      }
      guard code == SQLITE_ROW,
        let mutationIDBytes = sqlite3_column_text(statement, 0),
        sqlite3_column_type(statement, 4) != SQLITE_NULL
      else {
        throw persistenceError(
          operation: "read automatic failed-mutation retry candidates",
          message: lastErrorMessage()
        )
      }
      let mutationID = String(cString: mutationIDBytes)
      rows.append(
        InstantFailedMutationRetryCandidateRow(
          mutationID: mutationID,
          position: InstantOutboxDeliveryPosition(
            createdAtMilliseconds: sqlite3_column_int64(statement, 1),
            mutationID: mutationID
          ),
          mutationRevision: sqlite3_column_int64(statement, 2),
          deliveryState: sqlite3_column_text(statement, 3).map(String.init(cString:)),
          actualBodyByteCount: Int(sqlite3_column_int64(statement, 4))
        )
      )
    }
  }

  private func hasAutomaticFailedMutationRetryCandidateWithoutTransaction(
    after position: InstantOutboxDeliveryPosition,
    excludingMutationIDs: Set<String>,
    expectedAttributeRevision: Int64
  ) throws -> Bool {
    let exclusion = automaticFailedMutationRetryExclusion(
      excludingMutationIDs: excludingMutationIDs
    )
    return try selectInt64(
      """
      SELECT EXISTS(
        SELECT 1
        FROM instant_outbox INDEXED BY instant_outbox_failed_retry_window_idx
        WHERE \(Self.automaticFailedMutationRetryEligibilitySQL)
          \(Self.automaticFailedMutationRetryAttributeRevisionSQL)
          AND (created_at_ms, mutation_id) > (?, ?)
          \(exclusion.sql)
        LIMIT 1
      )
      """,
      [
        .int(expectedAttributeRevision),
        .int(position.createdAtMilliseconds),
        .text(position.mutationID),
      ] + exclusion.bindings
    ) != 0
  }

  private func automaticFailedMutationRetryExclusion(
    excludingMutationIDs: Set<String>
  ) -> (sql: String, bindings: [SQLiteBinding]) {
    let mutationIDs = excludingMutationIDs.sorted()
    guard !mutationIDs.isEmpty else { return ("", []) }
    return (
      "AND mutation_id NOT IN ("
        + Array(repeating: "?", count: mutationIDs.count).joined(separator: ", ")
        + ")",
      mutationIDs.map(SQLiteBinding.text)
    )
  }

  private func automaticFailedMutationRetryCandidateStillMatchesWithoutTransaction(
    _ candidate: InstantFailedMutationRetryCandidateRow,
    originalJSON: String?,
    expectedAttributeRevision: Int64
  ) throws -> Bool {
    let jsonProofSQL = originalJSON == nil ? "" : "AND json = ?"
    let deliveryStateBinding = candidate.deliveryState.map(SQLiteBinding.text) ?? .null
    var bindings: [SQLiteBinding] = [
      .text(candidate.mutationID),
      .int(candidate.position.createdAtMilliseconds),
      .int(candidate.mutationRevision),
      deliveryStateBinding,
      .int(Int64(candidate.actualBodyByteCount)),
      .int(expectedAttributeRevision),
    ]
    if let originalJSON {
      bindings.append(.text(originalJSON))
    }
    return try selectInt64(
      """
      SELECT EXISTS(
        SELECT 1 FROM instant_outbox
        WHERE mutation_id = ? AND created_at_ms = ? AND mutation_revision = ?
          AND delivery_state IS ?
          AND length(CAST(json AS BLOB)) = ?
          AND \(Self.automaticFailedMutationRetryEligibilitySQL)
          \(Self.automaticFailedMutationRetryAttributeRevisionSQL)
          \(jsonProofSQL)
        LIMIT 1
      )
      """,
      bindings
    ) != 0
  }

  private func retryFailedMutationWithoutTransaction(
    _ mutation: PendingMutation,
    candidate: InstantFailedMutationRetryCandidateRow,
    originalJSON: String,
    expectedAttributeRevision: Int64
  ) throws {
    guard let receiptFingerprint = try mutation.optimisticEffectReceiptFingerprint() else {
      throw persistenceError(
        operation: "retry automatic failed-mutation window",
        message:
          "The failed mutation '\(mutation.id)' has no canonical prepared optimistic-effect receipt."
      )
    }
    let encodedBody = try encode(mutation)
    try execute(
      """
      UPDATE instant_outbox
      SET status = ?, delivery_state = ?, delivery_metadata_version = ?,
          transport_step_count = ?, encoded_body_bytes = ?, lifecycle_json = ?,
          failure_message = NULL, confirmation_proven = 0,
          failure_attribute_revision = NULL,
          server_transaction_id = NULL, confirmation_source = NULL,
          server_acceptance_payload_fingerprint = NULL,
          optimistic_overlay_active = 1, mutation_revision = mutation_revision + 1,
          delivery_claim_state = ?, delivery_claim_token = NULL,
          delivery_claimant_id = NULL, delivery_claim_deadline_ms = NULL,
          delivery_claim_projected_body_bytes = NULL,
          delivery_claim_payload_fingerprint = NULL,
          json = ?
      WHERE mutation_id = ? AND created_at_ms = ? AND mutation_revision = ?
        AND delivery_state IS ? AND length(CAST(json AS BLOB)) = ?
        AND optimistic_effect_receipt_fingerprint = ?
        AND \(Self.automaticFailedMutationRetryEligibilitySQL)
        \(Self.automaticFailedMutationRetryAttributeRevisionSQL)
        AND json = ?
      """,
      [
        .text(InstantMutationStatus.pending.rawValue),
        .text(InstantOutboxDeliveryState.needsDelivery.rawValue),
        .int(Int64(InstantOutboxDeliveryMetadata.currentVersion)),
        .int(Int64(InstantOutboxDeliveryMetadata.stepCount(in: mutation))),
        .int(Int64(encodedBody.utf8.count)),
        .text(try encode(mutation.compactedForMemory)),
        .text(InstantOutboxDeliveryClaimState.ready.rawValue),
        .text(encodedBody),
        .text(candidate.mutationID),
        .int(candidate.position.createdAtMilliseconds),
        .int(candidate.mutationRevision),
        candidate.deliveryState.map(SQLiteBinding.text) ?? .null,
        .int(Int64(candidate.actualBodyByteCount)),
        .text(receiptFingerprint),
        .int(expectedAttributeRevision),
        .text(originalJSON),
      ]
    )
    guard sqlite3_changes(connection.raw) == 1 else {
      throw persistenceError(
        operation: "retry automatic failed-mutation window",
        message: "The exact failed mutation '\(candidate.mutationID)' changed during its retry."
      )
    }
    try saveMutationLifecycleWithoutTransaction(mutation)
  }

  private func isolateAutomaticFailedMutationRetryWithoutTransaction(
    _ mutation: PendingMutation,
    candidate: InstantFailedMutationRetryCandidateRow,
    originalJSON: String,
    reason: String,
    expectedAttributeRevision: Int64
  ) throws {
    let encodedBody = try encode(mutation)
    try execute(
      """
      UPDATE instant_outbox
      SET status = ?, delivery_state = ?, delivery_metadata_version = ?,
          transport_step_count = ?, encoded_body_bytes = ?, lifecycle_json = ?,
          failure_message = ?, confirmation_proven = 0,
          failure_attribute_revision = NULL,
          server_transaction_id = NULL, confirmation_source = NULL,
          server_acceptance_payload_fingerprint = NULL,
          optimistic_overlay_active = 1, mutation_revision = mutation_revision + 1,
          delivery_claim_state = ?, delivery_claim_token = NULL,
          delivery_claimant_id = NULL, delivery_claim_deadline_ms = NULL,
          delivery_claim_projected_body_bytes = NULL,
          delivery_claim_payload_fingerprint = NULL,
          json = ?
      WHERE mutation_id = ? AND created_at_ms = ? AND mutation_revision = ?
        AND delivery_state IS ? AND length(CAST(json AS BLOB)) = ?
        AND \(Self.automaticFailedMutationRetryEligibilitySQL)
        \(Self.automaticFailedMutationRetryAttributeRevisionSQL)
        AND json = ?
      """,
      [
        .text(InstantMutationStatus.failed.rawValue),
        .text(InstantOutboxDeliveryState.invalid.rawValue),
        .int(Int64(InstantOutboxDeliveryMetadata.currentVersion)),
        .int(Int64(InstantOutboxDeliveryMetadata.stepCount(in: mutation))),
        .int(Int64(encodedBody.utf8.count)),
        .text(try encode(mutation.compactedForMemory)),
        mutation.failureMessage.map(SQLiteBinding.text) ?? .null,
        .text(InstantOutboxDeliveryClaimState.ready.rawValue),
        .text(encodedBody),
        .text(candidate.mutationID),
        .int(candidate.position.createdAtMilliseconds),
        .int(candidate.mutationRevision),
        candidate.deliveryState.map(SQLiteBinding.text) ?? .null,
        .int(Int64(candidate.actualBodyByteCount)),
        .int(expectedAttributeRevision),
        .text(originalJSON),
      ]
    )
    guard sqlite3_changes(connection.raw) == 1 else {
      throw persistenceError(
        operation: "isolate automatic failed-mutation retry",
        message: "The exact failed mutation '\(candidate.mutationID)' changed during isolation."
      )
    }
    try resetOptimisticEffectMetadataForUnknownMutationWithoutTransaction(
      id: mutation.id
    )
    try saveMutationLifecycleWithoutTransaction(mutation)
    InstantDiagnostics.shared.record(
      .error,
      subsystem: "instant-swift-data-core",
      category: "outbox",
      event: "outbox.failed-mutation-retry.isolated",
      message: mutation.failureMessage ?? reason,
      metadata: ["mutationID": mutation.id],
      correlationID: mutation.id
    )
    reportIssue(
      """
      \(mutation.failureMessage ?? reason)

      The row remains durable and failed, but it no longer blocks later automatic retries. \(reason) Use an authoritative refresh before choosing a manual retry or discard.
      """
    )
  }

  private func advanceQuarantinedMutationRevisionWithoutTransaction(
    _ candidate: InstantFailedMutationRetryCandidateRow
  ) throws {
    try execute(
      """
      UPDATE instant_outbox
      SET mutation_revision = mutation_revision + 1
      WHERE mutation_id = ? AND mutation_revision = ?
      """,
      [.text(candidate.mutationID), .int(candidate.mutationRevision)]
    )
    guard sqlite3_changes(connection.raw) == 1 else {
      throw persistenceError(
        operation: "advance quarantined failed-mutation revision",
        message: "The quarantined mutation '\(candidate.mutationID)' changed unexpectedly."
      )
    }
  }

  private func firstFailedMutationShellWithoutTransaction() throws -> PendingMutation? {
    var statement: OpaquePointer?
    try prepare(
      """
      SELECT mutation_id, created_at_ms, failure_message, lifecycle_json,
             CASE WHEN lifecycle_json IS NULL
               THEN NULL ELSE length(CAST(lifecycle_json AS BLOB)) END,
             delivery_metadata_version,
             optimistic_effect_receipt_fingerprint
      FROM instant_outbox
      WHERE status = ?
      ORDER BY created_at_ms, mutation_id
      LIMIT 1
      """,
      statement: &statement
    )
    defer { sqlite3_finalize(statement) }
    try bind([.text(InstantMutationStatus.failed.rawValue)], to: statement)
    let code = sqlite3_step(statement)
    if code == SQLITE_DONE { return nil }
    guard code == SQLITE_ROW, let mutationIDBytes = sqlite3_column_text(statement, 0) else {
      throw persistenceError(
        operation: "read failed mutation summary",
        message: lastErrorMessage()
      )
    }
    let mutationID = String(cString: mutationIDBytes)
    let failureMessage = sqlite3_column_text(statement, 2).map(String.init(cString:))
      ?? "The Instant server rejected the mutation."
    let lifecycleByteCount = sqlite3_column_type(statement, 4) == SQLITE_NULL
      ? nil
      : Int(sqlite3_column_int64(statement, 4))
    if sqlite3_column_int64(statement, 5)
      == Int64(InstantOutboxDeliveryMetadata.currentVersion),
      let lifecycleByteCount,
      lifecycleByteCount <= InstantAutomaticOutboxClaimLimits.maximumEncodedBodyBytes,
      let lifecycleBytes = sqlite3_column_text(statement, 3),
      let lifecycle: PendingMutation = try? decodeOutboxBody(
        String(cString: lifecycleBytes)
      ),
      lifecycle.id == mutationID,
      lifecycle.status == .failed
    {
      return compactedLifecycleForInspection(
        lifecycle,
        hasStoredReceiptFingerprint: sqlite3_column_type(statement, 6) != SQLITE_NULL
      )
    }

    // Missing, oversized, invalid, or legacy lifecycle metadata cannot prove
    // whether the failed row still has a local effect. Return a bounded shell
    // with no fabricated optimistic-overlay receipt.
    var mutation = PendingMutation(
      id: mutationID,
      createdAt: InstantTimestamp(milliseconds: sqlite3_column_int64(statement, 1)),
      transaction: InstantStoreTransaction(id: mutationID, operations: []),
      status: .failed,
      failureMessage: failureMessage
    )
    mutation.failure = InstantMutationFailure(
      code: PendingMutation.failureCode(message: failureMessage),
      message: failureMessage
    )
    return mutation
  }

  private func loadOutboxDeliveryCandidateRowsWithoutTransaction(
    _ sql: String,
    _ bindings: [SQLiteBinding]
  ) throws -> [InstantOutboxDeliveryCandidateRow] {
    var statement: OpaquePointer?
    try prepare(sql, statement: &statement)
    defer { sqlite3_finalize(statement) }
    try bind(bindings, to: statement)

    var rows: [InstantOutboxDeliveryCandidateRow] = []
    while true {
      let code = sqlite3_step(statement)
      if code == SQLITE_DONE { return rows }
      guard code == SQLITE_ROW else {
        throw persistenceError(
          operation: "read outbox delivery candidates",
          message: lastErrorMessage()
        )
      }
      guard let mutationID = sqlite3_column_text(statement, 0),
        let statusBytes = sqlite3_column_text(statement, 5),
        let status = InstantMutationStatus(rawValue: String(cString: statusBytes))
      else {
        throw persistenceError(
          operation: "read outbox delivery candidates",
          message: "SQLite returned an invalid bounded-delivery mutation id or status."
        )
      }
      rows.append(
        InstantOutboxDeliveryCandidateRow(
          mutationID: String(cString: mutationID),
          createdAtMilliseconds: sqlite3_column_int64(statement, 1),
          metadataVersion: Int(sqlite3_column_int64(statement, 2)),
          transportStepCount: sqlite3_column_type(statement, 3) == SQLITE_NULL
            ? nil
            : Int(sqlite3_column_int64(statement, 3)),
          encodedBodyByteCount: Int(sqlite3_column_int64(statement, 4)),
          status: status,
          deliveryStarted: sqlite3_column_int64(statement, 6) != 0
        )
      )
    }
  }

  private func loadOutboxBodyRowWithoutTransaction(
    id: String
  ) throws -> InstantOutboxBodyRow? {
    try loadOutboxBodyRowsWithoutTransaction(
      """
      SELECT mutation_id, created_at_ms, json,
             optimistic_effect_receipt_fingerprint,
             delivery_claim_payload_fingerprint,
             server_acceptance_payload_fingerprint
      FROM instant_outbox
      WHERE mutation_id = ?
      LIMIT 1
      """,
      [.text(id)]
    ).first
  }

  private func loadOutboxPositionWithoutTransaction(
    id: String
  ) throws -> InstantOutboxDeliveryPosition? {
    var statement: OpaquePointer?
    try prepare(
      """
      SELECT created_at_ms, mutation_id
      FROM instant_outbox
      WHERE mutation_id = ?
      LIMIT 1
      """,
      statement: &statement
    )
    defer { sqlite3_finalize(statement) }
    try bind([.text(id)], to: statement)
    guard sqlite3_step(statement) == SQLITE_ROW,
      let mutationID = sqlite3_column_text(statement, 1)
    else { return nil }
    return InstantOutboxDeliveryPosition(
      createdAtMilliseconds: sqlite3_column_int64(statement, 0),
      mutationID: String(cString: mutationID)
    )
  }

  private func latestOutboxPositionWithoutTransaction()
    throws -> InstantOutboxDeliveryPosition?
  {
    var statement: OpaquePointer?
    try prepare(
      """
      SELECT created_at_ms, mutation_id
      FROM instant_outbox
      ORDER BY created_at_ms DESC, mutation_id DESC
      LIMIT 1
      """,
      statement: &statement
    )
    defer { sqlite3_finalize(statement) }
    guard sqlite3_step(statement) == SQLITE_ROW,
      let mutationID = sqlite3_column_text(statement, 1)
    else { return nil }
    return InstantOutboxDeliveryPosition(
      createdAtMilliseconds: sqlite3_column_int64(statement, 0),
      mutationID: String(cString: mutationID)
    )
  }

  private func loadTerminalFailureTargetControlWithoutTransaction(
    id: String
  ) throws -> InstantTerminalFailureTargetControl? {
    var statement: OpaquePointer?
    try prepare(
      """
      SELECT mutation_id, created_at_ms, mutation_revision,
             optimistic_effect_metadata_version, optimistic_effect_is_global,
             MAX(
               COALESCE(encoded_body_bytes, 0),
               length(CAST(json AS BLOB))
             ),
             status, confirmation_proven, delivery_state,
             delivery_claim_state, delivery_claim_token
      FROM instant_outbox
      WHERE mutation_id = ?
      LIMIT 1
      """,
      statement: &statement
    )
    defer { sqlite3_finalize(statement) }
    try bind([.text(id)], to: statement)
    guard sqlite3_step(statement) == SQLITE_ROW,
      let mutationIDBytes = sqlite3_column_text(statement, 0),
      let statusBytes = sqlite3_column_text(statement, 6),
      let deliveryStateBytes = sqlite3_column_text(statement, 8),
      let claimStateBytes = sqlite3_column_text(statement, 9),
      let status = InstantMutationStatus(rawValue: String(cString: statusBytes)),
      let deliveryState = InstantOutboxDeliveryState(
        rawValue: String(cString: deliveryStateBytes)
      ),
      let claimState = InstantOutboxDeliveryClaimState(
        rawValue: String(cString: claimStateBytes)
      )
    else {
      if sqlite3_errcode(connection.raw) == SQLITE_OK
        || sqlite3_errcode(connection.raw) == SQLITE_DONE
      {
        return nil
      }
      throw persistenceError(
        operation: "read terminal failure target",
        message: lastErrorMessage()
      )
    }
    let mutationID = String(cString: mutationIDBytes)
    terminalFailureMetadataMetrics.outboxRowCount += 1
    return InstantTerminalFailureTargetControl(
      effect: InstantOptimisticEffectRow(
        mutationID: mutationID,
        position: InstantOutboxDeliveryPosition(
          createdAtMilliseconds: sqlite3_column_int64(statement, 1),
          mutationID: mutationID
        ),
        mutationRevision: sqlite3_column_int64(statement, 2),
        metadataVersion: Int(sqlite3_column_int64(statement, 3)),
        isGlobal: sqlite3_column_int64(statement, 4) != 0,
        encodedBodyByteCount: Int(sqlite3_column_int64(statement, 5))
      ),
      status: status,
      confirmationProven: sqlite3_column_int64(statement, 7) != 0,
      deliveryState: deliveryState,
      claimState: claimState,
      claimToken: sqlite3_column_text(statement, 10).map(String.init(cString:))
    )
  }

  private func resolveOptimisticEffectComponentRowsWithoutTransaction(
    target: InstantOptimisticEffectRow
  ) throws -> InstantOptimisticEffectComponentRowsResolution {
    guard target.metadataVersion == InstantOptimisticEffectFootprint.currentVersion,
      try storedOptimisticEffectReceiptFingerprintWithoutTransaction(id: target.mutationID) != nil
    else {
      return .normalizationRequired(mutationID: target.mutationID)
    }
    if let unknown = try loadFirstUnknownActiveOptimisticEffectRowWithoutTransaction(
      after: target.position
    ) {
      return .normalizationRequired(mutationID: unknown.mutationID)
    }

    let maximumRowCount = InstantAutomaticOutboxClaimLimits.maximumBodyDecodeCount + 1
    let hasGlobalSuccessor: Bool
    if target.isGlobal {
      hasGlobalSuccessor = false
    } else {
      hasGlobalSuccessor = try loadFirstActiveGlobalOptimisticEffectRowWithoutTransaction(
        after: target.position
      ) != nil
    }
    if target.isGlobal || hasGlobalSuccessor {
      let successors = try loadBoundedActiveOptimisticEffectRowsWithoutTransaction(
        after: target.position,
        limit: maximumRowCount - 1
      )
      return .ready(
        InstantOptimisticEffectComponentRows(
          target: target,
          successors: successors
        )
      )
    }

    var rowsByMutationID = [target.mutationID: target]
    var encodedBodyByteCount = target.encodedBodyByteCount
    if encodedBodyByteCount > InstantAutomaticOutboxClaimLimits.maximumEncodedBodyBytes {
      return .ready(
        InstantOptimisticEffectComponentRows(target: target, successors: [])
      )
    }
    var visitedEntityIDs: Set<String> = []
    var pendingEntityIDs = Array(
      try loadOptimisticEffectEntityIDsWithoutTransaction(
        mutationID: target.mutationID
      )
    )
    while let entityID = pendingEntityIDs.popLast() {
      guard visitedEntityIDs.insert(entityID).inserted else { continue }
      let remainingRowCount = maximumRowCount - rowsByMutationID.count
      guard remainingRowCount > 0 else { break }
      let candidates = try loadBoundedActiveOptimisticEffectRowsWithoutTransaction(
        affectingEntityID: entityID,
        after: target.position,
        excludingMutationIDs: Set(rowsByMutationID.keys),
        limit: remainingRowCount
      )
      for candidate in candidates {
        guard rowsByMutationID[candidate.mutationID] == nil else { continue }
        rowsByMutationID[candidate.mutationID] = candidate

        let exceedsByteLimit = candidate.encodedBodyByteCount
          > InstantAutomaticOutboxClaimLimits.maximumEncodedBodyBytes
            - encodedBodyByteCount
        if rowsByMutationID.count >= maximumRowCount || exceedsByteLimit {
          let successors = rowsByMutationID.values
            .filter { $0.mutationID != target.mutationID }
            .sorted(by: optimisticEffectRowPrecedes)
          return .ready(
            InstantOptimisticEffectComponentRows(
              target: target,
              successors: successors
            )
          )
        }
        encodedBodyByteCount += candidate.encodedBodyByteCount
        pendingEntityIDs.append(
          contentsOf: try loadOptimisticEffectEntityIDsWithoutTransaction(
            mutationID: candidate.mutationID
          )
        )
      }
    }
    let successors = rowsByMutationID.values
      .filter { $0.mutationID != target.mutationID }
      .sorted(by: optimisticEffectRowPrecedes)
    return .ready(
      InstantOptimisticEffectComponentRows(
        target: target,
        successors: successors
      )
    )
  }

  private func loadBoundedActiveOptimisticEffectRowsWithoutTransaction(
    after position: InstantOutboxDeliveryPosition,
    limit: Int
  ) throws -> [InstantOptimisticEffectRow] {
    guard limit > 0 else { return [] }
    return try loadOptimisticEffectRowsWithoutTransaction(
      """
      SELECT mutation_id, created_at_ms, mutation_revision,
             optimistic_effect_metadata_version, optimistic_effect_is_global,
             MAX(
               COALESCE(encoded_body_bytes, 0),
               length(CAST(json AS BLOB))
             )
      FROM instant_outbox
      WHERE (
        created_at_ms > ? OR (created_at_ms = ? AND mutation_id > ?)
      )
      AND optimistic_overlay_active != 0
      AND confirmation_proven = 0
      ORDER BY created_at_ms, mutation_id
      LIMIT ?
      """,
      [
        .int(position.createdAtMilliseconds),
        .int(position.createdAtMilliseconds),
        .text(position.mutationID),
        .int(Int64(limit)),
      ]
    )
  }

  private func loadBoundedActiveOptimisticEffectRowsWithoutTransaction(
    affectingEntityID entityID: String,
    after position: InstantOutboxDeliveryPosition,
    excludingMutationIDs: Set<String>,
    limit: Int
  ) throws -> [InstantOptimisticEffectRow] {
    guard limit > 0 else { return [] }
    let excludedMutationIDs = excludingMutationIDs.sorted()
    let exclusionSQL = excludedMutationIDs.isEmpty
      ? ""
      : "AND effects.mutation_id NOT IN ("
        + Array(repeating: "?", count: excludedMutationIDs.count).joined(separator: ", ")
        + ")"
    return try loadOptimisticEffectRowsWithoutTransaction(
      """
      SELECT outbox.mutation_id, effects.created_at_ms, outbox.mutation_revision,
             outbox.optimistic_effect_metadata_version,
             outbox.optimistic_effect_is_global,
             MAX(
               COALESCE(outbox.encoded_body_bytes, 0),
               length(CAST(outbox.json AS BLOB))
             )
      FROM instant_outbox_effect_entities AS effects
        INDEXED BY instant_outbox_effect_entities_lookup_idx
      JOIN instant_outbox AS outbox
        ON outbox.mutation_id = effects.mutation_id
      WHERE effects.entity_id = ?
        AND (effects.created_at_ms, effects.mutation_id) > (?, ?)
        AND outbox.optimistic_overlay_active != 0
        AND COALESCE(outbox.confirmation_proven, 0) = 0
        \(exclusionSQL)
      ORDER BY effects.created_at_ms, effects.mutation_id
      LIMIT ?
      """,
      [
        .text(entityID),
        .int(position.createdAtMilliseconds),
        .text(position.mutationID),
      ]
        + excludedMutationIDs.map(SQLiteBinding.text)
        + [.int(Int64(limit))],
      recordsEntityFrontierMetrics: true
    )
  }

  private func loadFirstActiveGlobalOptimisticEffectRowWithoutTransaction(
    after position: InstantOutboxDeliveryPosition
  ) throws -> InstantOptimisticEffectRow? {
    try loadOptimisticEffectRowsWithoutTransaction(
      """
      SELECT mutation_id, created_at_ms, mutation_revision,
             optimistic_effect_metadata_version, optimistic_effect_is_global,
             MAX(
               COALESCE(encoded_body_bytes, 0),
               length(CAST(json AS BLOB))
             )
      FROM instant_outbox INDEXED BY instant_outbox_global_effect_order_idx
      WHERE optimistic_overlay_active = 1
        AND optimistic_effect_is_global = 1
        AND confirmation_proven = 0
        AND (
          created_at_ms > ? OR (created_at_ms = ? AND mutation_id > ?)
        )
      ORDER BY created_at_ms, mutation_id
      LIMIT 1
      """,
      [
        .int(position.createdAtMilliseconds),
        .int(position.createdAtMilliseconds),
        .text(position.mutationID),
      ]
    ).first
  }

  private func loadFirstUnknownActiveOptimisticEffectRowWithoutTransaction(
    after position: InstantOutboxDeliveryPosition
  ) throws -> InstantOptimisticEffectRow? {
    let currentVersion = InstantOptimisticEffectFootprint.currentVersion
    return try loadOptimisticEffectRowsWithoutTransaction(
      """
      SELECT mutation_id, created_at_ms, mutation_revision,
             optimistic_effect_metadata_version, optimistic_effect_is_global,
             MAX(
               COALESCE(encoded_body_bytes, 0),
               length(CAST(json AS BLOB))
             )
      FROM instant_outbox INDEXED BY instant_outbox_effect_normalization_idx
      WHERE optimistic_overlay_active = 1
        AND (
          optimistic_effect_metadata_version != ?
          OR optimistic_effect_receipt_fingerprint IS NULL
        )
        AND confirmation_proven = 0
        AND (
          created_at_ms > ? OR (created_at_ms = ? AND mutation_id > ?)
        )
      ORDER BY created_at_ms, mutation_id
      LIMIT 1
      """,
      [
        .int(Int64(currentVersion)),
        .int(position.createdAtMilliseconds),
        .int(position.createdAtMilliseconds),
        .text(position.mutationID),
      ]
    ).first
  }

  private func optimisticEffectRowPrecedes(
    _ lhs: InstantOptimisticEffectRow,
    _ rhs: InstantOptimisticEffectRow
  ) -> Bool {
    if lhs.position.createdAtMilliseconds != rhs.position.createdAtMilliseconds {
      return lhs.position.createdAtMilliseconds < rhs.position.createdAtMilliseconds
    }
    return lhs.mutationID < rhs.mutationID
  }

  private func loadUnknownOptimisticEffectRowsWithoutTransaction(
    atOrAfter position: InstantOutboxDeliveryPosition,
    limit: Int
  ) throws -> [InstantOptimisticEffectRow] {
    try loadOptimisticEffectRowsWithoutTransaction(
      """
      SELECT mutation_id, created_at_ms, mutation_revision,
             optimistic_effect_metadata_version, optimistic_effect_is_global,
             MAX(
               COALESCE(encoded_body_bytes, 0),
               length(CAST(json AS BLOB))
             )
      FROM instant_outbox
      WHERE (
        created_at_ms > ? OR (created_at_ms = ? AND mutation_id >= ?)
      )
      AND (
        mutation_id = ?
        OR (optimistic_overlay_active != 0 AND confirmation_proven = 0)
      )
      AND (
        optimistic_effect_metadata_version != ?
        OR optimistic_effect_receipt_fingerprint IS NULL
      )
      ORDER BY created_at_ms, mutation_id
      LIMIT ?
      """,
      [
        .int(position.createdAtMilliseconds),
        .int(position.createdAtMilliseconds),
        .text(position.mutationID),
        .text(position.mutationID),
        .int(Int64(InstantOptimisticEffectFootprint.currentVersion)),
        .int(Int64(limit)),
      ]
    )
  }

  private func loadOptimisticEffectRowsWithoutTransaction(
    _ sql: String,
    _ bindings: [SQLiteBinding],
    recordsEntityFrontierMetrics: Bool = false
  ) throws -> [InstantOptimisticEffectRow] {
    var statement: OpaquePointer?
    try prepare(sql, statement: &statement)
    defer { sqlite3_finalize(statement) }
    try bind(bindings, to: statement)
    var rows: [InstantOptimisticEffectRow] = []
    while true {
      let code = sqlite3_step(statement)
      if code == SQLITE_DONE {
        if recordsEntityFrontierMetrics {
          terminalFailureMetadataMetrics.maximumEntityFrontierRowCount = max(
            terminalFailureMetadataMetrics.maximumEntityFrontierRowCount,
            rows.count
          )
          terminalFailureMetadataMetrics.entityFrontierSortCount += Int(
            sqlite3_stmt_status(statement, SQLITE_STMTSTATUS_SORT, 0)
          )
          terminalFailureMetadataMetrics.entityFrontierFullScanStepCount += Int(
            sqlite3_stmt_status(statement, SQLITE_STMTSTATUS_FULLSCAN_STEP, 0)
          )
        }
        return rows
      }
      guard code == SQLITE_ROW,
        let mutationIDBytes = sqlite3_column_text(statement, 0)
      else {
        throw persistenceError(
          operation: "read optimistic effect metadata",
          message: lastErrorMessage()
        )
      }
      let mutationID = String(cString: mutationIDBytes)
      terminalFailureMetadataMetrics.outboxRowCount += 1
      rows.append(
        InstantOptimisticEffectRow(
          mutationID: mutationID,
          position: InstantOutboxDeliveryPosition(
            createdAtMilliseconds: sqlite3_column_int64(statement, 1),
            mutationID: mutationID
          ),
          mutationRevision: sqlite3_column_int64(statement, 2),
          metadataVersion: Int(sqlite3_column_int64(statement, 3)),
          isGlobal: sqlite3_column_int64(statement, 4) != 0,
          encodedBodyByteCount: Int(sqlite3_column_int64(statement, 5))
        )
      )
    }
  }

  private func loadOptimisticEffectEntityIDsWithoutTransaction(
    mutationID: String
  ) throws -> Set<String> {
    var statement: OpaquePointer?
    try prepare(
      """
      SELECT entity_id
      FROM instant_outbox_effect_entities
      WHERE mutation_id = ?
      ORDER BY entity_id
      """,
      statement: &statement
    )
    defer { sqlite3_finalize(statement) }
    try bind([.text(mutationID)], to: statement)
    var entityIDs: Set<String> = []
    while true {
      let code = sqlite3_step(statement)
      if code == SQLITE_DONE { return entityIDs }
      guard code == SQLITE_ROW,
        let entityIDBytes = sqlite3_column_text(statement, 0)
      else {
        throw persistenceError(
          operation: "read optimistic effect entities",
          message: lastErrorMessage()
        )
      }
      terminalFailureMetadataMetrics.effectEntityRowCount += 1
      entityIDs.insert(String(cString: entityIDBytes))
    }
  }

  private func automaticDeliveryStepCountFits(
    _ stepCount: Int,
    admittedStepCount: Int,
    remainingStepCount: Int
  ) -> Bool {
    guard stepCount >= 0 else { return false }
    return
      admittedStepCount <= remainingStepCount
      && stepCount <= remainingStepCount - admittedStepCount
  }

  private func claimOutboxMutationWithoutTransaction(
    id: String,
    claimantID: String,
    claimToken: String,
    deadlineMilliseconds: Int64,
    projectedBodyByteCount: Int,
    payloadFingerprint: String
  ) throws {
    precondition(projectedBodyByteCount >= 0)
    try execute(
      """
      UPDATE instant_outbox
      SET delivery_started = 1, delivery_claim_state = ?, delivery_claim_token = ?,
          delivery_claimant_id = ?, delivery_claim_deadline_ms = ?,
          delivery_claim_projected_body_bytes = ?,
          delivery_claim_payload_fingerprint = ?
      WHERE mutation_id = ? AND delivery_claim_state = ?
      """,
      [
        .text(InstantOutboxDeliveryClaimState.claimed.rawValue),
        .text(claimToken),
        .text(claimantID),
        .int(deadlineMilliseconds),
        .int(Int64(projectedBodyByteCount)),
        .text(payloadFingerprint),
        .text(id),
        .text(InstantOutboxDeliveryClaimState.ready.rawValue),
      ]
    )
    guard sqlite3_changes(connection.raw) == 1 else {
      throw persistenceError(
        operation: "claim automatic outbox mutation",
        message: "SQLite did not claim ready mutation '\(id)' exactly once."
      )
    }
  }

  private func updateProjectedOutboxClaimByteCountWithoutTransaction(
    id: String,
    claimToken: String,
    projectedBodyByteCount: Int,
    payloadFingerprint: String
  ) throws {
    precondition(projectedBodyByteCount >= 0)
    try execute(
      """
      UPDATE instant_outbox
      SET delivery_claim_projected_body_bytes = ?,
          delivery_claim_payload_fingerprint = ?
      WHERE mutation_id = ? AND delivery_claim_state = ?
        AND delivery_claim_token = ?
      """,
      [
        .int(Int64(projectedBodyByteCount)),
        .text(payloadFingerprint),
        .text(id),
        .text(InstantOutboxDeliveryClaimState.claimed.rawValue),
        .text(claimToken),
      ]
    )
    guard sqlite3_changes(connection.raw) == 1 else {
      throw persistenceError(
        operation: "reserve projected outbox claim bytes",
        message: "The exact durable claim changed before projected-byte admission."
      )
    }
  }

  private func releaseUnofferedOutboxClaimWithoutTransaction(
    id: String,
    claimToken: String,
    deliveryStarted: Bool
  ) throws {
    try execute(
      """
      UPDATE instant_outbox
      SET delivery_started = ?, delivery_claim_state = ?,
          delivery_claim_token = NULL, delivery_claimant_id = NULL,
          delivery_claim_deadline_ms = NULL,
          delivery_claim_projected_body_bytes = NULL,
          delivery_claim_payload_fingerprint = NULL
      WHERE mutation_id = ? AND delivery_claim_state = ?
        AND delivery_claim_token = ?
      """,
      [
        .int(deliveryStarted ? 1 : 0),
        .text(InstantOutboxDeliveryClaimState.ready.rawValue),
        .text(id),
        .text(InstantOutboxDeliveryClaimState.claimed.rawValue),
        .text(claimToken),
      ]
    )
    guard sqlite3_changes(connection.raw) == 1 else {
      throw persistenceError(
        operation: "defer projected outbox mutation",
        message: "The exact durable claim changed before projected-window deferral."
      )
    }
  }

  private func reclaimExpiredOutboxClaimsWithoutTransaction(
    nowMilliseconds: Int64
  ) throws -> Set<String> {
    let ids = Set(try selectStrings(
      """
      SELECT mutation_id FROM instant_outbox
      WHERE delivery_claim_state = ? AND delivery_claim_deadline_ms <= ?
      ORDER BY created_at_ms, mutation_id
      LIMIT ?
      """,
      [
        .text(InstantOutboxDeliveryClaimState.claimed.rawValue),
        .int(nowMilliseconds),
        .int(Int64(InstantAutomaticOutboxClaimLimits.maximumMutationCount)),
      ]
    ))
    guard !ids.isEmpty else { return [] }
    try execute(
      """
      UPDATE instant_outbox
      SET delivery_claim_state = ?, delivery_claim_token = NULL,
          delivery_claimant_id = NULL, delivery_claim_deadline_ms = NULL,
          delivery_claim_projected_body_bytes = NULL,
          delivery_claim_payload_fingerprint = NULL
      WHERE delivery_claim_state = ? AND delivery_claim_deadline_ms <= ?
      """,
      [
        .text(InstantOutboxDeliveryClaimState.ready.rawValue),
        .text(InstantOutboxDeliveryClaimState.claimed.rawValue),
        .int(nowMilliseconds),
      ]
    )
    return ids
  }

  private func hasActiveOutboxClaimWithoutTransaction(
    excludingClaimantID claimantID: String
  ) throws -> Bool {
    try selectInt64(
      """
      SELECT EXISTS(
        SELECT 1 FROM instant_outbox
        WHERE delivery_claim_state = ?
          AND (delivery_claimant_id IS NULL OR delivery_claimant_id != ?)
        LIMIT 1
      )
      """,
      [
        .text(InstantOutboxDeliveryClaimState.claimed.rawValue),
        .text(claimantID),
      ]
    ) != 0
  }

  private func minimumOutboxClaimDeadlineWithoutTransaction() throws -> Int64? {
    try selectScalar(
      """
      SELECT CAST(MIN(delivery_claim_deadline_ms) AS TEXT)
      FROM instant_outbox
      WHERE delivery_claim_state = ?
      """,
      [.text(InstantOutboxDeliveryClaimState.claimed.rawValue)]
    ).flatMap(Int64.init)
  }

  private func storedOptimisticEffectReceiptFingerprintWithoutTransaction(
    id: String
  ) throws -> String? {
    try selectScalar(
      """
      SELECT optimistic_effect_receipt_fingerprint
      FROM instant_outbox
      WHERE mutation_id = ?
      LIMIT 1
      """,
      [.text(id)]
    )
  }

  private func hasStoredPreparedOptimisticEffectReceiptWithoutTransaction(
    _ mutation: PendingMutation
  ) throws -> Bool {
    guard let candidate = try mutation.optimisticEffectReceiptFingerprint() else {
      return false
    }
    return try storedOptimisticEffectReceiptFingerprintWithoutTransaction(id: mutation.id)
      == candidate
  }

  private func hasStoredPreparedOptimisticEffectReceipt(
    _ mutation: PendingMutation,
    in row: InstantOutboxBodyRow
  ) throws -> Bool {
    guard row.mutationID == mutation.id,
      let candidate = try mutation.optimisticEffectReceiptFingerprint()
    else { return false }
    return row.optimisticEffectReceiptFingerprint == candidate
  }

  private func hasStoredServerAcceptance(
    _ mutation: PendingMutation,
    in row: InstantOutboxBodyRow
  ) throws -> Bool {
    guard row.serverAcceptancePayloadFingerprint != nil else { return false }
    return try hasStoredPreparedOptimisticEffectReceipt(mutation, in: row)
  }

  private func durableDeliveryState(
    for mutation: PendingMutation,
    hasServerAcceptance: Bool
  ) -> InstantOutboxDeliveryState {
    if hasServerAcceptance {
      return .serverAccepted
    }
    switch mutation.status {
    case .pending:
      return .needsDelivery
    case .failed:
      return .terminal
    case .confirmed:
      // A local-only confirmation remains deliverable. A body that claims a
      // server ACK without the SQLite-owned matching wire digest is ambiguous:
      // never resend it and never let its historical ACK attest edited bytes.
      return mutation.provesServerAcceptance ? .invalid : .needsDelivery
    }
  }

  private func compactedLifecycleForInspection(
    _ mutation: PendingMutation,
    hasStoredReceiptFingerprint: Bool
  ) -> PendingMutation {
    lifecycleMutationForInspection(
      mutation.compactedForMemory,
      hasStoredReceiptFingerprint: hasStoredReceiptFingerprint
    )
  }

  private func lifecycleMutationForInspection(
    _ mutation: PendingMutation,
    hasStoredReceiptFingerprint: Bool
  ) -> PendingMutation {
    var lifecycle = mutation
    if !hasStoredReceiptFingerprint {
      // The compact body cannot recompute the full admission fingerprint because
      // its forward and rollback operations were intentionally removed. Keep the
      // lifecycle bounded, but never report a body-shaped receipt as trusted when
      // SQLite has no Runtime-owned provenance for the full durable body. A
      // caller-authored `.removed` value is equally untrusted: only a matching
      // SQLite tombstone fingerprint proves that no optimistic inverse remains.
      lifecycle.optimisticOverlayState = nil
      lifecycle.optimisticEffectReceiptVersion = nil
      lifecycle.rollbackTransaction = nil
    }
    return lifecycle
  }

  /// Validates caller-visible bodies against SQLite-owned Runtime admission
  /// authority under the same outbox revision used by the eventual CAS write.
  package func validatePreparedOptimisticEffectReceipts(
    _ mutations: [PendingMutation],
    expectedOutboxRevision: Int64
  ) throws -> InstantOptimisticEffectReceiptValidation {
    try readTransaction {
      guard try loadMetadataRevisionWithoutTransaction(Self.outboxRevisionKey)
        == expectedOutboxRevision
      else {
        return InstantOptimisticEffectReceiptValidation(
          matchesOutboxRevision: false,
          firstUntrustedMutationID: nil
        )
      }
      for mutation in mutations {
        guard try hasStoredPreparedOptimisticEffectReceiptWithoutTransaction(mutation) else {
          return InstantOptimisticEffectReceiptValidation(
            matchesOutboxRevision: true,
            firstUntrustedMutationID: mutation.id
          )
        }
      }
      return InstantOptimisticEffectReceiptValidation(
        matchesOutboxRevision: true,
        firstUntrustedMutationID: nil
      )
    }
  }

  package func optimisticEffectReceiptFingerprintForTesting(id: String) throws -> String? {
    try storedOptimisticEffectReceiptFingerprintWithoutTransaction(id: id)
  }

  private func decodeOutboxBody<Value: Decodable>(_ json: String) throws -> Value {
    guard let data = json.data(using: .utf8) else {
      throw persistenceError(
        operation: "decode outbox delivery row",
        message: "SQLite outbox JSON was not UTF-8."
      )
    }
    return try decoder.decode(Value.self, from: data)
  }

  private func saveOutboxDeliveryMetadataWithoutTransaction(
    _ mutation: PendingMutation
  ) throws {
    let encodedBody = try encode(mutation)
    let row = try loadOutboxBodyRowWithoutTransaction(id: mutation.id)
    let hasPreparedReceipt = if let row {
      try hasStoredPreparedOptimisticEffectReceipt(mutation, in: row)
    } else {
      false
    }
    let hasAcceptedWireIntent = if let row {
      try hasStoredServerAcceptance(mutation, in: row)
    } else {
      false
    }
    try execute(
      """
      UPDATE instant_outbox
      SET delivery_state = ?, delivery_metadata_version = ?, transport_step_count = ?,
          encoded_body_bytes = ?, lifecycle_json = ?, failure_message = ?,
          confirmation_proven = ?, optimistic_overlay_active = ?
      WHERE mutation_id = ?
      """,
      [
        .text(durableDeliveryState(
          for: mutation,
          hasServerAcceptance: hasAcceptedWireIntent
        ).rawValue),
        .int(Int64(InstantOutboxDeliveryMetadata.currentVersion)),
        .int(Int64(InstantOutboxDeliveryMetadata.stepCount(in: mutation))),
        .int(Int64(encodedBody.utf8.count)),
        .text(try encode(mutation.compactedForMemory)),
        mutation.failureMessage.map(SQLiteBinding.text) ?? .null,
        .int(hasAcceptedWireIntent ? 1 : 0),
        .int(mutation.optimisticOverlayState == .removed && hasPreparedReceipt ? 0 : 1),
        .text(mutation.id),
      ]
    )
    try replaceOutboxWriteKeysWithoutTransaction(for: mutation)
  }

  private func quarantineInvalidOutboxMutationWithoutTransaction(
    _ row: InstantOutboxBodyRow,
    reason: String
  ) throws -> PendingMutation {
    let message =
      "Instant quarantined corrupt durable mutation '\(row.mutationID)'. \(reason)"
    var mutation = PendingMutation(
      id: row.mutationID,
      createdAt: InstantTimestamp(milliseconds: row.createdAtMilliseconds),
      transaction: InstantStoreTransaction(id: row.mutationID, operations: []),
      status: .failed,
      failureMessage: message
    )
    mutation.failure = InstantMutationFailure(
      code: .persistenceFailed,
      message: message
    )
    mutation.optimisticOverlayState = nil
    mutation.optimisticEffectReceiptVersion = nil
    mutation.rollbackTransaction = nil
    let encodedMutation = try encode(mutation)
    let encodedLifecycle = try encode(mutation.compactedForMemory)
    try execute(
      """
      UPDATE instant_outbox
      SET status = ?, delivery_state = ?, delivery_metadata_version = ?,
          transport_step_count = 0, encoded_body_bytes = ?, lifecycle_json = ?,
          failure_message = ?, confirmation_proven = 0, quarantine_json = ?,
          quarantine_lifecycle_json = lifecycle_json,
          optimistic_overlay_active = 1, delivery_claim_state = ?,
          delivery_claim_token = NULL, delivery_claimant_id = NULL,
          delivery_claim_deadline_ms = NULL,
          delivery_claim_projected_body_bytes = NULL, json = ?
      WHERE mutation_id = ?
      """,
      [
        .text(InstantMutationStatus.failed.rawValue),
        .text(InstantOutboxDeliveryState.invalid.rawValue),
        .int(Int64(InstantOutboxDeliveryMetadata.currentVersion)),
        .int(Int64(encodedMutation.utf8.count)),
        .text(encodedLifecycle),
        .text(message),
        .text(row.json),
        .text(InstantOutboxDeliveryClaimState.ready.rawValue),
        .text(encodedMutation),
        .text(row.mutationID),
      ]
    )
    try execute(
      "DELETE FROM instant_outbox_write_keys WHERE mutation_id = ?",
      [.text(row.mutationID)]
    )
    try resetOptimisticEffectMetadataForUnknownMutationWithoutTransaction(
      id: row.mutationID
    )
    try saveMutationLifecycleWithoutTransaction(mutation)
    InstantDiagnostics.shared.record(
      .error,
      subsystem: "instant-swift-data-core",
      category: "outbox",
      event: "outbox.mutation.quarantined-corrupt-body",
      message: message,
      metadata: ["mutationID": row.mutationID],
      correlationID: row.mutationID
    )
    recordOutboxQuarantineIssue(
      mutationID: row.mutationID,
      message: message,
      recovery:
        "The row is now a visible failed synchronization blocker. Its original bytes remain in instant_outbox.quarantine_json at \(fileURL.path). Automatic synchronization, retry, and discard are intentionally refused until an app-owned persistence reset or rebuild."
    )
    return mutation
  }

  /// Moves an oversized body to durable quarantine using SQLite itself, so the
  /// automatic path never materializes the unbounded string in Swift memory.
  private func quarantineOversizedOutboxMutationWithoutTransaction(
    id: String,
    createdAtMilliseconds: Int64,
    encodedBodyByteCount: Int,
    maximumEncodedBodyByteCount: Int
  ) throws -> PendingMutation {
    let message =
      "Instant quarantined durable mutation '\(id)' because its \(encodedBodyByteCount)-byte body exceeds the \(maximumEncodedBodyByteCount)-byte automatic-delivery limit."
    var mutation = PendingMutation(
      id: id,
      createdAt: InstantTimestamp(milliseconds: createdAtMilliseconds),
      transaction: InstantStoreTransaction(id: id, operations: []),
      status: .failed,
      failureMessage: message
    )
    mutation.failure = InstantMutationFailure(code: .validationFailed, message: message)
    mutation.optimisticOverlayState = nil
    mutation.optimisticEffectReceiptVersion = nil
    mutation.rollbackTransaction = nil
    let encodedMutation = try encode(mutation)
    try execute(
      """
      UPDATE instant_outbox
      SET status = ?, delivery_state = ?, delivery_metadata_version = ?,
          transport_step_count = 0, encoded_body_bytes = ?, lifecycle_json = ?,
          failure_message = ?, confirmation_proven = 0, quarantine_json = json,
          quarantine_lifecycle_json = lifecycle_json,
          optimistic_overlay_active = 1, delivery_claim_state = ?,
          delivery_claim_token = NULL, delivery_claimant_id = NULL,
          delivery_claim_deadline_ms = NULL,
          delivery_claim_projected_body_bytes = NULL, json = ?
      WHERE mutation_id = ?
      """,
      [
        .text(InstantMutationStatus.failed.rawValue),
        .text(InstantOutboxDeliveryState.invalid.rawValue),
        .int(Int64(InstantOutboxDeliveryMetadata.currentVersion)),
        .int(Int64(encodedMutation.utf8.count)),
        .text(try encode(mutation.compactedForMemory)),
        .text(message),
        .text(InstantOutboxDeliveryClaimState.ready.rawValue),
        .text(encodedMutation),
        .text(id),
      ]
    )
    try execute(
      "DELETE FROM instant_outbox_write_keys WHERE mutation_id = ?",
      [.text(id)]
    )
    try resetOptimisticEffectMetadataForUnknownMutationWithoutTransaction(id: id)
    try saveMutationLifecycleWithoutTransaction(mutation)
    InstantDiagnostics.shared.record(
      .error,
      subsystem: "instant-swift-data-core",
      category: "outbox",
      event: "outbox.mutation.quarantined-oversized-body",
      message: message,
      metadata: [
        "mutationID": id,
        "encodedBodyByteCount": String(encodedBodyByteCount),
        "maximumEncodedBodyByteCount": String(maximumEncodedBodyByteCount),
      ],
      correlationID: id
    )
    recordOutboxQuarantineIssue(
      mutationID: id,
      message: message,
      recovery:
        "The row is a visible failed synchronization blocker. Its original bytes remain in instant_outbox.quarantine_json at \(fileURL.path). Automatic synchronization, retry, and discard are intentionally refused until an app-owned persistence reset or rebuild."
    )
    return mutation
  }

  /// Quarantines a legacy durable row whose normalized transport expansion is
  /// larger than the fixed automatic-delivery step limit. Current metadata lets
  /// this transition copy the raw JSON inside SQLite without decoding it.
  private func quarantineOverLimitStepOutboxMutationWithoutTransaction(
    id: String,
    createdAtMilliseconds: Int64,
    transportStepCount: Int
  ) throws -> PendingMutation {
    let maximumStepCount = InstantAutomaticOutboxClaimLimits.maximumStepCount
    let message =
      "Instant quarantined durable mutation '\(id)' because its \(transportStepCount) transport steps exceeds the \(maximumStepCount)-step automatic-delivery limit."
    var mutation = PendingMutation(
      id: id,
      createdAt: InstantTimestamp(milliseconds: createdAtMilliseconds),
      transaction: InstantStoreTransaction(id: id, operations: []),
      status: .failed,
      failureMessage: message
    )
    mutation.failure = InstantMutationFailure(code: .validationFailed, message: message)
    mutation.optimisticOverlayState = nil
    mutation.optimisticEffectReceiptVersion = nil
    mutation.rollbackTransaction = nil
    let encodedMutation = try encode(mutation)
    try execute(
      """
      UPDATE instant_outbox
      SET status = ?, delivery_state = ?, delivery_metadata_version = ?,
          transport_step_count = 0, encoded_body_bytes = ?, lifecycle_json = ?,
          failure_message = ?, confirmation_proven = 0, quarantine_json = json,
          quarantine_lifecycle_json = lifecycle_json,
          optimistic_overlay_active = 1, delivery_claim_state = ?,
          delivery_claim_token = NULL, delivery_claimant_id = NULL,
          delivery_claim_deadline_ms = NULL,
          delivery_claim_projected_body_bytes = NULL, json = ?
      WHERE mutation_id = ?
      """,
      [
        .text(InstantMutationStatus.failed.rawValue),
        .text(InstantOutboxDeliveryState.invalid.rawValue),
        .int(Int64(InstantOutboxDeliveryMetadata.currentVersion)),
        .int(Int64(encodedMutation.utf8.count)),
        .text(try encode(mutation.compactedForMemory)),
        .text(message),
        .text(InstantOutboxDeliveryClaimState.ready.rawValue),
        .text(encodedMutation),
        .text(id),
      ]
    )
    try execute(
      "DELETE FROM instant_outbox_write_keys WHERE mutation_id = ?",
      [.text(id)]
    )
    try resetOptimisticEffectMetadataForUnknownMutationWithoutTransaction(id: id)
    try saveMutationLifecycleWithoutTransaction(mutation)
    InstantDiagnostics.shared.record(
      .error,
      subsystem: "instant-swift-data-core",
      category: "outbox",
      event: "outbox.mutation.quarantined-over-limit-steps",
      message: message,
      metadata: [
        "mutationID": id,
        "transportStepCount": String(transportStepCount),
        "maximumTransportStepCount": String(maximumStepCount),
      ],
      correlationID: id
    )
    recordOutboxQuarantineIssue(
      mutationID: id,
      message: message,
      recovery:
        "The row is a visible failed synchronization blocker. Its original bytes remain in instant_outbox.quarantine_json at \(fileURL.path). Automatic synchronization, retry, and discard are intentionally refused until an app-owned persistence reset or rebuild."
    )
    return mutation
  }

  /// Removes any prior body-derived footprint after quarantine replaces a row
  /// with an unknown-effect shell. Leaving the old metadata behind could make a
  /// later server apply treat the shell as normalized and try to peel an effect
  /// whose provenance is intentionally unknown.
  private func resetOptimisticEffectMetadataForUnknownMutationWithoutTransaction(
    id: String
  ) throws {
    try execute(
      """
      UPDATE instant_outbox
      SET optimistic_effect_metadata_version = 0,
          optimistic_effect_is_global = 0,
          optimistic_effect_receipt_fingerprint = NULL,
          delivery_claim_payload_fingerprint = NULL,
          server_acceptance_payload_fingerprint = NULL,
          confirmation_proven = 0
      WHERE mutation_id = ?
      """,
      [.text(id)]
    )
    try execute(
      "DELETE FROM instant_outbox_effect_entities WHERE mutation_id = ?",
      [.text(id)]
    )
  }

  private func recordOutboxQuarantineIssue(
    mutationID: String,
    message: String,
    recovery: String
  ) {
    guard var batch = activeOutboxQuarantineIssueBatch else {
      reportIssue("\(message)\n\n\(recovery)")
      return
    }
    batch.record(
      mutationID: mutationID,
      message: message,
      recovery: recovery
    )
    activeOutboxQuarantineIssueBatch = batch
  }

  private func reportOutboxQuarantineIssueBatch(
    _ batch: InstantOutboxQuarantineIssueBatch?
  ) {
    guard let batch, batch.count > 0,
      let firstMessage = batch.firstMessage,
      let firstRecovery = batch.firstRecovery
    else { return }
    let exampleMutationIDs = batch.exampleMutationIDs.joined(separator: ", ")
    reportIssue(
      """
      Instant quarantined \(batch.count) durable outbox row\(batch.count == 1 ? "" : "s") during one atomic persistence operation.

      First failure: \(firstMessage)
      Example mutation IDs: \(exampleMutationIDs)

      \(firstRecovery)
      """
    )
  }

  private func replaceOutboxWriteKeysWithoutTransaction(
    for mutation: PendingMutation
  ) throws {
    try execute(
      "DELETE FROM instant_outbox_write_keys WHERE mutation_id = ?",
      [.text(mutation.id)]
    )
    let keys = InstantOutboxDeliveryMetadata.writeKeys(in: mutation)
      .sorted { lhs, rhs in
        (lhs.entityID, lhs.attributeID) < (rhs.entityID, rhs.attributeID)
      }
    for key in keys {
      try execute(
        """
        INSERT INTO instant_outbox_write_keys (mutation_id, entity_id, attribute_id)
        VALUES (?, ?, ?)
        """,
        [
          .text(mutation.id),
          .text(key.entityID),
          .text(key.attributeID),
        ]
      )
    }
  }

  private func replaceOutboxEffectEntitiesWithoutTransaction(
    mutationID: String,
    createdAtMilliseconds: Int64,
    entityIDs: Set<String>
  ) throws {
    try execute(
      "DELETE FROM instant_outbox_effect_entities WHERE mutation_id = ?",
      [.text(mutationID)]
    )
    for entityID in entityIDs.sorted() {
      try execute(
        """
        INSERT INTO instant_outbox_effect_entities (mutation_id, entity_id, created_at_ms)
        VALUES (?, ?, ?)
        """,
        [.text(mutationID), .text(entityID), .int(createdAtMilliseconds)]
      )
    }
  }

  /// Returns true when a later locally visible overlay cannot provide a
  /// trustworthy normalized write-key proof. Such an overlay is not
  /// authoritative server state, so delivery must conservatively preserve all
  /// selected writes rather than filtering one away.
  private func hasUnknownActiveOverlayAfterWithoutTransaction(
    _ position: InstantOutboxDeliveryPosition,
    excludingClaimToken claimToken: String
  ) throws -> Bool {
    try selectInt64(
      """
      SELECT EXISTS(
        SELECT 1
        FROM instant_outbox AS outbox
        WHERE (
          outbox.created_at_ms > ?
          OR (outbox.created_at_ms = ? AND outbox.mutation_id > ?)
        )
        AND outbox.optimistic_overlay_active != 0
        AND COALESCE(outbox.confirmation_proven, 0) = 0
        AND NOT (
          outbox.delivery_claim_state = ?
          AND COALESCE(outbox.delivery_claim_token, '') = ?
        )
        AND (
          outbox.delivery_metadata_version < ?
          OR NOT EXISTS (
            SELECT 1
            FROM instant_outbox_write_keys AS write_keys
            WHERE write_keys.mutation_id = outbox.mutation_id
          )
        )
        LIMIT 1
      )
      """,
      [
        .int(position.createdAtMilliseconds),
        .int(position.createdAtMilliseconds),
        .text(position.mutationID),
        .text(InstantOutboxDeliveryClaimState.claimed.rawValue),
        .text(claimToken),
        .int(Int64(InstantOutboxDeliveryMetadata.currentVersion)),
      ]
    ) != 0
  }

  private func hasActiveOverlayWriteKeyAfterWithoutTransaction(
    _ key: InstantVisibleWriteKey,
    position: InstantOutboxDeliveryPosition,
    excludingClaimToken claimToken: String
  ) throws -> Bool {
    try selectInt64(
      """
      SELECT EXISTS(
        SELECT 1
        FROM instant_outbox_write_keys AS write_keys
        JOIN instant_outbox AS outbox
          ON outbox.mutation_id = write_keys.mutation_id
        WHERE (
          outbox.created_at_ms > ?
          OR (outbox.created_at_ms = ? AND outbox.mutation_id > ?)
        )
        AND outbox.optimistic_overlay_active != 0
        AND outbox.confirmation_proven = 0
        AND NOT (
          outbox.delivery_claim_state = ?
          AND COALESCE(outbox.delivery_claim_token, '') = ?
        )
        AND write_keys.entity_id = ?
        AND write_keys.attribute_id = ?
        LIMIT 1
      )
      """,
      [
        .int(position.createdAtMilliseconds),
        .int(position.createdAtMilliseconds),
        .text(position.mutationID),
        .text(InstantOutboxDeliveryClaimState.claimed.rawValue),
        .text(claimToken),
        .text(key.entityID),
        .text(key.attributeID),
      ]
    ) != 0
  }

  private func hasAutomaticDeliveryCandidateWithoutTransaction() throws -> Bool {
    let sql =
      """
      SELECT EXISTS(
        SELECT 1
        FROM instant_outbox
        WHERE delivery_claim_state = ?
          AND (
            delivery_state = ?
            OR (status IN (?, ?) AND delivery_metadata_version < ?)
          )
        LIMIT 1
      )
      """
    let bindings: [SQLiteBinding] = [
      .text(InstantOutboxDeliveryClaimState.ready.rawValue),
      .text(InstantOutboxDeliveryState.needsDelivery.rawValue),
      .text(InstantMutationStatus.pending.rawValue),
      .text(InstantMutationStatus.confirmed.rawValue),
      .int(Int64(InstantOutboxDeliveryMetadata.currentVersion)),
    ]
    return try selectInt64(sql, bindings) != 0
  }

  private func loadVisibleWriteFilterWithoutTransaction(
    for writeKeys: Set<InstantVisibleWriteKey>
  ) throws -> InstantVisibleWriteFilter {
    let attributeIDs = Set(writeKeys.map(\.attributeID)).sorted()
    var attributesByID: [String: InstantAttribute] = [:]
    attributesByID.reserveCapacity(attributeIDs.count)
    for attributeID in attributeIDs {
      let attributes: [InstantAttribute] = try selectJSON(
        "SELECT json FROM instant_attributes WHERE id = ? LIMIT 1",
        [.text(attributeID)]
      )
      if let attribute = attributes.first {
        attributesByID[attributeID] = attribute
      }
    }

    var newestVisibleWrite: [InstantVisibleWriteKey: InstantTimestamp] = [:]
    var newestVisibleRequiredScalarEncodedValueByteCount:
      [InstantVisibleWriteKey: Int] = [:]
    newestVisibleWrite.reserveCapacity(writeKeys.count)
    newestVisibleRequiredScalarEncodedValueByteCount.reserveCapacity(writeKeys.count)
    for key in writeKeys {
      // A pending optimistic triple is locally visible but is not server proof.
      // Using it here could alias a successor's value into an older mutation and
      // leave that value remote even when the successor is later rejected.
      if let attribute = attributesByID[key.attributeID],
        attribute.cardinality == .one,
        !attribute.primaryKey,
        attribute.isRequired,
        attribute.valueType != .ref
      {
        var statement: OpaquePointer?
        try prepare(
          """
          SELECT triples.tx_time_ms, length(CAST(triples.value_json AS BLOB))
          FROM instant_triples AS triples
          WHERE triples.entity_id = ? AND triples.attribute_id = ?
            AND NOT EXISTS (
              SELECT 1
              FROM instant_outbox AS outbox
              WHERE outbox.mutation_id = triples.tx_id
                AND outbox.optimistic_overlay_active != 0
                AND COALESCE(outbox.confirmation_proven, 0) = 0
            )
          ORDER BY triples.tx_time_ms DESC, triples.value_json ASC
          LIMIT 1
          """,
          statement: &statement
        )
        defer { sqlite3_finalize(statement) }
        try bind([.text(key.entityID), .text(key.attributeID)], to: statement)
        let code = sqlite3_step(statement)
        if code == SQLITE_ROW {
          let encodedValueByteCount = Int(sqlite3_column_int64(statement, 1))
          guard encodedValueByteCount >= 0 else {
            throw persistenceError(
              operation: "read visible required scalar metadata",
              message: "SQLite returned a negative required-scalar value length."
            )
          }
          newestVisibleWrite[key] = InstantTimestamp(
            milliseconds: sqlite3_column_int64(statement, 0)
          )
          newestVisibleRequiredScalarEncodedValueByteCount[key] = encodedValueByteCount
        } else if code != SQLITE_DONE {
          throw persistenceError(
            operation: "read visible required scalar metadata",
            message: lastErrorMessage()
          )
        }
        continue
      }
      guard let milliseconds = try selectScalar(
        """
        SELECT CAST(MAX(triples.tx_time_ms) AS TEXT)
        FROM instant_triples AS triples
        WHERE triples.entity_id = ? AND triples.attribute_id = ?
          AND NOT EXISTS (
            SELECT 1
            FROM instant_outbox AS outbox
            WHERE outbox.mutation_id = triples.tx_id
              AND outbox.optimistic_overlay_active != 0
              AND COALESCE(outbox.confirmation_proven, 0) = 0
          )
        """,
        [.text(key.entityID), .text(key.attributeID)]
      ).flatMap(Int64.init)
      else { continue }
      newestVisibleWrite[key] = InstantTimestamp(milliseconds: milliseconds)
    }
    return InstantVisibleWriteFilter(
      attributesByID: attributesByID,
      newestVisibleWrite: newestVisibleWrite,
      newestVisibleRequiredScalar: [:],
      newestVisibleRequiredScalarEncodedValueByteCount:
        newestVisibleRequiredScalarEncodedValueByteCount
    )
  }

  private func loadVisibleRequiredScalarWithoutTransaction(
    for key: InstantVisibleWriteKey,
    timestamp: InstantTimestamp,
    encodedValueByteCount: Int
  ) throws -> InstantTriple {
    var statement: OpaquePointer?
    try prepare(
      """
      SELECT triples.json
      FROM instant_triples AS triples
      WHERE triples.entity_id = ? AND triples.attribute_id = ?
        AND triples.tx_time_ms = ?
        AND length(CAST(triples.value_json AS BLOB)) = ?
        AND NOT EXISTS (
          SELECT 1
          FROM instant_outbox AS outbox
          WHERE outbox.mutation_id = triples.tx_id
            AND outbox.optimistic_overlay_active != 0
            AND COALESCE(outbox.confirmation_proven, 0) = 0
        )
      ORDER BY triples.value_json ASC
      LIMIT 1
      """,
      statement: &statement
    )
    defer { sqlite3_finalize(statement) }
    try bind(
      [
        .text(key.entityID),
        .text(key.attributeID),
        .int(timestamp.milliseconds),
        .int(Int64(encodedValueByteCount)),
      ],
      to: statement
    )
    guard sqlite3_step(statement) == SQLITE_ROW,
      let jsonBytes = sqlite3_column_text(statement, 0)
    else {
      throw persistenceError(
        operation: "hydrate visible required scalar",
        message:
          "The authoritative required scalar changed inside one atomic delivery claim."
      )
    }
    let json = String(cString: jsonBytes)
    guard let data = json.data(using: .utf8) else {
      throw persistenceError(
        operation: "hydrate visible required scalar",
        message: "The authoritative required scalar was not UTF-8 JSON."
      )
    }
    let triple = try decoder.decode(InstantTriple.self, from: data)
    guard triple.entityID == key.entityID,
      triple.attributeID == key.attributeID,
      triple.txTime == timestamp
    else {
      throw persistenceError(
        operation: "hydrate visible required scalar",
        message: "The decoded authoritative required scalar did not match its metadata."
      )
    }
    decodedVisibleRequiredScalarCount += 1
    decodedVisibleRequiredScalarValueByteCount += encodedValueByteCount
    return triple
  }

  private func loadOutboxBodyRowsWithoutTransaction(
    _ sql: String,
    _ bindings: [SQLiteBinding] = []
  ) throws -> [InstantOutboxBodyRow] {
    var statement: OpaquePointer?
    try prepare(sql, statement: &statement)
    defer { sqlite3_finalize(statement) }
    try bind(bindings, to: statement)

    var rows: [InstantOutboxBodyRow] = []
    while true {
      let code = sqlite3_step(statement)
      if code == SQLITE_DONE { return rows }
      guard code == SQLITE_ROW else {
        throw persistenceError(operation: "read outbox delivery rows", message: lastErrorMessage())
      }
      guard
        let mutationID = sqlite3_column_text(statement, 0),
        let json = sqlite3_column_text(statement, 2)
      else {
        throw persistenceError(
          operation: "read outbox delivery rows",
          message: "SQLite returned a NULL bounded-delivery column."
        )
      }
      let body = String(cString: json)
      materializedOutboxBodyCount += 1
      materializedOutboxBodyByteCount += body.utf8.count
      rows.append(
        InstantOutboxBodyRow(
          mutationID: String(cString: mutationID),
          createdAtMilliseconds: sqlite3_column_int64(statement, 1),
          json: body,
          optimisticEffectReceiptFingerprint: sqlite3_column_text(statement, 3)
            .map(String.init(cString:)),
          deliveryClaimPayloadFingerprint: sqlite3_column_text(statement, 4)
            .map(String.init(cString:)),
          serverAcceptancePayloadFingerprint: sqlite3_column_text(statement, 5)
            .map(String.init(cString:))
        )
      )
    }
  }

  private func selectJSON<Value: Decodable>(
    _ sql: String,
    _ bindings: [SQLiteBinding] = []
  ) throws -> [Value] {
    var statement: OpaquePointer?
    try prepare(sql, statement: &statement)
    defer { sqlite3_finalize(statement) }
    try bind(bindings, to: statement)

    var values: [Value] = []
    while true {
      let code = sqlite3_step(statement)
      if code == SQLITE_DONE {
        return values
      }
      guard code == SQLITE_ROW else {
        throw persistenceError(operation: "read SQL", message: lastErrorMessage())
      }
      guard let cString = sqlite3_column_text(statement, 0)
      else {
        throw persistenceError(operation: "decode row", message: "SQLite returned a NULL JSON row.")
      }
      let json = String(cString: cString)
      guard let data = json.data(using: .utf8)
      else {
        throw persistenceError(operation: "decode row", message: "SQLite JSON was not UTF-8.")
      }
      values.append(try decoder.decode(Value.self, from: data))
    }
  }

  private func selectBatchedJSON<Value: Decodable & Sendable>(
    _ sql: String,
    _ bindings: [SQLiteBinding] = [],
    maxRowsPerBatch: Int = 1_024,
    maxEncodedBytesPerBatch: Int = 1_024 * 1_024
  ) throws -> (values: [Value], batchCount: Int, encodedByteCount: Int) {
    var statement: OpaquePointer?
    try prepare(sql, statement: &statement)
    defer { sqlite3_finalize(statement) }
    try bind(bindings, to: statement)

    let decodeResults = JSONBatchDecodeResults<Value>()
    let decodeGroup = DispatchGroup()
    let decodeSlots = DispatchSemaphore(value: 2)
    let persistencePath = fileURL.path
    var batchData = Data()
    batchData.reserveCapacity(maxEncodedBytesPerBatch + 1)
    batchData.append(0x5B)
    var batchRowCount = 0
    var totalRowCount = 0
    var batchCount = 0
    var encodedByteCount = 0

    func flushBatch() {
      guard batchRowCount > 0 else { return }
      batchData.append(0x5D)
      let data = batchData
      let batchIndex = batchCount
      let firstRowNumber = totalRowCount - batchRowCount + 1
      let lastRowNumber = totalRowCount
      decodeSlots.wait()
      decodeGroup.enter()
      instantPersistenceDecodeQueue.async {
        defer {
          decodeSlots.signal()
          decodeGroup.leave()
        }
        do {
          decodeResults.store(
            .success(try JSONDecoder().decode([Value].self, from: data)),
            at: batchIndex
          )
        } catch {
          decodeResults.store(
            .failure(
              InstantError(
                code: .persistenceFailed,
                operation: "decode persisted JSON rows",
                message:
                  "SQLite JSON rows \(firstRowNumber)-\(lastRowNumber) could not be decoded: \(error)",
                recovery:
                  "Inspect the local SQLite cache at \(persistencePath), then retry the command."
              )
            ),
            at: batchIndex
          )
        }
      }
      batchCount += 1
      batchData = Data()
      batchData.reserveCapacity(maxEncodedBytesPerBatch + 1)
      batchData.append(0x5B)
      batchRowCount = 0
    }

    defer { decodeGroup.wait() }
    while true {
      let code = sqlite3_step(statement)
      if code == SQLITE_DONE {
        flushBatch()
        decodeGroup.wait()
        return (try decodeResults.joined(batchCount: batchCount), batchCount, encodedByteCount)
      }
      guard code == SQLITE_ROW else {
        throw persistenceError(operation: "read SQL", message: lastErrorMessage())
      }
      guard let bytes = sqlite3_column_text(statement, 0) else {
        throw persistenceError(operation: "decode row", message: "SQLite returned a NULL JSON row.")
      }
      let byteCount = Int(sqlite3_column_bytes(statement, 0))
      let separatorByteCount = batchRowCount == 0 ? 0 : 1
      if batchRowCount > 0,
        batchRowCount >= maxRowsPerBatch
          || batchData.count + separatorByteCount + byteCount + 1 > maxEncodedBytesPerBatch
      {
        flushBatch()
      }
      if batchRowCount > 0 {
        batchData.append(0x2C)
      }
      batchData.append(bytes, count: byteCount)
      batchRowCount += 1
      totalRowCount += 1
      encodedByteCount += byteCount
    }
  }

  private func selectScalar(_ sql: String, _ bindings: [SQLiteBinding] = []) throws -> String? {
    var statement: OpaquePointer?
    try prepare(sql, statement: &statement)
    defer { sqlite3_finalize(statement) }
    try bind(bindings, to: statement)

    let code = sqlite3_step(statement)
    if code == SQLITE_DONE { return nil }
    guard code == SQLITE_ROW else {
      throw persistenceError(operation: "read SQL", message: lastErrorMessage())
    }
    guard let cString = sqlite3_column_text(statement, 0) else { return nil }
    return String(cString: cString)
  }

  private func selectStrings(
    _ sql: String,
    _ bindings: [SQLiteBinding] = []
  ) throws -> [String] {
    var statement: OpaquePointer?
    try prepare(sql, statement: &statement)
    defer { sqlite3_finalize(statement) }
    try bind(bindings, to: statement)

    var values: [String] = []
    while true {
      let code = sqlite3_step(statement)
      if code == SQLITE_DONE { return values }
      guard code == SQLITE_ROW else {
        throw persistenceError(operation: "read SQL", message: lastErrorMessage())
      }
      guard let cString = sqlite3_column_text(statement, 0) else {
        throw persistenceError(
          operation: "read SQL",
          message: "SQLite returned a NULL string row."
        )
      }
      values.append(String(cString: cString))
    }
  }

  private func selectInt64(_ sql: String, _ bindings: [SQLiteBinding] = []) throws -> Int64 {
    var statement: OpaquePointer?
    try prepare(sql, statement: &statement)
    defer { sqlite3_finalize(statement) }
    try bind(bindings, to: statement)

    let code = sqlite3_step(statement)
    if code == SQLITE_DONE { return 0 }
    guard code == SQLITE_ROW else {
      throw persistenceError(operation: "read SQL", message: lastErrorMessage())
    }
    return sqlite3_column_int64(statement, 0)
  }

  private func loadQueryCacheRowsWithoutTransaction() throws -> [QueryCacheStorageRow] {
    var statement: OpaquePointer?
    try prepare(
      """
      SELECT cache_key, json, updated_at_ms
      FROM instant_query_cache
      ORDER BY updated_at_ms, query_id, cache_key
      """,
      statement: &statement
    )
    defer { sqlite3_finalize(statement) }

    var rows: [QueryCacheStorageRow] = []
    while true {
      let code = sqlite3_step(statement)
      if code == SQLITE_DONE {
        return rows
      }
      guard code == SQLITE_ROW else {
        throw persistenceError(operation: "read query cache rows", message: lastErrorMessage())
      }
      guard
        let cacheKeyCString = sqlite3_column_text(statement, 0),
        let jsonCString = sqlite3_column_text(statement, 1)
      else {
        throw persistenceError(
          operation: "read query cache rows",
          message: "SQLite returned a NULL query cache column."
        )
      }
      rows.append(
        QueryCacheStorageRow(
          cacheKey: String(cString: cacheKeyCString),
          json: String(cString: jsonCString),
          updatedAtMilliseconds: sqlite3_column_int64(statement, 2)
        )
      )
    }
  }

  private func loadLiveQueryResultRowsWithoutTransaction() throws
    -> [LiveQueryResultStorageRow]
  {
    var statement: OpaquePointer?
    try prepare(
      """
      SELECT query_key, updated_at_ms, triple_count
      FROM instant_live_query_results
      ORDER BY updated_at_ms, query_key
      """,
      statement: &statement
    )
    defer { sqlite3_finalize(statement) }

    var rows: [LiveQueryResultStorageRow] = []
    while true {
      let code = sqlite3_step(statement)
      if code == SQLITE_DONE {
        return rows
      }
      guard code == SQLITE_ROW else {
        throw persistenceError(
          operation: "read live query result rows",
          message: lastErrorMessage()
        )
      }
      guard let queryKeyCString = sqlite3_column_text(statement, 0) else {
        throw persistenceError(
          operation: "read live query result rows",
          message: "SQLite returned a NULL live query result column."
        )
      }
      rows.append(
        LiveQueryResultStorageRow(
          queryKey: String(cString: queryKeyCString),
          updatedAtMilliseconds: sqlite3_column_int64(statement, 1),
          tripleCount: Int(sqlite3_column_int64(statement, 2))
        )
      )
    }
  }

  private func retainedLiveQueryEntityIDsWithoutTransaction(
    attributes: [InstantAttribute]
  ) throws -> Set<String> {
    let rows = try loadLiveQueryResultRowsWithoutTransaction()
    var retained: Set<String> = []
    for row in rows {
      guard let result = try liveQueryResultWithoutTransaction(key: row.queryKey) else {
        continue
      }
      retained.formUnion(
        InstantLiveQueryNestedLimit.retainedEntityIDs(
          queryKey: result.key,
          triples: Array(result.triples),
          attributes: attributes
        )
      )
    }
    return retained
  }

  private func outboxRequiresConservativeLiveQueryPruningWithoutTransaction() throws -> Bool {
    try selectInt64(
      """
      SELECT EXISTS(
        SELECT 1
        FROM instant_outbox
        WHERE optimistic_overlay_active != 0
        LIMIT 1
      )
      """,
      []
    ) != 0
  }

  private func liveQueryResultWithoutTransaction(
    key: String
  ) throws -> InstantPersistedLiveQueryResult? {
    let results: [InstantPersistedLiveQueryResult] = try selectJSON(
      "SELECT json FROM instant_live_query_results WHERE query_key = ? LIMIT 1",
      [.text(key)]
    )
    return results.first
  }

  private func liveQueryTripleHasOwnerWithoutTransaction(
    _ identity: InstantLiveTripleIdentity,
    excludingQueryKeys: Set<String>
  ) throws -> Bool {
    var sql =
      """
      SELECT query_key
      FROM instant_live_query_triples
      WHERE entity_id = ? AND attribute_id = ? AND value_json = ?
      """
    var bindings: [SQLiteBinding] = [
      .text(identity.entityID),
      .text(identity.attributeID),
      .text(try encode(identity.value)),
    ]
    if !excludingQueryKeys.isEmpty {
      sql += " AND query_key NOT IN ("
        + Array(repeating: "?", count: excludingQueryKeys.count).joined(separator: ", ")
        + ")"
      bindings.append(contentsOf: excludingQueryKeys.sorted().map(SQLiteBinding.text))
    }
    sql += " LIMIT 1"
    return try selectScalar(sql, bindings) != nil
  }

  private static func indexLiveTriples(
    _ triples: [InstantTriple]
  ) -> [InstantLiveTripleIdentity: InstantTriple] {
    Dictionary(
      triples.map { (InstantLiveTripleIdentity($0), $0) },
      uniquingKeysWith: { _, latest in latest }
    )
  }

  private func saveStoreSnapshotWithoutTransaction(_ snapshot: InstantStoreSnapshot) throws {
    try invalidateDeclaredRelationStorageMarkerIfNeeded(
      replacingAttributes: snapshot.attributes
    )
    try execute("DELETE FROM instant_attributes")
    try execute("DELETE FROM instant_triples")

    for attribute in snapshot.attributes {
      try execute(
        "INSERT INTO instant_attributes (id, json) VALUES (?, ?)",
        [.text(attribute.id), .text(try encode(attribute))]
      )
    }

    for triple in snapshot.triples {
      try insertTripleWithoutTransaction(triple)
    }
  }

  private func insertTripleWithoutTransaction(_ triple: InstantTriple) throws {
    try invalidateDeclaredRelationStorageMarkerIfNeeded(
      forAttributeIDs: [triple.attributeID]
    )
    if deferredValueResidency.attributeIDs.contains(triple.attributeID) {
      try execute(
        "DELETE FROM instant_triples WHERE entity_id = ? AND attribute_id = ?",
        [.text(triple.entityID), .text(triple.attributeID)]
      )
    }
    try execute(
      """
      INSERT OR REPLACE INTO instant_triples
        (entity_id, attribute_id, value_json, tx_id, tx_time_ms, json)
      VALUES (?, ?, ?, ?, ?, ?)
      """,
      [
        .text(triple.entityID),
        .text(triple.attributeID),
        .text(try encode(triple.value)),
        .text(triple.txID),
        .int(triple.txTime.milliseconds),
        .text(try encode(triple)),
      ]
    )
  }

  private func saveTripleDiffWithoutTransaction(
    from previousTriples: [InstantTriple],
    to triples: [InstantTriple]
  ) throws {
    let previous = Dictionary(
      uniqueKeysWithValues: previousTriples.map { (StoredTripleKey($0), $0) }
    )
    let current = Dictionary(uniqueKeysWithValues: triples.map { (StoredTripleKey($0), $0) })
    for key in previous.keys where current[key] == nil {
      try execute(
        """
        DELETE FROM instant_triples
        WHERE entity_id = ? AND attribute_id = ? AND value_json = ?
        """,
        [.text(key.entityID), .text(key.attributeID), .text(try encode(key.value))]
      )
    }
    for triple in triples where previous[StoredTripleKey(triple)] != triple {
      try insertTripleWithoutTransaction(triple)
    }
  }

  private func replaceCachedTriples(
    in triples: inout [InstantTriple],
    with changedEntityTriples: [String: [InstantTriple]]
  ) {
    for entityID in changedEntityTriples.keys.sorted() {
      let lowerBound = tripleIndex(in: triples, entityID: entityID, includingEqual: true)
      let upperBound = tripleIndex(in: triples, entityID: entityID, includingEqual: false)
      let replacement = changedEntityTriples[entityID, default: []].sorted {
        if $0.attributeID != $1.attributeID {
          return $0.attributeID < $1.attributeID
        }
        return $0.value.comparableKey < $1.value.comparableKey
      }
      triples.replaceSubrange(lowerBound..<upperBound, with: replacement)
    }
  }

  private func cachedTriples(
    in triples: [InstantTriple],
    entityID: String
  ) -> [InstantTriple] {
    let lowerBound = tripleIndex(in: triples, entityID: entityID, includingEqual: true)
    let upperBound = tripleIndex(in: triples, entityID: entityID, includingEqual: false)
    return Array(triples[lowerBound..<upperBound])
  }

  private func tripleIndex(
    in triples: [InstantTriple],
    entityID: String,
    includingEqual: Bool
  ) -> Int {
    var lowerBound = triples.startIndex
    var upperBound = triples.endIndex
    while lowerBound < upperBound {
      let distance = triples.distance(from: lowerBound, to: upperBound)
      let index = triples.index(lowerBound, offsetBy: distance / 2)
      let belongsBeforeBoundary = includingEqual
        ? triples[index].entityID < entityID
        : triples[index].entityID <= entityID
      if belongsBeforeBoundary {
        lowerBound = triples.index(after: index)
      } else {
        upperBound = index
      }
    }
    return lowerBound
  }

  private func saveStoreSnapshotDiffWithoutTransaction(
    from previousSnapshot: InstantStoreSnapshot,
    to snapshot: InstantStoreSnapshot
  ) throws {
    if previousSnapshot.attributes != snapshot.attributes {
      try invalidateDeclaredRelationStorageMarkerIfNeeded(
        replacingAttributes: snapshot.attributes
      )
    }
    let previousAttributes = Dictionary(
      uniqueKeysWithValues: previousSnapshot.attributes.map { ($0.id, $0) }
    )
    let attributes = Dictionary(uniqueKeysWithValues: snapshot.attributes.map { ($0.id, $0) })

    for id in previousAttributes.keys where attributes[id] == nil {
      try execute("DELETE FROM instant_attributes WHERE id = ?", [.text(id)])
    }
    for attribute in snapshot.attributes where previousAttributes[attribute.id] != attribute {
      try execute(
        "INSERT OR REPLACE INTO instant_attributes (id, json) VALUES (?, ?)",
        [.text(attribute.id), .text(try encode(attribute))]
      )
    }

    let previousTriples = Dictionary(
      uniqueKeysWithValues: previousSnapshot.triples.map { (StoredTripleKey($0), $0) }
    )
    let triples = Dictionary(
      uniqueKeysWithValues: snapshot.triples.map { (StoredTripleKey($0), $0) }
    )

    let previousEntityIDs = Set(previousSnapshot.triples.map(\.entityID))
    let entityIDs = Set(snapshot.triples.map(\.entityID))
    for entityID in previousEntityIDs.subtracting(entityIDs) {
      try execute(
        "DELETE FROM instant_triples WHERE entity_id = ?",
        [.text(entityID)]
      )
    }

    for (key, _) in previousTriples where triples[key] == nil {
      try execute(
        """
        DELETE FROM instant_triples
        WHERE entity_id = ? AND attribute_id = ? AND value_json = ?
        """,
        [.text(key.entityID), .text(key.attributeID), .text(try encode(key.value))]
      )
    }
    for triple in snapshot.triples where previousTriples[StoredTripleKey(triple)] != triple {
      try insertTripleWithoutTransaction(triple)
    }
  }

  /// Public store persistence cannot prove how a changed snapshot relates to
  /// Runtime-owned optimistic layers. Rejecting the write preserves both the
  /// current cache and its active owner; clearing a receipt or deleting the row
  /// would leave an optimistic value ownerless. Runtime's atomic prepare/rebase
  /// seams use separate package-internal writers and are not subject to this
  /// public boundary.
  private func requireNoActiveOptimisticOwnerForPublicStoreChangeWithoutTransaction(
    from previousSnapshot: InstantStoreSnapshot,
    to snapshot: InstantStoreSnapshot
  ) throws {
    guard previousSnapshot != snapshot else { return }
    let activeMutationID = try selectScalar(
      """
      SELECT mutation_id
      FROM instant_outbox
      WHERE optimistic_overlay_active != 0
      ORDER BY created_at_ms, mutation_id
      LIMIT 1
      """
    )
    guard let activeMutationID else { return }
    throw persistenceError(
      operation: "save public store snapshot",
      message:
        "Store changes are blocked while optimistic mutation '\(activeMutationID)' owns materialized state."
    )
  }

  private func requirePublicOutboxDeletionIsSafeWithoutTransaction(id: String) throws {
    guard try selectInt64(
      """
      SELECT EXISTS(
        SELECT 1 FROM instant_outbox
        WHERE mutation_id = ? AND optimistic_overlay_active != 0
        LIMIT 1
      )
      """,
      [.text(id)]
    ) == 0 else {
      throw persistenceError(
        operation: "save public outbox",
        message:
          "Active optimistic mutation '\(id)' cannot be omitted without Runtime-owned rollback; preserve it until an app-owned persistence reset or rebuild."
      )
    }
  }

  private func saveOutboxWithoutTransaction(
    _ mutations: [PendingMutation],
    receiptWriteAuthority: InstantOptimisticEffectReceiptWriteAuthority
  ) throws {
    let mutationIDs = Set(mutations.map(\.id))
    let existingIDs = try selectStrings("SELECT mutation_id FROM instant_outbox")
    for id in existingIDs where !mutationIDs.contains(id) {
      if case .publicPersistence = receiptWriteAuthority {
        try requirePublicOutboxDeletionIsSafeWithoutTransaction(id: id)
      }
      try execute("DELETE FROM instant_outbox WHERE mutation_id = ?", [.text(id)])
    }
    for mutation in mutations {
      try saveOutboxMutationWithoutTransaction(
        mutation,
        receiptWriteAuthority: receiptWriteAuthority
      )
    }
  }

  private func saveOutboxDiffWithoutTransaction(
    from previousMutations: [PendingMutation],
    to mutations: [PendingMutation],
    receiptWriteAuthority: InstantOptimisticEffectReceiptWriteAuthority
  ) throws {
    let previous = Dictionary(uniqueKeysWithValues: previousMutations.map { ($0.id, $0) })
    let current = Dictionary(uniqueKeysWithValues: mutations.map { ($0.id, $0) })

    for id in previous.keys where current[id] == nil {
      if case .publicPersistence = receiptWriteAuthority {
        try requirePublicOutboxDeletionIsSafeWithoutTransaction(id: id)
      }
      try execute("DELETE FROM instant_outbox WHERE mutation_id = ?", [.text(id)])
    }
    for mutation in mutations where previous[mutation.id] != mutation {
      try saveOutboxMutationWithoutTransaction(
        mutation,
        receiptWriteAuthority: receiptWriteAuthority
      )
    }
  }

  private func saveOutboxMutationWithoutTransaction(
    _ mutation: PendingMutation,
    lifecycleID requestedLifecycleID: String? = nil,
    advancingFromMutationID: String? = nil,
    failureAttributeRevision: Int64? = nil,
    receiptWriteAuthority: InstantOptimisticEffectReceiptWriteAuthority
  ) throws {
    let candidateFingerprint = try mutation.optimisticEffectReceiptFingerprint()
    let candidateWireFingerprint = try mutation.mutationWireIntentFingerprint()
    let durableMutation = mutation
    var statement: OpaquePointer?
    try prepare(
      """
      SELECT optimistic_effect_receipt_fingerprint,
             server_acceptance_payload_fingerprint,
             server_transaction_id, confirmation_source, json,
             delivery_started
      FROM instant_outbox
      WHERE mutation_id = ?
      LIMIT 1
      """,
      statement: &statement
    )
    try bind([.text(mutation.id)], to: statement)
    let hasExisting = sqlite3_step(statement) == SQLITE_ROW
    let existingReceiptFingerprint = hasExisting
      ? sqlite3_column_text(statement, 0).map(String.init(cString:))
      : nil
    let existingAcceptanceFingerprint = hasExisting
      ? sqlite3_column_text(statement, 1).map(String.init(cString:))
      : nil
    let existingServerTransactionID = hasExisting
      ? sqlite3_column_text(statement, 2).map(String.init(cString:))
      : nil
    let existingConfirmationSource = hasExisting
      ? sqlite3_column_text(statement, 3).map(String.init(cString:))
      : nil
    let existingJSON = hasExisting
      ? sqlite3_column_text(statement, 4).map(String.init(cString:))
      : nil
    let existingDeliveryStarted = hasExisting
      ? sqlite3_column_int64(statement, 5) != 0
      : false
    sqlite3_finalize(statement)
    if case .publicPersistence = receiptWriteAuthority,
      existingReceiptFingerprint != nil,
      candidateFingerprint != existingReceiptFingerprint
    {
      throw persistenceError(
        operation: "persist prepared outbox mutation",
        message:
          "Mutation '\(mutation.id)' already owns a SQLite-bound optimistic layer. Public persistence cannot change or remove its prepared body while that layer remains materialized; submit new work through InstantRuntime."
      )
    }
    let receiptFingerprint: String?
    switch receiptWriteAuthority {
    case .runtimePrepared:
      receiptFingerprint = candidateFingerprint
    case .publicPersistence:
      receiptFingerprint = candidateFingerprint == existingReceiptFingerprint
        ? candidateFingerprint
        : nil
    }
    // Generic persistence never mints server acceptance from caller-visible
    // Codable fields. It can only carry an existing SQLite-owned wire binding
    // across an exact forward-intent match. ACK/server-result seams mint it.
    let existingWireFingerprint: String? = try existingJSON.flatMap { json in
      let existingMutation: PendingMutation = try decodeOutboxBody(json)
      guard existingMutation.id == mutation.id else { return nil }
      return try existingMutation.mutationWireIntentFingerprint()
    }
    let preservesMaterialAuthority: Bool
    switch receiptWriteAuthority {
    case .runtimePrepared:
      preservesMaterialAuthority = receiptFingerprint != nil
    case .publicPersistence:
      preservesMaterialAuthority = receiptFingerprint != nil
        && receiptFingerprint == existingReceiptFingerprint
    }
    let preservesAcceptedPayload = preservesMaterialAuthority
      && candidateWireFingerprint == existingWireFingerprint
    if existingAcceptanceFingerprint != nil, !preservesAcceptedPayload {
      throw persistenceError(
        operation: "persist accepted outbox mutation",
        message:
          "Mutation '\(mutation.id)' already has SQLite-bound server acceptance and cannot change its prepared materialization or forward wire intent. Use a new mutation id for new work."
      )
    }
    let acceptanceFingerprint = preservesAcceptedPayload
      ? existingAcceptanceFingerprint
      : nil
    if existingAcceptanceFingerprint != nil, mutation.status != .confirmed {
      throw persistenceError(
        operation: "persist accepted outbox mutation",
        message:
          "Mutation '\(mutation.id)' cannot downgrade a SQLite-bound server acceptance to '\(mutation.status.rawValue)'."
      )
    }
    if existingAcceptanceFingerprint != nil,
      mutation.serverTransactionID != existingServerTransactionID
        || mutation.confirmationSource?.rawValue != existingConfirmationSource
    {
      throw persistenceError(
        operation: "persist accepted outbox mutation",
        message:
          "Mutation '\(mutation.id)' cannot rewrite SQLite-bound server-acceptance evidence."
      )
    }
    if existingDeliveryStarted, candidateWireFingerprint != existingWireFingerprint {
      throw persistenceError(
        operation: "persist offered outbox mutation",
        message:
          "Mutation '\(mutation.id)' has already been offered to delivery and its forward wire intent is immutable. Use a new mutation id for compensating work."
      )
    }
    let deliveryState = durableDeliveryState(
      for: durableMutation,
      hasServerAcceptance: acceptanceFingerprint != nil
    )
    let encodedBody = try encode(durableMutation)
    let effectFootprint = receiptFingerprint == nil
      ? nil
      : InstantOptimisticEffectFootprint.normalized(for: durableMutation)
    try execute(
      """
      INSERT INTO instant_outbox (
        mutation_id,
        status,
        created_at_ms,
        delivery_state,
        delivery_metadata_version,
        transport_step_count,
        encoded_body_bytes,
        delivery_started,
        lifecycle_json,
        failure_message,
        failure_attribute_revision,
        confirmation_proven,
        optimistic_overlay_active,
        mutation_revision,
        optimistic_effect_metadata_version,
        optimistic_effect_is_global,
        optimistic_effect_receipt_fingerprint,
        server_acceptance_payload_fingerprint,
        server_transaction_id,
        confirmation_source,
        delivery_claim_state,
        json
      )
      VALUES (?, ?, ?, ?, ?, ?, ?, 0, ?, ?, ?, ?, ?, 1, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(mutation_id) DO UPDATE SET
        status = excluded.status,
        created_at_ms = excluded.created_at_ms,
        delivery_state = excluded.delivery_state,
        delivery_metadata_version = excluded.delivery_metadata_version,
        transport_step_count = excluded.transport_step_count,
        encoded_body_bytes = excluded.encoded_body_bytes,
        lifecycle_json = excluded.lifecycle_json,
        failure_message = excluded.failure_message,
        failure_attribute_revision = CASE
          WHEN excluded.status = 'failed'
            AND excluded.failure_message IS instant_outbox.failure_message
          THEN COALESCE(
            excluded.failure_attribute_revision,
            instant_outbox.failure_attribute_revision
          )
          ELSE excluded.failure_attribute_revision
        END,
        confirmation_proven = excluded.confirmation_proven,
        optimistic_overlay_active = excluded.optimistic_overlay_active,
        mutation_revision = instant_outbox.mutation_revision + 1,
        optimistic_effect_metadata_version = excluded.optimistic_effect_metadata_version,
        optimistic_effect_is_global = excluded.optimistic_effect_is_global,
        optimistic_effect_receipt_fingerprint = excluded.optimistic_effect_receipt_fingerprint,
        server_acceptance_payload_fingerprint = excluded.server_acceptance_payload_fingerprint,
        server_transaction_id = excluded.server_transaction_id,
        confirmation_source = excluded.confirmation_source,
        json = excluded.json
      """,
      [
        .text(durableMutation.id),
        .text(durableMutation.status.rawValue),
        .int(durableMutation.createdAt.milliseconds),
        .text(deliveryState.rawValue),
        .int(Int64(InstantOutboxDeliveryMetadata.currentVersion)),
        .int(Int64(InstantOutboxDeliveryMetadata.stepCount(in: durableMutation))),
        .int(Int64(encodedBody.utf8.count)),
        .text(try encode(durableMutation.compactedForMemory)),
        durableMutation.failureMessage.map(SQLiteBinding.text) ?? .null,
        failureAttributeRevision.map(SQLiteBinding.int) ?? .null,
        .int(acceptanceFingerprint == nil ? 0 : 1),
        .int(
          durableMutation.optimisticOverlayState == .removed
            && receiptFingerprint != nil ? 0 : 1
        ),
        .int(Int64(
          effectFootprint == nil ? 0 : InstantOptimisticEffectFootprint.currentVersion
        )),
        .int(effectFootprint?.isGlobal == true ? 1 : 0),
        receiptFingerprint.map(SQLiteBinding.text) ?? .null,
        acceptanceFingerprint.map(SQLiteBinding.text) ?? .null,
        (acceptanceFingerprint == nil
          ? durableMutation.serverTransactionID
          : existingServerTransactionID).map(SQLiteBinding.text) ?? .null,
        (acceptanceFingerprint == nil
          ? durableMutation.confirmationSource?.rawValue
          : existingConfirmationSource).map(SQLiteBinding.text) ?? .null,
        .text(InstantOutboxDeliveryClaimState.ready.rawValue),
        .text(encodedBody),
      ]
    )
    try replaceOutboxEffectEntitiesWithoutTransaction(
      mutationID: durableMutation.id,
      createdAtMilliseconds: durableMutation.createdAt.milliseconds,
      entityIDs: effectFootprint?.entityIDs ?? []
    )
    try replaceOutboxWriteKeysWithoutTransaction(for: durableMutation)
    try saveMutationLifecycleWithoutTransaction(
      durableMutation,
      lifecycleID: requestedLifecycleID,
      advancingFromMutationID: advancingFromMutationID
    )
  }

  private func lifecycleIDWithoutTransaction(
    for mutationID: String
  ) throws -> String? {
    try selectScalar(
      """
      SELECT lifecycle_id
      FROM instant_outbox_lifecycle_aliases
      WHERE mutation_id = ?
      LIMIT 1
      """,
      [.text(mutationID)]
    )
  }

  private func currentMutationIDWithoutTransaction(
    lifecycleID: String
  ) throws -> String? {
    try selectScalar(
      """
      SELECT current_mutation_id
      FROM instant_outbox_lifecycles
      WHERE lifecycle_id = ?
      LIMIT 1
      """,
      [.text(lifecycleID)]
    )
  }

  private func saveMutationLifecycleWithoutTransaction(
    _ mutation: PendingMutation,
    lifecycleID requestedLifecycleID: String? = nil,
    advancingFromMutationID: String? = nil
  ) throws {
    let existingLifecycleID = try lifecycleIDWithoutTransaction(for: mutation.id)
    // Ordinary mutations keep their existing row-addressed lifecycle behavior
    // and do not create permanent history tables. Durable lineage exists only
    // after an actual supersession chain starts.
    if let advancingFromMutationID {
      guard let lifecycleID = requestedLifecycleID,
        mutation.id != advancingFromMutationID,
        existingLifecycleID == nil
      else {
        throw persistenceError(
          operation: "advance outbox mutation lifecycle",
          message:
            "A supersession newcomer must have a distinct transaction id that has never belonged to a lifecycle."
        )
      }
      let terminal = try terminalLifecycleRecord(for: mutation)

      let currentMutationID = try currentMutationIDWithoutTransaction(
        lifecycleID: lifecycleID
      )
      if let currentMutationID {
        guard currentMutationID == advancingFromMutationID else {
          throw persistenceError(
            operation: "advance outbox mutation lifecycle",
            message:
              "Lifecycle '\(lifecycleID)' no longer names predecessor '\(advancingFromMutationID)' as its current mutation."
          )
        }
        try execute(
          """
          UPDATE instant_outbox_lifecycles
          SET current_mutation_id = ?, terminal_json = ?,
              terminal_optimistic_effect_receipt_fingerprint = ?,
              terminal_server_acceptance_payload_fingerprint = ?
          WHERE lifecycle_id = ? AND current_mutation_id = ?
          """,
          [
            .text(mutation.id),
            terminal.map { .text($0.json) } ?? .null,
            terminal?.optimisticEffectReceiptFingerprint.map(SQLiteBinding.text) ?? .null,
            terminal?.serverAcceptancePayloadFingerprint.map(SQLiteBinding.text) ?? .null,
            .text(lifecycleID),
            .text(advancingFromMutationID),
          ]
        )
        guard try selectInt64("SELECT changes()") == 1 else {
          throw persistenceError(
            operation: "advance outbox mutation lifecycle",
            message: "SQLite did not advance the lifecycle from its proven predecessor."
          )
        }
      } else {
        guard lifecycleID == advancingFromMutationID else {
          throw persistenceError(
            operation: "create outbox mutation lifecycle",
            message: "A new lifecycle must be rooted at the replaced predecessor id."
          )
        }
        try execute(
          """
          INSERT INTO instant_outbox_lifecycles (
            lifecycle_id, current_mutation_id, terminal_json,
            terminal_optimistic_effect_receipt_fingerprint,
            terminal_server_acceptance_payload_fingerprint
          ) VALUES (?, ?, ?, ?, ?)
          """,
          [
            .text(lifecycleID),
            .text(mutation.id),
            terminal.map { .text($0.json) } ?? .null,
            terminal?.optimisticEffectReceiptFingerprint.map(SQLiteBinding.text) ?? .null,
            terminal?.serverAcceptancePayloadFingerprint.map(SQLiteBinding.text) ?? .null,
          ]
        )
      }
      try saveMutationLifecycleAliasWithoutTransaction(
        mutationID: mutation.id,
        lifecycleID: lifecycleID
      )
      return
    }

    guard requestedLifecycleID == nil, let lifecycleID = existingLifecycleID else {
      // Ordinary mutations do not create history. Passing a lifecycle without
      // a proven predecessor transition is never allowed to move its survivor.
      if requestedLifecycleID != nil {
        throw persistenceError(
          operation: "save outbox mutation lifecycle",
          message: "Lifecycle advancement requires an exact predecessor id."
        )
      }
      return
    }
    guard try currentMutationIDWithoutTransaction(lifecycleID: lifecycleID) == mutation.id
    else {
      throw persistenceError(
        operation: "save outbox mutation lifecycle",
        message:
          "Refused to move lifecycle '\(lifecycleID)' backward through stale alias '\(mutation.id)'."
      )
    }
    let terminal = try terminalLifecycleRecord(for: mutation)
    try execute(
      """
      UPDATE instant_outbox_lifecycles
      SET terminal_json = ?,
          terminal_optimistic_effect_receipt_fingerprint = ?,
          terminal_server_acceptance_payload_fingerprint = ?
      WHERE lifecycle_id = ? AND current_mutation_id = ?
      """,
      [
        terminal.map { .text($0.json) } ?? .null,
        terminal?.optimisticEffectReceiptFingerprint.map(SQLiteBinding.text) ?? .null,
        terminal?.serverAcceptancePayloadFingerprint.map(SQLiteBinding.text) ?? .null,
        .text(lifecycleID),
        .text(mutation.id),
      ]
    )
  }

  private func saveMutationLifecycleAliasWithoutTransaction(
    mutationID: String,
    lifecycleID: String
  ) throws {
    try execute(
      """
      INSERT INTO instant_outbox_lifecycle_aliases (mutation_id, lifecycle_id)
      VALUES (?, ?)
      ON CONFLICT(mutation_id) DO NOTHING
      """,
      [.text(mutationID), .text(lifecycleID)]
    )
    guard try lifecycleIDWithoutTransaction(for: mutationID) == lifecycleID else {
      throw persistenceError(
        operation: "save outbox mutation lifecycle alias",
        message:
          "Transaction id '\(mutationID)' already belongs to another lifecycle and cannot be reassigned."
      )
    }
  }

  private func lifecycleEvent(
    for mutation: PendingMutation,
    hasServerAcceptance: Bool
  ) -> InstantMutationLifecycleEvent? {
    switch mutation.status {
    case .confirmed where hasServerAcceptance:
      .serverAccepted(mutation)
    case .failed:
      .failed(mutation)
    case .pending, .confirmed:
      nil
    }
  }

  private func terminalLifecycleRecord(
    for mutation: PendingMutation
  ) throws -> InstantTerminalLifecycleRecord? {
    guard let row = try loadOutboxBodyRowWithoutTransaction(id: mutation.id) else {
      return nil
    }
    let hasPreparedReceipt = try hasStoredPreparedOptimisticEffectReceipt(
      mutation,
      in: row
    )
    let lifecycle = compactedLifecycleForInspection(
      mutation,
      hasStoredReceiptFingerprint: hasPreparedReceipt
    )
    let hasServerAcceptance = try hasStoredServerAcceptance(mutation, in: row)
    guard lifecycleEvent(
      for: lifecycle,
      hasServerAcceptance: hasServerAcceptance
    ) != nil else { return nil }
    return InstantTerminalLifecycleRecord(
      json: try encode(lifecycle),
      optimisticEffectReceiptFingerprint: hasPreparedReceipt
        ? row.optimisticEffectReceiptFingerprint
        : nil,
      serverAcceptancePayloadFingerprint: hasServerAcceptance
        ? row.serverAcceptancePayloadFingerprint
        : nil
    )
  }

  private func saveQueryCacheEntryWithoutTransaction(
    _ entry: InstantCachedQuery,
    tableName: String = "instant_query_cache"
  ) throws {
    try execute(
      """
      INSERT OR REPLACE INTO \(tableName) (cache_key, query_id, json, updated_at_ms)
      VALUES (?, ?, ?, ?)
      """,
      [
        .text(entry.cacheKey),
        .text(entry.queryID),
        .text(try encode(entry)),
        .int(entry.updatedAt.milliseconds),
      ]
    )
  }

  private func saveLiveQueryResultWithoutTransaction(
    _ result: InstantPersistedLiveQueryResult
  ) throws {
    try invalidateDeclaredRelationStorageMarkerIfNeeded(
      forAttributeIDs: Set(result.triples.map(\.attributeID))
    )
    let attributes = try loadAttributesWithoutTransaction(tracesStartupCollection: false)
    var result = result
    result.triples = InstantLiveQueryNestedLimit.limitedTriples(
      queryKey: result.key,
      triples: Array(result.triples),
      attributes: attributes
    )
    let nextOwnership = try Set(
      result.triples.map { triple in
        LiveQueryOwnershipIdentity(
          entityID: triple.entityID,
          attributeID: triple.attributeID,
          valueJSON: try encode(triple.value)
        )
      }
    )
    let previousOwnership = try liveQueryOwnershipWithoutTransaction(queryKey: result.key)
    try execute(
      """
      INSERT INTO instant_live_query_results
        (query_key, triple_count, updated_at_ms, json)
      VALUES (?, ?, ?, ?)
      ON CONFLICT(query_key) DO UPDATE SET
        triple_count = excluded.triple_count,
        updated_at_ms = excluded.updated_at_ms,
        json = excluded.json
      """,
      [
        .text(result.key),
        .int(Int64(result.triples.count)),
        .int(result.updatedAt.milliseconds),
        .text(try encode(result)),
      ]
    )
    let removedOwnership = previousOwnership.subtracting(nextOwnership).sorted(
      by: Self.liveQueryOwnershipOrder
    )
    try executeRepeated(
      """
      DELETE FROM instant_live_query_triples
      WHERE query_key = ?
        AND entity_id = ?
        AND attribute_id = ?
        AND value_json = ?
      """,
      bindings: removedOwnership.map { identity in
        [
          .text(result.key),
          .text(identity.entityID),
          .text(identity.attributeID),
          .text(identity.valueJSON),
        ]
      }
    )
    let insertedOwnership = nextOwnership.subtracting(previousOwnership).sorted(
      by: Self.liveQueryOwnershipOrder
    )
    try executeRepeated(
      """
      INSERT INTO instant_live_query_triples
        (query_key, entity_id, attribute_id, value_json)
      VALUES (?, ?, ?, ?)
      """,
      bindings: insertedOwnership.map { identity in
        [
          .text(result.key),
          .text(identity.entityID),
          .text(identity.attributeID),
          .text(identity.valueJSON),
        ]
      }
    )
  }

  private func liveQueryOwnershipWithoutTransaction(
    queryKey: String
  ) throws -> Set<LiveQueryOwnershipIdentity> {
    var statement: OpaquePointer?
    try prepare(
      """
      SELECT entity_id, attribute_id, value_json
      FROM instant_live_query_triples
      WHERE query_key = ?
      """,
      statement: &statement
    )
    defer { sqlite3_finalize(statement) }
    try bind([.text(queryKey)], to: statement)

    var ownership: Set<LiveQueryOwnershipIdentity> = []
    while true {
      let code = sqlite3_step(statement)
      if code == SQLITE_DONE { return ownership }
      guard code == SQLITE_ROW else {
        throw persistenceError(
          operation: "read live-query ownership",
          message: lastErrorMessage()
        )
      }
      guard
        let entityID = sqlite3_column_text(statement, 0),
        let attributeID = sqlite3_column_text(statement, 1),
        let valueJSON = sqlite3_column_text(statement, 2)
      else {
        throw persistenceError(
          operation: "read live-query ownership",
          message: "SQLite returned a NULL live-query ownership column."
        )
      }
      ownership.insert(
        LiveQueryOwnershipIdentity(
          entityID: String(cString: entityID),
          attributeID: String(cString: attributeID),
          valueJSON: String(cString: valueJSON)
        )
      )
    }
  }

  private static func liveQueryOwnershipOrder(
    _ lhs: LiveQueryOwnershipIdentity,
    _ rhs: LiveQueryOwnershipIdentity
  ) -> Bool {
    (lhs.entityID, lhs.attributeID, lhs.valueJSON)
      < (rhs.entityID, rhs.attributeID, rhs.valueJSON)
  }

  private func saveMetadataValueWithoutTransaction(
    _ value: String,
    key: String,
    updatedAt: InstantTimestamp
  ) throws {
    try execute(
      """
      INSERT OR REPLACE INTO instant_sync_metadata (key, value, updated_at_ms)
      VALUES (?, ?, ?)
      """,
      [
        .text(key),
        .text(value),
        .int(updatedAt.milliseconds),
      ]
    )
  }

  private func deleteMetadataValueWithoutTransaction(key: String) throws {
    try execute(
      "DELETE FROM instant_sync_metadata WHERE key = ?",
      [.text(key)]
    )
  }

  private func loadMetadataRevisionWithoutTransaction(_ key: String) throws -> Int64 {
    let value: String? = try selectScalar(
      "SELECT value FROM instant_sync_metadata WHERE key = ? LIMIT 1",
      [.text(key)]
    )
    return value.flatMap(Int64.init) ?? 0
  }

  private func bumpMetadataRevisionWithoutTransaction(_ key: String) throws -> Int64 {
    let revision = try loadMetadataRevisionWithoutTransaction(key) + 1
    try execute(
      """
      INSERT OR REPLACE INTO instant_sync_metadata (key, value, updated_at_ms)
      VALUES (?, ?, ?)
      """,
      [
        .text(key),
        .text(String(revision)),
        .int(Self.nowMilliseconds()),
      ]
    )
    return revision
  }

  private func nextStreamChunkIndexWithoutTransaction(appID: String, streamID: String) throws
    -> Int64
  {
    let value: String? = try selectScalar(
      """
      SELECT CAST(COALESCE(MAX(chunk_index), -1) + 1 AS TEXT)
      FROM instant_stream_chunks
      WHERE app_id = ? AND stream_id = ?
      """,
      [.text(appID), .text(streamID)]
    )
    return value.flatMap(Int64.init) ?? 0
  }

  private func streamMetadataWithoutTransaction(
    appID: String,
    streamID: String
  ) throws -> InstantStreamMetadata? {
    let rows: [InstantStreamMetadata] = try selectJSON(
      """
      SELECT json FROM instant_streams
      WHERE app_id = ? AND stream_id = ?
      LIMIT 1
      """,
      [.text(appID), .text(streamID)]
    )
    return rows.first
  }

  private func streamMetadataWithoutTransaction(
    appID: String,
    clientID: String
  ) throws -> InstantStreamMetadata? {
    let rows: [InstantStreamMetadata] = try selectJSON(
      """
      SELECT json FROM instant_streams
      WHERE app_id = ? AND client_id = ?
      LIMIT 1
      """,
      [.text(appID), .text(clientID)]
    )
    return rows.first
  }

  private func insertStreamMetadataWithoutTransaction(_ metadata: InstantStreamMetadata) throws {
    try execute(
      """
      INSERT INTO instant_streams
        (app_id, stream_id, client_id, user_id, done, size, abort_reason,
         created_at_ms, updated_at_ms, json)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      """,
      [
        .text(metadata.appID),
        .text(metadata.id),
        .text(metadata.clientID),
        .text(metadata.userID),
        .int(metadata.done ? Int64(1) : Int64(0)),
        metadata.size.map { .int($0) } ?? .null,
        metadata.abortReason.map { .text($0) } ?? .null,
        .int(metadata.createdAt.milliseconds),
        .int(metadata.updatedAt.milliseconds),
        .text(try encode(metadata)),
      ]
    )
  }

  private func saveStreamMetadataWithoutTransaction(_ metadata: InstantStreamMetadata) throws {
    try execute(
      """
      INSERT INTO instant_streams
        (app_id, stream_id, client_id, user_id, done, size, abort_reason,
         created_at_ms, updated_at_ms, json)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(app_id, stream_id) DO UPDATE SET
        client_id = excluded.client_id,
        user_id = excluded.user_id,
        done = excluded.done,
        size = excluded.size,
        abort_reason = excluded.abort_reason,
        created_at_ms = excluded.created_at_ms,
        updated_at_ms = excluded.updated_at_ms,
        json = excluded.json
      """,
      [
        .text(metadata.appID),
        .text(metadata.id),
        .text(metadata.clientID),
        .text(metadata.userID),
        .int(metadata.done ? Int64(1) : Int64(0)),
        metadata.size.map { .int($0) } ?? .null,
        metadata.abortReason.map { .text($0) } ?? .null,
        .int(metadata.createdAt.milliseconds),
        .int(metadata.updatedAt.milliseconds),
        .text(try encode(metadata)),
      ]
    )
  }

  private func streamContentSizeWithoutTransaction(appID: String, streamID: String) throws -> Int64
  {
    let value: String? = try selectScalar(
      """
      SELECT CAST(COALESCE(SUM(byte_count), 0) AS TEXT)
      FROM instant_stream_content_chunks
      WHERE app_id = ? AND stream_id = ?
      """,
      [.text(appID), .text(streamID)]
    )
    return value.flatMap(Int64.init) ?? 0
  }

  private func streamContentReadWithoutTransaction(
    metadata: InstantStreamMetadata,
    byteOffset: Int64
  ) throws -> InstantStreamContentRead {
    let currentSize = try streamContentSizeWithoutTransaction(
      appID: metadata.appID,
      streamID: metadata.id
    )
    guard byteOffset <= currentSize else {
      throw streamValidationError(
        operation: "read stream content",
        localID: metadata.id,
        message:
          "Stream '\(metadata.id)' contains \(currentSize) bytes, so byte offset \(byteOffset) is out of range.",
        recovery: "Read from an offset less than or equal to the stream byte count."
      )
    }

    let chunks: [InstantStreamContentChunk] = try selectJSON(
      """
      SELECT json FROM instant_stream_content_chunks
      WHERE app_id = ? AND stream_id = ? AND offset + byte_count > ?
      ORDER BY offset, chunk_id
      """,
      [.text(metadata.appID), .text(metadata.id), .int(byteOffset)]
    )

    var data = Data()
    for chunk in chunks {
      data.append(contentsOf: chunk.content.utf8)
    }
    if let firstChunk = chunks.first {
      let droppedByteCount = byteOffset - firstChunk.offset
      if droppedByteCount > 0 {
        data.removeFirst(Int(droppedByteCount))
      }
    }
    guard let content = String(data: data, encoding: .utf8) else {
      throw streamValidationError(
        operation: "read stream content",
        localID: metadata.id,
        message:
          "Stream '\(metadata.id)' cannot be decoded from byte offset \(byteOffset) as UTF-8.",
        recovery: "Resume from a UTF-8 character boundary when using Swift string streams."
      )
    }
    return InstantStreamContentRead(
      metadata: metadata,
      byteOffset: byteOffset,
      byteCount: Int64(data.count),
      content: content,
      done: metadata.done,
      abortReason: metadata.abortReason
    )
  }

  private func saveShareWithoutTransaction(_ share: InstantShare) throws {
    try execute(
      """
      INSERT OR REPLACE INTO instant_shares
        (app_id, share_id, root_namespace, root_id, owner_user_id, token,
         created_at_ms, updated_at_ms, revoked_at_ms, json)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      """,
      [
        .text(share.appID),
        .text(share.id),
        .text(share.rootNamespace),
        .text(share.rootID),
        .text(share.ownerUserID),
        .text(share.token),
        .int(share.createdAt.milliseconds),
        .int(share.updatedAt.milliseconds),
        share.revokedAt.map { .int($0.milliseconds) } ?? .null,
        .text(try encode(share)),
      ]
    )
  }

  private func saveShareMembershipWithoutTransaction(_ membership: InstantShareMembership) throws {
    try execute(
      """
      INSERT OR REPLACE INTO instant_share_memberships
        (app_id, share_id, user_id, role, accepted_at_ms, revoked_at_ms, json)
      VALUES (?, ?, ?, ?, ?, ?, ?)
      """,
      [
        .text(membership.appID),
        .text(membership.shareID),
        .text(membership.userID),
        .text(membership.role.rawValue),
        .int(membership.acceptedAt.milliseconds),
        membership.revokedAt.map { .int($0.milliseconds) } ?? .null,
        .text(try encode(membership)),
      ]
    )
  }

  private func shareWithoutTransaction(appID: String, shareID: String) throws -> InstantShare? {
    let shares: [InstantShare] = try selectJSON(
      """
      SELECT json FROM instant_shares
      WHERE app_id = ? AND share_id = ?
      LIMIT 1
      """,
      [.text(appID), .text(shareID)]
    )
    return shares.first
  }

  private func shareWithoutTransaction(appID: String, token: String) throws -> InstantShare? {
    let shares: [InstantShare] = try selectJSON(
      """
      SELECT json FROM instant_shares
      WHERE app_id = ? AND token = ?
      LIMIT 1
      """,
      [.text(appID), .text(token)]
    )
    return shares.first
  }

  private func shareMembershipWithoutTransaction(
    appID: String,
    shareID: String,
    userID: String
  ) throws -> InstantShareMembership? {
    let memberships: [InstantShareMembership] = try selectJSON(
      """
      SELECT json FROM instant_share_memberships
      WHERE app_id = ? AND share_id = ? AND user_id = ?
      LIMIT 1
      """,
      [.text(appID), .text(shareID), .text(userID)]
    )
    return memberships.first
  }

  private func shareMembershipsWithoutTransaction(
    appID: String,
    shareID: String,
    activeOnly: Bool
  ) throws -> [InstantShareMembership] {
    var sql =
      """
      SELECT json FROM instant_share_memberships
      WHERE app_id = ? AND share_id = ?
      """
    if activeOnly {
      sql.append("\nAND revoked_at_ms IS NULL")
    }
    sql.append("\nORDER BY accepted_at_ms, user_id")
    return try selectJSON(sql, [.text(appID), .text(shareID)])
  }

  private func shareSnapshotWithoutTransaction(
    appID: String,
    shareID: String,
    activeMembershipsOnly: Bool = false
  ) throws -> InstantShareSnapshot {
    guard let share = try shareWithoutTransaction(appID: appID, shareID: shareID) else {
      throw persistenceError(operation: "read share", message: "Share '\(shareID)' disappeared.")
    }
    let memberships = try shareMembershipsWithoutTransaction(
      appID: appID,
      shareID: shareID,
      activeOnly: activeMembershipsOnly
    )
    return InstantShareSnapshot(share: share, memberships: memberships)
  }

  private func execute(_ sql: String, _ bindings: [SQLiteBinding] = []) throws {
    var statement: OpaquePointer?
    try prepare(sql, statement: &statement)
    defer { sqlite3_finalize(statement) }
    try bind(bindings, to: statement)
    let code = sqlite3_step(statement)
    guard code == SQLITE_DONE || code == SQLITE_ROW else {
      throw persistenceError(operation: "execute SQL", message: lastErrorMessage())
    }
  }

  private func executeRepeated(
    _ sql: String,
    bindings rows: [[SQLiteBinding]]
  ) throws {
    guard !rows.isEmpty else { return }
    var statement: OpaquePointer?
    try prepare(sql, statement: &statement)
    defer { sqlite3_finalize(statement) }

    for bindings in rows {
      guard sqlite3_reset(statement) == SQLITE_OK else {
        throw persistenceError(operation: "reset SQL", message: lastErrorMessage())
      }
      guard sqlite3_clear_bindings(statement) == SQLITE_OK else {
        throw persistenceError(operation: "clear SQL bindings", message: lastErrorMessage())
      }
      try bind(bindings, to: statement)
      guard sqlite3_step(statement) == SQLITE_DONE else {
        throw persistenceError(operation: "execute repeated SQL", message: lastErrorMessage())
      }
    }
  }

  private func prepare(_ sql: String, statement: inout OpaquePointer?) throws {
    try ensureOpenConnection()
    guard sqlite3_prepare_v2(connection.raw, sql, -1, &statement, nil) == SQLITE_OK else {
      throw persistenceError(operation: "prepare SQL", message: lastErrorMessage())
    }
  }

  private func ensureOpenConnection() throws {
    guard connection.raw == nil else { return }
    try reopenConnection()
  }

  private func reopenConnection() throws {
    sqlite3_close(connection.raw)
    connection.raw = nil
    connection.raw = try Self.openRawConnection(fileURL: fileURL)
  }

  private func bind(_ bindings: [SQLiteBinding], to statement: OpaquePointer?) throws {
    for (offset, binding) in bindings.enumerated() {
      let index = Int32(offset + 1)
      let result: Int32
      switch binding {
      case let .int(value):
        result = sqlite3_bind_int64(statement, index, sqlite3_int64(value))
      case let .text(value):
        result = value.withCString {
          sqlite3_bind_text(statement, index, $0, -1, sqliteTransient)
        }
      case .null:
        result = sqlite3_bind_null(statement, index)
      }
      guard result == SQLITE_OK else {
        throw persistenceError(operation: "bind SQL", message: lastErrorMessage())
      }
    }
  }

  private func encode<Value: Encodable>(_ value: Value) throws -> String {
    let data = try encoder.encode(value)
    guard let string = String(data: data, encoding: .utf8) else {
      throw persistenceError(operation: "encode JSON", message: "Encoded JSON was not UTF-8.")
    }
    return string
  }

  private func lastErrorMessage() -> String {
    connection.raw.flatMap { sqlite3_errmsg($0) }.map { String(cString: $0) }
      ?? "Unknown SQLite error."
  }

  private func streamValidationError(
    operation: String,
    localID: String,
    message: String,
    recovery: String
  ) -> InstantError {
    InstantError(
      code: .validationFailed,
      operation: operation,
      localID: localID,
      message: message,
      recovery: recovery
    )
  }

  private func persistenceError(operation: String, message: String) -> InstantError {
    InstantError(
      code: .persistenceFailed,
      operation: operation,
      message: message,
      recovery: "Inspect the local SQLite cache at \(fileURL.path), then retry the command."
    )
  }

  private static func nowMilliseconds() -> Int64 {
    Int64((Date().timeIntervalSince1970 * 1000).rounded())
  }

  private var localFilesRootURL: URL {
    fileURL.deletingLastPathComponent().appendingPathComponent("files", isDirectory: true)
  }

  private func localCacheFileSize() -> Int64 {
    [fileURL.path, fileURL.path + "-wal", fileURL.path + "-shm"].reduce(0) { size, path in
      let attributes = try? FileManager.default.attributesOfItem(atPath: path)
      let fileSize = (attributes?[.size] as? NSNumber)?.int64Value ?? 0
      return size + fileSize
    }
  }

  private func sanitizedFileComponent(_ value: String) -> String {
    let sanitized = value.map { character in
      character == "/" || character == ":" || character == "\u{0}" ? "_" : character
    }
    let string = String(sanitized).trimmingCharacters(in: .whitespacesAndNewlines)
    return string.isEmpty || string == "." || string == ".." ? "file" : string
  }

  private static let storeRevisionKey = "store_revision"
  private static let attributeRevisionKey = "attribute_revision"
  private static let outboxRevisionKey = "outbox_revision"
  private static let queryResultRevisionKey = "query_result_revision"
  private static let declaredRelationStorageReconciliationMarkerKey =
    "instant.internal.declared-relation-storage-reconciliation.v1"
}

private enum SQLiteBinding: Sendable {
  case int(Int64)
  case text(String)
  case null
}

private struct DeclaredRelationStorageReconciliationMarker: Codable, Equatable {
  var retainedAttributes: [InstantAttribute]
  var declaredAttributes: [InstantAttribute]
  var obsoleteAttributeIDs: [String]
}

private struct QueryCacheStorageRow: Sendable {
  var cacheKey: String
  var json: String
  var updatedAtMilliseconds: Int64

  var byteCount: Int {
    json.utf8.count
  }
}

extension InstantError {
  fileprivate var isSQLiteBusy: Bool {
    let lowercasedMessage = message.lowercased()
    return lowercasedMessage.contains("database is locked")
      || lowercasedMessage.contains("database schema is locked")
      || lowercasedMessage.contains("database table is locked")
  }
}

// SAFETY: SQLite's raw pointer is confined to the `SQLitePersistenceStore` actor.
// The wrapper is immutable outside that actor and only closes the connection when released.
private final class SQLiteConnection: @unchecked Sendable {
  var raw: OpaquePointer?

  init(_ raw: OpaquePointer?) {
    self.raw = raw
  }

  deinit {
    sqlite3_close(raw)
  }
}

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
