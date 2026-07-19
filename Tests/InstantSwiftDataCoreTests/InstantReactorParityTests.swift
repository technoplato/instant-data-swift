import CustomDump
import Foundation
@testable import InstantSwiftDataCore
import Testing

@Suite(.serialized)
struct InstantReactorParityTests {
  @Test
  func upstreamReactorQuerySubsRoundTripsCachedResultsAcrossRelaunch() async throws {
    let cacheURL = try temporaryReactorParityCacheURL()
    let createdAt = InstantTimestamp(milliseconds: 1_700_000_030_000)
    let cachedAt = InstantTimestamp(milliseconds: createdAt.milliseconds + 10)
    let plan = InstantQueryPlan(
      id: "reactor.query-subs.todos",
      namespace: TodoExample.namespace
    )
    let query: InstantLiveJSONValue = .object([TodoExample.namespace: .object([:])])
    let liveSession = LiveReactorParitySession(messages: [
      liveReactorInitOK(attrs: liveReactorTodoServerAttrs),
      liveReactorAddQueryOK(
        query: query,
        processedTransactionID: "0",
        result: liveReactorTodoQueryResult(
          id: "todo-reactor-query-subs",
          text: "restore cached querySub",
          createdAt: createdAt
        )
      ),
    ])
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "reactor-query-subs-parity",
        persistenceURL: cacheURL,
        initialAttributes: TodoExample.attributes,
        now: { cachedAt },
        liveTransport: liveSession.transport
      )
    )
    let stream = await runtime.observe(plan)
    var iterator = stream.makeAsyncIterator()
    let initial = try #require(await iterator.next())
    expectNoDifference(initial.values, [], reactorQuerySubsSource)
    _ = try await runtime.connect()

    let emission = try #require(await iterator.next())
    let liveTodos = try TodoExample.decode(emission.values)
    expectNoDifference(
      liveTodos,
      [
        TodoRecord(
          id: "todo-reactor-query-subs",
          text: "restore cached querySub",
          isCompleted: false,
          createdAt: createdAt
        )
      ],
      reactorQuerySubsSource
    )
    let sentMessages = await liveSession.sentMessages()
    expectNoDifference(sentMessages.map(\.op), ["init", "add-query"], reactorQuerySubsSource)
    expectNoDifference(sentMessages.last?.fields["q"], query, reactorQuerySubsSource)

    _ = try await runtime.queryOnce(plan)
    let loadedCachedQuery = try await runtime.cachedQuery(plan)
    let cachedQuery = try #require(loadedCachedQuery)
    expectNoDifference(emission.queryID, "reactor.query-subs.todos", reactorQuerySubsSource)
    expectNoDifference(cachedQuery.queryID, plan.id, reactorQuerySubsSource)
    expectNoDifference(cachedQuery.cacheKey, plan.cacheKey, reactorQuerySubsSource)
    expectNoDifference(cachedQuery.plan, plan, reactorQuerySubsSource)
    expectNoDifference(cachedQuery.emission.values, emission.values, reactorQuerySubsSource)
    expectNoDifference(cachedQuery.updatedAt, cachedAt, reactorQuerySubsSource)

    let relaunchedRuntime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "reactor-query-subs-parity",
        persistenceURL: cacheURL,
        initialAttributes: TodoExample.attributes
      )
    )
    let relaunchedCache = try #require(try await relaunchedRuntime.cachedQuery(plan))
    let relaunchedTodos = try TodoExample.decode(relaunchedCache.emission.values)
    expectNoDifference(
      relaunchedTodos,
      [
        TodoRecord(
          id: "todo-reactor-query-subs",
          text: "restore cached querySub",
          isCompleted: false,
          createdAt: createdAt
        )
      ],
      reactorQuerySubsSource
    )
    let relaunchedCacheKeys = try await relaunchedRuntime.cachedQueries().map(\.cacheKey)
    expectNoDifference(relaunchedCacheKeys, [plan.cacheKey], reactorQuerySubsSource)

    try await relaunchedRuntime.closeConnection()
    do {
      _ = try await relaunchedRuntime.queryOnce(plan)
      Issue.record("Expected closed queryOnce to fail with a cached querySub-equivalent result.")
    } catch let error as InstantError {
      expectNoDifference(error.code, .networkFailed, reactorQuerySubsSource)
      expectNoDifference(error.operation, "queryOnce", reactorQuerySubsSource)
      expectNoDifference(error.cachedQuery?.queryID, plan.id, reactorQuerySubsSource)
      expectNoDifference(error.cachedQuery?.cacheKey, plan.cacheKey, reactorQuerySubsSource)
      expectNoDifference(error.cachedQuery?.emission.values, emission.values, reactorQuerySubsSource)
    }
  }

  @Test
  func upstreamReactorOptimisticTxIsNotOverwrittenByRefreshOK() async throws {
    let cacheURL = try temporaryReactorParityCacheURL()
    let createdAt = InstantTimestamp(milliseconds: 1_700_000_040_000)
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "reactor-optimistic-refresh-parity",
        persistenceURL: cacheURL,
        initialAttributes: TodoExample.attributes
      )
    )
    try await runtime.transact(
      InstantStoreTransaction(
        id: "tx-reactor-optimistic-seed",
        operations: TodoExample.createOperations(
          id: "todo-reactor-optimistic",
          text: "joe",
          createdAt: createdAt,
          transactionID: "tx-reactor-optimistic-seed"
        )
      ),
      createdAt: createdAt
    )
    try await runtime.confirmMutation(id: "tx-reactor-optimistic-seed")
    var visibleTexts = try await reactorOptimisticTextsFromQueryOnce(runtime)
    expectNoDifference(visibleTexts, ["joe"], reactorOptimisticRefreshSource)

    let joe2At = InstantTimestamp(milliseconds: createdAt.milliseconds + 1)
    try await runtime.transact(
      InstantStoreTransaction(
        id: "tx-reactor-optimistic-joe2",
        operations: TodoExample.updateTextOperations(
          id: "todo-reactor-optimistic",
          text: "joe2",
          updatedAt: joe2At,
          transactionID: "tx-reactor-optimistic-joe2"
        )
      ),
      createdAt: joe2At
    )
    visibleTexts = try await reactorOptimisticTextsFromQueryOnce(runtime)
    expectNoDifference(visibleTexts, ["joe2"], reactorOptimisticRefreshSource)

    let joe3At = InstantTimestamp(milliseconds: createdAt.milliseconds + 2)
    try await runtime.transact(
      InstantStoreTransaction(
        id: "tx-reactor-optimistic-joe3",
        operations: TodoExample.updateTextOperations(
          id: "todo-reactor-optimistic",
          text: "joe3",
          updatedAt: joe3At,
          transactionID: "tx-reactor-optimistic-joe3"
        )
      ),
      createdAt: joe3At
    )
    visibleTexts = try await reactorOptimisticTextsFromQueryOnce(runtime)
    expectNoDifference(visibleTexts, ["joe3"], reactorOptimisticRefreshSource)

    try await runtime.confirmMutation(id: "tx-reactor-optimistic-joe2")
    _ = try await runtime.applyLiveRefresh(
      InstantLiveRefreshOK(
        clientEventID: nil,
        processedTransactionID: "server-tx-100",
        attrs: liveReactorTodoServerAttrs,
        computations: [
          liveReactorTodoComputation(
            query: .object([TodoExample.namespace: .object([:])]),
            id: "todo-reactor-optimistic",
            text: "joe",
            createdAt: createdAt,
            processedTransactionID: "server-tx-100"
          )
        ]
      )
    )
    let refreshEmission = try await runtime.queryOnce(TodoExample.query)
    visibleTexts = try TodoExample.decode(refreshEmission.values).map(\.text)
    let refreshedCache = try #require(try await runtime.cachedQuery(TodoExample.query))
    let refreshedCacheTexts = try TodoExample.decode(refreshedCache.emission.values).map(\.text)
    let pendingAfterFirstConfirm = await runtime.pendingMutations().map(\.id)
    expectNoDifference(visibleTexts, ["joe3"], reactorOptimisticRefreshSource)
    expectNoDifference(refreshedCacheTexts, ["joe3"], reactorOptimisticRefreshSource)
    expectNoDifference(
      pendingAfterFirstConfirm,
      ["tx-reactor-optimistic-joe3"],
      reactorOptimisticRefreshSource
    )

    let relaunchedRuntime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "reactor-optimistic-refresh-parity",
        persistenceURL: cacheURL,
        initialAttributes: TodoExample.attributes
      )
    )
    let relaunchedTexts = try await reactorOptimisticTextsFromQueryOnce(relaunchedRuntime)
    let relaunchedPending = await relaunchedRuntime.pendingMutations().map(\.id)
    expectNoDifference(relaunchedTexts, ["joe3"], reactorOptimisticRefreshSource)
    expectNoDifference(
      relaunchedPending,
      ["tx-reactor-optimistic-joe3"],
      reactorOptimisticRefreshSource
    )

    try await relaunchedRuntime.confirmMutation(id: "tx-reactor-optimistic-joe3")
    let afterSecondConfirmTexts = try await reactorOptimisticTextsFromQueryOnce(relaunchedRuntime)
    let pendingAfterSecondConfirm = await relaunchedRuntime.pendingMutations()
    expectNoDifference(afterSecondConfirmTexts, ["joe3"], reactorOptimisticRefreshSource)
    expectNoDifference(pendingAfterSecondConfirm, [], reactorOptimisticRefreshSource)
  }

  /// Canonical source:
  /// upstream/instant/client/packages/core/src/Reactor.js refresh-ok branch,
  /// which creates a new store from each computation's returned triples.
  @Test
  func upstreamReactorRefreshReplacesRowsMissingFromAuthoritativeResult() async throws {
    let cacheURL = try temporaryReactorParityCacheURL()
    let createdAt = InstantTimestamp(milliseconds: 1_700_000_042_000)
    let query: InstantLiveJSONValue = .object([TodoExample.namespace: .object([:])])
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "reactor-authoritative-refresh-removal",
        persistenceURL: cacheURL,
        initialAttributes: TodoExample.attributes
      )
    )

    _ = try await runtime.applyLiveRefresh(
      InstantLiveRefreshOK(
        clientEventID: nil,
        processedTransactionID: "server-refresh-present",
        attrs: liveReactorTodoServerAttrs,
        computations: [
          liveReactorTodoComputation(
            query: query,
            id: "todo-authoritative-refresh",
            text: "present",
            createdAt: createdAt,
            processedTransactionID: "server-refresh-present"
          )
        ]
      )
    )
    let presentTexts = try await reactorOptimisticTextsFromQueryOnce(runtime)
    expectNoDifference(presentTexts, ["present"], reactorAuthoritativeRefreshSource)

    _ = try await runtime.applyLiveRefresh(
      InstantLiveRefreshOK(
        clientEventID: nil,
        processedTransactionID: "server-refresh-empty",
        attrs: liveReactorTodoServerAttrs,
        computations: [
          .object([
            "instaql-query": query,
            "instaql-result": .array([]),
          ])
        ]
      )
    )
    let removedTexts = try await reactorOptimisticTextsFromQueryOnce(runtime)
    expectNoDifference(removedTexts, [], reactorAuthoritativeRefreshSource)
  }

  @Test
  func authoritativeRefreshRetainsTriplesOwnedByAnotherLiveQuery() async throws {
    let cacheURL = try temporaryReactorParityCacheURL()
    let createdAt = InstantTimestamp(milliseconds: 1_700_000_043_000)
    let allQuery: InstantLiveJSONValue = .object([TodoExample.namespace: .object([:])])
    let filteredQuery: InstantLiveJSONValue = .object([
      TodoExample.namespace: .object([
        "$": .object([
          "where": .object(["id": .string("todo-shared-refresh")])
        ])
      ])
    ])
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "reactor-overlapping-live-query-refresh",
        persistenceURL: cacheURL,
        initialAttributes: TodoExample.attributes
      )
    )

    let present = { (query: InstantLiveJSONValue, transactionID: String) in
      liveReactorTodoComputation(
        query: query,
        id: "todo-shared-refresh",
        text: "shared",
        createdAt: createdAt,
        processedTransactionID: transactionID
      )
    }
    let empty = { (query: InstantLiveJSONValue) in
      InstantLiveJSONValue.object([
        "instaql-query": query,
        "instaql-result": .array([]),
      ])
    }

    _ = try await runtime.applyLiveRefresh(
      InstantLiveRefreshOK(
        clientEventID: nil,
        processedTransactionID: "server-overlap-present",
        attrs: liveReactorTodoServerAttrs,
        computations: [
          present(allQuery, "server-overlap-present"),
          present(filteredQuery, "server-overlap-present"),
        ]
      )
    )
    _ = try await runtime.applyLiveRefresh(
      InstantLiveRefreshOK(
        clientEventID: nil,
        processedTransactionID: "server-overlap-all-empty",
        attrs: liveReactorTodoServerAttrs,
        computations: [empty(allQuery)]
      )
    )
    let retainedTexts = try await reactorOptimisticTextsFromQueryOnce(runtime)
    expectNoDifference(retainedTexts, ["shared"], reactorAuthoritativeRefreshSource)

    _ = try await runtime.applyLiveRefresh(
      InstantLiveRefreshOK(
        clientEventID: nil,
        processedTransactionID: "server-overlap-filtered-empty",
        attrs: liveReactorTodoServerAttrs,
        computations: [empty(filteredQuery)]
      )
    )
    let removedTexts = try await reactorOptimisticTextsFromQueryOnce(runtime)
    expectNoDifference(removedTexts, [], reactorAuthoritativeRefreshSource)
  }

  @Test("SQLiteData SharingPermissionsTests.createRecordWhenLocalHasPermissionsButCloudKitDoesNot")
  func rejectedOptimisticCreateIsRemovedByAuthoritativeRefresh() async throws {
    let cacheURL = try temporaryReactorParityCacheURL()
    let createdAt = InstantTimestamp(milliseconds: 1_700_000_044_000)
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "reactor-rejected-optimistic-create",
        persistenceURL: cacheURL,
        initialAttributes: TodoExample.attributes
      )
    )

    try await runtime.transact(
      InstantStoreTransaction(
        id: "tx-rejected-create",
        operations: TodoExample.createOperations(
          id: "todo-rejected-create",
          text: "Get milk",
          createdAt: createdAt,
          transactionID: "tx-rejected-create"
        )
      ),
      createdAt: createdAt
    )
    let optimisticTexts = try await reactorOptimisticTextsFromQueryOnce(runtime)
    expectNoDifference(optimisticTexts, ["Get milk"])

    _ = try await runtime.failMutation(
      id: "tx-rejected-create",
      message: "permission denied"
    )
    _ = try await runtime.applyLiveRefresh(
      InstantLiveRefreshOK(
        clientEventID: nil,
        processedTransactionID: "server-tx-rejected-create-refresh",
        attrs: liveReactorTodoServerAttrs,
        computations: []
      )
    )

    let refreshedTexts = try await reactorOptimisticTextsFromQueryOnce(runtime)
    let pending = await runtime.pendingMutations()
    expectNoDifference(refreshedTexts, [])
    expectNoDifference(pending, [])
    let failed = try #require(await runtime.outboxMutations().first)
    expectNoDifference(failed.status, .failed)
    expectNoDifference(failed.failureMessage, "permission denied")

    let relaunched = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "reactor-rejected-optimistic-create",
        persistenceURL: cacheURL,
        initialAttributes: TodoExample.attributes
      )
    )
    let relaunchedTexts = try await reactorOptimisticTextsFromQueryOnce(relaunched)
    let relaunchedPending = await relaunched.pendingMutations()
    let relaunchedStatuses = await relaunched.outboxMutations().map(\.status)
    expectNoDifference(relaunchedTexts, [])
    expectNoDifference(relaunchedPending, [])
    expectNoDifference(relaunchedStatuses, [.failed])
  }

  @Test("SQLiteData SharingPermissionsTests.editRecordWhenLocalHasPermissionsButCloudKitDoesNot")
  func rejectedOptimisticTransactionIsNotRebasedOverAuthoritativeRefresh() async throws {
    let cacheURL = try temporaryReactorParityCacheURL()
    let createdAt = InstantTimestamp(milliseconds: 1_700_000_045_000)
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "reactor-rejected-optimistic-refresh",
        persistenceURL: cacheURL,
        initialAttributes: TodoExample.attributes
      )
    )
    try await runtime.transact(
      InstantStoreTransaction(
        id: "tx-rejected-seed",
        operations: TodoExample.createOperations(
          id: "todo-rejected-optimistic",
          text: "server value",
          createdAt: createdAt,
          transactionID: "tx-rejected-seed"
        )
      ),
      createdAt: createdAt
    )
    _ = try await runtime.confirmMutation(id: "tx-rejected-seed")

    let rejectedAt = InstantTimestamp(milliseconds: createdAt.milliseconds + 1)
    try await runtime.transact(
      InstantStoreTransaction(
        id: "tx-rejected-update",
        operations: TodoExample.updateTextOperations(
          id: "todo-rejected-optimistic",
          text: "rejected value",
          updatedAt: rejectedAt,
          transactionID: "tx-rejected-update"
        )
      ),
      createdAt: rejectedAt
    )
    let optimisticTexts = try await reactorOptimisticTextsFromQueryOnce(runtime)
    expectNoDifference(optimisticTexts, ["rejected value"])

    _ = try await runtime.failMutation(
      id: "tx-rejected-update",
      message: "permission denied"
    )
    _ = try await runtime.applyLiveRefresh(
      InstantLiveRefreshOK(
        clientEventID: nil,
        processedTransactionID: "server-tx-rejected-refresh",
        attrs: liveReactorTodoServerAttrs,
        computations: [
          liveReactorTodoComputation(
            query: .object([TodoExample.namespace: .object([:])]),
            id: "todo-rejected-optimistic",
            text: "server value",
            createdAt: createdAt,
            processedTransactionID: "server-tx-rejected-refresh"
          )
        ]
      )
    )

    let refreshedTexts = try await reactorOptimisticTextsFromQueryOnce(runtime)
    let pending = await runtime.pendingMutations()
    expectNoDifference(refreshedTexts, ["server value"])
    expectNoDifference(pending, [])
    let failed = try #require(await runtime.outboxMutations().first)
    expectNoDifference(failed.status, .failed)
    expectNoDifference(failed.failureMessage, "permission denied")

    let relaunched = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "reactor-rejected-optimistic-refresh",
        persistenceURL: cacheURL,
        initialAttributes: TodoExample.attributes
      )
    )
    let relaunchedTexts = try await reactorOptimisticTextsFromQueryOnce(relaunched)
    let relaunchedPending = await relaunched.pendingMutations()
    let relaunchedStatuses = await relaunched.outboxMutations().map(\.status)
    expectNoDifference(relaunchedTexts, ["server value"])
    expectNoDifference(relaunchedPending, [])
    expectNoDifference(relaunchedStatuses, [.failed])
  }

  @Test
  func upstreamReactorDoesNotCleanupMutationsStillWaitingOn() async throws {
    let cacheURL = try temporaryReactorParityCacheURL()
    let createdAt = InstantTimestamp(milliseconds: 1_700_000_050_000)
    let liveSession = LiveReactorParitySession(messages: [
      liveReactorInitOK(attrs: liveReactorTodoServerAttrs)
    ])
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "reactor-pending-cleanup-parity",
        persistenceURL: cacheURL,
        initialAttributes: TodoExample.attributes,
        liveTransport: liveSession.transport
      )
    )
    try await runtime.transact(
      InstantStoreTransaction(
        id: "tx-reactor-cleanup-seed",
        operations: TodoExample.createOperations(
          id: "todo-reactor-cleanup",
          text: "joe",
          createdAt: createdAt,
          transactionID: "tx-reactor-cleanup-seed"
        )
      ),
      createdAt: createdAt
    )
    try await runtime.confirmMutation(id: "tx-reactor-cleanup-seed")
    _ = try await runtime.connect()

    let joe2At = InstantTimestamp(milliseconds: createdAt.milliseconds + 1)
    try await runtime.transact(
      InstantStoreTransaction(
        id: "tx-reactor-cleanup-joe2",
        operations: TodoExample.updateTextOperations(
          id: "todo-reactor-cleanup",
          text: "joe2",
          updatedAt: joe2At,
          transactionID: "tx-reactor-cleanup-joe2"
        )
      ),
      createdAt: joe2At
    )
    let joe3At = InstantTimestamp(milliseconds: createdAt.milliseconds + 2)
    try await runtime.transact(
      InstantStoreTransaction(
        id: "tx-reactor-cleanup-joe3",
        operations: TodoExample.updateTextOperations(
          id: "todo-reactor-cleanup",
          text: "joe3",
          updatedAt: joe3At,
          transactionID: "tx-reactor-cleanup-joe3"
        )
      ),
      createdAt: joe3At
    )

    let pendingBeforeCleanup = await runtime.pendingMutations().map(\.id)
    expectNoDifference(
      pendingBeforeCleanup,
      ["tx-reactor-cleanup-joe2", "tx-reactor-cleanup-joe3"],
      reactorPendingCleanupSource
    )
    await liveSession.waitForSentMessageCount(3)
    let sentMessages = await liveSession.sentMessages()
    expectNoDifference(
      sentMessages.map(\.op),
      ["init", "transact", "transact"],
      reactorPendingCleanupSource
    )
    expectNoDifference(
      sentMessages.dropFirst().compactMap(\.clientEventID),
      ["tx-reactor-cleanup-joe2", "tx-reactor-cleanup-joe3"],
      reactorPendingCleanupSource
    )

    let statuses = try await runtime.observeConnectionStatus()
    var statusIterator = statuses.makeAsyncIterator()
    let beforeConfirmation = try #require(await statusIterator.next())
    expectNoDifference(beforeConfirmation.pendingMutationCount, 2, reactorPendingCleanupSource)
    await liveSession.enqueue(
      InstantLiveMessage(
        op: "transact-ok",
        clientEventID: "tx-reactor-cleanup-joe2",
        fields: ["tx-id": .string("server-tx-reactor-cleanup-joe2")]
      )
    )
    let afterConfirmation = try #require(await statusIterator.next())
    expectNoDifference(
      afterConfirmation.pendingMutationCount,
      1,
      reactorPendingCleanupSource
    )

    let pendingAfterCleanup = await runtime.pendingMutations().map(\.id)
    let visibleTexts = try await reactorOptimisticTextsFromQueryOnce(runtime)
    expectNoDifference(
      pendingAfterCleanup,
      ["tx-reactor-cleanup-joe3"],
      reactorPendingCleanupSource
    )
    expectNoDifference(visibleTexts, ["joe3"], reactorPendingCleanupSource)

    let relaunchedRuntime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "reactor-pending-cleanup-parity",
        persistenceURL: cacheURL,
        initialAttributes: TodoExample.attributes
      )
    )
    let relaunchedPending = await relaunchedRuntime.pendingMutations().map(\.id)
    let relaunchedTexts = try await reactorOptimisticTextsFromQueryOnce(relaunchedRuntime)
    expectNoDifference(
      relaunchedPending,
      ["tx-reactor-cleanup-joe3"],
      reactorPendingCleanupSource
    )
    expectNoDifference(relaunchedTexts, ["joe3"], reactorPendingCleanupSource)
    _ = try await runtime.closeConnection()
  }

  @Test
  func upstreamPythonSubscriptionPostInitFailureSilentlyRetriesAndResubscribes() async throws {
    let cacheURL = try temporaryReactorParityCacheURL()
    let query: InstantLiveJSONValue = .object([TodoExample.namespace: .object([:])])
    let createdAt = InstantTimestamp(milliseconds: 1_700_000_060_000)
    let firstSession = LiveReactorParitySession(messages: [
      liveReactorInitOK(attrs: liveReactorTodoServerAttrs, sessionID: "session-before-drop"),
      liveReactorAddQueryOK(
        query: query,
        processedTransactionID: "server-tx-before-drop",
        result: liveReactorTodoQueryResult(
          id: "todo-reconnect",
          text: "before reconnect",
          createdAt: createdAt
        )
      ),
    ])
    let secondSession = LiveReactorParitySession(messages: [
      liveReactorInitOK(attrs: liveReactorTodoServerAttrs, sessionID: "session-after-drop"),
      liveReactorAddQueryOK(
        query: query,
        processedTransactionID: "server-tx-after-drop",
        result: liveReactorTodoQueryResult(
          id: "todo-reconnect",
          text: "post-reconnect",
          createdAt: createdAt
        )
      ),
    ])
    let transport = LiveReactorParityTransport(sessions: [firstSession, secondSession])
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "python-subscription-reconnect-parity",
        persistenceURL: cacheURL,
        initialAttributes: TodoExample.attributes,
        liveTransport: transport.transport
      )
    )
    let statuses = try await runtime.observeConnectionStatus()
    let observedStates = Task { () -> [InstantConnectionState] in
      var states: [InstantConnectionState] = []
      for await status in statuses {
        states.append(status.state)
        if Task.isCancelled {
          break
        }
      }
      return states
    }
    let stream = await runtime.observe(TodoExample.query)
    var iterator = stream.makeAsyncIterator()
    let initial = try #require(await iterator.next())
    expectNoDifference(initial.values, [], pythonSubscriptionReconnectSource)

    _ = try await runtime.connect()
    let beforeDrop = try #require(await iterator.next())
    expectNoDifference(
      try TodoExample.decode(beforeDrop.values).map(\.text),
      ["before reconnect"],
      pythonSubscriptionReconnectSource
    )

    await firstSession.failReceive(
      InstantError(
        code: .networkFailed,
        operation: "receive Reactor parity live event",
        message: "transient drop after init",
        recovery: "Reconnect the established live subscription."
      )
    )
    try await Task.sleep(nanoseconds: 50_000_000)
    let requestsAfterDrop = await transport.connectionRequests()
    try #require(
      requestsAfterDrop.count == 2,
      "\(pythonSubscriptionReconnectSource) Expected one initial connection and one silent reconnect, got \(requestsAfterDrop.count)."
    )
    await secondSession.waitForSentMessageCount(2)

    let postReconnect = try #require(await iterator.next())
    expectNoDifference(
      try TodoExample.decode(postReconnect.values).map(\.text),
      ["post-reconnect"],
      pythonSubscriptionReconnectSource
    )
    expectNoDifference(requestsAfterDrop.map(\.appID), [
      "python-subscription-reconnect-parity",
      "python-subscription-reconnect-parity",
    ], pythonSubscriptionReconnectSource)
    let postReconnectSentOps = await secondSession.sentMessages().map(\.op)
    expectNoDifference(
      postReconnectSentOps,
      ["init", "add-query"],
      pythonSubscriptionReconnectSource
    )
    let status = try await runtime.connectionStatus()
    expectNoDifference(status.state, .opened, pythonSubscriptionReconnectSource)
    expectNoDifference(status.lastErrorMessage, nil, pythonSubscriptionReconnectSource)
    observedStates.cancel()
    let states = await observedStates.value
    #expect(states.contains(.closed), "\(pythonSubscriptionReconnectSource)")
    #expect(!states.contains(.errored), "\(pythonSubscriptionReconnectSource)")
    expectNoDifference(states.last, .opened, pythonSubscriptionReconnectSource)
    _ = try await runtime.closeConnection()
  }

  @Test
  func runtimeReconnectBacksOffAndFlushesOnlyUnacknowledgedWork() async throws {
    let cacheURL = try temporaryReactorParityCacheURL()
    let query: InstantLiveJSONValue = .object([TodoExample.namespace: .object([:])])
    let firstCreatedAt = InstantTimestamp(milliseconds: 1_700_000_070_000)
    let secondCreatedAt = InstantTimestamp(milliseconds: firstCreatedAt.milliseconds + 1)
    let firstSession = LiveReactorParitySession(messages: [
      liveReactorInitOK(attrs: liveReactorTodoServerAttrs, sessionID: "flush-before-drop")
    ])
    let secondSession = LiveReactorParitySession(messages: [
      liveReactorInitOK(attrs: liveReactorTodoServerAttrs, sessionID: "flush-after-drop"),
      liveReactorAddQueryOK(
        query: query,
        processedTransactionID: "server-tx-after-flush-reconnect",
        result: liveReactorTodoQueryResult(
          id: "todo-reconnect-pending",
          text: "still pending after reconnect",
          createdAt: secondCreatedAt
        )
      ),
    ])
    let reconnectFailures: [LiveReactorParityTransportAttempt] = (1...12).map { attempt in
      .failure(
        InstantError(
          code: .networkFailed,
          operation: "Reactor parity reconnect attempt \(attempt)",
          message: "temporary reconnect failure \(attempt)",
          recovery: "Retry with bounded backoff."
        )
      )
    }
    let transport = LiveReactorParityTransport(
      attempts: [.session(firstSession)] + reconnectFailures + [.session(secondSession)]
    )
    let reconnectSleep = LiveReactorParityReconnectSleep()
    var configuration = InstantRuntimeConfiguration(
      appID: "reactor-reconnect-flush-parity",
      persistenceURL: cacheURL,
      initialAttributes: TodoExample.attributes,
      liveTransport: transport.transport
    )
    configuration.liveReconnectSleep = { milliseconds in
      try await reconnectSleep.sleep(milliseconds: milliseconds)
    }
    let runtime = try await InstantRuntime.bootstrap(configuration: configuration)
    let stream = await runtime.observe(TodoExample.query)
    var iterator = stream.makeAsyncIterator()
    let initial = try #require(await iterator.next())
    expectNoDifference(initial.values, [], reactorReconnectFlushSource)

    try await runtime.transact(
      InstantStoreTransaction(
        id: "tx-reconnect-acknowledged",
        operations: TodoExample.createOperations(
          id: "todo-reconnect-acknowledged",
          text: "acknowledged before reconnect",
          createdAt: firstCreatedAt,
          transactionID: "tx-reconnect-acknowledged"
        )
      ),
      createdAt: firstCreatedAt
    )
    try await runtime.transact(
      InstantStoreTransaction(
        id: "tx-reconnect-pending",
        operations: TodoExample.createOperations(
          id: "todo-reconnect-pending",
          text: "still pending after reconnect",
          createdAt: secondCreatedAt,
          transactionID: "tx-reconnect-pending"
        )
      ),
      createdAt: secondCreatedAt
    )
    _ = try await runtime.connect()
    await firstSession.waitForSentMessageCount(4)
    let initiallySentOps = await firstSession.sentMessages().map(\.op)
    expectNoDifference(
      initiallySentOps,
      ["init", "add-query", "transact", "transact"],
      reactorReconnectFlushSource
    )

    await firstSession.enqueue(
      InstantLiveMessage(
        op: "transact-ok",
        clientEventID: "tx-reconnect-acknowledged",
        fields: ["tx-id": .string("server-tx-reconnect-acknowledged")]
      )
    )
    _ = try #require(
      try await instantLiveWithTimeout(
        operation: "wait for acknowledged reconnect mutation cleanup",
        timeoutMilliseconds: 500
      ) {
        try await runtime.observeConnectionStatus().first { $0.pendingMutationCount == 1 }
      }
    )
    await firstSession.failReceive(
      InstantError(
        code: .networkFailed,
        operation: "drop Reactor parity flush session",
        message: "transient drop after one acknowledgement",
        recovery: "Reconnect and send only unacknowledged work."
      )
    )
    try await instantLiveWithTimeout(
      operation: "wait for failed and successful reconnect attempts",
      timeoutMilliseconds: 500
    ) {
      await transport.waitForConnectionCount(14)
    }
    await secondSession.waitForSentMessageCount(3)

    let reconnectDelays = await reconnectSleep.delays()
    expectNoDifference(
      reconnectDelays,
      [
        0, 1_000, 2_000, 3_000, 4_000, 5_000, 6_000,
        7_000, 8_000, 9_000, 10_000, 10_000, 10_000,
      ],
      reactorReconnectFlushSource
    )
    let reconnectedMessages = await secondSession.sentMessages()
    expectNoDifference(
      reconnectedMessages.map(\.op),
      ["init", "add-query", "transact"],
      reactorReconnectFlushSource
    )
    expectNoDifference(
      reconnectedMessages.last?.clientEventID,
      "tx-reconnect-pending",
      reactorReconnectFlushSource
    )
    let postReconnect = try #require(await iterator.next())
    expectNoDifference(
      try TodoExample.decode(postReconnect.values).map(\.text),
      ["acknowledged before reconnect", "still pending after reconnect"],
      reactorReconnectFlushSource
    )
    let pendingAfterReconnect = await runtime.pendingMutations().map(\.id)
    expectNoDifference(
      pendingAfterReconnect,
      ["tx-reconnect-pending"],
      reactorReconnectFlushSource
    )

    await secondSession.enqueue(
      InstantLiveMessage(
        op: "transact-ok",
        clientEventID: "tx-reconnect-pending",
        fields: ["tx-id": .string("server-tx-reconnect-pending")]
      )
    )
    _ = try #require(
      try await instantLiveWithTimeout(
        operation: "wait for reconnected mutation acknowledgement",
        timeoutMilliseconds: 500
      ) {
        try await runtime.observeConnectionStatus().first { $0.pendingMutationCount == 0 }
      }
    )
    let pendingAfterAcknowledgement = await runtime.pendingMutations()
    expectNoDifference(pendingAfterAcknowledgement, [], reactorReconnectFlushSource)
    _ = try await runtime.closeConnection()
  }

  @Test
  func upstreamPythonConnectionCloseCancelsInflightReconnectTask() async throws {
    let firstSession = LiveReactorParitySession(messages: [
      liveReactorInitOK(attrs: liveReactorTodoServerAttrs)
    ])
    let secondSession = LiveReactorParitySession(messages: [
      liveReactorInitOK(attrs: liveReactorTodoServerAttrs, sessionID: "unexpected-reconnect")
    ])
    let transport = LiveReactorParityTransport(sessions: [firstSession, secondSession])
    let reconnectSleeper = LiveReactorParityReconnectSleep(suspendsUntilCancelled: true)
    var configuration = InstantRuntimeConfiguration(
      appID: "python-connection-close-reconnect-parity",
      persistenceURL: try temporaryReactorParityCacheURL(),
      initialAttributes: TodoExample.attributes,
      liveTransport: transport.transport
    )
    configuration.liveReconnectSleep = { milliseconds in
      try await reconnectSleeper.sleep(milliseconds: milliseconds)
    }
    let runtime = try await InstantRuntime.bootstrap(configuration: configuration)
    _ = try await runtime.connect()

    await firstSession.failReceive(
      InstantError(
        code: .networkFailed,
        operation: "receive Reactor parity live event",
        message: "transient drop before explicit close",
        recovery: "Cancel the pending reconnect when the runtime closes."
      )
    )
    await reconnectSleeper.waitForDelayCount(1)
    _ = try await runtime.closeConnection()
    try await instantLiveWithTimeout(
      operation: "wait for explicit close to cancel reconnect sleep",
      timeoutMilliseconds: 500
    ) {
      await reconnectSleeper.waitForCancellationCount(1)
    }

    let delays = await reconnectSleeper.delays()
    let requests = await transport.connectionRequests()
    expectNoDifference(delays, [0], pythonConnectionCloseReconnectSource)
    expectNoDifference(requests.map(\.appID), [
      "python-connection-close-reconnect-parity"
    ], pythonConnectionCloseReconnectSource)
    let status = try await runtime.connectionStatus()
    expectNoDifference(status.state, .closed, pythonConnectionCloseReconnectSource)
  }

  @Test
  func runtimeReconnectRejoinsRoomAndFlushesLatestPresenceAndTopic() async throws {
    let room = InstantRoomHandle(type: "chat", id: "room-reconnect")
    let firstSession = LiveReactorParitySession(messages: [
      liveReactorInitOK(attrs: liveReactorTodoServerAttrs, sessionID: "room-before-drop")
    ])
    let secondSession = LiveReactorParitySession(messages: [
      liveReactorInitOK(attrs: liveReactorTodoServerAttrs, sessionID: "room-after-drop")
    ])
    let transport = LiveReactorParityTransport(sessions: [firstSession, secondSession])
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "reactor-room-reconnect-parity",
        persistenceURL: try temporaryReactorParityCacheURL(),
        initialAttributes: TodoExample.attributes,
        liveTransport: transport.transport
      )
    )
    _ = try await runtime.connect()
    _ = try await runtime.joinRoom(room)
    _ = try await runtime.joinRoom(room)
    _ = try await runtime.setPresence(
      room: room,
      userID: "user-1",
      values: ["status": .string("before reconnect")]
    )
    _ = try await runtime.publishTopicMessage(
      room: room,
      topic: "reaction",
      userID: "user-1",
      payload: .object(["emoji": .string("👋")])
    )
    await firstSession.waitForSentMessageCount(2)
    let firstOpsBeforeJoinOK = await firstSession.sentMessages().map(\.op)
    expectNoDifference(
      firstOpsBeforeJoinOK,
      ["init", "join-room"],
      reactorRoomReconnectSource
    )
    await firstSession.enqueue(
      InstantLiveMessage(
        op: "join-room-ok",
        fields: ["room-id": .string(room.id)]
      )
    )
    await firstSession.waitForSentMessageCount(4)
    let firstSent = await firstSession.sentMessages()
    expectNoDifference(
      firstSent.map(\.op),
      ["init", "join-room", "set-presence", "client-broadcast"],
      reactorRoomReconnectSource
    )

    await firstSession.failReceive(
      InstantError(
        code: .networkFailed,
        operation: "drop Reactor room parity session",
        message: "transient room drop",
        recovery: "Rejoin the active room and flush queued ephemeral state."
      )
    )
    try await instantLiveWithTimeout(
      operation: "wait for room reconnect",
      timeoutMilliseconds: 500
    ) {
      await transport.waitForConnectionCount(2)
    }
    await secondSession.waitForSentMessageCount(2)
    let rejoinMessages = await secondSession.sentMessages()
    expectNoDifference(
      rejoinMessages.map(\.op),
      ["init", "join-room"],
      reactorRoomReconnectSource
    )
    expectNoDifference(
      rejoinMessages[1].fields["data"],
      .object(["status": .string("before reconnect")]),
      reactorRoomReconnectSource
    )

    _ = try await runtime.setPresence(
      room: room,
      userID: "user-1",
      values: ["status": .string("after reconnect")]
    )
    _ = try await runtime.publishTopicMessage(
      room: room,
      topic: "reaction",
      userID: "user-1",
      payload: .object(["emoji": .string("✅")])
    )
    let queuedReconnectMessageCount = await secondSession.sentMessages().count
    expectNoDifference(
      queuedReconnectMessageCount,
      2,
      reactorRoomReconnectSource
    )
    await secondSession.enqueue(
      InstantLiveMessage(
        op: "join-room-ok",
        fields: ["room-id": .string(room.id)]
      )
    )
    await secondSession.waitForSentMessageCount(4)
    let flushedMessages = await secondSession.sentMessages()
    expectNoDifference(
      flushedMessages.map(\.op),
      ["init", "join-room", "set-presence", "client-broadcast"],
      reactorRoomReconnectSource
    )
    expectNoDifference(
      flushedMessages[2].fields["data"],
      .object(["status": .string("after reconnect")]),
      reactorRoomReconnectSource
    )
    expectNoDifference(
      flushedMessages[3].fields["data"],
      .object(["emoji": .string("✅")]),
      reactorRoomReconnectSource
    )

    var reconnectedPresence = (try await runtime.observeRoomPresence(room: room))
      .makeAsyncIterator()
    let initialReconnectedPresence = try #require(await reconnectedPresence.next())
    expectNoDifference(
      initialReconnectedPresence.map(\.userID),
      ["user-1"],
      reactorRoomReconnectSource
    )
    var reconnectedTopics = (try await runtime.observeRoomTopicMessages(
      room: room,
      topic: "reaction"
    )).makeAsyncIterator()
    let initialReconnectedTopics = try #require(await reconnectedTopics.next())
    expectNoDifference(
      initialReconnectedTopics.map(\.payload),
      [
        .object(["emoji": .string("👋")]),
        .object(["emoji": .string("✅")]),
      ],
      reactorRoomReconnectSource
    )
    await secondSession.enqueue(
      InstantLiveMessage(
        op: "refresh-presence",
        fields: [
          "data": .object([
            "room-after-drop": livePresenceSession(
              peerID: "room-after-drop",
              userID: "user-self",
              values: ["status": .string("self")]
            ),
            "room-peer-after-drop": livePresenceSession(
              peerID: "room-peer-after-drop",
              userID: "user-peer",
              values: ["status": .string("reconnected")]
            ),
          ]),
          "room-id": .string(room.id),
        ]
      )
    )
    let peerPresence = try #require(await reconnectedPresence.next())
    let reconnectedPeer = try #require(
      peerPresence.first(where: { $0.userID == "user-peer" })
    )
    expectNoDifference(
      peerPresence.map(\.userID),
      ["user-1", "user-peer"],
      reactorRoomReconnectSource
    )
    expectNoDifference(
      reconnectedPeer.values,
      ["status": .string("reconnected")],
      reactorRoomReconnectSource
    )
    await secondSession.enqueue(
      InstantLiveMessage(
        op: "server-broadcast",
        clientEventID: "event-peer-after-drop",
        fields: [
          "data": .object([
            "data": .object(["emoji": .string("🔁")]),
            "peer-id": .string("room-peer-after-drop"),
            "user": .object(["id": .string("user-peer")]),
          ]),
          "room-id": .string(room.id),
          "topic": .string("reaction"),
        ]
      )
    )
    let peerTopics = try #require(await reconnectedTopics.next())
    let reconnectedTopic = try #require(
      peerTopics.first(where: { $0.id == "event-peer-after-drop" })
    )
    expectNoDifference(
      reconnectedTopic.payload,
      .object(["emoji": .string("🔁")]),
      reactorRoomReconnectSource
    )

    _ = try await runtime.leaveRoom(room)
    await secondSession.waitForSentMessageCount(5)
    let leaveOp = await secondSession.sentMessages().last?.op
    expectNoDifference(
      leaveOp,
      "leave-room",
      reactorRoomReconnectSource
    )
    _ = try await runtime.closeConnection()
  }

  @Test
  func runtimeReconnectRestoresActiveStreamReaderAndUnsubscribesOnCancellation() async throws {
    let firstSession = LiveReactorParitySession(messages: [
      liveReactorInitOK(attrs: liveReactorTodoServerAttrs, sessionID: "stream-before-drop")
    ])
    let secondSession = LiveReactorParitySession(messages: [
      liveReactorInitOK(attrs: liveReactorTodoServerAttrs, sessionID: "stream-after-drop")
    ])
    let transport = LiveReactorParityTransport(sessions: [firstSession, secondSession])
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "python-stream-reader-reconnect-parity",
        persistenceURL: try temporaryReactorParityCacheURL(),
        initialAttributes: TodoExample.attributes,
        liveTransport: transport.transport
      )
    )
    _ = try await runtime.signInAsGuest()
    let metadata = try await runtime.createStream(clientID: "stream-reader-reconnect")
    _ = try await runtime.appendStreamContent(streamID: metadata.id, content: "hello")
    _ = try await runtime.connect()

    let observation = try await runtime.observeStreamContent(
      streamID: metadata.id,
      byteOffset: 2
    )
    let observerTask = Task { () -> InstantStreamContentRead? in
      var iterator = observation.makeAsyncIterator()
      let initial = await iterator.next()
      _ = await iterator.next()
      return initial
    }
    defer { observerTask.cancel() }

    try await instantLiveWithTimeout(
      operation: "wait for initial live stream subscription",
      timeoutMilliseconds: 500
    ) {
      await firstSession.waitForSentMessageCount(2)
    }
    let firstMessages = await firstSession.sentMessages()
    expectNoDifference(
      firstMessages.map(\.op),
      ["init", "subscribe-stream"],
      pythonStreamReaderReconnectSource
    )
    expectNoDifference(
      firstMessages[1].fields,
      [
        "offset": .number(5),
        "stream-id": .string(metadata.id),
      ],
      pythonStreamReaderReconnectSource
    )

    await firstSession.failReceive(
      InstantError(
        code: .networkFailed,
        operation: "drop stream reader parity session",
        message: "transient stream reader drop",
        recovery: "Reconnect the active stream reader."
      )
    )
    try await instantLiveWithTimeout(
      operation: "wait for stream reader reconnect",
      timeoutMilliseconds: 500
    ) {
      await transport.waitForConnectionCount(2)
    }
    try await instantLiveWithTimeout(
      operation: "wait for restored live stream subscription",
      timeoutMilliseconds: 500
    ) {
      await secondSession.waitForSentMessageCount(2)
    }
    let secondMessages = await secondSession.sentMessages()
    expectNoDifference(
      secondMessages.map(\.op),
      ["init", "subscribe-stream"],
      pythonStreamReaderReconnectSource
    )
    expectNoDifference(
      secondMessages[1].fields,
      [
        "offset": .number(5),
        "stream-id": .string(metadata.id),
      ],
      pythonStreamReaderReconnectSource
    )

    observerTask.cancel()
    let initialRead = try #require(await observerTask.value)
    expectNoDifference(initialRead.byteOffset, 2, pythonStreamReaderReconnectSource)
    expectNoDifference(initialRead.byteCount, 3, pythonStreamReaderReconnectSource)
    expectNoDifference(initialRead.content, "llo", pythonStreamReaderReconnectSource)
    try await instantLiveWithTimeout(
      operation: "wait for live stream unsubscription",
      timeoutMilliseconds: 500
    ) {
      await secondSession.waitForSentMessageCount(3)
    }
    let unsubscribe = try #require(await secondSession.sentMessages().last)
    expectNoDifference(unsubscribe.op, "unsubscribe-stream", pythonStreamReaderReconnectSource)
    expectNoDifference(
      unsubscribe.fields,
      ["subscribe-event-id": .string(try #require(secondMessages[1].clientEventID))],
      pythonStreamReaderReconnectSource
    )
    _ = try await runtime.closeConnection()
  }

  @Test
  func runtimeStreamAppendRetryReconnectsWithoutPublishingAppend() async throws {
    let firstSession = LiveReactorParitySession(messages: [
      liveReactorInitOK(attrs: liveReactorTodoServerAttrs, sessionID: "stream-retry-before")
    ])
    let secondSession = LiveReactorParitySession(messages: [
      liveReactorInitOK(attrs: liveReactorTodoServerAttrs, sessionID: "stream-retry-after")
    ])
    let transport = LiveReactorParityTransport(sessions: [firstSession, secondSession])
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "python-stream-append-retry-parity",
        persistenceURL: try temporaryReactorParityCacheURL(),
        initialAttributes: TodoExample.attributes,
        liveTransport: transport.transport
      )
    )
    _ = try await runtime.signInAsGuest()
    let metadata = try await runtime.createStream(clientID: "stream-append-retry")
    _ = try await runtime.appendStreamContent(streamID: metadata.id, content: "hello")
    _ = try await runtime.connect()

    let observation = try await runtime.observeStreamContent(streamID: metadata.id)
    let observerTask = Task { () -> InstantStreamContentRead? in
      var iterator = observation.makeAsyncIterator()
      let initial = await iterator.next()
      _ = await iterator.next()
      return initial
    }
    defer { observerTask.cancel() }

    try await instantLiveWithTimeout(
      operation: "wait for retry stream subscription",
      timeoutMilliseconds: 500
    ) {
      await firstSession.waitForSentMessageCount(2)
    }
    let subscribe = try #require(await firstSession.sentMessages().last)
    await firstSession.enqueue(
      InstantLiveMessage(
        op: "stream-append",
        clientEventID: subscribe.clientEventID,
        fields: [
          "client-id": .string("stream-append-retry"),
          "error": .string("transient"),
          "offset": .number(5),
          "retry": .bool(true),
          "stream-id": .string(metadata.id),
        ]
      )
    )

    try await instantLiveWithTimeout(
      operation: "wait for retryable stream append reconnect",
      timeoutMilliseconds: 500
    ) {
      await transport.waitForConnectionCount(2)
    }
    try await instantLiveWithTimeout(
      operation: "wait for retry stream resubscription",
      timeoutMilliseconds: 500
    ) {
      await secondSession.waitForSentMessageCount(2)
    }
    let resubscribe = try #require(await secondSession.sentMessages().last)
    expectNoDifference(resubscribe.op, "subscribe-stream", pythonStreamAppendRetrySource)
    expectNoDifference(
      resubscribe.fields,
      [
        "offset": .number(5),
        "stream-id": .string(metadata.id),
      ],
      pythonStreamAppendRetrySource
    )

    observerTask.cancel()
    let initial = try #require(await observerTask.value)
    expectNoDifference(initial.content, "hello", pythonStreamAppendRetrySource)
    _ = try await runtime.closeConnection()
  }

  @Test
  func runtimeInlineStreamAppendPublishesAndAdvancesReconnectOffset() async throws {
    let firstSession = LiveReactorParitySession(messages: [
      liveReactorInitOK(attrs: liveReactorTodoServerAttrs, sessionID: "stream-inline-before")
    ])
    let secondSession = LiveReactorParitySession(messages: [
      liveReactorInitOK(attrs: liveReactorTodoServerAttrs, sessionID: "stream-inline-after")
    ])
    let transport = LiveReactorParityTransport(sessions: [firstSession, secondSession])
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "python-stream-inline-append-parity",
        persistenceURL: try temporaryReactorParityCacheURL(),
        initialAttributes: TodoExample.attributes,
        liveTransport: transport.transport
      )
    )
    _ = try await runtime.signInAsGuest()
    let metadata = try await runtime.createStream(clientID: "stream-inline-append")
    _ = try await runtime.appendStreamContent(streamID: metadata.id, content: "hello")
    _ = try await runtime.connect()

    let observation = try await runtime.observeStreamContent(streamID: metadata.id)
    let observerTask = Task { () -> [InstantStreamContentRead] in
      var iterator = observation.makeAsyncIterator()
      var values: [InstantStreamContentRead] = []
      if let initial = await iterator.next() { values.append(initial) }
      if let updated = await iterator.next() { values.append(updated) }
      return values
    }
    defer { observerTask.cancel() }

    try await instantLiveWithTimeout(
      operation: "wait for inline stream subscription",
      timeoutMilliseconds: 500
    ) {
      await firstSession.waitForSentMessageCount(2)
    }
    let subscribe = try #require(await firstSession.sentMessages().last)
    await firstSession.enqueue(
      InstantLiveMessage(
        op: "stream-append",
        clientEventID: subscribe.clientEventID,
        fields: [
          "client-id": .string("stream-inline-append"),
          "content": .string(" 🚀"),
          "offset": .number(5),
          "retry": .bool(false),
          "stream-id": .string(metadata.id),
        ]
      )
    )

    let values = try await instantLiveWithTimeout(
      operation: "wait for inline stream append publication",
      timeoutMilliseconds: 500
    ) {
      await observerTask.value
    }
    expectNoDifference(
      values.map(\.content),
      ["hello", "hello 🚀"],
      pythonStreamAppendMaterializationSource
    )

    await firstSession.failReceive(
      InstantError(
        code: .networkFailed,
        operation: "drop inline stream session",
        message: "verify advanced resume offset",
        recovery: "Reconnect the stream reader."
      )
    )
    try await instantLiveWithTimeout(
      operation: "wait for inline stream reconnect",
      timeoutMilliseconds: 500
    ) {
      await transport.waitForConnectionCount(2)
    }
    try await instantLiveWithTimeout(
      operation: "wait for inline stream resubscription",
      timeoutMilliseconds: 500
    ) {
      await secondSession.waitForSentMessageCount(2)
    }
    let resubscribe = try #require(await secondSession.sentMessages().last)
    expectNoDifference(
      resubscribe.fields,
      [
        "offset": .number(10),
        "stream-id": .string(metadata.id),
      ],
      pythonStreamAppendMaterializationSource
    )
    _ = try await runtime.closeConnection()
  }

  @Test
  func runtimeFileStreamAppendPublishesAndAdvancesByFetchedBytes() async throws {
    let firstSession = LiveReactorParitySession(messages: [
      liveReactorInitOK(attrs: liveReactorTodoServerAttrs, sessionID: "stream-file-before")
    ])
    let secondSession = LiveReactorParitySession(messages: [
      liveReactorInitOK(attrs: liveReactorTodoServerAttrs, sessionID: "stream-file-after")
    ])
    let transport = LiveReactorParityTransport(sessions: [firstSession, secondSession])
    let fileTransport = InstantStreamFileTransportClient { url in
      expectNoDifference(
        url.absoluteString,
        "https://files.test/chunk",
        pythonStreamAppendMaterializationSource
      )
      let bytes = Data("lo 🚀".utf8)
      return InstantStreamFileFetchResponse(
        statusCode: 200,
        body: AsyncThrowingStream { continuation in
          continuation.yield(bytes.prefix(5))
          continuation.yield(bytes.dropFirst(5))
          continuation.finish()
        }
      )
    }
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "python-stream-file-append-parity",
        persistenceURL: try temporaryReactorParityCacheURL(),
        initialAttributes: TodoExample.attributes,
        liveTransport: transport.transport
      ),
      storageTransport: nil,
      streamFileTransport: fileTransport
    )
    _ = try await runtime.signInAsGuest()
    let metadata = try await runtime.createStream(clientID: "stream-file-append")
    _ = try await runtime.appendStreamContent(streamID: metadata.id, content: "hello")
    _ = try await runtime.connect()

    let observation = try await runtime.observeStreamContent(streamID: metadata.id)
    let observerTask = Task { () -> [InstantStreamContentRead] in
      var iterator = observation.makeAsyncIterator()
      var values: [InstantStreamContentRead] = []
      if let initial = await iterator.next() { values.append(initial) }
      if let updated = await iterator.next() { values.append(updated) }
      return values
    }
    defer { observerTask.cancel() }

    try await instantLiveWithTimeout(
      operation: "wait for file stream subscription",
      timeoutMilliseconds: 500
    ) {
      await firstSession.waitForSentMessageCount(2)
    }
    let subscribe = try #require(await firstSession.sentMessages().last)
    await firstSession.enqueue(
      InstantLiveMessage(
        op: "stream-append",
        clientEventID: subscribe.clientEventID,
        fields: [
          "client-id": .string("stream-file-append"),
          "files": .array([
            .object([
              "size": .number(999),
              "url": .string("https://files.test/chunk"),
            ])
          ]),
          "offset": .number(3),
          "retry": .bool(false),
          "stream-id": .string(metadata.id),
        ]
      )
    )

    let values = try await instantLiveWithTimeout(
      operation: "wait for file stream append publication",
      timeoutMilliseconds: 500
    ) {
      await observerTask.value
    }
    expectNoDifference(
      values.map(\.content),
      ["hello", "hello 🚀"],
      pythonStreamAppendMaterializationSource
    )

    await firstSession.failReceive(
      InstantError(
        code: .networkFailed,
        operation: "drop file stream session",
        message: "verify fetched-byte resume offset",
        recovery: "Reconnect the stream reader."
      )
    )
    try await instantLiveWithTimeout(
      operation: "wait for file stream reconnect",
      timeoutMilliseconds: 500
    ) {
      await transport.waitForConnectionCount(2)
    }
    try await instantLiveWithTimeout(
      operation: "wait for file stream resubscription",
      timeoutMilliseconds: 500
    ) {
      await secondSession.waitForSentMessageCount(2)
    }
    let resubscribe = try #require(await secondSession.sentMessages().last)
    expectNoDifference(
      resubscribe.fields,
      [
        "offset": .number(10),
        "stream-id": .string(metadata.id),
      ],
      pythonStreamAppendMaterializationSource
    )
    _ = try await runtime.closeConnection()
  }

  @Test
  func runtimeFileStreamFailureReconnectsWithoutAdvancingOffset() async throws {
    let firstSession = LiveReactorParitySession(messages: [
      liveReactorInitOK(attrs: liveReactorTodoServerAttrs, sessionID: "stream-file-fail-before")
    ])
    let secondSession = LiveReactorParitySession(messages: [
      liveReactorInitOK(attrs: liveReactorTodoServerAttrs, sessionID: "stream-file-fail-after")
    ])
    let transport = LiveReactorParityTransport(sessions: [firstSession, secondSession])
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "python-stream-file-failure-parity",
        persistenceURL: try temporaryReactorParityCacheURL(),
        initialAttributes: TodoExample.attributes,
        liveTransport: transport.transport
      ),
      storageTransport: nil,
      streamFileTransport: InstantStreamFileTransportClient { _ in
        InstantStreamFileFetchResponse(statusCode: 503, data: Data())
      }
    )
    _ = try await runtime.signInAsGuest()
    let metadata = try await runtime.createStream(clientID: "stream-file-failure")
    _ = try await runtime.appendStreamContent(streamID: metadata.id, content: "hello")
    _ = try await runtime.connect()

    let observation = try await runtime.observeStreamContent(streamID: metadata.id)
    let observerTask = Task {
      var iterator = observation.makeAsyncIterator()
      _ = await iterator.next()
      _ = await iterator.next()
    }
    defer { observerTask.cancel() }

    try await instantLiveWithTimeout(
      operation: "wait for failing file stream subscription",
      timeoutMilliseconds: 500
    ) {
      await firstSession.waitForSentMessageCount(2)
    }
    let subscribe = try #require(await firstSession.sentMessages().last)
    await firstSession.enqueue(
      InstantLiveMessage(
        op: "stream-append",
        clientEventID: subscribe.clientEventID,
        fields: [
          "client-id": .string("stream-file-failure"),
          "files": .array([
            .object([
              "size": .number(10),
              "url": .string("https://files.test/failure"),
            ])
          ]),
          "offset": .number(5),
          "retry": .bool(false),
          "stream-id": .string(metadata.id),
        ]
      )
    )

    try await instantLiveWithTimeout(
      operation: "wait for failed file stream reconnect",
      timeoutMilliseconds: 500
    ) {
      await transport.waitForConnectionCount(2)
    }
    try await instantLiveWithTimeout(
      operation: "wait for failed file stream resubscription",
      timeoutMilliseconds: 500
    ) {
      await secondSession.waitForSentMessageCount(2)
    }
    let resubscribe = try #require(await secondSession.sentMessages().last)
    expectNoDifference(
      resubscribe.fields,
      [
        "offset": .number(5),
        "stream-id": .string(metadata.id),
      ],
      pythonStreamAppendMaterializationSource
    )
    let read = try await runtime.streamContent(streamID: metadata.id)
    expectNoDifference(read.content, "hello", pythonStreamAppendMaterializationSource)
    _ = try await runtime.closeConnection()
  }

  @Test
  func runtimeClientIDReaderBootstrapsRemoteStreamMetadata() async throws {
    let session = LiveReactorParitySession(messages: [
      liveReactorInitOK(attrs: liveReactorTodoServerAttrs, sessionID: "remote-stream-reader")
    ])
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "typescript-remote-stream-bootstrap-parity",
        persistenceURL: try temporaryReactorParityCacheURL(),
        initialAttributes: TodoExample.attributes,
        liveTransport: session.transport
      )
    )
    let auth = try await runtime.signInAsGuest()
    _ = try await runtime.connect()

    let clientObservation = try await runtime.observeStreamContent(clientID: "remote-client")
    let streamObservation = try await runtime.observeStreamContent(streamID: "remote-stream")
    let clientObserverTask = Task { () -> [InstantStreamContentRead] in
      var iterator = clientObservation.makeAsyncIterator()
      var values: [InstantStreamContentRead] = []
      if let content = await iterator.next() { values.append(content) }
      if let closed = await iterator.next() { values.append(closed) }
      return values
    }
    let streamObserverTask = Task { () -> [InstantStreamContentRead] in
      var iterator = streamObservation.makeAsyncIterator()
      var values: [InstantStreamContentRead] = []
      if let content = await iterator.next() { values.append(content) }
      if let closed = await iterator.next() { values.append(closed) }
      return values
    }
    defer {
      clientObserverTask.cancel()
      streamObserverTask.cancel()
    }

    try await instantLiveWithTimeout(
      operation: "wait for remote client-id stream subscription",
      timeoutMilliseconds: 500
    ) {
      await session.waitForSentMessageCount(3)
    }
    let subscriptions = await session.sentMessages().filter { $0.op == "subscribe-stream" }
    let clientSubscribe = try #require(
      subscriptions.first { $0.fields["client-id"] == .string("remote-client") }
    )
    let streamSubscribe = try #require(
      subscriptions.first { $0.fields["stream-id"] == .string("remote-stream") }
    )
    expectNoDifference(
      clientSubscribe.fields,
      ["client-id": .string("remote-client")],
      typescriptStreamSource
    )
    expectNoDifference(
      streamSubscribe.fields,
      ["stream-id": .string("remote-stream")],
      typescriptStreamSource
    )
    await session.enqueue(
      InstantLiveMessage(
        op: "stream-append",
        clientEventID: clientSubscribe.clientEventID,
        fields: [
          "client-id": .string("remote-client"),
          "content": .string("hello 🚀"),
          "done": .bool(true),
          "offset": .number(0),
          "retry": .bool(false),
          "stream-id": .string("remote-stream"),
        ]
      )
    )

    let clientValues = try await instantLiveWithTimeout(
      operation: "wait for remote stream metadata bootstrap",
      timeoutMilliseconds: 500
    ) {
      await clientObserverTask.value
    }
    let streamValues = try await instantLiveWithTimeout(
      operation: "wait for remote stream-id publication",
      timeoutMilliseconds: 500
    ) {
      await streamObserverTask.value
    }
    expectNoDifference(
      clientValues.map(\.content),
      ["hello 🚀", "hello 🚀"],
      typescriptStreamSource
    )
    expectNoDifference(clientValues.map(\.done), [false, true], typescriptStreamSource)
    expectNoDifference(clientValues.map(\.byteCount), [10, 10], typescriptStreamSource)
    expectNoDifference(streamValues, clientValues, typescriptStreamSource)
    let byClientID = try await runtime.streamMetadata(clientID: "remote-client")
    let byStreamID = try await runtime.streamMetadata(streamID: "remote-stream")
    expectNoDifference(byClientID, byStreamID, typescriptStreamSource)
    expectNoDifference(byClientID.clientID, "remote-client", typescriptStreamSource)
    expectNoDifference(byClientID.userID, auth.userID, typescriptStreamSource)
    expectNoDifference(byClientID.size, 10, typescriptStreamSource)
    _ = try await runtime.closeConnection()
  }

  @Test
  func runtimeLiveWriterStartsAppendsAndClosesCanonicalStream() async throws {
    let session = LiveReactorParitySession(messages: [
      liveReactorInitOK(attrs: liveReactorTodoServerAttrs, sessionID: "live-stream-writer")
    ])
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "typescript-live-stream-writer-parity",
        persistenceURL: try temporaryReactorParityCacheURL(),
        initialAttributes: TodoExample.attributes,
        liveTransport: session.transport
      )
    )
    _ = try await runtime.signInAsGuest()
    _ = try await runtime.connect()

    let createTask = Task {
      try await runtime.createStream(clientID: "swift-writer")
    }
    try await instantLiveWithTimeout(
      operation: "wait for canonical start-stream",
      timeoutMilliseconds: 500
    ) {
      await session.waitForSentMessageCount(2)
    }
    let start = try #require(await session.sentMessages().last)
    expectNoDifference(start.op, "start-stream", typescriptStreamWriterSource)
    expectNoDifference(start.fields["client-id"], .string("swift-writer"))
    guard case let .string(reconnectToken)? = start.fields["reconnect-token"] else {
      Issue.record("Expected a canonical reconnect token string.")
      return
    }
    #expect(UUID(uuidString: reconnectToken) != nil)
    await session.enqueue(
      InstantLiveMessage(
        op: "start-stream-ok",
        clientEventID: start.clientEventID,
        fields: [
          "client-id": .string("swift-writer"),
          "offset": .number(0),
          "stream-id": .string("00000000-0000-0000-0000-000000000101"),
        ]
      )
    )
    let metadata = try await createTask.value
    expectNoDifference(
      metadata.id,
      "00000000-0000-0000-0000-000000000101",
      typescriptStreamWriterSource
    )

    let append = try await runtime.appendStreamContent(
      streamID: metadata.id,
      content: "hello 🚀",
      expectedOffset: 0
    )
    await session.waitForSentMessageCount(3)
    let appendMessage = try #require(await session.sentMessages().last)
    expectNoDifference(appendMessage.op, "append-stream", typescriptStreamWriterSource)
    expectNoDifference(appendMessage.fields, [
      "chunks": .array([.string("hello 🚀")]),
      "done": .bool(false),
      "offset": .number(0),
      "stream-id": .string(metadata.id),
    ])
    expectNoDifference(append.chunk.byteCount, 10, typescriptStreamWriterSource)

    let closed = try await runtime.closeStream(streamID: metadata.id)
    await session.waitForSentMessageCount(4)
    let closeMessage = try #require(await session.sentMessages().last)
    expectNoDifference(closeMessage.op, "append-stream", typescriptStreamWriterSource)
    expectNoDifference(closeMessage.fields, [
      "chunks": .array([]),
      "done": .bool(true),
      "offset": .number(10),
      "stream-id": .string(metadata.id),
    ])
    expectNoDifference(closed.done, true, typescriptStreamWriterSource)
    expectNoDifference(closed.size, 10, typescriptStreamWriterSource)
    _ = try await runtime.closeConnection()
  }

  @Test
  func runtimeLiveWriterReconnectsAndResendsOnlyUnflushedChunks() async throws {
    let firstSession = LiveReactorParitySession(messages: [
      liveReactorInitOK(attrs: liveReactorTodoServerAttrs, sessionID: "writer-before-drop")
    ])
    let secondSession = LiveReactorParitySession(messages: [
      liveReactorInitOK(attrs: liveReactorTodoServerAttrs, sessionID: "writer-after-drop")
    ])
    let transport = LiveReactorParityTransport(sessions: [firstSession, secondSession])
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "typescript-resumable-stream-writer-parity",
        persistenceURL: try temporaryReactorParityCacheURL(),
        initialAttributes: TodoExample.attributes,
        liveTransport: transport.transport
      )
    )
    _ = try await runtime.signInAsGuest()
    _ = try await runtime.connect()

    let createTask = Task { try await runtime.createStream(clientID: "resumable-writer") }
    await firstSession.waitForSentMessageCount(2)
    let firstStart = try #require(await firstSession.sentMessages().last)
    let reconnectToken = try #require(firstStart.fields["reconnect-token"])
    await firstSession.enqueue(
      InstantLiveMessage(
        op: "start-stream-ok",
        clientEventID: firstStart.clientEventID,
        fields: [
          "client-id": .string("resumable-writer"),
          "offset": .number(0),
          "stream-id": .string("00000000-0000-0000-0000-000000000201"),
        ]
      )
    )
    let metadata = try await createTask.value
    _ = try await runtime.appendStreamContent(
      streamID: metadata.id,
      content: "hello",
      expectedOffset: 0
    )
    await firstSession.enqueue(
      InstantLiveMessage(
        op: "stream-flushed",
        fields: [
          "done": .bool(false),
          "offset": .number(5),
          "stream-id": .string(metadata.id),
        ]
      )
    )
    _ = try await runtime.appendStreamContent(
      streamID: metadata.id,
      content: " 🚀",
      expectedOffset: 5
    )
    await firstSession.waitForSentMessageCount(4)
    await firstSession.failReceive(
      InstantError(
        code: .networkFailed,
        operation: "drop resumable writer session",
        message: "transient writer drop",
        recovery: "Reconnect with the original token."
      )
    )

    try await instantLiveWithTimeout(
      operation: "wait for resumable writer reconnect",
      timeoutMilliseconds: 500
    ) {
      await transport.waitForConnectionCount(2)
    }
    await secondSession.waitForSentMessageCount(2)
    let secondStart = try #require(await secondSession.sentMessages().last)
    expectNoDifference(secondStart.op, "start-stream", typescriptStreamWriterSource)
    expectNoDifference(secondStart.fields, [
      "client-id": .string("resumable-writer"),
      "reconnect-token": reconnectToken,
    ])
    await secondSession.enqueue(
      InstantLiveMessage(
        op: "start-stream-ok",
        clientEventID: secondStart.clientEventID,
        fields: [
          "client-id": .string("resumable-writer"),
          "offset": .number(5),
          "stream-id": .string(metadata.id),
        ]
      )
    )
    await secondSession.waitForSentMessageCount(3)
    let resent = try #require(await secondSession.sentMessages().last)
    expectNoDifference(resent.op, "append-stream", typescriptStreamWriterSource)
    expectNoDifference(resent.fields, [
      "chunks": .array([.string(" 🚀")]),
      "done": .bool(false),
      "offset": .number(5),
      "stream-id": .string(metadata.id),
    ])
    _ = try await runtime.closeConnection()
  }

  @Test
  func runtimeAppliesLivePresencePatchesAndEphemeralServerBroadcasts() async throws {
    let room = InstantRoomHandle(type: "chat", id: "room-events")
    let now = InstantTimestamp(milliseconds: 1_700_000_080_000)
    let cacheURL = try temporaryReactorParityCacheURL()
    let session = LiveReactorParitySession(messages: [
      liveReactorInitOK(attrs: liveReactorTodoServerAttrs, sessionID: "session-self")
    ])
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "reactor-room-events-parity",
        persistenceURL: cacheURL,
        initialAttributes: TodoExample.attributes,
        now: { now },
        liveTransport: session.transport
      )
    )
    _ = try await runtime.connect()
    _ = try await runtime.joinRoom(room)

    var presence = (try await runtime.observeRoomPresence(room: room)).makeAsyncIterator()
    let initialPresence = await presence.next()
    expectNoDifference(initialPresence, [], reactorRoomEventsSource)
    await session.enqueue(
      InstantLiveMessage(
        op: "join-room-ok",
        fields: ["room-id": .string(room.id)]
      )
    )
    await session.enqueue(
      InstantLiveMessage(
        op: "refresh-presence",
        fields: [
          "data": .object([
            "session-self": livePresenceSession(
              peerID: "session-self",
              userID: "user-self",
              values: ["status": .string("self")]
            ),
            "session-peer": livePresenceSession(
              peerID: "session-peer",
              userID: "user-peer",
              values: ["status": .string("online")]
            ),
          ]),
          "room-id": .string(room.id),
        ]
      )
    )
    let refreshed = try #require(await presence.next())
    expectNoDifference(refreshed.map(\.userID), ["user-peer"], reactorRoomEventsSource)
    expectNoDifference(
      refreshed.first?.values,
      ["status": .string("online")],
      reactorRoomEventsSource
    )

    await session.enqueue(
      InstantLiveMessage(
        op: "patch-presence",
        fields: [
          "edits": .array([
            livePresenceEdit(
              path: ["session-peer", "data", "status"],
              operation: "r",
              value: .string("away")
            ),
            livePresenceEdit(
              path: ["session-peer", "data", "typing"],
              operation: "+",
              value: .bool(true)
            ),
          ]),
          "room-id": .string(room.id),
        ]
      )
    )
    let patched = try #require(await presence.next())
    expectNoDifference(
      patched.first?.values,
      ["status": .string("away"), "typing": .bool(true)],
      reactorRoomEventsSource
    )
    await session.enqueue(
      InstantLiveMessage(
        op: "patch-presence",
        fields: [
          "edits": .array([
            livePresenceEdit(
              path: ["session-peer", "data", "typing"],
              operation: "-"
            )
          ]),
          "room-id": .string(room.id),
        ]
      )
    )
    let removed = try #require(await presence.next())
    expectNoDifference(
      removed.first?.values,
      ["status": .string("away")],
      reactorRoomEventsSource
    )
    var topics = (try await runtime.observeRoomTopicMessages(
      room: room,
      topic: "reaction"
    )).makeAsyncIterator()
    let initialTopics = await topics.next()
    expectNoDifference(initialTopics, [], reactorRoomEventsSource)
    await session.enqueue(
      InstantLiveMessage(
        op: "server-broadcast",
        clientEventID: "event-peer-reaction",
        fields: [
          "data": .object([
            "data": .object(["emoji": .string("🔥")]),
            "peer-id": .string("session-peer"),
            "user": .object(["id": .string("user-peer")]),
          ]),
          "room-id": .string(room.id),
          "topic": .string("reaction"),
        ]
      )
    )
    let topicMessages = try #require(await topics.next())
    expectNoDifference(topicMessages.map(\.id), ["event-peer-reaction"], reactorRoomEventsSource)
    expectNoDifference(topicMessages.map(\.userID), ["user-peer"], reactorRoomEventsSource)
    expectNoDifference(
      topicMessages.map(\.payload),
      [.object(["emoji": .string("🔥")])],
      reactorRoomEventsSource
    )

    let selfTopicStream = try await runtime.observeRoomTopicMessages(
      room: room,
      topic: "reaction"
    )
    let selfTopicTask = Task {
      var iterator = selfTopicStream.makeAsyncIterator()
      _ = await iterator.next()
      return await iterator.next()
    }
    defer { selfTopicTask.cancel() }
    await session.enqueue(
      InstantLiveMessage(
        op: "server-broadcast",
        clientEventID: "event-self-reaction",
        fields: [
          "data": .object([
            "data": .object(["emoji": .string("✅")]),
            "peer-id": .string("session-self"),
            "user": .object(["id": .string("user-self")]),
          ]),
          "room-id": .string(room.id),
          "topic": .string("reaction"),
        ]
      )
    )
    let selfTopicMessages = try await instantLiveWithTimeout(
      operation: "wait for Reactor current-session server-broadcast",
      timeoutMilliseconds: 500
    ) {
      try #require(await selfTopicTask.value)
    }
    expectNoDifference(
      selfTopicMessages.map(\.id),
      ["event-self-reaction"],
      reactorRoomEventsSource
    )
    expectNoDifference(
      selfTopicMessages.map(\.userID),
      ["user-self"],
      reactorRoomEventsSource
    )
    expectNoDifference(
      selfTopicMessages.map(\.payload),
      [.object(["emoji": .string("✅")])],
      reactorRoomEventsSource
    )
    let durableMessages = try await runtime.roomTopicMessages(room: room, topic: "reaction")
    expectNoDifference(durableMessages, [], reactorRoomEventsSource)
    _ = try await runtime.closeConnection()
    let disconnectedPresence = try await runtime.roomPresence(room: room)
    expectNoDifference(
      disconnectedPresence.map(\.userID),
      ["user-peer"],
      reactorRoomEventsSource
    )
    expectNoDifference(
      disconnectedPresence.map(\.values),
      [["status": .string("away")]],
      reactorRoomEventsSource
    )

    let relaunchedRuntime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "reactor-room-events-parity",
        persistenceURL: cacheURL,
        initialAttributes: TodoExample.attributes,
        now: { now }
      )
    )
    let relaunchedPresence = try await relaunchedRuntime.roomPresence(room: room)
    let relaunchedTopics = try await relaunchedRuntime.roomTopicMessages(
      room: room,
      topic: "reaction"
    )
    expectNoDifference(relaunchedPresence, [], reactorRoomEventsSource)
    expectNoDifference(relaunchedTopics, [], reactorRoomEventsSource)
  }

  @Test
  func upstreamReactorRewriteMutationsKeepsPendingTransportStable() async throws {
    let cacheURL = try temporaryReactorParityCacheURL()
    let seedTime = InstantTimestamp(milliseconds: 1_700_000_010_000)
    let rewriteTime = InstantTimestamp(milliseconds: seedTime.milliseconds + 1)
    let attributes = reactorRewriteAttributes()
    let runtime = try await reactorRewriteRuntime(cacheURL: cacheURL, attributes: attributes)
    try await seedReactorRewriteFixture(runtime: runtime, at: seedTime)
    let transaction = reactorRewriteTransaction(id: "tx-reactor-rewrite-single", at: rewriteTime)

    try await runtime.transact(transaction, createdAt: rewriteTime)

    let pendingTransport = await runtime.outboxTransportMutations()
    let mutation = try #require(
      pendingTransport.first { $0.mutationID == "tx-reactor-rewrite-single" }
    )
    expectNoDifference(mutation.txSteps, reactorRewriteExpectedSteps, reactorRewriteSource)
    expectNoDifference(mutation.preconditions, [], reactorRewriteSource)

    let relaunchedRuntime = try await reactorRewriteRuntime(cacheURL: cacheURL, attributes: attributes)
    let relaunchedPending = await relaunchedRuntime.pendingMutations()
    let relaunchedTransport = await relaunchedRuntime.outboxTransportMutations()
    let relaunchedMutation = try #require(
      relaunchedTransport.first { $0.mutationID == "tx-reactor-rewrite-single" }
    )
    expectNoDifference(relaunchedPending.map(\.id), ["tx-reactor-rewrite-single"], reactorRewriteSource)
    expectNoDifference(relaunchedMutation.txSteps, reactorRewriteExpectedSteps, reactorRewriteSource)
    expectNoDifference(relaunchedMutation.preconditions, [], reactorRewriteSource)
  }

  @Test
  func upstreamReactorRewriteMutationsHandlesMultiplePendingTransactions() async throws {
    let cacheURL = try temporaryReactorParityCacheURL()
    let seedTime = InstantTimestamp(milliseconds: 1_700_000_020_000)
    let attributes = reactorRewriteAttributes()
    let runtime = try await reactorRewriteRuntime(cacheURL: cacheURL, attributes: attributes)
    try await seedReactorRewriteFixture(runtime: runtime, at: seedTime)

    for (index, suffix) in ["a", "b", "c", "d"].enumerated() {
      let timestamp = InstantTimestamp(milliseconds: seedTime.milliseconds + Int64(index) + 1)
      try await runtime.transact(
        reactorRewriteTransaction(id: "tx-reactor-rewrite-\(suffix)", at: timestamp),
        createdAt: timestamp
      )
    }

    let relaunchedRuntime = try await reactorRewriteRuntime(cacheURL: cacheURL, attributes: attributes)
    let relaunchedPending = await relaunchedRuntime.pendingMutations()
    let relaunchedTransport = await relaunchedRuntime.outboxTransportMutations()

    expectNoDifference(
      relaunchedPending.map(\.id),
      [
        "tx-reactor-rewrite-a",
        "tx-reactor-rewrite-b",
        "tx-reactor-rewrite-c",
        "tx-reactor-rewrite-d",
      ],
      reactorRewriteMultipleSource
    )
    expectNoDifference(
      relaunchedTransport.map(\.txSteps),
      Array(repeating: reactorRewriteExpectedSteps, count: 4),
      reactorRewriteMultipleSource
    )
    expectNoDifference(
      relaunchedTransport.flatMap(\.preconditions),
      [],
      reactorRewriteMultipleSource
    )
  }

  @Test
  func upstreamReactorGetLocalIDAlwaysReturnsSameID() async throws {
    let cacheURL = try temporaryReactorParityCacheURL()
    let idFactory = SequentialLocalIDFactory()
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "reactor-local-id-parity",
        persistenceURL: cacheURL,
        makeID: idFactory.makeID
      )
    )

    let ids = try await withThrowingTaskGroup(of: String.self) { group in
      for _ in 0..<1_000 {
        group.addTask {
          try await runtime.localID(named: "id")
        }
      }

      var ids: [String] = []
      for try await id in group {
        ids.append(id)
      }
      return ids
    }

    let uniqueIDs = Set(ids)
    let firstID = try #require(uniqueIDs.first)
    expectNoDifference(uniqueIDs.count, 1, reactorGetLocalIDSource)
    expectNoDifference(idFactory.count, 1, reactorGetLocalIDSource)

    let relaunchedRuntime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "reactor-local-id-parity",
        persistenceURL: cacheURL,
        makeID: { "unexpected-relaunch-local-id" }
      )
    )

    let relaunchedID = try await relaunchedRuntime.localID(named: "id")
    let persistedIDs = try await relaunchedRuntime.localIDs()
    expectNoDifference(relaunchedID, firstID, reactorGetLocalIDSource)
    expectNoDifference(persistedIDs, [InstantLocalID(name: "id", entityID: firstID)], reactorGetLocalIDSource)
  }
}

