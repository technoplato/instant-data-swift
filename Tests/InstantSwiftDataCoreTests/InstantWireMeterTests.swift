// History:
// - 2026-10-24: added (#1124): the live socket counts its frames and bytes by op, each way, and the device log reports
//   them once a minute, so a phone's bytes per change can be measured.
// - 2026-10-26 (#1117): a refresh's bytes are counted by the query each computation answers. On one device a recording
//   received about 1.15 MB per final line, and only two copies of its store said which live queries carried it.
// - 2026-11-05 (#1781): a query's first answer is timed from its own ask, by client-event-id, with the triples it
//   carried, under its shape.

import CustomDump
import Foundation
import Network
import Testing

@testable import InstantSwiftDataCore

@Suite
struct InstantWireMeterTests {
  /// One frame sent and one received through the URLSession socket, against a WebSocket server on the loopback
  /// interface: each counted under its op and direction with its text's size, as the library encoded and decoded it.
  @Test
  func theSocketCountsEachFrameByOpAndDirection() async throws {
    let reply = #"{"op":"refresh-ok","processed-tx-id":7}"#
    let server = try await LoopbackWebSocketServer.start(reply: reply)
    defer { server.stop() }
    let meter = InstantWireMeterStorage()
    let socket = try InstantURLSessionLiveWebSocket(url: server.url, wireMeter: meter)
    let message = InstantLiveMessage(op: "transact", clientEventID: "event-1", fields: ["tx-steps": .array([])])

    try await socket.send(message)
    let received = try await socket.receive()
    await socket.close()

    expectNoDifference(received.op, "refresh-ok")
    expectNoDifference(
      meter.snapshot(),
      InstantWireSnapshot(
        sent: ["transact": InstantWireSnapshot.Measure(frames: 1, bytes: try JSONEncoder().encode(message).count)],
        received: ["refresh-ok": InstantWireSnapshot.Measure(frames: 1, bytes: reply.utf8.count)]
      )
    )
  }

  /// The meter hands back a summary once a minute of traffic has passed: what that minute added, by op and direction,
  /// which the socket logs as `network.wire-summary`.
  @Test
  func aSummaryCoversWhatTheMinuteAdded() {
    let meter = InstantWireMeterStorage(now: 0)
    let minute = InstantWireMeterStorage.summaryIntervalNanoseconds

    let early = [
      meter.record(.sent, op: "transact", bytes: 1_150, now: 1),
      meter.record(.received, op: "transact-ok", bytes: 210, now: 2),
    ]
    let first = meter.record(.received, op: "refresh-ok", bytes: 129_100, now: minute)
    let quiet = meter.record(.sent, op: "transact", bytes: 1_200, now: minute + 1)
    let second = meter.record(.received, op: "refresh-ok", bytes: 128_000, now: 2 * minute)

    expectNoDifference(early, [nil, nil])
    expectNoDifference(
      first,
      InstantWireSnapshot(
        sent: ["transact": InstantWireSnapshot.Measure(frames: 1, bytes: 1_150)],
        received: [
          "transact-ok": InstantWireSnapshot.Measure(frames: 1, bytes: 210),
          "refresh-ok": InstantWireSnapshot.Measure(frames: 1, bytes: 129_100),
        ]
      )
    )
    expectNoDifference(quiet, nil)
    expectNoDifference(
      second?.logMetadata,
      [
        "sentFrames": "1", "sentBytes": "1200", "receivedFrames": "1", "receivedBytes": "128000",
        "sent.transact": "1/1200", "received.refresh-ok": "1/128000",
      ]
    )
    expectNoDifference(meter.snapshot().receivedBytes, 210 + 129_100 + 128_000)
  }
}

