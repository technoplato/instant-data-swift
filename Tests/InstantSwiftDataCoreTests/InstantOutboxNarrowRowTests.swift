// History:
// - 2026-10-30: added (#1435): a claim and an acknowledgement write the outbox's narrow row and the indexes whose
//   columns they change, never a page of the write's body.

import CustomDump
import Foundation
import SQLite3
import Testing

@testable import InstantSwiftDataCore

extension StorageIOExercises {
  /// A claim sets a write's claim columns and an acknowledgement its delivery columns; neither changes what the write
  /// is (#1435). While the body (`json`, `lifecycle_json`) shared the row with those columns, each changed the record's
  /// size, and SQLite rewrites a cell whose size changes whole, every overflow page of the body with it, freeing the old
  /// pages (page 1 holds the free list's count); the acknowledgement also re-encoded the body, which carried status,
  /// serverTransactionID and confirmationSource as well as the columns. Measured 2026-10-30 on the phone's ledger: the
  /// claim 108 MB an hour, the acknowledgement 154.
  ///
  /// So each writes only the outbox's row (its leaf, never an overflow page) and the indexes holding a column it sets:
  /// the claim the delivery index, the acknowledgement that, the server-apply watermark index and the outbox revision.
  @Test
  func aClaimAndAnAcknowledgementWriteNoPageOfTheBody() async throws {
    let measured = try await OutboxStepPages.measure(label: "outbox-narrow-row")
    measured.print()

    let claimOutside = measured.frames(of: .claim).filter { !OutboxStepPages.claimTrees.contains($0.key) }
    let acknowledgementOutside = measured.frames(of: .ack).filter {
      !OutboxStepPages.acknowledgementTrees.contains($0.key)
    }
    #expect(claimOutside.isEmpty, "the claim wrote pages beyond its row and index: \(claimOutside)")
    #expect(
      acknowledgementOutside.isEmpty,
      "the acknowledgement wrote pages beyond its row, indexes and revision: \(acknowledgementOutside)"
    )
  }
}

/// A live write's frames by step, by the b-tree and kind of page each landed on (#1435).
struct OutboxStepPages {
  /// The pages a claim may write: the row's leaf, and the delivery index, which holds the claim state and deadline.
  static let claimTrees: Set<String> = ["instant_outbox", "instant_outbox_delivery_idx"]
  /// The pages an acknowledgement may write: the row's leaf, the delivery index (the claim ends), the server-apply
  /// watermark index (status and server transaction id) and the outbox revision in the metadata table.
  static let acknowledgementTrees: Set<String> = [
    "instant_outbox", "instant_outbox_delivery_idx", "instant_outbox_server_apply_watermark_idx",
    "instant_sync_metadata",
  ]

  var writes: Int
  var framesByStep: [StorageIOStep: [String: Int]]

  func frames(of step: StorageIOStep) -> [String: Int] { framesByStep[step] ?? [:] }

  func print() {
    for step in [StorageIOStep.save, .claim, .ack, .echo] {
      let frames = frames(of: step)
      var line = StorageIOLine("outbox-narrow-row", step.rawValue)
      line.add("framesPerWrite", Double(frames.values.reduce(0, +)) / Double(max(1, writes)), digits: 2)
      line.print()
      for (tree, count) in frames.sorted(by: { ($0.value, $1.key) > ($1.value, $0.key) }) {
        var treeLine = StorageIOLine("outbox-narrow-row-btrees", step.rawValue)
        treeLine.add("btree", tree)
        treeLine.add("framesPerWrite", Double(count) / Double(max(1, writes)), digits: 2)
        treeLine.print()
      }
    }
  }

  /// Six live writes, after one that prepares the recording's statements, on a small store (`StorageIOWriteCycle`:
  /// Scribe's line writes answered by `FastDrainServer`), each step's frames named by the page they landed on.
  static func measure(label: String) async throws -> Self {
    StorageIOCounters.install(asDefault: false)
    let run = try StorageIORun(label: label)
    defer { run.remove() }
    StorageIOCounters.watch(directory: run.directory)
    defer { StorageIOCounters.watch(directory: nil) }
    let settings = StorageIOExerciseSettings(
      stepLines: 1, recordingLines: 30, pageLines: 16, minutes: 1, linesPerMinute: 15, fixtureScale: 1
    )
    var cycle = try await SQLitePersistenceStore.$connectionVFSForTesting.withValue(StorageIOCounters.vfsName) {
      try await StorageIOWriteCycle.make(label: label, directory: run.directory, settings: settings)
    }
    try await cycle.writeLine(into: StorageIOLedger())
    let ledger = StorageIOLedger()
    for _ in 0..<settings.stepLines { try await cycle.writeLine(into: ledger) }
    let pages = try OutboxPageKinds.read(store: cycle.configuration.persistenceURL)
    _ = try? await cycle.runtime.closeConnection()
    var framesByStep: [StorageIOStep: [String: Int]] = [:]
    for step in [StorageIOStep.save, .claim, .ack, .echo] {
      framesByStep[step] = pages.byTree(ledger.io(step).walFramesByPage)
    }
    return Self(writes: max(1, ledger.count(.save)), framesByStep: framesByStep)
  }
}

/// Each page's b-tree and kind, from SQLite's `dbstat` on a connection that bypasses the counting shim (#1435). A
/// table's overflow page is named `<table> overflow`, so a step that rewrote a row's spilled body shows apart from one
/// that wrote the row's leaf; a page no b-tree holds now (freed, or the free list's own) is `(free or other)`, and page
/// 1, which holds the free list's count and the file's size, is `sqlite_schema`.
struct OutboxPageKinds {
  var treeByPage: [UInt32: String]

  static func read(store: URL) throws -> Self {
    var connection: OpaquePointer?
    guard sqlite3_open_v2(store.path, &connection, SQLITE_OPEN_READONLY, "unix") == SQLITE_OK, let connection else {
      sqlite3_close_v2(connection)
      throw StorageIOError("open \(store.lastPathComponent) for its page kinds")
    }
    defer { sqlite3_close_v2(connection) }
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(connection, "SELECT name, pageno, pagetype FROM dbstat", -1, &statement, nil) == SQLITE_OK
    else { throw StorageIOError(String(cString: sqlite3_errmsg(connection))) }
    defer { sqlite3_finalize(statement) }
    var treeByPage: [UInt32: String] = [:]
    while sqlite3_step(statement) == SQLITE_ROW {
      let name = sqlite3_column_text(statement, 0).map { String(cString: $0) } ?? "(unnamed)"
      let kind = sqlite3_column_text(statement, 2).map { String(cString: $0) } ?? ""
      treeByPage[UInt32(sqlite3_column_int64(statement, 1))] = kind == "overflow" ? "\(name) overflow" : name
    }
    return Self(treeByPage: treeByPage)
  }

  func byTree(_ framesByPage: [UInt32: Int]) -> [String: Int] {
    var frames: [String: Int] = [:]
    for (page, count) in framesByPage {
      frames[treeByPage[page] ?? "(free or other)", default: 0] += count
    }
    return frames
  }
}