private let reactorGetLocalIDSource =
  "upstream/instant/client/packages/core/__tests__/src/Reactor.test.ts getLocalId always returns the same id [adapted: Swift uses InstantRuntime.localID over the local SQLite cache instead of the IndexedDB-backed Reactor harness.]"

private let reactorQuerySubsSource =
  "upstream/instant/client/packages/core/__tests__/src/Reactor.test.ts querySubs round-trips [adapted: Swift installs the query on the runtime live session, applies add-query-ok through the public observer, persists the resulting store and query cache in SQLite, and proves relaunch and closed-query fallback.]"

private let reactorOptimisticRefreshSource =
  "upstream/instant/client/packages/core/__tests__/src/Reactor.test.ts optimisticTx is not overwritten by refresh-ok [adapted: Swift applies the raw refresh-ok payload after confirming the earlier mutation and proves the later optimistic write remains visible and persisted.]"

private let reactorAuthoritativeRefreshSource =
  "upstream/instant/client/packages/core/src/Reactor.js refresh-ok branch [adapted: Swift must replace each computation's server triples so rows absent from the authoritative result are removed.]"

private let reactorPendingCleanupSource =
  "upstream/instant/client/packages/core/__tests__/src/Reactor.test.ts we don't cleanup mutations we're still waiting on [adapted: Swift sends both durable pending mutations through the owned live session, applies transact-ok for only the first, and proves the still-unacknowledged optimistic mutation remains pending and visible across relaunch.]"

