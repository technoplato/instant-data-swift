import CustomDump
import Foundation
import IssueReporting
import Testing
@testable import InstantSwiftDataCore

/// Regression coverage for the 2026-08-01 Scribe field failure, reconstructed
/// from a device outbox that held 691 pending mutations and one `failed`
/// mutation whose stored message read:
///
///     Could not resolve 'recordingAttachments/analysisCaptureContextJSON'
///     from the attrs returned by init-ok.
///
/// The device kept recording, so local writes stayed durable, but nothing
/// reached the server for two days and the stored connection state ended at
/// `errored`. These tests pin the three behaviors that failure required.
@Suite(.serialized)
struct InstantOutboxDeliveryStallTests {
  /// Upstream Reactor registers a one-shot query before reconnecting, so
  /// `_flushPendingMessages` sends its `add-query` before persisted mutations.
  /// Swift previously connected first and registered the query afterward,
  /// allowing a deep device outbox to consume the socket until query timeout.
  @Test
  func queryThatInitiatesReconnectPrecedesPersistedMutations() async throws {
    let cacheURL = try temporaryOutboxStallCacheURL()
    let createdAt = InstantTimestamp(milliseconds: 1_700_000_039_000)
    let seedRuntime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "outbox-stall-query-priority",
        persistenceURL: cacheURL,
        initialAttributes: TodoExample.attributes
      )
    )
    try await seedRuntime.transact(
      InstantStoreTransaction(
        id: "tx-outbox-query-priority",
        operations: TodoExample.createOperations(
          id: "todo-outbox-query-priority",
          text: "persisted before reconnect",
          createdAt: createdAt,
          transactionID: "tx-outbox-query-priority"
        )
      ),
      createdAt: createdAt
    )

    let plan = InstantQueryPlan(
      id: "outbox-stall.query-priority",
      namespace: TodoExample.namespace
    )
    let query = try InstantLiveQueryEncoder.encode(plan)
    let liveSession = LiveReactorParitySession(messages: [
      liveReactorInitOK(attrs: liveReactorTodoServerAttrs),
      liveReactorAddQueryOK(
        query: query,
        processedTransactionID: "0",
        result: []
      ),
    ])
    let reconnectGate = OutboxReconnectTransportGate(session: liveSession)
    var configuration = InstantRuntimeConfiguration(
      appID: "outbox-stall-query-priority",
      persistenceURL: cacheURL,
      initialAttributes: TodoExample.attributes,
      liveTransport: reconnectGate.transport
    )
    configuration.autoConnectLiveTransport = true
    let runtime = try await InstantRuntime.bootstrap(configuration: configuration)

    await reconnectGate.waitForConnectionAttempt()
    let queryTask = Task { try await runtime.queryOnce(plan) }
    defer { queryTask.cancel() }
    // The transport remains suspended while the query task registers its
    // intent. Yielding lets that task reach the reentrant live-session actor
    // without introducing a wall-clock race.
    for _ in 0..<100 {
      await Task.yield()
    }
    await reconnectGate.release()
    _ = try await queryTask.value
    try await instantLiveWithTimeout(
      operation: "wait for persisted mutation after query-priority reconnect",
      timeoutMilliseconds: 5_000
    ) {
      while !Task.isCancelled {
        let sent = await liveSession.sentMessages()
        if sent.contains(where: { $0.op == "transact" }) { return }
        await Task.yield()
      }
      throw CancellationError()
    }

    let sent = await liveSession.sentMessages()
    let addQueryIndex = try #require(sent.firstIndex { $0.op == "add-query" })
    let transactIndex = try #require(sent.firstIndex { $0.op == "transact" })
    #expect(
      addQueryIndex < transactIndex,
      "A reconnecting query must be sent before the persisted outbox: \(sent.map(\.op))"
    )
  }

  /// A mutation naming an attribute the server never received must not stop
  /// the mutations queued behind it. Before the fix a schema-drifted write
  /// could hold an entire backlog indefinitely.
  @Test
  func undeliverableMutationDoesNotBlockLaterMutations() async throws {
    let cacheURL = try temporaryOutboxStallCacheURL()
    let createdAt = InstantTimestamp(milliseconds: 1_700_000_040_000)
    let liveSession = LiveReactorParitySession(messages: [
      liveReactorInitOK(attrs: liveReactorTodoServerAttrs)
    ])
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "outbox-stall-drift",
        persistenceURL: cacheURL,
        initialAttributes: TodoExample.attributes,
        liveTransport: liveSession.transport
      )
    )

    // Queued first, so an ordered flush reaches it before the healthy writes.
    try await runtime.transact(
      InstantStoreTransaction(
        id: "tx-outbox-stall-poison",
        operations: [
          .insert(
            InstantTriple(
              entityID: "todo-outbox-stall-poison",
              attributeID: "todos/attributeTheServerNeverReceived",
              value: .string("drifted"),
              txID: "tx-outbox-stall-poison",
              txTime: createdAt
            )
          )
        ]
      ),
      createdAt: createdAt
    )

    for index in 0..<3 {
      let queuedAt = InstantTimestamp(milliseconds: createdAt.milliseconds + Int64(index + 1))
      try await runtime.transact(
        InstantStoreTransaction(
          id: "tx-outbox-stall-healthy-\(index)",
          operations: TodoExample.createOperations(
            id: "todo-outbox-stall-\(index)",
            text: "queued behind the drifted write",
            createdAt: queuedAt,
            transactionID: "tx-outbox-stall-healthy-\(index)"
          )
        ),
        createdAt: queuedAt
      )
    }

    // The quarantine is reported to the developer, which is the point: this
    // failure was previously invisible until a device database was inspected.
    try await withKnownIssue {
      _ = try await runtime.connect()
      try? await Task.sleep(nanoseconds: 300_000_000)
    } matching: { issue in
      issue.description.contains("quarantined")
        || issue.description.contains("attributeTheServerNeverReceived")
    }

    let transactedEventIDs = await liveSession.sentMessages()
      .filter { $0.op == "transact" }
      .compactMap(\.clientEventID)
    expectNoDifference(
      transactedEventIDs.contains("tx-outbox-stall-poison"),
      false,
      outboxStallSource
    )
    for index in 0..<3 {
      expectNoDifference(
        transactedEventIDs.contains("tx-outbox-stall-healthy-\(index)"),
        true,
        outboxStallSource
      )
    }
  }

  /// A backlog is flushed in bounded batches. The field failure sent every
  /// queued mutation in a single burst, which starved the session's own
  /// queries until they hit the 10s transport timeout and closed the
  /// connection, so the backlog could never shrink.
  @Test
  func deepBacklogIsFlushedInBoundedBatches() async throws {
    let cacheURL = try temporaryOutboxStallCacheURL()
    let createdAt = InstantTimestamp(milliseconds: 1_700_000_050_000)
    let liveSession = LiveReactorParitySession(messages: [
      liveReactorInitOK(attrs: liveReactorTodoServerAttrs)
    ])
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "outbox-stall-batching",
        persistenceURL: cacheURL,
        initialAttributes: TodoExample.attributes,
        liveTransport: liveSession.transport
      )
    )

    let backlogCount = InstantRuntimeLiveSessionLimits.maximumMutationsPerFlush + 20
    for index in 0..<backlogCount {
      let queuedAt = InstantTimestamp(milliseconds: createdAt.milliseconds + Int64(index))
      try await runtime.transact(
        InstantStoreTransaction(
          id: "tx-outbox-backlog-\(index)",
          operations: TodoExample.createOperations(
            id: "todo-outbox-backlog-\(index)",
            text: "backlog \(index)",
            createdAt: queuedAt,
            transactionID: "tx-outbox-backlog-\(index)"
          )
        ),
        createdAt: queuedAt
      )
    }

    let sentBeforeConnect = await liveSession.sentMessages()
      .filter { $0.op == "transact" }
      .count
    expectNoDifference(sentBeforeConnect, 0, outboxStallSource)

    _ = try await runtime.connect()
    try await instantLiveWithTimeout(
      operation: "wait for the first bounded backlog delivery window",
      timeoutMilliseconds: 5_000
    ) {
      await liveSession.waitForSentMessageCount(
        InstantRuntimeLiveSessionLimits.maximumMutationsPerFlush + 1
      )
    }
    // One flush pass, before any acknowledgement can arrive.
    let firstPass = await liveSession.sentMessages()
      .filter { $0.op == "transact" }
      .count
    #expect(
      firstPass <= InstantRuntimeLiveSessionLimits.maximumMutationsPerFlush,
      "One flush pass must stay bounded; sent \(firstPass)"
    )
    #expect(firstPass > 0, "A bounded flush must still make progress")
  }

  /// Count-only batching is insufficient because one Scribe mutation can
  /// contain hundreds of low-level tx steps. Keep one bounded operation
  /// window in flight, then refill it only after server acknowledgements.
  @Test
  func weightedBacklogRefillsAfterAcknowledgements() async throws {
    let cacheURL = try temporaryOutboxStallCacheURL()
    let createdAt = InstantTimestamp(milliseconds: 1_700_000_055_000)
    let liveSession = LiveReactorParitySession(messages: [
      liveReactorInitOK(attrs: liveReactorTodoServerAttrs)
    ])
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "outbox-stall-weighted-batching",
        persistenceURL: cacheURL,
        initialAttributes: TodoExample.attributes,
        liveTransport: liveSession.transport
      )
    )

    let todosPerMutation =
      InstantRuntimeLiveSessionLimits.maximumTransactionStepsInFlight / 4
    for mutationIndex in 0..<3 {
      let transactionID = "tx-outbox-weighted-\(mutationIndex)"
      let operations = (0..<todosPerMutation).flatMap { todoIndex in
        TodoExample.createOperations(
          id: "todo-outbox-weighted-\(mutationIndex)-\(todoIndex)",
          text: "weighted backlog",
          createdAt: InstantTimestamp(
            milliseconds: createdAt.milliseconds + Int64(mutationIndex)
          ),
          transactionID: transactionID
        )
      }
      try await runtime.transact(
        InstantStoreTransaction(id: transactionID, operations: operations),
        createdAt: InstantTimestamp(
          milliseconds: createdAt.milliseconds + Int64(mutationIndex)
        )
      )
    }
    let transportStepCounts = await runtime.outboxTransportMutations()
      .map { $0.txSteps.count }
    expectNoDifference(
      transportStepCounts,
      Array(repeating: InstantRuntimeLiveSessionLimits.maximumTransactionStepsInFlight, count: 3),
      outboxStallSource
    )

    _ = try await runtime.connect()
    try await instantLiveWithTimeout(
      operation: "wait for the first weighted backlog mutation",
      timeoutMilliseconds: 5_000
    ) {
      await liveSession.waitForSentMessageCount(2)
    }
    var sentTransactionIDs = await liveSession.sentMessages()
      .filter { $0.op == "transact" }
      .compactMap(\.clientEventID)
    expectNoDifference(sentTransactionIDs, ["tx-outbox-weighted-0"], outboxStallSource)

    await liveSession.enqueue(
      InstantLiveMessage(
        op: "transact-ok",
        clientEventID: "tx-outbox-weighted-0",
        fields: ["tx-id": .string("server-tx-outbox-weighted-0")]
      )
    )
    try await instantLiveWithTimeout(
      operation: "wait for the second weighted backlog mutation",
      timeoutMilliseconds: 5_000
    ) {
      await liveSession.waitForSentMessageCount(3)
    }
    sentTransactionIDs = await liveSession.sentMessages()
      .filter { $0.op == "transact" }
      .compactMap(\.clientEventID)
    expectNoDifference(
      sentTransactionIDs,
      ["tx-outbox-weighted-0", "tx-outbox-weighted-1"],
      outboxStallSource
    )

    await liveSession.enqueue(
      InstantLiveMessage(
        op: "transact-ok",
        clientEventID: "tx-outbox-weighted-1",
        fields: ["tx-id": .string("server-tx-outbox-weighted-1")]
      )
    )
    try await instantLiveWithTimeout(
      operation: "wait for the third weighted backlog mutation",
      timeoutMilliseconds: 5_000
    ) {
      await liveSession.waitForSentMessageCount(4)
    }
    sentTransactionIDs = await liveSession.sentMessages()
      .filter { $0.op == "transact" }
      .compactMap(\.clientEventID)
    expectNoDifference(
      sentTransactionIDs,
      [
        "tx-outbox-weighted-0",
        "tx-outbox-weighted-1",
        "tx-outbox-weighted-2",
      ],
      outboxStallSource
    )
  }

  /// A fast server can acknowledge while URLSession's async send is still
  /// suspended. The acknowledgement must clear the whole reservation rather
  /// than letting the resumed sender recreate stale weight and timeout state.
  @Test
  func acknowledgementBeforeSendReturnsClearsTheWholeReservation() async throws {
    let liveSession = ImmediateAckBeforeSendReturnSession()
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "outbox-stall-reentrant-ack",
        persistenceURL: try temporaryOutboxStallCacheURL(),
        initialAttributes: TodoExample.attributes,
        liveTransport: liveSession.transport
      )
    )
    _ = try await runtime.connect()

    let createdAt = InstantTimestamp(milliseconds: 1_700_000_057_000)
    let transactTask = Task {
      try await runtime.transact(
        InstantStoreTransaction(
          id: "tx-outbox-reentrant-ack",
          operations: TodoExample.createOperations(
            id: "todo-outbox-reentrant-ack",
            text: "acknowledged before send returns",
            createdAt: createdAt,
            transactionID: "tx-outbox-reentrant-ack"
          )
        ),
        createdAt: createdAt
      )
    }
    defer {
      transactTask.cancel()
      Task { await liveSession.releaseTransactSend() }
    }

    await liveSession.waitForBlockedTransactSend()
    try await instantLiveWithTimeout(
      operation: "wait for reentrant transaction acknowledgement",
      timeoutMilliseconds: 500
    ) {
      while !Task.isCancelled {
        if await runtime.pendingMutations().isEmpty {
          return
        }
        await Task.yield()
      }
      throw CancellationError()
    }
    await liveSession.releaseTransactSend()
    _ = try await transactTask.value

    let reservations = await runtime.liveMutationReservationCountsForTesting()
    expectNoDifference(reservations.ids, 0, outboxStallSource)
    expectNoDifference(reservations.stepCounts, 0, outboxStallSource)
    expectNoDifference(reservations.deadlines, 0, outboxStallSource)
  }

  /// A mutation quarantined because the server was missing a schema attribute
  /// must deliver once that attribute is deployed. The field devices held 463
  /// and 1 such mutations that no reconnect would ever have retried.
  @Test
  func quarantinedMutationDeliversAfterTheSchemaIsDeployed() async throws {
    let cacheURL = try temporaryOutboxStallCacheURL()
    let createdAt = InstantTimestamp(milliseconds: 1_700_000_060_000)
    let driftedAttribute = "todos/deployedLater"
    let driftedSession = LiveReactorParitySession(messages: [
      liveReactorInitOK(attrs: liveReactorTodoServerAttrs)
    ])
    let driftedRuntime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "outbox-stall-recovery",
        persistenceURL: cacheURL,
        initialAttributes: TodoExample.attributes,
        liveTransport: driftedSession.transport
      )
    )
    try await driftedRuntime.transact(
      InstantStoreTransaction(
        id: "tx-outbox-recovery",
        operations: [
          .insert(
            InstantTriple(
              entityID: "todo-outbox-recovery",
              attributeID: driftedAttribute,
              value: .string("queued before the deployment"),
              txID: "tx-outbox-recovery",
              txTime: createdAt
            )
          )
        ]
      ),
      createdAt: createdAt
    )
    try await withKnownIssue {
      _ = try await driftedRuntime.connect()
      try? await Task.sleep(nanoseconds: 200_000_000)
    } matching: { issue in
      issue.description.contains("quarantined")
    }
    let quarantinedSends = await driftedSession.sentMessages()
      .filter { $0.op == "transact" }
      .count
    expectNoDifference(quarantinedSends, 0, outboxStallSource)

    // The schema is deployed, then the app relaunches against the same store.
    let deployedAttrs =
      liveReactorTodoServerAttrs + [
        .object([
          "cardinality": .string("one"),
          "forward-identity": .array([
            .string("identity-server-todos-deployed-later"),
            .string(TodoExample.namespace),
            .string("deployedLater"),
          ]),
          "id": .string("server-todos-deployed-later"),
          "unique?": .bool(false),
          "value-type": .string("string"),
        ])
      ]
    let deployedSession = LiveReactorParitySession(messages: [
      liveReactorInitOK(attrs: deployedAttrs)
    ])
    let deployedRuntime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "outbox-stall-recovery",
        persistenceURL: cacheURL,
        initialAttributes: TodoExample.attributes,
        liveTransport: deployedSession.transport
      )
    )
    _ = try await deployedRuntime.connect()
    try? await Task.sleep(nanoseconds: 200_000_000)

    let recoveredEventIDs = await deployedSession.sentMessages()
      .filter { $0.op == "transact" }
      .compactMap(\.clientEventID)
    expectNoDifference(
      recoveredEventIDs.contains("tx-outbox-recovery"),
      true,
      outboxStallSource
    )
  }

  /// The 2026-08-02 upgrade failure. A device that upgraded to the
  /// acknowledgement release still carried `failed` rows written by an earlier
  /// version, so those rows have neither a Runtime receipt nor a trustworthy
  /// rollback. Continuing delivery would make later server truth authoritative
  /// over a local layer whose ownership cannot be reconstructed. The upgraded
  /// Runtime must retain both rows, expose one manual-recovery blocker, and stop
  /// before any wire send or reconnect loop.
  @Test
  func legacyUnknownFailedMutationBlocksLiveConnectWithoutSendingOrReconnecting() async throws {
    let cacheURL = try temporaryOutboxStallCacheURL()
    let createdAt = InstantTimestamp(milliseconds: 1_700_000_060_000)
    let seedRuntime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "outbox-stall-legacy-unknown",
        persistenceURL: cacheURL,
        initialAttributes: TodoExample.attributes
      )
    )
    try await seedRuntime.transact(
      InstantStoreTransaction(
        id: "tx-outbox-legacy-unknown",
        operations: TodoExample.createOperations(
          id: "todo-outbox-legacy-unknown",
          text: "written by an earlier release",
          createdAt: createdAt,
          transactionID: "tx-outbox-legacy-unknown"
        )
      ),
      createdAt: createdAt
    )
    let queuedAt = InstantTimestamp(milliseconds: createdAt.milliseconds + 1)
    try await seedRuntime.transact(
      InstantStoreTransaction(
        id: "tx-outbox-after-legacy",
        operations: TodoExample.createOperations(
          id: "todo-outbox-after-legacy",
          text: "queued behind the legacy row",
          createdAt: queuedAt,
          transactionID: "tx-outbox-after-legacy"
        )
      ),
      createdAt: queuedAt
    )
    // Exactly the shape an upgraded device carries: failed, deploy-fixable
    // message, and no durable optimistic-overlay or rollback metadata.
    _ = try await seedRuntime.rewriteResidentPersistenceSnapshotForTesting(
      name: "outbox-stall-legacy-unknown"
    ) { snapshot in
      var snapshot = snapshot
      guard
        let index = snapshot.outbox.firstIndex(where: { $0.id == "tx-outbox-legacy-unknown" })
      else { return snapshot }
      snapshot.outbox[index].status = .failed
      snapshot.outbox[index].failureMessage =
        "Could not resolve 'todos/attributeTheServerNeverReceived' from the attrs returned by init-ok."
      snapshot.outbox[index].rollbackTransaction = nil
      snapshot.outbox[index].optimisticOverlayState = nil
      return snapshot
    }

    let liveSession = LiveReactorParitySession(messages: [
      liveReactorInitOK(attrs: liveReactorTodoServerAttrs)
    ])
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "outbox-stall-legacy-unknown",
        persistenceURL: cacheURL,
        initialAttributes: TodoExample.attributes,
        liveTransport: liveSession.transport
      )
    )

    do {
      _ = try await runtime.connect()
      Issue.record("Expected the unknown durable effect to block the live connection.")
    } catch let error as InstantError {
      expectNoDifference(error.code, .persistenceFailed, outboxStallSource)
      expectNoDifference(error.operation, "open Instant live connection", outboxStallSource)
      expectNoDifference(error.localID, "tx-outbox-legacy-unknown", outboxStallSource)
      expectNoDifference(error.localMutationDisposition, .retainedUnknown, outboxStallSource)
    }

    let sentMessages = await liveSession.sentMessages()
    expectNoDifference(sentMessages, [], outboxStallSource)
    let status = try await runtime.connectionStatus()
    expectNoDifference(status.state, .errored, outboxStallSource)
    expectNoDifference(
      status.synchronizationBlocker,
      InstantSynchronizationBlocker(
        reason: .unknownOptimisticEffectReceipt,
        firstMutationID: "tx-outbox-legacy-unknown",
        blockedMutationCount: 1
      ),
      outboxStallSource
    )
    let mutationPumpIsSuspended = await runtime.automaticMutationPumpIsSuspendedForTesting()
    expectNoDifference(mutationPumpIsSuspended, true, outboxStallSource)
    let reconnectControllerIsIdle = await runtime.liveReconnectControllerIsIdleForTesting()
    expectNoDifference(reconnectControllerIsIdle, true, outboxStallSource)

    let outbox = try await runtime.persistence.loadState().snapshot.outbox
    let legacy = try #require(outbox.first { $0.id == "tx-outbox-legacy-unknown" })
    expectNoDifference(legacy.status, .failed, outboxStallSource)
    expectNoDifference(legacy.optimisticOverlayState == nil, true, outboxStallSource)
    let successor = try #require(outbox.first { $0.id == "tx-outbox-after-legacy" })
    expectNoDifference(successor.status, .pending, outboxStallSource)
  }

  /// A live observation must hit the same blocker before registering a query or
  /// accepting a refresh. This keeps the unknown local owner and server result
  /// from being combined into a store that neither side can later reconstruct.
  @Test
  func legacyUnknownFailedMutationBlocksLiveObservationBeforeServerApply() async throws {
    let cacheURL = try temporaryOutboxStallCacheURL()
    let createdAt = InstantTimestamp(milliseconds: 1_700_000_061_000)
    let seedRuntime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "outbox-stall-legacy-apply",
        persistenceURL: cacheURL,
        initialAttributes: TodoExample.attributes
      )
    )
    try await seedRuntime.transact(
      InstantStoreTransaction(
        id: "tx-outbox-legacy-apply-poison",
        operations: TodoExample.createOperations(
          id: "todo-outbox-legacy-apply-poison",
          text: "failed legacy row that must not freeze apply",
          createdAt: createdAt,
          transactionID: "tx-outbox-legacy-apply-poison"
        )
      ),
      createdAt: createdAt
    )
    _ = try await seedRuntime.rewriteResidentPersistenceSnapshotForTesting(
      name: "outbox-stall-legacy-apply"
    ) { snapshot in
      var snapshot = snapshot
      guard
        let index = snapshot.outbox.firstIndex(where: {
          $0.id == "tx-outbox-legacy-apply-poison"
        })
      else { return snapshot }
      snapshot.outbox[index].status = .failed
      snapshot.outbox[index].failureMessage =
        "Validation failed for tx-step: Creating entities that exist: todo-outbox-legacy-apply-poison"
      snapshot.outbox[index].rollbackTransaction = nil
      snapshot.outbox[index].optimisticOverlayState = nil
      return snapshot
    }

    let liveSession = LiveReactorParitySession(messages: [
      liveReactorInitOK(
        attrs: liveReactorTodoServerAttrs,
        sessionID: "legacy-apply-isolation"
      )
    ])
    var configuration = InstantRuntimeConfiguration(
      appID: "outbox-stall-legacy-apply",
      persistenceURL: cacheURL,
      initialAttributes: TodoExample.attributes,
      liveTransport: liveSession.transport
    )
    configuration.liveReconnectSleep = { _ in }
    configuration.autoConnectLiveTransport = false
    let runtime = try await InstantRuntime.bootstrap(configuration: configuration)
    let plan = TodoExample.query
    let stream = await runtime.observe(plan)
    var iterator = stream.makeAsyncIterator()
    _ = try #require(await iterator.next())

    do {
      _ = try await runtime.connect()
      Issue.record("Expected the unknown durable effect to block live observation.")
    } catch let error as InstantError {
      expectNoDifference(error.localID, "tx-outbox-legacy-apply-poison", outboxStallSource)
      expectNoDifference(error.localMutationDisposition, .retainedUnknown, outboxStallSource)
    }
    let sentMessages = await liveSession.sentMessages()
    expectNoDifference(sentMessages, [], outboxStallSource)
    let status = try await runtime.connectionStatus()
    expectNoDifference(
      status.synchronizationBlocker?.firstMutationID,
      "tx-outbox-legacy-apply-poison",
      outboxStallSource
    )
    let reconnectControllerIsIdle = await runtime.liveReconnectControllerIsIdleForTesting()
    expectNoDifference(reconnectControllerIsIdle, true, outboxStallSource)

    let persisted = try await runtime.persistence.loadState().snapshot
    let outbox = persisted.outbox
    let legacy = try #require(outbox.first { $0.id == "tx-outbox-legacy-apply-poison" })
    expectNoDifference(legacy.status, .failed, outboxStallSource)
    expectNoDifference(legacy.optimisticOverlayState == nil, true, outboxStallSource)
    #expect(!persisted.store.triples.contains { $0.entityID == "todo-server-after-legacy" })
  }

  /// Explicit server apply matches connection preflight: it fails before
  /// changing the hot or durable store and retains the unknown owner verbatim.
  @Test
  func legacyUnknownFailedMutationBlocksExplicitServerApplyAtomically() async throws {
    let cacheURL = try temporaryOutboxStallCacheURL()
    let baseTime = InstantTimestamp(milliseconds: 1_700_000_062_000)
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "outbox-stall-legacy-explicit-apply",
        persistenceURL: cacheURL,
        initialAttributes: TodoExample.attributes
      )
    )
    try await runtime.transact(
      InstantStoreTransaction(
        id: "tx-legacy-explicit-poison",
        operations: TodoExample.createOperations(
          id: "todo-legacy-explicit-poison",
          text: "poison",
          createdAt: baseTime,
          transactionID: "tx-legacy-explicit-poison"
        )
      ),
      createdAt: baseTime
    )
    _ = try await runtime.rewriteResidentPersistenceSnapshotForTesting(
      name: "outbox-stall-legacy-explicit-apply"
    ) { snapshot in
      var snapshot = snapshot
      guard
        let index = snapshot.outbox.firstIndex(where: { $0.id == "tx-legacy-explicit-poison" })
      else { return snapshot }
      snapshot.outbox[index].status = .failed
      snapshot.outbox[index].failureMessage = "legacy unknown failure"
      snapshot.outbox[index].rollbackTransaction = nil
      snapshot.outbox[index].optimisticOverlayState = nil
      return snapshot
    }

    let before = try await runtime.persistence.loadState().snapshot
    var caughtError: InstantError?
    try await withKnownIssue {
      do {
        _ = try await runtime.applyServerTransaction(
          InstantStoreTransaction(
            id: "server-tx-explicit-over-legacy",
            operations: TodoExample.upsertOperations(
              id: "todo-server-explicit",
              text: "server truth after isolation",
              createdAt: InstantTimestamp(milliseconds: baseTime.milliseconds + 1_000),
              transactionID: "server-tx-explicit-over-legacy"
            )
          )
        )
        Issue.record("Expected unknown receipt to block explicit server apply.")
      } catch let error as InstantError {
        caughtError = error
      }
    } matching: { issue in
      issue.description.contains("tx-legacy-explicit-poison")
        && issue.description.contains("apply server transaction")
    }
    let error = try #require(caughtError)
    expectNoDifference(error.code, .persistenceFailed, outboxStallSource)
    expectNoDifference(error.localID, "tx-legacy-explicit-poison", outboxStallSource)
    expectNoDifference(error.localMutationDisposition, .retainedUnknown, outboxStallSource)

    let after = try await runtime.persistence.loadState().snapshot
    expectNoDifference(after, before, outboxStallSource)
    let legacy = try #require(after.outbox.first { $0.id == "tx-legacy-explicit-poison" })
    expectNoDifference(legacy.status, .failed, outboxStallSource)
  }
}

