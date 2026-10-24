import Foundation
import Testing

@testable import InstantSwiftDataCore

// #1072 (2026-10-24): budgets at the phone's size that fail the build when an operation's cost grows with the store
// again. Every case so far (#654, #932, #1035, #1006, #653, the stored-file reloads of #1072) was found one at a time
// from a phone's measurements; these hold the class in CI the way an allocation-counting benchmark does.
//
// Each operation runs on the generated store at a quarter of the phone's size and at its full size (the report's own
// operations, `RealSizeOperations`). Two kinds of budget:
//
// - Scale: the same change on a store four times larger costs about the same. The ratio of heap allocations and of
//   instructions retired, full size over quarter size, stays under `RealSizeBudget.scaleLimit` (1.5; a cost that grows
//   with the store reads about 4). Both counts barely move with the machine's load, so this check fails on a
//   regression, not on a busy host. An operation too small to count reliably (under 2,000 allocations, or 20 million
//   instructions, at a quarter of the size) is held by its ceiling alone: background work dominates its ratio.
// - Ceiling: at full size, allocations stay under a ceiling about twice what they measured, and the median wall time
//   under a generous one (ten times what it measured on an idle Mac mini, at least 20 ms), which only an
//   order-of-magnitude regression crosses.
//
// The operations whose cost still grows with the store carry a known issue, each with its own filed issue: the budget
// is the one they must meet, so a fix shows up as the known issue no longer happening, and the budget tightens.
//
// The ceilings are calibrated for optimized builds, as the correctness job runs (`swift test -c release`): a debug
// build allocates more for the same work, so the suite runs only in release unless `INSTANT_REAL_SIZE_BUDGETS=1`
// forces it; `INSTANT_REAL_SIZE_BUDGETS=0` turns it off. Its allocation counts are process-wide, so it runs
// serialized, as the whole correctness job does (`--no-parallel`).
//
// History:
// - 2026-10-24: #1072: the budgets.

/// When the budgets run: in optimized builds, unless the environment says otherwise.
enum RealSizeBudget {
  static var isEnabled: Bool {
    switch ProcessInfo.processInfo.environment["INSTANT_REAL_SIZE_BUDGETS"] {
    case "1": return true
    case "0": return false
    default: return isOptimized
    }
  }

  #if DEBUG
    static let isOptimized = false
  #else
    static let isOptimized = true
  #endif

  /// How much more an operation may allocate, or retire in instructions, on a store four times larger.
  static let scaleLimit = 1.5
  /// Below these counts at a quarter of the size, a ratio is mostly other work's noise.
  static let scaleFloorAllocations = 2_000
  static let scaleFloorInstructions: UInt64 = 20_000_000

  /// The full-size budgets of one operation.
  struct Ceiling: Sendable {
    /// The most heap allocations one call may make.
    var allocations: Int
    /// The longest median wall time.
    var wall: Duration
  }

  /// One operation's budgets: the scale check, and its full-size ceiling.
  struct Rule: Sendable {
    var operation: String
    var ceiling: Ceiling
    /// The issue that tracks a known excess, when the operation does not meet its budget yet.
    var knownIssue: String?
    /// Whether the excess shows only on some runs (a ratio near its limit): the known issue may not occur.
    var knownIssueIsIntermittent = false
  }
}

@Suite(.serialized, .enabled(if: RealSizeBudget.isEnabled, "Real-size budgets run in optimized builds"))
struct RealSizeBudgetTests {
  /// The groups the budgets meter: the report's, without the ones that hold no budget yet.
  static let groups: Set<String> = [
    "transact", "server-apply", "prune", "query", "observe", "files", "outbox", "status", "refused-write",
  ]

  /// Operations the budgets leave to the report: the ones that take seconds by design (a whole list, each with its own
  /// issue: #1105, #1106) and the ones whose answer differs between the two sizes.
  static let skipped: Set<String> = [
    "cachedQueries", "pendingMutations", "failedMutations",
    "queryOnce.transcript-page", "queryLocally.transcript-page", "observe.first-emission", "localStoredFiles",
    "downloadStoredFile.by-id-without-record", "failedMutations(limit:500)", "pendingMutations(limit:50)",
    "quarantinedMutationCount", "syncState", "compactLocalCache", "prune",
  ]

