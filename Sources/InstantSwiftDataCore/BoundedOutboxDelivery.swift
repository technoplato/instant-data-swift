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
