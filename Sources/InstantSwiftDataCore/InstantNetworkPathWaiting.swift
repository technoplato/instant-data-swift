// Waiting for the network path from outside the live connection (#1012).
//
// History:
// - 2026-10-23: first version (#1012). Progressive media's uploader makes no attempt while the device has no route to
//   the network, the same rule the socket's reconnect follows (#669, `Reactor.js` `_scheduleReconnect`).

import Foundation

extension InstantNetworkPath {
  /// Returns once this path has a route to the network; at once when it has one, or when it is always there.
  ///
  /// ```swift
  /// try await InstantNetworkPath.system.waitUntilSatisfied()
  /// ```
  ///
  /// Throws `CancellationError` when the waiting task is cancelled.
  public func waitUntilSatisfied() async throws {
    try await monitor?.waitUntilSatisfied()
  }
}
