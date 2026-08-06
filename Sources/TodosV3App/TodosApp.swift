import Dependencies
import Foundation
import InstantSwiftData

public struct TodosAppConfiguration: Hashable, Sendable {
  public var appID: String
  public var persistenceURL: URL?
  public var enablesLiveSync: Bool

  public init(appID: String, persistenceURL: URL? = nil, enablesLiveSync: Bool) {
    self.appID = appID
    self.persistenceURL = persistenceURL
    self.enablesLiveSync = enablesLiveSync
  }

  public static func environment(
    _ environment: [String: String] = ProcessInfo.processInfo.environment
  ) -> Self {
    let configuredAppID = environment["INSTANT_APP_ID"]?
      .trimmingCharacters(in: .whitespacesAndNewlines)
    let appID = configuredAppID.flatMap { $0.isEmpty ? nil : $0 } ?? "todos-v3-local"
    return Self(
      appID: appID,
      persistenceURL: environment["INSTANT_PERSISTENCE_PATH"].map(URL.init(fileURLWithPath:)),
      enablesLiveSync: configuredAppID?.isEmpty == false
    )
  }
}

#if canImport(SwiftUI)
  import SwiftUI

  @MainActor
  public final class TodosBootstrapModel: ObservableObject {
    @Published public private(set) var client: InstantSwiftDataClient?
    @Published public private(set) var errorMessage: String?

    public let configuration: TodosAppConfiguration
    private var task: Task<Void, Never>?

    public init(configuration: TodosAppConfiguration) {
      self.configuration = configuration
    }

    public func startIfNeeded() {
      guard client == nil, task == nil else { return }
      task = Task { @MainActor [weak self, configuration] in
        do {
          var dependencies = DependencyValues()
          if configuration.enablesLiveSync {
            dependencies.instantLiveTransport = .live
          }
          try await dependencies.bootstrapInstantSwiftData(
            appID: configuration.appID,
            persistenceURL: configuration.persistenceURL,
            initialAttributes: Todo.instantAttributes
          )
          let client = dependencies.defaultInstantSwiftData
          prepareDependencies { $0.defaultInstantSwiftData = client }
          self?.client = client
          self?.task = nil
        } catch {
          self?.errorMessage = String(describing: error)
          self?.task = nil
        }
      }
    }
  }

  @MainActor
  @available(iOS 16.0, macOS 13.0, tvOS 16.0, watchOS 9.0, *)
  public struct TodosBootstrapScreen: View {
    @StateObject private var model: TodosBootstrapModel

    public init(model: TodosBootstrapModel) {
      _model = StateObject(wrappedValue: model)
    }

    public var body: some View {
      Group {
        if let client = model.client {
          // Standalone Todos host: inject the bootstrapped client into the
          // SwiftUI dependency tree (same pattern as RecipesV3).
          TodosScreen()
            .dependency(\.defaultInstantSwiftData, client)
        } else if let errorMessage = model.errorMessage {
          Text(errorMessage)
        } else {
          ProgressView("Opening Todos")
        }
      }
      .task { model.startIfNeeded() }
    }
  }

  @MainActor
  @available(iOS 16.0, macOS 13.0, tvOS 16.0, watchOS 9.0, *)
  public struct TodosScreen: View {
    @FetchAll(Todo.query.order(.serverCreatedAt, .descending)) private var todos: [Todo]
    @Room private var room: InstantRoom<TodosRoom>
    @Presence private var peers: [TodoViewerPresence]
    @Dependency(\.defaultInstantSwiftData) private var db
    @Dependency(\.date.now) private var now
    @Dependency(\.uuid) private var uuid

    @State private var text = ""
    @State private var message = ""
    private let wrapsInNavigationStack: Bool

    public init(wrapsInNavigationStack: Bool = true) {
      self.wrapsInNavigationStack = wrapsInNavigationStack
    }

    public var body: some View {
      Group {
        if wrapsInNavigationStack {
          NavigationStack { content }
        } else {
          content
        }
      }
      .instantRoom(
        $room,
        InstantRoom<TodosRoom>(type: TodosRoom.roomType, id: "main")
      )
      .presence($peers, in: room, publishing: TodoViewerPresence())
    }

    private var content: some View {
      List {
        Section("\(peers.count + 1) viewing") {
          TextField("What needs doing?", text: $text)
          Button("Add todo", action: addTodoButtonTapped)
            .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
          if !todos.isEmpty {
            Button("Delete all todos", role: .destructive, action: deleteAllTodosButtonTapped)
          }
        }
        ForEach(todos) { todo in
          Button(action: { todoButtonTapped(todo) }) {
            Label(
              todo.text,
              systemImage: todo.isCompleted ? "checkmark.circle.fill" : "circle"
            )
          }
          .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
              deleteTodoButtonTapped(todo)
            } label: {
              Label("Delete", systemImage: "trash")
            }
          }
          .contextMenu {
            Button("Delete", role: .destructive) {
              deleteTodoButtonTapped(todo)
            }
          }
        }
        if !message.isEmpty {
          Text(message)
        }
      }
      .navigationTitle("Todos")
    }

    private func addTodoButtonTapped() {
      let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !value.isEmpty else { return }
      db.send(
        CreateTodo(
          id: InstantID(rawValue: uuid().uuidString.lowercased()),
          text: value,
          createdAt: now
        ),
        onOptimisticCommit: { _ in text = "" },
        onServerAccepted: { _ in message = "Todo synced" },
        onFailure: { error in message = error.recoveryMessage }
      )
    }

    private func todoButtonTapped(_ todo: Todo) {
      db.send(
        SetTodoCompletion(id: todo.id, isCompleted: !todo.isCompleted),
        onServerAccepted: { _ in message = "Todo updated" },
        onFailure: { error in message = error.recoveryMessage }
      )
    }

    private func deleteTodoButtonTapped(_ todo: Todo) {
      db.send(
        DeleteTodo(id: todo.id),
        onOptimisticCommit: { _ in message = "Deleted todo" },
        onServerAccepted: { _ in message = "Delete synced" },
        onFailure: { error in message = error.recoveryMessage }
      )
    }

    private func deleteAllTodosButtonTapped() {
      let ids = todos.map(\.id)
      guard !ids.isEmpty else { return }
      // Single outbox mutation (not N× send). Prevents a live refresh from
      // re-showing server todos between individual pending deletes — the
      // "delete all → add one → everything comes back" flash.
      db.send(
        DeleteTodos(ids: ids),
        onOptimisticCommit: { _ in
          message = "Deleted \(ids.count) todos (local)"
        },
        onServerAccepted: { _ in
          message = "Deleted \(ids.count) todos (synced)"
        },
        onFailure: { error in
          message = "Delete all failed: \(error.recoveryMessage)"
        }
      )
    }
  }
#endif
