import CustomDump
import Dispatch
import Foundation
@testable import InstantSwiftDataCore
import Testing

/// A value shared between a test and the tasks and hooks it starts.
// SAFETY: `lock` guards `storage` for every read and write.
private final class PriorityTestBox<Value>: @unchecked Sendable {
  private let lock = NSLock()
  private var storage: Value

  init(_ value: Value) {
    storage = value
  }

  var value: Value {
    lock.withLock { storage }
  }

  func setValue(_ value: Value) {
    lock.withLock { storage = value }
  }

  func withValue<Result>(_ body: (inout Value) -> Result) -> Result {
    lock.withLock { body(&storage) }
  }
}

/// Runs on the persistence actor and keeps it busy until `release` is signalled, as a slow disk kept the iPhone's
/// SQLite reads waiting in `pread` (freeze-185).
private func occupyPersistence(
  _ persistence: isolated SQLitePersistenceStore,
  entered: PriorityTestBox<Bool>,
  until release: DispatchSemaphore
) {
  entered.setValue(true)
  _ = release.wait(timeout: .now() + 20)
}

private func waitFor(
  _ what: String,
  within timeout: Duration = .seconds(10),
  _ condition: () async -> Bool
) async throws {
  let deadline = ContinuousClock.now + timeout
  while await !condition() {
    guard ContinuousClock.now < deadline else {
      Issue.record("Timed out waiting for \(what)")
      return
    }
    try await Task.sleep(for: .milliseconds(10))
  }
}

/// freeze-185 item 2 (#473): the operation gate served callers first come, first served, so a transcript write queued
/// behind server catch-ups, hydrations and listings; a 331 s catch-up on the Mac logged a critical stall line every 5 s.
/// Callers now queue by priority, a waiter that waited long enough moves up, and a holder is reported once.
@Suite(.serialized)
struct InstantOperationGatePriorityTests {
  // MARK: - The gate

  @Test
  func aHolderPastTheStallThresholdIsReportedOnceHoweverLongItHolds() async throws {
    let stalls = PriorityTestBox<[AsyncSerialGate.StallReport]>([])
    let gate = AsyncSerialGate(
      label: "test",
      stallThresholdMilliseconds: 30,
      report: { report in stalls.withValue { $0.append(report) } }
    )
    await gate.enter(operation: "long holder")
    let waiter = Task.detached {
      await gate.enter(operation: "waiter")
      await gate.leave()
    }
    try await waitFor("the waiter to queue") { await gate.waiterCount == 1 }
    try await Task.sleep(for: .milliseconds(400))
    await gate.leave()
    await waiter.value
    expectNoDifference(stalls.value.count, 1, "one stall report per holder, not one every threshold")
  }
}

// MARK: - The runtime

