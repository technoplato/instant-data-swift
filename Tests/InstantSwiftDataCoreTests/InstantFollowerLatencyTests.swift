// History
// 2026-11-04  #1796  Created. A tablet following a live recording, 8,240 of its own writes pending, applied every
//                    server frame in arrival order at about 1.5 s each, superseded refreshes included, and showed the
//                    recording about six minutes late; its one-shot reads failed at a fixed 5 s while its socket was
//                    open and frames were applying.
// 2026-11-04  #1796  A one-shot read whose add-query met a socket that had just died; how old the newest server
//                    write is when the buffer applies it, which nothing measured on the tablet.

import CustomDump
import Foundation
import Testing

@testable import InstantSwiftDataCore

/// A follower applies the newest result of each query next, however deep its receive buffer, and a one-shot read waits
/// while the connection is busy delivering what came before its answer (#1796).
///
/// Upstream: the server drops a queued refresh that a newer one supersedes (`session.clj`, `combine [:refresh
/// :refresh]` keeps the second), `Reactor.js` replaces a query's stored result whole on every `refresh-ok`
/// (`querySubs[hash].result`), and its `queryOnce` waits 30 s (`QUERY_ONCE_TIMEOUT`).
@Suite(.serialized, .timeLimit(.minutes(3)))
struct InstantFollowerLatencyTests {
  // MARK: - The receive buffer

  /// A waiting `refresh-ok` loses the results a newer one restates, and one left with none leaves the buffer; the
  /// acknowledgement that arrived between them keeps its place.
  @Test
  func aWaitingRefreshLosesTheResultsANewerRefreshRestates() async throws {
    let frames = InstantLiveReceivedFrames(capacity: 16)
    for frame in [
      FollowerFrame.refresh(transaction: 101, [.list: 1, .page: 1]),
      FollowerFrame.transactOK("write-1", transaction: 102),
      FollowerFrame.refresh(transaction: 103, [.list: 2]),
      FollowerFrame.refresh(transaction: 104, [.page: 3]),
    ] {
      #expect(await frames.append(frame))
    }

    let taken = try await FollowerFrame.takeBuffered(from: frames)
    expectNoDifference(
      taken,
      ["transact-ok 102", "refresh-ok 103 list(2)", "refresh-ok 104 page(3)"],
      "#1796: the first refresh's list and page were both restated by newer frames before the applier reached it"
    )
  }

  /// A waiting `refresh-ok` that a newer one restates only in part keeps the rest.
  @Test
  func aWaitingRefreshKeepsTheResultsNoNewerRefreshRestates() async throws {
    let frames = InstantLiveReceivedFrames(capacity: 16)
    #expect(await frames.append(FollowerFrame.refresh(transaction: 101, [.list: 1, .page: 1])))
    #expect(await frames.append(FollowerFrame.refresh(transaction: 102, [.list: 2])))

    let taken = try await FollowerFrame.takeBuffered(from: frames)
    expectNoDifference(
      taken,
      ["refresh-ok 101 page(1)", "refresh-ok 102 list(2)"]
    )
  }

  /// A `refresh-ok` that carries `attrs` keeps every result: the applier records its attributes as it takes it, and a
  /// newer frame that omits them relies on that.
  @Test
  func aRefreshCarryingAttributesKeepsItsResults() async throws {
    let frames = InstantLiveReceivedFrames(capacity: 16)
    #expect(await frames.append(FollowerFrame.refresh(transaction: 101, [.list: 1], attrs: liveReactorTodoServerAttrs)))
    #expect(await frames.append(FollowerFrame.refresh(transaction: 102, [.list: 2])))

    let taken = try await FollowerFrame.takeBuffered(from: frames)
    expectNoDifference(
      taken,
      ["refresh-ok 101 list(1) attrs", "refresh-ok 102 list(2)"]
    )
  }

