import CustomDump
import Foundation
import SQLite3
import Testing

@testable import InstantSwiftDataCore

@Suite(.serialized)
struct InstantStartupTraceTests {
  @Test func runtimeBootstrapReportsOrderedLocalStartupPhases() async throws {
    let events = StartupTraceRecorder()
    let trace = InstantStartupTrace(id: "startup-test") { event in
      events.record(event)
    }
    let persistenceURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("instant-startup-trace-\(UUID().uuidString).sqlite")
    defer { try? FileManager.default.removeItem(at: persistenceURL) }
    var configuration = InstantRuntimeConfiguration(
      appID: "startup-trace-test",
      persistenceURL: persistenceURL
    )
    configuration.startupTrace = trace

    _ = try await InstantRuntime.bootstrap(configuration: configuration)

    expectNoDifference(
      events.values.map { "\($0.kind.rawValue):\($0.phase)" },
      [
        "started:runtime.bootstrap",
        "completed:runtime.validation",
        "started:sqlite.open",
        "completed:sqlite.open",
        "started:sqlite.schema",
        "completed:sqlite.schema",
        "started:sqlite.state-load",
        "completed:sqlite.state-load.attributes",
        "completed:sqlite.state-load.triples",
        "completed:sqlite.state-load.outbox",
        "completed:sqlite.state-load",
        "completed:runtime.store-materialization",
        "completed:runtime.attribute-store-merge",
        "completed:runtime.attribute-merge",
        "completed:runtime.services-scheduled",
        "completed:runtime.bootstrap",
      ]
    )
    let completedEvents = events.values.filter { $0.kind == .completed }
    #expect(completedEvents.allSatisfy { ($0.durationMilliseconds ?? -1) >= 0 })
  }

  @Test func queryObservationSeparatesStoreWaitFromLocalRegistration() async throws {
    let events = StartupTraceRecorder()
    let trace = InstantStartupTrace(id: "query-trace-test") { event in
      events.record(event)
    }
    let persistenceURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("instant-query-trace-\(UUID().uuidString).sqlite")
    defer { try? FileManager.default.removeItem(at: persistenceURL) }
    var configuration = InstantRuntimeConfiguration(
      appID: "query-trace-test",
      persistenceURL: persistenceURL,
      initialAttributes: TodoExample.attributes
    )
    configuration.startupTrace = trace
    let runtime = try await InstantRuntime.bootstrap(configuration: configuration)

    _ = await runtime.observe(TodoExample.query)

    expectNoDifference(
      events.values
        .filter { $0.phase.hasPrefix("query.") }
        .map { "\($0.kind.rawValue):\($0.phase)" },
      [
        "started:query.observe",
        "completed:query.schema-snapshot",
        "completed:query.local-registration",
        "completed:query.local-observer",
      ]
    )
  }

  @Test func persistenceOnlyReportsItsFirstStateLoadAsStartupWork() async throws {
    let events = StartupTraceRecorder()
    let trace = InstantStartupTrace(id: "state-load-trace-test") { event in
      events.record(event)
    }
    let persistenceURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("instant-state-load-trace-\(UUID().uuidString).sqlite")
    defer { try? FileManager.default.removeItem(at: persistenceURL) }
    let persistence = try SQLitePersistenceStore(
      fileURL: persistenceURL,
      startupTrace: trace
    )
    try await persistence.bootstrap()

    _ = try await persistence.loadState()
    _ = try await persistence.loadState()

    expectNoDifference(
      events.values
        .filter { $0.phase == "sqlite.state-load" }
        .map(\.kind),
      [.started, .completed]
    )
  }

