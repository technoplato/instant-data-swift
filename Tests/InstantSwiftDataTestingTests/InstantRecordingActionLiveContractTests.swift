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

  @Test
  func localQueryAndSnapshotProjectCanonicalRecordingGraph() throws {
    let localQuery = InstantRecordingActionLiveContract.localQuery(
      recordingID: ids.recordingID
    )
    expectNoDifference(localQuery.namespace, "v3_capture_recordings")
    expectNoDifference(
      localQuery.filters,
      [.equals(field: "id", value: .string(ids.recordingID))]
    )
    expectNoDifference(
      localQuery.includes?.map { [$0.name, $0.direction.rawValue] },
      [
        ["owner", "forward"],
        ["attachments", "reverse"],
        ["members", "reverse"],
        ["transcriptions", "reverse"],
      ]
    )
    expectNoDifference(localQuery.includes?[2].query?.includes?.map(\.name), ["user"])

    let owner = InstantLinkedEntitySnapshot(
      id: ids.ownerID,
      namespace: "$users",
      values: [:]
    )
    let attachment = InstantLinkedEntitySnapshot(
      id: ids.attachmentID,
      namespace: "v3_capture_attachments",
      values: [
        "kind": .one(.string("text")),
        "contents": .one(.string("Cross-SDK notes")),
        "offsetMilliseconds": .one(.number(2_500)),
      ]
    )
    let member = InstantLinkedEntitySnapshot(
      id: ids.memberID,
      namespace: "v3_capture_members",
      values: ["role": .one(.string("owner"))],
      links: ["user": [owner]]
    )
    let transcription = InstantLinkedEntitySnapshot(
      id: ids.transcriptionID,
      namespace: "v3_capture_transcriptions",
      values: ["state": .one(.string("processing"))]
    )
    let recording = InstantEntitySnapshot(
      id: ids.recordingID,
      namespace: "v3_capture_recordings",
      values: [
        "title": .one(.string("Canonical recording")),
        "deviceID": .one(.string("typescript-e2e")),
        "state": .one(.string("recording")),
        "durationMilliseconds": .one(.number(0)),
      ],
      links: [
        "owner": [owner],
        "attachments": [attachment],
        "members": [member],
        "transcriptions": [transcription],
      ]
    )

    expectNoDifference(
      try InstantRecordingActionLiveContract.snapshot(from: [recording]),
      .object([
        "recording": .object([
          "id": .string(ids.recordingID),
          "title": .string("Canonical recording"),
          "deviceID": .string("typescript-e2e"),
          "state": .string("recording"),
          "durationMilliseconds": .number(0),
          "ownerID": .string(ids.ownerID),
        ]),
        "attachments": .array([
          .object([
            "id": .string(ids.attachmentID),
            "kind": .string("text"),
            "contents": .string("Cross-SDK notes"),
            "offsetMilliseconds": .number(2_500),
          ])
        ]),
        "members": .array([
          .object([
            "id": .string(ids.memberID),
            "role": .string("owner"),
            "userID": .string(ids.ownerID),
          ])
        ]),
        "transcriptions": .array([
          .object([
            "id": .string(ids.transcriptionID),
            "state": .string("processing"),
          ])
        ]),
      ])
    )
  }

  @Test
  func observedSnapshotDecodesCanonicalTypeScriptUpdate() throws {
    let snapshot = try InstantRecordingActionObservedSnapshot.decode(
      recordingSnapshots: [
        InstantEntitySnapshot(
          id: ids.recordingID,
          namespace: "v3_capture_recordings",
          values: [
            "title": .one(.string("Canonical recording")),
            "deviceID": .one(.string("swift-e2e")),
            "state": .one(.string("finished")),
            "durationMilliseconds": .one(.number(42_000)),
          ],
          links: [
            "owner": [
              InstantLinkedEntitySnapshot(
                id: ids.ownerID,
                namespace: "$users",
                values: [:]
              )
            ],
            "transcriptions": [
              InstantLinkedEntitySnapshot(
                id: ids.transcriptionID,
                namespace: "v3_capture_transcriptions",
                values: ["state": .one(.string("complete"))]
              )
            ],
          ]
        )
      ],
      ids: ids
    )

    expectNoDifference(
      snapshot,
      InstantRecordingActionObservedSnapshot(
        recordingID: ids.recordingID,
        title: "Canonical recording",
        ownerID: ids.ownerID,
        deviceID: "swift-e2e",
        recordingState: "finished",
        durationMilliseconds: 42_000,
        transcriptionID: ids.transcriptionID,
        transcriptionState: "complete"
      )
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
