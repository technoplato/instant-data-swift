// History
// 2026-10-31  #1492  Created. The wire encoder built an index of every server attribute (2,283 on a phone) for every
//                    mutation it sent: about 1.2 ms of CPU a send on a Mac mini, 2-3 ms on a phone, on the live session
//                    actor. The attributes change only with init-ok or a refresh-ok that carries them.
// 2026-10-31  #1496  A send started three unstructured tasks (its own, and instantLiveWithTimeout's work and deadline)
//                    and armed a 5 s timer. A frame is now written by one task, and one watcher per socket keeps the
//                    deadlines; writes stay independent, as the room and query registration races need.

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

  /// A send starts one task and arms no timer (#1496): the frame's own write, while the socket's one watcher keeps every
  /// write's deadline. A send started three tasks (its own, and instantLiveWithTimeout's work and deadline) and armed a
  /// 5 s timer, about 270 tasks and 90 timers a minute while recording.
  @Test
  func aSendStartsOneTaskAndArmsNoTimer() async throws {
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
    #expect(startedBySends == 100)
    #expect(startedWithTheSocket == 1, "the socket's deadline watcher")
    await live.close()
  }

  /// A frame held at the socket does not hold a later one (#1496): each frame is written by its own task, as each was
  /// before. The runtime leaves a room while a presence write is stuck (#461), and registers an equivalent query while
  /// the earlier one's removal is held (#1131); one task writing the frames in order made both wait for the held write.
  @Test
  func aFrameHeldAtTheSocketDoesNotHoldALaterOne() async throws {
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
      request: InstantLiveSessionRequest(appID: "live-send-path-independent"),
      transport: transport,
      makeID: { UUID().uuidString.lowercased() }
    )

    let first = Task { try await live.sendMutations([Self.lineWrite(0)], claimToken: nil) }
    await held.waitUntilHolding()
    _ = try await live.sendMutations([Self.lineWrite(1)], claimToken: nil)
    let whileHeld = await wire.sentMessages().filter { $0.op == "transact" }.compactMap(\.clientEventID)
    await held.release()
    _ = try await first.value

    #expect(whileHeld == ["mutation-1"])
    let written = await wire.sentMessages().filter { $0.op == "transact" }.compactMap(\.clientEventID)
    #expect(written == ["mutation-1", "mutation-0"])
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

  /// A write still in the socket at its deadline fails its caller then, with the live timeout's error, and nothing
  /// waits for it (#1496), as `instantLiveWithTimeout` never waited for work it abandoned (#1021).
  @Test
  func aWritePastItsDeadlineFailsItsCallerWithoutWaitingForIt() async throws {
    let held = InstantLiveHeldWrite(clientEventID: "held")
    let writer = InstantLiveSocketWriter(session: Self.socket(holding: held), timeoutMilliseconds: 50)

    do {
      try await writer.write(Self.frame("held"))
      Issue.record("Expected the write's deadline to fail it.")
    } catch let error as InstantError {
      #expect(error.code == .networkFailed)
      #expect(error.operation == "send Instant live session message")
      #expect(error.message == "Timed out after 50ms waiting for Instant live transport.")
    }

    #expect(await held.isHeld, "the writer waited for the write it abandoned")
    writer.finish()
    await held.release()
  }

  /// Finishing the writer refuses later frames, and a write in flight still completes (#1496).
  @Test
  func finishingTheWriterRefusesLaterFramesAndLetsWritesInFlightFinish() async throws {
    let held = InstantLiveHeldWrite(clientEventID: "first")
    let sent = InstantLiveSentFrames()
    let writer = InstantLiveSocketWriter(session: Self.socket(holding: held, recording: sent))
    let first = Task { try await writer.write(Self.frame("first")) }
    await held.waitUntilHolding()

    writer.finish()
    await #expect(throws: InstantSupersededLiveSessionSend.self) { try await writer.write(Self.frame("second")) }
    await held.release()
    try await first.value

    #expect(await sent.clientEventIDs == ["first"])
    #expect(writer.inFlightCountForTesting == 0)
  }

  /// A caller cancelled while its frame is being written does not stop the write, and returns when the socket took it
  /// (#1496, library-78).
  @Test
  func aCancelledCallerDoesNotStopItsWrite() async throws {
    let held = InstantLiveHeldWrite(clientEventID: "first")
    let sent = InstantLiveSentFrames()
    let writer = InstantLiveSocketWriter(session: Self.socket(holding: held, recording: sent))
    let caller = Task { try await writer.write(Self.frame("first")) }
    await held.waitUntilHolding()

    caller.cancel()
    await held.release()
    try await caller.value

    #expect(await sent.clientEventIDs == ["first"])
    writer.finish()
  }

  static func frame(_ clientEventID: String) -> InstantLiveMessage {
    InstantLiveMessage(op: "transact", clientEventID: clientEventID, fields: [:])
  }

  /// A socket whose writes pass `held`, then reach `sent`.
  static func socket(
    holding held: InstantLiveHeldWrite,
    recording sent: InstantLiveSentFrames = InstantLiveSentFrames()
  ) -> InstantLiveWebSocketSession {
    InstantLiveWebSocketSession(
      send: { message in
        await held.pass(message)
        await sent.record(message)
      },
      receive: {
        try await Task.sleep(for: .seconds(3_600))
        throw CancellationError()
      },
      close: {},
      abort: {}
    )
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

/// Holds the write of one message until released (#1496).
actor InstantLiveHeldWrite {
  private let clientEventID: String
  private var isHolding = false
  private var isReleased = false
  private var held: [CheckedContinuation<Void, Never>] = []
  private var holdingWaiters: [CheckedContinuation<Void, Never>] = []

  init(clientEventID: String) {
    self.clientEventID = clientEventID
  }

  func pass(_ message: InstantLiveMessage) async {
    guard message.clientEventID == clientEventID, !isReleased else { return }
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

  /// Whether the held write is waiting for ``release()``.
  var isHeld: Bool { !held.isEmpty }

  func release() {
    isReleased = true
    let continuations = held
    held = []
    continuations.forEach { $0.resume() }
  }
}

/// The frames a test socket took, in order (#1496).
actor InstantLiveSentFrames {
  private(set) var clientEventIDs: [String] = []

  func record(_ message: InstantLiveMessage) {
    clientEventIDs.append(message.clientEventID ?? message.op)
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
