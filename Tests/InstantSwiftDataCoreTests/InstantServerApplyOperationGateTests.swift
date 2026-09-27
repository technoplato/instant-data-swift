import CustomDump
import Foundation
import Testing

@testable import InstantSwiftDataCore

/// #277. After a reconnect, server apply finished its plan under the operation gate while a local
/// transact queued behind it: an iPhone with 439 pending mutations held the gate 5,632 ms and one
/// transact waited 5,057 ms (Scribe device pull, 2026-09-27 13:53:47). A local write is local
/// materialization plus a durable outbox row; it must not wait on server catch-up.
@Suite(.serialized)
struct InstantServerApplyOperationGateTests {
  /// A thousand pending sections linked to one recording, as after a reconnect, then a server
  /// write to that recording: every pending mutation is in the plan's component. A new section is
  /// written every 25 ms throughout. Before the fix the component closure and the outbox rewrite
  /// were quadratic in that component and ran under the operation gate; a local write waited
  /// seconds behind them.
  @Test func localTransactsDoNotWaitBehindAServerApplyOverAHubComponent() async throws {
    let fixture = try await OperationGateFixture.make(suffix: "hub", pendingCount: 1_000)
    let timelines = GateTimelineRecorder(correlationID: fixture.serverTransactionID)
    let token = InstantDiagnostics.shared.addHandler { entry in
      Task { await timelines.record(entry) }
    }
    defer { InstantDiagnostics.shared.removeHandler(token) }

    let writer = ContinuousSegmentWriter(runtime: fixture.runtime, recordingID: fixture.recordingID)
    await writer.start()
    let result = try await fixture.runtime.applyServerTransaction(fixture.serverTransaction)
    try await Task.sleep(for: .milliseconds(100))
    let written = await writer.stop()
    let timeline = try await timelines.waitForFirst()
    let longestLocalWrite = written.latencies.max() ?? 0
    let heldMilliseconds = Int(timeline["heldMilliseconds"] ?? "") ?? .max
    print(
      """
      server-apply operation gate: held \(heldMilliseconds) ms \
      (catch up \(timeline["catchUpMilliseconds"] ?? "?"), commit \(timeline["commitMilliseconds"] ?? "?"), \
      patch \(timeline["patchMilliseconds"] ?? "?")); \(written.latencies.count) local writes, \
      longest \(longestLocalWrite) ms
      """
    )

    #expect(!written.latencies.isEmpty)
    #expect(longestLocalWrite < 2_000)
    #expect(heldMilliseconds < 2_000)
    expectNoDifference(result.syncState.processedTransactionID, fixture.serverTransactionID)

    let state = try await fixture.runtime.persistence.loadState()
    expectNoDifference(
      state.snapshot.store.triples.first {
        $0.entityID == fixture.recordingID && $0.attributeID == "recordings/title"
      }?.value,
      .string("server")
    )
    let outboxIDs = Set(state.snapshot.outbox.map(\.id))
    expectNoDifference(outboxIDs.filter { $0.hasPrefix("pending-") }.count, 1_000)
    expectNoDifference(written.mutationIDs.filter { !outboxIDs.contains($0) }, [])
    let storedLiveSegments = Set(
      state.snapshot.store.triples
        .filter { $0.attributeID == "segments/recording" && $0.entityID.hasPrefix("live-segment-") }
        .map(\.entityID)
    )
    expectNoDifference(storedLiveSegments.count, written.mutationIDs.count)
  }
}

// MARK: - Fixture

private let operationGateAttributes: [InstantAttribute] = [
  InstantAttribute(id: "recordings/title", namespace: "recordings", name: "title", valueType: .string, isRequired: false),
  InstantAttribute(id: "segments/text", namespace: "segments", name: "text", valueType: .string, isRequired: false),
  InstantAttribute(
    id: "segments/recording",
    namespace: "segments",
    name: "recording",
    valueType: .ref,
    cardinality: .one,
    isIndexed: true,
    forwardIdentity: "segments/recording",
    reverseIdentity: "recordings/segments",
    linkNamespace: "recordings"
  ),
  InstantAttribute(id: "notes/value", namespace: "notes", name: "value", valueType: .string, isRequired: false),
]

/// About the size of a Scribe transcript section with its words JSON.
private let sectionPayload = String(repeating: "word ", count: 500)

private struct OperationGateFixture {
  var runtime: InstantRuntime
  var recordingID: String
  var serverTransactionID: String
  var serverTransaction: InstantStoreTransaction

