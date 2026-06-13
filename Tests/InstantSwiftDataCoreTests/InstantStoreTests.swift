import CustomDump
import Foundation
import SQLite3
@testable import InstantSwiftDataCore
import Testing

@Suite(.serialized)
struct InstantStoreTests {
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

    for field in ["missing.title", "project.missing", "text.value", "project.title.extra"] {
      let ids = try await queryIDs(
        runtime,
        id: "todos.invalid-nested.\(field)",
        namespace: TodoExample.namespace,
        filters: [.equals(field: field, value: .string("Launch"))]
      )
      expectNoDifference(ids, [])
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

    let undeclared = try await runtime.query(
      .init(
        id: "todos.bad-include",
        namespace: TodoExample.namespace,
        includes: [InstantQueryInclude("missing")]
      )
    )
    expectNoDifference(undeclared, [])

    let mismatchedNamespace = try await runtime.query(
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
    expectNoDifference(mismatchedNamespace, [])

    let undeclaredNestedFilter = try await runtime.query(
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
    expectNoDifference(undeclaredNestedFilter, [])

    #expect(
      InstantQueryInclude(
        "project",
        query: InstantQueryPlan(id: "projects.paginated", namespace: "projects", limit: 1)
      ) == nil
    )
    #expect(
      InstantQueryInclude(
        "project",
        query: InstantQueryPlan(
          id: "projects.with-todos",
          namespace: "projects",
          includes: [InstantQueryInclude("todos", direction: .reverse)]
        )
      ) == nil
    )
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

    let unknownSelection = try await runtime.query(
      .init(
        id: "items.unknown-selection",
        namespace: "items",
        selectedFields: ["missing"]
      )
    )
    expectNoDifference(unknownSelection, [])
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
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "test-app",
        persistenceURL: temporaryCacheURL(),
        initialAttributes: [score, tag, optional]
      )
    )
    let time = InstantTimestamp(milliseconds: 10)

    try await runtime.transact(
      InstantStoreTransaction(
        id: "tx-filter-items",
        operations: [
          .insert(.init(entityID: "item-1", attributeID: "items/score", value: .number(1), txID: "tx-filter-items", txTime: time)),
          .insert(.init(entityID: "item-1", attributeID: "items/tag", value: .string("red"), txID: "tx-filter-items", txTime: time)),
          .insert(.init(entityID: "item-2", attributeID: "items/score", value: .number(2), txID: "tx-filter-items", txTime: time)),
          .insert(.init(entityID: "item-2", attributeID: "items/tag", value: .string("blue"), txID: "tx-filter-items", txTime: time)),
          .insert(.init(entityID: "item-2", attributeID: "items/optional", value: .string("present"), txID: "tx-filter-items", txTime: time)),
          .insert(.init(entityID: "item-3", attributeID: "items/score", value: .number(3), txID: "tx-filter-items", txTime: time)),
          .insert(.init(entityID: "item-3", attributeID: "items/tag", value: .string("green"), txID: "tx-filter-items", txTime: time)),
          .insert(.init(entityID: "item-4", attributeID: "items/score", value: .number(4), txID: "tx-filter-items", txTime: time)),
          .insert(.init(entityID: "item-4", attributeID: "items/tag", value: .string("purple"), txID: "tx-filter-items", txTime: time)),
          .insert(.init(entityID: "item-4", attributeID: "items/optional", value: .null, txID: "tx-filter-items", txTime: time)),
          .insert(.init(entityID: "item-5", attributeID: "items/score", value: .number(5), txID: "tx-filter-items", txTime: time)),
          .insert(.init(entityID: "item-5", attributeID: "items/tag", value: .string("red"), txID: "tx-filter-items", txTime: time)),
          .insert(.init(entityID: "item-5", attributeID: "items/tag", value: .string("yellow"), txID: "tx-filter-items", txTime: time)),
          .insert(.init(entityID: "item-5", attributeID: "items/optional", value: .string("present"), txID: "tx-filter-items", txTime: time)),
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

    let unknownNotEquals = try await runtime.query(
      .init(
        id: "items.ne-unknown",
        namespace: "items",
        filters: [.notEquals(field: "unknown", value: .string("anything"))],
        order: .init("score")
      )
    )
    expectNoDifference(unknownNotEquals, [])

    let unknownIsNull = try await runtime.query(
      .init(
        id: "items.null-unknown",
        namespace: "items",
        filters: [.isNull(field: "unknown")],
        order: .init("score")
      )
    )
    expectNoDifference(unknownIsNull, [])

    let unknownIsNotNull = try await runtime.query(
      .init(
        id: "items.not-null-unknown",
        namespace: "items",
        filters: [.isNotNull(field: "unknown")],
        order: .init("score")
      )
    )
    expectNoDifference(unknownIsNotNull, [])

    let unknownInsideOr = try await runtime.query(
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
    expectNoDifference(unknownInsideOr, [])

    let mixedTypeComparison = try await runtime.query(
      .init(
        id: "items.mixed-type-range",
        namespace: "items",
        filters: [.greaterThan(field: "tag", value: .number(1))],
        order: .init("score")
      )
    )
    expectNoDifference(mixedTypeComparison, [])
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
}

private struct LegacyCachedQuery: Encodable, Sendable {
  var queryID: String
  var plan: InstantQueryPlan
  var emission: InstantQueryEmission
  var updatedAt: InstantTimestamp
  var storeRevision: Int64
}
