import Foundation
import InstantSwiftDataCore
import InstantSwiftDataSchema

@main
struct InstantSwiftDataCLI {
  static func main() async {
    do {
      try await run()
    } catch let error as CLIError {
      writeError(error.description)
      exit(error.exitCode)
    } catch let error as InstantError {
      writeError(error.description)
      exit(exitCode(for: error))
    } catch {
      writeError("instant-swift-data: \(error)")
      exit(70)
    }
  }

  private static func run() async throws {
    var arguments = Array(CommandLine.arguments.dropFirst())
    let output = OutputMode.consume(from: &arguments)

    guard let command = arguments.popFirstArgument() else {
      printHelp()
      return
    }

    switch command {
    case "help", "--help", "-h":
      printHelp()

    case "schema":
      try runSchema(arguments: arguments)

    case "examples":
      try await runExamples(arguments: arguments, output: output)

    default:
      throw CLIError("Unknown command: \(command)", exitCode: 64)
    }
  }

  private static func runSchema(arguments: [String]) throws {
    var arguments = arguments
    guard arguments.popFirstArgument() == "generate" else {
      throw CLIError("Usage: instant-swift-data schema generate --example todos", exitCode: 64)
    }
    guard arguments.popFirstArgument() == "--example", arguments.popFirstArgument() == "todos" else {
      throw CLIError("Only '--example todos' is implemented in this core slice.", exitCode: 64)
    }

    let schema = InstantEntitySchema(
      typeName: "Todo",
      attributes: TodoExample.attributes
    )
    print(TypeScriptSchemaPrinter().printSchema([schema]))
  }

  private static func runExamples(arguments: [String], output: OutputMode) async throws {
    var arguments = arguments
    guard arguments.popFirstArgument() == "todos" else {
      throw CLIError("Usage: instant-swift-data examples todos <add|list|complete|refresh>", exitCode: 64)
    }
    guard let command = arguments.popFirstArgument() else {
      throw CLIError("Usage: instant-swift-data examples todos <add|list|complete|refresh>", exitCode: 64)
    }

    let context = try await CLIContext.bootstrap()

    switch command {
    case "add":
      let text = arguments.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
      guard !text.isEmpty else {
        throw CLIError("Usage: instant-swift-data examples todos add \"todo text\"", exitCode: 64)
      }
      let transactionID = context.runtime.configuration.makeID()
      let todoID = context.runtime.configuration.makeID()
      let now = context.runtime.configuration.now()
      let transaction = InstantStoreTransaction(
        id: transactionID,
        operations: TodoExample.createOperations(
          id: todoID,
          text: text,
          createdAt: now,
          transactionID: transactionID
        )
      )
      try await context.runtime.transact(transaction, createdAt: now, source: "cli.examples.todos.add")
      try await printTodos(context: context, output: output, event: "add", changedID: todoID)

    case "list":
      try await printTodos(context: context, output: output, event: "list")

    case "complete":
      guard let todoID = arguments.popFirstArgument() else {
        throw CLIError("Usage: instant-swift-data examples todos complete <todo-id>", exitCode: 64)
      }
      let currentTodos = try await TodoExample.decode(context.runtime.query(TodoExample.query))
      guard currentTodos.contains(where: { $0.id == todoID }) else {
        throw CLIError("Todo not found: \(todoID)", exitCode: 66)
      }
      let transactionID = context.runtime.configuration.makeID()
      let now = context.runtime.configuration.now()
      let transaction = InstantStoreTransaction(
        id: transactionID,
        operations: TodoExample.completeOperations(
          id: todoID,
          updatedAt: now,
          transactionID: transactionID
        )
      )
      try await context.runtime.transact(
        transaction,
        createdAt: now,
        source: "cli.examples.todos.complete"
      )
      try await printTodos(context: context, output: output, event: "complete", changedID: todoID)

    case "refresh":
      try await printTodos(context: context, output: output, event: "refresh")

    default:
      throw CLIError("Unknown todos command: \(command)", exitCode: 64)
    }
  }

