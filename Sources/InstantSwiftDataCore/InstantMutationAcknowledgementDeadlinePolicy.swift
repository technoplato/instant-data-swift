import Foundation

/// Mirrors upstream Reactor's six-second interval multiplied by the in-flight
/// mutation ordinal for both durable automatic claims and live reservations.
/// Swift adapts timeout recovery by retaining the durable row while the live
/// session enforces a replacement-generation barrier before retry.
enum InstantMutationAcknowledgementDeadlinePolicy {
  static let baseIntervalMilliseconds: Int64 = 6_000

  static func timeoutMilliseconds(inFlightOrdinal: Int) -> Int64 {
    precondition(inFlightOrdinal > 0)
    let (timeout, overflow) = baseIntervalMilliseconds.multipliedReportingOverflow(
      by: Int64(inFlightOrdinal)
    )
    return overflow ? .max : timeout
  }

  static func deadlineMilliseconds(
    after now: InstantTimestamp,
    inFlightOrdinal: Int
  ) -> Int64 {
    let timeout = timeoutMilliseconds(inFlightOrdinal: inFlightOrdinal)
    let (deadline, overflow) = now.milliseconds.addingReportingOverflow(timeout)
    return overflow ? .max : deadline
  }

  static func deadline(
    after now: Date,
    inFlightOrdinal: Int
  ) -> Date {
    now.addingTimeInterval(
      TimeInterval(timeoutMilliseconds(inFlightOrdinal: inFlightOrdinal)) / 1_000
    )
  }
}
