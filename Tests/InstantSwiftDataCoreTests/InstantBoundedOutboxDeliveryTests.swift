import CustomDump
import Foundation
import SQLite3
import Testing

@testable import InstantSwiftDataCore

/// Upstream delivery authority:
/// `/Users/laptop/Sync/instant-data-swift/upstream/instant/client/packages/core/src/Reactor.js`
/// at upstream commit `e71017612aed4031710a35e2fcace30d38d557ac`.
///
/// Reactor keeps pending mutations in a resident map and `_flushPendingMessages`
/// visits that map in mutation order. Swift adapts the same ordering and
/// acknowledgement rules to a durable SQLite queue, so automatic delivery must
/// first admit a fixed row window instead of rebuilding the complete map.
@Suite(.serialized)
struct InstantBoundedOutboxDeliveryTests {
  @Test
  func explicitClaimThrowsSynchronizationBlockerBeforeUnknownHeadDecodeOrSuccessorClaim()
    async throws
  {
    let cacheURL = try temporaryBoundedOutboxCacheURL()
    let timestamp = InstantTimestamp(milliseconds: 1)
    let unknown = PendingMutation(
      id: "tx-explicit-unknown-head-00000",
      createdAt: timestamp,
      transaction: InstantStoreTransaction(
        id: "tx-explicit-unknown-head-00000",
        operations: [
          .insert(
            InstantTriple(
              entityID: "todo-explicit-unknown-head",
              attributeID: "todos/text",
              value: .string("Must be quarantined before explicit delivery"),
              txID: "tx-explicit-unknown-head-00000",
              txTime: timestamp
            )
          )
        ]
      )
    )
    let successor = boundedMutation(index: 1, prefix: "explicit-unknown-head")
    let persistence = try SQLitePersistenceStore(fileURL: cacheURL)
    try await persistence.bootstrap()
    try await persistence.saveOutbox([unknown])
    let publicSeed = try await persistence.loadCompactState()
    let didSeedPreparedSuccessor = try await persistence.saveOutbox(
      [unknown, successor],
      replacing: [unknown],
      metadataEntries: [],
      expectedStoreRevision: publicSeed.storeRevision,
      expectedOutboxRevision: publicSeed.outboxRevision
    )
    expectNoDifference(didSeedPreparedSuccessor, true)
    let rawUnknownBeforeClaimValue = try boundedOutboxRawBody(
      id: unknown.id,
      cacheURL: cacheURL
    )
    let rawUnknownBeforeClaim = try #require(rawUnknownBeforeClaimValue)
    await persistence.resetDecodedOutboxBodyCount()

    do {
      _ = try await persistence.claimExplicitOutboxDeliveryWindow(
        limit: 1,
        claimantID: "explicit-unknown-head-runtime",
        claimToken: "explicit-unknown-head-token",
        now: InstantTimestamp(milliseconds: 10_000)
      )
      Issue.record("An explicit claim must stop at the durable synchronization blocker.")
    } catch let error as InstantError {
      expectNoDifference(error.code, .persistenceFailed)
      expectNoDifference(error.operation, "claim explicit outbox flush")
      expectNoDifference(error.localID, unknown.id)
      expectNoDifference(error.localMutationDisposition, .retainedUnknown)
      #expect(error.message.contains("Synchronization is blocked by 1 retained mutation."))
    }

    let blockerValue = try await persistence.synchronizationBlocker()
    let blocker = try #require(blockerValue)
    expectNoDifference(blocker.reason, .unknownOptimisticEffectReceipt)
    expectNoDifference(blocker.firstMutationID, unknown.id)
    expectNoDifference(blocker.blockedMutationCount, 1)
    let decodedBodyCount = await persistence.currentDecodedOutboxBodyCount()
    expectNoDifference(decodedBodyCount, 0)
    let rawUnknownAfterClaimValue = try boundedOutboxRawBody(
      id: unknown.id,
      cacheURL: cacheURL
    )
    let rawUnknownAfterClaim = try #require(rawUnknownAfterClaimValue)
    expectNoDifference(rawUnknownAfterClaim, rawUnknownBeforeClaim)
    let quarantinedJSON = try await persistence.quarantinedOutboxBodyForTesting(
      id: unknown.id
    )
    expectNoDifference(quarantinedJSON, nil)
    let outboxRevision = try await persistence.currentOutboxRevision()
    let retainedRowsValue = try await persistence.loadOutboxMutations(
      statuses: [.pending],
      ids: [unknown.id, successor.id],
      limit: 2,
      expectedOutboxRevision: outboxRevision
    )
    let retainedRows = try #require(retainedRowsValue)
    let retainedUnknown = try #require(
      retainedRows.first { $0.id == unknown.id }
    )
    let retainedSuccessor = try #require(
      retainedRows.first { $0.id == successor.id }
    )
    expectNoDifference(retainedUnknown.status, .pending)
    expectNoDifference(retainedSuccessor.status, .pending)
    let unknownClaimValue = try await persistence.outboxDeliveryClaimForTesting(id: unknown.id)
    let unknownClaim = try #require(unknownClaimValue)
    expectNoDifference(unknownClaim.state, .ready)
    expectNoDifference(unknownClaim.claimToken, nil)
    expectNoDifference(unknownClaim.deliveryStarted, false)
    let successorClaimValue = try await persistence.outboxDeliveryClaimForTesting(
      id: successor.id
    )
    let successorClaim = try #require(successorClaimValue)
    expectNoDifference(successorClaim.state, .ready)
    expectNoDifference(successorClaim.claimToken, nil)
    expectNoDifference(successorClaim.deliveryStarted, false)
    let unknownReceipt = try await persistence.optimisticEffectReceiptFingerprintForTesting(
      id: unknown.id
    )
    let successorReceipt = try await persistence.optimisticEffectReceiptFingerprintForTesting(
      id: successor.id
    )
    expectNoDifference(unknownReceipt, nil)
    #expect(successorReceipt != nil)
  }

  @Test
  func synchronizationBlockerUsesCoveringIndexAndRepairsReconstructedTable() async throws {
    let cacheURL = try temporaryBoundedOutboxCacheURL()
    try await seedBoundedOutbox(
      (0..<1_000).map { boundedMutation(index: $0, prefix: "blocker-index") },
      cacheURL: cacheURL
    )
    try executeBoundedOutboxSQL(
      """
      UPDATE instant_outbox
      SET optimistic_effect_receipt_fingerprint = NULL
      WHERE mutation_id IN (
        'tx-blocker-index-00307',
        'tx-blocker-index-00411',
        'tx-blocker-index-00449'
      );
      UPDATE instant_outbox
      SET optimistic_overlay_active = 0,
          optimistic_effect_receipt_fingerprint = NULL
      WHERE mutation_id IN (
        'tx-blocker-index-00005',
        'tx-blocker-index-00007'
      );
      """,
      cacheURL: cacheURL
    )

    let persistence = try SQLitePersistenceStore(fileURL: cacheURL)
    try await persistence.bootstrap()
    let blockerValue = try await persistence.synchronizationBlocker()
    let blocker = try #require(blockerValue)
    expectNoDifference(blocker.reason, .unknownOptimisticEffectReceipt)
    expectNoDifference(blocker.firstMutationID, "tx-blocker-index-00307")
    expectNoDifference(blocker.blockedMutationCount, 3)

    let firstBlockedPlan = try boundedOutboxQueryPlan(
      """
      SELECT mutation_id
      FROM instant_outbox INDEXED BY instant_outbox_synchronization_blocker_idx
      WHERE optimistic_overlay_active = 1
        AND optimistic_effect_receipt_fingerprint IS NULL
      ORDER BY created_at_ms, mutation_id
      LIMIT 1
      """,
      cacheURL: cacheURL
    )
    let blockedCountPlan = try boundedOutboxQueryPlan(
      """
      SELECT COUNT(*)
      FROM instant_outbox INDEXED BY instant_outbox_synchronization_blocker_idx
      WHERE optimistic_overlay_active = 1
        AND optimistic_effect_receipt_fingerprint IS NULL
      """,
      cacheURL: cacheURL
    )
    #expect(
      firstBlockedPlan.contains {
        $0.contains("USING COVERING INDEX instant_outbox_synchronization_blocker_idx")
      }
    )
    #expect(!firstBlockedPlan.contains { $0.contains("USE TEMP B-TREE FOR ORDER BY") })
    #expect(
      blockedCountPlan.contains {
        $0.contains("USING COVERING INDEX instant_outbox_synchronization_blocker_idx")
      }
    )

    await persistence.simulateUnexpectedConnectionCloseForTesting()
    expectNoDifference(
      try boundedOutboxMigrationLedgerCount(
        name: "0022_outbox_synchronization_blocker_index",
        cacheURL: cacheURL
      ),
      1
    )
    try restorePreBoundedDeliveryOutboxSchema(cacheURL: cacheURL)
    expectNoDifference(
      try boundedOutboxMigrationLedgerCount(
        name: "0022_outbox_synchronization_blocker_index",
        cacheURL: cacheURL
      ),
      1,
      "The reconstructed table retains migration 0022 while dropping its index."
    )

    let reconstructed = try SQLitePersistenceStore(fileURL: cacheURL)
    try await reconstructed.bootstrap()
    let repairedPlan = try boundedOutboxQueryPlan(
      """
      SELECT mutation_id
      FROM instant_outbox INDEXED BY instant_outbox_synchronization_blocker_idx
      WHERE optimistic_overlay_active = 1
        AND optimistic_effect_receipt_fingerprint IS NULL
      ORDER BY created_at_ms, mutation_id
      LIMIT 1
      """,
      cacheURL: cacheURL
    )
    #expect(
      repairedPlan.contains {
        $0.contains("USING COVERING INDEX instant_outbox_synchronization_blocker_idx")
      }
    )
    #expect(!repairedPlan.contains { $0.contains("USE TEMP B-TREE FOR ORDER BY") })
    expectNoDifference(
      try boundedOutboxMigrationLedgerCount(
        name: "0022_outbox_synchronization_blocker_index",
        cacheURL: cacheURL
      ),
      1
    )
  }

  @Test
  func automaticClaimExcludesForeignRuntimeSuccessorUntilHeadIsAccepted()
    async throws
  {
    let cacheURL = try temporaryBoundedOutboxCacheURL()
    let firstMutation = boundedMutation(
      index: 0,
      prefix: "atomic-claim",
      entityID: "shared-claim-entity"
    )
    try await seedBoundedOutbox(
      [firstMutation],
      cacheURL: cacheURL
    )
    let firstStore = try SQLitePersistenceStore(fileURL: cacheURL)
    let secondStore = try SQLitePersistenceStore(fileURL: cacheURL)
    try await firstStore.bootstrap()
    try await secondStore.bootstrap()

    let first = try await firstStore.claimAutomaticOutboxDeliveryWindow(
      InstantAutomaticOutboxClaimRequest(
        claimantID: "runtime-a",
        claimToken: "claim-a",
        now: InstantTimestamp(milliseconds: 10_000),
        maximumMutationCount: 1
      )
    )
    let successor = boundedMutation(
      index: 1,
      prefix: "atomic-claim",
      entityID: "shared-claim-entity"
    )
    _ = try await appendRuntimePreparedBoundedOutbox([successor], to: secondStore)
    let second = try await secondStore.claimAutomaticOutboxDeliveryWindow(
      InstantAutomaticOutboxClaimRequest(
        claimantID: "runtime-b",
        claimToken: "claim-b",
        now: InstantTimestamp(milliseconds: 10_000),
        maximumMutationCount: 50
      )
    )

    expectNoDifference(first.mutations.map(\.id), ["tx-atomic-claim-00000"])
    expectNoDifference(
      second.mutations.map(\.id),
      [],
      "A foreign claimant owns the whole ordered lane, even when global count/step/byte capacity remains."
    )
    #expect(Set(first.mutations.map(\.id)).isDisjoint(with: second.mutations.map(\.id)))
    let firstClaim = try await firstStore.outboxDeliveryClaimForTesting(
      id: "tx-atomic-claim-00000"
    )
    expectNoDifference(firstClaim?.state, .claimed)
    expectNoDifference(firstClaim?.claimToken, "claim-a")
    expectNoDifference(firstClaim?.claimantID, "runtime-a")
    expectNoDifference(firstClaim?.deadlineMilliseconds, 16_000)
    expectNoDifference(firstClaim?.deliveryStarted, true)

    let revision = try await firstStore.currentOutboxRevision()
    let acceptedHead = try await firstStore.acceptOutboxMutation(
      id: "tx-atomic-claim-00000",
      serverTransactionID: "server-atomic-head",
      claimantID: "runtime-a",
      claimToken: "claim-a",
      expectedOutboxRevision: revision
    )
    _ = try #require(acceptedHead)
    let acceptedHeadClaim = try #require(
      try await firstStore.outboxDeliveryClaimForTesting(id: "tx-atomic-claim-00000")
    )
    expectNoDifference(acceptedHeadClaim.state, .ready)
    expectNoDifference(acceptedHeadClaim.projectedBodyByteCount, nil)
    let successorClaim = try await secondStore.claimAutomaticOutboxDeliveryWindow(
      InstantAutomaticOutboxClaimRequest(
        claimantID: "runtime-b",
        claimToken: "claim-b-after-head",
        now: InstantTimestamp(milliseconds: 10_001)
      )
    )
    expectNoDifference(successorClaim.mutations.map(\.id), ["tx-atomic-claim-00001"])
    try await secondStore.releaseAutomaticOutboxClaim(token: "claim-b-after-head")
    let releasedSuccessor = try await secondStore.outboxDeliveryClaimForTesting(
      id: "tx-atomic-claim-00001"
    )
    expectNoDifference(releasedSuccessor?.state, .ready)
    expectNoDifference(releasedSuccessor?.claimToken, nil)
    expectNoDifference(releasedSuccessor?.projectedBodyByteCount, nil)
    expectNoDifference(
      releasedSuccessor?.deliveryStarted,
      true,
      "Release makes a row retryable but never erases proof that it was offered to delivery."
    )
    await firstStore.simulateUnexpectedConnectionCloseForTesting()
    await secondStore.simulateUnexpectedConnectionCloseForTesting()
  }

  @Test
  func offeredMutationRejectsRuntimePreparedChangedWireAndPreservesOriginalClaim() async throws {
    let cacheURL = try temporaryBoundedOutboxCacheURL()
    let persistence = try SQLitePersistenceStore(fileURL: cacheURL)
    try await persistence.bootstrap()
    let original = try #require(
      try await appendRuntimePreparedBoundedOutbox(
        [
          boundedMutation(
            index: 0,
            prefix: "stale-ack-payload-a",
            entityID: "stale-ack-entity-a"
          )
        ],
        to: persistence
      ).first
    )
    let claimA = try await persistence.claimAutomaticOutboxDeliveryWindow(
      InstantAutomaticOutboxClaimRequest(
        claimantID: "stale-ack-runtime",
        claimToken: "stale-ack-token-a",
        now: InstantTimestamp(milliseconds: 10_000),
        maximumMutationCount: 1
      )
    )
    expectNoDifference(claimA.mutations.map(\.id), [original.id])
    let optionalRawBodyBeforeRewrite = try boundedOutboxRawBody(
      id: original.id,
      cacheURL: cacheURL
    )
    let rawBodyBeforeRewrite = try #require(optionalRawBodyBeforeRewrite)
    let wireFingerprintBeforeRewrite = try original.mutationWireIntentFingerprint()
    let claimBeforeRewrite = try #require(
      try await persistence.outboxDeliveryClaimForTesting(id: original.id)
    )
    let mutationRevisionBeforeRewrite = try await persistence
      .outboxMutationRevisionForTesting(id: original.id)
    let persistenceStateBeforeRewrite = try await persistence.loadCompactState()

    var changedWire = original
    changedWire.transaction = boundedMutation(
      index: 1,
      prefix: "stale-ack-payload-b",
      entityID: "stale-ack-entity-b"
    ).transaction
    changedWire.transaction.id = original.id
    do {
      _ = try await replaceRuntimePreparedBoundedOutboxMutation(
        changedWire,
        replacing: original,
        in: persistence
      )
      Issue.record("Expected an offered mutation's forward wire intent to be immutable.")
    } catch let error as InstantError {
      expectNoDifference(error.code, .persistenceFailed)
      expectNoDifference(error.operation, "persist offered outbox mutation")
      #expect(error.message.contains(original.id))
    }

    let optionalRawBodyAfterRewrite = try boundedOutboxRawBody(
      id: original.id,
      cacheURL: cacheURL
    )
    let rawBodyAfterRewrite = try #require(optionalRawBodyAfterRewrite)
    let persistenceStateAfterRewrite = try await persistence.loadCompactState()
    let mutationRevisionAfterRewrite = try await persistence
      .outboxMutationRevisionForTesting(id: original.id)
    let claimAfterRewrite = try #require(
      try await persistence.outboxDeliveryClaimForTesting(id: original.id)
    )
    expectNoDifference(rawBodyAfterRewrite, rawBodyBeforeRewrite)
    expectNoDifference(
      try JSONDecoder().decode(PendingMutation.self, from: Data(rawBodyAfterRewrite.utf8))
        .mutationWireIntentFingerprint(),
      wireFingerprintBeforeRewrite
    )
    expectNoDifference(claimAfterRewrite, claimBeforeRewrite)
    expectNoDifference(mutationRevisionAfterRewrite, mutationRevisionBeforeRewrite)
    expectNoDifference(
      persistenceStateAfterRewrite.storeRevision,
      persistenceStateBeforeRewrite.storeRevision
    )
    expectNoDifference(
      persistenceStateAfterRewrite.outboxRevision,
      persistenceStateBeforeRewrite.outboxRevision
    )
    expectNoDifference(
      persistenceStateAfterRewrite.attributeRevision,
      persistenceStateBeforeRewrite.attributeRevision
    )
    expectNoDifference(
      persistenceStateAfterRewrite.queryResultRevision,
      persistenceStateBeforeRewrite.queryResultRevision
    )

    let revision = persistenceStateAfterRewrite.outboxRevision
    let current = try #require(
      try await persistence.loadOutboxMutations(
        statuses: [.pending, .confirmed, .failed],
        ids: [original.id],
        limit: 1,
        expectedOutboxRevision: revision
      )?.first
    )
    expectNoDifference(current.transaction, original.transaction)
    expectNoDifference(claimAfterRewrite.state, .claimed)
    expectNoDifference(claimAfterRewrite.claimToken, "stale-ack-token-a")
    expectNoDifference(claimAfterRewrite.claimantID, "stale-ack-runtime")

    let accepted = try await persistence.acceptOutboxMutation(
      id: original.id,
      serverTransactionID: "server-original-offer",
      claimantID: "stale-ack-runtime",
      claimToken: "stale-ack-token-a",
      expectedOutboxRevision: revision
    )
    expectNoDifference(accepted?.didChange, true)
    expectNoDifference(accepted?.mutation?.transaction, original.transaction)
    expectNoDifference(accepted?.mutation?.status, .confirmed)
    expectNoDifference(accepted?.mutation?.serverTransactionID, "server-original-offer")
  }

  @Test
  func acceptedMutationRejectsPublicAndRuntimePreparedChangedWireRewrites() async throws {
    let cacheURL = try temporaryBoundedOutboxCacheURL()
    let persistence = try SQLitePersistenceStore(fileURL: cacheURL)
    try await persistence.bootstrap()
    let original = try #require(
      try await appendRuntimePreparedBoundedOutbox(
        [
          boundedMutation(
            index: 0,
            prefix: "accepted-rewrite-original",
            entityID: "accepted-rewrite-original-entity"
          )
        ],
        to: persistence
      ).first
    )
    let claim = try await persistence.claimAutomaticOutboxDeliveryWindow(
      InstantAutomaticOutboxClaimRequest(
        claimantID: "accepted-rewrite-runtime",
        claimToken: "accepted-rewrite-token",
        now: InstantTimestamp(milliseconds: 20_000),
        maximumMutationCount: 1
      )
    )
    expectNoDifference(claim.mutations.map(\.id), [original.id])
    let acceptanceRevision = try await persistence.currentOutboxRevision()
    let acceptance = try await persistence.acceptOutboxMutation(
      id: original.id,
      serverTransactionID: "server-accepted-rewrite-original",
      claimantID: "accepted-rewrite-runtime",
      claimToken: "accepted-rewrite-token",
      expectedOutboxRevision: acceptanceRevision
    )
    let accepted = try #require(acceptance?.mutation)
    expectNoDifference(accepted.status, .confirmed)
    let acceptanceFingerprint = try #require(
      try boundedOutboxServerAcceptanceFingerprint(id: original.id, cacheURL: cacheURL)
    )

    var publicChangedWire = accepted
    publicChangedWire.transaction = boundedMutation(
      index: 1,
      prefix: "accepted-rewrite-public",
      entityID: "accepted-rewrite-public-entity"
    ).transaction
    publicChangedWire.transaction.id = accepted.id
    #expect(
      try accepted.mutationWireIntentFingerprint()
        != publicChangedWire.mutationWireIntentFingerprint()
    )
    do {
      try await persistence.saveOutbox([publicChangedWire])
      Issue.record("Expected public persistence to reject a changed accepted payload.")
    } catch let error as InstantError {
      expectNoDifference(error.operation, "persist prepared outbox mutation")
    }
    try await requireAcceptedBoundedOutboxMutationUnchanged(
      accepted,
      acceptanceFingerprint: acceptanceFingerprint,
      cacheURL: cacheURL,
      persistence: persistence
    )

    var runtimeChangedWire = accepted
    runtimeChangedWire.transaction = boundedMutation(
      index: 2,
      prefix: "accepted-rewrite-runtime",
      entityID: "accepted-rewrite-runtime-entity"
    ).transaction
    runtimeChangedWire.transaction.id = accepted.id
    #expect(
      try accepted.mutationWireIntentFingerprint()
        != runtimeChangedWire.mutationWireIntentFingerprint()
    )
    do {
      _ = try await replaceRuntimePreparedBoundedOutboxMutation(
        runtimeChangedWire,
        replacing: accepted,
        in: persistence
      )
      Issue.record("Expected Runtime persistence to reject a changed accepted payload.")
    } catch let error as InstantError {
      expectNoDifference(error.operation, "persist accepted outbox mutation")
    }
    try await requireAcceptedBoundedOutboxMutationUnchanged(
      accepted,
      acceptanceFingerprint: acceptanceFingerprint,
      cacheURL: cacheURL,
      persistence: persistence
    )
  }

  @Test
  func preparedPendingMutationRejectsPublicChangedBodyWithoutLosingItsOwner() async throws {
    let cacheURL = try temporaryBoundedOutboxCacheURL()
    let persistence = try SQLitePersistenceStore(fileURL: cacheURL)
    try await persistence.bootstrap()
    let original = try #require(
      try await appendRuntimePreparedBoundedOutbox(
        [
          boundedMutation(
            index: 0,
            prefix: "prepared-public-rewrite",
            entityID: "prepared-public-rewrite-original"
          )
        ],
        to: persistence
      ).first
    )
    let originalFingerprint = try #require(
      try await persistence.optimisticEffectReceiptFingerprintForTesting(id: original.id)
    )
    let originalState = try await persistence.loadState()

    var changed = original
    changed.transaction = boundedMutation(
      index: 1,
      prefix: "prepared-public-rewrite",
      entityID: "prepared-public-rewrite-changed"
    ).transaction
    changed.transaction.id = original.id
    #expect(
      try changed.optimisticEffectReceiptFingerprint() != originalFingerprint,
      "The public body edit must invalidate the Runtime-prepared materialization receipt."
    )

    do {
      try await persistence.saveOutbox([changed])
      Issue.record("Expected public persistence to reject a changed prepared pending body.")
    } catch let error as InstantError {
      expectNoDifference(error.operation, "persist prepared outbox mutation")
    }

    let reloaded = try await persistence.loadState()
    let reloadedFingerprint = try await persistence
      .optimisticEffectReceiptFingerprintForTesting(id: original.id)
    expectNoDifference(reloaded.snapshot, originalState.snapshot)
    expectNoDifference(reloaded.outboxRevision, originalState.outboxRevision)
    expectNoDifference(reloadedFingerprint, originalFingerprint)
  }

  @Test
  func legacyClaimWithoutProjectedBytesBlocksRefillUntilReleased() async throws {
    let cacheURL = try temporaryBoundedOutboxCacheURL()
    let mutations = (0..<2).map {
      boundedMutation(index: $0, prefix: "legacy-projected-byte-claim")
    }
    try await seedBoundedOutbox(mutations, cacheURL: cacheURL)
    let store = try SQLitePersistenceStore(fileURL: cacheURL)
    try await store.bootstrap()

    let firstWindow = try await store.claimAutomaticOutboxDeliveryWindow(
      InstantAutomaticOutboxClaimRequest(
        claimantID: "legacy-projected-byte-runtime",
        claimToken: "legacy-projected-byte-token",
        now: InstantTimestamp(milliseconds: 10_000),
        maximumMutationCount: 1
      )
    )
    expectNoDifference(firstWindow.mutations.map(\.id), [mutations[0].id])
    try executeBoundedOutboxSQL(
      """
      UPDATE instant_outbox
      SET delivery_claim_projected_body_bytes = NULL
      WHERE mutation_id = '\(mutations[0].id)';
      """,
      cacheURL: cacheURL
    )

    let blockedWindow = try await store.claimAutomaticOutboxDeliveryWindow(
      InstantAutomaticOutboxClaimRequest(
        claimantID: "legacy-projected-byte-runtime",
        claimToken: "blocked-refill-token",
        now: InstantTimestamp(milliseconds: 10_001)
      )
    )
    expectNoDifference(blockedWindow.mutations.map(\.id), [])
    let blockedTail = try #require(
      try await store.outboxDeliveryClaimForTesting(id: mutations[1].id)
    )
    expectNoDifference(blockedTail.state, .ready)
    expectNoDifference(blockedTail.claimToken, nil)
    expectNoDifference(blockedTail.projectedBodyByteCount, nil)
    expectNoDifference(blockedTail.deliveryStarted, false)

    _ = try await store.releaseAutomaticOutboxClaim(token: "legacy-projected-byte-token")
    let releasedHead = try #require(
      try await store.outboxDeliveryClaimForTesting(id: mutations[0].id)
    )
    expectNoDifference(releasedHead.state, .ready)
    expectNoDifference(releasedHead.projectedBodyByteCount, nil)
    let didReclaimHead = try await store.claimOutboxMutationWithoutHydrationForTesting(
      id: mutations[0].id,
      claimantID: "legacy-projected-byte-runtime",
      claimToken: "legacy-projected-byte-ack-token",
      deadlineMilliseconds: 16_001
    )
    expectNoDifference(didReclaimHead, true)
    let revision = try await store.currentOutboxRevision()
    _ = try #require(
      try await store.acceptOutboxMutation(
        id: mutations[0].id,
        serverTransactionID: "server-legacy-projected-byte-head",
        claimantID: "legacy-projected-byte-runtime",
        claimToken: "legacy-projected-byte-ack-token",
        expectedOutboxRevision: revision
      )
    )
    let tailWindow = try await store.claimAutomaticOutboxDeliveryWindow(
      InstantAutomaticOutboxClaimRequest(
        claimantID: "legacy-projected-byte-runtime",
        claimToken: "tail-after-legacy-release-token",
        now: InstantTimestamp(milliseconds: 10_002)
      )
    )
    expectNoDifference(tailWindow.mutations.map(\.id), [mutations[1].id])
    _ = try await store.releaseAutomaticOutboxClaim(token: "tail-after-legacy-release-token")
    await store.simulateUnexpectedConnectionCloseForTesting()
  }

  @Test
  func expiredClaimClearsProjectedByteReservationBeforeRefill() async throws {
    let cacheURL = try temporaryBoundedOutboxCacheURL()
    let mutation = boundedMutation(index: 0, prefix: "expired-projected-byte-claim")
    try await seedBoundedOutbox([mutation], cacheURL: cacheURL)
    let store = try SQLitePersistenceStore(fileURL: cacheURL)
    try await store.bootstrap()

    let claim = try await store.claimAutomaticOutboxDeliveryWindow(
      InstantAutomaticOutboxClaimRequest(
        claimantID: "expired-projected-byte-runtime",
        claimToken: "expired-projected-byte-token",
        now: InstantTimestamp(milliseconds: 10_000)
      )
    )
    expectNoDifference(claim.mutations.map(\.id), [mutation.id])
    #expect(
      try await store.outboxDeliveryClaimForTesting(id: mutation.id)?
        .projectedBodyByteCount != nil
    )

    let reclaimed = try await store.claimAutomaticOutboxDeliveryWindow(
      InstantAutomaticOutboxClaimRequest(
        claimantID: "expired-projected-byte-runtime",
        claimToken: "no-refill-token",
        now: InstantTimestamp(
          milliseconds: 10_000
            + InstantMutationAcknowledgementDeadlinePolicy.baseIntervalMilliseconds
        ),
        maximumMutationCount: 0
      )
    )
    expectNoDifference(reclaimed.reclaimedMutationIDs, [mutation.id])
    expectNoDifference(reclaimed.mutations.map(\.id), [])
    let expiredClaim = try #require(
      try await store.outboxDeliveryClaimForTesting(id: mutation.id)
    )
    expectNoDifference(expiredClaim.state, .ready)
    expectNoDifference(expiredClaim.claimToken, nil)
    expectNoDifference(expiredClaim.projectedBodyByteCount, nil)
    await store.simulateUnexpectedConnectionCloseForTesting()
  }

  @Test
  func explicitFlushCannotLeapfrogAnAutomaticallyClaimedHead() async throws {
    let cacheURL = try temporaryBoundedOutboxCacheURL()
    let mutations = (0..<2).map {
      boundedMutation(
        index: $0,
        prefix: "explicit-head-barrier",
        entityID: "one-explicit-head-entity"
      )
    }
    try await seedBoundedOutbox(mutations, cacheURL: cacheURL)
    let automaticStore = try SQLitePersistenceStore(fileURL: cacheURL)
    let explicitStore = try SQLitePersistenceStore(fileURL: cacheURL)
    try await automaticStore.bootstrap()
    try await explicitStore.bootstrap()
    let automatic = try await automaticStore.claimAutomaticOutboxDeliveryWindow(
      InstantAutomaticOutboxClaimRequest(
        claimantID: "automatic-runtime",
        claimToken: "automatic-head-token",
        now: InstantTimestamp(milliseconds: 20_000),
        maximumMutationCount: 1
      )
    )
    expectNoDifference(automatic.mutations.map(\.id), ["tx-explicit-head-barrier-00000"])

    do {
      _ = try await explicitStore.claimPendingOutboxMutationsForExplicitFlush(
        limit: 1,
        claimantID: "explicit-runtime",
        claimToken: "explicit-token",
        now: InstantTimestamp(milliseconds: 20_000)
      )
      Issue.record("Expected the explicit lane to stop at the claimed queue head.")
    } catch let error as InstantError {
      expectNoDifference(error.operation, "claim explicit outbox flush")
    }

    let revision = try await automaticStore.currentOutboxRevision()
    _ = try await automaticStore.acceptOutboxMutation(
      id: "tx-explicit-head-barrier-00000",
      serverTransactionID: "server-explicit-head",
      claimantID: "automatic-runtime",
      claimToken: "automatic-head-token",
      expectedOutboxRevision: revision
    )
    let explicit = try await explicitStore.claimPendingOutboxMutationsForExplicitFlush(
      limit: 1,
      claimantID: "explicit-runtime",
      claimToken: "explicit-token-after-head",
      now: InstantTimestamp(milliseconds: 20_001)
    )
    expectNoDifference(explicit.map(\.id), ["tx-explicit-head-barrier-00001"])
    _ = try await explicitStore.releaseAutomaticOutboxClaim(
      token: "explicit-token-after-head"
    )
  }

  @Test
  func explicitFlushStopsBeforeLocalOnlyConfirmedBarrier() async throws {
    let cacheURL = try temporaryBoundedOutboxCacheURL()
    let liveSession = LiveReactorParitySession(messages: [
      liveReactorInitOK(attrs: liveReactorTodoServerAttrs)
    ])
    let explicitProbe = BoundedOutboxExplicitRequestProbe()
    var configuration = InstantRuntimeConfiguration(
      appID: "bounded-outbox-explicit-confirmed-barrier",
      persistenceURL: cacheURL,
      initialAttributes: TodoExample.attributes,
      mutationTransport: InstantMutationTransportClient { request in
        await explicitProbe.record(request)
        return InstantMutationTransportResponse(results: [])
      },
      liveTransport: liveSession.transport
    )
    configuration.autoConnectLiveTransport = false
    let runtime = try await InstantRuntime.bootstrap(configuration: configuration)
    _ = try await appendRuntimePreparedBoundedOutbox([
      unprovenConfirmedBoundedMutation(
        index: 0,
        prefix: "explicit-confirmed-barrier"
      ),
      boundedMutation(index: 1, prefix: "explicit-confirmed-barrier"),
    ], to: runtime.persistence)

    let flush = try await runtime.flushPendingMutations(limit: 1)
    #expect(flush.request.mutations.isEmpty)
    let explicitRequestCount = await explicitProbe.requestCount()
    expectNoDifference(explicitRequestCount, 0)

    _ = try await runtime.connect()
    try await instantLiveWithTimeout(
      operation: "wait for automatic delivery behind the explicit confirmed barrier",
      timeoutMilliseconds: 5_000
    ) {
      await liveSession.waitForSentMessageCount(3)
    }
    let sentIDs = await liveSession.sentMessages()
      .filter { $0.op == "transact" }
      .compactMap(\.clientEventID)
    expectNoDifference(sentIDs, [
      "tx-explicit-confirmed-barrier-00000",
      "tx-explicit-confirmed-barrier-00001",
    ])
    _ = try? await runtime.closeConnection()
  }

  @Test
  func explicitFlushMarksOnlySelectedRowsBeforeTransportAndKeepsProofSticky()
    async throws
  {
    let cacheURL = try temporaryBoundedOutboxCacheURL()
    let probe = BoundedOutboxExplicitFlushProbe(cacheURL: cacheURL)
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "bounded-outbox-explicit-offer",
        persistenceURL: cacheURL,
        initialAttributes: TodoExample.attributes,
        mutationTransport: InstantMutationTransportClient { request in
          try await probe.observe(request)
          return InstantMutationTransportResponse(
            results: request.mutations.map {
              InstantMutationTransportResult(
                mutationID: $0.mutationID,
                outcome: .confirmed
              )
            }
          )
        }
      )
    )
    for index in 0..<2 {
      let mutation = boundedMutation(index: index, prefix: "explicit-offer")
      _ = try await runtime.transact(mutation.transaction, createdAt: mutation.createdAt)
    }

    _ = await runtime.outboxMutations()
    let firstBeforeFlush = try await runtime.persistence.outboxDeliveryStartedForTesting(
      id: "tx-explicit-offer-00000"
    )
    let secondBeforeFlush = try await runtime.persistence.outboxDeliveryStartedForTesting(
      id: "tx-explicit-offer-00001"
    )
    expectNoDifference(firstBeforeFlush, false, "Public inspection is read-only.")
    expectNoDifference(secondBeforeFlush, false, "Public inspection is read-only.")

    let result = try await runtime.flushPendingMutations(limit: 1)
    let observed = await probe.observedDeliveryStarted()
    expectNoDifference(result.request.mutations.map(\.mutationID), ["tx-explicit-offer-00000"])
    expectNoDifference(observed, [
      "tx-explicit-offer-00000": true,
      "tx-explicit-offer-00001": false,
    ])

    let firstAfterStatusRewrite = try await runtime.persistence
      .outboxDeliveryStartedForTesting(id: "tx-explicit-offer-00000")
    let secondAfterStatusRewrite = try await runtime.persistence
      .outboxDeliveryStartedForTesting(id: "tx-explicit-offer-00001")
    expectNoDifference(
      firstAfterStatusRewrite,
      true,
      "A transport-result body/status rewrite must preserve ever-offered proof."
    )
    expectNoDifference(secondAfterStatusRewrite, false, "The flush limit marks no tail rows.")
  }

  @Test
  func explicitFlushTimeoutAbortsAndExactlyJoinsCancellationIgnoringOperationAndRenewal()
    async throws
  {
    let cacheURL = try temporaryBoundedOutboxCacheURL()
    let transport = BoundedOutboxCancellationIgnoringPreparedTransport()
    let deadlineSleep = BoundedOutboxCancellationIgnoringSleep()
    let renewalSleep = BoundedOutboxCancellationIgnoringSleep()
    let completion = BoundedOutboxCompletionProbe()
    var configuration = InstantRuntimeConfiguration(
      appID: "bounded-outbox-explicit-timeout-exact-cleanup",
      persistenceURL: cacheURL,
      initialAttributes: TodoExample.attributes,
      mutationTransport: .preparedOperations { request in
        transport.operation(for: request)
      }
    )
    configuration.explicitMutationTransportDeadlineSleep = { milliseconds in
      try await deadlineSleep.sleep(milliseconds: milliseconds)
    }
    configuration.explicitMutationClaimRenewalSleep = { milliseconds in
      try await renewalSleep.sleep(milliseconds: milliseconds)
    }
    let runtime = try await InstantRuntime.bootstrap(configuration: configuration)
    let mutation = boundedMutation(
      index: 0,
      prefix: "explicit-timeout-exact-cleanup",
      entityID: "one-explicit-timeout-entity"
    )
    _ = try await runtime.transact(mutation.transaction, createdAt: mutation.createdAt)

    let flush = Task {
      defer { completion.record() }
      return try await runtime.flushPendingMutations(limit: 1)
    }
    defer {
      flush.cancel()
      transport.releaseWithServerAcceptance()
      deadlineSleep.release()
      renewalSleep.release()
    }
    try await instantLiveWithTimeout(
      operation: "wait for the prepared explicit mutation operation and its owned timers",
      timeoutMilliseconds: 5_000
    ) {
      while !transport.didEnter || !deadlineSleep.didEnter || !renewalSleep.didEnter {
        try Task.checkCancellation()
        await Task.yield()
      }
    }
    expectNoDifference(transport.mutationIDs, [mutation.id])
    expectNoDifference(
      deadlineSleep.requestedMilliseconds,
      UInt64(InstantAutomaticOutboxClaimLimits.claimTimeoutMilliseconds)
    )

    deadlineSleep.release()
    try await instantLiveWithTimeout(
      operation: "wait for explicit mutation timeout to abort transport work",
      timeoutMilliseconds: 5_000
    ) {
      while transport.abortCount != 1 {
        try Task.checkCancellation()
        await Task.yield()
      }
    }
    expectNoDifference(
      renewalSleep.cancellationCount,
      0,
      "The durable claim keeps renewing until the exact late response is dispositioned."
    )
    expectNoDifference(
      deadlineSleep.cancellationCount,
      0,
      "The five-second deadline wins naturally; it is not modeled as caller cancellation."
    )
    expectNoDifference(completion.didComplete, false)
    #expect(!(await runtime.exactCloseBackgroundTasksAreIdleForTesting()))

    transport.releaseWithServerAcceptance()
    try await instantLiveWithTimeout(
      operation: "wait for cancellation-ignoring explicit transport to return",
      timeoutMilliseconds: 5_000
    ) {
      while transport.runCompletionCount != 1 {
        try Task.checkCancellation()
        await Task.yield()
      }
    }
    try await instantLiveWithTimeout(
      operation: "wait for late authoritative acceptance disposition before timeout returns",
      timeoutMilliseconds: 5_000
    ) {
      while try await runtime.persistence.countOutboxMutations(status: .confirmed) != 1 {
        try Task.checkCancellation()
        await Task.yield()
      }
    }
    expectNoDifference(
      completion.didComplete,
      false,
      "A timeout cannot return while the exact renewal tail still owns the flush graph."
    )
    let outboxRevisionAfterDisposition = try await runtime.persistence.currentOutboxRevision()
    let persistedAfterDisposition = try #require(
      try await runtime.persistence.loadOutboxMutations(
        statuses: [.pending, .confirmed, .failed],
        ids: [mutation.id],
        limit: 1,
        expectedOutboxRevision: outboxRevisionAfterDisposition
      )?.first
    )
    expectNoDifference(persistedAfterDisposition.status, .confirmed)
    expectNoDifference(persistedAfterDisposition.confirmationSource, .serverTransport)
    #expect(persistedAfterDisposition.provesServerAcceptance)
    try await instantLiveWithTimeout(
      operation: "wait for renewal cancellation after authoritative timeout disposition",
      timeoutMilliseconds: 5_000
    ) {
      while renewalSleep.cancellationCount != 1 {
        try Task.checkCancellation()
        await Task.yield()
      }
    }
    expectNoDifference(completion.didComplete, false)

    renewalSleep.release()
    do {
      _ = try await instantLiveWithTimeout(
        operation: "wait for explicit timeout to join all exact owned work",
        timeoutMilliseconds: 5_000
      ) {
        try await flush.value
      }
      Issue.record("Expected the explicit mutation transport to time out at five seconds.")
    } catch let error as InstantError {
      expectNoDifference(error.operation, "flush Instant mutation transport")
      #expect(error.message.contains("5000ms"))
    }

    expectNoDifference(completion.didComplete, true)
    expectNoDifference(transport.abortCount, 1, "Prepared-operation abort is idempotent.")
    #expect(await runtime.exactCloseBackgroundTasksAreIdleForTesting())
    let pendingCount = try await runtime.persistence.countOutboxMutations(status: .pending)
    expectNoDifference(pendingCount, 0)
    let confirmedCount = try await runtime.persistence.countOutboxMutations(status: .confirmed)
    expectNoDifference(confirmedCount, 1)
    let outboxRevisionAfterTimeoutReturn = try await runtime.persistence.currentOutboxRevision()
    expectNoDifference(
      outboxRevisionAfterTimeoutReturn,
      outboxRevisionAfterDisposition,
      "The timeout error returns only after authoritative acceptance is durably complete."
    )
  }

  @Test
  func closeConnectionAbortsAndExactlyJoinsActiveExplicitFlushBeforeReturning()
    async throws
  {
    let cacheURL = try temporaryBoundedOutboxCacheURL()
    let transport = BoundedOutboxCancellationIgnoringPreparedTransport()
    let deadlineSleep = BoundedOutboxCancellationIgnoringSleep()
    let renewalSleep = BoundedOutboxCancellationIgnoringSleep()
    let flushCompletion = BoundedOutboxCompletionProbe()
    let closeCompletion = BoundedOutboxCompletionProbe()
    var configuration = InstantRuntimeConfiguration(
      appID: "bounded-outbox-explicit-close-exact-cleanup",
      persistenceURL: cacheURL,
      initialAttributes: TodoExample.attributes,
      mutationTransport: .preparedOperations { request in
        transport.operation(for: request)
      }
    )
    configuration.explicitMutationTransportDeadlineSleep = { milliseconds in
      try await deadlineSleep.sleep(milliseconds: milliseconds)
    }
    configuration.explicitMutationClaimRenewalSleep = { milliseconds in
      try await renewalSleep.sleep(milliseconds: milliseconds)
    }
    let runtime = try await InstantRuntime.bootstrap(configuration: configuration)
    let mutation = boundedMutation(index: 0, prefix: "explicit-close-exact-cleanup")
    _ = try await runtime.transact(mutation.transaction, createdAt: mutation.createdAt)

    let flush = Task {
      defer { flushCompletion.record() }
      return try await runtime.flushPendingMutations(limit: 1)
    }
    defer {
      flush.cancel()
      transport.releaseWithServerAcceptance()
      deadlineSleep.release()
      renewalSleep.release()
    }
    try await instantLiveWithTimeout(
      operation: "wait for active explicit flush before close",
      timeoutMilliseconds: 5_000
    ) {
      while !transport.didEnter || !deadlineSleep.didEnter || !renewalSleep.didEnter {
        try Task.checkCancellation()
        await Task.yield()
      }
    }
    expectNoDifference(transport.mutationIDs, [mutation.id])
    let close = Task {
      let status = try await runtime.closeConnection()
      closeCompletion.record()
      return status
    }
    defer { close.cancel() }
    try await instantLiveWithTimeout(
      operation: "wait for close to abort explicit transport and deadline work",
      timeoutMilliseconds: 5_000
    ) {
      while transport.abortCount != 1
        || deadlineSleep.cancellationCount != 1
      {
        try Task.checkCancellation()
        await Task.yield()
      }
    }
    expectNoDifference(
      renewalSleep.cancellationCount,
      0,
      "Close keeps the durable claim renewed until the exact late response is dispositioned."
    )
    let stateWhileAuthoritativeResponseIsPending = try await runtime.connectionStatus().state
    #expect(stateWhileAuthoritativeResponseIsPending != .closed)
    expectNoDifference(closeCompletion.didComplete, false)
    expectNoDifference(flushCompletion.didComplete, false)
    #expect(!(await runtime.exactCloseBackgroundTasksAreIdleForTesting()))

    transport.releaseWithServerAcceptance()
    try await instantLiveWithTimeout(
      operation: "wait for aborted explicit transport tail",
      timeoutMilliseconds: 5_000
    ) {
      while transport.runCompletionCount != 1 {
        try Task.checkCancellation()
        await Task.yield()
      }
    }
    try await instantLiveWithTimeout(
      operation: "wait for authoritative acceptance disposition before close publishes closed",
      timeoutMilliseconds: 5_000
    ) {
      while try await runtime.persistence.countOutboxMutations(status: .confirmed) != 1 {
        try Task.checkCancellation()
        await Task.yield()
      }
    }
    expectNoDifference(closeCompletion.didComplete, false)
    expectNoDifference(flushCompletion.didComplete, false)
    let stateAfterDispositionBeforeCleanupJoin = try await runtime.connectionStatus().state
    #expect(stateAfterDispositionBeforeCleanupJoin != .closed)
    let outboxRevisionAfterDisposition = try await runtime.persistence.currentOutboxRevision()
    let persistedAfterDisposition = try #require(
      try await runtime.persistence.loadOutboxMutations(
        statuses: [.pending, .confirmed, .failed],
        ids: [mutation.id],
        limit: 1,
        expectedOutboxRevision: outboxRevisionAfterDisposition
      )?.first
    )
    expectNoDifference(persistedAfterDisposition.status, .confirmed)
    expectNoDifference(persistedAfterDisposition.confirmationSource, .serverTransport)
    #expect(persistedAfterDisposition.provesServerAcceptance)
    try await instantLiveWithTimeout(
      operation: "wait for renewal cancellation after authoritative close disposition",
      timeoutMilliseconds: 5_000
    ) {
      while renewalSleep.cancellationCount != 1 {
        try Task.checkCancellation()
        await Task.yield()
      }
    }
    expectNoDifference(closeCompletion.didComplete, false)
    expectNoDifference(flushCompletion.didComplete, false)

    deadlineSleep.release()
    renewalSleep.release()
    let closedStatus = try await instantLiveWithTimeout(
      operation: "wait for close to join active explicit flush",
      timeoutMilliseconds: 5_000
    ) {
      try await close.value
    }
    expectNoDifference(closedStatus.state, .closed)
    expectNoDifference(closeCompletion.didComplete, true)
    #expect(await runtime.exactCloseBackgroundTasksAreIdleForTesting())
    let pendingCountAtCloseReturn = try await runtime.persistence.countOutboxMutations(
      status: .pending
    )
    expectNoDifference(pendingCountAtCloseReturn, 0)
    let confirmedCountAtCloseReturn = try await runtime.persistence.countOutboxMutations(
      status: .confirmed
    )
    expectNoDifference(confirmedCountAtCloseReturn, 1)
    let outboxRevisionAtCloseReturn = try await runtime.persistence.currentOutboxRevision()
    expectNoDifference(
      outboxRevisionAtCloseReturn,
      outboxRevisionAfterDisposition,
      "Close publishes closed only after the exact accepted response is durable."
    )

    do {
      _ = try await instantLiveWithTimeout(
        operation: "wait for close-cancelled explicit flush caller",
        timeoutMilliseconds: 5_000
      ) {
        try await flush.value
      }
    } catch {}

    expectNoDifference(flushCompletion.didComplete, true)
    expectNoDifference(transport.abortCount, 1, "Close abort is idempotent.")
    #expect(await runtime.exactCloseBackgroundTasksAreIdleForTesting())
    let outboxRevisionAfterFlushCaller = try await runtime.persistence.currentOutboxRevision()
    expectNoDifference(
      outboxRevisionAfterFlushCaller,
      outboxRevisionAtCloseReturn,
      "No explicit-flush disposition may write after close returns."
    )
  }

  @Test
  func staleExplicitFailureCannotFailAReclaimedMutation() async throws {
    let cacheURL = try temporaryBoundedOutboxCacheURL()
    let transport = BoundedOutboxSuspendedExplicitTransport()
    let now = InstantTimestamp(milliseconds: 100_000)
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "bounded-outbox-explicit-stale-failure",
        persistenceURL: cacheURL,
        initialAttributes: TodoExample.attributes,
        now: { now },
        mutationTransport: InstantMutationTransportClient { request in
          await transport.send(request)
        }
      )
    )
    let mutation = boundedMutation(
      index: 0,
      prefix: "explicit-stale-failure",
      entityID: "explicit-stale-failure-entity"
    )
    _ = try await runtime.transact(mutation.transaction, createdAt: mutation.createdAt)

    let flush = Task { try await runtime.flushPendingMutations(limit: 1) }
    await transport.waitUntilEntered()
    let competingStore = try SQLitePersistenceStore(fileURL: cacheURL)
    try await competingStore.bootstrap()
    let expired = try await competingStore.claimAutomaticOutboxDeliveryWindow(
      InstantAutomaticOutboxClaimRequest(
        claimantID: "reclaiming-runtime",
        claimToken: "expiry-only-token",
        now: InstantTimestamp(
          milliseconds: now.milliseconds
            + InstantAutomaticOutboxClaimLimits.claimTimeoutMilliseconds + 1
        )
      )
    )
    expectNoDifference(expired.reclaimedMutationIDs, [mutation.id])
    expectNoDifference(expired.mutations, [])
    let reclaimed = try await competingStore.claimAutomaticOutboxDeliveryWindow(
      InstantAutomaticOutboxClaimRequest(
        claimantID: "reclaiming-runtime",
        claimToken: "reclaimed-token",
        now: InstantTimestamp(
          milliseconds: now.milliseconds
            + InstantAutomaticOutboxClaimLimits.claimTimeoutMilliseconds + 1
        )
      )
    )
    expectNoDifference(reclaimed.mutations.map(\.id), [mutation.id])

    await transport.resumeFailed(message: "late permission rejection")
    let result = try await flush.value
    #expect(
      result.failed.isEmpty,
      "A transport response may dispose only the exact durable claim token it was issued."
    )
    let outboxRevision = try await competingStore.currentOutboxRevision()
    let persistedRows = try await competingStore.loadOutboxMutations(
      statuses: [.pending, .confirmed, .failed],
      ids: [mutation.id],
      limit: 1,
      expectedOutboxRevision: outboxRevision
    )
    let persisted = try #require(
      persistedRows?.first
    )
    expectNoDifference(persisted.status, .pending)
    expectNoDifference(persisted.failureMessage, nil)
    let claim = try await competingStore.outboxDeliveryClaimForTesting(id: mutation.id)
    expectNoDifference(claim?.claimToken, "reclaimed-token")
    let visible = await runtime.store.snapshot().triples
    #expect(visible.contains { $0.entityID == "explicit-stale-failure-entity" })
    _ = try await competingStore.releaseAutomaticOutboxClaim(token: "reclaimed-token")
  }

  @Test
  func validExplicitFailureAtomicallyRemovesItsOptimisticValue() async throws {
    let cacheURL = try temporaryBoundedOutboxCacheURL()
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "bounded-outbox-explicit-valid-failure",
        persistenceURL: cacheURL,
        initialAttributes: TodoExample.attributes,
        mutationTransport: InstantMutationTransportClient { request in
          InstantMutationTransportResponse(
            results: request.mutations.map {
              InstantMutationTransportResult(
                mutationID: $0.mutationID,
                outcome: .failed,
                message: "permission rejected"
              )
            }
          )
        }
      )
    )
    let mutation = boundedMutation(
      index: 0,
      prefix: "explicit-valid-failure",
      entityID: "explicit-valid-failure-entity"
    )
    _ = try await runtime.transact(mutation.transaction, createdAt: mutation.createdAt)
    let optimistic = await runtime.store.snapshot().triples
    #expect(optimistic.contains { $0.entityID == "explicit-valid-failure-entity" })

    let result = try await runtime.flushPendingMutations(limit: 1)
    expectNoDifference(result.failed.map(\.id), [mutation.id])
    let afterRejection = await runtime.store.snapshot().triples
    #expect(
      !afterRejection.contains { $0.entityID == "explicit-valid-failure-entity" },
      "A valid server rejection removes the rejected optimistic layer, matching Reactor."
    )
  }

  @Test
  func explicitConfirmationRejectsChangedWireAndPreservesSameWireRebase() async throws {
    let cacheURL = try temporaryBoundedOutboxCacheURL()
    let persistence = try SQLitePersistenceStore(fileURL: cacheURL)
    try await persistence.bootstrap()
    let original = boundedMutation(
      index: 0,
      prefix: "explicit-confirm-rebase",
      entityID: "before-rebase"
    )
    let durableOriginal = try #require(
      try await appendRuntimePreparedBoundedOutbox([original], to: persistence).first
    )
    let selected = try await persistence.claimPendingOutboxMutationsForExplicitFlush(
      limit: 1,
      claimantID: "explicit-confirm-runtime",
      claimToken: "explicit-confirm-token",
      now: InstantTimestamp(milliseconds: 50_000)
    )
    let optionalRawBodyBeforeChangedWire = try boundedOutboxRawBody(
      id: durableOriginal.id,
      cacheURL: cacheURL
    )
    let rawBodyBeforeChangedWire = try #require(optionalRawBodyBeforeChangedWire)
    let claimBeforeChangedWire = try #require(
      try await persistence.outboxDeliveryClaimForTesting(id: durableOriginal.id)
    )
    let rowRevisionBeforeChangedWire = try await persistence
      .outboxMutationRevisionForTesting(id: durableOriginal.id)
    let stateBeforeChangedWire = try await persistence.loadCompactState()

    var changedWire = durableOriginal
    changedWire.transaction = boundedMutation(
      index: 1,
      prefix: "explicit-confirm-rebased-body",
      entityID: "rebased-current-entity"
    ).transaction
    changedWire.transaction.id = durableOriginal.id
    do {
      _ = try await replaceRuntimePreparedBoundedOutboxMutation(
        changedWire,
        replacing: durableOriginal,
        in: persistence
      )
      Issue.record("Expected explicit delivery to freeze the offered wire intent.")
    } catch let error as InstantError {
      expectNoDifference(error.code, .persistenceFailed)
      expectNoDifference(error.operation, "persist offered outbox mutation")
    }

    let optionalRawBodyAfterChangedWire = try boundedOutboxRawBody(
      id: durableOriginal.id,
      cacheURL: cacheURL
    )
    let rawBodyAfterChangedWire = try #require(optionalRawBodyAfterChangedWire)
    let claimAfterChangedWire = try #require(
      try await persistence.outboxDeliveryClaimForTesting(id: durableOriginal.id)
    )
    let rowRevisionAfterChangedWire = try await persistence
      .outboxMutationRevisionForTesting(id: durableOriginal.id)
    let stateAfterChangedWire = try await persistence.loadCompactState()
    expectNoDifference(rawBodyAfterChangedWire, rawBodyBeforeChangedWire)
    expectNoDifference(claimAfterChangedWire, claimBeforeChangedWire)
    expectNoDifference(rowRevisionAfterChangedWire, rowRevisionBeforeChangedWire)
    expectNoDifference(stateAfterChangedWire.storeRevision, stateBeforeChangedWire.storeRevision)
    expectNoDifference(
      stateAfterChangedWire.attributeRevision,
      stateBeforeChangedWire.attributeRevision
    )
    expectNoDifference(
      stateAfterChangedWire.outboxRevision,
      stateBeforeChangedWire.outboxRevision
    )
    expectNoDifference(
      stateAfterChangedWire.queryResultRevision,
      stateBeforeChangedWire.queryResultRevision
    )

    let confirmedOriginal = try await persistence.confirmExplicitlyFlushedOutboxMutations(
      [
        InstantMutationTransportResult(
          mutationID: durableOriginal.id,
          outcome: .confirmed,
          acceptance: .serverAccepted
        )
      ],
      selectedMutations: selected,
      claimToken: "explicit-confirm-token"
    )
    expectNoDifference(confirmedOriginal.map(\.transaction), [durableOriginal.transaction])
    expectNoDifference(confirmedOriginal.map(\.status), [.confirmed])
    let revision = try await persistence.currentOutboxRevision()
    let currentRows = try await persistence.loadOutboxMutations(
      statuses: [.pending, .confirmed, .failed],
      ids: [durableOriginal.id],
      limit: 1,
      expectedOutboxRevision: revision
    )
    let current = try #require(currentRows?.first)
    expectNoDifference(current.transaction, durableOriginal.transaction)
    expectNoDifference(current.rollbackTransaction, durableOriginal.rollbackTransaction)
    expectNoDifference(current.status, .confirmed)

    let sameWireURL = try temporaryBoundedOutboxCacheURL()
    let sameWirePersistence = try SQLitePersistenceStore(fileURL: sameWireURL)
    try await sameWirePersistence.bootstrap()
    let sameWireOriginal = try #require(
      try await appendRuntimePreparedBoundedOutbox(
        [boundedMutation(index: 0, prefix: "explicit-confirm-same-wire")],
        to: sameWirePersistence
      ).first
    )
    let selectedSameWire = try await sameWirePersistence
      .claimPendingOutboxMutationsForExplicitFlush(
        limit: 1,
        claimantID: "explicit-confirm-runtime",
        claimToken: "explicit-confirm-same-wire-token",
        now: InstantTimestamp(milliseconds: 60_000)
      )
    let claimBeforeSameWireRebase = try #require(
      try await sameWirePersistence.outboxDeliveryClaimForTesting(id: sameWireOriginal.id)
    )
    let rowRevisionBeforeSameWireRebase = try await sameWirePersistence
      .outboxMutationRevisionForTesting(id: sameWireOriginal.id)
    let stateBeforeSameWireRebase = try await sameWirePersistence.loadCompactState()
    var sameWireRebase = sameWireOriginal
    sameWireRebase.transaction.operations = sameWireRebase.transaction.operations.map {
      switch $0 {
      case var .insert(triple):
        triple.txTime = InstantTimestamp(milliseconds: 60_001)
        return .insert(triple)
      default:
        return $0
      }
    }
    let durableSameWireRebase = try await replaceRuntimePreparedBoundedOutboxMutation(
      sameWireRebase,
      replacing: sameWireOriginal,
      in: sameWirePersistence
    )
    let claimAfterSameWireRebase = try #require(
      try await sameWirePersistence.outboxDeliveryClaimForTesting(id: sameWireOriginal.id)
    )
    let rowRevisionAfterSameWireRebase = try await sameWirePersistence
      .outboxMutationRevisionForTesting(id: sameWireOriginal.id)
    let stateAfterSameWireRebase = try await sameWirePersistence.loadCompactState()
    expectNoDifference(claimAfterSameWireRebase, claimBeforeSameWireRebase)
    expectNoDifference(rowRevisionAfterSameWireRebase, rowRevisionBeforeSameWireRebase + 1)
    expectNoDifference(
      stateAfterSameWireRebase.outboxRevision,
      stateBeforeSameWireRebase.outboxRevision + 1
    )
    expectNoDifference(
      try sameWireOriginal.mutationWireIntentFingerprint(),
      try durableSameWireRebase.mutationWireIntentFingerprint()
    )
    let confirmedSameWire = try await sameWirePersistence
      .confirmExplicitlyFlushedOutboxMutations(
        [
          InstantMutationTransportResult(
            mutationID: sameWireOriginal.id,
            outcome: .confirmed,
            acceptance: .serverAccepted
          )
        ],
        selectedMutations: selectedSameWire,
        claimToken: "explicit-confirm-same-wire-token"
      )
    let returnedSameWire = try #require(confirmedSameWire.first)
    expectNoDifference(returnedSameWire.transaction, durableSameWireRebase.transaction)
    expectNoDifference(
      returnedSameWire.rollbackTransaction,
      durableSameWireRebase.rollbackTransaction
    )
    expectNoDifference(returnedSameWire.status, .confirmed)

    let sameWireRevision = try await sameWirePersistence.currentOutboxRevision()
    let sameWireRows = try await sameWirePersistence.loadOutboxMutations(
      statuses: [.pending, .confirmed, .failed],
      ids: [sameWireOriginal.id],
      limit: 1,
      expectedOutboxRevision: sameWireRevision
    )
    let currentSameWire = try #require(sameWireRows?.first)
    expectNoDifference(currentSameWire.transaction, durableSameWireRebase.transaction)
    expectNoDifference(
      currentSameWire.rollbackTransaction,
      durableSameWireRebase.rollbackTransaction
    )
    expectNoDifference(currentSameWire.status, .confirmed)
  }

  @Test
  func migrationTreatsLegacyRowsAsOfferedAndNewRowsAsNeverOffered() async throws {
    let cacheURL = try temporaryBoundedOutboxCacheURL()
    let legacyMutation = boundedMutation(index: 0, prefix: "migration-legacy")
    let legacyStore = try SQLitePersistenceStore(fileURL: cacheURL)
    try await legacyStore.bootstrap()
    try await legacyStore.saveOutbox([legacyMutation])
    await legacyStore.simulateUnexpectedConnectionCloseForTesting()
    try restorePreBoundedDeliveryOutboxSchema(cacheURL: cacheURL)

    let migratedStore = try SQLitePersistenceStore(fileURL: cacheURL)
    try await migratedStore.bootstrap()
    let legacyDeliveryStarted = try await migratedStore.outboxDeliveryStartedForTesting(
      id: legacyMutation.id
    )
    expectNoDifference(
      legacyDeliveryStarted,
      true,
      "Rows that predate durable offer tracking must migrate fail-closed."
    )

    let newMutation = boundedMutation(index: 1, prefix: "migration-new")
    try await migratedStore.saveOutbox([legacyMutation, newMutation])
    let preservedLegacyDeliveryStarted =
      try await migratedStore
      .outboxDeliveryStartedForTesting(id: legacyMutation.id)
    let newDeliveryStarted = try await migratedStore.outboxDeliveryStartedForTesting(
      id: newMutation.id
    )
    expectNoDifference(preservedLegacyDeliveryStarted, true, boundedOutboxSource)
    expectNoDifference(
      newDeliveryStarted,
      false,
      "Only rows inserted with durable offer tracking may begin as never offered."
    )
  }

  @Test
  func receiptAuthorityMigrationGrandfathersOnlyBoundedPreReceiptRuntimeShapes() async throws {
    let cacheURL = try temporaryBoundedOutboxCacheURL()
    let store = try SQLitePersistenceStore(fileURL: cacheURL)
    try await store.bootstrap()

    let materialized = legacyReceiptMutation(
      index: 0,
      prefix: "receipt-migration-materialized",
      overlayState: .applied,
      rollback: .releasedInverse
    )
    let replayable = legacyReceiptMutation(
      index: 1,
      prefix: "receipt-migration-replayable",
      overlayState: .applied,
      rollback: .none
    )
    let removed = legacyReceiptMutation(
      index: 2,
      prefix: "receipt-migration-removed",
      status: .failed,
      overlayState: .removed,
      rollback: .none
    )
    var accepted = legacyReceiptMutation(
      index: 3,
      prefix: "receipt-migration-accepted",
      status: .confirmed,
      overlayState: .applied,
      rollback: .releasedInverse
    )
    accepted.serverTransactionID = "server-receipt-migration-accepted"
    accepted.confirmationSource = .webSocketTransactOK
    let wrongRollbackID = legacyReceiptMutation(
      index: 4,
      prefix: "receipt-migration-wrong-rollback-id",
      overlayState: .applied,
      rollback: .wrongID
    )
    let unsupportedRollback = legacyReceiptMutation(
      index: 5,
      prefix: "receipt-migration-unsupported-rollback",
      overlayState: .applied,
      rollback: .unsupportedOperation
    )
    let emptyForward = legacyReceiptMutation(
      index: 6,
      prefix: "receipt-migration-empty-forward",
      overlayState: .applied,
      rollback: .releasedInverse,
      stepCount: 0
    )
    let overStepLimit = legacyReceiptMutation(
      index: 7,
      prefix: "receipt-migration-over-step-limit",
      overlayState: .applied,
      rollback: .releasedInverse,
      stepCount: InstantAutomaticOutboxClaimLimits.maximumStepCount + 1
    )
    var newReceiptShape = legacyReceiptMutation(
      index: 8,
      prefix: "receipt-migration-new-shape",
      overlayState: .applied,
      rollback: .none
    )
    newReceiptShape.optimisticEffectReceiptVersion =
      PendingMutation.currentOptimisticEffectReceiptVersion
    let deployedDeleteInverse = legacyReceiptMutation(
      index: 9,
      prefix: "receipt-migration-deployed-delete-inverse",
      overlayState: .applied,
      rollback: .deployedDeleteEntityInverse
    )
    let taggedReleaseRemoved = legacyReceiptMutation(
      index: 10,
      prefix: "receipt-migration-tagged-release-removed",
      status: .failed,
      overlayState: .removed,
      rollback: .none
    )
    var taggedReleaseAccepted = legacyReceiptMutation(
      index: 11,
      prefix: "receipt-migration-tagged-release-accepted",
      status: .confirmed,
      overlayState: .applied,
      rollback: .releasedInverse
    )
    taggedReleaseAccepted.serverTransactionID = "server-tagged-release-accepted"
    taggedReleaseAccepted.confirmationSource = nil
    let malformed = legacyReceiptMutation(
      index: 12,
      prefix: "receipt-migration-malformed",
      overlayState: .applied,
      rollback: .releasedInverse
    )
    let seeded = [
      materialized,
      replayable,
      removed,
      accepted,
      wrongRollbackID,
      unsupportedRollback,
      emptyForward,
      overStepLimit,
      newReceiptShape,
      deployedDeleteInverse,
      taggedReleaseRemoved,
      taggedReleaseAccepted,
      malformed,
    ]
    try await store.saveOutbox(seeded)
    await store.simulateUnexpectedConnectionCloseForTesting()
    try executeBoundedOutboxSQL(
      """
      UPDATE instant_outbox
      SET optimistic_overlay_active = 0
      WHERE mutation_id = '\(removed.id)';
      UPDATE instant_outbox
      SET confirmation_proven = 1
      WHERE mutation_id = '\(accepted.id)';
      UPDATE instant_outbox
      SET delivery_metadata_version = 0,
          optimistic_overlay_active = 1
      WHERE mutation_id = '\(taggedReleaseRemoved.id)';
      UPDATE instant_outbox
      SET delivery_metadata_version = 0,
          confirmation_proven = NULL
      WHERE mutation_id = '\(taggedReleaseAccepted.id)';
      """,
      cacheURL: cacheURL
    )
    try corruptBoundedOutboxBody(id: malformed.id, cacheURL: cacheURL)
    try restorePreReceiptAuthorityOutboxSchema(cacheURL: cacheURL)

    let migrated = try SQLitePersistenceStore(fileURL: cacheURL)
    try await migrated.bootstrap()
    let migratedRows = try #require(
      try await migrated.loadOutboxMutations(
        statuses: [.pending, .confirmed, .failed],
        ids: seeded.dropLast().map(\.id),
        limit: seeded.count,
        expectedOutboxRevision: try await migrated.currentOutboxRevision()
      )
    )
    let migratedByID = Dictionary(uniqueKeysWithValues: migratedRows.map { ($0.id, $0) })

    expectNoDifference(migratedByID[materialized.id]?.optimisticOverlayState, .applied)
    expectNoDifference(
      migratedByID[replayable.id]?.optimisticOverlayState,
      .applied
    )
    expectNoDifference(
      migratedByID[replayable.id]?.optimisticEffectReceiptVersion,
      PendingMutation.currentOptimisticEffectReceiptVersion
    )
    expectNoDifference(migratedByID[removed.id]?.optimisticOverlayState, .removed)
    for mutation in [
      materialized,
      replayable,
      removed,
      accepted,
      deployedDeleteInverse,
      taggedReleaseRemoved,
      taggedReleaseAccepted,
    ] {
      #expect(
        try await migrated.optimisticEffectReceiptFingerprintForTesting(id: mutation.id) != nil
      )
    }
    for mutation in [wrongRollbackID, unsupportedRollback, emptyForward, overStepLimit, newReceiptShape] {
      let fingerprint = try await migrated
        .optimisticEffectReceiptFingerprintForTesting(id: mutation.id)
      expectNoDifference(fingerprint, nil)
    }
    expectNoDifference(
      try boundedOutboxReceiptFingerprint(id: malformed.id, cacheURL: cacheURL),
      nil
    )
    #expect(
      try boundedOutboxServerAcceptanceFingerprint(id: accepted.id, cacheURL: cacheURL) != nil
    )
    #expect(
      try boundedOutboxServerAcceptanceFingerprint(
        id: taggedReleaseAccepted.id,
        cacheURL: cacheURL
      ) != nil,
      "A v1.5.6 acceptance reaches 0020 with confirmation_proven NULL."
    )
    expectNoDifference(
      try boundedOutboxOptimisticOverlayActive(id: removed.id, cacheURL: cacheURL),
      false
    )
    expectNoDifference(
      try boundedOutboxOptimisticOverlayActive(
        id: taggedReleaseRemoved.id,
        cacheURL: cacheURL
      ),
      false,
      "A v1.5.6 removed body reaches 0020 with the migration-0012 active default."
    )

    let migratedAuthoritySnapshot = try boundedOutboxAuthoritySnapshot(
      ids: seeded.map(\.id),
      cacheURL: cacheURL
    )
    let migratedOutboxRevision = try await migrated.currentOutboxRevision()
    expectNoDifference(
      try boundedOutboxMigrationLedgerCount(
        name: "0020_outbox_optimistic_effect_receipt_fingerprint",
        cacheURL: cacheURL
      ),
      1
    )

    await migrated.simulateUnexpectedConnectionCloseForTesting()
    let relaunched = try SQLitePersistenceStore(fileURL: cacheURL)
    try await relaunched.bootstrap()
    let relaunchedOutboxRevision = try await relaunched.currentOutboxRevision()
    expectNoDifference(
      try boundedOutboxAuthoritySnapshot(ids: seeded.map(\.id), cacheURL: cacheURL),
      migratedAuthoritySnapshot,
      "Re-running bootstrap must not broaden, erase, or rewrite the one-time receipt decision."
    )
    expectNoDifference(
      relaunchedOutboxRevision,
      migratedOutboxRevision
    )
    expectNoDifference(
      try boundedOutboxMigrationLedgerCount(
        name: "0020_outbox_optimistic_effect_receipt_fingerprint",
        cacheURL: cacheURL
      ),
      1
    )
  }

  @Test
  func preServerApplySchemaUpgradeToleratesMalformedAndOversizedOutboxBodies() async throws {
    let cacheURL = try temporaryBoundedOutboxCacheURL()
    let malformed = legacyReceiptMutation(
      index: 0,
      prefix: "malformed-released-upgrade",
      overlayState: .applied,
      rollback: .releasedInverse
    )
    var oversized = legacyReceiptMutation(
      index: 1,
      prefix: "oversized-pre-server-apply-upgrade",
      overlayState: .applied,
      rollback: .releasedInverse
    )
    oversized.transaction.operations = [
      .insert(
        InstantTriple(
          entityID: "todo-oversized-pre-server-apply-upgrade",
          attributeID: "todos/text",
          value: .string(
            String(
              repeating: "x",
              count: InstantAutomaticOutboxClaimLimits.maximumEncodedBodyBytes + 1
            )
          ),
          txID: oversized.id,
          txTime: oversized.createdAt
        )
      )
    ]
    let oversizedBody = String(
      decoding: try JSONEncoder().encode(oversized),
      as: UTF8.self
    )
    #expect(
      oversizedBody.utf8.count > InstantAutomaticOutboxClaimLimits.maximumEncodedBodyBytes
    )
    let store = try SQLitePersistenceStore(fileURL: cacheURL)
    try await store.bootstrap()
    try await store.saveOutbox([malformed, legacyReceiptMutation(
      index: 1,
      prefix: "oversized-pre-server-apply-upgrade",
      overlayState: .applied,
      rollback: .releasedInverse
    )])
    await store.simulateUnexpectedConnectionCloseForTesting()
    try corruptBoundedOutboxBody(id: malformed.id, cacheURL: cacheURL)
    try replaceBoundedOutboxBody(
      id: oversized.id,
      body: oversizedBody,
      cacheURL: cacheURL
    )
    let rawMalformedBodyBeforeUpgrade = try boundedOutboxRawBody(
      id: malformed.id,
      cacheURL: cacheURL
    )
    let malformedBodyBeforeUpgrade = try #require(rawMalformedBodyBeforeUpgrade)
    try restorePreServerApplyAndReceiptAuthorityOutboxSchema(cacheURL: cacheURL)

    let migrated = try SQLitePersistenceStore(fileURL: cacheURL)
    try await migrated.bootstrap()
    expectNoDifference(
      try boundedOutboxReceiptFingerprint(id: malformed.id, cacheURL: cacheURL),
      nil
    )
    expectNoDifference(
      try boundedOutboxReceiptFingerprint(id: oversized.id, cacheURL: cacheURL),
      nil
    )
    expectNoDifference(
      try boundedOutboxRawBody(id: malformed.id, cacheURL: cacheURL),
      malformedBodyBeforeUpgrade
    )
    expectNoDifference(
      try boundedOutboxRawBody(id: oversized.id, cacheURL: cacheURL),
      oversizedBody
    )
  }

  @Test
  func coldRelaunchTenThousandRowDeliveryDecodesOnlyFiftyAndIgnoresCorruptTail() async throws {
    let cacheURL = try temporaryBoundedOutboxCacheURL()
    try await seedBoundedOutbox(
      (0..<10_000).map { boundedMutation(index: $0, prefix: "ten-thousand") },
      cacheURL: cacheURL
    )
    try corruptBoundedOutboxBody(
      id: "tx-ten-thousand-09999",
      cacheURL: cacheURL
    )
    let residentBeforeRelaunch = InstantProcessMemory.sample()?.residentBytes
    let liveSession = LiveReactorParitySession(messages: [
      liveReactorInitOK(attrs: liveReactorTodoServerAttrs)
    ])
    var configuration = InstantRuntimeConfiguration(
      appID: "bounded-outbox-ten-thousand",
      persistenceURL: cacheURL,
      initialAttributes: TodoExample.attributes,
      liveTransport: liveSession.transport
    )
    configuration.autoConnectLiveTransport = false
    let runtime = try await InstantRuntime.bootstrap(configuration: configuration)
    let residentAfterRelaunch = InstantProcessMemory.sample()?.residentBytes
    let bootstrapBodyDecodeCount = await runtime.persistence.currentDecodedOutboxBodyCount()
    let bootstrapLifecycleDecodeCount =
      await runtime.persistence.currentDecodedOutboxLifecycleCount()
    expectNoDifference(bootstrapBodyDecodeCount, 0)
    expectNoDifference(bootstrapLifecycleDecodeCount, 0)
    if let residentBeforeRelaunch, let residentAfterRelaunch {
      #expect(
        residentAfterRelaunch <= residentBeforeRelaunch + 64 * 1_024 * 1_024,
        "Cold bootstrap retained \(residentAfterRelaunch - min(residentAfterRelaunch, residentBeforeRelaunch)) extra resident bytes."
      )
    }
    let firstDeliveryStartedBeforeSelection = try await runtime.persistence
      .outboxDeliveryStartedForTesting(id: "tx-ten-thousand-00000")
    expectNoDifference(firstDeliveryStartedBeforeSelection, false, boundedOutboxSource)

    _ = try await runtime.connect()
    try await instantLiveWithTimeout(
      operation: "wait for bounded ten-thousand-row delivery",
      timeoutMilliseconds: 5_000
    ) {
      await liveSession.waitForSentMessageCount(51)
    }

    let sentMutationIDs = await liveSession.sentMessages()
      .filter { $0.op == "transact" }
      .compactMap(\.clientEventID)
    expectNoDifference(
      sentMutationIDs,
      (0..<50).map { String(format: "tx-ten-thousand-%05d", $0) },
      boundedOutboxSource
    )
    let decodedBodyCount = await runtime.persistence.currentDecodedOutboxBodyCount()
    expectNoDifference(
      decodedBodyCount,
      50,
      boundedOutboxSource
    )
    let decodedBodyByteCount = await runtime.persistence.currentDecodedOutboxBodyByteCount()
    #expect(decodedBodyByteCount <= InstantAutomaticOutboxClaimLimits.maximumEncodedBodyBytes)
    let firstDeliveryStartedAfterSelection = try await runtime.persistence
      .outboxDeliveryStartedForTesting(id: "tx-ten-thousand-00000")
    let tailDeliveryStartedAfterSelection = try await runtime.persistence
      .outboxDeliveryStartedForTesting(id: "tx-ten-thousand-09999")
    expectNoDifference(firstDeliveryStartedAfterSelection, true, boundedOutboxSource)
    expectNoDifference(tailDeliveryStartedAfterSelection, false, boundedOutboxSource)
    _ = try? await runtime.closeConnection()
  }

  @Test
  func untrustedAcceptedHeadsAndCorruptSentinelBlockConnectionBeforePendingTail()
    async throws
  {
    let cacheURL = try temporaryBoundedOutboxCacheURL()
    let liveSession = LiveReactorParitySession(messages: [
      liveReactorInitOK(attrs: liveReactorTodoServerAttrs)
    ])
    let runtime = try await disconnectedRuntime(
      appID: "bounded-outbox-legacy-heads",
      cacheURL: cacheURL,
      liveSession: liveSession
    )
    let acceptedLooking = (0..<2).map {
      acceptedBoundedMutation(index: $0, prefix: "legacy-head")
    }
    try await runtime.persistence.saveOutbox(acceptedLooking)
    let preparedTail = try await appendRuntimePreparedBoundedOutbox(
      [boundedMutation(index: 2, prefix: "legacy-tail")],
      to: runtime.persistence
    )
    expectNoDifference(
      try boundedOutboxReceiptFingerprint(
        id: "tx-legacy-head-00000",
        cacheURL: cacheURL
      ),
      nil
    )
    expectNoDifference(
      try boundedOutboxServerAcceptanceFingerprint(
        id: "tx-legacy-head-00000",
        cacheURL: cacheURL
      ),
      nil
    )
    #expect(
      try boundedOutboxOptimisticOverlayActive(
        id: "tx-legacy-head-00000",
        cacheURL: cacheURL
      )
    )
    try corruptBoundedOutboxBody(
      id: "tx-legacy-head-00000",
      cacheURL: cacheURL
    )
    await runtime.persistence.invalidateMemoryCache()
    await runtime.persistence.resetDecodedOutboxBodyCount()

    do {
      _ = try await runtime.connect()
      Issue.record("Untrusted accepted-looking rows must block live transport I/O.")
    } catch let error as InstantError {
      expectNoDifference(error.code, .persistenceFailed)
      expectNoDifference(error.localID, "tx-legacy-head-00000")
      expectNoDifference(error.localMutationDisposition, .retainedUnknown)
      #expect(error.recovery.contains("Automatic reconnect is paused"))
    }

    let sentMessages = await liveSession.sentMessages()
    let sentMutationIDs = sentMessages
      .filter { $0.op == "transact" }
      .compactMap(\.clientEventID)
    expectNoDifference(sentMessages, [], boundedOutboxSource)
    expectNoDifference(sentMutationIDs, [], boundedOutboxSource)
    let decodedBodyCount = await runtime.persistence.currentDecodedOutboxBodyCount()
    expectNoDifference(decodedBodyCount, 0)
    let rawCorruptBody = try boundedOutboxRawBody(
      id: "tx-legacy-head-00000",
      cacheURL: cacheURL
    )
    expectNoDifference(rawCorruptBody, "{malformed-json")
    let quarantinedBody = try await runtime.persistence.quarantinedOutboxBodyForTesting(
      id: "tx-legacy-head-00000"
    )
    expectNoDifference(
      quarantinedBody,
      nil,
      "The body-free connection preflight must retain the raw repair evidence without decoding or rewriting it."
    )
    let tail = try #require(preparedTail.first)
    let tailRevision = try await runtime.persistence.currentOutboxRevision()
    let durableTail = try #require(
      try await runtime.persistence.loadOutboxMutations(
        statuses: [.pending],
        ids: [tail.id],
        limit: 1,
        expectedOutboxRevision: tailRevision
      )?.first
    )
    expectNoDifference(durableTail.status, .pending)
    let tailClaimValue = try await runtime.persistence.outboxDeliveryClaimForTesting(
      id: tail.id
    )
    let tailClaim = try #require(tailClaimValue)
    expectNoDifference(tailClaim.state, .ready)
    expectNoDifference(tailClaim.claimToken, nil)
    expectNoDifference(tailClaim.deliveryStarted, false)
    let tailReceipt = try await runtime.persistence
      .optimisticEffectReceiptFingerprintForTesting(id: tail.id)
    #expect(tailReceipt != nil)
    let connectionStatus = try await runtime.connectionStatus()
    expectNoDifference(connectionStatus.state, .errored)
    let reconnectIsIdle = await runtime.liveReconnectControllerIsIdleForTesting()
    expectNoDifference(reconnectIsIdle, true)
  }

  @Test
  func SQLiteAuthorizedAcceptedHeadsDoNotStarvePendingTail() async throws {
    let cacheURL = try temporaryBoundedOutboxCacheURL()
    let liveSession = LiveReactorParitySession(messages: [
      liveReactorInitOK(attrs: liveReactorTodoServerAttrs)
    ])
    let runtime = try await disconnectedRuntime(
      appID: "bounded-outbox-authorized-accepted-heads",
      cacheURL: cacheURL,
      liveSession: liveSession
    )
    let preparedHeads = try await appendRuntimePreparedBoundedOutbox(
      (0..<2).map { boundedMutation(index: $0, prefix: "authorized-head") },
      to: runtime.persistence
    )
    let claim = try await runtime.persistence.claimAutomaticOutboxDeliveryWindow(
      InstantAutomaticOutboxClaimRequest(
        claimantID: "authorized-head-runtime",
        claimToken: "authorized-head-token",
        now: InstantTimestamp(milliseconds: 10_000),
        maximumMutationCount: 2
      )
    )
    expectNoDifference(claim.mutations.map(\.id), preparedHeads.map(\.id))
    for head in preparedHeads {
      let revision = try await runtime.persistence.currentOutboxRevision()
      let acceptanceValue = try await runtime.persistence.acceptOutboxMutation(
        id: head.id,
        serverTransactionID: "server-\(head.id)",
        claimantID: "authorized-head-runtime",
        claimToken: "authorized-head-token",
        expectedOutboxRevision: revision
      )
      let acceptance = try #require(acceptanceValue)
      expectNoDifference(acceptance.didChange, true)
      expectNoDifference(acceptance.mutation?.status, .confirmed)
      #expect(
        try boundedOutboxServerAcceptanceFingerprint(id: head.id, cacheURL: cacheURL)
          != nil
      )
    }
    let preparedTail = try await appendRuntimePreparedBoundedOutbox(
      [boundedMutation(index: 2, prefix: "authorized-tail")],
      to: runtime.persistence
    )
    let tail = try #require(preparedTail.first)
    await runtime.persistence.resetDecodedOutboxBodyCount()

    _ = try await runtime.connect()
    try await instantLiveWithTimeout(
      operation: "wait for pending tail behind SQLite-authorized accepted heads",
      timeoutMilliseconds: 5_000
    ) {
      await liveSession.waitForSentMessageCount(2)
    }

    let sentMutationIDs = await liveSession.sentMessages()
      .filter { $0.op == "transact" }
      .compactMap(\.clientEventID)
    expectNoDifference(sentMutationIDs, [tail.id], boundedOutboxSource)
    let acceptedRevision = try await runtime.persistence.currentOutboxRevision()
    let durableHeads = try #require(
      try await runtime.persistence.loadOutboxMutations(
        statuses: [.confirmed],
        ids: preparedHeads.map(\.id),
        limit: preparedHeads.count,
        expectedOutboxRevision: acceptedRevision
      )
    )
    for head in preparedHeads {
      let durableHead = try #require(
        durableHeads.first { $0.id == head.id }
      )
      expectNoDifference(durableHead.status, .confirmed)
    }
    let tailRevision = try await runtime.persistence.currentOutboxRevision()
    let durableTail = try #require(
      try await runtime.persistence.loadOutboxMutations(
        statuses: [.pending],
        ids: [tail.id],
        limit: 1,
        expectedOutboxRevision: tailRevision
      )?.first
    )
    expectNoDifference(durableTail.status, .pending)
    _ = try? await runtime.closeConnection()
  }

  @Test
  func inFlightRowsDoNotConsumeTheNextDurableSelectionWindow() async throws {
    let cacheURL = try temporaryBoundedOutboxCacheURL()
    let liveSession = LiveReactorParitySession(messages: [
      liveReactorInitOK(attrs: liveReactorTodoServerAttrs)
    ])
    let runtime = try await connectedRuntime(
      appID: "bounded-outbox-in-flight",
      cacheURL: cacheURL,
      liveSession: liveSession
    )
    _ = try await appendRuntimePreparedBoundedOutbox(
      (0..<51).map { boundedMutation(index: $0, prefix: "in-flight") },
      to: runtime.persistence
    )

    await runtime.requestLiveMutationDelivery()
    try await instantLiveWithTimeout(
      operation: "wait for initial fifty-mutation window",
      timeoutMilliseconds: 5_000
    ) {
      await liveSession.waitForSentMessageCount(51)
    }
    await runtime.persistence.resetDecodedOutboxBodyCount()
    let sentWithoutFreedCapacity = await runtime.sendOutstandingMutationsToLiveSession()
    #expect(sentWithoutFreedCapacity)
    let fullWindowDecodeCount = await runtime.persistence.currentDecodedOutboxBodyCount()
    expectNoDifference(
      fullWindowDecodeCount,
      0,
      "A full in-flight window must not decode any additional durable bodies."
    )
    await liveSession.enqueue(
      InstantLiveMessage(
        op: "transact-ok",
        clientEventID: "tx-in-flight-00000",
        fields: ["tx-id": .string("server-in-flight-00000")]
      )
    )
    try await instantLiveWithTimeout(
      operation: "wait for one freed slot to admit the unsent tail",
      timeoutMilliseconds: 5_000
    ) {
      await liveSession.waitForSentMessageCount(52)
    }

    let sentMutationIDs = await liveSession.sentMessages()
      .filter { $0.op == "transact" }
      .compactMap(\.clientEventID)
    expectNoDifference(sentMutationIDs.last, "tx-in-flight-00050", boundedOutboxSource)
    let decodedBodyCount = await runtime.persistence.currentDecodedOutboxBodyCount()
    expectNoDifference(
      decodedBodyCount,
      2,
      "The acknowledgement decodes one row and the refill decodes only the one unsent row."
    )
    _ = try? await runtime.closeConnection()
  }

  @Test
  func sameKeySuccessorBeyondFiftyRowBoundaryPreservesOlderVisibleWrite() async throws {
    let cacheURL = try temporaryBoundedOutboxCacheURL()
    let liveSession = LiveReactorParitySession(messages: [
      liveReactorInitOK(attrs: liveReactorTodoServerAttrs)
    ])
    var configuration = InstantRuntimeConfiguration(
      appID: "bounded-outbox-write-key-boundary",
      persistenceURL: cacheURL,
      initialAttributes: TodoExample.attributes,
      liveTransport: liveSession.transport
    )
    configuration.autoConnectLiveTransport = false
    let runtime = try await InstantRuntime.bootstrap(configuration: configuration)
    for index in 0..<51 {
      let mutation = boundedMutation(
        index: index,
        prefix: "write-key-boundary",
        entityID: "todo-shared-write-key"
      )
      try await runtime.transact(
        mutation.transaction,
        createdAt: mutation.createdAt
      )
    }
    await runtime.persistence.resetDecodedOutboxBodyCount()

    _ = try await runtime.connect()
    try await instantLiveWithTimeout(
      operation: "wait for the fifty-mutation same-key boundary window",
      timeoutMilliseconds: 5_000
    ) {
      await liveSession.waitForSentMessageCount(51)
    }
    let sent = await liveSession.sentMessages().filter { $0.op == "transact" }
    expectNoDifference(sent.count, 50, boundedOutboxSource)
    let boundary = try #require(sent.last)
    expectNoDifference(boundary.clientEventID, "tx-write-key-boundary-00049")
    #expect(
      boundary.fields["tx-steps"]?.arrayValue?.isEmpty == false,
      "The older write at the admitted-window boundary must remain because a same-key successor is durably queued just beyond it."
    )
    let decodedBodyCount = await runtime.persistence.currentDecodedOutboxBodyCount()
    expectNoDifference(
      decodedBodyCount,
      50,
      boundedOutboxSource
    )
    _ = try? await runtime.closeConnection()
  }

  @Test
  func failedActiveOverlaySuccessorPreservesOlderAutomaticWrite() async throws {
    let cacheURL = try temporaryBoundedOutboxCacheURL()
    let liveSession = LiveReactorParitySession(messages: [
      liveReactorInitOK(attrs: liveReactorTodoServerAttrs)
    ])
    var configuration = InstantRuntimeConfiguration(
      appID: "bounded-outbox-failed-active-successor",
      persistenceURL: cacheURL,
      initialAttributes: TodoExample.attributes,
      liveTransport: liveSession.transport
    )
    configuration.autoConnectLiveTransport = false
    let runtime = try await InstantRuntime.bootstrap(configuration: configuration)
    let older = boundedMutation(
      index: 0,
      prefix: "failed-active-successor",
      entityID: "failed-active-shared-entity"
    )
    let newer = boundedMutation(
      index: 1,
      prefix: "failed-active-successor",
      entityID: "failed-active-shared-entity"
    )
    _ = try await runtime.transact(older.transaction, createdAt: older.createdAt)
    _ = try await runtime.transact(newer.transaction, createdAt: newer.createdAt)

    let revision = try await runtime.persistence.currentOutboxRevision()
    var durable = try #require(
      try await runtime.persistence.loadOutboxMutations(
        statuses: [.pending, .confirmed, .failed],
        expectedOutboxRevision: revision
      )
    )
    let newerIndex = try #require(durable.firstIndex { $0.id == newer.id })
    durable[newerIndex].status = .failed
    durable[newerIndex].failureMessage = "permission denied"
    durable[newerIndex].failure = InstantMutationFailure(
      code: .permissionRejected,
      message: "permission denied"
    )
    durable[newerIndex].optimisticOverlayState = .applied
    try await runtime.persistence.saveOutbox(durable)

    _ = try await runtime.connect()
    try await instantLiveWithTimeout(
      operation: "wait for the older write protected by a failed active overlay",
      timeoutMilliseconds: 5_000
    ) {
      await liveSession.waitForSentMessageCount(2)
    }
    let sent = try #require(
      await liveSession.sentMessages().first {
        $0.op == "transact" && $0.clientEventID == older.id
      }
    )
    #expect(
      sent.fields["tx-steps"]?.arrayValue?.isEmpty == false,
      "A newer failed mutation whose optimistic overlay is still visible must preserve the older same-key wire write."
    )
    _ = try? await runtime.closeConnection()
  }

  @Test
  func corruptActiveOverlayInsideWindowCommitsBlockerAndReleasesOnlyNewClaims()
    async throws
  {
    let cacheURL = try temporaryBoundedOutboxCacheURL()
    let persistence = try SQLitePersistenceStore(fileURL: cacheURL)
    try await persistence.bootstrap()
    let prepared = try await appendRuntimePreparedBoundedOutbox(
      (0..<5).map { boundedMutation(index: $0, prefix: "corrupt-active-window") },
      to: persistence
    )
    let olderClaim = prepared[0]
    let previouslyOfferedNewClaim = prepared[1]
    let neverOfferedNewClaim = prepared[2]
    let corrupt = prepared[3]
    let untouchedTail = prepared[4]
    let claimantID = "corrupt-active-window-runtime"
    let didClaimOlder = try await persistence.claimOutboxMutationWithoutHydrationForTesting(
      id: olderClaim.id,
      claimantID: claimantID,
      claimToken: "older-claim-token",
      deadlineMilliseconds: 20_000
    )
    expectNoDifference(didClaimOlder, true)
    try executeBoundedOutboxSQL(
      """
      UPDATE instant_outbox
      SET delivery_started = 1
      WHERE mutation_id = '\(previouslyOfferedNewClaim.id)';
      """,
      cacheURL: cacheURL
    )
    try corruptBoundedOutboxBody(id: corrupt.id, cacheURL: cacheURL)
    await persistence.invalidateMemoryCache()
    await persistence.resetDecodedOutboxBodyCount()
    let outboxRevisionBeforeClaim = try await persistence.currentOutboxRevision()

    try await withKnownIssue {
      do {
        _ = try await persistence.claimAutomaticOutboxDeliveryWindow(
          InstantAutomaticOutboxClaimRequest(
            claimantID: claimantID,
            claimToken: "new-claim-token",
            now: InstantTimestamp(milliseconds: 10_000)
          )
        )
        Issue.record("A newly quarantined active row must block the whole claim window.")
      } catch let error as InstantError {
        expectNoDifference(error.code, .persistenceFailed)
        expectNoDifference(error.operation, "claim automatic outbox delivery")
        expectNoDifference(error.localID, corrupt.id)
        expectNoDifference(error.localMutationDisposition, .retainedUnknown)
        #expect(error.message.contains("Synchronization is blocked by 1 retained mutation."))
      }
    } matching: { issue in
      issue.description.contains("quarantined corrupt durable mutation")
    }

    let outboxRevisionAfterClaim = try await persistence.currentOutboxRevision()
    expectNoDifference(
      outboxRevisionAfterClaim,
      outboxRevisionBeforeClaim + 1,
      "The quarantine and claim rollback commit as one outbox revision."
    )
    let blockerValue = try await persistence.synchronizationBlocker()
    let blocker = try #require(blockerValue)
    expectNoDifference(blocker.firstMutationID, corrupt.id)
    expectNoDifference(blocker.blockedMutationCount, 1)
    let olderClaimStateValue = try await persistence.outboxDeliveryClaimForTesting(
      id: olderClaim.id
    )
    let olderClaimState = try #require(olderClaimStateValue)
    expectNoDifference(olderClaimState.state, .claimed)
    expectNoDifference(olderClaimState.claimToken, "older-claim-token")
    expectNoDifference(olderClaimState.deliveryStarted, true)
    for (mutation, expectedDeliveryStarted) in [
      (previouslyOfferedNewClaim, true),
      (neverOfferedNewClaim, false),
    ] {
      let claimValue = try await persistence.outboxDeliveryClaimForTesting(
        id: mutation.id
      )
      let claim = try #require(claimValue)
      expectNoDifference(claim.state, .ready)
      expectNoDifference(claim.claimToken, nil)
      expectNoDifference(
        claim.deliveryStarted,
        expectedDeliveryStarted,
        "The aborted window must restore the exact preclaim offer bit for '\(mutation.id)'."
      )
    }
    let tailClaimValue = try await persistence.outboxDeliveryClaimForTesting(
      id: untouchedTail.id
    )
    let tailClaim = try #require(tailClaimValue)
    expectNoDifference(tailClaim.state, .ready)
    expectNoDifference(tailClaim.claimToken, nil)
    expectNoDifference(tailClaim.deliveryStarted, false)
    let corruptClaimValue = try await persistence.outboxDeliveryClaimForTesting(
      id: corrupt.id
    )
    let corruptClaim = try #require(corruptClaimValue)
    expectNoDifference(corruptClaim.state, .ready)
    expectNoDifference(corruptClaim.claimToken, nil)
    expectNoDifference(corruptClaim.deliveryStarted, false)
    let decodedBodyCount = await persistence.currentDecodedOutboxBodyCount()
    expectNoDifference(
      decodedBodyCount,
      3,
      "The untouched tail must not be decoded after quarantine creates the blocker."
    )
    let quarantinedBody = try await persistence.quarantinedOutboxBodyForTesting(
      id: corrupt.id
    )
    expectNoDifference(quarantinedBody, "{malformed-json")
  }

  @Test
  func publicTransportProjectionPreservesWriteAcrossCorruptActiveSuccessor()
    async throws
  {
    let cacheURL = try temporaryBoundedOutboxCacheURL()
    var configuration = InstantRuntimeConfiguration(
      appID: "bounded-outbox-public-corrupt-successor",
      persistenceURL: cacheURL,
      initialAttributes: TodoExample.attributes
    )
    configuration.autoConnectLiveTransport = false
    let runtime = try await InstantRuntime.bootstrap(configuration: configuration)
    let older = boundedMutation(
      index: 0,
      prefix: "public-corrupt-successor",
      entityID: "public-corrupt-shared-entity"
    )
    let corruptSuccessor = boundedMutation(
      index: 1,
      prefix: "public-corrupt-successor",
      entityID: "public-corrupt-shared-entity"
    )
    _ = try await runtime.transact(older.transaction, createdAt: older.createdAt)
    _ = try await runtime.transact(
      corruptSuccessor.transaction,
      createdAt: corruptSuccessor.createdAt
    )
    try corruptBoundedOutboxBody(id: corruptSuccessor.id, cacheURL: cacheURL)

    try await withKnownIssue {
      let transport = await runtime.outboxTransportMutations()
      let projectedOlder = try #require(transport.first { $0.mutationID == older.id })
      #expect(
        !projectedOlder.txSteps.isEmpty,
        "Public inspection must return the older raw wire write when a newer visible overlay cannot be decoded."
      )
    } matching: { issue in
      issue.description.contains("quarantined corrupt durable mutation")
    }
  }

  @Test
  func automaticDeliveryKeepsMutationAndStepBudgets() async throws {
    let cacheURL = try temporaryBoundedOutboxCacheURL()
    let liveSession = LiveReactorParitySession(messages: [
      liveReactorInitOK(attrs: liveReactorTodoServerAttrs)
    ])
    let runtime = try await connectedRuntime(
      appID: "bounded-outbox-step-budget",
      cacheURL: cacheURL,
      liveSession: liveSession
    )
    _ = try await appendRuntimePreparedBoundedOutbox(
      (0..<30).map { boundedMutation(index: $0, prefix: "step-budget", stepCount: 10) },
      to: runtime.persistence
    )

    await runtime.requestLiveMutationDelivery()
    try await instantLiveWithTimeout(
      operation: "wait for weighted automatic delivery window",
      timeoutMilliseconds: 5_000
    ) {
      await liveSession.waitForSentMessageCount(26)
    }

    let sent = await liveSession.sentMessages().filter { $0.op == "transact" }
    #expect(sent.count <= 50)
    let sentStepCount = sent.reduce(into: 0) { count, message in
      count += message.fields["tx-steps"]?.arrayValue?.count ?? 0
    }
    #expect(sentStepCount <= 256, "Automatic delivery admitted \(sentStepCount) steps.")
    expectNoDifference(sent.count, 25, boundedOutboxSource)
    let lastAdmittedDeliveryStarted = try await runtime.persistence
      .outboxDeliveryStartedForTesting(id: "tx-step-budget-00024")
    let firstUnsentDeliveryStarted = try await runtime.persistence
      .outboxDeliveryStartedForTesting(id: "tx-step-budget-00025")
    let tailDeliveryStarted = try await runtime.persistence
      .outboxDeliveryStartedForTesting(id: "tx-step-budget-00029")
    expectNoDifference(lastAdmittedDeliveryStarted, true, boundedOutboxSource)
    expectNoDifference(
      firstUnsentDeliveryStarted,
      false,
      "A row stopped by the step budget has never been offered."
    )
    expectNoDifference(
      tailDeliveryStarted,
      false,
      "Rows beyond the step-budget boundary remain eligible for never-offered supersession."
    )
    _ = try? await runtime.closeConnection()
  }

  @Test
  func overLimitStepHeadCommitsBlockerWithoutClaimingTail() async throws {
    let cacheURL = try temporaryBoundedOutboxCacheURL()
    let persistence = try SQLitePersistenceStore(fileURL: cacheURL)
    try await persistence.bootstrap()
    let prepared = try await appendRuntimePreparedBoundedOutbox(
      [
        boundedMutation(
          index: 0,
          prefix: "hard-step-limit",
          stepCount: InstantAutomaticOutboxClaimLimits.maximumStepCount + 1
        ),
        boundedMutation(index: 1, prefix: "hard-step-limit"),
      ],
      to: persistence
    )
    await persistence.resetDecodedOutboxBodyCount()

    try await withKnownIssue {
      do {
        _ = try await persistence.claimAutomaticOutboxDeliveryWindow(
          InstantAutomaticOutboxClaimRequest(
            claimantID: "hard-step-limit-runtime",
            claimToken: "hard-step-limit-token",
            now: InstantTimestamp(milliseconds: 10_000)
          )
        )
        Issue.record("An over-limit active head must become a synchronization blocker.")
      } catch let error as InstantError {
        expectNoDifference(error.code, .persistenceFailed)
        expectNoDifference(error.operation, "claim automatic outbox delivery")
        expectNoDifference(error.localID, prepared[0].id)
        expectNoDifference(error.localMutationDisposition, .retainedUnknown)
      }
    } matching: { issue in
      issue.description.contains(
        "257 transport steps exceeds the 256-step automatic-delivery limit"
      )
    }

    let decodedBodyCount = await persistence.currentDecodedOutboxBodyCount()
    expectNoDifference(
      decodedBodyCount,
      0,
      "Normalized step metadata quarantines the head before either durable body is decoded."
    )
    let tailClaimValue = try await persistence.outboxDeliveryClaimForTesting(
      id: prepared[1].id
    )
    let tailClaim = try #require(tailClaimValue)
    expectNoDifference(tailClaim.state, .ready)
    expectNoDifference(tailClaim.claimToken, nil)
    expectNoDifference(tailClaim.deliveryStarted, false)
    let blockerValue = try await persistence.synchronizationBlocker()
    let blocker = try #require(blockerValue)
    expectNoDifference(blocker.firstMutationID, prepared[0].id)
    expectNoDifference(blocker.blockedMutationCount, 1)
  }

  @Test
  func newOverLimitStepMutationFailsBeforeLocalCommitAndNextWriteDelivers() async throws {
    let cacheURL = try temporaryBoundedOutboxCacheURL()
    let liveSession = LiveReactorParitySession(messages: [
      liveReactorInitOK(attrs: liveReactorTodoServerAttrs)
    ])
    let runtime = try await connectedRuntime(
      appID: "bounded-outbox-reject-new-step-oversize",
      cacheURL: cacheURL,
      liveSession: liveSession
    )
    let oversized = boundedMutation(
      index: 0,
      prefix: "reject-new-step-oversize",
      stepCount: InstantAutomaticOutboxClaimLimits.maximumStepCount + 1
    )
    do {
      _ = try await runtime.transact(oversized.transaction, createdAt: oversized.createdAt)
      Issue.record("Expected a new 257-step mutation to fail before local commit.")
    } catch let error as InstantError {
      expectNoDifference(error.code, .validationFailed)
      #expect(error.message.contains("257 transport steps"))
    }
    let triplesAfterRejectedWrite = await runtime.store.snapshot().triples
    let outboxCountAfterRejectedWrite = try await runtime.persistence.countOutboxMutations()
    expectNoDifference(triplesAfterRejectedWrite, [])
    expectNoDifference(outboxCountAfterRejectedWrite, 0)

    let valid = boundedMutation(index: 1, prefix: "reject-new-step-oversize")
    _ = try await runtime.transact(valid.transaction, createdAt: valid.createdAt)
    try await instantLiveWithTimeout(
      operation: "wait for valid write after rejected step-oversize write",
      timeoutMilliseconds: 5_000
    ) {
      await liveSession.waitForSentMessageCount(2)
    }
    let sentIDs = await liveSession.sentMessages()
      .filter { $0.op == "transact" }
      .compactMap(\.clientEventID)
    expectNoDifference(sentIDs, [valid.id])
    _ = try? await runtime.closeConnection()
  }

  @Test
  func newOversizedBodyMutationFailsBeforeLocalCommitAndNextWriteDelivers() async throws {
    let cacheURL = try temporaryBoundedOutboxCacheURL()
    let liveSession = LiveReactorParitySession(messages: [
      liveReactorInitOK(attrs: liveReactorTodoServerAttrs)
    ])
    let runtime = try await connectedRuntime(
      appID: "bounded-outbox-reject-new-body-oversize",
      cacheURL: cacheURL,
      liveSession: liveSession
    )
    let oversized = boundedLargeMutation(
      index: 0,
      prefix: "reject-new-body-oversize",
      valueByteCount: InstantAutomaticOutboxClaimLimits.maximumEncodedBodyBytes + 1_024
    )
    do {
      _ = try await runtime.transact(oversized.transaction, createdAt: oversized.createdAt)
      Issue.record("Expected a new oversized durable mutation body to fail before local commit.")
    } catch let error as InstantError {
      expectNoDifference(error.code, .validationFailed)
      #expect(error.message.contains("8388608-byte durable delivery limit"))
    }
    let triplesAfterRejectedWrite = await runtime.store.snapshot().triples
    let outboxCountAfterRejectedWrite = try await runtime.persistence.countOutboxMutations()
    expectNoDifference(triplesAfterRejectedWrite, [])
    expectNoDifference(outboxCountAfterRejectedWrite, 0)

    let valid = boundedMutation(index: 1, prefix: "reject-new-body-oversize")
    _ = try await runtime.transact(valid.transaction, createdAt: valid.createdAt)
    try await instantLiveWithTimeout(
      operation: "wait for valid write after rejected body-oversize write",
      timeoutMilliseconds: 5_000
    ) {
      await liveSession.waitForSentMessageCount(2)
    }
    let sentIDs = await liveSession.sentMessages()
      .filter { $0.op == "transact" }
      .compactMap(\.clientEventID)
    expectNoDifference(sentIDs, [valid.id])
    _ = try? await runtime.closeConnection()
  }

  @Test
  func legacySameKeyStepBlockerRemainsSuccessorProofAndNeverOffered() async throws {
    let cacheURL = try temporaryBoundedOutboxCacheURL()
    let liveSession = LiveReactorParitySession(messages: [
      liveReactorInitOK(attrs: liveReactorTodoServerAttrs)
    ])
    let runtime = try await disconnectedRuntime(
      appID: "bounded-outbox-legacy-step-blocker",
      cacheURL: cacheURL,
      liveSession: liveSession
    )
    _ = try await appendRuntimePreparedBoundedOutbox([
      boundedMutation(
        index: 0,
        prefix: "legacy-step-blocker",
        entityID: "shared-step-blocker",
        stepCount: 250
      ),
      boundedMutation(
        index: 1,
        prefix: "legacy-step-blocker",
        entityID: "shared-step-blocker",
        stepCount: 10
      ),
    ], to: runtime.persistence)
    try clearBoundedDeliveryMetadata(
      id: "tx-legacy-step-blocker-00001",
      cacheURL: cacheURL
    )
    await runtime.persistence.invalidateMemoryCache()

    _ = try await runtime.connect()
    try await instantLiveWithTimeout(
      operation: "wait for first mutation before legacy step blocker",
      timeoutMilliseconds: 5_000
    ) {
      await liveSession.waitForSentMessageCount(2)
    }

    let sent = try #require(
      await liveSession.sentMessages().first { $0.op == "transact" }
    )
    let blockerDeliveryStarted = try await runtime.persistence
      .outboxDeliveryStartedForTesting(id: "tx-legacy-step-blocker-00001")
    expectNoDifference(sent.clientEventID, "tx-legacy-step-blocker-00000")
    #expect(sent.fields["tx-steps"]?.arrayValue?.isEmpty == false)
    expectNoDifference(
      blockerDeliveryStarted,
      false,
      "A decoded row stopped by the remaining step budget is normalized but not offered."
    )
    _ = try? await runtime.closeConnection()
  }

  @Test
  func automaticDeliveryHydratesRequiredFoundationAndFiltersOptionalStaleWrite()
    async throws
  {
    let cacheURL = try temporaryBoundedOutboxCacheURL()
    let liveSession = LiveReactorParitySession(messages: [
      liveReactorInitOK(attrs: liveReactorServerAttrs(from: requiredFoundationAttributes))
    ])
    var configuration = InstantRuntimeConfiguration(
      appID: "bounded-outbox-required-foundation",
      persistenceURL: cacheURL,
      initialAttributes: requiredFoundationAttributes,
      liveTransport: liveSession.transport
    )
    configuration.autoConnectLiveTransport = false
    let runtime = try await InstantRuntime.bootstrap(configuration: configuration)
    let mutation = requiredFoundationMutation(
      id: "tx-required-foundation-older",
      entityID: "segment-required-foundation",
      text: "older text must not overwrite the visible value",
      optionalPreview: "older preview must be filtered",
      recordingID: "recording-required-foundation",
      createdAt: InstantTimestamp(milliseconds: 100)
    )
    try await saveRuntimeAuthorizedBoundedOutboxBodies(
      [mutation],
      to: runtime.persistence
    )

    let visibleAt = InstantTimestamp(milliseconds: 200)
    let otherRuntimePersistence = try SQLitePersistenceStore(fileURL: cacheURL)
    try await otherRuntimePersistence.bootstrap()
    try await saveRuntimePreparedBoundedStoreSnapshot(
      InstantStoreSnapshot(
        attributes: requiredFoundationAttributes,
        triples: [
          requiredFoundationTriple(
            entityID: "segment-required-foundation",
            attributeID: "transcriptionSegments/id",
            value: .string("segment-required-foundation"),
            transactionID: mutation.id,
            timestamp: mutation.createdAt
          ),
          requiredFoundationTriple(
            entityID: "segment-required-foundation",
            attributeID: "transcriptionSegments/recording",
            value: .ref("recording-required-foundation"),
            transactionID: mutation.id,
            timestamp: mutation.createdAt
          ),
          requiredFoundationTriple(
            entityID: "segment-required-foundation",
            attributeID: "transcriptionSegments/text",
            value: .string("newest materialized text"),
            transactionID: "newer-visible-write",
            timestamp: visibleAt
          ),
          requiredFoundationTriple(
            entityID: "segment-required-foundation",
            attributeID: "transcriptionSegments/searchPreview",
            value: .string("newest optional preview"),
            transactionID: "newer-visible-write",
            timestamp: visibleAt
          ),
        ]
      ),
      to: otherRuntimePersistence
    )

    _ = try await runtime.connect()
    try await instantLiveWithTimeout(
      operation: "wait for schema-complete required-foundation delivery",
      timeoutMilliseconds: 5_000
    ) {
      await liveSession.waitForSentMessageCount(2)
    }
    let sent = try #require(
      await liveSession.sentMessages().first { $0.op == "transact" }
    )
    let valuesByAttributeID = boundedOutboxAddTripleValues(in: sent)

    expectNoDifference(sent.clientEventID, mutation.id)
    expectNoDifference(
      valuesByAttributeID,
      [
        "transcriptionSegments/id": .string("segment-required-foundation"),
        "transcriptionSegments/recording": .string("recording-required-foundation"),
        "transcriptionSegments/text": .string("newest materialized text"),
      ],
      "The relation-bearing wire mutation must carry the newest required scalar without reviving an optional stale field."
    )
    _ = try? await runtime.closeConnection()
    await otherRuntimePersistence.simulateUnexpectedConnectionCloseForTesting()
  }

  @Test
  func automaticDeliveryFailsOversizedRequiredHydrationAndSendsSmallTail()
    async throws
  {
    let cacheURL = try temporaryBoundedOutboxCacheURL()
    let liveSession = LiveReactorParitySession(messages: [
      liveReactorInitOK(attrs: liveReactorServerAttrs(from: requiredFoundationAttributes))
    ])
    var configuration = InstantRuntimeConfiguration(
      appID: "bounded-outbox-required-foundation-projected-oversize",
      persistenceURL: cacheURL,
      initialAttributes: requiredFoundationAttributes,
      liveTransport: liveSession.transport
    )
    configuration.autoConnectLiveTransport = false
    let runtime = try await InstantRuntime.bootstrap(configuration: configuration)
    let oversizedHead = requiredFoundationMutation(
      id: "tx-required-foundation-projected-oversize",
      entityID: "segment-required-foundation-projected-oversize",
      text: "tiny persisted text",
      optionalPreview: nil,
      recordingID: "recording-required-foundation-projected-oversize",
      createdAt: InstantTimestamp(milliseconds: 100)
    )
    let smallTail = requiredFoundationMutation(
      id: "tx-required-foundation-projected-small-tail",
      entityID: "segment-required-foundation-projected-small-tail",
      text: "small tail text",
      optionalPreview: nil,
      recordingID: "recording-required-foundation-projected-small-tail",
      createdAt: InstantTimestamp(milliseconds: 300)
    )
    try await saveRuntimeAuthorizedBoundedOutboxBodies(
      [oversizedHead, smallTail],
      to: runtime.persistence
    )

    let oversizedAuthoritativeText = String(
      repeating: "x",
      count: InstantAutomaticOutboxClaimLimits.maximumEncodedBodyBytes + 1_024
    )
    try await saveRuntimePreparedBoundedStoreSnapshot(
      InstantStoreSnapshot(
        attributes: requiredFoundationAttributes,
        triples: [
          requiredFoundationTriple(
            entityID: "segment-required-foundation-projected-oversize",
            attributeID: "transcriptionSegments/text",
            value: .string(oversizedAuthoritativeText),
            transactionID: "authoritative-required-foundation-projected-oversize",
            timestamp: InstantTimestamp(milliseconds: 200)
          )
        ]
      ),
      to: runtime.persistence
    )

    await runtime.persistence.resetVisibleRequiredScalarDecodeMetricsForTesting()
    _ = try await runtime.connect()
    try await instantLiveWithTimeout(
      operation: "wait for small tail behind projected-oversize required hydration",
      timeoutMilliseconds: 5_000
    ) {
      await liveSession.waitForSentMessageCount(2)
    }

    let sentMutationIDs = await liveSession.sentMessages()
      .filter { $0.op == "transact" }
      .compactMap(\.clientEventID)
    let failedHead = try #require(
      await runtime.failedMutations().first { $0.id == oversizedHead.id }
    )
    let headClaim = try #require(
      try await runtime.persistence.outboxDeliveryClaimForTesting(id: oversizedHead.id)
    )
    let decodedRequiredScalarCount =
      await runtime.persistence.decodedVisibleRequiredScalarCountForTesting()
    let decodedRequiredScalarValueByteCount =
      await runtime.persistence.decodedVisibleRequiredScalarValueByteCountForTesting()
    let materializedText = try #require(
      try await runtime.persistence.loadSnapshot().store.triples.first {
        $0.entityID == "segment-required-foundation-projected-oversize"
          && $0.attributeID == "transcriptionSegments/text"
      }
    )

    expectNoDifference(sentMutationIDs, [smallTail.id])
    expectNoDifference(failedHead.failure?.code, .validationFailed)
    #expect(failedHead.failureMessage?.contains("projected pending body") == true)
    #expect(
      failedHead.failureMessage?.contains(
        "\(InstantAutomaticOutboxClaimLimits.maximumEncodedBodyBytes)-byte"
      ) == true
    )
    expectNoDifference(headClaim.state, .ready)
    expectNoDifference(headClaim.claimToken, nil)
    expectNoDifference(headClaim.projectedBodyByteCount, nil)
    expectNoDifference(
      decodedRequiredScalarCount,
      0,
      "An individually oversized projected row must fail from SQLite value-length metadata before decoding the authoritative value."
    )
    expectNoDifference(decodedRequiredScalarValueByteCount, 0)
    expectNoDifference(materializedText.value, .string(oversizedAuthoritativeText))

    let repeatedPumpCompleted = await runtime.sendOutstandingMutationsToLiveSession()
    #expect(repeatedPumpCompleted)
    let repeatedSentMutationIDs = await liveSession.sentMessages()
      .filter { $0.op == "transact" }
      .compactMap(\.clientEventID)
    expectNoDifference(repeatedSentMutationIDs, [smallTail.id])
    _ = try? await runtime.closeConnection()
  }

  @Test
  func automaticDeliveryDefersSecondFiveMiBRequiredHydrationUntilCapacityReleases()
    async throws
  {
    let cacheURL = try temporaryBoundedOutboxCacheURL()
    let liveSession = LiveReactorParitySession(messages: [
      liveReactorInitOK(attrs: liveReactorServerAttrs(from: requiredFoundationAttributes))
    ])
    var configuration = InstantRuntimeConfiguration(
      appID: "bounded-outbox-required-foundation-projected-window",
      persistenceURL: cacheURL,
      initialAttributes: requiredFoundationAttributes,
      liveTransport: liveSession.transport
    )
    configuration.autoConnectLiveTransport = false
    let runtime = try await InstantRuntime.bootstrap(configuration: configuration)
    let first = requiredFoundationMutation(
      id: "tx-required-foundation-projected-window-first",
      entityID: "segment-required-foundation-projected-window-first",
      text: "tiny first persisted text",
      optionalPreview: nil,
      recordingID: "recording-required-foundation-projected-window-first",
      createdAt: InstantTimestamp(milliseconds: 100)
    )
    let second = requiredFoundationMutation(
      id: "tx-required-foundation-projected-window-second",
      entityID: "segment-required-foundation-projected-window-second",
      text: "tiny second persisted text",
      optionalPreview: nil,
      recordingID: "recording-required-foundation-projected-window-second",
      createdAt: InstantTimestamp(milliseconds: 200)
    )
    try await saveRuntimeAuthorizedBoundedOutboxBodies(
      [first, second],
      to: runtime.persistence
    )

    let fiveMiBText = String(repeating: "y", count: 5 * 1_024 * 1_024)
    try await saveRuntimePreparedBoundedStoreSnapshot(
      InstantStoreSnapshot(
        attributes: requiredFoundationAttributes,
        triples: [
          requiredFoundationTriple(
            entityID: "segment-required-foundation-projected-window-first",
            attributeID: "transcriptionSegments/text",
            value: .string(fiveMiBText),
            transactionID: "authoritative-required-foundation-projected-window-first",
            timestamp: InstantTimestamp(milliseconds: 300)
          ),
          requiredFoundationTriple(
            entityID: "segment-required-foundation-projected-window-second",
            attributeID: "transcriptionSegments/text",
            value: .string(fiveMiBText),
            transactionID: "authoritative-required-foundation-projected-window-second",
            timestamp: InstantTimestamp(milliseconds: 300)
          ),
        ]
      ),
      to: runtime.persistence
    )

    await runtime.persistence.resetVisibleRequiredScalarDecodeMetricsForTesting()
    _ = try await runtime.connect()
    try await instantLiveWithTimeout(
      operation: "wait for first five-MiB projected mutation",
      timeoutMilliseconds: 5_000
    ) {
      await liveSession.waitForSentMessageCount(2)
    }

    let initiallySentMutationIDs = await liveSession.sentMessages()
      .filter { $0.op == "transact" }
      .compactMap(\.clientEventID)
    let firstClaim = try #require(
      try await runtime.persistence.outboxDeliveryClaimForTesting(id: first.id)
    )
    let deferredClaim = try #require(
      try await runtime.persistence.outboxDeliveryClaimForTesting(id: second.id)
    )
    let initialRequiredScalarDecodeCount =
      await runtime.persistence.decodedVisibleRequiredScalarCountForTesting()
    let initialRequiredScalarValueByteCount =
      await runtime.persistence.decodedVisibleRequiredScalarValueByteCountForTesting()
    expectNoDifference(initiallySentMutationIDs, [first.id])
    expectNoDifference(firstClaim.state, .claimed)
    #expect((firstClaim.projectedBodyByteCount ?? 0) > 5 * 1_024 * 1_024)
    #expect(
      (firstClaim.projectedBodyByteCount ?? .max)
        <= InstantAutomaticOutboxClaimLimits.maximumEncodedBodyBytes
    )
    expectNoDifference(deferredClaim.state, .ready)
    expectNoDifference(deferredClaim.claimToken, nil)
    expectNoDifference(deferredClaim.projectedBodyByteCount, nil)
    expectNoDifference(deferredClaim.deliveryStarted, false)
    expectNoDifference(
      initialRequiredScalarDecodeCount,
      1,
      "The aggregate-overflow suffix must remain metadata-only until the admitted prefix releases capacity."
    )
    #expect(initialRequiredScalarValueByteCount > 5 * 1_024 * 1_024)
    #expect(
      initialRequiredScalarValueByteCount
        <= InstantAutomaticOutboxClaimLimits.maximumEncodedBodyBytes
    )

    await liveSession.enqueue(
      InstantLiveMessage(
        op: "transact-ok",
        clientEventID: first.id,
        fields: ["tx-id": .string("server-required-foundation-projected-window-first")]
      )
    )
    try await instantLiveWithTimeout(
      operation: "wait for deferred five-MiB projection after capacity release",
      timeoutMilliseconds: 5_000
    ) {
      await liveSession.waitForSentMessageCount(3)
    }
    let finallySentMutationIDs = await liveSession.sentMessages()
      .filter { $0.op == "transact" }
      .compactMap(\.clientEventID)
    let finalRequiredScalarDecodeCount =
      await runtime.persistence.decodedVisibleRequiredScalarCountForTesting()
    expectNoDifference(finallySentMutationIDs, [first.id, second.id])
    expectNoDifference(finalRequiredScalarDecodeCount, 2)
    _ = try? await runtime.closeConnection()
  }

  @Test
  func activeSuccessorKeepsOriginalThenNewRequiredFoundationValues() async throws {
    let cacheURL = try temporaryBoundedOutboxCacheURL()
    let liveSession = LiveReactorParitySession(messages: [
      liveReactorInitOK(attrs: liveReactorServerAttrs(from: requiredFoundationAttributes))
    ])
    var configuration = InstantRuntimeConfiguration(
      appID: "bounded-outbox-required-foundation-successor",
      persistenceURL: cacheURL,
      initialAttributes: requiredFoundationAttributes,
      liveTransport: liveSession.transport
    )
    configuration.autoConnectLiveTransport = false
    let runtime = try await InstantRuntime.bootstrap(configuration: configuration)
    let older = requiredFoundationMutation(
      id: "tx-required-foundation-successor-older",
      entityID: "segment-required-foundation-successor",
      text: "older ordered text",
      optionalPreview: nil,
      recordingID: "recording-required-foundation-successor",
      createdAt: InstantTimestamp(milliseconds: 100)
    )
    let newer = requiredFoundationMutation(
      id: "tx-required-foundation-successor-newer",
      entityID: "segment-required-foundation-successor",
      text: "newer ordered text",
      optionalPreview: nil,
      recordingID: nil,
      createdAt: InstantTimestamp(milliseconds: 200)
    )
    _ = try await runtime.transact(older.transaction, createdAt: older.createdAt)
    _ = try await runtime.transact(newer.transaction, createdAt: newer.createdAt)

    _ = try await runtime.connect()
    try await instantLiveWithTimeout(
      operation: "wait for ordered required-foundation successor delivery",
      timeoutMilliseconds: 5_000
    ) {
      await liveSession.waitForSentMessageCount(3)
    }
    let sent = await liveSession.sentMessages().filter { $0.op == "transact" }
    let olderSent = try #require(sent.first { $0.clientEventID == older.id })
    let newerSent = try #require(sent.first { $0.clientEventID == newer.id })

    expectNoDifference(sent.compactMap(\.clientEventID), [older.id, newer.id])
    expectNoDifference(
      boundedOutboxAddTripleValues(in: olderSent)["transcriptionSegments/text"],
      .string("older ordered text"),
      "A pending successor is not authoritative: the predecessor must keep its original required value."
    )
    expectNoDifference(
      boundedOutboxAddTripleValues(in: newerSent)["transcriptionSegments/text"],
      .string("newer ordered text")
    )
    _ = try? await runtime.closeConnection()
  }

  @Test
  func legacyActiveUnconfirmedOverlayCannotHydrateLaterFoundationMutation()
    async throws
  {
    let cacheURL = try temporaryBoundedOutboxCacheURL()
    let liveSession = LiveReactorParitySession(messages: [
      liveReactorInitOK(attrs: liveReactorServerAttrs(from: requiredFoundationAttributes))
    ])
    var configuration = InstantRuntimeConfiguration(
      appID: "bounded-outbox-required-foundation-legacy-overlay",
      persistenceURL: cacheURL,
      initialAttributes: requiredFoundationAttributes,
      liveTransport: liveSession.transport
    )
    configuration.autoConnectLiveTransport = false
    let runtime = try await InstantRuntime.bootstrap(configuration: configuration)
    var activeFailedOverlay = requiredFoundationMutation(
      id: "tx-required-foundation-active-failed-overlay",
      entityID: "segment-required-foundation-active-failed-overlay",
      text: "newer unconfirmed optimistic text",
      optionalPreview: nil,
      recordingID: nil,
      createdAt: InstantTimestamp(milliseconds: 300)
    )
    activeFailedOverlay.createdAt = InstantTimestamp(milliseconds: 100)
    activeFailedOverlay.status = .failed
    activeFailedOverlay.failureMessage = "permission denied"
    activeFailedOverlay.failure = InstantMutationFailure(
      code: .permissionRejected,
      message: "permission denied"
    )
    activeFailedOverlay.optimisticOverlayState = .applied
    let foundation = requiredFoundationMutation(
      id: "tx-required-foundation-after-active-failed-overlay",
      entityID: "segment-required-foundation-active-failed-overlay",
      text: "foundation text",
      optionalPreview: nil,
      recordingID: "recording-required-foundation-active-failed-overlay",
      createdAt: InstantTimestamp(milliseconds: 200)
    )
    activeFailedOverlay.rollbackTransaction = InstantStoreTransaction(
      id: "rollback-\(activeFailedOverlay.id)",
      operations: [
        .insert(
          requiredFoundationTriple(
            entityID: "segment-required-foundation-active-failed-overlay",
            attributeID: "transcriptionSegments/text",
            value: .string("foundation text"),
            transactionID: foundation.id,
            timestamp: foundation.createdAt
          )
        )
      ]
    )
    try await saveRuntimeAuthorizedBoundedOutboxBodies(
      [activeFailedOverlay, foundation],
      to: runtime.persistence
    )
    try await saveRuntimePreparedBoundedStoreSnapshot(
      InstantStoreSnapshot(
        attributes: requiredFoundationAttributes,
        triples: [
          requiredFoundationTriple(
            entityID: "segment-required-foundation-active-failed-overlay",
            attributeID: "transcriptionSegments/id",
            value: .string("segment-required-foundation-active-failed-overlay"),
            transactionID: foundation.id,
            timestamp: foundation.createdAt
          ),
          requiredFoundationTriple(
            entityID: "segment-required-foundation-active-failed-overlay",
            attributeID: "transcriptionSegments/recording",
            value: .ref("recording-required-foundation-active-failed-overlay"),
            transactionID: foundation.id,
            timestamp: foundation.createdAt
          ),
          requiredFoundationTriple(
            entityID: "segment-required-foundation-active-failed-overlay",
            attributeID: "transcriptionSegments/text",
            value: .string("newer unconfirmed optimistic text"),
            transactionID: activeFailedOverlay.id,
            timestamp: InstantTimestamp(milliseconds: 300)
          ),
        ]
      ),
      to: runtime.persistence
    )
    try executeBoundedOutboxSQL(
      """
      UPDATE instant_outbox
      SET confirmation_proven = NULL
      WHERE mutation_id = 'tx-required-foundation-active-failed-overlay';
      """,
      cacheURL: cacheURL
    )
    await runtime.persistence.invalidateMemoryCache()

    _ = try await runtime.connect()
    try await instantLiveWithTimeout(
      operation: "wait for foundation delivery past an active legacy overlay",
      timeoutMilliseconds: 5_000
    ) {
      await liveSession.waitForSentMessageCount(2)
    }
    let sent = try #require(
      await liveSession.sentMessages().first { $0.op == "transact" }
    )
    let materializedText = try #require(
      try await runtime.persistence.loadSnapshot().store.triples.first {
        $0.entityID == "segment-required-foundation-active-failed-overlay"
          && $0.attributeID == "transcriptionSegments/text"
      }
    )

    expectNoDifference(sent.clientEventID, foundation.id)
    expectNoDifference(
      boundedOutboxAddTripleValues(in: sent)["transcriptionSegments/text"],
      .string("foundation text"),
      "An active unconfirmed overlay is locally visible but cannot become authoritative input to an older-id wire body."
    )
    expectNoDifference(
      materializedText.value,
      .string("newer unconfirmed optimistic text"),
      "Filtering wire delivery must not disturb the newer local optimistic value."
    )
    _ = try? await runtime.closeConnection()
  }

  @Test
  func automaticDeliveryUsesRevisionQualifiedDurableVisibleWrites() async throws {
    let cacheURL = try temporaryBoundedOutboxCacheURL()
    let liveSession = LiveReactorParitySession(messages: [
      liveReactorInitOK(attrs: liveReactorTodoServerAttrs)
    ])
    var configuration = InstantRuntimeConfiguration(
      appID: "bounded-outbox-shared-sqlite-visible-write",
      persistenceURL: cacheURL,
      initialAttributes: TodoExample.attributes,
      liveTransport: liveSession.transport
    )
    configuration.autoConnectLiveTransport = false
    let staleRuntime = try await InstantRuntime.bootstrap(configuration: configuration)
    let mutation = boundedMutation(
      index: 0,
      prefix: "shared-sqlite-visible-write",
      entityID: "shared-todo"
    )
    try await saveRuntimeAuthorizedBoundedOutboxBodies(
      [mutation],
      to: staleRuntime.persistence
    )

    let otherRuntimePersistence = try SQLitePersistenceStore(fileURL: cacheURL)
    try await otherRuntimePersistence.bootstrap()
    try await saveRuntimePreparedBoundedStoreSnapshot(
      InstantStoreSnapshot(
        attributes: TodoExample.attributes,
        triples: [
          InstantTriple(
            entityID: "shared-todo",
            attributeID: "todos/text",
            value: .string("newer durable value"),
            txID: "other-runtime-server-write",
            txTime: InstantTimestamp(milliseconds: 10_000)
          )
        ]
      ),
      to: otherRuntimePersistence
    )

    _ = try await staleRuntime.connect()
    try await instantLiveWithTimeout(
      operation: "wait for the revision-qualified durable visible write",
      timeoutMilliseconds: 5_000
    ) {
      await liveSession.waitForSentMessageCount(2)
    }
    let sent = try #require(
      await liveSession.sentMessages().first { $0.op == "transact" }
    )
    expectNoDifference(sent.clientEventID, mutation.id)
    expectNoDifference(
      boundedOutboxAddTripleValues(in: sent),
      ["server-todos-text": .string("newer durable value")],
      "A required scalar must use the revision-qualified durable value instead of disappearing or reviving its stale body value."
    )
    _ = try? await staleRuntime.closeConnection()
    await otherRuntimePersistence.simulateUnexpectedConnectionCloseForTesting()
  }

  @Test
  func automaticDeliveryBoundsEncodedBodyBytesBeforeDecode() async throws {
    let cacheURL = try temporaryBoundedOutboxCacheURL()
    let liveSession = LiveReactorParitySession(messages: [
      liveReactorInitOK(attrs: liveReactorTodoServerAttrs)
    ])
    let runtime = try await connectedRuntime(
      appID: "bounded-outbox-body-bytes",
      cacheURL: cacheURL,
      liveSession: liveSession
    )
    _ = try await appendRuntimePreparedBoundedOutbox(
      (0..<3).map {
        boundedLargeMutation(index: $0, prefix: "body-bytes", valueByteCount: 5 * 1_024 * 1_024)
      },
      to: runtime.persistence
    )
    await runtime.persistence.resetDecodedOutboxBodyCount()

    await runtime.requestLiveMutationDelivery()
    try await instantLiveWithTimeout(
      operation: "wait for byte-bounded automatic delivery",
      timeoutMilliseconds: 5_000
    ) {
      await liveSession.waitForSentMessageCount(2)
    }

    let sentIDs = await liveSession.sentMessages()
      .filter { $0.op == "transact" }
      .compactMap(\.clientEventID)
    expectNoDifference(sentIDs, ["tx-body-bytes-00000"])
    let decodedBodyCount = await runtime.persistence.currentDecodedOutboxBodyCount()
    expectNoDifference(decodedBodyCount, 1)
    let decodedBodyByteCount = await runtime.persistence.currentDecodedOutboxBodyByteCount()
    #expect(decodedBodyByteCount <= InstantAutomaticOutboxClaimLimits.maximumEncodedBodyBytes)
    let secondMutationDeliveryStarted = try await runtime.persistence
      .outboxDeliveryStartedForTesting(id: "tx-body-bytes-00001")
    expectNoDifference(secondMutationDeliveryStarted, false)

    await runtime.persistence.resetDecodedOutboxBodyCount()
    let repeatedPumpCompleted = await runtime.sendOutstandingMutationsToLiveSession()
    let repeatedPumpDecodeCount = await runtime.persistence.currentDecodedOutboxBodyCount()
    let repeatedSentIDs = await liveSession.sentMessages()
      .filter { $0.op == "transact" }
      .compactMap(\.clientEventID)
    #expect(repeatedPumpCompleted)
    expectNoDifference(
      repeatedPumpDecodeCount,
      0,
      "The first 5 MiB durable claim consumes the global byte window; another pump may not decode a second 5 MiB body before ACK or release."
    )
    expectNoDifference(repeatedSentIDs, ["tx-body-bytes-00000"])
    _ = try? await runtime.closeConnection()
  }

  @Test
  func oversizedHeadCommitsBlockerWithoutDecodingOrClaimingTail() async throws {
    let cacheURL = try temporaryBoundedOutboxCacheURL()
    let persistence = try SQLitePersistenceStore(fileURL: cacheURL)
    try await persistence.bootstrap()
    let prepared = try await appendRuntimePreparedBoundedOutbox(
      [
        boundedLargeMutation(
          index: 0,
          prefix: "oversized-head",
          valueByteCount: InstantAutomaticOutboxClaimLimits.maximumEncodedBodyBytes + 1_024
        ),
        boundedMutation(index: 1, prefix: "oversized-head"),
      ],
      to: persistence
    )
    await persistence.resetDecodedOutboxBodyCount()

    try await withKnownIssue {
      do {
        _ = try await persistence.claimAutomaticOutboxDeliveryWindow(
          InstantAutomaticOutboxClaimRequest(
            claimantID: "oversized-head-runtime",
            claimToken: "oversized-head-token",
            now: InstantTimestamp(milliseconds: 10_000)
          )
        )
        Issue.record("An oversized active head must become a synchronization blocker.")
      } catch let error as InstantError {
        expectNoDifference(error.code, .persistenceFailed)
        expectNoDifference(error.operation, "claim automatic outbox delivery")
        expectNoDifference(error.localID, prepared[0].id)
        expectNoDifference(error.localMutationDisposition, .retainedUnknown)
      }
    } matching: { issue in
      issue.description.contains("exceeds the 8388608-byte automatic-delivery limit")
    }

    let decodedBodyCount = await persistence.currentDecodedOutboxBodyCount()
    let decodedBodyBytes = await persistence.currentDecodedOutboxBodyByteCount()
    let quarantinedBodyBytes = try await persistence
      .quarantinedOutboxBodyByteCountForTesting(id: prepared[0].id)
    expectNoDifference(decodedBodyCount, 0)
    expectNoDifference(decodedBodyBytes, 0)
    #expect(quarantinedBodyBytes > InstantAutomaticOutboxClaimLimits.maximumEncodedBodyBytes)
    let tailClaimValue = try await persistence.outboxDeliveryClaimForTesting(
      id: prepared[1].id
    )
    let tailClaim = try #require(tailClaimValue)
    expectNoDifference(tailClaim.state, .ready)
    expectNoDifference(tailClaim.claimToken, nil)
    expectNoDifference(tailClaim.deliveryStarted, false)
    let blockerValue = try await persistence.synchronizationBlocker()
    let blocker = try #require(blockerValue)
    expectNoDifference(blocker.firstMutationID, prepared[0].id)
    expectNoDifference(blocker.blockedMutationCount, 1)
  }

  @Test
  func corruptHeadWindowStopsAtFirstBlockerWithoutDecodingTail() async throws {
    let cacheURL = try temporaryBoundedOutboxCacheURL()
    let persistence = try SQLitePersistenceStore(fileURL: cacheURL)
    try await persistence.bootstrap()
    let prepared = try await appendRuntimePreparedBoundedOutbox(
      (0..<51).map { boundedMutation(index: $0, prefix: "corrupt-head-window") },
      to: persistence
    )
    try corruptBoundedOutboxBodies(
      ids: (0..<50).map { String(format: "tx-corrupt-head-window-%05d", $0) },
      cacheURL: cacheURL
    )
    await persistence.invalidateMemoryCache()
    await persistence.resetDecodedOutboxBodyCount()

    try await withKnownIssue {
      do {
        _ = try await persistence.claimAutomaticOutboxDeliveryWindow(
          InstantAutomaticOutboxClaimRequest(
            claimantID: "corrupt-head-window-runtime",
            claimToken: "corrupt-head-window-token",
            now: InstantTimestamp(milliseconds: 10_000)
          )
        )
        Issue.record("The first corrupt active head must block the claim window.")
      } catch let error as InstantError {
        expectNoDifference(error.code, .persistenceFailed)
        expectNoDifference(error.localID, prepared[0].id)
        expectNoDifference(error.localMutationDisposition, .retainedUnknown)
      }
    } matching: { issue in
      issue.description.contains("quarantined corrupt durable mutation")
    }

    let decodedBodyCount = await persistence.currentDecodedOutboxBodyCount()
    let quarantinedBody = try await persistence.quarantinedOutboxBodyForTesting(
      id: prepared[0].id
    )
    expectNoDifference(quarantinedBody, "{malformed-json")
    expectNoDifference(decodedBodyCount, 1)
    let secondQuarantinedBody = try await persistence.quarantinedOutboxBodyForTesting(
      id: prepared[1].id
    )
    expectNoDifference(
      secondQuarantinedBody,
      nil,
      "Rows after the new blocker remain byte-for-byte repair evidence, not a batch quarantine."
    )
    let tailClaimValue = try await persistence.outboxDeliveryClaimForTesting(
      id: prepared[50].id
    )
    let tailClaim = try #require(tailClaimValue)
    expectNoDifference(tailClaim.state, .ready)
    expectNoDifference(tailClaim.claimToken, nil)
    expectNoDifference(tailClaim.deliveryStarted, false)
    let maximumWindowBodyCount =
      await persistence.maximumAutomaticOutboxWindowBodyCountForTesting()
    #expect(maximumWindowBodyCount <= InstantAutomaticOutboxClaimLimits.maximumBodyDecodeCount)
  }

  @Test
  func malformedLifecycleWithOversizedFailedBodyBlocksConnectAndRetainsTail() async throws {
    let cacheURL = try temporaryBoundedOutboxCacheURL()
    var oversizedFailure = boundedLargeMutation(
      index: 0,
      prefix: "oversized-failed-lifecycle",
      valueByteCount: InstantAutomaticOutboxClaimLimits.maximumEncodedBodyBytes + 1_024
    )
    oversizedFailure.status = .failed
    oversizedFailure.failureMessage = "could not resolve missing deployed attribute"
    oversizedFailure.failure = InstantMutationFailure(
      code: .validationFailed,
      message: oversizedFailure.failureMessage!
    )
    try await seedBoundedOutbox(
      [
        oversizedFailure,
        boundedMutation(index: 1, prefix: "oversized-failed-lifecycle"),
      ],
      cacheURL: cacheURL
    )
    try corruptBoundedOutboxLifecycle(
      id: oversizedFailure.id,
      cacheURL: cacheURL
    )

    let liveSession = LiveReactorParitySession(messages: [
      liveReactorInitOK(attrs: liveReactorTodoServerAttrs)
    ])
    var configuration = InstantRuntimeConfiguration(
      appID: "bounded-outbox-oversized-failed-lifecycle",
      persistenceURL: cacheURL,
      initialAttributes: TodoExample.attributes,
      liveTransport: liveSession.transport
    )
    configuration.autoConnectLiveTransport = false
    let runtime = try await InstantRuntime.bootstrap(configuration: configuration)
    await runtime.persistence.resetDecodedOutboxBodyCount()

    try await withKnownIssue {
      _ = try await runtime.connect()
      _ = try await instantLiveWithTimeout(
        operation: "wait for oversized failed lifecycle blocker",
        timeoutMilliseconds: 5_000
      ) {
        while true {
          let status = try await runtime.connectionStatus()
          if status.state == .errored, status.synchronizationBlocker != nil {
            return status
          }
          try Task.checkCancellation()
          await Task.yield()
        }
      }
    } matching: { issue in
      issue.description.contains("invalid lifecycle metadata")
        || issue.description.contains("exceeds the 8388608-byte automatic-delivery limit")
    }
    let connectionStatus = try await runtime.connectionStatus()

    let sentIDs = await liveSession.sentMessages()
      .filter { $0.op == "transact" }
      .compactMap(\.clientEventID)
    let decodedBodyCount = await runtime.persistence.currentDecodedOutboxBodyCount()
    let decodedBodyBytes = await runtime.persistence.currentDecodedOutboxBodyByteCount()
    expectNoDifference(sentIDs, [])
    expectNoDifference(decodedBodyCount, 0)
    expectNoDifference(decodedBodyBytes, 0)
    let tailClaimValue = try await runtime.persistence.outboxDeliveryClaimForTesting(
      id: "tx-oversized-failed-lifecycle-00001"
    )
    let tailClaim = try #require(tailClaimValue)
    expectNoDifference(tailClaim.state, .ready)
    expectNoDifference(tailClaim.claimToken, nil)
    expectNoDifference(tailClaim.deliveryStarted, false)
    expectNoDifference(connectionStatus.state, .errored)
    expectNoDifference(
      connectionStatus.synchronizationBlocker?.firstMutationID,
      oversizedFailure.id
    )
    _ = try? await runtime.closeConnection()
  }

  @Test
  func retryableFailedLifecycleIsNotHiddenBehindFiftyTerminalFailures() async throws {
    let cacheURL = try temporaryBoundedOutboxCacheURL()
    var mutations = (0..<50).map { index -> PendingMutation in
      var mutation = boundedMutation(index: index, prefix: "retry-candidate-order")
      mutation.status = .failed
      mutation.failureMessage = "permission denied while delivering"
      mutation.failure = InstantMutationFailure(
        code: .permissionRejected,
        message: mutation.failureMessage!
      )
      return mutation
    }
    var retryable = boundedMutation(index: 50, prefix: "retry-candidate-order")
    retryable.status = .failed
    retryable.failureMessage = "could not resolve attribute after schema deployment"
    retryable.failure = InstantMutationFailure(
      code: .validationFailed,
      message: retryable.failureMessage!
    )
    mutations.append(retryable)
    try await seedBoundedOutbox(mutations, cacheURL: cacheURL)
    let persistence = try SQLitePersistenceStore(fileURL: cacheURL)
    try await persistence.bootstrap()

    let candidates = try await persistence.loadFailedMutationLifecycles(limit: 50)
    expectNoDifference(candidates.map(\.id), ["tx-retry-candidate-order-00050"])
  }

  @Test
  func fiftyEncodingFailuresUseBoundedRowAddressedQuarantineAndDoNotStarveTail()
    async throws
  {
    let cacheURL = try temporaryBoundedOutboxCacheURL()
    let liveSession = LiveReactorParitySession(messages: [
      liveReactorInitOK(attrs: liveReactorTodoServerAttrs)
    ])
    let runtime = try await connectedRuntime(
      appID: "bounded-outbox-encoding-head-window",
      cacheURL: cacheURL,
      liveSession: liveSession
    )
    let invalid = (0..<50).map {
      boundedEncodingFailureMutation(index: $0, prefix: "encoding-head-window")
    }
    _ = try await appendRuntimePreparedBoundedOutbox(
      invalid + [boundedMutation(index: 50, prefix: "encoding-head-window")],
      to: runtime.persistence
    )
    await runtime.persistence.resetDecodedOutboxBodyCount()
    await runtime.persistence.resetFailedMutationRetryMetricsForTesting()
    let encodingQuarantineDiagnostics = BoundedOutboxDiagnosticCounter()
    let diagnosticsToken = InstantDiagnostics.shared.addHandler { entry in
      guard entry.event == "outbox.mutation.encoding-quarantined",
        entry.metadata["mutationID"]?.hasPrefix("tx-encoding-head-window-") == true
      else { return }
      encodingQuarantineDiagnostics.increment()
    }
    defer { InstantDiagnostics.shared.removeHandler(diagnosticsToken) }

    try await withKnownIssue {
      await runtime.requestLiveMutationDelivery()
      try await instantLiveWithTimeout(
        operation: "wait for tail behind encoding-failure window",
        timeoutMilliseconds: 5_000
      ) {
        await liveSession.waitForSentMessageCount(2)
      }
      try await instantLiveWithTimeout(
        operation: "wait for the encoding-failure delivery pump to become idle",
        timeoutMilliseconds: 5_000
      ) {
        while !(await runtime.automaticMutationPumpIsIdleForTesting()) {
          await Task.yield()
        }
      }
    } matching: { issue in
      issue.description.contains("quarantined")
        || issue.description.contains("missing-bounded-attribute")
    }

    let sentIDs = await liveSession.sentMessages()
      .filter { $0.op == "transact" }
      .compactMap(\.clientEventID)
    expectNoDifference(sentIDs, ["tx-encoding-head-window-00050"])
    let decodedBodyCount = await runtime.persistence.currentDecodedOutboxBodyCount()
    let failedMutationCount = await runtime.failedMutations().count
    expectNoDifference(failedMutationCount, 50)
    let quarantineDiagnosticCount = encodingQuarantineDiagnostics.value
    expectNoDifference(quarantineDiagnosticCount, 50)
    let retryMetrics = await runtime.persistence.failedMutationRetryMetricsForTesting()
    expectNoDifference(retryMetrics.completedWindowCount, 0)
    expectNoDifference(retryMetrics.totalCandidateRowCount, 0)
    expectNoDifference(retryMetrics.totalDecodedBodyCount, 0)
    let maximumWindowBodyCount =
      await runtime.persistence.maximumAutomaticOutboxWindowBodyCountForTesting()
    expectNoDifference(decodedBodyCount, 101)
    #expect(maximumWindowBodyCount <= InstantAutomaticOutboxClaimLimits.maximumBodyDecodeCount)
    _ = try? await runtime.closeConnection()
  }

  @Test
  func mixedEncodingFailureWindowRefillsWithoutAnAcknowledgement() async throws {
    let cacheURL = try temporaryBoundedOutboxCacheURL()
    let liveSession = LiveReactorParitySession(messages: [
      liveReactorInitOK(attrs: liveReactorTodoServerAttrs)
    ])
    let runtime = try await connectedRuntime(
      appID: "bounded-outbox-mixed-encoding-window",
      cacheURL: cacheURL,
      liveSession: liveSession
    )
    let mutations = (0..<49).map {
      boundedEncodingFailureMutation(index: $0, prefix: "mixed-encoding-window")
    } + [
      boundedMutation(index: 49, prefix: "mixed-encoding-window"),
      boundedMutation(index: 50, prefix: "mixed-encoding-window"),
    ]
    _ = try await appendRuntimePreparedBoundedOutbox(mutations, to: runtime.persistence)

    try await withKnownIssue {
      await runtime.requestLiveMutationDelivery()
      try await instantLiveWithTimeout(
        operation: "wait for mixed encoding-window refill",
        timeoutMilliseconds: 5_000
      ) {
        await liveSession.waitForSentMessageCount(3)
      }
    } matching: { issue in
      issue.description.contains("quarantined")
        || issue.description.contains("missing-bounded-attribute")
    }

    let sentIDs = await liveSession.sentMessages()
      .filter { $0.op == "transact" }
      .compactMap(\.clientEventID)
    expectNoDifference(sentIDs, [
      "tx-mixed-encoding-window-00049",
      "tx-mixed-encoding-window-00050",
    ])
    expectNoDifference(Set(sentIDs).count, sentIDs.count)
    _ = try? await runtime.closeConnection()
  }

  @Test
  func legacyConfirmedUnprovenRowsRemainOrderedAheadOfPendingTail() async throws {
    let cacheURL = try temporaryBoundedOutboxCacheURL()
    let mutations = (0..<100).map {
      unprovenConfirmedBoundedMutation(index: $0, prefix: "legacy-order")
    } + [boundedMutation(index: 100, prefix: "legacy-order")]
    try await seedBoundedOutbox(mutations, cacheURL: cacheURL)
    try restorePreBoundedDeliveryOutboxSchema(cacheURL: cacheURL)

    let liveSession = LiveReactorParitySession(messages: [
      liveReactorInitOK(attrs: liveReactorTodoServerAttrs)
    ])
    var configuration = InstantRuntimeConfiguration(
      appID: "bounded-outbox-legacy-order",
      persistenceURL: cacheURL,
      initialAttributes: TodoExample.attributes,
      liveTransport: liveSession.transport
    )
    configuration.autoConnectLiveTransport = false
    let runtime = try await InstantRuntime.bootstrap(configuration: configuration)
    _ = try await runtime.connect()
    try await instantLiveWithTimeout(
      operation: "wait for first strict legacy claim window",
      timeoutMilliseconds: 5_000
    ) {
      await liveSession.waitForSentMessageCount(51)
    }

    let sentIDs = await liveSession.sentMessages()
      .filter { $0.op == "transact" }
      .compactMap(\.clientEventID)
    expectNoDifference(
      sentIDs,
      (0..<50).map { String(format: "tx-legacy-order-%05d", $0) },
      "Legacy confirmed rows with no server proof are ordered delivery barriers; the pending tail may not leapfrog them."
    )
    #expect(!sentIDs.contains("tx-legacy-order-00100"))
    _ = try? await runtime.closeConnection()
  }

  @Test
  func ordinalAcknowledgementDeadlinesKeepEightRowWindowSingleSendPastFiveSeconds()
    async throws
  {
    let cacheURL = try temporaryBoundedOutboxCacheURL()
    let mutations = (0..<8).map {
      boundedMutation(index: $0, prefix: "ordinal-ack-deadline")
    }
    try await seedBoundedOutbox(mutations, cacheURL: cacheURL)
    let clock = BoundedOutboxLockedClock(milliseconds: 100_000)
    let deadlineSleep = BoundedOutboxControlledSleep()
    let pumpPasses = BoundedOutboxDiagnosticCounter()
    let liveSession = LiveReactorParitySession(messages: [
      liveReactorInitOK(attrs: liveReactorTodoServerAttrs)
    ])
    var configuration = InstantRuntimeConfiguration(
      appID: "bounded-outbox-ordinal-ack-deadline",
      persistenceURL: cacheURL,
      initialAttributes: TodoExample.attributes,
      now: { clock.now() },
      liveTransport: liveSession.transport
    )
    configuration.autoConnectLiveTransport = false
    configuration.liveMutationDeadlineSleep = { milliseconds in
      try await deadlineSleep.sleep(milliseconds: milliseconds)
    }
    configuration.onAutomaticMutationPumpRetryWindowCompletedForTesting = {
      pumpPasses.increment()
    }
    let runtime = try await InstantRuntime.bootstrap(configuration: configuration)

    _ = try await runtime.connect()
    try await instantLiveWithTimeout(
      operation: "wait for the eight-row acknowledgement window",
      timeoutMilliseconds: 5_000
    ) {
      await liveSession.waitForSentMessageCount(9)
    }
    try await instantLiveWithTimeout(
      operation: "wait for the ordinal acknowledgement deadline schedule",
      timeoutMilliseconds: 5_000
    ) {
      await deadlineSleep.waitForFirstDelay()
    }

    var durableDeadlines: [Int64?] = []
    for mutation in mutations {
      durableDeadlines.append(
        try await runtime.persistence.outboxDeliveryClaimForTesting(id: mutation.id)?
          .deadlineMilliseconds
      )
    }
    expectNoDifference(
      durableDeadlines,
      (1...8).map { Optional(100_000 + Int64($0) * 6_000) },
      "The durable claim gives each in-flight ordinal its own Reactor-shaped acknowledgement budget."
    )
    let firstDelay = await deadlineSleep.firstDelay()
    expectNoDifference(firstDelay, 6_000)

    let completedPumpPasses = pumpPasses.value
    clock.advance(by: 5_500)
    await deadlineSleep.resumeFirstDelay()
    try await instantLiveWithTimeout(
      operation: "wait for the early deadline wake to finish without reclaiming",
      timeoutMilliseconds: 5_000
    ) {
      while true {
        let pumpIsIdle = await runtime.automaticMutationPumpIsIdleForTesting()
        if pumpPasses.value != completedPumpPasses, pumpIsIdle { break }
        await Task.yield()
      }
    }

    for mutation in mutations {
      await liveSession.enqueue(
        InstantLiveMessage(
          op: "transact-ok",
          clientEventID: mutation.id,
          fields: ["tx-id": .string("server-\(mutation.id)")]
        )
      )
    }
    try await instantLiveWithTimeout(
      operation: "wait for all delayed acknowledgements",
      timeoutMilliseconds: 5_000
    ) {
      while try await runtime.persistence.countOutboxMutations(status: .pending) != 0 {
        await Task.yield()
      }
    }

    let sentIDs = await liveSession.sentMessages()
      .filter { $0.op == "transact" }
      .compactMap(\.clientEventID)
    expectNoDifference(sentIDs, mutations.map(\.id))
    expectNoDifference(Set(sentIDs).count, mutations.count)
    _ = try? await runtime.closeConnection()
  }

  @Test
  func acknowledgementTimeoutRetriesOnlyAfterReplacingTheLiveGeneration()
    async throws
  {
    let cacheURL = try temporaryBoundedOutboxCacheURL()
    let predecessor = boundedMutation(
      index: 0,
      prefix: "ack-generation-barrier",
      entityID: "ack-generation-barrier-entity"
    )
    let successor = boundedMutation(
      index: 1,
      prefix: "ack-generation-barrier",
      entityID: "ack-generation-barrier-entity"
    )
    try await seedBoundedOutbox([predecessor, successor], cacheURL: cacheURL)
    let clock = BoundedOutboxLockedClock(milliseconds: 100_000)
    let deadlineSleep = BoundedOutboxControlledSleep()
    let reconnectSleep = BoundedOutboxControlledSleep()
    let pumpPasses = BoundedOutboxDiagnosticCounter()
    let receiverEventGate = BoundedOutboxReceiverEventGate(blockingEventOrdinal: 2)
    let firstSession = LiveReactorParitySession(messages: [
      liveReactorInitOK(
        attrs: liveReactorTodoServerAttrs,
        sessionID: "before-acknowledgement-timeout"
      )
    ])
    let replacementSession = LiveReactorParitySession(messages: [
      liveReactorInitOK(
        attrs: liveReactorTodoServerAttrs,
        sessionID: "after-acknowledgement-timeout"
      )
    ])
    let transport = LiveReactorParityTransport(sessions: [firstSession, replacementSession])
    var configuration = InstantRuntimeConfiguration(
      appID: "bounded-outbox-ack-generation-barrier",
      persistenceURL: cacheURL,
      initialAttributes: TodoExample.attributes,
      now: { clock.now() },
      liveTransport: transport.transport
    )
    configuration.autoConnectLiveTransport = false
    configuration.liveReconnectSleep = { milliseconds in
      try await reconnectSleep.sleep(milliseconds: milliseconds)
    }
    configuration.liveMutationDeadlineSleep = { milliseconds in
      try await deadlineSleep.sleep(milliseconds: milliseconds)
    }
    configuration.onLiveReceiverEventAcquiredForTesting = {
      await receiverEventGate.eventAcquired()
    }
    configuration.onAutomaticMutationPumpRetryWindowCompletedForTesting = {
      pumpPasses.increment()
    }
    let runtime = try await InstantRuntime.bootstrap(configuration: configuration)

    try await withKnownIssue {
      _ = try await runtime.connect()
      try await instantLiveWithTimeout(
        operation: "wait for the predecessor and successor sends",
        timeoutMilliseconds: 5_000
      ) {
        await firstSession.waitForSentMessageCount(3)
      }
      await firstSession.enqueue(
        InstantLiveMessage(
          op: "transact-ok",
          clientEventID: successor.id,
          fields: ["tx-id": .string("server-\(successor.id)")]
        )
      )
      try await instantLiveWithTimeout(
        operation: "wait for the acknowledged successor to leave the outbox",
        timeoutMilliseconds: 5_000
      ) {
        while try await runtime.persistence.countOutboxMutations(status: .pending) != 1 {
          await Task.yield()
        }
      }
      await firstSession.enqueue(
        InstantLiveMessage(
          op: "error",
          clientEventID: predecessor.id,
          fields: [
            "message": .string("permission denied after stale replay"),
            "status": .number(403),
            "type": .string("permission-denied"),
          ]
        )
      )
      try await instantLiveWithTimeout(
        operation: "hold the stale response inside the expiring generation",
        timeoutMilliseconds: 5_000
      ) {
        await receiverEventGate.waitUntilBlocked()
      }
      try await instantLiveWithTimeout(
        operation: "wait for the durable mutation deadline schedule",
        timeoutMilliseconds: 5_000
      ) {
        await deadlineSleep.waitForFirstDelay()
      }
      let firstDelay = await deadlineSleep.firstDelay()
      expectNoDifference(firstDelay, 6_000)
      let completedPumpPasses = pumpPasses.value
      clock.advance(by: 6_000)
      await deadlineSleep.resumeFirstDelay()
      try await instantLiveWithTimeout(
        operation: "wait for reconnect before a second durable claim pass",
        timeoutMilliseconds: 5_000
      ) {
        await reconnectSleep.waitForFirstDelay()
      }
      expectNoDifference(
        pumpPasses.value,
        completedPumpPasses + 1,
        "A timed-out generation must reconnect before another durable claim pass."
      )
      let firstGenerationIDsBeforeReconnect = await firstSession.sentMessages()
        .filter { $0.op == "transact" }
        .compactMap(\.clientEventID)
      expectNoDifference(firstGenerationIDsBeforeReconnect, [predecessor.id, successor.id])
      await receiverEventGate.releaseBlockedEvent()
      await reconnectSleep.resumeFirstDelay()
      try await instantLiveWithTimeout(
        operation: "wait for the acknowledgement-unknown replacement generation",
        timeoutMilliseconds: 5_000
      ) {
        await transport.waitForConnectionCount(2)
        await replacementSession.waitForSentMessageCount(2)
      }
    } matching: { issue in
      issue.description.contains("did not acknowledge")
    }

    let firstGenerationIDs = await firstSession.sentMessages()
      .filter { $0.op == "transact" }
      .compactMap(\.clientEventID)
    let replacementGenerationIDs = await replacementSession.sentMessages()
      .filter { $0.op == "transact" }
      .compactMap(\.clientEventID)
    expectNoDifference(firstGenerationIDs, [predecessor.id, successor.id])
    expectNoDifference(replacementGenerationIDs, [predecessor.id])

    let failedMutations = await runtime.failedMutations()
    let pendingMutationIDs = await runtime.pendingMutations().map(\.id)
    expectNoDifference(failedMutations, [])
    expectNoDifference(pendingMutationIDs, [predecessor.id])

    await replacementSession.enqueue(
      InstantLiveMessage(
        op: "transact-ok",
        clientEventID: predecessor.id,
        fields: ["tx-id": .string("server-\(predecessor.id)")]
      )
    )
    try await instantLiveWithTimeout(
      operation: "wait for replacement-generation acknowledgement",
      timeoutMilliseconds: 5_000
    ) {
      while try await runtime.persistence.countOutboxMutations(status: .pending) != 0 {
        await Task.yield()
      }
    }
    _ = try? await runtime.closeConnection()
  }

  @Test
  func sameProcessOfflineTenThousandEnqueuesKeepResidentBarrierCacheBounded()
    async throws
  {
    let cacheURL = try temporaryBoundedOutboxCacheURL()
    var configuration = InstantRuntimeConfiguration(
      appID: "bounded-outbox-same-process-ten-thousand",
      persistenceURL: cacheURL,
      initialAttributes: TodoExample.attributes
    )
    configuration.autoConnectLiveTransport = false
    let runtime = try await InstantRuntime.bootstrap(configuration: configuration)

    for index in 0..<10_000 {
      let mutation = boundedMutation(
        index: index,
        prefix: "same-process-ten-thousand",
        entityID: "one-hot-offline-entity"
      )
      _ = try await runtime.transact(mutation.transaction, createdAt: mutation.createdAt)
    }

    let durableMutationCount = try await runtime.persistence.countOutboxMutations()
    expectNoDifference(durableMutationCount, 10_000)
    let residentBarrierCount = await runtime.mutationDeliveryBarrierMutations().count
    #expect(
      residentBarrierCount <= InstantAutomaticOutboxClaimLimits.maximumMutationCount,
      "SQLite owns the queue; the runtime keeps only its bounded active claim/barrier set."
    )
    let queueWideReadCount =
      await runtime.persistence.localMutationQueueWideReadCountForTesting()
    expectNoDifference(
      queueWideReadCount,
      0,
      "Appending one local mutation must not scan or rebuild the durable queue."
    )
  }

  @Test
  func publicTenThousandRowTransportInspectionDoesNotPopulateDeliveryBarrier()
    async throws
  {
    let cacheURL = try temporaryBoundedOutboxCacheURL()
    try await seedBoundedOutbox(
      (0..<10_000).map { boundedMutation(index: $0, prefix: "inspection-ten-thousand") },
      cacheURL: cacheURL
    )
    var configuration = InstantRuntimeConfiguration(
      appID: "bounded-outbox-inspection-ten-thousand",
      persistenceURL: cacheURL,
      initialAttributes: TodoExample.attributes
    )
    configuration.autoConnectLiveTransport = false
    let runtime = try await InstantRuntime.bootstrap(configuration: configuration)

    let mutations = await runtime.outboxTransportMutations()
    expectNoDifference(mutations.count, 10_000)
    let residentBarrier = await runtime.mutationDeliveryBarrierMutations()
    expectNoDifference(residentBarrier, [])
    let firstDeliveryStarted = try await runtime.persistence.outboxDeliveryStartedForTesting(
      id: "tx-inspection-ten-thousand-00000"
    )
    expectNoDifference(
      firstDeliveryStarted,
      false,
      "Explicit inspection neither claims nor marks a mutation as offered."
    )
  }

  @Test
  func coldTenThousandRowInspectionQuarantinesCorruptTailWithoutReturningPartialQueue()
    async throws
  {
    let cacheURL = try temporaryBoundedOutboxCacheURL()
    try await seedBoundedOutbox(
      (0..<10_000).map { boundedMutation(index: $0, prefix: "inspection-corrupt-tail") },
      cacheURL: cacheURL
    )
    try corruptBoundedOutboxBody(
      id: "tx-inspection-corrupt-tail-09999",
      cacheURL: cacheURL
    )
    var configuration = InstantRuntimeConfiguration(
      appID: "bounded-outbox-inspection-corrupt-tail",
      persistenceURL: cacheURL,
      initialAttributes: TodoExample.attributes
    )
    configuration.autoConnectLiveTransport = false
    let runtime = try await InstantRuntime.bootstrap(configuration: configuration)
    await runtime.persistence.resetDecodedOutboxBodyCount()

    var mutations: [PendingMutation] = []
    await withKnownIssue {
      mutations = await runtime.outboxMutations()
    } matching: { issue in
      issue.description.contains("quarantined corrupt durable mutation")
    }
    expectNoDifference(
      mutations.count,
      10_000,
      "A corrupt tail becomes one visible failed shell; it must not collapse a complete durable inspection to an empty resident fallback."
    )
    let tail = try #require(mutations.last)
    expectNoDifference(tail.id, "tx-inspection-corrupt-tail-09999")
    expectNoDifference(tail.status, .failed)
    let decodedBodyCount = await runtime.persistence.currentDecodedOutboxBodyCount()
    expectNoDifference(decodedBodyCount, 10_000)
    let quarantinedByteCount = try await runtime.persistence
      .quarantinedOutboxBodyByteCountForTesting(id: tail.id)
    #expect(quarantinedByteCount > 0)
    let residentBarrier = await runtime.mutationDeliveryBarrierMutations()
    expectNoDifference(residentBarrier, [])
  }

  @Test
  func unlimitedExplicitFlushOfTenThousandRowsAdmitsOneFiftyMutationWindow()
    async throws
  {
    let cacheURL = try temporaryBoundedOutboxCacheURL()
    try await seedBoundedOutbox(
      (0..<10_000).map {
        boundedMutation(index: $0, prefix: "unlimited-flush-ten-thousand")
      },
      cacheURL: cacheURL
    )
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "bounded-outbox-unlimited-flush-ten-thousand",
        persistenceURL: cacheURL,
        initialAttributes: TodoExample.attributes
      )
    )
    await runtime.persistence.resetDecodedOutboxBodyCount()

    let result = try await runtime.flushPendingMutations()

    expectNoDifference(
      result.request.mutations.map(\.mutationID),
      (0..<InstantAutomaticOutboxClaimLimits.maximumMutationCount).map {
        String(format: "tx-unlimited-flush-ten-thousand-%05d", $0)
      }
    )
    expectNoDifference(result.pendingMutationCount, 9_950)
    expectNoDifference(result.mutationCount, 10_000)
    let decodedBodyCount = await runtime.persistence.currentDecodedOutboxBodyCount()
    expectNoDifference(
      decodedBodyCount,
      InstantAutomaticOutboxClaimLimits.maximumMutationCount,
      "The exact owned window carries each selected body through disposition instead of decoding it twice or hydrating the tail."
    )
    let firstTailClaim = try await runtime.persistence.outboxDeliveryClaimForTesting(
      id: "tx-unlimited-flush-ten-thousand-00050"
    )
    let finalTailClaim = try await runtime.persistence.outboxDeliveryClaimForTesting(
      id: "tx-unlimited-flush-ten-thousand-09999"
    )
    expectNoDifference(firstTailClaim?.state, .ready)
    expectNoDifference(firstTailClaim?.deliveryStarted, false)
    expectNoDifference(finalTailClaim?.state, .ready)
    expectNoDifference(finalTailClaim?.deliveryStarted, false)
    let residentBarrier = await runtime.mutationDeliveryBarrierMutations()
    expectNoDifference(residentBarrier, [])
  }

  @Test
  func unlimitedExplicitFlushHonorsTheTwoHundredFiftySixStepWindow()
    async throws
  {
    let cacheURL = try temporaryBoundedOutboxCacheURL()
    try await seedBoundedOutbox(
      (0..<30).map {
        boundedMutation(index: $0, prefix: "explicit-step-window", stepCount: 10)
      },
      cacheURL: cacheURL
    )
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "bounded-outbox-explicit-step-window",
        persistenceURL: cacheURL,
        initialAttributes: TodoExample.attributes
      )
    )
    await runtime.persistence.resetDecodedOutboxBodyCount()

    let result = try await runtime.flushPendingMutations()

    expectNoDifference(result.request.mutations.count, 25)
    let transportStepCount = result.request.mutations.reduce(into: 0) { count, mutation in
      count += mutation.txSteps.count
    }
    expectNoDifference(transportStepCount, 250)
    #expect(transportStepCount <= InstantAutomaticOutboxClaimLimits.maximumStepCount)
    let decodedBodyCount = await runtime.persistence.currentDecodedOutboxBodyCount()
    expectNoDifference(decodedBodyCount, 25)
    let firstTailClaim = try await runtime.persistence.outboxDeliveryClaimForTesting(
      id: "tx-explicit-step-window-00025"
    )
    expectNoDifference(firstTailClaim?.state, .ready)
    expectNoDifference(firstTailClaim?.deliveryStarted, false)
  }

  @Test
  func unlimitedExplicitFlushHonorsTheEightMiBDurableBodyWindowBeforeDecode()
    async throws
  {
    let cacheURL = try temporaryBoundedOutboxCacheURL()
    try await seedBoundedOutbox(
      (0..<3).map {
        boundedLargeMutation(
          index: $0,
          prefix: "explicit-byte-window",
          valueByteCount: 5 * 1_024 * 1_024
        )
      },
      cacheURL: cacheURL
    )
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "bounded-outbox-explicit-byte-window",
        persistenceURL: cacheURL,
        initialAttributes: TodoExample.attributes
      )
    )
    await runtime.persistence.resetDecodedOutboxBodyCount()

    let result = try await runtime.flushPendingMutations()

    expectNoDifference(
      result.request.mutations.map(\.mutationID),
      ["tx-explicit-byte-window-00000"]
    )
    let decodedBodyCount = await runtime.persistence.currentDecodedOutboxBodyCount()
    expectNoDifference(decodedBodyCount, 1)
    let decodedBodyBytes = await runtime.persistence.currentDecodedOutboxBodyByteCount()
    #expect(decodedBodyBytes <= InstantAutomaticOutboxClaimLimits.maximumEncodedBodyBytes)
    let firstTailClaim = try await runtime.persistence.outboxDeliveryClaimForTesting(
      id: "tx-explicit-byte-window-00001"
    )
    expectNoDifference(firstTailClaim?.state, .ready)
    expectNoDifference(firstTailClaim?.deliveryStarted, false)
  }

  @Test
  func limitedExplicitFlushOfTenThousandRowsDecodesAndDisposesOnlySelectedBody()
    async throws
  {
    let cacheURL = try temporaryBoundedOutboxCacheURL()
    try await seedBoundedOutbox(
      (0..<10_000).map { boundedMutation(index: $0, prefix: "flush-ten-thousand") },
      cacheURL: cacheURL
    )
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "bounded-outbox-flush-ten-thousand",
        persistenceURL: cacheURL,
        initialAttributes: TodoExample.attributes
      )
    )
    await runtime.persistence.resetDecodedOutboxBodyCount()

    let result = try await runtime.flushPendingMutations(limit: 1)
    expectNoDifference(result.request.mutations.map(\.mutationID), [
      "tx-flush-ten-thousand-00000"
    ])
    expectNoDifference(result.pendingMutationCount, 9_999)
    expectNoDifference(result.mutationCount, 10_000)
    let decodedBodyCount = await runtime.persistence.currentDecodedOutboxBodyCount()
    expectNoDifference(
      decodedBodyCount,
      1,
      "A smaller caller limit still owns and decodes exactly one body through transport and disposition."
    )
    let residentBarrier = await runtime.mutationDeliveryBarrierMutations()
    expectNoDifference(residentBarrier, [])
  }

  @Test
  func repeatedExplicitFailureOfTenThousandRowsKeepsResidentActorEmpty()
    async throws
  {
    let cacheURL = try temporaryBoundedOutboxCacheURL()
    var mutations = (0..<10_000).map {
      boundedMutation(index: $0, prefix: "failed-flush-ten-thousand")
    }
    let targetTriples = try (0..<2).map { index in
      let triple = try #require(
        mutations[index].transaction.operations.compactMap { operation -> InstantTriple? in
          guard case let .insert(triple) = operation else { return nil }
          return triple
        }.first
      )
      mutations[index].rollbackTransaction = InstantStoreTransaction(
        id: "rollback-\(mutations[index].id)",
        operations: [.deleteEntity(triple.entityID)]
      )
      mutations[index].optimisticOverlayState = .applied
      return triple
    }
    let persistence = try SQLitePersistenceStore(fileURL: cacheURL)
    try await persistence.bootstrap()
    try await persistence.saveStoreSnapshot(
      InstantStoreSnapshot(
        attributes: TodoExample.attributes,
        triples: targetTriples
      )
    )
    let preparedState = try await persistence.loadCompactState()
    let didAdmitPreparedMutations = try await persistence.saveOutbox(
      mutations,
      replacing: [],
      metadataEntries: [],
      expectedStoreRevision: preparedState.storeRevision,
      expectedOutboxRevision: preparedState.outboxRevision
    )
    expectNoDifference(didAdmitPreparedMutations, true)
    await persistence.simulateUnexpectedConnectionCloseForTesting()
    let corruptTailID = "tx-failed-flush-ten-thousand-09999"
    try corruptBoundedOutboxBody(id: corruptTailID, cacheURL: cacheURL)
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "bounded-outbox-failed-flush-ten-thousand",
        persistenceURL: cacheURL,
        initialAttributes: TodoExample.attributes,
        mutationTransport: InstantMutationTransportClient { request in
          InstantMutationTransportResponse(
            results: request.mutations.map {
              InstantMutationTransportResult(
                mutationID: $0.mutationID,
                outcome: .failed,
                message: "permission rejected"
              )
            }
          )
        }
      )
    )
    await runtime.persistence.resetDecodedOutboxBodyCount()

    let result = try await runtime.flushPendingMutations(limit: 1)

    expectNoDifference(result.failed.map(\.id), ["tx-failed-flush-ten-thousand-00000"])
    expectNoDifference(result.pendingMutationCount, 9_999)
    expectNoDifference(result.mutationCount, 10_000)
    let decodedBodyCount = await runtime.persistence.currentDecodedOutboxBodyCount()
    expectNoDifference(
      decodedBodyCount,
      2,
      "Explicit rejection decodes the selected transport body and only its affected terminal component."
    )
    let quarantinedTailByteCount = try await runtime.persistence
      .quarantinedOutboxBodyByteCountForTesting(id: corruptTailID)
    expectNoDifference(quarantinedTailByteCount, 0)
    let tailDeliveryStarted = try await runtime.persistence.outboxDeliveryStartedForTesting(
      id: corruptTailID
    )
    expectNoDifference(tailDeliveryStarted, false)
    let residentBarrierAfterFirstFailure = await runtime.mutationDeliveryBarrierMutations()
    expectNoDifference(
      residentBarrierAfterFirstFailure,
      [],
      "A terminal failure removes its target shell and must not append it back to an empty resident actor."
    )

    await runtime.persistence.resetDecodedOutboxBodyCount()
    let repeated = try await runtime.flushPendingMutations(limit: 1)

    expectNoDifference(repeated.failed.map(\.id), ["tx-failed-flush-ten-thousand-00001"])
    expectNoDifference(repeated.pendingMutationCount, 9_998)
    expectNoDifference(repeated.mutationCount, 10_000)
    let repeatedDecodedBodyCount = await runtime.persistence.currentDecodedOutboxBodyCount()
    expectNoDifference(repeatedDecodedBodyCount, 2)
    let residentBarrierAfterSecondFailure = await runtime.mutationDeliveryBarrierMutations()
    expectNoDifference(
      residentBarrierAfterSecondFailure,
      [],
      "Repeated terminal failures must keep the body-free resident actor empty."
    )
  }
}

