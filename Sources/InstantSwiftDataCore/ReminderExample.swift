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

  public init(
    localIDName: String,
    listLocalIDName: String,
    title: String,
    notes: String,
    isCompleted: Bool,
    isFlagged: Bool,
    position: Int,
    createdAtOffsetMilliseconds: Int64
  ) {
    self.localIDName = localIDName
    self.listLocalIDName = listLocalIDName
    self.title = title
    self.notes = notes
    self.isCompleted = isCompleted
    self.isFlagged = isFlagged
    self.position = position
    self.createdAtOffsetMilliseconds = createdAtOffsetMilliseconds
  }
}

public enum ReminderExample {
  public static let listsNamespace = "remindersLists"
  public static let remindersNamespace = "reminders"
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
      createdAtOffsetMilliseconds: 1
    ),
    ReminderSeedRecord(
      localIDName: "examples.reminders.seed.haircut",
      listLocalIDName: "examples.reminders.seed.personal",
      title: "Haircut",
      notes: "",
      isCompleted: false,
      isFlagged: true,
      position: 1,
      createdAtOffsetMilliseconds: 2
    ),
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

  public static func remindersForListQuery(_ listID: String) -> InstantQueryPlan {
    InstantQueryPlan(
      id: "examples.reminders.reminders.list-\(queryIDFragment(listID))",
      namespace: remindersNamespace,
      filters: [.equals(field: "list", value: .ref(listID))],
      order: InstantQueryOrder("position", .ascending)
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

  public static func seedOperations(
    lists: [(id: String, seed: RemindersListSeedRecord)],
    reminders: [(id: String, listID: String, seed: ReminderSeedRecord)],
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

  private static func queryIDFragment(_ value: String) -> String {
    Data(value.utf8).base64EncodedString()
      .replacingOccurrences(of: "+", with: "-")
      .replacingOccurrences(of: "/", with: "_")
      .replacingOccurrences(of: "=", with: "")
  }
}