  /// A refresh never loses results to a frame that reflects an earlier transaction.
  @Test
  func aRefreshNeverLosesResultsToAnEarlierTransaction() async throws {
    let frames = InstantLiveReceivedFrames(capacity: 16)
    #expect(await frames.append(FollowerFrame.refresh(transaction: 105, [.list: 1])))
    #expect(await frames.append(FollowerFrame.refresh(transaction: 104, [.list: 2])))

    let taken = try await FollowerFrame.takeBuffered(from: frames)
    expectNoDifference(
      taken,
      ["refresh-ok 105 list(1)", "refresh-ok 104 list(2)"]
    )
  }

  /// A full buffer makes room when a newer refresh replaces a waiting one, so the reader keeps reading.
  @Test
  func aFullBufferMakesRoomWhenANewerRefreshReplacesAWaitingOne() async throws {
    let frames = InstantLiveReceivedFrames(capacity: 2)
    #expect(await frames.append(FollowerFrame.refresh(transaction: 101, [.list: 1])))
    #expect(await frames.append(FollowerFrame.refresh(transaction: 102, [.page: 1])))

    let appended = FollowerRecorder<Bool>()
    let append = Task {
      await appended.append(await frames.append(FollowerFrame.refresh(transaction: 103, [.list: 2])))
    }
    try await followerWait("the third frame buffered, or its reader waiting for room") {
      let finished = await !appended.values.isEmpty
      return finished || frames.readerIsWaitingForTesting
    }
    #expect(!frames.readerIsWaitingForTesting, "#1796: the reader waited although the newer list replaced the first")

    let taken = try await FollowerFrame.takeBuffered(from: frames)
    await append.value
    let appendedValues = await appended.values
    expectNoDifference(appendedValues, [true])
    expectNoDifference(taken, ["refresh-ok 102 page(1)", "refresh-ok 103 list(2)"])
  }

  /// The buffer measures how old the newest server write is when its frame finishes applying (#1796): a `refresh-ok`
  /// carrying a fact newer than every fact applied before counts, from the fact's server time (the fourth element of
  /// its triple, child nodes included) to the end of its apply. An answer to `add-query` restates what the server
  /// already holds, so it only moves the mark, and an older fact does not count. The tablet behind #1796 showed a live
  /// recording about six minutes late, and nothing it logged measured that.
  @Test
  func theBufferMeasuresHowOldTheNewestServerWriteIsWhenItIsApplied() async throws {
    let frames = InstantLiveReceivedFrames(capacity: 16, wallClockMilliseconds: { 1_700_000_010_000 })
    for frame in [
      FollowerFrame.answer(.list, factTime: 1_700_000_005_000),
      FollowerFrame.timedRefresh(transaction: 101, .page, factTime: 1_700_000_004_000),
      FollowerFrame.transactOK("write-1", transaction: 102),
      FollowerFrame.timedRefresh(transaction: 103, .list, factTime: 1_700_000_008_000),
      FollowerFrame.nestedRefresh(transaction: 104, .page, childFactTime: 1_700_000_009_500),
    ] {
      #expect(await frames.append(frame))
      // Taking the next frame ends the apply of the one before.
      _ = try await frames.next()
    }
    frames.finish(throwing: FollowerBufferEnded())
    await #expect(throws: FollowerBufferEnded.self) { try await frames.next() }

    expectNoDifference(
      frames.factLagsForTesting,
      [2_000, 500],
      "#1796: the refreshes at 103 and 104 brought the newest writes, 2.0 s and 0.5 s after the server stored them"
    )
  }

  /// The receive summary reports how old the newest writes were at the median, at p95 and at most (#1796).
  @Test
  func theReceiveSummaryReportsHowOldTheNewestWritesWere() throws {
    let start = ContinuousClock.now
    var meter = InstantLiveReceiveMeter(windowStart: start)
    meter.recordTake(waited: .milliseconds(3), buffered: 0)
    for lag in [400, 100, 300, 200, 5_000] {
      meter.recordFactLag(milliseconds: lag)
    }
    let window = meter.summary(at: start + .seconds(61), buffered: 0)
    let summary = try #require(window)

    expectNoDifference(
      [
        summary.factLagFrames, summary.factLagMedianMilliseconds, summary.factLagP95Milliseconds,
        summary.factLagMaxMilliseconds,
      ],
      [5, 300, 5_000, 5_000]
    )
  }

