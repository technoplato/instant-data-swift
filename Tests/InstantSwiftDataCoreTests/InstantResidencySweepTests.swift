import CustomDump
import Foundation
import Testing

@testable import InstantSwiftDataCore

// #1145: after a relaunch the store holds the facts the stored results own and the outbox's effects, and a local read
// finds the rest on disk (#1006, `InstantLocalReadTests.aRelaunchedStoreReadsTheLinesItKeepsOnDisk`). A running session
// kept every row it wrote in memory after the server proved it and no result owned it: on a phone recording the store
// grew about 13,000 facts an hour until the next relaunch. A residency sweep releases those rows from memory, never from
// disk, so a long session's memory is a relaunch's; a write reads a released row before it prepares (#1165).
//
// Equality is checked with `#expect`: in a release build `expectNoDifference` reports through IssueReporting, which
// records nothing outside debug builds.
//
// History:
// - 2026-11-04: #1145: the sweep's tests; a write is proven as a connection proves it (claimed, accepted, then a frame
//   at its transaction), since a local confirmation keeps its outbox row.

@Suite(.serialized, .timeLimit(.minutes(2)))
struct InstantResidencySweepTests {
  /// The running-session shape of the relaunch test: 64 lines this device wrote and the server proved, which no stored
  /// result owns, beside two lines a stored result owns. After a sweep memory holds the two, and the local read still
  /// finds all 66 with their text.
  @Test func provenLinesNoResultOwnsLeaveMemoryAndStayOnDisk() async throws {
    let runtime = try await Self.runtime(ownedLines: 0..<2)
    let owned: Set<String> = ["line-0", "line-1"]
    let written = try await Self.write(lines: 2..<66, to: runtime)
    try await Self.prove(lines: 2..<66, on: runtime)

    let result = try await runtime.sweepResidentEntities()

    #expect(result.releasedEntityCount == 64)
    #expect(result.releasedFactCount == 64 * 3, "id, recordingID and index; the text is on disk only")
    #expect(result.keptEntityCount == 0)
    #expect(result.batchCount == 1)
    #expect(await runtime.store.entityIDsWithFacts(among: owned.union(written)) == owned, "memory holds what a result owns")
    let read = try await runtime.queryLocally(InstantLocalReadTests.recordingLines("recording-1"))
    #expect(read.values.map(\.id) == (0..<66).map { "line-\($0)" }, "every line stays on disk")
    #expect(InstantLocalReadTests.texts(read).suffix(2) == ["Line 64", "Line 65"])
  }

  /// A line whose write the server has not proved stays in memory, and a sweep that finds nothing else takes no gate;
  /// the sweep after the proof releases it.
  @Test func aPendingWriteKeepsItsLineUntilTheServerProvesIt() async throws {
    let runtime = try await Self.runtime()
    _ = try await Self.write(lines: 5..<6, to: runtime)

    var result = try await runtime.sweepResidentEntities()
    #expect(result.releasedEntityCount == 0)
    #expect(result.keptEntityCount == 1)
    #expect(result.batchCount == 0, "nothing to release: no gate")
    #expect(await runtime.store.entityIDsWithFacts(among: ["line-5"]) == ["line-5"])

    try await Self.prove(lines: 5..<6, on: runtime)
    result = try await runtime.sweepResidentEntities()
    #expect(result.releasedEntityCount == 1)
    #expect(await runtime.store.entityIDsWithFacts(among: ["line-5"]).isEmpty)
  }

