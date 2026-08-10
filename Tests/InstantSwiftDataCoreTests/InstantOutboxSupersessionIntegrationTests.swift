import CustomDump
import Foundation
import SQLite3
import Testing
@testable import InstantSwiftDataCore

@Suite(.serialized)
struct InstantOutboxSupersessionIntegrationTests {
  private let attributes: [InstantAttribute] = [
    .primaryKey(namespace: "supersession_items"),
    InstantAttribute(
      id: "supersession_items/value",
      namespace: "supersession_items",
      name: "value",
      valueType: .string
    ),
  ]

  @Test
  func immediateTailClassifierAcceptsExactConcreteInsertShape() {
    let predecessor = mutation(id: "older", value: "one", timestamp: 1)
    let newcomer = mutation(id: "newer", value: "two", timestamp: 2)

    #expect(
      OutboxSameEntitySupersession.canReplaceImmediateTail(
        predecessor,
        with: newcomer,
        attributes: attributes
      )
    )
  }

  @Test(
    arguments: [
      InstantTripleOperation.retract(
        InstantTriple(
          entityID: "item",
          attributeID: "supersession_items/value",
          value: .string("one"),
          txID: "newer",
          txTime: InstantTimestamp(milliseconds: 2)
        )
      ),
      .merge(
        InstantTriple(
          entityID: "item",
          attributeID: "supersession_items/value",
          value: .string("two"),
          txID: "newer",
          txTime: InstantTimestamp(milliseconds: 2)
        )
      ),
      .deleteEntity("item"),
      .requireEntityExists(entityID: "item", namespace: "supersession_items"),
      .insertByLookup(
        entity: InstantLookupRef(
          attributeID: "supersession_items/id",
          value: .string("item")
        ),
        attributeID: "supersession_items/value",
        value: .string("two"),
        txID: "newer",
        txTime: InstantTimestamp(milliseconds: 2)
      ),
    ]
  )
  func immediateTailClassifierRejectsNonInsertOperations(
    operation: InstantTripleOperation
  ) {
    let predecessor = mutation(id: "older", value: "one", timestamp: 1)
    var newcomer = mutation(id: "newer", value: "two", timestamp: 2)
    newcomer.transaction.operations.append(operation)

    #expect(
      !OutboxSameEntitySupersession.canReplaceImmediateTail(
        predecessor,
        with: newcomer,
        attributes: attributes
      )
    )
  }

  @Test
  func immediateTailClassifierRejectsPartialOlderOrNonMonotonicShape() {
    let predecessor = mutation(id: "older", value: "one", timestamp: 2)
    var partial = mutation(id: "partial", value: "two", timestamp: 3)
    partial.transaction.operations.removeFirst()
    let olderTimestamp = mutation(id: "clock-regression", value: "three", timestamp: 1)

    #expect(
      !OutboxSameEntitySupersession.canReplaceImmediateTail(
        predecessor,
        with: partial,
        attributes: attributes
      )
    )
    #expect(
      !OutboxSameEntitySupersession.canReplaceImmediateTail(
        predecessor,
        with: olderTimestamp,
        attributes: attributes
      )
    )
  }

  @Test
  func immediateTailClassifierRequiresStrictDurableCreationOrderAndDistinctIDs() {
    let predecessor = mutation(id: "tail-z", value: "one", timestamp: 2)
    let lowerIDAtSameTime = mutation(id: "tail-a", value: "two", timestamp: 2)
    let higherIDAtSameTime = mutation(id: "tail-zz", value: "three", timestamp: 2)
    let reusedID = mutation(id: "tail-z", value: "four", timestamp: 3)

    #expect(
      !OutboxSameEntitySupersession.canReplaceImmediateTail(
        predecessor,
        with: lowerIDAtSameTime,
        attributes: attributes
      )
    )
    #expect(
      OutboxSameEntitySupersession.canReplaceImmediateTail(
        predecessor,
        with: higherIDAtSameTime,
        attributes: attributes
      )
    )
    #expect(
      !OutboxSameEntitySupersession.canReplaceImmediateTail(
        predecessor,
        with: reusedID,
        attributes: attributes
      )
    )
  }

  @Test
  func immediateTailClassifierRejectsMissingOrMismatchedPrimaryKey() {
    let predecessor = mutation(id: "older", value: "one", timestamp: 1)
    var missing = mutation(id: "missing", value: "two", timestamp: 2)
    missing.transaction.operations.removeFirst()
    var mismatched = mutation(id: "mismatched", value: "two", timestamp: 2)
    guard case let .insert(primaryKeyTriple) = mismatched.transaction.operations[0] else {
      Issue.record("Expected a primary-key insert fixture.")
      return
    }
    var wrongPrimaryKey = primaryKeyTriple
    wrongPrimaryKey.value = .string("different-entity")
    mismatched.transaction.operations[0] = .insert(wrongPrimaryKey)

    #expect(
      !OutboxSameEntitySupersession.canReplaceImmediateTail(
        predecessor,
        with: missing,
        attributes: attributes
      )
    )
    #expect(
      !OutboxSameEntitySupersession.canReplaceImmediateTail(
        predecessor,
        with: mismatched,
        attributes: attributes
      )
    )
  }

  @Test
  func immediateTailClassifierRejectsReferenceAndCardinalityManyAttributes() {
    let referenceAttributes = attributes + [
      InstantAttribute(
        id: "supersession_items/owner",
        namespace: "supersession_items",
        name: "owner",
        valueType: .ref
      )
    ]
    let manyAttributes = attributes + [
      InstantAttribute(
        id: "supersession_items/tag",
        namespace: "supersession_items",
        name: "tag",
        valueType: .string,
        cardinality: .many
      )
    ]
    let predecessor = mutation(id: "older", value: "one", timestamp: 1)
    var reference = mutation(id: "reference", value: "two", timestamp: 2)
    reference.transaction.operations.append(
      .insert(
        InstantTriple(
          entityID: "item",
          attributeID: "supersession_items/owner",
          value: .ref("person"),
          txID: "reference",
          txTime: InstantTimestamp(milliseconds: 2)
        )
      )
    )
    var referencePredecessor = predecessor
    referencePredecessor.transaction.operations.append(
      .insert(
        InstantTriple(
          entityID: "item",
          attributeID: "supersession_items/owner",
          value: .ref("old-person"),
          txID: "older",
          txTime: InstantTimestamp(milliseconds: 1)
        )
      )
    )
    var many = mutation(id: "many", value: "two", timestamp: 2)
    many.transaction.operations.append(
      .insert(
        InstantTriple(
          entityID: "item",
          attributeID: "supersession_items/tag",
          value: .string("tag"),
          txID: "many",
          txTime: InstantTimestamp(milliseconds: 2)
        )
      )
    )
    var manyPredecessor = predecessor
    manyPredecessor.transaction.operations.append(
      .insert(
        InstantTriple(
          entityID: "item",
          attributeID: "supersession_items/tag",
          value: .string("old-tag"),
          txID: "older",
          txTime: InstantTimestamp(milliseconds: 1)
        )
      )
    )

    #expect(
      !OutboxSameEntitySupersession.canReplaceImmediateTail(
        referencePredecessor,
        with: reference,
        attributes: referenceAttributes
      )
    )
    #expect(
      !OutboxSameEntitySupersession.canReplaceImmediateTail(
        manyPredecessor,
        with: many,
        attributes: manyAttributes
      )
    )
  }

  @Test
  func immediateTailClassifierTreatsUnrelatedEntityAsBarrier() {
    let predecessor = mutation(id: "older", entityID: "item-a", value: "one", timestamp: 1)
    let newcomer = mutation(id: "newer", entityID: "item-b", value: "two", timestamp: 2)

    #expect(
      !OutboxSameEntitySupersession.canReplaceImmediateTail(
        predecessor,
        with: newcomer,
        attributes: attributes
      )
    )
  }

  @Test
  func tenThousandOfflineUpsertsKeepOneDurableSurvivorAcrossRestartAndConnect()
    async throws
  {
    let cacheURL = temporaryCacheURL("ten-thousand")
    let runtime = try await makeOfflineRuntime(cacheURL: cacheURL)

    for index in 0..<10_000 {
      let id = String(format: "supersession-%05d", index)
      let timestamp = Int64(index + 1)
      _ = try await runtime.transact(
        integrationTransaction(id: id, value: "value-\(index)", timestamp: timestamp),
        createdAt: InstantTimestamp(milliseconds: timestamp)
      )
    }

    let durableCount = try await runtime.persistence.countOutboxMutations()
    let residentCount = await runtime.mutationDeliveryBarrierMutations().count
    let queueWideReads = await runtime.persistence.localMutationQueueWideReadCountForTesting()
    let lifecycleCounts = try await runtime.persistence.outboxLifecycleCountsForTesting()
    let maximumAliasMetadataByteCount = try await runtime.persistence
      .maximumOutboxLifecycleAliasMetadataByteCountForTesting()
    expectNoDifference(durableCount, 1)
    #expect(residentCount <= 1)
    expectNoDifference(queueWideReads, 0)
    expectNoDifference(lifecycleCounts.lifecycles, 1)
    expectNoDifference(lifecycleCounts.aliases, 10_000)
    #expect(
      maximumAliasMetadataByteCount <= 64,
      "Aliases retain only the two fixed identity strings, never historical mutation bodies."
    )

    let durableState = try await runtime.persistence.loadState()
    let durable = try #require(durableState.snapshot.outbox.first)
    expectNoDifference(durable.id, "supersession-09999")
    expectNoDifference(integrationValue(in: durable.transaction), "value-9999")
    #expect((durable.rollbackTransaction?.operations.count ?? 0) <= 1)

    let reopened = try await makeOfflineRuntime(cacheURL: cacheURL)
    let reopenedCount = try await reopened.persistence.countOutboxMutations()
    let startupLifecycleDecodes =
      await reopened.persistence.currentDecodedOutboxLifecycleCount()
    let reopenedState = try await reopened.persistence.loadState()
    let reopenedDurable = try #require(reopenedState.snapshot.outbox.first)
    expectNoDifference(reopenedCount, 1)
    expectNoDifference(
      startupLifecycleDecodes,
      0,
      "Cold bootstrap retains lifecycle rows in SQLite; it does not mirror or decode them."
    )
    expectNoDifference(reopenedDurable.id, "supersession-09999")
    expectNoDifference(integrationValue(in: reopenedDurable.transaction), "value-9999")

    let liveSession = LiveReactorParitySession(messages: [
      liveReactorInitOK(attrs: liveReactorTodoServerAttrs)
    ])
    var liveConfiguration = InstantRuntimeConfiguration(
      appID: "supersession-ten-thousand-live",
      persistenceURL: cacheURL,
      initialAttributes: TodoExample.attributes
    )
    liveConfiguration.liveTransport = liveSession.transport
    liveConfiguration.autoConnectLiveTransport = false
    let liveRuntime = try await InstantRuntime.bootstrap(configuration: liveConfiguration)
    _ = try await liveRuntime.connect()
    try await instantLiveWithTimeout(
      operation: "wait for supersession survivor delivery",
      timeoutMilliseconds: 5_000
    ) {
      await liveSession.waitForSentMessageCount(2)
    }
    let sentIDs = await liveSession.sentMessages()
      .filter { $0.op == "transact" }
      .compactMap(\.clientEventID)
    expectNoDifference(sentIDs, ["supersession-09999"])
    _ = try? await liveRuntime.closeConnection()
  }

  @Test
  func tenThousandPartialWritesNeverMaterializeImmediateTailBodies() async throws {
    let runtime = try await makeOfflineRuntime(
      cacheURL: temporaryCacheURL("ten-thousand-ineligible")
    )
    _ = try await runtime.transact(
      integrationTransaction(id: "complete-tail", value: "baseline", timestamp: 1),
      createdAt: InstantTimestamp(milliseconds: 1)
    )
    await runtime.persistence.resetDecodedOutboxBodyCount()

    for index in 0..<10_000 {
      let timestamp = Int64(index + 2)
      let id = String(format: "partial-%05d", index)
      _ = try await runtime.transact(
        partialIntegrationTransaction(id: id, value: "value-\(index)", timestamp: timestamp),
        createdAt: InstantTimestamp(milliseconds: timestamp)
      )
    }

    let decodedBodyCount = await runtime.persistence.currentDecodedOutboxBodyCount()
    let materializedBodyCount = await runtime.persistence.currentMaterializedOutboxBodyCount()
    let durableCount = try await runtime.persistence.countOutboxMutations()
    let queueWideReadCount =
      await runtime.persistence.localMutationQueueWideReadCountForTesting()
    expectNoDifference(
      decodedBodyCount,
      0,
      "A newcomer without its primary-key assignment must be rejected before tail decode."
    )
    expectNoDifference(
      materializedBodyCount,
      0,
      "Ineligible newcomers must not even SELECT the durable tail JSON into Swift memory."
    )
    expectNoDifference(durableCount, 10_001)
    expectNoDifference(queueWideReadCount, 0)
  }

  @Test
  func supersededTransactionIDRemainsAnImmutableReservationBeforeAndAfterPrune()
    async throws
  {
    let cacheURL = temporaryCacheURL("alias-idempotence")
    let runtime = try await makeOfflineRuntime(cacheURL: cacheURL)
    let predecessor = integrationTransaction(id: "older", value: "one", timestamp: 1)
    let survivor = integrationTransaction(id: "newer", value: "two", timestamp: 2)
    _ = try await runtime.transact(
      predecessor,
      createdAt: InstantTimestamp(milliseconds: 1)
    )
    _ = try await runtime.transact(
      survivor,
      createdAt: InstantTimestamp(milliseconds: 2)
    )

    do {
      _ = try await runtime.transact(
        predecessor,
        createdAt: InstantTimestamp(milliseconds: 1)
      )
      Issue.record("Expected an exact retry of a superseded transaction id to be rejected.")
    } catch let error as InstantError {
      expectNoDifference(error.code, .validationFailed)
      expectNoDifference(error.operation, "transact")
      expectNoDifference(error.localID, predecessor.id)
      #expect(error.message.contains("permanently reserved"))
      #expect(error.message.contains("pending"))
    }
    var durable = try await runtime.persistence.loadState().snapshot.outbox
    expectNoDifference(durable.map(\.id), [survivor.id])
    expectNoDifference(integrationValue(in: durable[0].transaction), "two")
    let predecessorPublication = try await runtime.persistence
      .mutationLifecyclePublicationIdentity(for: predecessor.id)
    let survivorPublication = try await runtime.persistence
      .mutationLifecyclePublicationIdentity(for: survivor.id)
    #expect(predecessorPublication == nil)
    expectNoDifference(survivorPublication, predecessor.id)

    let conflictingReuse = integrationTransaction(
      id: predecessor.id,
      value: "different-intent",
      timestamp: 3
    )
    do {
      _ = try await runtime.transact(
        conflictingReuse,
        createdAt: InstantTimestamp(milliseconds: 3)
      )
      Issue.record("Expected a superseded transaction id with different intent to be rejected.")
    } catch let error as InstantError {
      expectNoDifference(error.code, .validationFailed)
      expectNoDifference(error.operation, "transact")
      expectNoDifference(error.localID, predecessor.id)
    }
    durable = try await runtime.persistence.loadState().snapshot.outbox
    expectNoDifference(durable.map(\.id), [survivor.id])

    let lifecycle = try await runtime.observeMutationLifecycle(id: predecessor.id)
    var iterator = lifecycle.makeAsyncIterator()
    let initialLifecycle = await iterator.next()
    expectNoDifference(initialLifecycle, .waiting)
    _ = try await runtime.acceptMutationIfPresent(
      id: survivor.id,
      serverTransactionID: "42"
    )
    guard case let .serverAccepted(accepted) = await iterator.next() else {
      Issue.record("Expected the immutable predecessor alias to observe survivor acceptance.")
      return
    }
    expectNoDifference(accepted.id, survivor.id)
    _ = try await runtime.applyServerTransaction(
      InstantStoreTransaction(id: "43", operations: []),
      processedTransactionID: "43"
    )
    let prunedCount = try await runtime.persistence.countOutboxMutations()
    expectNoDifference(prunedCount, 0)

    let reopened = try await makeOfflineRuntime(cacheURL: cacheURL)
    do {
      _ = try await reopened.transact(
        predecessor,
        createdAt: InstantTimestamp(milliseconds: 1)
      )
      Issue.record("Expected a completed supersession alias to reject transaction-id reuse.")
    } catch let error as InstantError {
      expectNoDifference(error.code, .validationFailed)
      expectNoDifference(error.operation, "transact")
      expectNoDifference(error.localID, predecessor.id)
      #expect(error.message.contains("permanently reserved"))
      #expect(error.message.contains("completed"))
    }
    let reopenedCount = try await reopened.persistence.countOutboxMutations()
    let reopenedPredecessorPublication = try await reopened.persistence
      .mutationLifecyclePublicationIdentity(for: predecessor.id)
    let reopenedSurvivorPublication = try await reopened.persistence
      .mutationLifecyclePublicationIdentity(for: survivor.id)
    expectNoDifference(reopenedCount, 0)
    #expect(reopenedPredecessorPublication == nil)
    expectNoDifference(reopenedSurvivorPublication, predecessor.id)
    let terminal = try await reopened.observeMutationLifecycle(id: predecessor.id)
    var terminalIterator = terminal.makeAsyncIterator()
    guard case let .serverAccepted(persisted) = await terminalIterator.next() else {
      Issue.record("Expected retry rejection to preserve the survivor terminal lifecycle.")
      return
    }
    expectNoDifference(persisted.id, survivor.id)
  }

  @Test
  func survivorFailureRestoresAuthoritativeBaselineAndNotifiesOriginalID()
    async throws
  {
    let runtime = try await makeOfflineRuntime(cacheURL: temporaryCacheURL("baseline-failure"))
    _ = try await runtime.applyServerTransaction(
      integrationTransaction(id: "server", value: "baseline", timestamp: 1),
      processedTransactionID: "1"
    )
    let originalLifecycle = try await runtime.observeMutationLifecycle(id: "older")
    var iterator = originalLifecycle.makeAsyncIterator()
    let initialLifecycle = await iterator.next()
    expectNoDifference(initialLifecycle, .waiting)

    _ = try await runtime.transact(
      integrationTransaction(id: "older", value: "one", timestamp: 2),
      createdAt: InstantTimestamp(milliseconds: 2)
    )
    _ = try await runtime.transact(
      integrationTransaction(id: "newer", value: "two", timestamp: 3),
      createdAt: InstantTimestamp(milliseconds: 3)
    )
    let durableStateBeforeFailure = try await runtime.persistence.loadState()
    let durableBeforeFailure = try #require(durableStateBeforeFailure.snapshot.outbox.first)
    expectNoDifference(durableBeforeFailure.rollbackTransaction?.operations.count, 4)

    _ = try await runtime.failMutation(id: "newer", message: "permission denied")

    guard case let .failed(failedMutation) = await iterator.next() else {
      Issue.record("Expected the original id to observe the survivor failure.")
      return
    }
    expectNoDifference(failedMutation.id, "newer")
    let storeSnapshot = await runtime.store.snapshot()
    expectNoDifference(currentIntegrationValue(in: storeSnapshot), "baseline")
  }

  @Test
  func survivorFailureRestoresEntityAbsence() async throws {
    let runtime = try await makeOfflineRuntime(cacheURL: temporaryCacheURL("absence-failure"))
    _ = try await runtime.transact(
      integrationTransaction(id: "older", value: "one", timestamp: 1),
      createdAt: InstantTimestamp(milliseconds: 1)
    )
    _ = try await runtime.transact(
      integrationTransaction(id: "newer", value: "two", timestamp: 2),
      createdAt: InstantTimestamp(milliseconds: 2)
    )

    _ = try await runtime.failMutation(id: "newer", message: "permission denied")

    let storeSnapshot = await runtime.store.snapshot()
    #expect(storeSnapshot.triples.allSatisfy { $0.entityID != "shared-item" })
  }

  @Test
  func originalIDResolvesSurvivorAcceptanceAfterRestartAndPrune() async throws {
    let cacheURL = temporaryCacheURL("accepted-lineage")
    let original = try await makeOfflineRuntime(cacheURL: cacheURL)
    _ = try await original.transact(
      integrationTransaction(id: "older", value: "one", timestamp: 1),
      createdAt: InstantTimestamp(milliseconds: 1)
    )
    // Simulate a predecessor written before migration 0013 introduced stable
    // lifecycle aliases. Supersession must lazily create the root using the
    // predecessor id, and that fallback must remain observable after restart.
    try await original.persistence.removeMutationLifecycleMetadataForTesting(id: "older")
    _ = try await original.transact(
      integrationTransaction(id: "newer", value: "two", timestamp: 2),
      createdAt: InstantTimestamp(milliseconds: 2)
    )

    let reopened = try await makeOfflineRuntime(cacheURL: cacheURL)
    let lifecycle = try await reopened.observeMutationLifecycle(id: "older")
    var iterator = lifecycle.makeAsyncIterator()
    let initialLifecycle = await iterator.next()
    expectNoDifference(initialLifecycle, .waiting)
    _ = try await reopened.acceptMutationIfPresent(
      id: "newer",
      serverTransactionID: "42"
    )
    guard case let .serverAccepted(accepted) = await iterator.next() else {
      Issue.record("Expected the original id to observe survivor acceptance.")
      return
    }
    expectNoDifference(accepted.id, "newer")

    _ = try await reopened.applyServerTransaction(
      InstantStoreTransaction(id: "43", operations: []),
      processedTransactionID: "43"
    )
    let remainingCount = try await reopened.persistence.countOutboxMutations()
    expectNoDifference(remainingCount, 0)

    let afterPrune = try await makeOfflineRuntime(cacheURL: cacheURL)
    let terminal = try await afterPrune.observeMutationLifecycle(id: "older")
    var terminalIterator = terminal.makeAsyncIterator()
    guard case let .serverAccepted(persisted) = await terminalIterator.next() else {
      Issue.record("Expected durable terminal lifecycle after survivor pruning.")
      return
    }
    expectNoDifference(persisted.id, "newer")
  }

  @Test
  func onlyCurrentSurvivorPublishesToAliasedLifecycle() async throws {
    let runtime = try await makeOfflineRuntime(cacheURL: temporaryCacheURL("stale-event"))
    _ = try await runtime.transact(
      integrationTransaction(id: "older", value: "one", timestamp: 1),
      createdAt: InstantTimestamp(milliseconds: 1)
    )
    _ = try await runtime.transact(
      integrationTransaction(id: "newer", value: "two", timestamp: 2),
      createdAt: InstantTimestamp(milliseconds: 2)
    )

    let staleIdentity = try await runtime.persistence
      .mutationLifecyclePublicationIdentity(for: "older")
    let survivorIdentity = try await runtime.persistence
      .mutationLifecyclePublicationIdentity(for: "newer")
    #expect(staleIdentity == nil)
    expectNoDifference(survivorIdentity, "older")
  }

  @Test
  func ordinaryMutationsDoNotCreatePermanentLifecycleHistory() async throws {
    let runtime = try await makeOfflineRuntime(cacheURL: temporaryCacheURL("ordinary-history"))
    _ = try await runtime.transact(
      integrationTransaction(id: "ordinary", value: "one", timestamp: 1),
      createdAt: InstantTimestamp(milliseconds: 1)
    )
    var counts = try await runtime.persistence.outboxLifecycleCountsForTesting()
    expectNoDifference(counts.lifecycles, 0)
    expectNoDifference(counts.aliases, 0)

    _ = try await runtime.acceptMutationIfPresent(
      id: "ordinary",
      serverTransactionID: "42"
    )
    counts = try await runtime.persistence.outboxLifecycleCountsForTesting()
    expectNoDifference(counts.lifecycles, 0)
    expectNoDifference(counts.aliases, 0)
  }

  @Test
  func failedTailAndOfferedTailRemainDurableBarriers() async throws {
    let failedRuntime = try await makeOfflineRuntime(cacheURL: temporaryCacheURL("failed-barrier"))
    _ = try await failedRuntime.transact(
      integrationTransaction(id: "failed", value: "one", timestamp: 1),
      createdAt: InstantTimestamp(milliseconds: 1)
    )
    _ = try await failedRuntime.failMutation(id: "failed", message: "permission denied")
    _ = try await failedRuntime.transact(
      integrationTransaction(id: "after-failed", value: "two", timestamp: 2),
      createdAt: InstantTimestamp(milliseconds: 2)
    )
    let failedBarrierState = try await failedRuntime.persistence.loadState()
    expectNoDifference(
      failedBarrierState.snapshot.outbox.map(\.id),
      ["failed", "after-failed"]
    )

    let offeredURL = temporaryCacheURL("offered-barrier")
    let offeredRuntime = try await makeOfflineRuntime(cacheURL: offeredURL)
    _ = try await offeredRuntime.transact(
      integrationTransaction(id: "offered", value: "one", timestamp: 1),
      createdAt: InstantTimestamp(milliseconds: 1)
    )
    let claimStore = try SQLitePersistenceStore(fileURL: offeredURL)
    try await claimStore.bootstrap()
    let claim = try await claimStore.claimAutomaticOutboxDeliveryWindow(
      InstantAutomaticOutboxClaimRequest(
        claimantID: "barrier-claimant",
        claimToken: "barrier-token",
        now: InstantTimestamp(milliseconds: 10)
      )
    )
    expectNoDifference(claim.mutations.map(\.id), ["offered"])
    let released = try await claimStore.releaseAutomaticOutboxClaim(
      id: "offered",
      claimantID: "barrier-claimant"
    )
    #expect(released)
    _ = try await offeredRuntime.transact(
      integrationTransaction(id: "after-offered", value: "two", timestamp: 2),
      createdAt: InstantTimestamp(milliseconds: 2)
    )
    let offeredBarrierState = try await offeredRuntime.persistence.loadState()
    expectNoDifference(
      offeredBarrierState.snapshot.outbox.map(\.id),
      ["offered", "after-offered"]
    )
  }

  @Test
  func claimRaceAtSupersessionSaveFallsBackToOrderedAppend() async throws {
    let cacheURL = temporaryCacheURL("claim-race")
    let competingStore = try SQLitePersistenceStore(fileURL: cacheURL)
    try await competingStore.bootstrap()
    let race = SupersessionClaimRace()
    var configuration = InstantRuntimeConfiguration(
      appID: "outbox-supersession-claim-race",
      persistenceURL: cacheURL,
      initialAttributes: TodoExample.attributes
    )
    configuration.autoConnectLiveTransport = false
    configuration.onLocalMutationSupersessionPreparedForTesting = {
      predecessorID, _ in
      await race.claimOnce(store: competingStore, expectedID: predecessorID)
    }
    let runtime = try await InstantRuntime.bootstrap(configuration: configuration)
    _ = try await runtime.transact(
      integrationTransaction(id: "race-older", value: "one", timestamp: 1),
      createdAt: InstantTimestamp(milliseconds: 1)
    )

    _ = try await runtime.transact(
      integrationTransaction(id: "race-newer", value: "two", timestamp: 2),
      createdAt: InstantTimestamp(milliseconds: 2)
    )

    let durable = try await runtime.persistence.loadState().snapshot.outbox
    expectNoDifference(durable.map(\.id), ["race-older", "race-newer"])
    let predecessorClaim = try await competingStore.outboxDeliveryClaimForTesting(
      id: "race-older"
    )
    expectNoDifference(predecessorClaim?.state, .claimed)
    expectNoDifference(integrationValue(in: durable[1].transaction), "two")
  }

  @Test
  func claimAfterInvalidTailReadPreventsQuarantineAndPreservesRawEvidence() async throws {
    let cacheURL = temporaryCacheURL("invalid-tail-claim-race")
    let seedStore = try SQLitePersistenceStore(fileURL: cacheURL)
    try await seedStore.bootstrap()
    try await seedStore.saveStoreSnapshot(
      InstantStoreSnapshot(attributes: TodoExample.attributes)
    )
    var tail = PendingMutation(
      id: "invalid-claimed-tail",
      createdAt: InstantTimestamp(milliseconds: 1),
      transaction: integrationTransaction(
        id: "invalid-claimed-tail",
        value: "old",
        timestamp: 1
      )
    )
    tail.rollbackTransaction = InstantStoreTransaction(
      id: "rollback-invalid-claimed-tail",
      operations: [.deleteEntity("shared-item")]
    )
    try await seedStore.saveOutbox([tail])
    await seedStore.simulateUnexpectedConnectionCloseForTesting()
    let rawTail = try supersessionOutboxRawRow(
      id: tail.id,
      cacheURL: cacheURL
    )
    let corruptJSON = String(repeating: "x", count: rawTail.encodedBodyByteCount)
    try replaceSupersessionOutboxBody(id: tail.id, json: corruptJSON, cacheURL: cacheURL)

    let competingStore = try SQLitePersistenceStore(fileURL: cacheURL)
    try await competingStore.bootstrap()
    let race = SupersessionClaimRace()
    let runtime = try await makeOfflineRuntime(cacheURL: cacheURL)
    await runtime.persistence.setInvalidImmediateSupersessionTailReadHookForTesting { id in
      await race.claimWithoutHydrationOnce(store: competingStore, expectedID: id)
    }

    _ = try await runtime.transact(
      integrationTransaction(id: "after-invalid-claim", value: "new", timestamp: 2),
      createdAt: InstantTimestamp(milliseconds: 2)
    )
    await runtime.persistence.setInvalidImmediateSupersessionTailReadHookForTesting(nil)

    let claim = try await competingStore.outboxDeliveryClaimForTesting(id: tail.id)
    let quarantine = try await runtime.persistence.quarantinedOutboxBodyForTesting(id: tail.id)
    let durableCount = try await runtime.persistence.countOutboxMutations()
    let preservedJSON = try supersessionOutboxRawRow(id: tail.id, cacheURL: cacheURL).json
    expectNoDifference(claim?.state, .claimed)
    expectNoDifference(claim?.deliveryStarted, true)
    expectNoDifference(quarantine, nil)
    expectNoDifference(preservedJSON, corruptJSON)
    expectNoDifference(durableCount, 2)
  }

  @Test
  func oversizedNormalizedTailIsNeverDecodedByTenThousandLaterEnqueues()
    async throws
  {
    let cacheURL = temporaryCacheURL("oversized-tail")
    let persistence = try SQLitePersistenceStore(fileURL: cacheURL)
    try await persistence.bootstrap()
    try await persistence.saveStoreSnapshot(
      InstantStoreSnapshot(attributes: TodoExample.attributes)
    )
    let oversized = PendingMutation(
      id: "oversized-tail",
      createdAt: InstantTimestamp(milliseconds: 1),
      transaction: integrationTransaction(
        id: "oversized-tail",
        value: String(
          repeating: "x",
          count: InstantAutomaticOutboxClaimLimits.maximumEncodedBodyBytes + 1
        ),
        timestamp: 1
      )
    )
    try await persistence.saveOutbox([oversized])
    let runtime = try await makeOfflineRuntime(cacheURL: cacheURL)
    let bootstrapDecodeCount = await runtime.persistence.currentDecodedOutboxBodyCount()
    expectNoDifference(
      bootstrapDecodeCount,
      0,
      "Cold bootstrap must not decode an oversized legacy tail body."
    )
    await runtime.persistence.resetDecodedOutboxBodyCount()
    _ = try await runtime.transact(
      integrationTransaction(id: "new-00000", value: "value-0", timestamp: 2),
      createdAt: InstantTimestamp(milliseconds: 2)
    )
    let decodeCountAfterBarrier = await runtime.persistence.currentDecodedOutboxBodyCount()
    let decodedBytesAfterBarrier = await runtime.persistence.currentDecodedOutboxBodyByteCount()
    expectNoDifference(decodeCountAfterBarrier, 0)
    expectNoDifference(decodedBytesAfterBarrier, 0)

    for index in 1..<10_000 {
      let timestamp = Int64(index + 2)
      _ = try await runtime.transact(
        integrationTransaction(
          id: String(format: "new-%05d", index),
          value: "value-\(index)",
          timestamp: timestamp
        ),
        createdAt: InstantTimestamp(milliseconds: timestamp)
      )
    }

    let durableCount = try await runtime.persistence.countOutboxMutations()
    expectNoDifference(durableCount, 2)
    let durableState = try await runtime.persistence.loadState()
    expectNoDifference(durableState.snapshot.outbox.map(\.id), [
      "oversized-tail", "new-09999",
    ])
  }

  @Test
  func staleSmallByteMetadataCannotMaterializeAnOversizedImmediateTail() async throws {
    let cacheURL = temporaryCacheURL("stale-small-byte-metadata")
    let persistence = try SQLitePersistenceStore(fileURL: cacheURL)
    try await persistence.bootstrap()
    try await persistence.saveStoreSnapshot(
      InstantStoreSnapshot(attributes: TodoExample.attributes)
    )
    var tail = PendingMutation(
      id: "stale-size-tail",
      createdAt: InstantTimestamp(milliseconds: 1),
      transaction: integrationTransaction(id: "stale-size-tail", value: "small", timestamp: 1)
    )
    tail.rollbackTransaction = InstantStoreTransaction(
      id: "rollback-stale-size-tail",
      operations: [.deleteEntity("shared-item")]
    )
    try await persistence.saveOutbox([tail])
    await persistence.simulateUnexpectedConnectionCloseForTesting()

    let oversizedJSON = String(
      repeating: "x",
      count: InstantAutomaticOutboxClaimLimits.maximumEncodedBodyBytes + 1
    )
    try replaceSupersessionOutboxBody(
      id: tail.id,
      json: oversizedJSON,
      cacheURL: cacheURL
    )

    let runtime = try await makeOfflineRuntime(cacheURL: cacheURL)
    await runtime.persistence.resetDecodedOutboxBodyCount()
    try await withKnownIssue {
      _ = try await runtime.transact(
        integrationTransaction(id: "after-stale-size", value: "new", timestamp: 2),
        createdAt: InstantTimestamp(milliseconds: 2)
      )
    } matching: { issue in
      issue.description.contains("quarantined durable mutation 'stale-size-tail'")
        && issue.description.contains("body exceeds")
    }

    let decodedBodyCount = await runtime.persistence.currentDecodedOutboxBodyCount()
    let decodedBodyByteCount = await runtime.persistence.currentDecodedOutboxBodyByteCount()
    let materializedBodyCount = await runtime.persistence.currentMaterializedOutboxBodyCount()
    let materializedBodyByteCount =
      await runtime.persistence.currentMaterializedOutboxBodyByteCount()
    let quarantineBodyByteCount = try await runtime.persistence
      .quarantinedOutboxBodyByteCountForTesting(id: tail.id)
    let failedCount = try await runtime.persistence.countOutboxMutations(status: .failed)
    let durableCount = try await runtime.persistence.countOutboxMutations()
    expectNoDifference(decodedBodyCount, 0)
    expectNoDifference(decodedBodyByteCount, 0)
    expectNoDifference(materializedBodyCount, 0)
    expectNoDifference(materializedBodyByteCount, 0)
    expectNoDifference(
      quarantineBodyByteCount,
      oversizedJSON.utf8.count,
      "SQLite must preserve the raw oversized evidence without copying it into Swift memory."
    )
    expectNoDifference(failedCount, 1)
    expectNoDifference(durableCount, 2)
  }

  @Test
  func corruptImmediateTailIsDecodedAndQuarantinedOnceBeforeTenThousandLaterEnqueues()
    async throws
  {
    let cacheURL = temporaryCacheURL("corrupt-tail")
    let persistence = try SQLitePersistenceStore(fileURL: cacheURL)
    try await persistence.bootstrap()
    try await persistence.saveStoreSnapshot(
      InstantStoreSnapshot(attributes: TodoExample.attributes)
    )
    var corruptTail = PendingMutation(
      id: "corrupt-tail",
      createdAt: InstantTimestamp(milliseconds: 1),
      transaction: integrationTransaction(id: "corrupt-tail", value: "old", timestamp: 1)
    )
    corruptTail.rollbackTransaction = InstantStoreTransaction(
      id: "rollback-corrupt-tail",
      operations: [.deleteEntity("shared-item")]
    )
    try await persistence.saveOutbox([corruptTail])
    await persistence.simulateUnexpectedConnectionCloseForTesting()
    let rawTail = try supersessionOutboxRawRow(
      id: corruptTail.id,
      cacheURL: cacheURL
    )
    let corruptJSON = String(repeating: "x", count: rawTail.encodedBodyByteCount)
    try replaceSupersessionOutboxBody(
      id: corruptTail.id,
      json: corruptJSON,
      cacheURL: cacheURL
    )

    let runtime = try await makeOfflineRuntime(cacheURL: cacheURL)
    let bootstrapDecodeCount = await runtime.persistence.currentDecodedOutboxBodyCount()
    expectNoDifference(
      bootstrapDecodeCount,
      0,
      "Cold bootstrap must leave normalized outbox bodies in SQLite."
    )
    await runtime.persistence.resetDecodedOutboxBodyCount()

    try await withKnownIssue {
      _ = try await runtime.transact(
        integrationTransaction(id: "new-00000", value: "value-0", timestamp: 2),
        createdAt: InstantTimestamp(milliseconds: 2)
      )
    } matching: { issue in
      issue.description.contains("quarantined corrupt durable mutation 'corrupt-tail'")
    }
    let corruptDecodeCount = await runtime.persistence.currentDecodedOutboxBodyCount()
    let quarantinedBody = try await runtime.persistence.quarantinedOutboxBodyForTesting(
      id: corruptTail.id
    )
    let failedCountAfterQuarantine = try await runtime.persistence.countOutboxMutations(
      status: .failed
    )
    expectNoDifference(
      corruptDecodeCount,
      1,
      "The corrupt tail is decoded exactly once before durable quarantine changes its status."
    )
    expectNoDifference(quarantinedBody, corruptJSON)
    expectNoDifference(failedCountAfterQuarantine, 1)

    await runtime.persistence.resetDecodedOutboxBodyCount()
    for index in 1..<10_000 {
      let timestamp = Int64(index + 2)
      _ = try await runtime.transact(
        integrationTransaction(
          id: String(format: "new-%05d", index),
          value: "value-\(index)",
          timestamp: timestamp
        ),
        createdAt: InstantTimestamp(milliseconds: timestamp)
      )
    }

    let laterDecodeCount = await runtime.persistence.currentDecodedOutboxBodyCount()
    let durableCount = try await runtime.persistence.countOutboxMutations()
    let finalFailedCount = try await runtime.persistence.countOutboxMutations(status: .failed)
    let retainedQuarantine = try await runtime.persistence.quarantinedOutboxBodyForTesting(
      id: corruptTail.id
    )
    expectNoDifference(
      laterDecodeCount,
      9_999,
      "Only each valid immediate survivor is decoded; the quarantined predecessor is never retried."
    )
    expectNoDifference(durableCount, 2)
    expectNoDifference(finalFailedCount, 1)
    expectNoDifference(retainedQuarantine, corruptJSON)
  }

  private func mutation(
    id: String,
    entityID: String = "item",
    value: String,
    timestamp: Int64
  ) -> PendingMutation {
    let time = InstantTimestamp(milliseconds: timestamp)
    return PendingMutation(
      id: id,
      createdAt: time,
      transaction: InstantStoreTransaction(
        id: id,
        operations: [
          .insert(
            InstantTriple(
              entityID: entityID,
              attributeID: "supersession_items/id",
              value: .string(entityID),
              txID: id,
              txTime: time
            )
          ),
          .insert(
            InstantTriple(
              entityID: entityID,
              attributeID: "supersession_items/value",
              value: .string(value),
              txID: id,
              txTime: time
            )
          ),
        ]
      )
    )
  }
}

