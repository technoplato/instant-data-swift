import CustomDump
import Foundation
import Testing
@testable import InstantSwiftDataCore

/// Measures #296's cause against a real Instant server with the library's own URLSession transport.
///
/// The server pings every 5 s and closes a client that has sent nothing, not even a pong, for longer than its idle
/// timeout (upstream `server/src/instant/lib/ring/websocket.clj`, `straight-jacket-run-ping-job`). URLSession
/// answers a ping only while a `receive()` is outstanding. So a receive loop that applies one frame for longer than
/// that loses its socket.
///
/// Measured on 2026-09-30 against production Instant: with `receive()` withheld, the socket survived 20 s (2 of 2),
/// died at 24-28 s in 3 of 6 trials, and died at 32-45 s in 7 of 7, each time with "Socket is not connected" (POSIX
/// 57), as on the device. A Node client that reads but never pongs is closed at about 25 s. So these probes hold 40 s,
/// clear of that jitter.
///
/// The probes keep the socket quiet while they hold it: no query subscription, so no `refresh-ok` traffic. Heavy
/// server traffic that the client is not reading postpones the close. The server's idle check runs in the same job as
/// a blocking ping send, and TCP backpressure blocks that send (measured: subscribed sockets on a busy app survived
/// 40 s holds, and so did a client that read one frame every 30 s for 94 s). Recording 023's connections were quiet
/// enough to be closed during their 26-37 s applies.
///
/// Credentialed and opt-in: set `INSTANT_KEEPALIVE_PROBE_APP_ID` to a throwaway Instant app. The sessions are
/// unauthenticated (no refresh token). They send `init`, `add-query`, and `join-room`, and write no data.
struct InstantURLSessionKeepaliveLiveTests {
  @Test(
    .enabled(
      if: KeepaliveProbe.appID != nil,
      "Set INSTANT_KEEPALIVE_PROBE_APP_ID to a throwaway Instant app to run the live keepalive probe."
    )
  )
  func urlSessionAnswersServerPingsOnlyWhileAReceiveIsOutstanding() async throws {
    let appID = try #require(KeepaliveProbe.appID)
    async let shortHold = KeepaliveProbe.run(appID: appID, holdSeconds: 10, keepsReceiveOutstanding: false)
    async let longHold = KeepaliveProbe.run(appID: appID, holdSeconds: 40, keepsReceiveOutstanding: false)
    async let longHoldWhileReading = KeepaliveProbe.run(
      appID: appID,
      holdSeconds: 40,
      keepsReceiveOutstanding: true
    )
    let results = try await [shortHold, longHold, longHoldWhileReading]
    for result in results {
      print(result.summary)
    }
    expectNoDifference(results.map(\.outcome), [.alive, .closed, .alive])
  }

  /// A one-off measurement: set `INSTANT_KEEPALIVE_PROBE_SWEEP_SECONDS` (for example `12,14,16,18,20,22,25`) to print
  /// which withheld-`receive()` durations the server survives. Each hold runs on its own socket.
  @Test(
    .enabled(
      if: KeepaliveProbe.appID != nil && KeepaliveProbe.sweepSeconds != nil,
      "Set INSTANT_KEEPALIVE_PROBE_APP_ID and INSTANT_KEEPALIVE_PROBE_SWEEP_SECONDS to measure the close threshold."
    )
  )
  func measureTheCloseThreshold() async throws {
    let appID = try #require(KeepaliveProbe.appID)
    let holds = try #require(KeepaliveProbe.sweepSeconds)
    let results = try await withThrowingTaskGroup(of: KeepaliveProbe.Result.self) { group in
      for hold in holds {
        group.addTask {
          try await KeepaliveProbe.run(appID: appID, holdSeconds: hold, keepsReceiveOutstanding: false)
        }
      }
      var results: [KeepaliveProbe.Result] = []
      for try await result in group {
        results.append(result)
      }
      return results.sorted { $0.holdSeconds < $1.holdSeconds }
    }
    for result in results {
      print(result.summary)
    }
    #expect(results.count == holds.count)
  }

