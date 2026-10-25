// History:
// - 2026-10-14: a retained mutation with no SQLite-owned preparation receipt moves, whole, into
//   instant_outbox_quarantined at runtime bootstrap instead of refusing every live connection (#696).
// - 2026-10-15: live-query ownership rows name their result by an integer query_id instead of repeating the query's
//   whole key, and a store in 0011's layout converts once at bootstrap (#704, ADR 0020).
// - 2026-10-23: the session prune unloads a closed query's result into instant_unloaded_live_query_results instead of
//   deleting it, and the query's next subscription loads it back, as upstream PersistedObject.unloadKey keeps a closed
//   query's stored copy (#1006).
// - 2026-10-24: a closed result's reload commits the row its caller read before the operation gate, reading it again
//   when a newer one replaced it, and moves the stored JSON inside SQLite instead of encoding it again (#1131).
// - 2026-10-24: the reload moves the row back first and then gives it its facts a bounded chunk at a time, each chunk
//   its own transaction, stopping once a server answer replaced the row (#1131).
// - 2026-10-23: an uploaded file's record keeps no copy of its bytes (saveUploadedFileRecord), a record without a copy
//   is not downloaded to reads and the snapshot, and an evicted copy's record stays (forgetStoredFileCopy) (#959).
// - 2026-10-23: metadata rows upsert in place, and an acknowledgement leaves a write's unchanged key rows alone: both
//   rewrote unchanged rows to new pages on every write (#1007).
// - 2026-10-23: a server-apply commit times its parts (validation, facts, outbox, results, bookkeeping, the SQLite
//   COMMIT) for the gate-held event (#932).
// - 2026-10-23: the resident-patch page reads only the staged rows among the ids it is given (#932).
// - 2026-10-23: a server apply's body page checks only its own rows against the outbox; it re-checked the whole plan
//   on every 51-row page (~2R^2/50 row checks per apply, each walking a body's overflow pages). Extending the plan
//   and its commit still check every row (#932).
// - 2026-10-23: the reduction context names, for each shadowed entity the store does not show, the surviving write
//   that deletes it last (#932).
// - 2026-10-23: a live-query result's save splits into preparing (nested limits, ownership difference, JSON when
//   written) and applying, so a server apply prepares its results before the operation gate (#932).
// - 2026-10-23: a server-apply commit updates its changed outbox rows from one join instead of fifteen correlated
//   lookups each, the staging table keeps its bodies after its small columns, and the commit's closure re-plan reads
//   no body sizes (#932).
// - 2026-10-23: a partial index over the lookup attributes, ensured at bootstrap, and a read-only connection beside the
//   writer, so a local read finds what this device keeps on disk without waiting for writes (#1006).
// - 2026-10-23: the storage snapshot reports the file's free pages, and `vacuum()` gives them back for compaction, its
//   dirty pages bounded; new caches stay in auto_vacuum NONE, whose writes cost 3-6% less than INCREMENTAL's (#1015).
// - 2026-10-23: the outbox drops instant_outbox_delivery_window_idx, which no statement used, and an acknowledgement
//   sets the overlay flag only when it changes: each wrote index pages on every write for nothing (#1007).
// - 2026-10-23: a server apply's staging keeps no copy of each body as planned: both passes and the stage read the
//   outbox's body, whose every rewrite bumps the revision each page checks against the plan (#932, the disk map's F1a).
// - 2026-10-23: the statement cache keeps 256 statements instead of 64, room for a live write's whole cycle, which
//   prepared every statement again on every write; a reuse hashes its SQL once instead of five times (#1007).
// - 2026-10-23: a fact's value text and its own text are written by InstantStoredJSON, the value once, as JSONEncoder
//   writes them (#1007).
// - 2026-10-23: a save and an acknowledgement fingerprint a write's optimistic effect once each; the save asked whether
//   there was one before computing the one it stores, and the acknowledgement computed it for two checks (#1007).
// - 2026-10-23: a refused write's rollback advances the memory cache to the revision it commits, as a server apply and a
//   local write do; it dropped the cache, and the next read rebuilt the whole store from SQLite (#1035).
// - 2026-10-23: the live-query prune chooses each batch from the stored results' rows and the facts they hold, then
//   drops it against the hot store's facts of only those entities, deleting a dropped entity's rows by its id; each
//   batch built a dictionary of every fact and diffed the whole store into SQLite (#654).
// - 2026-10-24: the delivery pump's candidate read and continuation check search their two branches by index
//   (instant_outbox_delivery_candidate_idx, migration 0029) instead of visiting every ready row, refused writes and
//   their bodies' overflow pages included, after every write and acknowledgement (#1108).
// - 2026-10-24: the delivery's unknown-overlay check seeks the overlay flag (= 1) instead of scanning the table, and the
//   supersession tail read finds the newest id in a covering index before it reads that one row (#1108, #1114).
// - 2026-10-24: the writer checkpoints every 4,000 frames of the log instead of Apple's 1,000: three F_FULLFSYNCs per
//   checkpoint, one every 16 writes, made 1,039 full syncs an hour of recording (#1118).
// - 2026-10-25: a write's key rows and effect entities live in WITHOUT ROWID tables, and one delivery index replaces
//   the deadline and candidate indexes: two b-trees fewer on every save and echo, one fewer on every claim (#1115).
// - 2026-10-25: each fact is stored once: the fact table is keyed by the fact itself (WITHOUT ROWID) and its json is
//   computed when read (127.1 -> 40.7 MB on a copy of a phone's store); a re-saved fact is upserted where it is, and
//   the migration passes over facts walk a snapshot of their keys (#1121, #1120).

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

/// A persisted live-query result as an open-time pass reads it (#436): decoded, or over the pass's row bound, which the
/// pass drops so the store still opens and the query refetches the result.
private enum InstantBoundedLiveQueryResultRow {
  case decoded(InstantPersistedLiveQueryResult)
  case oversized(queryKey: String, byteCount: Int64)
}

/// What a batch of live-query result replacements retracts (#431): the retractions, and the single-value slots among
/// them the server cleared, which only a pending write of the slot itself protects.
struct InstantLiveQueryReplacementRetractions: Sendable {
  var operations: [InstantTripleOperation]
  var clearedSlots: Set<InstantVisibleWriteKey>
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

private struct InstantApplicationMigrationOutboxRow {
  var mutation: PendingMutation
  var deliveryStarted: Bool
  var confirmationProven: Bool
  var optimisticOverlayActive: Bool
  var optimisticEffectReceiptFingerprint: String?
  var serverAcceptancePayloadFingerprint: String?
}

private struct InstantApplicationMigrationTripleRow {
  /// The row's place in the pass's snapshot of keys (#1121): the fact table is keyed by the fact itself, so a pass
  /// walks a snapshot taken before it changes anything, and a fact whose value it rewrites is not met again.
  var rowID: Int64
  /// The fact's key as stored: the row a pass updates or removes.
  var entityID: String
  var attributeID: String
  var valueJSON: String
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
  /// The results that left the stored results: deleted, or unloaded and kept (``unloadedQueryKeys``).
  public var removedQueryKeys: [String]
  public var remainingQueryKeys: [String]
  public var removedOrphanedTripleCount: Int
  public var remainingEntryCount: Int
  public var remainingTripleCount: Int
  /// The removed results of closed queries kept for their next subscription (#1006), a subset of ``removedQueryKeys``.
  public var unloadedQueryKeys: [String]

  public init(
    removedQueryKeys: [String],
    remainingQueryKeys: [String],
    removedOrphanedTripleCount: Int,
    remainingEntryCount: Int,
    remainingTripleCount: Int,
    unloadedQueryKeys: [String] = []
  ) {
    self.removedQueryKeys = removedQueryKeys
    self.remainingQueryKeys = remainingQueryKeys
    self.removedOrphanedTripleCount = removedOrphanedTripleCount
    self.remainingEntryCount = remainingEntryCount
    self.remainingTripleCount = remainingTripleCount
    self.unloadedQueryKeys = unloadedQueryKeys
  }
}

/// A closed query's stored result as one read found it (#1131), with what names its row: a reopened query reads it
/// before it takes the operation gate, and the reload under the gate commits it only while that row is still the one
/// stored under its key.
struct InstantUnloadedLiveQueryResultRead: Sendable {
  var result: InstantPersistedLiveQueryResult
  var rowTripleCount: Int
  var rowUpdatedAtMilliseconds: Int64
}

/// Where a closed result's reload stands once its row is back among the stored results (#1131).
struct InstantUnloadedLiveQueryResultReloadStart: Sendable {
  /// The result as it is stored now: the one read before the operation gate, or a newer one that replaced it.
  var result: InstantPersistedLiveQueryResult
  /// What names the row the reload moved back, for each chunk to check it still holds it.
  var rowTripleCount: Int
  var rowUpdatedAtMilliseconds: Int64
  /// The result's facts it keeps no ownership of: those its query's nested limits leave out, none for most results.
  var unownedFacts: Set<InstantLiveTripleIdentity>
  /// Whether the row read before the operation gate had been replaced, so the reload read it again.
  var readAgain: Bool
}

/// One chunk of a closed result's reload (#1131).
struct InstantUnloadedLiveQueryResultChunkReload: Sendable {
  /// The facts of the chunk's entities that had left the store, for the store in memory; deferred payloads stay in
  /// SQLite.
  var restoredTriples: [InstantTriple]
  /// Entities written back to SQLite from the result.
  var restoredFromResultEntityCount: Int
  /// Entities SQLite still held that the store in memory did not.
  var restoredFromSQLiteEntityCount: Int
  /// Whether SQLite's facts changed, which moved the store revision.
  var storeChanged: Bool
  var storeRevision: Int64
  var attributeRevision: Int64
}

struct InstantLiveQueryResultPruningApplication: Sendable {
  var result: InstantLiveQueryResultPruningResult
  var state: InstantPersistenceState
  /// Rows the policy removes that a bounded batch left for the next one (#303, item 6).
  var hasMoreToRemove = false
  /// Facts a removed row released that the whole-entity rule kept, because their entity still had a fact no removed
  /// row released. A later batch that releases the rest of the entity removes them together.
  var retainedReleasedIdentities: Set<InstantLiveTripleIdentity> = []
}

/// The results a live-query prune batch removes and the facts they hold, chosen from the stored results alone (#654).
struct InstantLiveQueryResultPruneBatch: Sendable {
  /// The results the batch removes, in the policy's order.
  var removedQueryKeys: [String]
  /// Whether the policy removes more results than this batch holds (#303, item 6).
  var hasMoreToRemove: Bool
  /// The facts the removed results hold, and the ones an earlier batch carried.
  var releasedIdentities: Set<InstantLiveTripleIdentity>
  /// Of ``removedQueryKeys``, the closed queries' results kept for their next subscription (#1006).
  fileprivate var unloadingQueryKeys: Set<String>
  /// Of ``removedQueryKeys``, those whose result could not be read: their rows stay, as before #654.
  fileprivate var unreadableQueryKeys: Set<String>
  /// The stored results that stay, oldest first, then the ones a later batch removes.
  fileprivate var remainingRows: [LiveQueryResultStorageRow]
  /// The revisions the batch was chosen at; it applies only at them.
  fileprivate var revisions: LiveQueryResultPruneRevisions

  /// The entities whose facts the batch may drop: the only part of the store it reads.
  var releasedEntityIDs: Set<String> {
    Set(releasedIdentities.lazy.map(\.entityID))
  }

  /// The result of a prune that removes nothing: every stored result stays.
  var resultRemovingNothing: InstantLiveQueryResultPruningResult {
    InstantLiveQueryResultPruningResult(
      removedQueryKeys: [],
      remainingQueryKeys: remainingRows.map(\.queryKey),
      removedOrphanedTripleCount: 0,
      remainingEntryCount: remainingRows.count,
      remainingTripleCount: remainingRows.reduce(0) { $0 + $1.tripleCount }
    )
  }

  /// What a batch that removes nothing changed: nothing.
  var applicationRemovingNothing: InstantLiveQueryResultPruneBatchApplication {
    InstantLiveQueryResultPruneBatchApplication(
      result: resultRemovingNothing,
      removedFacts: [],
      storeRevision: revisions.store,
      attributeRevision: revisions.attribute,
      queryResultRevision: revisions.queryResult,
      hasMoreToRemove: false,
      retainedReleasedIdentities: []
    )
  }
}

/// What a live-query prune batch removed (#654).
struct InstantLiveQueryResultPruneBatchApplication: Sendable {
  var result: InstantLiveQueryResultPruningResult
  /// The store's facts the batch removed, whole entities only: the hot store retracts exactly these.
  var removedFacts: [InstantTriple]
  var storeRevision: Int64
  var attributeRevision: Int64
  var queryResultRevision: Int64
  /// Rows the policy removes that the batch left for the next one (#303, item 6).
  var hasMoreToRemove: Bool
  /// Facts a removed row released that the whole-entity rule kept, because their entity still had a fact no removed
  /// row released. A later batch that releases the rest of the entity removes them together.
  var retainedReleasedIdentities: Set<InstantLiveTripleIdentity>

  var removedEntityIDs: Set<String> {
    Set(removedFacts.lazy.map(\.entityID))
  }
}

/// The revisions a live-query prune batch is chosen at (#654).
private struct LiveQueryResultPruneRevisions: Hashable, Sendable {
  var store: Int64
  var attribute: Int64
  var outbox: Int64
  var queryResult: Int64
}

private struct LiveQueryResultStorageRow: Sendable {
  var queryKey: String
  var updatedAtMilliseconds: Int64
  var tripleCount: Int
}

// #590 (2026-10-23): the queue keeps its own user-initiated QoS. A caller waits for its batches on a dispatch group from
// a cooperative thread; with no QoS of its own, the batches inherited that thread's QoS, and the whole test bundle
// stopped with every cooperative thread waiting on a group whose work never got a thread.
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

/// The one exact durable outbox tail, read inside `transact`'s ``SQLitePersistenceStore/run(_:)`` turn (#403).
struct InstantOutboxImmediateTailRead: Sendable {
  var load: InstantOutboxImmediateTailLoad
  /// A tail the read found undecodable or oversized. Pass it to
  /// ``SQLitePersistenceStore/quarantineInvalidImmediateSupersessionTail(_:expectedStoreRevision:expectedOutboxRevision:)``
  /// before preparing the write; `load.matchesRevisions` is `false` until it has.
  var invalidTail: InstantOutboxInvalidImmediateTail?
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

struct InstantOutboxBodyRow: Sendable {
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

enum InstantOutboxInvalidImmediateTail: Sendable {
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

/// Why a server apply keeps the whole-component rebase instead of dropping the facts it cannot change (#296).
enum InstantServerApplyReductionIneligibility: String, Sendable {
  case revisionChanged
  case failedOverlay
  case unscopedOverlay
  case nonPrefixWatermark
  case tooManyBodies
  case unsupportedOperation
  /// A fact on a shadowed slot that no surviving write inserts does not hold in the store.
  case changesShadowedFact
  /// A surviving write merges into the slot, or its latest writer's value is not what the store shows.
  case shadowedSlotNotReplaced
  /// The first writer's receipt cannot name the base value beneath it (it deletes the entity, or restores several
  /// values), or restores none while earlier pending writes touch the entity.
  case unprovenBeforeImage
  /// A surviving write inserts this link from the other side, which leaves no write key on this slot.
  case reverseLinkWriter
  case retractsShadowedFact
  case linksToShadowedEntity
  /// A fact on an entity a surviving write deletes that the reduction cannot place: a link, a many-valued slot, an
  /// entity the store still shows, or a receipt that does not name the slot's base (#932).
  case deletedEntityFact
}

enum InstantServerApplyReduction: Sendable {
  /// The operations that can change the base; every other one already holds beneath the pending writes. Where the
  /// server changed a slot beneath its pending writers, `receiptPatches` names each slot's first surviving writer and
  /// the server fact that becomes its before-image, which is the only receipt the full rebase would change there.
  case reduced([InstantTripleOperation], receiptPatches: [String: [InstantTriple]] = [:])
  /// The first fact that needs the whole-component rebase, when one fact decided it.
  case declined(InstantServerApplyReductionIneligibility, fact: InstantTriple? = nil)
}

/// Refused writes a reduced server apply removes itself (#296), and what their removal changes.
struct InstantServerApplyFailureSplice: Sendable {
  struct ReceiptRebase: Sendable {
    /// The refused write's before-image facts on slots this write replaces.
    var baseFacts: [InstantTriple] = []
    /// Slots the refused write set from empty.
    var absentSlots: Set<InstantVisibleWriteKey> = []
  }

  /// What the store goes back to where no surviving write replaces a refused write's change.
  var storeOperations: [InstantTripleOperation] = []
  /// The next surviving writer of each slot a refused write changed, with the before-image its receipt takes over.
  var receiptRebases: [String: ReceiptRebase] = [:]
  /// Refused writes whose overlays this apply removes.
  var removedFailedIDs: Set<String> = []

  /// Rows the plan must stage: the removed refused writes and the re-receipted writers.
  var patchedMutationIDs: Set<String> {
    removedFailedIDs.union(receiptRebases.keys)
  }
}

enum InstantServerApplyReductionLoad: Sendable {
  case ineligible(InstantServerApplyReductionIneligibility)
  case ready(InstantServerApplyReductionContext)
}

/// The pending writes that survive one server apply, as far as the facts that apply names can see them.
struct InstantServerApplyReductionContext: Sendable {
  /// Entities of the apply that a surviving pending write touches (its effect entities).
  var shadowedEntityIDs: Set<String> = []
  /// For each slot of a shadowed entity that a surviving pending write inserts or merges, the earliest such write.
  var firstWriterBySlot: [InstantVisibleWriteKey: String] = [:]
  /// For the same slots, the latest such write, whose value the store must show.
  var lastWriterBySlot: [InstantVisibleWriteKey: String] = [:]
  /// For each shadowed entity with a first writer, the earliest surviving pending write that touches the entity at
  /// all. When it is the slot's first writer, no earlier pending write can have removed the slot's base value.
  var firstOverlayByEntity: [String: String] = [:]
  /// For each reverse-form link slot (target entity, reverse attribute) that surviving pending writes insert, the
  /// earliest and the latest such write. A write of `transcriptionSegments/recording` on a segment materializes as
  /// `recordings/segments` on the recording, but its write key names the segment's slot, so a forward link fact alone
  /// cannot see that write.
  var firstReverseLinkWriterBySlot: [InstantVisibleWriteKey: String] = [:]
  var lastReverseLinkWriterBySlot: [InstantVisibleWriteKey: String] = [:]
  /// Refused writes whose overlays are still on the store, in delivery order. The reduction removes them itself: each
  /// slot a refused write changed goes back to its before-image, in the store or in the next surviving writer's receipt.
  var failedOverlayIDs: [String] = []
  /// For each refused write and each slot it writes (its write keys), the next surviving writer of that slot.
  var nextWriterAfterFailed: [String: [InstantVisibleWriteKey: String]] = [:]
  /// For each refused write, the entities it created (its receipt deletes them) that a surviving write after it touches.
  var createdEntitiesTouchedAfterFailed: [String: Set<String>] = [:]
  /// For each shadowed entity whose latest surviving write deletes it, that write (#932). Scribe's live line is deleted
  /// by its line's final; while a backlog drains, the server's results still show the row. A delete has no write keys,
  /// so the slot rules above cannot see it.
  var deletingWriterByEntity: [String: String] = [:]
  /// The durable bodies of every write named above.
  var bodies: [String: PendingMutation] = [:]
}

/// What a pending write's own operations say about one entity it deletes (#932).
enum InstantServerApplyDeletion {
  /// Whether `operations` delete `entityID` and touch none of its slots afterwards (no re-creation in the same write).
  static func deletesLast(_ entityID: String, in operations: [InstantTripleOperation]) -> Bool {
    var deleted = false
    for operation in operations {
      switch operation {
      case let .deleteEntity(deletedID) where deletedID == entityID:
        deleted = true
      case let .deleteEntityInNamespace(deletedID, _) where deletedID == entityID:
        deleted = true
      case let .insert(triple), let .merge(triple), let .retract(triple):
        if triple.entityID == entityID { deleted = false }
      default:
        continue
      }
    }
    return deleted
  }
}

enum InstantServerApplyReductionLimits {
  /// Bounds the bodies one apply decodes to prove a frame cannot change the base; past it, the full rebase runs.
  static let maximumBodies = 256
  /// Refused writes one apply removes without the full rebase; past it, the full rebase removes them all at once.
  static let maximumFailedOverlays = 16
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
  /// Of the planned bodies, the component the apply peels and replays; the rest are pruned, confirmed, or re-receipted.
  var plannedComponentBodyCount: Int = 0
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
  var timing = InstantServerApplyCommitTiming()
}

/// Where one server-apply commit spends its time inside the persistence actor, in milliseconds (#932).
///
/// The phone's gate-held events showed commits of 1-4 s with nothing pending and no entity changed, and 3-6 s with
/// 2,560 pending, but not whether that was SQLite work, a checkpoint inside `COMMIT`, or waiting for the actor.
struct InstantServerApplyCommitTiming: Sendable, Equatable {
  /// The revision checks and the plan's row and closure validation.
  var validateMilliseconds = 0
  /// The changed facts and merged attributes.
  var factsMilliseconds = 0
  /// The outbox rows the apply removed or rewrote, and their effect entities.
  var outboxMilliseconds = 0
  /// The live-query results the frame carried, and the result JSON whose write was due (#566).
  var resultsMilliseconds = 0
  /// Metadata, revisions and the pending count.
  var bookkeepingMilliseconds = 0
  /// The `COMMIT` statement: the WAL append and, past `wal_autocheckpoint`, the checkpoint SQLite runs inside it.
  var sqliteCommitMilliseconds = 0
  /// From entering `commitServerApplyPlan` to leaving it.
  var insideMilliseconds = 0
  /// Bytes of live-query result JSON this commit wrote.
  var resultJSONBytes = 0
  /// The plan's rows the commit deleted from the outbox (accepted writes the watermark covers, and pruned rows).
  var deletedOutboxRowCount = 0

  static func milliseconds(from start: ContinuousClock.Instant, to end: ContinuousClock.Instant) -> Int {
    let duration = start.duration(to: end)
    return Int(duration.components.seconds * 1_000 + duration.components.attoseconds / 1_000_000_000_000_000)
  }
}

/// One restated live-query result's save, worked out before the server apply takes the operation gate (#932): the
/// result as stored (nested limits applied), the ownership rows that leave and join, and its JSON when the save writes
/// it now. The commit applies it without reading the result's ownership rows or encoding its values under the gate,
/// which cost 87-140 ms a frame for 7,287 restated facts on a Mac mini and 1-4 s on the phone with nothing pending.
struct InstantPreparedLiveQueryResultSave: Sendable {
  var result: InstantPersistedLiveQueryResult
  fileprivate var attributeIDs: Set<String>
  fileprivate var removedOwnership: [LiveQueryOwnershipIdentity]
  fileprivate var insertedOwnership: [LiveQueryOwnershipIdentity]
  fileprivate var json: String?
}

/// Times a commit's consecutive sections into an ``InstantServerApplyCommitTiming`` (#932).
struct InstantServerApplyCommitClock: Sendable {
  var timing = InstantServerApplyCommitTiming()
  private var sectionStartedAt: ContinuousClock.Instant

  init(startedAt: ContinuousClock.Instant) {
    sectionStartedAt = startedAt
  }

