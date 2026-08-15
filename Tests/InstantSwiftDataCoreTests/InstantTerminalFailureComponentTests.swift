import CustomDump
import Foundation
import SQLite3
import Testing

@testable import InstantSwiftDataCore

@Suite(.serialized)
struct InstantTerminalFailureComponentTests {
  @Test
  func footprintIncludesForwardRollbackAndReferenceTargets() throws {
    var mutation = terminalMutation(
      id: "target",
      position: 0,
      entityIDs: ["forward-source"]
    )
    mutation.transaction.operations = [
      .insert(terminalTriple(
        entityID: "forward-source",
        value: .ref("forward-target"),
        transactionID: mutation.id,
        milliseconds: 1
      ))
    ]
    mutation.rollbackTransaction = InstantStoreTransaction(
      id: "rollback-target",
      operations: [
        .retract(terminalTriple(
          entityID: "rollback-source",
          value: .ref("rollback-target"),
          transactionID: "rollback-target",
          milliseconds: 2
        ))
      ]
    )

    let footprint = try #require(InstantOptimisticEffectFootprint.normalized(for: mutation))

    expectNoDifference(
      footprint.entityIDs,
      ["forward-source", "forward-target", "rollback-source", "rollback-target"]
    )
    #expect(!footprint.isGlobal)
  }

  @Test
  func footprintIncludesConcretePreconditionsAndTreatsUnknownRulesAsGlobal() throws {
    var mutation = terminalMutation(id: "preconditions", position: 0, entityIDs: [])
    mutation.transaction.operations = [
      .requireEntityMissing(entityID: "missing-entity", namespace: "items"),
      .requireEntityExists(entityID: "existing-entity", namespace: "items"),
      .requireTripleExists(
        entityID: "triple-source",
        attributeID: "items/parent",
        value: .ref("triple-target")
      ),
    ]

    let concrete = try #require(InstantOptimisticEffectFootprint.normalized(for: mutation))

    expectNoDifference(
      concrete.entityIDs,
      ["existing-entity", "missing-entity", "triple-source", "triple-target"]
    )
    #expect(!concrete.isGlobal)

    mutation.transaction.operations.append(
      .ruleParams(entityID: "rule-entity", namespace: "items", params: .object([:]))
    )
    let rule = try #require(InstantOptimisticEffectFootprint.normalized(for: mutation))
    #expect(rule.isGlobal)

    mutation.transaction.operations = [
      .requireEntityExistsByLookup(
        InstantLookupRef(attributeID: "items/id", value: .string("lookup")),
        namespace: "items"
      )
    ]
    let lookup = try #require(InstantOptimisticEffectFootprint.normalized(for: mutation))
    #expect(lookup.isGlobal)
  }

  @Test
  func lookupEffectsAreGlobalAndRemovedOverlaysHaveNoFootprint() throws {
    var lookup = terminalMutation(id: "lookup", position: 0, entityIDs: ["ignored"])
    lookup.transaction.operations = [
      .deleteEntityByLookup(
        InstantLookupRef(
          attributeID: "items/id",
          value: .string("lookup")
        )
      )
    ]
    lookup.rollbackTransaction = nil
    lookup.optimisticOverlayState = .applied
    lookup.optimisticEffectReceiptVersion =
      PendingMutation.currentOptimisticEffectReceiptVersion
    let global = try #require(InstantOptimisticEffectFootprint.normalized(for: lookup))
    #expect(global.isGlobal)

    lookup.optimisticOverlayState = .removed
    let removed = try #require(InstantOptimisticEffectFootprint.normalized(for: lookup))
    expectNoDifference(removed.entityIDs, [])
    #expect(!removed.isGlobal)
  }