private let pythonSubscriptionReconnectSource =
  "upstream/instant/client/packages/python/tests/test_subscription_state.py test_post_init_failure_silently_retries [adapted: Swift's owned WebSocket session establishes init and a query result, receives a transient post-init failure, reconnects without publishing a terminal error, reinstalls the active query, and emits the post-reconnect result. This also pins upstream/instant/client/packages/core/src/Reactor.js _transportOnClose and _scheduleReconnect behavior.]"

private let reactorReconnectFlushSource =
  "upstream/instant/client/packages/core/src/Reactor.js _scheduleReconnect and _flushPendingMessages [adapted: Swift records the same immediate, one-second progression, and ten-second retry cap, reinstalls the active query, and resends only the durable mutation that did not receive transact-ok before the drop.]"

private let pythonConnectionCloseReconnectSource =
  "upstream/instant/client/packages/python/tests/test_streams_state.py test_connection_aclose_cancels_inflight_reconnect_task [adapted: Swift blocks the reconnect backoff task after a post-init transport failure, explicitly closes the runtime, and proves cancellation prevents a second live transport connection. This also pins upstream/instant/client/packages/core/src/Reactor.js shutdown branch in _transportOnClose.]"

private let reactorRoomReconnectSource =
  "upstream/instant/client/packages/core/src/Reactor.js init-ok room loop, joinRoom, _flushEnqueuedRoomData, publishPresence, publishTopic, refresh-presence, and server-broadcast branches [adapted: Swift rejoins an active room with current presence, queues newer presence/topic data until join-room-ok, flushes it once, receives fresh peer presence and topics after rejoin, and sends leave-room on explicit cleanup.]"

