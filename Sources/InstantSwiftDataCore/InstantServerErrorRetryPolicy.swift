import Foundation

/// How long to wait before offering a write, or sending an add-query, again after the server answered it with a
/// transient error: a 5xx such as a stalled server's `operation-timed-out`, a 408, a 425, or a 429.
///
/// The delay doubles from ``baseMilliseconds`` with each consecutive failure of the same write or query, is capped at
/// ``maximumMilliseconds``, and is scaled by a jitter factor in `0.5...1`, so the clients that failed together in one
/// server stall do not all retry in the same instant.
///
/// Upstream `Reactor.js` never retries either: `_handleMutationError` drops the mutation, and `notifyQueryError`
/// leaves a failed query to the next `init-ok`. Swift keeps a durable outbox and long-lived queries, so it retries
/// both on the socket that is still open instead of closing it (#376, #360). Only a dead socket reconnects: a close,
/// or a server that stops answering pings.
struct InstantServerErrorRetryPolicy: Sendable {
  var baseMilliseconds: UInt64 = 250
  var maximumMilliseconds: UInt64 = 5_000
  /// The jitter factor, clamped to `0.5...1`. Tests pin it to 1.
  var jitter: @Sendable () -> Double = { Double.random(in: 0.5...1) }

  /// The delay before the next attempt, after `attempt` consecutive failures (1 for the first).
  func delayMilliseconds(afterFailure attempt: Int) -> UInt64 {
    let doublings = UInt64(min(max(attempt - 1, 0), 32))
    let (uncapped, overflow) = baseMilliseconds.multipliedReportingOverflow(by: 1 << doublings)
    let capped = overflow ? maximumMilliseconds : min(uncapped, maximumMilliseconds)
    let factor = min(max(jitter(), 0.5), 1)
    return UInt64((Double(capped) * factor).rounded())
  }
}

/// The automatic outbox's response to writes the server answered with a transient error (#376).
///
/// The socket stays open and every other write in flight keeps its claim. Delivery pauses until the backoff of the
/// write that failed most often has passed, then offers one write at a time, in outbox order, until the server
/// accepts one. A server that is stalled therefore sees one probe per backoff, not the whole window again.
struct InstantMutationServerErrorBackoff: Sendable {
  private var consecutiveFailures: [String: Int] = [:]
  private(set) var deliveryResumesAtMilliseconds: Int64?
  private(set) var probesOneWrite = false

  /// Records one transient failure of `mutationID` at `now` and returns its attempt number and delay.
  mutating func recordFailure(
    of mutationID: String,
    now: Int64,
    policy: InstantServerErrorRetryPolicy
  ) -> (attempt: Int, delayMilliseconds: UInt64, resumesAtMilliseconds: Int64) {
    let attempt = consecutiveFailures[mutationID, default: 0] + 1
    consecutiveFailures[mutationID] = attempt
    let delay = policy.delayMilliseconds(afterFailure: attempt)
    let (resumesAt, overflow) = now.addingReportingOverflow(Int64(clamping: delay))
    let deadline = overflow ? Int64.max : resumesAt
    deliveryResumesAtMilliseconds = max(deliveryResumesAtMilliseconds ?? deadline, deadline)
    probesOneWrite = true
    return (attempt, delay, deliveryResumesAtMilliseconds ?? deadline)
  }

  /// The server accepted `mutationID`: it is healthy again, so delivery returns to full windows.
  mutating func recordAcceptance(of mutationID: String) {
    consecutiveFailures[mutationID] = nil
    probesOneWrite = false
  }

  /// `mutationID` reached a terminal outcome other than acceptance; forget its failures.
  mutating func forget(_ mutationID: String) {
    consecutiveFailures[mutationID] = nil
  }

  /// The time delivery may resume, while the pause is still running at `now`; `nil` once it has passed.
  mutating func pauseDeadline(now: Int64) -> Int64? {
    guard let deliveryResumesAtMilliseconds else { return nil }
    guard now < deliveryResumesAtMilliseconds else {
      self.deliveryResumesAtMilliseconds = nil
      return nil
    }
    return deliveryResumesAtMilliseconds
  }

  func consecutiveFailureCount(of mutationID: String) -> Int {
    consecutiveFailures[mutationID, default: 0]
  }
}

/// The runtime's ``InstantMutationServerErrorBackoff``, shared by its receive loop and its delivery pump.
actor InstantMutationServerErrorBackoffState {
  private var backoff = InstantMutationServerErrorBackoff()

  func recordFailure(
    of mutationID: String,
    now: Int64,
    policy: InstantServerErrorRetryPolicy
  ) -> (attempt: Int, delayMilliseconds: UInt64, resumesAtMilliseconds: Int64) {
    backoff.recordFailure(of: mutationID, now: now, policy: policy)
  }

  func recordAcceptance(of mutationID: String) {
    backoff.recordAcceptance(of: mutationID)
  }

  func forget(_ mutationID: String) {
    backoff.forget(mutationID)
  }

  func pauseDeadline(now: Int64) -> Int64? {
    backoff.pauseDeadline(now: now)
  }

  var probesOneWrite: Bool {
    backoff.probesOneWrite
  }
}

/// What a transient-server-error retry belongs to, for tests and diagnostics.
package enum InstantServerErrorRetryOwner: Hashable, Sendable {
  /// A durable write, by mutation id.
  case mutation(String)
  /// A live query, by registration key.
  case query(String)
}
