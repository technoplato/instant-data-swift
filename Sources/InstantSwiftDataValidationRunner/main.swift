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

    case .liveMobileChatV3Write, .liveMobileChatV3Observe:
      let environment = ProcessInfo.processInfo.environment
      let appID = try requiredEnvironment(
        "INSTANT_APP_ID",
        environment: environment,
        caseID: invocation.caseID
      )
      let refreshToken = try requiredEnvironment(
        "INSTANT_SWIFT_DATA_MOBILE_CHAT_V3_REFRESH_TOKEN",
        environment: environment,
        caseID: invocation.caseID
      )
      let userID = try requiredEnvironment(
        "INSTANT_SWIFT_DATA_MOBILE_CHAT_V3_USER_ID",
        environment: environment,
        caseID: invocation.caseID
      )
      let profileID = try requiredEnvironment(
        "INSTANT_SWIFT_DATA_MOBILE_CHAT_V3_PROFILE_ID",
        environment: environment,
        caseID: invocation.caseID
      )
      let displayName = try requiredEnvironment(
        "INSTANT_SWIFT_DATA_MOBILE_CHAT_V3_DISPLAY_NAME",
        environment: environment,
        caseID: invocation.caseID
      )
      let channelID = try requiredEnvironment(
        "INSTANT_SWIFT_DATA_MOBILE_CHAT_V3_CHANNEL_ID",
        environment: environment,
        caseID: invocation.caseID
      )
      let channelName = try requiredEnvironment(
        "INSTANT_SWIFT_DATA_MOBILE_CHAT_V3_CHANNEL_NAME",
        environment: environment,
        caseID: invocation.caseID
      )
      let messageID = try requiredEnvironment(
        "INSTANT_SWIFT_DATA_MOBILE_CHAT_V3_MESSAGE_ID",
        environment: environment,
        caseID: invocation.caseID
      )
      let content = try requiredEnvironment(
        "INSTANT_SWIFT_DATA_MOBILE_CHAT_V3_CONTENT",
        environment: environment,
        caseID: invocation.caseID
      )
      let timestampMilliseconds = try requiredIntEnvironment(
        "INSTANT_SWIFT_DATA_MOBILE_CHAT_V3_TIMESTAMP_MILLISECONDS",
        environment: environment,
        caseID: invocation.caseID
      )
      let apiURI = URL(
        string: environment["INSTANT_API_URI"]
          ?? InstantRuntimeConfiguration.defaultAPIURI.absoluteString
      ) ?? InstantRuntimeConfiguration.defaultAPIURI
      let websocketURI = URL(
        string: environment["INSTANT_WEBSOCKET_URI"]
          ?? InstantRuntimeConfiguration.defaultWebSocketURI.absoluteString
      ) ?? InstantRuntimeConfiguration.defaultWebSocketURI

      switch invocation {
      case .liveMobileChatV3Write:
        let peerProfileID = try requiredEnvironment(
          "INSTANT_SWIFT_DATA_MOBILE_CHAT_V3_PEER_PROFILE_ID",
          environment: environment,
          caseID: invocation.caseID
        )
        let row = try await InstantMobileChatV3LiveValidation.write(
          appID: appID,
          apiURI: apiURI,
          websocketURI: websocketURI,
          refreshToken: refreshToken,
          expectedUserID: userID,
          profileID: profileID,
          displayName: displayName,
          channelID: channelID,
          channelName: channelName,
          messageID: messageID,
          content: content,
          timestampMilliseconds: Int64(timestampMilliseconds),
          expectedPeerProfileID: peerProfileID
        )
        try writeJSONLine(row)

      case .liveMobileChatV3Observe:
        let rows = InstantMobileChatV3LiveValidation.observe(
          appID: appID,
          apiURI: apiURI,
          websocketURI: websocketURI,
          refreshToken: refreshToken,
          expectedUserID: userID,
          profileID: profileID,
          displayName: displayName,
          channelID: channelID,
          channelName: channelName,
          messageID: messageID,
          content: content,
          timestampMilliseconds: Int64(timestampMilliseconds)
        )
        for try await row in rows {
          try writeJSONLine(row)
        }

      default:
        preconditionFailure("Unexpected Mobile Chat V3 runner mode.")
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

    case .liveTypingIndicatorV3:
      let environment = ProcessInfo.processInfo.environment
      let appID = try requiredEnvironment("INSTANT_APP_ID", environment: environment)
      let refreshToken = try requiredEnvironment(
        "INSTANT_SWIFT_DATA_TYPING_INDICATOR_REFRESH_TOKEN",
        environment: environment
      )
      let swiftUserID = try requiredEnvironment(
        "INSTANT_SWIFT_DATA_TYPING_INDICATOR_SWIFT_USER_ID",
        environment: environment
      )
      let typeScriptUserID = try requiredEnvironment(
        "INSTANT_SWIFT_DATA_TYPING_INDICATOR_TYPESCRIPT_USER_ID",
        environment: environment
      )
      let roomID = try requiredEnvironment(
        "INSTANT_SWIFT_DATA_TYPING_INDICATOR_ROOM_ID",
        environment: environment
      )
      let apiURI = URL(
        string: environment["INSTANT_API_URI"]
          ?? InstantRuntimeConfiguration.defaultAPIURI.absoluteString
      ) ?? InstantRuntimeConfiguration.defaultAPIURI
      let websocketURI = URL(
        string: environment["INSTANT_WEBSOCKET_URI"]
          ?? InstantRuntimeConfiguration.defaultWebSocketURI.absoluteString
      ) ?? InstantRuntimeConfiguration.defaultWebSocketURI
      let row = try await InstantTypingIndicatorV3LiveValidation.run(
        appID: appID,
        apiURI: apiURI,
        websocketURI: websocketURI,
        refreshToken: refreshToken,
        swiftUserID: swiftUserID,
        typeScriptUserID: typeScriptUserID,
        roomID: roomID,
        onFramesObserved: {
          emit(
            caseID: "validation.live.typing-indicator-v3",
            event: "typescript-frames-observed",
            ok: true,
            appID: appID,
            details: ["roomID": roomID]
          )
        }
      )
      try writeJSONLine(row)

    case .liveStreamsV3:
      let environment = ProcessInfo.processInfo.environment
      let appID = try requiredEnvironment("INSTANT_APP_ID", environment: environment)
      let refreshToken = try requiredEnvironment(
        "INSTANT_SWIFT_DATA_STREAMS_REFRESH_TOKEN",
        environment: environment
      )
      let swiftUserID = try requiredEnvironment(
        "INSTANT_SWIFT_DATA_STREAMS_SWIFT_USER_ID",
        environment: environment
      )
      let typeScriptClientID = try requiredEnvironment(
        "INSTANT_SWIFT_DATA_STREAMS_TYPESCRIPT_CLIENT_ID",
        environment: environment
      )
      let swiftClientID = try requiredEnvironment(
        "INSTANT_SWIFT_DATA_STREAMS_SWIFT_CLIENT_ID",
        environment: environment
      )
      let apiURI = URL(
        string: environment["INSTANT_API_URI"]
          ?? InstantRuntimeConfiguration.defaultAPIURI.absoluteString
      ) ?? InstantRuntimeConfiguration.defaultAPIURI
      let websocketURI = URL(
        string: environment["INSTANT_WEBSOCKET_URI"]
          ?? InstantRuntimeConfiguration.defaultWebSocketURI.absoluteString
      ) ?? InstantRuntimeConfiguration.defaultWebSocketURI
      let row = try await InstantStreamsV3LiveValidation.run(
        appID: appID,
        apiURI: apiURI,
        websocketURI: websocketURI,
        refreshToken: refreshToken,
        expectedSwiftUserID: swiftUserID,
        typeScriptClientID: typeScriptClientID,
        swiftClientID: swiftClientID,
        onReaderReady: {
          emit(
            caseID: "validation.live.streams-v3",
            event: "typescript-writer-ready",
            ok: true,
            appID: appID,
            details: ["clientID": typeScriptClientID]
          )
        },
        onSwiftWriterCreated: { streamID in
          emit(
            caseID: "validation.live.streams-v3",
            event: "swift-writer-created",
            ok: true,
            appID: appID,
            details: ["clientID": swiftClientID, "streamID": streamID]
          )
        }
      )
      try writeJSONLine(row)

    case .liveCloudKitDemoV3:
      let environment = ProcessInfo.processInfo.environment
      let appID = try requiredEnvironment("INSTANT_APP_ID", environment: environment)
      let apiURI = URL(
        string: environment["INSTANT_API_URI"]
          ?? InstantRuntimeConfiguration.defaultAPIURI.absoluteString
      ) ?? InstantRuntimeConfiguration.defaultAPIURI
      let websocketURI = URL(
        string: environment["INSTANT_WEBSOCKET_URI"]
          ?? InstantRuntimeConfiguration.defaultWebSocketURI.absoluteString
      ) ?? InstantRuntimeConfiguration.defaultWebSocketURI
      let row = try await InstantCloudKitDemoV3LiveValidation.run(
        appID: appID,
        apiURI: apiURI,
        websocketURI: websocketURI,
        ownerRefreshToken: try requiredEnvironment(
          "INSTANT_SWIFT_DATA_CLOUDKIT_OWNER_REFRESH_TOKEN",
          environment: environment
        ),
        ownerUserID: try requiredEnvironment(
          "INSTANT_SWIFT_DATA_CLOUDKIT_OWNER_USER_ID",
          environment: environment
        ),
        readerRefreshToken: try requiredEnvironment(
          "INSTANT_SWIFT_DATA_CLOUDKIT_READER_REFRESH_TOKEN",
          environment: environment
        ),
        readerUserID: try requiredEnvironment(
          "INSTANT_SWIFT_DATA_CLOUDKIT_READER_USER_ID",
          environment: environment
        ),
        writerUserID: try requiredEnvironment(
          "INSTANT_SWIFT_DATA_CLOUDKIT_WRITER_USER_ID",
          environment: environment
        ),
        counterID: try requiredEnvironment(
          "INSTANT_SWIFT_DATA_CLOUDKIT_COUNTER_ID",
          environment: environment
        ),
        shareID: try requiredEnvironment(
          "INSTANT_SWIFT_DATA_CLOUDKIT_SHARE_ID",
          environment: environment
        ),
        ownerMembershipID: try requiredEnvironment(
          "INSTANT_SWIFT_DATA_CLOUDKIT_OWNER_MEMBERSHIP_ID",
          environment: environment
        ),
        readerMembershipID: try requiredEnvironment(
          "INSTANT_SWIFT_DATA_CLOUDKIT_READER_MEMBERSHIP_ID",
          environment: environment
        ),
        writerMembershipID: try requiredEnvironment(
          "INSTANT_SWIFT_DATA_CLOUDKIT_WRITER_MEMBERSHIP_ID",
          environment: environment
        ),
        onTypeScriptWriterReady: {
          emit(
            caseID: "validation.live.cloudkit-demo-v3",
            event: "typescript-writer-ready",
            ok: true,
            appID: appID,
            details: [
              "counterID": environment["INSTANT_SWIFT_DATA_CLOUDKIT_COUNTER_ID"] ?? ""
            ]
          )
        }
      )
      try writeJSONLine(row)

    case .liveReactionsV3:
      let environment = ProcessInfo.processInfo.environment
      let appID = try requiredEnvironment("INSTANT_APP_ID", environment: environment)
      let refreshToken = try requiredEnvironment(
        "INSTANT_SWIFT_DATA_REACTIONS_REFRESH_TOKEN",
        environment: environment
      )
      let swiftUserID = try requiredEnvironment(
        "INSTANT_SWIFT_DATA_REACTIONS_SWIFT_USER_ID",
        environment: environment
      )
      let roomID = try requiredEnvironment(
        "INSTANT_SWIFT_DATA_REACTIONS_ROOM_ID",
        environment: environment
      )
      let apiURI = URL(
        string: environment["INSTANT_API_URI"]
          ?? InstantRuntimeConfiguration.defaultAPIURI.absoluteString
      ) ?? InstantRuntimeConfiguration.defaultAPIURI
      let websocketURI = URL(
        string: environment["INSTANT_WEBSOCKET_URI"]
          ?? InstantRuntimeConfiguration.defaultWebSocketURI.absoluteString
      ) ?? InstantRuntimeConfiguration.defaultWebSocketURI
      let row = try await InstantReactionsV3LiveValidation.run(
        appID: appID,
        apiURI: apiURI,
        websocketURI: websocketURI,
        refreshToken: refreshToken,
        expectedUserID: swiftUserID,
        roomID: roomID,
        onPayloadsObserved: {
          emit(
            caseID: "validation.live.reactions-v3",
            event: "typescript-payloads-observed",
            ok: true,
            appID: appID,
            details: ["roomID": roomID]
          )
        }
      )
      try writeJSONLine(row)

    case .liveAvatarStackV3:
      let environment = ProcessInfo.processInfo.environment
      let appID = try requiredEnvironment("INSTANT_APP_ID", environment: environment)
      let refreshToken = try requiredEnvironment(
        "INSTANT_SWIFT_DATA_AVATAR_STACK_REFRESH_TOKEN",
        environment: environment
      )
      let swiftUserID = try requiredEnvironment(
        "INSTANT_SWIFT_DATA_AVATAR_STACK_SWIFT_USER_ID",
        environment: environment
      )
      let roomID = try requiredEnvironment(
        "INSTANT_SWIFT_DATA_AVATAR_STACK_ROOM_ID",
        environment: environment
      )
      let apiURI = URL(
        string: environment["INSTANT_API_URI"]
          ?? InstantRuntimeConfiguration.defaultAPIURI.absoluteString
      ) ?? InstantRuntimeConfiguration.defaultAPIURI
      let websocketURI = URL(
        string: environment["INSTANT_WEBSOCKET_URI"]
          ?? InstantRuntimeConfiguration.defaultWebSocketURI.absoluteString
      ) ?? InstantRuntimeConfiguration.defaultWebSocketURI
      let row = try await InstantAvatarStackV3LiveValidation.run(
        appID: appID,
        apiURI: apiURI,
        websocketURI: websocketURI,
        refreshToken: refreshToken,
        expectedUserID: swiftUserID,
        roomID: roomID,
        onPresenceObserved: {
          emit(
            caseID: "validation.live.avatar-stack-v3",
            event: "typescript-presence-observed",
            ok: true,
            appID: appID,
            details: ["roomID": roomID]
          )
        }
      )
      try writeJSONLine(row)

    case .liveCursorsV3:
      let environment = ProcessInfo.processInfo.environment
      let appID = try requiredEnvironment("INSTANT_APP_ID", environment: environment)
      let refreshToken = try requiredEnvironment(
        "INSTANT_SWIFT_DATA_CURSORS_REFRESH_TOKEN",
        environment: environment
      )
      let swiftUserID = try requiredEnvironment(
        "INSTANT_SWIFT_DATA_CURSORS_SWIFT_USER_ID",
        environment: environment
      )
      let roomID = try requiredEnvironment(
        "INSTANT_SWIFT_DATA_CURSORS_ROOM_ID",
        environment: environment
      )
      let apiURI = URL(
        string: environment["INSTANT_API_URI"]
          ?? InstantRuntimeConfiguration.defaultAPIURI.absoluteString
      ) ?? InstantRuntimeConfiguration.defaultAPIURI
      let websocketURI = URL(
        string: environment["INSTANT_WEBSOCKET_URI"]
          ?? InstantRuntimeConfiguration.defaultWebSocketURI.absoluteString
      ) ?? InstantRuntimeConfiguration.defaultWebSocketURI
      let row = try await InstantCursorsV3LiveValidation.run(
        appID: appID,
        apiURI: apiURI,
        websocketURI: websocketURI,
        refreshToken: refreshToken,
        expectedUserID: swiftUserID,
        roomID: roomID,
        onCursorObserved: {
          emit(
            caseID: "validation.live.cursors-v3",
            event: "typescript-cursor-observed",
            ok: true,
            appID: appID,
            details: ["roomID": roomID]
          )
        },
        onCursorCleared: {
          emit(
            caseID: "validation.live.cursors-v3",
            event: "typescript-cursor-cleared",
            ok: true,
            appID: appID,
            details: ["roomID": roomID]
          )
        }
      )
      try writeJSONLine(row)

    case .liveCustomCursorsV3:
      let environment = ProcessInfo.processInfo.environment
      let appID = try requiredEnvironment("INSTANT_APP_ID", environment: environment)
      let refreshToken = try requiredEnvironment(
        "INSTANT_SWIFT_DATA_CUSTOM_CURSORS_REFRESH_TOKEN",
        environment: environment
      )
      let swiftUserID = try requiredEnvironment(
        "INSTANT_SWIFT_DATA_CUSTOM_CURSORS_SWIFT_USER_ID",
        environment: environment
      )
      let roomID = try requiredEnvironment(
        "INSTANT_SWIFT_DATA_CUSTOM_CURSORS_ROOM_ID",
        environment: environment
      )
      let apiURI = URL(
        string: environment["INSTANT_API_URI"]
          ?? InstantRuntimeConfiguration.defaultAPIURI.absoluteString
      ) ?? InstantRuntimeConfiguration.defaultAPIURI
      let websocketURI = URL(
        string: environment["INSTANT_WEBSOCKET_URI"]
          ?? InstantRuntimeConfiguration.defaultWebSocketURI.absoluteString
      ) ?? InstantRuntimeConfiguration.defaultWebSocketURI
      let row = try await InstantCustomCursorsV3LiveValidation.run(
        appID: appID,
        apiURI: apiURI,
        websocketURI: websocketURI,
        refreshToken: refreshToken,
        expectedUserID: swiftUserID,
        roomID: roomID,
        onCursorObserved: {
          emit(
            caseID: "validation.live.custom-cursors-v3",
            event: "typescript-custom-cursor-observed",
            ok: true,
            appID: appID,
            details: ["roomID": roomID]
          )
        },
        onCursorCleared: {
          emit(
            caseID: "validation.live.custom-cursors-v3",
            event: "typescript-custom-cursor-cleared-name-retained",
            ok: true,
            appID: appID,
            details: ["roomID": roomID]
          )
        }
      )
      try writeJSONLine(row)

    case .liveMergeTileGameV3:
      let environment = ProcessInfo.processInfo.environment
      let appID = try requiredEnvironment("INSTANT_APP_ID", environment: environment)
      let refreshToken = try requiredEnvironment(
        "INSTANT_SWIFT_DATA_MERGE_TILE_GAME_REFRESH_TOKEN",
        environment: environment
      )
      let swiftUserID = try requiredEnvironment(
        "INSTANT_SWIFT_DATA_MERGE_TILE_GAME_SWIFT_USER_ID",
        environment: environment
      )
      let apiURI = URL(
        string: environment["INSTANT_API_URI"]
          ?? InstantRuntimeConfiguration.defaultAPIURI.absoluteString
      ) ?? InstantRuntimeConfiguration.defaultAPIURI
      let websocketURI = URL(
        string: environment["INSTANT_WEBSOCKET_URI"]
          ?? InstantRuntimeConfiguration.defaultWebSocketURI.absoluteString
      ) ?? InstantRuntimeConfiguration.defaultWebSocketURI
      let row = try await InstantMergeTileGameV3LiveValidation.run(
        appID: appID,
        apiURI: apiURI,
        websocketURI: websocketURI,
        refreshToken: refreshToken,
        expectedUserID: swiftUserID,
        onSwiftReady: {
          emit(
            caseID: "validation.live.merge-tile-game-v3",
            event: "swift-merge-and-presence-ready",
            ok: true,
            appID: appID,
            details: ["boardID": InstantMergeTileGameV3LiveValidation.boardID]
          )
        },
        onTypeScriptMergeObserved: {
          emit(
            caseID: "validation.live.merge-tile-game-v3",
            event: "typescript-independent-merge-observed",
            ok: true,
            appID: appID,
            details: ["boardID": InstantMergeTileGameV3LiveValidation.boardID]
          )
        },
        onResetObserved: {
          emit(
            caseID: "validation.live.merge-tile-game-v3",
            event: "typescript-reset-observed",
            ok: true,
            appID: appID,
            details: ["boardID": InstantMergeTileGameV3LiveValidation.boardID]
          )
        }
      )
      try writeJSONLine(row)

    case .liveStroopwafelV3:
      let environment = ProcessInfo.processInfo.environment
      let appID = try requiredEnvironment(
        "INSTANT_APP_ID",
        environment: environment,
        caseID: invocation.caseID
      )
      let refreshToken = try requiredEnvironment(
        "INSTANT_SWIFT_DATA_STROOPWAFEL_REFRESH_TOKEN",
        environment: environment,
        caseID: invocation.caseID
      )
      let hostUserID = try requiredEnvironment(
        "INSTANT_SWIFT_DATA_STROOPWAFEL_HOST_USER_ID",
        environment: environment,
        caseID: invocation.caseID
      )
      let guestUserID = try requiredEnvironment(
        "INSTANT_SWIFT_DATA_STROOPWAFEL_GUEST_USER_ID",
        environment: environment,
        caseID: invocation.caseID
      )
      let apiURI = URL(
        string: environment["INSTANT_API_URI"]
          ?? InstantRuntimeConfiguration.defaultAPIURI.absoluteString
      ) ?? InstantRuntimeConfiguration.defaultAPIURI
      let websocketURI = URL(
        string: environment["INSTANT_WEBSOCKET_URI"]
          ?? InstantRuntimeConfiguration.defaultWebSocketURI.absoluteString
      ) ?? InstantRuntimeConfiguration.defaultWebSocketURI
      let row = try await InstantStroopwafelV3LiveValidation.run(
        appID: appID,
        apiURI: apiURI,
        websocketURI: websocketURI,
        refreshToken: refreshToken,
        expectedHostUserID: hostUserID,
        expectedGuestUserID: guestUserID,
        onSwiftRoomReady: {
          emit(
            caseID: "validation.live.stroopwafel-v3",
            event: "swift-room-ready",
            ok: true,
            appID: appID,
            details: ["roomID": InstantStroopwafelV3LiveValidation.roomID]
          )
        },
        onTypeScriptReadyObserved: {
          emit(
            caseID: "validation.live.stroopwafel-v3",
            event: "typescript-ready-observed",
            ok: true,
            appID: appID,
            details: ["roomID": InstantStroopwafelV3LiveValidation.roomID]
          )
        },
        onSwiftGameStarted: {
          emit(
            caseID: "validation.live.stroopwafel-v3",
            event: "swift-game-started",
            ok: true,
            appID: appID,
            details: ["gameID": InstantStroopwafelV3LiveValidation.gameID]
          )
        },
        onTypeScriptPointObserved: {
          emit(
            caseID: "validation.live.stroopwafel-v3",
            event: "typescript-point-observed",
            ok: true,
            appID: appID,
            details: ["pointID": InstantStroopwafelV3LiveValidation.guestPointID]
          )
        },
        onSwiftCompleted: {
          emit(
            caseID: "validation.live.stroopwafel-v3",
            event: "swift-completion-observed",
            ok: true,
            appID: appID,
            details: ["gameID": InstantStroopwafelV3LiveValidation.gameID]
          )
        }
      )
      try writeJSONLine(row)

    case .liveRemindersV3:
      let environment = ProcessInfo.processInfo.environment
      let appID = try requiredEnvironment(
        "INSTANT_APP_ID",
        environment: environment,
        caseID: invocation.caseID
      )
      let refreshToken = try requiredEnvironment(
        "INSTANT_SWIFT_DATA_REMINDERS_REFRESH_TOKEN",
        environment: environment,
        caseID: invocation.caseID
      )
      let ownerUserID = try requiredEnvironment(
        "INSTANT_SWIFT_DATA_REMINDERS_OWNER_USER_ID",
        environment: environment,
        caseID: invocation.caseID
      )
      let ownerEmail = try requiredEnvironment(
        "INSTANT_SWIFT_DATA_REMINDERS_OWNER_EMAIL",
        environment: environment,
        caseID: invocation.caseID
      )
      let ownerDisplayName = try requiredEnvironment(
        "INSTANT_SWIFT_DATA_REMINDERS_OWNER_DISPLAY_NAME",
        environment: environment,
        caseID: invocation.caseID
      )
      let ownerUsername = try requiredEnvironment(
        "INSTANT_SWIFT_DATA_REMINDERS_OWNER_USERNAME",
        environment: environment,
        caseID: invocation.caseID
      )
      let participantUserID = try requiredEnvironment(
        "INSTANT_SWIFT_DATA_REMINDERS_PARTICIPANT_USER_ID",
        environment: environment,
        caseID: invocation.caseID
      )
      let participantEmail = try requiredEnvironment(
        "INSTANT_SWIFT_DATA_REMINDERS_PARTICIPANT_EMAIL",
        environment: environment,
        caseID: invocation.caseID
      )
      let participantDisplayName = try requiredEnvironment(
        "INSTANT_SWIFT_DATA_REMINDERS_PARTICIPANT_DISPLAY_NAME",
        environment: environment,
        caseID: invocation.caseID
      )
      let participantUsername = try requiredEnvironment(
        "INSTANT_SWIFT_DATA_REMINDERS_PARTICIPANT_USERNAME",
        environment: environment,
        caseID: invocation.caseID
      )
      let listID = try requiredEnvironment(
        "INSTANT_SWIFT_DATA_REMINDERS_LIST_ID",
        environment: environment,
        caseID: invocation.caseID
      )
      let swiftReminderID = try requiredEnvironment(
        "INSTANT_SWIFT_DATA_REMINDERS_SWIFT_REMINDER_ID",
        environment: environment,
        caseID: invocation.caseID
      )
      let shareID = try requiredEnvironment(
        "INSTANT_SWIFT_DATA_REMINDERS_SHARE_ID",
        environment: environment,
        caseID: invocation.caseID
      )
      let ownerMembershipID = try requiredEnvironment(
        "INSTANT_SWIFT_DATA_REMINDERS_OWNER_MEMBERSHIP_ID",
        environment: environment,
        caseID: invocation.caseID
      )
      let readerMembershipID = try requiredEnvironment(
        "INSTANT_SWIFT_DATA_REMINDERS_READER_MEMBERSHIP_ID",
        environment: environment,
        caseID: invocation.caseID
      )
      let typeScriptReminderID = try requiredEnvironment(
        "INSTANT_SWIFT_DATA_REMINDERS_TYPESCRIPT_REMINDER_ID",
        environment: environment,
        caseID: invocation.caseID
      )
      let swiftTagID = try requiredEnvironment(
        "INSTANT_SWIFT_DATA_REMINDERS_SWIFT_TAG_ID",
        environment: environment,
        caseID: invocation.caseID
      )
      let typeScriptTagID = try requiredEnvironment(
        "INSTANT_SWIFT_DATA_REMINDERS_TYPESCRIPT_TAG_ID",
        environment: environment,
        caseID: invocation.caseID
      )
      let swiftTagTitle = try requiredEnvironment(
        "INSTANT_SWIFT_DATA_REMINDERS_SWIFT_TAG_TITLE",
        environment: environment,
        caseID: invocation.caseID
      )
      let shareToken = try requiredEnvironment(
        "INSTANT_SWIFT_DATA_REMINDERS_SHARE_TOKEN",
        environment: environment,
        caseID: invocation.caseID
      )
      let apiURI = URL(
        string: environment["INSTANT_API_URI"]
          ?? InstantRuntimeConfiguration.defaultAPIURI.absoluteString
      ) ?? InstantRuntimeConfiguration.defaultAPIURI
      let websocketURI = URL(
        string: environment["INSTANT_WEBSOCKET_URI"]
          ?? InstantRuntimeConfiguration.defaultWebSocketURI.absoluteString
      ) ?? InstantRuntimeConfiguration.defaultWebSocketURI
      let row = try await InstantRemindersV3LiveValidation.run(
        appID: appID,
        apiURI: apiURI,
        websocketURI: websocketURI,
        refreshToken: refreshToken,
        expectedOwnerUserID: ownerUserID,
        expectedOwnerEmail: ownerEmail,
        expectedOwnerDisplayName: ownerDisplayName,
        expectedOwnerUsername: ownerUsername,
        expectedParticipantUserID: participantUserID,
        expectedParticipantEmail: participantEmail,
        expectedParticipantDisplayName: participantDisplayName,
        expectedParticipantUsername: participantUsername,
        listID: listID,
        swiftReminderID: swiftReminderID,
        shareID: shareID,
        ownerMembershipID: ownerMembershipID,
        readerMembershipID: readerMembershipID,
        typeScriptReminderID: typeScriptReminderID,
        swiftTagID: swiftTagID,
        typeScriptTagID: typeScriptTagID,
        swiftTagTitle: swiftTagTitle,
        shareToken: shareToken,
        readerCheckSignalURL: environment["INSTANT_SWIFT_DATA_REMINDERS_READER_CHECK_SIGNAL"]
          .map { URL(fileURLWithPath: $0) },
        onSwiftGraphReady: {
          emit(
            caseID: "validation.live.reminders-v3",
            event: "swift-graph-ready",
            ok: true,
            appID: appID,
            details: ["listID": listID]
          )
        },
        onReaderObserved: {
          emit(
            caseID: "validation.live.reminders-v3",
            event: "typescript-reader-observed",
            ok: true,
            appID: appID,
            details: ["membershipID": readerMembershipID]
          )
        },
        onWriterReady: {
          emit(
            caseID: "validation.live.reminders-v3",
            event: "swift-writer-promotion-ready",
            ok: true,
            appID: appID,
            details: ["membershipID": readerMembershipID]
          )
        },
        onTypeScriptReminderObserved: {
          emit(
            caseID: "validation.live.reminders-v3",
            event: "typescript-reminder-observed",
            ok: true,
            appID: appID,
            details: ["reminderID": typeScriptReminderID]
          )
        }
      )
      try writeJSONLine(row)

    case .liveSyncUpsV3:
      let environment = ProcessInfo.processInfo.environment
      let appID = try requiredEnvironment(
        "INSTANT_APP_ID",
        environment: environment,
        caseID: invocation.caseID
      )
      let refreshToken = try requiredEnvironment(
        "INSTANT_SWIFT_DATA_SYNCUPS_REFRESH_TOKEN",
        environment: environment,
        caseID: invocation.caseID
      )
      let userID = try requiredEnvironment(
        "INSTANT_SWIFT_DATA_SYNCUPS_USER_ID",
        environment: environment,
        caseID: invocation.caseID
      )
      let apiURI = URL(
        string: environment["INSTANT_API_URI"]
          ?? InstantRuntimeConfiguration.defaultAPIURI.absoluteString
      ) ?? InstantRuntimeConfiguration.defaultAPIURI
      let websocketURI = URL(
        string: environment["INSTANT_WEBSOCKET_URI"]
          ?? InstantRuntimeConfiguration.defaultWebSocketURI.absoluteString
      ) ?? InstantRuntimeConfiguration.defaultWebSocketURI
      let row = try await InstantSyncUpsV3LiveValidation.run(
        appID: appID,
        apiURI: apiURI,
        websocketURI: websocketURI,
        refreshToken: refreshToken,
        expectedUserID: userID,
        onSwiftGraphReady: {
          emit(
            caseID: "validation.live.syncups-v3",
            event: "swift-graph-ready",
            ok: true,
            appID: appID,
            details: ["syncUpID": InstantSyncUpsV3LiveValidation.syncUpID]
          )
        },
        onTypeScriptGraphObserved: {
          emit(
            caseID: "validation.live.syncups-v3",
            event: "typescript-graph-observed",
            ok: true,
            appID: appID,
            details: ["syncUpID": InstantSyncUpsV3LiveValidation.syncUpID]
          )
        }
      )
      try writeJSONLine(row)

    case .liveAppBuilderV3:
      let environment = ProcessInfo.processInfo.environment
      let appID = try requiredEnvironment(
        "INSTANT_APP_ID",
        environment: environment,
        caseID: invocation.caseID
      )
      let refreshToken = try requiredEnvironment(
        "INSTANT_SWIFT_DATA_APP_BUILDER_REFRESH_TOKEN",
        environment: environment,
        caseID: invocation.caseID
      )
      let userID = try requiredEnvironment(
        "INSTANT_SWIFT_DATA_APP_BUILDER_USER_ID",
        environment: environment,
        caseID: invocation.caseID
      )
      let apiURI = URL(
        string: environment["INSTANT_API_URI"]
          ?? InstantRuntimeConfiguration.defaultAPIURI.absoluteString
      ) ?? InstantRuntimeConfiguration.defaultAPIURI
      let websocketURI = URL(
        string: environment["INSTANT_WEBSOCKET_URI"]
          ?? InstantRuntimeConfiguration.defaultWebSocketURI.absoluteString
      ) ?? InstantRuntimeConfiguration.defaultWebSocketURI
      let row = try await InstantAppBuilderV3LiveValidation.run(
        appID: appID,
        apiURI: apiURI,
        websocketURI: websocketURI,
        refreshToken: refreshToken,
        expectedUserID: userID,
        onSwiftBuildReady: {
          emit(
            caseID: "validation.live.app-builder-v3",
            event: "swift-build-ready",
            ok: true,
            appID: appID,
            details: ["buildID": InstantAppBuilderV3LiveValidation.swiftBuildID]
          )
        },
        onTypeScriptBuildObserved: {
          emit(
            caseID: "validation.live.app-builder-v3",
            event: "typescript-build-observed",
            ok: true,
            appID: appID,
            details: ["buildID": InstantAppBuilderV3LiveValidation.typeScriptBuildID]
          )
        }
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
