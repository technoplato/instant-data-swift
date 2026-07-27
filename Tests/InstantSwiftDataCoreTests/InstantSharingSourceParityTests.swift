import CustomDump
import Foundation
@testable import InstantSwiftDataCore
import Testing

@Suite(.serialized)
struct InstantSharingSourceParityTests {
  // Source: pointfreeco/sqlite-data@0c79d7a5748fc6d9ce7a1ba2b50f31b175305049
  // Examples/RemindersTests/RemindersListsTests.swift
  // Adaptation: InstantShareSnapshot replaces CKShare and explicit load() replaces @Fetch loading.
  @Test("SQLiteData RemindersListsTests.basics")
  func remindersListsModelLoadsSourceCountsStatsAndTags() async throws {
    let fixture = try await remindersListsSourceFixture()
    defer { try? FileManager.default.removeItem(at: fixture.cacheURL.deletingLastPathComponent()) }
    var model = RemindersListsModel(runtime: fixture.runtime, now: { fixture.now })

    try await model.load()

    expectNoDifference(model.remindersLists.map(\.remindersCount), [4, 2, 2])
    expectNoDifference(model.remindersLists.map(\.remindersList.title), [
      "Personal",
      "Family",
      "Business",
    ])
    expectNoDifference(model.remindersLists.map(\.share), [nil, nil, nil])
    expectNoDifference(
      model.stats,
      RemindersStats(
        allCount: 8,
        completedCount: 3,
        flaggedCount: 2,
        scheduledCount: 7,
        todayCount: 2
      )
    )
    expectNoDifference(model.tags.map(\.title), [
      "adulting",
      "car",
      "kids",
      "night",
      "optional",
      "social",
      "someday",
    ])
  }

  @Test("SQLiteData RemindersListsTests.move")
  func remindersListsModelMovesSourceListToFront() async throws {
    let fixture = try await remindersListsSourceFixture()
    defer { try? FileManager.default.removeItem(at: fixture.cacheURL.deletingLastPathComponent()) }
    var model = RemindersListsModel(runtime: fixture.runtime, now: { fixture.now })
    try await model.load()
    expectNoDifference(model.remindersLists.map(\.remindersList.title), [
      "Personal",
      "Family",
      "Business",
    ])

    try await model.move(
      fromOffsets: [2],
      toOffset: 0,
      updatedAt: InstantTimestamp(milliseconds: fixture.now.milliseconds + 1_000),
      transactionID: "tx-source-reminders-lists-move"
    )

    expectNoDifference(model.remindersLists.map(\.remindersList.title), [
      "Business",
      "Personal",
      "Family",
    ])
  }

  @Test("SQLiteData RemindersListsTests.share")
  func remindersListsModelLoadsSourceShareMetadata() async throws {
    let fixture = try await remindersListsSourceFixture()
    defer { try? FileManager.default.removeItem(at: fixture.cacheURL.deletingLastPathComponent()) }
    let created = try await fixture.runtime.createShare(
      rootNamespace: ReminderExample.listsNamespace,
      rootID: fixture.personalListID
    )
    var model = RemindersListsModel(runtime: fixture.runtime, now: { fixture.now })

    try await model.load()

    expectNoDifference(model.remindersLists.map(\.remindersCount), [4, 2, 2])
    expectNoDifference(model.remindersLists.map(\.share?.id), [created.id, nil, nil])
  }

