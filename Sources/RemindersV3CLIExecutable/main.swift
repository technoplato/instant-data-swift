import Foundation
import InstantSwiftData
import RemindersV3App

@main
struct RemindersV3CLI {
  static func main() async {
    do {
      try await run()
    } catch let error as CLIError {
      writeError(error.description)
      exit(error.exitCode)
    } catch let error as InstantError {
      writeError(error.description)
      exit(65)
    } catch {
      writeError("reminders-v3-cli: \(error)")
      exit(70)
    }
  }

  private static func run() async throws {
    var input = Array(CommandLine.arguments.dropFirst())
    let output = OutputMode.consume(from: &input)
    guard let group = input.first else {
      printUsage()
      return
    }
    input.removeFirst()

    switch group {
    case "help", "--help", "-h":
      printUsage()

    case "auth":
      try await runAuth(input, output: output)

    case "lists", "list":
      try await runLists(input, output: output)

    case "tags", "tag":
      try await runTags(input, output: output)

    case "reminders", "reminder":
      try await runReminders(input, output: output)

    case "share", "shares":
      try await runShares(input, output: output)

    case "sync":
      try await runSync(input, output: output)

    default:
      throw CLIError(
        "Unknown command group '\(group)'. Run 'reminders-v3-cli help'.",
        exitCode: 64
      )
    }
  }

  private static func runAuth(_ arguments: [String], output: OutputMode) async throws {
    guard let command = arguments.first else {
      throw CLIError(AuthUsage.text, exitCode: 64)
    }
    let context = try await CLIContext.bootstrap(connectIfAuthenticated: false)
    switch command {
    case "show":
      try output.write(AuthOutput(context: context, session: try await context.client.authSession()))

    case "guest":
      let session = try await context.client.signInAsGuest()
      _ = try? await context.connectIfLive()
      try output.write(AuthOutput(context: context, session: session))

    case "token":
      guard arguments.count >= 2 else {
        throw CLIError("Missing refresh token.\n\(AuthUsage.text)", exitCode: 64)
      }
      let session = try await context.client.signInWithRefreshToken(arguments[1])
      _ = try? await context.connectIfLive()
      try output.write(AuthOutput(context: context, session: session))

    case "sign-out", "logout":
      try await context.client.signOut()
      try output.write(SimpleOutput(event: "auth.sign-out", ok: true, message: "Signed out."))

    default:
      throw CLIError("Unknown auth command '\(command)'.\n\(AuthUsage.text)", exitCode: 64)
    }
  }

  private static func runLists(_ arguments: [String], output: OutputMode) async throws {
    guard let command = arguments.first else {
      throw CLIError(ListsUsage.text, exitCode: 64)
    }
    let context = try await CLIContext.bootstrap()
    switch command {
    case "list", "ls":
      let options = try ListOptions(Array(arguments.dropFirst()))
      let lists = try await loadVisibleLists(context: context)
      try output.write(ListsOutput(event: "lists.list", lists: lists, status: try await context.status()))
      if options.watch {
        try await watchLists(context: context, output: output)
      }

    case "add":
      let options = try AddListOptions(Array(arguments.dropFirst()))
      let userID = try await context.requireUserID()
      let lists = try await loadVisibleLists(context: context)
      let listID = InstantID<RemindersV3List>(rawValue: context.makeID())
      let coverFileID = try await resolveCoverFileID(
        context: context,
        explicitID: options.coverFileID,
        fileURL: options.coverFileURL
      )
      try await context.send(
        CreateRemindersV3List(
          listID: listID,
          ownerID: userID,
          title: options.title,
          color: options.color,
          coverFileID: coverFileID,
          position: lists.count,
          createdAt: context.now()
        )
      )
      try output.write(
        ChangeOutput(
          event: "lists.add",
          changedID: listID.rawValue,
          status: try await context.status()
        )
      )

    case "rename":
      guard arguments.count >= 3 else {
        throw CLIError("Usage: reminders-v3-cli lists rename <list-id> \"new title\"", exitCode: 64)
      }
      let listID = InstantID<RemindersV3List>(rawValue: arguments[1])
      try await context.send(RenameRemindersV3List(listID: listID, title: joinedTitle(arguments, from: 2)))
      try output.write(ChangeOutput(event: "lists.rename", changedID: listID.rawValue, status: try await context.status()))

    case "update", "edit":
      let options = try UpdateListOptions(Array(arguments.dropFirst()))
      let list = try await requireList(context: context, id: options.listID)
      let coverFileID: String?
      if options.clearsCover {
        coverFileID = nil
      } else if options.coverFileID != nil || options.coverFileURL != nil {
        coverFileID = try await resolveCoverFileID(
          context: context,
          explicitID: options.coverFileID,
          fileURL: options.coverFileURL
        )
      } else {
        coverFileID = list.coverFileID
      }
      try await context.send(
        UpdateRemindersV3List(
          listID: list.id,
          title: options.title ?? list.title,
          color: options.color ?? list.color,
          coverFileID: coverFileID
        )
      )
      try output.write(ChangeOutput(event: "lists.update", changedID: list.id.rawValue, status: try await context.status()))

    case "delete", "rm":
      guard arguments.count == 2 else {
        throw CLIError("Usage: reminders-v3-cli lists delete <list-id>", exitCode: 64)
      }
      let listID = InstantID<RemindersV3List>(rawValue: arguments[1])
      try await context.send(DeleteRemindersV3List(listID: listID))
      try output.write(ChangeOutput(event: "lists.delete", changedID: listID.rawValue, status: try await context.status()))

    default:
      throw CLIError("Unknown lists command '\(command)'.\n\(ListsUsage.text)", exitCode: 64)
    }
  }

