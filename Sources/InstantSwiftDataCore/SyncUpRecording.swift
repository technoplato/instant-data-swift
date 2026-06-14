import Foundation

public enum SyncUpSpeechAuthorizationStatus: String, Codable, Hashable, Sendable {
  case notDetermined
  case denied
  case restricted
  case authorized
}

public struct SyncUpSpeechRecognitionResult: Hashable, Codable, Sendable {
  public var formattedString: String
  public var isFinal: Bool

  public init(formattedString: String, isFinal: Bool = false) {
    self.formattedString = formattedString
    self.isFinal = isFinal
  }
}

public struct SyncUpSpeechClient: Sendable {
  public var authorizationStatus: @Sendable () -> SyncUpSpeechAuthorizationStatus
  public var requestAuthorization: @Sendable () async -> SyncUpSpeechAuthorizationStatus
  public var startTask:
    @Sendable () async -> AsyncThrowingStream<SyncUpSpeechRecognitionResult, Error>

  public init(
    authorizationStatus: @escaping @Sendable () -> SyncUpSpeechAuthorizationStatus,
    requestAuthorization: @escaping @Sendable () async -> SyncUpSpeechAuthorizationStatus,
    startTask: @escaping @Sendable () async
      -> AsyncThrowingStream<SyncUpSpeechRecognitionResult, Error>
  ) {
    self.authorizationStatus = authorizationStatus
    self.requestAuthorization = requestAuthorization
    self.startTask = startTask
  }
}

extension SyncUpSpeechClient {
  public static let local = Self.scripted(
    results: [
      SyncUpSpeechRecognitionResult(formattedString: "Reviewed launch risks."),
      SyncUpSpeechRecognitionResult(formattedString: "Reviewed launch risks. Final notes.", isFinal: true),
    ]
  )

  public static let denied = Self(
    authorizationStatus: { .denied },
    requestAuthorization: { .denied },
    startTask: {
      AsyncThrowingStream { continuation in
        continuation.finish()
      }
    }
  )

  public static func scripted(
    authorizationStatus: SyncUpSpeechAuthorizationStatus = .authorized,
    requestedAuthorization: SyncUpSpeechAuthorizationStatus = .authorized,
    results: [SyncUpSpeechRecognitionResult]
  ) -> Self {
    Self(
      authorizationStatus: { authorizationStatus },
      requestAuthorization: { requestedAuthorization },
      startTask: {
        AsyncThrowingStream { continuation in
          for result in results {
            continuation.yield(result)
          }
          continuation.finish()
        }
      }
    )
  }

  public static func failing(
    after results: [SyncUpSpeechRecognitionResult] = [
      SyncUpSpeechRecognitionResult(formattedString: "Partial transcript")
    ]
  ) -> Self {
    Self(
      authorizationStatus: { .authorized },
      requestAuthorization: { .authorized },
      startTask: {
        AsyncThrowingStream { continuation in
          for result in results {
            continuation.yield(result)
          }
          continuation.finish(
            throwing: InstantError(
              code: .implementationFailed,
              operation: "record sync-up speech",
              message: "The local speech recognizer failed.",
              recovery: "Keep the partial transcript or retry the recording."
            )
          )
        }
      }
    )
  }
}

public struct SyncUpSoundEffectClient: Sendable {
  public var load: @Sendable (_ fileName: String) async -> Void
  public var play: @Sendable () async -> Void

  public init(
    load: @escaping @Sendable (_ fileName: String) async -> Void,
    play: @escaping @Sendable () async -> Void
  ) {
    self.load = load
    self.play = play
  }
}

extension SyncUpSoundEffectClient {
  public static let local = Self(
    load: { _ in },
    play: {}
  )
}

public struct SyncUpOpenSettingsClient: Sendable {
  public var open: @Sendable () async -> Void

  public init(open: @escaping @Sendable () async -> Void) {
    self.open = open
  }
}

extension SyncUpOpenSettingsClient {
  public static let local = Self(open: {})
}

public enum SyncUpRecordingAlert: Hashable, Codable, Sendable {
  case endMeeting(isDiscardable: Bool)
  case speechRecognitionDenied
  case speechRecognitionFailed
}

public enum SyncUpRecordingAlertAction: String, Codable, Hashable, Sendable {
  case confirmSave
  case confirmDiscard
  case openSettings
  case cancel
}

public enum SyncUpRecordingAlertOutcome: String, Codable, Hashable, Sendable {
  case none
  case saveRequested
  case discarded
  case settingsOpened
}

