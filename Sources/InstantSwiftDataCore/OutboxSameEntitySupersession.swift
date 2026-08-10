import Foundation

// MARK: - ADR 0015 same-entity outbox supersession (#155)
//
// Durable immediate-tail policy for high-churn open-segment assignments. The
// enqueue path compares only the one exact physical tail with the newcomer and
// replaces it only when both are identical schema-known scalar assignments.
//
// Docs:
//   docs/adr/0015-sqlite-data-parity-ergonomics/follow-on-outbox-same-entity-supersession.md
// Parent write shape:
//   docs/adr/0015-sqlite-data-parity-ergonomics/open-segment-write-recipe.md
//
// Upstream TypeScript (`Reactor.js` pushOps) appends every pending mutation and
// rewrites attr ids; it does not coalesce same-entity upserts. Swift’s durable
// SQLite outbox deliberately diverges only for a never-offered immediate tail.

// MARK: - Model

/// Primary key for supersession grouping: Instant namespace + entity id.
public struct OutboxSupersessionEntityKey: Hashable, Codable, Sendable, Comparable {
  public var namespace: String
  public var entityID: String

  public init(namespace: String, entityID: String) {
    self.namespace = namespace
    self.entityID = entityID
  }

  public static func < (lhs: Self, rhs: Self) -> Bool {
    if lhs.namespace != rhs.namespace {
      return lhs.namespace < rhs.namespace
    }
    return lhs.entityID < rhs.entityID
  }
}

/// Closed set of outbox operation kinds for supersession policy.
///
/// Prefer this ADT over free-form strings (ADR 0015 / library AGENTS).
public enum OutboxSupersessionOpKind: String, Hashable, Codable, Sendable {
  /// Full create/update/merge upsert of entity field triples.
  case upsert
  /// Entity delete.
  case delete
  /// Link / unlink cardinality ops (not full row replace).
  case link
  /// Media transfer — never supersede via this policy.
  case media
  /// Anything else (rule params, mixed, unknown).
  case other
}

/// Legacy queue-wide projection retained for source compatibility.
///
/// Durable enqueue does not use this projection. It cannot prove exact queue
/// adjacency, normalized operation shape, rollback composition, or whether a
/// row was ever claimed/offered.
public struct OutboxSupersessionCandidate: Hashable, Codable, Sendable, Identifiable {
  /// Outbox / transaction id.
  public var id: String
  /// Entity keys touched by this mutation (empty = ineligible for v1 replace).
  public var entityKeys: Set<OutboxSupersessionEntityKey>
  public var opKind: OutboxSupersessionOpKind
  public var status: InstantMutationStatus
  /// Outbox creation time (ms).
  public var createdAtMs: Int64
  /// Legacy payload revision retained for decoding/source compatibility. The
  /// durable immediate-tail policy does not use domain payload revisions.
  public var payloadRevisionMs: Int64?
  /// Already sent to server; awaiting ack — v1 does not supersede these.
  public var isInFlightToServer: Bool
  /// Permission-denied / poison terminal evidence — never drop.
  public var isPermissionPoison: Bool

  public init(
    id: String,
    entityKeys: Set<OutboxSupersessionEntityKey>,
    opKind: OutboxSupersessionOpKind,
    status: InstantMutationStatus = .pending,
    createdAtMs: Int64,
    payloadRevisionMs: Int64? = nil,
    isInFlightToServer: Bool = false,
    isPermissionPoison: Bool = false
  ) {
    self.id = id
    self.entityKeys = entityKeys
    self.opKind = opKind
    self.status = status
    self.createdAtMs = createdAtMs
    self.payloadRevisionMs = payloadRevisionMs
    self.isInFlightToServer = isInFlightToServer
    self.isPermissionPoison = isPermissionPoison
  }

