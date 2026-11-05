import Foundation
import Testing

@testable import InstantSwiftDataCore

// History:
// - 2026-11-04: #1480: a server refresh diffed each restated result against its stored ownership rows twice, once for
//   the retractions and once for the save, each pass encoding every restated value and reading every row. On the phone
//   the two passes were serverApplyRetractions 15.0 and serverApplyPlan 15.3 CPU-s in 88 minutes of recording (build
//   248's ledger).
// - 2026-11-05: #1116: one comparison a refresh still read every stored row and encoded every restated value; a refresh
//   now reads and encodes the facts of the entities it changed only.

/// What a server refresh reads to compare a restated result with the one it stored (#1480, #1116).
@Suite(.serialized)
struct InstantRefreshPlanningReadTests {
  /// A refresh that restates a stored 32-line page with one line changed reads the ownership rows of that line only and
  /// encodes that line's values only (#1116). Until #1480 it read every row and encoded every value twice, until #1116
  /// once.
  @Test
  func aRefreshComparesARestatedResultWithItsStoredRowsOnce() async throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("InstantRefreshPlanningRead-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "refresh-planning-read",
        persistenceURL: directory.appendingPathComponent("store.sqlite"),
        initialAttributes: PlanningReadPage.attributes
      )
    )
    let page = PlanningReadPage(lines: 32)
    _ = try await runtime.applyLiveRefresh(page.refresh(transactionID: "1", changedLine: nil), receivedAt: .init(milliseconds: 1))

    let before = await runtime.persistence.liveQueryResultDiffCountsForTesting()
    let changed = try await runtime.applyLiveRefresh(
      page.refresh(transactionID: "2", changedLine: 7),
      receivedAt: .init(milliseconds: 2)
    )
    let after = await runtime.persistence.liveQueryResultDiffCountsForTesting()

    #expect(changed.application.mutation.changedEntityIDs == [page.lineID(7)])
    // Three facts a line: its id, its text and its index; of the page's 96, the changed line's three.
    #expect(after.ownershipRowsRead - before.ownershipRowsRead == 3, "rows read: \(after.ownershipRowsRead - before.ownershipRowsRead)")
    #expect(after.valuesEncoded - before.valuesEncoded == 3, "values encoded: \(after.valuesEncoded - before.valuesEncoded)")
    let storedValue = try await runtime.persistence.liveQueryResult(key: page.queryKey())
    let stored = try #require(storedValue)
    #expect(stored.triples.count == 96)
    #expect(stored.triples.contains { $0.entityID == page.lineID(7) && $0.value == .string("line 7 edited") })
  }

  /// F21 (#1109, #1116): a refresh costs its change, not its page. Restating a 256-line page with one line changed reads
  /// and encodes about what a 64-line page's restatement does.
  @Test
  func aLargerPageWithOneLineChangedCostsAboutWhatASmallerOneDoes() async throws {
    var costs: [Int: (rows: Int, values: Int)] = [:]
    for lines in [64, 256] {
      let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("InstantRefreshPlanningRatio-\(UUID().uuidString)", isDirectory: true)
      defer { try? FileManager.default.removeItem(at: directory) }
      let runtime = try await InstantRuntime.bootstrap(
        configuration: InstantRuntimeConfiguration(
          appID: "refresh-planning-ratio-\(lines)",
          persistenceURL: directory.appendingPathComponent("store.sqlite"),
          initialAttributes: PlanningReadPage.attributes
        )
      )
      let page = PlanningReadPage(lines: lines)
      _ = try await runtime.applyLiveRefresh(page.refresh(transactionID: "1", changedLine: nil), receivedAt: .init(milliseconds: 1))
      let before = await runtime.persistence.liveQueryResultDiffCountsForTesting()
      _ = try await runtime.applyLiveRefresh(page.refresh(transactionID: "2", changedLine: 7), receivedAt: .init(milliseconds: 2))
      let after = await runtime.persistence.liveQueryResultDiffCountsForTesting()
      costs[lines] = (after.ownershipRowsRead - before.ownershipRowsRead, after.valuesEncoded - before.valuesEncoded)
    }
    let small = try #require(costs[64])
    let large = try #require(costs[256])
    #expect(large.rows < small.rows * 2, "rows read: \(large.rows) at 256 lines, \(small.rows) at 64")
    #expect(large.values < small.values * 2, "values encoded: \(large.values) at 256 lines, \(small.values) at 64")
  }

  /// #1116: a refresh that compares only the entities it changed leaves the same rows, results and facts as the full
  /// comparison. Two runtimes take the same seeded run of refreshes of two pages, lines edited, added, removed, reordered
  /// and left alone, one or both pages a frame, with a prune between (a writer of ownership rows that is not a server
  /// apply), one with the entity fingerprints off; after every frame both hold the same. Nothing runs in the
  /// background: the cadence prune and the residency sweep are off, so the two stores differ only by the comparison.
  @Test(arguments: [UInt64(1_116), 20_261_105, 7])
  func comparingTheChangedEntitiesLeavesWhatTheFullComparisonLeaves(seed: UInt64) async throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("InstantRefreshFingerprints-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    func runtime(_ name: String) async throws -> InstantRuntime {
      var configuration = InstantRuntimeConfiguration(
        appID: "refresh-fingerprints-\(name)",
        persistenceURL: directory.appendingPathComponent("\(name).sqlite"),
        initialAttributes: FingerprintPage.attributes
      )
      configuration.liveQueryResultPruningWriteInterval = .max
      configuration.residencySweepWriteInterval = .max
      return try await InstantRuntime.bootstrap(configuration: configuration)
    }
    let fingerprinted = try await runtime("fingerprinted")
    let full = try await runtime("full")
    await full.persistence.setUsesLiveQueryEntityFingerprintsForTesting(false)

    var random = SplitMix64(seed: seed)
    var pages = [FingerprintPage(name: "a", lines: 24), FingerprintPage(name: "b", lines: 12)]
    for step in 1...60 {
      if step % 20 == 0 {
        // One closed result stays; the prune releases or unloads the other, and bumps the query-result revision.
        let policy = InstantLiveQueryResultPruningPolicy(maxEntries: 1)
        _ = try await fingerprinted.pruneLiveQueryResults(policy: policy, now: .init(milliseconds: Int64(step)))
        _ = try await full.pruneLiveQueryResults(policy: policy, now: .init(milliseconds: Int64(step)))
      }
      var restated: [FingerprintPage] = []
      for index in pages.indices {
        guard step == 1 || random.next() % 3 != 0 else { continue }
        pages[index].change(using: &random, step: step)
        restated.append(pages[index])
      }
      if restated.isEmpty { continue }
      let frame = FingerprintPage.refresh(restated, transactionID: String(step))
      _ = try await fingerprinted.applyLiveRefresh(frame, receivedAt: .init(milliseconds: Int64(step)))
      _ = try await full.applyLiveRefresh(frame, receivedAt: .init(milliseconds: Int64(step)))
      for page in pages {
        let key = try page.queryKey()
        let rows = try await fingerprinted.persistence.liveQueryOwnershipForTesting(queryKey: key)
        let expectedRows = try await full.persistence.liveQueryOwnershipForTesting(queryKey: key)
        #expect(rows == expectedRows, "seed \(seed), step \(step), page \(page.name): ownership rows differ")
        let result = try await fingerprinted.persistence.storedLiveQueryResultForTesting(key: key)
        let expectedResult = try await full.persistence.storedLiveQueryResultForTesting(key: key)
        #expect(result == expectedResult, "seed \(seed), step \(step), page \(page.name): stored results differ")
      }
      let facts = await Set(fingerprinted.store.snapshot().triples)
      let expectedFacts = await Set(full.store.snapshot().triples)
      #expect(facts == expectedFacts, "seed \(seed), step \(step): the stores' facts differ")
    }
    let fingerprintedReads = await fingerprinted.persistence.liveQueryResultDiffCountsForTesting()
    let fullReads = await full.persistence.liveQueryResultDiffCountsForTesting()
    #expect(
      fingerprintedReads.ownershipRowsRead < fullReads.ownershipRowsRead / 2,
      "rows read: \(fingerprintedReads.ownershipRowsRead) with fingerprints, \(fullReads.ownershipRowsRead) without"
    )
  }
}