private func temporaryCacheURL(_ suffix: String) -> URL {
  FileManager.default.temporaryDirectory
    .appendingPathComponent("instant-outbox-supersession-\(suffix)-\(UUID().uuidString).sqlite")
}

private func makeOfflineRuntime(cacheURL: URL) async throws -> InstantRuntime {
  var configuration = InstantRuntimeConfiguration(
    appID: "outbox-supersession-\(UUID().uuidString)",
    persistenceURL: cacheURL,
    initialAttributes: TodoExample.attributes
  )
  configuration.autoConnectLiveTransport = false
  return try await InstantRuntime.bootstrap(configuration: configuration)
}

private func integrationTransaction(
  id: String,
  value: String,
  timestamp: Int64,
  entityID: String = "shared-item"
) -> InstantStoreTransaction {
  let time = InstantTimestamp(milliseconds: timestamp)
  return InstantStoreTransaction(
    id: id,
    operations: [
      .insert(
        InstantTriple(
          entityID: entityID,
          attributeID: "todos/id",
          value: .string(entityID),
          txID: id,
          txTime: time
        )
      ),
      .insert(
        InstantTriple(
          entityID: entityID,
          attributeID: "todos/text",
          value: .string(value),
          txID: id,
          txTime: time
        )
      )
    ]
  )
}

