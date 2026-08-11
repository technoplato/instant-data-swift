import CustomDump
import Foundation
@testable import InstantSwiftDataCore
import Testing

extension InstantStoreTests {
  @Test
  func validationHarnessRecordsSwiftSchemaFixtureArtifacts() throws {
    let harness = try String(
      contentsOf: packageRootURL()
        .appendingPathComponent("validation/run-e2e.sh"),
      encoding: .utf8
    )

    let requiredArtifacts = [
      "swift-schema-generate.json",
      "swift-perms-generate.json",
      "swift-schema-verify.json",
      "swift-perms-verify.json",
      "swift-generated-schema-verify.json",
      "swift-generated-perms-verify.json",
      "generated.instant.schema.ts",
      "generated.instant.perms.ts",
    ]
    let requiredEvents = [
      "swift-schema-fixtures-start",
      "swift-schema-generate-complete",
      "swift-perms-generate-complete",
      "swift-schema-verify-complete",
      "swift-perms-verify-complete",
      "swift-generated-schema-verify-complete",
      "swift-generated-perms-verify-complete",
      "swift-schema-fixtures-complete",
    ]
    let requiredCommands = [
      "swift run instant-swift-data schema generate",
      "swift run instant-swift-data perms generate",
      "swift run instant-swift-data schema verify",
      "swift run instant-swift-data perms verify",
      "--example validation",
      "--from validation/fixtures/instant.schema.ts",
      "--from validation/fixtures/instant.perms.ts",
    ]

    expectNoDifference(requiredArtifacts.filter { !harness.contains($0) }, [])
    expectNoDifference(requiredEvents.filter { !harness.contains($0) }, [])
    expectNoDifference(requiredCommands.filter { !harness.contains($0) }, [])
  }

