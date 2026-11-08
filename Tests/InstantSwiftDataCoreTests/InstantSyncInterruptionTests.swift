import CustomDump
import Foundation
import Testing
@testable import InstantSwiftDataCore

/// Why changes are not reaching Instant, as a cause an app can show (#2037).
///
/// A device on a cellular network that dropped every few minutes met three failures over and over: a receive that ended
/// with "Socket is not connected" (POSIX 57), an open that met the five-second deadline ("Timed out after 5000ms waiting
/// for Instant live transport."), and a send that failed on a socket that had already died. The connection status said
/// `.errored` with that text, so the app could only say that it was not syncing. The same open deadline is what a
/// device with no network at all meets, because the socket waits for connectivity: only the network path tells a weak
/// network from none. Upstream's server sends a rate limit over the socket as an `error` frame with status 400 and type
/// `rate-limited` (over HTTP, a 429), with its retry time only in the hint (`retry-at`, ISO 8601; `retry-after`, whole
/// seconds).
@Suite
struct InstantSyncInterruptionTests {
  static let now: Int64 = 1_794_095_640_000  // 2026-11-07 18:54:00 EST
  static let cellular = InstantNetworkPathState(isSatisfied: true, isExpensive: true, interface: .cellular)
  static let wifi = InstantNetworkPathState(isSatisfied: true, interface: .wifi)
  static let none = InstantNetworkPathState(isSatisfied: false)

  static let openTimedOut = InstantError(
    code: .networkFailed,
    operation: "open Instant live session",
    message: "Timed out after 5000ms waiting for Instant live transport.",
    recovery: "Check the Instant WebSocket endpoint, credentials, and server response."
  )
  static let socketNotConnected = NSError(
    domain: NSPOSIXErrorDomain,
    code: 57,
    userInfo: [NSLocalizedDescriptionKey: "Socket is not connected"]
  )

  static func cause(_ error: any Error, on path: InstantNetworkPathState?) -> InstantSyncInterruption.Cause {
    let failure = InstantConnectionFailure(classifying: error, atMilliseconds: now)
    return InstantSyncInterruption(failure: failure, path: path).cause
  }

  static func rateLimited(status: Int, hint: InstantLiveJSONValue?) -> InstantError {
    InstantError(
      code: .validationFailed,
      operation: "transact",
      serverStatus: status,
      serverType: "rate-limited",
      serverHint: hint,
      message: "You're making too many requests. Please email support@instantdb.com or ask for help in the Discord.",
      recovery: "Wait, then send it again."
    )
  }

  /// The drive's failures: a weak network while the cellular path is there, no network once it is gone.
  @Test
  func aTransportThatDoesNotKeepUpIsAWeakNetworkOnAPathAndNoNetworkWithoutOne() {
    let transportFailures: [any Error] = [
      Self.openTimedOut,
      Self.socketNotConnected,
      URLError(.timedOut),
      URLError(.networkConnectionLost),
      NSError(domain: NSPOSIXErrorDomain, code: 54, userInfo: [NSLocalizedDescriptionKey: "Connection reset by peer"]),
    ]
    for error in transportFailures {
      expectNoDifference(Self.cause(error, on: Self.cellular), .weakNetwork, "\(error)")
      expectNoDifference(Self.cause(error, on: Self.wifi), .weakNetwork, "\(error)")
      expectNoDifference(Self.cause(error, on: Self.none), .noNetwork, "\(error)")
      // A transport that reads no path (a scripted one, watchOS, a simulator) still says the network did not keep up.
      expectNoDifference(Self.cause(error, on: nil), .weakNetwork, "\(error)")
    }
  }

  /// The system's own word that there is no route is no network, whatever the path last said.
  @Test
  func theSystemSayingThereIsNoRouteIsNoNetwork() {
    for code in [URLError.Code.notConnectedToInternet, .dataNotAllowed, .internationalRoamingOff] {
      expectNoDifference(Self.cause(URLError(code), on: Self.cellular), .noNetwork, "\(code)")
    }
  }

  /// A network that answers while Instant's server does not: its host is not found or refuses the connection, the
  /// secure connection fails, or it answers with a server error.
  @Test
  func aServerThatDoesNotAnswerIsUnreachableWhileThePathIsThere() {
    let failures: [any Error] = [
      URLError(.cannotFindHost),
      URLError(.dnsLookupFailed),
      URLError(.cannotConnectToHost),
      URLError(.secureConnectionFailed),
      URLError(.badServerResponse),
      NSError(domain: NSPOSIXErrorDomain, code: 61, userInfo: [NSLocalizedDescriptionKey: "Connection refused"]),
      InstantError(
        code: .networkFailed,
        operation: "open Instant live session",
        serverStatus: 503,
        message: "This app is served by a different backend.",
        recovery: "Try again."
      ),
    ]
    for error in failures {
      expectNoDifference(Self.cause(error, on: Self.wifi), .serverUnreachable, "\(error)")
      expectNoDifference(Self.cause(error, on: Self.none), .noNetwork, "\(error)")
    }
  }