private let pythonStreamReaderReconnectSource =
  "upstream/instant/client/packages/python/tests/test_streams_state.py test_reader_on_reconnect_resubscribes_with_current_offset and upstream/instant/client/packages/core/src/Stream.ts onConnectionStatusChange [adapted: Swift registers a public stream-content observer with the owned live session at the end of its local read, restores that subscription at the same byte offset after reconnect, and unsubscribes with the reconnected subscription event id when observation is cancelled.]"

private let pythonStreamAppendRetrySource =
  "upstream/instant/client/packages/python/tests/test_streams_state.py test_reader_stream_append_with_retry_triggers_force_reconnect and upstream/instant/client/packages/core/src/Stream.ts onStreamAppend [adapted: Swift correlates a retryable stream-append error to the active subscription, reconnects the owned live session without publishing the failed append, and resubscribes from the last seen byte offset.]"

private let pythonStreamAppendMaterializationSource =
  "upstream/instant/client/packages/python/src/instantdb/_async/streams/reader.py _process_append plus tests/test_streams_state.py test_reader_holds_partial_utf8_across_chunk_boundary and upstream/instant/client/packages/core/src/Stream.ts createReadStream [adapted: Swift persists an inline stream-append through the public observer, preserves the multi-byte scalar, publishes the full content snapshot, and advances the next reconnect subscription by UTF-8 byte count.]"

