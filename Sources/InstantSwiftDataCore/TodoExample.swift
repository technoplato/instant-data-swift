import Foundation

public struct TodoRecord: Hashable, Codable, Sendable, Identifiable {
  public var id: String
  public var text: String
  public var isCompleted: Bool
  public var createdAt: InstantTimestamp

  public init(id: String, text: String, isCompleted: Bool, createdAt: InstantTimestamp) {
    self.id = id
    self.text = text
    self.isCompleted = isCompleted
    self.createdAt = createdAt
  }
}

public struct TodoSeedRecord: Hashable, Codable, Sendable {
  public var localIDName: String
  public var text: String
  public var isCompleted: Bool
  public var createdAtOffsetMilliseconds: Int64

  public init(
    localIDName: String,
    text: String,
    isCompleted: Bool,
    createdAtOffsetMilliseconds: Int64
  ) {
    self.localIDName = localIDName
    self.text = text
    self.isCompleted = isCompleted
    self.createdAtOffsetMilliseconds = createdAtOffsetMilliseconds
  }
}

public enum TodoExample {
  public static let namespace = "todos"

  public static let seedRecords: [TodoSeedRecord] = [
    TodoSeedRecord(
      localIDName: "examples.todos.seed.plan",
      text: "Plan the Instant Swift Data demo",
      isCompleted: true,
      createdAtOffsetMilliseconds: 0
    ),
    TodoSeedRecord(
      localIDName: "examples.todos.seed.terminal",
      text: "Run the non-captive terminal workflow",
      isCompleted: false,
      createdAtOffsetMilliseconds: 1
    ),
    TodoSeedRecord(
      localIDName: "examples.todos.seed.audit",
      text: "Audit the local cache and outbox",
      isCompleted: false,
      createdAtOffsetMilliseconds: 2
    ),
  ]

  public static let attributes: [InstantAttribute] = [
    InstantAttribute(
      id: "todos/text",
      namespace: namespace,
      name: "text",
      valueType: .string,
      isIndexed: true
    ),
    InstantAttribute(
      id: "todos/isCompleted",
      namespace: namespace,
      name: "isCompleted",
      valueType: .boolean,
      isIndexed: true
    ),
    InstantAttribute(
      id: "todos/createdAt",
      namespace: namespace,
      name: "createdAt",
      valueType: .date,
      isIndexed: true
    ),
  ]

  public static let query = InstantQueryPlan(
    id: "examples.todos.list",
    namespace: namespace,
    order: InstantQueryOrder("createdAt", .ascending)
  )

  public static func createOperations(
    id: String,
    text: String,
    createdAt: InstantTimestamp,
    transactionID: String
  ) -> [InstantTripleOperation] {
    [
      .insert(
        InstantTriple(
          entityID: id,
          attributeID: "todos/text",
          value: .string(text),
          txID: transactionID,
          txTime: createdAt
        )
      ),
      .insert(
        InstantTriple(
          entityID: id,
          attributeID: "todos/isCompleted",
          value: .bool(false),
          txID: transactionID,
          txTime: createdAt
        )
      ),
      .insert(
        InstantTriple(
          entityID: id,
          attributeID: "todos/createdAt",
          value: .date(Date(timeIntervalSince1970: Double(createdAt.milliseconds) / 1000)),
          txID: transactionID,
          txTime: createdAt
        )
      ),
    ]
  }

  public static func seedOperations(
    records: [(id: String, seed: TodoSeedRecord)],
    baseCreatedAt: InstantTimestamp,
    transactionID: String
  ) -> [InstantTripleOperation] {
    records.flatMap { id, seed in
      let createdAt = InstantTimestamp(
        milliseconds: baseCreatedAt.milliseconds + seed.createdAtOffsetMilliseconds
      )
      return createOperations(
        id: id,
        text: seed.text,
        createdAt: createdAt,
        transactionID: transactionID
      ) + completeOperations(
        id: id,
        isCompleted: seed.isCompleted,
        updatedAt: createdAt,
        transactionID: transactionID
      )
    }
  }

  public static func completeOperations(
    id: String,
    isCompleted: Bool = true,
    updatedAt: InstantTimestamp,
    transactionID: String
  ) -> [InstantTripleOperation] {
    [
      .insert(
        InstantTriple(
          entityID: id,
          attributeID: "todos/isCompleted",
          value: .bool(isCompleted),
          txID: transactionID,
          txTime: updatedAt
        )
      )
    ]
  }

  public static func updateTextOperations(
    id: String,
    text: String,
    updatedAt: InstantTimestamp,
    transactionID: String
  ) -> [InstantTripleOperation] {
    [
      .insert(
        InstantTriple(
          entityID: id,
          attributeID: "todos/text",
          value: .string(text),
          txID: transactionID,
          txTime: updatedAt
        )
      )
    ]
  }

  public static func deleteOperations(id: String) -> [InstantTripleOperation] {
    [.deleteEntity(id)]
  }

  public static func resetOperations(ids: [String]) -> [InstantTripleOperation] {
    ids.map(InstantTripleOperation.deleteEntity)
  }

  public static func decode(_ snapshots: [InstantEntitySnapshot]) throws -> [TodoRecord] {
    try snapshots.map { snapshot in
      guard case let .string(text) = snapshot.values["text"]?.first
      else {
        throw decodeError(snapshot: snapshot, field: "text", expected: "string")
      }
      guard case let .bool(isCompleted) = snapshot.values["isCompleted"]?.first
      else {
        throw decodeError(snapshot: snapshot, field: "isCompleted", expected: "boolean")
      }
      guard case let .date(createdAt) = snapshot.values["createdAt"]?.first
      else {
        throw decodeError(snapshot: snapshot, field: "createdAt", expected: "date")
      }
      return TodoRecord(
        id: snapshot.id,
        text: text,
        isCompleted: isCompleted,
        createdAt: InstantTimestamp(
          milliseconds: Int64((createdAt.timeIntervalSince1970 * 1000).rounded())
        )
      )
    }
  }

  private static func decodeError(
    snapshot: InstantEntitySnapshot,
    field: String,
    expected: String
  ) -> InstantError {
    InstantError(
      code: .decodeFailed,
      operation: "decode todo",
      namespace: namespace,
      path: field,
      localID: snapshot.id,
      message: "Expected \(expected) for todo field '\(field)'.",
      recovery: "Check schema generation and server values for the todos namespace."
    )
  }
}
