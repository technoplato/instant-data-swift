// History:
// - 2026-10-30: added (#1435): a store whose outbox rows hold their bodies converts at open to a narrow row and a body
//   table, with writes refused, acknowledged, claimed and pending, and every one of them goes on as it would have.

import CustomDump
import Foundation
import SQLite3
import Testing

@testable import InstantSwiftDataCore

/// An outbox row held its write's body (`json`, `lifecycle_json`, the quarantine copies) beside 25 delivery columns
/// until #1435; the store now keeps the body in `instant_outbox_bodies` and the row narrow, so a claim and an
/// acknowledgement write the row alone. A store in the old layout converts once at open, decided by the table's own
/// columns, so a restore that rebuilds the old shape converts again.
@Suite(.serialized)
struct InstantOutboxBodyConversionTests {
  /// A store shaped like a phone's, in the old layout: refused writes with 19 KB bodies (the phone's copy held 728 of
  /// them), and a recording's writes in flight, one acknowledged and waiting for its echo, one claimed and one pending.
  /// The conversion keeps every row's columns, body, key rows and effect entities as they were; then the claimed write is
  /// acknowledged under its claim, the pending one is claimed and delivered, all three are echoed, and the refused
  /// writes stay with their bodies. Nothing is lost.
  @Test
  func aStoreWhoseRowsHoldTheirBodiesConvertsWithWritesInFlight() async throws {
    let run = try StorageIORun(label: "outbox-body-conversion")
    defer { run.remove() }
    let settings = StorageIOExerciseSettings(
      stepLines: 1, recordingLines: 30, pageLines: 16, minutes: 1, linesPerMinute: 15, fixtureScale: 1
    )
    var cycle = try await StorageIOWriteCycle.make(label: "outbox-body-conversion", directory: run.directory, settings: settings)
    let url = cycle.configuration.persistenceURL
    let claimant = await cycle.runtime.automaticDeliveryClaimantIDForTesting()

    // Refused writes, each with a body that spills over several pages.
    var refused: [String] = []
    for index in 0..<OutboxConversion.refusedCount {
      cycle.clock.advance(by: 1_000)
      let write = OutboxConversion.refusedWrite(index: index, at: cycle.clock.now())
      _ = try await cycle.runtime.transact(write, createdAt: cycle.clock.now())
      let token = "conversion-refused-\(index)"
      let window = try await cycle.runtime.persistence.claimAutomaticOutboxDeliveryWindow(
        InstantAutomaticOutboxClaimRequest(
          claimantID: claimant, claimToken: token, now: cycle.clock.now(), maximumMutationCount: 1
        )
      )
      expectNoDifference(window.mutations.map(\.id), [write.id])
      _ = try await cycle.runtime.failClaimedMutationForTesting(
        id: write.id, message: "permission denied", claimToken: token
      )
      refused.append(write.id)
    }

    // A recording's line in flight: acknowledged (waiting for its echo), claimed, and pending.
    let writes = cycle.script.nextLineWrites()
    let acknowledged = writes[0]
    let claimed = writes[1]
    let pending = writes[2]
    cycle.clock.advance(by: 1_000)
    _ = try await cycle.runtime.transact(acknowledged, createdAt: cycle.clock.now())
    let acknowledgedWindow = try await cycle.runtime.persistence.claimAutomaticOutboxDeliveryWindow(
      InstantAutomaticOutboxClaimRequest(
        claimantID: claimant, claimToken: "conversion-acknowledged", now: cycle.clock.now(), maximumMutationCount: 1
      )
    )
    expectNoDifference(acknowledgedWindow.mutations.map(\.id), [acknowledged.id])
    let acknowledgedTransactionID = cycle.server.accept(acknowledged.operations)
    let acceptance = try await cycle.runtime.acceptMutationIfPresent(
      id: acknowledged.id, serverTransactionID: acknowledgedTransactionID, claimToken: "conversion-acknowledged"
    )
    #expect(acceptance?.status == .confirmed)
    cycle.clock.advance(by: 1_000)
    _ = try await cycle.runtime.transact(claimed, createdAt: cycle.clock.now())
    let claimedWindow = try await cycle.runtime.persistence.claimAutomaticOutboxDeliveryWindow(
      InstantAutomaticOutboxClaimRequest(
        claimantID: claimant, claimToken: "conversion-claimed", now: cycle.clock.now(), maximumMutationCount: 1
      )
    )
    expectNoDifference(claimedWindow.mutations.map(\.id), [claimed.id])
    cycle.clock.advance(by: 1_000)
    _ = try await cycle.runtime.transact(pending, createdAt: cycle.clock.now())
    _ = try await cycle.runtime.closeConnection()
    await cycle.runtime.persistence.simulateUnexpectedConnectionCloseForTesting()

    let ids = refused + [acknowledged.id, claimed.id, pending.id]
    let before = try await OutboxConversion.Snapshot.read(url: url, ids: ids)
    #expect(before.mutations[acknowledged.id]??.status == .confirmed)
    #expect(before.mutations[claimed.id]??.status == .pending)
    #expect(before.mutations[refused[0]]??.status == .failed)
    try OutboxConversion.restoreBodiesInTheirRows(url: url)

    // The open converts the store.
    let after = try await OutboxConversion.Snapshot.read(url: url, ids: ids)
    let layout = try OutboxConversion.Layout.read(url: url)
    #expect(!layout.outboxColumns.contains("json"), "instant_outbox still holds the body: \(layout.outboxColumns)")
    #expect(!layout.outboxColumns.contains("lifecycle_json"), "\(layout.outboxColumns)")
    #expect(layout.outboxIsWithoutRowID, "instant_outbox is keyed by its mutation id alone")
    #expect(layout.bodyCount == ids.count, "\(layout.bodyCount) bodies for \(ids.count) rows")
    expectNoDifference(after, before)
    #expect(after == before)

    // The writes in flight go on: the claimed one is acknowledged under the claim it held, the pending one is claimed,
    // and the server's answer echoes all three.
    let persistence = try SQLitePersistenceStore(fileURL: url)
    try await persistence.bootstrap()
    let claimedTransactionID = cycle.server.accept(claimed.operations)
    let claimedRevision = try await persistence.currentOutboxRevision()
    let claimedAcceptance = try await persistence.acceptOutboxMutation(
      id: claimed.id,
      serverTransactionID: claimedTransactionID,
      claimantID: claimant,
      claimToken: "conversion-claimed",
      expectedOutboxRevision: claimedRevision
    )
    #expect(claimedAcceptance?.didChange == true)
    let pendingWindow = try await persistence.claimAutomaticOutboxDeliveryWindow(
      InstantAutomaticOutboxClaimRequest(
        claimantID: claimant, claimToken: "conversion-pending", now: cycle.clock.now(), maximumMutationCount: 50
      )
    )
    expectNoDifference(pendingWindow.mutations.map(\.id), [pending.id])
    let pendingTransactionID = cycle.server.accept(pending.operations)
    let pendingRevision = try await persistence.currentOutboxRevision()
    let pendingAcceptance = try await persistence.acceptOutboxMutation(
      id: pending.id,
      serverTransactionID: pendingTransactionID,
      claimantID: claimant,
      claimToken: "conversion-pending",
      expectedOutboxRevision: pendingRevision
    )
    #expect(pendingAcceptance?.didChange == true)
    await persistence.simulateUnexpectedConnectionCloseForTesting()

    let runtime = try await InstantRuntime.bootstrap(configuration: cycle.configuration)
    let frame = cycle.server.frame(
      queries: cycle.server.registeredQueries,
      processedTransactionID: String(cycle.server.lastTransactionNumber)
    )
    _ = try await runtime.applyServerTransactionMergingAttributesForTesting(
      frame.transaction,
      attributesToMerge: [],
      liveQueryResultReplacements: frame.replacements
    )
    _ = try? await runtime.closeConnection()

    let delivered = try await OutboxConversion.Snapshot.read(url: url, ids: ids)
    for id in [acknowledged.id, claimed.id, pending.id] {
      #expect(delivered.mutations[id] == .some(nil), "\(id) is still in the outbox after its echo")
    }
    for id in refused {
      #expect(delivered.mutations[id] == before.mutations[id], "refused write \(id) changed")
    }
    let finalLayout = try OutboxConversion.Layout.read(url: url)
    #expect(finalLayout.bodyCount == refused.count, "\(finalLayout.bodyCount) bodies for \(refused.count) refused rows")
    #expect(finalLayout.rowCount == refused.count)
  }
}