extension InstantWireMeterTests {
  /// A refresh's computations are counted apart, each with its own text's bytes, under its query's shape.
  @Test
  func aRefreshCountsEachComputationUnderItsQueryShape() throws {
    let window = #"{"instaql-query":{"lines":{"$":{"limit":16,"order":{"updatedAtMs":"desc"},"where":{"recordingID":"r-1"}}}},"instaql-result":[{"data":{"datalog-result":{"join-rows":[[["e-1","a-1","one line",7]]]}}}]}"#
    let list = #"{"instaql-query":{"recordings":{"$":{"where":{"and":[{"id":{"$in":["r-1","r-2"]}},{"deletedAtMs":{"$isNull":true}}]}},"previewSegmentA":{}}},"instaql-result":[]}"#
    let frame = #"{"op":"refresh-ok","processed-tx-id":7,"computations":["# + window + "," + list + #"]}"#
    let meter = InstantWireMeterStorage()

    let message = try InstantLiveMessage.decoded(fromFrame: Data(frame.utf8), meter: meter)

    expectNoDifference(message.op, "refresh-ok")
    expectNoDifference(
      meter.snapshot().receivedByQuery,
      [
        "lines/16[recordingID]": InstantWireSnapshot.Measure(frames: 1, bytes: window.utf8.count),
        "recordings[deletedAtMs,id]": InstantWireSnapshot.Measure(frames: 1, bytes: list.utf8.count),
      ]
    )
  }

  /// A query's first answer counts its whole frame under its shape.
  @Test
  func aQuerysFirstAnswerCountsItsFrameUnderItsShape() throws {
    let frame = #"{"op":"add-query-ok","q":{"liveLines":{"$":{"limit":8,"where":{"recordingID":"r-1"}}}},"result":[]}"#
    let meter = InstantWireMeterStorage()

    _ = try InstantLiveMessage.decoded(fromFrame: frame, meter: meter)

    expectNoDifference(
      meter.snapshot().receivedByQuery,
      ["liveLines/8[recordingID]": InstantWireSnapshot.Measure(frames: 1, bytes: frame.utf8.count)]
    )
  }

