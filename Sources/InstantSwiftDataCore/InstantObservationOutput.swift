// History:
// - 2026-10-31: one stream per query observation, written by the store and by the live query's server error under one
//   lock and read in its consumer's own pull; a live query ran five forwarding tasks per observation, a local one two,
//   and each emission resumed every one of them (#1493). The tasks an observation keeps running are counted for tests.

import Foundation
import os

/// The stream one query observation's consumer reads, and the one place its emissions are written (#1493).
///
/// The store hands each emission it gives the observer to ``yield(_:)``, and a live query's server error arrives
/// through ``reportServerError(_:)``. Both write under one lock: a new emission carries the current error, and a changed
/// error repeats the latest emission with it, so the stream's one buffered slot always holds the latest values with the
/// latest error, and nothing older can land after something newer (#360). The error stage this replaces was three tasks
/// merging two streams into a third.
///
/// Upstream `Reactor.js` `notifyQueryError` calls a query's callbacks with `{ error }` and the next result replaces it;
/// Swift keeps the values in the same emission, because a local-first observer must not lose what it shows when the
/// server stalls.
final class InstantObservationOutput: Sendable {
  private struct State: Sendable {
    /// The last emission written, kept only while a server error may repeat it.
    var latest: InstantQueryEmission?
    var serverError: InstantError?
  }

  let stream: AsyncStream<InstantQueryEmission>
  private let continuation: AsyncStream<InstantQueryEmission>.Continuation
  /// Whether a live query's server error can reach this output: a local observation keeps no copy of its latest
  /// emission.
  private let reportsServerErrors: Bool
  private let state = OSAllocatedUnfairLock(initialState: State())

  init(reportsServerErrors: Bool = false) {
    (stream, continuation) = AsyncStream.makeStream(bufferingPolicy: .bufferingNewest(1))
    self.reportsServerErrors = reportsServerErrors
  }

  /// Writes an emission the store hands the observer, with the query's current server error.
  func yield(_ emission: InstantQueryEmission) {
    guard reportsServerErrors else {
      continuation.yield(emission)
      return
    }
    state.withLock { state in
      let reported = emission.reportingServerError(state.serverError)
      state.latest = reported
      continuation.yield(reported)
    }
  }

  /// Records the query's latest server error (`nil` once the server answers it) and, when it changes what the latest
  /// emission reports, repeats that emission with it.
  func reportServerError(_ error: InstantError?) {
    state.withLock { state in
      state.serverError = error
      guard let current = state.latest, current.error != error else { return }
      let reported = current.reportingServerError(error)
      state.latest = reported
      continuation.yield(reported)
    }
  }

  /// Ends the stream: its consumer reads what the stream still holds, then the end. The latest emission kept for a
  /// server error goes now, not when the consumer lets go of the stream.
  func finish() {
    state.withLock { $0.latest = nil }
    continuation.finish()
  }

  /// Runs `action` once the stream ends, by ``finish()`` or because its consumer's task was cancelled while it waited.
  func onTermination(_ action: @escaping @Sendable () -> Void) {
    continuation.onTermination = { @Sendable _ in action() }
  }
}

/// The library tasks query observations keep running, counted for tests (#1493).
///
/// Every task an observation starts on the way to its consumer reports itself here. A test binds a census around the
/// call that opens an observation, and the census counts the tasks that call starts and the tasks those start, since a
/// task inherits its task-locals:
///
/// ```swift
/// let census = InstantObservationTaskCensus()
/// let stream = await InstantObservationTaskCensus.$current.withValue(census) {
///   await runtime.observe(plan)
/// }
/// ```
///
/// Outside tests no census is bound: a task pays one task-local read when it starts, and nothing is counted.
package final class InstantObservationTaskCensus: Sendable {
  @TaskLocal package static var current: InstantObservationTaskCensus?

  private let alive = OSAllocatedUnfairLock(initialState: 0)

  package init() {}

  /// The counted tasks that have started and not yet returned.
  package var aliveCount: Int { alive.withLock { $0 } }

  package func taskStarted() {
    alive.withLock { $0 += 1 }
  }

  package func taskFinished() {
    alive.withLock { $0 -= 1 }
  }
}