  // MARK: - A follower

  /// A follower held in a long apply while a writer's lines arrive applies the newest list once, after every
  /// acknowledgement of its own writes that arrived among them, and ends where applying every frame leads (#1796).
  ///
  /// The tablet behind #1796 received 29 `refresh-ok` of the recording list a minute and applied each in about 1.5 s
  /// with its own writes pending, so each new line waited behind every older restatement of the same list.
  @Test
  func aFollowerBehindALongApplyAppliesTheNewestListOnceAndEveryAcknowledgement() async throws {
    let transport = FollowerTransport()
    let gate = FollowerApplyGate()
    let box = FollowerRuntimeBox()
    let applied = FollowerRecorder<String>()
    var configuration = try followerConfiguration(appID: "follower-long-apply", transport: transport)
    configuration.onLiveReceiverEventAcquiredForTesting = {
      if let runtime = await box.runtime, let op = await runtime.liveFrameBeingAppliedForTesting() {
        await applied.append(op)
      }
      await gate.enter()
    }
    let runtime = try await InstantRuntime.bootstrap(configuration: configuration)
    await box.set(runtime)
    // Registered, so the cadence prune keeps the list's result.
    let observation = await runtime.observeQueryLease(TodoExample.query)

    try await withFollowerCleanup({ await gate.release() }) {
      _ = try await runtime.connect()
      let socket = try #require(await transport.socket(0))
      let writes = ["w1", "w2", "w3"]
      for (index, write) in writes.enumerated() {
        try await transactFollowerTodo(write, index: index, on: runtime)
      }
      try await followerWait("the pump to offer the three writes") { await socket.sentTransactIDs == writes }

      await socket.push(followerLongFrame)
      try await followerWait("the applier to hold the long frame") { await gate.enteredCount == 1 }
      // The writer's lines: refresh k restates the list with k lines and every write the server accepted before it.
      // Write j is accepted at transaction 100 + 30j + 5, between refreshes 3j and 3j + 1.
      for line in 1...12 {
        let accepted = writes.indices.filter { 30 * ($0 + 1) + 5 <= 10 * line }.map { writes[$0] }
        await socket.push(FollowerFrame.listRefresh(transaction: 100 + 10 * line, lines: line, acceptedWrites: accepted))
        if line % 3 == 0, line / 3 <= writes.count {
          let write = writes[line / 3 - 1]
          await socket.push(FollowerFrame.transactOK(write, transaction: 100 + 10 * line + 5))
        }
      }
      try await followerWait("the reader to buffer every frame") { await socket.isCaughtUp }

      await gate.release()
      try await followerWait("every frame to be applied") {
        let pending = await runtime.pendingMutations()
        let idle = await runtime.liveReceiverIsWaitingForAFrameForTesting()
        return pending.isEmpty && idle
      }

      let appliedOps = await applied.values
      expectNoDifference(
        appliedOps,
        ["follower-long-frame", "transact-ok", "transact-ok", "transact-ok", "refresh-ok"],
        "#1796: the follower applied refreshes that newer buffered refreshes restated"
      )
      let texts = try await runtime.queryLocally(TodoExample.query).values.compactMap { entity -> String? in
        guard case let .string(text)? = entity.values["text"]?.first else { return nil }
        return text
      }
      expectNoDifference(
        texts.sorted(),
        ((1...12).map { "line \($0)" } + writes.map { "local \($0)" }).sorted()
      )
      await observation.cancel()
      _ = try await runtime.closeConnection()
    }
  }

  // MARK: - One-shot reads

