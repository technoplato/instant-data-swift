import Dependencies
import Foundation
import InstantSwiftData
import TodosV3App

@MainActor
private final class TodosV3MessageOutcome {
  var accepted = false
  var failure: InstantError?
}

public struct InstantTodosV3LiveValidationDetails: Codable, Equatable, Sendable {
  public var direction: String
  public var id: String
  public var text: String
  public var isCompleted: Bool
  public var createdAtMilliseconds: Int64
  public var connectionState: String
  public var pendingMutationCount: Int

  public init(
    direction: String,
    id: String,
    text: String,
    isCompleted: Bool,
    createdAtMilliseconds: Int64,
    connectionState: String,
    pendingMutationCount: Int
  ) {
    self.direction = direction
    self.id = id
    self.text = text
    self.isCompleted = isCompleted
    self.createdAtMilliseconds = createdAtMilliseconds
    self.connectionState = connectionState
    self.pendingMutationCount = pendingMutationCount
  }
}

public enum InstantTodosV3LiveValidation {
  public static func write(
    appID: String,
    apiURI: URL,
    websocketURI: URL,
    refreshToken: String,
    expectedUserID: String,
    id: String,
    text: String,
    createdAtMilliseconds: Int64,
    persistenceURL: URL? = nil
  ) async throws -> ValidationEvidenceRow<InstantTodosV3LiveValidationDetails> {
    let client = try await liveClient(
      appID: appID,
      apiURI: apiURI,
      websocketURI: websocketURI,
      persistenceURL: persistenceURL
    )
    try await authenticate(
      client,
      refreshToken: refreshToken,
      expectedUserID: expectedUserID
    )

    let todoID = InstantID<Todo>(rawValue: id)
    try await sendAndRequireServerAcceptance(
      CreateTodo(
        id: todoID,
        text: text,
        createdAt: Date(timeIntervalSince1970: Double(createdAtMilliseconds) / 1_000)
      ),
      using: client,
      operation: "create Todos V3 todo"
    )
    try await sendAndRequireServerAcceptance(
      SetTodoCompletion(id: todoID, isCompleted: true),
      using: client,
      operation: "complete Todos V3 todo"
    )

    return try await evidence(
      direction: "swift-to-typescript",
      id: id,
      text: text,
      isCompleted: true,
      createdAtMilliseconds: createdAtMilliseconds,
      appID: appID,
      client: client,
      event: "app-todo-completed"
    )
  }

  public static func observe(
    appID: String,
    apiURI: URL,
    websocketURI: URL,
    refreshToken: String,
    expectedUserID: String,
    id: String,
    text: String,
    createdAtMilliseconds: Int64,
    persistenceURL: URL? = nil
  ) -> AsyncThrowingStream<
    ValidationEvidenceRow<InstantTodosV3LiveValidationDetails>,
    Error
  > {
    AsyncThrowingStream { continuation in
      let task = Task {
        do {
          let client = try await liveClient(
            appID: appID,
            apiURI: apiURI,
            websocketURI: websocketURI,
            persistenceURL: persistenceURL
          )
          try await authenticate(
            client,
            refreshToken: refreshToken,
            expectedUserID: expectedUserID
          )

          let rows = FetchAll<Todo>()
          let rowsTask = Task {
            try await rows.task(
              Todo.query.order(.serverCreatedAt, .descending),
              using: client
            )
          }
          defer { rowsTask.cancel() }

          continuation.yield(
            try await evidence(
              direction: "typescript-to-swift",
              id: id,
              text: text,
              isCompleted: false,
              createdAtMilliseconds: createdAtMilliseconds,
              appID: appID,
              client: client,
              event: "observer-ready"
            )
          )

          let observed = try await waitForTodo(
            id: id,
            text: text,
            isCompleted: false,
            createdAtMilliseconds: createdAtMilliseconds,
            rows: rows
          )
          continuation.yield(
            try await evidence(
              direction: "typescript-to-swift",
              id: observed.id.rawValue,
              text: observed.text,
              isCompleted: observed.isCompleted,
              createdAtMilliseconds: milliseconds(observed.createdAt),
              appID: appID,
              client: client,
              event: "typescript-todo-observed"
            )
          )
          rowsTask.cancel()
          _ = try? await rowsTask.value
          _ = try await client.closeConnection()
          continuation.finish()
        } catch {
          continuation.finish(throwing: error)
        }
      }
      continuation.onTermination = { _ in task.cancel() }
    }
  }

