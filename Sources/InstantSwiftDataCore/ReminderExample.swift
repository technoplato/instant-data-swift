import Foundation

public enum ReminderPriority: String, CaseIterable, Codable, Hashable, Sendable {
  case low
  case medium
  case high

  public var rank: Int {
    switch self {
    case .low:
      return 1
    case .medium:
      return 2
    case .high:
      return 3
    }
  }

  public init?(rank: Int) {
    switch rank {
    case 1:
      self = .low
    case 2:
      self = .medium
    case 3:
      self = .high
    default:
      return nil
    }
  }
}

public struct RemindersListRecord: Hashable, Codable, Sendable, Identifiable {
  public var id: String
  public var title: String
  public var color: String
  public var position: Int
  public var createdAt: InstantTimestamp

  public init(
    id: String,
    title: String,
    color: String,
    position: Int,
    createdAt: InstantTimestamp
  ) {
    self.id = id
    self.title = title
    self.color = color
    self.position = position
    self.createdAt = createdAt
  }
}

public struct ReminderRecord: Hashable, Codable, Sendable, Identifiable {
  public var id: String
  public var remindersListID: String
  public var title: String
  public var notes: String
  public var isCompleted: Bool
  public var isFlagged: Bool
  public var dueDate: InstantTimestamp?
  public var priority: ReminderPriority?
  public var position: Int
  public var createdAt: InstantTimestamp

  public init(
    id: String,
    remindersListID: String,
    title: String,
    notes: String,
    isCompleted: Bool,
    isFlagged: Bool,
    dueDate: InstantTimestamp? = nil,
    priority: ReminderPriority? = nil,
    position: Int,
    createdAt: InstantTimestamp
  ) {
    self.id = id
    self.remindersListID = remindersListID
    self.title = title
    self.notes = notes
    self.isCompleted = isCompleted
    self.isFlagged = isFlagged
    self.dueDate = dueDate
    self.priority = priority
    self.position = position
    self.createdAt = createdAt
  }
}

public struct ReminderDraft: Hashable, Codable, Sendable, Identifiable {
  public var id: String?
  public var listID: String
  public var title: String
  public var notes: String
  public var isFlagged: Bool
  public var dueDate: InstantTimestamp?
  public var priority: ReminderPriority?
  public var position: Int

  public init(
    id: String? = nil,
    listID: String,
    title: String = "",
    notes: String = "",
    isFlagged: Bool = false,
    dueDate: InstantTimestamp? = nil,
    priority: ReminderPriority? = nil,
    position: Int = 0
  ) {
    self.id = id
    self.listID = listID
    self.title = title
    self.notes = notes
    self.isFlagged = isFlagged
    self.dueDate = dueDate
    self.priority = priority
    self.position = position
  }

  public init(_ reminder: ReminderRecord) {
    self.init(
      id: reminder.id,
      listID: reminder.remindersListID,
      title: reminder.title,
      notes: reminder.notes,
      isFlagged: reminder.isFlagged,
      dueDate: reminder.dueDate,
      priority: reminder.priority,
      position: reminder.position
    )
  }

  public var isDateSet: Bool {
    dueDate != nil
  }

  public mutating func setDateEnabled(
    _ isEnabled: Bool,
    defaultDueDate: InstantTimestamp
  ) {
    dueDate = isEnabled ? (dueDate ?? defaultDueDate) : nil
  }
}

public struct ReminderTagRecord: Hashable, Codable, Sendable, Identifiable {
  public var id: String
  public var title: String

  public init(id: String, title: String) {
    self.id = id
    self.title = title
  }
}

public struct ReminderFormSave: Hashable, Sendable {
  public var reminderID: String
  public var operations: [InstantTripleOperation]
  public var selectedTags: [ReminderTagRecord]

  public init(
    reminderID: String,
    operations: [InstantTripleOperation],
    selectedTags: [ReminderTagRecord]
  ) {
    self.reminderID = reminderID
    self.operations = operations
    self.selectedTags = selectedTags
  }
}

public struct ReminderFormModel: Hashable, Sendable {
  public var isDismissed: Bool
  public var reminder: ReminderDraft
  public var selectedTags: [ReminderTagRecord]
  public private(set) var existingTagIDs: [String]

  public init(
    reminder: ReminderDraft,
    selectedTags: [ReminderTagRecord] = [],
    existingTagIDs: [String] = []
  ) {
    self.reminder = reminder
    self.selectedTags = Self.uniqueTags(selectedTags)
    self.existingTagIDs = Self.unique(existingTagIDs)
    self.isDismissed = false
  }

  public init(
    reminder: ReminderRecord,
    selectedTags: [ReminderTagRecord] = []
  ) {
    self.init(
      reminder: ReminderDraft(reminder),
      selectedTags: selectedTags,
      existingTagIDs: selectedTags.map(\.id)
    )
  }

  public mutating func cancelButtonTapped() {
    isDismissed = true
  }

  public mutating func saveButtonTapped(
    newReminderID: String,
    updatedAt: InstantTimestamp,
    transactionID: String
  ) -> ReminderFormSave {
    selectedTags = Self.uniqueTags(selectedTags)

    let isNew = reminder.id == nil
    let reminderID = reminder.id ?? newReminderID
    let reminderOperations =
      isNew
      ? ReminderExample.createReminderOperations(
        id: reminderID,
        listID: reminder.listID,
        title: reminder.title,
        notes: reminder.notes,
        isFlagged: reminder.isFlagged,
        dueDate: reminder.dueDate,
        priority: reminder.priority,
        position: reminder.position,
        createdAt: updatedAt,
        transactionID: transactionID
      )
      : ReminderExample.updateReminderDetailsOperations(
        id: reminderID,
        listID: reminder.listID,
        title: reminder.title,
        notes: reminder.notes,
        isFlagged: reminder.isFlagged,
        dueDate: reminder.dueDate,
        priority: reminder.priority,
        updatedAt: updatedAt,
        transactionID: transactionID
      )
    let operations =
      reminderOperations
      + ReminderExample.replaceReminderTagsOperations(
        reminderID: reminderID,
        listID: reminder.listID,
        existingTagIDs: existingTagIDs,
        selectedTags: selectedTags,
        updatedAt: updatedAt,
        transactionID: transactionID,
        requiresExistingReminder: !isNew
      )
    return ReminderFormSave(
      reminderID: reminderID,
      operations: operations,
      selectedTags: selectedTags
    )
  }

  public mutating func commit(_ save: ReminderFormSave) {
    reminder.id = save.reminderID
    selectedTags = save.selectedTags
    existingTagIDs = save.selectedTags.map(\.id)
    isDismissed = true
  }

  private static func uniqueTags(_ tags: [ReminderTagRecord]) -> [ReminderTagRecord] {
    var seen: Set<String> = []
    return tags.filter { tag in
      seen.insert(tag.id).inserted
    }
  }

  private static func unique(_ ids: [String]) -> [String] {
    var seen: Set<String> = []
    return ids.filter { seen.insert($0).inserted }
  }
}

public struct ReminderTagLinkRecord: Hashable, Codable, Sendable, Identifiable {
  public var id: String { "\(reminderID)#\(tagID)" }
  public var reminderID: String
  public var tagID: String

  public init(reminderID: String, tagID: String) {
    self.reminderID = reminderID
    self.tagID = tagID
  }
}

public struct RemindersListSummary: Hashable, Codable, Sendable, Identifiable {
  public var id: String { list.id }
  public var list: RemindersListRecord
  public var reminderCount: Int

  public init(list: RemindersListRecord, reminderCount: Int) {
    self.list = list
    self.reminderCount = reminderCount
  }
}

public struct RemindersStats: Hashable, Codable, Sendable {
  public var allCount: Int
  public var completedCount: Int
  public var flaggedCount: Int
  public var scheduledCount: Int
  public var todayCount: Int

  public init(
    allCount: Int = 0,
    completedCount: Int = 0,
    flaggedCount: Int = 0,
    scheduledCount: Int = 0,
    todayCount: Int = 0
  ) {
    self.allCount = allCount
    self.completedCount = completedCount
    self.flaggedCount = flaggedCount
    self.scheduledCount = scheduledCount
    self.todayCount = todayCount
  }
}

public struct SearchRemindersResults: Hashable, Codable, Sendable {
  public var completedCount: Int
  public var rows: [SearchRemindersRow]

  public init(completedCount: Int = 0, rows: [SearchRemindersRow] = []) {
    self.completedCount = completedCount
    self.rows = rows
  }
}

public struct SearchRemindersRow: Hashable, Codable, Sendable, Identifiable {
  public var id: String { reminder.id }
  public var isPastDue: Bool
  public var notes: String
  public var reminder: ReminderRecord
  public var remindersList: RemindersListRecord
  public var tags: String
  public var title: String

  public init(
    isPastDue: Bool,
    notes: String,
    reminder: ReminderRecord,
    remindersList: RemindersListRecord,
    tags: String,
    title: String
  ) {
    self.isPastDue = isPastDue
    self.notes = notes
    self.reminder = reminder
    self.remindersList = remindersList
    self.tags = tags
    self.title = title
  }
}

