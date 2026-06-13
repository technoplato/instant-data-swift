import Foundation

public struct TodoProjectRecord: Hashable, Codable, Sendable, Identifiable {
  public var id: String
  public var title: String

  public init(id: String, title: String) {
    self.id = id
    self.title = title
  }
}

public struct LinkedTodoRecord: Hashable, Codable, Sendable, Identifiable {
  public var id: String
  public var text: String
  public var isCompleted: Bool
  public var createdAt: InstantTimestamp
  public var projectID: String?

  public init(
    id: String,
    text: String,
    isCompleted: Bool,
    createdAt: InstantTimestamp,
    projectID: String? = nil
  ) {
    self.id = id
    self.text = text
    self.isCompleted = isCompleted
    self.createdAt = createdAt
    self.projectID = projectID
  }
}

public enum TodoProjectExample {
  public static let namespace = "projects"
  public static let projectIDName = "examples.todo-links.project"
  public static let todoIDName = "examples.todo-links.todo"

  public static let attributes: [InstantAttribute] = TodoExample.attributes + [
    .primaryKey(namespace: namespace),
    InstantAttribute(
      id: "projects/title",
      namespace: namespace,
      name: "title",
      valueType: .string,
      isIndexed: true
    ),
    InstantAttribute(
      id: "todos/project",
      namespace: TodoExample.namespace,
      name: "project",
      valueType: .ref,
      isRequired: false,
      isIndexed: true,
      forwardIdentity: "todos/project",
      reverseIdentity: "projects/todos",
      linkNamespace: namespace
    ),
  ]

  public static let projectsQuery = InstantQueryPlan(
    id: "examples.todo-links.projects",
    namespace: namespace,
    order: InstantQueryOrder("title", .ascending)
  )

  public static let todosQuery = InstantQueryPlan(
    id: "examples.todo-links.todos",
    namespace: TodoExample.namespace,
    order: InstantQueryOrder("createdAt", .ascending)
  )

  public static let todosWithProjectQuery = InstantQueryPlan(
    id: "examples.todo-links.todos.with-project",
    namespace: TodoExample.namespace,
    order: InstantQueryOrder("createdAt", .ascending),
    includes: [
      InstantQueryInclude(
        "project",
        query: InstantQueryIncludePlan(
          id: "examples.todo-links.included-projects",
          namespace: namespace,
          order: InstantQueryOrder("title", .ascending),
          selectedFields: ["title"]
        )
      )
    ]
  )

  public static let projectsWithTodosQuery = InstantQueryPlan(
    id: "examples.todo-links.projects.with-todos",
    namespace: namespace,
    order: InstantQueryOrder("title", .ascending),
    includes: [
      InstantQueryInclude(
        "todos",
        direction: .reverse,
        query: InstantQueryIncludePlan(
          id: "examples.todo-links.included-todos",
          namespace: TodoExample.namespace,
          order: InstantQueryOrder("createdAt", .ascending),
          selectedFields: ["text", "project"]
        )
      )
    ]
  )

  public static func createProjectOperations(
    id: String,
    title: String,
    createdAt: InstantTimestamp,
    transactionID: String
  ) -> [InstantTripleOperation] {
    [
      .requireEntityMissing(entityID: id, namespace: namespace),
    ] + upsertProjectOperations(
      id: id,
      title: title,
      createdAt: createdAt,
      transactionID: transactionID
    )
  }

  public static func upsertProjectOperations(
    id: String,
    title: String,
    createdAt: InstantTimestamp,
    transactionID: String
  ) -> [InstantTripleOperation] {
    [
      identityOperation(id: id, updatedAt: createdAt, transactionID: transactionID),
      .insert(
        InstantTriple(
          entityID: id,
          attributeID: "projects/title",
          value: .string(title),
          txID: transactionID,
          txTime: createdAt
        )
      )
    ]
  }

  private static func identityOperation(
    id: String,
    updatedAt: InstantTimestamp,
    transactionID: String
  ) -> InstantTripleOperation {
    .insert(
      InstantTriple(
        entityID: id,
        attributeID: InstantAttribute.primaryKeyID(namespace: namespace),
        value: .string(id),
        txID: transactionID,
        txTime: updatedAt
      )
    )
  }

  public static func linkOperations(
    todoID: String,
    projectID: String,
    updatedAt: InstantTimestamp,
    transactionID: String
  ) -> [InstantTripleOperation] {
    [
      .insert(
        InstantTriple(
          entityID: todoID,
          attributeID: "todos/project",
          value: .ref(projectID),
          txID: transactionID,
          txTime: updatedAt
        )
      )
    ]
  }

  public static func unlinkOperations(
    todoID: String,
    projectID: String,
    updatedAt: InstantTimestamp,
    transactionID: String
  ) -> [InstantTripleOperation] {
    [
      .retract(
        InstantTriple(
          entityID: todoID,
          attributeID: "todos/project",
          value: .ref(projectID),
          txID: transactionID,
          txTime: updatedAt
        )
      )
    ]
  }

  public static func decodeProjects(
    _ snapshots: [InstantEntitySnapshot]
  ) throws -> [TodoProjectRecord] {
    try snapshots.map { snapshot in
      guard case let .string(title) = snapshot.values["title"]?.first else {
        throw decodeError(
          namespace: namespace,
          id: snapshot.id,
          field: "title",
          expected: "string"
        )
      }
      return TodoProjectRecord(id: snapshot.id, title: title)
    }
  }

  public static func decodeLinkedTodos(
    _ snapshots: [InstantEntitySnapshot]
  ) throws -> [LinkedTodoRecord] {
    try snapshots.map { snapshot in
      guard case let .string(text) = snapshot.values["text"]?.first else {
        throw decodeError(
          namespace: TodoExample.namespace,
          id: snapshot.id,
          field: "text",
          expected: "string"
        )
      }
      guard case let .bool(isCompleted) = snapshot.values["isCompleted"]?.first else {
        throw decodeError(
          namespace: TodoExample.namespace,
          id: snapshot.id,
          field: "isCompleted",
          expected: "boolean"
        )
      }
      guard case let .date(createdAt) = snapshot.values["createdAt"]?.first else {
        throw decodeError(
          namespace: TodoExample.namespace,
          id: snapshot.id,
          field: "createdAt",
          expected: "date"
        )
      }

      let projectID: String?
      if let project = snapshot.values["project"]?.first {
        guard case let .ref(rawValue) = project else {
          throw decodeError(
            namespace: TodoExample.namespace,
            id: snapshot.id,
            field: "project",
            expected: "ref"
          )
        }
        projectID = rawValue
      } else {
        projectID = nil
      }

      return LinkedTodoRecord(
        id: snapshot.id,
        text: text,
        isCompleted: isCompleted,
        createdAt: InstantTimestamp(
          milliseconds: Int64((createdAt.timeIntervalSince1970 * 1000).rounded())
        ),
        projectID: projectID
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
      operation: "decode linked todo example",
      namespace: namespace,
      path: field,
      localID: id,
      message: "Expected \(expected) for '\(namespace).\(field)'.",
      recovery: "Inspect the local linked todo example triples and attributes."
    )
  }
}