  @Test func largeStoreStateLoadReportsEachPersistedCollection() async throws {
    let persistenceURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("instant-large-startup-\(UUID().uuidString).sqlite")
    defer { try? FileManager.default.removeItem(at: persistenceURL) }
    let seededPersistence = try SQLitePersistenceStore(fileURL: persistenceURL)
    try await seededPersistence.bootstrap()
    try await seededPersistence.saveStoreSnapshot(
      InstantStoreSnapshot(triples: largeStoreTriples(count: 20_000))
    )
    try await seededPersistence.saveOutbox(largeStoreOutbox(count: 500))

    let events = StartupTraceRecorder()
    let trace = InstantStartupTrace(id: "large-state-load-trace-test") { event in
      events.record(event)
    }
    var configuration = InstantRuntimeConfiguration(
      appID: "large-state-load-trace-test",
      persistenceURL: persistenceURL
    )
    configuration.startupTrace = trace

    let runtime = try await InstantRuntime.bootstrap(configuration: configuration)
    let state = try await runtime.persistence.loadState()

    #expect(state.snapshot.store.triples.count == 20_000)
    #expect(state.snapshot.outbox.count == 500)
    #expect(state.snapshot.store.triples.first?.entityID == "entity-00000000")
    #expect(state.snapshot.store.triples.last?.entityID == "entity-00019999")
    #expect(state.snapshot.outbox.first?.id == "pending-mutation-0")
    #expect(state.snapshot.outbox.last?.id == "pending-mutation-499")
    let collectionEvents = events.values.filter {
      $0.kind == .completed && $0.phase.hasPrefix("sqlite.state-load.")
    }
    expectNoDifference(
      collectionEvents.map(\.phase),
      [
        "sqlite.state-load.attributes",
        "sqlite.state-load.triples",
        "sqlite.state-load.outbox",
      ]
    )
    #expect(
      collectionEvents.allSatisfy {
        $0.metadata["decodeStrategy"] == "batched-json-array"
          && $0.metadata["decodeConcurrency"] == "2"
      }
    )
    for event in collectionEvents where event.metadata["count"] != "0" {
      let rowCount = try #require(Int(event.metadata["count", default: ""]))
      let batchCount = try #require(Int(event.metadata["decodeBatchCount", default: ""]))
      #expect(batchCount < rowCount)
    }
  }

  @Test func batchedStateLoadReportsMalformedRowRangeAndPath() async throws {
    let persistenceURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("instant-malformed-startup-\(UUID().uuidString).sqlite")
    defer { try? FileManager.default.removeItem(at: persistenceURL) }
    do {
      let seededPersistence = try SQLitePersistenceStore(fileURL: persistenceURL)
      try await seededPersistence.bootstrap()
      try await seededPersistence.saveStoreSnapshot(
        InstantStoreSnapshot(triples: largeStoreTriples(count: 2))
      )
    }
    try corruptSecondLargeStoreTripleJSON(at: persistenceURL)

    let events = StartupTraceRecorder()
    let trace = InstantStartupTrace(id: "malformed-state-load-trace-test") { event in
      events.record(event)
    }
    let persistence = try SQLitePersistenceStore(
      fileURL: persistenceURL,
      startupTrace: trace
    )
    try await persistence.bootstrap()

    do {
      _ = try await persistence.loadState()
      Issue.record("Expected the malformed persisted triple to fail the state load.")
    } catch let error as InstantError {
      expectNoDifference(error.code, .persistenceFailed)
      expectNoDifference(error.operation, "decode persisted JSON rows")
      #expect(error.message.contains("SQLite JSON rows 1-2 could not be decoded"))
      expectNoDifference(
        error.recovery,
        "Inspect the local SQLite cache at \(persistenceURL.path), then retry the command."
      )
    }
    let failure = try #require(
      events.values.first {
        $0.phase == "sqlite.state-load.triples" && $0.kind == .failed
      }
    )
    #expect(
      failure.metadata["errorDescription"]?.contains(
        "SQLite JSON rows 1-2 could not be decoded"
      ) == true
    )
  }

  @Test func copiedPhysicalStoreCanReportColdStartPhases() async throws {
    guard
      let fixturePath = ProcessInfo.processInfo.environment["INSTANT_COLD_START_FIXTURE"],
      !fixturePath.isEmpty
    else { return }

    let events = StartupTraceRecorder()
    let trace = InstantStartupTrace(id: "physical-cold-start") { event in
      events.record(event)
    }
    var configuration = InstantRuntimeConfiguration(
      appID: "physical-cold-start",
      persistenceURL: URL(fileURLWithPath: fixturePath)
    )
    configuration.startupTrace = trace

    let runtime = try await InstantRuntime.bootstrap(configuration: configuration)
    let state = try await runtime.persistence.loadState()

    print(
      "physical-cold-start attributes=\(state.snapshot.store.attributes.count) "
        + "triples=\(state.snapshot.store.triples.count) "
        + "outbox=\(state.snapshot.outbox.count)"
    )
    for event in events.values where event.kind == .completed {
      print(
        "physical-cold-start phase=\(event.phase) "
          + "durationMilliseconds=\(event.durationMilliseconds ?? -1) "
          + "elapsedMilliseconds=\(event.elapsedMilliseconds)"
      )
    }
  }

  @Test func startupCanReadAttributesAndSkipANoOpMergeWithoutMaterializingTriples() async {
    let store = InstantStore(
      snapshot: InstantStoreSnapshot(attributes: TodoExample.attributes)
    )

    let attributes = await store.attributeSnapshot()
    expectNoDifference(attributes, TodoExample.attributes.sorted { $0.id < $1.id })
    #expect(await store.mergeAttributesIfChanged(TodoExample.attributes) == nil)
  }
}

