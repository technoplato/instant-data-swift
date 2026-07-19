import CustomDump
import Foundation
import InstantSwiftData
import RemindersV3App
import Testing

// Canonical sources:
// pointfreeco/sqlite-data@0c79d7a5748fc6d9ce7a1ba2b50f31b175305049
// - Examples/Reminders/Schema.swift
// - Examples/Reminders/RemindersLists.swift
// - Examples/Reminders/RemindersDetail.swift
// - Tests/SQLiteDataTests/CloudKitTests/SharingTests.swift
@Suite
struct RemindersV3SourceContractTests {
  @Test
  func desiredTypedEntityAndQuerySyntaxCompiles() {
    let userID = InstantID<RemindersV3User>(rawValue: "user-1")
    let listID = InstantID<RemindersV3List>(rawValue: "list-1")
    let lists = FetchAll(RemindersV3List.visible(to: userID))
    let reminders = FetchAll(RemindersV3Reminder.forList(listID))
    let allReminders = FetchAll(
      RemindersV3Reminder.forList(listID, includeCompleted: true)
    )
    let tags = FetchAll(RemindersV3Tag.query.order(RemindersV3Tag.title))
    let listDraft = RemindersV3List.Draft(
      title: "Family",
      color: "#4a99ef",
      position: 0,
      createdAt: Date(timeIntervalSince1970: 1_700_000_000),
      owner: userID
    )
    let reminderDraft = RemindersV3Reminder.Draft(
      title: "Pack lunch",
      notes: "Fruit and water",
      isCompleted: false,
      isFlagged: true,
      dueDate: Date(timeIntervalSince1970: 1_700_086_400),
      priority: .high,
      position: 0,
      createdAt: Date(timeIntervalSince1970: 1_700_000_001),
      list: listID
    )

    _ = lists
    _ = reminders
    _ = allReminders
    _ = tags
    _ = listDraft
    _ = reminderDraft
    _ = CreateRemindersV3List(
      listID: listID,
      ownerID: userID,
      title: "Family",
      position: 0,
      createdAt: Date(timeIntervalSince1970: 1_700_000_000)
    )
    _ = CreateRemindersV3Reminder(
      reminderID: InstantID(rawValue: "reminder-1"),
      listID: listID,
      title: "Pack lunch",
      position: 0,
      createdAt: Date(timeIntervalSince1970: 1_700_000_001),
      tagIDs: [InstantID(rawValue: "family")]
    )
    _ = CreateRemindersV3Share(
      shareID: InstantID(rawValue: "share-1"),
      ownerMembershipID: InstantID(rawValue: "membership-owner"),
      listID: listID,
      ownerID: userID,
      token: "share-token",
      createdAt: Date(timeIntervalSince1970: 1_700_000_000)
    )
  }

  @Test
  func typedEntitiesPreserveNamespacesAndWireAttributes() {
    expectNoDifference(RemindersV3List.instantNamespace, "remindersLists")
    expectNoDifference(RemindersV3Reminder.instantNamespace, "reminders")
    expectNoDifference(RemindersV3Tag.instantNamespace, "tags")
    expectNoDifference(RemindersV3Share.instantNamespace, "v3_shares")
    expectNoDifference(
      RemindersV3ShareMembership.instantNamespace,
      "v3_share_memberships"
    )
    expectNoDifference(
      RemindersV3List.instantAttributes.map(\.name),
      [
        "id", "title", "color", "position", "createdAt", "owner", "readers", "writers",
      ]
    )
    expectNoDifference(
      RemindersV3Reminder.instantAttributes.map(\.name),
      [
        "id", "title", "notes", "isCompleted", "isFlagged", "dueDate", "priority",
        "position", "createdAt", "list", "tags",
      ]
    )
  }

  @Test
  func priorityUsesTheUpstreamNumericWireRanks() throws {
    let encoder = JSONEncoder()
    expectNoDifference(
      String(decoding: try encoder.encode(RemindersV3Priority.low), as: UTF8.self),
      "1"
    )
    expectNoDifference(
      String(decoding: try encoder.encode(RemindersV3Priority.medium), as: UTF8.self),
      "2"
    )
    expectNoDifference(
      String(decoding: try encoder.encode(RemindersV3Priority.high), as: UTF8.self),
      "3"
    )
  }
}