extension InstantOperationGatePriorityTests {
  /// A local write queued after an outbox listing goes first: the listing is background work no caller waits on.
  @Test
  func aLocalWriteGoesAheadOfAnOutboxListingQueuedBeforeIt() async throws {
    let releaseHeld = AsyncStream<Void>.makeStream()
    let heldPaused = AsyncStream<Void>.makeStream()
    let runtime = try await InstantOfflineRuntimeFixture.offlineRuntime("priority-listing") { configuration in
      configuration.onLocalMutationPersistedBeforeStorePublicationForTesting = { transactionID in
        guard transactionID == "tx-held" else { return }
        heldPaused.continuation.yield()
        var iterator = releaseHeld.stream.makeAsyncIterator()
        _ = await iterator.next()
      }
    }
    let waits = PriorityTestBox<[InstantDiagnosticEntry]>([])
    // Other suites' runtimes report their own operation gates at the same time, so only this runtime's count.
    let token = InstantDiagnostics.shared.addHandler { entry in
      guard entry.event == "serial-gate.waited", entry.metadata["gate"] == "operation",
        entry.metadata["owner"] == "offline-priority-listing"
      else { return }
      waits.withValue { $0.append(entry) }
    }
    defer { InstantDiagnostics.shared.removeHandler(token) }

    let held = Task { try await InstantOfflineRuntimeFixture.createTodo("held", in: runtime) }
    var paused = heldPaused.stream.makeAsyncIterator()
    _ = await paused.next()
    let listing = Task { await runtime.failedMutations() }
    try await waitFor("the listing to queue") { await runtime.operationGateWaiterCountForTesting() == 1 }
    let write = Task { try await InstantOfflineRuntimeFixture.createTodo("second", in: runtime) }
    try await waitFor("the write to queue") { await runtime.operationGateWaiterCountForTesting() == 2 }
    // Both wait past the 250 ms report threshold, so each handoff is reported.
    try await Task.sleep(for: .milliseconds(400))
    releaseHeld.continuation.yield()
    try await held.value
    _ = await listing.value
    try await write.value

    let operations: Set<String> = ["transact(_:createdAt:source:)", "durableOutboxMutations(statuses:fallback:)"]
    try await waitFor("both handoffs to be reported") {
      waits.value.filter { operations.contains($0.metadata["waitingOperation"] ?? "") }.count >= 2
    }
    // The first handoff left one caller queued, the second none.
    let order = waits.value
      .filter { operations.contains($0.metadata["waitingOperation"] ?? "") }
      .sorted { Int($0.metadata["remainingWaiterCount"] ?? "0")! > Int($1.metadata["remainingWaiterCount"] ?? "0")! }
      .compactMap { $0.metadata["waitingOperation"] }
    expectNoDifference(order, ["transact(_:createdAt:source:)", "durableOutboxMutations(statuses:fallback:)"])
  }

  /// A local write's observers refresh after it leaves the operation gate: while its publication is held up, another
  /// caller of the gate runs (#473).
  @Test
  func aLocalWritesObserversRefreshAfterItLeavesTheGate() async throws {
    let runtime = try await InstantOfflineRuntimeFixture.offlineRuntime("publish-after-gate")
    let observation = await runtime.observe(TodoExample.query)
    var iterator = observation.makeAsyncIterator()
    _ = await iterator.next()
    let transactionID = "tx-\(UUID().uuidString)"
    let publishing = PriorityTestBox(false)
    let releasePublication = DispatchSemaphore(value: 0)
    // The publication's line runs this handler on the store's thread, so blocking here holds the publication.
    let token = InstantDiagnostics.shared.addHandler { entry in
      guard entry.event == "store.mutation-published", entry.correlationID == transactionID else { return }
      publishing.setValue(true)
      _ = releasePublication.wait(timeout: .now() + 20)
    }
    defer { InstantDiagnostics.shared.removeHandler(token) }

    let createdAt = InstantTimestamp(milliseconds: 1_700_000_000_000)
    let write = Task {
      try await runtime.transact(
        InstantStoreTransaction(
          id: transactionID,
          operations: TodoExample.createOperations(
            id: "todo-published",
            text: "published",
            createdAt: createdAt,
            transactionID: transactionID
          )
        ),
        createdAt: createdAt
      )
    }
    try await waitFor("the write to publish") { publishing.value }
    let status = PriorityTestBox(false)
    let probe = Task {
      _ = try await runtime.connectionStatus()
      status.setValue(true)
    }
    for _ in 0..<200 where !status.value {
      try await Task.sleep(for: .milliseconds(10))
    }
    let ranDuringThePublication = status.value
    releasePublication.signal()
    _ = try await write.value
    try await probe.value
    #expect(ranDuringThePublication, "the connection status waited for the write's publication")
  }

