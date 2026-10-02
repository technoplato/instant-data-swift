import CustomDump
import Foundation
@testable import InstantSwiftDataCore
import Testing

/// #376: a write the server answers with a transient error keeps the socket.
///
/// A stalled server answers every `transact` with `{op: error, status: 500, type: operation-timed-out}`. Swift used to
/// release every claim and close the socket for it, so each reconnect re-sent init, every query, and the same write:
/// 36 reconnects and 324 add-queries in 12 s in the companion harness (`run.py agent-side --scenario transact-burst`).
/// Upstream `Reactor.js` `_handleMutationError` keeps the socket and drops the write; Swift keeps the socket and offers
/// the durable write again on it after a backoff that grows with each consecutive failure. Only a dead socket
/// reconnects.
@Suite(.serialized)
struct InstantTransientMutationRetryTests {
  static func transactTimedOut(_ mutationID: String) -> InstantLiveMessage {
    InstantLiveMessage(
      op: "error",
      clientEventID: mutationID,
      fields: [
        "message": .string("Operation timed out: handle-receive"),
        "type": .string("operation-timed-out"),
        "status": .number(500),
        "original-event": .object([
          "client-event-id": .string(mutationID),
          "op": .string("transact"),
        ]),
      ]
    )
  }

  static func transactOK(_ mutationID: String, transactionID: String) -> InstantLiveMessage {
    InstantLiveMessage(
      op: "transact-ok",
      clientEventID: mutationID,
      fields: ["tx-id": .string(transactionID)]
    )
  }

  static func temporaryCacheURL() throws -> URL {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("instant-transient-mutation-retry-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory.appendingPathComponent("instant.sqlite")
  }

  /// How many times `session` has been sent `op`, once `count` is reached or `timeout` passes.
  static func sentCount(
    of op: String,
    in session: LiveReactorParitySession,
    reaching count: Int,
    within timeout: Duration = .seconds(10)
  ) async throws -> Int {
    let deadline = ContinuousClock.now + timeout
    while true {
      let sent = await session.sentMessages().filter { $0.op == op }.count
      if sent >= count || ContinuousClock.now >= deadline { return sent }
      try await Task.sleep(for: .milliseconds(20))
    }
  }

  static func createTodo(_ runtime: InstantRuntime, id: String, at time: InstantTimestamp) async throws {
    try await runtime.transact(
      InstantStoreTransaction(
        id: "tx-\(id)",
        operations: TodoExample.createOperations(
          id: id,
          text: "written while the server stalls",
          createdAt: time,
          transactionID: "tx-\(id)"
        )
      ),
      createdAt: time
    )
  }

  @Test
  func aWriteAnsweredWithAServerTimeoutIsOfferedAgainOnTheSameSocket() async throws {
    let session = LiveReactorParitySession(messages: [
      liveReactorInitOK(attrs: liveReactorTodoServerAttrs, sessionID: "stalled-server")
    ])
    // One scripted session only: a reconnect would be a second connection request, and it would fail.
    let transport = LiveReactorParityTransport(sessions: [session])
    var configuration = InstantRuntimeConfiguration(
      appID: "transient-mutation-same-socket",
      persistenceURL: try Self.temporaryCacheURL(),
      initialAttributes: TodoExample.attributes,
      liveTransport: transport.transport
    )
    configuration.liveReconnectSleep = { _ in }
    let runtime = try await InstantRuntime.bootstrap(configuration: configuration)
    _ = try await runtime.connect()

    let mutationID = "tx-todo-stalled-write"
    try await Self.createTodo(runtime, id: "todo-stalled-write", at: InstantTimestamp(milliseconds: 1_700_000_376_000))
    #expect(try await Self.sentCount(of: "transact", in: session, reaching: 1) == 1)

    // The server stalls for three answers, then accepts the write.
    for answer in 1...3 {
      await session.enqueue(Self.transactTimedOut(mutationID))
      let offers = try await Self.sentCount(of: "transact", in: session, reaching: answer + 1)
      #expect(offers == answer + 1, "offer \(answer + 1) of the write should reach the same socket")
      guard offers == answer + 1 else { break }
    }
    await session.enqueue(Self.transactOK(mutationID, transactionID: "server-tx-after-stall"))
    let drained = try await instantLiveWithTimeout(
      operation: "wait for the stalled write to be accepted",
      timeoutMilliseconds: 10_000
    ) {
      try await runtime.observeConnectionStatus().first { $0.pendingMutationCount == 0 } != nil
    }
    #expect(drained)

    let connections = await transport.connectionRequests()
    expectNoDifference(connections.count, 1, "a transient server error must not reconnect a healthy socket")
    let ops = await session.sentMessages().map(\.op)
    expectNoDifference(ops, ["init", "transact", "transact", "transact", "transact"])
    let transactIDs = await session.sentMessages().filter { $0.op == "transact" }.map(\.clientEventID)
    expectNoDifference(transactIDs, Array(repeating: mutationID, count: 4))
    _ = try await runtime.closeConnection()
  }
}

extension InstantTransientMutationRetryTests {
  actor RetryRecorder {
    private(set) var retries: [(owner: InstantServerErrorRetryOwner, attempt: Int, delay: UInt64)] = []

    func record(_ owner: InstantServerErrorRetryOwner, _ attempt: Int, _ delay: UInt64) {
      retries.append((owner, attempt, delay))
    }

    func mutationDelays(_ mutationID: String) -> [UInt64] {
      retries.filter { $0.owner == .mutation(mutationID) }.map(\.delay)
    }

    func mutationAttempts(_ mutationID: String) -> [Int] {
      retries.filter { $0.owner == .mutation(mutationID) }.map(\.attempt)
    }
  }

