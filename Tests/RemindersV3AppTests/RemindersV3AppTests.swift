import CustomDump
import Foundation
import InstantSwiftData
import RemindersV3App
import Testing

#if canImport(SwiftUI)
  import SwiftUI
  #if os(macOS)
    import AppKit
  #endif
#endif

@Suite(.serialized)
struct RemindersV3AppTests {
  // Source adaptation:
  // pointfreeco/sqlite-data@0c79d7a5748fc6d9ce7a1ba2b50f31b175305049
  // - Examples/RemindersTests/RemindersListsTests.swift
  // - Examples/RemindersTests/RemindersDetailsTests.swift
  // SQLiteData commits the parent foreign key with each inserted row. The Instant
  // port must preserve that atomic shape by lowering owner/list refs into the same
  // create transaction, rather than repairing relationships in a later mutation.
  @Test
  func appConfigurationReadsLiveEndpointsAndIsolatedPersistenceFromEnvironment() throws {
    let configuration = RemindersV3AppConfiguration.environment([
      "INSTANT_APP_ID": " live-reminders ",
      "INSTANT_API_URI": "http://127.0.0.1:18080",
      "INSTANT_WEBSOCKET_URI": "ws://127.0.0.1:18081/runtime/session",
      "INSTANT_PERSISTENCE_PATH": "/tmp/reminders-environment.sqlite",
      "REMINDERS_V3_USER_ID": " 00000000-0000-4000-8000-000000000001 ",
      "REMINDERS_V3_REFRESH_TOKEN": " demo-refresh-token ",
    ])

    expectNoDifference(configuration.appID, "live-reminders")
    expectNoDifference(configuration.apiURI.absoluteString, "http://127.0.0.1:18080")
    expectNoDifference(
      configuration.websocketURI.absoluteString,
      "ws://127.0.0.1:18081/runtime/session"
    )
    expectNoDifference(configuration.persistenceURL?.path, "/tmp/reminders-environment.sqlite")
    expectNoDifference(configuration.enablesLiveSync, true)
    expectNoDifference(
      configuration.userIDOverride?.rawValue,
      "00000000-0000-4000-8000-000000000001"
    )
    expectNoDifference(configuration.refreshTokenOverride, "demo-refresh-token")

    let local = RemindersV3AppConfiguration.environment([:])
    expectNoDifference(local.appID, "reminders-v3-local")
    expectNoDifference(local.apiURI, InstantRuntimeConfiguration.defaultAPIURI)
    expectNoDifference(local.websocketURI, InstantRuntimeConfiguration.defaultWebSocketURI)
    expectNoDifference(local.enablesLiveSync, false)
    expectNoDifference(local.userIDOverride, nil)
    expectNoDifference(local.refreshTokenOverride, nil)

    let bundled = RemindersV3AppConfiguration.environment(
      [:],
      bundledAppID: "reminders-bundled-live"
    )
    expectNoDifference(bundled.appID, "reminders-bundled-live")
    expectNoDifference(bundled.enablesLiveSync, true)
  }

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

    try await transact(DeleteRemindersV3Tag(tagID: homeTagID), using: client)
    try await lists.load(using: client)
    expectNoDifference(lists.wrappedValue.first?.reminders.first?.tags, [])
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