private func partialIntegrationTransaction(
  id: String,
  value: String,
  timestamp: Int64
) -> InstantStoreTransaction {
  let time = InstantTimestamp(milliseconds: timestamp)
  return InstantStoreTransaction(
    id: id,
    operations: [
      .insert(
        InstantTriple(
          entityID: "shared-item",
          attributeID: "todos/text",
          value: .string(value),
          txID: id,
          txTime: time
        )
      )
    ]
  )
}

private func integrationValue(in transaction: InstantStoreTransaction) -> String? {
  for operation in transaction.operations {
    guard case let .insert(triple) = operation,
      triple.attributeID == "todos/text",
      case let .string(value) = triple.value
    else { continue }
    return value
  }
  return nil
}

private func currentIntegrationValue(in snapshot: InstantStoreSnapshot) -> String? {
  snapshot.triples
    .filter { $0.entityID == "shared-item" && $0.attributeID == "todos/text" }
    .sorted { $0.txTime < $1.txTime }
    .last
    .flatMap { triple in
      guard case let .string(value) = triple.value else { return nil }
      return value
    }
}

private actor SupersessionClaimRace {
  private var didClaim = false

  func claimOnce(
    store: SQLitePersistenceStore,
    expectedID: String
  ) async {
    guard !didClaim else { return }
    didClaim = true
    do {
      let window = try await store.claimAutomaticOutboxDeliveryWindow(
        InstantAutomaticOutboxClaimRequest(
          claimantID: "race-claimant",
          claimToken: "race-token",
          now: InstantTimestamp(milliseconds: 10)
        )
      )
      guard window.mutations.map(\.id) == [expectedID] else {
        Issue.record(
          "Expected the competing claim to reserve only \(expectedID), got \(window.mutations.map(\.id))."
        )
        return
      }
    } catch {
      Issue.record("Could not install deterministic competing claim: \(error)")
    }
  }

  func claimWithoutHydrationOnce(
    store: SQLitePersistenceStore,
    expectedID: String
  ) async {
    guard !didClaim else { return }
    didClaim = true
    do {
      let claimed = try await store.claimOutboxMutationWithoutHydrationForTesting(
        id: expectedID,
        claimantID: "invalid-tail-race-claimant",
        claimToken: "invalid-tail-race-token",
        deadlineMilliseconds: 5_000
      )
      if !claimed {
        Issue.record("Expected the invalid tail race hook to claim \(expectedID).")
      }
    } catch {
      Issue.record("Could not install the invalid tail race claim: \(error)")
    }
  }
}

