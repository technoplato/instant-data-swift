import CustomDump
import Foundation
import InstantSwiftData
import Testing

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

@Suite(.serialized)
struct InstantMessageServerAcceptanceTests {
  private let upstreamProvenance =
    "upstream/instant/client/packages/core/src/Reactor.js:pushOps/_handleMutationError/transact-ok"

  @Test
  func preparesOnceAndReturnsOnlyAfterServerAcceptance() async throws {
    let counter = MessagePreparationCounter()
    let completion = MessageTaskCompletionProbe()
    let session = AcceptanceReconnectLiveSession()
    let cacheURL = acceptanceCacheURL("accepted")
    let runtime = try await acceptanceRuntime(
      suffix: "accepted",
      cacheURL: cacheURL,
      liveTransport: session.transport
    )
    _ = try await runtime.connect()
    let client = InstantSwiftDataClient(runtime: runtime)
    let task = Task {
      do {
        let change = try await client.sendAwaitingServerAcceptance(
          AwaitedMessage(change: "accepted change", counter: counter)
        )
        await completion.finished()
        return change
      } catch {
        await completion.finished()
        throw error
      }
    }

    try await waitForAcceptanceMutation(runtime)
    let preparedBeforeAcceptance = await counter.value
    expectNoDifference(preparedBeforeAcceptance, 1)
    #expect(await !completion.isFinished)
    await session.acceptMutation(id: "tx-accepted", serverTransactionID: "server-tx-accepted")

    let acceptedChange = try await task.value
    let preparedAfterAcceptance = await counter.value
    expectNoDifference(acceptedChange, "accepted change")
    expectNoDifference(preparedAfterAcceptance, 1)
    expectNoDifference(
      upstreamProvenance,
      "upstream/instant/client/packages/core/src/Reactor.js:pushOps/_handleMutationError/transact-ok"
    )
    _ = try await runtime.closeConnection()
  }

  @Test
  func localTransportFlushCannotCompleteServerAcceptance() async throws {
    let completion = MessageTaskCompletionProbe()
    let (client, runtime, _) = try await acceptanceClient("local-flush")
    let task = acceptanceTask(
      client: client,
      change: "local flush is not server proof",
      completion: completion
    )

    try await waitForAcceptanceMutation(runtime)
    let flush = try await runtime.flushPendingMutations()
    expectNoDifference(flush.confirmed.map(\.id), ["tx-local-flush"])
    try await Task.sleep(for: .milliseconds(20))
    #expect(await !completion.isFinished)
    await expectAcceptanceTimeout(task, id: "tx-local-flush")
  }

  @Test
  func manualConfirmationCannotCompleteServerAcceptance() async throws {
    let completion = MessageTaskCompletionProbe()
    let (client, runtime, _) = try await acceptanceClient("manual-confirm")
    let task = acceptanceTask(
      client: client,
      change: "manual confirmation is not server proof",
      completion: completion
    )

    try await waitForAcceptanceMutation(runtime)
    _ = try await runtime.confirmMutation(id: "tx-manual-confirm")
    try await Task.sleep(for: .milliseconds(20))
    #expect(await !completion.isFinished)
    await expectAcceptanceTimeout(task, id: "tx-manual-confirm")
  }

  @Test
  func localDrainCannotCompleteServerAcceptance() async throws {
    let completion = MessageTaskCompletionProbe()
    let (client, runtime, _) = try await acceptanceClient("local-drain")
    let task = acceptanceTask(
      client: client,
      change: "local drain is not server proof",
      completion: completion
    )

    try await waitForAcceptanceMutation(runtime)
    let drained = try await runtime.drainPendingMutationsLocally()
    expectNoDifference(drained.map(\.id), ["tx-local-drain"])
    try await Task.sleep(for: .milliseconds(20))
    #expect(await !completion.isFinished)
    await expectAcceptanceTimeout(task, id: "tx-local-drain")
  }

  @Test
  func genericRefreshCannotCompleteServerAcceptanceEvenWhenCheckpointMatchesMutationID()
    async throws
  {
    let completion = MessageTaskCompletionProbe()
    let (client, runtime, _) = try await acceptanceClient("generic-refresh")
    let task = acceptanceTask(
      client: client,
      change: "query refresh is not transaction proof",
      completion: completion
    )

    try await waitForAcceptanceMutation(runtime)
    _ = try await runtime.applyLiveRefresh(
      InstantLiveRefreshOK(
        clientEventID: "tx-generic-refresh",
        processedTransactionID: "tx-generic-refresh",
        attrs: [],
        computations: []
      )
    )
    try await Task.sleep(for: .milliseconds(20))
    #expect(await !completion.isFinished)
    await expectAcceptanceTimeout(task, id: "tx-generic-refresh")
  }

