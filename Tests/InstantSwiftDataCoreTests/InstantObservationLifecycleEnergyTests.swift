import CustomDump
import Foundation
import Testing
@testable import InstantSwiftDataCore

/// A store's observers go away when their readers stop (#669).
///
/// An app's media scan reads a few local queries once a minute: it observes each, takes the first emission through a
/// reader task, and cancels the reader. A live query that outlives a reconnect is registered again on the new socket.
/// Neither may leave an observer behind: each one is refreshed on every committed change for as long as it lives.
@Suite(.serialized)
struct InstantObservationLifecycleEnergyTests {
  @Test
  func readingTheFirstLocalEmissionAndCancellingLeavesNoObserver() async throws {
    let runtime = try await InstantRuntime.bootstrap(
      configuration: try observationEnergyConfiguration(appID: "observation-first-emission")
    )
    try await seedObservationEnergyTodos(on: runtime, count: 8)
    let standing = await runtime.observe(TodoExample.query)
    let standingReader = Task { for await _ in standing {} }
    try await observationEnergyWait("the standing observer to install") {
      await runtime.store.activeObservationCount() == 1
    }
    let plans = [
      InstantQueryPlan(id: "scan-a", namespace: TodoExample.namespace, limit: 64),
      InstantQueryPlan(
        id: "scan-b",
        namespace: TodoExample.namespace,
        filters: [.equals(field: "isCompleted", value: .bool(false))],
        limit: 64
      ),
      InstantQueryPlan(id: "scan-c", namespace: TodoExample.namespace, order: InstantQueryOrder("createdAt", .descending), limit: 8),
    ]
    // Twenty minutes of the scan: three reads a minute.
    for _ in 0..<20 {
      for plan in plans {
        let first = await firstLocalEmission(of: plan, on: runtime)
        #expect(first != nil)
      }
    }
    try await observationEnergyWait("every scan observer to go") {
      await runtime.store.activeObservationCount() == 1
    }
    let observers = await runtime.store.activeObservationCount()
    expectNoDifference(observers, 1, "Only the standing observer remains.")
    standingReader.cancel()
    try await observationEnergyWait("the standing observer to go") {
      await runtime.store.activeObservationCount() == 0
    }
  }

  /// The scan's reader is cancelled at its five-second timeout when the first emission is late, for one while a long
  /// server apply holds the runtime: here every reader is cancelled at once, whether or not its first emission came.
  @Test
  func cancellingAReaderBeforeItsFirstEmissionLeavesNoObserver() async throws {
    let runtime = try await InstantRuntime.bootstrap(
      configuration: try observationEnergyConfiguration(appID: "observation-early-cancel")
    )
    try await seedObservationEnergyTodos(on: runtime, count: 8)
    for index in 0..<60 {
      let plan = InstantQueryPlan(id: "early-cancel-\(index % 3)", namespace: TodoExample.namespace, limit: 8 + index % 3)
      let observation = await runtime.observeLocally(plan)
      let reader = Task { for await _ in observation {} }
      reader.cancel()
      await reader.value
    }
    try await observationEnergyWait("every cancelled reader's observer to go") {
      await runtime.store.activeObservationCount() == 0
    }
    let observers = await runtime.store.activeObservationCount()
    expectNoDifference(observers, 0)
  }

  @Test
  func aLiveObservationRegisteredAgainAfterAReconnectLeavesOneObserver() async throws {
    let transport = ObservationEnergyTransport()
    var configuration = try observationEnergyConfiguration(appID: "observation-reconnect", transport: transport.client)
    configuration.autoConnectLiveTransport = true
    configuration.liveReconnectSleep = { _ in }
    let runtime = try await InstantRuntime.bootstrap(configuration: configuration)
    try await observationEnergyWait("the first session to open") {
      try await runtime.connectionStatus().state == .opened
    }
    let observation = await runtime.observe(TodoExample.query)
    let reader = Task { for await _ in observation {} }
    try await observationEnergyWait("the live observer to install") {
      await runtime.store.activeObservationCount() == 1
    }
    for reconnect in 1...3 {
      let socket = try #require(await transport.socket(reconnect - 1))
      await socket.die()
      try await observationEnergyWait("reconnect \(reconnect) to open a session") {
        let sockets = await transport.socketCount
        let state = try await runtime.connectionStatus().state
        return sockets == reconnect + 1 && state == .opened
      }
      let observers = await runtime.store.activeObservationCount()
      expectNoDifference(observers, 1, "Registering the query again on the new socket adds no observer.")
    }
    reader.cancel()
    try await observationEnergyWait("the live observer to go") {
      await runtime.store.activeObservationCount() == 0
    }
    _ = try await runtime.closeConnection()
  }
}

/// The app's pattern: observe locally, forward through a reader task, take the first emission, cancel the reader.
private func firstLocalEmission(
  of plan: InstantQueryPlan,
  on runtime: InstantRuntime
) async -> InstantQueryEmission? {
  let observation = await runtime.observeLocally(plan)
  let (emissions, emitted) = AsyncStream.makeStream(
    of: InstantQueryEmission.self,
    bufferingPolicy: .bufferingNewest(1)
  )
  let reader = Task {
    for await emission in observation { emitted.yield(emission) }
    emitted.finish()
  }
  defer { reader.cancel() }
  for await emission in emissions {
    return emission
  }
  return nil
}

