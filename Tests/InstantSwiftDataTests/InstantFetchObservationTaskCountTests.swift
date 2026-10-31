import CustomDump
import Dependencies
import Foundation
import InstantSwiftData
import Testing

/// #1493: a typed subscription keeps no library task of its own, and a fetch wrapper keeps one: its own consumer.
///
/// On top of the runtime's five forwarding tasks, a live typed subscription added a task that decoded each emission,
/// `map` (which `FetchOne` uses) one more, and a wrapper's automatic observation its consumer: up to eight tasks per
/// live query, each resumed by every emission. A typed subscription now decodes in its consumer's own pull, and `map`
/// composes its transform onto the same pull.
@Suite(.serialized)
struct InstantFetchObservationTaskCountTests {
  static func client(_ name: String) async throws -> (client: InstantSwiftDataClient, runtime: InstantRuntime) {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("InstantFetchObservationTaskCountTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    var configuration = InstantRuntimeConfiguration(
      appID: "fetch-observation-task-count-\(name)",
      persistenceURL: directory.appendingPathComponent("state.sqlite"),
      initialAttributes: TaskCountTodo.instantAttributes
    )
    // Never connected (automatic connection is off), so each observation is a live query's whole chain without a
    // socket.
    configuration.liveTransport = .connectionAttempts { _ in throw TaskCountNoServer() }
    let runtime = try await InstantRuntime.bootstrap(configuration: configuration)
    _ = try await runtime.applyServerTransaction(
      InstantStoreTransaction(
        id: "seed",
        operations: [
          .insert(
            InstantTriple(
              entityID: "todo-1",
              attributeID: TaskCountTodo.idAttributeID,
              value: .string("todo-1"),
              txID: "seed",
              txTime: InstantTimestamp(milliseconds: 1)
            )
          ),
          .insert(
            InstantTriple(
              entityID: "todo-1",
              attributeID: TaskCountTodo.textAttributeID,
              value: .string("observed"),
              txID: "seed",
              txTime: InstantTimestamp(milliseconds: 1)
            )
          ),
        ]
      ),
      processedTransactionID: "1"
    )
    return (InstantSwiftDataClient(runtime: runtime), runtime)
  }

  @Test
  func anOpenTypedSubscriptionKeepsNoLibraryTask() async throws {
    let (client, _) = try await Self.client("typed")
    let census = InstantObservationTaskCensus()
    let subscription = await InstantObservationTaskCensus.$current.withValue(census) {
      await client.subscribe(TaskCountTodo.query)
    }
    var iterator = subscription.makeAsyncIterator()
    let first = try #require(try await iterator.next())
    expectNoDifference(first.map(\.text), ["observed"])
    expectNoDifference(census.aliveCount, 0, "six before #1493: the runtime's five and the decoding bridge")
    subscription.cancel()
    try await subscription.task
  }

  @Test
  func anOpenMappedSubscriptionKeepsNoLibraryTask() async throws {
    let (client, _) = try await Self.client("mapped")
    let census = InstantObservationTaskCensus()
    let subscription = await InstantObservationTaskCensus.$current.withValue(census) {
      await client.subscribe(TaskCountTodo.query).map(\.first)
    }
    var iterator = subscription.makeAsyncIterator()
    let first = try #require(try await iterator.next())
    expectNoDifference(first?.text, "observed")
    expectNoDifference(census.aliveCount, 0, "seven before #1493: FetchOne's shape adds map's task")
    subscription.cancel()
    try await subscription.task
  }

  @Test
  func fetchAllKeepsOneLibraryTaskItsOwnConsumer() async throws {
    let (client, runtime) = try await Self.client("fetch-all")
    let census = InstantObservationTaskCensus()
    try await withDependencies {
      $0.defaultInstantSwiftData = client
    } operation: {
      let fetch = InstantObservationTaskCensus.$current.withValue(census) {
        let fetch = FetchAll<TaskCountTodo>(TaskCountTodo.query)
        // The first read starts the wrapper's automatic observation, inside the census.
        _ = fetch.wrappedValue
        return fetch
      }
      let deadline = ContinuousClock.now + .seconds(5)
      while fetch.wrappedValue.map(\.text) != ["observed"] {
        guard ContinuousClock.now < deadline else {
          Issue.record("Timed out waiting for FetchAll's first value")
          return
        }
        try await Task.sleep(for: .milliseconds(10))
      }
      expectNoDifference(census.aliveCount, 1, "seven before #1493: the runtime's five, the bridge and the consumer")
      withExtendedLifetime(fetch) {}
    }
    _ = runtime
  }
}

private struct TaskCountNoServer: Error {}

private struct TaskCountTodo: Hashable, Codable, InstantEntityModel {
  var id: InstantID<TaskCountTodo>
  var text: String

  static let instantNamespace = "task_count_todos"
  static let idAttributeID = InstantAttribute.primaryKeyID(namespace: instantNamespace)
  static let textAttributeID = "\(instantNamespace)/text"
  static let text = InstantAttributePath<TaskCountTodo, String>("text")
  static let instantAttributes = [
    InstantAttribute.primaryKey(namespace: instantNamespace),
    InstantAttribute(
      id: textAttributeID,
      namespace: instantNamespace,
      name: "text",
      valueType: .string,
      isIndexed: true
    ),
  ]

  init(snapshot: InstantEntitySnapshot) throws {
    id = InstantID(rawValue: snapshot.id)
    guard case let .string(text) = snapshot.values["text"]?.first else {
      throw InstantError(
        code: .validationFailed,
        operation: "decode task count todo",
        namespace: Self.instantNamespace,
        path: "text",
        localID: snapshot.id,
        message: "Expected a string text value.",
        recovery: "Store a string in the text attribute before decoding this fixture."
      )
    }
    self.text = text
  }
}
