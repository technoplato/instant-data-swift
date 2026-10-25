// History:
// - 2026-10-25: added (#1115): a live write's save, claim, acknowledgement and echo, each step's log frames counted by
//   the outbox b-tree they land on.
// - 2026-10-25: the rare-state indexes (#1115 slice 2): a live write writes none of the three that find a write in a
//   rare state, and the outbox takes at most 24 frames per write, the issue's criterion.

import CustomDump
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
    let measured = try await OutboxBTreeFrames.measure(label: "outbox-btrees")
    let twice = [
      "sqlite_autoindex_instant_outbox_write_keys_1",
      "sqlite_autoindex_instant_outbox_effect_entities_1",
      "instant_outbox_delivery_candidate_idx",
    ]
    let duplicated = measured.steps.flatMap { step in
      twice.filter { measured.frames[step]?[$0] != nil }.map { "\(step.rawValue) \($0)" }
    }

    #expect(duplicated.isEmpty, "b-trees that repeat another's rows took frames: \(duplicated)")
    // An acknowledgement leaves the write's key rows alone (#1007; WITHOUT ROWID they have no rowid to watch).
    let acknowledged = (measured.frames[.ack] ?? [:]).keys.filter { $0.hasPrefix("instant_outbox_write_keys") }
    #expect(acknowledged.isEmpty, "the acknowledgement wrote the key rows' b-trees: \(acknowledged)")
    #expect(measured.framesPerWrite <= 24, "outbox frames per write \(measured.framesPerWrite): \(measured)")
  }

  /// Three outbox indexes exist to find a write in a rare state (#1115): an active overlay with no receipt (the
  /// synchronization blocker), an active overlay whose effect metadata is not the current version or has no receipt
  /// (effect normalization), and a row whose delivery metadata is older than the current version. A live write is
  /// saved at the current versions with its receipt, so none of them ever returns it, yet as full indexes they held
  /// it: its save, its acknowledgement and its echo each wrote a page of all three, 7 of the outbox's 30 frames.
  @Test
  func aLiveWriteWritesNoRareStateIndex() async throws {
    let measured = try await OutboxBTreeFrames.measure(label: "outbox-rare-state")
    let rareState = [
      "instant_outbox_synchronization_blocker_idx",
      "instant_outbox_effect_normalization_idx",
      "instant_outbox_delivery_metadata_idx",
    ]
    let written = measured.steps.flatMap { step in
      rareState.filter { measured.frames[step]?[$0] != nil }.map { "\(step.rawValue) \($0)" }
    }

    expectNoDifference(written, [])
  }
}

/// A live write's outbox frames by step and b-tree (#1115).
struct OutboxBTreeFrames: CustomStringConvertible {
  var steps: [StorageIOStep]
  /// The frames each step wrote on each outbox b-tree.
  var frames: [StorageIOStep: [String: Int]]
  var framesPerWrite: Double

  var description: String {
    steps.map { "\($0.rawValue) \(frames[$0] ?? [:])" }.joined(separator: "; ")
  }

  /// Four live writes, after one that prepares the recording's statements, on a small store: the steps' frames
  /// counted on the b-trees whose name begins with the outbox's.
  static func measure(label: String) async throws -> Self {
    StorageIOCounters.install(asDefault: false)
    let run = try StorageIORun(label: label)
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
      try await StorageIOWriteCycle.make(label: label, directory: run.directory, settings: settings)
    }
    // A recording that is already running: its statements prepared.
    try await cycle.writeLine(into: StorageIOLedger())
    let ledger = StorageIOLedger()
    for _ in 0..<settings.stepLines { try await cycle.writeLine(into: ledger) }
    let map = try StorageIOPageMap.read(store: cycle.configuration.persistenceURL)

    let steps: [StorageIOStep] = [.save, .claim, .ack, .echo]
    var frames: [StorageIOStep: [String: Int]] = [:]
    for step in steps {
      frames[step] = map.byName(ledger.io(step).walFramesByPage).filter {
        $0.key.hasPrefix("instant_outbox") || $0.key.hasPrefix("sqlite_autoindex_instant_outbox")
      }
    }
    let total = frames.values.reduce(0) { $0 + $1.values.reduce(0, +) }
    return Self(
      steps: steps,
      frames: frames,
      framesPerWrite: Double(total) / Double(max(1, ledger.count(.save)))
    )
  }
}
