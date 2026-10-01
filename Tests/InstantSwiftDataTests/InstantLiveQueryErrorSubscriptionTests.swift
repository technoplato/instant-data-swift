import CustomDump
import Dependencies
import Foundation
import InstantSwiftData
import Testing

/// #360: a typed subscription and the fetch property wrappers report a live query's server error without ending.
///
/// The runtime adds the server's error to the query's emissions (`InstantQueryEmission.error`) and repeats the latest
/// values whenever it changes. A typed `subscribe()` yields entities, so it exposes the error beside them as
/// `FetchSubscription.liveQueryError`, and `FetchAll`, `FetchOne`, and `Fetch` report it as `loadError` while they
/// keep observing. Upstream `Reactor.js` `notifyQueryError` calls the query's callback with `{ error }`.
@Suite(.serialized)
struct InstantLiveQueryErrorSubscriptionTests {
  static let stalled = InstantError(
    code: .networkFailed,
    operation: "run Instant live query",
    serverStatus: 500,
    serverType: "operation-timed-out",
    message: "Operation timed out: handle-receive",
    recovery: "The query stays registered and is sent again on this socket after a backoff."
  )

  static func row(_ id: String, text: String) -> InstantEntitySnapshot {
    InstantEntitySnapshot(
      id: id,
      namespace: LiveErrorTodo.instantNamespace,
      values: ["text": .one(.string(text))]
    )
  }

  static func client(_ feed: EmissionFeed) -> InstantSwiftDataClient {
    InstantSwiftDataClient(
      transact: { _ in
        InstantStoreMutationResult(transactionID: "tx", changedEntityIDs: [], tripleCount: 0, emissions: [])
      },
      query: { _ in [] },
      observe: { plan in await feed.stream(for: plan) },
      pendingMutations: { [] },
      localID: { name in "local-\(name)" }
    )
  }

  static func waitFor(
    _ condition: @escaping @Sendable () async -> Bool,
    _ operation: String
  ) async throws {
    let deadline = ContinuousClock.now + .seconds(5)
    while await !condition() {
      guard ContinuousClock.now < deadline else {
        Issue.record("Timed out: \(operation)")
        return
      }
      try await Task.sleep(for: .milliseconds(10))
    }
  }

  @Test
  func aTypedSubscriptionKeepsItsValuesAndReportsTheServerErrorUntilItClears() async throws {
    let feed = EmissionFeed()
    let subscription = await Self.client(feed).subscribe(LiveErrorTodo.query)
    var iterator = subscription.makeAsyncIterator()
    try await Self.waitFor({ await feed.isObserved }, "the subscription observes the query")

    await feed.yield([Self.row("todo-1", text: "shown before the stall")], error: nil)
    let shown = try #require(try await iterator.next())
    expectNoDifference(shown.map(\.text), ["shown before the stall"])
    expectNoDifference(subscription.liveQueryError, nil)

    await feed.yield([Self.row("todo-1", text: "shown before the stall")], error: Self.stalled)
    let failed = try #require(try await iterator.next())
    expectNoDifference(failed.map(\.text), ["shown before the stall"])
    expectNoDifference(subscription.liveQueryError, Self.stalled)

    await feed.yield([Self.row("todo-1", text: "shown before the stall")], error: nil)
    let recovered = try #require(try await iterator.next())
    expectNoDifference(recovered.map(\.text), ["shown before the stall"])
    expectNoDifference(subscription.liveQueryError, nil)
    subscription.cancel()
  }

  @Test
  func fetchAllReportsTheServerErrorAsItsLoadErrorAndKeepsObserving() async throws {
    let feed = EmissionFeed()
    try await withDependencies {
      $0.defaultInstantSwiftData = Self.client(feed)
    } operation: {
      let fetch = FetchAll<LiveErrorTodo>(LiveErrorTodo.query)
      _ = fetch.wrappedValue
      try await Self.waitFor({ await feed.isObserved }, "FetchAll observes the query")

      await feed.yield([Self.row("todo-2", text: "before")], error: nil)
      try await Self.waitFor({ fetch.wrappedValue.map(\.text) == ["before"] }, "the first rows")
      expectNoDifference(fetch.loadError, nil)

      await feed.yield([Self.row("todo-2", text: "before")], error: Self.stalled)
      try await Self.waitFor({ fetch.loadError == Self.stalled }, "the server error as loadError")
      expectNoDifference(fetch.wrappedValue.map(\.text), ["before"])
      expectNoDifference(fetch.isLoading, false)

      await feed.yield([Self.row("todo-2", text: "after")], error: nil)
      try await Self.waitFor({ fetch.wrappedValue.map(\.text) == ["after"] }, "rows after the recovery")
      expectNoDifference(fetch.loadError, nil)
    }
  }
}

/// A query stream the test drives one emission at a time.
actor EmissionFeed {
  private var continuation: AsyncStream<InstantQueryEmission>.Continuation?
  private var queryID = ""
  private var sequence: Int64 = 0

  var isObserved: Bool { continuation != nil }

  func stream(for plan: InstantQueryPlan) -> AsyncStream<InstantQueryEmission> {
    let (stream, continuation) = AsyncStream<InstantQueryEmission>.makeStream(
      bufferingPolicy: .bufferingNewest(1)
    )
    self.continuation = continuation
    queryID = plan.id
    return stream
  }

  func yield(_ values: [InstantEntitySnapshot], error: InstantError?) {
    sequence += 1
    continuation?.yield(
      InstantQueryEmission(queryID: queryID, sequence: sequence, values: values, error: error)
    )
  }
}

private struct LiveErrorTodo: Hashable, Codable, InstantEntityModel {
  var id: InstantID<LiveErrorTodo>
  var text: String

  static let instantNamespace = "live_query_error_todos"
  static let text = InstantAttributePath<LiveErrorTodo, String>("text")
  static let instantAttributes = [
    InstantAttribute(
      id: "live-query-error-todos/text",
      namespace: instantNamespace,
      name: "text",
      valueType: .string,
      isIndexed: true
    )
  ]

  init(snapshot: InstantEntitySnapshot) throws {
    id = InstantID(rawValue: snapshot.id)
    guard case let .string(text) = snapshot.values["text"]?.first else {
      throw InstantError(
        code: .validationFailed,
        operation: "decode live query error todo",
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