  /// The runtime keeps its socket while it applies one frame for 40 s. `onLiveReceiverEventAcquiredForTesting` holds
  /// the first frame, standing in for Recording 023's 26-37 s rebase. The frame answers a join of a fresh room, so no
  /// query refreshes flow while it is held. Build 72 lost the socket at this point and reconnected. With the reader,
  /// the same connection still answers the next join.
  @Test(
    .enabled(
      if: KeepaliveProbe.appID != nil,
      "Set INSTANT_KEEPALIVE_PROBE_APP_ID to a throwaway Instant app to run the live keepalive probe."
    )
  )
  func runtimeKeepsItsSocketThroughALongFrameApply() async throws {
    let appID = try #require(KeepaliveProbe.appID)
    let attempts = KeepaliveCounter()
    let transport = InstantLiveTransportClient.connectionAttempts { request in
      attempts.increment()
      return try InstantLiveTransportClient.live.makeConnectionAttempt(request)
    }
    let longApply = KeepaliveLongApply(holdSeconds: 40)
    let receiveLoopFailures = KeepaliveCounter()
    let handler = InstantDiagnostics.shared.addHandler { entry in
      if entry.event == "connection.receive-loop-failed", entry.metadata["appID"] == appID {
        receiveLoopFailures.increment()
      }
    }
    defer { InstantDiagnostics.shared.removeHandler(handler) }
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("InstantURLSessionKeepaliveLiveTests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    var configuration = InstantRuntimeConfiguration(
      appID: appID,
      persistenceURL: directory.appendingPathComponent("state.sqlite"),
      initialAttributes: TodoExample.attributes,
      liveTransport: transport
    )
    configuration.autoConnectLiveTransport = false
    configuration.onLiveReceiverEventAcquiredForTesting = { await longApply.frameAcquired() }
    let runtime = try await InstantRuntime.bootstrap(configuration: configuration)

    _ = try await runtime.connect()
    _ = try await runtime.joinRoom(InstantRoomHandle(type: "keepaliveProbe", id: UUID().uuidString.lowercased()))
    try await keepaliveWait("the room join's answer to reach the applier", timeoutSeconds: 5) {
      await longApply.acquiredCount >= 1
    }
    let startedAt = ContinuousClock.now
    // Not a timeout for the server: the 40 s hold is the experiment itself. The bound is the hold plus the usual 5 s.
    try await keepaliveWait("the held frame to finish its 40 s apply", timeoutSeconds: 40 + 5) {
      await longApply.finishedFirstFrame
    }
    let applySeconds = (ContinuousClock.now - startedAt).components.seconds

    let framesBeforeSecondJoin = await longApply.acquiredCount
    _ = try await runtime.joinRoom(InstantRoomHandle(type: "keepaliveProbe", id: UUID().uuidString.lowercased()))
    try await keepaliveWait("the server to answer the next join", timeoutSeconds: 5) {
      await longApply.acquiredCount > framesBeforeSecondJoin
    }
    print(
      "runtime long apply: held \(applySeconds) s; connection attempts \(attempts.value); "
        + "receive-loop failures \(receiveLoopFailures.value)"
    )
    expectNoDifference(attempts.value, 1, "The first connection survived the long apply.")
    expectNoDifference(receiveLoopFailures.value, 0)
    _ = try await runtime.closeConnection()
  }
}

private enum KeepaliveProbe {
  /// The throwaway app to probe. Production Scribe (`e7c49961…`) is refused even if it is set here.
  static let appID: String? = {
    guard
      let raw = ProcessInfo.processInfo.environment["INSTANT_KEEPALIVE_PROBE_APP_ID"]?
        .trimmingCharacters(in: .whitespacesAndNewlines),
      !raw.isEmpty,
      !raw.hasPrefix("e7c49961")
    else { return nil }
    return raw
  }()

  static let sweepSeconds: [UInt64]? = {
    guard let raw = ProcessInfo.processInfo.environment["INSTANT_KEEPALIVE_PROBE_SWEEP_SECONDS"] else {
      return nil
    }
    let holds = raw.split(separator: ",").compactMap {
      UInt64($0.trimmingCharacters(in: .whitespaces))
    }
    return holds.isEmpty ? nil : holds
  }()

  enum Outcome: Equatable {
    /// The server answered a request sent after the hold.
    case alive
    /// Sending or receiving after the hold failed: the server had closed the socket.
    case closed
    /// Nothing failed, but no answer arrived within 5 s.
    case unanswered
  }

