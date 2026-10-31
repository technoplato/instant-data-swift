// History:
// - 2026-10-31: the tasks a query observation keeps running are counted for tests (#1493).

import Foundation
import os

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
