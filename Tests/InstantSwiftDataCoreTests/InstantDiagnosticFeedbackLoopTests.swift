import Foundation
import Testing

@testable import InstantSwiftDataCore

/// Host apps (Scribe) dual-write InstantDiagnostics into Instant as debug-log
/// batches. When routine outbox/query/transport chatter is emitted at `.info`
/// or `.notice`, that dual-write re-enters the outbox and multiplies into
/// multi-GB idle memory (field: iPad 2026-08-05, ~2.7–3.8 GB sitting idle with
/// continuous `debug-log-batch` mutations of ~700 ops).
///
/// High-frequency routine events must stay at `.debug`/`.trace` so a host bridge
/// with `minimumLevel: .info` does not create that feedback loop.
@Suite("Instant diagnostic feedback loop")
struct InstantDiagnosticFeedbackLoopTests {
  /// Events that were observed flooding Tailnet dual-write while idle.
  static let highFrequencyRoutineEvents: Set<String> = [
    "outbox.flush.started",
    "outbox.flush.finished",
    "outbox.mutation.send",
    "query-once.started",
    "query-once.completed",
    "transaction.started",
    "transaction.optimistic-commit",
    "websocket.message-sent",
  ]

  @Test("routine outbox and query diagnostics stay below info for dual-write hosts")
  func routineDiagnosticsStayBelowInfo() async throws {
    let cacheURL = try temporaryDiagnosticFeedbackCacheURL()
    defer { try? FileManager.default.removeItem(at: cacheURL.deletingLastPathComponent()) }

    let liveSession = LiveReactorParitySession(messages: [
      liveReactorInitOK(attrs: liveReactorTodoServerAttrs)
    ])

    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "diag-feedback-loop",
        persistenceURL: cacheURL,
        initialAttributes: TodoExample.attributes,
        liveTransport: liveSession.transport
      )
    )

    final class Box: @unchecked Sendable {
      var infoOrHigherHighFrequency: [String] = []
      let lock = NSLock()
      func append(_ event: String) {
        lock.lock()
        infoOrHigherHighFrequency.append(event)
        lock.unlock()
      }
      var snapshot: [String] {
        lock.lock()
        defer { lock.unlock() }
        return infoOrHigherHighFrequency
      }
    }
    let box = Box()
    let token = InstantDiagnostics.shared.addHandler { entry in
      guard Self.highFrequencyRoutineEvents.contains(entry.event) else { return }
      // Host bridges that dual-write to Instant typically use minimumLevel `.info`.
      guard entry.level.priorityBridgeComparable(to: .info) else { return }
      box.append(entry.event)
    }
    defer { InstantDiagnostics.shared.removeHandler(token) }

    let createdAt = InstantTimestamp(milliseconds: 1_700_000_100_000)
    // One large-ish mutation (many todos) then connect so flush/send path runs.
    let operations = (0..<40).flatMap { index in
      TodoExample.createOperations(
        id: "todo-diag-\(index)",
        text: "feedback",
        createdAt: createdAt,
        transactionID: "tx-diag-batch"
      )
    }
    try await runtime.transact(
      InstantStoreTransaction(id: "tx-diag-batch", operations: operations),
      createdAt: createdAt
    )
    _ = try await runtime.connect()
    // Local query-once path
    _ = try await runtime.queryOnce(TodoExample.query)

    // Allow async flush diagnostics to land.
    try await Task.sleep(for: .milliseconds(50))

    let leaked = box.snapshot
    #expect(
      leaked.isEmpty,
      """
      High-frequency routine diagnostics reached info+ handlers: \(leaked).
      Host dual-write bridges will re-ingest these into Instant and thrash memory.
      Keep these events at debug/trace.
      """
    )
  }

  @Test("info-level dual-write handler does not re-enter on large local transact volume")
  func infoHandlerDoesNotAmplifyLargeTransactVolume() async throws {
    let cacheURL = try temporaryDiagnosticFeedbackCacheURL()
    defer { try? FileManager.default.removeItem(at: cacheURL.deletingLastPathComponent()) }

    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "diag-amplify",
        persistenceURL: cacheURL,
        initialAttributes: TodoExample.attributes
      )
    )

    final class Counter: @unchecked Sendable {
      var handlerFires = 0
      let lock = NSLock()
      func inc() {
        lock.lock()
        handlerFires += 1
        lock.unlock()
      }
    }
    let counter = Counter()
    // Simulate Scribe bridge: only info+.
    let token = InstantDiagnostics.shared.addHandler { entry in
      guard entry.level.priorityBridgeComparable(to: .info) else { return }
      guard entry.subsystem == "instant-swift-data-core" else { return }
      counter.inc()
    }
    defer { InstantDiagnostics.shared.removeHandler(token) }

    let baseline = InstantProcessMemory.sample()?.physicalFootprintBytes ?? 0
    let createdAt = InstantTimestamp(milliseconds: 1_700_000_200_000)
    for batch in 0..<8 {
      let operations = (0..<30).flatMap { index in
        TodoExample.createOperations(
          id: "todo-amp-\(batch)-\(index)",
          text: String(repeating: "w", count: 64),
          createdAt: InstantTimestamp(milliseconds: createdAt.milliseconds + Int64(batch)),
          transactionID: "tx-amp-\(batch)"
        )
      }
      try await runtime.transact(
        InstantStoreTransaction(id: "tx-amp-\(batch)", operations: operations),
        createdAt: InstantTimestamp(milliseconds: createdAt.milliseconds + Int64(batch))
      )
    }
    let after = InstantProcessMemory.sample()?.physicalFootprintBytes ?? baseline
    let growth = after > baseline ? after - baseline : 0
    let fires = counter.handlerFires

    // With demoted routine events, an info-level dual-write handler should almost
    // never fire on pure local transact volume. Allow a small number for any
    // remaining notice/error paths; fail hard if each transact multiplies events.
    #expect(
      fires < 16,
      "info dual-write handler fired \(fires) times on local transacts — feedback risk"
    )
    // Not a multi-GB thrash budget; catches pathological amplification.
    #expect(
      growth < 512 * 1_024 * 1_024,
      "physical footprint grew \(growth) bytes under local batch transacts"
    )
  }
}

extension InstantDiagnosticLevel {
  /// Same ordering as host bridges (InstantDBLogger bridgeInstantDiagnostics).
  fileprivate func priorityBridgeComparable(to minimum: InstantDiagnosticLevel) -> Bool {
    priorityValue >= minimum.priorityValue
  }

  fileprivate var priorityValue: Int {
    switch self {
    case .trace: 0
    case .debug: 1
    case .info: 2
    case .notice: 3
    case .warning: 4
    case .error: 5
    case .critical: 6
    }
  }
}

private func temporaryDiagnosticFeedbackCacheURL() throws -> URL {
  let directory = FileManager.default.temporaryDirectory
    .appendingPathComponent("InstantDiagnosticFeedbackLoopTests-\(UUID().uuidString)")
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  return directory.appendingPathComponent("state.sqlite")
}
