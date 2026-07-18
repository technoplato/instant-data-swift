import Foundation
import InstantSwiftData

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
          let runtime = try await InstantRuntime.bootstrap(
            configuration: InstantRuntimeConfiguration(
              appID: appID,
              websocketURI: websocketURI,
              persistenceURL: persistenceURL,
              initialAttributes: voiceTrailAttributes,
              liveShareContract: .v3CaptureRecordings
            )
          )
          _ = try await runtime.signInWithRefreshToken(
            refreshToken,
            userID: viewerUserID
          )
          let client = InstantSwiftDataClient(runtime: runtime)
          let rows = FetchAll<LiveRecordingRow>()
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
              operation: "wait for owner recordings-list row"
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
              operation: "wait for reader recordings-list row"
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
              operation: "wait for writer recordings-list role replacement"
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
              rows: rows
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
  ) -> InstantQuery<LiveRecordingRow> {
    let viewerID = InstantID<LiveUser>(rawValue: viewerUserID)
    let membership = LiveMembership.query
      .where(LiveMembership.user == viewerID)
      .include(LiveMembership.user)
    let share = LiveShare.query
      .include(LiveShare.owner)
      .include(LiveShare.memberships, membership)
    let query = LiveRecordingRow.query
      .include(LiveRecordingRow.owner)
      .include(LiveRecordingRow.readers)
      .include(LiveRecordingRow.writers)
      .include(LiveRecordingRow.share, share)
      .order(LiveRecordingRow.title)
    switch mode {
    case .owner:
      return query.where(LiveRecordingRow.owner == viewerID)
    case .member:
      return query.where(
        .any(
          LiveRecordingRow.readers == viewerID,
          LiveRecordingRow.writers == viewerID
        )
      )
    }
  }

  private static func waitForRole(
    _ role: InstantShareRole,
    recordingID: String,
    rows: FetchAll<LiveRecordingRow>,
    operation: String
  ) async throws -> [LiveRecordingRow] {
    for _ in 0..<800 {
      let values = rows.wrappedValue
      if values.contains(where: { $0.id.rawValue == recordingID && $0.viewerRole == role }) {
        return values
      }
      if let error = rows.loadError { throw error }
      try await Task.sleep(for: .milliseconds(25))
    }
    throw timeout(operation, rows: rows.wrappedValue)
  }

  private static func waitForRevocation(
    recordingID: String,
    rows: FetchAll<LiveRecordingRow>
  ) async throws -> [LiveRecordingRow] {
    for _ in 0..<800 {
      let values = rows.wrappedValue
      if !values.contains(where: { $0.id.rawValue == recordingID }) {
        return values
      }
      if let error = rows.loadError { throw error }
      try await Task.sleep(for: .milliseconds(25))
    }
    throw timeout("wait for recordings-list revocation", rows: rows.wrappedValue)
  }

  private static func evidence(
    stage: String,
    viewerUserID: String,
    rows: [LiveRecordingRow],
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
            ownerUserID: $0.ownerUserID.rawValue,
            viewerRole: $0.viewerRole?.rawValue
          )
        },
        connectionState: status.state.rawValue
      )
    )
  }

  private static func timeout(
    _ operation: String,
    rows: [LiveRecordingRow]
  ) -> InstantError {
    let summary = rows.map {
      "\($0.id.rawValue):\($0.viewerRole?.rawValue ?? "none")"
    }
    return InstantError(
      code: .networkFailed,
      operation: operation,
      message: "Timed out with rows \(summary).",
      recovery: "Inspect the VoiceTrail live query, role links, and nested membership graph."
    )
  }

  private static func timestampMilliseconds() -> Int64 {
    Int64((Date().timeIntervalSince1970 * 1_000).rounded())
  }

  private static let voiceTrailAttributes =
    LiveUser.instantAttributes
    + LiveRecordingRow.instantAttributes
    + LiveShare.instantAttributes
    + LiveMembership.instantAttributes
}

private struct LiveRecordingRow: Hashable, Codable, InstantEntityModel {
  var id: InstantID<Self>
  var title: String
  var ownerUserID: InstantID<LiveUser>
  var viewerRole: InstantShareRole?

  static let instantNamespace = "v3_capture_recordings"
  static let title = InstantAttributePath<Self, String>("title")
  static let owner = InstantAttributePath<Self, InstantID<LiveUser>>("owner")
  static let readers = InstantAttributePath<Self, InstantID<LiveUser>>("readers")
  static let writers = InstantAttributePath<Self, InstantID<LiveUser>>("writers")
  static let share = InstantReverseRelation<Self, LiveShare>(attribute: LiveShare.root)
  static let instantAttributes = [
    InstantAttribute.primaryKey(namespace: instantNamespace),
    scalar("title", .string),
    scalar("deviceID", .string),
    scalar("state", .string),
    scalar("durationMilliseconds", .number),
    userLink("owner", reverse: "recordings", cardinality: .one),
    userLink("readers", reverse: "readableRecordings", cardinality: .many),
    userLink("writers", reverse: "writableRecordings", cardinality: .many),
  ]

  init(snapshot: InstantEntitySnapshot) throws {
    guard case let .string(title) = snapshot.values["title"]?.first,
      case let .ref(ownerUserID) = snapshot.values["owner"]?.first
    else {
      throw decodeError("Expected recording title and owner.", snapshot: snapshot)
    }
    id = InstantID(rawValue: snapshot.id)
    self.title = title
    self.ownerUserID = InstantID(rawValue: ownerUserID)
    let membership = snapshot.links?["share"]?.first?.links?["memberships"]?.first
    if let membership {
      guard case let .string(rawRole) = membership.values["role"]?.first,
        let role = InstantShareRole(rawValue: rawRole)
      else {
        throw decodeError("Expected a canonical membership role.", snapshot: snapshot)
      }
      viewerRole = role
    } else {
      viewerRole = nil
    }
  }