  @Test
  func tenThousandDisjointSuccessorsDecodeOnlyTargetAndCommitOnlyTarget() async throws {
    let target = terminalMutation(id: "target", position: 0, entityIDs: ["target-entity"])
    let successors = (1...10_000).map { index in
      terminalMutation(
        id: String(format: "successor-%05d", index),
        position: Int64(index),
        entityIDs: ["entity-\(index)"]
      )
    }
    let persistence = try await terminalPersistence(
      suffix: "ten-thousand-disjoint",
      mutations: [target] + successors
    )
    let state = try await persistence.loadCompactState()
    let claimToken = "target-claim"
    let didClaimTarget = try await persistence.claimOutboxMutationWithoutHydrationForTesting(
      id: target.id,
      claimantID: "terminal-test",
      claimToken: claimToken,
      deadlineMilliseconds: 5_000
    )
    #expect(didClaimTarget)
    await persistence.resetDecodedOutboxBodyCount()
    await persistence.resetTerminalFailureMetadataMetricsForTesting()

    let load = try await persistence.loadClaimedTerminalFailureComponent(
      id: target.id,
      claimToken: claimToken,
      expectedStoreRevision: state.storeRevision,
      expectedAttributeRevision: state.attributeRevision
    )
    let component = try #require(load.component)
    expectNoDifference(component.target.id, target.id)
    expectNoDifference(component.successors, [])
    expectNoDifference(component.decodedBodyCount, 1)
    let decodedBodyCountAfterLoad = await persistence.currentDecodedOutboxBodyCount()
    let queueWideReadCountAfterLoad = await persistence.localMutationQueueWideReadCountForTesting()
    let metadataMetricsAfterLoad =
      await persistence.terminalFailureMetadataMetricsForTesting()
    expectNoDifference(decodedBodyCountAfterLoad, 1)
    expectNoDifference(queueWideReadCountAfterLoad, 0)
    expectNoDifference(
      metadataMetricsAfterLoad,
      InstantTerminalFailureMetadataMetrics(
        outboxRowCount: 1,
        effectEntityRowCount: 1,
        maximumEntityFrontierRowCount: 0,
        entityFrontierSortCount: 0,
        entityFrontierFullScanStepCount: 0
      )
    )

    var failed = component.target
    failed.status = .failed
    failed.failureMessage = "permission denied"
    failed.failure = InstantMutationFailure(
      code: .permissionRejected,
      message: "permission denied"
    )
    failed.optimisticOverlayState = .removed
    failed.rollbackTransaction = nil
    let committed = try await persistence.commitClaimedTerminalFailure(
      targetID: target.id,
      claimToken: claimToken,
      expectedStoreRevision: component.expectedStoreRevision,
      expectedAttributeRevision: state.attributeRevision,
      expectedComponentRowRevisions: component.rowRevisions,
      expectedComponentIDs: component.ids,
      failedMutation: failed,
      rebasedSuccessors: [],
      changedEntityTriples: [:],
      metadataEntries: []
    )
    #expect(committed?.didChange == true)
    let targetRevision = try await persistence.outboxMutationRevisionForTesting(id: target.id)
    let lastSuccessorRevision = try await persistence.outboxMutationRevisionForTesting(
      id: successors.last!.id
    )
    let decodedBodyCountAfterCommit = await persistence.currentDecodedOutboxBodyCount()
    let queueWideReadCountAfterCommit =
      await persistence.localMutationQueueWideReadCountForTesting()
    let metadataMetricsAfterCommit =
      await persistence.terminalFailureMetadataMetricsForTesting()
    expectNoDifference(targetRevision, 2)
    expectNoDifference(lastSuccessorRevision, 1)
    expectNoDifference(decodedBodyCountAfterCommit, 1)
    expectNoDifference(queueWideReadCountAfterCommit, 0)
    expectNoDifference(
      metadataMetricsAfterCommit,
      InstantTerminalFailureMetadataMetrics(
        outboxRowCount: 2,
        effectEntityRowCount: 2,
        maximumEntityFrontierRowCount: 0,
        entityFrontierSortCount: 0,
        entityFrontierFullScanStepCount: 0
      )
    )
  }