  @Test
  func explicitlyServerAcceptedMutationTransportCompletesAcceptance() async throws {
    let cacheURL = acceptanceCacheURL("server-transport")
    let runtime = try await acceptanceRuntime(
      suffix: "server-transport",
      cacheURL: cacheURL,
      mutationTransport: InstantMutationTransportClient { request in
        InstantMutationTransportResponse(
          results: request.mutations.map {
            InstantMutationTransportResult(
              mutationID: $0.mutationID,
              outcome: .confirmed,
              acceptance: .serverAccepted
            )
          }
        )
      }
    )
    let client = InstantSwiftDataClient(runtime: runtime)
    let task = Task {
      try await client.sendAwaitingServerAcceptance(
        AwaitedMessage(change: "server transport accepted"),
        timeout: .seconds(1)
      )
    }

    try await waitForAcceptanceMutation(runtime)
    _ = try await runtime.flushPendingMutations()

    let accepted = try await task.value
    expectNoDifference(accepted, "server transport accepted")
  }

  @Test
  func retainedRejectionThrowsExactMessageAndMutationID() async throws {
    let (client, runtime, _) = try await acceptanceClient("retained")
    let task = Task {
      try await client.sendAwaitingServerAcceptance(
        AwaitedMessage(change: "retained change"),
        onServerRejected: { error in
          expectNoDifference(error.message, "title reservation permission denied")
          expectNoDifference(error.localID, "tx-retained")
          return .retainForRetry
        }
      )
    }

    try await waitForAcceptanceMutation(runtime)
    _ = try await runtime.failMutation(
      id: "tx-retained",
      message: "title reservation permission denied"
    )

    do {
      _ = try await task.value
      Issue.record("Expected the retained server rejection to throw.")
    } catch let error as InstantError {
      expectNoDifference(error.code, .permissionRejected)
      expectNoDifference(error.message, "title reservation permission denied")
      expectNoDifference(error.localID, "tx-retained")
      expectNoDifference(error.serverEventID, nil)
      expectNoDifference(error.localMutationDisposition, .retainedForRetry)
    }
    let retainedOutbox = try await client.failedMutations()
    expectNoDifference(retainedOutbox.map(\.status), [.failed])
  }

  @Test
  func handledRejectionDiscardsOnlyTheFailedMutationDurably() async throws {
    let (client, runtime, cacheURL) = try await acceptanceClient("discarded")
    let task = Task {
      try await client.sendAwaitingServerAcceptance(
        AwaitedMessage(change: "discarded change"),
        onServerRejected: { _ in .discard }
      )
    }

    try await waitForAcceptanceMutation(runtime)
    _ = try await runtime.failMutation(id: "tx-discarded", message: "CAS lost")
    do {
      _ = try await task.value
      Issue.record("Expected the validation rejection to throw.")
    } catch let error as InstantError {
      expectNoDifference(error.code, .validationFailed)
      expectNoDifference(error.message, "CAS lost")
      expectNoDifference(error.localID, "tx-discarded")
      expectNoDifference(error.localMutationDisposition, .discarded)
    }
    let discardedOutbox = try await client.failedMutations()
    expectNoDifference(discardedOutbox, [])

    let relaunched = try await acceptanceRuntime(suffix: "discarded", cacheURL: cacheURL)
    let relaunchedOutbox = await relaunched.outboxMutations()
    expectNoDifference(relaunchedOutbox, [])
  }