private func connectedRuntime(
  appID: String,
  cacheURL: URL,
  liveSession: LiveReactorParitySession
) async throws -> InstantRuntime {
  let runtime = try await disconnectedRuntime(
    appID: appID,
    cacheURL: cacheURL,
    liveSession: liveSession
  )
  _ = try await runtime.connect()
  let sentOps = await liveSession.sentMessages().map(\.op)
  expectNoDifference(
    sentOps,
    ["init"],
    boundedOutboxSource
  )
  return runtime
}

private func disconnectedRuntime(
  appID: String,
  cacheURL: URL,
  liveSession: LiveReactorParitySession
) async throws -> InstantRuntime {
  var configuration = InstantRuntimeConfiguration(
    appID: appID,
    persistenceURL: cacheURL,
    initialAttributes: TodoExample.attributes,
    liveTransport: liveSession.transport
  )
  configuration.autoConnectLiveTransport = false
  return try await InstantRuntime.bootstrap(configuration: configuration)
}

private func boundedMutation(
  index: Int,
  prefix: String,
  entityID: String? = nil,
  stepCount: Int = 1
) -> PendingMutation {
  let id = String(format: "tx-%@-%05d", prefix, index)
  let createdAt = InstantTimestamp(milliseconds: Int64(index + 1))
  let operations = (0..<stepCount).map { step in
    InstantTripleOperation.insert(
      InstantTriple(
        entityID: entityID ?? "todo-\(prefix)-\(index)-\(step)",
        attributeID: "todos/text",
        value: .string("value-\(index)-\(step)"),
        txID: id,
        txTime: createdAt
      )
    )
  }
  var mutation = PendingMutation(
    id: id,
    createdAt: createdAt,
    transaction: InstantStoreTransaction(id: id, operations: operations)
  )
  mutation.optimisticOverlayState = .applied
  mutation.optimisticEffectReceiptVersion =
    PendingMutation.currentOptimisticEffectReceiptVersion
  return mutation
}

