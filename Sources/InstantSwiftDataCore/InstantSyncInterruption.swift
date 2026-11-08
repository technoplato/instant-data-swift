import Foundation

// History:
// - 2026-11-07: #2037: created. A connection status said `.errored` with the error as text, so an app could not tell a
//   weak signal from no network, a server that does not answer, a rate limit or a refused sign-in, and showed every one
//   of them as the same failure.

/// Why this device's changes are not reaching Instant now, in terms an app can show (#2037).
///
/// The runtime derives it from what the connection last met and the network path the system reports. A transport that
/// does not open or keep up is a weak network while the path is there and no network while it is not: the socket waits
/// for connectivity, so a device without a network meets the same five-second open deadline as one with a weak signal,
/// and only the path tells them apart. Every cause keeps the queued changes: the outbox is durable, and its writes go
/// out, in order, when the interruption ends.
///
/// ```swift
/// for await status in try await runtime.observeConnectionStatus() {
///   guard let interruption = status.interruption else { continue }  // Changes are reaching Instant.
///   switch interruption.cause {
///   case .weakNetwork: show("Weak connection. Changes sync as soon as it is back.")
///   case .rateLimited: show("Instant is limiting this app until \(interruption.retryAt?.formatted() ?? "later").")
///   default: show(interruption.cause.rawValue)
///   }
/// }
/// ```
public struct InstantSyncInterruption: Hashable, Codable, Sendable {
  /// What stands between this device's changes and Instant.
  public enum Cause: String, Hashable, Codable, Sendable, CaseIterable {
    /// The device has no route to any network: the system's path is unsatisfied, or it said it is not connected.
    case noNetwork
    /// A route is there, but the connection did not open or keep up in time: a weak signal or a network that drops.
    case weakNetwork
    /// The network answers, but Instant's server does not: its host was not found or refused the connection, the
    /// secure connection failed, or the server answered with an error of its own.
    case serverUnreachable
    /// Instant refused this app's requests as too many. ``InstantSyncInterruption/retryAt`` is when it said to try
    /// again, when it said.
    case rateLimited
    /// Instant did not accept this device's sign-in.
    case authentication
    /// Local state needs a repair before this device syncs again (``InstantSynchronizationBlocker``).
    case localRepairNeeded
    /// Anything else; ``InstantSyncInterruption/detail`` says what.
    case other

    /// Whether changes saved during the interruption stay on this device, to be sent when it ends. Every cause keeps
    /// them: none discards a queued write.
    public var keepsQueuedChanges: Bool {
      switch self {
      case .noNetwork, .weakNetwork, .serverUnreachable, .rateLimited, .authentication, .localRepairNeeded, .other:
        true
      }
    }

    /// Whether the interruption ends with no one acting: the runtime keeps trying, and the queued changes go out once
    /// it gets through. A refused sign-in waits for a new one, and a local repair for the app.
    public var endsOnItsOwn: Bool {
      switch self {
      case .noNetwork, .weakNetwork, .serverUnreachable, .rateLimited, .other:
        true
      case .authentication, .localRepairNeeded:
        false
      }
    }
  }

  public var cause: Cause
  /// When the interruption began: the first failure since the connection was last open.
  public var since: Date
  /// When the server said to try again (a rate limit's `retry-at`, or `retry-after` from when it answered), or nil when
  /// it did not say.
  public var retryAt: Date?
  /// The network path in a few words when the status was made: `none`, `cellular expensive`, `wifi`; nil where the
  /// runtime reads no path (a scripted transport, watchOS, a simulator).
  public var networkPath: String?
  /// The failure in the library's words, for a log or a details view.
  public var detail: String

  public init(
    cause: Cause,
    since: Date,
    retryAt: Date? = nil,
    networkPath: String? = nil,
    detail: String
  ) {
    self.cause = cause
    self.since = since
    self.retryAt = retryAt
    self.networkPath = networkPath
    self.detail = detail
  }

  /// Whether changes saved during the interruption stay on this device, to be sent when it ends: always.
  public var keepsQueuedChanges: Bool { cause.keepsQueuedChanges }

  /// Whether the interruption ends with no one acting.
  public var endsOnItsOwn: Bool { cause.endsOnItsOwn }
}

/// A connection failure as the runtime keeps it (#2037): its kind, read from the error alone, when the failures began,
/// and the server's retry time. The network path is read when a status is made, so the cause it becomes follows the
/// path: a path that goes away after the failure turns a weak network into no network.
struct InstantConnectionFailure: Hashable, Codable, Sendable {
  enum Kind: String, Hashable, Codable, Sendable {
    /// The transport did not open or keep up: a timeout, a lost connection, a socket that is not connected.
    case transport
    /// The system said this device has no route to the internet.
    case noNetwork
    case serverUnreachable
    case rateLimited
    case authentication
    case localRepairNeeded
    case other
  }

  var kind: Kind
  var sinceMilliseconds: Int64
  var retryAtMilliseconds: Int64?
  var detail: String

  init(kind: Kind, sinceMilliseconds: Int64, retryAtMilliseconds: Int64? = nil, detail: String) {
    self.kind = kind
    self.sinceMilliseconds = sinceMilliseconds
    self.retryAtMilliseconds = retryAtMilliseconds
    self.detail = detail
  }

  /// The failure `error` is, met at `nowMilliseconds`.
  init(classifying error: any Error, atMilliseconds nowMilliseconds: Int64) {
    self.init(kind: .other, sinceMilliseconds: nowMilliseconds, detail: String(describing: error))
  }

  /// This failure, kept as the start of an interruption that `earlier` began: the newest kind and retry time, the
  /// earliest start.
  func continuing(_ earlier: Self?) -> Self {
    self
  }
}

extension InstantSyncInterruption {
  /// The interruption `failure` means while the network path is `path` (nil: the runtime reads none): pure.
  init(failure: InstantConnectionFailure, path: InstantNetworkPathState?) {
    self.init(
      cause: .other,
      since: Date(timeIntervalSince1970: Double(failure.sinceMilliseconds) / 1_000),
      detail: failure.detail
    )
  }
}
