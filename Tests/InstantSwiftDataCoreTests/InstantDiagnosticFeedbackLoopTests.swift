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
///
/// This suite uses **production Scribe namespaces** and **guest auth** (not the
/// TodoExample toy path) so release demotion cannot pass without the Scribe
/// shape that dual-writes in the field.
@Suite("Instant diagnostic feedback loop", .serialized)
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
      liveReactorInitOK(
        attrs: liveReactorServerAttrs(from: ScribeProductionShapedSchema.attributes)
      )
    ])

    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "diag-feedback-loop-scribe",
        persistenceURL: cacheURL,
        initialAttributes: ScribeProductionShapedSchema.attributes,
        makeID: { UUID().uuidString.lowercased() },
        guestAuthenticator: .local,
        liveTransport: liveSession.transport
      )
    )
    let session = try await runtime.signInAsGuest()
    #expect(session.userID.isEmpty == false)
    #expect(session.isGuest == true)

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
    // Production-namespace batch (recordings + transcriptions), then connect so flush runs.
    var operations: [InstantTripleOperation] = []
    for index in 0..<20 {
      let recordingID = "rec-diag-\(index)"
      let transcriptionID = "tx-diag-\(index)"
      operations.append(
        contentsOf: ScribeProductionShapedSchema.createRecordingOperations(
          id: recordingID,
          title: "diag \(index)",
          updatedAt: createdAt,
          transactionID: "tx-diag-batch"
        )
      )
      operations.append(
        contentsOf: ScribeProductionShapedSchema.createTranscriptionOperations(
          id: transcriptionID,
          recordingID: recordingID,
          wordCount: 4,
          updatedAt: createdAt,
          transactionID: "tx-diag-batch",
          transcriptText: "word",
          segmentCount: 1
        )
      )
    }
    try await runtime.transact(
      InstantStoreTransaction(id: "tx-diag-batch", operations: operations),
      createdAt: createdAt
    )
    _ = try await runtime.connect()
    _ = try await runtime.queryOnce(
      InstantQueryPlan(
        id: "diag.query-once.recordings",
        namespace: ScribeProductionShapedSchema.recordingNamespace,
        limit: 5
      )
    )

    try await Task.sleep(for: .milliseconds(50))

    let leaked = box.snapshot
    #expect(
      leaked.isEmpty,
      """
      High-frequency routine diagnostics reached info+ handlers: \(leaked). \
      Guest-auth Scribe production namespaces dual-write hosts will re-ingest \
      these into Instant debugLogs and thrash memory. Keep these events at debug/trace.
      """
    )
  }

  @Test("info-level dual-write handler does not re-enter on large local transact volume")
  func infoHandlerDoesNotAmplifyLargeTransactVolume() async throws {
    let cacheURL = try temporaryDiagnosticFeedbackCacheURL()
    defer { try? FileManager.default.removeItem(at: cacheURL.deletingLastPathComponent()) }

    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "diag-amplify-scribe",
        persistenceURL: cacheURL,
        initialAttributes: ScribeProductionShapedSchema.attributes,
        makeID: { UUID().uuidString.lowercased() },
        guestAuthenticator: .local
      )
    )
    _ = try await runtime.signInAsGuest()

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
      var operations: [InstantTripleOperation] = []
      for index in 0..<12 {
        let recordingID = "rec-amp-\(batch)-\(index)"
        let transcriptionID = "tx-amp-\(batch)-\(index)"
        let now = InstantTimestamp(milliseconds: createdAt.milliseconds + Int64(batch))
        operations.append(
          contentsOf: ScribeProductionShapedSchema.createRecordingOperations(
            id: recordingID,
            title: String(repeating: "w", count: 32),
            updatedAt: now,
            transactionID: "tx-amp-\(batch)"
          )
        )
        operations.append(
          contentsOf: ScribeProductionShapedSchema.createTranscriptionOperations(
            id: transcriptionID,
            recordingID: recordingID,
            wordCount: 2,
            updatedAt: now,
            transactionID: "tx-amp-\(batch)",
            transcriptText: "amp",
            segmentCount: 1
          )
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

    #expect(
      fires < 16,
      "info dual-write handler fired \(fires) times on guest-auth Scribe local transacts — feedback risk"
    )
    #expect(
      growth < 512 * 1_024 * 1_024,
      "physical footprint grew \(growth) bytes under Scribe-namespace local batch transacts"
    )
  }

  @Test("guest-auth Scribe dual Instant debugLogs thrash stays demoted at info bridge")
  func guestAuthScribeDualInstantDebugLogsThrashStaysDemoted() async throws {
    // End-to-end demotion proof: guest auth + production graph + second Instant
    // debugLogs store. An info bridge that would dual-write high-frequency
    // events must see zero leaks and must not enqueue debugLogs batches.
    let mainCache = try temporaryDiagnosticFeedbackCacheURL(prefix: "main")
    let debugCache = try temporaryDiagnosticFeedbackCacheURL(prefix: "debugLogs")
    defer {
      try? FileManager.default.removeItem(at: mainCache.deletingLastPathComponent())
      try? FileManager.default.removeItem(at: debugCache.deletingLastPathComponent())
    }

    let mainRuntime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "diag-dual-main",
        persistenceURL: mainCache,
        initialAttributes: ScribeProductionShapedSchema.attributes,
        makeID: { UUID().uuidString.lowercased() },
        guestAuthenticator: .local
      )
    )
    let debugRuntime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "diag-dual-debugLogs",
        persistenceURL: debugCache,
        initialAttributes: ScribeProductionShapedSchema.debugLogsAttributes,
        makeID: { UUID().uuidString.lowercased() },
        guestAuthenticator: .local
      )
    )
    let session = try await mainRuntime.signInAsGuest()
    #expect(session.isGuest == true)
    _ = try await debugRuntime.signInAsGuest()

    final class Box: @unchecked Sendable {
      var leaks = 0
      var batches = 0
      let lock = NSLock()
      func leak() {
        lock.lock()
        leaks += 1
        lock.unlock()
      }
      func batch() {
        lock.lock()
        batches += 1
        lock.unlock()
      }
    }
    let box = Box()
    let token = InstantDiagnostics.shared.addHandler { entry in
      guard Self.highFrequencyRoutineEvents.contains(entry.event) else { return }
      guard entry.level.priorityBridgeComparable(to: .info) else { return }
      box.leak()
      // If demotion regressed, dual-write a multi-attr debugLogs batch into the
      // second Instant store — the field thrash unit.
      Task {
        box.batch()
        let n = box.batches
        let now = InstantTimestamp(milliseconds: 1_700_400_000_000 + Int64(n))
        var operations: [InstantTripleOperation] = []
        for entity in 0..<8 {
          operations.append(
            contentsOf: ScribeProductionShapedSchema.createDebugLogOperations(
              id: "leak-\(n)-\(entity)",
              batchIndex: n,
              entityIndex: entity,
              updatedAt: now,
              transactionID: "debug-log-batch-leak-\(n)"
            )
          )
        }
        try? await debugRuntime.transact(
          InstantStoreTransaction(id: "debug-log-batch-leak-\(n)", operations: operations),
          createdAt: now
        )
      }
    }
    defer { InstantDiagnostics.shared.removeHandler(token) }

    let now = InstantTimestamp(milliseconds: 1_700_400_100_000)
    var operations: [InstantTripleOperation] = []
    for index in 0..<16 {
      let recordingID = "dual-rec-\(index)"
      operations.append(
        contentsOf: ScribeProductionShapedSchema.createRecordingOperations(
          id: recordingID,
          title: "dual \(index)",
          updatedAt: now,
          transactionID: "dual-tx"
        )
      )
      operations.append(
        contentsOf: ScribeProductionShapedSchema.createTranscriptionOperations(
          id: "dual-tx-\(index)",
          recordingID: recordingID,
          wordCount: 3,
          updatedAt: now,
          transactionID: "dual-tx",
          transcriptText: "dual",
          segmentCount: 1
        )
      )
    }
    try await mainRuntime.transact(
      InstantStoreTransaction(id: "dual-tx", operations: operations),
      createdAt: now
    )
    for index in 0..<8 {
      _ = try await mainRuntime.queryOnce(
        InstantQueryPlan(
          id: "dual.query.\(index)",
          namespace: ScribeProductionShapedSchema.recordingNamespace,
          limit: 5
        )
      )
    }
    try await Task.sleep(for: .milliseconds(80))

    #expect(
      box.leaks == 0,
      """
      Guest-auth Scribe demotion leaked \(box.leaks) info+ high-frequency events \
      and enqueued \(box.batches) debugLogs thrash batches into the second Instant store.
      """
    )
    #expect(box.batches == 0)
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

private func temporaryDiagnosticFeedbackCacheURL(prefix: String = "default") throws -> URL {
  let directory = FileManager.default.temporaryDirectory
    .appendingPathComponent("InstantDiagnosticFeedbackLoopTests-\(prefix)-\(UUID().uuidString)")
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  return directory.appendingPathComponent("state.sqlite")
}
