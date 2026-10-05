import CustomDump
import Foundation
@testable import InstantSwiftDataCore
import Testing

/// #541: two maps that grew for a session's whole life are bounded by what is live.
///
/// A memory audit (#541) found that the store's TxIDInterner keeps every transaction ID it ever met, and the
/// live-query acknowledgement state keeps a revision and an outcome for every live-query key a session ever
/// registered. A client's agent replies restarted about 380 times in 16 minutes, each with a new key, and a recording
/// interns a new transaction for each of its 45-120 saves a minute.
@Suite(.serialized)
struct InstantSessionMapBoundsTests {
  static func temporaryCacheURL() throws -> URL {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("instant-session-map-bounds-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory.appendingPathComponent("instant.sqlite")
  }

  // MARK: - The transaction ID interner

  @Test
  func aPruneRebuildsTheTransactionIDsWhenTheyAreOverTwiceTheLiveOnes() async throws {
    var configuration = InstantRuntimeConfiguration(
      appID: "session-map-bounds-interner",
      persistenceURL: try Self.temporaryCacheURL(),
      initialAttributes: TodoExample.attributes
    )
    configuration.autoConnectLiveTransport = false
    let runtime = try await InstantRuntime.bootstrap(configuration: configuration)
    // One todo saved 1,200 times, each save its own transaction, as a live recording saves its newest section. The
    // interner is counted only past 1,024 IDs.
    let createdAt = InstantTimestamp(milliseconds: 1_700_000_541_000)
    for save in 0..<1_200 {
      let transactionID = "save-\(save)"
      _ = try await runtime.transact(
        InstantStoreTransaction(
          id: transactionID,
          operations: TodoExample.upsertOperations(
            id: "todo-saved-often",
            text: "draft \(save)",
            createdAt: createdAt,
            transactionID: transactionID
          )
        ),
        createdAt: InstantTimestamp(milliseconds: createdAt.milliseconds + Int64(save))
      )
    }
    let before = await runtime.store.internedTransactionIDCount()
    let triplesBefore = await runtime.store.snapshot().triples
    let liveTransactionIDs = Set(triplesBefore.map(\.txID))
    #expect(before > 1_200, "every save interned its transaction: \(before)")
    #expect(liveTransactionIDs.count < 10, "the saves replaced each other: \(liveTransactionIDs.count) live")

    _ = try await runtime.pruneLiveQueryResults(
      policy: configuration.liveQueryResultPruningPolicy,
      now: configuration.now()
    )

    let after = await runtime.store.internedTransactionIDCount()
    #expect(
      after <= 2 * liveTransactionIDs.count + 1,
      "after the prune the interner holds \(after) IDs for \(liveTransactionIDs.count) live ones"
    )
    // The rebuild renumbers transaction IDs; every triple still reads its own.
    let triplesAfter = await runtime.store.snapshot().triples
    expectNoDifference(triplesAfter, triplesBefore)
    // Writes after the rebuild still intern and read their transaction IDs.
    _ = try await runtime.transact(
      InstantStoreTransaction(
        id: "save-after-rebuild",
        operations: TodoExample.upsertOperations(
          id: "todo-saved-often",
          text: "after the rebuild",
          createdAt: createdAt,
          transactionID: "save-after-rebuild"
        )
      ),
      createdAt: InstantTimestamp(milliseconds: createdAt.milliseconds + 1_000)
    )
    let textTriple = try #require(
      await runtime.store.snapshot().triples.first { $0.attributeID == "todos/text" }
    )
    expectNoDifference(textTriple.value, .string("after the rebuild"))
    expectNoDifference(textTriple.txID, "save-after-rebuild")
    _ = try? await runtime.closeConnection()
  }

  // MARK: - Live-query acknowledgements

  static func messages(_ op: String, in session: LiveReactorParitySession) async -> [InstantLiveMessage] {
    await session.sentMessages().filter { $0.op == op }
  }

  static func waitForMessages(
    _ op: String,
    count: Int,
    in session: LiveReactorParitySession
  ) async throws -> [InstantLiveMessage] {
    let deadline = ContinuousClock.now + .seconds(10)
    while true {
      let sent = await messages(op, in: session)
      if sent.count >= count || ContinuousClock.now >= deadline { return sent }
      try await Task.sleep(for: .milliseconds(10))
    }
  }

  @Test
  func liveQueriesThatUnregisterLeaveNoAcknowledgementEntries() async throws {
    let session = LiveReactorParitySession(messages: [liveReactorInitOK(attrs: liveReactorTodoServerAttrs)])
    var configuration = InstantRuntimeConfiguration(
      appID: "session-map-bounds-acknowledgements",
      persistenceURL: try Self.temporaryCacheURL(),
      initialAttributes: TodoExample.attributes,
      liveTransport: session.transport
    )
    configuration.liveReconnectSleep = { _ in }
    let runtime = try await InstantRuntime.bootstrap(configuration: configuration)
    _ = try await runtime.connect()

    // Twelve distinct live queries, each answered by the server and then given up, as agent replies restarts with a
    // new room order.
    for index in 0..<12 {
      let plan = InstantQueryPlan(
        id: "todos.restart.\(index)",
        namespace: TodoExample.namespace,
        order: InstantQueryOrder("createdAt", .ascending),
        limit: index + 1
      )
      let observation = await runtime.observeQueryLease(plan)
      var iterator = observation.stream.makeAsyncIterator()
      _ = await iterator.next()
      let added = try await Self.waitForMessages("add-query", count: index + 1, in: session)
      try #require(added.count == index + 1, "add-query \(index) was sent")
      let query = try InstantLiveQueryEncoder.encode(plan)
      await session.enqueue(
        liveReactorAddQueryOK(
          query: query,
          processedTransactionID: "server-tx-\(index)",
          result: liveReactorTodoQueryResult(
            id: "todo-\(index)",
            text: "row \(index)",
            createdAt: InstantTimestamp(milliseconds: 1_700_000_541_000 + Int64(index))
          )
        )
      )
      // The answer is recorded as answered, then acknowledged: wait for both before the query is given up.
      let deadline = ContinuousClock.now + .seconds(10)
      while true {
        let answered = try await runtime.isAnsweredOnCurrentSocketForTesting(plan)
        let acknowledged = await runtime.liveQueryAcknowledgementKeyCountForTesting() > 0
        if answered && acknowledged { break }
        guard ContinuousClock.now < deadline else {
          Issue.record("The server's answer to query \(index) was never recorded.")
          break
        }
        try await Task.sleep(for: .milliseconds(5))
      }
      await observation.cancel()
      let removed = try await Self.waitForMessages("remove-query", count: index + 1, in: session)
      try #require(removed.count == index + 1, "remove-query \(index) was sent")
    }

    // The key is forgotten just after its remove-query is sent.
    let deadline = ContinuousClock.now + .seconds(5)
    var remembered = await runtime.liveQueryAcknowledgementKeyCountForTesting()
    while remembered > 0, ContinuousClock.now < deadline {
      try await Task.sleep(for: .milliseconds(10))
      remembered = await runtime.liveQueryAcknowledgementKeyCountForTesting()
    }
    expectNoDifference(remembered, 0, "keys remembered after every query unregistered")
    _ = try await runtime.closeConnection()
  }
}
