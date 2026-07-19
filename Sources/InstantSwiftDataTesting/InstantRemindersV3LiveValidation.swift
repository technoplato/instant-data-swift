import Dependencies
import Foundation
import InstantSwiftData
import RemindersV3App

@MainActor
private final class RemindersV3MessageOutcome {
  var accepted = false
  var failure: InstantError?
}

public struct InstantRemindersV3LiveReminderEvidence:
  Codable, Equatable, Sendable
{
  public var id: String
  public var title: String
  public var notes: String
  public var isCompleted: Bool
  public var isFlagged: Bool
  public var dueDateMilliseconds: Int64?
  public var priority: Int?
  public var position: Int
  public var tagIDs: [String]

  public init(
    id: String,
    title: String,
    notes: String,
    isCompleted: Bool,
    isFlagged: Bool,
    dueDateMilliseconds: Int64?,
    priority: Int?,
    position: Int,
    tagIDs: [String]
  ) {
    self.id = id
    self.title = title
    self.notes = notes
    self.isCompleted = isCompleted
    self.isFlagged = isFlagged
    self.dueDateMilliseconds = dueDateMilliseconds
    self.priority = priority
    self.position = position
    self.tagIDs = tagIDs
  }
}

public struct InstantRemindersV3LiveListEvidence:
  Codable, Equatable, Sendable
{
  public var id: String
  public var title: String
  public var color: String
  public var position: Int
  public var ownerID: String
  public var readerIDs: [String]
  public var writerIDs: [String]
  public var shareID: String?
  public var membershipRoles: [String]

  public init(
    id: String,
    title: String,
    color: String,
    position: Int,
    ownerID: String,
    readerIDs: [String],
    writerIDs: [String],
    shareID: String?,
    membershipRoles: [String]
  ) {
    self.id = id
    self.title = title
    self.color = color
    self.position = position
    self.ownerID = ownerID
    self.readerIDs = readerIDs
    self.writerIDs = writerIDs
    self.shareID = shareID
    self.membershipRoles = membershipRoles
  }
}

public struct InstantRemindersV3LiveValidationDetails:
  Codable, Equatable, Sendable
{
  public var list: InstantRemindersV3LiveListEvidence
  public var swiftReminder: InstantRemindersV3LiveReminderEvidence
  public var typeScriptReminderObservedBySwift: InstantRemindersV3LiveReminderEvidence
  public var connectionState: String
  public var pendingMutationCount: Int

  public init(
    list: InstantRemindersV3LiveListEvidence,
    swiftReminder: InstantRemindersV3LiveReminderEvidence,
    typeScriptReminderObservedBySwift: InstantRemindersV3LiveReminderEvidence,
    connectionState: String,
    pendingMutationCount: Int
  ) {
    self.list = list
    self.swiftReminder = swiftReminder
    self.typeScriptReminderObservedBySwift = typeScriptReminderObservedBySwift
    self.connectionState = connectionState
    self.pendingMutationCount = pendingMutationCount
  }
}

public enum InstantRemindersV3LiveValidation {
  public static let listID = "00000000-0000-4000-8000-000000000401"
  public static let swiftReminderID = "00000000-0000-4000-8000-000000000402"
  public static let shareID = "00000000-0000-4000-8000-000000000403"
  public static let ownerMembershipID = "00000000-0000-4000-8000-000000000404"
  public static let readerMembershipID = "00000000-0000-4000-8000-000000000405"
  public static let typeScriptReminderID = "00000000-0000-4000-8000-000000000406"
  public static let swiftTagID = "swift"
  public static let typeScriptTagID = "typescript"
  public static let listTitle = "Family"
  public static let listColor = "#4a99ef"
  public static let shareToken = "reminders-v3-share"
  public static let swiftReminderTitle = "Swift reminder"
  public static let swiftReminderUpdatedTitle = "Swift reminder updated by TypeScript"
  public static let typeScriptReminderTitle = "TypeScript reminder"
  public static let createdAtMilliseconds: Int64 = 1_784_424_000_000
  public static let dueAtMilliseconds: Int64 = 1_784_510_400_000

