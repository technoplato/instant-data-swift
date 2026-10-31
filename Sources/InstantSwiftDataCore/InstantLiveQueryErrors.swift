// History:
// - 2026-10-31: the registry writes each query's error into its observations' outputs, the streams their consumers read,
//   instead of a stream of errors that three tasks per observation merged into the emissions (#1493).

import Foundation

/// The latest server error of each live query, by registration key, for that query's observers (#360).
///
/// Upstream `Reactor.js` `notifyQueryError` calls every subscriber of a query with `{ error }`, and the subscription
/// stays registered. Swift adds the error to the query's emissions instead: an observer keeps its stream and its
/// last values, sees the error, and sees it clear once the server answers the query again. Each observation's output
/// takes the error under the lock it writes emissions under (#1493), so an error never lands on an older emission.
actor InstantLiveQueryErrors {
  private var errors: [String: InstantError] = [:]
  private var outputs: [String: [UUID: InstantObservationOutput]] = [:]

  /// Reports `key`'s errors to `output` from now on, starting with its current error when it has one.
  func register(_ output: InstantObservationOutput, for key: String) -> UUID {
    let id = UUID()
    outputs[key, default: [:]][id] = output
    if let error = errors[key] {
      output.reportServerError(error)
    }
    return id
  }

  /// Records `error` as the query's latest server error (`nil` once the server answers it) and tells its observers.
  func publish(_ error: InstantError?, for key: String) {
    guard errors[key] != error else { return }
    errors[key] = error
    for output in outputs[key, default: [:]].values {
      output.reportServerError(error)
    }
  }

  func error(for key: String) -> InstantError? {
    errors[key]
  }

  func observerCountForTesting(for key: String) -> Int {
    outputs[key]?.count ?? 0
  }

  /// Stops reporting to the output `register(_:for:)` returned `id` for.
  func remove(_ id: UUID, for key: String) {
    outputs[key]?[id] = nil
    guard outputs[key]?.isEmpty == true else { return }
    // Nobody observes the query any more; a later observation starts from the server's next answer.
    outputs[key] = nil
    errors[key] = nil
  }
}

extension InstantQueryEmission {
  /// This emission with `error` as the live query's latest server error.
  func reportingServerError(_ error: InstantError?) -> InstantQueryEmission {
    var emission = self
    emission.error = error
    return emission
  }
}
