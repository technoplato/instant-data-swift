import Dispatch
import Foundation
@testable import InstantSwiftDataCore
import Testing

/// The quality of service of the runtime's steady-state sync work (1.10.0).
///
/// During a 30-minute recording on library 1.9.8 (#590), unnamed workers at priority 37 (user-initiated) averaged
/// 10.7% of a phone core and peaked at 29.5%, and the process used 39% of a core against a 25% budget. The
/// persistence's decode queue ran at user-initiated, and the runtime's long-lived tasks inherited the priority of the
/// task that opened the runtime, which a client may open at user-initiated. #590 asks for a configurable decode QoS,
/// utility by default.
@Suite(.serialized)
struct InstantSyncQualityOfServiceTests {
  actor Recorded<Value: Sendable> {
    private(set) var values: [Value] = []

    func append(_ value: Value) {
      values.append(value)
    }
  }

  static func persistenceWithTodos(_ count: Int) async throws -> SQLitePersistenceStore {
    let url = try InstantLiveQueryResultWriteTests.temporaryCacheURL()
    let persistence = try SQLitePersistenceStore(fileURL: url)
    try await persistence.bootstrap()
    var triples: [InstantTriple] = []
    for index in 0..<count {
      triples += TodoExample.upsertOperations(
        id: InstantLiveQueryResultWriteTests.todoID(index),
        text: "todo \(index)",
        createdAt: InstantTimestamp(milliseconds: 1_700_000_000_000 + Int64(index)),
        transactionID: "seed"
      ).compactMap { operation in
        if case let .insert(triple) = operation { return triple }
        return nil
      }
    }
    try await persistence.saveStoreSnapshot(InstantStoreSnapshot(attributes: TodoExample.attributes, triples: triples))
    return persistence
  }

  @Test
  func decodeBatchesRunAtUtilityByDefault() async throws {
    let persistence = try await Self.persistenceWithTodos(200)
    let recorded = Recorded<DispatchQoS.QoSClass>()
    await persistence.observeDecodeBatchesForTesting { qos in Task { await recorded.append(qos) } }

    _ = try await Task(priority: .userInitiated) { try await persistence.loadCompactState() }.value

    try await InstantLiveQueryResultWriteTests.waitFor("a decode batch") { await !recorded.values.isEmpty }
    let classes = Set(await recorded.values)
    #expect(classes == [.utility])
  }

  @Test
  func decodeBatchesFollowTheirReaderWithoutAConfiguredQoS() async throws {
    let persistence = try await Self.persistenceWithTodos(200)
    await persistence.configureDecode(qos: nil)
    let recorded = Recorded<DispatchQoS.QoSClass>()
    await persistence.observeDecodeBatchesForTesting { qos in Task { await recorded.append(qos) } }

    _ = try await Task(priority: .userInitiated) { try await persistence.loadCompactState() }.value

    try await InstantLiveQueryResultWriteTests.waitFor("a decode batch") { await !recorded.values.isEmpty }
    let classes = Set(await recorded.values)
    #expect(classes == [.userInitiated])
  }

  @Test
  func theSteadyStateSyncTasksRunAtTheConfiguredPriorityWhateverOpenedTheRuntime() async throws {
    let url = try InstantLiveQueryResultWriteTests.temporaryCacheURL()
    let session = LiveReactorParitySession(messages: [liveReactorInitOK(attrs: liveReactorTodoServerAttrs)])
    let connectionTask = Recorded<TaskPriority>()
    let applier = Recorded<TaskPriority>()
    var configuration = InstantRuntimeConfiguration(
      appID: "sync-qos-priority",
      persistenceURL: url,
      initialAttributes: TodoExample.attributes,
      liveTransport: session.transport
    )
    configuration.liveReconnectSleep = { _ in }
    configuration.autoConnectLiveTransport = true
    configuration.liveSyncTaskPriority = .utility
    configuration.onAutomaticLiveConnectionTaskStartedForTesting = { await connectionTask.append(Task.currentPriority) }
    configuration.onLiveReceiverEventAcquiredForTesting = { await applier.append(Task.currentPriority) }
    let finalConfiguration = configuration

    // A client may open its store from a user-initiated detached task.
    let runtime = try await Task.detached(priority: .userInitiated) {
      try await InstantRuntime.bootstrap(configuration: finalConfiguration)
    }.value
    let query = try InstantLiveQueryEncoder.encode(TodoExample.query)
    let observation = await Task.detached(priority: .userInitiated) {
      await runtime.observeQueryLease(TodoExample.query)
    }.value
    try await InstantLiveQueryResultWriteTests.waitFor("the todo query's add-query") {
      await session.sentMessages().contains { $0.op == "add-query" }
    }
    await session.enqueue(
      liveReactorAddQueryOK(query: query, processedTransactionID: "server-tx-0", result: InstantLiveQueryResultWriteTests.todoResult(["one"]))
    )
    try await InstantLiveQueryResultWriteTests.waitFor("the applier's first frame") { await !applier.values.isEmpty }

    let connectionPriorities = await connectionTask.values
    let applierPriorities = await applier.values
    #expect(connectionPriorities == [.utility])
    #expect(!applierPriorities.isEmpty && applierPriorities.allSatisfy { $0 == .utility }, "\(applierPriorities)")
    await observation.cancel()
    _ = try await runtime.closeConnection()
  }
}
