import CustomDump
import Foundation
@testable import InstantSwiftDataCore
import Testing

/// #360: a live query whose add-query the server answers with a transient error recovers on the same socket.
///
/// A stalled server answers add-query with `{op: error, status: 500, type: operation-timed-out}`. Library-77 kept the
/// registration (#324) but sent it again only on the next `init-ok`, and a healthy socket never reconnects, so the
/// query went silent: the phone showed 0 of 6 reply cards after a burst (`run.py app --scenario
/// burst-then-reconnect`). Upstream `Reactor.js` `_handleReceiveError` calls `notifyQueryError`, so the query's
/// subscribers see the error, and keeps the subscription for the next `init-ok`. Swift delivers the error the same
/// way and also sends the add-query again on the open socket after a growing backoff.
@Suite(.serialized)
struct InstantLiveQueryErrorRecoveryTests {
  static func temporaryCacheURL() throws -> URL {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("instant-live-query-error-recovery-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory.appendingPathComponent("instant.sqlite")
  }

  static func addQueryMessages(in session: LiveReactorParitySession) async -> [InstantLiveMessage] {
    await session.sentMessages().filter { $0.op == "add-query" }
  }

  /// The add-queries `session` has been sent, once there are `count` of them or `timeout` passes.
  static func addQueries(
    in session: LiveReactorParitySession,
    reaching count: Int,
    within timeout: Duration = .seconds(10)
  ) async throws -> [InstantLiveMessage] {
    let deadline = ContinuousClock.now + timeout
    while true {
      let sent = await addQueryMessages(in: session)
      if sent.count >= count || ContinuousClock.now >= deadline { return sent }
      try await Task.sleep(for: .milliseconds(20))
    }
  }

  static func timedOut(_ query: InstantLiveJSONValue, answering addQuery: InstantLiveMessage) -> InstantLiveMessage {
    InstantReactorParityTests.addQueryError(
      to: query,
      clientEventID: addQuery.clientEventID,
      status: 500,
      type: "operation-timed-out",
      message: "Operation timed out: handle-receive"
    )
  }

  @Test
  func aTimedOutAddQueryIsSentAgainOnTheSameSocketAndRefreshes() async throws {
    let query = try InstantLiveQueryEncoder.encode(TodoExample.query)
    let session = LiveReactorParitySession(messages: [
      liveReactorInitOK(attrs: liveReactorTodoServerAttrs, sessionID: "stalled-add-query")
    ])
    // One scripted session only: a reconnect would be a second connection request, and it would fail.
    let transport = LiveReactorParityTransport(sessions: [session])
    var configuration = InstantRuntimeConfiguration(
      appID: "live-query-error-same-socket",
      persistenceURL: try Self.temporaryCacheURL(),
      initialAttributes: TodoExample.attributes,
      liveTransport: transport.transport
    )
    configuration.liveReconnectSleep = { _ in }
    let runtime = try await InstantRuntime.bootstrap(configuration: configuration)
    let stream = await runtime.observe(TodoExample.query)
    var iterator = stream.makeAsyncIterator()
    _ = try #require(await iterator.next())
    _ = try await runtime.connect()

    // The server stalls for two answers.
    for answer in 1...2 {
      let sent = try await Self.addQueries(in: session, reaching: answer)
      try #require(sent.count == answer, "add-query \(answer) should reach the same socket")
      await session.enqueue(Self.timedOut(query, answering: sent[answer - 1]))
    }
    let resent = try await Self.addQueries(in: session, reaching: 3)
    expectNoDifference(resent.count, 3, "the failed add-query should be sent again without a reconnect")
    guard resent.count == 3 else {
      _ = try await runtime.closeConnection()
      return
    }
    await session.enqueue(
      liveReactorAddQueryOK(
        query: query,
        processedTransactionID: "server-tx-after-stall",
        result: liveReactorTodoQueryResult(
          id: "todo-after-stall",
          text: "refreshed on the same socket",
          createdAt: InstantTimestamp(milliseconds: 1_700_000_360_000)
        )
      )
    )
    var texts: [String] = []
    while texts != ["refreshed on the same socket"], let emission = await iterator.next() {
      texts = try TodoExample.decode(emission.values).map(\.text)
    }
    expectNoDifference(texts, ["refreshed on the same socket"])
    let connections = await transport.connectionRequests()
    expectNoDifference(connections.count, 1, "a transient add-query error must not need a reconnect")
    _ = try await runtime.closeConnection()
  }
}

extension InstantLiveQueryErrorRecoveryTests {
  actor QueryRetryRecorder {
    private(set) var delays: [UInt64] = []
    private(set) var attempts: [Int] = []

    func record(_ owner: InstantServerErrorRetryOwner, _ attempt: Int, _ delay: UInt64) {
      guard case .query = owner else { return }
      attempts.append(attempt)
      delays.append(delay)
    }
  }

