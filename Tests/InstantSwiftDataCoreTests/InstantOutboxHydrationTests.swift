import CustomDump
import Foundation
import SQLite3
import Testing
@testable import InstantSwiftDataCore

@Suite(.serialized)
struct InstantOutboxHydrationTests {
  @Test
  func freshRuntimePersistsInitialAttributesBeforeFirstWrite() async throws {
    let cacheURL = try temporaryOutboxHydrationCacheURL()
    _ = try await makeRuntime(appID: "bootstrap-attribute-diff-base", cacheURL: cacheURL)

    let independentReopen = try SQLitePersistenceStore(fileURL: cacheURL)
    try await independentReopen.bootstrap()
    let durableAttributes = try await independentReopen.loadState().snapshot.store.attributes

    expectNoDifference(
      Set(durableAttributes),
      Set(TodoExample.attributes),
      upstreamDeliverySource
    )
  }

  @Test
  func sameProcessLiveDeliveryCandidatesRetainExactTransactionSteps() async throws {
    let now = InstantTimestamp(milliseconds: 1_700_000_070_000)
    let transaction = makeTransaction(id: "tx-live-hydration", at: now)
    let runtime = try await makeRuntime(
      appID: "outbox-live-hydration",
      cacheURL: temporaryOutboxHydrationCacheURL()
    )

    try await runtime.transact(transaction, createdAt: now)

    let delivered = try #require(
      await runtime.outboxTransportMutations().first {
        $0.mutationID == transaction.id
      }
    )
    let expected = InstantTransportMutation(
      PendingMutation(id: transaction.id, createdAt: now, transaction: transaction)
    )
    expectNoDifference(delivered.preconditions, expected.preconditions, upstreamDeliverySource)
    expectNoDifference(delivered.txSteps, expected.txSteps, upstreamDeliverySource)
    #expect(
      !delivered.txSteps.isEmpty,
      "The durable transaction must not become an empty upstream transact message."
    )
    let durable = try #require(
      try await runtime.persistence.loadState().snapshot.outbox.first {
        $0.id == transaction.id
      }
    )
    expectNoDifference(durable.transaction, transaction, upstreamDeliverySource)
  }

  @Test
  func sameProcessAutomaticLiveDeliverySendsExactTransactionSteps() async throws {
    let now = InstantTimestamp(milliseconds: 1_700_000_075_000)
    let transaction = makeTransaction(id: "tx-automatic-live-hydration", at: now)
    let expected = InstantTransportMutation(
      PendingMutation(id: transaction.id, createdAt: now, transaction: transaction)
    )
    let liveSession = LiveReactorParitySession(messages: [
      liveReactorInitOK(attrs: liveReactorTodoServerAttrs)
    ])
    let runtime = try await makeRuntime(
      appID: "outbox-automatic-live-hydration",
      cacheURL: temporaryOutboxHydrationCacheURL(),
      liveTransport: liveSession.transport
    )
    let lifecycle = try await runtime.observeMutationLifecycle(id: transaction.id)
    let lifecycleTask = Task { () -> [InstantMutationLifecycleEvent] in
      var iterator = lifecycle.makeAsyncIterator()
      var events: [InstantMutationLifecycleEvent] = []
      for _ in 0..<2 {
        guard let event = await iterator.next() else { break }
        events.append(event)
      }
      return events
    }
    defer { lifecycleTask.cancel() }

    try await instantLiveWithTimeout(
      operation: "wait for automatic live session initialization",
      timeoutMilliseconds: 5_000
    ) {
      await liveSession.waitForSentMessageCount(1)
    }
    try await runtime.transact(transaction, createdAt: now)
    try await instantLiveWithTimeout(
      operation: "wait for automatic live mutation delivery",
      timeoutMilliseconds: 5_000
    ) {
      await liveSession.waitForSentMessageCount(2)
    }

    let resolvedSteps = try InstantLiveMutationEncoder.resolveAttributeIDs(
      in: expected.txSteps,
      attrs: liveReactorTodoServerAttrs
    )
    let sentMessages = await liveSession.sentMessages()
    expectNoDifference(sentMessages.map(\.op), ["init", "transact"], upstreamDeliverySource)
    expectNoDifference(
      sentMessages.last,
      try InstantLiveMessage.transact(resolvedSteps, clientEventID: transaction.id),
      upstreamDeliverySource
    )
    let sentSteps = try #require(sentMessages.last?.fields["tx-steps"]?.arrayValue)
    #expect(!sentSteps.isEmpty, "Automatic live delivery must send the durable transaction steps.")
    await liveSession.enqueue(
      InstantLiveMessage(
        op: "transact-ok",
        clientEventID: transaction.id,
        fields: ["tx-id": .string("server-\(transaction.id)")]
      )
    )
    let lifecycleEvents = try await instantLiveWithTimeout(
      operation: "wait for server-accepted mutation lifecycle",
      timeoutMilliseconds: 5_000
    ) {
      await lifecycleTask.value
    }
    guard lifecycleEvents.first == .waiting else {
      Issue.record("Expected the mutation lifecycle to begin in the waiting state.")
      return
    }
    guard lifecycleEvents.count == 2,
      case .serverAccepted(let accepted) = lifecycleEvents[1]
    else {
      Issue.record("Expected the server acknowledgement to publish an accepted mutation.")
      return
    }
    expectNoDifference(accepted.transaction, transaction, upstreamDeliverySource)
    let durableAccepted = try #require(
      try await runtime.persistence.loadState().snapshot.outbox.first {
        $0.id == transaction.id
      }
    )
    expectNoDifference(durableAccepted.transaction, transaction, upstreamDeliverySource)
    _ = try? await runtime.closeConnection()
  }

  @Test
  func explicitlyConnectedRuntimeDeliversLaterTransactionWithoutAutoConnect() async throws {
    let now = InstantTimestamp(milliseconds: 1_700_000_077_000)
    let transaction = makeTransaction(id: "tx-explicit-live-hydration", at: now)
    let liveSession = LiveReactorParitySession(messages: [
      liveReactorInitOK(attrs: liveReactorTodoServerAttrs)
    ])
    let runtime = try await makeRuntime(
      appID: "outbox-explicit-live-hydration",
      cacheURL: temporaryOutboxHydrationCacheURL(),
      liveTransport: liveSession.transport,
      autoConnectLiveTransport: false
    )

    _ = try await runtime.connect()
    try await runtime.transact(transaction, createdAt: now)

    try await instantLiveWithTimeout(
      operation: "wait for explicitly connected mutation delivery",
      timeoutMilliseconds: 5_000
    ) {
      while await liveSession.sentMessages().count < 2 {
        try Task.checkCancellation()
        await Task.yield()
      }
    }
    let sentMessages = await liveSession.sentMessages()
    expectNoDifference(sentMessages.map(\.op), ["init", "transact"], upstreamDeliverySource)
    let sentSteps = try #require(sentMessages.last?.fields["tx-steps"]?.arrayValue)
    #expect(!sentSteps.isEmpty, "An open explicit connection must send later durable writes.")
    _ = try? await runtime.closeConnection()
  }

  @Test
  func explicitlyConnectedRuntimeRunsLaterQueryOnceThroughLiveSession() async throws {
    let serverCreatedAt = InstantTimestamp(milliseconds: 1_700_000_078_000)
    let query = try InstantLiveQueryEncoder.encode(TodoExample.query)
    let liveSession = LiveReactorParitySession(messages: [
      liveReactorInitOK(attrs: liveReactorTodoServerAttrs),
      liveReactorAddQueryOK(
        query: query,
        processedTransactionID: "server-explicit-query",
        result: liveReactorTodoQueryResult(
          id: "todo-explicit-query",
          text: "arrived from the explicitly opened session",
          createdAt: serverCreatedAt
        )
      ),
    ])
    let runtime = try await makeRuntime(
      appID: "query-explicit-live-hydration",
      cacheURL: temporaryOutboxHydrationCacheURL(),
      liveTransport: liveSession.transport,
      autoConnectLiveTransport: false
    )

    _ = try await runtime.connect()
    let todos = try TodoExample.decode(try await runtime.queryOnce(TodoExample.query).values)
    try await instantLiveWithTimeout(
      operation: "wait for explicitly connected one-shot query cleanup",
      timeoutMilliseconds: 5_000
    ) {
      await liveSession.waitForSentMessageCount(3)
    }

    expectNoDifference(todos.map(\.id), ["todo-explicit-query"], upstreamQuerySource)
    let sentMessages = await liveSession.sentMessages()
    expectNoDifference(
      sentMessages.map(\.op),
      ["init", "add-query", "remove-query"],
      upstreamQuerySource
    )
    _ = try? await runtime.closeConnection()
  }

  @Test
  func queryOnceClassifiesPermissionTypeEvenWhenServerUsesStatus400() async throws {
    let plan = InstantQueryPlan(
      id: "query.permission-status-400",
      namespace: TodoExample.namespace,
      filters: [.equals(field: "text", value: .string("forbidden"))]
    )
    let encodedQuery = try InstantLiveQueryEncoder.encode(plan)
    let liveSession = LiveReactorParitySession(messages: [
      liveReactorInitOK(attrs: liveReactorTodoServerAttrs)
    ])
    let runtime = try await makeRuntime(
      appID: "query-permission-status-400",
      cacheURL: temporaryOutboxHydrationCacheURL(),
      liveTransport: liveSession.transport
    )
    let queryTask = Task { try await runtime.queryOnce(plan) }
    defer { queryTask.cancel() }

    try await instantLiveWithTimeout(
      operation: "wait for status-400 permission query registration",
      timeoutMilliseconds: 5_000
    ) {
      await liveSession.waitForSentMessageCount(2)
    }
    let addQuery = try #require(await liveSession.sentMessages().last)
    let eventID = try #require(addQuery.clientEventID)
    await liveSession.enqueue(
      InstantLiveMessage(
        op: "error",
        clientEventID: eventID,
        fields: [
          "message": .string("The query was rejected."),
          "original-event": .object([
            "client-event-id": .string(eventID),
            "op": .string("add-query"),
            "q": encodedQuery,
          ]),
          "status": .number(400),
          "type": .string("permission-denied"),
        ]
      )
    )

    do {
      _ = try await instantLiveWithTimeout(
        operation: "wait for status-400 permission query rejection",
        timeoutMilliseconds: 5_000
      ) {
        try await queryTask.value
      }
      Issue.record("Expected the server permission rejection to fail queryOnce.")
    } catch let error as InstantError {
      expectNoDifference(error.code, .permissionRejected, upstreamQuerySource)
      expectNoDifference(error.operation, "run Instant live query", upstreamQuerySource)
      expectNoDifference(error.message, "The query was rejected.", upstreamQuerySource)
    }
    let connectionState = try await runtime.connectionStatus().state
    expectNoDifference(connectionState, .opened, upstreamQuerySource)
    _ = try? await runtime.closeConnection()
  }

  @Test
  func server500PermissionEvaluationFailureRemainsRetryable() async throws {
    let now = InstantTimestamp(milliseconds: 1_700_000_079_000)
    let transaction = makeTransaction(id: "tx-permission-service-unavailable", at: now)
    let firstSession = LiveReactorParitySession(messages: [
      liveReactorInitOK(attrs: liveReactorTodoServerAttrs, sessionID: "permission-timeout-first")
    ])
    let secondSession = LiveReactorParitySession(messages: [
      liveReactorInitOK(attrs: liveReactorTodoServerAttrs, sessionID: "permission-timeout-second")
    ])
    let transport = LiveReactorParityTransport(sessions: [firstSession, secondSession])
    let configuration = InstantRuntimeConfiguration(
      appID: "mutation-permission-service-unavailable",
      persistenceURL: try temporaryOutboxHydrationCacheURL(),
      initialAttributes: TodoExample.attributes,
      liveTransport: transport.transport
    )
    let runtime = try await InstantRuntime.bootstrap(configuration: configuration)
    _ = try await runtime.connect()

    try await instantLiveWithTimeout(
      operation: "wait for permission-service first session initialization",
      timeoutMilliseconds: 5_000
    ) {
      await firstSession.waitForSentMessageCount(1)
    }
    try await runtime.transact(transaction, createdAt: now)
    try await instantLiveWithTimeout(
      operation: "wait for permission-service first mutation delivery",
      timeoutMilliseconds: 5_000
    ) {
      await firstSession.waitForSentMessageCount(2)
    }
    await firstSession.enqueue(
      InstantLiveMessage(
        op: "error",
        clientEventID: transaction.id,
        fields: [
          "message": .string("Permission service unavailable"),
          "status": .number(500),
          "type": .string("permission-evaluation-failed"),
        ]
      )
    )

    try await instantLiveWithTimeout(
      operation: "wait for permission-service reconnect",
      timeoutMilliseconds: 5_000
    ) {
      await transport.waitForConnectionCount(2)
    }
    try await instantLiveWithTimeout(
      operation: "wait for permission-service reconnect to finish opening",
      timeoutMilliseconds: 5_000
    ) {
      while try await runtime.connectionStatus().state != .opened {
        try await Task.sleep(for: .milliseconds(1))
      }
    }
    try await instantLiveWithTimeout(
      operation: "wait for permission-service mutation retry",
      timeoutMilliseconds: 5_000
    ) {
      await secondSession.waitForSentMessageCount(2)
    }
    let retriedMessages = await secondSession.sentMessages()
    expectNoDifference(
      retriedMessages.map(\.op),
      ["init", "transact"],
      upstreamDeliverySource
    )
    let retriedSteps = try #require(retriedMessages.last?.fields["tx-steps"]?.arrayValue)
    #expect(retriedSteps.isEmpty == false)
    let pending = try #require(await runtime.pendingMutations().first { $0.id == transaction.id })
    expectNoDifference(pending.status, .pending, upstreamDeliverySource)
    expectNoDifference(pending.failureMessage, nil, upstreamDeliverySource)
    let failed = await runtime.failedMutations()
    expectNoDifference(failed, [], upstreamDeliverySource)

    await secondSession.enqueue(
      InstantLiveMessage(
        op: "transact-ok",
        clientEventID: transaction.id,
        fields: ["tx-id": .string("server-permission-service-retry")]
      )
    )
    _ = try #require(
      try await instantLiveWithTimeout(
        operation: "wait for retried permission-timeout mutation acknowledgement",
        timeoutMilliseconds: 5_000
      ) {
        try await runtime.observeConnectionStatus().first { $0.pendingMutationCount == 0 }
      }
    )
    _ = try? await runtime.closeConnection()
  }

  @Test
  func sameProcessExplicitFlushRetainsExactTransactionSteps() async throws {
    let now = InstantTimestamp(milliseconds: 1_700_000_080_000)
    let transaction = makeTransaction(id: "tx-flush-hydration", at: now)
    let recorder = OutboxHydrationTransportRecorder()
    let runtime = try await makeRuntime(
      appID: "outbox-flush-hydration",
      cacheURL: temporaryOutboxHydrationCacheURL(),
      mutationTransport: InstantMutationTransportClient { request in
        await recorder.record(request)
        return InstantMutationTransportResponse(
          results: request.mutations.map {
            InstantMutationTransportResult(mutationID: $0.mutationID, outcome: .confirmed)
          }
        )
      }
    )

    try await runtime.transact(transaction, createdAt: now)
    let result = try await runtime.flushPendingMutations()

    let delivered = try #require(result.request.mutations.first)
    let expected = InstantTransportMutation(
      PendingMutation(id: transaction.id, createdAt: now, transaction: transaction)
    )
    expectNoDifference(delivered.preconditions, expected.preconditions, upstreamDeliverySource)
    expectNoDifference(delivered.txSteps, expected.txSteps, upstreamDeliverySource)
    #expect(
      !delivered.txSteps.isEmpty,
      "Explicit flush must not turn a durable transaction into an empty upstream transact message."
    )
    let recordedRequests = await recorder.requests()
    expectNoDifference(
      recordedRequests.flatMap(\.mutations).map(\.txSteps),
      [expected.txSteps],
      upstreamDeliverySource
    )
    let durableConfirmed = try #require(
      try await runtime.persistence.loadState().snapshot.outbox.first {
        $0.id == transaction.id
      }
    )
    expectNoDifference(durableConfirmed.transaction, transaction, upstreamDeliverySource)
  }

  @Test
  func terminalFailureRebasesSuccessorUsingDurableOperations() async throws {
    let firstTime = InstantTimestamp(milliseconds: 1_700_000_090_000)
    let secondTime = InstantTimestamp(milliseconds: firstTime.milliseconds + 1)
    let rejected = makeTransaction(id: "tx-rejected-hydration", at: firstTime)
    let successor = makeTransaction(id: "tx-successor-hydration", at: secondTime)
    let runtime = try await makeRuntime(
      appID: "outbox-failure-hydration",
      cacheURL: temporaryOutboxHydrationCacheURL()
    )

    try await runtime.transact(rejected, createdAt: firstTime)
    try await runtime.transact(successor, createdAt: secondTime)
    _ = try await runtime.failMutation(id: rejected.id, message: "permission rejected")
    let idempotentReplay = try await runtime.transact(successor, createdAt: secondTime)
    expectNoDifference(idempotentReplay.transactionID, successor.id, upstreamDeliverySource)
    expectNoDifference(idempotentReplay.changedEntityIDs, [], upstreamDeliverySource)
    let conflictingReplay = InstantStoreTransaction(
      id: successor.id,
      operations: TodoExample.createOperations(
        id: "todo-\(successor.id)",
        text: "different durable intent",
        createdAt: secondTime,
        transactionID: successor.id
      )
    )
    do {
      _ = try await runtime.transact(conflictingReplay, createdAt: secondTime)
      Issue.record("Expected a same-id replay with different wire intent to be rejected.")
    } catch let error as InstantError {
      expectNoDifference(error.code, .validationFailed, upstreamDeliverySource)
      expectNoDifference(error.operation, "transact", upstreamDeliverySource)
      expectNoDifference(error.localID, successor.id, upstreamDeliverySource)
    }

    let todos = try TodoExample.decode(try await runtime.query(TodoExample.query))
    expectNoDifference(todos.map(\.id), ["todo-\(successor.id)"], upstreamDeliverySource)
    let persisted = try await runtime.persistence.loadState().snapshot
    let durable = persisted.outbox
    let durableRejected = try #require(durable.first { $0.id == rejected.id })
    let durableSuccessor = try #require(durable.first { $0.id == successor.id })
    expectNoDifference(durableRejected.status, .failed, upstreamDeliverySource)
    expectNoDifference(durableRejected.transaction, rejected, upstreamDeliverySource)
    expectNoDifference(durableSuccessor.status, .pending, upstreamDeliverySource)
    expectNoDifference(
      InstantTransportMutation(durableSuccessor).txSteps,
      InstantTransportMutation(
        PendingMutation(id: successor.id, createdAt: secondTime, transaction: successor)
      ).txSteps,
      upstreamDeliverySource
    )
    let rebasedWriteTimes = durableSuccessor.transaction.operations.compactMap {
      operation -> InstantTimestamp? in
      guard case let .insert(triple) = operation else { return nil }
      return triple.txTime
    }
    let visibleWriteTimes = persisted.store.triples
      .filter { $0.entityID == "todo-\(successor.id)" }
      .map(\.txTime)
    #expect(!rebasedWriteTimes.isEmpty)
    expectNoDifference(
      Set(rebasedWriteTimes),
      Set(visibleWriteTimes),
      upstreamDeliverySource
    )
    #expect(
      durableSuccessor.rollbackTransaction?.operations.isEmpty == false,
      "The successor must retain a rebuilt rollback after the rejected predecessor is removed."
    )
    let deliveredSuccessor = try #require(
      await runtime.outboxTransportMutations().first { $0.mutationID == successor.id }
    )
    let expectedSuccessor = InstantTransportMutation(
      PendingMutation(id: successor.id, createdAt: secondTime, transaction: successor)
    )
    expectNoDifference(
      deliveredSuccessor.txSteps,
      expectedSuccessor.txSteps,
      upstreamDeliverySource
    )
  }

  @Test
  func manualConfirmationKeepsDurableBodyWhileResidentActorStaysCompact() async throws {
    let now = InstantTimestamp(milliseconds: 1_700_000_095_000)
    let transaction = makeTransaction(id: "tx-manual-confirm-hydration", at: now)
    let runtime = try await makeRuntime(
      appID: "outbox-manual-confirm-hydration",
      cacheURL: temporaryOutboxHydrationCacheURL()
    )

    try await runtime.transact(transaction, createdAt: now)

    let residentPending = await runtime.mutationDeliveryBarrierMutations()
    expectNoDifference(
      residentPending,
      [],
      "Ordinary enqueue leaves SQLite authoritative until a bounded delivery claim is admitted."
    )
    let hydratedPending = try #require(
      await runtime.pendingMutations().first { $0.id == transaction.id }
    )
    expectNoDifference(hydratedPending.transaction, transaction, upstreamDeliverySource)
    #expect(hydratedPending.rollbackTransaction?.operations.isEmpty == false)
    let compactPersistence = try await runtime.persistence.loadCompactState().snapshot.outbox
    expectNoDifference(
      compactPersistence,
      [],
      "Cold/compact state keeps no queue-depth-proportional lifecycle shell array."
    )
    let inspectedPending = try #require(
      await runtime.outboxMutations().first { $0.id == transaction.id }
    )
    expectNoDifference(inspectedPending.transaction, transaction, upstreamDeliverySource)

    _ = try await runtime.confirmMutation(id: transaction.id)

    let residentConfirmed = await runtime.mutationDeliveryBarrierMutations()
    expectNoDifference(
      residentConfirmed,
      [],
      "Manual confirmation stays durable and deliverable without repopulating resident queue shells."
    )
    let durableConfirmed = try #require(
      try await runtime.persistence.loadState().snapshot.outbox.first { $0.id == transaction.id }
    )
    expectNoDifference(durableConfirmed.transaction, transaction, upstreamDeliverySource)
    #expect(durableConfirmed.rollbackTransaction?.operations.isEmpty == false)
    let delivered = try #require(
      await runtime.outboxTransportMutations().first { $0.mutationID == transaction.id }
    )
    let expected = InstantTransportMutation(
      PendingMutation(id: transaction.id, createdAt: now, transaction: transaction)
    )
    expectNoDifference(delivered.txSteps, expected.txSteps, upstreamDeliverySource)
    #expect(!delivered.txSteps.isEmpty)
  }

  @Test
  func serverAcceptanceDecodesOnlyAddressedRowInTenThousandRowOutbox() async throws {
    let cacheURL = try temporaryOutboxHydrationCacheURL()
    let persistence = try SQLitePersistenceStore(fileURL: cacheURL)
    try await persistence.bootstrap()
    let targetID = "tx-accept-row-09999"
    let localReceiptID = "tx-accept-row-00001"
    let preparedNoEffectMutations = (0..<10_000).compactMap { index -> PendingMutation? in
      let id = String(format: "tx-accept-row-%05d", index)
      guard id != targetID, id != localReceiptID else { return nil }
      var mutation = PendingMutation(
        id: id,
        createdAt: InstantTimestamp(milliseconds: Int64(index + 100)),
        transaction: InstantStoreTransaction(id: id, operations: [])
      )
      mutation.optimisticOverlayState = .applied
      mutation.optimisticEffectReceiptVersion =
        PendingMutation.currentOptimisticEffectReceiptVersion
      return mutation
    }
    let seedState = try await persistence.loadCompactState()
    let didSeedPreparedNoEffectRows = try await persistence.saveOutbox(
      preparedNoEffectMutations,
      replacing: [],
      metadataEntries: [],
      expectedStoreRevision: seedState.storeRevision,
      expectedOutboxRevision: seedState.outboxRevision
    )
    expectNoDifference(didSeedPreparedNoEffectRows, true)
    let runtime = try await makeRuntime(
      appID: "outbox-row-addressed-acceptance",
      cacheURL: cacheURL
    )
    let targetTransaction = makeTransaction(
      id: targetID,
      at: InstantTimestamp(milliseconds: 1)
    )
    try await runtime.transact(
      targetTransaction,
      createdAt: InstantTimestamp(milliseconds: 1)
    )
    let localReceiptTransaction = makeTransaction(
      id: localReceiptID,
      at: InstantTimestamp(milliseconds: 2)
    )
    try await runtime.transact(
      localReceiptTransaction,
      createdAt: InstantTimestamp(milliseconds: 2)
    )
    _ = try await runtime.confirmMutation(id: localReceiptID)
    try corruptOutboxJSON(
      id: "tx-accept-row-00000",
      in: cacheURL
    )
    await runtime.persistence.invalidateMemoryCache()

    let claimantID = await runtime.automaticDeliveryClaimantIDForTesting()
    let targetClaimToken = "row-addressed-target-claim"
    await runtime.persistence.resetDecodedOutboxBodyCount()
    let targetClaim = try await runtime.persistence.claimAutomaticOutboxDeliveryWindow(
      InstantAutomaticOutboxClaimRequest(
        claimantID: claimantID,
        claimToken: targetClaimToken,
        now: InstantTimestamp(milliseconds: 10_000),
        maximumMutationCount: 1
      )
    )
    expectNoDifference(targetClaim.mutations.map(\.id), [targetID], upstreamDeliverySource)
    let targetClaimDecodeCount = await runtime.persistence.currentDecodedOutboxBodyCount()
    expectNoDifference(
      targetClaimDecodeCount,
      1,
      "The Runtime-owned target precedes the corrupt prepared no-effect head and is the only claim body decoded."
    )

    await runtime.persistence.resetDecodedOutboxBodyCount()
    let accepted = try #require(
      try await runtime.acceptMutationIfPresent(
        id: targetID,
        serverTransactionID: "server-row-addressed-acceptance",
        claimToken: targetClaimToken
      )
    )

    expectNoDifference(accepted.id, targetID, upstreamDeliverySource)
    expectNoDifference(accepted.status, .confirmed, upstreamDeliverySource)
    let firstAcceptanceDecodeCount = await runtime.persistence.currentDecodedOutboxBodyCount()
    expectNoDifference(
      firstAcceptanceDecodeCount,
      1,
      upstreamDeliverySource
    )
    let pendingMutationCount = await runtime.pendingMutationCount()
    expectNoDifference(pendingMutationCount, 9_998, upstreamDeliverySource)
    let status = try await runtime.connectionStatus()
    expectNoDifference(status.pendingMutationCount, 9_998, upstreamDeliverySource)
    let decodeCountAfterStatusReads = await runtime.persistence.currentDecodedOutboxBodyCount()
    expectNoDifference(decodeCountAfterStatusReads, 1, upstreamDeliverySource)
    let resident = await runtime.mutationDeliveryBarrierMutations()
    expectNoDifference(
      resident,
      [],
      "Server-accepted rows remain durable but leave the bounded delivery barrier actor."
    )
    let revisionAfterFirstAcceptance = try await runtime.persistence.currentOutboxRevision()

    await runtime.persistence.resetDecodedOutboxBodyCount()
    let duplicate = try #require(
      try await runtime.acceptMutationIfPresent(
        id: targetID,
        serverTransactionID: "server-conflicting-duplicate",
        claimToken: nil
      )
    )
    expectNoDifference(duplicate.status, .confirmed, upstreamDeliverySource)
    expectNoDifference(
      duplicate.serverTransactionID,
      "server-row-addressed-acceptance",
      upstreamDeliverySource
    )
    let duplicateDecodeCount = await runtime.persistence.currentDecodedOutboxBodyCount()
    expectNoDifference(
      duplicateDecodeCount,
      1,
      upstreamDeliverySource
    )
    let revisionAfterDuplicate = try await runtime.persistence.currentOutboxRevision()
    expectNoDifference(
      revisionAfterDuplicate,
      revisionAfterFirstAcceptance,
      upstreamDeliverySource
    )

    let localReceiptClaimToken = "row-addressed-local-receipt-claim"
    await runtime.persistence.resetDecodedOutboxBodyCount()
    let localReceiptClaim = try await runtime.persistence
      .claimAutomaticOutboxDeliveryWindow(
        InstantAutomaticOutboxClaimRequest(
          claimantID: claimantID,
          claimToken: localReceiptClaimToken,
          now: InstantTimestamp(milliseconds: 10_001),
          maximumMutationCount: 1
        )
      )
    expectNoDifference(
      localReceiptClaim.mutations.map(\.id),
      [localReceiptID],
      upstreamDeliverySource
    )
    let localReceiptClaimDecodeCount =
      await runtime.persistence.currentDecodedOutboxBodyCount()
    expectNoDifference(
      localReceiptClaimDecodeCount,
      1,
      "The local receipt is Runtime-prepared and claimed without touching the corrupt prepared row."
    )

    await runtime.persistence.resetDecodedOutboxBodyCount()
    let acceptedLocalReceipt = try #require(
      try await runtime.acceptMutationIfPresent(
        id: localReceiptID,
        serverTransactionID: "server-local-receipt-acceptance",
        claimToken: localReceiptClaimToken
      )
    )
    expectNoDifference(acceptedLocalReceipt.status, .confirmed, upstreamDeliverySource)
    expectNoDifference(
      acceptedLocalReceipt.confirmationSource,
      .webSocketTransactOK,
      upstreamDeliverySource
    )
    expectNoDifference(
      acceptedLocalReceipt.serverTransactionID,
      "server-local-receipt-acceptance",
      upstreamDeliverySource
    )
    let pendingCountAfterLocalReceipt = await runtime.pendingMutationCount()
    expectNoDifference(pendingCountAfterLocalReceipt, 9_998, upstreamDeliverySource)
    let decodeCountAfterLocalReceipt =
      await runtime.persistence.currentDecodedOutboxBodyCount()
    expectNoDifference(
      decodeCountAfterLocalReceipt,
      1,
      upstreamDeliverySource
    )

    let revisionBeforeMissingAcceptance = try await runtime.persistence.currentOutboxRevision()
    await runtime.persistence.resetDecodedOutboxBodyCount()
    let missing = try await runtime.acceptMutationIfPresent(
      id: "tx-accept-row-missing",
      serverTransactionID: "server-missing",
      claimToken: nil
    )
    expectNoDifference(missing, nil, upstreamDeliverySource)
    let missingDecodeCount = await runtime.persistence.currentDecodedOutboxBodyCount()
    expectNoDifference(missingDecodeCount, 0, upstreamDeliverySource)
    let revisionAfterMissingAcceptance = try await runtime.persistence.currentOutboxRevision()
    expectNoDifference(
      revisionAfterMissingAcceptance,
      revisionBeforeMissingAcceptance,
      upstreamDeliverySource
    )
  }

  @Test
  func pendingMutationCountReadsSharedDurableStateInsteadOfResidentActor() async throws {
    let now = InstantTimestamp(milliseconds: 1_700_000_096_000)
    let cacheURL = try temporaryOutboxHydrationCacheURL()
    let writer = try await makeRuntime(appID: "outbox-durable-count", cacheURL: cacheURL)
    let independentReader = try await makeRuntime(
      appID: "outbox-durable-count",
      cacheURL: cacheURL
    )
    let initiallyResident = await independentReader.mutationDeliveryBarrierMutations()
    expectNoDifference(initiallyResident, [], upstreamDeliverySource)

    let first = makeTransaction(id: "tx-shared-durable-count-first", at: now)
    let second = makeTransaction(
      id: "tx-shared-durable-count-second",
      at: InstantTimestamp(milliseconds: now.milliseconds + 1)
    )
    try await writer.transact(
      first,
      createdAt: now
    )
    try await writer.transact(
      second,
      createdAt: InstantTimestamp(milliseconds: now.milliseconds + 1)
    )

    let durableCount = await independentReader.pendingMutationCount()
    expectNoDifference(durableCount, 2, upstreamDeliverySource)
    _ = try await writer.confirmMutation(id: first.id)
    let afterConfirmationCount = await independentReader.pendingMutationCount()
    expectNoDifference(afterConfirmationCount, 1, upstreamDeliverySource)
    let stillResident = await independentReader.mutationDeliveryBarrierMutations()
    expectNoDifference(
      stillResident,
      [],
      "The independently bootstrapped actor remains stale; the count must come from SQLite."
    )
  }

  @Test
  func crossRuntimeDeliveredMutationUsesDurableIdentityForTerminalRejection() async throws {
    let now = InstantTimestamp(milliseconds: 1_700_000_096_250)
    let cacheURL = try temporaryOutboxHydrationCacheURL()
    let transaction = makeTransaction(id: "tx-cross-runtime-terminal-rejection", at: now)
    let liveSession = LiveReactorParitySession(messages: [
      liveReactorInitOK(attrs: liveReactorTodoServerAttrs)
    ])
    let reader = try await makeRuntime(
      appID: "outbox-cross-runtime-terminal-rejection",
      cacheURL: cacheURL,
      liveTransport: liveSession.transport,
      autoConnectLiveTransport: false
    )
    let writer = try await makeRuntime(
      appID: "outbox-cross-runtime-terminal-rejection",
      cacheURL: cacheURL
    )
    let initialReaderBarrier = await reader.mutationDeliveryBarrierMutations()
    expectNoDifference(initialReaderBarrier, [], upstreamDeliverySource)

    try await writer.transact(transaction, createdAt: now)
    _ = try await reader.connect()
    try await instantLiveWithTimeout(
      operation: "wait for cross-runtime mutation delivery",
      timeoutMilliseconds: 5_000
    ) {
      await liveSession.waitForSentMessageCount(2)
    }
    let sentBeforeRejection = await liveSession.sentMessages()
    expectNoDifference(
      sentBeforeRejection.map(\.op),
      ["init", "transact"],
      upstreamDeliverySource
    )
    #expect(sentBeforeRejection.last?.fields["tx-steps"]?.arrayValue?.isEmpty == false)

    await liveSession.enqueue(
      InstantLiveMessage(
        op: "error",
        clientEventID: transaction.id,
        fields: [
          "message": .string("The cross-runtime mutation is not permitted."),
          "status": .number(400),
          "type": .string("permission-denied"),
        ]
      )
    )
    let rejected = try await instantLiveWithTimeout(
      operation: "wait for cross-runtime terminal rejection",
      timeoutMilliseconds: 5_000
    ) {
      while true {
        if let mutation = await reader.outboxMutations().first(where: {
          $0.id == transaction.id && $0.status == .failed
        }) {
          return mutation
        }
        try Task.checkCancellation()
        await Task.yield()
      }
    }

    expectNoDifference(rejected.failure?.code, .permissionRejected, upstreamDeliverySource)
    expectNoDifference(rejected.transaction, transaction, upstreamDeliverySource)
    let visible = try TodoExample.decode(await reader.store.materialize(TodoExample.query))
    expectNoDifference(visible, [], upstreamDeliverySource)
    let connectionStatus = try await reader.connectionStatus()
    expectNoDifference(connectionStatus.state, .opened, upstreamDeliverySource)
    expectNoDifference(connectionStatus.lastErrorMessage, nil, upstreamDeliverySource)
    let sentAfterRejection = await liveSession.sentMessages()
    expectNoDifference(
      sentAfterRejection.filter { $0.op == "transact" }.count,
      1,
      upstreamDeliverySource
    )
    _ = try? await reader.closeConnection()
  }

  @Test
  func explicitCloseWinsOverAnInFlightMutationSendFailure() async throws {
    let now = InstantTimestamp(milliseconds: 1_700_000_096_375)
    let transaction = makeTransaction(id: "tx-close-during-live-send", at: now)
    let liveTransport = CloseDuringTransactLiveTransport()
    var configuration = InstantRuntimeConfiguration(
      appID: "outbox-close-during-live-send",
      apiURI: URL(string: "https://api.example.test")!,
      websocketURI: URL(string: "wss://socket.example.test/runtime/session")!,
      persistenceURL: try temporaryOutboxHydrationCacheURL(),
      initialAttributes: TodoExample.attributes,
      liveTransport: liveTransport.transport
    )
    configuration.autoConnectLiveTransport = false
    configuration.liveReconnectSleep = { _ in }
    let runtime = try await InstantRuntime.bootstrap(configuration: configuration)
    _ = try await runtime.connect()

    try await runtime.transact(transaction, createdAt: now)
    try await instantLiveWithTimeout(
      operation: "wait for mutation send before explicit close",
      timeoutMilliseconds: 5_000
    ) {
      await liveTransport.waitForBlockedTransactSend()
    }
    let closeStatus = try await runtime.closeConnection()
    expectNoDifference(closeStatus.state, .closed, upstreamDeliverySource)
    expectNoDifference(closeStatus.lastErrorMessage, nil, upstreamDeliverySource)
    try await instantLiveWithTimeout(
      operation: "wait for in-flight send to observe explicit close",
      timeoutMilliseconds: 5_000
    ) {
      await liveTransport.waitForTransactSendFailure()
    }

    // Give the failed sender ample scheduler turns to attempt the stale reconnect that this
    // regression guards against, without hiding a hang behind a wall-clock sleep.
    for _ in 0..<1_000 {
      await Task.yield()
    }
    let finalStatus = try await runtime.connectionStatus()
    expectNoDifference(finalStatus.state, .closed, upstreamDeliverySource)
    expectNoDifference(finalStatus.lastErrorMessage, nil, upstreamDeliverySource)
    let connectionCount = await liveTransport.connectionCount()
    expectNoDifference(connectionCount, 1, upstreamDeliverySource)
    let pending = await runtime.pendingMutations()
    let durable = try #require(pending.first { $0.id == transaction.id })
    expectNoDifference(durable.transaction, transaction, upstreamDeliverySource)
  }

  @Test
  func cancelledConnectionQueuedOnTheSerialGateCannotReopen() async throws {
    let firstSession = LiveReactorParitySession(messages: [
      liveReactorInitOK(
        attrs: liveReactorTodoServerAttrs,
        sessionID: "queued-connect-first"
      )
    ])
    let secondSession = LiveReactorParitySession(messages: [
      liveReactorInitOK(
        attrs: liveReactorTodoServerAttrs,
        sessionID: "queued-connect-second"
      )
    ])
    let liveTransport = QueuedConnectCancellationTransport(
      sessions: [firstSession, secondSession]
    )
    var configuration = InstantRuntimeConfiguration(
      appID: "outbox-cancelled-queued-connect",
      apiURI: URL(string: "https://api.example.test")!,
      websocketURI: URL(string: "wss://socket.example.test/runtime/session")!,
      persistenceURL: try temporaryOutboxHydrationCacheURL(),
      initialAttributes: TodoExample.attributes,
      liveTransport: liveTransport.transport
    )
    configuration.autoConnectLiveTransport = false
    let runtime = try await InstantRuntime.bootstrap(configuration: configuration)
    let firstConnect = Task { try await runtime.connect() }
    defer { firstConnect.cancel() }
    try await instantLiveWithTimeout(
      operation: "wait for first connection to hold the serial gate",
      timeoutMilliseconds: 5_000
    ) {
      await liveTransport.waitForFirstConnection()
    }

    let cancelledConnect = Task { try await runtime.connect() }
    cancelledConnect.cancel()
    await liveTransport.releaseFirstConnection()
    _ = try await instantLiveWithTimeout(
      operation: "wait for first serialized connection",
      timeoutMilliseconds: 5_000
    ) {
      try await firstConnect.value
    }
    do {
      _ = try await instantLiveWithTimeout(
        operation: "wait for cancelled queued connection",
        timeoutMilliseconds: 5_000
      ) {
        try await cancelledConnect.value
      }
      Issue.record("Expected the queued connection to preserve Task cancellation.")
    } catch is CancellationError {
    }

    let connectionCount = await liveTransport.connectionCount()
    expectNoDifference(connectionCount, 1, upstreamDeliverySource)
    let connectionState = try await runtime.connectionStatus().state
    expectNoDifference(connectionState, .opened, upstreamDeliverySource)
    _ = try? await runtime.closeConnection()
  }

  @Test
  func durableOutboxInspectionSynchronizesAnExternalStoreRevisionBeforeLocalQuery() async throws {
    let now = InstantTimestamp(milliseconds: 1_700_000_096_500)
    let cacheURL = try temporaryOutboxHydrationCacheURL()
    let reader = try await makeRuntime(
      appID: "outbox-inspection-store-synchronization",
      cacheURL: cacheURL
    )
    let writer = try await makeRuntime(
      appID: "outbox-inspection-store-synchronization",
      cacheURL: cacheURL
    )
    let transaction = makeTransaction(id: "tx-external-server-store", at: now)

    _ = try await writer.applyServerTransaction(
      transaction,
      receivedAt: InstantTimestamp(milliseconds: now.milliseconds + 1)
    )

    let inspected = await reader.pendingMutations()
    expectNoDifference(inspected, [], upstreamDeliverySource)
    let visible = try TodoExample.decode(try await reader.query(TodoExample.query))
    expectNoDifference(
      visible.map(\.id),
      ["todo-\(transaction.id)"],
      "A read-only outbox inspection must not bless a compact cache while leaving the hot store stale."
    )
  }

  @Test
  func identityMigrationDoesNotResurrectAnExternallyDeletedFinalRow() async throws {
    let now = InstantTimestamp(milliseconds: 1_700_000_096_625)
    let cacheURL = try temporaryOutboxHydrationCacheURL()
    let reader = try await makeRuntime(
      appID: "migration-external-final-delete",
      cacheURL: cacheURL
    )
    let created = makeTransaction(id: "server-migration-final-row", at: now)
    _ = try await reader.applyServerTransaction(created, receivedAt: now)
    let writer = try await makeRuntime(
      appID: "migration-external-final-delete",
      cacheURL: cacheURL
    )
    _ = try await writer.applyServerTransaction(
      InstantStoreTransaction(
        id: "server-migration-final-delete",
        operations: TodoExample.deleteOperations(id: "todo-\(created.id)")
      ),
      receivedAt: InstantTimestamp(milliseconds: now.milliseconds + 1)
    )

    let didMigrate = try await reader.rewriteResidentPersistenceSnapshotForTesting(
      name: "identity-after-external-final-delete"
    ) { $0 }

    expectNoDifference(didMigrate, false, upstreamDeliverySource)
    let readerTriples = await reader.store.snapshot().triples
    expectNoDifference(readerTriples, [], upstreamDeliverySource)
    let durable = try await reader.persistence.loadState().snapshot.store.triples
    expectNoDifference(durable, [], upstreamDeliverySource)
  }

  @Test
  func localStrictUpdateSeesAnExternallyDeletedFinalRowAsMissing() async throws {
    let now = InstantTimestamp(milliseconds: 1_700_000_096_750)
    let cacheURL = try temporaryOutboxHydrationCacheURL()
    let reader = try await makeRuntime(
      appID: "transact-external-final-delete",
      cacheURL: cacheURL
    )
    let created = makeTransaction(id: "server-transact-final-row", at: now)
    _ = try await reader.applyServerTransaction(created, receivedAt: now)
    let writer = try await makeRuntime(
      appID: "transact-external-final-delete",
      cacheURL: cacheURL
    )
    _ = try await writer.applyServerTransaction(
      InstantStoreTransaction(
        id: "server-transact-final-delete",
        operations: TodoExample.deleteOperations(id: "todo-\(created.id)")
      ),
      receivedAt: InstantTimestamp(milliseconds: now.milliseconds + 1)
    )

    do {
      _ = try await reader.transact(
        InstantStoreTransaction(
          id: "tx-update-externally-deleted-final-row",
          operations: TodoExample.updateTextOperations(
            id: "todo-\(created.id)",
            text: "must not resurrect",
            updatedAt: InstantTimestamp(milliseconds: now.milliseconds + 2),
            transactionID: "tx-update-externally-deleted-final-row"
          )
        )
      )
      Issue.record("Expected the strict update to observe the external final-row deletion.")
    } catch let error as InstantError {
      expectNoDifference(error.code, .validationFailed, upstreamDeliverySource)
      expectNoDifference(error.operation, "strict update entity", upstreamDeliverySource)
    }
    let readerTriples = await reader.store.snapshot().triples
    expectNoDifference(readerTriples, [], upstreamDeliverySource)
    let durable = try await reader.persistence.loadState().snapshot.store.triples
    expectNoDifference(durable, [], upstreamDeliverySource)
  }

  @Test
  func bootstrapLiveQueryPruningInstallsAnEmptyFinalStore() async throws {
    let now = InstantTimestamp(milliseconds: 1_700_000_096_875)
    let cacheURL = try temporaryOutboxHydrationCacheURL()
    let persistence = try SQLitePersistenceStore(fileURL: cacheURL)
    try await persistence.bootstrap()
    let transaction = makeTransaction(id: "server-bootstrap-prune-final-row", at: now)
    let triples = transaction.operations.compactMap { operation -> InstantTriple? in
      guard case let .insert(triple) = operation else { return nil }
      return triple
    }
    let result = InstantPersistedLiveQueryResult(
      replacement: InstantLiveQueryResultReplacement(
        key: "bootstrap-prune-final-row",
        triples: triples,
        pageInfo: nil
      ),
      updatedAt: now
    )
    let initial = try await persistence.loadState()
    let didSave = try await persistence.saveLiveRefresh(
      InstantPersistenceSnapshot(
        store: InstantStoreSnapshot(attributes: TodoExample.attributes, triples: triples)
      ),
      queryResults: [result],
      storeChanged: true,
      outboxChanged: false,
      metadataKey: "test.bootstrap-prune-final-row",
      metadataValue: "seeded",
      metadataUpdatedAt: now,
      expectedStoreRevision: initial.storeRevision,
      expectedOutboxRevision: initial.outboxRevision,
      expectedAttributeRevision: initial.attributeRevision
    )
    expectNoDifference(didSave, true, upstreamDeliverySource)
    var configuration = InstantRuntimeConfiguration(
      appID: "bootstrap-prune-final-row",
      persistenceURL: cacheURL,
      initialAttributes: TodoExample.attributes,
      now: { InstantTimestamp(milliseconds: now.milliseconds + 1) }
    )
    configuration.liveQueryResultPruningPolicy = InstantLiveQueryResultPruningPolicy(
      maxEntries: 0
    )

    let runtime = try await InstantRuntime.bootstrap(configuration: configuration)

    #expect(try await runtime.persistence.liveQueryResult(key: result.key) == nil)
    let runtimeTriples = await runtime.store.snapshot().triples
    expectNoDifference(runtimeTriples, [], upstreamDeliverySource)
    let visible = try TodoExample.decode(await runtime.store.materialize(TodoExample.query))
    expectNoDifference(visible, [], upstreamDeliverySource)
    let durable = try await runtime.persistence.loadState().snapshot.store.triples
    expectNoDifference(durable, [], upstreamDeliverySource)
  }

  @Test
  func metadataDiffPathsDeleteWarmCachedTriples() async throws {
    for path in MetadataDiffPath.allCases {
      let now = InstantTimestamp(milliseconds: 1_700_000_097_000)
      let cacheURL = try temporaryOutboxHydrationCacheURL()
      let persistence = try SQLitePersistenceStore(fileURL: cacheURL)
      try await persistence.bootstrap()
      let transaction = makeTransaction(id: "tx-metadata-delete-\(path.rawValue)", at: now)
      let triples = transaction.operations.compactMap { operation -> InstantTriple? in
        guard case let .insert(triple) = operation else { return nil }
        return triple
      }
      let initial = InstantPersistenceSnapshot(
        store: InstantStoreSnapshot(attributes: TodoExample.attributes, triples: triples)
      )
      try await persistence.saveSnapshot(initial)
      _ = try await persistence.loadCompactState()
      let targetStore = InstantStoreSnapshot(attributes: TodoExample.attributes, triples: [])
      let target = InstantPersistenceSnapshot(store: targetStore)
      let didSave: Bool
      switch path {
      case .store:
        didSave = try await persistence.saveStoreSnapshot(
          targetStore,
          replacing: initial.store,
          metadataKey: "test.metadata-delete.\(path.rawValue)",
          metadataValue: "deleted",
          metadataUpdatedAt: now,
          expectedStoreRevision: 1,
          expectedOutboxRevision: 1,
          expectedAttributeRevision: 1
        )
      case .snapshot:
        didSave = try await persistence.saveSnapshot(
          target,
          replacing: initial,
          metadataKey: "test.metadata-delete.\(path.rawValue)",
          metadataValue: "deleted",
          metadataUpdatedAt: now,
          expectedStoreRevision: 1,
          expectedAttributeRevision: 1,
          expectedOutboxRevision: 1
        )
      case .liveRefresh:
        didSave = try await persistence.saveLiveRefresh(
          target,
          replacing: initial,
          queryResults: [],
          storeChanged: true,
          outboxChanged: false,
          metadataKey: "test.metadata-delete.\(path.rawValue)",
          metadataValue: "deleted",
          metadataUpdatedAt: now,
          expectedStoreRevision: 1,
          expectedOutboxRevision: 1,
          expectedAttributeRevision: 1
        )
      }
      expectNoDifference(didSave, true, "metadata diff path: \(path.rawValue)")
      let reopened = try SQLitePersistenceStore(fileURL: cacheURL)
      try await reopened.bootstrap()
      let durable = try await reopened.loadState().snapshot
      expectNoDifference(durable.store.triples, [], "metadata diff path: \(path.rawValue)")
      expectNoDifference(durable.outbox, [])
    }
  }

  @Test
  func liveRefreshPreservesComponentsWhoseChangeFlagsAreFalse() async throws {
    let now = InstantTimestamp(milliseconds: 1_700_000_098_000)
    let cacheURL = try temporaryOutboxHydrationCacheURL()
    let persistence = try SQLitePersistenceStore(fileURL: cacheURL)
    try await persistence.bootstrap()
    let transaction = makeTransaction(id: "tx-live-refresh-unchanged", at: now)
    let triples = transaction.operations.compactMap { operation -> InstantTriple? in
      guard case let .insert(triple) = operation else { return nil }
      return triple
    }
    let initial = InstantPersistenceSnapshot(
      store: InstantStoreSnapshot(attributes: TodoExample.attributes, triples: triples),
      outbox: [PendingMutation(id: transaction.id, createdAt: now, transaction: transaction)]
    )
    try await persistence.saveSnapshot(initial)
    _ = try await persistence.loadCompactState()

    let didSave = try await persistence.saveLiveRefresh(
      InstantPersistenceSnapshot(
        store: InstantStoreSnapshot(attributes: [], triples: []),
        outbox: []
      ),
      queryResults: [],
      storeChanged: false,
      outboxChanged: false,
      metadataKey: "test.live-refresh-unchanged-components",
      metadataValue: "metadata-only",
      metadataUpdatedAt: now,
      expectedStoreRevision: 1,
      expectedOutboxRevision: 1,
      expectedAttributeRevision: 1
    )

    expectNoDifference(didSave, true)
    let compact = try await persistence.loadCompactState().snapshot
    expectNoDifference(Set(compact.store.attributes), Set(TodoExample.attributes))
    expectNoDifference(compact.outbox, [])
    let full = try await persistence.loadState().snapshot
    expectNoDifference(Set(full.store.triples), Set(triples))
    expectNoDifference(full.outbox.first?.transaction, transaction)
  }

  private func makeRuntime(
    appID: String,
    cacheURL: URL,
    mutationTransport: InstantMutationTransportClient = .local,
    liveTransport: InstantLiveTransportClient? = nil,
    autoConnectLiveTransport: Bool? = nil
  ) async throws -> InstantRuntime {
    var configuration = InstantRuntimeConfiguration(
      appID: appID,
      apiURI: URL(string: "https://api.example.test")!,
      websocketURI: URL(string: "wss://socket.example.test/runtime/session")!,
      persistenceURL: cacheURL,
      initialAttributes: TodoExample.attributes,
      mutationTransport: mutationTransport,
      liveTransport: liveTransport
    )
    configuration.autoConnectLiveTransport = autoConnectLiveTransport ?? (liveTransport != nil)
    return try await InstantRuntime.bootstrap(configuration: configuration)
  }

  private func makeTransaction(
    id: String,
    at timestamp: InstantTimestamp
  ) -> InstantStoreTransaction {
    InstantStoreTransaction(
      id: id,
      operations: TodoExample.createOperations(
        id: "todo-\(id)",
        text: "durable transport operations",
        createdAt: timestamp,
        transactionID: id
      )
    )
  }
}

