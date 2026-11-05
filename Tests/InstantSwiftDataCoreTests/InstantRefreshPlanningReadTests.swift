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
