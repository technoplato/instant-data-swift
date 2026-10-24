import Foundation

@testable import InstantSwiftDataCore

// #1075 (2026-10-24): the memory audit's scripted server, for exercises that run long or meter a frame's decode.
//
// It stands in for #1072's `RealSizeServer` (whose generated store, account and query answers it reuses) where a
// memory measurement needs two things that server does not do:
//
// - It keeps no history. `RealSizeServer.sent` holds every frame the runtime sent; over a two-hour replay that is
//   thousands of frames, growth that would read as the library's. This server keeps counters and the open queries
//   only.
// - It hands the runtime text frames, which the runtime decodes with its production decoder
//   (`InstantLiveMessage.decoded(fromFrame:)`), as a WebSocket delivers them. `RealSizeServer` hands over decoded
//   messages, so a frame's parse never runs and never shows in a measurement. Outgoing frames are encoded with the
//   production encoder's `JSONEncoder` for the same reason.
//
// The server's own work stays out of the counts where it would be large: `init-ok`'s attributes and any prepared
// answer are encoded once, before a measurement, and spliced into the frame; `transact-ok` is written by hand. Frames
// a measurement pushes itself (`push(encoded:)`) are encoded before its counted pass.
//
// History:
// - 2026-10-24: #1075: the server, its connection and the apply waiter; answers from the account by default, one
//   `refresh-ok` can carry several queries' results, as the server's does for every query a transaction touched, a link
//   attribute goes out with its cardinality and reverse identity, and transaction ids are integers, as Instant's are.

