import Foundation

public struct SyncUpsRecordingValidationDetails: Codable, Equatable, Sendable {
  public var cachePath: String
  public var syncUpIDs: [String]
  public var syncUpTitles: [String]
  public var attendeeIDs: [String]
  public var attendeeNames: [String]
  public var meetingIDs: [String]
  public var meetingTranscripts: [String]
  public var pendingMutationIDs: [String]
  public var recording: SyncUpRecordingSummary?
  public var tickEvent: String?
  public var alertOutcome: SyncUpRecordingAlertOutcome?
  public var openSettingsCount: Int

  public init(
    cachePath: String,
    syncUpIDs: [String],
    syncUpTitles: [String],
    attendeeIDs: [String],
    attendeeNames: [String],
    meetingIDs: [String],
    meetingTranscripts: [String],
    pendingMutationIDs: [String],
    recording: SyncUpRecordingSummary? = nil,
    tickEvent: String? = nil,
    alertOutcome: SyncUpRecordingAlertOutcome? = nil,
    openSettingsCount: Int = 0
  ) {
    self.cachePath = cachePath
    self.syncUpIDs = syncUpIDs
    self.syncUpTitles = syncUpTitles
    self.attendeeIDs = attendeeIDs
    self.attendeeNames = attendeeNames
    self.meetingIDs = meetingIDs
    self.meetingTranscripts = meetingTranscripts
    self.pendingMutationIDs = pendingMutationIDs
    self.recording = recording
    self.tickEvent = tickEvent
    self.alertOutcome = alertOutcome
    self.openSettingsCount = openSettingsCount
  }
}

public struct SyncUpsRecordingValidationResult: Sendable {
  public var appID: String
  public var cacheURL: URL
  public var syncUpID: String
  public var attendeeIDs: [String]
  public var meetingID: String
  public var evidence: [ValidationEvidenceRow<SyncUpsRecordingValidationDetails>]

  public init(
    appID: String,
    cacheURL: URL,
    syncUpID: String,
    attendeeIDs: [String],
    meetingID: String,
    evidence: [ValidationEvidenceRow<SyncUpsRecordingValidationDetails>]
  ) {
    self.appID = appID
    self.cacheURL = cacheURL
    self.syncUpID = syncUpID
    self.attendeeIDs = attendeeIDs
    self.meetingID = meetingID
    self.evidence = evidence
  }
}