  /// A one-shot read whose answer waits more than 5 s behind a long apply is answered once the applier reaches it: the
  /// socket was open and the applier busy the whole time (#1796). It failed as "Network or live transport failed" on
  /// the tablet behind #1796, whose playback screen showed that text.
  @Test
  func aOneShotReadQueuedBehindALongApplyIsAnswered() async throws {
    let transport = FollowerTransport()
    let gate = FollowerApplyGate()
    var configuration = try followerConfiguration(appID: "follower-query-once", transport: transport)
    configuration.onLiveReceiverEventAcquiredForTesting = { await gate.enter() }
    let runtime = try await InstantRuntime.bootstrap(configuration: configuration)

    try await withFollowerCleanup({ await gate.release() }) {
      _ = try await runtime.connect()
      let socket = try #require(await transport.socket(0))
      await socket.push(followerLongFrame)
      try await followerWait("the applier to hold the long frame") { await gate.enteredCount == 1 }

      let read = Task { try await runtime.queryOnce(TodoExample.query) }
      try await followerWait("the read's add-query on the socket") { await socket.sentQueries.count == 1 }
      let query = try #require(await socket.sentQueries.first)
      await socket.push(
        liveReactorAddQueryOK(
          query: query,
          processedTransactionID: "110",
          result: liveReactorTodoQueryResult(
            id: "todo-line-1",
            text: "line 1",
            createdAt: InstantTimestamp(milliseconds: 1_700_000_000_001)
          )
        )
      )
      // Past the old fixed wait: the answer is in the buffer, behind the frame the applier holds.
      try await Task.sleep(for: .milliseconds(6_500))
      await gate.release()

      let emission = try await read.value
      expectNoDifference(emission.values.map(\.id), ["todo-line-1"])
      _ = try await runtime.closeConnection()
    }
  }

  /// A one-shot read whose `add-query` met a socket that had just died waits for the reconnect and is answered on the
  /// next socket (#1796), as upstream `Reactor.js` sends a queryOnce's add-query from `_flushPendingMessages` on the
  /// next `init-ok`, and as an observer's registration already waits here. A tablet resuming from 229 s suspended
  /// failed a read this way in 0 ms while its connection still read as open.
  @Test
  func aOneShotReadSentOnASocketThatJustDiedIsAnsweredAfterTheReconnect() async throws {
    let transport = FollowerTransport()
    let gate = FollowerApplyGate()
    var configuration = try followerConfiguration(appID: "follower-dead-socket", transport: transport)
    configuration.onLiveReceiverEventAcquiredForTesting = { await gate.enter() }
    let runtime = try await InstantRuntime.bootstrap(configuration: configuration)

    try await withFollowerCleanup({ await gate.release() }) {
      _ = try await runtime.connect()
      let socket = try #require(await transport.socket(0))
      // The applier is inside a frame when the socket dies, so the runtime has not taken the death yet.
      await socket.push(followerLongFrame)
      try await followerWait("the applier to hold the long frame") { await gate.enteredCount == 1 }
      await socket.die(with: followerSocketAborted)

      let read = Task { try await runtime.queryOnce(TodoExample.query) }
      try await followerWait("the read's add-query to fail on the dead socket") {
        await socket.failedSendOps.contains("add-query")
      }
      await gate.release()

      try await followerWait("the next socket to send the read's add-query") {
        await transport.socket(1)?.sentQueries.isEmpty == false
      }
      let next = try #require(await transport.socket(1))
      let query = try #require(await next.sentQueries.first)
      await next.push(
        liveReactorAddQueryOK(
          query: query,
          processedTransactionID: "120",
          result: liveReactorTodoQueryResult(
            id: "todo-line-1",
            text: "line 1",
            createdAt: InstantTimestamp(milliseconds: 1_700_000_000_001)
          )
        )
      )

      let emission = try await read.value
      expectNoDifference(emission.values.map(\.id), ["todo-line-1"])
      _ = try await runtime.closeConnection()
    }
  }

