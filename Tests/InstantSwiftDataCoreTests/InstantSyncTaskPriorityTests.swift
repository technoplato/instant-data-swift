import CustomDump
import Foundation
import Testing

@testable import InstantSwiftDataCore

/// #590: the runtime's steady-state sync tasks inherited the priority of whatever task opened the runtime. An app that
/// opens it from a user-initiated task ran them on the performance cores for the process's life: while recording, 64 of
/// the app's 125 CPU-seconds in five minutes were user-initiated (build 114, Power Profiler). The live session's reader
/// and frame applier and the mutation delivery pump run at `liveSyncTaskPriority` when the app sets it; a call the app
/// awaits (the connect handshake, a write, a read) keeps its own priority.
@Suite
struct InstantSyncTaskPriorityTests {
  @Test
  func steadyStateSyncRunsAtTheConfiguredPriorityWhicheverTaskConnects() async throws {
    let loopback = PriorityLoopback()
    var configuration = InstantRuntimeConfiguration(
      appID: "sync-task-priority",
      apiURI: URL(string: "http://127.0.0.1:1")!,
      websocketURI: URL(string: "ws://127.0.0.1:1/runtime/session")!,
      persistenceURL: FileManager.default.temporaryDirectory
        .appendingPathComponent("instant-sync-task-priority-\(UUID().uuidString).sqlite"),
      initialAttributes: TodoExample.attributes,
      liveTransport: .immediate { _ in loopback.session() },
      userCookieSyncClient: .local
    )
    // Nil (inherit) unless the app chooses: utility work also waits behind every busier task.
    expectNoDifference(configuration.liveSyncTaskPriority, nil)
    configuration.liveSyncTaskPriority = .utility
    let runtime = try await InstantRuntime.bootstrap(configuration: configuration)

    try await Task(priority: .userInitiated) {
      _ = try await runtime.connect()
      _ = try await runtime.transact(
        InstantStoreTransaction(
          id: "priority-write",
          operations: [
            .insert(
              InstantTriple(
                entityID: "priority-todo",
                attributeID: "todos/text",
                value: .string("written from a user-initiated task"),
                txID: "priority-write",
                txTime: InstantTimestamp(milliseconds: 1_000)
              )
            )
          ]
        ),
        createdAt: InstantTimestamp(milliseconds: 1_000)
      )
    }.value
    try await instantLiveWithTimeout(
      operation: "wait for the write and its acknowledgement to pass the loopback",
      timeoutMilliseconds: InstantTestWait.hangMilliseconds
    ) {
      while loopback.observed().receives.count < 3 || loopback.observed().transactSends.isEmpty {
        try Task.checkCancellation()
        await Task.yield()
      }
    }

    let observed = loopback.observed()
    // The handshake's init-ok is read by the connecting call; every read after it is the session's reader.
    let readerReceives = observed.receives.dropFirst()
    #expect(!readerReceives.isEmpty)
    #expect(readerReceives.allSatisfy { $0 == .utility }, "\(observed.receives)")
    expectNoDifference(observed.transactSends, [.utility])
    _ = try await runtime.closeConnection()
  }
}

/// A live session that answers init with init-ok and each transact with transact-ok, and records the priority of the
/// task that sent each transact and of each receive.
private final class PriorityLoopback: @unchecked Sendable {
  struct Observed {
    var receives: [TaskPriority] = []
    var transactSends: [TaskPriority] = []
  }

  // SAFETY: `lock` guards every field below.
  private let lock = NSLock()
  private var pending: [InstantLiveMessage] = []
  private var waiters: [CheckedContinuation<InstantLiveMessage, any Error>] = []
  private var recorded = Observed()
  private var transactionNumber = 0

  func observed() -> Observed {
    lock.withLock { recorded }
  }

  func session() -> InstantLiveWebSocketSession {
    InstantLiveWebSocketSession(
      send: { [self] message in send(message) },
      receive: { [self] in try await receive() },
      close: { [self] in failWaiters() },
      abort: { [self] in failWaiters() }
    )
  }

  private func failWaiters() {
    let failed = lock.withLock {
      defer { waiters = [] }
      return waiters
    }
    for waiter in failed { waiter.resume(throwing: CancellationError()) }
  }

  private func send(_ message: InstantLiveMessage) {
    let priority = Task.currentPriority
    var response: InstantLiveMessage?
    lock.withLock {
      switch message.op {
      case "init":
        response = InstantLiveMessage(
          op: "init-ok",
          clientEventID: message.clientEventID,
          fields: ["attrs": .array([]), "auth": .null, "session-id": .string("priority-session")]
        )
      case "transact":
        recorded.transactSends.append(priority)
        transactionNumber += 1
        response = InstantLiveMessage(
          op: "transact-ok",
          clientEventID: message.clientEventID,
          fields: ["tx-id": .string(String(transactionNumber))]
        )
      default:
        break
      }
    }
    guard let response else { return }
    let waiter: CheckedContinuation<InstantLiveMessage, any Error>? = lock.withLock {
      if waiters.isEmpty {
        pending.append(response)
        return nil
      }
      return waiters.removeFirst()
    }
    waiter?.resume(returning: response)
  }

  private func receive() async throws -> InstantLiveMessage {
    let priority = Task.currentPriority
    lock.withLock { recorded.receives.append(priority) }
    return try await withCheckedThrowingContinuation { continuation in
      let message: InstantLiveMessage? = lock.withLock {
        if pending.isEmpty {
          waiters.append(continuation)
          return nil
        }
        return pending.removeFirst()
      }
      if let message { continuation.resume(returning: message) }
    }
  }
}