  struct Fixture {
    var runtime: InstantRuntime
    var session: LiveReactorParitySession
    var transport: LiveReactorParityTransport
    var query: InstantLiveJSONValue
  }

  static func fixture(
    _ name: String,
    retryPolicy: InstantServerErrorRetryPolicy = InstantServerErrorRetryPolicy(),
    recorder: QueryRetryRecorder? = nil
  ) async throws -> Fixture {
    let query = try InstantLiveQueryEncoder.encode(TodoExample.query)
    let session = LiveReactorParitySession(messages: [
      liveReactorInitOK(attrs: liveReactorTodoServerAttrs, sessionID: name)
    ])
    let transport = LiveReactorParityTransport(sessions: [session])
    var configuration = InstantRuntimeConfiguration(
      appID: "live-query-error-\(name)",
      persistenceURL: try temporaryCacheURL(),
      initialAttributes: TodoExample.attributes,
      liveTransport: transport.transport
    )
    configuration.liveReconnectSleep = { _ in }
    configuration.liveServerErrorRetryPolicy = retryPolicy
    if let recorder {
      configuration.onServerErrorRetryScheduledForTesting = { owner, attempt, delay in
        await recorder.record(owner, attempt, delay)
      }
    }
    let runtime = try await InstantRuntime.bootstrap(configuration: configuration)
    return Fixture(runtime: runtime, session: session, transport: transport, query: query)
  }

  static func addQueryOK(_ query: InstantLiveJSONValue, id: String, text: String) -> InstantLiveMessage {
    liveReactorAddQueryOK(
      query: query,
      processedTransactionID: "server-tx-\(id)",
      result: liveReactorTodoQueryResult(
        id: id,
        text: text,
        createdAt: InstantTimestamp(milliseconds: 1_700_000_360_100)
      )
    )
  }

  @Test
  func anObserverSeesTheServerErrorAndItsClearingWithoutItsStreamEnding() async throws {
    let fixture = try await Self.fixture("observer-sees-error")
    let stream = await fixture.runtime.observe(TodoExample.query)
    var iterator = stream.makeAsyncIterator()
    _ = try #require(await iterator.next())
    _ = try await fixture.runtime.connect()

    // The server answers first; the observer shows the row.
    let first = try await Self.addQueries(in: fixture.session, reaching: 1)
    try #require(first.count == 1)
    await fixture.session.enqueue(Self.addQueryOK(fixture.query, id: "todo-before-stall", text: "before the stall"))
    var shown = try #require(await iterator.next())
    while try TodoExample.decode(shown.values).map(\.text) != ["before the stall"] {
      shown = try #require(await iterator.next())
    }
    #expect(shown.error == nil)

    // A later add-query of the same query (a reconnect's, or a refresh) times out on the server.
    let failure = Self.timedOut(fixture.query, answering: first[0])
    await fixture.session.enqueue(failure)
    let failed = try #require(await iterator.next())
    expectNoDifference(failed.error?.serverStatus, 500)
    expectNoDifference(failed.error?.serverType, "operation-timed-out")
    expectNoDifference(try TodoExample.decode(failed.values).map(\.text), ["before the stall"])

    // The re-sent add-query is answered: the error clears, and the stream is still open.
    let resent = try await Self.addQueries(in: fixture.session, reaching: 2)
    try #require(resent.count == 2)
    await fixture.session.enqueue(Self.addQueryOK(fixture.query, id: "todo-before-stall", text: "before the stall"))
    let recovered = try #require(await iterator.next())
    #expect(recovered.error == nil)
    expectNoDifference(try TodoExample.decode(recovered.values).map(\.text), ["before the stall"])
    let observed1 = await fixture.transport.connectionRequests().count
    expectNoDifference(observed1, 1)
    _ = try await fixture.runtime.closeConnection()
  }

  @Test
  func aRejectedQueryReportsTheRejectionAndIsNotSentAgain() async throws {
    let fixture = try await Self.fixture("rejected-query")
    let stream = await fixture.runtime.observe(TodoExample.query)
    var iterator = stream.makeAsyncIterator()
    _ = try #require(await iterator.next())
    _ = try await fixture.runtime.connect()
    let first = try await Self.addQueries(in: fixture.session, reaching: 1)
    try #require(first.count == 1)
    await fixture.session.enqueue(
      InstantReactorParityTests.addQueryError(
        to: fixture.query,
        clientEventID: first[0].clientEventID,
        status: 400,
        type: "permission-denied",
        message: "Permission denied: not perms-pass?"
      )
    )
    let rejected = try #require(await iterator.next())
    expectNoDifference(rejected.error?.code, .permissionRejected)
    // A rejection that would repeat is not sent again.
    let sent = try await Self.addQueries(in: fixture.session, reaching: 2, within: .milliseconds(800))
    expectNoDifference(sent.count, 1)
    _ = try await fixture.runtime.closeConnection()
  }