/// Mirrors the private tuning constants so the test fails loudly if they move.
enum InstantRuntimeLiveSessionLimits {
  static let maximumMutationsPerFlush = 50
  static let maximumTransactionStepsInFlight = 256
  static let inFlightMutationTimeoutSeconds = 10
}

private let outboxStallSource = "Scribe field failure 2026-08-01: device outbox stall"

private func temporaryOutboxStallCacheURL() throws -> URL {
  let directory = FileManager.default.temporaryDirectory
    .appendingPathComponent("InstantOutboxDeliveryStallTests-\(UUID().uuidString)")
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  return directory.appendingPathComponent("state.sqlite")
}

private actor OutboxReconnectTransportGate {
  private let session: LiveReactorParitySession
  private var connectionAttempted = false
  private var connectionWaiters: [CheckedContinuation<Void, Never>] = []
  private var isReleased = false
  private var pendingConnections: [InstantLiveTestConnectionContinuation] = []

  init(session: LiveReactorParitySession) {
    self.session = session
  }

  nonisolated var transport: InstantLiveTransportClient {
    .connectionAttempts { _ in
      let connection = InstantLiveTestConnectionContinuation()
      return InstantLiveConnectionAttempt(
        connect: {
          Task { await self.beginConnection(connection) }
          return try await connection.connect()
        },
        abort: { connection.abort() }
      )
    }
  }

  func waitForConnectionAttempt() async {
    guard !connectionAttempted else { return }
    await withCheckedContinuation { continuation in
      connectionWaiters.append(continuation)
    }
  }

  func release() {
    isReleased = true
    let connections = pendingConnections
    pendingConnections.removeAll()
    for connection in connections {
      connection.succeed(session.webSocketSession)
    }
  }

  private func beginConnection(_ connection: InstantLiveTestConnectionContinuation) {
    connectionAttempted = true
    let waiters = connectionWaiters
    connectionWaiters.removeAll()
    for waiter in waiters {
      waiter.resume()
    }
    if isReleased {
      connection.succeed(session.webSocketSession)
    } else {
      pendingConnections.append(connection)
    }
  }
}

