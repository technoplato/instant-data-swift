import Foundation
import InstantSwiftDataCLIParsing
import InstantSwiftDataCore
import InstantSwiftDataTesting

@main
struct InstantSwiftDataValidationRunner {
  static func main() async {
    do {
      try await run()
    } catch let error as ValidationFailure {
      emit(
        caseID: error.caseID,
        event: "failed",
        ok: false,
        appID: error.appID,
        details: ["message": error.message]
      )
      exit(1)
    } catch let error as CLIValidationRunnerArgumentError {
      emit(
        caseID: "validation.arguments",
        event: "failed",
        ok: false,
        appID: CLIValidationRunnerInvocation.localTodos.appID,
        details: ["message": error.description]
      )
      exit(1)
    } catch {
      let caseID = requestedCaseID()
      emit(
        caseID: caseID,
        event: "failed",
        ok: false,
        appID: requestedAppID(),
        details: ["message": String(describing: error)]
      )
      exit(1)
    }
  }

  private static func requestedCaseID() -> String {
    (try? CLIValidationRunnerArguments.parse(Array(CommandLine.arguments.dropFirst())))?.caseID
      ?? "validation.arguments"
  }

  private static func requestedAppID() -> String {
    (try? CLIValidationRunnerArguments.parse(Array(CommandLine.arguments.dropFirst())))?.appID
      ?? CLIValidationRunnerInvocation.localTodos.appID
  }

