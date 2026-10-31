// History:
// - 2026-10-31: added (#1491): the outbox's newest row in delivery order, which every local write and every server
//   apply's plan reads, is one entry of an index in that order, not a sort of every row.

import CustomDump
import Foundation
import Testing

@testable import InstantSwiftDataCore

/// The outbox's tail: its newest row in delivery order, `created_at_ms` then `mutation_id` (#1491).
///
/// Every local write reads it inside the operation gate (the creation cursor it must follow, and for a same-entity write
/// the tail it may replace), and a server apply's plan reads it as it begins and as it takes in later writes. No index
/// held every row in that order, so SQLite scanned the whole global-effect index and kept the newest row in a temporary
/// b-tree: on the outbox's schema with the phone-shaped store's 663 refused writes, 291 us a read against 29 us from an
/// index (laptop), and 2.25 ms with an hour of lines written offline, 5,400 rows.
@Suite
struct InstantOutboxTailReadTests {
  /// Each read of the tail, as the library runs it, reads one entry of the creation-order index and sorts nothing.
  @Test
  func theOutboxTailIsOneEntryOfAnIndexInDeliveryOrder() async throws {
    let store = try await RareStateIndexes.store("outbox-tail-plans")
    for sql in [
      SQLitePersistenceStore.outboxTailPositionSQL,
      SQLitePersistenceStore.outboxTailIDSQL,
      SQLitePersistenceStore.immediateSupersessionTailSQL,
    ] {
      let plan = try RareStateIndexes.plan(store, sql)
      #expect(!plan.contains { $0.contains("TEMP B-TREE") }, "the outbox sorted for its tail: \(plan) for \(sql)")
      #expect(
        plan.contains { $0.contains("INDEX instant_outbox_creation_order_idx") },
        "the creation-order index not in \(plan) for \(sql)"
      )
    }
  }
}
