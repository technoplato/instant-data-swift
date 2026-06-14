import Foundation

public struct RemindersValidationDetails: Codable, Equatable, Sendable {
  public var cachePath: String
  public var listIDs: [String]
  public var listTitles: [String]
  public var reminderIDs: [String]
  public var reminderTitles: [String]
  public var reminderNotes: [String]
  public var completedReminderIDs: [String]
  public var flaggedReminderIDs: [String]
  public var scheduledReminderIDs: [String]
  public var todayReminderIDs: [String]
  public var priorityReminderIDs: [String]
  public var tagIDs: [String]
  public var tagTitles: [String]
  public var reminderTagIDs: [String]
  public var stats: RemindersStats
  public var activeShareIDs: [String]
  public var shareRoleSummaries: [String]
  public var rejectedOperations: [String]
  public var pendingMutationIDs: [String]
  public var queryCacheCount: Int

  public init(
    cachePath: String,
    listIDs: [String] = [],
    listTitles: [String] = [],
    reminderIDs: [String] = [],
    reminderTitles: [String] = [],
    reminderNotes: [String] = [],
    completedReminderIDs: [String] = [],
    flaggedReminderIDs: [String] = [],
    scheduledReminderIDs: [String] = [],
    todayReminderIDs: [String] = [],
    priorityReminderIDs: [String] = [],
    tagIDs: [String] = [],
    tagTitles: [String] = [],
    reminderTagIDs: [String] = [],
    stats: RemindersStats = RemindersStats(),
    activeShareIDs: [String] = [],
    shareRoleSummaries: [String] = [],
    rejectedOperations: [String] = [],
    pendingMutationIDs: [String] = [],
    queryCacheCount: Int = 0
  ) {
    self.cachePath = cachePath
    self.listIDs = listIDs
    self.listTitles = listTitles
    self.reminderIDs = reminderIDs
    self.reminderTitles = reminderTitles
    self.reminderNotes = reminderNotes
    self.completedReminderIDs = completedReminderIDs
    self.flaggedReminderIDs = flaggedReminderIDs
    self.scheduledReminderIDs = scheduledReminderIDs
    self.todayReminderIDs = todayReminderIDs
    self.priorityReminderIDs = priorityReminderIDs
    self.tagIDs = tagIDs
    self.tagTitles = tagTitles
    self.reminderTagIDs = reminderTagIDs
    self.stats = stats
    self.activeShareIDs = activeShareIDs
    self.shareRoleSummaries = shareRoleSummaries
    self.rejectedOperations = rejectedOperations
    self.pendingMutationIDs = pendingMutationIDs
    self.queryCacheCount = queryCacheCount
  }
}

public struct RemindersValidationResult: Sendable {
  public var appID: String
  public var cacheURL: URL
  public var evidence: [ValidationEvidenceRow<RemindersValidationDetails>]

  public init(
    appID: String,
    cacheURL: URL,
    evidence: [ValidationEvidenceRow<RemindersValidationDetails>]
  ) {
    self.appID = appID
    self.cacheURL = cacheURL
    self.evidence = evidence
  }
}

