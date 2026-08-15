import CustomDump
import Foundation
import InstantSwiftData
import Testing

@Suite(.serialized)
struct MutationDeliveryTests {
  @Test
  func synchronizationBlockerRoundTripsAndLegacyConnectionStatusDecodesWithoutIt()
    throws
  {
    let blocker = InstantSynchronizationBlocker(
      reason: .unknownOptimisticEffectReceipt,
      firstMutationID: "tx-unknown-receipt-first",
      blockedMutationCount: 3
    )
    let status = InstantConnectionStatus(
      appID: "synchronization-blocker-codable",
      apiURI: URL(string: "https://api.instantdb.com")!,
      websocketURI: URL(string: "wss://api.instantdb.com/runtime/session")!,
      transport: .webSocket,
      state: .errored,
      isAuthenticated: false,
      userID: nil,
      pendingMutationCount: 4,
      processedTransactionID: "100",
      lastErrorMessage: "Local synchronization is blocked.",
      synchronizationBlocker: blocker
    )

    let encoded = try JSONEncoder().encode(status)
    let decoded = try JSONDecoder().decode(InstantConnectionStatus.self, from: encoded)
    expectNoDifference(decoded, status)

    var legacyObject = try #require(
      JSONSerialization.jsonObject(with: encoded) as? [String: Any]
    )
    expectNoDifference(legacyObject.removeValue(forKey: "synchronizationBlocker") != nil, true)
    let legacyData = try JSONSerialization.data(withJSONObject: legacyObject)
    let legacy = try JSONDecoder().decode(InstantConnectionStatus.self, from: legacyData)
    var expectedLegacy = status
    expectedLegacy.synchronizationBlocker = nil
    expectNoDifference(legacy, expectedLegacy)
  }

  @Test
  func unknownReceiptSynchronizationBlockerBuildsCanonicalManualRecoveryError() {
    let blocker = InstantSynchronizationBlocker(
      reason: .unknownOptimisticEffectReceipt,
      firstMutationID: "tx-unknown-receipt-first",
      blockedMutationCount: 2
    )

    let error = blocker.error(operation: "open Instant live connection")

    expectNoDifference(error.code, .persistenceFailed)
    expectNoDifference(error.operation, "open Instant live connection")
    expectNoDifference(error.localID, "tx-unknown-receipt-first")
    expectNoDifference(error.localMutationDisposition, .retainedUnknown)
    #expect(error.message.contains("Synchronization is blocked by 2 retained mutations."))
    #expect(error.recovery.contains("Automatic reconnect is paused"))
    #expect(error.recovery.contains("destructive local persistence reset"))
    #expect(error.recovery.contains("cannot guarantee lossless recovery"))
  }

  @Test
  func waitsForServerAcknowledgementWithoutLocallyFlushingTheOutbox() async throws {
    let probe = MutationDeliveryProbe(
      pendingResponses: [[Self.pendingMutation], []],
      connectionState: .opened
    )
    let client = Self.client(probe: probe)

    try await client.waitForAllPendingMutations(
      timeout: .seconds(1),
      pollInterval: .zero
    )

    let counts = await probe.counts()
    expectNoDifference(counts.pending, 2)
    expectNoDifference(counts.flush, 0)
    expectNoDifference(counts.connect, 0)
  }

  @Test
  func reconnectsAClosedLiveClientBeforeWaitingForAcknowledgement() async throws {
    let probe = MutationDeliveryProbe(
      pendingResponses: [[Self.pendingMutation], []],
      connectionState: .closed
    )
    let client = Self.client(probe: probe)

    try await client.waitForAllPendingMutations(
      timeout: .seconds(1),
      pollInterval: .zero
    )

    let counts = await probe.counts()
    expectNoDifference(counts.connect, 1)
    expectNoDifference(counts.flush, 0)
  }

  @Test
  func timesOutWithoutConfirmingAnUnacknowledgedMutation() async throws {
    let probe = MutationDeliveryProbe(
      pendingResponses: [[Self.pendingMutation]],
      connectionState: .opened
    )
    let client = Self.client(probe: probe)

    await #expect(throws: InstantError.self) {
      try await client.waitForAllPendingMutations(
        timeout: .zero,
        pollInterval: .zero
      )
    }

    let counts = await probe.counts()
    expectNoDifference(counts.flush, 0)
  }

  @Test
  func failedMutationCannotLookLikeCompletedDelivery() async throws {
    let probe = MutationDeliveryProbe(
      pendingResponses: [[Self.failedMutation]],
      connectionState: .errored
    )
    let client = Self.client(probe: probe)

    do {
      try await client.waitForAllPendingMutations(
        timeout: .seconds(1),
        pollInterval: .zero
      )
      Issue.record("Expected a failed outbox mutation to fail the delivery boundary.")
    } catch let error as InstantError {
      expectNoDifference(error.code, .permissionRejected)
      expectNoDifference(error.operation, "wait for pending mutations")
      expectNoDifference(error.localID, "tx-failed-delivery")
      expectNoDifference(error.serverEventID, nil)
      expectNoDifference(error.message, "permission denied while delivering")
    }
  }

  @Test
  func runtimeWaitReadsDurableOutboxWhenResidentClaimCacheIsEmpty() async throws {
    let cacheURL = FileManager.default.temporaryDirectory.appendingPathComponent(
      "instant-wait-durable-outbox-\(UUID().uuidString).sqlite"
    )
    var configuration = InstantRuntimeConfiguration(
      appID: "instant-wait-durable-outbox",
      persistenceURL: cacheURL,
      initialAttributes: TodoExample.attributes
    )
    configuration.autoConnectLiveTransport = false
    let runtime = try await InstantRuntime.bootstrap(configuration: configuration)
    let client = InstantSwiftDataClient(runtime: runtime)
    let transaction = InstantStoreTransaction(
      id: "tx-wait-durable-outbox",
      operations: [
        .insert(
          InstantTriple(
            entityID: "todo-wait-durable-outbox",
            attributeID: "todos/text",
            value: .string("wait for durable delivery"),
            txID: "tx-wait-durable-outbox",
            txTime: InstantTimestamp(milliseconds: 1)
          )
        )
      ]
    )
    _ = try await runtime.transact(
      transaction,
      createdAt: InstantTimestamp(milliseconds: 1)
    )

    await #expect(throws: InstantError.self) {
      try await client.waitForAllPendingMutations(
        timeout: .zero,
        pollInterval: .zero
      )
    }
    let residentBarrier = await runtime.mutationDeliveryBarrierMutations()
    let durablePendingCount = await runtime.pendingMutationCount()
    expectNoDifference(residentBarrier, [])
    expectNoDifference(durablePendingCount, 1)
  }

  private static let pendingMutation = PendingMutation(
    id: "tx-pending-delivery",
    createdAt: InstantTimestamp(milliseconds: 1_700_000_000_000),
    transaction: InstantStoreTransaction(
      id: "tx-pending-delivery",
      operations: []
    )
  )

  private static let failedMutation = PendingMutation(
    id: "tx-failed-delivery",
    createdAt: InstantTimestamp(milliseconds: 1_700_000_000_001),
    transaction: InstantStoreTransaction(
      id: "tx-failed-delivery",
      operations: []
    ),
    status: .failed,
    failureMessage: "permission denied while delivering"
  )

  private static func client(probe: MutationDeliveryProbe) -> InstantSwiftDataClient {
    InstantSwiftDataClient(
      transact: { transaction in
        InstantStoreMutationResult(
          transactionID: transaction.id,
          changedEntityIDs: [],
          tripleCount: transaction.operations.count,
          emissions: []
        )
      },
      query: { _ in [] },
      observe: { _ in .finished },
      pendingMutations: { await probe.pendingMutations() },
      flushPendingMutations: { _ in
        await probe.recordFlush()
        return InstantMutationTransportFlushResult(
          request: InstantMutationTransportRequest(
            appID: "mutation-delivery-tests",
            apiURI: URL(string: "https://api.instantdb.com")!,
            websocketURI: URL(string: "wss://api.instantdb.com/runtime/session")!,
            mutations: []
          ),
          results: [],
          confirmed: [],
          failed: [],
          pendingMutationCount: 0,
          mutationCount: 0
        )
      },
      connectionStatus: { await probe.connectionStatus() },
      connect: { await probe.connect() },
      localID: { $0 }
    )
  }
}

