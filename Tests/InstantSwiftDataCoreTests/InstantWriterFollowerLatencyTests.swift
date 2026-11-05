// History
// 2026-11-04  #1796  Created. A writer and a follower over one scripted server: the writer's lines reach a follower
//                    that spends 1.5 s on each server frame while its own writes drain, within seconds, and the lag
//                    stays flat. A tablet following a live recording that way showed it about six minutes late.
// 2026-11-05  #1796  The lags are printed when the test passes too, for the release record.

import CustomDump
import Foundation
import Testing

@testable import InstantSwiftDataCore

/// A writer's lines reach a follower within seconds however long the writer records, while the follower spends seconds
/// on each server frame and its own writes drain (#1796).
///
/// On 2026-11-04 a tablet followed a phone's live recording with 8,240 of its own writes pending. It spent about 1.5 s
/// on each server frame and received, each minute, 29 `refresh-ok` of the recording list and 31 `transact-ok` of its
/// own writes: about 90 s of applies a minute. Applied in arrival order, each new line waited behind every older
/// restatement of the same list, the wait grew every minute, and the tablet showed the recording about six minutes
/// late. A `refresh-ok` restates each of its queries' results whole, so the follower needs only the newest one: the
/// server combines the refreshes it has not sent the same way (`session.clj`, `combine [:refresh :refresh]` keeps the
/// second), and `Reactor.js` replaces a query's stored result whole on each one. Acknowledgements keep their order.
///
/// Both runtimes run their live sessions over scripted sockets, and the test is the server between them: it accepts
/// each write the writer sends, acknowledges it and restates the follower's list, and it acknowledges the follower's
/// own writes at the tablet's rate. Time is the test's clock. Every frame arrives at its scheduled time, and the
/// follower's applier spends 1.5 s on each frame it takes: `onLiveReceiverEventAcquiredForTesting` holds the frame
/// until the clock reaches the apply's end. A line's lag runs from the writer's write to the end of the apply that
/// first shows the line in the follower's store.
@Suite(.serialized, .timeLimit(.minutes(3)))
struct InstantWriterFollowerLatencyTests {
  /// The tablet's minute from 17:09:42 (Mac diagnostics collector): 29 list refreshes and 31 acknowledgements of its
  /// own writes, about 1.5 s an apply. Two minutes of it; the follower's 40 writes fit one delivery window.
  private static let applyMilliseconds = 1_500
  private static let lineEveryMilliseconds = 2_069
  private static let ownWriteAcknowledgedEveryMilliseconds = 1_935
  private static let replayMilliseconds = 120_000
  private static let ownWriteCount = 40