private func largeStoreTriples(count: Int) -> [InstantTriple] {
  (0..<count).map { index in
    InstantTriple(
      entityID: String(format: "entity-%08d", index),
      attributeID: "large-store/value",
      value: .string("value-\(index)"),
      txID: "transaction-\(index)",
      txTime: InstantTimestamp(milliseconds: Int64(index))
    )
  }
}

private func largeStoreOutbox(count: Int) -> [PendingMutation] {
  (0..<count).map { index in
    let triple = InstantTriple(
      entityID: "pending-entity-\(index)",
      attributeID: "large-store/value",
      value: .string("pending-value-\(index)"),
      txID: "pending-transaction-\(index)",
      txTime: InstantTimestamp(milliseconds: Int64(index))
    )
    return PendingMutation(
      id: "pending-mutation-\(index)",
      createdAt: InstantTimestamp(milliseconds: Int64(index)),
      transaction: InstantStoreTransaction(
        id: "pending-transaction-\(index)",
        operations: [.insert(triple)]
      )
    )
  }
}

private func corruptSecondLargeStoreTripleJSON(at url: URL) throws {
  var connection: OpaquePointer?
  guard
    sqlite3_open_v2(
      url.path,
      &connection,
      SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX,
      nil
    ) == SQLITE_OK,
    let connection
  else {
    defer { sqlite3_close(connection) }
    throw InstantError(
      code: .persistenceFailed,
      operation: "open malformed-row test database",
      message: connection.map { String(cString: sqlite3_errmsg($0)) }
        ?? "SQLite could not open \(url.path).",
      recovery: "Check the temporary test database."
    )
  }
  defer { sqlite3_close(connection) }
  sqlite3_busy_timeout(connection, 10_000)

  var errorMessage: UnsafeMutablePointer<CChar>?
  guard
    sqlite3_exec(
      connection,
      """
      UPDATE instant_triples
      SET json = 'not-json'
      WHERE entity_id = 'entity-00000001'
      """,
      nil,
      nil,
      &errorMessage
    ) == SQLITE_OK,
    sqlite3_changes(connection) == 1
  else {
    let message =
      errorMessage.map { String(cString: $0) }
      ?? String(cString: sqlite3_errmsg(connection))
    sqlite3_free(errorMessage)
    throw InstantError(
      code: .persistenceFailed,
      operation: "corrupt malformed-row test database",
      message: message,
      recovery: "Check the temporary test database."
    )
  }
}

private final class StartupTraceRecorder: @unchecked Sendable {
  private let lock = NSLock()
  private var storage: [InstantStartupTraceEvent] = []

  var values: [InstantStartupTraceEvent] {
    lock.withLock { storage }
  }

  func record(_ event: InstantStartupTraceEvent) {
    lock.withLock { storage.append(event) }
  }
}
