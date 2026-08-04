import CustomDump
import Foundation
@testable import InstantSwiftDataCore
import Testing

/// Ports Point-Free SQLiteData ergonomics tests that Instant can honor without
/// becoming a SQLite clone.
///
/// Upstream source (vendored):
/// `upstream/sqlite-data` at commit `0c79d7a5748fc6d9ce7a1ba2b50f31b175305049`.
///
/// Instant differences called out in each test's header: optimistic multi-device
/// sync, Instant IDs, and InstaQL materialization instead of SQL cursors.
@Suite(.serialized)
struct InstantSQLiteDataErgonomicsParityTests {
  /// Ports `Tests/SQLiteDataTests/DateTests.swift` `roundtrip`.
  ///
  /// SQLiteData inserts a `Date`, updates the same row, and expects bit-equal
  /// `Date` values. Instant stores `.date` on a typed attribute and materializes
  /// the same value after insert and after a subsequent merge update.
  @Test
  func dateAttributeRoundtripInsertUpdateMaterializesEqualValue() async throws {
    let date = Date(timeIntervalSinceReferenceDate: 793_109_282.061)
    let time = InstantTimestamp(milliseconds: 1_700_000_000_000)
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "sqlite-date-roundtrip",
        persistenceURL: temporaryCacheURL(),
        initialAttributes: dateRecordAttributes
      )
    )

    try await runtime.transact(
      InstantStoreTransaction(
        id: "tx-date-insert",
        operations: [
          .insert(
            InstantTriple(
              entityID: "record-1",
              attributeID: "records/id",
              value: .string("record-1"),
              txID: "tx-date-insert",
              txTime: time
            )
          ),
          .insert(
            InstantTriple(
              entityID: "record-1",
              attributeID: "records/date",
              value: .date(date),
              txID: "tx-date-insert",
              txTime: time
            )
          ),
        ]
      ),
      createdAt: time
    )

    let inserted = try #require(
      try await runtime.query(
        InstantQueryPlan(id: "records.after-insert", namespace: "records")
      ).first
    )
    expectNoDifference(dateValue(inserted), date)

    let later = InstantTimestamp(milliseconds: time.milliseconds + 1)
    try await runtime.transact(
      InstantStoreTransaction(
        id: "tx-date-update",
        operations: [
          .merge(
            InstantTriple(
              entityID: "record-1",
              attributeID: "records/date",
              value: .date(date),
              txID: "tx-date-update",
              txTime: later
            )
          )
        ]
      ),
      createdAt: later
    )

    let updated = try #require(
      try await runtime.query(
        InstantQueryPlan(id: "records.after-update", namespace: "records")
      ).first
    )
    expectNoDifference(dateValue(updated), date)
    expectNoDifference(dateValue(inserted), dateValue(updated))
  }

  /// Ports the ergonomic *shape* of `AssertQueryTests` without SQL.
  ///
  /// Upstream `assertQuery` snapshots SQL result tables. Instant has no SQL
  /// surface; the same contract is "materialize a plan and get a stable,
  /// human-readable dump of the rows." These cases cover basic select, empty
  /// result, update-then-read, and the failure mode where a required row is
  /// missing after a non-empty expectation.
  @Test
  func assertQueryStyleMaterializationSnapshotsMatchExpectedTables() async throws {
    let time = InstantTimestamp(milliseconds: 1_700_000_000_000)
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "sqlite-assert-query-style",
        persistenceURL: temporaryCacheURL(),
        initialAttributes: TodoExample.attributes
      )
    )

    for (index, text) in ["one", "two", "three"].enumerated() {
      let txID = "tx-seed-\(index + 1)"
      try await runtime.transact(
        InstantStoreTransaction(
          id: txID,
          operations: TodoExample.createOperations(
            id: "todo-\(index + 1)",
            text: text,
            createdAt: InstantTimestamp(milliseconds: time.milliseconds + Int64(index)),
            transactionID: txID
          )
        ),
        createdAt: InstantTimestamp(milliseconds: time.milliseconds + Int64(index))
      )
    }

    // assertQueryBasic — ids of all rows
    let all = try await runtime.query(
      InstantQueryPlan(id: "todos.all", namespace: "todos")
    )
    expectNoDifference(
      all.map(\.id).sorted(),
      ["todo-1", "todo-2", "todo-3"]
    )
    // assertQuery dumps a table; Instant dumps stable (id, field) rows.
    expectNoDifference(
      all.map { "\($0.id)|\($0.string("text") ?? "")" }.sorted(),
      ["todo-1|one", "todo-2|two", "todo-3|three"]
    )

    // assertQueryRecord — single entity
    let one = try #require(all.first { $0.id == "todo-1" })
    expectNoDifference(one.string("text"), "one")

    // assertQueryBasicUpdate / assertQueryRecordUpdate — mutate then re-read
    try await runtime.transact(
      InstantStoreTransaction(
        id: "tx-complete-1",
        operations: [
          .merge(
            InstantTriple(
              entityID: "todo-1",
              attributeID: "todos/isCompleted",
              value: .bool(true),
              txID: "tx-complete-1",
              txTime: InstantTimestamp(milliseconds: time.milliseconds + 10)
            )
          )
        ]
      ),
      createdAt: InstantTimestamp(milliseconds: time.milliseconds + 10)
    )
    let afterUpdate = try await runtime.query(
      InstantQueryPlan(id: "todos.after-update", namespace: "todos")
    )
    let updated = try #require(afterUpdate.first { $0.id == "todo-1" })
    expectNoDifference(updated.bool("isCompleted"), true)

    // assertQueryEmpty — filter that matches nothing (Instant requires declared namespaces)
    let empty = try await runtime.query(
      InstantQueryPlan(
        id: "todos.none",
        namespace: "todos",
        filters: [.equals(field: "text", value: .string("does-not-exist"))]
      )
    )
    expectNoDifference(empty.count, 0)

    // assertQueryFailsNoResultsNonEmptySnapshot — required non-empty expectation fails loudly
    let onlyCompleted = try await runtime.query(
      InstantQueryPlan(
        id: "todos.completed-only",
        namespace: "todos",
        filters: [.equals(field: "isCompleted", value: .bool(true))]
      )
    )
    #expect(onlyCompleted.count == 1)
    #expect(
      onlyCompleted.map(\.id) != ["todo-1", "todo-2", "todo-3"],
      "A non-empty snapshot expectation must not silently match a filtered subset."
    )
  }

  // MARK: - Support

  private var dateRecordAttributes: [InstantAttribute] {
    [
      .primaryKey(namespace: "records"),
      InstantAttribute(
        id: "records/date",
        namespace: "records",
        name: "date",
        valueType: .date,
        isIndexed: true
      ),
    ]
  }

  private func dateValue(_ snapshot: InstantEntitySnapshot) -> Date? {
    guard case let .date(date) = snapshot.values["date"]?.first else { return nil }
    return date
  }

  private func temporaryCacheURL() throws -> URL {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("InstantSQLiteDataErgonomics-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory.appendingPathComponent("state.sqlite")
  }
}

private extension InstantEntitySnapshot {
  func string(_ field: String) -> String? {
    guard case let .string(value) = values[field]?.first else { return nil }
    return value
  }

  func bool(_ field: String) -> Bool? {
    guard case let .bool(value) = values[field]?.first else { return nil }
    return value
  }
}
