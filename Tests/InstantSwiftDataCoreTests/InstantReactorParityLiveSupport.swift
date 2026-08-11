import Foundation
@testable import InstantSwiftDataCore

final class InstantLiveTestThrowingContinuationBox<Value: Sendable>: @unchecked Sendable {
  private let lock = NSLock()
  private var continuation: CheckedContinuation<Value, Error>?

  init(_ continuation: CheckedContinuation<Value, Error>) {
    self.continuation = continuation
  }

  func resume(returning value: Value) {
    resume(with: .success(value))
  }

  func resume(throwing error: any Error) {
    resume(with: .failure(error))
  }

  private func resume(with result: Result<Value, any Error>) {
    let continuation = lock.withLock {
      let continuation = self.continuation
      self.continuation = nil
      return continuation
    }
    continuation?.resume(with: result)
  }
}

struct InstantLiveTestPendingOperation<Value: Sendable>: Sendable {
  var id: UUID
  var abortToken: UUID
  var continuation: InstantLiveTestThrowingContinuationBox<Value>
}

/// Owns the exact continuation and operation task for one scripted connection
/// attempt. `abort()` is synchronous, lock-backed, and safe to call before the
/// connector task starts, while it is suspended, or after it returns a session.
final class InstantLiveTestConnectionContinuation: @unchecked Sendable {
  private typealias Outcome = Result<InstantLiveWebSocketSession, any Error>

  private let lock = NSLock()
  private var continuation:
    InstantLiveTestThrowingContinuationBox<InstantLiveWebSocketSession>?
  private var bufferedOutcome: Outcome?
  private var operationTask: Task<Void, Never>?
  private var didInstallContinuation = false
  private var didResolve = false
  private var didStartOperation = false
  private var isAborted = false

  func start(
    _ operation:
      @escaping @Sendable () async throws
        -> InstantLiveWebSocketSession
  ) {
    let shouldStart = lock.withLock {
      guard !didStartOperation, !isAborted else { return false }
      didStartOperation = true
      return true
    }
    guard shouldStart else { return }

    let task = Task {
      do {
        resolve(.success(try await operation()))
      } catch {
        resolve(.failure(error))
      }
    }
    let shouldCancel = lock.withLock {
      guard !isAborted, !didResolve else { return true }
      operationTask = task
      return false
    }
    if shouldCancel { task.cancel() }
  }

  func connect() async throws -> InstantLiveWebSocketSession {
    try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { rawContinuation in
        let continuation = InstantLiveTestThrowingContinuationBox(rawContinuation)
        let immediateOutcome = lock.withLock { () -> Outcome? in
          guard !didInstallContinuation else {
            return .failure(
              InstantError(
                code: .validationFailed,
                operation: "connect scripted Instant live transport",
                message: "The same scripted connection continuation was awaited twice.",
                recovery: "Create one continuation for every connection attempt."
              )
            )
          }
          didInstallContinuation = true
          guard !isAborted else { return .failure(CancellationError()) }
          if let bufferedOutcome {
            self.bufferedOutcome = nil
            return bufferedOutcome
          }
          self.continuation = continuation
          return nil
        }
        if let immediateOutcome {
          resume(continuation, with: immediateOutcome)
        }
      }
    } onCancel: {
      abort()
    }
  }

  func succeed(_ session: InstantLiveWebSocketSession) {
    resolve(.success(session))
  }

  func fail(_ error: any Error) {
    resolve(.failure(error))
  }

  func abort() {
    let abandoned = lock.withLock {
      () -> (
        Task<Void, Never>?,
        InstantLiveTestThrowingContinuationBox<InstantLiveWebSocketSession>?,
        InstantLiveWebSocketSession?
      ) in
      guard !isAborted else { return (nil, nil, nil) }
      isAborted = true
      let task = operationTask
      operationTask = nil
      let continuation = self.continuation
      self.continuation = nil
      let session: InstantLiveWebSocketSession?
      if case let .success(bufferedSession)? = bufferedOutcome {
        session = bufferedSession
      } else {
        session = nil
      }
      bufferedOutcome = nil
      return (task, continuation, session)
    }
    abandoned.0?.cancel()
    abandoned.1?.resume(throwing: CancellationError())
    abandoned.2?.abort()
  }

  private func resolve(_ outcome: Outcome) {
    let resolution = lock.withLock {
      () -> (
        InstantLiveTestThrowingContinuationBox<InstantLiveWebSocketSession>?,
        Outcome?,
        InstantLiveWebSocketSession?
      ) in
      operationTask = nil
      guard !didResolve else {
        if case let .success(session) = outcome {
          return (nil, nil, session)
        }
        return (nil, nil, nil)
      }
      didResolve = true
      guard !isAborted else {
        if case let .success(session) = outcome {
          return (nil, nil, session)
        }
        return (nil, nil, nil)
      }
      if let continuation {
        self.continuation = nil
        return (continuation, outcome, nil)
      }
      bufferedOutcome = outcome
      return (nil, nil, nil)
    }
    if let continuation = resolution.0, let outcome = resolution.1 {
      resume(continuation, with: outcome)
    }
    resolution.2?.abort()
  }

  private func resume(
    _ continuation:
      InstantLiveTestThrowingContinuationBox<InstantLiveWebSocketSession>,
    with outcome: Outcome
  ) {
    switch outcome {
    case let .success(session):
      continuation.resume(returning: session)
    case let .failure(error):
      continuation.resume(throwing: error)
    }
  }
}

