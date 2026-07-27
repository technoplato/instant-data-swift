import CustomDump
import Foundation
import InstantSwiftData
import Testing

@Suite(.serialized)
struct MutationDeliveryTests {
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

  private static let pendingMutation = PendingMutation(
    id: "tx-pending-delivery",
    createdAt: InstantTimestamp(milliseconds: 1_700_000_000_000),
    transaction: InstantStoreTransaction(
      id: "tx-pending-delivery",
      operations: []
    )
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