  /// A one-shot read on a socket that delivers nothing still fails after the 5 s stall, long before upstream's 30 s
  /// limit: a stall stays loud (F41).
  @Test
  func aOneShotReadOnASilentSocketFailsAfterTheStall() async throws {
    let transport = FollowerTransport()
    let configuration = try followerConfiguration(appID: "follower-silent", transport: transport)
    let runtime = try await InstantRuntime.bootstrap(configuration: configuration)
    _ = try await runtime.connect()

    let started = ContinuousClock.now
    var failure: InstantError?
    do {
      _ = try await runtime.queryOnce(TodoExample.query)
    } catch let error as InstantError {
      failure = error
    }
    let elapsed = ContinuousClock.now - started

    expectNoDifference(failure?.code, .networkFailed)
    #expect(elapsed >= .milliseconds(4_900), "failed after \(elapsed), before the stall")
    #expect(elapsed < .seconds(20), "failed after \(elapsed): the silent socket waited toward the 30 s limit")
    _ = try await runtime.closeConnection()
  }
}

// MARK: - Frames

/// The two live queries the buffer tests restate: the list and a page, as a follower's list and transcript page.
private enum FollowerQuery: CaseIterable {
  case list
  case page

  var json: InstantLiveJSONValue {
    switch self {
    case .list:
      .object(["todos": .object(["$": .object(["limit": .number(64)])])])
    case .page:
      .object(["todos": .object(["$": .object(["limit": .number(16)])])])
    }
  }

  var name: String {
    switch self {
    case .list: "list"
    case .page: "page"
    }
  }
}

private enum FollowerFrame {
  /// A `refresh-ok` restating each query's whole result with `rows` todos.
  static func refresh(
    transaction: Int,
    _ results: KeyValuePairs<FollowerQuery, Int>,
    attrs: [InstantLiveJSONValue] = []
  ) -> InstantLiveMessage {
    var fields: [String: InstantLiveJSONValue] = [
      "processed-tx-id": .number(Double(transaction)),
      "computations": .array(
        results.map { query, rows in
          .object([
            "instaql-query": query.json,
            "instaql-result": .array(todoResult(texts: (1...max(rows, 1)).prefix(rows).map { "line \($0)" })),
          ])
        }
      ),
    ]
    if !attrs.isEmpty {
      fields["attrs"] = .array(attrs)
    }
    return InstantLiveMessage(op: "refresh-ok", clientEventID: nil, fields: fields)
  }

  /// The follower's list query (`TodoExample.query`) restated with `lines` of the writer's lines and the follower's
  /// own writes the server accepted before it.
  static func listRefresh(transaction: Int, lines: Int, acceptedWrites: [String]) -> InstantLiveMessage {
    let query = (try? InstantLiveQueryEncoder.encode(TodoExample.query)) ?? .null
    var rows = (1...lines).map { line in
      todoRow(id: "todo-line-\(line)", text: "line \(line)", createdAt: 1_700_000_000_000 + Int64(line))
    }
    rows += acceptedWrites.enumerated().map { index, write in
      todoRow(id: "todo-\(write)", text: "local \(write)", createdAt: 1_700_000_100_000 + Int64(index))
    }
    return InstantLiveMessage(
      op: "refresh-ok",
      clientEventID: nil,
      fields: [
        "processed-tx-id": .number(Double(transaction)),
        "computations": .array([
          .object([
            "instaql-query": query,
            "instaql-result": .array([
              .object(["data": .object(["datalog-result": .object(["join-rows": .array(rows)])]), "child-nodes": .array([])])
            ]),
          ])
        ]),
      ]
    )
  }

  static func transactOK(_ write: String, transaction: Int) -> InstantLiveMessage {
    InstantLiveMessage(op: "transact-ok", clientEventID: write, fields: ["tx-id": .number(Double(transaction))])
  }

  /// A `refresh-ok` restating `query` with one todo whose facts the server stored at `factTime`.
  static func timedRefresh(transaction: Int, _ query: FollowerQuery, factTime: Int64) -> InstantLiveMessage {
    timedRefresh(transaction: transaction, query, nodes: [timedNode(id: "todo-\(transaction)", factTime: factTime)])
  }

  /// A `refresh-ok` whose newest fact is in a child node, as a parent row's included rows are.
  static func nestedRefresh(transaction: Int, _ query: FollowerQuery, childFactTime: Int64) -> InstantLiveMessage {
    let child = timedNode(id: "todo-child-\(transaction)", factTime: childFactTime)
    return timedRefresh(
      transaction: transaction,
      query,
      nodes: [timedNode(id: "todo-parent-\(transaction)", factTime: childFactTime - 60_000, children: [child])]
    )
  }

