import Foundation
@testable import InstantSwiftDataCore

actor LiveReactorParitySession {
  private struct SentWaiter {
    var count: Int
    var continuation: CheckedContinuation<Void, Never>
  }

  private var messages: [InstantLiveMessage]
  private var sent: [InstantLiveMessage] = []
  private var sentWaiters: [SentWaiter] = []
  private var receiveContinuation: CheckedContinuation<InstantLiveMessage, Error>?
  private var receiveFailure: InstantError?
  private var isClosed = false

  init(messages: [InstantLiveMessage]) {
    self.messages = messages
  }

  nonisolated var transport: InstantLiveTransportClient {
    InstantLiveTransportClient { _ in
      self.webSocketSession
    }
  }

  nonisolated var webSocketSession: InstantLiveWebSocketSession {
    InstantLiveWebSocketSession(
      send: { message in await self.send(message) },
      receive: { try await self.receive() },
      close: { await self.close() }
    )
  }

  func sentMessages() -> [InstantLiveMessage] {
    sent
  }

  func waitForSentMessageCount(_ count: Int) async {
    guard sent.count < count else { return }
    await withCheckedContinuation { continuation in
      sentWaiters.append(SentWaiter(count: count, continuation: continuation))
    }
  }

  func enqueue(_ message: InstantLiveMessage) {
    if let receiveContinuation {
      self.receiveContinuation = nil
      receiveContinuation.resume(returning: message)
    } else if !isClosed {
      messages.append(message)
    }
  }

  func failReceive(_ error: InstantError) {
    if let receiveContinuation {
      self.receiveContinuation = nil
      receiveContinuation.resume(throwing: error)
    } else if !isClosed {
      receiveFailure = error
    }
  }

  private func send(_ message: InstantLiveMessage) {
    sent.append(message)
    var pending: [SentWaiter] = []
    for waiter in sentWaiters {
      if sent.count >= waiter.count {
        waiter.continuation.resume()
      } else {
        pending.append(waiter)
      }
    }
    sentWaiters = pending
  }

  private func receive() async throws -> InstantLiveMessage {
    if !messages.isEmpty {
      return messages.removeFirst()
    }
    if let receiveFailure {
      self.receiveFailure = nil
      throw receiveFailure
    }
    if isClosed {
      throw CancellationError()
    }
    return try await withCheckedThrowingContinuation { continuation in
      receiveContinuation = continuation
    }
  }

  private func close() {
    isClosed = true
    receiveContinuation?.resume(throwing: CancellationError())
    receiveContinuation = nil
  }
}

actor LiveReactorParityTransport {
  private struct ConnectionWaiter {
    var count: Int
    var continuation: CheckedContinuation<Void, Never>
  }

  private var attempts: [LiveReactorParityTransportAttempt]
  private var requests: [InstantLiveSessionRequest] = []
  private var waiters: [ConnectionWaiter] = []

  init(sessions: [LiveReactorParitySession]) {
    self.attempts = sessions.map(LiveReactorParityTransportAttempt.session)
  }

  init(attempts: [LiveReactorParityTransportAttempt]) {
    self.attempts = attempts
  }

  nonisolated var transport: InstantLiveTransportClient {
    InstantLiveTransportClient { request in
      try await self.connect(request)
    }
  }

  func connectionRequests() -> [InstantLiveSessionRequest] {
    requests
  }

  func waitForConnectionCount(_ count: Int) async {
    guard requests.count < count else { return }
    await withCheckedContinuation { continuation in
      waiters.append(ConnectionWaiter(count: count, continuation: continuation))
    }
  }

  private func connect(_ request: InstantLiveSessionRequest) throws
    -> InstantLiveWebSocketSession
  {
    requests.append(request)
    resumeConnectionWaiters()
    guard !attempts.isEmpty else {
      throw InstantError(
        code: .networkFailed,
        operation: "connect Reactor parity live transport",
        message: "No scripted live session remains.",
        recovery: "Add one scripted session for every expected connection attempt."
      )
    }
    switch attempts.removeFirst() {
    case let .session(session):
      return session.webSocketSession
    case let .failure(error):
      throw error
    }
  }

  private func resumeConnectionWaiters() {
    var pending: [ConnectionWaiter] = []
    for waiter in waiters {
      if requests.count >= waiter.count {
        waiter.continuation.resume()
      } else {
        pending.append(waiter)
      }
    }
    waiters = pending
  }
}

enum LiveReactorParityTransportAttempt: Sendable {
  case session(LiveReactorParitySession)
  case failure(InstantError)
}