public enum SyncUpRecordingEvent: Hashable, Sendable {
  case tick
  case advancedSpeaker(attendeeID: String)
  case finished
  case ignored
}

public struct SyncUpRecordingSave: Hashable, Sendable {
  public var meetingID: String
  public var operations: [InstantTripleOperation]
  public var transcript: String
  public var date: InstantTimestamp

  public init(
    meetingID: String,
    operations: [InstantTripleOperation],
    transcript: String,
    date: InstantTimestamp
  ) {
    self.meetingID = meetingID
    self.operations = operations
    self.transcript = transcript
    self.date = date
  }
}

public struct SyncUpRecordingSummary: Hashable, Codable, Sendable {
  public var syncUpID: String
  public var meetingID: String?
  public var authorizationStatus: SyncUpSpeechAuthorizationStatus?
  public var requestedAuthorization: Bool
  public var loadedSoundEffectFileName: String?
  public var soundEffectPlayCount: Int
  public var speechResultCount: Int
  public var secondsElapsed: Int
  public var speakerIndex: Int
  public var currentSpeakerName: String?
  public var transcript: String
  public var alert: SyncUpRecordingAlert?
  public var isDismissed: Bool

  public init(model: SyncUpRecordingModel, save: SyncUpRecordingSave? = nil) {
    self.syncUpID = model.syncUp.id
    self.meetingID = save?.meetingID
    self.authorizationStatus = model.authorizationStatus
    self.requestedAuthorization = model.requestedAuthorization
    self.loadedSoundEffectFileName = model.loadedSoundEffectFileName
    self.soundEffectPlayCount = model.soundEffectPlayCount
    self.speechResultCount = model.speechResultCount
    self.secondsElapsed = model.secondsElapsed
    self.speakerIndex = model.speakerIndex
    self.currentSpeakerName = model.currentSpeaker?.name
    self.transcript = model.transcript
    self.alert = model.alert
    self.isDismissed = model.isDismissed
  }
}

public struct SyncUpRecordingModel: Sendable {
  public var syncUp: SyncUpRecord
  public var attendees: [SyncUpAttendeeRecord]
  public private(set) var alert: SyncUpRecordingAlert?
  public private(set) var authorizationStatus: SyncUpSpeechAuthorizationStatus?
  public private(set) var isDismissed: Bool
  public private(set) var loadedSoundEffectFileName: String?
  public private(set) var requestedAuthorization: Bool
  public private(set) var secondsElapsed: Int
  public private(set) var soundEffectPlayCount: Int
  public private(set) var speakerIndex: Int
  public private(set) var speechResultCount: Int
  public private(set) var transcript: String

  private var openSettingsClient: SyncUpOpenSettingsClient
  private var soundEffectClient: SyncUpSoundEffectClient
  private var speechClient: SyncUpSpeechClient

  public init(
    syncUp: SyncUpRecord,
    attendees: [SyncUpAttendeeRecord],
    speechClient: SyncUpSpeechClient = .local,
    soundEffectClient: SyncUpSoundEffectClient = .local,
    openSettingsClient: SyncUpOpenSettingsClient = .local
  ) {
    self.syncUp = syncUp
    self.attendees = attendees
    self.alert = nil
    self.authorizationStatus = nil
    self.isDismissed = false
    self.loadedSoundEffectFileName = nil
    self.requestedAuthorization = false
    self.secondsElapsed = 0
    self.soundEffectPlayCount = 0
    self.speakerIndex = 0
    self.speechResultCount = 0
    self.transcript = ""
    self.openSettingsClient = openSettingsClient
    self.soundEffectClient = soundEffectClient
    self.speechClient = speechClient
  }

  public var currentSpeaker: SyncUpAttendeeRecord? {
    guard attendees.indices.contains(speakerIndex) else { return nil }
    return attendees[speakerIndex]
  }

  public var durationPerAttendeeSeconds: Int {
    guard !attendees.isEmpty else { return max(syncUp.seconds, 1) }
    return max(syncUp.seconds / attendees.count, 1)
  }

  public mutating func task(soundEffectFileName: String = "ding.wav") async {
    loadedSoundEffectFileName = soundEffectFileName
    await soundEffectClient.load(soundEffectFileName)

    let initialAuthorization = speechClient.authorizationStatus()
    let authorization: SyncUpSpeechAuthorizationStatus
    if initialAuthorization == .notDetermined {
      requestedAuthorization = true
      authorization = await speechClient.requestAuthorization()
    } else {
      authorization = initialAuthorization
    }
    authorizationStatus = authorization

    switch authorization {
    case .authorized:
      await startSpeechRecognition()
    case .notDetermined, .denied, .restricted:
      alert = .speechRecognitionDenied
    }
  }