enum OutboxConversion {
  static let refusedCount = 12

  /// A write of a line no recording reaches, with 18 KB of words: as large as the phone's refused bodies, so its body
  /// spills onto several overflow pages.
  static func refusedWrite(index: Int, at time: InstantTimestamp) -> InstantStoreTransaction {
    let id = UUID().uuidString.lowercased()
    let line = FastDrainSchema.liveLineID(90_000 + index)
    let words = StorageIOLineScript.words(line: 90_000 + index, count: 300)
    func insert(_ attribute: String, _ value: InstantValue) -> InstantTripleOperation {
      .insert(InstantTriple(entityID: line, attributeID: "liveLines/\(attribute)", value: value, txID: id, txTime: time))
    }
    return InstantStoreTransaction(
      id: id,
      operations: [
        insert("id", .string(line)),
        insert("recordingID", .string(FastDrainSchema.recordingID)),
        insert("text", .string(StorageIOLineScript.text(words))),
        insert("wordsJSON", .string(StorageIOLineScript.wordsJSON(words))),
        insert("updatedAtMs", .number(Double(time.milliseconds))),
      ]
    )
  }

  /// The delivery columns an outbox row keeps in both layouts.
  static let rowColumns = [
    "mutation_id", "status", "created_at_ms", "delivery_state", "delivery_metadata_version", "transport_step_count",
    "encoded_body_bytes", "failure_message", "confirmation_proven", "optimistic_overlay_active", "delivery_started",
    "delivery_claim_state", "delivery_claim_token", "delivery_claimant_id", "delivery_claim_deadline_ms",
    "mutation_revision", "optimistic_effect_metadata_version", "optimistic_effect_is_global", "server_transaction_id",
    "confirmation_source", "failure_attribute_revision", "delivery_claim_projected_body_bytes",
    "optimistic_effect_receipt_fingerprint", "delivery_claim_payload_fingerprint", "server_acceptance_payload_fingerprint",
  ]