  /// Legacy convenience projection. It does not establish supersession safety.
  @available(
    *,
    deprecated,
    message: "Queue-wide candidate projection cannot prove durable immediate-tail safety."
  )
  public static func singletonUpsert(
    id: String,
    namespace: String,
    entityID: String,
    createdAtMs: Int64,
    payloadRevisionMs: Int64? = nil,
    status: InstantMutationStatus = .pending,
    isInFlightToServer: Bool = false,
    isPermissionPoison: Bool = false
  ) -> Self {
    Self(
      id: id,
      entityKeys: [OutboxSupersessionEntityKey(namespace: namespace, entityID: entityID)],
      opKind: .upsert,
      status: status,
      createdAtMs: createdAtMs,
      payloadRevisionMs: payloadRevisionMs,
      isInFlightToServer: isInFlightToServer,
      isPermissionPoison: isPermissionPoison
    )
  }
}

/// Partition of input transaction ids after supersession.
public struct OutboxSupersessionDecision: Hashable, Codable, Sendable {
  /// Entries that remain in the outbox (including non-eligible).
  public var keptIDs: [String]
  /// Eligible pending upserts fully replaced by a later same-key upsert.
  public var supersededIDs: [String]

  public init(keptIDs: [String], supersededIDs: [String]) {
    self.keptIDs = keptIDs
    self.supersededIDs = supersededIDs
  }

  public var keptIDSet: Set<String> { Set(keptIDs) }
  public var supersededIDSet: Set<String> { Set(supersededIDs) }
}

// MARK: - Policy

/// Exact immediate-tail supersession plus source-compatible legacy no-ops.
public enum OutboxSameEntitySupersession: Sendable {
  /// Returns whether a newcomer has the complete schema-known scalar
  /// assignment shape required for supersession. Runtime calls this before
  /// reading the durable tail so partial/reference writes pay no tail decode.
  static func isEligibleImmediateTailNewcomer(
    _ newcomer: PendingMutation,
    attributes: [InstantAttribute]
  ) -> Bool {
    guard newcomer.status == .pending else { return false }
    let attributesByID = Dictionary(
      uniqueKeysWithValues: attributes.map { ($0.id, $0) }
    )
    return immediateTailShape(
      newcomer.transaction,
      attributesByID: attributesByID
    ) != nil
  }

  /// Returns whether a newly prepared mutation may replace the one exact
  /// durable outbox tail immediately before it.
  ///
  /// This is deliberately pairwise. Durable enqueue owns ordering and must
  /// never search past an intervening row: a failed, claimed, offered, delete,
  /// precondition, lookup, reference, or unrelated tail is an ordering barrier.
  /// Persistence separately proves that the predecessor remains the exact
  /// pending/active/ready/never-offered tail in the save transaction.
  static func canReplaceImmediateTail(
    _ predecessor: PendingMutation,
    with newcomer: PendingMutation,
    attributes: [InstantAttribute]
  ) -> Bool {
    guard predecessor.status == .pending, newcomer.status == .pending else {
      return false
    }
    // The physical queue is ordered by `(createdAt, id)`. Requiring strict
    // creation order prevents an equal-time, lower-id replacement from moving
    // ahead of an unrelated row that was previously before the tail. Reusing
    // the predecessor id is also unsafe because a late server frame would be
    // indistinguishable from the survivor.
    guard predecessor.id != newcomer.id,
      PendingMutation.creationOrder(predecessor, newcomer)
    else { return false }

    let attributesByID = Dictionary(
      uniqueKeysWithValues: attributes.map { ($0.id, $0) }
    )
    guard
      let predecessorShape = immediateTailShape(
        predecessor.transaction,
        attributesByID: attributesByID
      ),
      let newcomerShape = immediateTailShape(
        newcomer.transaction,
        attributesByID: attributesByID
      ),
      predecessorShape.entityID == newcomerShape.entityID,
      predecessorShape.namespace == newcomerShape.namespace,
      predecessorShape.writeTimes.keys == newcomerShape.writeTimes.keys
    else { return false }

    return predecessorShape.writeTimes.allSatisfy { attributeID, predecessorTime in
      guard let newcomerTime = newcomerShape.writeTimes[attributeID] else { return false }
      return newcomerTime >= predecessorTime
    }
  }

