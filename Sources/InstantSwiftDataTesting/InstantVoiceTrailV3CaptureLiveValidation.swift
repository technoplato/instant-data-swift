import Dependencies
import Foundation
import InstantSwiftData
import VoiceTrailV3App

public struct InstantVoiceTrailV3CaptureLiveValidationDetails: Codable, Equatable, Sendable {
  public var direction: String
  public var userID: String
  public var recordingID: String
  public var transcriptionID: String
  public var title: String
  public var deviceID: String
  public var recordingState: String
  public var durationMilliseconds: Int
  public var transcriptionState: String
  public var connectionState: String
  public var pendingMutationCount: Int

  public init(
    direction: String,
    userID: String,
    recordingID: String,
    transcriptionID: String,
    title: String,
    deviceID: String,
    recordingState: String,
    durationMilliseconds: Int,
    transcriptionState: String,
    connectionState: String,
    pendingMutationCount: Int
  ) {
    self.direction = direction
    self.userID = userID
    self.recordingID = recordingID
    self.transcriptionID = transcriptionID
    self.title = title
    self.deviceID = deviceID
    self.recordingState = recordingState
    self.durationMilliseconds = durationMilliseconds
    self.transcriptionState = transcriptionState
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
    title: String,
    deviceID: String,
    persistenceURL: URL? = nil
  ) async throws -> ValidationEvidenceRow<InstantVoiceTrailV3CaptureLiveValidationDetails> {
    var dependencies = DependencyValues()
    dependencies.instantLiveTransport = .live
    try await dependencies.bootstrapInstantSwiftData(
      appID: appID,
      apiURI: apiURI,
      websocketURI: websocketURI,
      persistenceURL: persistenceURL ?? FileManager.default.temporaryDirectory
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

    let prepared = try await CreateVoiceTrailRecording(
      recordingID: InstantID(rawValue: recordingID),
      transcriptionID: InstantID(rawValue: transcriptionID),
      ownerID: InstantID(rawValue: expectedUserID),
      deviceID: deviceID,
      title: title
    ).prepare(using: client)
    _ = try await client.transact {
      for mutation in prepared.mutations { mutation }
    }
    try await waitForOutboxDrain(client)

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
      event: "app-capture-created",
      appID: appID,
      entityID: recordingID,
      timestampMs: Int64((Date().timeIntervalSince1970 * 1_000).rounded()),
      ok: true,
      details: InstantVoiceTrailV3CaptureLiveValidationDetails(
        direction: "swift-to-typescript",
        userID: expectedUserID,
        recordingID: recordingID,
        transcriptionID: transcriptionID,
        title: title,
        deviceID: deviceID,
        recordingState: "recording",
        durationMilliseconds: 0,
        transcriptionState: "processing",
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

  private static func waitForOutboxDrain(_ client: InstantSwiftDataClient) async throws {
    let deadline = ContinuousClock.now + .seconds(15)
    while ContinuousClock.now < deadline {
      _ = try await client.flushPendingMutations()
      if await client.pendingMutations().isEmpty { return }
      try await Task.sleep(for: .milliseconds(25))
    }
    let count = await client.pendingMutations().count
    throw validationFailure(
      operation: "drain VoiceTrail V3 capture outbox",
      message: "Expected zero pending mutations, found \(count)."
    )
  }
}
