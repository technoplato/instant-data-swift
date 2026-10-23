import CryptoKit
import CustomDump
import Foundation
import SQLite3
import Testing

@testable import InstantSwiftDataCore

/// #1015: the local cache never gave back the pages it freed. On one iPhone (2026-10-23, 1.9.13) the cache was a
/// 916 MB file of which 676 MB, 165,125 pages, were free: SQLite reuses a free page before it grows the file, but in
/// `auto_vacuum = NONE` it never shrinks it, and nothing ran `VACUUM`. Compaction runs one `VACUUM` when the free pages
/// are a quarter of the file and 64 MB, under the operation gate, never while the device is hot, in Low Power Mode,
/// short of disk, cancelled, or held by the application. Caches stay in `auto_vacuum = NONE`: `INCREMENTAL` would give
/// pages back in small steps, but its pointer-map pages made every write cost 3-6% more on the library's own write
/// path (`InstantLocalCacheWriteCostTests`).
@Suite(.serialized)
struct InstantLocalCacheCompactionTests {
  // MARK: - A new cache

  /// A new cache keeps no pointer-map pages: every write would pay for them.
  @Test
  func aNewCacheKeepsNoPointerMapPages() async throws {
    let url = try Self.cacheURL("new")
    let persistence = try SQLitePersistenceStore(fileURL: url)
    try await persistence.bootstrap()

    let file = try await persistence.localCacheFile()
    expectNoDifference(file.autoVacuum, .none)
    expectNoDifference(try Self.pragma("journal_mode", at: url), "wal")
  }

  // MARK: - Compaction

  /// The phone's case: deletes left most of the file free. One `VACUUM` rewrites it without its free pages; every row
  /// is as it was, the file on disk shrinks to its live pages, and a second call has nothing to do.
  @Test
  func aCacheMostlyFreeIsRewrittenWithoutItsFreePages() async throws {
    let url = try Self.cacheURL("mostly-free")
    try await Self.fill(url, written: 4_000, kept: 400)
    let runtime = try await Self.runtime(on: url)
    let rows = try Self.tableChecksums(at: url)
    let cacheSpill = try await runtime.persistence.cacheSpillPagesForTesting()

    let compaction = try await runtime.compactLocalCache(policy: Self.policy) { nil }

    expectNoDifference(compaction.outcome, .compacted)
    #expect(compaction.vacuumDuration != nil)
    #expect(
      compaction.before.freePageCount > compaction.before.livePageCount,
      "the fixture should leave most of the file free: \(compaction.before)"
    )
    expectNoDifference(compaction.after.freePageCount, 0)
    #expect(compaction.after.pageCount <= compaction.before.livePageCount)
    expectNoDifference(compaction.after.autoVacuum, .none)
    expectNoDifference(try Self.tableChecksums(at: url), rows)
    expectNoDifference(try Self.fileSize(url), compaction.after.byteCount)
    // The VACUUM bounds its own dirty pages; every other transaction keeps the connection's setting.
    let cacheSpillAfter = try await runtime.persistence.cacheSpillPagesForTesting()
    expectNoDifference(cacheSpillAfter, cacheSpill)

