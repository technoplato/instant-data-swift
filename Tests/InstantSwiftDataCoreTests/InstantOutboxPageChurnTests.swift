import CustomDump
import Foundation
import SQLite3
import Testing

@testable import InstantSwiftDataCore

/// #1007: a write's steady cycle (save, claim, acknowledgement, the server's echo) rewrote about 68 whole 4 KB pages of
/// the store's write-ahead log on a device, most of them bookkeeping that did not change. Two of the rewrites change no
/// row's content: a revision bump stored with `INSERT OR REPLACE`, which deletes the row and inserts it again under a new
/// rowid (the table's leaf and its key index both rewritten, every transaction), and an acknowledgement that deletes a
/// write's key rows and inserts the same rows again. An unchanged row keeps its place.
@Suite(.serialized)
struct InstantOutboxPageChurnTests {
  /// An acknowledgement leaves the write's key rows and the store's revision rows where they are. The key rows live in a
  /// WITHOUT ROWID table since #1115, which has no rowid to watch: `aWritesOutboxRowsWriteNoBTreeTwice` (in
  /// `StorageIOExercises`) checks that the acknowledgement writes no page of it, here its rows stay the same.
  @Test
  func anAcknowledgementUpdatesItsBookkeepingRowsInPlace() async throws {
    var fixture = try await FastDrainFixture.make(
      suffix: "page-churn",
      serverSegmentCount: 4,
      pendingSegmentCount: 1
    )
    let database = fixture.configuration.persistenceURL
    let (token, mutations) = try await fixture.claimWindow()
    let mutation = try #require(mutations.first)
    let keysBefore = try Self.rows(
      "SELECT entity_id, attribute_id FROM instant_outbox_write_keys WHERE mutation_id = ? ORDER BY entity_id, attribute_id",
      binding: mutation.id,
      in: database
    )
    let metadataBefore = try Self.rows(
      "SELECT rowid, key FROM instant_sync_metadata ORDER BY key",
      in: database
    )
    #expect(!keysBefore.isEmpty)
    let pagesBefore = await fixture.runtime.sqlitePagesWrittenForTesting()

    let transactionID = fixture.server.accept(mutation.transaction.operations)
    _ = try await fixture.runtime.acceptMutationIfPresent(
      id: mutation.id,
      serverTransactionID: transactionID,
      claimToken: token
    )

    let pagesAfter = await fixture.runtime.sqlitePagesWrittenForTesting()
    print("outbox-page-churn: one acknowledgement wrote \(pagesAfter.pages - pagesBefore.pages) pages")
    let keysAfter = try Self.rows(
      "SELECT entity_id, attribute_id FROM instant_outbox_write_keys WHERE mutation_id = ? ORDER BY entity_id, attribute_id",
      binding: mutation.id,
      in: database
    )
    let metadataAfter = try Self.rows(
      "SELECT rowid, key FROM instant_sync_metadata ORDER BY key",
      in: database
    )
    expectNoDifference(keysAfter, keysBefore)
    // Every revision row that existed before keeps its rowid; the acknowledgement may add rows, never move one.
    let keptMetadata = metadataAfter.filter { row in metadataBefore.contains { $0.last == row.last } }
    expectNoDifference(keptMetadata, metadataBefore)
    _ = try? await fixture.runtime.closeConnection()
  }

  /// A revision bump changes the row's value, not its identity, and never touches another row.
  @Test
  func aWriteBumpsTheStoresRevisionRowsInPlace() async throws {
    var fixture = try await FastDrainFixture.make(
      suffix: "page-churn-save",
      serverSegmentCount: 2,
      pendingSegmentCount: 1
    )
    let database = fixture.configuration.persistenceURL
    let metadataBefore = try Self.rows(
      "SELECT rowid, key FROM instant_sync_metadata ORDER BY key",
      in: database
    )
    let revisionsBefore = try Self.rows(
      "SELECT key, value FROM instant_sync_metadata ORDER BY key",
      in: database
    )
    _ = try await fixture.writeSegments(1)
    let metadataAfter = try Self.rows(
      "SELECT rowid, key FROM instant_sync_metadata ORDER BY key",
      in: database
    )
    let revisionsAfter = try Self.rows(
      "SELECT key, value FROM instant_sync_metadata ORDER BY key",
      in: database
    )
    // The writes moved at least one revision forward, so a row was written.
    #expect(revisionsAfter != revisionsBefore)
    let keptMetadata = metadataAfter.filter { row in metadataBefore.contains { $0.last == row.last } }
    expectNoDifference(keptMetadata, metadataBefore)
    _ = try? await fixture.runtime.closeConnection()
  }

