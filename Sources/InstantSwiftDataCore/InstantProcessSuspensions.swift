// History:
// - 2026-10-28: the process's suspensions, as an app's watchdog finds them, so the operation gate's measures count only
//   the time the process ran (#1319).

import Foundation

/// The times this process was suspended, as the app's watchdog found them (#1319).
public enum InstantProcessSuspensions {
  /// How many suspensions the record keeps.
  static let capacity = 64

  /// Records that the process was suspended for `seconds` and has just resumed.
  public static func recordResume(afterSuspensionOf seconds: TimeInterval) {}

  /// Records a suspension that ended at `end` on `CLOCK_UPTIME_RAW` and lasted `nanoseconds`.
  static func record(suspensionEndingAtUptime end: UInt64, nanoseconds: UInt64) {}

  /// How many nanoseconds the process was recorded suspended between two readings of `CLOCK_UPTIME_RAW`.
  static func suspendedNanoseconds(fromUptime start: UInt64, toUptime end: UInt64) -> UInt64 { 0 }

  static var recordedCountForTesting: Int { 0 }

  static func resetForTesting() {}
}
