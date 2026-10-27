import CustomDump
import Foundation
import SQLite3
import Testing

@testable import InstantSwiftDataCore

/// #1245: on one device a recording hour wrote 3.31 GB, and 0.80 GB of it no meter named: the store's write meter
/// counts the pages each store call writes to the write-ahead log, and nothing counted a checkpoint's copies into the
/// database file, the temporary database, its journal or a sort's transient file. The file meter is a pass-through VFS
/// in front of the system's that counts what SQLite writes to each kind of file.
///
/// The meter's counts are the process's, and other suites write stores in parallel, so each test asserts what its own
/// writes add at least.
@Suite
struct InstantSQLiteFileMeterTests {
  @Test
  func aStoresLogPagesAreCountedUnderTheWriteAheadLog() async throws {
    let directory = try Self.temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = try SQLitePersistenceStore(
      fileURL: directory.appendingPathComponent("state.sqlite"),
      declaredAttributes: TodoExample.attributes
    )
    try await store.bootstrap()

    let filesBefore = InstantSQLiteFileMeter.snapshot()
    let pagesBefore = InstantStorageWriteMeter.snapshot()
    try await store.saveStoreSnapshot(InstantStoreSnapshot(attributes: TodoExample.attributes, triples: Self.triples))
    let files = InstantSQLiteFileMeter.snapshot().subtracting(filesBefore)
    let save = try #require(
      InstantStorageWriteMeter.snapshot().subtracting(pagesBefore).operations["saveStoreSnapshot(_:)"]
    )

    // Each page the save wrote is one frame of the log: the page and a 24-byte frame header.
    #expect(save.pagesWritten >= 8, "pages: \(save.pagesWritten)")
    #expect(files[.wal].bytesWritten >= save.pagesWritten * 4_096, "files: \(files)")
    #expect(files[.wal].writes >= save.pagesWritten, "files: \(files)")
  }

  @Test
  func aCheckpointsCopiesAreCountedUnderTheDatabaseFile() throws {
    let directory = try Self.temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let connection = try Self.openThroughTheMeter(directory.appendingPathComponent("raw.sqlite"))
    defer { sqlite3_close_v2(connection) }
    try Self.execute("PRAGMA journal_mode = WAL", on: connection)
    try Self.execute("CREATE TABLE line (id INTEGER PRIMARY KEY, text TEXT NOT NULL)", on: connection)
    try Self.execute(
      """
      WITH RECURSIVE n(x) AS (SELECT 1 UNION ALL SELECT x + 1 FROM n WHERE x < 400)
      INSERT INTO line (text) SELECT printf('%.*c', 300, 'w') FROM n
      """,
      on: connection
    )

    let before = InstantSQLiteFileMeter.snapshot()
    try Self.execute("PRAGMA wal_checkpoint(TRUNCATE)", on: connection)
    let checkpoint = InstantSQLiteFileMeter.snapshot().subtracting(before)

    // 400 rows of about 300 bytes are about 30 pages; the checkpoint copies each into the database file once and syncs
    // it.
    #expect(checkpoint[.database].bytesWritten >= 25 * 4_096, "files: \(checkpoint)")
    #expect(checkpoint[.database].syncs >= 1, "files: \(checkpoint)")
    #expect(checkpoint[.wal].truncates >= 1, "files: \(checkpoint)")
  }

  @Test
  func aTemporaryTablesWritesAreCountedUnderTheTemporaryFiles() throws {
    let directory = try Self.temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let connection = try Self.openThroughTheMeter(directory.appendingPathComponent("raw.sqlite"))
    defer { sqlite3_close_v2(connection) }
    try Self.execute("PRAGMA journal_mode = WAL", on: connection)
    try Self.execute("PRAGMA temp_store = FILE", on: connection)
    try Self.execute("CREATE TEMP TABLE staged (id INTEGER PRIMARY KEY, body TEXT NOT NULL)", on: connection)
    // A small page cache, so the temporary database's pages reach its file inside the transaction.
    try Self.execute("PRAGMA temp.cache_size = 10", on: connection)

    let before = InstantSQLiteFileMeter.snapshot()
    for _ in 0..<2 {
      try Self.execute("BEGIN", on: connection)
      try Self.execute("DELETE FROM staged", on: connection)
      try Self.execute(
        """
        WITH RECURSIVE n(x) AS (SELECT 1 UNION ALL SELECT x + 1 FROM n WHERE x < 300)
        INSERT INTO staged (body) SELECT printf('%.*c', 500, 's') FROM n
        """,
        on: connection
      )
      try Self.execute("COMMIT", on: connection)
    }
    let staged = InstantSQLiteFileMeter.snapshot().subtracting(before)

    let temporaryBytes = staged[.temporary].bytesWritten + staged[.temporaryJournal].bytesWritten
    #expect(temporaryBytes >= 4 * 4_096, "files: \(staged)")
    #expect(staged.bytesWritten >= temporaryBytes)
  }

  @Test
  func theStoresWriterAndReadersOpenThroughTheMeter() async throws {
    let directory = try Self.temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = try SQLitePersistenceStore(
      fileURL: directory.appendingPathComponent("state.sqlite"),
      declaredAttributes: TodoExample.attributes
    )
    try await store.bootstrap()

    let vfs = await store.connectionVFSNameForTesting()
    expectNoDifference(vfs, InstantSQLiteFileMeter.vfsName)
  }

  private static let triples = (0..<200).map { index in
    InstantTriple(
      entityID: "todo-\(index)",
      attributeID: TodoExample.attributes[1].id,
      value: .string(String(repeating: "words of todo \(index) ", count: 8)),
      txID: "tx-\(index)",
      txTime: InstantTimestamp(milliseconds: Int64(index) + 1)
    )
  }

  private static func temporaryDirectory() throws -> URL {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("InstantSQLiteFileMeterTests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
  }

  private static func openThroughTheMeter(_ url: URL) throws -> OpaquePointer {
    let vfs = try #require(InstantSQLiteFileMeter.registeredVFSName())
    var connection: OpaquePointer?
    let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_NOMUTEX
    guard sqlite3_open_v2(url.path, &connection, flags, vfs) == SQLITE_OK, let connection else {
      sqlite3_close_v2(connection)
      throw CocoaError(.fileWriteUnknown)
    }
    return connection
  }

  private static func execute(_ sql: String, on connection: OpaquePointer) throws {
    var message: UnsafeMutablePointer<CChar>?
    guard sqlite3_exec(connection, sql, nil, nil, &message) == SQLITE_OK else {
      let text = message.map { String(cString: $0) } ?? "unknown"
      sqlite3_free(message)
      Issue.record("SQLite: \(text) in \(sql)")
      throw CocoaError(.fileWriteUnknown)
    }
  }
}