  struct Result: Sendable {
    var holdSeconds: UInt64
    var keepsReceiveOutstanding: Bool
    var outcome: Outcome
    var detail: String

    var summary: String {
      let reading = keepsReceiveOutstanding ? "receive() outstanding" : "no receive() outstanding"
      return "keepalive probe: held \(holdSeconds) s with \(reading) -> \(outcome) (\(detail))"
    }
  }

  static func run(
    appID: String,
    holdSeconds: UInt64,
    keepsReceiveOutstanding: Bool
  ) async throws -> Result {
    let request = InstantLiveSessionRequest(appID: appID)
    let session = try await InstantLiveTransportClient.live.connect(request)
    defer { session.abort() }
    let initReply = try await answer(from: session, pending: nil) {
      try await session.send(request.initMessage(clientEventID: UUID().uuidString.lowercased()))
    }
    guard initReply.op == "init-ok" else {
      throw InstantError(
        code: .networkFailed,
        operation: "open keepalive probe session",
        message: "Expected init-ok, received \(initReply.op).",
        recovery: "Check INSTANT_KEEPALIVE_PROBE_APP_ID."
      )
    }
    let pending: Task<InstantLiveMessage, any Error>? =
      keepsReceiveOutstanding ? Task { try await session.receive() } : nil
    try await Task.sleep(nanoseconds: holdSeconds * 1_000_000_000)

    var outcome = Outcome.alive
    var detail = ""
    do {
      let reply = try await answer(from: session, pending: pending) {
        try await session.send(
          .addQuery(
            .object(["keepaliveProbe": .object(["$": .object(["limit": .number(1)])])]),
            clientEventID: UUID().uuidString.lowercased()
          )
        )
      }
      detail = "answered with \(reply.op)"
    } catch let error as InstantError where error.operation == Self.answerOperation {
      outcome = .unanswered
      detail = error.message
    } catch {
      outcome = .closed
      detail = String(describing: error)
    }
    return Result(
      holdSeconds: holdSeconds,
      keepsReceiveOutstanding: keepsReceiveOutstanding,
      outcome: outcome,
      detail: detail
    )
  }

  private static let answerOperation = "wait for the keepalive probe's answer"

  /// Sends `request`, then returns the next frame. After 5 s without one it throws an error whose operation is
  /// `answerOperation`.
  private static func answer(
    from session: InstantLiveWebSocketSession,
    pending: Task<InstantLiveMessage, any Error>?,
    after request: @escaping @Sendable () async throws -> Void
  ) async throws -> InstantLiveMessage {
    try await instantLiveWithTimeout(
      operation: answerOperation,
      timeoutMilliseconds: 5_000,
      onAbandon: { session.abort() }
    ) {
      try await request()
      if let pending {
        return try await pending.value
      }
      return try await session.receive()
    }
  }
}

/// Holds the first acquired frame for `holdSeconds`, then lets every frame through.
private actor KeepaliveLongApply {
  private let holdSeconds: UInt64
  private(set) var acquiredCount = 0
  private(set) var finishedFirstFrame = false

  init(holdSeconds: UInt64) {
    self.holdSeconds = holdSeconds
  }

  func frameAcquired() async {
    acquiredCount += 1
    guard acquiredCount == 1 else { return }
    try? await Task.sleep(nanoseconds: holdSeconds * 1_000_000_000)
    finishedFirstFrame = true
  }
}

// SAFETY: `lock` protects `count`.
private final class KeepaliveCounter: @unchecked Sendable {
  private let lock = NSLock()
  private var count = 0

  var value: Int { lock.withLock { count } }

  func increment() {
    lock.withLock { count += 1 }
  }
}

private func keepaliveWait(
  _ description: String,
  timeoutSeconds: Int,
  _ condition: @Sendable () async -> Bool
) async throws {
  let deadline = ContinuousClock.now + .seconds(timeoutSeconds)
  while !(await condition()) {
    guard ContinuousClock.now < deadline else {
      throw InstantError(
        code: .networkFailed,
        operation: "keepalive live test",
        message: "Timed out after \(timeoutSeconds) s waiting for \(description).",
        recovery: "Inspect the live session diagnostics."
      )
    }
    try await Task.sleep(nanoseconds: 10_000_000)
  }
}