private enum LegacyReceiptRollback {
  case none
  case releasedInverse
  case deployedDeleteEntityInverse
  case wrongID
  case unsupportedOperation
}

private func legacyReceiptMutation(
  index: Int,
  prefix: String,
  status: InstantMutationStatus = .pending,
  overlayState: InstantOptimisticOverlayState,
  rollback: LegacyReceiptRollback,
  stepCount: Int = 1
) -> PendingMutation {
  var mutation = boundedMutation(
    index: index,
    prefix: prefix,
    stepCount: stepCount
  )
  mutation.status = status
  mutation.optimisticOverlayState = overlayState
  mutation.optimisticEffectReceiptVersion = nil
  let inverseTriple: InstantTriple
  if case let .insert(triple)? = mutation.transaction.operations.first {
    inverseTriple = triple
  } else {
    inverseTriple = InstantTriple(
      entityID: "todo-\(prefix)-\(index)-inverse",
      attributeID: "todos/text",
      value: .string("legacy inverse"),
      txID: mutation.id,
      txTime: mutation.createdAt
    )
  }
  switch rollback {
  case .none:
    mutation.rollbackTransaction = nil
  case .releasedInverse:
    mutation.rollbackTransaction = InstantStoreTransaction(
      id: "rollback-\(mutation.id)",
      operations: [.retract(inverseTriple)]
    )
  case .deployedDeleteEntityInverse:
    mutation.rollbackTransaction = InstantStoreTransaction(
      id: "rollback-\(mutation.id)",
      operations: [.deleteEntity(inverseTriple.entityID)]
    )
  case .wrongID:
    mutation.rollbackTransaction = InstantStoreTransaction(
      id: "wrong-rollback-\(mutation.id)",
      operations: [.retract(inverseTriple)]
    )
  case .unsupportedOperation:
    mutation.rollbackTransaction = InstantStoreTransaction(
      id: "rollback-\(mutation.id)",
      operations: [
        .ruleParams(
          entityID: inverseTriple.entityID,
          namespace: "todos",
          params: .object(["allow": .bool(true)])
        )
      ]
    )
  }
  return mutation
}