  @Test("SQLiteData SharingPermissionsTests.insertRecordInReadOnlyRemindersList")
  func readOnlySharedListRejectsChildInsertBeforePersistence() async throws {
    let cacheURL = temporarySharingCacheURL()
    defer { try? FileManager.default.removeItem(at: cacheURL) }
    let now = InstantTimestamp(milliseconds: 1_700_000_000_000)
    let listID = "list-read-only"
    let owner = try await sharingRuntime(cacheURL: cacheURL, now: now)
    _ = try await owner.signInWithRefreshToken("owner-refresh", userID: "owner-user")
    try await owner.transact(
      InstantStoreTransaction(
        id: "create-list",
        operations: ReminderExample.createListOperations(
          id: listID,
          title: "Personal",
          position: 0,
          createdAt: now,
          transactionID: "create-list"
        )
      ),
      createdAt: now
    )
    let share = try await owner.createShare(
      rootNamespace: ReminderExample.listsNamespace,
      rootID: listID
    )

    let reader = try await sharingRuntime(cacheURL: cacheURL, now: now)
    _ = try await reader.signInWithRefreshToken("reader-refresh", userID: "reader-user")
    _ = try await reader.acceptShare(token: share.share.token)
    let pendingBefore = await reader.pendingMutations()

    do {
      try await reader.transact(
        InstantStoreTransaction(
          id: "reader-insert",
          operations: ReminderExample.createReminderOperations(
            id: "reader-reminder",
            listID: listID,
            title: "Get milk",
            position: 0,
            createdAt: now,
            transactionID: "reader-insert"
          )
        ),
        createdAt: now
      )
      Issue.record("Expected a read-only shared-list insert to be rejected.")
    } catch let error as InstantError {
      expectNoDifference(error.code, .permissionRejected)
      expectNoDifference(error.operation, "write shared root")
      expectNoDifference(error.namespace, ReminderExample.listsNamespace)
      expectNoDifference(error.localID, listID)
    }

    let pendingAfter = await reader.pendingMutations()
    let readerReminders = try ReminderExample.decodeReminders(
      try await reader.query(ReminderExample.remindersForListQuery(listID))
    )
    expectNoDifference(pendingAfter, pendingBefore)
    expectNoDifference(
      readerReminders,
      []
    )
  }

  @Test("SQLiteData RemindersListsTests.share")
  func sharedListBecomesVisibleWithOwnerMembership() async throws {
    let cacheURL = temporarySharingCacheURL()
    defer { try? FileManager.default.removeItem(at: cacheURL) }
    let now = InstantTimestamp(milliseconds: 1_700_000_000_000)
    let runtime = try await sharingRuntime(cacheURL: cacheURL, now: now)
    _ = try await runtime.signInWithRefreshToken("owner-refresh", userID: "owner-user")
    try await runtime.transact(
      InstantStoreTransaction(
        id: "create-list",
        operations: ReminderExample.createListOperations(
          id: "personal-list",
          title: "Personal",
          position: 0,
          createdAt: now,
          transactionID: "create-list"
        )
      ),
      createdAt: now
    )

    let created = try await runtime.createShare(
      rootNamespace: ReminderExample.listsNamespace,
      rootID: "personal-list"
    )

    let visibleShares = try await runtime.shares()
    expectNoDifference(visibleShares, [created])
    expectNoDifference(created.share.rootNamespace, ReminderExample.listsNamespace)
    expectNoDifference(created.share.rootID, "personal-list")
    expectNoDifference(created.memberships.map(\.userID), ["owner-user"])
    expectNoDifference(created.memberships.map(\.role), [.owner])
  }