private actor ImmediateAckBeforeSendReturnSession {
  nonisolated private let abortState = InstantLiveTestWireAbortState()
  private var messages = [
    liveReactorInitOK(
      attrs: liveReactorTodoServerAttrs,
      sessionID: "outbox-reentrant-ack"
    )
  ]
  private var receiveContinuation: InstantLiveTestPendingOperation<InstantLiveMessage>?
  private var blockedTransactSend = false
  private var blockedSendWaiters: [CheckedContinuation<Void, Never>] = []
  private var releaseTransactSendContinuation: InstantLiveTestPendingOperation<Void>?
  private var isTransactSendReleased = false
  private var isClosed = false

  nonisolated var transport: InstantLiveTransportClient {
    .immediate { _ in self.webSocketSession }
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

  func waitForBlockedTransactSend() async {
    guard !blockedTransactSend else { return }
    await withCheckedContinuation { continuation in
      blockedSendWaiters.append(continuation)
    }
  }

  func releaseTransactSend() {
    isTransactSendReleased = true
    if let releaseTransactSendContinuation {
      abortState.unregister(releaseTransactSendContinuation.abortToken)
      releaseTransactSendContinuation.continuation.resume(returning: ())
    }
    releaseTransactSendContinuation = nil
  }

  private func send(_ message: InstantLiveMessage) async throws {
    try abortState.check()
    guard message.op == "transact" else { return }
    let clientEventID = try #require(message.clientEventID)
    enqueue(
      InstantLiveMessage(
        op: "transact-ok",
        clientEventID: clientEventID,
        fields: ["tx-id": .string("server-\(clientEventID)")]
      )
    )
    blockedTransactSend = true
    let waiters = blockedSendWaiters
    blockedSendWaiters.removeAll()
    for waiter in waiters {
      waiter.resume()
    }
    if !isTransactSendReleased {
      let id = UUID()
      defer { clearTransactSendContinuation(id: id) }
      try await withCheckedThrowingContinuation {
        (continuation: CheckedContinuation<Void, Error>) in
        let continuation = InstantLiveTestThrowingContinuationBox(continuation)
        guard
          let abortToken = abortState.register({
            continuation.resume(throwing: CancellationError())
          })
        else {
          continuation.resume(throwing: CancellationError())
          return
        }
        releaseTransactSendContinuation = InstantLiveTestPendingOperation(
          id: id,
          abortToken: abortToken,
          continuation: continuation
        )
      }
    }
    try abortState.check()
    try Task.checkCancellation()
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

  private func enqueue(_ message: InstantLiveMessage) {
    guard !abortState.isAborted else { return }
    if let receiveContinuation {
      self.receiveContinuation = nil
      abortState.unregister(receiveContinuation.abortToken)
      receiveContinuation.continuation.resume(returning: message)
    } else {
      messages.append(message)
    }
  }

  private func close() {
    isClosed = true
    abortState.abort()
    receiveContinuation = nil
    releaseTransactSendContinuation = nil
  }

  private func clearReceiveContinuation(id: UUID) {
    guard let receiveContinuation, receiveContinuation.id == id else { return }
    abortState.unregister(receiveContinuation.abortToken)
    self.receiveContinuation = nil
  }

  private func clearTransactSendContinuation(id: UUID) {
    guard let releaseTransactSendContinuation, releaseTransactSendContinuation.id == id else {
      return
    }
    abortState.unregister(releaseTransactSendContinuation.abortToken)
    self.releaseTransactSendContinuation = nil
  }
}