public struct SearchRemindersModel: Sendable {
  public struct Token: Hashable, Codable, Sendable, Identifiable {
    public enum Kind: String, Codable, Sendable {
      case near
      case tag
    }

    public var id: Self { self }
    public var kind: Kind
    public var rawValue: String

    public init(kind: Kind, rawValue: String) {
      self.kind = kind
      self.rawValue = rawValue
    }
  }

  public var searchText: String
  public var searchTokens: [Token]
  public var showCompletedInSearchResults: Bool
  public private(set) var searchResults: SearchRemindersResults
  public private(set) var tagSuggestions: [ReminderTagRecord]

  private let runtime: InstantRuntime
  private let now: @Sendable () -> InstantTimestamp

  public init(
    runtime: InstantRuntime,
    searchText: String = "",
    searchTokens: [Token] = [],
    showCompletedInSearchResults: Bool = false,
    now: @escaping @Sendable () -> InstantTimestamp
  ) {
    self.runtime = runtime
    self.searchText = searchText
    self.searchTokens = searchTokens
    self.showCompletedInSearchResults = showCompletedInSearchResults
    self.searchResults = SearchRemindersResults()
    self.tagSuggestions = []
    self.now = now
  }

  public var isSearching: Bool {
    !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      || !searchTokens.isEmpty
  }

  public mutating func load() async throws {
    if searchText.hasSuffix("\t") {
      let tokenText = String(searchText.dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
      if !tokenText.isEmpty {
        searchTokens.append(Token(kind: .near, rawValue: tokenText))
      }
      searchText = ""
    }

    let trimmedText = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    let context = try await ReminderExample.modelContext(runtime: runtime)

    if trimmedText.hasPrefix("#") {
      tagSuggestions = ReminderExample.tagSuggestions(
        in: Array(context.tagsByID.values),
        matching: trimmedText,
        excluding: searchTokens.compactMap { token in
          token.kind == .tag ? token.rawValue : nil
        }
      )
      if searchTokens.isEmpty {
        searchResults = SearchRemindersResults()
      }
      return
    }

    tagSuggestions = []

    guard isSearching else {
      showCompletedInSearchResults = false
      searchResults = SearchRemindersResults()
      return
    }

    let tagIDs = ReminderExample.searchTokenTagIDs(searchTokens, context: context)
    let nearTexts = searchTokens.compactMap { token in
      token.kind == .near ? token.rawValue : nil
    }
    let highlightText = ReminderExample.searchHighlightText(
      searchText: trimmedText,
      nearTexts: nearTexts
    )
    let tagHighlightText =
      trimmedText.isEmpty
      ? searchTokens.first { $0.kind == .tag }?.rawValue ?? ""
      : trimmedText
    let matchingReminders = try ReminderExample.decodeReminders(
      try await runtime.query(
        ReminderExample.remindersSearchQuery(
          text: trimmedText,
          tagIDs: tagIDs,
          nearTexts: nearTexts,
          includeCompleted: true
        )
      )
    )
    let completedCount = matchingReminders.filter(\.isCompleted).count
    let visibleReminders = matchingReminders
      .filter { showCompletedInSearchResults || !$0.isCompleted }
      .sorted { lhs, rhs in
        ReminderExample.searchSortKey(lhs) < ReminderExample.searchSortKey(rhs)
      }
    searchResults = SearchRemindersResults(
      completedCount: completedCount,
      rows: visibleReminders.compactMap { reminder in
        guard let list = context.listsByID[reminder.remindersListID] else { return nil }
        return SearchRemindersRow(
          isPastDue: ReminderExample.isPastDue(reminder, now: now()),
          notes: ReminderExample.searchSnippet(reminder.notes, matching: highlightText),
          reminder: reminder,
          remindersList: list,
          tags: ReminderExample.highlightedTags(
            context.tagsByReminderID[reminder.id] ?? [],
            matching: tagHighlightText
          ),
          title: ReminderExample.highlight(reminder.title, matching: highlightText)
        )
      }
    )
  }

  public mutating func tagButtonTapped(_ tag: ReminderTagRecord) {
    guard !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
    searchTokens.append(Token(kind: .tag, rawValue: tag.title))
    searchText = ""
    tagSuggestions = []
  }

  public mutating func showCompletedButtonTapped() async throws {
    showCompletedInSearchResults.toggle()
    try await load()
  }

  public mutating func deleteCompletedReminders(
    monthsAgo: Int? = nil,
    updatedAt: InstantTimestamp,
    transactionID: String
  ) async throws {
    let trimmedText = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard isSearching else { return }
    let context = try await ReminderExample.modelContext(runtime: runtime)
    let tagIDs = ReminderExample.searchTokenTagIDs(searchTokens, context: context)
    let nearTexts = searchTokens.compactMap { token in
      token.kind == .near ? token.rawValue : nil
    }
    let matchingReminders = try ReminderExample.decodeReminders(
      try await runtime.query(
        ReminderExample.remindersSearchQuery(
          text: trimmedText,
          tagIDs: tagIDs,
          nearTexts: nearTexts,
          includeCompleted: true
        )
      )
    )
    let cutoff = monthsAgo.flatMap { ReminderExample.monthsAgoCutoff($0, from: now()) }
    if monthsAgo != nil, cutoff == nil {
      try await load()
      return
    }
    let completedReminders = matchingReminders
      .filter(\.isCompleted)
      .filter { reminder in
        guard let cutoff else { return true }
        guard let dueDate = reminder.dueDate else { return false }
        return dueDate < cutoff
      }
      .map { (id: $0.id, listID: $0.remindersListID) }
    guard !completedReminders.isEmpty else {
      try await load()
      return
    }
    _ = try await runtime.transact(
      InstantStoreTransaction(
        id: transactionID,
        operations: ReminderExample.deleteCompletedReminderOperations(
          reminders: completedReminders,
          updatedAt: updatedAt,
          transactionID: transactionID
        )
      )
    )
    try await load()
  }
}

public enum RemindersDetailOrdering: String, CaseIterable, Codable, Sendable {
  case dueDate
  case manual
  case priority
  case title
}

public enum RemindersDetailType: Hashable, Codable, Sendable {
  case all
  case completed
  case flagged
  case remindersList(RemindersListRecord)
  case scheduled
  case tags([ReminderTagRecord])
  case today
}

public struct RemindersDetailRow: Hashable, Codable, Sendable, Identifiable {
  public var id: String { reminder.id }
  public var reminder: ReminderRecord
  public var remindersList: RemindersListRecord
  public var isPastDue: Bool
  public var notes: String
  public var tags: String

  public init(
    reminder: ReminderRecord,
    remindersList: RemindersListRecord,
    isPastDue: Bool,
    notes: String,
    tags: String
  ) {
    self.reminder = reminder
    self.remindersList = remindersList
    self.isPastDue = isPastDue
    self.notes = notes
    self.tags = tags
  }
}

public struct RemindersDetailModel: Sendable {
  public let detailType: RemindersDetailType
  public var ordering: RemindersDetailOrdering
  public var showCompleted: Bool
  public private(set) var reminderRows: [RemindersDetailRow]

  private let runtime: InstantRuntime
  private let now: @Sendable () -> InstantTimestamp

  public init(
    detailType: RemindersDetailType,
    runtime: InstantRuntime,
    ordering: RemindersDetailOrdering = .dueDate,
    now: @escaping @Sendable () -> InstantTimestamp
  ) {
    self.detailType = detailType
    self.runtime = runtime
    self.ordering = ordering
    self.showCompleted = detailType == .completed
    self.reminderRows = []
    self.now = now
  }

  public mutating func load() async throws {
    let context = try await ReminderExample.modelContext(runtime: runtime)
    let reminders = context.reminders
      .filter { ReminderExample.matchesDetailType($0, detailType, context: context, now: now()) }
      .filter { showCompleted || !$0.isCompleted }
      .sorted { lhs, rhs in
        ReminderExample.detailSortKey(lhs, ordering: ordering) < ReminderExample.detailSortKey(rhs, ordering: ordering)
      }
    reminderRows = reminders.compactMap { reminder in
      guard let list = context.listsByID[reminder.remindersListID] else { return nil }
      return RemindersDetailRow(
        reminder: reminder,
        remindersList: list,
        isPastDue: ReminderExample.isPastDue(reminder, now: now()),
        notes: ReminderExample.inlineNotes(reminder.notes),
        tags: ReminderExample.tagText(context.tagsByReminderID[reminder.id] ?? [])
      )
    }
  }

  public mutating func orderingButtonTapped(_ ordering: RemindersDetailOrdering) async throws {
    self.ordering = ordering
    try await load()
  }