  private static func liveClient(
    appID: String,
    apiURI: URL,
    websocketURI: URL,
    persistenceURL: URL?
  ) async throws -> InstantSwiftDataClient {
    try await withDependencies {
      $0.context = .live
      $0.instantLiveTransport = .live
      try await $0.bootstrapInstantSwiftData(
        appID: appID,
        apiURI: apiURI,
        websocketURI: websocketURI,
        persistenceURL: persistenceURL
          ?? FileManager.default.temporaryDirectory
          .appendingPathComponent("instant-todos-v3-live-\(UUID().uuidString).sqlite"),
        context: .live,
        initialAttributes: Todo.instantAttributes
      )
    } operation: {
      @Dependency(\.defaultInstantSwiftData) var client
      return client
    }
  }

  private static func authenticate(
    _ client: InstantSwiftDataClient,
    refreshToken: String,
    expectedUserID: String
  ) async throws {
    let session = try await client.signInWithRefreshToken(
      refreshToken,
      userID: "untrusted-todos-v3-user"
    )
    guard session.userID == expectedUserID else {
      throw validationFailure(
        operation: "authenticate Todos V3",
        message: "Server-verified Todos user did not match the expected user."
      )
    }
    _ = try await client.connect()
    let deadline = ContinuousClock.now + .seconds(15)
    while ContinuousClock.now < deadline {
      if try await client.connectionStatus().state == .authenticated { return }
      try await Task.sleep(for: .milliseconds(25))
    }
    throw validationFailure(
      operation: "wait for Todos V3 authentication",
      message: "The live client did not reach authenticated state."
    )
  }

  private static func sendAndRequireServerAcceptance<Message: InstantMessage>(
    _ message: Message,
    using client: InstantSwiftDataClient,
    operation: String
  ) async throws {
    let outcome = await MainActor.run { TodosV3MessageOutcome() }
    let task = client.send(
      message,
      onServerAccepted: { _ in outcome.accepted = true },
      onFailure: { outcome.failure = $0 }
    )
    defer { task.cancel() }

    try await withThrowingTaskGroup(of: Void.self) { group in
      group.addTask { await task.value }
      group.addTask {
        try await Task.sleep(for: .seconds(15))
        throw validationFailure(
          operation: operation,
          message: "Timed out waiting for server acceptance."
        )
      }
      _ = try await group.next()
      group.cancelAll()
    }

    let result = await MainActor.run { (outcome.accepted, outcome.failure) }
    if let failure = result.1 { throw failure }
    guard result.0 else {
      throw validationFailure(
        operation: operation,
        message: "The message completed without server acceptance."
      )
    }
  }

  private static func waitForTodo(
    id: String,
    text: String,
    isCompleted: Bool,
    createdAtMilliseconds: Int64,
    rows: FetchAll<Todo>
  ) async throws -> Todo {
    for _ in 0..<800 {
      if let todo = rows.wrappedValue.first(where: {
        $0.id.rawValue == id
          && $0.text == text
          && $0.isCompleted == isCompleted
          && milliseconds($0.createdAt) == createdAtMilliseconds
      }) {
        return todo
      }
      if let error = rows.loadError { throw error }
      try await Task.sleep(for: .milliseconds(25))
    }
    throw validationFailure(
      operation: "observe TypeScript Todos V3 write",
      message: "Timed out waiting for the exact TypeScript-created todo."
    )
  }

  private static func evidence(
    direction: String,
    id: String,
    text: String,
    isCompleted: Bool,
    createdAtMilliseconds: Int64,
    appID: String,
    client: InstantSwiftDataClient,
    event: String
  ) async throws -> ValidationEvidenceRow<InstantTodosV3LiveValidationDetails> {
    let status = try await client.connectionStatus()
    let pendingMutationCount = await client.pendingMutations().count
    guard status.state == .authenticated, pendingMutationCount == 0 else {
      throw validationFailure(
        operation: "record Todos V3 evidence",
        message:
          "Expected authenticated with zero pending mutations, found "
          + "\(status.state.rawValue) and \(pendingMutationCount) pending."
      )
    }
    return ValidationEvidenceRow(
      caseID: "validation.live.todos-v3",
      side: "swift",
      event: event,
      appID: appID,
      entityID: id,
      timestampMs: milliseconds(Date()),
      ok: true,
      details: InstantTodosV3LiveValidationDetails(
        direction: direction,
        id: id,
        text: text,
        isCompleted: isCompleted,
        createdAtMilliseconds: createdAtMilliseconds,
        connectionState: status.state.rawValue,
        pendingMutationCount: pendingMutationCount
      )
    )
  }

  private static func milliseconds(_ date: Date) -> Int64 {
    Int64((date.timeIntervalSince1970 * 1_000).rounded())
  }

  private static func validationFailure(operation: String, message: String) -> InstantError {
    InstantError(
      code: .validationFailed,
      operation: operation,
      message: message,
      recovery: "Inspect the Todos V3 app messages and live contract."
    )
  }
}
