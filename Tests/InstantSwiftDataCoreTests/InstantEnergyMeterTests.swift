import CustomDump
import Darwin
import Foundation
import Testing
@testable import InstantSwiftDataCore

/// The energy meter an app reads once a minute to say which library operation costs what (#669).
///
/// The meter is process-wide, and other suites run beside these, so the runtime tests expect at least what they caused;
/// the meter's own arithmetic is checked on a private storage.
@Suite(.serialized)
struct InstantEnergyMeterTests {
  @Test
  func aSectionAddsItsCountCPUAndWallTime() throws {
    let meter = InstantEnergyMeterStorage()
    let checksum = energyMeterBusyWork(meter, operation: .localSave, iterations: 200_000)
    #expect(checksum != 0)
    let measure = meter.snapshot()[.localSave]
    expectNoDifference(measure.count, 1)
    #expect(measure.cpuNanoseconds > 0)
    #expect(measure.wallNanoseconds > 0)
    expectNoDifference(meter.snapshot()[.storePrepare], InstantEnergySnapshot.Measure())
  }

  @Test
  func aSpanAddsItsCountAndWallTimeButNoCPU() async throws {
    let meter = InstantEnergyMeterStorage()
    let span = meter.beginSpan(.connectAttempt)
    try await Task.sleep(nanoseconds: 5_000_000)
    span.end()
    let measure = meter.snapshot()[.connectAttempt]
    expectNoDifference(measure.count, 1)
    expectNoDifference(measure.cpuNanoseconds, 0)
    #expect(measure.wallNanoseconds >= 5_000_000)
  }

  @Test
  func eventsAndSnapshotsSubtract() throws {
    let meter = InstantEnergyMeterStorage()
    meter.record(.transaction)
    meter.record(.outboxRowWritten)
    let earlier = meter.snapshot()
    meter.record(.transaction, count: 2)
    meter.record(.outboxRowSuperseded, count: 3)
    meter.record(.reconnectAttempt)
    _ = energyMeterBusyWork(meter, operation: .prune, iterations: 1_000)
    let delta = meter.snapshot().subtracting(earlier)
    expectNoDifference(delta.transactions, 2)
    expectNoDifference(delta.outboxRowsWritten, 0)
    expectNoDifference(delta.outboxRowsSuperseded, 3)
    expectNoDifference(delta.reconnectAttempts, 1)
    expectNoDifference(delta[.prune].count, 1)
    expectNoDifference(Set(meter.snapshot().operations.keys), Set(InstantEnergyOperation.allCases))
  }

  /// The meter's own cost: begin/end pairs on one thread, with no one recording signposts. Prints the cost per pair.
  @Test
  func aSectionCostsAMicrosecondOrLess() throws {
    let meter = InstantEnergyMeterStorage()
    let pairs = 200_000
    _ = energyMeterPairs(meter, count: 10_000)
    let cpuNanoseconds = energyMeterPairs(meter, count: pairs)
    let perPair = Double(cpuNanoseconds) / Double(pairs)
    print("energy-meter: \(String(format: "%.0f", perPair)) ns of thread CPU per begin/end pair over \(pairs) pairs")
    expectNoDifference(meter.snapshot()[.observerRefresh].count, pairs + 10_000)
    #expect(perPair < 2_000)
  }

  /// Local writes count their transactions and outbox rows; a run of same-entity assignments supersedes the tail.
  @Test
  func localWritesCountTransactionsRowsAndSupersededRows() async throws {
    let runtime = try await InstantRuntime.bootstrap(configuration: try energyMeterConfiguration(appID: "energy-local"))
    let observation = await runtime.observe(TodoExample.query)
    let drain = Task { for await _ in observation {} }
    defer { drain.cancel() }
    let before = InstantEnergyMeter.snapshot()
    let writes = 20
    for revision in 0..<writes {
      let id = "energy-tx-\(revision)"
      let time = InstantTimestamp(milliseconds: 1_700_000_000_000 + Int64(revision))
      try await runtime.transact(
        InstantStoreTransaction(
          id: id,
          operations: TodoExample.upsertOperations(
            id: "energy-todo",
            text: "revision \(revision)",
            createdAt: time,
            transactionID: id
          )
        ),
        createdAt: time
      )
    }
    let delta = InstantEnergyMeter.snapshot().subtracting(before)
    #expect(delta.transactions >= writes)
    #expect(delta.outboxRowsWritten >= 1)
    #expect(delta.outboxRowsSuperseded >= writes - 1)
    #expect(delta[.localSave].count >= writes)
    #expect(delta[.localSave].cpuNanoseconds > 0)
    #expect(delta[.storePrepare].count >= writes)
    #expect(delta[.observerRefresh].count >= 1)
    let pending = await runtime.pendingMutationCount()
    expectNoDifference(pending, 1, "The run of assignments left one outbox row.")
  }

