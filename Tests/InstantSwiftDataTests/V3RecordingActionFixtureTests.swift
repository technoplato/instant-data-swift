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
    func recordingActionSyntaxCompilesAgainstPublicAuthLocalIDAndMessageAPIs() {
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
      let pendingCreate = try #require(
        await runtime.pendingMutations().first(where: { $0.id == mutationID })
      )
      let createTransport = try v3RecordingTransportShape(pendingCreate)
      expectNoDifference(createTransport.preconditions, [
        "entity-missing",
        "entity-missing",
        "entity-missing",
      ])
      expectNoDifference(createTransport.refValues, [
        "v3_capture_members/recording": prepared.recordingID.rawValue,
        "v3_capture_members/user": prepared.ownerID.rawValue,
        "v3_capture_recordings/owner": prepared.ownerID.rawValue,
        "v3_capture_transcriptions/recording": prepared.recordingID.rawValue,
      ])
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
      expectNoDifference(durable.map(\.ownerID.rawValue), ["user-created"])
      expectNoDifference(durable.map(\.deviceID), ["device-created"])
      expectNoDifference(durable.map(\.state), ["recording"])

      let durableTranscriptions = try await InstantSwiftDataClient(runtime: relaunched).query(
        V3CaptureTranscription.query
      )
      let durableMembers = try await InstantSwiftDataClient(runtime: relaunched).query(
        V3CaptureMember.query
      )
      expectNoDifference(durableTranscriptions.map(\.recordingID), [prepared.recordingID])
      expectNoDifference(durableTranscriptions.map(\.state), ["processing"])
      expectNoDifference(durableMembers.map(\.recordingID), [prepared.recordingID])
      expectNoDifference(durableMembers.map(\.userID), [prepared.ownerID])
      expectNoDifference(durableMembers.map(\.role), ["owner"])
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

    @Test @MainActor
    func attachmentAndFinishMessagesAreOptimisticAcceptedAndDurable() async throws {
      let cacheURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("v3-recording-finish-\(UUID().uuidString).sqlite")
      let appID = "v3-recording-finish"
      let runtime = try await v3RecordingActionRuntime(appID: appID, cacheURL: cacheURL)
      let client = InstantSwiftDataClient(runtime: runtime)
      let prepared = V3PreparedRecording(
        recordingID: "recording-finish",
        ownerID: InstantID(rawValue: "user-finish"),
        deviceID: "device-finish"
      )

      let createTask = client.send(
        V3CreateRecordingSession(prepared: prepared, title: "Finish notes")
      )
      let createMutationID = try await waitForV3RecordingActionMutation(runtime)
      _ = try await runtime.confirmMutation(id: createMutationID)
      await createTask.value

      let attachmentCallbacks = V3RecordingAttachmentCallbacks()
      let attachmentTask = client.send(
        V3CreateRecordingAttachment(
          id: InstantID(rawValue: "attachment-screenshot"),
          recordingID: prepared.recordingID,
          kind: "screenshot",
          contents: "capture.png",
          offsetMilliseconds: 2_500
        ),
        onOptimisticCommit: { change in
          attachmentCallbacks.optimistic.append(change.summary())
        },
        onServerAccepted: { change in
          attachmentCallbacks.accepted.append(change.summary())
        },
        onFailure: { error in
          attachmentCallbacks.failures.append(error)
        }
      )

      let attachmentMutationID = try await waitForV3RecordingActionMutation(runtime)
      let pendingAttachment = try #require(
        await runtime.pendingMutations().first(where: { $0.id == attachmentMutationID })
      )
      let attachmentTransport = try v3RecordingTransportShape(pendingAttachment)
      expectNoDifference(attachmentTransport.preconditions, ["entity-missing"])
      expectNoDifference(attachmentTransport.refValues, [
        "v3_capture_attachments/recording": prepared.recordingID.rawValue
      ])
      let optimisticAttachments = try await client.query(V3CaptureAttachment.query)
      expectNoDifference(optimisticAttachments.map(\.kind), ["screenshot"])
      expectNoDifference(optimisticAttachments.map(\.contents), ["capture.png"])
      expectNoDifference(attachmentCallbacks.optimistic.map(\.attachmentID), [
        "attachment-screenshot"
      ])
      expectNoDifference(attachmentCallbacks.accepted, [])
      expectNoDifference(attachmentCallbacks.failures, [])

      _ = try await runtime.confirmMutation(id: attachmentMutationID)
      await attachmentTask.value
      expectNoDifference(attachmentCallbacks.optimistic.count, 1)
      expectNoDifference(attachmentCallbacks.accepted.map(\.attachmentID), [
        "attachment-screenshot"
      ])

      let finishCallbacks = V3RecordingFinishCallbacks()
      let finishTask = client.send(
        V3FinishRecording(
          recordingID: prepared.recordingID,
          transcriptionID: prepared.transcriptionID,
          durationMilliseconds: 12_750
        ),
        onOptimisticCommit: { change in
          finishCallbacks.optimistic.append(change.summary())
        },
        onServerAccepted: { change in
          finishCallbacks.accepted.append(change.summary())
        },
        onFailure: { error in
          finishCallbacks.failures.append(error)
        }
      )

      let finishMutationID = try await waitForV3RecordingActionMutation(runtime)
      let pendingFinish = try #require(
        await runtime.pendingMutations().first(where: { $0.id == finishMutationID })
      )
      let finishTransport = try v3RecordingTransportShape(pendingFinish)
      expectNoDifference(finishTransport.preconditions, [
        "entity-exists",
        "entity-exists",
      ])
      expectNoDifference(finishTransport.refValues, [:])
      let optimisticRecordings = try await client.query(V3CaptureRecording.query)
      let optimisticTranscriptions = try await client.query(V3CaptureTranscription.query)
      expectNoDifference(optimisticRecordings.map(\.state), ["finished"])
      expectNoDifference(optimisticRecordings.map(\.durationMilliseconds), [12_750])
      expectNoDifference(optimisticTranscriptions.map(\.state), ["ready"])
      expectNoDifference(finishCallbacks.optimistic.map(\.durationMilliseconds), [12_750])
      expectNoDifference(finishCallbacks.accepted, [])
      expectNoDifference(finishCallbacks.failures, [])

      _ = try await runtime.confirmMutation(id: finishMutationID)
      await finishTask.value
      expectNoDifference(finishCallbacks.optimistic.count, 1)
      expectNoDifference(finishCallbacks.accepted.map(\.durationMilliseconds), [12_750])

      let relaunched = try await v3RecordingActionRuntime(appID: appID, cacheURL: cacheURL)
      let relaunchedClient = InstantSwiftDataClient(runtime: relaunched)
      let durableRecordings = try await relaunchedClient.query(V3CaptureRecording.query)
      let durableTranscriptions = try await relaunchedClient.query(V3CaptureTranscription.query)
      let durableAttachments = try await relaunchedClient.query(V3CaptureAttachment.query)
      expectNoDifference(durableRecordings.map(\.state), ["finished"])
      expectNoDifference(durableRecordings.map(\.durationMilliseconds), [12_750])
      expectNoDifference(durableTranscriptions.map(\.state), ["ready"])
      expectNoDifference(durableAttachments.map(\.recordingID), [prepared.recordingID])
      expectNoDifference(durableAttachments.map(\.offsetMilliseconds), [2_500])
    }

    @Test @MainActor
    func attachmentAndFinishRejectionsDoNotReplayCallbacksAfterRetry() async throws {
      let cacheURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("v3-recording-action-rejections-\(UUID().uuidString).sqlite")
      let runtime = try await v3RecordingActionRuntime(
        appID: "v3-recording-action-rejections",
        cacheURL: cacheURL
      )
      let client = InstantSwiftDataClient(runtime: runtime)
      let prepared = V3PreparedRecording(
        recordingID: "recording-action-rejections",
        ownerID: InstantID(rawValue: "user-action-rejections"),
        deviceID: "device-action-rejections"
      )

      let createTask = client.send(
        V3CreateRecordingSession(prepared: prepared, title: "Rejected actions")
      )
      let createMutationID = try await waitForV3RecordingActionMutation(runtime)
      _ = try await runtime.confirmMutation(id: createMutationID)
      await createTask.value

      let attachmentCallbacks = V3RecordingAttachmentCallbacks()
      let attachmentTask = client.send(
        V3CreateRecordingAttachment(
          id: InstantID(rawValue: "attachment-rejected"),
          recordingID: prepared.recordingID,
          kind: "text",
          contents: "Rejected clipboard text",
          offsetMilliseconds: 4_000
        ),
        onOptimisticCommit: { change in
          attachmentCallbacks.optimistic.append(change.summary())
        },
        onServerAccepted: { change in
          attachmentCallbacks.accepted.append(change.summary())
        },
        onFailure: { attachmentCallbacks.failures.append($0) }
      )
      let attachmentMutationID = try await waitForV3RecordingActionMutation(runtime)
      _ = try await runtime.failMutation(
        id: attachmentMutationID,
        message: "attachment creation denied"
      )
      await attachmentTask.value

      expectNoDifference(attachmentCallbacks.optimistic.count, 1)
      expectNoDifference(attachmentCallbacks.accepted, [])
      expectNoDifference(
        attachmentCallbacks.failures.map(\.message),
        ["attachment creation denied"]
      )
      _ = try await runtime.retryMutation(id: attachmentMutationID)
      _ = try await runtime.confirmMutation(id: attachmentMutationID)
      try await Task.sleep(nanoseconds: 10_000_000)
      expectNoDifference(attachmentCallbacks.optimistic.count, 1)
      expectNoDifference(attachmentCallbacks.accepted, [])
      expectNoDifference(attachmentCallbacks.failures.count, 1)

      let finishCallbacks = V3RecordingFinishCallbacks()
      let finishTask = client.send(
        V3FinishRecording(
          recordingID: prepared.recordingID,
          transcriptionID: prepared.transcriptionID,
          durationMilliseconds: 14_250
        ),
        onOptimisticCommit: { change in
          finishCallbacks.optimistic.append(change.summary())
        },
        onServerAccepted: { change in
          finishCallbacks.accepted.append(change.summary())
        },
        onFailure: { finishCallbacks.failures.append($0) }
      )
      let finishMutationID = try await waitForV3RecordingActionMutation(runtime)
      _ = try await runtime.failMutation(
        id: finishMutationID,
        message: "recording finish denied"
      )
      await finishTask.value

      expectNoDifference(finishCallbacks.optimistic.count, 1)
      expectNoDifference(finishCallbacks.accepted, [])
      expectNoDifference(
        finishCallbacks.failures.map(\.message),
        ["recording finish denied"]
      )
      _ = try await runtime.retryMutation(id: finishMutationID)
      _ = try await runtime.confirmMutation(id: finishMutationID)
      try await Task.sleep(nanoseconds: 10_000_000)
      expectNoDifference(finishCallbacks.optimistic.count, 1)
      expectNoDifference(finishCallbacks.accepted, [])
      expectNoDifference(finishCallbacks.failures.count, 1)
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
      VStack {
        Text(recorder.title)
        Button("Screenshot") {
          screenshotButtonTapped()
        }
        Button("Copy text") {
          copiedTextButtonTapped()
        }
        Button("Stop") {
          stopButtonTapped()
        }
      }
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

    private func screenshotButtonTapped() {
      recorder.captureScreenshot(
        onCaptured: { screenshot in
          db.send(
            V3CreateRecordingAttachment(
              id: InstantID(rawValue: screenshot.attachmentID),
              recordingID: InstantID(rawValue: recorder.recordingID),
              kind: "screenshot",
              contents: screenshot.fileName,
              offsetMilliseconds: screenshot.offsetMilliseconds
            ),
            onOptimisticCommit: { (_: borrowing V3RecordingAttachmentCreatedChange) in },
            onServerAccepted: { (_: borrowing V3RecordingAttachmentCreatedChange) in },
            onFailure: { _ in }
          )
        },
        onFailure: { _ in }
      )
    }

    private func copiedTextButtonTapped() {
      recorder.readClipboardText(
        onRead: { copiedText in
          db.send(
            V3CreateRecordingAttachment(
              id: InstantID(rawValue: copiedText.attachmentID),
              recordingID: InstantID(rawValue: recorder.recordingID),
              kind: "text",
              contents: copiedText.text,
              offsetMilliseconds: copiedText.offsetMilliseconds
            ),
            onOptimisticCommit: { (_: borrowing V3RecordingAttachmentCreatedChange) in },
            onServerAccepted: { (_: borrowing V3RecordingAttachmentCreatedChange) in },
            onFailure: { _ in }
          )
        },
        onFailure: { _ in }
      )
    }

    private func stopButtonTapped() {
      recorder.stop(
        onFinished: { finished in
          db.send(
            V3FinishRecording(
              recordingID: InstantID(rawValue: recorder.recordingID),
              transcriptionID: InstantID(rawValue: recorder.transcriptionID),
              durationMilliseconds: finished.durationMilliseconds
            ),
            onOptimisticCommit: { (_: borrowing V3RecordingFinishedChange) in },
            onServerAccepted: { (_: borrowing V3RecordingFinishedChange) in },
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
    @Published private(set) var transcriptionID = "transcription-recording-session"

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
          recordingID = prepared.recordingID.rawValue
          transcriptionID = prepared.transcriptionID.rawValue
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

    func captureScreenshot(
      onCaptured: @escaping @MainActor @Sendable (V3CapturedScreenshot) -> Void,
      onFailure: @escaping @MainActor @Sendable (InstantError) -> Void
    ) {
      _ = onFailure
      onCaptured(
        V3CapturedScreenshot(
          attachmentID: "attachment-screenshot",
          fileName: "capture.png",
          offsetMilliseconds: 2_500
        )
      )
    }

    func readClipboardText(
      onRead: @escaping @MainActor @Sendable (V3CopiedText) -> Void,
      onFailure: @escaping @MainActor @Sendable (InstantError) -> Void
    ) {
      _ = onFailure
      onRead(
        V3CopiedText(
          attachmentID: "attachment-text",
          text: "Copied notes",
          offsetMilliseconds: 3_000
        )
      )
    }

    func stop(
      onFinished: @escaping @MainActor @Sendable (V3FinishedRecording) -> Void,
      onFailure: @escaping @MainActor @Sendable (InstantError) -> Void
    ) {
      _ = onFailure
      onFinished(V3FinishedRecording(durationMilliseconds: 12_750))
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
    var recordingID: InstantID<V3CaptureRecording>
    var transcriptionID: InstantID<V3CaptureTranscription>
    var memberID: InstantID<V3CaptureMember>
    var ownerID: InstantID<V3CaptureUser>
    var deviceID: String

    init(
      recordingID: String,
      ownerID: InstantID<V3CaptureUser>,
      deviceID: String
    ) {
      self.recordingID = InstantID(rawValue: recordingID)
      self.transcriptionID = InstantID(rawValue: "transcription-\(recordingID)")
      self.memberID = InstantID(rawValue: "member-\(recordingID)")
      self.ownerID = ownerID
      self.deviceID = deviceID
    }
  }

  private struct V3CapturedScreenshot: Sendable {
    var attachmentID: String
    var fileName: String
    var offsetMilliseconds: Int
  }

  private struct V3CopiedText: Sendable {
    var attachmentID: String
    var text: String
    var offsetMilliseconds: Int
  }

  private struct V3FinishedRecording: Sendable {
    var durationMilliseconds: Int
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
    var ownerID: InstantID<V3CaptureUser>
    var deviceID: String
    var state: String
    var durationMilliseconds: Int

    static let instantNamespace = "v3_capture_recordings"
    static let title = InstantAttributePath<Self, String>("title")
    static let owner = InstantAttributePath<Self, InstantID<V3CaptureUser>>("owner")
    static let deviceID = InstantAttributePath<Self, String>("deviceID")
    static let state = InstantAttributePath<Self, String>("state")
    static let durationMilliseconds = InstantAttributePath<Self, Int>("durationMilliseconds")
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
        id: "v3_capture_recordings/owner",
        namespace: instantNamespace,
        name: "owner",
        valueType: .ref,
        isIndexed: true,
        forwardIdentity: "v3_capture_recordings/owner",
        reverseIdentity: "$users/recordings",
        linkNamespace: V3CaptureUser.instantNamespace
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
      InstantAttribute(
        id: "v3_capture_recordings/durationMilliseconds",
        namespace: instantNamespace,
        name: "durationMilliseconds",
        valueType: .number,
        isIndexed: true
      ),
    ]

    init(snapshot: InstantEntitySnapshot) throws {
      guard case let .string(title) = snapshot.values["title"]?.first,
        case let .ref(ownerID) = snapshot.values["owner"]?.first,
        case let .string(deviceID) = snapshot.values["deviceID"]?.first,
        case let .string(state) = snapshot.values["state"]?.first,
        case let .number(durationMilliseconds) =
          snapshot.values["durationMilliseconds"]?.first
      else {
        throw InstantError(
          code: .decodeFailed,
          operation: "decode V3 capture recording fixture",
          namespace: Self.instantNamespace,
          localID: snapshot.id,
          message: "Expected title, owner ref, deviceID, state, and duration values.",
          recovery: "Keep the recording action fixture aligned with its attributes."
        )
      }
      id = InstantID(rawValue: snapshot.id)
      self.title = title
      self.ownerID = InstantID(rawValue: ownerID)
      self.deviceID = deviceID
      self.state = state
      self.durationMilliseconds = Int(durationMilliseconds)
    }
  }

  private struct V3CaptureTranscription: Hashable, Codable, InstantEntityModel {
    var id: InstantID<Self>
    var recordingID: InstantID<V3CaptureRecording>
    var state: String

    static let instantNamespace = "v3_capture_transcriptions"
    static let recording =
      InstantAttributePath<Self, InstantID<V3CaptureRecording>>("recording")
    static let state = InstantAttributePath<Self, String>("state")
    static let instantAttributes = [
      InstantAttribute.primaryKey(namespace: instantNamespace),
      InstantAttribute(
        id: "v3_capture_transcriptions/recording",
        namespace: instantNamespace,
        name: "recording",
        valueType: .ref,
        isIndexed: true,
        forwardIdentity: "v3_capture_transcriptions/recording",
        reverseIdentity: "v3_capture_recordings/transcriptions",
        linkNamespace: V3CaptureRecording.instantNamespace
      ),
      InstantAttribute(
        id: "v3_capture_transcriptions/state",
        namespace: instantNamespace,
        name: "state",
        valueType: .string,
        isIndexed: true
      ),
    ]

    init(snapshot: InstantEntitySnapshot) throws {
      guard case let .ref(recordingID) = snapshot.values["recording"]?.first,
        case let .string(state) = snapshot.values["state"]?.first
      else {
        throw InstantError(
          code: .decodeFailed,
          operation: "decode V3 capture transcription fixture",
          namespace: Self.instantNamespace,
          localID: snapshot.id,
          message: "Expected recording ref and state values.",
          recovery: "Keep the recording transcription fixture aligned with its attributes."
        )
      }
      id = InstantID(rawValue: snapshot.id)
      self.recordingID = InstantID(rawValue: recordingID)
      self.state = state
    }
  }

  private struct V3CaptureMember: Hashable, Codable, InstantEntityModel {
    var id: InstantID<Self>
    var recordingID: InstantID<V3CaptureRecording>
    var userID: InstantID<V3CaptureUser>
    var role: String

    static let instantNamespace = "v3_capture_members"
    static let recording =
      InstantAttributePath<Self, InstantID<V3CaptureRecording>>("recording")
    static let user = InstantAttributePath<Self, InstantID<V3CaptureUser>>("user")
    static let role = InstantAttributePath<Self, String>("role")
    static let instantAttributes = [
      InstantAttribute.primaryKey(namespace: instantNamespace),
      InstantAttribute(
        id: "v3_capture_members/recording",
        namespace: instantNamespace,
        name: "recording",
        valueType: .ref,
        isIndexed: true,
        forwardIdentity: "v3_capture_members/recording",
        reverseIdentity: "v3_capture_recordings/members",
        linkNamespace: V3CaptureRecording.instantNamespace
      ),
      InstantAttribute(
        id: "v3_capture_members/user",
        namespace: instantNamespace,
        name: "user",
        valueType: .ref,
        isIndexed: true,
        forwardIdentity: "v3_capture_members/user",
        reverseIdentity: "$users/recordingMemberships",
        linkNamespace: V3CaptureUser.instantNamespace
      ),
      InstantAttribute(
        id: "v3_capture_members/role",
        namespace: instantNamespace,
        name: "role",
        valueType: .string,
        isIndexed: true
      ),
    ]

    init(snapshot: InstantEntitySnapshot) throws {
      guard case let .ref(recordingID) = snapshot.values["recording"]?.first,
        case let .ref(userID) = snapshot.values["user"]?.first,
        case let .string(role) = snapshot.values["role"]?.first
      else {
        throw InstantError(
          code: .decodeFailed,
          operation: "decode V3 capture member fixture",
          namespace: Self.instantNamespace,
          localID: snapshot.id,
          message: "Expected recording ref, user ref, and role values.",
          recovery: "Keep the recording member fixture aligned with its attributes."
        )
      }
      id = InstantID(rawValue: snapshot.id)
      self.recordingID = InstantID(rawValue: recordingID)
      self.userID = InstantID(rawValue: userID)
      self.role = role
    }
  }

  private struct V3CaptureAttachment: Hashable, Codable, InstantEntityModel {
    var id: InstantID<Self>
    var recordingID: InstantID<V3CaptureRecording>
    var kind: String
    var contents: String
    var offsetMilliseconds: Int

    static let instantNamespace = "v3_capture_attachments"
    static let recording =
      InstantAttributePath<Self, InstantID<V3CaptureRecording>>("recording")
    static let kind = InstantAttributePath<Self, String>("kind")
    static let contents = InstantAttributePath<Self, String>("contents")
    static let offsetMilliseconds = InstantAttributePath<Self, Int>("offsetMilliseconds")
    static let instantAttributes = [
      InstantAttribute.primaryKey(namespace: instantNamespace),
      InstantAttribute(
        id: "v3_capture_attachments/recording",
        namespace: instantNamespace,
        name: "recording",
        valueType: .ref,
        isIndexed: true,
        forwardIdentity: "v3_capture_attachments/recording",
        reverseIdentity: "v3_capture_recordings/attachments",
        linkNamespace: V3CaptureRecording.instantNamespace
      ),
      InstantAttribute(
        id: "v3_capture_attachments/kind",
        namespace: instantNamespace,
        name: "kind",
        valueType: .string,
        isIndexed: true
      ),
      InstantAttribute(
        id: "v3_capture_attachments/contents",
        namespace: instantNamespace,
        name: "contents",
        valueType: .string
      ),
      InstantAttribute(
        id: "v3_capture_attachments/offsetMilliseconds",
        namespace: instantNamespace,
        name: "offsetMilliseconds",
        valueType: .number,
        isIndexed: true
      ),
    ]

    init(snapshot: InstantEntitySnapshot) throws {
      guard case let .ref(recordingID) = snapshot.values["recording"]?.first,
        case let .string(kind) = snapshot.values["kind"]?.first,
        case let .string(contents) = snapshot.values["contents"]?.first,
        case let .number(offsetMilliseconds) =
          snapshot.values["offsetMilliseconds"]?.first
      else {
        throw InstantError(
          code: .decodeFailed,
          operation: "decode V3 capture attachment fixture",
          namespace: Self.instantNamespace,
          localID: snapshot.id,
          message: "Expected recording ref, kind, contents, and offset values.",
          recovery: "Keep the recording attachment fixture aligned with its attributes."
        )
      }
      id = InstantID(rawValue: snapshot.id)
      self.recordingID = InstantID(rawValue: recordingID)
      self.kind = kind
      self.contents = contents
      self.offsetMilliseconds = Int(offsetMilliseconds)
    }
  }

  private struct V3CreateRecordingSession: InstantMessage {
    var prepared: V3PreparedRecording
    var title: String

    func prepare(using client: InstantSwiftDataClient) async throws
      -> InstantPreparedMessage<V3RecordingSessionCreatedChange>
    {
      _ = client
      let change = V3RecordingSessionCreatedChange(
        recordingID: prepared.recordingID.rawValue
      )
      return InstantPreparedMessage(change: change) {
        V3CaptureRecording.create(
          id: prepared.recordingID,
          V3CaptureRecording.title.set(title),
          V3CaptureRecording.owner.set(prepared.ownerID),
          V3CaptureRecording.deviceID.set(prepared.deviceID),
          V3CaptureRecording.state.set("recording"),
          V3CaptureRecording.durationMilliseconds.set(0)
        )
        V3CaptureTranscription.create(
          id: prepared.transcriptionID,
          V3CaptureTranscription.recording.set(prepared.recordingID),
          V3CaptureTranscription.state.set("processing")
        )
        V3CaptureMember.create(
          id: prepared.memberID,
          V3CaptureMember.recording.set(prepared.recordingID),
          V3CaptureMember.user.set(prepared.ownerID),
          V3CaptureMember.role.set("owner")
        )
      }
    }
  }

  private struct V3CreateRecordingAttachment: InstantMessage {
    var id: InstantID<V3CaptureAttachment>
    var recordingID: InstantID<V3CaptureRecording>
    var kind: String
    var contents: String
    var offsetMilliseconds: Int

    func prepare(using client: InstantSwiftDataClient) async throws
      -> InstantPreparedMessage<V3RecordingAttachmentCreatedChange>
    {
      _ = client
      let change = V3RecordingAttachmentCreatedChange(attachmentID: id.rawValue)
      return InstantPreparedMessage(change: change) {
        V3CaptureAttachment.create(
          id: id,
          V3CaptureAttachment.recording.set(recordingID),
          V3CaptureAttachment.kind.set(kind),
          V3CaptureAttachment.contents.set(contents),
          V3CaptureAttachment.offsetMilliseconds.set(offsetMilliseconds)
        )
      }
    }
  }

  private struct V3FinishRecording: InstantMessage {
    var recordingID: InstantID<V3CaptureRecording>
    var transcriptionID: InstantID<V3CaptureTranscription>
    var durationMilliseconds: Int

    func prepare(using client: InstantSwiftDataClient) async throws
      -> InstantPreparedMessage<V3RecordingFinishedChange>
    {
      _ = client
      let change = V3RecordingFinishedChange(
        recordingID: recordingID.rawValue,
        durationMilliseconds: durationMilliseconds
      )
      return InstantPreparedMessage(change: change) {
        V3CaptureRecording.updateExisting(
          id: recordingID,
          V3CaptureRecording.state.set("finished"),
          V3CaptureRecording.durationMilliseconds.set(durationMilliseconds)
        )
        V3CaptureTranscription.updateExisting(
          id: transcriptionID,
          V3CaptureTranscription.state.set("ready")
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

  private struct V3RecordingAttachmentCreatedChange: Sendable {
    var attachmentID: String

    borrowing func summary() -> V3RecordingAttachmentCreatedSummary {
      V3RecordingAttachmentCreatedSummary(attachmentID: attachmentID)
    }
  }

  private struct V3RecordingAttachmentCreatedSummary: Equatable, Sendable {
    var attachmentID: String
  }

  private struct V3RecordingFinishedChange: Sendable {
    var recordingID: String
    var durationMilliseconds: Int

    borrowing func summary() -> V3RecordingFinishedSummary {
      V3RecordingFinishedSummary(
        recordingID: recordingID,
        durationMilliseconds: durationMilliseconds
      )
    }
  }

  private struct V3RecordingFinishedSummary: Equatable, Sendable {
    var recordingID: String
    var durationMilliseconds: Int
  }

  @MainActor
  private final class V3RecordingMessageCallbacks {
    var optimistic: [V3RecordingSessionCreatedSummary] = []
    var accepted: [V3RecordingSessionCreatedSummary] = []
    var failures: [InstantError] = []
  }

  @MainActor
  private final class V3RecordingAttachmentCallbacks {
    var optimistic: [V3RecordingAttachmentCreatedSummary] = []
    var accepted: [V3RecordingAttachmentCreatedSummary] = []
    var failures: [InstantError] = []
  }

  @MainActor
  private final class V3RecordingFinishCallbacks {
    var optimistic: [V3RecordingFinishedSummary] = []
    var accepted: [V3RecordingFinishedSummary] = []
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

  private struct V3RecordingTransportShape: Equatable, Sendable {
    var preconditions: [String]
    var refValues: [String: String]
  }

  private func v3RecordingTransportShape(
    _ mutation: PendingMutation
  ) throws -> V3RecordingTransportShape {
    let transport = InstantTransportMutation(mutation)
    let refAttributeIDs: Set<String> = [
      "v3_capture_attachments/recording",
      "v3_capture_members/recording",
      "v3_capture_members/user",
      "v3_capture_recordings/owner",
      "v3_capture_transcriptions/recording",
    ]
    var refValues: [String: String] = [:]
    for step in transport.txSteps {
      guard case let .addTriple(_, attributeID, value, _) = step,
        refAttributeIDs.contains(attributeID),
        case let .string(rawValue) = value
      else { continue }
      refValues[attributeID] = rawValue
    }
    return V3RecordingTransportShape(
      preconditions: transport.preconditions.map(\.kind.rawValue),
      refValues: refValues
    )
  }

  private func v3RecordingActionRuntime(appID: String, cacheURL: URL) async throws
    -> InstantRuntime
  {
    try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: appID,
        persistenceURL: cacheURL,
        initialAttributes:
          V3CaptureRecording.instantAttributes
          + V3CaptureTranscription.instantAttributes
          + V3CaptureMember.instantAttributes
          + V3CaptureAttachment.instantAttributes
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
