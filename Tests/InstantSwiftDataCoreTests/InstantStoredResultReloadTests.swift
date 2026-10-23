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
/// the server applies that hold the operation gate.
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

extension InstantStoredResultReloadTests {
  /// A value kept on disk rather than in memory (a transcript line's text and words) comes back with the reopened rows.
  @Test
  func aReopenedQueryHydratesTheDeferredValuesItsStoredResultKept() async throws {
    let session = LiveReactorParitySession(messages: [liveReactorInitOK(attrs: liveReactorTodoServerAttrs)])
    // A deferred value is one no query filters or orders by, so `text` is not indexed here.
    let attributes = TodoExample.attributes.map { attribute in
      var attribute = attribute
      if attribute.id == "todos/text" { attribute.isIndexed = false }
      return attribute
    }
    var configuration = InstantRuntimeConfiguration(
      appID: "stored-result-reload-deferred",
      persistenceURL: try Self.temporaryCacheURL(),
      initialAttributes: attributes,
      liveTransport: session.transport
    )
    configuration.deferredValueResidency = InstantDeferredValueResidencyPolicy(attributeIDs: ["todos/text"])
    configuration.liveReconnectSleep = { _ in }
    let runtime = try await InstantRuntime.bootstrap(configuration: configuration)

    let keepAlive = await runtime.observeQueryLease(
      InstantQueryPlan(
        id: "todos.keep-alive",
        namespace: TodoExample.namespace,
        filters: [.equals(field: "isCompleted", value: .bool(true))]
      )
    )
    _ = try await runtime.connect()
    await session.enqueue(
      liveReactorAddQueryOK(
        query: try await Self.registeredQuery(number: 1, in: session),
        processedTransactionID: "tx-keep-alive",
        result: Self.todoResult([("todo-keep", "keep", 10)])
      )
    )
    let list = await runtime.observeQueryLease(TodoExample.query)
    await session.enqueue(
      liveReactorAddQueryOK(
        query: try await Self.registeredQuery(number: 2, in: session),
        processedTransactionID: "tx-list",
        result: Self.todoResult([("todo-1", "one", 1), ("todo-2", "two", 2)])
      )
    )
    _ = try await Self.emission(of: list.stream, operation: "show the server's list") {
      Set(["todo-1", "todo-2"]).isSubset(of: $0.values.map(\.id))
    }
    await list.cancel()
    try await Self.waitForOp("remove-query", count: 1, in: session)
    _ = try await runtime.pruneLiveQueryResults(policy: Self.productionPolicy, now: Self.pruneTime)

    let reopened = await runtime.observeQueryLease(TodoExample.query)
    let first = try await Self.emission(of: reopened.stream, operation: "reopen the list") { _ in true }
    let texts = try TodoExample.decode(first.values).map(\.text)
    expectNoDifference(texts, ["one", "two", "keep"], "#1006: deferred values come back with the reopened rows")

    await reopened.cancel()
    await keepAlive.cancel()
    _ = try await runtime.closeConnection()
  }

  /// Unloaded results count toward the policy's limits and go first, oldest first; an open query's result never goes.
  @Test
  func thePolicyCollectsUnloadedResultsOldestFirst() async throws {
    let persistence = try SQLitePersistenceStore(fileURL: try Self.temporaryCacheURL())
    try await persistence.bootstrap()
    let results = (0..<5).map { index in
      InstantPersistedLiveQueryResult(
        replacement: InstantLiveQueryResultReplacement(
          key: "query-\(index)",
          triples: Self.todoTriples(index: index),
          pageInfo: nil
        ),
        updatedAt: InstantTimestamp(milliseconds: Int64(index + 1))
      )
    }
    try await Self.save(results, in: persistence)

    // Query 4 stays open: the session prune unloads 0 through 3.
    let unload = try await persistence.pruneLiveQueryResults(
      policy: Self.productionPolicy,
      now: InstantTimestamp(milliseconds: 10),
      preservingQueryKeys: ["query-4"]
    )
    expectNoDifference(unload.result.unloadedQueryKeys.sorted(), ["query-0", "query-1", "query-2", "query-3"])
    expectNoDifference(unload.result.remainingQueryKeys, ["query-4"])
    for index in 0..<4 {
      #expect(try await persistence.unloadedLiveQueryResult(key: "query-\(index)") != nil)
    }

    // Three results at most, loaded and unloaded together: the two oldest unloaded go.
    _ = try await persistence.pruneLiveQueryResults(
      policy: InstantLiveQueryResultPruningPolicy(maxEntries: 3),
      now: InstantTimestamp(milliseconds: 11),
      preservingQueryKeys: ["query-4"]
    )
    var kept: [String] = []
    for index in 0..<4 where try await persistence.unloadedLiveQueryResult(key: "query-\(index)") != nil {
      kept.append("query-\(index)")
    }
    expectNoDifference(kept, ["query-2", "query-3"])

    // Past the age limit, the rest go too.
    _ = try await persistence.pruneLiveQueryResults(
      policy: InstantLiveQueryResultPruningPolicy(maxAgeMilliseconds: 5),
      now: InstantTimestamp(milliseconds: 100),
      preservingQueryKeys: ["query-4"]
    )
    for index in 0..<4 {
      #expect(try await persistence.unloadedLiveQueryResult(key: "query-\(index)") == nil)
    }
  }