  @Test
  func liveValidationRejectionPreservesStructuredServerMetadata() async throws {
    let session = AcceptanceReconnectLiveSession()
    let cacheURL = FileManager.default.temporaryDirectory.appendingPathComponent(
      "instant-message-server-acceptance-structured-rejection-\(UUID().uuidString).sqlite"
    )
    let runtime = try await acceptanceRuntime(
      suffix: "structured-rejection",
      cacheURL: cacheURL,
      liveTransport: session.transport
    )
    _ = try await runtime.connect()
    let client = InstantSwiftDataClient(runtime: runtime)
    let task = Task {
      try await client.sendAwaitingServerAcceptance(
        AwaitedMessage(change: "structured rejection")
      )
    }
    try await waitForAcceptanceMutation(runtime)
    try await waitForAcceptanceMutationSend(
      id: "tx-structured-rejection",
      in: session
    )

    await session.rejectMutation(
      id: "tx-structured-rejection",
      message: "counter compare-and-swap lost",
      status: 409,
      type: "record-not-unique",
      hint: .object(["attribute": .string("recordingTitleSequences/nextValue")]),
      traceID: "trace-structured-rejection",
      originalEventTraceID: "trace-original-transact"
    )

    do {
      _ = try await task.value
      Issue.record("Expected the structured live validation rejection to throw.")
    } catch let error as InstantError {
      expectNoDifference(error.code, .validationFailed)
      expectNoDifference(error.message, "counter compare-and-swap lost")
      expectNoDifference(error.localID, "tx-structured-rejection")
      expectNoDifference(error.serverEventID, nil)
      expectNoDifference(error.serverStatus, 409)
      expectNoDifference(error.serverType, "record-not-unique")
      expectNoDifference(error.serverTraceID, "trace-structured-rejection")
      expectNoDifference(error.serverOriginalEventTraceID, "trace-original-transact")
      expectNoDifference(
        error.serverHint,
        .object(["attribute": .string("recordingTitleSequences/nextValue")])
      )
    }
    let failed = try #require(await runtime.outboxMutations().first)
    expectNoDifference(failed.status, .failed)
    _ = try await runtime.closeConnection()
  }

  @Test
  func reconnectCannotResendWhileAsyncDiscardDispositionIsSuspended() async throws {
    let session = AcceptanceReconnectLiveSession()
    let gate = AcceptanceRejectionDispositionGate()
    let cacheURL = FileManager.default.temporaryDirectory.appendingPathComponent(
      "instant-message-server-acceptance-reconnect-discard-\(UUID().uuidString).sqlite"
    )
    let runtime = try await acceptanceRuntime(
      suffix: "reconnect-discard",
      cacheURL: cacheURL,
      liveTransport: session.transport
    )
    let client = InstantSwiftDataClient(runtime: runtime)
    let task = Task {
      try await client.sendAwaitingServerAcceptance(
        AwaitedMessage(change: "reconnect discard"),
        onServerRejected: { _ in
          await gate.started()
          await gate.waitForRelease()
          return .discard
        }
      )
    }

    try await waitForAcceptanceMutation(runtime)
    _ = try await runtime.failMutation(
      id: "tx-reconnect-discard",
      message: "permission denied during disposition"
    )
    await gate.waitUntilStarted()

    _ = try await runtime.connect()
    await gate.release()

    do {
      _ = try await task.value
      Issue.record("Expected the rejected mutation to throw its server error.")
    } catch let error as InstantError {
      expectNoDifference(error.code, .permissionRejected)
      expectNoDifference(error.localID, "tx-reconnect-discard")
      expectNoDifference(error.message, "permission denied during disposition")
    }
    let sentMessages = await session.sentMessages()
    let outbox = await runtime.outboxMutations()
    expectNoDifference(sentMessages.map(\.op), ["init"])
    expectNoDifference(outbox, [])
    _ = try await runtime.closeConnection()
  }