  @Test
  func tenThousandSameEntitySuccessorsUseCoveredBoundedFrontier() async throws {
    let target = terminalMutation(id: "target", position: 0, entityIDs: ["shared"])
    let successors = (1...10_000).map { index in
      terminalMutation(
        id: String(format: "successor-%05d", index),
        position: Int64(index),
        entityIDs: ["shared"]
      )
    }
    let persistence = try await terminalPersistence(
      suffix: "ten-thousand-same-entity",
      mutations: [target] + successors
    )
    let state = try await persistence.loadCompactState()
    let didClaimTarget = try await persistence.claimOutboxMutationWithoutHydrationForTesting(
      id: target.id,
      claimantID: "terminal-test",
      claimToken: "target-claim",
      deadlineMilliseconds: 5_000
    )
    #expect(didClaimTarget)
    await persistence.resetDecodedOutboxBodyCount()
    await persistence.resetTerminalFailureMetadataMetricsForTesting()

    let load = try await persistence.loadClaimedTerminalFailureComponent(
      id: target.id,
      claimToken: "target-claim",
      expectedStoreRevision: state.storeRevision,
      expectedAttributeRevision: state.attributeRevision
    )

    expectNoDifference(load.componentLimitMutationCountAtLeast, 51)
    let decodedBodyCount = await persistence.currentDecodedOutboxBodyCount()
    expectNoDifference(decodedBodyCount, 0)
    let metrics = await persistence.terminalFailureMetadataMetricsForTesting()
    expectNoDifference(metrics.outboxRowCount, 51)
    expectNoDifference(metrics.effectEntityRowCount, 50)
    expectNoDifference(metrics.maximumEntityFrontierRowCount, 50)
    expectNoDifference(
      metrics.entityFrontierSortCount,
      0,
      "The covered effect-entity index must satisfy component order without a temp sort."
    )
    expectNoDifference(
      metrics.entityFrontierFullScanStepCount,
      0,
      "The same-entity frontier must seek the effect index instead of scanning the outbox."
    )
  }

  @Test
  func migrationBackfillsEffectEntityCreationOrder() async throws {
    let target = terminalMutation(id: "target", position: 10, entityIDs: ["A"])
    let successor = terminalMutation(id: "successor", position: 20, entityIDs: ["A", "B"])
    let persistence = try await terminalPersistence(
      suffix: "effect-entity-order-migration",
      mutations: [target, successor]
    )
    let fileURL = await persistence.fileURLForTesting()
    await persistence.simulateUnexpectedConnectionCloseForTesting()
    try executeTerminalSQL(
      at: fileURL,
      sql:
        """
        PRAGMA foreign_keys = OFF;
        DROP INDEX instant_outbox_effect_entities_lookup_idx;
        CREATE TABLE instant_outbox_effect_entities_pre_0015 (
          mutation_id TEXT NOT NULL,
          entity_id TEXT NOT NULL,
          PRIMARY KEY (mutation_id, entity_id),
          FOREIGN KEY (mutation_id) REFERENCES instant_outbox (mutation_id)
            ON DELETE CASCADE
        );
        INSERT INTO instant_outbox_effect_entities_pre_0015 (mutation_id, entity_id)
        SELECT mutation_id, entity_id FROM instant_outbox_effect_entities;
        DROP TABLE instant_outbox_effect_entities;
        ALTER TABLE instant_outbox_effect_entities_pre_0015
          RENAME TO instant_outbox_effect_entities;
        CREATE INDEX instant_outbox_effect_entities_lookup_idx
          ON instant_outbox_effect_entities (entity_id, mutation_id);
        DELETE FROM instant_schema_migrations
          WHERE name = '0015_outbox_effect_entity_order';
        PRAGMA foreign_keys = ON;
        """
    )

    let migrated = try SQLitePersistenceStore(fileURL: fileURL)
    try await migrated.bootstrap()

    expectNoDifference(
      try terminalInt64(
        at: fileURL,
        sql: "SELECT COUNT(*) FROM instant_outbox_effect_entities"
      ),
      3
    )
    expectNoDifference(
      try terminalInt64(
        at: fileURL,
        sql:
          """
          SELECT COUNT(*)
          FROM instant_outbox_effect_entities AS effects
          JOIN instant_outbox AS outbox ON outbox.mutation_id = effects.mutation_id
          WHERE effects.created_at_ms != outbox.created_at_ms
          """
      ),
      0
    )
    expectNoDifference(
      try terminalInt64(
        at: fileURL,
        sql:
          """
          SELECT COUNT(*)
          FROM pragma_index_info('instant_outbox_effect_entities_lookup_idx')
          WHERE (seqno = 0 AND name = 'entity_id')
             OR (seqno = 1 AND name = 'created_at_ms')
             OR (seqno = 2 AND name = 'mutation_id')
          """
      ),
      3
    )
  }

