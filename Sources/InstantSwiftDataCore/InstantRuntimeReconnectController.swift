import Foundation

/// The live connection's scheduled reconnect: one task that waits out a backoff, then attempts (#296, #669).
///
/// Upstream `Reactor.js` `_scheduleReconnect` waits `_reconnectTimeoutMs`, then grows it by a second up to ten
/// (`Math.min(this._reconnectTimeoutMs + 1000, 10000)`), skips the attempt while `_isOnline` is false, and starts the
/// socket otherwise; `init-ok` resets the delay to zero, and so does a user change. Its `NetworkListener` starts the
/// socket as soon as the network returns.
///
/// The delay lives here, on the controller, as upstream keeps it on the reactor (#669). A local of `run()` restarted at
/// zero whenever a run ended without `init-ok`: an explicit connect that cancelled the run, for one. The runtime calls
/// ``recordSessionOpened()`` when a session reaches `init-ok`, and ``resetBackoff()`` when the user changes.
///
/// While the transport's ``InstantNetworkPath`` is missing the controller makes no attempt; it waits, still owning the
/// next connection, and attempts at once when the path returns, including during a backoff. Before, every attempt ran
/// regardless: a device without a network spent each one creating a socket that waited out the five-second open
/// deadline, once every 15 s. Upstream's listener also replaces a socket that is still open when the network returns;
/// Swift leaves an open socket to its receive loop, which fails when the route it used goes away, so no listener runs
/// while the connection is up.
actor InstantRuntimeReconnectController {
  /// Upstream's step and cap for `_reconnectTimeoutMs`.
  static let delayStepMilliseconds: UInt64 = 1_000
  static let maximumDelayMilliseconds: UInt64 = 10_000

  private let taskOwner = InstantRuntimeExactTaskOwner()
  private var lifecycleGeneration = 0
  private var acceptsStarts = true
  /// The wait before the next scheduled attempt: upstream's `_reconnectTimeoutMs`.
  private(set) var nextDelayMilliseconds: UInt64 = 0
  /// The scheduled attempt waits for the network path to come back.
  private(set) var isWaitingForNetwork = false

  func start(
    appID: String,
    sleep: @escaping @Sendable (UInt64) async throws -> Void,
    networkPath: InstantNetworkPath,
    reconnect: @escaping @Sendable () async throws -> Void
  ) {
    guard acceptsStarts else { return }
    _ = taskOwner.start(restartIfRunning: true) { [weak self] in
      await self?.run(appID: appID, sleep: sleep, networkPath: networkPath, reconnect: reconnect)
    }
  }

  /// A session reached `init-ok`: the next scheduled reconnect waits zero, as upstream's `init-ok` handler resets
  /// `_reconnectTimeoutMs`.
  func recordSessionOpened() {
    nextDelayMilliseconds = 0
  }

  /// The signed-in user changed: upstream's `updateUser`, run by `changeCurrentUser`, resets `_reconnectTimeoutMs`
  /// before it closes the socket.
  func resetBackoff() {
    nextDelayMilliseconds = 0
  }

  func cancelAndWait() async {
    lifecycleGeneration += 1
    let lifecycleGeneration = lifecycleGeneration
    acceptsStarts = false
    let handle = taskOwner.requestStop()
    await handle.wait()
    guard lifecycleGeneration == self.lifecycleGeneration else { return }
    taskOwner.resume()
    acceptsStarts = true
  }

  func requestStop() -> InstantRuntimeExactTaskOwner.Handle {
    lifecycleGeneration += 1
    acceptsStarts = false
    return taskOwner.requestStop()
  }

  func isIdleForTesting() -> Bool {
    taskOwner.isIdle
  }

  /// A reconnect is waiting out its backoff, waiting for the network, or connecting, so it owns the next connection
  /// (#296).
  var ownsNextConnection: Bool {
    !taskOwner.isIdle
  }

  private func run(
    appID: String,
    sleep: @escaping @Sendable (UInt64) async throws -> Void,
    networkPath: InstantNetworkPath,
    reconnect: @escaping @Sendable () async throws -> Void
  ) async {
    let monitor = networkPath.monitor
    while !Task.isCancelled {
      do {
        try await waitOutBackoff(sleep: sleep, monitor: monitor)
        // Upstream grows the delay when its timer fires, before it checks `_isOnline`.
        nextDelayMilliseconds = min(
          nextDelayMilliseconds + Self.delayStepMilliseconds,
          Self.maximumDelayMilliseconds
        )
        if let monitor {
          try await waitForNetwork(monitor, appID: appID)
        }
        try Task.checkCancellation()
        InstantEnergyMeter.record(.reconnectAttempt)
        try await reconnect()
        return
      } catch is CancellationError {
        return
      } catch {
        continue
      }
    }
  }

  /// Waits out the current delay. A path that comes back meanwhile ends the wait, as upstream's listener starts the
  /// socket on the change to online without waiting for the pending timer.
  private func waitOutBackoff(
    sleep: @escaping @Sendable (UInt64) async throws -> Void,
    monitor: InstantNetworkPathMonitor?
  ) async throws {
    let delay = nextDelayMilliseconds
    guard let monitor, delay > 0 else {
      try await sleep(delay)
      return
    }
    let returnsBefore = monitor.snapshot.returnCount
    try await withThrowingTaskGroup(of: Void.self) { group in
      group.addTask { try await sleep(delay) }
      group.addTask { try await monitor.waitForReturn(after: returnsBefore) }
      defer { group.cancelAll() }
      _ = try await group.next()
    }
  }

  /// Makes no attempt while the path is missing; returns when it comes back.
  private func waitForNetwork(_ monitor: InstantNetworkPathMonitor, appID: String) async throws {
    guard !monitor.isSatisfied else { return }
    isWaitingForNetwork = true
    defer { isWaitingForNetwork = false }
    InstantDiagnostics.shared.record(
      .info,
      subsystem: "instant-swift-data-core",
      category: "connection",
      event: "connection.reconnect-waiting-for-network",
      message: "The scheduled reconnect waits for the network path to come back.",
      metadata: [
        "appID": appID,
        "nextDelayMilliseconds": String(nextDelayMilliseconds),
      ]
    )
    try await monitor.waitUntilSatisfied()
    InstantDiagnostics.shared.record(
      .info,
      subsystem: "instant-swift-data-core",
      category: "connection",
      event: "connection.network-returned",
      message: "The network path came back; the scheduled reconnect attempts now.",
      metadata: ["appID": appID]
    )
  }
}