  @Test
  func explicitRetryCannotRaceAsyncDiscardDisposition() async throws {
    let (client, runtime, _) = try await acceptanceClient("retry-during-disposition")
    let gate = AcceptanceRejectionDispositionGate()
    let task = Task {
      try await client.sendAwaitingServerAcceptance(
        AwaitedMessage(change: "explicit retry discard"),
        onServerRejected: { _ in
          await gate.started()
          await gate.waitForRelease()
          return .discard
        }
      )
    }

    try await waitForAcceptanceMutation(runtime)
    _ = try await runtime.failMutation(
      id: "tx-retry-during-disposition",
      message: "permission denied before explicit retry"
    )
    await gate.waitUntilStarted()

    do {
      _ = try await runtime.retryMutation(id: "tx-retry-during-disposition")
      Issue.record("Expected explicit retry to wait for the rejection disposition.")
    } catch let error as InstantError {
      expectNoDifference(error.code, .validationFailed)
      expectNoDifference(error.localID, "tx-retry-during-disposition")
      #expect(error.message.contains("awaiting a server-rejection disposition"))
    }

    await gate.release()
    await #expect(throws: InstantError.self) {
      _ = try await task.value
    }
    let outbox = await runtime.outboxMutations()
    expectNoDifference(outbox, [])
  }

  @Test
  func publicFailedMutationResolutionCannotRaceAsyncDisposition() async throws {
    let (client, runtime, _) = try await acceptanceClient("public-resolution-disposition")
    let gate = AcceptanceRejectionDispositionGate()
    let id = "tx-public-resolution-disposition"
    let task = Task {
      try await client.sendAwaitingServerAcceptance(
        AwaitedMessage(change: "public resolution disposition"),
        onServerRejected: { _ in
          await gate.started()
          await gate.waitForRelease()
          return .discard
        }
      )
    }

    try await waitForAcceptanceMutation(runtime)
    _ = try await runtime.failMutation(
      id: id,
      message: "permission denied before public resolution"
    )
    await gate.waitUntilStarted()
    let beforeResolution = try await acceptancePersistenceRevisions(runtime)

    do {
      _ = try await client.retryFailedMutation(id: id)
      Issue.record("Expected public failed retry to respect the active disposition owner.")
    } catch let error as InstantError {
      expectNoDifference(error.code, .validationFailed)
      expectNoDifference(error.operation, "retry failed outbox mutation")
      expectNoDifference(error.localID, id)
      expectNoDifference(error.localMutationDisposition, .retainedForRetry)
      #expect(error.message.contains("awaiting a server-rejection disposition"))
    }
    do {
      _ = try await client.discardFailedMutation(id: id)
      Issue.record("Expected public discard to respect the active disposition owner.")
    } catch let error as InstantError {
      expectNoDifference(error.code, .validationFailed)
      expectNoDifference(error.operation, "discard failed outbox mutation")
      expectNoDifference(error.localID, id)
      expectNoDifference(error.localMutationDisposition, .retainedForRetry)
      #expect(error.message.contains("awaiting a server-rejection disposition"))
    }

    let afterRefusedResolution = try await acceptancePersistenceRevisions(runtime)
    expectNoDifference(afterRefusedResolution, beforeResolution)
    let stillFailed = try await client.failedMutations()
    expectNoDifference(stillFailed.map(\.id), [id])
    expectNoDifference(stillFailed.map(\.status), [.failed])

    await gate.release()
    do {
      _ = try await task.value
      Issue.record("Expected the disposition owner to throw the original rejection.")
    } catch let error as InstantError {
      expectNoDifference(error.code, .permissionRejected)
      expectNoDifference(error.localID, id)
      expectNoDifference(error.localMutationDisposition, .discarded)
    }
    let failuresAfterOwnerDiscard = try await client.failedMutations()
    expectNoDifference(failuresAfterOwnerDiscard, [])
  }

  @Test
  func timeoutDoesNotDiscardPendingMutation() async throws {
    let (client, runtime, _) = try await acceptanceClient("timeout")

    do {
      _ = try await client.sendAwaitingServerAcceptance(
        AwaitedMessage(change: "timeout change"),
        timeout: .zero
      )
      Issue.record("Expected acknowledgement wait to time out.")
    } catch let error as InstantError {
      expectNoDifference(error.code, .networkFailed)
      expectNoDifference(error.operation, "send Instant message awaiting server acceptance")
      expectNoDifference(error.localID, "tx-timeout")
      expectNoDifference(error.serverEventID, nil)
    }

    let timedOutPending = await runtime.pendingMutations()
    expectNoDifference(timedOutPending.map(\.id), ["tx-timeout"])
    _ = try await runtime.failMutation(
      id: "tx-timeout",
      message: "test rejection after acknowledgement timeout"
    )
    let retried = try await runtime.retryMutation(id: "tx-timeout")
    expectNoDifference(retried.status, .pending)
  }

  @Test
  func cancellationDoesNotDiscardPendingMutation() async throws {
    let (client, runtime, _) = try await acceptanceClient("cancelled")
    let task = Task {
      try await client.sendAwaitingServerAcceptance(
        AwaitedMessage(change: "cancelled change")
      )
    }
    try await waitForAcceptanceMutation(runtime)

    task.cancel()
    await #expect(throws: CancellationError.self) {
      _ = try await task.value
    }
    let cancelledPending = await runtime.pendingMutations()
    expectNoDifference(cancelledPending.map(\.id), ["tx-cancelled"])
    _ = try await runtime.failMutation(
      id: "tx-cancelled",
      message: "test rejection after acknowledgement cancellation"
    )
    let retried = try await runtime.retryMutation(id: "tx-cancelled")
    expectNoDifference(retried.status, .pending)
  }

  @Test
  func runtimeLessClientFailsBeforeOptimisticTransaction() async throws {
    let probe = RuntimeLessMessageProbe()
    let client = runtimeLessClient(probe: probe)

    do {
      _ = try await client.sendAwaitingServerAcceptance(
        AwaitedMessage(change: "runtime-less")
      )
      Issue.record("Expected the runtime-less client to reject acknowledgement waiting.")
    } catch let error as InstantError {
      expectNoDifference(error.code, .implementationFailed)
      expectNoDifference(error.operation, "send Instant message awaiting server acceptance")
    }
    let transactCount = await probe.transactCount
    expectNoDifference(transactCount, 0)
  }

  @Test
  func manualConfirmationCannotSatisfyServerDurabilityBarrier() async throws {
    let (client, runtime, _) = try await acceptanceClient("wait-manual-confirm")
    try await enqueueAcceptanceMutation(id: "tx-wait-manual-confirm", runtime: runtime)
    _ = try await runtime.confirmMutation(id: "tx-wait-manual-confirm")

    await expectLocalOnlyDurabilityFailure(
      client: client,
      runtime: runtime,
      id: "tx-wait-manual-confirm",
      source: .manual
    )
  }

  @Test
  func localDrainCannotSatisfyServerDurabilityBarrier() async throws {
    let (client, runtime, _) = try await acceptanceClient("wait-local-drain")
    try await enqueueAcceptanceMutation(id: "tx-wait-local-drain", runtime: runtime)
    _ = try await runtime.drainPendingMutationsLocally()

    await expectLocalOnlyDurabilityFailure(
      client: client,
      runtime: runtime,
      id: "tx-wait-local-drain",
      source: .localDrain
    )
  }

  @Test
  func defaultLocalTransportCannotSatisfyServerDurabilityBarrier() async throws {
    let (client, runtime, _) = try await acceptanceClient("wait-local-transport")
    try await enqueueAcceptanceMutation(id: "tx-wait-local-transport", runtime: runtime)
    _ = try await runtime.flushPendingMutations()

    await expectLocalOnlyDurabilityFailure(
      client: client,
      runtime: runtime,
      id: "tx-wait-local-transport",
      source: .localTransport
    )
  }

  @Test
  func publicFailedMutationWrappersRetryAndDiscardThroughAtomicRuntimeGuards() async throws {
    let (client, runtime, _) = try await acceptanceClient("public-failure-wrappers")
    let id = "tx-public-failure-wrappers"
    try await enqueueAcceptanceMutation(id: id, runtime: runtime)
    _ = try await runtime.failMutation(id: id, message: "permission denied for public wrapper")

    let listed = try await client.failedMutations()
    expectNoDifference(listed.map(\.id), [id])
    let retry = try await client.retryFailedMutation(id: id)
    expectNoDifference(retry.mutation.status, .pending)
    expectNoDifference(retry.localStateDisposition, .retainedForRetry)

    do {
      _ = try await client.retryFailedMutation(id: id)
      Issue.record("Expected the failed-only retry wrapper to reject a pending mutation.")
    } catch let error as InstantError {
      expectNoDifference(error.code, .validationFailed)
      expectNoDifference(error.localID, id)
      expectNoDifference(error.localMutationDisposition, .retainedUnknown)
    }
    let pendingAfterRejectedRetry = await runtime.pendingMutations()
    expectNoDifference(pendingAfterRejectedRetry.map(\.id), [id])

    _ = try await runtime.failMutation(id: id, message: "permission denied after public retry")
    let discard = try await client.discardFailedMutation(id: id)
    expectNoDifference(discard.mutation.id, id)
    expectNoDifference(discard.localStateDisposition, .discarded)
    let failedAfterDiscard = try await client.failedMutations()
    expectNoDifference(failedAfterDiscard, [])
  }

  @Test
  func overlappingSameIDRetryReservationsRemainHeldUntilEveryOwnerReleases() async throws {
    let (_, runtime, _) = try await acceptanceClient("retry-reservation-refcount")
    let id = "tx-retry-reservation-refcount"
    try await enqueueAcceptanceMutation(id: id, runtime: runtime)
    _ = try await runtime.failMutation(id: id, message: "retry reservation test failure")
    let gate = AcceptanceRejectionDispositionGate()

    let innerTask = await runtime.withAutomaticMutationRetrySuspended(id: id) {
      let task = Task {
        await runtime.withAutomaticMutationRetrySuspended(id: id) {
          await gate.started()
          await gate.waitForRelease()
        }
      }
      await gate.waitUntilStarted()
      return task
    }

    do {
      _ = try await runtime.retryMutation(id: id)
      Issue.record("Expected the remaining same-ID owner to keep automatic retry suspended.")
    } catch let error as InstantError {
      expectNoDifference(error.code, .validationFailed)
      expectNoDifference(error.localID, id)
      #expect(error.message.contains("awaiting a server-rejection disposition"))
    }

    await gate.release()
    await innerTask.value
    let retried = try await runtime.retryMutation(id: id)
    expectNoDifference(retried.status, .pending)
  }

  @Test
  func legacyInstantErrorWithoutStructuredServerFieldsStillDecodes() throws {
    let data = Data(
      """
      {
        "code": "networkFailed",
        "operation": "legacy mutation delivery",
        "message": "socket closed",
        "recovery": "reconnect"
      }
      """.utf8
    )

    let error = try JSONDecoder().decode(InstantError.self, from: data)

    expectNoDifference(error.code, .networkFailed)
    expectNoDifference(error.serverStatus, nil)
    expectNoDifference(error.serverType, nil)
    expectNoDifference(error.serverHint, nil)
    expectNoDifference(error.serverTraceID, nil)
    expectNoDifference(error.serverOriginalEventTraceID, nil)
    expectNoDifference(error.localMutationDisposition, nil)
  }
}

