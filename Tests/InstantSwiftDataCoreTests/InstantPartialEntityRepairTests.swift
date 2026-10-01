import CustomDump
import Foundation
import SQLite3
import Testing

@testable import InstantSwiftDataCore

/// #278. Live-query pruning used to keep some of an entity's facts and delete the rest; one iPhone
/// kept 1,067 transcription segments with `text` but no `id`, `recordingID`, or `segmentIndex`. A
/// store that has synced drops those entities once, so the server delivers them whole again.
@Suite(.serialized)
struct InstantPartialEntityRepairTests {
  @Test
  func reopeningASyncedStoreRemovesEntitiesThatLostTheirIDFact() async throws {
    let url = try await makeDamagedStore(hasSynced: true)
    defer { try? FileManager.default.removeItem(at: url) }
    let repairs = RepairDiagnostics()
    let token = InstantDiagnostics.shared.addHandler { entry in
      repairs.record(entry)
    }
    defer { InstantDiagnostics.shared.removeHandler(token) }

    let reopened = try SQLitePersistenceStore(fileURL: url, declaredAttributes: repairAttributes)
    try await reopened.bootstrap()

    expectNoDifference(
      try sqliteStrings(url, "SELECT DISTINCT entity_id FROM instant_triples ORDER BY entity_id"),
      ["section-pending", "section-whole"]
    )
    expectNoDifference(
      try sqliteStrings(
        url,
        "SELECT entity_id FROM instant_live_query_triples ORDER BY entity_id"
      ),
      ["section-whole"]
    )
    expectNoDifference(
      repairs.records(),
      [
        [
          "entityCount": "1",
          "factCount": "2",
          "namespaces": "sections:1",
          "sampleEntityIDs": "section-damaged",
        ]
      ]
    )
  }

  @Test
  func aStoreThatNeverSyncedKeepsItsEntities() async throws {
    let url = try await makeDamagedStore(hasSynced: false)
    defer { try? FileManager.default.removeItem(at: url) }

    let reopened = try SQLitePersistenceStore(fileURL: url, declaredAttributes: repairAttributes)
    try await reopened.bootstrap()

    expectNoDifference(
      try sqliteStrings(url, "SELECT DISTINCT entity_id FROM instant_triples ORDER BY entity_id"),
      ["section-damaged", "section-pending", "section-whole"]
    )
  }
}

// MARK: - Fixture

private let repairAttributes: [InstantAttribute] = [
  InstantAttribute(id: "sections/id", namespace: "sections", name: "id", valueType: .string, isRequired: true),
  InstantAttribute(id: "sections/text", namespace: "sections", name: "text", valueType: .string, isRequired: false),
  InstantAttribute(id: "sections/wordsJSON", namespace: "sections", name: "wordsJSON", valueType: .string, isRequired: false),
]

/// A whole section, a section that lost its `id` fact the way pruning left them, and a section
/// without an `id` fact that a pending local mutation still owns. The repair migration has not run.
private func makeDamagedStore(hasSynced: Bool) async throws -> URL {
  let url = FileManager.default.temporaryDirectory
    .appendingPathComponent("instant-partial-entity-repair-\(UUID().uuidString).sqlite")
  let persistence = try SQLitePersistenceStore(fileURL: url, declaredAttributes: repairAttributes)
  try await persistence.bootstrap()

  let time = InstantTimestamp(milliseconds: 1)
  func triple(_ entityID: String, _ attributeID: String, _ value: String, txID: String = "server") -> InstantTriple {
    InstantTriple(entityID: entityID, attributeID: attributeID, value: .string(value), txID: txID, txTime: time)
  }
  let pendingTriple = triple("section-pending", "sections/text", "written offline", txID: "pending-1")
  try await persistence.saveStoreSnapshot(
    InstantStoreSnapshot(
      attributes: repairAttributes,
      triples: [
        triple("section-whole", "sections/id", "section-whole"),
        triple("section-whole", "sections/text", "whole"),
        triple("section-damaged", "sections/text", "damaged"),
        triple("section-damaged", "sections/wordsJSON", "[]"),
        pendingTriple,
      ]
    )
  )
  var mutation = PendingMutation(
    id: "pending-1",
    createdAt: time,
    transaction: InstantStoreTransaction(id: "pending-1", operations: [.insert(pendingTriple)]),
    status: .pending
  )
  mutation.rollbackTransaction = InstantStoreTransaction(
    id: "rollback-pending-1",
    operations: [.deleteEntity("section-pending")]
  )
  mutation.optimisticOverlayState = .applied
  mutation.optimisticEffectReceiptVersion = PendingMutation.currentOptimisticEffectReceiptVersion
  let seeded = try await persistence.loadCompactState()
  #expect(
    try await persistence.saveOutbox(
      [mutation],
      replacing: [],
      metadataEntries: [],
      expectedStoreRevision: seeded.storeRevision,
      expectedOutboxRevision: seeded.outboxRevision
    )
  )
  expectNoDifference(
    try sqliteStrings(url, "SELECT entity_id FROM instant_outbox_effect_entities"),
    ["section-pending"]
  )
  if hasSynced {
    try await persistence.saveMetadataValue(
      "2847024639",
      key: "sync.processed_transaction_id:repair-app",
      updatedAt: time
    )
  }
  try sqliteExecute(
    url,
    """
    INSERT INTO instant_live_query_results (query_key, triple_count, updated_at_ms, json)
    VALUES ('sections-list', 2, 1, '{}');
    INSERT INTO instant_live_query_triples (query_key, entity_id, attribute_id, value_json)
    VALUES
      ('sections-list', 'section-whole', 'sections/text', 'whole'),
      ('sections-list', 'section-damaged', 'sections/text', 'damaged');
    DELETE FROM instant_schema_migrations WHERE name = '0024_remove_entities_missing_their_id_fact';
    """
  )
  return url
}

private final class RepairDiagnostics: @unchecked Sendable {
  private let lock = NSLock()
  private var metadata: [[String: String]] = []

  func record(_ entry: InstantDiagnosticEntry) {
    guard entry.event == "sqlite.repair.entities-missing-id-removed" else { return }
    lock.withLock { metadata.append(entry.metadata) }
  }

  func records() -> [[String: String]] {
    lock.withLock { metadata }
  }
}

private func withSQLite<Result>(_ url: URL, _ body: (OpaquePointer?) throws -> Result) throws -> Result {
  var database: OpaquePointer?
  guard sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK
  else {
    defer { sqlite3_close(database) }
    throw NSError(domain: "InstantPartialEntityRepairTests", code: 1)
  }
  defer { sqlite3_close(database) }
  return try body(database)
}

private func sqliteExecute(_ url: URL, _ sql: String) throws {
  try withSQLite(url) { database in
    var errorMessage: UnsafeMutablePointer<CChar>?
    guard sqlite3_exec(database, sql, nil, nil, &errorMessage) == SQLITE_OK else {
      defer { sqlite3_free(errorMessage) }
      throw NSError(
        domain: "InstantPartialEntityRepairTests",
        code: 2,
        userInfo: [NSLocalizedDescriptionKey: errorMessage.map { String(cString: $0) } ?? "SQLite error"]
      )
    }
  }
}

private func sqliteStrings(_ url: URL, _ sql: String) throws -> [String] {
  try withSQLite(url) { database in
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
      throw NSError(domain: "InstantPartialEntityRepairTests", code: 3)
    }
    defer { sqlite3_finalize(statement) }
    var values: [String] = []
    while sqlite3_step(statement) == SQLITE_ROW {
      values.append(String(cString: sqlite3_column_text(statement, 0)))
    }
    return values
  }
}
