import Foundation

// History:
// - 2026-10-14: added for #696. A store an earlier library version wrote can hold retained mutations whose optimistic
//   effect has no SQLite-owned preparation receipt; the first one refused every live connection, so every later write
//   waited unsent. Runtime bootstrap now moves each one aside, whole, and synchronizes the rest.

/// An outbox mutation the runtime moved aside, whole, instead of letting it stop synchronization (#696).
///
/// A store written by an earlier library version can hold a retained mutation whose optimistic effect has no
/// SQLite-owned preparation receipt, so the runtime cannot prove how to undo or replay what it did to the local cache.
/// Up to 1.9.9 the first such mutation refused every live connection until the application reset its store, and every
/// later write, however valid, waited unsent behind it. Since 1.9.10, runtime bootstrap moves each one into the
/// `instant_outbox_quarantined` table with its outbox row exactly as it was, then synchronizes every other write in its
/// order. The library never sends, changes, or deletes a quarantined mutation; an application lists and exports them:
///
/// ```swift
/// for mutation in try await client.quarantinedMutations(limit: 100) {
///   print(mutation.id, mutation.reason, mutation.outboxRowJSON)
/// }
/// ```
public struct InstantQuarantinedMutation: Hashable, Sendable, Identifiable {
  /// Why the runtime moved a mutation aside.
  public enum Reason: String, Hashable, Codable, Sendable {
    /// The mutation's optimistic effect has no SQLite-owned preparation receipt, so its local cache effect is unknown.
    case noPreparationReceipt = "no-preparation-receipt"
  }

  /// The mutation's ID, which is also its transaction's ID.
  public var id: String
  /// Why the runtime moved it aside.
  public var reason: Reason
  /// When the runtime moved it aside.
  public var quarantinedAt: InstantTimestamp
  /// When the mutation was created, which is its place in the outbox's order.
  public var createdAt: InstantTimestamp
  /// The status the mutation had in the outbox, such as pending or failed, when it is one this version knows.
  public var status: InstantMutationStatus?
  /// The outbox body, exactly as it was stored.
  public var body: String
  /// Every column of the outbox row as it was, as one JSON object: what an export writes.
  public var outboxRowJSON: String
  /// The body, decoded; nil when it no longer decodes.
  public var mutation: PendingMutation?

  public init(
    id: String,
    reason: Reason,
    quarantinedAt: InstantTimestamp,
    createdAt: InstantTimestamp,
    status: InstantMutationStatus?,
    body: String,
    outboxRowJSON: String,
    mutation: PendingMutation?
  ) {
    self.id = id
    self.reason = reason
    self.quarantinedAt = quarantinedAt
    self.createdAt = createdAt
    self.status = status
    self.body = body
    self.outboxRowJSON = outboxRowJSON
    self.mutation = mutation
  }
}

/// What runtime bootstrap does with a retained outbox mutation that has no SQLite-owned preparation receipt (#696).
///
/// Such a mutation comes from a store an earlier library version wrote, or from a body whose receipt the runtime
/// revoked because it no longer matched. Its local cache effect is unknown, so it can never be sent safely.
public enum InstantRetainedMutationRecovery: String, Hashable, Sendable {
  /// Moves each one, whole, into the quarantine (see ``InstantQuarantinedMutation``), then synchronizes every other
  /// write in its order. The default since 1.9.10.
  case quarantine
  /// Keeps each one in the outbox, where it refuses every live connection until the application resets its store or
  /// an operator repairs it: the behavior up to 1.9.9.
  case blockSynchronization
}