  static func make(suffix: String, pendingCount: Int, baseTripleCount: Int = 4_000) async throws -> Self {
    let recordingID = "gate-recording"
    let cacheURL = FileManager.default.temporaryDirectory.appendingPathComponent(
      "instant-operation-gate-\(suffix)-\(UUID().uuidString).sqlite"
    )
    let persistence = try SQLitePersistenceStore(
      fileURL: cacheURL,
      declaredAttributes: operationGateAttributes
    )
    try await persistence.bootstrap()

    let seedTime = InstantTimestamp(milliseconds: 1)
    var triples: [InstantTriple] = [
      InstantTriple(entityID: recordingID, attributeID: "recordings/title", value: .string("base"), txID: "seed", txTime: seedTime)
    ]
    for index in 0..<baseTripleCount {
      triples.append(
        InstantTriple(entityID: "note-\(index)", attributeID: "notes/value", value: .string("note \(index)"), txID: "seed", txTime: seedTime)
      )
    }
    var outbox: [PendingMutation] = []
    for index in 0..<pendingCount {
      let mutationID = "pending-\(String(format: "%05d", index))"
      let segmentID = "segment-\(String(format: "%05d", index))"
      let time = InstantTimestamp(milliseconds: Int64(index) + 2)
      let segmentTriples = [
        InstantTriple(entityID: segmentID, attributeID: "segments/text", value: .string(sectionPayload), txID: mutationID, txTime: time),
        InstantTriple(entityID: segmentID, attributeID: "segments/recording", value: .ref(recordingID), txID: mutationID, txTime: time),
      ]
      triples.append(contentsOf: segmentTriples)
      var mutation = PendingMutation(
        id: mutationID,
        createdAt: time,
        transaction: InstantStoreTransaction(id: mutationID, operations: segmentTriples.map(InstantTripleOperation.insert)),
        status: .pending
      )
      mutation.rollbackTransaction = InstantStoreTransaction(
        id: "rollback-\(mutationID)",
        operations: [.deleteEntity(segmentID)]
      )
      mutation.optimisticOverlayState = .applied
      mutation.optimisticEffectReceiptVersion = PendingMutation.currentOptimisticEffectReceiptVersion
      outbox.append(mutation)
    }
    try await persistence.saveStoreSnapshot(
      InstantStoreSnapshot(attributes: operationGateAttributes, triples: triples)
    )
    let seeded = try await persistence.loadCompactState()
    let saved = try await persistence.saveOutbox(
      outbox,
      replacing: [],
      metadataEntries: [],
      expectedStoreRevision: seeded.storeRevision,
      expectedOutboxRevision: seeded.outboxRevision
    )
    #expect(saved)

    let configuration = InstantRuntimeConfiguration(
      appID: "operation-gate-\(suffix)",
      persistenceURL: cacheURL,
      initialAttributes: operationGateAttributes
    )
    let runtime = try await InstantRuntime.bootstrap(configuration: configuration)
    let serverTransactionID = "server-refresh-\(suffix)-\(UUID().uuidString)"
    let serverTransaction = InstantStoreTransaction(
      id: serverTransactionID,
      operations: [
        .insert(
          InstantTriple(
            entityID: recordingID,
            attributeID: "recordings/title",
            value: .string("server"),
            txID: serverTransactionID,
            txTime: InstantTimestamp(milliseconds: 1)
          )
        )
      ]
    )
    return Self(
      runtime: runtime,
      recordingID: recordingID,
      serverTransactionID: serverTransactionID,
      serverTransaction: serverTransaction
    )
  }
}

/// Writes one new section every 25 ms, as a live Scribe recording does, and records how long each
/// local transact took.
private actor ContinuousSegmentWriter {
  private let runtime: InstantRuntime
  private let recordingID: String
  private var task: Task<Void, Never>?
  private var latencies: [Int] = []
  private var mutationIDs: [String] = []

  init(runtime: InstantRuntime, recordingID: String) {
    self.runtime = runtime
    self.recordingID = recordingID
  }

  func start() {
    let runtime = runtime
    let recordingID = recordingID
    task = Task { [weak self] in
      var index = 0
      while !Task.isCancelled {
        let segmentID = "live-segment-\(index)"
        let mutationID = "live-\(index)"
        let started = ContinuousClock.now
        do {
          _ = try await runtime.transact(
            InstantStoreTransaction(
              id: mutationID,
              operations: [
                .insert(InstantTriple(entityID: segmentID, attributeID: "segments/text", value: .string(sectionPayload), txID: mutationID, txTime: InstantTimestamp(milliseconds: 1_000_000 + Int64(index)))),
                .insert(InstantTriple(entityID: segmentID, attributeID: "segments/recording", value: .ref(recordingID), txID: mutationID, txTime: InstantTimestamp(milliseconds: 1_000_000 + Int64(index)))),
              ]
            )
          )
        } catch {
          break
        }
        await self?.record(
          InstantServerApplyGateTimeline.milliseconds(from: started, to: ContinuousClock.now),
          mutationID: mutationID
        )
        index += 1
        try? await Task.sleep(for: .milliseconds(25))
      }
    }
  }

  private func record(_ milliseconds: Int, mutationID: String) {
    latencies.append(milliseconds)
    mutationIDs.append(mutationID)
  }

  func stop() async -> (latencies: [Int], mutationIDs: [String]) {
    task?.cancel()
    await task?.value
    return (latencies, mutationIDs)
  }
}

private actor GateTimelineRecorder {
  private let correlationID: String
  private var metadata: [String: String]?

  init(correlationID: String) {
    self.correlationID = correlationID
  }

  func record(_ entry: InstantDiagnosticEntry) {
    guard entry.event == "server-apply.operation-gate-held", entry.correlationID == correlationID else { return }
    metadata = entry.metadata
  }

  func waitForFirst(timeout: Duration = .seconds(5)) async throws -> [String: String] {
    let deadline = ContinuousClock.now.advanced(by: timeout)
    while metadata == nil {
      if ContinuousClock.now >= deadline { throw CancellationError() }
      try await Task.sleep(for: .milliseconds(5))
    }
    return metadata!
  }
}
