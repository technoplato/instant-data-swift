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
    let prepared = await store.prepare(
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
    let prepared = await store.prepare(
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
