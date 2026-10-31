// History:
// - 2026-10-30: added (#1436): which of the outbox's b-trees the statements of a live write's save, claim,
//   acknowledgement and echo read, from SQLite's own plans of the statements they ran; and, by audit triggers, that a
//   write's effect entities are inserted once and deleted once, across a recording's overlapping writes and a backlog.

import CustomDump
import Foundation
import Testing

@testable import InstantSwiftDataCore

extension StorageIOExercises {
  /// Every index is written by every insert and delete of a row it holds, so an index earns its pages by the reads that
  /// use it (#1436, after SQLite's author: keep only the indexes a hot query uses, and prove each with `EXPLAIN QUERY
  /// PLAN`). This runs a recording's line of live writes, each saved before the previous one's echo as on a phone,
  /// records the statements the store ran (`sqlite3_trace_v2`), asks SQLite for each one's plan on the store's own
  /// connection, and prints, for each outbox index, the statements whose plan reads it. Prints `OUTBOXREADS` lines;
  /// asserts only that every outbox index a live write writes is read by one of its statements.
  @Test
  func eachOutboxIndexALiveWriteWritesServesOneOfItsReads() async throws {
    let reads = try await OutboxBTreeReads.measure(label: "outbox-btree-reads")
    reads.print()
    let unread = reads.writtenIndexes.subtracting(reads.statementsByIndex.keys)
    #expect(unread.isEmpty, "indexes a live write writes and none of its statements reads: \(unread.sorted())")
  }
}

extension StorageIOExercises {
  /// A write's effect entities are rows of two b-trees (the table and its lookup by entity). The save writes them and
  /// the echo deletes them; nothing between should (#1436). The echo's commit deleted and inserted every staged write's
  /// rows, and each re-save (a failure, a confirmation) did the same, though the footprint had not changed: the key rows
  /// were made to keep theirs in #1007. Audit triggers count the rows' inserts and deletes across a recording's
  /// overlapping writes and a refusal's re-save.
  @Test
  func aWritesEffectEntitiesAreInsertedOnceAndDeletedOnce() async throws {
    let run = try StorageIORun(label: "effect-entity-writes")
    defer { run.remove() }
    let settings = StorageIOExerciseSettings(
      stepLines: 2, recordingLines: 30, pageLines: 16, minutes: 1, linesPerMinute: 15, fixtureScale: 1
    )
    var cycle = try await StorageIOWriteCycle.make(label: "effect-entity-writes", directory: run.directory, settings: settings)
    let url = cycle.configuration.persistenceURL
    try OutboxConversion.execute(
      url,
      """
      CREATE TABLE effect_entity_audit (op TEXT NOT NULL, mutation_id TEXT NOT NULL, entity_id TEXT NOT NULL);
      CREATE TRIGGER effect_entity_audit_insert AFTER INSERT ON instant_outbox_effect_entities
      BEGIN INSERT INTO effect_entity_audit VALUES ('insert', NEW.mutation_id, NEW.entity_id); END;
      CREATE TRIGGER effect_entity_audit_delete AFTER DELETE ON instant_outbox_effect_entities
      BEGIN INSERT INTO effect_entity_audit VALUES ('delete', OLD.mutation_id, OLD.entity_id); END;
      """
    )
    for _ in 0..<settings.stepLines { try await cycle.writeLine(into: StorageIOLedger(), overlapping: true) }

    _ = try? await cycle.runtime.closeConnection()

    // Each row inserted once, by its save, and deleted at most once, by its echo.
    let repeated = try OutboxConversion.strings(
      url,
      """
      SELECT op || ' ' || mutation_id || ' ' || entity_id || ' x' || count(*) FROM effect_entity_audit
      GROUP BY op, mutation_id, entity_id HAVING count(*) > 1
      """
    )
    let inserts = try OutboxConversion.strings(url, "SELECT count(*) FROM effect_entity_audit WHERE op = 'insert'")
    var line = StorageIOLine("effect-entity-writes", "line")
    line.add("inserts", inserts.first ?? "?")
    line.add("repeated", repeated.count)
    line.print()
    #expect(repeated.isEmpty, "effect entity rows written more than once: \(repeated.prefix(8))")
  }