  private static func run() async throws {
    let arguments = Array(CommandLine.arguments.dropFirst())
    let invocation = try CLIValidationRunnerArguments.parse(arguments)

    if ProcessInfo.processInfo.environment["INSTANT_SWIFT_DATA_VALIDATION_RUNNER_FAIL_CASE"]
      == invocation.caseID
    {
      throw ForcedValidationRunnerFailure(caseID: invocation.caseID)
    }

    switch invocation {
    case .localIntegrations:
      let result = try await InstantSwiftDataLocalIntegrationValidation.run(
        appID: invocation.appID
      )
      for row in result.evidence {
        try writeJSONLine(row)
      }

    case .reminders:
      let result = try await InstantSwiftDataRemindersValidation.run(appID: invocation.appID)
      for row in result.evidence {
        try writeJSONLine(row)
      }

    case .serverTransactionLoopback:
      let run = try await InstantSwiftDataTestHarness.runServerTransactionLoopbackValidation(
        appID: invocation.appID
      )
      for row in run.result.evidence {
        try writeJSONLine(row)
      }

    case .cloudKitDemo:
      let run = try await InstantSwiftDataTestHarness.runCloudKitDemoValidation(
        appID: invocation.appID
      )
      for row in run.result.evidence {
        try writeJSONLine(row)
      }

    case .liveSession:
      do {
        let run = try await InstantSwiftDataTestHarness.runLiveSessionValidation(
          appID: invocation.appID
        )
        for row in run.result.evidence {
          try writeJSONLine(row)
        }
      } catch let failure as LiveSessionValidationFailure {
        for row in failure.evidence {
          try writeJSONLine(row)
        }
        throw failure
      }

    case .liveTransaction:
      do {
        let run = try await InstantSwiftDataTestHarness.runLiveSessionValidation(
          appID: invocation.appID,
          caseID: invocation.caseID,
          includeTransaction: true
        )
        for row in run.result.evidence {
          try writeJSONLine(row)
        }
      } catch let failure as LiveSessionValidationFailure {
        for row in failure.evidence {
          try writeJSONLine(row)
        }
        throw failure
      }

    case .liveObserve:
      do {
        let run = try await InstantSwiftDataTestHarness.runLiveSessionValidation(
          appID: invocation.appID,
          caseID: invocation.caseID
        )
        for row in run.result.evidence {
          try writeJSONLine(row)
        }
      } catch let failure as LiveSessionValidationFailure {
        for row in failure.evidence {
          try writeJSONLine(row)
        }
        throw failure
      }

    case .liveSharing:
      let environment = ProcessInfo.processInfo.environment
      let appID = try requiredEnvironment("INSTANT_APP_ID", environment: environment)
      let refreshToken = try requiredEnvironment(
        "INSTANT_SWIFT_DATA_SHARING_REFRESH_TOKEN",
        environment: environment
      )
      let readerUserID = try requiredEnvironment(
        "INSTANT_SWIFT_DATA_SHARING_USER_ID",
        environment: environment
      )
      let listID = try requiredEnvironment(
        "INSTANT_SWIFT_DATA_SHARING_LIST_ID",
        environment: environment
      )
      let expectedValue = try requiredDoubleEnvironment(
        "INSTANT_SWIFT_DATA_SHARING_EXPECTED_VALUE",
        environment: environment
      )
      let rejectedValue = try requiredDoubleEnvironment(
        "INSTANT_SWIFT_DATA_SHARING_REJECTED_VALUE",
        environment: environment
      )
      let websocketURI =
        URL(
          string: environment["INSTANT_WEBSOCKET_URI"]
            ?? InstantRuntimeConfiguration.defaultWebSocketURI.absoluteString
        ) ?? InstantRuntimeConfiguration.defaultWebSocketURI
      let row = try await InstantSharingLiveValidation.run(
        appID: appID,
        websocketURI: websocketURI,
        refreshToken: refreshToken,
        readerUserID: readerUserID,
        listID: listID,
        expectedServerValue: expectedValue,
        rejectedOptimisticValue: rejectedValue
      )
      try writeJSONLine(row)

    case .liveSharingWriter:
      let environment = ProcessInfo.processInfo.environment
      let appID = try requiredEnvironment("INSTANT_APP_ID", environment: environment)
      let refreshToken = try requiredEnvironment(
        "INSTANT_SWIFT_DATA_SHARING_REFRESH_TOKEN",
        environment: environment
      )
      let writerUserID = try requiredEnvironment(
        "INSTANT_SWIFT_DATA_SHARING_USER_ID",
        environment: environment
      )
      let listID = try requiredEnvironment(
        "INSTANT_SWIFT_DATA_SHARING_LIST_ID",
        environment: environment
      )
      let expectedValue = try requiredDoubleEnvironment(
        "INSTANT_SWIFT_DATA_SHARING_EXPECTED_VALUE",
        environment: environment
      )
      let acceptedValue = try requiredDoubleEnvironment(
        "INSTANT_SWIFT_DATA_SHARING_ACCEPTED_VALUE",
        environment: environment
      )
      let websocketURI =
        URL(
          string: environment["INSTANT_WEBSOCKET_URI"]
            ?? InstantRuntimeConfiguration.defaultWebSocketURI.absoluteString
        ) ?? InstantRuntimeConfiguration.defaultWebSocketURI
      let row = try await InstantSharingLiveValidation.runWriter(
        appID: appID,
        websocketURI: websocketURI,
        refreshToken: refreshToken,
        writerUserID: writerUserID,
        listID: listID,
        expectedServerValue: expectedValue,
        acceptedValue: acceptedValue
      )
      try writeJSONLine(row)

    case .liveVoiceTrailRecordingsList:
      let environment = ProcessInfo.processInfo.environment
      let appID = try requiredEnvironment(
        "INSTANT_APP_ID",
        environment: environment,
        caseID: invocation.caseID
      )
      let refreshToken = try requiredEnvironment(
        "INSTANT_SWIFT_DATA_RECORDINGS_REFRESH_TOKEN",
        environment: environment,
        caseID: invocation.caseID
      )
      let viewerUserID = try requiredEnvironment(
        "INSTANT_SWIFT_DATA_RECORDINGS_VIEWER_USER_ID",
        environment: environment,
        caseID: invocation.caseID
      )
      let recordingID = try requiredEnvironment(
        "INSTANT_SWIFT_DATA_RECORDINGS_RECORDING_ID",
        environment: environment,
        caseID: invocation.caseID
      )
      let rawMode = try requiredEnvironment(
        "INSTANT_SWIFT_DATA_RECORDINGS_MODE",
        environment: environment,
        caseID: invocation.caseID
      )
      guard let mode = InstantVoiceTrailRecordingsListValidationMode(rawValue: rawMode) else {
        throw ValidationFailure(
          caseID: invocation.caseID,
          appID: appID,
          message: "Expected INSTANT_SWIFT_DATA_RECORDINGS_MODE to be owner or member."
        )
      }
      let websocketURI =
        URL(
          string: environment["INSTANT_WEBSOCKET_URI"]
            ?? InstantRuntimeConfiguration.defaultWebSocketURI.absoluteString
        ) ?? InstantRuntimeConfiguration.defaultWebSocketURI
      let rows = InstantVoiceTrailRecordingsListLiveValidation.run(
        appID: appID,
        websocketURI: websocketURI,
        refreshToken: refreshToken,
        viewerUserID: viewerUserID,
        recordingID: recordingID,
        mode: mode
      )
      for try await row in rows {
        try writeJSONLine(row)
      }

    case .liveVoiceTrailV3Capture:
      let environment = ProcessInfo.processInfo.environment
      let appID = try requiredEnvironment(
        "INSTANT_APP_ID",
        environment: environment,
        caseID: invocation.caseID
      )
      let refreshToken = try requiredEnvironment(
        "INSTANT_SWIFT_DATA_VOICE_TRAIL_V3_REFRESH_TOKEN",
        environment: environment,
        caseID: invocation.caseID
      )
      let userID = try requiredEnvironment(
        "INSTANT_SWIFT_DATA_VOICE_TRAIL_V3_USER_ID",
        environment: environment,
        caseID: invocation.caseID
      )
      let recordingID = try requiredEnvironment(
        "INSTANT_SWIFT_DATA_VOICE_TRAIL_V3_RECORDING_ID",
        environment: environment,
        caseID: invocation.caseID
      )
      let transcriptionID = try requiredEnvironment(
        "INSTANT_SWIFT_DATA_VOICE_TRAIL_V3_TRANSCRIPTION_ID",
        environment: environment,
        caseID: invocation.caseID
      )
      let attachmentID = try requiredEnvironment(
        "INSTANT_SWIFT_DATA_VOICE_TRAIL_V3_ATTACHMENT_ID",
        environment: environment,
        caseID: invocation.caseID
      )
      let title = try requiredEnvironment(
        "INSTANT_SWIFT_DATA_VOICE_TRAIL_V3_TITLE",
        environment: environment,
        caseID: invocation.caseID
      )
      let deviceID = try requiredEnvironment(
        "INSTANT_SWIFT_DATA_VOICE_TRAIL_V3_DEVICE_ID",
        environment: environment,
        caseID: invocation.caseID
      )
      let attachmentKind = try requiredEnvironment(
        "INSTANT_SWIFT_DATA_VOICE_TRAIL_V3_ATTACHMENT_KIND",
        environment: environment,
        caseID: invocation.caseID
      )
      let attachmentContents = try requiredEnvironment(
        "INSTANT_SWIFT_DATA_VOICE_TRAIL_V3_ATTACHMENT_CONTENTS",
        environment: environment,
        caseID: invocation.caseID
      )
      let attachmentOffsetMilliseconds = try requiredIntEnvironment(
        "INSTANT_SWIFT_DATA_VOICE_TRAIL_V3_ATTACHMENT_OFFSET_MILLISECONDS",
        environment: environment,
        caseID: invocation.caseID
      )
      let durationMilliseconds = try requiredIntEnvironment(
        "INSTANT_SWIFT_DATA_VOICE_TRAIL_V3_DURATION_MILLISECONDS",
        environment: environment,
        caseID: invocation.caseID
      )
      let apiURI =
        URL(
          string: environment["INSTANT_API_URI"]
            ?? InstantRuntimeConfiguration.defaultAPIURI.absoluteString
        ) ?? InstantRuntimeConfiguration.defaultAPIURI
      let websocketURI =
        URL(
          string: environment["INSTANT_WEBSOCKET_URI"]
            ?? InstantRuntimeConfiguration.defaultWebSocketURI.absoluteString
        ) ?? InstantRuntimeConfiguration.defaultWebSocketURI
      let row = try await InstantVoiceTrailV3CaptureLiveValidation.run(
        appID: appID,
        apiURI: apiURI,
        websocketURI: websocketURI,
        refreshToken: refreshToken,
        expectedUserID: userID,
        recordingID: recordingID,
        transcriptionID: transcriptionID,
        attachmentID: attachmentID,
        title: title,
        deviceID: deviceID,
        attachmentKind: attachmentKind,
        attachmentContents: attachmentContents,
        attachmentOffsetMilliseconds: attachmentOffsetMilliseconds,
        durationMilliseconds: durationMilliseconds
      )
      try writeJSONLine(row)

    case .liveTodosV3Write, .liveTodosV3Observe:
      let environment = ProcessInfo.processInfo.environment
      let appID = try requiredEnvironment(
        "INSTANT_APP_ID",
        environment: environment,
        caseID: invocation.caseID
      )
      let refreshToken = try requiredEnvironment(
        "INSTANT_SWIFT_DATA_TODOS_V3_REFRESH_TOKEN",
        environment: environment,
        caseID: invocation.caseID
      )
      let userID = try requiredEnvironment(
        "INSTANT_SWIFT_DATA_TODOS_V3_USER_ID",
        environment: environment,
        caseID: invocation.caseID
      )
      let id = try requiredEnvironment(
        "INSTANT_SWIFT_DATA_TODOS_V3_ID",
        environment: environment,
        caseID: invocation.caseID
      )
      let text = try requiredEnvironment(
        "INSTANT_SWIFT_DATA_TODOS_V3_TEXT",
        environment: environment,
        caseID: invocation.caseID
      )
      let createdAtMilliseconds = try requiredIntEnvironment(
        "INSTANT_SWIFT_DATA_TODOS_V3_CREATED_AT_MILLISECONDS",
        environment: environment,
        caseID: invocation.caseID
      )
      let apiURI =
        URL(
          string: environment["INSTANT_API_URI"]
            ?? InstantRuntimeConfiguration.defaultAPIURI.absoluteString
        ) ?? InstantRuntimeConfiguration.defaultAPIURI
      let websocketURI =
        URL(
          string: environment["INSTANT_WEBSOCKET_URI"]
            ?? InstantRuntimeConfiguration.defaultWebSocketURI.absoluteString
        ) ?? InstantRuntimeConfiguration.defaultWebSocketURI

      switch invocation {
      case .liveTodosV3Write:
        let offlineID = try requiredEnvironment(
          "INSTANT_SWIFT_DATA_TODOS_V3_OFFLINE_ID",
          environment: environment,
          caseID: invocation.caseID
        )
        let offlineText = try requiredEnvironment(
          "INSTANT_SWIFT_DATA_TODOS_V3_OFFLINE_TEXT",
          environment: environment,
          caseID: invocation.caseID
        )
        let offlineCreatedAtMilliseconds = try requiredIntEnvironment(
          "INSTANT_SWIFT_DATA_TODOS_V3_OFFLINE_CREATED_AT_MILLISECONDS",
          environment: environment,
          caseID: invocation.caseID
        )
        let row = try await InstantTodosV3LiveValidation.write(
          appID: appID,
          apiURI: apiURI,
          websocketURI: websocketURI,
          refreshToken: refreshToken,
          expectedUserID: userID,
          id: id,
          text: text,
          createdAtMilliseconds: Int64(createdAtMilliseconds),
          offlineID: offlineID,
          offlineText: offlineText,
          offlineCreatedAtMilliseconds: Int64(offlineCreatedAtMilliseconds)
        )
        try writeJSONLine(row)

      case .liveTodosV3Observe:
        let rows = InstantTodosV3LiveValidation.observe(
          appID: appID,
          apiURI: apiURI,
          websocketURI: websocketURI,
          refreshToken: refreshToken,
          expectedUserID: userID,
          id: id,
          text: text,
          createdAtMilliseconds: Int64(createdAtMilliseconds)
        )
        for try await row in rows {
          try writeJSONLine(row)
        }

      default:
        preconditionFailure("Unexpected Todos V3 runner mode.")
      }

    case .liveAuthInvalidation:
      let environment = ProcessInfo.processInfo.environment
      let appID = try requiredEnvironment("INSTANT_APP_ID", environment: environment)
      let refreshToken = try requiredEnvironment(
        "INSTANT_SWIFT_DATA_AUTH_REFRESH_TOKEN",
        environment: environment
      )
      let userID = try requiredEnvironment(
        "INSTANT_SWIFT_DATA_AUTH_USER_ID",
        environment: environment
      )
      let apiURI =
        URL(
          string: environment["INSTANT_API_URI"]
            ?? InstantRuntimeConfiguration.defaultAPIURI.absoluteString
        ) ?? InstantRuntimeConfiguration.defaultAPIURI
      let row = try await InstantAuthLiveValidation.run(
        appID: appID,
        apiURI: apiURI,
        refreshToken: refreshToken,
        expectedUserID: userID
      )
      try writeJSONLine(row)

    case .liveAuthV3App:
      let environment = ProcessInfo.processInfo.environment
      let appID = try requiredEnvironment("INSTANT_APP_ID", environment: environment)
      let refreshToken = try requiredEnvironment(
        "INSTANT_SWIFT_DATA_AUTH_REFRESH_TOKEN",
        environment: environment
      )
      let userID = try requiredEnvironment(
        "INSTANT_SWIFT_DATA_AUTH_USER_ID",
        environment: environment
      )
      let apiURI =
        URL(
          string: environment["INSTANT_API_URI"]
            ?? InstantRuntimeConfiguration.defaultAPIURI.absoluteString
        ) ?? InstantRuntimeConfiguration.defaultAPIURI
      let row = try await InstantAuthV3AppLiveValidation.run(
        appID: appID,
        apiURI: apiURI,
        refreshToken: refreshToken,
        expectedUserID: userID
      )
      try writeJSONLine(row)

    case .livePlaybackRoom:
      let environment = ProcessInfo.processInfo.environment
      let appID = try requiredEnvironment("INSTANT_APP_ID", environment: environment)
      let refreshToken = try requiredEnvironment(
        "INSTANT_SWIFT_DATA_PLAYBACK_REFRESH_TOKEN",
        environment: environment
      )
      let swiftUserID = try requiredEnvironment(
        "INSTANT_SWIFT_DATA_PLAYBACK_SWIFT_USER_ID",
        environment: environment
      )
      let typeScriptUserID = try requiredEnvironment(
        "INSTANT_SWIFT_DATA_PLAYBACK_TYPESCRIPT_USER_ID",
        environment: environment
      )
      let roomID = try requiredEnvironment(
        "INSTANT_SWIFT_DATA_PLAYBACK_ROOM_ID",
        environment: environment
      )
      let apiURI =
        URL(
          string: environment["INSTANT_API_URI"]
            ?? InstantRuntimeConfiguration.defaultAPIURI.absoluteString
        ) ?? InstantRuntimeConfiguration.defaultAPIURI
      let websocketURI =
        URL(
          string: environment["INSTANT_WEBSOCKET_URI"]
            ?? InstantRuntimeConfiguration.defaultWebSocketURI.absoluteString
        ) ?? InstantRuntimeConfiguration.defaultWebSocketURI
      let row = try await InstantPlaybackRoomLiveValidation.run(
        appID: appID,
        apiURI: apiURI,
        websocketURI: websocketURI,
        refreshToken: refreshToken,
        swiftUserID: swiftUserID,
        typeScriptUserID: typeScriptUserID,
        roomID: roomID
      )
      try writeJSONLine(row)

    case .livePreferences:
      let environment = ProcessInfo.processInfo.environment
      let appID = try requiredEnvironment(
        "INSTANT_APP_ID",
        environment: environment,
        caseID: invocation.caseID
      )
      let refreshToken = try requiredEnvironment(
        "INSTANT_SWIFT_DATA_PREFERENCES_REFRESH_TOKEN",
        environment: environment,
        caseID: invocation.caseID
      )
      let expectedUserID = try requiredEnvironment(
        "INSTANT_SWIFT_DATA_PREFERENCES_USER_ID",
        environment: environment,
        caseID: invocation.caseID
      )
      let apiURI = URL(
        string: environment["INSTANT_API_URI"] ?? "https://api.instantdb.com"
      )!
      let websocketURI = URL(
        string: environment["INSTANT_WEBSOCKET_URI"]
          ?? "wss://api.instantdb.com/runtime/session"
      )!
      let persistenceURL = environment["INSTANT_SWIFT_DATA_PREFERENCES_PERSISTENCE_PATH"]
        .map { URL(fileURLWithPath: $0) }
      let row = try await InstantPreferencesLiveValidation.run(
        appID: appID,
        apiURI: apiURI,
        websocketURI: websocketURI,
        refreshToken: refreshToken,
        expectedUserID: expectedUserID,
        persistenceURL: persistenceURL
      )
      try writeJSONLine(row)

    case .typedDrafts:
      let run = try await InstantSwiftDataTestHarness.runDraftValidation()
      for row in run.result.evidence {
        try writeJSONLine(row)
      }

    case .platformAdapters:
      let result = try await InstantSwiftDataPlatformAdapterValidation.run(
        appID: invocation.appID
      )
      for row in result.evidence {
        try writeJSONLine(row)
      }

    case .syncUpsRecording:
      let run = try await InstantSwiftDataTestHarness.runSyncUpsRecordingValidation()
      for row in run.result.evidence {
        try writeJSONLine(row)
      }

    case .parityReport:
      let run = try InstantSwiftDataTestHarness.runParityCoverageValidation(
        artifactsDirectory: validationCoverageArtifactsDirectory()
      )
      for row in run.result.evidenceRows(appID: run.summary.appID ?? "local-validation") {
        try writeJSONLine(row)
      }

    case .coverage:
      let run = try InstantSwiftDataTestHarness.runParityCoverageValidation(
        artifactsDirectory: validationCoverageArtifactsDirectory()
      )
      let summary = InstantParityCoverageSummary(run.result)
      try writeJSONLine(
        ValidationEvidenceRow(
          caseID: "validation.coverage",
          side: "swift",
          event: "coverage-summary",
          appID: run.summary.appID ?? "local-validation",
          timestampMs: 0,
          ok: summary.ok,
          details: summary
        )
      )

    case .localTodos:
      let run = try await InstantSwiftDataTestHarness.runLocalTodoValidation()
      for row in run.result.evidence {
        try writeJSONLine(row)
      }
    }
  }

