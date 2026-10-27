import Foundation
import os

#if canImport(Network) && !os(watchOS) && !targetEnvironment(simulator)
  import Network
#endif

// History:
// - 2026-10-11: #669: the reconnect loop waits for a missing path, as upstream's `NetworkListener` makes it.
// - 2026-10-26: #1237, #1231: the path keeps its cost and a generation, and a route preference: connections ask for a
//   route that is not expensive while the path has one. On one device Wi-Fi Assist moved the live socket's reconnect and
//   the storage connection to cellular for 57 minutes while Wi-Fi stayed the primary interface; the path never changed,
//   so nothing that watched it could move them back.

/// Whether this device has a route to the network, as the live connection's reconnect loop sees it (#669).
///
/// Upstream `Reactor.js` takes a `NetworkListener` (`WindowNetworkListener` in a browser): `_scheduleReconnect` skips its
/// attempt while `_isOnline` is false, and the listener starts the socket as soon as the network returns. A transport
/// carries its path in ``InstantLiveTransportClient/networkPath``: ``InstantLiveTransportClient/live`` uses ``system``,
/// and every other transport uses ``alwaysSatisfied`` unless it sets one.
///
/// The system path also says whether a route that is not expensive is there (Wi-Fi or wired), and the live socket and
/// the live storage client ask the system for one whenever it is (#1237, #1231), as Apple's "Reducing networking and
/// Bluetooth power usage" asks: "To prevent network tasks from using an expensive network, set
/// allowsExpensiveNetworkAccess to false."
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

  /// Whether a route that is not expensive answers now: a connection to `host`:`port` that prohibits expensive paths
  /// becomes ready within five seconds (#1237).
  typealias Probe = @Sendable (_ host: String, _ port: Int) async -> Bool

  let source: Source
  private let testProbe: Probe?

  init(_ source: Source) {
    self.source = source
    self.testProbe = nil
  }

  init(monitor: InstantNetworkPathMonitor, probe: Probe? = nil) {
    self.source = .monitor(monitor)
    self.testProbe = probe
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

  /// How this path checks for a route that is not expensive, or nil where it cannot: a scripted path without one.
  var probe: Probe? {
    switch source {
    case .alwaysSatisfied:
      return nil
    case .system:
      #if canImport(Network) && !os(watchOS) && !targetEnvironment(simulator)
        return { host, port in await InstantSystemNetworkPath.probeNonexpensiveRoute(host: host, port: port) }
      #else
        return nil
      #endif
    case .monitor:
      return testProbe
    }
  }
}

/// A network path's answer in the library's words (#669, #1237).
struct InstantNetworkPathState: Equatable, Sendable {
  enum Interface: String, Sendable {
    case wifi
    case cellular
    case wired
    case other
    case none
  }

  var isSatisfied: Bool
  /// Cellular or a personal hotspot, as the system marks them.
  var isExpensive: Bool
  /// Low Data Mode.
  var isConstrained: Bool
  /// The interface the path uses first.
  var interface: Interface

  init(isSatisfied: Bool, isExpensive: Bool = false, isConstrained: Bool = false, interface: Interface? = nil) {
    self.isSatisfied = isSatisfied
    self.isExpensive = isExpensive
    self.isConstrained = isConstrained
    self.interface = interface ?? (isSatisfied ? .other : .none)
  }

  /// A route that is not expensive is there: Wi-Fi or wired, satisfied.
  var hasNonexpensiveRoute: Bool { isSatisfied && !isExpensive }

  /// The path in a few words, for a log line: `wifi`, `cellular expensive`, `none`.
  var logDescription: String {
    guard isSatisfied else { return "none" }
    var words = [interface.rawValue]
    if isExpensive { words.append("expensive") }
    if isConstrained { words.append("constrained") }
    return words.joined(separator: " ")
  }
}

