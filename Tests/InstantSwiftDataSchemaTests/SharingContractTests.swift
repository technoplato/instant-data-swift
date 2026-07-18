import CustomDump
import InstantSwiftDataSchema
import Testing

@Suite
struct SharingContractTests {
  @Test("SQLiteData SharingPermissionsTests adapted to an Instant sharing graph")
  func sharingSchemaDeclaresRootsSharesMembershipsAndRoles() {
    let document = InstantSchemaExamples.sharingDocument

    expectNoDifference(
      document.entities.map(\.namespace).sorted(),
      ["$users", "v3_share_memberships", "v3_shared_lists", "v3_shares"]
    )
    expectNoDifference(
      document.links.map(\.name).sorted(),
      [
        "v3_share_membershipsShare",
        "v3_share_membershipsUser",
        "v3_shared_listsOwner",
        "v3_shared_listsReaders",
        "v3_shared_listsWriters",
        "v3_sharesOwner",
        "v3_sharesRoot",
      ]
    )
  }

  @Test("SQLiteData read-only and read-write sharing permissions")
  func sharingPermissionsSeparateReaderAndWriterCapabilities() {
    let namespaces = Dictionary(
      uniqueKeysWithValues: InstantSchemaExamples.sharingPermissions.namespaces.map {
        ($0.namespace, $0.allow)
      }
    )

    expectNoDifference(
      namespaces["$users"],
      [
        .view: "auth.id != null",
      ]
    )
    expectNoDifference(
      namespaces["v3_shared_lists"],
      [
        .view: "isOwner || isWriter || isReader",
        .create: "isOwner",
        .update: "isOwner || isWriter",
        .delete: "isOwner",
      ]
    )
    expectNoDifference(
      namespaces["v3_shares"],
      [
        .view: "isOwner || isMember",
        .create: "isOwner",
        .update: "isOwner",
        .delete: "isOwner",
      ]
    )
    expectNoDifference(
      namespaces["v3_share_memberships"],
      [
        .view: "isSelf || isShareOwner",
        .create: "isSelf || isShareOwner",
        .update: "isShareOwner",
        .delete: "isShareOwner",
      ]
    )
  }

  @Test("VoiceTrail uses the canonical share graph with recording roots")
  func voiceTrailSchemaTargetsCaptureRecordings() {
    let document = InstantSchemaExamples.voiceTrailDocument

    expectNoDifference(
      document.entities.map(\.namespace).sorted(),
      [
        "$users",
        "v3_capture_attachments",
        "v3_capture_recordings",
        "v3_capture_transcriptions",
        "v3_share_memberships",
        "v3_shares",
      ]
    )
    expectNoDifference(
      document.links.map(\.name).sorted(),
      [
        "v3_capture_attachmentsRecording",
        "v3_capture_recordingsOwner",
        "v3_capture_recordingsReaders",
        "v3_capture_recordingsWriters",
        "v3_capture_transcriptionsRecording",
        "v3_share_membershipsShare",
        "v3_share_membershipsUser",
        "v3_sharesOwner",
        "v3_sharesRoot",
      ]
    )
    expectNoDifference(document.rooms.map(\.name), ["recording.playback"])
    let root = document.links.first { $0.name == "v3_sharesRoot" }
    expectNoDifference(root?.forward.namespace, "v3_shares")
    expectNoDifference(root?.forward.label, "root")
    expectNoDifference(root?.reverse.namespace, "v3_capture_recordings")
    expectNoDifference(root?.reverse.label, "share")
  }

  @Test("VoiceTrail permissions preserve owner reader and writer capabilities")
  func voiceTrailPermissionsSeparateRoles() {
    let namespaces = Dictionary(
      uniqueKeysWithValues: InstantSchemaExamples.voiceTrailPermissions.namespaces.map {
        ($0.namespace, $0.allow)
      }
    )

    expectNoDifference(
      namespaces["v3_capture_recordings"],
      [
        .view: "isOwner || isWriter || isReader",
        .create: "isOwner",
        .update: "isOwner || isWriter",
        .delete: "isOwner",
      ]
    )
    for namespace in ["v3_capture_attachments", "v3_capture_transcriptions"] {
      expectNoDifference(
        namespaces[namespace],
        [
          .view: "isOwner || isWriter || isReader",
          .create: "isOwner || isWriter",
          .update: "isOwner || isWriter",
          .delete: "isOwner || isWriter",
        ]
      )
    }
    expectNoDifference(
      namespaces["v3_shares"],
      [
        .view: "isOwner || isMember",
        .create: "isOwner",
        .update: "isOwner",
        .delete: "isOwner",
      ]
    )
  }
}
