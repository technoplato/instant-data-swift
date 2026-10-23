import CustomDump
import Foundation
import Testing

@testable import InstantSwiftDataCore

/// A query that closes keeps its stored result, and reopening it answers from the device before the server does (#1006).
///
/// Upstream `PersistedObject.unloadKey` (`utils/PersistedObject.ts`) "unloads the key so that it can be garbage collected,
/// but does not delete it": `Reactor.js` `_cleanupQuery` drops a closed query's result from memory, the stored copy stays
/// until the age, entry and size limits collect it (1 year, 1,000 results, 1,000,000 triples), and a later subscription
/// loads it back (`querySubs.waitForKeyToLoad`) and answers from it first.
///
/// The session prune deleted a closed query's result and every entity only that result held (6c6760b4). Reopening a long
/// list then waited on the server: its first page held only the rows other open queries kept, and each later page, a
/// cursor page, showed nothing until the server answered it, one round trip after another, each answer applied behind
/// the server applies that hold the operation gate. A transcript of 986 lines opened with 2 of them and a loading notice.
@Suite(.serialized, .timeLimit(.minutes(2)))
struct InstantStoredResultReloadTests {
  /// The production pruning policy (`InstantRuntimeConfiguration.liveQueryResultPruningPolicy`).
  static let productionPolicy = InstantLiveQueryResultPruningPolicy(
    maxAgeMilliseconds: 1_000 * 60 * 60 * 24 * 7 * 52,
    maxEntries: 1_000,
    maxTripleCount: 1_000_000
  )
  static let pruneTime = InstantTimestamp(milliseconds: 1_800_000_000_000)

  /// A standard live query, closed and pruned, reopens with its rows while the server stays silent.
  @Test
  func aClosedQueryReopensWithItsRowsBeforeTheServerAnswers() async throws {
    let session = LiveReactorParitySession(messages: [liveReactorInitOK(attrs: liveReactorTodoServerAttrs)])
    var configuration = InstantRuntimeConfiguration(
      appID: "stored-result-reload-standard",
      persistenceURL: try Self.temporaryCacheURL(),
      initialAttributes: TodoExample.attributes,
      liveTransport: session.transport
    )
    configuration.liveReconnectSleep = { _ in }
    let runtime = try await InstantRuntime.bootstrap(configuration: configuration)

    // Another query stays open throughout, so the prune below is the session prune that runs while the app is in use.
    let keepAlive = await runtime.observeQueryLease(Self.keepAliveTodosQuery)
    _ = try await runtime.connect()
    let keepAliveQuery = try await Self.registeredQuery(number: 1, in: session)
    await session.enqueue(
      liveReactorAddQueryOK(
        query: keepAliveQuery,
        processedTransactionID: "tx-keep-alive",
        result: Self.todoResult([("todo-keep", "keep", 10)])
      )
    )

    let list = await runtime.observeQueryLease(TodoExample.query)
    let listQuery = try await Self.registeredQuery(number: 2, in: session)
    await session.enqueue(
      liveReactorAddQueryOK(
        query: listQuery,
        processedTransactionID: "tx-list",
        result: Self.todoResult([("todo-1", "one", 1), ("todo-2", "two", 2), ("todo-3", "three", 3)])
      )
    )
    _ = try await Self.emission(of: list.stream, operation: "show the server's list") {
      Set(["todo-1", "todo-2", "todo-3"]).isSubset(of: $0.values.map(\.id))
    }
    await list.cancel()
    try await Self.waitForOp("remove-query", count: 1, in: session)

    _ = try await runtime.pruneLiveQueryResults(policy: Self.productionPolicy, now: Self.pruneTime)

    // The prune took the closed query's rows out of memory: only the open query's row is left there.
    let inMemory = await runtime.observeLocallyLease(TodoExample.query)
    let memoryEmission = try await Self.emission(of: inMemory.stream, operation: "read memory") { _ in true }
    await inMemory.cancel()
    expectNoDifference(memoryEmission.values.map(\.id), ["todo-keep"])

    // The server answers nothing from here on: what the reopened list shows comes from the device.
    let reopened = await runtime.observeQueryLease(TodoExample.query)
    let first = try await Self.emission(of: reopened.stream, operation: "reopen the list") { _ in true }
    expectNoDifference(
      first.values.map(\.id),
      ["todo-1", "todo-2", "todo-3", "todo-keep"],
      "#1006: the reopened list's first answer holds the rows its stored result kept"
    )
    let sent = await session.sentMessages().filter { $0.op == "add-query" }
    expectNoDifference(sent.count, 3, "the reopened list still registers with the server")

    await reopened.cancel()
    await keepAlive.cancel()
    _ = try await runtime.closeConnection()
  }

