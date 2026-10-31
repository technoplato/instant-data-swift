// History
// 2026-10-31  #1492  Created. The wire encoder built an index of every server attribute (2,283 on a phone) for every
//                    mutation it sent: about 1.2 ms of CPU a send on a Mac mini, 2-3 ms on a phone, on the live session
//                    actor. The attributes change only with init-ok or a refresh-ok that carries them.
// 2026-10-31  #1496  A send started three unstructured tasks (its own, and instantLiveWithTimeout's work and deadline)
//                    and armed a 5 s timer; two sends that overlapped could reach the socket in either order.

import CustomDump
import Foundation
import Testing

@testable import InstantSwiftDataCore

@Suite
struct InstantLiveSendPathTests {
  /// One resolver per server schema (#1492): a hundred sends on one connection build the attribute index once, and
  /// each still goes out with the server's attribute ids.
  @Test
  func aConnectionBuildsItsAttributeResolverOnceForEverySend() async throws {
    let wire = LiveReactorParitySession(messages: [liveReactorInitOK(attrs: Self.attributes)])
    let live = InstantRuntimeLiveSession()
    try await live.open(
      request: InstantLiveSessionRequest(appID: "live-send-path-resolver"),
      transport: wire.transport,
      makeID: { UUID().uuidString.lowercased() }
    )

    for index in 0..<100 {
      let mutation = Self.lineWrite(index)
      try await live.sendMutations([mutation], claimToken: nil)
      // The server's answer, as the runtime records it, so the in-flight window never fills.
      await live.releaseMutationReservations([mutation.mutationID], timedOut: false)
    }

    let transacts = await wire.sentMessages().filter { $0.op == "transact" }
    // Counts use #expect: IssueReporting records nothing in release, where expectNoDifference passes silently.
    #expect(transacts.count == 100)
    expectNoDifference(
      transacts.last?.fields["tx-steps"],
      .array([
        .array([.string("add-triple"), .string("line-99"), .string("server-attr-41"), .string("line 99")]),
        .array([.string("add-triple"), .string("line-99"), .string("server-attr-2282"), .number(99)]),
      ])
    )
    let resolverBuilds = await live.attributeResolverBuildCountForTesting()
    #expect(resolverBuilds == 1)
    await live.close()
  }

  /// A refresh-ok that carries attributes changes the schema the next send resolves against (#1492): the kept resolver
  /// is dropped with the old attributes and the next send builds one from the new ones.
  @Test
  func aRefreshThatCarriesAttributesRebuildsTheResolverForTheNextSend() async throws {
    let wire = LiveReactorParitySession(messages: [liveReactorInitOK(attrs: Self.attributes)])
    let live = InstantRuntimeLiveSession()
    try await live.open(
      request: InstantLiveSessionRequest(appID: "live-send-path-new-attributes"),
      transport: wire.transport,
      makeID: { UUID().uuidString.lowercased() }
    )
    let first = Self.lineWrite(0)
    try await live.sendMutations([first], claimToken: nil)
    await live.releaseMutationReservations([first.mutationID], timedOut: false)

    let (refreshes, refreshed) = AsyncStream.makeStream(of: Void.self)
    try await live.startReceiving(
      onEvent: { event, _, _ in
        if case .refreshOK = event { refreshed.yield() }
      },
      onFailure: { _ in }
    )
    let added = liveReactorServerAttr(id: "server-attr-added", name: "speaker", namespace: "namespace0")
    await wire.enqueue(
      InstantLiveMessage(
        op: "refresh-ok",
        clientEventID: nil,
        fields: [
          "attrs": .array(Self.attributes + [added]),
          "computations": .array([]),
          "processed-tx-id": .string("1"),
        ]
      )
    )
    var iterator = refreshes.makeAsyncIterator()
    _ = await iterator.next()

    let second = InstantTransportMutation(
      mutationID: "mutation-speaker",
      transactionID: "transaction-speaker",
      createdAt: InstantTimestamp(milliseconds: 1_793_400_001_000),
      status: .pending,
      preconditions: [],
      txSteps: [.addTriple(entity: .id("line-1"), attributeID: "namespace0/speaker", value: .string("A"))]
    )
    let failures = try await live.sendMutations([second], claimToken: nil)

    #expect(failures.isEmpty)
    let transacts = await wire.sentMessages().filter { $0.op == "transact" }
    expectNoDifference(
      transacts.last?.fields["tx-steps"],
      .array([.array([.string("add-triple"), .string("line-1"), .string("server-attr-added"), .string("A")])])
    )
    let resolverBuilds = await live.attributeResolverBuildCountForTesting()
    #expect(resolverBuilds == 2)
    await live.close()
  }