    let again = try await runtime.compactLocalCache(policy: Self.policy) { nil }
    expectNoDifference(again.outcome, .notNeeded)
    expectNoDifference(again.after, compaction.after)
  }

  /// The `VACUUM` runs under the operation gate, so never while a server apply or a write holds it; a write that
  /// arrives meanwhile waits for it and lands after it.
  @Test
  func theVacuumHoldsTheOperationGateAndAWriteLandsAfterIt() async throws {
    let url = try Self.cacheURL("gate")
    try await Self.fill(url, written: 4_000, kept: 400)
    let observed = VacuumObservation()
    let runtime = try await Self.runtime(on: url) { configuration in
      configuration.onLocalCacheVacuumStartingForTesting = { await observed.vacuumStarting() }
    }
    await observed.set(runtime)

    let compaction = try await runtime.compactLocalCache(policy: Self.policy) { nil }
    try await observed.waitForWrite()

    expectNoDifference(compaction.outcome, .compacted)
    let gate = try #require(await observed.gate)
    #expect(gate.holder?.hasPrefix("compactLocalCache") == true, "gate holder: \(String(describing: gate.holder))")
    expectNoDifference(gate.holderPhase, "vacuum")
    let todos = try await runtime.query(TodoExample.query)
    expectNoDifference(todos.map(\.id), ["todo-during-vacuum"])
  }

  /// A cache whose free pages are under a quarter of the file, or under the free bytes the policy asks, is left alone:
  /// nothing is written.
  @Test
  func aCacheWithinItsAllowanceIsLeftAlone() async throws {
    let url = try Self.cacheURL("allowance")
    try await Self.fill(url, written: 1_000, kept: 990)
    let runtime = try await Self.runtime(on: url)

    let compaction = try await runtime.compactLocalCache(policy: Self.policy) { nil }
    let bigFloor = try await runtime.compactLocalCache(
      policy: InstantLocalCacheCompactionPolicy(minimumFreeFraction: 0, minimumFreeBytes: 1 << 40)
    ) { nil }

    expectNoDifference(compaction.outcome, .notNeeded)
    expectNoDifference(compaction.after, compaction.before)
    #expect(compaction.vacuumDuration == nil)
    expectNoDifference(bigFloor.outcome, .notNeeded)
  }

  /// Nothing runs while the device is hot or in Low Power Mode: the file stays as it was, and the outcome says why.
  @Test(
    arguments: [
      (
        InstantStorageMaintenanceConditions(isHot: true, availableDiskBytes: 1 << 40),
        InstantLocalCacheCompaction.Hold.deviceIsHot
      ),
      (InstantStorageMaintenanceConditions(isLowPowerModeEnabled: true, availableDiskBytes: 1 << 40), .lowPowerMode),
    ]
  )
  func nothingRunsWhileTheDeviceIsHotOrInLowPowerMode(
    conditions: InstantStorageMaintenanceConditions,
    hold: InstantLocalCacheCompaction.Hold
  ) async throws {
    let url = try Self.cacheURL("device-hold")
    try await Self.fill(url, written: 4_000, kept: 400)
    let runtime = try await Self.runtime(on: url) { $0.storageMaintenanceConditions = { _ in conditions } }

    let compaction = try await runtime.compactLocalCache(policy: Self.policy) { nil }

    expectNoDifference(compaction.outcome, .held(hold))
    expectNoDifference(compaction.after, compaction.before)
    #expect(compaction.before.freePageCount > compaction.before.livePageCount)
  }

  /// The application's hold (Scribe's: a recording, or a phone off its charger) keeps the `VACUUM` from starting; the
  /// next call tries again.
  @Test
  func theApplicationsHoldKeepsItFromStarting() async throws {
    let url = try Self.cacheURL("application-hold")
    try await Self.fill(url, written: 4_000, kept: 400)
    let runtime = try await Self.runtime(on: url)

    let held = try await runtime.compactLocalCache(policy: Self.policy) { "recording" }

    expectNoDifference(held.outcome, .held(.application("recording")))
    expectNoDifference(held.after, held.before)

    let compacted = try await runtime.compactLocalCache(policy: Self.policy) { nil }

    expectNoDifference(compacted.outcome, .compacted)
    expectNoDifference(compacted.before, held.after)
    expectNoDifference(compacted.after.freePageCount, 0)
  }

  /// A cancelled task does not start the `VACUUM`.
  @Test
  func aCancelledTaskDoesNotStartIt() async throws {
    let url = try Self.cacheURL("cancel")
    try await Self.fill(url, written: 4_000, kept: 400)
    let runtime = try await Self.runtime(on: url)

    let task = Task {
      withUnsafeCurrentTask { $0?.cancel() }
      return try await runtime.compactLocalCache(policy: Self.policy) { nil }
    }
    let compaction = try await task.value

    expectNoDifference(compaction.outcome, .held(.cancelled))
    expectNoDifference(compaction.after, compaction.before)
  }

  /// The `VACUUM` writes a copy of the live pages and a WAL as large before the file shrinks: it waits for that room on
  /// the volume.
  @Test
  func itWaitsForRoomForItsCopyAndItsWAL() async throws {
    let url = try Self.cacheURL("disk-room")
    try await Self.fill(url, written: 4_000, kept: 400)
    let runtime = try await Self.runtime(on: url) {
      $0.storageMaintenanceConditions = { _ in InstantStorageMaintenanceConditions(availableDiskBytes: 1_048_576) }
    }

    let compaction = try await runtime.compactLocalCache(policy: Self.policy) { nil }

    expectNoDifference(
      compaction.outcome,
      .held(
        .insufficientDiskSpace(
          availableBytes: 1_048_576,
          requiredBytes: Self.policy.requiredDiskBytes(compaction.before)
        )
      )
    )
    #expect(Self.policy.requiredDiskBytes(compaction.before) > 2 * Int64(compaction.before.livePageCount * 4_096))
    expectNoDifference(compaction.after, compaction.before)
  }

  /// The storage snapshot says how much of the cache's file is free (#1015), as SQLite counts it.
  @Test
  func theStorageSnapshotSaysHowMuchOfTheFileIsFree() async throws {
    let url = try Self.cacheURL("snapshot")
    try await Self.fill(url, written: 4_000, kept: 400)
    let runtime = try await Self.runtime(on: url)

    let snapshot = try await runtime.storageSnapshot()

    let file = try #require(snapshot.localCacheFile)
    let current = try await runtime.persistence.localCacheFile()
    expectNoDifference(file, current)
    #expect(file.freePageCount > file.livePageCount)
  }

  // MARK: - Helpers

  /// A floor low enough that a few megabytes of free pages are worth a `VACUUM`.
  static let policy = InstantLocalCacheCompactionPolicy(minimumFreeFraction: 0.25, minimumFreeBytes: 1_048_576)

  static let attributes = [
    InstantAttribute(
      id: "compaction/body",
      namespace: "compaction",
      name: "body",
      valueType: .string,
      cardinality: .one,
      isIndexed: false,
      isUnique: false
    )
  ]

  static func cacheURL(_ name: String) throws -> URL {
    // Removed when the process exits (#1021: test stores were never removed and filled the Mac mini).
    let directory = try InstantTestScratch.directory("instant-local-cache-compaction-\(name)")
    return directory.appendingPathComponent("instant.sqlite")
  }

  /// Writes `written` entities of about 1 KB, then a snapshot of the first `kept`: the deleted rows leave their pages
  /// free, scattered between the kept ones.
  static func fill(_ url: URL, written: Int, kept: Int) async throws {
    let persistence = try SQLitePersistenceStore(fileURL: url)
    try await persistence.bootstrap()
    let triples = (0..<written).map { index in
      InstantTriple(
        entityID: "entity-\(index)",
        attributeID: "compaction/body",
        value: .string("body-\(index)-" + String(repeating: "x", count: 1_000)),
        txID: "seed-\(index)",
        txTime: InstantTimestamp(milliseconds: Int64(index + 1))
      )
    }
    try await persistence.saveStoreSnapshot(InstantStoreSnapshot(attributes: attributes, triples: triples))
    try await persistence.saveStoreSnapshot(
      InstantStoreSnapshot(attributes: attributes, triples: Array(triples.prefix(kept)))
    )
    await persistence.simulateUnexpectedConnectionCloseForTesting()
  }

  static func runtime(
    on url: URL,
    configure: (inout InstantRuntimeConfiguration) -> Void = { _ in }
  ) async throws -> InstantRuntime {
    var configuration = InstantRuntimeConfiguration(
      appID: "local-cache-compaction",
      persistenceURL: url,
      initialAttributes: attributes + TodoExample.attributes
    )
    configuration.storageMaintenanceConditions = { _ in InstantStorageMaintenanceConditions(availableDiskBytes: 1 << 40) }
    configure(&configuration)
    return try await InstantRuntime.bootstrap(configuration: configuration)
  }

  static func fileSize(_ url: URL) throws -> Int64 {
    let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
    return (attributes[.size] as? NSNumber)?.int64Value ?? -1
  }

  static func pragma(_ name: String, at url: URL) throws -> String? {
    try withReadOnlyConnection(url) { database in
      var statement: OpaquePointer?
      guard sqlite3_prepare_v2(database, "PRAGMA \(name)", -1, &statement, nil) == SQLITE_OK else {
        throw CompactionTestError.sqlite("PRAGMA \(name)")
      }
      defer { sqlite3_finalize(statement) }
      guard sqlite3_step(statement) == SQLITE_ROW, let text = sqlite3_column_text(statement, 0) else { return nil }
      return String(cString: text)
    }
  }

  /// Every table's rows, in full column order, hashed with SHA-256 on a connection of the test's own: the check the
  /// #1015 measurement ran on copies of the phone's cache. A `VACUUM` may renumber a table's implicit rowids, which no
  /// row's content holds, so they are not part of it.
  static func tableChecksums(at url: URL) throws -> [String: String] {
    try withReadOnlyConnection(url) { database in
      var tables: [String] = []
      var statement: OpaquePointer?
      guard
        sqlite3_prepare_v2(
          database,
          "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%' ORDER BY name",
          -1,
          &statement,
          nil
        ) == SQLITE_OK
      else { throw CompactionTestError.sqlite("list tables") }
      while sqlite3_step(statement) == SQLITE_ROW {
        tables.append(String(cString: sqlite3_column_text(statement, 0)))
      }
      sqlite3_finalize(statement)

      var checksums: [String: String] = [:]
      for table in tables {
        var columns: OpaquePointer?
        guard sqlite3_prepare_v2(database, "SELECT * FROM \"\(table)\" LIMIT 0", -1, &columns, nil) == SQLITE_OK else {
          throw CompactionTestError.sqlite("columns of \(table)")
        }
        let columnCount = sqlite3_column_count(columns)
        sqlite3_finalize(columns)
        let order = (1...max(columnCount, 1)).map(String.init).joined(separator: ", ")
        var rows: OpaquePointer?
        guard sqlite3_prepare_v2(database, "SELECT * FROM \"\(table)\" ORDER BY \(order)", -1, &rows, nil) == SQLITE_OK
        else { throw CompactionTestError.sqlite("rows of \(table)") }
        var hasher = SHA256()
        var count = 0
        while sqlite3_step(rows) == SQLITE_ROW {
          count += 1
          for column in 0..<columnCount {
            let type = sqlite3_column_type(rows, column)
            var tag = UInt8(type)
            withUnsafeBytes(of: &tag) { hasher.update(bufferPointer: $0) }
            if type != SQLITE_NULL, let bytes = sqlite3_column_blob(rows, column) {
              hasher.update(
                bufferPointer: UnsafeRawBufferPointer(start: bytes, count: Int(sqlite3_column_bytes(rows, column)))
              )
            }
          }
        }
        sqlite3_finalize(rows)
        checksums[table] = "\(count) rows " + hasher.finalize().map { String(format: "%02x", $0) }.joined()
      }
      return checksums
    }
  }

  static func withReadOnlyConnection<Value>(_ url: URL, _ body: (OpaquePointer?) throws -> Value) throws -> Value {
    var database: OpaquePointer?
    guard sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
      sqlite3_close_v2(database)
      throw CompactionTestError.sqlite("open \(url.lastPathComponent) read-only")
    }
    defer { sqlite3_close_v2(database) }
    return try body(database)
  }
}

enum CompactionTestError: Error {
  case sqlite(String)
}

/// What the operation gate showed when the `VACUUM` started, and a write started then, which queues behind it.
actor VacuumObservation {
  private(set) var gate: InstantOperationGateSnapshot?
  private var runtime: InstantRuntime?
  private var write: Task<Void, Error>?

  func set(_ runtime: InstantRuntime) {
    self.runtime = runtime
  }

  func vacuumStarting() {
    guard let runtime else { return }
    gate = runtime.operationGateSnapshot()
    write = Task { try await InstantOfflineRuntimeFixture.createTodo("during-vacuum", in: runtime) }
  }

  func waitForWrite() async throws {
    try await write?.value
  }
}