  /// Applying every frame in arrival order lets the wait grow with every minute replayed: by a model of this schedule,
  /// the worst line about 40 s late and the last lines about 30 s after two minutes. Applying only the newest list
  /// keeps it flat: about 13 s at worst, behind the follower's own acknowledgements, and about 1.5 s for the last
  /// lines.
  @Test
  func aWritersLinesReachASlowFollowerWithinSecondsAndTheLagStaysFlat() async throws {
    let writerTransport = TwoClientTransport()
    let writer = try await InstantRuntime.bootstrap(
      configuration: try twoClientConfiguration(appID: "two-client-writer", transport: writerTransport)
    )
    let followerTransport = TwoClientTransport()
    let gate = TwoClientApplyGate()
    var followerConfiguration = try twoClientConfiguration(appID: "two-client-follower", transport: followerTransport)
    followerConfiguration.onLiveReceiverEventAcquiredForTesting = { await gate.enter() }
    let follower = try await InstantRuntime.bootstrap(configuration: followerConfiguration)
    // Registered, so the cadence prune keeps the list's result, as the tablet's list screen kept it.
    let observation = await follower.observeQueryLease(TodoExample.query)

    try await withTwoClientCleanup({ await gate.open() }) {
      _ = try await writer.connect()
      _ = try await follower.connect()
      let writerSocket = try #require(await writerTransport.socket(0))
      let followerSocket = try #require(await followerTransport.socket(0))

      let ownWrites = (1...Self.ownWriteCount).map { "own-\($0)" }
      for (index, write) in ownWrites.enumerated() {
        try await follower.transact(
          TwoClientRow.ownWrite(write, index: index),
          createdAt: TwoClientRow.ownCreatedAt(index)
        )
      }
      // They go out in one window; any the pump has not sent when its acknowledgement is due waits one apply more.
      _ = try await twoClientWait("the follower's pump to send its writes", failsOnTimeout: false) {
        await followerSocket.sentTransactIDs.count == ownWrites.count
      }

      var schedule = TwoClientSchedule(
        lineEveryMilliseconds: Self.lineEveryMilliseconds,
        acknowledgementEveryMilliseconds: Self.ownWriteAcknowledgedEveryMilliseconds,
        durationMilliseconds: Self.replayMilliseconds,
        acknowledgementCount: ownWrites.count
      )
      var server = TwoClientServer()
      var clock = 0
      // The end of the follower's apply while its applier holds a frame; nil while it waits for one.
      var applyEnds: Int?
      var framesTaken = 0
      var writtenAt: [Int: Int] = [:]
      var shownAt: [Int: Int] = [:]

      while true {
        // Applying every frame in order ends about 27 s after the replay; an acknowledgement that never finds its
        // write on the socket would postpone itself forever.
        guard clock <= Self.replayMilliseconds + 120_000 else {
          Issue.record("#1796: the follower's pump sent \(server.acceptedOwnWrites.count) of its writes")
          break
        }
        if let next = schedule.next(atOrBefore: applyEnds) {
          clock = next.at
          var reachesFollower = true
          switch next.event {
          case let .line(line):
            let write = "line-\(line)"
            try await writer.transact(TwoClientRow.line(line), createdAt: TwoClientRow.lineCreatedAt(line))
            try await twoClientWait("the writer to send line \(line)") {
              await writerSocket.sentTransactIDs.contains(write)
            }
            let transaction = server.accept(write)
            await writerSocket.push(TwoClientFrame.transactOK(write, transaction: transaction))
            writtenAt[line] = clock
            server.lineCount = line
            await followerSocket.push(
              TwoClientFrame.list(
                transaction: transaction,
                lines: server.lineCount,
                acceptedOwnWrites: server.acceptedOwnWrites
              )
            )
          case .ownAcknowledgement:
            let write = ownWrites[server.acceptedOwnWrites.count]
            if await followerSocket.sentTransactIDs.contains(write) {
              let transaction = server.accept(write)
              server.acceptedOwnWrites.append(write)
              await followerSocket.push(TwoClientFrame.transactOK(write, transaction: transaction))
            } else {
              schedule.postpone(.ownAcknowledgement, to: clock + Self.applyMilliseconds)
              reachesFollower = false
            }
          }
          guard reachesFollower else { continue }
          try await twoClientWait("the follower's reader to buffer the frame") { await followerSocket.isCaughtUp }
          if applyEnds == nil {
            // An idle applier takes the frame at once.
            let taken = framesTaken
            try await twoClientWait("the follower's applier to take the frame") { await gate.enteredCount > taken }
            framesTaken += 1
            applyEnds = clock + Self.applyMilliseconds
          }
        } else if let end = applyEnds {
          clock = end
          let taken = framesTaken
          await gate.step()
          try await twoClientWait("the follower to finish its frame") {
            if await gate.enteredCount > taken { return true }
            return await follower.liveReceiverIsWaitingForAFrameForTesting()
          }
          for line in try await TwoClientRow.lines(in: follower) where shownAt[line] == nil {
            shownAt[line] = clock
          }
          if await gate.enteredCount > framesTaken {
            framesTaken += 1
            applyEnds = clock + Self.applyMilliseconds
          } else {
            applyEnds = nil
          }
        } else {
          break
        }
      }

      let lags = TwoClientLags(writtenAt: writtenAt, shownAt: shownAt)
      // The distribution is the release's evidence whether the bounds hold or not; a passing #expect prints nothing.
      print("#1796 two-client lags: \(lags)")
      #expect(lags.unshownLines.isEmpty, "#1796: lines the follower never showed: \(lags.unshownLines)")
      #expect(lags.worst <= 20_000, "#1796: a writer's line reached the follower late: \(lags)")
      #expect(lags.newest <= 8_000, "#1796: the follower's lag grew while the writer recorded: \(lags)")

      // The follower ends where applying every frame leads, and every write of both runtimes is accepted.
      await gate.open()
      await followerSocket.push(
        TwoClientFrame.list(
          transaction: server.transaction,
          lines: server.lineCount,
          acceptedOwnWrites: server.acceptedOwnWrites
        )
      )
      try await twoClientWait("the follower to apply every frame and its writes to be accepted") {
        let caughtUp = await followerSocket.isCaughtUp
        let idle = await follower.liveReceiverIsWaitingForAFrameForTesting()
        let pending = await follower.pendingMutations()
        return caughtUp && idle && pending.isEmpty
      }
      try await twoClientWait("the writer's lines to be accepted") { await writer.pendingMutations().isEmpty }
      let texts = try await TwoClientRow.texts(in: follower)
      expectNoDifference(
        texts.sorted(),
        ((1...server.lineCount).map { "line \($0)" } + ownWrites.map { "local \($0)" }).sorted()
      )
      expectNoDifference(server.acceptedOwnWrites, ownWrites)
      await observation.cancel()
      _ = try await follower.closeConnection()
      _ = try await writer.closeConnection()
    }
  }
}

