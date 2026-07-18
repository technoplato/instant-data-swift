import CustomDump
import InstantSwiftDataCore
import InstantSwiftDataTesting
import Testing

@Suite
struct InstantRecordingActionLiveContractTests {
  private let ids = InstantRecordingActionLiveIDs(
    recordingID: "recording-e2e",
    transcriptionID: "transcription-e2e",
    memberID: "member-e2e",
    attachmentID: "attachment-e2e",
    ownerID: "owner-e2e"
  )

  @Test
  func createStepsMatchCanonicalRecordingGraph() {
    let steps = InstantRecordingActionLiveContract.createSteps(
      ids: ids,
      title: "Canonical recording",
      deviceID: "swift-e2e",
      attachmentContents: "Cross-SDK notes"
    )

    expectNoDifference(steps.count, 18)
    expectNoDifference(
      steps,
      [
        add(ids.recordingID, "v3_capture_recordings/id", .string(ids.recordingID)),
        add(
          ids.recordingID,
          "v3_capture_recordings/title",
          .string("Canonical recording")
        ),
        add(ids.recordingID, "v3_capture_recordings/owner", .string(ids.ownerID)),
        add(ids.recordingID, "v3_capture_recordings/deviceID", .string("swift-e2e")),
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
        add(
          ids.transcriptionID,
          "v3_capture_transcriptions/state",
          .string("processing")
        ),
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
          .string("Cross-SDK notes")
        ),
        add(
          ids.attachmentID,
          "v3_capture_attachments/offsetMilliseconds",
          .number(2_500)
        ),
      ]
    )
  }

  @Test
  func queryIncludesEntireCanonicalRecordingGraph() {
    expectNoDifference(
      InstantRecordingActionLiveContract.query(recordingID: ids.recordingID),
      .object([
        "v3_capture_recordings": .object([
          "$": .object([
            "where": .object([
              "id": .string(ids.recordingID)
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
    )
  }

  private func add(
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
