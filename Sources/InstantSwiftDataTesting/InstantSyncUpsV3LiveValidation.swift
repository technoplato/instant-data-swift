import Dependencies
import Foundation
import InstantSwiftData
import SyncUpsV3App

@MainActor
private final class SyncUpsV3MessageOutcome {
  var accepted = false
  var failure: InstantError?
}

public struct InstantSyncUpsV3LiveMeetingDetails: Codable, Equatable, Sendable {
  public var id: String
  public var dateMilliseconds: Int64
  public var transcript: String

  public init(id: String, dateMilliseconds: Int64, transcript: String) {
    self.id = id
    self.dateMilliseconds = dateMilliseconds
    self.transcript = transcript
  }
}

public struct InstantSyncUpsV3LiveValidationDetails: Codable, Equatable, Sendable {
  public var syncUpID: String
  public var seconds: Int
  public var theme: String
  public var title: String
  public var attendeeIDs: [String]
  public var attendeeNames: [String]
  public var meetings: [InstantSyncUpsV3LiveMeetingDetails]
  public var connectionState: String
  public var pendingMutationCount: Int

  public init(
    syncUpID: String,
    seconds: Int,
    theme: String,
    title: String,
    attendeeIDs: [String],
    attendeeNames: [String],
    meetings: [InstantSyncUpsV3LiveMeetingDetails],
    connectionState: String,
    pendingMutationCount: Int
  ) {
    self.syncUpID = syncUpID
    self.seconds = seconds
    self.theme = theme
    self.title = title
    self.attendeeIDs = attendeeIDs
    self.attendeeNames = attendeeNames
    self.meetings = meetings
    self.connectionState = connectionState
    self.pendingMutationCount = pendingMutationCount
  }
}

public enum InstantSyncUpsV3LiveValidation {
  public static let syncUpID = "00000000-0000-4000-8000-000000000501"
  public static let swiftAttendeeID = "00000000-0000-4000-8000-000000000502"
  public static let swiftMeetingID = "00000000-0000-4000-8000-000000000503"
  public static let typeScriptAttendeeID = "00000000-0000-4000-8000-000000000504"
  public static let typeScriptMeetingID = "00000000-0000-4000-8000-000000000505"
  public static let swiftMeetingDateMilliseconds: Int64 = 1_784_467_200_000
  public static let typeScriptMeetingDateMilliseconds: Int64 = 1_784_467_201_000

  public static func run(
    appID: String,
    apiURI: URL,
    websocketURI: URL,
    refreshToken: String,
    expectedUserID: String,
    persistenceURL: URL? = nil,
    onSwiftGraphReady: @escaping @Sendable () -> Void = {},
    onTypeScriptGraphObserved: @escaping @Sendable () -> Void = {}
  ) async throws -> ValidationEvidenceRow<InstantSyncUpsV3LiveValidationDetails> {
    let client = try await liveClient(
      appID: appID,
      apiURI: apiURI,
      websocketURI: websocketURI,
      persistenceURL: persistenceURL
    )
    try await authenticate(
      client,
      refreshToken: refreshToken,
      expectedUserID: expectedUserID
    )

    let rows = FetchAll<SyncUpsV3SyncUp>()
    let rowsTask = Task {
      try await rows.task(
        SyncUpsV3SyncUp.detail(InstantID(rawValue: syncUpID)),
        using: client
      )
    }
    defer { rowsTask.cancel() }

    try await sendAndRequireServerAcceptance(
      SaveSyncUpsV3Form(
        syncUpID: InstantID(rawValue: syncUpID),
        isNew: true,
        title: "Design",
        seconds: 300,
        theme: .appOrange,
        attendees: [
          SyncUpsV3AttendeeInput(
            id: InstantID(rawValue: swiftAttendeeID),
            name: "Blob"
          )
        ]
      ),
      using: client,
      operation: "create Swift SyncUps graph"
    )
    try await sendAndRequireServerAcceptance(
      RecordSyncUpsV3Meeting(
        meetingID: InstantID(rawValue: swiftMeetingID),
        syncUpID: InstantID(rawValue: syncUpID),
        date: Date(
          timeIntervalSince1970: Double(swiftMeetingDateMilliseconds) / 1_000
        ),
        transcript: "Reviewed launch risks."
      ),
      using: client,
      operation: "record Swift SyncUps meeting"
    )

    _ = try await waitForSyncUp(rows: rows) { syncUp in
      syncUp.title == "Design"
        && syncUp.attendees.contains { $0.id.rawValue == swiftAttendeeID }
        && syncUp.meetings.contains { $0.id.rawValue == swiftMeetingID }
    }
    onSwiftGraphReady()

    let completed = try await waitForSyncUp(rows: rows) { syncUp in
      syncUp.title == "Design updated by TypeScript"
        && syncUp.attendees.contains { attendee in
          attendee.id.rawValue == typeScriptAttendeeID && attendee.name == "Blob Jr"
        }
        && syncUp.meetings.contains { meeting in
          meeting.id.rawValue == typeScriptMeetingID
            && meeting.transcript == "TypeScript follow-up notes."
        }
    }
    onTypeScriptGraphObserved()

    rowsTask.cancel()
    _ = try? await rowsTask.value
    let status = try await client.connectionStatus()
    let pendingMutationCount = await client.pendingMutations().count
    _ = try await client.closeConnection()

    return ValidationEvidenceRow(
      caseID: "validation.live.syncups-v3",
      side: "swift",
      event: "typescript-graph-observed",
      appID: appID,
      entityID: syncUpID,
      timestampMs: milliseconds(Date()),
      ok: true,
      details: details(
        completed,
        connectionState: status.state.rawValue,
        pendingMutationCount: pendingMutationCount
      )
    )
  }