private let requiredFoundationAttributes: [InstantAttribute] = [
  .primaryKey(namespace: "transcriptionSegments"),
  InstantAttribute(
    id: "transcriptionSegments/text",
    namespace: "transcriptionSegments",
    name: "text",
    valueType: .string,
    isRequired: true
  ),
  InstantAttribute(
    id: "transcriptionSegments/searchPreview",
    namespace: "transcriptionSegments",
    name: "searchPreview",
    valueType: .string,
    isRequired: false
  ),
  InstantAttribute(
    id: "transcriptionSegments/recording",
    namespace: "transcriptionSegments",
    name: "recording",
    valueType: .ref,
    isRequired: false,
    forwardIdentity: "transcriptionSegments/recording",
    reverseIdentity: "recordings/transcriptionSegments",
    linkNamespace: "recordings"
  ),
]

private func requiredFoundationMutation(
  id: String,
  entityID: String,
  text: String,
  optionalPreview: String?,
  recordingID: String?,
  createdAt: InstantTimestamp
) -> PendingMutation {
  var operations: [InstantTripleOperation] = [
    .insert(
      requiredFoundationTriple(
        entityID: entityID,
        attributeID: "transcriptionSegments/id",
        value: .string(entityID),
        transactionID: id,
        timestamp: createdAt
      )
    )
  ]
  if let recordingID {
    operations.append(
      .insert(
        requiredFoundationTriple(
          entityID: entityID,
          attributeID: "transcriptionSegments/recording",
          value: .ref(recordingID),
          transactionID: id,
          timestamp: createdAt
        )
      )
    )
  }
  operations.append(
    .insert(
      requiredFoundationTriple(
        entityID: entityID,
        attributeID: "transcriptionSegments/text",
        value: .string(text),
        transactionID: id,
        timestamp: createdAt
      )
    )
  )
  if let optionalPreview {
    operations.append(
      .insert(
        requiredFoundationTriple(
          entityID: entityID,
          attributeID: "transcriptionSegments/searchPreview",
          value: .string(optionalPreview),
          transactionID: id,
          timestamp: createdAt
        )
      )
    )
  }
  var mutation = PendingMutation(
    id: id,
    createdAt: createdAt,
    transaction: InstantStoreTransaction(id: id, operations: operations)
  )
  mutation.optimisticOverlayState = .applied
  mutation.optimisticEffectReceiptVersion =
    PendingMutation.currentOptimisticEffectReceiptVersion
  return mutation
}

