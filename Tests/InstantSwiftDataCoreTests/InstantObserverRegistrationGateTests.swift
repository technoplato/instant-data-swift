// History
// 2026-10-24  #1131  Created. Registering an observer held the operation gate across its socket send and across the
//                    reload of its closed stored result: on builds 121-126 one registration held the gate 5.0-7.8 s with
//                    about 11 callers queued, and in the concurrency audit's exercises a registration held it 153 ms over
//                    a 150 ms socket and 1,718 ms to reload the `$files` list's 75,640 facts.
// 2026-10-24  #1131  A closed result loads back in bounded holds: with its read out of the gate, the `$files` reload's
//                    commit still held it about 1.3 s.

import CustomDump
import Foundation
import Testing

@testable import InstantSwiftDataCore

/// Registering an observer holds the operation gate only for what must be exclusive (#1131): recording the
/// registration, which the prune reads to keep a result, and committing a closed result's reload. Its `add-query` goes
/// out after it leaves the gate, and its closed result is read and decoded before it enters.
///
/// Upstream `Reactor.js` `subscribeQuery` records the query (`querySubs`), sends `add-query` with a synchronous
/// `ws.send`, and loads a closed query's stored result (`querySubs.waitForKeyToLoad`) without blocking any other caller;
/// JavaScript has no gate to hold. Swift's gate serializes the runtime's multi-await critical sections, so this keeps
/// the network and the result-sized read out of them.
@Suite(.serialized, .timeLimit(.minutes(2)))
struct InstantObserverRegistrationGateTests {
  /// While the socket has not taken an observer's `add-query` (a full send buffer, a slow network), the operation gate
  /// is free and a local write lands.
  @Test
  func anObserversAddQuerySendHoldsNoGate() async throws {
    let session = LiveReactorParitySession(messages: [liveReactorInitOK(attrs: liveReactorTodoServerAttrs)])
    let stall = InstantStalledLiveSend(op: "add-query")
    let runtime = try await Self.runtime("observer-registration-send", transport: stall.transport(over: session))
    _ = try await runtime.connect()

    let observing = Task { await runtime.observeQueryLease(TodoExample.query) }
    try await stall.waitUntilHolding()

    let holder = runtime.operationGateSnapshot().holder
    let write = await Self.finishes(within: .seconds(4)) {
      try await InstantOfflineRuntimeFixture.createTodo("during-send", in: runtime)
    }
    stall.release()
    try await write.work.value
    let lease = await observing.value

    #expect(holder != "observe standard live query", "#1131: the registration held the gate across its send")
    #expect(write.finished, "#1131: a local write waited for an observer's add-query to reach the socket")

    // The registration still reaches the server, once, and its answer still reaches the observer.
    await session.enqueue(
      liveReactorAddQueryOK(
        query: try await InstantStoredResultReloadTests.registeredQuery(number: 1, in: session),
        processedTransactionID: "tx-list",
        result: InstantStoredResultReloadTests.todoResult([("todo-1", "one", 1)])
      )
    )
    _ = try await InstantStoredResultReloadTests.emission(of: lease.stream, operation: "show the server's answer") {
      $0.values.map(\.id).contains("todo-1")
    }
    let sent = await session.sentMessages().filter { $0.op == "add-query" }
    expectNoDifference(sent.count, 1)

    await lease.cancel()
    _ = try await runtime.closeConnection()
  }

  /// A reopened query reads and decodes its closed stored result before it takes the operation gate: while that read
  /// runs, the gate is free and a local write lands, and the reopened query still answers from the stored result first.
  @Test
  func aClosedResultsReloadReadsOutsideTheGate() async throws {
    let session = LiveReactorParitySession(messages: [liveReactorInitOK(attrs: liveReactorTodoServerAttrs)])
    let pause = InstantPausePoint()
    let runtime = try await Self.runtime("observer-registration-reload", transport: session.transport) {
      $0.onUnloadedLiveQueryResultReadForTesting = { _ in await pause.pauseOnce() }
    }
    let keepAlive = try await Self.openClosePrune(runtime: runtime, session: session)

    let reopening = Task { await runtime.observeQueryLease(TodoExample.query) }
    try await pause.waitUntilEntered()

    let holder = runtime.operationGateSnapshot().holder
    let write = await Self.finishes(within: .seconds(4)) {
      try await InstantOfflineRuntimeFixture.createTodo("during-reload", in: runtime)
    }
    pause.release()
    try await write.work.value
    let reopened = await reopening.value

    #expect(holder != "observe standard live query", "#1131: the reload read its stored result holding the gate")
    #expect(write.finished, "#1131: a local write waited for a closed result's read")

    // #1006 still holds: the first answer comes from the stored result while the server stays silent.
    let first = try await InstantStoredResultReloadTests.emission(of: reopened.stream, operation: "reopen the list") {
      _ in true
    }
    #expect(
      Set(["todo-1", "todo-2", "todo-3"]).isSubset(of: first.values.map(\.id)),
      "the reopened list's first answer holds its stored rows, not \(first.values.map(\.id))"
    )