  /// A shape names a query's namespaces, its page size and the attributes its where tests, never a value it compares.
  @Test
  func aQueryShapeNamesItsPageAndAttributesButNoValues() {
    func shape(_ json: String) -> String {
      InstantWireMeter.queryShape(of: try! JSONDecoder().decode(InstantLiveJSONValue.self, from: Data(json.utf8)))
    }
    expectNoDifference(
      shape(#"{"transcriptionSegments":{"$":{"limit":64,"order":{"segmentIndex":"desc"},"where":{"recordingID":"e0f8636a"}}}}"#),
      "transcriptionSegments/64[recordingID]"
    )
    expectNoDifference(
      shape(#"{"recordings":{"$":{"first":12,"where":{"or":[{"ownerUserID":"u-1"},{"title":{"$ilike":"%x%"}}]}}}}"#),
      "recordings/12[ownerUserID,title]"
    )
    expectNoDifference(shape(#"{"b":{},"a":{"$":{"last":3}}}"#), "a/3+b")
    expectNoDifference(shape(#"[1]"#), "unknown")
  }

  /// The meter keeps a bounded number of shapes: past the limit, more count as `other`.
  @Test
  func theMeterKeepsABoundedNumberOfShapes() {
    let meter = InstantWireMeterStorage()
    for index in 0..<(InstantWireMeterStorage.maximumQueryShapes + 2) {
      meter.recordQueries([(shape: "q\(index)", bytes: 10)])
    }

    let byQuery = meter.snapshot().receivedByQuery
    expectNoDifference(byQuery.count, InstantWireMeterStorage.maximumQueryShapes + 1)
    expectNoDifference(byQuery["other"], InstantWireSnapshot.Measure(frames: 2, bytes: 20))
  }

  /// The minute's summary names its three heaviest query shapes, and what a minute added subtracts like the ops.
  @Test
  func aSummaryNamesTheHeaviestQueries() {
    let earlier = InstantWireSnapshot(receivedByQuery: ["a": .init(frames: 1, bytes: 100)])
    let later = InstantWireSnapshot(
      received: ["refresh-ok": .init(frames: 4, bytes: 1_600)],
      receivedByQuery: [
        "a": .init(frames: 2, bytes: 300),
        "b": .init(frames: 1, bytes: 900),
        "c": .init(frames: 1, bytes: 50),
        "d": .init(frames: 1, bytes: 400),
      ]
    )

    let minute = later.subtracting(earlier)

    expectNoDifference(minute.receivedByQuery["a"], .init(frames: 1, bytes: 200))
    expectNoDifference(
      minute.logMetadata.filter { $0.key.hasPrefix("query.") },
      ["query.1": "b=1/900", "query.2": "d=1/400", "query.3": "a=1/200"]
    )
  }
}

extension InstantWireMeterTests {
  /// A query's first answer through the loopback socket: the add-query-ok that echoes the ask's client-event-id closes
  /// its note, and the wait and the answer's triples, children included, count under the query's shape (#1781).
  @Test
  func aQuerysFirstAnswerIsTimedUnderItsShapeWithItsTriples() async throws {
    let reply = #"{"op":"add-query-ok","client-event-id":"ask-1","q":{"liveLines":{"$":{"limit":8,"where":{"recordingID":"r-1"}}}},"result":[{"data":{"datalog-result":{"join-rows":[[["e-1","a-1","one",7]],[["e-1","a-2","two",7],["e-2","a-1","three",7]]]}},"child-nodes":[{"data":{"datalog-result":{"join-rows":[[["e-3","a-1","four",7]]]}}}]}]}"#
    let server = try await LoopbackWebSocketServer.start(reply: reply)
    defer { server.stop() }
    let meter = InstantWireMeterStorage()
    let socket = try InstantURLSessionLiveWebSocket(url: server.url, wireMeter: meter)

    try await socket.send(Self.ask("ask-1", #"{"liveLines":{"$":{"limit":8,"where":{"recordingID":"r-1"}}}}"#))
    _ = try await socket.receive()
    await socket.close()

    let firstAnswers = meter.snapshot().firstAnswersByQuery
    expectNoDifference(Array(firstAnswers.keys), ["liveLines/8[recordingID]"])
    let answers = try #require(firstAnswers["liveLines/8[recordingID]"])
    expectNoDifference(answers.answers, 1)
    expectNoDifference(answers.triples, 4)
    expectNoDifference(answers.slowAnswers, 0)
    #expect(answers.waitNanoseconds > 0)
  }

  /// Each answer closes its own ask's note by client-event-id, in whatever order answers arrive; the wait is the
  /// uptime between the two, and five seconds or more counts as slow (#1781).
  @Test
  func eachAnswerClosesItsOwnAsksNote() {
    var notes = InstantFirstAnswerNotes()
    let meter = InstantWireMeterStorage()
    let list = #"{"recordings":{"$":{"where":{"ownerUserID":"u-1"}}}}"#

    let noted = [
      notes.asked(Self.ask("a-1", list), at: 1_000),
      notes.asked(Self.ask("a-2", list), at: 2_000),
      notes.asked(InstantLiveMessage(op: "transact", clientEventID: "t-1"), at: 3_000),
    ]
    let second = notes.answered(InstantLiveMessage(op: "add-query-exists", clientEventID: "a-2"), at: 5_000_002_000)
    let first = notes.answered(Self.answer("a-1", triples: 2), at: 41_001_000)
    let unknown = notes.answered(Self.answer("a-9", triples: 1), at: 42_000_000)
    for answer in [first, second].compactMap({ $0 }) { meter.recordFirstAnswer(answer) }

    expectNoDifference(noted, [true, true, false])
    expectNoDifference(
      [first, second],
      [
        InstantFirstAnswer(shape: "recordings[ownerUserID]", waitNanoseconds: 41_000_000, triples: 2),
        InstantFirstAnswer(shape: "recordings[ownerUserID]", waitNanoseconds: 5_000_000_000, triples: 0),
      ]
    )
    expectNoDifference(unknown, nil)
    expectNoDifference(notes.count, 0)
    expectNoDifference(
      meter.snapshot().firstAnswersByQuery,
      [
        "recordings[ownerUserID]": InstantWireSnapshot.FirstAnswers(
          answers: 2, waitNanoseconds: 5_041_000_000, slowAnswers: 1, triples: 2)
      ]
    )
  }

  /// An error for a noted ask closes its note with no answer, a frame that was never sent is forgotten, and the notes
  /// stay bounded when no answer comes (#1781).
  @Test
  func notesCloseOnAnErrorOrAFailedSendAndStayBounded() {
    var notes = InstantFirstAnswerNotes()
    let ask = Self.ask("a-1", #"{"lines":{}}"#)

    let notedBeforeTheError = notes.asked(ask, at: 1)
    let error = InstantLiveMessage(op: "error", clientEventID: "a-1", fields: ["status": .number(400)])
    let answerToTheError = notes.answered(error, at: 2)
    let afterTheError = notes.count
    let notedBeforeTheFailedSend = notes.asked(ask, at: 3)
    notes.forget(ask)
    let afterTheFailedSend = notes.count
    for index in 0..<(InstantFirstAnswerNotes.maximumNotes + 10) {
      notes.asked(Self.ask("b-\(index)", #"{"lines":{}}"#), at: UInt64(index))
    }
    let notedPastTheBound = notes.asked(Self.ask("c-1", #"{"lines":{}}"#), at: 1_000)

    expectNoDifference([notedBeforeTheError, notedBeforeTheFailedSend], [true, true])
    expectNoDifference(answerToTheError, nil)
    expectNoDifference([afterTheError, afterTheFailedSend], [0, 0])
    expectNoDifference(notes.count, InstantFirstAnswerNotes.maximumNotes)
    expectNoDifference(notedPastTheBound, false)
  }

  /// A minute's first answers subtract like the other counts, and its summary names the three longest waits in all,
  /// `shape=answers/averageMs/slow/triples` (#1781).
  @Test
  func aSummaryNamesTheLongestFirstAnswerWaits() {
    let earlier = InstantWireSnapshot(
      firstAnswersByQuery: ["a": .init(answers: 1, waitNanoseconds: 100_000_000, slowAnswers: 0, triples: 10)]
    )
    let later = InstantWireSnapshot(
      firstAnswersByQuery: [
        "a": .init(answers: 3, waitNanoseconds: 700_000_000, slowAnswers: 0, triples: 30),
        "b": .init(answers: 1, waitNanoseconds: 6_000_000_000, slowAnswers: 1, triples: 900),
        "c": .init(answers: 1, waitNanoseconds: 20_000_000, slowAnswers: 0, triples: 0),
        "d": .init(answers: 2, waitNanoseconds: 400_000_000, slowAnswers: 0, triples: 4),
      ]
    )

    let minute = later.subtracting(earlier)

    expectNoDifference(
      minute.firstAnswersByQuery["a"],
      .init(answers: 2, waitNanoseconds: 600_000_000, slowAnswers: 0, triples: 20)
    )
    expectNoDifference(
      minute.logMetadata.filter { $0.key.hasPrefix("firstAnswer.") },
      ["firstAnswer.1": "b=1/6000/1/900", "firstAnswer.2": "a=2/300/0/20", "firstAnswer.3": "d=2/200/0/4"]
    )
  }

  /// Past the bound on shapes, a first answer counts as `other`, as the bytes do (#1781).
  @Test
  func firstAnswersKeepABoundedNumberOfShapes() {
    let meter = InstantWireMeterStorage()
    for index in 0..<(InstantWireMeterStorage.maximumQueryShapes + 2) {
      meter.recordFirstAnswer(InstantFirstAnswer(shape: "q\(index)", waitNanoseconds: 10, triples: 1))
    }

    let byQuery = meter.snapshot().firstAnswersByQuery
    expectNoDifference(byQuery.count, InstantWireMeterStorage.maximumQueryShapes + 1)
    expectNoDifference(byQuery["other"], .init(answers: 2, waitNanoseconds: 20, slowAnswers: 0, triples: 2))
  }

  private static func ask(_ clientEventID: String, _ query: String) -> InstantLiveMessage {
    InstantLiveMessage(
      op: "add-query",
      clientEventID: clientEventID,
      fields: ["q": try! JSONDecoder().decode(InstantLiveJSONValue.self, from: Data(query.utf8))]
    )
  }

  private static func answer(_ clientEventID: String, triples: Int) -> InstantLiveMessage {
    let triple = InstantLiveJSONValue.array([.string("e"), .string("a"), .string("v"), .number(7)])
    let joinRows = InstantLiveJSONValue.array(Array(repeating: .array([triple]), count: triples))
    let node = InstantLiveJSONValue.object(["data": .object(["datalog-result": .object(["join-rows": joinRows])])])
    return InstantLiveMessage(op: "add-query-ok", clientEventID: clientEventID, fields: ["result": .array([node])])
  }
}

/// A WebSocket server on the loopback interface that answers each message it receives with one text frame.
private final class LoopbackWebSocketServer: @unchecked Sendable {
  // SAFETY: `connections` is touched only on `queue`; `port` is set once, before `start` returns the server.
  private let listener: NWListener
  private let reply: String
  private let queue = DispatchQueue(label: "instant-wire-meter-tests.server")
  private var connections: [NWConnection] = []
  private var port: UInt16 = 0

  var url: URL { URL(string: "ws://127.0.0.1:\(port)/runtime/session")! }

  private init(listener: NWListener, reply: String) {
    self.listener = listener
    self.reply = reply
  }

  static func start(reply: String) async throws -> LoopbackWebSocketServer {
    let parameters = NWParameters.tcp
    parameters.acceptLocalOnly = true
    parameters.requiredInterfaceType = .loopback
    let webSocket = NWProtocolWebSocket.Options()
    webSocket.autoReplyPing = true
    parameters.defaultProtocolStack.applicationProtocols.insert(webSocket, at: 0)
    let listener = try NWListener(using: parameters)
    let server = LoopbackWebSocketServer(listener: listener, reply: reply)
    listener.newConnectionHandler = { [server] connection in server.accept(connection) }
    server.port = try await withCheckedThrowingContinuation { continuation in
      let once = ResumeOnce()
      listener.stateUpdateHandler = { state in
        switch state {
        case .ready:
          if once.claim() { continuation.resume(returning: listener.port?.rawValue ?? 0) }
        case .failed(let error):
          if once.claim() { continuation.resume(throwing: error) }
        default:
          break
        }
      }
      listener.start(queue: server.queue)
    }
    return server
  }

  private func accept(_ connection: NWConnection) {
    connections.append(connection)
    connection.start(queue: queue)
    answer(connection)
  }

  private func answer(_ connection: NWConnection) {
    connection.receiveMessage { [weak self] data, _, _, error in
      guard let self, error == nil, data != nil else { return }
      let metadata = NWProtocolWebSocket.Metadata(opcode: .text)
      let context = NWConnection.ContentContext(identifier: "reply", metadata: [metadata])
      connection.send(
        content: Data(self.reply.utf8),
        contentContext: context,
        isComplete: true,
        completion: .contentProcessed { _ in }
      )
      self.answer(connection)
    }
  }

  func stop() {
    queue.async {
      for connection in self.connections { connection.cancel() }
      self.connections = []
    }
    listener.cancel()
  }
}

/// Lets a callback that may run more than once resume its continuation once.
private final class ResumeOnce: @unchecked Sendable {
  // SAFETY: `lock` guards `claimed`.
  private let lock = NSLock()
  private var claimed = false

  func claim() -> Bool {
    lock.withLock {
      defer { claimed = true }
      return !claimed
    }
  }
}