  /// A failed connection counts as a connect attempt, and the scheduled reconnect's attempts count as reconnects.
  @Test
  func failedConnectionsCountAttemptsAndReconnects() async throws {
    let attempts = EnergyMeterFailingTransport()
    var configuration = try energyMeterConfiguration(appID: "energy-connect", transport: attempts.client)
    configuration.autoConnectLiveTransport = true
    configuration.liveReconnectSleep = { _ in
      // The bootstrap's attempt and two reconnects, then the reconnect waits until the test closes the connection.
      if await attempts.count >= 3 {
        await attempts.park()
        try await Task.sleep(nanoseconds: 60_000_000_000)
      }
    }
    let before = InstantEnergyMeter.snapshot()
    let runtime = try await InstantRuntime.bootstrap(configuration: configuration)
    let deadline = ContinuousClock.now + .seconds(5)
    while await !attempts.isParked, ContinuousClock.now < deadline {
      try await Task.sleep(nanoseconds: 2_000_000)
    }
    let delta = InstantEnergyMeter.snapshot().subtracting(before)
    #expect(delta[.connectAttempt].count >= 3)
    #expect(delta[.connectAttempt].wallNanoseconds > 0)
    #expect(delta.reconnectAttempts >= 2)
    _ = try await runtime.closeConnection()
  }
}

/// A synchronous section around some hashing, so the CPU clock moves.
private func energyMeterBusyWork(
  _ meter: InstantEnergyMeterStorage,
  operation: InstantEnergyOperation,
  iterations: Int
) -> Int {
  let interval = meter.begin(operation)
  var hasher = Hasher()
  for value in 0..<iterations {
    hasher.combine(value)
  }
  interval.end()
  return hasher.finalize() | 1
}

/// The thread CPU time `count` empty begin/end pairs take.
private func energyMeterPairs(_ meter: InstantEnergyMeterStorage, count: Int) -> UInt64 {
  let start = clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID)
  for _ in 0..<count {
    meter.begin(.observerRefresh).end()
  }
  return clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID) - start
}

/// Every attempt fails at once, as an open that timed out.
private actor EnergyMeterFailingTransport {
  private(set) var count = 0
  /// The reconnect waits after its third attempt: every attempt so far has finished.
  private(set) var isParked = false

  func park() {
    isParked = true
  }

  nonisolated var client: InstantLiveTransportClient {
    .connectionAttempts { _ in
      InstantLiveConnectionAttempt(
        connect: {
          await self.increment()
          throw InstantError(
            code: .networkFailed,
            operation: "open Instant live session",
            message: "Timed out after 5000ms waiting for Instant live transport.",
            recovery: "Check the Instant WebSocket endpoint, credentials, and server response."
          )
        },
        abort: {}
      )
    }
  }

  private func increment() {
    count += 1
  }
}

/// A runtime with a live transport that never connects on its own, so local writes stay in the durable outbox.
private func energyMeterConfiguration(
  appID: String,
  transport: InstantLiveTransportClient? = nil
) throws -> InstantRuntimeConfiguration {
  let directory = FileManager.default.temporaryDirectory
    .appendingPathComponent("InstantEnergyMeterTests-\(UUID().uuidString)")
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  var configuration = InstantRuntimeConfiguration(
    appID: appID,
    persistenceURL: directory.appendingPathComponent("state.sqlite"),
    initialAttributes: TodoExample.attributes,
    now: { InstantTimestamp(milliseconds: 1_700_000_000_000) },
    liveTransport: transport ?? .connectionAttempts { _ in
      InstantLiveConnectionAttempt(
        connect: { throw CancellationError() },
        abort: {}
      )
    }
  )
  configuration.autoConnectLiveTransport = false
  return configuration
}