    await reopened.cancel()
    await keepAlive.cancel()
    _ = try await runtime.closeConnection()
  }

  /// A reload begins from the closed result stored now, not the one it read before the operation gate (#1131): here the
  /// query was answered again with a fourth todo and unloaded again after the read. A second observer cannot do this
  /// meanwhile, since it waits for the first one's registration (``aSecondObserverWaitsForTheReloadOfItsQuery()``),
  /// but a reload never commits a row it did not read.
  @Test
  func aReloadBeginsFromTheRowStoredNowNotTheOneItRead() async throws {
    let persistence = try SQLitePersistenceStore(fileURL: try InstantStoredResultReloadTests.temporaryCacheURL())
    try await persistence.bootstrap()
    try await InstantStoredResultReloadTests.save([Self.closedResult(todos: 3, at: 1)], in: persistence)
    try await Self.unloadEverything(in: persistence, at: 2)
    let read = try #require(try await persistence.readConnection.unloadedLiveQueryResult(key: "query-closed"))

    try await InstantStoredResultReloadTests.save([Self.closedResult(todos: 4, at: 3)], in: persistence)
    try await Self.unloadEverything(in: persistence, at: 4)
    let begun = try #require(try await persistence.beginUnloadedLiveQueryResultReload(read))

    #expect(begun.readAgain)
    expectNoDifference(Set(begun.result.triples.map(\.entityID)), ["todo-0", "todo-1", "todo-2", "todo-3"])
    #expect(try await persistence.unloadedLiveQueryResult(key: "query-closed") == nil, "the row is a stored result again")
  }

  /// A chunk of a reload writes nothing once a server answer replaced the row the reload moved back (#1131): the
  /// server's facts stand, and the entities the answer left out stay out.
  @Test
  func aReloadChunkWritesNothingOnceAServerAnswerReplacedItsRow() async throws {
    let persistence = try SQLitePersistenceStore(fileURL: try InstantStoredResultReloadTests.temporaryCacheURL())
    try await persistence.bootstrap()
    try await InstantStoredResultReloadTests.save([Self.closedResult(todos: 3, at: 1)], in: persistence)
    try await Self.unloadEverything(in: persistence, at: 2)
    let read = try #require(try await persistence.readConnection.unloadedLiveQueryResult(key: "query-closed"))
    let begun = try #require(try await persistence.beginUnloadedLiveQueryResultReload(read))

    try await InstantStoredResultReloadTests.save([Self.closedResult(todos: 1, at: 5)], in: persistence)
    let entityTriples = Dictionary(grouping: begun.result.triples, by: \.entityID)
    let chunk = try await persistence.reloadUnloadedLiveQueryResultChunk(
      key: "query-closed",
      rowTripleCount: begun.rowTripleCount,
      rowUpdatedAtMilliseconds: begun.rowUpdatedAtMilliseconds,
      entityTriples: entityTriples,
      ownedFacts: begun.result.triples,
      residentEntityIDs: []
    )

    #expect(chunk == nil)
  }
}

// MARK: - The wire's order

extension InstantObserverRegistrationGateTests {
  /// A registration whose last observer leaves before its owed add-query went out sends that add-query first, then
  /// its remove-query (#1131): the wire reads add then remove, as upstream's synchronous `ws.send` at subscription made
  /// it, and the late send after them sends nothing. Under load an infinite query's frozen chunk was evicted that fast
  /// and the wire read remove alone (`liveWindowEvictsAndCancelsOppositeCursorChunkInBothDirections`).
  @Test
  func anUnregistrationBeforeTheOwedSendSendsAddThenRemove() async throws {
    let session = LiveReactorParitySession(messages: [liveReactorInitOK(attrs: liveReactorTodoServerAttrs)])
    let live = InstantRuntimeLiveSession()
    try await live.open(
      request: InstantLiveSessionRequest(appID: "observer-registration-wire-order"),
      transport: session.transport,
      makeID: { UUID().uuidString.lowercased() }
    )
    let query = try InstantLiveQueryEncoder.encode(TodoExample.query)
    let key = try InstantLiveQueryEncoder.registrationKey(for: query)

    let owed = try #require(await live.recordQueryRegistration(query, key: key))
    _ = try await live.unregisterQuery(key: key, clientEventID: "event-remove")
    try await live.sendQueryRegistration(owed, clientEventID: "event-late")

    let ops = await session.sentMessages().map(\.op).filter { $0 != "init" }
    expectNoDifference(ops, ["add-query", "remove-query"])
    await live.close()
  }
}