  public static func run(
    appID: String,
    apiURI: URL,
    websocketURI: URL,
    refreshToken: String,
    expectedOwnerUserID: String,
    expectedParticipantUserID: String,
    persistenceURL: URL? = nil,
    readerCheckSignalURL: URL? = nil,
    onSwiftGraphReady: @escaping @Sendable () -> Void = {},
    onReaderObserved: @escaping @Sendable () -> Void = {},
    onWriterReady: @escaping @Sendable () -> Void = {},
    onTypeScriptReminderObserved: @escaping @Sendable () -> Void = {}
  ) async throws -> ValidationEvidenceRow<InstantRemindersV3LiveValidationDetails> {
    let client = try await liveClient(
      appID: appID,
      apiURI: apiURI,
      websocketURI: websocketURI,
      persistenceURL: persistenceURL
    )
    try await authenticate(
      client,
      refreshToken: refreshToken,
      expectedUserID: expectedOwnerUserID
    )

    let ownerID = InstantID<RemindersV3User>(rawValue: expectedOwnerUserID)
    let participantID = InstantID<RemindersV3User>(rawValue: expectedParticipantUserID)
    let typedListID = InstantID<RemindersV3List>(rawValue: listID)
    let lists = FetchOne<RemindersV3List?>()
    let listTask = Task {
      try await lists.task(
        RemindersV3List.byID(typedListID, visibleTo: ownerID),
        using: client
      )
    }
    defer { listTask.cancel() }

    let createdAt = Date(timeIntervalSince1970: Double(createdAtMilliseconds) / 1_000)
    try await requireServerAcceptance(
      CreateRemindersV3List(
        listID: typedListID,
        ownerID: ownerID,
        title: listTitle,
        color: listColor,
        position: 0,
        createdAt: createdAt
      ),
      using: client,
      operation: "create Swift Reminders list"
    )
    try await requireServerAcceptance(
      CreateRemindersV3Reminder(
        reminderID: InstantID(rawValue: swiftReminderID),
        listID: typedListID,
        title: swiftReminderTitle,
        notes: "Created by InstantSwiftData",
        isFlagged: true,
        dueDate: Date(timeIntervalSince1970: Double(dueAtMilliseconds) / 1_000),
        priority: .high,
        position: 0,
        createdAt: createdAt,
        tagIDs: [InstantID(rawValue: swiftTagID)]
      ),
      using: client,
      operation: "create Swift Reminders reminder and tag"
    )
    try await requireServerAcceptance(
      CreateRemindersV3Share(
        shareID: InstantID(rawValue: shareID),
        ownerMembershipID: InstantID(rawValue: ownerMembershipID),
        listID: typedListID,
        ownerID: ownerID,
        token: shareToken,
        createdAt: createdAt
      ),
      using: client,
      operation: "create Swift Reminders share"
    )

    _ = try await waitForList(lists) { list in
      list.id.rawValue == listID
        && list.owner == ownerID
        && list.share?.id.rawValue == shareID
        && list.share?.memberships.contains {
          $0.id.rawValue == ownerMembershipID && $0.shareRole == .owner
        } == true
        && list.reminders.contains { reminder in
          reminder.id.rawValue == swiftReminderID
            && reminder.tags.map(\.id.rawValue).contains(swiftTagID)
        }
    }
    onSwiftGraphReady()

    _ = try await waitForList(lists) { list in
      list.share?.memberships.contains {
          $0.id.rawValue == readerMembershipID
            && $0.user == participantID
            && $0.shareRole == .reader
        } == true
    }
    try await requireServerAcceptance(
      AcceptRemindersV3Share(
        shareID: InstantID(rawValue: shareID),
        membershipID: InstantID(rawValue: readerMembershipID),
        listID: typedListID,
        userID: participantID,
        role: .reader,
        acceptedAt: createdAt.addingTimeInterval(1)
      ),
      using: client,
      operation: "accept TypeScript participant as Reminders reader"
    )
    _ = try await waitForList(lists) { list in
      list.readers.contains(participantID)
        && list.share?.memberships.contains {
          $0.id.rawValue == readerMembershipID
            && $0.user == participantID
            && $0.shareRole == .reader
        } == true
    }
    onReaderObserved()
    if let readerCheckSignalURL {
      try await withTimeout("wait for TypeScript reader-denial evidence") {
        while !FileManager.default.fileExists(atPath: readerCheckSignalURL.path) {
          try await Task.sleep(for: .milliseconds(25))
        }
      }
    }

    let promotedAt = createdAt.addingTimeInterval(2)
    try await requireServerAcceptance(
      ChangeRemindersV3ShareRole(
        shareID: InstantID(rawValue: shareID),
        membershipID: InstantID(rawValue: readerMembershipID),
        listID: typedListID,
        userID: participantID,
        previousRole: .reader,
        role: .writer,
        updatedAt: promotedAt
      ),
      using: client,
      operation: "promote Reminders reader to writer"
    )
    _ = try await waitForList(lists) { list in
      !list.readers.contains(participantID)
        && list.writers.contains(participantID)
        && list.share?.memberships.contains {
          $0.id.rawValue == readerMembershipID
            && $0.user == participantID
            && $0.shareRole == .writer
        } == true
    }
    onWriterReady()

    let completedList = try await waitForList(lists) { list in
      list.reminders.contains {
        $0.id.rawValue == swiftReminderID && $0.title == swiftReminderUpdatedTitle
      }
        && list.reminders.contains { reminder in
          reminder.id.rawValue == typeScriptReminderID
            && reminder.title == typeScriptReminderTitle
            && reminder.tags.map(\.id.rawValue).contains(typeScriptTagID)
        }
    }
    guard let swiftReminder = completedList.reminders.first(where: {
      $0.id.rawValue == swiftReminderID
    }), let typeScriptReminder = completedList.reminders.first(where: {
      $0.id.rawValue == typeScriptReminderID
    }) else {
      throw failure("The canonical Reminders graph did not include both SDK-owned reminders.")
    }
    onTypeScriptReminderObserved()

    let status = try await client.connectionStatus()
    let pendingMutationCount = await client.pendingMutations().count
    guard pendingMutationCount == 0 else {
      throw failure("The Reminders live runner still had pending mutations.")
    }
    _ = try await client.closeConnection()

    return ValidationEvidenceRow(
      caseID: "validation.live.reminders-v3",
      side: "swift",
      event: "typescript-writer-reminder-observed",
      appID: appID,
      entityID: listID,
      timestampMs: Int64((Date().timeIntervalSince1970 * 1_000).rounded()),
      ok: true,
      details: InstantRemindersV3LiveValidationDetails(
        list: listEvidence(completedList),
        swiftReminder: reminderEvidence(swiftReminder),
        typeScriptReminderObservedBySwift: reminderEvidence(typeScriptReminder),
        connectionState: status.state.rawValue,
        pendingMutationCount: pendingMutationCount
      )
    )
  }

