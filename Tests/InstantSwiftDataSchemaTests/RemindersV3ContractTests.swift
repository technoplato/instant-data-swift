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
}