  private static func validationCoverageArtifactsDirectory() -> URL? {
    guard
      let path = trimmedEnvironmentValue("INSTANT_SWIFT_DATA_COVERAGE_ARTIFACTS_DIR")
        ?? trimmedEnvironmentValue("INSTANT_SWIFT_DATA_VALIDATION_RESULTS_DIR")
    else {
      return nil
    }
    return URL(fileURLWithPath: path, isDirectory: true)
  }

  private static func trimmedEnvironmentValue(_ key: String) -> String? {
    let value = ProcessInfo.processInfo.environment[key]?
      .trimmingCharacters(in: .whitespacesAndNewlines)
    guard let value, !value.isEmpty else { return nil }
    return value
  }

  private static func requiredEnvironment(
    _ key: String,
    environment: [String: String],
    caseID: String = "validation.live.sharing"
  ) throws -> String {
    guard let value = environment[key]?.trimmingCharacters(in: .whitespacesAndNewlines),
      !value.isEmpty
    else {
      throw ValidationFailure(
        caseID: caseID,
        appID: environment["INSTANT_APP_ID"] ?? "live-sharing-validation",
        message: "Missing \(key)."
      )
    }
    return value
  }

  private static func requiredDoubleEnvironment(
    _ key: String,
    environment: [String: String]
  ) throws -> Double {
    let value = try requiredEnvironment(key, environment: environment)
    guard let number = Double(value), number.isFinite else {
      throw ValidationFailure(
        caseID: "validation.live.sharing",
        appID: environment["INSTANT_APP_ID"] ?? "live-sharing-validation",
        message: "Expected \(key) to be a finite number."
      )
    }
    return number
  }

