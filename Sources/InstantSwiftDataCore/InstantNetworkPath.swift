import Foundation
import os

#if canImport(Network) && !os(watchOS) && !targetEnvironment(simulator)
  import Network
#endif

/// Whether this device has a route to the network, as the live connection's reconnect loop sees it (#669).
///
/// Upstream `Reactor.js` takes a `NetworkListener` (`WindowNetworkListener` in a browser): `_scheduleReconnect` skips its
/// attempt while `_isOnline` is false, and the listener starts the socket as soon as the network returns. A transport
/// carries its path in ``InstantLiveTransportClient/networkPath``: ``InstantLiveTransportClient/live`` uses ``system``,
/// and every other transport uses ``alwaysSatisfied`` unless it sets one.
///
/// ```swift
/// var transport = InstantLiveTransportClient.connectionAttempts(makeAttempt)
/// transport.networkPath = .system
/// ```
public struct InstantNetworkPath: Sendable {
  enum Source: Sendable {
    case alwaysSatisfied
    case system
    case monitor(InstantNetworkPathMonitor)
  }

  let source: Source

  init(_ source: Source) {
    self.source = source
  }

  init(monitor: InstantNetworkPathMonitor) {
    self.source = .monitor(monitor)
  }

  /// A path that is always there: an in-process or scripted transport, which needs no network.
  public static let alwaysSatisfied = Self(.alwaysSatisfied)

  /// The system's path, from one `NWPathMonitor` that starts the first time a reconnect reads it.
  ///
  /// A path the system reports as `requiresConnection` (a VPN on demand, for one) counts as there: an attempt can bring
  /// it up. watchOS and the simulators use ``alwaysSatisfied``, because a path that wrongly reads as missing would stop
  /// every reconnect: an app's requests on a Watch usually travel through the paired iPhone, which a path monitor on the
  /// Watch may not describe (TN3135), and a simulator's monitor can keep a stale answer after the host's network
  /// changes.
  public static let system = Self(.system)

  /// The monitor that answers for this path, or nil when the path is always there.
  var monitor: InstantNetworkPathMonitor? {
    switch source {
    case .alwaysSatisfied:
      return nil
    case .system:
      #if canImport(Network) && !os(watchOS) && !targetEnvironment(simulator)
        return InstantSystemNetworkPath.shared.monitor
      #else
        return nil
      #endif
    case let .monitor(monitor):
      return monitor
    }
  }
}

/// The newest answer of a network path that can change, and the reconnects waiting for it to come back (#669).
///
/// The lock guards one small state value for one transition, never a call out; continuations resume after it is
/// released.
final class InstantNetworkPathMonitor: Sendable {
  private enum Waiter {
    case pending
    case registered(after: UInt64, CheckedContinuation<Void, any Error>)
    case cancelled
  }

  private struct State {
    var isSatisfied: Bool
    /// How many times the path went from missing to there.
    var returnCount: UInt64 = 0
    var waiters: [UInt64: Waiter] = [:]
    var nextWaiterID: UInt64 = 0
  }

  private let state: OSAllocatedUnfairLock<State>

  init(isSatisfied: Bool) {
    state = OSAllocatedUnfairLock(initialState: State(isSatisfied: isSatisfied))
  }

  /// Whether the path is there now.
  var isSatisfied: Bool {
    state.withLock { $0.isSatisfied }
  }

  /// The path's answer and how many times it has come back, read together.
  var snapshot: (isSatisfied: Bool, returnCount: UInt64) {
    state.withLock { ($0.isSatisfied, $0.returnCount) }
  }

  /// Records the path's newest answer. A change from missing to there wakes every waiter.
  func update(isSatisfied: Bool) {
    let woken: [CheckedContinuation<Void, any Error>] = state.withLock { state in
      guard state.isSatisfied != isSatisfied else { return [] }
      state.isSatisfied = isSatisfied
      guard isSatisfied else { return [] }
      state.returnCount &+= 1
      var woken: [CheckedContinuation<Void, any Error>] = []
      for (id, waiter) in state.waiters {
        guard case let .registered(after, continuation) = waiter, state.returnCount > after else { continue }
        state.waiters[id] = nil
        woken.append(continuation)
      }
      return woken
    }
    for continuation in woken {
      continuation.resume()
    }
  }

  /// Returns once the path is there; at once when it already is.
  func waitUntilSatisfied() async throws {
    let current = snapshot
    guard !current.isSatisfied else { return }
    try await waitForReturn(after: current.returnCount)
  }

  /// Returns once the path has come back more than `returnCount` times. Throws `CancellationError` when cancelled.
  func waitForReturn(after returnCount: UInt64) async throws {
    let id = state.withLock { state -> UInt64 in
      state.nextWaiterID &+= 1
      state.waiters[state.nextWaiterID] = .pending
      return state.nextWaiterID
    }
    try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
        let outcome: Result<Void, any Error>? = state.withLock { state in
          guard case .pending = state.waiters[id] else {
            state.waiters[id] = nil
            return .failure(CancellationError())
          }
          if state.returnCount > returnCount {
            state.waiters[id] = nil
            return .success(())
          }
          state.waiters[id] = .registered(after: returnCount, continuation)
          return nil
        }
        if let outcome {
          continuation.resume(with: outcome)
        }
      }
    } onCancel: {
      let continuation: CheckedContinuation<Void, any Error>? = state.withLock { state in
        switch state.waiters[id] {
        case .pending:
          state.waiters[id] = .cancelled
          return nil
        case let .registered(_, continuation):
          state.waiters[id] = nil
          return continuation
        case .cancelled, nil:
          return nil
        }
      }
      continuation?.resume(throwing: CancellationError())
    }
  }

  /// How many reconnects wait for the path to come back.
  var waiterCount: Int {
    state.withLock { state in
      state.waiters.values.filter {
        if case .registered = $0 { return true }
        return false
      }.count
    }
  }
}

#if canImport(Network) && !os(watchOS) && !targetEnvironment(simulator)
  /// The one `NWPathMonitor` behind ``InstantNetworkPath/system``.
  // SAFETY: `pathMonitor` is configured and started in `init` and never mutated afterwards; the system calls its
  // handler on `queue`, and the handler only writes `monitor`, which is `Sendable`.
  private final class InstantSystemNetworkPath: @unchecked Sendable {
    static let shared = InstantSystemNetworkPath()

    let monitor = InstantNetworkPathMonitor(isSatisfied: true)
    private let pathMonitor = NWPathMonitor()

    private init() {
      let monitor = monitor
      pathMonitor.pathUpdateHandler = { path in
        monitor.update(isSatisfied: path.status != .unsatisfied)
      }
      pathMonitor.start(queue: DispatchQueue(label: "instant-swift-data.network-path", qos: .utility))
    }
  }
#endif