  /// A hydration's SQLite read does not hold the operation gate: while SQLite is busy, a local write takes the gate
  /// instead of queueing behind the read (#473; on the iPhone a hydrate held the gate in `pread` with seven callers
  /// queued).
  @Test
  func aHydrationsSQLiteReadDoesNotHoldTheOperationGate() async throws {
    let fixture = GateHydrationFixture()
    let cacheURL = try fixture.temporaryCacheURL("hydration-read")
    defer { try? FileManager.default.removeItem(at: cacheURL.deletingLastPathComponent()) }
    try await fixture.seed(cacheURL, rows: [(id: "chunk-a", title: "A", payload: fixture.payload("a"))])
    let runtimeBox = PriorityTestBox<InstantRuntime?>(nil)
    let claimed = PriorityTestBox(false)
    let persistenceBusy = PriorityTestBox(false)
    let releasePersistence = DispatchSemaphore(value: 0)
    let probe = PriorityTestBox<Task<Void, any Error>?>(nil)
    var configuration = fixture.configuration(appID: "gate-hydration-read", cacheURL: cacheURL)
    configuration.onDeferredQueryEmissionHydrationStartingForTesting = { _ in
      guard let runtime = runtimeBox.value, claimed.withValue({ wasClaimed in
        defer { wasClaimed = true }
        return !wasClaimed
      }) else { return }
      let persistence = runtime.persistence
      Task.detached { await occupyPersistence(persistence, entered: persistenceBusy, until: releasePersistence) }
      for _ in 0..<1_000 where !persistenceBusy.value {
        try? await Task.sleep(for: .milliseconds(5))
      }
      // A transcript write arrives while the hydration waits for SQLite.
      probe.setValue(
        Task {
          let createdAt = InstantTimestamp(milliseconds: 1_700_000_000_100)
          _ = try await runtime.transact(
            InstantStoreTransaction(
              id: "tx-probe",
              operations: [
                .insert(
                  InstantTriple(
                    entityID: "chunk-b",
                    attributeID: fixture.idAttribute.id,
                    value: .string("chunk-b"),
                    txID: "tx-probe",
                    txTime: createdAt
                  )
                ),
                .insert(
                  InstantTriple(
                    entityID: "chunk-b",
                    attributeID: fixture.titleAttribute.id,
                    value: .string("B"),
                    txID: "tx-probe",
                    txTime: createdAt
                  )
                ),
              ]
            ),
            createdAt: createdAt
          )
        }
      )
    }
    let runtime = try await InstantRuntime.bootstrap(configuration: configuration)
    runtimeBox.setValue(runtime)
    let stream = await runtime.observe(
      fixture.pageQuery(id: "gate-hydration-read", selectedFields: [fixture.titleAttribute.name, fixture.samplesAttribute.name])
    )
    let results = PriorityTestBox<[InstantQueryEmission]>([])
    let consumer = Task {
      for await emission in stream {
        results.withValue { $0.append(emission) }
      }
    }
    try await waitFor("the probe write to start") { probe.value != nil }
    try await Task.sleep(for: .milliseconds(300))
    let queued = await runtime.operationGateWaiterCountForTesting()
    releasePersistence.signal()
    try await probe.value?.value
    try await waitFor("the hydrated row") {
      results.value.contains { $0.values.first?.values[fixture.samplesAttribute.name] == .one(.json(fixture.payload("a"))) }
    }
    consumer.cancel()
    expectNoDifference(queued, 0, "a caller queued behind the hydration's SQLite read")
  }
}

extension InstantOperationGatePriorityTests {
  fileprivate static func renameChunk(
    _ fixture: GateHydrationFixture,
    title: String,
    payload: JSONValue,
    transactionID: String
  ) -> InstantStoreTransaction {
    let createdAt = InstantTimestamp(milliseconds: 1_700_000_000_200)
    func insert(_ attributeID: String, _ value: InstantValue) -> InstantTripleOperation {
      .insert(InstantTriple(entityID: "chunk-a", attributeID: attributeID, value: value, txID: transactionID, txTime: createdAt))
    }
    return InstantStoreTransaction(
      id: transactionID,
      operations: [
        .requireEntityExists(entityID: "chunk-a", namespace: fixture.namespace),
        insert(fixture.titleAttribute.id, .string(title)),
        insert(fixture.samplesAttribute.id, .json(payload)),
      ]
    )
  }

