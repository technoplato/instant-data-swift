import CustomDump
import Foundation
import InstantSwiftData
import SwiftUI
import Testing

@testable import VoiceTrailV3App

@Suite(.serialized)
struct VoiceTrailV3AppTests {
  @Test @MainActor
  func rootCompilesEverySettledScreenAndRoutesRecordingToPlayback() {
    let model = VoiceTrailAppModel()
    let root: any View = VoiceTrailRootScreen(model: model)
    _ = root

    expectNoDifference(
      VoiceTrailAppTab.allCases,
      [
        .auth, .recordings, .capture, .playback, .preferences,
      ])
    expectNoDifference(model.selectedTab, .recordings)

    let recordingID = InstantID<VoiceTrailRecording>(rawValue: "recording-app-route")
    model.recordingTapped(recordingID)

    expectNoDifference(model.playbackRecordingID, recordingID)
    expectNoDifference(model.selectedTab, .playback)
  }

  @Test
  func environmentConfigurationSelectsLocalAndLiveModes() {
    expectNoDifference(
      VoiceTrailAppConfiguration.environment(
        [:],
        bundledAppID: nil,
        bundledDemoMode: false
      ),
      VoiceTrailAppConfiguration(
        appID: "voicetrail-v3-local",
        enablesLiveSync: false
      )
    )
    expectNoDifference(
      VoiceTrailAppConfiguration.environment([
        "INSTANT_APP_ID": " app-live ",
        "INSTANT_PERSISTENCE_PATH": "/tmp/voicetrail-live.sqlite",
      ]),
      VoiceTrailAppConfiguration(
        appID: "app-live",
        persistenceURL: URL(fileURLWithPath: "/tmp/voicetrail-live.sqlite"),
        enablesLiveSync: true
      )
    )
    expectNoDifference(
      VoiceTrailAppConfiguration.environment(
        ["VOICE_TRAIL_DEMO_MODE": "1"],
        bundledAppID: "ignored-live-app",
        bundledDemoMode: false
      ),
      VoiceTrailAppConfiguration(
        appID: "voicetrail-v3-watch-demo",
        enablesLiveSync: false,
        userIDOverride: VoiceTrailWatchDemo.userID,
        refreshTokenOverride: VoiceTrailWatchDemo.refreshToken,
        isDemoMode: true
      )
    )
  }

  @Test
  func transcriptStreamUsesStableIdentityAndLatestValidSnapshot() throws {
    let recordingID = InstantID<VoiceTrailRecording>(rawValue: "recording-watch")

    expectNoDifference(
      VoiceTrailTranscriptStream.clientID(for: recordingID),
      "voicetrail-transcript-recording-watch"
    )
    expectNoDifference(
      VoiceTrailTranscriptStream.transcriptionID(for: recordingID).rawValue,
      "transcription-recording-watch"
    )

    let chunks = [
      transcriptChunk(index: 0, payload: .string("not a transcript snapshot")),
      transcriptChunk(
        index: 1,
        payload: VoiceTrailTranscriptUpdate(text: "Live words").payload
      ),
      transcriptChunk(
        index: 2,
        payload: VoiceTrailTranscriptUpdate(
          text: "Live words on Watch",
          isFinal: true
        ).payload
      ),
    ]

    expectNoDifference(
      VoiceTrailTranscriptStream.latestUpdate(in: chunks),
      VoiceTrailTranscriptUpdate(text: "Live words on Watch", isFinal: true)
    )
  }

  @Test @MainActor
  func bootstrapInstallsClientAndPublishesReady() async throws {
    let client = InstantSwiftDataClient.unimplemented("VoiceTrail bootstrap fixture")
    let model = VoiceTrailBootstrapModel(
      configuration: VoiceTrailAppConfiguration(
        appID: "app-bootstrap",
        enablesLiveSync: false
      ),
      bootstrapper: VoiceTrailAppBootstrapper { _ in client }
    )

    model.startIfNeeded()
    for _ in 0..<100 where model.phase != .ready {
      await Task.yield()
    }

    expectNoDifference(model.phase, .ready)
  }

