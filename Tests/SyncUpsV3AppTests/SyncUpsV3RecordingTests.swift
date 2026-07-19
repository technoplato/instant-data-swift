import CustomDump
import Dependencies
import DependenciesTestSupport
import Foundation
import InstantSwiftData
import SyncUpsV3App
import Testing

@Suite
@MainActor
struct SyncUpsV3RecordingTests {
  @Test(
    .dependencies {
      $0.continuousClock = TestClock()
      $0.date.now = Date(timeIntervalSince1970: 1_700_000_000)
      $0.uuid = .constant(UUID(uuidString: "00000000-0000-4000-8000-000000000503")!)
      $0.syncUpSpeechClient = .scripted(
        authorizationStatus: .notDetermined,
        requestedAuthorization: .authorized,
        results: [
          SyncUpSpeechRecognitionResult(formattedString: "Blob opened"),
          SyncUpSpeechRecognitionResult(formattedString: "Blob Jr closed", isFinal: true),
        ]
      )
    }
  )
  func speechSoundAndClockProduceTheTypedMeetingMessage() async throws {
    @Dependency(\.continuousClock, as: TestClock<Duration>.self) var clock
    let sounds = SyncUpsV3SoundRecorder()
    let model = withDependencies {
      $0.syncUpSoundEffectClient = SyncUpSoundEffectClient(
        load: { await sounds.load($0) },
        play: { await sounds.play() }
      )
    } operation: {
      makeModel()
    }

    let task = Task { await model.task() }
    await Task.yield()
    await Task.yield()

    await clock.advance(by: .seconds(1))
    await Task.yield()
    expectNoDifference(model.speakerIndex, 1)
    expectNoDifference(model.secondsElapsed, 1)
    expectNoDifference(model.currentSpeaker?.name, "Blob Jr")

    await clock.advance(by: .seconds(1))
    let meeting = try #require(await task.value)
    expectNoDifference(
      model.snapshot,
      SyncUpsV3RecordingSnapshot(
        alert: nil,
        authorizationStatus: .authorized,
        currentSpeakerID: InstantID(rawValue: "attendee-2"),
        isDismissed: true,
        loadedSoundEffectFileName: "ding.wav",
        requestedAuthorization: true,
        secondsElapsed: 2,
        soundEffectPlayCount: 1,
        speakerIndex: 1,
        speechResultCount: 2,
        transcript: "Blob Jr closed"
      )
    )
    expectNoDifference(meeting.meetingID.rawValue, "00000000-0000-4000-8000-000000000503")
    expectNoDifference(meeting.syncUpID.rawValue, "sync-up")
    expectNoDifference(meeting.date, Date(timeIntervalSince1970: 1_700_000_000))
    expectNoDifference(meeting.transcript, "Blob Jr closed")
    let loadedFileNames = await sounds.loadedFileNames()
    let playCount = await sounds.playCount()
    expectNoDifference(loadedFileNames, ["ding.wav"])
    expectNoDifference(playCount, 1)
  }

  @Test(
    .dependencies {
      $0.syncUpSpeechClient = .denied
    }
  )
  func deniedSpeechOffersTheInjectedSettingsAction() async {
    let settings = SyncUpsV3SettingsRecorder()
    let model = withDependencies {
      $0.syncUpOpenSettingsClient = SyncUpOpenSettingsClient {
        await settings.open()
      }
    } operation: {
      makeModel()
    }

    let meeting = await model.task()
    expectNoDifference(meeting?.meetingID, nil)
    expectNoDifference(model.authorizationStatus, .denied)
    expectNoDifference(model.alert, .speechRecognitionDenied)

    await model.openSettingsButtonTapped()
    let openCount = await settings.openCount()
    expectNoDifference(openCount, 1)
  }

  @Test(
    .dependencies {
      $0.continuousClock = TestClock()
      $0.syncUpSpeechClient = .failing(
        after: [SyncUpSpeechRecognitionResult(formattedString: "Partial transcript")]
      )
    }
  )
  func speechFailureKeepsThePartialTranscriptAndStopsAutomaticSave() async {
    let model = makeModel()

    let meeting = await model.task()
    expectNoDifference(meeting?.meetingID, nil)
    expectNoDifference(model.alert, .speechRecognitionFailed)
    expectNoDifference(model.transcript, "Partial transcript ❌")
    expectNoDifference(model.isDismissed, false)
  }

  private func makeModel() -> SyncUpsV3RecordingModel {
    let syncUpID = InstantID<SyncUpsV3SyncUp>(rawValue: "sync-up")
    let attendees = [
      SyncUpsV3Attendee(
        id: InstantID(rawValue: "attendee-1"),
        name: "Blob",
        syncUp: syncUpID
      ),
      SyncUpsV3Attendee(
        id: InstantID(rawValue: "attendee-2"),
        name: "Blob Jr",
        syncUp: syncUpID
      ),
    ]
    return SyncUpsV3RecordingModel(
      syncUp: SyncUpsV3SyncUp(
        id: syncUpID,
        seconds: 2,
        theme: .appOrange,
        title: "Tiny standup",
        attendees: attendees
      ),
      attendees: attendees
    )
  }
}

private actor SyncUpsV3SoundRecorder {
  private var fileNames: [String] = []
  private var count = 0

  func load(_ fileName: String) {
    fileNames.append(fileName)
  }

  func play() {
    count += 1
  }

  func loadedFileNames() -> [String] {
    fileNames
  }

  func playCount() -> Int {
    count
  }
}

private actor SyncUpsV3SettingsRecorder {
  private var count = 0

  func open() {
    count += 1
  }

  func openCount() -> Int {
    count
  }
}
