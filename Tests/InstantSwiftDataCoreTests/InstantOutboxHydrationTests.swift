import CustomDump
import Foundation
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
    var configuration = InstantRuntimeConfiguration(
      appID: "mutation-permission-service-unavailable",
      persistenceURL: try temporaryOutboxHydrationCacheURL(),
      initialAttributes: TodoExample.attributes,
      liveTransport: transport.transport
    )
    configuration.liveReconnectSleep = { _ in }
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

    let todos = try TodoExample.decode(try await runtime.query(TodoExample.query))
    expectNoDifference(todos.map(\.id), ["todo-\(successor.id)"], upstreamDeliverySource)
    let durable = try await runtime.persistence.loadState().snapshot.outbox
    let durableRejected = try #require(durable.first { $0.id == rejected.id })
    let durableSuccessor = try #require(durable.first { $0.id == successor.id })
    expectNoDifference(durableRejected.status, .failed, upstreamDeliverySource)
    expectNoDifference(durableRejected.transaction, rejected, upstreamDeliverySource)
    expectNoDifference(durableSuccessor.status, .pending, upstreamDeliverySource)
    expectNoDifference(durableSuccessor.transaction, successor, upstreamDeliverySource)
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

    let residentPending = try #require(
      await runtime.mutationDeliveryBarrierMutations().first { $0.id == transaction.id }
    )
    expectNoDifference(residentPending.transaction.operations, [], upstreamDeliverySource)
    #expect(residentPending.rollbackTransaction?.operations.isEmpty == true)
    let hydratedPending = try #require(
      await runtime.pendingMutations().first { $0.id == transaction.id }
    )
    expectNoDifference(hydratedPending.transaction, transaction, upstreamDeliverySource)
    #expect(hydratedPending.rollbackTransaction?.operations.isEmpty == false)
    let compactPersistence = try #require(
      try await runtime.persistence.loadCompactState().snapshot.outbox.first {
        $0.id == transaction.id
      }
    )
    expectNoDifference(compactPersistence.transaction.operations, [], upstreamDeliverySource)
    #expect(compactPersistence.rollbackTransaction?.operations.isEmpty == true)
    let inspectedPending = try #require(
      await runtime.outboxMutations().first { $0.id == transaction.id }
    )
    expectNoDifference(inspectedPending.transaction, transaction, upstreamDeliverySource)

    _ = try await runtime.confirmMutation(id: transaction.id)

    let residentConfirmed = try #require(
      await runtime.mutationDeliveryBarrierMutations().first { $0.id == transaction.id }
    )
    expectNoDifference(residentConfirmed.status, .confirmed, upstreamDeliverySource)
    expectNoDifference(residentConfirmed.transaction.operations, [], upstreamDeliverySource)
    #expect(residentConfirmed.rollbackTransaction?.operations.isEmpty == true)
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

    let didMigrate = try await reader.migrateLocalPersistenceSnapshot(
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
      expectedOutboxRevision: initial.outboxRevision
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
      let mutation = PendingMutation(id: transaction.id, createdAt: now, transaction: transaction)
      let initial = InstantPersistenceSnapshot(
        store: InstantStoreSnapshot(attributes: TodoExample.attributes, triples: triples),
        outbox: [mutation]
      )
      try await persistence.saveSnapshot(initial)
      _ = try await persistence.loadCompactState()
      let targetStore = InstantStoreSnapshot(attributes: TodoExample.attributes, triples: [])
      let target = InstantPersistenceSnapshot(store: targetStore, outbox: [mutation])
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
          expectedOutboxRevision: 1
        )
      case .snapshot:
        didSave = try await persistence.saveSnapshot(
          target,
          replacing: initial,
          metadataKey: "test.metadata-delete.\(path.rawValue)",
          metadataValue: "deleted",
          metadataUpdatedAt: now,
          expectedStoreRevision: 1,
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
          expectedOutboxRevision: 1
        )
      }
      expectNoDifference(didSave, true, "metadata diff path: \(path.rawValue)")
      let reopened = try SQLitePersistenceStore(fileURL: cacheURL)
      try await reopened.bootstrap()
      let durable = try await reopened.loadState().snapshot
      expectNoDifference(durable.store.triples, [], "metadata diff path: \(path.rawValue)")
      expectNoDifference(durable.outbox.first?.transaction, transaction)
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
      expectedOutboxRevision: 1
    )

    expectNoDifference(didSave, true)
    let compact = try await persistence.loadCompactState().snapshot
    expectNoDifference(compact.store.attributes, TodoExample.attributes)
    expectNoDifference(compact.outbox.map(\.id), [transaction.id])
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
  private var messages = [
    liveReactorInitOK(
      attrs: liveReactorTodoServerAttrs,
      sessionID: "close-during-transact"
    )
  ]
  private var connections = 0
  private var receiveContinuation: CheckedContinuation<InstantLiveMessage, Error>?
  private var transactSendBlocked = false
  private var transactSendBlockWaiters: [CheckedContinuation<Void, Never>] = []
  private var transactSendFailureObserved = false
  private var transactSendFailureWaiters: [CheckedContinuation<Void, Never>] = []
  private var transactSendContinuation: CheckedContinuation<Void, Never>?
  private var isClosed = false

  nonisolated var transport: InstantLiveTransportClient {
    InstantLiveTransportClient { _ in await self.connect() }
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
      receive: { try await self.receive() },
      close: { await self.close() }
    )
  }

  private func send(_ message: InstantLiveMessage) async throws {
    guard message.op == "transact" else { return }
    transactSendBlocked = true
    let blockWaiters = transactSendBlockWaiters
    transactSendBlockWaiters.removeAll()
    for waiter in blockWaiters {
      waiter.resume()
    }
    if !isClosed {
      await withCheckedContinuation { continuation in
        transactSendContinuation = continuation
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
    if !messages.isEmpty {
      return messages.removeFirst()
    }
    if isClosed {
      throw CancellationError()
    }
    return try await withCheckedThrowingContinuation { continuation in
      receiveContinuation = continuation
    }
  }

  private func close() {
    isClosed = true
    receiveContinuation?.resume(throwing: CancellationError())
    receiveContinuation = nil
    transactSendContinuation?.resume()
    transactSendContinuation = nil
  }
}

private actor QueuedConnectCancellationTransport {
  private let sessions: [LiveReactorParitySession]
  private var connections = 0
  private var firstConnectionStarted = false
  private var firstConnectionWaiters: [CheckedContinuation<Void, Never>] = []
  private var firstConnectionReleased = false
  private var firstConnectionReleaseWaiters: [CheckedContinuation<Void, Never>] = []

  init(sessions: [LiveReactorParitySession]) {
    self.sessions = sessions
  }

  nonisolated var transport: InstantLiveTransportClient {
    InstantLiveTransportClient { _ in try await self.connect() }
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
    let waiters = firstConnectionReleaseWaiters
    firstConnectionReleaseWaiters.removeAll()
    for waiter in waiters {
      waiter.resume()
    }
  }

  private func connect() async throws -> InstantLiveWebSocketSession {
    let index = connections
    connections += 1
    guard sessions.indices.contains(index) else {
      throw InstantError(
        code: .networkFailed,
        operation: "connect cancelled queued live transport",
        message: "No scripted live session remains.",
        recovery: "A cancelled queued connection must not reach the transport."
      )
    }
    if index == 0 {
      firstConnectionStarted = true
      let waiters = firstConnectionWaiters
      firstConnectionWaiters.removeAll()
      for waiter in waiters {
        waiter.resume()
      }
      if !firstConnectionReleased {
        await withCheckedContinuation { continuation in
          firstConnectionReleaseWaiters.append(continuation)
        }
      }
    }
    return sessions[index].webSocketSession
  }
}

private func temporaryOutboxHydrationCacheURL() throws -> URL {
  let directory = FileManager.default.temporaryDirectory
    .appendingPathComponent("InstantOutboxHydrationTests-\(UUID().uuidString)")
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  return directory.appendingPathComponent("state.sqlite")
}

private let upstreamDeliverySource =
  "upstream/instant/client/packages/core/src/Reactor.js _flushPendingMessages/_sendMutation [adapted: Swift persists typed transactions in SQLite and must selectively rehydrate the exact durable operations before lowering tx-steps.]"

private let upstreamQuerySource =
  "upstream/instant/client/packages/core/src/Reactor.js queryOnce/_startQuerySub [adapted: Swift's auto-connect option governs opening a session, not whether an already-open explicit session sends a query.]"