final class InstantLiveTestWireAbortState: @unchecked Sendable {
  private let lock = NSLock()
  private var actions: [UUID: @Sendable () -> Void] = [:]
  private var aborted = false

  var isAborted: Bool {
    lock.withLock { aborted }
  }

  func check() throws {
    if isAborted {
      throw CancellationError()
    }
  }

  func register(_ action: @escaping @Sendable () -> Void) -> UUID? {
    lock.withLock {
      guard !aborted else { return nil }
      let id = UUID()
      actions[id] = action
      return id
    }
  }

  func unregister(_ id: UUID) {
    lock.withLock { actions[id] = nil }
  }

  func abort() {
    let actions = lock.withLock {
      guard !aborted else { return [@Sendable () -> Void]() }
      aborted = true
      let actions = Array(self.actions.values)
      self.actions.removeAll()
      return actions
    }
    for action in actions {
      action()
    }
  }
}

// SAFETY: `lock` protects every mutable field, and continuations are always
// extracted while locked and resumed only after the lock is released.
final class LiveReactorParityExactCloseCheckpoint: @unchecked Sendable {
  private let lock = NSLock()
  private var didEnterStorage = false
  private var didObserveCancellationStorage: Bool?
  private var releaseToCancellationContinuation: CheckedContinuation<Void, Never>?
  private var finishContinuation: CheckedContinuation<Void, Never>?
  private var shouldReleaseToCancellation = false
  private var shouldFinish = false

  var didEnter: Bool {
    lock.withLock { didEnterStorage }
  }

  var didObserveCancellation: Bool? {
    lock.withLock { didObserveCancellationStorage }
  }

  func pause() async {
    await withCheckedContinuation { continuation in
      lock.lock()
      didEnterStorage = true
      if shouldReleaseToCancellation {
        lock.unlock()
        continuation.resume()
      } else {
        releaseToCancellationContinuation = continuation
        lock.unlock()
      }
    }

    lock.withLock {
      didObserveCancellationStorage = Task.isCancelled
    }

    await withCheckedContinuation { continuation in
      lock.lock()
      if shouldFinish {
        lock.unlock()
        continuation.resume()
      } else {
        finishContinuation = continuation
        lock.unlock()
      }
    }
  }

  func releaseToCancellationObservation() {
    let continuation = lock.withLock {
      shouldReleaseToCancellation = true
      let continuation = releaseToCancellationContinuation
      releaseToCancellationContinuation = nil
      return continuation
    }
    continuation?.resume()
  }

  func finish() {
    let continuations = lock.withLock {
      shouldReleaseToCancellation = true
      shouldFinish = true
      let continuations = (
        releaseToCancellationContinuation,
        finishContinuation
      )
      releaseToCancellationContinuation = nil
      finishContinuation = nil
      return continuations
    }
    continuations.0?.resume()
    continuations.1?.resume()
  }
}

actor LiveReactorParityCompletionProbe {
  private var countStorage = 0

  var count: Int { countStorage }

  func record() {
    countStorage += 1
  }
}