  /// What the store holds for each write, read through a store opened on it (which converts an old layout first) and
  /// through SQLite: the decoded write, its row's delivery columns, its key rows and effect entities, its receipt.
  struct Snapshot: Equatable, CustomDebugStringConvertible {
    var mutations: [String: PendingMutation?]
    var rows: [String]
    var writeKeys: [String]
    var effectEntities: [String]
    var receipts: [String: String?]
    var outboxRevision: Int64

    var debugDescription: String {
      "Snapshot(\(mutations.count) writes, \(rows.count) rows, \(writeKeys.count) keys, \(effectEntities.count) effects)"
    }

    static func read(url: URL, ids: [String]) async throws -> Self {
      let persistence = try SQLitePersistenceStore(fileURL: url)
      try await persistence.bootstrap()
      var mutations: [String: PendingMutation?] = [:]
      var receipts: [String: String?] = [:]
      for id in ids {
        mutations[id] = try await persistence.outboxMutationForDiagnostics(id: id)
        receipts[id] = try await persistence.optimisticEffectReceiptFingerprintForTesting(id: id)
      }
      let outboxRevision = try await persistence.currentOutboxRevision()
      await persistence.simulateUnexpectedConnectionCloseForTesting()
      let quoted = rowColumns.map { "quote(\($0))" }.joined(separator: " || ',' || ")
      return Self(
        mutations: mutations,
        rows: try strings(url, "SELECT \(quoted) FROM instant_outbox ORDER BY mutation_id"),
        writeKeys: try strings(
          url,
          """
          SELECT mutation_id || ',' || entity_id || ',' || attribute_id FROM instant_outbox_write_keys
          ORDER BY mutation_id, entity_id, attribute_id
          """
        ),
        effectEntities: try strings(
          url,
          """
          SELECT mutation_id || ',' || entity_id || ',' || created_at_ms FROM instant_outbox_effect_entities
          ORDER BY mutation_id, entity_id
          """
        ),
        receipts: receipts,
        outboxRevision: outboxRevision
      )
    }
  }

  /// The outbox's tables as SQLite holds them.
  struct Layout {
    var outboxColumns: [String]
    var outboxIsWithoutRowID: Bool
    var rowCount: Int
    var bodyCount: Int

    static func read(url: URL) throws -> Self {
      let hasBodies = try strings(
        url, "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'instant_outbox_bodies'"
      ).isEmpty == false
      return Self(
        outboxColumns: try strings(url, "SELECT name FROM pragma_table_info('instant_outbox') ORDER BY cid"),
        outboxIsWithoutRowID: try strings(
          url, "SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'instant_outbox'"
        ).first?.contains("WITHOUT ROWID") == true,
        rowCount: Int(try strings(url, "SELECT COUNT(*) FROM instant_outbox").first ?? "0") ?? 0,
        bodyCount: hasBodies
          ? Int(try strings(url, "SELECT COUNT(*) FROM instant_outbox_bodies").first ?? "0") ?? 0
          : 0
      )
    }
  }