private let typescriptStreamSource =
  "upstream/instant/client/packages/core/src/Stream.ts createReadStream and upstream/instant/server/src/instant/reactive/session.clj handle-subscribe-stream! [adapted: Swift starts a reader from a client id before local metadata exists, accepts the canonical server-resolved stream and client ids, persists the remote metadata and UTF-8 content, and publishes the open then closed snapshots.]"

private let typescriptStreamWriterSource =
  "upstream/instant/client/packages/core/src/Stream.ts createWriteStream, startWriteStream, and appendStream plus upstream/instant/server/src/instant/reactive/session.clj handle-start-stream! and handle-append-stream! [adapted: Swift awaits the server stream id, persists that canonical identity, sends ordered UTF-8 chunks at exact byte offsets, and closes with an empty done append.]"

private let reactorRoomEventsSource =
  "upstream/instant/client/packages/core/src/Reactor.js refresh-presence, patch-presence, and server-broadcast receive branches plus upstream/instant/server/test/instant/reactive/session_test.clj patch-presence-works and broadcast-works [adapted: Swift excludes its own live session from peer presence, applies canonical +/r/- edits in memory, publishes typed peer state, and emits remote broadcasts without adding them to durable topic history.]"

private let reactorRewriteSource =
  "upstream/instant/client/packages/core/__tests__/src/Reactor.test.ts rewrite mutations [adapted: Swift pending mutations store typed transactions and lower them to stable transport steps over declared server attributes instead of rewriting cached JavaScript tx-steps.]"