  @Test
  func theRetryPolicyDoublesFromItsBaseIsCappedAndJittersDownByAtMostHalf() {
    let exact = InstantServerErrorRetryPolicy(baseMilliseconds: 250, maximumMilliseconds: 5_000, jitter: { 1 })
    expectNoDifference(
      (1...8).map { exact.delayMilliseconds(afterFailure: $0) },
      [250, 500, 1_000, 2_000, 4_000, 5_000, 5_000, 5_000]
    )
    expectNoDifference(exact.delayMilliseconds(afterFailure: 1_000), 5_000)
    let halved = InstantServerErrorRetryPolicy(baseMilliseconds: 250, maximumMilliseconds: 5_000, jitter: { 0.5 })
    expectNoDifference(halved.delayMilliseconds(afterFailure: 1), 125)
    // A jitter source outside 0.5...1 is clamped, so a delay never drops below half or exceeds the cap.
    let wild = InstantServerErrorRetryPolicy(baseMilliseconds: 250, maximumMilliseconds: 5_000, jitter: { 7 })
    expectNoDifference(wild.delayMilliseconds(afterFailure: 9), 5_000)
    let negative = InstantServerErrorRetryPolicy(baseMilliseconds: 250, maximumMilliseconds: 5_000, jitter: { -3 })
    expectNoDifference(negative.delayMilliseconds(afterFailure: 1), 125)
    for attempt in 1...12 {
      let delay = InstantServerErrorRetryPolicy().delayMilliseconds(afterFailure: attempt)
      let ceiling = exact.delayMilliseconds(afterFailure: attempt)
      #expect(delay <= ceiling && delay >= ceiling / 2, "attempt \(attempt): \(delay) outside \(ceiling / 2)...\(ceiling)")
    }
  }

  @Test
  func theBackoffGrowsWithEachConsecutiveFailureOfTheSameWrite() async throws {
    let session = LiveReactorParitySession(messages: [
      liveReactorInitOK(attrs: liveReactorTodoServerAttrs, sessionID: "growing-backoff")
    ])
    let transport = LiveReactorParityTransport(sessions: [session])
    let recorder = RetryRecorder()
    var configuration = InstantRuntimeConfiguration(
      appID: "transient-mutation-growing-backoff",
      persistenceURL: try Self.temporaryCacheURL(),
      initialAttributes: TodoExample.attributes,
      liveTransport: transport.transport
    )
    configuration.liveReconnectSleep = { _ in }
    configuration.liveServerErrorRetryPolicy = InstantServerErrorRetryPolicy(
      baseMilliseconds: 20,
      maximumMilliseconds: 80,
      jitter: { 1 }
    )
    configuration.onServerErrorRetryScheduledForTesting = { owner, attempt, delay in
      await recorder.record(owner, attempt, delay)
    }
    let runtime = try await InstantRuntime.bootstrap(configuration: configuration)
    _ = try await runtime.connect()
    let mutationID = "tx-todo-growing-backoff"
    try await Self.createTodo(runtime, id: "todo-growing-backoff", at: InstantTimestamp(milliseconds: 1_700_000_376_100))
    for answer in 1...4 {
      #expect(try await Self.sentCount(of: "transact", in: session, reaching: answer) == answer)
      await session.enqueue(Self.transactTimedOut(mutationID))
    }
    #expect(try await Self.sentCount(of: "transact", in: session, reaching: 5) == 5)
    await session.enqueue(Self.transactOK(mutationID, transactionID: "server-tx-growing-backoff"))
    _ = try #require(
      try await instantLiveWithTimeout(operation: "wait for the write", timeoutMilliseconds: 10_000) {
        try await runtime.observeConnectionStatus().first { $0.pendingMutationCount == 0 }
      }
    )
    let observed1 = await recorder.mutationAttempts(mutationID)
    expectNoDifference(observed1, [1, 2, 3, 4])
    let observed2 = await recorder.mutationDelays(mutationID)
    expectNoDifference(observed2, [20, 40, 80, 80])
    let observed3 = await transport.connectionRequests().count
    expectNoDifference(observed3, 1)
    _ = try await runtime.closeConnection()
  }

