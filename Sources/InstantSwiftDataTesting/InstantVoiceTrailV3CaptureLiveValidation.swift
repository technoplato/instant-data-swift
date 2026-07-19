import Dependencies
import Foundation
import InstantSwiftData
import VoiceTrailV3App

@MainActor
private final class VoiceTrailMessageOutcome {
  var accepted = false
  var failure: InstantError?
}

public struct InstantVoiceTrailV3CaptureLiveValidationDetails: Codable, Equatable, Sendable {
  public var direction: String
  public var userID: String
  public var recordingID: String
  public var transcriptionID: String
  public var attachmentID: String
  public var title: String
  public var deviceID: String
  public var recordingState: String
  public var durationMilliseconds: Int
  public var transcriptionState: String
  public var attachmentKind: String
  public var attachmentContents: String
  public var attachmentOffsetMilliseconds: Int
  public var connectionState: String
  public var pendingMutationCount: Int

  public init(
    direction: String,
    userID: String,
    recordingID: String,
    transcriptionID: String,
    attachmentID: String,
    title: String,
    deviceID: String,
    recordingState: String,
    durationMilliseconds: Int,
    transcriptionState: String,
    attachmentKind: String,
    attachmentContents: String,
    attachmentOffsetMilliseconds: Int,
    connectionState: String,
    pendingMutationCount: Int
  ) {
    self.direction = direction
    self.userID = userID
    self.recordingID = recordingID
    self.transcriptionID = transcriptionID
    self.attachmentID = attachmentID
    self.title = title
    self.deviceID = deviceID
    self.recordingState = recordingState
    self.durationMilliseconds = durationMilliseconds
    self.transcriptionState = transcriptionState
    self.attachmentKind = attachmentKind
    self.attachmentContents = attachmentContents
    self.attachmentOffsetMilliseconds = attachmentOffsetMilliseconds
    self.connectionState = connectionState
    self.pendingMutationCount = pendingMutationCount
  }
}

