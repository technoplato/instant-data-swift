import Foundation

// History:
// - 2026-11-06: added for #696 (criteria from #134). A held write could be listed, exported and sent again, never
//   settled: nothing read the server to say whether it had landed. Verification reads the server's own rows, and
//   completing or discarding a held write records that evidence beside its kept row.

/// What the server holds of a held write, read from the server (#696).
///
/// A held write's effect on this device's cache is unknown, so this device cannot say whether the write landed; the
/// server can. A verification reads the server's own rows for every slot the write set (the answer the server sent, not
/// this device's view of it, which unsent later writes and the held write's own leftover effect can still color) and
/// settles the write only on that evidence:
///
/// ```swift
/// let verification = try await client.verifyQuarantinedMutation(id: mutation.id)
/// switch verification.verdict {
/// case .applied: try await client.completeQuarantinedMutation(id: mutation.id)
/// case .notApplied: try await client.discardQuarantinedMutation(id: mutation.id)
/// case .cannotTell: break  // It stays held; the verdict says why.
/// }
/// ```
public struct InstantQuarantinedMutationVerification: Hashable, Codable, Sendable {
  /// Whether the server holds the write.
  public enum Verdict: Hashable, Codable, Sendable {
    /// The server holds every value the write set, or a newer one that a later write of this device, which the server
    /// accepted, set: nothing of it is left to send, and completing it loses nothing.
    case applied
    /// The write is not on the server, and its record says why it will not get there as it stands.
    case notApplied(NotApplied)
    /// The server's rows cannot settle it, for the reason given. It stays held.
    case cannotTell(CannotTell)
  }

  /// Why a write is not on the server.
  public enum NotApplied: Hashable, Codable, Sendable {
    /// Its outbox row records no send: it never left this device. Send it again to deliver it, or discard it.
    case neverSent
    /// The server refused it with a client-error status, and its rows do not hold what it set.
    case refusedByServer(status: Int, type: String?, message: String)
  }

  /// Why the server's rows cannot settle a write.
  public enum CannotTell: Hashable, Codable, Sendable {
    /// It was sent, the server did not refuse it, and the server's rows do not hold some value it set. It may never
    /// have arrived, or it arrived and a later write this device does not know of replaced it; a value that differs
    /// cannot tell those apart.
    case serverDoesNotHoldIt
    /// It has an operation whose effect the server's rows cannot show, named here: a retraction, a deletion, a step
    /// addressed by a lookup, a deep merge that removes a key, or no write at all.
    case uncheckableOperation(String)
    /// The server could not be read: the error's message.
    case serverUnreadable(String)
    /// Its body no longer decodes, so what it set is unknown.
    case undecodable
  }

  /// The mutation's ID.
  public var id: String
  /// When the server's rows were read.
  public var verifiedAt: InstantTimestamp
  public var verdict: Verdict
  /// Every write operation of the mutation, with what covers it: the server's rows (``InstantSlotCoverage/Coverage/serverResult(receivedAt:)``,
  /// at ``verifiedAt``), a later write of this device, or nothing (with the values the server's rows hold). Empty when
  /// the body does not decode or the server could not be read.
  public var slots: [InstantSlotCoverage]

  public init(
    id: String,
    verifiedAt: InstantTimestamp,
    verdict: Verdict,
    slots: [InstantSlotCoverage]
  ) {
    self.id = id
    self.verifiedAt = verifiedAt
    self.verdict = verdict
    self.slots = slots
  }
}