  /// The answer to an `add-query` for `query`: one todo whose facts the server stored at `factTime`.
  static func answer(_ query: FollowerQuery, factTime: Int64) -> InstantLiveMessage {
    InstantLiveMessage(
      op: "add-query-ok",
      clientEventID: nil,
      fields: [
        "q": query.json,
        "processed-tx-id": .number(100),
        "result": .array([timedNode(id: "todo-answer", factTime: factTime)]),
      ]
    )
  }

  private static func timedRefresh(
    transaction: Int,
    _ query: FollowerQuery,
    nodes: [InstantLiveJSONValue]
  ) -> InstantLiveMessage {
    InstantLiveMessage(
      op: "refresh-ok",
      clientEventID: nil,
      fields: [
        "processed-tx-id": .number(Double(transaction)),
        "computations": .array([.object(["instaql-query": query.json, "instaql-result": .array(nodes)])]),
      ]
    )
  }

  private static func timedNode(
    id: String,
    factTime: Int64,
    children: [InstantLiveJSONValue] = []
  ) -> InstantLiveJSONValue {
    .object([
      "data": .object([
        "datalog-result": .object(["join-rows": .array([todoRow(id: id, text: id, createdAt: factTime)])])
      ]),
      "child-nodes": .array(children),
    ])
  }

  /// Takes every frame the buffer holds, a waiting reader's frame included, and describes each.
  static func takeBuffered(from frames: InstantLiveReceivedFrames) async throws -> [String] {
    var taken: [String] = []
    while frames.bufferedCountForTesting > 0 {
      taken.append(describe(try await frames.next()))
    }
    return taken
  }

  /// `op transaction` and, for a refresh, each query's name and row count in the frame's order.
  static func describe(_ message: InstantLiveMessage) -> String {
    switch message.op {
    case "transact-ok":
      return "transact-ok \(number(message.fields["tx-id"]))"
    case "refresh-ok":
      let results = (message.fields["computations"]?.arrayValue ?? []).map { computation -> String in
        let query = computation.objectValue?["instaql-query"]
        let name = FollowerQuery.allCases.first { $0.json == query }?.name ?? "?"
        let data = computation.objectValue?["instaql-result"]?.arrayValue?.first?.objectValue?["data"]
        let rows = data?.objectValue?["datalog-result"]?.objectValue?["join-rows"]?.arrayValue?.count ?? 0
        return "\(name)(\(rows))"
      }
      let attrs = (message.fields["attrs"]?.arrayValue?.isEmpty ?? true) ? "" : " attrs"
      return "refresh-ok \(number(message.fields["processed-tx-id"])) \(results.joined(separator: " "))\(attrs)"
    default:
      return message.op
    }
  }

  private static func number(_ value: InstantLiveJSONValue?) -> String {
    switch value {
    case let .number(number)?: String(Int(number))
    case let .string(text)?: text
    default: "?"
    }
  }

  private static func todoResult(texts: [String]) -> [InstantLiveJSONValue] {
    let rows = texts.enumerated().map { index, text in
      todoRow(id: "todo-\(index)", text: text, createdAt: 1_700_000_000_000 + Int64(index))
    }
    return [.object(["data": .object(["datalog-result": .object(["join-rows": .array(rows)])]), "child-nodes": .array([])])]
  }

  private static func todoRow(id: String, text: String, createdAt: Int64) -> InstantLiveJSONValue {
    func fact(_ attribute: String, _ value: InstantLiveJSONValue) -> InstantLiveJSONValue {
      .array([.string(id), .string(attribute), value, .number(Double(createdAt))])
    }
    return .array([
      fact("server-todos-id", .string(id)),
      fact("server-todos-text", .string(text)),
      fact("server-todos-is-completed", .bool(false)),
      fact("server-todos-created-at", .number(Double(createdAt))),
    ])
  }
}

