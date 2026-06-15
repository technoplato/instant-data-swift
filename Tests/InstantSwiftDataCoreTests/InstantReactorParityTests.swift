import CustomDump
import Foundation
@testable import InstantSwiftDataCore
import Testing

@Suite(.serialized)
struct InstantReactorParityTests {
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