  public mutating func move(
    fromOffsets source: IndexSet,
    toOffset destination: Int,
    updatedAt: InstantTimestamp,
    transactionID: String
  ) async throws {
    if reminderRows.isEmpty {
      try await load()
    }
    var rows = reminderRows
    ReminderExample.moveRows(&rows, fromOffsets: source, toOffset: destination)
    let operations = rows.enumerated().flatMap { offset, row in
      ReminderExample.updateReminderPositionOperations(
        id: row.reminder.id,
        listID: row.reminder.remindersListID,
        position: offset,
        updatedAt: updatedAt,
        transactionID: transactionID
      )
    }
    guard !operations.isEmpty else { return }
    _ = try await runtime.transact(
      InstantStoreTransaction(id: transactionID, operations: operations)
    )
    ordering = .manual
    try await load()
  }

  public mutating func showCompletedButtonTapped() async throws {
    showCompleted.toggle()
    try await load()
  }
}

public struct RemindersListSeedRecord: Hashable, Codable, Sendable {
  public var localIDName: String
  public var title: String
  public var color: String
  public var position: Int
  public var createdAtOffsetMilliseconds: Int64

  public init(
    localIDName: String,
    title: String,
    color: String,
    position: Int,
    createdAtOffsetMilliseconds: Int64
  ) {
    self.localIDName = localIDName
    self.title = title
    self.color = color
    self.position = position
    self.createdAtOffsetMilliseconds = createdAtOffsetMilliseconds
  }
}

public struct ReminderSeedRecord: Hashable, Codable, Sendable {
  public var localIDName: String
  public var listLocalIDName: String
  public var title: String
  public var notes: String
  public var isCompleted: Bool
  public var isFlagged: Bool
  public var dueDateOffsetMilliseconds: Int64?
  public var priority: ReminderPriority?
  public var position: Int
  public var createdAtOffsetMilliseconds: Int64
  public var tagTitles: [String]

  public init(
    localIDName: String,
    listLocalIDName: String,
    title: String,
    notes: String,
    isCompleted: Bool,
    isFlagged: Bool,
    dueDateOffsetMilliseconds: Int64? = nil,
    priority: ReminderPriority? = nil,
    position: Int,
    createdAtOffsetMilliseconds: Int64,
    tagTitles: [String] = []
  ) {
    self.localIDName = localIDName
    self.listLocalIDName = listLocalIDName
    self.title = title
    self.notes = notes
    self.isCompleted = isCompleted
    self.isFlagged = isFlagged
    self.dueDateOffsetMilliseconds = dueDateOffsetMilliseconds
    self.priority = priority
    self.position = position
    self.createdAtOffsetMilliseconds = createdAtOffsetMilliseconds
    self.tagTitles = tagTitles
  }
}

public struct ReminderTagSeedRecord: Hashable, Codable, Sendable {
  public var title: String

  public init(title: String) {
    self.title = title
  }
}

public enum ReminderExample {
  public static let listsNamespace = "remindersLists"
  public static let remindersNamespace = "reminders"
  public static let tagsNamespace = "tags"
  public static let defaultListColor = "#4a99ef"

  public static let seedLists: [RemindersListSeedRecord] = [
    RemindersListSeedRecord(
      localIDName: "examples.reminders.seed.personal",
      title: "Personal",
      color: defaultListColor,
      position: 0,
      createdAtOffsetMilliseconds: 0
    )
  ]

  public static let seedReminders: [ReminderSeedRecord] = [
    ReminderSeedRecord(
      localIDName: "examples.reminders.seed.groceries",
      listLocalIDName: "examples.reminders.seed.personal",
      title: "Groceries",
      notes: "Milk\nEggs\nApples",
      isCompleted: false,
      isFlagged: false,
      dueDateOffsetMilliseconds: 24 * 60 * 60 * 1000,
      priority: .medium,
      position: 0,
      createdAtOffsetMilliseconds: 1,
      tagTitles: ["shopping"]
    ),
    ReminderSeedRecord(
      localIDName: "examples.reminders.seed.haircut",
      listLocalIDName: "examples.reminders.seed.personal",
      title: "Haircut",
      notes: "",
      isCompleted: false,
      isFlagged: true,
      dueDateOffsetMilliseconds: 3 * 24 * 60 * 60 * 1000,
      priority: .high,
      position: 1,
      createdAtOffsetMilliseconds: 2,
      tagTitles: ["personal"]
    ),
  ]

  public static let seedTags: [ReminderTagSeedRecord] = [
    ReminderTagSeedRecord(title: "personal"),
    ReminderTagSeedRecord(title: "shopping"),
  ]

  public static let attributes: [InstantAttribute] = [
    .primaryKey(namespace: listsNamespace),
    InstantAttribute(
      id: "remindersLists/title",
      namespace: listsNamespace,
      name: "title",
      valueType: .string,
      isIndexed: true
    ),
    InstantAttribute(
      id: "remindersLists/color",
      namespace: listsNamespace,
      name: "color",
      valueType: .string,
      isIndexed: true
    ),
    InstantAttribute(
      id: "remindersLists/position",
      namespace: listsNamespace,
      name: "position",
      valueType: .number,
      isIndexed: true
    ),
    InstantAttribute(
      id: "remindersLists/createdAt",
      namespace: listsNamespace,
      name: "createdAt",
      valueType: .date,
      isIndexed: true
    ),
    .primaryKey(namespace: remindersNamespace),
    InstantAttribute(
      id: "reminders/title",
      namespace: remindersNamespace,
      name: "title",
      valueType: .string,
      isIndexed: true
    ),
    InstantAttribute(
      id: "reminders/notes",
      namespace: remindersNamespace,
      name: "notes",
      valueType: .string,
      isIndexed: true
    ),
    InstantAttribute(
      id: "reminders/isCompleted",
      namespace: remindersNamespace,
      name: "isCompleted",
      valueType: .boolean,
      isIndexed: true
    ),
    InstantAttribute(
      id: "reminders/isFlagged",
      namespace: remindersNamespace,
      name: "isFlagged",
      valueType: .boolean,
      isIndexed: true
    ),
    InstantAttribute(
      id: "reminders/dueDate",
      namespace: remindersNamespace,
      name: "dueDate",
      valueType: .date,
      isRequired: false,
      isIndexed: true
    ),
    InstantAttribute(
      id: "reminders/priority",
      namespace: remindersNamespace,
      name: "priority",
      valueType: .number,
      isRequired: false,
      isIndexed: true
    ),
    InstantAttribute(
      id: "reminders/position",
      namespace: remindersNamespace,
      name: "position",
      valueType: .number,
      isIndexed: true
    ),
    InstantAttribute(
      id: "reminders/createdAt",
      namespace: remindersNamespace,
      name: "createdAt",
      valueType: .date,
      isIndexed: true
    ),
    .primaryKey(namespace: tagsNamespace),
    InstantAttribute(
      id: "tags/title",
      namespace: tagsNamespace,
      name: "title",
      valueType: .string,
      isIndexed: true,
      isUnique: true
    ),
    InstantAttribute(
      id: "reminders/list",
      namespace: remindersNamespace,
      name: "list",
      valueType: .ref,
      isRequired: true,
      isIndexed: true,
      forwardIdentity: "reminders/list",
      reverseIdentity: "remindersLists/reminders",
      linkNamespace: listsNamespace,
      onDelete: .cascade
    ),
    InstantAttribute(
      id: "reminders/tags",
      namespace: remindersNamespace,
      name: "tags",
      valueType: .ref,
      isRequired: false,
      cardinality: .many,
      isIndexed: true,
      forwardIdentity: "reminders/tags",
      reverseIdentity: "tags/reminders",
      linkNamespace: tagsNamespace
    ),
  ]

  public static let listsQuery = InstantQueryPlan(
    id: "examples.reminders.lists",
    namespace: listsNamespace,
    order: InstantQueryOrder("position", .ascending)
  )

  public static let remindersQuery = InstantQueryPlan(
    id: "examples.reminders.reminders",
    namespace: remindersNamespace,
    order: InstantQueryOrder("position", .ascending)
  )

  public static let tagsQuery = InstantQueryPlan(
    id: "examples.reminders.tags",
    namespace: tagsNamespace,
    order: InstantQueryOrder("title", .ascending)
  )

  public static func remindersForListQuery(_ listID: String) -> InstantQueryPlan {
    InstantQueryPlan(
      id: "examples.reminders.reminders.list-\(queryIDFragment(listID))",
      namespace: remindersNamespace,
      filters: [.equals(field: "list", value: .ref(listID))],
      order: InstantQueryOrder("position", .ascending)
    )
  }

