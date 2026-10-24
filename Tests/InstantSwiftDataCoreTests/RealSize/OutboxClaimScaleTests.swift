import CustomDump
import Foundation
import SQLite3
import Testing

@testable import InstantSwiftDataCore

// #1108, #1114 (2026-10-24): the delivery pump's claim pass, after every write and every acknowledgement, read every
// ready outbox row to find the next write to deliver, refused writes included. Its candidate read and its continuation
// check filter `delivery_claim_state = ? AND (delivery_state = ? OR (legacy metadata))`; the `OR` left SQLite one plan,
// a search on the claim state alone and a sort, so each of the 663 refused writes on one phone's store was visited
// through its body's overflow pages. On the phone-shaped store the claim held the operation gate 402-524 ms of every
// recording minute, about 60% of the gate (#1072's recording minutes, Mac mini, release).
//
// History:
// - 2026-10-24: #1108: the scale test.
// - 2026-10-24: #1108, #1114: the delivery's overlay check and the supersession tail read, which walked every row too.

@Suite(.serialized)
struct OutboxClaimScaleTests {
  @Test("The pump's candidate read and continuation check visit no refused write: 400 of them cost what 7 do")
  func claimReadsDoNotGrowWithRefusedWrites() async throws {
    let few = RealSizeShape.phone.scaled(0.01)
    var many = few
    many.refusedWrites = 400

    let fewSteps = try await Self.claimReadSteps(few, label: "claim-few")
    let manySteps = try await Self.claimReadSteps(many, label: "claim-many")

    // SQLite's virtual-machine steps: a read that visited each refused write would take some ten more per row.
    #expect(
      manySteps.candidates <= fewSteps.candidates + 50,
      "The candidate read took \(manySteps.candidates) steps beside 400 refused writes against \(fewSteps.candidates) beside 7."
    )
    #expect(
      manySteps.check <= fewSteps.check + 50,
      "The continuation check took \(manySteps.check) steps beside 400 refused writes against \(fewSteps.check) beside 7."
    )
  }

  // After the claim, #1076's exercise still read 1.87 MB of the outbox per write in delivery on the phone-shaped store:
  // the unknown-overlay check filtered `optimistic_overlay_active != 0`, which no index seeks, so it scanned the table.
  @Test("The delivery's overlay check visits no refused write: 400 of them cost what 7 do")
  func overlayCheckDoesNotGrowWithRefusedWrites() async throws {
    let few = RealSizeShape.phone.scaled(0.01)
    var many = few
    many.refusedWrites = 400
    let fewSteps = try await Self.overlayCheckSteps(few, label: "overlay-few")
    let manySteps = try await Self.overlayCheckSteps(many, label: "overlay-many")
    #expect(
      manySteps <= fewSteps + 50,
      "The overlay check took \(manySteps) steps beside 400 refused writes against \(fewSteps) beside 7."
    )
  }

  // The supersession tail read, before every eligible write (a live line about once a second while speaking), chose the
  // newest row with its body size: a scan of the table, each row read through its body, and a sort.
  @Test("The supersession tail read scans no outbox row: it finds the newest id in an index, then reads that one row")
  func tailReadScansNoOutboxRow() async throws {
    let session = try await RealSizeFixture.open(RealSizeShape.phone.scaled(0.01), label: "tail-plan")
    let plan = try await session.closing {
      try Self.queryPlan(SQLitePersistenceStore.immediateSupersessionTailSQL, in: session.configuration.persistenceURL)
    }
    let tableScans = plan.filter { $0.hasPrefix("SCAN instant_outbox") && !$0.contains("COVERING INDEX") }
    expectNoDifference(tableScans, [], "plan: \(plan)")
  }

  private static func overlayCheckSteps(_ shape: RealSizeShape, label: String) async throws -> Int {
    let session = try await RealSizeFixture.open(shape, label: label)
    return try await session.closing {
      try await RealSizeGenerator.waitForSettledOutbox(session.runtime)
      return try await session.runtime.persistence.unknownActiveOverlayCheckStepsForTesting()
    }
  }

  /// SQLite's plan of `sql` on the store at `url`, one detail line each, through a read-only connection of its own.
  private static func queryPlan(_ sql: String, in url: URL) throws -> [String] {
    var database: OpaquePointer?
    defer { sqlite3_close(database) }
    try #require(sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK)
    var statement: OpaquePointer?
    defer { sqlite3_finalize(statement) }
    try #require(sqlite3_prepare_v2(database, "EXPLAIN QUERY PLAN \(sql)", -1, &statement, nil) == SQLITE_OK)
    var details: [String] = []
    while sqlite3_step(statement) == SQLITE_ROW {
      if let detail = sqlite3_column_text(statement, 3) { details.append(String(cString: detail)) }
    }
    return details
  }

  /// The claim reads' steps on a generated store of `shape`, once its writes settled: no write left to deliver, the
  /// refused ones kept.
  private static func claimReadSteps(_ shape: RealSizeShape, label: String) async throws -> (candidates: Int, check: Int) {
    let session = try await RealSizeFixture.open(shape, label: label)
    return try await session.closing {
      try await RealSizeGenerator.waitForSettledOutbox(session.runtime)
      let refused = await session.runtime.failedMutations(limit: 1_000).count
      #expect(refused == shape.refusedWrites)
      return try await session.runtime.persistence.automaticDeliveryCandidateReadStepsForTesting()
    }
  }
}