  @Test
  func transitiveComponentIncludesFailedActiveSuccessorButNotDisjointWork() async throws {
    let mutations = [
      terminalMutation(id: "target-A", position: 0, entityIDs: ["A"]),
      terminalMutation(id: "successor-A-B", position: 1, entityIDs: ["A", "B"]),
      terminalMutation(
        id: "successor-B-C-failed",
        position: 2,
        entityIDs: ["B", "C"],
        status: .failed
      ),
      terminalMutation(id: "successor-C", position: 3, entityIDs: ["C"]),
      terminalMutation(id: "successor-D", position: 4, entityIDs: ["D"]),
    ]
    let persistence = try await terminalPersistence(
      suffix: "transitive-component",
      mutations: mutations
    )
    let state = try await persistence.loadCompactState()
    let didClaimTarget = try await persistence.claimOutboxMutationWithoutHydrationForTesting(
      id: "target-A",
      claimantID: "terminal-test",
      claimToken: "claim-A",
      deadlineMilliseconds: 5_000
    )
    #expect(didClaimTarget)
    await persistence.resetDecodedOutboxBodyCount()

    let load = try await persistence.loadClaimedTerminalFailureComponent(
      id: "target-A",
      claimToken: "claim-A",
      expectedStoreRevision: state.storeRevision,
      expectedAttributeRevision: state.attributeRevision
    )
    let component = try #require(load.component)

    expectNoDifference(
      component.successors.map(\.id),
      ["successor-A-B", "successor-B-C-failed", "successor-C"]
    )
    expectNoDifference(component.decodedBodyCount, 4)
    let decodedBodyCount = await persistence.currentDecodedOutboxBodyCount()
    expectNoDifference(decodedBodyCount, 4)
    #expect(component.successors[1].status == .failed)
  }

  @Test
  func laterGlobalEffectConservativelyConnectsEveryActiveSuccessor() async throws {
    let target = terminalMutation(id: "target", position: 0, entityIDs: ["A"])
    let disjointBeforeGlobal = terminalMutation(
      id: "disjoint-before-global",
      position: 1,
      entityIDs: ["B"]
    )
    var global = terminalMutation(id: "global", position: 2, entityIDs: [])
    global.transaction.operations = [
      .ruleParams(entityID: "rule-entity", namespace: "items", params: .object([:]))
    ]
    global.rollbackTransaction = nil
    global.optimisticOverlayState = .applied
    global.optimisticEffectReceiptVersion =
      PendingMutation.currentOptimisticEffectReceiptVersion
    let disjointAfterGlobal = terminalMutation(
      id: "disjoint-after-global",
      position: 3,
      entityIDs: ["C"]
    )
    let persistence = try await terminalPersistence(
      suffix: "global-frontier",
      mutations: [target, disjointBeforeGlobal, global, disjointAfterGlobal]
    )
    let state = try await persistence.loadCompactState()
    let didClaimTarget = try await persistence.claimOutboxMutationWithoutHydrationForTesting(
      id: target.id,
      claimantID: "terminal-test",
      claimToken: "claim",
      deadlineMilliseconds: 5_000
    )
    #expect(didClaimTarget)
    await persistence.resetDecodedOutboxBodyCount()

    let load = try await persistence.loadClaimedTerminalFailureComponent(
      id: target.id,
      claimToken: "claim",
      expectedStoreRevision: state.storeRevision,
      expectedAttributeRevision: state.attributeRevision
    )
    let component = try #require(load.component)

    expectNoDifference(
      component.successors.map(\.id),
      ["disjoint-before-global", "global", "disjoint-after-global"]
    )
    expectNoDifference(component.decodedBodyCount, 4)
  }

