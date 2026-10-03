import Foundation

enum InstantOutboxDeliveryState: String, Sendable {
  case needsDelivery = "needs_delivery"
  case serverAccepted = "server_accepted"
  case terminal
  case invalid
}

enum InstantOutboxDeliveryClaimState: String, Sendable {
  case ready
  case claimed
}

/// Durable ownership of a WebSocket mutation-error frame.
///
/// A server error is allowed to mutate local state only while the receiving
/// runtime still owns the exact SQLite delivery claim. A terminal row makes a
/// duplicate frame an idempotent no-op, while every other state is stale for
/// this socket and must not be resolved through lifecycle aliases.
enum InstantLiveMutationErrorDisposition: Equatable, Sendable {
  case owned(claimToken: String)
  case alreadyTerminal
  case stale
  case missing
}

/// One fixed memory/transport envelope shared by automatic delivery and every
/// public explicit-flush call. An explicit call is one window, not a request to
/// materialize or aggregate the durable queue.
enum InstantOutboxClaimLimits {
  static let maximumMutationCount = 50
  static let maximumStepCount = 256
  static let maximumBodyDecodeCount = 50
  static let maximumEncodedBodyBytes = 8 * 1_024 * 1_024
  static let claimTimeoutMilliseconds: Int64 = 5_000
}

typealias InstantAutomaticOutboxClaimLimits = InstantOutboxClaimLimits

enum InstantAutomaticOutboxAdmission {
  /// Validates the exact durable mutation after rollback metadata is attached
  /// and before either SQLite or the hot store commits it. Existing legacy rows
  /// are quarantined by the selector, but a new local write must fail without
  /// ever materializing an undeliverable optimistic value.
  static func validateNewMutation(_ mutation: PendingMutation) throws {
    guard mutation.provesReplayableOptimisticEffectReceipt else {
      throw InstantError(
        code: .validationFailed,
        operation: "transact",
        localID: mutation.id,
        message:
          "Mutation '\(mutation.id)' has no Runtime-prepared optimistic-effect receipt.",
        recovery:
          "Submit the transaction through InstantRuntime so local preparation and durable outbox admission commit together."
      )
    }
    let stepCount = InstantOutboxDeliveryMetadata.stepCount(in: mutation)
    guard stepCount <= InstantAutomaticOutboxClaimLimits.maximumStepCount else {
      throw InstantError(
        code: .validationFailed,
        operation: "transact",
        localID: mutation.id,
        message:
          "Mutation '\(mutation.id)' expands to \(stepCount) transport steps, exceeding the \(InstantAutomaticOutboxClaimLimits.maximumStepCount)-step durable delivery limit.",
        recovery:
          "Split this write into smaller transactions before retrying; no local triples or outbox row were committed."
      )
    }

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let encodedBodyByteCount = try encoder.encode(mutation).count
    guard encodedBodyByteCount <= InstantAutomaticOutboxClaimLimits.maximumEncodedBodyBytes
    else {
      throw InstantError(
        code: .validationFailed,
        operation: "transact",
        localID: mutation.id,
        message:
          "Mutation '\(mutation.id)' encodes to \(encodedBodyByteCount) bytes, exceeding the \(InstantAutomaticOutboxClaimLimits.maximumEncodedBodyBytes)-byte durable delivery limit.",
        recovery:
          "Split or reduce this write before retrying; no local triples or outbox row were committed."
      )
    }
  }
}

struct InstantOutboxDeliveryPosition: Hashable, Sendable {
  var createdAtMilliseconds: Int64
  var mutationID: String
}

struct InstantAutomaticOutboxClaimRequest: Sendable {
  var claimantID: String
  var claimToken: String
  var now: InstantTimestamp
  var maximumMutationCount: Int
  var maximumStepCount: Int
  var maximumBodyDecodeCount: Int
  var maximumEncodedBodyByteCount: Int
  var requiresExclusiveLane: Bool

  init(
    claimantID: String,
    claimToken: String,
    now: InstantTimestamp,
    maximumMutationCount: Int = InstantAutomaticOutboxClaimLimits.maximumMutationCount,
    maximumStepCount: Int = InstantAutomaticOutboxClaimLimits.maximumStepCount,
    maximumBodyDecodeCount: Int = InstantAutomaticOutboxClaimLimits.maximumBodyDecodeCount,
    maximumEncodedBodyByteCount: Int = InstantAutomaticOutboxClaimLimits.maximumEncodedBodyBytes,
    requiresExclusiveLane: Bool = false
  ) {
    self.claimantID = claimantID
    self.claimToken = claimToken
    self.now = now
    self.maximumMutationCount = maximumMutationCount
    self.maximumStepCount = maximumStepCount
    self.maximumBodyDecodeCount = maximumBodyDecodeCount
    self.maximumEncodedBodyByteCount = maximumEncodedBodyByteCount
    self.requiresExclusiveLane = requiresExclusiveLane
  }
}

