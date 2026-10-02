import CustomDump
import Foundation
import Testing

@testable import InstantSwiftDataCore

/// A relaunch reads the applied migrations once instead of opening a write transaction per migration (#403).
@Suite(.serialized)
struct SQLiteBootstrapMigrationTests {
  @Test
  func aRelaunchOpensNoMigrationTransaction() async throws {
    let cacheURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("SQLiteBootstrapMigrationTests-\(UUID().uuidString).sqlite")
    defer {
      for suffix in ["", "-wal", "-shm"] {
        try? FileManager.default.removeItem(at: URL(fileURLWithPath: cacheURL.path + suffix))
      }
    }
    let first = try SQLitePersistenceStore(fileURL: cacheURL)
    try await first.bootstrap()
    let firstLaunchMigrationTransactions = await first.migrationTransactionCountForTesting()
    let firstLaunchTransactions = await first.transactionCountsForTesting()

    let relaunched = try SQLitePersistenceStore(fileURL: cacheURL)
    try await relaunched.bootstrap()
    let relaunchMigrationTransactions = await relaunched.migrationTransactionCountForTesting()
    let relaunchTransactions = await relaunched.transactionCountsForTesting()

    // The first launch applies every migration in its own transaction; the relaunch finds them all applied in one read.
    #expect(firstLaunchMigrationTransactions >= 25)
    #expect(firstLaunchTransactions.began >= 25)
    expectNoDifference(relaunchMigrationTransactions, 0)
    expectNoDifference(relaunchTransactions.began, 0)

    // The relaunched store has the whole schema: it reads and writes the outbox and metadata.
    let pending = try await relaunched.countOutboxMutations(status: .pending)
    try await relaunched.saveMetadataValue(
      "1",
      key: "bootstrap-probe",
      updatedAt: InstantTimestamp(milliseconds: 1)
    )
    let probe = try await relaunched.loadMetadataValue(key: "bootstrap-probe")
    expectNoDifference(pending, 0)
    expectNoDifference(probe, "1")
  }

  /// A migration the read did not see, as when another process applies one meanwhile, still checks in its own
  /// transaction and runs once.
  @Test
  func aMigrationMissingFromTheLedgerStillRuns() async throws {
    let cacheURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("SQLiteBootstrapMigrationTests-\(UUID().uuidString).sqlite")
    defer {
      for suffix in ["", "-wal", "-shm"] {
        try? FileManager.default.removeItem(at: URL(fileURLWithPath: cacheURL.path + suffix))
      }
    }
    let first = try SQLitePersistenceStore(fileURL: cacheURL)
    try await first.bootstrap()
    try await first.executeForTesting("DROP TABLE instant_stream_writers")
    try await first.executeForTesting(
      "DELETE FROM instant_schema_migrations WHERE name = '0025_stream_writers'"
    )

    let relaunched = try SQLitePersistenceStore(fileURL: cacheURL)
    try await relaunched.bootstrap()
    let relaunchMigrationTransactions = await relaunched.migrationTransactionCountForTesting()
    let streamWriterTables = try await relaunched.selectInt64ForTesting(
      "SELECT COUNT(*) FROM sqlite_master WHERE type = 'table' AND name = 'instant_stream_writers'"
    )
    let ledgerRows = try await relaunched.selectInt64ForTesting(
      "SELECT COUNT(*) FROM instant_schema_migrations WHERE name = '0025_stream_writers'"
    )
    expectNoDifference(relaunchMigrationTransactions, 1)
    expectNoDifference(streamWriterTables, 1)
    expectNoDifference(ledgerRows, 1)
  }
}
