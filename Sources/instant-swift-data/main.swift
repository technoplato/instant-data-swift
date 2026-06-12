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
      try runSchema(arguments: arguments, output: output)

    case "perms", "permissions":
      try runPermissions(arguments: arguments)

    case "examples":
      try await runExamples(arguments: arguments, output: output)

    case "cache":
      try await runCache(arguments: arguments, output: output)

    case "outbox":
      try await runOutbox(arguments: arguments, output: output)

    default:
      throw CLIError("Unknown command: \(command)", exitCode: 64)
    }
  }

  private static func runSchema(arguments: [String], output: OutputMode) throws {
    if arguments.first == "verify" {
      let options = try SchemaVerifyOptions.parse(arguments: arguments)
      try requireTodoExample(options.example)
      try verifySchema(options: options, output: output)
      return
    }

    let options = try GenerateOptions.parse(
      arguments: arguments,
      usage: "Usage: instant-swift-data schema generate --example todos [--to instant.schema.ts]"
    )
    try requireTodoExample(options.example)

    try writeGenerated(
      try TypeScriptSchemaPrinter().printSchema(InstantSchemaExamples.todosDocument),
      to: options.outputPath
    )
  }

  private static func runPermissions(arguments: [String]) throws {
    let options = try GenerateOptions.parse(
      arguments: arguments,
      usage: "Usage: instant-swift-data perms generate --example todos [--to instant.perms.ts]"
    )
    try requireTodoExample(options.example)

    try writeGenerated(
      try TypeScriptPermissionsPrinter().printPermissions(InstantSchemaExamples.todoPermissions),
      to: options.outputPath
    )
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
      let query = try todoListQuery(arguments: arguments)
      try await printTodos(context: context, output: output, event: "list", query: query)

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
      let query = try todoListQuery(arguments: arguments)
      try await printTodos(context: context, output: output, event: "refresh", query: query)

    default:
      throw CLIError("Unknown todos command: \(command)", exitCode: 64)
    }
  }

  private static func runCache(arguments: [String], output: OutputMode) async throws {
    var arguments = arguments
    guard arguments.popFirstArgument() == "inspect", arguments.isEmpty else {
      throw CLIError("Usage: instant-swift-data cache inspect [--json|--jsonl]", exitCode: 64)
    }

    let context = try await CLIContext.bootstrap()
    let snapshot = try await context.runtime.persistence.loadSnapshot()
    let summary = CacheInspectOutput(
      appID: context.appID,
      cachePath: context.cacheURL.path,
      transport: "not-implemented-local-cache-only",
      attributeCount: snapshot.store.attributes.count,
      tripleCount: snapshot.store.triples.count,
      outboxMutationCount: snapshot.outbox.count,
      namespaces: namespaceSummaries(snapshot.store)
    )

    switch output {
    case .human:
      print("cache: \(summary.cachePath)")
      print("attributes: \(summary.attributeCount)")
      print("triples: \(summary.tripleCount)")
      print("outbox mutations: \(summary.outboxMutationCount)")
      if summary.namespaces.isEmpty {
        print("namespaces: none")
      } else {
        print("namespaces:")
        for namespace in summary.namespaces {
          print(
            "  \(namespace.namespace) entities=\(namespace.entityCount) triples=\(namespace.tripleCount)"
          )
        }
      }

    case .json:
      try writeJSON(summary)

    case .jsonl:
      try writeJSONLine(
        EvidenceRow(
          caseID: "cli.cache.inspect",
          side: "swift",
          event: "summary",
          appID: context.appID,
          ok: true,
          details: summary
        )
      )
      for namespace in summary.namespaces {
        try writeJSONLine(
          EvidenceRow(
            caseID: "cli.cache.inspect",
            side: "swift",
            event: "namespace",
            appID: context.appID,
            entityID: namespace.namespace,
            ok: true,
            details: namespace
          )
        )
      }
    }
  }

  private static func runOutbox(arguments: [String], output: OutputMode) async throws {
    var arguments = arguments
    guard let command = arguments.popFirstArgument() else {
      throw CLIError(outboxUsage, exitCode: 64)
    }

    let context = try await CLIContext.bootstrap()

    switch command {
    case "inspect":
      guard arguments.isEmpty else {
        throw CLIError("Usage: instant-swift-data outbox inspect [--json|--jsonl]", exitCode: 64)
      }
      try await printOutbox(context: context, output: output)

    case "confirm":
      guard let mutationID = arguments.popFirstArgument(), arguments.isEmpty else {
        throw CLIError("Usage: instant-swift-data outbox confirm <mutation-id> [--json|--jsonl]", exitCode: 64)
      }
      let mutation = try await context.runtime.confirmMutation(id: mutationID)
      try await printOutboxUpdate(
        context: context,
        output: output,
        event: "confirm",
        mutation: mutation
      )

    case "fail":
      guard let mutationID = arguments.popFirstArgument() else {
        throw CLIError(
          "Usage: instant-swift-data outbox fail <mutation-id> \"reason\" [--json|--jsonl]",
          exitCode: 64
        )
      }
      let message = arguments.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
      guard !message.isEmpty else {
        throw CLIError(
          "Usage: instant-swift-data outbox fail <mutation-id> \"reason\" [--json|--jsonl]",
          exitCode: 64
        )
      }
      let mutation = try await context.runtime.failMutation(id: mutationID, message: message)
      try await printOutboxUpdate(
        context: context,
        output: output,
        event: "fail",
        mutation: mutation
      )

    default:
      throw CLIError(outboxUsage, exitCode: 64)
    }
  }

  private static func printOutbox(
    context: CLIContext,
    output: OutputMode
  ) async throws {
    let mutations = await context.runtime.outboxMutations()
    let summary = OutboxInspectOutput(
      appID: context.appID,
      cachePath: context.cacheURL.path,
      transport: "not-implemented-local-cache-only",
      pendingMutationCount: mutations.filter { $0.status == .pending }.count,
      mutationCount: mutations.count,
      mutations: mutations
    )

    switch output {
    case .human:
      print("outbox: \(summary.cachePath)")
      print("mutations: \(summary.mutationCount)")
      print("pending mutations: \(summary.pendingMutationCount)")
      for mutation in summary.mutations {
        print(
          "- \(mutation.id) status=\(mutation.status.rawValue) createdAtMs=\(mutation.createdAt.milliseconds) operations=\(mutation.transaction.operations.count)"
        )
      }

    case .json:
      try writeJSON(summary)

    case .jsonl:
      try writeJSONLine(
        EvidenceRow(
          caseID: "cli.outbox.inspect",
          side: "swift",
          event: "summary",
          appID: context.appID,
          ok: true,
          details: summary
        )
      )
      for mutation in summary.mutations {
        try writeJSONLine(
          EvidenceRow(
            caseID: "cli.outbox.inspect",
            side: "swift",
            event: "mutation",
            appID: context.appID,
            entityID: mutation.id,
            ok: true,
            details: mutation
          )
        )
      }
    }
  }

  private static func printOutboxUpdate(
    context: CLIContext,
    output: OutputMode,
    event: String,
    mutation: PendingMutation
  ) async throws {
    let mutations = await context.runtime.outboxMutations()
    let update = OutboxUpdateOutput(
      appID: context.appID,
      cachePath: context.cacheURL.path,
      event: event,
      transport: "not-implemented-local-cache-only",
      pendingMutationCount: mutations.filter { $0.status == .pending }.count,
      mutationCount: mutations.count,
      mutation: mutation
    )

    switch output {
    case .human:
      print("outbox: \(update.cachePath)")
      print("event: \(event)")
      print("mutation: \(mutation.id)")
      print("status: \(mutation.status.rawValue)")
      if let failureMessage = mutation.failureMessage {
        print("failure: \(failureMessage)")
      }
      print("pending mutations: \(update.pendingMutationCount)")

    case .json:
      try writeJSON(update)

    case .jsonl:
      try writeJSONLine(
        EvidenceRow(
          caseID: "cli.outbox.update",
          side: "swift",
          event: event,
          appID: context.appID,
          entityID: mutation.id,
          ok: true,
          details: update
        )
      )
    }
  }

  private static func printTodos(
    context: CLIContext,
    output: OutputMode,
    event: String,
    changedID: String? = nil,
    query: InstantQueryPlan = TodoExample.query
  ) async throws {
    let snapshots = await context.runtime.query(query)
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
        schema generate --example todos [--to instant.schema.ts]
        schema verify --example todos --from instant.schema.ts [--json|--jsonl]
        perms generate --example todos [--to instant.perms.ts]
        examples todos add "do the dishes" [--json|--jsonl]
        examples todos list [--completed true|false] [--limit n] [--order asc|desc] [--json|--jsonl]
        examples todos complete <todo-id> [--json|--jsonl]
        examples todos refresh [--completed true|false] [--limit n] [--order asc|desc] [--json|--jsonl]
        cache inspect [--json|--jsonl]
        outbox inspect [--json|--jsonl]
        outbox confirm <mutation-id> [--json|--jsonl]
        outbox fail <mutation-id> "reason" [--json|--jsonl]

      Environment:
        INSTANT_SWIFT_DATA_HOME  Directory for CLI SQLite state. Defaults to ~/.instant-swift-data.
        INSTANT_APP_ID           Logical app id recorded in output. Defaults to local-demo.
      """
    )
  }

  private static func requireTodoExample(_ example: String) throws {
    guard example == "todos" else {
      throw CLIError("Only '--example todos' is implemented in this core slice.", exitCode: 64)
    }
  }

  private static func writeGenerated(_ contents: String, to outputPath: String?) throws {
    let data = Data(contents.utf8)
    guard let outputPath else {
      FileHandle.standardOutput.write(data)
      return
    }

    let currentDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    let url = URL(fileURLWithPath: outputPath, relativeTo: currentDirectory).standardizedFileURL
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try data.write(to: url, options: .atomic)
  }

  private static func verifySchema(options: SchemaVerifyOptions, output: OutputMode) throws {
    let currentDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    let url = URL(fileURLWithPath: options.inputPath, relativeTo: currentDirectory)
      .standardizedFileURL
    let source = try String(contentsOf: url, encoding: .utf8)
    let parsed: ParsedInstantSchemaDocument
    do {
      parsed = try TypeScriptSchemaParser().parseDocument(source)
    } catch let error as TypeScriptSchemaParseError {
      throw CLIError("Schema parse failed: \(error.description)", exitCode: 66)
    }

    let expected = ParsedInstantSchemaDocument(InstantSchemaExamples.todosDocument)
    guard parsed == expected else {
      throw CLIError("Schema does not match --example todos.", exitCode: 66)
    }

    let summary = SchemaVerifyOutput(
      example: options.example,
      path: url.path,
      entityCount: parsed.entities.count,
      attributeCount: parsed.entities.reduce(0) { $0 + $1.attributes.count },
      linkCount: parsed.links.count
    )

    switch output {
    case .human:
      print("schema: ok")
      print("example: \(summary.example)")
      print("entities: \(summary.entityCount)")
      print("attributes: \(summary.attributeCount)")
      print("links: \(summary.linkCount)")
      print("path: \(summary.path)")

    case .json:
      try writeJSON(summary)

    case .jsonl:
      try writeJSONLine(
        EvidenceRow(
          caseID: "cli.schema.verify",
          side: "swift",
          event: "summary",
          appID: "schema-tooling",
          ok: true,
          details: summary
        )
      )
    }
  }

  private static func todoListQuery(arguments: [String]) throws -> InstantQueryPlan {
    var arguments = arguments
    var completed: Bool?
    var limit: Int?
    var direction = InstantQuerySortDirection.ascending

    while let option = arguments.popFirstArgument() {
      switch option {
      case "--completed":
        guard let value = arguments.popFirstArgument(), let parsed = parseBool(value) else {
          throw CLIError("Usage: instant-swift-data examples todos list --completed true|false", exitCode: 64)
        }
        completed = parsed

      case "--limit":
        guard let value = arguments.popFirstArgument(),
          let parsed = Int(value),
          parsed >= 0
        else {
          throw CLIError("Usage: instant-swift-data examples todos list --limit n", exitCode: 64)
        }
        limit = parsed

      case "--order":
        guard let value = arguments.popFirstArgument(), let parsed = parseSortDirection(value) else {
          throw CLIError("Usage: instant-swift-data examples todos list --order asc|desc", exitCode: 64)
        }
        direction = parsed

      default:
        throw CLIError(
          "Unknown todo list option: \(option). Usage: instant-swift-data examples todos list [--completed true|false] [--limit n] [--order asc|desc]",
          exitCode: 64
        )
      }
    }

    var filters: [InstantQueryFilter] = []
    var id = "examples.todos.list"
    if let completed {
      filters.append(.equals(field: "isCompleted", value: .bool(completed)))
      id += ".completed-\(completed)"
    }
    if direction != .ascending {
      id += ".order-\(direction.rawValue)"
    }
    if let limit {
      id += ".limit-\(limit)"
    }

    return InstantQueryPlan(
      id: id,
      namespace: TodoExample.namespace,
      filters: filters,
      order: InstantQueryOrder("createdAt", direction),
      limit: limit
    )
  }

  private static func parseBool(_ value: String) -> Bool? {
    switch value.lowercased() {
    case "true", "yes", "1":
      return true
    case "false", "no", "0":
      return false
    default:
      return nil
    }
  }

  private static func parseSortDirection(_ value: String) -> InstantQuerySortDirection? {
    switch value.lowercased() {
    case "asc", "ascending":
      return .ascending
    case "desc", "descending":
      return .descending
    default:
      return nil
    }
  }

  private static var outboxUsage: String {
    """
    Usage: instant-swift-data outbox <inspect|confirm|fail>
      instant-swift-data outbox inspect [--json|--jsonl]
      instant-swift-data outbox confirm <mutation-id> [--json|--jsonl]
      instant-swift-data outbox fail <mutation-id> "reason" [--json|--jsonl]
    """
  }

  private static func namespaceSummaries(
    _ snapshot: InstantStoreSnapshot
  ) -> [CacheNamespaceSummary] {
    let attributesByID = Dictionary(uniqueKeysWithValues: snapshot.attributes.map { ($0.id, $0) })
    var entityIDsByNamespace: [String: Set<String>] = [:]
    var tripleCountsByNamespace: [String: Int] = [:]

    for triple in snapshot.triples {
      let namespace =
        attributesByID[triple.attributeID]?.namespace
        ?? triple.attributeID.split(separator: "/", maxSplits: 1).first.map(String.init)
        ?? "unknown"
      entityIDsByNamespace[namespace, default: []].insert(triple.entityID)
      tripleCountsByNamespace[namespace, default: 0] += 1
    }

    for attribute in snapshot.attributes {
      if entityIDsByNamespace[attribute.namespace] == nil {
        entityIDsByNamespace[attribute.namespace] = []
      }
      if tripleCountsByNamespace[attribute.namespace] == nil {
        tripleCountsByNamespace[attribute.namespace] = 0
      }
    }

    return entityIDsByNamespace.keys.sorted().map { namespace in
      CacheNamespaceSummary(
        namespace: namespace,
        entityCount: entityIDsByNamespace[namespace, default: []].count,
        tripleCount: tripleCountsByNamespace[namespace, default: 0],
        attributeCount: snapshot.attributes.filter { $0.namespace == namespace }.count
      )
    }
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

private struct CacheInspectOutput: Codable, Sendable {
  var appID: String
  var cachePath: String
  var transport: String
  var attributeCount: Int
  var tripleCount: Int
  var outboxMutationCount: Int
  var namespaces: [CacheNamespaceSummary]
}

private struct CacheNamespaceSummary: Codable, Sendable {
  var namespace: String
  var entityCount: Int
  var tripleCount: Int
  var attributeCount: Int
}

private struct OutboxInspectOutput: Codable, Sendable {
  var appID: String
  var cachePath: String
  var transport: String
  var pendingMutationCount: Int
  var mutationCount: Int
  var mutations: [PendingMutation]
}

private struct OutboxUpdateOutput: Codable, Sendable {
  var appID: String
  var cachePath: String
  var event: String
  var transport: String
  var pendingMutationCount: Int
  var mutationCount: Int
  var mutation: PendingMutation
}

private struct SchemaVerifyOutput: Codable, Sendable {
  var example: String
  var path: String
  var entityCount: Int
  var attributeCount: Int
  var linkCount: Int
}

private struct GenerateOptions: Sendable {
  var example: String
  var outputPath: String?

  static func parse(arguments: [String], usage: String) throws -> Self {
    var arguments = arguments
    guard arguments.popFirstArgument() == "generate" else {
      throw CLIError(usage, exitCode: 64)
    }

    var example: String?
    var outputPath: String?

    while let option = arguments.popFirstArgument() {
      switch option {
      case "--example":
        guard let value = arguments.popFirstArgument() else {
          throw CLIError(usage, exitCode: 64)
        }
        example = value

      case "--to":
        guard let value = arguments.popFirstArgument() else {
          throw CLIError(usage, exitCode: 64)
        }
        outputPath = value

      default:
        throw CLIError("Unknown generate option: \(option). \(usage)", exitCode: 64)
      }
    }

    guard let example else {
      throw CLIError(usage, exitCode: 64)
    }

    return Self(example: example, outputPath: outputPath)
  }
}

private struct SchemaVerifyOptions: Sendable {
  var example: String
  var inputPath: String

  static func parse(arguments: [String]) throws -> Self {
    let usage = "Usage: instant-swift-data schema verify --example todos --from instant.schema.ts"
    var arguments = arguments
    guard arguments.popFirstArgument() == "verify" else {
      throw CLIError(usage, exitCode: 64)
    }

    var example: String?
    var inputPath: String?

    while let option = arguments.popFirstArgument() {
      switch option {
      case "--example":
        guard let value = arguments.popFirstArgument() else {
          throw CLIError(usage, exitCode: 64)
        }
        example = value

      case "--from":
        guard let value = arguments.popFirstArgument() else {
          throw CLIError(usage, exitCode: 64)
        }
        inputPath = value

      default:
        throw CLIError("Unknown schema verify option: \(option). \(usage)", exitCode: 64)
      }
    }

    guard let example, let inputPath else {
      throw CLIError(usage, exitCode: 64)
    }

    return Self(example: example, inputPath: inputPath)
  }
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