  @Test
  func localConfirmationIsRejectableButServerProofIsAlreadyTerminal() async throws {
    var local = terminalMutation(id: "local", position: 0, entityIDs: ["local"])
    local.status = .confirmed
    local.confirmationSource = .manual
    let localPersistence = try await terminalPersistence(
      suffix: "local-confirmed",
      mutations: [local]
    )
    let localState = try await localPersistence.loadCompactState()
    let didClaimLocal = try await localPersistence.claimOutboxMutationWithoutHydrationForTesting(
      id: local.id,
      claimantID: "terminal-test",
      claimToken: "local-claim",
      deadlineMilliseconds: 5_000
    )
    #expect(didClaimLocal)
    let localLoad = try await localPersistence.loadClaimedTerminalFailureComponent(
      id: local.id,
      claimToken: "local-claim",
      expectedStoreRevision: localState.storeRevision,
      expectedAttributeRevision: localState.attributeRevision
    )
    #expect(localLoad.component?.target.status == .confirmed)

    let proven = terminalMutation(id: "proven", position: 0, entityIDs: ["proven"])
    let provenPersistence = try await terminalPersistence(
      suffix: "server-proven",
      mutations: [proven]
    )
    let acceptanceClaim = try await provenPersistence.claimAutomaticOutboxDeliveryWindow(
      InstantAutomaticOutboxClaimRequest(
        claimantID: "terminal-acceptance-runtime",
        claimToken: "terminal-acceptance-claim",
        now: InstantTimestamp(milliseconds: 10_000)
      )
    )
    expectNoDifference(acceptanceClaim.mutations.map(\.id), [proven.id])
    let acceptanceRevision = try await provenPersistence.currentOutboxRevision()
    let acceptance = try await provenPersistence.acceptOutboxMutation(
      id: proven.id,
      serverTransactionID: "server-1",
      claimantID: "terminal-acceptance-runtime",
      claimToken: "terminal-acceptance-claim",
      expectedOutboxRevision: acceptanceRevision
    )
    expectNoDifference(acceptance?.mutation?.status, .confirmed)
    let provenState = try await provenPersistence.loadCompactState()
    let didClaimProven = try await provenPersistence.claimOutboxMutationWithoutHydrationForTesting(
      id: proven.id,
      claimantID: "terminal-test",
      claimToken: "proven-claim",
      deadlineMilliseconds: 5_000
    )
    #expect(didClaimProven)
    let provenLoad = try await provenPersistence.loadClaimedTerminalFailureComponent(
      id: proven.id,
      claimToken: "proven-claim",
      expectedStoreRevision: provenState.storeRevision,
      expectedAttributeRevision: provenState.attributeRevision
    )
    #expect(provenLoad.isAlreadyTerminal)
  }

  @Test
  func staleClaimAndDuplicateTerminalLoadNoBodies() async throws {
    let target = terminalMutation(id: "target", position: 0, entityIDs: ["A"])
    let persistence = try await terminalPersistence(
      suffix: "stale-claim",
      mutations: [target]
    )
    let state = try await persistence.loadCompactState()
    let didClaimTarget = try await persistence.claimOutboxMutationWithoutHydrationForTesting(
      id: target.id,
      claimantID: "terminal-test",
      claimToken: "owned",
      deadlineMilliseconds: 5_000
    )
    #expect(didClaimTarget)
    await persistence.resetDecodedOutboxBodyCount()

    let stale = try await persistence.loadClaimedTerminalFailureComponent(
      id: target.id,
      claimToken: "stale",
      expectedStoreRevision: state.storeRevision,
      expectedAttributeRevision: state.attributeRevision
    )
    #expect(stale.isStaleClaim)
    let staleDecodedBodyCount = await persistence.currentDecodedOutboxBodyCount()
    expectNoDifference(staleDecodedBodyCount, 0)

    var failed = target
    failed.status = .failed
    try await persistence.saveOutbox([failed])
    let duplicateState = try await persistence.loadCompactState()
    await persistence.resetDecodedOutboxBodyCount()
    let duplicate = try await persistence.loadClaimedTerminalFailureComponent(
      id: target.id,
      claimToken: "owned",
      expectedStoreRevision: duplicateState.storeRevision,
      expectedAttributeRevision: duplicateState.attributeRevision
    )
    #expect(duplicate.isAlreadyTerminal)
    let duplicateDecodedBodyCount = await persistence.currentDecodedOutboxBodyCount()
    expectNoDifference(duplicateDecodedBodyCount, 0)
  }