  @Test
  func validationHarnessNormalizesRelativeResultsDirectory() throws {
    let harness = try String(
      contentsOf: packageRootURL()
        .appendingPathComponent("validation/run-e2e.sh"),
      encoding: .utf8
    )

    let requiredLines = [
      #"if [[ "${RESULTS_DIR}" != /* ]]; then"#,
      #"  RESULTS_DIR="${PWD}/${RESULTS_DIR}""#,
    ]

    expectNoDifference(requiredLines.filter { !harness.contains($0) }, [])
    #expect(
      harness.range(of: #"RESULTS_DIR="${INSTANT_SWIFT_DATA_VALIDATION_RESULTS_DIR"#)!
        .upperBound
        <= harness.range(of: #"if [[ "${RESULTS_DIR}" != /* ]]; then"#)!.lowerBound
    )
    #expect(
      harness.range(of: #"fi"#, range: harness.range(of: #"if [[ "${RESULTS_DIR}" != /* ]]; then"#)!.lowerBound..<harness.endIndex)!
        .upperBound
        <= harness.range(of: #"mkdir -p "${RESULTS_DIR}""#)!.lowerBound
    )
  }

  @Test
  func liveSessionValidationRejectsLegacySessionBeforeWireIO() async throws {
    let probe = LiveValidationSessionProbe()

    do {
      _ = try await InstantSwiftDataLiveSessionValidation.run(
        appID: "legacy-live-session-validation",
        websocketURI: try #require(URL(string: "wss://example.test/runtime/session")),
        liveTransport: probe.transport(providesImmediateAbort: false)
      )
      Issue.record("Expected validation to reject a session without immediate abort support.")
    } catch let failure as LiveSessionValidationFailure {
      expectNoDifference(failure.instantError?.code, .validationFailed)
      expectNoDifference(
        failure.instantError?.operation,
        "connect Instant live validation transport"
      )
      expectNoDifference(
        failure.instantError?.message,
        "The custom Instant live connection has no immediate abort operation."
      )
      #expect(failure.instantError?.recovery.contains("connectionAttempts") == true)
    }

    expectNoDifference(
      probe.snapshot(),
      LiveValidationSessionProbe.Snapshot()
    )
  }

  @Test
  func liveSessionValidationTimeoutAbortsStuckConnectionAttemptBeforeWireIO() async throws {
    let connection = InstantLiveTestConnectionContinuation()
    let probe = LiveValidationConnectionProbe()
    let transport = InstantLiveTransportClient.connectionAttempts { _ in
      InstantLiveConnectionAttempt(
        connect: {
          probe.recordStart()
          return try await connection.connect()
        },
        abort: {
          probe.recordAbort()
          connection.abort()
        }
      )
    }

    do {
      _ = try await InstantSwiftDataLiveSessionValidation.run(
        appID: "stuck-connect-live-session-validation",
        websocketURI: try #require(URL(string: "wss://example.test/runtime/session")),
        liveTransport: transport,
        eventTimeoutMillisecondsForTesting: 1,
        eventTimeoutSleepForTesting: { _ in
          while probe.snapshot().startCount == 0 {
            try Task.checkCancellation()
            await Task.yield()
          }
        }
      )
      Issue.record("Expected validation to time out the stuck connection attempt.")
    } catch let failure as LiveSessionValidationFailure {
      expectNoDifference(failure.instantError?.code, .networkFailed)
      expectNoDifference(
        failure.instantError?.operation,
        "connect Instant live validation transport"
      )
      expectNoDifference(
        failure.instantError?.message,
        "Timed out after 1ms waiting for Instant live transport."
      )
    }

    expectNoDifference(
      probe.snapshot(),
      LiveValidationConnectionProbe.Snapshot(startCount: 1, abortCount: 1)
    )
  }

  @Test
  func liveSessionValidationTimeoutAbortsStuckSendExactlyOnce() async throws {
    let probe = LiveValidationSessionProbe(sendWaitsForAbort: true)

    do {
      _ = try await InstantSwiftDataLiveSessionValidation.run(
        appID: "stuck-send-live-session-validation",
        websocketURI: try #require(URL(string: "wss://example.test/runtime/session")),
        liveTransport: probe.transport(providesImmediateAbort: true),
        eventTimeoutMillisecondsForTesting: 1,
        eventTimeoutSleepForTesting: { _ in
          while probe.snapshot().sendCount == 0 {
            try Task.checkCancellation()
            await Task.yield()
          }
        }
      )
      Issue.record("Expected validation to time out a stuck send.")
    } catch let failure as LiveSessionValidationFailure {
      expectNoDifference(failure.instantError?.code, .networkFailed)
      expectNoDifference(failure.instantError?.operation, "validate Instant live init")
      expectNoDifference(
        failure.instantError?.message,
        "Timed out after 1ms waiting for Instant live transport."
      )
    }

    expectNoDifference(
      probe.snapshot(),
      LiveValidationSessionProbe.Snapshot(sendCount: 1, abortCount: 1)
    )
  }
}

private final class LiveValidationConnectionProbe: @unchecked Sendable {
  struct Snapshot: Equatable {
    var startCount = 0
    var abortCount = 0
  }

  private let lock = NSLock()
  private var value = Snapshot()

  func recordStart() {
    lock.withLock { value.startCount += 1 }
  }

  func recordAbort() {
    lock.withLock { value.abortCount += 1 }
  }

  func snapshot() -> Snapshot {
    lock.withLock { value }
  }
}

private final class LiveValidationSessionProbe: @unchecked Sendable {
  struct Snapshot: Equatable {
    var sendCount = 0
    var receiveCount = 0
    var closeCount = 0
    var abortCount = 0
  }

  private let lock = NSLock()
  private let sendWaitsForAbort: Bool
  private var sendContinuation: CheckedContinuation<Void, Never>?
  private var state = Snapshot()

  init(sendWaitsForAbort: Bool = false) {
    self.sendWaitsForAbort = sendWaitsForAbort
  }

  func transport(providesImmediateAbort: Bool) -> InstantLiveTransportClient {
    .immediate { _ in
      if providesImmediateAbort {
        return InstantLiveWebSocketSession(
          send: { _ in await self.send() },
          receive: { try self.receive() },
          close: { self.recordClose() },
          abort: { self.abort() }
        )
      } else {
        return InstantLiveWebSocketSession(
          send: { _ in await self.send() },
          receive: { try self.receive() },
          close: { self.recordClose() }
        )
      }
    }
  }

  func snapshot() -> Snapshot {
    lock.withLock { state }
  }

  private func send() async {
    let waitsForAbort = lock.withLock {
      state.sendCount += 1
      return sendWaitsForAbort
    }
    guard waitsForAbort else { return }
    await withCheckedContinuation { continuation in
      let wasAlreadyAborted = lock.withLock {
        guard state.abortCount == 0 else { return true }
        sendContinuation = continuation
        return false
      }
      if wasAlreadyAborted { continuation.resume() }
    }
  }

  private func receive() throws -> InstantLiveMessage {
    lock.withLock {
      state.receiveCount += 1
    }
    throw CancellationError()
  }

  private func recordClose() {
    lock.withLock {
      state.closeCount += 1
    }
  }

  private func abort() {
    let continuation = lock.withLock {
      state.abortCount += 1
      let continuation = sendContinuation
      sendContinuation = nil
      return continuation
    }
    continuation?.resume()
  }
}

private func packageRootURL(filePath: String = #filePath) -> URL {
  URL(fileURLWithPath: filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
}