  private static func scalar(_ name: String, _ type: InstantValueType) -> InstantAttribute {
    InstantAttribute(
      id: "\(instantNamespace)/\(name)",
      namespace: instantNamespace,
      name: name,
      valueType: type,
      isIndexed: true
    )
  }

  private static func userLink(
    _ name: String,
    reverse: String,
    cardinality: InstantCardinality
  ) -> InstantAttribute {
    InstantAttribute(
      id: "\(instantNamespace)/\(name)",
      namespace: instantNamespace,
      name: name,
      valueType: .ref,
      cardinality: cardinality,
      forwardIdentity: "\(instantNamespace)/\(name)",
      reverseIdentity: "$users/\(reverse)",
      linkNamespace: LiveUser.instantNamespace
    )
  }
}

private struct LiveUser: Hashable, Codable, InstantEntityModel {
  var id: InstantID<Self>
  static let instantNamespace = "$users"
  static let instantAttributes = [InstantAttribute.primaryKey(namespace: instantNamespace)]

  init(snapshot: InstantEntitySnapshot) throws {
    id = InstantID(rawValue: snapshot.id)
  }
}

private struct LiveShare: Hashable, Codable, InstantEntityModel {
  var id: InstantID<Self>
  static let instantNamespace = "v3_shares"
  static let owner = InstantAttributePath<Self, InstantID<LiveUser>>("owner")
  static let root = InstantAttributePath<Self, InstantID<LiveRecordingRow>>("root")
  static let memberships = InstantReverseRelation<Self, LiveMembership>(
    attribute: LiveMembership.share
  )
  static let instantAttributes = [
    InstantAttribute.primaryKey(namespace: instantNamespace),
    ref("owner", target: LiveUser.instantNamespace, reverse: "$users/ownedShares"),
    ref(
      "root",
      target: LiveRecordingRow.instantNamespace,
      reverse: "v3_capture_recordings/share",
      isUnique: true
    ),
    scalar("token", .string),
    scalar("rootNamespace", .string),
    scalar("rootID", .string),
    scalar("createdAt", .date),
    scalar("updatedAt", .date),
    scalar("revokedAt", .date, isRequired: false),
  ]

  init(snapshot: InstantEntitySnapshot) throws {
    id = InstantID(rawValue: snapshot.id)
  }

  private static func scalar(
    _ name: String,
    _ type: InstantValueType,
    isRequired: Bool = true
  ) -> InstantAttribute {
    InstantAttribute(
      id: "\(instantNamespace)/\(name)",
      namespace: instantNamespace,
      name: name,
      valueType: type,
      isRequired: isRequired,
      isIndexed: true
    )
  }

  private static func ref(
    _ name: String,
    target: String,
    reverse: String,
    isUnique: Bool = false
  ) -> InstantAttribute {
    InstantAttribute(
      id: "\(instantNamespace)/\(name)",
      namespace: instantNamespace,
      name: name,
      valueType: .ref,
      isUnique: isUnique,
      forwardIdentity: "\(instantNamespace)/\(name)",
      reverseIdentity: reverse,
      linkNamespace: target
    )
  }
}

private struct LiveMembership: Hashable, Codable, InstantEntityModel {
  var id: InstantID<Self>
  static let instantNamespace = "v3_share_memberships"
  static let share = InstantAttributePath<Self, InstantID<LiveShare>>("share")
  static let user = InstantAttributePath<Self, InstantID<LiveUser>>("user")
  static let instantAttributes = [
    InstantAttribute.primaryKey(namespace: instantNamespace),
    scalar("role", .string),
    scalar("acceptedAt", .date),
    scalar("revokedAt", .date, isRequired: false),
    ref("share", target: LiveShare.instantNamespace, reverse: "v3_shares/memberships"),
    ref("user", target: LiveUser.instantNamespace, reverse: "$users/shareMemberships"),
  ]

  init(snapshot: InstantEntitySnapshot) throws {
    id = InstantID(rawValue: snapshot.id)
  }

  private static func scalar(
    _ name: String,
    _ type: InstantValueType,
    isRequired: Bool = true
  ) -> InstantAttribute {
    InstantAttribute(
      id: "\(instantNamespace)/\(name)",
      namespace: instantNamespace,
      name: name,
      valueType: type,
      isRequired: isRequired,
      isIndexed: true
    )
  }

  private static func ref(
    _ name: String,
    target: String,
    reverse: String
  ) -> InstantAttribute {
    InstantAttribute(
      id: "\(instantNamespace)/\(name)",
      namespace: instantNamespace,
      name: name,
      valueType: .ref,
      forwardIdentity: "\(instantNamespace)/\(name)",
      reverseIdentity: reverse,
      linkNamespace: target
    )
  }
}

private func decodeError(
  _ message: String,
  snapshot: InstantEntitySnapshot
) -> InstantError {
  InstantError(
    code: .decodeFailed,
    operation: "decode live VoiceTrail recordings-list row",
    namespace: snapshot.namespace,
    localID: snapshot.id,
    message: message,
    recovery: "Keep the Swift row projection aligned with the canonical TypeScript graph."
  )
}
