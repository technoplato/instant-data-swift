import CustomDump
import InstantSwiftDataSchema
import Testing

// Canonical sources:
// pointfreeco/sqlite-data@0c79d7a5748fc6d9ce7a1ba2b50f31b175305049
// - Examples/Reminders/Schema.swift
// - Tests/SQLiteDataTests/CloudKitTests/SharingTests.swift
// - Tests/SQLiteDataTests/CloudKitTests/SharingPermissionsTests.swift
@Suite
struct RemindersV3ContractTests {
  @Test("Reminders preserves the established Instant entity shapes")
  func schemaPreservesListsRemindersAndTags() throws {
    let document = InstantSchemaExamples.remindersV3Document

    expectNoDifference(
      document.entities.map(\.namespace),
      [
        "$users",
        "remindersLists",
        "reminders",
        "tags",
        "v3_share_memberships",
        "v3_shares",
      ]
    )

    let lists = try #require(document.entities.first { $0.namespace == "remindersLists" })
    expectNoDifference(
      lists.attributes.map(\.name),
      ["id", "title", "color", "position", "createdAt"]
    )
    expectNoDifference(
      lists.attributes.map(\.valueType),
      [.string, .string, .string, .number, .date]
    )

    let reminders = try #require(document.entities.first { $0.namespace == "reminders" })
    expectNoDifference(
      reminders.attributes.map(\.name),
      [
        "id",
        "title",
        "notes",
        "isCompleted",
        "isFlagged",
        "dueDate",
        "priority",
        "position",
        "createdAt",
      ]
    )
    expectNoDifference(
      reminders.attributes.map(\.valueType),
      [.string, .string, .string, .boolean, .boolean, .date, .number, .number, .date]
    )
    expectNoDifference(
      reminders.attributes.filter { !$0.isRequired }.map(\.name),
      ["dueDate", "priority"]
    )

    let tags = try #require(document.entities.first { $0.namespace == "tags" })
    expectNoDifference(tags.attributes.map(\.name), ["id", "title"])
    expectNoDifference(tags.attributes.last?.isUnique, true)
  }

  @Test("Only list roots are shareable and reminders are cascading children")
  func schemaPreservesListRootSharingAndChildContainment() throws {
    let document = InstantSchemaExamples.remindersV3Document

    expectNoDifference(
      document.links.map(\.name),
      [
        "remindersList",
        "remindersTags",
        "remindersListsOwner",
        "remindersListsReaders",
        "remindersListsWriters",
        "v3_share_membershipsShare",
        "v3_share_membershipsUser",
        "v3_sharesOwner",
        "v3_sharesRoot",
      ]
    )

    let parent = try #require(document.links.first { $0.name == "remindersList" })
    expectNoDifference(parent.forward.namespace, "reminders")
    expectNoDifference(parent.forward.cardinality, .one)
    expectNoDifference(parent.forward.label, "list")
    expectNoDifference(parent.forward.onDelete, .cascade)
    expectNoDifference(parent.reverse.namespace, "remindersLists")
    expectNoDifference(parent.reverse.cardinality, .many)
    expectNoDifference(parent.reverse.label, "reminders")
    expectNoDifference(parent.isRequired, true)

    let root = try #require(document.links.first { $0.name == "v3_sharesRoot" })
    expectNoDifference(root.forward.namespace, "v3_shares")
    expectNoDifference(root.forward.label, "root")
    expectNoDifference(root.reverse.namespace, "remindersLists")
    expectNoDifference(root.reverse.label, "share")
    expectNoDifference(root.isRequired, true)
  }

  @Test("Lists expose owner reader and writer relations for generated permissions")
  func schemaPreservesVisibleSharingRoles() throws {
    let document = InstantSchemaExamples.remindersV3Document
    let roleLinks = document.links.filter { $0.forward.namespace == "remindersLists" }

    expectNoDifference(
      roleLinks.map(\.forward.label),
      ["owner", "readers", "writers"]
    )
    expectNoDifference(
      roleLinks.map(\.forward.cardinality),
      [.one, .many, .many]
    )
    expectNoDifference(
      roleLinks.map(\.reverse.label),
      ["ownedRemindersLists", "readableRemindersLists", "writableRemindersLists"]
    )
    expectNoDifference(roleLinks.map(\.isRequired), [true, nil, nil])
  }

