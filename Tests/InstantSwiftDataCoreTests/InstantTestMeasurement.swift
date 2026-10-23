// History
// 2026-10-23  #1021  Created. Tests that measure the whole process (its CPU, its memory, the process-wide diagnostics
//                    hub, or the wall time a step takes) failed in every whole-bundle run on an idle Mac mini and
//                    passed alone: beside 1,384 tests running in parallel they measured the neighbours. They now run
//                    alone, serially, in the measurement pass of scripts/known-failing-tests.sh.

import Foundation
import Testing

/// Whether this process is the measurement pass: `scripts/known-failing-tests.sh run` sets it for a second, serial
/// run of only the measurement tests, after the bundle (#1021).
enum InstantTestMeasurement {
  static let environmentKey = "INSTANT_SWIFT_DATA_MEASUREMENTS"

  static var isMeasurementPass: Bool {
    ProcessInfo.processInfo.environment[environmentKey] == "1"
  }
}

extension Trait where Self == ConditionTrait {
  /// A test whose assertion is a measurement the rest of the bundle would change: CPU, physical footprint, a count
  /// on the process-wide diagnostics hub, or how long a step takes on the wall clock (#1021).
  ///
  /// It runs only in the measurement pass, alone and serially. A plain `swift test` reports it as skipped with this
  /// reason; run it with `scripts/known-failing-tests.sh run`, or set `INSTANT_SWIFT_DATA_MEASUREMENTS=1` and run it
  /// by itself.
  static var measurement: Self {
    .enabled(
      if: InstantTestMeasurement.isMeasurementPass,
      "A measurement: it runs alone, in the measurement pass of scripts/known-failing-tests.sh (#1021)."
    )
  }
}