  /// The playback's shape: an accumulated paged query whose every page loads, closed and pruned, reopens with every
  /// page from the device while the server stays silent.
  @Test
  func aClosedPagedQueryReopensEveryPageBeforeTheServerAnswers() async throws {
    let session = LiveReactorParitySession(messages: [
      liveReactorInitOK(attrs: liveReactorTodoServerAttrs + Self.itemServerAttributes)
    ])
    var configuration = InstantRuntimeConfiguration(
      appID: "stored-result-reload-paged",
      persistenceURL: try Self.temporaryCacheURL(),
      initialAttributes: TodoExample.attributes + Self.itemAttributes,
      makeID: { UUID().uuidString.lowercased() },
      liveTransport: session.transport
    )
    configuration.liveReconnectSleep = { _ in }
    configuration.autoConnectLiveTransport = true
    let runtime = try await InstantRuntime.bootstrap(configuration: configuration)
    let server = ItemServer(session: session, itemCount: 5)
    let serving = Task { await server.serve() }
    defer { serving.cancel() }

    let keepAlive = await runtime.observeQueryLease(Self.keepAliveTodosQuery)
    _ = try await Self.emission(of: keepAlive.stream, operation: "answer the open query") {
      $0.values.map(\.id) == ["todo-keep"]
    }

    let pages = await runtime.subscribeInfiniteQuery(Self.itemsPageQuery, retentionPolicy: .accumulated)
    let whole = try await Self.loadEveryPage(of: pages, expecting: 5)
    expectNoDifference(whole.values.map(\.id), (1...5).map { "item-\($0)" })
    let itemRegistrations = await session.sentMessages().filter {
      $0.op == "add-query" && $0.fields["q"]?.objectValue?["items"] != nil
    }.count
    pages.unsubscribe()
    try await Self.waitForOp("remove-query", count: itemRegistrations, in: session)

    _ = try await runtime.pruneLiveQueryResults(policy: Self.productionPolicy, now: Self.pruneTime)

    await server.goSilent()
    let start = ContinuousClock.now
    let reopened = await runtime.subscribeInfiniteQuery(Self.itemsPageQuery, retentionPolicy: .accumulated)
    let reopenedWhole = try await Self.loadEveryPage(of: reopened, expecting: 5)
    let elapsed = start.duration(to: .now)
    print("#1006 reopened paged query: \(reopenedWhole.values.count) rows in \(elapsed), server silent")
    expectNoDifference(
      reopenedWhole.values.map(\.id),
      (1...5).map { "item-\($0)" },
      "#1006: every page of the reopened query comes from its stored results"
    )
    #expect(!reopenedWhole.canLoadNextPage)

    reopened.unsubscribe()
    await keepAlive.cancel()
    _ = try await runtime.closeConnection()
  }
}

// MARK: - Fixtures

extension InstantStoredResultReloadTests {
  static let keepAliveTodosQuery = InstantQueryPlan(
    id: "todos.keep-alive",
    namespace: TodoExample.namespace,
    filters: [.equals(field: "text", value: .string("keep"))]
  )

  static let itemsPageQuery = InstantQueryPlan(
    id: "items.pages",
    namespace: "items",
    order: InstantQueryOrder("value", .ascending),
    limit: 2
  )

  static let itemAttributes: [InstantAttribute] = [
    .primaryKey(namespace: "items"),
    InstantAttribute(id: "items/value", namespace: "items", name: "value", valueType: .number, isIndexed: true),
  ]

  static let itemServerAttributes: [InstantLiveJSONValue] = [
    itemServerAttribute(id: "server-items-id", name: "id", valueType: "string"),
    itemServerAttribute(id: "server-items-value", name: "value", valueType: "number"),
  ]