private func requiredFoundationTriple(
  entityID: String,
  attributeID: String,
  value: InstantValue,
  transactionID: String,
  timestamp: InstantTimestamp
) -> InstantTriple {
  InstantTriple(
    entityID: entityID,
    attributeID: attributeID,
    value: value,
    txID: transactionID,
    txTime: timestamp
  )
}

private func boundedOutboxAddTripleValues(
  in message: InstantLiveMessage
) -> [String: InstantLiveJSONValue] {
  Dictionary(
    uniqueKeysWithValues: message.fields["tx-steps"]?.arrayValue?.compactMap { step in
      guard let values = step.arrayValue,
        values.count >= 4,
        values[0].stringValue == "add-triple",
        let attributeID = values[2].stringValue
      else { return nil }
      return (attributeID, values[3])
    } ?? []
  )
}

private func acceptedBoundedMutation(index: Int, prefix: String) -> PendingMutation {
  var mutation = boundedMutation(index: index, prefix: prefix)
  mutation.status = .confirmed
  mutation.serverTransactionID = "server-\(mutation.id)"
  mutation.confirmationSource = nil
  return mutation
}

private func unprovenConfirmedBoundedMutation(index: Int, prefix: String) -> PendingMutation {
  var mutation = boundedMutation(index: index, prefix: prefix)
  mutation.status = .confirmed
  mutation.serverTransactionID = nil
  mutation.confirmationSource = .localTransport
  return mutation
}

