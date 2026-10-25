// History:
// - 2026-10-25: added (#1119): an echo with a write pending, and the first echo of a backlog of writes, write no
//   temporary file.

import CustomDump
import Foundation
import Testing

@testable import InstantSwiftDataCore

extension StorageIOExercises {
  /// A phone saves its next interim while the server's answer to the last is on its way (#1119). At the audit's
  /// baseline the phone-shaped exercise's echoes wrote 222 KB each to the server-apply plan's temporary journal, and
  /// nothing to the temporary database's own file or to a sort's (the shim's temp kinds, laptop, release); that exercise
  /// saved each write only after the last one's echo. Here each write after a line's first is saved before the previous
  /// one's echo (the cycle checks one is waiting), and the echoes write no temporary file of any kind. In the
  /// suite, which runs one test at a time: the shim's counters are the process's.
  @Test
  func anEchoWithAWritePendingWritesNoTemporaryFile() async throws {
    let ledger = try await TemporaryFiles.measure(label: "temp-journal-overlap") { cycle, ledger in
      try await cycle.writeLine(into: StorageIOLedger(), overlapping: true)
      for _ in 0..<4 { try await cycle.writeLine(into: ledger, overlapping: true) }
    }

    expectNoDifference(TemporaryFiles.written(ledger.io(.echo)), TemporaryFiles.none)
  }

  /// A phone that recorded offline saves a backlog, and the first echo after it reconnects leaves every write still
  /// waiting to be replayed over the server's answer (#1119, #932). That echo writes no temporary file either. (At the
  /// audit's baseline the phone-shaped echo staged bodies in the plan's temporary tables, 2.06 times an echo; on
  /// 2026-10-25's main neither this echo nor the overlapped ones stage any.)
  @Test
  func aBacklogsFirstEchoWritesNoTemporaryFile() async throws {
    let ledger = try await TemporaryFiles.measure(label: "temp-journal-backlog") { cycle, ledger in
      try await cycle.writeLine(into: StorageIOLedger())
      try await cycle.echoTheFirstOfABacklog(lines: 12, into: ledger)
    }

    expectNoDifference(TemporaryFiles.written(ledger.io(.echo)), TemporaryFiles.none)
  }
}

/// The temporary files a step wrote, by kind (#1119).
enum TemporaryFiles {
  static let none = ["temp 0", "tempjournal 0", "transient 0"]

  static func written(_ io: StorageIOSnapshot) -> [String] {
    [StorageIOFileKind.temporary, .temporaryJournal, .transient].map { "\($0.rawValue) \(io[$0].bytesWritten)" }
  }

  /// Runs `body` on a small store's write cycle, its connection through the counting shim.
  static func measure(
    label: String,
    _ body: (inout StorageIOWriteCycle, StorageIOLedger) async throws -> Void
  ) async throws -> StorageIOLedger {
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
    let ledger = StorageIOLedger()
    try await body(&cycle, ledger)
    return ledger
  }
}

extension StorageIOWriteCycle {
  /// `lines` lines' writes saved while nothing is delivered, as a phone saves them offline; then the first of them is
  /// claimed, acknowledged and echoed while the rest wait (#1119). The cycle checks they do.
  mutating func echoTheFirstOfABacklog(lines: Int, into ledger: StorageIOLedger) async throws {
    var saved = 0
    for _ in 0..<lines {
      for write in script.nextLineWrites() {
        clock.advance(by: millisecondsPerWrite)
        _ = try await runtime.transact(write, createdAt: clock.now())
        saved += 1
      }
    }
    claimSequence += 1
    let token = "storage-io-backlog-\(claimSequence)"
    let window = try await runtime.persistence.claimAutomaticOutboxDeliveryWindow(
      InstantAutomaticOutboxClaimRequest(
        claimantID: runtime.automaticDeliveryClaimantIDForTesting(),
        claimToken: token,
        now: clock.now(),
        maximumMutationCount: 1
      )
    )
    let mutation = try #require(InstantBoundedOutboxDelivery.transportMutations(in: window).first)
    let operations = window.mutations.first { $0.id == mutation.mutationID }?.transaction.operations ?? []
    let transactionID = server.accept(operations)
    _ = try await runtime.acceptMutationIfPresent(
      id: mutation.mutationID,
      serverTransactionID: transactionID,
      claimToken: token
    )
    let touched = Set(operations.compactMap(\.storageIOInsertedTriple).map(\.entityID))
    let deleted = Set(operations.compactMap(\.storageIODeletedEntityID))
    server.timelineWindow = pageLines
    let frame = server.frame(
      queries: server.queries(touching: touched.union(deleted), deleting: deleted),
      processedTransactionID: transactionID
    )
    let waiting = await runtime.pendingMutationCount()
    // A later interim of a line supersedes an earlier one that waits (47 of 72 waited on the Mac mini), so at least one
    // write of every line waits.
    #expect(waiting >= lines, "the backlog waits while the echo applies: \(waiting) of \(saved)")
    let echo = StorageIOProbe.start()
    _ = try await runtime.applyServerTransactionMergingAttributesForTesting(
      frame.transaction,
      attributesToMerge: [],
      liveQueryResultReplacements: frame.replacements
    )
    ledger.record(.echo, echo.stop())
  }
}