private struct AwaitedMessage: InstantMessage {
  var change: String
  var counter: MessagePreparationCounter?

  init(change: String, counter: MessagePreparationCounter? = nil) {
    self.change = change
    self.counter = counter
  }

  func prepare(using client: InstantSwiftDataClient) async throws
    -> InstantPreparedMessage<String>
  {
    _ = client
    await counter?.increment()
    return InstantPreparedMessage(change: change) {
      InstantMutation { transactionID, transactionTime in
        [
          .insert(
            InstantTriple(
              entityID: "message-row",
              attributeID: acceptanceAttribute.id,
              value: .string(change),
              txID: transactionID,
              txTime: transactionTime
            )
          )
        ]
      }
    }
  }
}

private actor MessagePreparationCounter {
  private(set) var value = 0

  func increment() {
    value += 1
  }
}

private actor MessageTaskCompletionProbe {
  private(set) var isFinished = false

  func finished() {
    isFinished = true
  }
}

private let acceptanceAttribute = InstantAttribute(
  id: "messageRows/value",
  namespace: "messageRows",
  name: "value",
  valueType: .string
)

private func acceptanceClient(
  _ suffix: String
) async throws -> (InstantSwiftDataClient, InstantRuntime, URL) {
  let cacheURL = acceptanceCacheURL(suffix)
  let runtime = try await acceptanceRuntime(suffix: suffix, cacheURL: cacheURL)
  return (InstantSwiftDataClient(runtime: runtime), runtime, cacheURL)
}

