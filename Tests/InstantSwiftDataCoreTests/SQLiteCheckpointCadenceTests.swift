// History:
// - 2026-10-24: added (#1118): the store's writer checkpoints every 4,000 frames instead of Apple's 1,000, and a crash
//   or a power loss with a log that long leaves a store that opens consistent, with every write it had made durable.

import CustomDump
import Foundation
import SQLite3
import Testing

@testable import InstantSwiftDataCore

/// The store's writer checkpoints every 4,000 frames instead of Apple's 1,000 (#1118), and what a crash can take.
///
/// Each checkpoint costs three `F_FULLFSYNC`s (the log before the copy, the file after, the restarted log's header).
/// At a recording's 62.5 frames a write, Apple's default ran one every 16 writes: 1,039 full syncs in #1076's simulated
/// hour. A longer log changes what a crash can take, so these tests open the files a crash leaves. An app that dies
/// (killed, crashed, out of memory) loses nothing: every commit was written to the log before its write returned, and
/// the file system keeps what a dead process wrote. A power loss takes the commits since the last checkpoint, because
/// `synchronous = NORMAL` syncs the log only there; the store must still open consistent.
@Suite
struct SQLiteCheckpointCadenceTests {
  @Test
  func theWriterCheckpointsEveryFourThousandFrames() async throws {
    let directory = try InstantTestScratch.directory("checkpoint-cadence-setting")
    let store = try SQLitePersistenceStore(fileURL: directory.appendingPathComponent("store.sqlite"))
    try await store.bootstrap()

    let opened = try await store.walAutocheckpointForTesting()
    // A connection the store opens again keeps it.
    await store.simulateUnexpectedConnectionCloseForTesting()
    let reopened = try await store.walAutocheckpointForTesting()

    expectNoDifference([opened, reopened], [4_000, 4_000])
  }

  /// The copy is the store's files as a process that dies leaves them, taken with more than 2,000 frames in the log:
  /// Apple's default checkpointed before 1,000. The next open replays the log.
  @Test
  func anAppThatDiesWithALongLogKeepsEveryWriteItMade() async throws {
    let directory = try InstantTestScratch.directory("checkpoint-cadence-crash")
    let store = directory.appendingPathComponent("store.sqlite")
    let runtime = try await CheckpointCadence.runtime(store)
    var written: [String] = []
    while try CheckpointCadence.walFrames(store) <= 2_000, written.count < CheckpointCadence.maximumWrites {
      written.append(try await CheckpointCadence.write(written.count, on: runtime))
    }
    let frames = try CheckpointCadence.walFrames(store)
    try #require(frames > 2_000, "After \(written.count) writes the log holds \(frames) frames: a checkpoint ran.")

    let crashed = try CheckpointCadence.copy(store, to: InstantTestScratch.directory("checkpoint-cadence-crashed"))
    let reopened = try await CheckpointCadence.reopen(crashed)

    expectNoDifference(reopened, CheckpointCadence.Reopened(outbox: written, todos: written, integrity: "ok"))
  }
}

extension StorageIOExercises {
  /// A power loss leaves each file as its last full sync left it, and maybe part of what followed. The images below
  /// are taken with more than 2,000 frames of the log unsynced after a checkpoint (Apple's default never left 1,000),
  /// through the shim's journal (`StorageIOCounters.powerLossImage`): the worst case, where the drive kept nothing
  /// after the sync, and drives that wrote the log in order and stopped partway. Each opens consistent, with the
  /// writes in order up to some point and none after it; the worst case keeps exactly the writes the last checkpoint
  /// synced. In the suite, which runs one test at a time: the shim's journal watches one directory for the process.
  @Test
  func aPowerLossWithALongLogKeepsEveryWriteTheLastCheckpointSynced() async throws {
    StorageIOCounters.install(asDefault: false)
    let directory = try InstantTestScratch.directory("checkpoint-cadence-power-loss")
    StorageIOCounters.journalUnsyncedWrites(under: directory)
    defer { StorageIOCounters.journalUnsyncedWrites(under: nil) }
    let store = directory.appendingPathComponent("store.sqlite")
    let runtime = try await SQLitePersistenceStore.$connectionVFSForTesting.withValue(StorageIOCounters.vfsName) {
      try await CheckpointCadence.runtime(store)
    }

    var written: [String] = []
    var durable = 0
    let opened = StorageIOCounters.unsyncedWrites(of: store)
    var unsynced = opened
    while written.count < CheckpointCadence.maximumWrites {
      let before = unsynced
      written.append(try await CheckpointCadence.write(written.count, on: runtime))
      unsynced = StorageIOCounters.unsyncedWrites(of: store)
      // A checkpoint inside this write's commit synced the log, this write included, then the database file.
      if unsynced.databaseFullSyncs > before.databaseFullSyncs { durable = written.count }
      if durable > 0, unsynced.walBytes > 2_000 * CheckpointCadence.frameBytes { break }
    }
    try #require(
      durable > 0 && unsynced.walBytes > 2_000 * CheckpointCadence.frameBytes,
      """
      After \(written.count) writes the log holds \(unsynced.walBytes / CheckpointCadence.frameBytes) unsynced frames \
      after a checkpoint at write \(durable); a checkpoint ran sooner.
      """
    )
    #expect(
      unsynced.partialSyncs == opened.partialSyncs,
      "every sync the writes asked for was full; only those are durable on Apple's drives"
    )
    #expect(unsynced.databaseWrites == 0, "between commits the database file holds nothing unsynced")

    let images = try InstantTestScratch.directory("checkpoint-cadence-power-loss-images")
    let lost = try await CheckpointCadence.reopen(
      StorageIOCounters.powerLossImage(of: store, in: images.appendingPathComponent("none-kept"))
    )
    let synced = Array(written.prefix(durable))
    expectNoDifference(lost, CheckpointCadence.Reopened(outbox: synced, todos: synced, integrity: "ok"))

    for kept in [unsynced.walWrites / 4, unsynced.walWrites / 2, unsynced.walWrites * 3 / 4, unsynced.walWrites] {
      let torn = try await CheckpointCadence.reopen(
        StorageIOCounters.powerLossImage(
          of: store,
          in: images.appendingPathComponent("\(kept)-kept"),
          keepingUnsyncedWrites: kept
        )
      )
      let survived = Array(written.prefix(max(durable, torn.outbox.count)))
      expectNoDifference(torn, CheckpointCadence.Reopened(outbox: survived, todos: survived, integrity: "ok"))
      if kept == unsynced.walWrites {
        expectNoDifference(torn.outbox, written, "a drive that kept every write keeps what a dead app keeps")
      }
    }
  }
}