  /// A send starts no task of its own (#1496): the socket's writer and its deadline watcher, started with the socket,
  /// write every frame. A send started three tasks and armed a 5 s timer, about 270 tasks and 90 timers a minute while
  /// recording.
  @Test
  func aSendStartsNoTaskOfItsOwn() async throws {
    let wire = LiveReactorParitySession(messages: [liveReactorInitOK(attrs: Self.attributes)])
    let live = InstantRuntimeLiveSession()
    try await live.open(
      request: InstantLiveSessionRequest(appID: "live-send-path-tasks"),
      transport: wire.transport,
      makeID: { UUID().uuidString.lowercased() }
    )
    let startedWithTheSocket = await live.sendTaskStartCountForTesting()

    for index in 0..<100 {
      let mutation = Self.lineWrite(index)
      try await live.sendMutations([mutation], claimToken: nil)
      await live.releaseMutationReservations([mutation.mutationID], timedOut: false)
    }

    let startedBySends = await live.sendTaskStartCountForTesting() - startedWithTheSocket
    let transacts = await wire.sentMessages().filter { $0.op == "transact" }
    #expect(transacts.count == 100)
    #expect(startedBySends <= 100, "at most one task a send")
    #expect(startedBySends == 0)
    #expect(startedWithTheSocket <= 2)
    await live.close()
  }

  /// Frames leave in the order the session sent them (#1496), as upstream `Reactor.js` writes each with a synchronous
  /// `ws.send`: a send that begins while an earlier one is still being written goes after it. Each send wrote from its
  /// own task, so the later one could reach the socket first.
  @Test
  func framesLeaveInTheOrderTheSessionSentThem() async throws {
    let wire = LiveReactorParitySession(messages: [liveReactorInitOK(attrs: Self.attributes)])
    let held = InstantLiveHeldWrite(clientEventID: "mutation-0")
    let transport = InstantLiveTransportClient.immediate { _ in
      let inner = wire.webSocketSession
      return InstantLiveWebSocketSession(
        send: { message in
          await held.pass(message)
          try await inner.send(message)
        },
        receive: { try await inner.receive() },
        close: { await inner.close() },
        abort: { inner.abort() }
      )
    }
    let live = InstantRuntimeLiveSession()
    try await live.open(
      request: InstantLiveSessionRequest(appID: "live-send-path-order"),
      transport: transport,
      makeID: { UUID().uuidString.lowercased() }
    )

    let first = Task { try await live.sendMutations([Self.lineWrite(0)], claimToken: nil) }
    await held.waitUntilHolding()
    let second = Task { try await live.sendMutations([Self.lineWrite(1)], claimToken: nil) }
    let entered = ContinuousClock.now + InstantTestWait.hang
    while await live.inFlightSendCountForTesting() < 2, ContinuousClock.now < entered {
      try await Task.sleep(for: .milliseconds(1))
    }
    // A write that does not wait for the one ahead of it reaches the socket now.
    _ = await held.waitUntilPassed("mutation-1", atMost: .milliseconds(500))
    await held.release()
    _ = try await first.value
    _ = try await second.value

    let order = await wire.sentMessages().filter { $0.op == "transact" }.compactMap(\.clientEventID)
    expectNoDifference(order, ["mutation-0", "mutation-1"])
    #expect(order == ["mutation-0", "mutation-1"])
    await live.close()
  }

  /// The send path's own cost (#1496), measured in release with `INSTANT_SEND_PATH_BENCH=1`: 20,000 transacts through
  /// one live session to a socket that takes each at once. Prints the process's CPU time and the wall time per send, and
  /// the CPU of the 5.5 s after the last one, when the timers a send armed and cancelled still fire.
  @Test(.enabled(if: ProcessInfo.processInfo.environment["INSTANT_SEND_PATH_BENCH"] == "1"))
  func measureTheSendPath() async throws {
    let wire = LiveReactorParitySession(messages: [liveReactorInitOK(attrs: Self.attributes)])
    let live = InstantRuntimeLiveSession()
    try await live.open(
      request: InstantLiveSessionRequest(appID: "live-send-path-bench"),
      transport: wire.transport,
      makeID: { UUID().uuidString.lowercased() }
    )
    func send(_ indices: Range<Int>) async throws {
      for index in indices {
        let mutation = Self.lineWrite(index)
        try await live.sendMutations([mutation], claimToken: nil)
        await live.releaseMutationReservations([mutation.mutationID], timedOut: false)
      }
    }
    try await send(0..<1_000)
    try await Task.sleep(for: .milliseconds(5_500))

    let sends = 20_000
    let cpuStart = clock_gettime_nsec_np(CLOCK_PROCESS_CPUTIME_ID)
    let wallStart = ContinuousClock.now
    try await send(1_000..<(1_000 + sends))
    let wall = ContinuousClock.now - wallStart
    let cpuSends = clock_gettime_nsec_np(CLOCK_PROCESS_CPUTIME_ID) - cpuStart
    try await Task.sleep(for: .milliseconds(5_500))
    let cpuTail = clock_gettime_nsec_np(CLOCK_PROCESS_CPUTIME_ID) - cpuStart - cpuSends

    let wallMicroseconds = Double(wall.components.seconds) * 1e6 + Double(wall.components.attoseconds) / 1e12
    print(
      "SENDPATH n=\(sends) cpu_per_send_us=\(String(format: "%.2f", Double(cpuSends) / Double(sends) / 1_000)) "
        + "wall_per_send_us=\(String(format: "%.2f", wallMicroseconds / Double(sends))) "
        + "tail_cpu_ms=\(String(format: "%.2f", Double(cpuTail) / 1e6)) "
        + "send_tasks=\(await live.sendTaskStartCountForTesting())"
    )
    await live.close()
  }