  public static func remindersFilterQuery(
    listID: String? = nil,
    includeCompleted: Bool = false,
    flagged: Bool? = nil,
    scheduled: Bool = false,
    today: InstantTimestamp? = nil,
    priority: ReminderPriority? = nil
  ) -> InstantQueryPlan {
    var fragments: [String] = []
    var filters: [InstantQueryFilter] = []

    if let listID {
      fragments.append("list-\(queryIDFragment(listID))")
      filters.append(.equals(field: "list", value: .ref(listID)))
    }

    if !includeCompleted {
      fragments.append("incomplete")
      filters.append(.equals(field: "isCompleted", value: .bool(false)))
    }

    if let flagged {
      fragments.append("flagged-\(flagged)")
      filters.append(.equals(field: "isFlagged", value: .bool(flagged)))
    }

    if scheduled {
      fragments.append("scheduled")
      filters.append(.isNotNull(field: "dueDate"))
    }

    if let today {
      let range = dayRange(containing: today)
      fragments.append("today-\(timestampMilliseconds(for: range.start))")
      filters.append(
        .and([
          .greaterThanOrEqual(field: "dueDate", value: .date(range.start)),
          .lessThan(field: "dueDate", value: .date(range.end)),
        ])
      )
    }

    if let priority {
      fragments.append("priority-\(priority.rawValue)")
      filters.append(priorityFilter(priority))
    }

    return InstantQueryPlan(
      id: "examples.reminders.filter.\(fragments.isEmpty ? "all" : fragments.joined(separator: "."))",
      namespace: remindersNamespace,
      filters: filters,
      order: InstantQueryOrder("position", .ascending)
    )
  }