/// Whether new connections ask the system for a route that is not expensive (#1237, #1231): pure.
///
/// They ask while the path has one, unless such an attempt failed on the same path within its backoff: one minute, then
/// twice as long after each further failure, up to 32 minutes, as Apple's "Reducing networking and Bluetooth power usage"
/// backs off retries "to prevent energy-draining retry loops". An attempt that succeeds resets it. An attempt that fails
/// is followed at once by one on any network, so a device whose only working route is cellular still connects.
struct InstantRoutePreference: Equatable, Sendable {
  static let firstBackoff: Duration = .seconds(60)
  static let longestBackoff: Duration = .seconds(32 * 60)

  struct Refusal: Equatable, Sendable {
    /// The path's generation when the attempt failed.
    var generation: UInt64
    /// When the next attempt may ask again on that path.
    var endsAt: ContinuousClock.Instant
  }

  private(set) var refusal: Refusal?
  /// The wait the next refusal gets.
  private(set) var backoff: Duration = firstBackoff

  func asksForNonexpensiveRoute(
    on path: InstantNetworkPathState,
    generation: UInt64,
    now: ContinuousClock.Instant
  ) -> Bool {
    guard path.hasNonexpensiveRoute else { return false }
    guard let refusal, refusal.generation == generation else { return true }
    return now >= refusal.endsAt
  }

  mutating func refused(generation: UInt64, now: ContinuousClock.Instant) {
    refusal = Refusal(generation: generation, endsAt: now + backoff)
    backoff = min(backoff * 2, Self.longestBackoff)
  }

  /// Returns whether the success ended a refusal: a route that is not expensive works again.
  mutating func succeeded() -> Bool {
    defer {
      refusal = nil
      backoff = Self.firstBackoff
    }
    return refusal != nil
  }
}

/// Where a path stood when a connection opened (#1237): its answer, its generation, and how many times a route that is
/// not expensive came back after a failure.
struct InstantNetworkRouteMark: Equatable, Sendable {
  var path: InstantNetworkPathState
  var generation: UInt64
  var recoveries: UInt64
}

/// The newest answer of a network path that can change, and the reconnects waiting for it to come back (#669).
///
/// It also keeps the path's cost and a generation that changes with it, the route preference, and waiters for a change
/// of either (#1237). The lock guards one small state value for one transition, never a call out; continuations resume
/// after it is released.
final class InstantNetworkPathMonitor: Sendable {
  private enum Counter: Sendable {
    /// How many times the path went from missing to there.
    case returns
    /// How many times the path's answer changed or a route that is not expensive came back after a failure.
    case routeChanges
  }

  private enum Waiter {
    case pending
    case registered(Counter, after: UInt64, CheckedContinuation<Void, any Error>)
    case cancelled
  }

  private struct State {
    var path: InstantNetworkPathState
    var generation: UInt64 = 0
    var returnCount: UInt64 = 0
    var routeChangeCount: UInt64 = 0
    var recoveries: UInt64 = 0
    var preference = InstantRoutePreference()
    var waiters: [UInt64: Waiter] = [:]
    var nextWaiterID: UInt64 = 0

    func count(_ counter: Counter) -> UInt64 {
      switch counter {
      case .returns: returnCount
      case .routeChanges: routeChangeCount
      }
    }

    mutating func wakeWaiters() -> [CheckedContinuation<Void, any Error>] {
      var woken: [CheckedContinuation<Void, any Error>] = []
      for (id, waiter) in waiters {
        guard case let .registered(counter, after, continuation) = waiter, count(counter) > after else { continue }
        waiters[id] = nil
        woken.append(continuation)
      }
      return woken
    }
  }

  private let state: OSAllocatedUnfairLock<State>

  init(isSatisfied: Bool) {
    state = OSAllocatedUnfairLock(initialState: State(path: InstantNetworkPathState(isSatisfied: isSatisfied)))
  }

  init(path: InstantNetworkPathState) {
    state = OSAllocatedUnfairLock(initialState: State(path: path))
  }

  /// Whether the path is there now.
  var isSatisfied: Bool {
    state.withLock { $0.path.isSatisfied }
  }

