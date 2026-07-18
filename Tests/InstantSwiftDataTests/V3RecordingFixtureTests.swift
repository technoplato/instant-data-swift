import CustomDump
import Dependencies
import Foundation
import InstantSwiftData
import Testing

#if canImport(SwiftUI)
  import SwiftUI
  #if os(macOS)
    import AppKit
  #endif

  @Suite(.serialized)
  struct V3RecordingFixtureTests {
    private let sourceReferences = [
      "upstream/instant/client/packages/core/__tests__/src/Reactor.test.ts:414-470",
      "Tests/InstantSwiftDataCoreTests/InstantReactorParityTests.swift:1369-1410",
      "upstream/instant/client/packages/vue/src/tests/InstantVueDatabase.test.ts:172-204",
      "upstream/sqlite-data/Sources/SQLiteData/Documentation.docc/Articles/DynamicQueries.md:46-91",
      "screens/v3/recording.md",
    ]

    @Test @MainActor
    func recordingScreenSyntaxCompilesWithConcreteSessionQueryIdentity() {
      let screen = V3RecordingFixture()
      let view: any View = screen
      _ = view

      let firstSegments = V3TranscriptionSegment.liveTimeline(
        transcriptionID: "transcription-a"
      )
      let secondSegments = V3TranscriptionSegment.liveTimeline(
        transcriptionID: "transcription-b"
      )
      let firstAttachments = V3RecordingAttachment.liveTimeline(
        recordingID: "recording-a"
      )
      let secondAttachments = V3RecordingAttachment.liveTimeline(
        recordingID: "recording-b"
      )

      #expect(firstSegments.plan.id != secondSegments.plan.id)
      #expect(firstAttachments.plan.id != secondAttachments.plan.id)
      expectNoDifference(
        firstSegments.plan.filters,
        [.equals(field: "transcriptionID", value: .string("transcription-a"))]
      )
      expectNoDifference(
        firstAttachments.plan.filters,
        [.equals(field: "recordingID", value: .string("recording-a"))]
      )
      expectNoDifference(
        sourceReferences,
        [
          "upstream/instant/client/packages/core/__tests__/src/Reactor.test.ts:414-470",
          "Tests/InstantSwiftDataCoreTests/InstantReactorParityTests.swift:1369-1410",
          "upstream/instant/client/packages/vue/src/tests/InstantVueDatabase.test.ts:172-204",
          "upstream/sqlite-data/Sources/SQLiteData/Documentation.docc/Articles/DynamicQueries.md:46-91",
          "screens/v3/recording.md",
        ]
      )
    }

    @Test @MainActor
    func localIDDynamicPropertyStartsOneResolutionAcrossRepeatedUpdates() async throws {
      let recorder = V3LocalIDRecorder()
      let client = v3LocalIDClient(recorder)
      var localID = LocalID("device")

      await withDependencies {
        $0.defaultInstantSwiftData = client
      } operation: {
        localID.update()
        localID.update()

        await recorder.resumeResolution(with: "device-local-id")
        try? await waitForV3RecordingCondition(
          operation: "wait for automatic local ID resolution"
        ) {
          localID.wrappedValue == "device-local-id"
        }
      }

      expectNoDifference(localID.wrappedValue, "device-local-id")
      expectNoDifference(localID.loadError, nil)
      expectNoDifference(localID.isLoading, false)
      let recordedNames = await recorder.recordedNames()
      expectNoDifference(recordedNames, ["device"])
    }

    #if os(macOS)
      @Test @MainActor
      func localIDResolutionInvalidatesAHostedSwiftUIView() async throws {
        let recorder = V3LocalIDRecorder()
        let renders = V3LocalIDRenderRecorder()
        let client = v3LocalIDClient(recorder)

        try await withDependencies {
          $0.defaultInstantSwiftData = client
        } operation: {
          let hostingView = NSHostingView(
            rootView: V3LocalIDRenderingFixture(renders: renders)
          )
          hostingView.frame = NSRect(x: 0, y: 0, width: 320, height: 80)
          hostingView.layoutSubtreeIfNeeded()

          try await waitForV3RecordingCondition(
            operation: "wait for hosted local ID request"
          ) {
            !renders.values.isEmpty
          }
          await recorder.resumeResolution(with: "hosted-device-local-id")
          try await waitForV3RecordingCondition(
            operation: "wait for hosted local ID invalidation"
          ) {
            renders.values.last == "hosted-device-local-id"
          }

          withExtendedLifetime(hostingView) {}
        }

        #expect(renders.values.count >= 2)
        #expect(renders.values[0] == nil)
        expectNoDifference(renders.values.last, "hosted-device-local-id")
        let recordedNames = await recorder.recordedNames()
        expectNoDifference(recordedNames, ["device"])
      }
    #endif
  }

  @MainActor
  private struct V3RecordingFixture: View {
    @LocalID("device")
    private var deviceID

    @V3RecordingSession
    private var recorder

    @FetchAll
    private var segments: [V3TranscriptionSegment]

    @FetchAll
    private var attachments: [V3RecordingAttachment]

    var body: some View {
      VStack {
        Text(deviceID ?? "Resolving device")
        Text(recorder.title)
        Text("\(segments.count) segments")
        Text("\(attachments.count) attachments")
      }
      .instantFetch(
        $segments,
        V3TranscriptionSegment.liveTimeline(
          transcriptionID: recorder.transcriptionID
        )
      )
      .instantFetch(
        $attachments,
        V3RecordingAttachment.liveTimeline(
          recordingID: recorder.recordingID
        )
      )
    }
  }

  @MainActor
  @propertyWrapper
  private struct V3RecordingSession: DynamicProperty {
    @State private var value = V3RecordingSessionValue()

    var wrappedValue: V3RecordingSessionValue {
      get { value }
      nonmutating set { value = newValue }
    }
  }

  private struct V3RecordingSessionValue: Sendable {
    var title = "New recording"
    var transcriptionID = "transcription-session"
    var recordingID = "recording-session"
  }

  #if os(macOS)
    @MainActor
    private struct V3LocalIDRenderingFixture: View {
      @LocalID("device") private var deviceID
      let renders: V3LocalIDRenderRecorder

      var body: some View {
        renders.record(deviceID)
        return Text(deviceID ?? "Resolving device")
      }
    }

    @MainActor
    private final class V3LocalIDRenderRecorder {
      private(set) var values: [String?] = []

      func record(_ value: String?) {
        values.append(value)
      }
    }
  #endif

  private struct V3TranscriptionSegment: Hashable, Codable, InstantEntityModel {
    var id: InstantID<Self>
    var transcriptionID: String
    var position: Int

    static let instantNamespace = "v3_transcription_segments"
    static let transcriptionID = InstantAttributePath<Self, String>("transcriptionID")
    static let position = InstantAttributePath<Self, Int>("position")
    static let instantAttributes = [
      InstantAttribute.primaryKey(namespace: instantNamespace),
      InstantAttribute(
        id: "v3_transcription_segments/transcriptionID",
        namespace: instantNamespace,
        name: "transcriptionID",
        valueType: .string,
        isIndexed: true
      ),
      InstantAttribute(
        id: "v3_transcription_segments/position",
        namespace: instantNamespace,
        name: "position",
        valueType: .number,
        isIndexed: true
      ),
    ]

    static func liveTimeline(transcriptionID: String) -> InstantQuery<Self> {
      query
        .where(Self.transcriptionID == transcriptionID)
        .order(Self.position)
    }

    init(snapshot: InstantEntitySnapshot) throws {
      guard case let .string(transcriptionID) = snapshot.values["transcriptionID"]?.first,
        case let .number(position) = snapshot.values["position"]?.first
      else {
        throw InstantError(
          code: .decodeFailed,
          operation: "decode V3 transcription segment fixture",
          namespace: Self.instantNamespace,
          localID: snapshot.id,
          message: "Expected transcriptionID and position values.",
          recovery: "Keep the recording fixture aligned with its declared attributes."
        )
      }
      id = InstantID(rawValue: snapshot.id)
      self.transcriptionID = transcriptionID
      self.position = Int(position)
    }
  }

  private struct V3RecordingAttachment: Hashable, Codable, InstantEntityModel {
    var id: InstantID<Self>
    var recordingID: String
    var position: Int

    static let instantNamespace = "v3_recording_attachments"
    static let recordingID = InstantAttributePath<Self, String>("recordingID")
    static let position = InstantAttributePath<Self, Int>("position")
    static let instantAttributes = [
      InstantAttribute.primaryKey(namespace: instantNamespace),
      InstantAttribute(
        id: "v3_recording_attachments/recordingID",
        namespace: instantNamespace,
        name: "recordingID",
        valueType: .string,
        isIndexed: true
      ),
      InstantAttribute(
        id: "v3_recording_attachments/position",
        namespace: instantNamespace,
        name: "position",
        valueType: .number,
        isIndexed: true
      ),
    ]

    static func liveTimeline(recordingID: String) -> InstantQuery<Self> {
      query
        .where(Self.recordingID == recordingID)
        .order(Self.position)
    }

    init(snapshot: InstantEntitySnapshot) throws {
      guard case let .string(recordingID) = snapshot.values["recordingID"]?.first,
        case let .number(position) = snapshot.values["position"]?.first
      else {
        throw InstantError(
          code: .decodeFailed,
          operation: "decode V3 recording attachment fixture",
          namespace: Self.instantNamespace,
          localID: snapshot.id,
          message: "Expected recordingID and position values.",
          recovery: "Keep the recording fixture aligned with its declared attributes."
        )
      }
      id = InstantID(rawValue: snapshot.id)
      self.recordingID = recordingID
      self.position = Int(position)
    }
  }

  private actor V3LocalIDRecorder {
    private var names: [String] = []
    private var continuation: CheckedContinuation<String, Never>?
    private var resumedValue: String?

    func resolve(_ name: String) async -> String {
      names.append(name)
      if let resumedValue { return resumedValue }
      return await withCheckedContinuation { continuation in
        self.continuation = continuation
      }
    }

    func resumeResolution(with value: String) {
      resumedValue = value
      continuation?.resume(returning: value)
      continuation = nil
    }

    func recordedNames() -> [String] {
      names
    }
  }

  private func v3LocalIDClient(_ recorder: V3LocalIDRecorder) -> InstantSwiftDataClient {
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
      observe: { _ in AsyncStream { continuation in continuation.finish() } },
      pendingMutations: { [] },
      localID: { name in
        await recorder.resolve(name)
      }
    )
  }

  private func waitForV3RecordingCondition(
    operation: String,
    until condition: @escaping @MainActor @Sendable () -> Bool
  ) async throws {
    for _ in 0..<300 {
      if await condition() { return }
      try await Task.sleep(nanoseconds: 10_000_000)
    }
    throw InstantError(
      code: .implementationFailed,
      operation: operation,
      message: "Timed out waiting for the V3 recording fixture condition.",
      recovery: "Inspect the wrapper-owned lifecycle and retry the focused test."
    )
  }
#endif
