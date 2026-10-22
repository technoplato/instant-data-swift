import Foundation

// History:
// - 2026-10-21: claims left by a process that has ended are released at the next claim instead of waiting out their
//   acknowledgement deadlines (#990).

/// The process that owns a runtime's durable delivery claims, and how a runtime tells that the process behind
/// another claimant's claims has ended (#990).
///
/// A delivery claim is a lease on the ordered outbox head: until it is answered, released, or its acknowledgement
/// deadline passes, no other claimant delivers. A runtime releases its own claims when its socket ends. A process that
/// ends without that release (killed, crashed, replaced by an update) leaves its claims behind, each with a deadline of
/// six seconds times its in-flight ordinal, up to five minutes for a full window, and the next launch delivers nothing
/// until the last of them passes.
///
/// Upstream `Reactor.js` keeps no durable claims: on `init-ok` of a new socket, `_flushPendingMessages` sends every
/// pending mutation again, in order. A claim whose process has ended can never be answered, so it can only be
/// released. A claim of a process that still runs, such as an app extension that shares the store, keeps its lease.
struct InstantOutboxClaimantProcess: Sendable {
  /// This process's identifier.
  var processID: Int32
  /// Unique to this launch. The system may give a later process the same identifier, never the same launch.
  var launchID: String
  /// Whether a claim whose claimant id names no process has ended. Libraries before #990 wrote such ids.
  var endsUnidentifiedClaimants: Bool
  /// Whether a process with this identifier exists now.
  var isRunning: @Sendable (_ processID: Int32) -> Bool

  /// The running process.
  static let current = InstantOutboxClaimantProcess(
    processID: ProcessInfo.processInfo.processIdentifier,
    launchID: UUID().uuidString.lowercased(),
    endsUnidentifiedClaimants: false,
    isRunning: { _ in true }
  )

  /// The claimant id of one runtime in this process, `process-<pid>-<launch>/<runtime>`.
  func claimantID(runtimeID: String) -> String {
    "process-\(processID)-\(launchID)/\(runtimeID)"
  }

  /// Whether the process that made claims under `claimantID` has ended, so that its claims can only be released.
  func hasEnded(claimantID: String) -> Bool {
    false
  }

  /// The process identifier and launch that a claimant id names, or `nil` for an id that names none.
  static func process(ofClaimantID claimantID: String) -> (processID: Int32, launchID: String)? {
    nil
  }
}
