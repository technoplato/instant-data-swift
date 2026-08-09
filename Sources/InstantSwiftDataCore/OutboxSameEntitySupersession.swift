import Foundation

// MARK: - ADR 0015 same-entity outbox supersession (#155)
//
// Pure policy for high-churn open-segment (and similar) upserts: when many
// pending outbox mutations target the same singleton entity key with op kind
// upsert, keep only the latest local intent.
//
// Docs:
//   docs/adr/0015-sqlite-data-parity-ergonomics/follow-on-outbox-same-entity-supersession.md
// Parent write shape:
//   docs/adr/0015-sqlite-data-parity-ergonomics/open-segment-write-recipe.md
//
// Full InstantOutbox enqueue integration is intentional follow-on — call
// `OutboxSameEntitySupersession.decide` from the durable enqueue path when
// wiring (see TODO recipe entry on InstantRuntime outbox append).
//
// Upstream TypeScript (`Reactor.js` pushOps) appends every pending mutation and
// rewrites attr ids; it does not coalesce same-entity upserts. Swift’s durable
// SQLite outbox deliberately diverges for speech load (see recipe).

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

/// One outbox row projected for pure supersession decisions.
///
/// Deliberately decoupled from `PendingMutation` so policy unit tests do not
/// require a full store/transaction graph. Integration maps real mutations into
/// this shape at enqueue time.
public struct OutboxSupersessionCandidate: Hashable, Codable, Sendable, Identifiable {
  /// Outbox / transaction id.
  public var id: String
  /// Entity keys touched by this mutation (empty = ineligible for v1 replace).
  public var entityKeys: Set<OutboxSupersessionEntityKey>
  public var opKind: OutboxSupersessionOpKind
  public var status: InstantMutationStatus
  /// Outbox creation time (ms).
  public var createdAtMs: Int64
  /// Payload revision (e.g. segment `updatedAtMs`). When nil, `createdAtMs` is used.
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

  /// Convenience: singleton entity upsert candidate (speech open-segment shape).
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

/// Pure same-entity outbox supersession (no I/O, no actor).
///
/// **v1 eligibility (all required):**
/// - `status == .pending`
/// - `opKind == .upsert`
/// - exactly one entity key
/// - not permission poison
/// - not in-flight to server
///
/// Within each `(namespace, entityID, upsert)` group, only the latest intent
/// (by payload revision, then createdAt, then id) is kept.
public enum OutboxSameEntitySupersession: Sendable {
  /// Decide which candidates are superseded vs kept.
  ///
  /// Every input `id` appears in exactly one of `keptIDs` or `supersededIDs`.
  /// Order of `keptIDs` follows intent order among survivors; `supersededIDs`
  /// follow intent order among dropped rows.
  public static func decide(
    entries: [OutboxSupersessionCandidate]
  ) -> OutboxSupersessionDecision {
    guard !entries.isEmpty else {
      return OutboxSupersessionDecision(keptIDs: [], supersededIDs: [])
    }

    let sorted = entries.sorted(by: intentOrder)

    var superseded: [String] = []
    var keptEligibleLastByGroup: [SupersessionGroupKey: String] = [:]
    var nonEligibleKept: [String] = []
    // Track first-pass kept order for eligible survivors (updated as group grows).
    var eligibleSurvivorOrder: [String] = []
    var eligibleSurvivorIndex: [String: Int] = [:]

    for entry in sorted {
      guard isEligible(entry), let groupKey = supersessionGroupKey(for: entry) else {
        nonEligibleKept.append(entry.id)
        continue
      }

      if let previousID = keptEligibleLastByGroup[groupKey] {
        superseded.append(previousID)
        if let index = eligibleSurvivorIndex[previousID] {
          eligibleSurvivorOrder[index] = entry.id
          eligibleSurvivorIndex[entry.id] = index
          eligibleSurvivorIndex.removeValue(forKey: previousID)
        } else {
          eligibleSurvivorIndex[entry.id] = eligibleSurvivorOrder.count
          eligibleSurvivorOrder.append(entry.id)
        }
        keptEligibleLastByGroup[groupKey] = entry.id
      } else {
        keptEligibleLastByGroup[groupKey] = entry.id
        eligibleSurvivorIndex[entry.id] = eligibleSurvivorOrder.count
        eligibleSurvivorOrder.append(entry.id)
      }
    }

    // Survivors: eligible last-per-group in first-seen group order, then
    // non-eligible in intent order. Stable, deterministic, easy to assert.
    var kept = eligibleSurvivorOrder
    kept.append(contentsOf: nonEligibleKept)

    return OutboxSupersessionDecision(
      keptIDs: kept,
      supersededIDs: superseded
    )
  }

  /// Apply a decision to a candidate list (filter to kept, intent-sorted).
  public static func applying(
    _ decision: OutboxSupersessionDecision,
    to entries: [OutboxSupersessionCandidate]
  ) -> [OutboxSupersessionCandidate] {
    let kept = decision.keptIDSet
    return entries.filter { kept.contains($0.id) }.sorted(by: intentOrder)
  }

  /// Convenience: decide and return surviving candidates only.
  public static func coalescing(
    entries: [OutboxSupersessionCandidate]
  ) -> [OutboxSupersessionCandidate] {
    applying(decide(entries: entries), to: entries)
  }

  // MARK: Eligibility

  /// Whether this candidate may participate in same-entity upsert supersession.
  public static func isEligible(_ entry: OutboxSupersessionCandidate) -> Bool {
    guard entry.status == .pending else { return false }
    guard entry.opKind == .upsert else { return false }
    guard entry.entityKeys.count == 1 else { return false }
    guard !entry.isPermissionPoison else { return false }
    guard !entry.isInFlightToServer else { return false }
    return true
  }

  // MARK: Ordering

  /// Later local intent wins: payload revision, then createdAt, then id.
  public static func intentOrder(
    _ lhs: OutboxSupersessionCandidate,
    _ rhs: OutboxSupersessionCandidate
  ) -> Bool {
    let leftRevision = lhs.payloadRevisionMs ?? lhs.createdAtMs
    let rightRevision = rhs.payloadRevisionMs ?? rhs.createdAtMs
    if leftRevision != rightRevision {
      return leftRevision < rightRevision
    }
    if lhs.createdAtMs != rhs.createdAtMs {
      return lhs.createdAtMs < rhs.createdAtMs
    }
    return lhs.id < rhs.id
  }

  // MARK: Private

  private struct SupersessionGroupKey: Hashable, Sendable {
    var namespace: String
    var entityID: String
    var opKind: OutboxSupersessionOpKind
  }

  private static func supersessionGroupKey(
    for entry: OutboxSupersessionCandidate
  ) -> SupersessionGroupKey? {
    guard let key = entry.entityKeys.first, entry.entityKeys.count == 1 else {
      return nil
    }
    return SupersessionGroupKey(
      namespace: key.namespace,
      entityID: key.entityID,
      opKind: entry.opKind
    )
  }
}