// MARK: - A reload in bounded holds

extension InstantObserverRegistrationGateTests {
  /// A closed result loads back in holds of a bounded size, and the registration's own hold loads none of it (#1131):
  /// with 4 facts a hold, the 12-fact list loads back in one hold that moves its row and three that load its entities.
  /// The `$files` list's 75,640 facts held the gate about 1.3 s in one hold after the read moved out of it.
  @Test
  func aClosedResultReloadsInBoundedHolds() async throws {
    let session = LiveReactorParitySession(messages: [liveReactorInitOK(attrs: liveReactorTodoServerAttrs)])
    let holds = InstantGateHoldCounter()
    let runtime = try await Self.runtime("observer-registration-reload-chunks", transport: session.transport) {
      $0.liveQueryResultReloadChunkTripleCount = 4
      $0.operationGateTimeline = holds.record
    }
    let keepAlive = try await Self.openClosePrune(runtime: runtime, session: session)
    holds.reset()

    let reopened = await runtime.observeQueryLease(TodoExample.query)
    let first = try await InstantStoredResultReloadTests.emission(of: reopened.stream, operation: "reopen the list") {
      _ in true
    }

    #expect(Set(["todo-1", "todo-2", "todo-3"]).isSubset(of: first.values.map(\.id)))
    expectNoDifference(holds.count(of: "reload closed query result"), 4)
    expectNoDifference(holds.count(of: "observe standard live query"), 1)

    await reopened.cancel()
    await keepAlive.cancel()
    _ = try await runtime.closeConnection()
  }

  /// Between two holds of a reload, the prune keeps the reloading result: it is no open query's yet, and a prune that
  /// unloaded it then would drop the entities its first holds loaded back.
  @Test
  func thePruneKeepsAResultWhileItReloads() async throws {
    let session = LiveReactorParitySession(messages: [liveReactorInitOK(attrs: liveReactorTodoServerAttrs)])
    let pause = InstantPausePoint()
    let runtime = try await Self.runtime("observer-registration-reload-prune", transport: session.transport) {
      $0.liveQueryResultReloadChunkTripleCount = 4
      $0.onUnloadedLiveQueryResultReloadChunkForTesting = { _, chunksDone in
        if chunksDone == 1 { await pause.pauseOnce() }
      }
    }
    let keepAlive = try await Self.openClosePrune(runtime: runtime, session: session)

    let reopening = Task { await runtime.observeQueryLease(TodoExample.query) }
    try await pause.waitUntilEntered(within: .seconds(10))
    let pruned = try await runtime.pruneLiveQueryResults(
      policy: InstantStoredResultReloadTests.productionPolicy,
      now: InstantStoredResultReloadTests.pruneTime
    )
    pause.release()
    let reopened = await reopening.value

    expectNoDifference(pruned.unloadedQueryKeys, [], "#1131: the prune unloaded a result that was loading back")
    let first = try await InstantStoredResultReloadTests.emission(of: reopened.stream, operation: "reopen the list") {
      _ in true
    }
    #expect(
      Set(["todo-1", "todo-2", "todo-3"]).isSubset(of: first.values.map(\.id)),
      "the reopened list's first answer holds every stored row, not \(first.values.map(\.id))"
    )