public enum InstantSwiftDataRemindersValidation {
  public static func run(
    appID: String = "local-validation",
    cacheURL: URL? = nil,
    timestamp: @escaping @Sendable () -> InstantTimestamp = {
      InstantTimestamp(milliseconds: Int64((Date().timeIntervalSince1970 * 1000).rounded()))
    },
    makeID: @escaping @Sendable () -> String = { UUID().uuidString.lowercased() }
  ) async throws -> RemindersValidationResult {
    let cacheURL =
      cacheURL
      ?? FileManager.default.temporaryDirectory
        .appendingPathComponent("InstantSwiftDataRemindersValidation-\(makeID())", isDirectory: true)
        .appendingPathComponent("state.sqlite")
    let today = timestamp()
    let listID = "validation-reminders-list"
    let firstReminderID = "validation-reminders-pack-lunch"
    let secondReminderID = "validation-reminders-read-book"
    let tagID = "family"
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: appID,
        persistenceURL: cacheURL,
        initialAttributes: ReminderExample.attributes,
        now: { today },
        makeID: makeID
      )
    )
    _ = try await runtime.signInWithRefreshToken("owner-refresh", userID: "user-1")

    var evidence: [ValidationEvidenceRow<RemindersValidationDetails>] = []

    try await transact(
      runtime,
      id: "validation.reminders.create-list",
      createdAt: today,
      operations: ReminderExample.createListOperations(
        id: listID,
        title: "Family",
        position: 0,
        createdAt: today,
        transactionID: "validation.reminders.create-list"
      )
    )
    try await transact(
      runtime,
      id: "validation.reminders.create-reminders",
      createdAt: today,
      operations: ReminderExample.createReminderOperations(
        id: firstReminderID,
        listID: listID,
        title: "Pack lunch",
        notes: "Bring a cooler",
        isFlagged: true,
        dueDate: today,
        priority: .high,
        position: 0,
        createdAt: today,
        transactionID: "validation.reminders.create-reminders"
      ) + ReminderExample.createReminderOperations(
        id: secondReminderID,
        listID: listID,
        title: "Read book",
        position: 1,
        createdAt: today,
        transactionID: "validation.reminders.create-reminders"
      )
    )
    try await transact(
      runtime,
      id: "validation.reminders.add-tag",
      createdAt: today,
      operations: ReminderExample.addTagOperations(
        reminderID: firstReminderID,
        listID: listID,
        tagID: tagID,
        title: tagID,
        updatedAt: today,
        transactionID: "validation.reminders.add-tag"
      )
    )
    evidence.append(
      try await evidenceRow(event: "seed", runtime: runtime, cacheURL: cacheURL, today: today)
    )

    let searched = try await reminders(
      runtime,
      query: ReminderExample.remindersSearchQuery(text: "Pack", tagID: tagID)
    )
    try require(
      searched.map(\.id) == [firstReminderID],
      operation: "validate reminders search",
      message: "Expected tag-filtered search to return the packed lunch reminder."
    )
    evidence.append(
      try await evidenceRow(
        event: "search-tags",
        runtime: runtime,
        cacheURL: cacheURL,
        today: today,
        eventReminders: searched
      )
    )

    let scheduled = try await reminders(
      runtime,
      query: ReminderExample.remindersFilterQuery(scheduled: true)
    )
    let dueToday = try await reminders(
      runtime,
      query: ReminderExample.remindersFilterQuery(today: today)
    )
    let highPriority = try await reminders(
      runtime,
      query: ReminderExample.remindersFilterQuery(priority: .high)
    )
    try require(
      scheduled.map(\.id) == [firstReminderID]
        && dueToday.map(\.id) == [firstReminderID]
        && highPriority.map(\.id) == [firstReminderID],
      operation: "validate reminders rich filters",
      message: "Expected scheduled, today, and high-priority filters to identify the same reminder."
    )
    evidence.append(
      try await evidenceRow(
        event: "rich-filters",
        runtime: runtime,
        cacheURL: cacheURL,
        today: today,
        eventReminders: scheduled,
        scheduledReminderIDs: scheduled.map(\.id),
        todayReminderIDs: dueToday.map(\.id),
        priorityReminderIDs: highPriority.map(\.id)
      )
    )

    try await transact(
      runtime,
      id: "validation.reminders.edit-rich-fields",
      createdAt: today,
      operations: ReminderExample.updateReminderDetailsOperations(
        id: firstReminderID,
        listID: listID,
        title: "Pack lunch and snacks",
        notes: "Updated through validation",
        isFlagged: false,
        dueDate: nil,
        priority: nil,
        updatedAt: today,
        transactionID: "validation.reminders.edit-rich-fields"
      )
    )
    let edited = try await reminders(
      runtime,
      query: ReminderExample.remindersSearchQuery(text: "snacks", includeCompleted: true)
    )
    try require(
      edited.map(\.id) == [firstReminderID]
        && edited.first?.dueDate == nil
        && edited.first?.priority == nil
        && edited.first?.isFlagged == false,
      operation: "validate reminders edit",
      message: "Expected rich reminder edit to clear date, priority, and flagged state."
    )
    evidence.append(
      try await evidenceRow(
        event: "edit-rich-fields",
        runtime: runtime,
        cacheURL: cacheURL,
        today: today,
        eventReminders: edited
      )
    )

    try await transact(
      runtime,
      id: "validation.reminders.complete-second",
      createdAt: today,
      operations: ReminderExample.completeReminderOperations(
        id: secondReminderID,
        listID: listID,
        updatedAt: today,
        transactionID: "validation.reminders.complete-second"
      )
    )
    evidence.append(
      try await evidenceRow(event: "complete", runtime: runtime, cacheURL: cacheURL, today: today)
    )

    let createdShare = try await runtime.createShare(
      rootNamespace: ReminderExample.listsNamespace,
      rootID: listID
    )
    _ = try await runtime.signInWithRefreshToken("invitee-refresh", userID: "user-2")
    let acceptedShare = try await runtime.acceptShare(token: createdShare.share.token)
    let readerRejection = try await expectPermissionRejection("reader-update") {
      try await runtime.transact(
        InstantStoreTransaction(
          id: "validation.reminders.reader-update",
          operations: ReminderExample.updateReminderTitleOperations(
            id: firstReminderID,
            listID: listID,
            title: "Reader edit",
            updatedAt: today,
            transactionID: "validation.reminders.reader-update"
          )
        ),
        createdAt: today,
        source: "validation.reminders.reader-update"
      )
    }
    evidence.append(
      try await evidenceRow(
        event: "reader-rejection",
        runtime: runtime,
        cacheURL: cacheURL,
        today: today,
        shareSnapshots: [acceptedShare],
        rejectedOperations: [readerRejection]
      )
    )

    _ = try await runtime.signInWithRefreshToken("owner-refresh", userID: "user-1")
    let promotedShare = try await runtime.updateShareMembershipRole(
      shareID: createdShare.share.id,
      userID: "user-2",
      role: .writer
    )
    _ = try await runtime.signInWithRefreshToken("invitee-refresh", userID: "user-2")
    try await transact(
      runtime,
      id: "validation.reminders.writer-update",
      createdAt: today,
      operations: ReminderExample.updateReminderTitleOperations(
        id: firstReminderID,
        listID: listID,
        title: "Writer edit",
        updatedAt: today,
        transactionID: "validation.reminders.writer-update"
      )
    )
    let writerEdited = try await reminders(
      runtime,
      query: ReminderExample.remindersSearchQuery(text: "Writer", includeCompleted: true)
    )
    try require(
      writerEdited.map(\.id) == [firstReminderID],
      operation: "validate reminders writer update",
      message: "Expected promoted writer to edit the shared reminder."
    )
    evidence.append(
      try await evidenceRow(
        event: "writer-update",
        runtime: runtime,
        cacheURL: cacheURL,
        today: today,
        eventReminders: writerEdited,
        shareSnapshots: [promotedShare]
      )
    )

    _ = try await runtime.signInWithRefreshToken("owner-refresh", userID: "user-1")
    let demotedShare = try await runtime.updateShareMembershipRole(
      shareID: createdShare.share.id,
      userID: "user-2",
      role: .reader
    )
    _ = try await runtime.signInWithRefreshToken("invitee-refresh", userID: "user-2")
    let demotedRejection = try await expectPermissionRejection("demoted-reader-add-tag") {
      try await runtime.transact(
        InstantStoreTransaction(
          id: "validation.reminders.demoted-reader-add-tag",
          operations: ReminderExample.addTagOperations(
            reminderID: firstReminderID,
            listID: listID,
            tagID: "reader",
            title: "reader",
            updatedAt: today,
            transactionID: "validation.reminders.demoted-reader-add-tag"
          )
        ),
        createdAt: today,
        source: "validation.reminders.demoted-reader-add-tag"
      )
    }
    evidence.append(
      try await evidenceRow(
        event: "demoted-reader-rejection",
        runtime: runtime,
        cacheURL: cacheURL,
        today: today,
        shareSnapshots: [demotedShare],
        rejectedOperations: [demotedRejection]
      )
    )

    let relaunchedRuntime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: appID,
        persistenceURL: cacheURL,
        initialAttributes: ReminderExample.attributes,
        now: { today },
        makeID: makeID
      )
    )
    let relaunchedReminders = try await reminders(
      relaunchedRuntime,
      query: ReminderExample.remindersSearchQuery(text: "Writer", includeCompleted: true)
    )
    try require(
      relaunchedReminders.map(\.id) == [firstReminderID],
      operation: "validate reminders relaunch",
      message: "Expected writer edit to persist across runtime relaunch."
    )
    evidence.append(
      try await evidenceRow(
        event: "relaunch",
        runtime: relaunchedRuntime,
        cacheURL: cacheURL,
        today: today,
        eventReminders: relaunchedReminders,
        shareSnapshots: [demotedShare]
      )
    )

    return RemindersValidationResult(appID: appID, cacheURL: cacheURL, evidence: evidence)
  }

  private static func transact(
    _ runtime: InstantRuntime,
    id: String,
    createdAt: InstantTimestamp,
    operations: [InstantTripleOperation]
  ) async throws {
    try await runtime.transact(
      InstantStoreTransaction(id: id, operations: operations),
      createdAt: createdAt,
      source: "validation.reminders"
    )
  }

  private static func evidenceRow(
    event: String,
    runtime: InstantRuntime,
    cacheURL: URL,
    today: InstantTimestamp,
    eventReminders: [ReminderRecord]? = nil,
    scheduledReminderIDs: [String]? = nil,
    todayReminderIDs: [String]? = nil,
    priorityReminderIDs: [String]? = nil,
    shareSnapshots: [InstantShareSnapshot] = [],
    rejectedOperations: [String] = []
  ) async throws -> ValidationEvidenceRow<RemindersValidationDetails> {
    let lists = try ReminderExample.decodeLists(
      (try await runtime.queryOnce(ReminderExample.listsQuery)).values
    )
    let allReminders = try await reminders(runtime, query: ReminderExample.remindersQuery)
    let tags = try ReminderExample.decodeTags(
      (try await runtime.queryOnce(ReminderExample.tagsQuery)).values
    )
    let reminderTags = try ReminderExample.decodeReminderTagLinks(
      (try await runtime.queryOnce(ReminderExample.remindersQuery)).values
    )
    let visibleReminders = eventReminders ?? allReminders
    let cachedQueries = try await runtime.cachedQueries()
    let pending = await runtime.pendingMutations()
    let activeShares = try await runtime.shares()
    return ValidationEvidenceRow(
      caseID: "validation.reminders",
      side: "swift",
      event: event,
      appID: runtime.configuration.appID,
      timestampMs: today.milliseconds,
      ok: true,
      details: RemindersValidationDetails(
        cachePath: cacheURL.path,
        listIDs: lists.map(\.id),
        listTitles: lists.map(\.title),
        reminderIDs: visibleReminders.map(\.id),
        reminderTitles: visibleReminders.map(\.title),
        reminderNotes: visibleReminders.map(\.notes),
        completedReminderIDs: allReminders.filter(\.isCompleted).map(\.id),
        flaggedReminderIDs: allReminders.filter(\.isFlagged).map(\.id),
        scheduledReminderIDs: scheduledReminderIDs ?? allReminders.filter { $0.dueDate != nil }.map(\.id),
        todayReminderIDs: todayReminderIDs ?? reminderIDsDueToday(in: allReminders, today: today),
        priorityReminderIDs: priorityReminderIDs ?? allReminders.filter { $0.priority != nil }.map(\.id),
        tagIDs: tags.map(\.id),
        tagTitles: tags.map(\.title),
        reminderTagIDs: reminderTags.map(\.id),
        stats: ReminderExample.stats(for: allReminders, today: today),
        activeShareIDs: activeShares.map(\.id),
        shareRoleSummaries: shareRoleSummaries(from: shareSnapshots.isEmpty ? activeShares : shareSnapshots),
        rejectedOperations: rejectedOperations,
        pendingMutationIDs: pending.map(\.id),
        queryCacheCount: cachedQueries.count
      )
    )
  }

  private static func reminders(
    _ runtime: InstantRuntime,
    query: InstantQueryPlan
  ) async throws -> [ReminderRecord] {
    try ReminderExample.decodeReminders((try await runtime.queryOnce(query)).values)
  }

  private static func reminderIDsDueToday(
    in reminders: [ReminderRecord],
    today: InstantTimestamp
  ) -> [String] {
    ReminderExample.stats(for: reminders, today: today).todayCount == 0
      ? []
      : reminders.filter { reminder in
        guard let dueDate = reminder.dueDate else { return false }
        let day = 24 * 60 * 60 * 1000
        let start = today.milliseconds - (today.milliseconds % Int64(day))
        return dueDate.milliseconds >= start && dueDate.milliseconds < start + Int64(day)
      }
      .map(\.id)
  }

  private static func shareRoleSummaries(
    from snapshots: [InstantShareSnapshot]
  ) -> [String] {
    snapshots
      .flatMap { snapshot in
        snapshot.memberships.map { membership in
          "\(snapshot.share.rootNamespace):\(snapshot.share.rootID):\(membership.userID):\(membership.role.rawValue)"
        }
      }
      .sorted()
  }

  private static func expectPermissionRejection(
    _ operation: String,
    work: () async throws -> Void
  ) async throws -> String {
    do {
      try await work()
    } catch let error as InstantError where error.code == .permissionRejected {
      return [
        operation,
        error.code.rawValue,
        error.namespace,
        error.localID,
      ]
      .compactMap { $0 }
      .joined(separator: ":")
    }
    throw validationError(
      operation: "validate reminders permission rejection",
      message: "Expected \(operation) to fail with a permission rejection."
    )
  }

  private static func require(
    _ condition: Bool,
    operation: String,
    message: String
  ) throws {
    guard condition else {
      throw validationError(operation: operation, message: message)
    }
  }

  private static func validationError(
    operation: String,
    message: String
  ) -> InstantError {
    InstantError(
      code: .validationFailed,
      operation: operation,
      message: message,
      recovery: "Inspect local Reminders validation operations, query filters, and share-role guards."
    )
  }
}