// MARK: - The replay

private enum TwoClientEvent: Equatable {
  /// The writer writes its next line.
  case line(Int)
  /// The server accepts the follower's next own write.
  case ownAcknowledgement
}

/// What the server does when, in the test's milliseconds, earliest first; at one instant an acknowledgement goes
/// before a line.
private struct TwoClientSchedule {
  private var events: [(at: Int, event: TwoClientEvent)]

  init(
    lineEveryMilliseconds: Int,
    acknowledgementEveryMilliseconds: Int,
    durationMilliseconds: Int,
    acknowledgementCount: Int
  ) {
    var events: [(at: Int, event: TwoClientEvent)] = []
    var line = 1
    while lineEveryMilliseconds * line <= durationMilliseconds {
      events.append((lineEveryMilliseconds * line, .line(line)))
      line += 1
    }
    for index in 1...acknowledgementCount where acknowledgementEveryMilliseconds * index <= durationMilliseconds {
      events.append((acknowledgementEveryMilliseconds * index, .ownAcknowledgement))
    }
    self.events = []
    for event in events {
      insert(event)
    }
  }

  /// The next event, when it comes no later than `deadline` (any time when nil).
  mutating func next(atOrBefore deadline: Int?) -> (at: Int, event: TwoClientEvent)? {
    guard let first = events.first else { return nil }
    if let deadline, first.at > deadline { return nil }
    return events.removeFirst()
  }

  mutating func postpone(_ event: TwoClientEvent, to at: Int) {
    insert((at, event))
  }

  private mutating func insert(_ event: (at: Int, event: TwoClientEvent)) {
    let rank = { (kind: TwoClientEvent) in kind == .ownAcknowledgement ? 0 : 1 }
    let index =
      events.firstIndex { ($0.at, rank($0.event)) > (event.at, rank(event.event)) } ?? events.endIndex
    events.insert(event, at: index)
  }
}

/// The test's server: its transaction count and what it accepted.
private struct TwoClientServer {
  private(set) var transaction = 100
  var lineCount = 0
  var acceptedOwnWrites: [String] = []

  mutating func accept(_ write: String) -> Int {
    transaction += 1
    return transaction
  }
}

/// Each line's lag in the test's milliseconds: from the writer's write to the end of the apply that first showed it.
private struct TwoClientLags: CustomStringConvertible {
  var lags: [Int]
  var unshownLines: [Int]

  init(writtenAt: [Int: Int], shownAt: [Int: Int]) {
    let lines = writtenAt.keys.sorted()
    lags = lines.compactMap { line in shownAt[line].map { $0 - writtenAt[line, default: 0] } }
    unshownLines = lines.filter { shownAt[$0] == nil }
  }

  var worst: Int { lags.max() ?? .max }
  var newest: Int { lags.last ?? .max }

  var description: String {
    let sorted = lags.sorted()
    func percentile(_ fraction: Double) -> Int {
      sorted.isEmpty ? 0 : sorted[Int((Double(sorted.count - 1) * fraction).rounded())]
    }
    return "\(lags.count) lines: median \(percentile(0.5)) ms, p95 \(percentile(0.95)) ms, worst \(worst) ms, "
      + "newest \(newest) ms"
  }
}

// MARK: - Rows and frames

private enum TwoClientRow {
  static func lineCreatedAt(_ line: Int) -> InstantTimestamp {
    InstantTimestamp(milliseconds: 1_700_000_000_000 + Int64(line))
  }

  static func ownCreatedAt(_ index: Int) -> InstantTimestamp {
    InstantTimestamp(milliseconds: 1_700_000_100_000 + Int64(index))
  }

  /// The writer's line `line`: a todo the follower's list shows.
  static func line(_ line: Int) -> InstantStoreTransaction {
    let write = "line-\(line)"
    return InstantStoreTransaction(
      id: write,
      operations: TodoExample.createOperations(
        id: "todo-\(write)",
        text: "line \(line)",
        createdAt: lineCreatedAt(line),
        transactionID: write
      )
    )
  }

  /// One of the follower's own writes, as the tablet's backlog was.
  static func ownWrite(_ write: String, index: Int) -> InstantStoreTransaction {
    InstantStoreTransaction(
      id: write,
      operations: TodoExample.createOperations(
        id: "todo-\(write)",
        text: "local \(write)",
        createdAt: ownCreatedAt(index),
        transactionID: write
      )
    )
  }

  static func texts(in runtime: InstantRuntime) async throws -> [String] {
    try await runtime.queryLocally(TodoExample.query).values.compactMap { entity -> String? in
      guard case let .string(text)? = entity.values["text"]?.first else { return nil }
      return text
    }
  }