  @Test
  func createRecordingMessageMaterializesCanonicalAppShape() async throws {
    let cacheURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("voicetrail-app-message-\(UUID().uuidString).sqlite")
    defer { try? FileManager.default.removeItem(at: cacheURL) }

    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "voicetrail-app-message",
        persistenceURL: cacheURL,
        initialAttributes: VoiceTrailSchema.attributes
      )
    )
    _ = try await runtime.signInWithRefreshToken("app-refresh", userID: "owner-app")
    let client = InstantSwiftDataClient(runtime: runtime)
    let recordingID = InstantID<VoiceTrailRecording>(rawValue: "recording-app")
    let transcriptionID = InstantID<VoiceTrailTranscription>(rawValue: "transcription-app")
    let prepared = try await CreateVoiceTrailRecording(
      recordingID: recordingID,
      transcriptionID: transcriptionID,
      ownerID: InstantID(rawValue: "owner-app"),
      deviceID: "device-app",
      title: "App capture"
    ).prepare(using: client)

    _ = try await client.transact {
      for mutation in prepared.mutations {
        mutation
      }
    }

    let recordings = FetchAll(VoiceTrailRecording.query)
    try await recordings.load(using: client)
    let transcriptions = FetchAll(VoiceTrailTranscription.query)
    try await transcriptions.load(using: client)

    let recording = try #require(recordings.wrappedValue.first)
    expectNoDifference(recording.id, recordingID)
    expectNoDifference(recording.title, "App capture")
    expectNoDifference(recording.ownerID.rawValue, "owner-app")
    expectNoDifference(recording.deviceID, "device-app")
    expectNoDifference(recording.state, "recording")
    expectNoDifference(recording.durationMilliseconds, 0)

    let transcription = try #require(transcriptions.wrappedValue.first)
    expectNoDifference(transcription.id, transcriptionID)
    expectNoDifference(transcription.recordingID, recordingID)
    expectNoDifference(transcription.state, "processing")

    let attachmentID = InstantID<VoiceTrailAttachment>(rawValue: "attachment-app")
    let attachment = try await CreateVoiceTrailAttachment(
      attachmentID: attachmentID,
      recordingID: recordingID,
      kind: "screenshot",
      contents: "capture.png",
      offsetMilliseconds: 2_500
    ).prepare(using: client)
    let finished = try await FinishVoiceTrailRecording(
      recordingID: recordingID,
      transcriptionID: transcriptionID,
      durationMilliseconds: 12_750
    ).prepare(using: client)
    _ = try await client.transact {
      for mutation in attachment.mutations { mutation }
      for mutation in finished.mutations { mutation }
    }

    try await recordings.load(using: client)
    try await transcriptions.load(using: client)
    let attachments = FetchAll(VoiceTrailAttachment.query)
    try await attachments.load(using: client)

    expectNoDifference(recordings.wrappedValue.first?.state, "finished")
    expectNoDifference(recordings.wrappedValue.first?.durationMilliseconds, 12_750)
    expectNoDifference(transcriptions.wrappedValue.first?.state, "ready")
    let storedAttachment = try #require(attachments.wrappedValue.first)
    expectNoDifference(storedAttachment.id, attachmentID)
    expectNoDifference(storedAttachment.recordingID, recordingID)
    expectNoDifference(storedAttachment.kind, "screenshot")
    expectNoDifference(storedAttachment.contents, "capture.png")
    expectNoDifference(storedAttachment.offsetMilliseconds, 2_500)
  }
}

private func transcriptChunk(index: Int64, payload: JSONValue) -> InstantStreamChunk {
  InstantStreamChunk(
    id: "chunk-\(index)",
    appID: "app-watch",
    streamID: "stream-watch",
    index: index,
    payload: payload,
    userID: "user-watch",
    createdAt: InstantTimestamp(milliseconds: index)
  )
}