  /// A line an open observer shows stays in memory, and stays a candidate.
  @Test func aLineAnOpenObserverShowsStays() async throws {
    let runtime = try await Self.runtime()
    let written = try await Self.write(lines: 0..<4, to: runtime)
    try await Self.prove(lines: 0..<4, on: runtime)
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

  /// A write to a line the sweep released reads it from disk first (#1165): the line keeps its other facts, a strict
  /// update of it succeeds, and it is in memory again, whole.
  @Test func aWriteToAReleasedLineKeepsItsOtherFacts() async throws {
    let runtime = try await Self.runtime()
    _ = try await Self.write(lines: 7..<8, to: runtime)
    try await Self.prove(lines: 7..<8, on: runtime)
    #expect(try await runtime.sweepResidentEntities().releasedEntityCount == 1)

    _ = try await runtime.transact(
      InstantStoreTransaction(
        id: "edit-7",
        operations: [
          .requireEntityExists(entityID: "line-7", namespace: "lines"),
          .insert(
            InstantTriple(
              entityID: "line-7", attributeID: "lines/text", value: .string("Edited"), txID: "edit-7",
              txTime: InstantTimestamp(milliseconds: 9_000)
            )
          ),
        ]
      )
    )

    #expect(await runtime.store.entityIDsWithFacts(among: ["line-7"]) == ["line-7"])
    let read = try await runtime.queryLocally(InstantLocalReadTests.recordingLines("recording-1"))
    #expect(read.values.map(\.id) == ["line-7"])
    #expect(InstantLocalReadTests.texts(read) == ["Edited"])
    #expect(read.values.first?.values["index"] == .one(.number(7)))
  }

  /// The sweep starts by itself after the configured number of local writes; the write that starts it is still pending.
  @Test func theSweepRunsAfterTheConfiguredNumberOfWrites() async throws {
    let runtime = try await Self.runtime(sweepEvery: 4)
    let proven = try await Self.write(lines: 0..<3, to: runtime)
    try await Self.prove(lines: 0..<3, on: runtime)
    #expect(await runtime.store.entityIDsWithFacts(among: proven) == proven, "three writes start nothing")

    _ = try await Self.write(lines: 3..<4, to: runtime)
    await runtime.residencySweepSettledForTesting()

    #expect(await runtime.store.entityIDsWithFacts(among: proven).isEmpty)
    #expect(await runtime.store.entityIDsWithFacts(among: ["line-3"]) == ["line-3"], "its write is pending")
  }

  /// A result's save names the entities it stopped owning, once: a line that left a window may be owned by no result now.
  /// A line whose value changed stays owned, and is not named.
  @Test func aSaveNamesTheEntitiesItStoppedOwning() async throws {
    let url = try InstantLocalReadTests.temporaryCacheURL()
    let lines = (0..<3).map { InstantLocalReadTests.line($0, recordingID: "recording-1") }
    let persistence = try SQLitePersistenceStore(
      fileURL: url,
      deferredValueResidency: InstantDeferredValueResidencyPolicy(attributeIDs: ["lines/text"]),
      declaredAttributes: InstantLocalReadTests.attributes,
      recordingOwnershipReleases: true
    )
    try await persistence.bootstrap()
    try await Self.save(lines, owning: lines[0..<3], to: persistence)
    #expect(await persistence.takeOwnershipReleasedEntityIDs().isEmpty)

    var moved = lines
    moved[1] = InstantLocalReadTests.line(1, recordingID: "recording-2")
    try await Self.save(moved, owning: moved[1..<3], to: persistence)
    #expect(await persistence.takeOwnershipReleasedEntityIDs() == ["line-0"])
    #expect(await persistence.takeOwnershipReleasedEntityIDs().isEmpty, "each release is named once")
  }

  // MARK: - Helpers

  /// A runtime over a store whose stored result owns `ownedLines`, sweeping after `sweepEvery` writes (by default never
  /// by itself, so a test sweeps when it chooses; the writes still record their candidates).
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

  /// A line written as the app writes one: its facts inserted in one transaction.
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

  /// Writes `lines`, each in its own transaction; returns their ids.
  static func write(lines: Range<Int>, to runtime: InstantRuntime) async throws -> Set<String> {
    for index in lines {
      _ = try await runtime.transact(transaction(writing: index))
    }
    return Set(lines.map { "line-\($0)" })
  }

  /// Proves the writes of `lines` as a connection does: they are claimed, the server accepts each with its own
  /// transaction number (`transact-ok`), and a frame at the last number restates them, which removes their outbox rows.
  /// A local confirmation (`confirmMutationIfPresent`) keeps a row until such a frame.
  static func prove(lines: Range<Int>, on runtime: InstantRuntime) async throws {
    let ids = Set(lines.map { "write-line-\($0)" })
    var number = 1_000 + lines.lowerBound
    var restated: [InstantTripleOperation] = []
    var claimed: Set<String> = []
    // A claim takes a bounded window of the outbox; claim until every write is taken, as the pump does.
    for attempt in 0..<16 where claimed != ids {
      let token = "residency-sweep-claim-\(lines.lowerBound)-\(attempt)"
      let window = try await runtime.persistence.claimAutomaticOutboxDeliveryWindow(
        InstantAutomaticOutboxClaimRequest(
          claimantID: await runtime.automaticDeliveryClaimantIDForTesting(),
          claimToken: token,
          now: InstantTimestamp(milliseconds: Int64(Date().timeIntervalSince1970 * 1_000)),
          maximumMutationCount: ids.count
        )
      )
      for mutation in window.mutations.sorted(by: PendingMutation.creationOrder) where ids.contains(mutation.id) {
        number += 1
        _ = try await runtime.acceptMutationIfPresent(
          id: mutation.id,
          serverTransactionID: String(number),
          claimToken: token
        )
        restated += mutation.transaction.operations
        claimed.insert(mutation.id)
      }
    }
    #expect(claimed == ids, "every write is claimed")
    _ = try await runtime.applyServerTransactionMergingAttributesForTesting(
      InstantStoreTransaction(id: String(number), operations: restated),
      attributesToMerge: []
    )
    let pending = try await runtime.persistence.countOutboxMutations(status: .pending)
    let confirmed = try await runtime.persistence.countOutboxMutations(status: .confirmed)
    #expect(pending + confirmed == 0, "the proof removes the outbox rows")
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