private enum MetadataDiffPath: String, CaseIterable {
  case store
  case snapshot
  case liveRefresh
}

private actor OutboxHydrationTransportRecorder {
  private var recordedRequests: [InstantMutationTransportRequest] = []

  func record(_ request: InstantMutationTransportRequest) {
    recordedRequests.append(request)
  }

  func requests() -> [InstantMutationTransportRequest] {
    recordedRequests
  }
}

private actor CloseDuringTransactLiveTransport {
  nonisolated private let abortState = InstantLiveTestWireAbortState()
  private var messages = [
    liveReactorInitOK(
      attrs: liveReactorTodoServerAttrs,
      sessionID: "close-during-transact"
    )
  ]
  private var connections = 0
  private var receiveContinuation: InstantLiveTestPendingOperation<InstantLiveMessage>?
  private var transactSendBlocked = false
  private var transactSendBlockWaiters: [CheckedContinuation<Void, Never>] = []
  private var transactSendFailureObserved = false
  private var transactSendFailureWaiters: [CheckedContinuation<Void, Never>] = []
  private var transactSendContinuation: InstantLiveTestPendingOperation<Void>?
  private var isClosed = false

  nonisolated var transport: InstantLiveTransportClient {
    .connectionAttempts { _ in
      let connection = InstantLiveTestConnectionContinuation()
      return InstantLiveConnectionAttempt(
        connect: {
          connection.start { await self.connect() }
          return try await connection.connect()
        },
        abort: { connection.abort() }
      )
    }
  }

  func connectionCount() -> Int {
    connections
  }

  func waitForBlockedTransactSend() async {
    guard !transactSendBlocked else { return }
    await withCheckedContinuation { continuation in
      transactSendBlockWaiters.append(continuation)
    }
  }

  func waitForTransactSendFailure() async {
    guard !transactSendFailureObserved else { return }
    await withCheckedContinuation { continuation in
      transactSendFailureWaiters.append(continuation)
    }
  }

  private func connect() -> InstantLiveWebSocketSession {
    connections += 1
    return InstantLiveWebSocketSession(
      send: { message in try await self.send(message) },
      receive: {
        try self.abortState.check()
        return try await self.receive()
      },
      close: { await self.close() },
      abort: { self.abortState.abort() }
    )
  }

  private func send(_ message: InstantLiveMessage) async throws {
    try abortState.check()
    guard message.op == "transact" else { return }
    transactSendBlocked = true
    let blockWaiters = transactSendBlockWaiters
    transactSendBlockWaiters.removeAll()
    for waiter in blockWaiters {
      waiter.resume()
    }
    if !isClosed {
      let id = UUID()
      defer { clearTransactSendContinuation(id: id) }
      try await withCheckedThrowingContinuation {
        (continuation: CheckedContinuation<Void, Error>) in
        let continuation = InstantLiveTestThrowingContinuationBox(continuation)
        guard
          let abortToken = abortState.register({
            continuation.resume(returning: ())
          })
        else {
          continuation.resume(returning: ())
          return
        }
        transactSendContinuation = InstantLiveTestPendingOperation(
          id: id,
          abortToken: abortToken,
          continuation: continuation
        )
      }
    }
    transactSendFailureObserved = true
    let failureWaiters = transactSendFailureWaiters
    transactSendFailureWaiters.removeAll()
    for waiter in failureWaiters {
      waiter.resume()
    }
    throw InstantError(
      code: .networkFailed,
      operation: "send mutation interrupted by explicit close",
      message: "The explicit close interrupted the in-flight mutation send.",
      recovery: "Keep the durable mutation pending until the caller explicitly reconnects."
    )
  }

  private func receive() async throws -> InstantLiveMessage {
    try abortState.check()
    if !messages.isEmpty {
      return messages.removeFirst()
    }
    if isClosed {
      throw CancellationError()
    }
    let id = UUID()
    defer { clearReceiveContinuation(id: id) }
    return try await withCheckedThrowingContinuation { continuation in
      let continuation = InstantLiveTestThrowingContinuationBox(continuation)
      guard
        let abortToken = abortState.register({
          continuation.resume(throwing: CancellationError())
        })
      else {
        continuation.resume(throwing: CancellationError())
        return
      }
      receiveContinuation = InstantLiveTestPendingOperation(
        id: id,
        abortToken: abortToken,
        continuation: continuation
      )
    }
  }

  private func close() {
    isClosed = true
    abortState.abort()
    receiveContinuation = nil
    transactSendContinuation = nil
  }

  private func clearReceiveContinuation(id: UUID) {
    guard let receiveContinuation, receiveContinuation.id == id else { return }
    abortState.unregister(receiveContinuation.abortToken)
    self.receiveContinuation = nil
  }

  private func clearTransactSendContinuation(id: UUID) {
    guard let transactSendContinuation, transactSendContinuation.id == id else { return }
    abortState.unregister(transactSendContinuation.abortToken)
    self.transactSendContinuation = nil
  }
}