/// Later writes of this device that cover every operation of a write (library-78, item 3), and for a refused re-send
/// the server's own results (#441).
enum InstantOutboxWriteCoverage: Sendable {
  /// Accepted writes cover it, or for a refused re-send the server's results show the rest; `serverTransactionID` is
  /// the newest of theirs.
  case acceptedWrites(serverTransactionID: String, mutationIDs: [String])
  /// Writes not all accepted yet cover it.
  case pendingWrites(mutationIDs: [String])
  /// A refused re-send that later writes and the server's results do not cover yet, whose uncovered operations are
  /// all inserts a result from the server may still show (#441).
  case awaitingServerResult(mutationIDs: [String])
  case none
}

/// What a refused re-send counts beyond later writes of this device (#441).
///
/// A slot counts as held when a live-query result the server sent, stored at or after the write was created, shows
/// the write's value for it. Instant's server applies every transact it receives, without deduplicating a re-sent
/// client-event-id (`session.clj`), so a re-send whose first offer was applied is refused by a rule like
/// `newData.updatedAtMs >= data.updatedAtMs` once a later write advanced the row, while the server already holds the
/// values it sets.
struct InstantServerResultCheck: Sendable {
  /// The metadata key of the processed-transaction watermark; a write resolved by the server's results takes the
  /// watermark as its server transaction id, so it leaves the outbox at the next server apply.
  var processedTransactionIDKey: String
  /// Whether an insert no stored result shows yet may wait for a result that does: the runtime allows it while the
  /// connection still owes the first answer to a registered live query and the wait has not ended.
  var waitsForServerResult: Bool
}

/// How a server refusal of a write resolves when later writes of this device, or for a re-send the server's own
/// results, may cover it (item 3, #441).
enum InstantRefusedWriteResolution: Sendable {
  /// Accepted writes cover it, or for a re-send the server's results show the rest: resolved as accepted, not
  /// failed. `serverResultSlotCount` counts the slots the server's results showed.
  case superseded(PendingMutation, coveringMutationIDs: [String], serverResultSlotCount: Int)
  /// Writes still in flight cover it: it keeps its claim, parked, until they are answered.
  case heldBehindPendingWrites(coveringMutationIDs: [String])
  /// A re-send whose remaining slots a result from the server may still show (#441): it keeps its claim, parked,
  /// until one does or the wait ends.
  case awaitingServerResult(coveringMutationIDs: [String])
  /// The refusal stands.
  case notCovered
  /// This runtime no longer holds the write's claim.
  case stale
}

struct InstantAutomaticOutboxClaimWindow: Sendable {
  var mutations: [PendingMutation]
  var projectedMutations: [PendingMutation]
  var failedMutations: [PendingMutation]
  var successorWriteKeys: Set<InstantVisibleWriteKey>
  var hasUnknownSuccessorWriteKeys: Bool
  var visibleWriteFilter: InstantVisibleWriteFilter
  var resultingRevisions: InstantPersistenceRevisions
  var claimToken: String?
  var reclaimedMutationIDs: Set<String>
  var nextClaimDeadlineMilliseconds: Int64?
  var shouldContinueImmediately: Bool
  var decodedBodyCount: Int
  var decodedBodyByteCount: Int
  var synchronizationBlocker: InstantSynchronizationBlocker?
  /// Re-sends that accepted later writes cover, resolved as accepted instead of offered again (item 3).
  var supersededMutations: [PendingMutation] = []
}

/// One durable mutation plus the exact later-write frontier that protects its
/// ordered body while visible state is projected for delivery.
struct InstantOutboxProjectionCandidate: Sendable {
  var mutation: PendingMutation
  var preservingWriteKeys: Set<InstantVisibleWriteKey>
}

struct InstantOutboxProjectionMetadata: Sendable {
  var encodedBodyByteCount: Int
  var requiredScalarKeys: Set<InstantVisibleWriteKey>
}

struct InstantOutboxDeliveryClaim: Equatable, Sendable {
  var state: InstantOutboxDeliveryClaimState
  var claimToken: String?
  var claimantID: String?
  var deadlineMilliseconds: Int64?
  var projectedBodyByteCount: Int?
  var deliveryStarted: Bool
}

