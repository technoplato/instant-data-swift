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
}