  /// A write saved to SQLite but not yet committed to the store when a hydration reads: the read sees the new samples
  /// while the emission still has the old title, so the emission must not be delivered with them (#473). Every
  /// delivered row pairs a title with its own samples, and the last one is the write's.
  @Test
  func aHydrationNeverPairsAnEmissionWithAWriteSavedDuringItsRead() async throws {
    let fixture = GateHydrationFixture()
    let cacheURL = try fixture.temporaryCacheURL("hydration-pairing")
    defer { try? FileManager.default.removeItem(at: cacheURL.deletingLastPathComponent()) }
    try await fixture.seed(cacheURL, rows: [(id: "chunk-a", title: "A", payload: fixture.payload("a"))])
    let runtimeBox = PriorityTestBox<InstantRuntime?>(nil)
    let claimed = PriorityTestBox(false)
    let writePaused = PriorityTestBox(false)
    let releaseWrite = AsyncStream<Void>.makeStream()
    let write = PriorityTestBox<Task<Void, any Error>?>(nil)
    var configuration = fixture.configuration(appID: "gate-hydration-pairing", cacheURL: cacheURL)
    configuration.onLocalMutationPersistedBeforeStorePublicationForTesting = { transactionID in
      guard transactionID == "tx-rename" else { return }
      writePaused.setValue(true)
      var iterator = releaseWrite.stream.makeAsyncIterator()
      _ = await iterator.next()
    }
    configuration.onDeferredQueryEmissionHydrationStartingForTesting = { _ in
      guard let runtime = runtimeBox.value, claimed.withValue({ wasClaimed in
        defer { wasClaimed = true }
        return !wasClaimed
      }) else { return }
      // The write saves its new title and samples, then pauses before the store commits them.
      write.setValue(
        Task {
          _ = try await runtime.transact(
            Self.renameChunk(fixture, title: "A2", payload: fixture.payload("a2"), transactionID: "tx-rename")
          )
        }
      )
      for _ in 0..<1_000 where !writePaused.value {
        try? await Task.sleep(for: .milliseconds(5))
      }
    }
    let runtime = try await InstantRuntime.bootstrap(configuration: configuration)
    runtimeBox.setValue(runtime)
    let stream = await runtime.observe(
      fixture.pageQuery(id: "gate-hydration-pairing", selectedFields: [fixture.titleAttribute.name, fixture.samplesAttribute.name])
    )
    let rows = PriorityTestBox<[(title: InstantMaterializedValue?, samples: InstantMaterializedValue?)]>([])
    let consumer = Task {
      for await emission in stream {
        guard let row = emission.values.first else { continue }
        rows.withValue {
          $0.append((row.values[fixture.titleAttribute.name], row.values[fixture.samplesAttribute.name]))
        }
      }
    }
    try await waitFor("the write to pause after its save") { writePaused.value }
    // The hydration has read the saved samples; let the write commit.
    try await Task.sleep(for: .milliseconds(200))
    releaseWrite.continuation.yield()
    try await write.value?.value
    try await waitFor("the write's row") { rows.value.last?.title == .one(.string("A2")) }
    consumer.cancel()
    let oldTitle = InstantMaterializedValue.one(.string("A"))
    let newSamples = InstantMaterializedValue.one(.json(fixture.payload("a2")))
    let mismatched = rows.value.filter { $0.title == oldTitle && $0.samples == newSamples }.count
    expectNoDifference(mismatched, 0, "an emission paired the old title with the write's samples")
    expectNoDifference(rows.value.last?.samples, newSamples)
  }
}

/// A route-chunk store whose samples are deferred values, as Scribe's are.
private struct GateHydrationFixture {
  let namespace = "routeChunks"
  let idAttribute = InstantAttribute.primaryKey(namespace: "routeChunks")
  let titleAttribute = InstantAttribute(
    id: "routeChunks/title",
    namespace: "routeChunks",
    name: "title",
    valueType: .string,
    isIndexed: true
  )
  let samplesAttribute = InstantAttribute(
    id: "routeChunks/samplesJSON",
    namespace: "routeChunks",
    name: "samplesJSON",
    valueType: .json
  )

  var attributes: [InstantAttribute] {
    [idAttribute, titleAttribute, samplesAttribute]
  }

