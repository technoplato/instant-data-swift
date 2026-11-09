#!/usr/bin/env python3
"""#1796 step 3: the receive summary measures how old the newest server write is when it is applied.

  python3 .runs-1796/next/apply3.py red   [root]  # tests + scaffold (the lag is never recorded)
  python3 .runs-1796/next/apply3.py green [root]  # record it, and log it

Why: the tablet behind #1796 showed a live recording about six minutes late and nothing measured it; the brief asks
for the follower's latency distribution (p50, p95, max) after the release.
"""
import pathlib, sys

step = sys.argv[1]
root = pathlib.Path(sys.argv[2]) if len(sys.argv) > 2 else pathlib.Path(__file__).resolve().parents[2]

def edit(rel, old, new):
    p = root / rel
    s = p.read_text()
    assert s.count(old) == 1, (rel, s.count(old), old[:100])
    p.write_text(s.replace(old, new))
    print(f"{rel}: applied")

SRC = "Sources/InstantSwiftDataCore/InstantRuntimeLiveSession.swift"
TEST = "Tests/InstantSwiftDataCoreTests/InstantFollowerLatencyTests.swift"

if step == "red":
    # Scaffold: the clock, the storage, the summary fields, an accessor. Nothing records a lag yet.
    edit(SRC, '''  /// When the applier took its last frame; the next `next()` call ends that frame's apply.
  private var lastTakenAt: ContinuousClock.Instant?

  init(capacity: Int) {
    precondition(capacity > 0, "A live receive buffer needs room for at least one frame.")
    self.capacity = capacity
    meter = InstantLiveReceiveMeter(windowStart: ContinuousClock.now)
  }
''', '''  /// When the applier took its last frame; the next `next()` call ends that frame's apply.
  private var lastTakenAt: ContinuousClock.Instant?
  /// This device's wall clock in milliseconds since 1970, the scale of the server's fact times (#1796).
  private let wallClockMilliseconds: @Sendable () -> Int64

  init(
    capacity: Int,
    wallClockMilliseconds: @escaping @Sendable () -> Int64 = { InstantLiveReceivedFrames.systemMilliseconds() }
  ) {
    precondition(capacity > 0, "A live receive buffer needs room for at least one frame.")
    self.capacity = capacity
    self.wallClockMilliseconds = wallClockMilliseconds
    meter = InstantLiveReceiveMeter(windowStart: ContinuousClock.now)
  }

  static func systemMilliseconds() -> Int64 {
    Int64((Date().timeIntervalSince1970 * 1_000).rounded())
  }
''')
    edit(SRC, '''  var applierIsWaitingForTesting: Bool {
    lock.withLock { waitingApplier != nil }
  }
''', '''  var applierIsWaitingForTesting: Bool {
    lock.withLock { waitingApplier != nil }
  }

  /// The lags this minute's meter recorded, in order (#1796).
  var factLagsForTesting: [Int] {
    lock.withLock { meter.factLagsMillisecondsForTesting }
  }
''')
    edit(SRC, '''  private var replacedFrames = 0
  private var replacedResults = 0

  init(windowStart: ContinuousClock.Instant) {''', '''  private var replacedFrames = 0
  private var replacedResults = 0
  /// How old the newest server write was when its frame finished applying, for each frame that carried one newer than
  /// any applied before (#1796); kept like the waits.
  private var factLagsMilliseconds: [Int] = []
  private var longestFactLag = 0
  private var factLagFrames = 0

  init(windowStart: ContinuousClock.Instant) {''')
    edit(SRC, '''  mutating func recordReplacedFrame() {
    replacedFrames += 1
  }
''', '''  mutating func recordReplacedFrame() {
    replacedFrames += 1
  }

  mutating func recordFactLag(milliseconds: Int) {}

  var factLagsMillisecondsForTesting: [Int] { factLagsMilliseconds }
''')
    edit(SRC, '''    let sorted = waitsMilliseconds.sorted()
''', '''    let sorted = waitsMilliseconds.sorted()
    let lags = factLagsMilliseconds.sorted()
''')
    edit(SRC, '''      replacedFrames: replacedFrames,
      replacedResults: replacedResults
    )''', '''      replacedFrames: replacedFrames,
      replacedResults: replacedResults,
      factLagFrames: factLagFrames,
      factLagMedianMilliseconds: lags.isEmpty ? 0 : lags[lags.count / 2],
      factLagP95Milliseconds: lags.isEmpty ? 0 : lags[min(lags.count - 1, lags.count * 95 / 100)],
      factLagMaxMilliseconds: longestFactLag
    )''')
    edit(SRC, '''  var replacedFrames: Int
  var replacedResults: Int

  /// The share of the window''', '''  var replacedFrames: Int
  var replacedResults: Int
  /// How old the newest server writes were when their frames finished applying: the lag a device following another
  /// one sees, plus any difference between this device's clock and the server's (#1796).
  var factLagFrames: Int
  var factLagMedianMilliseconds: Int
  var factLagP95Milliseconds: Int
  var factLagMaxMilliseconds: Int

  /// The share of the window''')

    edit(TEST, '''//                    open and frames were applying.
''', '''//                    open and frames were applying.
// 2026-11-04  #1796  A one-shot read whose add-query met a socket that had just died; how old the newest server
//                    write is when the buffer applies it, which nothing measured on the tablet.
''')
    edit(TEST, '''  // MARK: - A follower
''', '''  /// The buffer measures how old the newest server write is when its frame finishes applying (#1796): a `refresh-ok`
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
''')
    edit(TEST, '''  static func transactOK(_ write: String, transaction: Int) -> InstantLiveMessage {
    InstantLiveMessage(op: "transact-ok", clientEventID: write, fields: ["tx-id": .number(Double(transaction))])
  }
''', '''  static func transactOK(_ write: String, transaction: Int) -> InstantLiveMessage {
    InstantLiveMessage(op: "transact-ok", clientEventID: write, fields: ["tx-id": .number(Double(transaction))])
  }

  /// A `refresh-ok` restating `query` with one todo whose facts the server stored at `factTime`.
  static func timedRefresh(transaction: Int, _ query: FollowerQuery, factTime: Int64) -> InstantLiveMessage {
    timedRefresh(transaction: transaction, query, nodes: [timedNode(id: "todo-\\(transaction)", factTime: factTime)])
  }

  /// A `refresh-ok` whose newest fact is in a child node, as a parent row's included rows are.
  static func nestedRefresh(transaction: Int, _ query: FollowerQuery, childFactTime: Int64) -> InstantLiveMessage {
    let child = timedNode(id: "todo-child-\\(transaction)", factTime: childFactTime)
    return timedRefresh(
      transaction: transaction,
      query,
      nodes: [timedNode(id: "todo-parent-\\(transaction)", factTime: childFactTime - 60_000, children: [child])]
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
''')
    edit(TEST, '''private struct FollowerWaitTimedOut: Error, CustomStringConvertible {
  var description: String
}
''', '''private struct FollowerWaitTimedOut: Error, CustomStringConvertible {
  var description: String
}

private struct FollowerBufferEnded: Error {}
''')