  private static func liveClient(
    appID: String,
    apiURI: URL,
    websocketURI: URL,
    persistenceURL: URL?
  ) async throws -> InstantSwiftDataClient {
    try await withDependencies {
      $0.context = .live
      $0.instantLiveTransport = .live
      try await $0.bootstrapInstantSwiftData(
        appID: appID,
        apiURI: apiURI,
        websocketURI: websocketURI,
        persistenceURL: persistenceURL
          ?? FileManager.default.temporaryDirectory
          .appendingPathComponent("instant-reminders-v3-live-\(UUID().uuidString).sqlite"),
        context: .live,
        initialAttributes: RemindersV3Schema.attributes
      )
    } operation: {
      @Dependency(\.defaultInstantSwiftData) var client
      return client
    }
  }

  private static func authenticate(
    _ client: InstantSwiftDataClient,
    refreshToken: String,
    expectedUserID: String
  ) async throws {
    let session = try await client.signInWithRefreshToken(
      refreshToken,
      userID: "untrusted-swift-reminders-user"
    )
    guard session.userID == expectedUserID else {
      throw failure("Server-verified Swift Reminders user did not match the expected owner.")
    }
    _ = try await client.connect()
    try await withTimeout("authenticate Swift Reminders client") {
      while try await client.connectionStatus().state != .authenticated {
        try await Task.sleep(for: .milliseconds(25))
      }
    }
  }