  /// Adds the time since the previous section ended to `section`.
  mutating func end(_ section: WritableKeyPath<InstantServerApplyCommitTiming, Int>) {
    let now = ContinuousClock.now
    timing[keyPath: section] += InstantServerApplyCommitTiming.milliseconds(from: sectionStartedAt, to: now)
    sectionStartedAt = now
  }
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
  /// Set when Runtime proved the watermark prunes only a prefix of the overlays and this apply changes no entity a
  /// surviving overlay touches (#296). The pruned rows then leave the outbox as staged deletions without pulling their
  /// connected component into a peel and replay that could not change anything.
  var excludesWatermarkRoots = false
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
  /// Planned bodies that are peeled and replayed (the component), as opposed to pruned, confirmed, or re-receipted.
  package var plannedComponentBodyCount = 0
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
  /// Checks of every row of a plan against the outbox (#932): each reads the outbox columns stored after a row's body,
  /// so a check costs the whole plan's bodies in page reads.
  package var wholePlanValidationCount = 0
  /// Ownership rows a commit read, and result values it encoded, to save restated results (#932).
  package var commitResultOwnershipRowReadCount = 0
  package var commitResultValueEncodeCount = 0
  package var maximumResidentPatchPageCount = 0
  package var maximumResidentPatchPageByteCount = 0
  package var commitAttemptCount = 0
  package var staleCommitCount = 0
  /// Server applies that asked whether their facts could change the base beneath the pending writes (#296).
  package var reductionCount = 0
  /// Of those, the applies that could drop the facts they cannot change instead of rebasing everything.
  package var reducedCount = 0
  /// Receipts re-based onto a server change beneath their pending write, without peeling or replaying it.
  package var receiptPatchCount = 0
  /// Refused writes' overlays a reduced apply removed without the whole-component rebase.
  package var removedFailedOverlayCount = 0

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

/// A stream this device writes, with what it needs to bring the server's copy up to date (#329, ADR 0017).
struct InstantStreamWriterRecord: Hashable, Codable, Sendable {
  /// The id `createStream` returned on this device.
  var streamID: String
  var clientID: String
  /// Lets this device restart the server's copy; the server accepts no other (`session.clj` `handle-start-stream!`).
  /// `nil` until the stream first starts on the server: a stream written offline gets its token then.
  var reconnectToken: String?
  /// The id the server assigned, once a `start-stream-ok` named it.
  var serverStreamID: String?
}

/// Where the server's copy of a stream this device writes stands.
enum InstantStreamWriterState: String, Sendable {
  /// The server may lack some of the stream or its close; each connection's catch-up sends what it lacks.
  case catchingUp = "catching-up"
  /// The server confirmed the close (`stream-flushed` with `done`).
  case delivered
  /// The server refused to start the stream; asking again cannot succeed.
  case refused
}

/// What reading stream content from SQLite cost: the reads, and the stored chunks and bytes they decoded. A stream
/// append must not re-read the whole stream to tell its observers (upstream `Stream.ts` pushes only the new chunk).
package struct InstantStreamContentReadMetrics: Equatable, Sendable {
  package var readCount = 0
  package var decodedChunkCount = 0
  package var decodedByteCount = 0
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
  private let localLookup: InstantLocalLookupPolicy
  private let declaredAttributes: [InstantAttribute]
  /// The VFS the writer opens through, from ``connectionVFSForTesting`` at init, so a reopened connection keeps it.
  private let connectionVFS: String?
  private let connection: SQLiteConnection
  /// A read-only connection to this store's file, for local reads that must not wait behind this actor's writes
  /// (#1006). Reached without a hop onto this actor.
  nonisolated let readConnection: SQLiteReadConnection
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
  private var optimisticEffectFingerprintCount = 0
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
  private var streamContentReadMetrics = InstantStreamContentReadMetrics()
  /// The attributes a live-result save limits its rows with, reused while neither this connection nor another process
  /// has written `instant_attributes` (#303). Every server apply used to load and decode every attribute row once per
  /// query result it saved, inside the commit.
  private var liveResultAttributes: (revision: Int64, generation: Int, attributes: [InstantAttribute])?
  /// What a live refresh's retraction plan reads off `liveResultAttributes` (#431), kept while they are unchanged: the
  /// attributes by id, and the attributes each query key selects.
  private var liveQuerySelections = LiveQuerySelections()
  /// Query keys whose refreshed result, scanned in this process, showed no value in a slot its query selects and leaves
  /// empty, so their later refreshes skip that scan (#431).
  private var liveQueryKeysWithNoClearedSlotLeft: Set<String> = []
  /// Bumped by every write to `instant_attributes` on this connection.
  private var attributeWriteGeneration = 0
  private var liveResultAttributeLoads = 0
  /// Releases SQLite's memory when the system warns of memory pressure (#653).
  private let memoryPressureMonitor: SQLiteMemoryPressureMonitor
  /// Live-query result saves, and the result JSON they wrote (#566): for tests and the release's measurements.
  private var liveQueryResultJSONWriteStats = (saves: 0, writes: 0, bytes: 0)
  /// What this process knows about each live query's stored result JSON (#566). A server apply used to rewrite a
  /// refreshed query's whole result as one JSON blob, every time: Michael's iPhone dirtied 1,074 MB in 185 s after
  /// launch on build 90. Now a result that did not change writes no JSON, and a changed result's JSON is written at most
  /// once per query per `liveQueryResultJSONWriteIntervalMilliseconds`; meanwhile the newest result is here, and every
  /// reader in this process reads it from here. The ownership rows stay exact on every refresh. A result whose JSON
  /// waits is marked in `instant_sync_metadata`, so if the process ends before the write, the next bootstrap rebuilds
  /// it from its ownership rows (`repairDeferredLiveQueryResultJSON()`). Restored when a write transaction rolls back.
  private struct LiveQueryResultJSONState {
    /// The newest result of each query whose stored JSON is older.
    var deferred: [String: InstantPersistedLiveQueryResult] = [:]
    /// When this process last wrote each query's JSON: that result's `updatedAt`, in milliseconds.
    var writtenAt: [String: Int64] = [:]
    /// The page info each query's stored JSON holds, for the queries this process wrote.
    var writtenPageInfo: [String: InstantQueryPageInfo?] = [:]
    /// The queries whose stale marker this process wrote and has not deleted.
    var marked: Set<String> = []
  }
  private var liveQueryResultJSON = LiveQueryResultJSONState()
  private var liveQueryResultJSONWriteIntervalMilliseconds: Int64 = 30_000
  /// Ownership rows read and result values encoded to save live-query results, for the commit's metrics (#932).
  private var liveQueryOwnershipRowReadCount = 0
  private var liveQueryResultValueEncodeCount = 0
  private var liveQueryResultJSONFlushSleep: @Sendable (_ milliseconds: UInt64) async throws -> Void = { milliseconds in
    try await Task.sleep(nanoseconds: milliseconds * 1_000_000)
  }
  private var liveQueryResultJSONFlushTask: Task<Void, Never>?
  private static let deferredLiveQueryResultJSONMarkerPrefix = "live-query-result-json-waiting:"
  private var declaredRelationReconciliationLiveResultScanCount = 0
  private var installedDeclaredRelationStorageMarker:
    DeclaredRelationStorageReconciliationMarker?
  private var installedDeclaredRelationStorageObsoleteAttributeIDs: Set<String> = []
  private var didLoadDeclaredRelationStorageMarker = false
  private var onFailedMutationRetryWindowLoadedForTesting:
    (@Sendable (_ mutationIDs: [String]) async throws -> Void)?

  package func deferredValueDecodeMetricsForTesting() -> InstantDeferredValueDecodeMetrics {
    // Local reads decode theirs on the read connection (#1006).
    let local = readConnection.deferredValueDecodeMetrics
    return InstantDeferredValueDecodeMetrics(
      valueCount: deferredValueDecodeMetrics.valueCount + local.valueCount,
      encodedByteCount: deferredValueDecodeMetrics.encodedByteCount + local.encodedByteCount
    )
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

  /// How many optimistic-effect fingerprints this store has computed (#1007).
  package func optimisticEffectFingerprintCountForTesting() -> Int {
    optimisticEffectFingerprintCount
  }

  /// `mutation`'s optimistic-effect receipt fingerprint, counted (#1007). Each one encodes the mutation's transaction and
  /// rollback with `JSONEncoder` and hashes the text.
  private func optimisticEffectFingerprint(of mutation: PendingMutation) throws -> String? {
    optimisticEffectFingerprintCount += 1
    return try mutation.optimisticEffectReceiptFingerprint()
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

  /// How many live-result saves loaded the attributes from SQLite instead of reusing them (#303).
  package func liveResultAttributeLoadCountForTesting() -> Int {
    liveResultAttributeLoads
  }

  /// How many live-query results were saved, and how many writes and bytes of result JSON they made (#566).
  package func liveQueryResultJSONWriteStatsForTesting() -> (saves: Int, writes: Int, bytes: Int) {
    liveQueryResultJSONWriteStats
  }

  /// Sets how often a live query's result JSON may be written while it changes, and how the scheduled write waits
  /// (#566). An interval of 0 writes every changed result at once.
  package func configureLiveQueryResultJSONWrites(
    intervalMilliseconds: Int64,
    flushSleep: @escaping @Sendable (_ milliseconds: UInt64) async throws -> Void
  ) {
    liveQueryResultJSONWriteIntervalMilliseconds = max(0, intervalMilliseconds)
    liveQueryResultJSONFlushSleep = flushSleep
  }

  /// Writes the stored JSON of every live-query result whose write waited, or of the ones in `keys` (#566). The app
  /// calls this when it goes to the background or terminates; the runtime calls it when a query unsubscribes and when
  /// the connection closes. Returns how many results it wrote.
  @discardableResult
  package func flushDeferredLiveQueryResults(keys: Set<String>? = nil) throws -> Int {
    let waiting = keys.map { !Set(liveQueryResultJSON.deferred.keys).isDisjoint(with: $0) }
      ?? !liveQueryResultJSON.deferred.isEmpty
    guard waiting else { return 0 }
    return try transaction { try flushDeferredLiveQueryResultsWithoutTransaction(keys: keys) }
  }

  /// How many live-query results wait for their JSON write (#566), for tests.
  package func deferredLiveQueryResultCountForTesting() -> Int {
    liveQueryResultJSON.deferred.count
  }

  /// Writes, within one interval, the results whose JSON waited, if any are left (#566).
  private func scheduleDeferredLiveQueryResultFlushIfNeeded() {
    guard !liveQueryResultJSON.deferred.isEmpty, liveQueryResultJSONFlushTask == nil else { return }
    let sleep = liveQueryResultJSONFlushSleep
    let interval = UInt64(liveQueryResultJSONWriteIntervalMilliseconds)
    liveQueryResultJSONFlushTask = Task { [weak self] in
      try? await sleep(interval)
      await self?.runScheduledDeferredLiveQueryResultFlush()
    }
  }

  private func runScheduledDeferredLiveQueryResultFlush() {
    liveQueryResultJSONFlushTask = nil
    do {
      try flushDeferredLiveQueryResults()
    } catch {
      InstantDiagnostics.shared.record(
        error: error,
        subsystem: "instant-swift-data-core",
        category: "persistence",
        event: "live-query-results.deferred-json-flush-failed",
        message: "Could not write the live-query results whose JSON waited; the next flush or bootstrap writes them."
      )
    }
    scheduleDeferredLiveQueryResultFlushIfNeeded()
  }

  /// Writes the stored JSON of the results whose write waited (#566): all of them, the ones in `keys`, or, with
  /// `dueAt`, the ones whose last write is at least one interval older than it.
  @discardableResult
  private func flushDeferredLiveQueryResultsWithoutTransaction(
    keys: Set<String>? = nil,
    dueAt now: Int64? = nil
  ) throws -> Int {
    var written = 0
    for (key, result) in liveQueryResultJSON.deferred.sorted(by: { $0.key < $1.key }) {
      if let keys, !keys.contains(key) { continue }
      if let now, let writtenAt = liveQueryResultJSON.writtenAt[key],
        now - writtenAt < liveQueryResultJSONWriteIntervalMilliseconds
      {
        continue
      }
      let json = try encode(result)
      try execute(
        """
        UPDATE instant_live_query_results
        SET triple_count = ?, updated_at_ms = MAX(updated_at_ms, ?), json = ?
        WHERE query_key = ?
        """,
        [
          .int(Int64(result.triples.count)),
          .int(result.updatedAt.milliseconds),
          .text(json),
          .text(key),
        ]
      )
      if sqlite3_changes(connection.raw) == 1 {
        liveQueryResultJSONWriteStats.writes += 1
        liveQueryResultJSONWriteStats.bytes += json.utf8.count
        written += 1
      }
      liveQueryResultJSON.deferred[key] = nil
      liveQueryResultJSON.writtenAt[key] = result.updatedAt.milliseconds
      liveQueryResultJSON.writtenPageInfo[key] = result.pageInfo
      try clearDeferredLiveQueryResultJSONMarkerWithoutTransaction(key)
    }
    return written
  }

  private func markDeferredLiveQueryResultJSONWithoutTransaction(_ key: String, at milliseconds: Int64) throws {
    guard liveQueryResultJSON.marked.insert(key).inserted else { return }
    try execute(
      Self.upsertMetadataSQL,
      [.text(Self.deferredLiveQueryResultJSONMarkerPrefix + key), .text("1"), .int(milliseconds)]
    )
  }

  private func clearDeferredLiveQueryResultJSONMarkerWithoutTransaction(_ key: String) throws {
    guard liveQueryResultJSON.marked.remove(key) != nil else { return }
    try execute(
      "DELETE FROM instant_sync_metadata WHERE key = ?",
      [.text(Self.deferredLiveQueryResultJSONMarkerPrefix + key)]
    )
  }

  /// Forgets a dropped or pruned result's deferred JSON and marker (#566).
  private func forgetLiveQueryResultJSONStateWithoutTransaction(_ key: String) throws {
    liveQueryResultJSON.deferred[key] = nil
    liveQueryResultJSON.writtenAt[key] = nil
    liveQueryResultJSON.writtenPageInfo[key] = nil
    liveQueryResultJSON.marked.remove(key)
    try execute(
      "DELETE FROM instant_sync_metadata WHERE key = ?",
      [.text(Self.deferredLiveQueryResultJSONMarkerPrefix + key)]
    )
  }

  /// Rebuilds the stored JSON of each live-query result whose JSON write waited when the last process ended (#566),
  /// before anything reads it: its facts are its ownership rows (exact on every refresh), each with the stamp the stale
  /// JSON or the store holds for it, and its page info is the stale JSON's. A later server result is diffed against
  /// this one to retract what left it, so a crash between throttled writes cannot keep a fact the server deleted.
  private func repairDeferredLiveQueryResultJSON() throws {
    let prefix = Self.deferredLiveQueryResultJSONMarkerPrefix
    var markerKeys: [String] = []
    var statement: OpaquePointer?
    try prepare(
      "SELECT key FROM instant_sync_metadata WHERE key >= ? AND key < ? ORDER BY key",
      statement: &statement
    )
    defer { finishStatement(statement) }
    try bind([.text(prefix), .text(prefix + "\u{10FFFF}")], to: statement)
    while sqlite3_step(statement) == SQLITE_ROW {
      if let key = sqlite3_column_text(statement, 0) {
        markerKeys.append(String(cString: key))
      }
    }
    guard !markerKeys.isEmpty else { return }
    var repaired = 0
    try transaction {
      for marker in markerKeys {
        let queryKey = String(marker.dropFirst(prefix.count))
        defer { _ = try? execute("DELETE FROM instant_sync_metadata WHERE key = ?", [.text(marker)]) }
        guard
          let updatedAtText: String = try selectScalar(
            "SELECT updated_at_ms FROM instant_live_query_results WHERE query_key = ? LIMIT 1",
            [.text(queryKey)]
          ),
          let updatedAt = Int64(updatedAtText),
          var result = try liveQueryResultWithoutTransaction(key: queryKey)
        else { continue }
        var staleByIdentity: [LiveQueryOwnershipIdentity: InstantTriple] = [:]
        for triple in result.triples {
          staleByIdentity[
            LiveQueryOwnershipIdentity(
              entityID: triple.entityID,
              attributeID: triple.attributeID,
              valueJSON: try encode(triple.value)
            )
          ] = triple
        }
        var triples: [InstantTriple] = []
        for identity in try liveQueryOwnershipWithoutTransaction(queryKey: queryKey) {
          if let triple = staleByIdentity[identity] {
            triples.append(triple)
            continue
          }
          let stored: [InstantTriple] = try selectJSON(
            """
            SELECT json FROM instant_triples
            WHERE entity_id = ? AND attribute_id = ? AND value_json = ?
            LIMIT 1
            """,
            [.text(identity.entityID), .text(identity.attributeID), .text(identity.valueJSON)]
          )
          if let stored = stored.first {
            triples.append(stored)
          } else {
            triples.append(
              InstantTriple(
                entityID: identity.entityID,
                attributeID: identity.attributeID,
                value: try decoder.decode(InstantValue.self, from: Data(identity.valueJSON.utf8)),
                txID: "live-query-result-repair",
                txTime: InstantTimestamp(milliseconds: updatedAt)
              )
            )
          }
        }
        result.triples = triples.sorted(by: InstantPersistedLiveQueryResult.storedOrder)
        result.updatedAt = InstantTimestamp(milliseconds: updatedAt)
        try execute(
          "UPDATE instant_live_query_results SET triple_count = ?, json = ? WHERE query_key = ?",
          [.int(Int64(result.triples.count)), .text(try encode(result)), .text(queryKey)]
        )
        repaired += 1
      }
    }
    InstantDiagnostics.shared.record(
      .info,
      subsystem: "instant-swift-data-core",
      category: "persistence",
      event: "live-query-results.deferred-json-repaired",
      message: "Rebuilt the stored JSON of live-query results whose write waited when the last process ended.",
      metadata: ["markerCount": String(markerKeys.count), "repairedCount": String(repaired)]
    )
  }

  /// How many pages this connection has written to the database or its WAL since it opened, and the page size (#566).
  package func sqlitePagesWrittenForTesting() throws -> (pages: Int, pageSize: Int) {
    var current: Int32 = 0
    var highwater: Int32 = 0
    sqlite3_db_status(connection.raw, SQLITE_DBSTATUS_CACHE_WRITE, &current, &highwater, 0)
    let pageSize: Int64 = try selectInt64("PRAGMA page_size", [])
    return (Int(current), Int(pageSize))
  }

  /// One full attribute load, as each live-result save did before it reused them; for cost tests.
  package func loadAttributesForTesting() throws -> [InstantAttribute] {
    try loadAttributesWithoutTransaction(tracesStartupCollection: false)
  }

  /// The attributes a live-result save uses now; for cost tests.
  package func attributesForLiveResultSaveForTesting() throws -> [InstantAttribute] {
    try attributesForLiveResultSaveWithoutTransaction()
  }

  package func serverApplyMetricsForTesting() -> InstantServerApplyMetrics {
    serverApplyMetrics
  }

  /// Holds this actor for `duration` without suspending, as a long SQLite commit does, after calling `started` (#1006).
  package func occupyForTesting(_ duration: Duration, started: @Sendable () -> Void) {
    started()
    let (seconds, attoseconds) = duration.components
    Thread.sleep(forTimeInterval: Double(seconds) + Double(attoseconds) / 1e18)
  }

  package func streamContentReadMetricsForTesting() -> InstantStreamContentReadMetrics {
    streamContentReadMetrics
  }

  package func resetStreamContentReadMetricsForTesting() {
    streamContentReadMetrics = InstantStreamContentReadMetrics()
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
    defer { finishStatement(statement) }
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

  /// Releases the memory SQLite holds for this connection: its page cache, which is bounded at 2 MiB, the prepared
  /// statements waiting for reuse, and whatever else `sqlite3_db_release_memory` frees (#653). The store calls it when
  /// the system warns of memory pressure; SQLite reads the pages it needs again afterwards, and prepares the statements
  /// again on their next use. A save used to run `PRAGMA shrink_memory` every time.
  package func releaseMemory() {
    guard let raw = connection.raw else { return }
    var usedBefore: Int32 = 0
    var highwater: Int32 = 0
    sqlite3_db_status(raw, SQLITE_DBSTATUS_CACHE_USED, &usedBefore, &highwater, 0)
    // On Apple's SQLite `sqlite3_db_release_memory` leaves the page cache as it was (411 KB before and after, measured);
    // lowering the bound to one page drops the rest, and the 2 MiB bound comes back for the next reads.
    connection.statements.finalizeIdle()
    _ = sqlite3_exec(raw, "PRAGMA cache_size = 1", nil, nil, nil)
    _ = sqlite3_exec(raw, "PRAGMA cache_size = \(sqlitePageCacheSizeKibibytes)", nil, nil, nil)
    sqlite3_db_release_memory(raw)
    var usedAfter: Int32 = 0
    sqlite3_db_status(raw, SQLITE_DBSTATUS_CACHE_USED, &usedAfter, &highwater, 0)
    InstantDiagnostics.shared.record(
      .info,
      subsystem: "instant-swift-data-core",
      category: "persistence",
      event: "sqlite.memory-released",
      message: "Released SQLite's page cache under memory pressure.",
      metadata: [
        "cacheBytesBefore": String(usedBefore),
        "cacheBytesAfter": String(usedAfter),
      ]
    )
  }

  private func adoptCachedState(_ state: InstantPersistenceState) {
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
  }

  private func advanceCachedRevisionDomains(
    expectedStoreRevision: Int64,
    expectedAttributeRevision: Int64,
    expectedOutboxRevision: Int64,
    expectedQueryResultRevision: Int64,
    changedEntityTriples: [String: [InstantTriple]],
    changedFactScope: InstantFactScope,
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
          with: changedEntityTriples,
          scope: changedFactScope
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
      adoptCachedState(state)
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
    localLookup: InstantLocalLookupPolicy = .none,
    declaredAttributes: [InstantAttribute] = []
  ) throws {
    self.fileURL = fileURL
    self.startupTrace = startupTrace
    self.deferredValueResidency = deferredValueResidency
    self.localLookup = localLookup
    self.declaredAttributes = declaredAttributes
    let connectionVFS = Self.connectionVFSForTesting
    self.connectionVFS = connectionVFS
    self.readConnection = SQLiteReadConnection(
      fileURL: fileURL,
      deferredAttributeIDs: deferredValueResidency.attributeIDs,
      lookupAttributeIDs: localLookup.attributeIDs
    )
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
      self.connection = SQLiteConnection(try Self.openRawConnection(fileURL: fileURL, vfs: connectionVFS))
      self.memoryPressureMonitor = SQLiteMemoryPressureMonitor()
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
    memoryPressureMonitor.start { [weak self] in
      guard let self else { return }
      Task { await self.releaseMemory() }
    }
  }

  /// The VFS a store made in this task opens its writer through; `nil`, the system's default. A test sets it to watch
  /// what SQLite asks the file system to do: #1118's power-loss images journal every write since the last sync.
  @TaskLocal package static var connectionVFSForTesting: String?

  private static func openRawConnection(fileURL: URL, vfs: String?) throws -> OpaquePointer? {
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
    guard sqlite3_open_v2(fileURL.path, &opened, flags, vfs) == SQLITE_OK
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
    // A page cache bounded at 2 MiB per connection (#653), instead of `cache_size = 0` and a `PRAGMA shrink_memory`
    // after every save. On Apple's SQLite 0 did not bound the cache: reading a 20,000-fact store left 8.8 MB in it, and
    // the shrink did not lower it. In the release write-path harness the change left CPU and logical writes about the
    // same (a 4,344-write replay: -1% instructions, -0.5% bytes); the #653 audit's estimate of 992 to 609 KB per write
    // did not reproduce there. A failure here leaves SQLite's default cache, so it does not fail the open.
    _ = sqlite3_exec(opened, "PRAGMA cache_size = \(sqlitePageCacheSizeKibibytes)", nil, nil, nil)
    // #1118: a checkpoint every 4,000 frames of the log instead of Apple's 1,000. Each one costs three F_FULLFSYNCs
    // (the log before the copy, the file after it, the restarted log's header); at a recording's 62.5 frames a write
    // the default ran one every 16 writes, 1,039 full syncs in #1076's simulated hour, and copied the same hot pages
    // again each time. 4,000 frames still fit the log index's first 32 KB block (4,062 frames), so a read probes one
    // hash table, and the log tops out near 16 MB. What it costs: synchronous = NORMAL syncs the log only at a
    // checkpoint, so a power loss (not an app crash, which loses nothing) can take the writes since the last one, up
    // to 4,000 frames instead of 1,000; the store opens consistent either way (SQLiteCheckpointCadenceTests). A
    // failure leaves Apple's default, so it does not fail the open.
    _ = sqlite3_wal_autocheckpoint(opened, sqliteWALAutocheckpointFrames)
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

  /// Runs `body` on this store in one actor turn and returns its result.
  ///
  /// Each `await` on a method of this actor is one hop onto its executor, and another caller's persistence work can
  /// run between two of them. A runtime step that needs several of these synchronous methods calls them inside one
  /// `run` instead: one hop, and nothing interleaves, because `body` cannot suspend. This is Point-Free's `run` (ep362
  /// at 12:16; rule 2 of their isolation series: enter an actor once, then work synchronously). Each method keeps its
  /// own SQLite transaction; `run` adds none.
  ///
  ///     let (state, pendingCount) = try await persistence.run { persistence in
  ///       (try persistence.loadCompactState(), try persistence.countOutboxMutations(status: .pending))
  ///     }
  package func run<Result: Sendable>(
    _ body: @Sendable (isolated SQLitePersistenceStore) throws -> Result
  ) rethrows -> Result {
    try body(self)
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
    // #1015: SQLite fixes `auto_vacuum` when it writes a file's first page, which `journal_mode = WAL` does, so a mode
    // other than NONE goes first; set after it, the mode stays NONE and SQLite says nothing (Apple's SQLite 3.54).
    if Self.newCacheAutoVacuum != .none {
      try withSQLiteBusyRetry {
        if try selectInt64("PRAGMA page_count") == 0 {
          try execute(
            Self.newCacheAutoVacuum == .full ? "PRAGMA auto_vacuum = FULL" : "PRAGMA auto_vacuum = INCREMENTAL"
          )
        }
      }
    }
    try withSQLiteBusyRetry {
      try execute("PRAGMA journal_mode = WAL")
    }
    try execute("PRAGMA foreign_keys = ON")
    recordDurabilitySettings()
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
        // A store that ran this step before #704 keyed every ownership row by its query's whole key;
        // `compactLiveQueryOwnershipIfNeeded()` converts it. A new store gets the compact tables here (ADR 0020).
        try execute(Self.liveQueryResultsTableSQL(named: "instant_live_query_results"))
        try execute(Self.liveQueryOwnershipTableSQL)
        try execute(Self.liveQueryOwnershipIdentityIndexSQL)
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
    try withSQLiteBusyRetry {
      try migrate(name: "0024_remove_entities_missing_their_id_fact") {
        try removeEntitiesMissingTheirIDFactWithoutTransaction()
      }
    }
    try withSQLiteBusyRetry {
      // The streams this device writes, and what the server has of them (#329, ADR 0017).
      try migrate(name: "0025_stream_writers") {
        try execute(
          """
          CREATE TABLE IF NOT EXISTS instant_stream_writers (
            app_id TEXT NOT NULL,
            stream_id TEXT NOT NULL,
            client_id TEXT NOT NULL,
            reconnect_token TEXT,
            server_stream_id TEXT,
            state TEXT NOT NULL,
            refusal TEXT,
            PRIMARY KEY (app_id, stream_id),
            FOREIGN KEY (app_id, stream_id) REFERENCES instant_streams (app_id, stream_id)
              ON DELETE CASCADE
          )
          """
        )
        try execute(
          """
          CREATE INDEX IF NOT EXISTS instant_stream_writers_state_idx
          ON instant_stream_writers (app_id, state)
          """
        )
      }
    }
    try withSQLiteBusyRetry {
      // Results of queries that closed, kept for their next subscription (#1006). Upstream
      // `PersistedObject.unloadKey` unloads a closed query from memory and keeps its stored copy until the age, entry
      // and size limits collect it. A row lives in this table or in `instant_live_query_results`, never both, so every
      // reader of that table sees an unloaded result as removed, as before.
      try migrate(name: "0027_unloaded_live_query_results") {
        try execute(Self.unloadedLiveQueryResultsTableSQL)
      }
    }
    try withSQLiteBusyRetry {
      // No statement's plan used this index, and every insert, claim, acknowledgement and delete of a row wrote a page
      // of it (#1007). The statements that filter on the claim state alone use `instant_outbox_delivery_deadline_idx`,
      // which leads with the same column; the ones that name the delivery state hold it inside an `OR`.
      try migrate(name: "0028_drop_unused_outbox_delivery_window_index") {
        try execute("DROP INDEX IF EXISTS instant_outbox_delivery_window_idx")
      }
    }
    try withSQLiteBusyRetry {
      // The delivery pump's candidate read searches its needs-delivery branch by this index (#1108). Each write of an
      // outbox row writes a page of it; each claim pass no longer reads every ready row's overflow pages.
      try migrate(name: "0029_outbox_delivery_candidate_index") {
        try execute(Self.deliveryCandidateIndexSQL)
      }
    }
    try withSQLiteBusyRetry {
      // #1115: a write's key rows and its effect entities are keyed by their whole row. As rowid tables each kept a
      // second b-tree, its primary key's index, holding the same columns, so every save and every echo wrote a page of
      // both: 4 of a live write's 36 outbox frames (#1076's eachStepOfALiveWrite). WITHOUT ROWID the key is the table.
      // A row whose write is gone (a restore that turned foreign keys off can leave one) is not carried over.
      try migrate(name: "0030_outbox_key_tables_without_rowid") {
        for table in Self.outboxKeyTablesWithoutRowid {
          try execute(table.create)
          try execute(
            """
            INSERT INTO \(table.name)_0030 (\(table.columns))
            SELECT \(table.columns) FROM \(table.name) AS keyed
            WHERE EXISTS (SELECT 1 FROM instant_outbox AS outbox WHERE outbox.mutation_id = keyed.mutation_id)
            """
          )
          try execute("DROP TABLE \(table.name)")
          try execute("ALTER TABLE \(table.name)_0030 RENAME TO \(table.name)")
          try execute(table.lookupIndex)
        }
      }
    }
    try withSQLiteBusyRetry {
      // #1115: one index for the delivery order and the claims' deadlines, where a claim moved its row in two (the
      // deadline index and #1108's candidate index) and a save inserted it into both.
      try migrate(name: "0031_outbox_delivery_index") {
        try execute("DROP INDEX IF EXISTS instant_outbox_delivery_candidate_idx")
        try execute("DROP INDEX IF EXISTS instant_outbox_delivery_deadline_idx")
        try execute(Self.deliveryIndexSQL)
      }
    }
    try withSQLiteBusyRetry {
      try migrateFactsToOneCopyIfNeeded()
    }
    try withSQLiteBusyRetry {
      try compactLiveQueryOwnershipIfNeeded()
    }
    // A restore that rebuilt `instant_outbox` after 0031 ran keeps the claim off a scan too (#1108, #1115).
    try execute(Self.deliveryIndexSQL)
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
    try withSQLiteBusyRetry {
      try ensureLookupIndexes()
    }
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

  /// The fact table: each fact once, keyed by the fact itself (#1121). `json`, the text every reader decodes, is a virtual
  /// generated column: SQLite computes it from the row when it is read and stores nothing. Its keys come in the order
  /// `InstantStoredJSON` wrote them; a string's `/` is not escaped as `JSONEncoder` escapes it, which no decoder minds.
  /// `value_json` keeps the value's text exactly as before: it is part of the key and of every lookup by value.
  static func factTableSQL(named name: String) -> String {
    """
    CREATE TABLE \(name) (
      entity_id TEXT NOT NULL,
      attribute_id TEXT NOT NULL,
      value_json TEXT NOT NULL,
      tx_id TEXT NOT NULL,
      tx_time_ms INTEGER NOT NULL,
      json TEXT GENERATED ALWAYS AS (
        '{"attributeID":' || json_quote(attribute_id) || ',"entityID":' || json_quote(entity_id)
          || ',"txID":' || json_quote(tx_id) || ',"txTime":{"milliseconds":' || tx_time_ms
          || '},"value":' || value_json || '}'
      ) VIRTUAL,
      PRIMARY KEY (entity_id, attribute_id, value_json)
    ) WITHOUT ROWID
    """
  }

  /// Rebuilds the fact table with each fact stored once (#1121), the first time a store opens in the old layout.
  ///
  /// The old table kept a fact's five columns, a `json` column repeating the whole row, and, as a rowid table with a
  /// text key, the key again in its own index: on a copy of one phone's store 174,817 facts took 127.1 MB (87.0 of
  /// table, 40.1 of key index), and the same facts in this layout 40.7 MB, rebuilt in 0.9 s with 8.9 MB of memory on a
  /// laptop. The rebuild is one transaction: the new table is filled in key order, checked against the old one (the
  /// row count and every column's total size) and only then put in its place, so a store that fails the check keeps
  /// its old table whole. Dirty pages spill to the log past 256, as in `vacuum()`, so the rebuild's memory stays small
  /// (Apple's SQLite holds 20,000 dirty pages otherwise). The lookup index goes with the old table and is made again
  /// on the new one at the end of `bootstrap`. The old table's pages become free pages, given back by
  /// `compactLocalCache`'s `VACUUM` (#1015).
  private func migrateFactsToOneCopyIfNeeded() throws {
    let cacheSpill = try selectInt64("PRAGMA cache_spill")
    try execute("PRAGMA cache_spill = 256")
    defer { _ = try? execute("PRAGMA cache_spill = \(cacheSpill)") }
    try migrate(name: "0032_instant_triples_stored_once") {
      let columns = "entity_id, attribute_id, value_json, tx_id, tx_time_ms"
      try execute("DROP TABLE IF EXISTS instant_triples_0032")
      try execute(Self.factTableSQL(named: "instant_triples_0032"))
      try execute(
        """
        INSERT INTO instant_triples_0032 (\(columns))
        SELECT \(columns) FROM instant_triples ORDER BY entity_id, attribute_id, value_json
        """
      )
      func census(_ table: String) throws -> String? {
        try selectScalar(
          """
          SELECT count(*) || ':' || coalesce(sum(length(entity_id) + length(attribute_id) + length(value_json)
            + length(tx_id)), 0) || ':' || coalesce(sum(tx_time_ms), 0)
          FROM \(table)
          """
        )
      }
      let before = try census("instant_triples")
      let after = try census("instant_triples_0032")
      guard before == after else {
        throw persistenceError(
          operation: "store each fact once",
          message: "The rebuilt fact table does not match the old one (\(after ?? "none") against \(before ?? "none"))."
        )
      }
      try execute("DROP TABLE instant_triples")
      try execute("ALTER TABLE instant_triples_0032 RENAME TO instant_triples")
    }
  }

  /// The partial index local reads look entities up by (#1006). One index for every lookup attribute, so building it
  /// reads the table once: one device's store held 1.6 GB.
  static let lookupIndexName = "instant_triples_lookup"

  /// The partial index's WHERE clause for `attributeIDs`. A lookup repeats it word for word, so SQLite can prove the
  /// index applies.
  static func lookupIndexCondition(_ attributeIDs: Set<String>) -> String {
    "attribute_id IN (" + attributeIDs.sorted().map(sqlLiteral).joined(separator: ", ") + ")"
  }

  /// `text` as a quoted SQL string literal.
  static func sqlLiteral(_ text: String) -> String {
    "'" + text.replacingOccurrences(of: "'", with: "''") + "'"
  }

  /// The lookup index on the facts of the policy's attributes alone (#1006): a local read filtered by
  /// `attribute == value` finds the entities this device keeps on disk without reading the table. The index is rebuilt
  /// when the policy names other attributes, and dropped when it names none; building it reads the table once.
  private func ensureLookupIndexes() throws {
    let existing = try selectStrings(
      "SELECT sql FROM sqlite_master WHERE type = 'index' AND name = ?",
      [.text(Self.lookupIndexName)]
    ).first
    guard localLookup.isEnabled else {
      if existing != nil { try execute("DROP INDEX IF EXISTS \(Self.lookupIndexName)") }
      return
    }
    let condition = Self.lookupIndexCondition(localLookup.attributeIDs)
    if let existing, existing.hasSuffix("WHERE " + condition) { return }
    let started = ContinuousClock.now
    try execute("DROP INDEX IF EXISTS \(Self.lookupIndexName)")
    try execute(
      "CREATE INDEX \(Self.lookupIndexName) ON instant_triples (attribute_id, value_json, entity_id) WHERE \(condition)"
    )
    let elapsed = started.duration(to: .now).components
    InstantDiagnostics.shared.record(
      .notice,
      subsystem: "instant-swift-data-core",
      category: "persistence",
      event: "sqlite.lookup-index-created",
      message: "#1006 Built the index local reads look entities up by.",
      metadata: [
        "attributeIDs": localLookup.attributeIDs.sorted().joined(separator: ","),
        "elapsedMilliseconds": String(elapsed.seconds * 1_000 + elapsed.attoseconds / 1_000_000_000_000_000),
      ]
    )
  }

  package func bootstrap(
    queryCachePruningPolicy: InstantQueryCachePruningPolicy,
    now: InstantTimestamp
  ) throws -> InstantQueryCachePruningResult? {
    try bootstrap()
    try repairDeferredLiveQueryResultJSON()
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

  /// The ledger row the conversion below writes. The table's columns, not this row, decide whether it runs (#704).
  private static let compactLiveQueryOwnershipMigrationName = "0026_live_query_compact_ownership"

  /// A stored live-query result, named by an integer id (its rowid) as well as by its key (#704, ADR 0020).
  private static func liveQueryResultsTableSQL(named name: String) -> String {
    """
    CREATE TABLE IF NOT EXISTS \(name) (
      query_id INTEGER PRIMARY KEY,
      query_key TEXT NOT NULL UNIQUE,
      triple_count INTEGER NOT NULL,
      updated_at_ms INTEGER NOT NULL,
      json TEXT NOT NULL
    )
    """
  }

  /// A closed query's stored result, unloaded from the store and owning no fact, until its query subscribes again or
  /// the pruning policy collects it (#1006). The columns are `instant_live_query_results`' without its `query_id`.
  private static let unloadedLiveQueryResultsTableSQL = """
    CREATE TABLE IF NOT EXISTS instant_unloaded_live_query_results (
      query_key TEXT PRIMARY KEY NOT NULL,
      triple_count INTEGER NOT NULL,
      updated_at_ms INTEGER NOT NULL,
      json TEXT NOT NULL
    )
    """

  /// A result's ownership of a fact, one row each, its own primary-key b-tree (#704, ADR 0020).
  private static let liveQueryOwnershipTableSQL = """
    CREATE TABLE IF NOT EXISTS instant_live_query_triples (
      query_id INTEGER NOT NULL,
      entity_id TEXT NOT NULL,
      attribute_id TEXT NOT NULL,
      value_json TEXT NOT NULL,
      PRIMARY KEY (query_id, entity_id, attribute_id, value_json),
      FOREIGN KEY (query_id) REFERENCES instant_live_query_results (query_id)
        ON DELETE CASCADE
    ) WITHOUT ROWID
    """

  /// The results that own a fact, by entity, attribute and value (#704, ADR 0020).
  private static let liveQueryOwnershipIdentityIndexSQL = """
    CREATE INDEX IF NOT EXISTS instant_live_query_triples_identity_idx
    ON instant_live_query_triples (entity_id, attribute_id, value_json, query_id)
    """

  /// Converts migration 0011's live-query tables to ownership rows that name their result by `query_id` (#704,
  /// ADR 0020).
  ///
  /// 0011 keyed every ownership row by the result's `query_key`, the whole InstaQL JSON of its query, and both of the
  /// table's indexes held it: on a device, 32,555 rows with 3.7 MB of values took 328.9 MB, most index entries on an
  /// overflow page of their own. Each result row now has an integer `query_id` (its rowid), the ownership table is its
  /// own primary-key b-tree (`WITHOUT ROWID`), and the identity index ends with the id.
  ///
  /// One transaction: a process that dies during it leaves 0011's tables as they were, and the next open converts
  /// again from the start. Every result row and every ownership row whose result exists is copied as it was; a row
  /// whose result is missing (the foreign key forbids one) names nothing and is counted, not copied. The check is the
  /// table's columns rather than the ledger, because fixtures and restores can recreate 0011's tables after the
  /// ledger recorded this step. A new store's 0011 creates the compact tables, so it has nothing to convert.
  private func compactLiveQueryOwnershipIfNeeded() throws {
    guard try liveQueryOwnershipRowsCarryTheirQueryKey() else { return }
    let stopwatch = startupTrace.started(
      "sqlite.live-query-ownership-compaction",
      metadata: ["file": fileURL.lastPathComponent]
    )
    let startedAt = DispatchTime.now().uptimeNanoseconds
    let counts: (rows: Int64, copiedRows: Int64, results: Int64)?
    do {
      counts = try transaction { () -> (rows: Int64, copiedRows: Int64, results: Int64)? in
        // Another connection may have converted the store while this one waited for the write lock.
        guard try liveQueryOwnershipRowsCarryTheirQueryKey() else { return nil }
        try execute("DROP TABLE IF EXISTS instant_live_query_results_0026")
        try execute("DROP TABLE IF EXISTS temp.instant_live_query_triples_0026")
        try execute(Self.liveQueryResultsTableSQL(named: "instant_live_query_results_0026"))
        try execute(
          """
          INSERT INTO instant_live_query_results_0026 (query_key, triple_count, updated_at_ms, json)
          SELECT query_key, triple_count, updated_at_ms, json
          FROM instant_live_query_results
          ORDER BY query_key
          """
        )
        let results = Int64(sqlite3_changes(connection.raw))
        let rows = try selectInt64("SELECT COUNT(*) FROM instant_live_query_triples")
        // The rows wait, with their ids, in a temporary table while the old tables go, so the new ownership table is
        // created under its own name with its final foreign key.
        try execute(
          """
          CREATE TEMP TABLE instant_live_query_triples_0026 AS
          SELECT result.query_id AS query_id, owned.entity_id AS entity_id,
            owned.attribute_id AS attribute_id, owned.value_json AS value_json
          FROM instant_live_query_triples AS owned
          JOIN instant_live_query_results_0026 AS result ON result.query_key = owned.query_key
          """
        )
        // The old ownership table first: it is the old results table's only child, so neither drop deletes a row
        // through a foreign key.
        try execute("DROP TABLE instant_live_query_triples")
        try execute("DROP TABLE instant_live_query_results")
        try execute("ALTER TABLE instant_live_query_results_0026 RENAME TO instant_live_query_results")
        try execute(Self.liveQueryOwnershipTableSQL)
        try execute(
          """
          INSERT INTO instant_live_query_triples (query_id, entity_id, attribute_id, value_json)
          SELECT query_id, entity_id, attribute_id, value_json
          FROM temp.instant_live_query_triples_0026
          ORDER BY query_id, entity_id, attribute_id, value_json
          """
        )
        let copiedRows = Int64(sqlite3_changes(connection.raw))
        try execute("DROP TABLE temp.instant_live_query_triples_0026")
        try execute(Self.liveQueryOwnershipIdentityIndexSQL)
        try execute(
          "INSERT OR IGNORE INTO instant_schema_migrations (name, applied_at_ms) VALUES (?, ?)",
          [.text(Self.compactLiveQueryOwnershipMigrationName), .int(Self.nowMilliseconds())]
        )
        return (rows, copiedRows, results)
      }
    } catch {
      startupTrace.failed(
        "sqlite.live-query-ownership-compaction",
        error: error,
        since: stopwatch,
        metadata: ["file": fileURL.lastPathComponent]
      )
      throw error
    }
    startupTrace.completed(
      "sqlite.live-query-ownership-compaction",
      since: stopwatch,
      metadata: ["file": fileURL.lastPathComponent]
    )
    guard let counts else { return }
    let milliseconds = (DispatchTime.now().uptimeNanoseconds - startedAt) / 1_000_000
    InstantDiagnostics.shared.record(
      .notice,
      subsystem: "instant-swift-data-core",
      category: "persistence",
      event: "sqlite.live-query-ownership.compacted",
      message: "Live-query ownership rows now name their result by id instead of repeating the query's key.",
      metadata: [
        "milliseconds": String(milliseconds),
        "path": fileURL.path,
        "results": String(counts.results),
        "rows": String(counts.copiedRows),
        "rowsWithoutAResult": String(counts.rows - counts.copiedRows),
      ]
    )
  }

  /// Whether the ownership table still has 0011's `query_key` column (#704).
  private func liveQueryOwnershipRowsCarryTheirQueryKey() throws -> Bool {
    try selectInt64(
      "SELECT COUNT(*) FROM pragma_table_info('instant_live_query_triples') WHERE name = 'query_key'"
    ) > 0
  }

  /// The id of the stored result for `key` (#704). Callers have just written or found the row.
  private func liveQueryResultIDWithoutTransaction(key: String) throws -> Int64 {
    guard
      let text = try selectScalar(
        "SELECT query_id FROM instant_live_query_results WHERE query_key = ? LIMIT 1",
        [.text(key)]
      ),
      let queryID = Int64(text)
    else {
      throw persistenceError(
        operation: "read a live-query result's id",
        message: "Live-query result '\(key)' has no stored row."
      )
    }
    return queryID
  }

  /// Reconciles reciprocal application declarations with the server's durable physical link.
  ///
  /// Runtime bootstrap normally hydrates only live-query and outbox-owned entities. Performing
  /// this transition in SQLite before that compact load keeps cold triples queryable after the
  /// duplicate attribute metadata is removed. The original outbox remains the caller's logical
  /// intent; only materialized storage and persisted query ownership use the canonical direction.
  private func reconcileDeclaredRelationStorageIfNeeded() throws {
    guard !declaredAttributes.isEmpty else { return }
    var droppedResults: [(queryKey: String, byteCount: Int64)] = []
    let didChange = try transaction {
      droppedResults = []
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
      // An unloaded result keeps the storage it was written in; drop them rather than reload one in the old shape
      // (#1006). Each query asks the server again when it next subscribes.
      try execute("DELETE FROM instant_unloaded_live_query_results")

      let obsoleteAttributeIDs = reconciliation.obsoleteAttributeIDs
      var triplesChanged = false
      var tripleRowID: Int64 = 0
      try snapshotApplicationMigrationTripleKeysWithoutTransaction(affectedAttributeIDs: obsoleteAttributeIDs)
      while let row = try nextApplicationMigrationTripleRowWithoutTransaction(after: tripleRowID) {
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
        try execute(
          "DELETE FROM instant_triples WHERE entity_id = ? AND attribute_id = ? AND value_json = ?",
          [.text(row.entityID), .text(row.attributeID), .text(row.valueJSON)]
        )
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
      while let row = try nextDeclaredRelationLiveQueryResultWithoutTransaction(
        after: liveQueryCursor
      ) {
        let result: InstantPersistedLiveQueryResult
        switch row {
        case let .oversized(queryKey, byteCount):
          // One cached result over the bound must not fail every open (#436): drop it, so its query refetches it.
          liveQueryCursor = queryKey
          try dropLiveQueryResultWithoutTransaction(queryKey: queryKey)
          droppedResults.append((queryKey, byteCount))
          liveQueryResultsChanged = true
          continue
        case let .decoded(decoded):
          result = decoded
        }
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
          try executeAttributeWrite(
            "INSERT OR REPLACE INTO instant_attributes (id, json) VALUES (?, ?)",
            [.text(attribute.id), .text(try encode(attribute))]
          )
        }
        for attributeID in durableByID.keys.sorted() where reconciledByID[attributeID] == nil {
          try executeAttributeWrite("DELETE FROM instant_attributes WHERE id = ?", [.text(attributeID)])
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
    Self.recordDroppedOversizedLiveQueryResults(droppedResults, pass: "declared relation storage reconciliation")
    guard didChange else { return }
    cachedState = nil
    cachedMaterializedStore = nil
  }

  /// Deletes one cached live-query result and its ownership rows (#436). Its facts stay in the store; the next refresh of
  /// its query stores the result again.
  private func dropLiveQueryResultWithoutTransaction(queryKey: String) throws {
    try execute(
      """
      DELETE FROM instant_live_query_triples
      WHERE query_id = (SELECT query_id FROM instant_live_query_results WHERE query_key = ?)
      """,
      [.text(queryKey)]
    )
    try execute("DELETE FROM instant_live_query_results WHERE query_key = ?", [.text(queryKey)])
    try forgetLiveQueryResultJSONStateWithoutTransaction(queryKey)
  }

  /// Logs each cached result an open-time pass dropped, once the pass has committed.
  private static func recordDroppedOversizedLiveQueryResults(
    _ dropped: [(queryKey: String, byteCount: Int64)],
    pass: String
  ) {
    for (queryKey, byteCount) in dropped {
      InstantDiagnostics.shared.record(
        .warning,
        subsystem: "instant-swift-data-core",
        category: "persistence",
        event: "live-query-result.oversized-dropped",
        message:
          "Dropped a cached live-query result over the open-time row bound instead of failing the store's open; its query refetches it.",
        metadata: [
          "byteCount": String(byteCount),
          "limitBytes": String(InstantAutomaticOutboxClaimLimits.maximumEncodedBodyBytes),
          "pass": pass,
          "queryKey": queryKey,
        ]
      )
    }
  }

  /// Reads every persisted result through a one-row keyset cursor.
  ///
  /// Ownership is an index of the encoded result, but an interrupted older build or imported
  /// fixture can drift on either side. Scanning all bounded result bodies lets reconciliation heal
  /// both an obsolete triple that exists only in JSON and obsolete ownership whose JSON is already
  /// canonical. A result over the row bound comes back unread (`.oversized`), for the pass to drop (#436).
  private func nextDeclaredRelationLiveQueryResultWithoutTransaction(
    after queryKey: String?
  ) throws -> InstantBoundedLiveQueryResultRow? {
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
    defer { finishStatement(statement) }
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
      return .oversized(queryKey: rowQueryKey, byteCount: bodyByteCount)
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
    return .decoded(result)
  }

  private func upsertCanonicalRelationTripleWithoutTransaction(
    _ triple: InstantTriple
  ) throws {
    try execute(
      """
      INSERT INTO instant_triples (entity_id, attribute_id, value_json, tx_id, tx_time_ms)
      VALUES (?, ?, ?, ?, ?)
      ON CONFLICT(entity_id, attribute_id, value_json) DO UPDATE SET
        tx_id = excluded.tx_id,
        tx_time_ms = excluded.tx_time_ms
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
    let queryID = try liveQueryResultIDWithoutTransaction(key: result.key)
    try execute("DELETE FROM instant_live_query_triples WHERE query_id = ?", [.int(queryID)])
    try executeRepeated(
      """
      INSERT INTO instant_live_query_triples
        (query_id, entity_id, attribute_id, value_json)
      VALUES (?, ?, ?, ?)
      """,
      bindings: ownership.sorted(by: LiveQueryOwnershipDiff.storeOrder).map { identity in
        [
          .int(queryID),
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
    var droppedResults: [(queryKey: String, byteCount: Int64)] = []
    let didChange = try transaction {
      droppedResults = []
      let alreadyApplied: String? = try selectScalar(
        """
        SELECT name FROM instant_application_persistence_migrations
        WHERE name = ?
        LIMIT 1
        """,
        [.text(migration.name)]
      )
      guard alreadyApplied == nil else { return false }
      // The migration rewrites stored results, not unloaded ones: drop those (#1006).
      try execute("DELETE FROM instant_unloaded_live_query_results")

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
        try executeAttributeWrite(
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
      try snapshotApplicationMigrationTripleKeysWithoutTransaction(affectedAttributeIDs: migration.affectedAttributeIDs)
      while let row = try nextApplicationMigrationTripleRowWithoutTransaction(after: tripleRowID) {
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
          SET value_json = ?, tx_id = ?, tx_time_ms = ?
          WHERE entity_id = ? AND attribute_id = ? AND value_json = ?
          """,
          [
            .text(try encode(migrated.value)),
            .text(migrated.txID),
            .int(migrated.txTime.milliseconds),
            .text(row.entityID),
            .text(row.attributeID),
            .text(row.valueJSON),
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
      var liveQueryResultsDropped = false
      var liveQueryCursor: String?
      while let row = try nextApplicationMigrationLiveQueryResultWithoutTransaction(
        after: liveQueryCursor,
        affectedAttributeIDs: migration.affectedAttributeIDs
      ) {
        let result: InstantPersistedLiveQueryResult
        switch row {
        case let .oversized(queryKey, byteCount):
          // A cached result over the bound is refetched rather than migrated (#436).
          liveQueryCursor = queryKey
          try dropLiveQueryResultWithoutTransaction(queryKey: queryKey)
          droppedResults.append((queryKey, byteCount))
          liveQueryResultsDropped = true
          continue
        case let .decoded(decoded):
          result = decoded
        }
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
          // The migration grew the cached result past the bound: refetch it rather than fail the open (#436).
          try dropLiveQueryResultWithoutTransaction(queryKey: result.key)
          droppedResults.append((result.key, Int64(encodedMigratedResult.utf8.count)))
          liveQueryResultsDropped = true
          continue
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

      if triplesChanged || attributesChanged || liveQueryResultsChanged || liveQueryResultsDropped {
        try execute("DELETE FROM instant_query_cache")
      }
      if triplesChanged || liveQueryResultsChanged || liveQueryResultsDropped {
        _ = try bumpMetadataRevisionWithoutTransaction(Self.storeRevisionKey)
      }
      if attributesChanged {
        _ = try bumpMetadataRevisionWithoutTransaction(Self.attributeRevisionKey)
      }
      if outboxChanged {
        _ = try bumpMetadataRevisionWithoutTransaction(Self.outboxRevisionKey)
      }
      if liveQueryResultsChanged || liveQueryResultsDropped {
        _ = try bumpMetadataRevisionWithoutTransaction(Self.queryResultRevisionKey)
      }
      try execute(
        """
        INSERT INTO instant_application_persistence_migrations (name, applied_at_ms)
        VALUES (?, ?)
        """,
        [.text(migration.name), .int(Self.nowMilliseconds())]
      )
      return didChangeAny || liveQueryResultsDropped
    }
    Self.recordDroppedOversizedLiveQueryResults(droppedResults, pass: "application migration '\(migration.name)'")
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
    defer { finishStatement(statement) }
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

  /// The keys of the facts of `affectedAttributeIDs`, in key order, taken before a pass changes any of them (#1121): the
  /// fact table is keyed by the fact itself, so a pass that rewrote a fact's value would meet it again under its new
  /// key if it walked the table. The pass walks this snapshot instead, as it walked the rowids before.
  private func snapshotApplicationMigrationTripleKeysWithoutTransaction(affectedAttributeIDs: Set<String>) throws {
    let sortedAttributeIDs = affectedAttributeIDs.sorted()
    let placeholders = Array(repeating: "?", count: sortedAttributeIDs.count).joined(separator: ", ")
    try execute("DROP TABLE IF EXISTS temp.instant_migration_triple_keys")
    try execute(
      """
      CREATE TEMP TABLE instant_migration_triple_keys AS
      SELECT entity_id, attribute_id, value_json FROM instant_triples
      WHERE attribute_id IN (\(placeholders))
      ORDER BY entity_id, attribute_id, value_json
      """,
      sortedAttributeIDs.map(SQLiteBinding.text)
    )
  }

  /// The next fact of the pass's snapshot after `rowID` that is still stored, decoded.
  private func nextApplicationMigrationTripleRowWithoutTransaction(
    after rowID: Int64
  ) throws -> InstantApplicationMigrationTripleRow? {
    var statement: OpaquePointer?
    try prepare(
      """
      SELECT keys.rowid, keys.entity_id, keys.attribute_id, keys.value_json, length(CAST(triples.json AS BLOB))
      FROM temp.instant_migration_triple_keys AS keys
      JOIN instant_triples AS triples
        ON triples.entity_id = keys.entity_id
        AND triples.attribute_id = keys.attribute_id
        AND triples.value_json = keys.value_json
      WHERE keys.rowid > ?
      ORDER BY keys.rowid
      LIMIT 1
      """,
      statement: &statement
    )
    defer { finishStatement(statement) }
    try bind([.int(rowID)], to: statement)
    let code = sqlite3_step(statement)
    if code == SQLITE_DONE {
      try execute("DROP TABLE IF EXISTS temp.instant_migration_triple_keys")
      return nil
    }
    guard code == SQLITE_ROW else {
      throw persistenceError(
        operation: "read local persistence migration triple",
        message: lastErrorMessage()
      )
    }
    let matchingRowID = sqlite3_column_int64(statement, 0)
    let entityID = String(cString: sqlite3_column_text(statement, 1))
    let attributeID = String(cString: sqlite3_column_text(statement, 2))
    let valueJSON = String(cString: sqlite3_column_text(statement, 3))
    let bodyByteCount = sqlite3_column_int64(statement, 4)
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
      "SELECT json FROM instant_triples WHERE entity_id = ? AND attribute_id = ? AND value_json = ? LIMIT 1",
      [.text(entityID), .text(attributeID), .text(valueJSON)]
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
      entityID: entityID,
      attributeID: attributeID,
      valueJSON: valueJSON,
      triple: try decoder.decode(InstantTriple.self, from: data)
    )
  }

  /// A result over the row bound comes back unread (`.oversized`), for the migration to drop (#436).
  private func nextApplicationMigrationLiveQueryResultWithoutTransaction(
    after queryKey: String?,
    affectedAttributeIDs: Set<String>
  ) throws -> InstantBoundedLiveQueryResultRow? {
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
        WHERE owned.query_id = result.query_id
          AND owned.attribute_id IN (\(placeholders))
      )
      \(cursorClause)
      ORDER BY result.query_key
      LIMIT 1
      """
    try prepare(sql, statement: &statement)
    defer { finishStatement(statement) }
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
      return .oversized(queryKey: rowQueryKey, byteCount: bodyByteCount)
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
    return .decoded(result)
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
      let computedReceipt = try optimisticEffectFingerprint(of: row.mutation)
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
    connection.close()
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
    confirmingClaimantID: String?,
    excludesWatermarkRoots: Bool = false,
    receiptPatchMutationIDs: Set<String> = []
  ) throws -> InstantServerApplyPlanLoad {
    let energy = InstantEnergyMeter.begin(.serverApplyPlan); defer { energy.end() }
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
          confirming_claimant_id, excludes_watermark_roots
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
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
          .int(excludesWatermarkRoots ? 1 : 0),
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
      for mutationID in receiptPatchMutationIDs.sorted() {
        try execute(
          """
          INSERT INTO instant_server_apply_receipt_patches (plan_id, mutation_id)
          VALUES (?, ?)
          """,
          [.text(planID), .text(mutationID)]
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
      let componentBodyCount = Int(try selectInt64(
        """
        SELECT COUNT(*) FROM instant_server_apply_rows
        WHERE plan_id = ? AND requires_body = 1 AND is_component_body = 1
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
          plannedBodyByteCount: bodyByteCount,
          plannedComponentBodyCount: componentBodyCount
        )
      )
    }
    if case let .ready(plan) = result {
      serverApplyMetrics.planCount += 1
      serverApplyMetrics.plannedBodyCount += plan.plannedBodyCount
      serverApplyMetrics.plannedComponentBodyCount += plan.plannedComponentBodyCount
      serverApplyMetrics.receiptPatchCount += receiptPatchMutationIDs.count
      serverApplyMetrics.removedFailedOverlayCount += Int(try selectInt64(
        """
        SELECT COUNT(*) FROM instant_server_apply_rows AS planned
        JOIN instant_outbox AS outbox ON outbox.mutation_id = planned.mutation_id
        WHERE planned.plan_id = ? AND planned.is_component_body = 0 AND planned.requires_body = 1
          AND outbox.status = 'failed'
        """,
        [.text(plan.id)]
      ))
      serverApplyMetrics.plannedBodyByteCount += plan.plannedBodyByteCount
    }
    return result
  }

  // MARK: - Quarantined mutations (#696)

  /// What a quarantined mutation's lifecycle observers are told (#696).
  static let quarantinedMutationFailureMessage =
    "Held aside at launch in instant_outbox_quarantined: it has no SQLite-owned preparation receipt, so its local "
    + "cache effect is unknown. The library sends it only when asked to send it again."

  /// The rows ``synchronizationBlocker()`` reports: an active optimistic effect with no SQLite-owned receipt.
  private static let receiptlessRetainedMutationPredicate =
    "optimistic_overlay_active = 1 AND optimistic_effect_receipt_fingerprint IS NULL"

  /// Moves each retained mutation that has no SQLite-owned preparation receipt, whole, out of the outbox and into
  /// `instant_outbox_quarantined`, in one SQLite transaction, and returns their IDs in outbox order (#696).
  ///
  /// These are exactly the rows ``synchronizationBlocker()`` reports, so it reports none afterward. Up to 1.9.9 the
  /// first of them refused every live connection, forever, and every later write waited behind it: a store an earlier
  /// version wrote held five, and thousands of valid writes made after them never left the device. Each row keeps its
  /// body byte for byte and every column of its outbox row as one JSON object; its derived write-key and effect-entity
  /// index rows leave with it, as they do whenever a row leaves the outbox. Local triples are not touched: what such a
  /// mutation materialized stays until a server result replaces it, which it now can, because no unproven row protects
  /// every server retraction any more. The library never deletes a quarantined row.
  ///
  /// A store with no such row is not written to: the check is one indexed read, and the table is never created.
  @discardableResult
  func quarantineRetainedMutationsWithoutPreparationReceipt(
    now: InstantTimestamp
  ) throws -> [String] {
    guard try synchronizationBlocker() != nil else { return [] }
    let predicate = Self.receiptlessRetainedMutationPredicate
    let quarantinedIDs: [String] = try transaction {
      let ids = try selectStrings(
        """
        SELECT mutation_id
        FROM instant_outbox INDEXED BY instant_outbox_synchronization_blocker_idx
        WHERE \(predicate)
        ORDER BY created_at_ms, mutation_id
        """
      )
      guard !ids.isEmpty else { return [] }
      try ensureQuarantinedOutboxTableWithoutTransaction()
      let rowJSON = try outboxRowJSONObjectExpressionWithoutTransaction()
      for id in ids {
        try execute(
          """
          INSERT INTO instant_outbox_quarantined (
            mutation_id, reason, quarantined_at_ms, created_at_ms, status, json, outbox_row_json
          )
          SELECT mutation_id, ?, ?, created_at_ms, status, json, \(rowJSON)
          FROM instant_outbox
          WHERE mutation_id = ? AND \(predicate)
          """,
          [
            .text(InstantQuarantinedMutation.Reason.noPreparationReceipt.rawValue),
            .int(now.milliseconds),
            .text(id),
          ]
        )
        guard try selectInt64("SELECT changes()") == 1 else {
          throw persistenceError(
            operation: "quarantine a retained mutation without a preparation receipt",
            message: "SQLite did not copy outbox row '\(id)' into the quarantine."
          )
        }
        try execute("DELETE FROM instant_outbox_write_keys WHERE mutation_id = ?", [.text(id)])
        try execute("DELETE FROM instant_outbox_effect_entities WHERE mutation_id = ?", [.text(id)])
        try execute(
          "DELETE FROM instant_outbox WHERE mutation_id = ? AND \(predicate)",
          [.text(id)]
        )
        guard try selectInt64("SELECT changes()") == 1 else {
          throw persistenceError(
            operation: "quarantine a retained mutation without a preparation receipt",
            message: "SQLite did not remove outbox row '\(id)' after copying it into the quarantine."
          )
        }
      }
      _ = try bumpMetadataRevisionWithoutTransaction(Self.outboxRevisionKey)
      return ids
    }
    if !quarantinedIDs.isEmpty {
      InstantDiagnostics.shared.record(
        .error,
        subsystem: "instant-swift-data-core",
        category: "outbox",
        event: "outbox.mutation.quarantined-no-preparation-receipt",
        message: """
          Moved \(quarantinedIDs.count) retained mutation\(quarantinedIDs.count == 1 ? "" : "s") without a \
          preparation receipt into the quarantine; every other write synchronizes in its order.
          """,
        metadata: [
          "count": String(quarantinedIDs.count),
          "firstMutationID": quarantinedIDs[0],
          "mutationIDs": quarantinedIDs.prefix(20).joined(separator: ","),
          "table": "instant_outbox_quarantined",
        ]
      )
    }
    return quarantinedIDs
  }

  /// Bootstrap's call of ``quarantineRetainedMutationsWithoutPreparationReceipt(now:)`` (#696). With
  /// `.blockSynchronization` it does nothing. A failure rolls back, is recorded, and leaves the rows where they were,
  /// so the blocker stops synchronization as it did up to 1.9.9; a launch never fails because of this step.
  @discardableResult
  func quarantineRetainedMutationsAtBootstrap(
    recovery: InstantRetainedMutationRecovery,
    now: InstantTimestamp
  ) -> [String] {
    guard recovery == .quarantine else { return [] }
    do {
      return try quarantineRetainedMutationsWithoutPreparationReceipt(now: now)
    } catch {
      InstantDiagnostics.shared.record(
        error: error,
        subsystem: "instant-swift-data-core",
        category: "outbox",
        event: "outbox.mutation.quarantine-failed",
        message:
          "Could not move retained mutations without a preparation receipt into the quarantine; they still block synchronization."
      )
      return []
    }
  }

  /// The oldest `limit` quarantined mutations still held, in the order they had in the outbox (#696). A row sent
  /// again, or whose reason this version does not know (a later version wrote it), is left out.
  func quarantinedOutboxMutations(limit: Int) throws -> [InstantQuarantinedMutation] {
    guard limit > 0 else { return [] }
    return try readTransaction {
      try heldQuarantinedOutboxMutationsWithoutTransaction(
        """
        SELECT mutation_id, reason, quarantined_at_ms, created_at_ms, status, json, outbox_row_json
        FROM instant_outbox_quarantined
        WHERE resolution IS NULL
        ORDER BY created_at_ms, mutation_id, quarantine_id
        LIMIT ?
        """,
        [.int(Int64(limit))]
      )
    }
  }

  /// How many quarantined mutations are still held (#696).
  func quarantinedOutboxMutationCount() throws -> Int {
    try readTransaction {
      guard try quarantinedOutboxTableExistsWithoutTransaction() else { return 0 }
      return Int(
        try selectInt64("SELECT COUNT(*) FROM instant_outbox_quarantined WHERE resolution IS NULL")
      )
    }
  }

  /// The held quarantined mutation with this ID, or nil (#696).
  func heldQuarantinedOutboxMutation(id: String) throws -> InstantQuarantinedMutation? {
    try readTransaction {
      try heldQuarantinedOutboxMutationsWithoutTransaction(
        """
        SELECT mutation_id, reason, quarantined_at_ms, created_at_ms, status, json, outbox_row_json
        FROM instant_outbox_quarantined
        WHERE resolution IS NULL AND mutation_id = ?
        ORDER BY quarantine_id
        LIMIT 1
        """,
        [.text(id)]
      ).first
    }
  }

  /// Records that the held rows with this ID were sent again (#696). The rows stay, with `resolution` saying so;
  /// returns how many it marked.
  @discardableResult
  func markQuarantinedOutboxMutationSentAgain(id: String, now: InstantTimestamp) throws -> Int {
    try transaction {
      guard try quarantinedOutboxTableExistsWithoutTransaction() else { return 0 }
      try execute(
        """
        UPDATE instant_outbox_quarantined
        SET resolution = 'sent-again', resolved_at_ms = ?
        WHERE mutation_id = ? AND resolution IS NULL
        """,
        [.int(now.milliseconds), .text(id)]
      )
      return Int(try selectInt64("SELECT changes()"))
    }
  }

  private func heldQuarantinedOutboxMutationsWithoutTransaction(
    _ sql: String,
    _ bindings: [SQLiteBinding]
  ) throws -> [InstantQuarantinedMutation] {
    guard try quarantinedOutboxTableExistsWithoutTransaction() else { return [] }
    var statement: OpaquePointer?
    try prepare(sql, statement: &statement)
    defer { finishStatement(statement) }
    try bind(bindings, to: statement)
    var mutations: [InstantQuarantinedMutation] = []
    while true {
      let code = sqlite3_step(statement)
      if code == SQLITE_DONE { return mutations }
      guard code == SQLITE_ROW,
        let idBytes = sqlite3_column_text(statement, 0),
        let reasonBytes = sqlite3_column_text(statement, 1),
        let statusBytes = sqlite3_column_text(statement, 4),
        let bodyBytes = sqlite3_column_text(statement, 5),
        let rowBytes = sqlite3_column_text(statement, 6)
      else {
        throw persistenceError(operation: "read quarantined mutations", message: lastErrorMessage())
      }
      guard let reason = InstantQuarantinedMutation.Reason(rawValue: String(cString: reasonBytes)) else {
        continue
      }
      let body = String(cString: bodyBytes)
      mutations.append(
        InstantQuarantinedMutation(
          id: String(cString: idBytes),
          reason: reason,
          quarantinedAt: InstantTimestamp(milliseconds: sqlite3_column_int64(statement, 2)),
          createdAt: InstantTimestamp(milliseconds: sqlite3_column_int64(statement, 3)),
          status: InstantMutationStatus(rawValue: String(cString: statusBytes)),
          body: body,
          outboxRowJSON: String(cString: rowBytes),
          mutation: try? decodeOutboxBody(body) as PendingMutation
        )
      )
    }
  }

  private func quarantinedOutboxTableExistsWithoutTransaction() throws -> Bool {
    try selectInt64(
      "SELECT COUNT(*) FROM sqlite_master WHERE type = 'table' AND name = 'instant_outbox_quarantined'"
    ) != 0
  }

  /// Created by the first quarantine, not by a migration, so a store that never needs it never gains it (#696).
  /// `quarantine_id` keeps a mutation quarantined twice as two rows: nothing in the table is ever replaced. A row stays
  /// after Send Again, with `resolution` saying so; until then `resolution` is NULL and the row is held.
  private func ensureQuarantinedOutboxTableWithoutTransaction() throws {
    try execute(
      """
      CREATE TABLE IF NOT EXISTS instant_outbox_quarantined (
        quarantine_id INTEGER PRIMARY KEY,
        mutation_id TEXT NOT NULL,
        reason TEXT NOT NULL,
        quarantined_at_ms INTEGER NOT NULL,
        created_at_ms INTEGER NOT NULL,
        status TEXT NOT NULL,
        json TEXT NOT NULL,
        outbox_row_json TEXT NOT NULL,
        resolution TEXT,
        resolved_at_ms INTEGER
      )
      """
    )
    try execute(
      """
      CREATE INDEX IF NOT EXISTS instant_outbox_quarantined_order_idx
      ON instant_outbox_quarantined (resolution, created_at_ms, mutation_id, quarantine_id)
      """
    )
  }

  /// A `json_object(...)` expression of every column `instant_outbox` has in this store, read from its schema, so a
  /// quarantined row keeps the columns of whichever version wrote it. A BLOB, which no outbox column holds today, is
  /// kept as its hex digits.
  private func outboxRowJSONObjectExpressionWithoutTransaction() throws -> String {
    let columns = try selectStrings("SELECT name FROM pragma_table_info('instant_outbox') ORDER BY cid")
    guard !columns.isEmpty,
      columns.allSatisfy({ name in
        !name.isEmpty && name.unicodeScalars.allSatisfy { $0 == "_" || CharacterSet.alphanumerics.contains($0) }
      })
    else {
      throw persistenceError(
        operation: "quarantine a retained mutation without a preparation receipt",
        message: "instant_outbox has a column name the quarantine cannot copy: \(columns)."
      )
    }
    let pairs = columns.map { column in
      "'\(column)', CASE typeof(\"\(column)\") WHEN 'blob' THEN json_object('hex', hex(\"\(column)\")) "
        + "ELSE \"\(column)\" END"
    }
    return "json_object(\(pairs.joined(separator: ", ")))"
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
  ///
  /// A pending write of an entity protects the retractions of its facts, so an entity that left a result is collected
  /// whole or kept whole (#259). A retraction in a slot the server cleared (`clearedSlots`) is protected only by a
  /// pending write of that slot, and not by a write the apply at `processedTransactionID` prunes at the watermark
  /// (#431): a write of another slot of the entity, or the write this apply confirms, no longer keeps a value the
  /// server cleared, as upstream drops a mutation's optimistic layer once `processed-tx-id` covers it. A protected
  /// retraction is dropped for good, because the result it came from is stored without the fact. Every other
  /// retraction keeps its protection, including by the write this apply confirms: those retract a value the batch
  /// replaces or a fact of an entity that left a result, and letting them through made every confirming refresh
  /// republish the entities its writes touched (Scribe's soak published 1,274 store changes for 873 writes).
  func protectingServerRetractions(
    _ operations: [InstantTripleOperation],
    processedTransactionID: String? = nil,
    clearedSlots: Set<InstantVisibleWriteKey> = []
  ) throws -> [InstantTripleOperation] {
    try readTransaction {
      try protectingServerRetractionsWithoutTransaction(
        operations,
        processedTransactionID: processedTransactionID,
        clearedSlots: clearedSlots
      )
    }
  }

  func protectingServerRetractions(
    _ operations: [InstantTripleOperation],
    expectedOutboxRevision: Int64,
    processedTransactionID: String? = nil,
    clearedSlots: Set<InstantVisibleWriteKey> = []
  ) throws -> [InstantTripleOperation]? {
    try readTransaction {
      guard try loadMetadataRevisionWithoutTransaction(Self.outboxRevisionKey)
        == expectedOutboxRevision
      else { return nil }
      return try protectingServerRetractionsWithoutTransaction(
        operations,
        processedTransactionID: processedTransactionID,
        clearedSlots: clearedSlots
      )
    }
  }

  private func protectingServerRetractionsWithoutTransaction(
    _ operations: [InstantTripleOperation],
    processedTransactionID: String?,
    clearedSlots: Set<InstantVisibleWriteKey>
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
    // The writes this apply prunes at the watermark, selected as the server-apply reduction selects them, which protect
    // no cleared slot.
    let pruned = processedTransactionID.map {
      Self.serverApplyReductionPrunablePredicate(processedTransactionID: $0, alias: "outbox")
    }
    let survivorSQL = pruned.map { "AND NOT \($0.sql)" } ?? ""
    let survivorBindings = pruned?.bindings ?? []
    var protected: [InstantTripleOperation] = []
    protected.reserveCapacity(operations.count)
    for operation in operations {
      guard case let .retract(triple) = operation else {
        protected.append(operation)
        continue
      }
      let hasOwner: Bool
      if clearedSlots.contains(InstantVisibleWriteKey(entityID: triple.entityID, attributeID: triple.attributeID)) {
        hasOwner = try selectInt64(
          """
          SELECT EXISTS(
            SELECT 1
            FROM instant_outbox_write_keys AS write_keys
            JOIN instant_outbox AS outbox
              ON outbox.mutation_id = write_keys.mutation_id
            WHERE write_keys.entity_id = ?
              AND write_keys.attribute_id = ?
              AND outbox.optimistic_overlay_active = 1
              AND outbox.status != ?
              \(survivorSQL)
            LIMIT 1
          )
          """,
          [
            .text(triple.entityID),
            .text(triple.attributeID),
            .text(InstantMutationStatus.failed.rawValue),
          ] + survivorBindings
        ) != 0
      } else {
        hasOwner = try selectInt64(
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
      }
      if !hasOwner { protected.append(operation) }
    }
    return protected
  }

  /// Loads what `InstantRuntime` needs to decide which facts of one server apply can change the authoritative base
  /// beneath the pending writes (#296), or the reason the whole-component rebase must run instead.
  ///
  /// Upstream `Reactor.js` keeps each query's server result in its own store and reapplies pending mutations on top
  /// (`dataForQuery`, `_applyOptimisticUpdates`). Swift keeps one materialized store, so it peels and replays the
  /// connected component instead. That replay changes nothing when every server fact already holds beneath the
  /// overlays, which is the common frame while a large outbox drains. Deciding that needs, for each entity the frame
  /// names, whether a pending write that survives this apply touches it, and for each slot such a write inserts, the
  /// first such write's durable receipt (its before-image is the base value). Everything is read in one transaction
  /// at the revisions the caller's seed was taken at.
  /// - Parameter absentEntityIDs: The frame's entities the store does not show. For each one a surviving write touches,
  ///   the context names the write that deletes it last, if any (#932).
  func loadServerApplyReductionContext(
    slots: [String: Set<String>],
    reverseLinkSlots: Set<InstantVisibleWriteKey> = [],
    absentEntityIDs: Set<String> = [],
    processedTransactionID: String,
    expectedStoreRevision: Int64,
    expectedAttributeRevision: Int64,
    expectedOutboxRevision: Int64,
    expectedQueryResultRevision: Int64
  ) throws -> InstantServerApplyReductionLoad {
    // Every query below is an indexed probe that stops at its first match, so deciding a frame costs the same with 30
    // pending writes as with 2,500.
    let load: InstantServerApplyReductionLoad = try readTransaction {
      guard
        try loadMetadataRevisionWithoutTransaction(Self.storeRevisionKey) == expectedStoreRevision,
        try loadMetadataRevisionWithoutTransaction(Self.attributeRevisionKey) == expectedAttributeRevision,
        try loadMetadataRevisionWithoutTransaction(Self.outboxRevisionKey) == expectedOutboxRevision,
        try loadMetadataRevisionWithoutTransaction(Self.queryResultRevisionKey)
          == expectedQueryResultRevision
      else { return .ineligible(.revisionChanged) }

      // Rows whose effect a full rebase treats specially: a failed overlay is removed, a global or unproven receipt
      // cannot be scoped, an old delivery-metadata row has no trustworthy write keys, and a transport confirmation
      // without a transaction id is replaced by the server's coverage.
      // Refused writes whose overlays are still on the store: up to a bound, the reduction removes them itself.
      var failedPositions: [InstantOutboxDeliveryPosition] = []
      do {
        var statement: OpaquePointer?
        try prepare(
          """
          SELECT mutation_id, created_at_ms
          FROM instant_outbox INDEXED BY instant_outbox_server_apply_failed_idx
          WHERE status = 'failed' AND optimistic_overlay_active = 1
          ORDER BY created_at_ms, mutation_id
          LIMIT ?
          """,
          statement: &statement
        )
        defer { finishStatement(statement) }
        try bind([.int(Int64(InstantServerApplyReductionLimits.maximumFailedOverlays + 1))], to: statement)
        while sqlite3_step(statement) == SQLITE_ROW {
          guard let idBytes = sqlite3_column_text(statement, 0) else { continue }
          failedPositions.append(
            InstantOutboxDeliveryPosition(
              createdAtMilliseconds: sqlite3_column_int64(statement, 1),
              mutationID: String(cString: idBytes)
            )
          )
        }
      }
      guard failedPositions.count <= InstantServerApplyReductionLimits.maximumFailedOverlays else {
        return .ineligible(.failedOverlay)
      }
      let unscoped: [(sql: String, bindings: [SQLiteBinding])] = [
        (
          """
          SELECT EXISTS(
            SELECT 1 FROM instant_outbox INDEXED BY instant_outbox_global_effect_order_idx
            WHERE optimistic_overlay_active = 1 AND optimistic_effect_is_global = 1 LIMIT 1
          )
          """,
          []
        ),
        (
          """
          SELECT EXISTS(
            SELECT 1 FROM instant_outbox INDEXED BY instant_outbox_synchronization_blocker_idx
            WHERE optimistic_overlay_active = 1 AND optimistic_effect_receipt_fingerprint IS NULL LIMIT 1
          )
          """,
          []
        ),
        (
          """
          SELECT EXISTS(
            SELECT 1 FROM instant_outbox INDEXED BY instant_outbox_effect_normalization_idx
            WHERE optimistic_overlay_active = 1
              AND (optimistic_effect_metadata_version < ? OR optimistic_effect_metadata_version > ?)
            LIMIT 1
          )
          """,
          [
            .int(Int64(InstantOptimisticEffectFootprint.currentVersion)),
            .int(Int64(InstantOptimisticEffectFootprint.currentVersion)),
          ]
        ),
        (
          """
          SELECT EXISTS(
            SELECT 1 FROM instant_outbox
            WHERE status IN (?, ?) AND delivery_metadata_version < ? AND optimistic_overlay_active = 1
            LIMIT 1
          )
          """,
          [
            .text(InstantMutationStatus.pending.rawValue),
            .text(InstantMutationStatus.confirmed.rawValue),
            .int(Int64(InstantOutboxDeliveryMetadata.currentVersion)),
          ]
        ),
        (
          """
          SELECT EXISTS(
            SELECT 1 FROM instant_outbox INDEXED BY instant_outbox_server_apply_watermark_idx
            WHERE status = ? AND optimistic_overlay_active = 1
              AND COALESCE(server_transaction_id, '') = '' AND COALESCE(confirmation_source, '') = ?
            LIMIT 1
          )
          """,
          [
            .text(InstantMutationStatus.confirmed.rawValue),
            .text(InstantMutationConfirmationSource.serverTransport.rawValue),
          ]
        ),
      ]
      for check in unscoped where try selectInt64(check.sql, check.bindings) != 0 {
        return .ineligible(.unscopedOverlay)
      }

      let prunable = Self.serverApplyReductionPrunablePredicate(
        processedTransactionID: processedTransactionID,
        alias: "outbox"
      )
      // The watermark may prune only a prefix of the active overlays. A pending write older than a pruned one would
      // be replayed on top of it by the full rebase, which can change what the device shows.
      var newestPrunedStatement: OpaquePointer?
      try prepare(
        """
        SELECT outbox.created_at_ms, outbox.mutation_id
        FROM instant_outbox AS outbox INDEXED BY instant_outbox_server_apply_watermark_idx
        WHERE outbox.optimistic_overlay_active = 1 AND \(prunable.sql)
        ORDER BY outbox.created_at_ms DESC, outbox.mutation_id DESC
        LIMIT 1
        """,
        statement: &newestPrunedStatement
      )
      defer { finishStatement(newestPrunedStatement) }
      try bind(prunable.bindings, to: newestPrunedStatement)
      if sqlite3_step(newestPrunedStatement) == SQLITE_ROW,
        let newestPrunedIDBytes = sqlite3_column_text(newestPrunedStatement, 1)
      {
        let newestPrunedMilliseconds = sqlite3_column_int64(newestPrunedStatement, 0)
        let newestPrunedID = String(cString: newestPrunedIDBytes)
        let olderSurvivorExists = try selectInt64(
          """
          SELECT EXISTS(
            SELECT 1 FROM instant_outbox AS outbox INDEXED BY instant_outbox_global_effect_order_idx
            WHERE outbox.optimistic_overlay_active = 1 AND outbox.optimistic_effect_is_global = 0
              AND (
                outbox.created_at_ms < ?
                OR (outbox.created_at_ms = ? AND outbox.mutation_id < ?)
              )
              AND outbox.status != 'failed' AND NOT \(prunable.sql)
            LIMIT 1
          )
          """,
          [.int(newestPrunedMilliseconds), .int(newestPrunedMilliseconds), .text(newestPrunedID)]
            + prunable.bindings
        ) != 0
        if olderSurvivorExists { return .ineligible(.nonPrefixWatermark) }
      }

      let remaining = """
        outbox.optimistic_overlay_active = 1 AND outbox.status != 'failed' AND NOT \(prunable.sql)
        """
      var context = InstantServerApplyReductionContext()
      for entityID in slots.keys.sorted() {
        let isShadowed = try selectInt64(
          """
          SELECT EXISTS(
            SELECT 1
            FROM instant_outbox_effect_entities AS effects
              INDEXED BY instant_outbox_effect_entities_lookup_idx
            JOIN instant_outbox AS outbox ON outbox.mutation_id = effects.mutation_id
            WHERE effects.entity_id = ? AND \(remaining)
            LIMIT 1
          )
          """,
          [.text(entityID)] + prunable.bindings
        ) != 0
        if isShadowed { context.shadowedEntityIDs.insert(entityID) }
      }

      // The surviving writes that insert one slot, walked in delivery order along the effect index (the write-key
      // index is not ordered by creation), stopping at the first.
      func writer(
        of attributeID: String,
        on entityID: String,
        newest: Bool,
        after position: InstantOutboxDeliveryPosition? = nil
      ) throws -> InstantOutboxDeliveryPosition? {
        var statement: OpaquePointer?
        let afterSQL = position == nil
          ? ""
          : """
            AND (
              effects.created_at_ms > ?
              OR (effects.created_at_ms = ? AND effects.mutation_id > ?)
            )
            """
        try prepare(
          """
          SELECT effects.mutation_id, effects.created_at_ms
          FROM instant_outbox_effect_entities AS effects
            INDEXED BY instant_outbox_effect_entities_lookup_idx
          JOIN instant_outbox AS outbox ON outbox.mutation_id = effects.mutation_id
          WHERE effects.entity_id = ? AND \(remaining)
            AND EXISTS(
              SELECT 1 FROM instant_outbox_write_keys AS write_keys
              WHERE write_keys.mutation_id = effects.mutation_id
                AND write_keys.entity_id = ? AND write_keys.attribute_id = ?
            )
            \(afterSQL)
          ORDER BY effects.created_at_ms \(newest ? "DESC" : "ASC"), effects.mutation_id \(newest ? "DESC" : "ASC")
          LIMIT 1
          """,
          statement: &statement
        )
        defer { finishStatement(statement) }
        let afterBindings: [SQLiteBinding] = position.map {
          [.int($0.createdAtMilliseconds), .int($0.createdAtMilliseconds), .text($0.mutationID)]
        } ?? []
        try bind(
          [.text(entityID)] + prunable.bindings + [.text(entityID), .text(attributeID)] + afterBindings,
          to: statement
        )
        guard sqlite3_step(statement) == SQLITE_ROW,
          let mutationIDBytes = sqlite3_column_text(statement, 0)
        else { return nil }
        return InstantOutboxDeliveryPosition(
          createdAtMilliseconds: sqlite3_column_int64(statement, 1),
          mutationID: String(cString: mutationIDBytes)
        )
      }

      var bodyIDs: Set<String> = []
      for entityID in context.shadowedEntityIDs.sorted() {
        var hasFirstWriter = false
        for attributeID in (slots[entityID] ?? []).sorted() {
          guard let first = try writer(of: attributeID, on: entityID, newest: false) else { continue }
          hasFirstWriter = true
          let slot = InstantVisibleWriteKey(entityID: entityID, attributeID: attributeID)
          context.firstWriterBySlot[slot] = first.mutationID
          bodyIDs.insert(first.mutationID)
          if let last = try writer(of: attributeID, on: entityID, newest: true) {
            context.lastWriterBySlot[slot] = last.mutationID
            bodyIDs.insert(last.mutationID)
          }
        }
        guard hasFirstWriter else { continue }
        // The earliest surviving write on this entity: a first writer that is also the entity's first overlay has no
        // earlier pending write beneath it that could have retracted or deleted the slot.
        let firstOverlay = try selectStrings(
          """
          SELECT effects.mutation_id
          FROM instant_outbox_effect_entities AS effects
            INDEXED BY instant_outbox_effect_entities_lookup_idx
          JOIN instant_outbox AS outbox ON outbox.mutation_id = effects.mutation_id
          WHERE effects.entity_id = ? AND \(remaining)
          ORDER BY effects.created_at_ms, effects.mutation_id
          LIMIT 1
          """,
          [.text(entityID)] + prunable.bindings
        )
        if let firstOverlay = firstOverlay.first {
          context.firstOverlayByEntity[entityID] = firstOverlay
          // Its receipt shows whether it created the entity.
          bodyIDs.insert(firstOverlay)
        }
      }
      // #932: the latest surviving write on each shadowed entity the store does not show; its body says below whether
      // it deletes the entity. Only those: a body per shadowed entity would bring a large frame to the body bound.
      var lastOverlayByEntity: [String: String] = [:]
      for entityID in context.shadowedEntityIDs.intersection(absentEntityIDs).sorted() {
        let lastOverlay = try selectStrings(
          """
          SELECT effects.mutation_id
          FROM instant_outbox_effect_entities AS effects
            INDEXED BY instant_outbox_effect_entities_lookup_idx
          JOIN instant_outbox AS outbox ON outbox.mutation_id = effects.mutation_id
          WHERE effects.entity_id = ? AND \(remaining)
          ORDER BY effects.created_at_ms DESC, effects.mutation_id DESC
          LIMIT 1
          """,
          [.text(entityID)] + prunable.bindings
        )
        if let lastOverlay = lastOverlay.first {
          lastOverlayByEntity[entityID] = lastOverlay
          bodyIDs.insert(lastOverlay)
        }
        if context.firstOverlayByEntity[entityID] == nil {
          let firstOverlay = try selectStrings(
            """
            SELECT effects.mutation_id
            FROM instant_outbox_effect_entities AS effects
              INDEXED BY instant_outbox_effect_entities_lookup_idx
            JOIN instant_outbox AS outbox ON outbox.mutation_id = effects.mutation_id
            WHERE effects.entity_id = ? AND \(remaining)
            ORDER BY effects.created_at_ms, effects.mutation_id
            LIMIT 1
            """,
            [.text(entityID)] + prunable.bindings
          )
          if let firstOverlay = firstOverlay.first {
            context.firstOverlayByEntity[entityID] = firstOverlay
            bodyIDs.insert(firstOverlay)
          }
        }
      }
      // Each refused write's slots (its write keys), and the next surviving writer of each.
      for failed in failedPositions {
        context.failedOverlayIDs.append(failed.mutationID)
        bodyIDs.insert(failed.mutationID)
        var statement: OpaquePointer?
        try prepare(
          """
          SELECT entity_id, attribute_id FROM instant_outbox_write_keys
          WHERE mutation_id = ?
          ORDER BY entity_id, attribute_id
          """,
          statement: &statement
        )
        var keys: [InstantVisibleWriteKey] = []
        do {
          defer { finishStatement(statement) }
          try bind([.text(failed.mutationID)], to: statement)
          while sqlite3_step(statement) == SQLITE_ROW {
            guard let entityBytes = sqlite3_column_text(statement, 0),
              let attributeBytes = sqlite3_column_text(statement, 1)
            else { continue }
            keys.append(
              InstantVisibleWriteKey(
                entityID: String(cString: entityBytes),
                attributeID: String(cString: attributeBytes)
              )
            )
          }
        }
        for key in keys {
          guard let next = try writer(of: key.attributeID, on: key.entityID, newest: false, after: failed) else {
            continue
          }
          context.nextWriterAfterFailed[failed.mutationID, default: [:]][key] = next.mutationID
          bodyIDs.insert(next.mutationID)
        }
      }
      for slot in reverseLinkSlots.sorted(by: { ($0.entityID, $0.attributeID) < ($1.entityID, $1.attributeID) }) {
        guard let first = try writer(of: slot.attributeID, on: slot.entityID, newest: false) else { continue }
        context.firstReverseLinkWriterBySlot[slot] = first.mutationID
        bodyIDs.insert(first.mutationID)
        if let last = try writer(of: slot.attributeID, on: slot.entityID, newest: true) {
          context.lastReverseLinkWriterBySlot[slot] = last.mutationID
          bodyIDs.insert(last.mutationID)
        }
      }
      guard bodyIDs.count <= InstantServerApplyReductionLimits.maximumBodies else {
        return .ineligible(.tooManyBodies)
      }
      for mutationID in bodyIDs.sorted() {
        guard let row = try loadOutboxBodyRowWithoutTransaction(id: mutationID) else {
          return .ineligible(.revisionChanged)
        }
        let mutation: PendingMutation = try decodeOutboxBody(row.json)
        decodedOutboxBodyCount += 1
        decodedOutboxBodyByteCount += row.json.utf8.count
        context.bodies[mutationID] = mutation
      }
      for (entityID, mutationID) in lastOverlayByEntity {
        guard let body = context.bodies[mutationID],
          InstantServerApplyDeletion.deletesLast(entityID, in: body.transaction.operations)
        else { continue }
        context.deletingWriterByEntity[entityID] = mutationID
      }
      // An entity a refused write created stays only if no surviving write after it touches the entity; the reduction
      // then deletes it, as the full rebase's replay would leave it out.
      for failed in failedPositions {
        guard let body = context.bodies[failed.mutationID],
          case let .materialized(rollback) = body.optimisticEffectReceipt
        else { continue }
        for operation in rollback.operations {
          let createdEntityID: String
          switch operation {
          case let .deleteEntity(entityID), let .deleteEntityInNamespace(entityID, _):
            createdEntityID = entityID
          default:
            continue
          }
          let touchedLater = try selectInt64(
            """
            SELECT EXISTS(
              SELECT 1
              FROM instant_outbox_effect_entities AS effects
                INDEXED BY instant_outbox_effect_entities_lookup_idx
              JOIN instant_outbox AS outbox ON outbox.mutation_id = effects.mutation_id
              WHERE effects.entity_id = ? AND \(remaining)
                AND (
                  effects.created_at_ms > ?
                  OR (effects.created_at_ms = ? AND effects.mutation_id > ?)
                )
              LIMIT 1
            )
            """,
            [.text(createdEntityID)] + prunable.bindings + [
              .int(failed.createdAtMilliseconds), .int(failed.createdAtMilliseconds), .text(failed.mutationID),
            ]
          ) != 0
          if touchedLater {
            context.createdEntitiesTouchedAfterFailed[failed.mutationID, default: []].insert(createdEntityID)
          }
        }
      }
      return .ready(context)
    }
    serverApplyMetrics.reductionCount += 1
    if case .ready = load { serverApplyMetrics.reducedCount += 1 }
    return load
  }

  /// `outbox.status = confirmed`, proven, and covered by `processedTransactionID` (the watermark prune), as SQL that is
  /// never NULL.
  private static func serverApplyReductionPrunablePredicate(
    processedTransactionID: String,
    alias: String
  ) -> (sql: String, bindings: [SQLiteBinding]) {
    let serverTransactionID = "COALESCE(\(alias).server_transaction_id, '')"
    let covered: String
    var bindings: [SQLiteBinding] = [
      .text(InstantMutationStatus.confirmed.rawValue),
      .text(processedTransactionID),
    ]
    if let processedNumber = Int64(processedTransactionID) {
      covered = """
        (\(serverTransactionID) = ? OR (
          \(serverTransactionID) != ''
          AND \(serverTransactionID) NOT GLOB '*[^0-9]*'
          AND CAST(\(serverTransactionID) AS INTEGER) <= ?
        ))
        """
      bindings.append(.int(processedNumber))
    } else {
      covered = "\(serverTransactionID) = ?"
    }
    return (
      """
      (\(alias).status = ? AND COALESCE(\(alias).confirmation_proven, 0) = 1 AND \(covered))
      """,
      bindings
    )
  }

  func loadServerApplyBodyPage(
    planID: String,
    direction: InstantServerApplyBodyDirection,
    after position: InstantOutboxDeliveryPosition?
  ) throws -> InstantServerApplyBodyPage {
    let energy = InstantEnergyMeter.begin(.serverApplyPlan); defer { energy.end() }
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
    // #1011: its own name; an iOS disk-write report's heaviest stack ended here.
    let energy = InstantEnergyMeter.begin(.serverApplyStage); defer { energy.end() }
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
          guard let receiptFingerprint = try optimisticEffectFingerprint(of: mutation) else {
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
            // #932: the body as planned is the outbox's body. The check below refuses only an offered write, and an
            // offered write's wire intent never changes in place (persisting it with another refuses, and confirming
            // or retrying it keeps it), so it gives the answer the staged copy of the body gave.
            var statement: OpaquePointer?
            try prepare(
              """
              SELECT planned.expected_server_acceptance_payload_fingerprint,
                     planned.expected_delivery_claim_payload_fingerprint,
                     planned.expected_delivery_claimant_id,
                     planned.confirm_at_apply, outbox.json,
                     planned.expected_delivery_started, outbox.delivery_started
              FROM instant_server_apply_rows AS planned
              JOIN instant_outbox AS outbox
                ON outbox.mutation_id = planned.mutation_id
              WHERE planned.plan_id = ? AND planned.mutation_id = ?
              LIMIT 1
              """,
              statement: &statement
            )
            defer { finishStatement(statement) }
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
    let energy = InstantEnergyMeter.begin(.serverApplyPlan); defer { energy.end() }
    return try transaction {
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
          is_catch_up, prune_at_watermark, confirm_at_apply,
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
               1, 1, 1, 0, 0, 0, 0
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
    changedFactScope: InstantFactScope = InstantFactScope(),
    mergingAttributes attributes: [InstantAttribute],
    queryResults: [InstantPersistedLiveQueryResult],
    preparedQueryResults: [InstantPreparedLiveQueryResultSave]? = nil,
    storeChanged: Bool,
    metadataKey: String,
    metadataValue: String,
    metadataUpdatedAt: InstantTimestamp
  ) throws -> InstantServerApplyCommit? {
    let energy = InstantEnergyMeter.begin(.serverApplyCommit); defer { energy.end() }
    serverApplyMetrics.commitAttemptCount += 1
    // #932: each section's time goes to the gate-held event, so a slow commit names its part.
    let startedAt = ContinuousClock.now
    let resultJSONBytesBefore = liveQueryResultJSONWriteStats.bytes
    let body: (commit: InstantServerApplyCommit?, clock: InstantServerApplyCommitClock) = try transaction {
      var clock = InstantServerApplyCommitClock(startedAt: startedAt)
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
      else { return (nil, clock) }
      clock.end(\.validateMilliseconds)

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
      clock.end(\.outboxMilliseconds)
      let didChangeStore = storeChanged && !changedEntityTriples.isEmpty
      let didChangeAttributes = !attributes.isEmpty
      let didChangeQueryResults = !queryResults.isEmpty

      if didChangeStore {
        for entityID in changedEntityTriples.keys.sorted() {
          try saveChangedEntityFactsWithoutTransaction(
            entityID: entityID,
            scope: changedFactScope[entityID],
            triples: changedEntityTriples[entityID, default: []]
          )
        }
      }
      if didChangeAttributes {
        try invalidateDeclaredRelationStorageMarkerIfNeeded(
          forIncomingAttributes: attributes
        )
        for attribute in attributes {
          try executeAttributeWrite(
            "INSERT OR REPLACE INTO instant_attributes (id, json) VALUES (?, ?)",
            [.text(attribute.id), .text(try encode(attribute))]
          )
        }
      }
      clock.end(\.factsMilliseconds)

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
        clock.timing.deletedOutboxRowCount = Int(sqlite3_changes(connection.raw))
        try execute(
          """
          UPDATE instant_outbox AS outbox
          SET status = planned.staged_status,
              delivery_state = planned.staged_delivery_state,
              delivery_metadata_version = ?,
              transport_step_count = planned.staged_transport_step_count,
              encoded_body_bytes = length(CAST(planned.staged_json AS BLOB)),
              lifecycle_json = planned.staged_lifecycle_json,
              failure_message = planned.staged_failure_message,
              confirmation_proven = planned.staged_confirmation_proven,
              optimistic_overlay_active = planned.staged_overlay_active,
              mutation_revision = outbox.mutation_revision + 1,
              optimistic_effect_metadata_version = planned.staged_effect_metadata_version,
              optimistic_effect_is_global = planned.staged_effect_is_global,
              optimistic_effect_receipt_fingerprint = planned.staged_effect_receipt_fingerprint,
              server_acceptance_payload_fingerprint = planned.staged_server_acceptance_payload_fingerprint,
              server_transaction_id = planned.staged_server_transaction_id,
              confirmation_source = planned.staged_confirmation_source,
              json = planned.staged_json
          FROM instant_server_apply_rows AS planned
          WHERE planned.plan_id = ? AND planned.staged = 1 AND planned.staged_delete = 0
            AND outbox.mutation_id = planned.mutation_id
            AND (
              planned.staged_json != outbox.json
              OR planned.staged_effect_receipt_fingerprint
                IS NOT outbox.optimistic_effect_receipt_fingerprint
              OR planned.staged_server_acceptance_payload_fingerprint
                IS NOT outbox.server_acceptance_payload_fingerprint
            )
          """,
          // #932: one join visits the plan's staged rows and each one's outbox row through its key. The fifteen
          // correlated lookups this replaces read the staged row once per column, under the operation gate. (Before
          // #277 a correlated IN rescanned every plan row for each outbox row: 7.4 s for 2,000 pending mutations.)
          [.int(Int64(InstantOutboxDeliveryMetadata.currentVersion)), .text(planID)]
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
      clock.end(\.outboxMilliseconds)

      let ownershipRowReadsBefore = liveQueryOwnershipRowReadCount
      let valueEncodesBefore = liveQueryResultValueEncodeCount
      if let preparedQueryResults {
        // #932: worked out before the gate, under the query-result revision this commit checked above.
        for save in preparedQueryResults {
          try applyLiveQueryResultSaveWithoutTransaction(save, deferringJSON: true)
        }
      } else {
        for result in queryResults {
          try saveLiveQueryResultWithoutTransaction(result, deferringJSON: true)
        }
      }
      serverApplyMetrics.commitResultOwnershipRowReadCount += liveQueryOwnershipRowReadCount - ownershipRowReadsBefore
      serverApplyMetrics.commitResultValueEncodeCount += liveQueryResultValueEncodeCount - valueEncodesBefore
      // A query that keeps refreshing writes its newest result once per interval (#566).
      try flushDeferredLiveQueryResultsWithoutTransaction(dueAt: metadataUpdatedAt.milliseconds)
      clock.end(\.resultsMilliseconds)
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
      let pendingMutationCount = Int(try selectInt64(
        "SELECT COUNT(*) FROM instant_outbox WHERE status = ?",
        [.text(InstantMutationStatus.pending.rawValue)]
      ))
      clock.end(\.bookkeepingMilliseconds)
      let commit = InstantServerApplyCommit(
        pendingMutationCount: pendingMutationCount,
        expectedStoreRevision: plan.expectedStoreRevision,
        expectedAttributeRevision: plan.expectedAttributeRevision,
        expectedOutboxRevision: plan.expectedOutboxRevision,
        expectedQueryResultRevision: plan.expectedQueryResultRevision,
        didChangeStore: didChangeStore,
        didChangeAttributes: didChangeAttributes,
        didChangeOutbox: didChangeOutbox,
        didChangeQueryResults: didChangeQueryResults
      )
      return (commit, clock)
    }
    var clock = body.clock
    clock.end(\.sqliteCommitMilliseconds)
    var commit = body.commit
    // A result whose JSON write waited is written within one interval, if no later refresh writes it first (#566).
    scheduleDeferredLiveQueryResultFlushIfNeeded()
    if commit == nil {
      serverApplyMetrics.staleCommitCount += 1
    } else if let commit {
      advanceCachedRevisionDomains(
        expectedStoreRevision: commit.expectedStoreRevision,
        expectedAttributeRevision: commit.expectedAttributeRevision,
        expectedOutboxRevision: commit.expectedOutboxRevision,
        expectedQueryResultRevision: commit.expectedQueryResultRevision,
        changedEntityTriples: changedEntityTriples,
        changedFactScope: changedFactScope,
        mergingAttributes: attributes,
        storeChanged: commit.didChangeStore,
        attributesChanged: commit.didChangeAttributes,
        outboxChanged: commit.didChangeOutbox,
        queryResultsChanged: commit.didChangeQueryResults
      )
    }
    clock.timing.resultJSONBytes = liveQueryResultJSONWriteStats.bytes - resultJSONBytesBefore
    clock.timing.insideMilliseconds = InstantServerApplyCommitTiming.milliseconds(from: startedAt, to: ContinuousClock.now)
    commit?.timing = clock.timing
    return commit
  }

  /// One page of the staged rows among `mutationIDs`, the rows the resident outbox holds (#932), in creation order.
  func loadServerApplyResidentPatchPage(
    planID: String,
    among mutationIDs: Set<String>,
    after position: InstantOutboxDeliveryPosition?
  ) throws -> InstantServerApplyResidentPatchPage {
    var sql =
      """
      SELECT mutation_id, created_at_ms, staged_delete,
             CASE WHEN staged_delete = 1 THEN 0
                  ELSE length(CAST(staged_lifecycle_json AS BLOB)) END
      FROM instant_server_apply_rows
      WHERE plan_id = ? AND staged = 1
        AND mutation_id IN (SELECT value FROM json_each(?))
      """
    var bindings: [SQLiteBinding] = [.text(planID), .text(try encode(mutationIDs.sorted()))]
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
    defer { finishStatement(statement) }
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
             confirming_claimant_id, excludes_watermark_roots
      FROM instant_server_apply_plans
      WHERE plan_id = ?
      LIMIT 1
      """,
      statement: &statement
    )
    defer { finishStatement(statement) }
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
      confirmingClaimantID: sqlite3_column_text(statement, 9).map(String.init(cString:)),
      excludesWatermarkRoots: sqlite3_column_int64(statement, 10) != 0
    )
  }

  @discardableResult
  private func insertServerApplyRowsWithoutTransaction(
    planID: String,
    readsBodyBytes: Bool = true,
    componentBody: Bool,
    requiresBody: Bool,
    closureRound: Int = 0,
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
        is_catch_up, prune_at_watermark, confirm_at_apply, staged_delete, staged,
        closure_round
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
             \(readsBodyBytes
               ? "MAX(COALESCE(outbox.encoded_body_bytes, 0), length(CAST(outbox.json AS BLOB)))"
               : "0"),
             ?, ?, 0, 0, 0, 0, 0, ?
      \(selectionSQL)
      """,
      [
        .text(planID),
        .int(componentBody ? 1 : 0),
        .int(requiresBody ? 1 : 0),
        .int(Int64(closureRound)),
      ] + selectionBindings
    )
    return Int(try selectInt64("SELECT changes()"))
  }

  /// Marks the entities of the component rows found in `round` as visited, and returns how many
  /// were new. Only new entities are expanded in the next round.
  private func insertServerApplyClosureEntitiesWithoutTransaction(
    planID: String,
    fromRowsInRound round: Int
  ) throws -> Int {
    try execute(
      """
      INSERT OR IGNORE INTO instant_server_apply_closure_entities (plan_id, entity_id, round)
      SELECT ?, effects.entity_id, ?
      FROM instant_server_apply_rows AS planned
        INDEXED BY instant_server_apply_rows_closure_round_idx
      JOIN instant_outbox_effect_entities AS effects
        ON effects.mutation_id = planned.mutation_id
      WHERE planned.plan_id = ? AND planned.closure_round = ?
        AND planned.is_component_body = 1
      """,
      [.text(planID), .int(Int64(round)), .text(planID), .int(Int64(round))]
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

  /// - Parameter readsBodyBytes: Whether each row records its body's size, which reads the whole body. The commit's
  ///   closure check compares no size, so it passes false (#932).
  private func populateServerApplyPlanRowsWithoutTransaction(
    id planID: String,
    readsBodyBytes: Bool = true
  ) throws {
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
          readsBodyBytes: readsBodyBytes,
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
        // A reduced apply (#296) has proven the watermark prunes only a prefix, so a pruned row keeps its effect and
        // is no reason to peel what it connects to.
        let excludesPruned = control.excludesWatermarkRoots
          ? """
            AND NOT COALESCE(
              (outbox.status = ? AND COALESCE(outbox.confirmation_proven, 0) = 1 AND \(watermark.sql)), 0
            )
            """
          : ""
        try insertServerApplyRowsWithoutTransaction(
          planID: planID,
          readsBodyBytes: readsBodyBytes,
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
              \(excludesPruned)
            """,
          bindings: [.text(planID)]
            + (control.excludesWatermarkRoots
              ? [.text(InstantMutationStatus.confirmed.rawValue)] + watermark.bindings
              : [])
        )
        // A reduced apply (#296) removes refused writes itself, as receipt-patch rows; a whole-component rebase peels them.
        if !control.excludesWatermarkRoots {
          try insertServerApplyRowsWithoutTransaction(
            planID: planID,
            readsBodyBytes: readsBodyBytes,
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
        }
        if !control.excludesWatermarkRoots {
          try insertServerApplyRowsWithoutTransaction(
            planID: planID,
            readsBodyBytes: readsBodyBytes,
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
        }
        if let confirmingMutationID = control.confirmingMutationID {
          try insertServerApplyRowsWithoutTransaction(
            planID: planID,
            readsBodyBytes: readsBodyBytes,
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

        // The component closure is a breadth-first search over entities: each round expands
        // only the entities first seen in the previous round, so every entity is expanded once
        // and every mutation is found once, linear in (mutation, entity) effect pairs. Joining
        // every planned row through every shared entity each round was quadratic around a hub:
        // 2,000 pending sections linked to one recording held the operation gate 23 s in the
        // commit's closure revalidation (#277).
        var round = 0
        while true {
          let newEntities = try insertServerApplyClosureEntitiesWithoutTransaction(
            planID: planID,
            fromRowsInRound: round
          )
          if newEntities == 0 { break }
          let inserted = try insertServerApplyRowsWithoutTransaction(
            planID: planID,
            readsBodyBytes: readsBodyBytes,
            componentBody: true,
            requiresBody: true,
            closureRound: round + 1,
            selectionSQL:
              """
              FROM instant_server_apply_closure_entities AS frontier
                INDEXED BY instant_server_apply_closure_entities_round_idx
              JOIN instant_outbox_effect_entities AS connected_effect
                INDEXED BY instant_outbox_effect_entities_lookup_idx
                ON connected_effect.entity_id = frontier.entity_id
              JOIN instant_outbox AS outbox
                ON outbox.mutation_id = connected_effect.mutation_id
              WHERE frontier.plan_id = ? AND frontier.round = ?
                AND outbox.optimistic_overlay_active = 1
                AND outbox.optimistic_effect_receipt_fingerprint IS NOT NULL
              """,
            bindings: [.text(planID), .int(Int64(round))]
          )
          if inserted == 0 { break }
          round += 1
        }
        try execute(
          "DELETE FROM instant_server_apply_closure_entities WHERE plan_id = ?",
          [.text(planID)]
        )
      }
    }

    try insertServerApplyRowsWithoutTransaction(
      planID: planID,
      readsBodyBytes: readsBodyBytes,
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
        readsBodyBytes: readsBodyBytes,
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

    // A reduced apply's receipt patches (#296): each named first writer is loaded, re-receipted, and staged, but not
    // peeled or replayed. Its row is addressed like any other body, so the commit revalidates it.
    try insertServerApplyRowsWithoutTransaction(
      planID: planID,
      readsBodyBytes: readsBodyBytes,
      componentBody: false,
      requiresBody: true,
      selectionSQL:
        """
        FROM instant_server_apply_receipt_patches AS patches
        JOIN instant_outbox AS outbox ON outbox.mutation_id = patches.mutation_id
        WHERE patches.plan_id = ? AND outbox.optimistic_overlay_active = 1
          AND outbox.optimistic_effect_receipt_fingerprint IS NOT NULL
        """,
      bindings: [.text(planID)]
    )
  }

  private func loadServerApplyBodyPageWithoutTransaction(
    planID: String,
    direction: InstantServerApplyBodyDirection,
    after position: InstantOutboxDeliveryPosition?
  ) throws -> InstantServerApplyBodyPage {
    // #932: both passes read the body from the outbox. Every statement that rewrites an outbox body also bumps the row's
    // mutation_revision, and each page compares its rows with the plan, revision included, in the transaction that
    // reads them, so the forward pass reads the body the reverse pass read or the page is stale. The reverse pass used
    // to copy each body into its staging row, which the stage then rewrote whole: on Apple's SQLite, with 2,500 pending
    // bodies of 15 KB, 320 MB of writes for the first apply and 246 MB for the next, against 122 and 39 MB without the
    // copy (the disk map's F1a).
    var sql =
      """
      SELECT planned.mutation_id, planned.created_at_ms,
             length(CAST(outbox.json AS BLOB)),
             planned.is_component_body, planned.prune_at_watermark,
             planned.confirm_at_apply
      FROM instant_server_apply_rows AS planned
      JOIN instant_outbox AS outbox ON outbox.mutation_id = planned.mutation_id
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
    defer { finishStatement(statement) }
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
    finishStatement(statement)
    statement = nil
    // #932: the page checks its own rows, in the transaction that reads them. Checking every row of the plan here cost
    // ~2R^2/50 row checks a full apply, each reading the outbox columns stored after a row's body (~262,000 at the
    // phone's 2,560 pending). A row that moves after its page was read still makes the plan stale: extending the plan
    // and its commit check every row, in the transactions that write.
    let pageMutationIDs = candidates.map(\.mutationID) + (oversizedMutationID.map { [$0] } ?? [])
    guard try serverApplyPlanRowsStillMatchWithoutTransaction(id: planID, among: pageMutationIDs) else {
      return InstantServerApplyBodyPage(
        isStale: true,
        entries: [],
        nextPosition: nil,
        decodedBodyByteCount: 0
      )
    }
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
      let json: String? = try selectScalar(
        "SELECT json FROM instant_outbox WHERE mutation_id = ? LIMIT 1",
        [.text(candidate.mutationID)]
      )
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

  /// Whether every row of the plan, or only those among `mutationIDs`, still matches the outbox row it was planned
  /// from.
  private func serverApplyPlanRowsStillMatchWithoutTransaction(
    id planID: String,
    among mutationIDs: [String]? = nil
  ) throws -> Bool {
    let scope: String
    var bindings: [SQLiteBinding] = [.text(planID)]
    if let mutationIDs {
      guard !mutationIDs.isEmpty else { return true }
      scope = "AND planned.mutation_id IN (SELECT value FROM json_each(?))"
      bindings.append(.text(try encode(mutationIDs)))
    } else {
      serverApplyMetrics.wholePlanValidationCount += 1
      scope = ""
    }
    return try selectInt64(
      """
      SELECT COUNT(*)
      FROM instant_server_apply_rows AS planned
      LEFT JOIN instant_outbox AS outbox
        ON outbox.mutation_id = planned.mutation_id
      WHERE planned.plan_id = ? \(scope) AND (
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
      bindings
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
             confirming_claimant_id, excludes_watermark_roots
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
    try execute(
      """
      INSERT INTO instant_server_apply_receipt_patches (plan_id, mutation_id)
      SELECT ?, mutation_id
      FROM instant_server_apply_receipt_patches
      WHERE plan_id = ?
      """,
      [.text(validationID), .text(planID)]
    )
    // #932: the comparison below reads no body size, so the copy does not read every body: under the gate, at the
    // phone's 2,560 pending writes of 12-25 KB, that was every pending body read once more per commit.
    try populateServerApplyPlanRowsWithoutTransaction(id: validationID, readsBodyBytes: false)
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
      "DELETE FROM instant_server_apply_closure_entities WHERE plan_id = ?",
      [.text(id)]
    )
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
      "DELETE FROM instant_server_apply_receipt_patches WHERE plan_id = ?",
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
    changedFactScope: InstantFactScope = InstantFactScope(),
    metadataEntries: [InstantPersistenceMetadataEntry]
  ) throws -> InstantTerminalFailureCommit? {
    let committed: (
      commit: InstantTerminalFailureCommit,
      outboxRevision: Int64,
      queryResultRevision: Int64
    )? = try transaction {
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
        return (
          commit: InstantTerminalFailureCommit(
            failedMutation: nil,
            rebasedSuccessors: [],
            pendingMutationCount: Int(try selectInt64(
              "SELECT COUNT(*) FROM instant_outbox WHERE status = ?",
              [.text(InstantMutationStatus.pending.rawValue)]
            )),
            didChange: false
          ),
          outboxRevision: 0,
          queryResultRevision: 0
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
        try saveChangedEntityFactsWithoutTransaction(
          entityID: entityID,
          scope: changedFactScope[entityID],
          triples: changedEntityTriples[entityID, default: []]
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
      let outboxRevision = try loadMetadataRevisionWithoutTransaction(Self.outboxRevisionKey)
      let queryResultRevision = try loadMetadataRevisionWithoutTransaction(
        Self.queryResultRevisionKey
      )
      _ = try bumpMetadataRevisionWithoutTransaction(Self.storeRevisionKey)
      _ = try bumpMetadataRevisionWithoutTransaction(Self.outboxRevisionKey)
      return (
        commit: InstantTerminalFailureCommit(
          failedMutation: failedMutation,
          rebasedSuccessors: rebasedSuccessors,
          pendingMutationCount: Int(try selectInt64(
            "SELECT COUNT(*) FROM instant_outbox WHERE status = ?",
            [.text(InstantMutationStatus.pending.rawValue)]
          )),
          didChange: true
        ),
        outboxRevision: outboxRevision,
        queryResultRevision: queryResultRevision
      )
    }
    if let committed, committed.commit.didChange {
      // #1035: the runtime installs this rollback in its hot store and records the next store revision, so the cache
      // moves with it. Dropping it made the next read of a 39,507-fact store rebuild every fact from SQLite (12.9 MB,
      // 242-338 ms on a phone) and replace the hot store, once per refused write.
      advanceCachedRevisionDomains(
        expectedStoreRevision: expectedStoreRevision,
        expectedAttributeRevision: expectedAttributeRevision,
        expectedOutboxRevision: committed.outboxRevision,
        expectedQueryResultRevision: committed.queryResultRevision,
        changedEntityTriples: changedEntityTriples,
        changedFactScope: changedFactScope,
        mergingAttributes: [],
        storeChanged: true,
        attributesChanged: false,
        outboxChanged: true,
        queryResultsChanged: false
      )
    }
    return committed?.commit
  }

  /// Removes the failed mutation `id` by its row alone, for a discard whose receipt records no materialized effect: the
  /// row and what cascades from it, the outbox revision bumped, and the cached store kept, since nothing in the store
  /// changes (#1103). False, changing nothing, when a revision moved since the caller read the row or the row is no
  /// longer a failed one.
  ///
  /// #1103 (2026-10-24): such a discard went through the whole-snapshot save, a diff of every resident fact against
  /// an identical copy, three revisions bumped and the cache dropped, so the next read rebuilt the store from SQLite:
  /// 112 ms to 1.7 s of the operation gate on a phone-shaped store, up to 32 times a recovery sweep. The outbox diff of
  /// that save deleted this one row and nothing else.
  func removeFailedMutationWithoutEffect(
    id: String,
    expectedStoreRevision: Int64,
    expectedAttributeRevision: Int64,
    expectedOutboxRevision: Int64
  ) throws -> Bool {
    let queryResultRevision: Int64? = try transaction {
      guard
        try loadMetadataRevisionWithoutTransaction(Self.storeRevisionKey) == expectedStoreRevision,
        try loadMetadataRevisionWithoutTransaction(Self.attributeRevisionKey) == expectedAttributeRevision,
        try loadMetadataRevisionWithoutTransaction(Self.outboxRevisionKey) == expectedOutboxRevision,
        try selectInt64(
          "SELECT COUNT(*) FROM instant_outbox WHERE mutation_id = ? AND status = ?",
          [.text(id), .text(InstantMutationStatus.failed.rawValue)]
        ) == 1
      else { return nil }
      let queryResultRevision = try loadMetadataRevisionWithoutTransaction(Self.queryResultRevisionKey)
      try execute("DELETE FROM instant_outbox WHERE mutation_id = ?", [.text(id)])
      _ = try bumpMetadataRevisionWithoutTransaction(Self.outboxRevisionKey)
      return queryResultRevision
    }
    guard let queryResultRevision else { return false }
    advanceCachedRevisionDomains(
      expectedStoreRevision: expectedStoreRevision,
      expectedAttributeRevision: expectedAttributeRevision,
      expectedOutboxRevision: expectedOutboxRevision,
      expectedQueryResultRevision: queryResultRevision,
      changedEntityTriples: [:],
      changedFactScope: InstantFactScope(),
      mergingAttributes: [],
      storeChanged: false,
      attributesChanged: false,
      outboxChanged: true,
      queryResultsChanged: false
    )
    return true
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

  /// The outbox's newest creation time, and the newest row in delivery order (`created_at_ms`, then `mutation_id`),
  /// which a write must follow to be the tail.
  func latestOutboxCreationTimestamp(expectedOutboxRevision: Int64) throws
    -> (matchesRevision: Bool, timestamp: InstantTimestamp?, tail: InstantOutboxDeliveryPosition?)
  {
    try readTransaction {
      guard
        try loadMetadataRevisionWithoutTransaction(Self.outboxRevisionKey)
          == expectedOutboxRevision
      else { return (false, nil, nil) }
      let tail = try latestOutboxPositionWithoutTransaction()
      return (true, tail.map { InstantTimestamp(milliseconds: $0.createdAtMilliseconds) }, tail)
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
  /// returned as `nil` without decoding its body. An undecodable or oversized
  /// tail comes back as `invalidTail`, for
  /// ``quarantineInvalidImmediateSupersessionTail(_:expectedStoreRevision:expectedOutboxRevision:)``
  /// to repair before the caller prepares its write. Synchronous, so `transact`
  /// reads it in the same persistence turn as its other reads (#403).
  /// The outbox's newest row, with what the supersession tail check needs of it.
  ///
  /// #1108, #1114 (2026-10-24): the newest id first, from an index that holds every row's creation time and id (a
  /// covering scan of its small pages), then that one row by its key. Chosen in one step, with the row's other columns
  /// and its body size, the read scanned the table, every row through its body, and sorted it, before every eligible
  /// write: 1,336 page reads on a copy of the phone-shaped store against 24.
  package static let immediateSupersessionTailSQL =
    """
    SELECT mutation_id, status, optimistic_overlay_active,
           delivery_claim_state, delivery_started, delivery_state,
           delivery_metadata_version, encoded_body_bytes,
           created_at_ms, length(CAST(json AS BLOB))
    FROM instant_outbox
    WHERE mutation_id = (
      SELECT mutation_id
      FROM instant_outbox
      ORDER BY created_at_ms DESC, mutation_id DESC
      LIMIT 1
    )
    """

  func readImmediateSupersessionTail(
    expectedStoreRevision: Int64,
    expectedOutboxRevision: Int64
  ) throws -> InstantOutboxImmediateTailRead {
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
      try prepare(Self.immediateSupersessionTailSQL, statement: &statement)
      defer { finishStatement(statement) }
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
    return InstantOutboxImmediateTailRead(load: load, invalidTail: invalidTail)
  }

  /// Quarantines an invalid tail that ``readImmediateSupersessionTail(expectedStoreRevision:expectedOutboxRevision:)``
  /// found, if it is still the exact tail at both revisions. Always reports a revision mismatch, so the caller reloads.
  func quarantineInvalidImmediateSupersessionTail(
    _ invalidTail: InstantOutboxInvalidImmediateTail,
    expectedStoreRevision: Int64,
    expectedOutboxRevision: Int64
  ) async throws -> InstantOutboxImmediateTailLoad {
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
      defer { finishStatement(statement) }
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
      defer { finishStatement(statement) }
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
        // A mutation bootstrap quarantined is never sent by the library on its own, so its observers learn that it
        // failed, with its effect unknown, instead of waiting forever (#696). Send Again writes it anew.
        if let held = try heldQuarantinedOutboxMutationsWithoutTransaction(
          """
          SELECT mutation_id, reason, quarantined_at_ms, created_at_ms, status, json, outbox_row_json
          FROM instant_outbox_quarantined
          WHERE resolution IS NULL AND mutation_id = ?
          ORDER BY quarantine_id
          LIMIT 1
          """,
          [.text(currentMutationID)]
        ).first, var mutation = held.mutation {
          mutation.status = .failed
          mutation.failureMessage = Self.quarantinedMutationFailureMessage
          mutation.failure = InstantMutationFailure(
            code: .persistenceFailed,
            message: Self.quarantinedMutationFailureMessage
          )
          if let event = lifecycleEvent(
            for: lifecycleMutationForInspection(mutation, hasStoredReceiptFingerprint: false),
            hasServerAcceptance: false
          ) {
            return InstantMutationLifecycleResolution(observationID: lifecycleID, event: event)
          }
        }
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
          hasServerAcceptance: hasStoredServerAcceptance(in: row, hasPreparedReceipt: hasPreparedReceipt)
        ) ?? .waiting
      )
    }
  }

  /// The oldest `limit` outbox mutations with one of `statuses`, in send order, in one actor turn and without a
  /// queue-wide decode (#445).
  func oldestOutboxMutations(statuses: [InstantMutationStatus], limit: Int) throws -> [PendingMutation] {
    try loadOutboxMutations(
      statuses: statuses,
      limit: max(0, limit),
      expectedOutboxRevision: try currentOutboxRevision()
    ) ?? []
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
            hasServerAcceptance: hasStoredServerAcceptance(in: row, hasPreparedReceipt: true)
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
        let selectedReceiptFingerprint = try optimisticEffectFingerprint(of: selectedMutation)
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

  /// Moves every live claim of one claimant later, so the earliest deadline is at least
  /// `earliestDeadlineMilliseconds`, keeping the claims' ordinal spacing (#296).
  ///
  /// Only deadlines change: tokens, claimants, and claim states stay, so an acknowledgement that arrives for a
  /// renewed claim still matches it. Returns how many claims moved and the earliest deadline after the move.
  func deferAutomaticOutboxClaimDeadlines(
    claimantID: String,
    earliestDeadlineMilliseconds: Int64
  ) throws -> (deferredClaimCount: Int, nextClaimDeadlineMilliseconds: Int64?) {
    try transaction {
      let claimed = InstantOutboxDeliveryClaimState.claimed.rawValue
      guard
        let earliest = try selectScalar(
          """
          SELECT CAST(MIN(delivery_claim_deadline_ms) AS TEXT) FROM instant_outbox
          WHERE delivery_claim_state = ? AND delivery_claimant_id = ?
            AND delivery_claim_deadline_ms IS NOT NULL
          """,
          [.text(claimed), .text(claimantID)]
        ).flatMap(Int64.init)
      else { return (0, nil) }
      guard earliest < earliestDeadlineMilliseconds else { return (0, earliest) }
      let shift = earliestDeadlineMilliseconds - earliest
      try execute(
        """
        UPDATE instant_outbox
        SET delivery_claim_deadline_ms = delivery_claim_deadline_ms + ?
        WHERE delivery_claim_state = ? AND delivery_claimant_id = ?
          AND delivery_claim_deadline_ms IS NOT NULL
        """,
        [.int(shift), .text(claimed), .text(claimantID)]
      )
      return (Int(sqlite3_changes(connection.raw)), earliestDeadlineMilliseconds)
    }
  }

  /// Decodes one outbox row by id so a refusal can be logged with the refused write's values (#296). Read-only; a
  /// missing or undecodable row returns nil rather than failing the refusal it describes.
  func outboxMutationForDiagnostics(id: String) throws -> PendingMutation? {
    try readTransaction {
      guard let row = try loadOutboxBodyRowWithoutTransaction(id: id) else { return nil }
      return try? decodeOutboxBody(row.json)
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
  /// Which later writes of this device cover every operation of a write, if any (library-78, item 3).
  ///
  /// A write offered again after its first offer may have been applied (a lost acknowledgment, a reconnect, a
  /// transient error) is refused by an `updatedAtMs >= data.updatedAtMs`-style rule when a newer write of the same row
  /// reached the server first, although the server holds a newer value for every slot it sets. Coverage is
  /// conservative: the write may hold only inserts and merges (lookups, retractions, and deletes never count as
  /// covered); a cardinality-one slot is covered by a later insert of the slot, any other value only by the same value
  /// (`InstantAuthoritativeWriteCoverage`). Failed rows never cover. Candidates come from the stored write keys, so a
  /// write no later row shares a slot with costs one indexed query and no body decode.
  ///
  /// - Parameters:
  ///   - decoded: The write's body when the caller already decoded it.
  ///   - acceptedOnly: Consider only later writes the server accepted.
  ///   - pendingMustBeClaimed: Count a later write the server has not accepted only while it is in flight, so a write
  ///     parked behind it waits for an answer that is coming.
  ///   - serverResults: For a refused re-send only (#441): an insert that a later write does not cover also counts
  ///     when a result the server sent since the write was created shows its value (`InstantServerResultCheck`).
  /// - Returns: The coverage, the write's decoded body (`nil` when no later write shares a slot with it and no server
  ///   result is consulted), and how many of its slots the server's results showed.
  private func laterWriteCoverageWithoutTransaction(
    ofMutationID mutationID: String,
    createdAtMilliseconds: Int64,
    decoded: PendingMutation?,
    acceptedOnly: Bool,
    pendingMustBeClaimed: Bool = false,
    serverResults: InstantServerResultCheck? = nil,
    attributes: () throws -> AttributeStore
  ) throws -> (coverage: InstantOutboxWriteCoverage, mutation: PendingMutation?, serverResultSlotCount: Int) {
    let candidates = try laterWriteCandidatesWithoutTransaction(
      ofMutationID: mutationID,
      createdAtMilliseconds: createdAtMilliseconds,
      acceptedOnly: acceptedOnly,
      pendingMustBeClaimed: pendingMustBeClaimed
    )
    guard !candidates.isEmpty || serverResults != nil else { return (.none, decoded, 0) }
    let mutation: PendingMutation
    if let decoded {
      mutation = decoded
    } else {
      guard let row = try loadOutboxBodyRowWithoutTransaction(id: mutationID) else { return (.none, nil, 0) }
      mutation = try decodeOutboxBody(row.json)
      decodedOutboxBodyCount += 1
      decodedOutboxBodyByteCount += row.json.utf8.count
    }
    var hasWrite = false
    for operation in mutation.transaction.operations {
      switch operation {
      case .insert, .merge:
        hasWrite = true
      case .requireEntityMissing, .requireEntityMissingByLookup,
        .requireEntityExists, .requireEntityExistsByLookup,
        .requireTripleExists, .ruleParams, .ruleParamsByLookup:
        continue
      case .retract, .retractByLookup, .insertByLookup, .mergeByLookup,
        .deleteEntity, .deleteEntityInNamespace, .deleteEntityByLookup:
        return (.none, mutation, 0)
      }
    }
    guard hasWrite else { return (.none, mutation, 0) }
    var acceptedOperations: [InstantTripleOperation] = []
    var allOperations: [InstantTripleOperation] = []
    var acceptedIDs: [String] = []
    var allIDs: [String] = []
    var newestAcceptedTransactionID: String?
    for candidate in candidates {
      guard let row = try loadOutboxBodyRowWithoutTransaction(id: candidate.id) else { continue }
      let covering: PendingMutation = try decodeOutboxBody(row.json)
      decodedOutboxBodyCount += 1
      decodedOutboxBodyByteCount += row.json.utf8.count
      allOperations.append(contentsOf: covering.transaction.operations)
      allIDs.append(candidate.id)
      guard candidate.accepted else { continue }
      acceptedOperations.append(contentsOf: covering.transaction.operations)
      acceptedIDs.append(candidate.id)
      if let transactionID = candidate.serverTransactionID, !transactionID.isEmpty {
        newestAcceptedTransactionID = Self.newerServerTransactionID(newestAcceptedTransactionID, transactionID)
      }
    }
    let attributeStore = try attributes()
    let acceptedCoverage: InstantAuthoritativeWriteCoverage? =
      acceptedOperations.isEmpty || newestAcceptedTransactionID == nil
      ? nil
      : InstantAuthoritativeWriteCoverage(
        operations: acceptedOperations,
        attributes: attributeStore,
        previousChangedEntityTriples: [:],
        changedEntityTriples: [:]
      )
    if let acceptedCoverage,
      let serverTransactionID = newestAcceptedTransactionID,
      acceptedCoverage.covers(mutation.transaction.operations)
    {
      return (.acceptedWrites(serverTransactionID: serverTransactionID, mutationIDs: acceptedIDs), mutation, 0)
    }
    let allCoverage: InstantAuthoritativeWriteCoverage? =
      acceptedOnly
      ? nil
      : InstantAuthoritativeWriteCoverage(
        operations: allOperations,
        attributes: attributeStore,
        previousChangedEntityTriples: [:],
        changedEntityTriples: [:]
      )
    if let allCoverage, allCoverage.covers(mutation.transaction.operations) {
      return (.pendingWrites(mutationIDs: allIDs), mutation, 0)
    }
    guard let serverResults else { return (.none, mutation, 0) }
    // A refused re-send (#441): each insert a later write does not cover may be held by the server's own results. The
    // watermark is the server transaction id a write they resolve takes; without one, no result has been stored.
    let serverResultTransactionID = try loadMetadataValue(key: serverResults.processedTransactionIDKey)
      .flatMap { $0.isEmpty ? nil : $0 }
    var serverResultSlotCount = 0
    var coveredByAcceptedWritesOrResults = true
    var coveredByAnyWriteOrResults = true
    var uncoveredAreInsertsOnly = true
    for operation in mutation.transaction.operations {
      let triple: InstantTriple
      let isInsert: Bool
      switch operation {
      case let .insert(inserted):
        triple = inserted
        isInsert = true
      case let .merge(merged):
        triple = merged
        isInsert = false
      default:
        continue
      }
      let coveredByAccepted = acceptedCoverage?.covers([operation]) == true
      var held = false
      if !coveredByAccepted, isInsert, serverResultTransactionID != nil {
        held = try newestServerResultShowingWithoutTransaction(
          triple,
          attributes: attributeStore,
          storedAtOrAfter: createdAtMilliseconds
        ) != nil
      }
      if held { serverResultSlotCount += 1 }
      if !coveredByAccepted && !held { coveredByAcceptedWritesOrResults = false }
      if !coveredByAccepted && !held && allCoverage?.covers([operation]) != true {
        coveredByAnyWriteOrResults = false
        if !isInsert { uncoveredAreInsertsOnly = false }
      }
    }
    if coveredByAcceptedWritesOrResults, serverResultSlotCount > 0, let serverResultTransactionID {
      let serverTransactionID = newestAcceptedTransactionID.map {
        Self.newerServerTransactionID(serverResultTransactionID, $0)
      } ?? serverResultTransactionID
      return (
        .acceptedWrites(serverTransactionID: serverTransactionID, mutationIDs: acceptedIDs),
        mutation,
        serverResultSlotCount
      )
    }
    if allCoverage != nil, coveredByAnyWriteOrResults {
      return (.pendingWrites(mutationIDs: allIDs), mutation, serverResultSlotCount)
    }
    if serverResults.waitsForServerResult, uncoveredAreInsertsOnly {
      return (.awaitingServerResult(mutationIDs: allIDs), mutation, serverResultSlotCount)
    }
    return (.none, mutation, serverResultSlotCount)
  }

  /// The later writes of this device that share a slot with a write, oldest first, at most 64; failed rows never count
  /// (library-78, item 3). Candidates come from the stored write keys, so a write no later row shares a slot with costs
  /// one indexed query and no body decode.
  private func laterWriteCandidatesWithoutTransaction(
    ofMutationID mutationID: String,
    createdAtMilliseconds: Int64,
    acceptedOnly: Bool,
    pendingMustBeClaimed: Bool
  ) throws -> [(id: String, createdAt: Int64, accepted: Bool, serverTransactionID: String?)] {
    var candidates: [(id: String, createdAt: Int64, accepted: Bool, serverTransactionID: String?)] = []
    var statement: OpaquePointer?
    try prepare(
      """
      SELECT DISTINCT o.mutation_id, o.created_at_ms, o.status, o.confirmation_proven, o.server_transaction_id,
             o.delivery_claim_state
      FROM instant_outbox_write_keys own
      JOIN instant_outbox_write_keys other
        ON other.entity_id = own.entity_id AND other.attribute_id = own.attribute_id
      JOIN instant_outbox o ON o.mutation_id = other.mutation_id
      WHERE own.mutation_id = ? AND o.mutation_id != ? AND o.status != ?
        AND (o.created_at_ms > ? OR (o.created_at_ms = ? AND o.mutation_id > ?))
        AND (? = 0 OR (o.status = ? AND COALESCE(o.confirmation_proven, 0) = 1))
      ORDER BY o.created_at_ms, o.mutation_id
      LIMIT 64
      """,
      statement: &statement
    )
    defer { finishStatement(statement) }
    try bind(
      [
        .text(mutationID),
        .text(mutationID),
        .text(InstantMutationStatus.failed.rawValue),
        .int(createdAtMilliseconds),
        .int(createdAtMilliseconds),
        .text(mutationID),
        .int(acceptedOnly ? 1 : 0),
        .text(InstantMutationStatus.confirmed.rawValue),
      ],
      to: statement
    )
    while true {
      let code = sqlite3_step(statement)
      if code == SQLITE_DONE { break }
      guard code == SQLITE_ROW, let idBytes = sqlite3_column_text(statement, 0) else {
        throw persistenceError(operation: "find covering outbox writes", message: lastErrorMessage())
      }
      let status = sqlite3_column_text(statement, 2).map { String(cString: $0) }
      let accepted = status == InstantMutationStatus.confirmed.rawValue && sqlite3_column_int64(statement, 3) == 1
      let claimed = sqlite3_column_text(statement, 5).map { String(cString: $0) }
        == InstantOutboxDeliveryClaimState.claimed.rawValue
      guard accepted || !pendingMustBeClaimed || claimed else { continue }
      candidates.append((
        id: String(cString: idBytes),
        createdAt: sqlite3_column_int64(statement, 1),
        accepted: accepted,
        serverTransactionID: sqlite3_column_text(statement, 4).map { String(cString: $0) }
      ))
    }
    return candidates
  }

  /// When the newest live-query result the server sent, stored at or after `storedAtOrAfter`, that shows an insert's
  /// value for its slot arrived, if one does (#441). Stored results hold only the server's facts
  /// (`instant_live_query_triples`, the ownership of each result's triples, indexed by entity, attribute, and value),
  /// and a result is stamped when it is received. An identity insert (`<namespace>/id` set to the entity's own id) only
  /// says the entity exists, so any of the entity's triples in a result shows it.
  private func newestServerResultShowingWithoutTransaction(
    _ triple: InstantTriple,
    attributes: AttributeStore,
    storedAtOrAfter milliseconds: Int64
  ) throws -> Int64? {
    let attribute = attributes[triple.attributeID]
    if attribute?.primaryKey == true || attribute?.name == "id", triple.value == .string(triple.entityID) {
      return try selectScalar(
        """
        SELECT MAX(result.updated_at_ms)
        FROM instant_live_query_triples AS owned
        JOIN instant_live_query_results AS result ON result.query_id = owned.query_id
        WHERE owned.entity_id = ? AND result.updated_at_ms >= ?
        """,
        [.text(triple.entityID), .int(milliseconds)]
      ).flatMap { Int64($0) }
    }
    return try selectScalar(
      """
      SELECT MAX(result.updated_at_ms)
      FROM instant_live_query_triples AS owned
      JOIN instant_live_query_results AS result ON result.query_id = owned.query_id
      WHERE owned.entity_id = ? AND owned.attribute_id = ? AND owned.value_json = ?
        AND result.updated_at_ms >= ?
      """,
      [
        .text(triple.entityID),
        .text(triple.attributeID),
        .text(try encode(triple.value)),
        .int(milliseconds),
      ]
    ).flatMap { Int64($0) }
  }

  /// The newer of two server transaction ids: numeric when both are, otherwise the later one.
  private static func newerServerTransactionID(_ current: String?, _ candidate: String) -> String {
    guard let current else { return candidate }
    if let lhs = Int64(current), let rhs = Int64(candidate) {
      return rhs > lhs ? candidate : current
    }
    return candidate
  }

  /// Resolves a pending write as accepted because later accepted writes of this device cover it (item 3).
  ///
  /// The row becomes confirmed with `supersededByAcceptedWrite` and the newest covering server transaction id, so it
  /// leaves the outbox with its covering writes when the watermark passes them; its optimistic overlay stays until
  /// then, beneath the covering writes' values. It is not offered again.
  private func supersedeOutboxMutationWithoutTransaction(
    _ mutation: PendingMutation,
    serverTransactionID: String
  ) throws -> PendingMutation? {
    var superseded = mutation
    superseded.status = .confirmed
    superseded.failureMessage = nil
    superseded.failure = nil
    superseded.serverTransactionID = serverTransactionID
    superseded.confirmationSource = .supersededByAcceptedWrite
    let encodedBody = try encode(superseded)
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
      WHERE mutation_id = ? AND delivery_state = ? AND status IN (?, ?)
        AND COALESCE(confirmation_proven, 0) = 0
      """,
      [
        .text(superseded.status.rawValue),
        .text(InstantOutboxDeliveryState.serverAccepted.rawValue),
        .int(Int64(InstantOutboxDeliveryMetadata.currentVersion)),
        .int(Int64(InstantOutboxDeliveryMetadata.stepCount(in: superseded))),
        .int(Int64(encodedBody.utf8.count)),
        .text(try encode(superseded.compactedForMemory)),
        .int(superseded.optimisticOverlayState == .removed ? 0 : 1),
        .text(InstantOutboxDeliveryClaimState.ready.rawValue),
        .text(serverTransactionID),
        .text(InstantMutationConfirmationSource.supersededByAcceptedWrite.rawValue),
        .text(try mutation.mutationWireIntentFingerprint()),
        .text(encodedBody),
        .text(mutation.id),
        .text(InstantOutboxDeliveryState.needsDelivery.rawValue),
        .text(InstantMutationStatus.pending.rawValue),
        .text(InstantMutationStatus.confirmed.rawValue),
      ]
    )
    guard sqlite3_changes(connection.raw) == 1 else { return nil }
    try replaceOutboxWriteKeysWithoutTransaction(for: superseded)
    try saveMutationLifecycleWithoutTransaction(superseded)
    InstantDiagnostics.shared.record(
      .notice,
      subsystem: "instant-swift-data-core",
      category: "outbox",
      event: "outbox.mutation.superseded",
      message:
        "Later writes of this device that the server accepted, or the server's own results for a refused re-send, cover every operation of this write, so it is resolved as accepted and not offered again.",
      metadata: [
        "mutationID": mutation.id,
        "serverTransactionID": serverTransactionID,
      ],
      correlationID: mutation.id
    )
    return superseded
  }

  /// Resolves a write the server refused, when later writes of this device cover all of it (item 3), or for a re-send
  /// when the server's own results show the rest (#441).
  ///
  /// The server holds a newer value for every slot the refused write sets, or will once the covering writes in flight
  /// are answered. Covered by accepted writes: superseded now. Covered by writes not yet accepted: the write keeps its
  /// claim, parked with a distant acknowledgement deadline, until they are answered (`resolveParkedRefusal`); delivery
  /// stays an ordered prefix. A re-send whose remaining slots a result from the server sent since the write was created
  /// shows with the write's values counts as covered too; one whose remaining slots are inserts no result shows yet is
  /// parked the same way, waiting for one. Otherwise the refusal stands.
  /// - Parameters:
  ///   - holdsBehindPendingWrites: Hold the write behind covering writes not yet accepted. Only for a write whose
  ///     earlier offer may have been applied (a replay): a refusal of a first offer is the server's verdict on the
  ///     write itself, so only accepted covering writes make it moot.
  ///   - serverResults: For a replay only: also count the slots the server's results show (#441).
  ///   - parkedDeadlineMilliseconds: The acknowledgement deadline a parked write's claim takes, so the claim does not
  ///     expire as an acknowledgement timeout while the covering writes are answered.
  func resolveRefusedWriteIfCovered(
    id: String,
    claimantID: String,
    claimToken: String,
    holdsBehindPendingWrites: Bool,
    serverResults: InstantServerResultCheck? = nil,
    parkedDeadlineMilliseconds: Int64
  ) throws -> InstantRefusedWriteResolution {
    let previousState = cachedState
    let resolution: InstantRefusedWriteResolution = try transaction {
      guard
        try selectInt64(
          """
          SELECT EXISTS(
            SELECT 1 FROM instant_outbox
            WHERE mutation_id = ? AND delivery_claim_state = ?
              AND delivery_claimant_id = ? AND delivery_claim_token = ?
              AND status IN (?, ?) AND COALESCE(confirmation_proven, 0) = 0
            LIMIT 1
          )
          """,
          [
            .text(id),
            .text(InstantOutboxDeliveryClaimState.claimed.rawValue),
            .text(claimantID),
            .text(claimToken),
            .text(InstantMutationStatus.pending.rawValue),
            .text(InstantMutationStatus.confirmed.rawValue),
          ]
        ) != 0,
        let position = try loadOutboxPositionWithoutTransaction(id: id)
      else { return .notCovered }
      let (coverage, mutation, serverResultSlotCount) = try laterWriteCoverageWithoutTransaction(
        ofMutationID: id,
        createdAtMilliseconds: position.createdAtMilliseconds,
        decoded: nil,
        acceptedOnly: !holdsBehindPendingWrites,
        pendingMustBeClaimed: true,
        serverResults: holdsBehindPendingWrites ? serverResults : nil,
        attributes: {
          AttributeStore(attributes: try loadAttributesWithoutTransaction(tracesStartupCollection: false))
        }
      )
      let parked: InstantRefusedWriteResolution
      switch coverage {
      case let .acceptedWrites(serverTransactionID, coveringIDs):
        guard let mutation,
          let superseded = try supersedeOutboxMutationWithoutTransaction(
            mutation,
            serverTransactionID: serverTransactionID
          )
        else { return .notCovered }
        _ = try bumpMetadataRevisionWithoutTransaction(Self.outboxRevisionKey)
        return .superseded(
          superseded,
          coveringMutationIDs: coveringIDs,
          serverResultSlotCount: serverResultSlotCount
        )
      case let .pendingWrites(coveringIDs):
        guard holdsBehindPendingWrites else { return .notCovered }
        parked = .heldBehindPendingWrites(coveringMutationIDs: coveringIDs)
      case let .awaitingServerResult(coveringIDs):
        guard holdsBehindPendingWrites else { return .notCovered }
        parked = .awaitingServerResult(coveringMutationIDs: coveringIDs)
      case .none:
        return .notCovered
      }
      try execute(
        """
        UPDATE instant_outbox
        SET delivery_claim_deadline_ms = ?
        WHERE mutation_id = ? AND delivery_claim_state = ? AND delivery_claim_token = ?
        """,
        [
          .int(parkedDeadlineMilliseconds),
          .text(id),
          .text(InstantOutboxDeliveryClaimState.claimed.rawValue),
          .text(claimToken),
        ]
      )
      return sqlite3_changes(connection.raw) == 1 ? parked : .notCovered
    }
    if case .superseded = resolution {
      cachedState = nil
      _ = previousState
    }
    return resolution
  }

  /// Resolves a refusal parked behind covering writes in flight (item 3) or waiting for a server result (#441), while
  /// this runtime still holds its claim: superseded once the covering writes are accepted and the server's results
  /// show the rest; `.notCovered` once neither can cover it any more (a covering write failed, or the wait for a
  /// result ended), so the runtime records the original refusal; still parked otherwise.
  func resolveParkedRefusal(
    id: String,
    claimantID: String,
    claimToken: String,
    serverResults: InstantServerResultCheck? = nil
  ) throws -> InstantRefusedWriteResolution {
    let resolution: InstantRefusedWriteResolution = try transaction {
      guard
        try selectInt64(
          """
          SELECT EXISTS(
            SELECT 1 FROM instant_outbox
            WHERE mutation_id = ? AND delivery_claim_state = ?
              AND delivery_claimant_id = ? AND delivery_claim_token = ?
              AND status IN (?, ?) AND COALESCE(confirmation_proven, 0) = 0
            LIMIT 1
          )
          """,
          [
            .text(id),
            .text(InstantOutboxDeliveryClaimState.claimed.rawValue),
            .text(claimantID),
            .text(claimToken),
            .text(InstantMutationStatus.pending.rawValue),
            .text(InstantMutationStatus.confirmed.rawValue),
          ]
        ) != 0,
        let position = try loadOutboxPositionWithoutTransaction(id: id)
      else { return .stale }
      let (coverage, mutation, serverResultSlotCount) = try laterWriteCoverageWithoutTransaction(
        ofMutationID: id,
        createdAtMilliseconds: position.createdAtMilliseconds,
        decoded: nil,
        acceptedOnly: false,
        serverResults: serverResults,
        attributes: {
          AttributeStore(attributes: try loadAttributesWithoutTransaction(tracesStartupCollection: false))
        }
      )
      switch coverage {
      case let .acceptedWrites(serverTransactionID, coveringIDs):
        guard let mutation,
          let superseded = try supersedeOutboxMutationWithoutTransaction(
            mutation,
            serverTransactionID: serverTransactionID
          )
        else { return .notCovered }
        _ = try bumpMetadataRevisionWithoutTransaction(Self.outboxRevisionKey)
        return .superseded(
          superseded,
          coveringMutationIDs: coveringIDs,
          serverResultSlotCount: serverResultSlotCount
        )
      case let .pendingWrites(coveringIDs):
        return .heldBehindPendingWrites(coveringMutationIDs: coveringIDs)
      case let .awaitingServerResult(coveringIDs):
        return .awaitingServerResult(coveringMutationIDs: coveringIDs)
      case .none:
        return .notCovered
      }
    }
    if case .superseded = resolution {
      cachedState = nil
    }
    return resolution
  }

  /// Whether a retained failed write is superseded (#445): the rule `resolveRefusedWriteIfCovered` applies to a refused
  /// re-send, reported slot by slot and read only. Each insert or merge counts as covered by the newest later write of
  /// this device that the server accepted and that sets it, or for an insert by a live-query result the server sent
  /// since the write was created that shows its value. A later write not accepted yet is named but does not count.
  /// Retractions, deletions, and lookup steps are never covered. Preconditions are not listed.
  /// - Returns: `nil` when `id` is not a retained failed write.
  func failedMutationSupersession(id: String) throws -> InstantMutationSupersession? {
    try readTransaction {
      var coverages: [String: InstantAuthoritativeWriteCoverage] = [:]
      return try failedMutationSupersessionWithoutTransaction(
        id: id,
        attributes: AttributeStore(attributes: try loadAttributesWithoutTransaction(tracesStartupCollection: false)),
        coverages: &coverages
      )
    }
  }

  /// `failedMutationSupersession` for every retained failed write, oldest first, at most `limit` of them (#445).
  func failedMutationSupersessions(limit: Int = 1_000) throws -> [String: InstantMutationSupersession] {
    try readTransaction {
      let attributes = AttributeStore(
        attributes: try loadAttributesWithoutTransaction(tracesStartupCollection: false)
      )
      var ids: [String] = []
      var statement: OpaquePointer?
      try prepare(
        """
        SELECT mutation_id FROM instant_outbox
        WHERE status = ?
        ORDER BY created_at_ms, mutation_id
        LIMIT ?
        """,
        statement: &statement
      )
      defer { finishStatement(statement) }
      try bind([.text(InstantMutationStatus.failed.rawValue), .int(Int64(max(0, limit)))], to: statement)
      while true {
        let code = sqlite3_step(statement)
        if code == SQLITE_DONE { break }
        guard code == SQLITE_ROW, let idBytes = sqlite3_column_text(statement, 0) else {
          throw persistenceError(operation: "list failed outbox writes", message: lastErrorMessage())
        }
        ids.append(String(cString: idBytes))
      }
      // Failed writes of one row share their later writes (a recording's heartbeats), so each is decoded once.
      var coverages: [String: InstantAuthoritativeWriteCoverage] = [:]
      var supersessions: [String: InstantMutationSupersession] = [:]
      for id in ids {
        supersessions[id] = try failedMutationSupersessionWithoutTransaction(
          id: id,
          attributes: attributes,
          coverages: &coverages
        )
      }
      return supersessions
    }
  }

  private func failedMutationSupersessionWithoutTransaction(
    id: String,
    attributes: AttributeStore,
    coverages: inout [String: InstantAuthoritativeWriteCoverage]
  ) throws -> InstantMutationSupersession? {
    guard
      try selectScalar(
        "SELECT status FROM instant_outbox WHERE mutation_id = ? LIMIT 1",
        [.text(id)]
      ) == InstantMutationStatus.failed.rawValue,
      let position = try loadOutboxPositionWithoutTransaction(id: id),
      let row = try loadOutboxBodyRowWithoutTransaction(id: id)
    else { return nil }
    let mutation: PendingMutation = try decodeOutboxBody(row.json)
    // A failed row's write keys are gone, so each slot finds its later writes by its own key, newest first: the first
    // that covers it is the one whose value the server holds now. Each later write is decoded once per read.
    func coverers(
      of key: InstantVisibleWriteKey
    ) throws -> [(id: String, accepted: Bool, serverTransactionID: String?, coverage: InstantAuthoritativeWriteCoverage)] {
      var found: [(id: String, accepted: Bool, serverTransactionID: String?, coverage: InstantAuthoritativeWriteCoverage)] =
        []
      for candidate in try laterWritesOfSlotWithoutTransaction(key, after: position) {
        let coverage: InstantAuthoritativeWriteCoverage
        if let cached = coverages[candidate.id] {
          coverage = cached
        } else {
          guard let candidateRow = try loadOutboxBodyRowWithoutTransaction(id: candidate.id) else { continue }
          let covering: PendingMutation = try decodeOutboxBody(candidateRow.json)
          coverage = InstantAuthoritativeWriteCoverage(
            operations: covering.transaction.operations,
            attributes: attributes,
            previousChangedEntityTriples: [:],
            changedEntityTriples: [:]
          )
          coverages[candidate.id] = coverage
        }
        found.append((candidate.id, candidate.accepted, candidate.serverTransactionID, coverage))
      }
      return found
    }
    var slots: [InstantSlotCoverage] = []
    func uncheckable(_ entityID: String, _ attributeID: String, _ kind: String, _ value: InstantValue?) {
      let attribute = attributes[attributeID]
      slots.append(
        InstantSlotCoverage(
          entityID: entityID,
          namespace: attribute?.namespace,
          attributeName: attribute?.name,
          attributeID: attributeID,
          operation: .other(kind),
          value: value,
          coverage: .notCheckable
        )
      )
    }
    for operation in mutation.transaction.operations {
      let triple: InstantTriple
      let isInsert: Bool
      switch operation {
      case let .insert(inserted):
        triple = inserted
        isInsert = true
      case let .merge(merged):
        triple = merged
        isInsert = false
      case let .retract(retracted):
        uncheckable(retracted.entityID, retracted.attributeID, "retract", retracted.value)
        continue
      case let .insertByLookup(entity, attributeID, value, _, _):
        uncheckable(entity.description, attributeID, "insertByLookup", value)
        continue
      case let .mergeByLookup(entity, attributeID, value, _, _):
        uncheckable(entity.description, attributeID, "mergeByLookup", value)
        continue
      case let .retractByLookup(entity, attributeID, value, _, _):
        uncheckable(entity.description, attributeID, "retractByLookup", value)
        continue
      case let .deleteEntity(entityID):
        uncheckable(entityID, "", "deleteEntity", nil)
        continue
      case let .deleteEntityInNamespace(entityID, _):
        uncheckable(entityID, "", "deleteEntityInNamespace", nil)
        continue
      case let .deleteEntityByLookup(entity):
        uncheckable(entity.description, "", "deleteEntityByLookup", nil)
        continue
      case .requireEntityMissing, .requireEntityMissingByLookup,
        .requireEntityExists, .requireEntityExistsByLookup,
        .requireTripleExists, .ruleParams, .ruleParamsByLookup:
        continue
      }
      let slotCoverers = try coverers(
        of: InstantVisibleWriteKey(entityID: triple.entityID, attributeID: triple.attributeID)
      )
      let coverage: InstantSlotCoverage.Coverage
      if let accepted = slotCoverers.first(where: { $0.accepted && $0.coverage.covers([operation]) }) {
        coverage = .laterAcceptedWrite(mutationID: accepted.id, serverTransactionID: accepted.serverTransactionID)
      } else if isInsert,
        let receivedAt = try newestServerResultShowingWithoutTransaction(
          triple,
          attributes: attributes,
          storedAtOrAfter: position.createdAtMilliseconds
        )
      {
        coverage = .serverResult(receivedAt: InstantTimestamp(milliseconds: receivedAt))
      } else if let pending = slotCoverers.first(where: { !$0.accepted && $0.coverage.covers([operation]) }) {
        coverage = .laterPendingWrite(mutationID: pending.id)
      } else {
        coverage = .notCovered(serverValues: try newestServerValuesWithoutTransaction(of: triple))
      }
      let attribute = attributes[triple.attributeID]
      slots.append(
        InstantSlotCoverage(
          entityID: triple.entityID,
          namespace: attribute?.namespace,
          attributeName: attribute?.name,
          attributeID: triple.attributeID,
          operation: isInsert ? .insert : .merge,
          value: triple.value,
          coverage: coverage
        )
      )
    }
    return !slots.isEmpty && slots.allSatisfy(\.isCovered)
      ? .superseded(by: slots)
      : .notSuperseded(slots: slots)
  }

  /// The later outbox writes of this device that set `key`'s slot, newest first, at most 64; failed rows never count
  /// (#445).
  private func laterWritesOfSlotWithoutTransaction(
    _ key: InstantVisibleWriteKey,
    after position: InstantOutboxDeliveryPosition
  ) throws -> [(id: String, accepted: Bool, serverTransactionID: String?)] {
    var statement: OpaquePointer?
    try prepare(
      """
      SELECT o.mutation_id, o.status, o.confirmation_proven, o.server_transaction_id
      FROM instant_outbox_write_keys AS slot
      JOIN instant_outbox AS o ON o.mutation_id = slot.mutation_id
      WHERE slot.entity_id = ? AND slot.attribute_id = ? AND o.mutation_id != ? AND o.status != ?
        AND (o.created_at_ms > ? OR (o.created_at_ms = ? AND o.mutation_id > ?))
      ORDER BY o.created_at_ms DESC, o.mutation_id DESC
      LIMIT 64
      """,
      statement: &statement
    )
    defer { finishStatement(statement) }
    try bind(
      [
        .text(key.entityID),
        .text(key.attributeID),
        .text(position.mutationID),
        .text(InstantMutationStatus.failed.rawValue),
        .int(position.createdAtMilliseconds),
        .int(position.createdAtMilliseconds),
        .text(position.mutationID),
      ],
      to: statement
    )
    var writes: [(id: String, accepted: Bool, serverTransactionID: String?)] = []
    while true {
      let code = sqlite3_step(statement)
      if code == SQLITE_DONE { return writes }
      guard code == SQLITE_ROW, let idBytes = sqlite3_column_text(statement, 0) else {
        throw persistenceError(operation: "find a slot's later outbox writes", message: lastErrorMessage())
      }
      let status = sqlite3_column_text(statement, 1).map { String(cString: $0) }
      writes.append((
        id: String(cString: idBytes),
        accepted: status == InstantMutationStatus.confirmed.rawValue && sqlite3_column_int64(statement, 2) == 1,
        serverTransactionID: sqlite3_column_text(statement, 3).map { String(cString: $0) }
      ))
    }
  }

  /// The values the newest stored live-query result that holds `triple`'s slot shows for it (#445).
  private func newestServerValuesWithoutTransaction(of triple: InstantTriple) throws -> [InstantValue] {
    guard
      let queryIDText = try selectScalar(
        """
        SELECT owned.query_id
        FROM instant_live_query_triples AS owned
        JOIN instant_live_query_results AS result ON result.query_id = owned.query_id
        WHERE owned.entity_id = ? AND owned.attribute_id = ?
        ORDER BY result.updated_at_ms DESC, result.query_key
        LIMIT 1
        """,
        [.text(triple.entityID), .text(triple.attributeID)]
      ),
      let queryID = Int64(queryIDText)
    else { return [] }
    var statement: OpaquePointer?
    try prepare(
      """
      SELECT value_json FROM instant_live_query_triples
      WHERE query_id = ? AND entity_id = ? AND attribute_id = ?
      ORDER BY value_json
      LIMIT 32
      """,
      statement: &statement
    )
    defer { finishStatement(statement) }
    try bind([.int(queryID), .text(triple.entityID), .text(triple.attributeID)], to: statement)
    var values: [InstantValue] = []
    while true {
      let code = sqlite3_step(statement)
      if code == SQLITE_DONE { return values }
      guard code == SQLITE_ROW, let json = sqlite3_column_text(statement, 0) else {
        throw persistenceError(operation: "read a slot's server values", message: lastErrorMessage())
      }
      values.append(try decoder.decode(InstantValue.self, from: Data(String(cString: json).utf8)))
    }
  }

  func claimAutomaticOutboxDeliveryWindow(
    _ request: InstantAutomaticOutboxClaimRequest
  ) throws -> InstantAutomaticOutboxClaimWindow {
    let energy = InstantEnergyMeter.begin(.outboxClaim); defer { energy.end() }
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
      // A claim of a process that has ended can never be answered (#990). Released before this claim, its rows go
      // out now, in order, instead of after each one's acknowledgement deadline; they are not timeouts of this runtime.
      try releaseClaimsOfEndedClaimantsWithoutTransaction(
        excludingClaimantID: request.claimantID,
        now: request.now,
        hasEnded: request.claimantHasEnded
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
      var supersededMutations: [PendingMutation] = []
      var coverageAttributes: AttributeStore?
      func coverageAttributeStore() throws -> AttributeStore {
        if let coverageAttributes { return coverageAttributes }
        let loaded = AttributeStore(
          attributes: try loadAttributesWithoutTransaction(tracesStartupCollection: false)
        )
        coverageAttributes = loaded
        return loaded
      }
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
            // Item 3 (library-78): a write offered before may already be applied. When later writes of this device
            // that the server accepted cover all of it, the server holds a newer value for every slot it sets, and
            // offering it again only earns a replay refusal; resolve it as accepted instead. Delivery stays an
            // ordered prefix: a write covered only by writes not yet accepted is still offered, and its refusal is
            // parked until they are answered (resolveRefusedWriteIfCovered).
            if candidate.deliveryStarted, !request.requiresExclusiveLane,
              case let .acceptedWrites(serverTransactionID, _) = try laterWriteCoverageWithoutTransaction(
                ofMutationID: mutation.id,
                createdAtMilliseconds: candidate.createdAtMilliseconds,
                decoded: mutation,
                acceptedOnly: true,
                attributes: coverageAttributeStore
              ).coverage,
              let superseded = try supersedeOutboxMutationWithoutTransaction(
                mutation,
                serverTransactionID: serverTransactionID
              )
            {
              supersededMutations.append(superseded)
              didChangeLifecycle = true
              didMakeNonSendingProgress = true
              continue
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
        synchronizationBlocker: synchronizationBlocker,
        supersededMutations: supersededMutations
      )
    }
    if let blocker = window.synchronizationBlocker {
      cachedState = nil
      throw blocker.error(operation: operation)
    }
    if !window.supersededMutations.isEmpty {
      cachedState = nil
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
  ///
  /// - Parameter claimToken: When given, the claim is released only if it is still the claim the response answered;
  ///   a late response must not release a newer claim of the same row (#376).
  @discardableResult
  func releaseAutomaticOutboxClaim(
    id: String,
    claimantID: String,
    claimToken: String? = nil
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
          AND (? IS NULL OR delivery_claim_token = ?)
        """,
        [
          .text(InstantOutboxDeliveryClaimState.ready.rawValue),
          .text(id),
          .text(InstantOutboxDeliveryClaimState.claimed.rawValue),
          .text(claimantID),
          claimToken.map(SQLiteBinding.text) ?? .null,
          claimToken.map(SQLiteBinding.text) ?? .null,
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
    let energy = InstantEnergyMeter.begin(.acknowledgement); defer { energy.end() }
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

      // One fingerprint for the acknowledgement's three checks: each encodes the whole transaction (#1007).
      let effectFingerprint = try optimisticEffectFingerprint(of: mutation)
      let hasPreparedMaterializedEffect = hasStoredPreparedOptimisticEffectReceipt(
        mutation,
        in: row,
        fingerprint: effectFingerprint
      )
      let alreadyAccepted = hasStoredServerAcceptance(in: row, hasPreparedReceipt: hasPreparedMaterializedEffect)
      if !alreadyAccepted {
        guard let claimPayloadFingerprint = row.deliveryClaimPayloadFingerprint,
          let claimToken,
          let materializedEffectFingerprint = effectFingerprint
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
              delivery_claim_state = ?,
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
        try setOptimisticOverlayActiveIfChangedWithoutTransaction(mutation)
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

  /// Sets the row's optimistic overlay flag to `mutation`'s overlay state, only when the row holds the other value.
  ///
  /// SQLite rewrites a row's entry in every index holding a column an `UPDATE` sets, changed or not, and three of the
  /// outbox's indexes hold this flag. An acknowledgement nearly always finds the flag at its value already, so it sets
  /// the flag apart from the row's other columns and writes no index for it then (#1007).
  private func setOptimisticOverlayActiveIfChangedWithoutTransaction(_ mutation: PendingMutation) throws {
    let overlayActive = SQLiteBinding.int(mutation.optimisticOverlayState == .removed ? 0 : 1)
    try execute(
      """
      UPDATE instant_outbox SET optimistic_overlay_active = ?
      WHERE mutation_id = ? AND optimistic_overlay_active != ?
      """,
      [overlayActive, .text(mutation.id), overlayActive]
    )
  }

  /// Applies a caller's local confirmation to one addressed row. This is the
  /// normal receive-path counterpart to `acceptOutboxMutation`; it must never
  /// reconstruct unrelated durable mutation bodies.
  func confirmOutboxMutationIfPresent(
    id: String,
    expectedOutboxRevision: Int64
  ) throws -> InstantOutboxRowAcceptance? {
    let energy = InstantEnergyMeter.begin(.acknowledgement); defer { energy.end() }
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
        adoptCachedState(state)
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

  /// Deletes the deferred payload rows of entities that no longer exist in the store.
  private func deleteDeferredValuesWithoutTransaction(entityIDs: Set<String>) throws {
    let attributeIDs = deferredValueResidency.attributeIDs.sorted()
    guard !attributeIDs.isEmpty else { return }
    let sortedEntityIDs = entityIDs.sorted()
    let attributePlaceholders = Array(repeating: "?", count: attributeIDs.count)
      .joined(separator: ", ")
    // Stay well under SQLite's bound-parameter limit.
    for start in stride(from: 0, to: sortedEntityIDs.count, by: 500) {
      let batch = Array(sortedEntityIDs[start..<min(start + 500, sortedEntityIDs.count)])
      let entityPlaceholders = Array(repeating: "?", count: batch.count).joined(separator: ", ")
      try execute(
        """
        DELETE FROM instant_triples
        WHERE attribute_id IN (\(attributePlaceholders))
          AND entity_id IN (\(entityPlaceholders))
        """,
        attributeIDs.map(SQLiteBinding.text) + batch.map(SQLiteBinding.text)
      )
    }
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
    let energy = InstantEnergyMeter.begin(.deferredHydrate); defer { energy.end() }
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
    // #1011: metered under its own name; a device profile found it outside every name.
    let energy = InstantEnergyMeter.begin(.serverApplyRetractions); defer { energy.end() }
    return try readTransaction {
      try liveQueryReplacementRetractionsWithoutTransaction(for: replacements).operations
    }
  }

  func liveQueryReplacementRetractions(
    for replacements: [InstantLiveQueryResultReplacement],
    expectedQueryResultRevision: Int64
  ) throws -> InstantLiveQueryReplacementRetractions? {
    guard !replacements.isEmpty else {
      return InstantLiveQueryReplacementRetractions(operations: [], clearedSlots: [])
    }
    let energy = InstantEnergyMeter.begin(.serverApplyRetractions); defer { energy.end() }
    return try readTransaction {
      guard try loadMetadataRevisionWithoutTransaction(Self.queryResultRevisionKey)
        == expectedQueryResultRevision
      else { return nil }
      return try liveQueryReplacementRetractionsWithoutTransaction(for: replacements)
    }
  }

  private func liveQueryReplacementRetractionsWithoutTransaction(
    for replacements: [InstantLiveQueryResultReplacement]
  ) throws -> InstantLiveQueryReplacementRetractions {
    let replacementKeys = Set(replacements.map(\.key))
    var prospective: [String: [InstantLiveTripleIdentity: InstantTriple]] = [:]
    for key in replacementKeys {
      let triples = try liveQueryResultWithoutTransaction(key: key)?.triples ?? []
      prospective[key] = Self.indexLiveTriples(triples)
    }
    let selections = try liveQuerySelectionsWithoutTransaction()
    let attributesByID = selections.attributesByID
    // The single-value attributes each replacement's query selects, by namespace, for the keys that vouch for them
    // (``liveQuerySelectedValueAttributeIDs(queryKey:attributes:)``).
    var selectedByKey: [String: [String: Set<String>]] = [:]
    for key in replacementKeys {
      if let selected = liveQuerySelections.selected(byQueryKey: key) {
        selectedByKey[key] = selected
      }
    }

    var removed: [InstantLiveTripleIdentity: InstantTriple] = [:]
    // Facts of entities that left a result entirely, rather than facts a server edit changed on an entity that is
    // still in the result.
    var departed: Set<InstantLiveTripleIdentity> = []
    // Facts that a result whose key vouches for selecting their attribute no longer holds.
    var removedFromVouchingResults: Set<InstantLiveTripleIdentity> = []
    for replacement in replacements {
      let next = Self.indexLiveTriples(replacement.triples)
      let previous = prospective[replacement.key] ?? [:]
      let nextEntityIDs = Set(next.keys.map(\.entityID))
      for (identity, triple) in previous where next[identity] == nil {
        removed[identity] = triple
        if !nextEntityIDs.contains(identity.entityID) {
          departed.insert(identity)
        }
        if let namespace = attributesByID[identity.attributeID]?.namespace,
          selectedByKey[replacement.key]?[namespace]?.contains(identity.attributeID) == true
        {
          removedFromVouchingResults.insert(identity)
        }
      }
      prospective[replacement.key] = next
    }

    let retainedByReplacements = Set(prospective.values.flatMap(\.keys))
    // A result whose key vouches for its selection is scanned for selected slots it leaves empty on the first refresh
    // of that key in this process, and again until a scan finds no value there. Those values were left by 1.9.1, or
    // by a pruned write whose slot another device cleared before any refresh restated it. The scan's work grows with
    // the result, so later refreshes of the key skip it.
    let scannedKeys = replacementKeys.filter {
      selectedByKey[$0] != nil && !liveQueryKeysWithNoClearedSlotLeft.contains($0)
    }
    // The slots the batch holds, for the entities the two rules below look at.
    var entityIDsOfInterest: Set<String> = []
    for identity in removed.keys where !departed.contains(identity) {
      entityIDsOfInterest.insert(identity.entityID)
    }
    for replacement in replacements where scannedKeys.contains(replacement.key) {
      for triple in replacement.triples {
        entityIDsOfInterest.insert(triple.entityID)
      }
    }
    var heldAttributeIDsByEntityID: [String: Set<String>] = [:]
    if !entityIDsOfInterest.isEmpty {
      for identity in retainedByReplacements where entityIDsOfInterest.contains(identity.entityID) {
        heldAttributeIDsByEntityID[identity.entityID, default: []].insert(identity.attributeID)
      }
    }
    func isHeld(_ entityID: String, _ attributeID: String) -> Bool {
      heldAttributeIDsByEntityID[entityID]?.contains(attributeID) ?? false
    }

    // Single-value slots the server cleared (#431), on entities still in a result of this batch, that no result of the
    // batch holds a value of:
    // - a slot a result held and no longer holds;
    // - a slot a result's query selects (its `fields`, or every attribute without them) and holds no value of. This is
    //   how a value no result ever held goes too.
    // Upstream builds each result's store from the server's triples alone (`createStore`), so the slot is empty there
    // and only a pending mutation overlays it. Links stay with the entity rules below. When the result's key vouches
    // for its selection, the batch is the server's newest word on the slot, so every value the store shows there goes,
    // whichever result stored earlier still lists it. Otherwise (a key this store cannot read, or a `where` across a
    // link, whose matched triples bring other entities into the result) a value another stored result owns stays.
    var newestWordSlots: Set<InstantVisibleWriteKey> = []
    var ownerCheckedSlots: Set<InstantVisibleWriteKey> = []
    for identity in removed.keys where !departed.contains(identity) {
      if case .ref = identity.value { continue }
      guard !isHeld(identity.entityID, identity.attributeID),
        attributesByID[identity.attributeID]?.cardinality == .one
      else { continue }
      let slot = InstantVisibleWriteKey(entityID: identity.entityID, attributeID: identity.attributeID)
      if removedFromVouchingResults.contains(identity) {
        newestWordSlots.insert(slot)
      } else {
        ownerCheckedSlots.insert(slot)
      }
    }
    var scannedSlotsByKey: [String: Set<InstantVisibleWriteKey>] = [:]
    for replacement in replacements where scannedKeys.contains(replacement.key) {
      guard let selected = selectedByKey[replacement.key] else { continue }
      var namespaceByEntityID: [String: String] = [:]
      var mixedEntityIDs: Set<String> = []
      for triple in replacement.triples {
        guard let namespace = attributesByID[triple.attributeID]?.namespace
          ?? InstantLiveQueryNestedLimit.namespace(in: triple.attributeID)
        else {
          mixedEntityIDs.insert(triple.entityID)
          continue
        }
        if let known = namespaceByEntityID[triple.entityID], known != namespace {
          mixedEntityIDs.insert(triple.entityID)
        }
        namespaceByEntityID[triple.entityID] = namespace
      }
      var slots: Set<InstantVisibleWriteKey> = []
      for (entityID, namespace) in namespaceByEntityID where !mixedEntityIDs.contains(entityID) {
        for attributeID in selected[namespace] ?? [] where !isHeld(entityID, attributeID) {
          slots.insert(InstantVisibleWriteKey(entityID: entityID, attributeID: attributeID))
        }
      }
      scannedSlotsByKey[replacement.key, default: []].formUnion(slots)
      newestWordSlots.formUnion(slots)
    }
    ownerCheckedSlots.subtract(newestWordSlots)
    let candidateSlots = newestWordSlots.union(ownerCheckedSlots)

    // A pending write of a cleared slot keeps its value (`protectingServerRetractions`).
    var clearedSlots: Set<InstantVisibleWriteKey> = []
    var retractions: [InstantTriple] = []
    var retracted: Set<InstantLiveTripleIdentity> = []
    var slotsShowingAValue: Set<InstantVisibleWriteKey> = []
    let orderedCandidates = candidateSlots.sorted {
      ($0.entityID, $0.attributeID) < ($1.entityID, $1.attributeID)
    }
    // Stay well under SQLite's bound-parameter limit.
    for start in stride(from: 0, to: orderedCandidates.count, by: 400) {
      let batch = orderedCandidates[start..<min(start + 400, orderedCandidates.count)]
      let resident: [InstantTriple] = try selectJSON(
        "SELECT json FROM instant_triples WHERE (entity_id, attribute_id) IN (VALUES "
          + Array(repeating: "(?, ?)", count: batch.count).joined(separator: ", ") + ")",
        batch.flatMap { [SQLiteBinding.text($0.entityID), .text($0.attributeID)] }
      )
      for fact in resident {
        let slot = InstantVisibleWriteKey(entityID: fact.entityID, attributeID: fact.attributeID)
        slotsShowingAValue.insert(slot)
        let identity = InstantLiveTripleIdentity(fact)
        if !newestWordSlots.contains(slot),
          try liveQueryTripleHasOwnerWithoutTransaction(identity, excludingQueryKeys: replacementKeys)
        {
          continue
        }
        guard retracted.insert(identity).inserted else { continue }
        clearedSlots.insert(slot)
        retractions.append(fact)
      }
    }
    // A scanned key whose selected empty slots showed no value has nothing left to heal in this process.
    for (key, slots) in scannedSlotsByKey where slots.isDisjoint(with: slotsShowingAValue) {
      if liveQueryKeysWithNoClearedSlotLeft.count >= 4_096 {
        liveQueryKeysWithNoClearedSlotLeft.removeAll(keepingCapacity: true)
      }
      liveQueryKeysWithNoClearedSlotLeft.insert(key)
    }

    // The other facts the results no longer hold: links, values of many-valued attributes, the facts of an entity
    // that left a result, and the old value of a slot the batch holds a new value of. Each goes unless another stored
    // result still owns it.
    for identity in removed.keys where !retainedByReplacements.contains(identity) {
      // A cleared slot's values went above; a value the store no longer shows there needs no retraction.
      if candidateSlots.contains(InstantVisibleWriteKey(entityID: identity.entityID, attributeID: identity.attributeID)) {
        continue
      }
      if try liveQueryTripleHasOwnerWithoutTransaction(
        identity,
        excludingQueryKeys: replacementKeys
      ) {
        continue
      }
      if let triple = removed[identity], retracted.insert(identity).inserted {
        retractions.append(triple)
      }
    }
    // An entity that left one result is collected whole or not at all, as result pruning collects it (#259). If it
    // still has a stored fact this retraction would not remove (another result owns it, or no result ever did, like a
    // field this device wrote), it still exists: keep every fact it left behind. Retracting them one at a time
    // stripped the list-only fields (wallClockStartedAtMs, wallClockEndedAtMs, sentToInstantAtMs) from Scribe segments
    // the live timeline still held when their preview slot moved (Recording 023, #296).
    let candidates = Set(retractions.map(InstantLiveTripleIdentity.init))
    let departedEntityIDs = Set(candidates.intersection(departed).map(\.entityID))
    var keptEntityIDs: Set<String> = []
    for entityID in departedEntityIDs.sorted() {
      let stored: [InstantTriple] = try selectJSON(
        "SELECT json FROM instant_triples WHERE entity_id = ?",
        [.text(entityID)]
      )
      if stored.contains(where: { !candidates.contains(InstantLiveTripleIdentity($0)) }) {
        keptEntityIDs.insert(entityID)
      }
    }
    retractions.removeAll {
      keptEntityIDs.contains($0.entityID) && departed.contains(InstantLiveTripleIdentity($0))
    }
    return InstantLiveQueryReplacementRetractions(
      // The tuple order, without building both values' keys on every comparison (#1007).
      operations: retractions
        .sorted(by: InstantPersistedLiveQueryResult.storedOrder)
        .map(InstantTripleOperation.retract),
      clearedSlots: clearedSlots
    )
  }

  /// The single-value, non-link attributes a live query selects, by the namespace of the entities that hold them, from
  /// its registration key (the InstaQL query): each level's `fields`, or every attribute of its namespace without
  /// them. A namespace at several levels keeps only what every one of them selects. Nil when the key does not vouch for
  /// its selection, so no slot is taken for cleared on its word (#431): the key is not an InstaQL query, one of its
  /// namespaces or links is unknown, or a level's `where` names a path through a link.
  static func liveQuerySelectedValueAttributeIDs(
    queryKey: String,
    attributes: [InstantAttribute]
  ) -> [String: Set<String>]? {
    guard let object = try? JSONSerialization.jsonObject(with: Data(queryKey.utf8)) as? [String: Any],
      !object.isEmpty
    else { return nil }
    var attributesByNamespace: [String: [InstantAttribute]] = [:]
    for attribute in attributes {
      attributesByNamespace[attribute.namespace, default: []].append(attribute)
    }
    func childNamespace(of parent: String, include: String) -> String? {
      let identity = "\(parent)/\(include)"
      if let reverseLink = attributes.first(where: { $0.reverseIdentity == identity }) {
        return reverseLink.namespace
      }
      return attributes.first {
        $0.namespace == parent && $0.name == include && $0.valueType == .ref
      }?.linkNamespace
    }
    // A path through a link (`"parent.id"`): the server sends the triples it matched, which bring the linked entities
    // into the result without their selected attributes.
    func whereCrossesALink(_ filter: Any) -> Bool {
      if let object = filter as? [String: Any] {
        return object.contains { key, value in key.contains(".") || whereCrossesALink(value) }
      }
      if let array = filter as? [Any] {
        return array.contains(where: whereCrossesALink)
      }
      return false
    }
    var selected: [String: Set<String>] = [:]
    func visit(_ namespace: String, _ node: [String: Any]) -> Bool {
      guard let namespaceAttributes = attributesByNamespace[namespace] else { return false }
      if let filter = (node["$"] as? [String: Any])?["where"], whereCrossesALink(filter) { return false }
      let fields = ((node["$"] as? [String: Any])?["fields"] as? [Any]).map {
        Set($0.compactMap { $0 as? String })
      }
      let attributeIDs = Set(
        namespaceAttributes
          .filter { $0.cardinality == .one && $0.valueType != .ref && (fields?.contains($0.name) ?? true) }
          .map(\.id)
      )
      selected[namespace] = selected[namespace].map { $0.intersection(attributeIDs) } ?? attributeIDs
      for (include, value) in node where include != "$" {
        guard let child = value as? [String: Any],
          let childNamespace = childNamespace(of: namespace, include: include),
          visit(childNamespace, child)
        else { return false }
      }
      return true
    }
    for (namespace, value) in object {
      guard let node = value as? [String: Any], visit(namespace, node) else { return nil }
    }
    return selected
  }

  /// ``liveQuerySelections`` for the stored attributes as they are now.
  private func liveQuerySelectionsWithoutTransaction() throws -> LiveQuerySelections {
    let attributes = try attributesForLiveResultSaveWithoutTransaction()
    if let stamp = liveResultAttributes.map({ ($0.revision, $0.generation) }),
      liveQuerySelections.stamp.map({ $0 == stamp }) != true
    {
      liveQuerySelections = LiveQuerySelections(stamp: stamp, attributes: attributes)
    }
    return liveQuerySelections
  }

  struct LiveQuerySelections {
    /// The `liveResultAttributes` revision and generation these were read off.
    var stamp: (Int64, Int)?
    var attributes: [InstantAttribute] = []
    var attributesByID: [String: InstantAttribute] = [:]
    private var selectedByQueryKey: [String: [String: Set<String>]?] = [:]

    init() {}

    init(stamp: (Int64, Int), attributes: [InstantAttribute]) {
      self.stamp = stamp
      self.attributes = attributes
      attributesByID = Dictionary(attributes.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// ``SQLitePersistenceStore/liveQuerySelectedValueAttributeIDs(queryKey:attributes:)`` for `queryKey`, kept for the
    /// next refresh of the same query. A paged query's key changes with its cursor, so at most 256 keys are kept.
    mutating func selected(byQueryKey queryKey: String) -> [String: Set<String>]? {
      if let selected = selectedByQueryKey[queryKey] { return selected }
      let selected = SQLitePersistenceStore.liveQuerySelectedValueAttributeIDs(
        queryKey: queryKey,
        attributes: attributes
      )
      if selectedByQueryKey.count >= 256 { selectedByQueryKey.removeAll(keepingCapacity: true) }
      selectedByQueryKey[queryKey] = .some(selected)
      return selected
    }
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
    let energy = InstantEnergyMeter.begin(.prune); defer { energy.end() }
    return try transaction {
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
      try writeStoredFileRecord(savedFile)
    } catch {
      try? FileManager.default.removeItem(at: targetURL)
      throw error
    }
    return savedFile
  }

  /// Records a file that storage holds, with no copy on this device (#959): an upload's file, whose bytes the caller
  /// keeps. The record lists the file offline and names it for a later download.
  public func saveUploadedFileRecord(_ file: InstantStoredFile) throws -> InstantStoredFile {
    var savedFile = file
    savedFile.localPath = ""
    try writeStoredFileRecord(savedFile)
    return savedFile
  }

  /// Marks a stored file's record as having no copy on this device, once the caller removed the copy (#959). Nil
  /// when there is no record.
  public func forgetStoredFileCopy(appID: String, fileID: String) throws -> InstantStoredFile? {
    guard var file = try loadStoredFile(appID: appID, fileID: fileID) else { return nil }
    file.localPath = ""
    try writeStoredFileRecord(file)
    return file
  }

  private func writeStoredFileRecord(_ file: InstantStoredFile) throws {
    try execute(
      """
      INSERT OR REPLACE INTO instant_files
        (app_id, file_id, name, created_at_ms, updated_at_ms, json)
      VALUES (?, ?, ?, ?, ?, ?)
      """,
      [
        .text(file.appID),
        .text(file.id),
        .text(file.name),
        .int(file.createdAt.milliseconds),
        .int(file.updatedAt.milliseconds),
        .text(try encode(file)),
      ]
    )
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
      try writeStoredFileRecord(savedFile)
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
    // #959: a record without a copy (an upload's, or an evicted one) takes no room here.
    let files = try loadStoredFiles(appID: appID).filter(\.isDownloaded)
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
      downloadedFileCount: files.count,
      localCacheFile: try localCacheFile()
    )
  }

  // MARK: - Free pages (#1015)

  /// The `auto_vacuum` mode a new cache file starts in (#1015): `NONE`, which costs ordinary writes nothing. The write
  /// cost measurement (`InstantLocalCacheWriteCostTests`) creates caches in each mode with it.
  @TaskLocal package static var newCacheAutoVacuum: InstantLocalCacheFile.AutoVacuum = .none

  /// The cache file's pages as SQLite counts them: `page_size`, `page_count`, `freelist_count` and `auto_vacuum`, four
  /// reads of the file's header (#1015).
  package func localCacheFile() throws -> InstantLocalCacheFile {
    InstantLocalCacheFile(
      pageSize: Int(try selectInt64("PRAGMA page_size")),
      pageCount: Int(try selectInt64("PRAGMA page_count")),
      freePageCount: Int(try selectInt64("PRAGMA freelist_count")),
      autoVacuum: InstantLocalCacheFile.AutoVacuum(sqliteValue: try selectInt64("PRAGMA auto_vacuum"))
    )
  }

  /// `PRAGMA cache_spill` on this connection: how many dirty pages a transaction keeps in memory before it writes
  /// them out (#1015).
  package func cacheSpillPagesForTesting() throws -> Int64 {
    try selectInt64("PRAGMA cache_spill")
  }

  /// Rewrites the cache file without its free pages: one `VACUUM` (#1015).
  ///
  /// In WAL mode SQLite builds the copy in a temporary file, writes it through the WAL and checkpoints it, so the live
  /// pages are written three times: on a copy of the phone's cache, 630-645 MB for 197 MB of live pages, in 0.8-1.0 s
  /// on a Mac mini, with a copy and a WAL as large on the volume meanwhile. Apple's SQLite keeps up to 20,000 dirty
  /// pages (`cache_spill`) in memory before it writes them out, whatever `cache_size` says: the `VACUUM` peaked at
  /// 194 MB of memory, and at 21 MB spilling past 256 pages, for 2% more writes. That bound holds for the `VACUUM`
  /// alone. A passive checkpoint after it shrinks the file at once unless a reader still holds an older snapshot.
  /// `VACUUM INTO` and a swap would write the live pages once, but the swap needs every connection to the file closed.
  package func vacuum() throws {
    let cacheSpill = try selectInt64("PRAGMA cache_spill")
    try execute("PRAGMA cache_spill = 256")
    defer { _ = try? execute("PRAGMA cache_spill = \(cacheSpill)") }
    let interval = InstantEnergyMeter.begin(.localCacheVacuum)
    defer { interval.end() }
    try execute("VACUUM")
    _ = sqlite3_wal_checkpoint_v2(connection.raw, nil, SQLITE_CHECKPOINT_PASSIVE, nil, nil)
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
    // #959: a record without a copy is read from storage, like a file this device never had.
    guard let file = try loadStoredFile(appID: appID, fileID: fileID), file.isDownloaded else {
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
      try createStreamWithoutTransaction(
        appID: appID,
        streamID: streamID,
        clientID: clientID,
        userID: userID,
        createdAt: createdAt
      )
    }
  }

  /// Creates a stream this device writes while the server cannot name it, and records it for the server (#329).
  func createWrittenStream(
    appID: String,
    streamID: String,
    clientID: String,
    userID: String,
    createdAt: InstantTimestamp
  ) throws -> InstantStreamMetadata {
    try transaction {
      let metadata = try createStreamWithoutTransaction(
        appID: appID,
        streamID: streamID,
        clientID: clientID,
        userID: userID,
        createdAt: createdAt
      )
      try insertStreamWriterWithoutTransaction(
        appID: appID,
        streamID: streamID,
        clientID: clientID,
        reconnectToken: nil,
        serverStreamID: nil
      )
      return metadata
    }
  }

  private func createStreamWithoutTransaction(
    appID: String,
    streamID: String,
    clientID: String,
    userID: String,
    createdAt: InstantTimestamp
  ) throws -> InstantStreamMetadata {
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
      try ensureStreamMetadataWithoutTransaction(
        appID: appID,
        streamID: streamID,
        clientID: clientID,
        userID: userID,
        createdAt: createdAt
      )
    }
  }

  /// Stores a stream this device writes, which the server started under `streamID`, and records it for the server
  /// so a reconnect or relaunch can restart it (#329).
  func ensureWrittenStreamMetadata(
    appID: String,
    streamID: String,
    clientID: String,
    reconnectToken: String,
    userID: String,
    createdAt: InstantTimestamp
  ) throws -> InstantStreamMetadata {
    try transaction {
      let metadata = try ensureStreamMetadataWithoutTransaction(
        appID: appID,
        streamID: streamID,
        clientID: clientID,
        userID: userID,
        createdAt: createdAt
      )
      try insertStreamWriterWithoutTransaction(
        appID: appID,
        streamID: streamID,
        clientID: clientID,
        reconnectToken: reconnectToken,
        serverStreamID: streamID
      )
      return metadata
    }
  }

  private func ensureStreamMetadataWithoutTransaction(
    appID: String,
    streamID: String,
    clientID: String,
    userID: String,
    createdAt: InstantTimestamp
  ) throws -> InstantStreamMetadata {
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

  /// The streams `userID` writes on this device whose server copy may lack content or the close, oldest first.
  func loadStreamWritersAwaitingServer(appID: String, userID: String) throws -> [InstantStreamWriterRecord] {
    try readTransaction {
      try selectJSON(
        """
        SELECT json_object(
          'streamID', writers.stream_id,
          'clientID', writers.client_id,
          'reconnectToken', writers.reconnect_token,
          'serverStreamID', writers.server_stream_id
        )
        FROM instant_stream_writers AS writers
        JOIN instant_streams AS streams
          ON streams.app_id = writers.app_id AND streams.stream_id = writers.stream_id
        WHERE writers.app_id = ? AND writers.state = ? AND streams.user_id = ?
        ORDER BY writers.rowid
        """,
        [.text(appID), .text(InstantStreamWriterState.catchingUp.rawValue), .text(userID)]
      )
    }
  }

  /// Whether this device writes the stream, as opposed to reading one another device writes.
  func isWrittenStream(appID: String, streamID: String) throws -> Bool {
    try readTransaction {
      let found: String? = try selectScalar(
        "SELECT stream_id FROM instant_stream_writers WHERE app_id = ? AND stream_id = ? LIMIT 1",
        [.text(appID), .text(streamID)]
      )
      return found != nil
    }
  }

  /// Stores the reconnect token a stream written offline presents at its first start, before it is sent.
  func recordStreamWriterReconnectToken(appID: String, streamID: String, reconnectToken: String) throws {
    try transaction {
      try execute(
        "UPDATE instant_stream_writers SET reconnect_token = ? WHERE app_id = ? AND stream_id = ?",
        [.text(reconnectToken), .text(appID), .text(streamID)]
      )
    }
  }

  func recordStreamWriterServerStreamID(appID: String, streamID: String, serverStreamID: String) throws {
    try transaction {
      try execute(
        "UPDATE instant_stream_writers SET server_stream_id = ? WHERE app_id = ? AND stream_id = ?",
        [.text(serverStreamID), .text(appID), .text(streamID)]
      )
    }
  }

  /// Records that the server confirmed the stream's close, so no later connection restarts it.
  func recordStreamWriterDelivered(appID: String, streamID: String) throws {
    try transaction {
      try execute(
        "UPDATE instant_stream_writers SET state = ? WHERE app_id = ? AND stream_id = ?",
        [.text(InstantStreamWriterState.delivered.rawValue), .text(appID), .text(streamID)]
      )
    }
  }

  /// Records that the server refused the stream, so no later connection asks again.
  func recordStreamWriterRefused(appID: String, streamID: String, message: String) throws {
    try transaction {
      try execute(
        "UPDATE instant_stream_writers SET state = ?, refusal = ? WHERE app_id = ? AND stream_id = ?",
        [.text(InstantStreamWriterState.refused.rawValue), .text(message), .text(appID), .text(streamID)]
      )
    }
  }

  private func insertStreamWriterWithoutTransaction(
    appID: String,
    streamID: String,
    clientID: String,
    reconnectToken: String?,
    serverStreamID: String?
  ) throws {
    try execute(
      """
      INSERT OR IGNORE INTO instant_stream_writers
        (app_id, stream_id, client_id, reconnect_token, server_stream_id, state)
      VALUES (?, ?, ?, ?, ?, ?)
      """,
      [
        .text(appID),
        .text(streamID),
        .text(clientID),
        reconnectToken.map { .text($0) } ?? .null,
        serverStreamID.map { .text($0) } ?? .null,
        .text(InstantStreamWriterState.catchingUp.rawValue),
      ]
    )
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

  /// The stored byte count of a stream, without reading its content; `nil` when the stream is not stored here.
  func loadStreamContentByteCount(appID: String, streamID: String) throws -> Int64? {
    try readTransaction {
      guard try streamMetadataWithoutTransaction(appID: appID, streamID: streamID) != nil else { return nil }
      return try streamContentSizeWithoutTransaction(appID: appID, streamID: streamID)
    }
  }

  /// Up to `limit` stored chunks of a stream that end after `offset`, in order: what a writer resends to a server
  /// that holds `offset` bytes (#329).
  func loadStreamContentChunks(
    appID: String,
    streamID: String,
    endingAfter offset: Int64,
    limit: Int
  ) throws -> [InstantStreamContentChunk] {
    try readTransaction {
      try selectJSON(
        """
        SELECT json FROM instant_stream_content_chunks
        WHERE app_id = ? AND stream_id = ? AND offset + byte_count > ?
        ORDER BY offset, chunk_id
        LIMIT ?
        """,
        [.text(appID), .text(streamID), .int(offset), .int(Int64(limit))]
      )
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

  /// Prunes the stored live-query results the policy selects in one transaction, and returns the whole state after it.
  ///
  /// For callers without a hot store: the store's facts come from SQLite, so this reads every fact. The runtime prunes
  /// with
  /// ``liveQueryResultPruneBatch(policy:now:preservingQueryKeys:maximumRemovedTripleCount:carriedReleasedIdentities:)``
  /// and ``applyLiveQueryResultPruneBatch(_:policy:now:residentFacts:)`` instead, which read only the facts the removed
  /// results held (#654). All three choose and keep by the same rules, in the same order.
  ///
  /// - Parameters:
  ///   - maximumRemovedTripleCount: Remove at most this many result triples in this call (at least one row), and say
  ///     whether rows the policy removes are left, so the caller can release the operation gate between bounded
  ///     batches (#303, item 6). `nil` removes everything the policy selects at once.
  ///   - carriedReleasedIdentities: The previous batch's `retainedReleasedIdentities`.
  func pruneLiveQueryResults(
    policy: InstantLiveQueryResultPruningPolicy,
    now: InstantTimestamp,
    preservingQueryKeys: Set<String> = [],
    maximumRemovedTripleCount: Int? = nil,
    carriedReleasedIdentities: Set<InstantLiveTripleIdentity> = []
  ) throws -> InstantLiveQueryResultPruningApplication {
    let energy = InstantEnergyMeter.begin(.prune); defer { energy.end() }
    let application = try transaction {
      let revisions = try liveQueryResultPruneRevisionsWithoutTransaction()
      let currentState: InstantPersistenceState
      if var cachedState,
        cachedState.storeRevision == revisions.store,
        cachedState.attributeRevision == revisions.attribute,
        cachedState.outboxRevision == revisions.outbox
      {
        cachedState.queryResultRevision = revisions.queryResult
        if cachedState.snapshot.store.triples.isEmpty {
          cachedState.snapshot.store = try loadStoreSnapshotWithoutTransaction(
            tracesStartupCollections: false
          )
        }
        currentState = cachedState
      } else {
        currentState = try InstantPersistenceState(
          snapshot: loadCompactSnapshotWithoutTransaction(),
          storeRevision: revisions.store,
          outboxRevision: revisions.outbox,
          attributeRevision: revisions.attribute,
          queryResultRevision: revisions.queryResult
        )
      }
      let batch = try liveQueryResultPruneBatchWithoutTransaction(
        policy: policy,
        now: now,
        preservingQueryKeys: preservingQueryKeys,
        maximumRemovedTripleCount: maximumRemovedTripleCount,
        carriedReleasedIdentities: carriedReleasedIdentities,
        revisions: revisions
      )
      guard !batch.removedQueryKeys.isEmpty else {
        try collectUnloadedLiveQueryResultsWithoutTransaction(
          policy: policy,
          now: now,
          loadedRows: batch.remainingRows
        )
        return InstantLiveQueryResultPruningApplication(result: batch.resultRemovingNothing, state: currentState)
      }
      let releasedEntityIDs = batch.releasedEntityIDs
      let applied = try applyLiveQueryResultPruneBatchWithoutTransaction(
        batch,
        policy: policy,
        now: now,
        residentFacts: currentState.snapshot.store.triples.filter { releasedEntityIDs.contains($0.entityID) }
      )
      var snapshot = currentState.snapshot
      let removedEntityIDs = applied.removedEntityIDs
      if !removedEntityIDs.isEmpty {
        snapshot.store.triples.removeAll { removedEntityIDs.contains($0.entityID) }
      }
      return InstantLiveQueryResultPruningApplication(
        result: applied.result,
        state: InstantPersistenceState(
          snapshot: snapshot,
          storeRevision: applied.storeRevision,
          outboxRevision: revisions.outbox,
          attributeRevision: revisions.attribute,
          queryResultRevision: applied.queryResultRevision
        ),
        hasMoreToRemove: applied.hasMoreToRemove,
        retainedReleasedIdentities: applied.retainedReleasedIdentities
      )
    }
    adoptCachedState(application.state)
    return application
  }

  /// Chooses the next live-query prune batch (#654): the stored results the policy removes, from the results' own rows,
  /// and the facts those results hold. It reads no other fact of the store, so it costs in proportion to the results
  /// it chooses. Pass the hot store's facts of ``InstantLiveQueryResultPruneBatch/releasedEntityIDs`` to
  /// ``applyLiveQueryResultPruneBatch(_:policy:now:residentFacts:)``.
  ///
  /// Choosing an empty batch also collects the unloaded results the policy collects, as a prune that removed nothing
  /// always did.
  ///
  /// - Parameters:
  ///   - preservingQueryKeys: The open queries' keys. Their results stay, and every other result is unloaded (#1006);
  ///     empty at bootstrap, when only the policy's limits remove results.
  ///   - maximumRemovedTripleCount: Choose about this many result triples (at least one result), so the caller can
  ///     release the operation gate between bounded batches (#303, item 6); `nil` chooses everything at once.
  ///   - carriedReleasedIdentities: The previous batch's `retainedReleasedIdentities`.
  func liveQueryResultPruneBatch(
    policy: InstantLiveQueryResultPruningPolicy,
    now: InstantTimestamp,
    preservingQueryKeys: Set<String>,
    maximumRemovedTripleCount: Int?,
    carriedReleasedIdentities: Set<InstantLiveTripleIdentity>
  ) throws -> InstantLiveQueryResultPruneBatch {
    let energy = InstantEnergyMeter.begin(.prune); defer { energy.end() }
    return try transaction {
      let batch = try liveQueryResultPruneBatchWithoutTransaction(
        policy: policy,
        now: now,
        preservingQueryKeys: preservingQueryKeys,
        maximumRemovedTripleCount: maximumRemovedTripleCount,
        carriedReleasedIdentities: carriedReleasedIdentities,
        revisions: try liveQueryResultPruneRevisionsWithoutTransaction()
      )
      if batch.removedQueryKeys.isEmpty {
        try collectUnloadedLiveQueryResultsWithoutTransaction(
          policy: policy,
          now: now,
          loadedRows: batch.remainingRows
        )
      }
      return batch
    }
  }

  /// Removes `batch`'s results and the entities only they held, in one transaction (#654).
  ///
  /// A released fact is dropped when no stored result still holds it (the ownership index answers that per fact) and
  /// the store holds it; an entity is dropped whole or not at all, so one with a fact no result released stays (#259).
  /// SQLite loses each dropped entity's rows by its id. The cached state moves past the batch without being rebuilt.
  ///
  /// - Parameter residentFacts: The hot store's facts of `batch.releasedEntityIDs`, all of them: the whole-entity rule
  ///   needs every fact of each entity it might drop.
  /// - Returns: The batch's changes, its `removedFacts` for the hot store to retract; nil when the store, its schema,
  ///   the outbox or the stored results changed after `batch` was chosen, with nothing written, to choose again.
  func applyLiveQueryResultPruneBatch(
    _ batch: InstantLiveQueryResultPruneBatch,
    policy: InstantLiveQueryResultPruningPolicy,
    now: InstantTimestamp,
    residentFacts: [InstantTriple]
  ) throws -> InstantLiveQueryResultPruneBatchApplication? {
    let energy = InstantEnergyMeter.begin(.prune); defer { energy.end() }
    let application: InstantLiveQueryResultPruneBatchApplication? = try transaction {
      guard try liveQueryResultPruneRevisionsWithoutTransaction() == batch.revisions else { return nil }
      return try applyLiveQueryResultPruneBatchWithoutTransaction(
        batch,
        policy: policy,
        now: now,
        residentFacts: residentFacts
      )
    }
    if let application {
      advanceCachedStateAfterLiveQueryResultPrune(from: batch.revisions, application: application)
    }
    return application
  }

  private func liveQueryResultPruneRevisionsWithoutTransaction() throws -> LiveQueryResultPruneRevisions {
    LiveQueryResultPruneRevisions(
      store: try loadMetadataRevisionWithoutTransaction(Self.storeRevisionKey),
      attribute: try loadMetadataRevisionWithoutTransaction(Self.attributeRevisionKey),
      outbox: try loadMetadataRevisionWithoutTransaction(Self.outboxRevisionKey),
      queryResult: try loadMetadataRevisionWithoutTransaction(Self.queryResultRevisionKey)
    )
  }

  /// The policy's choice among the stored results' rows, bounded to one batch, and the facts the chosen results hold.
  private func liveQueryResultPruneBatchWithoutTransaction(
    policy: InstantLiveQueryResultPruningPolicy,
    now: InstantTimestamp,
    preservingQueryKeys: Set<String>,
    maximumRemovedTripleCount: Int?,
    carriedReleasedIdentities: Set<InstantLiveTripleIdentity>,
    revisions: LiveQueryResultPruneRevisions
  ) throws -> InstantLiveQueryResultPruneBatch {
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

    // A closed query's result is unloaded, not deleted (#1006): its facts leave the store as a deleted result's do,
    // and its stored copy answers the query's next subscription before the server does. Upstream
    // `PersistedObject.unloadKey` "unloads the key so that it can be garbage collected, but does not delete it".
    var unloadingKeys: Set<String> = []
    if !preservingQueryKeys.isEmpty {
      for row in Array(rows) where !preservingQueryKeys.contains(row.queryKey) {
        if remove(row) { unloadingKeys.insert(row.queryKey) }
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

    // A bounded batch removes the selected rows in selection order until it holds about the budget's triples; the
    // rest stay for the next batch, which selects them again.
    var deferredRows: [LiveQueryResultStorageRow] = []
    if let maximumRemovedTripleCount, removedRows.count > 1 {
      var batch: [LiveQueryResultStorageRow] = []
      var batchTripleCount = 0
      for row in removedRows {
        if !batch.isEmpty, batchTripleCount + row.tripleCount > maximumRemovedTripleCount {
          deferredRows.append(row)
          continue
        }
        batch.append(row)
        batchTripleCount += row.tripleCount
      }
      removedRows = batch
      rows.append(contentsOf: deferredRows)
    }

    var releasedIdentities = carriedReleasedIdentities
    var unreadableQueryKeys: Set<String> = []
    for row in removedRows {
      guard let result = try liveQueryResultWithoutTransaction(key: row.queryKey) else {
        // As before #654: a row whose result cannot be read stays, and releases nothing.
        unreadableQueryKeys.insert(row.queryKey)
        continue
      }
      for triple in result.triples {
        releasedIdentities.insert(InstantLiveTripleIdentity(triple))
      }
    }
    return InstantLiveQueryResultPruneBatch(
      removedQueryKeys: removedRows.map(\.queryKey),
      hasMoreToRemove: !deferredRows.isEmpty,
      releasedIdentities: releasedIdentities,
      unloadingQueryKeys: unloadingKeys,
      unreadableQueryKeys: unreadableQueryKeys,
      remainingRows: rows,
      revisions: revisions
    )
  }

  /// Removes `batch`'s results, then the entities only they held among `residentFacts`.
  private func applyLiveQueryResultPruneBatchWithoutTransaction(
    _ batch: InstantLiveQueryResultPruneBatch,
    policy: InstantLiveQueryResultPruningPolicy,
    now: InstantTimestamp,
    residentFacts: [InstantTriple]
  ) throws -> InstantLiveQueryResultPruneBatchApplication {
    var unloadedKeys: [String] = []
    for queryKey in batch.removedQueryKeys where !batch.unreadableQueryKeys.contains(queryKey) {
      if batch.unloadingQueryKeys.contains(queryKey) {
        try unloadLiveQueryResultWithoutTransaction(key: queryKey)
        unloadedKeys.append(queryKey)
      }
      // Its ownership rows go with it (`ON DELETE CASCADE`), so the checks below see only the results that stay.
      try execute(
        "DELETE FROM instant_live_query_results WHERE query_key = ?",
        [.text(queryKey)]
      )
      try forgetLiveQueryResultJSONStateWithoutTransaction(queryKey)
    }
    try collectUnloadedLiveQueryResultsWithoutTransaction(
      policy: policy,
      now: now,
      loadedRows: batch.remainingRows
    )

    // #654: the released entities' own facts stand in for the whole store, which each batch used to copy into a
    // dictionary of every fact to answer these same questions.
    let residentIdentities = Set(residentFacts.lazy.map(InstantLiveTripleIdentity.init))
    var orphanedIdentities: Set<InstantLiveTripleIdentity> = []
    for identity in batch.releasedIdentities where residentIdentities.contains(identity) {
      guard !(try liveQueryTripleHasOwnerWithoutTransaction(identity, excludingQueryKeys: [])) else { continue }
      orphanedIdentities.insert(identity)
    }
    // Collect whole entities only. An entity that still has a fact no remaining result owns
    // (typically one this device wrote that the pruned query never selected) is local data;
    // removing just the pruned query's facts left rows with `text` but no `recordingID`, which
    // no relationship or filter can reach again (#259).
    let candidateEntityIDs = Set(orphanedIdentities.lazy.map(\.entityID))
    var retainedEntityIDs: Set<String> = []
    for triple in residentFacts
    where candidateEntityIDs.contains(triple.entityID)
      && !orphanedIdentities.contains(InstantLiveTripleIdentity(triple))
    {
      retainedEntityIDs.insert(triple.entityID)
    }
    let removedEntityIDs = candidateEntityIDs.subtracting(retainedEntityIDs)
    let removedFacts = residentFacts.filter { removedEntityIDs.contains($0.entityID) }
    let retainedReleasedIdentities = Set(
      batch.releasedIdentities.lazy.filter {
        retainedEntityIDs.contains($0.entityID) && residentIdentities.contains($0)
      }
    )
    // The whole-store diff this replaced deleted every row of each entity that left the store, its deferred payloads
    // and anything else SQLite held of it among them, so a removed entity's rows go by its id.
    for entityID in removedEntityIDs.sorted() {
      try execute("DELETE FROM instant_triples WHERE entity_id = ?", [.text(entityID)])
    }
    let storeRevision = removedFacts.isEmpty
      ? batch.revisions.store
      : try bumpMetadataRevisionWithoutTransaction(Self.storeRevisionKey)
    let queryResultRevision = try bumpMetadataRevisionWithoutTransaction(Self.queryResultRevisionKey)
    return InstantLiveQueryResultPruneBatchApplication(
      result: InstantLiveQueryResultPruningResult(
        removedQueryKeys: batch.removedQueryKeys,
        remainingQueryKeys: batch.remainingRows.map(\.queryKey),
        removedOrphanedTripleCount: removedFacts.count,
        remainingEntryCount: batch.remainingRows.count,
        remainingTripleCount: batch.remainingRows.reduce(0) { $0 + $1.tripleCount },
        unloadedQueryKeys: unloadedKeys
      ),
      removedFacts: removedFacts,
      storeRevision: storeRevision,
      attributeRevision: batch.revisions.attribute,
      queryResultRevision: queryResultRevision,
      hasMoreToRemove: batch.hasMoreToRemove,
      retainedReleasedIdentities: retainedReleasedIdentities
    )
  }

  /// Moves the cached state past a prune batch (#654): its revisions, and the removed entities out of any facts it
  /// keeps. The prune used to adopt the whole state it rebuilt; a cache at other revisions is dropped, as
  /// `advanceCachedRevisionDomains` drops one, and its next reader loads it.
  private func advanceCachedStateAfterLiveQueryResultPrune(
    from revisions: LiveQueryResultPruneRevisions,
    application: InstantLiveQueryResultPruneBatchApplication
  ) {
    var removedEntityTriples: [String: [InstantTriple]] = [:]
    for fact in application.removedFacts {
      removedEntityTriples[fact.entityID] = []
    }
    // Like the prune before #654, the stored results' revision is taken from SQLite rather than matched.
    if var state = cachedState,
      state.storeRevision == revisions.store,
      state.attributeRevision == revisions.attribute,
      state.outboxRevision == revisions.outbox
    {
      if !state.snapshot.store.triples.isEmpty, !removedEntityTriples.isEmpty {
        replaceCachedTriples(in: &state.snapshot.store.triples, with: removedEntityTriples, scope: InstantFactScope())
      }
      state.storeRevision = application.storeRevision
      state.queryResultRevision = application.queryResultRevision
      adoptCachedState(state)
      return
    }
    cachedState = nil
    if var materializedStore = cachedMaterializedStore,
      materializedStore.storeRevision == revisions.store,
      materializedStore.attributeRevision == revisions.attribute
    {
      if !materializedStore.snapshot.triples.isEmpty, !removedEntityTriples.isEmpty {
        replaceCachedTriples(
          in: &materializedStore.snapshot.triples,
          with: removedEntityTriples,
          scope: InstantFactScope()
        )
      }
      materializedStore.storeRevision = application.storeRevision
      cachedMaterializedStore = materializedStore
    }
  }

  /// Keeps the newest result stored under `key`, a closed query's, for its next subscription (#1006).
  private func unloadLiveQueryResultWithoutTransaction(key: String) throws {
    // The stored row is the newest unless a JSON write waits (#566); copying it skips encoding the result again.
    if liveQueryResultJSON.deferred[key] == nil {
      try execute(
        """
        INSERT OR REPLACE INTO instant_unloaded_live_query_results (query_key, triple_count, updated_at_ms, json)
        SELECT query_key, triple_count, updated_at_ms, json FROM instant_live_query_results WHERE query_key = ?
        """,
        [.text(key)]
      )
      if sqlite3_changes(connection.raw) == 1 { return }
    }
    guard let result = try liveQueryResultWithoutTransaction(key: key) else { return }
    try execute(
      """
      INSERT OR REPLACE INTO instant_unloaded_live_query_results (query_key, triple_count, updated_at_ms, json)
      VALUES (?, ?, ?, ?)
      """,
      [
        .text(result.key),
        .int(Int64(result.triples.count)),
        .int(result.updatedAt.milliseconds),
        .text(try encode(result)),
      ]
    )
  }

  /// Collects unloaded results by the pruning policy, oldest first, as upstream's `PersistedObject` GC collects
  /// unloaded keys (#1006): past the age limit, then while the stored results, loaded and unloaded, exceed the entry or
  /// triple limit. `loadedRows` are the stored results that stay; the policy never collects them here.
  private func collectUnloadedLiveQueryResultsWithoutTransaction(
    policy: InstantLiveQueryResultPruningPolicy,
    now: InstantTimestamp,
    loadedRows: [LiveQueryResultStorageRow]
  ) throws {
    if let maxAgeMilliseconds = policy.maxAgeMilliseconds {
      try execute(
        "DELETE FROM instant_unloaded_live_query_results WHERE updated_at_ms < ?",
        [.int(now.milliseconds - Swift.max(0, maxAgeMilliseconds))]
      )
    }
    guard policy.maxEntries != nil || policy.maxTripleCount != nil else { return }
    var unloaded: [(queryKey: String, tripleCount: Int)] = []
    do {
      var statement: OpaquePointer?
      try prepare(
        """
        SELECT query_key, triple_count FROM instant_unloaded_live_query_results
        ORDER BY updated_at_ms, query_key
        """,
        statement: &statement
      )
      defer { finishStatement(statement) }
      while true {
        let code = sqlite3_step(statement)
        if code == SQLITE_DONE { break }
        guard code == SQLITE_ROW, let queryKey = sqlite3_column_text(statement, 0) else {
          throw persistenceError(operation: "read unloaded live-query results", message: lastErrorMessage())
        }
        unloaded.append((String(cString: queryKey), Int(sqlite3_column_int64(statement, 1))))
      }
    }
    var entryCount = loadedRows.count + unloaded.count
    var tripleCount = loadedRows.reduce(0) { $0 + $1.tripleCount } + unloaded.reduce(0) { $0 + $1.tripleCount }
    var collected: [String] = []
    for row in unloaded {
      let overEntries = policy.maxEntries.map { entryCount > Swift.max(0, $0) } ?? false
      let overTriples = policy.maxTripleCount.map { tripleCount > Swift.max(0, $0) } ?? false
      guard overEntries || overTriples else { break }
      collected.append(row.queryKey)
      entryCount -= 1
      tripleCount -= row.tripleCount
    }
    try executeRepeated(
      "DELETE FROM instant_unloaded_live_query_results WHERE query_key = ?",
      bindings: collected.map { [.text($0)] }
    )
  }

  /// The unloaded result of `key`, if a prune unloaded it and nothing since saved or collected it (#1006). A reopened
  /// query reads it on the read connection before it takes the operation gate (#1131); this read, on the store's own
  /// connection, is for when that one cannot read.
  func unloadedLiveQueryResult(key: String) throws -> InstantUnloadedLiveQueryResultRead? {
    try readTransaction { try unloadedLiveQueryResultWithoutTransaction(key: key) }
  }

  private func unloadedLiveQueryResultWithoutTransaction(key: String) throws -> InstantUnloadedLiveQueryResultRead? {
    guard let identity = try unloadedLiveQueryResultRowIdentityWithoutTransaction(key: key) else { return nil }
    let results: [InstantPersistedLiveQueryResult] = try selectJSON(
      "SELECT json FROM instant_unloaded_live_query_results WHERE query_key = ? LIMIT 1",
      [.text(key)]
    )
    return results.first.map {
      InstantUnloadedLiveQueryResultRead(
        result: $0,
        rowTripleCount: identity.tripleCount,
        rowUpdatedAtMilliseconds: identity.updatedAtMilliseconds
      )
    }
  }

  /// What names `key`'s unloaded row: a prune writes the result's own fact count and update time with it, so a row
  /// unloaded again for a newer result differs in one of them (#1131).
  private func unloadedLiveQueryResultRowIdentityWithoutTransaction(
    key: String
  ) throws -> (tripleCount: Int, updatedAtMilliseconds: Int64)? {
    var statement: OpaquePointer?
    try prepare(
      "SELECT triple_count, updated_at_ms FROM instant_unloaded_live_query_results WHERE query_key = ? LIMIT 1",
      statement: &statement
    )
    defer { finishStatement(statement) }
    try bind([.text(key)], to: statement)
    let code = sqlite3_step(statement)
    if code == SQLITE_DONE { return nil }
    guard code == SQLITE_ROW else {
      throw persistenceError(operation: "read an unloaded live-query result", message: lastErrorMessage())
    }
    return (Int(sqlite3_column_int64(statement, 0)), sqlite3_column_int64(statement, 1))
  }

  /// Starts loading `read`'s result, an unloaded result whose query subscribes again, back among the stored results
  /// (#1006), in chunks (#1131): moves its row back, its JSON inside SQLite rather than encoded again, so it is a stored
  /// result again, and owns no fact yet. ``reloadUnloadedLiveQueryResultChunk(key:rowTripleCount:rowUpdatedAtMilliseconds:entityTriples:ownedFacts:residentEntityIDs:)``
  /// then gives it its facts and brings its entities back, a bounded chunk at a time, each in its own operation-gate
  /// hold; one hold for the `$files` list's 75,640 facts held the gate about 1.3 s on the Mac mini.
  ///
  /// `read` was read before the caller took the operation gate. When another row has replaced it since (its query
  /// reopened, was restated and closed, and a prune unloaded it again), the row stored now is read again here.
  ///
  /// Returns nil when the result is no longer unloaded.
  func beginUnloadedLiveQueryResultReload(
    _ read: InstantUnloadedLiveQueryResultRead
  ) throws -> InstantUnloadedLiveQueryResultReloadStart? {
    var expected: (store: Int64, attributes: Int64, outbox: Int64, queryResults: Int64) = (0, 0, 0, 0)
    let start: InstantUnloadedLiveQueryResultReloadStart? = try transaction {
      let key = read.result.key
      guard let identity = try unloadedLiveQueryResultRowIdentityWithoutTransaction(key: key) else { return nil }
      var result = read.result
      var row = identity
      let readAgain = identity.tripleCount != read.rowTripleCount
        || identity.updatedAtMilliseconds != read.rowUpdatedAtMilliseconds
      if readAgain {
        guard let current = try unloadedLiveQueryResultWithoutTransaction(key: key) else { return nil }
        result = current.result
        row = (current.rowTripleCount, current.rowUpdatedAtMilliseconds)
      }
      expected = (
        try loadMetadataRevisionWithoutTransaction(Self.storeRevisionKey),
        try loadMetadataRevisionWithoutTransaction(Self.attributeRevisionKey),
        try loadMetadataRevisionWithoutTransaction(Self.outboxRevisionKey),
        try loadMetadataRevisionWithoutTransaction(Self.queryResultRevisionKey)
      )
      // A save keeps ownership of only the facts the query's nested limits keep; the unloaded row was written from such
      // a save, so with the schema it was written under they keep every fact, and its JSON is this result's.
      let limited = InstantLiveQueryNestedLimit.limitedTriples(
        queryKey: key,
        triples: Array(result.triples),
        attributes: try attributesForLiveResultSaveWithoutTransaction()
      )
      var unownedFacts: Set<InstantLiveTripleIdentity> = []
      if limited.count != result.triples.count {
        unownedFacts = Set(result.triples.map(InstantLiveTripleIdentity.init))
          .subtracting(limited.map(InstantLiveTripleIdentity.init))
      }
      try invalidateDeclaredRelationStorageMarkerIfNeeded(forAttributeIDs: Set(result.triples.map(\.attributeID)))
      // A key lives in one of the two tables (#1006).
      try execute("DELETE FROM instant_live_query_results WHERE query_key = ?", [.text(key)])
      if unownedFacts.isEmpty {
        // The moved row keeps its count and time, so `row` names it.
        try execute(
          """
          INSERT INTO instant_live_query_results (query_key, triple_count, updated_at_ms, json)
          SELECT query_key, triple_count, updated_at_ms, json FROM instant_unloaded_live_query_results WHERE query_key = ?
          """,
          [.text(key)]
        )
      } else {
        var limitedResult = result
        limitedResult.triples = limited
        try execute(
          "INSERT INTO instant_live_query_results (query_key, triple_count, updated_at_ms, json) VALUES (?, ?, ?, ?)",
          [
            .text(key),
            .int(Int64(limited.count)),
            .int(result.updatedAt.milliseconds),
            .text(try encode(limitedResult)),
          ]
        )
        row = (limited.count, result.updatedAt.milliseconds)
      }
      try execute("DELETE FROM instant_unloaded_live_query_results WHERE query_key = ?", [.text(key)])
      liveQueryResultJSONWriteStats.saves += 1
      liveQueryResultJSON.deferred[key] = nil
      liveQueryResultJSON.writtenAt[key] = result.updatedAt.milliseconds
      liveQueryResultJSON.writtenPageInfo[key] = result.pageInfo
      try clearDeferredLiveQueryResultJSONMarkerWithoutTransaction(key)
      _ = try bumpMetadataRevisionWithoutTransaction(Self.queryResultRevisionKey)
      return InstantUnloadedLiveQueryResultReloadStart(
        result: result,
        rowTripleCount: row.tripleCount,
        rowUpdatedAtMilliseconds: row.updatedAtMilliseconds,
        unownedFacts: unownedFacts,
        readAgain: readAgain
      )
    }
    if start != nil {
      advanceCachedRevisionDomains(
        expectedStoreRevision: expected.store,
        expectedAttributeRevision: expected.attributes,
        expectedOutboxRevision: expected.outbox,
        expectedQueryResultRevision: expected.queryResults,
        changedEntityTriples: [:],
        changedFactScope: InstantFactScope(),
        mergingAttributes: [],
        storeChanged: false,
        attributesChanged: false,
        outboxChanged: false,
        queryResultsChanged: true
      )
    }
    return start
  }

  /// One chunk of a closed result's reload (#1131): the stored result under `key` owns `ownedFacts`, and the entities of
  /// `entityTriples` the store does not hold come back, from SQLite when it still holds them (facts this device wrote
  /// that no stored result owned load only when one does), else from the result. An entity the store still holds keeps
  /// what the store holds.
  ///
  /// Returns nil, writing nothing, when the stored row is no longer the one ``beginUnloadedLiveQueryResultReload(_:)``
  /// moved back: a server answer replaced it, and the server's facts stand.
  func reloadUnloadedLiveQueryResultChunk(
    key: String,
    rowTripleCount: Int,
    rowUpdatedAtMilliseconds: Int64,
    entityTriples: [String: [InstantTriple]],
    ownedFacts: [InstantTriple],
    residentEntityIDs: Set<String>
  ) throws -> InstantUnloadedLiveQueryResultChunkReload? {
    var expected: (store: Int64, attributes: Int64, outbox: Int64, queryResults: Int64) = (0, 0, 0, 0)
    var restoredEntityTriples: [String: [InstantTriple]] = [:]
    let reload: InstantUnloadedLiveQueryResultChunkReload? = try transaction {
      guard
        let row = try loadedLiveQueryResultRowIdentityWithoutTransaction(key: key),
        row.tripleCount == rowTripleCount,
        row.updatedAtMilliseconds == rowUpdatedAtMilliseconds
      else { return nil }
      expected = (
        try loadMetadataRevisionWithoutTransaction(Self.storeRevisionKey),
        try loadMetadataRevisionWithoutTransaction(Self.attributeRevisionKey),
        try loadMetadataRevisionWithoutTransaction(Self.outboxRevisionKey),
        try loadMetadataRevisionWithoutTransaction(Self.queryResultRevisionKey)
      )
      var ownership: Set<LiveQueryOwnershipIdentity> = []
      for triple in ownedFacts {
        ownership.insert(
          LiveQueryOwnershipIdentity(
            entityID: triple.entityID,
            attributeID: triple.attributeID,
            valueJSON: try encode(triple.value)
          )
        )
      }
      liveQueryResultValueEncodeCount += ownedFacts.count
      let queryID = try liveQueryResultIDWithoutTransaction(key: key)
      try executeRepeated(
        """
        INSERT OR IGNORE INTO instant_live_query_triples
          (query_id, entity_id, attribute_id, value_json)
        VALUES (?, ?, ?, ?)
        """,
        bindings: ownership.sorted(by: LiveQueryOwnershipDiff.storeOrder).map { identity in
          [.int(queryID), .text(identity.entityID), .text(identity.attributeID), .text(identity.valueJSON)]
        }
      )
      var wroteTriples = false
      var restoredFromResultCount = 0
      var restoredFromSQLiteCount = 0
      for (entityID, triples) in entityTriples where !residentEntityIDs.contains(entityID) {
        let stored: [InstantTriple] = try selectJSON(
          "SELECT json FROM instant_triples WHERE entity_id = ?",
          [.text(entityID)]
        )
        let restored: [InstantTriple]
        if stored.isEmpty {
          for triple in triples {
            try insertTripleWithoutTransaction(triple)
          }
          wroteTriples = true
          restoredFromResultCount += 1
          restored = triples
        } else {
          restoredFromSQLiteCount += 1
          restored = stored
        }
        // Deferred payloads stay in SQLite; the store reads them when a query selects them.
        let resident = restored.filter { !deferredValueResidency.attributeIDs.contains($0.attributeID) }
        if !resident.isEmpty {
          restoredEntityTriples[entityID] = resident
        }
      }
      let storeRevision = wroteTriples
        ? try bumpMetadataRevisionWithoutTransaction(Self.storeRevisionKey) : expected.store
      _ = try bumpMetadataRevisionWithoutTransaction(Self.queryResultRevisionKey)
      return InstantUnloadedLiveQueryResultChunkReload(
        restoredTriples: restoredEntityTriples.values.flatMap { $0 },
        restoredFromResultEntityCount: restoredFromResultCount,
        restoredFromSQLiteEntityCount: restoredFromSQLiteCount,
        storeChanged: wroteTriples,
        storeRevision: storeRevision,
        attributeRevision: expected.attributes
      )
    }
    if let reload {
      advanceCachedRevisionDomains(
        expectedStoreRevision: expected.store,
        expectedAttributeRevision: expected.attributes,
        expectedOutboxRevision: expected.outbox,
        expectedQueryResultRevision: expected.queryResults,
        changedEntityTriples: restoredEntityTriples,
        changedFactScope: InstantFactScope(),
        mergingAttributes: [],
        storeChanged: reload.storeChanged,
        attributesChanged: false,
        outboxChanged: false,
        queryResultsChanged: true
      )
    }
    return reload
  }

  /// What names `key`'s stored row, as ``unloadedLiveQueryResultRowIdentityWithoutTransaction(key:)`` names its
  /// unloaded one.
  private func loadedLiveQueryResultRowIdentityWithoutTransaction(
    key: String
  ) throws -> (tripleCount: Int, updatedAtMilliseconds: Int64)? {
    var statement: OpaquePointer?
    try prepare(
      "SELECT triple_count, updated_at_ms FROM instant_live_query_results WHERE query_key = ? LIMIT 1",
      statement: &statement
    )
    defer { finishStatement(statement) }
    try bind([.text(key)], to: statement)
    let code = sqlite3_step(statement)
    if code == SQLITE_DONE { return nil }
    guard code == SQLITE_ROW else {
      throw persistenceError(operation: "read a stored live-query result", message: lastErrorMessage())
    }
    return (Int(sqlite3_column_int64(statement, 0)), sqlite3_column_int64(statement, 1))
  }

  /// Whether this app has any unrevoked share. Without one, shared-root authorization cannot
  /// refuse a write, so `transact` skips it and the full store snapshot it would build.
  public func hasActiveShares(appID: String) throws -> Bool {
    try readTransaction {
      try selectInt64(
        "SELECT EXISTS(SELECT 1 FROM instant_shares WHERE app_id = ? AND revoked_at_ms IS NULL)",
        [.text(appID)]
      ) != 0
    }
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
    changedFactScope: InstantFactScope = InstantFactScope(),
    outbox: [PendingMutation]? = nil,
    pendingMutation: PendingMutation,
    supersedingImmediateTail: PendingMutation? = nil,
    metadataEntries: [InstantPersistenceMetadataEntry] = [],
    deletingMetadataKeys: [String] = [],
    expectedStoreRevision: Int64,
    expectedAttributeRevision: Int64,
    expectedOutboxRevision: Int64
  ) throws -> Bool {
    let energy = InstantEnergyMeter.begin(.localSave); defer { energy.end() }
    // The fingerprint itself is computed once, where the receipt is stored (#1007).
    guard pendingMutation.hasOptimisticEffectReceiptFingerprint else {
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
        try saveChangedEntityFactsWithoutTransaction(
          entityID: entityID,
          scope: changedFactScope[entityID],
          triples: changedEntityTriples[entityID, default: []],
          cachedPreviousTriples: cachedChangedEntityTriples?[entityID]
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
          with: changedEntityTriples,
          scope: changedFactScope
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
    defer { finishStatement(statement) }

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

  /// One-time repair for stores that live-query pruning damaged before it collected whole
  /// entities (#259, #278).
  ///
  /// Pruning used to delete some of an entity's facts and keep the rest. One iPhone kept 1,067
  /// transcription segments with a few facts (usually `text` and `wordsJSON`) but without `id`,
  /// `recordingID`, or `segmentIndex`: no relationship or filter could reach them, and a query that
  /// met one failed to decode it. The
  /// Instant server sends an entity's `id` fact with every selection (`instaql.clj`
  /// `etype-attr-ids`: "Make sure we give them the id or else the client won't be able to find the
  /// entity"), and typed writes always write it, so facts without their entity's `id` fact are what
  /// that bug left. Removing them lets the server deliver those entities whole again. Entities a
  /// pending mutation touches are kept, and a store that has never synced is left alone.
  private func removeEntitiesMissingTheirIDFactWithoutTransaction() throws {
    let hasSynced = try selectInt64(
      """
      SELECT EXISTS (
        SELECT 1 FROM instant_sync_metadata
        WHERE instr(key, 'sync.processed_transaction_id:') = 1
      )
      """
    )
    guard hasSynced == 1 else { return }
    try execute("DROP TABLE IF EXISTS temp.instant_repair_entities")
    try execute(
      "CREATE TEMP TABLE instant_repair_entities (entity_id TEXT PRIMARY KEY NOT NULL) WITHOUT ROWID"
    )
    defer { try? execute("DROP TABLE IF EXISTS temp.instant_repair_entities") }
    try execute(
      """
      INSERT INTO temp.instant_repair_entities (entity_id)
      SELECT entity_id FROM instant_triples
      WHERE instr(attribute_id, '/') > 1
        AND entity_id NOT IN (SELECT entity_id FROM instant_outbox_effect_entities)
      GROUP BY entity_id
      HAVING max(substr(attribute_id, -3) = '/id') = 0
      """
    )
    let entityCount = try selectInt64("SELECT count(*) FROM temp.instant_repair_entities")
    guard entityCount > 0 else { return }
    let namespaceCounts = try selectStrings(
      """
      SELECT namespace || ':' || count(*) FROM (
        SELECT DISTINCT entity_id, substr(attribute_id, 1, instr(attribute_id, '/') - 1) AS namespace
        FROM instant_triples
        WHERE entity_id IN (SELECT entity_id FROM temp.instant_repair_entities)
          AND instr(attribute_id, '/') > 1
      )
      GROUP BY namespace
      ORDER BY count(*) DESC, namespace
      """
    )
    let sampleEntityIDs = try selectStrings(
      "SELECT entity_id FROM temp.instant_repair_entities ORDER BY entity_id LIMIT 5"
    )
    try execute(
      "DELETE FROM instant_triples WHERE entity_id IN (SELECT entity_id FROM temp.instant_repair_entities)"
    )
    let factCount = try selectInt64("SELECT changes()")
    try execute(
      """
      DELETE FROM instant_live_query_triples
      WHERE entity_id IN (SELECT entity_id FROM temp.instant_repair_entities)
      """
    )
    _ = try bumpMetadataRevisionWithoutTransaction(Self.storeRevisionKey)
    _ = try bumpMetadataRevisionWithoutTransaction(Self.queryResultRevisionKey)
    InstantDiagnostics.shared.record(
      .warning,
      subsystem: "instant-swift-data-core",
      category: "persistence",
      event: "sqlite.repair.entities-missing-id-removed",
      message: """
        Removed \(entityCount) local entities whose facts had lost their entity's id fact; the \
        server delivers them again when a query needs them.
        """,
      metadata: [
        "entityCount": String(entityCount),
        "factCount": String(factCount),
        "namespaces": namespaceCounts.joined(separator: ","),
        "sampleEntityIDs": sampleEntityIDs.joined(separator: ","),
      ]
    )
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
      defer { finishStatement(statement) }
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

      guard let fingerprint = try? optimisticEffectFingerprint(of: mutation),
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
        confirming_claimant_id TEXT,
        excludes_watermark_roots INTEGER NOT NULL DEFAULT 0
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
    // A reduced apply's receipt patches (#296), kept with the plan like its roots, so the commit's revalidation
    // plans the same rows.
    try execute(
      """
      CREATE TEMP TABLE IF NOT EXISTS instant_server_apply_receipt_patches (
        plan_id TEXT NOT NULL,
        mutation_id TEXT NOT NULL,
        PRIMARY KEY (plan_id, mutation_id)
      ) WITHOUT ROWID
      """
    )
    // #932: a row's bodies come last. SQLite stores a row's columns in order, and a body larger than a page spills
    // into overflow pages, so reading a column stored after it walks the body's overflow chain: every scan of a plan
    // (staged, staged_delete, closure_round) and each of the commit's per-row reads walked three bodies.
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
        closure_round INTEGER NOT NULL DEFAULT 0,
        staged_json TEXT,
        staged_lifecycle_json TEXT,
        PRIMARY KEY (plan_id, mutation_id)
      ) WITHOUT ROWID
      """
    )
    // The entities a plan's component closure has already expanded, with the round that found
    // them, so each entity is expanded once (#277).
    try execute(
      """
      CREATE TEMP TABLE IF NOT EXISTS instant_server_apply_closure_entities (
        plan_id TEXT NOT NULL,
        entity_id TEXT NOT NULL,
        round INTEGER NOT NULL,
        PRIMARY KEY (plan_id, entity_id)
      ) WITHOUT ROWID
      """
    )
    try execute(
      """
      CREATE INDEX IF NOT EXISTS instant_server_apply_closure_entities_round_idx
      ON instant_server_apply_closure_entities (plan_id, round, entity_id)
      """
    )
    try execute(
      """
      CREATE INDEX IF NOT EXISTS instant_server_apply_rows_closure_round_idx
      ON instant_server_apply_rows (plan_id, closure_round, mutation_id)
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
  /// - Parameter operation: The store call that runs the transaction, under which ``InstantStorageWriteMeter`` counts
  ///   the pages it writes (#1007).
  private func transaction<Value>(
    operation: StaticString = #function,
    _ body: () throws -> Value
  ) throws -> Value {
    precondition(
      activeOutboxQuarantineIssueBatch == nil,
      "SQLite persistence transactions must not be nested."
    )
    let pagesBefore = cacheWritePages()
    defer { recordStorageWrites(operation: operation, pages: cacheWritePages() - pagesBefore) }
    try execute("BEGIN IMMEDIATE TRANSACTION")
    activeOutboxQuarantineIssueBatch = InstantOutboxQuarantineIssueBatch()
    let liveQueryResultJSONBeforeTransaction = liveQueryResultJSON
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
      liveQueryResultJSON = liveQueryResultJSONBeforeTransaction
      // Marker helpers participate in the same transaction but live on the actor. A rollback must
      // discard their speculative cache so the next writer reloads the durable marker instead of
      // trusting state that SQLite did not commit.
      installedDeclaredRelationStorageMarker = nil
      installedDeclaredRelationStorageObsoleteAttributeIDs = []
      didLoadDeclaredRelationStorageMarker = false
      throw error
    }
  }

  /// The pages this connection has written to the write-ahead log and the temporary file since it opened (#1007).
  private func cacheWritePages() -> Int {
    var current: Int32 = 0
    var highwater: Int32 = 0
    sqlite3_db_status(connection.raw, SQLITE_DBSTATUS_CACHE_WRITE, &current, &highwater, 0)
    return Int(current)
  }

  /// Counts one write transaction's pages under its store call, and reports the last 30 s at info when that is due.
  private func recordStorageWrites(operation: StaticString, pages: Int) {
    guard let summary = InstantStorageWriteMeter.record(operation: operation, pages: pages),
      InstantDiagnostics.shared.isEnabled(at: .info)
    else { return }
    let ranked = summary.operations.sorted { $0.value.pagesWritten > $1.value.pagesWritten }
    InstantDiagnostics.shared.record(
      .info,
      subsystem: "instant-swift-data-core",
      category: "persistence",
      event: "persistence.write-summary",
      message: "The local store wrote \(summary.bytesWritten / 1_024) KB in \(ranked.reduce(0) { $0 + $1.value.transactions }) write transactions in the last 30 s or more.",
      metadata: [
        "bytesWritten": String(summary.bytesWritten),
        "transactions": String(ranked.reduce(0) { $0 + $1.value.transactions }),
        // The calls that wrote the most, as call=pages/transactions, largest first.
        "byCall": ranked.prefix(12).map { "\($0.key)=\($0.value.pagesWritten)/\($0.value.transactions)" }
          .joined(separator: ";"),
      ]
    )
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

  /// The automatic pump's next writes to deliver, oldest first: the ready rows that need delivery, and the legacy rows
  /// whose delivery metadata predates the current version.
  ///
  /// #1108 (2026-10-24): one branch each, each searched by its own index (`instant_outbox_delivery_idx` since #1115, then
  /// `instant_outbox_delivery_candidate_idx`, and `instant_outbox_delivery_metadata_idx`). As one filter, `claim state AND (delivery state OR legacy metadata)`, the
  /// `OR` left SQLite a search on the claim state alone and a sort: every ready row was visited, refused writes
  /// included, each through its body's overflow pages, after every write and acknowledgement; on one phone's store that
  /// was 663 refused writes, and the claim held the operation gate about 60% of every recording minute.
  private static let automaticDeliveryCandidatesSQL =
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
    WHERE \(SQLitePersistenceStore.readyForDeliveryCondition)
    UNION
    SELECT
      mutation_id,
      created_at_ms,
      delivery_metadata_version,
      transport_step_count,
      COALESCE(encoded_body_bytes, length(CAST(json AS BLOB))),
      status,
      delivery_started
    FROM instant_outbox
    WHERE delivery_claim_state = ? AND status IN (?, ?) AND delivery_metadata_version < ?
    ORDER BY created_at_ms, mutation_id
    LIMIT ?
    """

  private static func automaticDeliveryCandidateBindings(limit: Int) -> [SQLiteBinding] {
    [
      .text(InstantOutboxDeliveryClaimState.ready.rawValue),
      .text(InstantMutationStatus.pending.rawValue),
      .text(InstantMutationStatus.confirmed.rawValue),
      .int(Int64(InstantOutboxDeliveryMetadata.currentVersion)),
      .int(Int64(limit)),
    ]
  }

  /// Whether the automatic pump has another write to deliver: the continuation check of a claim pass, split into the
  /// candidate read's two branches for the same reason (#1108).
  private static let automaticDeliveryCandidateExistsSQL =
    """
    SELECT EXISTS(
      SELECT 1
      FROM instant_outbox
      WHERE \(SQLitePersistenceStore.readyForDeliveryCondition)
    ) OR EXISTS(
      SELECT 1
      FROM instant_outbox
      WHERE delivery_claim_state = ? AND status IN (?, ?) AND delivery_metadata_version < ?
    )
    """

  private static var automaticDeliveryCandidateExistsBindings: [SQLiteBinding] {
    [
      .text(InstantOutboxDeliveryClaimState.ready.rawValue),
      .text(InstantMutationStatus.pending.rawValue),
      .text(InstantMutationStatus.confirmed.rawValue),
      .int(Int64(InstantOutboxDeliveryMetadata.currentVersion)),
    ]
  }

  /// A row the pump may claim now: ready, in need of delivery, and so with no claim deadline (every statement that
  /// makes a row ready clears it; only a claimed row has one). The deadline's `IS NULL` is what lets
  /// ``deliveryIndexSQL`` hand these rows back in creation order, so the read stops at its limit (#1115). Written with
  /// literals, as #1108's partial index needed.
  private static let readyForDeliveryCondition =
    "delivery_claim_state = \(SQLitePersistenceStore.sqlLiteral(InstantOutboxDeliveryClaimState.ready.rawValue))"
      + " AND delivery_state = \(SQLitePersistenceStore.sqlLiteral(InstantOutboxDeliveryState.needsDelivery.rawValue))"
      + " AND delivery_claim_deadline_ms IS NULL"

  /// The index the candidate read's first branch searched from #1108 to #1115, as migration 0029 made it: only the rows
  /// the pump may claim now, in delivery order. Partial, so a refused write, a claimed one and an acknowledgement never
  /// touched it: #1007 dropped a full index on the claim and delivery states because every write of a row wrote a page
  /// of it, and the old filter's `OR` kept any statement from using it. It led with the two states, constant inside it,
  /// because SQLite without statistics prefers an index whose leading columns a filter's equalities match. Migration
  /// 0031 drops it for ``deliveryIndexSQL``, which leads the same way and serves the claims' deadlines too.
  static let deliveryCandidateIndexSQL =
    """
    CREATE INDEX IF NOT EXISTS instant_outbox_delivery_candidate_idx
    ON instant_outbox (delivery_claim_state, delivery_state, created_at_ms, mutation_id)
    WHERE delivery_claim_state = 'ready' AND delivery_state = 'needs_delivery'
    """

  /// The index the pump's candidate read and every claim statement search (#1115): rows by claim state, delivery state
  /// and claim deadline, in delivery order. The rows the pump may claim now are one stretch of it in creation order (a
  /// ready row has no deadline), and a claim statement seeks the claimed rows, at most a window's worth. Migration 0031
  /// put it in place of the deadline index and #1108's candidate partial index, which each moved a row on every claim.
  static let deliveryIndexSQL =
    """
    CREATE INDEX IF NOT EXISTS instant_outbox_delivery_idx
    ON instant_outbox
      (delivery_claim_state, delivery_state, delivery_claim_deadline_ms, created_at_ms, mutation_id)
    """

  /// The tables keyed by their whole row that migration 0030 rebuilds WITHOUT ROWID (#1115), each with its new
  /// definition, its columns and its lookup index.
  private static let outboxKeyTablesWithoutRowid: [(name: String, create: String, columns: String, lookupIndex: String)]
    = [
      (
        name: "instant_outbox_write_keys",
        create: """
          CREATE TABLE instant_outbox_write_keys_0030 (
            mutation_id TEXT NOT NULL,
            entity_id TEXT NOT NULL,
            attribute_id TEXT NOT NULL,
            PRIMARY KEY (mutation_id, entity_id, attribute_id),
            FOREIGN KEY (mutation_id) REFERENCES instant_outbox (mutation_id)
              ON DELETE CASCADE
          ) WITHOUT ROWID
          """,
        columns: "mutation_id, entity_id, attribute_id",
        lookupIndex: """
          CREATE INDEX instant_outbox_write_keys_lookup_idx
          ON instant_outbox_write_keys (entity_id, attribute_id, mutation_id)
          """
      ),
      (
        name: "instant_outbox_effect_entities",
        create: """
          CREATE TABLE instant_outbox_effect_entities_0030 (
            mutation_id TEXT NOT NULL,
            entity_id TEXT NOT NULL,
            created_at_ms INTEGER NOT NULL DEFAULT 0,
            PRIMARY KEY (mutation_id, entity_id),
            FOREIGN KEY (mutation_id) REFERENCES instant_outbox (mutation_id)
              ON DELETE CASCADE
          ) WITHOUT ROWID
          """,
        columns: "mutation_id, entity_id, created_at_ms",
        lookupIndex: """
          CREATE INDEX instant_outbox_effect_entities_lookup_idx
          ON instant_outbox_effect_entities (entity_id, created_at_ms, mutation_id)
          """
      ),
    ]

  private func loadAutomaticDeliveryCandidateRowsWithoutTransaction(
    limit: Int
  ) throws -> [InstantOutboxDeliveryCandidateRow] {
    try loadOutboxDeliveryCandidateRowsWithoutTransaction(
      Self.automaticDeliveryCandidatesSQL,
      Self.automaticDeliveryCandidateBindings(limit: limit)
    )
  }

  /// The SQLite virtual-machine steps the automatic pump's candidate read and continuation check take on this store,
  /// for tests (#1108): a read that visits every outbox row takes steps in proportion to them.
  package func automaticDeliveryCandidateReadStepsForTesting(limit: Int = 50) throws -> (candidates: Int, check: Int) {
    func steps(_ sql: String, _ bindings: [SQLiteBinding]) throws -> Int {
      var statement: OpaquePointer?
      try prepare(sql, statement: &statement)
      defer { finishStatement(statement) }
      try bind(bindings, to: statement)
      _ = sqlite3_stmt_status(statement, SQLITE_STMTSTATUS_VM_STEP, 1)
      while sqlite3_step(statement) == SQLITE_ROW {}
      return Int(sqlite3_stmt_status(statement, SQLITE_STMTSTATUS_VM_STEP, 0))
    }
    return (
      candidates: try steps(Self.automaticDeliveryCandidatesSQL, Self.automaticDeliveryCandidateBindings(limit: limit)),
      check: try steps(Self.automaticDeliveryCandidateExistsSQL, Self.automaticDeliveryCandidateExistsBindings)
    )
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
    defer { finishStatement(statement) }
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
    defer { finishStatement(statement) }
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
    guard let receiptFingerprint = try optimisticEffectFingerprint(of: mutation) else {
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
    defer { finishStatement(statement) }
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
    defer { finishStatement(statement) }
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
    defer { finishStatement(statement) }
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
    defer { finishStatement(statement) }
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
    defer { finishStatement(statement) }
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
    defer { finishStatement(statement) }
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
    defer { finishStatement(statement) }
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

  /// Releases every claim whose claimant's process has ended, fenced by that exact claimant (#990).
  ///
  /// A released row keeps its offer bit (`delivery_started`), so the next claim still treats it as possibly applied.
  /// Claims without a claimant id keep their lease, as do claims whose claimant `hasEnded` does not end.
  private func releaseClaimsOfEndedClaimantsWithoutTransaction(
    excludingClaimantID claimantID: String,
    now: InstantTimestamp,
    hasEnded: (String) -> Bool
  ) throws {
    let claimed = InstantOutboxDeliveryClaimState.claimed.rawValue
    let endedClaimantIDs = try selectStrings(
      """
      SELECT DISTINCT delivery_claimant_id FROM instant_outbox
      WHERE delivery_claim_state = ? AND delivery_claimant_id IS NOT NULL
        AND delivery_claimant_id != ?
      """,
      [.text(claimed), .text(claimantID)]
    ).filter(hasEnded).sorted()
    guard !endedClaimantIDs.isEmpty else { return }
    var releasedMutationIDs: [String] = []
    var latestDeadlineMilliseconds: Int64?
    for endedClaimantID in endedClaimantIDs {
      releasedMutationIDs += try selectStrings(
        """
        SELECT mutation_id FROM instant_outbox
        WHERE delivery_claim_state = ? AND delivery_claimant_id = ?
        ORDER BY created_at_ms, mutation_id
        """,
        [.text(claimed), .text(endedClaimantID)]
      )
      if let deadline = try selectScalar(
        """
        SELECT CAST(MAX(delivery_claim_deadline_ms) AS TEXT) FROM instant_outbox
        WHERE delivery_claim_state = ? AND delivery_claimant_id = ?
        """,
        [.text(claimed), .text(endedClaimantID)]
      ).flatMap(Int64.init) {
        latestDeadlineMilliseconds = max(latestDeadlineMilliseconds ?? deadline, deadline)
      }
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
          .text(claimed),
          .text(endedClaimantID),
        ]
      )
    }
    InstantDiagnostics.shared.record(
      .notice,
      subsystem: "instant-swift-data-core",
      category: "outbox",
      event: "outbox.claims.ended-claimant-released",
      message:
        "Released the delivery claims of a process that has ended; they go out again now, in order, instead of after their acknowledgement deadlines.",
      metadata: [
        "releasedMutationCount": String(releasedMutationIDs.count),
        "claimantCount": String(endedClaimantIDs.count),
        "claimantIDs": endedClaimantIDs.prefix(3).joined(separator: ","),
        "waitAvoidedMilliseconds": latestDeadlineMilliseconds
          .map { String(max(0, $0 - now.milliseconds)) } ?? "",
        "mutationIDs": releasedMutationIDs.prefix(12).joined(separator: ","),
      ]
    )
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
    guard let candidate = try optimisticEffectFingerprint(of: mutation) else {
      return false
    }
    return try storedOptimisticEffectReceiptFingerprintWithoutTransaction(id: mutation.id)
      == candidate
  }

  private func hasStoredPreparedOptimisticEffectReceipt(
    _ mutation: PendingMutation,
    in row: InstantOutboxBodyRow
  ) throws -> Bool {
    guard row.mutationID == mutation.id else { return false }
    return hasStoredPreparedOptimisticEffectReceipt(
      mutation,
      in: row,
      fingerprint: try optimisticEffectFingerprint(of: mutation)
    )
  }

  /// ``hasStoredPreparedOptimisticEffectReceipt(_:in:)`` with the mutation's fingerprint already computed (#1007).
  private func hasStoredPreparedOptimisticEffectReceipt(
    _ mutation: PendingMutation,
    in row: InstantOutboxBodyRow,
    fingerprint: String?
  ) -> Bool {
    guard row.mutationID == mutation.id, let fingerprint else { return false }
    return row.optimisticEffectReceiptFingerprint == fingerprint
  }

  private func hasStoredServerAcceptance(
    _ mutation: PendingMutation,
    in row: InstantOutboxBodyRow
  ) throws -> Bool {
    guard row.serverAcceptancePayloadFingerprint != nil else { return false }
    return try hasStoredPreparedOptimisticEffectReceipt(mutation, in: row)
  }

  /// ``hasStoredServerAcceptance(_:in:)`` once the receipt check has run for the same mutation and row (#1007): an
  /// acceptance counts only over a prepared receipt, and the receipt check is the part that fingerprints.
  private func hasStoredServerAcceptance(in row: InstantOutboxBodyRow, hasPreparedReceipt: Bool) -> Bool {
    row.serverAcceptancePayloadFingerprint != nil && hasPreparedReceipt
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
      hasStoredServerAcceptance(in: row, hasPreparedReceipt: hasPreparedReceipt)
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
    let writeKeys = InstantOutboxDeliveryMetadata.writeKeys(in: mutation)
    // An acknowledgement saves the write again with the same keys: deleting and inserting the same rows moved them to
    // new pages of three b-trees for every write (#1007). The rows are the keys, so an equal set means equal rows.
    if try storedOutboxWriteKeysWithoutTransaction(mutationID: mutation.id) == writeKeys { return }
    try execute(
      "DELETE FROM instant_outbox_write_keys WHERE mutation_id = ?",
      [.text(mutation.id)]
    )
    let keys = writeKeys
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

  private func storedOutboxWriteKeysWithoutTransaction(
    mutationID: String
  ) throws -> Set<InstantVisibleWriteKey> {
    var statement: OpaquePointer?
    try prepare(
      "SELECT entity_id, attribute_id FROM instant_outbox_write_keys WHERE mutation_id = ?",
      statement: &statement
    )
    defer { finishStatement(statement) }
    try bind([.text(mutationID)], to: statement)
    var keys: Set<InstantVisibleWriteKey> = []
    while sqlite3_step(statement) == SQLITE_ROW {
      guard
        let entityID = sqlite3_column_text(statement, 0),
        let attributeID = sqlite3_column_text(statement, 1)
      else { continue }
      keys.insert(
        InstantVisibleWriteKey(entityID: String(cString: entityID), attributeID: String(cString: attributeID))
      )
    }
    return keys
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
      Self.unknownActiveOverlayAfterSQL,
      Self.unknownActiveOverlayAfterBindings(position, excludingClaimToken: claimToken)
    ) != 0
  }

  /// Whether a later write's locally visible overlay has no trustworthy normalized write-key proof.
  ///
  /// #1108, #1114 (2026-10-24): the overlay flag is tested `= 1` (it holds only 0 and 1), which an index on it can seek,
  /// so the check visits active overlays alone. Tested `!= 0`, it scanned the table in every claim pass: each refused
  /// write's late columns read through its body, 5,709 SQLite steps beside 400 of them against 58 beside 7.
  private static let unknownActiveOverlayAfterSQL =
    """
    SELECT EXISTS(
      SELECT 1
      FROM instant_outbox AS outbox
      WHERE (
        outbox.created_at_ms > ?
        OR (outbox.created_at_ms = ? AND outbox.mutation_id > ?)
      )
      AND outbox.optimistic_overlay_active = 1
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
    """

  private static func unknownActiveOverlayAfterBindings(
    _ position: InstantOutboxDeliveryPosition,
    excludingClaimToken claimToken: String
  ) -> [SQLiteBinding] {
    [
      .int(position.createdAtMilliseconds),
      .int(position.createdAtMilliseconds),
      .text(position.mutationID),
      .text(InstantOutboxDeliveryClaimState.claimed.rawValue),
      .text(claimToken),
      .int(Int64(InstantOutboxDeliveryMetadata.currentVersion)),
    ]
  }

  /// The SQLite steps of the delivery's unknown-overlay check over every row after the start, for tests (#1108).
  package func unknownActiveOverlayCheckStepsForTesting() throws -> Int {
    var statement: OpaquePointer?
    try prepare(Self.unknownActiveOverlayAfterSQL, statement: &statement)
    defer { finishStatement(statement) }
    try bind(
      Self.unknownActiveOverlayAfterBindings(
        InstantOutboxDeliveryPosition(createdAtMilliseconds: 0, mutationID: ""),
        excludingClaimToken: "no-claim"
      ),
      to: statement
    )
    _ = sqlite3_stmt_status(statement, SQLITE_STMTSTATUS_VM_STEP, 1)
    while sqlite3_step(statement) == SQLITE_ROW {}
    return Int(sqlite3_stmt_status(statement, SQLITE_STMTSTATUS_VM_STEP, 0))
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
    try selectInt64(Self.automaticDeliveryCandidateExistsSQL, Self.automaticDeliveryCandidateExistsBindings) != 0
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
        defer { finishStatement(statement) }
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
    defer { finishStatement(statement) }
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
    defer { finishStatement(statement) }
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
    defer { finishStatement(statement) }
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
    defer { finishStatement(statement) }
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
    defer { finishStatement(statement) }
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
    defer { finishStatement(statement) }
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
    defer { finishStatement(statement) }
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
    defer { finishStatement(statement) }

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
    defer { finishStatement(statement) }

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
    // A result whose JSON write waits is newer than its stored JSON (#566).
    if let deferred = liveQueryResultJSON.deferred[key] {
      return deferred
    }
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
      SELECT 1
      FROM instant_live_query_triples
      WHERE entity_id = ? AND attribute_id = ? AND value_json = ?
      """
    var bindings: [SQLiteBinding] = [
      .text(identity.entityID),
      .text(identity.attributeID),
      .text(try encode(identity.value)),
    ]
    if !excludingQueryKeys.isEmpty {
      // A key with no stored result owns no rows, so excluding the stored ones' ids excludes the same rows (#704).
      sql += " AND query_id NOT IN (SELECT query_id FROM instant_live_query_results WHERE query_key IN ("
        + Array(repeating: "?", count: excludingQueryKeys.count).joined(separator: ", ")
        + "))"
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
    try executeAttributeWrite("DELETE FROM instant_attributes")
    try execute("DELETE FROM instant_triples")

    for attribute in snapshot.attributes {
      try executeAttributeWrite(
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
    // The value's text, written once (#1007); the fact's own JSON is computed when it is read (#1121).
    let value = try InstantStoredJSON.stored(triple.value, using: encoder)
    if deferredValueResidency.attributeIDs.contains(triple.attributeID) {
      // A deferred value is not in memory, so the diff cannot name the value this one replaces: every other value of
      // the slot goes. The same value stays in its row (#1120).
      try execute(
        "DELETE FROM instant_triples WHERE entity_id = ? AND attribute_id = ? AND value_json != ?",
        [.text(triple.entityID), .text(triple.attributeID), .text(value)]
      )
    }
    // #1120: the fact is updated where it is. INSERT OR REPLACE deleted the row and inserted it again, which on the old
    // rowid table moved it to the table's end and its key's index entry with it: one re-saved transcript line (16
    // facts, each re-stamped by its new write) dirtied 9-15 pages on a copy of the phone's store, in place 3. Keyed by
    // the fact since #1121, an entity's facts share their leaf. The key is the only unique constraint, so this conflicts
    // where REPLACE did, and a local or server write overwrites the stamp as before (the canonical relation upsert
    // keeps the newer stamp instead).
    try execute(
      """
      INSERT INTO instant_triples (entity_id, attribute_id, value_json, tx_id, tx_time_ms)
      VALUES (?, ?, ?, ?, ?)
      ON CONFLICT(entity_id, attribute_id, value_json) DO UPDATE SET
        tx_id = excluded.tx_id,
        tx_time_ms = excluded.tx_time_ms
      """,
      [
        .text(triple.entityID),
        .text(triple.attributeID),
        .text(value),
        .text(triple.txID),
        .int(triple.txTime.milliseconds),
      ]
    )
  }

  /// Rewrites only the facts of `entityID` inside `scope`.
  ///
  /// `triples` is already limited to that scope (`PreparedStoreMutation.changedEntityTriples`),
  /// so the previous rows must be too; otherwise every row outside the scope would look deleted.
  /// A whole-entity scope reads the entity's rows as before.
  private func saveChangedEntityFactsWithoutTransaction(
    entityID: String,
    scope: InstantEntityFactScope,
    triples: [InstantTriple],
    cachedPreviousTriples: [InstantTriple]? = nil
  ) throws {
    let previousTriples: [InstantTriple]
    if let cachedPreviousTriples {
      previousTriples = cachedPreviousTriples.filter(scope.contains)
    } else {
      switch scope {
      case .wholeEntity:
        previousTriples = try selectJSON(
          "SELECT json FROM instant_triples WHERE entity_id = ? ORDER BY attribute_id, value_json",
          [.text(entityID)]
        )
      case let .facts(attributeIDs, values):
        var scoped: [InstantTriple] = []
        for attributeID in attributeIDs.sorted() {
          scoped += try selectJSON(
            "SELECT json FROM instant_triples WHERE entity_id = ? AND attribute_id = ?",
            [.text(entityID), .text(attributeID)]
          ) as [InstantTriple]
        }
        for attributeID in values.keys.sorted() where !attributeIDs.contains(attributeID) {
          for value in values[attributeID] ?? [] {
            scoped += try selectJSON(
              """
              SELECT json FROM instant_triples
              WHERE entity_id = ? AND attribute_id = ? AND value_json = ?
              """,
              [.text(entityID), .text(attributeID), .text(try encode(value))]
            ) as [InstantTriple]
          }
        }
        previousTriples = scoped
      }
    }
    try saveTripleDiffWithoutTransaction(from: previousTriples, to: triples)
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
    with changedEntityTriples: [String: [InstantTriple]],
    scope: InstantFactScope
  ) {
    for entityID in changedEntityTriples.keys.sorted() {
      let lowerBound = tripleIndex(in: triples, entityID: entityID, includingEqual: true)
      let upperBound = tripleIndex(in: triples, entityID: entityID, includingEqual: false)
      let entityScope = scope[entityID]
      var changed = changedEntityTriples[entityID, default: []]
      if entityScope != .wholeEntity {
        // Scoped changes replace only their own facts; the entity's other facts stay.
        changed += triples[lowerBound..<upperBound].filter { !entityScope.contains($0) }
      }
      let replacement = changed.sorted {
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
      try executeAttributeWrite("DELETE FROM instant_attributes WHERE id = ?", [.text(id)])
    }
    for attribute in snapshot.attributes where previousAttributes[attribute.id] != attribute {
      try executeAttributeWrite(
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
    let candidateFingerprint = try optimisticEffectFingerprint(of: mutation)
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
    finishStatement(statement)
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
    let hasServerAcceptance = hasStoredServerAcceptance(in: row, hasPreparedReceipt: hasPreparedReceipt)
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

  /// Runs one statement that writes `instant_attributes`, and forgets the attributes live-result saves reuse.
  private func executeAttributeWrite(_ sql: String, _ bindings: [SQLiteBinding] = []) throws {
    attributeWriteGeneration &+= 1
    try execute(sql, bindings)
  }

  /// The stored attributes, reused while this connection has not written them and the attribute revision another
  /// process would bump is unchanged.
  private func attributesForLiveResultSaveWithoutTransaction() throws -> [InstantAttribute] {
    let revision = try loadMetadataRevisionWithoutTransaction(Self.attributeRevisionKey)
    if let cached = liveResultAttributes,
      cached.revision == revision,
      cached.generation == attributeWriteGeneration
    {
      return cached.attributes
    }
    let attributes = try loadAttributesWithoutTransaction(tracesStartupCollection: false)
    liveResultAttributeLoads += 1
    liveResultAttributes = (revision, attributeWriteGeneration, attributes)
    return attributes
  }

  private func saveLiveQueryResultWithoutTransaction(
    _ result: InstantPersistedLiveQueryResult,
    deferringJSON: Bool = false
  ) throws {
    let prepared = try preparedLiveQueryResultSaveWithoutTransaction(
      result,
      previousFacts: nil,
      encodingJSONIfWritten: nil
    )
    try applyLiveQueryResultSaveWithoutTransaction(prepared.save, deferringJSON: deferringJSON)
  }

  /// Works out the saves of a server apply's restated results before the apply takes the operation gate (#932); nil
  /// when the query-result revision moved since `expectedQueryResultRevision`. The commit checks the same revision, and
  /// every writer of a result's ownership rows bumps it in the same transaction, so the rows read here are the rows
  /// the commit replaces. Each save's JSON is encoded here too when, as things stand, the commit would write it.
  func prepareLiveQueryResultSaves(
    _ results: [InstantPersistedLiveQueryResult],
    expectedQueryResultRevision: Int64
  ) throws -> [InstantPreparedLiveQueryResultSave]? {
    guard !results.isEmpty else { return [] }
    let energy = InstantEnergyMeter.begin(.serverApplyPlan); defer { energy.end() }
    return try readTransaction {
      guard try loadMetadataRevisionWithoutTransaction(Self.queryResultRevisionKey) == expectedQueryResultRevision
      else { return nil }
      // A key restated twice in one frame is saved twice in order: the second save replaces the first's rows.
      var storedFactsByKey: [String: [InstantTriple]] = [:]
      var saves: [InstantPreparedLiveQueryResultSave] = []
      for result in results {
        let prepared = try preparedLiveQueryResultSaveWithoutTransaction(
          result,
          previousFacts: storedFactsByKey[result.key],
          encodingJSONIfWritten: storedFactsByKey[result.key] == nil ? true : nil
        )
        storedFactsByKey[result.key] = prepared.storedFacts
        saves.append(prepared.save)
      }
      return saves
    }
  }

  /// One result's save against the rows `previousFacts` own (an earlier save of the same key in this frame), or the
  /// stored rows when nil, and the facts it stores. With `encodingJSONIfWritten`, the JSON too when a deferring save
  /// would write it now.
  private func preparedLiveQueryResultSaveWithoutTransaction(
    _ result: InstantPersistedLiveQueryResult,
    previousFacts knownPreviousFacts: [InstantTriple]?,
    encodingJSONIfWritten: Bool?
  ) throws -> (save: InstantPreparedLiveQueryResultSave, storedFacts: [InstantTriple]) {
    let attributeIDs = Set(result.triples.map(\.attributeID))
    let attributes = try attributesForLiveResultSaveWithoutTransaction()
    var result = result
    result.triples = InstantLiveQueryNestedLimit.limitedTriples(
      queryKey: result.key,
      triples: Array(result.triples),
      attributes: attributes
    )
    liveQueryResultValueEncodeCount += result.triples.count
    var ownership = try LiveQueryOwnershipDiff(next: Array(result.triples), encoder: encoder)
    if let knownPreviousFacts {
      try ownership.previousFacts(knownPreviousFacts)
    } else {
      try liveQueryOwnershipRowsWithoutTransaction(queryKey: result.key, into: &ownership)
    }
    try ownership.finish()
    var json: String?
    if encodingJSONIfWritten == true,
      try liveQueryResultJSONWriteWithoutTransaction(
        result,
        ownershipUnchanged: ownership.isUnchanged,
        deferringJSON: true
      ).writesJSON
    {
      json = try encode(result)
    }
    return (
      InstantPreparedLiveQueryResultSave(
        result: result,
        attributeIDs: attributeIDs,
        removedOwnership: ownership.removed,
        insertedOwnership: ownership.inserted,
        json: json
      ),
      Array(result.triples)
    )
  }

  /// Whether saving `result` writes its JSON now (#566), with what the decision read.
  private func liveQueryResultJSONWriteWithoutTransaction(
    _ result: InstantPersistedLiveQueryResult,
    ownershipUnchanged: Bool,
    deferringJSON: Bool
  ) throws -> (writesJSON: Bool, storedJSONIsCurrent: Bool) {
    let key = result.key
    let rowExists = try selectScalar(
      "SELECT 1 FROM instant_live_query_results WHERE query_key = ? LIMIT 1",
      [.text(key)]
    ) != nil
    // The stored JSON already holds this result: the same facts and page info, and no newer result waits (#566).
    let storedJSONIsCurrent = rowExists
      && liveQueryResultJSON.deferred[key] == nil
      && ownershipUnchanged
      && liveQueryResultJSON.writtenPageInfo[key].map { $0 == result.pageInfo } == true
    let writeIsDue = liveQueryResultJSON.writtenAt[key].map {
      result.updatedAt.milliseconds - $0 >= liveQueryResultJSONWriteIntervalMilliseconds
    } ?? true
    return (!(rowExists && (storedJSONIsCurrent || (deferringJSON && !writeIsDue))), storedJSONIsCurrent)
  }

  private func applyLiveQueryResultSaveWithoutTransaction(
    _ save: InstantPreparedLiveQueryResultSave,
    deferringJSON: Bool
  ) throws {
    let result = save.result
    try invalidateDeclaredRelationStorageMarkerIfNeeded(forAttributeIDs: save.attributeIDs)
    // A saved result supersedes the copy a prune unloaded (#1006): a key lives in one of the two tables.
    try execute("DELETE FROM instant_unloaded_live_query_results WHERE query_key = ?", [.text(result.key)])
    liveQueryResultJSONWriteStats.saves += 1
    let key = result.key
    let removedOwnership = save.removedOwnership
    let insertedOwnership = save.insertedOwnership
    let decision = try liveQueryResultJSONWriteWithoutTransaction(
      result,
      ownershipUnchanged: removedOwnership.isEmpty && insertedOwnership.isEmpty,
      deferringJSON: deferringJSON
    )
    let storedJSONIsCurrent = decision.storedJSONIsCurrent
    if !decision.writesJSON {
      // The row's count and time stay exact: #441's refusal resolution reads when the server last showed a fact.
      try execute(
        "UPDATE instant_live_query_results SET triple_count = ?, updated_at_ms = ? WHERE query_key = ?",
        [.int(Int64(result.triples.count)), .int(result.updatedAt.milliseconds), .text(key)]
      )
      if !storedJSONIsCurrent {
        liveQueryResultJSON.deferred[key] = result
        try markDeferredLiveQueryResultJSONWithoutTransaction(key, at: result.updatedAt.milliseconds)
      }
    } else {
      let json = try save.json ?? encode(result)
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
          .text(key),
          .int(Int64(result.triples.count)),
          .int(result.updatedAt.milliseconds),
          .text(json),
        ]
      )
      liveQueryResultJSONWriteStats.writes += 1
      liveQueryResultJSONWriteStats.bytes += json.utf8.count
      liveQueryResultJSON.deferred[key] = nil
      liveQueryResultJSON.writtenAt[key] = result.updatedAt.milliseconds
      liveQueryResultJSON.writtenPageInfo[key] = result.pageInfo
      try clearDeferredLiveQueryResultJSONMarkerWithoutTransaction(key)
    }
    try applyLiveQueryOwnershipChangesWithoutTransaction(
      key: key,
      removed: removedOwnership,
      inserted: insertedOwnership
    )
  }

  /// Writes a stored result's ownership rows that leave and join; the result's row must be written already.
  private func applyLiveQueryOwnershipChangesWithoutTransaction(
    key: String,
    removed removedOwnership: [LiveQueryOwnershipIdentity],
    inserted insertedOwnership: [LiveQueryOwnershipIdentity]
  ) throws {
    guard !removedOwnership.isEmpty || !insertedOwnership.isEmpty else { return }
    // The row was written above; its id names it in every ownership row (#704).
    let queryID = try liveQueryResultIDWithoutTransaction(key: key)
    try executeRepeated(
      """
      DELETE FROM instant_live_query_triples
      WHERE query_id = ?
        AND entity_id = ?
        AND attribute_id = ?
        AND value_json = ?
      """,
      bindings: removedOwnership.map { identity in
        [
          .int(queryID),
          .text(identity.entityID),
          .text(identity.attributeID),
          .text(identity.valueJSON),
        ]
      }
    )
    try executeRepeated(
      """
      INSERT INTO instant_live_query_triples
        (query_id, entity_id, attribute_id, value_json)
      VALUES (?, ?, ?, ?)
      """,
      bindings: insertedOwnership.map { identity in
        [
          .int(queryID),
          .text(identity.entityID),
          .text(identity.attributeID),
          .text(identity.valueJSON),
        ]
      }
    )
  }

  /// Hands each ownership row of the stored result `queryKey` to `diff`, as its columns' bytes (#1147).
  private func liveQueryOwnershipRowsWithoutTransaction(
    queryKey: String,
    into diff: inout LiveQueryOwnershipDiff
  ) throws {
    var statement: OpaquePointer?
    try prepare(
      """
      SELECT entity_id, attribute_id, value_json
      FROM instant_live_query_triples
      WHERE query_id = (SELECT query_id FROM instant_live_query_results WHERE query_key = ?)
      """,
      statement: &statement
    )
    defer { finishStatement(statement) }
    try bind([.text(queryKey)], to: statement)
    func column(_ index: Int32) -> UnsafeBufferPointer<UInt8>? {
      guard let text = sqlite3_column_text(statement, index) else { return nil }
      return UnsafeBufferPointer(start: text, count: Int(sqlite3_column_bytes(statement, index)))
    }
    var rows = 0
    while true {
      let code = sqlite3_step(statement)
      if code == SQLITE_DONE {
        liveQueryOwnershipRowReadCount += rows
        return
      }
      guard code == SQLITE_ROW else {
        throw persistenceError(
          operation: "read live-query ownership",
          message: lastErrorMessage()
        )
      }
      guard let entityID = column(0), let attributeID = column(1), let valueJSON = column(2) else {
        throw persistenceError(
          operation: "read live-query ownership",
          message: "SQLite returned a NULL live-query ownership column."
        )
      }
      diff.previousRow(entityID: entityID, attributeID: attributeID, valueJSON: valueJSON)
      rows += 1
    }
  }

  private func liveQueryOwnershipWithoutTransaction(
    queryKey: String
  ) throws -> Set<LiveQueryOwnershipIdentity> {
    var statement: OpaquePointer?
    try prepare(
      """
      SELECT entity_id, attribute_id, value_json
      FROM instant_live_query_triples
      WHERE query_id = (SELECT query_id FROM instant_live_query_results WHERE query_key = ?)
      """,
      statement: &statement
    )
    defer { finishStatement(statement) }
    try bind([.text(queryKey)], to: statement)

    var ownership: Set<LiveQueryOwnershipIdentity> = []
    while true {
      let code = sqlite3_step(statement)
      if code == SQLITE_DONE {
        liveQueryOwnershipRowReadCount += ownership.count
        return ownership
      }
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

  // MARK: Live-query ownership reads, for tests (#704)
  //
  // Each answers through the private statement the runtime uses, so a test can compare what a store answers before and
  // after its ownership rows change layout.

  /// The ownership rows of the stored result for `queryKey` as `[entityID, attributeID, valueJSON]`, sorted.
  package func liveQueryOwnershipForTesting(queryKey: String) throws -> [[String]] {
    try readTransaction {
      try liveQueryOwnershipWithoutTransaction(queryKey: queryKey)
        .sorted(by: LiveQueryOwnershipDiff.storeOrder)
        .map { [$0.entityID, $0.attributeID, $0.valueJSON] }
    }
  }

  /// Whether a stored result whose key is not in `excludingQueryKeys` owns `triple`'s fact.
  package func liveQueryTripleHasOwnerForTesting(
    _ triple: InstantTriple,
    excludingQueryKeys: Set<String>
  ) throws -> Bool {
    try readTransaction {
      try liveQueryTripleHasOwnerWithoutTransaction(
        InstantLiveTripleIdentity(triple),
        excludingQueryKeys: excludingQueryKeys
      )
    }
  }

  /// #441's read: when the newest result stored at or after `milliseconds` that shows `triple` was stored.
  func newestServerResultShowingForTesting(
    _ triple: InstantTriple,
    attributes: AttributeStore,
    storedAtOrAfter milliseconds: Int64
  ) throws -> Int64? {
    try readTransaction {
      try newestServerResultShowingWithoutTransaction(triple, attributes: attributes, storedAtOrAfter: milliseconds)
    }
  }

  /// #445's read: the values the newest stored result that holds `triple`'s slot shows for it.
  package func newestServerValuesForTesting(of triple: InstantTriple) throws -> [InstantValue] {
    try readTransaction {
      try newestServerValuesWithoutTransaction(of: triple)
    }
  }

  /// The result keys an application migration of `affectedAttributeIDs` visits, in its order.
  package func applicationMigrationLiveQueryResultKeysForTesting(
    affectedAttributeIDs: Set<String>
  ) throws -> [String] {
    try readTransaction {
      var keys: [String] = []
      var cursor: String?
      while let row = try nextApplicationMigrationLiveQueryResultWithoutTransaction(
        after: cursor,
        affectedAttributeIDs: affectedAttributeIDs
      ) {
        switch row {
        case let .oversized(queryKey, _):
          keys.append(queryKey)
          cursor = queryKey
        case let .decoded(result):
          keys.append(result.key)
          cursor = result.key
        }
      }
      return keys
    }
  }


  /// Writes a metadata row in place (#1007). `INSERT OR REPLACE` deleted the row and inserted it again under a new rowid,
  /// so every revision bump rewrote the table's leaf and its key index, in every transaction.
  private static let upsertMetadataSQL = """
    INSERT INTO instant_sync_metadata (key, value, updated_at_ms)
    VALUES (?, ?, ?)
    ON CONFLICT(key) DO UPDATE SET value = excluded.value, updated_at_ms = excluded.updated_at_ms
    """

  private func saveMetadataValueWithoutTransaction(
    _ value: String,
    key: String,
    updatedAt: InstantTimestamp
  ) throws {
    try execute(
      Self.upsertMetadataSQL,
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
      Self.upsertMetadataSQL,
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

  /// Where a stream's content ends. Chunks are stored back to back (each append starts at the previous end), so the
  /// chunk with the greatest offset ends the stream; the index finds it without summing every chunk, which made each
  /// append cost the stream's length.
  private func streamContentSizeWithoutTransaction(appID: String, streamID: String) throws -> Int64
  {
    let value: String? = try selectScalar(
      """
      SELECT CAST(offset + byte_count AS TEXT)
      FROM instant_stream_content_chunks
      WHERE app_id = ? AND stream_id = ?
      ORDER BY offset DESC, byte_count DESC
      LIMIT 1
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
    streamContentReadMetrics.readCount += 1
    streamContentReadMetrics.decodedChunkCount += chunks.count
    streamContentReadMetrics.decodedByteCount += data.count
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
    defer { finishStatement(statement) }
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
    defer { finishStatement(statement) }

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

  /// Checks out a prepared statement for `sql` from the connection's cache, preparing it when the cache has none
  /// (#653). Every caller returns it with ``finishStatement(_:)``.
  private func prepare(_ sql: String, statement: inout OpaquePointer?) throws {
    try ensureOpenConnection()
    let checkedOut = connection.statements.checkOut(sql, on: connection.raw)
    guard checkedOut.resultCode == SQLITE_OK else {
      throw persistenceError(operation: "prepare SQL", message: lastErrorMessage())
    }
    statement = checkedOut.statement
  }

  /// Returns a statement from ``prepare(_:statement:)``: reset, its bindings cleared, and kept for the next use of the
  /// same SQL (#653).
  private func finishStatement(_ statement: OpaquePointer?) {
    connection.statements.checkIn(statement)
  }

  /// How many statements SQLite has prepared on this store's connections (#653).
  package func preparedStatementCountForTesting() -> Int {
    connection.statements.preparedCount
  }

  /// How many prepared statements wait for reuse, and the heap bytes SQLite holds for every statement of the
  /// connection (`SQLITE_DBSTATUS_STMT_USED`) (#653).
  package func statementCacheStatusForTesting() -> (idleCount: Int, statementBytes: Int) {
    var used: Int32 = 0
    var highwater: Int32 = 0
    if let raw = connection.raw {
      sqlite3_db_status(raw, SQLITE_DBSTATUS_STMT_USED, &used, &highwater, 0)
    }
    return (connection.statements.idleCount, Int(used))
  }

  private func ensureOpenConnection() throws {
    guard connection.raw == nil else { return }
    try reopenConnection()
  }

  private func reopenConnection() throws {
    connection.close()
    connection.raw = try Self.openRawConnection(fileURL: fileURL, vfs: connectionVFS)
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

  /// A value's stored text, as `JSONEncoder` writes it (#1007): see ``InstantStoredJSON``.
  private func encode(_ value: InstantValue) throws -> String {
    try InstantStoredJSON.stored(value, using: encoder)
  }

  /// A fact's stored text, as `JSONEncoder` writes it (#1007): see ``InstantStoredJSON``.
  private func encode(_ triple: InstantTriple) throws -> String {
    try InstantStoredJSON.stored(triple, using: encoder)
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

  /// Records how SQLite makes commits durable on this connection, once per open (#473, freeze-185 item 3).
  ///
  /// The freeze report asked for `PRAGMA synchronous = NORMAL` so a commit under the operation gate costs no fsync.
  /// Apple's SQLite already defaults a WAL connection to NORMAL: macOS 26.5's SQLite 3.51.0 and the iOS 27.0
  /// simulator's 3.54.0 are built with `SQLITE_DEFAULT_WAL_SYNCHRONOUS=1` (and `DEFAULT_CKPTFULLFSYNC`), so a commit
  /// appends to the WAL without an fsync and only a checkpoint syncs. This line shows what the device's SQLite does:
  /// since #1118 the checkpoint's cadence (4,000 frames), whether its syncs are `F_FULLFSYNC`, and the size the log is
  /// cut back to when it starts over.
  private func recordDurabilitySettings() {
    let synchronous = try? selectScalar("PRAGMA synchronous")
    let journalMode = try? selectScalar("PRAGMA journal_mode")
    let walAutocheckpoint = try? selectScalar("PRAGMA wal_autocheckpoint")
    let checkpointFullfsync = try? selectScalar("PRAGMA checkpoint_fullfsync")
    let journalSizeLimit = try? selectScalar("PRAGMA journal_size_limit")
    InstantDiagnostics.shared.record(
      .info,
      subsystem: "instant-swift-data-core",
      category: "persistence",
      event: "sqlite.durability",
      message: "SQLite commits with synchronous=\(synchronous ?? "unknown") in \(journalMode ?? "unknown") mode.",
      metadata: [
        "synchronous": synchronous ?? "",
        "journalMode": journalMode ?? "",
        "walAutocheckpoint": walAutocheckpoint ?? "",
        "checkpointFullfsync": checkpointFullfsync ?? "",
        "journalSizeLimit": journalSizeLimit ?? "",
        "sqliteVersion": String(cString: sqlite3_libversion()),
      ]
    )
  }

  /// `PRAGMA synchronous` on this connection: 0 off, 1 normal, 2 full, 3 extra.
  package func synchronousSettingForTesting() throws -> String? {
    try selectScalar("PRAGMA synchronous")
  }

  /// `PRAGMA wal_autocheckpoint` on the writer: a commit that leaves the log this many frames long or longer
  /// checkpoints it (#1118). The setting is the connection's own, so only the store can say what its writer uses.
  package func walAutocheckpointForTesting() throws -> Int64 {
    try selectInt64("PRAGMA wal_autocheckpoint")
  }

  /// What SQLite's page cache holds on this connection (#653).
  package func pageCacheStatusForTesting() throws -> InstantSQLitePageCacheStatus {
    try ensureOpenConnection()
    let cacheSize = try selectInt64("PRAGMA cache_size")
    var usedBytes: Int32 = 0
    var highwater: Int32 = 0
    sqlite3_db_status(connection.raw, SQLITE_DBSTATUS_CACHE_USED, &usedBytes, &highwater, 0)
    return InstantSQLitePageCacheStatus(cacheSize: cacheSize, usedBytes: Int(usedBytes))
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

/// What SQLite's page cache holds on one connection (#653).
package struct InstantSQLitePageCacheStatus: Equatable, Sendable {
  /// `PRAGMA cache_size`: a negative value bounds the cache in KiB, a positive one in pages.
  package var cacheSize: Int64
  /// The heap bytes the connection's page cache holds now (`SQLITE_DBSTATUS_CACHE_USED`).
  package var usedBytes: Int
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

// SAFETY: SQLite's raw pointer and its prepared statements are confined to the `SQLitePersistenceStore` actor.
// The wrapper is immutable outside that actor and only closes the connection when released.
private final class SQLiteConnection: @unchecked Sendable {
  var raw: OpaquePointer?
  /// Prepared statements kept for reuse on this connection (#653).
  var statements = SQLiteStatementCache()

  init(_ raw: OpaquePointer?) {
    self.raw = raw
  }

  /// Finalizes the cached statements and closes the connection. `sqlite3_close_v2` closes it once a statement still
  /// checked out is finalized too, when it is checked in.
  func close() {
    statements.finalizeAll()
    sqlite3_close_v2(raw)
    raw = nil
  }

  deinit {
    statements.finalizeAll()
    sqlite3_close_v2(raw)
  }
}

/// Prepared statements kept for reuse on one SQLite connection, keyed by their SQL (#653).
///
/// Preparing parses and plans the SQL, and a save ran the same few dozen statements every time, each prepared and
/// finalized on every call. A statement is checked out for one use and checked in afterwards, reset and with its
/// bindings cleared, so an idle statement holds no read snapshot and no bound value. A nested use of the same SQL while
/// it is checked out prepares its own statement. DDL, which runs once, and a statement with more than
/// `maximumParameterCount` parameters, built for one batch size, are not kept. At most `capacity` idle statements are
/// kept, the least recently used finalized past that. `finalizeAll()` runs before the connection closes; a statement
/// checked out then is finalized when it is checked in. An unmerged #403 branch (484c4f35) prepared statements once in
/// the same way.
struct SQLiteStatementCache {
  /// Room for a live write's whole cycle (#1007). Its save, delivery claim, acknowledgement and the apply of the server's
  /// answer run about 150 distinct statements (956 KB of statement memory in the tests' write cycle), and with 64 kept
  /// the least recently used one was always the next one needed, so every statement was prepared again on every write.
  static let defaultCapacity = 256
  static let maximumParameterCount = 32

  /// One SQL text's place in the cache. It stays in place while its statement is checked out, and the check-in reaches
  /// it through the statement, so a reuse hashes the SQL once (#1007). Taking a statement out of a dictionary and
  /// putting it back hashed the SQL five times, and each removal re-hashed the neighbors it shifted: SQL keys are
  /// hundreds of characters long.
  private final class Entry {
    let sql: String
    /// The statement waiting for reuse, or nil while it is checked out.
    var idle: OpaquePointer?
    var lastUse: UInt64 = 0
    /// False once the entry has left the cache; a statement of it that comes back is finalized.
    var isKept = true

    init(sql: String) {
      self.sql = sql
    }
  }

  let capacity: Int
  /// How many statements this cache has prepared.
  private(set) var preparedCount = 0
  /// How many statements wait for reuse.
  private(set) var idleCount = 0
  private var entries: [String: Entry] = [:]
  private var checkedOut: [OpaquePointer: (entry: Entry?, generation: Int)] = [:]
  private var generation = 0
  private var useClock: UInt64 = 0

  init(capacity: Int = defaultCapacity) {
    self.capacity = capacity
  }

  /// A statement for `sql` on `connection`: an idle one, or a new one. Nil with SQLite's result code when the SQL does
  /// not prepare.
  mutating func checkOut(
    _ sql: String,
    on connection: OpaquePointer?
  ) -> (statement: OpaquePointer?, resultCode: Int32) {
    let entry = entries[sql]
    if let entry, let statement = entry.idle {
      entry.idle = nil
      idleCount -= 1
      checkedOut[statement] = (entry, generation)
      return (statement, SQLITE_OK)
    }
    let mayKeep = !Self.isDDL(sql)
    var statement: OpaquePointer?
    let resultCode = sqlite3_prepare_v3(
      connection,
      sql,
      -1,
      mayKeep ? UInt32(SQLITE_PREPARE_PERSISTENT) : 0,
      &statement,
      nil
    )
    preparedCount += 1
    guard resultCode == SQLITE_OK, let statement else {
      sqlite3_finalize(statement)
      return (nil, resultCode)
    }
    var kept: Entry?
    if mayKeep, Int(sqlite3_bind_parameter_count(statement)) <= Self.maximumParameterCount {
      if let entry {
        kept = entry
      } else {
        let created = Entry(sql: sql)
        entries[sql] = created
        kept = created
      }
    }
    checkedOut[statement] = (kept, generation)
    return (statement, resultCode)
  }

  /// Takes back a statement from ``checkOut(_:on:)``: reset, bindings cleared, kept for reuse when it may be. A nested
  /// use's statement that comes back while the first one is already idle again is finalized.
  mutating func checkIn(_ statement: OpaquePointer?) {
    guard let statement else { return }
    guard let use = checkedOut.removeValue(forKey: statement),
      let entry = use.entry,
      entry.isKept,
      use.generation == generation,
      entry.idle == nil
    else {
      sqlite3_finalize(statement)
      return
    }
    sqlite3_reset(statement)
    sqlite3_clear_bindings(statement)
    useClock &+= 1
    entry.idle = statement
    entry.lastUse = useClock
    idleCount += 1
    if idleCount > capacity {
      evictLeastRecentlyUsed()
    }
  }

  /// Finalizes the idle statement used longest ago, and its entry leaves the cache.
  private mutating func evictLeastRecentlyUsed() {
    var leastRecentlyUsed: Entry?
    for entry in entries.values where entry.idle != nil {
      if entry.lastUse < leastRecentlyUsed?.lastUse ?? .max {
        leastRecentlyUsed = entry
      }
    }
    guard let leastRecentlyUsed, let statement = leastRecentlyUsed.idle else { return }
    sqlite3_finalize(statement)
    leastRecentlyUsed.idle = nil
    leastRecentlyUsed.isKept = false
    idleCount -= 1
    entries[leastRecentlyUsed.sql] = nil
  }

  /// Finalizes the statements waiting for reuse.
  mutating func finalizeIdle() {
    for entry in entries.values {
      if let statement = entry.idle {
        sqlite3_finalize(statement)
        entry.idle = nil
      }
    }
    idleCount = 0
  }

  /// Finalizes the statements waiting for reuse before their connection closes; a statement checked out now is
  /// finalized when it is checked in.
  mutating func finalizeAll() {
    finalizeIdle()
    generation += 1
  }

  /// `CREATE`, `ALTER` and `DROP` run once, at bootstrap or in a migration.
  private static func isDDL(_ sql: String) -> Bool {
    let keyword = sql.drop(while: \.isWhitespace).prefix(6).uppercased()
    return keyword.hasPrefix("CREATE") || keyword.hasPrefix("ALTER") || keyword.hasPrefix("DROP")
  }
}

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// `PRAGMA cache_size` for every connection: negative, so it bounds the page cache in KiB (2 MiB) (#653).
private let sqlitePageCacheSizeKibibytes = -2_048

/// The writer's `wal_autocheckpoint`: a commit that leaves the log this many frames long checkpoints it (#1118).
private let sqliteWALAutocheckpointFrames: Int32 = 4_000

/// Calls a handler when the system warns of memory pressure, from a dispatch memory-pressure source, which UIKit's
/// memory warning also comes from; it runs no timer (#653).
// SAFETY: `source` is a `let`: the store creates it, starts it once in its initializer, and cancels it in `deinit`, and
// a dispatch source is safe to call from any thread or executor (dispatch synchronizes it, no lock of ours is needed);
// its handler runs on a global dispatch queue and only starts a task.
private final class SQLiteMemoryPressureMonitor: @unchecked Sendable {
  private let source = DispatchSource.makeMemoryPressureSource(
    eventMask: [.warning, .critical],
    queue: .global(qos: .utility)
  )

  func start(_ handler: @escaping @Sendable () -> Void) {
    source.setEventHandler(handler: handler)
    source.activate()
  }

  deinit {
    source.cancel()
  }
}
