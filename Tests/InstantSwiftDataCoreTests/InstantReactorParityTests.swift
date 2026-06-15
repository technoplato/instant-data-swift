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
      namespace: TodoExample.namespace,
      order: InstantQueryOrder("createdAt", .ascending)
    )
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "reactor-query-subs-parity",
        persistenceURL: cacheURL,
        initialAttributes: TodoExample.attributes,
        now: { cachedAt }
      )
    )
    try await runtime.transact(
      InstantStoreTransaction(
        id: "tx-reactor-query-subs-seed",
        operations: TodoExample.createOperations(
          id: "todo-reactor-query-subs",
          text: "restore cached querySub",
          createdAt: createdAt,
          transactionID: "tx-reactor-query-subs-seed"
        )
      ),
      createdAt: createdAt
    )

    let emission = try await runtime.queryOnce(plan)
    let cachedQuery = try #require(try await runtime.cachedQuery(plan))
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
  "upstream/instant/client/packages/core/__tests__/src/Reactor.test.ts querySubs round-trips [adapted: Swift writes queryOnce results to the SQLite query cache and relaunches cachedQuery/queryOnce fallback instead of IndexedDB querySubs callbacks.]"

private let reactorOptimisticRefreshSource =
  "upstream/instant/client/packages/core/__tests__/src/Reactor.test.ts optimisticTx is not overwritten by refresh-ok [adapted: Swift has no raw refresh-ok handler; it confirms earlier outbox mutations and runs queryOnce/cache refresh without replacing the later optimistic local write.]"

private let reactorRewriteSource =
  "upstream/instant/client/packages/core/__tests__/src/Reactor.test.ts rewrite mutations [adapted: Swift pending mutations store typed transactions and lower them to stable transport steps over declared server attributes instead of rewriting cached JavaScript tx-steps.]"

private let reactorRewriteMultipleSource =
  "upstream/instant/client/packages/core/__tests__/src/Reactor.test.ts rewrite mutations works with multiple transactions [adapted: Swift re-lowers every pending typed transaction to the same transport steps after persistence instead of rewriting a JavaScript pendingMutations map.]"

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
    value: .array([.string("users/handle"), .string("stopa")])
  ),
  .addTriple(
    entity: .id("bookshelfId"),
    attributeID: "bookshelves/id",
    value: .string("bookshelfId")
  ),
  .addTriple(
    entity: .id("bookshelfId"),
    attributeID: "bookshelves/users",
    value: .array([.string("users/handle"), .string("stopa")])
  ),
  .retractTriple(
    entity: .id("bookshelfId"),
    attributeID: "bookshelves/users",
    value: .array([.string("users/handle"), .string("joe")])
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
