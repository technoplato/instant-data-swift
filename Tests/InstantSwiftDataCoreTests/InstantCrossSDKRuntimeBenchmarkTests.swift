import CustomDump
import Foundation
import Testing

@testable import InstantSwiftDataCore

@Suite(.serialized)
struct InstantCrossSDKRuntimeBenchmarkTests {
  @Test
  func runtimeComparisonProducesEveryPinnedDurableWorkload() async throws {
    let cacheURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("InstantCrossSDKRuntimeBenchmarkTests-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: cacheURL) }
    let clock = RuntimeBenchmarkNanosecondClock(step: 100)

    let result = try await InstantSwiftDataCrossSDKRuntimeBenchmarks.run(
      appID: "cross-sdk-runtime-test",
      iterations: 2,
      cacheDirectory: cacheURL,
      clockNanoseconds: { clock.next() }
    )

    expectNoDifference(result.suite, "cross-sdk-runtime")
    expectNoDifference(result.transport, "sqlite-local-runtime")
    expectNoDifference(result.iterations, 2)
    expectNoDifference(result.ok, true)
    expectNoDifference(result.finalTodoCount, 1)
    expectNoDifference(result.pendingMutationCount, 0)
    expectNoDifference(
      result.metrics.map { $0.name },
      InstantCrossSDKRuntimeBenchmarkContract.metricNames
    )
    expectNoDifference(
      result.metrics.flatMap { metric in metric.samples.map { $0.durationNanoseconds } },
      Array(repeating: 100, count: 6)
    )
    #expect(result.metrics.flatMap { $0.samples }.allSatisfy { ($0.actorHopCount ?? 0) > 0 })
    expectNoDifference(
      result.metrics.first { $0.name == "pending-mutation-enqueue.update" }?
        .samples.map { $0.pendingMutationCount },
      [1, 1]
    )
    expectNoDifference(
      result.metrics.first { $0.name == "offline-restore.relaunch" }?
        .samples.map { $0.pendingMutationCount },
      [1, 1]
    )
    expectNoDifference(
      result.metrics.first { $0.name == "reconnect-outbox-drain" }?
        .samples.map { $0.pendingMutationCount },
      [0, 0]
    )
  }

  /// Every actor call and unstructured task on the three workloads, pinned (#403). An added await on any of these
  /// paths changes a count here; ADR 0018 maps each hop to the line that makes it and what it protects.
  @Test
  func runtimeWorkloadsPinEveryActorHop() async throws {
    let cacheURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("InstantCrossSDKRuntimeBenchmarkHopTests-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: cacheURL) }

    let result = try await InstantSwiftDataCrossSDKRuntimeBenchmarks.run(
      appID: "cross-sdk-runtime-hop-test",
      iterations: 2,
      cacheDirectory: cacheURL
    )

    // transact: the gate, one persistence turn of reads, the store's prepare, one turn for the save and the status
    // it changed, the store's commit, the status publish, and the gate. The 12 persistence awaits were 2 turns.
    let enqueue: [String: Int] = [
      "operation-gate": 2,
      "persistence": 2,
      "store": 2,
      "observers": 1,
    ]
    // Relaunch: one turn to open the store, the live-result prune, the first connection status and auth session
    // inside the gate (#1132: status reads and observations answer without the gate after it), then a query without the
    // gate (#1134: one turn of reads, the store's attribute index, a local observation's answer, the query-cache save)
    // and the pending mutations (one turn, inside the gate). The save of the store's first answer is two turns (#1498):
    // one finds no row holding it, then the answer is encoded on the reader's task, not the persistence actor, and the
    // second writes it; an unchanged answer is one turn and no encode.
    let relaunch: [String: Int] = [
      "operation-gate": 4,
      "persistence": 7,
      "store": 4,
    ]
    // Reconnect and drain: connect saves the opened state and reads the status in one turn; the explicit flush claims
    // in one turn, confirms, then settles in one turn. Its five tasks are unchanged.
    let drain: [String: Int] = [
      "connection-gate": 2,
      "mutation-flush-gate": 2,
      "mutation-transport": 1,
      "observers": 2,
      "operation-gate": 6,
      "outbox": 2,
      "persistence": 4,
      "reconnect-controller": 1,
      "task": 5,
    ]
    expectNoDifference(
      result.metrics.map { metric in metric.samples.map(\.actorHopBreakdown) },
      [[enqueue, enqueue], [relaunch, relaunch], [drain, drain]]
    )
    expectNoDifference(
      result.metrics.map { metric in metric.samples.map(\.actorHopCount) },
      [[7, 7], [15, 15], [25, 25]]
    )

    // A server refresh restating a 50-row list (#1494), six persistence turns: the frame's seed; its plan in two (the
    // restated result's retractions and saves, the retractions' protection and the reduction's context in one turn,
    // then the plan's begin; a plan that holds no pending write reads no body page); then, holding the gate, the
    // catch-up, the commit, and the plan's end with the connection status. It took twelve: each of the four reads in a
    // turn of its own, an empty body page each way, the plan's end and the status read apart.
    let refresh = try await Self.serverRefreshHops()
    let refreshHops: [String: Int] = ["observers": 1, "operation-gate": 4, "outbox": 1, "persistence": 6, "store": 4]
    expectNoDifference(refresh.breakdown, refreshHops, "\(refresh.breakdown)")

    // The same refresh over a pending local write on its first row, which the plan holds as a body: its first reverse
    // page is read in the plan's begin, and each pass stops at the page that held its last row. Eight persistence
    // turns: the six above, a forward page and its stage. Without, the reverse pass read its page and then an empty one,
    // and the forward pass an empty page after its stage.
    let overLocalWrite = try await Self.serverRefreshHops(overPendingLocalWrite: true)
    let overLocalWriteHops: [String: Int] = [
      "observers": 1, "operation-gate": 4, "outbox": 1, "persistence": 8, "store": 4,
    ]
    expectNoDifference(overLocalWrite.breakdown, overLocalWriteHops, "\(overLocalWrite.breakdown)")
  }

  /// The actor hops of one refresh-ok restating a 50-row todos list that the store already holds, one row changed,
  /// and, with `overPendingLocalWrite`, a local text update of that row still pending beneath it.
  static func serverRefreshHops(overPendingLocalWrite: Bool = false) async throws -> InstantActorHopSummary {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("InstantCrossSDKRuntimeBenchmarkServerRefresh-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let recorder = InstantActorHopRecorder()
    var configuration = InstantRuntimeConfiguration(
      appID: "cross-sdk-runtime-server-refresh",
      persistenceURL: directory.appendingPathComponent("state.sqlite"),
      initialAttributes: TodoExample.attributes
    )
    configuration.actorHopRecorder = recorder
    let runtime = try await InstantRuntime.bootstrap(configuration: configuration)
    let query = try InstantLiveQueryEncoder.encode(TodoExample.query)
    func refresh(_ frame: Int, changedText: String) -> InstantLiveRefreshOK {
      let createdAt = InstantTimestamp(milliseconds: 1_700_000_494_000)
      let rows: [InstantLiveJSONValue] = (0..<50).map { row in
        let id = "refresh-todo-\(row)"
        let text = row == 0 ? changedText : "row \(row)"
        func fact(_ attribute: String, _ value: InstantLiveJSONValue) -> InstantLiveJSONValue {
          .array([.string(id), .string(attribute), value, .number(Double(createdAt.milliseconds + Int64(frame)))])
        }
        return .array([
          fact("server-todos-id", .string(id)),
          fact("server-todos-text", .string(text)),
          fact("server-todos-is-completed", .bool(false)),
          fact("server-todos-created-at", .number(Double(createdAt.milliseconds + Int64(row)))),
        ])
      }
      let result: InstantLiveJSONValue = .object([
        "data": .object(["datalog-result": .object(["join-rows": .array(rows)])]),
        "child-nodes": .array([]),
      ])
      return InstantLiveRefreshOK(
        clientEventID: nil,
        processedTransactionID: "server-refresh-\(frame)",
        attrs: liveReactorTodoServerAttrs,
        computations: [.object(["instaql-query": query, "instaql-result": .array([result])])]
      )
    }
    _ = try await runtime.applyLiveRefresh(refresh(1, changedText: "first"))
    if overPendingLocalWrite {
      let transactionID = "server-refresh-local-write"
      _ = try await runtime.transact(
        InstantStoreTransaction(
          id: transactionID,
          operations: TodoExample.updateTextOperations(
            id: "refresh-todo-0",
            text: "local",
            updatedAt: InstantTimestamp(milliseconds: 1_700_000_495_000),
            transactionID: transactionID
          )
        )
      )
    }
    let baseline = recorder.baseline()
    _ = try await runtime.applyLiveRefresh(refresh(2, changedText: "restated"))
    return recorder.summary(since: baseline)
  }

  @Test
  func contractPinsEquivalentRuntimeOperationCounts() {
    expectNoDifference(InstantCrossSDKRuntimeBenchmarkContract.version, 1)
    expectNoDifference(InstantCrossSDKRuntimeBenchmarkContract.mutationCount, 1)
  }
}

// SAFETY: mutation is protected by `lock`.
private final class RuntimeBenchmarkNanosecondClock: @unchecked Sendable {
  private let lock = NSLock()
  private let step: UInt64
  private var nanoseconds: UInt64 = 0

  init(step: UInt64) {
    self.step = step
  }

  func next() -> UInt64 {
    lock.lock()
    defer { lock.unlock() }
    nanoseconds += step
    return nanoseconds
  }
}