private func acceptanceRuntime(
  suffix: String,
  cacheURL: URL,
  liveTransport: InstantLiveTransportClient? = nil,
  mutationTransport: InstantMutationTransportClient = .local
) async throws -> InstantRuntime {
  var configuration = InstantRuntimeConfiguration(
    appID: "instant-message-server-acceptance-\(suffix)",
    persistenceURL: cacheURL,
    initialAttributes: [acceptanceAttribute],
    now: { InstantTimestamp(milliseconds: 1_700_000_000_000) },
    makeID: { "tx-\(suffix)" },
    mutationTransport: mutationTransport,
    liveTransport: liveTransport
  )
  configuration.autoConnectLiveTransport = false
  return try await InstantRuntime.bootstrap(configuration: configuration)
}

private func acceptanceCacheURL(_ suffix: String) -> URL {
  FileManager.default.temporaryDirectory.appendingPathComponent(
    "instant-message-server-acceptance-\(suffix)-\(UUID().uuidString).sqlite"
  )
}

private struct AcceptancePersistenceRevisions: Equatable {
  var storeRevision: Int64
  var attributeRevision: Int64
  var outboxRevision: Int64
  var queryResultRevision: Int64
}

private func acceptancePersistenceRevisions(
  _ runtime: InstantRuntime
) async throws -> AcceptancePersistenceRevisions {
  let state = try await runtime.persistence.loadState()
  return AcceptancePersistenceRevisions(
    storeRevision: state.storeRevision,
    attributeRevision: state.attributeRevision,
    outboxRevision: state.outboxRevision,
    queryResultRevision: state.queryResultRevision
  )
}