private actor QueuedConnectCancellationTransport {
  private let sessions: [LiveReactorParitySession]
  private var connections = 0
  private var firstConnectionStarted = false
  private var firstConnectionWaiters: [CheckedContinuation<Void, Never>] = []
  private var firstConnectionReleased = false
  private var firstConnectionPending:
    [(InstantLiveTestConnectionContinuation, InstantLiveWebSocketSession)] = []

  init(sessions: [LiveReactorParitySession]) {
    self.sessions = sessions
  }

  nonisolated var transport: InstantLiveTransportClient {
    .connectionAttempts { _ in
      let connection = InstantLiveTestConnectionContinuation()
      return InstantLiveConnectionAttempt(
        connect: {
          Task { await self.beginConnection(connection) }
          return try await connection.connect()
        },
        abort: { connection.abort() }
      )
    }
  }

  func connectionCount() -> Int {
    connections
  }

  func waitForFirstConnection() async {
    guard !firstConnectionStarted else { return }
    await withCheckedContinuation { continuation in
      firstConnectionWaiters.append(continuation)
    }
  }

  func releaseFirstConnection() {
    firstConnectionReleased = true
    let pending = firstConnectionPending
    firstConnectionPending.removeAll()
    for (connection, session) in pending {
      connection.succeed(session)
    }
  }

  private func beginConnection(_ connection: InstantLiveTestConnectionContinuation) {
    let index = connections
    connections += 1
    guard sessions.indices.contains(index) else {
      connection.fail(
        InstantError(
          code: .networkFailed,
          operation: "connect cancelled queued live transport",
          message: "No scripted live session remains.",
          recovery: "A cancelled queued connection must not reach the transport."
        )
      )
      return
    }
    let session = sessions[index].webSocketSession
    if index == 0 {
      firstConnectionStarted = true
      let waiters = firstConnectionWaiters
      firstConnectionWaiters.removeAll()
      for waiter in waiters {
        waiter.resume()
      }
      if !firstConnectionReleased {
        firstConnectionPending.append((connection, session))
        return
      }
    }
    connection.succeed(session)
  }
}