  @Test
  func theResendBackoffGrowsAcrossConsecutiveFailuresAndStartsOverOnAnAnswer() async throws {
    let recorder = QueryRetryRecorder()
    let fixture = try await Self.fixture(
      "resend-backoff",
      retryPolicy: InstantServerErrorRetryPolicy(baseMilliseconds: 20, maximumMilliseconds: 60, jitter: { 1 }),
      recorder: recorder
    )
    let stream = await fixture.runtime.observe(TodoExample.query)
    var iterator = stream.makeAsyncIterator()
    _ = try #require(await iterator.next())
    _ = try await fixture.runtime.connect()
    for answer in 1...4 {
      let sent = try await Self.addQueries(in: fixture.session, reaching: answer)
      try #require(sent.count == answer)
      await fixture.session.enqueue(Self.timedOut(fixture.query, answering: sent[answer - 1]))
    }
    let sent = try await Self.addQueries(in: fixture.session, reaching: 5)
    try #require(sent.count == 5)
    await fixture.session.enqueue(Self.addQueryOK(fixture.query, id: "todo-backoff", text: "answered"))
    var texts: [String] = []
    while texts != ["answered"], let emission = await iterator.next() {
      texts = try TodoExample.decode(emission.values).map(\.text)
    }
    // One more failure after the answer starts the backoff over.
    await fixture.session.enqueue(Self.timedOut(fixture.query, answering: sent[4]))
    #expect(try await Self.addQueries(in: fixture.session, reaching: 6).count == 6)
    let observed2 = await recorder.attempts
    expectNoDifference(observed2, [1, 2, 3, 4, 1])
    let observed3 = await recorder.delays
    expectNoDifference(observed3, [20, 40, 60, 60, 20])
    let observed4 = await fixture.transport.connectionRequests().count
    expectNoDifference(observed4, 1)
    _ = try await fixture.runtime.closeConnection()
  }

  @Test
  func anInfiniteQueryKeepsItsRowsAndReportsTheServerErrorUntilItClears() async throws {
    let fixture = try await Self.fixture("infinite-query-error")
    let subscription = await fixture.runtime.subscribeInfiniteQuery(
      InstantQueryPlan(
        id: "todos.infinite-error",
        namespace: TodoExample.namespace,
        order: InstantQueryOrder("createdAt", .ascending),
        limit: 10
      )
    )
    var snapshots = subscription.snapshots.makeAsyncIterator()
    _ = try await fixture.runtime.connect()
    // The starter page's first add-query is answered with a row.
    let first = try await Self.addQueries(in: fixture.session, reaching: 1)
    try #require(first.count >= 1)
    let starter = first[0]
    let starterQuery = try #require(starter.fields["q"])
    await fixture.session.enqueue(
      liveReactorAddQueryOK(
        query: starterQuery,
        processedTransactionID: "server-tx-infinite",
        result: liveReactorTodoQueryResult(
          id: "todo-infinite",
          text: "a page row",
          createdAt: InstantTimestamp(milliseconds: 1_700_000_360_200)
        )
      )
    )
    var snapshot = try #require(await snapshots.next())
    while snapshot.values.isEmpty {
      snapshot = try #require(await snapshots.next())
    }
    #expect(snapshot.error == nil)
    // The server fails the starter's add-query: the rows stay, and the snapshot reports the error.
    await fixture.session.enqueue(
      InstantReactorParityTests.addQueryError(
        to: starterQuery,
        clientEventID: starter.clientEventID,
        status: 500,
        type: "operation-timed-out",
        message: "Operation timed out: handle-receive"
      )
    )
    var failed = try #require(await snapshots.next())
    while failed.error == nil {
      failed = try #require(await snapshots.next())
    }
    expectNoDifference(failed.error?.serverType, "operation-timed-out")
    expectNoDifference(failed.values.map(\.id), ["todo-infinite"])
    // The re-sent starter is answered and the error clears.
    let resent = try await Self.addQueries(in: fixture.session, reaching: first.count + 1)
    try #require(resent.count == first.count + 1)
    await fixture.session.enqueue(
      liveReactorAddQueryOK(
        query: starterQuery,
        processedTransactionID: "server-tx-infinite-2",
        result: liveReactorTodoQueryResult(
          id: "todo-infinite",
          text: "a page row",
          createdAt: InstantTimestamp(milliseconds: 1_700_000_360_200)
        )
      )
    )
    var recovered = try #require(await snapshots.next())
    while recovered.error != nil {
      recovered = try #require(await snapshots.next())
    }
    expectNoDifference(recovered.values.map(\.id), ["todo-infinite"])
    subscription.unsubscribe()
    _ = try await fixture.runtime.closeConnection()
  }
}