  /// A result the server sends again for a key replaces the copy a prune unloaded: a key lives in one table.
  @Test
  func aSavedResultSupersedesItsUnloadedCopy() async throws {
    let persistence = try SQLitePersistenceStore(fileURL: try Self.temporaryCacheURL())
    try await persistence.bootstrap()
    let open = InstantPersistedLiveQueryResult(
      replacement: InstantLiveQueryResultReplacement(key: "query-open", triples: Self.todoTriples(index: 0), pageInfo: nil),
      updatedAt: InstantTimestamp(milliseconds: 1)
    )
    let closed = InstantPersistedLiveQueryResult(
      replacement: InstantLiveQueryResultReplacement(key: "query-closed", triples: Self.todoTriples(index: 1), pageInfo: nil),
      updatedAt: InstantTimestamp(milliseconds: 2)
    )
    try await Self.save([open, closed], in: persistence)
    _ = try await persistence.pruneLiveQueryResults(
      policy: Self.productionPolicy,
      now: InstantTimestamp(milliseconds: 3),
      preservingQueryKeys: ["query-open"]
    )
    #expect(try await persistence.unloadedLiveQueryResult(key: "query-closed") != nil)

    var answered = closed
    answered.updatedAt = InstantTimestamp(milliseconds: 4)
    try await Self.save([answered], in: persistence)
    #expect(try await persistence.unloadedLiveQueryResult(key: "query-closed") == nil)
  }

  static func todoTriples(index: Int) -> [InstantTriple] {
    TodoExample.createOperations(
      id: "todo-\(index)",
      text: "Todo \(index)",
      createdAt: InstantTimestamp(milliseconds: Int64(index + 1)),
      transactionID: "seed-todo-\(index)"
    ).compactMap { operation in
      guard case let .insert(triple) = operation else { return nil }
      return triple
    }
  }

  /// Saves `results` and their facts as a server refresh does.
  static func save(
    _ results: [InstantPersistedLiveQueryResult],
    in persistence: SQLitePersistenceStore
  ) async throws {
    let state = try await persistence.loadCompactState()
    var triples = state.snapshot.store.triples
    triples.append(contentsOf: results.flatMap(\.triples))
    let didSave = try await persistence.saveLiveRefresh(
      InstantPersistenceSnapshot(
        store: InstantStoreSnapshot(attributes: TodoExample.attributes, triples: triples),
        outbox: []
      ),
      queryResults: results,
      storeChanged: true,
      outboxChanged: false,
      metadataKey: "test.stored-result-reload",
      metadataValue: "seeded",
      metadataUpdatedAt: results.map(\.updatedAt).max() ?? InstantTimestamp(milliseconds: 0),
      expectedStoreRevision: state.storeRevision,
      expectedOutboxRevision: state.outboxRevision,
      expectedAttributeRevision: state.attributeRevision
    )
    expectNoDifference(didSave, true)
  }
}