  /// The path's answer and how many times it has come back, read together.
  var snapshot: (isSatisfied: Bool, returnCount: UInt64) {
    state.withLock { ($0.path.isSatisfied, $0.returnCount) }
  }

  /// The path now, its generation, and its recoveries, read together (#1237).
  var routeMark: InstantNetworkRouteMark {
    state.withLock { InstantNetworkRouteMark(path: $0.path, generation: $0.generation, recoveries: $0.recoveries) }
  }

  /// How many times the path's answer changed or a route that is not expensive came back (#1237).
  var routeChangeCount: UInt64 {
    state.withLock { $0.routeChangeCount }
  }

  /// When the route preference's backoff ends, or nil when no attempt failed since the last success (#1237).
  var refusalEndsAt: ContinuousClock.Instant? {
    state.withLock { $0.preference.refusal?.endsAt }
  }

  /// Records the path's newest answer. A change from missing to there wakes every waiter.
  func update(isSatisfied: Bool) {
    update { path in
      path.isSatisfied = isSatisfied
      if !isSatisfied {
        path.interface = .none
      } else if path.interface == .none {
        path.interface = .other
      }
    }
  }

  /// Records the path's newest answer with its cost (#1237). Returns whether it changed.
  @discardableResult
  func update(_ newPath: InstantNetworkPathState) -> Bool {
    update { $0 = newPath }
  }

  @discardableResult
  private func update(_ change: @Sendable (inout InstantNetworkPathState) -> Void) -> Bool {
    let (changed, woken): (Bool, [CheckedContinuation<Void, any Error>]) = state.withLock { state in
      var path = state.path
      change(&path)
      guard path != state.path else { return (false, []) }
      let returned = !state.path.isSatisfied && path.isSatisfied
      state.path = path
      state.generation &+= 1
      state.routeChangeCount &+= 1
      if returned { state.returnCount &+= 1 }
      return (true, state.wakeWaiters())
    }
    for continuation in woken {
      continuation.resume()
    }
    return changed
  }

  /// Whether a new connection should ask for a route that is not expensive now (#1237).
  func asksForNonexpensiveRoute(now: ContinuousClock.Instant = .now) -> Bool {
    state.withLock { $0.preference.asksForNonexpensiveRoute(on: $0.path, generation: $0.generation, now: now) }
  }

  /// An attempt that asked for a route that is not expensive failed: the next ones may use any network on this path
  /// until the backoff ends (#1237).
  func recordNonexpensiveRouteRefused(now: ContinuousClock.Instant = .now) {
    state.withLock { $0.preference.refused(generation: $0.generation, now: now) }
  }

  /// An attempt that asked for a route that is not expensive went through. After a failure, that is a recovery: it
  /// wakes the sockets waiting for one (#1237).
  func recordNonexpensiveRouteSucceeded() {
    let woken: [CheckedContinuation<Void, any Error>] = state.withLock { state in
      guard state.preference.succeeded() else { return [] }
      state.recoveries &+= 1
      state.routeChangeCount &+= 1
      return state.wakeWaiters()
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
    try await wait(for: .returns, after: returnCount)
  }

  /// Returns once the path's answer changed, or a route that is not expensive came back, more than `routeChangeCount`
  /// times (#1237). Throws `CancellationError` when cancelled.
  func waitForRouteChange(after routeChangeCount: UInt64) async throws {
    try await wait(for: .routeChanges, after: routeChangeCount)
  }

  private func wait(for counter: Counter, after mark: UInt64) async throws {
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
          if state.count(counter) > mark {
            state.waiters[id] = nil
            return .success(())
          }
          state.waiters[id] = .registered(counter, after: mark, continuation)
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
        case let .registered(_, _, continuation):
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
        if case .registered(.returns, _, _) = $0 { return true }
        return false
      }.count
    }
  }
}

