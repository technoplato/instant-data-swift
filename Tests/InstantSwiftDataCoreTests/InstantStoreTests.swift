import CustomDump
import Foundation
import InstantSwiftDataCore
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

    let posts = await runtime.query(.init(id: "posts", namespace: "posts"))
    expectNoDifference(posts.map { $0.values["author"]?.first }, [.ref("user-2")])

    try await runtime.transact(
      InstantStoreTransaction(id: "tx-3", operations: [.deleteEntity("user-2")]),
      createdAt: time
    )

    let cleanedPosts = await runtime.query(.init(id: "posts", namespace: "posts"))
    expectNoDifference(cleanedPosts.map { $0.values["author"]?.first }, [nil])
    expectNoDifference(cleanedPosts.map { $0.values["title"]?.first }, [.string("Hello")])
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

    let ordered = await runtime.query(
      .init(id: "items.ordered", namespace: "items", order: .init("score"))
    )
    expectNoDifference(ordered.map(\.id), ["item-2", "item-10"])

    let filtered = await runtime.query(
      .init(
        id: "items.filtered",
        namespace: "items",
        filters: [.equals(field: "tag", value: .string("b"))]
      )
    )
    expectNoDifference(filtered.map(\.id), ["item-10"])
  }

  private func temporaryCacheURL() throws -> URL {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("InstantSwiftDataTests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory.appendingPathComponent("state.sqlite")
  }
}