  /// A rate limit is itself, over the socket (status 400) or HTTP (429), with the server's retry time when it gives one.
  @Test
  func aRateLimitIsItselfWithTheServersRetryTime() throws {
    let retryAt = Date(timeIntervalSince1970: Double(Self.now) / 1_000 + 42)
    let withRetryAt = Self.rateLimited(
      status: 400,
      hint: .object([
        "retry-at": .string(retryAt.formatted(.iso8601)),
        "retry-after": .number(42),
        "remaining-tokens": .number(0),
      ])
    )
    let failure = InstantConnectionFailure(classifying: withRetryAt, atMilliseconds: Self.now)
    let interruption = InstantSyncInterruption(failure: failure, path: Self.cellular)
    expectNoDifference(interruption.cause, .rateLimited)
    expectNoDifference(interruption.retryAt, retryAt)

    // Only `retry-after`: seconds from when the server answered.
    let afterOnly = InstantConnectionFailure(
      classifying: Self.rateLimited(status: 429, hint: .object(["retry-after": .number(30)])),
      atMilliseconds: Self.now
    )
    expectNoDifference(afterOnly.kind, .rateLimited)
    expectNoDifference(afterOnly.retryAtMilliseconds, Self.now + 30_000)

    // An app the server limits as a whole sends no hint: no retry time, still a rate limit.
    let flagged = InstantConnectionFailure(
      classifying: Self.rateLimited(status: 400, hint: nil),
      atMilliseconds: Self.now
    )
    expectNoDifference(flagged.kind, .rateLimited)
    expectNoDifference(flagged.retryAtMilliseconds, nil)
    // With no network at all, that is what stands in the way first.
    expectNoDifference(InstantSyncInterruption(failure: flagged, path: Self.none).cause, .noNetwork)
  }

  /// A refused sign-in, and a local repair, wait for someone to act; every other cause ends on its own.
  @Test
  func aRefusedSignInAndALocalRepairWaitForSomeoneToAct() {
    let refusedSignIn = InstantError(
      code: .authFailed,
      operation: "verify refresh token",
      message: "Instant auth returned HTTP 401 (record-not-found): Record not found: app-user",
      recovery: "Sign in again."
    )
    expectNoDifference(Self.cause(refusedSignIn, on: Self.wifi), .authentication)
    let blocker = InstantSynchronizationBlocker(
      reason: .unknownOptimisticEffectReceipt,
      firstMutationID: "tx-unknown",
      blockedMutationCount: 2
    ).error(operation: "open Instant live connection")
    expectNoDifference(Self.cause(blocker, on: Self.wifi), .localRepairNeeded)
    // A missing network does not hide what someone must do.
    expectNoDifference(Self.cause(refusedSignIn, on: Self.none), .authentication)
    expectNoDifference(Self.cause(blocker, on: Self.none), .localRepairNeeded)

    expectNoDifference(
      InstantSyncInterruption.Cause.allCases.filter { !$0.endsOnItsOwn },
      [.authentication, .localRepairNeeded]
    )
  }

  /// No cause discards a queued change: the outbox is durable for every one.
  @Test
  func everyCauseKeepsTheQueuedChanges() {
    expectNoDifference(
      InstantSyncInterruption.Cause.allCases.filter { !$0.keepsQueuedChanges },
      []
    )
  }

  /// Anything else is other, and keeps the library's words for a details view.
  @Test
  func anythingElseIsOtherWithItsWords() {
    let failure = InstantConnectionFailure(
      classifying: InstantError(
        code: .decodeFailed,
        operation: "decode Instant live message",
        message: "Unexpected frame.",
        recovery: "Report it."
      ),
      atMilliseconds: Self.now
    )
    expectNoDifference(failure.kind, .other)
    #expect(failure.detail.contains("Unexpected frame."))
  }

  /// One interruption from the first failure to the next open: a later failure keeps the start and takes the newest
  /// kind and retry time.
  @Test
  func aLaterFailureKeepsTheInterruptionsStart() {
    let first = InstantConnectionFailure(classifying: Self.socketNotConnected, atMilliseconds: Self.now)
    let later = InstantConnectionFailure(
      classifying: Self.rateLimited(status: 400, hint: .object(["retry-after": .number(5)])),
      atMilliseconds: Self.now + 9_000
    )
    let kept = later.continuing(first)
    expectNoDifference(kept.sinceMilliseconds, Self.now)
    expectNoDifference(kept.kind, .rateLimited)
    expectNoDifference(kept.retryAtMilliseconds, Self.now + 9_000 + 5_000)
    expectNoDifference(first.continuing(nil), first)
  }

  /// A rate-limited write is not a refusal: it can succeed when sent again.
  @Test
  func aRateLimitedWriteIsTransientNotARefusal() {
    expectNoDifference(
      InstantWriteFailureKind.serverFailureKind(
        status: 400,
        type: "rate-limited",
        message: "You're making too many requests. Please email support@instantdb.com or ask for help in the Discord."
      ),
      .transient
    )
    expectNoDifference(
      InstantWriteFailureKind.serverFailureKind(
        status: 400,
        type: "permission-denied",
        message: "Permission denied: not perms-pass?"
      ),
      .rejected(.refusedByServer)
    )
  }
}
