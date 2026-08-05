import Foundation
import InstantSwiftData

@InstantEntity
public struct Todo: Hashable, Codable, InstantEntityModel {
  public var id: InstantID<Todo>
  public var text: String
  public var isCompleted: Bool
  public var createdAt: Date

  public init(
    id: InstantID<Todo>,
    text: String,
    isCompleted: Bool,
    createdAt: Date
  ) {
    self.id = id
    self.text = text
    self.isCompleted = isCompleted
    self.createdAt = createdAt
  }

  public init(snapshot: InstantEntitySnapshot) throws {
    guard case let .string(text) = snapshot.values["text"]?.first,
      case let .bool(isCompleted) = snapshot.values["isCompleted"]?.first,
      case let .date(createdAt) = snapshot.values["createdAt"]?.first
    else {
      throw InstantError(
        code: .decodeFailed,
        operation: "decode Todos V3 todo",
        namespace: Self.instantNamespace,
        localID: snapshot.id,
        message: "Expected text, completion, and creation-date values.",
        recovery: "Keep the Todos V3 app model aligned with the generated Todos schema."
      )
    }
    id = InstantID(rawValue: snapshot.id)
    self.text = text
    self.isCompleted = isCompleted
    self.createdAt = createdAt
  }
}

public struct TodoCreated: Hashable, Sendable {
  public var id: InstantID<Todo>

  public init(id: InstantID<Todo>) {
    self.id = id
  }
}

public struct CreateTodo: InstantMessage {
  public var id: InstantID<Todo>
  public var text: String
  public var createdAt: Date

  public init(id: InstantID<Todo>, text: String, createdAt: Date) {
    self.id = id
    self.text = text
    self.createdAt = createdAt
  }

  public func prepare(using client: InstantSwiftDataClient) async throws
    -> InstantPreparedMessage<TodoCreated>
  {
    _ = client
    return InstantPreparedMessage(change: TodoCreated(id: id)) {
      Todo.create(
        id: id,
        Todo.text.set(text),
        Todo.isCompleted.set(false),
        Todo.createdAt.set(createdAt)
      )
    }
  }
}

public struct TodoCompletionChanged: Hashable, Sendable {
  public var id: InstantID<Todo>
  public var isCompleted: Bool

  public init(id: InstantID<Todo>, isCompleted: Bool) {
    self.id = id
    self.isCompleted = isCompleted
  }
}

public struct SetTodoCompletion: InstantMessage {
  public var id: InstantID<Todo>
  public var isCompleted: Bool

  public init(id: InstantID<Todo>, isCompleted: Bool) {
    self.id = id
    self.isCompleted = isCompleted
  }

  public func prepare(using client: InstantSwiftDataClient) async throws
    -> InstantPreparedMessage<TodoCompletionChanged>
  {
    _ = client
    return InstantPreparedMessage(
      change: TodoCompletionChanged(id: id, isCompleted: isCompleted)
    ) {
      Todo.updateExisting(id: id, Todo.isCompleted.set(isCompleted))
    }
  }
}

public struct TodoDeleted: Hashable, Sendable {
  public var id: InstantID<Todo>

  public init(id: InstantID<Todo>) {
    self.id = id
  }
}

public struct DeleteTodo: InstantMessage {
  public var id: InstantID<Todo>

  public init(id: InstantID<Todo>) {
    self.id = id
  }

  public func prepare(using client: InstantSwiftDataClient) async throws
    -> InstantPreparedMessage<TodoDeleted>
  {
    _ = client
    return InstantPreparedMessage(change: TodoDeleted(id: id)) {
      Todo.delete(id: id)
    }
  }
}

public struct TodoViewerPresence: Codable, Equatable, Sendable {
  public init() {}
}

public struct TodosRoom: InstantRoomSchema {
  public typealias Presence = TodoViewerPresence
  public static let roomType = "todos"

  public enum Topic: String, InstantRoomTopic {
    public typealias RoomSchema = TodosRoom
    case changed
  }
}
