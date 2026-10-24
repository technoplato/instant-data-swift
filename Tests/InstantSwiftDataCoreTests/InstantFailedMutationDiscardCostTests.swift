import CustomDump
import Foundation
import Testing

@testable import InstantSwiftDataCore

// #1103 (2026-10-24): a discard of a refused write whose rollback already ran (its receipt says it left no materialized
// effect) loaded and decoded the whole durable outbox, copied every resident fact, diffed both copies into SQLite,
// bumped the store's revisions and dropped the cached state, so the next read rebuilt the store from SQLite. On #1072's
// phone-shaped store (fixture version 3) that held the operation gate 112 ms on the store as launched and 1.7 s once
// the whole `$files` list had loaded, and the consuming app's recovery discards up to 32 at a time.
//
// History:
// - 2026-10-24: #1103: the cost test.

@Suite(.serialized)
struct InstantFailedMutationDiscardCostTests {
  @Test("Discarding a refused write that left no effect reads no other outbox row and keeps the cached store")
  func discardOfARefusalWithoutEffectIsRowAddressed() async throws {
    let session = try await RealSizeFixture.open(RealSizeShape.phone.scaled(0.01), label: "discard-cost")
    try await session.closing {
      let runtime = session.runtime
      try await RealSizeGenerator.waitForSettledOutbox(runtime)
      let failed = await runtime.failedMutations(limit: 100)
      let target = try #require(
        failed.first { mutation in
          if case .noCurrentMaterializedEffect = mutation.optimisticEffectReceipt { return true }
          return false
        }
      )
      let wideReadsBefore = await runtime.persistence.localMutationQueueWideReadCountForTesting()
      await runtime.persistence.resetCacheResidencyMetricsForTesting()

      _ = try await runtime.discardFailedMutation(id: target.id)
      // The next write reads its state from the cache the discard kept.
      try await runtime.transact(
        session.segmentWrite(
          recordingID: RealSizeID.make(.recording, 0), line: 50_000, revision: 0, id: RealSizeID.make(.write, 900_000)
        )
      )

      let wideReads = await runtime.persistence.localMutationQueueWideReadCountForTesting() - wideReadsBefore
      let residency = await runtime.persistence.cacheResidencyMetricsForTesting()
      expectNoDifference(wideReads, 0)
      expectNoDifference(residency.fullStoreSnapshotLoadCount, 0)
      expectNoDifference(residency.fullStateReconstructionCount, 0)
      let remaining = await runtime.failedMutations(limit: 100).map(\.id)
      expectNoDifference(remaining, failed.map(\.id).filter { $0 != target.id })
    }
  }
}