  private static func liveClient(
    appID: String,
    apiURI: URL,
    websocketURI: URL,
    persistenceURL: URL?
  ) async throws -> InstantSwiftDataClient {
    try await withDependencies {
      $0.context = .live
      $0.instantLiveTransport = .live
      try await $0.bootstrapInstantSwiftData(
        appID: appID,
        apiURI: apiURI,
        websocketURI: websocketURI,
        persistenceURL: persistenceURL
          ?? FileManager.default.temporaryDirectory
          .appendingPathComponent("instant-syncups-v3-live-\(UUID().uuidString).sqlite"),
        context: .live,
        initialAttributes: SyncUpsV3Schema.attributes
      )
    } operation: {
      @Dependency(\.defaultInstantSwiftData) var client
      return client
    }
  }

  private static func authenticate(
    _ client: InstantSwiftDataClient,
    refreshToken: String,
    expectedUserID: String
  ) async throws {
    let session = try await client.signInWithRefreshToken(
      refreshToken,
      userID: "untrusted-syncups-v3-user"
    )
    guard session.userID == expectedUserID else {
      throw failure(
        operation: "authenticate SyncUps V3",
        message: "Server-verified SyncUps user did not match the expected user."
      )
    }
    _ = try await client.connect()
    let deadline = ContinuousClock.now + .seconds(15)
    while ContinuousClock.now < deadline {
      if try await client.connectionStatus().state == .authenticated { return }
      try await Task.sleep(for: .milliseconds(25))
    }
    throw failure(
      operation: "wait for SyncUps V3 authentication",
      message: "The live client did not reach authenticated state."
    )
  }

  private static func sendAndRequireServerAcceptance<Message: InstantMessage>(
    _ message: Message,
    using client: InstantSwiftDataClient,
    operation: String
  ) async throws {
    let outcome = await MainActor.run { SyncUpsV3MessageOutcome() }
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
        throw failure(operation: operation, message: "Timed out waiting for server acceptance.")
      }
      _ = try await group.next()
      group.cancelAll()
    }

    let result = await MainActor.run { (outcome.accepted, outcome.failure) }
    if let error = result.1 { throw error }
    guard result.0 else {
      throw failure(
        operation: operation,
        message: "The message completed without server acceptance."
      )
    }
  }

  private static func waitForSyncUp(
    rows: FetchAll<SyncUpsV3SyncUp>,
    predicate: @escaping (SyncUpsV3SyncUp) -> Bool
  ) async throws -> SyncUpsV3SyncUp {
    let deadline = ContinuousClock.now + .seconds(30)
    while ContinuousClock.now < deadline {
      if let syncUp = rows.wrappedValue.first(where: predicate) { return syncUp }
      try await Task.sleep(for: .milliseconds(25))
    }
    throw failure(
      operation: "observe SyncUps V3 graph",
      message: "Timed out waiting for the expected nested graph."
    )
  }

  private static func details(
    _ syncUp: SyncUpsV3SyncUp,
    connectionState: String,
    pendingMutationCount: Int
  ) -> InstantSyncUpsV3LiveValidationDetails {
    InstantSyncUpsV3LiveValidationDetails(
      syncUpID: syncUp.id.rawValue,
      seconds: syncUp.seconds,
      theme: syncUp.theme.rawValue,
      title: syncUp.title,
      attendeeIDs: syncUp.attendees.map(\.id.rawValue),
      attendeeNames: syncUp.attendees.map(\.name),
      meetings: syncUp.meetings.map {
        InstantSyncUpsV3LiveMeetingDetails(
          id: $0.id.rawValue,
          dateMilliseconds: milliseconds($0.date),
          transcript: $0.transcript
        )
      },
      connectionState: connectionState,
      pendingMutationCount: pendingMutationCount
    )
  }

  private static func milliseconds(_ date: Date) -> Int64 {
    Int64((date.timeIntervalSince1970 * 1_000).rounded())
  }

  private static func failure(operation: String, message: String) -> InstantError {
    InstantError(
      code: .validationFailed,
      operation: operation,
      message: message,
      recovery: "Inspect the SyncUps V3 live contract and generated schema."
    )
  }
}
