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
}
