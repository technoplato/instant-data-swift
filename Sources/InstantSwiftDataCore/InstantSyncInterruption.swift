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

  /// The failure `error` is, met at `nowMilliseconds`: pure.
  ///
  /// A server's answer decides first (its status and type), then the error's own kind. The socket waits for
  /// connectivity, so a device without a network fails as a transport timeout too; the path tells them apart later,
  /// when a status is made.
  init(classifying error: any Error, atMilliseconds nowMilliseconds: Int64) {
    switch error {
    case let error as InstantError:
      let kind = Self.kind(of: error)
      self.init(
        kind: kind,
        sinceMilliseconds: nowMilliseconds,
        retryAtMilliseconds: kind == .rateLimited
          ? Self.retryAtMilliseconds(hint: error.serverHint, nowMilliseconds: nowMilliseconds) : nil,
        detail: error.description
      )
    case let error as URLError:
      self.init(kind: Self.kind(of: error.code), sinceMilliseconds: nowMilliseconds, detail: String(describing: error))
    default:
      let error = error as NSError
      let kind: Kind =
        if error.domain == NSPOSIXErrorDomain {
          // ECONNREFUSED: a host answered and refused. Any other socket error is the link: not connected, reset, timed
          // out, aborted, unreachable.
          error.code == 61 ? .serverUnreachable : .transport
        } else {
          .other
        }
      self.init(kind: kind, sinceMilliseconds: nowMilliseconds, detail: String(describing: error))
    }
  }

  /// The failure as the runtime stores it beside the connection's last error.
  var storedJSON: String? {
    (try? JSONEncoder().encode(self)).flatMap { String(data: $0, encoding: .utf8) }
  }

  /// A failure the runtime stored, or nil for one it cannot read.
  init?(storedJSON: String) {
    guard let failure = try? JSONDecoder().decode(Self.self, from: Data(storedJSON.utf8)) else { return nil }
    self = failure
  }

  /// The failure a server's rate-limit answer on the socket is (#2037): `type` `rate-limited` with its retry time.
  init(rateLimitedBy error: InstantLiveErrorMessage, atMilliseconds nowMilliseconds: Int64) {
    self.init(
      kind: .rateLimited,
      sinceMilliseconds: nowMilliseconds,
      retryAtMilliseconds: Self.retryAtMilliseconds(hint: error.hint, nowMilliseconds: nowMilliseconds),
      detail: error.message
    )
  }

  /// This failure, kept as the start of an interruption that `earlier` began: the newest kind and retry time, the
  /// earliest start.
  func continuing(_ earlier: Self?) -> Self {
    guard let earlier else { return self }
    var kept = self
    kept.sinceMilliseconds = min(earlier.sinceMilliseconds, sinceMilliseconds)
    return kept
  }

  /// Whether a server's answer is a rate limit: type `rate-limited` (status 400 over the socket, 429 over HTTP), or a
  /// 429 that is not the server's `timeout` (a query or transaction that took too long, which upstream also sends as a
  /// 429 over HTTP).
  static func isRateLimit(status: Int?, type: String?) -> Bool {
    let type = type?.lowercased()
    return type == "rate-limited" || (status == 429 && type != "timeout")
  }

  private static func kind(of error: InstantError) -> Kind {
    if error.serverStatus != nil || error.serverType != nil {
      let type = error.serverType?.lowercased()
      if isRateLimit(status: error.serverStatus, type: type) { return .rateLimited }
      if error.serverStatus == 401 { return .authentication }
      if let status = error.serverStatus, (500...599).contains(status) { return .serverUnreachable }
      if type == "timeout" || type == "operation-timed-out" { return .serverUnreachable }
      return .other
    }
    switch error.code {
    case .networkFailed:
      return .transport
    case .authFailed:
      return .authentication
    case .persistenceFailed where error.localMutationDisposition == .retainedUnknown:
      return .localRepairNeeded
    case .persistenceFailed, .validationFailed, .permissionRejected, .decodeFailed, .implementationFailed:
      return .other
    }
  }

  private static func kind(of code: URLError.Code) -> Kind {
    switch code {
    case .notConnectedToInternet, .dataNotAllowed, .internationalRoamingOff, .callIsActive:
      .noNetwork
    case .timedOut, .networkConnectionLost:
      .transport
    case .cannotFindHost, .dnsLookupFailed, .cannotConnectToHost, .secureConnectionFailed, .serverCertificateUntrusted,
      .serverCertificateHasBadDate, .serverCertificateHasUnknownRoot, .serverCertificateNotYetValid,
      .clientCertificateRejected, .clientCertificateRequired, .badServerResponse, .zeroByteResource,
      .cannotParseResponse:
      .serverUnreachable
    case .userAuthenticationRequired:
      .authentication
    default:
      .other
    }
  }

  /// When a rate limit's hint says to try again: `retry-at` (ISO 8601, as upstream writes a `java.time.Instant`, with or
  /// without a fraction of a second), else `retry-after` seconds from `nowMilliseconds`.
  static func retryAtMilliseconds(hint: InstantLiveJSONValue?, nowMilliseconds: Int64) -> Int64? {
    guard let hint = hint?.objectValue else { return nil }
    if let text = hint["retry-at"]?.stringValue, let date = Self.instant(text) {
      return Int64((date.timeIntervalSince1970 * 1_000).rounded())
    }
    if case let .number(seconds)? = hint["retry-after"], seconds.isFinite, seconds >= 0 {
      return nowMilliseconds + Int64((seconds * 1_000).rounded())
    }
    return nil
  }

  /// An ISO 8601 instant with an optional fraction of any length: `2026-11-08T03:42:00Z`, `2026-11-08T03:42:00.123456Z`.
  private static func instant(_ text: String) -> Date? {
    guard let dot = text.firstIndex(of: ".") else { return try? Date(text, strategy: .iso8601) }
    let digits = text[text.index(after: dot)...].prefix(while: \.isNumber)
    guard !digits.isEmpty, let whole = try? Date(String(text[..<dot]) + text[digits.endIndex...], strategy: .iso8601)
    else { return nil }
    return whole.addingTimeInterval(Double("0." + digits) ?? 0)
  }
}

extension InstantSyncInterruption {
  /// The interruption `failure` means while the network path is `path` (nil: the runtime reads none): pure.
  ///
  /// With no path at all, no network is what stands in the way first, except for what waits on someone: a refused
  /// sign-in or a local repair.
  init(failure: InstantConnectionFailure, path: InstantNetworkPathState?) {
    let pathIsMissing = path.map { !$0.isSatisfied } ?? false
    let cause: Cause =
      switch failure.kind {
      case .authentication: .authentication
      case .localRepairNeeded: .localRepairNeeded
      case _ where pathIsMissing: .noNetwork
      case .noNetwork: .noNetwork
      case .transport: .weakNetwork
      case .serverUnreachable: .serverUnreachable
      case .rateLimited: .rateLimited
      case .other: .other
      }
    self.init(
      cause: cause,
      since: Date(timeIntervalSince1970: Double(failure.sinceMilliseconds) / 1_000),
      retryAt: failure.retryAtMilliseconds.map { Date(timeIntervalSince1970: Double($0) / 1_000) },
      networkPath: path?.logDescription,
      detail: failure.detail
    )
  }
}