  @Test("SQLiteData read-only participants can read a list and cannot mutate children")
  func permissionsSeparateReaderAndWriterCapabilities() throws {
    let namespaces = Dictionary(
      uniqueKeysWithValues: InstantSchemaExamples.remindersV3Permissions.namespaces.map {
        ($0.namespace, $0)
      }
    )

    let lists = try #require(namespaces["remindersLists"])
    let users = try #require(namespaces["$users"])
    expectNoDifference(
      users.link,
      [
        "ownedRemindersLists": "data.id == auth.id && actions.linkedData == 'create'",
        "readableRemindersLists": "auth.id in linkedData.ref('owner.id')",
        "writableRemindersLists": "auth.id in linkedData.ref('owner.id')",
        "ownedShares": "data.id == auth.id && actions.linkedData == 'create'",
        "shareMemberships": "auth.id in linkedData.ref('share.owner.id')",
      ]
    )
    expectNoDifference(
      lists.allow,
      [
        .view: "isOwner || isWriter || isReader",
        .create: "auth.id != null",
        .update: "isOwner || isWriter",
        .delete: "isOwner",
      ]
    )
    expectNoDifference(
      lists.bind,
      [
        InstantPermissionBinding("isOwner", "auth.id in data.ref('owner.id')"),
        InstantPermissionBinding("isWriter", "auth.id in data.ref('writers.id')"),
        InstantPermissionBinding("isReader", "auth.id in data.ref('readers.id')"),
      ]
    )
    expectNoDifference(
      lists.link,
      [
        "owner": "actions.data == 'create' || data.id in auth.ref('$user.ownedRemindersLists.id')",
        "readers": "data.id in auth.ref('$user.ownedRemindersLists.id')",
        "writers": "data.id in auth.ref('$user.ownedRemindersLists.id')",
        "share": "data.id in auth.ref('$user.ownedRemindersLists.id')",
        "reminders": "data.id in auth.ref('$user.ownedRemindersLists.id') || data.id in auth.ref('$user.writableRemindersLists.id')",
      ]
    )
    expectNoDifference(
      lists.unlink,
      [
        "owner": "data.id in auth.ref('$user.ownedRemindersLists.id')",
        "readers": "data.id in auth.ref('$user.ownedRemindersLists.id')",
        "writers": "data.id in auth.ref('$user.ownedRemindersLists.id')",
        "share": "data.id in auth.ref('$user.ownedRemindersLists.id')",
        "reminders": "data.id in auth.ref('$user.ownedRemindersLists.id') || data.id in auth.ref('$user.writableRemindersLists.id')",
      ]
    )

    let reminders = try #require(namespaces["reminders"])
    expectNoDifference(
      reminders.allow,
      [
        .view: "isOwner || isWriter || isReader",
        .create: "auth.id != null",
        .update: "isOwner || isWriter",
        .delete: "isOwner || isWriter",
      ]
    )
    expectNoDifference(
      reminders.bind,
      [
        InstantPermissionBinding("isOwner", "auth.id in data.ref('list.owner.id')"),
        InstantPermissionBinding("isWriter", "auth.id in data.ref('list.writers.id')"),
        InstantPermissionBinding("isReader", "auth.id in data.ref('list.readers.id')"),
      ]
    )
    expectNoDifference(reminders.link, [:])
  }

  @Test("Tags inherit visibility from linked reminder list roots")
  func permissionsKeepTagsInsideVisibleSharedLists() throws {
    let tags = try #require(
      InstantSchemaExamples.remindersV3Permissions.namespaces.first {
        $0.namespace == "tags"
      }
    )

    expectNoDifference(
      tags.allow,
      [
        .view: "isOwner || isWriter || isReader",
        .create: "auth.id != null",
        .update: "isOwner || isWriter",
        .delete: "isOwner",
      ]
    )
    expectNoDifference(
      tags.bind,
      [
        InstantPermissionBinding(
          "isOwner",
          "auth.id in data.ref('reminders.list.owner.id')"
        ),
        InstantPermissionBinding(
          "isWriter",
          "auth.id in data.ref('reminders.list.writers.id')"
        ),
        InstantPermissionBinding(
          "isReader",
          "auth.id in data.ref('reminders.list.readers.id')"
        ),
      ]
    )
    expectNoDifference(
      tags.link,
      [
        "reminders": "actions.data == 'create' || actions.linkedData == 'create' || auth.id in linkedData.ref('list.owner.id') || auth.id in linkedData.ref('list.writers.id')"
      ]
    )
  }

  @Test("Share metadata remains owner managed and member visible")
  func permissionsPreserveAcceptAndRevokeMetadata() throws {
    let namespaces = Dictionary(
      uniqueKeysWithValues: InstantSchemaExamples.remindersV3Permissions.namespaces.map {
        ($0.namespace, $0)
      }
    )

    expectNoDifference(
      namespaces["v3_shares"]?.allow,
      [
        .view: "isOwner || isMember",
        .create: "auth.id != null",
        .update: "isOwner",
        .delete: "isOwner",
      ]
    )
    expectNoDifference(
      namespaces["v3_shares"]?.link,
      [
        "owner": "actions.data == 'create' || auth.id in data.ref('owner.id')",
        "root": "actions.data == 'create' || auth.id in data.ref('owner.id')",
        "memberships": "auth.id in data.ref('owner.id')",
      ]
    )
    expectNoDifference(
      namespaces["v3_share_memberships"]?.allow,
      [
        .view: "isSelf || isShareOwner",
        .create: "auth.id != null",
        .update: "isShareOwner",
        .delete: "isShareOwner",
      ]
    )
    expectNoDifference(
      namespaces["v3_share_memberships"]?.link,
      [
        "share": "actions.data == 'create' || auth.id in data.ref('share.owner.id')",
        "user": "actions.data == 'create' || auth.id in data.ref('share.owner.id')",
      ]
    )
  }
}