  private static func printTodos(
    context: CLIContext,
    output: OutputMode,
    event: String,
    changedID: String? = nil
  ) async throws {
    let snapshots = await context.runtime.query(TodoExample.query)
    let todos = try TodoExample.decode(snapshots)
    let pending = await context.runtime.pendingMutations()
    let payload = TodosOutput(
      appID: context.appID,
      cachePath: context.cacheURL.path,
      event: event,
      changedID: changedID,
      transport: "not-implemented-local-cache-only",
      pendingMutationCount: pending.count,
      todos: todos
    )

    switch output {
    case .human:
      if todos.isEmpty {
        print("No todos.")
      } else {
        for todo in todos {
          let mark = todo.isCompleted ? "[x]" : "[ ]"
          print("\(mark) \(todo.id) \(todo.text)")
        }
      }
      print("pending mutations: \(pending.count)")
      print("cache: \(context.cacheURL.path)")

    case .json:
      try writeJSON(payload)

    case .jsonl:
      try writeJSONLine(
        EvidenceRow(
          caseID: "cli.examples.todos",
          side: "swift",
          event: event,
          appID: context.appID,
          ok: true,
          details: payload
        )
      )
      for todo in todos {
        try writeJSONLine(
          EvidenceRow(
            caseID: "cli.examples.todos",
            side: "swift",
            event: "todo",
            appID: context.appID,
            entityID: todo.id,
            ok: true,
            details: todo
          )
        )
      }
    }
  }

  private static func printHelp() {
    print(
      """
      instant-swift-data

      Commands:
        schema generate --example todos
        examples todos add "do the dishes" [--json|--jsonl]
        examples todos list [--json|--jsonl]
        examples todos complete <todo-id> [--json|--jsonl]
        examples todos refresh [--json|--jsonl]

      Environment:
        INSTANT_SWIFT_DATA_HOME  Directory for CLI SQLite state. Defaults to ~/.instant-swift-data.
        INSTANT_APP_ID           Logical app id recorded in output. Defaults to local-demo.
      """
    )
  }

  private static func writeJSON<Value: Encodable>(_ value: Value) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(value)
    FileHandle.standardOutput.write(data)
    FileHandle.standardOutput.write(Data("\n".utf8))
  }

  private static func writeJSONLine<Value: Encodable>(_ value: Value) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let data = try encoder.encode(value)
    FileHandle.standardOutput.write(data)
    FileHandle.standardOutput.write(Data("\n".utf8))
  }

  private static func writeError(_ string: String) {
    FileHandle.standardError.write(Data((string + "\n").utf8))
  }

  private static func exitCode(for error: InstantError) -> Int32 {
    switch error.code {
    case .authFailed:
      65
    case .validationFailed, .decodeFailed:
      66
    case .networkFailed:
      69
    case .permissionRejected:
      77
    case .persistenceFailed:
      74
    case .implementationFailed:
      70
    }
  }
}

private struct CLIContext: Sendable {
  var appID: String
  var cacheURL: URL
  var runtime: InstantRuntime

  static func bootstrap() async throws -> Self {
    let environment = ProcessInfo.processInfo.environment
    let appID = environment["INSTANT_APP_ID"] ?? "local-demo"
    let homeURL = environment["INSTANT_SWIFT_DATA_HOME"].map(URL.init(fileURLWithPath:))
      ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".instant-swift-data")
    let cacheURL = homeURL.appendingPathComponent("state.sqlite")
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: appID,
        persistenceURL: cacheURL,
        initialAttributes: TodoExample.attributes
      )
    )
    return Self(appID: appID, cacheURL: cacheURL, runtime: runtime)
  }
}

private enum OutputMode: Sendable {
  case human
  case json
  case jsonl

  static func consume(from arguments: inout [String]) -> Self {
    if let index = arguments.firstIndex(of: "--jsonl") {
      arguments.remove(at: index)
      return .jsonl
    }
    if let index = arguments.firstIndex(of: "--json") {
      arguments.remove(at: index)
      return .json
    }
    return .human
  }
}

private struct TodosOutput: Codable, Sendable {
  var appID: String
  var cachePath: String
  var event: String
  var changedID: String?
  var transport: String
  var pendingMutationCount: Int
  var todos: [TodoRecord]
}

private struct EvidenceRow<Details: Encodable & Sendable>: Encodable, Sendable {
  var caseID: String
  var side: String
  var event: String
  var appID: String
  var entityID: String?
  var timestampMs: Int64
  var ok: Bool
  var details: Details

  init(
    caseID: String,
    side: String,
    event: String,
    appID: String,
    entityID: String? = nil,
    ok: Bool,
    details: Details
  ) {
    self.caseID = caseID
    self.side = side
    self.event = event
    self.appID = appID
    self.entityID = entityID
    self.timestampMs = Int64((Date().timeIntervalSince1970 * 1000).rounded())
    self.ok = ok
    self.details = details
  }

  enum CodingKeys: String, CodingKey {
    case caseID = "case"
    case side
    case event
    case appID
    case entityID
    case timestampMs
    case ok
    case details
  }
}

private struct CLIError: Error, CustomStringConvertible {
  var description: String
  var exitCode: Int32

  init(_ description: String, exitCode: Int32) {
    self.description = description
    self.exitCode = exitCode
  }
}

private extension Array {
  mutating func popFirstArgument() -> Element? {
    guard !isEmpty else { return nil }
    return removeFirst()
  }
}