  func payload(_ marker: String) -> JSONValue {
    .string(marker + String(repeating: "-route-sample", count: 512))
  }

  func pageQuery(id: String, selectedFields: [String]) -> InstantQueryPlan {
    InstantQueryPlan(
      id: id,
      namespace: namespace,
      order: InstantQueryOrder(titleAttribute.name),
      limit: 1,
      selectedFields: selectedFields
    )
  }

  func temporaryCacheURL(_ name: String) throws -> URL {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("InstantOperationGatePriorityTests-\(name)-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory.appendingPathComponent("state.sqlite")
  }

  func configuration(appID: String, cacheURL: URL) -> InstantRuntimeConfiguration {
    InstantRuntimeConfiguration(
      appID: appID,
      persistenceURL: cacheURL,
      initialAttributes: attributes,
      deferredValueResidency: InstantDeferredValueResidencyPolicy(attributeIDs: [samplesAttribute.id])
    )
  }

  func seed(_ cacheURL: URL, rows: [(id: String, title: String, payload: JSONValue)]) async throws {
    let persistence = try SQLitePersistenceStore(fileURL: cacheURL)
    try await persistence.bootstrap()
    var triples: [InstantTriple] = []
    for (offset, row) in rows.enumerated() {
      let timestamp = InstantTimestamp(milliseconds: Int64(offset + 1))
      triples.append(
        InstantTriple(entityID: row.id, attributeID: idAttribute.id, value: .string(row.id), txID: "seed-\(row.id)", txTime: timestamp)
      )
      triples.append(
        InstantTriple(entityID: row.id, attributeID: titleAttribute.id, value: .string(row.title), txID: "seed-\(row.id)", txTime: timestamp)
      )
      triples.append(
        InstantTriple(entityID: row.id, attributeID: samplesAttribute.id, value: .json(row.payload), txID: "seed-\(row.id)", txTime: timestamp)
      )
    }
    try await persistence.saveStoreSnapshot(InstantStoreSnapshot(attributes: attributes, triples: triples))
  }
}

// MARK: - Needs v1.9.7's API: the red run on v1.9.6 drops everything below this line.

extension InstantOperationGatePriorityTests {
  @Test
  func aHigherPriorityWaiterTakesTheGateFirst() async throws {
    let gate = AsyncSerialGate(label: "test")
    let order = PriorityTestBox<[String]>([])
    await gate.enter(operation: "holder")
    let background = Task.detached {
      await gate.enter(operation: "server apply", priority: .background)
      order.withValue { $0.append("server apply") }
      await gate.leave()
    }
    try await waitFor("the server apply to queue") { await gate.waiterCount == 1 }
    let interactive = Task.detached {
      await gate.enter(operation: "transcript write", priority: .interactive)
      order.withValue { $0.append("transcript write") }
      await gate.leave()
    }
    try await waitFor("the write to queue") { await gate.waiterCount == 2 }
    await gate.leave()
    await background.value
    await interactive.value
    expectNoDifference(order.value, ["transcript write", "server apply"])
  }

  @Test
  func aWaiterThatWaitedPastTheAgingIntervalGoesAheadOfNewerInteractiveOnes() async throws {
    let gate = AsyncSerialGate(label: "test", agingMilliseconds: 100)
    let order = PriorityTestBox<[String]>([])
    await gate.enter(operation: "holder")
    let background = Task.detached {
      await gate.enter(operation: "server apply", priority: .background)
      order.withValue { $0.append("server apply") }
      await gate.leave()
    }
    try await waitFor("the server apply to queue") { await gate.waiterCount == 1 }
    // Two aging intervals: the background waiter now ranks with an interactive one, and it is older.
    try await Task.sleep(for: .milliseconds(250))
    let interactive = Task.detached {
      await gate.enter(operation: "transcript write", priority: .interactive)
      order.withValue { $0.append("transcript write") }
      await gate.leave()
    }
    try await waitFor("the write to queue") { await gate.waiterCount == 2 }
    await gate.leave()
    await background.value
    await interactive.value
    expectNoDifference(order.value, ["server apply", "transcript write"])
  }