  /// A relaunch with a backlog delivers its writes one by one, and each echo's server apply rebases the writes still
  /// waiting that touch what it changed (#1119): Scribe's summary and duration writes all touch the recording. The
  /// commit deleted and inserted every staged write's effect entities, so a backlog's echoes rewrote the waiting writes'
  /// rows again and again (#1436). Three lines saved before any is delivered, then each write claimed, acknowledged and
  /// echoed in order.
  @Test
  func aBacklogsEchoesRewriteNoWaitingWritesEffectEntities() async throws {
    let run = try StorageIORun(label: "effect-entity-backlog")
    defer { run.remove() }
    let settings = StorageIOExerciseSettings(
      stepLines: 3, recordingLines: 30, pageLines: 16, minutes: 1, linesPerMinute: 15, fixtureScale: 1
    )
    var cycle = try await StorageIOWriteCycle.make(label: "effect-entity-backlog", directory: run.directory, settings: settings)
    let url = cycle.configuration.persistenceURL
    try OutboxConversion.execute(
      url,
      """
      CREATE TABLE effect_entity_audit (op TEXT NOT NULL, mutation_id TEXT NOT NULL, entity_id TEXT NOT NULL);
      CREATE TRIGGER effect_entity_audit_insert AFTER INSERT ON instant_outbox_effect_entities
      BEGIN INSERT INTO effect_entity_audit VALUES ('insert', NEW.mutation_id, NEW.entity_id); END;
      CREATE TRIGGER effect_entity_audit_delete AFTER DELETE ON instant_outbox_effect_entities
      BEGIN INSERT INTO effect_entity_audit VALUES ('delete', OLD.mutation_id, OLD.entity_id); END;
      """
    )
    var backlog: [InstantStoreTransaction] = []
    for _ in 0..<settings.stepLines {
      for write in cycle.script.nextLineWrites() {
        cycle.clock.advance(by: 1_000)
        _ = try await cycle.runtime.transact(write, createdAt: cycle.clock.now())
        backlog.append(write)
      }
    }
    // The waiting writes in delivery order; a write saved over one not yet sent may have replaced it (supersession).
    let claimant = await cycle.runtime.automaticDeliveryClaimantIDForTesting()
    var delivered = 0
    while delivered <= backlog.count {
      let token = "effect-entity-backlog-\(delivered)"
      let window = try await cycle.runtime.persistence.claimAutomaticOutboxDeliveryWindow(
        InstantAutomaticOutboxClaimRequest(
          claimantID: claimant, claimToken: token, now: cycle.clock.now(), maximumMutationCount: 1
        )
      )
      guard let mutation = window.mutations.first else { break }
      let operations = mutation.transaction.operations
      let transactionID = cycle.server.accept(operations)
      _ = try await cycle.runtime.acceptMutationIfPresent(
        id: mutation.id, serverTransactionID: transactionID, claimToken: token
      )
      delivered += 1
      let touched = Set(operations.compactMap(\.storageIOInsertedTriple).map(\.entityID))
      let deleted = Set(operations.compactMap(\.storageIODeletedEntityID))
      let frame = cycle.server.frame(
        queries: cycle.server.queries(touching: touched.union(deleted), deleting: deleted),
        processedTransactionID: transactionID
      )
      _ = try await cycle.runtime.applyServerTransactionMergingAttributesForTesting(
        frame.transaction,
        attributesToMerge: [],
        liveQueryResultReplacements: frame.replacements
      )
    }
    _ = try? await cycle.runtime.closeConnection()

    let repeated = try OutboxConversion.strings(
      url,
      """
      SELECT op || ' ' || mutation_id || ' ' || entity_id || ' x' || count(*) FROM effect_entity_audit
      GROUP BY op, mutation_id, entity_id HAVING count(*) > 1
      """
    )
    let counts = try OutboxConversion.strings(
      url, "SELECT op || '=' || count(*) FROM effect_entity_audit GROUP BY op ORDER BY op"
    )
    var line = StorageIOLine("effect-entity-backlog", "line")
    line.add("writes", backlog.count)
    line.add("delivered", delivered)
    line.add("rows", counts.joined(separator: ","))
    line.add("repeated", repeated.count)
    line.print()
    #expect(delivered > 0)
    #expect(repeated.isEmpty, "effect entity rows written more than once: \(repeated.prefix(8))")
  }
}

/// The statements a recording's live writes ran and the outbox indexes each one's plan reads (#1436).
struct OutboxBTreeReads {
  /// The outbox's indexes on rows a live write holds: everything but the partial indexes of rare states.
  var writtenIndexes: Set<String>
  /// For each index, the statements whose plan reads it, with the plan's line.
  var statementsByIndex: [String: [(sql: String, plan: String)]]
  var statementCount: Int

  func print() {
    var summary = StorageIOLine("outbox-btree-reads", "line")
    summary.add("statements", statementCount)
    summary.print()
    for index in writtenIndexes.union(statementsByIndex.keys).sorted() {
      let statements = statementsByIndex[index] ?? []
      var line = StorageIOLine("outbox-btree-reads", "index")
      line.add("btree", index)
      line.add("written", writtenIndexes.contains(index) ? 1 : 0)
      line.add("statements", statements.count)
      line.print()
      for statement in statements {
        let sql = statement.sql.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        Swift.print("OUTBOXREADS \(index) | \(statement.plan) | \(sql.prefix(220))")
      }
    }
  }

  static func measure(label: String) async throws -> Self {
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

    // The indexes a live write writes: the full ones on its row, its body, its key rows and its effect entities.
    let indexes = Set(
      try OutboxConversion.strings(
        cycle.configuration.persistenceURL,
        """
        SELECT name FROM sqlite_master
        WHERE type = 'index' AND sql IS NOT NULL AND sql NOT LIKE '%WHERE%'
          AND tbl_name IN (
            'instant_outbox', 'instant_outbox_bodies', 'instant_outbox_write_keys', 'instant_outbox_effect_entities'
          )
        """
      )
    )
    var statementsByIndex: [String: [(sql: String, plan: String)]] = [:]
    let traced = statements.all.filter { $0.contains("instant_outbox") }
    for sql in traced {
      guard let plan = try? await persistence.queryPlanForTesting(sql) else { continue }
      for line in plan {
        guard let range = line.range(of: "INDEX ") else { continue }
        let name = String(line[range.upperBound...].prefix { !$0.isWhitespace })
        guard name.hasPrefix("instant_outbox") else { continue }
        statementsByIndex[name, default: []].append((sql, line))
      }
    }
    _ = try? await cycle.runtime.closeConnection()
    return Self(writtenIndexes: indexes, statementsByIndex: statementsByIndex, statementCount: traced.count)
  }
}

/// The distinct statements a trace saw, in the order it first saw them.
final class TracedStatements: @unchecked Sendable {
  // SAFETY: `lock` guards both collections.
  private let lock = NSLock()
  private var seen: Set<String> = []
  private var ordered: [String] = []

  func insert(_ sql: String) {
    lock.withLock {
      if seen.insert(sql).inserted { ordered.append(sql) }
    }
  }

  var all: [String] { lock.withLock { ordered } }
}