  /// Legacy queue-wide decision retained as a conservative no-op.
  @available(
    *,
    deprecated,
    message: "Queue-wide grouping crosses durable barriers; enqueue uses exact immediate-tail assignment checks."
  )
  public static func decide(
    entries: [OutboxSupersessionCandidate]
  ) -> OutboxSupersessionDecision {
    return OutboxSupersessionDecision(
      keptIDs: entries.map(\.id),
      supersededIDs: []
    )
  }

  /// Legacy queue-wide application retained as a conservative no-op.
  @available(
    *,
    deprecated,
    message: "Queue-wide projection is disabled; enqueue uses exact immediate-tail assignment checks."
  )
  public static func applying(
    _ decision: OutboxSupersessionDecision,
    to entries: [OutboxSupersessionCandidate]
  ) -> [OutboxSupersessionCandidate] {
    _ = decision
    return entries
  }

  /// Legacy queue-wide coalescing retained as a conservative no-op.
  @available(
    *,
    deprecated,
    message: "Queue-wide coalescing crosses durable barriers; enqueue uses exact immediate-tail assignment checks."
  )
  public static func coalescing(
    entries: [OutboxSupersessionCandidate]
  ) -> [OutboxSupersessionCandidate] {
    entries
  }

  /// Legacy projected eligibility is disabled because it lacks durable facts.
  @available(
    *,
    deprecated,
    message: "Projected eligibility cannot prove immediate-tail assignment safety."
  )
  public static func isEligible(_ entry: OutboxSupersessionCandidate) -> Bool {
    _ = entry
    return false
  }

  /// Legacy ordering now mirrors durable creation order and ignores payload
  /// revision. It does not itself authorize replacement.
  @available(
    *,
    deprecated,
    message: "Ordering does not authorize supersession; use the durable enqueue path."
  )
  public static func intentOrder(
    _ lhs: OutboxSupersessionCandidate,
    _ rhs: OutboxSupersessionCandidate
  ) -> Bool {
    if lhs.createdAtMs != rhs.createdAtMs {
      return lhs.createdAtMs < rhs.createdAtMs
    }
    return lhs.id < rhs.id
  }

  // MARK: Private

  private struct ImmediateTailShape: Sendable {
    var entityID: String
    var namespace: String
    var writeTimes: [String: InstantTimestamp]
  }

  private static func immediateTailShape(
    _ transaction: InstantStoreTransaction,
    attributesByID: [String: InstantAttribute]
  ) -> ImmediateTailShape? {
    guard !transaction.operations.isEmpty else { return nil }

    var entityID: String?
    var namespace: String?
    var writeTimes: [String: InstantTimestamp] = [:]
    var hasMatchingPrimaryKey = false
    writeTimes.reserveCapacity(transaction.operations.count)

    for operation in transaction.operations {
      guard case let .insert(triple) = operation,
        let attribute = attributesByID[triple.attributeID],
        attribute.cardinality == .one,
        attribute.valueType != .ref,
        isConcreteScalar(triple.value),
        writeTimes.updateValue(triple.txTime, forKey: triple.attributeID) == nil
      else { return nil }

      if let entityID {
        guard entityID == triple.entityID else { return nil }
      } else {
        entityID = triple.entityID
      }
      if let namespace {
        guard namespace == attribute.namespace else { return nil }
      } else {
        namespace = attribute.namespace
      }
      if attribute.primaryKey {
        guard !hasMatchingPrimaryKey,
          case let .string(primaryKeyValue) = triple.value,
          primaryKeyValue == triple.entityID
        else { return nil }
        hasMatchingPrimaryKey = true
      }
    }

    guard let entityID, let namespace, hasMatchingPrimaryKey else { return nil }
    return ImmediateTailShape(
      entityID: entityID,
      namespace: namespace,
      writeTimes: writeTimes
    )
  }

  /// Instant scalar attributes include JSON values; only relationships and
  /// lookup targets are excluded. Cardinality and schema type are checked by
  /// `immediateTailShape` before this value-level check.
  private static func isConcreteScalar(_ value: InstantValue) -> Bool {
    switch value {
    case .ref, .lookupRef:
      false
    case .null, .string, .number, .bool, .date, .json:
      true
    }
  }
}