  /// The outbox keeps no index its statements cannot use (#1007): every insert, claim, acknowledgement and delete of a
  /// row writes a page of each index, and no statement's plan used `instant_outbox_delivery_window_idx` (its leading
  /// column is the claim state, which the deadline index leads with too and serves). Since #1115 one delivery index
  /// serves the claims' deadlines and the candidate read, in place of the deadline index and #1108's candidate index.
  @Test
  func theOutboxKeepsNoIndexItsStatementsCannotUse() async throws {
    var fixture = try await FastDrainFixture.make(
      suffix: "page-churn-indexes",
      serverSegmentCount: 2,
      pendingSegmentCount: 1
    )
    let indexes = try Self.rows(
      "SELECT name FROM sqlite_master WHERE type = 'index' AND tbl_name = 'instant_outbox' ORDER BY name",
      in: fixture.configuration.persistenceURL
    ).map { $0[0] }
    #expect(indexes.contains("instant_outbox_delivery_idx"), "indexes: \(indexes)")
    for retired in [
      "instant_outbox_delivery_window_idx", "instant_outbox_delivery_deadline_idx", "instant_outbox_delivery_candidate_idx",
    ] {
      #expect(!indexes.contains(retired), "indexes: \(indexes)")
    }
    _ = try? await fixture.runtime.closeConnection()
  }

  /// An acknowledgement moves the row only in the indexes whose columns it changes (#1007). It set the optimistic
  /// overlay flag to the value it already held, and SQLite rewrites a row's entry in every index holding a column an
  /// `UPDATE` sets, changed or not: three indexes rewritten for nothing on every acknowledgement.
  @Test
  func anAcknowledgementLeavesTheIndexesOfColumnsItDoesNotChange() async throws {
    var fixture = try await FastDrainFixture.make(
      suffix: "page-churn-ack-indexes",
      serverSegmentCount: 4,
      pendingSegmentCount: 1
    )
    let (token, mutations) = try await fixture.claimWindow()
    let mutation = try #require(mutations.first)
    let pagesBefore = await fixture.runtime.sqlitePagesWrittenForTesting()

    let transactionID = fixture.server.accept(mutation.transaction.operations)
    _ = try await fixture.runtime.acceptMutationIfPresent(
      id: mutation.id,
      serverTransactionID: transactionID,
      claimToken: token
    )

    let pages = await fixture.runtime.sqlitePagesWrittenForTesting().pages - pagesBefore.pages
    print("outbox-page-churn: one acknowledgement wrote \(pages) pages")
    // The row's leaf, the delivery (claim and deadline), delivery-metadata and watermark indexes it moves, its lifecycle
    // and the revision row: about six pages, against nine with the unused window index and the three rewritten overlay
    // indexes.
    #expect(pages <= 6, "one acknowledgement wrote \(pages) pages")
    _ = try? await fixture.runtime.closeConnection()
  }

  // MARK: - Helpers

  /// Every row `sql` returns, each column as text, read through a second, read-only connection.
  static func rows(_ sql: String, binding: String? = nil, in url: URL) throws -> [[String]] {
    var database: OpaquePointer?
    guard sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
      defer { sqlite3_close(database) }
      throw ReadFailure(message: String(cString: sqlite3_errmsg(database)))
    }
    defer { sqlite3_close(database) }
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
      throw ReadFailure(message: String(cString: sqlite3_errmsg(database)))
    }
    defer { sqlite3_finalize(statement) }
    if let binding {
      sqlite3_bind_text(statement, 1, binding, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
    }
    var rows: [[String]] = []
    while sqlite3_step(statement) == SQLITE_ROW {
      let count = sqlite3_column_count(statement)
      rows.append(
        (0..<count).map { column in
          sqlite3_column_text(statement, column).map { String(cString: $0) } ?? "NULL"
        }
      )
    }
    return rows
  }

  struct ReadFailure: Error, CustomStringConvertible {
    var message: String
    var description: String { message }
  }
}
