import Foundation

#if canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#endif

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
    endsUnidentifiedClaimants: endsUnidentifiedClaimantsOnThisPlatform,
    isRunning: processExists
  )

  /// True on iOS, tvOS, watchOS and visionOS. There an app and its extensions are updated together, and the update
  /// ends every process of the old build, so a claim that an older library wrote belongs to a process that has ended.
  /// False on macOS and Mac Catalyst, where processes of different builds can share one store, so such a claim keeps
  /// its lease.
  static var endsUnidentifiedClaimantsOnThisPlatform: Bool {
    #if (os(iOS) && !targetEnvironment(macCatalyst)) || os(tvOS) || os(watchOS) || os(visionOS)
      true
    #else
      false
    #endif
  }

  /// The claimant id of one runtime in this process, `process-<pid>-<launch>/<runtime>`.
  func claimantID(runtimeID: String) -> String {
    "process-\(processID)-\(launchID)/\(runtimeID)"
  }

  /// Whether the process that made claims under `claimantID` has ended, so that its claims can only be released.
  ///
  /// A claimant of this launch is another runtime of this process, or its explicit flush lane, and has not ended. A
  /// claimant with this process's identifier but another launch has ended: one identifier belongs to one process at a
  /// time, and this process holds it. Any other claimant has ended when no process with its identifier exists; when the
  /// system has given that identifier to another process, the claim keeps its lease, as it did before #990.
  func hasEnded(claimantID: String) -> Bool {
    guard let claimant = Self.process(ofClaimantID: claimantID) else {
      return endsUnidentifiedClaimants
    }
    if claimant.launchID == launchID { return false }
    if claimant.processID == processID { return true }
    return !isRunning(claimant.processID)
  }

  /// The process identifier and launch that a claimant id names, or `nil` for an id that names none.
  ///
  /// The explicit flush lane appends `-explicit-<token>` to its runtime's claimant id; the process part is the same.
  static func process(ofClaimantID claimantID: String) -> (processID: Int32, launchID: String)? {
    let prefix = "process-"
    guard claimantID.hasPrefix(prefix), let slash = claimantID.firstIndex(of: "/") else { return nil }
    let named = claimantID[claimantID.index(claimantID.startIndex, offsetBy: prefix.count)..<slash]
    guard let dash = named.firstIndex(of: "-"),
      let processID = Int32(named[..<dash]), processID > 0
    else { return nil }
    let launchID = named[named.index(after: dash)...]
    guard !launchID.isEmpty else { return nil }
    return (processID, String(launchID))
  }

  /// Whether a process with this identifier exists, asked with `kill(_:_:)` and signal 0, which delivers no signal.
  /// Only `ESRCH` means that none exists. Any other answer, `EPERM` from a sandbox included, means one does.
  static func processExists(_ processID: Int32) -> Bool {
    guard processID > 0 else { return true }
    #if canImport(Darwin) || canImport(Glibc)
      if kill(processID, 0) == 0 { return true }
      return errno != ESRCH
    #else
      return true
    #endif
  }
}