  /// The writer's lines the follower's store holds.
  static func lines(in runtime: InstantRuntime) async throws -> [Int] {
    try await texts(in: runtime).compactMap { text in
      text.hasPrefix("line ") ? Int(text.dropFirst("line ".count)) : nil
    }
  }
}

private enum TwoClientFrame {
  /// The follower's list (`TodoExample.query`) restated whole: the writer's first `lines` lines and the follower's own
  /// writes the server accepted.
  static func list(transaction: Int, lines: Int, acceptedOwnWrites: [String]) -> InstantLiveMessage {
    let query = (try? InstantLiveQueryEncoder.encode(TodoExample.query)) ?? .null
    var rows = (1...max(lines, 1)).prefix(lines).map { line in
      row(id: "todo-line-\(line)", text: "line \(line)", createdAt: TwoClientRow.lineCreatedAt(line).milliseconds)
    }
    rows += acceptedOwnWrites.enumerated().map { index, write in
      row(id: "todo-\(write)", text: "local \(write)", createdAt: TwoClientRow.ownCreatedAt(index).milliseconds)
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

  private static func row(id: String, text: String, createdAt: Int64) -> InstantLiveJSONValue {
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

// MARK: - Scripted sockets

/// One scripted Instant socket: pushed frames reach `receive()` in order, and every sent frame is recorded.
private actor TwoClientSocket {
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

  func push(_ frame: InstantLiveMessage) {
    guard !isClosed else { return }
    if let pending = takePendingReceive() {
      pending.continuation.resume(returning: frame)
    } else {
      frames.append(frame)
    }
  }

  private func send(_ message: InstantLiveMessage) throws {
    try abortState.check()
    sent.append(message)
  }

  private func receive() async throws -> InstantLiveMessage {
    try abortState.check()
    if !frames.isEmpty {
      return frames.removeFirst()
    }
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

/// Opens a fresh `TwoClientSocket`, with `init-ok` queued, for every connection attempt.
private actor TwoClientTransport {
  private var sockets: [TwoClientSocket] = []

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

  func socket(_ index: Int) -> TwoClientSocket? {
    sockets.indices.contains(index) ? sockets[index] : nil
  }

  private func openSocket() -> InstantLiveWebSocketSession {
    let socket = TwoClientSocket(frames: [
      liveReactorInitOK(attrs: liveReactorTodoServerAttrs, sessionID: "two-client-\(sockets.count + 1)")
    ])
    sockets.append(socket)
    return socket.session
  }
}

/// Holds each frame the follower's applier takes, through `onLiveReceiverEventAcquiredForTesting`, until `step()`:
/// the frame's apply ends when the test's clock says so. `open()` lets every frame through.
private actor TwoClientApplyGate {
  private var isOpen = false
  private var parked: CheckedContinuation<Void, Never>?
  private(set) var enteredCount = 0

  func enter() async {
    enteredCount += 1
    guard !isOpen else { return }
    await withCheckedContinuation { parked = $0 }
  }

  /// Ends the apply of the frame the applier holds.
  func step() {
    parked?.resume()
    parked = nil
  }

  func open() {
    isOpen = true
    step()
  }
}

private struct TwoClientWaitTimedOut: Error, CustomStringConvertible {
  var description: String
}

// MARK: - Helpers

/// A frozen clock keeps every delivery claim inside its acknowledgement deadline, so no deadline replaces a
/// connection behind the test's back; the replay's time is the test's own.
private func twoClientConfiguration(
  appID: String,
  transport: TwoClientTransport
) throws -> InstantRuntimeConfiguration {
  let directory = FileManager.default.temporaryDirectory
    .appendingPathComponent("InstantWriterFollowerLatencyTests-\(UUID().uuidString)")
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

/// Polls `condition` every 2 ms, up to the hang bound (#1021). Returns whether it held; a wait that
/// `failsOnTimeout` throws instead.
@discardableResult
private func twoClientWait(
  _ description: String,
  failsOnTimeout: Bool = true,
  _ condition: @Sendable () async throws -> Bool
) async throws -> Bool {
  let deadline = ContinuousClock.now + .milliseconds(Int(InstantTestWait.hangMilliseconds))
  while !(try await condition()) {
    guard ContinuousClock.now < deadline else {
      if failsOnTimeout { throw TwoClientWaitTimedOut(description: "Timed out waiting for \(description).") }
      return false
    }
    try await Task.sleep(nanoseconds: 2_000_000)
  }
  return true
}

/// Runs `cleanup` after `body`, including when `body` throws, so a failed wait never leaves a parked task behind.
private func withTwoClientCleanup(
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