private func enqueueAcceptanceMutation(
  id: String,
  runtime: InstantRuntime
) async throws {
  try await runtime.transact(
    InstantStoreTransaction(
      id: id,
      operations: [
        .insert(
          InstantTriple(
            entityID: "message-row-\(id)",
            attributeID: acceptanceAttribute.id,
            value: .string(id),
            txID: id,
            txTime: InstantTimestamp(milliseconds: 1_700_000_000_001)
          )
        )
      ]
    )
  )
}

private func expectLocalOnlyDurabilityFailure(
  client: InstantSwiftDataClient,
  runtime: InstantRuntime,
  id: String,
  source: InstantMutationConfirmationSource
) async {
  do {
    try await client.waitForAllPendingMutations(timeout: .zero)
    Issue.record("Expected local-only completion '\(source.rawValue)' to fail server durability.")
  } catch let error as InstantError {
    expectNoDifference(error.code, .networkFailed)
    expectNoDifference(error.operation, "wait for pending mutations")
    expectNoDifference(error.localID, id)
    #expect(error.message.contains(source.rawValue))
    #expect(error.message.contains("not by the Instant server"))
  } catch {
    Issue.record("Expected InstantError, received \(String(describing: error)).")
  }

  do {
    let persisted = try await runtime.persistence.loadState().snapshot.outbox
    let proof = persisted.first(where: { $0.id == id })
    expectNoDifference(proof?.status, .confirmed)
    expectNoDifference(proof?.confirmationSource, source)
  } catch {
    Issue.record("Could not inspect retained local confirmation proof: \(error)")
  }
}

private func acceptanceTask(
  client: InstantSwiftDataClient,
  change: String,
  completion: MessageTaskCompletionProbe
) -> Task<String, Error> {
  Task {
    do {
      let change = try await client.sendAwaitingServerAcceptance(
        AwaitedMessage(change: change),
        timeout: .milliseconds(80)
      )
      await completion.finished()
      return change
    } catch {
      await completion.finished()
      throw error
    }
  }
}

private func expectAcceptanceTimeout(_ task: Task<String, Error>, id: String) async {
  do {
    _ = try await task.value
    Issue.record("Expected local confirmation to remain insufficient for server acceptance.")
  } catch let error as InstantError {
    expectNoDifference(error.code, .networkFailed)
    expectNoDifference(error.localID, id)
  } catch {
    Issue.record("Expected InstantError, received \(String(describing: error)).")
  }
}

private func waitForAcceptanceMutation(_ runtime: InstantRuntime) async throws {
  for _ in 0..<5_000 {
    if !(await runtime.pendingMutations()).isEmpty {
      return
    }
    try await Task.sleep(for: .milliseconds(1))
  }
  throw InstantError(
    code: .implementationFailed,
    operation: "wait for acknowledgement test mutation",
    message: "The message mutation was not persisted.",
    recovery: "Inspect the typed message acknowledgement implementation."
  )
}

private func waitForAcceptanceMutationSend(
  id: String,
  in session: AcceptanceReconnectLiveSession
) async throws {
  for _ in 0..<5_000 {
    if await session.sentMessages().contains(where: {
      $0.op == "transact" && $0.clientEventID == id
    }) {
      return
    }
    try await Task.sleep(for: .milliseconds(1))
  }
  throw InstantError(
    code: .implementationFailed,
    operation: "wait for acknowledgement test mutation send",
    message: "The message mutation was not sent within five seconds.",
    recovery: "Inspect automatic live mutation delivery and its durable claim."
  )
}

private actor RuntimeLessMessageProbe {
  private(set) var transactCount = 0

  func transact(_ transaction: InstantStoreTransaction) -> InstantStoreMutationResult {
    transactCount += 1
    return InstantStoreMutationResult(
      transactionID: transaction.id,
      changedEntityIDs: [],
      tripleCount: transaction.operations.count,
      emissions: []
    )
  }
}