private actor MutationDeliveryProbe {
  private var pendingResponses: [[PendingMutation]]
  private var connectionState: InstantConnectionState
  private var pendingRequests = 0
  private var flushRequests = 0
  private var connectRequests = 0

  init(
    pendingResponses: [[PendingMutation]],
    connectionState: InstantConnectionState
  ) {
    self.pendingResponses = pendingResponses
    self.connectionState = connectionState
  }

  func pendingMutations() -> [PendingMutation] {
    pendingRequests += 1
    guard pendingResponses.count > 1 else { return pendingResponses[0] }
    return pendingResponses.removeFirst()
  }

  func connectionStatus() -> InstantConnectionStatus {
    Self.status(state: connectionState)
  }

  func connect() -> InstantConnectionStatus {
    connectRequests += 1
    connectionState = .opened
    return Self.status(state: connectionState)
  }

  func recordFlush() {
    flushRequests += 1
  }

  func counts() -> (pending: Int, flush: Int, connect: Int) {
    (pendingRequests, flushRequests, connectRequests)
  }

  private static func status(state: InstantConnectionState) -> InstantConnectionStatus {
    InstantConnectionStatus(
      appID: "mutation-delivery-tests",
      apiURI: URL(string: "https://api.instantdb.com")!,
      websocketURI: URL(string: "wss://api.instantdb.com/runtime/session")!,
      transport: .webSocket,
      state: state,
      isAuthenticated: false,
      userID: nil,
      pendingMutationCount: state == .opened ? 1 : 0,
      processedTransactionID: nil
    )
  }
}