  private static func runReminders(_ arguments: [String], output: OutputMode) async throws {
    guard let command = arguments.first else {
      throw CLIError(RemindersUsage.text, exitCode: 64)
    }
    let context = try await CLIContext.bootstrap()
    switch command {
    case "list", "ls":
      let options = try ReminderListOptions(Array(arguments.dropFirst()))
      let reminders = try await loadReminders(context: context, options: options)
      try output.write(RemindersOutput(event: "reminders.list", reminders: reminders, status: try await context.status()))
      if options.watch {
        try await watchReminders(context: context, output: output, options: options)
      }

    case "add":
      let options = try AddReminderOptions(Array(arguments.dropFirst()))
      let current = try await remindersForList(context: context, listID: options.listID)
      let resolvedTags = try await resolveTags(
        context: context,
        titles: options.tagIDs.compactMap { options.tagTitles[$0] }
      )
      let reminderID = InstantID<RemindersV3Reminder>(rawValue: context.makeID())
      try await context.send(
        CreateRemindersV3Reminder(
          reminderID: reminderID,
          listID: options.listID,
          title: options.title,
          notes: options.notes,
          isFlagged: options.isFlagged,
          dueDate: options.dueDate,
          priority: options.priority,
          position: current.count,
          createdAt: context.now(),
          tagIDs: resolvedTags.map(\.id),
          tagTitles: Dictionary(uniqueKeysWithValues: resolvedTags.map { ($0.id, $0.title) })
        )
      )
      try output.write(ChangeOutput(event: "reminders.add", changedID: reminderID.rawValue, status: try await context.status()))

    case "update":
      let options = try UpdateReminderOptions(Array(arguments.dropFirst()))
      let reminder = try await requireReminder(context: context, id: options.reminderID)
      let resolvedTags: [(id: InstantID<RemindersV3Tag>, title: String)]?
      if let tagIDs = options.replacingTags {
        resolvedTags = try await resolveTags(
          context: context,
          titles: tagIDs.compactMap { options.tagTitles[$0] }
        )
      } else {
        resolvedTags = nil
      }
      let nextTagIDs = resolvedTags?.map { $0.id } ?? reminder.tags.map(\.id)
      let nextTagTitles: [InstantID<RemindersV3Tag>: String] = resolvedTags.map { tags in
        Dictionary(uniqueKeysWithValues: tags.map { ($0.id, $0.title) })
      } ?? Dictionary(uniqueKeysWithValues: reminder.tags.map { ($0.id, $0.title) })
      try await context.send(
        UpdateRemindersV3Reminder(
          reminderID: reminder.id,
          listID: reminder.list,
          title: options.title ?? reminder.title,
          notes: options.notes ?? reminder.notes,
          isFlagged: options.isFlagged ?? reminder.isFlagged,
          dueDate: options.clearsDueDate ? nil : (options.dueDate ?? reminder.dueDate),
          priority: options.clearsPriority ? nil : (options.priority ?? reminder.priority),
          existingTagIDs: reminder.tags.map(\.id),
          tagIDs: nextTagIDs,
          tagTitles: nextTagTitles
        )
      )
      try output.write(ChangeOutput(event: "reminders.update", changedID: reminder.id.rawValue, status: try await context.status()))

    case "complete", "done":
      guard arguments.count == 2 else {
        throw CLIError("Usage: reminders-v3-cli reminders complete <reminder-id>", exitCode: 64)
      }
      let reminder = try await requireReminder(context: context, id: InstantID(rawValue: arguments[1]))
      try await context.send(SetRemindersV3Completion(reminderID: reminder.id, listID: reminder.list, isCompleted: true))
      try output.write(ChangeOutput(event: "reminders.complete", changedID: reminder.id.rawValue, status: try await context.status()))

    case "reopen", "undone":
      guard arguments.count == 2 else {
        throw CLIError("Usage: reminders-v3-cli reminders reopen <reminder-id>", exitCode: 64)
      }
      let reminder = try await requireReminder(context: context, id: InstantID(rawValue: arguments[1]))
      try await context.send(SetRemindersV3Completion(reminderID: reminder.id, listID: reminder.list, isCompleted: false))
      try output.write(ChangeOutput(event: "reminders.reopen", changedID: reminder.id.rawValue, status: try await context.status()))

    case "delete", "rm":
      guard arguments.count == 2 else {
        throw CLIError("Usage: reminders-v3-cli reminders delete <reminder-id>", exitCode: 64)
      }
      let reminder = try await requireReminder(context: context, id: InstantID(rawValue: arguments[1]))
      try await context.send(DeleteRemindersV3Reminder(reminderID: reminder.id, listID: reminder.list))
      try output.write(ChangeOutput(event: "reminders.delete", changedID: reminder.id.rawValue, status: try await context.status()))

    case "delete-completed", "clear-completed", "cleanup-completed":
      let options = try CompletedCleanupOptions(Array(arguments.dropFirst()))
      let lists = try await loadVisibleLists(context: context)
      let selectedLists = try selectLists(lists, listID: options.listID)
      let targets = selectedLists.flatMap { list in
        list.reminders
          .filter { options.scope.includes($0, now: context.now()) }
          .map { reminder in
            DeleteRemindersV3CompletedReminders.Target(
              reminderID: reminder.id,
              listID: list.id
            )
          }
      }
      try await context.send(DeleteRemindersV3CompletedReminders(targets: targets))
      try output.write(
        DeleteCompletedOutput(
          event: "reminders.delete-completed",
          deletedIDs: targets.map(\.reminderID.rawValue),
          scope: options.scope.description,
          status: try await context.status()
        )
      )

    case "tag":
      try await runReminderTags(Array(arguments.dropFirst()), context: context, output: output)

    default:
      throw CLIError("Unknown reminders command '\(command)'.\n\(RemindersUsage.text)", exitCode: 64)
    }
  }

  private static func runTags(_ arguments: [String], output: OutputMode) async throws {
    guard let command = arguments.first else {
      throw CLIError(TagsUsage.text, exitCode: 64)
    }
    let context = try await CLIContext.bootstrap()
    switch command {
    case "list", "ls":
      let tags = usedTags(in: try await loadVisibleLists(context: context))
      try output.write(TagsOutput(event: "tags.list", tags: tags, status: try await context.status()))

    case "delete", "rm":
      guard arguments.count == 2 else {
        throw CLIError("Usage: reminders-v3-cli tags delete <tag-id-or-title>", exitCode: 64)
      }
      let userID = try await context.requireUserID()
      let lists = try await loadVisibleLists(context: context)
      let tag = try requireTag(arguments[1], in: usedTags(in: lists))
      guard canDeleteTag(tag, in: lists, userID: userID) else {
        throw CLIError(
          "Refusing to delete tag '\(tag.title)' because at least one linked list is shared with you rather than owned by you.",
          exitCode: 66
        )
      }
      try await context.send(DeleteRemindersV3Tag(tagID: tag.id))
      try output.write(ChangeOutput(event: "tags.delete", changedID: tag.id.rawValue, status: try await context.status()))

    default:
      throw CLIError("Unknown tags command '\(command)'.\n\(TagsUsage.text)", exitCode: 64)
    }
  }

