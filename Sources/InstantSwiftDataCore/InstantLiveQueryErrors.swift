import Foundation

/// The latest server error of each live query, by registration key, for that query's observers (#360).
///
/// Upstream `Reactor.js` `notifyQueryError` calls every subscriber of a query with `{ error }`, and the subscription
/// stays registered. Swift adds the error to the query's emissions instead: an observer keeps its stream and its
/// last values, sees the error, and sees it clear once the server answers the query again.
actor InstantLiveQueryErrors {
  private var errors: [String: InstantError] = [:]
  private var subscribers: [String: [UUID: AsyncStream<InstantError?>.Continuation]] = [:]

  /// The error updates for `key`, starting with its current error when it has one.
  func updates(for key: String) -> AsyncStream<InstantError?> {
    let (stream, continuation) = AsyncStream<InstantError?>.makeStream(
      bufferingPolicy: .bufferingNewest(1)
    )
    let id = UUID()
    subscribers[key, default: [:]][id] = continuation
    if let error = errors[key] {
      continuation.yield(error)
    }
    continuation.onTermination = { @Sendable [weak self] _ in
      Task { await self?.removeSubscriber(id, for: key) }
    }
    return stream
  }

  /// Records `error` as the query's latest server error (`nil` once the server answers it) and tells its observers.
  func publish(_ error: InstantError?, for key: String) {
    guard errors[key] != error else { return }
    errors[key] = error
    for continuation in subscribers[key, default: [:]].values {
      continuation.yield(error)
    }
  }

  func error(for key: String) -> InstantError? {
    errors[key]
  }

  func observerCountForTesting(for key: String) -> Int {
    subscribers[key]?.count ?? 0
  }

  private func removeSubscriber(_ id: UUID, for key: String) {
    subscribers[key]?[id] = nil
    guard subscribers[key]?.isEmpty == true else { return }
    // Nobody observes the query any more; a later observation starts from the server's next answer.
    subscribers[key] = nil
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

/// One input of the stage that adds a live query's server error to its emissions.
enum InstantLiveQueryErrorReportingEvent: Sendable {
  case emission(InstantQueryEmission)
  case serverError(InstantError?)
  case sourceFinished
}