private func seedObservationEnergyTodos(on runtime: InstantRuntime, count: Int) async throws {
  var operations: [InstantTripleOperation] = []
  for index in 0..<count {
    operations += TodoExample.upsertOperations(
      id: "seed-todo-\(index)",
      text: "seed \(index)",
      createdAt: InstantTimestamp(milliseconds: 1_700_000_000_000 + Int64(index)),
      transactionID: "seed"
    )
  }
  _ = try await runtime.applyServerTransaction(
    InstantStoreTransaction(id: "seed", operations: operations),
    processedTransactionID: "1"
  )
}

/// One socket: answers `init` with `init-ok`, accepts every frame, and fails its pending receive on `die()`.
private actor ObservationEnergySocket {
  private let abortState = InstantLiveTestWireAbortState()
  private var frames: [InstantLiveMessage]
  private var pendingReceive: InstantLiveTestThrowingContinuationBox<InstantLiveMessage>?
  private var pendingAbortToken: UUID?
  private var isDead = false

  init(sessionID: String) {
    frames = [liveReactorInitOK(attrs: liveReactorTodoServerAttrs, sessionID: sessionID)]
  }

  nonisolated var session: InstantLiveWebSocketSession {
    InstantLiveWebSocketSession(
      send: { _ in try await self.send() },
      receive: { try await self.receive() },
      close: { await self.close() },
      abort: { self.abortState.abort() }
    )
  }

  func die() {
    guard !isDead else { return }
    isDead = true
    guard let pending = pendingReceive else { return }
    pendingReceive = nil
    if let token = pendingAbortToken {
      abortState.unregister(token)
      pendingAbortToken = nil
    }
    pending.resume(throwing: observationEnergySocketNotConnected)
  }

  private func send() throws {
    try abortState.check()
    if isDead { throw observationEnergySocketNotConnected }
  }

  private func receive() async throws -> InstantLiveMessage {
    try abortState.check()
    if !frames.isEmpty { return frames.removeFirst() }
    if isDead { throw observationEnergySocketNotConnected }
    return try await withCheckedThrowingContinuation { rawContinuation in
      let continuation = InstantLiveTestThrowingContinuationBox(rawContinuation)
      guard
        let token = abortState.register({ continuation.resume(throwing: CancellationError()) })
      else {
        continuation.resume(throwing: CancellationError())
        return
      }
      pendingReceive = continuation
      pendingAbortToken = token
    }
  }

  private func close() {
    abortState.abort()
  }
}

/// Opens a fresh socket for every attempt.
private actor ObservationEnergyTransport {
  private var sockets: [ObservationEnergySocket] = []

  var socketCount: Int { sockets.count }

  func socket(_ index: Int) -> ObservationEnergySocket? {
    sockets.indices.contains(index) ? sockets[index] : nil
  }

  nonisolated var client: InstantLiveTransportClient {
    .connectionAttempts { _ in
      let connection = InstantLiveTestConnectionContinuation()
      return InstantLiveConnectionAttempt(
        connect: {
          connection.start { await self.open() }
          return try await connection.connect()
        },
        abort: { connection.abort() }
      )
    }
  }

  private func open() -> InstantLiveWebSocketSession {
    let socket = ObservationEnergySocket(sessionID: "observation-energy-\(sockets.count + 1)")
    sockets.append(socket)
    return socket.session
  }
}

private let observationEnergySocketNotConnected = NSError(
  domain: NSPOSIXErrorDomain,
  code: 57,
  userInfo: [NSLocalizedDescriptionKey: "Socket is not connected"]
)

private func observationEnergyConfiguration(
  appID: String,
  transport: InstantLiveTransportClient? = nil
) throws -> InstantRuntimeConfiguration {
  let directory = FileManager.default.temporaryDirectory
    .appendingPathComponent("InstantObservationLifecycleEnergyTests-\(UUID().uuidString)")
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  var configuration = InstantRuntimeConfiguration(
    appID: appID,
    persistenceURL: directory.appendingPathComponent("state.sqlite"),
    initialAttributes: TodoExample.attributes,
    now: { InstantTimestamp(milliseconds: 1_700_000_000_000) },
    liveTransport: transport
  )
  configuration.autoConnectLiveTransport = false
  return configuration
}

private struct ObservationEnergyWaitTimedOut: Error, CustomStringConvertible {
  var description: String
}

/// Polls `condition` every 2 ms for at most 5 s (the codebase's timeout rule).
private func observationEnergyWait(
  _ description: String,
  _ condition: @Sendable () async throws -> Bool
) async throws {
  let deadline = ContinuousClock.now + .seconds(5)
  while !(try await condition()) {
    guard ContinuousClock.now < deadline else {
      throw ObservationEnergyWaitTimedOut(description: "Timed out after 5000 ms waiting for \(description).")
    }
    try await Task.sleep(nanoseconds: 2_000_000)
  }
}
