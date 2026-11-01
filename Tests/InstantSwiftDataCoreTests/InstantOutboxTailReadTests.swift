// History:
// - 2026-10-31: added (#1491): the outbox's newest row in delivery order, which every local write and every server
//   apply's plan reads, is one entry of an index in that order, not a sort of every row; and that index makes no plan
//   of a live write's statements read more of the outbox.

import Foundation
import SQLite3
import Testing

@testable import InstantSwiftDataCore

/// The outbox's tail: its newest row in delivery order, `created_at_ms` then `mutation_id` (#1491).
///
/// Every local write reads it inside the operation gate (the creation cursor it must follow, and for a same-entity write
/// the tail it may replace), and a server apply's plan reads it as it begins and as it takes in later writes. No index
/// held every row in that order, so SQLite scanned the whole global-effect index and kept the newest row in a temporary
/// b-tree: on the outbox's schema with the phone-shaped store's 663 refused writes, 291 us a read against 29 us from an
/// index (laptop), and 2.25 ms with an hour of lines written offline, 5,400 rows.
@Suite
struct InstantOutboxTailReadTests {
  /// Each read of the tail, as the library runs it, reads one entry of the creation-order index and sorts nothing.
  @Test
  func theOutboxTailIsOneEntryOfAnIndexInDeliveryOrder() async throws {
    let store = try await RareStateIndexes.store("outbox-tail-plans")
    for sql in [
      SQLitePersistenceStore.outboxTailPositionSQL,
      SQLitePersistenceStore.outboxTailIDSQL,
      SQLitePersistenceStore.immediateSupersessionTailSQL,
    ] {
      let plan = try RareStateIndexes.plan(store, sql)
      #expect(!plan.contains { $0.contains("TEMP B-TREE") }, "the outbox sorted for its tail: \(plan) for \(sql)")
      #expect(
        plan.contains { $0.contains("INDEX instant_outbox_creation_order_idx") },
        "the creation-order index not in \(plan) for \(sql)"
      )
    }
  }

  /// The creation-order index makes no statement a recording's live writes run read more of the outbox. SQLite plans
  /// these statements without statistics, so a new index could draw a statement that searched another index into
  /// walking this one in order past every refused write. A recording's line of live writes runs its saves, claims,
  /// acknowledgements and echoes (as ``OutboxBTreeReads`` does, #1436); each statement that names the outbox is planned
  /// on the store's own connection with the index and again without it. A changed plan may drop a sort or a full scan;
  /// it may not gain one, nor trade another index's search for one of this index. Besides the tail reads, the first run
  /// changed two counts of the server apply's catch-up: the whole outbox's count scans this smaller index, and the count
  /// of the writes appended after the plan's tail searches it instead of scanning the outbox.
  @Test
  func theCreationOrderIndexMakesNoPlanReadMoreOfTheOutbox() async throws {
    let label = "creation-order-plans"
    let run = try StorageIORun(label: label)
    defer { run.remove() }
    let settings = StorageIOExerciseSettings(
      stepLines: 2, recordingLines: 30, pageLines: 16, minutes: 1, linesPerMinute: 15, fixtureScale: 1
    )
    var cycle = try await StorageIOWriteCycle.make(label: label, directory: run.directory, settings: settings)
    try await cycle.writeLine(into: StorageIOLedger(), overlapping: true)
    let statements = TracedStatements()
    let persistence = cycle.runtime.persistence
    await persistence.traceStatementsForTesting { statements.insert($0) }
    for _ in 0..<settings.stepLines { try await cycle.writeLine(into: StorageIOLedger(), overlapping: true) }
    await persistence.traceStatementsForTesting(nil)
    let traced = statements.all.filter { $0.contains("instant_outbox") }

    var plansWithIndex: [String: [String]] = [:]
    for sql in traced { plansWithIndex[sql] = try? await persistence.queryPlanForTesting(sql) }
    try OutboxTailIndex.drop(from: cycle.configuration.persistenceURL)
    // `EXPLAIN QUERY PLAN` plans on the connection's cached schema, which still holds the index; the store's next read
    // checks the schema and loads it again.
    _ = try await persistence.latestOutboxCreationTimestamp(expectedOutboxRevision: 0)
    let tailPlanWithoutIndex = try await persistence.queryPlanForTesting(SQLitePersistenceStore.outboxTailPositionSQL)
    try #require(
      tailPlanWithoutIndex.contains { $0.contains("TEMP B-TREE") },
      "the store's connection still plans with the dropped index: \(tailPlanWithoutIndex)"
    )
    var changed: [String] = []
    var plansWithoutIndex: [String: [String]] = [:]
    for sql in traced {
      let planWithoutIndex = try? await persistence.queryPlanForTesting(sql)
      plansWithoutIndex[sql] = planWithoutIndex
      guard planWithoutIndex != plansWithIndex[sql] else { continue }
      changed.append(sql)
      let oneLine = sql.split(whereSeparator: \.isWhitespace).joined(separator: " ")
      print(
        "TAILPLANS with=\(plansWithIndex[sql] ?? []) without=\(planWithoutIndex ?? []) | \(oneLine.prefix(220))"
      )
    }
    print("TAILPLANS traced=\(traced.count) changed=\(changed.count)")
    _ = try? await cycle.runtime.closeConnection()

    let tailReads = changed.filter { $0.contains("ORDER BY created_at_ms DESC, mutation_id DESC") }
    #expect(!tailReads.isEmpty, "the \(traced.count) traced statements changed no tail read's plan")
    // `#expect`, not `expectNoDifference`, which passes without a word in a release build's run.
    let worse = changed.filter { sql in
      OutboxTailIndex.readsMore(with: plansWithIndex[sql] ?? [], than: plansWithoutIndex[sql] ?? [])
    }
    #expect(worse.isEmpty, "plans that read more of the outbox with the creation-order index: \(worse)")
  }
}

/// The creation-order index, dropped through a connection of the test's own while the runtime keeps the store open.
enum OutboxTailIndex {
  /// Whether a plan with the index reads more of the outbox than the plan without it: it sorts where the other did not,
  /// scans more often, or searches this index where the other searched another one.
  static func readsMore(with plan: [String], than planWithout: [String]) -> Bool {
    func sorts(_ plan: [String]) -> Int { plan.filter { $0.contains("TEMP B-TREE") }.count }
    func scans(_ plan: [String]) -> Int { plan.filter { $0.hasPrefix("SCAN ") }.count }
    let searchesThisIndex = plan.contains { $0.hasPrefix("SEARCH ") && $0.contains("instant_outbox_creation_order_idx") }
    let searchedAnother = planWithout.contains { $0.hasPrefix("SEARCH ") && $0.contains("INDEX instant_outbox") }
    return sorts(plan) > sorts(planWithout) || scans(plan) > scans(planWithout)
      || (searchesThisIndex && searchedAnother && scans(planWithout) == 0)
  }

  static func drop(from store: URL) throws {
    var connection: OpaquePointer?
    defer { sqlite3_close_v2(connection) }
    guard sqlite3_open_v2(store.path, &connection, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK else {
      throw StorageIOError("open \(store.lastPathComponent)")
    }
    sqlite3_busy_timeout(connection, 5_000)
    guard sqlite3_exec(connection, "DROP INDEX instant_outbox_creation_order_idx", nil, nil, nil) == SQLITE_OK else {
      throw StorageIOError(String(cString: sqlite3_errmsg(connection)))
    }
  }
}
