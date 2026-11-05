// History:
// - 2026-11-04: added (#1500): a closed query's stored result is unloaded where it is, without a whole-result copy.

import CustomDump
import Foundation
import SQLite3
import Testing

@testable import InstantSwiftDataCore

/// A closed query's stored result is unloaded where it is (#1500).
///
/// The session prune copied each closed result whole into `instant_unloaded_live_query_results` (its facts' values as JSON),
/// deleted its row and ownership rows, and deleted from SQLite and memory every entity no other result owned; reopening
/// read the copy back and wrote the rows and facts again. On a phone's store the copies were 207 MB, 65.5% of their facts
/// duplicates of another copy's and 89% no longer in `instant_triples`, and the copy, release and reload writers wrote
/// 145-308 MB an hour while recording (2026-10-30 and 31).
///
/// Upstream `PersistedObject.unloadKey` "unloads the key so that it can be garbage collected, but does not delete it": a
/// closed query's stored copy stays as it is until the limits collect it, and only memory lets it go. Here the stored
/// result is its row and its ownership rows (#1426), so unloading marks the row, its facts stay on disk, memory releases
/// what nothing open shows (#1145), and a write to a released entity reads it from disk first (#1165).
@Suite(.serialized, .timeLimit(.minutes(2)))
struct InstantUnloadInPlaceTests {
  @Test
  func aClosedResultIsUnloadedWhereItIsWithoutACopy() async throws {
    let url = try InstantStoredResultReloadTests.temporaryCacheURL()
    let session = LiveReactorParitySession(messages: [liveReactorInitOK(attrs: liveReactorTodoServerAttrs)])
    var configuration = InstantRuntimeConfiguration(
      appID: "unload-in-place",
      persistenceURL: url,
      initialAttributes: TodoExample.attributes,
      liveTransport: session.transport
    )
    configuration.liveReconnectSleep = { _ in }
    let runtime = try await InstantRuntime.bootstrap(configuration: configuration)

    // Another query stays open throughout, so the prune below is the session prune that runs while the app is in use.
    let keepAlive = await runtime.observeQueryLease(InstantStoredResultReloadTests.keepAliveTodosQuery)
    _ = try await runtime.connect()
    let keepAliveQuery = try await InstantStoredResultReloadTests.registeredQuery(number: 1, in: session)
    await session.enqueue(
      liveReactorAddQueryOK(
        query: keepAliveQuery,
        processedTransactionID: "tx-keep-alive",
        result: InstantStoredResultReloadTests.todoResult([("todo-keep", "keep", 10)])
      )
    )
    let list = await runtime.observeQueryLease(TodoExample.query)
    let listQuery = try await InstantStoredResultReloadTests.registeredQuery(number: 2, in: session)
    await session.enqueue(
      liveReactorAddQueryOK(
        query: listQuery,
        processedTransactionID: "tx-list",
        result: InstantStoredResultReloadTests.todoResult([("todo-1", "one", 1), ("todo-2", "two", 2), ("todo-3", "three", 3)])
      )
    )
    _ = try await InstantStoredResultReloadTests.emission(of: list.stream, operation: "show the server's list") {
      Set(["todo-1", "todo-2", "todo-3"]).isSubset(of: $0.values.map(\.id))
    }
    await list.cancel()
    try await InstantStoredResultReloadTests.waitForOp("remove-query", count: 1, in: session)

    _ = try await runtime.pruneLiveQueryResults(
      policy: InstantStoredResultReloadTests.productionPolicy,
      now: InstantStoredResultReloadTests.pruneTime
    )

    #expect(try Self.scalar(url, "SELECT COUNT(*) FROM instant_unloaded_live_query_results") == 0, "no whole-result copy")
    #expect(
      try Self.scalar(url, "SELECT COUNT(*) FROM instant_live_query_results") == 2,
      "the closed result keeps its row beside the open one's"
    )
    #expect(
      try Self.scalar(url, "SELECT COUNT(*) FROM instant_live_query_triples WHERE entity_id IN ('todo-1', 'todo-2', 'todo-3')")
        == 12,
      "the closed result keeps its ownership rows"
    )
    #expect(
      try Self.scalar(url, "SELECT COUNT(*) FROM instant_triples WHERE entity_id IN ('todo-1', 'todo-2', 'todo-3')") == 12,
      "its facts stay on disk"
    )

    // Memory lets them go: only the open query's row is left there.
    let inMemory = await runtime.observeLocallyLease(TodoExample.query)
    let memoryEmission = try await InstantStoredResultReloadTests.emission(of: inMemory.stream, operation: "read memory") {
      _ in true
    }
    await inMemory.cancel()
    expectNoDifference(memoryEmission.values.map(\.id), ["todo-keep"])

    // The server answers nothing from here on: the reopened list answers from the rows kept on disk.
    let reopened = await runtime.observeQueryLease(TodoExample.query)
    let first = try await InstantStoredResultReloadTests.emission(of: reopened.stream, operation: "reopen the list") { _ in
      true
    }
    expectNoDifference(first.values.map(\.id), ["todo-1", "todo-2", "todo-3", "todo-keep"])

    await reopened.cancel()
    await keepAlive.cancel()
    _ = try await runtime.closeConnection()
  }

  /// The first column of `sql`'s first row, read straight from the SQLite file (the runtime holds its own connection).
  static func scalar(_ store: URL, _ sql: String) throws -> Int64 {
    var connection: OpaquePointer?
    guard sqlite3_open_v2(store.path, &connection, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
      defer { sqlite3_close_v2(connection) }
      throw StorageIOError("open \(store.lastPathComponent)")
    }
    defer { sqlite3_close_v2(connection) }
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(connection, sql, -1, &statement, nil) == SQLITE_OK else {
      throw StorageIOError(String(cString: sqlite3_errmsg(connection)))
    }
    defer { sqlite3_finalize(statement) }
    guard sqlite3_step(statement) == SQLITE_ROW else { throw StorageIOError("no row for \(sql)") }
    return sqlite3_column_int64(statement, 0)
  }
}
