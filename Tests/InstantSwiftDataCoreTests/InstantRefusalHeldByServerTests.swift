import CustomDump
import Foundation
@testable import InstantSwiftDataCore
import Testing

/// #441: a re-sent write the server already holds is not a failure.
///
/// Michael, Recording 040 at 11:53 on 2026-10-03, verbatim: "And then I got a not synced, instant refused one change to
/// this recording, so I need to, um, diagnose and debug where that is probably around when I opened the iPad." The
/// iPhone wrote the recording's capture gaps; the socket dropped before the server answered; the re-send on the next
/// connection was refused by Scribe's `validUpdate` rule (`newData.updatedAtMs >= data.updatedAtMs`), because a later
/// duration heartbeat had advanced `updatedAtMs`. Production holds the gaps: the first offer was applied and only its
/// answer was lost. Instant's server applies every transact it receives, without deduplicating a re-sent
/// client-event-id (`session.clj`), and `Reactor.js` re-sends every unanswered mutation after a reconnect
/// (`_flushPendingMessages`) and drops a refused one as an error (`_handleMutationError`). Library-78 already resolves
/// such a refusal as accepted when later accepted writes of this device cover every slot it sets
/// (`InstantSupersededReplayTests`); nothing later wrote the gaps, so it stood. Now a slot that a result the server sent
/// since the write was created shows with the write's value counts too.
@Suite(.serialized)
struct InstantRefusalHeldByServerTests {
  static let todoID = InstantSupersededReplayTests.todoID

  /// The server's result from the next connection shows the value the write set, then the server refuses its re-send.
  @Test
  func aRefusedReSendWhoseValuesTheServersResultShowsResolvesAsAccepted() async throws {
    let fixture = try await Fixture.make("held-before-refusal")
    try await fixture.writeTextAndDropBeforeTheAnswer("first")
    await fixture.second.enqueue(fixture.refresh(text: "first", processedTransactionID: 3))
    try await fixture.waitUntilTheStoredResultShows(text: "first")
    await fixture.second.enqueue(InstantSupersededReplayTests.refused("tx-first"))
    try await InstantSupersededReplayTests.waitUntil("the refusal is resolved") {
      await InstantSupersededReplayTests.mutation("tx-first", in: fixture.runtime)?.status != .pending
    }

    let first = await InstantSupersededReplayTests.mutation("tx-first", in: fixture.runtime)
    expectNoDifference(first?.status, .confirmed)
    expectNoDifference(first?.confirmationSource, .supersededByAcceptedWrite)
    let failed = await fixture.failedMutationIDs()
    expectNoDifference(failed, [])
    let offered = await InstantSupersededReplayTests.transactIDs(sentTo: fixture.second)
    expectNoDifference(offered, ["tx-first"], "the resolved write is not offered again")
    _ = try await fixture.runtime.closeConnection()
  }

  /// The refusal arrives with the re-sent backlog, before the next connection answers its query: it waits, not failed,
  /// and resolves when the answer shows the value it set.
  @Test
  func aRefusalBeforeTheConnectionsQueryAnswerWaitsForItAndResolvesAsAccepted() async throws {
    let fixture = try await Fixture.make("held-after-refusal")
    try await fixture.writeTextAndDropBeforeTheAnswer("first")
    await fixture.second.enqueue(InstantSupersededReplayTests.refused("tx-first"))
    try await Task.sleep(for: .milliseconds(300))
    let waiting = await InstantSupersededReplayTests.mutation("tx-first", in: fixture.runtime)?.status
    expectNoDifference(waiting, .pending, "waiting for the connection's query answer, not failed")

    await fixture.second.enqueue(fixture.addQueryOK(text: "first", processedTransactionID: 3))
    try await InstantSupersededReplayTests.waitUntil("the waiting refusal is resolved") {
      await InstantSupersededReplayTests.mutation("tx-first", in: fixture.runtime)?.status == .confirmed
    }
    let source = await InstantSupersededReplayTests.mutation("tx-first", in: fixture.runtime)?.confirmationSource
    expectNoDifference(source, .supersededByAcceptedWrite)
    let failed = await fixture.failedMutationIDs()
    expectNoDifference(failed, [])
    let offered = await InstantSupersededReplayTests.transactIDs(sentTo: fixture.second)
    expectNoDifference(offered, ["tx-first"], "a waiting write is not offered again")
    _ = try await fixture.runtime.closeConnection()
  }

