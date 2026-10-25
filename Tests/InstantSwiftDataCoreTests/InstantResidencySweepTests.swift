import CustomDump
import Foundation
import Testing

@testable import InstantSwiftDataCore

// #1145 (2026-10-25): after a relaunch the store holds only the facts a stored result owns, and a local read finds the
// rest on disk (#1006, `InstantLocalReadTests.aRelaunchedStoreReadsTheLinesItKeepsOnDisk`); a running session kept every
// row it wrote in memory once the server acknowledged it and no result owned it, +12.1 MB of heap an hour in the memory
// audit's two-hour replay. A residency sweep releases those rows from memory, never from disk, so a long session's memory
// is a relaunch's.
//
// Equality is checked with `#expect`: in a release build `expectNoDifference` reports through IssueReporting, which
// records nothing outside debug builds.
//
// History:
// - 2026-10-25: #1145: the sweep's tests.

@Suite(.serialized, .timeLimit(.minutes(2)))
struct InstantResidencySweepTests {
  /// The running-session shape of the relaunch test: 64 lines this device wrote and the server acknowledged, which no
  /// stored result owns, beside two lines a stored result owns. After a sweep memory holds the two, and the local read
  /// still finds all 66 with their text.
  @Test func acknowledgedLinesNoResultOwnsLeaveMemoryAndStayOnDisk() async throws {
    let runtime = try await Self.runtime(ownedLines: 0..<2)
    let owned: Set<String> = ["line-0", "line-1"]
    let written = try await Self.write(lines: 2..<66, to: runtime, acknowledged: true)

    let result = try await runtime.sweepResidentEntities()

    #expect(result.releasedEntityCount == 64)
    #expect(result.keptEntityCount == 0)
    #expect(await runtime.store.entityIDsWithFacts(among: owned.union(written)) == owned, "memory holds what a result owns")
    let read = try await runtime.queryLocally(InstantLocalReadTests.recordingLines("recording-1"))
    #expect(read.values.map(\.id) == (0..<66).map { "line-\($0)" }, "every line stays on disk")
    #expect(InstantLocalReadTests.texts(read).suffix(2) == ["Line 64", "Line 65"])
  }

  /// A line whose write the server has not acknowledged stays in memory; the sweep after the acknowledgment releases it.
  @Test func aPendingWriteKeepsItsLineUntilTheServerAcknowledgesIt() async throws {
    let runtime = try await Self.runtime()
    let pending = Self.transaction(writing: 5)
    _ = try await runtime.transact(pending)

    var result = try await runtime.sweepResidentEntities()
    #expect(result.releasedEntityCount == 0)
    #expect(result.keptEntityCount == 1)
    #expect(await runtime.store.entityIDsWithFacts(among: ["line-5"]) == ["line-5"])

    _ = try await runtime.confirmMutationIfPresent(id: pending.id)
    result = try await runtime.sweepResidentEntities()
    #expect(result.releasedEntityCount == 1)
    #expect(await runtime.store.entityIDsWithFacts(among: ["line-5"]).isEmpty)
  }

  /// A line an open observer shows stays in memory, and stays a candidate.
  @Test func aLineAnOpenObserverShowsStays() async throws {
    let runtime = try await Self.runtime()
    let written = try await Self.write(lines: 0..<4, to: runtime, acknowledged: true)
    var plan = InstantLocalReadTests.recordingLines("recording-1")
    plan.limit = 2
    let lease = await runtime.observeLocallyLease(plan)
    var answers = lease.stream.makeAsyncIterator()
    let shown = await answers.next()
    #expect(shown?.values.map(\.id) == ["line-0", "line-1"])

    let result = try await runtime.sweepResidentEntities()
    await lease.cancel()

    #expect(result.releasedEntityCount == 2)
    #expect(result.keptEntityCount == 2)
    #expect(await runtime.store.entityIDsWithFacts(among: written) == ["line-0", "line-1"])
  }

  /// A write to a line the sweep released saves only what it writes: the line keeps its other attributes on disk.
  @Test func aWriteToAReleasedLineKeepsItsOtherAttributes() async throws {
    let runtime = try await Self.runtime()
    _ = try await Self.write(lines: 7..<8, to: runtime, acknowledged: true)
    #expect(try await runtime.sweepResidentEntities().releasedEntityCount == 1)

    let edit = InstantStoreTransaction(
      id: "edit-7",
      operations: [
        .insert(
          InstantTriple(
            entityID: "line-7", attributeID: "lines/text", value: .string("Edited"), txID: "edit-7",
            txTime: InstantTimestamp(milliseconds: 9_000)
          )
        )
      ]
    )
    _ = try await runtime.transact(edit)
    _ = try await runtime.confirmMutationIfPresent(id: edit.id)
    _ = try await runtime.sweepResidentEntities()

    let read = try await runtime.queryLocally(InstantLocalReadTests.recordingLines("recording-1"))
    #expect(read.values.map(\.id) == ["line-7"])
    #expect(InstantLocalReadTests.texts(read) == ["Edited"])
    #expect(read.values.first?.values["index"] == .one(.number(7)))
  }

