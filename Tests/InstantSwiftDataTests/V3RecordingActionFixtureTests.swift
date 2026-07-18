import CustomDump
import Dependencies
import Foundation
import InstantSwiftData
import Testing

#if canImport(SwiftUI)
  import SwiftUI

  @Suite
  struct V3RecordingActionFixtureTests {
    private let sourceReferences = [
      "upstream/sqlite-data/Examples/SyncUps/RecordMeeting.swift:45-101",
      "Tests/InstantSwiftDataCoreTests/InstantStoreTests.swift:11936-12035",
      "upstream/instant/client/packages/core/__tests__/src/Reactor.test.ts:203-350",
      "Tests/InstantSwiftDataTests/V3RecordingsListFixtureTests.swift:169-249",
      "screens/v3/recording.md:194-351",
    ]

    @Test @MainActor
    func recordingStartActionSyntaxCompilesAgainstPublicAuthLocalIDAndMessageAPIs() {
      let screen = V3RecordingStartActionFixture()
      let view: any View = screen
      _ = view

      expectNoDifference(
        sourceReferences,
        [
          "upstream/sqlite-data/Examples/SyncUps/RecordMeeting.swift:45-101",
          "Tests/InstantSwiftDataCoreTests/InstantStoreTests.swift:11936-12035",
          "upstream/instant/client/packages/core/__tests__/src/Reactor.test.ts:203-350",
          "Tests/InstantSwiftDataTests/V3RecordingsListFixtureTests.swift:169-249",
          "screens/v3/recording.md:194-351",
        ]
      )
    }

    @Test @MainActor
    func productPreparationReplacementCancelsStaleWork() async throws {
      let gate = V3RecordingPreparationGate()
      let state = V3ProductRecordingSessionState { request in
        if request.deviceID == "device-first" {
          await gate.markFirstStarted()
          try await gate.waitForFirstRelease()
        }
        try Task.checkCancellation()
        return V3PreparedRecording(
          recordingID: "recording-\(request.deviceID)",
          ownerID: request.ownerID,
          deviceID: request.deviceID
        )
      }
      let callbacks = V3RecordingPreparationCallbacks()
      let ownerID = InstantID<V3CaptureUser>(rawValue: "user-capture")

      state.start(
        owner: ownerID,
        deviceID: "device-first",
        onPrepared: { callbacks.prepared.append($0) },
        onFailure: { callbacks.failures.append($0) }
      )
      await gate.waitForFirstStart()
      state.start(
        owner: ownerID,
        deviceID: "device-second",
        onPrepared: { callbacks.prepared.append($0) },
        onFailure: { callbacks.failures.append($0) }
      )

      try await waitForV3RecordingActionCondition(
        operation: "wait for replacement recording preparation"
      ) {
        callbacks.prepared.count == 1
      }
      await gate.releaseFirst()
      try await Task.sleep(nanoseconds: 10_000_000)

      expectNoDifference(callbacks.prepared.map(\.deviceID), ["device-second"])
      expectNoDifference(callbacks.failures, [])
      expectNoDifference(state.recordingID, "recording-device-second")
      expectNoDifference(state.phase, .prepared)
    }

    @Test @MainActor
    func createRecordingMessageIsOptimisticAcceptedAndDurableAcrossRelaunch() async throws {
      let cacheURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("v3-recording-create-\(UUID().uuidString).sqlite")
      let appID = "v3-recording-create"
      let runtime = try await v3RecordingActionRuntime(appID: appID, cacheURL: cacheURL)
      let client = InstantSwiftDataClient(runtime: runtime)
      let callbacks = V3RecordingMessageCallbacks()
      let prepared = V3PreparedRecording(
        recordingID: "recording-created",
        ownerID: InstantID(rawValue: "user-created"),
        deviceID: "device-created"
      )

      let task = client.send(
        V3CreateRecordingSession(prepared: prepared, title: "Morning notes"),
        onOptimisticCommit: { change in
          callbacks.optimistic.append(change.summary())
        },
        onServerAccepted: { change in
          callbacks.accepted.append(change.summary())
        },
        onFailure: { error in
          callbacks.failures.append(error)
        }
      )

      let mutationID = try await waitForV3RecordingActionMutation(runtime)
      let optimistic = try await client.query(V3CaptureRecording.query)
      expectNoDifference(optimistic.map(\.title), ["Morning notes"])
      expectNoDifference(callbacks.optimistic.map(\.recordingID), ["recording-created"])
      expectNoDifference(callbacks.accepted, [])
      expectNoDifference(callbacks.failures, [])

      _ = try await runtime.confirmMutation(id: mutationID)
      await task.value
      expectNoDifference(callbacks.optimistic.count, 1)
      expectNoDifference(callbacks.accepted.map(\.recordingID), ["recording-created"])
      expectNoDifference(callbacks.failures, [])

      let relaunched = try await v3RecordingActionRuntime(appID: appID, cacheURL: cacheURL)
      let durable = try await InstantSwiftDataClient(runtime: relaunched).query(
        V3CaptureRecording.query
      )
      expectNoDifference(durable.map(\.title), ["Morning notes"])
      expectNoDifference(durable.map(\.ownerID), ["user-created"])
      expectNoDifference(durable.map(\.deviceID), ["device-created"])
      expectNoDifference(durable.map(\.state), ["recording"])
    }

    @Test @MainActor
    func createRecordingRejectionDoesNotReplayCallbacksAfterRetry() async throws {
      let cacheURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("v3-recording-rejected-\(UUID().uuidString).sqlite")
      let runtime = try await v3RecordingActionRuntime(
        appID: "v3-recording-rejected",
        cacheURL: cacheURL
      )
      let client = InstantSwiftDataClient(runtime: runtime)
      let callbacks = V3RecordingMessageCallbacks()
      let prepared = V3PreparedRecording(
        recordingID: "recording-rejected",
        ownerID: InstantID(rawValue: "user-rejected"),
        deviceID: "device-rejected"
      )

      let task = client.send(
        V3CreateRecordingSession(prepared: prepared, title: "Rejected notes"),
        onOptimisticCommit: { change in
          callbacks.optimistic.append(change.summary())
        },
        onServerAccepted: { change in
          callbacks.accepted.append(change.summary())
        },
        onFailure: { error in
          callbacks.failures.append(error)
        }
      )

      let mutationID = try await waitForV3RecordingActionMutation(runtime)
      _ = try await runtime.failMutation(
        id: mutationID,
        message: "recording creation denied"
      )
      await task.value

      expectNoDifference(callbacks.optimistic.count, 1)
      expectNoDifference(callbacks.accepted, [])
      expectNoDifference(callbacks.failures.map(\.message), ["recording creation denied"])
      expectNoDifference(
        callbacks.failures.map(\.recoveryMessage),
        ["Inspect the deployed schema and permissions, then retry the action."]
      )

      _ = try await runtime.retryMutation(id: mutationID)
      _ = try await runtime.confirmMutation(id: mutationID)
      try await Task.sleep(nanoseconds: 10_000_000)

      expectNoDifference(callbacks.optimistic.count, 1)
      expectNoDifference(callbacks.accepted, [])
      expectNoDifference(callbacks.failures.count, 1)
    }
  }

  @MainActor
  private struct V3RecordingStartActionFixture: View {
    @InstantAuth(V3CaptureUser.self, providers: V3CaptureAuthProviders.self)
    private var auth

    @LocalID("device")
    private var deviceID

    @V3ProductRecordingSession
    private var recorder

    @Dependency(\.defaultInstantSwiftData)
    private var db

    var body: some View {
      Text(recorder.title)
        .onAppear {
          appeared()
        }
    }

    private func appeared() {
      guard
        recorder.phase == .idle,
        let user = auth.user,
        let deviceID
      else { return }

      recorder.start(
        owner: user.id,
        deviceID: deviceID,
        onPrepared: { prepared in
          db.send(
            V3CreateRecordingSession(prepared: prepared, title: recorder.title),
            onOptimisticCommit: { (_: borrowing V3RecordingSessionCreatedChange) in },
            onServerAccepted: { (_: borrowing V3RecordingSessionCreatedChange) in },
            onFailure: { _ in }
          )
        },
        onFailure: { _ in }
      )
    }
  }

  @MainActor
  @propertyWrapper
  private struct V3ProductRecordingSession: DynamicProperty {
    @StateObject private var state = V3ProductRecordingSessionState()

    var wrappedValue: V3ProductRecordingSessionState {
      state
    }
  }

  @MainActor
  private final class V3ProductRecordingSessionState: ObservableObject {
    typealias Prepare = @Sendable (V3RecordingPreparationRequest) async throws
      -> V3PreparedRecording

    @Published var title = "New recording"
    @Published private(set) var phase = V3RecordingPreparationPhase.idle
    @Published private(set) var recordingID = "recording-session"

    private let prepare: Prepare
    private var activeTask: Task<Void, Never>?

    init(
      prepare: @escaping Prepare = { request in
        V3PreparedRecording(
          recordingID: "recording-session",
          ownerID: request.ownerID,
          deviceID: request.deviceID
        )
      }
    ) {
      self.prepare = prepare
    }

    func start(
      owner: InstantID<V3CaptureUser>,
      deviceID: String,
      onPrepared: @escaping @MainActor @Sendable (V3PreparedRecording) -> Void,
      onFailure: @escaping @MainActor @Sendable (InstantError) -> Void
    ) {
      activeTask?.cancel()
      phase = .preparing
      let request = V3RecordingPreparationRequest(ownerID: owner, deviceID: deviceID)
      activeTask = Task { @MainActor [weak self, prepare] in
        do {
          let prepared = try await prepare(request)
          try Task.checkCancellation()
          guard let self else { return }
          recordingID = prepared.recordingID
          phase = .prepared
          onPrepared(prepared)
        } catch is CancellationError {
        } catch let error as InstantError {
          self?.phase = .failed
          onFailure(error)
        } catch {
          self?.phase = .failed
          onFailure(
            InstantError(
              code: .implementationFailed,
              operation: "prepare VoiceTrail recording",
              message: String(describing: error),
              recovery: "Inspect the product recording dependencies and retry."
            )
          )
        }
      }
    }

    deinit {
      activeTask?.cancel()
    }
  }

  private enum V3RecordingPreparationPhase: Equatable, Sendable {
    case idle
    case preparing
    case prepared
    case failed
  }

  private struct V3RecordingPreparationRequest: Sendable {
    var ownerID: InstantID<V3CaptureUser>
    var deviceID: String
  }

  private struct V3PreparedRecording: Sendable {
    var recordingID: String
    var ownerID: InstantID<V3CaptureUser>
    var deviceID: String
  }

  private enum V3CaptureAuthProviders: InstantAuthProviderCatalog {
    static let all: [AuthProvider] = []
  }

  private struct V3CaptureUser: Hashable, Codable, InstantEntityModel {
    var id: InstantID<Self>

    static let instantNamespace = "$users"
    static let instantAttributes: [InstantAttribute] = []

    init(snapshot: InstantEntitySnapshot) throws {
      id = InstantID(rawValue: snapshot.id)
    }
  }

  private struct V3CaptureRecording: Hashable, Codable, InstantEntityModel {
    var id: InstantID<Self>
    var title: String
    var ownerID: String
    var deviceID: String
    var state: String

    static let instantNamespace = "v3_capture_recordings"
    static let title = InstantAttributePath<Self, String>("title")
    static let ownerID = InstantAttributePath<Self, String>("ownerID")
    static let deviceID = InstantAttributePath<Self, String>("deviceID")
    static let state = InstantAttributePath<Self, String>("state")
    static let instantAttributes = [
      InstantAttribute.primaryKey(namespace: instantNamespace),
      InstantAttribute(
        id: "v3_capture_recordings/title",
        namespace: instantNamespace,
        name: "title",
        valueType: .string,
        isIndexed: true
      ),
      InstantAttribute(
        id: "v3_capture_recordings/ownerID",
        namespace: instantNamespace,
        name: "ownerID",
        valueType: .string,
        isIndexed: true
      ),
      InstantAttribute(
        id: "v3_capture_recordings/deviceID",
        namespace: instantNamespace,
        name: "deviceID",
        valueType: .string,
        isIndexed: true
      ),
      InstantAttribute(
        id: "v3_capture_recordings/state",
        namespace: instantNamespace,
        name: "state",
        valueType: .string,
        isIndexed: true
      ),
    ]

    init(snapshot: InstantEntitySnapshot) throws {
      guard case let .string(title) = snapshot.values["title"]?.first,
        case let .string(ownerID) = snapshot.values["ownerID"]?.first,
        case let .string(deviceID) = snapshot.values["deviceID"]?.first,
        case let .string(state) = snapshot.values["state"]?.first
      else {
        throw InstantError(
          code: .decodeFailed,
          operation: "decode V3 capture recording fixture",
          namespace: Self.instantNamespace,
          localID: snapshot.id,
          message: "Expected title, ownerID, deviceID, and state values.",
          recovery: "Keep the recording action fixture aligned with its attributes."
        )
      }
      id = InstantID(rawValue: snapshot.id)
      self.title = title
      self.ownerID = ownerID
      self.deviceID = deviceID
      self.state = state
    }
  }

  private struct V3CreateRecordingSession: InstantMessage {
    var prepared: V3PreparedRecording
    var title: String

    func prepare(using client: InstantSwiftDataClient) async throws
      -> InstantPreparedMessage<V3RecordingSessionCreatedChange>
    {
      _ = client
      let change = V3RecordingSessionCreatedChange(recordingID: prepared.recordingID)
      return InstantPreparedMessage(change: change) {
        V3CaptureRecording.create(
          id: InstantID(rawValue: prepared.recordingID),
          V3CaptureRecording.title.set(title),
          V3CaptureRecording.ownerID.set(prepared.ownerID.rawValue),
          V3CaptureRecording.deviceID.set(prepared.deviceID),
          V3CaptureRecording.state.set("recording")
        )
      }
    }
  }

  private struct V3RecordingSessionCreatedChange: Sendable {
    var recordingID: String

    borrowing func summary() -> V3RecordingSessionCreatedSummary {
      V3RecordingSessionCreatedSummary(recordingID: recordingID)
    }
  }

  private struct V3RecordingSessionCreatedSummary: Equatable, Sendable {
    var recordingID: String
  }

  @MainActor
  private final class V3RecordingMessageCallbacks {
    var optimistic: [V3RecordingSessionCreatedSummary] = []
    var accepted: [V3RecordingSessionCreatedSummary] = []
    var failures: [InstantError] = []
  }

  @MainActor
  private final class V3RecordingPreparationCallbacks {
    var prepared: [V3PreparedRecording] = []
    var failures: [InstantError] = []
  }

  private actor V3RecordingPreparationGate {
    private var firstStarted = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseWaiters: [CheckedContinuation<Void, Never>] = []
    private var released = false

    func markFirstStarted() {
      firstStarted = true
      startWaiters.forEach { $0.resume() }
      startWaiters.removeAll()
    }

    func waitForFirstStart() async {
      guard !firstStarted else { return }
      await withCheckedContinuation { startWaiters.append($0) }
    }

    func waitForFirstRelease() async throws {
      guard !released else { return }
      await withCheckedContinuation { releaseWaiters.append($0) }
      try Task.checkCancellation()
    }

    func releaseFirst() {
      released = true
      releaseWaiters.forEach { $0.resume() }
      releaseWaiters.removeAll()
    }
  }

  private func v3RecordingActionRuntime(appID: String, cacheURL: URL) async throws
    -> InstantRuntime
  {
    try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: appID,
        persistenceURL: cacheURL,
        initialAttributes: V3CaptureRecording.instantAttributes
      )
    )
  }

  private func waitForV3RecordingActionMutation(_ runtime: InstantRuntime) async throws
    -> String
  {
    for _ in 0..<100 {
      if let id = await runtime.pendingMutations().first?.id { return id }
      try await Task.sleep(nanoseconds: 10_000_000)
    }
    throw InstantError(
      code: .validationFailed,
      operation: "wait for V3 recording action mutation",
      message: "Timed out waiting for the optimistic recording mutation.",
      recovery: "Inspect typed message preparation and the durable outbox."
    )
  }

  @MainActor
  private func waitForV3RecordingActionCondition(
    operation: String,
    until condition: @escaping @MainActor @Sendable () -> Bool
  ) async throws {
    for _ in 0..<100 {
      if condition() { return }
      try await Task.sleep(nanoseconds: 10_000_000)
    }
    throw InstantError(
      code: .implementationFailed,
      operation: operation,
      message: "Timed out waiting for the recording action fixture condition.",
      recovery: "Inspect product-owned task replacement and callback delivery."
    )
  }
#endif