  /// Recording 040's shape: a later write of this device covers some of the refused re-send's slots and was accepted
  /// (the heartbeat's `updatedAtMs`), so the server shows its newer value there; the server's result shows the rest
  /// (the capture gaps).
  @Test
  func aRefusedReSendCoveredPartlyByALaterAcceptedWriteAndPartlyByTheServersResultResolvesAsAccepted() async throws {
    let fixture = try await Fixture.make("partly-covered")
    try await fixture.transact("tx-first", at: 1, text: "first", isCompleted: false)
    try await fixture.transact("tx-second", at: 2, text: nil, isCompleted: true)
    _ = try await InstantSupersededReplayTests.waitForTransacts(3, on: fixture.first)
    await fixture.dropTheFirstConnection()
    let resent = try await InstantSupersededReplayTests.waitForTransacts(2, on: fixture.second)
    expectNoDifference(resent, ["tx-first", "tx-second"])
    await fixture.second.enqueue(fixture.refresh(text: "first", isCompleted: true, processedTransactionID: 3))
    try await fixture.waitUntilTheStoredResultShows(text: "first")
    await fixture.second.enqueue(InstantSupersededReplayTests.refused("tx-first"))
    await fixture.second.enqueue(InstantSupersededReplayTests.accepted("tx-second", transactionID: 4))
    try await InstantSupersededReplayTests.waitUntil("both writes are answered") {
      let first = await InstantSupersededReplayTests.mutation("tx-first", in: fixture.runtime)?.status
      let second = await InstantSupersededReplayTests.mutation("tx-second", in: fixture.runtime)?.status
      return first != .pending && second != .pending
    }

    let first = await InstantSupersededReplayTests.mutation("tx-first", in: fixture.runtime)
    expectNoDifference(first?.status, .confirmed)
    expectNoDifference(first?.confirmationSource, .supersededByAcceptedWrite)
    expectNoDifference(first?.serverTransactionID, "4", "it leaves the outbox with the write that covers it")
    let failed = await fixture.failedMutationIDs()
    expectNoDifference(failed, [])
    let offered = await InstantSupersededReplayTests.transactIDs(sentTo: fixture.second)
    expectNoDifference(offered, ["tx-first", "tx-second"])
    _ = try await fixture.runtime.closeConnection()
  }

  /// The connection has answered its query, and the answer shows another value: no result will show the write's value,
  /// so the refusal stands at once, as before.
  @Test
  func aRefusedReSendFailsAtOnceWhenTheConnectionsAnswersShowAnotherValue() async throws {
    let fixture = try await Fixture.make("answered-other-value")
    try await fixture.writeTextAndDropBeforeTheAnswer("first")
    await fixture.second.enqueue(fixture.addQueryOK(text: "another device's text", processedTransactionID: 3))
    try await fixture.waitUntilTheStoredResultShows(text: "another device's text")
    await fixture.second.enqueue(InstantSupersededReplayTests.refused("tx-first"))
    try await InstantSupersededReplayTests.waitUntil("the refusal is recorded", within: .seconds(5)) {
      await InstantSupersededReplayTests.mutation("tx-first", in: fixture.runtime)?.status == .failed
    }
    let failed = await fixture.failedMutationIDs()
    expectNoDifference(failed, ["tx-first"])
    _ = try await fixture.runtime.closeConnection()
  }

  /// A first offer's refusal is the server's verdict on the write itself, even when the server shows the same value.
  @Test
  func aFirstOffersRefusalStillFailsWhenTheServerShowsTheSameValue() async throws {
    let fixture = try await Fixture.make("first-offer")
    try await InstantSupersededReplayTests.updateText(fixture.runtime, "tx-first", "first", at: 1)
    _ = try await InstantSupersededReplayTests.waitForTransacts(2, on: fixture.first)
    await fixture.first.enqueue(fixture.refresh(text: "first", processedTransactionID: 3))
    try await fixture.waitUntilTheStoredResultShows(text: "first")
    await fixture.first.enqueue(InstantSupersededReplayTests.refused("tx-first"))
    try await InstantSupersededReplayTests.waitUntil("the refusal is recorded") {
      await InstantSupersededReplayTests.mutation("tx-first", in: fixture.runtime)?.status == .failed
    }
    let status = await InstantSupersededReplayTests.mutation("tx-first", in: fixture.runtime)?.status
    expectNoDifference(status, .failed)
    _ = try await fixture.runtime.closeConnection()
  }

