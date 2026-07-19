import CustomDump
import Foundation
import InstantSwiftData
import Testing
@testable import TodosV3App

@Suite
struct TodosV3AppTests {
  @Test
  func desiredPublicSyntaxCompilesAndMessagesMaterializeExactShape() async throws {
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "todos-v3-tests",
        persistenceURL: FileManager.default.temporaryDirectory
          .appendingPathComponent("todos-v3-tests-\(UUID().uuidString).sqlite"),
        initialAttributes: Todo.instantAttributes
      )
    )
    let client = InstantSwiftDataClient(runtime: runtime)
    let id = InstantID<Todo>(rawValue: "todo-app")
    let createdAt = Date(timeIntervalSince1970: 1_700_000_000)
    let created = try await CreateTodo(
      id: id,
      text: "Ship Todos V3",
      createdAt: createdAt
    ).prepare(using: client)
    _ = try await client.transact {
      for mutation in created.mutations { mutation }
    }

    let completed = try await SetTodoCompletion(
      id: id,
      isCompleted: true
    ).prepare(using: client)
    _ = try await client.transact {
      for mutation in completed.mutations { mutation }
    }

    let todos = FetchAll(Todo.query.order(.serverCreatedAt, .descending))
    try await todos.load(using: client)
    expectNoDifference(
      todos.wrappedValue,
      [Todo(id: id, text: "Ship Todos V3", isCompleted: true, createdAt: createdAt)]
    )
    expectNoDifference(TodosRoom.roomType, "todos")
  }

  @Test
  func environmentConfigurationSelectsLocalAndLiveModes() {
    expectNoDifference(
      TodosAppConfiguration.environment([:]),
      TodosAppConfiguration(appID: "todos-v3-local", enablesLiveSync: false)
    )
    expectNoDifference(
      TodosAppConfiguration.environment(["INSTANT_APP_ID": "todos-live"]),
      TodosAppConfiguration(appID: "todos-live", enablesLiveSync: true)
    )
  }
}