/// The error a suspended app's socket fails with when it resumes (POSIX 53).
private let followerSocketAborted = NSError(
  domain: NSPOSIXErrorDomain,
  code: 53,
  userInfo: [NSLocalizedDescriptionKey: "Software caused connection abort"]
)

/// An unknown op: the runtime records it as the frame being applied and ignores it otherwise. The apply gate holds it
/// to stand in for an apply that takes seconds.
private let followerLongFrame = InstantLiveMessage(op: "follower-long-frame", clientEventID: nil, fields: [:])

// MARK: - Scripted sockets

/// One scripted Instant socket: pushed frames reach `receive()` in order, and every sent frame is recorded.
private actor FollowerSocket {
  private struct PendingReceive {
    var id: UUID
    var abortToken: UUID
    var continuation: InstantLiveTestThrowingContinuationBox<InstantLiveMessage>
  }

  private let abortState = InstantLiveTestWireAbortState()
  private var frames: [InstantLiveMessage]
  private var pendingReceive: PendingReceive?
  private var sent: [InstantLiveMessage] = []
  private var isClosed = false
  private var death: (any Error)?
  /// The ops of the frames sent after the socket died, each of which failed.
  private(set) var failedSendOps: [String] = []

  init(frames: [InstantLiveMessage]) {
    self.frames = frames
  }

  nonisolated var session: InstantLiveWebSocketSession {
    InstantLiveWebSocketSession(
      send: { message in try await self.send(message) },
      receive: { try await self.receive() },
      close: { await self.close() },
      abort: { self.abortState.abort() }
    )
  }

  /// Every pushed frame has been handed to a `receive()`, and another `receive()` is waiting.
  var isCaughtUp: Bool { frames.isEmpty && pendingReceive != nil }

  var sentTransactIDs: [String] {
    sent.filter { $0.op == "transact" }.compactMap(\.clientEventID)
  }

  /// The queries of every `add-query` sent, in order.
  var sentQueries: [InstantLiveJSONValue] {
    sent.filter { $0.op == "add-query" }.compactMap { $0.fields["q"] }
  }

  func push(_ frame: InstantLiveMessage) {
    guard !isClosed else { return }
    if let pending = takePendingReceive() {
      pending.continuation.resume(returning: frame)
    } else {
      frames.append(frame)
    }
  }

  /// Ends the socket the way the system's abort after a suspension did: the pending receive and every later send fail.
  func die(with error: any Error) {
    guard death == nil else { return }
    death = error
    takePendingReceive()?.continuation.resume(throwing: error)
  }

  private func send(_ message: InstantLiveMessage) throws {
    try abortState.check()
    if let death {
      failedSendOps.append(message.op)
      throw death
    }
    sent.append(message)
  }

  private func receive() async throws -> InstantLiveMessage {
    try abortState.check()
    if !frames.isEmpty {
      return frames.removeFirst()
    }
    if let death { throw death }
    if isClosed { throw CancellationError() }
    let id = UUID()
    defer { clearPendingReceive(id: id) }
    return try await withCheckedThrowingContinuation { rawContinuation in
      let continuation = InstantLiveTestThrowingContinuationBox(rawContinuation)
      guard let abortToken = abortState.register({ continuation.resume(throwing: CancellationError()) }) else {
        continuation.resume(throwing: CancellationError())
        return
      }
      pendingReceive = PendingReceive(id: id, abortToken: abortToken, continuation: continuation)
    }
  }

  private func close() {
    isClosed = true
    abortState.abort()
  }

  private func takePendingReceive() -> PendingReceive? {
    guard let pending = pendingReceive else { return nil }
    pendingReceive = nil
    abortState.unregister(pending.abortToken)
    return pending
  }

  private func clearPendingReceive(id: UUID) {
    guard pendingReceive?.id == id else { return }
    _ = takePendingReceive()
  }
}

