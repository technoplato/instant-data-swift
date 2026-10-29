// History:
// - 2026-10-28: maintenance no caller waits for runs inside an activity that keeps the process running, and stops
//   between its steps when the system is about to suspend the process (#1319).

import Foundation
import os

/// Keeps the process running while the runtime does maintenance no caller waits for, such as the live-query prune, and
/// says when the system is about to suspend it (#1319).
public struct InstantMaintenanceActivity: Sendable {
  /// Starts an activity named `reason`; end the token when the work stops.
  public var begin: @Sendable (_ reason: String) -> InstantMaintenanceActivityToken

  public init(begin: @escaping @Sendable (_ reason: String) -> InstantMaintenanceActivityToken) {
    self.begin = begin
  }

  /// An activity that never expires.
  public static let unbounded = Self { _ in InstantMaintenanceActivityToken() }
}

/// One maintenance activity (#1319).
public final class InstantMaintenanceActivityToken: Sendable {
  private struct State: Sendable {
    var isExpired = false
    var isEnded = false
  }

  private let state = OSAllocatedUnfairLock(initialState: State())

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
  public func end() { state.withLock { $0.isEnded = true } }
}
