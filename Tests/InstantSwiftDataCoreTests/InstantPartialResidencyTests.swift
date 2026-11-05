// History:
// - 2026-11-05: added (#1149): a relaunch holds the facts its loaded results own of each entity, not the entity whole;
//   a write, a server apply and a local read reach the rest on disk first, so nothing is lost or missed.

import CustomDump
import Foundation
import Testing

@testable import InstantSwiftDataCore

/// A relaunch holds what its loaded results own, attribute by attribute (#1149).
///
/// A launch loaded every entity a loaded result owns any fact of, whole: on a phone's store (2026-11-04, the consuming
/// app's build 253) the ten newest results own 11,400 facts and the launch held 31,070, 19,686 of them recordings'
/// links to lines, attachments and events that no loaded result selects, because the recordings list owns a few
/// fields of every recording. Upstream builds one store per query result from that result's triples (`Reactor.js`,
/// `createStore(attrs, result.triples)`), so it never holds more of an entity than a result selected.
///
/// Memory holding part of an entity is what #1165 guarded against: a write prepared against the part, and a server
/// apply, diffed the entity's whole picture against its rows on disk and deleted the rest. So a write or an apply that
/// names an entity held in part reads the entity from disk first, and a local read merges it from disk with the
/// entities kept on disk only (#1006).
@Suite(.serialized, .timeLimit(.minutes(2)))
struct InstantPartialResidencyTests {
  /// The recordings list owns a recording's id and title: the relaunch holds those two facts, not its duration nor its
  /// links to lines; a page owns a line's id and index, and the relaunch holds those, not its recording.
  @Test
  func aRelaunchHoldsTheFactsItsLoadedResultsOwnOfAnEntity() async throws {
    let (_, runtime) = try await Self.relaunchedStore()

    expectNoDifference(
      Self.described(await runtime.store.facts(of: ["recording-1"])),
      ["recordings/id=\"recording-1\"", "recordings/title=\"One\""]
    )
    expectNoDifference(
      Self.described(await runtime.store.facts(of: ["line-0"])),
      ["lines/id=\"line-0\"", "lines/index=0"]
    )
  }

  /// A write to an entity held in part keeps the facts it does not restate on disk.
  @Test
  func aWriteToAnEntityHeldInPartKeepsItsOtherFactsOnDisk() async throws {
    let (url, runtime) = try await Self.relaunchedStore()

    try await runtime.transact(
      InstantStoreTransaction(
        id: "retitle-recording-1",
        operations: [.insert(Self.fact("recording-1", "recordings/title", .string("Uno")))]
      ),
      createdAt: Self.now
    )

    expectNoDifference(
      try InstantNonResidentWriteTests.facts(url, entityID: "recording-1"),
      [
        "recordings/durationMs=100",
        "recordings/id=\"recording-1\"",
        "recordings/lines=\"line-0\"",
        "recordings/lines=\"line-1\"",
        "recordings/lines=\"line-2\"",
        "recordings/title=\"Uno\"",
      ]
    )
    #expect(
      Self.described(await runtime.store.facts(of: ["recording-1"])).contains("recordings/title=\"Uno\""),
      "memory holds the written title"
    )
  }

  /// A server apply that restates one field of an entity held in part keeps its other facts on disk.
  @Test
  func aServerApplyToAnEntityHeldInPartKeepsItsOtherFactsOnDisk() async throws {
    let (url, runtime) = try await Self.relaunchedStore()

    _ = try await runtime.applyServerTransactionMergingAttributesForTesting(
      InstantStoreTransaction(
        id: "server-retitle-recording-1",
        operations: [
          .insert(Self.fact("recording-1", "recordings/title", .string("Uno"), txID: "server-retitle-recording-1"))
        ]
      ),
      attributesToMerge: []
    )

    expectNoDifference(
      try InstantNonResidentWriteTests.facts(url, entityID: "recording-1"),
      [
        "recordings/durationMs=100",
        "recordings/id=\"recording-1\"",
        "recordings/lines=\"line-0\"",
        "recordings/lines=\"line-1\"",
        "recordings/lines=\"line-2\"",
        "recordings/title=\"Uno\"",
      ]
    )
  }

  /// A page owns a line's id and index: a local read of the recording's lines by its lookup finds that line by its
  /// recording on disk, with the lines kept on disk only.
  @Test
  func aLocalReadFindsAnEntityHeldInPartByWhatItKeepsOnDisk() async throws {
    let (_, runtime) = try await Self.relaunchedStore()

    let read = try await runtime.queryLocally(InstantLocalReadTests.recordingLines("recording-1"))

    expectNoDifference(read.values.map(\.id), ["line-0", "line-1", "line-2"])
  }

  /// A write to a line held in part keeps its recording and text on disk.
  @Test
  func aWriteToALineHeldInPartKeepsItsOtherFactsOnDisk() async throws {
    let (url, runtime) = try await Self.relaunchedStore()

    try await runtime.transact(
      InstantStoreTransaction(id: "move-line-0", operations: [.insert(Self.fact("line-0", "lines/index", .number(100)))]),
      createdAt: Self.now
    )

    expectNoDifference(
      try InstantNonResidentWriteTests.facts(url, entityID: "line-0"),
      [
        "lines/id=\"line-0\"",
        "lines/index=100",
        "lines/recordingID=\"recording-1\"",
        "lines/text=\"Line 0\"",
      ]
    )
  }
}