private struct LiveReactorParityCountWaiters {
  private struct Waiter {
    var id: UUID
    var count: Int
    var continuation: CheckedContinuation<Void, Never>
  }

  private var waiters: [Waiter] = []

  mutating func append(
    id: UUID,
    count: Int,
    continuation: CheckedContinuation<Void, Never>
  ) {
    waiters.append(Waiter(id: id, count: count, continuation: continuation))
  }

  mutating func resumeSatisfied(by count: Int) {
    var pending: [Waiter] = []
    for waiter in waiters {
      if count >= waiter.count {
        waiter.continuation.resume()
      } else {
        pending.append(waiter)
      }
    }
    waiters = pending
  }

  mutating func cancel(id: UUID) {
    guard let index = waiters.firstIndex(where: { $0.id == id }) else { return }
    waiters.remove(at: index).continuation.resume()
  }
}

actor LiveReactorParitySession {
  nonisolated private let abortState = InstantLiveTestWireAbortState()
  private var messages: [InstantLiveMessage]
  private var sent: [InstantLiveMessage] = []
  private var sentWaiters = LiveReactorParityCountWaiters()
  private var receiveContinuation: InstantLiveTestPendingOperation<InstantLiveMessage>?
  private var receiveFailure: InstantError?
  private var isClosed = false

  init(messages: [InstantLiveMessage]) {
    self.messages = messages
  }

  nonisolated var transport: InstantLiveTransportClient {
    .immediate { _ in
      self.webSocketSession
    }
  }

  nonisolated var webSocketSession: InstantLiveWebSocketSession {
    InstantLiveWebSocketSession(
      send: { message in try await self.send(message) },
      receive: {
        try self.abortState.check()
        return try await self.receive()
      },
      close: { await self.close() },
      abort: { self.abortState.abort() }
    )
  }

  func sentMessages() -> [InstantLiveMessage] {
    sent
  }

  func waitForSentMessageCount(_ count: Int) async {
    guard sent.count < count else { return }
    let waiterID = UUID()
    await withTaskCancellationHandler {
      await withCheckedContinuation { continuation in
        if Task.isCancelled {
          continuation.resume()
        } else {
          sentWaiters.append(id: waiterID, count: count, continuation: continuation)
        }
      }
    } onCancel: {
      Task { await self.cancelSentWaiter(id: waiterID) }
    }
  }

  func enqueue(_ message: InstantLiveMessage) {
    guard !abortState.isAborted else { return }
    if let receiveContinuation {
      self.receiveContinuation = nil
      abortState.unregister(receiveContinuation.abortToken)
      receiveContinuation.continuation.resume(returning: message)
    } else if !isClosed {
      messages.append(message)
    }
  }

  func failReceive(_ error: InstantError) {
    guard !abortState.isAborted else { return }
    if let receiveContinuation {
      self.receiveContinuation = nil
      abortState.unregister(receiveContinuation.abortToken)
      receiveContinuation.continuation.resume(throwing: error)
    } else if !isClosed {
      receiveFailure = error
    }
  }

  private func send(_ message: InstantLiveMessage) throws {
    try abortState.check()
    sent.append(message)
    sentWaiters.resumeSatisfied(by: sent.count)
  }

  private func cancelSentWaiter(id: UUID) {
    sentWaiters.cancel(id: id)
  }

  private func receive() async throws -> InstantLiveMessage {
    try abortState.check()
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
    let id = UUID()
    defer { clearReceiveContinuation(id: id) }
    return try await withCheckedThrowingContinuation { continuation in
      let continuation = InstantLiveTestThrowingContinuationBox(continuation)
      guard
        let abortToken = abortState.register({
          continuation.resume(throwing: CancellationError())
        })
      else {
        continuation.resume(throwing: CancellationError())
        return
      }
      receiveContinuation = InstantLiveTestPendingOperation(
        id: id,
        abortToken: abortToken,
        continuation: continuation
      )
    }
  }

  private func close() {
    isClosed = true
    abortState.abort()
    receiveContinuation = nil
  }

  private func clearReceiveContinuation(id: UUID) {
    guard let receiveContinuation, receiveContinuation.id == id else { return }
    abortState.unregister(receiveContinuation.abortToken)
    self.receiveContinuation = nil
  }
}

