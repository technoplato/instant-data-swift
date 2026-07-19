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

    @Test @MainActor
    func storageStatusLoadsExactSizesAndClearsMatchingFilesOnce() async throws {
      let recorder = V3PreferencesStorageRecorder()
      let client = v3PreferencesStorageClient(recorder)
      let state = InstantStorageStatusState()

      await state.load(using: client).value
      expectNoDifference(state.localCacheSize, 184)
      expectNoDifference(state.streamCacheSize, 12)
      expectNoDifference(state.downloadedFileSize, 7)
      expectNoDifference(state.downloadedFileCount, 2)

      let callbacks = V3PreferencesStorageCallbacks()
      await state.clearDownloadedFiles(
        matching: V3RecordingAudioPath.self,
        using: client,
        onCleared: { callbacks.cleared.append($0) },
        onFailure: { callbacks.failures.append($0) }
      ).value

      expectNoDifference(
        callbacks.cleared,
        [InstantStorageFilesClearedEvent(fileCount: 1, bytesRemoved: 4)]
      )
      expectNoDifference(callbacks.failures, [])
      let deletedIDs = await recorder.deletedIDs()
      expectNoDifference(deletedIDs, ["recording-audio"])
      expectNoDifference(state.downloadedFileSize, 3)
      expectNoDifference(state.downloadedFileCount, 1)
    }
  }

  @MainActor
  private struct V3PreferencesSyncFixture: View {
    @ConnectionStatus private var connection
    @InstantSyncStatus private var sync
    @InstantStorageStatus private var storage

    var body: some View {
      Form {
        Text(connection.state.rawValue)
        Text(sync.summary)
        Text(sync.pendingOutboxCount.formatted())
        Text(storage.localCacheSize.formatted())
        Text(storage.streamCacheSize.formatted())
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

  private enum V3RecordingAudioPath: InstantStoredFileMatcher {
    static func matches(_ file: InstantStoredFile) -> Bool {
      file.contentType?.hasPrefix("audio/") == true
    }
  }

  @MainActor
  private final class V3PreferencesStorageCallbacks {
    var cleared: [InstantStorageFilesClearedEvent] = []
    var failures: [InstantError] = []
  }

  private actor V3PreferencesStorageRecorder {
    private var files = [
      InstantStoredFile(
        id: "recording-audio",
        appID: "preferences-test",
        name: "recording.m4a",
        contentType: "audio/mp4",
        byteCount: 4,
        localPath: "/tmp/recording.m4a",
        ownerUserID: "preferences-user",
        createdAt: InstantTimestamp(milliseconds: 1),
        updatedAt: InstantTimestamp(milliseconds: 1)
      ),
      InstantStoredFile(
        id: "transcript",
        appID: "preferences-test",
        name: "transcript.txt",
        contentType: "text/plain",
        byteCount: 3,
        localPath: "/tmp/transcript.txt",
        ownerUserID: "preferences-user",
        createdAt: InstantTimestamp(milliseconds: 2),
        updatedAt: InstantTimestamp(milliseconds: 2)
      ),
    ]
    private var deleted: [String] = []

    func snapshot() -> InstantStorageSnapshot {
      InstantStorageSnapshot(
        localCacheSize: 184,
        streamCacheSize: 12,
        downloadedFileSize: files.reduce(0) { $0 + $1.byteCount },
        downloadedFileCount: files.count
      )
    }

    func storedFiles() -> [InstantStoredFile] { files }

    func delete(id: String) throws -> InstantStoredFile {
      guard let index = files.firstIndex(where: { $0.id == id }) else {
        throw InstantError(
          code: .validationFailed,
          operation: "delete preferences fixture file",
          message: "Missing file \(id).",
          recovery: "Use a fixture file id."
        )
      }
      deleted.append(id)
      return files.remove(at: index)
    }

    func deletedIDs() -> [String] { deleted }
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

  private func v3PreferencesStorageClient(
    _ recorder: V3PreferencesStorageRecorder
  ) -> InstantSwiftDataClient {
    InstantSwiftDataClient(
      transact: { _ in fatalError("Unused preferences transaction") },
      query: { _ in [] },
      observe: { _ in AsyncStream { $0.finish() } },
      pendingMutations: { [] },
      localID: { _ in "unused-preferences-local-id" },
      storedFiles: { await recorder.storedFiles() },
      storageSnapshot: { await recorder.snapshot() },
      deleteStoredFile: { try await recorder.delete(id: $0) }
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