#if canImport(Network) && !os(watchOS) && !targetEnvironment(simulator)
  /// The one `NWPathMonitor` behind ``InstantNetworkPath/system``.
  // SAFETY: `pathMonitor` is configured and started in `init` and never mutated afterwards; the system calls its
  // handler on `queue`, a serial dispatch queue that is its only executor, and the handler only writes `monitor`, which
  // keeps its state behind its own lock.
  private final class InstantSystemNetworkPath: @unchecked Sendable {
    static let shared = InstantSystemNetworkPath()

    let monitor = InstantNetworkPathMonitor(isSatisfied: true)
    private let pathMonitor = NWPathMonitor()

    private init() {
      let monitor = monitor
      pathMonitor.pathUpdateHandler = { path in
        let previous = monitor.routeMark.path
        let state = InstantNetworkPathState(path)
        // #1237: no line said when the path changed, so a device's log could not tell a path change from Wi-Fi
        // Assist. The system reports many updates that change none of these fields; they log nothing.
        guard monitor.update(state) else { return }
        InstantDiagnostics.shared.record(
          .notice,
          subsystem: "instant-swift-data-core",
          category: "network",
          event: "network.path-changed",
          message: "The network path is now \(state.logDescription) (was \(previous.logDescription)).",
          metadata: [
            "path": state.logDescription,
            "previousPath": previous.logDescription,
            "interfaces": path.availableInterfaces.map(\.name).joined(separator: ","),
          ]
        )
      }
      pathMonitor.start(queue: DispatchQueue(label: "instant-swift-data.network-path", qos: .utility))
    }

    /// One TCP connection to `host`:`port` that prohibits expensive paths: true once it is ready, false when it waits,
    /// fails or is not ready within five seconds; it is cancelled either way, so it costs one handshake (#1237).
    static func probeNonexpensiveRoute(host: String, port: Int) async -> Bool {
      guard let endpointPort = NWEndpoint.Port(rawValue: UInt16(clamping: port)) else { return false }
      let parameters = NWParameters.tcp
      parameters.prohibitExpensivePaths = true
      let connection = NWConnection(host: NWEndpoint.Host(host), port: endpointPort, using: parameters)
      defer { connection.cancel() }
      let answer = InstantProbeAnswer()
      return await withTaskCancellationHandler {
        await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
          answer.install(continuation)
          connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
              answer.finish(true)
            case .waiting, .failed, .cancelled:
              answer.finish(false)
            case .setup, .preparing:
              break
            @unknown default:
              break
            }
          }
          connection.start(queue: DispatchQueue(label: "instant-swift-data.route-probe", qos: .utility))
          DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + .milliseconds(5_000)) {
            answer.finish(false)
          }
        }
      } onCancel: {
        answer.finish(false)
      }
    }
  }

  extension InstantNetworkPathState {
    init(_ path: NWPath) {
      let interface: Interface =
        if path.status == .unsatisfied {
          .none
        } else if path.usesInterfaceType(.wifi) {
          .wifi
        } else if path.usesInterfaceType(.cellular) {
          .cellular
        } else if path.usesInterfaceType(.wiredEthernet) {
          .wired
        } else {
          .other
        }
      self.init(
        isSatisfied: path.status != .unsatisfied,
        isExpensive: path.isExpensive,
        isConstrained: path.isConstrained,
        interface: interface
      )
    }
  }

  /// The probe's one answer: the first of ready, a failure, the deadline, or cancellation.
  // SAFETY: `lock` guards the continuation and the answer; each is taken once.
  private final class InstantProbeAnswer: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Bool, Never>?
    private var answer: Bool?

    func install(_ continuation: CheckedContinuation<Bool, Never>) {
      let ready: Bool? = lock.withLock {
        if let answer { return answer }
        self.continuation = continuation
        return nil
      }
      if let ready { continuation.resume(returning: ready) }
    }

    func finish(_ value: Bool) {
      let continuation: CheckedContinuation<Bool, Never>? = lock.withLock {
        guard answer == nil else { return nil }
        answer = value
        defer { self.continuation = nil }
        return self.continuation
      }
      continuation?.resume(returning: value)
    }
  }

#endif