  private static func runReminderTags(
    _ arguments: [String],
    context: CLIContext,
    output: OutputMode
  ) async throws {
    guard arguments.count >= 3 else {
      throw CLIError("Usage: reminders-v3-cli reminders tag <add|remove|set> <reminder-id> <tag> [...]", exitCode: 64)
    }
    let verb = arguments[0]
    let reminder = try await requireReminder(context: context, id: InstantID(rawValue: arguments[1]))
    let existing = reminder.tags.map(\.id)
    let normalizedTags = try arguments.dropFirst(2).map(normalizedTag)
    let resolvedTags = try await resolveTags(context: context, titles: normalizedTags)
    let requestedIDs = resolvedTags.map(\.id)
    let next: [InstantID<RemindersV3Tag>]
    switch verb {
    case "add":
      next = unique(existing + requestedIDs)
    case "remove", "rm":
      let removing = Set(requestedIDs.map(\.rawValue))
      next = existing.filter { !removing.contains($0.rawValue) }
    case "set":
      next = unique(requestedIDs)
    default:
      throw CLIError("Unknown tag command '\(verb)'. Use add, remove, or set.", exitCode: 64)
    }
    var titlesByID = Dictionary(uniqueKeysWithValues: reminder.tags.map { ($0.id, $0.title) })
    for tag in resolvedTags {
      titlesByID[tag.id] = tag.title
    }
    try await context.send(
      UpdateRemindersV3Reminder(
        reminderID: reminder.id,
        listID: reminder.list,
        title: reminder.title,
        notes: reminder.notes,
        isFlagged: reminder.isFlagged,
        dueDate: reminder.dueDate,
        priority: reminder.priority,
        existingTagIDs: existing,
        tagIDs: next,
        tagTitles: Dictionary(uniqueKeysWithValues: next.compactMap { id in
          titlesByID[id].map { (id, $0) }
        })
      )
    )
    try output.write(ChangeOutput(event: "reminders.tag.\(verb)", changedID: reminder.id.rawValue, status: try await context.status()))
  }

  private static func runShares(_ arguments: [String], output: OutputMode) async throws {
    guard let command = arguments.first else {
      throw CLIError(SharesUsage.text, exitCode: 64)
    }
    let context = try await CLIContext.bootstrap()
    switch command {
    case "create":
      guard arguments.count == 2 else {
        throw CLIError("Usage: reminders-v3-cli share create <list-id>", exitCode: 64)
      }
      let userID = try await context.requireUserID()
      let listID = InstantID<RemindersV3List>(rawValue: arguments[1])
      let shareID = InstantID<RemindersV3Share>(rawValue: context.makeID())
      try await context.send(
        CreateRemindersV3Share(
          shareID: shareID,
          ownerMembershipID: InstantID(rawValue: context.makeID()),
          listID: listID,
          ownerID: userID,
          token: context.makeID(),
          createdAt: context.now()
        )
      )
      try output.write(ChangeOutput(event: "share.create", changedID: shareID.rawValue, status: try await context.status()))

    case "grant":
      guard arguments.count == 5 else {
        throw CLIError("Usage: reminders-v3-cli share grant <list-id> <share-id> <user-id> <reader|writer>", exitCode: 64)
      }
      let role = try parseParticipantRole(arguments[4])
      let listID = InstantID<RemindersV3List>(rawValue: arguments[1])
      let shareID = InstantID<RemindersV3Share>(rawValue: arguments[2])
      let userID = InstantID<RemindersV3User>(rawValue: arguments[3])
      let membership = try await currentMembership(context: context, listID: listID, userID: userID)
      if let membership, let previousRole = membership.shareRole {
        try await context.send(
          ChangeRemindersV3ShareRole(
            shareID: shareID,
            membershipID: membership.id,
            listID: listID,
            userID: userID,
            previousRole: previousRole,
            role: role,
            updatedAt: context.now()
          )
        )
      } else {
        try await context.send(
          AcceptRemindersV3Share(
            shareID: shareID,
            membershipID: InstantID(rawValue: context.makeID()),
            listID: listID,
            userID: userID,
            role: role,
            acceptedAt: context.now()
          )
        )
      }
      try output.write(ChangeOutput(event: "share.grant", changedID: userID.rawValue, status: try await context.status()))

    case "revoke":
      guard arguments.count == 5 else {
        throw CLIError("Usage: reminders-v3-cli share revoke <list-id> <share-id> <membership-id> <reader|writer>", exitCode: 64)
      }
      let listID = InstantID<RemindersV3List>(rawValue: arguments[1])
      let shareID = InstantID<RemindersV3Share>(rawValue: arguments[2])
      let membershipID = InstantID<RemindersV3ShareMembership>(rawValue: arguments[3])
      let role = try parseParticipantRole(arguments[4])
      let membership = try await requireMembership(context: context, id: membershipID)
      try await context.send(
        RevokeRemindersV3Share(
          shareID: shareID,
          membershipID: membershipID,
          listID: listID,
          userID: membership.user,
          role: role,
          revokedAt: context.now()
        )
      )
      try output.write(ChangeOutput(event: "share.revoke", changedID: membershipID.rawValue, status: try await context.status()))

    default:
      throw CLIError("Unknown share command '\(command)'.\n\(SharesUsage.text)", exitCode: 64)
    }
  }

  private static func runSync(_ arguments: [String], output: OutputMode) async throws {
    let command = arguments.first ?? "status"
    let context = try await CLIContext.bootstrap(connectIfAuthenticated: false)
    switch command {
    case "status":
      try output.write(SyncOutput(event: "sync.status", status: try await context.status()))
    case "connect":
      _ = try await context.connectIfLive()
      try output.write(SyncOutput(event: "sync.connect", status: try await context.status()))
    case "close":
      _ = try await context.client.closeConnection()
      try output.write(SyncOutput(event: "sync.close", status: try await context.status()))
    case "flush":
      let result = try await context.client.flushPendingMutations()
      try output.write(FlushOutput(event: "sync.flush", confirmed: result.confirmed.map(\.id), failed: result.failed.map(\.id), status: try await context.status()))
    case "pending":
      let pending = await context.client.pendingMutations()
      try output.write(PendingOutput(event: "sync.pending", pendingIDs: pending.map(\.id), status: try await context.status()))
    default:
      throw CLIError("Unknown sync command '\(command)'.\n\(SyncUsage.text)", exitCode: 64)
    }
  }

  private static func loadVisibleLists(context: CLIContext) async throws -> [RemindersV3List] {
    let userID = try await context.requireUserID()
    let fetch = FetchAll<RemindersV3List>()
    try await fetch.load(visibleListsQuery(), using: context.client)
    return fetch.wrappedValue.filter { isVisible($0, to: userID) }
  }

  private static func watchLists(context: CLIContext, output: OutputMode) async throws {
    let userID = try await context.requireUserID()
    let fetch = FetchAll<RemindersV3List>()
    let subscription = try await fetch.subscribe(visibleListsQuery(), using: context.client)
    defer { subscription.cancel() }
    var lastLists: [RemindersV3List]?
    for try await lists in subscription {
      guard lists != lastLists else { continue }
      lastLists = lists
      try output.write(
        ListsOutput(
          event: "lists.watch",
          lists: lists.filter { isVisible($0, to: userID) },
          status: try await context.status()
        )
      )
    }
  }

