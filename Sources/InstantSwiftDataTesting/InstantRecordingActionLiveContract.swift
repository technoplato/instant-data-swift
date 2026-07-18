import InstantSwiftDataCore

public struct InstantRecordingActionLiveIDs: Equatable, Sendable {
  public var recordingID: String
  public var transcriptionID: String
  public var memberID: String
  public var attachmentID: String
  public var ownerID: String

  public init(
    recordingID: String,
    transcriptionID: String,
    memberID: String,
    attachmentID: String,
    ownerID: String
  ) {
    self.recordingID = recordingID
    self.transcriptionID = transcriptionID
    self.memberID = memberID
    self.attachmentID = attachmentID
    self.ownerID = ownerID
  }
}

public enum InstantRecordingActionLiveContract {
  public static func localQuery(recordingID: String) -> InstantQueryPlan {
    InstantQueryPlan(
      id: "validation.live.recording-action.snapshot",
      namespace: "v3_capture_recordings",
      filters: [.equals(field: "id", value: .string(recordingID))],
      includes: [
        InstantQueryInclude("owner"),
        InstantQueryInclude("attachments", direction: .reverse),
        InstantQueryInclude(
          "members",
          direction: .reverse,
          query: InstantQueryIncludePlan(
            id: "validation.live.recording-action.members",
            namespace: "v3_capture_members",
            includes: [InstantQueryInclude("user")]
          )
        ),
        InstantQueryInclude("transcriptions", direction: .reverse),
      ]
    )
  }

  public static func query(recordingID: String) -> InstantLiveJSONValue {
    .object([
      "v3_capture_recordings": .object([
        "$": .object([
          "where": .object([
            "id": .string(recordingID)
          ])
        ]),
        "attachments": .object([:]),
        "members": .object([
          "user": .object([:])
        ]),
        "owner": .object([:]),
        "transcriptions": .object([:]),
      ])
    ])
  }

  public static func createSteps(
    ids: InstantRecordingActionLiveIDs,
    title: String,
    deviceID: String,
    attachmentContents: String
  ) -> [InstantTransportStep] {
    [
      add(ids.recordingID, "v3_capture_recordings/id", .string(ids.recordingID)),
      add(ids.recordingID, "v3_capture_recordings/title", .string(title)),
      add(ids.recordingID, "v3_capture_recordings/owner", .string(ids.ownerID)),
      add(ids.recordingID, "v3_capture_recordings/deviceID", .string(deviceID)),
      add(ids.recordingID, "v3_capture_recordings/state", .string("recording")),
      add(ids.recordingID, "v3_capture_recordings/durationMilliseconds", .number(0)),
      add(
        ids.transcriptionID,
        "v3_capture_transcriptions/id",
        .string(ids.transcriptionID)
      ),
      add(
        ids.transcriptionID,
        "v3_capture_transcriptions/recording",
        .string(ids.recordingID)
      ),
      add(ids.transcriptionID, "v3_capture_transcriptions/state", .string("processing")),
      add(ids.memberID, "v3_capture_members/id", .string(ids.memberID)),
      add(ids.memberID, "v3_capture_members/recording", .string(ids.recordingID)),
      add(ids.memberID, "v3_capture_members/user", .string(ids.ownerID)),
      add(ids.memberID, "v3_capture_members/role", .string("owner")),
      add(ids.attachmentID, "v3_capture_attachments/id", .string(ids.attachmentID)),
      add(
        ids.attachmentID,
        "v3_capture_attachments/recording",
        .string(ids.recordingID)
      ),
      add(ids.attachmentID, "v3_capture_attachments/kind", .string("text")),
      add(
        ids.attachmentID,
        "v3_capture_attachments/contents",
        .string(attachmentContents)
      ),
      add(ids.attachmentID, "v3_capture_attachments/offsetMilliseconds", .number(2_500)),
    ]
  }