  @Test
  func bulkCompletedCleanupDeletesOnlyExplicitCompletedTargets() async throws {
    let persistenceURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("reminders-v3-completed-cleanup-\(UUID().uuidString).sqlite")
    defer { try? FileManager.default.removeItem(at: persistenceURL) }
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "reminders-v3-completed-cleanup-tests",
        persistenceURL: persistenceURL,
        initialAttributes: RemindersV3Schema.attributes
      )
    )
    let client = InstantSwiftDataClient(runtime: runtime)
    let ownerID = InstantID<RemindersV3User>(rawValue: "owner-user")
    let listID = InstantID<RemindersV3List>(rawValue: "list-family")
    let oldCompletedID = InstantID<RemindersV3Reminder>(rawValue: "old-completed")
    let openID = InstantID<RemindersV3Reminder>(rawValue: "open-reminder")
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
    for (position, reminderID) in [oldCompletedID, openID].enumerated() {
      try await transact(
        CreateRemindersV3Reminder(
          reminderID: reminderID,
          listID: listID,
          title: "Reminder \(position)",
          position: position,
          createdAt: createdAt.addingTimeInterval(Double(position))
        ),
        using: client
      )
    }
    try await transact(
      SetRemindersV3Completion(
        reminderID: oldCompletedID,
        listID: listID,
        isCompleted: true
      ),
      using: client
    )

    try await transact(
      DeleteRemindersV3CompletedReminders(
        targets: [
          .init(reminderID: oldCompletedID, listID: listID)
        ]
      ),
      using: client
    )

    let all = FetchAll(RemindersV3Reminder.forList(listID, includeCompleted: true))
    try await all.load(using: client)
    expectNoDifference(all.wrappedValue.map(\.id), [openID])
  }

  @Test
  func listEditsAndAtomicReorderingMaterializeThroughTypedMessages() async throws {
    let persistenceURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("reminders-v3-reorder-\(UUID().uuidString).sqlite")
    defer { try? FileManager.default.removeItem(at: persistenceURL) }
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "reminders-v3-reorder-tests",
        persistenceURL: persistenceURL,
        initialAttributes: RemindersV3Schema.attributes
      )
    )
    let client = InstantSwiftDataClient(runtime: runtime)
    let ownerID = InstantID<RemindersV3User>(rawValue: "owner")
    let firstListID = InstantID<RemindersV3List>(rawValue: "first-list")
    let secondListID = InstantID<RemindersV3List>(rawValue: "second-list")
    let firstReminderID = InstantID<RemindersV3Reminder>(rawValue: "first-reminder")
    let secondReminderID = InstantID<RemindersV3Reminder>(rawValue: "second-reminder")
    let createdAt = Date(timeIntervalSince1970: 1_700_000_000)

    _ = try await runtime.transact(
      InstantStoreTransaction(
        id: "seed-owner",
        operations: [
          .insert(
            InstantTriple(
              entityID: ownerID.rawValue,
              attributeID: "$users/id",
              value: .string(ownerID.rawValue),
              txID: "seed-owner",
              txTime: InstantTimestamp(milliseconds: 1_700_000_000_000)
            )
          )
        ]
      ),
      createdAt: InstantTimestamp(milliseconds: 1_700_000_000_000)
    )

    for (position, listID) in [firstListID, secondListID].enumerated() {
      try await transact(
        CreateRemindersV3List(
          listID: listID,
          ownerID: ownerID,
          title: "List \(position)",
          position: position,
          createdAt: createdAt
        ),
        using: client
      )
    }
    for (position, reminderID) in [firstReminderID, secondReminderID].enumerated() {
      try await transact(
        CreateRemindersV3Reminder(
          reminderID: reminderID,
          listID: firstListID,
          title: "Reminder \(position)",
          position: position,
          createdAt: createdAt
        ),
        using: client
      )
    }

    try await transact(
      UpdateRemindersV3List(
        listID: firstListID,
        title: "Family",
        color: "#34c759",
        coverFileID: "cover-file-1"
      ),
      using: client
    )
    try await transact(
      ReorderRemindersV3Lists(
        positions: [
          .init(listID: firstListID, position: 1),
          .init(listID: secondListID, position: 0),
        ]
      ),
      using: client
    )
    try await transact(
      ReorderRemindersV3Reminders(
        listID: firstListID,
        positions: [
          .init(reminderID: firstReminderID, position: 1),
          .init(reminderID: secondReminderID, position: 0),
        ]
      ),
      using: client
    )

    let lists = FetchAll(RemindersV3List.visible(to: ownerID))
    try await lists.load(using: client)
    expectNoDifference(lists.wrappedValue.map(\.id), [secondListID, firstListID])
    let family = try #require(lists.wrappedValue.last)
    expectNoDifference(family.title, "Family")
    expectNoDifference(family.color, "#34c759")
    expectNoDifference(family.coverFileID, "cover-file-1")
    expectNoDifference(
      family.reminders.map(\.id),
      [secondReminderID, firstReminderID]
    )
  }

  #if os(macOS)
    @Test @MainActor
    func liveFetchInvalidatesAHostedSwiftUIList() async throws {
      let persistenceURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("reminders-v3-render-\(UUID().uuidString).sqlite")
      defer { try? FileManager.default.removeItem(at: persistenceURL) }
      let runtime = try await InstantRuntime.bootstrap(
        configuration: InstantRuntimeConfiguration(
          appID: "reminders-v3-render-tests",
          persistenceURL: persistenceURL,
          initialAttributes: RemindersV3Schema.attributes
        )
      )
      let client = InstantSwiftDataClient(runtime: runtime)
      let ownerID = InstantID<RemindersV3User>(rawValue: "render-owner")
      let listID = InstantID<RemindersV3List>(rawValue: "render-list")
      _ = try await runtime.transact(
        InstantStoreTransaction(
          id: "seed-render-owner",
          operations: [
            .insert(
              InstantTriple(
                entityID: ownerID.rawValue,
                attributeID: "$users/id",
                value: .string(ownerID.rawValue),
                txID: "seed-render-owner",
                txTime: InstantTimestamp(milliseconds: 1_700_000_000_000)
              )
            )
          ]
        ),
        createdAt: InstantTimestamp(milliseconds: 1_700_000_000_000)
      )
      let recorder = RemindersV3ListRenderRecorder()
      let hostingView = NSHostingView(
        rootView: RemindersV3ListRenderFixture(
          client: client,
          ownerID: ownerID,
          recorder: recorder
        )
      )
      hostingView.frame = NSRect(x: 0, y: 0, width: 320, height: 80)
      hostingView.layoutSubtreeIfNeeded()

      try await waitForRender(operation: "wait for initial list render") {
        !recorder.snapshots.isEmpty && recorder.didStartTask
      }
      try await transact(
        CreateRemindersV3List(
          listID: listID,
          ownerID: ownerID,
          title: "Rendered live",
          position: 0,
          createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        ),
        using: client
      )
      do {
        try await waitForRender(operation: "wait for live fetch view invalidation") {
          recorder.snapshots.last == ["Rendered live"]
        }
      } catch {
        Issue.record(
          "Hosted snapshots: \(recorder.snapshots); fetch error: \(recorder.error ?? "none")"
        )
        throw error
      }

      withExtendedLifetime(hostingView) {}
      #expect(recorder.error == nil)
      #expect(recorder.snapshots.count >= 2)
      expectNoDifference(recorder.snapshots.first, [])
      expectNoDifference(recorder.snapshots.last, ["Rendered live"])
    }

    @MainActor
    private func waitForRender(
      operation: String,
      condition: () -> Bool
    ) async throws {
      for _ in 0..<200 {
        if condition() { return }
        try await Task.sleep(for: .milliseconds(10))
      }
      Issue.record("Timed out while attempting to \(operation).")
      throw CancellationError()
    }
  #endif

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
      guard case .addTriple(_, let candidateAttributeID, let value, let options) = step,
        candidateAttributeID == attributeID,
        case .string(let rawValue) = value
      else { continue }
      return RequiredRef(value: rawValue, mode: options?.mode)
    }
    Issue.record("Missing required ref step for \(attributeID)")
    throw CancellationError()
  }
}

#if os(macOS)
  @MainActor
  private struct RemindersV3ListRenderFixture: View {
    @FetchAll private var lists: [RemindersV3List]

    let client: InstantSwiftDataClient
    let ownerID: InstantID<RemindersV3User>
    let recorder: RemindersV3ListRenderRecorder

    var body: some View {
      recorder.record(lists.map(\.title))
      return Text(lists.map(\.title).joined(separator: ","))
        .task {
          recorder.taskStarted()
          do {
            try await $lists.task(RemindersV3List.visible(to: ownerID), using: client)
          } catch is CancellationError {
          } catch {
            recorder.record(error: error)
          }
        }
    }
  }

  @MainActor
  private final class RemindersV3ListRenderRecorder {
    private(set) var snapshots: [[String]] = []
    private(set) var didStartTask = false
    private(set) var error: String?

    func record(_ titles: [String]) {
      snapshots.append(titles)
    }

    func taskStarted() {
      didStartTask = true
    }

    func record(error: Error) {
      self.error = String(describing: error)
    }
  }
#endif