extension InstantStoredResultReloadTests {
  /// The playback transcript's shape (#1006): 986 lines read 256 to a page, all of them, with each server answer taking
  /// `answerDelay`. Prints how long the first open and the reopen take to hold every line; a silent server on reopen.
  @Test(arguments: [Duration.milliseconds(300)])
  func aTranscriptOfNineHundredEightySixLinesOpensAndReopens(answerDelay: Duration) async throws {
    let lineCount = 986
    let session = LiveReactorParitySession(messages: [
      liveReactorInitOK(attrs: liveReactorTodoServerAttrs + Self.itemServerAttributes)
    ])
    var configuration = InstantRuntimeConfiguration(
      appID: "stored-result-reload-transcript",
      persistenceURL: try Self.temporaryCacheURL(),
      initialAttributes: TodoExample.attributes + Self.itemAttributes,
      makeID: { UUID().uuidString.lowercased() },
      liveTransport: session.transport
    )
    configuration.liveReconnectSleep = { _ in }
    configuration.autoConnectLiveTransport = true
    let runtime = try await InstantRuntime.bootstrap(configuration: configuration)
    let server = ItemServer(session: session, itemCount: lineCount, answerDelay: answerDelay)
    let serving = Task { await server.serve() }
    defer { serving.cancel() }
    let keepAlive = await runtime.observeQueryLease(Self.keepAliveTodosQuery)
    _ = try await Self.emission(of: keepAlive.stream, operation: "answer the open query") {
      $0.values.map(\.id) == ["todo-keep"]
    }
    var transcriptQuery = Self.itemsPageQuery
    transcriptQuery.limit = 256

    let firstOpenStart = ContinuousClock.now
    let pages = await runtime.subscribeInfiniteQuery(transcriptQuery, retentionPolicy: .accumulated)
    let whole = try await Self.loadEveryPage(of: pages, expecting: lineCount, within: .seconds(30))
    let firstOpen = firstOpenStart.duration(to: .now)
    expectNoDifference(whole.values.count, lineCount)
    let itemRegistrations = await session.sentMessages().filter {
      $0.op == "add-query" && $0.fields["q"]?.objectValue?["items"] != nil
    }.count
    pages.unsubscribe()
    try await Self.waitForOp("remove-query", count: itemRegistrations, in: session)
    _ = try await runtime.pruneLiveQueryResults(policy: Self.productionPolicy, now: Self.pruneTime)

    await server.goSilent()
    let reopenStart = ContinuousClock.now
    let reopened = await runtime.subscribeInfiniteQuery(transcriptQuery, retentionPolicy: .accumulated)
    let reopenedWhole = try await Self.loadEveryPage(of: reopened, expecting: lineCount, within: .seconds(5))
    let reopen = reopenStart.duration(to: .now)
    print(
      "#1006 transcript of \(lineCount) lines, 256 a page, server answer \(answerDelay): first open \(whole.values.count) "
        + "lines in \(firstOpen) over \(itemRegistrations) registrations; reopen with the server silent "
        + "\(reopenedWhole.values.count) lines in \(reopen)"
    )
    expectNoDifference(reopenedWhole.values.count, lineCount, "#1006: every line reopens from the device")
    #expect(reopen < .seconds(1))

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
    let deadline = ContinuousClock.now + InstantTestWait.hang
    while ContinuousClock.now < deadline {
      let sent = await session.sentMessages().filter { $0.op == "add-query" }
      if sent.count >= number, let query = sent[number - 1].fields["q"] { return query }
      try await Task.sleep(for: .milliseconds(5))
    }
    throw InstantStoredResultReloadTestFailure("No add-query number \(number) within \(InstantTestWait.hang).")
  }

  static func waitForOp(_ op: String, count: Int, in session: LiveReactorParitySession) async throws {
    let deadline = ContinuousClock.now + InstantTestWait.hang
    while ContinuousClock.now < deadline {
      if await session.sentMessages().count(where: { $0.op == op }) >= count { return }
      try await Task.sleep(for: .milliseconds(5))
    }
    throw InstantStoredResultReloadTestFailure("Fewer than \(count) \(op) messages within \(InstantTestWait.hang).")
  }

  /// The first emission of `stream` that `matches`, up to the hang bound (#1021).
  static func emission(
    of stream: AsyncStream<InstantQueryEmission>,
    operation: String,
    matching matches: @escaping @Sendable (InstantQueryEmission) -> Bool
  ) async throws -> InstantQueryEmission {
    let found = try await instantLiveWithTimeout(operation: operation, timeoutMilliseconds: InstantTestWait.hangMilliseconds) {
      await stream.first(where: matches)
    }
    guard let found else { throw InstantStoredResultReloadTestFailure("The stream ended before it could \(operation).") }
    return found
  }

  /// Loads the next page whenever the query reports one, as the playback's detail observation does, and returns the
  /// snapshot that holds `expectedCount` rows with no next page; after `limit`, the last snapshot.
  static func loadEveryPage(
    of subscription: InstantInfiniteQuerySubscription,
    expecting expectedCount: Int,
    within limit: Duration = InstantTestWait.hang
  ) async throws -> InstantInfiniteQuerySnapshot {
    let last = LastSnapshot()
    let limitMilliseconds = UInt64(limit.components.seconds * 1_000)
    do {
      return try await instantLiveWithTimeout(operation: "load every page", timeoutMilliseconds: limitMilliseconds) {
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
  /// How long each answer takes, a round trip and the server apply behind it.
  let answerDelay: Duration
  private var answered = 0
  private var isSilent = false

  init(session: LiveReactorParitySession, itemCount: Int, answerDelay: Duration = .zero) {
    self.session = session
    self.itemCount = itemCount
    self.answerDelay = answerDelay
  }

  func goSilent() { isSilent = true }

  func serve() async {
    while !Task.isCancelled {
      let queries = await session.sentMessages().filter { $0.op == "add-query" }.compactMap { $0.fields["q"] }
      while answered < queries.count {
        let query = queries[answered]
        answered += 1
        guard !isSilent else { continue }
        if answerDelay > .zero { try? await Task.sleep(for: answerDelay) }
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