  private static func loadReminders(
    context: CLIContext,
    options: ReminderListOptions
  ) async throws -> [RemindersV3Reminder] {
    let lists = try await loadVisibleLists(context: context)
    let visible = options.listID.map { listID in
      lists.filter { $0.id == listID }
    } ?? lists
    if let listID = options.listID, visible.isEmpty {
      throw CLIError("List not found or not visible to the signed-in user: \(listID.rawValue)", exitCode: 66)
    }
    return filter(visible.flatMap(\.reminders), options: options)
  }

  private static func watchReminders(
    context: CLIContext,
    output: OutputMode,
    options: ReminderListOptions
  ) async throws {
    let userID = try await context.requireUserID()
    let fetch = FetchAll<RemindersV3List>()
    let query = visibleListsQuery()
    let subscription = try await fetch.subscribe(query, using: context.client)
    defer { subscription.cancel() }
    var lastReminders: [RemindersV3Reminder]?
    for try await lists in subscription {
      let visible = lists.filter { isVisible($0, to: userID) }
      let selected = options.listID.map { listID in
        visible.filter { $0.id == listID }
      } ?? visible
      let reminders = filter(selected.flatMap(\.reminders), options: options)
      guard reminders != lastReminders else { continue }
      lastReminders = reminders
      try output.write(
        RemindersOutput(
          event: "reminders.watch",
          reminders: reminders,
          status: try await context.status()
        )
      )
    }
  }

  private static func remindersForList(
    context: CLIContext,
    listID: InstantID<RemindersV3List>
  ) async throws -> [RemindersV3Reminder] {
    let lists = try await loadVisibleLists(context: context)
    guard let list = lists.first(where: { $0.id == listID }) else {
      throw CLIError("List not found or not visible to the signed-in user: \(listID.rawValue)", exitCode: 66)
    }
    return list.reminders
  }

  private static func requireList(
    context: CLIContext,
    id: InstantID<RemindersV3List>
  ) async throws -> RemindersV3List {
    let lists = try await loadVisibleLists(context: context)
    guard let list = lists.first(where: { $0.id == id }) else {
      throw CLIError("List not found or not visible to the signed-in user: \(id.rawValue)", exitCode: 66)
    }
    return list
  }

  private static func selectLists(
    _ lists: [RemindersV3List],
    listID: InstantID<RemindersV3List>?
  ) throws -> [RemindersV3List] {
    guard let listID else { return lists }
    let selected = lists.filter { $0.id == listID }
    guard !selected.isEmpty else {
      throw CLIError("List not found or not visible to the signed-in user: \(listID.rawValue)", exitCode: 66)
    }
    return selected
  }

  private static func requireReminder(
    context: CLIContext,
    id: InstantID<RemindersV3Reminder>
  ) async throws -> RemindersV3Reminder {
    let reminders = try await loadVisibleLists(context: context).flatMap(\.reminders)
    guard let reminder = reminders.first(where: { $0.id == id }) else {
      throw CLIError("Reminder not found: \(id.rawValue)", exitCode: 66)
    }
    return reminder
  }

  private static func usedTags(in lists: [RemindersV3List]) -> [RemindersV3Tag] {
    var tagsByID: [InstantID<RemindersV3Tag>: RemindersV3Tag] = [:]
    for tag in lists.flatMap(\.reminders).flatMap(\.tags) {
      tagsByID[tag.id] = tag
    }
    return tagsByID.values.sorted {
      let comparison = $0.title.localizedCaseInsensitiveCompare($1.title)
      if comparison != .orderedSame { return comparison == .orderedAscending }
      return $0.id.rawValue < $1.id.rawValue
    }
  }

  private static func requireTag(
    _ raw: String,
    in tags: [RemindersV3Tag]
  ) throws -> RemindersV3Tag {
    let normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard let tag = tags.first(where: {
      $0.id.rawValue.lowercased() == normalized || $0.title.lowercased() == normalized
    }) else {
      throw CLIError("Tag not found: \(raw)", exitCode: 66)
    }
    return tag
  }

  private static func canDeleteTag(
    _ tag: RemindersV3Tag,
    in lists: [RemindersV3List],
    userID: InstantID<RemindersV3User>
  ) -> Bool {
    let linkedLists = lists.filter { list in
      list.reminders.contains { reminder in
        reminder.tags.contains { $0.id == tag.id }
      }
    }
    return !linkedLists.isEmpty && linkedLists.allSatisfy { $0.isOwned(by: userID) }
  }

  private static func resolveTags(
    context: CLIContext,
    titles: [String]
  ) async throws -> [(id: InstantID<RemindersV3Tag>, title: String)] {
    let fetch = FetchAll<RemindersV3Tag>()
    try await fetch.load(RemindersV3Tag.query, using: context.client)
    let existingByTitle = Dictionary(
      fetch.wrappedValue.map { ($0.title.lowercased(), $0) },
      uniquingKeysWith: { first, _ in first }
    )
    var seen: Set<String> = []
    return titles.compactMap { title in
      let normalized = title.lowercased()
      guard seen.insert(normalized).inserted else { return nil }
      if let existing = existingByTitle[normalized] {
        return (existing.id, existing.title)
      }
      return (InstantID(rawValue: context.makeID()), title)
    }
  }

  private static func visibleListsQuery() -> InstantEntityQuery<RemindersV3List> {
    let membershipQuery = RemindersV3ShareMembership.query
      .include(RemindersV3ShareMembership.user)
    let shareQuery = RemindersV3Share.query
      .include(RemindersV3Share.owner)
      .include(RemindersV3Share.memberships, membershipQuery)
    let reminderQuery = RemindersV3Reminder.query
      .include(RemindersV3Reminder.tags)
      .order(RemindersV3Reminder.position)
    return RemindersV3List.query
      .include(RemindersV3List.owner)
      .include(RemindersV3List.readers)
      .include(RemindersV3List.writers)
      .include(RemindersV3List.reminders, reminderQuery)
      .include(RemindersV3List.share, shareQuery)
      .order(RemindersV3List.position)
  }

  private static func isVisible(
    _ list: RemindersV3List,
    to userID: InstantID<RemindersV3User>
  ) -> Bool {
    list.owner == userID
      || list.readers.contains(userID)
      || list.writers.contains(userID)
  }

  private static func currentMembership(
    context: CLIContext,
    listID: InstantID<RemindersV3List>,
    userID: InstantID<RemindersV3User>
  ) async throws -> RemindersV3ShareMembership? {
    let lists = try await loadVisibleLists(context: context)
    return lists.first(where: { $0.id == listID })?.share?.memberships.first { $0.user == userID }
  }

