import Foundation
import InstantSwiftData
import VoiceTrailV3App

public enum InstantVoiceTrailRecordingsListValidationMode: String, Sendable {
  case owner
  case member
}

public struct InstantVoiceTrailRecordingRowEvidence: Codable, Equatable, Sendable {
  public var id: String
  public var title: String
  public var ownerUserID: String
  public var viewerRole: String?

  public init(id: String, title: String, ownerUserID: String, viewerRole: String?) {
    self.id = id
    self.title = title
    self.ownerUserID = ownerUserID
    self.viewerRole = viewerRole
  }
}

public struct InstantVoiceTrailRecordingsListLiveDetails: Codable, Equatable, Sendable {
  public var stage: String
  public var viewerUserID: String
  public var rows: [InstantVoiceTrailRecordingRowEvidence]
  public var connectionState: String
  public var cancellationClean: Bool?

  public init(
    stage: String,
    viewerUserID: String,
    rows: [InstantVoiceTrailRecordingRowEvidence],
    connectionState: String,
    cancellationClean: Bool? = nil
  ) {
    self.stage = stage
    self.viewerUserID = viewerUserID
    self.rows = rows
    self.connectionState = connectionState
    self.cancellationClean = cancellationClean
  }
}

public enum InstantVoiceTrailRecordingsListLiveValidation {
  public static func queryPlan(
    viewerUserID: String,
    mode: InstantVoiceTrailRecordingsListValidationMode
  ) -> InstantQueryPlan {
    recordingsQuery(viewerUserID: viewerUserID, mode: mode).plan
  }

  public static func run(
    appID: String,
    websocketURI: URL,
    refreshToken: String,
    viewerUserID: String,
    recordingID: String,
    mode: InstantVoiceTrailRecordingsListValidationMode,
    persistenceURL: URL? = nil
  ) -> AsyncThrowingStream<
    ValidationEvidenceRow<InstantVoiceTrailRecordingsListLiveDetails>,
    Error
  > {
    AsyncThrowingStream { continuation in
      let task = Task {
        do {
          let persistenceURL = persistenceURL ?? FileManager.default.temporaryDirectory
            .appendingPathComponent(
              "instant-voice-trail-recordings-live-\(UUID().uuidString).sqlite"
            )
          let trace = VoiceTrailRecordingsLiveTrace()
          let runtime = try await InstantRuntime.bootstrap(
            configuration: InstantRuntimeConfiguration(
              appID: appID,
              websocketURI: websocketURI,
              persistenceURL: persistenceURL,
              initialAttributes: voiceTrailAttributes,
              liveTransport: trace.transport,
              liveShareContract: .v3CaptureRecordings
            )
          )
          _ = try await runtime.signInWithRefreshToken(
            refreshToken,
            userID: viewerUserID
          )
          let client = InstantSwiftDataClient(runtime: runtime)
          let rows = FetchAll<VoiceTrailRecording>()
          let query = recordingsQuery(viewerUserID: viewerUserID, mode: mode)
          let rowsTask = Task {
            try await rows.task(query, using: client)
          }
          defer { rowsTask.cancel() }

          _ = try await runtime.connect()
          switch mode {
          case .owner:
            let values = try await waitForRole(
              .owner,
              recordingID: recordingID,
              rows: rows,
              operation: "wait for owner recordings-list row",
              trace: trace
            )
            continuation.yield(
              try await evidence(
                stage: "owner",
                viewerUserID: viewerUserID,
                rows: values,
                runtime: runtime
              )
            )

          case .member:
            let reader = try await waitForRole(
              .reader,
              recordingID: recordingID,
              rows: rows,
              operation: "wait for reader recordings-list row",
              trace: trace
            )
            continuation.yield(
              try await evidence(
                stage: "reader",
                viewerUserID: viewerUserID,
                rows: reader,
                runtime: runtime
              )
            )
            let writer = try await waitForRole(
              .writer,
              recordingID: recordingID,
              rows: rows,
              operation: "wait for writer recordings-list role replacement",
              trace: trace
            )
            continuation.yield(
              try await evidence(
                stage: "writer",
                viewerUserID: viewerUserID,
                rows: writer,
                runtime: runtime
              )
            )
            let revoked = try await waitForRevocation(
              recordingID: recordingID,
              rows: rows,
              trace: trace
            )
            continuation.yield(
              try await evidence(
                stage: "revoked",
                viewerUserID: viewerUserID,
                rows: revoked,
                runtime: runtime
              )
            )
          }

          rowsTask.cancel()
          let cancellationClean: Bool
          do {
            try await rowsTask.value
            cancellationClean = false
          } catch is CancellationError {
            cancellationClean = true
          }
          let status = try await runtime.connectionStatus()
          continuation.yield(
            ValidationEvidenceRow(
              caseID: "validation.live.voice-trail-recordings-list",
              side: "swift",
              event: "recordings-list-cancelled",
              appID: appID,
              entityID: recordingID,
              timestampMs: timestampMilliseconds(),
              ok: cancellationClean,
              details: InstantVoiceTrailRecordingsListLiveDetails(
                stage: "cancelled",
                viewerUserID: viewerUserID,
                rows: [],
                connectionState: status.state.rawValue,
                cancellationClean: cancellationClean
              )
            )
          )
          _ = try await runtime.closeConnection()
          continuation.finish()
        } catch {
          continuation.finish(throwing: error)
        }
      }
      continuation.onTermination = { _ in task.cancel() }
    }
  }