  // Ceilings: about twice the allocations and ten times the median wall time measured at the phone's size on a Mac mini
  // (M4, release, 2026-10-24, fixture version 3), the wall at least 20 ms. The known issues are the budgets the
  // operations must meet once fixed.
  static let rules: [RealSizeBudget.Rule] = [
    // Writes and what they start (the outbox pump), the server's refresh of a live page, a prune of one closed page.
    // Its instructions read 1.38-1.51x at the phone's size, the pump's claim after each write and the 2,283-attribute map
    // of its supersession check, both #1108: once fixed, its ratio is about 1.
    .init(
      operation: "transact", ceiling: .init(allocations: 20_000, wall: .milliseconds(20)),
      knownIssue: "#1108: a write's supersession check maps every attribute, and the pump's claim after it reads every refused write",
      knownIssueIsIntermittent: true
    ),
    .init(
      operation: "refused-write", ceiling: .init(allocations: 32_000, wall: .milliseconds(150)),
      knownIssue: "#1108: the outbox pump's claim reads every refused write's row after each write",
      knownIssueIsIntermittent: true
    ),
    .init(operation: "server-apply.refresh-128", ceiling: .init(allocations: 42_000, wall: .milliseconds(200))),
    .init(operation: "prune.one-closed-page", ceiling: .init(allocations: 100_000, wall: .milliseconds(300))),
    // Queries and observations of one bounded page.
    .init(operation: "queryOnce.first-32", ceiling: .init(allocations: 90_000, wall: .milliseconds(200))),
    .init(
      operation: "queryLocally.first-32", ceiling: .init(allocations: 12_000, wall: .milliseconds(60)),
      knownIssue: "#1111: a local read builds an attribute store of the whole schema and validates against it"
    ),
    .init(
      operation: "observe.first-emission-32", ceiling: .init(allocations: 100_000, wall: .milliseconds(120)),
      knownIssue: "#1111: an observation builds an attribute store of the whole schema and validates against it"
    ),
    .init(operation: "observe.emission-after-write", ceiling: .init(allocations: 120_000, wall: .milliseconds(200))),
    // The file calls the consuming app makes while recording and at launch.
    // Their ceilings sit well above the few hundred allocations they make: background work (a pump pass) can land in a
    // count this small, and the regression they guard against cost 107,142.
    .init(operation: "uploadFile", ceiling: .init(allocations: 5_000, wall: .milliseconds(20))),
    .init(operation: "deleteStoredFile.uploaded", ceiling: .init(allocations: 5_000, wall: .milliseconds(20))),
    .init(operation: "downloadStoredFile.by-id-with-record", ceiling: .init(allocations: 5_000, wall: .milliseconds(20))),
    .init(
      operation: "evictStoredFiles.200", ceiling: .init(allocations: 5_000, wall: .milliseconds(20)),
      knownIssue: "#1104: eviction reads every file record to find its ids"
    ),
    .init(
      operation: "storageSnapshot", ceiling: .init(allocations: 1_000, wall: .milliseconds(20)),
      knownIssue: "#1104: the storage snapshot decodes every file record to count the held copies"
    ),
    // The outbox reads the consuming app makes on every refusal and at launch.
    .init(operation: "pendingMutationCount", ceiling: .init(allocations: 5_000, wall: .milliseconds(20))),
    .init(operation: "failedMutations(limit:50)", ceiling: .init(allocations: 60_000, wall: .milliseconds(50))),
    .init(
      operation: "failedMutationSupersessions", ceiling: .init(allocations: 50_000, wall: .milliseconds(50)),
      knownIssue: "#1106: the supersessions of the failed writes read every later write of each slot"
    ),
    .init(
      operation: "discardFailedMutation", ceiling: .init(allocations: 50_000, wall: .milliseconds(50)),
      knownIssue: "#1103: a discard copies, diffs and reloads the whole store under the operation gate"
    ),
    .init(operation: "connectionStatus", ceiling: .init(allocations: 5_000, wall: .milliseconds(20))),
  ]

  @Test("No operation costs more on a store four times larger, and each stays under its ceiling at the phone's size")
  func budgetsAtTheRealSize() async throws {
    var measured: [String: [String: RealSizeMeasurement]] = [:]
    for (label, shape) in [("quarter", RealSizeShape.phone.scaled(0.25)), ("phone", RealSizeShape.phone)] {
      let session = try await RealSizeFixture.open(shape, label: "budget-\(label)")
      var byOperation: [String: RealSizeMeasurement] = [:]
      try await session.closing {
        try await RealSizeOperations.operations(
          on: session, label: label, wanted: { Self.groups.contains($0) }, skipping: Self.skipped,
          emit: { measurement in
            print(measurement.line)
            byOperation[measurement.operation] = measurement
          }
        )
      }
      measured[label] = byOperation
    }

    for rule in Self.rules {
      let quarter = measured["quarter"]?[rule.operation]
      let phone = measured["phone"]?[rule.operation]
      guard let quarter, let phone else {
        Issue.record("\(rule.operation) was not measured at both sizes: its step failed (see its REALSIZE line).")
        continue
      }
      let check = {
        Self.expectScale(rule.operation, quarter: quarter, phone: phone)
        Self.expectCeiling(rule, phone: phone)
      }
      if let knownIssue = rule.knownIssue {
        withKnownIssue(Comment(rawValue: knownIssue), isIntermittent: rule.knownIssueIsIntermittent) { check() }
      } else {
        check()
      }
    }
  }

  private static func expectScale(_ operation: String, quarter: RealSizeMeasurement, phone: RealSizeMeasurement) {
    let allocations = Double(phone.allocations) / Double(max(1, quarter.allocations))
    let instructions = Double(phone.instructions) / Double(max(1, quarter.instructions))
    #expect(
      quarter.allocations < RealSizeBudget.scaleFloorAllocations || allocations <= RealSizeBudget.scaleLimit,
      """
      \(operation) allocated \(phone.allocations) times on the phone-sized store against \(quarter.allocations) on \
      one a quarter of its size: its cost grows with the store, not with the change.
      """
    )
    #expect(
      quarter.instructions < RealSizeBudget.scaleFloorInstructions || instructions <= RealSizeBudget.scaleLimit,
      """
      \(operation) retired \(phone.instructions) instructions on the phone-sized store against \
      \(quarter.instructions) on one a quarter of its size: its cost grows with the store, not with the change.
      """
    )
  }

  private static func expectCeiling(_ rule: RealSizeBudget.Rule, phone: RealSizeMeasurement) {
    #expect(
      phone.allocations <= rule.ceiling.allocations,
      "\(rule.operation) allocated \(phone.allocations) times at the phone's size; its budget is \(rule.ceiling.allocations)."
    )
    #expect(
      phone.medianWall <= rule.ceiling.wall,
      "\(rule.operation) took \(phone.medianWall) (median) at the phone's size; its budget is \(rule.ceiling.wall)."
    )
  }
}
