import CustomDump
import Foundation
@testable import InstantSwiftDataCore
import Testing

/// Library-78, item 7: one-shot reads of rows already on the device do not wait on the WebSocket.
///
/// `queryOnce` sent add-query and waited up to 5 s for the server even when the same query was already subscribed and
/// answered, which upstream `Reactor.js` also does (it resolves on add-query-exists with the local result). Behind a
/// backlog of server frames that wait failed Scribe's Copy Transcript at 5,004 ms while the transcript was on screen
/// (#307), and the Watch's startup reads stalled the same way (#317). A query whose exact subscription the server
/// answered on the open socket, and has not failed since, is now answered from the store; every other query asks the
/// server as before.
@Suite(.serialized)
struct InstantLocalFirstQueryOnceTests {
  static func temporaryCacheURL() throws -> URL {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("instant-local-first-query-once-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory.appendingPathComponent("instant.sqlite")
  }

  static func addQueries(in session: LiveReactorParitySession) async -> [InstantLiveMessage] {
    await session.sentMessages().filter { $0.op == "add-query" }
  }

  static func waitForAddQueries(_ count: Int, in session: LiveReactorParitySession) async throws -> [InstantLiveMessage] {
    let deadline = ContinuousClock.now + .seconds(10)
    while true {
      let sent = await addQueries(in: session)
      if sent.count >= count || ContinuousClock.now >= deadline { return sent }
      try await Task.sleep(for: .milliseconds(20))
    }
  }

  struct Fixture {
    var runtime: InstantRuntime
    var session: LiveReactorParitySession
    var query: InstantLiveJSONValue
    var observation: InstantQueryObservationLease
  }

  /// Observes the todo query and has the server answer it with one row.
  static func answeredSubscription(_ name: String) async throws -> Fixture {
    let query = try InstantLiveQueryEncoder.encode(TodoExample.query)
    let session = LiveReactorParitySession(messages: [liveReactorInitOK(attrs: liveReactorTodoServerAttrs)])
    var configuration = InstantRuntimeConfiguration(
      appID: "local-first-query-once-\(name)",
      persistenceURL: try temporaryCacheURL(),
      initialAttributes: TodoExample.attributes,
      liveTransport: session.transport
    )
    configuration.liveReconnectSleep = { _ in }
    let runtime = try await InstantRuntime.bootstrap(configuration: configuration)
    let observation = await runtime.observeQueryLease(TodoExample.query)
    var iterator = observation.stream.makeAsyncIterator()
    _ = await iterator.next()
    _ = try await runtime.connect()
    _ = try await waitForAddQueries(1, in: session)
    await session.enqueue(
      liveReactorAddQueryOK(
        query: query,
        processedTransactionID: "server-tx-subscribed",
        result: liveReactorTodoQueryResult(
          id: "todo-on-device",
          text: "already on the device",
          createdAt: InstantTimestamp(milliseconds: 1_700_000_317_000)
        )
      )
    )
    var texts: [String] = []
    while texts != ["already on the device"], let emission = await iterator.next() {
      texts = try TodoExample.decode(emission.values).map(\.text)
    }
    // Observers see the rows a moment before the receive loop records the answer.
    let deadline = ContinuousClock.now + .seconds(5)
    while try await !runtime.isAnsweredOnCurrentSocketForTesting(TodoExample.query) {
      guard ContinuousClock.now < deadline else {
        Issue.record("The server's answer was never recorded for the subscription.")
        break
      }
      try await Task.sleep(for: .milliseconds(5))
    }
    return Fixture(runtime: runtime, session: session, query: query, observation: observation)
  }

  @Test
  func aQueryOnceOfAnAnsweredSubscriptionIsAnsweredFromTheDeviceWithoutARoundTrip() async throws {
    let fixture = try await Self.answeredSubscription("answered")
    // The server answers nothing more: a round trip would wait 5 s and fail.
    let started = ContinuousClock.now
    let emission = try await fixture.runtime.queryOnce(TodoExample.query)
    let elapsed = started.duration(to: .now)
    expectNoDifference(try TodoExample.decode(emission.values).map(\.text), ["already on the device"])
    #expect(elapsed < .seconds(2), "answered from the device in \(elapsed)")
    let ops = await fixture.session.sentMessages().map(\.op)
    expectNoDifference(ops, ["init", "add-query"], "no second add-query")
    await fixture.observation.cancel()
    _ = try await fixture.runtime.closeConnection()
  }

  @Test
  func aQueryOnceThatNoAnsweredSubscriptionCoversStillAsksTheServer() async throws {
    let fixture = try await Self.answeredSubscription("other-query")
    let other = InstantQueryPlan(
      id: "examples.todos.newest",
      namespace: TodoExample.namespace,
      order: InstantQueryOrder("createdAt", .descending),
      limit: 1
    )
    let once = Task { try await fixture.runtime.queryOnce(other) }
    let sent = try await Self.waitForAddQueries(2, in: fixture.session)
    expectNoDifference(sent.count, 2, "a different query asks the server")
    let otherQuery = try #require(sent.last?.fields["q"])
    await fixture.session.enqueue(
      liveReactorAddQueryOK(
        query: otherQuery,
        processedTransactionID: "server-tx-other",
        result: liveReactorTodoQueryResult(
          id: "todo-on-device",
          text: "already on the device",
          createdAt: InstantTimestamp(milliseconds: 1_700_000_317_000)
        )
      )
    )
    let emission = try await once.value
    expectNoDifference(emission.values.map(\.id), ["todo-on-device"])
    await fixture.observation.cancel()
    _ = try await fixture.runtime.closeConnection()
  }

  @Test
  func afterAServerErrorTheSubscriptionMustBeAnsweredAgainFirst() async throws {
    let fixture = try await Self.answeredSubscription("after-error")
    let first = try #require(await Self.addQueries(in: fixture.session).first)
    await fixture.session.enqueue(
      InstantReactorParityTests.addQueryError(
        to: fixture.query,
        clientEventID: first.clientEventID,
        status: 500,
        type: "operation-timed-out",
        message: "Operation timed out: handle-receive"
      )
    )
    try await Task.sleep(for: .milliseconds(100))
    // The failed subscription's rows may be behind the server, so queryOnce asks again.
    let once = Task { try await fixture.runtime.queryOnce(TodoExample.query) }
    let sent = try await Self.waitForAddQueries(2, in: fixture.session)
    #expect(sent.count >= 2, "queryOnce asks the server while the subscription is failed")
    await fixture.session.enqueue(
      liveReactorAddQueryOK(
        query: fixture.query,
        processedTransactionID: "server-tx-recovered",
        result: liveReactorTodoQueryResult(
          id: "todo-on-device",
          text: "answered again",
          createdAt: InstantTimestamp(milliseconds: 1_700_000_317_000)
        )
      )
    )
    let emission = try await once.value
    expectNoDifference(try TodoExample.decode(emission.values).map(\.text), ["answered again"])
    await fixture.observation.cancel()
    _ = try await fixture.runtime.closeConnection()
  }
}