private func temporaryOutboxHydrationCacheURL() throws -> URL {
  let directory = FileManager.default.temporaryDirectory
    .appendingPathComponent("InstantOutboxHydrationTests-\(UUID().uuidString)")
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  return directory.appendingPathComponent("state.sqlite")
}

private func corruptOutboxJSON(id: String, in cacheURL: URL) throws {
  var database: OpaquePointer?
  guard sqlite3_open_v2(cacheURL.path, &database, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK else {
    defer { sqlite3_close(database) }
    throw NSError(
      domain: "InstantOutboxHydrationTests",
      code: 1,
      userInfo: [NSLocalizedDescriptionKey: "Could not open the outbox fault-injection database."]
    )
  }
  defer { sqlite3_close(database) }
  var statement: OpaquePointer?
  guard sqlite3_prepare_v2(
    database,
    "UPDATE instant_outbox SET json = '{malformed-json' WHERE mutation_id = ?",
    -1,
    &statement,
    nil
  ) == SQLITE_OK else {
    throw NSError(
      domain: "InstantOutboxHydrationTests",
      code: 2,
      userInfo: [NSLocalizedDescriptionKey: "Could not prepare the outbox fault injection."]
    )
  }
  defer { sqlite3_finalize(statement) }
  let bindResult = id.withCString {
    sqlite3_bind_text(statement, 1, $0, -1, outboxHydrationSQLiteTransient)
  }
  guard bindResult == SQLITE_OK else {
    throw NSError(
      domain: "InstantOutboxHydrationTests",
      code: 3,
      userInfo: [NSLocalizedDescriptionKey: "Could not bind the outbox fault-injection id."]
    )
  }
  guard sqlite3_step(statement) == SQLITE_DONE else {
    throw NSError(
      domain: "InstantOutboxHydrationTests",
      code: 4,
      userInfo: [NSLocalizedDescriptionKey: "Could not install the outbox JSON sentinel."]
    )
  }
}

private let outboxHydrationSQLiteTransient = unsafeBitCast(
  -1,
  to: sqlite3_destructor_type.self
)

private let upstreamDeliverySource =
  "upstream/instant/client/packages/core/src/Reactor.js _flushPendingMessages/_sendMutation [adapted: Swift persists typed transactions in SQLite and must selectively rehydrate the exact durable operations before lowering tx-steps.]"

private let upstreamQuerySource =
  "upstream/instant/client/packages/core/src/Reactor.js queryOnce/_startQuerySub [adapted: Swift's auto-connect option governs opening a session, not whether an already-open explicit session sends a query.]"