    await reopened.cancel()
    await keepAlive.cancel()
    _ = try await runtime.closeConnection()
  }

  /// A second observer of a query whose closed result is loading back waits for that reload, and then shares the first
  /// observer's subscription: it never answers from a half-loaded result, and nothing is sent twice.
  @Test
  func aSecondObserverWaitsForTheReloadOfItsQuery() async throws {
    let session = LiveReactorParitySession(messages: [liveReactorInitOK(attrs: liveReactorTodoServerAttrs)])
    let pause = InstantPausePoint()
    let runtime = try await Self.runtime("observer-registration-reload-second", transport: session.transport) {
      $0.liveQueryResultReloadChunkTripleCount = 4
      $0.onUnloadedLiveQueryResultReloadChunkForTesting = { _, chunksDone in
        if chunksDone == 1 { await pause.pauseOnce() }
      }
    }
    let keepAlive = try await Self.openClosePrune(runtime: runtime, session: session)

    let first = Task { await runtime.observeQueryLease(TodoExample.query) }
    try await pause.waitUntilEntered(within: .seconds(10))
    let secondReturned = InstantPausePoint()
    let second = Task {
      let lease = await runtime.observeQueryLease(TodoExample.query)
      secondReturned.release()
      return lease
    }
    try await Task.sleep(for: .milliseconds(300))
    let returnedDuringTheReload = secondReturned.isReleased
    pause.release()
    let firstLease = await first.value
    let secondLease = await second.value

    #expect(!returnedDuringTheReload, "#1131: a second observer answered while its query's result was half loaded")
    for lease in [firstLease, secondLease] {
      let answer = try await InstantStoredResultReloadTests.emission(of: lease.stream, operation: "reopen the list") {
        _ in true
      }
      #expect(Set(["todo-1", "todo-2", "todo-3"]).isSubset(of: answer.values.map(\.id)))
    }
    let addQueries = await session.sentMessages().filter { $0.op == "add-query" }
    expectNoDifference(addQueries.count, 3, "the keep-alive, the list, and the list reopened once")

    await firstLease.cancel()
    await secondLease.cancel()
    await keepAlive.cancel()
    _ = try await runtime.closeConnection()
  }
}

// MARK: - Fixtures

extension InstantObserverRegistrationGateTests {
  static func runtime(
    _ name: String,
    transport: InstantLiveTransportClient,
    configure: (inout InstantRuntimeConfiguration) -> Void = { _ in }
  ) async throws -> InstantRuntime {
    var configuration = InstantRuntimeConfiguration(
      appID: name,
      persistenceURL: try InstantStoredResultReloadTests.temporaryCacheURL(),
      initialAttributes: TodoExample.attributes,
      liveTransport: transport
    )
    configuration.liveReconnectSleep = { _ in }
    configure(&configuration)
    return try await InstantRuntime.bootstrap(configuration: configuration)
  }

  /// Opens a keep-alive query and the todo list, has the server answer both, closes the list, and prunes it, so its
  /// result is unloaded to disk (#1006). Returns the keep-alive lease, still open.
  static func openClosePrune(
    runtime: InstantRuntime,
    session: LiveReactorParitySession
  ) async throws -> InstantQueryObservationLease {
    let keepAlive = await runtime.observeQueryLease(InstantStoredResultReloadTests.keepAliveTodosQuery)
    _ = try await runtime.connect()
    await session.enqueue(
      liveReactorAddQueryOK(
        query: try await InstantStoredResultReloadTests.registeredQuery(number: 1, in: session),
        processedTransactionID: "tx-keep-alive",
        result: InstantStoredResultReloadTests.todoResult([("todo-keep", "keep", 10)])
      )
    )
    let list = await runtime.observeQueryLease(TodoExample.query)
    await session.enqueue(
      liveReactorAddQueryOK(
        query: try await InstantStoredResultReloadTests.registeredQuery(number: 2, in: session),
        processedTransactionID: "tx-list",
        result: InstantStoredResultReloadTests.todoResult([("todo-1", "one", 1), ("todo-2", "two", 2), ("todo-3", "three", 3)])
      )
    )
    _ = try await InstantStoredResultReloadTests.emission(of: list.stream, operation: "show the server's list") {
      Set(["todo-1", "todo-2", "todo-3"]).isSubset(of: $0.values.map(\.id))
    }
    await list.cancel()
    try await InstantStoredResultReloadTests.waitForOp("remove-query", count: 1, in: session)
    let pruned = try await runtime.pruneLiveQueryResults(
      policy: InstantStoredResultReloadTests.productionPolicy,
      now: InstantStoredResultReloadTests.pruneTime
    )
    expectNoDifference(pruned.unloadedQueryKeys.count, 1)
    return keepAlive
  }