  public static func remindersSearchQuery(
    text: String,
    listID: String? = nil,
    tagID: String? = nil,
    tagIDs: [String] = [],
    nearTexts: [String] = [],
    includeCompleted: Bool = false,
    flagged: Bool? = nil,
    scheduled: Bool = false,
    today: InstantTimestamp? = nil,
    priority: ReminderPriority? = nil
  ) -> InstantQueryPlan {
    let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
    var fragments: [String] = []
    var filters: [InstantQueryFilter] = []

    if !trimmedText.isEmpty {
      fragments.append("text-\(queryIDFragment(trimmedText))")
      filters.append(searchTextFilter(trimmedText))
    }

    for nearText in nearTexts.map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) })
      where !nearText.isEmpty
    {
      fragments.append("near-\(queryIDFragment(nearText))")
      filters.append(searchTextFilter(nearText))
    }

    if let listID {
      fragments.append("list-\(queryIDFragment(listID))")
      filters.append(.equals(field: "list", value: .ref(listID)))
    }

    for tagID in Array(Set([tagID].compactMap(\.self) + tagIDs)).sorted() {
      fragments.append("tag-\(queryIDFragment(tagID))")
      filters.append(.equals(field: "tags", value: .ref(tagID)))
    }

    if let flagged {
      fragments.append("flagged-\(flagged)")
      filters.append(.equals(field: "isFlagged", value: .bool(flagged)))
    }

    if scheduled {
      fragments.append("scheduled")
      filters.append(.isNotNull(field: "dueDate"))
    }

    if let today {
      let range = dayRange(containing: today)
      fragments.append("today-\(timestampMilliseconds(for: range.start))")
      filters.append(
        .and([
          .greaterThanOrEqual(field: "dueDate", value: .date(range.start)),
          .lessThan(field: "dueDate", value: .date(range.end)),
        ])
      )
    }

    if let priority {
      fragments.append("priority-\(priority.rawValue)")
      filters.append(priorityFilter(priority))
    }

    if !includeCompleted {
      fragments.append("incomplete")
      filters.append(.equals(field: "isCompleted", value: .bool(false)))
    } else {
      fragments.append("all")
    }

    return InstantQueryPlan(
      id: "examples.reminders.search.\(fragments.isEmpty ? "all" : fragments.joined(separator: "."))",
      namespace: remindersNamespace,
      filters: filters,
      order: InstantQueryOrder("position", .ascending)
    )
  }

  public static func normalizedTagTitle(_ rawValue: String) -> String? {
    var value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
    if value.hasPrefix("#") {
      value.removeFirst()
    }
    let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    return normalized.isEmpty ? nil : normalized
  }

  public static func tagSuggestions(
    in tags: [ReminderTagRecord],
    matching searchText: String,
    excluding existingTagTitles: [String]
  ) -> [ReminderTagRecord] {
    let trimmedSearchText = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmedSearchText.hasPrefix("#") else { return [] }
    let prefix = normalizedTagTitle(String(trimmedSearchText.dropFirst())) ?? ""
    let existing = Set(existingTagTitles.compactMap(normalizedTagTitle))
    return tags
      .filter { tag in
        let normalizedTitle = normalizedTagTitle(tag.title) ?? tag.id
        return !existing.contains(normalizedTitle) && tag.title.lowercased().hasPrefix(prefix)
      }
      .sorted { ($0.title.lowercased(), $0.id) < ($1.title.lowercased(), $1.id) }
  }

  fileprivate static func searchHighlightText(
    searchText: String,
    nearTexts: [String]
  ) -> String {
    let trimmedSearchText = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    if !trimmedSearchText.isEmpty {
      return trimmedSearchText
    }
    return nearTexts
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .first { !$0.isEmpty } ?? ""
  }

  fileprivate static func searchTokenTagIDs(
    _ tokens: [SearchRemindersModel.Token],
    context: ModelContext
  ) -> [String] {
    let tagsByTitle = Dictionary(
      grouping: context.tagsByID.values,
      by: { normalizedTagTitle($0.title) ?? $0.title.lowercased() }
    )
    var seen: Set<String> = []
    return tokens.compactMap { token -> String? in
      guard token.kind == .tag else { return nil }
      let rawValue = token.rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
      let resolvedID =
        context.tagsByID[rawValue]?.id
        ?? normalizedTagTitle(rawValue).flatMap { normalized in
          tagsByTitle[normalized]?.sorted {
            ($0.title.lowercased(), $0.id) < ($1.title.lowercased(), $1.id)
          }.first?.id
        }
      guard let resolvedID, seen.insert(resolvedID).inserted else { return nil }
      return resolvedID
    }
  }

  fileprivate static func monthsAgoCutoff(
    _ monthsAgo: Int,
    from timestamp: InstantTimestamp
  ) -> InstantTimestamp? {
    guard monthsAgo >= 0 else { return nil }
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let date = Date(timeIntervalSince1970: Double(timestamp.milliseconds) / 1000)
    guard let cutoff = calendar.date(byAdding: .month, value: -monthsAgo, to: date) else {
      return nil
    }
    return InstantTimestamp(milliseconds: timestampMilliseconds(for: calendar.startOfDay(for: cutoff)))
  }

  public static func stats(
    for reminders: [ReminderRecord],
    today: InstantTimestamp
  ) -> RemindersStats {
    let range = dayRange(containing: today)
    let start = timestampMilliseconds(for: range.start)
    let end = timestampMilliseconds(for: range.end)
    let incompleteReminders = reminders.filter { !$0.isCompleted }
    return RemindersStats(
      allCount: incompleteReminders.count,
      completedCount: reminders.filter(\.isCompleted).count,
      flaggedCount: incompleteReminders.filter(\.isFlagged).count,
      scheduledCount: incompleteReminders.filter { $0.dueDate != nil }.count,
      todayCount: incompleteReminders.filter { reminder in
        guard let dueDate = reminder.dueDate else { return false }
        return dueDate.milliseconds >= start && dueDate.milliseconds < end
      }.count
    )
  }

  public static func createListOperations(
    id: String,
    title: String,
    color: String = defaultListColor,
    position: Int,
    createdAt: InstantTimestamp,
    transactionID: String
  ) -> [InstantTripleOperation] {
    [
      .requireEntityMissing(entityID: id, namespace: listsNamespace),
    ] + upsertListOperations(
      id: id,
      title: title,
      color: color,
      position: position,
      updatedAt: createdAt,
      transactionID: transactionID
    )
  }

  public static func renameListOperations(
    id: String,
    title: String,
    updatedAt: InstantTimestamp,
    transactionID: String
  ) -> [InstantTripleOperation] {
    [
      .requireEntityExists(entityID: id, namespace: listsNamespace),
      listIdentityOperation(id: id, updatedAt: updatedAt, transactionID: transactionID),
      .insert(
        InstantTriple(
          entityID: id,
          attributeID: "remindersLists/title",
          value: .string(title),
          txID: transactionID,
          txTime: updatedAt
        )
      ),
    ]
  }

  public static func upsertListOperations(
    id: String,
    title: String,
    color: String,
    position: Int,
    updatedAt: InstantTimestamp,
    transactionID: String
  ) -> [InstantTripleOperation] {
    [
      listIdentityOperation(id: id, updatedAt: updatedAt, transactionID: transactionID),
      .insert(
        InstantTriple(
          entityID: id,
          attributeID: "remindersLists/title",
          value: .string(title),
          txID: transactionID,
          txTime: updatedAt
        )
      ),
      .insert(
        InstantTriple(
          entityID: id,
          attributeID: "remindersLists/color",
          value: .string(color),
          txID: transactionID,
          txTime: updatedAt
        )
      ),
      .insert(
        InstantTriple(
          entityID: id,
          attributeID: "remindersLists/position",
          value: .number(Double(position)),
          txID: transactionID,
          txTime: updatedAt
        )
      ),
      .insert(
        InstantTriple(
          entityID: id,
          attributeID: "remindersLists/createdAt",
          value: .date(Date(timeIntervalSince1970: Double(updatedAt.milliseconds) / 1000)),
          txID: transactionID,
          txTime: updatedAt
        )
      ),
    ]
  }

  public static func createReminderOperations(
    id: String,
    listID: String,
    title: String,
    notes: String = "",
    isFlagged: Bool = false,
    dueDate: InstantTimestamp? = nil,
    priority: ReminderPriority? = nil,
    position: Int,
    createdAt: InstantTimestamp,
    transactionID: String
  ) -> [InstantTripleOperation] {
    [
      .requireEntityExists(entityID: listID, namespace: listsNamespace),
      .requireEntityMissing(entityID: id, namespace: remindersNamespace),
    ] + upsertReminderOperations(
      id: id,
      listID: listID,
      title: title,
      notes: notes,
      isCompleted: false,
      isFlagged: isFlagged,
      dueDate: dueDate,
      priority: priority,
      position: position,
      updatedAt: createdAt,
      transactionID: transactionID
    )
  }

  public static func completeReminderOperations(
    id: String,
    listID: String,
    isCompleted: Bool = true,
    updatedAt: InstantTimestamp,
    transactionID: String
  ) -> [InstantTripleOperation] {
    [
      .requireEntityExists(entityID: listID, namespace: listsNamespace),
      .requireEntityExists(entityID: id, namespace: remindersNamespace),
      requireReminderInListOperation(reminderID: id, listID: listID),
      reminderIdentityOperation(id: id, updatedAt: updatedAt, transactionID: transactionID),
      listRefOperation(reminderID: id, listID: listID, updatedAt: updatedAt, transactionID: transactionID),
      .insert(
        InstantTriple(
          entityID: id,
          attributeID: "reminders/isCompleted",
          value: .bool(isCompleted),
          txID: transactionID,
          txTime: updatedAt
        )
      ),
    ]
  }

  public static func updateReminderTitleOperations(
    id: String,
    listID: String,
    title: String,
    updatedAt: InstantTimestamp,
    transactionID: String
  ) -> [InstantTripleOperation] {
    [
      .requireEntityExists(entityID: listID, namespace: listsNamespace),
      .requireEntityExists(entityID: id, namespace: remindersNamespace),
      requireReminderInListOperation(reminderID: id, listID: listID),
      reminderIdentityOperation(id: id, updatedAt: updatedAt, transactionID: transactionID),
      listRefOperation(reminderID: id, listID: listID, updatedAt: updatedAt, transactionID: transactionID),
      .insert(
        InstantTriple(
          entityID: id,
          attributeID: "reminders/title",
          value: .string(title),
          txID: transactionID,
          txTime: updatedAt
        )
      ),
    ]
  }

  public static func updateReminderPositionOperations(
    id: String,
    listID: String,
    position: Int,
    updatedAt: InstantTimestamp,
    transactionID: String
  ) -> [InstantTripleOperation] {
    [
      .requireEntityExists(entityID: listID, namespace: listsNamespace),
      .requireEntityExists(entityID: id, namespace: remindersNamespace),
      requireReminderInListOperation(reminderID: id, listID: listID),
      reminderIdentityOperation(id: id, updatedAt: updatedAt, transactionID: transactionID),
      listRefOperation(reminderID: id, listID: listID, updatedAt: updatedAt, transactionID: transactionID),
      .insert(
        InstantTriple(
          entityID: id,
          attributeID: "reminders/position",
          value: .number(Double(position)),
          txID: transactionID,
          txTime: updatedAt
        )
      ),
    ]
  }

  public static func updateReminderDetailsOperations(
    id: String,
    listID: String,
    title: String,
    notes: String,
    isFlagged: Bool,
    dueDate: InstantTimestamp?,
    priority: ReminderPriority?,
    updatedAt: InstantTimestamp,
    transactionID: String
  ) -> [InstantTripleOperation] {
    [
      .requireEntityExists(entityID: listID, namespace: listsNamespace),
      .requireEntityExists(entityID: id, namespace: remindersNamespace),
      requireReminderInListOperation(reminderID: id, listID: listID),
      reminderIdentityOperation(id: id, updatedAt: updatedAt, transactionID: transactionID),
      listRefOperation(reminderID: id, listID: listID, updatedAt: updatedAt, transactionID: transactionID),
      .insert(
        InstantTriple(
          entityID: id,
          attributeID: "reminders/title",
          value: .string(title),
          txID: transactionID,
          txTime: updatedAt
        )
      ),
      .insert(
        InstantTriple(
          entityID: id,
          attributeID: "reminders/notes",
          value: .string(notes),
          txID: transactionID,
          txTime: updatedAt
        )
      ),
      .insert(
        InstantTriple(
          entityID: id,
          attributeID: "reminders/isFlagged",
          value: .bool(isFlagged),
          txID: transactionID,
          txTime: updatedAt
        )
      ),
      dueDateOperation(reminderID: id, dueDate: dueDate, updatedAt: updatedAt, transactionID: transactionID),
      priorityOperation(reminderID: id, priority: priority, updatedAt: updatedAt, transactionID: transactionID),
    ]
  }

  public static func upsertTagOperations(
    id: String,
    title: String,
    updatedAt: InstantTimestamp,
    transactionID: String
  ) -> [InstantTripleOperation] {
    [
      tagIdentityOperation(id: id, updatedAt: updatedAt, transactionID: transactionID),
      .insert(
        InstantTriple(
          entityID: id,
          attributeID: "tags/title",
          value: .string(title),
          txID: transactionID,
          txTime: updatedAt
        )
      ),
    ]
  }

  public static func addTagOperations(
    reminderID: String,
    listID: String,
    tagID: String,
    title: String,
    updatedAt: InstantTimestamp,
    transactionID: String
  ) -> [InstantTripleOperation] {
    [
      .requireEntityExists(entityID: listID, namespace: listsNamespace),
      .requireEntityExists(entityID: reminderID, namespace: remindersNamespace),
      requireReminderInListOperation(reminderID: reminderID, listID: listID),
    ] + upsertTagOperations(
      id: tagID,
      title: title,
      updatedAt: updatedAt,
      transactionID: transactionID
    ) + [
      listRefOperation(reminderID: reminderID, listID: listID, updatedAt: updatedAt, transactionID: transactionID),
      tagRefOperation(
        reminderID: reminderID,
        tagID: tagID,
        updatedAt: updatedAt,
        transactionID: transactionID
      ),
    ]
  }

  public static func removeTagOperations(
    reminderID: String,
    listID: String,
    tagID: String,
    updatedAt: InstantTimestamp,
    transactionID: String
  ) -> [InstantTripleOperation] {
    [
      .requireEntityExists(entityID: listID, namespace: listsNamespace),
      .requireEntityExists(entityID: reminderID, namespace: remindersNamespace),
      requireReminderInListOperation(reminderID: reminderID, listID: listID),
      listRefOperation(reminderID: reminderID, listID: listID, updatedAt: updatedAt, transactionID: transactionID),
      .retract(
        InstantTriple(
          entityID: reminderID,
          attributeID: "reminders/tags",
          value: .ref(tagID),
          txID: transactionID,
          txTime: updatedAt
        )
      ),
    ]
  }

  public static func replaceReminderTagsOperations(
    reminderID: String,
    listID: String,
    existingTagIDs: [String],
    selectedTags: [ReminderTagRecord],
    updatedAt: InstantTimestamp,
    transactionID: String,
    requiresExistingReminder: Bool = true
  ) -> [InstantTripleOperation] {
    let selectedTags = uniqueTags(selectedTags)
    let selectedTagIDs = Set(selectedTags.map(\.id))
    let existingTagIDs = unique(existingTagIDs)
    var operations: [InstantTripleOperation] = [
      .requireEntityExists(entityID: listID, namespace: listsNamespace),
      listRefOperation(reminderID: reminderID, listID: listID, updatedAt: updatedAt, transactionID: transactionID),
    ]
    if requiresExistingReminder {
      operations.insert(
        contentsOf: [
          .requireEntityExists(entityID: reminderID, namespace: remindersNamespace),
          requireReminderInListOperation(reminderID: reminderID, listID: listID),
        ],
        at: 1
      )
    }
    return operations + existingTagIDs.filter { !selectedTagIDs.contains($0) }.map { tagID in
      .retract(
        InstantTriple(
          entityID: reminderID,
          attributeID: "reminders/tags",
          value: .ref(tagID),
          txID: transactionID,
          txTime: updatedAt
        )
      )
    } + selectedTags.flatMap { tag in
      upsertTagOperations(
        id: tag.id,
        title: tag.title,
        updatedAt: updatedAt,
        transactionID: transactionID
      ) + [
        tagRefOperation(
          reminderID: reminderID,
          tagID: tag.id,
          updatedAt: updatedAt,
          transactionID: transactionID
        )
      ]
    }
  }

  public static func deleteReminderOperations(
    id: String,
    listID: String,
    updatedAt: InstantTimestamp,
    transactionID: String
  ) -> [InstantTripleOperation] {
    [
      .requireEntityExists(entityID: listID, namespace: listsNamespace),
      .requireEntityExists(entityID: id, namespace: remindersNamespace),
      requireReminderInListOperation(reminderID: id, listID: listID),
      listRefOperation(reminderID: id, listID: listID, updatedAt: updatedAt, transactionID: transactionID),
      .deleteEntityInNamespace(entityID: id, namespace: remindersNamespace),
    ]
  }

  public static func deleteCompletedReminderOperations(
    reminders: [(id: String, listID: String)],
    updatedAt: InstantTimestamp,
    transactionID: String
  ) -> [InstantTripleOperation] {
    reminders.flatMap { id, listID in
      deleteReminderOperations(
        id: id,
        listID: listID,
        updatedAt: updatedAt,
        transactionID: transactionID
      )
    }
  }

  public static func deleteListOperations(
    id: String
  ) -> [InstantTripleOperation] {
    [
      .requireEntityExists(entityID: id, namespace: listsNamespace),
      .deleteEntityInNamespace(entityID: id, namespace: listsNamespace),
    ]
  }

  public static func seedOperations(
    lists: [(id: String, seed: RemindersListSeedRecord)],
    reminders: [(id: String, listID: String, seed: ReminderSeedRecord)],
    tags: [(id: String, seed: ReminderTagSeedRecord)] = [],
    reminderTags: [(reminderID: String, tagID: String)] = [],
    baseCreatedAt: InstantTimestamp,
    transactionID: String
  ) -> [InstantTripleOperation] {
    lists.flatMap { id, seed in
      let createdAt = InstantTimestamp(
        milliseconds: baseCreatedAt.milliseconds + seed.createdAtOffsetMilliseconds
      )
      return upsertListOperations(
        id: id,
        title: seed.title,
        color: seed.color,
        position: seed.position,
        updatedAt: createdAt,
        transactionID: transactionID
      )
    } + tags.flatMap { id, seed in
      upsertTagOperations(
        id: id,
        title: seed.title,
        updatedAt: baseCreatedAt,
        transactionID: transactionID
      )
    } + reminders.flatMap { id, listID, seed in
      let createdAt = InstantTimestamp(
        milliseconds: baseCreatedAt.milliseconds + seed.createdAtOffsetMilliseconds
      )
      let dueDate = seed.dueDateOffsetMilliseconds.map {
        InstantTimestamp(milliseconds: baseCreatedAt.milliseconds + $0)
      }
      return upsertReminderOperations(
        id: id,
        listID: listID,
        title: seed.title,
        notes: seed.notes,
        isCompleted: seed.isCompleted,
        isFlagged: seed.isFlagged,
        dueDate: dueDate,
        priority: seed.priority,
        position: seed.position,
        updatedAt: createdAt,
        transactionID: transactionID
      )
    } + reminderTags.map { reminderID, tagID in
      tagRefOperation(
        reminderID: reminderID,
        tagID: tagID,
        updatedAt: baseCreatedAt,
        transactionID: transactionID
      )
    }
  }

  public static func decodeLists(
    _ snapshots: [InstantEntitySnapshot]
  ) throws -> [RemindersListRecord] {
    try snapshots.map { snapshot in
      let createdAt = try timestampField("createdAt", from: snapshot, namespace: listsNamespace)
      return RemindersListRecord(
        id: snapshot.id,
        title: try stringField("title", from: snapshot, namespace: listsNamespace),
        color: try stringField("color", from: snapshot, namespace: listsNamespace),
        position: try intField("position", from: snapshot, namespace: listsNamespace),
        createdAt: createdAt
      )
    }
  }

  public static func decodeReminders(
    _ snapshots: [InstantEntitySnapshot]
  ) throws -> [ReminderRecord] {
    try snapshots.map { snapshot in
      ReminderRecord(
        id: snapshot.id,
        remindersListID: try refField("list", from: snapshot, namespace: remindersNamespace),
        title: try stringField("title", from: snapshot, namespace: remindersNamespace),
        notes: try stringField("notes", from: snapshot, namespace: remindersNamespace),
        isCompleted: try boolField("isCompleted", from: snapshot, namespace: remindersNamespace),
        isFlagged: try boolField("isFlagged", from: snapshot, namespace: remindersNamespace),
        dueDate: try optionalTimestampField("dueDate", from: snapshot, namespace: remindersNamespace),
        priority: try optionalPriorityField("priority", from: snapshot, namespace: remindersNamespace),
        position: try intField("position", from: snapshot, namespace: remindersNamespace),
        createdAt: try timestampField("createdAt", from: snapshot, namespace: remindersNamespace)
      )
    }
  }

  public static func decodeTags(
    _ snapshots: [InstantEntitySnapshot]
  ) throws -> [ReminderTagRecord] {
    try snapshots.map { snapshot in
      ReminderTagRecord(
        id: snapshot.id,
        title: try stringField("title", from: snapshot, namespace: tagsNamespace)
      )
    }
  }

  public static func decodeReminderTagLinks(
    _ snapshots: [InstantEntitySnapshot]
  ) throws -> [ReminderTagLinkRecord] {
    try snapshots.flatMap { snapshot in
      try (snapshot.values["tags"]?.values ?? []).map { value in
        guard case let .ref(tagID) = value else {
          throw decodeError(
            namespace: remindersNamespace,
            id: snapshot.id,
            field: "tags",
            expected: "ref"
          )
        }
        return ReminderTagLinkRecord(reminderID: snapshot.id, tagID: tagID)
      }
      .sorted { $0.tagID < $1.tagID }
    }
  }

  fileprivate struct ModelContext: Sendable {
    var reminders: [ReminderRecord]
    var listsByID: [String: RemindersListRecord]
    var tagsByID: [String: ReminderTagRecord]
    var tagIDsByReminderID: [String: Set<String>]
    var tagsByReminderID: [String: [ReminderTagRecord]]
  }

  fileprivate static func modelContext(runtime: InstantRuntime) async throws -> ModelContext {
    let reminderSnapshots = try await runtime.query(remindersQuery)
    let reminders = try decodeReminders(reminderSnapshots)
    let lists = try decodeLists(try await runtime.query(listsQuery))
    let tags = try decodeTags(try await runtime.query(tagsQuery))
    let tagsByID = Dictionary(uniqueKeysWithValues: tags.map { ($0.id, $0) })
    var tagIDsByReminderID: [String: Set<String>] = [:]
    var tagsByReminderID: [String: [ReminderTagRecord]] = [:]
    for link in try decodeReminderTagLinks(reminderSnapshots) {
      tagIDsByReminderID[link.reminderID, default: []].insert(link.tagID)
      if let tag = tagsByID[link.tagID] {
        tagsByReminderID[link.reminderID, default: []].append(tag)
      }
    }
    for reminderID in tagsByReminderID.keys {
      tagsByReminderID[reminderID]?.sort {
        tagSortKey($0) < tagSortKey($1)
      }
    }
    return ModelContext(
      reminders: reminders,
      listsByID: Dictionary(uniqueKeysWithValues: lists.map { ($0.id, $0) }),
      tagsByID: tagsByID,
      tagIDsByReminderID: tagIDsByReminderID,
      tagsByReminderID: tagsByReminderID
    )
  }

  fileprivate static func searchSortKey(
    _ reminder: ReminderRecord
  ) -> (Int, Int64, Int64, String) {
    (
      reminder.isCompleted ? 1 : 0,
      reminder.dueDate?.milliseconds ?? Int64.max,
      Int64(reminder.position),
      reminder.title
    )
  }

  fileprivate static func detailSortKey(
    _ reminder: ReminderRecord,
    ordering: RemindersDetailOrdering
  ) -> (Int, Int64, Int64, Int64, String) {
    let completed = reminder.isCompleted ? 1 : 0
    switch ordering {
    case .dueDate:
      return (
        completed,
        reminder.dueDate?.milliseconds ?? Int64.max,
        0,
        Int64(reminder.position),
        reminder.title
      )

    case .manual:
      return (
        completed,
        Int64(reminder.position),
        0,
        0,
        reminder.title
      )

    case .priority:
      return (
        completed,
        Int64(-(reminder.priority?.rank ?? 0)),
        reminder.isFlagged ? -1 : 0,
        Int64(reminder.position),
        reminder.title
      )

    case .title:
      return (
        completed,
        0,
        0,
        0,
        reminder.title.lowercased()
      )
    }
  }

  fileprivate static func matchesDetailType(
    _ reminder: ReminderRecord,
    _ detailType: RemindersDetailType,
    context: ModelContext,
    now: InstantTimestamp
  ) -> Bool {
    switch detailType {
    case .all:
      return true
    case .completed:
      return reminder.isCompleted
    case .flagged:
      return reminder.isFlagged
    case let .remindersList(list):
      return reminder.remindersListID == list.id
    case .scheduled:
      return !reminder.isCompleted && reminder.dueDate != nil
    case let .tags(tags):
      let selectedTagIDs = Set(tags.map(\.id))
      return !(context.tagIDsByReminderID[reminder.id, default: []].isDisjoint(with: selectedTagIDs))
    case .today:
      return isToday(reminder, now: now)
    }
  }

  fileprivate static func isPastDue(
    _ reminder: ReminderRecord,
    now: InstantTimestamp
  ) -> Bool {
    guard !reminder.isCompleted, let dueDate = reminder.dueDate else { return false }
    let today = dayRange(containing: now)
    return dueDate.milliseconds < timestampMilliseconds(for: today.start)
  }

  fileprivate static func isToday(
    _ reminder: ReminderRecord,
    now: InstantTimestamp
  ) -> Bool {
    guard !reminder.isCompleted, let dueDate = reminder.dueDate else { return false }
    let today = dayRange(containing: now)
    let dueDateMilliseconds = dueDate.milliseconds
    return timestampMilliseconds(for: today.start) <= dueDateMilliseconds
      && dueDateMilliseconds < timestampMilliseconds(for: today.end)
  }

  fileprivate static func inlineNotes(_ notes: String) -> String {
    notes
      .split(whereSeparator: \.isWhitespace)
      .joined(separator: " ")
  }

  fileprivate static func searchSnippet(
    _ notes: String,
    matching searchText: String
  ) -> String {
    highlight(inlineNotes(notes), matching: searchText)
  }

  fileprivate static func highlightedTags(
    _ tags: [ReminderTagRecord],
    matching searchText: String
  ) -> String {
    highlight(tagText(tags), matching: searchText)
  }

  fileprivate static func tagText(_ tags: [ReminderTagRecord]) -> String {
    tags.map { "#\($0.title)" }.joined(separator: " ")
  }

  private static let upstreamExampleTagOrder: [String: Int] = [
    "car": 0,
    "kids": 1,
    "someday": 2,
    "optional": 3,
    "social": 4,
    "night": 5,
    "adulting": 6,
  ]

  fileprivate static func tagSortKey(_ tag: ReminderTagRecord) -> (Int, String) {
    (upstreamExampleTagOrder[tag.id] ?? Int.max, tag.title)
  }

  fileprivate static func moveRows<Row>(
    _ rows: inout [Row],
    fromOffsets source: IndexSet,
    toOffset destination: Int
  ) {
    guard !source.isEmpty else { return }
    let indexes = source.sorted()
    guard indexes.allSatisfy({ rows.indices.contains($0) }) else { return }
    let movingRows = indexes.map { rows[$0] }
    let adjustedDestination = max(
      0,
      min(destination - indexes.filter { $0 < destination }.count, rows.count - indexes.count)
    )
    for index in indexes.reversed() {
      rows.remove(at: index)
    }
    rows.insert(contentsOf: movingRows, at: adjustedDestination)
  }

  fileprivate static func highlight(
    _ value: String,
    matching searchText: String
  ) -> String {
    let searchText = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !searchText.isEmpty,
      let range = value.range(of: searchText, options: [.caseInsensitive, .diacriticInsensitive])
    else { return value }
    return "\(value[..<range.lowerBound])**\(value[range])**\(value[range.upperBound...])"
  }

  private static func upsertReminderOperations(
    id: String,
    listID: String,
    title: String,
    notes: String,
    isCompleted: Bool,
    isFlagged: Bool,
    dueDate: InstantTimestamp?,
    priority: ReminderPriority?,
    position: Int,
    updatedAt: InstantTimestamp,
    transactionID: String
  ) -> [InstantTripleOperation] {
    [
      reminderIdentityOperation(id: id, updatedAt: updatedAt, transactionID: transactionID),
      listRefOperation(reminderID: id, listID: listID, updatedAt: updatedAt, transactionID: transactionID),
      .insert(
        InstantTriple(
          entityID: id,
          attributeID: "reminders/title",
          value: .string(title),
          txID: transactionID,
          txTime: updatedAt
        )
      ),
      .insert(
        InstantTriple(
          entityID: id,
          attributeID: "reminders/notes",
          value: .string(notes),
          txID: transactionID,
          txTime: updatedAt
        )
      ),
      .insert(
        InstantTriple(
          entityID: id,
          attributeID: "reminders/isCompleted",
          value: .bool(isCompleted),
          txID: transactionID,
          txTime: updatedAt
        )
      ),
      .insert(
        InstantTriple(
          entityID: id,
          attributeID: "reminders/isFlagged",
          value: .bool(isFlagged),
          txID: transactionID,
          txTime: updatedAt
        )
      ),
      dueDateOperation(reminderID: id, dueDate: dueDate, updatedAt: updatedAt, transactionID: transactionID),
      priorityOperation(reminderID: id, priority: priority, updatedAt: updatedAt, transactionID: transactionID),
      .insert(
        InstantTriple(
          entityID: id,
          attributeID: "reminders/position",
          value: .number(Double(position)),
          txID: transactionID,
          txTime: updatedAt
        )
      ),
      .insert(
        InstantTriple(
          entityID: id,
          attributeID: "reminders/createdAt",
          value: .date(Date(timeIntervalSince1970: Double(updatedAt.milliseconds) / 1000)),
          txID: transactionID,
          txTime: updatedAt
        )
      ),
    ]
  }

  private static func listRefOperation(
    reminderID: String,
    listID: String,
    updatedAt: InstantTimestamp,
    transactionID: String
  ) -> InstantTripleOperation {
    .insert(
      InstantTriple(
        entityID: reminderID,
        attributeID: "reminders/list",
        value: .ref(listID),
        txID: transactionID,
        txTime: updatedAt
      )
    )
  }

  private static func tagRefOperation(
    reminderID: String,
    tagID: String,
    updatedAt: InstantTimestamp,
    transactionID: String
  ) -> InstantTripleOperation {
    .insert(
      InstantTriple(
        entityID: reminderID,
        attributeID: "reminders/tags",
        value: .ref(tagID),
        txID: transactionID,
        txTime: updatedAt
      )
    )
  }

  private static func dueDateOperation(
    reminderID: String,
    dueDate: InstantTimestamp?,
    updatedAt: InstantTimestamp,
    transactionID: String
  ) -> InstantTripleOperation {
    .insert(
      InstantTriple(
        entityID: reminderID,
        attributeID: "reminders/dueDate",
        value: dueDate.map {
          .date(Date(timeIntervalSince1970: Double($0.milliseconds) / 1000))
        } ?? .null,
        txID: transactionID,
        txTime: updatedAt
      )
    )
  }

  private static func priorityOperation(
    reminderID: String,
    priority: ReminderPriority?,
    updatedAt: InstantTimestamp,
    transactionID: String
  ) -> InstantTripleOperation {
    .insert(
      InstantTriple(
        entityID: reminderID,
        attributeID: "reminders/priority",
        value: priority.map { .number(Double($0.rank)) } ?? .null,
        txID: transactionID,
        txTime: updatedAt
      )
    )
  }

  private static func priorityFilter(_ priority: ReminderPriority) -> InstantQueryFilter {
    .equals(field: "priority", value: .number(Double(priority.rank)))
  }

  public static func migrateLegacyPriorityRanks(
    in snapshot: InstantPersistenceSnapshot
  ) -> InstantPersistenceSnapshot {
    InstantPersistenceSnapshot(
      store: migrateLegacyPriorityRanks(in: snapshot.store),
      outbox: snapshot.outbox.map(migrateLegacyPriorityRanks(in:))
    )
  }

  public static func migrateLegacyPriorityRanks(
    in snapshot: InstantStoreSnapshot
  ) -> InstantStoreSnapshot {
    let attributes = snapshot.attributes.map { attribute in
      var attribute = attribute
      if attribute.id == "reminders/priority" {
        attribute.valueType = .number
      }
      return attribute
    }
    var seenTriples: Set<InstantTriple> = []
    let triples = snapshot.triples.compactMap { triple -> InstantTriple? in
      let migrated = migrateLegacyPriorityRank(in: triple)
      guard seenTriples.insert(migrated).inserted else { return nil }
      return migrated
    }
    return InstantStoreSnapshot(attributes: attributes, triples: triples)
  }

  private static func migrateLegacyPriorityRanks(
    in mutation: PendingMutation
  ) -> PendingMutation {
    var mutation = mutation
    mutation.transaction = InstantStoreTransaction(
      id: mutation.transaction.id,
      operations: mutation.transaction.operations.map(migrateLegacyPriorityRank(in:))
    )
    return mutation
  }

  private static func migrateLegacyPriorityRank(
    in operation: InstantTripleOperation
  ) -> InstantTripleOperation {
    switch operation {
    case let .requireTripleExists(entityID, attributeID, value):
      return .requireTripleExists(
        entityID: entityID,
        attributeID: attributeID,
        value: migrateLegacyPriorityRank(attributeID: attributeID, value: value)
      )

    case let .merge(triple):
      return .merge(migrateLegacyPriorityRank(in: triple))

    case let .mergeByLookup(entity, attributeID, value, txID, txTime):
      return .mergeByLookup(
        entity: entity,
        attributeID: attributeID,
        value: migrateLegacyPriorityRank(attributeID: attributeID, value: value),
        txID: txID,
        txTime: txTime
      )

    case let .insert(triple):
      return .insert(migrateLegacyPriorityRank(in: triple))

    case let .insertByLookup(entity, attributeID, value, txID, txTime):
      return .insertByLookup(
        entity: entity,
        attributeID: attributeID,
        value: migrateLegacyPriorityRank(attributeID: attributeID, value: value),
        txID: txID,
        txTime: txTime
      )

    case let .retract(triple):
      return .retract(migrateLegacyPriorityRank(in: triple))

    case let .retractByLookup(entity, attributeID, value, txID, txTime):
      return .retractByLookup(
        entity: entity,
        attributeID: attributeID,
        value: migrateLegacyPriorityRank(attributeID: attributeID, value: value),
        txID: txID,
        txTime: txTime
      )

    case .requireEntityMissing, .requireEntityMissingByLookup,
      .requireEntityExists, .requireEntityExistsByLookup,
      .deleteEntity, .deleteEntityInNamespace, .deleteEntityByLookup,
      .ruleParams, .ruleParamsByLookup:
      return operation
    }
  }

  private static func migrateLegacyPriorityRank(
    in triple: InstantTriple
  ) -> InstantTriple {
    var triple = triple
    triple.value = migrateLegacyPriorityRank(
      attributeID: triple.attributeID,
      value: triple.value
    )
    return triple
  }

  private static func migrateLegacyPriorityRank(
    attributeID: String,
    value: InstantValue
  ) -> InstantValue {
    guard attributeID == "reminders/priority",
      case let .string(rawValue) = value,
      let priority = ReminderPriority(rawValue: rawValue)
    else { return value }
    return .number(Double(priority.rank))
  }

  private static func requireReminderInListOperation(
    reminderID: String,
    listID: String
  ) -> InstantTripleOperation {
    .requireTripleExists(
      entityID: reminderID,
      attributeID: "reminders/list",
      value: .ref(listID)
    )
  }

  private static func listIdentityOperation(
    id: String,
    updatedAt: InstantTimestamp,
    transactionID: String
  ) -> InstantTripleOperation {
    .insert(
      InstantTriple(
        entityID: id,
        attributeID: InstantAttribute.primaryKeyID(namespace: listsNamespace),
        value: .string(id),
        txID: transactionID,
        txTime: updatedAt
      )
    )
  }

  private static func reminderIdentityOperation(
    id: String,
    updatedAt: InstantTimestamp,
    transactionID: String
  ) -> InstantTripleOperation {
    .insert(
      InstantTriple(
        entityID: id,
        attributeID: InstantAttribute.primaryKeyID(namespace: remindersNamespace),
        value: .string(id),
        txID: transactionID,
        txTime: updatedAt
      )
    )
  }

  private static func tagIdentityOperation(
    id: String,
    updatedAt: InstantTimestamp,
    transactionID: String
  ) -> InstantTripleOperation {
    .insert(
      InstantTriple(
        entityID: id,
        attributeID: InstantAttribute.primaryKeyID(namespace: tagsNamespace),
        value: .string(id),
        txID: transactionID,
        txTime: updatedAt
      )
    )
  }

  private static func stringField(
    _ field: String,
    from snapshot: InstantEntitySnapshot,
    namespace: String
  ) throws -> String {
    guard case let .string(value) = snapshot.values[field]?.first else {
      throw decodeError(namespace: namespace, id: snapshot.id, field: field, expected: "string")
    }
    return value
  }

  private static func refField(
    _ field: String,
    from snapshot: InstantEntitySnapshot,
    namespace: String
  ) throws -> String {
    guard case let .ref(value) = snapshot.values[field]?.first else {
      throw decodeError(namespace: namespace, id: snapshot.id, field: field, expected: "ref")
    }
    return value
  }

  private static func boolField(
    _ field: String,
    from snapshot: InstantEntitySnapshot,
    namespace: String
  ) throws -> Bool {
    guard case let .bool(value) = snapshot.values[field]?.first else {
      throw decodeError(namespace: namespace, id: snapshot.id, field: field, expected: "boolean")
    }
    return value
  }

  private static func intField(
    _ field: String,
    from snapshot: InstantEntitySnapshot,
    namespace: String
  ) throws -> Int {
    guard case let .number(value) = snapshot.values[field]?.first else {
      throw decodeError(namespace: namespace, id: snapshot.id, field: field, expected: "number")
    }
    return Int(value.rounded())
  }

  private static func timestampField(
    _ field: String,
    from snapshot: InstantEntitySnapshot,
    namespace: String
  ) throws -> InstantTimestamp {
    guard case let .date(value) = snapshot.values[field]?.first else {
      throw decodeError(namespace: namespace, id: snapshot.id, field: field, expected: "date")
    }
    return InstantTimestamp(milliseconds: Int64((value.timeIntervalSince1970 * 1000).rounded()))
  }

  private static func optionalTimestampField(
    _ field: String,
    from snapshot: InstantEntitySnapshot,
    namespace: String
  ) throws -> InstantTimestamp? {
    guard let value = snapshot.values[field]?.first else { return nil }
    switch value {
    case .null:
      return nil
    case let .date(date):
      return InstantTimestamp(milliseconds: Int64((date.timeIntervalSince1970 * 1000).rounded()))
    default:
      throw decodeError(namespace: namespace, id: snapshot.id, field: field, expected: "date")
    }
  }

  private static func optionalPriorityField(
    _ field: String,
    from snapshot: InstantEntitySnapshot,
    namespace: String
  ) throws -> ReminderPriority? {
    guard let value = snapshot.values[field]?.first else { return nil }
    switch value {
    case .null:
      return nil
    case let .string(rawValue):
      guard let priority = ReminderPriority(rawValue: rawValue) else {
        throw decodeError(namespace: namespace, id: snapshot.id, field: field, expected: "priority")
      }
      return priority
    case let .number(rawValue):
      let rank = Int(rawValue.rounded())
      guard Double(rank) == rawValue, let priority = ReminderPriority(rank: rank) else {
        throw decodeError(namespace: namespace, id: snapshot.id, field: field, expected: "priority")
      }
      return priority
    default:
      throw decodeError(
        namespace: namespace,
        id: snapshot.id,
        field: field,
        expected: "priority"
      )
    }
  }

  private static func decodeError(
    namespace: String,
    id: String,
    field: String,
    expected: String
  ) -> InstantError {
    InstantError(
      code: .decodeFailed,
      operation: "decode reminders example",
      namespace: namespace,
      path: field,
      localID: id,
      message: "Expected \(expected) for '\(namespace).\(field)'.",
      recovery: "Inspect the local reminders example triples and attributes."
    )
  }

  private static func likePatternLiteral(_ value: String) -> String {
    let sanitized = value.filter { character in
      character != "%" && character != "_" && character != "\\"
    }
    return sanitized.isEmpty ? "\u{0}" : String(sanitized)
  }

  private static func searchTextFilter(_ text: String) -> InstantQueryFilter {
    let filters = text.split(whereSeparator: \.isWhitespace).map { searchTermFilter(String($0)) }
    if filters.count == 1, let filter = filters.first {
      return filter
    }
    return .and(filters)
  }

  private static func searchTermFilter(_ term: String) -> InstantQueryFilter {
    let pattern = "%\(likePatternLiteral(term))%"
    return .or([
      .iLike(field: "title", pattern: pattern),
      .iLike(field: "notes", pattern: pattern),
      .iLike(field: "tags.title", pattern: pattern),
      .iLike(field: "tags.id", pattern: pattern),
    ])
  }

  private static func dayRange(containing timestamp: InstantTimestamp) -> (start: Date, end: Date) {
    let date = Date(timeIntervalSince1970: Double(timestamp.milliseconds) / 1000)
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let start = calendar.startOfDay(for: date)
    let end = calendar.date(byAdding: .day, value: 1, to: start)!
    return (start, end)
  }

  private static func timestampMilliseconds(for date: Date) -> Int64 {
    Int64((date.timeIntervalSince1970 * 1000).rounded())
  }

  private static func uniqueTags(_ tags: [ReminderTagRecord]) -> [ReminderTagRecord] {
    var seen: Set<String> = []
    return tags.filter { tag in
      seen.insert(tag.id).inserted
    }
  }

  private static func unique(_ ids: [String]) -> [String] {
    var seen: Set<String> = []
    return ids.filter { seen.insert($0).inserted }
  }

  private static func queryIDFragment(_ value: String) -> String {
    Data(value.utf8).base64EncodedString()
      .replacingOccurrences(of: "+", with: "-")
      .replacingOccurrences(of: "/", with: "_")
      .replacingOccurrences(of: "=", with: "")
  }
}