/// Opens a fresh `FollowerSocket`, with `init-ok` queued, for every connection attempt.
private actor FollowerTransport {
  private var sockets: [FollowerSocket] = []

  nonisolated var client: InstantLiveTransportClient {
    .connectionAttempts { _ in
      let connection = InstantLiveTestConnectionContinuation()
      return InstantLiveConnectionAttempt(
        connect: {
          connection.start { await self.openSocket() }
          return try await connection.connect()
        },
        abort: { connection.abort() }
      )
    }
  }

  func socket(_ index: Int) -> FollowerSocket? {
    sockets.indices.contains(index) ? sockets[index] : nil
  }

  private func openSocket() -> InstantLiveWebSocketSession {
    let socket = FollowerSocket(frames: [
      liveReactorInitOK(attrs: liveReactorTodoServerAttrs, sessionID: "follower-\(sockets.count + 1)")
    ])
    sockets.append(socket)
    return socket.session
  }
}

/// Holds the first frame in the runtime's applier through `onLiveReceiverEventAcquiredForTesting` until `release()`;
/// every later frame passes.
private actor FollowerApplyGate {
  private var holds = true
  private var parked: [CheckedContinuation<Void, Never>] = []
  private(set) var enteredCount = 0

  func enter() async {
    enteredCount += 1
    guard holds else { return }
    await withCheckedContinuation { parked.append($0) }
  }

  func release() {
    holds = false
    let parked = parked
    self.parked.removeAll()
    for frame in parked {
      frame.resume()
    }
  }
}

private actor FollowerRuntimeBox {
  private(set) var runtime: InstantRuntime?

  func set(_ runtime: InstantRuntime) {
    self.runtime = runtime
  }
}

private actor FollowerRecorder<Value: Sendable> {
  private(set) var values: [Value] = []

  func append(_ value: Value) {
    values.append(value)
  }
}

private struct FollowerWaitTimedOut: Error, CustomStringConvertible {
  var description: String
}

private struct FollowerBufferEnded: Error {}

// MARK: - Helpers

/// A frozen clock keeps every delivery claim inside its acknowledgement deadline, so no deadline replaces a
/// connection behind a test's back.
private func followerConfiguration(
  appID: String,
  transport: FollowerTransport
) throws -> InstantRuntimeConfiguration {
  let directory = FileManager.default.temporaryDirectory
    .appendingPathComponent("InstantFollowerLatencyTests-\(UUID().uuidString)")
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  var configuration = InstantRuntimeConfiguration(
    appID: appID,
    persistenceURL: directory.appendingPathComponent("state.sqlite"),
    initialAttributes: TodoExample.attributes,
    now: { InstantTimestamp(milliseconds: 1_700_000_000_000) },
    liveTransport: transport.client
  )
  configuration.autoConnectLiveTransport = false
  return configuration
}

private func transactFollowerTodo(_ write: String, index: Int, on runtime: InstantRuntime) async throws {
  let createdAt = InstantTimestamp(milliseconds: 1_700_000_100_000 + Int64(index))
  try await runtime.transact(
    InstantStoreTransaction(
      id: write,
      operations: TodoExample.createOperations(
        id: "todo-\(write)",
        text: "local \(write)",
        createdAt: createdAt,
        transactionID: write
      )
    ),
    createdAt: createdAt
  )
}

/// Polls `condition` every 2 ms, up to the hang bound (#1021).
private func followerWait(
  _ description: String,
  _ condition: @Sendable () async throws -> Bool
) async throws {
  let deadline = ContinuousClock.now + .milliseconds(Int(InstantTestWait.hangMilliseconds))
  while !(try await condition()) {
    guard ContinuousClock.now < deadline else {
      throw FollowerWaitTimedOut(description: "Timed out waiting for \(description).")
    }
    try await Task.sleep(nanoseconds: 2_000_000)
  }
}

/// Runs `cleanup` after `body`, including when `body` throws, so a failed wait never leaves a parked task behind.
private func withFollowerCleanup(
  _ cleanup: @Sendable () async -> Void,
  _ body: () async throws -> Void
) async throws {
  do {
    try await body()
  } catch {
    await cleanup()
    throw error
  }
  await cleanup()
}
