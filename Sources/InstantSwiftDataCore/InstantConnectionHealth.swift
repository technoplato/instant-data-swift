import Foundation
import os

/// A cheap read of how the connection to Instant is doing (#482 part C).
///
/// Scribe's save lane sets a write aside after it keeps failing for an unknown reason only while the connection is
/// demonstrably healthy: open, and other writes or results got through since that write first failed. Reading
/// ``InstantRuntime/connectionStatus()`` for that waits for the operation gate and reads SQLite; this reads counters the
/// runtime keeps in memory, with no gate, no SQLite and no actor hop.
public struct InstantConnectionHealth: Hashable, Sendable {
  /// Whether the live session is open: the server answered `init-ok` and the socket has not closed since.
  public var isOpen: Bool
  /// When a local write last committed: a `transact` returned after its local commit.
  public var lastLocalCommitAt: Date?
  /// When the server last acknowledged a write of this device (`transact-ok`).
  public var lastServerAcknowledgementAt: Date?
  /// When the server last sent a query result (`add-query-ok` or `refresh-ok`).
  public var lastServerResultAt: Date?
  /// The pending-write count the runtime last published in its connection status.
  public var pendingCount: Int

  public init(
    isOpen: Bool,
    lastLocalCommitAt: Date? = nil,
    lastServerAcknowledgementAt: Date? = nil,
    lastServerResultAt: Date? = nil,
    pendingCount: Int = 0
  ) {
    self.isOpen = isOpen
    self.lastLocalCommitAt = lastLocalCommitAt
    self.lastServerAcknowledgementAt = lastServerAcknowledgementAt
    self.lastServerResultAt = lastServerResultAt
    self.pendingCount = pendingCount
  }
}

/// The counters behind ``InstantConnectionHealth``, written where each event happens and read without a hop.
///
/// The lock guards one small value for one load or store, never a call out: the "tiny, local isolation domain" a lock is
/// for (Point-Free ep358 at 4:01), as `AsyncSerialGate`'s held flag does.
package final class InstantConnectionHealthRecorder: Sendable {
  private struct Counters {
    var lastLocalCommitAt: Date?
    var lastServerAcknowledgementAt: Date?
    var lastServerResultAt: Date?
    var pendingCount = 0
  }

  private let counters = OSAllocatedUnfairLock(initialState: Counters())

  package init() {}

  package func recordLocalCommit(at date: Date) {
    counters.withLock { $0.lastLocalCommitAt = date }
  }

  package func recordServerAcknowledgement(at date: Date) {
    counters.withLock { $0.lastServerAcknowledgementAt = date }
  }

  package func recordServerResult(at date: Date) {
    counters.withLock { $0.lastServerResultAt = date }
  }

  package func recordPendingCount(_ count: Int) {
    counters.withLock { $0.pendingCount = count }
  }

  package func health(isOpen: Bool) -> InstantConnectionHealth {
    let current = counters.withLock { $0 }
    return InstantConnectionHealth(
      isOpen: isOpen,
      lastLocalCommitAt: current.lastLocalCommitAt,
      lastServerAcknowledgementAt: current.lastServerAcknowledgementAt,
      lastServerResultAt: current.lastServerResultAt,
      pendingCount: current.pendingCount
    )
  }
}

extension InstantTimestamp {
  /// This timestamp as a `Date`.
  package var date: Date {
    Date(timeIntervalSince1970: Double(milliseconds) / 1_000)
  }
}

/// What holds the runtime's operation gate now, read without a hop onto the gate (freeze-185 item 7).
///
/// An app's watchdog can tell a slow save from a stuck one: which function holds the gate, in which of its named
/// phases, since when, and how many callers queue behind it.
public struct InstantOperationGateSnapshot: Hashable, Sendable {
  /// The function that holds the gate, or nil when it is free.
  public var holder: String?
  /// The phase the holder named last, such as a write's "save" or a server apply's "commit plan".
  public var holderPhase: String?
  /// When the holder took the gate.
  public var heldSince: Date?
  /// How many callers queue behind the holder.
  public var waiterCount: Int
  /// When the longest-queued caller started waiting.
  public var longestWaitingSince: Date?

  public init(
    holder: String?,
    holderPhase: String? = nil,
    heldSince: Date? = nil,
    waiterCount: Int = 0,
    longestWaitingSince: Date? = nil
  ) {
    self.holder = holder
    self.holderPhase = holderPhase
    self.heldSince = heldSince
    self.waiterCount = waiterCount
    self.longestWaitingSince = longestWaitingSince
  }
}