struct InstantAutomaticOutboxTransportSelection: Sendable {
  var mutations: [InstantTransportMutation]
  var claimToken: String?
  var claimedMutationIDs: Set<String>
  var reclaimedMutationIDs: Set<String>
  var nextClaimDeadlineMilliseconds: Int64?
  var shouldContinueImmediately: Bool
}

struct InstantPersistenceRevisions: Equatable, Sendable {
  var store: Int64
  var outbox: Int64
}

struct InstantOutboxBatchFailureApplication: Sendable {
  var mutations: [PendingMutation]
  var resultingOutboxRevision: Int64
  var decodedBodyCount: Int
  var decodedBodyByteCount: Int
}

/// A body-free durable snapshot for public wait-all semantics.
///
/// The runtime's resident outbox actor contains only the active bounded claim,
/// so it cannot answer whether SQLite still has work. This summary keeps the
/// public wait contract durable without reconstructing the queue.
package struct InstantMutationDeliveryBarrierSummary: Sendable {
  package var outstandingMutationCount: Int
  package var firstOutstandingMutationID: String?
  package var firstOutstandingIsLocalOnlyConfirmation: Bool
  package var firstOutstandingConfirmationSource: InstantMutationConfirmationSource?
  package var sampleOutstandingMutationIDs: [String]
  package var firstFailedMutation: PendingMutation?

  package init(
    outstandingMutationCount: Int,
    firstOutstandingMutationID: String?,
    firstOutstandingIsLocalOnlyConfirmation: Bool,
    firstOutstandingConfirmationSource: InstantMutationConfirmationSource?,
    sampleOutstandingMutationIDs: [String],
    firstFailedMutation: PendingMutation?
  ) {
    self.outstandingMutationCount = outstandingMutationCount
    self.firstOutstandingMutationID = firstOutstandingMutationID
    self.firstOutstandingIsLocalOnlyConfirmation = firstOutstandingIsLocalOnlyConfirmation
    self.firstOutstandingConfirmationSource = firstOutstandingConfirmationSource
    self.sampleOutstandingMutationIDs = sampleOutstandingMutationIDs
    self.firstFailedMutation = firstFailedMutation
  }
}

enum InstantOutboxDeliveryMetadata {
  static let currentVersion = 2

  static func state(for mutation: PendingMutation) -> InstantOutboxDeliveryState {
    switch mutation.status {
    case .pending:
      .needsDelivery
    case .confirmed:
      mutation.provesServerAcceptance ? .serverAccepted : .needsDelivery
    case .failed:
      .terminal
    }
  }

  static func writeKeys(in mutation: PendingMutation) -> Set<InstantVisibleWriteKey> {
    InstantVisibleWriteFilter.writeKeys(in: mutation.transaction.operations)
  }

  static func stepCount(in mutation: PendingMutation) -> Int {
    InstantTransportMutation(mutation).txSteps.count
  }

  static func confirmationProven(in mutation: PendingMutation) -> Bool {
    mutation.status == .confirmed && mutation.provesServerAcceptance
  }
}

enum InstantBoundedOutboxDelivery {
  static func projectionCandidates(
    mutations: [PendingMutation],
    successorWriteKeys: Set<InstantVisibleWriteKey>,
    hasUnknownSuccessorWriteKeys: Bool
  ) -> [InstantOutboxProjectionCandidate] {
    let mutations = mutations.sorted(by: PendingMutation.creationOrder)
    let selectedWriteKeys = InstantVisibleWriteFilter.writeKeys(in: mutations)
    var laterQueuedWriteKeys = successorWriteKeys
    if hasUnknownSuccessorWriteKeys {
      laterQueuedWriteKeys.formUnion(selectedWriteKeys)
    }

    var candidatesReversed: [InstantOutboxProjectionCandidate] = []
    candidatesReversed.reserveCapacity(mutations.count)
    for mutation in mutations.reversed() {
      candidatesReversed.append(
        InstantOutboxProjectionCandidate(
          mutation: mutation,
          preservingWriteKeys: laterQueuedWriteKeys
        )
      )
      laterQueuedWriteKeys.formUnion(
        InstantVisibleWriteFilter.writeKeys(in: mutation.transaction.operations)
      )
    }
    return Array(candidatesReversed.reversed())
  }