private func runtimeLessClient(probe: RuntimeLessMessageProbe) -> InstantSwiftDataClient {
  InstantSwiftDataClient(
    transact: { transaction in await probe.transact(transaction) },
    query: { _ in [] },
    observe: { _ in .finished },
    pendingMutations: { [] },
    flushPendingMutations: { _ in
      InstantMutationTransportFlushResult(
        request: InstantMutationTransportRequest(
          appID: "runtime-less",
          apiURI: InstantRuntimeConfiguration.defaultAPIURI,
          websocketURI: InstantRuntimeConfiguration.defaultWebSocketURI,
          mutations: []
        ),
        results: [],
        confirmed: [],
        failed: [],
        pendingMutationCount: 0,
        mutationCount: 0
      )
    },
    connectionStatus: {
      throw InstantError(
        code: .implementationFailed,
        operation: "runtime-less connection status",
        message: "No runtime.",
        recovery: "Use a runtime-backed client."
      )
    },
    connect: {
      throw InstantError(
        code: .implementationFailed,
        operation: "runtime-less connect",
        message: "No runtime.",
        recovery: "Use a runtime-backed client."
      )
    },
    localID: { $0 }
  )
}

private actor AcceptanceRejectionDispositionGate {
  private var didStart = false
  private var startWaiters: [CheckedContinuation<Void, Never>] = []
  private var releaseWaiters: [CheckedContinuation<Void, Never>] = []

  func started() {
    didStart = true
    let waiters = startWaiters
    startWaiters = []
    for waiter in waiters { waiter.resume() }
  }

  func waitUntilStarted() async {
    guard !didStart else { return }
    await withCheckedContinuation { startWaiters.append($0) }
  }

  func waitForRelease() async {
    await withCheckedContinuation { releaseWaiters.append($0) }
  }

  func release() {
    let waiters = releaseWaiters
    releaseWaiters = []
    for waiter in waiters { waiter.resume() }
  }
}

private actor AcceptanceReconnectLiveSession {
  private struct SentWaiter {
    var count: Int
    var continuation: CheckedContinuation<Void, Never>
  }

  nonisolated private let abortState = InstantLiveTestWireAbortState()
  private var messages: [InstantLiveMessage] = []
  private var receiveContinuation: InstantLiveTestPendingOperation<InstantLiveMessage>?
  private var sent: [InstantLiveMessage] = []
  private var sentWaiters: [SentWaiter] = []
  private var isClosed = false

  nonisolated var transport: InstantLiveTransportClient {
    .immediate { _ in
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
  }

  func sentMessages() -> [InstantLiveMessage] {
    sent
  }

  func rejectMutation(
    id: String,
    message: String,
    status: Int,
    type: String,
    hint: InstantLiveJSONValue,
    traceID: String,
    originalEventTraceID: String
  ) {
    enqueue(
      InstantLiveMessage(
        op: "error",
        clientEventID: id,
        fields: [
          "hint": hint,
          "message": .string(message),
          "original-event": .object([
            "client-event-id": .string(id),
            "op": .string("transact"),
            "trace-id": .string(originalEventTraceID),
          ]),
          "status": .number(Double(status)),
          "trace-id": .string(traceID),
          "type": .string(type),
        ]
      )
    )
  }

  func acceptMutation(id: String, serverTransactionID: String) {
    enqueue(
      InstantLiveMessage(
        op: "transact-ok",
        clientEventID: id,
        fields: ["tx-id": .string(serverTransactionID)]
      )
    )
  }

  private func send(_ message: InstantLiveMessage) throws {
    try abortState.check()
    sent.append(message)
    if message.op == "init" {
      enqueue(
        InstantLiveMessage(
          op: "init-ok",
          clientEventID: message.clientEventID,
          fields: [
            "attrs": .array([]),
            "auth": .null,
            "session-id": .string("acceptance-reconnect-session"),
          ]
        )
      )
    }
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

  private func enqueue(_ message: InstantLiveMessage) {
    guard !abortState.isAborted else { return }
    if let receiveContinuation {
      self.receiveContinuation = nil
      abortState.unregister(receiveContinuation.abortToken)
      receiveContinuation.continuation.resume(returning: message)
    } else if !isClosed {
      messages.append(message)
    }
  }

  private func receive() async throws -> InstantLiveMessage {
    try abortState.check()
    if !messages.isEmpty {
      return messages.removeFirst()
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