/// A page of lines whose text, membership and order change between refreshes, for #1116's comparison test.
struct FingerprintPage {
  static let namespaces = ["fpLinesA", "fpLinesB"]
  static let attributes: [InstantAttribute] = namespaces.flatMap { namespace in
    [
      InstantAttribute.primaryKey(namespace: namespace),
      InstantAttribute(id: "\(namespace)/text", namespace: namespace, name: "text", valueType: .string),
      InstantAttribute(id: "\(namespace)/index", namespace: namespace, name: "index", valueType: .number, isIndexed: true),
    ]
  }

  let name: String
  var namespace: String { name == "a" ? Self.namespaces[0] : Self.namespaces[1] }
  /// Each line's id, text and order.
  private(set) var lines: [(id: String, text: String, index: Int)]
  private var nextLine: Int

  init(name: String, lines count: Int) {
    self.name = name
    lines = (0..<count).map { ("fp-\(name)-\($0)", "line \($0)", $0) }
    nextLine = count
  }

  /// Edits, adds, removes or reorders a few lines, or leaves the page as it is.
  mutating func change(using random: inout SplitMix64, step: Int) {
    for _ in 0..<Int(random.next() % 4) {
      switch random.next() % 5 {
      case 0, 1:
        guard !lines.isEmpty else { continue }
        let index = Int(random.next() % UInt64(lines.count))
        lines[index].text = "line \(lines[index].id) at step \(step) \(random.next() % 1_000)"
      case 2:
        lines.append(("fp-\(name)-\(nextLine)", "new line \(nextLine)", nextLine))
        nextLine += 1
      case 3:
        guard lines.count > 1 else { continue }
        lines.remove(at: Int(random.next() % UInt64(lines.count)))
      default:
        guard !lines.isEmpty else { continue }
        let index = Int(random.next() % UInt64(lines.count))
        lines[index].index = nextLine + 1_000
      }
    }
  }