  /// The sweep starts by itself after the configured number of local writes; the write that starts it is still pending.
  @Test func theSweepRunsAfterTheConfiguredNumberOfWrites() async throws {
    let runtime = try await Self.runtime(sweepEvery: 4)
    let acknowledged = try await Self.write(lines: 0..<3, to: runtime, acknowledged: true)
    #expect(await runtime.store.entityIDsWithFacts(among: acknowledged) == acknowledged, "three writes start nothing")

    _ = try await runtime.transact(Self.transaction(writing: 3))
    await runtime.residencySweepSettledForTesting()

    #expect(await runtime.store.entityIDsWithFacts(among: acknowledged).isEmpty)
    #expect(await runtime.store.entityIDsWithFacts(among: ["line-3"]) == ["line-3"], "its write is pending")
  }

  /// A result's save names the entities whose ownership rows it removed: a line that left a window may be owned by no
  /// result now.
  @Test func aSaveNamesTheEntitiesItStoppedOwning() async throws {
    let url = try InstantLocalReadTests.temporaryCacheURL()
    let lines = (0..<3).map { InstantLocalReadTests.line($0, recordingID: "recording-1") }
    let persistence = try SQLitePersistenceStore(
      fileURL: url,
      deferredValueResidency: InstantDeferredValueResidencyPolicy(attributeIDs: ["lines/text"]),
      declaredAttributes: InstantLocalReadTests.attributes
    )
    try await persistence.bootstrap()
    await persistence.recordOwnershipReleases(true)
    try await Self.save(lines, owning: lines[0..<3], to: persistence)
    #expect(await persistence.takeOwnershipReleasedEntityIDs().isEmpty)

    try await Self.save(lines, owning: lines[1..<3], to: persistence)
    #expect(await persistence.takeOwnershipReleasedEntityIDs() == ["line-0"])
    #expect(await persistence.takeOwnershipReleasedEntityIDs().isEmpty, "each release is named once")
  }

  // MARK: - Helpers

  /// A runtime over a store whose stored result owns `ownedLines`, sweeping after `sweepEvery` writes (by default
  /// never by itself, so a test sweeps when it chooses; the writes still record their candidates).
  static func runtime(ownedLines: Range<Int> = 0..<0, sweepEvery: Int = 1_000_000) async throws -> InstantRuntime {
    let url = try InstantLocalReadTests.temporaryCacheURL()
    if !ownedLines.isEmpty {
      let lines = ownedLines.map { InstantLocalReadTests.line($0, recordingID: "recording-1") }
      try await InstantLocalReadTests.seed(url, lines: lines, ownedBy: ["preview": lines[...]])
    }
    var configuration = InstantLocalReadTests.configuration(url, lookup: true)
    configuration.residencySweepWriteInterval = sweepEvery
    return try await InstantRuntime.bootstrap(configuration: configuration)
  }

  /// A line written as the app writes one: its facts inserted in one transaction (`.merge` deep-merges JSON values).
  static func transaction(writing index: Int) -> InstantStoreTransaction {
    let id = "write-line-\(index)"
    return InstantStoreTransaction(
      id: id,
      operations: InstantLocalReadTests.line(index, recordingID: "recording-1").map { triple in
        var triple = triple
        triple.txID = id
        return .insert(triple)
      }
    )
  }

  /// Writes `lines`, each acknowledged by the server when `acknowledged`; returns their ids.
  static func write(lines: Range<Int>, to runtime: InstantRuntime, acknowledged: Bool) async throws -> Set<String> {
    for index in lines {
      let transaction = transaction(writing: index)
      _ = try await runtime.transact(transaction)
      if acknowledged {
        _ = try await runtime.confirmMutationIfPresent(id: transaction.id)
      }
    }
    return Set(lines.map { "line-\($0)" })
  }

  /// Saves `lines` and one stored result, "window", owning `owned`.
  static func save(
    _ lines: [[InstantTriple]],
    owning owned: ArraySlice<[InstantTriple]>,
    to persistence: SQLitePersistenceStore
  ) async throws {
    let state = try await persistence.loadCompactState()
    let now = InstantTimestamp(milliseconds: Int64(Date().timeIntervalSince1970 * 1_000))
    let didSave = try await persistence.saveLiveRefresh(
      InstantPersistenceSnapshot(
        store: InstantStoreSnapshot(attributes: InstantLocalReadTests.attributes, triples: lines.flatMap { $0 })
      ),
      queryResults: [
        InstantPersistedLiveQueryResult(
          replacement: InstantLiveQueryResultReplacement(key: "window", triples: owned.flatMap { $0 }, pageInfo: nil),
          updatedAt: now
        )
      ],
      storeChanged: true,
      outboxChanged: false,
      metadataKey: "test.residency-sweep",
      metadataValue: "saved",
      metadataUpdatedAt: now,
      expectedStoreRevision: state.storeRevision,
      expectedOutboxRevision: state.outboxRevision,
      expectedAttributeRevision: state.attributeRevision
    )
    #expect(didSave)
  }
}
