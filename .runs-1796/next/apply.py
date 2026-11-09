#!/usr/bin/env python3
"""#1796 step 2 (apply only after job 1796-check has STARTED: it snapshots the worktree at start).

  python3 .runs-1796/next/apply.py red    # the test: a one-shot read sent on a socket that just died
  python3 .runs-1796/next/apply.py green  # the fix: queryOnceThroughLive keeps the registration across the reconnect

Measured (iPad, build 248, 2026-11-04 17:33:00-17:33:12): the socket died after a 229 s suspension (POSIX 53); for 12 s
the connection still read as open, sends failed at once as InstantReceiverOwnedLiveSessionSendFailure, and a
recordingAttachments one-shot read failed in 0 ms. Observers already keep their registration for the reconnect
(InstantRuntime prepareObservation: "The registration stays recorded"); upstream Reactor.js sends a queryOnce's
add-query from _flushPendingMessages on the next init-ok.
"""
import pathlib, sys

root = pathlib.Path(__file__).resolve().parents[2]
step = sys.argv[1]

def edit(rel, old, new):
    p = root / rel
    s = p.read_text()
    if new in s:
        print(f"{rel}: already applied")
        return
    assert s.count(old) == 1, (rel, old[:80])
    p.write_text(s.replace(old, new))
    print(f"{rel}: applied")

TEST = "Tests/InstantSwiftDataCoreTests/InstantFollowerLatencyTests.swift"
if step == "red":
    edit(TEST, '''  /// A one-shot read on a socket that delivers nothing still fails after the 5 s stall, long before upstream's 30 s''',
'''  /// A one-shot read whose `add-query` met a socket that had just died waits for the reconnect and is answered on the
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
      expectNoDifference(emission.values.map(\\.id), ["todo-line-1"])
      _ = try await runtime.closeConnection()
    }
  }

  /// A one-shot read on a socket that delivers nothing still fails after the 5 s stall, long before upstream's 30 s''')
    edit(TEST, '''  private var sent: [InstantLiveMessage] = []
  private var isClosed = false
''', '''  private var sent: [InstantLiveMessage] = []
  private var isClosed = false
  private var death: (any Error)?
  /// The ops of the frames sent after the socket died, each of which failed.
  private(set) var failedSendOps: [String] = []
''')
    edit(TEST, '''  private func send(_ message: InstantLiveMessage) throws {
    try abortState.check()
    sent.append(message)
  }
''', '''  /// Ends the socket the way the system's abort after a suspension did: the pending receive and every later send fail.
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
''')
    edit(TEST, '''    if !frames.isEmpty {
      return frames.removeFirst()
    }
    if isClosed { throw CancellationError() }''', '''    if !frames.isEmpty {
      return frames.removeFirst()
    }
    if let death { throw death }
    if isClosed { throw CancellationError() }''')
    edit(TEST, '''/// An unknown op: the runtime records it as the frame being applied and ignores it otherwise.''',
'''/// The error a suspended app's socket fails with when it resumes (POSIX 53).
private let followerSocketAborted = NSError(
  domain: NSPOSIXErrorDomain,
  code: 53,
  userInfo: [NSLocalizedDescriptionKey: "Software caused connection abort"]
)

/// An unknown op: the runtime records it as the frame being applied and ignores it otherwise.''')
elif step == "green":
    edit("Sources/InstantSwiftDataCore/InstantRuntime.swift", '''      if let owedSend {
        try await liveSession.sendQueryRegistration(owedSend, clientEventID: configuration.makeID())
      }
      try await ensureLiveConnectionIfNeeded()
''', '''      if let owedSend {
        do {
          try await liveSession.sendQueryRegistration(owedSend, clientEventID: configuration.makeID())
        } catch is InstantReceiverOwnedLiveSessionSendFailure {
          // #1796: the socket died before its receiver took the death. The registration stays recorded and the next
          // session's init sends it with every registered query, as an observer's registration does and as upstream
          // `Reactor.js` sends a queryOnce's add-query from `_flushPendingMessages` on the next `init-ok`; the wait
          // below spans the reconnect. A tablet resuming from 229 s suspended failed a read this way in 0 ms while its
          // connection still read as open.
        }
      }
      try await ensureLiveConnectionIfNeeded()
''')
else:
    sys.exit("usage: apply.py red|green")
