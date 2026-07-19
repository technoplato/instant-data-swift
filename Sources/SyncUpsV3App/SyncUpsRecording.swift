import Dependencies
import Foundation
import InstantSwiftData
import Observation

@MainActor
@Observable
public final class SyncUpsV3RecordingModel: Identifiable {
  public let syncUp: SyncUpsV3SyncUp
  public let attendees: [SyncUpsV3Attendee]
  public var alert: SyncUpRecordingAlert?
  public var authorizationStatus: SyncUpSpeechAuthorizationStatus?
  public var isDismissed = false
  public var loadedSoundEffectFileName: String?
  public var requestedAuthorization = false
  public var secondsElapsed = 0
  public var soundEffectPlayCount = 0
  public var speakerIndex = 0
  public var speechResultCount = 0
  public var transcript = ""

  @ObservationIgnored @Dependency(\.continuousClock) private var clock
  @ObservationIgnored @Dependency(\.date.now) private var now
  @ObservationIgnored @Dependency(\.syncUpOpenSettingsClient) private var openSettingsClient
  @ObservationIgnored @Dependency(\.syncUpSoundEffectClient) private var soundEffectClient
  @ObservationIgnored @Dependency(\.syncUpSpeechClient) private var speechClient
  @ObservationIgnored @Dependency(\.uuid) private var uuid

  public init(syncUp: SyncUpsV3SyncUp, attendees: [SyncUpsV3Attendee]) {
    self.syncUp = syncUp
    self.attendees = attendees
  }

  public var currentSpeaker: SyncUpsV3Attendee? {
    attendees.indices.contains(speakerIndex) ? attendees[speakerIndex] : nil
  }

  public var durationPerAttendeeSeconds: Int {
    attendees.isEmpty ? max(syncUp.seconds, 1) : max(syncUp.seconds / attendees.count, 1)
  }

  public var durationRemaining: Int {
    max(0, syncUp.seconds - secondsElapsed)
  }

  public var snapshot: SyncUpsV3RecordingSnapshot {
    SyncUpsV3RecordingSnapshot(
      alert: alert,
      authorizationStatus: authorizationStatus,
      currentSpeakerID: currentSpeaker?.id,
      isDismissed: isDismissed,
      loadedSoundEffectFileName: loadedSoundEffectFileName,
      requestedAuthorization: requestedAuthorization,
      secondsElapsed: secondsElapsed,
      soundEffectPlayCount: soundEffectPlayCount,
      speakerIndex: speakerIndex,
      speechResultCount: speechResultCount,
      transcript: transcript
    )
  }

  public func task() async -> RecordSyncUpsV3Meeting? {
    guard !attendees.isEmpty else {
      alert = .endMeeting(isDiscardable: false)
      return nil
    }

    loadedSoundEffectFileName = "ding.wav"
    await soundEffectClient.load("ding.wav")

    let initialAuthorization = speechClient.authorizationStatus()
    let authorization: SyncUpSpeechAuthorizationStatus
    if initialAuthorization == .notDetermined {
      requestedAuthorization = true
      authorization = await speechClient.requestAuthorization()
    } else {
      authorization = initialAuthorization
    }
    authorizationStatus = authorization

    guard authorization == .authorized else {
      alert = .speechRecognitionDenied
      return nil
    }

    return await withTaskGroup(
      of: SyncUpsV3RecordingTaskOutcome.self,
      returning: RecordSyncUpsV3Meeting?.self
    ) { group in
      group.addTask {
        await self.runSpeechRecognition()
        return .speechEnded
      }
      group.addTask {
        .timerEnded(finished: await self.runTimer())
      }

      while let outcome = await group.next() {
        switch outcome {
        case .speechEnded where alert != nil:
          group.cancelAll()
          return nil
        case .speechEnded:
          continue
        case .timerEnded(finished: true):
          group.cancelAll()
          return finishMeeting()
        case .timerEnded(finished: false):
          group.cancelAll()
          return nil
        }
      }
      return nil
    }
  }