  static func projectedPendingMutation(
    _ candidate: InstantOutboxProjectionCandidate,
    visibleWriteFilter: InstantVisibleWriteFilter
  ) -> PendingMutation {
    var mutation = candidate.mutation
    mutation.transaction.operations =
      visibleWriteFilter.discardingWritesOlderThanVisibleState(
        mutation.transaction.operations,
        preserving: candidate.preservingWriteKeys
      )
    return mutation
  }

  static func encodedProjectedBodyByteCount(_ mutation: PendingMutation) throws -> Int {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    return try encoder.encode(mutation).count
  }

  /// Computes the exact projected `PendingMutation` size without decoding the
  /// authoritative scalar. Filtering first accounts for removed optional
  /// writes; each required substitution then changes only one encoded value.
  static func projectionMetadata(
    for candidate: InstantOutboxProjectionCandidate,
    visibleWriteFilter: InstantVisibleWriteFilter
  ) throws -> InstantOutboxProjectionMetadata {
    let hydrations = visibleWriteFilter.requiredScalarHydrations(
      in: candidate.mutation.transaction.operations,
      preserving: candidate.preservingWriteKeys
    )
    let baseMutation = projectedPendingMutation(
      candidate,
      visibleWriteFilter: visibleWriteFilter
    )
    var encodedBodyByteCount = try encodedProjectedBodyByteCount(baseMutation)
    let valueEncoder = JSONEncoder()
    valueEncoder.outputFormatting = [.sortedKeys]
    for hydration in hydrations {
      guard let authoritativeValueByteCount =
        visibleWriteFilter.requiredScalarEncodedValueByteCount(for: hydration.key)
      else { continue }
      let originalValueByteCount = try valueEncoder.encode(hydration.originalValue).count
      encodedBodyByteCount -= originalValueByteCount
      encodedBodyByteCount += authoritativeValueByteCount
    }
    return InstantOutboxProjectionMetadata(
      encodedBodyByteCount: encodedBodyByteCount,
      requiredScalarKeys: Set(hydrations.map(\.key))
    )
  }

  static func transportMutations(
    in window: InstantAutomaticOutboxClaimWindow
  ) -> [InstantTransportMutation] {
    window.projectedMutations.sorted(by: PendingMutation.creationOrder).map { mutation in
      var transportMutation = InstantTransportMutation(mutation)
      if mutation.status == .confirmed, !mutation.provesServerAcceptance {
        transportMutation.status = .pending
      }
      return transportMutation
    }
  }
}

/// Refusals parked behind covering writes in flight (library-78, item 3) or waiting for a result from the server that
/// shows the values they set (#441), with the claim each still holds and the failure to record if neither comes. In
/// memory only: a socket's death releases every claim, and the next connection offers the write again.
actor InstantParkedRefusals {
  struct Parked: Sendable {
    var claimToken: String
    var failure: InstantMutationFailure
    /// The server's refusal, for the log if the refusal stands.
    var error: InstantLiveErrorMessage
    /// Until when the refusal waits for a server result (#441); `nil` waits only for the covering writes' answers.
    var serverResultDeadlineMilliseconds: Int64?
  }

  private var parked: [String: Parked] = [:]

  var isEmpty: Bool { parked.isEmpty }

  var snapshot: [String: Parked] { parked }

  /// The earliest server-result deadline of a parked refusal, if any waits for one.
  var earliestServerResultDeadlineMilliseconds: Int64? {
    parked.values.compactMap(\.serverResultDeadlineMilliseconds).min()
  }

  func park(
    _ mutationID: String,
    claimToken: String,
    failure: InstantMutationFailure,
    error: InstantLiveErrorMessage,
    serverResultDeadlineMilliseconds: Int64?
  ) {
    parked[mutationID] = Parked(
      claimToken: claimToken,
      failure: failure,
      error: error,
      serverResultDeadlineMilliseconds: serverResultDeadlineMilliseconds
    )
  }

  /// Stops a parked refusal's wait for a server result once only covering writes in flight remain to answer.
  func stopWaitingForServerResult(_ mutationID: String, claimToken: String) {
    guard parked[mutationID]?.claimToken == claimToken else { return }
    parked[mutationID]?.serverResultDeadlineMilliseconds = nil
  }

  func remove(_ mutationID: String) {
    parked[mutationID] = nil
  }

  /// Forgets every parked refusal; returns whether one waited for a server result, so its wake can be cancelled.
  @discardableResult
  func removeAll() -> Bool {
    let waited = parked.values.contains { $0.serverResultDeadlineMilliseconds != nil }
    parked.removeAll()
    return waited
  }
}