  @Test
  func afterAServerErrorDeliveryProbesWithOneWriteUntilTheServerAcceptsOne() async throws {
    let session = LiveReactorParitySession(messages: [
      liveReactorInitOK(attrs: liveReactorTodoServerAttrs, sessionID: "probe-one-write")
    ])
    let transport = LiveReactorParityTransport(sessions: [session])
    var configuration = InstantRuntimeConfiguration(
      appID: "transient-mutation-probe",
      persistenceURL: try Self.temporaryCacheURL(),
      initialAttributes: TodoExample.attributes,
      liveTransport: transport.transport
    )
    configuration.liveReconnectSleep = { _ in }
    configuration.liveServerErrorRetryPolicy = InstantServerErrorRetryPolicy(
      baseMilliseconds: 20,
      maximumMilliseconds: 20,
      jitter: { 1 }
    )
    let runtime = try await InstantRuntime.bootstrap(configuration: configuration)
    _ = try await runtime.connect()
    let ids = ["probe-a", "probe-b", "probe-c"]
    for (offset, id) in ids.enumerated() {
      try await Self.createTodo(
        runtime,
        id: id,
        at: InstantTimestamp(milliseconds: 1_700_000_376_200 + Int64(offset))
      )
    }
    #expect(try await Self.sentCount(of: "transact", in: session, reaching: 3) == 3)
    // The stalled server fails all three writes in flight.
    for id in ids {
      await session.enqueue(Self.transactTimedOut("tx-\(id)"))
    }
    // After the pause, only the outbox head is offered, and nothing else while it waits for its answer.
    #expect(try await Self.sentCount(of: "transact", in: session, reaching: 4) == 4)
    try await Task.sleep(for: .milliseconds(300))
    let probes = await session.sentMessages().filter { $0.op == "transact" }.dropFirst(3).map(\.clientEventID)
    expectNoDifference(probes, ["tx-probe-a"])
    // The server recovers: once it accepts the probe, the rest of the outbox goes out together.
    await session.enqueue(Self.transactOK("tx-probe-a", transactionID: "server-tx-probe-a"))
    #expect(try await Self.sentCount(of: "transact", in: session, reaching: 6) == 6)
    let resumed = await session.sentMessages().filter { $0.op == "transact" }.dropFirst(4).map(\.clientEventID)
    expectNoDifference(resumed, ["tx-probe-b", "tx-probe-c"])
    await session.enqueue(Self.transactOK("tx-probe-b", transactionID: "server-tx-probe-b"))
    await session.enqueue(Self.transactOK("tx-probe-c", transactionID: "server-tx-probe-c"))
    _ = try #require(
      try await instantLiveWithTimeout(operation: "wait for the outbox to drain", timeoutMilliseconds: 10_000) {
        try await runtime.observeConnectionStatus().first { $0.pendingMutationCount == 0 }
      }
    )
    let observed4 = await transport.connectionRequests().count
    expectNoDifference(observed4, 1)
    _ = try await runtime.closeConnection()
  }

  @Test
  func anErrorThatNoWriteQueryOrStreamOwnsKeepsTheSocket() async throws {
    let session = LiveReactorParitySession(messages: [
      liveReactorInitOK(attrs: liveReactorTodoServerAttrs, sessionID: "unrouted-error")
    ])
    let transport = LiveReactorParityTransport(sessions: [session])
    var configuration = InstantRuntimeConfiguration(
      appID: "unrouted-error-keeps-socket",
      persistenceURL: try Self.temporaryCacheURL(),
      initialAttributes: TodoExample.attributes,
      liveTransport: transport.transport
    )
    configuration.liveReconnectSleep = { _ in }
    let runtime = try await InstantRuntime.bootstrap(configuration: configuration)
    _ = try await runtime.connect()
    // A refusal for a stream reader that already stopped, and an answer to a write this runtime never sent.
    await session.enqueue(
      InstantLiveMessage(
        op: "error",
        clientEventID: "subscribe-stream-after-cancel",
        fields: [
          "message": .string("Stream is missing"),
          "status": .number(400),
          "original-event": .object([
            "client-event-id": .string("subscribe-stream-after-cancel"),
            "op": .string("subscribe-stream"),
          ]),
        ]
      )
    )
    await session.enqueue(Self.transactTimedOut("tx-never-sent"))
    // The socket still delivers: a write after the errors goes out on the same session.
    try await Self.createTodo(runtime, id: "after-unrouted", at: InstantTimestamp(milliseconds: 1_700_000_376_300))
    #expect(try await Self.sentCount(of: "transact", in: session, reaching: 1) == 1)
    try await Task.sleep(for: .milliseconds(200))
    let observed5 = await transport.connectionRequests().count
    expectNoDifference(observed5, 1)
    _ = try await runtime.closeConnection()
  }
}