actor LiveReactorParityReconnectSleep {
  private struct DelayWaiter {
    var count: Int
    var continuation: CheckedContinuation<Void, Never>
  }

  private struct CancellationWaiter {
    var count: Int
    var continuation: CheckedContinuation<Void, Never>
  }

  private let suspendsUntilCancelled: Bool
  private var recordedDelays: [UInt64] = []
  private var cancellationCount = 0
  private var delayWaiters: [DelayWaiter] = []
  private var cancellationWaiters: [CancellationWaiter] = []

  init(suspendsUntilCancelled: Bool = false) {
    self.suspendsUntilCancelled = suspendsUntilCancelled
  }

  func sleep(milliseconds: UInt64) async throws {
    recordedDelays.append(milliseconds)
    resumeDelayWaiters()
    guard suspendsUntilCancelled else { return }
    do {
      try await Task.sleep(nanoseconds: 60_000_000_000)
    } catch is CancellationError {
      cancellationCount += 1
      resumeCancellationWaiters()
      throw CancellationError()
    }
  }

  func delays() -> [UInt64] {
    recordedDelays
  }

  func waitForDelayCount(_ count: Int) async {
    guard recordedDelays.count < count else { return }
    await withCheckedContinuation { continuation in
      delayWaiters.append(DelayWaiter(count: count, continuation: continuation))
    }
  }

  func waitForCancellationCount(_ count: Int) async {
    guard cancellationCount < count else { return }
    await withCheckedContinuation { continuation in
      cancellationWaiters.append(CancellationWaiter(count: count, continuation: continuation))
    }
  }

  private func resumeDelayWaiters() {
    var pending: [DelayWaiter] = []
    for waiter in delayWaiters {
      if recordedDelays.count >= waiter.count {
        waiter.continuation.resume()
      } else {
        pending.append(waiter)
      }
    }
    delayWaiters = pending
  }

  private func resumeCancellationWaiters() {
    var pending: [CancellationWaiter] = []
    for waiter in cancellationWaiters {
      if cancellationCount >= waiter.count {
        waiter.continuation.resume()
      } else {
        pending.append(waiter)
      }
    }
    cancellationWaiters = pending
  }
}

let liveReactorTodoServerAttrs: [InstantLiveJSONValue] = [
  liveReactorServerAttr(id: "server-todos-id", name: "id"),
  liveReactorServerAttr(id: "server-todos-text", name: "text"),
  liveReactorServerAttr(id: "server-todos-is-completed", name: "isCompleted"),
  liveReactorServerAttr(id: "server-todos-created-at", name: "createdAt"),
]

func liveReactorInitOK(
  attrs: [InstantLiveJSONValue],
  sessionID: String = "reactor-parity-session"
) -> InstantLiveMessage {
  InstantLiveMessage(
    op: "init-ok",
    clientEventID: "event-init",
    fields: [
      "attrs": .array(attrs),
      "auth": .null,
      "session-id": .string(sessionID),
    ]
  )
}

func liveReactorAddQueryOK(
  query: InstantLiveJSONValue,
  processedTransactionID: String,
  result: [InstantLiveJSONValue]
) -> InstantLiveMessage {
  InstantLiveMessage(
    op: "add-query-ok",
    clientEventID: "event-query",
    fields: [
      "q": query,
      "processed-tx-id": .string(processedTransactionID),
      "result": .array(result),
    ]
  )
}

func liveReactorTodoComputation(
  query: InstantLiveJSONValue,
  id: String,
  text: String,
  createdAt: InstantTimestamp,
  processedTransactionID: String
) -> InstantLiveJSONValue {
  .object([
    "instaql-query": query,
    "instaql-result": .array(
      liveReactorTodoQueryResult(id: id, text: text, createdAt: createdAt)
    ),
    "processed-tx-id": .string(processedTransactionID),
  ])
}

func liveReactorTodoQueryResult(
  id: String,
  text: String,
  createdAt: InstantTimestamp
) -> [InstantLiveJSONValue] {
  [
    .object([
      "data": .object([
        "datalog-result": .object([
          "join-rows": .array([
            .array([
              liveReactorJoinRow(id, "server-todos-id", .string(id), createdAt),
              liveReactorJoinRow(id, "server-todos-text", .string(text), createdAt),
              liveReactorJoinRow(id, "server-todos-is-completed", .bool(false), createdAt),
              liveReactorJoinRow(
                id,
                "server-todos-created-at",
                .number(Double(createdAt.milliseconds)),
                createdAt
              ),
            ])
          ])
        ])
      ]),
      "child-nodes": .array([]),
    ])
  ]
}

private func liveReactorJoinRow(
  _ entityID: String,
  _ attributeID: String,
  _ value: InstantLiveJSONValue,
  _ timestamp: InstantTimestamp
) -> InstantLiveJSONValue {
  .array([
    .string(entityID),
    .string(attributeID),
    value,
    .number(Double(timestamp.milliseconds)),
  ])
}

private func liveReactorServerAttr(id: String, name: String) -> InstantLiveJSONValue {
  .object([
    "cardinality": .string("one"),
    "forward-identity": .array([
      .string("identity-\(id)"),
      .string(TodoExample.namespace),
      .string(name),
    ]),
    "id": .string(id),
    "unique?": .bool(name == "id"),
    "value-type": .string(
      name == "createdAt" ? "date" : (name == "isCompleted" ? "boolean" : "string")
    ),
  ])
}
