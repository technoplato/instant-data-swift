// History
// 2026-10-24  #1131  Created. Registering an observer held the operation gate across its socket send and across the
//                    reload of its closed stored result: on builds 121-126 one registration held the gate 5.0-7.8 s with
//                    about 11 callers queued, and in the concurrency audit's exercises a registration held it 153 ms over
//                    a 150 ms socket and 1,718 ms to reload the `$files` list's 75,640 facts.

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

  /// A closed result that changed between the reload's read and its commit is not committed from the stale read: here
  /// a second observer reopened the same query, the server answered it with a new row, the query closed again and was
  /// pruned again, all while the first reload's read waited. The first observer answers with the newer result.
  @Test
  func aReloadWhoseStoredResultChangedReadsItAgain() async throws {
    let session = LiveReactorParitySession(messages: [liveReactorInitOK(attrs: liveReactorTodoServerAttrs)])
    let pause = InstantPausePoint()
    let runtime = try await Self.runtime("observer-registration-reload-changed", transport: session.transport) {
      $0.onUnloadedLiveQueryResultReadForTesting = { _ in await pause.pauseOnce() }
    }
    let keepAlive = try await Self.openClosePrune(runtime: runtime, session: session)

    // The first reopening reads the closed result and waits.
    let first = Task { await runtime.observeQueryLease(TodoExample.query) }
    try await pause.waitUntilEntered()

    // Meanwhile the query reopens, the server restates it with a fourth row, and it closes and is pruned again.
    let meanwhile = await Self.finishes(within: .seconds(10)) {
      let second = await runtime.observeQueryLease(TodoExample.query)
      await session.enqueue(
        liveReactorAddQueryOK(
          query: try await InstantStoredResultReloadTests.registeredQuery(number: 3, in: session),
          processedTransactionID: "tx-list-again",
          result: InstantStoredResultReloadTests.todoResult([
            ("todo-1", "one", 1), ("todo-2", "two", 2), ("todo-3", "three", 3), ("todo-4", "four", 4),
          ])
        )
      )
      _ = try await InstantStoredResultReloadTests.emission(of: second.stream, operation: "show the restated list") {
        $0.values.map(\.id).contains("todo-4")
      }
      await second.cancel()
      try await InstantStoredResultReloadTests.waitForOp("remove-query", count: 2, in: session)
      let pruned = try await runtime.pruneLiveQueryResults(
        policy: InstantStoredResultReloadTests.productionPolicy,
        now: InstantStoredResultReloadTests.pruneTime
      )
      expectNoDifference(pruned.unloadedQueryKeys.count, 1)
    }
    #expect(meanwhile.finished, "#1131: a second observer of the query waited for the first one's reload read")

    pause.release()
    try await meanwhile.work.value
    let reopened = await first.value
    let answer = try await InstantStoredResultReloadTests.emission(of: reopened.stream, operation: "reopen the list") {
      _ in true
    }
    #expect(
      Set(["todo-1", "todo-2", "todo-3", "todo-4"]).isSubset(of: answer.values.map(\.id)),
      "#1131: the reload committed the result it read before the query closed again: \(answer.values.map(\.id))"
    )

    await reopened.cancel()
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
