import CustomDump
import Foundation
@testable import InstantSwiftDataCore
import Testing

@Suite(.serialized)
struct InstantSharingSourceParityTests {
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
}
