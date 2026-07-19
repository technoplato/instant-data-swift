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

    expectNoDifference(VoiceTrailAppTab.allCases, [
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
      VoiceTrailAppConfiguration.environment([:]),
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
  }
}