  private static func requireMembership(
    context: CLIContext,
    id: InstantID<RemindersV3ShareMembership>
  ) async throws -> RemindersV3ShareMembership {
    let lists = try await loadVisibleLists(context: context)
    let memberships = lists.flatMap { $0.share?.memberships ?? [] }
    guard let membership = memberships.first(where: { $0.id == id }) else {
      throw CLIError("Share membership not found: \(id.rawValue)", exitCode: 66)
    }
    return membership
  }

  private static func filter(
    _ reminders: [RemindersV3Reminder],
    options: ReminderListOptions
  ) -> [RemindersV3Reminder] {
    reminders.filter { reminder in
      switch options.completion {
      case .open:
        return !reminder.isCompleted
      case .done:
        return reminder.isCompleted
      case .all:
        return true
      }
    }
  }

  private static func resolveCoverFileID(
    context: CLIContext,
    explicitID: String?,
    fileURL: URL?
  ) async throws -> String? {
    if let explicitID {
      return explicitID
    }
    guard let fileURL else { return nil }
    guard FileManager.default.fileExists(atPath: fileURL.path) else {
      throw CLIError("Cover file not found: \(fileURL.path)", exitCode: 66)
    }
    let file = try await context.client.uploadFile(
      from: fileURL,
      name: fileURL.lastPathComponent,
      contentType: contentType(for: fileURL)
    )
    return file.id
  }

  private static func contentType(for fileURL: URL) -> String? {
    switch fileURL.pathExtension.lowercased() {
    case "jpg", "jpeg":
      return "image/jpeg"
    case "png":
      return "image/png"
    case "gif":
      return "image/gif"
    case "heic":
      return "image/heic"
    case "webp":
      return "image/webp"
    default:
      return nil
    }
  }

  private static func parseParticipantRole(_ raw: String) throws -> InstantShareRole {
    switch raw.lowercased() {
    case "reader", "read":
      return .reader
    case "writer", "write":
      return .writer
    case "owner":
      throw CLIError("Role 'owner' is managed by list creation. Use reader or writer.", exitCode: 64)
    default:
      throw CLIError("Unknown role '\(raw)'. Use reader or writer.", exitCode: 64)
    }
  }

  fileprivate static func parsePriority(_ raw: String) throws -> RemindersV3Priority {
    switch raw.lowercased() {
    case "low", "1":
      return .low
    case "medium", "med", "2":
      return .medium
    case "high", "3":
      return .high
    default:
      throw CLIError("Unknown priority '\(raw)'. Use low, medium, high, 1, 2, or 3.", exitCode: 64)
    }
  }

  fileprivate static func parseDate(_ raw: String) throws -> Date {
    if let milliseconds = Int64(raw) {
      return Date(timeIntervalSince1970: Double(milliseconds) / 1_000)
    }
    let iso = ISO8601DateFormatter()
    if let date = iso.date(from: raw) { return date }
    let day = DateFormatter()
    day.calendar = Calendar(identifier: .gregorian)
    day.locale = Locale(identifier: "en_US_POSIX")
    day.dateFormat = "yyyy-MM-dd"
    if let date = day.date(from: raw) { return date }
    throw CLIError("Invalid date '\(raw)'. Use YYYY-MM-DD, ISO-8601, or epoch milliseconds.", exitCode: 64)
  }

  fileprivate static func normalizedTag(_ raw: String) throws -> String {
    let tag = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard !tag.isEmpty else {
      throw CLIError("Tag must not be empty.", exitCode: 64)
    }
    guard !tag.contains("/") else {
      throw CLIError("Tag '\(raw)' must not contain '/'.", exitCode: 64)
    }
    return tag
  }

  private static func unique<T: Hashable>(_ values: [T]) -> [T] {
    var seen: Set<T> = []
    return values.filter { seen.insert($0).inserted }
  }

  private static func joinedTitle(_ arguments: [String], from index: Int) -> String {
    arguments.dropFirst(index).joined(separator: " ")
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private static func printUsage() {
    print(
      """
      reminders-v3-cli

      Auth:
        reminders-v3-cli auth show
        reminders-v3-cli auth guest
        reminders-v3-cli auth token <refresh-token>
        reminders-v3-cli auth sign-out

      Lists:
        reminders-v3-cli lists list [--watch]
        reminders-v3-cli lists add "Family" [--color #4a99ef] [--cover-file path|--cover-file-id id]
        reminders-v3-cli lists rename <list-id> "New title"
        reminders-v3-cli lists update <list-id> [--title text] [--color #4a99ef] [--cover-file path|--cover-file-id id|--clear-cover]
        reminders-v3-cli lists delete <list-id>

      Tags:
        reminders-v3-cli tags list
        reminders-v3-cli tags delete <tag-id-or-title>

      Reminders:
        reminders-v3-cli reminders list [--list <list-id>] [--completed open|done|all] [--watch]
        reminders-v3-cli reminders add <list-id> "Title" [--notes text] [--due-date date] [--priority low|medium|high] [--flagged] [--tag tag]...
        reminders-v3-cli reminders update <reminder-id> [--title text] [--notes text] [--due-date date|--clear-due-date] [--priority low|medium|high|--clear-priority] [--flagged|--unflagged] [--tag tag]...
        reminders-v3-cli reminders complete <reminder-id>
        reminders-v3-cli reminders reopen <reminder-id>
        reminders-v3-cli reminders delete <reminder-id>
        reminders-v3-cli reminders delete-completed [--list <list-id>] [--scope all|1m|6m|1y]
        reminders-v3-cli reminders tag <add|remove|set> <reminder-id> <tag> [...]

      Sharing:
        reminders-v3-cli share create <list-id>
        reminders-v3-cli share grant <list-id> <share-id> <user-id> <reader|writer>
        reminders-v3-cli share revoke <list-id> <share-id> <membership-id> <reader|writer>

      Sync:
        reminders-v3-cli sync status
        reminders-v3-cli sync connect
        reminders-v3-cli sync flush
        reminders-v3-cli sync pending
        reminders-v3-cli sync close

      Environment:
        INSTANT_APP_ID enables live sync. Without it, the app is local/offline-first.
        INSTANT_PERSISTENCE_PATH overrides the SQLite cache path.
        Use an authenticated cache for the same user, or sign in a separate cache and
        grant that CLI user writer access to a shared list, to drive running app clients.
      """
    )
  }
}

private struct CLIContext {
  var client: InstantSwiftDataClient
  var appID: String
  var isLive: Bool