public enum InstantVoiceTrailV3CaptureLiveValidation {
  public static func run(
    appID: String,
    apiURI: URL,
    websocketURI: URL,
    refreshToken: String,
    expectedUserID: String,
    recordingID: String,
    transcriptionID: String,
    attachmentID: String,
    title: String,
    deviceID: String,
    attachmentKind: String,
    attachmentContents: String,
    attachmentOffsetMilliseconds: Int,
    durationMilliseconds: Int,
    persistenceURL: URL? = nil
  ) async throws -> ValidationEvidenceRow<InstantVoiceTrailV3CaptureLiveValidationDetails> {
    var dependencies = DependencyValues()
    dependencies.instantLiveTransport = .live
    try await dependencies.bootstrapInstantSwiftData(
      appID: appID,
      apiURI: apiURI,
      websocketURI: websocketURI,
      persistenceURL: persistenceURL
        ?? FileManager.default.temporaryDirectory
        .appendingPathComponent("instant-voice-trail-v3-capture-\(UUID().uuidString).sqlite"),
      initialAttributes: VoiceTrailSchema.attributes,
      liveShareContract: .v3CaptureRecordings
    )
    let client = dependencies.defaultInstantSwiftData
    let session = try await client.signInWithRefreshToken(
      refreshToken,
      userID: "untrusted-voice-trail-v3-user"
    )
    guard session.userID == expectedUserID else {
      throw validationFailure(
        operation: "authenticate VoiceTrail V3 capture",
        message: "Server-verified capture user did not match the expected user."
      )
    }
    _ = try await client.connect()
    try await waitForAuthenticated(client)

    try await sendAndRequireServerAcceptance(
      CreateVoiceTrailRecording(
        recordingID: InstantID(rawValue: recordingID),
        transcriptionID: InstantID(rawValue: transcriptionID),
        ownerID: InstantID(rawValue: expectedUserID),
        deviceID: deviceID,
        title: title
      ),
      using: client,
      operation: "create VoiceTrail V3 recording"
    )

    try await sendAndRequireServerAcceptance(
      CreateVoiceTrailAttachment(
        attachmentID: InstantID(rawValue: attachmentID),
        recordingID: InstantID(rawValue: recordingID),
        kind: attachmentKind,
        contents: attachmentContents,
        offsetMilliseconds: attachmentOffsetMilliseconds
      ),
      using: client,
      operation: "create VoiceTrail V3 attachment"
    )

    try await sendAndRequireServerAcceptance(
      FinishVoiceTrailRecording(
        recordingID: InstantID(rawValue: recordingID),
        transcriptionID: InstantID(rawValue: transcriptionID),
        durationMilliseconds: durationMilliseconds
      ),
      using: client,
      operation: "finish VoiceTrail V3 recording"
    )

    let pendingMutationCount = await client.pendingMutations()
      .filter { $0.status == .pending }
      .count
    let status = try await client.connectionStatus()
    guard pendingMutationCount == 0, status.state == .authenticated else {
      throw validationFailure(
        operation: "sync VoiceTrail V3 capture",
        message:
          "Expected an authenticated connection with zero pending mutations; found "
          + "\(status.state.rawValue) and \(pendingMutationCount) pending."
      )
    }

    return ValidationEvidenceRow(
      caseID: "validation.live.voice-trail-v3-capture",
      side: "swift",
      event: "app-capture-finished",
      appID: appID,
      entityID: recordingID,
      timestampMs: Int64((Date().timeIntervalSince1970 * 1_000).rounded()),
      ok: true,
      details: InstantVoiceTrailV3CaptureLiveValidationDetails(
        direction: "swift-to-typescript",
        userID: expectedUserID,
        recordingID: recordingID,
        transcriptionID: transcriptionID,
        attachmentID: attachmentID,
        title: title,
        deviceID: deviceID,
        recordingState: "finished",
        durationMilliseconds: durationMilliseconds,
        transcriptionState: "ready",
        attachmentKind: attachmentKind,
        attachmentContents: attachmentContents,
        attachmentOffsetMilliseconds: attachmentOffsetMilliseconds,
        connectionState: status.state.rawValue,
        pendingMutationCount: pendingMutationCount
      )
    )
  }

  private static func validationFailure(operation: String, message: String) -> InstantError {
    InstantError(
      code: .validationFailed,
      operation: operation,
      message: message,
      recovery: "Inspect the VoiceTrail V3 app capture messages and live permissions."
    )
  }

  private static func waitForAuthenticated(_ client: InstantSwiftDataClient) async throws {
    let deadline = ContinuousClock.now + .seconds(15)
    while ContinuousClock.now < deadline {
      if try await client.connectionStatus().state == .authenticated { return }
      try await Task.sleep(for: .milliseconds(25))
    }
    let status = try await client.connectionStatus()
    throw validationFailure(
      operation: "wait for VoiceTrail V3 authentication",
      message: "Expected authenticated, found \(status.state.rawValue)."
    )
  }

  private static func sendAndRequireServerAcceptance<Message: InstantMessage>(
    _ message: Message,
    using client: InstantSwiftDataClient,
    operation: String
  ) async throws {
    let outcome = await MainActor.run { VoiceTrailMessageOutcome() }
    let task = client.send(
      message,
      onServerAccepted: { _ in outcome.accepted = true },
      onFailure: { outcome.failure = $0 }
    )
    defer { task.cancel() }

    try await withThrowingTaskGroup(of: Void.self) { group in
      group.addTask { await task.value }
      group.addTask {
        try await Task.sleep(for: .seconds(15))
        throw validationFailure(
          operation: operation,
          message: "Timed out waiting for server acceptance."
        )
      }
      _ = try await group.next()
      group.cancelAll()
    }

    let result = await MainActor.run { (outcome.accepted, outcome.failure) }
    if let failure = result.1 { throw failure }
    guard result.0 else {
      throw validationFailure(
        operation: operation,
        message: "The message completed without server acceptance."
      )
    }
  }
}