actor LiveReactorParityTransport {
  private var attempts: [LiveReactorParityTransportAttempt]
  private var requests: [InstantLiveSessionRequest] = []
  private var waiters = LiveReactorParityCountWaiters()

  init(sessions: [LiveReactorParitySession]) {
    self.attempts = sessions.map(LiveReactorParityTransportAttempt.session)
  }

  init(attempts: [LiveReactorParityTransportAttempt]) {
    self.attempts = attempts
  }

  nonisolated var transport: InstantLiveTransportClient {
    .connectionAttempts { request in
      let connection = InstantLiveTestConnectionContinuation()
      return InstantLiveConnectionAttempt(
        connect: {
          connection.start { try await self.connect(request) }
          return try await connection.connect()
        },
        abort: { connection.abort() }
      )
    }
  }

  func connectionRequests() -> [InstantLiveSessionRequest] {
    requests
  }

  func waitForConnectionCount(_ count: Int) async {
    guard requests.count < count else { return }
    let waiterID = UUID()
    await withTaskCancellationHandler {
      await withCheckedContinuation { continuation in
        if Task.isCancelled {
          continuation.resume()
        } else {
          waiters.append(id: waiterID, count: count, continuation: continuation)
        }
      }
    } onCancel: {
      Task { await self.cancelConnectionWaiter(id: waiterID) }
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
    waiters.resumeSatisfied(by: requests.count)
  }

  private func cancelConnectionWaiter(id: UUID) {
    waiters.cancel(id: id)
  }
}

enum LiveReactorParityTransportAttempt: Sendable {
  case session(LiveReactorParitySession)
  case failure(InstantError)
}

actor LiveReactorParityReconnectSleep {
  private let suspendsUntilCancelled: Bool
  private let postCancellationCheckpoint: LiveReactorParityExactCloseCheckpoint?
  private var recordedDelays: [UInt64] = []
  private var cancellationCountStorage = 0

  init(
    suspendsUntilCancelled: Bool = false,
    postCancellationCheckpoint: LiveReactorParityExactCloseCheckpoint? = nil
  ) {
    self.suspendsUntilCancelled = suspendsUntilCancelled
    self.postCancellationCheckpoint = postCancellationCheckpoint
  }

  func sleep(milliseconds: UInt64) async throws {
    recordedDelays.append(milliseconds)
    guard suspendsUntilCancelled else { return }
    do {
      try await Task.sleep(nanoseconds: 60_000_000_000)
    } catch is CancellationError {
      cancellationCountStorage += 1
      await postCancellationCheckpoint?.pause()
      throw CancellationError()
    }
  }

  func delays() -> [UInt64] {
    recordedDelays
  }

  func cancellationCount() -> Int {
    cancellationCountStorage
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

func liveReactorServerAttr(
  id: String,
  name: String,
  namespace: String = TodoExample.namespace,
  valueType: String? = nil
) -> InstantLiveJSONValue {
  let resolvedValueType =
    valueType
    ?? (name == "createdAt" || name == "updatedAt"
      ? "date"
      : (name == "isCompleted" || name == "buildIsDirty" ? "boolean" : "string"))
  return .object([
    "cardinality": .string("one"),
    "forward-identity": .array([
      .string("identity-\(id)"),
      .string(namespace),
      .string(name),
    ]),
    "id": .string(id),
    "unique?": .bool(name == "id"),
    "value-type": .string(resolvedValueType),
  ])
}

/// Map local InstantAttribute rows into init-ok server attrs for reactor tests.
func liveReactorServerAttrs(from attributes: [InstantAttribute]) -> [InstantLiveJSONValue] {
  attributes.map { attribute in
    let valueType: String
    switch attribute.valueType {
    case .string: valueType = "string"
    case .number: valueType = "number"
    case .boolean: valueType = "boolean"
    case .date: valueType = "date"
    case .json: valueType = "json"
    case .any: valueType = "any"
    case .ref: valueType = "ref"
    }
    return liveReactorServerAttr(
      id: attribute.id,
      name: attribute.name,
      namespace: attribute.namespace,
      valueType: valueType
    )
  }
}