  @Test
  func waitersOfOnePriorityKeepTheirOrder() async throws {
    let gate = AsyncSerialGate(label: "test")
    let order = PriorityTestBox<[Int]>([])
    await gate.enter(operation: "holder")
    var tasks: [Task<Void, Never>] = []
    for index in 0..<4 {
      tasks.append(
        Task.detached {
          await gate.enter(operation: "write \(index)", priority: .interactive)
          order.withValue { $0.append(index) }
          await gate.leave()
        }
      )
      try await waitFor("write \(index) to queue") { await gate.waiterCount == index + 1 }
    }
    await gate.leave()
    for task in tasks { await task.value }
    expectNoDifference(order.value, [0, 1, 2, 3])
  }

  @Test
  func theSnapshotNamesTheHolderItsPhaseAndTheQueueWithoutAHop() async throws {
    let gate = AsyncSerialGate(label: "test")
    expectNoDifference(gate.snapshot.holder, nil)
    await gate.enter(operation: "holder")
    gate.markHolderPhase("save")
    let waiter = Task.detached {
      await gate.enter(operation: "waiter")
      await gate.leave()
    }
    try await waitFor("the waiter to queue") { await gate.waiterCount == 1 }
    let snapshot = gate.snapshot
    expectNoDifference(snapshot.holder, "holder")
    expectNoDifference(snapshot.holderPhase, "save")
    expectNoDifference(snapshot.waiterCount, 1)
    #expect(snapshot.heldSince != nil)
    #expect(snapshot.longestWaitingSince != nil)
    await gate.leave()
    await waiter.value
    try await waitFor("the gate to be free") { gate.snapshot.holder == nil }
    expectNoDifference(gate.snapshot.waiterCount, 0)
  }

  /// A write that lands after a hydration's read and before its check: the emission it read for is stale, so it is
  /// dropped, and the write's emission is hydrated instead (#473).
  @Test
  func aWriteBetweenAnUngatedReadAndItsCheckDropsTheStaleEmission() async throws {
    let fixture = GateHydrationFixture()
    let cacheURL = try fixture.temporaryCacheURL("hydration-recheck")
    defer { try? FileManager.default.removeItem(at: cacheURL.deletingLastPathComponent()) }
    try await fixture.seed(cacheURL, rows: [(id: "chunk-a", title: "A", payload: fixture.payload("a"))])
    let runtimeBox = PriorityTestBox<InstantRuntime?>(nil)
    let claimed = PriorityTestBox(false)
    var configuration = fixture.configuration(appID: "gate-hydration-recheck", cacheURL: cacheURL)
    configuration.onDeferredValuesReadWithoutOperationGateForTesting = { _ in
      guard let runtime = runtimeBox.value, claimed.withValue({ wasClaimed in
        defer { wasClaimed = true }
        return !wasClaimed
      }) else { return }
      _ = try? await runtime.transact(
        Self.renameChunk(fixture, title: "A2", payload: fixture.payload("a2"), transactionID: "tx-recheck")
      )
    }
    let runtime = try await InstantRuntime.bootstrap(configuration: configuration)
    runtimeBox.setValue(runtime)
    let stream = await runtime.observe(
      fixture.pageQuery(id: "gate-hydration-recheck", selectedFields: [fixture.titleAttribute.name, fixture.samplesAttribute.name])
    )
    let first = await withTaskGroup(of: InstantQueryEmission?.self) { group in
      group.addTask {
        for await emission in stream where emission.values.first?.values[fixture.samplesAttribute.name] != nil {
          return emission
        }
        return nil
      }
      group.addTask {
        try? await Task.sleep(for: .seconds(10))
        return nil
      }
      let first = await group.next() ?? nil
      group.cancelAll()
      return first
    }
    #expect(claimed.value, "the write landed between the read and the check")
    let row = try #require(first?.values.first)
    expectNoDifference(row.values[fixture.titleAttribute.name], .one(.string("A2")))
    expectNoDifference(row.values[fixture.samplesAttribute.name], .one(.json(fixture.payload("a2"))))
  }