private let reactorRewriteMultipleSource =
  "upstream/instant/client/packages/core/__tests__/src/Reactor.test.ts rewrite mutations works with multiple transactions [adapted: Swift re-lowers every pending typed transaction to the same transport steps after persistence instead of rewriting a JavaScript pendingMutations map.]"

private func livePresenceSession(
  peerID: String,
  userID: String,
  values: [String: InstantLiveJSONValue]
) -> InstantLiveJSONValue {
  .object([
    "data": .object(values),
    "peer-id": .string(peerID),
    "user": .object(["id": .string(userID)]),
  ])
}

private func livePresenceEdit(
  path: [String],
  operation: String,
  value: InstantLiveJSONValue? = nil
) -> InstantLiveJSONValue {
  var parts: [InstantLiveJSONValue] = [
    .array(path.map(InstantLiveJSONValue.string)),
    .string(operation),
  ]
  if let value {
    parts.append(value)
  }
  return .array(parts)
}

private func temporaryReactorParityCacheURL() throws -> URL {
  let directory = FileManager.default.temporaryDirectory
    .appendingPathComponent("InstantReactorParityTests-\(UUID().uuidString)")
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  return directory.appendingPathComponent("state.sqlite")
}

private func reactorRewriteRuntime(
  cacheURL: URL,
  attributes: [InstantAttribute]
) async throws -> InstantRuntime {
  try await InstantRuntime.bootstrap(
    configuration: InstantRuntimeConfiguration(
      appID: "reactor-rewrite-parity",
      persistenceURL: cacheURL,
      initialAttributes: attributes
    )
  )
}