// MARK: - Fixtures

extension InstantPartialResidencyTests {
  static let now = InstantTimestamp(milliseconds: 1_790_900_000_000)

  static let attributes: [InstantAttribute] = InstantLocalReadTests.attributes + [
    .primaryKey(namespace: "recordings"),
    InstantAttribute(id: "recordings/title", namespace: "recordings", name: "title", valueType: .string),
    InstantAttribute(id: "recordings/durationMs", namespace: "recordings", name: "durationMs", valueType: .number),
    InstantAttribute(
      id: "recordings/lines", namespace: "recordings", name: "lines", valueType: .ref, isRequired: false,
      cardinality: .many, linkNamespace: "lines"
    ),
  ]

  static func fact(
    _ entityID: String, _ attributeID: String, _ value: InstantValue, txID: String = "local"
  ) -> InstantTriple {
    InstantTriple(entityID: entityID, attributeID: attributeID, value: value, txID: txID, txTime: now)
  }

  /// `facts` as `attribute=value`, sorted, values as their plain JSON.
  static func described(_ facts: [InstantTriple]) -> [String] {
    facts.map { fact -> String in
      switch fact.value {
      case let .string(text), let .ref(text): "\(fact.attributeID)=\"\(text)\""
      case let .number(number): "\(fact.attributeID)=\(number.rounded() == number ? String(Int(number)) : String(number))"
      default: "\(fact.attributeID)=\(fact.value)"
      }
    }
    .sorted()
  }

  /// A store as a relaunch finds it: recording-1 with its title, duration and links to three lines; the newest of two
  /// stored results, the recordings list, owns the recording's id and title; the other, a page, owns line-0's id and
  /// index. Both are loaded at the relaunch (ten are). A runtime opened on it.
  static func relaunchedStore() async throws -> (URL, InstantRuntime) {
    let url = try InstantLocalReadTests.temporaryCacheURL()
    let lines = (0..<3).map { InstantLocalReadTests.line($0, recordingID: "recording-1") }
    let seed = InstantTimestamp(milliseconds: 1_000)
    let recording = [
      InstantTriple(entityID: "recording-1", attributeID: "recordings/id", value: .string("recording-1"), txID: "seed", txTime: seed),
      InstantTriple(entityID: "recording-1", attributeID: "recordings/title", value: .string("One"), txID: "seed", txTime: seed),
      InstantTriple(entityID: "recording-1", attributeID: "recordings/durationMs", value: .number(100), txID: "seed", txTime: seed),
    ] + (0..<3).map {
      InstantTriple(
        entityID: "recording-1", attributeID: "recordings/lines", value: .ref("line-\($0)"), txID: "seed", txTime: seed
      )
    }
    let persistence = try SQLitePersistenceStore(
      fileURL: url,
      deferredValueResidency: InstantDeferredValueResidencyPolicy(attributeIDs: ["lines/text"]),
      declaredAttributes: attributes
    )
    try await persistence.bootstrap()
    let state = try await persistence.loadCompactState()
    // A result as old as 1970 would be past the pruning policy's age limit, and a launch would collect it.
    let stamp = Int64(Date().timeIntervalSince1970 * 1_000)
    let results = [
      InstantPersistedLiveQueryResult(
        replacement: InstantLiveQueryResultReplacement(
          key: "page",
          triples: lines[0].filter { ["lines/id", "lines/index"].contains($0.attributeID) },
          pageInfo: nil
        ),
        updatedAt: InstantTimestamp(milliseconds: stamp - 1)
      ),
      InstantPersistedLiveQueryResult(
        replacement: InstantLiveQueryResultReplacement(
          key: "recordings-list",
          triples: recording.filter { ["recordings/id", "recordings/title"].contains($0.attributeID) },
          pageInfo: nil
        ),
        updatedAt: InstantTimestamp(milliseconds: stamp)
      ),
    ]
    let didSave = try await persistence.saveLiveRefresh(
      InstantPersistenceSnapshot(store: InstantStoreSnapshot(attributes: attributes, triples: lines.flatMap { $0 } + recording)),
      queryResults: results,
      storeChanged: true,
      outboxChanged: false,
      metadataKey: "test.partial-residency",
      metadataValue: "seeded",
      metadataUpdatedAt: InstantTimestamp(milliseconds: stamp),
      expectedStoreRevision: state.storeRevision,
      expectedOutboxRevision: state.outboxRevision,
      expectedAttributeRevision: state.attributeRevision
    )
    expectNoDifference(didSave, true)
    var configuration = InstantLocalReadTests.configuration(url, lookup: true)
    configuration.initialAttributes = attributes
    let runtime = try await InstantRuntime.bootstrap(configuration: configuration)
    return (url, runtime)
  }
}