  public static func snapshot(
    from recordings: [InstantEntitySnapshot]
  ) throws -> InstantLiveJSONValue {
    guard recordings.count == 1, let recording = recordings.first else {
      throw snapshotError(
        path: "v3_capture_recordings",
        message: "Expected exactly one recording, received \(recordings.count)."
      )
    }
    let owner = try oneLink(recording.links, name: "owner", path: "recording.owner")
    let attachments = try requiredLinks(
      recording.links,
      name: "attachments",
      path: "recording.attachments"
    )
    let members = try requiredLinks(
      recording.links,
      name: "members",
      path: "recording.members"
    )
    let transcriptions = try requiredLinks(
      recording.links,
      name: "transcriptions",
      path: "recording.transcriptions"
    )

    return .object([
      "recording": .object([
        "id": .string(recording.id),
        "title": .string(try string(recording.values, "title", "recording.title")),
        "deviceID": .string(
          try string(recording.values, "deviceID", "recording.deviceID")
        ),
        "state": .string(try string(recording.values, "state", "recording.state")),
        "durationMilliseconds": .number(
          try number(
            recording.values,
            "durationMilliseconds",
            "recording.durationMilliseconds"
          )
        ),
        "ownerID": .string(owner.id),
      ]),
      "attachments": .array(
        try attachments.sorted(by: idOrder).map { attachment in
          .object([
            "id": .string(attachment.id),
            "kind": .string(try string(attachment.values, "kind", "attachment.kind")),
            "contents": .string(
              try string(attachment.values, "contents", "attachment.contents")
            ),
            "offsetMilliseconds": .number(
              try number(
                attachment.values,
                "offsetMilliseconds",
                "attachment.offsetMilliseconds"
              )
            ),
          ])
        }
      ),
      "members": .array(
        try members.sorted(by: idOrder).map { member in
          let user = try oneLink(member.links, name: "user", path: "member.user")
          return .object([
            "id": .string(member.id),
            "role": .string(try string(member.values, "role", "member.role")),
            "userID": .string(user.id),
          ])
        }
      ),
      "transcriptions": .array(
        try transcriptions.sorted(by: idOrder).map { transcription in
          .object([
            "id": .string(transcription.id),
            "state": .string(
              try string(transcription.values, "state", "transcription.state")
            ),
          ])
        }
      ),
    ])
  }

  private static func add(
    _ entityID: String,
    _ attributeID: String,
    _ value: InstantTransportValue
  ) -> InstantTransportStep {
    .addTriple(
      entity: .id(entityID),
      attributeID: attributeID,
      value: value
    )
  }

  private static func requiredLinks(
    _ links: [String: [InstantLinkedEntitySnapshot]]?,
    name: String,
    path: String
  ) throws -> [InstantLinkedEntitySnapshot] {
    guard let values = links?[name], !values.isEmpty else {
      throw snapshotError(path: path, message: "Expected at least one linked entity.")
    }
    return values
  }

  private static func oneLink(
    _ links: [String: [InstantLinkedEntitySnapshot]]?,
    name: String,
    path: String
  ) throws -> InstantLinkedEntitySnapshot {
    let values = try requiredLinks(links, name: name, path: path)
    guard values.count == 1, let value = values.first else {
      throw snapshotError(
        path: path,
        message: "Expected exactly one linked entity, received \(values.count)."
      )
    }
    return value
  }

  private static func string(
    _ values: [String: InstantMaterializedValue],
    _ field: String,
    _ path: String
  ) throws -> String {
    guard case let .string(value) = values[field]?.first else {
      throw snapshotError(path: path, message: "Expected a string value.")
    }
    return value
  }

  private static func number(
    _ values: [String: InstantMaterializedValue],
    _ field: String,
    _ path: String
  ) throws -> Double {
    guard case let .number(value) = values[field]?.first, value.isFinite else {
      throw snapshotError(path: path, message: "Expected a finite number value.")
    }
    return value
  }

  private static func idOrder(
    _ lhs: InstantLinkedEntitySnapshot,
    _ rhs: InstantLinkedEntitySnapshot
  ) -> Bool {
    lhs.id < rhs.id
  }

  private static func snapshotError(path: String, message: String) -> InstantError {
    InstantError(
      code: .validationFailed,
      operation: "project recording action live snapshot",
      path: path,
      message: message,
      recovery: "Keep the Swift recording query and canonical TypeScript graph aligned."
    )
  }
}