private func boundedEncodingFailureMutation(index: Int, prefix: String) -> PendingMutation {
  var mutation = boundedMutation(index: index, prefix: prefix)
  guard case let .insert(originalTriple)? = mutation.transaction.operations.first else {
    return mutation
  }
  var triple = originalTriple
  triple.attributeID = "missing-bounded-attribute"
  mutation.transaction.operations = [.insert(triple)]
  return mutation
}

private func boundedLargeMutation(
  index: Int,
  prefix: String,
  valueByteCount: Int
) -> PendingMutation {
  var mutation = boundedMutation(index: index, prefix: prefix)
  let id = mutation.id
  mutation.transaction.operations = [
    .insert(
      InstantTriple(
        entityID: "todo-\(prefix)-\(index)",
        attributeID: "todos/text",
        value: .string(String(repeating: "x", count: valueByteCount)),
        txID: id,
        txTime: mutation.createdAt
      )
    )
  ]
  return mutation
}

private func temporaryBoundedOutboxCacheURL() throws -> URL {
  let directory = FileManager.default.temporaryDirectory
    .appendingPathComponent("InstantBoundedOutboxDeliveryTests-\(UUID().uuidString)")
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  return directory.appendingPathComponent("state.sqlite")
}

private func seedBoundedOutbox(
  _ mutations: [PendingMutation],
  cacheURL: URL
) async throws {
  let persistence = try SQLitePersistenceStore(fileURL: cacheURL)
  try await persistence.bootstrap()
  _ = try await appendRuntimePreparedBoundedOutbox(mutations, to: persistence)
  await persistence.simulateUnexpectedConnectionCloseForTesting()
}