  /// Puts each body back in its row, in the layout every store had before #1435 (columns in the order the migrations
  /// added them, the body carrying its delivery fields again), and forgets that the store was converted. A store already
  /// in that layout is left alone.
  static func restoreBodiesInTheirRows(url: URL) throws {
    let hasBodies = try strings(
      url, "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'instant_outbox_bodies'"
    ).isEmpty == false
    guard hasBodies else { return }
    let columns = rowColumns.joined(separator: ", ")
    try execute(
      url,
      """
      PRAGMA foreign_keys = OFF;
      BEGIN;
      CREATE TABLE instant_outbox_wide (
        mutation_id TEXT PRIMARY KEY NOT NULL,
        status TEXT NOT NULL,
        created_at_ms INTEGER NOT NULL,
        json TEXT NOT NULL,
        delivery_state TEXT,
        delivery_metadata_version INTEGER NOT NULL DEFAULT 0,
        transport_step_count INTEGER,
        lifecycle_json TEXT,
        quarantine_json TEXT,
        quarantine_lifecycle_json TEXT,
        encoded_body_bytes INTEGER,
        failure_message TEXT,
        confirmation_proven INTEGER,
        optimistic_overlay_active INTEGER NOT NULL DEFAULT 1,
        delivery_started INTEGER NOT NULL DEFAULT 1,
        delivery_claim_state TEXT NOT NULL DEFAULT 'ready',
        delivery_claim_token TEXT,
        delivery_claimant_id TEXT,
        delivery_claim_deadline_ms INTEGER,
        mutation_revision INTEGER NOT NULL DEFAULT 0,
        optimistic_effect_metadata_version INTEGER NOT NULL DEFAULT 0,
        optimistic_effect_is_global INTEGER NOT NULL DEFAULT 0,
        server_transaction_id TEXT,
        confirmation_source TEXT,
        failure_attribute_revision INTEGER,
        delivery_claim_projected_body_bytes INTEGER,
        optimistic_effect_receipt_fingerprint TEXT,
        delivery_claim_payload_fingerprint TEXT,
        server_acceptance_payload_fingerprint TEXT
      );
      INSERT INTO instant_outbox_wide (\(columns), json, lifecycle_json, quarantine_json, quarantine_lifecycle_json)
      SELECT \(rowColumns.map { "outbox.\($0)" }.joined(separator: ", ")),
        json_set(
          CASE WHEN outbox.confirmation_source IS NULL THEN body.json
            ELSE json_set(body.json, '$.confirmationSource', outbox.confirmation_source) END,
          '$.status', outbox.status
        ),
        body.lifecycle_json, body.quarantine_json, body.quarantine_lifecycle_json
      FROM instant_outbox AS outbox JOIN instant_outbox_bodies AS body ON body.mutation_id = outbox.mutation_id;
      UPDATE instant_outbox_wide
      SET json = json_set(json, '$.serverTransactionID', server_transaction_id)
      WHERE server_transaction_id IS NOT NULL;
      DROP TABLE instant_outbox_bodies;
      DROP TABLE instant_outbox;
      ALTER TABLE instant_outbox_wide RENAME TO instant_outbox;
      CREATE INDEX instant_outbox_delivery_idx ON instant_outbox
        (delivery_claim_state, delivery_state, delivery_claim_deadline_ms, created_at_ms, mutation_id);
      CREATE INDEX instant_outbox_global_effect_order_idx ON instant_outbox
        (optimistic_overlay_active, optimistic_effect_is_global, created_at_ms, mutation_id);
      CREATE INDEX instant_outbox_server_apply_watermark_idx ON instant_outbox
        (status, confirmation_proven, server_transaction_id, optimistic_overlay_active, created_at_ms, mutation_id);
      CREATE INDEX instant_outbox_server_apply_failed_idx ON instant_outbox
        (status, optimistic_overlay_active, created_at_ms, mutation_id)
        WHERE status = 'failed' AND optimistic_overlay_active = 1;
      COMMIT;
      PRAGMA foreign_keys = ON;
      """
    )
  }

  static func strings(_ url: URL, _ sql: String) throws -> [String] {
    var connection: OpaquePointer?
    guard sqlite3_open_v2(url.path, &connection, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, let connection else {
      sqlite3_close_v2(connection)
      throw StorageIOError("open \(url.lastPathComponent)")
    }
    defer { sqlite3_close_v2(connection) }
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(connection, sql, -1, &statement, nil) == SQLITE_OK else {
      throw StorageIOError("\(String(cString: sqlite3_errmsg(connection))) in \(sql)")
    }
    defer { sqlite3_finalize(statement) }
    var rows: [String] = []
    while sqlite3_step(statement) == SQLITE_ROW {
      rows.append(sqlite3_column_text(statement, 0).map { String(cString: $0) } ?? "NULL")
    }
    return rows
  }

  static func execute(_ url: URL, _ sql: String) throws {
    var connection: OpaquePointer?
    guard sqlite3_open_v2(url.path, &connection, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK, let connection else {
      sqlite3_close_v2(connection)
      throw StorageIOError("open \(url.lastPathComponent)")
    }
    defer { sqlite3_close_v2(connection) }
    var message: UnsafeMutablePointer<CChar>?
    guard sqlite3_exec(connection, sql, nil, nil, &message) == SQLITE_OK else {
      defer { sqlite3_free(message) }
      throw StorageIOError(message.map { String(cString: $0) } ?? "SQLite failed")
    }
  }
}
