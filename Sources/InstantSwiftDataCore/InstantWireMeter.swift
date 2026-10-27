import Foundation
import os

// History:
// - 2026-10-24: added (#1124): the live socket's frames and bytes, by op and direction. A device's log said nothing about
//   what a change cost the radio: #1076's exercise measured 126 KB received per transcript write (a whole 256-line
//   page restated by every refresh-ok), and no phone could be checked against it.

/// The live socket's traffic: frames and bytes by op, each way, counted where each frame is sent or received (#1124).
///
/// A frame's bytes are its text as the library encodes or decodes it. `URLSessionWebSocketTask` compresses frames with
/// permessage-deflate when the server accepts it, as Instant's did when #1076 checked, so the radio carries less than
/// this: about a tenth for a refresh in #1076's exercise. Counting a frame is one lock. Once a minute of traffic the
/// socket logs what the minute added (`network.wire-summary`).
///
/// ```swift
/// let minute = InstantWireMeter.snapshot().subtracting(previous)
/// let receivedKB = Double(minute.receivedBytes) / 1_024
/// ```
public enum InstantWireMeter {
  /// Everything counted since launch.
  public static func snapshot() -> InstantWireSnapshot {
    shared.snapshot()
  }

  /// A query's shape (#1117).
  public static func queryShape(of query: InstantLiveJSONValue) -> String {
    "unknown"
  }

  package static let shared = InstantWireMeterStorage()
}

/// Which way a frame went (#1124).
public enum InstantWireDirection: String, CaseIterable, Sendable {
  case sent
  case received
}

/// What ``InstantWireMeter`` counted, or what it counted between two snapshots (#1124).
public struct InstantWireSnapshot: Sendable, Equatable {
  /// One op's frames in one direction.
  public struct Measure: Sendable, Equatable {
    public var frames: Int
    /// The frames' text, in bytes.
    public var bytes: Int

    public init(frames: Int = 0, bytes: Int = 0) {
      self.frames = frames
      self.bytes = bytes
    }
  }

  /// By op (`transact`, `add-query`, ...).
  public var sent: [String: Measure]
  /// By op (`transact-ok`, `refresh-ok`, `add-query-ok`, ...).
  public var received: [String: Measure]
  /// What each query's answers carried (#1117), by its shape (``InstantWireMeter/queryShape(of:)``).
  public var receivedByQuery: [String: Measure]

  public init(
    sent: [String: Measure] = [:],
    received: [String: Measure] = [:],
    receivedByQuery: [String: Measure] = [:]
  ) {
    self.sent = sent
    self.received = received
    self.receivedByQuery = receivedByQuery
  }

  public var sentFrames: Int { sent.values.reduce(0) { $0 + $1.frames } }
  public var sentBytes: Int { sent.values.reduce(0) { $0 + $1.bytes } }
  public var receivedFrames: Int { received.values.reduce(0) { $0 + $1.frames } }
  public var receivedBytes: Int { received.values.reduce(0) { $0 + $1.bytes } }

  /// What was counted after `earlier`.
  public func subtracting(_ earlier: Self) -> Self {
    func delta(_ later: [String: Measure], _ earlier: [String: Measure]) -> [String: Measure] {
      later.reduce(into: [:]) { result, entry in
        let before = earlier[entry.key] ?? Measure()
        let measure = Measure(
          frames: max(0, entry.value.frames - before.frames),
          bytes: max(0, entry.value.bytes - before.bytes)
        )
        if measure.frames > 0 || measure.bytes > 0 { result[entry.key] = measure }
      }
    }
    return Self(sent: delta(sent, earlier.sent), received: delta(received, earlier.received))
  }

  /// The log line's fields: each direction's totals, and each op's `frames/bytes`.
  var logMetadata: [String: String] {
    var metadata = [
      "sentFrames": String(sentFrames),
      "sentBytes": String(sentBytes),
      "receivedFrames": String(receivedFrames),
      "receivedBytes": String(receivedBytes),
    ]
    for (op, measure) in sent { metadata["sent.\(op)"] = "\(measure.frames)/\(measure.bytes)" }
    for (op, measure) in received { metadata["received.\(op)"] = "\(measure.frames)/\(measure.bytes)" }
    return metadata
  }
}

/// The meter's counts: the process-wide one behind ``InstantWireMeter``, or a test's own (#1124).
///
/// The lock guards two small dictionaries updated in place, one short critical section per frame.
package final class InstantWireMeterStorage: Sendable {
  private struct State: Sendable {
    var counts = InstantWireSnapshot()
    var countsAtLastSummary = InstantWireSnapshot()
    var lastSummaryAt: UInt64
  }

  /// How much traffic a summary covers: one a minute, as a host's energy ledger reads its counters.
  package static let summaryIntervalNanoseconds: UInt64 = 60_000_000_000

  private let state: OSAllocatedUnfairLock<State>

  package init(now: UInt64 = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)) {
    state = OSAllocatedUnfairLock(initialState: State(lastSummaryAt: now))
  }

  /// Counts one frame of `op` and returns the summary that is due, if one is: what was counted since the last one,
  /// at most one a minute.
  package func record(
    _ direction: InstantWireDirection,
    op: String,
    bytes: Int,
    now: UInt64 = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
  ) -> InstantWireSnapshot? {
    state.withLock { state in
      switch direction {
      case .sent:
        state.counts.sent[op, default: InstantWireSnapshot.Measure()].frames += 1
        state.counts.sent[op, default: InstantWireSnapshot.Measure()].bytes += max(0, bytes)
      case .received:
        state.counts.received[op, default: InstantWireSnapshot.Measure()].frames += 1
        state.counts.received[op, default: InstantWireSnapshot.Measure()].bytes += max(0, bytes)
      }
      guard now &- state.lastSummaryAt >= Self.summaryIntervalNanoseconds else { return nil }
      let summary = state.counts.subtracting(state.countsAtLastSummary)
      state.lastSummaryAt = now
      state.countsAtLastSummary = state.counts
      return summary
    }
  }

  package func snapshot() -> InstantWireSnapshot {
    state.withLock { $0.counts }
  }

  /// The most query shapes the meter keeps apart (#1117).
  package static let maximumQueryShapes = 48

  /// Counts one answer for each shape (#1117).
  package func recordQueries(_ answers: [(shape: String, bytes: Int)]) {}
}
