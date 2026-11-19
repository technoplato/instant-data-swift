// History:
// - 2026-11-19: added (#2551): a save reads the facts it replaces from their columns, not the table's generated `json`.

import CustomDump
import Foundation
import Testing

@testable import InstantSwiftDataCore

/// #2551: a local save reads back the entity's facts it replaces, to write only the difference. With the memory-thinned
/// cache that holds no facts, it read them through the fact table's generated `json` column, which SQLite builds for each
/// row, and decoded each with `JSONDecoder`: 91 of 1,451 save samples (6%) in a 3.6-hour Power Profiler trace. The other
/// fact reads have used the columns since #1150 (``InstantFactRowReader``). These tests pin that a save reads no
/// generated `json`, and that the facts it leaves are the ones the write states, for each kind of value a todo holds.
@Suite(.serialized)
struct InstantSaveReadBackColumnsTests {
  /// A todo created, then two of its facts written again: the second save reads the facts it replaces from their
  /// columns, and the entity holds the new values beside the ones it kept.
  @Test
  func aSaveReadsTheFactsItReplacesFromTheirColumns() async throws {
    let url = try InstantStoredResultReloadTests.temporaryCacheURL()
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "save-read-back-columns",
        persistenceURL: url,
        initialAttributes: TodoExample.attributes
      )
    )
    _ = try await runtime.transact(
      operations: TodoExample.createOperations(
        id: "todo-1",
        text: "first \"text\" with a / and an \u{e9}",
        createdAt: InstantTimestamp(milliseconds: 1_000),
        transactionID: "create-1"
      )
    )
    let traced = OwnerProbeStatements()
    await runtime.persistence.traceStatementsForTesting { traced.record($0) }

    _ = try await runtime.transact(
      InstantStoreTransaction(
        id: "edit-1",
        operations: [
          .insert(
            InstantTriple(
              entityID: "todo-1", attributeID: "todos/text", value: .string("second \u{1f399}"), txID: "edit-1",
              txTime: InstantTimestamp(milliseconds: 2_000)
            )
          ),
          .insert(
            InstantTriple(
              entityID: "todo-1", attributeID: "todos/isCompleted", value: .bool(true), txID: "edit-1",
              txTime: InstantTimestamp(milliseconds: 2_000)
            )
          ),
        ]
      )
    )
    await runtime.persistence.traceStatementsForTesting(nil)

    let generatedJSONReads = traced.statements.filter { $0.contains("SELECT json FROM instant_triples") }
    expectNoDifference(generatedJSONReads, [])
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let expectedValues: [(attributeID: String, value: InstantValue)] = [
      ("todos/createdAt", .date(Date(timeIntervalSince1970: 1))),
      ("todos/id", .string("todo-1")),
      ("todos/isCompleted", .bool(true)),
      ("todos/text", .string("second \u{1f399}")),
    ]
    let expected = try expectedValues.map { [$0.attributeID, try InstantStoredJSON.stored($0.value, using: encoder)] }
    let stored = try SQLiteFile.rows(
      url,
      "SELECT attribute_id, value_json FROM instant_triples WHERE entity_id = 'todo-1' ORDER BY attribute_id, value_json"
    )
    expectNoDifference(stored, expected)
  }
}