  static func itemServerAttribute(id: String, name: String, valueType: String) -> InstantLiveJSONValue {
    .object([
      "cardinality": .string("one"),
      "forward-identity": .array([.string("identity-\(id)"), .string("items"), .string(name)]),
      "id": .string(id),
      "index?": .bool(name == "value"),
      "unique?": .bool(name == "id"),
      "value-type": .string(valueType),
    ])
  }

  /// A server answer holding `todos`, one join row per todo.
  static func todoResult(_ todos: [(id: String, text: String, createdAt: Int64)]) -> [InstantLiveJSONValue] {
    let joinRows = todos.map { todo -> InstantLiveJSONValue in
      let time = InstantLiveJSONValue.number(Double(todo.createdAt))
      return .array([
        .array([.string(todo.id), .string("server-todos-id"), .string(todo.id), time]),
        .array([.string(todo.id), .string("server-todos-text"), .string(todo.text), time]),
        .array([.string(todo.id), .string("server-todos-is-completed"), .bool(false), time]),
        .array([.string(todo.id), .string("server-todos-created-at"), time, time]),
      ])
    }
    return [
      .object([
        "data": .object(["datalog-result": .object(["join-rows": .array(joinRows)])]),
        "child-nodes": .array([]),
      ])
    ]
  }