actor MemoryReplayServer {
  /// The account's answer to an `add-query`: join rows (`RealSizeEntity.joinRow()`).
  typealias Answer = @Sendable (InstantLiveJSONValue) async -> [InstantLiveJSONValue]

  /// `init-ok`'s attributes, encoded once.
  private let attributesJSON: String
  private var connection: MemoryReplayConnection?
  private var answer: Answer
  /// Answers encoded beforehand, by the query's namespace: the `result` field's JSON.
  private var preparedResults: [String: String] = [:]
  private var addQueryCount = 0
  private var lastAddQuery: InstantLiveJSONValue = .null
  private var addQueryWaiters: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []
  /// What the server sent and received, as counts: never the frames themselves.
  private(set) var framesToClient = 0
  private(set) var bytesToClient = 0
  private(set) var largestFrameToClient = 0
  private(set) var framesFromClient = 0
  private(set) var bytesFromClient = 0
  private(set) var connections = 0

  init(attributes: [InstantAttribute], answer: @escaping Answer = { _ in [] }) {
    attributesJSON = Self.json(.array(Self.wireAttributes(attributes)))
    self.answer = answer
  }

  /// `init-ok`'s attributes as the server sends them: #1072's encoding, plus the cardinality and reverse identity of
  /// a link (the memory exercises add one, a recording's lines).
  static func wireAttributes(_ attributes: [InstantAttribute]) -> [InstantLiveJSONValue] {
    zip(attributes, RealSizeWire.attributes(attributes)).map { attribute, wire in
      guard attribute.valueType == .ref, case .object(var object) = wire else { return wire }
      object["cardinality"] = .string(attribute.cardinality == .many ? "many" : "one")
      if let reverse = attribute.reverseIdentity, let slash = reverse.firstIndex(of: "/") {
        object["reverse-identity"] = .array([
          .string("reverse-\(attribute.id)"), .string(String(reverse[..<slash])),
          .string(String(reverse[reverse.index(after: slash)...])),
        ])
      }
      return .object(object)
    }
  }

  nonisolated var transport: InstantLiveTransportClient {
    .immediate { _ in
      let connection = MemoryReplayConnection()
      return InstantLiveWebSocketSession(
        send: { message in
          // The production transport encodes every frame it sends (`encodedFrame`); so does this one.
          let bytes = (try? JSONEncoder().encode(message).count) ?? 0
          await self.received(message, bytes: bytes, from: connection)
        },
        receive: { try InstantLiveMessage.decoded(fromFrame: try await connection.next()) },
        close: { connection.abort() },
        abort: { connection.abort() }
      )
    }
  }

  func setAnswer(_ answer: @escaping Answer) { self.answer = answer }

  /// Answers every `add-query` of `namespace` with `rows`, encoded now, so the measurement that opens the query
  /// counts only the runtime's decode and apply of the answer.
  func prepareAnswer(namespace: String, rows: [InstantLiveJSONValue]) {
    preparedResults[namespace] = Self.json(.array(RealSizeWire.result(rows)))
  }

  func forgetPreparedAnswer(namespace: String) { preparedResults[namespace] = nil }

  var addQueries: Int { addQueryCount }

  /// Waits until the runtime has sent more than `count` `add-query` frames, and returns the newest one's query.
  func nextAddQuery(after count: Int) async -> InstantLiveJSONValue {
    if addQueryCount <= count {
      await withCheckedContinuation { continuation in
        addQueryWaiters.append((count + 1, continuation))
      }
    }
    return lastAddQuery
  }

  /// Sends the server's `refresh-ok` of `query` with `rows`, as the server does for every open query a transaction
  /// touched, and returns its processed transaction id.
  @discardableResult
  func refresh(_ query: InstantLiveJSONValue, rows: [InstantLiveJSONValue]) -> String {
    refresh([(query, rows)])
  }

  /// One `refresh-ok` carrying each query's whole result: what the server sends after a transaction that touched
  /// several open queries.
  @discardableResult
  func refresh(_ results: [(query: InstantLiveJSONValue, rows: [InstantLiveJSONValue])]) -> String {
    let tx = nextTransactionID()
    push(Self.refreshFrame(results, tx: tx))
    return tx
  }

  /// Sends a frame encoded beforehand, so a measurement counts only the runtime's decode and apply.
  func push(encoded frame: String) {
    framesToClient += 1
    bytesToClient += frame.utf8.count
    largestFrameToClient = max(largestFrameToClient, frame.utf8.count)
    connection?.push(frame)
  }

  func push(_ message: InstantLiveMessage) {
    push(encoded: Self.encoded(message))
  }

  /// The next processed transaction id, for a frame a measurement encodes itself.
  func nextTransactionID() -> String { String(MemoryTransactionIDs.shared.make()) }

  /// A transaction id as the server sends it: a JSON number (an id that is not one stays a string).
  static func txValue(_ tx: String) -> InstantLiveJSONValue {
    Int64(tx).map { .number(Double($0)) } ?? .string(tx)
  }

  static func encoded(_ message: InstantLiveMessage) -> String {
    String(decoding: (try? JSONEncoder().encode(message)) ?? Data(), as: UTF8.self)
  }

  static func json(_ value: InstantLiveJSONValue) -> String {
    String(decoding: (try? JSONEncoder().encode(value)) ?? Data(), as: UTF8.self)
  }

  /// A JSON string literal of an id this server or the runtime made (hex, digits, dashes): no escaping needed.
  private static func quoted(_ id: String) -> String { "\"" + id + "\"" }

  static func refreshFrame(_ query: InstantLiveJSONValue, rows: [InstantLiveJSONValue], tx: String) -> InstantLiveMessage {
    refreshFrame([(query, rows)], tx: tx)
  }

  static func refreshFrame(
    _ results: [(query: InstantLiveJSONValue, rows: [InstantLiveJSONValue])], tx: String
  ) -> InstantLiveMessage {
    InstantLiveMessage(
      op: "refresh-ok",
      clientEventID: nil,
      fields: [
        "attrs": .array([]),
        "computations": .array(
          results.map { result in
            .object([
              "instaql-query": result.query, "instaql-result": .array(RealSizeWire.result(result.rows)),
              "processed-tx-id": txValue(tx),
            ])
          }
        ),
        "processed-tx-id": txValue(tx),
      ]
    )
  }

  static func addQueryOKFrame(_ query: InstantLiveJSONValue, rows: [InstantLiveJSONValue], tx: String) -> InstantLiveMessage {
    InstantLiveMessage(
      op: "add-query-ok",
      clientEventID: nil,
      fields: ["q": query, "processed-tx-id": txValue(tx), "result": .array(RealSizeWire.result(rows))]
    )
  }

  // MARK: - The wire

  private func received(_ message: InstantLiveMessage, bytes: Int, from connection: MemoryReplayConnection) async {
    if self.connection !== connection { connections += 1 }
    self.connection = connection
    framesFromClient += 1
    bytesFromClient += bytes
    switch message.op {
    case "init":
      let id = message.clientEventID.map { "\"client-event-id\":" + Self.quoted($0) + "," } ?? ""
      push(
        encoded: "{\"op\":\"init-ok\"," + id + "\"attrs\":" + attributesJSON
          + ",\"auth\":null,\"session-id\":\"memory-replay-session\"}"
      )
    case "add-query":
      let query = message.fields["q"] ?? .null
      addQueryCount += 1
      lastAddQuery = query
      if case .object(let root) = query, let namespace = root.keys.first, let result = preparedResults[namespace] {
        push(
          encoded: "{\"op\":\"add-query-ok\",\"processed-tx-id\":" + nextTransactionID()
            + ",\"q\":" + Self.json(query) + ",\"result\":" + result + "}"
        )
      } else {
        let rows = await answer(query)
        push(Self.addQueryOKFrame(query, rows: rows, tx: nextTransactionID()))
      }
      let ready = addQueryWaiters.filter { $0.count <= addQueryCount }
      addQueryWaiters.removeAll { $0.count <= addQueryCount }
      for waiter in ready { waiter.continuation.resume() }
    case "transact":
      guard let id = message.clientEventID else { return }
      push(
        encoded: "{\"op\":\"transact-ok\",\"client-event-id\":" + Self.quoted(id) + ",\"tx-id\":"
          + nextTransactionID() + "}"
      )
    default:
      break
    }
  }
}

