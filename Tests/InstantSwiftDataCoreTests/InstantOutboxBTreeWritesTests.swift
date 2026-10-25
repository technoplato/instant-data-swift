// History:
// - 2026-10-25: added (#1115): a live write's save, claim, acknowledgement and echo, each step's log frames counted by
//   the outbox b-tree they land on.

import Foundation
import Testing

@testable import InstantSwiftDataCore

extension StorageIOExercises {
  /// One live write at a time, as a phone with an open socket delivers them (`StorageIOWriteCycle`: Scribe's line
  /// writes answered by `FastDrainServer`), on a small store, with each step's log frames counted by the outbox b-tree
  /// they land on (#1115). The write keys and the effect entities are keyed by their whole row, so as rowid tables each
  /// kept a second b-tree, its primary key's index, holding the same columns, and every save and every echo wrote a
  /// page of both; WITHOUT ROWID the key is the table. The claim moved its row in two delivery indexes, the deadline
  /// index and the candidate one, where one index can hold both orders. In the suite, which runs one test at a time:
  /// the shim's counters are the process's.
  @Test
  func aWritesOutboxRowsWriteNoBTreeTwice() async throws {
    StorageIOCounters.install(asDefault: false)
    let run = try StorageIORun(label: "outbox-btrees")
    defer { run.remove() }
    StorageIOCounters.watch(directory: run.directory)
    defer { StorageIOCounters.watch(directory: nil) }
    let settings = StorageIOExerciseSettings(
      stepLines: 4,
      recordingLines: 30,
      pageLines: 16,
      minutes: 1,
      linesPerMinute: 15,
      fixtureScale: 1
    )
    var cycle = try await SQLitePersistenceStore.$connectionVFSForTesting.withValue(StorageIOCounters.vfsName) {
      try await StorageIOWriteCycle.make(label: "outbox-btrees", directory: run.directory, settings: settings)
    }
    // A recording that is already running: its statements prepared.
    try await cycle.writeLine(into: StorageIOLedger())
    let ledger = StorageIOLedger()
    for _ in 0..<settings.stepLines { try await cycle.writeLine(into: ledger) }
    let map = try StorageIOPageMap.read(store: cycle.configuration.persistenceURL)

    let steps: [StorageIOStep] = [.save, .claim, .ack, .echo]
    let framesByStep = steps.map { step in
      map.byName(ledger.io(step).walFramesByPage).filter {
        $0.key.hasPrefix("instant_outbox") || $0.key.hasPrefix("sqlite_autoindex_instant_outbox")
      }
    }
    let twice = [
      "sqlite_autoindex_instant_outbox_write_keys_1",
      "sqlite_autoindex_instant_outbox_effect_entities_1",
      "instant_outbox_delivery_candidate_idx",
    ]
    let duplicated = zip(steps, framesByStep).flatMap { step, frames in
      twice.filter { frames[$0] != nil }.map { "\(step.rawValue) \($0)" }
    }
    let framesPerWrite =
      Double(framesByStep.reduce(0) { $0 + $1.values.reduce(0, +) }) / Double(max(1, ledger.count(.save)))

    #expect(duplicated.isEmpty, "b-trees that repeat another's rows took frames: \(duplicated)")
    // An acknowledgement leaves the write's key rows alone (#1007; WITHOUT ROWID they have no rowid to watch).
    let acknowledged = framesByStep[steps.firstIndex(of: .ack)!].keys.filter { $0.hasPrefix("instant_outbox_write_keys") }
    #expect(acknowledged.isEmpty, "the acknowledgement wrote the key rows' b-trees: \(acknowledged)")
    #expect(framesPerWrite <= 30, "outbox frames per write \(framesPerWrite): \(Array(zip(steps, framesByStep)))")
  }
}