  // MARK: - The store's publications

  static func todoPrepared(
    _ store: InstantStore,
    id: String,
    text: String,
    transactionID: String
  ) async throws -> PreparedStoreMutation {
    let createdAt = InstantTimestamp(milliseconds: 1_700_000_000_000)
    return try await store.prepareCurrent(
      InstantStoreTransaction(
        id: transactionID,
        operations: TodoExample.upsertOperations(
          id: id,
          text: text,
          createdAt: createdAt,
          transactionID: transactionID
        )
      )
    )
  }

  /// Two commits before the publication are published together, once, and both commits get its emissions.
  @Test
  func commitsBeforeAPublicationArePublishedTogetherOnce() async throws {
    let store = InstantStore(snapshot: InstantStoreSnapshot(attributes: TodoExample.attributes, triples: []))
    let observation = await store.observe(TodoExample.query)
    var iterator = observation.makeAsyncIterator()
    _ = await iterator.next()

    let first = try await Self.todoPrepared(store, id: "todo-1", text: "one", transactionID: "tx-1")
    let firstCommit = await store.commitDeferringPublication(first)
    let second = try await Self.todoPrepared(store, id: "todo-2", text: "two", transactionID: "tx-2")
    let secondCommit = await store.commitDeferringPublication(second)
    let firstTicket = try #require(firstCommit.publication)
    let secondTicket = try #require(secondCommit.publication)
    expectNoDifference(firstTicket, secondTicket, "the second commit joins the pending publication")

    let firstEmissions = await store.publishCommittedChanges(firstTicket)
    let secondEmissions = await store.publishCommittedChanges(secondTicket)
    expectNoDifference(firstEmissions, secondEmissions)
    expectNoDifference(firstEmissions.first?.values.map(\.id).sorted(), ["todo-1", "todo-2"])
    let published = await iterator.next()
    expectNoDifference(published?.values.map(\.id).sorted(), ["todo-1", "todo-2"])
  }

  /// A reader that asks whether a query was refreshed sees a committed change that was not published yet.
  @Test
  func aRefreshCheckPublishesCommittedChangesFirst() async throws {
    let store = InstantStore(snapshot: InstantStoreSnapshot(attributes: TodoExample.attributes, triples: []))
    let observation = await store.observe(TodoExample.query)
    var iterator = observation.makeAsyncIterator()
    let initial = await iterator.next()
    let initialSequence = try #require(initial?.sequence)

    let prepared = try await Self.todoPrepared(store, id: "todo-1", text: "one", transactionID: "tx-1")
    let committed = await store.commitDeferringPublication(prepared)
    let refreshed = await store.wasRefreshed(queryID: TodoExample.query.id, after: initialSequence)
    #expect(refreshed, "the pending publication refreshed the query")
    let ticket = try #require(committed.publication)
    let emissions = await store.publishCommittedChanges(ticket)
    expectNoDifference(emissions.first?.values.map(\.id), ["todo-1"], "the ticket still redeems its emissions")
  }

  @Test
  func everyCommitStillLogsItsPublishedLineWithThePublicationsMetrics() async throws {
    let store = InstantStore(snapshot: InstantStoreSnapshot(attributes: TodoExample.attributes, triples: []))
    let observation = await store.observe(TodoExample.query)
    var iterator = observation.makeAsyncIterator()
    _ = await iterator.next()
    let ids = (UUID().uuidString, UUID().uuidString)
    let lines = PriorityTestBox<[InstantDiagnosticEntry]>([])
    let token = InstantDiagnostics.shared.addHandler { entry in
      guard entry.event == "store.mutation-published",
        entry.correlationID == ids.0 || entry.correlationID == ids.1
      else { return }
      lines.withValue { $0.append(entry) }
    }
    defer { InstantDiagnostics.shared.removeHandler(token) }

    let first = try await Self.todoPrepared(store, id: "todo-1", text: "one", transactionID: ids.0)
    let firstCommitted = await store.commitDeferringPublication(first)
    let firstTicket = try #require(firstCommitted.publication)
    let second = try await Self.todoPrepared(store, id: "todo-2", text: "two", transactionID: ids.1)
    _ = await store.commitDeferringPublication(second)
    _ = await store.publishCommittedChanges(firstTicket)

    expectNoDifference(lines.value.compactMap(\.correlationID), [ids.0, ids.1])
    expectNoDifference(lines.value.map { $0.metadata["publicationCommitCount"] }, ["2", "2"])
    expectNoDifference(lines.value.map(\.level), [.info, .info])
  }