  @Test
  func unknownSuccessorNormalizesBeforeComponentDecode() async throws {
    let target = terminalMutation(id: "target", position: 0, entityIDs: ["A"])
    let successor = terminalMutation(id: "successor", position: 1, entityIDs: ["A"])
    let persistence = try await terminalPersistence(
      suffix: "normalize-unknown",
      mutations: [target, successor]
    )
    try executeTerminalSQL(
      at: await persistence.fileURLForTesting(),
      sql:
        "UPDATE instant_outbox SET optimistic_effect_metadata_version = 0 WHERE mutation_id = 'successor'; DELETE FROM instant_outbox_effect_entities WHERE mutation_id = 'successor';"
    )
    await persistence.invalidateMemoryCache()
    let state = try await persistence.loadCompactState()
    let didClaimTarget = try await persistence.claimOutboxMutationWithoutHydrationForTesting(
      id: target.id,
      claimantID: "terminal-test",
      claimToken: "claim",
      deadlineMilliseconds: 5_000
    )
    #expect(didClaimTarget)
    await persistence.resetDecodedOutboxBodyCount()

    let blocked = try await persistence.loadClaimedTerminalFailureComponent(
      id: target.id,
      claimToken: "claim",
      expectedStoreRevision: state.storeRevision,
      expectedAttributeRevision: state.attributeRevision
    )
    expectNoDifference(blocked.normalizationRequiredMutationID, successor.id)
    let blockedDecodedBodyCount = await persistence.currentDecodedOutboxBodyCount()
    expectNoDifference(blockedDecodedBodyCount, 0)

    let normalization = try await persistence.normalizeOptimisticEffectMetadata(
      startingAtMutationID: successor.id
    )
    expectNoDifference(normalization.normalizedMutationIDs, [successor.id])
    #expect(normalization.blockedMutationID == nil)
    let ready = try await persistence.loadClaimedTerminalFailureComponent(
      id: target.id,
      claimToken: "claim",
      expectedStoreRevision: state.storeRevision,
      expectedAttributeRevision: state.attributeRevision
    )
    expectNoDifference(ready.component?.successors.map(\.id), [successor.id])
  }

  @Test
  func fiftyOneConnectedBodiesFailClosedBeforeDecode() async throws {
    let target = terminalMutation(id: "target", position: 0, entityIDs: ["A"])
    let successors = (1...50).map { index in
      terminalMutation(
        id: String(format: "successor-%02d", index),
        position: Int64(index),
        entityIDs: ["A"]
      )
    }
    let persistence = try await terminalPersistence(
      suffix: "component-over-limit",
      mutations: [target] + successors
    )
    let state = try await persistence.loadCompactState()
    let didClaimTarget = try await persistence.claimOutboxMutationWithoutHydrationForTesting(
      id: target.id,
      claimantID: "terminal-test",
      claimToken: "claim",
      deadlineMilliseconds: 5_000
    )
    #expect(didClaimTarget)
    await persistence.resetDecodedOutboxBodyCount()

    let load = try await persistence.loadClaimedTerminalFailureComponent(
      id: target.id,
      claimToken: "claim",
      expectedStoreRevision: state.storeRevision,
      expectedAttributeRevision: state.attributeRevision
    )
    expectNoDifference(load.componentLimitMutationCountAtLeast, 51)
    let decodedBodyCount = await persistence.currentDecodedOutboxBodyCount()
    expectNoDifference(decodedBodyCount, 0)
  }