private let supersessionSQLiteTransient = unsafeBitCast(
  -1,
  to: sqlite3_destructor_type.self
)

private struct SupersessionOutboxRawRow {
  var encodedBodyByteCount: Int
  var json: String
}

private func supersessionOutboxRawRow(
  id: String,
  cacheURL: URL
) throws -> SupersessionOutboxRawRow {
  var database: OpaquePointer?
  guard sqlite3_open_v2(cacheURL.path, &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
    defer { sqlite3_close(database) }
    throw NSError(
      domain: "InstantOutboxSupersessionIntegrationTests",
      code: 4,
      userInfo: [NSLocalizedDescriptionKey: "Could not open the fault-injection database."]
    )
  }
  defer { sqlite3_close(database) }
  var statement: OpaquePointer?
  guard sqlite3_prepare_v2(
    database,
    "SELECT encoded_body_bytes, json FROM instant_outbox WHERE mutation_id = ? LIMIT 1",
    -1,
    &statement,
    nil
  ) == SQLITE_OK else {
    throw NSError(
      domain: "InstantOutboxSupersessionIntegrationTests",
      code: 5,
      userInfo: [NSLocalizedDescriptionKey: "Could not prepare the raw outbox-row lookup."]
    )
  }
  defer { sqlite3_finalize(statement) }
  let idBind = id.withCString {
    sqlite3_bind_text(statement, 1, $0, -1, supersessionSQLiteTransient)
  }
  guard idBind == SQLITE_OK, sqlite3_step(statement) == SQLITE_ROW else {
    throw NSError(
      domain: "InstantOutboxSupersessionIntegrationTests",
      code: 6,
      userInfo: [NSLocalizedDescriptionKey: "Could not read the raw outbox row."]
    )
  }
  guard let jsonBytes = sqlite3_column_text(statement, 1) else {
    throw NSError(
      domain: "InstantOutboxSupersessionIntegrationTests",
      code: 7,
      userInfo: [NSLocalizedDescriptionKey: "The raw outbox row had no JSON body."]
    )
  }
  return SupersessionOutboxRawRow(
    encodedBodyByteCount: Int(sqlite3_column_int64(statement, 0)),
    json: String(cString: jsonBytes)
  )
}

