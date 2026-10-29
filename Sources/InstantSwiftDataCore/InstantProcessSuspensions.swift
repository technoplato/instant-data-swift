// History:
// - 2026-10-28: the process's suspensions, as an app's watchdog finds them, so the operation gate's measures count only
//   the time the process ran (#1319).

import Foundation
import os

/// The times this process was suspended, as the app's watchdog found them (#1319).
///
/// A device's operation gate reported a prune batch holding it 2,236,773 ms, and an outbox release waiting 391,652 ms
/// behind it: the gate timed on the wall clock, and iOS had suspended the app for most of it. No clock stops while a
/// process is suspended and the device is awake (`CLOCK_UPTIME_RAW` stops only while the device sleeps), so the gate
/// subtracts the suspensions recorded here. An app whose watchdog ticks on its own thread knows each one when it next
/// ticks; Scribe's StallWatchdog calls ``recordResume(afterSuspensionOf:)`` with the gap it saw.
///
/// The record keeps the last ``capacity`` suspensions as values under one lock, so recording one costs one lock and no
/// allocation once full, and reading costs one pass over at most ``capacity`` spans (#1285: a diagnostic never slows the
/// app, and holds values, never a function, in its lock).
public enum InstantProcessSuspensions {
  /// How many suspensions the record keeps: a wait or a hold that outlives more than this many is rare, and its
  /// oldest suspensions then count as running time.
  static let capacity = 64

  private struct Span: Sendable {
    var start: UInt64
    var end: UInt64
  }

  private struct Record: Sendable {
    var spans: [Span] = []
    /// Where the next span goes once the record is full.
    var next = 0
    /// The latest end of any span kept, so a span that began after it is answered without a pass.
    var latestEnd: UInt64 = 0
  }

  private static let ledger = OSAllocatedUnfairLock(initialState: Record())

  /// Records that the process was suspended for `seconds` and has just resumed: the suspension ends now on
  /// `CLOCK_UPTIME_RAW`. Call it from the thread that noticed, as soon as it noticed.
  public static func recordResume(afterSuspensionOf seconds: TimeInterval) {
    guard seconds.isFinite, seconds > 0 else { return }
    let end = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
    let nanoseconds = min(UInt64(seconds * 1e9), end)
    record(suspensionEndingAtUptime: end, nanoseconds: nanoseconds)
  }

  /// Records a suspension that ended at `end` on `CLOCK_UPTIME_RAW` and lasted `nanoseconds`.
  static func record(suspensionEndingAtUptime end: UInt64, nanoseconds: UInt64) {
    let span = Span(start: end >= nanoseconds ? end - nanoseconds : 0, end: end)
    ledger.withLock { record in
      if record.spans.count < capacity {
        record.spans.append(span)
      } else {
        record.spans[record.next] = span
        record.next = (record.next + 1) % capacity
      }
      record.latestEnd = max(record.latestEnd, end)
    }
  }

  /// How many nanoseconds the process was recorded suspended between two readings of `CLOCK_UPTIME_RAW`, at most the
  /// span between them.
  static func suspendedNanoseconds(fromUptime start: UInt64, toUptime end: UInt64) -> UInt64 {
    guard end > start else { return 0 }
    return ledger.withLock { record in
      guard record.latestEnd > start else { return 0 }
      var total: UInt64 = 0
      for span in record.spans {
        let from = max(span.start, start)
        let to = min(span.end, end)
        if to > from { total += to - from }
      }
      return min(total, end - start)
    }
  }

  static var recordedCountForTesting: Int { ledger.withLock { $0.spans.count } }

  static func resetForTesting() {
    ledger.withLock { $0 = Record() }
  }
}
