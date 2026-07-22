import CustomDump
import Foundation
import SQLite3
@testable import InstantSwiftDataCore
import Testing

@Suite(.serialized)
struct InstantStoreTests {
  @Test
  func persistenceFilesRestrictRefreshSessionsToTheCurrentUser() async throws {
    let cacheURL = try temporaryCacheURL()
    let store = try SQLitePersistenceStore(fileURL: cacheURL)
    try await store.bootstrap()
    try await store.saveAuthSession(
      InstantAuthSession(
        appID: "permissions-app",
        userID: "user-1",
        refreshToken: "private-refresh-token",
        isGuest: true,
        createdAt: InstantTimestamp(milliseconds: 1),
        updatedAt: InstantTimestamp(milliseconds: 1)
      ),
      key: "permissions-app"
    )

    let fileManager = FileManager.default
    let persistenceFiles = [
      cacheURL,
      URL(fileURLWithPath: cacheURL.path + "-wal"),
      URL(fileURLWithPath: cacheURL.path + "-shm"),
    ].filter { fileManager.fileExists(atPath: $0.path) }
    #expect(!persistenceFiles.isEmpty)
    for fileURL in persistenceFiles {
      let attributes = try fileManager.attributesOfItem(atPath: fileURL.path)
      let permissions = try #require(attributes[.posixPermissions] as? NSNumber)
      expectNoDifference(permissions.intValue & 0o777, 0o600)
    }
  }

  @Test
  func runtimePersistsTodosAndOutboxAcrossLaunches() async throws {
    let cacheURL = try temporaryCacheURL()
    let createdAt = InstantTimestamp(milliseconds: 1_700_000_000_000)
    let transaction = InstantStoreTransaction(
      id: "tx-create-todo",
      operations: TodoExample.createOperations(
        id: "todo-1",
        text: "do the dishes",
        createdAt: createdAt,
        transactionID: "tx-create-todo"
      )
    )

    let firstRuntime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "test-app",
        persistenceURL: cacheURL,
        initialAttributes: TodoExample.attributes
      )
    )
    try await firstRuntime.transact(transaction, createdAt: createdAt)

    let relaunchedRuntime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "test-app",
        persistenceURL: cacheURL,
        initialAttributes: TodoExample.attributes
      )
    )

    let todos = try await TodoExample.decode(relaunchedRuntime.query(TodoExample.query))
    expectNoDifference(
      todos,
      [
        TodoRecord(
          id: "todo-1",
          text: "do the dishes",
          isCompleted: false,
          createdAt: createdAt
        )
      ]
    )

    let pending = await relaunchedRuntime.pendingMutations()
    expectNoDifference(pending.map(\.id), ["tx-create-todo"])
  }

  @Test
  func emptyRuntimeTransactionDoesNotPersistPendingMutation() async throws {
    let cacheURL = try temporaryCacheURL()
    let createdAt = InstantTimestamp(milliseconds: 1_700_000_000_000)
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "test-app",
        persistenceURL: cacheURL,
        initialAttributes: TodoExample.attributes
      )
    )

    let empty = try await runtime.transact(
      InstantStoreTransaction(id: "tx-empty-runtime", operations: []),
      createdAt: createdAt
    )
    expectNoDifference(empty.transactionID, "tx-empty-runtime")
    expectNoDifference(empty.changedEntityIDs, [])
    expectNoDifference(empty.tripleCount, 0)
    expectNoDifference(empty.emissions, [])
    let pendingAfterEmpty = await runtime.pendingMutations()
    expectNoDifference(pendingAfterEmpty, [])

    try await runtime.transact(
      InstantStoreTransaction(
        id: "tx-empty-runtime",
        operations: TodoExample.createOperations(
          id: "todo-after-empty",
          text: "after empty",
          createdAt: createdAt,
          transactionID: "tx-empty-runtime"
        )
      ),
      createdAt: createdAt
    )

    let todos = try await TodoExample.decode(runtime.query(TodoExample.query))
    expectNoDifference(todos.map(\.id), ["todo-after-empty"])
    let pendingAfterWrite = await runtime.pendingMutations()
    expectNoDifference(pendingAfterWrite.map(\.id), ["tx-empty-runtime"])
  }

  @Test
  func serverTransactionPersistsPublishesCheckpointAndDoesNotAppendOutbox() async throws {
    let cacheURL = try temporaryCacheURL()
    let localCreatedAt = InstantTimestamp(milliseconds: 1_700_000_000_000)
    let serverCreatedAt = InstantTimestamp(milliseconds: localCreatedAt.milliseconds + 1)
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "server-transaction-loopback",
        persistenceURL: cacheURL,
        initialAttributes: TodoExample.attributes
      )
    )
    try await runtime.transact(
      InstantStoreTransaction(
        id: "tx-local",
        operations: TodoExample.createOperations(
          id: "todo-local",
          text: "local optimistic write",
          createdAt: localCreatedAt,
          transactionID: "tx-local"
        )
      ),
      createdAt: localCreatedAt
    )

    let stream = await runtime.observe(TodoExample.query)
    var iterator = stream.makeAsyncIterator()
    let initialEmission = try #require(await iterator.next())
    expectNoDifference(
      try TodoExample.decode(initialEmission.values),
      [
        TodoRecord(
          id: "todo-local",
          text: "local optimistic write",
          isCompleted: false,
          createdAt: localCreatedAt
        )
      ]
    )
    let pendingBeforeServerApply = await runtime.pendingMutations()
    expectNoDifference(pendingBeforeServerApply.map(\.id), ["tx-local"])
    let syncStateBeforeServerApply = try await runtime.syncState()
    expectNoDifference(syncStateBeforeServerApply.processedTransactionID, nil)
    let persistenceStateBeforeServerApply = try await runtime.persistence.loadState()

    let result = try await runtime.applyServerTransaction(
      InstantStoreTransaction(
        id: " server-tx-1 ",
        operations: TodoExample.createOperations(
          id: "todo-server",
          text: "server inbound write",
          createdAt: serverCreatedAt,
          transactionID: "server-tx-1"
        )
      ),
      receivedAt: InstantTimestamp(milliseconds: serverCreatedAt.milliseconds + 1)
    )

    expectNoDifference(result.mutation.transactionID, "server-tx-1")
    expectNoDifference(result.mutation.changedEntityIDs, Set(["todo-server"]))
    expectNoDifference(result.mutation.emissions.map(\.queryID), [TodoExample.query.id])
    expectNoDifference(result.syncState.processedTransactionID, "server-tx-1")
    expectNoDifference(result.pendingMutationCount, 1)
    let pendingAfterServerApply = await runtime.pendingMutations()
    expectNoDifference(pendingAfterServerApply.map(\.id), ["tx-local"])
    let syncStateAfterServerApply = try await runtime.syncState()
    expectNoDifference(syncStateAfterServerApply.processedTransactionID, "server-tx-1")
    let persistenceStateAfterServerApply = try await runtime.persistence.loadState()
    expectNoDifference(
      persistenceStateAfterServerApply.storeRevision,
      persistenceStateBeforeServerApply.storeRevision + 1
    )
    expectNoDifference(
      persistenceStateAfterServerApply.outboxRevision,
      persistenceStateBeforeServerApply.outboxRevision
    )

    let update = try #require(await iterator.next())
    expectNoDifference(
      try TodoExample.decode(update.values),
      [
        TodoRecord(
          id: "todo-local",
          text: "local optimistic write",
          isCompleted: false,
          createdAt: localCreatedAt
        ),
        TodoRecord(
          id: "todo-server",
          text: "server inbound write",
          isCompleted: false,
          createdAt: serverCreatedAt
        ),
      ]
    )

    let relaunchedRuntime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "server-transaction-loopback",
        persistenceURL: cacheURL,
        initialAttributes: TodoExample.attributes
      )
    )
    let relaunchedTodos = try await TodoExample.decode(relaunchedRuntime.query(TodoExample.query))
    expectNoDifference(
      relaunchedTodos,
      [
        TodoRecord(
          id: "todo-local",
          text: "local optimistic write",
          isCompleted: false,
          createdAt: localCreatedAt
        ),
        TodoRecord(
          id: "todo-server",
          text: "server inbound write",
          isCompleted: false,
          createdAt: serverCreatedAt
        ),
      ]
    )
    let relaunchedPending = await relaunchedRuntime.pendingMutations()
    expectNoDifference(relaunchedPending.map(\.id), ["tx-local"])
    let relaunchedSyncState = try await relaunchedRuntime.syncState()
    expectNoDifference(relaunchedSyncState.processedTransactionID, "server-tx-1")
  }

  @Test
  func emptyServerTransactionUpdatesCheckpointWithoutOutboxOrStoreRevision() async throws {
    let cacheURL = try temporaryCacheURL()
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "empty-server-transaction-loopback",
        persistenceURL: cacheURL,
        initialAttributes: TodoExample.attributes
      )
    )
    let before = try await runtime.persistence.loadState()

    let result = try await runtime.applyServerTransaction(
      InstantStoreTransaction(id: "server-empty-tx", operations: []),
      receivedAt: InstantTimestamp(milliseconds: 1_700_000_000_000)
    )

    expectNoDifference(result.mutation.transactionID, "server-empty-tx")
    expectNoDifference(result.mutation.changedEntityIDs, [])
    expectNoDifference(result.mutation.emissions, [])
    expectNoDifference(result.syncState.processedTransactionID, "server-empty-tx")
    expectNoDifference(result.pendingMutationCount, 0)
    let after = try await runtime.persistence.loadState()
    expectNoDifference(after.storeRevision, before.storeRevision)
    expectNoDifference(after.outboxRevision, before.outboxRevision)
    expectNoDifference(after.snapshot.store, before.snapshot.store)
    expectNoDifference(after.snapshot.outbox, [])
    let syncState = try await runtime.syncState()
    expectNoDifference(syncState.processedTransactionID, "server-empty-tx")
  }

  @Test
  func staleRuntimeServerTransactionPreservesNewerPersistedOutbox() async throws {
    let cacheURL = try temporaryCacheURL()
    let localCreatedAt = InstantTimestamp(milliseconds: 1_700_000_000_000)
    let serverCreatedAt = InstantTimestamp(milliseconds: localCreatedAt.milliseconds + 1)
    let staleRuntime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "stale-server-transaction-loopback",
        persistenceURL: cacheURL,
        initialAttributes: TodoExample.attributes
      )
    )
    let writerRuntime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "stale-server-transaction-loopback",
        persistenceURL: cacheURL,
        initialAttributes: TodoExample.attributes
      )
    )
    try await writerRuntime.transact(
      InstantStoreTransaction(
        id: "tx-newer-local",
        operations: TodoExample.createOperations(
          id: "todo-newer-local",
          text: "newer persisted local write",
          createdAt: localCreatedAt,
          transactionID: "tx-newer-local"
        )
      ),
      createdAt: localCreatedAt
    )
    let persistedAfterWriter = try await writerRuntime.persistence.loadState()
    expectNoDifference(persistedAfterWriter.snapshot.outbox.map(\.id), ["tx-newer-local"])
    let initialStalePending = await staleRuntime.pendingMutations()
    expectNoDifference(initialStalePending, [])

    let result = try await staleRuntime.applyServerTransaction(
      InstantStoreTransaction(
        id: "server-stale-runtime",
        operations: TodoExample.createOperations(
          id: "todo-server-stale-runtime",
          text: "server write on stale runtime",
          createdAt: serverCreatedAt,
          transactionID: "server-stale-runtime"
        )
      ),
      receivedAt: InstantTimestamp(milliseconds: serverCreatedAt.milliseconds + 1)
    )

    expectNoDifference(result.pendingMutationCount, 1)
    let staleRuntimePending = await staleRuntime.pendingMutations()
    expectNoDifference(staleRuntimePending.map(\.id), ["tx-newer-local"])
    let persistedAfterServerApply = try await staleRuntime.persistence.loadState()
    expectNoDifference(persistedAfterServerApply.snapshot.outbox.map(\.id), ["tx-newer-local"])
    expectNoDifference(
      persistedAfterServerApply.outboxRevision,
      persistedAfterWriter.outboxRevision
    )
    expectNoDifference(
      persistedAfterServerApply.storeRevision,
      persistedAfterWriter.storeRevision + 1
    )
    let staleRuntimeTodos = try await TodoExample.decode(staleRuntime.query(TodoExample.query))
    expectNoDifference(staleRuntimeTodos.map(\.id), ["todo-newer-local", "todo-server-stale-runtime"])
  }

  @Test
  func runtimeBootstrapRejectsServerCreatedAtAttributes() async throws {
    do {
      _ = try await InstantRuntime.bootstrap(
        configuration: InstantRuntimeConfiguration(
          appID: "test-app",
          persistenceURL: try temporaryCacheURL(),
          initialAttributes: [
            InstantAttribute(
              id: "todos/serverCreatedAt",
              namespace: "todos",
              name: "serverCreatedAt",
              valueType: .date,
              isIndexed: true
            )
          ]
        )
      )
      #expect(Bool(false), "Expected bootstrap to reject serverCreatedAt schema attributes.")
    } catch let error as InstantError {
      expectNoDifference(error.code, .validationFailed)
      expectNoDifference(error.operation, "bootstrap attributes")
      expectNoDifference(error.namespace, "todos")
      expectNoDifference(error.path, "serverCreatedAt")
      expectNoDifference(error.localID, "todos/serverCreatedAt")
    } catch {
      #expect(Bool(false), "Unexpected error: \(error)")
    }
  }

  @Test
  func runtimeConfigurationInitializerReferenceKeepsLegacyShape() async throws {
    let make:
      (
        String,
        URL,
        [InstantAttribute],
        @escaping @Sendable () -> InstantTimestamp,
        @escaping @Sendable () -> String,
        InstantRefreshTokenVerifier,
        InstantGuestAuthenticator,
        InstantMagicCodeExchange,
        InstantIDTokenExchange,
        InstantOAuthExchange,
        InstantAuthTokenInvalidator,
        InstantPlatformAppClient,
        AppBuilderCodeGeneratorClient
      ) -> InstantRuntimeConfiguration = InstantRuntimeConfiguration.init

    let configuration = make(
      "test-app",
      try temporaryCacheURL(),
      TodoExample.attributes,
      { InstantTimestamp(milliseconds: 1_700_000_000_000) },
      { "fixed-id" },
      .local,
      .local,
      .local,
      .local,
      .local,
      .local,
      .local,
      .local
    )

    expectNoDifference(configuration.appID, "test-app")
    expectNoDifference(configuration.apiURI, InstantRuntimeConfiguration.defaultAPIURI)
    expectNoDifference(configuration.websocketURI, InstantRuntimeConfiguration.defaultWebSocketURI)
    expectNoDifference(configuration.initialAttributes, TodoExample.attributes)
    expectNoDifference(configuration.now(), InstantTimestamp(milliseconds: 1_700_000_000_000))
    expectNoDifference(configuration.makeID(), "fixed-id")
    let platformApp = try await configuration.platformAppClient.createApp(
      InstantPlatformAppCreateRequest(
        title: "Pinned initializer",
        orgID: "local-org",
        createdAt: configuration.now(),
        makeID: configuration.makeID
      )
    )
    expectNoDifference(
      platformApp,
      InstantPlatformApp(
        id: "local-platform-fixed-id",
        title: "Pinned initializer",
        orgID: "local-org",
        createdAt: InstantTimestamp(milliseconds: 1_700_000_000_000)
      )
    )
  }

  @Test
  func queryResultsPersistInQueryCacheAcrossLaunches() async throws {
    let cacheURL = try temporaryCacheURL()
    let createdAt = InstantTimestamp(milliseconds: 1_700_000_000_000)
    let cachedAt = InstantTimestamp(milliseconds: createdAt.milliseconds + 10)
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "test-app",
        persistenceURL: cacheURL,
        initialAttributes: TodoExample.attributes,
        now: { cachedAt }
      )
    )
    try await runtime.transact(
      InstantStoreTransaction(
        id: "tx-cached-query",
        operations: TodoExample.createOperations(
          id: "todo-cached",
          text: "restore cached query",
          createdAt: createdAt,
          transactionID: "tx-cached-query"
        )
      ),
      createdAt: createdAt
    )

    let snapshots = try await runtime.query(TodoExample.query)
    let cachedQuery = try await runtime.cachedQuery(TodoExample.query)

    expectNoDifference(cachedQuery?.queryID, TodoExample.query.id)
    expectNoDifference(cachedQuery?.cacheKey, TodoExample.query.cacheKey)
    expectNoDifference(cachedQuery?.plan, TodoExample.query)
    expectNoDifference(cachedQuery?.emission.values, snapshots)
    expectNoDifference(cachedQuery?.updatedAt, cachedAt)

    let secondCreatedAt = InstantTimestamp(milliseconds: createdAt.milliseconds + 1)
    try await runtime.transact(
      InstantStoreTransaction(
        id: "tx-cached-query-2",
        operations: TodoExample.createOperations(
          id: "todo-cached-2",
          text: "replace cached query",
          createdAt: secondCreatedAt,
          transactionID: "tx-cached-query-2"
        )
      ),
      createdAt: secondCreatedAt
    )

    let refreshedSnapshots = try await runtime.query(TodoExample.query)
    let refreshedCache = try await runtime.cachedQuery(TodoExample.query)
    expectNoDifference(refreshedCache?.emission.values, refreshedSnapshots)
    expectNoDifference(refreshedSnapshots.map(\.id), ["todo-cached", "todo-cached-2"])

    try await runtime.closeConnection()
    do {
      _ = try await runtime.queryOnce(TodoExample.query)
      #expect(Bool(false), "Expected queryOnce to fail while the connection is closed.")
    } catch let error as InstantError {
      expectNoDifference(error.code, .networkFailed)
      expectNoDifference(error.operation, "queryOnce")
      expectNoDifference(error.namespace, TodoExample.namespace)
      expectNoDifference(error.cachedQuery?.queryID, TodoExample.query.id)
      expectNoDifference(error.cachedQuery?.cacheKey, TodoExample.query.cacheKey)
      expectNoDifference(error.cachedQuery?.emission.values, refreshedSnapshots)
    } catch {
      #expect(Bool(false), "Unexpected error: \(error)")
    }

    let uncachedPlan = InstantQueryPlan(
      id: "examples.todos.uncached-closed",
      namespace: TodoExample.namespace,
      filters: [.equals(field: "text", value: .string("missing"))]
    )
    do {
      _ = try await runtime.queryOnce(uncachedPlan)
      #expect(Bool(false), "Expected uncached queryOnce to fail while the connection is closed.")
    } catch let error as InstantError {
      expectNoDifference(error.code, .networkFailed)
      expectNoDifference(error.operation, "queryOnce")
      expectNoDifference(error.namespace, TodoExample.namespace)
      expectNoDifference(error.cachedQuery, nil)
    } catch {
      #expect(Bool(false), "Unexpected error: \(error)")
    }

    try await runtime.connect()
    let reconnectedSnapshots = try await runtime.query(TodoExample.query)
    expectNoDifference(reconnectedSnapshots, refreshedSnapshots)

    let relaunchedRuntime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "test-app",
        persistenceURL: cacheURL,
        initialAttributes: TodoExample.attributes
      )
    )
    let relaunchedCache = try await relaunchedRuntime.cachedQuery(TodoExample.query)
    let cachedTodos = try TodoExample.decode(relaunchedCache?.emission.values ?? [])
    let cachedQueries = try await relaunchedRuntime.cachedQueries()

    expectNoDifference(cachedQueries.map(\.queryID), [TodoExample.query.id])
    expectNoDifference(cachedQueries.map(\.cacheKey), [TodoExample.query.cacheKey])
    expectNoDifference(
      cachedTodos,
      [
        TodoRecord(
          id: "todo-cached",
          text: "restore cached query",
          isCompleted: false,
          createdAt: createdAt
        ),
        TodoRecord(
          id: "todo-cached-2",
          text: "replace cached query",
          isCompleted: false,
          createdAt: secondCreatedAt
        )
      ]
    )
  }

  @Test
  func closedQueryDoesNotReturnStaleCachedQueryAfterServerTransaction() async throws {
    let cacheURL = try temporaryCacheURL()
    let seedCreatedAt = InstantTimestamp(milliseconds: 1_700_000_000_000)
    let serverCreatedAt = InstantTimestamp(milliseconds: seedCreatedAt.milliseconds + 1)
    let cachedAt = InstantTimestamp(milliseconds: seedCreatedAt.milliseconds + 10)
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "stale-server-cache",
        persistenceURL: cacheURL,
        initialAttributes: TodoExample.attributes,
        now: { cachedAt }
      )
    )

    try await runtime.transact(
      InstantStoreTransaction(
        id: "tx-stale-cache-seed",
        operations: TodoExample.createOperations(
          id: "todo-stale-cache-seed",
          text: "cached before server",
          createdAt: seedCreatedAt,
          transactionID: "tx-stale-cache-seed"
        )
      ),
      createdAt: seedCreatedAt
    )
    let seededSnapshots = try await runtime.query(TodoExample.query)
    let seededCache = try #require(try await runtime.cachedQuery(TodoExample.query))
    let stateBeforeServerApply = try await runtime.persistence.loadState()

    expectNoDifference(seededCache.storeRevision, stateBeforeServerApply.storeRevision)
    expectNoDifference(seededCache.emission.values, seededSnapshots)

    try await runtime.applyServerTransaction(
      InstantStoreTransaction(
        id: "server-stale-cache",
        operations: TodoExample.createOperations(
          id: "todo-server-stale-cache",
          text: "server after cache",
          createdAt: serverCreatedAt,
          transactionID: "server-stale-cache"
        )
      ),
      receivedAt: InstantTimestamp(milliseconds: serverCreatedAt.milliseconds + 1)
    )
    let stateAfterServerApply = try await runtime.persistence.loadState()
    expectNoDifference(
      stateAfterServerApply.storeRevision,
      stateBeforeServerApply.storeRevision + 1
    )

    let persistedStaleCache = try #require(try await runtime.cachedQuery(TodoExample.query))
    expectNoDifference(persistedStaleCache.storeRevision, stateBeforeServerApply.storeRevision)
    expectNoDifference(persistedStaleCache.emission.values, seededSnapshots)

    try await runtime.closeConnection()
    do {
      _ = try await runtime.queryOnce(TodoExample.query)
      Issue.record("Expected closed queryOnce to fail without a stale cached query.")
    } catch let error as InstantError {
      expectNoDifference(error.code, .networkFailed)
      expectNoDifference(error.operation, "queryOnce")
      expectNoDifference(error.namespace, TodoExample.namespace)
      expectNoDifference(error.cachedQuery, nil)
    } catch {
      Issue.record("Unexpected error: \(error)")
    }
  }

  @Test
  func closedQueryReturnsCachedQueryWhenRevisionChangedButResultMatches() async throws {
    let cacheURL = try temporaryCacheURL()
    let seedCreatedAt = InstantTimestamp(milliseconds: 1_700_000_000_000)
    let completedCreatedAt = InstantTimestamp(milliseconds: seedCreatedAt.milliseconds + 1)
    let cachedAt = InstantTimestamp(milliseconds: seedCreatedAt.milliseconds + 10)
    let openPlan = InstantQueryPlan(
      id: "examples.todos.open",
      namespace: TodoExample.namespace,
      filters: [.equals(field: "isCompleted", value: .bool(false))],
      order: InstantQueryOrder("createdAt", .ascending)
    )
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "matching-stale-revision-cache",
        persistenceURL: cacheURL,
        initialAttributes: TodoExample.attributes,
        now: { cachedAt }
      )
    )

    try await runtime.transact(
      InstantStoreTransaction(
        id: "tx-matching-revision-seed",
        operations: TodoExample.createOperations(
          id: "todo-matching-revision-seed",
          text: "open cached todo",
          createdAt: seedCreatedAt,
          transactionID: "tx-matching-revision-seed"
        )
      ),
      createdAt: seedCreatedAt
    )
    let openSnapshots = try await runtime.query(openPlan)
    let cachedOpenQuery = try #require(try await runtime.cachedQuery(openPlan))
    let stateBeforeUnrelatedApply = try await runtime.persistence.loadState()

    expectNoDifference(cachedOpenQuery.storeRevision, stateBeforeUnrelatedApply.storeRevision)
    expectNoDifference(cachedOpenQuery.emission.values, openSnapshots)

    try await runtime.applyServerTransaction(
      InstantStoreTransaction(
        id: "server-completed-unrelated",
        operations: TodoExample.createOperations(
          id: "todo-completed-unrelated",
          text: "completed after cache",
          createdAt: completedCreatedAt,
          transactionID: "server-completed-unrelated"
        ) + TodoExample.completeOperations(
          id: "todo-completed-unrelated",
          updatedAt: completedCreatedAt,
          transactionID: "server-completed-unrelated"
        )
      ),
      receivedAt: InstantTimestamp(milliseconds: completedCreatedAt.milliseconds + 1)
    )
    let stateAfterUnrelatedApply = try await runtime.persistence.loadState()
    expectNoDifference(
      stateAfterUnrelatedApply.storeRevision,
      stateBeforeUnrelatedApply.storeRevision + 1
    )

    let persistedOlderCache = try #require(try await runtime.cachedQuery(openPlan))
    expectNoDifference(persistedOlderCache.storeRevision, stateBeforeUnrelatedApply.storeRevision)
    expectNoDifference(persistedOlderCache.emission.values, openSnapshots)

    try await runtime.closeConnection()
    do {
      _ = try await runtime.queryOnce(openPlan)
      Issue.record("Expected closed queryOnce to fail with a matching cached query.")
    } catch let error as InstantError {
      expectNoDifference(error.code, .networkFailed)
      expectNoDifference(error.operation, "queryOnce")
      expectNoDifference(error.namespace, TodoExample.namespace)
      expectNoDifference(error.cachedQuery?.queryID, openPlan.id)
      expectNoDifference(error.cachedQuery?.cacheKey, openPlan.cacheKey)
      expectNoDifference(error.cachedQuery?.storeRevision, stateBeforeUnrelatedApply.storeRevision)
      expectNoDifference(error.cachedQuery?.emission.values, openSnapshots)
    } catch {
      Issue.record("Unexpected error: \(error)")
    }
  }

  @Test
  func closedQueryDoesNotReturnStaleCachedQueryAfterCrossRuntimeTransaction() async throws {
    let cacheURL = try temporaryCacheURL()
    let seedCreatedAt = InstantTimestamp(milliseconds: 1_700_000_000_000)
    let writerCreatedAt = InstantTimestamp(milliseconds: seedCreatedAt.milliseconds + 1)
    let cachedAt = InstantTimestamp(milliseconds: seedCreatedAt.milliseconds + 10)
    let staleRuntime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "stale-cross-runtime-cache",
        persistenceURL: cacheURL,
        initialAttributes: TodoExample.attributes,
        now: { cachedAt }
      )
    )

    try await staleRuntime.transact(
      InstantStoreTransaction(
        id: "tx-cross-runtime-cache-seed",
        operations: TodoExample.createOperations(
          id: "todo-cross-runtime-cache-seed",
          text: "cached before writer",
          createdAt: seedCreatedAt,
          transactionID: "tx-cross-runtime-cache-seed"
        )
      ),
      createdAt: seedCreatedAt
    )
    let seededSnapshots = try await staleRuntime.query(TodoExample.query)
    let seededCache = try #require(try await staleRuntime.cachedQuery(TodoExample.query))
    let stateBeforeWriter = try await staleRuntime.persistence.loadState()

    expectNoDifference(seededCache.storeRevision, stateBeforeWriter.storeRevision)
    expectNoDifference(seededCache.emission.values, seededSnapshots)

    let writerRuntime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "stale-cross-runtime-cache",
        persistenceURL: cacheURL
      )
    )
    try await writerRuntime.transact(
      InstantStoreTransaction(
        id: "tx-cross-runtime-cache-writer",
        operations: TodoExample.createOperations(
          id: "todo-cross-runtime-cache-writer",
          text: "writer after cache",
          createdAt: writerCreatedAt,
          transactionID: "tx-cross-runtime-cache-writer"
        )
      ),
      createdAt: writerCreatedAt
    )
    let stateAfterWriter = try await staleRuntime.persistence.loadState()
    expectNoDifference(stateAfterWriter.storeRevision, stateBeforeWriter.storeRevision + 1)

    let persistedStaleCache = try #require(try await staleRuntime.cachedQuery(TodoExample.query))
    expectNoDifference(persistedStaleCache.storeRevision, stateBeforeWriter.storeRevision)
    expectNoDifference(persistedStaleCache.emission.values, seededSnapshots)

    try await staleRuntime.closeConnection()
    do {
      _ = try await staleRuntime.queryOnce(TodoExample.query)
      Issue.record("Expected closed queryOnce to fail without a stale cached query.")
    } catch let error as InstantError {
      expectNoDifference(error.code, .networkFailed)
      expectNoDifference(error.operation, "queryOnce")
      expectNoDifference(error.namespace, TodoExample.namespace)
      expectNoDifference(error.cachedQuery, nil)
    } catch {
      Issue.record("Unexpected error: \(error)")
    }
  }

  @Test
  func queryCacheRowsSaveReplaceAndReloadForPersistedObjectParity() async throws {
    let source = persistedObjectSource(
      "PersistedObject saves values to storage / merges existing values "
        + "[adapted: Swift has no storage-memory merge callback; query cache rows replace existing keyed storage.]"
    )
    let cacheURL = try temporaryCacheURL()
    let store = try SQLitePersistenceStore(fileURL: cacheURL)
    try await store.bootstrap()

    let firstEntry = persistedObjectCacheEntry(
      cacheKey: "cache-a",
      updatedAt: InstantTimestamp(milliseconds: 1),
      payload: "b"
    )
    let didSaveFirstEntry = try await store.saveQueryCache(
      firstEntry,
      expectedStoreRevision: 0
    )
    expectNoDifference(didSaveFirstEntry, true, source)
    let firstEntries = try await store.loadQueryCache()
    expectNoDifference(firstEntries, [firstEntry], source)

    let reloadedStore = try SQLitePersistenceStore(fileURL: cacheURL)
    try await reloadedStore.bootstrap()
    let reloadedEntries = try await reloadedStore.loadQueryCache()
    expectNoDifference(reloadedEntries, [firstEntry], source)

    let replacementEntry = persistedObjectCacheEntry(
      cacheKey: "cache-a",
      updatedAt: InstantTimestamp(milliseconds: 2),
      payload: "merged-value-2"
    )
    let didSaveReplacementEntry = try await reloadedStore.saveQueryCache(
      replacementEntry,
      expectedStoreRevision: 0
    )
    expectNoDifference(didSaveReplacementEntry, true, source)

    let secondReloadedStore = try SQLitePersistenceStore(fileURL: cacheURL)
    try await secondReloadedStore.bootstrap()
    let secondReloadedEntries = try await secondReloadedStore.loadQueryCache()
    expectNoDifference(secondReloadedEntries, [replacementEntry], source)
  }

  @Test
  func queryCacheRecoversAfterSQLiteConnectionCloseForPersistedObjectParity() async throws {
    let source = persistedObjectSource(
      "IndexedDBStorage recovers when the database connection closes "
        + "[adapted: Swift reopens its actor-confined SQLite handle after an unexpected close.]"
    )
    let cacheURL = try temporaryCacheURL()
    let store = try SQLitePersistenceStore(fileURL: cacheURL)
    try await store.bootstrap()

    let firstEntry = persistedObjectCacheEntry(
      cacheKey: "key1",
      updatedAt: InstantTimestamp(milliseconds: 1),
      payload: "value1"
    )
    let didSaveFirstEntry = try await store.saveQueryCache(firstEntry, expectedStoreRevision: 0)
    expectNoDifference(didSaveFirstEntry, true, source)
    let firstValue = try await store.cachedQuery(cacheKey: "key1")
    expectNoDifference(firstValue, firstEntry, source)

    await store.simulateUnexpectedConnectionCloseForTesting()
    let secondEntry = persistedObjectCacheEntry(
      cacheKey: "key2",
      updatedAt: InstantTimestamp(milliseconds: 2),
      payload: "value2"
    )
    let thirdEntry = persistedObjectCacheEntry(
      cacheKey: "key3",
      updatedAt: InstantTimestamp(milliseconds: 3),
      payload: "value3"
    )
    let fourthEntry = persistedObjectCacheEntry(
      cacheKey: "key4",
      updatedAt: InstantTimestamp(milliseconds: 4),
      payload: "value4"
    )
    let didSaveSecondEntry = try await store.saveQueryCache(secondEntry, expectedStoreRevision: 0)
    let didSaveBatch = try await store.saveQueryCache(
      [thirdEntry, fourthEntry],
      expectedStoreRevision: 0
    )
    expectNoDifference(didSaveSecondEntry, true, source)
    expectNoDifference(didSaveBatch, true, source)
    let recoveredFirstValue = try await store.cachedQuery(cacheKey: "key1")
    let secondValue = try await store.cachedQuery(cacheKey: "key2")
    expectNoDifference(recoveredFirstValue, firstEntry, source)
    expectNoDifference(secondValue, secondEntry, source)

    await store.simulateUnexpectedConnectionCloseForTesting()
    let cacheKeys = try await store.loadQueryCache().map(\.cacheKey).sorted()
    expectNoDifference(cacheKeys, ["key1", "key2", "key3", "key4"], source)

    await store.simulateUnexpectedConnectionCloseForTesting()
    try await store.deleteQueryCache(cacheKey: "key4")
    let deletedValue = try await store.cachedQuery(cacheKey: "key4")
    expectNoDifference(deletedValue, nil, source)
  }

  @Test
  func queryCachePruningPreservesLiveKeysAndDropsOldestUnpreservedRowsForPersistedObjectParity()
    async throws
  {
    let source = persistedObjectSource(
      "PersistedObject garbage collects when we exceed max items "
        + "[adapted: preservingCacheKeys models PersistedObject's live in-memory keys.]"
    )
    let cacheURL = try temporaryCacheURL()
    let store = try SQLitePersistenceStore(fileURL: cacheURL)
    try await store.bootstrap()
    let entries = try await savePersistedObjectCacheEntries(in: store)
    let allKeys = Set(entries.map(\.cacheKey))
    let liveKeysAfterUnloadingE = Set(entries.dropLast().map(\.cacheKey))

    let protected = try await store.pruneQueryCache(
      policy: InstantQueryCachePruningPolicy(maxEntries: 3),
      preservingCacheKeys: allKeys
    )
    expectNoDifference(protected.removedCacheKeys, [], source)
    expectNoDifference(protected.remainingCacheKeys, entries.map(\.cacheKey), source)

    let afterUnloadingE = try await store.pruneQueryCache(
      policy: InstantQueryCachePruningPolicy(maxEntries: 3),
      preservingCacheKeys: liveKeysAfterUnloadingE
    )
    expectNoDifference(afterUnloadingE.removedCacheKeys, ["cache-e"], source)
    expectNoDifference(afterUnloadingE.remainingCacheKeys, ["cache-a", "cache-b", "cache-c", "cache-d"], source)

    let reloadedStore = try SQLitePersistenceStore(fileURL: cacheURL)
    try await reloadedStore.bootstrap()
    let afterRelaunch = try await reloadedStore.pruneQueryCache(
      policy: InstantQueryCachePruningPolicy(maxEntries: 3)
    )
    expectNoDifference(afterRelaunch.removedCacheKeys, ["cache-a"], source)
    expectNoDifference(afterRelaunch.remainingCacheKeys, ["cache-b", "cache-c", "cache-d"], source)
  }

  @Test
  func queryCachePruningUsesEncodedRowBytesForPersistedObjectSizeParity() async throws {
    let source = persistedObjectSource(
      "PersistedObject garbage collects when we exceed max size "
        + "[adapted: Swift uses persisted JSON row bytes instead of a JavaScript objectSize callback.]"
    )
    let cacheURL = try temporaryCacheURL()
    let store = try SQLitePersistenceStore(fileURL: cacheURL)
    try await store.bootstrap()
    let entries = try await savePersistedObjectCacheEntries(in: store)
    let allKeys = Set(entries.map(\.cacheKey))
    let liveKeysAfterUnloadingE = Set(entries.dropLast().map(\.cacheKey))
    let cEntry = try #require(entries.first { $0.cacheKey == "cache-c" })
    let dEntry = try #require(entries.first { $0.cacheKey == "cache-d" })
    let cAndDBudget = try encodedQueryCacheByteCount(cEntry) + encodedQueryCacheByteCount(dEntry)

    let protected = try await store.pruneQueryCache(
      policy: InstantQueryCachePruningPolicy(maxEncodedJSONBytes: cAndDBudget),
      preservingCacheKeys: allKeys
    )
    expectNoDifference(protected.removedCacheKeys, [], source)
    expectNoDifference(protected.remainingCacheKeys, entries.map(\.cacheKey), source)

    let afterUnloadingE = try await store.pruneQueryCache(
      policy: InstantQueryCachePruningPolicy(maxEncodedJSONBytes: cAndDBudget),
      preservingCacheKeys: liveKeysAfterUnloadingE
    )
    expectNoDifference(afterUnloadingE.removedCacheKeys, ["cache-e"], source)
    expectNoDifference(afterUnloadingE.remainingCacheKeys, ["cache-a", "cache-b", "cache-c", "cache-d"], source)

    let reloadedStore = try SQLitePersistenceStore(fileURL: cacheURL)
    try await reloadedStore.bootstrap()
    let afterRelaunch = try await reloadedStore.pruneQueryCache(
      policy: InstantQueryCachePruningPolicy(maxEncodedJSONBytes: cAndDBudget)
    )
    expectNoDifference(afterRelaunch.removedCacheKeys, ["cache-a", "cache-b"], source)
    expectNoDifference(afterRelaunch.remainingCacheKeys, ["cache-c", "cache-d"], source)
    expectNoDifference(afterRelaunch.remainingEncodedJSONByteCount, cAndDBudget, source)
  }

  @Test
  func queryCachePruningUsesUpdatedAtForPersistedObjectAgeParity() async throws {
    let source = persistedObjectSource(
      "PersistedObject garbage collects when we exceed max age "
        + "[adapted: Swift uses instant_query_cache.updated_at_ms as the persisted age clock.]"
    )
    let cacheURL = try temporaryCacheURL()
    let store = try SQLitePersistenceStore(fileURL: cacheURL)
    try await store.bootstrap()
    let entries = try await savePersistedObjectCacheEntries(in: store)
    let allKeys = Set(entries.map(\.cacheKey))
    let liveKeysAfterUnloadingE = Set(entries.dropLast().map(\.cacheKey))

    let protected = try await store.pruneQueryCache(
      policy: InstantQueryCachePruningPolicy(maxAgeMilliseconds: 0),
      now: InstantTimestamp(milliseconds: 100),
      preservingCacheKeys: allKeys
    )
    expectNoDifference(protected.removedCacheKeys, [], source)
    expectNoDifference(protected.remainingCacheKeys, entries.map(\.cacheKey), source)

    let afterUnloadingE = try await store.pruneQueryCache(
      policy: InstantQueryCachePruningPolicy(maxAgeMilliseconds: 0),
      now: InstantTimestamp(milliseconds: 100),
      preservingCacheKeys: liveKeysAfterUnloadingE
    )
    expectNoDifference(afterUnloadingE.removedCacheKeys, ["cache-e"], source)
    expectNoDifference(afterUnloadingE.remainingCacheKeys, ["cache-a", "cache-b", "cache-c", "cache-d"], source)

    let reloadedStore = try SQLitePersistenceStore(fileURL: cacheURL)
    try await reloadedStore.bootstrap()
    let afterRelaunch = try await reloadedStore.pruneQueryCache(
      policy: InstantQueryCachePruningPolicy(maxAgeMilliseconds: 0),
      now: InstantTimestamp(milliseconds: 100)
    )
    expectNoDifference(
      afterRelaunch.removedCacheKeys,
      ["cache-a", "cache-b", "cache-c", "cache-d"],
      source
    )
    expectNoDifference(afterRelaunch.remainingCacheKeys, [], source)
  }

  @Test
  func queryCachePruningKeepsRowsAtPersistedObjectAgeCutoff() async throws {
    let source = persistedObjectSource(
      "PersistedObject garbage collects when we exceed max age "
        + "[adapted: Swift pins the same strict updatedAt cutoff boundary.]"
    )
    let cacheURL = try temporaryCacheURL()
    let store = try SQLitePersistenceStore(fileURL: cacheURL)
    try await store.bootstrap()
    let boundaryEntry = persistedObjectCacheEntry(
      cacheKey: "cache-boundary",
      updatedAt: InstantTimestamp(milliseconds: 50),
      payload: "boundary"
    )
    let olderEntry = persistedObjectCacheEntry(
      cacheKey: "cache-older",
      updatedAt: InstantTimestamp(milliseconds: 49),
      payload: "older"
    )
    for entry in [olderEntry, boundaryEntry] {
      let didSave = try await store.saveQueryCache(entry, expectedStoreRevision: 0)
      expectNoDifference(didSave, true, source)
    }

    let result = try await store.pruneQueryCache(
      policy: InstantQueryCachePruningPolicy(maxAgeMilliseconds: 50),
      now: InstantTimestamp(milliseconds: 100)
    )

    expectNoDifference(result.removedCacheKeys, ["cache-older"], source)
    expectNoDifference(result.remainingCacheKeys, ["cache-boundary"], source)
  }

  @Test
  func observeRefreshesDurableSnapshotBeforeInitialEmission() async throws {
    let cacheURL = try temporaryCacheURL()
    let createdAt = InstantTimestamp(milliseconds: 1_700_000_000_000)
    let staleRuntime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "observe-refresh",
        persistenceURL: cacheURL,
        initialAttributes: TodoExample.attributes
      )
    )
    let writerRuntime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "observe-refresh",
        persistenceURL: cacheURL,
        initialAttributes: TodoExample.attributes
      )
    )
    try await writerRuntime.transact(
      InstantStoreTransaction(
        id: "tx-observe-refresh",
        operations: TodoExample.createOperations(
          id: "todo-observe-refresh",
          text: "offline observer refresh",
          createdAt: createdAt,
          transactionID: "tx-observe-refresh"
        )
      ),
      createdAt: createdAt
    )
    try await writerRuntime.closeConnection()

    let stream = await staleRuntime.observe(TodoExample.query)
    var iterator = stream.makeAsyncIterator()
    let emission = try #require(await iterator.next())
    let todos = try TodoExample.decode(emission.values)
    expectNoDifference(todos.map(\.text), ["offline observer refresh"])
  }

  @Test
  func deleteEntityRemovesTodoAndPersistsAcrossLaunches() async throws {
    let cacheURL = try temporaryCacheURL()
    let createdAt = InstantTimestamp(milliseconds: 1_700_000_000_100)
    let secondCreatedAt = InstantTimestamp(milliseconds: createdAt.milliseconds + 1)

    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "test-app",
        persistenceURL: cacheURL,
        initialAttributes: TodoExample.attributes
      )
    )
    try await runtime.transact(
      InstantStoreTransaction(
        id: "tx-create-deleted-todo",
        operations: TodoExample.createOperations(
          id: "todo-delete-me",
          text: "delete me",
          createdAt: createdAt,
          transactionID: "tx-create-deleted-todo"
        )
      ),
      createdAt: createdAt
    )
    try await runtime.transact(
      InstantStoreTransaction(
        id: "tx-create-kept-todo",
        operations: TodoExample.createOperations(
          id: "todo-keep-me",
          text: "keep me",
          createdAt: secondCreatedAt,
          transactionID: "tx-create-kept-todo"
        )
      ),
      createdAt: secondCreatedAt
    )
    try await runtime.transact(
      InstantStoreTransaction(
        id: "tx-delete-todo",
        operations: TodoExample.deleteOperations(id: "todo-delete-me")
      ),
      createdAt: InstantTimestamp(milliseconds: createdAt.milliseconds + 2)
    )

    let todos = try await TodoExample.decode(runtime.query(TodoExample.query))
    expectNoDifference(todos.map(\.id), ["todo-keep-me"])

    let relaunchedRuntime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "test-app",
        persistenceURL: cacheURL,
        initialAttributes: TodoExample.attributes
      )
    )
    let relaunchedTodos = try await TodoExample.decode(relaunchedRuntime.query(TodoExample.query))
    expectNoDifference(relaunchedTodos.map(\.id), ["todo-keep-me"])

    let pending = await relaunchedRuntime.pendingMutations()
    expectNoDifference(
      pending.map(\.id),
      ["tx-create-deleted-todo", "tx-create-kept-todo", "tx-delete-todo"]
    )
  }

  @Test
  func updateTextReplacesTodoAndPersistsAcrossLaunches() async throws {
    let cacheURL = try temporaryCacheURL()
    let createdAt = InstantTimestamp(milliseconds: 1_700_000_000_200)
    let updatedAt = InstantTimestamp(milliseconds: createdAt.milliseconds + 1)

    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "test-app",
        persistenceURL: cacheURL,
        initialAttributes: TodoExample.attributes
      )
    )
    try await runtime.transact(
      InstantStoreTransaction(
        id: "tx-create-update-todo",
        operations: TodoExample.createOperations(
          id: "todo-update-me",
          text: "draft text",
          createdAt: createdAt,
          transactionID: "tx-create-update-todo"
        )
      ),
      createdAt: createdAt
    )
    try await runtime.transact(
      InstantStoreTransaction(
        id: "tx-update-todo-text",
        operations: TodoExample.updateTextOperations(
          id: "todo-update-me",
          text: "polished text",
          updatedAt: updatedAt,
          transactionID: "tx-update-todo-text"
        )
      ),
      createdAt: updatedAt
    )

    let todos = try await TodoExample.decode(runtime.query(TodoExample.query))
    expectNoDifference(todos.map(\.text), ["polished text"])
    expectNoDifference(todos.map(\.createdAt), [createdAt])

    let relaunchedRuntime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "test-app",
        persistenceURL: cacheURL,
        initialAttributes: TodoExample.attributes
      )
    )
    let relaunchedTodos = try await TodoExample.decode(relaunchedRuntime.query(TodoExample.query))
    expectNoDifference(relaunchedTodos.map(\.text), ["polished text"])

    let pending = await relaunchedRuntime.pendingMutations()
    expectNoDifference(pending.map(\.id), ["tx-create-update-todo", "tx-update-todo-text"])
  }

  @Test
  func lookupOperationsApplyOptimisticallyAndPersistOutboxAcrossLaunches() async throws {
    let cacheURL = try temporaryCacheURL()
    let seedTime = InstantTimestamp(milliseconds: 1_700_000_000_300)
    let lookupTime = InstantTimestamp(milliseconds: seedTime.milliseconds + 1)
    let attributes = lookupTestAttributes()
    let userLookup = InstantLookupRef(
      attributeID: "users/email",
      value: .string("blob@example.com")
    )
    let renamedUserLookup = InstantLookupRef(
      attributeID: "users/email",
      value: .string("blob@instantdb.com")
    )
    let postLookup = InstantLookupRef(
      attributeID: "posts/slug",
      value: .string("hello-lookup")
    )
    let seedTransaction = InstantStoreTransaction(
      id: "tx-core-lookup-seed",
      operations: [
        .insert(
          InstantTriple(
            entityID: "user-1",
            attributeID: "users/id",
            value: .string("user-1"),
            txID: "tx-core-lookup-seed",
            txTime: seedTime
          )
        ),
        .insert(
          InstantTriple(
            entityID: "user-1",
            attributeID: "users/email",
            value: .string("blob@example.com"),
            txID: "tx-core-lookup-seed",
            txTime: seedTime
          )
        ),
        .insert(
          InstantTriple(
            entityID: "user-1",
            attributeID: "users/name",
            value: .string("Blob"),
            txID: "tx-core-lookup-seed",
            txTime: seedTime
          )
        ),
        .insert(
          InstantTriple(
            entityID: "post-1",
            attributeID: "posts/id",
            value: .string("post-1"),
            txID: "tx-core-lookup-seed",
            txTime: seedTime
          )
        ),
        .insert(
          InstantTriple(
            entityID: "post-1",
            attributeID: "posts/slug",
            value: .string("hello-lookup"),
            txID: "tx-core-lookup-seed",
            txTime: seedTime
          )
        ),
        .insert(
          InstantTriple(
            entityID: "post-1",
            attributeID: "posts/title",
            value: .string("Hello lookup"),
            txID: "tx-core-lookup-seed",
            txTime: seedTime
          )
        ),
      ]
    )
    let lookupTransaction = InstantStoreTransaction(
      id: "tx-core-lookup",
      operations: [
        .insertByLookup(
          entity: userLookup,
          attributeID: "users/id",
          value: .lookupRef(userLookup),
          txID: "tx-core-lookup",
          txTime: lookupTime
        ),
        .insertByLookup(
          entity: userLookup,
          attributeID: "users/name",
          value: .string("Blob Jr."),
          txID: "tx-core-lookup",
          txTime: lookupTime
        ),
        .insertByLookup(
          entity: userLookup,
          attributeID: "users/email",
          value: .string("blob@instantdb.com"),
          txID: "tx-core-lookup",
          txTime: lookupTime
        ),
        .insertByLookup(
          entity: userLookup,
          attributeID: "users/name",
          value: .string("Should not apply after the lookup value changes"),
          txID: "tx-core-lookup",
          txTime: lookupTime
        ),
        .insertByLookup(
          entity: postLookup,
          attributeID: "posts/id",
          value: .lookupRef(postLookup),
          txID: "tx-core-lookup",
          txTime: lookupTime
        ),
        .insertByLookup(
          entity: postLookup,
          attributeID: "posts/author",
          value: .lookupRef(renamedUserLookup),
          txID: "tx-core-lookup",
          txTime: lookupTime
        ),
      ]
    )

    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "test-app",
        persistenceURL: cacheURL,
        initialAttributes: attributes
      )
    )
    try await runtime.transact(seedTransaction, createdAt: seedTime)
    try await runtime.transact(lookupTransaction, createdAt: lookupTime)

    let users = try await runtime.query(InstantQueryPlan(id: "lookup.users", namespace: "users"))
    expectNoDifference(users.map(\.id), ["user-1"])
    expectNoDifference(users.first?.values["email"]?.first, .string("blob@instantdb.com"))
    expectNoDifference(users.first?.values["name"]?.first, .string("Blob Jr."))

    let posts = try await runtime.query(InstantQueryPlan(id: "lookup.posts", namespace: "posts"))
    expectNoDifference(posts.map(\.id), ["post-1"])
    expectNoDifference(posts.first?.values["author"]?.first, .ref("user-1"))

    let relaunchedRuntime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "test-app",
        persistenceURL: cacheURL,
        initialAttributes: attributes
      )
    )
    let relaunchedPending = await relaunchedRuntime.pendingMutations()
    expectNoDifference(relaunchedPending.map(\.id), ["tx-core-lookup-seed", "tx-core-lookup"])
    expectNoDifference(
      relaunchedPending.first { $0.id == "tx-core-lookup" }?.transaction,
      lookupTransaction
    )
  }

  @Test
  func unresolvedLookupOperationsNoOpLocallyButPersistPendingAcrossLaunches() async throws {
    let cacheURL = try temporaryCacheURL()
    let createdAt = InstantTimestamp(milliseconds: 1_700_000_000_325)
    let lookup = InstantLookupRef(
      attributeID: "users/email",
      value: .string("missing@example.com")
    )
    let transaction = InstantStoreTransaction(
      id: "tx-unresolved-core-lookup",
      operations: [
        .insertByLookup(
          entity: lookup,
          attributeID: "users/name",
          value: .string("Server may resolve later"),
          txID: "tx-unresolved-core-lookup",
          txTime: createdAt
        )
      ]
    )

    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "test-app",
        persistenceURL: cacheURL,
        initialAttributes: lookupTestAttributes()
      )
    )
    try await runtime.transact(transaction, createdAt: createdAt)

    let users = try await runtime.query(InstantQueryPlan(id: "lookup.empty-users", namespace: "users"))
    expectNoDifference(users, [])

    let relaunchedRuntime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "test-app",
        persistenceURL: cacheURL,
        initialAttributes: lookupTestAttributes()
      )
    )
    let relaunchedPending = await relaunchedRuntime.pendingMutations()
    expectNoDifference(relaunchedPending.map(\.transaction), [transaction])
  }

  @Test
  func ruleParamsPersistPendingWithoutChangingLocalStore() async throws {
    let cacheURL = try temporaryCacheURL()
    let createdAt = InstantTimestamp(milliseconds: 1_700_000_000_350)
    let lookup = InstantLookupRef(
      attributeID: "users/email",
      value: .string("missing@example.com")
    )
    let transactions = [
      InstantStoreTransaction(
        id: "tx-rule-params-id",
        operations: [
          .ruleParams(
            entityID: "user-rule",
            namespace: "users",
            params: .object(["role": .string("owner")])
          )
        ]
      ),
      InstantStoreTransaction(
        id: "tx-rule-params-lookup",
        operations: [
          .ruleParamsByLookup(
            entity: lookup,
            namespace: "users",
            params: .object(["role": .string("editor")])
          )
        ]
      ),
    ]

    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "test-app",
        persistenceURL: cacheURL,
        initialAttributes: lookupTestAttributes()
      )
    )
    for transaction in transactions {
      try await runtime.transact(transaction, createdAt: createdAt)
    }

    let users = try await runtime.query(InstantQueryPlan(id: "rule-params.users", namespace: "users"))
    expectNoDifference(users, [])

    let relaunchedRuntime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "test-app",
        persistenceURL: cacheURL,
        initialAttributes: lookupTestAttributes()
      )
    )
    let relaunchedPending = await relaunchedRuntime.pendingMutations()
    expectNoDifference(relaunchedPending.map(\.transaction), transactions)
  }

  @Test
  func ruleParamsByLookupRejectsNonUniqueLookupAttributesBeforePersistence() async throws {
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "test-app",
        persistenceURL: temporaryCacheURL(),
        initialAttributes: lookupTestAttributes()
      )
    )

    do {
      try await runtime.transact(
        InstantStoreTransaction(
          id: "tx-invalid-rule-params-lookup",
          operations: [
            .ruleParamsByLookup(
              entity: InstantLookupRef(attributeID: "users/name", value: .string("Blob")),
              namespace: "users",
              params: .object(["role": .string("owner")])
            )
          ]
        )
      )
      #expect(Bool(false), "Expected non-unique rule params lookup to fail.")
    } catch let error as InstantError {
      expectNoDifference(error.code, .validationFailed)
      expectNoDifference(error.operation, "lookup entity")
      expectNoDifference(error.namespace, "users")
      expectNoDifference(error.path, "name")
    } catch {
      #expect(Bool(false), "Unexpected error: \(error)")
    }

    let pending = await runtime.pendingMutations()
    expectNoDifference(pending, [])
  }

  @Test
  func ruleParamsOperationCodableShapeRoundTrips() throws {
    let lookup = InstantLookupRef(
      attributeID: "users/email",
      value: .string("blob@example.com")
    )
    let transaction = InstantStoreTransaction(
      id: "tx-rule-params-codable",
      operations: [
        .ruleParams(
          entityID: "user-rule",
          namespace: "users",
          params: .object(["role": .string("owner")])
        ),
        .ruleParamsByLookup(
          entity: lookup,
          namespace: "users",
          params: .object(["role": .string("editor")])
        ),
      ]
    )

    let data = try JSONEncoder().encode(transaction)
    let decoded = try JSONDecoder().decode(InstantStoreTransaction.self, from: data)

    expectNoDifference(decoded, transaction)
  }

  @Test
  func requireTripleExistsRejectsMissingTripleBeforePersistence() async throws {
    let cacheURL = try temporaryCacheURL()
    let timestamp = InstantTimestamp(milliseconds: 1_700_000_000_000)
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "test-app",
        persistenceURL: cacheURL,
        initialAttributes: ReminderExample.attributes,
        now: { timestamp }
      )
    )
    try await runtime.transact(
      InstantStoreTransaction(
        id: "tx-list",
        operations: ReminderExample.createListOperations(
          id: "list-a",
          title: "A",
          position: 0,
          createdAt: timestamp,
          transactionID: "tx-list"
        )
      ),
      createdAt: timestamp
    )
    do {
      try await runtime.transact(
        InstantStoreTransaction(
          id: "tx-require-missing",
          operations: [
            .requireTripleExists(
              entityID: "reminder-a",
              attributeID: "reminders/list",
              value: .ref("list-a")
            )
          ]
        ),
        createdAt: timestamp
      )
      #expect(Bool(false), "Expected missing triple precondition to fail.")
    } catch let error as InstantError {
      expectNoDifference(error.code, .validationFailed)
      expectNoDifference(error.operation, "require triple")
      expectNoDifference(error.namespace, ReminderExample.remindersNamespace)
      expectNoDifference(error.path, "list")
      expectNoDifference(error.localID, "reminder-a")
    } catch {
      #expect(Bool(false), "Unexpected error: \(error)")
    }
  }

  @Test
  func transportMutationLowersPendingOperationsToInstantTxSteps() throws {
    let txTime = InstantTimestamp(milliseconds: 1_700_000_000_000)
    let lookup = InstantLookupRef(
      attributeID: "users/email",
      value: .string("blob@example.com")
    )
    let transaction = InstantStoreTransaction(
      id: "tx-transport",
      operations: [
        .requireEntityMissing(entityID: "todo-1", namespace: "todos"),
        .insert(
          InstantTriple(
            entityID: "todo-1",
            attributeID: "todos/id",
            value: .string("todo-1"),
            txID: "tx-transport",
            txTime: txTime
          )
        ),
        .insert(
          InstantTriple(
            entityID: "todo-1",
            attributeID: "todos/text",
            value: .string("Ship transport lowering"),
            txID: "tx-transport",
            txTime: txTime
          )
        ),
        .insert(
          InstantTriple(
            entityID: "todo-1",
            attributeID: "todos/createdAt",
            value: .date(Date(timeIntervalSince1970: Double(1_700_000_000_123) / 1000)),
            txID: "tx-transport",
            txTime: txTime
          )
        ),
        .merge(
          InstantTriple(
            entityID: "todo-1",
            attributeID: "todos/metadata",
            value: .json(.object(["nested": .object(["done": .bool(false)])])),
            txID: "tx-transport",
            txTime: txTime
          )
        ),
        .requireEntityExistsByLookup(lookup, namespace: "users"),
        .insertByLookup(
          entity: lookup,
          attributeID: "users/name",
          value: .string("Blob"),
          txID: "tx-transport",
          txTime: txTime
        ),
        .retract(
          InstantTriple(
            entityID: "todo-1",
            attributeID: "todos/project",
            value: .ref("project-1"),
            txID: "tx-transport",
            txTime: txTime
          )
        ),
        .ruleParams(
          entityID: "todo-1",
          namespace: "todos",
          params: .object(["role": .string("owner")])
        ),
        .requireEntityExists(entityID: "old-todo", namespace: "todos"),
        .deleteEntity("old-todo"),
      ]
    )
    let mutation = PendingMutation(id: "tx-transport", createdAt: txTime, transaction: transaction)
    let transportMutation = InstantTransportMutation(mutation)

    expectNoDifference(transportMutation.preconditions.count, 3)
    expectNoDifference(transportMutation.txSteps.count, 8)

    let data = try JSONEncoder().encode(transportMutation)
    let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    let preconditions = try #require(object["preconditions"] as? [[String: Any]])
    expectNoDifference(preconditions.map { $0["kind"] as? String }, [
      "entity-missing",
      "entity-exists",
      "entity-exists",
    ])

    let txSteps = try #require(object["txSteps"] as? [[Any]])
    expectNoDifference(txSteps[0][0] as? String, "add-triple")
    expectNoDifference(txSteps[0][1] as? String, "todo-1")
    expectNoDifference(txSteps[0][2] as? String, "todos/id")
    expectNoDifference(txSteps[0][3] as? String, "todo-1")
    expectNoDifference((txSteps[0][4] as? [String: Any])?["mode"] as? String, "create")

    expectNoDifference(txSteps[2][0] as? String, "add-triple")
    expectNoDifference(txSteps[2][2] as? String, "todos/createdAt")
    expectNoDifference(txSteps[2][3] as? String, "2023-11-14T22:13:20.123Z")
    expectNoDifference((txSteps[2][4] as? [String: Any])?["mode"] as? String, "create")

    expectNoDifference(txSteps[3][0] as? String, "deep-merge-triple")
    let metadata = try #require(txSteps[3][3] as? [String: Any])
    let nested = try #require(metadata["nested"] as? [String: Any])
    expectNoDifference(nested["done"] as? Bool, false)

    let lookupEntity = try #require(txSteps[4][1] as? [Any])
    expectNoDifference(lookupEntity[0] as? String, "users/email")
    expectNoDifference(lookupEntity[1] as? String, "blob@example.com")
    expectNoDifference((txSteps[4][4] as? [String: Any])?["mode"] as? String, "update")

    expectNoDifference(txSteps[5][0] as? String, "retract-triple")
    expectNoDifference(txSteps[6][0] as? String, "rule-params")
    expectNoDifference(txSteps[7][0] as? String, "delete-entity")
    expectNoDifference(txSteps[7][2] as? String, "todos")
  }

  @Test
  func transportMutationPortsInstamlBasicUpdateTransform() throws {
    let txTime = InstantTimestamp(milliseconds: 1_700_000_000_000)
    let source =
      "upstream/instant/client/packages/core/__tests__/src/instaml.test.ts "
      + "simple update transform / undefined is ignored in update / ignores id attrs "
      + "[adapted: InstantInstamlTransform omits absent fields and derives primary-key triples from the entity id.]"

    func txSteps(for transaction: InstantStoreTransaction) throws -> [[Any]] {
      let mutation = InstantTransportMutation(
        PendingMutation(id: transaction.id, createdAt: txTime, transaction: transaction)
      )
      let data = try JSONEncoder().encode(mutation)
      let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
      return try #require(object["txSteps"] as? [[Any]])
    }

    func stepSummary(_ steps: [[Any]]) -> [[String]] {
      steps.map { step in
        [
          step[safe: 0] as? String ?? "",
          step[safe: 1] as? String ?? "",
          step[safe: 2] as? String ?? "",
          step[safe: 3] as? String ?? "",
          (step[safe: 4] as? [String: Any])?["mode"] as? String ?? "",
        ]
      }
    }

    let simpleUpdate = try txSteps(
      for: InstantStoreTransaction(
        id: "tx-instaml-simple-update",
        operations: InstantInstamlTransform.updateOperations(
          namespace: "books",
          entityID: "book-1",
          fields: ["title": .some(.string("New Title"))],
          txID: "tx-instaml-simple-update",
          txTime: txTime
        )
      )
    )
    expectNoDifference(simpleUpdate.map(\.count), [4, 4], source)
    expectNoDifference(
      stepSummary(simpleUpdate).sorted { $0.joined(separator: "|") < $1.joined(separator: "|") },
      [
        ["add-triple", "book-1", "books/id", "book-1", ""],
        ["add-triple", "book-1", "books/title", "New Title", ""],
      ],
      source
    )

    let omittedFieldsUpdate = try txSteps(
      for: InstantStoreTransaction(
        id: "tx-instaml-omitted-fields",
        operations: InstantInstamlTransform.updateOperations(
          namespace: "users",
          entityID: "user-1",
          fields: [
            "fullName": nil,
            "handle": .some(.string("bobby")),
          ],
          txID: "tx-instaml-omitted-fields",
          txTime: txTime
        )
      )
    )
    expectNoDifference(omittedFieldsUpdate.map(\.count), [4, 4], source)
    expectNoDifference(
      stepSummary(omittedFieldsUpdate).sorted { $0.joined(separator: "|") < $1.joined(separator: "|") },
      [
        ["add-triple", "user-1", "users/handle", "bobby", ""],
        ["add-triple", "user-1", "users/id", "user-1", ""],
      ],
      source
    )
    expectNoDifference(
      omittedFieldsUpdate.compactMap { $0[safe: 2] as? String }.contains("users/fullName"),
      false,
      source
    )

    let ignoredPayloadID = try txSteps(
      for: InstantStoreTransaction(
        id: "tx-instaml-ignored-id-attr",
        operations: InstantInstamlTransform.updateOperations(
          namespace: "books",
          entityID: "book-1",
          fields: [
            "id": .some(.string("ploop")),
            "title": .some(.string("New Title")),
          ],
          txID: "tx-instaml-ignored-id-attr",
          txTime: txTime
        )
      )
    )
    expectNoDifference(ignoredPayloadID.map(\.count), [4, 4], source)
    expectNoDifference(
      stepSummary(ignoredPayloadID).sorted { $0.joined(separator: "|") < $1.joined(separator: "|") },
      [
        ["add-triple", "book-1", "books/id", "book-1", ""],
        ["add-triple", "book-1", "books/title", "New Title", ""],
      ],
      source
    )
    expectNoDifference(
      stepSummary(ignoredPayloadID).flatMap { $0 }.contains("ploop"),
      false,
      source
    )
  }

  @Test
  func transportMutationPortsInstamlOptimisticUnknownAttrTransform() async throws {
    let cacheURL = try temporaryCacheURL()
    let txTime = InstantTimestamp(milliseconds: 1_700_000_000_000)
    let source =
      "upstream/instant/client/packages/core/__tests__/src/instaml.test.ts "
      + "optimistically adds attrs if they don't exist "
      + "[adapted: Swift keeps namespace-prefixed unknown attrs as triples instead of emitting add-attr txSteps.]"
    let transaction = InstantStoreTransaction(
      id: "tx-instaml-optimistic-unknown-attr",
      operations: InstantInstamlTransform.updateOperations(
        namespace: "books",
        entityID: "book-unknown-attr",
        fields: ["newAttr": .some(.string("New Title"))],
        txID: "tx-instaml-optimistic-unknown-attr",
        txTime: txTime
      )
    )
    let mutation = InstantTransportMutation(
      PendingMutation(id: transaction.id, createdAt: txTime, transaction: transaction)
    )
    expectNoDifference(mutation.preconditions, [], source)
    expectNoDifference(mutation.txSteps.count, 2, source)

    let data = try JSONEncoder().encode(mutation)
    let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    let txSteps = try #require(object["txSteps"] as? [[Any]])
    expectNoDifference(txSteps.map(\.count), [4, 4], source)
    expectNoDifference(
      txSteps.sorted { ($0[safe: 2] as? String ?? "") < ($1[safe: 2] as? String ?? "") }
        .map {
          [
            $0[safe: 0] as? String ?? "",
            $0[safe: 1] as? String ?? "",
            $0[safe: 2] as? String ?? "",
            $0[safe: 3] as? String ?? "",
          ]
        },
      [
        ["add-triple", "book-unknown-attr", "books/id", "book-unknown-attr"],
        ["add-triple", "book-unknown-attr", "books/newAttr", "New Title"],
      ],
      source
    )

    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "test-app",
        persistenceURL: cacheURL,
        initialAttributes: []
      )
    )
    let result = try await runtime.transact(transaction, createdAt: txTime)
    let snapshot = await runtime.store.snapshot()
    expectNoDifference(result.changedEntityIDs, ["book-unknown-attr"], source)
    expectNoDifference(result.tripleCount, 2, source)
    expectNoDifference(
      snapshot.triples,
      [
        InstantTriple(
          entityID: "book-unknown-attr",
          attributeID: "books/id",
          value: .string("book-unknown-attr"),
          txID: "tx-instaml-optimistic-unknown-attr",
          txTime: txTime
        ),
        InstantTriple(
          entityID: "book-unknown-attr",
          attributeID: "books/newAttr",
          value: .string("New Title"),
          txID: "tx-instaml-optimistic-unknown-attr",
          txTime: txTime
        ),
      ],
      source
    )
  }

  @Test
  func transportMutationPortsInstamlLookupResolvedUpdateTransform() throws {
    let txTime = InstantTimestamp(milliseconds: 1_700_000_000_000)
    let source =
      "upstream/instant/client/packages/core/__tests__/src/instaml.test.ts lookup resolves attr ids "
      + "[adapted: Swift lookup refs use declared attribute ids in lookup-shaped txSteps.]"
    let lookup = InstantLookupRef(
      attributeID: "users/email",
      value: .string("stopa@instantdb.com")
    )
    let transaction = InstantStoreTransaction(
      id: "tx-instaml-lookup-resolves-attrs",
      operations: InstantInstamlTransform.updateOperations(
        namespace: "users",
        entityLookup: lookup,
        fields: ["handle": .some(.string("stopa"))],
        txID: "tx-instaml-lookup-resolves-attrs",
        txTime: txTime
      )
    )
    let mutation = InstantTransportMutation(
      PendingMutation(id: transaction.id, createdAt: txTime, transaction: transaction)
    )
    expectNoDifference(mutation.preconditions, [], source)
    expectNoDifference(mutation.txSteps.count, 2, source)

    let data = try JSONEncoder().encode(mutation)
    let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    let txSteps = try #require(object["txSteps"] as? [[Any]])
    expectNoDifference(txSteps.map(\.count), [4, 4], source)
    expectNoDifference(txSteps.map { $0.first as? String }, ["add-triple", "add-triple"], source)

    let handleStep = try #require(txSteps.first { $0[safe: 2] as? String == "users/handle" })
    let handleEntity = try #require(handleStep[safe: 1] as? [Any])
    expectNoDifference(handleEntity.count, 2, source)
    expectNoDifference(handleEntity[0] as? String, "users/email", source)
    expectNoDifference(handleEntity[1] as? String, "stopa@instantdb.com", source)
    expectNoDifference(handleStep[safe: 3] as? String, "stopa", source)

    let idStep = try #require(txSteps.first { $0[safe: 2] as? String == "users/id" })
    let idEntity = try #require(idStep[safe: 1] as? [Any])
    expectNoDifference(idEntity.count, 2, source)
    expectNoDifference(idEntity[0] as? String, "users/email", source)
    expectNoDifference(idEntity[1] as? String, "stopa@instantdb.com", source)
    let idValue = try #require(idStep[safe: 3] as? [Any])
    expectNoDifference(idValue.count, 2, source)
    expectNoDifference(idValue[0] as? String, "users/email", source)
    expectNoDifference(idValue[1] as? String, "stopa@instantdb.com", source)
  }

  @Test
  func transportMutationPortsInstamlCustomLookupUpdateTransform() throws {
    let txTime = InstantTimestamp(milliseconds: 1_700_000_000_000)
    let source =
      "upstream/instant/client/packages/core/__tests__/src/instaml.test.ts "
      + "lookup creates unique attrs for custom lookups "
      + "[adapted: Swift preserves explicit lookup attr ids instead of emitting add-attr txSteps.]"
    let lookup = InstantLookupRef(
      attributeID: "users/newAttr",
      value: .string("newAttrValue")
    )
    let transaction = InstantStoreTransaction(
      id: "tx-instaml-custom-lookup",
      operations: InstantInstamlTransform.updateOperations(
        namespace: "users",
        entityLookup: lookup,
        fields: ["handle": .some(.string("stopa"))],
        txID: "tx-instaml-custom-lookup",
        txTime: txTime
      )
    )
    let mutation = InstantTransportMutation(
      PendingMutation(id: transaction.id, createdAt: txTime, transaction: transaction)
    )
    expectNoDifference(mutation.preconditions, [], source)
    expectNoDifference(mutation.txSteps.count, 2, source)

    let data = try JSONEncoder().encode(mutation)
    let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    let txSteps = try #require(object["txSteps"] as? [[Any]])
    expectNoDifference(txSteps.map(\.count), [4, 4], source)
    expectNoDifference(txSteps.map { $0.first as? String }, ["add-triple", "add-triple"], source)

    let handleStep = try #require(txSteps.first { $0[safe: 2] as? String == "users/handle" })
    let handleEntity = try #require(handleStep[safe: 1] as? [Any])
    expectNoDifference(handleEntity.count, 2, source)
    expectNoDifference(handleEntity[0] as? String, "users/newAttr", source)
    expectNoDifference(handleEntity[1] as? String, "newAttrValue", source)
    expectNoDifference(handleStep[safe: 3] as? String, "stopa", source)

    let idStep = try #require(txSteps.first { $0[safe: 2] as? String == "users/id" })
    let idEntity = try #require(idStep[safe: 1] as? [Any])
    expectNoDifference(idEntity.count, 2, source)
    expectNoDifference(idEntity[0] as? String, "users/newAttr", source)
    expectNoDifference(idEntity[1] as? String, "newAttrValue", source)
    let idValue = try #require(idStep[safe: 3] as? [Any])
    expectNoDifference(idValue.count, 2, source)
    expectNoDifference(idValue[0] as? String, "users/newAttr", source)
    expectNoDifference(idValue[1] as? String, "newAttrValue", source)
  }

  @Test
  func transportMutationPortsInstamlLookupLinkValueTransform() throws {
    let txTime = InstantTimestamp(milliseconds: 1_700_000_000_000)
    let source =
      "upstream/instant/client/packages/core/__tests__/src/instaml.test.ts "
      + "lookup creates unique attrs for lookups in link values "
      + "[adapted: Swift preserves lookup link values with declared attr ids instead of emitting add-attr txSteps.]"
    let postLookup = InstantLookupRef(
      attributeID: "posts/slug",
      value: .string("life-is-good")
    )
    let transaction = InstantStoreTransaction(
      id: "tx-instaml-lookup-link-value",
      operations: InstantInstamlTransform.updateOperations(
        namespace: "users",
        entityID: "user-lookup-link",
        fields: [:],
        txID: "tx-instaml-lookup-link-value",
        txTime: txTime
      )
      + [
        .insert(
          InstantTriple(
            entityID: "user-lookup-link",
            attributeID: "users/posts",
            value: .lookupRef(postLookup),
            txID: "tx-instaml-lookup-link-value",
            txTime: txTime
          )
        )
      ]
    )
    let mutation = InstantTransportMutation(
      PendingMutation(id: transaction.id, createdAt: txTime, transaction: transaction)
    )
    expectNoDifference(mutation.preconditions, [], source)
    expectNoDifference(mutation.txSteps.count, 2, source)

    let data = try JSONEncoder().encode(mutation)
    let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    let txSteps = try #require(object["txSteps"] as? [[Any]])
    expectNoDifference(txSteps.map(\.count), [4, 4], source)
    expectNoDifference(txSteps.map { $0.first as? String }, ["add-triple", "add-triple"], source)

    let idStep = try #require(txSteps.first { $0[safe: 2] as? String == "users/id" })
    expectNoDifference(idStep[safe: 1] as? String, "user-lookup-link", source)
    expectNoDifference(idStep[safe: 3] as? String, "user-lookup-link", source)

    let linkStep = try #require(txSteps.first { $0[safe: 2] as? String == "users/posts" })
    expectNoDifference(linkStep[safe: 1] as? String, "user-lookup-link", source)
    let linkValue = try #require(linkStep[safe: 3] as? [Any])
    expectNoDifference(linkValue.count, 2, source)
    expectNoDifference(linkValue[0] as? String, "posts/slug", source)
    expectNoDifference(linkValue[1] as? String, "life-is-good", source)
  }

  @Test
  func transportMutationPortsInstamlLookupLinkExistingForwardIdentity() async throws {
    let txTime = InstantTimestamp(milliseconds: 1_700_000_000_000)
    let source =
      "upstream/instant/client/packages/core/__tests__/src/instaml.test.ts "
      + "lookup creates unique attrs for lookups in link values when fwd-ident exists "
      + "[adapted: Swift writes through the declared forward relation attr id.]"
    let declaredAttributes = [
      InstantAttribute(
        id: "users/posts",
        namespace: "users",
        name: "posts",
        valueType: .ref,
        isRequired: false,
        cardinality: .one,
        isIndexed: true,
        isUnique: true,
        forwardIdentity: "users/posts",
        reverseIdentity: "posts/users",
        linkNamespace: "posts"
      ),
      InstantAttribute(
        id: "posts/slug",
        namespace: "posts",
        name: "slug",
        valueType: .string,
        isRequired: false,
        isIndexed: true,
        isUnique: true
      ),
    ]
    let seedTriples = [
      InstantTriple(
        entityID: "post-forward-link",
        attributeID: "posts/id",
        value: .string("post-forward-link"),
        txID: "seed-instaml-forward-link",
        txTime: txTime
      ),
      InstantTriple(
        entityID: "post-forward-link",
        attributeID: "posts/slug",
        value: .string("life-is-good"),
        txID: "seed-instaml-forward-link",
        txTime: txTime
      ),
    ]
    let postLookup = InstantLookupRef(
      attributeID: "posts/slug",
      value: .string("life-is-good")
    )
    let transaction = InstantStoreTransaction(
      id: "tx-instaml-forward-lookup-link",
      operations: InstantInstamlTransform.updateOperations(
        namespace: "users",
        entityID: "user-forward-link",
        fields: [:],
        txID: "tx-instaml-forward-lookup-link",
        txTime: txTime
      )
      + [
        .insert(
          InstantTriple(
            entityID: "user-forward-link",
            attributeID: "users/posts",
            value: .lookupRef(postLookup),
            txID: "tx-instaml-forward-lookup-link",
            txTime: txTime
          )
        )
      ]
    )
    let mutation = InstantTransportMutation(
      PendingMutation(id: transaction.id, createdAt: txTime, transaction: transaction)
    )
    expectNoDifference(
      mutation.txSteps,
      [
        .addTriple(
          entity: .id("user-forward-link"),
          attributeID: "users/id",
          value: .string("user-forward-link")
        ),
        .addTriple(
          entity: .id("user-forward-link"),
          attributeID: "users/posts",
          value: .lookupRef(attributeID: "posts/slug", value: .string("life-is-good"))
        ),
      ],
      source
    )

    let store = InstantStore(
      snapshot: InstantStoreSnapshot(attributes: declaredAttributes, triples: seedTriples)
    )
    let prepared = try await store.prepare(transaction)
    expectNoDifference(
      prepared.snapshot.attributes.map(\.id),
      ["posts/id", "posts/slug", "users/id", "users/posts"],
      source
    )
    expectNoDifference(
      prepared.snapshot.attributes.first { $0.id == "users/posts" },
      declaredAttributes[0],
      source
    )
    expectNoDifference(
      prepared.result.changedEntityIDs,
      ["post-forward-link", "user-forward-link"],
      source
    )
    expectNoDifference(
      prepared.snapshot.triples,
      seedTriples
        + [
          InstantTriple(
            entityID: "user-forward-link",
            attributeID: "users/id",
            value: .string("user-forward-link"),
            txID: "tx-instaml-forward-lookup-link",
            txTime: txTime
          ),
          InstantTriple(
            entityID: "user-forward-link",
            attributeID: "users/posts",
            value: .ref("post-forward-link"),
            txID: "tx-instaml-forward-lookup-link",
            txTime: txTime
          ),
        ],
      source
    )
  }

  @Test
  func transportMutationPortsInstamlLookupLinkExistingReverseIdentity() async throws {
    let txTime = InstantTimestamp(milliseconds: 1_700_000_000_000)
    let source =
      "upstream/instant/client/packages/core/__tests__/src/instaml.test.ts "
      + "lookup creates unique attrs for lookups in link values when rev-ident exists "
      + "[adapted: Swift lowers the reverse field through the declared forward relation attr id.]"
    let declaredAttributes = [
      InstantAttribute.primaryKey(namespace: "users"),
      InstantAttribute(
        id: "posts/users",
        namespace: "posts",
        name: "users",
        valueType: .ref,
        isRequired: false,
        cardinality: .one,
        isIndexed: true,
        isUnique: true,
        forwardIdentity: "posts/users",
        reverseIdentity: "users/posts",
        linkNamespace: "users"
      ),
      InstantAttribute(
        id: "posts/slug",
        namespace: "posts",
        name: "slug",
        valueType: .string,
        isRequired: false,
        isIndexed: true,
        isUnique: true
      ),
    ]
    let seedTriples = [
      InstantTriple(
        entityID: "post-reverse-link",
        attributeID: "posts/id",
        value: .string("post-reverse-link"),
        txID: "seed-instaml-reverse-link",
        txTime: txTime
      ),
      InstantTriple(
        entityID: "post-reverse-link",
        attributeID: "posts/slug",
        value: .string("life-is-good"),
        txID: "seed-instaml-reverse-link",
        txTime: txTime
      ),
    ]
    let postLookup = InstantLookupRef(
      attributeID: "posts/slug",
      value: .string("life-is-good")
    )
    let transaction = InstantStoreTransaction(
      id: "tx-instaml-reverse-lookup-link",
      operations: InstantInstamlTransform.updateOperations(
        namespace: "users",
        entityID: "user-reverse-link",
        fields: [:],
        txID: "tx-instaml-reverse-lookup-link",
        txTime: txTime
      )
      + [
        .insertByLookup(
          entity: postLookup,
          attributeID: "posts/users",
          value: .ref("user-reverse-link"),
          txID: "tx-instaml-reverse-lookup-link",
          txTime: txTime
        )
      ]
    )
    let mutation = InstantTransportMutation(
      PendingMutation(id: transaction.id, createdAt: txTime, transaction: transaction)
    )
    expectNoDifference(
      mutation.txSteps,
      [
        .addTriple(
          entity: .id("user-reverse-link"),
          attributeID: "users/id",
          value: .string("user-reverse-link")
        ),
        .addTriple(
          entity: .lookup(postLookup),
          attributeID: "posts/users",
          value: .string("user-reverse-link")
        ),
      ],
      source
    )

    let data = try JSONEncoder().encode(mutation)
    let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    let txSteps = try #require(object["txSteps"] as? [[Any]])
    let reverseStep = try #require(txSteps.first { $0[safe: 2] as? String == "posts/users" })
    let reverseEntity = try #require(reverseStep[safe: 1] as? [Any])
    expectNoDifference(reverseEntity.count, 2, source)
    expectNoDifference(reverseEntity[0] as? String, "posts/slug", source)
    expectNoDifference(reverseEntity[1] as? String, "life-is-good", source)
    expectNoDifference(reverseStep[safe: 3] as? String, "user-reverse-link", source)

    let store = InstantStore(
      snapshot: InstantStoreSnapshot(attributes: declaredAttributes, triples: seedTriples)
    )
    let prepared = try await store.prepare(transaction)
    expectNoDifference(
      prepared.snapshot.attributes.map(\.id),
      ["posts/id", "posts/slug", "posts/users", "users/id"],
      source
    )
    expectNoDifference(
      prepared.snapshot.attributes.first { $0.id == "posts/users" },
      declaredAttributes[1],
      source
    )
    expectNoDifference(
      prepared.result.changedEntityIDs,
      ["post-reverse-link", "user-reverse-link"],
      source
    )
    expectNoDifference(
      prepared.snapshot.triples,
      seedTriples
        + [
          InstantTriple(
            entityID: "post-reverse-link",
            attributeID: "posts/users",
            value: .ref("user-reverse-link"),
            txID: "tx-instaml-reverse-lookup-link",
            txTime: txTime
          ),
          InstantTriple(
            entityID: "user-reverse-link",
            attributeID: "users/id",
            value: .string("user-reverse-link"),
            txID: "tx-instaml-reverse-lookup-link",
            txTime: txTime
          ),
        ],
      source
    )
  }

  @Test
  func transportMutationPortsInstamlDeclaredLookupLinkAttrsDoNotOverride() async throws {
    let txTime = InstantTimestamp(milliseconds: 1_700_000_000_000)
    let source =
      "upstream/instant/client/packages/core/__tests__/src/instaml.test.ts "
      + "lookup doesn't override attrs for lookups in link values "
      + "[adapted: Swift writes declared attr ids directly and keeps the local schema fixed.]"
    let declaredAttributes = [
      InstantAttribute(
        id: "users/posts",
        namespace: "users",
        name: "posts",
        valueType: .ref,
        isRequired: false,
        cardinality: .one,
        isIndexed: true,
        isUnique: true,
        forwardIdentity: "users/posts",
        reverseIdentity: "posts/users",
        linkNamespace: "posts"
      ),
      InstantAttribute(
        id: "posts/slug",
        namespace: "posts",
        name: "slug",
        valueType: .string,
        isRequired: false,
        isIndexed: true,
        isUnique: true
      ),
    ]
    let postLookup = InstantLookupRef(
      attributeID: "posts/slug",
      value: .string("life-is-good")
    )
    let transaction = InstantStoreTransaction(
      id: "tx-instaml-declared-lookup-link",
      operations: InstantInstamlTransform.updateOperations(
        namespace: "users",
        entityID: "user-declared-link",
        fields: [:],
        txID: "tx-instaml-declared-lookup-link",
        txTime: txTime
      )
      + [
        .insert(
          InstantTriple(
            entityID: "user-declared-link",
            attributeID: "users/posts",
            value: .lookupRef(postLookup),
            txID: "tx-instaml-declared-lookup-link",
            txTime: txTime
          )
        )
      ]
    )
    let mutation = InstantTransportMutation(
      PendingMutation(id: transaction.id, createdAt: txTime, transaction: transaction)
    )
    expectNoDifference(mutation.preconditions, [], source)
    expectNoDifference(
      mutation.txSteps,
      [
        .addTriple(
          entity: .id("user-declared-link"),
          attributeID: "users/id",
          value: .string("user-declared-link")
        ),
        .addTriple(
          entity: .id("user-declared-link"),
          attributeID: "users/posts",
          value: .lookupRef(attributeID: "posts/slug", value: .string("life-is-good"))
        ),
      ],
      source
    )

    let data = try JSONEncoder().encode(mutation)
    let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    let txSteps = try #require(object["txSteps"] as? [[Any]])
    expectNoDifference(txSteps.map(\.count), [4, 4], source)
    expectNoDifference(txSteps.map { $0.first as? String }, ["add-triple", "add-triple"], source)
    expectNoDifference(txSteps.compactMap { $0[safe: 2] as? String }, ["users/id", "users/posts"], source)
    let linkValue = try #require(txSteps[1][safe: 3] as? [Any])
    expectNoDifference(linkValue.count, 2, source)
    expectNoDifference(linkValue[0] as? String, "posts/slug", source)
    expectNoDifference(linkValue[1] as? String, "life-is-good", source)

    let store = InstantStore(snapshot: InstantStoreSnapshot(attributes: declaredAttributes))
    let prepared = try await store.prepare(transaction)
    expectNoDifference(
      prepared.snapshot.attributes.map(\.id),
      ["posts/id", "posts/slug", "users/id", "users/posts"],
      source
    )
    expectNoDifference(
      prepared.snapshot.attributes.first { $0.id == "users/posts" },
      declaredAttributes[0],
      source
    )
    expectNoDifference(
      prepared.snapshot.attributes.first { $0.id == "posts/slug" },
      declaredAttributes[1],
      source
    )
    expectNoDifference(prepared.result.changedEntityIDs, ["user-declared-link"], source)
    expectNoDifference(
      prepared.snapshot.triples,
      [
        InstantTriple(
          entityID: "user-declared-link",
          attributeID: "users/id",
          value: .string("user-declared-link"),
          txID: "tx-instaml-declared-lookup-link",
          txTime: txTime
        )
      ],
      source
    )
  }

  @Test
  func transportMutationPortsInstamlLookupSelfLinksDoNotOverrideAttrs() async throws {
    let txTime = InstantTimestamp(milliseconds: 1_700_000_000_000)
    let source =
      "upstream/instant/client/packages/core/__tests__/src/instaml.test.ts "
      + "lookup doesn't override attrs for lookups in self links "
      + "[adapted: Swift writes concrete attr ids, so reverse child links write the declared forward attr from child to parent.]"
    let declaredAttributes = [
      InstantAttribute(
        id: "posts/slug",
        namespace: "posts",
        name: "slug",
        valueType: .string,
        isRequired: false,
        isIndexed: true,
        isUnique: true
      ),
      InstantAttribute(
        id: "posts/parent",
        namespace: "posts",
        name: "parent",
        valueType: .ref,
        isRequired: false,
        cardinality: .one,
        isIndexed: true,
        isUnique: true,
        forwardIdentity: "posts/parent",
        reverseIdentity: "posts/child",
        linkNamespace: "posts"
      ),
    ]
    let seedTriples = [
      InstantTriple(
        entityID: "post-self-link",
        attributeID: "posts/slug",
        value: .string("life-is-good"),
        txID: "seed-instaml-self-link",
        txTime: txTime
      ),
      InstantTriple(
        entityID: "post-child-link",
        attributeID: "posts/slug",
        value: .string("check-this-out"),
        txID: "seed-instaml-self-link",
        txTime: txTime
      ),
    ]
    let postLookup = InstantLookupRef(
      attributeID: "posts/slug",
      value: .string("life-is-good")
    )
    let childLookup = InstantLookupRef(
      attributeID: "posts/slug",
      value: .string("check-this-out")
    )
    let parentTransaction = InstantStoreTransaction(
      id: "tx-instaml-self-parent-link",
      operations: InstantInstamlTransform.updateOperations(
        namespace: "posts",
        entityLookup: postLookup,
        fields: [:],
        txID: "tx-instaml-self-parent-link",
        txTime: txTime
      )
      + [
        .insertByLookup(
          entity: postLookup,
          attributeID: "posts/parent",
          value: .lookupRef(postLookup),
          txID: "tx-instaml-self-parent-link",
          txTime: txTime
        )
      ]
    )
    let parentMutation = InstantTransportMutation(
      PendingMutation(id: parentTransaction.id, createdAt: txTime, transaction: parentTransaction)
    )
    expectNoDifference(parentMutation.preconditions, [], source)
    expectNoDifference(
      parentMutation.txSteps,
      [
        .addTriple(
          entity: .lookup(postLookup),
          attributeID: "posts/id",
          value: .lookupRef(attributeID: "posts/slug", value: .string("life-is-good"))
        ),
        .addTriple(
          entity: .lookup(postLookup),
          attributeID: "posts/parent",
          value: .lookupRef(attributeID: "posts/slug", value: .string("life-is-good"))
        ),
      ],
      source
    )

    let parentData = try JSONEncoder().encode(parentMutation)
    let parentObject = try #require(JSONSerialization.jsonObject(with: parentData) as? [String: Any])
    let parentTxSteps = try #require(parentObject["txSteps"] as? [[Any]])
    expectNoDifference(parentTxSteps.map { $0.first as? String }, ["add-triple", "add-triple"], source)

    let parentStore = InstantStore(
      snapshot: InstantStoreSnapshot(attributes: declaredAttributes, triples: seedTriples)
    )
    let preparedParent = try await parentStore.prepare(parentTransaction)
    expectNoDifference(
      preparedParent.snapshot.attributes.map(\.id),
      ["posts/id", "posts/parent", "posts/slug"],
      source
    )
    expectNoDifference(
      preparedParent.snapshot.attributes.first { $0.id == "posts/parent" },
      declaredAttributes[1],
      source
    )
    expectNoDifference(preparedParent.result.changedEntityIDs, ["post-self-link"], source)
    expectNoDifference(
      preparedParent.snapshot.triples,
      [
        InstantTriple(
          entityID: "post-child-link",
          attributeID: "posts/slug",
          value: .string("check-this-out"),
          txID: "seed-instaml-self-link",
          txTime: txTime
        ),
        InstantTriple(
          entityID: "post-self-link",
          attributeID: "posts/id",
          value: .string("post-self-link"),
          txID: "tx-instaml-self-parent-link",
          txTime: txTime
        ),
        InstantTriple(
          entityID: "post-self-link",
          attributeID: "posts/parent",
          value: .ref("post-self-link"),
          txID: "tx-instaml-self-parent-link",
          txTime: txTime
        ),
        InstantTriple(
          entityID: "post-self-link",
          attributeID: "posts/slug",
          value: .string("life-is-good"),
          txID: "seed-instaml-self-link",
          txTime: txTime
        ),
      ],
      source
    )

    let childTransaction = InstantStoreTransaction(
      id: "tx-instaml-self-child-link",
      operations: InstantInstamlTransform.updateOperations(
        namespace: "posts",
        entityLookup: postLookup,
        fields: [:],
        txID: "tx-instaml-self-child-link",
        txTime: txTime
      )
      + [
        .insertByLookup(
          entity: childLookup,
          attributeID: "posts/parent",
          value: .lookupRef(postLookup),
          txID: "tx-instaml-self-child-link",
          txTime: txTime
        )
      ]
    )
    let childMutation = InstantTransportMutation(
      PendingMutation(id: childTransaction.id, createdAt: txTime, transaction: childTransaction)
    )
    expectNoDifference(childMutation.preconditions, [], source)
    expectNoDifference(
      childMutation.txSteps,
      [
        .addTriple(
          entity: .lookup(postLookup),
          attributeID: "posts/id",
          value: .lookupRef(attributeID: "posts/slug", value: .string("life-is-good"))
        ),
        .addTriple(
          entity: .lookup(childLookup),
          attributeID: "posts/parent",
          value: .lookupRef(attributeID: "posts/slug", value: .string("life-is-good"))
        ),
      ],
      source
    )

    let childData = try JSONEncoder().encode(childMutation)
    let childObject = try #require(JSONSerialization.jsonObject(with: childData) as? [String: Any])
    let childTxSteps = try #require(childObject["txSteps"] as? [[Any]])
    expectNoDifference(childTxSteps.map { $0.first as? String }, ["add-triple", "add-triple"], source)

    let childStore = InstantStore(
      snapshot: InstantStoreSnapshot(attributes: declaredAttributes, triples: seedTriples)
    )
    let preparedChild = try await childStore.prepare(childTransaction)
    expectNoDifference(
      preparedChild.snapshot.attributes.map(\.id),
      ["posts/id", "posts/parent", "posts/slug"],
      source
    )
    expectNoDifference(
      preparedChild.snapshot.attributes.first { $0.id == "posts/parent" },
      declaredAttributes[1],
      source
    )
    expectNoDifference(
      preparedChild.result.changedEntityIDs,
      ["post-child-link", "post-self-link"],
      source
    )
    expectNoDifference(
      preparedChild.snapshot.triples,
      [
        InstantTriple(
          entityID: "post-child-link",
          attributeID: "posts/parent",
          value: .ref("post-self-link"),
          txID: "tx-instaml-self-child-link",
          txTime: txTime
        ),
        InstantTriple(
          entityID: "post-child-link",
          attributeID: "posts/slug",
          value: .string("check-this-out"),
          txID: "seed-instaml-self-link",
          txTime: txTime
        ),
        InstantTriple(
          entityID: "post-self-link",
          attributeID: "posts/id",
          value: .string("post-self-link"),
          txID: "tx-instaml-self-child-link",
          txTime: txTime
        ),
        InstantTriple(
          entityID: "post-self-link",
          attributeID: "posts/slug",
          value: .string("life-is-good"),
          txID: "seed-instaml-self-link",
          txTime: txTime
        ),
      ],
      source
    )
  }

  @Test
  func transportMutationPortsInstamlRefLookupUpdateTransform() async throws {
    let txTime = InstantTimestamp(milliseconds: 1_700_000_000_000)
    let source =
      "upstream/instant/client/packages/core/__tests__/src/instaml.test.ts "
      + "lookup creates unique ref attrs for ref lookup "
      + "[adapted: Swift writes declared ref lookup attr ids instead of add-attr txSteps.]"
    let userPrefsByUserLookup = InstantLookupRef(
      attributeID: "user_prefs/users",
      value: .ref("user-1")
    )
    let transaction = InstantStoreTransaction(
      id: "tx-instaml-ref-lookup",
      operations: InstantInstamlTransform.updateOperations(
        namespace: "users",
        entityID: "user-1",
        fields: [:],
        txID: "tx-instaml-ref-lookup",
        txTime: txTime
      )
      + InstantInstamlTransform.updateOperations(
        namespace: "user_prefs",
        entityLookup: userPrefsByUserLookup,
        fields: [:],
        txID: "tx-instaml-ref-lookup",
        txTime: txTime
      )
    )
    let mutation = InstantTransportMutation(
      PendingMutation(id: transaction.id, createdAt: txTime, transaction: transaction)
    )
    expectNoDifference(mutation.preconditions, [], source)
    expectNoDifference(
      mutation.txSteps,
      [
        .addTriple(entity: .id("user-1"), attributeID: "users/id", value: .string("user-1")),
        .addTriple(
          entity: .lookup(userPrefsByUserLookup),
          attributeID: "user_prefs/id",
          value: .lookupRef(attributeID: "user_prefs/users", value: .string("user-1"))
        ),
      ],
      source
    )

    let data = try JSONEncoder().encode(mutation)
    let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    let txSteps = try #require(object["txSteps"] as? [[Any]])
    expectNoDifference(txSteps.map(\.count), [4, 4], source)
    let lookupEntity = try #require(txSteps[1][safe: 1] as? [Any])
    expectNoDifference(lookupEntity.count, 2, source)
    expectNoDifference(lookupEntity[0] as? String, "user_prefs/users", source)
    expectNoDifference(lookupEntity[1] as? String, "user-1", source)
    let lookupValue = try #require(txSteps[1][safe: 3] as? [Any])
    expectNoDifference(lookupValue.count, 2, source)
    expectNoDifference(lookupValue[0] as? String, "user_prefs/users", source)
    expectNoDifference(lookupValue[1] as? String, "user-1", source)

    let declaredAttributes = [
      InstantAttribute.primaryKey(namespace: "users"),
      InstantAttribute.primaryKey(namespace: "user_prefs"),
      InstantAttribute(
        id: "user_prefs/users",
        namespace: "user_prefs",
        name: "users",
        valueType: .ref,
        isRequired: false,
        cardinality: .one,
        isIndexed: true,
        isUnique: true,
        forwardIdentity: "user_prefs/users",
        reverseIdentity: "users/user_prefs",
        linkNamespace: "users"
      ),
    ]
    let seedTriples = [
      InstantTriple(
        entityID: "user-1",
        attributeID: "users/id",
        value: .string("user-1"),
        txID: "seed-instaml-ref-lookup",
        txTime: txTime
      ),
      InstantTriple(
        entityID: "user_pref-1",
        attributeID: "user_prefs/users",
        value: .ref("user-1"),
        txID: "seed-instaml-ref-lookup",
        txTime: txTime
      ),
    ]
    let localTransaction = InstantStoreTransaction(
      id: "tx-instaml-ref-lookup-local",
      operations: [
        .insertByLookup(
          entity: userPrefsByUserLookup,
          attributeID: "user_prefs/id",
          value: .lookupRef(userPrefsByUserLookup),
          txID: "tx-instaml-ref-lookup-local",
          txTime: txTime
        )
      ]
    )
    let store = InstantStore(
      snapshot: InstantStoreSnapshot(attributes: declaredAttributes, triples: seedTriples)
    )
    let prepared = try await store.prepare(localTransaction)
    expectNoDifference(
      prepared.snapshot.attributes.map(\.id),
      ["user_prefs/id", "user_prefs/users", "users/id"],
      source
    )
    expectNoDifference(
      prepared.snapshot.attributes.first { $0.id == "user_prefs/users" },
      declaredAttributes[2],
      source
    )
    expectNoDifference(prepared.result.changedEntityIDs, ["user_pref-1"], source)
    expectNoDifference(
      prepared.snapshot.triples,
      [
        InstantTriple(
          entityID: "user-1",
          attributeID: "users/id",
          value: .string("user-1"),
          txID: "seed-instaml-ref-lookup",
          txTime: txTime
        ),
        InstantTriple(
          entityID: "user_pref-1",
          attributeID: "user_prefs/id",
          value: .string("user_pref-1"),
          txID: "tx-instaml-ref-lookup-local",
          txTime: txTime
        ),
        InstantTriple(
          entityID: "user_pref-1",
          attributeID: "user_prefs/users",
          value: .ref("user-1"),
          txID: "seed-instaml-ref-lookup",
          txTime: txTime
        ),
      ],
      source
    )
  }

  @Test
  func transportMutationPortsInstamlRefLookupInLinkValueTransform() async throws {
    let txTime = InstantTimestamp(milliseconds: 1_700_000_000_000)
    let source =
      "upstream/instant/client/packages/core/__tests__/src/instaml.test.ts "
      + "lookup creates unique ref attrs for ref lookup in link value "
      + "[adapted: Swift writes declared relation attr ids and preserves the ref lookup link value.]"
    let userPrefByUserLookup = InstantLookupRef(
      attributeID: "user_prefs/users",
      value: .ref("user-1")
    )
    let transaction = InstantStoreTransaction(
      id: "tx-instaml-ref-lookup-link-value",
      operations: InstantInstamlTransform.updateOperations(
        namespace: "users",
        entityID: "user-1",
        fields: [:],
        txID: "tx-instaml-ref-lookup-link-value",
        txTime: txTime
      )
      + [
        .insert(
          InstantTriple(
            entityID: "user-1",
            attributeID: "users/user_prefs",
            value: .lookupRef(userPrefByUserLookup),
            txID: "tx-instaml-ref-lookup-link-value",
            txTime: txTime
          )
        )
      ]
    )
    let mutation = InstantTransportMutation(
      PendingMutation(id: transaction.id, createdAt: txTime, transaction: transaction)
    )
    expectNoDifference(mutation.preconditions, [], source)
    expectNoDifference(
      mutation.txSteps,
      [
        .addTriple(entity: .id("user-1"), attributeID: "users/id", value: .string("user-1")),
        .addTriple(
          entity: .id("user-1"),
          attributeID: "users/user_prefs",
          value: .lookupRef(attributeID: "user_prefs/users", value: .string("user-1"))
        ),
      ],
      source
    )

    let data = try JSONEncoder().encode(mutation)
    let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    let txSteps = try #require(object["txSteps"] as? [[Any]])
    expectNoDifference(txSteps.map(\.count), [4, 4], source)
    expectNoDifference(txSteps[1][safe: 1] as? String, "user-1", source)
    expectNoDifference(txSteps[1][safe: 2] as? String, "users/user_prefs", source)
    let lookupValue = try #require(txSteps[1][safe: 3] as? [Any])
    expectNoDifference(lookupValue.count, 2, source)
    expectNoDifference(lookupValue[0] as? String, "user_prefs/users", source)
    expectNoDifference(lookupValue[1] as? String, "user-1", source)

    let declaredAttributes = [
      InstantAttribute.primaryKey(namespace: "users"),
      InstantAttribute.primaryKey(namespace: "user_prefs"),
      InstantAttribute(
        id: "users/user_prefs",
        namespace: "users",
        name: "user_prefs",
        valueType: .ref,
        isRequired: false,
        cardinality: .one,
        isIndexed: true,
        isUnique: true,
        forwardIdentity: "users/user_prefs",
        reverseIdentity: "user_prefs/users",
        linkNamespace: "user_prefs"
      ),
    ]
    let seedTriples = [
      InstantTriple(
        entityID: "user-1",
        attributeID: "users/user_prefs",
        value: .ref("user_pref-1"),
        txID: "seed-instaml-ref-lookup-link-value",
        txTime: txTime
      ),
      InstantTriple(
        entityID: "user_pref-1",
        attributeID: "user_prefs/id",
        value: .string("user_pref-1"),
        txID: "seed-instaml-ref-lookup-link-value",
        txTime: txTime
      ),
    ]
    let store = InstantStore(
      snapshot: InstantStoreSnapshot(attributes: declaredAttributes, triples: seedTriples)
    )
    let prepared = try await store.prepare(transaction)
    expectNoDifference(
      prepared.snapshot.attributes.map(\.id),
      ["user_prefs/id", "users/id", "users/user_prefs"],
      source
    )
    expectNoDifference(
      prepared.snapshot.attributes.first { $0.id == "users/user_prefs" },
      declaredAttributes[2],
      source
    )
    expectNoDifference(
      prepared.result.changedEntityIDs,
      ["user-1", "user_pref-1"],
      source
    )
    expectNoDifference(
      prepared.snapshot.triples,
      [
        InstantTriple(
          entityID: "user-1",
          attributeID: "users/id",
          value: .string("user-1"),
          txID: "tx-instaml-ref-lookup-link-value",
          txTime: txTime
        ),
        InstantTriple(
          entityID: "user-1",
          attributeID: "users/user_prefs",
          value: .ref("user_pref-1"),
          txID: "tx-instaml-ref-lookup-link-value",
          txTime: txTime
        ),
        InstantTriple(
          entityID: "user_pref-1",
          attributeID: "user_prefs/id",
          value: .string("user_pref-1"),
          txID: "seed-instaml-ref-lookup-link-value",
          txTime: txTime
        ),
      ],
      source
    )
  }

  @Test
  func transportMutationInfersLookupDeleteNamespaceWithoutPrecondition() throws {
    let txTime = InstantTimestamp(milliseconds: 1_700_000_000_000)
    let lookup = InstantLookupRef(
      attributeID: "users/email",
      value: .string("blob@example.com")
    )
    let transaction = InstantStoreTransaction(
      id: "tx-lookup-delete-transport",
      operations: [
        .deleteEntityByLookup(lookup)
      ]
    )
    let mutation = PendingMutation(
      id: "tx-lookup-delete-transport",
      createdAt: txTime,
      transaction: transaction
    )
    let transportMutation = InstantTransportMutation(mutation)

    expectNoDifference(transportMutation.preconditions, [])
    expectNoDifference(transportMutation.txSteps.count, 1)

    let data = try JSONEncoder().encode(transportMutation)
    let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    let txSteps = try #require(object["txSteps"] as? [[Any]])
    expectNoDifference(txSteps[0][0] as? String, "delete-entity")
    let lookupEntity = try #require(txSteps[0][1] as? [Any])
    expectNoDifference(lookupEntity[0] as? String, "users/email")
    expectNoDifference(lookupEntity[1] as? String, "blob@example.com")
    expectNoDifference(txSteps[0][2] as? String, "users")
  }

  @Test
  func transportMutationPortsInstamlModeUpdateOptions() throws {
    let txTime = InstantTimestamp(milliseconds: 1_700_000_000_000)
    let source =
      "upstream/instant/client/packages/core/__tests__/src/instaml.test.ts mode: update "
      + "[adapted: Swift explicit preconditions replace JavaScript store-aware mode inference.]"

    func txSteps(for transaction: InstantStoreTransaction) throws -> [[Any]] {
      let mutation = InstantTransportMutation(
        PendingMutation(id: transaction.id, createdAt: txTime, transaction: transaction)
      )
      let data = try JSONEncoder().encode(mutation)
      let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
      return try #require(object["txSteps"] as? [[Any]])
    }

    func expectAddTripleMode(
      _ transaction: InstantStoreTransaction,
      _ expectedMode: String?,
      source: String
    ) throws {
      let steps = try txSteps(for: transaction)
      expectNoDifference(steps.map { $0.first as? String }, ["add-triple"], source)
      if let expectedMode {
        expectNoDifference(steps.first?.count, 5, source)
        let options = try #require(steps.first?[4] as? [String: Any])
        expectNoDifference(options.keys.sorted(), ["mode"], source)
        expectNoDifference(options["mode"] as? String, expectedMode, source)
      } else {
        expectNoDifference(steps.first?.count, 4, source)
      }
    }

    try expectAddTripleMode(
      InstantStoreTransaction(
        id: "tx-instaml-upsert-new-id",
        operations: [
          .insert(
            InstantTriple(
              entityID: "new-user",
              attributeID: "users/handle",
              value: .string("test"),
              txID: "tx-instaml-upsert-new-id",
              txTime: txTime
            )
          )
        ]
      ),
      nil,
      source: source
    )

    try expectAddTripleMode(
      InstantStoreTransaction(
        id: "tx-instaml-update-by-id",
        operations: [
          .requireEntityExists(entityID: "ce942051-2d74-404a-9c7d-4aa3f2d54ae4", namespace: "users"),
          .insert(
            InstantTriple(
              entityID: "ce942051-2d74-404a-9c7d-4aa3f2d54ae4",
              attributeID: "users/handle",
              value: .string("joe2"),
              txID: "tx-instaml-update-by-id",
              txTime: txTime
            )
          ),
        ]
      ),
      "update",
      source: source
    )

    let emailLookup = InstantLookupRef(
      attributeID: "users/email",
      value: .string("stopa@instantdb.com")
    )
    let updateByLookup = InstantStoreTransaction(
      id: "tx-instaml-update-by-lookup",
      operations: [
        .requireEntityExistsByLookup(emailLookup, namespace: "users"),
        .insertByLookup(
          entity: emailLookup,
          attributeID: "users/handle",
          value: .string("stopa2"),
          txID: "tx-instaml-update-by-lookup",
          txTime: txTime
        ),
      ]
    )
    try expectAddTripleMode(updateByLookup, "update", source: source)
    let lookupSteps = try txSteps(for: updateByLookup)
    let lookupEntity = try #require(lookupSteps.first?[1] as? [Any])
    expectNoDifference(lookupEntity[0] as? String, "users/email", source)
    expectNoDifference(lookupEntity[1] as? String, "stopa@instantdb.com", source)

    try expectAddTripleMode(
      InstantStoreTransaction(
        id: "tx-instaml-forced-update",
        operations: [
          .requireEntityExists(entityID: "forced-user", namespace: "users"),
          .insert(
            InstantTriple(
              entityID: "forced-user",
              attributeID: "users/handle",
              value: .string("test"),
              txID: "tx-instaml-forced-update",
              txTime: txTime
            )
          ),
        ]
      ),
      "update",
      source: source
    )

    try expectAddTripleMode(
      InstantStoreTransaction(
        id: "tx-instaml-forced-upsert",
        operations: [
          .insert(
            InstantTriple(
              entityID: "ce942051-2d74-404a-9c7d-4aa3f2d54ae4",
              attributeID: "users/handle",
              value: .string("test"),
              txID: "tx-instaml-forced-upsert",
              txTime: txTime
            )
          )
        ]
      ),
      nil,
      source: source
    )
  }

  @Test
  func invalidLookupAttributePortsInstamlInvalidLinkAttrRejection() async throws {
    let cacheURL = try temporaryCacheURL()
    let time = InstantTimestamp(milliseconds: 1_700_000_000_000)
    let lookup = InstantLookupRef(
      attributeID: "users/user_pref.email",
      value: .string("test@example.com")
    )
    let transaction = InstantStoreTransaction(
      id: "tx-instaml-invalid-link-lookup",
      operations: [
        .insertByLookup(
          entity: lookup,
          attributeID: "users/a",
          value: .number(1),
          txID: "tx-instaml-invalid-link-lookup",
          txTime: time
        )
      ]
    )
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "test-app",
        persistenceURL: cacheURL,
        initialAttributes: [
          InstantAttribute(
            id: "users/a",
            namespace: "users",
            name: "a",
            valueType: .number
          )
        ]
      )
    )

    let source =
      "upstream/instant/client/packages/core/__tests__/src/instaml.test.ts "
      + "it throws if you use an invalid link attr "
      + "[adapted: Swift lookup refs use declared attribute ids rather than JavaScript lookup labels.]"
    do {
      try await runtime.transact(transaction, createdAt: time)
      #expect(Bool(false), "Expected invalid link-shaped lookup attr to fail. \(source)")
    } catch let error as InstantError {
      expectNoDifference(
        error,
        InstantError(
          code: .validationFailed,
          operation: "lookup entity",
          path: "users/user_pref.email",
          localID: lookup.description,
          message: "No attribute named 'users/user_pref.email' is declared for this lookup ref.",
          recovery: "Declare the lookup attribute in the schema before writing by lookup ref."
        ),
        source
      )
    } catch {
      #expect(Bool(false), "Unexpected error: \(error). \(source)")
    }

    let users = try await runtime.query(InstantQueryPlan(id: "invalid-link-lookup.users", namespace: "users"))
    let pending = await runtime.pendingMutations()
    expectNoDifference(users, [], source)
    expectNoDifference(pending, [], source)
  }

  @Test
  func lookupAttributeWithPeriodPortsInstamlDottedAttr() async throws {
    let cacheURL = try temporaryCacheURL()
    let time = InstantTimestamp(milliseconds: 1_700_000_000_000)
    let source =
      "upstream/instant/client/packages/core/__tests__/src/instaml.test.ts "
      + "it doesn't throw if you have a period in your attr "
      + "[adapted: Swift lookup refs use full attribute ids rather than JavaScript lookup labels.]"
    let attributes = [
      InstantAttribute(
        id: "users/attr.with.dot",
        namespace: "users",
        name: "attr.with.dot",
        valueType: .string,
        isIndexed: true,
        isUnique: true
      ),
      InstantAttribute(
        id: "users/a",
        namespace: "users",
        name: "a",
        valueType: .number
      ),
    ]
    let lookup = InstantLookupRef(
      attributeID: "users/attr.with.dot",
      value: .string("value")
    )
    let unresolvedTransaction = InstantStoreTransaction(
      id: "tx-instaml-dotted-lookup-transport",
      operations: [
        .insertByLookup(
          entity: lookup,
          attributeID: "users/id",
          value: .lookupRef(lookup),
          txID: "tx-instaml-dotted-lookup-transport",
          txTime: time
        ),
        .insertByLookup(
          entity: lookup,
          attributeID: "users/a",
          value: .number(1),
          txID: "tx-instaml-dotted-lookup-transport",
          txTime: time
        ),
      ]
    )

    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "test-app",
        persistenceURL: cacheURL,
        initialAttributes: attributes
      )
    )
    let unresolvedResult = try await runtime.transact(unresolvedTransaction, createdAt: time)
    let emptyUsers = try await runtime.query(InstantQueryPlan(id: "dotted-lookup.empty", namespace: "users"))
    expectNoDifference(unresolvedResult.changedEntityIDs, [], source)
    expectNoDifference(unresolvedResult.tripleCount, 0, source)
    expectNoDifference(emptyUsers, [], source)

    let transportMutation = InstantTransportMutation(
      PendingMutation(
        id: unresolvedTransaction.id,
        createdAt: time,
        transaction: unresolvedTransaction
      )
    )
    let data = try JSONEncoder().encode(transportMutation)
    let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    let txSteps = try #require(object["txSteps"] as? [[Any]])
    expectNoDifference(txSteps.count, 2, source)
    expectNoDifference(txSteps.map { $0.first as? String }, ["add-triple", "add-triple"], source)
    let lookupEntity = try #require(txSteps[0][1] as? [Any])
    expectNoDifference(lookupEntity.count, 2, source)
    expectNoDifference(lookupEntity[0] as? String, "users/attr.with.dot", source)
    expectNoDifference(lookupEntity[1] as? String, "value", source)
    expectNoDifference(txSteps[0][2] as? String, "users/id", source)
    let lookupValue = try #require(txSteps[0][3] as? [Any])
    expectNoDifference(lookupValue.count, 2, source)
    expectNoDifference(lookupValue[0] as? String, "users/attr.with.dot", source)
    expectNoDifference(lookupValue[1] as? String, "value", source)
    let secondLookupEntity = try #require(txSteps[1][1] as? [Any])
    expectNoDifference(secondLookupEntity.count, 2, source)
    expectNoDifference(secondLookupEntity[0] as? String, "users/attr.with.dot", source)
    expectNoDifference(secondLookupEntity[1] as? String, "value", source)
    expectNoDifference(txSteps[1][2] as? String, "users/a", source)
    expectNoDifference((txSteps[1][3] as? NSNumber)?.doubleValue, 1.0, source)
    expectNoDifference(txSteps.map(\.count), [4, 4], source)

    try await runtime.transact(
      InstantStoreTransaction(
        id: "tx-instaml-dotted-lookup-seed",
        operations: [
          .insert(
            InstantTriple(
              entityID: "user-1",
              attributeID: "users/id",
              value: .string("user-1"),
              txID: "tx-instaml-dotted-lookup-seed",
              txTime: InstantTimestamp(milliseconds: time.milliseconds + 1)
            )
          ),
          .insert(
            InstantTriple(
              entityID: "user-1",
              attributeID: "users/attr.with.dot",
              value: .string("local-value"),
              txID: "tx-instaml-dotted-lookup-seed",
              txTime: InstantTimestamp(milliseconds: time.milliseconds + 1)
            )
          ),
        ]
      ),
      createdAt: InstantTimestamp(milliseconds: time.milliseconds + 1)
    )
    let localLookup = InstantLookupRef(
      attributeID: "users/attr.with.dot",
      value: .string("local-value")
    )
    let localResult = try await runtime.transact(
      InstantStoreTransaction(
        id: "tx-instaml-dotted-lookup-local",
        operations: [
          .insertByLookup(
            entity: localLookup,
            attributeID: "users/a",
            value: .number(2),
            txID: "tx-instaml-dotted-lookup-local",
            txTime: InstantTimestamp(milliseconds: time.milliseconds + 2)
          )
        ]
      ),
      createdAt: InstantTimestamp(milliseconds: time.milliseconds + 2)
    )
    let users = try await runtime.query(InstantQueryPlan(id: "dotted-lookup.users", namespace: "users"))
    expectNoDifference(localResult.changedEntityIDs, ["user-1"], source)
    expectNoDifference(users.map(\.id), ["user-1"], source)
    expectNoDifference(users.first?.values["attr.with.dot"]?.first, .string("local-value"), source)
    expectNoDifference(users.first?.values["a"]?.first, .number(2), source)
  }

  @Test
  func transportMutationPreservesLookupRefsInLinkValuesForInstamlParity() throws {
    let txTime = InstantTimestamp(milliseconds: 1_700_000_000_000)
    let postLookup = InstantLookupRef(
      attributeID: "posts/slug",
      value: .string("life-is-good")
    )
    let userPrefsLookup = InstantLookupRef(
      attributeID: "user_prefs/users",
      value: .ref("user-1")
    )
    let transaction = InstantStoreTransaction(
      id: "tx-lookup-link-value-transport",
      operations: [
        .requireEntityExists(entityID: "user-1", namespace: "users"),
        .insert(
          InstantTriple(
            entityID: "user-1",
            attributeID: "users/posts",
            value: .lookupRef(postLookup),
            txID: "tx-lookup-link-value-transport",
            txTime: txTime
          )
        ),
        .insert(
          InstantTriple(
            entityID: "user-1",
            attributeID: "users/user_prefs",
            value: .lookupRef(userPrefsLookup),
            txID: "tx-lookup-link-value-transport",
            txTime: txTime
          )
        ),
      ]
    )
    let transportMutation = InstantTransportMutation(
      PendingMutation(
        id: "tx-lookup-link-value-transport",
        createdAt: txTime,
        transaction: transaction
      )
    )

    let source =
      "upstream instaml.test.ts: lookup link values stay two-element lookup refs in tx steps."
    expectNoDifference(
      transportMutation.preconditions,
      [
        InstantTransportPrecondition(
          kind: .entityExists,
          entity: .id("user-1"),
          namespace: "users"
        )
      ],
      source
    )
    expectNoDifference(
      transportMutation.txSteps,
      [
        .addTriple(
          entity: .id("user-1"),
          attributeID: "users/posts",
          value: .lookupRef(attributeID: "posts/slug", value: .string("life-is-good")),
          options: InstantTransportOptions(mode: .update)
        ),
        .addTriple(
          entity: .id("user-1"),
          attributeID: "users/user_prefs",
          value: .lookupRef(attributeID: "user_prefs/users", value: .string("user-1")),
          options: InstantTransportOptions(mode: .update)
        ),
      ],
      source
    )

    let data = try JSONEncoder().encode(transportMutation)
    let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    let txSteps = try #require(object["txSteps"] as? [[Any]])
    let postLookupValue = try #require(txSteps[0][3] as? [Any])
    expectNoDifference(postLookupValue.count, 2, source)
    expectNoDifference(postLookupValue[0] as? String, "posts/slug", source)
    expectNoDifference(postLookupValue[1] as? String, "life-is-good", source)
    let userPrefsLookupValue = try #require(txSteps[1][3] as? [Any])
    expectNoDifference(userPrefsLookupValue.count, 2, source)
    expectNoDifference(userPrefsLookupValue[0] as? String, "user_prefs/users", source)
    expectNoDifference(userPrefsLookupValue[1] as? String, "user-1", source)
  }

  @Test
  func transportMutationPortsInstamlLookupRefArraysInLinkValues() throws {
    let txTime = InstantTimestamp(milliseconds: 1_700_000_000_000)
    let firstPostLookup = InstantLookupRef(
      attributeID: "posts/slug",
      value: .string("life-is-good")
    )
    let secondPostLookup = InstantLookupRef(
      attributeID: "posts/slug",
      value: .string("check-this-out")
    )
    let transaction = InstantStoreTransaction(
      id: "tx-instaml-lookup-link-array-transport",
      operations: [
        .insert(
          InstantTriple(
            entityID: "user-1",
            attributeID: "users/id",
            value: .string("user-1"),
            txID: "tx-instaml-lookup-link-array-transport",
            txTime: txTime
          )
        ),
        .insert(
          InstantTriple(
            entityID: "user-1",
            attributeID: "users/posts",
            value: .lookupRef(firstPostLookup),
            txID: "tx-instaml-lookup-link-array-transport",
            txTime: txTime
          )
        ),
        .insert(
          InstantTriple(
            entityID: "user-1",
            attributeID: "users/posts",
            value: .lookupRef(secondPostLookup),
            txID: "tx-instaml-lookup-link-array-transport",
            txTime: txTime
          )
        ),
      ]
    )
    let transportMutation = InstantTransportMutation(
      PendingMutation(
        id: "tx-instaml-lookup-link-array-transport",
        createdAt: txTime,
        transaction: transaction
      )
    )

    let source =
      "upstream/instant/client/packages/core/__tests__/src/instaml.test.ts "
      + "lookup creates unique attrs for lookups in link values with arrays "
      + "[adapted: Swift represents link arrays as repeated ref inserts over declared attr ids.]"
    expectNoDifference(transportMutation.preconditions, [], source)
    expectNoDifference(
      transportMutation.txSteps,
      [
        .addTriple(
          entity: .id("user-1"),
          attributeID: "users/id",
          value: .string("user-1")
        ),
        .addTriple(
          entity: .id("user-1"),
          attributeID: "users/posts",
          value: .lookupRef(attributeID: "posts/slug", value: .string("life-is-good"))
        ),
        .addTriple(
          entity: .id("user-1"),
          attributeID: "users/posts",
          value: .lookupRef(attributeID: "posts/slug", value: .string("check-this-out"))
        ),
      ],
      source
    )

    let data = try JSONEncoder().encode(transportMutation)
    let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    let txSteps = try #require(object["txSteps"] as? [[Any]])
    expectNoDifference(txSteps.count, 3, source)
    expectNoDifference(txSteps.map { $0.first as? String }, ["add-triple", "add-triple", "add-triple"], source)
    expectNoDifference(txSteps.map(\.count), [4, 4, 4], source)
    expectNoDifference(txSteps[0][1] as? String, "user-1", source)
    expectNoDifference(txSteps[0][2] as? String, "users/id", source)
    expectNoDifference(txSteps[0][3] as? String, "user-1", source)

    let firstLookupValue = try #require(txSteps[1][3] as? [Any])
    expectNoDifference(txSteps[1][1] as? String, "user-1", source)
    expectNoDifference(txSteps[1][2] as? String, "users/posts", source)
    expectNoDifference(firstLookupValue.count, 2, source)
    expectNoDifference(firstLookupValue[0] as? String, "posts/slug", source)
    expectNoDifference(firstLookupValue[1] as? String, "life-is-good", source)

    let secondLookupValue = try #require(txSteps[2][3] as? [Any])
    expectNoDifference(txSteps[2][1] as? String, "user-1", source)
    expectNoDifference(txSteps[2][2] as? String, "users/posts", source)
    expectNoDifference(secondLookupValue.count, 2, source)
    expectNoDifference(secondLookupValue[0] as? String, "posts/slug", source)
    expectNoDifference(secondLookupValue[1] as? String, "check-this-out", source)
  }

  @Test
  func reciprocalLinksUseSingleRefAttributeForInstamlDuplicateRefAttrParity() async throws {
    let cacheURL = try temporaryCacheURL()
    let time = InstantTimestamp(milliseconds: 1_700_000_000_000)
    let source =
      "upstream/instant/client/packages/core/__tests__/src/instaml.test.ts "
      + "it doesn't create duplicate ref attrs "
      + "[adapted: Swift uses declared attrs; reciprocal link intents share one physical ref attr.]"
    let attributes = [
      InstantAttribute(
        id: "nsA/nsB",
        namespace: "nsA",
        name: "nsB",
        valueType: .ref,
        isRequired: false,
        cardinality: .many,
        forwardIdentity: "nsA/nsB",
        reverseIdentity: "nsB/nsA",
        linkNamespace: "nsB"
      ),
      InstantAttribute(
        id: "nsB/title",
        namespace: "nsB",
        name: "title",
        valueType: .string,
        isRequired: false
      ),
    ]
    let transaction = InstantStoreTransaction(
      id: "tx-instaml-no-duplicate-ref-attrs",
      operations: [
        .insert(
          InstantTriple(
            entityID: "a-1",
            attributeID: "nsA/id",
            value: .string("a-1"),
            txID: "tx-instaml-no-duplicate-ref-attrs",
            txTime: time
          )
        ),
        .insert(
          InstantTriple(
            entityID: "a-1",
            attributeID: "nsA/nsB",
            value: .ref("b-1"),
            txID: "tx-instaml-no-duplicate-ref-attrs",
            txTime: time
          )
        ),
        .insert(
          InstantTriple(
            entityID: "b-1",
            attributeID: "nsB/id",
            value: .string("b-1"),
            txID: "tx-instaml-no-duplicate-ref-attrs",
            txTime: time
          )
        ),
        .insert(
          InstantTriple(
            entityID: "a-1",
            attributeID: "nsA/nsB",
            value: .ref("b-1"),
            txID: "tx-instaml-no-duplicate-ref-attrs",
            txTime: time
          )
        ),
      ]
    )

    let store = InstantStore(snapshot: InstantStoreSnapshot(attributes: attributes))
    _ = try await store.prepare(transaction)
    let snapshot = await store.snapshot()
    expectNoDifference(
      snapshot.attributes.filter { $0.valueType == .ref }.map(\.id),
      ["nsA/nsB"],
      source
    )
    expectNoDifference(snapshot.triples.count, 3, source)

    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "test-app",
        persistenceURL: cacheURL,
        initialAttributes: attributes
      )
    )
    let result = try await runtime.transact(transaction, createdAt: time)
    let nsA = try await runtime.query(
      InstantQueryPlan(
        id: "duplicate-ref-attrs.nsA",
        namespace: "nsA",
        includes: [InstantQueryInclude("nsB")]
      )
    )
    let nsB = try await runtime.query(
      InstantQueryPlan(
        id: "duplicate-ref-attrs.nsB",
        namespace: "nsB",
        includes: [InstantQueryInclude("nsA", direction: .reverse)]
      )
    )

    expectNoDifference(result.changedEntityIDs, Set(["a-1", "b-1"]), source)
    expectNoDifference(result.tripleCount, 3, source)
    expectNoDifference(nsA.map(\.id), ["a-1"], source)
    expectNoDifference(nsA.first?.values["nsB"]?.values, [.ref("b-1")], source)
    expectNoDifference(nsA.first?.links?["nsB"]?.map(\.id), ["b-1"], source)
    expectNoDifference(nsB.map(\.id), ["b-1"], source)
    expectNoDifference(nsB.first?.links?["nsA"]?.map(\.id), ["a-1"], source)

    let transportMutations = await runtime.outboxTransportMutations()
    let transportMutation = try #require(transportMutations.first)
    expectNoDifference(
      transportMutation.txSteps,
      [
        .addTriple(entity: .id("a-1"), attributeID: "nsA/id", value: .string("a-1")),
        .addTriple(entity: .id("a-1"), attributeID: "nsA/nsB", value: .string("b-1")),
        .addTriple(entity: .id("b-1"), attributeID: "nsB/id", value: .string("b-1")),
        .addTriple(entity: .id("a-1"), attributeID: "nsA/nsB", value: .string("b-1")),
      ],
      source
    )
  }

  @Test
  func schemaMetadataPortsInstamlAttrsAndLinks() async throws {
    let cacheURL = try temporaryCacheURL()
    let time = InstantTimestamp(milliseconds: 1_700_000_000_000)
    let source =
      "upstream/instant/client/packages/core/__tests__/src/instaml.test.ts "
      + "Schema: uses info in `attrs` and `links` "
      + "[adapted: Swift uses declared attrs rather than transform-time add-attr generation.]"
    let attributes = [
      InstantAttribute(
        id: "comments/slug",
        namespace: "comments",
        name: "slug",
        valueType: .string,
        isRequired: false,
        isIndexed: true,
        isUnique: true
      ),
      InstantAttribute(
        id: "comments/book",
        namespace: "comments",
        name: "book",
        valueType: .ref,
        isRequired: false,
        cardinality: .one,
        forwardIdentity: "comments/book",
        reverseIdentity: "books/comments",
        linkNamespace: "books"
      ),
    ]
    let transaction = InstantStoreTransaction(
      id: "tx-instaml-schema-attrs-links",
      operations: [
        .insert(
          InstantTriple(
            entityID: "comment-1",
            attributeID: "comments/id",
            value: .string("comment-1"),
            txID: "tx-instaml-schema-attrs-links",
            txTime: time
          )
        ),
        .insert(
          InstantTriple(
            entityID: "comment-1",
            attributeID: "comments/slug",
            value: .string("test-slug"),
            txID: "tx-instaml-schema-attrs-links",
            txTime: time
          )
        ),
        .insert(
          InstantTriple(
            entityID: "comment-1",
            attributeID: "comments/book",
            value: .ref("book-1"),
            txID: "tx-instaml-schema-attrs-links",
            txTime: time
          )
        ),
      ]
    )

    let store = InstantStore(snapshot: InstantStoreSnapshot(attributes: attributes))
    _ = try await store.prepare(transaction)
    let snapshot = await store.snapshot()
    let attributesByID = Dictionary(uniqueKeysWithValues: snapshot.attributes.map { ($0.id, $0) })
    let slugAttribute = try #require(attributesByID["comments/slug"])
    let bookAttribute = try #require(attributesByID["comments/book"])
    expectNoDifference(slugAttribute.namespace, "comments", source)
    expectNoDifference(slugAttribute.name, "slug", source)
    expectNoDifference(slugAttribute.valueType, .string, source)
    expectNoDifference(slugAttribute.cardinality, .one, source)
    expectNoDifference(slugAttribute.isUnique, true, source)
    expectNoDifference(slugAttribute.isIndexed, true, source)
    expectNoDifference(bookAttribute.namespace, "comments", source)
    expectNoDifference(bookAttribute.name, "book", source)
    expectNoDifference(bookAttribute.valueType, .ref, source)
    expectNoDifference(bookAttribute.cardinality, .one, source)
    expectNoDifference(bookAttribute.isUnique, false, source)
    expectNoDifference(bookAttribute.isIndexed, false, source)
    expectNoDifference(bookAttribute.forwardIdentity, "comments/book", source)
    expectNoDifference(bookAttribute.reverseIdentity, "books/comments", source)
    expectNoDifference(bookAttribute.linkNamespace, "books", source)
    expectNoDifference(snapshot.triples.count, 3, source)

    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "test-app",
        persistenceURL: cacheURL,
        initialAttributes: attributes
      )
    )
    let result = try await runtime.transact(transaction, createdAt: time)
    let comments = try await runtime.query(
      InstantQueryPlan(id: "schema-attrs-links.comments", namespace: "comments")
    )

    expectNoDifference(result.changedEntityIDs, Set(["book-1", "comment-1"]), source)
    expectNoDifference(result.tripleCount, 3, source)
    expectNoDifference(comments.map(\.id), ["comment-1"], source)
    expectNoDifference(comments.first?.values["slug"]?.first, .string("test-slug"), source)
    expectNoDifference(comments.first?.values["book"]?.first, .ref("book-1"), source)

    let transportMutations = await runtime.outboxTransportMutations()
    let transportMutation = try #require(transportMutations.first)
    expectNoDifference(
      transportMutation.txSteps,
      [
        .addTriple(entity: .id("comment-1"), attributeID: "comments/id", value: .string("comment-1")),
        .addTriple(entity: .id("comment-1"), attributeID: "comments/slug", value: .string("test-slug")),
        .addTriple(entity: .id("comment-1"), attributeID: "comments/book", value: .string("book-1")),
      ],
      source
    )
  }

  @Test
  func schemaReciprocalLinksUseSingleRefAttributeForInstamlDuplicateRefAttrParity() async throws {
    let cacheURL = try temporaryCacheURL()
    let time = InstantTimestamp(milliseconds: 1_700_000_000_000)
    let source =
      "upstream/instant/client/packages/core/__tests__/src/instaml.test.ts "
      + "Schema: doesn't create duplicate ref attrs "
      + "[adapted: Swift core stores normalized physical ref triples; the reverse-side link intent is represented as a second comments/book write.]"
    let attributes = [
      InstantAttribute(
        id: "comments/book",
        namespace: "comments",
        name: "book",
        valueType: .ref,
        isRequired: false,
        cardinality: .one,
        forwardIdentity: "comments/book",
        reverseIdentity: "books/comments",
        linkNamespace: "books"
      ),
      InstantAttribute(
        id: "books/title",
        namespace: "books",
        name: "title",
        valueType: .string,
        isRequired: false
      ),
    ]
    let transaction = InstantStoreTransaction(
      id: "tx-instaml-schema-no-duplicate-ref-attrs",
      operations: [
        .insert(
          InstantTriple(
            entityID: "comment-1",
            attributeID: "comments/id",
            value: .string("comment-1"),
            txID: "tx-instaml-schema-no-duplicate-ref-attrs",
            txTime: time
          )
        ),
        .insert(
          InstantTriple(
            entityID: "comment-1",
            attributeID: "comments/book",
            value: .ref("book-1"),
            txID: "tx-instaml-schema-no-duplicate-ref-attrs",
            txTime: time
          )
        ),
        .insert(
          InstantTriple(
            entityID: "book-1",
            attributeID: "books/id",
            value: .string("book-1"),
            txID: "tx-instaml-schema-no-duplicate-ref-attrs",
            txTime: time
          )
        ),
        .insert(
          InstantTriple(
            entityID: "comment-1",
            attributeID: "comments/book",
            value: .ref("book-1"),
            txID: "tx-instaml-schema-no-duplicate-ref-attrs",
            txTime: time
          )
        ),
      ]
    )

    let store = InstantStore(snapshot: InstantStoreSnapshot(attributes: attributes))
    _ = try await store.prepare(transaction)
    let snapshot = await store.snapshot()
    let refAttributes = snapshot.attributes.filter { $0.valueType == .ref }
    let bookAttribute = try #require(refAttributes.first)
    expectNoDifference(refAttributes.map(\.id), ["comments/book"], source)
    expectNoDifference(bookAttribute.cardinality, .one, source)
    expectNoDifference(bookAttribute.forwardIdentity, "comments/book", source)
    expectNoDifference(bookAttribute.reverseIdentity, "books/comments", source)
    expectNoDifference(bookAttribute.linkNamespace, "books", source)
    expectNoDifference(
      snapshot.triples.filter { $0.attributeID == "comments/book" },
      [
        InstantTriple(
          entityID: "comment-1",
          attributeID: "comments/book",
          value: .ref("book-1"),
          txID: "tx-instaml-schema-no-duplicate-ref-attrs",
          txTime: time
        )
      ],
      source
    )
    expectNoDifference(snapshot.triples.count, 3, source)

    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "test-app",
        persistenceURL: cacheURL,
        initialAttributes: attributes
      )
    )
    let result = try await runtime.transact(transaction, createdAt: time)
    let comments = try await runtime.query(
      InstantQueryPlan(
        id: "schema-no-duplicate-ref-attrs.comments",
        namespace: "comments",
        includes: [InstantQueryInclude("book")]
      )
    )
    let books = try await runtime.query(
      InstantQueryPlan(
        id: "schema-no-duplicate-ref-attrs.books",
        namespace: "books",
        includes: [InstantQueryInclude("comments", direction: .reverse)]
      )
    )

    expectNoDifference(result.changedEntityIDs, Set(["book-1", "comment-1"]), source)
    expectNoDifference(result.tripleCount, 3, source)
    expectNoDifference(comments.map(\.id), ["comment-1"], source)
    expectNoDifference(comments.first?.values["book"]?.values, [.ref("book-1")], source)
    expectNoDifference(comments.first?.links?["book"]?.map(\.id), ["book-1"], source)
    expectNoDifference(books.map(\.id), ["book-1"], source)
    expectNoDifference(books.first?.links?["comments"]?.map(\.id), ["comment-1"], source)

    let transportMutations = await runtime.outboxTransportMutations()
    expectNoDifference(transportMutations.map(\.transactionID), ["tx-instaml-schema-no-duplicate-ref-attrs"], source)
    let transportMutation = try #require(transportMutations.first)
    expectNoDifference(
      transportMutation.txSteps,
      [
        .addTriple(entity: .id("comment-1"), attributeID: "comments/id", value: .string("comment-1")),
        .addTriple(entity: .id("comment-1"), attributeID: "comments/book", value: .string("book-1")),
        .addTriple(entity: .id("book-1"), attributeID: "books/id", value: .string("book-1")),
        .addTriple(entity: .id("comment-1"), attributeID: "comments/book", value: .string("book-1")),
      ],
      source
    )
  }

  @Test
  func schemaLookupRefsUseDeclaredUniqueAttrForInstamlCustomLookupParity() async throws {
    let cacheURL = try temporaryCacheURL()
    let time = InstantTimestamp(milliseconds: 1_700_000_000_000)
    let source =
      "upstream/instant/client/packages/core/__tests__/src/instaml.test.ts "
      + "Schema: lookup creates unique attrs for custom lookups "
      + "[adapted: Swift uses declared attrs; lookup entities and id values stay lookup-shaped for transport.]"
    let attributes = [
      InstantAttribute(
        id: "users/nickname",
        namespace: "users",
        name: "nickname",
        valueType: .string,
        isRequired: false,
        isIndexed: true,
        isUnique: true
      ),
      InstantAttribute(
        id: "users/handle",
        namespace: "users",
        name: "handle",
        valueType: .string,
        isRequired: false
      ),
    ]
    let lookup = InstantLookupRef(
      attributeID: "users/nickname",
      value: .string("stopanator")
    )
    let transaction = InstantStoreTransaction(
      id: "tx-instaml-schema-custom-lookup",
      operations: [
        .insertByLookup(
          entity: lookup,
          attributeID: "users/handle",
          value: .string("stopa"),
          txID: "tx-instaml-schema-custom-lookup",
          txTime: time
        ),
        .insertByLookup(
          entity: lookup,
          attributeID: "users/id",
          value: .lookupRef(lookup),
          txID: "tx-instaml-schema-custom-lookup",
          txTime: time
        ),
      ]
    )

    let store = InstantStore(snapshot: InstantStoreSnapshot(attributes: attributes))
    _ = try await store.prepare(transaction)
    let snapshot = await store.snapshot()
    let attributesByID = Dictionary(uniqueKeysWithValues: snapshot.attributes.map { ($0.id, $0) })
    let nicknameAttribute = try #require(attributesByID["users/nickname"])
    expectNoDifference(nicknameAttribute.namespace, "users", source)
    expectNoDifference(nicknameAttribute.name, "nickname", source)
    expectNoDifference(nicknameAttribute.valueType, .string, source)
    expectNoDifference(nicknameAttribute.cardinality, .one, source)
    expectNoDifference(nicknameAttribute.isUnique, true, source)
    expectNoDifference(nicknameAttribute.isIndexed, true, source)
    expectNoDifference(snapshot.triples, [], source)

    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "test-app",
        persistenceURL: cacheURL,
        initialAttributes: attributes
      )
    )
    let unresolvedResult = try await runtime.transact(transaction, createdAt: time)
    let emptyUsers = try await runtime.query(
      InstantQueryPlan(id: "schema-custom-lookup.empty", namespace: "users")
    )
    expectNoDifference(unresolvedResult.changedEntityIDs, [], source)
    expectNoDifference(unresolvedResult.tripleCount, 0, source)
    expectNoDifference(emptyUsers, [], source)

    let transportMutations = await runtime.outboxTransportMutations()
    expectNoDifference(transportMutations.map(\.transactionID), ["tx-instaml-schema-custom-lookup"], source)
    let transportMutation = try #require(transportMutations.first)
    expectNoDifference(
      transportMutation.txSteps,
      [
        .addTriple(entity: .lookup(lookup), attributeID: "users/handle", value: .string("stopa")),
        .addTriple(
          entity: .lookup(lookup),
          attributeID: "users/id",
          value: .lookupRef(attributeID: "users/nickname", value: .string("stopanator"))
        ),
      ],
      source
    )

    let data = try JSONEncoder().encode(transportMutation)
    let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    let txSteps = try #require(object["txSteps"] as? [[Any]])
    expectNoDifference(txSteps.count, 2, source)
    expectNoDifference(txSteps.map { $0.first as? String }, ["add-triple", "add-triple"], source)
    expectNoDifference(txSteps.map(\.count), [4, 4], source)
    let firstLookupEntity = try #require(txSteps[0][1] as? [Any])
    expectNoDifference(firstLookupEntity.count, 2, source)
    expectNoDifference(firstLookupEntity[0] as? String, "users/nickname", source)
    expectNoDifference(firstLookupEntity[1] as? String, "stopanator", source)
    expectNoDifference(txSteps[0][2] as? String, "users/handle", source)
    expectNoDifference(txSteps[0][3] as? String, "stopa", source)
    let secondLookupEntity = try #require(txSteps[1][1] as? [Any])
    expectNoDifference(secondLookupEntity.count, 2, source)
    expectNoDifference(secondLookupEntity[0] as? String, "users/nickname", source)
    expectNoDifference(secondLookupEntity[1] as? String, "stopanator", source)
    expectNoDifference(txSteps[1][2] as? String, "users/id", source)
    let lookupValue = try #require(txSteps[1][3] as? [Any])
    expectNoDifference(lookupValue.count, 2, source)
    expectNoDifference(lookupValue[0] as? String, "users/nickname", source)
    expectNoDifference(lookupValue[1] as? String, "stopanator", source)

    try await runtime.transact(
      InstantStoreTransaction(
        id: "tx-instaml-schema-custom-lookup-seed",
        operations: [
          .insert(
            InstantTriple(
              entityID: "user-1",
              attributeID: "users/id",
              value: .string("user-1"),
              txID: "tx-instaml-schema-custom-lookup-seed",
              txTime: InstantTimestamp(milliseconds: time.milliseconds + 1)
            )
          ),
          .insert(
            InstantTriple(
              entityID: "user-1",
              attributeID: "users/nickname",
              value: .string("local-stopanator"),
              txID: "tx-instaml-schema-custom-lookup-seed",
              txTime: InstantTimestamp(milliseconds: time.milliseconds + 1)
            )
          ),
        ]
      ),
      createdAt: InstantTimestamp(milliseconds: time.milliseconds + 1)
    )
    let localLookup = InstantLookupRef(
      attributeID: "users/nickname",
      value: .string("local-stopanator")
    )
    let localResult = try await runtime.transact(
      InstantStoreTransaction(
        id: "tx-instaml-schema-custom-lookup-local",
        operations: [
          .insertByLookup(
            entity: localLookup,
            attributeID: "users/handle",
            value: .string("stopa-local"),
            txID: "tx-instaml-schema-custom-lookup-local",
            txTime: InstantTimestamp(milliseconds: time.milliseconds + 2)
          )
        ]
      ),
      createdAt: InstantTimestamp(milliseconds: time.milliseconds + 2)
    )
    let users = try await runtime.query(
      InstantQueryPlan(id: "schema-custom-lookup.users", namespace: "users")
    )
    expectNoDifference(localResult.changedEntityIDs, ["user-1"], source)
    expectNoDifference(localResult.tripleCount, 3, source)
    expectNoDifference(users.map(\.id), ["user-1"], source)
    expectNoDifference(users.first?.values["nickname"]?.first, .string("local-stopanator"), source)
    expectNoDifference(users.first?.values["handle"]?.first, .string("stopa-local"), source)
  }

  @Test
  func schemaLookupRefsInLinkValuesUseDeclaredAttrsForInstamlParity() async throws {
    let cacheURL = try temporaryCacheURL()
    let time = InstantTimestamp(milliseconds: 1_700_000_000_000)
    let source =
      "upstream/instant/client/packages/core/__tests__/src/instaml.test.ts "
      + "Schema: lookup creates unique attrs for lookups in link values "
      + "[adapted: Swift preserves declared many relation cardinality; lookup link values stay lookup-shaped for transport.]"
    let attributes = [
      InstantAttribute(
        id: "users/authoredPosts",
        namespace: "users",
        name: "authoredPosts",
        valueType: .ref,
        isRequired: false,
        cardinality: .many,
        isIndexed: true,
        forwardIdentity: "users/authoredPosts",
        reverseIdentity: "posts/author",
        linkNamespace: "posts"
      ),
      InstantAttribute(
        id: "posts/slug",
        namespace: "posts",
        name: "slug",
        valueType: .string,
        isRequired: false,
        isIndexed: true,
        isUnique: true
      ),
    ]
    let postLookup = InstantLookupRef(
      attributeID: "posts/slug",
      value: .string("life-is-good")
    )
    let transaction = InstantStoreTransaction(
      id: "tx-instaml-schema-lookup-link-value",
      operations: [
        .insert(
          InstantTriple(
            entityID: "user-1",
            attributeID: "users/id",
            value: .string("user-1"),
            txID: "tx-instaml-schema-lookup-link-value",
            txTime: time
          )
        ),
        .insert(
          InstantTriple(
            entityID: "user-1",
            attributeID: "users/authoredPosts",
            value: .lookupRef(postLookup),
            txID: "tx-instaml-schema-lookup-link-value",
            txTime: time
          )
        ),
      ]
    )

    let store = InstantStore(snapshot: InstantStoreSnapshot(attributes: attributes))
    _ = try await store.prepare(transaction)
    let snapshot = await store.snapshot()
    let attributesByID = Dictionary(uniqueKeysWithValues: snapshot.attributes.map { ($0.id, $0) })
    let authoredPostsAttribute = try #require(attributesByID["users/authoredPosts"])
    let slugAttribute = try #require(attributesByID["posts/slug"])
    expectNoDifference(authoredPostsAttribute.valueType, .ref, source)
    expectNoDifference(authoredPostsAttribute.cardinality, .many, source)
    expectNoDifference(authoredPostsAttribute.isIndexed, true, source)
    expectNoDifference(authoredPostsAttribute.isUnique, false, source)
    expectNoDifference(authoredPostsAttribute.forwardIdentity, "users/authoredPosts", source)
    expectNoDifference(authoredPostsAttribute.reverseIdentity, "posts/author", source)
    expectNoDifference(authoredPostsAttribute.linkNamespace, "posts", source)
    expectNoDifference(slugAttribute.valueType, .string, source)
    expectNoDifference(slugAttribute.cardinality, .one, source)
    expectNoDifference(slugAttribute.isUnique, true, source)
    expectNoDifference(slugAttribute.isIndexed, true, source)
    expectNoDifference(
      snapshot.triples,
      [
        InstantTriple(
          entityID: "user-1",
          attributeID: "users/id",
          value: .string("user-1"),
          txID: "tx-instaml-schema-lookup-link-value",
          txTime: time
        )
      ],
      source
    )

    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "test-app",
        persistenceURL: cacheURL,
        initialAttributes: attributes
      )
    )
    let unresolvedResult = try await runtime.transact(transaction, createdAt: time)
    let unresolvedUsers = try await runtime.query(
      InstantQueryPlan(
        id: "schema-lookup-link-value.unresolved-users",
        namespace: "users",
        includes: [InstantQueryInclude("authoredPosts")]
      )
    )
    expectNoDifference(unresolvedResult.changedEntityIDs, ["user-1"], source)
    expectNoDifference(unresolvedResult.tripleCount, 1, source)
    expectNoDifference(unresolvedUsers.map(\.id), ["user-1"], source)
    expectNoDifference(unresolvedUsers.first?.values["authoredPosts"], nil, source)
    expectNoDifference(unresolvedUsers.first?.links?["authoredPosts"], [], source)

    let transportMutations = await runtime.outboxTransportMutations()
    expectNoDifference(transportMutations.map(\.transactionID), ["tx-instaml-schema-lookup-link-value"], source)
    let transportMutation = try #require(transportMutations.first)
    expectNoDifference(
      transportMutation.txSteps,
      [
        .addTriple(entity: .id("user-1"), attributeID: "users/id", value: .string("user-1")),
        .addTriple(
          entity: .id("user-1"),
          attributeID: "users/authoredPosts",
          value: .lookupRef(attributeID: "posts/slug", value: .string("life-is-good"))
        ),
      ],
      source
    )

    let data = try JSONEncoder().encode(transportMutation)
    let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    let txSteps = try #require(object["txSteps"] as? [[Any]])
    expectNoDifference(txSteps.count, 2, source)
    expectNoDifference(txSteps.map { $0.first as? String }, ["add-triple", "add-triple"], source)
    expectNoDifference(txSteps.map(\.count), [4, 4], source)
    expectNoDifference(txSteps[0][1] as? String, "user-1", source)
    expectNoDifference(txSteps[0][2] as? String, "users/id", source)
    expectNoDifference(txSteps[0][3] as? String, "user-1", source)
    expectNoDifference(txSteps[1][1] as? String, "user-1", source)
    expectNoDifference(txSteps[1][2] as? String, "users/authoredPosts", source)
    let lookupValue = try #require(txSteps[1][3] as? [Any])
    expectNoDifference(lookupValue.count, 2, source)
    expectNoDifference(lookupValue[0] as? String, "posts/slug", source)
    expectNoDifference(lookupValue[1] as? String, "life-is-good", source)

    try await runtime.transact(
      InstantStoreTransaction(
        id: "tx-instaml-schema-lookup-link-value-seed",
        operations: [
          .insert(
            InstantTriple(
              entityID: "post-1",
              attributeID: "posts/id",
              value: .string("post-1"),
              txID: "tx-instaml-schema-lookup-link-value-seed",
              txTime: InstantTimestamp(milliseconds: time.milliseconds + 1)
            )
          ),
          .insert(
            InstantTriple(
              entityID: "post-1",
              attributeID: "posts/slug",
              value: .string("life-is-good"),
              txID: "tx-instaml-schema-lookup-link-value-seed",
              txTime: InstantTimestamp(milliseconds: time.milliseconds + 1)
            )
          ),
        ]
      ),
      createdAt: InstantTimestamp(milliseconds: time.milliseconds + 1)
    )
    let localResult = try await runtime.transact(
      InstantStoreTransaction(
        id: "tx-instaml-schema-lookup-link-value-local",
        operations: [
          .insert(
            InstantTriple(
              entityID: "user-1",
              attributeID: "users/authoredPosts",
              value: .lookupRef(postLookup),
              txID: "tx-instaml-schema-lookup-link-value-local",
              txTime: InstantTimestamp(milliseconds: time.milliseconds + 2)
            )
          )
        ]
      ),
      createdAt: InstantTimestamp(milliseconds: time.milliseconds + 2)
    )
    let linkedUsers = try await runtime.query(
      InstantQueryPlan(
        id: "schema-lookup-link-value.users",
        namespace: "users",
        includes: [InstantQueryInclude("authoredPosts")]
      )
    )
    let linkedPosts = try await runtime.query(
      InstantQueryPlan(
        id: "schema-lookup-link-value.posts",
        namespace: "posts",
        includes: [InstantQueryInclude("author", direction: .reverse)]
      )
    )
    expectNoDifference(localResult.changedEntityIDs, Set(["post-1", "user-1"]), source)
    expectNoDifference(localResult.tripleCount, 4, source)
    expectNoDifference(linkedUsers.map(\.id), ["user-1"], source)
    expectNoDifference(linkedUsers.first?.values["authoredPosts"]?.values, [.ref("post-1")], source)
    expectNoDifference(linkedUsers.first?.links?["authoredPosts"]?.map(\.id), ["post-1"], source)
    expectNoDifference(linkedPosts.map(\.id), ["post-1"], source)
    expectNoDifference(linkedPosts.first?.links?["author"]?.map(\.id), ["user-1"], source)
  }

  @Test
  func schemaLookupRefArraysInLinkValuesUseDeclaredAttrsForInstamlParity() async throws {
    let cacheURL = try temporaryCacheURL()
    let time = InstantTimestamp(milliseconds: 1_700_000_000_000)
    let source =
      "upstream/instant/client/packages/core/__tests__/src/instaml.test.ts "
      + "Schema: lookup creates unique attrs for lookups in link values with arrays "
      + "[adapted: Swift preserves declared many relation cardinality; lookup link array values are repeated lookup-shaped link writes.]"
    let attributes = [
      InstantAttribute(
        id: "users/authoredPosts",
        namespace: "users",
        name: "authoredPosts",
        valueType: .ref,
        isRequired: false,
        cardinality: .many,
        isIndexed: true,
        forwardIdentity: "users/authoredPosts",
        reverseIdentity: "posts/author",
        linkNamespace: "posts"
      ),
      InstantAttribute(
        id: "posts/slug",
        namespace: "posts",
        name: "slug",
        valueType: .string,
        isRequired: false,
        isIndexed: true,
        isUnique: true
      ),
    ]
    let firstPostLookup = InstantLookupRef(
      attributeID: "posts/slug",
      value: .string("life-is-good")
    )
    let secondPostLookup = InstantLookupRef(
      attributeID: "posts/slug",
      value: .string("check-this-out")
    )
    let transaction = InstantStoreTransaction(
      id: "tx-instaml-schema-lookup-link-array",
      operations: [
        .insert(
          InstantTriple(
            entityID: "user-1",
            attributeID: "users/id",
            value: .string("user-1"),
            txID: "tx-instaml-schema-lookup-link-array",
            txTime: time
          )
        ),
        .insert(
          InstantTriple(
            entityID: "user-1",
            attributeID: "users/authoredPosts",
            value: .lookupRef(firstPostLookup),
            txID: "tx-instaml-schema-lookup-link-array",
            txTime: time
          )
        ),
        .insert(
          InstantTriple(
            entityID: "user-1",
            attributeID: "users/authoredPosts",
            value: .lookupRef(secondPostLookup),
            txID: "tx-instaml-schema-lookup-link-array",
            txTime: time
          )
        ),
      ]
    )

    let store = InstantStore(snapshot: InstantStoreSnapshot(attributes: attributes))
    _ = try await store.prepare(transaction)
    let snapshot = await store.snapshot()
    let attributesByID = Dictionary(uniqueKeysWithValues: snapshot.attributes.map { ($0.id, $0) })
    let authoredPostsAttribute = try #require(attributesByID["users/authoredPosts"])
    let slugAttribute = try #require(attributesByID["posts/slug"])
    expectNoDifference(authoredPostsAttribute.valueType, .ref, source)
    expectNoDifference(authoredPostsAttribute.cardinality, .many, source)
    expectNoDifference(authoredPostsAttribute.isIndexed, true, source)
    expectNoDifference(authoredPostsAttribute.isUnique, false, source)
    expectNoDifference(authoredPostsAttribute.forwardIdentity, "users/authoredPosts", source)
    expectNoDifference(authoredPostsAttribute.reverseIdentity, "posts/author", source)
    expectNoDifference(authoredPostsAttribute.linkNamespace, "posts", source)
    expectNoDifference(slugAttribute.valueType, .string, source)
    expectNoDifference(slugAttribute.cardinality, .one, source)
    expectNoDifference(slugAttribute.isUnique, true, source)
    expectNoDifference(slugAttribute.isIndexed, true, source)
    expectNoDifference(
      snapshot.triples,
      [
        InstantTriple(
          entityID: "user-1",
          attributeID: "users/id",
          value: .string("user-1"),
          txID: "tx-instaml-schema-lookup-link-array",
          txTime: time
        )
      ],
      source
    )

    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "test-app",
        persistenceURL: cacheURL,
        initialAttributes: attributes
      )
    )
    let unresolvedResult = try await runtime.transact(transaction, createdAt: time)
    let unresolvedUsers = try await runtime.query(
      InstantQueryPlan(
        id: "schema-lookup-link-array.unresolved-users",
        namespace: "users",
        includes: [InstantQueryInclude("authoredPosts")]
      )
    )
    expectNoDifference(unresolvedResult.changedEntityIDs, ["user-1"], source)
    expectNoDifference(unresolvedResult.tripleCount, 1, source)
    expectNoDifference(unresolvedUsers.map(\.id), ["user-1"], source)
    expectNoDifference(unresolvedUsers.first?.values["authoredPosts"], nil, source)
    expectNoDifference(unresolvedUsers.first?.links?["authoredPosts"], [], source)

    let transportMutations = await runtime.outboxTransportMutations()
    expectNoDifference(transportMutations.map(\.transactionID), ["tx-instaml-schema-lookup-link-array"], source)
    let transportMutation = try #require(transportMutations.first)
    expectNoDifference(
      transportMutation.txSteps,
      [
        .addTriple(entity: .id("user-1"), attributeID: "users/id", value: .string("user-1")),
        .addTriple(
          entity: .id("user-1"),
          attributeID: "users/authoredPosts",
          value: .lookupRef(attributeID: "posts/slug", value: .string("life-is-good"))
        ),
        .addTriple(
          entity: .id("user-1"),
          attributeID: "users/authoredPosts",
          value: .lookupRef(attributeID: "posts/slug", value: .string("check-this-out"))
        ),
      ],
      source
    )

    let data = try JSONEncoder().encode(transportMutation)
    let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    let txSteps = try #require(object["txSteps"] as? [[Any]])
    expectNoDifference(txSteps.count, 3, source)
    expectNoDifference(txSteps.map { $0.first as? String }, ["add-triple", "add-triple", "add-triple"], source)
    expectNoDifference(txSteps.map(\.count), [4, 4, 4], source)
    expectNoDifference(txSteps[0][1] as? String, "user-1", source)
    expectNoDifference(txSteps[0][2] as? String, "users/id", source)
    expectNoDifference(txSteps[0][3] as? String, "user-1", source)
    expectNoDifference(txSteps[1][1] as? String, "user-1", source)
    expectNoDifference(txSteps[1][2] as? String, "users/authoredPosts", source)
    let firstLookupValue = try #require(txSteps[1][3] as? [Any])
    expectNoDifference(firstLookupValue.count, 2, source)
    expectNoDifference(firstLookupValue[0] as? String, "posts/slug", source)
    expectNoDifference(firstLookupValue[1] as? String, "life-is-good", source)
    expectNoDifference(txSteps[2][1] as? String, "user-1", source)
    expectNoDifference(txSteps[2][2] as? String, "users/authoredPosts", source)
    let secondLookupValue = try #require(txSteps[2][3] as? [Any])
    expectNoDifference(secondLookupValue.count, 2, source)
    expectNoDifference(secondLookupValue[0] as? String, "posts/slug", source)
    expectNoDifference(secondLookupValue[1] as? String, "check-this-out", source)

    try await runtime.transact(
      InstantStoreTransaction(
        id: "tx-instaml-schema-lookup-link-array-seed",
        operations: [
          .insert(
            InstantTriple(
              entityID: "post-1",
              attributeID: "posts/id",
              value: .string("post-1"),
              txID: "tx-instaml-schema-lookup-link-array-seed",
              txTime: InstantTimestamp(milliseconds: time.milliseconds + 1)
            )
          ),
          .insert(
            InstantTriple(
              entityID: "post-1",
              attributeID: "posts/slug",
              value: .string("life-is-good"),
              txID: "tx-instaml-schema-lookup-link-array-seed",
              txTime: InstantTimestamp(milliseconds: time.milliseconds + 1)
            )
          ),
          .insert(
            InstantTriple(
              entityID: "post-2",
              attributeID: "posts/id",
              value: .string("post-2"),
              txID: "tx-instaml-schema-lookup-link-array-seed",
              txTime: InstantTimestamp(milliseconds: time.milliseconds + 1)
            )
          ),
          .insert(
            InstantTriple(
              entityID: "post-2",
              attributeID: "posts/slug",
              value: .string("check-this-out"),
              txID: "tx-instaml-schema-lookup-link-array-seed",
              txTime: InstantTimestamp(milliseconds: time.milliseconds + 1)
            )
          ),
        ]
      ),
      createdAt: InstantTimestamp(milliseconds: time.milliseconds + 1)
    )
    let localResult = try await runtime.transact(
      InstantStoreTransaction(
        id: "tx-instaml-schema-lookup-link-array-local",
        operations: [
          .insert(
            InstantTriple(
              entityID: "user-1",
              attributeID: "users/authoredPosts",
              value: .lookupRef(firstPostLookup),
              txID: "tx-instaml-schema-lookup-link-array-local",
              txTime: InstantTimestamp(milliseconds: time.milliseconds + 2)
            )
          ),
          .insert(
            InstantTriple(
              entityID: "user-1",
              attributeID: "users/authoredPosts",
              value: .lookupRef(secondPostLookup),
              txID: "tx-instaml-schema-lookup-link-array-local",
              txTime: InstantTimestamp(milliseconds: time.milliseconds + 2)
            )
          ),
        ]
      ),
      createdAt: InstantTimestamp(milliseconds: time.milliseconds + 2)
    )
    let linkedUsers = try await runtime.query(
      InstantQueryPlan(
        id: "schema-lookup-link-array.users",
        namespace: "users",
        includes: [InstantQueryInclude("authoredPosts")]
      )
    )
    let linkedPosts = try await runtime.query(
      InstantQueryPlan(
        id: "schema-lookup-link-array.posts",
        namespace: "posts",
        includes: [InstantQueryInclude("author", direction: .reverse)]
      )
    )
    expectNoDifference(localResult.changedEntityIDs, Set(["post-1", "post-2", "user-1"]), source)
    expectNoDifference(localResult.tripleCount, 7, source)
    expectNoDifference(linkedUsers.map(\.id), ["user-1"], source)
    expectNoDifference(linkedUsers.first?.values["authoredPosts"]?.values, [.ref("post-1"), .ref("post-2")], source)
    expectNoDifference(linkedUsers.first?.links?["authoredPosts"]?.map(\.id), ["post-1", "post-2"], source)
    expectNoDifference(linkedPosts.map(\.id), ["post-1", "post-2"], source)
    expectNoDifference(linkedPosts.map { $0.links?["author"]?.map(\.id) }, [["user-1"], ["user-1"]], source)
  }

  @Test
  func schemaRefLookupUsesDeclaredUniqueRefAttrForInstamlParity() async throws {
    let cacheURL = try temporaryCacheURL()
    let time = InstantTimestamp(milliseconds: 1_700_000_000_000)
    let source =
      "upstream/instant/client/packages/core/__tests__/src/instaml.test.ts "
      + "Schema: lookup creates unique ref attrs for ref lookup "
      + "[adapted: Swift uses declared attrs and normalizes id attrs as indexed primary keys; ref lookup entities and id values stay lookup-shaped for transport.]"
    let attributes = [
      InstantAttribute(
        id: "users/id",
        namespace: "users",
        name: "id",
        valueType: .string,
        isRequired: false,
        isUnique: true,
        primaryKey: true
      ),
      InstantAttribute(
        id: "user_prefs/id",
        namespace: "user_prefs",
        name: "id",
        valueType: .string,
        isRequired: false,
        isUnique: true,
        primaryKey: true
      ),
      InstantAttribute(
        id: "user_prefs/user",
        namespace: "user_prefs",
        name: "user",
        valueType: .ref,
        isRequired: false,
        cardinality: .one,
        isIndexed: true,
        isUnique: true,
        forwardIdentity: "user_prefs/user",
        reverseIdentity: "users/user_pref",
        linkNamespace: "users"
      ),
    ]
    let userPrefsByUserLookup = InstantLookupRef(
      attributeID: "user_prefs/user",
      value: .ref("user-1")
    )
    let transaction = InstantStoreTransaction(
      id: "tx-instaml-schema-ref-lookup",
      operations: [
        .insert(
          InstantTriple(
            entityID: "user-1",
            attributeID: "users/id",
            value: .string("user-1"),
            txID: "tx-instaml-schema-ref-lookup",
            txTime: time
          )
        ),
        .insertByLookup(
          entity: userPrefsByUserLookup,
          attributeID: "user_prefs/id",
          value: .lookupRef(userPrefsByUserLookup),
          txID: "tx-instaml-schema-ref-lookup",
          txTime: time
        ),
      ]
    )

    let store = InstantStore(snapshot: InstantStoreSnapshot(attributes: attributes))
    _ = try await store.prepare(transaction)
    let snapshot = await store.snapshot()
    let attributesByID = Dictionary(uniqueKeysWithValues: snapshot.attributes.map { ($0.id, $0) })
    let userIDAttribute = try #require(attributesByID["users/id"])
    let userPrefIDAttribute = try #require(attributesByID["user_prefs/id"])
    let userRefAttribute = try #require(attributesByID["user_prefs/user"])
    expectNoDifference(userIDAttribute.valueType, .string, source)
    expectNoDifference(userIDAttribute.cardinality, .one, source)
    expectNoDifference(userIDAttribute.isUnique, true, source)
    expectNoDifference(userIDAttribute.isIndexed, true, source)
    expectNoDifference(userIDAttribute.primaryKey, true, source)
    expectNoDifference(userPrefIDAttribute.valueType, .string, source)
    expectNoDifference(userPrefIDAttribute.cardinality, .one, source)
    expectNoDifference(userPrefIDAttribute.isUnique, true, source)
    expectNoDifference(userPrefIDAttribute.isIndexed, true, source)
    expectNoDifference(userPrefIDAttribute.primaryKey, true, source)
    expectNoDifference(userRefAttribute.valueType, .ref, source)
    expectNoDifference(userRefAttribute.cardinality, .one, source)
    expectNoDifference(userRefAttribute.isUnique, true, source)
    expectNoDifference(userRefAttribute.isIndexed, true, source)
    expectNoDifference(userRefAttribute.forwardIdentity, "user_prefs/user", source)
    expectNoDifference(userRefAttribute.reverseIdentity, "users/user_pref", source)
    expectNoDifference(userRefAttribute.linkNamespace, "users", source)
    expectNoDifference(
      snapshot.triples,
      [
        InstantTriple(
          entityID: "user-1",
          attributeID: "users/id",
          value: .string("user-1"),
          txID: "tx-instaml-schema-ref-lookup",
          txTime: time
        )
      ],
      source
    )

    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "test-app",
        persistenceURL: cacheURL,
        initialAttributes: attributes
      )
    )
    let unresolvedResult = try await runtime.transact(transaction, createdAt: time)
    let unresolvedUsers = try await runtime.query(
      InstantQueryPlan(
        id: "schema-ref-lookup.unresolved-users",
        namespace: "users",
        includes: [InstantQueryInclude("user_pref", direction: .reverse)]
      )
    )
    let unresolvedUserPrefs = try await runtime.query(
      InstantQueryPlan(
        id: "schema-ref-lookup.unresolved-user-prefs",
        namespace: "user_prefs",
        includes: [InstantQueryInclude("user")]
      )
    )
    expectNoDifference(unresolvedResult.changedEntityIDs, ["user-1"], source)
    expectNoDifference(unresolvedResult.tripleCount, 1, source)
    expectNoDifference(unresolvedUsers.map(\.id), ["user-1"], source)
    expectNoDifference(unresolvedUsers.first?.links?["user_pref"], [], source)
    expectNoDifference(unresolvedUserPrefs, [], source)

    let transportMutations = await runtime.outboxTransportMutations()
    expectNoDifference(transportMutations.map(\.transactionID), ["tx-instaml-schema-ref-lookup"], source)
    let transportMutation = try #require(transportMutations.first)
    expectNoDifference(
      transportMutation.txSteps,
      [
        .addTriple(entity: .id("user-1"), attributeID: "users/id", value: .string("user-1")),
        .addTriple(
          entity: .lookup(userPrefsByUserLookup),
          attributeID: "user_prefs/id",
          value: .lookupRef(attributeID: "user_prefs/user", value: .string("user-1"))
        ),
      ],
      source
    )

    let data = try JSONEncoder().encode(transportMutation)
    let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    let txSteps = try #require(object["txSteps"] as? [[Any]])
    expectNoDifference(txSteps.count, 2, source)
    expectNoDifference(txSteps.map { $0.first as? String }, ["add-triple", "add-triple"], source)
    expectNoDifference(txSteps.map(\.count), [4, 4], source)
    expectNoDifference(txSteps[0][1] as? String, "user-1", source)
    expectNoDifference(txSteps[0][2] as? String, "users/id", source)
    expectNoDifference(txSteps[0][3] as? String, "user-1", source)
    let lookupEntity = try #require(txSteps[1][1] as? [Any])
    expectNoDifference(lookupEntity.count, 2, source)
    expectNoDifference(lookupEntity[0] as? String, "user_prefs/user", source)
    expectNoDifference(lookupEntity[1] as? String, "user-1", source)
    expectNoDifference(txSteps[1][2] as? String, "user_prefs/id", source)
    let lookupValue = try #require(txSteps[1][3] as? [Any])
    expectNoDifference(lookupValue.count, 2, source)
    expectNoDifference(lookupValue[0] as? String, "user_prefs/user", source)
    expectNoDifference(lookupValue[1] as? String, "user-1", source)

    try await runtime.transact(
      InstantStoreTransaction(
        id: "tx-instaml-schema-ref-lookup-seed",
        operations: [
          .insert(
            InstantTriple(
              entityID: "user_pref-1",
              attributeID: "user_prefs/user",
              value: .ref("user-1"),
              txID: "tx-instaml-schema-ref-lookup-seed",
              txTime: InstantTimestamp(milliseconds: time.milliseconds + 1)
            )
          )
        ]
      ),
      createdAt: InstantTimestamp(milliseconds: time.milliseconds + 1)
    )
    let localResult = try await runtime.transact(
      InstantStoreTransaction(
        id: "tx-instaml-schema-ref-lookup-local",
        operations: [
          .insertByLookup(
            entity: userPrefsByUserLookup,
            attributeID: "user_prefs/id",
            value: .lookupRef(userPrefsByUserLookup),
            txID: "tx-instaml-schema-ref-lookup-local",
            txTime: InstantTimestamp(milliseconds: time.milliseconds + 2)
          )
        ]
      ),
      createdAt: InstantTimestamp(milliseconds: time.milliseconds + 2)
    )
    let linkedUsers = try await runtime.query(
      InstantQueryPlan(
        id: "schema-ref-lookup.users",
        namespace: "users",
        includes: [InstantQueryInclude("user_pref", direction: .reverse)]
      )
    )
    let linkedUserPrefs = try await runtime.query(
      InstantQueryPlan(
        id: "schema-ref-lookup.user-prefs",
        namespace: "user_prefs",
        includes: [InstantQueryInclude("user")]
      )
    )
    expectNoDifference(localResult.changedEntityIDs, ["user_pref-1"], source)
    expectNoDifference(localResult.tripleCount, 3, source)
    expectNoDifference(linkedUsers.map(\.id), ["user-1"], source)
    expectNoDifference(linkedUsers.first?.links?["user_pref"]?.map(\.id), ["user_pref-1"], source)
    expectNoDifference(linkedUserPrefs.map(\.id), ["user_pref-1"], source)
    expectNoDifference(linkedUserPrefs.first?.values["id"]?.first, .string("user_pref-1"), source)
    expectNoDifference(linkedUserPrefs.first?.values["user"]?.values, [.ref("user-1")], source)
    expectNoDifference(linkedUserPrefs.first?.links?["user"]?.map(\.id), ["user-1"], source)
  }

  @Test
  func schemaRefLookupInLinkValueUsesReverseIdentityForInstamlParity() async throws {
    let cacheURL = try temporaryCacheURL()
    let time = InstantTimestamp(milliseconds: 1_700_000_000_000)
    let source =
      "upstream/instant/client/packages/core/__tests__/src/instaml.test.ts "
      + "Schema: lookup creates unique ref attrs for ref lookup in link value "
      + "[adapted: Swift uses declared attrs, normalizes id attrs as indexed primary keys, and resolves reverse-identity lookup refs through the forward ref attr.]"
    let attributes = [
      InstantAttribute(
        id: "users/id",
        namespace: "users",
        name: "id",
        valueType: .string,
        isRequired: false,
        isUnique: true,
        primaryKey: true
      ),
      InstantAttribute(
        id: "user_prefs/id",
        namespace: "user_prefs",
        name: "id",
        valueType: .string,
        isRequired: false,
        isUnique: true,
        primaryKey: true
      ),
      InstantAttribute(
        id: "users/user_pref",
        namespace: "users",
        name: "user_pref",
        valueType: .ref,
        isRequired: false,
        cardinality: .one,
        isIndexed: true,
        isUnique: true,
        forwardIdentity: "users/user_pref",
        reverseIdentity: "user_prefs/user",
        linkNamespace: "user_prefs"
      ),
    ]
    let userPrefByUserLookup = InstantLookupRef(
      attributeID: "user_prefs/user",
      value: .ref("user-1")
    )
    let transaction = InstantStoreTransaction(
      id: "tx-instaml-schema-ref-lookup-link-value",
      operations: [
        .insert(
          InstantTriple(
            entityID: "user-1",
            attributeID: "users/id",
            value: .string("user-1"),
            txID: "tx-instaml-schema-ref-lookup-link-value",
            txTime: time
          )
        ),
        .insert(
          InstantTriple(
            entityID: "user-1",
            attributeID: "users/user_pref",
            value: .lookupRef(userPrefByUserLookup),
            txID: "tx-instaml-schema-ref-lookup-link-value",
            txTime: time
          )
        ),
      ]
    )

    let store = InstantStore(snapshot: InstantStoreSnapshot(attributes: attributes))
    _ = try await store.prepare(transaction)
    let snapshot = await store.snapshot()
    let attributesByID = Dictionary(uniqueKeysWithValues: snapshot.attributes.map { ($0.id, $0) })
    let userIDAttribute = try #require(attributesByID["users/id"])
    let userPrefIDAttribute = try #require(attributesByID["user_prefs/id"])
    let userPrefAttribute = try #require(attributesByID["users/user_pref"])
    expectNoDifference(userIDAttribute.valueType, .string, source)
    expectNoDifference(userIDAttribute.cardinality, .one, source)
    expectNoDifference(userIDAttribute.isUnique, true, source)
    expectNoDifference(userIDAttribute.isIndexed, true, source)
    expectNoDifference(userIDAttribute.primaryKey, true, source)
    expectNoDifference(userPrefIDAttribute.valueType, .string, source)
    expectNoDifference(userPrefIDAttribute.cardinality, .one, source)
    expectNoDifference(userPrefIDAttribute.isUnique, true, source)
    expectNoDifference(userPrefIDAttribute.isIndexed, true, source)
    expectNoDifference(userPrefIDAttribute.primaryKey, true, source)
    expectNoDifference(userPrefAttribute.valueType, .ref, source)
    expectNoDifference(userPrefAttribute.cardinality, .one, source)
    expectNoDifference(userPrefAttribute.isUnique, true, source)
    expectNoDifference(userPrefAttribute.isIndexed, true, source)
    expectNoDifference(userPrefAttribute.forwardIdentity, "users/user_pref", source)
    expectNoDifference(userPrefAttribute.reverseIdentity, "user_prefs/user", source)
    expectNoDifference(userPrefAttribute.linkNamespace, "user_prefs", source)
    expectNoDifference(
      snapshot.triples,
      [
        InstantTriple(
          entityID: "user-1",
          attributeID: "users/id",
          value: .string("user-1"),
          txID: "tx-instaml-schema-ref-lookup-link-value",
          txTime: time
        )
      ],
      source
    )

    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "test-app",
        persistenceURL: cacheURL,
        initialAttributes: attributes
      )
    )
    let unresolvedResult = try await runtime.transact(transaction, createdAt: time)
    let unresolvedUsers = try await runtime.query(
      InstantQueryPlan(
        id: "schema-ref-lookup-link-value.unresolved-users",
        namespace: "users",
        includes: [InstantQueryInclude("user_pref")]
      )
    )
    let unresolvedUserPrefs = try await runtime.query(
      InstantQueryPlan(
        id: "schema-ref-lookup-link-value.unresolved-user-prefs",
        namespace: "user_prefs",
        includes: [InstantQueryInclude("user", direction: .reverse)]
      )
    )
    expectNoDifference(unresolvedResult.changedEntityIDs, ["user-1"], source)
    expectNoDifference(unresolvedResult.tripleCount, 1, source)
    expectNoDifference(unresolvedUsers.map(\.id), ["user-1"], source)
    expectNoDifference(unresolvedUsers.first?.values["user_pref"], nil, source)
    expectNoDifference(unresolvedUsers.first?.links?["user_pref"], [], source)
    expectNoDifference(unresolvedUserPrefs, [], source)

    let transportMutations = await runtime.outboxTransportMutations()
    expectNoDifference(
      transportMutations.map(\.transactionID),
      ["tx-instaml-schema-ref-lookup-link-value"],
      source
    )
    let transportMutation = try #require(transportMutations.first)
    expectNoDifference(
      transportMutation.txSteps,
      [
        .addTriple(entity: .id("user-1"), attributeID: "users/id", value: .string("user-1")),
        .addTriple(
          entity: .id("user-1"),
          attributeID: "users/user_pref",
          value: .lookupRef(attributeID: "user_prefs/user", value: .string("user-1"))
        ),
      ],
      source
    )

    let data = try JSONEncoder().encode(transportMutation)
    let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    let txSteps = try #require(object["txSteps"] as? [[Any]])
    expectNoDifference(txSteps.count, 2, source)
    expectNoDifference(txSteps.map { $0.first as? String }, ["add-triple", "add-triple"], source)
    expectNoDifference(txSteps.map(\.count), [4, 4], source)
    expectNoDifference(txSteps[0][1] as? String, "user-1", source)
    expectNoDifference(txSteps[0][2] as? String, "users/id", source)
    expectNoDifference(txSteps[0][3] as? String, "user-1", source)
    expectNoDifference(txSteps[1][1] as? String, "user-1", source)
    expectNoDifference(txSteps[1][2] as? String, "users/user_pref", source)
    let lookupValue = try #require(txSteps[1][3] as? [Any])
    expectNoDifference(lookupValue.count, 2, source)
    expectNoDifference(lookupValue[0] as? String, "user_prefs/user", source)
    expectNoDifference(lookupValue[1] as? String, "user-1", source)

    try await runtime.transact(
      InstantStoreTransaction(
        id: "tx-instaml-schema-ref-lookup-link-value-seed",
        operations: [
          .insert(
            InstantTriple(
              entityID: "user_pref-1",
              attributeID: "user_prefs/id",
              value: .string("user_pref-1"),
              txID: "tx-instaml-schema-ref-lookup-link-value-seed",
              txTime: InstantTimestamp(milliseconds: time.milliseconds + 1)
            )
          ),
          .insert(
            InstantTriple(
              entityID: "user-1",
              attributeID: "users/user_pref",
              value: .ref("user_pref-1"),
              txID: "tx-instaml-schema-ref-lookup-link-value-seed",
              txTime: InstantTimestamp(milliseconds: time.milliseconds + 1)
            )
          ),
        ]
      ),
      createdAt: InstantTimestamp(milliseconds: time.milliseconds + 1)
    )
    let localResult = try await runtime.transact(
      InstantStoreTransaction(
        id: "tx-instaml-schema-ref-lookup-link-value-local",
        operations: [
          .insert(
            InstantTriple(
              entityID: "user-1",
              attributeID: "users/user_pref",
              value: .lookupRef(userPrefByUserLookup),
              txID: "tx-instaml-schema-ref-lookup-link-value-local",
              txTime: InstantTimestamp(milliseconds: time.milliseconds + 2)
            )
          )
        ]
      ),
      createdAt: InstantTimestamp(milliseconds: time.milliseconds + 2)
    )
    let linkedUsers = try await runtime.query(
      InstantQueryPlan(
        id: "schema-ref-lookup-link-value.users",
        namespace: "users",
        includes: [InstantQueryInclude("user_pref")]
      )
    )
    let linkedUserPrefs = try await runtime.query(
      InstantQueryPlan(
        id: "schema-ref-lookup-link-value.user-prefs",
        namespace: "user_prefs",
        includes: [InstantQueryInclude("user", direction: .reverse)]
      )
    )
    expectNoDifference(localResult.changedEntityIDs, Set(["user-1", "user_pref-1"]), source)
    expectNoDifference(localResult.tripleCount, 3, source)
    expectNoDifference(linkedUsers.map(\.id), ["user-1"], source)
    expectNoDifference(linkedUsers.first?.values["user_pref"]?.values, [.ref("user_pref-1")], source)
    expectNoDifference(linkedUsers.first?.links?["user_pref"]?.map(\.id), ["user_pref-1"], source)
    expectNoDifference(linkedUserPrefs.map(\.id), ["user_pref-1"], source)
    expectNoDifference(linkedUserPrefs.first?.links?["user"]?.map(\.id), ["user-1"], source)
  }

  @Test
  func schemaCheckedDataTypesPreserveInstamlScalarMetadata() async throws {
    let cacheURL = try temporaryCacheURL()
    let time = InstantTimestamp(milliseconds: 1_700_000_000_000)
    let date = Date(timeIntervalSince1970: 1_700_000_000)
    let source =
      "upstream/instant/client/packages/core/__tests__/src/instaml.test.ts "
      + "Schema: populates checked-data-type "
      + "[adapted: Swift preserves checked scalar metadata as value types, models i.any() explicitly, and applies local type validation before persistence.]"
    let attributes = [
      InstantAttribute(
        id: "comments/s",
        namespace: "comments",
        name: "s",
        valueType: .string,
        isRequired: false
      ),
      InstantAttribute(
        id: "comments/n",
        namespace: "comments",
        name: "n",
        valueType: .number,
        isRequired: false
      ),
      InstantAttribute(
        id: "comments/d",
        namespace: "comments",
        name: "d",
        valueType: .date,
        isRequired: false
      ),
      InstantAttribute(
        id: "comments/b",
        namespace: "comments",
        name: "b",
        valueType: .boolean,
        isRequired: false
      ),
      InstantAttribute(
        id: "comments/a",
        namespace: "comments",
        name: "a",
        valueType: .any,
        isRequired: false
      ),
      InstantAttribute(
        id: "comments/j",
        namespace: "comments",
        name: "j",
        valueType: .json,
        isRequired: false
      ),
    ]
    let transportOnlyTransaction = InstantStoreTransaction(
      id: "tx-instaml-schema-checked-types-transport",
      operations: [
        .insert(
          InstantTriple(
            entityID: "comment-1",
            attributeID: "comments/id",
            value: .string("comment-1"),
            txID: "tx-instaml-schema-checked-types-transport",
            txTime: time
          )
        ),
        .insert(
          InstantTriple(
            entityID: "comment-1",
            attributeID: "comments/s",
            value: .string("str"),
            txID: "tx-instaml-schema-checked-types-transport",
            txTime: time
          )
        ),
        .insert(
          InstantTriple(
            entityID: "comment-1",
            attributeID: "comments/n",
            value: .string("num"),
            txID: "tx-instaml-schema-checked-types-transport",
            txTime: time
          )
        ),
        .insert(
          InstantTriple(
            entityID: "comment-1",
            attributeID: "comments/d",
            value: .string("date"),
            txID: "tx-instaml-schema-checked-types-transport",
            txTime: time
          )
        ),
        .insert(
          InstantTriple(
            entityID: "comment-1",
            attributeID: "comments/b",
            value: .string("bool"),
            txID: "tx-instaml-schema-checked-types-transport",
            txTime: time
          )
        ),
        .insert(
          InstantTriple(
            entityID: "comment-1",
            attributeID: "comments/a",
            value: .string("any"),
            txID: "tx-instaml-schema-checked-types-transport",
            txTime: time
          )
        ),
        .insert(
          InstantTriple(
            entityID: "comment-1",
            attributeID: "comments/j",
            value: .string("json"),
            txID: "tx-instaml-schema-checked-types-transport",
            txTime: time
          )
        ),
      ]
    )
    let runtimeTransaction = InstantStoreTransaction(
      id: "tx-instaml-schema-checked-types",
      operations: [
        .insert(
          InstantTriple(
            entityID: "comment-1",
            attributeID: "comments/id",
            value: .string("comment-1"),
            txID: "tx-instaml-schema-checked-types",
            txTime: time
          )
        ),
        .insert(
          InstantTriple(
            entityID: "comment-1",
            attributeID: "comments/s",
            value: .string("str"),
            txID: "tx-instaml-schema-checked-types",
            txTime: time
          )
        ),
        .insert(
          InstantTriple(
            entityID: "comment-1",
            attributeID: "comments/n",
            value: .number(42),
            txID: "tx-instaml-schema-checked-types",
            txTime: time
          )
        ),
        .insert(
          InstantTriple(
            entityID: "comment-1",
            attributeID: "comments/d",
            value: .date(date),
            txID: "tx-instaml-schema-checked-types",
            txTime: time
          )
        ),
        .insert(
          InstantTriple(
            entityID: "comment-1",
            attributeID: "comments/b",
            value: .bool(true),
            txID: "tx-instaml-schema-checked-types",
            txTime: time
          )
        ),
        .insert(
          InstantTriple(
            entityID: "comment-1",
            attributeID: "comments/a",
            value: .json(.object(["kind": .string("any"), "count": .number(1)])),
            txID: "tx-instaml-schema-checked-types",
            txTime: time
          )
        ),
        .insert(
          InstantTriple(
            entityID: "comment-1",
            attributeID: "comments/j",
            value: .json(.string("json")),
            txID: "tx-instaml-schema-checked-types",
            txTime: time
          )
        ),
      ]
    )

    let store = InstantStore(snapshot: InstantStoreSnapshot(attributes: attributes))
    _ = try await store.prepare(runtimeTransaction)
    let snapshot = await store.snapshot()
    let attributesByID = Dictionary(uniqueKeysWithValues: snapshot.attributes.map { ($0.id, $0) })
    expectNoDifference(
      attributesByID.mapValues(\.valueType),
      [
        "comments/a": .any,
        "comments/b": .boolean,
        "comments/d": .date,
        "comments/id": .string,
        "comments/j": .json,
        "comments/n": .number,
        "comments/s": .string,
      ],
      source
    )
    let primaryKey = try #require(attributesByID["comments/id"])
    expectNoDifference(primaryKey.isUnique, true, source)
    expectNoDifference(primaryKey.isIndexed, true, source)
    expectNoDifference(primaryKey.primaryKey, true, source)

    let transportOnlyMutation = InstantTransportMutation(
      PendingMutation(
        id: "mutation-instaml-schema-checked-types-transport",
        createdAt: time,
        transaction: transportOnlyTransaction
      )
    )
    expectNoDifference(
      transportOnlyMutation.txSteps,
      [
        .addTriple(entity: .id("comment-1"), attributeID: "comments/id", value: .string("comment-1")),
        .addTriple(entity: .id("comment-1"), attributeID: "comments/s", value: .string("str")),
        .addTriple(entity: .id("comment-1"), attributeID: "comments/n", value: .string("num")),
        .addTriple(entity: .id("comment-1"), attributeID: "comments/d", value: .string("date")),
        .addTriple(entity: .id("comment-1"), attributeID: "comments/b", value: .string("bool")),
        .addTriple(entity: .id("comment-1"), attributeID: "comments/a", value: .string("any")),
        .addTriple(entity: .id("comment-1"), attributeID: "comments/j", value: .string("json")),
      ],
      source
    )

    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "test-app",
        persistenceURL: cacheURL,
        initialAttributes: attributes
      )
    )
    let result = try await runtime.transact(runtimeTransaction, createdAt: time)
    let comments = try await runtime.query(
      InstantQueryPlan(id: "schema-checked-types.comments", namespace: "comments")
    )
    let transportMutations = await runtime.outboxTransportMutations()
    let transportMutation = try #require(transportMutations.first)

    expectNoDifference(result.changedEntityIDs, Set(["comment-1"]), source)
    expectNoDifference(result.tripleCount, 7, source)
    expectNoDifference(comments.map(\.id), ["comment-1"], source)
    expectNoDifference(comments.first?.values["s"]?.first, .string("str"), source)
    expectNoDifference(comments.first?.values["n"]?.first, .number(42), source)
    expectNoDifference(comments.first?.values["d"]?.first, .date(date), source)
    expectNoDifference(comments.first?.values["b"]?.first, .bool(true), source)
    expectNoDifference(
      comments.first?.values["a"]?.first,
      .json(.object(["count": .number(1), "kind": .string("any")])),
      source
    )
    expectNoDifference(comments.first?.values["j"]?.first, .json(.string("json")), source)
    expectNoDifference(
      transportMutation.txSteps,
      [
        .addTriple(entity: .id("comment-1"), attributeID: "comments/id", value: .string("comment-1")),
        .addTriple(entity: .id("comment-1"), attributeID: "comments/s", value: .string("str")),
        .addTriple(entity: .id("comment-1"), attributeID: "comments/n", value: .number(42)),
        .addTriple(
          entity: .id("comment-1"),
          attributeID: "comments/d",
          value: InstantTransportValue(InstantValue.date(date))
        ),
        .addTriple(entity: .id("comment-1"), attributeID: "comments/b", value: .bool(true)),
        .addTriple(
          entity: .id("comment-1"),
          attributeID: "comments/a",
          value: .object(["count": .number(1), "kind": .string("any")])
        ),
        .addTriple(entity: .id("comment-1"), attributeID: "comments/j", value: .string("json")),
      ],
      source
    )
  }

  @Test
  func anyValueTypeAcceptsNonLinkPayloadsAndRejectsRefs() async throws {
    let time = InstantTimestamp(milliseconds: 1_700_000_000_000)
    let date = Date(timeIntervalSince1970: 1_700_000_000)
    let source = "InstantValueType.any accepts any non-link payload but does not model relationships."
    let attributes = [
      InstantAttribute(
        id: "comments/slug",
        namespace: "comments",
        name: "slug",
        valueType: .string,
        isRequired: false,
        isIndexed: true,
        isUnique: true
      ),
      InstantAttribute(
        id: "comments/a",
        namespace: "comments",
        name: "a",
        valueType: .any,
        isRequired: false
      )
    ]
    let store = InstantStore(snapshot: InstantStoreSnapshot(attributes: attributes))
    _ = try await store.prepare(
      InstantStoreTransaction(
        id: "tx-any-payloads",
        operations: [
          .insert(
            InstantTriple(
              entityID: "comment-string",
              attributeID: "comments/slug",
              value: .string("slug-1"),
              txID: "tx-any-payloads",
              txTime: time
            )
          ),
          .insert(
            InstantTriple(
              entityID: "comment-string",
              attributeID: "comments/a",
              value: .string("any"),
              txID: "tx-any-payloads",
              txTime: time
            )
          ),
          .insert(
            InstantTriple(
              entityID: "comment-number",
              attributeID: "comments/a",
              value: .number(42),
              txID: "tx-any-payloads",
              txTime: time
            )
          ),
          .insert(
            InstantTriple(
              entityID: "comment-bool",
              attributeID: "comments/a",
              value: .bool(false),
              txID: "tx-any-payloads",
              txTime: time
            )
          ),
          .insert(
            InstantTriple(
              entityID: "comment-date",
              attributeID: "comments/a",
              value: .date(date),
              txID: "tx-any-payloads",
              txTime: time
            )
          ),
          .insert(
            InstantTriple(
              entityID: "comment-json",
              attributeID: "comments/a",
              value: .json(.object(["kind": .string("json")])),
              txID: "tx-any-payloads",
              txTime: time
            )
          ),
        ]
      )
    )
    let snapshot = await store.snapshot()
    let valuesByEntityID = Dictionary(
      uniqueKeysWithValues: snapshot.triples
        .filter { $0.attributeID == "comments/a" }
        .map { ($0.entityID, $0.value) }
    )
    expectNoDifference(
      valuesByEntityID,
      [
        "comment-bool": .bool(false),
        "comment-date": .date(date),
        "comment-json": .json(.object(["kind": .string("json")])),
        "comment-number": .number(42),
        "comment-string": .string("any"),
      ],
      source
    )

    do {
      _ = try await store.prepare(
        InstantStoreTransaction(
          id: "tx-any-ref",
          operations: [
            .insert(
              InstantTriple(
                entityID: "comment-ref",
                attributeID: "comments/a",
                value: .ref("book-1"),
                txID: "tx-any-ref",
                txTime: time
              )
            )
          ]
        )
      )
      #expect(Bool(false), "Expected .any to reject ref payloads.")
    } catch let error as InstantError {
      expectNoDifference(error.code, .validationFailed, source)
      expectNoDifference(error.operation, "write entity attribute", source)
      expectNoDifference(error.path, "a", source)
    } catch {
      #expect(Bool(false), "Unexpected error: \(error)")
    }

    do {
      _ = try await store.prepare(
        InstantStoreTransaction(
          id: "tx-any-lookup-ref",
          operations: [
            .insert(
              InstantTriple(
                entityID: "comment-lookup-ref",
                attributeID: "comments/a",
                value: .lookupRef(
                  InstantLookupRef(attributeID: "comments/slug", value: .string("slug-1"))
                ),
                txID: "tx-any-lookup-ref",
                txTime: time
              )
            )
          ]
        )
      )
      #expect(Bool(false), "Expected .any to reject lookup ref payloads.")
    } catch let error as InstantError {
      expectNoDifference(error.code, .validationFailed, source)
      expectNoDifference(error.operation, "resolve lookup ref", source)
      expectNoDifference(error.path, "a", source)
    } catch {
      #expect(Bool(false), "Unexpected error: \(error)")
    }
  }

  @Test
  func deleteEntityByReverseIdentityLookupUsesResolvedNamespace() async throws {
    let time = InstantTimestamp(milliseconds: 1_700_000_000_000)
    let attributes = [
      InstantAttribute(
        id: "users/id",
        namespace: "users",
        name: "id",
        valueType: .string,
        isRequired: false,
        isUnique: true,
        primaryKey: true
      ),
      InstantAttribute(
        id: "user_prefs/id",
        namespace: "user_prefs",
        name: "id",
        valueType: .string,
        isRequired: false,
        isUnique: true,
        primaryKey: true
      ),
      InstantAttribute(
        id: "users/user_pref",
        namespace: "users",
        name: "user_pref",
        valueType: .ref,
        isRequired: false,
        cardinality: .one,
        isIndexed: true,
        isUnique: true,
        forwardIdentity: "users/user_pref",
        reverseIdentity: "user_prefs/user",
        linkNamespace: "user_prefs"
      ),
      InstantAttribute(
        id: "profiles/id",
        namespace: "profiles",
        name: "id",
        valueType: .string,
        isRequired: false,
        isUnique: true,
        primaryKey: true
      ),
      InstantAttribute(
        id: "profiles/nickname",
        namespace: "profiles",
        name: "nickname",
        valueType: .string,
        isRequired: false
      ),
    ]
    let initialTriples = [
      InstantTriple(
        entityID: "user-1",
        attributeID: "users/id",
        value: .string("user-1"),
        txID: "tx-seed",
        txTime: time
      ),
      InstantTriple(
        entityID: "user_pref-1",
        attributeID: "user_prefs/id",
        value: .string("user_pref-1"),
        txID: "tx-seed",
        txTime: time
      ),
      InstantTriple(
        entityID: "user-1",
        attributeID: "users/user_pref",
        value: .ref("user_pref-1"),
        txID: "tx-seed",
        txTime: time
      ),
      InstantTriple(
        entityID: "user_pref-1",
        attributeID: "profiles/id",
        value: .string("user_pref-1"),
        txID: "tx-seed",
        txTime: time
      ),
      InstantTriple(
        entityID: "user_pref-1",
        attributeID: "profiles/nickname",
        value: .string("kept"),
        txID: "tx-seed",
        txTime: time
      ),
    ]
    let store = InstantStore(
      snapshot: InstantStoreSnapshot(attributes: attributes, triples: initialTriples)
    )

    let result = try await store.prepare(
      InstantStoreTransaction(
        id: "tx-delete-user-pref-by-reverse-lookup",
        operations: [
          .deleteEntityByLookup(
            InstantLookupRef(
              attributeID: "user_prefs/user",
              value: .ref("user-1")
            )
          )
        ]
      )
    ).result
    let snapshot = await store.snapshot()

    expectNoDifference(result.changedEntityIDs, Set(["user-1", "user_pref-1"]))
    expectNoDifference(result.tripleCount, 3)
    expectNoDifference(
      snapshot.triples,
      [
        InstantTriple(
          entityID: "user-1",
          attributeID: "users/id",
          value: .string("user-1"),
          txID: "tx-seed",
          txTime: time
        ),
        InstantTriple(
          entityID: "user_pref-1",
          attributeID: "profiles/id",
          value: .string("user_pref-1"),
          txID: "tx-seed",
          txTime: time
        ),
        InstantTriple(
          entityID: "user_pref-1",
          attributeID: "profiles/nickname",
          value: .string("kept"),
          txID: "tx-seed",
          txTime: time
        ),
      ]
    )
  }

  @Test
  func transportMutationPreservesLookupEntitiesForInstamlLinkAndUnlinkParity() throws {
    let txTime = InstantTimestamp(milliseconds: 1_700_000_000_000)
    let userLookup = InstantLookupRef(
      attributeID: "users/handle",
      value: .string("bobby_newuser")
    )
    let linkMutation = InstantTransportMutation(
      PendingMutation(
        id: "tx-lookup-link-transport",
        createdAt: txTime,
        transaction: InstantStoreTransaction(
          id: "tx-lookup-link-transport",
          operations: [
            .insertByLookup(
              entity: userLookup,
              attributeID: "users/id",
              value: .lookupRef(userLookup),
              txID: "tx-lookup-link-transport",
              txTime: txTime
            ),
            .insertByLookup(
              entity: userLookup,
              attributeID: "users/bookshelves",
              value: .ref("bookshelf-1"),
              txID: "tx-lookup-link-transport",
              txTime: txTime
            ),
          ]
        )
      )
    )
    let unlinkMutation = InstantTransportMutation(
      PendingMutation(
        id: "tx-lookup-unlink-transport",
        createdAt: txTime,
        transaction: InstantStoreTransaction(
          id: "tx-lookup-unlink-transport",
          operations: [
            .insertByLookup(
              entity: userLookup,
              attributeID: "users/id",
              value: .lookupRef(userLookup),
              txID: "tx-lookup-unlink-transport",
              txTime: txTime
            ),
            .retractByLookup(
              entity: userLookup,
              attributeID: "users/bookshelves",
              value: .ref("bookshelf-1"),
              txID: "tx-lookup-unlink-transport",
              txTime: txTime
            ),
          ]
        )
      )
    )

    let source =
      "upstream/instant/client/packages/core/__tests__/src/instaml.test.ts "
      + "lookups create entities from links / lookups create entities from unlinks "
      + "[adapted: Swift writes declared attr ids directly and preserves lookup-shaped entity refs.]"
    expectNoDifference(linkMutation.preconditions, [], source)
    expectNoDifference(
      linkMutation.txSteps,
      [
        .addTriple(
          entity: .lookup(userLookup),
          attributeID: "users/id",
          value: .lookupRef(attributeID: "users/handle", value: .string("bobby_newuser"))
        ),
        .addTriple(
          entity: .lookup(userLookup),
          attributeID: "users/bookshelves",
          value: .string("bookshelf-1")
        ),
      ],
      source
    )
    expectNoDifference(unlinkMutation.preconditions, [], source)
    expectNoDifference(
      unlinkMutation.txSteps,
      [
        .addTriple(
          entity: .lookup(userLookup),
          attributeID: "users/id",
          value: .lookupRef(attributeID: "users/handle", value: .string("bobby_newuser"))
        ),
        .retractTriple(
          entity: .lookup(userLookup),
          attributeID: "users/bookshelves",
          value: .string("bookshelf-1")
        ),
      ],
      source
    )

    let linkData = try JSONEncoder().encode(linkMutation)
    let linkObject = try #require(JSONSerialization.jsonObject(with: linkData) as? [String: Any])
    let linkTxSteps = try #require(linkObject["txSteps"] as? [[Any]])
    expectNoDifference(linkTxSteps.count, 2, source)
    let linkIDEntity = try #require(linkTxSteps[0][1] as? [Any])
    expectNoDifference(linkIDEntity.count, 2, source)
    expectNoDifference(linkIDEntity[0] as? String, "users/handle", source)
    expectNoDifference(linkIDEntity[1] as? String, "bobby_newuser", source)
    let linkIDValue = try #require(linkTxSteps[0][3] as? [Any])
    expectNoDifference(linkIDValue.count, 2, source)
    expectNoDifference(linkIDValue[0] as? String, "users/handle", source)
    expectNoDifference(linkIDValue[1] as? String, "bobby_newuser", source)
    let linkEntity = try #require(linkTxSteps[1][1] as? [Any])
    expectNoDifference(linkEntity.count, 2, source)
    expectNoDifference(linkEntity[0] as? String, "users/handle", source)
    expectNoDifference(linkEntity[1] as? String, "bobby_newuser", source)
    expectNoDifference(linkTxSteps[1][3] as? String, "bookshelf-1", source)

    let unlinkData = try JSONEncoder().encode(unlinkMutation)
    let unlinkObject = try #require(
      JSONSerialization.jsonObject(with: unlinkData) as? [String: Any]
    )
    let unlinkTxSteps = try #require(unlinkObject["txSteps"] as? [[Any]])
    expectNoDifference(unlinkTxSteps.count, 2, source)
    let unlinkIDEntity = try #require(unlinkTxSteps[0][1] as? [Any])
    expectNoDifference(unlinkIDEntity.count, 2, source)
    expectNoDifference(unlinkIDEntity[0] as? String, "users/handle", source)
    expectNoDifference(unlinkIDEntity[1] as? String, "bobby_newuser", source)
    let unlinkIDValue = try #require(unlinkTxSteps[0][3] as? [Any])
    expectNoDifference(unlinkIDValue.count, 2, source)
    expectNoDifference(unlinkIDValue[0] as? String, "users/handle", source)
    expectNoDifference(unlinkIDValue[1] as? String, "bobby_newuser", source)
    expectNoDifference(unlinkTxSteps[1][0] as? String, "retract-triple", source)
    let unlinkEntity = try #require(unlinkTxSteps[1][1] as? [Any])
    expectNoDifference(unlinkEntity.count, 2, source)
    expectNoDifference(unlinkEntity[0] as? String, "users/handle", source)
    expectNoDifference(unlinkEntity[1] as? String, "bobby_newuser", source)
    expectNoDifference(unlinkTxSteps[1][3] as? String, "bookshelf-1", source)
  }

  @Test
  func transportMutationPreservesRuleParamsByLookup() throws {
    let txTime = InstantTimestamp(milliseconds: 1_700_000_000_000)
    let lookup = InstantLookupRef(
      attributeID: "users/email",
      value: .string("blob@example.com")
    )
    let params = JSONValue.object([
      "role": .string("editor"),
      "scopes": .array([.string("todos"), .string("projects")]),
    ])
    let transaction = InstantStoreTransaction(
      id: "tx-rule-params-lookup-transport",
      operations: [
        .ruleParamsByLookup(
          entity: lookup,
          namespace: "users",
          params: params
        )
      ]
    )
    let transportMutation = InstantTransportMutation(
      PendingMutation(
        id: "tx-rule-params-lookup-transport",
        createdAt: txTime,
        transaction: transaction
      )
    )

    expectNoDifference(transportMutation.preconditions, [])
    expectNoDifference(
      transportMutation.txSteps,
      [
        .ruleParams(
          entity: .lookup(lookup),
          namespace: "users",
          params: InstantTransportValue(params)
        )
      ]
    )

    let data = try JSONEncoder().encode(transportMutation)
    let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    let txSteps = try #require(object["txSteps"] as? [[Any]])
    expectNoDifference(txSteps.count, 1)
    expectNoDifference(txSteps[0].count, 4)
    expectNoDifference(txSteps[0][0] as? String, "rule-params")
    let lookupEntity = try #require(txSteps[0][1] as? [Any])
    expectNoDifference(lookupEntity.count, 2)
    expectNoDifference(lookupEntity[0] as? String, "users/email")
    expectNoDifference(lookupEntity[1] as? String, "blob@example.com")
    expectNoDifference(txSteps[0][2] as? String, "users")
    let encodedParams = try #require(txSteps[0][3] as? [String: Any])
    expectNoDifference(encodedParams.keys.sorted(), ["role", "scopes"])
    expectNoDifference(encodedParams["role"] as? String, "editor")
    expectNoDifference(encodedParams["scopes"] as? [String], ["todos", "projects"])
  }

  @Test
  func transportMutationPreservesTripleExistsPreconditions() throws {
    let txTime = InstantTimestamp(milliseconds: 1_700_000_000_000)
    let transaction = InstantStoreTransaction(
      id: "tx-syncup-transport-guard",
      operations: SyncUpsExample.replaceAttendeesOperations(
        syncUpID: "syncup-a",
        existingAttendeeIDs: ["attendee-b"],
        newAttendees: [SyncUpAttendeeDraft(id: "attendee-a-new", name: "A New")],
        updatedAt: txTime,
        transactionID: "tx-syncup-transport-guard"
      )
    )
    let mutation = InstantTransportMutation(
      PendingMutation(id: "tx-syncup-transport-guard", createdAt: txTime, transaction: transaction)
    )

    let data = try JSONEncoder().encode(mutation)
    let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    let preconditions = try #require(object["preconditions"] as? [[String: Any]])
    let tripleExists = try #require(
      preconditions.first { precondition in
        precondition["kind"] as? String == "triple-exists"
      }
    )
    expectNoDifference(tripleExists["entity"] as? String, "attendee-b")
    expectNoDifference(tripleExists["attributeID"] as? String, "attendees/syncUp")
    expectNoDifference(tripleExists["value"] as? String, "syncup-a")

    let txSteps = try #require(object["txSteps"] as? [[Any]])
    let deleteStep = try #require(
      txSteps.first { step in
        step.first as? String == "delete-entity" && step.dropFirst().first as? String == "attendee-b"
      }
    )
    expectNoDifference(deleteStep.dropFirst(2).first as? String, "attendees")
  }

  @Test
  func transportMutationAppliesPreconditionMetadataInOperationOrder() throws {
    let txTime = InstantTimestamp(milliseconds: 1_700_000_000_000)
    let transaction = InstantStoreTransaction(
      id: "tx-ordered-transport",
      operations: [
        .insert(
          InstantTriple(
            entityID: "todo-ordered",
            attributeID: "todos/text",
            value: .string("before precondition"),
            txID: "tx-ordered-transport",
            txTime: txTime
          )
        ),
        .requireEntityMissing(entityID: "todo-ordered", namespace: "todos"),
        .insert(
          InstantTriple(
            entityID: "todo-ordered",
            attributeID: "todos/title",
            value: .string("after create precondition"),
            txID: "tx-ordered-transport",
            txTime: txTime
          )
        ),
        .requireEntityExists(entityID: "todo-ordered", namespace: "archivedTodos"),
        .merge(
          InstantTriple(
            entityID: "todo-ordered",
            attributeID: "todos/metadata",
            value: .json(.object(["stage": .string("updated")])),
            txID: "tx-ordered-transport",
            txTime: txTime
          )
        ),
        .deleteEntity("todo-ordered"),
        .requireEntityExists(entityID: "todo-ordered", namespace: nil),
        .deleteEntity("todo-ordered"),
      ]
    )
    let mutation = InstantTransportMutation(
      PendingMutation(id: "tx-ordered-transport", createdAt: txTime, transaction: transaction)
    )

    let data = try JSONEncoder().encode(mutation)
    let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    let txSteps = try #require(object["txSteps"] as? [[Any]])

    expectNoDifference(txSteps.count, 5)
    expectNoDifference(txSteps[0][0] as? String, "add-triple")
    expectNoDifference(txSteps[0].count, 4)
    expectNoDifference(txSteps[1][0] as? String, "add-triple")
    expectNoDifference((txSteps[1][4] as? [String: Any])?["mode"] as? String, "create")
    expectNoDifference(txSteps[2][0] as? String, "deep-merge-triple")
    expectNoDifference((txSteps[2][4] as? [String: Any])?["mode"] as? String, "update")
    expectNoDifference(txSteps[3][0] as? String, "delete-entity")
    expectNoDifference(txSteps[3][2] as? String, "archivedTodos")
    expectNoDifference(txSteps[4][0] as? String, "delete-entity")
    expectNoDifference(txSteps[4].count, 2)
  }

  @Test
  func strictTodoUpdateRejectsMissingEntityBeforePersistence() async throws {
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "test-app",
        persistenceURL: temporaryCacheURL(),
        initialAttributes: TodoExample.attributes
      )
    )
    let updatedAt = InstantTimestamp(milliseconds: 1_700_000_000_250)

    do {
      try await runtime.transact(
        InstantStoreTransaction(
          id: "tx-update-missing-todo",
          operations: TodoExample.updateTextOperations(
            id: "missing-todo",
            text: "ghost text",
            updatedAt: updatedAt,
            transactionID: "tx-update-missing-todo"
          )
        ),
        createdAt: updatedAt
      )
      #expect(Bool(false), "Expected strict update to reject a missing todo.")
    } catch let error as InstantError {
      expectNoDifference(error.code, .validationFailed)
      expectNoDifference(error.operation, "strict update entity")
      expectNoDifference(error.namespace, TodoExample.namespace)
      expectNoDifference(error.localID, "missing-todo")
    } catch {
      #expect(Bool(false), "Unexpected error: \(error)")
    }

    let pending = await runtime.pendingMutations()
    expectNoDifference(pending, [])
    let todos = try await TodoExample.decode(runtime.query(TodoExample.query))
    expectNoDifference(todos, [])
  }

  @Test
  func strictTodoCreateRejectsExistingEntityBeforePersistence() async throws {
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "test-app",
        persistenceURL: temporaryCacheURL(),
        initialAttributes: TodoExample.attributes
      )
    )
    let createdAt = InstantTimestamp(milliseconds: 1_700_000_000_275)

    try await runtime.transact(
      InstantStoreTransaction(
        id: "tx-create-strict-todo",
        operations: TodoExample.createOperations(
          id: "todo-strict-create",
          text: "original text",
          createdAt: createdAt,
          transactionID: "tx-create-strict-todo"
        )
      ),
      createdAt: createdAt
    )

    do {
      try await runtime.transact(
        InstantStoreTransaction(
          id: "tx-duplicate-strict-todo",
          operations: TodoExample.createOperations(
            id: "todo-strict-create",
            text: "duplicate text",
            createdAt: InstantTimestamp(milliseconds: createdAt.milliseconds + 1),
            transactionID: "tx-duplicate-strict-todo"
          )
        ),
        createdAt: InstantTimestamp(milliseconds: createdAt.milliseconds + 1)
      )
      #expect(Bool(false), "Expected strict create to reject an existing todo.")
    } catch let error as InstantError {
      expectNoDifference(error.code, .validationFailed)
      expectNoDifference(error.operation, "strict create entity")
      expectNoDifference(error.namespace, TodoExample.namespace)
      expectNoDifference(error.localID, "todo-strict-create")
    } catch {
      #expect(Bool(false), "Unexpected error: \(error)")
    }

    let pending = await runtime.pendingMutations()
    expectNoDifference(pending.map(\.id), ["tx-create-strict-todo"])
    let todos = try await TodoExample.decode(runtime.query(TodoExample.query))
    expectNoDifference(todos.map(\.text), ["original text"])
  }

  @Test
  func seedAndResetTodoOperationsPersistAcrossLaunches() async throws {
    let cacheURL = try temporaryCacheURL()
    let seededAt = InstantTimestamp(milliseconds: 1_700_000_000_300)

    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "test-app",
        persistenceURL: cacheURL,
        initialAttributes: TodoExample.attributes
      )
    )
    try await runtime.transact(
      InstantStoreTransaction(
        id: "tx-seed-todos",
        operations: TodoExample.seedOperations(
          records: [
            ("todo-seed-plan", TodoExample.seedRecords[0]),
            ("todo-seed-terminal", TodoExample.seedRecords[1]),
            ("todo-seed-audit", TodoExample.seedRecords[2]),
          ],
          baseCreatedAt: seededAt,
          transactionID: "tx-seed-todos"
        )
      ),
      createdAt: seededAt
    )

    let seededTodos = try await TodoExample.decode(runtime.query(TodoExample.query))
    expectNoDifference(
      seededTodos.map { "\($0.id)|\($0.text)|\($0.isCompleted)" },
      [
        "todo-seed-plan|Plan the Instant Swift Data demo|true",
        "todo-seed-terminal|Run the non-captive terminal workflow|false",
        "todo-seed-audit|Audit the local cache and outbox|false",
      ]
    )

    let relaunchedSeededRuntime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "test-app",
        persistenceURL: cacheURL,
        initialAttributes: TodoExample.attributes
      )
    )
    let relaunchedSeededTodos = try await TodoExample.decode(
      relaunchedSeededRuntime.query(TodoExample.query)
    )
    expectNoDifference(relaunchedSeededTodos.map(\.id), seededTodos.map(\.id))

    try await relaunchedSeededRuntime.transact(
      InstantStoreTransaction(
        id: "tx-reset-todos",
        operations: TodoExample.resetOperations(ids: relaunchedSeededTodos.map(\.id))
      ),
      createdAt: InstantTimestamp(milliseconds: seededAt.milliseconds + 10)
    )

    let resetTodos = try await TodoExample.decode(relaunchedSeededRuntime.query(TodoExample.query))
    expectNoDifference(resetTodos, [])

    let relaunchedResetRuntime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "test-app",
        persistenceURL: cacheURL,
        initialAttributes: TodoExample.attributes
      )
    )
    let relaunchedResetTodos = try await TodoExample.decode(
      relaunchedResetRuntime.query(TodoExample.query)
    )
    expectNoDifference(relaunchedResetTodos, [])

    let pending = await relaunchedResetRuntime.pendingMutations()
    expectNoDifference(pending.map(\.id), ["tx-seed-todos", "tx-reset-todos"])
  }

  @Test
  func microblogFeedIncludesAuthorsLikesAndCascadesDeletes() async throws {
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "test-app",
        persistenceURL: temporaryCacheURL(),
        initialAttributes: MicroblogExample.attributes
      )
    )
    let seededAt = InstantTimestamp(milliseconds: 1_700_000_000_000)
    let seedIDs = MicroblogExample.SeedIDs(
      userIDs: ["user-sarah", "user-alex", "user-jordan"],
      postIDs: ["post-sarah", "post-alex", "post-jordan"],
      likeIDs: [
        (0..<12).map { "like-sarah-\($0)" },
        (0..<19).map { "like-alex-\($0)" },
        (0..<7).map { "like-jordan-\($0)" },
      ]
    )

    try await runtime.transact(
      InstantStoreTransaction(
        id: "tx-microblog-seed",
        operations: MicroblogExample.seedOperations(
          ids: seedIDs,
          baseTimestamp: seededAt,
          transactionID: "tx-microblog-seed"
        )
      ),
      createdAt: seededAt
    )

    let seededFeed = try await MicroblogExample.decodeFeed(
      runtime.query(MicroblogExample.feedQuery)
    )
    expectNoDifference(
      seededFeed.map { "\($0.post.id)|\($0.author?.handle ?? "missing")|\($0.likes.count)" },
      [
        "post-sarah|sarahchen|12",
        "post-alex|alexrivera|19",
        "post-jordan|jordanlee|7",
      ]
    )

    try await runtime.transact(
      InstantStoreTransaction(
        id: "tx-microblog-delete-post",
        operations: MicroblogExample.deletePostOperations(id: "post-sarah")
      ),
      createdAt: InstantTimestamp(milliseconds: seededAt.milliseconds + 1)
    )
    let afterPostDeleteFeed = try await MicroblogExample.decodeFeed(
      runtime.query(MicroblogExample.feedQuery)
    )
    let afterPostDeleteLikes = try await MicroblogExample.decodeLikes(
      runtime.query(MicroblogExample.likesQuery)
    )
    expectNoDifference(afterPostDeleteFeed.map(\.post.id), ["post-alex", "post-jordan"])
    expectNoDifference(afterPostDeleteLikes.count, 26)
    expectNoDifference(afterPostDeleteLikes.contains { $0.postID == "post-sarah" }, false)

    try await runtime.transact(
      InstantStoreTransaction(
        id: "tx-microblog-delete-user",
        operations: MicroblogExample.deleteUserOperations(id: "user-alex")
      ),
      createdAt: InstantTimestamp(milliseconds: seededAt.milliseconds + 2)
    )

    let users = try await MicroblogExample.decodeUsers(runtime.query(MicroblogExample.usersQuery))
    let profiles = try await MicroblogExample.decodeProfiles(
      runtime.query(MicroblogExample.profilesQuery)
    )
    let posts = try await MicroblogExample.decodePosts(runtime.query(MicroblogExample.postsQuery))
    let likes = try await MicroblogExample.decodeLikes(runtime.query(MicroblogExample.likesQuery))
    let feed = try await MicroblogExample.decodeFeed(runtime.query(MicroblogExample.feedQuery))
    expectNoDifference(users.map(\.id), ["user-jordan", "user-sarah"])
    expectNoDifference(profiles.map(\.handle), ["jordanlee", "sarahchen"])
    expectNoDifference(posts.map(\.id), ["post-jordan"])
    expectNoDifference(likes.map(\.postID), Array(repeating: "post-jordan", count: 7))
    expectNoDifference(feed.map { "\($0.post.id)|\($0.author?.handle ?? "missing")|\($0.likes.count)" }, [
      "post-jordan|jordanlee|7"
    ])
  }

  @Test
  func mobileChatMessagesIncludeNestedAuthorUsersAndCascadeDeletes() async throws {
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "test-app",
        persistenceURL: temporaryCacheURL(),
        initialAttributes: MobileChatExample.attributes
      )
    )
    let attributesByID = Dictionary(
      uniqueKeysWithValues: MobileChatExample.attributes.map { ($0.id, $0) }
    )
    expectNoDifference(attributesByID["$files/path"]?.isIndexed, true)
    expectNoDifference(attributesByID["$files/path"]?.isUnique, true)
    expectNoDifference(attributesByID["$users/linkedPrimaryUser"]?.linkNamespace, "$users")
    expectNoDifference(attributesByID["$users/linkedPrimaryUser"]?.onDelete, .cascade)
    expectNoDifference(attributesByID["mobileMessages/author"]?.isRequired, false)
    expectNoDifference(attributesByID["mobileMessages/author"]?.onDelete, .cascade)
    expectNoDifference(attributesByID["mobileMessages/channel"]?.reverseIdentity, "mobileChannels/messages")

    let seededAt = InstantTimestamp(milliseconds: 1_700_000_000_000)
    let seedIDs = MobileChatExample.SeedIDs(
      generalChannelID: "channel-general",
      randomChannelID: "channel-random",
      seedUserID: "user-instant",
      welcomeMessageID: "message-welcome",
      randomMessageID: "message-random"
    )
    try await runtime.transact(
      InstantStoreTransaction(
        id: "tx-mobile-chat-seed",
        operations: MobileChatExample.seedOperations(
          ids: seedIDs,
          baseTimestamp: seededAt,
          transactionID: "tx-mobile-chat-seed"
        )
      ),
      createdAt: seededAt
    )

    let channels = try await MobileChatExample.decodeChannels(
      runtime.query(MobileChatExample.channelsQuery)
    )
    expectNoDifference(channels.map(\.name), ["general", "random"])

    let generalMessages = try await MobileChatExample.decodeMessages(
      runtime.query(MobileChatExample.messagesForChannelQuery(seedIDs.generalChannelID))
    )
    expectNoDifference(generalMessages.map(\.content), ["Welcome to Instant mobile chat."])
    expectNoDifference(generalMessages.first?.author?.displayName, "Instant")
    expectNoDifference(generalMessages.first?.authorUser?.email, "instant@example.com")

    try await runtime.transact(
      InstantStoreTransaction(
        id: "tx-mobile-chat-no-profile-send",
        operations: MobileChatExample.createMessageOperations(
          id: "message-no-profile",
          channelID: seedIDs.generalChannelID,
          authorProfileID: nil,
          content: "Signed-in user has not created a profile yet.",
          timestamp: InstantTimestamp(milliseconds: seededAt.milliseconds + 10),
          transactionID: "tx-mobile-chat-no-profile-send"
        )
      ),
      createdAt: InstantTimestamp(milliseconds: seededAt.milliseconds + 10)
    )

    let profileTimestamp = InstantTimestamp(milliseconds: seededAt.milliseconds + 20)
    try await runtime.transact(
      InstantStoreTransaction(
        id: "tx-mobile-chat-profile",
        operations: MobileChatExample.createProfileOperations(
          userID: "user-cli",
          displayName: "CLI User",
          transactionID: "tx-mobile-chat-profile",
          updatedAt: profileTimestamp
        )
      ),
      createdAt: profileTimestamp
    )
    try await runtime.transact(
      InstantStoreTransaction(
        id: "tx-mobile-chat-profile-send",
        operations: MobileChatExample.createMessageOperations(
          id: "message-profile",
          channelID: seedIDs.generalChannelID,
          authorProfileID: "user-cli",
          content: "Hello from a profiled user.",
          timestamp: InstantTimestamp(milliseconds: seededAt.milliseconds + 21),
          transactionID: "tx-mobile-chat-profile-send"
        )
      ),
      createdAt: InstantTimestamp(milliseconds: seededAt.milliseconds + 21)
    )

    let updatedGeneralMessages = try await MobileChatExample.decodeMessages(
      runtime.query(MobileChatExample.messagesForChannelQuery(seedIDs.generalChannelID))
    )
    expectNoDifference(
      updatedGeneralMessages.map { message in
        "\(message.id)|\(message.author?.displayName ?? "missing")|\(message.authorUser?.id ?? "missing")"
      },
      [
        "message-welcome|Instant|user-instant",
        "message-no-profile|missing|missing",
        "message-profile|CLI User|user-cli",
      ]
    )

    let cliProfile = try #require(
      try await MobileChatExample.decodeProfiles(
        runtime.query(MobileChatExample.profileForUserQuery("user-cli"))
      )
      .first
    )
    let room = MobileChatExample.room(forChannelID: seedIDs.generalChannelID)
    let member = try await runtime.setPresence(
      room: room,
      userID: cliProfile.userID,
      values: MobileChatExample.presenceValues(profile: cliProfile)
    )
    expectNoDifference(member.values["profileId"], .string("user-cli"))
    expectNoDifference(member.values["displayName"], .string("CLI User"))
    let presenceUserIDs = try await runtime.roomPresence(room: room).map(\.userID)
    expectNoDifference(presenceUserIDs, ["user-cli"])

    try await runtime.transact(
      InstantStoreTransaction(
        id: "tx-mobile-chat-delete-channel",
        operations: MobileChatExample.deleteChannelOperations(id: seedIDs.generalChannelID)
      ),
      createdAt: InstantTimestamp(milliseconds: seededAt.milliseconds + 30)
    )
    let afterChannelDelete = try await MobileChatExample.decodeMessages(
      runtime.query(MobileChatExample.messagesQuery)
    )
    expectNoDifference(afterChannelDelete.map(\.id), ["message-random"])

    try await runtime.transact(
      InstantStoreTransaction(
        id: "tx-mobile-chat-delete-user",
        operations: MobileChatExample.deleteUserOperations(id: seedIDs.seedUserID)
      ),
      createdAt: InstantTimestamp(milliseconds: seededAt.milliseconds + 31)
    )
    let users = try await MobileChatExample.decodeUsers(runtime.query(MobileChatExample.usersQuery))
    let profiles = try await MobileChatExample.decodeProfiles(
      runtime.query(MobileChatExample.profilesQuery)
    )
    let messages = try await MobileChatExample.decodeMessages(
      runtime.query(MobileChatExample.messagesQuery)
    )
    expectNoDifference(users.map(\.id), ["user-cli"])
    expectNoDifference(profiles.map(\.displayName), ["CLI User"])
    expectNoDifference(messages, [])
  }

  @Test
  func stroopwafelRoomGameScoringAndSoftDeleteFlow() async throws {
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "test-app",
        persistenceURL: temporaryCacheURL(),
        initialAttributes: StroopwafelExample.attributes
      )
    )
    let attributesByID = Dictionary(
      uniqueKeysWithValues: StroopwafelExample.attributes.map { ($0.id, $0) }
    )
    func roomForCode(_ code: String) async throws -> StroopwafelRoomRecord {
      let page = try await runtime.queryOnce(StroopwafelExample.roomForCodeQuery(code))
      return try #require(try StroopwafelExample.decodeRooms(page.values).first)
    }
    func gameRecord(_ id: String) async throws -> StroopwafelGameRecord {
      let page = try await runtime.queryOnce(StroopwafelExample.gameQuery(id))
      return try #require(try StroopwafelExample.decodeGames(page.values).first)
    }

    expectNoDifference(attributesByID["$users/email"]?.valueType, .any)
    expectNoDifference(attributesByID["rooms/code"]?.isIndexed, true)
    expectNoDifference(attributesByID["rooms/readyIds"]?.valueType, .json)
    expectNoDifference(attributesByID["rooms/users"]?.reverseIdentity, "$users/rooms")
    expectNoDifference(attributesByID["games/points"]?.onDeleteReverse, .cascade)

    let startedAt = InstantTimestamp(milliseconds: 1_700_000_000_000)
    try await runtime.transact(
      InstantStoreTransaction(
        id: "tx-stroopwafel-users",
        operations:
          StroopwafelExample.setupProfileOperations(
            userID: "user-host",
            handle: "Host123",
            highScore: 0,
            createdAt: "2026-01-01T00:00:00.000Z",
            transactionID: "tx-stroopwafel-users",
            updatedAt: startedAt
          )
          + StroopwafelExample.setupProfileOperations(
            userID: "user-guest",
            handle: "Guest123",
            highScore: 0,
            createdAt: "2026-01-01T00:00:00.001Z",
            transactionID: "tx-stroopwafel-users",
            updatedAt: startedAt
          )
          + StroopwafelExample.setupProfileOperations(
            userID: "user-kicked",
            handle: "Kicked123",
            highScore: 0,
            createdAt: "2026-01-01T00:00:00.002Z",
            transactionID: "tx-stroopwafel-users",
            updatedAt: startedAt
          )
      ),
      createdAt: startedAt
    )

    try await runtime.transact(
      InstantStoreTransaction(
        id: "tx-stroopwafel-room",
        operations: StroopwafelExample.createRoomOperations(
          id: "room-1",
          code: "AB12",
          hostID: "user-host",
          createdAt: "2026-01-01T00:00:00.010Z",
          transactionID: "tx-stroopwafel-room",
          updatedAt: InstantTimestamp(milliseconds: startedAt.milliseconds + 10)
        )
      ),
      createdAt: InstantTimestamp(milliseconds: startedAt.milliseconds + 10)
    )
    var room = try await roomForCode("AB12")
    expectNoDifference(room.users.map(\.id), ["user-host"])
    expectNoDifference(room.readyIDs, [])

    try await runtime.transact(
      InstantStoreTransaction(
        id: "tx-stroopwafel-join",
        operations:
          StroopwafelExample.joinRoomOperations(
            room: room,
            userID: "user-guest",
            transactionID: "tx-stroopwafel-join",
            updatedAt: InstantTimestamp(milliseconds: startedAt.milliseconds + 20)
          )
          + StroopwafelExample.joinRoomOperations(
            room: room,
            userID: "user-kicked",
            transactionID: "tx-stroopwafel-join",
            updatedAt: InstantTimestamp(milliseconds: startedAt.milliseconds + 20)
          )
      ),
      createdAt: InstantTimestamp(milliseconds: startedAt.milliseconds + 20)
    )
    room = try await roomForCode("AB12")
    expectNoDifference(room.users.map(\.id), ["user-guest", "user-host", "user-kicked"])

    try await runtime.transact(
      InstantStoreTransaction(
        id: "tx-stroopwafel-ready",
        operations: StroopwafelExample.readyRoomOperations(
          room: room,
          userID: "user-guest",
          isReady: true,
          transactionID: "tx-stroopwafel-ready",
          updatedAt: InstantTimestamp(milliseconds: startedAt.milliseconds + 30)
        )
      ),
      createdAt: InstantTimestamp(milliseconds: startedAt.milliseconds + 30)
    )
    room = try await roomForCode("AB12")
    try await runtime.transact(
      InstantStoreTransaction(
        id: "tx-stroopwafel-kick",
        operations: StroopwafelExample.kickRoomOperations(
          room: room,
          userID: "user-kicked",
          transactionID: "tx-stroopwafel-kick",
          updatedAt: InstantTimestamp(milliseconds: startedAt.milliseconds + 31)
        )
      ),
      createdAt: InstantTimestamp(milliseconds: startedAt.milliseconds + 31)
    )
    room = try await roomForCode("AB12")
    expectNoDifference(room.readyIDs, ["user-guest"])
    expectNoDifference(room.kickedIDs, ["user-kicked"])
    expectNoDifference(room.users.map(\.id), ["user-guest", "user-host"])

    let playerIDs = room.users.map(\.id).filter { $0 == room.hostID || room.readyIDs.contains($0) }
    let pointIDsByPlayerID = playerIDs.map { (pointID: "point-\($0)", playerID: $0) }
    try await runtime.transact(
      InstantStoreTransaction(
        id: "tx-stroopwafel-start",
        operations: StroopwafelExample.startGameOperations(
          room: room,
          gameID: "game-1",
          pointIDsByPlayerID: pointIDsByPlayerID,
          colors: StroopwafelExample.generateGameColors(seed: "game-1"),
          createdAt: "2026-01-01T00:00:00.040Z",
          transactionID: "tx-stroopwafel-start",
          updatedAt: InstantTimestamp(milliseconds: startedAt.milliseconds + 40)
        )
      ),
      createdAt: InstantTimestamp(milliseconds: startedAt.milliseconds + 40)
    )
    var game = try await gameRecord("game-1")
    expectNoDifference(game.status, StroopwafelExample.gameInProgress)
    expectNoDifference(game.playerIDs.sorted(), ["user-guest", "user-host"])
    expectNoDifference(game.points.map(\.value), [0, 0])
    expectNoDifference(game.rooms.first?.currentGameID, "game-1")

    let hostPoint = try #require(game.points.first { $0.userID == "user-host" })
    let firstPrompt = try #require(game.colors.first)
    let wrongColor = try #require(StroopwafelExample.colorChoices.first { $0 != firstPrompt.label })
    try await runtime.transact(
      InstantStoreTransaction(
        id: "tx-stroopwafel-wrong-tap",
        operations: StroopwafelExample.tapOperations(
          game: game,
          userID: "user-host",
          selectedColor: wrongColor,
          transactionID: "tx-stroopwafel-wrong-tap",
          updatedAt: InstantTimestamp(milliseconds: startedAt.milliseconds + 50)
        )
      ),
      createdAt: InstantTimestamp(milliseconds: startedAt.milliseconds + 50)
    )
    game = try await gameRecord("game-1")
    expectNoDifference(game.points.first { $0.id == hostPoint.id }?.value, 0)

    var tapIndex = 0
    while game.status == StroopwafelExample.gameInProgress {
      let point = try #require(game.points.first { $0.userID == "user-host" })
      let prompt = try #require(game.colors[safe: point.value])
      let transactionID = "tx-stroopwafel-correct-tap-\(tapIndex)"
      try await runtime.transact(
        InstantStoreTransaction(
          id: transactionID,
          operations: StroopwafelExample.tapOperations(
            game: game,
            userID: "user-host",
            selectedColor: prompt.label,
            transactionID: transactionID,
            updatedAt: InstantTimestamp(milliseconds: startedAt.milliseconds + 60 + Int64(tapIndex))
          )
        ),
        createdAt: InstantTimestamp(milliseconds: startedAt.milliseconds + 60 + Int64(tapIndex))
      )
      game = try await gameRecord("game-1")
      tapIndex += 1
    }
    expectNoDifference(game.status, StroopwafelExample.gameCompleted)
    expectNoDifference(game.points.first { $0.userID == "user-host" }?.value, 13)
    expectNoDifference(game.rooms.first?.currentGameID, nil)

    room = try #require(game.rooms.first)
    try await runtime.transact(
      InstantStoreTransaction(
        id: "tx-stroopwafel-host-leave",
        operations: StroopwafelExample.leaveRoomOperations(
          room: room,
          userID: "user-host",
          deletedAt: "2026-01-01T00:00:00.090Z",
          transactionID: "tx-stroopwafel-host-leave",
          updatedAt: InstantTimestamp(milliseconds: startedAt.milliseconds + 90)
        )
      ),
      createdAt: InstantTimestamp(milliseconds: startedAt.milliseconds + 90)
    )
    let activeRoomPage = try await runtime.queryOnce(StroopwafelExample.roomForCodeQuery("AB12"))
    let activeRooms = try StroopwafelExample.decodeRooms(activeRoomPage.values)
    let allRoomPage = try await runtime.queryOnce(StroopwafelExample.roomsQuery)
    let allRooms = try StroopwafelExample.decodeRooms(allRoomPage.values)
    expectNoDifference(activeRooms, [])
    expectNoDifference(allRooms.first?.deletedAt, "2026-01-01T00:00:00.090Z")
  }

  @Test
  func queryCacheStoresSameQueryIDDifferentPlansSeparately() async throws {
    let cacheURL = try temporaryCacheURL()
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "test-app",
        persistenceURL: cacheURL,
        initialAttributes: TodoExample.attributes
      )
    )
    let firstCreatedAt = InstantTimestamp(milliseconds: 1_700_000_000_000)
    let secondCreatedAt = InstantTimestamp(milliseconds: firstCreatedAt.milliseconds + 1)
    try await runtime.transact(
      InstantStoreTransaction(
        id: "tx-cache-collision-a",
        operations: TodoExample.createOperations(
          id: "todo-open",
          text: "open",
          createdAt: firstCreatedAt,
          transactionID: "tx-cache-collision-a"
        )
      ),
      createdAt: firstCreatedAt
    )
    try await runtime.transact(
      InstantStoreTransaction(
        id: "tx-cache-collision-b",
        operations: TodoExample.createOperations(
          id: "todo-completed",
          text: "completed",
          createdAt: secondCreatedAt,
          transactionID: "tx-cache-collision-b"
        ) + TodoExample.completeOperations(
          id: "todo-completed",
          updatedAt: secondCreatedAt,
          transactionID: "tx-cache-collision-b"
        )
      ),
      createdAt: secondCreatedAt
    )

    let openPlan = InstantQueryPlan(
      id: "examples.todos.list",
      namespace: TodoExample.namespace,
      filters: [.equals(field: "isCompleted", value: .bool(false))],
      order: InstantQueryOrder("createdAt", .ascending)
    )
    let completedPlan = InstantQueryPlan(
      id: "examples.todos.list",
      namespace: TodoExample.namespace,
      filters: [.equals(field: "isCompleted", value: .bool(true))],
      order: InstantQueryOrder("createdAt", .ascending)
    )

    _ = try await runtime.query(openPlan)
    _ = try await runtime.query(completedPlan)

    let cachedQueries = try await runtime.cachedQueries()
    expectNoDifference(cachedQueries.map(\.queryID), ["examples.todos.list", "examples.todos.list"])
    expectNoDifference(
      Set(cachedQueries.map(\.cacheKey)),
      Set([openPlan.cacheKey, completedPlan.cacheKey])
    )

    let relaunchedRuntime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "test-app",
        persistenceURL: cacheURL,
        initialAttributes: TodoExample.attributes
      )
    )
    let openCache = try await relaunchedRuntime.cachedQuery(openPlan)
    let completedCache = try await relaunchedRuntime.cachedQuery(completedPlan)

    expectNoDifference(openCache?.emission.values.map(\.id), ["todo-open"])
    expectNoDifference(completedCache?.emission.values.map(\.id), ["todo-completed"])
  }

  @Test
  func queryCacheKeyDoesNotTrapForNonFiniteNumbers() {
    let nanPlan = InstantQueryPlan(
      id: "numbers.nan",
      namespace: "numbers",
      filters: [.equals(field: "value", value: .number(.nan))]
    )
    let infinityPlan = InstantQueryPlan(
      id: "numbers.infinity",
      namespace: "numbers",
      filters: [.equals(field: "value", value: .number(.infinity))]
    )

    #expect(nanPlan.cacheKey.hasPrefix("plan:"))
    #expect(infinityPlan.cacheKey.hasPrefix("plan:"))
    #expect(nanPlan.cacheKey != infinityPlan.cacheKey)
  }

  @Test
  func queryCacheMigrationPreservesLegacyRows() async throws {
    let cacheURL = try temporaryCacheURL()
    let updatedAt = InstantTimestamp(milliseconds: 1_700_000_000_000)
    try seedLegacyQueryCache(
      at: cacheURL,
      entry: LegacyCachedQuery(
        queryID: TodoExample.query.id,
        plan: TodoExample.query,
        emission: InstantQueryEmission(queryID: TodoExample.query.id, sequence: 0, values: []),
        updatedAt: updatedAt,
        storeRevision: 42
      )
    )

    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "test-app",
        persistenceURL: cacheURL,
        initialAttributes: TodoExample.attributes
      )
    )
    let cachedQuery = try await runtime.cachedQuery(TodoExample.query)
    let cachedQueries = try await runtime.cachedQueries()

    expectNoDifference(cachedQuery?.cacheKey, TodoExample.query.cacheKey)
    expectNoDifference(cachedQuery?.updatedAt, updatedAt)
    expectNoDifference(cachedQuery?.storeRevision, 42)
    expectNoDifference(cachedQueries.map(\.cacheKey), [TodoExample.query.cacheKey])
  }

  @Test
  func staleRuntimeReloadsBeforeReplacingQueryCache() async throws {
    let cacheURL = try temporaryCacheURL()
    let firstCreatedAt = InstantTimestamp(milliseconds: 1_700_000_000_000)
    let secondCreatedAt = InstantTimestamp(milliseconds: firstCreatedAt.milliseconds + 1)
    let seedRuntime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "test-app",
        persistenceURL: cacheURL,
        initialAttributes: TodoExample.attributes
      )
    )
    try await seedRuntime.transact(
      InstantStoreTransaction(
        id: "tx-seed-cache",
        operations: TodoExample.createOperations(
          id: "todo-seed",
          text: "seed cache",
          createdAt: firstCreatedAt,
          transactionID: "tx-seed-cache"
        )
      ),
      createdAt: firstCreatedAt
    )
    _ = try await seedRuntime.query(TodoExample.query)

    let staleRuntime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "test-app",
        persistenceURL: cacheURL
      )
    )
    let writerRuntime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "test-app",
        persistenceURL: cacheURL
      )
    )
    try await writerRuntime.transact(
      InstantStoreTransaction(
        id: "tx-cross-runtime",
        operations: TodoExample.createOperations(
          id: "todo-cross-runtime",
          text: "cross runtime",
          createdAt: secondCreatedAt,
          transactionID: "tx-cross-runtime"
        )
      ),
      createdAt: secondCreatedAt
    )

    let snapshots = try await staleRuntime.query(TodoExample.query)
    let cachedQuery = try await staleRuntime.cachedQuery(TodoExample.query)
    let cachedTodos = try TodoExample.decode(cachedQuery?.emission.values ?? [])

    expectNoDifference(snapshots.map(\.id), ["todo-seed", "todo-cross-runtime"])
    expectNoDifference(
      cachedTodos,
      [
        TodoRecord(
          id: "todo-seed",
          text: "seed cache",
          isCompleted: false,
          createdAt: firstCreatedAt
        ),
        TodoRecord(
          id: "todo-cross-runtime",
          text: "cross runtime",
          isCompleted: false,
          createdAt: secondCreatedAt
        ),
      ]
    )
  }

  @Test
  func duplicatePendingTransactionIDsAreIdempotentOnlyForMatchingTransactions() async throws {
    let cacheURL = try temporaryCacheURL()
    let createdAt = InstantTimestamp(milliseconds: 1_700_000_000_000)
    let transactionID = "tx-dedupe"
    let transaction = InstantStoreTransaction(
      id: transactionID,
      operations: TodoExample.createOperations(
        id: "todo-dedupe",
        text: "dedupe me",
        createdAt: createdAt,
        transactionID: transactionID
      )
    )
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "test-app",
        persistenceURL: cacheURL,
        initialAttributes: TodoExample.attributes
      )
    )

    let first = try await runtime.transact(transaction, createdAt: createdAt)
    let replayed = try await runtime.transact(
      transaction,
      createdAt: InstantTimestamp(milliseconds: createdAt.milliseconds + 1)
    )

    expectNoDifference(first.changedEntityIDs, Set(["todo-dedupe"]))
    expectNoDifference(replayed.changedEntityIDs, Set<String>())
    expectNoDifference(replayed.tripleCount, first.tripleCount)
    expectNoDifference(replayed.emissions, [])

    let mismatchedTransaction = InstantStoreTransaction(
      id: transactionID,
      operations: TodoExample.createOperations(
        id: "todo-dedupe-other",
        text: "different write",
        createdAt: InstantTimestamp(milliseconds: createdAt.milliseconds + 2),
        transactionID: transactionID
      )
    )
    do {
      try await runtime.transact(
        mismatchedTransaction,
        createdAt: InstantTimestamp(milliseconds: createdAt.milliseconds + 2)
      )
      #expect(Bool(false), "Expected duplicate transaction id to reject different operations.")
    } catch let error as InstantError {
      expectNoDifference(error.code, .validationFailed)
      expectNoDifference(error.operation, "transact")
      expectNoDifference(error.localID, transactionID)
    } catch {
      #expect(Bool(false), "Unexpected error: \(error)")
    }

    let pending = await runtime.pendingMutations()
    expectNoDifference(pending.map(\.id), [transactionID])
    expectNoDifference(pending.map(\.createdAt), [createdAt])
    expectNoDifference(pending.map(\.transaction), [transaction])
    let todos = try await TodoExample.decode(runtime.query(TodoExample.query))
    expectNoDifference(todos.map(\.id), ["todo-dedupe"])

    let relaunchedRuntime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "test-app",
        persistenceURL: cacheURL,
        initialAttributes: TodoExample.attributes
      )
    )
    let relaunchedPending = await relaunchedRuntime.pendingMutations()
    expectNoDifference(relaunchedPending.map(\.id), [transactionID])
    expectNoDifference(relaunchedPending.map(\.transaction), [transaction])
  }

  @Test
  func outboxConfirmationCleansUpAndFailuresPersistAcrossLaunches() async throws {
    let cacheURL = try temporaryCacheURL()
    let createdAt = InstantTimestamp(milliseconds: 1_700_000_000_000)
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "test-app",
        persistenceURL: cacheURL,
        initialAttributes: TodoExample.attributes
      )
    )

    try await runtime.transact(
      InstantStoreTransaction(
        id: "tx-confirm",
        operations: TodoExample.createOperations(
          id: "todo-confirm",
          text: "confirm me",
          createdAt: createdAt,
          transactionID: "tx-confirm"
        )
      ),
      createdAt: createdAt
    )
    try await runtime.transact(
      InstantStoreTransaction(
        id: "tx-fail",
        operations: TodoExample.createOperations(
          id: "todo-fail",
          text: "fail me",
          createdAt: InstantTimestamp(milliseconds: createdAt.milliseconds + 1),
          transactionID: "tx-fail"
        )
      ),
      createdAt: InstantTimestamp(milliseconds: createdAt.milliseconds + 1)
    )

    let confirmed = try await runtime.confirmMutation(id: "tx-confirm")
    let failed = try await runtime.failMutation(id: "tx-fail", message: "server rejected")
    expectNoDifference(confirmed.status, .confirmed)
    expectNoDifference(failed.status, .failed)
    expectNoDifference(failed.failureMessage, "server rejected")

    let liveMutations = await runtime.outboxMutations()
    expectNoDifference(liveMutations.map(\.id), ["tx-fail"])

    let relaunchedRuntime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "test-app",
        persistenceURL: cacheURL,
        initialAttributes: TodoExample.attributes
      )
    )

    let mutations = await relaunchedRuntime.outboxMutations()
    let pending = await relaunchedRuntime.pendingMutations()
    expectNoDifference(mutations.map(\.id), ["tx-fail"])
    expectNoDifference(mutations.map(\.status), [.failed])
    expectNoDifference(mutations.map(\.failureMessage), ["server rejected"])
    expectNoDifference(pending, [])
  }

  @Test
  func outboxDrainSkipsFailedMutationsAndRetryRestoresPendingState() async throws {
    let cacheURL = try temporaryCacheURL()
    let baseTime = InstantTimestamp(milliseconds: 1_700_000_000_000)
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "test-app",
        persistenceURL: cacheURL,
        initialAttributes: TodoExample.attributes
      )
    )

    for index in 0..<3 {
      let createdAt = InstantTimestamp(milliseconds: baseTime.milliseconds + Int64(index))
      try await runtime.transact(
        InstantStoreTransaction(
          id: "tx-drain-\(index)",
          operations: TodoExample.createOperations(
            id: "todo-drain-\(index)",
            text: "drain \(index)",
            createdAt: createdAt,
            transactionID: "tx-drain-\(index)"
          )
        ),
        createdAt: createdAt
      )
    }

    let failed = try await runtime.failMutation(id: "tx-drain-1", message: "permission rejected")
    expectNoDifference(failed.status, .failed)

    let drained = try await runtime.drainPendingMutationsLocally()
    expectNoDifference(drained.map(\.id), ["tx-drain-0", "tx-drain-2"])
    expectNoDifference(drained.map(\.status), [.confirmed, .confirmed])

    var mutations = await runtime.outboxMutations()
    expectNoDifference(mutations.map(\.id), ["tx-drain-1"])
    expectNoDifference(mutations.map(\.status), [.failed])

    let retried = try await runtime.retryMutation(id: "tx-drain-1")
    expectNoDifference(retried.status, .pending)
    expectNoDifference(retried.failureMessage, nil)

    let finalDrain = try await runtime.drainPendingMutationsLocally(limit: 1)
    expectNoDifference(finalDrain.map(\.id), ["tx-drain-1"])
    expectNoDifference(finalDrain.map(\.status), [.confirmed])
    mutations = await runtime.outboxMutations()
    expectNoDifference(mutations, [])

    let relaunchedRuntime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "test-app",
        persistenceURL: cacheURL,
        initialAttributes: TodoExample.attributes
      )
    )
    mutations = await relaunchedRuntime.outboxMutations()
    expectNoDifference(mutations, [])
  }

  @Test
  func outboxFlushUsesMutationTransportResults() async throws {
    let cacheURL = try temporaryCacheURL()
    let baseTime = InstantTimestamp(milliseconds: 1_700_000_000_000)
    let recorder = MutationTransportRecorder()
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "test-app",
        apiURI: try #require(URL(string: "https://api.example.test")),
        websocketURI: try #require(URL(string: "wss://socket.example.test/runtime/session")),
        persistenceURL: cacheURL,
        initialAttributes: TodoExample.attributes,
        mutationTransport: InstantMutationTransportClient { request in
          await recorder.record(request)
          return InstantMutationTransportResponse(
            results: request.mutations.map { mutation in
              if mutation.mutationID == "tx-flush-1" {
                return InstantMutationTransportResult(
                  mutationID: mutation.mutationID,
                  outcome: .failed,
                  message: "permission rejected"
                )
              }
              return InstantMutationTransportResult(
                mutationID: mutation.mutationID,
                outcome: .confirmed
              )
            }
          )
        }
      )
    )

    for index in 0..<3 {
      let createdAt = InstantTimestamp(milliseconds: baseTime.milliseconds + Int64(index))
      try await runtime.transact(
        InstantStoreTransaction(
          id: "tx-flush-\(index)",
          operations: TodoExample.createOperations(
            id: "todo-flush-\(index)",
            text: "flush \(index)",
            createdAt: createdAt,
            transactionID: "tx-flush-\(index)"
          )
        ),
        createdAt: createdAt
      )
    }

    let result = try await runtime.flushPendingMutations(limit: 2)
    expectNoDifference(result.request.appID, "test-app")
    expectNoDifference(result.request.apiURI.absoluteString, "https://api.example.test")
    expectNoDifference(
      result.request.websocketURI.absoluteString,
      "wss://socket.example.test/runtime/session"
    )
    expectNoDifference(result.request.mutations.map(\.mutationID), ["tx-flush-0", "tx-flush-1"])
    expectNoDifference(result.results.map(\.mutationID), ["tx-flush-0", "tx-flush-1"])
    expectNoDifference(result.results.map(\.outcome), [.confirmed, .failed])
    expectNoDifference(result.confirmed.map(\.id), ["tx-flush-0"])
    expectNoDifference(result.failed.map(\.id), ["tx-flush-1"])
    expectNoDifference(result.failed.map(\.failureMessage), ["permission rejected"])
    expectNoDifference(result.pendingMutationCount, 1)
    expectNoDifference(result.mutationCount, 2)
    let failedFlushStatus = try await runtime.connectionStatus()
    expectNoDifference(failedFlushStatus.state, .errored)
    expectNoDifference(failedFlushStatus.lastErrorMessage, "permission rejected")

    let requests = await recorder.requests()
    expectNoDifference(
      requests.map { $0.mutations.map(\.mutationID) },
      [["tx-flush-0", "tx-flush-1"]]
    )

    let relaunchedRuntime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "test-app",
        persistenceURL: cacheURL,
        initialAttributes: TodoExample.attributes
      )
    )
    let mutations = await relaunchedRuntime.outboxMutations()
    expectNoDifference(mutations.map(\.id), ["tx-flush-1", "tx-flush-2"])
    expectNoDifference(mutations.map(\.status), [.failed, .pending])
    expectNoDifference(mutations.map(\.failureMessage), ["permission rejected", nil])
    let relaunchedStatus = try await relaunchedRuntime.connectionStatus()
    expectNoDifference(relaunchedStatus.state, .errored)
    expectNoDifference(relaunchedStatus.lastErrorMessage, "permission rejected")
  }

  @Test
  func outboxFlushWaitsForReconnectWhenConnectionIsClosed() async throws {
    let cacheURL = try temporaryCacheURL()
    let baseTime = InstantTimestamp(milliseconds: 1_700_000_000_000)
    let recorder = MutationTransportRecorder()
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "test-app",
        persistenceURL: cacheURL,
        initialAttributes: TodoExample.attributes,
        mutationTransport: InstantMutationTransportClient { request in
          await recorder.record(request)
          return InstantMutationTransportResponse(
            results: request.mutations.map { mutation in
              InstantMutationTransportResult(mutationID: mutation.mutationID, outcome: .confirmed)
            }
          )
        }
      )
    )

    let emptyClosedStatus = try await runtime.closeConnection()
    expectNoDifference(emptyClosedStatus.state, .closed)
    expectNoDifference(emptyClosedStatus.pendingMutationCount, 0)
    let emptyFlush = try await runtime.flushPendingMutations()
    expectNoDifference(emptyFlush.request.mutations, [])
    expectNoDifference(emptyFlush.results, [])
    expectNoDifference(emptyFlush.confirmed, [])
    expectNoDifference(emptyFlush.failed, [])
    expectNoDifference(emptyFlush.pendingMutationCount, 0)
    expectNoDifference(emptyFlush.mutationCount, 0)
    let emptyBlockedRequests = await recorder.requests()
    expectNoDifference(emptyBlockedRequests.count, 0)

    try await runtime.transact(
      InstantStoreTransaction(
        id: "tx-offline-flush",
        operations: TodoExample.createOperations(
          id: "todo-offline-flush",
          text: "flush after reconnect",
          createdAt: baseTime,
          transactionID: "tx-offline-flush"
        )
      ),
      createdAt: baseTime
    )

    let closedStatus = try await runtime.connectionStatus()
    expectNoDifference(closedStatus.state, .closed)
    expectNoDifference(closedStatus.pendingMutationCount, 1)

    do {
      _ = try await runtime.flushPendingMutations()
      #expect(Bool(false), "Expected closed connection to block outbox flush.")
    } catch let error as InstantError {
      expectNoDifference(error.code, .networkFailed)
      expectNoDifference(error.operation, "flush outbox")
      expectNoDifference(
        error.message,
        "Cannot flush 1 pending mutation(s) while the Instant connection is closed."
      )
    } catch {
      #expect(Bool(false), "Unexpected error: \(error)")
    }

    let blockedStatus = try await runtime.connectionStatus()
    expectNoDifference(blockedStatus.state, .closed)
    expectNoDifference(blockedStatus.pendingMutationCount, 1)
    expectNoDifference(blockedStatus.lastErrorMessage, nil)
    let blockedRequests = await recorder.requests()
    expectNoDifference(blockedRequests.count, 0)
    let blockedMutations = await runtime.outboxMutations()
    expectNoDifference(blockedMutations.map(\.id), ["tx-offline-flush"])
    expectNoDifference(blockedMutations.map(\.status), [.pending])

    let connectedStatus = try await runtime.connect()
    expectNoDifference(connectedStatus.state, .opened)
    expectNoDifference(connectedStatus.pendingMutationCount, 1)

    let result = try await runtime.flushPendingMutations()
    expectNoDifference(result.confirmed.map(\.id), ["tx-offline-flush"])
    expectNoDifference(result.pendingMutationCount, 0)
    let requests = await recorder.requests()
    expectNoDifference(requests.map { $0.mutations.map(\.mutationID) }, [
      ["tx-offline-flush"]
    ])
    let flushedMutations = await runtime.outboxMutations()
    expectNoDifference(flushedMutations, [])
  }

  @Test
  func outboxFlushIgnoresTransportResultsOutsideRequestedBatch() async throws {
    let cacheURL = try temporaryCacheURL()
    let baseTime = InstantTimestamp(milliseconds: 1_700_000_000_000)
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "test-app",
        persistenceURL: cacheURL,
        initialAttributes: TodoExample.attributes,
        mutationTransport: InstantMutationTransportClient { request in
          let requestedMutationID = request.mutations.first?.mutationID ?? "missing-mutation"
          return InstantMutationTransportResponse(
            results: [
              InstantMutationTransportResult(
                mutationID: requestedMutationID,
                outcome: .confirmed
              ),
              InstantMutationTransportResult(
                mutationID: "tx-flush-1-ignored",
                outcome: .confirmed
              ),
            ]
          )
        }
      )
    )

    for index in 0..<2 {
      let transactionID = "tx-flush-\(index)-\(index == 0 ? "requested" : "ignored")"
      let createdAt = InstantTimestamp(milliseconds: baseTime.milliseconds + Int64(index))
      try await runtime.transact(
        InstantStoreTransaction(
          id: transactionID,
          operations: TodoExample.createOperations(
            id: "todo-\(transactionID)",
            text: transactionID,
            createdAt: createdAt,
            transactionID: transactionID
          )
        ),
        createdAt: createdAt
      )
    }

    let result = try await runtime.flushPendingMutations(limit: 1)
    expectNoDifference(result.request.mutations.map(\.mutationID), ["tx-flush-0-requested"])
    expectNoDifference(result.results.map(\.mutationID), ["tx-flush-0-requested"])
    expectNoDifference(result.confirmed.map(\.id), ["tx-flush-0-requested"])
    expectNoDifference(result.pendingMutationCount, 1)

    let mutations = await runtime.outboxMutations()
    expectNoDifference(mutations.map(\.id), ["tx-flush-1-ignored"])
    expectNoDifference(mutations.map(\.status), [.pending])
  }

  @Test
  func outboxFlushTransportErrorUpdatesConnectionStatus() async throws {
    let cacheURL = try temporaryCacheURL()
    let baseTime = InstantTimestamp(milliseconds: 1_700_000_000_000)
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "test-app",
        persistenceURL: cacheURL,
        initialAttributes: TodoExample.attributes,
        mutationTransport: InstantMutationTransportClient { _ in
          throw InstantError(
            code: .networkFailed,
            operation: "send mutations",
            message: "The local transport is offline.",
            recovery: "Reconnect before flushing pending mutations."
          )
        }
      )
    )
    try await runtime.transact(
      InstantStoreTransaction(
        id: "tx-flush-error",
        operations: TodoExample.createOperations(
          id: "todo-flush-error",
          text: "flush error",
          createdAt: baseTime,
          transactionID: "tx-flush-error"
        )
      ),
      createdAt: baseTime
    )

    do {
      _ = try await runtime.flushPendingMutations()
      #expect(Bool(false), "Expected transport error to fail the flush.")
    } catch let error as InstantError {
      expectNoDifference(error.code, .networkFailed)
      expectNoDifference(error.operation, "send mutations")
    } catch {
      #expect(Bool(false), "Unexpected error: \(error)")
    }

    let erroredStatus = try await runtime.connectionStatus()
    expectNoDifference(erroredStatus.state, .errored)
    #expect(erroredStatus.lastErrorMessage?.contains("send mutations") == true)

    let relaunchedErroredRuntime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "test-app",
        persistenceURL: cacheURL,
        initialAttributes: TodoExample.attributes
      )
    )
    let relaunchedErroredStatus = try await relaunchedErroredRuntime.connectionStatus()
    expectNoDifference(relaunchedErroredStatus.state, .errored)
    #expect(relaunchedErroredStatus.lastErrorMessage?.contains("send mutations") == true)

    let recoveryRuntime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "test-app",
        persistenceURL: cacheURL,
        initialAttributes: TodoExample.attributes,
        mutationTransport: .local
      )
    )
    _ = try await recoveryRuntime.flushPendingMutations()
    let recoveredStatus = try await recoveryRuntime.connectionStatus()
    expectNoDifference(recoveredStatus.state, .opened)
    expectNoDifference(recoveredStatus.lastErrorMessage, nil)
  }

  @Test
  func outboxFlushDoesNotClearConnectionErrorWhileFailedMutationsRemain() async throws {
    let cacheURL = try temporaryCacheURL()
    let baseTime = InstantTimestamp(milliseconds: 1_700_000_000_000)
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "test-app",
        persistenceURL: cacheURL,
        initialAttributes: TodoExample.attributes,
        mutationTransport: .local
      )
    )
    for index in 0..<2 {
      let transactionID = "tx-failed-remains-\(index)"
      let createdAt = InstantTimestamp(milliseconds: baseTime.milliseconds + Int64(index))
      try await runtime.transact(
        InstantStoreTransaction(
          id: transactionID,
          operations: TodoExample.createOperations(
            id: "todo-failed-remains-\(index)",
            text: "failed remains \(index)",
            createdAt: createdAt,
            transactionID: transactionID
          )
        ),
        createdAt: createdAt
      )
    }

    _ = try await runtime.failMutation(id: "tx-failed-remains-0", message: "older failure")
    let erroredStatus = try await runtime.connectionStatus()
    expectNoDifference(erroredStatus.state, .errored)
    expectNoDifference(erroredStatus.lastErrorMessage, "older failure")

    let result = try await runtime.flushPendingMutations(limit: 1)
    expectNoDifference(result.confirmed.map(\.id), ["tx-failed-remains-1"])
    expectNoDifference(result.failed, [])
    let stillErroredStatus = try await runtime.connectionStatus()
    expectNoDifference(stillErroredStatus.state, .errored)
    expectNoDifference(stillErroredStatus.lastErrorMessage, "older failure")
  }

  @Test
  func outboxFlushDoesNotBlockLocalTransactsWhileTransportIsSuspended() async throws {
    let baseTime = InstantTimestamp(milliseconds: 1_700_000_000_000)
    let transport = SuspendedMutationTransport()
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "test-app",
        persistenceURL: temporaryCacheURL(),
        initialAttributes: TodoExample.attributes,
        mutationTransport: InstantMutationTransportClient { request in
          await transport.send(request)
        }
      )
    )
    try await runtime.transact(
      InstantStoreTransaction(
        id: "tx-before-suspended-flush",
        operations: TodoExample.createOperations(
          id: "todo-before-suspended-flush",
          text: "before suspended flush",
          createdAt: baseTime,
          transactionID: "tx-before-suspended-flush"
        )
      ),
      createdAt: baseTime
    )

    let flushTask = Task {
      try await runtime.flushPendingMutations(limit: 1)
    }
    await transport.waitForRequest()

    let transactedWhileFlushWasSuspended = await withTaskGroup(of: Bool.self) { group in
      group.addTask {
        do {
          try await runtime.transact(
            InstantStoreTransaction(
              id: "tx-during-suspended-flush",
              operations: TodoExample.createOperations(
                id: "todo-during-suspended-flush",
                text: "during suspended flush",
                createdAt: InstantTimestamp(milliseconds: baseTime.milliseconds + 1),
                transactionID: "tx-during-suspended-flush"
              )
            ),
            createdAt: InstantTimestamp(milliseconds: baseTime.milliseconds + 1)
          )
          return true
        } catch {
          return false
        }
      }
      group.addTask {
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        return false
      }

      let completed = await group.next() ?? false
      if !completed {
        await transport.resumeConfirmingRequest()
      }
      group.cancelAll()
      return completed
    }

    #expect(transactedWhileFlushWasSuspended)
    await transport.resumeConfirmingRequest()
    let result = try await flushTask.value
    expectNoDifference(result.confirmed.map(\.id), ["tx-before-suspended-flush"])

    let mutations = await runtime.outboxMutations()
    expectNoDifference(mutations.map(\.id), ["tx-during-suspended-flush"])
    expectNoDifference(mutations.map(\.status), [.pending])
  }

  @Test
  func outboxDrainUsesIDAsStableTieBreakerForSameTimestampMutations() async throws {
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "test-app",
        persistenceURL: temporaryCacheURL(),
        initialAttributes: TodoExample.attributes
      )
    )
    let createdAt = InstantTimestamp(milliseconds: 1_700_000_000_000)

    for transactionID in ["tx-b", "tx-a", "tx-c"] {
      try await runtime.transact(
        InstantStoreTransaction(
          id: transactionID,
          operations: TodoExample.createOperations(
            id: "todo-\(transactionID)",
            text: transactionID,
            createdAt: createdAt,
            transactionID: transactionID
          )
        ),
        createdAt: createdAt
      )
    }

    let firstDrain = try await runtime.drainPendingMutationsLocally(limit: 2)
    expectNoDifference(firstDrain.map(\.id), ["tx-a", "tx-b"])

    let secondDrain = try await runtime.drainPendingMutationsLocally(limit: 2)
    expectNoDifference(secondDrain.map(\.id), ["tx-c"])
  }

  @Test
  func outboxStatusUpdateFailsForMissingMutation() async throws {
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "test-app",
        persistenceURL: temporaryCacheURL(),
        initialAttributes: TodoExample.attributes
      )
    )

    do {
      try await runtime.confirmMutation(id: "missing-mutation")
      #expect(Bool(false), "Expected missing outbox mutation to fail.")
    } catch let error as InstantError {
      expectNoDifference(error.code, .validationFailed)
      expectNoDifference(error.operation, "update outbox mutation")
      expectNoDifference(error.localID, "missing-mutation")
    } catch {
      #expect(Bool(false), "Unexpected error: \(error)")
    }
  }

  @Test
  func failedOutboxConfirmationDoesNotMutateLiveState() async throws {
    let cacheURL = try temporaryCacheURL()
    let createdAt = InstantTimestamp(milliseconds: 1_700_000_000_000)
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "test-app",
        persistenceURL: cacheURL,
        initialAttributes: TodoExample.attributes
      )
    )
    try await runtime.transact(
      InstantStoreTransaction(
        id: "tx-confirm-failure",
        operations: TodoExample.createOperations(
          id: "todo-confirm-failure",
          text: "confirm failure",
          createdAt: createdAt,
          transactionID: "tx-confirm-failure"
        )
      ),
      createdAt: createdAt
    )
    try dropOutboxTable(at: cacheURL)

    do {
      try await runtime.confirmMutation(id: "tx-confirm-failure")
      #expect(Bool(false), "Expected failed outbox persistence to throw.")
    } catch let error as InstantError {
      expectNoDifference(error.code, .persistenceFailed)
    } catch {
      #expect(Bool(false), "Unexpected error: \(error)")
    }

    let mutations = await runtime.outboxMutations()
    let pending = await runtime.pendingMutations()
    expectNoDifference(mutations.map(\.id), ["tx-confirm-failure"])
    expectNoDifference(mutations.map(\.status), [.pending])
    expectNoDifference(pending.map(\.id), ["tx-confirm-failure"])
  }

  @Test
  func failedOutboxFailureMarkDoesNotMutateLiveState() async throws {
    let cacheURL = try temporaryCacheURL()
    let createdAt = InstantTimestamp(milliseconds: 1_700_000_000_000)
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "test-app",
        persistenceURL: cacheURL,
        initialAttributes: TodoExample.attributes
      )
    )
    try await runtime.transact(
      InstantStoreTransaction(
        id: "tx-fail-failure",
        operations: TodoExample.createOperations(
          id: "todo-fail-failure",
          text: "fail failure",
          createdAt: createdAt,
          transactionID: "tx-fail-failure"
        )
      ),
      createdAt: createdAt
    )
    try dropOutboxTable(at: cacheURL)

    do {
      try await runtime.failMutation(id: "tx-fail-failure", message: "server rejected")
      #expect(Bool(false), "Expected failed outbox persistence to throw.")
    } catch let error as InstantError {
      expectNoDifference(error.code, .persistenceFailed)
    } catch {
      #expect(Bool(false), "Unexpected error: \(error)")
    }

    let mutations = await runtime.outboxMutations()
    let pending = await runtime.pendingMutations()
    expectNoDifference(mutations.map(\.id), ["tx-fail-failure"])
    expectNoDifference(mutations.map(\.status), [.pending])
    expectNoDifference(mutations.map(\.failureMessage), [nil])
    expectNoDifference(pending.map(\.id), ["tx-fail-failure"])
  }

  @Test
  func localIDsPersistByNameAcrossLaunches() async throws {
    let cacheURL = try temporaryCacheURL()
    let firstRuntime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "test-app",
        persistenceURL: cacheURL,
        makeID: { "local-1" }
      )
    )

    let firstID = try await firstRuntime.localID(named: "todos.viewer")
    expectNoDifference(firstID, "local-1")

    let relaunchedRuntime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "test-app",
        persistenceURL: cacheURL,
        makeID: { "local-2" }
      )
    )

    let relaunchedID = try await relaunchedRuntime.localID(named: "todos.viewer")
    let otherID = try await relaunchedRuntime.localID(named: "todos.other")
    expectNoDifference(relaunchedID, "local-1")
    expectNoDifference(otherID, "local-2")
  }

  @Test
  func concurrentLocalIDResolutionsConvergeAcrossRuntimes() async throws {
    let cacheURL = try temporaryCacheURL()
    let warmRuntime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "test-app",
        persistenceURL: cacheURL,
        makeID: { "warm-local-id" }
      )
    )
    let warmID = try await warmRuntime.localID(named: "todos.viewer")
    expectNoDifference(warmID, "warm-local-id")

    let ids = try await withThrowingTaskGroup(of: String.self) { group in
      for index in 0..<20 {
        group.addTask {
          let runtime = try await InstantRuntime.bootstrap(
            configuration: InstantRuntimeConfiguration(
              appID: "test-app",
              persistenceURL: cacheURL,
              makeID: { "local-\(index)" }
            )
          )
          return try await runtime.localID(named: "todos.viewer")
        }
      }

      var ids: [String] = []
      for try await id in group {
        ids.append(id)
      }
      return ids
    }

    expectNoDifference(Set(ids), ["warm-local-id"])
  }

  @Test
  func authSessionsPersistByAppIDAcrossLaunchesAndSignOut() async throws {
    let cacheURL = try temporaryCacheURL()
    let signedInAt = InstantTimestamp(milliseconds: 1_700_000_000_000)
    let guestRuntime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "app-a",
        persistenceURL: cacheURL,
        now: { signedInAt },
        makeID: { "guest-user" }
      )
    )

    let guest = try await guestRuntime.signInAsGuest()
    expectNoDifference(
      guest,
      InstantAuthSession(
        appID: "app-a",
        userID: "guest-user",
        refreshToken: "local-guest:app-a:guest-user",
        isGuest: true,
        createdAt: signedInAt,
        updatedAt: signedInAt
      )
    )

    let tokenRuntime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "app-b",
        persistenceURL: cacheURL,
        now: { signedInAt }
      )
    )
    let token = try await tokenRuntime.signInWithRefreshToken("refresh-token", userID: "token-user")
    expectNoDifference(token.userID, "token-user")
    expectNoDifference(token.refreshToken, "refresh-token")
    expectNoDifference(token.isGuest, false)

    let relaunchedGuestRuntime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(appID: "app-a", persistenceURL: cacheURL)
    )
    let relaunchedTokenRuntime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(appID: "app-b", persistenceURL: cacheURL)
    )
    let relaunchedGuest = try await relaunchedGuestRuntime.authSession()
    let relaunchedToken = try await relaunchedTokenRuntime.authSession()
    expectNoDifference(relaunchedGuest, guest)
    expectNoDifference(relaunchedToken, token)

    try await relaunchedGuestRuntime.signOut()

    let signedOutGuestRuntime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(appID: "app-a", persistenceURL: cacheURL)
    )
    let stillSignedInTokenRuntime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(appID: "app-b", persistenceURL: cacheURL)
    )
    let signedOutGuest = try await signedOutGuestRuntime.authSession()
    let stillSignedInToken = try await stillSignedInTokenRuntime.authSession()
    expectNoDifference(signedOutGuest, nil)
    expectNoDifference(stillSignedInToken, token)
  }

  @Test
  func guestSignInUsesAuthenticatorAndPersistsRefreshToken() async throws {
    let cacheURL = try temporaryCacheURL()
    let signedInAt = InstantTimestamp(milliseconds: 1_700_000_000_000)
    let requests = LockIsolated<[InstantGuestAuthRequest]>([])
    let authenticator = InstantGuestAuthenticator { request in
      requests.withValue { $0.append(request) }
      return InstantGuestAuthVerification(
        userID:
          "guest:\(request.appID):\(request.signedInAt.milliseconds):\(request.makeID())",
        refreshToken: "guest-refresh-token"
      )
    }
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "app-a",
        persistenceURL: cacheURL,
        now: { signedInAt },
        makeID: { "guest-user" },
        guestAuthenticator: authenticator
      )
    )

    let session = try await runtime.signInAsGuest()
    expectNoDifference(
      session,
      InstantAuthSession(
        appID: "app-a",
        userID: "guest:app-a:1700000000000:guest-user",
        refreshToken: "guest-refresh-token",
        isGuest: true,
        createdAt: signedInAt,
        updatedAt: signedInAt
      )
    )
    let authenticatorRequests = requests.withValue { $0 }
    expectNoDifference(authenticatorRequests.count, 1)
    expectNoDifference(authenticatorRequests.first?.appID, "app-a")
    expectNoDifference(authenticatorRequests.first?.apiURI.absoluteString, "https://api.instantdb.com")
    expectNoDifference(authenticatorRequests.first?.signedInAt, signedInAt)

    let relaunchedRuntime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(appID: "app-a", persistenceURL: cacheURL)
    )
    let persistedSession = try await relaunchedRuntime.authSession()
    expectNoDifference(persistedSession, session)
  }

  @Test
  func liveGuestAuthenticatorDecodesCanonicalResponse() async throws {
    let requests = LockIsolated<[URLRequest]>([])
    let authenticator = InstantGuestAuthenticator.live(
      httpClient: InstantAuthHTTPClient { request in
        requests.withValue { $0.append(request) }
        return InstantAuthHTTPResponse(
          statusCode: 200,
          data: Data(
            """
            {
              "user": {
                "id": "guest-user",
                "refresh_token": "guest-refresh-token",
                "type": "guest"
              }
            }
            """.utf8
          )
        )
      }
    )

    let verification = try await authenticator.signIn(
      InstantGuestAuthRequest(
        appID: "app-a",
        apiURI: try #require(URL(string: "https://api.example.test")),
        signedInAt: InstantTimestamp(milliseconds: 1_700_000_000_000),
        makeID: { "unused-local-id" }
      )
    )

    expectNoDifference(
      verification,
      InstantGuestAuthVerification(
        userID: "guest-user",
        refreshToken: "guest-refresh-token"
      )
    )
    let sentRequests = requests.withValue { $0 }
    expectNoDifference(sentRequests.count, 1)
    expectNoDifference(
      sentRequests.first?.url?.absoluteString,
      "https://api.example.test/runtime/auth/sign_in_guest"
    )
    expectNoDifference(sentRequests.first?.httpMethod, "POST")
    expectNoDifference(
      sentRequests.first.flatMap { $0.httpBody }.flatMap {
        String(data: $0, encoding: .utf8)
      },
      #"{"app-id":"app-a"}"#
    )
  }

  @Test
  func refreshTokenSignInUsesVerifierAndPersistsSession() async throws {
    let cacheURL = try temporaryCacheURL()
    let signedInAt = InstantTimestamp(milliseconds: 1_700_000_000_000)
    let requests = LockIsolated<[InstantRefreshTokenVerificationRequest]>([])
    let verifier = InstantRefreshTokenVerifier(
      verify: { request in
        requests.withValue { $0.append(request) }
        return InstantRefreshTokenVerification(
          userID:
            "dependency:\(request.appID):\(request.refreshToken):\(request.userID ?? "nil"):\(request.signedInAt.milliseconds):\(request.makeID())",
          refreshToken: "verified:\(request.refreshToken)"
        )
      }
    )
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "app-a",
        persistenceURL: cacheURL,
        now: { signedInAt },
        makeID: { "local-user-id" },
        refreshTokenVerifier: verifier
      )
    )

    let session = try await runtime.signInWithRefreshToken(
      " refresh-token ",
      userID: " token-user "
    )
    expectNoDifference(
      session,
      InstantAuthSession(
        appID: "app-a",
        userID: "dependency:app-a:refresh-token:token-user:1700000000000:local-user-id",
        refreshToken: "verified:refresh-token",
        isGuest: false,
        createdAt: signedInAt,
        updatedAt: signedInAt
      )
    )
    let verifierRequests = requests.withValue { $0 }
    expectNoDifference(verifierRequests.count, 1)
    expectNoDifference(verifierRequests.first?.appID, "app-a")
    expectNoDifference(verifierRequests.first?.refreshToken, "refresh-token")
    expectNoDifference(verifierRequests.first?.userID, "token-user")
    expectNoDifference(verifierRequests.first?.signedInAt, signedInAt)

    let relaunchedRuntime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(appID: "app-a", persistenceURL: cacheURL)
    )
    let persistedSession = try await relaunchedRuntime.authSession()
    expectNoDifference(persistedSession, session)
  }

  @Test
  func oauthEndpointHelpersUseConfiguredEndpoints() async throws {
    let cacheURL = try temporaryCacheURL()
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "app-a",
        apiURI: try #require(URL(string: "https://api.example.test/custom")),
        websocketURI: try #require(URL(string: "wss://ws.example.test/runtime/session")),
        persistenceURL: cacheURL
      )
    )

    let redirectURL = try #require(URL(string: "myapp://oauth/callback?state=abc&next=/home"))
    let authorizationURL = try runtime.oauthAuthorizationURL(
      clientName: " google-ios ",
      redirectURL: redirectURL
    )
    let components = try #require(URLComponents(url: authorizationURL, resolvingAgainstBaseURL: false))
    expectNoDifference(components.scheme, "https")
    expectNoDifference(components.host, "api.example.test")
    expectNoDifference(components.path, "/custom/runtime/oauth/start")
    let queryItems = Dictionary(
      uniqueKeysWithValues: (components.queryItems ?? []).compactMap { item in
        item.value.map { (item.name, $0) }
      }
    )
    expectNoDifference(queryItems["app_id"], "app-a")
    expectNoDifference(queryItems["client_name"], "google-ios")
    expectNoDifference(queryItems["redirect_uri"], redirectURL.absoluteString)

    let issuerURI = try runtime.issuerURI()
    expectNoDifference(issuerURI.absoluteString, "https://api.example.test/custom/runtime/app-a")
    expectNoDifference(
      runtime.configuration.websocketURI.absoluteString,
      "wss://ws.example.test/runtime/session"
    )
  }

  @Test
  func invalidOAuthEndpointInputsFailWithAuthError() async throws {
    let cacheURL = try temporaryCacheURL()
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(appID: "app-a", persistenceURL: cacheURL)
    )

    do {
      _ = try runtime.oauthAuthorizationURL(
        clientName: " ",
        redirectURL: try #require(URL(string: "myapp://oauth"))
      )
      #expect(Bool(false), "Expected empty OAuth client name to fail.")
    } catch let error as InstantError {
      expectNoDifference(error.code, .authFailed)
      expectNoDifference(error.operation, "create oauth authorization URL")
      #expect(error.description.contains("OAuth client name must not be empty"))
    } catch {
      #expect(Bool(false), "Unexpected error: \(error)")
    }

    do {
      _ = try runtime.oauthAuthorizationURL(
        clientName: "google-ios",
        redirectURL: try #require(URL(string: "relative/path"))
      )
      #expect(Bool(false), "Expected relative OAuth redirect URL to fail.")
    } catch let error as InstantError {
      expectNoDifference(error.code, .authFailed)
      expectNoDifference(error.operation, "create oauth authorization URL")
      #expect(error.description.contains("OAuth redirect URL must be absolute"))
    } catch {
      #expect(Bool(false), "Unexpected error: \(error)")
    }
  }

  @Test
  func invalidEndpointConfigurationFailsBootstrap() async throws {
    do {
      _ = try await InstantRuntime.bootstrap(
        configuration: InstantRuntimeConfiguration(
          appID: "app-a",
          apiURI: try #require(URL(string: "https://api.example.test?query=1")),
          persistenceURL: try temporaryCacheURL()
        )
      )
      #expect(Bool(false), "Expected apiURI with a query to fail.")
    } catch let error as InstantError {
      expectNoDifference(error.code, .validationFailed)
      expectNoDifference(error.operation, "bootstrap endpoint configuration")
      expectNoDifference(error.path, "apiURI")
      #expect(error.description.contains("no query or fragment"))
    } catch {
      #expect(Bool(false), "Unexpected error: \(error)")
    }

    do {
      _ = try await InstantRuntime.bootstrap(
        configuration: InstantRuntimeConfiguration(
          appID: "app-a",
          websocketURI: try #require(URL(string: "https://ws.example.test/runtime/session")),
          persistenceURL: try temporaryCacheURL()
        )
      )
      #expect(Bool(false), "Expected websocketURI with an HTTP scheme to fail.")
    } catch let error as InstantError {
      expectNoDifference(error.code, .validationFailed)
      expectNoDifference(error.operation, "bootstrap endpoint configuration")
      expectNoDifference(error.path, "websocketURI")
      #expect(error.description.contains("absolute ws or wss URL"))
    } catch {
      #expect(Bool(false), "Unexpected error: \(error)")
    }
  }

  @Test
  func signOutInvalidatesRefreshTokenWhenRequestedAndClearsSession() async throws {
    let cacheURL = try temporaryCacheURL()
    let signedOutAt = InstantTimestamp(milliseconds: 1_700_000_000_000)
    let invalidations = LockIsolated<[InstantAuthTokenInvalidationRequest]>([])
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "app-a",
        persistenceURL: cacheURL,
        now: { signedOutAt },
        authTokenInvalidator: InstantAuthTokenInvalidator(
          invalidate: { request in
            invalidations.withValue { $0.append(request) }
          }
        )
      )
    )

    _ = try await runtime.signInWithRefreshToken("refresh-token", userID: "token-user")
    let signOut: () async throws -> Void = runtime.signOut
    try await signOut()
    let signedOutSession = try await runtime.authSession()
    expectNoDifference(signedOutSession, nil)
    let defaultInvalidations = invalidations.withValue { $0 }
    expectNoDifference(defaultInvalidations.count, 1)
    expectNoDifference(defaultInvalidations.first?.appID, "app-a")
    expectNoDifference(defaultInvalidations.first?.refreshToken, "refresh-token")
    expectNoDifference(defaultInvalidations.first?.signedOutAt, signedOutAt)

    _ = try await runtime.signInWithRefreshToken("second-refresh-token", userID: "token-user")
    try await runtime.signOut(invalidateToken: false)
    let skippedInvalidationSession = try await runtime.authSession()
    expectNoDifference(skippedInvalidationSession, nil)
    expectNoDifference(invalidations.withValue { $0.count }, 1)
  }

  @Test
  func signOutIgnoresTokenInvalidationFailuresAfterClearingSession() async throws {
    let cacheURL = try temporaryCacheURL()
    let invalidationCount = LockIsolated(0)
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "app-a",
        persistenceURL: cacheURL,
        authTokenInvalidator: InstantAuthTokenInvalidator(
          invalidate: { _ in
            invalidationCount.withValue { $0 += 1 }
            throw InstantError(
              code: .networkFailed,
              operation: "invalidate auth token",
              message: "The local invalidator failed.",
              recovery: "Retry sign-out."
            )
          }
        )
      )
    )

    _ = try await runtime.signInWithRefreshToken("refresh-token", userID: "token-user")
    try await runtime.signOut()
    let signedOutSession = try await runtime.authSession()
    expectNoDifference(signedOutSession, nil)
    expectNoDifference(invalidationCount.withValue { $0 }, 1)
  }

  @Test
  func authSessionObservationEmitsCurrentAndDurableChanges() async throws {
    let cacheURL = try temporaryCacheURL()
    let timestamp = InstantTimestamp(milliseconds: 1_700_000_000_000)
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "app-a",
        persistenceURL: cacheURL,
        now: { timestamp },
        makeID: { UUID().uuidString.lowercased() }
      )
    )

    let stream = try await runtime.observeAuthSession()
    var iterator = stream.makeAsyncIterator()
    let initial = try #require(await iterator.next())
    expectNoDifference(initial, nil)

    let guest = try await runtime.signInAsGuest()
    let observedGuest = try #require(await iterator.next())
    expectNoDifference(observedGuest, guest)

    try await runtime.signOut()
    let observedSignOut = try #require(await iterator.next())
    expectNoDifference(observedSignOut, nil)

    let challenge = try await runtime.sendMagicCode(email: "User@Example.com")
    let magic = try await runtime.signInWithMagicCode(
      email: "user@example.com",
      code: challenge.code
    )
    let observedMagic = try #require(await iterator.next())
    expectNoDifference(observedMagic, magic)

    let token = try await runtime.signInWithRefreshToken("refresh-token", userID: "token-user")
    let observedToken = try #require(await iterator.next())
    expectNoDifference(observedToken, token)
  }

  @Test
  func authSessionObservationRegistersAtomicallyWithInFlightSignIn() async throws {
    let cacheURL = try temporaryCacheURL()
    let timestamp = InstantTimestamp(milliseconds: 1_700_000_000_000)
    let verifyEntered = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
    let resumeVerify = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
    let exchange = InstantMagicCodeExchange(
      send: { request in
        InstantMagicCodeChallenge(
          appID: request.appID,
          email: request.email,
          code: "135790",
          createdAt: request.sentAt,
          expiresAt: InstantTimestamp(milliseconds: request.sentAt.milliseconds + 60_000)
        )
      },
      verify: { request in
        verifyEntered.continuation.yield(())
        var iterator = resumeVerify.stream.makeAsyncIterator()
        _ = await iterator.next()
        return InstantMagicCodeVerification(
          userID: "email:\(request.email)",
          refreshToken: "local-magic:\(request.appID):\(request.email)"
        )
      }
    )
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "app-a",
        persistenceURL: cacheURL,
        now: { timestamp },
        magicCodeExchange: exchange
      )
    )

    let challenge = try await runtime.sendMagicCode(email: "User@Example.com")
    let signInTask = Task {
      try await runtime.signInWithMagicCode(email: "user@example.com", code: challenge.code)
    }
    var verifyEnteredIterator = verifyEntered.stream.makeAsyncIterator()
    _ = await verifyEnteredIterator.next()

    let observeTask = Task {
      try await runtime.observeAuthSession()
    }
    try await Task.sleep(nanoseconds: 10_000_000)
    resumeVerify.continuation.yield(())

    let stream = try await observeTask.value
    var iterator = stream.makeAsyncIterator()
    let observedSession = try #require(await iterator.next())
    let signedInSession = try await signInTask.value
    expectNoDifference(observedSession, signedInSession)
  }

  @Test
  func magicCodeSignInResultPersistsExtraFieldsAndCreatedFlag() async throws {
    let cacheURL = try temporaryCacheURL()
    let timestamp = InstantTimestamp(milliseconds: 1_700_000_031_000)
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "auth-extra-fields",
        persistenceURL: cacheURL,
        initialAttributes: [
          InstantAttribute(
            id: "$users/email",
            namespace: "$users",
            name: "email",
            valueType: .string,
            isRequired: false,
            isIndexed: true,
            isUnique: true
          ),
          InstantAttribute(
            id: "$users/username",
            namespace: "$users",
            name: "username",
            valueType: .string,
            isRequired: false,
            isIndexed: true,
            isUnique: true
          ),
          InstantAttribute(
            id: "$users/displayName",
            namespace: "$users",
            name: "displayName",
            valueType: .string,
            isRequired: false
          ),
        ],
        now: { timestamp },
        makeID: { "123456" }
      )
    )

    let firstChallenge = try await runtime.sendMagicCode(email: "New@Example.com")
    let firstSignIn = try await runtime.signInWithMagicCodeResult(
      email: "new@example.com",
      code: firstChallenge.code,
      extraFields: [
        "username": .string("cool_user"),
        "displayName": .string("Cool User"),
      ]
    )
    expectNoDifference(firstSignIn.created, true)
    expectNoDifference(firstSignIn.session.userID, "email:new@example.com")

    let users = try await runtime.query(
      InstantQueryPlan(id: "auth-extra-fields.users", namespace: "$users")
    )
    let user = try #require(users.first { $0.id == "email:new@example.com" })
    expectNoDifference(
      user.values,
      [
        "id": .one(.string("email:new@example.com")),
        "email": .one(.string("new@example.com")),
        "username": .one(.string("cool_user")),
        "displayName": .one(.string("Cool User")),
      ]
    )
    let pendingMutations = await runtime.pendingMutations()
    expectNoDifference(pendingMutations, [])

    let secondChallenge = try await runtime.sendMagicCode(email: "new@example.com")
    let secondSignIn = try await runtime.signInWithMagicCodeResult(
      email: "new@example.com",
      code: secondChallenge.code,
      extraFields: [
        "username": .string("should-not-overwrite"),
        "displayName": .string("Should Not Overwrite"),
      ]
    )
    expectNoDifference(secondSignIn.created, false)
    expectNoDifference(secondSignIn.session.userID, "email:new@example.com")
    let returningUser = try #require(
      try await runtime.query(
        InstantQueryPlan(id: "auth-extra-fields.returning-user", namespace: "$users")
      )
      .first { $0.id == "email:new@example.com" }
    )
    expectNoDifference(returningUser.values, user.values)

    let compatChallenge = try await runtime.sendMagicCode(email: "compat@example.com")
    let compatSignIn = try await runtime.signInWithMagicCodeResult(
      email: "compat@example.com",
      code: compatChallenge.code
    )
    expectNoDifference(compatSignIn.created, true)
    expectNoDifference(compatSignIn.session.userID, "email:compat@example.com")
    let compatUser = try #require(
      try await runtime.query(
        InstantQueryPlan(id: "auth-extra-fields.compat-user", namespace: "$users")
      )
      .first { $0.id == "email:compat@example.com" }
    )
    expectNoDifference(
      compatUser.values,
      [
        "id": .one(.string("email:compat@example.com")),
        "email": .one(.string("compat@example.com")),
      ]
    )
  }

  @Test
  func magicCodeExtraFieldsRequireUsersSchemaWhenSchemaIsDeclared() async throws {
    let cacheURL = try temporaryCacheURL()
    let timestamp = InstantTimestamp(milliseconds: 1_700_000_032_000)
    let verifyCount = LockIsolated(0)
    let exchange = InstantMagicCodeExchange(
      send: InstantMagicCodeExchange.local.send,
      verify: { request in
        verifyCount.withValue { $0 += 1 }
        return try await InstantMagicCodeExchange.local.verify(request)
      }
    )
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "auth-extra-fields-schema",
        persistenceURL: cacheURL,
        initialAttributes: TodoExample.attributes,
        now: { timestamp },
        makeID: { "654321" },
        magicCodeExchange: exchange
      )
    )

    let challenge = try await runtime.sendMagicCode(email: "user@example.com")
    do {
      _ = try await runtime.signInWithMagicCodeResult(
        email: "user@example.com",
        code: challenge.code,
        extraFields: ["username": .string("cool_user")]
      )
      Issue.record("Expected magic-code extra fields to require a $users schema.")
    } catch let error as InstantError {
      expectNoDifference(error.code, .validationFailed)
      expectNoDifference(error.namespace, "$users")
      expectNoDifference(
        error.message,
        "Cannot write magic-code extra fields because the '$users' namespace is not declared in the local schema."
      )
    }
    expectNoDifference(verifyCount.withValue { $0 }, 0)

    let session = try await runtime.signInWithMagicCode(
      email: "user@example.com",
      code: challenge.code
    )
    expectNoDifference(session.userID, "email:user@example.com")
  }

  @Test
  func roomPresenceAndTopicsPersistByAppIDAcrossLaunches() async throws {
    let cacheURL = try temporaryCacheURL()
    let room = InstantRoomHandle(type: "chat", id: "lobby")
    let firstTimestamp = InstantTimestamp(milliseconds: 1_700_000_000_000)
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "app-a",
        persistenceURL: cacheURL,
        now: { firstTimestamp },
        makeID: { "message-1" }
      )
    )
    _ = try await runtime.signInWithRefreshToken("refresh-token", userID: "user-1")

    let member = try await runtime.setPresence(
      room: room,
      values: [
        "name": .string("Blob"),
        "status": .string("online"),
      ]
    )
    expectNoDifference(
      member,
      InstantRoomPresenceMember(
        appID: "app-a",
        room: room,
        userID: "user-1",
        values: [
          "name": .string("Blob"),
          "status": .string("online"),
        ],
        updatedAt: firstTimestamp
      )
    )

    let message = try await runtime.publishTopicMessage(
      room: room,
      topic: "sendEmoji",
      payload: .object(["emoji": .string("wave")])
    )
    expectNoDifference(
      message,
      InstantRoomTopicMessage(
        id: "message-1",
        appID: "app-a",
        room: room,
        topic: "sendEmoji",
        userID: "user-1",
        payload: .object(["emoji": .string("wave")]),
        createdAt: firstTimestamp
      )
    )

    let relaunchedRuntime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "app-a",
        persistenceURL: cacheURL,
        now: { InstantTimestamp(milliseconds: firstTimestamp.milliseconds + 1_000) }
      )
    )
    let relaunchedPresence = try await relaunchedRuntime.roomPresence(room: room)
    let relaunchedMessages = try await relaunchedRuntime.roomTopicMessages(
      room: room,
      topic: "sendEmoji"
    )
    expectNoDifference(relaunchedPresence, [member])
    expectNoDifference(relaunchedMessages, [message])

    _ = try await relaunchedRuntime.setPresence(
      room: room,
      userID: " user-1 ",
      values: ["status": .string("away")]
    )
    let updatedMembers = try await relaunchedRuntime.roomPresence(room: room)
    expectNoDifference(updatedMembers.map(\.userID), ["user-1"])
    expectNoDifference(updatedMembers.first?.values, ["status": .string("away")])

    let otherAppRuntime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "app-b",
        persistenceURL: cacheURL,
        now: { firstTimestamp },
        makeID: { "message-1" }
      )
    )
    _ = try await otherAppRuntime.signInWithRefreshToken("other-refresh", userID: "user-2")
    let otherAppMessage = try await otherAppRuntime.publishTopicMessage(
      room: room,
      topic: "sendEmoji",
      payload: .object(["emoji": .string("other")])
    )
    let otherAppPresence = try await otherAppRuntime.roomPresence(room: room)
    let otherAppMessages = try await otherAppRuntime.roomTopicMessages(
      room: room,
      topic: "sendEmoji"
    )
    expectNoDifference(otherAppPresence, [])
    expectNoDifference(
      otherAppMessages,
      [
        InstantRoomTopicMessage(
          id: "message-1",
          appID: "app-b",
          room: room,
          topic: "sendEmoji",
          userID: "user-2",
          payload: .object(["emoji": .string("other")]),
          createdAt: firstTimestamp
        )
      ]
    )
    expectNoDifference(otherAppMessage.id, message.id)
    let appMessagesAfterOtherAppCollision = try await relaunchedRuntime.roomTopicMessages(
      room: room,
      topic: "sendEmoji"
    )
    expectNoDifference(appMessagesAfterOtherAppCollision, [message])

    let leftUserID = try await relaunchedRuntime.leavePresence(room: room, userID: nil)
    let remainingPresence = try await relaunchedRuntime.roomPresence(room: room)
    expectNoDifference(leftUserID, "user-1")
    expectNoDifference(remainingPresence, [])
  }

  @Test
  func roomPresenceAndTopicsRequireAuthOrExplicitUserID() async throws {
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "test-app",
        persistenceURL: temporaryCacheURL()
      )
    )
    let room = InstantRoomHandle(type: "chat", id: "lobby")

    do {
      _ = try await runtime.setPresence(room: room, values: ["status": .string("online")])
      #expect(Bool(false), "Expected anonymous presence to fail.")
    } catch let error as InstantError {
      expectNoDifference(error.code, .authFailed)
      expectNoDifference(error.operation, "set room presence")
    } catch {
      #expect(Bool(false), "Unexpected error: \(error)")
    }

    do {
      _ = try await runtime.publishTopicMessage(
        room: room,
        topic: "sendEmoji",
        payload: .string("wave")
      )
      #expect(Bool(false), "Expected anonymous topic publish to fail.")
    } catch let error as InstantError {
      expectNoDifference(error.code, .authFailed)
      expectNoDifference(error.operation, "publish room topic")
    } catch {
      #expect(Bool(false), "Unexpected error: \(error)")
    }

    let member = try await runtime.setPresence(
      room: room,
      userID: "user-1",
      values: ["status": .string("online")]
    )
    expectNoDifference(member.userID, "user-1")
  }

  @Test
  func roomTopicMigrationPreservesLegacyRowsAndScopesMessageIDsByApp() async throws {
    let cacheURL = try temporaryCacheURL()
    let room = InstantRoomHandle(type: "chat", id: "lobby")
    let legacyMessage = InstantRoomTopicMessage(
      id: "message-1",
      appID: "app-a",
      room: room,
      topic: "sendEmoji",
      userID: "user-1",
      payload: .object(["emoji": .string("wave")]),
      createdAt: InstantTimestamp(milliseconds: 1_700_000_000_000)
    )

    do {
      let persistence = try SQLitePersistenceStore(fileURL: cacheURL)
      try await persistence.bootstrap()
    }
    try seedLegacyRoomTopicMessageBeforeAppScopedMigration(at: cacheURL, message: legacyMessage)

    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(appID: "app-a", persistenceURL: cacheURL)
    )
    let migratedMessages = try await runtime.roomTopicMessages(room: room, topic: "sendEmoji")
    expectNoDifference(migratedMessages, [legacyMessage])

    let otherAppRuntime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "app-b",
        persistenceURL: cacheURL,
        now: { legacyMessage.createdAt },
        makeID: { legacyMessage.id }
      )
    )
    _ = try await otherAppRuntime.signInWithRefreshToken("other-refresh", userID: "user-2")
    let otherMessage = try await otherAppRuntime.publishTopicMessage(
      room: room,
      topic: "sendEmoji",
      payload: .object(["emoji": .string("spark")])
    )

    expectNoDifference(otherMessage.id, legacyMessage.id)
    let appMessages = try await runtime.roomTopicMessages(room: room, topic: "sendEmoji")
    let otherAppMessages = try await otherAppRuntime.roomTopicMessages(room: room, topic: "sendEmoji")
    expectNoDifference(appMessages, [legacyMessage])
    expectNoDifference(
      otherAppMessages,
      [
        InstantRoomTopicMessage(
          id: "message-1",
          appID: "app-b",
          room: room,
          topic: "sendEmoji",
          userID: "user-2",
          payload: .object(["emoji": .string("spark")]),
          createdAt: legacyMessage.createdAt
        )
      ]
    )
  }

  @Test
  func roomTopicsPreservePublicationOrderWhenTimestampsMatch() async throws {
    let ids = LockIsolated(["z-first", "a-second"])
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "room-topic-order",
        persistenceURL: temporaryCacheURL(),
        now: { InstantTimestamp(milliseconds: 1_700_000_000_000) },
        makeID: { ids.withValue { $0.removeFirst() } }
      )
    )
    _ = try await runtime.signInWithRefreshToken("refresh-token", userID: "user-1")
    let room = InstantRoomHandle(type: "chat", id: "lobby")

    _ = try await runtime.publishTopicMessage(
      room: room,
      topic: "reaction",
      payload: .string("first")
    )
    _ = try await runtime.publishTopicMessage(
      room: room,
      topic: "reaction",
      payload: .string("second")
    )

    let messageIDs = try await runtime.roomTopicMessages(room: room, topic: "reaction").map(\.id)
    expectNoDifference(messageIDs, ["z-first", "a-second"])
  }

  @Test
  func reactionsRecipePayloadsDecodeTopicMessages() async throws {
    let timestamp = InstantTimestamp(milliseconds: 1_700_000_000_000)
    let idSequence = LockIsolated(0)
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "reactions-test",
        persistenceURL: temporaryCacheURL(),
        now: { timestamp },
        makeID: {
          let nextID = idSequence.withValue { value in
            value += 1
            return value
          }
          return "message-\(nextID)"
        }
      )
    )
    _ = try await runtime.signInWithRefreshToken("refresh-token", userID: "user-1")

    let firePayload = ReactionsRecipeExample.payload(
      name: "fire",
      directionAngle: 45,
      rotationAngle: 90
    )
    let fireMessage = try await runtime.publishTopicMessage(
      room: ReactionsRecipeExample.room,
      topic: ReactionsRecipeExample.topic,
      payload: firePayload
    )
    expectNoDifference(
      fireMessage.payload,
      .object([
        "directionAngle": .number(45),
        "name": .string("fire"),
        "rotationAngle": .number(90),
      ])
    )

    _ = try await runtime.publishTopicMessage(
      room: ReactionsRecipeExample.room,
      topic: ReactionsRecipeExample.topic,
      userID: "user-2",
      payload: ReactionsRecipeExample.payload(
        name: "wave",
        directionAngle: 135,
        rotationAngle: 180
      )
    )
    _ = try await runtime.publishTopicMessage(
      room: ReactionsRecipeExample.room,
      topic: ReactionsRecipeExample.topic,
      userID: "user-3",
      payload: ReactionsRecipeExample.payload(
        name: "confetti",
        directionAngle: 200,
        rotationAngle: 315
      )
    )
    _ = try await runtime.publishTopicMessage(
      room: ReactionsRecipeExample.room,
      topic: ReactionsRecipeExample.topic,
      userID: "user-4",
      payload: .object([
        "directionAngle": .number(20),
        "name": .string("sparkle"),
        "rotationAngle": .number(30),
      ])
    )

    let messages = try await runtime.roomTopicMessages(
      room: ReactionsRecipeExample.room,
      topic: ReactionsRecipeExample.topic
    )
    let fireSymbol = try #require(ReactionsRecipeExample.symbol(forReactionName: "fire"))
    let waveSymbol = try #require(ReactionsRecipeExample.symbol(forReactionName: "wave"))
    let confettiSymbol = try #require(ReactionsRecipeExample.symbol(forReactionName: "confetti"))
    expectNoDifference(
      ReactionsRecipeExample.reactions(from: messages),
      [
        ReactionsRecipeReaction(
          id: "message-1",
          name: "fire",
          symbol: fireSymbol,
          directionAngle: 45,
          rotationAngle: 90,
          userID: "user-1",
          createdAt: timestamp
        ),
        ReactionsRecipeReaction(
          id: "message-2",
          name: "wave",
          symbol: waveSymbol,
          directionAngle: 135,
          rotationAngle: 180,
          userID: "user-2",
          createdAt: timestamp
        ),
        ReactionsRecipeReaction(
          id: "message-3",
          name: "confetti",
          symbol: confettiSymbol,
          directionAngle: 200,
          rotationAngle: 315,
          userID: "user-3",
          createdAt: timestamp
        ),
      ]
    )
    expectNoDifference(messages.count, 4)
    expectNoDifference(ReactionsRecipeExample.containsReactionName("heart"), true)
    expectNoDifference(ReactionsRecipeExample.containsReactionName("sparkle"), false)
    expectNoDifference(
      ReactionsRecipeExample.reaction(
        from: InstantRoomTopicMessage(
          id: "message-4",
          appID: "reactions-test",
          room: InstantRoomHandle(type: "chat", id: "lobby"),
          topic: ReactionsRecipeExample.topic,
          userID: "user-1",
          payload: firePayload,
          createdAt: timestamp
        )
      ),
      nil
    )
    let limited = try await runtime.roomTopicMessages(
      room: ReactionsRecipeExample.room,
      topic: ReactionsRecipeExample.topic,
      limit: 1
    )
    expectNoDifference(limited.map(\.id), ["message-1"])
  }

  @Test
  func typingIndicatorRecipeDerivesActivePresenceMembers() async throws {
    let timestamp = InstantTimestamp(milliseconds: 1_700_000_000_000)
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "typing-indicator-test",
        persistenceURL: temporaryCacheURL(),
        now: { timestamp }
      )
    )

    _ = try await runtime.setPresence(
      room: TypingIndicatorRecipeExample.room,
      userID: "user-1",
      values: TypingIndicatorRecipeExample.presenceValues(
        presenceID: "peer-1",
        isTyping: true
      )
    )
    _ = try await runtime.setPresence(
      room: TypingIndicatorRecipeExample.room,
      userID: "user-2",
      values: TypingIndicatorRecipeExample.presenceValues(
        presenceID: "peer-2",
        isTyping: false
      )
    )
    _ = try await runtime.setPresence(
      room: TypingIndicatorRecipeExample.room,
      userID: "user-3",
      values: [
        TypingIndicatorRecipeExample.idKey: .string("peer-3"),
        TypingIndicatorRecipeExample.inputName: .null,
      ]
    )
    _ = try await runtime.setPresence(
      room: TypingIndicatorRecipeExample.room,
      userID: "user-4",
      values: [TypingIndicatorRecipeExample.idKey: .string("peer-4")]
    )
    _ = try await runtime.setPresence(
      room: TypingIndicatorRecipeExample.room,
      userID: "user-5",
      values: [
        TypingIndicatorRecipeExample.inputName: .bool(true)
      ]
    )
    _ = try await runtime.setPresence(
      room: InstantRoomHandle(type: "chat", id: "lobby"),
      userID: "user-6",
      values: TypingIndicatorRecipeExample.presenceValues(
        presenceID: "peer-6",
        isTyping: true
      )
    )

    let presence = try await runtime.roomPresence(room: TypingIndicatorRecipeExample.room)
    expectNoDifference(
      TypingIndicatorRecipeExample.members(from: presence),
      [
        TypingIndicatorRecipeMember(
          userID: "user-1",
          presenceID: "peer-1",
          isTyping: true,
          updatedAt: timestamp
        ),
        TypingIndicatorRecipeMember(
          userID: "user-2",
          presenceID: "peer-2",
          isTyping: false,
          updatedAt: timestamp
        ),
        TypingIndicatorRecipeMember(
          userID: "user-3",
          presenceID: "peer-3",
          isTyping: false,
          updatedAt: timestamp
        ),
        TypingIndicatorRecipeMember(
          userID: "user-4",
          presenceID: "peer-4",
          isTyping: false,
          updatedAt: timestamp
        ),
        TypingIndicatorRecipeMember(
          userID: "user-5",
          presenceID: nil,
          isTyping: true,
          updatedAt: timestamp
        ),
      ]
    )
    expectNoDifference(
      TypingIndicatorRecipeExample.activeMembers(from: presence).map(\.userID),
      ["user-1", "user-5"]
    )
    expectNoDifference(
      TypingIndicatorRecipeExample.activeMembers(
        from: presence,
        excludingUserID: "user-1"
      )
      .map(\.userID),
      ["user-5"]
    )
    expectNoDifference(TypingIndicatorRecipeExample.typingInfo(activeCount: 0), nil)
    expectNoDifference(TypingIndicatorRecipeExample.typingInfo(activeCount: 1), "1 person is typing...")
    expectNoDifference(TypingIndicatorRecipeExample.typingInfo(activeCount: 2), "2 people are typing...")
    expectNoDifference(
      TypingIndicatorRecipeExample.member(
        from: InstantRoomPresenceMember(
          appID: "typing-indicator-test",
          room: InstantRoomHandle(type: "chat", id: "lobby"),
          userID: "user-7",
          values: TypingIndicatorRecipeExample.presenceValues(
            presenceID: "peer-7",
            isTyping: true
          ),
          updatedAt: timestamp
        )
      ),
      nil
    )
  }

  @Test
  func avatarStackRecipeBuildsViewerAndPeerSnapshot() async throws {
    let timestamp = InstantTimestamp(milliseconds: 1_700_000_000_000)
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "avatar-stack-test",
        persistenceURL: temporaryCacheURL(),
        now: { timestamp }
      )
    )

    _ = try await runtime.setPresence(
      room: AvatarStackRecipeExample.room,
      userID: "user-alpha",
      values: AvatarStackRecipeExample.presenceValues(
        name: AvatarStackRecipeExample.defaultName(forUserID: "user-alpha")
      )
    )
    _ = try await runtime.setPresence(
      room: AvatarStackRecipeExample.room,
      userID: "user-beta",
      values: AvatarStackRecipeExample.presenceValues(name: "Betty")
    )
    _ = try await runtime.setPresence(
      room: AvatarStackRecipeExample.room,
      userID: "user-missing",
      values: [:]
    )
    _ = try await runtime.setPresence(
      room: AvatarStackRecipeExample.room,
      userID: "user-number",
      values: [AvatarStackRecipeExample.nameKey: .number(42)]
    )

    let presence = try await runtime.roomPresence(room: AvatarStackRecipeExample.room)
    let viewerSnapshot = AvatarStackRecipeExample.snapshot(
      from: presence,
      viewerUserID: "user-alpha"
    )
    expectNoDifference(AvatarStackRecipeExample.defaultName(forUserID: "abcdefghi"), "abcdef")
    expectNoDifference(
      AvatarStackRecipeExample.presenceValues(name: "Alice"),
      [AvatarStackRecipeExample.nameKey: .string("Alice")]
    )
    expectNoDifference(
      viewerSnapshot,
      AvatarStackRecipeSnapshot(
        viewerUserID: "user-alpha",
        onlineCount: 2,
        currentUser: AvatarStackRecipeMember(
          userID: "user-alpha",
          name: "user-a",
          isViewer: true,
          updatedAt: timestamp
        ),
        peers: [
          AvatarStackRecipeMember(
            userID: "user-beta",
            name: "Betty",
            isViewer: false,
            updatedAt: timestamp
          )
        ],
        members: [
          AvatarStackRecipeMember(
            userID: "user-alpha",
            name: "user-a",
            isViewer: true,
            updatedAt: timestamp
          ),
          AvatarStackRecipeMember(
            userID: "user-beta",
            name: "Betty",
            isViewer: false,
            updatedAt: timestamp
          ),
        ]
      )
    )

    let terminalSnapshot = AvatarStackRecipeExample.snapshot(from: presence)
    expectNoDifference(terminalSnapshot.viewerUserID, nil)
    expectNoDifference(terminalSnapshot.onlineCount, 2)
    expectNoDifference(terminalSnapshot.currentUser, nil)
    expectNoDifference(terminalSnapshot.peers.map(\.userID), ["user-alpha", "user-beta"])
    expectNoDifference(terminalSnapshot.peers.map(\.isViewer), [false, false])
    expectNoDifference(
      AvatarStackRecipeExample.member(
        from: InstantRoomPresenceMember(
          appID: "avatar-stack-test",
          room: InstantRoomHandle(type: "chat", id: "lobby"),
          userID: "user-gamma",
          values: AvatarStackRecipeExample.presenceValues(name: "Gamma"),
          updatedAt: timestamp
        ),
        viewerUserID: "user-gamma"
      ),
      nil
    )
  }

  @Test
  func cursorsRecipeBuildsPeerVisibleSnapshots() async throws {
    let timestamp = InstantTimestamp(milliseconds: 1_700_000_000_000)
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "cursors-test",
        persistenceURL: temporaryCacheURL(),
        now: { timestamp }
      )
    )

    expectNoDifference(
      CursorsRecipeExample.spaceID,
      "cursors-space-default--cursors-example-123"
    )
    expectNoDifference(
      CursorsRecipeExample.spaceID(for: CursorsRecipeExample.customRoom),
      "cursors-space-default--cursors-example-124"
    )
    expectNoDifference(
      CursorsRecipeExample.cursorValues(
        x: 20,
        y: 40,
        width: 200,
        height: 80,
        color: "#123456"
      ),
      [
        CursorsRecipeExample.spaceID: .object([
          "color": .string("#123456"),
          "x": .number(20),
          "xPercent": .number(10),
          "y": .number(40),
          "yPercent": .number(50),
        ])
      ]
    )

    _ = try await runtime.setPresence(
      room: CursorsRecipeExample.room,
      userID: "user-alpha",
      values: CursorsRecipeExample.cursorValues(
        x: 10,
        y: 20,
        xPercent: 25,
        yPercent: 50,
        color: "#123456"
      )
    )
    _ = try await runtime.setPresence(
      room: CursorsRecipeExample.room,
      userID: "user-beta",
      values: CursorsRecipeExample.cursorValues(
        x: 30,
        y: 40,
        xPercent: 75,
        yPercent: 80
      )
    )
    _ = try await runtime.setPresence(
      room: CursorsRecipeExample.room,
      userID: "user-missing",
      values: [:]
    )
    _ = try await runtime.setPresence(
      room: CursorsRecipeExample.room,
      userID: "user-invalid",
      values: [CursorsRecipeExample.spaceID: .object(["x": .string("10")])]
    )
    _ = try await runtime.setPresence(
      room: CursorsRecipeExample.customRoom,
      userID: "user-custom",
      values: CursorsRecipeExample.customCursorValues(
        x: 1,
        y: 2,
        xPercent: 3,
        yPercent: 4,
        color: "#abcdef",
        name: "Ada"
      )
    )

    let presence = try await runtime.roomPresence(room: CursorsRecipeExample.room)
    let snapshot = CursorsRecipeExample.snapshot(
      from: presence,
      viewerUserID: "user-alpha"
    )
    expectNoDifference(
      snapshot,
      CursorsRecipeSnapshot(
        viewerUserID: "user-alpha",
        cursorCount: 1,
        visibleCursors: [
          CursorsRecipeCursor(
            userID: "user-beta",
            x: 30,
            y: 40,
            xPercent: 75,
            yPercent: 80,
            color: nil,
            name: nil,
            isViewer: false,
            updatedAt: timestamp
          )
        ],
        members: [
          CursorsRecipeCursor(
            userID: "user-alpha",
            x: 10,
            y: 20,
            xPercent: 25,
            yPercent: 50,
            color: "#123456",
            name: nil,
            isViewer: true,
            updatedAt: timestamp
          ),
          CursorsRecipeCursor(
            userID: "user-beta",
            x: 30,
            y: 40,
            xPercent: 75,
            yPercent: 80,
            color: nil,
            name: nil,
            isViewer: false,
            updatedAt: timestamp
          ),
        ]
      )
    )

    let terminalSnapshot = CursorsRecipeExample.snapshot(from: presence)
    expectNoDifference(terminalSnapshot.cursorCount, 2)
    expectNoDifference(terminalSnapshot.visibleCursors.map(\.userID), ["user-alpha", "user-beta"])
    let customPresence = try await runtime.roomPresence(room: CursorsRecipeExample.customRoom)
    expectNoDifference(
      CursorsRecipeExample.snapshot(
        from: customPresence,
        room: CursorsRecipeExample.customRoom,
        viewerUserID: "viewer"
      )
      .visibleCursors,
      [
        CursorsRecipeCursor(
          userID: "user-custom",
          x: 1,
          y: 2,
          xPercent: 3,
          yPercent: 4,
          color: "#abcdef",
          name: "Ada",
          isViewer: false,
          updatedAt: timestamp
        )
      ]
    )
  }

  @Test
  func mergeTileGameRecipeUsesMergeForIndependentTileTaps() async throws {
    let timestamp = InstantTimestamp(milliseconds: 1_700_000_000_000)
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "merge-tile-game-test",
        persistenceURL: temporaryCacheURL(),
        initialAttributes: MergeTileGameRecipeExample.attributes,
        now: { timestamp }
      )
    )

    expectNoDifference(MergeTileGameRecipeExample.namespace, "boards")
    expectNoDifference(
      MergeTileGameRecipeExample.boardID,
      "83c059e2-ed47-42e5-bdd9-6de88d26c521"
    )
    expectNoDifference(
      MergeTileGameRecipeExample.room,
      InstantRoomHandle(type: "tile-game-example", id: "_defaultRoomId")
    )
    expectNoDifference(MergeTileGameRecipeExample.boardSize, 4)
    expectNoDifference(MergeTileGameRecipeExample.emptyColor, "#f5f3f0")
    expectNoDifference(
      MergeTileGameRecipeExample.colors,
      ["#e76f51", "#2a9d8f", "#e9c46a", "#264653", "#f4a261", "#d4a0d0"]
    )
    expectNoDifference(MergeTileGameRecipeExample.cellKey(row: 3, column: 2), "3-2")
    expectNoDifference(MergeTileGameRecipeExample.isValidCell(row: 3, column: 3), true)
    expectNoDifference(MergeTileGameRecipeExample.isValidCell(row: 4, column: 0), false)
    let emptyState = MergeTileGameRecipeExample.makeEmptyBoardState()
    expectNoDifference(emptyState.count, 16)
    expectNoDifference(emptyState["0-0"], MergeTileGameRecipeExample.emptyColor)
    expectNoDifference(emptyState["3-3"], MergeTileGameRecipeExample.emptyColor)

    let createTransactionID = "tx-create-board"
    try await runtime.transact(
      InstantStoreTransaction(
        id: createTransactionID,
        operations: MergeTileGameRecipeExample.createBoardOperations(
          transactionID: createTransactionID,
          createdAt: timestamp
        )
      ),
      createdAt: timestamp,
      source: "test.merge-tile-game.create"
    )
    var boards = try MergeTileGameRecipeExample.decodeBoards(
      (try await runtime.queryOnce(MergeTileGameRecipeExample.boardQuery)).values
    )
    expectNoDifference(boards.map(\.id), [MergeTileGameRecipeExample.boardID])
    expectNoDifference(boards.first?.filledCount, 0)

    let firstTap = MergeTileGameRecipeExample.tapOperations(
      row: 0,
      column: 0,
      color: "#e76f51",
      transactionID: "tx-tap-0-0",
      updatedAt: timestamp
    )
    guard case let .merge(firstMerge) = firstTap[2] else {
      Issue.record("Expected tile taps to deep-merge a single state cell.")
      return
    }
    expectNoDifference(firstMerge.attributeID, "boards/state")
    expectNoDifference(firstMerge.value, .json(.object(["0-0": .string("#e76f51")])))
    try await runtime.transact(
      InstantStoreTransaction(id: "tx-tap-0-0", operations: firstTap),
      createdAt: timestamp,
      source: "test.merge-tile-game.tap"
    )
    try await runtime.transact(
      InstantStoreTransaction(
        id: "tx-tap-3-3",
        operations: MergeTileGameRecipeExample.tapOperations(
          row: 3,
          column: 3,
          color: "#2a9d8f",
          transactionID: "tx-tap-3-3",
          updatedAt: timestamp
        )
      ),
      createdAt: timestamp,
      source: "test.merge-tile-game.tap"
    )
    boards = try MergeTileGameRecipeExample.decodeBoards(
      (try await runtime.queryOnce(MergeTileGameRecipeExample.boardQuery)).values
    )
    let tappedBoard = try #require(boards.first)
    expectNoDifference(tappedBoard.state["0-0"], "#e76f51")
    expectNoDifference(tappedBoard.state["3-3"], "#2a9d8f")
    expectNoDifference(tappedBoard.state["0-1"], MergeTileGameRecipeExample.emptyColor)
    expectNoDifference(tappedBoard.filledCount, 2)

    let resetOperations = MergeTileGameRecipeExample.resetBoardOperations(
      transactionID: "tx-reset-board",
      updatedAt: timestamp
    )
    guard case let .insert(resetState) = resetOperations[1] else {
      Issue.record("Expected reset to replace the full board state.")
      return
    }
    guard case let .json(.object(resetJSON)) = resetState.value else {
      Issue.record("Expected reset state to be a JSON object.")
      return
    }
    expectNoDifference(resetJSON.count, 16)
    try await runtime.transact(
      InstantStoreTransaction(id: "tx-reset-board", operations: resetOperations),
      createdAt: timestamp,
      source: "test.merge-tile-game.reset"
    )
    boards = try MergeTileGameRecipeExample.decodeBoards(
      (try await runtime.queryOnce(MergeTileGameRecipeExample.boardQuery)).values
    )
    let resetBoard = try #require(boards.first)
    expectNoDifference(resetBoard.filledCount, 0)
    expectNoDifference(resetBoard.state["0-0"], MergeTileGameRecipeExample.emptyColor)
    expectNoDifference(resetBoard.state["3-3"], MergeTileGameRecipeExample.emptyColor)

    _ = try await runtime.setPresence(
      room: MergeTileGameRecipeExample.room,
      userID: "user-a",
      values: MergeTileGameRecipeExample.presenceValues(color: "#e76f51")
    )
    _ = try await runtime.setPresence(
      room: MergeTileGameRecipeExample.room,
      userID: "user-b",
      values: MergeTileGameRecipeExample.presenceValues(color: "#2a9d8f")
    )
    _ = try await runtime.setPresence(
      room: InstantRoomHandle(type: "tile-game-example", id: "other"),
      userID: "user-c",
      values: MergeTileGameRecipeExample.presenceValues(color: "#e9c46a")
    )
    let snapshot = MergeTileGameRecipeExample.snapshot(
      board: resetBoard,
      presence: try await runtime.roomPresence(room: MergeTileGameRecipeExample.room),
      viewerUserID: "user-a"
    )
    expectNoDifference(snapshot.currentPlayer?.userID, "user-a")
    expectNoDifference(snapshot.peers.map(\.userID), ["user-b"])
    expectNoDifference(snapshot.availableColors, ["#e9c46a", "#264653", "#f4a261", "#d4a0d0"])
    expectNoDifference(
      MergeTileGameRecipeExample.selectedColor(requestedColor: nil, players: snapshot.players),
      "#e9c46a"
    )
  }

  @Test
  func storedFilesPersistByAppIDAcrossLaunchesAndDeleteContent() async throws {
    let cacheURL = try temporaryCacheURL()
    let sourceURL = cacheURL.deletingLastPathComponent().appendingPathComponent("source.txt")
    let contents = Data("hello instant files\n".utf8)
    try contents.write(to: sourceURL)
    let timestamp = InstantTimestamp(milliseconds: 1_700_000_000_000)
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "app-a",
        persistenceURL: cacheURL,
        now: { timestamp },
        makeID: { "file-1" }
      )
    )
    _ = try await runtime.signInWithRefreshToken("refresh-token", userID: "user-1")

    let uploaded = try await runtime.uploadFile(
      from: sourceURL,
      name: " demo.txt ",
      contentType: " text/plain "
    )
    expectNoDifference(
      uploaded,
      InstantStoredFile(
        id: "file-1",
        appID: "app-a",
        name: "demo.txt",
        contentType: "text/plain",
        byteCount: Int64(contents.count),
        localPath: uploaded.localPath,
        ownerUserID: "user-1",
        createdAt: timestamp,
        updatedAt: timestamp
      )
    )
    expectNoDifference(FileManager.default.fileExists(atPath: uploaded.localPath), true)

    let relaunchedRuntime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(appID: "app-a", persistenceURL: cacheURL)
    )
    let relaunchedFiles = try await relaunchedRuntime.storedFiles()
    expectNoDifference(relaunchedFiles, [uploaded])
    let relaunchedContents = try await relaunchedRuntime.storedFileContents(id: uploaded.id)
    expectNoDifference(relaunchedContents.file, uploaded)
    expectNoDifference(relaunchedContents.byteCount, Int64(contents.count))
    expectNoDifference(relaunchedContents.data, contents)
    try await relaunchedRuntime.signOut()
    do {
      _ = try await relaunchedRuntime.storedFiles()
      #expect(Bool(false), "Expected signed-out file list to fail.")
    } catch let error as InstantError {
      expectNoDifference(error.code, .authFailed)
      expectNoDifference(error.operation, "list files")
    } catch {
      #expect(Bool(false), "Unexpected error: \(error)")
    }
    do {
      _ = try await relaunchedRuntime.storedFileContents(id: uploaded.id)
      #expect(Bool(false), "Expected signed-out file read to fail.")
    } catch let error as InstantError {
      expectNoDifference(error.code, .authFailed)
      expectNoDifference(error.operation, "read file")
    } catch {
      #expect(Bool(false), "Unexpected error: \(error)")
    }
    do {
      _ = try await relaunchedRuntime.deleteStoredFile(id: uploaded.id)
      #expect(Bool(false), "Expected signed-out file delete to fail.")
    } catch let error as InstantError {
      expectNoDifference(error.code, .authFailed)
      expectNoDifference(error.operation, "delete file")
    } catch {
      #expect(Bool(false), "Unexpected error: \(error)")
    }
    _ = try await relaunchedRuntime.signInWithRefreshToken("refresh-token", userID: "user-1")

    let otherAppRuntime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(appID: "app-b", persistenceURL: cacheURL)
    )
    _ = try await otherAppRuntime.signInWithRefreshToken("other-refresh", userID: "user-2")
    let otherAppFiles = try await otherAppRuntime.storedFiles()
    expectNoDifference(otherAppFiles, [])
    do {
      _ = try await otherAppRuntime.storedFileContents(id: uploaded.id)
      #expect(Bool(false), "Expected other app file read to fail.")
    } catch let error as InstantError {
      expectNoDifference(error.code, .validationFailed)
      expectNoDifference(error.operation, "read file")
    } catch {
      #expect(Bool(false), "Unexpected error: \(error)")
    }

    let deleted = try await relaunchedRuntime.deleteStoredFile(id: " file-1 ")
    let remainingFiles = try await relaunchedRuntime.storedFiles()
    expectNoDifference(deleted, uploaded)
    expectNoDifference(remainingFiles, [])
    expectNoDifference(FileManager.default.fileExists(atPath: uploaded.localPath), false)
  }

  @Test
  func storedFileContentsFailsWhenCopiedContentIsMissing() async throws {
    let cacheURL = try temporaryCacheURL()
    let sourceURL = cacheURL.deletingLastPathComponent().appendingPathComponent("missing-source.txt")
    try Data("vanishing local content\n".utf8).write(to: sourceURL)
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "app-a",
        persistenceURL: cacheURL,
        makeID: { "missing-file" }
      )
    )
    _ = try await runtime.signInWithRefreshToken("refresh-token", userID: "user-1")

    let uploaded = try await runtime.uploadFile(from: sourceURL)
    try FileManager.default.removeItem(atPath: uploaded.localPath)

    do {
      _ = try await runtime.storedFileContents(id: uploaded.id)
      #expect(Bool(false), "Expected missing local file content to fail.")
    } catch let error as InstantError {
      expectNoDifference(error.code, .persistenceFailed)
      expectNoDifference(error.operation, "read file")
      #expect(error.message.contains("Could not read stored file"))
    } catch {
      #expect(Bool(false), "Unexpected error: \(error)")
    }
  }

  @Test
  func fileUploadProgressEmitsLoadingAndSuccessAndPersistsFile() async throws {
    let cacheURL = try temporaryCacheURL()
    let sourceURL = cacheURL.deletingLastPathComponent().appendingPathComponent("progress.txt")
    let contents = Data("progress bytes\n".utf8)
    try contents.write(to: sourceURL)
    let timestamp = InstantTimestamp(milliseconds: 1_700_000_000_000)
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "app-a",
        persistenceURL: cacheURL,
        now: { timestamp },
        makeID: { "file-progress-1" }
      )
    )
    _ = try await runtime.signInWithRefreshToken("refresh-token", userID: "user-1")

    let stream = try await runtime.uploadFileProgress(
      from: sourceURL,
      name: " progress.txt ",
      contentType: " text/plain "
    )
    var events: [InstantFileUploadProgress] = []
    for try await event in stream {
      events.append(event)
    }

    expectNoDifference(events.map(\.state), [.loading, .success])
    expectNoDifference(events.map(\.completedByteCount), [0, Int64(contents.count)])
    expectNoDifference(events.map(\.totalByteCount), [Int64(contents.count), Int64(contents.count)])
    expectNoDifference(events.map(\.progress), [0, 1])
    let success = try #require(events.last)
    let uploaded = try #require(success.file)
    expectNoDifference(uploaded.id, "file-progress-1")
    expectNoDifference(uploaded.name, "progress.txt")
    expectNoDifference(uploaded.contentType, "text/plain")
    expectNoDifference(uploaded.ownerUserID, "user-1")
    expectNoDifference(FileManager.default.fileExists(atPath: uploaded.localPath), true)
    let files = try await runtime.storedFiles()
    expectNoDifference(files, [uploaded])
  }

  @Test
  func fileUploadProgressCancellationBeforeSaveDoesNotPersistFile() async throws {
    let cacheURL = try temporaryCacheURL()
    let sourceURL = cacheURL.deletingLastPathComponent().appendingPathComponent("cancel.txt")
    try Data("cancel before save\n".utf8).write(to: sourceURL)
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "app-a",
        persistenceURL: cacheURL,
        makeID: { "file-cancelled-1" }
      )
    )
    _ = try await runtime.signInWithRefreshToken("refresh-token", userID: "user-1")

    let firstEvent = try await Task {
      let stream = try await runtime.uploadFileProgress(from: sourceURL)
      var iterator = stream.makeAsyncIterator()
      return try #require(try await iterator.next())
    }.value
    expectNoDifference(firstEvent.state, .loading)

    try await Task.sleep(nanoseconds: 50_000_000)
    let files = try await runtime.storedFiles()
    expectNoDifference(files, [])
  }

  @Test
  func fileUploadRequiresAuth() async throws {
    let cacheURL = try temporaryCacheURL()
    let sourceURL = cacheURL.deletingLastPathComponent().appendingPathComponent("source.txt")
    try Data("hello".utf8).write(to: sourceURL)
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(appID: "test-app", persistenceURL: cacheURL)
    )

    do {
      _ = try await runtime.uploadFile(from: sourceURL)
      #expect(Bool(false), "Expected anonymous file upload to fail.")
    } catch let error as InstantError {
      expectNoDifference(error.code, .authFailed)
      expectNoDifference(error.operation, "upload file")
    } catch {
      #expect(Bool(false), "Unexpected error: \(error)")
    }

    do {
      _ = try await runtime.uploadFileProgress(from: sourceURL)
      #expect(Bool(false), "Expected anonymous file upload progress to fail.")
    } catch let error as InstantError {
      expectNoDifference(error.code, .authFailed)
      expectNoDifference(error.operation, "upload file")
    } catch {
      #expect(Bool(false), "Unexpected error: \(error)")
    }
  }

  @Test
  func streamChunksPersistOrderedByAppIDAcrossLaunches() async throws {
    let cacheURL = try temporaryCacheURL()
    let timestamp = InstantTimestamp(milliseconds: 1_700_000_000_000)
    let idSequence = LockIsolated(0)
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "app-a",
        persistenceURL: cacheURL,
        now: { timestamp },
        makeID: {
          let nextID = idSequence.withValue { value in
            value += 1
            return value
          }
          return "chunk-\(nextID)"
        }
      )
    )
    _ = try await runtime.signInWithRefreshToken("refresh-token", userID: "user-1")

    let first = try await runtime.appendStreamChunk(
      streamID: " chat/lobby ",
      payload: .object(["text": .string("hello")])
    )
    let second = try await runtime.appendStreamChunk(
      streamID: "chat/lobby",
      payload: .object(["text": .string("again")])
    )
    let otherStream = try await runtime.appendStreamChunk(
      streamID: "chat/side",
      payload: .object(["text": .string("side")])
    )
    expectNoDifference(first.index, 0)
    expectNoDifference(second.index, 1)
    expectNoDifference(otherStream.index, 0)

    let relaunchedRuntime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(appID: "app-a", persistenceURL: cacheURL)
    )
    _ = try await relaunchedRuntime.signInWithRefreshToken("refresh-token", userID: "user-1")
    let relaunchedChunks = try await relaunchedRuntime.streamChunks(streamID: "chat/lobby")
    expectNoDifference(relaunchedChunks, [first, second])
    let limitedChunks = try await relaunchedRuntime.streamChunks(streamID: "chat/lobby", limit: 1)
    expectNoDifference(limitedChunks, [first])
    let resumedChunks = try await relaunchedRuntime.streamChunks(
      streamID: "chat/lobby",
      afterIndex: first.index
    )
    expectNoDifference(resumedChunks, [second])
    let limitedResumedChunks = try await relaunchedRuntime.streamChunks(
      streamID: "chat/lobby",
      limit: 1,
      afterIndex: first.index
    )
    expectNoDifference(limitedResumedChunks, [second])
    let otherStreamChunks = try await relaunchedRuntime.streamChunks(streamID: "chat/side")
    expectNoDifference(otherStreamChunks, [otherStream])

    do {
      _ = try await relaunchedRuntime.streamChunks(streamID: "chat/lobby", afterIndex: -1)
      Issue.record("Expected negative stream afterIndex read to fail.")
    } catch let error as InstantError {
      expectNoDifference(error.code, .validationFailed)
      expectNoDifference(error.operation, "read stream chunks")
    } catch {
      Issue.record("Unexpected error: \(error).")
    }

    do {
      _ = try await relaunchedRuntime.observeStreamChunks(streamID: "chat/lobby", afterIndex: -1)
      Issue.record("Expected negative stream afterIndex observation to fail.")
    } catch let error as InstantError {
      expectNoDifference(error.code, .validationFailed)
      expectNoDifference(error.operation, "observe stream chunks")
    } catch {
      Issue.record("Unexpected error: \(error).")
    }

    try await relaunchedRuntime.signOut()
    do {
      _ = try await relaunchedRuntime.streamChunks(streamID: "chat/lobby")
      #expect(Bool(false), "Expected signed-out stream read to fail.")
    } catch let error as InstantError {
      expectNoDifference(error.code, .authFailed)
      expectNoDifference(error.operation, "read stream chunks")
    } catch {
      #expect(Bool(false), "Unexpected error: \(error)")
    }

    let otherAppRuntime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(appID: "app-b", persistenceURL: cacheURL)
    )
    _ = try await otherAppRuntime.signInWithRefreshToken("other-refresh", userID: "user-2")
    let otherChunks = try await otherAppRuntime.streamChunks(streamID: "chat/lobby")
    expectNoDifference(otherChunks, [])
  }

  @Test
  func byteStreamsPersistMetadataContentAndOffsetsAcrossLaunches() async throws {
    let cacheURL = try temporaryCacheURL()
    let timestamp = InstantTimestamp(milliseconds: 1_700_000_000_000)
    let idSequence = LockIsolated(0)
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "app-a",
        persistenceURL: cacheURL,
        now: { timestamp },
        makeID: {
          let nextID = idSequence.withValue { value in
            value += 1
            return value
          }
          return "stream-id-\(nextID)"
        }
      )
    )
    _ = try await runtime.signInWithRefreshToken("refresh-token", userID: "user-1")

    let metadata = try await runtime.createStream(clientID: " client-1 ")
    expectNoDifference(metadata.id, "stream-id-1")
    expectNoDifference(metadata.clientID, "client-1")
    expectNoDifference(metadata.done, false)
    expectNoDifference(metadata.size, nil)

    do {
      _ = try await runtime.createStream(clientID: "client-1")
      Issue.record("Expected duplicate stream client id to fail.")
    } catch let error as InstantError {
      expectNoDifference(error.code, .validationFailed)
      expectNoDifference(error.operation, "create stream")
    } catch {
      Issue.record("Unexpected error: \(error).")
    }

    let first = try await runtime.appendStreamContent(
      streamID: metadata.id,
      content: "Hi ",
      expectedOffset: 0
    )
    expectNoDifference(first.offset, 0)
    expectNoDifference(first.chunk.byteCount, 3)
    expectNoDifference(first.metadata.size, nil)

    do {
      _ = try await runtime.appendStreamContent(
        streamID: metadata.id,
        content: "wrong",
        expectedOffset: 99
      )
      Issue.record("Expected stream offset mismatch to fail.")
    } catch let error as InstantError {
      expectNoDifference(error.code, .validationFailed)
      expectNoDifference(error.operation, "append stream content")
    } catch {
      Issue.record("Unexpected error: \(error).")
    }

    let second = try await runtime.appendStreamContent(
      streamID: metadata.id,
      content: "🍕",
      expectedOffset: first.offset + first.chunk.byteCount
    )
    expectNoDifference(second.offset, 3)
    expectNoDifference(second.chunk.byteCount, 4)

    let fullRead = try await runtime.streamContent(streamID: metadata.id)
    expectNoDifference(fullRead.content, "Hi 🍕")
    expectNoDifference(fullRead.byteOffset, 0)
    expectNoDifference(fullRead.byteCount, 7)
    expectNoDifference(fullRead.done, false)
    expectNoDifference(fullRead.metadata.size, nil)

    let resumedRead = try await runtime.streamContent(streamID: metadata.id, byteOffset: 3)
    expectNoDifference(resumedRead.content, "🍕")
    expectNoDifference(resumedRead.byteCount, 4)

    let clientRead = try await runtime.streamContent(clientID: "client-1")
    expectNoDifference(clientRead, fullRead)

    do {
      _ = try await runtime.streamContent(streamID: metadata.id, byteOffset: 4)
      Issue.record("Expected middle-of-character byte offset to fail.")
    } catch let error as InstantError {
      expectNoDifference(error.code, .validationFailed)
      expectNoDifference(error.operation, "read stream content")
    } catch {
      Issue.record("Unexpected error: \(error).")
    }

    let closed = try await runtime.closeStream(streamID: metadata.id, abortReason: " done ")
    expectNoDifference(closed.done, true)
    expectNoDifference(closed.size, 7)
    expectNoDifference(closed.abortReason, "done")

    let closedRead = try await runtime.streamContent(streamID: metadata.id)
    expectNoDifference(closedRead.done, true)
    expectNoDifference(closedRead.abortReason, "done")
    expectNoDifference(closedRead.metadata.size, 7)

    do {
      _ = try await runtime.appendStreamContent(streamID: metadata.id, content: "blocked")
      Issue.record("Expected append after stream close to fail.")
    } catch let error as InstantError {
      expectNoDifference(error.code, .validationFailed)
      expectNoDifference(error.operation, "append stream content")
    } catch {
      Issue.record("Unexpected error: \(error).")
    }

    let relaunchedRuntime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(appID: "app-a", persistenceURL: cacheURL)
    )
    _ = try await relaunchedRuntime.signInWithRefreshToken("refresh-token", userID: "user-1")
    let relaunchedMetadata = try await relaunchedRuntime.streamMetadata(clientID: "client-1")
    let relaunchedRead = try await relaunchedRuntime.streamContent(clientID: "client-1")
    expectNoDifference(relaunchedMetadata, closed)
    expectNoDifference(relaunchedRead, closedRead)

    do {
      _ = try await relaunchedRuntime.streamContent(streamID: metadata.id, byteOffset: -1)
      Issue.record("Expected negative stream byte offset to fail.")
    } catch let error as InstantError {
      expectNoDifference(error.code, .validationFailed)
      expectNoDifference(error.operation, "read stream content")
    } catch {
      Issue.record("Unexpected error: \(error).")
    }
  }

  @Test
  func byteStreamCreationRejectsGeneratedStreamIDCollisions() async throws {
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "stream-id-collisions",
        persistenceURL: temporaryCacheURL(),
        makeID: { "stream-id-1" }
      )
    )
    _ = try await runtime.signInWithRefreshToken("refresh-token", userID: "user-1")

    let first = try await runtime.createStream(clientID: "client-1")
    expectNoDifference(first.id, "stream-id-1")

    do {
      _ = try await runtime.createStream(clientID: "client-2")
      Issue.record("Expected generated stream id collision to fail.")
    } catch let error as InstantError {
      expectNoDifference(error.code, .validationFailed)
      expectNoDifference(error.operation, "create stream")
      expectNoDifference(error.localID, "stream-id-1")
    } catch {
      Issue.record("Unexpected error: \(error).")
    }

    let preserved = try await runtime.streamMetadata(streamID: "stream-id-1")
    expectNoDifference(preserved, first)
  }

  @Test
  func byteStreamContentObservationsBufferEveryUpdate() async throws {
    let cacheURL = try temporaryCacheURL()
    let idSequence = LockIsolated(0)
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "byte-stream-observations",
        persistenceURL: cacheURL,
        makeID: {
          let nextID = idSequence.withValue { value in
            value += 1
            return value
          }
          return "stream-id-\(nextID)"
        }
      )
    )
    _ = try await runtime.signInWithRefreshToken("refresh-token", userID: "user-1")
    let metadata = try await runtime.createStream(clientID: "client-1")

    var iterator = (try await runtime.observeStreamContent(streamID: metadata.id))
      .makeAsyncIterator()
    let initialRead = try #require(await iterator.next())
    expectNoDifference(initialRead.content, "")
    expectNoDifference(initialRead.done, false)

    _ = try await runtime.appendStreamContent(streamID: metadata.id, content: "A")
    _ = try await runtime.appendStreamContent(streamID: metadata.id, content: "B")
    _ = try await runtime.closeStream(streamID: metadata.id)

    let firstUpdate = try #require(await iterator.next())
    let secondUpdate = try #require(await iterator.next())
    let closeUpdate = try #require(await iterator.next())
    expectNoDifference(firstUpdate.content, "A")
    expectNoDifference(firstUpdate.done, false)
    expectNoDifference(secondUpdate.content, "AB")
    expectNoDifference(secondUpdate.done, false)
    expectNoDifference(closeUpdate.content, "AB")
    expectNoDifference(closeUpdate.done, true)
    expectNoDifference(closeUpdate.metadata.size, 2)
  }

  @Test
  func localSnapshotObservationsEmitPersistedUpdates() async throws {
    let cacheURL = try temporaryCacheURL()
    let sourceURL = cacheURL.deletingLastPathComponent().appendingPathComponent("observed-source.txt")
    try Data("observed file\n".utf8).write(to: sourceURL)
    let timestamp = InstantTimestamp(milliseconds: 1_700_000_000_000)
    let idSequence = LockIsolated(0)
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "observed-local-snapshots",
        persistenceURL: cacheURL,
        now: { timestamp },
        makeID: {
          let nextID = idSequence.withValue { value in
            value += 1
            return value
          }
          return "observed-\(nextID)"
        }
      )
    )
    _ = try await runtime.signInWithRefreshToken("refresh-token", userID: "user-1")

    let room = InstantRoomHandle(type: "chat", id: "lobby")
    var presenceIterator = (try await runtime.observeRoomPresence(room: room)).makeAsyncIterator()
    let initialPresence = await presenceIterator.next()
    expectNoDifference(try #require(initialPresence), [])
    _ = try await runtime.setPresence(
      room: room,
      values: ["status": .string("online")]
    )
    let updatedPresence = await presenceIterator.next()
    expectNoDifference(
      try #require(updatedPresence).map(\.userID),
      ["user-1"]
    )

    var topicIterator = (try await runtime.observeRoomTopicMessages(
      room: room,
      topic: "sendEmoji"
    ))
    .makeAsyncIterator()
    let initialTopics = await topicIterator.next()
    expectNoDifference(try #require(initialTopics), [])
    _ = try await runtime.publishTopicMessage(
      room: room,
      topic: "sendEmoji",
      payload: .object(["emoji": .string("wave")])
    )
    let updatedTopics = await topicIterator.next()
    expectNoDifference(
      try #require(updatedTopics).map(\.payload),
      [.object(["emoji": .string("wave")])]
    )

    var filesIterator = (try await runtime.observeStoredFiles()).makeAsyncIterator()
    let initialFiles = await filesIterator.next()
    expectNoDifference(try #require(initialFiles), [])
    let uploaded = try await runtime.uploadFile(
      from: sourceURL,
      name: "observed.txt",
      contentType: "text/plain"
    )
    let updatedFiles = await filesIterator.next()
    expectNoDifference(
      try #require(updatedFiles).map(\.id),
      [uploaded.id]
    )

    var streamIterator = (try await runtime.observeStreamChunks(streamID: "chat/lobby"))
      .makeAsyncIterator()
    let initialChunks = await streamIterator.next()
    expectNoDifference(try #require(initialChunks), [])
    let chunk = try await runtime.appendStreamChunk(
      streamID: "chat/lobby",
      payload: .object(["text": .string("hello")])
    )
    let updatedChunks = await streamIterator.next()
    expectNoDifference(
      try #require(updatedChunks).map(\.id),
      [chunk.id]
    )

    var resumedStreamIterator = (try await runtime.observeStreamChunks(
      streamID: "chat/lobby",
      afterIndex: chunk.index
    ))
    .makeAsyncIterator()
    let initialResumedChunks = await resumedStreamIterator.next()
    expectNoDifference(try #require(initialResumedChunks), [])
    let laterChunk = try await runtime.appendStreamChunk(
      streamID: "chat/lobby",
      payload: .object(["text": .string("again")])
    )
    let resumedUpdatedChunks = await resumedStreamIterator.next()
    expectNoDifference(
      try #require(resumedUpdatedChunks).map(\.id),
      [laterChunk.id]
    )
  }

  @Test
  func streamAppendRequiresAuth() async throws {
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(appID: "test-app", persistenceURL: temporaryCacheURL())
    )

    do {
      _ = try await runtime.appendStreamChunk(
        streamID: "chat/lobby",
        payload: .object(["text": .string("hello")])
      )
      #expect(Bool(false), "Expected anonymous stream append to fail.")
    } catch let error as InstantError {
      expectNoDifference(error.code, .authFailed)
      expectNoDifference(error.operation, "append stream chunk")
    } catch {
      #expect(Bool(false), "Unexpected error: \(error)")
    }
  }

  @Test
  func sharesPersistMembershipsAndRevocationAcrossUsersAndApps() async throws {
    let cacheURL = try temporaryCacheURL()
    let timestamp = InstantTimestamp(milliseconds: 1_700_000_000_000)
    let idSequence = LockIsolated(0)
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "app-a",
        persistenceURL: cacheURL,
        now: { timestamp },
        makeID: {
          let nextID = idSequence.withValue { value in
            value += 1
            return value
          }
          return "id-\(nextID)"
        }
      )
    )
    _ = try await runtime.signInWithRefreshToken("owner-refresh", userID: "user-1")

    let created = try await runtime.createShare(
      rootNamespace: " remindersLists ",
      rootID: " list-1 "
    )
    expectNoDifference(created.share.id, "id-1")
    expectNoDifference(created.share.appID, "app-a")
    expectNoDifference(created.share.rootNamespace, "remindersLists")
    expectNoDifference(created.share.rootID, "list-1")
    expectNoDifference(created.share.ownerUserID, "user-1")
    expectNoDifference(created.share.token, "local-share-id-2")
    expectNoDifference(created.share.createdAt, timestamp)
    expectNoDifference(created.share.updatedAt, timestamp)
    expectNoDifference(created.share.revokedAt, nil)
    expectNoDifference(created.memberships.map(\.userID), ["user-1"])
    expectNoDifference(created.memberships.map(\.role), [.owner])
    expectNoDifference(created.memberships.map(\.acceptedAt), [timestamp])

    let inviteeRuntime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(appID: "app-a", persistenceURL: cacheURL)
    )
    _ = try await inviteeRuntime.signInWithRefreshToken("invitee-refresh", userID: "user-2")
    let accepted = try await inviteeRuntime.acceptShare(token: created.share.token)
    expectNoDifference(accepted.share.id, created.share.id)
    expectNoDifference(accepted.share.token, created.share.token)
    expectNoDifference(accepted.memberships.map(\.userID), ["user-1", "user-2"])
    expectNoDifference(accepted.memberships.map(\.role), [.owner, .reader])
    do {
      _ = try await inviteeRuntime.updateShareMembershipRole(
        shareID: created.share.id,
        userID: "user-2",
        role: .writer
      )
      #expect(Bool(false), "Expected non-owner role update to fail.")
    } catch let error as InstantError {
      expectNoDifference(error.code, .permissionRejected)
      expectNoDifference(error.operation, "update share role")
    } catch {
      #expect(Bool(false), "Unexpected error: \(error)")
    }

    let inviteeShares = try await inviteeRuntime.shares()
    expectNoDifference(inviteeShares.map(\.share.id), [accepted.share.id])
    expectNoDifference(inviteeShares.first?.memberships.map(\.userID), ["user-1", "user-2"])
    do {
      _ = try await inviteeRuntime.revokeShare(id: created.share.id)
      #expect(Bool(false), "Expected non-owner share revoke to fail.")
    } catch let error as InstantError {
      expectNoDifference(error.code, .permissionRejected)
      expectNoDifference(error.operation, "revoke share")
    } catch {
      #expect(Bool(false), "Unexpected error: \(error)")
    }

    _ = try await runtime.signInWithRefreshToken("owner-refresh", userID: "user-1")
    let ownerShares = try await runtime.shares()
    expectNoDifference(ownerShares.map(\.share.id), [accepted.share.id])
    expectNoDifference(ownerShares.first?.memberships.map(\.userID), ["user-1", "user-2"])
    do {
      _ = try await runtime.createShare(rootNamespace: "remindersLists", rootID: "list-1")
      #expect(Bool(false), "Expected duplicate owner share creation to fail.")
    } catch let error as InstantError {
      expectNoDifference(error.code, .validationFailed)
      expectNoDifference(error.operation, "create share")
      #expect(error.message.contains("already has active share"))
    } catch {
      #expect(Bool(false), "Unexpected error: \(error)")
    }
    do {
      _ = try await runtime.updateShareMembershipRole(
        shareID: created.share.id,
        userID: "user-1",
        role: .reader
      )
      #expect(Bool(false), "Expected owner role mutation to fail.")
    } catch let error as InstantError {
      expectNoDifference(error.code, .validationFailed)
      expectNoDifference(error.operation, "update share role")
      #expect(error.message.contains("owner's membership role cannot be changed"))
    } catch {
      #expect(Bool(false), "Unexpected error: \(error)")
    }
    do {
      _ = try await runtime.updateShareMembershipRole(
        shareID: created.share.id,
        userID: "missing-user",
        role: .writer
      )
      #expect(Bool(false), "Expected missing member role mutation to fail.")
    } catch let error as InstantError {
      expectNoDifference(error.code, .validationFailed)
      expectNoDifference(error.operation, "update share role")
      #expect(error.message.contains("not an active member"))
    } catch {
      #expect(Bool(false), "Unexpected error: \(error)")
    }
    let promoted = try await runtime.updateShareMembershipRole(
      shareID: created.share.id,
      userID: "user-2",
      role: .writer
    )
    expectNoDifference(promoted.memberships.map(\.role), [.owner, .writer])
    let promotedAgain = try await runtime.updateShareMembershipRole(
      shareID: created.share.id,
      userID: "user-2",
      role: .writer
    )
    expectNoDifference(promotedAgain, promoted)
    let demoted = try await runtime.updateShareMembershipRole(
      shareID: created.share.id,
      userID: "user-2",
      role: .reader
    )
    expectNoDifference(demoted.memberships.map(\.role), [.owner, .reader])
    let revoked = try await runtime.revokeShare(id: created.share.id)
    expectNoDifference(revoked.share.revokedAt, timestamp)
    expectNoDifference(revoked.memberships.map(\.revokedAt), [timestamp, timestamp])
    do {
      _ = try await runtime.updateShareMembershipRole(
        shareID: created.share.id,
        userID: "user-2",
        role: .writer
      )
      #expect(Bool(false), "Expected revoked share role mutation to fail.")
    } catch let error as InstantError {
      expectNoDifference(error.code, .validationFailed)
      expectNoDifference(error.operation, "update share role")
      #expect(error.message.contains("was not found or has been revoked"))
    } catch {
      #expect(Bool(false), "Unexpected error: \(error)")
    }
    let revokedAgain = try await runtime.revokeShare(id: created.share.id)
    expectNoDifference(revokedAgain.share.revokedAt, timestamp)
    expectNoDifference(revokedAgain.memberships.map(\.revokedAt), [timestamp, timestamp])
    let ownerSharesAfterRevoke = try await runtime.shares()
    expectNoDifference(ownerSharesAfterRevoke, [])

    do {
      _ = try await inviteeRuntime.acceptShare(token: created.share.token)
      #expect(Bool(false), "Expected revoked share accept to fail.")
    } catch let error as InstantError {
      expectNoDifference(error.code, .validationFailed)
      expectNoDifference(error.operation, "accept share")
    } catch {
      #expect(Bool(false), "Unexpected error: \(error)")
    }
    let inviteeSharesAfterRevoke = try await inviteeRuntime.shares()
    expectNoDifference(inviteeSharesAfterRevoke, [])

    let otherAppRuntime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(appID: "app-b", persistenceURL: cacheURL)
    )
    _ = try await otherAppRuntime.signInWithRefreshToken("other-refresh", userID: "user-2")
    do {
      _ = try await otherAppRuntime.acceptShare(token: created.share.token)
      #expect(Bool(false), "Expected cross-app share accept to fail.")
    } catch let error as InstantError {
      expectNoDifference(error.code, .validationFailed)
      expectNoDifference(error.operation, "accept share")
    } catch {
      #expect(Bool(false), "Unexpected error: \(error)")
    }
  }

  @Test
  func observeSharesEmitsUserScopedShareSnapshots() async throws {
    let cacheURL = try temporaryCacheURL()
    let timestamp = InstantTimestamp(milliseconds: 1_700_000_000_000)
    let idSequence = LockIsolated(0)
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "app-a",
        persistenceURL: cacheURL,
        now: { timestamp },
        makeID: {
          let nextID = idSequence.withValue { value in
            value += 1
            return value
          }
          return "id-\(nextID)"
        }
      )
    )
    _ = try await runtime.signInWithRefreshToken("owner-refresh", userID: "user-1")

    var iterator = (try await runtime.observeShares()).makeAsyncIterator()
    let initialShares = await iterator.next()
    expectNoDifference(initialShares, [])

    let created = try await runtime.createShare(
      rootNamespace: "remindersLists",
      rootID: "list-1"
    )
    let createdEmission = await iterator.next()
    expectNoDifference(createdEmission?.map(\.share.id), [created.share.id])
    expectNoDifference(createdEmission?.first?.memberships.map(\.role), [.owner])

    _ = try await runtime.signInWithRefreshToken("invitee-refresh", userID: "user-2")
    let accepted = try await runtime.acceptShare(token: created.share.token)
    var inviteeIterator = (try await runtime.observeShares()).makeAsyncIterator()
    let inviteeInitialEmission = await inviteeIterator.next()
    expectNoDifference(inviteeInitialEmission, [accepted])
    let acceptedEmission = await iterator.next()
    expectNoDifference(acceptedEmission, [accepted])

    _ = try await runtime.signInWithRefreshToken("owner-refresh", userID: "user-1")
    let promoted = try await runtime.updateShareMembershipRole(
      shareID: created.share.id,
      userID: "user-2",
      role: .writer
    )
    let promotedEmission = await iterator.next()
    expectNoDifference(promotedEmission, [promoted])
    let inviteePromotedEmission = await inviteeIterator.next()
    expectNoDifference(inviteePromotedEmission, [promoted])

    _ = try await runtime.revokeShare(id: created.share.id)
    let revokedEmission = await iterator.next()
    expectNoDifference(revokedEmission, [])
    let inviteeRevokedEmission = await inviteeIterator.next()
    expectNoDifference(inviteeRevokedEmission, [])
  }

  @Test
  func remindersExampleSharesListRootRolesAndPersistsCounts() async throws {
    let cacheURL = try temporaryCacheURL()
    let timestamp = InstantTimestamp(milliseconds: 1_700_000_000_000)
    let listID = "list-shared"
    let firstReminderID = "reminder-owner"
    let writerReminderID = "reminder-writer"
    let ownerRuntime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "app-a",
        persistenceURL: cacheURL,
        initialAttributes: ReminderExample.attributes,
        now: { timestamp }
      )
    )
    _ = try await ownerRuntime.signInWithRefreshToken("owner-refresh", userID: "user-1")
    try await ownerRuntime.transact(
      InstantStoreTransaction(
        id: "tx-owner-reminders-list",
        operations: ReminderExample.createListOperations(
          id: listID,
          title: "Family",
          position: 0,
          createdAt: timestamp,
          transactionID: "tx-owner-reminders-list"
        )
      ),
      createdAt: timestamp
    )
    try await ownerRuntime.transact(
      InstantStoreTransaction(
        id: "tx-owner-reminder",
        operations: ReminderExample.createReminderOperations(
          id: firstReminderID,
          listID: listID,
          title: "Pack lunch",
          position: 0,
          createdAt: timestamp,
          transactionID: "tx-owner-reminder"
        )
      ),
      createdAt: timestamp
    )
    let ownerLists = try ReminderExample.decodeLists(
      (try await ownerRuntime.queryOnce(ReminderExample.listsQuery)).values
    )
    let ownerReminders = try ReminderExample.decodeReminders(
      (try await ownerRuntime.queryOnce(ReminderExample.remindersForListQuery(listID))).values
    )
    expectNoDifference(ownerLists.map(\.title), ["Family"])
    expectNoDifference(ownerReminders.map(\.title), ["Pack lunch"])

    let createdShare = try await ownerRuntime.createShare(
      rootNamespace: ReminderExample.listsNamespace,
      rootID: listID
    )
    let inviteeRuntime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "app-a",
        persistenceURL: cacheURL,
        initialAttributes: ReminderExample.attributes,
        now: { timestamp }
      )
    )
    _ = try await inviteeRuntime.signInWithRefreshToken("invitee-refresh", userID: "user-2")
    let accepted = try await inviteeRuntime.acceptShare(token: createdShare.share.token)
    expectNoDifference(accepted.memberships.map(\.role), [.owner, .reader])

    do {
      try await inviteeRuntime.transact(
        InstantStoreTransaction(
          id: "tx-reader-rename-list",
          operations: ReminderExample.renameListOperations(
            id: listID,
            title: "Reader Family",
            updatedAt: timestamp,
            transactionID: "tx-reader-rename-list"
          )
        ),
        createdAt: timestamp
      )
      #expect(Bool(false), "Expected reader list rename to fail.")
    } catch let error as InstantError {
      expectNoDifference(error.code, .permissionRejected)
      expectNoDifference(error.operation, "write shared root")
      expectNoDifference(error.namespace, ReminderExample.listsNamespace)
      expectNoDifference(error.localID, listID)
      #expect(error.message.contains("reader access"))
    } catch {
      #expect(Bool(false), "Unexpected error: \(error)")
    }

    do {
      try await inviteeRuntime.transact(
        InstantStoreTransaction(
          id: "tx-reader-reminder",
          operations: ReminderExample.createReminderOperations(
            id: "reminder-reader",
            listID: listID,
            title: "Reader reminder",
            position: 1,
            createdAt: timestamp,
            transactionID: "tx-reader-reminder"
          )
        ),
        createdAt: timestamp
      )
      #expect(Bool(false), "Expected reader reminder creation for a shared list to fail.")
    } catch let error as InstantError {
      expectNoDifference(error.code, .permissionRejected)
      expectNoDifference(error.operation, "write shared root")
      expectNoDifference(error.namespace, ReminderExample.listsNamespace)
      expectNoDifference(error.localID, listID)
      #expect(error.message.contains("reader access"))
    } catch {
      #expect(Bool(false), "Unexpected error: \(error)")
    }

    do {
      try await inviteeRuntime.transact(
        InstantStoreTransaction(
          id: "tx-reader-tag",
          operations: ReminderExample.addTagOperations(
            reminderID: firstReminderID,
            listID: listID,
            tagID: "school",
            title: "school",
            updatedAt: timestamp,
            transactionID: "tx-reader-tag"
          )
        ),
        createdAt: timestamp
      )
      #expect(Bool(false), "Expected reader tag creation for a shared list reminder to fail.")
    } catch let error as InstantError {
      expectNoDifference(error.code, .permissionRejected)
      expectNoDifference(error.operation, "write shared root")
      expectNoDifference(error.namespace, ReminderExample.listsNamespace)
      expectNoDifference(error.localID, listID)
      #expect(error.message.contains("reader access"))
    } catch {
      #expect(Bool(false), "Unexpected error: \(error)")
    }

    do {
      try await inviteeRuntime.transact(
        InstantStoreTransaction(
          id: "tx-reader-delete-reminder",
          operations: ReminderExample.deleteReminderOperations(
            id: firstReminderID,
            listID: listID,
            updatedAt: timestamp,
            transactionID: "tx-reader-delete-reminder"
          )
        ),
        createdAt: timestamp
      )
      #expect(Bool(false), "Expected reader reminder delete for a shared list to fail.")
    } catch let error as InstantError {
      expectNoDifference(error.code, .permissionRejected)
      expectNoDifference(error.operation, "write shared root")
      expectNoDifference(error.namespace, ReminderExample.listsNamespace)
      expectNoDifference(error.localID, listID)
      #expect(error.message.contains("reader access"))
    } catch {
      #expect(Bool(false), "Unexpected error: \(error)")
    }

    do {
      try await inviteeRuntime.transact(
        InstantStoreTransaction(
          id: "tx-reader-delete-list",
          operations: ReminderExample.deleteListOperations(id: listID)
        ),
        createdAt: timestamp
      )
      #expect(Bool(false), "Expected reader list delete to fail.")
    } catch let error as InstantError {
      expectNoDifference(error.code, .permissionRejected)
      expectNoDifference(error.operation, "write shared root")
      expectNoDifference(error.namespace, ReminderExample.listsNamespace)
      expectNoDifference(error.localID, listID)
      #expect(error.message.contains("reader access"))
    } catch {
      #expect(Bool(false), "Unexpected error: \(error)")
    }

    try await inviteeRuntime.transact(
      InstantStoreTransaction(
        id: "tx-reader-unshared-list",
        operations: ReminderExample.createListOperations(
          id: "list-unshared",
          title: "Unshared",
          position: 1,
          createdAt: timestamp,
          transactionID: "tx-reader-unshared-list"
        )
      ),
      createdAt: timestamp
    )
    do {
      try await inviteeRuntime.transact(
        InstantStoreTransaction(
          id: "tx-reader-hostile-parent",
          operations: ReminderExample.updateReminderTitleOperations(
            id: firstReminderID,
            listID: "list-unshared",
            title: "Hostile parent",
            updatedAt: timestamp,
            transactionID: "tx-reader-hostile-parent"
          )
        ),
        createdAt: timestamp
      )
      #expect(Bool(false), "Expected mismatched reminder list update to fail.")
    } catch let error as InstantError {
      expectNoDifference(error.code, .validationFailed)
      expectNoDifference(error.operation, "require triple")
      expectNoDifference(error.namespace, ReminderExample.remindersNamespace)
      expectNoDifference(error.path, "list")
      expectNoDifference(error.localID, firstReminderID)
    } catch {
      #expect(Bool(false), "Unexpected error: \(error)")
    }

    _ = try await ownerRuntime.signInWithRefreshToken("owner-refresh", userID: "user-1")
    let promoted = try await ownerRuntime.updateShareMembershipRole(
      shareID: createdShare.share.id,
      userID: "user-2",
      role: .writer
    )
    expectNoDifference(promoted.memberships.map(\.role), [.owner, .writer])
    _ = try await inviteeRuntime.signInWithRefreshToken("invitee-refresh", userID: "user-2")
    try await inviteeRuntime.transact(
      InstantStoreTransaction(
        id: "tx-writer-rename-list",
        operations: ReminderExample.renameListOperations(
          id: listID,
          title: "Writer Family",
          updatedAt: timestamp,
          transactionID: "tx-writer-rename-list"
        )
      ),
      createdAt: timestamp
    )
    try await inviteeRuntime.transact(
      InstantStoreTransaction(
        id: "tx-writer-reminder",
        operations: ReminderExample.createReminderOperations(
          id: writerReminderID,
          listID: listID,
          title: "Writer reminder",
          position: 1,
          createdAt: timestamp,
          transactionID: "tx-writer-reminder"
        )
      ),
      createdAt: timestamp
    )
    try await inviteeRuntime.transact(
      InstantStoreTransaction(
        id: "tx-writer-tag",
        operations: ReminderExample.addTagOperations(
          reminderID: writerReminderID,
          listID: listID,
          tagID: "school",
          title: "school",
          updatedAt: timestamp,
          transactionID: "tx-writer-tag"
        )
      ),
      createdAt: timestamp
    )
    let writerLists = try ReminderExample.decodeLists(
      (try await inviteeRuntime.queryOnce(ReminderExample.listsQuery)).values
    )
    let writerReminders = try ReminderExample.decodeReminders(
      (try await inviteeRuntime.queryOnce(ReminderExample.remindersForListQuery(listID))).values
    )
    let writerTags = try ReminderExample.decodeTags(
      (try await inviteeRuntime.queryOnce(ReminderExample.tagsQuery)).values
    )
    let writerTaggedReminders = try ReminderExample.decodeReminders(
      (try await inviteeRuntime.queryOnce(ReminderExample.remindersSearchQuery(text: "", tagID: "school"))).values
    )
    let writerReminderTagLinks = try ReminderExample.decodeReminderTagLinks(
      (try await inviteeRuntime.queryOnce(ReminderExample.remindersForListQuery(listID))).values
    )
    expectNoDifference(writerLists.filter { $0.id == listID }.map(\.title), ["Writer Family"])
    expectNoDifference(writerReminders.map(\.title), ["Pack lunch", "Writer reminder"])
    expectNoDifference(writerTags.map(\.title), ["school"])
    expectNoDifference(writerTaggedReminders.map(\.id), [writerReminderID])
    expectNoDifference(writerReminderTagLinks, [
      ReminderTagLinkRecord(reminderID: writerReminderID, tagID: "school")
    ])

    _ = try await ownerRuntime.signInWithRefreshToken("owner-refresh", userID: "user-1")
    let demoted = try await ownerRuntime.updateShareMembershipRole(
      shareID: createdShare.share.id,
      userID: "user-2",
      role: .reader
    )
    expectNoDifference(demoted.memberships.map(\.role), [.owner, .reader])
    _ = try await inviteeRuntime.signInWithRefreshToken("invitee-refresh", userID: "user-2")
    do {
      try await inviteeRuntime.transact(
        InstantStoreTransaction(
          id: "tx-demoted-reader-rename-list",
          operations: ReminderExample.renameListOperations(
            id: listID,
            title: "Reader Again",
            updatedAt: timestamp,
            transactionID: "tx-demoted-reader-rename-list"
          )
        ),
        createdAt: timestamp
      )
      #expect(Bool(false), "Expected demoted reader list rename to fail.")
    } catch let error as InstantError {
      expectNoDifference(error.code, .permissionRejected)
      expectNoDifference(error.operation, "write shared root")
      #expect(error.message.contains("reader access"))
    } catch {
      #expect(Bool(false), "Unexpected error: \(error)")
    }
    do {
      try await inviteeRuntime.transact(
        InstantStoreTransaction(
          id: "tx-demoted-reader-remove-tag",
          operations: ReminderExample.removeTagOperations(
            reminderID: writerReminderID,
            listID: listID,
            tagID: "school",
            updatedAt: timestamp,
            transactionID: "tx-demoted-reader-remove-tag"
          )
        ),
        createdAt: timestamp
      )
      #expect(Bool(false), "Expected demoted reader tag removal to fail.")
    } catch let error as InstantError {
      expectNoDifference(error.code, .permissionRejected)
      expectNoDifference(error.operation, "write shared root")
      #expect(error.message.contains("reader access"))
    } catch {
      #expect(Bool(false), "Unexpected error: \(error)")
    }
    let finalReminders = try ReminderExample.decodeReminders(
      (try await inviteeRuntime.queryOnce(ReminderExample.remindersForListQuery(listID))).values
    )
    expectNoDifference(finalReminders.count, 2)
  }

  @Test
  func remindersExampleRichFieldsFilterAndPersist() async throws {
    let cacheURL = try temporaryCacheURL()
    let timestamp = InstantTimestamp(milliseconds: 1_700_000_000_000)
    let today = InstantTimestamp(milliseconds: 1_700_000_100_000)
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "app-a",
        persistenceURL: cacheURL,
        initialAttributes: ReminderExample.attributes,
        now: { timestamp }
      )
    )

    try await runtime.transact(
      InstantStoreTransaction(
        id: "tx-rich-list",
        operations: ReminderExample.createListOperations(
          id: "list-rich",
          title: "Family",
          position: 0,
          createdAt: timestamp,
          transactionID: "tx-rich-list"
        )
      ),
      createdAt: timestamp
    )
    try await runtime.transact(
      InstantStoreTransaction(
        id: "tx-rich-reminders",
        operations: ReminderExample.createReminderOperations(
          id: "reminder-dentist",
          listID: "list-rich",
          title: "Call dentist",
          notes: "Bring insurance card",
          isFlagged: true,
          dueDate: today,
          priority: .high,
          position: 0,
          createdAt: timestamp,
          transactionID: "tx-rich-reminders"
        ) + ReminderExample.createReminderOperations(
          id: "reminder-someday",
          listID: "list-rich",
          title: "Someday",
          position: 1,
          createdAt: timestamp,
          transactionID: "tx-rich-reminders"
        )
      ),
      createdAt: timestamp
    )

    let flagged = try ReminderExample.decodeReminders(
      (try await runtime.queryOnce(ReminderExample.remindersFilterQuery(flagged: true))).values
    )
    let scheduled = try ReminderExample.decodeReminders(
      (try await runtime.queryOnce(ReminderExample.remindersFilterQuery(scheduled: true))).values
    )
    let dueToday = try ReminderExample.decodeReminders(
      (try await runtime.queryOnce(ReminderExample.remindersFilterQuery(today: today))).values
    )
    let highPriority = try ReminderExample.decodeReminders(
      (try await runtime.queryOnce(ReminderExample.remindersFilterQuery(priority: .high))).values
    )
    expectNoDifference(flagged.map(\.id), ["reminder-dentist"])
    expectNoDifference(scheduled.map(\.id), ["reminder-dentist"])
    expectNoDifference(dueToday.map(\.id), ["reminder-dentist"])
    expectNoDifference(highPriority.map(\.id), ["reminder-dentist"])
    expectNoDifference(flagged.first?.notes, "Bring insurance card")
    expectNoDifference(flagged.first?.dueDate, today)
    expectNoDifference(flagged.first?.priority, .high)

    try await runtime.transact(
      InstantStoreTransaction(
        id: "tx-rich-update",
        operations: ReminderExample.updateReminderDetailsOperations(
          id: "reminder-dentist",
          listID: "list-rich",
          title: "Call orthodontist",
          notes: "Updated notes",
          isFlagged: false,
          dueDate: nil,
          priority: .medium,
          updatedAt: timestamp,
          transactionID: "tx-rich-update"
        )
      ),
      createdAt: timestamp
    )

    let noLongerScheduled = try ReminderExample.decodeReminders(
      (try await runtime.queryOnce(ReminderExample.remindersFilterQuery(scheduled: true))).values
    )
    let mediumPriority = try ReminderExample.decodeReminders(
      (try await runtime.queryOnce(ReminderExample.remindersFilterQuery(priority: .medium))).values
    )
    expectNoDifference(noLongerScheduled, [])
    expectNoDifference(mediumPriority.map(\.title), ["Call orthodontist"])
    expectNoDifference(mediumPriority.map(\.isFlagged), [false])
    expectNoDifference(mediumPriority.map(\.dueDate), [nil])
    expectNoDifference(mediumPriority.map(\.priority), [.medium])

    let relaunched = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "app-a",
        persistenceURL: cacheURL,
        initialAttributes: ReminderExample.attributes
      )
    )
    let persisted = try ReminderExample.decodeReminders(
      (try await relaunched.queryOnce(ReminderExample.remindersFilterQuery(priority: .medium))).values
    )
    expectNoDifference(persisted.map(\.notes), ["Updated notes"])
    expectNoDifference(persisted.map(\.dueDate), [nil])
    expectNoDifference(persisted.map(\.priority), [.medium])
  }

  @Test
  func reminderFormModelSavesNewDraftWithTags() async throws {
    let cacheURL = try temporaryCacheURL()
    let timestamp = InstantTimestamp(milliseconds: 1_700_000_000_000)
    let dueDate = InstantTimestamp(milliseconds: 1_700_086_400_000)
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "app-a",
        persistenceURL: cacheURL,
        initialAttributes: ReminderExample.attributes
      )
    )
    try await runtime.transact(
      InstantStoreTransaction(
        id: "tx-reminder-form-list",
        operations: ReminderExample.createListOperations(
          id: "list-form",
          title: "Family",
          position: 0,
          createdAt: timestamp,
          transactionID: "tx-reminder-form-list"
        )
      ),
      createdAt: timestamp
    )

    var draft = ReminderDraft(
      listID: "list-form",
      title: "Get milk",
      notes: "Whole milk",
      isFlagged: true,
      priority: .medium,
      position: 0
    )
    expectNoDifference(draft.isDateSet, false)
    draft.setDateEnabled(true, defaultDueDate: dueDate)
    expectNoDifference(draft.dueDate, dueDate)

    var model = ReminderFormModel(
      reminder: draft,
      selectedTags: [
        ReminderTagRecord(id: "shopping", title: "shopping"),
        ReminderTagRecord(id: "shopping", title: "duplicate"),
        ReminderTagRecord(id: "family", title: "family"),
      ]
    )
    let save = model.saveButtonTapped(
      newReminderID: "reminder-form-new",
      updatedAt: timestamp,
      transactionID: "tx-reminder-form-save"
    )
    try await runtime.transact(
      InstantStoreTransaction(id: "tx-reminder-form-save", operations: save.operations),
      createdAt: timestamp
    )
    model.commit(save)

    expectNoDifference(model.reminder.id, "reminder-form-new")
    expectNoDifference(model.isDismissed, true)
    expectNoDifference(model.selectedTags.map(\.id), ["shopping", "family"])
    expectNoDifference(model.existingTagIDs, ["shopping", "family"])

    let reminders = try ReminderExample.decodeReminders(
      (try await runtime.queryOnce(ReminderExample.remindersQuery)).values
    )
    expectNoDifference(reminders.map(\.id), ["reminder-form-new"])
    expectNoDifference(reminders.map(\.title), ["Get milk"])
    expectNoDifference(reminders.map(\.notes), ["Whole milk"])
    expectNoDifference(reminders.map(\.isFlagged), [true])
    expectNoDifference(reminders.map(\.dueDate), [dueDate])
    expectNoDifference(reminders.map(\.priority), [.medium])

    let tags = try ReminderExample.decodeTags(
      (try await runtime.queryOnce(ReminderExample.tagsQuery)).values
    )
    expectNoDifference(tags.map(\.id), ["family", "shopping"])
    expectNoDifference(tags.map(\.title), ["family", "shopping"])

    let tagLinks = try ReminderExample.decodeReminderTagLinks(
      (try await runtime.queryOnce(ReminderExample.remindersQuery)).values
    )
    expectNoDifference(
      tagLinks,
      [
        ReminderTagLinkRecord(reminderID: "reminder-form-new", tagID: "family"),
        ReminderTagLinkRecord(reminderID: "reminder-form-new", tagID: "shopping"),
      ]
    )
  }

  // Source: pointfreeco/sqlite-data@0c79d7a5748fc6d9ce7a1ba2b50f31b175305049
  // Examples/RemindersTests/SearchRemindersTests.swift
  @Test("SQLiteData SearchRemindersTests.basics/showCompleted/deleteCompleted")
  func searchRemindersModelPortsBasicsShowCompletedAndDeleteCompleted() async throws {
    let fixture = try await upstreamRemindersFixture()
    var model = SearchRemindersModel(runtime: fixture.runtime, now: { fixture.now })

    try await model.load()
    expectNoDifference(model.searchResults.completedCount, 0)
    expectNoDifference(model.searchResults.rows, [])

    model.searchText = "Take"
    try await model.load()
    expectNoDifference(model.searchResults.completedCount, 1)
    expectNoDifference(model.searchResults.rows.map(\.title), ["**Take** out trash"])
    expectNoDifference(model.searchResults.rows.map(\.reminder.title), ["Take out trash"])
    expectNoDifference(model.searchResults.rows.map(\.remindersList.title), ["Family"])
    expectNoDifference(model.searchResults.rows.map(\.isPastDue), [false])

    try await model.showCompletedButtonTapped()
    expectNoDifference(model.showCompletedInSearchResults, true)
    expectNoDifference(model.searchResults.completedCount, 1)
    expectNoDifference(model.searchResults.rows.map(\.title), [
      "**Take** out trash",
      "**Take** a walk",
    ])
    expectNoDifference(model.searchResults.rows.map(\.reminder.isCompleted), [false, true])
    expectNoDifference(model.searchResults.rows.map(\.tags), ["", "#car #kids #social"])

    try await model.deleteCompletedReminders(
      updatedAt: fixture.now,
      transactionID: "tx-reminders-search-delete-completed"
    )
    expectNoDifference(model.searchResults.completedCount, 0)
    expectNoDifference(model.searchResults.rows.map(\.title), ["**Take** out trash"])

    let matchingAfterDelete = try ReminderExample.decodeReminders(
      try await fixture.runtime.query(
        ReminderExample.remindersSearchQuery(text: "Take", includeCompleted: true)
      )
    )
    expectNoDifference(matchingAfterDelete.map(\.title), ["Take out trash"])
  }

  @Test
  func searchRemindersModelPortsTagTokensSuggestionsAndAgedCompletedDelete() async throws {
    let fixture = try await upstreamRemindersFixture()
    var model = SearchRemindersModel(runtime: fixture.runtime, now: { fixture.now })

    model.searchText = "#so"
    try await model.load()
    expectNoDifference(model.tagSuggestions.map(\.title), ["social", "someday"])

    model.searchText = "#"
    try await model.load()
    expectNoDifference(model.tagSuggestions.map(\.title), [
      "adulting",
      "car",
      "kids",
      "night",
      "optional",
      "social",
      "someday",
    ])

    model.searchText = "#ult"
    try await model.load()
    expectNoDifference(model.tagSuggestions.map(\.title), [])

    model.searchText = "#so"
    try await model.load()

    let social = try #require(fixture.tags.first { $0.id == "social" })
    model.tagButtonTapped(social)
    expectNoDifference(
      model.searchTokens,
      [SearchRemindersModel.Token(kind: .tag, rawValue: "social")]
    )
    expectNoDifference(model.searchText, "")

    try await model.load()
    expectNoDifference(model.searchResults.completedCount, 1)
    expectNoDifference(model.searchResults.rows.map(\.reminder.title), [
      "Buy concert tickets",
      "Prepare for WWDC",
    ])

    try await model.showCompletedButtonTapped()
    expectNoDifference(model.searchResults.rows.map(\.reminder.title), [
      "Buy concert tickets",
      "Prepare for WWDC",
      "Take a walk",
    ])
    expectNoDifference(model.searchResults.rows.map(\.tags), [
      "#**social** #night",
      "#**social**",
      "#car #kids #**social**",
    ])

    try await model.deleteCompletedReminders(
      monthsAgo: 6,
      updatedAt: fixture.now,
      transactionID: "tx-reminders-search-delete-aged-completed"
    )
    expectNoDifference(model.searchResults.completedCount, 0)
    expectNoDifference(model.searchResults.rows.map(\.reminder.title), [
      "Buy concert tickets",
      "Prepare for WWDC",
    ])

    var nearModel = SearchRemindersModel(runtime: fixture.runtime, now: { fixture.now })
    nearModel.searchText = "Doctor\t"
    try await nearModel.load()
    expectNoDifference(
      nearModel.searchTokens,
      [SearchRemindersModel.Token(kind: .near, rawValue: "Doctor")]
    )
    expectNoDifference(nearModel.searchText, "")
    expectNoDifference(nearModel.searchResults.rows.map(\.title), ["**Doctor** appointment"])

    var multiWordModel = SearchRemindersModel(runtime: fixture.runtime, now: { fixture.now })
    multiWordModel.searchText = "Take trash"
    try await multiWordModel.load()
    expectNoDifference(multiWordModel.searchResults.rows.map(\.reminder.title), ["Take out trash"])

    let remainingCompleted = try ReminderExample.decodeReminders(
      try await fixture.runtime.query(
        ReminderExample.remindersSearchQuery(text: "", tagIDs: ["social"], includeCompleted: true)
      )
    )
    expectNoDifference(remainingCompleted.map(\.title), [
      "Buy concert tickets",
      "Prepare for WWDC",
    ])

    let concert = try #require(remainingCompleted.first { $0.title == "Buy concert tickets" })
    try await fixture.runtime.transact(
      InstantStoreTransaction(
        id: "tx-reminders-search-custom-tag",
        operations: ReminderExample.addTagOperations(
          reminderID: concert.id,
          listID: concert.remindersListID,
          tagID: "tag-errands-uuid",
          title: "Errands",
          updatedAt: fixture.now,
          transactionID: "tx-reminders-search-custom-tag"
        )
      ),
      createdAt: fixture.now
    )

    var customTagModel = SearchRemindersModel(runtime: fixture.runtime, now: { fixture.now })
    customTagModel.searchText = "#err"
    try await customTagModel.load()
    expectNoDifference(customTagModel.tagSuggestions, [
      ReminderTagRecord(id: "tag-errands-uuid", title: "Errands")
    ])
    customTagModel.tagButtonTapped(try #require(customTagModel.tagSuggestions.first))
    expectNoDifference(customTagModel.searchTokens, [
      SearchRemindersModel.Token(kind: .tag, rawValue: "Errands")
    ])

    try await customTagModel.load()
    expectNoDifference(customTagModel.searchResults.rows.map(\.reminder.title), [
      "Buy concert tickets"
    ])
    expectNoDifference(customTagModel.searchResults.rows.map(\.tags), [
      "#social #night #**Errands**"
    ])
  }

  @Test
  func searchRemindersModelPreservesRowsAndRecordsLoadError() async throws {
    let fixture = try await upstreamRemindersFixture()
    var model = SearchRemindersModel(
      runtime: fixture.runtime,
      searchText: "Take",
      now: { fixture.now }
    )

    try await model.load()
    expectNoDifference(model.isLoading, false)
    expectNoDifference(model.loadError, nil)
    expectNoDifference(model.searchResults.rows.map(\.reminder.title), ["Take out trash"])

    try await corruptReminderTitle(
      runtime: fixture.runtime,
      reminderID: "00000000-0000-0000-0000-00000000000A",
      title: "Take out trash",
      timestamp: fixture.now,
      transactionID: "tx-reminders-search-status-corruption"
    )

    do {
      try await model.load()
      #expect(Bool(false), "Expected corrupted search model load to fail.")
    } catch let error as InstantError {
      expectNoDifference(error.operation, "load search reminders")
      expectNoDifference(error.code, .decodeFailed)
      expectNoDifference(error.namespace, ReminderExample.remindersNamespace)
      expectNoDifference(error.path, "title")
    }

    expectNoDifference(model.isLoading, false)
    expectNoDifference(model.loadError?.operation, "load search reminders")
    expectNoDifference(model.loadError?.code, .decodeFailed)
    expectNoDifference(model.searchResults.rows.map(\.reminder.title), ["Take out trash"])
  }

  // Source: pointfreeco/sqlite-data@0c79d7a5748fc6d9ce7a1ba2b50f31b175305049
  // Examples/RemindersTests/RemindersDetailsTests.swift
  @Test("SQLiteData RemindersDetailsTests.basics/ordering")
  func remindersDetailModelPortsOrderingAndRichRows() async throws {
    let fixture = try await upstreamRemindersFixture()
    var model = RemindersDetailModel(
      detailType: .remindersList(fixture.personalList),
      runtime: fixture.runtime,
      now: { fixture.now }
    )

    try await model.load()
    expectNoDifference(model.ordering, .dueDate)
    expectNoDifference(model.reminderRows.map(\.reminder.title), [
      "Haircut",
      "Doctor appointment",
      "Buy concert tickets",
      "Groceries",
    ])
    expectNoDifference(model.reminderRows.map(\.isPastDue), [true, false, false, false])
    expectNoDifference(model.reminderRows.map(\.notes), [
      "",
      "Ask about diet",
      "",
      "Milk Eggs Apples Oatmeal Spinach",
    ])
    expectNoDifference(model.reminderRows.map(\.tags), [
      "#someday #optional",
      "#adulting",
      "#social #night",
      "#someday #optional #adulting",
    ])

    try await model.orderingButtonTapped(.priority)
    expectNoDifference(model.ordering, .priority)
    expectNoDifference(model.reminderRows.map(\.reminder.title), [
      "Doctor appointment",
      "Haircut",
      "Groceries",
      "Buy concert tickets",
    ])

    try await model.orderingButtonTapped(.title)
    expectNoDifference(model.ordering, .title)
    expectNoDifference(model.reminderRows.map(\.reminder.title), [
      "Buy concert tickets",
      "Doctor appointment",
      "Groceries",
      "Haircut",
    ])
  }

  @Test("SQLiteData RemindersDetailsTests.showCompleted")
  func remindersDetailModelPortsShowCompletedToggle() async throws {
    let fixture = try await upstreamRemindersFixture()
    var model = RemindersDetailModel(
      detailType: .remindersList(fixture.personalList),
      runtime: fixture.runtime,
      now: { fixture.now }
    )

    try await model.load()
    expectNoDifference(model.showCompleted, false)
    expectNoDifference(model.reminderRows.map(\.reminder.title), [
      "Haircut",
      "Doctor appointment",
      "Buy concert tickets",
      "Groceries",
    ])

    try await model.showCompletedButtonTapped()
    expectNoDifference(model.showCompleted, true)
    expectNoDifference(model.reminderRows.map(\.reminder.title), [
      "Haircut",
      "Doctor appointment",
      "Buy concert tickets",
      "Groceries",
      "Take a walk",
    ])

    try await model.showCompletedButtonTapped()
    expectNoDifference(model.showCompleted, false)
    expectNoDifference(model.reminderRows.map(\.reminder.title), [
      "Haircut",
      "Doctor appointment",
      "Buy concert tickets",
      "Groceries",
    ])
  }

  @Test("SQLiteData RemindersDetailsTests.move")
  func remindersDetailModelPortsMoveToManualOrdering() async throws {
    let fixture = try await upstreamRemindersFixture()
    var model = RemindersDetailModel(
      detailType: .remindersList(fixture.personalList),
      runtime: fixture.runtime,
      now: { fixture.now }
    )

    try await model.load()
    expectNoDifference(model.reminderRows.map(\.reminder.title), [
      "Haircut",
      "Doctor appointment",
      "Buy concert tickets",
      "Groceries",
    ])

    try await model.move(
      fromOffsets: IndexSet(integer: 2),
      toOffset: 0,
      updatedAt: fixture.now,
      transactionID: "tx-reminders-detail-move"
    )
    expectNoDifference(model.ordering, .manual)
    expectNoDifference(model.reminderRows.map(\.reminder.title), [
      "Buy concert tickets",
      "Haircut",
      "Doctor appointment",
      "Groceries",
    ])
  }

  @Test
  func remindersDetailModelPreservesRowsAndRecordsLoadError() async throws {
    let fixture = try await upstreamRemindersFixture()
    var model = RemindersDetailModel(
      detailType: .remindersList(fixture.personalList),
      runtime: fixture.runtime,
      now: { fixture.now }
    )

    try await model.load()
    expectNoDifference(model.isLoading, false)
    expectNoDifference(model.loadError, nil)
    expectNoDifference(model.reminderRows.map(\.reminder.title), [
      "Haircut",
      "Doctor appointment",
      "Buy concert tickets",
      "Groceries",
    ])

    try await corruptReminderTitle(
      runtime: fixture.runtime,
      reminderID: "00000000-0000-0000-0000-000000000003",
      title: "Groceries",
      timestamp: fixture.now,
      transactionID: "tx-reminders-detail-status-corruption"
    )

    do {
      try await model.load()
      #expect(Bool(false), "Expected corrupted detail model load to fail.")
    } catch let error as InstantError {
      expectNoDifference(error.operation, "load reminders detail")
      expectNoDifference(error.code, .decodeFailed)
      expectNoDifference(error.namespace, ReminderExample.remindersNamespace)
      expectNoDifference(error.path, "title")
    }

    expectNoDifference(model.isLoading, false)
    expectNoDifference(model.loadError?.operation, "load reminders detail")
    expectNoDifference(model.loadError?.code, .decodeFailed)
    expectNoDifference(model.reminderRows.map(\.reminder.title), [
      "Haircut",
      "Doctor appointment",
      "Buy concert tickets",
      "Groceries",
    ])
  }

  @Test("SQLiteData RemindersDetailsTests.all/completed/flagged/scheduled/today/tagged")
  func remindersDetailModelPortsSmartListsAndTags() async throws {
    let fixture = try await upstreamRemindersFixture()
    let someday = try #require(fixture.tags.first { $0.id == "someday" })

    func titles(for detailType: RemindersDetailType) async throws -> [String] {
      var model = RemindersDetailModel(
        detailType: detailType,
        runtime: fixture.runtime,
        now: { fixture.now }
      )
      try await model.load()
      return model.reminderRows.map(\.reminder.title)
    }

    let allTitles = try await titles(for: .all)
    expectNoDifference(
      allTitles,
      [
        "Haircut",
        "Doctor appointment",
        "Buy concert tickets",
        "Pick up kids from school",
        "Call accountant",
        "Prepare for WWDC",
        "Take out trash",
        "Groceries",
      ]
    )
    let completedTitles = try await titles(for: .completed)
    expectNoDifference(
      completedTitles,
      [
        "Take a walk",
        "Get laundry",
        "Send weekly emails",
      ]
    )
    let flaggedTitles = try await titles(for: .flagged)
    expectNoDifference(
      flaggedTitles,
      [
        "Haircut",
        "Pick up kids from school",
      ]
    )
    let scheduledTitles = try await titles(for: .scheduled)
    expectNoDifference(
      scheduledTitles,
      [
        "Haircut",
        "Doctor appointment",
        "Buy concert tickets",
        "Pick up kids from school",
        "Call accountant",
        "Prepare for WWDC",
        "Take out trash",
      ]
    )
    var scheduledModel = RemindersDetailModel(
      detailType: .scheduled,
      runtime: fixture.runtime,
      now: { fixture.now }
    )
    try await scheduledModel.showCompletedButtonTapped()
    expectNoDifference(
      scheduledModel.reminderRows.map(\.reminder.title),
      scheduledTitles
    )

    let todayTitles = try await titles(for: .today)
    expectNoDifference(
      todayTitles,
      [
        "Doctor appointment",
        "Buy concert tickets",
      ]
    )
    let somedayTitles = try await titles(for: .tags([someday]))
    expectNoDifference(
      somedayTitles,
      [
        "Haircut",
        "Groceries",
      ]
    )
  }

  @Test
  func reminderFormModelEditsExistingDraftAndReplacesTags() async throws {
    let cacheURL = try temporaryCacheURL()
    let timestamp = InstantTimestamp(milliseconds: 1_700_000_000_000)
    let dueDate = InstantTimestamp(milliseconds: 1_700_086_400_000)
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "app-a",
        persistenceURL: cacheURL,
        initialAttributes: ReminderExample.attributes
      )
    )
    try await runtime.transact(
      InstantStoreTransaction(
        id: "tx-reminder-form-existing",
        operations: ReminderExample.createListOperations(
          id: "list-form",
          title: "Family",
          position: 0,
          createdAt: timestamp,
          transactionID: "tx-reminder-form-existing"
        ) + ReminderExample.createReminderOperations(
          id: "reminder-form-existing",
          listID: "list-form",
          title: "Pack lunch",
          notes: "Bring a cooler",
          isFlagged: true,
          dueDate: dueDate,
          priority: .high,
          position: 0,
          createdAt: timestamp,
          transactionID: "tx-reminder-form-existing"
        ) + ReminderExample.addTagOperations(
          reminderID: "reminder-form-existing",
          listID: "list-form",
          tagID: "old",
          title: "old",
          updatedAt: timestamp,
          transactionID: "tx-reminder-form-existing"
        ) + ReminderExample.addTagOperations(
          reminderID: "reminder-form-existing",
          listID: "list-form",
          tagID: "keep",
          title: "keep",
          updatedAt: timestamp,
          transactionID: "tx-reminder-form-existing"
        )
      ),
      createdAt: timestamp
    )

    let existing = try #require(
      try ReminderExample.decodeReminders(
        (try await runtime.queryOnce(ReminderExample.remindersQuery)).values
      )
      .first
    )
    var model = ReminderFormModel(
      reminder: ReminderDraft(existing),
      selectedTags: [
        ReminderTagRecord(id: "keep", title: "keep"),
        ReminderTagRecord(id: "new", title: "new"),
      ],
      existingTagIDs: ["old", "keep"]
    )
    model.reminder.title = "Pack lunch and snacks"
    model.reminder.notes = "Edited from form"
    model.reminder.isFlagged = false
    model.reminder.setDateEnabled(false, defaultDueDate: timestamp)
    model.reminder.priority = nil
    let save = model.saveButtonTapped(
      newReminderID: "unused-new-reminder",
      updatedAt: timestamp,
      transactionID: "tx-reminder-form-edit"
    )
    try await runtime.transact(
      InstantStoreTransaction(id: "tx-reminder-form-edit", operations: save.operations),
      createdAt: timestamp
    )
    model.commit(save)

    expectNoDifference(model.reminder.id, "reminder-form-existing")
    expectNoDifference(model.existingTagIDs, ["keep", "new"])
    expectNoDifference(model.isDismissed, true)

    let edited = try ReminderExample.decodeReminders(
      (try await runtime.queryOnce(ReminderExample.remindersSearchQuery(text: "snacks", includeCompleted: true))).values
    )
    expectNoDifference(edited.map(\.id), ["reminder-form-existing"])
    expectNoDifference(edited.map(\.notes), ["Edited from form"])
    expectNoDifference(edited.map(\.isFlagged), [false])
    expectNoDifference(edited.map(\.dueDate), [nil])
    expectNoDifference(edited.map(\.priority), [nil])

    let oldTagged = try ReminderExample.decodeReminders(
      (try await runtime.queryOnce(ReminderExample.remindersSearchQuery(text: "", tagID: "old", includeCompleted: true))).values
    )
    expectNoDifference(oldTagged, [])

    let tagLinks = try ReminderExample.decodeReminderTagLinks(
      (try await runtime.queryOnce(ReminderExample.remindersQuery)).values
    )
    expectNoDifference(
      tagLinks,
      [
        ReminderTagLinkRecord(reminderID: "reminder-form-existing", tagID: "keep"),
        ReminderTagLinkRecord(reminderID: "reminder-form-existing", tagID: "new"),
      ]
    )
  }

  @Test
  func remindersExampleStatsUseUpstreamIncompletePredicates() {
    let timestamp = InstantTimestamp(milliseconds: 1_700_000_000_000)
    let today = InstantTimestamp(milliseconds: 1_700_000_100_000)
    let tomorrow = InstantTimestamp(milliseconds: today.milliseconds + 24 * 60 * 60 * 1000)
    let reminders = [
      ReminderRecord(
        id: "reminder-today",
        remindersListID: "list-rich",
        title: "Today",
        notes: "",
        isCompleted: false,
        isFlagged: true,
        dueDate: today,
        priority: .high,
        position: 0,
        createdAt: timestamp
      ),
      ReminderRecord(
        id: "reminder-future",
        remindersListID: "list-rich",
        title: "Future",
        notes: "",
        isCompleted: false,
        isFlagged: false,
        dueDate: tomorrow,
        position: 1,
        createdAt: timestamp
      ),
      ReminderRecord(
        id: "reminder-completed",
        remindersListID: "list-rich",
        title: "Completed",
        notes: "",
        isCompleted: true,
        isFlagged: true,
        dueDate: today,
        priority: .medium,
        position: 2,
        createdAt: timestamp
      ),
      ReminderRecord(
        id: "reminder-open",
        remindersListID: "list-rich",
        title: "Open",
        notes: "",
        isCompleted: false,
        isFlagged: false,
        position: 3,
        createdAt: timestamp
      ),
    ]

    expectNoDifference(
      ReminderExample.stats(for: reminders, today: today),
      RemindersStats(
        allCount: 3,
        completedCount: 1,
        flaggedCount: 1,
        scheduledCount: 2,
        todayCount: 1
      )
    )
  }

  @Test
  func syncUpsExamplePersistsMeetingsAndCascadesChildren() async throws {
    let cacheURL = try temporaryCacheURL()
    let timestamp = InstantTimestamp(milliseconds: 1_700_000_000_000)
    let meetingTimestamp = InstantTimestamp(milliseconds: 1_700_000_001_000)
    let syncUpID = "syncup-design"
    let firstAttendeeID = "attendee-blob"
    let secondAttendeeID = "attendee-blob-jr"
    let replacementAttendeeID = "attendee-blob-sr"
    let meetingID = "meeting-design"
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "app-a",
        persistenceURL: cacheURL,
        initialAttributes: SyncUpsExample.attributes,
        now: { timestamp }
      )
    )

    try await runtime.transact(
      InstantStoreTransaction(
        id: "tx-syncup-create",
        operations: SyncUpsExample.createSyncUpOperations(
          id: syncUpID,
          title: "Design",
          seconds: 900,
          theme: .appOrange,
          updatedAt: timestamp,
          transactionID: "tx-syncup-create"
        )
          + SyncUpsExample.createAttendeeOperations(
            id: firstAttendeeID,
            syncUpID: syncUpID,
            name: "Blob",
            updatedAt: timestamp,
            transactionID: "tx-syncup-create"
          )
          + SyncUpsExample.createAttendeeOperations(
            id: secondAttendeeID,
            syncUpID: syncUpID,
            name: "Blob Jr",
            updatedAt: timestamp,
            transactionID: "tx-syncup-create"
          )
      ),
      createdAt: timestamp
    )

    let createdSyncUps = try SyncUpsExample.decodeSyncUps(
      (try await runtime.queryOnce(SyncUpsExample.syncUpsQuery)).values
    )
    let createdAttendees = try SyncUpsExample.decodeAttendees(
      (try await runtime.queryOnce(SyncUpsExample.attendeesForSyncUpQuery(syncUpID))).values
    )
    expectNoDifference(
      createdSyncUps,
      [SyncUpRecord(id: syncUpID, title: "Design", seconds: 900, theme: .appOrange)]
    )
    expectNoDifference(createdAttendees.map(\.name), ["Blob", "Blob Jr"])

    try await runtime.transact(
      InstantStoreTransaction(
        id: "tx-syncup-edit",
        operations: SyncUpsExample.updateSyncUpOperations(
          id: syncUpID,
          title: "Design Review",
          seconds: 1_200,
          theme: .periwinkle,
          updatedAt: meetingTimestamp,
          transactionID: "tx-syncup-edit"
        )
          + SyncUpsExample.replaceAttendeesOperations(
            syncUpID: syncUpID,
            existingAttendeeIDs: createdAttendees.map(\.id),
            newAttendees: [
              SyncUpAttendeeDraft(id: replacementAttendeeID, name: "Blob Sr")
            ],
            updatedAt: meetingTimestamp,
            transactionID: "tx-syncup-edit"
          )
          + SyncUpsExample.recordMeetingOperations(
            id: meetingID,
            syncUpID: syncUpID,
            transcript: "Reviewed launch risks.",
            date: meetingTimestamp,
            transactionID: "tx-syncup-edit"
          )
      ),
      createdAt: meetingTimestamp
    )

    let relaunchedRuntime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "app-a",
        persistenceURL: cacheURL,
        initialAttributes: SyncUpsExample.attributes
      )
    )
    let updatedSyncUps = try SyncUpsExample.decodeSyncUps(
      (try await relaunchedRuntime.queryOnce(SyncUpsExample.syncUpsQuery)).values
    )
    let updatedAttendees = try SyncUpsExample.decodeAttendees(
      (try await relaunchedRuntime.queryOnce(SyncUpsExample.attendeesForSyncUpQuery(syncUpID))).values
    )
    let meetings = try SyncUpsExample.decodeMeetings(
      (try await relaunchedRuntime.queryOnce(SyncUpsExample.meetingsForSyncUpQuery(syncUpID))).values
    )
    expectNoDifference(
      updatedSyncUps,
      [SyncUpRecord(id: syncUpID, title: "Design Review", seconds: 1_200, theme: .periwinkle)]
    )
    expectNoDifference(updatedAttendees, [
      SyncUpAttendeeRecord(id: replacementAttendeeID, name: "Blob Sr", syncUpID: syncUpID)
    ])
    expectNoDifference(meetings, [
      SyncUpMeetingRecord(
        id: meetingID,
        date: meetingTimestamp,
        syncUpID: syncUpID,
        transcript: "Reviewed launch risks."
      )
    ])

    try await relaunchedRuntime.transact(
      InstantStoreTransaction(
        id: "tx-syncup-delete",
        operations: SyncUpsExample.deleteSyncUpOperations(id: syncUpID)
      ),
      createdAt: meetingTimestamp
    )
    let finalSyncUps = try SyncUpsExample.decodeSyncUps(
      (try await relaunchedRuntime.queryOnce(SyncUpsExample.syncUpsQuery)).values
    )
    let finalAttendees = try SyncUpsExample.decodeAttendees(
      (try await relaunchedRuntime.queryOnce(SyncUpsExample.attendeesQuery)).values
    )
    let finalMeetings = try SyncUpsExample.decodeMeetings(
      (try await relaunchedRuntime.queryOnce(SyncUpsExample.meetingsQuery)).values
    )
    expectNoDifference(finalSyncUps, [])
    expectNoDifference(finalAttendees, [])
    expectNoDifference(finalMeetings, [])
  }

  @Test
  func syncUpsExampleDeletesAttendeesAndReaddsBlankReplacement() async throws {
    let cacheURL = try temporaryCacheURL()
    let timestamp = InstantTimestamp(milliseconds: 1_700_000_000_000)
    let syncUpID = "syncup-design"
    let firstAttendeeID = "attendee-blob"
    let secondAttendeeID = "attendee-blob-jr"
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "app-a",
        persistenceURL: cacheURL,
        initialAttributes: SyncUpsExample.attributes,
        now: { timestamp }
      )
    )

    try await runtime.transact(
      InstantStoreTransaction(
        id: "tx-syncup-attendees",
        operations: SyncUpsExample.createSyncUpOperations(
          id: syncUpID,
          title: "Design",
          seconds: 900,
          theme: .appOrange,
          updatedAt: timestamp,
          transactionID: "tx-syncup-attendees"
        )
        + SyncUpsExample.createAttendeeOperations(
          id: firstAttendeeID,
          syncUpID: syncUpID,
          name: "Blob",
          updatedAt: timestamp,
          transactionID: "tx-syncup-attendees"
        )
        + SyncUpsExample.createAttendeeOperations(
          id: secondAttendeeID,
          syncUpID: syncUpID,
          name: "Blob Jr",
          updatedAt: timestamp,
          transactionID: "tx-syncup-attendees"
        )
      ),
      createdAt: timestamp
    )

    try await runtime.transact(
      InstantStoreTransaction(
        id: "tx-delete-attendee",
        operations: SyncUpsExample.deleteAttendeeOperations(
          id: secondAttendeeID,
          syncUpID: syncUpID,
          remainingAttendeeIDs: [firstAttendeeID],
          updatedAt: timestamp,
          transactionID: "tx-delete-attendee"
        )
      ),
      createdAt: timestamp
    )

    let attendees = try SyncUpsExample.decodeAttendees(
      (try await runtime.queryOnce(SyncUpsExample.attendeesForSyncUpQuery(syncUpID))).values
    )
    expectNoDifference(attendees.map(\.name), ["Blob"])

    do {
      try await runtime.transact(
        InstantStoreTransaction(
          id: "tx-delete-last-attendee-without-replacement",
          operations: SyncUpsExample.deleteAttendeeOperations(
            id: firstAttendeeID,
            syncUpID: syncUpID,
            remainingAttendeeIDs: [],
            updatedAt: timestamp,
            transactionID: "tx-delete-last-attendee-without-replacement"
          )
        ),
        createdAt: timestamp
      )
      #expect(Bool(false), "Expected last attendee deletion without a replacement to fail.")
    } catch let error as InstantError {
      expectNoDifference(error.code, .validationFailed)
    }

    let stillHasOneAttendee = try SyncUpsExample.decodeAttendees(
      (try await runtime.queryOnce(SyncUpsExample.attendeesForSyncUpQuery(syncUpID))).values
    )
    expectNoDifference(stillHasOneAttendee.map(\.name), ["Blob"])

    try await runtime.transact(
      InstantStoreTransaction(
        id: "tx-delete-last-attendee",
        operations: SyncUpsExample.deleteAttendeeOperations(
          id: firstAttendeeID,
          syncUpID: syncUpID,
          remainingAttendeeIDs: [],
          replacementAttendeeID: "attendee-blank",
          updatedAt: timestamp,
          transactionID: "tx-delete-last-attendee"
        )
      ),
      createdAt: timestamp
    )

    let replacementAttendees = try SyncUpsExample.decodeAttendees(
      (try await runtime.queryOnce(SyncUpsExample.attendeesForSyncUpQuery(syncUpID))).values
    )
    expectNoDifference(replacementAttendees, [
      SyncUpAttendeeRecord(id: "attendee-blank", name: "", syncUpID: syncUpID)
    ])

    let relaunched = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "app-a",
        persistenceURL: cacheURL,
        initialAttributes: SyncUpsExample.attributes
      )
    )
    let persistedAttendees = try SyncUpsExample.decodeAttendees(
      (try await relaunched.queryOnce(SyncUpsExample.attendeesForSyncUpQuery(syncUpID))).values
    )
    expectNoDifference(persistedAttendees, [
      SyncUpAttendeeRecord(id: "attendee-blank", name: "", syncUpID: syncUpID)
    ])
  }

  @Test
  func syncUpFormModelSavesNewDraftWithNonBlankAttendees() async throws {
    let cacheURL = try temporaryCacheURL()
    let timestamp = InstantTimestamp(milliseconds: 1_700_000_000_000)
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "app-a",
        persistenceURL: cacheURL,
        initialAttributes: SyncUpsExample.attributes,
        now: { timestamp }
      )
    )
    var model = SyncUpFormModel(
      syncUp: SyncUpDraft(title: "Morning Sync"),
      blankAttendeeID: "attendee-draft-blank"
    )
    model.addAttendeeButtonTapped(id: "attendee-draft-second")
    model.addAttendeeButtonTapped(id: "attendee-draft-third")
    model.attendees[0].name = "Blob"
    model.attendees[1].name = "Blob Jr."

    let save = model.saveButtonTapped(
      newSyncUpID: "syncup-morning",
      blankAttendeeID: "attendee-draft-save-blank",
      updatedAt: timestamp,
      transactionID: "tx-syncup-form-new"
    )
    try await runtime.transact(
      InstantStoreTransaction(id: "tx-syncup-form-new", operations: save.operations),
      createdAt: timestamp
    )
    model.commit(save)

    let syncUps = try SyncUpsExample.decodeSyncUps(
      (try await runtime.queryOnce(SyncUpsExample.syncUpsQuery)).values
    )
    let attendees = try SyncUpsExample.decodeAttendees(
      (try await runtime.queryOnce(SyncUpsExample.attendeesForSyncUpQuery(save.syncUpID))).values
    )
    expectNoDifference(model.isDismissed, true)
    expectNoDifference(model.syncUp.id, "syncup-morning")
    expectNoDifference(syncUps, [
      SyncUpRecord(id: "syncup-morning", title: "Morning Sync", seconds: 300, theme: .bubblegum)
    ])
    expectNoDifference(attendees.map(\.name), ["Blob", "Blob Jr."])
  }

  @Test
  func syncUpFormModelFailedCreateCanRetryWithCreateSemantics() async throws {
    let cacheURL = try temporaryCacheURL()
    let timestamp = InstantTimestamp(milliseconds: 1_700_000_000_000)
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "app-a",
        persistenceURL: cacheURL,
        initialAttributes: SyncUpsExample.attributes,
        now: { timestamp }
      )
    )
    try await runtime.transact(
      InstantStoreTransaction(
        id: "tx-syncup-existing",
        operations: SyncUpsExample.createSyncUpOperations(
          id: "syncup-collision",
          title: "Existing",
          seconds: 60,
          theme: .appOrange,
          updatedAt: timestamp,
          transactionID: "tx-syncup-existing"
        )
      ),
      createdAt: timestamp
    )
    var model = SyncUpFormModel(
      syncUp: SyncUpDraft(title: "Retry Sync"),
      blankAttendeeID: "attendee-retry-blank"
    )
    model.attendees[0].name = "Blob"

    let failedSave = model.saveButtonTapped(
      newSyncUpID: "syncup-collision",
      blankAttendeeID: "attendee-retry-save-blank",
      updatedAt: timestamp,
      transactionID: "tx-syncup-form-collision"
    )
    do {
      try await runtime.transact(
        InstantStoreTransaction(id: "tx-syncup-form-collision", operations: failedSave.operations),
        createdAt: timestamp
      )
      #expect(Bool(false), "Expected duplicate sync-up id to fail before form commit.")
    } catch let error as InstantError {
      expectNoDifference(error.code, .validationFailed)
    } catch {
      #expect(Bool(false), "Unexpected error: \(error)")
    }
    expectNoDifference(model.syncUp.id, nil)
    expectNoDifference(model.existingAttendeeIDs, [])
    expectNoDifference(model.isDismissed, false)

    let retrySave = model.saveButtonTapped(
      newSyncUpID: "syncup-retry",
      blankAttendeeID: "attendee-retry-second-save-blank",
      updatedAt: timestamp,
      transactionID: "tx-syncup-form-retry"
    )
    try await runtime.transact(
      InstantStoreTransaction(id: "tx-syncup-form-retry", operations: retrySave.operations),
      createdAt: timestamp
    )
    model.commit(retrySave)

    let syncUps = try SyncUpsExample.decodeSyncUps(
      (try await runtime.queryOnce(SyncUpsExample.syncUpsQuery)).values
    )
    expectNoDifference(model.syncUp.id, "syncup-retry")
    expectNoDifference(model.isDismissed, true)
    expectNoDifference(syncUps.map(\.id), ["syncup-collision", "syncup-retry"])
  }

  @Test
  func syncUpFormNewDraftTransportDoesNotRequireCreatedSyncUpToExist() throws {
    let timestamp = InstantTimestamp(milliseconds: 1_700_000_000_000)
    var model = SyncUpFormModel(
      syncUp: SyncUpDraft(title: "Design"),
      blankAttendeeID: "attendee-blank"
    )
    model.attendees[0].name = "Blob"
    let save = model.saveButtonTapped(
      newSyncUpID: "syncup-new",
      blankAttendeeID: "attendee-save-blank",
      updatedAt: timestamp,
      transactionID: "tx-syncup-form-new-transport"
    )
    let transportMutation = InstantTransportMutation(
      PendingMutation(
        id: "mutation-syncup-form-new-transport",
        createdAt: timestamp,
        transaction: InstantStoreTransaction(
          id: "tx-syncup-form-new-transport",
          operations: save.operations
        )
      )
    )

    let data = try JSONEncoder().encode(transportMutation)
    let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    let preconditions = try #require(object["preconditions"] as? [[String: Any]])
    let syncUpKinds = preconditions.compactMap { precondition in
      precondition["entity"] as? String == "syncup-new"
        ? precondition["kind"] as? String
        : nil
    }
    expectNoDifference(syncUpKinds, ["entity-missing"])
  }

  @Test
  func syncUpFormModelUpdatesExistingDraftAndReplacesAttendees() async throws {
    let cacheURL = try temporaryCacheURL()
    let timestamp = InstantTimestamp(milliseconds: 1_700_000_000_000)
    let editTimestamp = InstantTimestamp(milliseconds: 1_700_000_001_000)
    let syncUpID = "syncup-design"
    let attendeeNames = ["Blob", "Blob Jr", "Blob Sr", "Blob Esq", "Blob III", "Blob I"]
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "app-a",
        persistenceURL: cacheURL,
        initialAttributes: SyncUpsExample.attributes,
        now: { timestamp }
      )
    )
    let createOperations = SyncUpsExample.createSyncUpOperations(
      id: syncUpID,
      title: "Design",
      seconds: 60,
      theme: .appOrange,
      updatedAt: timestamp,
      transactionID: "tx-syncup-form-seed"
    )
      + attendeeNames.enumerated().flatMap { offset, name in
        SyncUpsExample.createAttendeeOperations(
          id: "attendee-\(offset)",
          syncUpID: syncUpID,
          name: name,
          updatedAt: timestamp,
          transactionID: "tx-syncup-form-seed"
        )
      }
    try await runtime.transact(
      InstantStoreTransaction(id: "tx-syncup-form-seed", operations: createOperations),
      createdAt: timestamp
    )

    let existingSyncUp = try #require(
      try SyncUpsExample.decodeSyncUps(
        (try await runtime.queryOnce(SyncUpsExample.syncUpsQuery)).values
      )
      .first
    )
    let existingAttendees = try SyncUpsExample.decodeAttendees(
      (try await runtime.queryOnce(SyncUpsExample.attendeesForSyncUpQuery(syncUpID))).values
    )
    var model = SyncUpFormModel(
      syncUp: existingSyncUp,
      existingAttendees: existingAttendees,
      draftAttendeeIDs: existingAttendees.indices.map { "draft-attendee-\($0)" },
      blankAttendeeID: "draft-attendee-blank"
    )

    model.syncUp.title = "Evening Sync"
    model.deleteAttendees(atOffsets: IndexSet(1..<existingAttendees.count), blankAttendeeID: "draft-empty")
    model.addAttendeeButtonTapped(id: "draft-attendee-new")
    model.attendees[model.attendees.count - 1].name = "Blobby McBlob"

    let save = model.saveButtonTapped(
      newSyncUpID: "unused-new-syncup",
      blankAttendeeID: "draft-save-blank",
      updatedAt: editTimestamp,
      transactionID: "tx-syncup-form-edit"
    )
    try await runtime.transact(
      InstantStoreTransaction(id: "tx-syncup-form-edit", operations: save.operations),
      createdAt: editTimestamp
    )
    model.commit(save)

    let syncUp = try #require(
      try SyncUpsExample.decodeSyncUps(
        (try await runtime.queryOnce(SyncUpsExample.syncUpsQuery)).values
      )
      .first
    )
    let attendees = try SyncUpsExample.decodeAttendees(
      (try await runtime.queryOnce(SyncUpsExample.attendeesForSyncUpQuery(syncUpID))).values
    )
    expectNoDifference(model.isDismissed, true)
    expectNoDifference(save.syncUpID, syncUpID)
    expectNoDifference(syncUp.title, "Evening Sync")
    expectNoDifference(attendees.map(\.id), ["draft-attendee-0", "draft-attendee-new"])
    expectNoDifference(attendees.map(\.name), ["Blob", "Blobby McBlob"])
  }

  @Test
  func syncUpFormModelSanitizesDraftAttendeeIDsBeforeReplacement() {
    let existingAttendees = [
      SyncUpAttendeeRecord(id: "attendee-0", name: "Blob", syncUpID: "syncup-design"),
      SyncUpAttendeeRecord(id: "attendee-1", name: "Blob Jr", syncUpID: "syncup-design"),
    ]

    let model = SyncUpFormModel(
      syncUp: SyncUpRecord(
        id: "syncup-design",
        title: "Design",
        seconds: 60,
        theme: .appOrange
      ),
      existingAttendees: existingAttendees,
      draftAttendeeIDs: ["attendee-0", "attendee-0"],
      blankAttendeeID: "draft-blank"
    )

    expectNoDifference(model.existingAttendeeIDs, ["attendee-0", "attendee-1"])
    expectNoDifference(
      model.attendees.map(\.id),
      ["draft-attendee-0", "draft-draft-attendee-0"]
    )
    #expect(Set(model.attendees.map(\.id)).isDisjoint(with: Set(model.existingAttendeeIDs)))
  }

  @Test
  func syncUpFormModelSanitizesPublicDraftIDsAtInitAddAndSave() {
    var model = SyncUpFormModel(
      syncUp: SyncUpDraft(id: "syncup-design", title: "Design"),
      attendees: [
        SyncUpAttendeeDraft(id: "attendee-0", name: "Blob"),
        SyncUpAttendeeDraft(id: "attendee-0", name: "Blob Jr"),
      ],
      existingAttendeeIDs: ["attendee-0", "attendee-0", "attendee-1"],
      blankAttendeeID: "attendee-0",
      focus: .attendee("attendee-0")
    )

    expectNoDifference(model.existingAttendeeIDs, ["attendee-0", "attendee-1"])
    expectNoDifference(
      model.attendees.map(\.id),
      ["draft-attendee-0", "draft-draft-attendee-0"]
    )
    expectNoDifference(model.focus, .attendee("draft-attendee-0"))

    model.addAttendeeButtonTapped(id: "draft-attendee-0")
    expectNoDifference(
      model.attendees.map(\.id),
      ["draft-attendee-0", "draft-draft-attendee-0", "draft-draft-draft-attendee-0"]
    )
    expectNoDifference(model.focus, .attendee("draft-draft-draft-attendee-0"))

    model.attendees[2].name = "Blobby"
    model.attendees.append(SyncUpAttendeeDraft(id: "attendee-1", name: "Manual"))
    model.focus = .attendee("attendee-1")
    let save = model.saveButtonTapped(
      newSyncUpID: "unused-new-syncup",
      blankAttendeeID: "unused-blank",
      updatedAt: InstantTimestamp(milliseconds: 1_700_000_000_000),
      transactionID: "tx-syncup-form-public-sanitize"
    )

    expectNoDifference(
      save.attendees.map(\.id),
      [
        "draft-attendee-0",
        "draft-draft-attendee-0",
        "draft-draft-draft-attendee-0",
        "draft-attendee-1",
      ]
    )
    expectNoDifference(model.focus, .attendee("draft-attendee-0"))
    #expect(Set(save.attendees.map(\.id)).isDisjoint(with: Set(model.existingAttendeeIDs)))
    expectNoDifference(Set(save.attendees.map(\.id)).count, save.attendees.count)
  }

  @Test
  func syncUpFormReplacementRejectsOverlappingExistingAndNewAttendeeIDs() async throws {
    let cacheURL = try temporaryCacheURL()
    let timestamp = InstantTimestamp(milliseconds: 1_700_000_000_000)
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "app-a",
        persistenceURL: cacheURL,
        initialAttributes: SyncUpsExample.attributes,
        now: { timestamp }
      )
    )
    try await runtime.transact(
      InstantStoreTransaction(
        id: "tx-syncup-overlap-seed",
        operations: SyncUpsExample.createSyncUpOperations(
          id: "syncup-a",
          title: "A",
          seconds: 60,
          theme: .appOrange,
          updatedAt: timestamp,
          transactionID: "tx-syncup-overlap-seed"
        )
          + SyncUpsExample.createAttendeeOperations(
            id: "attendee-a",
            syncUpID: "syncup-a",
            name: "A",
            updatedAt: timestamp,
            transactionID: "tx-syncup-overlap-seed"
          )
      ),
      createdAt: timestamp
    )

    do {
      try await runtime.transact(
        InstantStoreTransaction(
          id: "tx-syncup-overlap-replace",
          operations: SyncUpsExample.replaceAttendeesOperations(
            syncUpID: "syncup-a",
            existingAttendeeIDs: ["attendee-a"],
            newAttendees: [SyncUpAttendeeDraft(id: "attendee-a", name: "A Updated")],
            updatedAt: timestamp,
            transactionID: "tx-syncup-overlap-replace"
          )
        ),
        createdAt: timestamp
      )
      #expect(Bool(false), "Expected overlapping replacement attendee IDs to fail.")
    } catch let error as InstantError {
      expectNoDifference(error.code, .validationFailed)
    } catch {
      #expect(Bool(false), "Unexpected error: \(error)")
    }

    let pending = await runtime.pendingMutations()
    expectNoDifference(pending.map(\.transaction.id), ["tx-syncup-overlap-seed"])
  }

  @Test
  func syncUpFormReplacementRejectsDuplicateNewAttendeeIDs() async throws {
    let cacheURL = try temporaryCacheURL()
    let timestamp = InstantTimestamp(milliseconds: 1_700_000_000_000)
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "app-a",
        persistenceURL: cacheURL,
        initialAttributes: SyncUpsExample.attributes,
        now: { timestamp }
      )
    )
    try await runtime.transact(
      InstantStoreTransaction(
        id: "tx-syncup-duplicate-seed",
        operations: SyncUpsExample.createSyncUpOperations(
          id: "syncup-a",
          title: "A",
          seconds: 60,
          theme: .appOrange,
          updatedAt: timestamp,
          transactionID: "tx-syncup-duplicate-seed"
        )
      ),
      createdAt: timestamp
    )

    do {
      try await runtime.transact(
        InstantStoreTransaction(
          id: "tx-syncup-duplicate-replace",
          operations: SyncUpsExample.replaceAttendeesOperations(
            syncUpID: "syncup-a",
            existingAttendeeIDs: [],
            newAttendees: [
              SyncUpAttendeeDraft(id: "attendee-a", name: "A"),
              SyncUpAttendeeDraft(id: "attendee-a", name: "A Duplicate"),
            ],
            updatedAt: timestamp,
            transactionID: "tx-syncup-duplicate-replace"
          )
        ),
        createdAt: timestamp
      )
      #expect(Bool(false), "Expected duplicate replacement attendee IDs to fail.")
    } catch let error as InstantError {
      expectNoDifference(error.code, .validationFailed)
    } catch {
      #expect(Bool(false), "Unexpected error: \(error)")
    }

    let pending = await runtime.pendingMutations()
    expectNoDifference(pending.map(\.transaction.id), ["tx-syncup-duplicate-seed"])
  }

  @Test
  func syncUpFormReplacementRejectsFreshExistingAttendeeIDsThatMatchNewAttendees() async throws {
    let cacheURL = try temporaryCacheURL()
    let timestamp = InstantTimestamp(milliseconds: 1_700_000_000_000)
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "app-a",
        persistenceURL: cacheURL,
        initialAttributes: SyncUpsExample.attributes,
        now: { timestamp }
      )
    )
    try await runtime.transact(
      InstantStoreTransaction(
        id: "tx-syncup-fresh-existing-seed",
        operations: SyncUpsExample.createSyncUpOperations(
          id: "syncup-a",
          title: "A",
          seconds: 60,
          theme: .appOrange,
          updatedAt: timestamp,
          transactionID: "tx-syncup-fresh-existing-seed"
        )
      ),
      createdAt: timestamp
    )

    do {
      try await runtime.transact(
        InstantStoreTransaction(
          id: "tx-syncup-fresh-existing-replace",
          operations: SyncUpsExample.replaceAttendeesOperations(
            syncUpID: "syncup-a",
            existingAttendeeIDs: ["attendee-a"],
            newAttendees: [SyncUpAttendeeDraft(id: "attendee-a", name: "A")],
            updatedAt: timestamp,
            transactionID: "tx-syncup-fresh-existing-replace"
          )
        ),
        createdAt: timestamp
      )
      #expect(Bool(false), "Expected fresh existing attendee IDs to fail before inserts.")
    } catch let error as InstantError {
      expectNoDifference(error.code, .validationFailed)
    } catch {
      #expect(Bool(false), "Unexpected error: \(error)")
    }

    let pending = await runtime.pendingMutations()
    expectNoDifference(pending.map(\.transaction.id), ["tx-syncup-fresh-existing-seed"])
  }

  @Test
  func syncUpFormReplacementRejectsExistingAttendeeFromAnotherSyncUp() async throws {
    let cacheURL = try temporaryCacheURL()
    let timestamp = InstantTimestamp(milliseconds: 1_700_000_000_000)
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "app-a",
        persistenceURL: cacheURL,
        initialAttributes: SyncUpsExample.attributes,
        now: { timestamp }
      )
    )
    let operations =
      SyncUpsExample.createSyncUpOperations(
        id: "syncup-a",
        title: "A",
        seconds: 60,
        theme: .appOrange,
        updatedAt: timestamp,
        transactionID: "tx-syncup-cross-seed"
      )
      + SyncUpsExample.createAttendeeOperations(
        id: "attendee-a",
        syncUpID: "syncup-a",
        name: "A",
        updatedAt: timestamp,
        transactionID: "tx-syncup-cross-seed"
      )
      + SyncUpsExample.createSyncUpOperations(
        id: "syncup-b",
        title: "B",
        seconds: 60,
        theme: .periwinkle,
        updatedAt: timestamp,
        transactionID: "tx-syncup-cross-seed"
      )
      + SyncUpsExample.createAttendeeOperations(
        id: "attendee-b",
        syncUpID: "syncup-b",
        name: "B",
        updatedAt: timestamp,
        transactionID: "tx-syncup-cross-seed"
      )
    try await runtime.transact(
      InstantStoreTransaction(id: "tx-syncup-cross-seed", operations: operations),
      createdAt: timestamp
    )

    do {
      try await runtime.transact(
        InstantStoreTransaction(
          id: "tx-syncup-cross-replace",
          operations: SyncUpsExample.replaceAttendeesOperations(
            syncUpID: "syncup-a",
            existingAttendeeIDs: ["attendee-b"],
            newAttendees: [SyncUpAttendeeDraft(id: "attendee-a-new", name: "A New")],
            updatedAt: timestamp,
            transactionID: "tx-syncup-cross-replace"
          )
        ),
        createdAt: timestamp
      )
      #expect(Bool(false), "Expected cross-sync-up attendee replacement to fail.")
    } catch let error as InstantError {
      expectNoDifference(error.code, .validationFailed)
    } catch {
      #expect(Bool(false), "Unexpected error: \(error)")
    }

    let syncUpBAttendees = try SyncUpsExample.decodeAttendees(
      (try await runtime.queryOnce(SyncUpsExample.attendeesForSyncUpQuery("syncup-b"))).values
    )
    expectNoDifference(syncUpBAttendees, [
      SyncUpAttendeeRecord(id: "attendee-b", name: "B", syncUpID: "syncup-b")
    ])
  }

  @Test
  func syncUpFormModelMaintainsBlankAttendeeFocusAndDismissalState() {
    var model = SyncUpFormModel(
      syncUp: SyncUpDraft(title: "Focus"),
      attendees: [
        SyncUpAttendeeDraft(id: "draft-first", name: "Blob"),
        SyncUpAttendeeDraft(id: "draft-second", name: "Blob Jr"),
      ],
      blankAttendeeID: "draft-unused-blank"
    )

    model.deleteAttendees(atOffsets: IndexSet(0..<2), blankAttendeeID: "draft-replacement")
    expectNoDifference(model.attendees, [
      SyncUpAttendeeDraft(id: "draft-replacement", name: "")
    ])
    expectNoDifference(model.focus, .attendee("draft-replacement"))

    model.attendees[0].name = "   "
    let save = model.saveButtonTapped(
      newSyncUpID: "syncup-focus",
      blankAttendeeID: "draft-save-replacement",
      updatedAt: InstantTimestamp(milliseconds: 1_700_000_000_000),
      transactionID: "tx-syncup-form-focus"
    )
    expectNoDifference(save.attendees, [
      SyncUpAttendeeDraft(id: "draft-save-replacement", name: "")
    ])
    expectNoDifference(model.focus, .attendee("draft-save-replacement"))
    expectNoDifference(model.isDismissed, false)
    model.commit(save)
    expectNoDifference(model.isDismissed, true)

    var cancelModel = SyncUpFormModel(
      syncUp: SyncUpDraft(title: "Cancel"),
      blankAttendeeID: "draft-cancel"
    )
    cancelModel.cancelButtonTapped()
    expectNoDifference(cancelModel.isDismissed, true)
  }

  @Test
  func syncUpRecordingModelUsesSpeechSoundAndSavesTranscript() async throws {
    let cacheURL = try temporaryCacheURL()
    let timestamp = InstantTimestamp(milliseconds: 1_700_000_000_000)
    let syncUp = SyncUpRecord(
      id: "syncup-recording",
      title: "Recording",
      seconds: 2,
      theme: .appOrange
    )
    let attendees = [
      SyncUpAttendeeRecord(id: "attendee-blob", name: "Blob", syncUpID: syncUp.id),
      SyncUpAttendeeRecord(id: "attendee-blob-jr", name: "Blob Jr", syncUpID: syncUp.id),
    ]
    let soundEffects = SyncUpSoundEffectRecorder()
    var model = SyncUpRecordingModel(
      syncUp: syncUp,
      attendees: attendees,
      speechClient: .scripted(
        authorizationStatus: .notDetermined,
        requestedAuthorization: .authorized,
        results: [
          SyncUpSpeechRecognitionResult(formattedString: "Blob opened"),
          SyncUpSpeechRecognitionResult(formattedString: "Blob Jr closed", isFinal: true),
        ]
      ),
      soundEffectClient: SyncUpSoundEffectClient(
        load: { await soundEffects.load($0) },
        play: { await soundEffects.play() }
      )
    )

    await model.task()
    expectNoDifference(model.requestedAuthorization, true)
    expectNoDifference(model.authorizationStatus, .authorized)
    expectNoDifference(model.loadedSoundEffectFileName, "ding.wav")
    expectNoDifference(model.transcript, "Blob Jr closed")
    expectNoDifference(model.speechResultCount, 2)
    let loadedFileNames = await soundEffects.loadedFileNames()
    expectNoDifference(loadedFileNames, ["ding.wav"])

    let firstTick = await model.tick()
    expectNoDifference(firstTick, .advancedSpeaker(attendeeID: "attendee-blob-jr"))
    expectNoDifference(model.speakerIndex, 1)
    expectNoDifference(model.secondsElapsed, 1)
    expectNoDifference(model.currentSpeaker?.name, "Blob Jr")
    let playCount = await soundEffects.playCount()
    expectNoDifference(playCount, 1)

    let finalTick = await model.tick()
    expectNoDifference(finalTick, .finished)
    let save = model.finishMeeting(
      meetingID: "meeting-recording",
      date: timestamp,
      transactionID: "tx-syncup-recording"
    )
    expectNoDifference(model.isDismissed, true)

    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "app-a",
        persistenceURL: cacheURL,
        initialAttributes: SyncUpsExample.attributes,
        now: { timestamp }
      )
    )
    try await runtime.transact(
      InstantStoreTransaction(
        id: "tx-syncup-create-recording",
        operations: SyncUpsExample.createSyncUpOperations(
          id: syncUp.id,
          title: syncUp.title,
          seconds: syncUp.seconds,
          theme: syncUp.theme,
          updatedAt: timestamp,
          transactionID: "tx-syncup-create-recording"
        )
        + attendees.flatMap { attendee in
          SyncUpsExample.createAttendeeOperations(
            id: attendee.id,
            syncUpID: attendee.syncUpID,
            name: attendee.name,
            updatedAt: timestamp,
            transactionID: "tx-syncup-create-recording"
          )
        }
      ),
      createdAt: timestamp
    )
    try await runtime.transact(
      InstantStoreTransaction(id: "tx-syncup-recording", operations: save.operations),
      createdAt: timestamp
    )

    let meetings = try SyncUpsExample.decodeMeetings(
      (try await runtime.queryOnce(SyncUpsExample.meetingsForSyncUpQuery(syncUp.id))).values
    )
    expectNoDifference(meetings, [
      SyncUpMeetingRecord(
        id: "meeting-recording",
        date: timestamp,
        syncUpID: syncUp.id,
        transcript: "Blob Jr closed"
      )
    ])
  }

  @Test
  func syncUpRecordingModelDeniedSpeechOpensSettings() async {
    let settings = SyncUpOpenSettingsRecorder()
    var model = SyncUpRecordingModel(
      syncUp: SyncUpRecord(
        id: "syncup-denied",
        title: "Denied",
        seconds: 60,
        theme: .bubblegum
      ),
      attendees: [
        SyncUpAttendeeRecord(id: "attendee-denied", name: "Blob", syncUpID: "syncup-denied")
      ],
      speechClient: .denied,
      openSettingsClient: SyncUpOpenSettingsClient {
        await settings.open()
      }
    )

    await model.task()
    expectNoDifference(model.authorizationStatus, .denied)
    expectNoDifference(model.alert, .speechRecognitionDenied)
    expectNoDifference(model.transcript, "")

    let outcome = await model.alertButtonTapped(.openSettings)
    expectNoDifference(outcome, .settingsOpened)
    let openCount = await settings.openCount()
    expectNoDifference(openCount, 1)
    expectNoDifference(model.alert, .speechRecognitionDenied)
  }

  @Test
  func syncUpsRecordingValidationProducesTerminalEvidence() async throws {
    let cacheURL = try temporaryCacheURL()
    let ids = LockIsolated([
      "syncup-validation",
      "attendee-blob",
      "attendee-blob-jr",
      "tx-seed",
      "meeting-validation",
      "tx-meeting",
    ])

    let result = try await InstantSwiftDataSyncUpsRecordingValidation.run(
      appID: "app-a",
      cacheURL: cacheURL,
      timestamp: { InstantTimestamp(milliseconds: 1_700_000_000_000) },
      makeID: {
        ids.withValue { ids in
          ids.isEmpty ? UUID().uuidString.lowercased() : ids.removeFirst()
        }
      }
    )

    expectNoDifference(result.appID, "app-a")
    expectNoDifference(result.cacheURL, cacheURL)
    expectNoDifference(result.syncUpID, "syncup-validation")
    expectNoDifference(result.attendeeIDs, ["attendee-blob", "attendee-blob-jr"])
    expectNoDifference(result.meetingID, "meeting-validation")
    expectNoDifference(result.evidence.map(\.caseID), Array(repeating: "validation.syncups.recording", count: 7))
    expectNoDifference(result.evidence.map(\.event), [
      "seed",
      "speech-task",
      "speaker-advance",
      "finish",
      "meeting-save",
      "settings-open",
      "relaunch",
    ])
    expectNoDifference(result.evidence.map(\.ok), Array(repeating: true, count: 7))

    let seed = result.evidence[0].details
    expectNoDifference(seed.syncUpIDs, ["syncup-validation"])
    expectNoDifference(seed.syncUpTitles, ["Tiny validation standup"])
    expectNoDifference(seed.attendeeIDs, ["attendee-blob", "attendee-blob-jr"])
    expectNoDifference(seed.attendeeNames, ["Blob", "Blob Jr"])
    expectNoDifference(seed.meetingIDs, [])

    let speech = try #require(result.evidence[1].details.recording)
    expectNoDifference(speech.authorizationStatus, .authorized)
    expectNoDifference(speech.loadedSoundEffectFileName, "ding.wav")
    expectNoDifference(speech.speechResultCount, 2)
    expectNoDifference(speech.transcript, "Reviewed launch risks. Final notes.")
    expectNoDifference(speech.soundEffectPlayCount, 0)

    let advance = try #require(result.evidence[2].details.recording)
    expectNoDifference(result.evidence[2].details.tickEvent, "advancedSpeaker")
    expectNoDifference(advance.secondsElapsed, 1)
    expectNoDifference(advance.speakerIndex, 1)
    expectNoDifference(advance.currentSpeakerName, "Blob Jr")
    expectNoDifference(advance.soundEffectPlayCount, 1)

    let finish = try #require(result.evidence[3].details.recording)
    expectNoDifference(result.evidence[3].details.tickEvent, "finished")
    expectNoDifference(finish.meetingID, "meeting-validation")
    expectNoDifference(finish.secondsElapsed, 2)
    expectNoDifference(finish.isDismissed, true)

    let saved = result.evidence[4].details
    expectNoDifference(saved.meetingIDs, ["meeting-validation"])
    expectNoDifference(saved.meetingTranscripts, ["Reviewed launch risks. Final notes."])

    let settings = result.evidence[5].details
    let deniedRecording = try #require(settings.recording)
    expectNoDifference(deniedRecording.authorizationStatus, .denied)
    expectNoDifference(deniedRecording.alert, .speechRecognitionDenied)
    expectNoDifference(settings.alertOutcome, .settingsOpened)
    expectNoDifference(settings.openSettingsCount, 1)

    let relaunch = result.evidence[6].details
    expectNoDifference(relaunch.meetingIDs, ["meeting-validation"])
    expectNoDifference(relaunch.meetingTranscripts, ["Reviewed launch risks. Final notes."])
    expectNoDifference(relaunch.recording?.meetingID, "meeting-validation")
  }

  @Test
  func syncUpsExampleSharedRootRolesProtectChildren() async throws {
    let cacheURL = try temporaryCacheURL()
    let timestamp = InstantTimestamp(milliseconds: 1_700_000_000_000)
    let syncUpID = "syncup-shared"
    let attendeeID = "attendee-owner"
    let ownerRuntime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "app-a",
        persistenceURL: cacheURL,
        initialAttributes: SyncUpsExample.attributes,
        now: { timestamp }
      )
    )
    _ = try await ownerRuntime.signInWithRefreshToken("owner-refresh", userID: "user-1")
    try await ownerRuntime.transact(
      InstantStoreTransaction(
        id: "tx-owner-syncup",
        operations: SyncUpsExample.createSyncUpOperations(
          id: syncUpID,
          title: "Design",
          seconds: 900,
          theme: .appOrange,
          updatedAt: timestamp,
          transactionID: "tx-owner-syncup"
        )
          + SyncUpsExample.createAttendeeOperations(
            id: attendeeID,
            syncUpID: syncUpID,
            name: "Blob",
            updatedAt: timestamp,
            transactionID: "tx-owner-syncup"
          )
      ),
      createdAt: timestamp
    )
    let createdShare = try await ownerRuntime.createShare(
      rootNamespace: SyncUpsExample.syncUpsNamespace,
      rootID: syncUpID
    )

    let inviteeRuntime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "app-a",
        persistenceURL: cacheURL,
        initialAttributes: SyncUpsExample.attributes,
        now: { timestamp }
      )
    )
    _ = try await inviteeRuntime.signInWithRefreshToken("invitee-refresh", userID: "user-2")
    let accepted = try await inviteeRuntime.acceptShare(token: createdShare.share.token)
    expectNoDifference(accepted.memberships.map(\.role), [.owner, .reader])

    do {
      try await inviteeRuntime.transact(
        InstantStoreTransaction(
          id: "tx-reader-edit-syncup",
          operations: SyncUpsExample.updateSyncUpOperations(
            id: syncUpID,
            title: "Reader Design",
            seconds: 900,
            theme: .appOrange,
            updatedAt: timestamp,
            transactionID: "tx-reader-edit-syncup"
          )
        ),
        createdAt: timestamp
      )
      #expect(Bool(false), "Expected reader sync-up edit to fail.")
    } catch let error as InstantError {
      expectNoDifference(error.code, .permissionRejected)
      expectNoDifference(error.operation, "write shared root")
      expectNoDifference(error.namespace, SyncUpsExample.syncUpsNamespace)
      expectNoDifference(error.localID, syncUpID)
    } catch {
      #expect(Bool(false), "Unexpected error: \(error)")
    }

    do {
      try await inviteeRuntime.transact(
        InstantStoreTransaction(
          id: "tx-reader-attendee",
          operations: SyncUpsExample.createAttendeeOperations(
            id: "attendee-reader",
            syncUpID: syncUpID,
            name: "Reader",
            updatedAt: timestamp,
            transactionID: "tx-reader-attendee"
          )
        ),
        createdAt: timestamp
      )
      #expect(Bool(false), "Expected reader attendee creation to fail.")
    } catch let error as InstantError {
      expectNoDifference(error.code, .permissionRejected)
      expectNoDifference(error.operation, "write shared root")
      expectNoDifference(error.namespace, SyncUpsExample.syncUpsNamespace)
      expectNoDifference(error.localID, syncUpID)
    } catch {
      #expect(Bool(false), "Unexpected error: \(error)")
    }

    do {
      try await inviteeRuntime.transact(
        InstantStoreTransaction(
          id: "tx-reader-meeting",
          operations: SyncUpsExample.recordMeetingOperations(
            id: "meeting-reader",
            syncUpID: syncUpID,
            transcript: "Reader transcript",
            date: timestamp,
            transactionID: "tx-reader-meeting"
          )
        ),
        createdAt: timestamp
      )
      #expect(Bool(false), "Expected reader meeting record to fail.")
    } catch let error as InstantError {
      expectNoDifference(error.code, .permissionRejected)
      expectNoDifference(error.operation, "write shared root")
      expectNoDifference(error.namespace, SyncUpsExample.syncUpsNamespace)
      expectNoDifference(error.localID, syncUpID)
    } catch {
      #expect(Bool(false), "Unexpected error: \(error)")
    }

    _ = try await ownerRuntime.signInWithRefreshToken("owner-refresh", userID: "user-1")
    let promoted = try await ownerRuntime.updateShareMembershipRole(
      shareID: createdShare.share.id,
      userID: "user-2",
      role: .writer
    )
    expectNoDifference(promoted.memberships.map(\.role), [.owner, .writer])
    _ = try await inviteeRuntime.signInWithRefreshToken("invitee-refresh", userID: "user-2")
    try await inviteeRuntime.transact(
      InstantStoreTransaction(
        id: "tx-writer-syncup",
        operations: SyncUpsExample.updateSyncUpOperations(
          id: syncUpID,
          title: "Writer Design",
          seconds: 1_200,
          theme: .periwinkle,
          updatedAt: timestamp,
          transactionID: "tx-writer-syncup"
        )
          + SyncUpsExample.recordMeetingOperations(
            id: "meeting-writer",
            syncUpID: syncUpID,
            transcript: "Writer transcript",
            date: timestamp,
            transactionID: "tx-writer-syncup"
          )
      ),
      createdAt: timestamp
    )

    _ = try await ownerRuntime.signInWithRefreshToken("owner-refresh", userID: "user-1")
    let demoted = try await ownerRuntime.updateShareMembershipRole(
      shareID: createdShare.share.id,
      userID: "user-2",
      role: .reader
    )
    expectNoDifference(demoted.memberships.map(\.role), [.owner, .reader])
    _ = try await inviteeRuntime.signInWithRefreshToken("invitee-refresh", userID: "user-2")
    do {
      try await inviteeRuntime.transact(
        InstantStoreTransaction(
          id: "tx-demoted-attendee",
          operations: SyncUpsExample.createAttendeeOperations(
            id: "attendee-demoted",
            syncUpID: syncUpID,
            name: "Demoted",
            updatedAt: timestamp,
            transactionID: "tx-demoted-attendee"
          )
        ),
        createdAt: timestamp
      )
      #expect(Bool(false), "Expected demoted reader attendee creation to fail.")
    } catch let error as InstantError {
      expectNoDifference(error.code, .permissionRejected)
      expectNoDifference(error.operation, "write shared root")
      expectNoDifference(error.namespace, SyncUpsExample.syncUpsNamespace)
      expectNoDifference(error.localID, syncUpID)
    } catch {
      #expect(Bool(false), "Unexpected error: \(error)")
    }

    let finalSyncUps = try SyncUpsExample.decodeSyncUps(
      (try await inviteeRuntime.queryOnce(SyncUpsExample.syncUpsQuery)).values
    )
    let finalMeetings = try SyncUpsExample.decodeMeetings(
      (try await inviteeRuntime.queryOnce(SyncUpsExample.meetingsForSyncUpQuery(syncUpID))).values
    )
    expectNoDifference(finalSyncUps.map(\.title), ["Writer Design"])
    expectNoDifference(finalMeetings.map(\.transcript), ["Writer transcript"])
  }

  @Test
  func sharedRootWritePermissionsRejectReadersBeforeOutboxPersistence() async throws {
    let cacheURL = try temporaryCacheURL()
    let timestamp = InstantTimestamp(milliseconds: 1_700_000_000_000)
    let todoID = "todo-shared"
    let ownerRuntime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "app-a",
        persistenceURL: cacheURL,
        initialAttributes: TodoExample.attributes,
        now: { timestamp }
      )
    )
    _ = try await ownerRuntime.signInWithRefreshToken("owner-refresh", userID: "user-1")

    try await ownerRuntime.transact(
      InstantStoreTransaction(
        id: "tx-owner-create",
        operations: TodoExample.createOperations(
          id: todoID,
          text: "owner created",
          createdAt: timestamp,
          transactionID: "tx-owner-create"
        )
      ),
      createdAt: timestamp
    )
    let createdShare = try await ownerRuntime.createShare(
      rootNamespace: TodoExample.namespace,
      rootID: todoID
    )
    try await ownerRuntime.transact(
      InstantStoreTransaction(
        id: "tx-owner-update",
        operations: TodoExample.updateTextOperations(
          id: todoID,
          text: "owner updated",
          updatedAt: timestamp,
          transactionID: "tx-owner-update"
        )
      ),
      createdAt: timestamp
    )

    let inviteeRuntime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "app-a",
        persistenceURL: cacheURL,
        initialAttributes: TodoExample.attributes,
        now: { timestamp }
      )
    )
    _ = try await inviteeRuntime.signInWithRefreshToken("invitee-refresh", userID: "user-2")
    let acceptedShare = try await inviteeRuntime.acceptShare(token: createdShare.share.token)
    expectNoDifference(acceptedShare.memberships.map(\.role), [.owner, .reader])
    do {
      _ = try await inviteeRuntime.createShare(rootNamespace: TodoExample.namespace, rootID: todoID)
      #expect(Bool(false), "Expected reader duplicate share creation to fail.")
    } catch let error as InstantError {
      expectNoDifference(error.code, .permissionRejected)
      expectNoDifference(error.operation, "create share")
      #expect(error.message.contains("cannot create a share"))
    } catch {
      #expect(Bool(false), "Unexpected error: \(error)")
    }
    let inviteeShares = try await inviteeRuntime.shares()
    expectNoDifference(inviteeShares.map(\.share.id), [createdShare.share.id])

    let pendingBeforeReaderWrite = await inviteeRuntime.pendingMutations()
    do {
      try await inviteeRuntime.transact(
        InstantStoreTransaction(
          id: "tx-owner-update",
          operations: TodoExample.updateTextOperations(
            id: todoID,
            text: "owner updated",
            updatedAt: timestamp,
            transactionID: "tx-owner-update"
          )
        ),
        createdAt: timestamp
      )
      #expect(Bool(false), "Expected reader replay of a pending owner write to fail.")
    } catch let error as InstantError {
      expectNoDifference(error.code, .permissionRejected)
      expectNoDifference(error.operation, "write shared root")
      #expect(error.message.contains("reader access"))
    } catch {
      #expect(Bool(false), "Unexpected error: \(error)")
    }
    let pendingAfterReaderReplay = await inviteeRuntime.pendingMutations()
    expectNoDifference(pendingAfterReaderReplay, pendingBeforeReaderWrite)

    do {
      try await inviteeRuntime.transact(
        InstantStoreTransaction(
          id: "tx-reader-update",
          operations: TodoExample.updateTextOperations(
            id: todoID,
            text: "reader updated",
            updatedAt: timestamp,
            transactionID: "tx-reader-update"
          )
        ),
        createdAt: timestamp
      )
      #expect(Bool(false), "Expected reader write to a shared root to fail.")
    } catch let error as InstantError {
      expectNoDifference(error.code, .permissionRejected)
      expectNoDifference(error.operation, "write shared root")
      expectNoDifference(error.namespace, TodoExample.namespace)
      expectNoDifference(error.localID, todoID)
      #expect(error.message.contains("reader access"))
    } catch {
      #expect(Bool(false), "Unexpected error: \(error)")
    }
    let pendingAfterReaderUpdate = await inviteeRuntime.pendingMutations()
    expectNoDifference(pendingAfterReaderUpdate, pendingBeforeReaderWrite)

    do {
      try await inviteeRuntime.transact(
        InstantStoreTransaction(
          id: "tx-reader-delete",
          operations: TodoExample.deleteOperations(id: todoID)
        ),
        createdAt: timestamp
      )
      #expect(Bool(false), "Expected reader delete of a shared root to fail.")
    } catch let error as InstantError {
      expectNoDifference(error.code, .permissionRejected)
      expectNoDifference(error.operation, "write shared root")
      expectNoDifference(error.namespace, TodoExample.namespace)
      expectNoDifference(error.localID, todoID)
      #expect(error.message.contains("reader access"))
    } catch {
      #expect(Bool(false), "Unexpected error: \(error)")
    }
    let pendingAfterReaderDelete = await inviteeRuntime.pendingMutations()
    expectNoDifference(pendingAfterReaderDelete, pendingBeforeReaderWrite)

    do {
      try await inviteeRuntime.transact(
        InstantStoreTransaction(
          id: "tx-reader-rogue-attribute",
          operations: [
            .insert(
              InstantTriple(
                entityID: todoID,
                attributeID: "todos/rogue",
                value: .string("reader bypass"),
                txID: "tx-reader-rogue-attribute",
                txTime: timestamp
              )
            )
          ]
        ),
        createdAt: timestamp
      )
      #expect(Bool(false), "Expected reader undeclared-attribute write to fail.")
    } catch let error as InstantError {
      expectNoDifference(error.code, .permissionRejected)
      expectNoDifference(error.operation, "write shared root")
      expectNoDifference(error.namespace, TodoExample.namespace)
      expectNoDifference(error.localID, todoID)
      #expect(error.message.contains("reader access"))
    } catch {
      #expect(Bool(false), "Unexpected error: \(error)")
    }
    let pendingAfterReaderRogueAttribute = await inviteeRuntime.pendingMutations()
    expectNoDifference(pendingAfterReaderRogueAttribute, pendingBeforeReaderWrite)

    let todosAfterReaderAttempts = try TodoExample.decode(
      (try await inviteeRuntime.queryOnce(TodoExample.query)).values
    )
    expectNoDifference(todosAfterReaderAttempts.map(\.text), ["owner updated"])

    _ = try await ownerRuntime.signInWithRefreshToken("owner-refresh", userID: "user-1")
    let promoted = try await ownerRuntime.updateShareMembershipRole(
      shareID: createdShare.share.id,
      userID: "user-2",
      role: .writer
    )
    expectNoDifference(promoted.memberships.map(\.role), [.owner, .writer])
    _ = try await inviteeRuntime.signInWithRefreshToken("invitee-refresh", userID: "user-2")
    do {
      _ = try await inviteeRuntime.createShare(rootNamespace: TodoExample.namespace, rootID: todoID)
      #expect(Bool(false), "Expected writer duplicate share creation to fail.")
    } catch let error as InstantError {
      expectNoDifference(error.code, .permissionRejected)
      expectNoDifference(error.operation, "create share")
      #expect(error.message.contains("cannot create a share"))
    } catch {
      #expect(Bool(false), "Unexpected error: \(error)")
    }
    let pendingBeforeWriterUpdate = await inviteeRuntime.pendingMutations()
    try await inviteeRuntime.transact(
      InstantStoreTransaction(
        id: "tx-writer-update",
        operations: TodoExample.updateTextOperations(
          id: todoID,
          text: "writer updated",
          updatedAt: timestamp,
          transactionID: "tx-writer-update"
        )
      ),
      createdAt: timestamp
    )
    let todosAfterWriterUpdate = try TodoExample.decode(
      (try await inviteeRuntime.queryOnce(TodoExample.query)).values
    )
    expectNoDifference(todosAfterWriterUpdate.map(\.text), ["writer updated"])
    let pendingAfterWriterUpdate = await inviteeRuntime.pendingMutations()
    expectNoDifference(pendingAfterWriterUpdate.count, pendingBeforeWriterUpdate.count + 1)

    _ = try await ownerRuntime.signInWithRefreshToken("owner-refresh", userID: "user-1")
    let demoted = try await ownerRuntime.updateShareMembershipRole(
      shareID: createdShare.share.id,
      userID: "user-2",
      role: .reader
    )
    expectNoDifference(demoted.memberships.map(\.role), [.owner, .reader])
    _ = try await inviteeRuntime.signInWithRefreshToken("invitee-refresh", userID: "user-2")
    do {
      try await inviteeRuntime.transact(
        InstantStoreTransaction(
          id: "tx-reader-update-after-demotion",
          operations: TodoExample.updateTextOperations(
            id: todoID,
            text: "reader after demotion",
            updatedAt: timestamp,
            transactionID: "tx-reader-update-after-demotion"
          )
        ),
        createdAt: timestamp
      )
      #expect(Bool(false), "Expected demoted reader write to fail.")
    } catch let error as InstantError {
      expectNoDifference(error.code, .permissionRejected)
      expectNoDifference(error.operation, "write shared root")
      #expect(error.message.contains("reader access"))
    } catch {
      #expect(Bool(false), "Unexpected error: \(error)")
    }

    let nonMemberRuntime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "app-a",
        persistenceURL: cacheURL,
        initialAttributes: TodoExample.attributes,
        now: { timestamp }
      )
    )
    _ = try await nonMemberRuntime.signInWithRefreshToken("other-refresh", userID: "user-3")
    do {
      try await nonMemberRuntime.transact(
        InstantStoreTransaction(
          id: "tx-non-member-update",
          operations: TodoExample.updateTextOperations(
            id: todoID,
            text: "non-member updated",
            updatedAt: timestamp,
            transactionID: "tx-non-member-update"
          )
        ),
        createdAt: timestamp
      )
      #expect(Bool(false), "Expected non-member write to a shared root to fail.")
    } catch let error as InstantError {
      expectNoDifference(error.code, .permissionRejected)
      expectNoDifference(error.operation, "write shared root")
      #expect(error.message.contains("not a member"))
    } catch {
      #expect(Bool(false), "Unexpected error: \(error)")
    }
    let pendingAfterNonMemberWrite = await nonMemberRuntime.pendingMutations()
    #expect(!pendingAfterNonMemberWrite.map(\.id).contains("tx-non-member-update"))
  }

  @Test
  func sharedRootWritePermissionsRejectReaderRefTargetMutation() async throws {
    let cacheURL = try temporaryCacheURL()
    let timestamp = InstantTimestamp(milliseconds: 1_700_000_000_000)
    let projectID = "project-shared"
    let todoID = "todo-source"
    let ownerRuntime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "app-a",
        persistenceURL: cacheURL,
        initialAttributes: TodoProjectExample.attributes,
        now: { timestamp }
      )
    )
    _ = try await ownerRuntime.signInWithRefreshToken("owner-refresh", userID: "user-1")
    try await ownerRuntime.transact(
      InstantStoreTransaction(
        id: "tx-owner-project",
        operations: TodoProjectExample.createProjectOperations(
          id: projectID,
          title: "Shared project",
          createdAt: timestamp,
          transactionID: "tx-owner-project"
        )
      ),
      createdAt: timestamp
    )
    let share = try await ownerRuntime.createShare(
      rootNamespace: TodoProjectExample.namespace,
      rootID: projectID
    )
    let remoteProjectID = "remote-project-shared"
    let remoteShare = try await ownerRuntime.createShare(
      rootNamespace: TodoProjectExample.namespace,
      rootID: remoteProjectID
    )

    let inviteeRuntime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "app-a",
        persistenceURL: cacheURL,
        initialAttributes: TodoProjectExample.attributes,
        now: { timestamp }
      )
    )
    _ = try await inviteeRuntime.signInWithRefreshToken("invitee-refresh", userID: "user-2")
    _ = try await inviteeRuntime.acceptShare(token: share.share.token)
    _ = try await inviteeRuntime.acceptShare(token: remoteShare.share.token)
    try await inviteeRuntime.transact(
      InstantStoreTransaction(
        id: "tx-reader-create-source",
        operations: TodoExample.createOperations(
          id: todoID,
          text: "reader source",
          createdAt: timestamp,
          transactionID: "tx-reader-create-source"
        )
      ),
      createdAt: timestamp
    )
    let pendingBeforeLink = await inviteeRuntime.pendingMutations()

    do {
      try await inviteeRuntime.transact(
        InstantStoreTransaction(
          id: "tx-reader-link-shared-project",
          operations: TodoProjectExample.linkOperations(
            todoID: todoID,
            projectID: projectID,
            updatedAt: timestamp,
            transactionID: "tx-reader-link-shared-project"
          )
        ),
        createdAt: timestamp
      )
      #expect(Bool(false), "Expected reader ref target write to a shared root to fail.")
    } catch let error as InstantError {
      expectNoDifference(error.code, .permissionRejected)
      expectNoDifference(error.operation, "write shared root")
      expectNoDifference(error.namespace, TodoProjectExample.namespace)
      expectNoDifference(error.localID, projectID)
      #expect(error.message.contains("reader access"))
    } catch {
      #expect(Bool(false), "Unexpected error: \(error)")
    }
    let pendingAfterLink = await inviteeRuntime.pendingMutations()
    expectNoDifference(pendingAfterLink, pendingBeforeLink)

    let missingTodoLookup = InstantLookupRef(
      attributeID: InstantAttribute.primaryKeyID(namespace: TodoExample.namespace),
      value: .string("missing-source")
    )
    do {
      try await inviteeRuntime.transact(
        InstantStoreTransaction(
          id: "tx-reader-link-missing-source",
          operations: [
            .insertByLookup(
              entity: missingTodoLookup,
              attributeID: "todos/project",
              value: .ref(projectID),
              txID: "tx-reader-link-missing-source",
              txTime: timestamp
            )
          ]
        ),
        createdAt: timestamp
      )
      #expect(Bool(false), "Expected unresolved source lookup with a shared ref target to fail.")
    } catch let error as InstantError {
      expectNoDifference(error.code, .permissionRejected)
      expectNoDifference(error.operation, "write shared root")
      expectNoDifference(error.namespace, TodoProjectExample.namespace)
      expectNoDifference(error.localID, projectID)
      #expect(error.message.contains("reader access"))
    } catch {
      #expect(Bool(false), "Unexpected error: \(error)")
    }
    let pendingAfterMissingSourceLink = await inviteeRuntime.pendingMutations()
    expectNoDifference(pendingAfterMissingSourceLink, pendingBeforeLink)

    let remoteProjectLookup = InstantLookupRef(
      attributeID: InstantAttribute.primaryKeyID(namespace: TodoProjectExample.namespace),
      value: .string(remoteProjectID)
    )
    do {
      try await inviteeRuntime.transact(
        InstantStoreTransaction(
          id: "tx-reader-link-remote-target-lookup",
          operations: [
            .insert(
              InstantTriple(
                entityID: todoID,
                attributeID: "todos/project",
                value: .lookupRef(remoteProjectLookup),
                txID: "tx-reader-link-remote-target-lookup",
                txTime: timestamp
              )
            )
          ]
        ),
        createdAt: timestamp
      )
      #expect(Bool(false), "Expected unresolved shared target lookup to fail.")
    } catch let error as InstantError {
      expectNoDifference(error.code, .permissionRejected)
      expectNoDifference(error.operation, "write shared root")
      expectNoDifference(error.namespace, TodoProjectExample.namespace)
      expectNoDifference(error.localID, remoteProjectID)
      #expect(error.message.contains("reader access"))
    } catch {
      #expect(Bool(false), "Unexpected error: \(error)")
    }
    let pendingAfterRemoteTargetLookup = await inviteeRuntime.pendingMutations()
    expectNoDifference(pendingAfterRemoteTargetLookup, pendingBeforeLink)

    let linkedTodos = try TodoProjectExample.decodeLinkedTodos(
      (try await inviteeRuntime.queryOnce(TodoProjectExample.todosQuery)).values
    )
    expectNoDifference(linkedTodos.map(\.projectID), [nil])
  }

  @Test
  func sharedRootWritePermissionsRejectReaderCascadeDeleteTarget() async throws {
    let cacheURL = try temporaryCacheURL()
    let timestamp = InstantTimestamp(milliseconds: 1_700_000_000_000)
    let taskNamespace = "tasks"
    let taskID = "task-source"
    let projectID = "project-shared"
    let attributes = TodoProjectExample.attributes + [
      .primaryKey(namespace: taskNamespace),
      InstantAttribute(
        id: "tasks/title",
        namespace: taskNamespace,
        name: "title",
        valueType: .string,
        isIndexed: true
      ),
      InstantAttribute(
        id: "tasks/project",
        namespace: taskNamespace,
        name: "project",
        valueType: .ref,
        isIndexed: true,
        linkNamespace: TodoProjectExample.namespace,
        onDeleteReverse: .cascade
      ),
    ]
    let ownerRuntime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "app-a",
        persistenceURL: cacheURL,
        initialAttributes: attributes,
        now: { timestamp }
      )
    )
    _ = try await ownerRuntime.signInWithRefreshToken("owner-refresh", userID: "user-1")
    try await ownerRuntime.transact(
      InstantStoreTransaction(
        id: "tx-owner-project-and-task",
        operations: TodoProjectExample.createProjectOperations(
          id: projectID,
          title: "Shared project",
          createdAt: timestamp,
          transactionID: "tx-owner-project-and-task"
        ) + [
          .insert(
            InstantTriple(
              entityID: taskID,
              attributeID: InstantAttribute.primaryKeyID(namespace: taskNamespace),
              value: .string(taskID),
              txID: "tx-owner-project-and-task",
              txTime: timestamp
            )
          ),
          .insert(
            InstantTriple(
              entityID: taskID,
              attributeID: "tasks/title",
              value: .string("Source task"),
              txID: "tx-owner-project-and-task",
              txTime: timestamp
            )
          ),
          .insert(
            InstantTriple(
              entityID: taskID,
              attributeID: "tasks/project",
              value: .ref(projectID),
              txID: "tx-owner-project-and-task",
              txTime: timestamp
            )
          ),
        ]
      ),
      createdAt: timestamp
    )
    let share = try await ownerRuntime.createShare(
      rootNamespace: TodoProjectExample.namespace,
      rootID: projectID
    )

    let inviteeRuntime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "app-a",
        persistenceURL: cacheURL,
        initialAttributes: attributes,
        now: { timestamp }
      )
    )
    _ = try await inviteeRuntime.signInWithRefreshToken("invitee-refresh", userID: "user-2")
    _ = try await inviteeRuntime.acceptShare(token: share.share.token)
    let pendingBeforeDelete = await inviteeRuntime.pendingMutations()

    do {
      try await inviteeRuntime.transact(
        InstantStoreTransaction(
          id: "tx-reader-delete-cascade-source",
          operations: [.deleteEntity(taskID)]
        ),
        createdAt: timestamp
      )
      #expect(Bool(false), "Expected reader cascade delete into a shared root to fail.")
    } catch let error as InstantError {
      expectNoDifference(error.code, .permissionRejected)
      expectNoDifference(error.operation, "write shared root")
      expectNoDifference(error.namespace, TodoProjectExample.namespace)
      expectNoDifference(error.localID, projectID)
      #expect(error.message.contains("reader access"))
    } catch {
      #expect(Bool(false), "Unexpected error: \(error)")
    }
    let pendingAfterDelete = await inviteeRuntime.pendingMutations()
    expectNoDifference(pendingAfterDelete, pendingBeforeDelete)

    let projects = try TodoProjectExample.decodeProjects(
      (try await inviteeRuntime.queryOnce(TodoProjectExample.projectsQuery)).values
    )
    expectNoDifference(projects.map(\.id), [projectID])
  }

  @Test
  func shareCreateRequiresAuth() async throws {
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(appID: "test-app", persistenceURL: temporaryCacheURL())
    )

    do {
      _ = try await runtime.createShare(rootNamespace: "remindersLists", rootID: "list-1")
      #expect(Bool(false), "Expected anonymous share create to fail.")
    } catch let error as InstantError {
      expectNoDifference(error.code, .authFailed)
      expectNoDifference(error.operation, "create share")
    } catch {
      #expect(Bool(false), "Unexpected error: \(error)")
    }
  }

  @Test
  func authRecipeExampleDerivesDashboardStateFromMagicCodeSessions() {
    let timestamp = InstantTimestamp(milliseconds: 1_700_000_000_000)
    let session = InstantAuthSession(
      appID: "app-a",
      userID: "email:user@example.com",
      refreshToken: "local-magic:app-a:user@example.com",
      isGuest: false,
      createdAt: timestamp,
      updatedAt: timestamp
    )

    expectNoDifference(AuthRecipeExample.recipeSlug, "auth")
    expectNoDifference(AuthRecipeExample.userEmail(from: session), "user@example.com")
    expectNoDifference(AuthRecipeExample.isDashboardVisible(for: session), true)
    expectNoDifference(AuthRecipeExample.isLoginVisible(for: session), false)
    expectNoDifference(AuthRecipeExample.isEmailEntryVisible(session: session, challenge: nil), false)
    expectNoDifference(AuthRecipeExample.isCodeEntryVisible(session: session, challenge: nil), false)
    expectNoDifference(AuthRecipeExample.userEmail(from: nil), nil)
    expectNoDifference(AuthRecipeExample.isDashboardVisible(for: nil), false)
    expectNoDifference(AuthRecipeExample.isLoginVisible(for: nil), true)
    expectNoDifference(AuthRecipeExample.isEmailEntryVisible(session: nil, challenge: nil), true)
    expectNoDifference(
      AuthRecipeExample.isCodeEntryVisible(
        session: nil,
        challenge: InstantMagicCodeChallenge(
          appID: "app-a",
          email: "user@example.com",
          code: "123456",
          createdAt: timestamp,
          expiresAt: timestamp
        )
      ),
      true
    )
  }

  @Test
  func appBuilderExampleCreatesUpdatesAndQueriesOwnerBuilds() async throws {
    let cacheURL = try temporaryCacheURL()
    let now = InstantTimestamp(milliseconds: 1_700_000_000_000)
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "app-builder-test",
        persistenceURL: cacheURL,
        initialAttributes: AppBuilderExample.attributes,
        now: { now }
      )
    )

    let platformApp = try await InstantPlatformAppClient.local.createApp(
      InstantPlatformAppCreateRequest(
        title: "Build a workout tracker",
        orgID: "org-1",
        createdAt: now,
        makeID: { "build-1" }
      )
    )
    expectNoDifference(
      platformApp,
      InstantPlatformApp(
        id: "local-platform-build-1",
        title: "Build a workout tracker",
        orgID: "org-1",
        createdAt: now
      )
    )

    let fileAttribute = try #require(
      AppBuilderExample.attributes.first { $0.id == "builds/file" }
    )
    expectNoDifference(fileAttribute.valueType, .ref)
    expectNoDifference(fileAttribute.linkNamespace, AppBuilderExample.filesNamespace)
    expectNoDifference(fileAttribute.forwardIdentity, "builds/file")
    expectNoDifference(fileAttribute.reverseIdentity, "$files/builds")

    try await runtime.transact(
      InstantStoreTransaction(
        id: "tx-create",
        operations: AppBuilderExample.createBuildOperations(
          id: "build-1",
          ownerID: "email:user@example.com",
          ownerEmail: "user@example.com",
          instantAppID: platformApp.id,
          title: AppBuilderExample.friendlyTitle(for: "Build a workout tracker"),
          createdAt: now,
          transactionID: "tx-create"
        )
      ),
      createdAt: now,
      source: "test.app-builder.create"
    )

    let stream = try await AppBuilderCodeGeneratorClient.local.generate(
      AppBuilderGenerationRequest(
        prompt: "Build a workout tracker",
        buildID: "build-1",
        instantAppID: platformApp.id
      )
    )
    var iterator = stream.makeAsyncIterator()
    var code = ""
    var reasoning = ""
    while let chunk = try await iterator.next() {
      switch chunk.kind {
      case .code:
        code += chunk.text
      case .reasoning:
        reasoning += chunk.text
      }
    }

    _ = try await runtime.signInWithRefreshToken(
      "builder-refresh",
      userID: "email:user@example.com"
    )
    let codeSourceURL = cacheURL.deletingLastPathComponent()
      .appendingPathComponent(AppBuilderExample.generatedCodeFileName(buildID: "build-1"))
    try Data(code.utf8).write(to: codeSourceURL)
    let uploadedFile = try await runtime.uploadFile(
      from: codeSourceURL,
      name: AppBuilderExample.generatedCodeFileName(buildID: "build-1"),
      contentType: AppBuilderExample.generatedCodeContentType
    )

    try await runtime.transact(
      InstantStoreTransaction(
        id: "tx-update",
        operations: AppBuilderExample.updateBuildOperations(
          id: "build-1",
          code: code,
          reasoning: reasoning,
          isPreviewable: true,
          fileID: uploadedFile.id,
          updatedAt: now,
          transactionID: "tx-update"
        )
      ),
      createdAt: now,
      source: "test.app-builder.update"
    )

    let ownerBuilds = try AppBuilderExample.decodeBuilds(
      (
        try await runtime.queryOnce(
          AppBuilderExample.buildsForOwnerQuery("email:user@example.com")
        )
      )
      .values
    )
    expectNoDifference(ownerBuilds.count, 1)
    let build = try #require(ownerBuilds.first)
    expectNoDifference(build.id, "build-1")
    expectNoDifference(build.instantAppID, "local-platform-build-1")
    expectNoDifference(build.ownerID, "email:user@example.com")
    expectNoDifference(build.title, "Build a workout tracker")
    expectNoDifference(build.isPreviewable, true)
    expectNoDifference(build.fileID, uploadedFile.id)
    #expect(build.reasoning?.contains("Create a compact Swift-friendly preview") == true)
    #expect(build.code.contains("local-platform-build-1"))
    let contents = try await runtime.storedFileContents(id: uploadedFile.id)
    expectNoDifference(contents.file.name, AppBuilderExample.generatedCodeFileName(buildID: "build-1"))
    expectNoDifference(contents.file.contentType, AppBuilderExample.generatedCodeContentType)
    expectNoDifference(contents.file.ownerUserID, "email:user@example.com")
    expectNoDifference(contents.data, Data(code.utf8))

    let detailBuilds = try AppBuilderExample.decodeBuilds(
      (try await runtime.queryOnce(AppBuilderExample.buildQuery("build-1"))).values
    )
    expectNoDifference(detailBuilds, ownerBuilds)

    let otherOwnerBuilds = try AppBuilderExample.decodeBuilds(
      (try await runtime.queryOnce(AppBuilderExample.buildsForOwnerQuery("email:other@example.com")))
        .values
    )
    expectNoDifference(otherOwnerBuilds, [])
  }

  @Test
  func magicCodeChallengePersistsAndVerifiesAcrossLaunches() async throws {
    let cacheURL = try temporaryCacheURL()
    let sentAt = InstantTimestamp(milliseconds: 1_700_000_000_000)
    let verifiedAt = InstantTimestamp(milliseconds: sentAt.milliseconds + 1_000)
    let senderRuntime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "app-a",
        persistenceURL: cacheURL,
        now: { sentAt },
        makeID: { "123456" }
      )
    )

    let challenge = try await senderRuntime.sendMagicCode(email: " User@Example.COM ")
    expectNoDifference(
      challenge,
      InstantMagicCodeChallenge(
        appID: "app-a",
        email: "user@example.com",
        code: "123456",
        createdAt: sentAt,
        expiresAt: InstantTimestamp(milliseconds: sentAt.milliseconds + 600_000)
      )
    )

    let otherAppRuntime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(appID: "app-b", persistenceURL: cacheURL)
    )
    do {
      _ = try await otherAppRuntime.signInWithMagicCode(email: "user@example.com", code: "123456")
      #expect(Bool(false), "Expected app-scoped magic code verification to fail.")
    } catch let error as InstantError {
      expectNoDifference(error.code, .authFailed)
      expectNoDifference(error.operation, "sign in with magic code")
    } catch {
      #expect(Bool(false), "Unexpected error: \(error)")
    }

    let verifierRuntime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "app-a",
        persistenceURL: cacheURL,
        now: { verifiedAt }
      )
    )
    let session = try await verifierRuntime.signInWithMagicCode(
      email: "USER@example.com",
      code: " 123456 "
    )
    expectNoDifference(
      session,
      InstantAuthSession(
        appID: "app-a",
        userID: "email:user@example.com",
        refreshToken: "local-magic:app-a:user@example.com",
        isGuest: false,
        createdAt: verifiedAt,
        updatedAt: verifiedAt
      )
    )
    let persistedSession = try await verifierRuntime.authSession()
    expectNoDifference(persistedSession, session)

    do {
      _ = try await verifierRuntime.signInWithMagicCode(email: "user@example.com", code: "123456")
      #expect(Bool(false), "Expected one-time magic code verification to fail after use.")
    } catch let error as InstantError {
      expectNoDifference(error.code, .authFailed)
    } catch {
      #expect(Bool(false), "Unexpected error: \(error)")
    }
  }

  @Test
  func idTokenSignInUsesExchangeAndPersistsSession() async throws {
    let cacheURL = try temporaryCacheURL()
    let signedInAt = InstantTimestamp(milliseconds: 1_700_000_000_000)
    let exchange = InstantIDTokenExchange(
      signIn: { request in
        InstantIDTokenVerification(
          userID:
            "dependency:\(request.appID):\(request.clientName):\(request.idToken):\(request.nonce ?? "nil")",
          refreshToken: "id-token-refresh:\(request.signedInAt.milliseconds)"
        )
      }
    )
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "app-a",
        persistenceURL: cacheURL,
        now: { signedInAt },
        idTokenExchange: exchange
      )
    )

    let session = try await runtime.signInWithIDToken(
      clientName: " google-ios ",
      idToken: " jwt-token ",
      nonce: " nonce-1 "
    )
    expectNoDifference(
      session,
      InstantAuthSession(
        appID: "app-a",
        userID: "dependency:app-a:google-ios:jwt-token: nonce-1 ",
        refreshToken: "id-token-refresh:1700000000000",
        isGuest: false,
        createdAt: signedInAt,
        updatedAt: signedInAt
      )
    )

    let relaunchedRuntime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(appID: "app-a", persistenceURL: cacheURL)
    )
    let persistedSession = try await relaunchedRuntime.authSession()
    expectNoDifference(persistedSession, session)
  }

  @Test
  func oauthSignInUsesExchangeRefreshTokenAndPersistsSession() async throws {
    let cacheURL = try temporaryCacheURL()
    let signedInAt = InstantTimestamp(milliseconds: 1_700_000_000_000)
    let exchange = InstantOAuthExchange(
      signIn: { request in
        InstantOAuthVerification(
          userID:
            "dependency:\(request.appID):\(request.code):\(request.codeVerifier ?? "nil"):\(request.refreshToken ?? "nil")",
          refreshToken: "oauth-refresh:\(request.signedInAt.milliseconds)"
        )
      }
    )
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "app-a",
        persistenceURL: cacheURL,
        now: { signedInAt },
        oauthExchange: exchange
      )
    )

    _ = try await runtime.signInWithRefreshToken(" existing-refresh ", userID: "existing-user")
    let session = try await runtime.signInWithOAuth(
      code: " oauth-code ",
      codeVerifier: " verifier with spaces "
    )
    expectNoDifference(
      session,
      InstantAuthSession(
        appID: "app-a",
        userID: "dependency:app-a:oauth-code: verifier with spaces :existing-refresh",
        refreshToken: "oauth-refresh:1700000000000",
        isGuest: false,
        createdAt: signedInAt,
        updatedAt: signedInAt
      )
    )

    let relaunchedRuntime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(appID: "app-a", persistenceURL: cacheURL)
    )
    let persistedSession = try await relaunchedRuntime.authSession()
    expectNoDifference(persistedSession, session)
  }

  @Test
  func invalidIDTokenInputsFailWithAuthError() async throws {
    let cacheURL = try temporaryCacheURL()
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(appID: "test-app", persistenceURL: cacheURL)
    )

    do {
      _ = try await runtime.signInWithIDToken(clientName: " ", idToken: "token")
      #expect(Bool(false), "Expected empty ID token client name to fail.")
    } catch let error as InstantError {
      expectNoDifference(error.code, .authFailed)
      expectNoDifference(error.operation, "sign in with id token")
      #expect(error.description.contains("Client name must not be empty"))
    } catch {
      #expect(Bool(false), "Unexpected error: \(error)")
    }

    do {
      _ = try await runtime.signInWithIDToken(clientName: "google-ios", idToken: " ")
      #expect(Bool(false), "Expected empty ID token to fail.")
    } catch let error as InstantError {
      expectNoDifference(error.code, .authFailed)
      expectNoDifference(error.operation, "sign in with id token")
      #expect(error.description.contains("ID token must not be empty"))
    } catch {
      #expect(Bool(false), "Unexpected error: \(error)")
    }
  }

  @Test
  func invalidOAuthInputsFailWithAuthError() async throws {
    let cacheURL = try temporaryCacheURL()
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(appID: "test-app", persistenceURL: cacheURL)
    )

    do {
      _ = try await runtime.signInWithOAuth(code: " ")
      #expect(Bool(false), "Expected empty OAuth code to fail.")
    } catch let error as InstantError {
      expectNoDifference(error.code, .authFailed)
      expectNoDifference(error.operation, "sign in with oauth")
      #expect(error.description.contains("OAuth authorization code must not be empty"))
    } catch {
      #expect(Bool(false), "Unexpected error: \(error)")
    }
  }

  @Test
  func invalidMagicCodeInputsFailWithAuthError() async throws {
    let cacheURL = try temporaryCacheURL()
    let sentAt = InstantTimestamp(milliseconds: 1_700_000_000_000)
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "test-app",
        persistenceURL: cacheURL,
        now: { sentAt },
        makeID: { "654321" }
      )
    )

    do {
      _ = try await runtime.sendMagicCode(email: "not-an-email")
      #expect(Bool(false), "Expected invalid email to fail.")
    } catch let error as InstantError {
      expectNoDifference(error.code, .authFailed)
      expectNoDifference(error.operation, "send magic code")
    } catch {
      #expect(Bool(false), "Unexpected error: \(error)")
    }

    _ = try await runtime.sendMagicCode(email: "user@example.com")
    do {
      _ = try await runtime.signInWithMagicCode(email: "user@example.com", code: "000000")
      #expect(Bool(false), "Expected wrong code to fail.")
    } catch let error as InstantError {
      expectNoDifference(error.code, .authFailed)
      expectNoDifference(error.operation, "sign in with magic code")
    } catch {
      #expect(Bool(false), "Unexpected error: \(error)")
    }

    let expiredRuntime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "test-app",
        persistenceURL: cacheURL,
        now: { InstantTimestamp(milliseconds: sentAt.milliseconds + 600_001) }
      )
    )
    do {
      _ = try await expiredRuntime.signInWithMagicCode(email: "user@example.com", code: "654321")
      #expect(Bool(false), "Expected expired code to fail.")
    } catch let error as InstantError {
      expectNoDifference(error.code, .authFailed)
      expectNoDifference(error.operation, "sign in with magic code")
    } catch {
      #expect(Bool(false), "Unexpected error: \(error)")
    }
  }

  @Test
  func emptyTokenSignInFailsWithAuthError() async throws {
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(appID: "test-app", persistenceURL: temporaryCacheURL())
    )

    do {
      _ = try await runtime.signInWithRefreshToken("  ")
      #expect(Bool(false), "Expected empty token sign-in to fail.")
    } catch let error as InstantError {
      expectNoDifference(error.code, .authFailed)
      expectNoDifference(error.operation, "sign in with token")
    } catch {
      #expect(Bool(false), "Unexpected error: \(error)")
    }
  }

  @Test
  func selectedAppIDPersistsAcrossLaunches() async throws {
    let cacheURL = try temporaryCacheURL()
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(appID: "app-a", persistenceURL: cacheURL)
    )

    let selected = try await runtime.saveSelectedAppID(" app-b ")
    expectNoDifference(selected, "app-b")

    let relaunchedRuntime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(appID: "app-c", persistenceURL: cacheURL)
    )
    let relaunchedSelected = try await relaunchedRuntime.selectedAppID()
    expectNoDifference(relaunchedSelected, "app-b")
  }

  @Test
  func processedTransactionCheckpointPersistsAcrossLaunches() async throws {
    let cacheURL = try temporaryCacheURL()
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(appID: "app-a", persistenceURL: cacheURL)
    )

    let initialState = try await runtime.syncState()
    expectNoDifference(initialState, InstantSyncState())

    let updatedState = try await runtime.markProcessedTransaction(id: " tx-processed ")
    expectNoDifference(
      updatedState,
      InstantSyncState(processedTransactionID: "tx-processed")
    )

    let otherAppRuntime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(appID: "app-b", persistenceURL: cacheURL)
    )
    let otherInitialState = try await otherAppRuntime.syncState()
    expectNoDifference(otherInitialState, InstantSyncState())
    let otherUpdatedState = try await otherAppRuntime.markProcessedTransaction(id: "tx-other")
    expectNoDifference(
      otherUpdatedState,
      InstantSyncState(processedTransactionID: "tx-other")
    )

    let relaunchedRuntime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(appID: "app-a", persistenceURL: cacheURL)
    )
    let relaunchedState = try await relaunchedRuntime.syncState()
    expectNoDifference(
      relaunchedState,
      InstantSyncState(processedTransactionID: "tx-processed")
    )

    let otherRelaunchedRuntime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(appID: "app-b", persistenceURL: cacheURL)
    )
    let otherRelaunchedState = try await otherRelaunchedRuntime.syncState()
    expectNoDifference(
      otherRelaunchedState,
      InstantSyncState(processedTransactionID: "tx-other")
    )
  }

  @Test
  func connectionStatusReflectsLocalTransportAuthAndOutbox() async throws {
    let cacheURL = try temporaryCacheURL()
    let createdAt = InstantTimestamp(milliseconds: 1_700_000_000_000)
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "status-app",
        apiURI: try #require(URL(string: "https://api.example.test")),
        websocketURI: try #require(URL(string: "wss://socket.example.test/runtime/session")),
        persistenceURL: cacheURL,
        initialAttributes: TodoExample.attributes
      )
    )

    let initialStatus = try await runtime.connectionStatus()
    expectNoDifference(initialStatus.appID, "status-app")
    expectNoDifference(initialStatus.apiURI.absoluteString, "https://api.example.test")
    expectNoDifference(
      initialStatus.websocketURI.absoluteString,
      "wss://socket.example.test/runtime/session"
    )
    expectNoDifference(initialStatus.transport, .localCacheOnly)
    expectNoDifference(initialStatus.state, .opened)
    expectNoDifference(initialStatus.isAuthenticated, false)
    expectNoDifference(initialStatus.userID, nil)
    expectNoDifference(initialStatus.pendingMutationCount, 0)
    expectNoDifference(initialStatus.processedTransactionID, nil)
    expectNoDifference(initialStatus.lastErrorMessage, nil)

    let closedStatus = try await runtime.closeConnection()
    expectNoDifference(closedStatus.state, .closed)
    expectNoDifference(closedStatus.isAuthenticated, false)
    expectNoDifference(closedStatus.pendingMutationCount, 0)
    let statusAfterClose = try await runtime.connectionStatus()
    expectNoDifference(statusAfterClose.state, .closed)
    expectNoDifference(statusAfterClose.isAuthenticated, false)

    let reconnectedStatus = try await runtime.connect()
    expectNoDifference(reconnectedStatus.state, .opened)
    expectNoDifference(reconnectedStatus.isAuthenticated, false)
    let statusAfterReconnect = try await runtime.connectionStatus()
    expectNoDifference(statusAfterReconnect.state, .opened)
    expectNoDifference(statusAfterReconnect.isAuthenticated, false)

    let session = try await runtime.signInAsGuest()
    try await runtime.transact(
      InstantStoreTransaction(
        id: "tx-status",
        operations: TodoExample.createOperations(
          id: "todo-status",
          text: "status",
          createdAt: createdAt,
          transactionID: "tx-status"
        )
      ),
      createdAt: createdAt
    )
    _ = try await runtime.markProcessedTransaction(id: "tx-remote")

    let authenticatedStatus = try await runtime.connectionStatus()
    expectNoDifference(authenticatedStatus.state, .authenticated)
    expectNoDifference(authenticatedStatus.isAuthenticated, true)
    expectNoDifference(authenticatedStatus.userID, session.userID)
    expectNoDifference(authenticatedStatus.pendingMutationCount, 1)
    expectNoDifference(authenticatedStatus.processedTransactionID, "tx-remote")

    let closedAuthenticatedStatus = try await runtime.closeConnection()
    expectNoDifference(closedAuthenticatedStatus.state, .closed)
    expectNoDifference(closedAuthenticatedStatus.isAuthenticated, true)
    expectNoDifference(closedAuthenticatedStatus.userID, session.userID)
    expectNoDifference(closedAuthenticatedStatus.pendingMutationCount, 1)
    let authenticatedStatusAfterClose = try await runtime.connectionStatus()
    expectNoDifference(authenticatedStatusAfterClose.state, .closed)
    expectNoDifference(authenticatedStatusAfterClose.isAuthenticated, true)
    expectNoDifference(authenticatedStatusAfterClose.userID, session.userID)

    let reconnectedAuthenticatedStatus = try await runtime.connect()
    expectNoDifference(reconnectedAuthenticatedStatus.state, .authenticated)
    expectNoDifference(reconnectedAuthenticatedStatus.isAuthenticated, true)
    expectNoDifference(reconnectedAuthenticatedStatus.userID, session.userID)
    let authenticatedStatusAfterReconnect = try await runtime.connectionStatus()
    expectNoDifference(authenticatedStatusAfterReconnect.state, .authenticated)
    expectNoDifference(authenticatedStatusAfterReconnect.isAuthenticated, true)
    expectNoDifference(authenticatedStatusAfterReconnect.userID, session.userID)

    let relaunchedRuntime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "status-app",
        persistenceURL: cacheURL,
        initialAttributes: TodoExample.attributes
      )
    )
    let relaunchedStatus = try await relaunchedRuntime.connectionStatus()
    expectNoDifference(relaunchedStatus.state, .authenticated)
    expectNoDifference(relaunchedStatus.userID, session.userID)
    expectNoDifference(relaunchedStatus.pendingMutationCount, 1)
    expectNoDifference(relaunchedStatus.processedTransactionID, "tx-remote")
  }

  @Test
  func automaticReconnectFailureRemainsRetryableAcrossRelaunchAndFlushesOfflineOutbox()
    async throws
  {
    let cacheURL = try temporaryCacheURL()
    let reconnectSleepCalls = LockIsolated(0)
    var offlineConfiguration = InstantRuntimeConfiguration(
      appID: "offline-relaunch-app",
      persistenceURL: cacheURL,
      initialAttributes: TodoExample.attributes,
      liveTransport: InstantLiveTransportClient { _ in
        throw InstantError(
          code: .networkFailed,
          operation: "open test live session",
          message: "The test network is offline.",
          recovery: "Relaunch with a reachable transport."
        )
      }
    )
    offlineConfiguration.autoConnectLiveTransport = true
    offlineConfiguration.liveReconnectSleep = { _ in
      reconnectSleepCalls.withValue { $0 += 1 }
      throw CancellationError()
    }
    let offlineRuntime = try await InstantRuntime.bootstrap(configuration: offlineConfiguration)

    for _ in 0..<100 where reconnectSleepCalls.withValue({ $0 }) == 0 {
      try await Task.sleep(nanoseconds: 10_000_000)
    }
    expectNoDifference(reconnectSleepCalls.withValue { $0 }, 1)
    let offlineStatus = try await offlineRuntime.connectionStatus()
    expectNoDifference(offlineStatus.state, .errored)
    #expect(offlineStatus.lastErrorMessage?.contains("test network is offline") == true)

    let createdAt = InstantTimestamp(milliseconds: 1_700_000_000_000)
    try await offlineRuntime.transact(
      InstantStoreTransaction(
        id: "tx-created-offline",
        operations: TodoExample.createOperations(
          id: "todo-created-offline",
          text: "flush after relaunch",
          createdAt: createdAt,
          transactionID: "tx-created-offline"
        )
      ),
      createdAt: createdAt
    )
    let offlinePendingIDs = await offlineRuntime.pendingMutations().map(\.id)
    expectNoDifference(offlinePendingIDs, ["tx-created-offline"])

    let onlineSession = PersistentTestLiveSession(appID: "offline-relaunch-app")
    var onlineConfiguration = InstantRuntimeConfiguration(
      appID: "offline-relaunch-app",
      persistenceURL: cacheURL,
      initialAttributes: TodoExample.attributes,
      liveTransport: InstantLiveTransportClient { _ in
        InstantLiveWebSocketSession(
          send: { message in await onlineSession.send(message) },
          receive: { try await onlineSession.receive() },
          close: { await onlineSession.close() }
        )
      }
    )
    onlineConfiguration.autoConnectLiveTransport = true
    let relaunchedRuntime = try await InstantRuntime.bootstrap(configuration: onlineConfiguration)

    var reconnectedStatus = try await relaunchedRuntime.connectionStatus()
    for _ in 0..<100 where
      reconnectedStatus.state != .opened || reconnectedStatus.pendingMutationCount != 0
    {
      try await Task.sleep(nanoseconds: 10_000_000)
      reconnectedStatus = try await relaunchedRuntime.connectionStatus()
    }
    expectNoDifference(reconnectedStatus.state, .opened)
    expectNoDifference(reconnectedStatus.pendingMutationCount, 0)
    expectNoDifference(reconnectedStatus.lastErrorMessage, nil)
    let relaunchedPending = await relaunchedRuntime.pendingMutations()
    expectNoDifference(relaunchedPending, [])
    let relaunchedTodos = try await TodoExample.decode(
      relaunchedRuntime.query(TodoExample.query)
    )
    expectNoDifference(
      relaunchedTodos.map(\.text),
      ["flush after relaunch"]
    )
  }

  @Test
  func observeConnectionStatusPublishesRuntimeStatusChanges() async throws {
    let cacheURL = try temporaryCacheURL()
    let baseTime = InstantTimestamp(milliseconds: 1_700_000_000_000)
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "observed-status-app",
        persistenceURL: cacheURL,
        initialAttributes: TodoExample.attributes
      )
    )
    let recorder = ConnectionStatusRecorder()
    let stream = try await runtime.observeConnectionStatus()
    let observationTask = Task {
      for await status in stream {
        await recorder.append(status)
      }
    }
    defer { observationTask.cancel() }
    var statusCursor = 0

    let initialResult = try await requireObservedConnectionStatus(
      recorder,
      after: statusCursor,
      operation: "observe connection status initial value"
    ) { $0.pendingMutationCount == 0 && $0.processedTransactionID == nil }
    statusCursor = initialResult.nextIndex
    let initial = initialResult.status
    expectNoDifference(initial.state, .opened)
    expectNoDifference(initial.pendingMutationCount, 0)
    expectNoDifference(initial.processedTransactionID, nil)
    expectNoDifference(initial.lastErrorMessage, nil)

    try await runtime.transact(
      InstantStoreTransaction(
        id: "tx-observed-status-1",
        operations: TodoExample.createOperations(
          id: "todo-observed-status-1",
          text: "observe status 1",
          createdAt: baseTime,
          transactionID: "tx-observed-status-1"
        )
      ),
      createdAt: baseTime
    )
    let pendingResult = try await requireObservedConnectionStatus(
      recorder,
      after: statusCursor,
      operation: "observe connection status pending mutation"
    ) { $0.pendingMutationCount == 1 && $0.processedTransactionID == nil }
    statusCursor = pendingResult.nextIndex
    let pending = pendingResult.status
    expectNoDifference(pending.state, .opened)
    expectNoDifference(pending.pendingMutationCount, 1)

    _ = try await runtime.markProcessedTransaction(id: "tx-remote-observed")
    let checkpointResult = try await requireObservedConnectionStatus(
      recorder,
      after: statusCursor,
      operation: "observe connection status processed checkpoint"
    ) { $0.processedTransactionID == "tx-remote-observed" }
    statusCursor = checkpointResult.nextIndex
    let checkpoint = checkpointResult.status
    expectNoDifference(checkpoint.pendingMutationCount, 1)
    expectNoDifference(checkpoint.processedTransactionID, "tx-remote-observed")

    _ = try await runtime.failMutation(id: "tx-observed-status-1", message: "server rejected")
    let failedResult = try await requireObservedConnectionStatus(
      recorder,
      after: statusCursor,
      operation: "observe connection status failed mutation"
    ) { $0.state == .errored && $0.lastErrorMessage == "server rejected" }
    statusCursor = failedResult.nextIndex
    let failed = failedResult.status
    expectNoDifference(failed.state, .errored)
    expectNoDifference(failed.pendingMutationCount, 0)
    expectNoDifference(failed.lastErrorMessage, "server rejected")

    _ = try await runtime.retryMutation(id: "tx-observed-status-1")
    let retriedResult = try await requireObservedConnectionStatus(
      recorder,
      after: statusCursor,
      operation: "observe connection status retried mutation"
    ) { $0.state == .opened && $0.pendingMutationCount == 1 && $0.lastErrorMessage == nil }
    statusCursor = retriedResult.nextIndex
    let retried = retriedResult.status
    expectNoDifference(retried.state, .opened)
    expectNoDifference(retried.pendingMutationCount, 1)
    expectNoDifference(retried.lastErrorMessage, nil)

    _ = try await runtime.confirmMutation(id: "tx-observed-status-1")
    let confirmedResult = try await requireObservedConnectionStatus(
      recorder,
      after: statusCursor,
      operation: "observe connection status confirmed mutation"
    ) { $0.pendingMutationCount == 0 && $0.processedTransactionID == "tx-remote-observed" }
    statusCursor = confirmedResult.nextIndex
    let confirmed = confirmedResult.status
    expectNoDifference(confirmed.pendingMutationCount, 0)
    expectNoDifference(confirmed.processedTransactionID, "tx-remote-observed")

    try await runtime.transact(
      InstantStoreTransaction(
        id: "tx-observed-status-2",
        operations: TodoExample.createOperations(
          id: "todo-observed-status-2",
          text: "observe status 2",
          createdAt: InstantTimestamp(milliseconds: baseTime.milliseconds + 1),
          transactionID: "tx-observed-status-2"
        )
      ),
      createdAt: InstantTimestamp(milliseconds: baseTime.milliseconds + 1)
    )
    let secondPendingResult = try await requireObservedConnectionStatus(
      recorder,
      after: statusCursor,
      operation: "observe connection status second pending mutation"
    ) { $0.pendingMutationCount == 1 && $0.processedTransactionID == "tx-remote-observed" }
    statusCursor = secondPendingResult.nextIndex
    let secondPending = secondPendingResult.status
    expectNoDifference(secondPending.pendingMutationCount, 1)

    _ = try await runtime.drainPendingMutationsLocally(limit: 1)
    let drainedResult = try await requireObservedConnectionStatus(
      recorder,
      after: statusCursor,
      operation: "observe connection status local drain"
    ) { $0.pendingMutationCount == 0 && $0.processedTransactionID == "tx-remote-observed" }
    statusCursor = drainedResult.nextIndex
    let drained = drainedResult.status
    expectNoDifference(drained.pendingMutationCount, 0)

    _ = try await runtime.applyServerTransaction(
      InstantStoreTransaction(id: "tx-server-observed", operations: [])
    )
    let serverAppliedResult = try await requireObservedConnectionStatus(
      recorder,
      after: statusCursor,
      operation: "observe connection status server apply"
    ) { $0.processedTransactionID == "tx-server-observed" }
    statusCursor = serverAppliedResult.nextIndex
    let serverApplied = serverAppliedResult.status
    expectNoDifference(serverApplied.processedTransactionID, "tx-server-observed")
    expectNoDifference(serverApplied.pendingMutationCount, 0)

    try await runtime.transact(
      InstantStoreTransaction(
        id: "tx-observed-status-kept-failure",
        operations: TodoExample.createOperations(
          id: "todo-observed-status-kept-failure",
          text: "kept failure",
          createdAt: InstantTimestamp(milliseconds: baseTime.milliseconds + 2),
          transactionID: "tx-observed-status-kept-failure"
        )
      ),
      createdAt: InstantTimestamp(milliseconds: baseTime.milliseconds + 2)
    )
    let failingPendingResult = try await requireObservedConnectionStatus(
      recorder,
      after: statusCursor,
      operation: "observe connection status pending mutation before kept failure"
    ) { $0.pendingMutationCount == 1 && $0.processedTransactionID == "tx-server-observed" }
    statusCursor = failingPendingResult.nextIndex
    expectNoDifference(failingPendingResult.status.pendingMutationCount, 1)

    _ = try await runtime.failMutation(
      id: "tx-observed-status-kept-failure",
      message: "kept failure"
    )
    let keptFailureResult = try await requireObservedConnectionStatus(
      recorder,
      after: statusCursor,
      operation: "observe connection status kept failed mutation"
    ) { $0.state == .errored && $0.lastErrorMessage == "kept failure" }
    statusCursor = keptFailureResult.nextIndex
    expectNoDifference(keptFailureResult.status.pendingMutationCount, 0)

    try await runtime.transact(
      InstantStoreTransaction(
        id: "tx-observed-status-flush",
        operations: TodoExample.createOperations(
          id: "todo-observed-status-flush",
          text: "flush while failed remains",
          createdAt: InstantTimestamp(milliseconds: baseTime.milliseconds + 3),
          transactionID: "tx-observed-status-flush"
        )
      ),
      createdAt: InstantTimestamp(milliseconds: baseTime.milliseconds + 3)
    )
    let flushPendingResult = try await requireObservedConnectionStatus(
      recorder,
      after: statusCursor,
      operation: "observe connection status pending flush with kept failure"
    ) { $0.state == .errored && $0.pendingMutationCount == 1 }
    statusCursor = flushPendingResult.nextIndex
    expectNoDifference(flushPendingResult.status.lastErrorMessage, "kept failure")

    _ = try await runtime.flushPendingMutations()
    let flushedResult = try await requireObservedConnectionStatus(
      recorder,
      after: statusCursor,
      operation: "observe connection status flushed pending with kept failure"
    ) { $0.state == .errored && $0.pendingMutationCount == 0 }
    expectNoDifference(flushedResult.status.lastErrorMessage, "kept failure")
  }

  @Test
  func concurrentOutboxCleanupAndTransactionPersistAcrossLaunches() async throws {
    let cacheURL = try temporaryCacheURL()
    let createdAt = InstantTimestamp(milliseconds: 1_700_000_000_000)
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "test-app",
        persistenceURL: cacheURL,
        initialAttributes: TodoExample.attributes
      )
    )

    try await runtime.transact(
      InstantStoreTransaction(
        id: "tx-confirm",
        operations: TodoExample.createOperations(
          id: "todo-confirm",
          text: "confirm me",
          createdAt: createdAt,
          transactionID: "tx-confirm"
        )
      ),
      createdAt: createdAt
    )

    try await withThrowingTaskGroup(of: Void.self) { group in
      group.addTask {
        _ = try await runtime.confirmMutation(id: "tx-confirm")
      }
      group.addTask {
        let newCreatedAt = InstantTimestamp(milliseconds: createdAt.milliseconds + 1)
        try await runtime.transact(
          InstantStoreTransaction(
            id: "tx-new",
            operations: TodoExample.createOperations(
              id: "todo-new",
              text: "new transaction",
              createdAt: newCreatedAt,
              transactionID: "tx-new"
            )
          ),
          createdAt: newCreatedAt
        )
      }
      try await group.waitForAll()
    }

    let relaunchedRuntime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "test-app",
        persistenceURL: cacheURL,
        initialAttributes: TodoExample.attributes
      )
    )
    let mutations = await relaunchedRuntime.outboxMutations()
    let pending = await relaunchedRuntime.pendingMutations()

    expectNoDifference(mutations.map(\.id), ["tx-new"])
    expectNoDifference(mutations.map(\.status), [.pending])
    expectNoDifference(pending.map(\.id), ["tx-new"])
  }

  @Test
  func staleRuntimeOutboxConfirmationPreservesNewerPersistedMutation() async throws {
    let cacheURL = try temporaryCacheURL()
    let createdAt = InstantTimestamp(milliseconds: 1_700_000_000_000)
    let writerRuntime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "test-app",
        persistenceURL: cacheURL,
        initialAttributes: TodoExample.attributes
      )
    )
    try await writerRuntime.transact(
      InstantStoreTransaction(
        id: "tx-confirm",
        operations: TodoExample.createOperations(
          id: "todo-confirm",
          text: "confirm me",
          createdAt: createdAt,
          transactionID: "tx-confirm"
        )
      ),
      createdAt: createdAt
    )

    let staleRuntime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "test-app",
        persistenceURL: cacheURL,
        initialAttributes: TodoExample.attributes
      )
    )
    let newerCreatedAt = InstantTimestamp(milliseconds: createdAt.milliseconds + 1)
    try await writerRuntime.transact(
      InstantStoreTransaction(
        id: "tx-new",
        operations: TodoExample.createOperations(
          id: "todo-new",
          text: "newer mutation",
          createdAt: newerCreatedAt,
          transactionID: "tx-new"
        )
      ),
      createdAt: newerCreatedAt
    )

    let confirmed = try await staleRuntime.confirmMutation(id: "tx-confirm")
    expectNoDifference(confirmed.status, .confirmed)

    let relaunchedRuntime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "test-app",
        persistenceURL: cacheURL,
        initialAttributes: TodoExample.attributes
      )
    )
    let mutations = await relaunchedRuntime.outboxMutations()
    expectNoDifference(mutations.map(\.id), ["tx-new"])
    expectNoDifference(mutations.map(\.status), [.pending])
  }

  @Test
  func staleRuntimeOutboxFailurePreservesNewerPersistedMutation() async throws {
    let cacheURL = try temporaryCacheURL()
    let createdAt = InstantTimestamp(milliseconds: 1_700_000_000_000)
    let writerRuntime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "test-app",
        persistenceURL: cacheURL,
        initialAttributes: TodoExample.attributes
      )
    )
    try await writerRuntime.transact(
      InstantStoreTransaction(
        id: "tx-fail",
        operations: TodoExample.createOperations(
          id: "todo-fail",
          text: "fail me",
          createdAt: createdAt,
          transactionID: "tx-fail"
        )
      ),
      createdAt: createdAt
    )

    let staleRuntime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "test-app",
        persistenceURL: cacheURL,
        initialAttributes: TodoExample.attributes
      )
    )
    let newerCreatedAt = InstantTimestamp(milliseconds: createdAt.milliseconds + 1)
    try await writerRuntime.transact(
      InstantStoreTransaction(
        id: "tx-new",
        operations: TodoExample.createOperations(
          id: "todo-new",
          text: "newer mutation",
          createdAt: newerCreatedAt,
          transactionID: "tx-new"
        )
      ),
      createdAt: newerCreatedAt
    )

    let failed = try await staleRuntime.failMutation(id: "tx-fail", message: "server rejected")
    expectNoDifference(failed.status, .failed)
    expectNoDifference(failed.failureMessage, "server rejected")

    let relaunchedRuntime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "test-app",
        persistenceURL: cacheURL,
        initialAttributes: TodoExample.attributes
      )
    )
    let mutations = await relaunchedRuntime.outboxMutations()
    expectNoDifference(mutations.map(\.id), ["tx-fail", "tx-new"])
    expectNoDifference(mutations.map(\.status), [.failed, .pending])
    expectNoDifference(mutations.map(\.failureMessage), ["server rejected", nil])
  }

  @Test
  func outboxStatusUpdatesDoNotInvalidateQueryCacheStoreRevision() async throws {
    let cacheURL = try temporaryCacheURL()
    let createdAt = InstantTimestamp(milliseconds: 1_700_000_000_000)
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "test-app",
        persistenceURL: cacheURL,
        initialAttributes: TodoExample.attributes
      )
    )
    try await runtime.transact(
      InstantStoreTransaction(
        id: "tx-query-revision",
        operations: TodoExample.createOperations(
          id: "todo-query-revision",
          text: "query revision",
          createdAt: createdAt,
          transactionID: "tx-query-revision"
        )
      ),
      createdAt: createdAt
    )

    let before = try await runtime.persistence.loadState()
    _ = try await runtime.confirmMutation(id: "tx-query-revision")
    let after = try await runtime.persistence.loadState()

    expectNoDifference(after.storeRevision, before.storeRevision)
    #expect(after.outboxRevision > before.outboxRevision)
  }

  @Test
  func staleRuntimeMissingOutboxTargetRefreshesBeforeFutureTransactions() async throws {
    let cacheURL = try temporaryCacheURL()
    let createdAt = InstantTimestamp(milliseconds: 1_700_000_000_000)
    let writerRuntime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "test-app",
        persistenceURL: cacheURL,
        initialAttributes: TodoExample.attributes
      )
    )
    try await writerRuntime.transact(
      InstantStoreTransaction(
        id: "tx-confirmed-elsewhere",
        operations: TodoExample.createOperations(
          id: "todo-confirmed-elsewhere",
          text: "confirmed elsewhere",
          createdAt: createdAt,
          transactionID: "tx-confirmed-elsewhere"
        )
      ),
      createdAt: createdAt
    )

    let staleRuntime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "test-app",
        persistenceURL: cacheURL,
        initialAttributes: TodoExample.attributes
      )
    )
    _ = try await writerRuntime.confirmMutation(id: "tx-confirmed-elsewhere")

    do {
      _ = try await staleRuntime.confirmMutation(id: "tx-confirmed-elsewhere")
      #expect(Bool(false), "Expected stale confirm to fail after another runtime cleaned it up.")
    } catch let error as InstantError {
      expectNoDifference(error.code, .validationFailed)
      expectNoDifference(error.operation, "update outbox mutation")
      expectNoDifference(error.localID, "tx-confirmed-elsewhere")
    } catch {
      #expect(Bool(false), "Unexpected error: \(error)")
    }

    let newCreatedAt = InstantTimestamp(milliseconds: createdAt.milliseconds + 1)
    try await staleRuntime.transact(
      InstantStoreTransaction(
        id: "tx-after-refresh",
        operations: TodoExample.createOperations(
          id: "todo-after-refresh",
          text: "after refresh",
          createdAt: newCreatedAt,
          transactionID: "tx-after-refresh"
        )
      ),
      createdAt: newCreatedAt
    )

    let relaunchedRuntime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "test-app",
        persistenceURL: cacheURL,
        initialAttributes: TodoExample.attributes
      )
    )
    let mutations = await relaunchedRuntime.outboxMutations()
    expectNoDifference(mutations.map(\.id), ["tx-after-refresh"])
    expectNoDifference(mutations.map(\.status), [.pending])
  }

  @Test
  func staleRuntimeTransactionDoesNotResurrectConfirmedMutation() async throws {
    let cacheURL = try temporaryCacheURL()
    let createdAt = InstantTimestamp(milliseconds: 1_700_000_000_000)
    let writerRuntime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "test-app",
        persistenceURL: cacheURL,
        initialAttributes: TodoExample.attributes
      )
    )
    try await writerRuntime.transact(
      InstantStoreTransaction(
        id: "tx-confirmed-elsewhere",
        operations: TodoExample.createOperations(
          id: "todo-confirmed-elsewhere",
          text: "confirmed elsewhere",
          createdAt: createdAt,
          transactionID: "tx-confirmed-elsewhere"
        )
      ),
      createdAt: createdAt
    )

    let staleRuntime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "test-app",
        persistenceURL: cacheURL,
        initialAttributes: TodoExample.attributes
      )
    )
    _ = try await writerRuntime.confirmMutation(id: "tx-confirmed-elsewhere")

    let newCreatedAt = InstantTimestamp(milliseconds: createdAt.milliseconds + 1)
    try await staleRuntime.transact(
      InstantStoreTransaction(
        id: "tx-after-stale",
        operations: TodoExample.createOperations(
          id: "todo-after-stale",
          text: "after stale",
          createdAt: newCreatedAt,
          transactionID: "tx-after-stale"
        )
      ),
      createdAt: newCreatedAt
    )

    let relaunchedRuntime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "test-app",
        persistenceURL: cacheURL,
        initialAttributes: TodoExample.attributes
      )
    )
    let mutations = await relaunchedRuntime.outboxMutations()
    expectNoDifference(mutations.map(\.id), ["tx-after-stale"])

    let todos = try await TodoExample.decode(relaunchedRuntime.query(TodoExample.query))
    expectNoDifference(todos.map(\.id), ["todo-confirmed-elsewhere", "todo-after-stale"])
  }

  @Test
  func staleRuntimeTransactionPreservesNewerPersistedStoreAndOutbox() async throws {
    let cacheURL = try temporaryCacheURL()
    let createdAt = InstantTimestamp(milliseconds: 1_700_000_000_000)
    let writerRuntime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "test-app",
        persistenceURL: cacheURL,
        initialAttributes: TodoExample.attributes
      )
    )
    try await writerRuntime.transact(
      InstantStoreTransaction(
        id: "tx-base",
        operations: TodoExample.createOperations(
          id: "todo-base",
          text: "base",
          createdAt: createdAt,
          transactionID: "tx-base"
        )
      ),
      createdAt: createdAt
    )

    let staleRuntime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "test-app",
        persistenceURL: cacheURL,
        initialAttributes: TodoExample.attributes
      )
    )
    let newerCreatedAt = InstantTimestamp(milliseconds: createdAt.milliseconds + 1)
    try await writerRuntime.transact(
      InstantStoreTransaction(
        id: "tx-newer",
        operations: TodoExample.createOperations(
          id: "todo-newer",
          text: "newer",
          createdAt: newerCreatedAt,
          transactionID: "tx-newer"
        )
      ),
      createdAt: newerCreatedAt
    )

    let staleCreatedAt = InstantTimestamp(milliseconds: createdAt.milliseconds + 2)
    try await staleRuntime.transact(
      InstantStoreTransaction(
        id: "tx-after-stale",
        operations: TodoExample.createOperations(
          id: "todo-after-stale",
          text: "after stale",
          createdAt: staleCreatedAt,
          transactionID: "tx-after-stale"
        )
      ),
      createdAt: staleCreatedAt
    )

    let relaunchedRuntime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "test-app",
        persistenceURL: cacheURL,
        initialAttributes: TodoExample.attributes
      )
    )
    let mutations = await relaunchedRuntime.outboxMutations()
    expectNoDifference(mutations.map(\.id), ["tx-base", "tx-newer", "tx-after-stale"])

    let todos = try await TodoExample.decode(relaunchedRuntime.query(TodoExample.query))
    expectNoDifference(todos.map(\.id), ["todo-base", "todo-newer", "todo-after-stale"])
  }

  @Test
  func failedTransactionPersistenceDoesNotMutateLiveStore() async throws {
    let cacheURL = try temporaryCacheURL()
    let createdAt = InstantTimestamp(milliseconds: 1_700_000_000_000)
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "test-app",
        persistenceURL: cacheURL,
        initialAttributes: TodoExample.attributes
      )
    )
    try await runtime.transact(
      InstantStoreTransaction(
        id: "tx-seed",
        operations: TodoExample.createOperations(
          id: "todo-seed",
          text: "seed",
          createdAt: createdAt,
          transactionID: "tx-seed"
        )
      ),
      createdAt: createdAt
    )
    try dropOutboxTable(at: cacheURL)

    do {
      let failedCreatedAt = InstantTimestamp(milliseconds: createdAt.milliseconds + 1)
      try await runtime.transact(
        InstantStoreTransaction(
          id: "tx-failed",
          operations: TodoExample.createOperations(
            id: "todo-failed",
            text: "failed",
            createdAt: failedCreatedAt,
            transactionID: "tx-failed"
          )
        ),
        createdAt: failedCreatedAt
      )
      #expect(Bool(false), "Expected failed transaction persistence to throw.")
    } catch let error as InstantError {
      expectNoDifference(error.code, .persistenceFailed)
    } catch {
      #expect(Bool(false), "Unexpected error: \(error)")
    }

    let liveTodos = try TodoExample.decode(await runtime.store.materialize(TodoExample.query))
    expectNoDifference(liveTodos.map(\.id), ["todo-seed"])

    let stream = await runtime.observe(TodoExample.query)
    var iterator = stream.makeAsyncIterator()
    let emission = await iterator.next()
    expectNoDifference(try TodoExample.decode(emission?.values ?? []).map(\.id), ["todo-seed"])
  }

  @Test
  func cardinalityOneRefOverwriteAndReverseDeleteCleanup() async throws {
    let authorAttribute = InstantAttribute(
      id: "posts/author",
      namespace: "posts",
      name: "author",
      valueType: .ref,
      isIndexed: true,
      linkNamespace: "users"
    )
    let titleAttribute = InstantAttribute(
      id: "posts/title",
      namespace: "posts",
      name: "title",
      valueType: .string
    )
    let nameAttribute = InstantAttribute(
      id: "users/name",
      namespace: "users",
      name: "name",
      valueType: .string
    )
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "test-app",
        persistenceURL: temporaryCacheURL(),
        initialAttributes: [authorAttribute, titleAttribute, nameAttribute]
      )
    )
    let time = InstantTimestamp(milliseconds: 10)

    try await runtime.transact(
      InstantStoreTransaction(
        id: "tx-1",
        operations: [
          .insert(.init(entityID: "user-1", attributeID: "users/name", value: .string("Blob"), txID: "tx-1", txTime: time)),
          .insert(.init(entityID: "user-2", attributeID: "users/name", value: .string("Blob Jr."), txID: "tx-1", txTime: time)),
          .insert(.init(entityID: "post-1", attributeID: "posts/title", value: .string("Hello"), txID: "tx-1", txTime: time)),
          .insert(.init(entityID: "post-1", attributeID: "posts/author", value: .ref("user-1"), txID: "tx-1", txTime: time)),
        ]
      ),
      createdAt: time
    )

    try await runtime.transact(
      InstantStoreTransaction(
        id: "tx-2",
        operations: [
          .insert(.init(entityID: "post-1", attributeID: "posts/author", value: .ref("user-2"), txID: "tx-2", txTime: time))
        ]
      ),
      createdAt: time
    )

    let posts = try await runtime.query(.init(id: "posts", namespace: "posts"))
    expectNoDifference(posts.map { $0.values["author"]?.first }, [.ref("user-2")])

    try await runtime.transact(
      InstantStoreTransaction(id: "tx-3", operations: [.deleteEntity("user-2")]),
      createdAt: time
    )

    let cleanedPosts = try await runtime.query(.init(id: "posts", namespace: "posts"))
    expectNoDifference(cleanedPosts.map { $0.values["author"]?.first }, [nil])
    expectNoDifference(cleanedPosts.map { $0.values["title"]?.first }, [.string("Hello")])
  }

  @Test
  func deleteEntityCascadesSourcesWhenForwardEndpointRequestsCascade() async throws {
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "test-app",
        persistenceURL: temporaryCacheURL(),
        initialAttributes: [
          InstantAttribute(
            id: "posts/author",
            namespace: "posts",
            name: "author",
            valueType: .ref,
            isIndexed: true,
            forwardIdentity: "posts/author",
            reverseIdentity: "users/posts",
            linkNamespace: "users",
            onDelete: .cascade
          ),
          InstantAttribute(
            id: "posts/title",
            namespace: "posts",
            name: "title",
            valueType: .string
          ),
          InstantAttribute(
            id: "users/name",
            namespace: "users",
            name: "name",
            valueType: .string
          ),
        ]
      )
    )
    let time = InstantTimestamp(milliseconds: 20)

    try await runtime.transact(
      InstantStoreTransaction(
        id: "tx-cascade-seed",
        operations: [
          .insert(.init(entityID: "user-1", attributeID: "users/name", value: .string("Blob"), txID: "tx-cascade-seed", txTime: time)),
          .insert(.init(entityID: "post-1", attributeID: "posts/title", value: .string("Hello"), txID: "tx-cascade-seed", txTime: time)),
          .insert(.init(entityID: "post-1", attributeID: "posts/author", value: .ref("user-1"), txID: "tx-cascade-seed", txTime: time)),
        ]
      ),
      createdAt: time
    )
    try await runtime.transact(
      InstantStoreTransaction(id: "tx-cascade-delete-user", operations: [.deleteEntity("user-1")]),
      createdAt: InstantTimestamp(milliseconds: time.milliseconds + 1)
    )

    let users = try await runtime.query(.init(id: "cascade.users", namespace: "users"))
    let posts = try await runtime.query(.init(id: "cascade.posts", namespace: "posts"))
    expectNoDifference(users, [])
    expectNoDifference(posts, [])
  }

  @Test
  func deleteEntityCascadesTargetsWhenReverseEndpointRequestsCascade() async throws {
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "test-app",
        persistenceURL: temporaryCacheURL(),
        initialAttributes: [
          InstantAttribute(
            id: "posts/author",
            namespace: "posts",
            name: "author",
            valueType: .ref,
            isIndexed: true,
            forwardIdentity: "posts/author",
            reverseIdentity: "users/posts",
            linkNamespace: "users",
            onDeleteReverse: .cascade
          ),
          InstantAttribute(
            id: "posts/title",
            namespace: "posts",
            name: "title",
            valueType: .string
          ),
          InstantAttribute(
            id: "users/name",
            namespace: "users",
            name: "name",
            valueType: .string
          ),
        ]
      )
    )
    let time = InstantTimestamp(milliseconds: 30)

    try await runtime.transact(
      InstantStoreTransaction(
        id: "tx-reverse-cascade-seed",
        operations: [
          .insert(.init(entityID: "user-1", attributeID: "users/name", value: .string("Blob"), txID: "tx-reverse-cascade-seed", txTime: time)),
          .insert(.init(entityID: "post-1", attributeID: "posts/title", value: .string("Hello"), txID: "tx-reverse-cascade-seed", txTime: time)),
          .insert(.init(entityID: "post-1", attributeID: "posts/author", value: .ref("user-1"), txID: "tx-reverse-cascade-seed", txTime: time)),
        ]
      ),
      createdAt: time
    )
    try await runtime.transact(
      InstantStoreTransaction(id: "tx-reverse-cascade-delete-post", operations: [.deleteEntity("post-1")]),
      createdAt: InstantTimestamp(milliseconds: time.milliseconds + 1)
    )

    let users = try await runtime.query(.init(id: "reverse-cascade.users", namespace: "users"))
    let posts = try await runtime.query(.init(id: "reverse-cascade.posts", namespace: "posts"))
    expectNoDifference(users, [])
    expectNoDifference(posts, [])
  }

  @Test
  func deleteEntityCascadesAcrossRelaunchAndPreservesOriginalPendingMutation() async throws {
    let cacheURL = try temporaryCacheURL()
    let time = InstantTimestamp(milliseconds: 40)
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "test-app",
        persistenceURL: cacheURL,
        initialAttributes: cascadeChainAttributes()
      )
    )

    try await runtime.transact(
      InstantStoreTransaction(
        id: "tx-cascade-chain-seed",
        operations: [
          .insert(.init(entityID: "grandparent-1", attributeID: "grandparents/name", value: .string("Grand"), txID: "tx-cascade-chain-seed", txTime: time)),
          .insert(.init(entityID: "parent-1", attributeID: "parents/name", value: .string("Parent"), txID: "tx-cascade-chain-seed", txTime: time)),
          .insert(.init(entityID: "child-1", attributeID: "children/name", value: .string("Child"), txID: "tx-cascade-chain-seed", txTime: time)),
          .insert(.init(entityID: "parent-1", attributeID: "parents/grandparent", value: .ref("grandparent-1"), txID: "tx-cascade-chain-seed", txTime: time)),
          .insert(.init(entityID: "child-1", attributeID: "children/parent", value: .ref("parent-1"), txID: "tx-cascade-chain-seed", txTime: time)),
        ]
      ),
      createdAt: time
    )
    try await runtime.transact(
      InstantStoreTransaction(
        id: "tx-delete-cascade-chain",
        operations: [.deleteEntity("grandparent-1")]
      ),
      createdAt: InstantTimestamp(milliseconds: time.milliseconds + 1)
    )

    let relaunchedRuntime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "test-app",
        persistenceURL: cacheURL,
        initialAttributes: cascadeChainAttributes()
      )
    )
    let grandparents = try await relaunchedRuntime.query(
      .init(id: "cascade-chain.grandparents", namespace: "grandparents")
    )
    let parents = try await relaunchedRuntime.query(
      .init(id: "cascade-chain.parents", namespace: "parents")
    )
    let children = try await relaunchedRuntime.query(
      .init(id: "cascade-chain.children", namespace: "children")
    )
    let pending = await relaunchedRuntime.pendingMutations()

    expectNoDifference(grandparents, [])
    expectNoDifference(parents, [])
    expectNoDifference(children, [])
    expectNoDifference(pending.map(\.transaction.id), [
      "tx-cascade-chain-seed",
      "tx-delete-cascade-chain",
    ])
    expectNoDifference(pending.last?.transaction.operations, [.deleteEntity("grandparent-1")])
  }

  @Test
  func cyclicCascadeDeletionTerminatesAndRemovesDanglingTriples() async throws {
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "test-app",
        persistenceURL: temporaryCacheURL(),
        initialAttributes: [
          InstantAttribute(
            id: "nodes/name",
            namespace: "nodes",
            name: "name",
            valueType: .string
          ),
          InstantAttribute(
            id: "nodes/next",
            namespace: "nodes",
            name: "next",
            valueType: .ref,
            isIndexed: true,
            forwardIdentity: "nodes/next",
            reverseIdentity: "nodes/previous",
            linkNamespace: "nodes",
            onDelete: .cascade
          ),
        ]
      )
    )
    let time = InstantTimestamp(milliseconds: 50)

    try await runtime.transact(
      InstantStoreTransaction(
        id: "tx-cycle-seed",
        operations: [
          .insert(.init(entityID: "node-1", attributeID: "nodes/name", value: .string("One"), txID: "tx-cycle-seed", txTime: time)),
          .insert(.init(entityID: "node-2", attributeID: "nodes/name", value: .string("Two"), txID: "tx-cycle-seed", txTime: time)),
          .insert(.init(entityID: "node-1", attributeID: "nodes/next", value: .ref("node-2"), txID: "tx-cycle-seed", txTime: time)),
          .insert(.init(entityID: "node-2", attributeID: "nodes/next", value: .ref("node-1"), txID: "tx-cycle-seed", txTime: time)),
        ]
      ),
      createdAt: time
    )
    try await runtime.transact(
      InstantStoreTransaction(id: "tx-cycle-delete", operations: [.deleteEntity("node-1")]),
      createdAt: InstantTimestamp(milliseconds: time.milliseconds + 1)
    )

    let nodes = try await runtime.query(.init(id: "cycle.nodes", namespace: "nodes"))
    expectNoDifference(nodes, [])
  }

  @Test
  func queryIncludesMaterializeForwardAndReverseLinkedSnapshots() async throws {
    let cacheURL = try temporaryCacheURL()
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "test-app",
        persistenceURL: cacheURL,
        initialAttributes: TodoProjectExample.attributes
      )
    )
    let createdAt = InstantTimestamp(milliseconds: 1_700_000_000_000)

    try await runtime.transact(
      InstantStoreTransaction(
        id: "tx-linked-todos",
        operations: TodoProjectExample.createProjectOperations(
          id: "project-1",
          title: "Launch",
          createdAt: createdAt,
          transactionID: "tx-linked-todos"
        ) + TodoExample.createOperations(
          id: "todo-1",
          text: "Wire links",
          createdAt: createdAt,
          transactionID: "tx-linked-todos"
        ) + TodoProjectExample.linkOperations(
          todoID: "todo-1",
          projectID: "project-1",
          updatedAt: createdAt,
          transactionID: "tx-linked-todos"
        )
      ),
      createdAt: createdAt
    )

    let todoSnapshots = try await runtime.query(TodoProjectExample.todosWithProjectQuery)
    expectNoDifference(todoSnapshots.map(\.id), ["todo-1"])
    expectNoDifference(todoSnapshots.first?.links?["project"]?.map(\.id), ["project-1"])
    expectNoDifference(todoSnapshots.first?.links?["project"]?.first?.values, [
      "title": .one(.string("Launch"))
    ])

    let projectSnapshots = try await runtime.query(TodoProjectExample.projectsWithTodosQuery)
    expectNoDifference(projectSnapshots.map(\.id), ["project-1"])
    expectNoDifference(projectSnapshots.first?.links?["todos"]?.map(\.id), ["todo-1"])
    expectNoDifference(projectSnapshots.first?.links?["todos"]?.first?.values, [
      "project": .one(.ref("project-1")),
      "text": .one(.string("Wire links")),
    ])

    let cachedTodos = try await runtime.cachedQuery(TodoProjectExample.todosWithProjectQuery)
    let cachedProjects = try await runtime.cachedQuery(TodoProjectExample.projectsWithTodosQuery)
    expectNoDifference(cachedTodos?.emission.values.first?.links?["project"]?.map(\.id), [
      "project-1"
    ])
    expectNoDifference(cachedProjects?.emission.values.first?.links?["todos"]?.map(\.id), [
      "todo-1"
    ])

    let relaunchedRuntime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "test-app",
        persistenceURL: cacheURL,
        initialAttributes: TodoProjectExample.attributes
      )
    )
    let relaunchedTodos = try await relaunchedRuntime.cachedQuery(
      TodoProjectExample.todosWithProjectQuery
    )
    let relaunchedProjects = try await relaunchedRuntime.cachedQuery(
      TodoProjectExample.projectsWithTodosQuery
    )
    expectNoDifference(relaunchedTodos?.plan, TodoProjectExample.todosWithProjectQuery)
    expectNoDifference(relaunchedProjects?.plan, TodoProjectExample.projectsWithTodosQuery)
    expectNoDifference(relaunchedTodos?.emission.values.first?.links?["project"]?.map(\.id), [
      "project-1"
    ])
    expectNoDifference(relaunchedProjects?.emission.values.first?.links?["todos"]?.map(\.id), [
      "todo-1"
    ])

    let fullPlan = InstantQueryPlan(id: "todos.full", namespace: "todos")
    let includePlan = InstantQueryPlan(
      id: "todos.full",
      namespace: "todos",
      includes: [InstantQueryInclude("project")]
    )
    #expect(fullPlan.cacheKey != includePlan.cacheKey)
  }

  @Test
  func queryFiltersSupportOneHopNestedRelationFields() async throws {
    let cacheURL = try temporaryCacheURL()
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "test-app",
        persistenceURL: cacheURL,
        initialAttributes: TodoProjectExample.attributes
      )
    )
    let createdAt = InstantTimestamp(milliseconds: 1_700_000_000_000)
    let secondCreatedAt = InstantTimestamp(milliseconds: createdAt.milliseconds + 1)
    let thirdCreatedAt = InstantTimestamp(milliseconds: createdAt.milliseconds + 2)
    let transactionID = "tx-nested-relation-filters"
    var operations: [InstantTripleOperation] = []
    operations += TodoProjectExample.createProjectOperations(
      id: "project-1",
      title: "Launch",
      createdAt: createdAt,
      transactionID: transactionID
    )
    operations += TodoProjectExample.createProjectOperations(
      id: "project-2",
      title: "Archive",
      createdAt: secondCreatedAt,
      transactionID: transactionID
    )
    operations += TodoProjectExample.createProjectOperations(
      id: "project-3",
      title: "Empty",
      createdAt: thirdCreatedAt,
      transactionID: transactionID
    )
    operations += TodoExample.createOperations(
      id: "todo-1",
      text: "Wire links",
      createdAt: createdAt,
      transactionID: transactionID
    )
    operations += TodoExample.createOperations(
      id: "todo-2",
      text: "Polish docs",
      createdAt: secondCreatedAt,
      transactionID: transactionID
    )
    operations += TodoExample.createOperations(
      id: "todo-3",
      text: "Loose todo",
      createdAt: thirdCreatedAt,
      transactionID: transactionID
    )
    operations += TodoProjectExample.linkOperations(
      todoID: "todo-1",
      projectID: "project-1",
      updatedAt: createdAt,
      transactionID: transactionID
    )
    operations += TodoProjectExample.linkOperations(
      todoID: "todo-2",
      projectID: "project-2",
      updatedAt: secondCreatedAt,
      transactionID: transactionID
    )
    try await runtime.transact(
      InstantStoreTransaction(id: transactionID, operations: operations),
      createdAt: createdAt
    )

    func queryIDs(
      _ runtime: InstantRuntime,
      id: String,
      namespace: String,
      filters: [InstantQueryFilter]
    ) async throws -> [String] {
      try await runtime.query(
        InstantQueryPlan(id: id, namespace: namespace, filters: filters)
      )
      .map(\.id)
    }

    let todoCases: [(String, [InstantQueryFilter], [String])] = [
      (
        "equals",
        [.equals(field: "project.title", value: .string("Launch"))],
        ["todo-1"]
      ),
      (
        "not-equals",
        [.notEquals(field: "project.title", value: .string("Launch"))],
        ["todo-2", "todo-3"]
      ),
      (
        "greater-than",
        [.greaterThan(field: "project.title", value: .string("Archive"))],
        ["todo-1"]
      ),
      (
        "greater-than-or-equal",
        [.greaterThanOrEqual(field: "project.title", value: .string("Launch"))],
        ["todo-1"]
      ),
      (
        "less-than",
        [.lessThan(field: "project.title", value: .string("Launch"))],
        ["todo-2"]
      ),
      (
        "less-than-or-equal",
        [.lessThanOrEqual(field: "project.title", value: .string("Archive"))],
        ["todo-2"]
      ),
      (
        "in",
        [.in(field: "project.title", values: [.string("Launch"), .string("Missing")])],
        ["todo-1"]
      ),
      (
        "like",
        [.like(field: "project.title", pattern: "%unch")],
        ["todo-1"]
      ),
      (
        "ilike",
        [.iLike(field: "project.title", pattern: "%launch%")],
        ["todo-1"]
      ),
      (
        "is-null",
        [.isNull(field: "project.title")],
        ["todo-3"]
      ),
      (
        "is-not-null",
        [.isNotNull(field: "project.title")],
        ["todo-1", "todo-2"]
      ),
      (
        "id",
        [.equals(field: "project.id", value: .string("project-1"))],
        ["todo-1"]
      ),
      (
        "compound-or",
        [
          .or([
            .equals(field: "project.title", value: .string("Launch")),
            .equals(field: "text", value: .string("Loose todo")),
          ])
        ],
        ["todo-1", "todo-3"]
      ),
    ]

    for (id, filters, expectedIDs) in todoCases {
      let ids = try await queryIDs(
        runtime,
        id: "todos.nested.\(id)",
        namespace: TodoExample.namespace,
        filters: filters
      )
      expectNoDifference(ids, expectedIDs)
    }

    let projectCases: [(String, [InstantQueryFilter], [String])] = [
      (
        "equals",
        [.equals(field: "todos.text", value: .string("Wire links"))],
        ["project-1"]
      ),
      (
        "not-equals",
        [.notEquals(field: "todos.text", value: .string("Wire links"))],
        ["project-2", "project-3"]
      ),
      (
        "ilike",
        [.iLike(field: "todos.text", pattern: "%DOCS%")],
        ["project-2"]
      ),
      (
        "is-null",
        [.isNull(field: "todos.text")],
        ["project-3"]
      ),
      (
        "is-not-null",
        [.isNotNull(field: "todos.text")],
        ["project-1", "project-2"]
      ),
      (
        "id",
        [.equals(field: "todos.id", value: .string("todo-1"))],
        ["project-1"]
      ),
    ]

    for (id, filters, expectedIDs) in projectCases {
      let ids = try await queryIDs(
        runtime,
        id: "projects.nested.\(id)",
        namespace: TodoProjectExample.namespace,
        filters: filters
      )
      expectNoDifference(ids, expectedIDs)
    }

    for (field, namespace) in [
      ("missing.title", TodoExample.namespace),
      ("project.missing", TodoProjectExample.namespace),
      ("text.value", TodoExample.namespace),
      ("project.title.extra", TodoProjectExample.namespace),
    ] {
      await expectQueryValidation(namespace: namespace, path: field) {
        _ = try await queryIDs(
          runtime,
          id: "todos.invalid-nested.\(field)",
          namespace: TodoExample.namespace,
          filters: [.equals(field: field, value: .string("Launch"))]
        )
      }
    }

    let launchPlan = InstantQueryPlan(
      id: "todos.nested.cached.launch",
      namespace: TodoExample.namespace,
      filters: [.equals(field: "project.title", value: .string("Launch"))]
    )
    let launchIDs = try await runtime.query(launchPlan).map(\.id)
    let cachedLaunchIDs = try await runtime.cachedQuery(launchPlan)?.emission.values.map(\.id)
    expectNoDifference(launchIDs, ["todo-1"])
    expectNoDifference(cachedLaunchIDs, ["todo-1"])

    let stream = await runtime.observe(launchPlan)
    var iterator = stream.makeAsyncIterator()
    let initialEmission = await iterator.next()
    expectNoDifference(initialEmission?.values.map(\.id), ["todo-1"])

    try await runtime.transact(
      InstantStoreTransaction(
        id: "tx-retitle-project",
        operations: TodoProjectExample.upsertProjectOperations(
          id: "project-1",
          title: "Released",
          createdAt: InstantTimestamp(milliseconds: createdAt.milliseconds + 3),
          transactionID: "tx-retitle-project"
        )
      ),
      createdAt: InstantTimestamp(milliseconds: createdAt.milliseconds + 3)
    )
    let retitledEmission = await iterator.next()
    expectNoDifference(retitledEmission?.values.map(\.id), [])

    let releasedPlan = InstantQueryPlan(
      id: "todos.nested.cached.released",
      namespace: TodoExample.namespace,
      filters: [.equals(field: "project.title", value: .string("Released"))]
    )
    let staleLaunchIDs = try await runtime.query(launchPlan).map(\.id)
    let releasedIDs = try await runtime.query(releasedPlan).map(\.id)
    let cachedReleasedIDs = try await runtime.cachedQuery(releasedPlan)?.emission.values.map(\.id)
    expectNoDifference(staleLaunchIDs, [])
    expectNoDifference(releasedIDs, ["todo-1"])
    expectNoDifference(cachedReleasedIDs, ["todo-1"])

    let relaunchedRuntime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "test-app",
        persistenceURL: cacheURL,
        initialAttributes: TodoProjectExample.attributes
      )
    )
    let relaunchedReleasedIDs = try await relaunchedRuntime.query(releasedPlan).map(\.id)
    expectNoDifference(relaunchedReleasedIDs, ["todo-1"])
  }

  @Test
  func queryFiltersSupportForwardManyNestedRelationFields() async throws {
    let articlesTitle = InstantAttribute(
      id: "articles/title",
      namespace: "articles",
      name: "title",
      valueType: .string
    )
    let articlesTags = InstantAttribute(
      id: "articles/tags",
      namespace: "articles",
      name: "tags",
      valueType: .ref,
      cardinality: .many,
      linkNamespace: "tags"
    )
    let tagsName = InstantAttribute(
      id: "tags/name",
      namespace: "tags",
      name: "name",
      valueType: .string
    )
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "test-app",
        persistenceURL: temporaryCacheURL(),
        initialAttributes: [articlesTitle, articlesTags, tagsName]
      )
    )
    let time = InstantTimestamp(milliseconds: 1_700_000_000_000)
    try await runtime.transact(
      InstantStoreTransaction(
        id: "tx-forward-many-nested-filters",
        operations: [
          .insert(.init(entityID: "article-1", attributeID: "articles/title", value: .string("Build"), txID: "tx-forward-many-nested-filters", txTime: time)),
          .insert(.init(entityID: "article-1", attributeID: "articles/tags", value: .ref("tag-swift"), txID: "tx-forward-many-nested-filters", txTime: time)),
          .insert(.init(entityID: "article-1", attributeID: "articles/tags", value: .ref("tag-data"), txID: "tx-forward-many-nested-filters", txTime: time)),
          .insert(.init(entityID: "article-2", attributeID: "articles/title", value: .string("Design"), txID: "tx-forward-many-nested-filters", txTime: time)),
          .insert(.init(entityID: "article-2", attributeID: "articles/tags", value: .ref("tag-ui"), txID: "tx-forward-many-nested-filters", txTime: time)),
          .insert(.init(entityID: "article-3", attributeID: "articles/title", value: .string("Draft"), txID: "tx-forward-many-nested-filters", txTime: time)),
          .insert(.init(entityID: "tag-swift", attributeID: "tags/name", value: .string("Swift"), txID: "tx-forward-many-nested-filters", txTime: time)),
          .insert(.init(entityID: "tag-data", attributeID: "tags/name", value: .string("Data"), txID: "tx-forward-many-nested-filters", txTime: time)),
          .insert(.init(entityID: "tag-ui", attributeID: "tags/name", value: .string("UI"), txID: "tx-forward-many-nested-filters", txTime: time)),
        ]
      ),
      createdAt: time
    )

    func articleIDs(id: String, filters: [InstantQueryFilter]) async throws -> [String] {
      try await runtime.query(
        InstantQueryPlan(id: id, namespace: "articles", filters: filters)
      )
      .map(\.id)
    }

    let swiftArticles = try await articleIDs(id: "articles.tags.name.swift", filters: [
      .equals(field: "tags.name", value: .string("Swift"))
    ])
    let notSwiftArticles = try await articleIDs(id: "articles.tags.name.not-swift", filters: [
      .notEquals(field: "tags.name", value: .string("Swift"))
    ])
    let untaggedArticles = try await articleIDs(id: "articles.tags.name.null", filters: [
      .isNull(field: "tags.name")
    ])
    let swiftIDArticles = try await articleIDs(id: "articles.tags.id.swift", filters: [
      .equals(field: "tags.id", value: .string("tag-swift"))
    ])

    expectNoDifference(swiftArticles, ["article-1"])
    expectNoDifference(notSwiftArticles, ["article-1", "article-2", "article-3"])
    expectNoDifference(untaggedArticles, ["article-3"])
    expectNoDifference(swiftIDArticles, ["article-1"])
  }

  @Test
  func queryFiltersSupportMultiHopNestedRelationFields() async throws {
    let commentsBody = InstantAttribute(
      id: "comments/body",
      namespace: "comments",
      name: "body",
      valueType: .string,
      isIndexed: true
    )
    let commentsPost = InstantAttribute(
      id: "comments/post",
      namespace: "comments",
      name: "post",
      valueType: .ref,
      isIndexed: true,
      forwardIdentity: "comments/post",
      reverseIdentity: "posts/comments",
      linkNamespace: "posts"
    )
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "test-app",
        persistenceURL: temporaryCacheURL(),
        initialAttributes: lookupTestAttributes() + [commentsBody, commentsPost]
      )
    )
    let time = InstantTimestamp(milliseconds: 1_700_000_000_000)
    let transactionID = "tx-multi-hop-nested-filters"
    try await runtime.transact(
      InstantStoreTransaction(
        id: transactionID,
        operations: [
          .insert(.init(entityID: "user-1", attributeID: "users/id", value: .string("user-1"), txID: transactionID, txTime: time)),
          .insert(.init(entityID: "user-1", attributeID: "users/name", value: .string("Ana"), txID: transactionID, txTime: time)),
          .insert(.init(entityID: "user-2", attributeID: "users/id", value: .string("user-2"), txID: transactionID, txTime: time)),
          .insert(.init(entityID: "user-2", attributeID: "users/name", value: .string("Ben"), txID: transactionID, txTime: time)),
          .insert(.init(entityID: "user-3", attributeID: "users/id", value: .string("user-3"), txID: transactionID, txTime: time)),
          .insert(.init(entityID: "user-3", attributeID: "users/name", value: .string("Cy"), txID: transactionID, txTime: time)),
          .insert(.init(entityID: "post-1", attributeID: "posts/id", value: .string("post-1"), txID: transactionID, txTime: time)),
          .insert(.init(entityID: "post-1", attributeID: "posts/title", value: .string("Swift"), txID: transactionID, txTime: time)),
          .insert(.init(entityID: "post-1", attributeID: "posts/author", value: .ref("user-1"), txID: transactionID, txTime: time)),
          .insert(.init(entityID: "post-2", attributeID: "posts/id", value: .string("post-2"), txID: transactionID, txTime: time)),
          .insert(.init(entityID: "post-2", attributeID: "posts/title", value: .string("Data"), txID: transactionID, txTime: time)),
          .insert(.init(entityID: "post-2", attributeID: "posts/author", value: .ref("user-2"), txID: transactionID, txTime: time)),
          .insert(.init(entityID: "post-3", attributeID: "posts/id", value: .string("post-3"), txID: transactionID, txTime: time)),
          .insert(.init(entityID: "post-3", attributeID: "posts/title", value: .string("Draft"), txID: transactionID, txTime: time)),
          .insert(.init(entityID: "post-3", attributeID: "posts/author", value: .ref("user-2"), txID: transactionID, txTime: time)),
          .insert(.init(entityID: "comment-1", attributeID: "comments/id", value: .string("comment-1"), txID: transactionID, txTime: time)),
          .insert(.init(entityID: "comment-1", attributeID: "comments/body", value: .string("Great comment!"), txID: transactionID, txTime: time)),
          .insert(.init(entityID: "comment-1", attributeID: "comments/post", value: .ref("post-1"), txID: transactionID, txTime: time)),
          .insert(.init(entityID: "comment-2", attributeID: "comments/id", value: .string("comment-2"), txID: transactionID, txTime: time)),
          .insert(.init(entityID: "comment-2", attributeID: "comments/body", value: .string("Needs work"), txID: transactionID, txTime: time)),
          .insert(.init(entityID: "comment-2", attributeID: "comments/post", value: .ref("post-2"), txID: transactionID, txTime: time)),
        ]
      ),
      createdAt: time
    )

    func ids(id: String, namespace: String, filters: [InstantQueryFilter]) async throws -> [String] {
      try await runtime.query(
        InstantQueryPlan(id: id, namespace: namespace, filters: filters)
      )
      .map(\.id)
    }

    let usersWithGreatComments = try await ids(
      id: "users.posts.comments.body.equals",
      namespace: "users",
      filters: [.equals(field: "posts.comments.body", value: .string("Great comment!"))]
    )
    expectNoDifference(usersWithGreatComments, ["user-1"])

    let usersWithoutGreatComments = try await ids(
      id: "users.posts.comments.body.not-equals",
      namespace: "users",
      filters: [.notEquals(field: "posts.comments.body", value: .string("Great comment!"))]
    )
    expectNoDifference(usersWithoutGreatComments, ["user-2", "user-3"])

    let usersMissingCommentBodies = try await ids(
      id: "users.posts.comments.body.null",
      namespace: "users",
      filters: [.isNull(field: "posts.comments.body")]
    )
    expectNoDifference(usersMissingCommentBodies, ["user-2", "user-3"])

    let usersWithPostOne = try await ids(
      id: "users.posts.ref.equals",
      namespace: "users",
      filters: [.equals(field: "posts", value: .ref("post-1"))]
    )
    expectNoDifference(usersWithPostOne, ["user-1"])

    let usersWithoutPostOne = try await ids(
      id: "users.posts.ref.not-equals",
      namespace: "users",
      filters: [.notEquals(field: "posts", value: .ref("post-1"))]
    )
    expectNoDifference(usersWithoutPostOne, ["user-2", "user-3"])

    let usersWithPostTwo = try await ids(
      id: "users.posts.ref.in",
      namespace: "users",
      filters: [.in(field: "posts", values: [.ref("post-2")])]
    )
    expectNoDifference(usersWithPostTwo, ["user-2"])

    let usersWithoutPosts = try await ids(
      id: "users.posts.ref.null",
      namespace: "users",
      filters: [.isNull(field: "posts")]
    )
    expectNoDifference(usersWithoutPosts, ["user-3"])

    let commentsByAna = try await ids(
      id: "comments.post.author.name.equals",
      namespace: "comments",
      filters: [.equals(field: "post.author.name", value: .string("Ana"))]
    )
    expectNoDifference(commentsByAna, ["comment-1"])

    let commentsByAuthorPattern = try await ids(
      id: "comments.post.author.name.ilike",
      namespace: "comments",
      filters: [.iLike(field: "post.author.name", pattern: "%e%")]
    )
    expectNoDifference(commentsByAuthorPattern, ["comment-2"])

    await expectQueryValidation(namespace: "comments", path: "posts.comments.missing") {
      _ = try await ids(
        id: "users.posts.comments.missing",
        namespace: "users",
        filters: [.equals(field: "posts.comments.missing", value: .string("missing"))]
      )
    }

    await expectQueryValidation(namespace: "posts", path: "posts.title.body") {
      _ = try await ids(
        id: "users.posts.title.body",
        namespace: "users",
        filters: [.equals(field: "posts.title.body", value: .string("missing"))]
      )
    }

    await expectQueryValidation(namespace: "users", path: "posts") {
      _ = try await ids(
        id: "users.posts.ref.invalid-type",
        namespace: "users",
        filters: [.equals(field: "posts", value: .string("post-1"))]
      )
    }
  }

  @Test
  func queryFiltersSupportDirectReverseRelationFieldEdges() async throws {
    let usersName = InstantAttribute(
      id: "users/name",
      namespace: "users",
      name: "name",
      valueType: .string,
      isIndexed: true
    )
    let usersBio = InstantAttribute(
      id: "users/bio",
      namespace: "users",
      name: "bio",
      valueType: .string,
      isRequired: false,
      isIndexed: false
    )
    let postsTitle = InstantAttribute(
      id: "posts/title",
      namespace: "posts",
      name: "title",
      valueType: .string,
      isIndexed: true
    )
    let postsAuthor = InstantAttribute(
      id: "posts/author",
      namespace: "posts",
      name: "author",
      valueType: .ref,
      isIndexed: true,
      forwardIdentity: "posts/author",
      reverseIdentity: "users/posts",
      linkNamespace: "users"
    )
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "test-app",
        persistenceURL: temporaryCacheURL(),
        initialAttributes: [usersName, usersBio, postsTitle, postsAuthor]
      )
    )
    let time = InstantTimestamp(milliseconds: 1_700_000_000_000)
    let transactionID = "tx-direct-reverse-relation-filters"
    try await runtime.transact(
      InstantStoreTransaction(
        id: transactionID,
        operations: [
          .insert(.init(entityID: "user-1", attributeID: "users/name", value: .string("Ana"), txID: transactionID, txTime: time)),
          .insert(.init(entityID: "user-1", attributeID: "users/bio", value: .string("Writes about Swift"), txID: transactionID, txTime: time)),
          .insert(.init(entityID: "user-2", attributeID: "users/name", value: .string("Ben"), txID: transactionID, txTime: time)),
          .insert(.init(entityID: "user-3", attributeID: "users/name", value: .string("Cy"), txID: transactionID, txTime: time)),
          .insert(.init(entityID: "post-1", attributeID: "posts/title", value: .string("First"), txID: transactionID, txTime: time)),
          .insert(.init(entityID: "post-1", attributeID: "posts/author", value: .ref("user-1"), txID: transactionID, txTime: time)),
          .insert(.init(entityID: "post-2", attributeID: "posts/title", value: .string("Second"), txID: transactionID, txTime: time)),
          .insert(.init(entityID: "post-2", attributeID: "posts/author", value: .ref("user-1"), txID: transactionID, txTime: time)),
          .insert(.init(entityID: "post-3", attributeID: "posts/title", value: .string("Third"), txID: transactionID, txTime: time)),
          .insert(.init(entityID: "post-3", attributeID: "posts/author", value: .ref("user-2"), txID: transactionID, txTime: time)),
        ]
      ),
      createdAt: time
    )

    func userIDs(id: String, filters: [InstantQueryFilter]) async throws -> [String] {
      try await runtime.query(
        InstantQueryPlan(
          id: id,
          namespace: "users",
          filters: filters,
          order: InstantQueryOrder("name")
        )
      )
      .map(\.id)
    }

    let usersWithPosts = try await userIDs(
      id: "users.posts.ref.not-null",
      filters: [.isNotNull(field: "posts")]
    )
    expectNoDifference(usersWithPosts, ["user-1", "user-2"])

    let usersWithoutPostOne = try await userIDs(
      id: "users.posts.ref.not-equals-many",
      filters: [.notEquals(field: "posts", value: .ref("post-1"))]
    )
    expectNoDifference(usersWithoutPostOne, ["user-1", "user-2", "user-3"])

    await expectQueryValidation(namespace: "users", path: "author.bio") {
      _ = try await runtime.query(
        InstantQueryPlan(
          id: "posts.author.bio.unindexed-ilike",
          namespace: "posts",
          filters: [.iLike(field: "author.bio", pattern: "%swift%")]
        )
      )
    }
  }

  @Test
  func queryIncludesRoundTripPublicCodableShape() throws {
    let plan = InstantQueryPlan(
      id: "todos.codable-include",
      namespace: TodoExample.namespace,
      includes: [
        InstantQueryInclude(
          "project",
          query: InstantQueryIncludePlan(
            id: "projects.codable-include",
            namespace: "projects",
            selectedFields: ["title"]
          )
        )
      ]
    )

    let data = try JSONEncoder().encode(plan)
    let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    let includes = try #require(object["includes"] as? [[String: Any]])
    #expect(includes.first?["rejectsQuery"] == nil)

    let decoded = try JSONDecoder().decode(InstantQueryPlan.self, from: data)
    expectNoDifference(decoded, plan)
    expectNoDifference(decoded.cacheKey, plan.cacheKey)

    let nestedPlan = InstantQueryPlan(
      id: "todos.codable-include",
      namespace: TodoExample.namespace,
      includes: [
        InstantQueryInclude(
          "project",
          query: InstantQueryIncludePlan(
            id: "projects.codable-include",
            namespace: "projects",
            selectedFields: ["title"],
            includes: [InstantQueryInclude("todos", direction: .reverse)]
          )
        )
      ]
    )
    let nestedData = try JSONEncoder().encode(nestedPlan)
    let nestedDecoded = try JSONDecoder().decode(InstantQueryPlan.self, from: nestedData)
    expectNoDifference(nestedDecoded, nestedPlan)
    #expect(nestedPlan.cacheKey != plan.cacheKey)
  }

  @Test
  func queryIncludesRejectUndeclaredLinksAndInvalidIncludePlans() async throws {
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "test-app",
        persistenceURL: temporaryCacheURL(),
        initialAttributes: TodoProjectExample.attributes
      )
    )
    let createdAt = InstantTimestamp(milliseconds: 1_700_000_000_000)
    try await runtime.transact(
      InstantStoreTransaction(
        id: "tx-invalid-include",
        operations: TodoProjectExample.createProjectOperations(
          id: "project-1",
          title: "Launch",
          createdAt: createdAt,
          transactionID: "tx-invalid-include"
        ) + TodoExample.createOperations(
          id: "todo-1",
          text: "Wire links",
          createdAt: createdAt,
          transactionID: "tx-invalid-include"
        ) + TodoProjectExample.linkOperations(
          todoID: "todo-1",
          projectID: "project-1",
          updatedAt: createdAt,
          transactionID: "tx-invalid-include"
        )
      ),
      createdAt: createdAt
    )

    await expectQueryValidation(namespace: TodoExample.namespace, path: "missing") {
      _ = try await runtime.query(
        .init(
          id: "todos.bad-include",
          namespace: TodoExample.namespace,
          includes: [InstantQueryInclude("missing")]
        )
      )
    }
    let invalidObservation = await runtime.observe(
      .init(
        id: "todos.bad-include-observe",
        namespace: TodoExample.namespace,
        includes: [InstantQueryInclude("missing")]
      )
    )
    var invalidObservationIterator = invalidObservation.makeAsyncIterator()
    let invalidObservationEmission = await invalidObservationIterator.next()
    expectNoDifference(invalidObservationEmission?.values.map(\.id), [])
    #expect(await invalidObservationIterator.next() == nil)

    await expectQueryValidation(namespace: TodoExample.namespace, path: "project") {
      _ = try await runtime.query(
        .init(
          id: "todos.mismatched-include",
          namespace: TodoExample.namespace,
          includes: [
            InstantQueryInclude(
              "project",
              query: InstantQueryIncludePlan(id: "comments", namespace: "comments")
            )
          ]
        )
      )
    }

    await expectQueryValidation(namespace: TodoProjectExample.namespace, path: "missing") {
      _ = try await runtime.query(
        .init(
          id: "todos.bad-nested-filter",
          namespace: TodoExample.namespace,
          includes: [
            InstantQueryInclude(
              "project",
              query: InstantQueryIncludePlan(
                id: "projects.bad-filter",
                namespace: "projects",
                filters: [.equals(field: "missing", value: .string("Launch"))]
              )
            )
          ]
        )
      )
    }

    #expect(
      InstantQueryInclude(
        "project",
        query: InstantQueryPlan(id: "projects.paginated", namespace: "projects", limit: 1)
      ) == nil
    )
    let nestedInclude = try #require(
      InstantQueryInclude(
        "project",
        query: InstantQueryPlan(
          id: "projects.with-todos",
          namespace: "projects",
          includes: [InstantQueryInclude("todos", direction: .reverse)]
        )
      )
    )
    let nested = try await runtime.query(
      InstantQueryPlan(
        id: "todos.valid-nested-include",
        namespace: TodoExample.namespace,
        includes: [nestedInclude]
      )
    )
    #expect(nested.first?.links?["project"]?.first?.links?["todos"]?.map(\.id) == ["todo-1"])
    await expectQueryValidation(namespace: "projects", path: "missing") {
      _ = try await runtime.query(
        .init(
          id: "todos.bad-nested-include",
          namespace: TodoExample.namespace,
          includes: [
            InstantQueryInclude(
              "project",
              query: InstantQueryIncludePlan(
                id: "projects.bad-include",
                namespace: "projects",
                includes: [InstantQueryInclude("missing")]
              )
            )
          ]
        )
      )
    }
  }

  @Test
  func storeCommitPublishesToObserversRegisteredAfterPrepare() async throws {
    let createdAt = InstantTimestamp(milliseconds: 1_700_000_000_000)
    let store = InstantStore(snapshot: InstantStoreSnapshot(attributes: TodoExample.attributes))
    let transaction = InstantStoreTransaction(
      id: "tx-observer-after-prepare",
      operations: TodoExample.createOperations(
        id: "todo-observer-after-prepare",
        text: "observer after prepare",
        createdAt: createdAt,
        transactionID: "tx-observer-after-prepare"
      )
    )
    let prepared = try await store.prepare(
      transaction,
      applyingTo: InstantStoreSnapshot(attributes: TodoExample.attributes)
    )

    let stream = await store.observe(TodoExample.query)
    var iterator = stream.makeAsyncIterator()
    let initialEmission = await iterator.next()
    expectNoDifference(initialEmission?.values, [])
    let secondStream = await store.observe(TodoExample.query)
    var secondIterator = secondStream.makeAsyncIterator()
    let secondInitialEmission = await secondIterator.next()
    expectNoDifference(secondInitialEmission?.values, [])

    let committed = await store.commitAndPublish(prepared)
    expectNoDifference(committed.result.emissions.map { $0.queryID }, [TodoExample.query.id])

    let update = await iterator.next()
    let secondUpdate = await secondIterator.next()
    expectNoDifference(
      try TodoExample.decode(update?.values ?? []),
      [
        TodoRecord(
          id: "todo-observer-after-prepare",
          text: "observer after prepare",
          isCompleted: false,
          createdAt: createdAt
        )
      ]
    )
    expectNoDifference(
      try TodoExample.decode(secondUpdate?.values ?? []),
      [
        TodoRecord(
          id: "todo-observer-after-prepare",
          text: "observer after prepare",
          isCompleted: false,
          createdAt: createdAt
        )
      ]
    )
  }

  @Test
  func storeCommitDistinguishesObserversWithSameQueryIDDifferentPlans() async throws {
    let createdAt = InstantTimestamp(milliseconds: 1_700_000_000_000)
    let store = InstantStore(snapshot: InstantStoreSnapshot(attributes: TodoExample.attributes))
    let transaction = InstantStoreTransaction(
      id: "tx-shared-query-id",
      operations: TodoExample.createOperations(
        id: "todo-shared-query-id",
        text: "shared query id",
        createdAt: createdAt,
        transactionID: "tx-shared-query-id"
      )
    )
    let incompletePlan = InstantQueryPlan(
      id: "shared-query-id",
      namespace: TodoExample.namespace,
      filters: [.equals(field: "isCompleted", value: .bool(false))]
    )
    let completedPlan = InstantQueryPlan(
      id: "shared-query-id",
      namespace: TodoExample.namespace,
      filters: [.equals(field: "isCompleted", value: .bool(true))]
    )
    let prepared = try await store.prepare(
      transaction,
      applyingTo: InstantStoreSnapshot(attributes: TodoExample.attributes)
    )

    let incompleteStream = await store.observe(incompletePlan)
    var incompleteIterator = incompleteStream.makeAsyncIterator()
    _ = await incompleteIterator.next()
    let completedStream = await store.observe(completedPlan)
    var completedIterator = completedStream.makeAsyncIterator()
    _ = await completedIterator.next()

    let committed = await store.commitAndPublish(prepared)
    expectNoDifference(committed.result.emissions.map { $0.queryID }, ["shared-query-id", "shared-query-id"])
    expectNoDifference(committed.result.emissions.map { $0.values.map(\.id) }, [["todo-shared-query-id"], []])

    let incompleteUpdate = await incompleteIterator.next()
    let completedUpdate = await completedIterator.next()
    expectNoDifference(incompleteUpdate?.values.map(\.id), ["todo-shared-query-id"])
    expectNoDifference(completedUpdate?.values, [])
  }

  @Test
  func storeObservationsHonorRemotePageInfoWindows() async throws {
    let store = InstantStore(snapshot: InstantStoreSnapshot(attributes: TodoExample.attributes))
    let firstCreatedAt = InstantTimestamp(milliseconds: 1_700_000_000_000)
    let secondCreatedAt = InstantTimestamp(milliseconds: 1_700_000_000_100)
    let thirdCreatedAt = InstantTimestamp(milliseconds: 1_700_000_000_200)
    let secondCreatedAtDate = Date(
      timeIntervalSince1970: Double(secondCreatedAt.milliseconds) / 1000
    )
    _ = try await store.prepare(
      InstantStoreTransaction(
        id: "tx-remote-page-info-seed",
        operations: TodoExample.createOperations(
          id: "todo-1",
          text: "first",
          createdAt: firstCreatedAt,
          transactionID: "tx-remote-page-info-seed"
        ) + TodoExample.createOperations(
          id: "todo-2",
          text: "second",
          createdAt: secondCreatedAt,
          transactionID: "tx-remote-page-info-seed"
        ) + TodoExample.createOperations(
          id: "todo-3",
          text: "third",
          createdAt: thirdCreatedAt,
          transactionID: "tx-remote-page-info-seed"
        )
      )
    )
    let plan = InstantQueryPlan(
      id: "todos.remote-page-info",
      namespace: TodoExample.namespace,
      order: InstantQueryOrder("createdAt"),
      offset: 1,
      limit: 1
    )
    let pageInfo = InstantQueryPageInfo(
      startCursor: InstantQueryCursor(
        entityID: "todo-2",
        sortValue: .date(secondCreatedAtDate)
      ),
      endCursor: InstantQueryCursor(
        entityID: "todo-2",
        sortValue: .date(secondCreatedAtDate)
      ),
      hasPreviousPage: true,
      hasNextPage: true
    )

    let waitingStream = await store.observe(plan, remotePageInfo: .waiting)
    var waitingIterator = waitingStream.makeAsyncIterator()
    let waitingInitial = await waitingIterator.next()
    expectNoDifference(waitingInitial?.values.map(\.id), [])
    expectNoDifference(waitingInitial?.pageInfo, nil)

    let readyStream = await store.observe(plan, remotePageInfo: .ready(pageInfo))
    var readyIterator = readyStream.makeAsyncIterator()
    let readyInitial = await readyIterator.next()
    expectNoDifference(readyInitial?.values.map(\.id), ["todo-2"])
    expectNoDifference(readyInitial?.pageInfo, pageInfo)

    let prepared = try await store.prepare(
      InstantStoreTransaction(
        id: "tx-remote-page-info-optimistic",
        operations: TodoExample.createOperations(
          id: "todo-0",
          text: "optimistic before window",
          createdAt: InstantTimestamp(milliseconds: 1_699_999_999_900),
          transactionID: "tx-remote-page-info-optimistic"
        )
      ),
      applyingTo: await store.snapshot()
    )
    let committed = await store.commitAndPublish(prepared)

    let publishedWindows = committed.result.emissions
      .map { $0.values.map(\.id) }
      .sorted { $0.joined(separator: "|") < $1.joined(separator: "|") }
    expectNoDifference(publishedWindows, [[], ["todo-2"]])

    let waitingUpdate = await waitingIterator.next()
    expectNoDifference(waitingUpdate?.values.map(\.id), [])
    expectNoDifference(waitingUpdate?.pageInfo, nil)
    let readyUpdate = await readyIterator.next()
    expectNoDifference(readyUpdate?.values.map(\.id), ["todo-2"])
    expectNoDifference(readyUpdate?.pageInfo, pageInfo)
  }

  @Test
  func liveObservationEmitsInitialAndOptimisticUpdates() async throws {
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "test-app",
        persistenceURL: temporaryCacheURL(),
        initialAttributes: TodoExample.attributes
      )
    )
    let stream = await runtime.observe(TodoExample.query)
    var iterator = stream.makeAsyncIterator()

    let initial = await iterator.next()
    expectNoDifference(initial?.values, [])

    let createdAt = InstantTimestamp(milliseconds: 1_700_000_000_000)
    try await runtime.transact(
      InstantStoreTransaction(
        id: "tx-observed",
        operations: TodoExample.createOperations(
          id: "todo-observed",
          text: "observe me",
          createdAt: createdAt,
          transactionID: "tx-observed"
        )
      ),
      createdAt: createdAt
    )

    let emission = await iterator.next()
    let todos = try TodoExample.decode(emission?.values ?? [])
    expectNoDifference(
      todos,
      [
        TodoRecord(
          id: "todo-observed",
          text: "observe me",
          isCompleted: false,
          createdAt: createdAt
        )
      ]
    )
  }

  @Test
  func concurrentTransactionsPersistEveryMutation() async throws {
    let cacheURL = try temporaryCacheURL()
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "test-app",
        persistenceURL: cacheURL,
        initialAttributes: TodoExample.attributes
      )
    )

    try await withThrowingTaskGroup(of: Void.self) { group in
      for index in 0..<20 {
        group.addTask {
          let createdAt = InstantTimestamp(milliseconds: Int64(1_700_000_000_000 + index))
          try await runtime.transact(
            InstantStoreTransaction(
              id: "tx-\(index)",
              operations: TodoExample.createOperations(
                id: "todo-\(index)",
                text: "todo \(index)",
                createdAt: createdAt,
                transactionID: "tx-\(index)"
              )
            ),
            createdAt: createdAt
          )
        }
      }
      try await group.waitForAll()
    }

    let relaunchedRuntime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "test-app",
        persistenceURL: cacheURL,
        initialAttributes: TodoExample.attributes
      )
    )

    let todos = try await TodoExample.decode(relaunchedRuntime.query(TodoExample.query))
    expectNoDifference(todos.map(\.id), (0..<20).map { "todo-\($0)" })

    let pending = await relaunchedRuntime.pendingMutations()
    expectNoDifference(Set(pending.map(\.id)), Set((0..<20).map { "tx-\($0)" }))
  }

  @Test
  func queryOrderingUsesTypedValuesAndManyFiltersCheckAllValues() async throws {
    let score = InstantAttribute(
      id: "items/score",
      namespace: "items",
      name: "score",
      valueType: .number,
      isIndexed: true
    )
    let tag = InstantAttribute(
      id: "items/tag",
      namespace: "items",
      name: "tag",
      valueType: .string,
      cardinality: .many,
      isIndexed: true
    )
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "test-app",
        persistenceURL: temporaryCacheURL(),
        initialAttributes: [score, tag]
      )
    )
    let time = InstantTimestamp(milliseconds: 10)

    try await runtime.transact(
      InstantStoreTransaction(
        id: "tx-items",
        operations: [
          .insert(.init(entityID: "item-10", attributeID: "items/score", value: .number(10), txID: "tx-items", txTime: time)),
          .insert(.init(entityID: "item-10", attributeID: "items/tag", value: .string("a"), txID: "tx-items", txTime: time)),
          .insert(.init(entityID: "item-10", attributeID: "items/tag", value: .string("b"), txID: "tx-items", txTime: time)),
          .insert(.init(entityID: "item-2", attributeID: "items/score", value: .number(2), txID: "tx-items", txTime: time)),
          .insert(.init(entityID: "item-2", attributeID: "items/tag", value: .string("c"), txID: "tx-items", txTime: time)),
        ]
      ),
      createdAt: time
    )

    let ordered = try await runtime.query(
      .init(id: "items.ordered", namespace: "items", order: .init("score"))
    )
    expectNoDifference(ordered.map(\.id), ["item-2", "item-10"])

    let paged = try await runtime.query(
      .init(
        id: "items.paged",
        namespace: "items",
        order: .init("score"),
        offset: 1,
        limit: 1
      )
    )
    expectNoDifference(paged.map(\.id), ["item-10"])

    let filtered = try await runtime.query(
      .init(
        id: "items.filtered",
        namespace: "items",
        filters: [.equals(field: "tag", value: .string("b"))]
      )
    )
    expectNoDifference(filtered.map(\.id), ["item-10"])
  }

  @Test
  func dateCoercionPortsUpstreamInstantDateCases() throws {
    let validDateStrings = [
      "Sat, 05 Apr 2025 18:00:31 GMT": "2025-04-05T18:00:31.000Z",
      "2025-01-01T00:00:00Z": "2025-01-01T00:00:00.000Z",
      "2025-01-01": "2025-01-01T00:00:00.000Z",
      "2025-01-02T00:00:00-08": "2025-01-02T08:00:00.000Z",
      "2025-11-2T00:00:00.000Z": "2025-11-02T00:00:00.000Z",
      "2025-1-2T00:00:00.000Z": "2025-01-02T00:00:00.000Z",
      "2025-1-2 00:00:00": "2025-01-02T00:00:00.000Z",
      #""2025-01-02T00:00:00-08""#: "2025-01-02T08:00:00.000Z",
      "2025-01-15 20:53:08.200": "2025-01-15T20:53:08.200Z",
      "2025-01-15 20:53:08.892865": "2025-01-15T20:53:08.892Z",
      #""2025-01-15 20:53:08""#: "2025-01-15T20:53:08.000Z",
      "Wed Jul 09 2025": "2025-07-09T00:00:00.000Z",
      "8/4/2025, 11:02:31 PM": "2025-08-04T23:02:31.000Z",
      "2024-12-30 20:19:41.892865+00": "2024-12-30T20:19:41.892Z",
      "epoch": "1970-01-01T00:00:00.000Z",
      "Mon Feb 24 2025 22:37:27 GMT+0000": "2025-02-24T22:37:27.000Z",
      "\t2025-03-02T16:08:53Z": "2025-03-02T16:08:53.000Z",
      "2024-05-29 01:51:06.11848+00": "2024-05-29T01:51:06.118Z",
      "2025-03-01T16:08:53+0000": "2025-03-01T16:08:53.000Z",
      "2025-12-31 21:11": "2025-12-31T21:11:00.000Z",
      "04-17-2025": "2025-04-17T00:00:00.000Z",
      "2025-06-12T10:56:31.924+0530": "2025-06-12T05:26:31.924Z",
      "2025-06-05T17:00:00EST": "2025-06-05T22:00:00.000Z",
      "2025-06-05T17:00:00EDT": "2025-06-05T21:00:00.000Z",
      "2025-06-05T17:00:00PDT": "2025-06-06T00:00:00.000Z",
      "2025-06-05T17:00:00PST": "2025-06-06T01:00:00.000Z",
      "2025-06-05T17:00:00PYST": "2025-06-05T20:00:00.000Z",
      "2025-06-05T17:00:00UTC": "2025-06-05T17:00:00.000Z",
      "2025-06-05T17:00:00CETDST": "2025-06-05T15:00:00.000Z",
      "2025-06-05T17:00:00CET": "2025-06-05T16:00:00.000Z",
      "2025-06-05T17:00:00CEST": "2025-06-05T15:00:00.000Z",
      "2026-04-28T04:7:00.000Z": "2026-04-28T04:07:00.000Z",
      "2026-04-28T4:07:00.000Z": "2026-04-28T04:07:00.000Z",
      "2026-04-28T04:07:7.000Z": "2026-04-28T04:07:07.000Z",
    ]

    for (dateString, expectedISOString) in validDateStrings {
      let date = try #require(InstantDateCoercion.parse(dateString), "Expected \(dateString) to parse.")
      let actualISOString = iso8601MillisecondsString(from: date)
      #expect(
        actualISOString == expectedISOString,
        "Expected \(dateString) to parse as \(expectedISOString), got \(actualISOString)."
      )
    }

    let numberDate = InstantDateCoercion.coerce(.number(1_642_234_800_000))
      .map(iso8601MillisecondsString(from:))
    #expect(numberDate == "2022-01-15T08:20:00.000Z")
    #expect(InstantDateCoercion.parse("2025-01-0") == nil)
    #expect(InstantDateCoercion.parse(#""2025-01-0""#) == nil)
    #expect(InstantDateCoercion.parse("2025--01-02") == nil)
    #expect(InstantDateCoercion.parse("2025-01-02-") == nil)
    #expect(InstantDateCoercion.coerce(.bool(true)) == nil)
    #expect(InstantDateCoercion.coerce(.json(.object([:]))) == nil)
  }

  @Test
  func dateAttributesCoerceStringAndNumberValuesForMaterializationAndQueries() async throws {
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "test-app",
        persistenceURL: temporaryCacheURL(),
        initialAttributes: TodoExample.attributes
      )
    )
    let time = InstantTimestamp(milliseconds: 1_700_000_000_000)
    try await runtime.transact(
      InstantStoreTransaction(
        id: "tx-date-coercion",
        operations: [
          .insert(.init(entityID: "todo-string", attributeID: "todos/id", value: .string("todo-string"), txID: "tx-date-coercion", txTime: time)),
          .insert(.init(entityID: "todo-string", attributeID: "todos/text", value: .string("from string"), txID: "tx-date-coercion", txTime: time)),
          .insert(.init(entityID: "todo-string", attributeID: "todos/isCompleted", value: .bool(false), txID: "tx-date-coercion", txTime: time)),
          .insert(.init(entityID: "todo-string", attributeID: "todos/createdAt", value: .string("2025-01-15 20:53:08.200"), txID: "tx-date-coercion", txTime: time)),
          .insert(.init(entityID: "todo-number", attributeID: "todos/id", value: .string("todo-number"), txID: "tx-date-coercion", txTime: time)),
          .insert(.init(entityID: "todo-number", attributeID: "todos/text", value: .string("from number"), txID: "tx-date-coercion", txTime: time)),
          .insert(.init(entityID: "todo-number", attributeID: "todos/isCompleted", value: .bool(false), txID: "tx-date-coercion", txTime: time)),
          .insert(.init(entityID: "todo-number", attributeID: "todos/createdAt", value: .number(1_642_234_800_000), txID: "tx-date-coercion", txTime: time)),
        ]
      ),
      createdAt: time
    )

    let ordered = try await runtime.query(
      InstantQueryPlan(
        id: "todos.date-coercion.ordered",
        namespace: TodoExample.namespace,
        order: InstantQueryOrder("createdAt")
      )
    )
    #expect(ordered.map(\.id) == ["todo-number", "todo-string"])
    let orderedDates = ordered.map { $0.values["createdAt"]?.first }.map { value -> String? in
        guard case let .date(date) = value else { return nil }
        return iso8601MillisecondsString(from: date)
      }
    #expect(
      orderedDates == [
        "2022-01-15T08:20:00.000Z",
        "2025-01-15T20:53:08.200Z",
      ],
      "Expected coerced date values, got \(orderedDates)."
    )

    let equalString = try await runtime.query(
      InstantQueryPlan(
        id: "todos.date-coercion.equal-string",
        namespace: TodoExample.namespace,
        filters: [.equals(field: "createdAt", value: .string("2025-01-15T20:53:08.200Z"))]
      )
    )
    #expect(equalString.map(\.id) == ["todo-string"])

    let equalNumber = try await runtime.query(
      InstantQueryPlan(
        id: "todos.date-coercion.equal-number",
        namespace: TodoExample.namespace,
        filters: [.equals(field: "createdAt", value: .number(1_642_234_800_000))]
      )
    )
    #expect(equalNumber.map(\.id) == ["todo-number"])

    let ranged = try await runtime.query(
      InstantQueryPlan(
        id: "todos.date-coercion.range",
        namespace: TodoExample.namespace,
        filters: [.greaterThan(field: "createdAt", value: .string("2024-12-31"))],
        order: InstantQueryOrder("createdAt")
      )
    )
    #expect(ranged.map(\.id) == ["todo-string"])

    let afterStringCursor = try await runtime.queryOnce(
      InstantQueryPlan(
        id: "todos.date-coercion.after-string-cursor",
        namespace: TodoExample.namespace,
        order: InstantQueryOrder("createdAt"),
        after: InstantQueryCursor(
          entityID: "todo-number",
          sortValue: .string("2022-01-15T09:00:00Z")
        )
      )
    )
    #expect(afterStringCursor.values.map(\.id) == ["todo-string"])
  }

  @Test
  func queryOrderingSupportsServerCreatedAtReservedField() async throws {
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "test-app",
        persistenceURL: temporaryCacheURL(),
        initialAttributes: TodoExample.attributes
      )
    )
    let firstCreatedAt = InstantTimestamp(milliseconds: 1_700_000_000_010)
    let secondCreatedAt = InstantTimestamp(milliseconds: 1_700_000_000_020)
    let updateTime = InstantTimestamp(milliseconds: 1_700_000_000_100)

    try await runtime.transact(
      InstantStoreTransaction(
        id: "tx-server-created-at",
        operations: TodoExample.createOperations(
          id: "todo-c",
          text: "same time c",
          createdAt: firstCreatedAt,
          transactionID: "tx-server-created-at"
        ) + TodoExample.createOperations(
          id: "todo-a",
          text: "same time a",
          createdAt: firstCreatedAt,
          transactionID: "tx-server-created-at"
        ) + TodoExample.createOperations(
          id: "todo-b",
          text: "later b",
          createdAt: secondCreatedAt,
          transactionID: "tx-server-created-at"
        )
      ),
      createdAt: firstCreatedAt
    )
    try await runtime.transact(
      InstantStoreTransaction(
        id: "tx-server-created-at-update",
        operations: TodoExample.updateTextOperations(
          id: "todo-a",
          text: "updated without moving",
          updatedAt: updateTime,
          transactionID: "tx-server-created-at-update"
        )
      ),
      createdAt: updateTime
    )

    let ascendingPlan = InstantQueryPlan(
      id: "todos.server-created-at.asc",
      namespace: TodoExample.namespace,
      order: .serverCreatedAt
    )
    let descendingPlan = InstantQueryPlan(
      id: "todos.server-created-at.desc",
      namespace: TodoExample.namespace,
      order: .serverCreatedAtDescending
    )
    let noOrderPlan = InstantQueryPlan(id: "todos.server-created-at.no-order", namespace: TodoExample.namespace)
    let noOrderFirstPlan = InstantQueryPlan(
      id: "todos.server-created-at.no-order.first",
      namespace: TodoExample.namespace,
      first: 1
    )
    let createdAtFieldPlan = InstantQueryPlan(
      id: "todos.created-at.asc",
      namespace: TodoExample.namespace,
      order: InstantQueryOrder("createdAt")
    )

    let ascending = try await runtime.query(ascendingPlan)
    let descending = try await runtime.query(descendingPlan)
    let noOrder = try await runtime.query(noOrderPlan)
    let noOrderFirst = try await runtime.queryOnce(noOrderFirstPlan)
    let noOrderNext = try await runtime.queryOnce(
      InstantQueryPlan(
        id: "todos.server-created-at.no-order.next",
        namespace: TodoExample.namespace,
        after: try #require(noOrderFirst.pageInfo?.endCursor)
      )
    )
    let selected = try await runtime.query(
      InstantQueryPlan(
        id: "todos.server-created-at.selected",
        namespace: TodoExample.namespace,
        order: .serverCreatedAt,
        selectedFields: ["text"]
      )
    )

    expectNoDifference(ascending.map(\.id), ["todo-a", "todo-c", "todo-b"])
    expectNoDifference(descending.map(\.id), ["todo-b", "todo-c", "todo-a"])
    expectNoDifference(noOrder.map(\.id), ["todo-a", "todo-c", "todo-b"])
    expectNoDifference(noOrderPlan.order, nil)
    #expect(noOrderPlan.cacheKey != ascendingPlan.cacheKey)
    expectNoDifference(noOrderFirst.values.map(\.id), ["todo-a"])
    expectNoDifference(
      noOrderFirst.pageInfo?.endCursor,
      InstantQueryCursor(
        entityID: "todo-a",
        sortValue: .number(Double(firstCreatedAt.milliseconds))
      )
    )
    expectNoDifference(noOrderNext.values.map(\.id), ["todo-c", "todo-b"])
    expectNoDifference(selected.map(\.values), [
      ["text": .one(.string("updated without moving"))],
      ["text": .one(.string("same time c"))],
      ["text": .one(.string("later b"))],
    ])
    await expectQueryValidation(namespace: TodoExample.namespace, path: "serverCreatedAt") {
      _ = try await runtime.query(
        InstantQueryPlan(
          id: "todos.server-created-at.invalid-selection",
          namespace: TodoExample.namespace,
          selectedFields: ["serverCreatedAt"]
        )
      )
    }
    #expect(ascendingPlan.cacheKey != createdAtFieldPlan.cacheKey)
  }

  @Test
  func serverCreatedAtCursorsUseNumericTimestampsAndFallbackToNamespaceTriples() async throws {
    let title = InstantAttribute(
      id: "items/title",
      namespace: "items",
      name: "title",
      valueType: .string
    )
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "test-app",
        persistenceURL: temporaryCacheURL(),
        initialAttributes: [title]
      )
    )
    let firstTime = InstantTimestamp(milliseconds: 1_700_000_000_010)
    let secondTime = InstantTimestamp(milliseconds: 1_700_000_000_020)
    let thirdTime = InstantTimestamp(milliseconds: 1_700_000_000_030)

    try await runtime.transact(
      InstantStoreTransaction(
        id: "tx-server-created-at-fallback",
        operations: [
          .insert(.init(entityID: "item-c", attributeID: "items/title", value: .string("third"), txID: "tx-server-created-at-fallback", txTime: thirdTime)),
          .insert(.init(entityID: "item-a", attributeID: "items/title", value: .string("first"), txID: "tx-server-created-at-fallback", txTime: firstTime)),
          .insert(.init(entityID: "item-b", attributeID: "items/title", value: .string("second"), txID: "tx-server-created-at-fallback", txTime: secondTime)),
        ]
      ),
      createdAt: firstTime
    )

    let firstPage = try await runtime.queryOnce(
      InstantQueryPlan(
        id: "items.server-created-at.first",
        namespace: "items",
        order: .serverCreatedAt,
        first: 1
      )
    )
    expectNoDifference(firstPage.values.map(\.id), ["item-a"])
    expectNoDifference(firstPage.pageInfo?.startCursor?.sortValue, .number(Double(firstTime.milliseconds)))
    expectNoDifference(firstPage.pageInfo?.endCursor?.sortValue, .number(Double(firstTime.milliseconds)))

    let afterCursor = try #require(firstPage.pageInfo?.endCursor)
    let nextPage = try await runtime.queryOnce(
      InstantQueryPlan(
        id: "items.server-created-at.next",
        namespace: "items",
        order: .serverCreatedAt,
        first: 2,
        after: afterCursor
      )
    )
    expectNoDifference(nextPage.values.map(\.id), ["item-b", "item-c"])

    let previousPage = try await runtime.queryOnce(
      InstantQueryPlan(
        id: "items.server-created-at.previous",
        namespace: "items",
        order: .serverCreatedAt,
        last: 2,
        before: InstantQueryCursor(
          entityID: "item-c",
          sortValue: .number(Double(thirdTime.milliseconds))
        )
      )
    )
    expectNoDifference(previousPage.values.map(\.id), ["item-a", "item-b"])

    await expectQueryValidation(namespace: "items", path: "missing") {
      _ = try await runtime.query(
        InstantQueryPlan(id: "items.unknown-order", namespace: "items", order: InstantQueryOrder("missing"))
      )
    }
  }

  @Test
  func queryCursorPaginationReturnsPageInfoAfterSorting() async throws {
    let score = InstantAttribute(
      id: "items/score",
      namespace: "items",
      name: "score",
      valueType: .number,
      isIndexed: true
    )
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "test-app",
        persistenceURL: temporaryCacheURL(),
        initialAttributes: [score]
      )
    )
    let time = InstantTimestamp(milliseconds: 10)

    try await runtime.transact(
      InstantStoreTransaction(
        id: "tx-cursor-items",
        operations: (1...4).map { index in
          .insert(
            .init(
              entityID: "item-\(index)",
              attributeID: "items/score",
              value: .number(Double(index)),
              txID: "tx-cursor-items",
              txTime: time
            )
          )
        }
      ),
      createdAt: time
    )

    let firstPage = try await runtime.queryOnce(
      .init(
        id: "items.cursor.first",
        namespace: "items",
        order: .init("score"),
        first: 2
      )
    )
    expectNoDifference(firstPage.values.map(\.id), ["item-1", "item-2"])
    expectNoDifference(firstPage.pageInfo?.startCursor?.entityID, "item-1")
    expectNoDifference(firstPage.pageInfo?.startCursor?.sortValue, .number(1))
    expectNoDifference(firstPage.pageInfo?.endCursor?.entityID, "item-2")
    expectNoDifference(firstPage.pageInfo?.endCursor?.sortValue, .number(2))
    expectNoDifference(firstPage.pageInfo?.hasPreviousPage, false)
    expectNoDifference(firstPage.pageInfo?.hasNextPage, true)

    let nextCursor = try #require(firstPage.pageInfo?.endCursor)
    let nextPage = try await runtime.queryOnce(
      .init(
        id: "items.cursor.next",
        namespace: "items",
        order: .init("score"),
        first: 2,
        after: nextCursor
      )
    )
    expectNoDifference(nextPage.values.map(\.id), ["item-3", "item-4"])
    expectNoDifference(nextPage.pageInfo?.hasPreviousPage, true)
    expectNoDifference(nextPage.pageInfo?.hasNextPage, false)

    let inclusivePage = try await runtime.query(
      .init(
        id: "items.cursor.inclusive",
        namespace: "items",
        order: .init("score"),
        first: 2,
        after: InstantQueryCursor(entityID: "item-2", inclusive: true)
      )
    )
    expectNoDifference(inclusivePage.map(\.id), ["item-2", "item-3"])

    let previousPage = try await runtime.queryOnce(
      .init(
        id: "items.cursor.previous",
        namespace: "items",
        order: .init("score"),
        last: 2,
        before: InstantQueryCursor(entityID: "item-4", sortValue: .number(4))
      )
    )
    expectNoDifference(previousPage.values.map(\.id), ["item-2", "item-3"])
    expectNoDifference(previousPage.pageInfo?.hasPreviousPage, true)
    expectNoDifference(previousPage.pageInfo?.hasNextPage, true)

    let customCursorPage = try await runtime.query(
      .init(
        id: "items.cursor.custom",
        namespace: "items",
        order: .init("score"),
        first: 1,
        after: InstantQueryCursor(entityID: "item-2.5", sortValue: .number(2.5))
      )
    )
    expectNoDifference(customCursorPage.map(\.id), ["item-3"])

    let descendingFirstPage = try await runtime.queryOnce(
      .init(
        id: "items.cursor.desc.first",
        namespace: "items",
        order: .init("score", .descending),
        first: 2
      )
    )
    expectNoDifference(descendingFirstPage.values.map(\.id), ["item-4", "item-3"])

    let descendingNextCursor = try #require(descendingFirstPage.pageInfo?.endCursor)
    let descendingNextPage = try await runtime.query(
      .init(
        id: "items.cursor.desc.next",
        namespace: "items",
        order: .init("score", .descending),
        first: 2,
        after: descendingNextCursor
      )
    )
    expectNoDifference(descendingNextPage.map(\.id), ["item-2", "item-1"])

    let descendingPreviousPage = try await runtime.queryOnce(
      .init(
        id: "items.cursor.desc.previous",
        namespace: "items",
        order: .init("score", .descending),
        last: 2,
        before: InstantQueryCursor(entityID: "item-1", sortValue: .number(1))
      )
    )
    expectNoDifference(descendingPreviousPage.values.map(\.id), ["item-3", "item-2"])
    expectNoDifference(descendingPreviousPage.pageInfo?.hasPreviousPage, true)
    expectNoDifference(descendingPreviousPage.pageInfo?.hasNextPage, true)

    let firstPlan = InstantQueryPlan(id: "items.cache", namespace: "items", first: 1)
    let afterPlan = InstantQueryPlan(
      id: "items.cache",
      namespace: "items",
      first: 1,
      after: InstantQueryCursor(entityID: "item-1")
    )
    #expect(firstPlan.cacheKey != afterPlan.cacheKey)
  }

  @Test
  func queryCursorsPageAcrossNullAndMissingOrderValues() async throws {
    let score = InstantAttribute(
      id: "items/score",
      namespace: "items",
      name: "score",
      valueType: .number,
      isIndexed: true
    )
    let title = InstantAttribute(
      id: "items/title",
      namespace: "items",
      name: "title",
      valueType: .string
    )
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "test-app",
        persistenceURL: temporaryCacheURL(),
        initialAttributes: [score, title]
      )
    )
    let time = InstantTimestamp(milliseconds: 10)

    try await runtime.transact(
      InstantStoreTransaction(
        id: "tx-null-cursor-items",
        operations: [
          .insert(.init(entityID: "item-0-null", attributeID: "items/score", value: .null, txID: "tx-null-cursor-items", txTime: time)),
          .insert(.init(entityID: "item-0-null", attributeID: "items/title", value: .string("explicit null 0"), txID: "tx-null-cursor-items", txTime: time)),
          .insert(.init(entityID: "item-1-missing", attributeID: "items/title", value: .string("missing 1"), txID: "tx-null-cursor-items", txTime: time)),
          .insert(.init(entityID: "item-2-null", attributeID: "items/score", value: .null, txID: "tx-null-cursor-items", txTime: time)),
          .insert(.init(entityID: "item-2-null", attributeID: "items/title", value: .string("explicit null 2"), txID: "tx-null-cursor-items", txTime: time)),
          .insert(.init(entityID: "item-3-missing", attributeID: "items/title", value: .string("missing 3"), txID: "tx-null-cursor-items", txTime: time)),
          .insert(.init(entityID: "item-4-one", attributeID: "items/score", value: .number(1), txID: "tx-null-cursor-items", txTime: time)),
          .insert(.init(entityID: "item-4-one", attributeID: "items/title", value: .string("one"), txID: "tx-null-cursor-items", txTime: time)),
        ]
      ),
      createdAt: time
    )

    let firstPage = try await runtime.queryOnce(
      InstantQueryPlan(
        id: "items.null-cursors.first",
        namespace: "items",
        order: InstantQueryOrder("score"),
        first: 2
      )
    )
    expectNoDifference(firstPage.values.map(\.id), ["item-0-null", "item-1-missing"])
    expectNoDifference(firstPage.pageInfo?.startCursor?.sortValue, .null)
    expectNoDifference(firstPage.pageInfo?.endCursor?.sortValue, nil)
    expectNoDifference(firstPage.pageInfo?.hasNextPage, true)

    let nextPage = try await runtime.queryOnce(
      InstantQueryPlan(
        id: "items.null-cursors.next",
        namespace: "items",
        order: InstantQueryOrder("score"),
        first: 2,
        after: try #require(firstPage.pageInfo?.endCursor)
      )
    )
    expectNoDifference(nextPage.values.map(\.id), ["item-2-null", "item-3-missing"])
    expectNoDifference(nextPage.pageInfo?.startCursor?.sortValue, .null)
    expectNoDifference(nextPage.pageInfo?.endCursor?.sortValue, nil)
    expectNoDifference(nextPage.pageInfo?.hasPreviousPage, true)
    expectNoDifference(nextPage.pageInfo?.hasNextPage, true)

    let beforeExplicitNullPage = try await runtime.queryOnce(
      InstantQueryPlan(
        id: "items.null-cursors.before-null",
        namespace: "items",
        order: InstantQueryOrder("score"),
        last: 2,
        before: try #require(nextPage.pageInfo?.startCursor)
      )
    )
    expectNoDifference(beforeExplicitNullPage.values.map(\.id), ["item-0-null", "item-1-missing"])
    expectNoDifference(beforeExplicitNullPage.pageInfo?.hasPreviousPage, false)
    expectNoDifference(beforeExplicitNullPage.pageInfo?.hasNextPage, true)

    let beforeMissingPage = try await runtime.queryOnce(
      InstantQueryPlan(
        id: "items.null-cursors.before-missing",
        namespace: "items",
        order: InstantQueryOrder("score"),
        last: 2,
        before: try #require(nextPage.pageInfo?.endCursor)
      )
    )
    expectNoDifference(beforeMissingPage.values.map(\.id), ["item-1-missing", "item-2-null"])
    expectNoDifference(beforeMissingPage.pageInfo?.hasPreviousPage, true)
    expectNoDifference(beforeMissingPage.pageInfo?.hasNextPage, true)

    let finalPage = try await runtime.queryOnce(
      InstantQueryPlan(
        id: "items.null-cursors.final",
        namespace: "items",
        order: InstantQueryOrder("score"),
        first: 2,
        after: try #require(nextPage.pageInfo?.endCursor)
      )
    )
    expectNoDifference(finalPage.values.map(\.id), ["item-4-one"])
    expectNoDifference(finalPage.pageInfo?.startCursor?.sortValue, .number(1))
    expectNoDifference(finalPage.pageInfo?.hasPreviousPage, true)
    expectNoDifference(finalPage.pageInfo?.hasNextPage, false)

    let previousPage = try await runtime.queryOnce(
      InstantQueryPlan(
        id: "items.null-cursors.previous",
        namespace: "items",
        order: InstantQueryOrder("score"),
        last: 2,
        before: try #require(finalPage.pageInfo?.startCursor)
      )
    )
    expectNoDifference(previousPage.values.map(\.id), ["item-2-null", "item-3-missing"])
    expectNoDifference(previousPage.pageInfo?.hasPreviousPage, true)
    expectNoDifference(previousPage.pageInfo?.hasNextPage, true)

    let descendingFirstPage = try await runtime.queryOnce(
      InstantQueryPlan(
        id: "items.null-cursors.desc.first",
        namespace: "items",
        order: InstantQueryOrder("score", .descending),
        first: 3
      )
    )
    expectNoDifference(descendingFirstPage.values.map(\.id), ["item-4-one", "item-3-missing", "item-2-null"])
    expectNoDifference(descendingFirstPage.pageInfo?.endCursor?.sortValue, .null)

    let descendingNextPage = try await runtime.queryOnce(
      InstantQueryPlan(
        id: "items.null-cursors.desc.next",
        namespace: "items",
        order: InstantQueryOrder("score", .descending),
        first: 3,
        after: try #require(descendingFirstPage.pageInfo?.endCursor)
      )
    )
    expectNoDifference(descendingNextPage.values.map(\.id), ["item-1-missing", "item-0-null"])
    expectNoDifference(descendingNextPage.pageInfo?.hasPreviousPage, true)
    expectNoDifference(descendingNextPage.pageInfo?.hasNextPage, false)
  }

  @Test
  func queryFieldSelectionTrimsReturnedValuesAfterFilteringAndOrdering() async throws {
    let score = InstantAttribute(
      id: "items/score",
      namespace: "items",
      name: "score",
      valueType: .number,
      isIndexed: true
    )
    let text = InstantAttribute(
      id: "items/text",
      namespace: "items",
      name: "text",
      valueType: .string
    )
    let status = InstantAttribute(
      id: "items/status",
      namespace: "items",
      name: "status",
      valueType: .string,
      isIndexed: true
    )
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "test-app",
        persistenceURL: temporaryCacheURL(),
        initialAttributes: [score, text, status]
      )
    )
    let time = InstantTimestamp(milliseconds: 10)

    try await runtime.transact(
      InstantStoreTransaction(
        id: "tx-select-items",
        operations: [
          .insert(.init(entityID: "item-1", attributeID: "items/score", value: .number(1), txID: "tx-select-items", txTime: time)),
          .insert(.init(entityID: "item-1", attributeID: "items/text", value: .string("first"), txID: "tx-select-items", txTime: time)),
          .insert(.init(entityID: "item-1", attributeID: "items/status", value: .string("open"), txID: "tx-select-items", txTime: time)),
          .insert(.init(entityID: "item-2", attributeID: "items/score", value: .number(2), txID: "tx-select-items", txTime: time)),
          .insert(.init(entityID: "item-2", attributeID: "items/text", value: .string("second"), txID: "tx-select-items", txTime: time)),
          .insert(.init(entityID: "item-2", attributeID: "items/status", value: .string("open"), txID: "tx-select-items", txTime: time)),
          .insert(.init(entityID: "item-3", attributeID: "items/score", value: .number(3), txID: "tx-select-items", txTime: time)),
          .insert(.init(entityID: "item-3", attributeID: "items/text", value: .string("third"), txID: "tx-select-items", txTime: time)),
          .insert(.init(entityID: "item-3", attributeID: "items/status", value: .string("closed"), txID: "tx-select-items", txTime: time)),
        ]
      ),
      createdAt: time
    )

    let selectedPlan = InstantQueryPlan(
      id: "items.selected",
      namespace: "items",
      filters: [.equals(field: "status", value: .string("open"))],
      order: .init("score", .descending),
      selectedFields: ["text"]
    )
    let selected = try await runtime.query(selectedPlan)
    expectNoDifference(selected.map(\.id), ["item-2", "item-1"])
    expectNoDifference(selected.map(\.values), [
      ["text": .one(.string("second"))],
      ["text": .one(.string("first"))],
    ])

    let fullPlan = InstantQueryPlan(
      id: "items.selected",
      namespace: "items",
      filters: [.equals(field: "status", value: .string("open"))],
      order: .init("score", .descending)
    )
    #expect(fullPlan.cacheKey != selectedPlan.cacheKey)
    let selectedAgain = InstantQueryPlan(
      id: "items.selected",
      namespace: "items",
      filters: [.equals(field: "status", value: .string("open"))],
      order: .init("score", .descending),
      selectedFields: ["text", "text"]
    )
    expectNoDifference(selectedAgain.selectedFields, ["text"])
    expectNoDifference(selectedAgain.cacheKey, selectedPlan.cacheKey)

    await expectQueryValidation(namespace: "items", path: "missing") {
      _ = try await runtime.query(
        .init(
          id: "items.unknown-selection",
          namespace: "items",
          selectedFields: ["missing"]
        )
      )
    }
  }

  @Test
  func queryFiltersSupportComparisonsInAndNullChecks() async throws {
    let score = InstantAttribute(
      id: "items/score",
      namespace: "items",
      name: "score",
      valueType: .number,
      isIndexed: true
    )
    let tag = InstantAttribute(
      id: "items/tag",
      namespace: "items",
      name: "tag",
      valueType: .string,
      cardinality: .many,
      isIndexed: true
    )
    let optional = InstantAttribute(
      id: "items/optional",
      namespace: "items",
      name: "optional",
      valueType: .string
    )
    let active = InstantAttribute(
      id: "items/active",
      namespace: "items",
      name: "active",
      valueType: .boolean,
      isIndexed: true
    )
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "test-app",
        persistenceURL: temporaryCacheURL(),
        initialAttributes: [score, tag, optional, active]
      )
    )
    let time = InstantTimestamp(milliseconds: 10)

    try await runtime.transact(
      InstantStoreTransaction(
        id: "tx-filter-items",
        operations: [
          .insert(.init(entityID: "item-1", attributeID: "items/score", value: .number(1), txID: "tx-filter-items", txTime: time)),
          .insert(.init(entityID: "item-1", attributeID: "items/tag", value: .string("red"), txID: "tx-filter-items", txTime: time)),
          .insert(.init(entityID: "item-1", attributeID: "items/active", value: .bool(true), txID: "tx-filter-items", txTime: time)),
          .insert(.init(entityID: "item-2", attributeID: "items/score", value: .number(2), txID: "tx-filter-items", txTime: time)),
          .insert(.init(entityID: "item-2", attributeID: "items/tag", value: .string("blue"), txID: "tx-filter-items", txTime: time)),
          .insert(.init(entityID: "item-2", attributeID: "items/optional", value: .string("present"), txID: "tx-filter-items", txTime: time)),
          .insert(.init(entityID: "item-2", attributeID: "items/active", value: .bool(false), txID: "tx-filter-items", txTime: time)),
          .insert(.init(entityID: "item-3", attributeID: "items/score", value: .number(3), txID: "tx-filter-items", txTime: time)),
          .insert(.init(entityID: "item-3", attributeID: "items/tag", value: .string("green"), txID: "tx-filter-items", txTime: time)),
          .insert(.init(entityID: "item-3", attributeID: "items/active", value: .bool(true), txID: "tx-filter-items", txTime: time)),
          .insert(.init(entityID: "item-4", attributeID: "items/score", value: .number(4), txID: "tx-filter-items", txTime: time)),
          .insert(.init(entityID: "item-4", attributeID: "items/tag", value: .string("purple"), txID: "tx-filter-items", txTime: time)),
          .insert(.init(entityID: "item-4", attributeID: "items/optional", value: .null, txID: "tx-filter-items", txTime: time)),
          .insert(.init(entityID: "item-4", attributeID: "items/active", value: .bool(false), txID: "tx-filter-items", txTime: time)),
          .insert(.init(entityID: "item-5", attributeID: "items/score", value: .number(5), txID: "tx-filter-items", txTime: time)),
          .insert(.init(entityID: "item-5", attributeID: "items/tag", value: .string("red"), txID: "tx-filter-items", txTime: time)),
          .insert(.init(entityID: "item-5", attributeID: "items/tag", value: .string("yellow"), txID: "tx-filter-items", txTime: time)),
          .insert(.init(entityID: "item-5", attributeID: "items/optional", value: .string("present"), txID: "tx-filter-items", txTime: time)),
          .insert(.init(entityID: "item-5", attributeID: "items/active", value: .bool(true), txID: "tx-filter-items", txTime: time)),
          .insert(.init(entityID: "item-6", attributeID: "items/score", value: .number(6), txID: "tx-filter-items", txTime: time)),
        ]
      ),
      createdAt: time
    )

    let greaterThan = try await runtime.query(
      .init(
        id: "items.gt",
        namespace: "items",
        filters: [.greaterThan(field: "score", value: .number(1))],
        order: .init("score")
      )
    )
    expectNoDifference(greaterThan.map(\.id), ["item-2", "item-3", "item-4", "item-5", "item-6"])

    let greaterThanOrEqual = try await runtime.query(
      .init(
        id: "items.gte",
        namespace: "items",
        filters: [.greaterThanOrEqual(field: "score", value: .number(2))],
        order: .init("score")
      )
    )
    expectNoDifference(greaterThanOrEqual.map(\.id), ["item-2", "item-3", "item-4", "item-5", "item-6"])

    let lessThan = try await runtime.query(
      .init(
        id: "items.lt",
        namespace: "items",
        filters: [.lessThan(field: "score", value: .number(3))],
        order: .init("score")
      )
    )
    expectNoDifference(lessThan.map(\.id), ["item-1", "item-2"])

    let lessThanOrEqual = try await runtime.query(
      .init(
        id: "items.lte",
        namespace: "items",
        filters: [.lessThanOrEqual(field: "score", value: .number(2))],
        order: .init("score")
      )
    )
    expectNoDifference(lessThanOrEqual.map(\.id), ["item-1", "item-2"])

    let activeGreaterThanTrue = try await runtime.query(
      .init(
        id: "items.bool-gt",
        namespace: "items",
        filters: [.greaterThan(field: "active", value: .bool(true))],
        order: .init("score")
      )
    )
    expectNoDifference(activeGreaterThanTrue.map(\.id), [])

    let activeGreaterThanOrEqualTrue = try await runtime.query(
      .init(
        id: "items.bool-gte",
        namespace: "items",
        filters: [.greaterThanOrEqual(field: "active", value: .bool(true))],
        order: .init("score")
      )
    )
    expectNoDifference(activeGreaterThanOrEqualTrue.map(\.id), ["item-1", "item-3", "item-5"])

    let activeLessThanTrue = try await runtime.query(
      .init(
        id: "items.bool-lt",
        namespace: "items",
        filters: [.lessThan(field: "active", value: .bool(true))],
        order: .init("score")
      )
    )
    expectNoDifference(activeLessThanTrue.map(\.id), ["item-2", "item-4"])

    let activeLessThanOrEqualTrue = try await runtime.query(
      .init(
        id: "items.bool-lte",
        namespace: "items",
        filters: [.lessThanOrEqual(field: "active", value: .bool(true))],
        order: .init("score")
      )
    )
    expectNoDifference(
      activeLessThanOrEqualTrue.map(\.id),
      ["item-1", "item-2", "item-3", "item-4", "item-5"]
    )

    let inFilter = try await runtime.query(
      .init(
        id: "items.in",
        namespace: "items",
        filters: [.in(field: "tag", values: [.string("red"), .string("green")])],
        order: .init("score")
      )
    )
    expectNoDifference(inFilter.map(\.id), ["item-1", "item-3", "item-5"])

    let notEquals = try await runtime.query(
      .init(
        id: "items.ne",
        namespace: "items",
        filters: [.notEquals(field: "tag", value: .string("blue"))],
        order: .init("score")
      )
    )
    expectNoDifference(notEquals.map(\.id), ["item-1", "item-3", "item-4", "item-5", "item-6"])

    let notEqualsMatchesManyValueCandidate = try await runtime.query(
      .init(
        id: "items.ne-many",
        namespace: "items",
        filters: [.notEquals(field: "tag", value: .string("red"))],
        order: .init("score")
      )
    )
    expectNoDifference(
      notEqualsMatchesManyValueCandidate.map(\.id),
      ["item-2", "item-3", "item-4", "item-5", "item-6"]
    )

    let isNull = try await runtime.query(
      .init(
        id: "items.null",
        namespace: "items",
        filters: [.isNull(field: "optional")],
        order: .init("score")
      )
    )
    expectNoDifference(isNull.map(\.id), ["item-1", "item-3", "item-4", "item-6"])

    let isNotNull = try await runtime.query(
      .init(
        id: "items.not-null",
        namespace: "items",
        filters: [.isNotNull(field: "optional")],
        order: .init("score")
      )
    )
    expectNoDifference(isNotNull.map(\.id), ["item-2", "item-5"])

    await expectQueryValidation(namespace: "items", path: "unknown") {
      _ = try await runtime.query(
        .init(
          id: "items.ne-unknown",
          namespace: "items",
          filters: [.notEquals(field: "unknown", value: .string("anything"))],
          order: .init("score")
        )
      )
    }

    await expectQueryValidation(namespace: "items", path: "unknown") {
      _ = try await runtime.query(
        .init(
          id: "items.null-unknown",
          namespace: "items",
          filters: [.isNull(field: "unknown")],
          order: .init("score")
        )
      )
    }

    await expectQueryValidation(namespace: "items", path: "unknown") {
      _ = try await runtime.query(
        .init(
          id: "items.not-null-unknown",
          namespace: "items",
          filters: [.isNotNull(field: "unknown")],
          order: .init("score")
        )
      )
    }

    await expectQueryValidation(namespace: "items", path: "unknown") {
      _ = try await runtime.query(
        .init(
          id: "items.unknown-inside-or",
          namespace: "items",
          filters: [
            .or([
              .equals(field: "unknown", value: .string("anything")),
              .equals(field: "score", value: .number(1)),
            ])
          ],
          order: .init("score")
        )
      )
    }

    await expectQueryValidation(namespace: "items", path: "tag") {
      _ = try await runtime.query(
        .init(
          id: "items.mixed-type-range",
          namespace: "items",
          filters: [.greaterThan(field: "tag", value: .number(1))],
          order: .init("score")
        )
      )
    }
  }

  @Test
  func queryFiltersSupportPatternAndCompoundPredicates() async throws {
    let text = InstantAttribute(
      id: "items/text",
      namespace: "items",
      name: "text",
      valueType: .string,
      isIndexed: true
    )
    let status = InstantAttribute(
      id: "items/status",
      namespace: "items",
      name: "status",
      valueType: .string,
      isIndexed: true
    )
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "test-app",
        persistenceURL: temporaryCacheURL(),
        initialAttributes: [text, status]
      )
    )
    let time = InstantTimestamp(milliseconds: 10)

    try await runtime.transact(
      InstantStoreTransaction(
        id: "tx-pattern-items",
        operations: [
          .insert(.init(entityID: "item-1", attributeID: "items/text", value: .string("Ship Instant Swift Data"), txID: "tx-pattern-items", txTime: time)),
          .insert(.init(entityID: "item-1", attributeID: "items/status", value: .string("open"), txID: "tx-pattern-items", txTime: time)),
          .insert(.init(entityID: "item-2", attributeID: "items/text", value: .string("swift instant docs"), txID: "tx-pattern-items", txTime: time)),
          .insert(.init(entityID: "item-2", attributeID: "items/status", value: .string("closed"), txID: "tx-pattern-items", txTime: time)),
          .insert(.init(entityID: "item-3", attributeID: "items/text", value: .string("Port README"), txID: "tx-pattern-items", txTime: time)),
          .insert(.init(entityID: "item-3", attributeID: "items/status", value: .string("open"), txID: "tx-pattern-items", txTime: time)),
          .insert(.init(entityID: "item-4", attributeID: "items/text", value: .string("release_v1"), txID: "tx-pattern-items", txTime: time)),
          .insert(.init(entityID: "item-4", attributeID: "items/status", value: .string("open"), txID: "tx-pattern-items", txTime: time)),
          .insert(.init(entityID: "item-5", attributeID: "items/text", value: .string("release\\av1"), txID: "tx-pattern-items", txTime: time)),
          .insert(.init(entityID: "item-5", attributeID: "items/status", value: .string("open"), txID: "tx-pattern-items", txTime: time)),
        ]
      ),
      createdAt: time
    )

    let like = try await runtime.query(
      .init(
        id: "items.like",
        namespace: "items",
        filters: [.like(field: "text", pattern: "%Swift%")]
      )
    )
    expectNoDifference(like.map(\.id), ["item-1"])

    let iLike = try await runtime.query(
      .init(
        id: "items.ilike",
        namespace: "items",
        filters: [.iLike(field: "text", pattern: "%instant%")]
      )
    )
    expectNoDifference(iLike.map(\.id), ["item-1", "item-2"])

    let and = try await runtime.query(
      .init(
        id: "items.and",
        namespace: "items",
        filters: [
          .and([
            .iLike(field: "text", pattern: "%instant%"),
            .equals(field: "status", value: .string("open")),
          ])
        ]
      )
    )
    expectNoDifference(and.map(\.id), ["item-1"])

    let or = try await runtime.query(
      .init(
        id: "items.or",
        namespace: "items",
        filters: [
          .or([
            .equals(field: "status", value: .string("closed")),
            .like(field: "text", pattern: "%README"),
          ])
        ]
      )
    )
    expectNoDifference(or.map(\.id), ["item-2", "item-3"])

    let underscoreWildcard = try await runtime.query(
      .init(
        id: "items.underscore-wildcard",
        namespace: "items",
        filters: [.like(field: "text", pattern: "release_v_")]
      )
    )
    expectNoDifference(underscoreWildcard.map(\.id), ["item-4"])

    let backslashIsLiteral = try await runtime.query(
      .init(
        id: "items.backslash-literal",
        namespace: "items",
        filters: [.like(field: "text", pattern: "release\\_v_")]
      )
    )
    expectNoDifference(backslashIsLiteral.map(\.id), ["item-5"])

    let emptyOr = try await runtime.query(
      .init(id: "items.empty-or", namespace: "items", filters: [.or([])])
    )
    expectNoDifference(emptyOr, [])
  }

  @Test
  func rawNegativePaginationPlansDoNotTrapMaterialization() async throws {
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "test-app",
        persistenceURL: temporaryCacheURL(),
        initialAttributes: TodoExample.attributes
      )
    )
    let createdAt = InstantTimestamp(milliseconds: 1_700_000_000_000)
    try await runtime.transact(
      InstantStoreTransaction(
        id: "tx-negative-limit",
        operations: TodoExample.createOperations(
          id: "todo-negative-limit",
          text: "negative limit",
          createdAt: createdAt,
          transactionID: "tx-negative-limit"
        )
      ),
      createdAt: createdAt
    )

    var plan = TodoExample.query
    plan.limit = -1

    let snapshots = try await runtime.query(plan)
    expectNoDifference(snapshots, [])

    plan.limit = nil
    plan.offset = -1

    let negativeOffsetSnapshots = try await runtime.query(plan)
    expectNoDifference(negativeOffsetSnapshots, [])
  }

  private func temporaryCacheURL() throws -> URL {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("InstantSwiftDataTests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory.appendingPathComponent("state.sqlite")
  }

  private struct UpstreamRemindersFixture {
    var runtime: InstantRuntime
    var now: InstantTimestamp
    var personalList: RemindersListRecord
    var tags: [ReminderTagRecord]
  }

  private func upstreamRemindersFixture() async throws -> UpstreamRemindersFixture {
    let cacheURL = try temporaryCacheURL()
    let now = InstantTimestamp(milliseconds: 1_234_567_890_000)
    let day: Int64 = 24 * 60 * 60 * 1000
    let personalID = "00000000-0000-0000-0000-000000000000"
    let familyID = "00000000-0000-0000-0000-000000000001"
    let businessID = "00000000-0000-0000-0000-000000000002"
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "reminders-upstream-fixture",
        persistenceURL: cacheURL,
        initialAttributes: ReminderExample.attributes,
        now: { now },
        makeID: { UUID().uuidString.lowercased() }
      )
    )

    let lists: [(id: String, seed: RemindersListSeedRecord)] = [
      (
        personalID,
        RemindersListSeedRecord(
          localIDName: "upstream.reminders.personal",
          title: "Personal",
          color: "#4895ef",
          position: 1,
          createdAtOffsetMilliseconds: 0
        )
      ),
      (
        familyID,
        RemindersListSeedRecord(
          localIDName: "upstream.reminders.family",
          title: "Family",
          color: "#ed8935",
          position: 2,
          createdAtOffsetMilliseconds: 1
        )
      ),
      (
        businessID,
        RemindersListSeedRecord(
          localIDName: "upstream.reminders.business",
          title: "Business",
          color: "#b25dd3",
          position: 3,
          createdAtOffsetMilliseconds: 2
        )
      ),
    ]
    let reminders: [(id: String, listID: String, seed: ReminderSeedRecord)] = [
      (
        "00000000-0000-0000-0000-000000000003",
        personalID,
        ReminderSeedRecord(
          localIDName: "upstream.reminders.groceries",
          listLocalIDName: "upstream.reminders.personal",
          title: "Groceries",
          notes: "Milk\nEggs\nApples\nOatmeal\nSpinach",
          isCompleted: false,
          isFlagged: false,
          position: 1,
          createdAtOffsetMilliseconds: 3,
          tagTitles: ["someday", "optional", "adulting"]
        )
      ),
      (
        "00000000-0000-0000-0000-000000000004",
        personalID,
        ReminderSeedRecord(
          localIDName: "upstream.reminders.haircut",
          listLocalIDName: "upstream.reminders.personal",
          title: "Haircut",
          notes: "",
          isCompleted: false,
          isFlagged: true,
          dueDateOffsetMilliseconds: -2 * day,
          position: 2,
          createdAtOffsetMilliseconds: 4,
          tagTitles: ["someday", "optional"]
        )
      ),
      (
        "00000000-0000-0000-0000-000000000005",
        personalID,
        ReminderSeedRecord(
          localIDName: "upstream.reminders.doctor",
          listLocalIDName: "upstream.reminders.personal",
          title: "Doctor appointment",
          notes: "Ask about diet",
          isCompleted: false,
          isFlagged: false,
          dueDateOffsetMilliseconds: 0,
          priority: .high,
          position: 3,
          createdAtOffsetMilliseconds: 5,
          tagTitles: ["adulting"]
        )
      ),
      (
        "00000000-0000-0000-0000-000000000006",
        personalID,
        ReminderSeedRecord(
          localIDName: "upstream.reminders.walk",
          listLocalIDName: "upstream.reminders.personal",
          title: "Take a walk",
          notes: "",
          isCompleted: true,
          isFlagged: false,
          dueDateOffsetMilliseconds: -190 * day,
          position: 4,
          createdAtOffsetMilliseconds: 6,
          tagTitles: ["car", "kids", "social"]
        )
      ),
      (
        "00000000-0000-0000-0000-000000000007",
        personalID,
        ReminderSeedRecord(
          localIDName: "upstream.reminders.concert",
          listLocalIDName: "upstream.reminders.personal",
          title: "Buy concert tickets",
          notes: "",
          isCompleted: false,
          isFlagged: false,
          dueDateOffsetMilliseconds: 0,
          position: 5,
          createdAtOffsetMilliseconds: 7,
          tagTitles: ["social", "night"]
        )
      ),
      (
        "00000000-0000-0000-0000-000000000008",
        familyID,
        ReminderSeedRecord(
          localIDName: "upstream.reminders.kids",
          listLocalIDName: "upstream.reminders.family",
          title: "Pick up kids from school",
          notes: "",
          isCompleted: false,
          isFlagged: true,
          dueDateOffsetMilliseconds: 2 * day,
          priority: .high,
          position: 6,
          createdAtOffsetMilliseconds: 8
        )
      ),
      (
        "00000000-0000-0000-0000-000000000009",
        familyID,
        ReminderSeedRecord(
          localIDName: "upstream.reminders.laundry",
          listLocalIDName: "upstream.reminders.family",
          title: "Get laundry",
          notes: "",
          isCompleted: true,
          isFlagged: false,
          dueDateOffsetMilliseconds: -2 * day,
          priority: .low,
          position: 7,
          createdAtOffsetMilliseconds: 9
        )
      ),
      (
        "00000000-0000-0000-0000-00000000000A",
        familyID,
        ReminderSeedRecord(
          localIDName: "upstream.reminders.trash",
          listLocalIDName: "upstream.reminders.family",
          title: "Take out trash",
          notes: "",
          isCompleted: false,
          isFlagged: false,
          dueDateOffsetMilliseconds: 4 * day,
          priority: .high,
          position: 8,
          createdAtOffsetMilliseconds: 10
        )
      ),
      (
        "00000000-0000-0000-0000-00000000000B",
        businessID,
        ReminderSeedRecord(
          localIDName: "upstream.reminders.accountant",
          listLocalIDName: "upstream.reminders.business",
          title: "Call accountant",
          notes: "Status of tax return\nExpenses for next year\nChanging payroll company",
          isCompleted: false,
          isFlagged: false,
          dueDateOffsetMilliseconds: 2 * day,
          position: 9,
          createdAtOffsetMilliseconds: 11
        )
      ),
      (
        "00000000-0000-0000-0000-00000000000C",
        businessID,
        ReminderSeedRecord(
          localIDName: "upstream.reminders.emails",
          listLocalIDName: "upstream.reminders.business",
          title: "Send weekly emails",
          notes: "",
          isCompleted: true,
          isFlagged: false,
          dueDateOffsetMilliseconds: -2 * day,
          priority: .medium,
          position: 10,
          createdAtOffsetMilliseconds: 12
        )
      ),
      (
        "00000000-0000-0000-0000-00000000000D",
        businessID,
        ReminderSeedRecord(
          localIDName: "upstream.reminders.wwdc",
          listLocalIDName: "upstream.reminders.business",
          title: "Prepare for WWDC",
          notes: "",
          isCompleted: false,
          isFlagged: false,
          dueDateOffsetMilliseconds: 2 * day,
          position: 11,
          createdAtOffsetMilliseconds: 13,
          tagTitles: ["social"]
        )
      ),
    ]
    let tagIDs = ["car", "kids", "someday", "optional", "social", "night", "adulting"]
    let tags = tagIDs.map { id in
      (id: id, seed: ReminderTagSeedRecord(title: id))
    }
    let reminderTags = reminders.flatMap { reminder in
      reminder.seed.tagTitles.map { tagID in
        (reminderID: reminder.id, tagID: tagID)
      }
    }
    try await runtime.transact(
      InstantStoreTransaction(
        id: "tx-upstream-reminders-seed",
        operations: ReminderExample.seedOperations(
          lists: lists,
          reminders: reminders,
          tags: tags,
          reminderTags: reminderTags,
          baseCreatedAt: now,
          transactionID: "tx-upstream-reminders-seed"
        )
      ),
      createdAt: now
    )

    let personalList = try #require(
      try ReminderExample.decodeLists(try await runtime.query(ReminderExample.listsQuery))
        .first { $0.id == personalID }
    )
    let decodedTags = try ReminderExample.decodeTags(try await runtime.query(ReminderExample.tagsQuery))
    return UpstreamRemindersFixture(
      runtime: runtime,
      now: now,
      personalList: personalList,
      tags: decodedTags
    )
  }

  private func corruptReminderTitle(
    runtime: InstantRuntime,
    reminderID: String,
    title: String,
    timestamp: InstantTimestamp,
    transactionID: String
  ) async throws {
    try await runtime.transact(
      InstantStoreTransaction(
        id: transactionID,
        operations: [
          .retract(
            InstantTriple(
              entityID: reminderID,
              attributeID: "\(ReminderExample.remindersNamespace)/title",
              value: .string(title),
              txID: transactionID,
              txTime: timestamp
            )
          )
        ]
      ),
      createdAt: timestamp
    )
  }

  private func persistedObjectSource(_ testName: String) -> String {
    "upstream/instant/client/packages/core/__tests__/src/utils/PersistedObject.test.ts \(testName)"
  }

  private func savePersistedObjectCacheEntries(
    in store: SQLitePersistenceStore
  ) async throws -> [InstantCachedQuery] {
    let entries = zip(["a", "b", "c", "d", "e"], [10, 20, 50, 50, 50]).enumerated().map {
      offset,
      value in
      persistedObjectCacheEntry(
        cacheKey: "cache-\(value.0)",
        updatedAt: InstantTimestamp(milliseconds: Int64(offset + 1) * 10),
        payload: String(repeating: value.0, count: value.1)
      )
    }
    for entry in entries {
      let didSave = try await store.saveQueryCache(entry, expectedStoreRevision: 0)
      expectNoDifference(didSave, true)
    }
    return entries
  }

  private func persistedObjectCacheEntry(
    cacheKey: String,
    updatedAt: InstantTimestamp,
    payload: String
  ) -> InstantCachedQuery {
    let queryID = "persisted-object-parity"
    let plan = InstantQueryPlan(
      id: queryID,
      namespace: "persisted_object_cache",
      filters: [.equals(field: "cacheKey", value: .string(cacheKey))]
    )
    return InstantCachedQuery(
      cacheKey: cacheKey,
      queryID: queryID,
      plan: plan,
      emission: InstantQueryEmission(
        queryID: queryID,
        sequence: updatedAt.milliseconds,
        values: [
          InstantEntitySnapshot(
            id: cacheKey,
            namespace: "persisted_object_cache",
            values: ["payload": .one(.string(payload))]
          )
        ]
      ),
      updatedAt: updatedAt,
      storeRevision: 0
    )
  }

  private func encodedQueryCacheByteCount(_ entry: InstantCachedQuery) throws -> Int {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    return try encoder.encode(entry).count
  }

  private func iso8601MillisecondsString(from date: Date) -> String {
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"
    return formatter.string(from: date)
  }

  private func lookupTestAttributes() -> [InstantAttribute] {
    [
      InstantAttribute(
        id: "users/name",
        namespace: "users",
        name: "name",
        valueType: .string,
        isIndexed: true
      ),
      InstantAttribute(
        id: "users/email",
        namespace: "users",
        name: "email",
        valueType: .string,
        isIndexed: true,
        isUnique: true
      ),
      InstantAttribute(
        id: "posts/title",
        namespace: "posts",
        name: "title",
        valueType: .string,
        isIndexed: true
      ),
      InstantAttribute(
        id: "posts/slug",
        namespace: "posts",
        name: "slug",
        valueType: .string,
        isIndexed: true,
        isUnique: true
      ),
      InstantAttribute(
        id: "posts/author",
        namespace: "posts",
        name: "author",
        valueType: .ref,
        isIndexed: true,
        forwardIdentity: "posts/author",
        reverseIdentity: "users/posts",
        linkNamespace: "users"
      ),
    ]
  }

  private func cascadeChainAttributes() -> [InstantAttribute] {
    [
      InstantAttribute(
        id: "grandparents/name",
        namespace: "grandparents",
        name: "name",
        valueType: .string
      ),
      InstantAttribute(
        id: "parents/name",
        namespace: "parents",
        name: "name",
        valueType: .string
      ),
      InstantAttribute(
        id: "children/name",
        namespace: "children",
        name: "name",
        valueType: .string
      ),
      InstantAttribute(
        id: "parents/grandparent",
        namespace: "parents",
        name: "grandparent",
        valueType: .ref,
        isIndexed: true,
        forwardIdentity: "parents/grandparent",
        reverseIdentity: "grandparents/parents",
        linkNamespace: "grandparents",
        onDelete: .cascade
      ),
      InstantAttribute(
        id: "children/parent",
        namespace: "children",
        name: "parent",
        valueType: .ref,
        isIndexed: true,
        forwardIdentity: "children/parent",
        reverseIdentity: "parents/children",
        linkNamespace: "parents",
        onDelete: .cascade
      ),
    ]
  }

  private func seedLegacyQueryCache(at url: URL, entry: LegacyCachedQuery) throws {
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )

    var connection: OpaquePointer?
    guard sqlite3_open_v2(url.path, &connection, SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil)
      == SQLITE_OK
    else {
      let message = connection.flatMap { sqlite3_errmsg($0) }.map { String(cString: $0) }
        ?? "SQLite could not open \(url.path)."
      sqlite3_close(connection)
      throw InstantError(
        code: .persistenceFailed,
        operation: "open legacy query cache",
        message: message,
        recovery: "Check the temporary test database."
      )
    }
    defer { sqlite3_close(connection) }

    var errorMessage: UnsafeMutablePointer<CChar>?
    guard sqlite3_exec(
      connection,
      """
      CREATE TABLE instant_query_cache (
        query_id TEXT PRIMARY KEY NOT NULL,
        json TEXT NOT NULL,
        updated_at_ms INTEGER NOT NULL
      )
      """,
      nil,
      nil,
      &errorMessage
    ) == SQLITE_OK
    else {
      let message = errorMessage.map { String(cString: $0) }
        ?? "SQLite could not create legacy instant_query_cache."
      sqlite3_free(errorMessage)
      throw InstantError(
        code: .persistenceFailed,
        operation: "create legacy query cache",
        message: message,
        recovery: "Check the temporary test database."
      )
    }

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let data = try encoder.encode(entry)
    let json = String(decoding: data, as: UTF8.self)

    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(
      connection,
      """
      INSERT INTO instant_query_cache (query_id, json, updated_at_ms)
      VALUES (?, ?, ?)
      """,
      -1,
      &statement,
      nil
    ) == SQLITE_OK
    else {
      let message = connection.flatMap { sqlite3_errmsg($0) }.map { String(cString: $0) }
        ?? "SQLite could not prepare legacy query cache insert."
      throw InstantError(
        code: .persistenceFailed,
        operation: "prepare legacy query cache insert",
        message: message,
        recovery: "Check the temporary test database."
      )
    }
    defer { sqlite3_finalize(statement) }

    try entry.queryID.withCString { queryIDCString in
      try json.withCString { jsonCString in
        guard sqlite3_bind_text(statement, 1, queryIDCString, -1, nil) == SQLITE_OK,
          sqlite3_bind_text(statement, 2, jsonCString, -1, nil) == SQLITE_OK,
          sqlite3_bind_int64(statement, 3, sqlite3_int64(entry.updatedAt.milliseconds)) == SQLITE_OK
        else {
          let message = connection.flatMap { sqlite3_errmsg($0) }.map { String(cString: $0) }
            ?? "SQLite could not bind legacy query cache insert."
          throw InstantError(
            code: .persistenceFailed,
            operation: "bind legacy query cache insert",
            message: message,
            recovery: "Check the temporary test database."
          )
        }

        guard sqlite3_step(statement) == SQLITE_DONE else {
          let message = connection.flatMap { sqlite3_errmsg($0) }.map { String(cString: $0) }
            ?? "SQLite could not insert legacy query cache row."
          throw InstantError(
            code: .persistenceFailed,
            operation: "insert legacy query cache",
            message: message,
            recovery: "Check the temporary test database."
          )
        }
      }
    }
  }

  private func seedLegacyRoomTopicMessageBeforeAppScopedMigration(
    at url: URL,
    message: InstantRoomTopicMessage
  ) throws {
    var connection: OpaquePointer?
    guard sqlite3_open_v2(url.path, &connection, SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil)
      == SQLITE_OK
    else {
      let message = connection.flatMap { sqlite3_errmsg($0) }.map { String(cString: $0) }
        ?? "SQLite could not open \(url.path)."
      sqlite3_close(connection)
      throw InstantError(
        code: .persistenceFailed,
        operation: "open legacy room topic messages",
        message: message,
        recovery: "Check the temporary test database."
      )
    }
    defer { sqlite3_close(connection) }

    var errorMessage: UnsafeMutablePointer<CChar>?
    guard sqlite3_exec(
      connection,
      """
      DELETE FROM instant_schema_migrations
      WHERE name = '0005_app_scoped_room_topic_messages';

      DROP TABLE IF EXISTS instant_room_topic_messages;

      CREATE TABLE instant_room_topic_messages (
        message_id TEXT PRIMARY KEY NOT NULL,
        app_id TEXT NOT NULL,
        room_type TEXT NOT NULL,
        room_id TEXT NOT NULL,
        topic TEXT NOT NULL,
        created_at_ms INTEGER NOT NULL,
        json TEXT NOT NULL
      );

      CREATE INDEX IF NOT EXISTS instant_room_topic_messages_room_idx
      ON instant_room_topic_messages (app_id, room_type, room_id, topic, created_at_ms, message_id);
      """,
      nil,
      nil,
      &errorMessage
    ) == SQLITE_OK
    else {
      let message = errorMessage.map { String(cString: $0) }
        ?? "SQLite could not create legacy instant_room_topic_messages."
      sqlite3_free(errorMessage)
      throw InstantError(
        code: .persistenceFailed,
        operation: "create legacy room topic messages",
        message: message,
        recovery: "Check the temporary test database."
      )
    }

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let data = try encoder.encode(message)
    let json = String(decoding: data, as: UTF8.self)

    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(
      connection,
      """
      INSERT INTO instant_room_topic_messages
        (message_id, app_id, room_type, room_id, topic, created_at_ms, json)
      VALUES (?, ?, ?, ?, ?, ?, ?)
      """,
      -1,
      &statement,
      nil
    ) == SQLITE_OK
    else {
      let message = connection.flatMap { sqlite3_errmsg($0) }.map { String(cString: $0) }
        ?? "SQLite could not prepare legacy room topic insert."
      throw InstantError(
        code: .persistenceFailed,
        operation: "prepare legacy room topic insert",
        message: message,
        recovery: "Check the temporary test database."
      )
    }
    defer { sqlite3_finalize(statement) }

    guard sqlite3_bind_text(statement, 1, message.id, -1, testSQLiteTransient) == SQLITE_OK,
      sqlite3_bind_text(statement, 2, message.appID, -1, testSQLiteTransient) == SQLITE_OK,
      sqlite3_bind_text(statement, 3, message.room.type, -1, testSQLiteTransient) == SQLITE_OK,
      sqlite3_bind_text(statement, 4, message.room.id, -1, testSQLiteTransient) == SQLITE_OK,
      sqlite3_bind_text(statement, 5, message.topic, -1, testSQLiteTransient) == SQLITE_OK,
      sqlite3_bind_int64(statement, 6, sqlite3_int64(message.createdAt.milliseconds)) == SQLITE_OK,
      sqlite3_bind_text(statement, 7, json, -1, testSQLiteTransient) == SQLITE_OK
    else {
      let message = connection.flatMap { sqlite3_errmsg($0) }.map { String(cString: $0) }
        ?? "SQLite could not bind legacy room topic insert."
      throw InstantError(
        code: .persistenceFailed,
        operation: "bind legacy room topic insert",
        message: message,
        recovery: "Check the temporary test database."
      )
    }

    guard sqlite3_step(statement) == SQLITE_DONE else {
      let message = connection.flatMap { sqlite3_errmsg($0) }.map { String(cString: $0) }
        ?? "SQLite could not insert legacy room topic row."
      throw InstantError(
        code: .persistenceFailed,
        operation: "insert legacy room topic",
        message: message,
        recovery: "Check the temporary test database."
      )
    }
  }

  private func dropOutboxTable(at url: URL) throws {
    var connection: OpaquePointer?
    guard sqlite3_open_v2(url.path, &connection, SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil)
      == SQLITE_OK
    else {
      let message = connection.flatMap { sqlite3_errmsg($0) }.map { String(cString: $0) }
        ?? "SQLite could not open \(url.path)."
      sqlite3_close(connection)
      throw InstantError(
        code: .persistenceFailed,
        operation: "open test sqlite connection",
        message: message,
        recovery: "Check the temporary test database."
      )
    }
    defer { sqlite3_close(connection) }

    var errorMessage: UnsafeMutablePointer<CChar>?
    guard sqlite3_exec(connection, "DROP TABLE instant_outbox", nil, nil, &errorMessage)
      == SQLITE_OK
    else {
      let message = errorMessage.map { String(cString: $0) }
        ?? "SQLite could not drop instant_outbox."
      sqlite3_free(errorMessage)
      throw InstantError(
        code: .persistenceFailed,
        operation: "drop test outbox table",
        message: message,
        recovery: "Check the temporary test database."
      )
    }
  }

  private func expectQueryValidation(
    namespace: String,
    path: String?,
    _ operation: () async throws -> Void
  ) async {
    do {
      try await operation()
      #expect(Bool(false), "Expected query validation to fail.")
    } catch let error as InstantError {
      expectNoDifference(error.code, .validationFailed)
      expectNoDifference(error.operation, "validate query")
      expectNoDifference(error.namespace, namespace)
      expectNoDifference(error.path, path)
    } catch {
      #expect(Bool(false), "Unexpected error: \(error)")
    }
  }
}

private struct LegacyCachedQuery: Encodable, Sendable {
  var queryID: String
  var plan: InstantQueryPlan
  var emission: InstantQueryEmission
  var updatedAt: InstantTimestamp
  var storeRevision: Int64
}

private actor MutationTransportRecorder {
  private var recordedRequests: [InstantMutationTransportRequest] = []

  func record(_ request: InstantMutationTransportRequest) {
    recordedRequests.append(request)
  }

  func requests() -> [InstantMutationTransportRequest] {
    recordedRequests
  }
}

private actor PersistentTestLiveSession {
  private let appID: String
  private var pending: [InstantLiveMessage] = []
  private var waiter: CheckedContinuation<InstantLiveMessage, Error>?
  private var isClosed = false

  init(appID: String) {
    self.appID = appID
  }

  func send(_ message: InstantLiveMessage) {
    guard !isClosed else { return }
    let response: InstantLiveMessage?
    switch message.op {
    case "init":
      response = InstantLiveMessage(
        op: "init-ok",
        clientEventID: message.clientEventID,
        fields: [
          "attrs": .array([]),
          "auth": .null,
          "session-id": .string("persistent-test-session-\(appID)"),
        ]
      )
    case "transact":
      response = InstantLiveMessage(
        op: "transact-ok",
        clientEventID: message.clientEventID,
        fields: [
          "isn": .string("persistent-test-isn"),
          "tx-id": .string("persistent-test-\(message.clientEventID ?? "transaction")"),
        ]
      )
    case "add-query":
      response = InstantLiveMessage(
        op: "add-query-ok",
        clientEventID: message.clientEventID,
        fields: [
          "q": message.fields["q"] ?? .object([:]),
          "result": .array([]),
        ]
      )
    default:
      response = nil
    }
    guard let response else { return }
    if let waiter {
      self.waiter = nil
      waiter.resume(returning: response)
    } else {
      pending.append(response)
    }
  }

  func receive() async throws -> InstantLiveMessage {
    if !pending.isEmpty {
      return pending.removeFirst()
    }
    if isClosed {
      throw CancellationError()
    }
    return try await withCheckedThrowingContinuation { continuation in
      waiter = continuation
    }
  }

  func close() {
    isClosed = true
    pending.removeAll()
    waiter?.resume(throwing: CancellationError())
    waiter = nil
  }
}

private actor SuspendedMutationTransport {
  private var continuation: CheckedContinuation<InstantMutationTransportResponse, Never>?
  private var request: InstantMutationTransportRequest?
  private var requestWaiter: CheckedContinuation<Void, Never>?

  func send(_ request: InstantMutationTransportRequest) async -> InstantMutationTransportResponse {
    self.request = request
    requestWaiter?.resume()
    requestWaiter = nil

    return await withCheckedContinuation { continuation in
      self.continuation = continuation
    }
  }

  func waitForRequest() async {
    guard request == nil else { return }
    await withCheckedContinuation { continuation in
      requestWaiter = continuation
    }
  }

  func resumeConfirmingRequest() {
    guard let request, let continuation else { return }
    self.continuation = nil
    continuation.resume(
      returning: InstantMutationTransportResponse(
        results: request.mutations.map { mutation in
          InstantMutationTransportResult(mutationID: mutation.mutationID, outcome: .confirmed)
        }
      )
    )
  }
}

private actor SyncUpSoundEffectRecorder {
  private var loaded: [String] = []
  private var plays = 0

  func load(_ fileName: String) {
    loaded.append(fileName)
  }

  func play() {
    plays += 1
  }

  func loadedFileNames() -> [String] {
    loaded
  }

  func playCount() -> Int {
    plays
  }
}

private actor SyncUpOpenSettingsRecorder {
  private var count = 0

  func open() {
    count += 1
  }

  func openCount() -> Int {
    count
  }
}

private actor ConnectionStatusRecorder {
  private var statuses: [InstantConnectionStatus] = []

  func append(_ status: InstantConnectionStatus) {
    statuses.append(status)
  }

  func snapshot() -> [InstantConnectionStatus] {
    statuses
  }
}

private func requireObservedConnectionStatus(
  _ recorder: ConnectionStatusRecorder,
  after cursor: Int,
  operation: String,
  matching predicate: @escaping @Sendable (InstantConnectionStatus) -> Bool
) async throws -> (nextIndex: Int, status: InstantConnectionStatus) {
  for _ in 0..<100 {
    let statuses = await recorder.snapshot()
    if cursor < statuses.endIndex {
      for index in cursor..<statuses.endIndex where predicate(statuses[index]) {
        return (index + 1, statuses[index])
      }
    }
    try await Task.sleep(nanoseconds: 10_000_000)
  }
  throw InstantError(
    code: .validationFailed,
    operation: operation,
    message: "Timed out waiting for the next matching connection status observation.",
    recovery: "Inspect InstantRuntime.observeConnectionStatus publication sites."
  )
}

// SAFETY: mutable test state is protected by `lock`.
private final class LockIsolated<Value>: @unchecked Sendable {
  private var value: Value
  private let lock = NSLock()

  init(_ value: Value) {
    self.value = value
  }

  func withValue<Result>(_ operation: (inout Value) throws -> Result) rethrows -> Result {
    lock.lock()
    defer { lock.unlock() }
    return try operation(&value)
  }
}

private extension Array {
  subscript(safe index: Index) -> Element? {
    indices.contains(index) ? self[index] : nil
  }
}

private let testSQLiteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