  static func bootstrap(connectIfAuthenticated: Bool = true) async throws -> Self {
    let environment = ProcessInfo.processInfo.environment
    let rawAppID = environment["INSTANT_APP_ID"]?.trimmingCharacters(in: .whitespacesAndNewlines)
    let isLive = rawAppID?.isEmpty == false
    let appID = isLive ? rawAppID! : "reminders-v3-local"
    let persistenceURL = try persistenceURL(appID: appID, environment: environment)
    var configuration = InstantRuntimeConfiguration(
      appID: appID,
      persistenceURL: persistenceURL,
      initialAttributes: RemindersV3Schema.attributes,
      refreshTokenVerifier: isLive ? .live : .local,
      guestAuthenticator: isLive ? .live : .local,
      authTokenInvalidator: isLive ? .live : .local,
      liveTransport: isLive ? .live : nil
    )
    configuration.autoConnectLiveTransport = isLive
    let runtime = try await InstantRuntime.bootstrap(configuration: configuration)
    let context = Self(client: InstantSwiftDataClient(runtime: runtime), appID: appID, isLive: isLive)
    if connectIfAuthenticated, isLive, try await context.client.authSession() != nil {
      _ = try? await context.client.connect()
    }
    return context
  }

  func requireUserID() async throws -> InstantID<RemindersV3User> {
    guard let session = try await client.authSession() else {
      throw CLIError(
        "Not signed in. Run 'reminders-v3-cli auth guest' or 'reminders-v3-cli auth token <refresh-token>'.",
        exitCode: 65
      )
    }
    return InstantID(rawValue: session.userID)
  }

  func connectIfLive() async throws -> InstantConnectionStatus? {
    guard isLive else { return nil }
    return try await client.connect()
  }

  func send<Message: InstantMessage>(_ message: Message) async throws {
    let prepared = try await message.prepare(using: client)
    _ = try await client.transact {
      for mutation in prepared.mutations { mutation }
    }
    if isLive {
      _ = try? await client.connect()
      _ = try? await client.flushPendingMutations()
    }
  }

  func status() async throws -> StatusOutput {
    let status = try await client.connectionStatus()
    return StatusOutput(
      appID: appID,
      mode: isLive ? "live" : "local",
      connectionState: status.state.rawValue,
      isAuthenticated: status.isAuthenticated,
      userID: status.userID,
      pendingMutationCount: status.pendingMutationCount
    )
  }

  func now() -> Date {
    Date()
  }

  func makeID() -> String {
    UUID().uuidString.lowercased()
  }

  private static func persistenceURL(appID: String, environment: [String: String]) throws -> URL {
    if let path = environment["INSTANT_PERSISTENCE_PATH"], !path.isEmpty {
      return URL(fileURLWithPath: path)
    }
    let root = FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent(".instant-swift-data", isDirectory: true)
      .appendingPathComponent("reminders-v3-cli", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let safeApp = appID.map { character in
      character.isLetter || character.isNumber || character == "-" || character == "_"
        ? character
        : "-"
    }
    return root.appendingPathComponent(String(safeApp) + ".sqlite")
  }
}

private enum OutputMode {
  case human
  case json

  static func consume(from arguments: inout [String]) -> Self {
    if let index = arguments.firstIndex(of: "--json") {
      arguments.remove(at: index)
      return .json
    }
    return .human
  }

  func write<Value: Encodable>(_ value: Value) throws {
    switch self {
    case .json:
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
      encoder.dateEncodingStrategy = .iso8601
      FileHandle.standardOutput.write(try encoder.encode(value))
      print()
    case .human:
      print(String(describing: value))
    }
  }
}

private struct ListOptions {
  var watch = false

  init(_ arguments: [String]) throws {
    for argument in arguments {
      switch argument {
      case "--watch":
        watch = true
      default:
        throw CLIError("Unknown lists list option '\(argument)'. Use --watch.", exitCode: 64)
      }
    }
  }
}

private struct AddListOptions {
  var title: String
  var color = "#4a99ef"
  var coverFileID: String?
  var coverFileURL: URL?

  init(_ arguments: [String]) throws {
    guard !arguments.isEmpty else {
      throw CLIError(
        "Usage: reminders-v3-cli lists add \"Family\" [--color #4a99ef] [--cover-file path|--cover-file-id id]",
        exitCode: 64
      )
    }
    var rest = arguments
    title = rest.removeFirst()
    while !rest.isEmpty {
      let option = rest.removeFirst()
      switch option {
      case "--color":
        guard let value = rest.first else {
          throw CLIError("Missing value for --color.", exitCode: 64)
        }
        color = value
        rest.removeFirst()
      case "--cover-file":
        guard coverFileID == nil else {
          throw CLIError("Use either --cover-file or --cover-file-id, not both.", exitCode: 64)
        }
        coverFileURL = URL(fileURLWithPath: try takeValue(&rest, option: option))
      case "--cover-file-id":
        guard coverFileURL == nil else {
          throw CLIError("Use either --cover-file or --cover-file-id, not both.", exitCode: 64)
        }
        coverFileID = try takeValue(&rest, option: option)
      default:
        throw CLIError(
          "Unknown lists add option '\(option)'. Use --color, --cover-file, or --cover-file-id.",
          exitCode: 64
        )
      }
    }
    guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw CLIError("List title must not be empty.", exitCode: 64)
    }
  }
}

private struct UpdateListOptions {
  var listID: InstantID<RemindersV3List>
  var title: String?
  var color: String?
  var coverFileID: String?
  var coverFileURL: URL?
  var clearsCover = false

  init(_ arguments: [String]) throws {
    guard !arguments.isEmpty else {
      throw CLIError(
        "Usage: reminders-v3-cli lists update <list-id> [--title text] [--color #4a99ef] [--cover-file path|--cover-file-id id|--clear-cover]",
        exitCode: 64
      )
    }
    var rest = arguments
    listID = InstantID(rawValue: rest.removeFirst())
    while !rest.isEmpty {
      let option = rest.removeFirst()
      switch option {
      case "--title":
        title = try takeValue(&rest, option: option)
      case "--color":
        color = try takeValue(&rest, option: option)
      case "--cover-file":
        try ensureCanSetCover(option)
        coverFileURL = URL(fileURLWithPath: try takeValue(&rest, option: option))
      case "--cover-file-id":
        try ensureCanSetCover(option)
        coverFileID = try takeValue(&rest, option: option)
      case "--clear-cover":
        guard coverFileID == nil, coverFileURL == nil else {
          throw CLIError("Use --clear-cover by itself, not with a replacement cover.", exitCode: 64)
        }
        clearsCover = true
      default:
        throw CLIError(
          "Unknown lists update option '\(option)'. Use --title, --color, --cover-file, --cover-file-id, or --clear-cover.",
          exitCode: 64
        )
      }
    }
    guard title != nil || color != nil || coverFileID != nil || coverFileURL != nil || clearsCover else {
      throw CLIError(
        "Usage: reminders-v3-cli lists update <list-id> [--title text] [--color #4a99ef] [--cover-file path|--cover-file-id id|--clear-cover]",
        exitCode: 64
      )
    }
  }