  static func temporaryCacheURL() throws -> URL {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("instant-stored-result-reload-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory.appendingPathComponent("instant.sqlite")
  }

  /// The `number`th query the runtime registered with the server.
  static func registeredQuery(number: Int, in session: LiveReactorParitySession) async throws -> InstantLiveJSONValue {
    let deadline = ContinuousClock.now + .seconds(5)
    while ContinuousClock.now < deadline {
      let sent = await session.sentMessages().filter { $0.op == "add-query" }
      if sent.count >= number, let query = sent[number - 1].fields["q"] { return query }
      try await Task.sleep(for: .milliseconds(5))
    }
    throw InstantStoredResultReloadTestFailure("No add-query number \(number) within 5 seconds.")
  }

  static func waitForOp(_ op: String, count: Int, in session: LiveReactorParitySession) async throws {
    let deadline = ContinuousClock.now + .seconds(5)
    while ContinuousClock.now < deadline {
      if await session.sentMessages().count(where: { $0.op == op }) >= count { return }
      try await Task.sleep(for: .milliseconds(5))
    }
    throw InstantStoredResultReloadTestFailure("Fewer than \(count) \(op) messages within 5 seconds.")
  }

  /// The first emission of `stream` that `matches`, within 5 seconds.
  static func emission(
    of stream: AsyncStream<InstantQueryEmission>,
    operation: String,
    matching matches: @escaping @Sendable (InstantQueryEmission) -> Bool
  ) async throws -> InstantQueryEmission {
    let found = try await instantLiveWithTimeout(operation: operation, timeoutMilliseconds: 5_000) {
      await stream.first(where: matches)
    }
    guard let found else { throw InstantStoredResultReloadTestFailure("The stream ended before it could \(operation).") }
    return found
  }

  /// Loads the next page whenever the query reports one, as the playback's detail observation does, and returns the
  /// snapshot that holds `expectedCount` rows with no next page; after 5 seconds, the last snapshot.
  static func loadEveryPage(
    of subscription: InstantInfiniteQuerySubscription,
    expecting expectedCount: Int
  ) async throws -> InstantInfiniteQuerySnapshot {
    let last = LastSnapshot()
    do {
      return try await instantLiveWithTimeout(operation: "load every page", timeoutMilliseconds: 5_000) {
        var requestedAtCount = -1
        for await snapshot in subscription.snapshots {
          await last.set(snapshot)
          if snapshot.canLoadNextPage {
            if snapshot.values.count > requestedAtCount {
              requestedAtCount = snapshot.values.count
              subscription.loadNextPage()
            }
          } else if snapshot.values.count == expectedCount {
            return snapshot
          }
        }
        throw InstantStoredResultReloadTestFailure("The paged query ended before every page loaded.")
      }
    } catch {
      // Timed out: the last snapshot says how far the pages got.
      if let snapshot = await last.value { return snapshot }
      throw error
    }
  }
}

private actor LastSnapshot {
  var value: InstantInfiniteQuerySnapshot?
  func set(_ snapshot: InstantInfiniteQuerySnapshot) { value = snapshot }
}

private struct InstantStoredResultReloadTestFailure: Error, CustomStringConvertible {
  var description: String
  init(_ description: String) { self.description = description }
}

/// A server for `items` (values 1 through `itemCount`, one item per value) and `todos` (one todo, "keep"): it answers
/// each add-query from what its options select, the way Instant's server pages a query, until it goes silent.
private actor ItemServer {
  let session: LiveReactorParitySession
  let itemCount: Int
  private var answered = 0
  private var isSilent = false

  init(session: LiveReactorParitySession, itemCount: Int) {
    self.session = session
    self.itemCount = itemCount
  }

  func goSilent() { isSilent = true }

  func serve() async {
    while !Task.isCancelled {
      let queries = await session.sentMessages().filter { $0.op == "add-query" }.compactMap { $0.fields["q"] }
      while answered < queries.count {
        let query = queries[answered]
        answered += 1
        guard !isSilent else { continue }
        await session.enqueue(
          liveReactorAddQueryOK(query: query, processedTransactionID: "tx-\(answered)", result: answer(query))
        )
      }
      try? await Task.sleep(for: .milliseconds(2))
    }
  }

  private func answer(_ query: InstantLiveJSONValue) -> [InstantLiveJSONValue] {
    guard let options = query.objectValue?["items"]?.objectValue?["$"]?.objectValue else {
      return InstantStoredResultReloadTests.todoResult([("todo-keep", "keep", 10)])
    }
    let descending = options["order"]?.objectValue?["value"] == .string("desc")
    func value(_ cursor: InstantLiveJSONValue?) -> Int? {
      guard case let .array(parts)? = cursor, parts.count > 2, case let .number(number) = parts[2] else { return nil }
      return Int(number)
    }
    // Every value in the query's order.
    var values = Array(1...itemCount)
    if descending { values.reverse() }
    func precedes(_ lhs: Int, _ rhs: Int) -> Bool { descending ? lhs > rhs : lhs < rhs }
    let afterInclusive = options["afterInclusive"] == .bool(true)
    let beforeInclusive = options["beforeInclusive"] == .bool(true)
    var selected = values
    if let after = value(options["after"]) {
      selected = selected.filter { afterInclusive ? !precedes($0, after) : precedes(after, $0) }
    }
    if let before = value(options["before"]) {
      selected = selected.filter { beforeInclusive ? !precedes(before, $0) : precedes($0, before) }
    }
    var page = selected
    if case let .number(limit)? = options["limit"] { page = Array(selected.prefix(Int(limit))) }
    let hasNextPage = page.last.map { last in selected.contains { precedes(last, $0) } } ?? false
    let hasPreviousPage = page.first.map { first in values.contains { precedes($0, first) } } ?? false
    let joinRows = page.map { value -> InstantLiveJSONValue in
      .array([
        .array([.string("item-\(value)"), .string("server-items-id"), .string("item-\(value)"), .number(1_767_225_600_000)]),
        .array([
          .string("item-\(value)"), .string("server-items-value"), .number(Double(value)),
          .number(Double(1_767_225_600_000 + value)),
        ]),
      ])
    }
    func cursor(_ value: Int?) -> InstantLiveJSONValue {
      guard let value else { return .null }
      return .array([
        .string("item-\(value)"), .string("server-items-value"), .number(Double(value)),
        .number(Double(1_767_225_600_000 + value)),
      ])
    }
    return [
      .object([
        "child-nodes": .array([]),
        "data": .object([
          "datalog-result": .object(["join-rows": .array(joinRows)]),
          "page-info": .object([
            "items": .object([
              "end-cursor": cursor(page.last),
              "has-next-page?": .bool(hasNextPage),
              "has-previous-page?": .bool(hasPreviousPage),
              "start-cursor": cursor(page.first),
            ])
          ]),
        ]),
      ])
    ]
  }
}
