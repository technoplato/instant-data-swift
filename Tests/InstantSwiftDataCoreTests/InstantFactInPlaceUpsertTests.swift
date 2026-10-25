// History:
// - 2026-10-24: added (#1120): a re-saved entity's facts are updated where their rows are. INSERT OR REPLACE deleted
//   each row and inserted it again under a new rowid at the table's end, moving its key's entry too: 9-15 pages per
//   transcript line on a copy of the phone's store, where an in-place upsert writes 3.
// - 2026-10-25: the facts live in a table keyed by the fact itself (#1121): a re-saved entity writes the one leaf its
//   facts share, and there is no separate key index to write.

import CustomDump
import Foundation
import SQLite3
import Testing

@testable import InstantSwiftDataCore

extension StorageIOExercises {
  /// A write that names every attribute of an entity again, as Scribe's open-segment writes do, with the same values
  /// and a new transaction's stamp (#1120, #1121): the save writes the one page the entity's facts share, and no other
  /// fact b-tree. 400 todos come first, so the first todo's facts are pages away from the table's end, where
  /// `INSERT OR REPLACE` moved them. In the suite, which runs one test at a time: the shim's counters are the process's.
  @Test
  func aReSavedEntityWritesOnlyTheLeafItsFactsShare() async throws {
    StorageIOCounters.install(asDefault: false)
    let directory = try InstantTestScratch.directory("fact-upsert-in-place")
    StorageIOCounters.watch(directory: directory)
    defer { StorageIOCounters.watch(directory: nil) }
    let store = directory.appendingPathComponent("store.sqlite")
    let runtime = try await SQLitePersistenceStore.$connectionVFSForTesting.withValue(StorageIOCounters.vfsName) {
      try await CheckpointCadence.runtime(store)
    }
    for index in 0..<400 { _ = try await CheckpointCadence.write(index, on: runtime) }

    // The same values under a new transaction: every fact's stamp changes, none of its keys.
    let before = StorageIOCounters.snapshot()
    try await runtime.transact(
      InstantStoreTransaction(
        id: "re-save",
        operations: TodoExample.upsertOperations(
          id: "todo-line-0000",
          text: "line-0000",
          createdAt: InstantTimestamp(milliseconds: 1_790_700_000_000),
          transactionID: "re-save"
        )
      ),
      createdAt: InstantTimestamp(milliseconds: 1_790_800_000_000)
    )
    let written = StorageIOCounters.snapshot().subtracting(before)
    let factFrames = try StorageIOPageMap.read(store: store).byName(written.walFramesByPage).filter {
      $0.key.contains("instant_triples")
    }

    expectNoDifference(try FactRows.transactionIDs(store, entityID: "todo-line-0000"), ["re-save"])
    #expect(factFrames.keys.sorted() == ["instant_triples"], "fact b-trees the save wrote: \(factFrames)")
    #expect((factFrames["instant_triples"] ?? 0) <= 1, "the entity's facts share one page: \(factFrames)")
  }
}

/// A fact's columns as SQLite holds them.
enum FactRows {
  /// The distinct transaction ids of `entityID`'s facts.
  static func transactionIDs(_ store: URL, entityID: String) throws -> [String] {
    var connection: OpaquePointer?
    guard sqlite3_open_v2(store.path, &connection, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
      defer { sqlite3_close_v2(connection) }
      throw StorageIOError("open \(store.lastPathComponent)")
    }
    defer { sqlite3_close_v2(connection) }
    var statement: OpaquePointer?
    let sql = "SELECT DISTINCT tx_id FROM instant_triples WHERE entity_id = ? ORDER BY tx_id"
    guard sqlite3_prepare_v2(connection, sql, -1, &statement, nil) == SQLITE_OK else {
      throw StorageIOError(String(cString: sqlite3_errmsg(connection)))
    }
    defer { sqlite3_finalize(statement) }
    sqlite3_bind_text(statement, 1, entityID, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
    var ids: [String] = []
    while sqlite3_step(statement) == SQLITE_ROW {
      ids.append(String(cString: sqlite3_column_text(statement, 0)))
    }
    return ids
  }
}