  private func ensureCanSetCover(_ option: String) throws {
    if clearsCover {
      throw CLIError("Use --clear-cover by itself, not with \(option).", exitCode: 64)
    }
    if coverFileID != nil || coverFileURL != nil {
      throw CLIError("Only one cover option is allowed.", exitCode: 64)
    }
  }
}

private enum CompletionFilter {
  case open
  case done
  case all
}

private enum CompletedCleanupScope: CustomStringConvertible {
  case all
  case olderThanMonths(Int)

  func includes(_ reminder: RemindersV3Reminder, now: Date) -> Bool {
    guard reminder.isCompleted else { return false }
    switch self {
    case .all:
      return true
    case .olderThanMonths(let months):
      guard let dueDate = reminder.dueDate,
        let cutoff = Calendar.current.date(byAdding: .month, value: -months, to: now)
      else { return false }
      return dueDate < cutoff
    }
  }

  var description: String {
    switch self {
    case .all:
      return "all"
    case .olderThanMonths(1):
      return "1m"
    case .olderThanMonths(6):
      return "6m"
    case .olderThanMonths(12):
      return "1y"
    case .olderThanMonths(let months):
      return "\(months)m"
    }
  }
}

private struct CompletedCleanupOptions {
  var listID: InstantID<RemindersV3List>?
  var scope = CompletedCleanupScope.all

  init(_ arguments: [String]) throws {
    var rest = arguments
    while !rest.isEmpty {
      let option = rest.removeFirst()
      switch option {
      case "--list", "--list-id":
        listID = InstantID(rawValue: try takeValue(&rest, option: option))
      case "--scope", "--older-than":
        scope = try Self.parseScope(try takeValue(&rest, option: option))
      case "--all":
        scope = .all
      default:
        throw CLIError(
          "Unknown delete-completed option '\(option)'. Use --list, --scope all|1m|6m|1y, or --older-than 1m|6m|1y.",
          exitCode: 64
        )
      }
    }
  }

  private static func parseScope(_ raw: String) throws -> CompletedCleanupScope {
    switch raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
    case "all":
      return .all
    case "1m", "1mo", "1month", "1-month", "month":
      return .olderThanMonths(1)
    case "6m", "6mo", "6months", "6-month", "6-months":
      return .olderThanMonths(6)
    case "1y", "12m", "12mo", "1year", "1-year", "year":
      return .olderThanMonths(12)
    case let value:
      if value.hasSuffix("m"),
        let months = Int(value.dropLast()),
        months > 0
      {
        return .olderThanMonths(months)
      }
      throw CLIError("Invalid completed cleanup scope '\(raw)'. Use all, 1m, 6m, or 1y.", exitCode: 64)
    }
  }
}

private struct ReminderListOptions {
  var listID: InstantID<RemindersV3List>?
  var completion = CompletionFilter.open
  var watch = false

  var includeCompleted: Bool {
    completion != .open
  }

  init(_ arguments: [String]) throws {
    var rest = arguments
    while !rest.isEmpty {
      let option = rest.removeFirst()
      switch option {
      case "--list":
        guard let value = rest.first else {
          throw CLIError("Missing value for --list.", exitCode: 64)
        }
        listID = InstantID(rawValue: value)
        rest.removeFirst()
      case "--completed":
        guard let value = rest.first else {
          throw CLIError("Missing value for --completed. Use open, done, or all.", exitCode: 64)
        }
        switch value.lowercased() {
        case "open", "false":
          completion = .open
        case "done", "true":
          completion = .done
        case "all":
          completion = .all
        default:
          throw CLIError("Invalid --completed value '\(value)'. Use open, done, or all.", exitCode: 64)
        }
        rest.removeFirst()
      case "--watch":
        watch = true
      default:
        throw CLIError("Unknown reminders list option '\(option)'. Use --list, --completed, or --watch.", exitCode: 64)
      }
    }
  }
}

private struct AddReminderOptions {
  var listID: InstantID<RemindersV3List>
  var title: String
  var notes = ""
  var dueDate: Date?
  var priority: RemindersV3Priority?
  var isFlagged = false
  var tagIDs: [InstantID<RemindersV3Tag>] = []
  var tagTitles: [InstantID<RemindersV3Tag>: String] = [:]

  init(_ arguments: [String]) throws {
    guard arguments.count >= 2 else {
      throw CLIError(RemindersUsage.add, exitCode: 64)
    }
    var rest = arguments
    listID = InstantID(rawValue: rest.removeFirst())
    title = rest.removeFirst()
    while !rest.isEmpty {
      let option = rest.removeFirst()
      switch option {
      case "--notes":
        notes = try takeValue(&rest, option: option)
      case "--due-date":
        dueDate = try RemindersV3CLI.parseDate(takeValue(&rest, option: option))
      case "--priority":
        priority = try RemindersV3CLI.parsePriority(takeValue(&rest, option: option))
      case "--flagged":
        isFlagged = true
      case "--tag":
        let tag = try RemindersV3CLI.normalizedTag(takeValue(&rest, option: option))
        let id = InstantID<RemindersV3Tag>(rawValue: tag)
        tagIDs.append(id)
        tagTitles[id] = tag
      default:
        throw CLIError("Unknown reminders add option '\(option)'.\n\(RemindersUsage.add)", exitCode: 64)
      }
    }
  }
}

private struct UpdateReminderOptions {
  var reminderID: InstantID<RemindersV3Reminder>
  var title: String?
  var notes: String?
  var dueDate: Date?
  var clearsDueDate = false
  var priority: RemindersV3Priority?
  var clearsPriority = false
  var isFlagged: Bool?
  var replacingTags: [InstantID<RemindersV3Tag>]?
  var tagTitles: [InstantID<RemindersV3Tag>: String] = [:]

  init(_ arguments: [String]) throws {
    guard !arguments.isEmpty else {
      throw CLIError(RemindersUsage.update, exitCode: 64)
    }
    var rest = arguments
    reminderID = InstantID(rawValue: rest.removeFirst())
    while !rest.isEmpty {
      let option = rest.removeFirst()
      switch option {
      case "--title":
        title = try takeValue(&rest, option: option)
      case "--notes":
        notes = try takeValue(&rest, option: option)
      case "--due-date":
        dueDate = try RemindersV3CLI.parseDate(takeValue(&rest, option: option))
        clearsDueDate = false
      case "--clear-due-date":
        clearsDueDate = true
        dueDate = nil
      case "--priority":
        priority = try RemindersV3CLI.parsePriority(takeValue(&rest, option: option))
        clearsPriority = false
      case "--clear-priority":
        clearsPriority = true
        priority = nil
      case "--flagged":
        isFlagged = true
      case "--unflagged":
        isFlagged = false
      case "--tag":
        let tag = try RemindersV3CLI.normalizedTag(takeValue(&rest, option: option))
        let id = InstantID<RemindersV3Tag>(rawValue: tag)
        replacingTags = (replacingTags ?? []) + [id]
        tagTitles[id] = tag
      default:
        throw CLIError("Unknown reminders update option '\(option)'.\n\(RemindersUsage.update)", exitCode: 64)
      }
    }
  }
}