  public func nextButtonTapped() async {
    guard !isDismissed else { return }
    guard speakerIndex < attendees.count - 1 else {
      alert = .endMeeting(isDiscardable: false)
      return
    }
    speakerIndex += 1
    secondsElapsed = speakerIndex * durationPerAttendeeSeconds
    await playSoundEffect()
  }

  public func endMeetingButtonTapped() {
    guard !isDismissed else { return }
    alert = .endMeeting(isDiscardable: true)
  }

  public func saveAndEndButtonTapped() -> RecordSyncUpsV3Meeting {
    finishMeeting()
  }

  public func discardButtonTapped() {
    alert = nil
    isDismissed = true
  }

  public func resumeButtonTapped() {
    alert = nil
  }

  public func openSettingsButtonTapped() async {
    guard alert == .speechRecognitionDenied else { return }
    await openSettingsClient.open()
  }

  private func runSpeechRecognition() async {
    do {
      let speechTask = await speechClient.startTask()
      for try await result in speechTask {
        guard !Task.isCancelled else { return }
        transcript = result.formattedString
        speechResultCount += 1
      }
    } catch is CancellationError {
    } catch {
      if !transcript.isEmpty {
        transcript += " ❌"
      }
      alert = .speechRecognitionFailed
    }
  }

  private func runTimer() async -> Bool {
    for await _ in clock.timer(interval: .seconds(1)) {
      guard !Task.isCancelled, alert == nil, !isDismissed else { return false }
      secondsElapsed += 1
      guard secondsElapsed.isMultiple(of: durationPerAttendeeSeconds) else { continue }
      guard speakerIndex < attendees.count - 1 else { return true }
      speakerIndex += 1
      await playSoundEffect()
    }
    return false
  }

  private func playSoundEffect() async {
    soundEffectPlayCount += 1
    await soundEffectClient.play()
  }

  private func finishMeeting() -> RecordSyncUpsV3Meeting {
    isDismissed = true
    return RecordSyncUpsV3Meeting(
      meetingID: InstantID(rawValue: uuid().uuidString.lowercased()),
      syncUpID: syncUp.id,
      date: now,
      transcript: transcript
    )
  }
}

public struct SyncUpsV3RecordingSnapshot: Equatable, Sendable {
  public var alert: SyncUpRecordingAlert?
  public var authorizationStatus: SyncUpSpeechAuthorizationStatus?
  public var currentSpeakerID: InstantID<SyncUpsV3Attendee>?
  public var isDismissed: Bool
  public var loadedSoundEffectFileName: String?
  public var requestedAuthorization: Bool
  public var secondsElapsed: Int
  public var soundEffectPlayCount: Int
  public var speakerIndex: Int
  public var speechResultCount: Int
  public var transcript: String

  public init(
    alert: SyncUpRecordingAlert?,
    authorizationStatus: SyncUpSpeechAuthorizationStatus?,
    currentSpeakerID: InstantID<SyncUpsV3Attendee>?,
    isDismissed: Bool,
    loadedSoundEffectFileName: String?,
    requestedAuthorization: Bool,
    secondsElapsed: Int,
    soundEffectPlayCount: Int,
    speakerIndex: Int,
    speechResultCount: Int,
    transcript: String
  ) {
    self.alert = alert
    self.authorizationStatus = authorizationStatus
    self.currentSpeakerID = currentSpeakerID
    self.isDismissed = isDismissed
    self.loadedSoundEffectFileName = loadedSoundEffectFileName
    self.requestedAuthorization = requestedAuthorization
    self.secondsElapsed = secondsElapsed
    self.soundEffectPlayCount = soundEffectPlayCount
    self.speakerIndex = speakerIndex
    self.speechResultCount = speechResultCount
    self.transcript = transcript
  }
}

private enum SyncUpsV3RecordingTaskOutcome: Sendable {
  case speechEnded
  case timerEnded(finished: Bool)
}