  private func sharingRuntime(
    cacheURL: URL,
    now: InstantTimestamp
  ) async throws -> InstantRuntime {
    try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "sharing-source-parity",
        persistenceURL: cacheURL,
        initialAttributes: ReminderExample.attributes,
        now: { now },
        makeID: { "sharing-source-id" }
      )
    )
  }

  private func temporarySharingCacheURL() -> URL {
    FileManager.default.temporaryDirectory
      .appendingPathComponent("instant-sharing-source-parity-\(UUID().uuidString).sqlite")
  }

  private struct RemindersListsSourceFixture {
    var cacheURL: URL
    var runtime: InstantRuntime
    var now: InstantTimestamp
    var personalListID: String
  }

  private func remindersListsSourceFixture() async throws -> RemindersListsSourceFixture {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("instant-reminders-lists-source-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let cacheURL = directory.appendingPathComponent("state.sqlite")
    let now = InstantTimestamp(milliseconds: 1_234_567_890_000)
    let day: Int64 = 24 * 60 * 60 * 1000
    let personalListID = "00000000-0000-0000-0000-000000000000"
    let familyListID = "00000000-0000-0000-0000-000000000001"
    let businessListID = "00000000-0000-0000-0000-000000000002"
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "reminders-lists-source-parity",
        persistenceURL: cacheURL,
        initialAttributes: ReminderExample.attributes,
        now: { now },
        makeID: { UUID().uuidString.lowercased() }
      )
    )
    _ = try await runtime.signInWithRefreshToken("owner-refresh", userID: "owner-user")

    let lists: [(id: String, seed: RemindersListSeedRecord)] = [
      (
        personalListID,
        RemindersListSeedRecord(
          localIDName: "source.personal",
          title: "Personal",
          color: "#4895ef",
          position: 1,
          createdAtOffsetMilliseconds: 0
        )
      ),
      (
        familyListID,
        RemindersListSeedRecord(
          localIDName: "source.family",
          title: "Family",
          color: "#ed8935",
          position: 2,
          createdAtOffsetMilliseconds: 1
        )
      ),
      (
        businessListID,
        RemindersListSeedRecord(
          localIDName: "source.business",
          title: "Business",
          color: "#b25dd3",
          position: 3,
          createdAtOffsetMilliseconds: 2
        )
      ),
    ]
    let reminders: [(id: String, listID: String, seed: ReminderSeedRecord)] = [
      sourceReminder(3, personalListID, "Groceries", notes: "Milk\nEggs\nApples\nOatmeal\nSpinach", position: 1, tags: ["someday", "optional", "adulting"]),
      sourceReminder(4, personalListID, "Haircut", isFlagged: true, dueDateOffset: -2 * day, position: 2, tags: ["someday", "optional"]),
      sourceReminder(5, personalListID, "Doctor appointment", notes: "Ask about diet", dueDateOffset: 0, priority: .high, position: 3, tags: ["adulting"]),
      sourceReminder(6, personalListID, "Take a walk", isCompleted: true, dueDateOffset: -190 * day, position: 4, tags: ["car", "kids", "social"]),
      sourceReminder(7, personalListID, "Buy concert tickets", dueDateOffset: 0, position: 5, tags: ["social", "night"]),
      sourceReminder(8, familyListID, "Pick up kids from school", isFlagged: true, dueDateOffset: 2 * day, priority: .high, position: 6),
      sourceReminder(9, familyListID, "Get laundry", isCompleted: true, dueDateOffset: -2 * day, priority: .low, position: 7),
      sourceReminder(10, familyListID, "Take out trash", dueDateOffset: 4 * day, priority: .high, position: 8),
      sourceReminder(11, businessListID, "Call accountant", notes: "Status of tax return\nExpenses for next year\nChanging payroll company", dueDateOffset: 2 * day, position: 9),
      sourceReminder(12, businessListID, "Send weekly emails", isCompleted: true, dueDateOffset: -2 * day, priority: .medium, position: 10),
      sourceReminder(13, businessListID, "Prepare for WWDC", dueDateOffset: 2 * day, position: 11, tags: ["social"]),
    ]
    let tagIDs = ["car", "kids", "someday", "optional", "social", "night", "adulting"]
    try await runtime.transact(
      InstantStoreTransaction(
        id: "tx-source-reminders-lists-seed",
        operations: ReminderExample.seedOperations(
          lists: lists,
          reminders: reminders,
          tags: tagIDs.map { (id: $0, seed: ReminderTagSeedRecord(title: $0)) },
          reminderTags: reminders.flatMap { reminder in
            reminder.seed.tagTitles.map { (reminderID: reminder.id, tagID: $0) }
          },
          baseCreatedAt: now,
          transactionID: "tx-source-reminders-lists-seed"
        )
      ),
      createdAt: now
    )
    return RemindersListsSourceFixture(
      cacheURL: cacheURL,
      runtime: runtime,
      now: now,
      personalListID: personalListID
    )
  }

  private func sourceReminder(
    _ id: Int,
    _ listID: String,
    _ title: String,
    notes: String = "",
    isCompleted: Bool = false,
    isFlagged: Bool = false,
    dueDateOffset: Int64? = nil,
    priority: ReminderPriority? = nil,
    position: Int,
    tags: [String] = []
  ) -> (id: String, listID: String, seed: ReminderSeedRecord) {
    (
      id: String(format: "00000000-0000-0000-0000-%012d", id),
      listID: listID,
      seed: ReminderSeedRecord(
        localIDName: "source.reminder.\(id)",
        listLocalIDName: "source.list.\(listID)",
        title: title,
        notes: notes,
        isCompleted: isCompleted,
        isFlagged: isFlagged,
        dueDateOffsetMilliseconds: dueDateOffset,
        priority: priority,
        position: position,
        createdAtOffsetMilliseconds: Int64(id),
        tagTitles: tags
      )
    )
  }
}