  public mutating func nextButtonTapped() async {
    guard !isDismissed else { return }
    guard speakerIndex < attendees.count - 1 else {
      alert = .endMeeting(isDiscardable: false)
      return
    }

    speakerIndex += 1
    secondsElapsed = speakerIndex * durationPerAttendeeSeconds
    await playSoundEffect()
  }

  public mutating func tick() async -> SyncUpRecordingEvent {
    guard alert == nil, !isDismissed, !attendees.isEmpty else { return .ignored }

    secondsElapsed += 1
    guard secondsElapsed.isMultiple(of: durationPerAttendeeSeconds) else {
      return .tick
    }
    guard speakerIndex < attendees.count - 1 else {
      return .finished
    }

    speakerIndex += 1
    await playSoundEffect()
    return .advancedSpeaker(attendeeID: attendees[speakerIndex].id)
  }

  public mutating func endMeetingButtonTapped() {
    guard !isDismissed else { return }
    alert = .endMeeting(isDiscardable: true)
  }

  public mutating func alertButtonTapped(
    _ action: SyncUpRecordingAlertAction
  ) async -> SyncUpRecordingAlertOutcome {
    switch action {
    case .confirmSave:
      guard case .endMeeting = alert else { return .none }
      alert = nil
      return .saveRequested

    case .confirmDiscard:
      guard case .endMeeting = alert else { return .none }
      alert = nil
      isDismissed = true
      return .discarded

    case .openSettings:
      guard alert == .speechRecognitionDenied else { return .none }
      await openSettingsClient.open()
      return .settingsOpened

    case .cancel:
      alert = nil
      return .none
    }
  }

  public mutating func runDemo(
    meetingID: String,
    date: InstantTimestamp,
    transactionID: String
  ) async throws -> SyncUpRecordingSave {
    guard !attendees.isEmpty else {
      throw InstantError(
        code: .validationFailed,
        operation: "record sync-up meeting",
        namespace: SyncUpsExample.attendeesNamespace,
        localID: syncUp.id,
        message: "Cannot record a sync-up meeting without at least one attendee.",
        recovery: "Add an attendee before starting the recording."
      )
    }

    await task()
    if let alert {
      throw recordingAlertError(alert)
    }

    while true {
      let event = await tick()
      if case .finished = event {
        break
      }
    }
    return finishMeeting(meetingID: meetingID, date: date, transactionID: transactionID)
  }

  public mutating func finishMeeting(
    meetingID: String,
    date: InstantTimestamp,
    transactionID: String
  ) -> SyncUpRecordingSave {
    isDismissed = true
    let operations = SyncUpsExample.recordMeetingOperations(
      id: meetingID,
      syncUpID: syncUp.id,
      transcript: transcript,
      date: date,
      transactionID: transactionID
    )
    return SyncUpRecordingSave(
      meetingID: meetingID,
      operations: operations,
      transcript: transcript,
      date: date
    )
  }

  private mutating func startSpeechRecognition() async {
    do {
      let speechTask = await speechClient.startTask()
      for try await result in speechTask {
        transcript = result.formattedString
        speechResultCount += 1
      }
    } catch {
      if !transcript.isEmpty {
        transcript += " [speech failed]"
      }
      alert = .speechRecognitionFailed
    }
  }

  private mutating func playSoundEffect() async {
    soundEffectPlayCount += 1
    await soundEffectClient.play()
  }

  private func recordingAlertError(_ alert: SyncUpRecordingAlert) -> InstantError {
    switch alert {
    case .speechRecognitionDenied:
      return InstantError(
        code: .authFailed,
        operation: "record sync-up speech",
        message: "Speech recognition is not authorized.",
        recovery: "Grant speech recognition access, or record with an explicit transcript."
      )
    case .speechRecognitionFailed:
      return InstantError(
        code: .implementationFailed,
        operation: "record sync-up speech",
        message: "Speech recognition failed before the meeting could be saved.",
        recovery: "Retry the recording or save a manual transcript."
      )
    case .endMeeting:
      return InstantError(
        code: .validationFailed,
        operation: "record sync-up meeting",
        localID: syncUp.id,
        message: "The recording is waiting for an end-meeting decision.",
        recovery: "Confirm saving or discard the meeting before continuing."
      )
    }
  }
}