/// Offline writes of one small entity each, as Scribe makes them while it has no socket: each stays in the outbox.
enum CheckpointCadence {
  /// Enough to fill the log past 6,000 frames at the 4,000-frame setting; a store that checkpoints at 1,000 stops here.
  static let maximumWrites = 600
  /// A frame: its 24-byte header and a 4,096-byte page.
  static let frameBytes = 4_096 + 24

  struct Reopened: Equatable {
    /// The outbox's writes, in order.
    var outbox: [String]
    /// The todos the store shows, by text, sorted.
    var todos: [String]
    /// `PRAGMA integrity_check`.
    var integrity: String
  }

  static func runtime(_ store: URL) async throws -> InstantRuntime {
    var configuration = InstantRuntimeConfiguration(
      appID: "checkpoint-cadence",
      persistenceURL: store,
      initialAttributes: TodoExample.attributes
    )
    configuration.autoConnectLiveTransport = false
    return try await InstantRuntime.bootstrap(configuration: configuration)
  }

  /// One write: a todo whose text is the write's id.
  static func write(_ index: Int, on runtime: InstantRuntime) async throws -> String {
    let id = String(format: "line-%04d", index)
    let createdAt = InstantTimestamp(milliseconds: 1_790_700_000_000 + Int64(index))
    try await runtime.transact(
      InstantStoreTransaction(
        id: id,
        operations: TodoExample.createOperations(id: "todo-\(id)", text: id, createdAt: createdAt, transactionID: id)
      ),
      createdAt: createdAt
    )
    return id
  }

  /// The frames the log file holds: Apple's SQLite cuts the log back to 32 KB as it starts over, so after that the
  /// file is as long as what was written since the last checkpoint.
  static func walFrames(_ store: URL) throws -> Int {
    let bytes = (try? FileManager.default.attributesOfItem(atPath: store.path + "-wal")[.size] as? Int) ?? 0
    return max(0, bytes - 32) / frameBytes
  }

  /// The store's file and its log, as a process that dies leaves them: no `-shm`, which SQLite rebuilds.
  static func copy(_ store: URL, to directory: URL) throws -> URL {
    let target = directory.appendingPathComponent(store.lastPathComponent)
    for suffix in ["", "-wal"] {
      try FileManager.default.copyItem(atPath: store.path + suffix, toPath: target.path + suffix)
    }
    return target
  }

  /// Opens a runtime on a crash's files and reads back what they hold.
  static func reopen(_ store: URL) async throws -> Reopened {
    let runtime = try await Self.runtime(store)
    let outbox = await runtime.outboxMutations().map(\.id)
    let todos = try await TodoExample.decode(runtime.query(TodoExample.query)).map(\.text).sorted()
    return Reopened(outbox: outbox, todos: todos, integrity: try integrity(store))
  }

  /// `PRAGMA integrity_check` on a connection of its own, beside the runtime's.
  static func integrity(_ store: URL) throws -> String {
    var connection: OpaquePointer?
    guard sqlite3_open_v2(store.path, &connection, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK else {
      defer { sqlite3_close_v2(connection) }
      throw StorageIOError("open \(store.lastPathComponent): \(String(cString: sqlite3_errmsg(connection)))")
    }
    defer { sqlite3_close_v2(connection) }
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(connection, "PRAGMA integrity_check", -1, &statement, nil) == SQLITE_OK else {
      throw StorageIOError(String(cString: sqlite3_errmsg(connection)))
    }
    defer { sqlite3_finalize(statement) }
    var lines: [String] = []
    while sqlite3_step(statement) == SQLITE_ROW {
      lines.append(sqlite3_column_text(statement, 0).map { String(cString: $0) } ?? "")
    }
    return lines.joined(separator: "\n")
  }
}
