// History:
// - 2026-10-28: maintenance no caller waits for runs inside an activity that keeps the process running, and stops
//   between its steps when the system is about to suspend the process (#1319).

import Foundation
import os

/// Keeps the process running while the runtime does maintenance no caller waits for, such as the live-query prune, and
/// says when the system is about to suspend it (#1319).
///
/// A device's prune batch took the operation gate 3 s after the app left the front, and iOS suspended the app in the
/// middle of it: the batch held the gate until the app ran again 37 minutes later, and the outbox release and the live
/// reconnect that ran first after the resume waited behind it. SQLite's and Apple's guidance meet here: hold a lock only
/// for the work that needs it, never across a suspension; work that may still run when the app leaves the front either
/// finishes inside a background task or lets go and resumes later. The prune takes an activity before its first batch
/// and stops before its next batch once the activity expires, so no batch is under way when the process is suspended.
///
/// ```swift
/// configuration.maintenanceActivity = .live  // the default; tests pass one they expire by hand
/// ```
public struct InstantMaintenanceActivity: Sendable {
  /// Starts an activity named `reason`; end the token when the work stops.
  public var begin: @Sendable (_ reason: String) -> InstantMaintenanceActivityToken

  public init(begin: @escaping @Sendable (_ reason: String) -> InstantMaintenanceActivityToken) {
    self.begin = begin
  }

  /// An activity that never expires.
  public static let unbounded = Self { _ in InstantMaintenanceActivityToken() }

  /// The system's expiring activity (`ProcessInfo.performExpiringActivity(withReason:using:)`) on iOS, iPadOS, watchOS,
  /// tvOS and visionOS, where the system suspends apps; ``unbounded`` on macOS, where it does not.
  ///
  /// The system calls the activity's block once to start it and again, with `expired`, when it is about to suspend the
  /// process; a first call that is already expired means it refused the time. The first call holds the activity until
  /// the work ends the token. Starting an activity asks another process for an assertion, which on a saturated phone can
  /// take seconds, so it is asked from a utility thread and the work never waits for the answer.
  public static let live = Self { reason in
    #if os(macOS)
      _ = reason
      return InstantMaintenanceActivityToken()
    #else
      let token = InstantMaintenanceActivityToken()
      DispatchQueue.global(qos: .utility).async {
        let started = OSAllocatedUnfairLock(initialState: false)
        ProcessInfo.processInfo.performExpiringActivity(withReason: reason) { expired in
          let isFirstCall = started.withLock { started in
            defer { started = true }
            return !started
          }
          if expired { token.expire() }
          guard isFirstCall, !expired else { return }
          token.waitUntilEnded()
        }
      }
      return token
    #endif
  }
}

/// One maintenance activity (#1319): whether the system is about to suspend the process, and the work's end.
public final class InstantMaintenanceActivityToken: Sendable {
  private struct State: Sendable {
    var isExpired = false
    var isEnded = false
  }

  private let state = OSAllocatedUnfairLock(initialState: State())
  /// Signalled once when the work ends, for the system's first call to return and end the activity.
  private let ended = DispatchSemaphore(value: 0)

  public init(isExpired: Bool = false) {
    state.withLock { $0.isExpired = isExpired }
  }

  /// Whether the system is about to suspend the process, or refused the activity: work stops at its next step.
  public var isExpired: Bool { state.withLock { $0.isExpired } }

  /// Whether the work ended the activity.
  public var isEnded: Bool { state.withLock { $0.isEnded } }

  /// The system's notice that it is about to suspend the process.
  public func expire() { state.withLock { $0.isExpired = true } }

  /// Ends the activity; later calls do nothing.
  public func end() {
    let first = state.withLock { state -> Bool in
      defer { state.isEnded = true }
      return !state.isEnded
    }
    if first { ended.signal() }
  }

  /// Blocks the calling thread, the system's first call, until the work ends the activity.
  func waitUntilEnded() {
    ended.wait()
  }
}
