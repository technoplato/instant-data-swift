import Dependencies
import Foundation
import InstantSwiftData

#if canImport(SwiftUI)
  import SwiftUI
  #if canImport(PhotosUI)
    import PhotosUI
  #endif
  #if canImport(UIKit)
    import UIKit
  #elseif canImport(AppKit)
    import AppKit
  #endif
  #if canImport(PhotosUI)
    import PhotosUI
  #endif
  #if canImport(UIKit)
    import UIKit
  #elseif canImport(AppKit)
    import AppKit
  #endif

  public enum RemindersV3CollectionFilter: Hashable, Sendable {
    case all
    case completed
    case flagged
    case scheduled
    case today
    case tag(id: InstantID<RemindersV3Tag>, title: String)
    case search(String)

    public var title: String {
      switch self {
      case .all: "All"
      case .completed: "Completed"
      case .flagged: "Flagged"
      case .scheduled: "Scheduled"
      case .today: "Today"
      case .tag(_, let title): "#\(title)"
      case .search(let text): "Search: \(text)"
      }
    }
  }

  public enum RemindersV3Ordering: String, CaseIterable, Hashable, Sendable {
    case dueDate = "Due Date"
    case manual = "Manual"
    case priority = "Priority"
    case title = "Title"
  }

  public enum RemindersV3CompletedCleanupScope: Hashable, Sendable {
    case olderThan(months: Int)
    case all

    public static let menuCases: [Self] = [
      .olderThan(months: 1),
      .olderThan(months: 6),
      .olderThan(months: 12),
      .all,
    ]

    public var title: String {
      switch self {
      case .olderThan(months: 1): "Older Than 1 Month"
      case .olderThan(months: 6): "Older Than 6 Months"
      case .olderThan(months: 12): "Older Than 1 Year"
      case .olderThan(let months): "Older Than \(months) Months"
      case .all: "All Completed"
      }
    }

    fileprivate var monthsAgo: Int? {
      switch self {
      case .olderThan(let months): months
      case .all: nil
      }
    }
  }

  public struct RemindersV3PresentationRow: Identifiable, Hashable, Sendable {
    public var id: InstantID<RemindersV3Reminder> { reminder.id }
    public var list: RemindersV3List
    public var reminder: RemindersV3Reminder
    public var searchSummary: String?
    public var searchScore: Int

    public init(
      list: RemindersV3List,
      reminder: RemindersV3Reminder,
      searchSummary: String? = nil,
      searchScore: Int = 0
    ) {
      self.list = list
      self.reminder = reminder
      self.searchSummary = searchSummary
      self.searchScore = searchScore
    }
  }

  public struct RemindersV3SearchMatch: Hashable, Sendable {
    public var score: Int
    public var summary: String

    public init(score: Int, summary: String) {
      self.score = score
      self.summary = summary
    }
  }

  public enum RemindersV3Presentation {
    public static func stats(
      lists: [RemindersV3List],
      now: Date
    ) -> RemindersStats {
      let reminders = lists.flatMap(\.reminders)
      let calendar = Calendar.current
      let incomplete = reminders.filter { !$0.isCompleted }
      return RemindersStats(
        allCount: incomplete.count,
        completedCount: reminders.filter(\.isCompleted).count,
        flaggedCount: incomplete.filter(\.isFlagged).count,
        scheduledCount: incomplete.filter { $0.dueDate != nil }.count,
        todayCount: incomplete.filter { reminder in
          reminder.dueDate.map { calendar.isDate($0, inSameDayAs: now) } ?? false
        }.count
      )
    }

    public static func usedTags(in lists: [RemindersV3List]) -> [RemindersV3Tag] {
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

    public static func rows(
      lists: [RemindersV3List],
      filter: RemindersV3CollectionFilter,
      showCompleted: Bool,
      ordering: RemindersV3Ordering,
      now: Date
    ) -> [RemindersV3PresentationRow] {
      let candidateRows = lists
        .flatMap { list in
          list.reminders.map { RemindersV3PresentationRow(list: list, reminder: $0) }
        }
        .filter { row in
          matches(row.reminder, filter: filter, now: now)
            && (showCompleted || !row.reminder.isCompleted || filter == .completed)
        }

      if case .search(let text) = filter {
        return candidateRows
          .compactMap { row in
            guard let match = searchMatch(row.reminder, text: text) else { return nil }
            return RemindersV3PresentationRow(
              list: row.list,
              reminder: row.reminder,
              searchSummary: match.summary,
              searchScore: match.score
            )
          }
          .sorted { lhs, rhs in
            if lhs.searchScore != rhs.searchScore { return lhs.searchScore > rhs.searchScore }
            return isOrdered(lhs.reminder, before: rhs.reminder, ordering: ordering)
          }
      }

      return candidateRows.sorted { lhs, rhs in
        isOrdered(lhs.reminder, before: rhs.reminder, ordering: ordering)
      }
    }

    public static func completedRows(
      _ rows: [RemindersV3PresentationRow],
      scope: RemindersV3CompletedCleanupScope,
      now: Date
    ) -> [RemindersV3PresentationRow] {
      rows.filter { row in
        guard row.reminder.isCompleted else { return false }
        guard let monthsAgo = scope.monthsAgo else { return true }
        guard let dueDate = row.reminder.dueDate,
          let cutoff = Calendar.current.date(byAdding: .month, value: -monthsAgo, to: now)
        else { return false }
        return dueDate < cutoff
      }
    }

    public static func completedReminders(
      _ reminders: [RemindersV3Reminder],
      scope: RemindersV3CompletedCleanupScope,
      now: Date
    ) -> [RemindersV3Reminder] {
      reminders.filter { reminder in
        guard reminder.isCompleted else { return false }
        guard let monthsAgo = scope.monthsAgo else { return true }
        guard let dueDate = reminder.dueDate,
          let cutoff = Calendar.current.date(byAdding: .month, value: -monthsAgo, to: now)
        else { return false }
        return dueDate < cutoff
      }
    }

    public static func canDeleteTag(
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

    public static func searchSummary(
      for reminder: RemindersV3Reminder,
      text: String
    ) -> String? {
      searchMatch(reminder, text: text)?.summary
    }

    public static func sorted(
      reminders: [RemindersV3Reminder],
      showCompleted: Bool,
      ordering: RemindersV3Ordering
    ) -> [RemindersV3Reminder] {
      reminders
        .filter { showCompleted || !$0.isCompleted }
        .sorted { isOrdered($0, before: $1, ordering: ordering) }
    }

    public static func completedRowsToDelete(
      rows: [RemindersV3PresentationRow],
      scope: RemindersV3CompletedCleanupScope,
      now: Date
    ) -> [RemindersV3PresentationRow] {
      completedRows(rows, scope: scope, now: now)
    }

    public static func searchPreview(
      for reminder: RemindersV3Reminder,
      text: String
    ) -> String? {
      let terms =
        text
        .split(whereSeparator: \Character.isWhitespace)
        .map { String($0).trimmingCharacters(in: CharacterSet(charactersIn: "#")).lowercased() }
        .filter { !$0.isEmpty }
      guard !terms.isEmpty else { return nil }
      let fields = [reminder.title, reminder.notes] + reminder.tags.map { "#\($0.title)" }
      for field in fields where !field.isEmpty {
        let lowercased = field.lowercased()
        if let term = terms.first(where: { lowercased.contains($0) }) {
          return snippet(in: field, around: term)
        }
      }
      return nil
    }

    private static func matches(
      _ reminder: RemindersV3Reminder,
      filter: RemindersV3CollectionFilter,
      now: Date
    ) -> Bool {
      switch filter {
      case .all:
        return true
      case .completed:
        return reminder.isCompleted
      case .flagged:
        return reminder.isFlagged
      case .scheduled:
        return reminder.dueDate != nil
      case .today:
        return reminder.dueDate.map { Calendar.current.isDate($0, inSameDayAs: now) } ?? false
      case .tag(let id, _):
        return reminder.tags.contains { $0.id == id }
      case .search(let text):
        return searchMatch(reminder, text: text) != nil
      }
    }

    private static func searchMatch(
      _ reminder: RemindersV3Reminder,
      text: String
    ) -> RemindersV3SearchMatch? {
      let terms =
        text
        .split(whereSeparator: \Character.isWhitespace)
        .map { String($0).lowercased() }
      guard !terms.isEmpty else { return nil }
      let title = reminder.title.lowercased()
      let notes = reminder.notes.lowercased()
      let tagTitles = reminder.tags.map { $0.title.lowercased() }
      var score = 0
      var summary: String?

      for term in terms {
        if term.hasPrefix("#") {
          let tagTerm = String(term.dropFirst())
          guard tagTitles.contains(tagTerm) else { return nil }
          score += 80
          summary = summary ?? "#\(tagTerm)"
        } else if title.contains(term) {
          score += title == term ? 140 : 100
          summary = summary ?? "Title: \(snippet(in: reminder.title, around: term))"
        } else if tagTitles.contains(where: { $0.contains(term) }) {
          score += 70
          summary = summary
            ?? reminder.tags.first { $0.title.lowercased().contains(term) }.map {
              "#\($0.title)"
            }
        } else if notes.contains(term) {
          score += 40
          summary = summary ?? "Notes: \(snippet(in: reminder.notes, around: term))"
        } else {
          return nil
        }
      }
      return RemindersV3SearchMatch(score: score, summary: summary ?? reminder.title)
    }

    private static func snippet(in text: String, around term: String) -> String {
      let lowercased = text.lowercased()
      guard let range = lowercased.range(of: term) else { return text }
      let distance = lowercased.distance(from: lowercased.startIndex, to: range.lowerBound)
      let startOffset = max(0, distance - 32)
      let endOffset = min(text.count, distance + term.count + 64)
      let start = text.index(text.startIndex, offsetBy: startOffset)
      let end = text.index(text.startIndex, offsetBy: endOffset)
      let prefix = startOffset > 0 ? "..." : ""
      let suffix = endOffset < text.count ? "..." : ""
      return prefix + String(text[start..<end]) + suffix
    }

    private static func isOrdered(
      _ lhs: RemindersV3Reminder,
      before rhs: RemindersV3Reminder,
      ordering: RemindersV3Ordering
    ) -> Bool {
      if lhs.isCompleted != rhs.isCompleted {
        return !lhs.isCompleted
      }
      switch ordering {
      case .dueDate:
        switch (lhs.dueDate, rhs.dueDate) {
        case (let lhs?, let rhs?) where lhs != rhs: return lhs < rhs
        case (.some, nil): return true
        case (nil, .some): return false
        default: return (lhs.position, lhs.id.rawValue) < (rhs.position, rhs.id.rawValue)
        }
      case .manual:
        return (lhs.position, lhs.id.rawValue) < (rhs.position, rhs.id.rawValue)
      case .priority:
        let lhsPriority = lhs.priority?.rawValue ?? 0
        let rhsPriority = rhs.priority?.rawValue ?? 0
        if lhsPriority != rhsPriority { return lhsPriority > rhsPriority }
        if lhs.isFlagged != rhs.isFlagged { return lhs.isFlagged }
        return (lhs.position, lhs.id.rawValue) < (rhs.position, rhs.id.rawValue)
      case .title:
        let comparison = lhs.title.localizedCaseInsensitiveCompare(rhs.title)
        if comparison != .orderedSame { return comparison == .orderedAscending }
        return lhs.id.rawValue < rhs.id.rawValue
      }
    }
  }

  struct RemindersV3ReminderFormDestination: Identifiable, Hashable {
    var id: String
    var listID: InstantID<RemindersV3List>
    var reminder: RemindersV3Reminder?
  }

  @MainActor
  @available(iOS 17.0, macOS 14.0, *)
  struct RemindersV3CollectionScreen: View {
    @FetchAll private var lists: [RemindersV3List]
    @Dependency(\.defaultInstantSwiftData) private var db
    @Dependency(\.date.now) private var now
    @Dependency(\.uuid) private var uuid

    @State private var form: RemindersV3ReminderFormDestination?
    @State private var message = ""
    @State private var ordering = RemindersV3Ordering.dueDate
    @State private var showCompleted: Bool

    let userID: InstantID<RemindersV3User>
    let filter: RemindersV3CollectionFilter

    init(
      userID: InstantID<RemindersV3User>,
      filter: RemindersV3CollectionFilter
    ) {
      self.userID = userID
      self.filter = filter
      showCompleted = filter == .completed
    }

    var body: some View {
      List {
        if rows.isEmpty {
          ContentUnavailableView(
            "No reminders",
            systemImage: "checklist",
            description: Text("Changes from other devices will appear here automatically.")
          )
        }
        ForEach(rows) { row in
          RemindersV3ReminderRow(
            reminder: row.reminder,
            listTitle: row.list.title,
            searchSummary: row.searchSummary,
            isEditable: row.list.canWrite(as: userID),
            onToggle: { toggle(row) },
            onEdit: { edit(row) },
            onDelete: { delete(row) }
          )
        }
        if !message.isEmpty { Text(message) }
      }
      .navigationTitle(filter.title)
      .toolbar {
        ToolbarItem(placement: .primaryAction) {
          Menu("View", systemImage: "ellipsis.circle") {
            Picker("Sort By", selection: $ordering) {
              ForEach(RemindersV3Ordering.allCases, id: \.self) {
                Text($0.rawValue).tag($0)
              }
            }
            if filter != .completed {
              Button(showCompleted ? "Hide Completed" : "Show Completed") {
                showCompleted.toggle()
              }
            }
            if canClearCompleted {
              Menu("Clear Completed", systemImage: "trash") {
                ForEach(RemindersV3CompletedCleanupScope.menuCases, id: \.self) { scope in
                  Button(scope.title, role: .destructive) {
                    clearCompleted(scope)
                  }
                }
              }
            }
          }
        }
      }
      .sheet(item: $form) { destination in
        NavigationStack {
          RemindersV3ReminderFormScreen(
            userID: userID,
            initialListID: destination.listID,
            reminder: destination.reminder,
            defaultDueDate: now
          )
        }
      }
      .task(id: userID) { await observeLists() }
      .onChange(of: rows.map(\.id)) { _, ids in
        InstantDiagnostics.shared.record(
          .info,
          subsystem: "reminders-v3",
          category: "query",
          event: "collection-query.emitted",
          message: "A Reminders collection emitted a snapshot.",
          metadata: [
            "collection": filter.title,
            "count": String(ids.count),
          ]
        )
      }
    }

    private var rows: [RemindersV3PresentationRow] {
      RemindersV3Presentation.rows(
        lists: lists,
        filter: filter,
        showCompleted: showCompleted,
        ordering: ordering,
        now: now
      )
    }

    private var allMatchingRows: [RemindersV3PresentationRow] {
      RemindersV3Presentation.rows(
        lists: lists,
        filter: filter,
        showCompleted: true,
        ordering: ordering,
        now: now
      )
    }

    private var canClearCompleted: Bool {
      allMatchingRows.contains { row in
        row.reminder.isCompleted && row.list.canWrite(as: userID)
      }
    }

    private func observeLists() async {
      do {
        try await $lists.task(RemindersV3List.visible(to: userID))
      } catch is CancellationError {
      } catch {
        message = String(describing: error)
        InstantDiagnostics.shared.record(
          error: error,
          subsystem: "reminders-v3",
          category: "query",
          event: "collection-query.failed",
          message: "A Reminders collection query failed.",
          metadata: ["collection": filter.title]
        )
      }
    }

    private func edit(_ row: RemindersV3PresentationRow) {
      form = RemindersV3ReminderFormDestination(
        id: row.reminder.id.rawValue,
        listID: row.list.id,
        reminder: row.reminder
      )
    }

    private func toggle(_ row: RemindersV3PresentationRow) {
      db.send(
        SetRemindersV3Completion(
          reminderID: row.reminder.id,
          listID: row.list.id,
          isCompleted: !row.reminder.isCompleted
        ),
        onFailure: handleMutationFailure
      )
    }

    private func delete(_ row: RemindersV3PresentationRow) {
      db.send(
        DeleteRemindersV3Reminder(
          reminderID: row.reminder.id,
          listID: row.list.id
        ),
        onFailure: handleMutationFailure
      )
    }

    private func clearCompleted(_ scope: RemindersV3CompletedCleanupScope) {
      let targets = RemindersV3Presentation.completedRowsToDelete(
        rows: allMatchingRows,
        scope: scope,
        now: now
      )
      .filter { $0.list.canWrite(as: userID) }
      .map {
        DeleteRemindersV3CompletedReminders.Target(
          reminderID: $0.reminder.id,
          listID: $0.list.id
        )
      }
      guard !targets.isEmpty else {
        message = "No completed reminders matched \(scope.title.lowercased())."
        return
      }
      db.send(
        DeleteRemindersV3CompletedReminders(targets: targets),
        onServerAccepted: { _ in message = "Completed reminders cleared" },
        onFailure: handleMutationFailure
      )
    }

    private func handleMutationFailure(_ error: InstantError) {
      message = error.recoveryMessage
      InstantDiagnostics.shared.record(
        error: error,
        subsystem: "reminders-v3",
        category: "mutation",
        event: "collection-mutation.failed",
        message: "A Reminders collection mutation failed.",
        metadata: ["collection": filter.title]
      )
    }
  }

  @MainActor
  @available(iOS 17.0, macOS 14.0, *)
  struct RemindersV3ReminderFormScreen: View {
    @FetchAll private var lists: [RemindersV3List]
    @Dependency(\.defaultInstantSwiftData) private var db
    @Dependency(\.date.now) private var now
    @Dependency(\.uuid) private var uuid
    @Environment(\.dismiss) private var dismiss

    @State private var dueDate: Date
    @State private var hasDueDate: Bool
    @State private var isFlagged: Bool
    @State private var listID: InstantID<RemindersV3List>
    @State private var message = ""
    @State private var notes: String
    @State private var priority: RemindersV3Priority?
    @State private var tagText: String
    @State private var title: String

    let userID: InstantID<RemindersV3User>
    let reminder: RemindersV3Reminder?

    init(
      userID: InstantID<RemindersV3User>,
      initialListID: InstantID<RemindersV3List>,
      reminder: RemindersV3Reminder?,
      defaultDueDate: Date
    ) {
      self.userID = userID
      self.reminder = reminder
      title = reminder?.title ?? ""
      notes = reminder?.notes ?? ""
      isFlagged = reminder?.isFlagged ?? false
      hasDueDate = reminder?.dueDate != nil
      dueDate = reminder?.dueDate ?? defaultDueDate
      priority = reminder?.priority
      listID = reminder?.list ?? initialListID
      tagText = reminder?.tags.map(\.title).joined(separator: ", ") ?? ""
    }

    var body: some View {
      Form {
        Section("Reminder") {
          TextField("Title", text: $title)
          TextField("Notes", text: $notes, axis: .vertical)
            .lineLimit(2...5)
          TextField("Tags, separated by commas", text: $tagText)
        }
        Section("Schedule") {
          Toggle("Date", isOn: $hasDueDate)
          if hasDueDate {
            DatePicker("Due", selection: $dueDate)
          }
          Toggle("Flagged", isOn: $isFlagged)
          Picker("Priority", selection: $priority) {
            Text("None").tag(RemindersV3Priority?.none)
            ForEach(RemindersV3Priority.allCases, id: \.self) { priority in
              Text(priority.title).tag(RemindersV3Priority?.some(priority))
            }
          }
          Picker("List", selection: $listID) {
            ForEach(writableLists) { list in
              Text(list.title).tag(list.id)
            }
          }
        }
        if !message.isEmpty { Text(message) }
      }
      .navigationTitle(reminder == nil ? "New Reminder" : "Edit Reminder")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Save", action: saveButtonTapped)
            .disabled(
              title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || !canWriteSelectedList
            )
        }
      }
      .task(id: userID) { await observeLists() }
    }

    private func observeLists() async {
      do {
        try await $lists.task(RemindersV3List.visible(to: userID))
      } catch is CancellationError {
      } catch {
        message = String(describing: error)
        record(error: error, event: "reminder-form-query.failed")
      }
    }

    private var writableLists: [RemindersV3List] {
      lists.filter { $0.canWrite(as: userID) }
    }

    private var canWriteSelectedList: Bool {
      writableLists.contains { $0.id == listID }
    }

    private func saveButtonTapped() {
      let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !cleanTitle.isEmpty else { return }
      let tags = selectedTags()
      let dueDate = hasDueDate ? dueDate : nil
      let message: any InstantMessage
      let reminderID: InstantID<RemindersV3Reminder>
      if let reminder {
        reminderID = reminder.id
        message = UpdateRemindersV3Reminder(
          reminderID: reminder.id,
          listID: listID,
          title: cleanTitle,
          notes: notes,
          isFlagged: isFlagged,
          dueDate: dueDate,
          priority: priority,
          existingTagIDs: reminder.tags.map(\.id),
          tagIDs: tags.map(\.id),
          tagTitles: Dictionary(uniqueKeysWithValues: tags.map { ($0.id, $0.title) })
        )
      } else {
        reminderID = InstantID(rawValue: uuid().uuidString.lowercased())
        let position = lists.first(where: { $0.id == listID })?.reminders.count ?? 0
        message = CreateRemindersV3Reminder(
          reminderID: reminderID,
          listID: listID,
          title: cleanTitle,
          notes: notes,
          isFlagged: isFlagged,
          dueDate: dueDate,
          priority: priority,
          position: position,
          createdAt: now,
          tagIDs: tags.map(\.id),
          tagTitles: Dictionary(uniqueKeysWithValues: tags.map { ($0.id, $0.title) })
        )
      }
      record(
        event: "reminder-form-save.requested",
        metadata: ["reminderID": reminderID.rawValue]
      )
      db.send(
        message,
        onOptimisticCommit: { _ in
          record(
            .notice,
            event: "reminder-form-save.optimistic-commit",
            metadata: ["reminderID": reminderID.rawValue]
          )
          dismiss()
        },
        onServerAccepted: { _ in
          record(
            .notice,
            event: "reminder-form-save.server-accepted",
            metadata: ["reminderID": reminderID.rawValue]
          )
        },
        onFailure: { error in
          self.message = error.recoveryMessage
          record(
            error: error,
            event: "reminder-form-save.failed",
            metadata: ["reminderID": reminderID.rawValue]
          )
        }
      )
    }

    private func selectedTags() -> [RemindersV3Tag] {
      var existing: [String: RemindersV3Tag] = [:]
      for tag in lists.flatMap(\.reminders).flatMap(\.tags) {
        existing[tag.title.lowercased()] = tag
      }
      var seen: Set<String> = []
      return tagText.split(separator: ",").compactMap { rawTitle in
        var title = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if title.hasPrefix("#") { title.removeFirst() }
        let normalized = title.lowercased()
        guard !normalized.isEmpty, seen.insert(normalized).inserted else { return nil }
        return existing[normalized]
          ?? RemindersV3Tag(
            id: InstantID(rawValue: uuid().uuidString.lowercased()),
            title: normalized
          )
      }
    }

    private func record(
      _ level: InstantDiagnosticLevel = .info,
      event: String,
      metadata: [String: String] = [:]
    ) {
      InstantDiagnostics.shared.record(
        level,
        subsystem: "reminders-v3",
        category: "mutation",
        event: event,
        message: "The reminder form changed persisted state.",
        metadata: metadata
      )
    }

    private func record(
      error: Error,
      event: String,
      metadata: [String: String] = [:]
    ) {
      InstantDiagnostics.shared.record(
        error: error,
        subsystem: "reminders-v3",
        category: "mutation",
        event: event,
        message: "The reminder form operation failed.",
        metadata: metadata
      )
    }
  }

  @MainActor
  @available(iOS 17.0, macOS 14.0, *)
  struct RemindersV3ListEditorScreen: View {
    @Dependency(\.defaultInstantSwiftData) private var db
    @Dependency(\.uuid) private var uuid
    @Environment(\.dismiss) private var dismiss

    @State private var color: String
    @State private var coverFileID: String?
    @State private var coverImageData: Data?
    @State private var confirmsDelete = false
    @State private var isSaving = false
    @State private var message = ""
    @State private var pendingCoverImageData: Data?
    #if canImport(PhotosUI)
      @State private var photosPickerItem: PhotosPickerItem?
    #endif
    @State private var selectedColor: Color
    @State private var title: String

    let list: RemindersV3List

    init(list: RemindersV3List) {
      self.list = list
      title = list.title
      color = list.color
      coverFileID = list.coverFileID
      selectedColor = Color(hex: list.color)
    }

    var body: some View {
      Form {
        Section("List") {
          TextField("List name", text: $title)
          ColorPicker("Color", selection: $selectedColor, supportsOpacity: false)
          ScrollView(.horizontal) {
            HStack {
              ForEach(Self.colors, id: \.self) { color in
                Button {
                  self.color = color
                  selectedColor = Color(hex: color)
                } label: {
                  Circle()
                    .fill(Color(hex: color))
                    .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Use color \(color)")
              }
            }
          }
        }
        Section("Cover Photo") {
          RemindersV3CoverImageView(data: coverImageData, height: 150)
          HStack {
            #if canImport(PhotosUI)
              PhotosPicker(selection: $photosPickerItem, matching: .images) {
                Label("Choose Photo", systemImage: "photo")
              }
            #endif
            if coverImageData != nil || coverFileID != nil {
              Button("Remove Photo", role: .destructive) {
                coverImageData = nil
                coverFileID = nil
                pendingCoverImageData = nil
              }
            }
          }
        }
        Section {
          Button("Delete List", role: .destructive) { confirmsDelete = true }
        }
        if !message.isEmpty { Text(message) }
      }
      .navigationTitle("List Details")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Save") { Task { await saveButtonTapped() } }
            .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
      }
      .disabled(isSaving)
      .confirmationDialog(
        "Delete \(list.title)?",
        isPresented: $confirmsDelete,
        titleVisibility: .visible
      ) {
        Button("Delete List", role: .destructive, action: deleteButtonTapped)
      } message: {
        Text("This also deletes every reminder in the list.")
      }
      .task(id: list.coverFileID) {
        await loadCoverImage()
      }
      #if canImport(PhotosUI)
        .onChange(of: photosPickerItem) { _, item in
          Task { await photosPickerItemChanged(item) }
        }
      #endif
    }

    private func saveButtonTapped() async {
      isSaving = true
      defer { isSaving = false }
      do {
        let nextCoverFileID = try await uploadPendingCoverImage()
        let nextColor = selectedColor.hexString(fallback: color)
        db.send(
          UpdateRemindersV3List(
            listID: list.id,
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            color: nextColor,
            coverFileID: nextCoverFileID
          ),
          onOptimisticCommit: { _ in dismiss() },
          onFailure: handleFailure
        )
      } catch {
        handleFailure(error)
      }
    }

    private func deleteButtonTapped() {
      db.send(
        DeleteRemindersV3List(listID: list.id),
        onOptimisticCommit: { _ in dismiss() },
        onFailure: handleFailure
      )
    }

    private func handleFailure(_ error: Error) {
      if let error = error as? InstantError {
        message = error.recoveryMessage
      } else {
        message = String(describing: error)
      }
      InstantDiagnostics.shared.record(
        error: error,
        subsystem: "reminders-v3",
        category: "mutation",
        event: "list-editor.failed",
        message: "A list-editor mutation failed.",
        metadata: ["listID": list.id.rawValue]
      )
    }

    private func loadCoverImage() async {
      guard let coverFileID = list.coverFileID else {
        coverImageData = nil
        return
      }
      do {
        coverImageData = try await db.storedFileContents(id: coverFileID).data
      } catch {
        handleFailure(error)
      }
    }

    private func uploadPendingCoverImage() async throws -> String? {
      guard let pendingCoverImageData else { return coverFileID }
      let sourceURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("reminders-cover-\(uuid().uuidString.lowercased()).jpg")
      try pendingCoverImageData.write(to: sourceURL, options: .atomic)
      defer { try? FileManager.default.removeItem(at: sourceURL) }
      let file = try await db.uploadFile(
        from: sourceURL,
        name: "reminders-cover-\(list.id.rawValue).jpg",
        contentType: "image/jpeg"
      )
      return file.id
    }

    #if canImport(PhotosUI)
      private func photosPickerItemChanged(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        do {
          if let data = try await item.loadTransferable(type: Data.self),
            let optimized = remindersV3OptimizedJPEGData(from: data)
          {
            coverImageData = optimized
            pendingCoverImageData = optimized
            coverFileID = nil
          }
          photosPickerItem = nil
        } catch {
          handleFailure(error)
        }
      }
    #endif

    private static let colors = ["#4a99ef", "#ff3b30", "#ff9500", "#34c759", "#af52de"]
  }

  struct RemindersV3CoverImageView: View {
    let data: Data?
    var height: CGFloat

    var body: some View {
      Group {
        if let data, let image = remindersV3Image(from: data) {
          image
            .resizable()
            .scaledToFill()
        } else {
          Rectangle()
            .fill(Color.secondary.opacity(0.12))
            .overlay {
              Image(systemName: "photo")
                .font(.title2)
                .foregroundStyle(.secondary)
            }
        }
      }
      .frame(height: height)
      .clipShape(RoundedRectangle(cornerRadius: 8))
    }
  }

  func remindersV3Image(from data: Data) -> Image? {
    #if canImport(UIKit)
      guard let image = UIImage(data: data) else { return nil }
      return Image(uiImage: image)
    #elseif canImport(AppKit)
      guard let image = NSImage(data: data) else { return nil }
      return Image(nsImage: image)
    #else
      _ = data
      return nil
    #endif
  }

  func remindersV3OptimizedJPEGData(from data: Data) -> Data? {
    #if canImport(UIKit)
      guard let image = UIImage(data: data) else { return nil }
      let maximum: CGFloat = 1_000
      let scale = min(1, maximum / max(image.size.width, image.size.height))
      let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
      UIGraphicsBeginImageContextWithOptions(size, true, 1)
      image.draw(in: CGRect(origin: .zero, size: size))
      let resized = UIGraphicsGetImageFromCurrentImageContext()
      UIGraphicsEndImageContext()
      return resized?.jpegData(compressionQuality: 0.82)
    #elseif canImport(AppKit)
      guard let image = NSImage(data: data),
        let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
      else { return nil }
      let rep = NSBitmapImageRep(cgImage: cgImage)
      return rep.representation(using: .jpeg, properties: [.compressionFactor: 0.82])
    #else
      return data
    #endif
  }

  extension Color {
    func hexString(fallback: String) -> String {
      #if canImport(UIKit)
        let color = UIColor(self)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        guard color.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else {
          return fallback
        }
        return String(
          format: "#%02x%02x%02x",
          Int(red * 255),
          Int(green * 255),
          Int(blue * 255)
        )
      #elseif canImport(AppKit)
        guard let color = NSColor(self).usingColorSpace(.sRGB) else { return fallback }
        return String(
          format: "#%02x%02x%02x",
          Int(color.redComponent * 255),
          Int(color.greenComponent * 255),
          Int(color.blueComponent * 255)
        )
      #else
        return fallback
      #endif
    }
  }

  @MainActor
  @available(iOS 17.0, macOS 14.0, *)
  struct RemindersV3ReminderRow: View {
    let reminder: RemindersV3Reminder
    let listTitle: String?
    let searchSummary: String?
    let isEditable: Bool
    let onToggle: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    init(
      reminder: RemindersV3Reminder,
      listTitle: String?,
      searchSummary: String? = nil,
      isEditable: Bool = true,
      onToggle: @escaping () -> Void,
      onEdit: @escaping () -> Void,
      onDelete: @escaping () -> Void
    ) {
      self.reminder = reminder
      self.listTitle = listTitle
      self.searchSummary = searchSummary
      self.isEditable = isEditable
      self.onToggle = onToggle
      self.onEdit = onEdit
      self.onDelete = onDelete
    }

    var body: some View {
      HStack(alignment: .top) {
        Button(action: onToggle) {
          Image(systemName: reminder.isCompleted ? "checkmark.circle.fill" : "circle")
        }
        .buttonStyle(.plain)
        .disabled(!isEditable)
        .accessibilityLabel(
          reminder.isCompleted
            ? "Mark \(reminder.title) incomplete"
            : "Mark \(reminder.title) complete"
        )
        Button(action: onEdit) {
          VStack(alignment: .leading, spacing: 3) {
            HStack {
              Text(reminder.title)
                .strikethrough(reminder.isCompleted)
              if reminder.isFlagged { Image(systemName: "flag.fill").foregroundStyle(.orange) }
              if let priority = reminder.priority {
                Text(priority.marker).foregroundStyle(.red)
              }
            }
            if !reminder.notes.isEmpty {
              Text(reminder.notes).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            if let searchSummary {
              Text(searchSummary).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            HStack(spacing: 6) {
              if let listTitle { Text(listTitle) }
              if let dueDate = reminder.dueDate {
                Text(dueDate, format: .dateTime.month(.abbreviated).day().hour().minute())
              }
              ForEach(reminder.tags) { tag in Text("#\(tag.title)") }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
          }
          .frame(maxWidth: .infinity, alignment: .leading)
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEditable)
        .accessibilityLabel("Edit \(reminder.title)")
        Button(role: .destructive, action: onDelete) {
          Image(systemName: "trash")
        }
        .buttonStyle(.plain)
        .disabled(!isEditable)
        .accessibilityLabel("Delete \(reminder.title)")
      }
    }
  }

  extension RemindersV3Priority {
    fileprivate var title: String {
      switch self {
      case .low: "Low"
      case .medium: "Medium"
      case .high: "High"
      }
    }

    fileprivate var marker: String {
      String(repeating: "!", count: rawValue)
    }
  }
#endif