public enum InstantSwiftDataSyncUpsRecordingValidation {
  public static func run(
    appID: String = "syncups-recording-validation",
    cacheURL: URL? = nil,
    timestamp: @escaping @Sendable () -> InstantTimestamp = {
      InstantTimestamp(milliseconds: Int64((Date().timeIntervalSince1970 * 1000).rounded()))
    },
    makeID: @escaping @Sendable () -> String = { UUID().uuidString.lowercased() }
  ) async throws -> SyncUpsRecordingValidationResult {
    let cacheURL =
      cacheURL
      ?? FileManager.default.temporaryDirectory
        .appendingPathComponent("InstantSwiftDataSyncUpsRecording-\(makeID())", isDirectory: true)
        .appendingPathComponent("state.sqlite")
    try FileManager.default.createDirectory(
      at: cacheURL.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )

    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: appID,
        persistenceURL: cacheURL,
        initialAttributes: SyncUpsExample.attributes,
        now: timestamp,
        makeID: makeID
      )
    )

    let syncUpID = makeID()
    let attendees = [
      SyncUpAttendeeRecord(id: makeID(), name: "Blob", syncUpID: syncUpID),
      SyncUpAttendeeRecord(id: makeID(), name: "Blob Jr", syncUpID: syncUpID),
    ]
    let syncUp = SyncUpRecord(
      id: syncUpID,
      title: "Tiny validation standup",
      seconds: 2,
      theme: .appOrange
    )

    var evidence: [ValidationEvidenceRow<SyncUpsRecordingValidationDetails>] = []

    let seedTransactionID = makeID()
    let seededAt = timestamp()
    try await runtime.transact(
      InstantStoreTransaction(
        id: seedTransactionID,
        operations: SyncUpsExample.createSyncUpOperations(
          id: syncUp.id,
          title: syncUp.title,
          seconds: syncUp.seconds,
          theme: syncUp.theme,
          updatedAt: seededAt,
          transactionID: seedTransactionID
        )
        + attendees.flatMap { attendee in
          SyncUpsExample.createAttendeeOperations(
            id: attendee.id,
            syncUpID: attendee.syncUpID,
            name: attendee.name,
            updatedAt: seededAt,
            transactionID: seedTransactionID
          )
        }
      ),
      createdAt: seededAt,
      source: "validation.syncups.recording.seed"
    )
    evidence.append(
      try await evidenceRow(event: "seed", runtime: runtime, cacheURL: cacheURL, timestamp: timestamp)
    )

    var model = SyncUpRecordingModel(syncUp: syncUp, attendees: attendees)
    await model.task()
    guard model.alert == nil else {
      throw recordingStateError(
        operation: "validate sync-up speech task",
        message: "Expected the local scripted speech client to authorize recording.",
        recovery: "Inspect SyncUpSpeechClient.local and SyncUpRecordingModel.task."
      )
    }
    evidence.append(
      try await evidenceRow(
        event: "speech-task",
        runtime: runtime,
        cacheURL: cacheURL,
        timestamp: timestamp,
        recording: SyncUpRecordingSummary(model: model)
      )
    )

    let firstTick = await model.tick()
    guard case let .advancedSpeaker(attendeeID) = firstTick,
      attendeeID == attendees[1].id
    else {
      throw recordingStateError(
        operation: "validate sync-up speaker advance",
        message: "Expected the first tick to advance to the second attendee.",
        recovery: "Inspect recording duration-per-attendee calculations."
      )
    }
    evidence.append(
      try await evidenceRow(
        event: "speaker-advance",
        runtime: runtime,
        cacheURL: cacheURL,
        timestamp: timestamp,
        recording: SyncUpRecordingSummary(model: model),
        tickEvent: "advancedSpeaker"
      )
    )

    let finalTick = await model.tick()
    guard case .finished = finalTick else {
      throw recordingStateError(
        operation: "validate sync-up recording finish",
        message: "Expected the final tick to finish the two-attendee meeting.",
        recovery: "Inspect SyncUpRecordingModel.tick and finish conditions."
      )
    }

    let meetingID = makeID()
    let meetingTransactionID = makeID()
    let recordedAt = timestamp()
    let save = model.finishMeeting(
      meetingID: meetingID,
      date: recordedAt,
      transactionID: meetingTransactionID
    )
    let recording = SyncUpRecordingSummary(model: model, save: save)
    evidence.append(
      try await evidenceRow(
        event: "finish",
        runtime: runtime,
        cacheURL: cacheURL,
        timestamp: timestamp,
        recording: recording,
        tickEvent: "finished"
      )
    )

    try await runtime.transact(
      InstantStoreTransaction(id: meetingTransactionID, operations: save.operations),
      createdAt: recordedAt,
      source: "validation.syncups.recording.meeting"
    )
    let savedMeetings = try await meetings(runtime: runtime, syncUpID: syncUp.id)
    guard savedMeetings.map(\.transcript) == [save.transcript] else {
      throw recordingStateError(
        operation: "validate sync-up meeting save",
        message: "Expected the saved meeting transcript to round-trip through the local runtime.",
        recovery: "Inspect SyncUpsExample.recordMeetingOperations and meeting decoding."
      )
    }
    evidence.append(
      try await evidenceRow(
        event: "meeting-save",
        runtime: runtime,
        cacheURL: cacheURL,
        timestamp: timestamp,
        recording: recording
      )
    )

    let openSettings = SyncUpsRecordingOpenSettingsRecorder()
    var deniedModel = SyncUpRecordingModel(
      syncUp: syncUp,
      attendees: attendees,
      speechClient: .denied,
      openSettingsClient: SyncUpOpenSettingsClient {
        await openSettings.open()
      }
    )
    await deniedModel.task()
    guard deniedModel.alert == .speechRecognitionDenied else {
      throw recordingStateError(
        operation: "validate denied sync-up speech",
        message: "Expected denied speech recognition to present the settings alert.",
        recovery: "Inspect SyncUpSpeechClient.denied and alert handling."
      )
    }
    let outcome = await deniedModel.alertButtonTapped(.openSettings)
    let openSettingsCount = await openSettings.openCount()
    guard outcome == .settingsOpened, openSettingsCount == 1 else {
      throw recordingStateError(
        operation: "validate sync-up open settings",
        message: "Expected tapping Open Settings to call the injected settings dependency once.",
        recovery: "Inspect SyncUpOpenSettingsClient wiring."
      )
    }
    evidence.append(
      try await evidenceRow(
        event: "settings-open",
        runtime: runtime,
        cacheURL: cacheURL,
        timestamp: timestamp,
        recording: SyncUpRecordingSummary(model: deniedModel),
        alertOutcome: outcome,
        openSettingsCount: openSettingsCount
      )
    )

    let relaunchedRuntime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: appID,
        persistenceURL: cacheURL,
        initialAttributes: SyncUpsExample.attributes,
        now: timestamp,
        makeID: makeID
      )
    )
    let relaunchedMeetings = try await meetings(runtime: relaunchedRuntime, syncUpID: syncUp.id)
    guard relaunchedMeetings == savedMeetings else {
      throw recordingStateError(
        operation: "validate sync-up meeting relaunch",
        message: "Expected the saved meeting transcript to restore after a fresh runtime bootstrap.",
        recovery: "Inspect SyncUps meeting persistence and SQLite query restoration."
      )
    }
    evidence.append(
      try await evidenceRow(
        event: "relaunch",
        runtime: relaunchedRuntime,
        cacheURL: cacheURL,
        timestamp: timestamp,
        recording: recording
      )
    )

    return SyncUpsRecordingValidationResult(
      appID: appID,
      cacheURL: cacheURL,
      syncUpID: syncUp.id,
      attendeeIDs: attendees.map(\.id),
      meetingID: meetingID,
      evidence: evidence
    )
  }

  private static func evidenceRow(
    event: String,
    runtime: InstantRuntime,
    cacheURL: URL,
    timestamp: @escaping @Sendable () -> InstantTimestamp,
    recording: SyncUpRecordingSummary? = nil,
    tickEvent: String? = nil,
    alertOutcome: SyncUpRecordingAlertOutcome? = nil,
    openSettingsCount: Int = 0
  ) async throws -> ValidationEvidenceRow<SyncUpsRecordingValidationDetails> {
    let syncUps = try await syncUps(runtime: runtime)
    let attendees = try await attendees(runtime: runtime)
    let meetings = try await meetings(runtime: runtime)
    let pending = await runtime.pendingMutations()
    return ValidationEvidenceRow(
      caseID: "validation.syncups.recording",
      side: "swift",
      event: event,
      appID: runtime.configuration.appID,
      timestampMs: timestamp().milliseconds,
      ok: true,
      details: SyncUpsRecordingValidationDetails(
        cachePath: cacheURL.path,
        syncUpIDs: syncUps.map(\.id),
        syncUpTitles: syncUps.map(\.title),
        attendeeIDs: attendees.map(\.id),
        attendeeNames: attendees.map(\.name),
        meetingIDs: meetings.map(\.id),
        meetingTranscripts: meetings.map(\.transcript),
        pendingMutationIDs: pending.map(\.id),
        recording: recording,
        tickEvent: tickEvent,
        alertOutcome: alertOutcome,
        openSettingsCount: openSettingsCount
      )
    )
  }

  private static func syncUps(runtime: InstantRuntime) async throws -> [SyncUpRecord] {
    try SyncUpsExample.decodeSyncUps(
      (try await runtime.queryOnce(SyncUpsExample.syncUpsQuery)).values
    )
  }

  private static func attendees(runtime: InstantRuntime) async throws -> [SyncUpAttendeeRecord] {
    try SyncUpsExample.decodeAttendees(
      (try await runtime.queryOnce(SyncUpsExample.attendeesQuery)).values
    )
  }

  private static func meetings(
    runtime: InstantRuntime,
    syncUpID: String? = nil
  ) async throws -> [SyncUpMeetingRecord] {
    let query = syncUpID.map(SyncUpsExample.meetingsForSyncUpQuery) ?? SyncUpsExample.meetingsQuery
    return try SyncUpsExample.decodeMeetings(
      (try await runtime.queryOnce(query)).values
    )
  }

  private static func recordingStateError(
    operation: String,
    message: String,
    recovery: String
  ) -> InstantError {
    InstantError(
      code: .validationFailed,
      operation: operation,
      message: message,
      recovery: recovery
    )
  }
}

private actor SyncUpsRecordingOpenSettingsRecorder {
  private var count = 0

  func open() {
    count += 1
  }

  func openCount() -> Int {
    count
  }
}