  private static func requireServerAcceptance<Message: InstantMessage>(
    _ message: Message,
    using client: InstantSwiftDataClient,
    operation: String
  ) async throws {
    let outcome = await MainActor.run { RemindersV3MessageOutcome() }
    let task = client.send(
      message,
      onServerAccepted: { _ in outcome.accepted = true },
      onFailure: { outcome.failure = $0 }
    )
    defer { task.cancel() }
    let deadline = ContinuousClock.now + .seconds(30)
    let explicitFlushAt = ContinuousClock.now + .seconds(5)
    var didExplicitlyFlush = false
    while ContinuousClock.now < deadline {
      let result = await MainActor.run { (outcome.accepted, outcome.failure) }
      if let error = result.1 { throw error }
      if result.0 { return }
      if !didExplicitlyFlush, ContinuousClock.now >= explicitFlushAt {
        didExplicitlyFlush = true
        let flush = try await client.flushPendingMutations()
        if let failed = flush.results.first(where: { $0.outcome == .failed }) {
          throw failure(
            "Server rejected \(operation): \(failed.message ?? "unknown failure")."
          )
        }
        if !flush.confirmed.isEmpty || flush.pendingMutationCount == 0 { return }
      }
      try await Task.sleep(for: .milliseconds(25))
    }
    throw failure("Timed out waiting for server acceptance: \(operation).")
  }

  private static func waitForList(
    _ rows: FetchOne<RemindersV3List?>,
    matching predicate: @escaping @Sendable (RemindersV3List) -> Bool
  ) async throws -> RemindersV3List {
    try await withTimeout("observe canonical Reminders list") {
      while true {
        if let list = rows.wrappedValue, predicate(list) { return list }
        try await Task.sleep(for: .milliseconds(25))
      }
    }
  }

  private static func listEvidence(
    _ list: RemindersV3List
  ) -> InstantRemindersV3LiveListEvidence {
    InstantRemindersV3LiveListEvidence(
      id: list.id.rawValue,
      title: list.title,
      color: list.color,
      position: list.position,
      ownerID: list.owner.rawValue,
      readerIDs: list.readers.map(\.rawValue).sorted(),
      writerIDs: list.writers.map(\.rawValue).sorted(),
      shareID: list.share?.id.rawValue,
      membershipRoles: list.share?.memberships.map(\.role).sorted() ?? []
    )
  }

  private static func reminderEvidence(
    _ reminder: RemindersV3Reminder
  ) -> InstantRemindersV3LiveReminderEvidence {
    InstantRemindersV3LiveReminderEvidence(
      id: reminder.id.rawValue,
      title: reminder.title,
      notes: reminder.notes,
      isCompleted: reminder.isCompleted,
      isFlagged: reminder.isFlagged,
      dueDateMilliseconds: reminder.dueDate.map {
        Int64(($0.timeIntervalSince1970 * 1_000).rounded())
      },
      priority: reminder.priority?.rawValue,
      position: reminder.position,
      tagIDs: reminder.tags.map(\.id.rawValue).sorted()
    )
  }

  private static func withTimeout<Value: Sendable>(
    _ operation: String,
    _ body: @escaping @Sendable () async throws -> Value
  ) async throws -> Value {
    try await withThrowingTaskGroup(of: Value.self) { group in
      group.addTask { try await body() }
      group.addTask {
        try await Task.sleep(for: .seconds(30))
        throw failure("Timed out: \(operation).")
      }
      guard let value = try await group.next() else {
        throw failure("No result produced: \(operation).")
      }
      group.cancelAll()
      return value
    }
  }

  private static func failure(_ message: String) -> InstantError {
    InstantError(
      code: .implementationFailed,
      operation: "validate Reminders V3 live contract",
      message: message,
      recovery: "Inspect the canonical list, reminder, tag, share, membership, schema, and permission lifecycle."
    )
  }
}
