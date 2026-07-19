import CustomDump
import Foundation
import InstantSwiftData
import Testing

#if canImport(SwiftUI)
  import SwiftUI

  @Suite(.serialized)
  struct V3PreferencesFixtureTests {
    private let sourceReferences = [
      "upstream/instant/client/packages/core/src/Reactor.js subscribeConnectionStatus, _transportOnOpen, _transportOnClose, and _handleReceive init-ok/error branches",
      "upstream/instant/client/packages/python/tests/test_subscription_state.py test_post_init_failure_silently_retries",
      "Tests/InstantSwiftDataCoreTests/InstantReactorParityTests.swift upstreamPythonSubscriptionPostInitFailureSilentlyRetriesAndResubscribes",
      "screens/v3/preferences.md",
    ]

    @Test @MainActor
    func preferencesSyncSyntaxCompilesWithRenderablePhases() {
      let view: any View = V3PreferencesSyncFixture()
      _ = view

      let state = InstantSyncStatusState()
      expectNoDifference(state.phase, .cached)
      expectNoDifference(state.policy, .automatic)
      expectNoDifference(
        InstantSyncPolicy.displayCases,
        [.automatic, .manual, .offlineOnly, .readOnly, .whenAuthenticated]
      )
      expectNoDifference(sourceReferences.count, 4)
    }

    @Test @MainActor
    func syncStatePortsCanonicalConnectionAndReconnectSequence() async throws {
      let recorder = V3PreferencesStatusRecorder()
      let client = v3PreferencesClient(recorder)
      let state = InstantSyncStatusState()
      state.startObservationIfNeeded(using: client)
      await recorder.waitUntilSubscribed()

      await recorder.yield(v3PreferencesStatus(state: .connecting))
      try await waitForV3PreferencesCondition { state.phase == .connecting }

      await recorder.yield(v3PreferencesStatus(state: .authenticated, pending: 2, txID: "tx-1"))
      try await waitForV3PreferencesCondition { state.phase == .authenticated }
      expectNoDifference(state.pendingOutboxCount, 2)
      expectNoDifference(state.lastRemoteChangeDescription, "tx-1")
      expectNoDifference(state.canFlush, true)

      await recorder.yield(v3PreferencesStatus(state: .closed, pending: 2, txID: "tx-1"))
      try await waitForV3PreferencesCondition { state.phase == .reconnecting }

      await recorder.yield(v3PreferencesStatus(state: .authenticated, pending: 2, txID: "tx-2"))
      try await waitForV3PreferencesCondition {
        state.phase == .authenticated && state.lastRemoteChangeDescription == "tx-2"
      }

      await recorder.yield(
        v3PreferencesStatus(state: .errored, pending: 2, error: "permission denied")
      )
      try await waitForV3PreferencesCondition { state.phase == .failed }
      expectNoDifference(state.summary, "permission denied")

      state.stopObservation()

      let offlineRecorder = V3PreferencesStatusRecorder()
      let offlineState = InstantSyncStatusState()
      offlineState.startObservationIfNeeded(using: v3PreferencesClient(offlineRecorder))
      await offlineRecorder.waitUntilSubscribed()
      await offlineRecorder.yield(v3PreferencesStatus(state: .closed))
      try await waitForV3PreferencesCondition { offlineState.phase == .offline }
      offlineState.stopObservation()
    }

    @Test @MainActor
    func manualFlushCallbacksMatchTheExplicitUserActionOnce() async throws {
      let recorder = V3PreferencesStatusRecorder()
      let client = v3PreferencesClient(recorder)
      let state = InstantSyncStatusState()
      let callbacks = V3PreferencesFlushRecorder()

      await recorder.setPendingMutationCount(2)
      let task = state.flush(
        using: client,
        onStarted: { callbacks.started.append($0) },
        onAccepted: { callbacks.accepted.append($0) },
        onFailure: { callbacks.failures.append($0) }
      )
      await task.value

      expectNoDifference(callbacks.started, [InstantSyncFlushStartedEvent(pendingCount: 2)])
      expectNoDifference(
        callbacks.accepted,
        [InstantSyncFlushAcceptedEvent(acceptedMutationCount: 2, pendingCount: 0)]
      )
      expectNoDifference(callbacks.failures, [])
    }
  }

  @MainActor
  private struct V3PreferencesSyncFixture: View {
    @ConnectionStatus private var connection
    @InstantSyncStatus private var sync

    var body: some View {
      Form {
        Text(connection.state.rawValue)
        Text(sync.summary)
        Text(sync.pendingOutboxCount.formatted())
        Toggle("Premium-only sync", isOn: $sync.usesPremiumGate)
      }
    }
  }

  @MainActor
  private final class V3PreferencesFlushRecorder {
    var started: [InstantSyncFlushStartedEvent] = []
    var accepted: [InstantSyncFlushAcceptedEvent] = []
    var failures: [InstantError] = []
  }

  private actor V3PreferencesStatusRecorder {
    private var continuation: AsyncStream<InstantConnectionStatus>.Continuation?
    private var bufferedStatuses: [InstantConnectionStatus] = []
    private var pendingMutationCount = 0

    func stream() -> AsyncStream<InstantConnectionStatus> {
      AsyncStream { continuation in
        self.continuation = continuation
        for status in bufferedStatuses {
          continuation.yield(status)
        }
        bufferedStatuses.removeAll()
      }
    }

    func yield(_ status: InstantConnectionStatus) {
      if let continuation {
        continuation.yield(status)
      } else {
        bufferedStatuses.append(status)
      }
    }

    func waitUntilSubscribed() async {
      while continuation == nil {
        await Task.yield()
      }
    }

    func setPendingMutationCount(_ count: Int) {
      pendingMutationCount = count
    }

    func pendingMutations() -> [PendingMutation] {
      (0..<pendingMutationCount).map { index in
        PendingMutation(
          id: "pending-\(index)",
          createdAt: InstantTimestamp(milliseconds: Int64(index)),
          transaction: InstantStoreTransaction(id: "tx-\(index)", operations: [])
        )
      }
    }
  }

  private func v3PreferencesClient(
    _ recorder: V3PreferencesStatusRecorder
  ) -> InstantSwiftDataClient {
    InstantSwiftDataClient(
      transact: { _ in fatalError("Unused preferences transaction") },
      query: { _ in [] },
      observe: { _ in AsyncStream { $0.finish() } },
      pendingMutations: { await recorder.pendingMutations() },
      flushPendingMutations: { _ in
        let pending = await recorder.pendingMutations()
        return InstantMutationTransportFlushResult(
          request: InstantMutationTransportRequest(
            appID: "preferences-test",
            apiURI: InstantRuntimeConfiguration.defaultAPIURI,
            websocketURI: InstantRuntimeConfiguration.defaultWebSocketURI,
            mutations: []
          ),
          results: pending.map {
            InstantMutationTransportResult(mutationID: $0.id, outcome: .confirmed)
          },
          confirmed: pending,
          failed: [],
          pendingMutationCount: 0,
          mutationCount: pending.count
        )
      },
      connectionStatus: { v3PreferencesStatus(state: .connecting) },
      observeConnectionStatus: { await recorder.stream() },
      localID: { _ in "unused-preferences-local-id" }
    )
  }

  private func v3PreferencesStatus(
    state: InstantConnectionState,
    pending: Int = 0,
    txID: String? = nil,
    error: String? = nil
  ) -> InstantConnectionStatus {
    InstantConnectionStatus(
      appID: "preferences-test",
      apiURI: InstantRuntimeConfiguration.defaultAPIURI,
      websocketURI: InstantRuntimeConfiguration.defaultWebSocketURI,
      transport: .webSocket,
      state: state,
      isAuthenticated: state == .authenticated,
      userID: state == .authenticated ? "preferences-user" : nil,
      pendingMutationCount: pending,
      processedTransactionID: txID,
      lastErrorMessage: error
    )
  }

  private func waitForV3PreferencesCondition(
    _ condition: @escaping @MainActor @Sendable () -> Bool
  ) async throws {
    for _ in 0..<200 {
      if await condition() { return }
      try await Task.sleep(for: .milliseconds(5))
    }
    Issue.record("Timed out waiting for V3 preferences state.")
  }
#endif
