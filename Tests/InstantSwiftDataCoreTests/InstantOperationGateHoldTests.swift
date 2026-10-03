import ConcurrencyExtras
import CustomDump
import Darwin
import Foundation
@testable import InstantSwiftDataCore
import Testing

/// #473 (P0 for 1.9.5): on Michael's iPhone a local write held the runtime's operation gate for 12 s at 13:17:46 and
/// the recording died behind it; transcription stalled behind gate backlogs twice that day. A write logs while it holds
/// the gate, and each log line created the directory, opened, locked, wrote and fsynced the file; the gate's handoff
/// wrote its wait report before the next holder could run; a write's phases had no names, so the stall line could not
/// say which one held the gate; and listing the outbox decoded every row under the gate.
@Suite(.serialized)
struct InstantOperationGateHoldTests {
  /// A log file that cannot be written (here a FIFO with no reader, whose open blocks) must not hold the caller.
  @Test
  func recordingAnEntryDoesNotWaitForTheLogFile() async throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("instant-diagnostics-fifo-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let fifo = directory.appendingPathComponent("blocked.jsonl")
    #expect(mkfifo(fifo.path, 0o600) == 0)
    let diagnostics = InstantDiagnostics(
      configuration: InstantDiagnosticsConfiguration(fileURL: fifo, maximumFileBytes: nil)
    )
    let returned = LockIsolated(false)
    let writer = Task.detached {
      diagnostics.record(
        subsystem: "test",
        category: "gate",
        event: "test.blocked-log",
        message: "The log file cannot be opened yet."
      )
      returned.setValue(true)
    }
    for _ in 0..<100 where !returned.value {
      try await Task.sleep(for: .milliseconds(10))
    }
    let returnedInTime = returned.value
    // A reader lets the blocked open finish, so the entry is written and nothing stays blocked.
    let reader = open(fifo.path, O_RDONLY | O_NONBLOCK)
    defer { close(reader) }
    await writer.value
    diagnostics.flush()
    #expect(returnedInTime, "record waited for a log file it could not open")
  }

  /// The gate hands over before it reports the wait: a wait report that blocks must not hold the next caller.
  @Test
  func theNextHolderRunsBeforeItsWaitIsReported() async throws {
    let reportEntered = DispatchSemaphore(value: 0)
    let releaseReport = DispatchSemaphore(value: 0)
    let gate = AsyncSerialGate(
      label: "test",
      waitReportThresholdMilliseconds: 0,
      waitReport: { _ in
        reportEntered.signal()
        releaseReport.wait()
      }
    )
    await gate.enter(operation: "holder")
    let nextHolderRan = LockIsolated(false)
    let waiter = Task.detached {
      await gate.enter(operation: "waiter")
      nextHolderRan.setValue(true)
      await gate.leave()
    }
    while await gate.waiterCount == 0 {
      try await Task.sleep(for: .milliseconds(5))
    }
    let leaving = Task.detached { await gate.leave() }
    // The report blocks on the gate's actor now; the next holder must already be running.
    for _ in 0..<200 where reportEntered.wait(timeout: .now()) == .timedOut {
      try await Task.sleep(for: .milliseconds(5))
    }
    for _ in 0..<100 where !nextHolderRan.value {
      try await Task.sleep(for: .milliseconds(10))
    }
    let ranWhileReporting = nextHolderRan.value
    releaseReport.signal()
    await leaving.value
    await waiter.value
    #expect(ranWhileReporting, "the next holder waited for the wait report")
  }