  /// A real-size schema: 2,283 attributes, as a phone's init-ok carries (`RealSizeFixture`), across 41 namespaces.
  static let attributes: [InstantLiveJSONValue] = (0..<2_283).map { index in
    liveReactorServerAttr(
      id: "server-attr-\(index)",
      name: "field\(index)",
      namespace: "namespace\(index % 41)"
    )
  }

  /// A transcript line's write, naming two of the schema's attributes by their local `namespace/name`.
  static func lineWrite(_ index: Int) -> InstantTransportMutation {
    InstantTransportMutation(
      mutationID: "mutation-\(index)",
      transactionID: "transaction-\(index)",
      createdAt: InstantTimestamp(milliseconds: 1_793_400_000_000 + Int64(index)),
      status: .pending,
      preconditions: [],
      txSteps: [
        .addTriple(entity: .id("line-\(index)"), attributeID: "namespace0/field41", value: .string("line \(index)")),
        .addTriple(entity: .id("line-\(index)"), attributeID: "namespace27/field2282", value: .number(Double(index))),
      ]
    )
  }
}

/// Holds the write of one message until released, and records the client event ids written past it (#1496).
actor InstantLiveHeldWrite {
  private let clientEventID: String
  private var isHolding = false
  private var isReleased = false
  private var held: [CheckedContinuation<Void, Never>] = []
  private var holdingWaiters: [CheckedContinuation<Void, Never>] = []
  private var passed: [String] = []

  init(clientEventID: String) {
    self.clientEventID = clientEventID
  }

  func pass(_ message: InstantLiveMessage) async {
    guard message.clientEventID == clientEventID, !isReleased else {
      if let id = message.clientEventID { passed.append(id) }
      return
    }
    isHolding = true
    let waiters = holdingWaiters
    holdingWaiters = []
    waiters.forEach { $0.resume() }
    await withCheckedContinuation { held.append($0) }
  }

  func waitUntilHolding() async {
    guard !isHolding else { return }
    await withCheckedContinuation { holdingWaiters.append($0) }
  }

  /// Whether `clientEventID`'s write went past the hold within `limit`.
  func waitUntilPassed(_ clientEventID: String, atMost limit: Duration) async -> Bool {
    let deadline = ContinuousClock.now + limit
    while !passed.contains(clientEventID), ContinuousClock.now < deadline {
      try? await Task.sleep(for: .milliseconds(5))
    }
    return passed.contains(clientEventID)
  }

  func release() {
    isReleased = true
    let continuations = held
    held = []
    continuations.forEach { $0.resume() }
  }
}

extension ContentionHarness {
  /// What the library's energy meter measured over an exercise's window (#1492): each operation that ran, its count, its
  /// CPU, and its CPU per call, so a send's encode or an acknowledgement's CPU is read from the same run as the gate's.
  func reportEnergy(_ exercise: String, _ energy: InstantEnergySnapshot) {
    for operation in InstantEnergyOperation.allCases {
      let measure = energy[operation]
      guard measure.count > 0 else { continue }
      let cpuMilliseconds = Double(measure.cpuNanoseconds) / 1_000_000
      printFields(exercise, "energy", [
        ("op", operation.rawValue),
        ("n", String(measure.count)),
        ("cpu_ms", ContentionReport.milliseconds(cpuMilliseconds)),
        ("cpu_per_call_us", String(format: "%.1f", cpuMilliseconds * 1_000 / Double(measure.count))),
        ("wall_ms", ContentionReport.milliseconds(Double(measure.wallNanoseconds) / 1_000_000)),
      ])
    }
  }
}
