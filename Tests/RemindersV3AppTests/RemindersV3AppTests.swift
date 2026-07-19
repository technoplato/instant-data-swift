import CustomDump
import Foundation
import InstantSwiftData
import RemindersV3App
import Testing

@Suite
struct RemindersV3AppTests {
  // Source adaptation:
  // pointfreeco/sqlite-data@0c79d7a5748fc6d9ce7a1ba2b50f31b175305049
  // - Examples/RemindersTests/RemindersListsTests.swift
  // - Examples/RemindersTests/RemindersDetailsTests.swift
  // SQLiteData commits the parent foreign key with each inserted row. The Instant
  // port must preserve that atomic shape by lowering owner/list refs into the same
  // create transaction, rather than repairing relationships in a later mutation.
  @Test
  func canonicalCreatesLowerRequiredRelationshipsAtomically() async throws {
    let persistenceURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("reminders-v3-transport-\(UUID().uuidString).sqlite")
    defer { try? FileManager.default.removeItem(at: persistenceURL) }
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "reminders-v3-transport-tests",
        persistenceURL: persistenceURL,
        initialAttributes: RemindersV3Schema.attributes
      )
    )
    let client = InstantSwiftDataClient(runtime: runtime)
    let ownerID = InstantID<RemindersV3User>(
      rawValue: "00000000-0000-4000-8000-000000000401"
    )
    let listID = InstantID<RemindersV3List>(
      rawValue: "00000000-0000-4000-8000-000000000402"
    )
    let reminderID = InstantID<RemindersV3Reminder>(
      rawValue: "00000000-0000-4000-8000-000000000403"
    )
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

    let pending = await client.pendingMutations()
    expectNoDifference(pending.count, 2)
    let listTransport = InstantTransportMutation(try #require(pending.first))
    let reminderTransport = InstantTransportMutation(try #require(pending.last))

    expectNoDifference(listTransport.preconditions.map(\.kind), [.entityMissing])
    expectNoDifference(reminderTransport.preconditions.map(\.kind), [.entityMissing])
    expectNoDifference(
      try requiredRef(in: listTransport, attributeID: "remindersLists/owner"),
      .init(value: ownerID.rawValue, mode: .create)
    )
    expectNoDifference(
      try requiredRef(in: reminderTransport, attributeID: "reminders/list"),
      .init(value: listID.rawValue, mode: .create)
    )
  }

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

  private struct RequiredRef: Equatable, Sendable {
    var value: String
    var mode: InstantTransportOptions.Mode?
  }

  private func requiredRef(
    in mutation: InstantTransportMutation,
    attributeID: String
  ) throws -> RequiredRef {
    for step in mutation.txSteps {
      guard case let .addTriple(_, candidateAttributeID, value, options) = step,
        candidateAttributeID == attributeID,
        case let .string(rawValue) = value
      else { continue }
      return RequiredRef(value: rawValue, mode: options?.mode)
    }
    Issue.record("Missing required ref step for \(attributeID)")
    throw CancellationError()
  }
}