private func takeValue(_ arguments: inout [String], option: String) throws -> String {
  guard let value = arguments.first, !value.hasPrefix("--") else {
    throw CLIError("Missing value for \(option).", exitCode: 64)
  }
  arguments.removeFirst()
  return value
}

private struct AuthOutput: Codable, CustomStringConvertible {
  var event = "auth"
  var appID: String
  var mode: String
  var isSignedIn: Bool
  var userID: String?
  var isGuest: Bool?
  var hasRefreshToken: Bool

  init(context: CLIContext, session: InstantAuthSession?) {
    appID = context.appID
    mode = context.isLive ? "live" : "local"
    isSignedIn = session != nil
    userID = session?.userID
    isGuest = session?.isGuest
    hasRefreshToken = session?.refreshToken?.isEmpty == false
  }

  var description: String {
    guard isSignedIn else { return "auth: signed out (\(mode), app \(appID))" }
    return "auth: \(isGuest == true ? "guest" : "user") \(userID ?? "") refresh-token=\(hasRefreshToken ? "present" : "none")"
  }
}

private struct StatusOutput: Codable, CustomStringConvertible {
  var appID: String
  var mode: String
  var connectionState: String
  var isAuthenticated: Bool
  var userID: String?
  var pendingMutationCount: Int

  var description: String {
    "status: \(mode) \(connectionState), authenticated=\(isAuthenticated), pending=\(pendingMutationCount)"
  }
}

private struct ListsOutput: Codable, CustomStringConvertible {
  var event: String
  var lists: [RemindersV3List]
  var status: StatusOutput

  var description: String {
    if lists.isEmpty { return "\(event): no lists\n\(status)" }
    return lists.map { list in
      let cover = list.coverFileID.map { " cover=\($0)" } ?? ""
      return "\(list.id.rawValue)  \(list.title)  color=\(list.color)\(cover) open=\(list.reminders.filter { !$0.isCompleted }.count) share=\(list.share?.id.rawValue ?? "-")"
    }.joined(separator: "\n") + "\n\(status)"
  }
}

private struct TagsOutput: Codable, CustomStringConvertible {
  var event: String
  var tags: [RemindersV3Tag]
  var status: StatusOutput

  var description: String {
    if tags.isEmpty { return "\(event): no tags\n\(status)" }
    return tags.map { "\($0.id.rawValue)  #\($0.title)" }.joined(separator: "\n")
      + "\n\(status)"
  }
}

private struct RemindersOutput: Codable, CustomStringConvertible {
  var event: String
  var reminders: [RemindersV3Reminder]
  var status: StatusOutput

  var description: String {
    if reminders.isEmpty { return "\(event): no reminders\n\(status)" }
    return reminders.map { reminder in
      let box = reminder.isCompleted ? "☑" : "☐"
      let priority = reminder.priority.map { " p\($0.rawValue)" } ?? ""
      let tags = reminder.tags.isEmpty ? "" : " #" + reminder.tags.map(\.title).joined(separator: " #")
      return "\(box) \(reminder.id.rawValue)  \(reminder.title)\(priority)\(tags)"
    }.joined(separator: "\n") + "\n\(status)"
  }
}

private struct ChangeOutput: Codable, CustomStringConvertible {
  var event: String
  var changedID: String
  var status: StatusOutput

  var description: String {
    "\(event): \(changedID)\n\(status)"
  }
}

private struct SyncOutput: Codable, CustomStringConvertible {
  var event: String
  var status: StatusOutput

  var description: String {
    "\(event)\n\(status)"
  }
}

private struct FlushOutput: Codable, CustomStringConvertible {
  var event: String
  var confirmed: [String]
  var failed: [String]
  var status: StatusOutput

  var description: String {
    "\(event): confirmed=\(confirmed.count) failed=\(failed.count)\n\(status)"
  }
}

private struct PendingOutput: Codable, CustomStringConvertible {
  var event: String
  var pendingIDs: [String]
  var status: StatusOutput

  var description: String {
    "\(event): \(pendingIDs.isEmpty ? "none" : pendingIDs.joined(separator: ", "))\n\(status)"
  }
}

private struct DeleteCompletedOutput: Codable, CustomStringConvertible {
  var event: String
  var deletedIDs: [String]
  var scope: String
  var status: StatusOutput

  var description: String {
    "\(event): deleted=\(deletedIDs.count) scope=\(scope)\n\(status)"
  }
}

private struct SimpleOutput: Codable, CustomStringConvertible {
  var event: String
  var ok: Bool
  var message: String

  var description: String { message }
}

private enum AuthUsage {
  static let text = "Usage: reminders-v3-cli auth <show|guest|token|sign-out>"
}

private enum ListsUsage {
  static let text = "Usage: reminders-v3-cli lists <list|add|rename|update|delete>"
}

private enum TagsUsage {
  static let text = "Usage: reminders-v3-cli tags <list|delete>"
}

private enum RemindersUsage {
  static let text = "Usage: reminders-v3-cli reminders <list|add|update|complete|reopen|delete|delete-completed|tag>"
  static let add = "Usage: reminders-v3-cli reminders add <list-id> \"Title\" [--notes text] [--due-date date] [--priority low|medium|high] [--flagged] [--tag tag]..."
  static let update = "Usage: reminders-v3-cli reminders update <reminder-id> [--title text] [--notes text] [--due-date date|--clear-due-date] [--priority low|medium|high|--clear-priority] [--flagged|--unflagged] [--tag tag]..."
}

private enum SharesUsage {
  static let text = "Usage: reminders-v3-cli share <create|grant|revoke>"
}

private enum SyncUsage {
  static let text = "Usage: reminders-v3-cli sync <status|connect|flush|pending|close>"
}

private struct CLIError: Error, CustomStringConvertible {
  var description: String
  var exitCode: Int32

  init(_ description: String, exitCode: Int32) {
    self.description = description
    self.exitCode = exitCode
  }
}

private func writeError(_ message: String) {
  FileHandle.standardError.write(Data((message + "\n").utf8))
}