private func saveRuntimePreparedBoundedStoreSnapshot(
  _ snapshot: InstantStoreSnapshot,
  to persistence: SQLitePersistenceStore
) async throws {
  let state = try await persistence.loadState()
  let didSave = try await persistence.saveRuntimePreparedStoreSnapshot(
    snapshot,
    replacing: state.snapshot.store,
    expectedStoreRevision: state.storeRevision,
    expectedOutboxRevision: state.outboxRevision,
    expectedAttributeRevision: state.attributeRevision
  )
  expectNoDifference(didSave, true)
}

private func saveRuntimeAuthorizedBoundedOutboxBodies(
  _ mutations: [PendingMutation],
  to persistence: SQLitePersistenceStore
) async throws {
  let state = try await persistence.loadState()
  let didSave = try await persistence.saveOutbox(
    state.snapshot.outbox + mutations,
    replacing: state.snapshot.outbox,
    metadataEntries: [],
    expectedStoreRevision: state.storeRevision,
    expectedOutboxRevision: state.outboxRevision
  )
  expectNoDifference(didSave, true)
}

@discardableResult
private func appendRuntimePreparedBoundedOutbox(
  _ mutations: [PendingMutation],
  to persistence: SQLitePersistenceStore
) async throws -> [PendingMutation] {
  let state = try await persistence.loadState()
  let prepared = try await prepareBoundedOutboxFixture(
    mutations,
    applyingTo: state.snapshot.store
  )
  let existingIDs = Set(state.snapshot.outbox.map(\.id))
  #expect(prepared.mutations.allSatisfy { !existingIDs.contains($0.id) })
  let didSave = try await persistence.saveSnapshot(
    InstantPersistenceSnapshot(
      store: prepared.store,
      outbox: state.snapshot.outbox + prepared.mutations
    ),
    replacing: state.snapshot,
    metadataEntries: [],
    expectedStoreRevision: state.storeRevision,
    expectedAttributeRevision: state.attributeRevision,
    expectedOutboxRevision: state.outboxRevision
  )
  expectNoDifference(didSave, true)
  return prepared.mutations
}

private func replaceRuntimePreparedBoundedOutboxMutation(
  _ replacement: PendingMutation,
  replacing original: PendingMutation,
  in persistence: SQLitePersistenceStore
) async throws -> PendingMutation {
  let state = try await persistence.loadState()
  let originalIndex = try #require(
    state.snapshot.outbox.firstIndex { $0.id == original.id }
  )
  let fixtureStore = InstantStore(snapshot: state.snapshot.store)
  switch original.optimisticEffectReceipt {
  case .unknown:
    Issue.record("A Runtime rebase fixture requires a proven original receipt.")
  case .noCurrentMaterializedEffect:
    break
  case let .materialized(rollback):
    _ = await fixtureStore.commitAndPublish(
      try await fixtureStore.prepareCurrent(rollback)
    )
  }
  let preparedReplacement = try await prepareBoundedOutboxFixture(
    [replacement],
    applyingTo: await fixtureStore.snapshot()
  )
  let durableReplacement = try #require(preparedReplacement.mutations.first)
  var nextOutbox = state.snapshot.outbox
  nextOutbox[originalIndex] = durableReplacement
  let didSave = try await persistence.saveSnapshot(
    InstantPersistenceSnapshot(
      store: preparedReplacement.store,
      outbox: nextOutbox
    ),
    replacing: state.snapshot,
    metadataEntries: [],
    expectedStoreRevision: state.storeRevision,
    expectedAttributeRevision: state.attributeRevision,
    expectedOutboxRevision: state.outboxRevision
  )
  expectNoDifference(didSave, true)
  return durableReplacement
}

private func prepareBoundedOutboxFixture(
  _ mutations: [PendingMutation],
  applyingTo baseStore: InstantStoreSnapshot
) async throws -> (store: InstantStoreSnapshot, mutations: [PendingMutation]) {
  let preparationAttribute = InstantAttribute(
    id: "missing-bounded-attribute",
    namespace: "missingBoundedAttributes",
    name: "value",
    valueType: .string
  )
  var preparationStore = baseStore
  for attribute in TodoExample.attributes + [preparationAttribute]
  where !preparationStore.attributes.contains(where: { $0.id == attribute.id }) {
    preparationStore.attributes.append(attribute)
  }
  let fixtureStore = InstantStore(snapshot: preparationStore)

  var insertedEntityIDs: [Set<String>] = []
  insertedEntityIDs.reserveCapacity(mutations.count)
  var allInsertedEntityIDs: Set<String> = []
  var canPrepareAsIndependentCreates = true
  for mutation in mutations {
    var entityIDs: Set<String> = []
    for operation in mutation.transaction.operations {
      guard case let .insert(triple) = operation else {
        canPrepareAsIndependentCreates = false
        break
      }
      entityIDs.insert(triple.entityID)
    }
    if !allInsertedEntityIDs.isDisjoint(with: entityIDs) {
      canPrepareAsIndependentCreates = false
    }
    allInsertedEntityIDs.formUnion(entityIDs)
    insertedEntityIDs.append(entityIDs)
  }
  if baseStore.triples.contains(where: { allInsertedEntityIDs.contains($0.entityID) }) {
    canPrepareAsIndependentCreates = false
  }

  var preparedMutations: [PendingMutation] = []
  preparedMutations.reserveCapacity(mutations.count)
  if canPrepareAsIndependentCreates {
    let aggregate = InstantStoreTransaction(
      id: "bounded-outbox-fixture-aggregate",
      operations: mutations.flatMap { $0.transaction.operations }
    )
    _ = await fixtureStore.commitAndPublish(
      try await fixtureStore.prepareCurrent(aggregate)
    )
    for (mutation, entityIDs) in zip(mutations, insertedEntityIDs) {
      var preparedMutation = mutation
      if entityIDs.isEmpty {
        preparedMutation.rollbackTransaction = nil
        preparedMutation.optimisticOverlayState = .applied
      } else {
        preparedMutation.rollbackTransaction = InstantStoreTransaction(
          id: "rollback-\(mutation.id)",
          operations: entityIDs.sorted().map(InstantTripleOperation.deleteEntity)
        )
        preparedMutation.optimisticOverlayState = .applied
      }
      preparedMutation.optimisticEffectReceiptVersion =
        PendingMutation.currentOptimisticEffectReceiptVersion
      preparedMutations.append(preparedMutation)
    }
  } else {
    for var mutation in mutations {
      let prepared = try await fixtureStore.prepareCurrent(mutation.transaction)
      mutation.rollbackTransaction = InstantRuntime.rollbackTransaction(
        mutationID: mutation.id,
        prepared: prepared
      )
      mutation.optimisticOverlayState = .applied
      mutation.optimisticEffectReceiptVersion =
        PendingMutation.currentOptimisticEffectReceiptVersion
      _ = await fixtureStore.commitAndPublish(prepared)
      preparedMutations.append(mutation)
    }
  }

  var durableStore = await fixtureStore.snapshot()
  durableStore.attributes = baseStore.attributes
  return (durableStore, preparedMutations)
}

private func clearBoundedDeliveryMetadata(cacheURL: URL) throws {
  try executeBoundedOutboxSQL(
    """
    UPDATE instant_outbox
    SET delivery_state = NULL, delivery_metadata_version = 0;
    DELETE FROM instant_outbox_write_keys;
    """,
    cacheURL: cacheURL
  )
}

private func clearBoundedDeliveryMetadata(id: String, cacheURL: URL) throws {
  try executeBoundedOutboxSQL(
    """
    UPDATE instant_outbox
    SET delivery_state = NULL, delivery_metadata_version = 0,
        transport_step_count = NULL, encoded_body_bytes = NULL
    WHERE mutation_id = '\(id)';
    DELETE FROM instant_outbox_write_keys WHERE mutation_id = '\(id)';
    """,
    cacheURL: cacheURL
  )
}

private func restorePreBoundedDeliveryOutboxSchema(cacheURL: URL) throws {
  try executeBoundedOutboxSQL(
    """
    PRAGMA foreign_keys = OFF;
    DROP TABLE instant_outbox_write_keys;
    CREATE TABLE instant_outbox_pre_0012 (
      mutation_id TEXT PRIMARY KEY NOT NULL,
      status TEXT NOT NULL,
      created_at_ms INTEGER NOT NULL,
      json TEXT NOT NULL
    );
    INSERT INTO instant_outbox_pre_0012 (mutation_id, status, created_at_ms, json)
    SELECT
      mutation_id,
      status,
      created_at_ms,
      json_remove(json, '$.optimisticEffectReceiptVersion')
    FROM instant_outbox;
    DROP TABLE instant_outbox;
    ALTER TABLE instant_outbox_pre_0012 RENAME TO instant_outbox;
    -- The effect-entity table stays at its 0015 shape, including created_at_ms.
    -- Replay only migrations whose outbox columns or indexes were removed.
    DELETE FROM instant_schema_migrations
    WHERE name IN (
      '0012_bounded_outbox_delivery',
      '0013_outbox_supersession_lifecycle',
      '0014_outbox_optimistic_effects',
      '0016_failed_mutation_retry_window',
      '0017_bounded_server_apply',
      '0018_schema_failure_attribute_revision',
      '0019_projected_outbox_claim_bytes',
      '0020_outbox_optimistic_effect_receipt_fingerprint'
    );
    PRAGMA foreign_keys = ON;
    """,
    cacheURL: cacheURL
  )
}

private func restorePreReceiptAuthorityOutboxSchema(cacheURL: URL) throws {
  try executeBoundedOutboxSQL(
    """
    DROP INDEX IF EXISTS instant_outbox_synchronization_blocker_idx;
    ALTER TABLE instant_outbox DROP COLUMN optimistic_effect_receipt_fingerprint;
    ALTER TABLE instant_outbox DROP COLUMN delivery_claim_payload_fingerprint;
    ALTER TABLE instant_outbox DROP COLUMN server_acceptance_payload_fingerprint;
    DELETE FROM instant_schema_migrations
    WHERE name = '0020_outbox_optimistic_effect_receipt_fingerprint';
    """,
    cacheURL: cacheURL
  )
}

