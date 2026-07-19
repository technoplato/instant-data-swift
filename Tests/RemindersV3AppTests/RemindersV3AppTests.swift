import CustomDump
import Foundation
import InstantSwiftData
import RemindersV3App
import Testing

@Suite
struct RemindersV3AppTests {
  @Test
  func typedMessagesMaterializeTheListReminderAndTagGraph() async throws {
    let persistenceURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("reminders-v3-app-\(UUID().uuidString).sqlite")
    defer { try? FileManager.default.removeItem(at: persistenceURL) }
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "reminders-v3-app-tests",
        persistenceURL: persistenceURL,
        initialAttributes: RemindersV3Schema.attributes
      )
    )
    let client = InstantSwiftDataClient(runtime: runtime)
    let ownerID = InstantID<RemindersV3User>(rawValue: "owner-user")
    let listID = InstantID<RemindersV3List>(rawValue: "list-family")
    let reminderID = InstantID<RemindersV3Reminder>(rawValue: "reminder-lunch")
    let familyTagID = InstantID<RemindersV3Tag>(rawValue: "family")
    let homeTagID = InstantID<RemindersV3Tag>(rawValue: "home")
    let createdAt = Date(timeIntervalSince1970: 1_700_000_000)
    let dueDate = Date(timeIntervalSince1970: 1_700_086_400)
    let createdAtTimestamp = InstantTimestamp(milliseconds: 1_700_000_000_000)

    _ = try await runtime.transact(
      InstantStoreTransaction(
        id: "seed-owner-user",
        operations: [
          .insert(
            InstantTriple(
              entityID: ownerID.rawValue,
              attributeID: "$users/id",
              value: .string(ownerID.rawValue),
              txID: "seed-owner-user",
              txTime: createdAtTimestamp
            )
          )
        ]
      ),
      createdAt: createdAtTimestamp
    )

    try await transact(
      CreateRemindersV3List(
        listID: listID,
        ownerID: ownerID,
        title: "Family",
        position: 0,
        createdAt: createdAt
      ),
      using: client
    )
    try await transact(
      CreateRemindersV3Reminder(
        reminderID: reminderID,
        listID: listID,
        title: "Pack lunch",
        notes: "Fruit and water",
        isFlagged: true,
        dueDate: dueDate,
        priority: .high,
        position: 0,
        createdAt: createdAt.addingTimeInterval(1),
        tagIDs: [familyTagID]
      ),
      using: client
    )
    try await transact(
      UpdateRemindersV3Reminder(
        reminderID: reminderID,
        listID: listID,
        title: "Pack school lunch",
        notes: "Fruit, water, and a sandwich",
        isFlagged: false,
        dueDate: dueDate,
        priority: .medium,
        existingTagIDs: [familyTagID],
        tagIDs: [homeTagID]
      ),
      using: client
    )

    let lists = FetchAll(RemindersV3List.visible(to: ownerID))
    try await lists.load(using: client)
    expectNoDifference(
      lists.wrappedValue,
      [
        RemindersV3List(
          id: listID,
          title: "Family",
          color: "#4a99ef",
          position: 0,
          createdAt: createdAt,
          owner: ownerID,
          reminders: [
            RemindersV3Reminder(
              id: reminderID,
              title: "Pack school lunch",
              notes: "Fruit, water, and a sandwich",
              isCompleted: false,
              isFlagged: false,
              dueDate: dueDate,
              priority: .medium,
              position: 0,
              createdAt: createdAt.addingTimeInterval(1),
              list: listID,
              tags: [RemindersV3Tag(id: homeTagID, title: "home")]
            )
          ]
        )
      ]
    )
  }

  @Test
  func completionAndDeletesPreserveListContainment() async throws {
    let persistenceURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("reminders-v3-delete-\(UUID().uuidString).sqlite")
    defer { try? FileManager.default.removeItem(at: persistenceURL) }
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "reminders-v3-delete-tests",
        persistenceURL: persistenceURL,
        initialAttributes: RemindersV3Schema.attributes
      )
    )
    let client = InstantSwiftDataClient(runtime: runtime)
    let ownerID = InstantID<RemindersV3User>(rawValue: "owner-user")
    let listID = InstantID<RemindersV3List>(rawValue: "list-family")
    let reminderID = InstantID<RemindersV3Reminder>(rawValue: "reminder-lunch")
    let createdAt = Date(timeIntervalSince1970: 1_700_000_000)

    try await transact(
      CreateRemindersV3List(
        listID: listID,
        ownerID: ownerID,
        title: "Family",
        position: 0,
        createdAt: createdAt
      ),
      using: client
    )
    try await transact(
      CreateRemindersV3Reminder(
        reminderID: reminderID,
        listID: listID,
        title: "Pack lunch",
        position: 0,
        createdAt: createdAt
      ),
      using: client
    )
    try await transact(
      SetRemindersV3Completion(
        reminderID: reminderID,
        listID: listID,
        isCompleted: true
      ),
      using: client
    )

    let incomplete = FetchAll(RemindersV3Reminder.forList(listID))
    try await incomplete.load(using: client)
    expectNoDifference(incomplete.wrappedValue, [])

    let all = FetchAll(RemindersV3Reminder.forList(listID, includeCompleted: true))
    try await all.load(using: client)
    expectNoDifference(all.wrappedValue.map(\.isCompleted), [true])

    try await transact(
      DeleteRemindersV3Reminder(reminderID: reminderID, listID: listID),
      using: client
    )
    try await all.load(using: client)
    expectNoDifference(all.wrappedValue, [])
  }

  private func transact<Message: InstantMessage>(
    _ message: Message,
    using client: InstantSwiftDataClient
  ) async throws {
    let prepared = try await message.prepare(using: client)
    _ = try await client.transact {
      for mutation in prepared.mutations { mutation }
    }
  }
}