private func replaceSupersessionOutboxBody(
  id: String,
  json: String,
  cacheURL: URL
) throws {
  var database: OpaquePointer?
  guard sqlite3_open_v2(cacheURL.path, &database, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK else {
    defer { sqlite3_close(database) }
    throw NSError(
      domain: "InstantOutboxSupersessionIntegrationTests",
      code: 1,
      userInfo: [NSLocalizedDescriptionKey: "Could not open the fault-injection database."]
    )
  }
  defer { sqlite3_close(database) }
  var statement: OpaquePointer?
  guard sqlite3_prepare_v2(
    database,
    "UPDATE instant_outbox SET json = ? WHERE mutation_id = ?",
    -1,
    &statement,
    nil
  ) == SQLITE_OK else {
    throw NSError(
      domain: "InstantOutboxSupersessionIntegrationTests",
      code: 2,
      userInfo: [NSLocalizedDescriptionKey: "Could not prepare outbox body corruption."]
    )
  }
  defer { sqlite3_finalize(statement) }
  let jsonBind = json.withCString {
    sqlite3_bind_text(statement, 1, $0, -1, supersessionSQLiteTransient)
  }
  let idBind = id.withCString {
    sqlite3_bind_text(statement, 2, $0, -1, supersessionSQLiteTransient)
  }
  guard jsonBind == SQLITE_OK, idBind == SQLITE_OK, sqlite3_step(statement) == SQLITE_DONE else {
    throw NSError(
      domain: "InstantOutboxSupersessionIntegrationTests",
      code: 3,
      userInfo: [NSLocalizedDescriptionKey: "Could not corrupt the outbox body."]
    )
  }
}