private func restorePreServerApplyAndReceiptAuthorityOutboxSchema(cacheURL: URL) throws {
  try executeBoundedOutboxSQL(
    """
    DROP INDEX IF EXISTS instant_outbox_synchronization_blocker_idx;
    DROP INDEX IF EXISTS instant_outbox_server_apply_watermark_idx;
    DROP INDEX IF EXISTS instant_outbox_server_apply_failed_idx;
    ALTER TABLE instant_outbox DROP COLUMN server_transaction_id;
    ALTER TABLE instant_outbox DROP COLUMN confirmation_source;
    ALTER TABLE instant_outbox DROP COLUMN failure_attribute_revision;
    ALTER TABLE instant_outbox DROP COLUMN delivery_claim_projected_body_bytes;
    ALTER TABLE instant_outbox DROP COLUMN optimistic_effect_receipt_fingerprint;
    ALTER TABLE instant_outbox DROP COLUMN delivery_claim_payload_fingerprint;
    ALTER TABLE instant_outbox DROP COLUMN server_acceptance_payload_fingerprint;
    DELETE FROM instant_schema_migrations
    WHERE name IN (
      '0017_bounded_server_apply',
      '0018_schema_failure_attribute_revision',
      '0019_projected_outbox_claim_bytes',
      '0020_outbox_optimistic_effect_receipt_fingerprint'
    );
    """,
    cacheURL: cacheURL
  )
}

private func corruptBoundedOutboxBody(id: String, cacheURL: URL) throws {
  try replaceBoundedOutboxBody(
    id: id,
    body: "{malformed-json",
    cacheURL: cacheURL
  )
}

private func replaceBoundedOutboxBody(
  id: String,
  body: String,
  cacheURL: URL
) throws {
  var database: OpaquePointer?
  guard sqlite3_open_v2(cacheURL.path, &database, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK else {
    defer { sqlite3_close(database) }
    throw boundedOutboxSQLiteError(database, operation: "open fault-injection database")
  }
  defer { sqlite3_close(database) }
  var statement: OpaquePointer?
  guard
    sqlite3_prepare_v2(
      database,
      "UPDATE instant_outbox SET json = ? WHERE mutation_id = ?",
      -1,
      &statement,
      nil
    ) == SQLITE_OK
  else {
    throw boundedOutboxSQLiteError(database, operation: "prepare body corruption")
  }
  defer { sqlite3_finalize(statement) }
  let bodyBindResult = body.withCString {
    sqlite3_bind_text(statement, 1, $0, -1, boundedOutboxSQLiteTransient)
  }
  let idBindResult = id.withCString {
    sqlite3_bind_text(statement, 2, $0, -1, boundedOutboxSQLiteTransient)
  }
  guard bodyBindResult == SQLITE_OK, idBindResult == SQLITE_OK,
    sqlite3_step(statement) == SQLITE_DONE
  else {
    throw boundedOutboxSQLiteError(database, operation: "replace outbox body")
  }
}

private func corruptBoundedOutboxBodies(ids: [String], cacheURL: URL) throws {
  for id in ids {
    try corruptBoundedOutboxBody(id: id, cacheURL: cacheURL)
  }
}

private func corruptBoundedOutboxLifecycle(id: String, cacheURL: URL) throws {
  var database: OpaquePointer?
  guard sqlite3_open_v2(cacheURL.path, &database, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK else {
    defer { sqlite3_close(database) }
    throw boundedOutboxSQLiteError(database, operation: "open lifecycle fault database")
  }
  defer { sqlite3_close(database) }
  var statement: OpaquePointer?
  guard
    sqlite3_prepare_v2(
      database,
      "UPDATE instant_outbox SET lifecycle_json = '{malformed-lifecycle' WHERE mutation_id = ?",
      -1,
      &statement,
      nil
    ) == SQLITE_OK
  else {
    throw boundedOutboxSQLiteError(database, operation: "prepare lifecycle corruption")
  }
  defer { sqlite3_finalize(statement) }
  let bindResult = id.withCString {
    sqlite3_bind_text(statement, 1, $0, -1, boundedOutboxSQLiteTransient)
  }
  guard bindResult == SQLITE_OK, sqlite3_step(statement) == SQLITE_DONE else {
    throw boundedOutboxSQLiteError(database, operation: "corrupt outbox lifecycle")
  }
}

private final class BoundedOutboxLockedClock: @unchecked Sendable {
  private let lock = NSLock()
  private var milliseconds: Int64

  init(milliseconds: Int64) {
    self.milliseconds = milliseconds
  }

  func now() -> InstantTimestamp {
    lock.withLock { InstantTimestamp(milliseconds: milliseconds) }
  }

  func advance(by delta: Int64) {
    lock.withLock { milliseconds += delta }
  }
}

private final class BoundedOutboxDiagnosticCounter: @unchecked Sendable {
  private let lock = NSLock()
  private var count = 0

  func increment() {
    lock.withLock { count += 1 }
  }

  var value: Int {
    lock.withLock { count }
  }
}

private actor BoundedOutboxReceiverEventGate {
  private let blockingEventOrdinal: Int
  private var acquiredEventCount = 0
  private var blockedEventContinuation: CheckedContinuation<Void, Never>?
  private var blockedEventWaiters: [UUID: CheckedContinuation<Void, Never>] = [:]

  init(blockingEventOrdinal: Int) {
    precondition(blockingEventOrdinal > 0)
    self.blockingEventOrdinal = blockingEventOrdinal
  }

  func eventAcquired() async {
    acquiredEventCount += 1
    guard acquiredEventCount == blockingEventOrdinal else { return }
    for waiter in blockedEventWaiters.values { waiter.resume() }
    blockedEventWaiters.removeAll()
    await withTaskCancellationHandler {
      await withCheckedContinuation { continuation in
        if Task.isCancelled {
          continuation.resume()
        } else {
          blockedEventContinuation = continuation
        }
      }
    } onCancel: {
      Task { await self.releaseBlockedEvent() }
    }
  }

  func waitUntilBlocked() async {
    guard acquiredEventCount < blockingEventOrdinal else { return }
    let waiterID = UUID()
    await withTaskCancellationHandler {
      await withCheckedContinuation { continuation in
        if Task.isCancelled {
          continuation.resume()
        } else {
          blockedEventWaiters[waiterID] = continuation
        }
      }
    } onCancel: {
      Task { await self.cancelBlockedEventWaiter(id: waiterID) }
    }
  }

  func releaseBlockedEvent() {
    blockedEventContinuation?.resume()
    blockedEventContinuation = nil
  }

  private func cancelBlockedEventWaiter(id: UUID) {
    blockedEventWaiters.removeValue(forKey: id)?.resume()
  }
}

private actor BoundedOutboxControlledSleep {
  private var recordedFirstDelay: UInt64?
  private var firstDelayContinuation: CheckedContinuation<Void, Error>?
  private var delayWaiters: [UUID: CheckedContinuation<Void, Never>] = [:]

  func sleep(milliseconds: UInt64) async throws {
    guard recordedFirstDelay == nil else { throw CancellationError() }
    recordedFirstDelay = milliseconds
    for waiter in delayWaiters.values { waiter.resume() }
    delayWaiters.removeAll()
    try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation {
        (continuation: CheckedContinuation<Void, Error>) in
        if Task.isCancelled {
          continuation.resume(throwing: CancellationError())
        } else {
          firstDelayContinuation = continuation
        }
      }
    } onCancel: {
      Task { await self.cancelFirstDelay() }
    }
  }

  func waitForFirstDelay() async {
    guard recordedFirstDelay == nil else { return }
    let waiterID = UUID()
    await withTaskCancellationHandler {
      await withCheckedContinuation { continuation in
        if Task.isCancelled {
          continuation.resume()
        } else {
          delayWaiters[waiterID] = continuation
        }
      }
    } onCancel: {
      Task { await self.cancelDelayWaiter(id: waiterID) }
    }
  }

  func firstDelay() -> UInt64? {
    recordedFirstDelay
  }

  func resumeFirstDelay() {
    firstDelayContinuation?.resume()
    firstDelayContinuation = nil
  }

  private func cancelFirstDelay() {
    firstDelayContinuation?.resume(throwing: CancellationError())
    firstDelayContinuation = nil
  }

  private func cancelDelayWaiter(id: UUID) {
    delayWaiters.removeValue(forKey: id)?.resume()
  }
}

// SAFETY: `lock` protects the completion bit shared by the test task and its
// observer. The probe deliberately has no asynchronous cleanup of its own.
private final class BoundedOutboxCompletionProbe: @unchecked Sendable {
  private let lock = NSLock()
  private var completed = false

  var didComplete: Bool {
    lock.withLock { completed }
  }

  func record() {
    lock.withLock { completed = true }
  }
}

// SAFETY: `lock` protects the one-shot continuation and every observation.
// Cancellation is recorded but intentionally does not resume the continuation,
// allowing tests to prove exact joins rather than cooperative cancellation.
private final class BoundedOutboxCancellationIgnoringSleep: @unchecked Sendable {
  private let lock = NSLock()
  private var entered = false
  private var milliseconds: UInt64?
  private var cancellations = 0
  private var isReleased = false
  private var continuation: CheckedContinuation<Void, Never>?

  var didEnter: Bool {
    lock.withLock { entered }
  }

  var requestedMilliseconds: UInt64? {
    lock.withLock { milliseconds }
  }

  var cancellationCount: Int {
    lock.withLock { cancellations }
  }

  func sleep(milliseconds: UInt64) async throws {
    lock.withLock {
      entered = true
      self.milliseconds = milliseconds
    }
    await withTaskCancellationHandler {
      await withCheckedContinuation { continuation in
        let resumeImmediately = lock.withLock { () -> Bool in
          guard !isReleased else { return true }
          self.continuation = continuation
          return false
        }
        if resumeImmediately {
          continuation.resume()
        }
      }
    } onCancel: {
      self.lock.withLock { self.cancellations += 1 }
    }
    try Task.checkCancellation()
  }

  func release() {
    let continuation = lock.withLock { () -> CheckedContinuation<Void, Never>? in
      guard !isReleased else { return nil }
      isReleased = true
      defer { self.continuation = nil }
      return self.continuation
    }
    continuation?.resume()
  }
}

// SAFETY: `lock` protects the one-shot run continuation, request, and counters.
// `releaseWithServerAcceptance` deliberately returns a successful response even
// after synchronous abort, proving that the exact owner durably dispositions an
// authoritative response before a timeout or close boundary can return.
private final class BoundedOutboxCancellationIgnoringPreparedTransport:
  @unchecked Sendable
{
  private let lock = NSLock()
  private var request: InstantMutationTransportRequest?
  private var entered = false
  private var isReleased = false
  private var continuation: CheckedContinuation<Void, Never>?
  private var aborts = 0
  private var runCompletions = 0

  var didEnter: Bool {
    lock.withLock { entered }
  }

  var abortCount: Int {
    lock.withLock { aborts }
  }

  var mutationIDs: [String] {
    lock.withLock { request?.mutations.map(\.mutationID) ?? [] }
  }

  var runCompletionCount: Int {
    lock.withLock { runCompletions }
  }

  func operation(
    for request: InstantMutationTransportRequest
  ) -> InstantMutationTransportOperation {
    InstantMutationTransportOperation(
      run: { try await self.run(request) },
      abort: { self.abort() }
    )
  }

  private func run(
    _ request: InstantMutationTransportRequest
  ) async throws -> InstantMutationTransportResponse {
    lock.withLock {
      self.request = request
      entered = true
    }
    await withCheckedContinuation { continuation in
      let resumeImmediately = lock.withLock { () -> Bool in
        guard !isReleased else { return true }
        self.continuation = continuation
        return false
      }
      if resumeImmediately {
        continuation.resume()
      }
    }
    lock.withLock { runCompletions += 1 }
    return InstantMutationTransportResponse(
      results: request.mutations.map {
        InstantMutationTransportResult(
          mutationID: $0.mutationID,
          outcome: .confirmed,
          acceptance: .serverAccepted
        )
      }
    )
  }

  private func abort() {
    lock.withLock { aborts += 1 }
  }

  func releaseWithServerAcceptance() {
    let continuation = lock.withLock { () -> CheckedContinuation<Void, Never>? in
      guard !isReleased else { return nil }
      isReleased = true
      defer { self.continuation = nil }
      return self.continuation
    }
    continuation?.resume()
  }
}

private actor BoundedOutboxExplicitFlushProbe {
  private let cacheURL: URL
  private var observed: [String: Bool] = [:]

  init(cacheURL: URL) {
    self.cacheURL = cacheURL
  }

  func observe(_ request: InstantMutationTransportRequest) throws {
    for id in ["tx-explicit-offer-00000", "tx-explicit-offer-00001"] {
      observed[id] = try boundedOutboxDeliveryStarted(id: id, cacheURL: cacheURL)
    }
    #expect(request.mutations.map(\.mutationID) == ["tx-explicit-offer-00000"])
  }

  func observedDeliveryStarted() -> [String: Bool] {
    observed
  }
}

private actor BoundedOutboxExplicitRequestProbe {
  private var requests: [InstantMutationTransportRequest] = []

  func record(_ request: InstantMutationTransportRequest) {
    requests.append(request)
  }

  func requestCount() -> Int {
    requests.count
  }
}

private actor BoundedOutboxSuspendedExplicitTransport {
  private var request: InstantMutationTransportRequest?
  private var responseContinuation:
    CheckedContinuation<InstantMutationTransportResponse, Never>?
  private var entryWaiters: [CheckedContinuation<Void, Never>] = []

  func send(_ request: InstantMutationTransportRequest) async
    -> InstantMutationTransportResponse
  {
    self.request = request
    for waiter in entryWaiters { waiter.resume() }
    entryWaiters.removeAll()
    // A checked continuation intentionally ignores Task cancellation. This
    // pins the runtime's hard-timeout + durable-renewal fence rather than the
    // cooperative behavior of Task.sleep.
    return await withCheckedContinuation { continuation in
      responseContinuation = continuation
    }
  }

  func waitUntilEntered() async {
    guard request == nil else { return }
    await withCheckedContinuation { continuation in
      entryWaiters.append(continuation)
    }
  }

  func resumeServerAccepted() {
    guard let request, let responseContinuation else { return }
    responseContinuation.resume(returning: InstantMutationTransportResponse(
      results: request.mutations.map {
        InstantMutationTransportResult(
          mutationID: $0.mutationID,
          outcome: .confirmed,
          acceptance: .serverAccepted
        )
      }
    ))
    self.responseContinuation = nil
  }

  func resumeFailed(message: String) {
    guard let request, let responseContinuation else { return }
    responseContinuation.resume(returning: InstantMutationTransportResponse(
      results: request.mutations.map {
        InstantMutationTransportResult(
          mutationID: $0.mutationID,
          outcome: .failed,
          message: message
        )
      }
    ))
    self.responseContinuation = nil
  }
}

private func requireAcceptedBoundedOutboxMutationUnchanged(
  _ expected: PendingMutation,
  acceptanceFingerprint: String,
  cacheURL: URL,
  persistence: SQLitePersistenceStore
) async throws {
  let state = try await persistence.loadState()
  let durable = try #require(
    state.snapshot.outbox.first { $0.id == expected.id }
  )
  expectNoDifference(durable, expected)
  expectNoDifference(
    try boundedOutboxServerAcceptanceFingerprint(id: expected.id, cacheURL: cacheURL),
    acceptanceFingerprint
  )
}

private func boundedOutboxServerAcceptanceFingerprint(
  id: String,
  cacheURL: URL
) throws -> String? {
  var database: OpaquePointer?
  guard sqlite3_open_v2(cacheURL.path, &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
    defer { sqlite3_close(database) }
    throw boundedOutboxSQLiteError(database, operation: "open acceptance probe database")
  }
  defer { sqlite3_close(database) }
  var statement: OpaquePointer?
  guard
    sqlite3_prepare_v2(
      database,
      """
      SELECT server_acceptance_payload_fingerprint
      FROM instant_outbox
      WHERE mutation_id = ?
      LIMIT 1
      """,
      -1,
      &statement,
      nil
    ) == SQLITE_OK
  else {
    throw boundedOutboxSQLiteError(database, operation: "prepare acceptance probe")
  }
  defer { sqlite3_finalize(statement) }
  let bindResult = id.withCString {
    sqlite3_bind_text(statement, 1, $0, -1, boundedOutboxSQLiteTransient)
  }
  guard bindResult == SQLITE_OK, sqlite3_step(statement) == SQLITE_ROW else {
    throw boundedOutboxSQLiteError(database, operation: "read acceptance proof")
  }
  return sqlite3_column_text(statement, 0).map(String.init(cString:))
}

private func boundedOutboxReceiptFingerprint(
  id: String,
  cacheURL: URL
) throws -> String? {
  try boundedOutboxOptionalText(
    column: "optimistic_effect_receipt_fingerprint",
    id: id,
    cacheURL: cacheURL
  )
}

private struct BoundedOutboxAuthorityRowSnapshot: Equatable {
  var mutationID: String
  var body: String
  var encodedBodyBytes: Int64?
  var receiptFingerprint: String?
  var claimFingerprint: String?
  var acceptanceFingerprint: String?
  var overlayIsActive: Bool
  var confirmationIsProven: Bool?
  var deliveryState: String?
  var mutationRevision: Int64
}

private func boundedOutboxAuthoritySnapshot(
  ids: [String],
  cacheURL: URL
) throws -> [BoundedOutboxAuthorityRowSnapshot] {
  var database: OpaquePointer?
  guard sqlite3_open_v2(cacheURL.path, &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
    defer { sqlite3_close(database) }
    throw boundedOutboxSQLiteError(database, operation: "open authority snapshot database")
  }
  defer { sqlite3_close(database) }

  return try ids.sorted().map { id in
    var statement: OpaquePointer?
    guard
      sqlite3_prepare_v2(
        database,
        """
        SELECT json, encoded_body_bytes,
               optimistic_effect_receipt_fingerprint,
               delivery_claim_payload_fingerprint,
               server_acceptance_payload_fingerprint,
               optimistic_overlay_active, confirmation_proven,
               delivery_state, mutation_revision
        FROM instant_outbox
        WHERE mutation_id = ?
        LIMIT 1
        """,
        -1,
        &statement,
        nil
      ) == SQLITE_OK
    else {
      throw boundedOutboxSQLiteError(database, operation: "prepare authority snapshot")
    }
    defer { sqlite3_finalize(statement) }
    let bindResult = id.withCString {
      sqlite3_bind_text(statement, 1, $0, -1, boundedOutboxSQLiteTransient)
    }
    guard bindResult == SQLITE_OK, sqlite3_step(statement) == SQLITE_ROW,
      let bodyBytes = sqlite3_column_text(statement, 0)
    else {
      throw boundedOutboxSQLiteError(database, operation: "read authority snapshot")
    }
    return BoundedOutboxAuthorityRowSnapshot(
      mutationID: id,
      body: String(cString: bodyBytes),
      encodedBodyBytes: sqlite3_column_type(statement, 1) == SQLITE_NULL
        ? nil
        : sqlite3_column_int64(statement, 1),
      receiptFingerprint: sqlite3_column_text(statement, 2).map(String.init(cString:)),
      claimFingerprint: sqlite3_column_text(statement, 3).map(String.init(cString:)),
      acceptanceFingerprint: sqlite3_column_text(statement, 4).map(String.init(cString:)),
      overlayIsActive: sqlite3_column_int64(statement, 5) != 0,
      confirmationIsProven: sqlite3_column_type(statement, 6) == SQLITE_NULL
        ? nil
        : sqlite3_column_int64(statement, 6) != 0,
      deliveryState: sqlite3_column_text(statement, 7).map(String.init(cString:)),
      mutationRevision: sqlite3_column_int64(statement, 8)
    )
  }
}

private func boundedOutboxMigrationLedgerCount(
  name: String,
  cacheURL: URL
) throws -> Int64 {
  var database: OpaquePointer?
  guard sqlite3_open_v2(cacheURL.path, &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
    defer { sqlite3_close(database) }
    throw boundedOutboxSQLiteError(database, operation: "open migration ledger database")
  }
  defer { sqlite3_close(database) }
  var statement: OpaquePointer?
  guard
    sqlite3_prepare_v2(
      database,
      "SELECT COUNT(*) FROM instant_schema_migrations WHERE name = ?",
      -1,
      &statement,
      nil
    ) == SQLITE_OK
  else {
    throw boundedOutboxSQLiteError(database, operation: "prepare migration ledger probe")
  }
  defer { sqlite3_finalize(statement) }
  let bindResult = name.withCString {
    sqlite3_bind_text(statement, 1, $0, -1, boundedOutboxSQLiteTransient)
  }
  guard bindResult == SQLITE_OK, sqlite3_step(statement) == SQLITE_ROW else {
    throw boundedOutboxSQLiteError(database, operation: "read migration ledger")
  }
  return sqlite3_column_int64(statement, 0)
}

private func boundedOutboxRawBody(id: String, cacheURL: URL) throws -> String? {
  var database: OpaquePointer?
  guard sqlite3_open_v2(cacheURL.path, &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
    defer { sqlite3_close(database) }
    throw boundedOutboxSQLiteError(database, operation: "open raw body database")
  }
  defer { sqlite3_close(database) }
  var statement: OpaquePointer?
  guard
    sqlite3_prepare_v2(
      database,
      "SELECT json FROM instant_outbox WHERE mutation_id = ? LIMIT 1",
      -1,
      &statement,
      nil
    ) == SQLITE_OK
  else {
    throw boundedOutboxSQLiteError(database, operation: "prepare raw body probe")
  }
  defer { sqlite3_finalize(statement) }
  let bindResult = id.withCString {
    sqlite3_bind_text(statement, 1, $0, -1, boundedOutboxSQLiteTransient)
  }
  guard bindResult == SQLITE_OK else {
    throw boundedOutboxSQLiteError(database, operation: "bind raw body probe")
  }
  let stepResult = sqlite3_step(statement)
  guard stepResult == SQLITE_ROW else {
    if stepResult == SQLITE_DONE { return nil }
    throw boundedOutboxSQLiteError(database, operation: "read raw body")
  }
  return sqlite3_column_text(statement, 0).map(String.init(cString:))
}

private func boundedOutboxOptimisticOverlayActive(
  id: String,
  cacheURL: URL
) throws -> Bool {
  var database: OpaquePointer?
  guard sqlite3_open_v2(cacheURL.path, &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
    defer { sqlite3_close(database) }
    throw boundedOutboxSQLiteError(database, operation: "open overlay probe database")
  }
  defer { sqlite3_close(database) }
  var statement: OpaquePointer?
  guard
    sqlite3_prepare_v2(
      database,
      "SELECT optimistic_overlay_active FROM instant_outbox WHERE mutation_id = ? LIMIT 1",
      -1,
      &statement,
      nil
    ) == SQLITE_OK
  else {
    throw boundedOutboxSQLiteError(database, operation: "prepare overlay probe")
  }
  defer { sqlite3_finalize(statement) }
  let bindResult = id.withCString {
    sqlite3_bind_text(statement, 1, $0, -1, boundedOutboxSQLiteTransient)
  }
  guard bindResult == SQLITE_OK, sqlite3_step(statement) == SQLITE_ROW else {
    throw boundedOutboxSQLiteError(database, operation: "read overlay activity")
  }
  return sqlite3_column_int64(statement, 0) != 0
}

private func boundedOutboxOptionalText(
  column: String,
  id: String,
  cacheURL: URL
) throws -> String? {
  precondition(
    ["optimistic_effect_receipt_fingerprint"].contains(column),
    "Only fixed test-owned column names may be interpolated."
  )
  var database: OpaquePointer?
  guard sqlite3_open_v2(cacheURL.path, &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
    defer { sqlite3_close(database) }
    throw boundedOutboxSQLiteError(database, operation: "open receipt probe database")
  }
  defer { sqlite3_close(database) }
  var statement: OpaquePointer?
  guard
    sqlite3_prepare_v2(
      database,
      "SELECT \(column) FROM instant_outbox WHERE mutation_id = ? LIMIT 1",
      -1,
      &statement,
      nil
    ) == SQLITE_OK
  else {
    throw boundedOutboxSQLiteError(database, operation: "prepare receipt probe")
  }
  defer { sqlite3_finalize(statement) }
  let bindResult = id.withCString {
    sqlite3_bind_text(statement, 1, $0, -1, boundedOutboxSQLiteTransient)
  }
  guard bindResult == SQLITE_OK, sqlite3_step(statement) == SQLITE_ROW else {
    throw boundedOutboxSQLiteError(database, operation: "read receipt proof")
  }
  return sqlite3_column_text(statement, 0).map(String.init(cString:))
}

private func boundedOutboxDeliveryStarted(id: String, cacheURL: URL) throws -> Bool {
  var database: OpaquePointer?
  guard sqlite3_open_v2(cacheURL.path, &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
    defer { sqlite3_close(database) }
    throw boundedOutboxSQLiteError(database, operation: "open explicit-flush probe database")
  }
  defer { sqlite3_close(database) }
  var statement: OpaquePointer?
  guard
    sqlite3_prepare_v2(
      database,
      "SELECT delivery_started FROM instant_outbox WHERE mutation_id = ? LIMIT 1",
      -1,
      &statement,
      nil
    ) == SQLITE_OK
  else {
    throw boundedOutboxSQLiteError(database, operation: "prepare explicit-flush probe")
  }
  defer { sqlite3_finalize(statement) }
  let bindResult = id.withCString {
    sqlite3_bind_text(statement, 1, $0, -1, boundedOutboxSQLiteTransient)
  }
  guard bindResult == SQLITE_OK, sqlite3_step(statement) == SQLITE_ROW else {
    throw boundedOutboxSQLiteError(database, operation: "read explicit-flush offer marker")
  }
  return sqlite3_column_int64(statement, 0) != 0
}

private func executeBoundedOutboxSQL(_ sql: String, cacheURL: URL) throws {
  var database: OpaquePointer?
  guard sqlite3_open_v2(cacheURL.path, &database, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK else {
    defer { sqlite3_close(database) }
    throw boundedOutboxSQLiteError(database, operation: "open metadata database")
  }
  defer { sqlite3_close(database) }
  guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else {
    throw boundedOutboxSQLiteError(database, operation: "clear delivery metadata")
  }
}

private func boundedOutboxQueryPlan(_ sql: String, cacheURL: URL) throws -> [String] {
  var database: OpaquePointer?
  guard sqlite3_open_v2(cacheURL.path, &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
    defer { sqlite3_close(database) }
    throw boundedOutboxSQLiteError(database, operation: "open query-plan database")
  }
  defer { sqlite3_close(database) }
  var statement: OpaquePointer?
  guard
    sqlite3_prepare_v2(
      database,
      "EXPLAIN QUERY PLAN \(sql)",
      -1,
      &statement,
      nil
    ) == SQLITE_OK
  else {
    throw boundedOutboxSQLiteError(database, operation: "prepare query plan")
  }
  defer { sqlite3_finalize(statement) }

  var details: [String] = []
  while true {
    switch sqlite3_step(statement) {
    case SQLITE_ROW:
      guard let detail = sqlite3_column_text(statement, 3) else {
        throw boundedOutboxSQLiteError(database, operation: "read query-plan detail")
      }
      details.append(String(cString: detail))
    case SQLITE_DONE:
      return details
    default:
      throw boundedOutboxSQLiteError(database, operation: "read query plan")
    }
  }
}

private func boundedOutboxSQLiteError(
  _ database: OpaquePointer?,
  operation: String
) -> NSError {
  NSError(
    domain: "InstantBoundedOutboxDeliveryTests",
    code: 1,
    userInfo: [
      NSLocalizedDescriptionKey: database.map { String(cString: sqlite3_errmsg($0)) }
        ?? "Could not \(operation)."
    ]
  )
}

private let boundedOutboxSQLiteTransient = unsafeBitCast(
  -1,
  to: sqlite3_destructor_type.self
)

private let boundedOutboxSource =
  "upstream Reactor.js pending-mutation order adapted to a fixed durable SQLite delivery window"