  func query() -> InstantLiveJSONValue {
    .object([namespace: .object(["$": .object(["order": .object(["index": .string("asc")])])])])
  }

  func queryKey() throws -> String {
    try InstantLiveQueryEncoder.registrationKey(for: query())
  }

  func computation() -> InstantLiveJSONValue {
    let rows: [InstantLiveJSONValue] = lines.map { line in
      func triple(_ attribute: String, _ value: InstantLiveJSONValue) -> InstantLiveJSONValue {
        .array([.string(line.id), .string("\(namespace)/\(attribute)"), value, .number(1)])
      }
      return .array([
        triple("id", .string(line.id)),
        triple("text", .string(line.text)),
        triple("index", .number(Double(line.index))),
      ])
    }
    return .object([
      "instaql-query": query(),
      "instaql-result": .array([
        .object([
          "data": .object(["datalog-result": .object(["join-rows": .array(rows)])]),
          "child-nodes": .array([]),
        ])
      ]),
    ])
  }

  static func refresh(_ pages: [FingerprintPage], transactionID: String) -> InstantLiveRefreshOK {
    InstantLiveRefreshOK(
      clientEventID: nil,
      processedTransactionID: transactionID,
      attrs: [],
      computations: pages.map { $0.computation() }
    )
  }
}

/// A seeded generator, so a failing run can be replayed (SplitMix64).
struct SplitMix64: RandomNumberGenerator {
  private var state: UInt64

  init(seed: UInt64) {
    state = seed
  }

  mutating func next() -> UInt64 {
    state &+= 0x9E37_79B9_7F4A_7C15
    var z = state
    z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
    z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
    return z ^ (z >> 31)
  }
}

/// A flat page of lines the server restates whole, as `refresh-ok` restates every changed query's result.
struct PlanningReadPage {
  static let namespace = "planReadLines"
  static let attributes: [InstantAttribute] = [
    .primaryKey(namespace: namespace),
    InstantAttribute(id: "\(namespace)/text", namespace: namespace, name: "text", valueType: .string),
    InstantAttribute(id: "\(namespace)/index", namespace: namespace, name: "index", valueType: .number, isIndexed: true),
  ]

  let lines: Int

  func lineID(_ index: Int) -> String { "plan-read-line-\(index)" }

  func query() -> InstantLiveJSONValue {
    .object([Self.namespace: .object(["$": .object(["order": .object(["index": .string("asc")])])])])
  }

  func queryKey() throws -> String {
    try InstantLiveQueryEncoder.registrationKey(for: query())
  }

  func refresh(transactionID: String, changedLine: Int?) -> InstantLiveRefreshOK {
    let rows: [InstantLiveJSONValue] = (0..<lines).map { index in
      let id = lineID(index)
      func triple(_ attribute: String, _ value: InstantLiveJSONValue) -> InstantLiveJSONValue {
        .array([.string(id), .string("\(Self.namespace)/\(attribute)"), value, .number(1)])
      }
      return .array([
        triple("id", .string(id)),
        triple("text", .string(index == changedLine ? "line \(index) edited" : "line \(index)")),
        triple("index", .number(Double(index))),
      ])
    }
    return InstantLiveRefreshOK(
      clientEventID: nil,
      processedTransactionID: transactionID,
      attrs: [],
      computations: [
        .object([
          "instaql-query": query(),
          "instaql-result": .array([
            .object([
              "data": .object(["datalog-result": .object(["join-rows": .array(rows)])]),
              "child-nodes": .array([]),
            ])
          ]),
        ])
      ]
    )
  }
}