  /// The result of `query-closed` with `todos` todos, stored at `time`.
  static func closedResult(todos: Int, at time: Int64) -> InstantPersistedLiveQueryResult {
    InstantPersistedLiveQueryResult(
      replacement: InstantLiveQueryResultReplacement(
        key: "query-closed",
        triples: (0..<todos).flatMap { InstantStoredResultReloadTests.todoTriples(index: $0) },
        pageInfo: nil
      ),
      updatedAt: InstantTimestamp(milliseconds: time)
    )
  }

  /// The session prune with another query open, which unloads every stored result (#1006).
  static func unloadEverything(in persistence: SQLitePersistenceStore, at time: Int64) async throws {
    _ = try await persistence.pruneLiveQueryResults(
      policy: InstantStoredResultReloadTests.productionPolicy,
      now: InstantTimestamp(milliseconds: time),
      preservingQueryKeys: ["query-open-elsewhere"]
    )
  }

  /// Starts `body` and says whether it finished within `limit`; the caller awaits `work` once whatever it waits for is
  /// released.
  static func finishes(
    within limit: Duration,
    _ body: @escaping @Sendable () async throws -> Void
  ) async -> (finished: Bool, work: Task<Void, any Error>) {
    let done = InstantPausePoint()
    let work = Task {
      try await body()
      done.release()
    }
    let deadline = ContinuousClock.now + limit
    while !done.isReleased, ContinuousClock.now < deadline {
      try? await Task.sleep(for: .milliseconds(5))
    }
    return (done.isReleased, work)
  }
}

struct InstantObserverRegistrationGateTestFailure: Error, CustomStringConvertible {
  var description: String
  init(_ description: String) { self.description = description }
}

/// How many times each holder took the operation gate, from the gate's timeline (#1074).
final class InstantGateHoldCounter: @unchecked Sendable {
  // SAFETY: `lock` guards `acquired`.
  private let lock = NSLock()
  private var acquired: [String: Int] = [:]

  var record: @Sendable (AsyncSerialGate.TimelineEvent) -> Void {
    { [weak self] event in
      guard event.kind == .acquired, let self else { return }
      self.lock.withLock { self.acquired[event.operation, default: 0] += 1 }
    }
  }

  func reset() { lock.withLock { acquired = [:] } }

  func count(of operation: String) -> Int { lock.withLock { acquired[operation, default: 0] } }
}

/// A point a task pauses at once until the test releases it.
final class InstantPausePoint: @unchecked Sendable {
  // SAFETY: `lock` guards every stored property below it.
  private let lock = NSLock()
  private var continuation: CheckedContinuation<Void, Never>?
  private var entered = false
  private var released = false

  /// Pauses the first caller until ``release()``; later callers pass.
  func pauseOnce() async {
    let pauses = lock.withLock { () -> Bool in
      guard !entered else { return false }
      entered = true
      return !released
    }
    guard pauses else { return }
    await withCheckedContinuation { continuation in
      let resumeNow = lock.withLock { () -> Bool in
        if released { return true }
        self.continuation = continuation
        return false
      }
      if resumeNow { continuation.resume() }
    }
  }

  var isReleased: Bool { lock.withLock { released } }

  func waitUntilEntered(within limit: Duration = InstantTestWait.hang) async throws {
    let deadline = ContinuousClock.now + limit
    while !lock.withLock({ entered }) {
      guard ContinuousClock.now < deadline else {
        throw InstantObserverRegistrationGateTestFailure("Nothing reached the pause point within \(limit).")
      }
      try await Task.sleep(for: .milliseconds(2))
    }
  }

  func release() {
    let continuation = lock.withLock { () -> CheckedContinuation<Void, Never>? in
      released = true
      defer { self.continuation = nil }
      return self.continuation
    }
    continuation?.resume()
  }
}

/// A socket that holds the first message of one op, as a full send buffer holds a write, until released (#1131).
final class InstantStalledLiveSend: Sendable {
  private let op: String
  private let point = InstantPausePoint()

  init(op: String) {
    self.op = op
  }

  func transport(over session: LiveReactorParitySession) -> InstantLiveTransportClient {
    let op = op
    let point = point
    return .immediate { _ in
      let inner = session.webSocketSession
      return InstantLiveWebSocketSession(
        send: { message in
          if message.op == op { await point.pauseOnce() }
          try await inner.send(message)
        },
        receive: { try await inner.receive() },
        close: { await inner.close() },
        abort: { inner.abort() }
      )
    }
  }

  func waitUntilHolding() async throws {
    try await point.waitUntilEntered()
  }

  func release() {
    point.release()
  }
}