  /// A runtime observing the todo query, connected, with the todo created and accepted on the first connection; the
  /// second connection follows a drop.
  struct Fixture: Sendable {
    var runtime: InstantRuntime
    var transport: LiveReactorParityTransport
    var first: LiveReactorParitySession
    var second: LiveReactorParitySession
    var query: InstantLiveJSONValue
    var queryKey: String
    var observation: AsyncStream<InstantQueryEmission>

    static func make(
      _ name: String,
      configure: (inout InstantRuntimeConfiguration) -> Void = { _ in }
    ) async throws -> Self {
      let first = LiveReactorParitySession(messages: [liveReactorInitOK(attrs: liveReactorTodoServerAttrs)])
      let second = LiveReactorParitySession(messages: [
        liveReactorInitOK(attrs: liveReactorTodoServerAttrs, sessionID: "after-drop")
      ])
      let transport = LiveReactorParityTransport(sessions: [first, second])
      var configuration = InstantRuntimeConfiguration(
        appID: "held-by-server-\(name)",
        persistenceURL: try InstantSupersededReplayTests.temporaryCacheURL(),
        initialAttributes: TodoExample.attributes,
        liveTransport: transport.transport
      )
      configuration.liveReconnectSleep = { _ in }
      configure(&configuration)
      let runtime = try await InstantRuntime.bootstrap(configuration: configuration)
      let observation = await runtime.observe(TodoExample.query)
      var iterator = observation.makeAsyncIterator()
      _ = await iterator.next()
      _ = try await runtime.connect()
      try await InstantSupersededReplayTests.createAcceptedTodo(runtime, on: first)
      let query = try InstantLiveQueryEncoder.encode(TodoExample.query)
      return Self(
        runtime: runtime,
        transport: transport,
        first: first,
        second: second,
        query: query,
        queryKey: try InstantLiveQueryEncoder.registrationKey(for: query),
        observation: observation
      )
    }

    /// Drops the first connection before the server answers its writes; the next connection re-sends them.
    func dropTheFirstConnection() async {
      await first.failReceive(
        InstantError(
          code: .networkFailed,
          operation: "receive held-by-server test event",
          message: "socket dropped before the answer",
          recovery: "Reconnect."
        )
      )
    }

    /// Writes the todo's text as `tx-first`, then drops the socket before the server answers.
    func writeTextAndDropBeforeTheAnswer(_ text: String) async throws {
      try await InstantSupersededReplayTests.updateText(runtime, "tx-first", text, at: 1)
      _ = try await InstantSupersededReplayTests.waitForTransacts(2, on: first)
      await dropTheFirstConnection()
      let resent = try await InstantSupersededReplayTests.waitForTransacts(1, on: second)
      expectNoDifference(resent, ["tx-first"])
    }

    /// Updates the todo: its text when given, and `isCompleted`.
    func transact(_ id: String, at offset: Int64, text: String?, isCompleted: Bool) async throws {
      let updatedAt = InstantTimestamp(milliseconds: 1_700_000_078_100 + offset)
      let todoID = InstantRefusalHeldByServerTests.todoID
      func insert(_ attributeID: String, _ value: InstantValue) -> InstantTripleOperation {
        .insert(InstantTriple(entityID: todoID, attributeID: attributeID, value: value, txID: id, txTime: updatedAt))
      }
      var operations: [InstantTripleOperation] = [
        .requireEntityExists(entityID: todoID, namespace: TodoExample.namespace),
        insert(InstantAttribute.primaryKeyID(namespace: TodoExample.namespace), .string(todoID)),
      ]
      if let text {
        operations.append(insert("todos/text", .string(text)))
      }
      operations.append(insert("todos/isCompleted", .bool(isCompleted)))
      _ = try await runtime.transact(InstantStoreTransaction(id: id, operations: operations), createdAt: updatedAt)
    }

    /// The todo query's result as the server sends it.
    func result(text: String, isCompleted: Bool) -> InstantLiveJSONValue {
      let todoID = InstantRefusalHeldByServerTests.todoID
      let createdAt = Double(1_700_000_078_000)
      func row(_ attributeID: String, _ value: InstantLiveJSONValue) -> InstantLiveJSONValue {
        .array([.string(todoID), .string(attributeID), value, .number(createdAt)])
      }
      return .object([
        "data": .object([
          "datalog-result": .object([
            "join-rows": .array([
              .array([
                row("server-todos-id", .string(todoID)),
                row("server-todos-text", .string(text)),
                row("server-todos-is-completed", .bool(isCompleted)),
                row("server-todos-created-at", .number(createdAt)),
              ])
            ])
          ])
        ]),
        "child-nodes": .array([]),
      ])
    }