/// Transaction ids as Instant's server makes them: integers that only grow, here across the process.
///
/// The library takes a write as covered by a refresh when the refresh's processed id is at or past the write's, compared
/// as integers (`serverApplyWatermarkPredicate`); a string id covers only itself. With string ids (this server's first
/// version, and #1072's `RealSizeServer` before its fixture version 3), no acknowledged write is ever covered: each
/// stays an optimistic overlay, and every server apply peels and replays all of them, a cost that grows with every write
/// and is the harness's, not the library's. The phone's store holds 3 confirmed writes, all with integer ids; a version-2
/// generated store holds 783 that can never be covered, which `MemoryExerciseSession.open` lets the library prune first.
final class MemoryTransactionIDs: @unchecked Sendable {
  static let shared = MemoryTransactionIDs()
  // SAFETY: `lock` guards `last`.
  private let lock = NSLock()
  /// Microseconds since 1970 at first use, as #1072's server seeds its own (version 3): past every id a store generated
  /// earlier holds, and past the phone's (about 2.89 billion), so a copy of either is covered too.
  private var last = Int64(Date().timeIntervalSince1970 * 1_000_000)

  func make() -> Int64 {
    lock.withLock {
      last += 1
      return last
    }
  }
}

/// One scripted socket of text frames: the frames the server sent that the runtime has not received, the waiting
/// `receive`, and whether it was closed. Its abort is synchronous, as the transport contract requires.
final class MemoryReplayConnection: @unchecked Sendable {
  // SAFETY: `lock` guards every stored property; continuations are resumed outside it.
  private let lock = NSLock()
  private var inbox: [String] = []
  private var inboxStart = 0
  private var continuation: CheckedContinuation<String, any Error>?
  private var aborted = false

  func push(_ frame: String) {
    let waiting: CheckedContinuation<String, any Error>? = lock.withLock {
      guard !aborted else { return nil }
      guard let continuation else {
        inbox.append(frame)
        return nil
      }
      self.continuation = nil
      return continuation
    }
    waiting?.resume(returning: frame)
  }

  func next() async throws -> String {
    try await withCheckedThrowingContinuation { continuation in
      enum Next { case frame(String), closed, wait }
      let next: Next = lock.withLock {
        if aborted { return .closed }
        if inboxStart < inbox.count {
          let frame = inbox[inboxStart]
          inboxStart += 1
          if inboxStart == inbox.count {
            inbox.removeAll(keepingCapacity: true)
            inboxStart = 0
          }
          return .frame(frame)
        }
        self.continuation = continuation
        return .wait
      }
      switch next {
      case .frame(let frame): continuation.resume(returning: frame)
      case .closed: continuation.resume(throwing: CancellationError())
      case .wait: break
      }
    }
  }

  func abort() {
    let waiting: CheckedContinuation<String, any Error>? = lock.withLock {
      aborted = true
      inbox = []
      inboxStart = 0
      defer { continuation = nil }
      return continuation
    }
    waiting?.resume(throwing: CancellationError())
  }
}

/// Waits for the runtime's server applies by processed transaction id, from the runtime's own
/// `server-apply.operation-gate-held` event. Unlike `RealSizeApplyLog`, it forgets an apply once it was waited for,
/// and keeps at most a few hundred it was never asked about, so it does not grow over a long run.
///
/// The event is debug-level when the apply held the gate under 250 ms, so the waiter needs the diagnostics floor at
/// `.debug` (the default): every exercise that waits on applies runs with one handler at that floor, which E09 prices.
final class MemoryApplyWaiter: @unchecked Sendable {
  // SAFETY: `lock` guards `finished` and `token`.
  private let lock = NSLock()
  private var finished: Set<String> = []
  private var token: UUID?
  private static let unclaimedLimit = 512

  init() {
    let token = InstantDiagnostics.shared.addHandler { [weak self] entry in
      guard let self, entry.event == "server-apply.operation-gate-held", let id = entry.correlationID else { return }
      self.lock.withLock {
        if self.finished.count >= Self.unclaimedLimit { self.finished.removeAll(keepingCapacity: true) }
        self.finished.insert(id)
      }
    }
    lock.withLock { self.token = token }
  }

  func stop() {
    if let token = lock.withLock({ self.token }) { InstantDiagnostics.shared.removeHandler(token) }
    lock.withLock { token = nil }
  }

  /// Returns once the apply of `transactionID` finished (and forgets it), or throws after `timeout`.
  func wait(for transactionID: String, timeout: Duration = .seconds(120)) async throws {
    let deadline = ContinuousClock.now + timeout
    while true {
      if lock.withLock({ finished.remove(transactionID) }) != nil { return }
      guard ContinuousClock.now < deadline else {
        throw InstantError(
          code: .implementationFailed, operation: "wait for a memory-replay server apply",
          message: "No server apply finished for \(transactionID) within \(timeout).",
          recovery: "Check that the frame names a query the runtime holds."
        )
      }
      try await Task.sleep(for: .microseconds(200))
    }
  }
}
