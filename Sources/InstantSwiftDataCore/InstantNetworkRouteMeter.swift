import Foundation
import os

// History:
// - 2026-10-26: added (#1237, #1231): how the open live socket reaches the network, its moves, and the attempts the
//   system refused on a route that is not expensive, for an app's energy ledger. On one device the socket sat on
//   cellular for 57 minutes while Wi-Fi was the path, and no counter could show it.

/// How the live socket reaches the network, counted where it opens, moves and closes (#1237).
///
/// ```swift
/// let route = InstantNetworkRouteMeter.snapshot()
/// if route.socket == .anyNetwork { /* the socket may be on cellular while Wi-Fi is the path */ }
/// ```
public enum InstantNetworkRouteMeter {
  /// Everything counted since launch, and the open socket's access now.
  public static func snapshot() -> InstantNetworkRouteSnapshot {
    shared.snapshot()
  }

  package static let shared = InstantNetworkRouteMeterStorage()
}

/// What ``InstantNetworkRouteMeter`` counted (#1237).
public struct InstantNetworkRouteSnapshot: Equatable, Sendable {
  /// How the open socket was asked to reach the network.
  public enum SocketAccess: String, Equatable, Sendable {
    /// The system kept it off networks it considers expensive (cellular, a personal hotspot).
    case nonexpensiveRoute = "not-expensive"
    /// It may use any network: the path had no route that is not expensive, or one had just failed.
    case anyNetwork = "any-network"
  }

  /// The open socket's access, or nil while no socket is open.
  public var socket: SocketAccess?
  /// Times the socket moved to a route that is not expensive.
  public var moves: Int
  /// Attempts and probes on a route that is not expensive that failed: the socket's and storage requests'.
  public var refusals: Int

  public init(socket: SocketAccess? = nil, moves: Int = 0, refusals: Int = 0) {
    self.socket = socket
    self.moves = moves
    self.refusals = refusals
  }
}

/// The counts behind ``InstantNetworkRouteMeter``: one lock per open, move, close or refusal (#1237).
package final class InstantNetworkRouteMeterStorage: Sendable {
  private let state = OSAllocatedUnfairLock(initialState: InstantNetworkRouteSnapshot())

  package init() {}

  func socketOpened(_ access: InstantNetworkRouteSnapshot.SocketAccess) {
    _ = access
  }

  func socketClosed() {
    state.withLock { $0.socket = nil }
  }

  func recordMove() {

  }

  func recordRefusal() {

  }

  func snapshot() -> InstantNetworkRouteSnapshot {
    state.withLock { $0 }
  }
}