private func reactorOptimisticTextsFromQueryOnce(_ runtime: InstantRuntime) async throws -> [String] {
  try await TodoExample.decode(runtime.queryOnce(TodoExample.query).values).map(\.text)
}

private func seedReactorRewriteFixture(
  runtime: InstantRuntime,
  at timestamp: InstantTimestamp
) async throws {
  let transaction = InstantStoreTransaction(
    id: "tx-reactor-rewrite-seed",
    operations: InstantInstamlTransform.updateOperations(
      namespace: "users",
      entityID: "user-stopa",
      fields: [
        "email": .string("old@example.com"),
        "handle": .string("stopa"),
      ],
      txID: "tx-reactor-rewrite-seed",
      txTime: timestamp
    )
    + InstantInstamlTransform.updateOperations(
      namespace: "users",
      entityID: "user-joe",
      fields: ["handle": .string("joe")],
      txID: "tx-reactor-rewrite-seed",
      txTime: timestamp
    )
    + InstantInstamlTransform.updateOperations(
      namespace: "bookshelves",
      entityID: "bookshelfId",
      fields: [:],
      txID: "tx-reactor-rewrite-seed",
      txTime: timestamp
    )
    + [
      .insert(
        InstantTriple(
          entityID: "bookshelfId",
          attributeID: "bookshelves/users",
          value: .ref("user-joe"),
          txID: "tx-reactor-rewrite-seed",
          txTime: timestamp
        )
      )
    ]
  )
  try await runtime.transact(transaction, createdAt: timestamp)
  try await runtime.confirmMutation(id: "tx-reactor-rewrite-seed")
}