elif step == "green":
    edit(SRC, '''//   buffer counts its progress for one-shot reads and logs a receive summary a minute (#1796).
''', '''//   buffer counts its progress for one-shot reads and logs a receive summary a minute (#1796).
// - 2026-11-04: the receive summary measures how old the newest server write is when its frame is applied, the lag a
//   device following another one sees (#1796).
''')
    edit(SRC, '''  /// Whether this frame is a query's result, which the next connection's answer to `add-query` replaces.
  var isQueryResult: Bool { Self.queryResultOps.contains(op) }
}
''', '''  /// Whether this frame is a query's result, which the next connection's answer to `add-query` replaces.
  var isQueryResult: Bool { Self.queryResultOps.contains(op) }

  /// The newest time at which the server stored a fact this query result carries, in milliseconds since 1970 (#1796):
  /// the fourth element of each `[entity, attribute, value, created-at]` join-row triple, child nodes included, which
  /// the applier stores as each fact's `txTime`. Nil for any other frame, or for a result with no timed fact.
  var newestFactMilliseconds: Int64? {
    var pending: [InstantLiveJSONValue]
    switch op {
    case "refresh-ok":
      pending = (fields["computations"]?.arrayValue ?? []).flatMap {
        $0.objectValue?["instaql-result"]?.arrayValue ?? []
      }
    case "add-query-ok":
      pending = fields["result"]?.arrayValue ?? []
    default:
      return nil
    }
    var newest: Int64?
    while let node = pending.popLast() {
      guard let object = node.objectValue else { continue }
      let rows = object["data"]?.objectValue?["datalog-result"]?.objectValue?["join-rows"]?.arrayValue ?? []
      for row in rows {
        for triple in row.arrayValue ?? [] {
          guard let elements = triple.arrayValue, elements.count >= 4,
            let time = Self.factTimeMilliseconds(elements[3])
          else { continue }
          newest = max(newest ?? time, time)
        }
      }
      pending.append(contentsOf: object["child-nodes"]?.arrayValue ?? [])
    }
    return newest
  }

  private static func factTimeMilliseconds(_ value: InstantLiveJSONValue) -> Int64? {
    switch value {
    case let .number(number):
      guard number.isFinite, abs(number) < 9.0e18 else { return nil }
      return Int64(number.rounded())
    case let .string(text):
      return Int64(text)
    case .null, .bool, .array, .object:
      return nil
    }
  }
}
''')
    edit(SRC, '''  /// One received frame, what it restates when it is a `refresh-ok`, and when the reader received it.
  private struct Received {
    var message: InstantLiveMessage
    var restatement: InstantLiveRefreshRestatement?
    var receivedAt: ContinuousClock.Instant
  }
''', '''  /// One received frame, what it restates when it is a `refresh-ok`, its newest fact, and when the reader received it.
  private struct Received {
    var message: InstantLiveMessage
    var restatement: InstantLiveRefreshRestatement?
    var newestFact: NewestFact?
    var receivedAt: ContinuousClock.Instant
  }

  /// The newest server time among a query result's facts, and whether its age counts as lag (#1796). A `refresh-ok`
  /// follows a change on the server; an answer to `add-query` restates what the server already holds, however old, so
  /// it only moves the mark the next refresh is measured against.
  private struct NewestFact {
    var milliseconds: Int64
    var counts: Bool
  }
''')
    edit(SRC, '''  /// This device's wall clock in milliseconds since 1970, the scale of the server's fact times (#1796).
  private let wallClockMilliseconds: @Sendable () -> Int64
''', '''  /// This device's wall clock in milliseconds since 1970, the scale of the server's fact times (#1796).
  private let wallClockMilliseconds: @Sendable () -> Int64
  /// The newest fact of the frame the applier took last, and the newest fact applied before it.
  private var lastTakenFact: NewestFact?
  private var newestAppliedFact: Int64?
''')
    edit(SRC, '''    let frame = Received(
      message: message,
      restatement: InstantLiveRefreshRestatement(message),
      receivedAt: clock.now
    )
''', '''    let frame = Received(
      message: message,
      restatement: InstantLiveRefreshRestatement(message),
      newestFact: message.newestFactMilliseconds.map { NewestFact(milliseconds: $0, counts: message.op == "refresh-ok") },
      receivedAt: clock.now
    )
''')
    edit(SRC, '''      meter.recordTake(waited: .zero, buffered: 0)
      lastTakenAt = clock.now
      return .handed(applier)
''', '''      meter.recordTake(waited: .zero, buffered: 0)
      lastTakenAt = clock.now
      lastTakenFact = frame.newestFact
      return .handed(applier)
''')
    edit(SRC, '''      } else {
        frames[index].message.fields["computations"] = .array(kept)
        frames[index].restatement?.queries.subtract(newer.queries)
      }
''', '''      } else {
        frames[index].message.fields["computations"] = .array(kept)
        frames[index].restatement?.queries.subtract(newer.queries)
        // Its newest fact may have left with the results; the newer frame carries those, and counts them.
        frames[index].newestFact = nil
      }
''')
    edit(SRC, '''    meter.recordTake(waited: now - frame.receivedAt, buffered: frames.count)
    lastTakenAt = now
    guard let reader = waitingReader else { return (frame.message, nil) }
''', '''    meter.recordTake(waited: now - frame.receivedAt, buffered: frames.count)
    lastTakenAt = now
    lastTakenFact = frame.newestFact
    guard let reader = waitingReader else { return (frame.message, nil) }
''')
    edit(SRC, '''    if let lastTakenAt {
      meter.recordApply(now - lastTakenAt)
      self.lastTakenAt = nil
    }
    return meter.summary(at: now, buffered: frames.count)
''', '''    if let lastTakenAt {
      meter.recordApply(now - lastTakenAt)
      self.lastTakenAt = nil
    }
    if let fact = lastTakenFact {
      lastTakenFact = nil
      if fact.milliseconds > newestAppliedFact ?? .min {
        if fact.counts {
          // A device clock behind the server's reads as a negative age, which counts as none.
          meter.recordFactLag(milliseconds: Int(max(0, wallClockMilliseconds() - fact.milliseconds)))
        }
        newestAppliedFact = fact.milliseconds
      }
    }
    return meter.summary(at: now, buffered: frames.count)
''')
    edit(SRC, '''  mutating func recordFactLag(milliseconds: Int) {}
''', '''  mutating func recordFactLag(milliseconds: Int) {
    factLagFrames += 1
    longestFactLag = max(longestFactLag, milliseconds)
    if factLagsMilliseconds.count < Self.maximumKeptWaits {
      factLagsMilliseconds.append(milliseconds)
    }
  }
''')
    edit(SRC, '''  /// A notice when a frame waited a second or more, which a follower sees as lag; otherwise a routine line.
  func log() {
    let level: InstantDiagnosticLevel = waitMaxMilliseconds >= 1_000 ? .notice : .info
''', '''  /// A notice when a frame waited a second or more, or the newest writes reached this store 10 s or more after the
  /// server stored them, which a follower sees as lag; otherwise a routine line.
  func log() {
    let level: InstantDiagnosticLevel =
      waitMaxMilliseconds >= 1_000 || factLagMaxMilliseconds >= 10_000 ? .notice : .info
''')
    edit(SRC, '''        + "newer frames replaced \\(replacedFrames) waiting refreshes and \\(replacedResults) results.",
''', '''        + "newer frames replaced \\(replacedFrames) waiting refreshes and \\(replacedResults) results; the newest "
        + "server writes reached this store \\(factLagMedianMilliseconds) ms after the server stored them at the median, "
        + "\\(factLagP95Milliseconds) ms at p95 and \\(factLagMaxMilliseconds) ms at most (\\(factLagFrames) frames).",
''')
    edit(SRC, '''        "replacedResults": String(replacedResults),
      ]
''', '''        "replacedResults": String(replacedResults),
        "factLagFrames": String(factLagFrames),
        "factLagMedianMilliseconds": String(factLagMedianMilliseconds),
        "factLagP95Milliseconds": String(factLagP95Milliseconds),
        "factLagMaxMilliseconds": String(factLagMaxMilliseconds),
      ]
''')
else:
    sys.exit("usage: apply3.py red|green [root]")