  private static func requiredIntEnvironment(
    _ key: String,
    environment: [String: String],
    caseID: String
  ) throws -> Int {
    let value = try requiredEnvironment(key, environment: environment, caseID: caseID)
    guard let number = Int(value) else {
      throw ValidationFailure(
        caseID: caseID,
        appID: environment["INSTANT_APP_ID"] ?? "live-validation",
        message: "Expected \(key) to be an integer."
      )
    }
    return number
  }

  private static func emit(
    caseID: String,
    event: String,
    ok: Bool,
    appID: String,
    details: [String: String]
  ) {
    let row = ValidationEvidenceRow(
      caseID: caseID,
      side: "swift",
      event: event,
      appID: appID,
      entityID: nil,
      timestampMs: Int64((Date().timeIntervalSince1970 * 1000).rounded()),
      ok: ok,
      details: details
    )
    try? writeJSONLine(row)
  }

  private static func writeJSONLine<Value: Encodable>(_ value: Value) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let data = try encoder.encode(value)
    FileHandle.standardOutput.write(data)
    FileHandle.standardOutput.write(Data("\n".utf8))
  }
}

private struct ValidationFailure: Error {
  var caseID: String
  var appID: String
  var message: String
}

private struct ForcedValidationRunnerFailure: Error, CustomStringConvertible {
  var caseID: String

  var description: String {
    "Forced validation runner failure for \(caseID)."
  }
}