  /// A local write names its phases, so a slow handoff says which one held the gate.
  @Test
  func aLocalWriteNamesThePhaseThatHeldTheGate() async throws {
    let releaseFirst = AsyncStream<Void>.makeStream()
    let firstPaused = AsyncStream<Void>.makeStream()
    let runtime = try await InstantPendingMutationsPageTests.offlineRuntime("gate-hold-phases") { configuration in
      configuration.onLocalMutationPersistedBeforeStorePublicationForTesting = { transactionID in
        guard transactionID == "tx-held" else { return }
        firstPaused.continuation.yield()
        var iterator = releaseFirst.stream.makeAsyncIterator()
        _ = await iterator.next()
      }
    }
    let reports = LockIsolated<[InstantDiagnosticEntry]>([])
    let token = InstantDiagnostics.shared.addHandler { entry in
      guard entry.event == "serial-gate.waited", entry.metadata["gate"] == "operation" else { return }
      reports.withValue { $0.append(entry) }
    }
    defer { InstantDiagnostics.shared.removeHandler(token) }

    let held = Task {
      try await InstantPendingMutationsPageTests.createTodo("held", in: runtime)
    }
    var paused = firstPaused.stream.makeAsyncIterator()
    _ = await paused.next()
    let waiting = Task {
      try await InstantPendingMutationsPageTests.createTodo("waiting", in: runtime)
    }
    try await Task.sleep(for: .milliseconds(400))
    releaseFirst.continuation.yield()
    try await held.value
    try await waiting.value

    // The handoff names the phase the held write was in when it left: the publish that follows its save.
    let phases = reports.value.map { $0.metadata["previousHolderPhase"] ?? "" }
    #expect(
      phases.contains { ["publish store", "publish status"].contains($0) },
      "the wait names the held write's phase, not \(phases)"
    )
  }

}

// MARK: - Needs v1.9.5's API: the red run on v1.9.4 drops everything below this line.

extension InstantOperationGateHoldTests {
  /// A holder's phase, named without a hop onto the gate, reaches the stall report.
  @Test
  func aPhaseNamedWithoutAHopReachesTheStallReport() async throws {
    let stalls = LockIsolated<[AsyncSerialGate.StallReport]>([])
    let gate = AsyncSerialGate(
      label: "test",
      stallThresholdMilliseconds: 50,
      report: { report in stalls.withValue { $0.append(report) } }
    )
    await gate.enter(operation: "holder")
    gate.markHolderPhase("slow phase")
    let waiter = Task.detached {
      await gate.enter(operation: "waiter")
      await gate.leave()
    }
    for _ in 0..<300 where stalls.value.isEmpty {
      try await Task.sleep(for: .milliseconds(10))
    }
    await gate.leave()
    await waiter.value
    expectNoDifference(stalls.value.first?.holderPhase, "slow phase")
  }

  /// Listing the oldest pending or failed writes never waits for the operation gate.
  @Test
  func aBoundedOutboxListingDoesNotWaitForTheOperationGate() async throws {
    let releaseFirst = AsyncStream<Void>.makeStream()
    let firstPaused = AsyncStream<Void>.makeStream()
    let runtime = try await InstantPendingMutationsPageTests.offlineRuntime("gate-hold-listing") { configuration in
      configuration.onLocalMutationPersistedBeforeStorePublicationForTesting = { transactionID in
        guard transactionID == "tx-held" else { return }
        firstPaused.continuation.yield()
        var iterator = releaseFirst.stream.makeAsyncIterator()
        _ = await iterator.next()
      }
    }
    try await InstantPendingMutationsPageTests.createTodo("queued", in: runtime)

    let held = Task {
      try await InstantPendingMutationsPageTests.createTodo("held", in: runtime)
    }
    var paused = firstPaused.stream.makeAsyncIterator()
    _ = await paused.next()
    let listing = Task { await runtime.pendingMutations(limit: 10) }
    let failedListing = Task { await runtime.failedMutations(limit: 10) }
    let listed = LockIsolated<[String]?>(nil)
    let listedFailed = LockIsolated<[String]?>(nil)
    Task {
      listed.setValue(await listing.value.map(\.id))
      listedFailed.setValue(await failedListing.value.map(\.id))
    }
    for _ in 0..<200 where listed.value == nil || listedFailed.value == nil {
      try await Task.sleep(for: .milliseconds(10))
    }
    let pendingWhileHeld = listed.value
    let failedWhileHeld = listedFailed.value
    releaseFirst.continuation.yield()
    try await held.value
    #expect(pendingWhileHeld?.contains("tx-queued") == true, "the listing waited for the held write")
    expectNoDifference(failedWhileHeld, [])
  }
}