  @Test
  func componentOverEightMiBFailsClosedBeforeDecode() async throws {
    let target = terminalMutation(id: "target", position: 0, entityIDs: ["A"])
    let successor = terminalMutation(id: "successor", position: 1, entityIDs: ["A"])
    let persistence = try await terminalPersistence(
      suffix: "component-byte-limit",
      mutations: [target, successor]
    )
    try executeTerminalSQL(
      at: await persistence.fileURLForTesting(),
      sql:
        "UPDATE instant_outbox SET encoded_body_bytes = \(8 * 1_024 * 1_024) WHERE mutation_id = 'target'; UPDATE instant_outbox SET encoded_body_bytes = 1 WHERE mutation_id = 'successor';"
    )
    await persistence.invalidateMemoryCache()
    let state = try await persistence.loadCompactState()
    let didClaimTarget = try await persistence.claimOutboxMutationWithoutHydrationForTesting(
      id: target.id,
      claimantID: "terminal-test",
      claimToken: "claim",
      deadlineMilliseconds: 5_000
    )
    #expect(didClaimTarget)
    await persistence.resetDecodedOutboxBodyCount()

    let load = try await persistence.loadClaimedTerminalFailureComponent(
      id: target.id,
      claimToken: "claim",
      expectedStoreRevision: state.storeRevision,
      expectedAttributeRevision: state.attributeRevision
    )
    let encodedBodyByteCountAtLeast = try #require(
      load.componentLimitEncodedBodyByteCountAtLeast
    )
    #expect(encodedBodyByteCountAtLeast > 8 * 1_024 * 1_024)
    let decodedBodyCount = await persistence.currentDecodedOutboxBodyCount()
    expectNoDifference(decodedBodyCount, 0)
  }

  @Test
  func commitReprovesTheExactComponentClosure() async throws {
    let target = terminalMutation(id: "target", position: 0, entityIDs: ["A"])
    let successor = terminalMutation(id: "successor", position: 1, entityIDs: ["B"])
    let persistence = try await terminalPersistence(
      suffix: "component-closure-cas",
      mutations: [target, successor]
    )
    let state = try await persistence.loadCompactState()
    let didClaimTarget = try await persistence.claimOutboxMutationWithoutHydrationForTesting(
      id: target.id,
      claimantID: "terminal-test",
      claimToken: "claim",
      deadlineMilliseconds: 5_000
    )
    #expect(didClaimTarget)
    let load = try await persistence.loadClaimedTerminalFailureComponent(
      id: target.id,
      claimToken: "claim",
      expectedStoreRevision: state.storeRevision,
      expectedAttributeRevision: state.attributeRevision
    )
    let component = try #require(load.component)
    expectNoDifference(component.successors, [])

    try executeTerminalSQL(
      at: await persistence.fileURLForTesting(),
      sql:
        "INSERT INTO instant_outbox_effect_entities (mutation_id, entity_id, created_at_ms) VALUES ('successor', 'A', 1);"
    )
    var failed = component.target
    failed.status = .failed
    failed.failureMessage = "permission denied"
    failed.failure = InstantMutationFailure(
      code: .permissionRejected,
      message: "permission denied"
    )
    failed.optimisticOverlayState = .removed
    failed.rollbackTransaction = nil
    let committed = try await persistence.commitClaimedTerminalFailure(
      targetID: target.id,
      claimToken: "claim",
      expectedStoreRevision: component.expectedStoreRevision,
      expectedAttributeRevision: state.attributeRevision,
      expectedComponentRowRevisions: component.rowRevisions,
      expectedComponentIDs: component.ids,
      failedMutation: failed,
      rebasedSuccessors: [],
      changedEntityTriples: [:],
      metadataEntries: []
    )
    #expect(committed == nil)
    let targetRevision = try await persistence.outboxMutationRevisionForTesting(id: target.id)
    expectNoDifference(targetRevision, 1)
  }
}

private extension InstantTerminalFailureComponentLoad {
  var component: InstantTerminalFailureComponent? {
    guard case let .ready(component) = self else { return nil }
    return component
  }

  var isAlreadyTerminal: Bool {
    if case .alreadyTerminal = self { return true }
    return false
  }

  var isStaleClaim: Bool {
    if case .staleClaim = self { return true }
    return false
  }

  var normalizationRequiredMutationID: String? {
    guard case let .normalizationRequired(mutationID) = self else { return nil }
    return mutationID
  }

  var componentLimitMutationCountAtLeast: Int? {
    guard case let .componentLimitExceeded(mutationCountAtLeast, _) = self else { return nil }
    return mutationCountAtLeast
  }

  var componentLimitEncodedBodyByteCountAtLeast: Int? {
    guard case let .componentLimitExceeded(_, encodedBodyByteCountAtLeast) = self else {
      return nil
    }
    return encodedBodyByteCountAtLeast
  }
}