  /// A watchdog reads what holds the gate without waiting for it.
  @Test
  func theRuntimesGateSnapshotNamesAHeldWriteAndItsPhase() async throws {
    let releaseHeld = AsyncStream<Void>.makeStream()
    let heldPaused = AsyncStream<Void>.makeStream()
    let runtime = try await InstantOfflineRuntimeFixture.offlineRuntime("gate-snapshot") { configuration in
      configuration.onLocalMutationPersistedBeforeStorePublicationForTesting = { transactionID in
        guard transactionID == "tx-held" else { return }
        heldPaused.continuation.yield()
        var iterator = releaseHeld.stream.makeAsyncIterator()
        _ = await iterator.next()
      }
    }
    expectNoDifference(runtime.operationGateSnapshot(), InstantOperationGateSnapshot(holder: nil))
    let held = Task { try await InstantOfflineRuntimeFixture.createTodo("held", in: runtime) }
    var paused = heldPaused.stream.makeAsyncIterator()
    _ = await paused.next()
    let queued = Task { try await InstantOfflineRuntimeFixture.createTodo("queued", in: runtime) }
    try await waitFor("the second write to queue") { runtime.operationGateSnapshot().waiterCount == 1 }
    let snapshot = runtime.operationGateSnapshot()
    expectNoDifference(snapshot.holder, "transact(_:createdAt:source:)")
    expectNoDifference(snapshot.holderPhase, "save")
    #expect(snapshot.heldSince != nil)
    #expect(snapshot.longestWaitingSince != nil)
    releaseHeld.continuation.yield()
    try await held.value
    try await queued.value
    try await waitFor("the gate to be free") { runtime.operationGateSnapshot().holder == nil }
  }

  /// Apple's SQLite commits a WAL connection with `synchronous` NORMAL, so a write under the gate pays no fsync; only a
  /// checkpoint syncs (#473, freeze-185 item 3).
  @Test
  func theStoresConnectionCommitsWithoutAnFsync() async throws {
    let runtime = try await InstantOfflineRuntimeFixture.offlineRuntime("durability")
    let synchronous = try await runtime.persistence.synchronousSettingForTesting()
    expectNoDifference(synchronous, "1")
  }

  @Test
  func thePublicationSummaryReportsAWindowOnceItsIntervalPassed() {
    var summary = InstantStorePublicationSummary()
    let start = ContinuousClock.now
    summary.record(commitCount: 2, metrics: InstantStorePublishMetrics(splicedObserverCount: 1), duration: .milliseconds(20))
    summary.record(commitCount: 1, metrics: InstantStorePublishMetrics(rematerializedObserverCount: 3), duration: .milliseconds(150))
    // takeIfDue mutates, and #expect evaluates its argument on a copy, so each call comes first.
    let early = summary.takeIfDue(now: start + .seconds(5), interval: .seconds(30))
    #expect(early == nil)
    let window = summary.takeIfDue(now: start + .seconds(31), interval: .seconds(30))
    expectNoDifference(window?.publicationCount, 2)
    expectNoDifference(window?.commitCount, 3)
    expectNoDifference(window?.slowPublicationCount, 1)
    expectNoDifference(window?.metrics.splicedObserverCount, 1)
    expectNoDifference(window?.metrics.rematerializedObserverCount, 3)
    expectNoDifference(window?.maximumDuration, .milliseconds(150))
    let empty = summary.takeIfDue(now: start + .seconds(70), interval: .seconds(30))
    #expect(empty == nil, "an empty window is not reported")
  }
}