private func reactorRewriteTransaction(
  id: String,
  at timestamp: InstantTimestamp
) -> InstantStoreTransaction {
  let stopaLookup = InstantLookupRef(attributeID: "users/handle", value: .string("stopa"))
  let joeLookup = InstantLookupRef(attributeID: "users/handle", value: .string("joe"))
  return InstantStoreTransaction(
    id: id,
    operations: InstantInstamlTransform.updateOperations(
      namespace: "books",
      entityID: "bookId",
      fields: ["title": .string("title")],
      txID: id,
      txTime: timestamp
    )
    + InstantInstamlTransform.updateOperations(
      namespace: "users",
      entityLookup: stopaLookup,
      fields: ["email": .string("s@example.com")],
      txID: id,
      txTime: timestamp
    )
    + InstantInstamlTransform.updateOperations(
      namespace: "bookshelves",
      entityID: "bookshelfId",
      fields: [:],
      txID: id,
      txTime: timestamp
    )
    + [
      .insert(
        InstantTriple(
          entityID: "bookshelfId",
          attributeID: "bookshelves/users",
          value: .lookupRef(stopaLookup),
          txID: id,
          txTime: timestamp
        )
      ),
      .retract(
        InstantTriple(
          entityID: "bookshelfId",
          attributeID: "bookshelves/users",
          value: .lookupRef(joeLookup),
          txID: id,
          txTime: timestamp
        )
      ),
    ]
  )
}

private let reactorRewriteExpectedSteps: [InstantTransportStep] = [
  .addTriple(entity: .id("bookId"), attributeID: "books/title", value: .string("title")),
  .addTriple(entity: .id("bookId"), attributeID: "books/id", value: .string("bookId")),
  .addTriple(
    entity: .lookup(InstantLookupRef(attributeID: "users/handle", value: .string("stopa"))),
    attributeID: "users/email",
    value: .string("s@example.com")
  ),
  .addTriple(
    entity: .lookup(InstantLookupRef(attributeID: "users/handle", value: .string("stopa"))),
    attributeID: "users/id",
    value: .lookupRef(attributeID: "users/handle", value: .string("stopa"))
  ),
  .addTriple(
    entity: .id("bookshelfId"),
    attributeID: "bookshelves/id",
    value: .string("bookshelfId")
  ),
  .addTriple(
    entity: .id("bookshelfId"),
    attributeID: "bookshelves/users",
    value: .lookupRef(attributeID: "users/handle", value: .string("stopa"))
  ),
  .retractTriple(
    entity: .id("bookshelfId"),
    attributeID: "bookshelves/users",
    value: .lookupRef(attributeID: "users/handle", value: .string("joe"))
  ),
]

private func reactorRewriteAttributes() -> [InstantAttribute] {
  [
    .primaryKey(namespace: "books"),
    .primaryKey(namespace: "users"),
    .primaryKey(namespace: "bookshelves"),
    InstantAttribute(
      id: "books/title",
      namespace: "books",
      name: "title",
      valueType: .string,
      isIndexed: true
    ),
    InstantAttribute(
      id: "users/handle",
      namespace: "users",
      name: "handle",
      valueType: .string,
      isIndexed: true,
      isUnique: true
    ),
    InstantAttribute(
      id: "users/email",
      namespace: "users",
      name: "email",
      valueType: .string,
      isIndexed: true
    ),
    InstantAttribute(
      id: "bookshelves/users",
      namespace: "bookshelves",
      name: "users",
      valueType: .ref,
      isIndexed: true,
      forwardIdentity: "bookshelves/users",
      reverseIdentity: "users/bookshelves",
      linkNamespace: "users"
    ),
  ]
}

private final class SequentialLocalIDFactory: @unchecked Sendable {
  private let lock = NSLock()
  private var nextID = 0

  var count: Int {
    lock.lock()
    defer { lock.unlock() }
    return nextID
  }

  func makeID() -> String {
    lock.lock()
    defer { lock.unlock() }
    nextID += 1
    return "local-\(nextID)"
  }
}