private func terminalPersistence(
  suffix: String,
  mutations: [PendingMutation]
) async throws -> SQLitePersistenceStore {
  let persistence = try SQLitePersistenceStore(
    fileURL: FileManager.default.temporaryDirectory.appendingPathComponent(
      "instant-terminal-component-\(suffix)-\(UUID().uuidString).sqlite"
    )
  )
  try await persistence.bootstrap()
  let emptyStore = try await persistence.loadCompactState()
  let didSeedRuntimePreparedOutbox = try await persistence.saveOutbox(
    mutations,
    replacing: [],
    metadataEntries: [],
    expectedStoreRevision: emptyStore.storeRevision,
    expectedOutboxRevision: emptyStore.outboxRevision
  )
  expectNoDifference(didSeedRuntimePreparedOutbox, true)
  return persistence
}

private func terminalMutation(
  id: String,
  position: Int64,
  entityIDs: [String],
  status: InstantMutationStatus = .pending
) -> PendingMutation {
  let timestamp = InstantTimestamp(milliseconds: position + 1)
  let operations = entityIDs.map { entityID in
    InstantTripleOperation.insert(
      terminalTriple(
        entityID: entityID,
        value: .string(id),
        transactionID: id,
        milliseconds: timestamp.milliseconds
      )
    )
  }
  var mutation = PendingMutation(
    id: id,
    createdAt: InstantTimestamp(milliseconds: position),
    transaction: InstantStoreTransaction(id: id, operations: operations),
    status: status,
    failureMessage: status == .failed ? "retained failure" : nil
  )
  mutation.rollbackTransaction = InstantStoreTransaction(
    id: "rollback-\(id)",
    operations: operations.map { operation in
      guard case let .insert(triple) = operation else { return operation }
      return .retract(triple)
    }
  )
  if mutation.rollbackTransaction?.operations.isEmpty == false {
    mutation.optimisticOverlayState = .applied
  } else {
    mutation.rollbackTransaction = nil
    mutation.optimisticOverlayState = .applied
  }
  mutation.optimisticEffectReceiptVersion =
    PendingMutation.currentOptimisticEffectReceiptVersion
  return mutation
}

private func terminalTriple(
  entityID: String,
  value: InstantValue,
  transactionID: String,
  milliseconds: Int64
) -> InstantTriple {
  InstantTriple(
    entityID: entityID,
    attributeID: "items/value",
    value: value,
    txID: transactionID,
    txTime: InstantTimestamp(milliseconds: milliseconds)
  )
}

private func executeTerminalSQL(at url: URL, sql: String) throws {
  var database: OpaquePointer?
  guard sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK else {
    defer { sqlite3_close(database) }
    throw InstantError(
      code: .persistenceFailed,
      operation: "open terminal rejection test database",
      message: "SQLite could not open the test database.",
      recovery: "Inspect the test database path."
    )
  }
  defer { sqlite3_close(database) }
  guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else {
    throw InstantError(
      code: .persistenceFailed,
      operation: "mutate terminal rejection test database",
      message: database.flatMap(sqlite3_errmsg).map(String.init(cString:)) ?? "SQLite failed.",
      recovery: "Inspect the test SQL."
    )
  }
}

private func terminalInt64(at url: URL, sql: String) throws -> Int64 {
  var database: OpaquePointer?
  guard sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
    defer { sqlite3_close(database) }
    throw InstantError(
      code: .persistenceFailed,
      operation: "open terminal rejection test database",
      message: "SQLite could not open the test database.",
      recovery: "Inspect the test database path."
    )
  }
  defer { sqlite3_close(database) }
  var statement: OpaquePointer?
  guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
    throw InstantError(
      code: .persistenceFailed,
      operation: "prepare terminal rejection test query",
      message: database.flatMap(sqlite3_errmsg).map(String.init(cString:)) ?? "SQLite failed.",
      recovery: "Inspect the test SQL."
    )
  }
  defer { sqlite3_finalize(statement) }
  guard sqlite3_step(statement) == SQLITE_ROW else {
    throw InstantError(
      code: .persistenceFailed,
      operation: "run terminal rejection test query",
      message: database.flatMap(sqlite3_errmsg).map(String.init(cString:)) ?? "SQLite failed.",
      recovery: "Inspect the test SQL."
    )
  }
  return sqlite3_column_int64(statement, 0)
}