  private static func recordingsQuery(
    viewerUserID: String,
    mode: InstantVoiceTrailRecordingsListValidationMode
  ) -> InstantQuery<VoiceTrailRecording> {
    VoiceTrailRecording.recordingsQuery(
      scope: mode == .owner ? .mine : .shared,
      searchText: "",
      viewerID: InstantID(rawValue: viewerUserID)
    )
  }

  private static func waitForRole(
    _ role: InstantShareRole,
    recordingID: String,
    rows: FetchAll<VoiceTrailRecording>,
    operation: String,
    trace: VoiceTrailRecordingsLiveTrace
  ) async throws -> [VoiceTrailRecording] {
    for _ in 0..<800 {
      let values = rows.wrappedValue
      if values.contains(where: { $0.id.rawValue == recordingID && $0.viewerRole == role }) {
        return values
      }
      if let error = rows.loadError { throw error }
      try await Task.sleep(for: .milliseconds(25))
    }
    throw await timeout(operation, rows: rows.wrappedValue, trace: trace)
  }

  private static func waitForRevocation(
    recordingID: String,
    rows: FetchAll<VoiceTrailRecording>,
    trace: VoiceTrailRecordingsLiveTrace
  ) async throws -> [VoiceTrailRecording] {
    for _ in 0..<800 {
      let values = rows.wrappedValue
      if !values.contains(where: { $0.id.rawValue == recordingID }) {
        return values
      }
      if let error = rows.loadError { throw error }
      try await Task.sleep(for: .milliseconds(25))
    }
    throw await timeout(
      "wait for recordings-list revocation",
      rows: rows.wrappedValue,
      trace: trace
    )
  }

  private static func evidence(
    stage: String,
    viewerUserID: String,
    rows: [VoiceTrailRecording],
    runtime: InstantRuntime
  ) async throws -> ValidationEvidenceRow<InstantVoiceTrailRecordingsListLiveDetails> {
    let status = try await runtime.connectionStatus()
    return ValidationEvidenceRow(
      caseID: "validation.live.voice-trail-recordings-list",
      side: "swift",
      event: "recordings-list-\(stage)",
      appID: status.appID,
      entityID: rows.first?.id.rawValue,
      timestampMs: timestampMilliseconds(),
      ok: true,
      details: InstantVoiceTrailRecordingsListLiveDetails(
        stage: stage,
        viewerUserID: viewerUserID,
        rows: rows.map {
          InstantVoiceTrailRecordingRowEvidence(
            id: $0.id.rawValue,
            title: $0.title,
            ownerUserID: $0.ownerID.rawValue,
            viewerRole: $0.viewerRole?.rawValue
          )
        },
        connectionState: status.state.rawValue
      )
    )
  }

  private static func timeout(
    _ operation: String,
    rows: [VoiceTrailRecording],
    trace: VoiceTrailRecordingsLiveTrace
  ) async -> InstantError {
    let summary = rows.map {
      "\($0.id.rawValue):\($0.viewerRole?.rawValue ?? "none")"
    }
    return InstantError(
      code: .networkFailed,
      operation: operation,
      message: "Timed out with rows \(summary); \(await trace.summary()).",
      recovery: "Inspect the VoiceTrail live query, role links, and nested membership graph."
    )
  }

  private static func timestampMilliseconds() -> Int64 {
    Int64((Date().timeIntervalSince1970 * 1_000).rounded())
  }

  private static let voiceTrailAttributes =
    VoiceTrailUser.instantAttributes
    + VoiceTrailRecording.instantAttributes
    + VoiceTrailShare.instantAttributes
    + VoiceTrailShareMembership.instantAttributes
}

private actor VoiceTrailRecordingsLiveTrace {
  private var sentOps: [String] = []
  private var receivedOps: [String] = []
  private var addQueries: [String] = []
  private var queryResults: [String] = []

  nonisolated var transport: InstantLiveTransportClient {
    let live = InstantLiveTransportClient.live
    return InstantLiveTransportClient { request in
      let session = try await live.connect(request)
      return InstantLiveWebSocketSession(
        send: { message in
          await self.recordSent(message)
          try await session.send(message)
        },
        receive: {
          let message = try await session.receive()
          await self.recordReceived(message)
          return message
        },
        close: { await session.close() }
      )
    }
  }

  func summary() -> String {
    "sent=\(sentOps), received=\(receivedOps), queries=\(addQueries), results=\(queryResults)"
  }

  private func recordSent(_ message: InstantLiveMessage) {
    sentOps.append(message.op)
    if message.op == "add-query" {
      addQueries.append(String(describing: message.fields["q"]))
    }
  }

  private func recordReceived(_ message: InstantLiveMessage) {
    receivedOps.append(message.op)
    if message.op == "add-query-ok" || message.op == "add-query-exists" {
      queryResults.append(String(describing: message.fields["result"]))
    }
  }
}
