// History:
// - 2026-10-31: added (#1504): closing a query's result and a recording's writes write no temporary file of any kind,
//   the statement journal included.
// - 2026-11-05: closing a query's result marks its row where it is (#1500); the guard checks the prune unloaded it.

import CustomDump
import Foundation
import Testing

@testable import InstantSwiftDataCore

/// Where SQLite keeps each connection's temporary structures (#1504).
@Suite
struct InstantTemporaryStoreTests {
  /// The writer from the end of its bootstrap, and every read connection, keep them in memory: `temp_store` 2. The
  /// one-time migrations before it keep SQLite's file (one copies every fact's key into a temporary table, 647,723 keys
  /// on the 10-30 iPhone store), and the server apply's staging tables come after it, because a change of the setting
  /// drops every temporary table that exists.
  @Test
  func everyConnectionKeepsItsTemporaryStructuresInMemory() async throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("instant-temp-store-1504-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = try SQLitePersistenceStore(fileURL: directory.appendingPathComponent("store.sqlite"))
    try await store.bootstrap()

    // Bound first: an expectation's autoclosure cannot await.
    let writer = try await store.temporaryStoreForTesting()
    let reader = try await store.readConnection.temporaryStoreForTesting()
    expectNoDifference(writer, 2)
    expectNoDifference(reader, 2)

    // A writer that reopens its connection keeps them in memory too.
    await store.simulateUnexpectedConnectionCloseForTesting()
    let reopened = try await store.temporaryStoreForTesting()
    expectNoDifference(reopened, 2)
  }
}

extension StorageIOExercises {
  /// Closing a query keeps SQLite's temporary structures in memory (#1504). On the phone the energy ledger's
  /// `sqlite.temp` writer (a statement journal, a sort's or an ephemeral b-tree's spill, the temporary database's
  /// journal) wrote 34,124-36,677 times an hour of recording, 19-49 MB/h, and 470,007 times (166 MB/h) across the 10-30
  /// evening's eight launches: every connection opened with SQLite's default `temp_store`, a file. A statement inside a
  /// transaction that may undo itself journals the pages it changes, in memory up to 64 KiB and then in a file, and a
  /// closed result's delete cascaded over every ownership row it held (since #1500 closing marks its row where it is
  /// instead). The bytes are transient by definition, deleted when the statement ends, and what they hold is bounded by
  /// the library's own batches (a prune batch, a released chunk, a reload chunk), so they belong in memory. At this size
  /// (300 todos, about 1,500 ownership rows) the journal stayed under the 64 KiB before the fix too, so this is a guard;
  /// which phone statement spilled is not reproduced here, and the phone's ledger after the build is the measure. In the
  /// suite, which runs one test at a time: the shim's counters are the process's.
  @Test
  func closingAQuerysResultWritesNoTemporaryFile() async throws {
    StorageIOCounters.install(asDefault: false)
    let run = try StorageIORun(label: "temp-store-1504-close")
    defer { run.remove() }
    StorageIOCounters.watch(directory: run.directory)
    defer { StorageIOCounters.watch(directory: nil) }
    let store = try SQLitePersistenceStore.$connectionVFSForTesting.withValue(StorageIOCounters.vfsName) {
      try SQLitePersistenceStore(fileURL: run.directory.appendingPathComponent("store.sqlite"))
    }
    try await store.bootstrap()

    // Two pages of 300 todos each, the size of a timeline's page on the phone (a 256-line page held about 4,000 facts).
    let openKey = "query-open-page"
    var results: [InstantPersistedLiveQueryResult] = []
    var facts: [InstantTriple] = []
    for page in 0..<2 {
      let triples = (page * 300..<(page + 1) * 300).flatMap(Self.todoTriples(index:))
      facts.append(contentsOf: triples)
      results.append(
        InstantPersistedLiveQueryResult(
          replacement: InstantLiveQueryResultReplacement(
            key: page == 0 ? openKey : "query-closed-page", triples: triples, pageInfo: nil),
          updatedAt: InstantTimestamp(milliseconds: Int64(page + 1))
        )
      )
    }
    let saved = try await store.saveLiveRefresh(
      InstantPersistenceSnapshot(store: InstantStoreSnapshot(attributes: TodoExample.attributes, triples: facts)),
      queryResults: results,
      storeChanged: true,
      outboxChanged: false,
      metadataKey: "test.temp-store-1504",
      metadataValue: "seeded",
      metadataUpdatedAt: InstantTimestamp(milliseconds: 10),
      expectedStoreRevision: 0,
      expectedOutboxRevision: 0,
      expectedAttributeRevision: 0
    )
    #expect(saved)

    let before = StorageIOCounters.snapshot()
    let application = try await store.pruneLiveQueryResults(
      policy: InstantLiveQueryResultPruningPolicy(maxAgeMilliseconds: nil, maxEntries: 1_000, maxTripleCount: 1_000_000),
      now: InstantTimestamp(milliseconds: 11),
      preservingQueryKeys: [openKey]
    )
    let io = StorageIOCounters.snapshot().subtracting(before)

    // #1500: the closed page is unloaded where it is (its row marked, its rows and facts kept on disk), so the open page
    // is the only loaded result; with nothing unloaded, the I/O below would measure no close at all.
    expectNoDifference(application.result.unloadedQueryKeys, ["query-closed-page"])
    expectNoDifference(application.result.remainingQueryKeys, [openKey])
    expectNoDifference(TemporaryFiles.writtenOfEveryKind(io), TemporaryFiles.noneOfEveryKind)
  }

  /// A recording's writes and its session prune stay in memory too (#1504; zero before the fix as well, at this
  /// exercise's small sizes: a guard, not the red).
  @Test
  func aRecordingsWritesAndItsPruneWriteNoTemporaryFile() async throws {
    let ledger = try await TemporaryFiles.measure(label: "temp-store-1504") { cycle, ledger in
      for _ in 0..<4 { try await cycle.writeLine(into: ledger) }
      for _ in 0..<2 { try await cycle.writeLine(into: ledger, overlapping: true) }
      try await cycle.prune(into: ledger)
    }

    expectNoDifference(
      StorageIOStep.allCases.map { "\($0.rawValue): \(TemporaryFiles.writtenOfEveryKind(ledger.io($0)))" },
      StorageIOStep.allCases.map { "\($0.rawValue): \(TemporaryFiles.noneOfEveryKind)" }
    )
  }

  static func todoTriples(index: Int) -> [InstantTriple] {
    let entityID = "todo-\(index)"
    return TodoExample.createOperations(
      id: entityID,
      text: "Todo \(index): \(String(repeating: "words ", count: 12))",
      createdAt: InstantTimestamp(milliseconds: Int64(index + 1)),
      transactionID: "seed-\(entityID)"
    ).compactMap { operation in
      guard case let .insert(triple) = operation else { return nil }
      return triple
    }
  }
}

extension TemporaryFiles {
  /// Every kind of temporary file, the statement journal included (#1504; #1119 measured the other three).
  static let noneOfEveryKind = ["stmtjournal 0", "temp 0", "tempjournal 0", "transient 0"]

  static func writtenOfEveryKind(_ io: StorageIOSnapshot) -> [String] {
    [StorageIOFileKind.statementJournal, .temporary, .temporaryJournal, .transient].map {
      "\($0.rawValue) \(io[$0].bytesWritten)"
    }
  }
}
