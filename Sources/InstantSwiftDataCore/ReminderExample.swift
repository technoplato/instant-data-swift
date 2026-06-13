import Foundation

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
  public var position: Int
  public var createdAt: InstantTimestamp

  public init(
    id: String,
    remindersListID: String,
    title: String,
    notes: String,
    isCompleted: Bool,
    isFlagged: Bool,
    position: Int,
    createdAt: InstantTimestamp
  ) {
    self.id = id
    self.remindersListID = remindersListID
    self.title = title
    self.notes = notes
    self.isCompleted = isCompleted
    self.isFlagged = isFlagged
    self.position = position
    self.createdAt = createdAt
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
      isIndexed: false
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

  public static func remindersSearchQuery(
    text: String,
    listID: String? = nil,
    tagID: String? = nil,
    includeCompleted: Bool = false
  ) -> InstantQueryPlan {
    let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
    var fragments: [String] = []
    var filters: [InstantQueryFilter] = []

    if !trimmedText.isEmpty {
      let pattern = "%\(likePatternLiteral(trimmedText))%"
      fragments.append("text-\(queryIDFragment(trimmedText))")
      filters.append(
        .or([
          .iLike(field: "title", pattern: pattern),
          .iLike(field: "notes", pattern: pattern),
          .iLike(field: "tags.title", pattern: pattern),
          .iLike(field: "tags.id", pattern: pattern),
        ])
      )
    }

    if let listID {
      fragments.append("list-\(queryIDFragment(listID))")
      filters.append(.equals(field: "list", value: .ref(listID)))
    }

    if let tagID {
      fragments.append("tag-\(queryIDFragment(tagID))")
      filters.append(.equals(field: "tags", value: .ref(tagID)))
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
      .deleteEntity(id),
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
      .deleteEntity(id),
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
      return upsertReminderOperations(
        id: id,
        listID: listID,
        title: seed.title,
        notes: seed.notes,
        isCompleted: seed.isCompleted,
        isFlagged: seed.isFlagged,
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

  private static func upsertReminderOperations(
    id: String,
    listID: String,
    title: String,
    notes: String,
    isCompleted: Bool,
    isFlagged: Bool,
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

  private static func queryIDFragment(_ value: String) -> String {
    Data(value.utf8).base64EncodedString()
      .replacingOccurrences(of: "+", with: "-")
      .replacingOccurrences(of: "/", with: "_")
      .replacingOccurrences(of: "=", with: "")
  }
}