    /// A refresh of the todo query, as the server pushes one after a change.
    func refresh(text: String, isCompleted: Bool = false, processedTransactionID: Int) -> InstantLiveMessage {
      InstantLiveMessage(
        op: "refresh-ok",
        clientEventID: nil,
        fields: [
          "attrs": .array([]),
          "computations": .array([
            .object([
              "instaql-query": query,
              "instaql-result": .array([result(text: text, isCompleted: isCompleted)]),
              "processed-tx-id": .string(String(processedTransactionID)),
            ])
          ]),
          "processed-tx-id": .string(String(processedTransactionID)),
        ]
      )
    }

    /// The connection's first answer to the todo query.
    func addQueryOK(text: String, isCompleted: Bool = false, processedTransactionID: Int) -> InstantLiveMessage {
      liveReactorAddQueryOK(
        query: query,
        processedTransactionID: String(processedTransactionID),
        result: [result(text: text, isCompleted: isCompleted)]
      )
    }

    func waitUntilTheStoredResultShows(text: String) async throws {
      let runtime = runtime
      let key = queryKey
      try await InstantSupersededReplayTests.waitUntil("the stored result shows \(text)") {
        let stored = try await runtime.persistence.liveQueryResult(key: key)
        return stored?.triples.contains { $0.attributeID == "todos/text" && $0.value == .string(text) } ?? false
      }
    }

    func failedMutationIDs() async -> [String] {
      await runtime.durableOutboxMutationsForTesting().filter { $0.status == .failed }.map(\.id)
    }
  }
}

// MARK: - Needs v1.9.4's wait setting: the red run on v1.9.3 drops everything below this line.

extension InstantRefusalHeldByServerTests {
  /// A pushed result shows another value for the slot while the connection's query is still unanswered: the refusal
  /// keeps waiting, and stands once the wait ends.
  @Test
  func aRefusalWhoseValueTheServersResultDoesNotShowFailsWhenTheWaitEnds() async throws {
    let fixture = try await Fixture.make("other-value") { $0.refusedReSendServerResultWaitMilliseconds = 3_000 }
    try await fixture.writeTextAndDropBeforeTheAnswer("first")
    await fixture.second.enqueue(InstantSupersededReplayTests.refused("tx-first"))
    await fixture.second.enqueue(fixture.refresh(text: "another device's text", processedTransactionID: 3))
    try await fixture.waitUntilTheStoredResultShows(text: "another device's text")
    let waiting = await InstantSupersededReplayTests.mutation("tx-first", in: fixture.runtime)?.status
    expectNoDifference(waiting, .pending, "still waiting: a later result may show the value")
    try await InstantSupersededReplayTests.waitUntil("the refusal is recorded") {
      await InstantSupersededReplayTests.mutation("tx-first", in: fixture.runtime)?.status == .failed
    }
    let failed = await fixture.failedMutationIDs()
    expectNoDifference(failed, ["tx-first"])
    let offered = await InstantSupersededReplayTests.transactIDs(sentTo: fixture.second)
    expectNoDifference(offered, ["tx-first"], "a refusal that stands is not offered again")
    _ = try await fixture.runtime.closeConnection()
  }

  /// The connection never answers its query: the refusal stands once the wait ends.
  @Test
  func aRefusedReSendNoResultShowsFailsWhenTheWaitEnds() async throws {
    let fixture = try await Fixture.make("no-result") { $0.refusedReSendServerResultWaitMilliseconds = 300 }
    try await fixture.writeTextAndDropBeforeTheAnswer("first")
    await fixture.second.enqueue(InstantSupersededReplayTests.refused("tx-first"))
    try await InstantSupersededReplayTests.waitUntil("the refusal is recorded") {
      await InstantSupersededReplayTests.mutation("tx-first", in: fixture.runtime)?.status == .failed
    }
    let failed = await fixture.failedMutationIDs()
    expectNoDifference(failed, ["tx-first"])
    _ = try await fixture.runtime.closeConnection()
  }
}
