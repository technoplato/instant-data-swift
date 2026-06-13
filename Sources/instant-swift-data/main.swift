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

    case "init":
      try runInit(arguments: arguments, output: output)

    case "schema":
      try runSchema(arguments: arguments, output: output)

    case "perms", "permissions":
      try runPermissions(arguments: arguments, output: output)

    case "examples":
      try await runExamples(arguments: arguments, output: output)

    case "query":
      try await runQuery(arguments: arguments, output: output)

    case "admin":
      try await runAdmin(arguments: arguments, output: output)

    case "cache":
      try await runCache(arguments: arguments, output: output)

    case "outbox":
      try await runOutbox(arguments: arguments, output: output)

    case "local-id", "localid":
      try await runLocalID(arguments: arguments, output: output)

    case "auth":
      try await runAuth(arguments: arguments, output: output)

    case "app":
      try await runApp(arguments: arguments, output: output)

    case "sync":
      try await runSync(arguments: arguments, output: output)

    case "connection", "connect":
      try await runConnection(arguments: arguments, output: output)

    case "rooms", "room":
      try await runRooms(arguments: arguments, output: output)

    case "files", "storage":
      try await runFiles(arguments: arguments, output: output)

    case "streams", "stream":
      try await runStreams(arguments: arguments, output: output)

    case "shares", "share", "sharing":
      try await runShares(arguments: arguments, output: output)

    case "validation", "validate":
      try await runValidation(arguments: arguments, output: output)

    case "benchmark", "benchmarks":
      try await runBenchmark(arguments: arguments, output: output)

    default:
      throw CLIError("Unknown command: \(command)", exitCode: 64)
    }
  }

  private static func runInit(arguments: [String], output: OutputMode) throws {
    let options = try ScaffoldOptions.parse(arguments: arguments)
    try requireTodoExample(options.example)
    try scaffoldTodoExample(options: options, output: output)
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
      usage: "Usage: instant-swift-data schema generate --example todos [--to instant.schema.ts] [--json|--jsonl]"
    )
    try requireTodoExample(options.example)

    try printGeneratedArtifact(
      try TypeScriptSchemaPrinter().printSchema(InstantSchemaExamples.todosDocument),
      kind: "schema",
      fileName: "instant.schema.ts",
      example: options.example,
      to: options.outputPath,
      output: output,
      caseID: "cli.schema.generate",
      appID: "schema-tooling"
    )
  }

  private static func runPermissions(arguments: [String], output: OutputMode) throws {
    if arguments.first == "verify" {
      let options = try PermissionsVerifyOptions.parse(arguments: arguments)
      try requireTodoExample(options.example)
      try verifyPermissions(options: options, output: output)
      return
    }

    let options = try GenerateOptions.parse(
      arguments: arguments,
      usage: "Usage: instant-swift-data perms generate --example todos [--to instant.perms.ts] [--json|--jsonl]"
    )
    try requireTodoExample(options.example)

    try printGeneratedArtifact(
      try TypeScriptPermissionsPrinter().printPermissions(InstantSchemaExamples.todoPermissions),
      kind: "permissions",
      fileName: "instant.perms.ts",
      example: options.example,
      to: options.outputPath,
      output: output,
      caseID: "cli.perms.generate",
      appID: "permissions-tooling"
    )
  }

  private static func runValidation(arguments: [String], output: OutputMode) async throws {
    var arguments = arguments
    guard let command = arguments.popFirstArgument(), arguments.isEmpty else {
      throw CLIError(validationUsage, exitCode: 64)
    }

    switch command {
    case "local-todos", "todos":
      let appID = validationAppID()
      do {
        let result = try await InstantSwiftDataLocalTodoValidation.run(appID: appID)
        try printLocalTodoValidation(result: result, output: output)
      } catch {
        if output == .jsonl {
          try writeJSONLine(validationFailureRow(appID: appID, error: error))
        }
        throw error
      }

    default:
      throw CLIError(validationUsage, exitCode: 64)
    }
  }

  private static func runBenchmark(arguments: [String], output: OutputMode) async throws {
    let options = try BenchmarkOptions.parse(arguments: arguments)
    let result = try await InstantSwiftDataLocalBenchmarks.runLocalTodos(
      appID: options.appID,
      iterations: options.iterations
    )
    try printBenchmark(result: result, output: output)
  }

  private static func runQuery(arguments: [String], output: OutputMode) async throws {
    var arguments = arguments
    guard let namespace = arguments.popFirstArgument() else {
      throw CLIError(queryUsage, exitCode: 64)
    }

    switch namespace {
    case "todos":
      let options = try todoQueryOptions(
        arguments: arguments,
        usageCommand: "instant-swift-data query todos"
      )
      let context = try await CLIContext.bootstrap()
      if options.rawSnapshots {
        try await printSnapshots(
          context: context,
          output: output,
          event: "query",
          query: options.query,
          caseID: "cli.query.todos.snapshots"
        )
      } else {
        try await printTodos(
          context: context,
          output: output,
          event: "query",
          query: options.query,
          caseID: "cli.query.todos"
        )
      }

    default:
      throw CLIError(queryUsage, exitCode: 64)
    }
  }

  private static func runAdmin(arguments: [String], output: OutputMode) async throws {
    var arguments = arguments
    guard let command = arguments.popFirstArgument() else {
      throw CLIError(adminUsage, exitCode: 64)
    }

    switch command {
    case "query":
      let options = try AdminQueryOptions.parse(arguments: arguments)
      let context = try await CLIContext.bootstrap(initialAttributes: [])
      try await printSnapshots(
        context: context,
        output: output,
        event: "admin-query",
        query: options.query,
        caseID: "cli.admin.query"
      )

    case "transact", "tx":
      let options = try AdminTransactOptions.parse(arguments: arguments)
      let context = try await CLIContext.bootstrap(initialAttributes: options.attributes)
      let transactionID = context.runtime.configuration.makeID()
      let now = context.runtime.configuration.now()
      let operations = adminUpsertOperations(
        options: options,
        transactionID: transactionID,
        txTime: now
      )
      let transaction = InstantStoreTransaction(id: transactionID, operations: operations)
      let result = try await context.runtime.transact(
        transaction,
        createdAt: now,
        source: "cli.admin.transact"
      )
      try await printAdminTransact(
        context: context,
        output: output,
        options: options,
        result: result
      )

    default:
      throw CLIError(adminUsage, exitCode: 64)
    }
  }

  private static func runExamples(arguments: [String], output: OutputMode) async throws {
    var arguments = arguments
    guard let example = arguments.popFirstArgument() else {
      throw CLIError(examplesUsage, exitCode: 64)
    }
    switch example {
    case "todo-links":
      try await runTodoLinks(arguments: arguments, output: output)
      return

    case "todos":
      break

    default:
      throw CLIError(examplesUsage, exitCode: 64)
    }
    guard let command = arguments.popFirstArgument() else {
      throw CLIError("Usage: instant-swift-data examples todos <add|seed|list|watch|complete|update|delete|reset|refresh>", exitCode: 64)
    }

    let context = try await CLIContext.bootstrap()

    switch command {
    case "seed":
      guard arguments.isEmpty else {
        throw CLIError("Usage: instant-swift-data examples todos seed [--json|--jsonl]", exitCode: 64)
      }
      let transactionID = context.runtime.configuration.makeID()
      let now = context.runtime.configuration.now()
      var seedRecords: [(id: String, seed: TodoSeedRecord)] = []
      for seed in TodoExample.seedRecords {
        seedRecords.append((try await context.runtime.localID(named: seed.localIDName), seed))
      }
      let transaction = InstantStoreTransaction(
        id: transactionID,
        operations: TodoExample.seedOperations(
          records: seedRecords,
          baseCreatedAt: now,
          transactionID: transactionID
        )
      )
      try await context.runtime.transact(
        transaction,
        createdAt: now,
        source: "cli.examples.todos.seed"
      )
      try await printTodos(context: context, output: output, event: "seed")

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

    case "watch", "observe":
      let options = try todoWatchOptions(arguments: arguments)
      try await watchTodos(context: context, output: output, options: options)

    case "complete":
      guard let todoID = arguments.popFirstArgument(), arguments.isEmpty else {
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

    case "update", "edit":
      guard let todoID = arguments.popFirstArgument() else {
        throw CLIError("Usage: instant-swift-data examples todos update <todo-id> \"new text\"", exitCode: 64)
      }
      let text = arguments.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
      guard !text.isEmpty else {
        throw CLIError("Usage: instant-swift-data examples todos update <todo-id> \"new text\"", exitCode: 64)
      }
      let currentTodos = try await TodoExample.decode(context.runtime.query(TodoExample.query))
      guard currentTodos.contains(where: { $0.id == todoID }) else {
        throw CLIError("Todo not found: \(todoID)", exitCode: 66)
      }
      let transactionID = context.runtime.configuration.makeID()
      let now = context.runtime.configuration.now()
      let transaction = InstantStoreTransaction(
        id: transactionID,
        operations: TodoExample.updateTextOperations(
          id: todoID,
          text: text,
          updatedAt: now,
          transactionID: transactionID
        )
      )
      try await context.runtime.transact(
        transaction,
        createdAt: now,
        source: "cli.examples.todos.update"
      )
      try await printTodos(context: context, output: output, event: "update", changedID: todoID)

    case "delete", "remove":
      guard let todoID = arguments.popFirstArgument(), arguments.isEmpty else {
        throw CLIError("Usage: instant-swift-data examples todos delete <todo-id>", exitCode: 64)
      }
      let currentTodos = try await TodoExample.decode(context.runtime.query(TodoExample.query))
      guard currentTodos.contains(where: { $0.id == todoID }) else {
        throw CLIError("Todo not found: \(todoID)", exitCode: 66)
      }
      let transactionID = context.runtime.configuration.makeID()
      let now = context.runtime.configuration.now()
      let transaction = InstantStoreTransaction(
        id: transactionID,
        operations: TodoExample.deleteOperations(id: todoID)
      )
      try await context.runtime.transact(
        transaction,
        createdAt: now,
        source: "cli.examples.todos.delete"
      )
      try await printTodos(context: context, output: output, event: "delete", changedID: todoID)

    case "reset":
      guard arguments.isEmpty else {
        throw CLIError("Usage: instant-swift-data examples todos reset [--json|--jsonl]", exitCode: 64)
      }
      let currentTodos = try await TodoExample.decode(context.runtime.query(TodoExample.query))
      if !currentTodos.isEmpty {
        let transactionID = context.runtime.configuration.makeID()
        let now = context.runtime.configuration.now()
        let transaction = InstantStoreTransaction(
          id: transactionID,
          operations: TodoExample.resetOperations(ids: currentTodos.map(\.id))
        )
        try await context.runtime.transact(
          transaction,
          createdAt: now,
          source: "cli.examples.todos.reset"
        )
      }
      try await printTodos(context: context, output: output, event: "reset")

    case "refresh":
      let query = try todoListQuery(arguments: arguments)
      try await printTodos(context: context, output: output, event: "refresh", query: query)

    default:
      throw CLIError("Unknown todos command: \(command)", exitCode: 64)
    }
  }

  private static func runTodoLinks(arguments: [String], output: OutputMode) async throws {
    var arguments = arguments
    guard let command = arguments.popFirstArgument() else {
      throw CLIError(todoLinksUsage, exitCode: 64)
    }
    let context = try await CLIContext.bootstrap(initialAttributes: TodoProjectExample.attributes)

    switch command {
    case "seed":
      guard arguments.isEmpty else {
        throw CLIError("Usage: instant-swift-data examples todo-links seed [--json|--jsonl]", exitCode: 64)
      }
      let projectID = try await context.runtime.localID(named: TodoProjectExample.projectIDName)
      let todoID = try await context.runtime.localID(named: TodoProjectExample.todoIDName)
      let transactionID = context.runtime.configuration.makeID()
      let now = context.runtime.configuration.now()
      let transaction = InstantStoreTransaction(
        id: transactionID,
        operations: TodoProjectExample.upsertProjectOperations(
          id: projectID,
          title: "Launch linked todos",
          createdAt: now,
          transactionID: transactionID
        ) + TodoExample.upsertOperations(
          id: todoID,
          text: "Wire a project link",
          createdAt: now,
          transactionID: transactionID
        ) + TodoProjectExample.linkOperations(
          todoID: todoID,
          projectID: projectID,
          updatedAt: now,
          transactionID: transactionID
        )
      )
      try await context.runtime.transact(
        transaction,
        createdAt: now,
        source: "cli.examples.todo-links.seed"
      )
      try await printTodoLinks(context: context, output: output, event: "seed", changedID: todoID)

    case "list":
      guard arguments.isEmpty else {
        throw CLIError("Usage: instant-swift-data examples todo-links list [--json|--jsonl]", exitCode: 64)
      }
      try await printTodoLinks(context: context, output: output, event: "list")

    case "nested":
      guard arguments.isEmpty else {
        throw CLIError("Usage: instant-swift-data examples todo-links nested [--json|--jsonl]", exitCode: 64)
      }
      try await printTodoLinkSnapshots(context: context, output: output, event: "nested")

    case "unlink":
      guard arguments.isEmpty else {
        throw CLIError("Usage: instant-swift-data examples todo-links unlink [--json|--jsonl]", exitCode: 64)
      }
      let projectID = try await context.runtime.localID(named: TodoProjectExample.projectIDName)
      let todoID = try await context.runtime.localID(named: TodoProjectExample.todoIDName)
      let transactionID = context.runtime.configuration.makeID()
      let now = context.runtime.configuration.now()
      let transaction = InstantStoreTransaction(
        id: transactionID,
        operations: TodoProjectExample.unlinkOperations(
          todoID: todoID,
          projectID: projectID,
          updatedAt: now,
          transactionID: transactionID
        )
      )
      try await context.runtime.transact(
        transaction,
        createdAt: now,
        source: "cli.examples.todo-links.unlink"
      )
      try await printTodoLinks(context: context, output: output, event: "unlink", changedID: todoID)

    default:
      throw CLIError("Unknown todo-links command: \(command). \(todoLinksUsage)", exitCode: 64)
    }
  }

  private static func runCache(arguments: [String], output: OutputMode) async throws {
    var arguments = arguments
    guard let command = arguments.popFirstArgument() else {
      throw CLIError(cacheUsage, exitCode: 64)
    }

    let context = try await CLIContext.bootstrap(initialAttributes: [])
    let snapshot = try await context.runtime.persistence.loadSnapshot()

    switch command {
    case "inspect":
      guard arguments.isEmpty else {
        throw CLIError("Usage: instant-swift-data cache inspect [--json|--jsonl]", exitCode: 64)
      }
      let queryCache = try await context.runtime.cachedQueries()
      let summary = CacheInspectOutput(
        appID: context.appID,
        cachePath: context.cacheURL.path,
        transport: "not-implemented-local-cache-only",
        attributeCount: snapshot.store.attributes.count,
        tripleCount: snapshot.store.triples.count,
        queryCacheCount: queryCache.count,
        outboxMutationCount: snapshot.outbox.count,
        namespaces: namespaceSummaries(snapshot.store),
        queries: queryCacheSummaries(queryCache)
      )

      switch output {
      case .human:
        print("cache: \(summary.cachePath)")
        print("attributes: \(summary.attributeCount)")
        print("triples: \(summary.tripleCount)")
        print("cached queries: \(summary.queryCacheCount)")
        print("outbox mutations: \(summary.outboxMutationCount)")
        if !summary.queries.isEmpty {
          print("cached query entries:")
          for query in summary.queries {
            print(
              "  \(query.queryID) namespace=\(query.namespace) results=\(query.resultCount) key=\(query.shortCacheKey)"
            )
          }
        }
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

    case "attributes", "attrs":
      let namespace = try parseOptionalCacheNamespace(
        arguments: arguments,
        usage: "Usage: instant-swift-data cache attributes [namespace] [--json|--jsonl]"
      )
      try printCacheAttributes(
        context: context,
        output: output,
        namespace: namespace,
        attributes: cacheAttributes(snapshot.store, namespace: namespace)
      )

    case "triples", "facts":
      let namespace = try parseOptionalCacheNamespace(
        arguments: arguments,
        usage: "Usage: instant-swift-data cache triples [namespace] [--json|--jsonl]"
      )
      try printCacheTriples(
        context: context,
        output: output,
        namespace: namespace,
        triples: cacheTriples(snapshot.store, namespace: namespace)
      )

    default:
      throw CLIError(cacheUsage, exitCode: 64)
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

    case "transport", "wire", "tx-steps":
      let includeFailed = try parseOutboxTransportOptions(arguments: arguments)
      let mutations = await context.runtime.outboxTransportMutations(includeFailed: includeFailed)
      try printOutboxTransport(
        context: context,
        output: output,
        includeFailed: includeFailed,
        mutations: mutations
      )

    case "flush", "send":
      let limit = try parseOutboxFlushLimit(arguments: arguments)
      let result = try await context.runtime.flushPendingMutations(limit: limit)
      try await printOutboxFlush(context: context, output: output, result: result)

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

    case "retry":
      guard let mutationID = arguments.popFirstArgument(), arguments.isEmpty else {
        throw CLIError("Usage: instant-swift-data outbox retry <mutation-id> [--json|--jsonl]", exitCode: 64)
      }
      let mutation = try await context.runtime.retryMutation(id: mutationID)
      try await printOutboxUpdate(
        context: context,
        output: output,
        event: "retry",
        mutation: mutation
      )

    case "drain":
      let limit = try parseOutboxDrainLimit(arguments: arguments)
      let mutations = try await context.runtime.drainPendingMutationsLocally(limit: limit)
      try await printOutboxDrain(
        context: context,
        output: output,
        event: "drain-local-confirm",
        mutations: mutations
      )

    default:
      throw CLIError(outboxUsage, exitCode: 64)
    }
  }

  private static func runLocalID(arguments: [String], output: OutputMode) async throws {
    var arguments = arguments
    guard let command = arguments.popFirstArgument() else {
      throw CLIError(localIDUsage, exitCode: 64)
    }

    switch command {
    case "get":
      guard let name = arguments.popFirstArgument(),
        arguments.isEmpty,
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      else {
        throw CLIError("Usage: instant-swift-data local-id get <name> [--json|--jsonl]", exitCode: 64)
      }

      let context = try await CLIContext.bootstrap(initialAttributes: [])
      let id = try await context.runtime.localID(named: name)
      let payload = LocalIDOutput(
        appID: context.appID,
        cachePath: context.cacheURL.path,
        transport: "not-implemented-local-cache-only",
        name: name,
        id: id
      )

      switch output {
      case .human:
        print(id)
        print("name: \(name)")
        print("cache: \(context.cacheURL.path)")

      case .json:
        try writeJSON(payload)

      case .jsonl:
        try writeJSONLine(
          EvidenceRow(
            caseID: "cli.local-id.get",
            side: "swift",
            event: "local-id",
            appID: context.appID,
            entityID: id,
            ok: true,
            details: payload
          )
        )
      }

    case "list", "ls":
      guard arguments.isEmpty else {
        throw CLIError("Usage: instant-swift-data local-id list [--json|--jsonl]", exitCode: 64)
      }
      let context = try await CLIContext.bootstrap(initialAttributes: [])
      let localIDs = try await context.runtime.localIDs()
      try printLocalIDs(context: context, output: output, localIDs: localIDs)

    default:
      throw CLIError(localIDUsage, exitCode: 64)
    }
  }

  private static func runAuth(arguments: [String], output: OutputMode) async throws {
    var arguments = arguments
    guard let command = arguments.popFirstArgument() else {
      throw CLIError(authUsage, exitCode: 64)
    }

    let context = try await CLIContext.bootstrap(initialAttributes: [])

    switch command {
    case "show", "status":
      guard arguments.isEmpty else {
        throw CLIError("Usage: instant-swift-data auth show [--json|--jsonl]", exitCode: 64)
      }
      let session = try await context.runtime.authSession()
      try printAuth(context: context, event: "show", session: session, output: output)

    case "guest":
      guard arguments.isEmpty else {
        throw CLIError("Usage: instant-swift-data auth guest [--json|--jsonl]", exitCode: 64)
      }
      let session = try await context.runtime.signInAsGuest()
      try printAuth(context: context, event: "guest", session: session, output: output)

    case "token":
      guard let refreshToken = arguments.popFirstArgument() else {
        throw CLIError("Usage: instant-swift-data auth token <refresh-token> [--user-id id] [--json|--jsonl]", exitCode: 64)
      }
      let userID = try parseAuthUserID(arguments: arguments)
      let session = try await context.runtime.signInWithRefreshToken(refreshToken, userID: userID)
      try printAuth(context: context, event: "token", session: session, output: output)

    case "id-token", "idtoken":
      guard let clientName = arguments.popFirstArgument(),
        let idToken = arguments.popFirstArgument()
      else {
        throw CLIError(
          "Usage: instant-swift-data auth id-token <client-name> <id-token> [--nonce nonce] [--json|--jsonl]",
          exitCode: 64
        )
      }
      let nonce = try parseAuthIDTokenNonce(arguments: arguments)
      let session = try await context.runtime.signInWithIDToken(
        clientName: clientName,
        idToken: idToken,
        nonce: nonce
      )
      try printAuth(context: context, event: "id-token", session: session, output: output)

    case "oauth":
      guard let code = arguments.popFirstArgument() else {
        throw CLIError(
          "Usage: instant-swift-data auth oauth <code> [--code-verifier verifier] [--json|--jsonl]",
          exitCode: 64
        )
      }
      let codeVerifier = try parseAuthOAuthCodeVerifier(arguments: arguments)
      let session = try await context.runtime.signInWithOAuth(
        code: code,
        codeVerifier: codeVerifier
      )
      try printAuth(context: context, event: "oauth", session: session, output: output)

    case "oauth-url", "authorization-url":
      guard let clientName = arguments.popFirstArgument(),
        let redirectURLValue = arguments.popFirstArgument(),
        arguments.isEmpty
      else {
        throw CLIError(
          "Usage: instant-swift-data auth oauth-url <client-name> <redirect-url> [--json|--jsonl]",
          exitCode: 64
        )
      }
      guard let redirectURL = URL(string: redirectURLValue) else {
        throw CLIError(
          "Usage: instant-swift-data auth oauth-url <client-name> <redirect-url> [--json|--jsonl]",
          exitCode: 64
        )
      }
      let authorizationURL = try context.runtime.oauthAuthorizationURL(
        clientName: clientName,
        redirectURL: redirectURL
      )
      let issuerURI = try context.runtime.issuerURI()
      try printAuthEndpoint(
        context: context,
        event: "oauth-url",
        authorizationURL: authorizationURL,
        issuerURI: issuerURI,
        output: output
      )

    case "issuer", "issuer-uri":
      guard arguments.isEmpty else {
        throw CLIError("Usage: instant-swift-data auth issuer [--json|--jsonl]", exitCode: 64)
      }
      let issuerURI = try context.runtime.issuerURI()
      try printAuthEndpoint(
        context: context,
        event: "issuer",
        authorizationURL: nil,
        issuerURI: issuerURI,
        output: output
      )

    case "magic-code", "magic":
      try await runMagicCode(arguments: arguments, context: context, output: output)

    case "watch", "observe":
      let eventCount = try parseAuthWatchEventCount(arguments: arguments)
      try await watchAuth(context: context, output: output, eventCount: eventCount)

    case "sign-out", "signout", "logout":
      let invalidateToken = try parseAuthSignOutInvalidateToken(arguments: arguments)
      try await context.runtime.signOut(invalidateToken: invalidateToken)
      try printAuth(context: context, event: "sign-out", session: nil, output: output)

    default:
      throw CLIError(authUsage, exitCode: 64)
    }
  }

  private static func runMagicCode(
    arguments: [String],
    context: CLIContext,
    output: OutputMode
  ) async throws {
    var arguments = arguments
    guard let command = arguments.popFirstArgument() else {
      throw CLIError(magicCodeUsage, exitCode: 64)
    }

    switch command {
    case "send":
      guard let email = arguments.popFirstArgument(), arguments.isEmpty else {
        throw CLIError("Usage: instant-swift-data auth magic-code send <email> [--json|--jsonl]", exitCode: 64)
      }
      let challenge = try await context.runtime.sendMagicCode(email: email)
      try printMagicCodeChallenge(context: context, challenge: challenge, output: output)

    case "verify":
      guard let email = arguments.popFirstArgument(),
        let code = arguments.popFirstArgument(),
        arguments.isEmpty
      else {
        throw CLIError("Usage: instant-swift-data auth magic-code verify <email> <code> [--json|--jsonl]", exitCode: 64)
      }
      let session = try await context.runtime.signInWithMagicCode(email: email, code: code)
      try printAuth(context: context, event: "magic-code", session: session, output: output)

    default:
      throw CLIError(magicCodeUsage, exitCode: 64)
    }
  }

  private static func runApp(arguments: [String], output: OutputMode) async throws {
    var arguments = arguments
    guard let command = arguments.popFirstArgument() else {
      throw CLIError(appUsage, exitCode: 64)
    }

    switch command {
    case "show", "status", "current":
      guard arguments.isEmpty else {
        throw CLIError("Usage: instant-swift-data app show [--json|--jsonl]", exitCode: 64)
      }
      let context = try await CLIContext.bootstrap(initialAttributes: [])
      try printApp(context: context, event: "show", output: output)

    case "select":
      guard let appID = arguments.popFirstArgument(),
        arguments.isEmpty,
        !appID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      else {
        throw CLIError("Usage: instant-swift-data app select <app-id> [--json|--jsonl]", exitCode: 64)
      }
      let context = try await CLIContext.bootstrap(appIDOverride: appID, initialAttributes: [])
      _ = try await context.runtime.saveSelectedAppID(appID)
      try printApp(context: context, event: "select", output: output)

    case "ephemeral":
      let options = try EphemeralAppOptions.parse(arguments: arguments)
      let app = try InstantEphemeralApps.makeLocal(title: options.title)
      let context = try await CLIContext.bootstrap(appIDOverride: app.appID, initialAttributes: [])
      _ = try await context.runtime.saveSelectedAppID(app.appID)
      try printApp(context: context, event: "ephemeral", output: output, ephemeralApp: app)

    default:
      throw CLIError(appUsage, exitCode: 64)
    }
  }

  private static func runSync(arguments: [String], output: OutputMode) async throws {
    var arguments = arguments
    guard let command = arguments.popFirstArgument() else {
      throw CLIError(syncUsage, exitCode: 64)
    }

    let context = try await CLIContext.bootstrap(initialAttributes: [])

    switch command {
    case "inspect", "show", "status":
      guard arguments.isEmpty else {
        throw CLIError("Usage: instant-swift-data sync inspect [--json|--jsonl]", exitCode: 64)
      }
      let state = try await context.runtime.syncState()
      try printSync(context: context, event: "inspect", state: state, output: output)

    case "mark-processed":
      guard let transactionID = arguments.popFirstArgument(),
        arguments.isEmpty,
        !transactionID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      else {
        throw CLIError("Usage: instant-swift-data sync mark-processed <tx-id> [--json|--jsonl]", exitCode: 64)
      }
      let state = try await context.runtime.markProcessedTransaction(id: transactionID)
      try printSync(context: context, event: "mark-processed", state: state, output: output)

    default:
      throw CLIError(syncUsage, exitCode: 64)
    }
  }

  private static func runConnection(arguments: [String], output: OutputMode) async throws {
    var arguments = arguments
    guard let command = arguments.popFirstArgument() else {
      throw CLIError(connectionUsage, exitCode: 64)
    }

    let context = try await CLIContext.bootstrap(initialAttributes: [])

    switch command {
    case "inspect", "show", "status":
      guard arguments.isEmpty else {
        throw CLIError(
          "Usage: instant-swift-data connection status [--json|--jsonl]",
          exitCode: 64
        )
      }
      let status = try await context.runtime.connectionStatus()
      try printConnectionStatus(context: context, event: "status", status: status, output: output)

    case "connect", "open":
      guard arguments.isEmpty else {
        throw CLIError(
          "Usage: instant-swift-data connection connect [--json|--jsonl]",
          exitCode: 64
        )
      }
      let status = try await context.runtime.connect()
      try printConnectionStatus(context: context, event: "connect", status: status, output: output)

    case "close", "disconnect":
      guard arguments.isEmpty else {
        throw CLIError(
          "Usage: instant-swift-data connection close [--json|--jsonl]",
          exitCode: 64
        )
      }
      let status = try await context.runtime.closeConnection()
      try printConnectionStatus(context: context, event: "close", status: status, output: output)

    default:
      throw CLIError(connectionUsage, exitCode: 64)
    }
  }

  private static func runRooms(arguments: [String], output: OutputMode) async throws {
    var arguments = arguments
    guard let domain = arguments.popFirstArgument() else {
      throw CLIError(roomsUsage, exitCode: 64)
    }

    let context = try await CLIContext.bootstrap(initialAttributes: [])

    switch domain {
    case "presence":
      try await runRoomPresence(arguments: arguments, context: context, output: output)

    case "topics", "topic":
      try await runRoomTopics(arguments: arguments, context: context, output: output)

    default:
      throw CLIError(roomsUsage, exitCode: 64)
    }
  }

  private static func runRoomPresence(
    arguments: [String],
    context: CLIContext,
    output: OutputMode
  ) async throws {
    var arguments = arguments
    guard let command = arguments.popFirstArgument() else {
      throw CLIError(roomPresenceUsage, exitCode: 64)
    }

    switch command {
    case "set":
      let options = try RoomPresenceSetOptions.parse(arguments: arguments)
      let member = try await context.runtime.setPresence(
        room: options.room,
        userID: options.userID,
        values: options.values
      )
      let members = try await context.runtime.roomPresence(room: options.room)
      try printRoomPresence(
        context: context,
        event: "presence-set",
        room: options.room,
        userID: member.userID,
        members: members,
        output: output
      )

    case "list":
      let options = try RoomPresenceListOptions.parse(arguments: arguments)
      let members = try await context.runtime.roomPresence(room: options.room)
      try printRoomPresence(
        context: context,
        event: "presence-list",
        room: options.room,
        userID: nil,
        members: members,
        output: output
      )

    case "leave":
      let options = try RoomPresenceLeaveOptions.parse(arguments: arguments)
      let userID = try await context.runtime.leavePresence(
        room: options.room,
        userID: options.userID
      )
      let members = try await context.runtime.roomPresence(room: options.room)
      try printRoomPresence(
        context: context,
        event: "presence-leave",
        room: options.room,
        userID: userID,
        members: members,
        output: output
      )

    default:
      throw CLIError(roomPresenceUsage, exitCode: 64)
    }
  }

  private static func runRoomTopics(
    arguments: [String],
    context: CLIContext,
    output: OutputMode
  ) async throws {
    var arguments = arguments
    guard let command = arguments.popFirstArgument() else {
      throw CLIError(roomTopicsUsage, exitCode: 64)
    }

    switch command {
    case "publish":
      let options = try RoomTopicPublishOptions.parse(arguments: arguments)
      let message = try await context.runtime.publishTopicMessage(
        room: options.room,
        topic: options.topic,
        userID: options.userID,
        payload: options.payload
      )
      let messages = try await context.runtime.roomTopicMessages(
        room: options.room,
        topic: options.topic
      )
      try printRoomTopic(
        context: context,
        event: "topic-publish",
        room: options.room,
        topic: options.topic,
        publishedMessageID: message.id,
        messages: messages,
        output: output
      )

    case "list":
      let options = try RoomTopicListOptions.parse(arguments: arguments)
      let messages = try await context.runtime.roomTopicMessages(
        room: options.room,
        topic: options.topic,
        limit: options.limit
      )
      try printRoomTopic(
        context: context,
        event: "topic-list",
        room: options.room,
        topic: options.topic,
        publishedMessageID: nil,
        messages: messages,
        output: output
      )

    default:
      throw CLIError(roomTopicsUsage, exitCode: 64)
    }
  }

  private static func runFiles(arguments: [String], output: OutputMode) async throws {
    var arguments = arguments
    guard let command = arguments.popFirstArgument() else {
      throw CLIError(filesUsage, exitCode: 64)
    }

    let context = try await CLIContext.bootstrap(initialAttributes: [])

    switch command {
    case "upload", "put":
      let options = try FileUploadOptions.parse(arguments: arguments)
      let file = try await context.runtime.uploadFile(
        from: options.sourceURL,
        name: options.name,
        contentType: options.contentType
      )
      let files = try await context.runtime.storedFiles()
      try printFiles(
        context: context,
        event: "upload",
        changedID: file.id,
        files: files,
        output: output
      )

    case "list", "ls":
      guard arguments.isEmpty else {
        throw CLIError("Usage: instant-swift-data files list [--json|--jsonl]", exitCode: 64)
      }
      let files = try await context.runtime.storedFiles()
      try printFiles(
        context: context,
        event: "list",
        changedID: nil,
        files: files,
        output: output
      )

    case "delete", "rm":
      guard let fileID = arguments.popFirstArgument(), arguments.isEmpty else {
        throw CLIError("Usage: instant-swift-data files delete <file-id> [--json|--jsonl]", exitCode: 64)
      }
      let file = try await context.runtime.deleteStoredFile(id: fileID)
      let files = try await context.runtime.storedFiles()
      try printFiles(
        context: context,
        event: "delete",
        changedID: file.id,
        files: files,
        output: output
      )

    default:
      throw CLIError(filesUsage, exitCode: 64)
    }
  }

  private static func runStreams(arguments: [String], output: OutputMode) async throws {
    var arguments = arguments
    guard let command = arguments.popFirstArgument() else {
      throw CLIError(streamsUsage, exitCode: 64)
    }

    let context = try await CLIContext.bootstrap(initialAttributes: [])

    switch command {
    case "append", "write":
      let options = try StreamAppendOptions.parse(arguments: arguments)
      let chunk = try await context.runtime.appendStreamChunk(
        streamID: options.streamID,
        payload: options.payload
      )
      let chunks = try await context.runtime.streamChunks(streamID: options.streamID)
      try printStreamChunks(
        context: context,
        event: "append",
        streamID: options.streamID,
        changedID: chunk.id,
        chunks: chunks,
        output: output
      )

    case "read", "list":
      let options = try StreamReadOptions.parse(arguments: arguments)
      let chunks = try await context.runtime.streamChunks(
        streamID: options.streamID,
        limit: options.limit
      )
      try printStreamChunks(
        context: context,
        event: "read",
        streamID: options.streamID,
        changedID: nil,
        chunks: chunks,
        output: output
      )

    default:
      throw CLIError(streamsUsage, exitCode: 64)
    }
  }

  private static func runShares(arguments: [String], output: OutputMode) async throws {
    var arguments = arguments
    guard let command = arguments.popFirstArgument() else {
      throw CLIError(sharesUsage, exitCode: 64)
    }

    let context = try await CLIContext.bootstrap(initialAttributes: [])

    switch command {
    case "create":
      guard let namespace = arguments.popFirstArgument(),
        let entityID = arguments.popFirstArgument(),
        arguments.isEmpty
      else {
        throw CLIError(sharesUsage, exitCode: 64)
      }
      let snapshot = try await context.runtime.createShare(
        rootNamespace: namespace,
        rootID: entityID
      )
      try printShares(
        context: context,
        event: "create",
        changedID: snapshot.share.id,
        shares: [snapshot],
        output: output
      )

    case "list", "ls":
      guard arguments.isEmpty else {
        throw CLIError("Usage: instant-swift-data shares list [--json|--jsonl]", exitCode: 64)
      }
      let shares = try await context.runtime.shares()
      try printShares(
        context: context,
        event: "list",
        changedID: nil,
        shares: shares,
        output: output
      )

    case "accept":
      guard let token = arguments.popFirstArgument(), arguments.isEmpty else {
        throw CLIError("Usage: instant-swift-data shares accept <token> [--json|--jsonl]", exitCode: 64)
      }
      let snapshot = try await context.runtime.acceptShare(token: token)
      try printShares(
        context: context,
        event: "accept",
        changedID: snapshot.share.id,
        shares: [snapshot],
        output: output
      )

    case "revoke":
      guard let shareID = arguments.popFirstArgument(), arguments.isEmpty else {
        throw CLIError("Usage: instant-swift-data shares revoke <share-id> [--json|--jsonl]", exitCode: 64)
      }
      let snapshot = try await context.runtime.revokeShare(id: shareID)
      try printShares(
        context: context,
        event: "revoke",
        changedID: snapshot.share.id,
        shares: [snapshot],
        output: output
      )

    default:
      throw CLIError(sharesUsage, exitCode: 64)
    }
  }

  private static func printLocalIDs(
    context: CLIContext,
    output: OutputMode,
    localIDs: [InstantLocalID]
  ) throws {
    let payload = LocalIDsOutput(
      appID: context.appID,
      cachePath: context.cacheURL.path,
      transport: "not-implemented-local-cache-only",
      localIDCount: localIDs.count,
      localIDs: localIDs
    )

    switch output {
    case .human:
      if localIDs.isEmpty {
        print("No local IDs.")
      } else {
        for localID in localIDs {
          print("\(localID.name) \(localID.entityID)")
        }
      }
      print("transport: \(payload.transport)")
      print("cache: \(context.cacheURL.path)")

    case .json:
      try writeJSON(payload)

    case .jsonl:
      try writeJSONLine(
        EvidenceRow(
          caseID: "cli.local-id.list",
          side: "swift",
          event: "summary",
          appID: context.appID,
          ok: true,
          details: payload
        )
      )
      for localID in localIDs {
        try writeJSONLine(
          EvidenceRow(
            caseID: "cli.local-id.list",
            side: "swift",
            event: "local-id",
            appID: context.appID,
            entityID: localID.entityID,
            ok: true,
            details: localID
          )
        )
      }
    }
  }

  private static func printCacheAttributes(
    context: CLIContext,
    output: OutputMode,
    namespace: String?,
    attributes: [InstantAttribute]
  ) throws {
    let payload = CacheAttributesOutput(
      appID: context.appID,
      cachePath: context.cacheURL.path,
      transport: "not-implemented-local-cache-only",
      namespace: namespace,
      attributeCount: attributes.count,
      attributes: attributes
    )

    switch output {
    case .human:
      if attributes.isEmpty {
        print("attributes: none")
      } else {
        for attribute in attributes {
          print(
            "\(attribute.id) namespace=\(attribute.namespace) name=\(attribute.name) type=\(attribute.valueType.rawValue)"
          )
        }
      }
      print("transport: \(payload.transport)")
      print("cache: \(context.cacheURL.path)")

    case .json:
      try writeJSON(payload)

    case .jsonl:
      try writeJSONLine(
        EvidenceRow(
          caseID: "cli.cache.attributes",
          side: "swift",
          event: "summary",
          appID: context.appID,
          entityID: namespace,
          ok: true,
          details: payload
        )
      )
      for attribute in attributes {
        try writeJSONLine(
          EvidenceRow(
            caseID: "cli.cache.attributes",
            side: "swift",
            event: "attribute",
            appID: context.appID,
            entityID: attribute.id,
            ok: true,
            details: attribute
          )
        )
      }
    }
  }

  private static func printCacheTriples(
    context: CLIContext,
    output: OutputMode,
    namespace: String?,
    triples: [InstantTriple]
  ) throws {
    let payload = CacheTriplesOutput(
      appID: context.appID,
      cachePath: context.cacheURL.path,
      transport: "not-implemented-local-cache-only",
      namespace: namespace,
      tripleCount: triples.count,
      triples: triples
    )

    switch output {
    case .human:
      if triples.isEmpty {
        print("triples: none")
      } else {
        for triple in triples {
          print(
            "\(triple.entityID) \(triple.attributeID) \(triple.value.comparableKey) tx=\(triple.txID)"
          )
        }
      }
      print("transport: \(payload.transport)")
      print("cache: \(context.cacheURL.path)")

    case .json:
      try writeJSON(payload)

    case .jsonl:
      try writeJSONLine(
        EvidenceRow(
          caseID: "cli.cache.triples",
          side: "swift",
          event: "summary",
          appID: context.appID,
          entityID: namespace,
          ok: true,
          details: payload
        )
      )
      for triple in triples {
        try writeJSONLine(
          EvidenceRow(
            caseID: "cli.cache.triples",
            side: "swift",
            event: "triple",
            appID: context.appID,
            entityID: triple.entityID,
            ok: true,
            details: triple
          )
        )
      }
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

  private static func printOutboxTransport(
    context: CLIContext,
    output: OutputMode,
    includeFailed: Bool,
    mutations: [InstantTransportMutation]
  ) throws {
    let txStepCount = mutations.reduce(0) { $0 + $1.txSteps.count }
    let preconditionCount = mutations.reduce(0) { $0 + $1.preconditions.count }
    let payload = OutboxTransportOutput(
      appID: context.appID,
      cachePath: context.cacheURL.path,
      event: "transport",
      transport: "not-implemented-local-cache-only",
      includeFailed: includeFailed,
      mutationCount: mutations.count,
      txStepCount: txStepCount,
      preconditionCount: preconditionCount,
      mutations: mutations
    )

    switch output {
    case .human:
      print("outbox transport: \(payload.cachePath)")
      print("mutations: \(payload.mutationCount)")
      print("tx steps: \(payload.txStepCount)")
      print("preconditions: \(payload.preconditionCount)")
      for mutation in mutations {
        print(
          "- \(mutation.mutationID) status=\(mutation.status.rawValue) txSteps=\(mutation.txSteps.count) preconditions=\(mutation.preconditions.count)"
        )
      }

    case .json:
      try writeJSON(payload)

    case .jsonl:
      try writeJSONLine(
        EvidenceRow(
          caseID: "cli.outbox.transport",
          side: "swift",
          event: "summary",
          appID: context.appID,
          ok: true,
          details: payload
        )
      )
      for mutation in mutations {
        try writeJSONLine(
          EvidenceRow(
            caseID: "cli.outbox.transport",
            side: "swift",
            event: "mutation",
            appID: context.appID,
            entityID: mutation.mutationID,
            ok: true,
            details: mutation
          )
        )
      }
    }
  }

  private static func printOutboxFlush(
    context: CLIContext,
    output: OutputMode,
    result: InstantMutationTransportFlushResult
  ) async throws {
    let payload = OutboxFlushOutput(
      appID: context.appID,
      cachePath: context.cacheURL.path,
      event: "flush-local-transport",
      transport: "local-mutation-transport",
      attemptedMutationCount: result.request.mutations.count,
      confirmedMutationCount: result.confirmed.count,
      failedMutationCount: result.failed.count,
      pendingMutationCount: result.pendingMutationCount,
      mutationCount: result.mutationCount,
      request: result.request,
      results: result.results,
      confirmed: result.confirmed,
      failed: result.failed
    )

    switch output {
    case .human:
      print("outbox flush: \(payload.cachePath)")
      print("attempted mutations: \(payload.attemptedMutationCount)")
      print("confirmed mutations: \(payload.confirmedMutationCount)")
      print("failed mutations: \(payload.failedMutationCount)")
      print("pending mutations: \(payload.pendingMutationCount)")
      for result in payload.results {
        if let message = result.message, !message.isEmpty {
          print("- \(result.mutationID) \(result.outcome.rawValue): \(message)")
        } else {
          print("- \(result.mutationID) \(result.outcome.rawValue)")
        }
      }

    case .json:
      try writeJSON(payload)

    case .jsonl:
      try writeJSONLine(
        EvidenceRow(
          caseID: "cli.outbox.flush",
          side: "swift",
          event: "summary",
          appID: context.appID,
          ok: payload.failedMutationCount == 0,
          details: payload
        )
      )
      for result in payload.results {
        try writeJSONLine(
          EvidenceRow(
            caseID: "cli.outbox.flush",
            side: "swift",
            event: result.outcome.rawValue,
            appID: context.appID,
            entityID: result.mutationID,
            ok: result.outcome == .confirmed,
            details: result
          )
        )
      }
    }
  }

  private static func printAuth(
    context: CLIContext,
    event: String,
    session: InstantAuthSession?,
    output: OutputMode
  ) throws {
    let payload = makeAuthOutput(context: context, event: event, session: session)

    switch output {
    case .human:
      printAuth(payload)

    case .json:
      try writeJSON(payload)

    case .jsonl:
      try writeJSONLine(
        EvidenceRow(
          caseID: "cli.auth",
          side: "swift",
          event: event,
          appID: context.appID,
          entityID: session?.userID,
          ok: true,
          details: payload
        )
      )
    }
  }

  private static func makeAuthOutput(
    context: CLIContext,
    event: String,
    session: InstantAuthSession?
  ) -> AuthOutput {
    AuthOutput(
      appID: context.appID,
      cachePath: context.cacheURL.path,
      event: event,
      transport: "not-implemented-local-cache-only",
      isSignedIn: session != nil,
      userID: session?.userID,
      isGuest: session?.isGuest,
      hasRefreshToken: session?.refreshToken != nil,
      createdAt: session?.createdAt,
      updatedAt: session?.updatedAt
    )
  }

  private static func printAuth(_ payload: AuthOutput) {
    if payload.isSignedIn {
      print("auth: \(payload.isGuest == true ? "guest" : "token")")
      if let userID = payload.userID {
        print("user: \(userID)")
      }
      print("refresh token: \(payload.hasRefreshToken ? "present" : "none")")
    } else {
      print("auth: signed out")
    }
    print("cache: \(payload.cachePath)")
  }

  private static func printAuthEndpoint(
    context: CLIContext,
    event: String,
    authorizationURL: URL?,
    issuerURI: URL,
    output: OutputMode
  ) throws {
    let payload = AuthEndpointOutput(
      appID: context.appID,
      cachePath: context.cacheURL.path,
      event: event,
      transport: "not-implemented-local-cache-only",
      apiURI: context.runtime.configuration.apiURI.absoluteString,
      websocketURI: context.runtime.configuration.websocketURI.absoluteString,
      authorizationURL: authorizationURL?.absoluteString,
      issuerURI: issuerURI.absoluteString
    )

    switch output {
    case .human:
      if let authorizationURL = payload.authorizationURL {
        print("authorization URL: \(authorizationURL)")
      }
      print("issuer URI: \(payload.issuerURI)")
      print("api URI: \(payload.apiURI)")
      print("websocket URI: \(payload.websocketURI)")
      print("cache: \(payload.cachePath)")

    case .json:
      try writeJSON(payload)

    case .jsonl:
      try writeJSONLine(
        EvidenceRow(
          caseID: "cli.auth.endpoint",
          side: "swift",
          event: event,
          appID: context.appID,
          entityID: payload.authorizationURL ?? payload.issuerURI,
          ok: true,
          details: payload
        )
      )
    }
  }

  private static func watchAuth(
    context: CLIContext,
    output: OutputMode,
    eventCount: Int
  ) async throws {
    let stream = try await context.runtime.observeAuthSession()
    var iterator = stream.makeAsyncIterator()
    var emissions: [AuthOutput] = []
    emissions.reserveCapacity(eventCount)

    while emissions.count < eventCount {
      guard let session = await iterator.next() else { break }
      let payload = makeAuthOutput(context: context, event: "watch", session: session)

      switch output {
      case .human:
        print("event: watch index=\(emissions.count)")
        printAuth(payload)

      case .json, .jsonl:
        break
      }

      emissions.append(payload)

      if output == .jsonl {
        try writeJSONLine(
          EvidenceRow(
            caseID: "cli.auth.watch",
            side: "swift",
            event: "watch",
            appID: context.appID,
            entityID: session?.userID,
            ok: true,
            details: payload
          )
        )
      }
    }

    switch output {
    case .human, .jsonl:
      break

    case .json:
      try writeJSON(
        AuthWatchOutput(
          appID: context.appID,
          cachePath: context.cacheURL.path,
          event: "watch",
          transport: "not-implemented-local-cache-only",
          requestedEventCount: eventCount,
          emittedEventCount: emissions.count,
          emissions: emissions
        )
      )
    }
  }

  private static func printMagicCodeChallenge(
    context: CLIContext,
    challenge: InstantMagicCodeChallenge,
    output: OutputMode
  ) throws {
    let payload = MagicCodeOutput(
      appID: context.appID,
      cachePath: context.cacheURL.path,
      event: "magic-code-send",
      transport: "not-implemented-local-cache-only",
      email: challenge.email,
      expiresAt: challenge.expiresAt,
      localVerificationCode: challenge.code
    )

    switch output {
    case .human:
      print("email: \(payload.email)")
      print("local verification code: \(payload.localVerificationCode)")
      print("expires at ms: \(payload.expiresAt.milliseconds)")
      print("cache: \(payload.cachePath)")

    case .json:
      try writeJSON(payload)

    case .jsonl:
      try writeJSONLine(
        EvidenceRow(
          caseID: "cli.auth.magic-code",
          side: "swift",
          event: "magic-code-send",
          appID: context.appID,
          entityID: challenge.email,
          ok: true,
          details: payload
        )
      )
    }
  }

  private static func printApp(
    context: CLIContext,
    event: String,
    output: OutputMode,
    ephemeralApp: InstantEphemeralApp? = nil
  ) throws {
    let payload = AppOutput(
      appID: context.appID,
      cachePath: context.cacheURL.path,
      event: event,
      transport: ephemeralApp?.transport ?? "not-implemented-local-cache-only",
      selectionSource: context.appIDSource.rawValue,
      title: ephemeralApp?.title,
      isLocalOnly: ephemeralApp?.isLocalOnly,
      createdAt: ephemeralApp?.createdAt
    )

    switch output {
    case .human:
      print("app: \(payload.appID)")
      print("source: \(payload.selectionSource)")
      if let title = payload.title {
        print("title: \(title)")
      }
      if let isLocalOnly = payload.isLocalOnly {
        print("local only: \(isLocalOnly)")
      }
      print("transport: \(payload.transport)")
      print("cache: \(payload.cachePath)")

    case .json:
      try writeJSON(payload)

    case .jsonl:
      try writeJSONLine(
        EvidenceRow(
          caseID: "cli.app",
          side: "swift",
          event: event,
          appID: context.appID,
          ok: true,
          details: payload
        )
      )
    }
  }

  private static func printSync(
    context: CLIContext,
    event: String,
    state: InstantSyncState,
    output: OutputMode
  ) throws {
    let payload = SyncOutput(
      appID: context.appID,
      cachePath: context.cacheURL.path,
      event: event,
      transport: "not-implemented-local-cache-only",
      processedTransactionID: state.processedTransactionID
    )

    switch output {
    case .human:
      print("processed transaction: \(payload.processedTransactionID ?? "none")")
      print("cache: \(payload.cachePath)")

    case .json:
      try writeJSON(payload)

    case .jsonl:
      try writeJSONLine(
        EvidenceRow(
          caseID: "cli.sync",
          side: "swift",
          event: event,
          appID: context.appID,
          entityID: state.processedTransactionID,
          ok: true,
          details: payload
        )
      )
    }
  }

  private static func printConnectionStatus(
    context: CLIContext,
    event: String,
    status: InstantConnectionStatus,
    output: OutputMode
  ) throws {
    let payload = ConnectionStatusOutput(
      appID: context.appID,
      cachePath: context.cacheURL.path,
      event: event,
      apiURI: status.apiURI.absoluteString,
      websocketURI: status.websocketURI.absoluteString,
      transport: status.transport.rawValue,
      state: status.state.rawValue,
      isAuthenticated: status.isAuthenticated,
      userID: status.userID,
      pendingMutationCount: status.pendingMutationCount,
      processedTransactionID: status.processedTransactionID,
      lastErrorMessage: status.lastErrorMessage
    )

    switch output {
    case .human:
      print("connection: \(payload.state)")
      print("transport: \(payload.transport)")
      print("authenticated: \(payload.isAuthenticated)")
      print("user: \(payload.userID ?? "none")")
      print("pending mutations: \(payload.pendingMutationCount)")
      print("processed transaction: \(payload.processedTransactionID ?? "none")")
      print("api: \(payload.apiURI)")
      print("websocket: \(payload.websocketURI)")
      print("cache: \(payload.cachePath)")

    case .json:
      try writeJSON(payload)

    case .jsonl:
      try writeJSONLine(
        EvidenceRow(
          caseID: "cli.connection.\(event)",
          side: "swift",
          event: event,
          appID: context.appID,
          entityID: status.userID,
          ok: status.lastErrorMessage == nil,
          details: payload
        )
      )
    }
  }

  private static func printRoomPresence(
    context: CLIContext,
    event: String,
    room: InstantRoomHandle,
    userID: String?,
    members: [InstantRoomPresenceMember],
    output: OutputMode
  ) throws {
    let payload = RoomPresenceOutput(
      appID: context.appID,
      cachePath: context.cacheURL.path,
      event: event,
      transport: "not-implemented-local-cache-only",
      room: room,
      userID: userID,
      memberCount: members.count,
      members: members
    )

    switch output {
    case .human:
      print("room: \(room.type)/\(room.id)")
      if let userID {
        print("user: \(userID)")
      }
      print("presence members: \(members.count)")
      for member in members {
        print("- \(member.userID) updatedAtMs=\(member.updatedAt.milliseconds)")
      }
      print("transport: \(payload.transport)")
      print("cache: \(context.cacheURL.path)")

    case .json:
      try writeJSON(payload)

    case .jsonl:
      try writeJSONLine(
        EvidenceRow(
          caseID: "cli.rooms.presence",
          side: "swift",
          event: event,
          appID: context.appID,
          entityID: userID,
          ok: true,
          details: payload
        )
      )
      for member in members {
        try writeJSONLine(
          EvidenceRow(
            caseID: "cli.rooms.presence",
            side: "swift",
            event: "presence-member",
            appID: context.appID,
            entityID: member.userID,
            ok: true,
            details: member
          )
        )
      }
    }
  }

  private static func printRoomTopic(
    context: CLIContext,
    event: String,
    room: InstantRoomHandle,
    topic: String,
    publishedMessageID: String?,
    messages: [InstantRoomTopicMessage],
    output: OutputMode
  ) throws {
    let payload = RoomTopicOutput(
      appID: context.appID,
      cachePath: context.cacheURL.path,
      event: event,
      transport: "not-implemented-local-cache-only",
      room: room,
      topic: topic,
      publishedMessageID: publishedMessageID,
      messageCount: messages.count,
      messages: messages
    )

    switch output {
    case .human:
      print("room: \(room.type)/\(room.id)")
      print("topic: \(topic)")
      if let publishedMessageID {
        print("message: \(publishedMessageID)")
      }
      print("messages: \(messages.count)")
      for message in messages {
        print("- \(message.id) user=\(message.userID) createdAtMs=\(message.createdAt.milliseconds)")
      }
      print("transport: \(payload.transport)")
      print("cache: \(context.cacheURL.path)")

    case .json:
      try writeJSON(payload)

    case .jsonl:
      try writeJSONLine(
        EvidenceRow(
          caseID: "cli.rooms.topics",
          side: "swift",
          event: event,
          appID: context.appID,
          entityID: publishedMessageID,
          ok: true,
          details: payload
        )
      )
      for message in messages {
        try writeJSONLine(
          EvidenceRow(
            caseID: "cli.rooms.topics",
            side: "swift",
            event: "topic-message",
            appID: context.appID,
            entityID: message.id,
            ok: true,
            details: message
          )
        )
      }
    }
  }

  private static func printFiles(
    context: CLIContext,
    event: String,
    changedID: String?,
    files: [InstantStoredFile],
    output: OutputMode
  ) throws {
    let payload = FilesOutput(
      appID: context.appID,
      cachePath: context.cacheURL.path,
      event: event,
      changedID: changedID,
      transport: "not-implemented-local-cache-only",
      fileCount: files.count,
      files: files
    )

    switch output {
    case .human:
      print("files: \(files.count)")
      for file in files {
        print("- \(file.id) \(file.name) bytes=\(file.byteCount)")
      }
      print("transport: \(payload.transport)")
      print("cache: \(context.cacheURL.path)")

    case .json:
      try writeJSON(payload)

    case .jsonl:
      try writeJSONLine(
        EvidenceRow(
          caseID: "cli.files",
          side: "swift",
          event: event,
          appID: context.appID,
          entityID: changedID,
          ok: true,
          details: payload
        )
      )
      for file in files {
        try writeJSONLine(
          EvidenceRow(
            caseID: "cli.files",
            side: "swift",
            event: "file",
            appID: context.appID,
            entityID: file.id,
            ok: true,
            details: file
          )
        )
      }
    }
  }

  private static func printStreamChunks(
    context: CLIContext,
    event: String,
    streamID: String,
    changedID: String?,
    chunks: [InstantStreamChunk],
    output: OutputMode
  ) throws {
    let payload = StreamsOutput(
      appID: context.appID,
      cachePath: context.cacheURL.path,
      event: event,
      changedID: changedID,
      transport: "not-implemented-local-cache-only",
      streamID: streamID,
      chunkCount: chunks.count,
      chunks: chunks
    )

    switch output {
    case .human:
      print("stream: \(streamID)")
      print("chunks: \(chunks.count)")
      for chunk in chunks {
        print("- \(chunk.index) \(chunk.id) user=\(chunk.userID)")
      }
      print("transport: \(payload.transport)")
      print("cache: \(context.cacheURL.path)")

    case .json:
      try writeJSON(payload)

    case .jsonl:
      try writeJSONLine(
        EvidenceRow(
          caseID: "cli.streams",
          side: "swift",
          event: event,
          appID: context.appID,
          entityID: changedID,
          ok: true,
          details: payload
        )
      )
      for chunk in chunks {
        try writeJSONLine(
          EvidenceRow(
            caseID: "cli.streams",
            side: "swift",
            event: "chunk",
            appID: context.appID,
            entityID: chunk.id,
            ok: true,
            details: chunk
          )
        )
      }
    }
  }

  private static func printShares(
    context: CLIContext,
    event: String,
    changedID: String?,
    shares: [InstantShareSnapshot],
    output: OutputMode
  ) throws {
    let payload = SharesOutput(
      appID: context.appID,
      cachePath: context.cacheURL.path,
      event: event,
      changedID: changedID,
      transport: "not-implemented-local-cache-only",
      shareCount: shares.count,
      shares: shares
    )

    switch output {
    case .human:
      print("shares: \(shares.count)")
      for snapshot in shares {
        let share = snapshot.share
        print("- \(share.id) root=\(share.rootNamespace)/\(share.rootID) owner=\(share.ownerUserID)")
        print("  token: \(share.token)")
        print("  members: \(snapshot.memberships.count)")
      }
      print("transport: \(payload.transport)")
      print("cache: \(context.cacheURL.path)")

    case .json:
      try writeJSON(payload)

    case .jsonl:
      try writeJSONLine(
        EvidenceRow(
          caseID: "cli.shares",
          side: "swift",
          event: event,
          appID: context.appID,
          entityID: changedID,
          ok: true,
          details: payload
        )
      )
      for snapshot in shares {
        try writeJSONLine(
          EvidenceRow(
            caseID: "cli.shares",
            side: "swift",
            event: "share",
            appID: context.appID,
            entityID: snapshot.share.id,
            ok: true,
            details: snapshot
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

  private static func printOutboxDrain(
    context: CLIContext,
    output: OutputMode,
    event: String,
    mutations: [PendingMutation]
  ) async throws {
    let remainingMutations = await context.runtime.outboxMutations()
    let update = OutboxDrainOutput(
      appID: context.appID,
      cachePath: context.cacheURL.path,
      event: event,
      transport: "not-implemented-local-cache-only",
      pendingMutationCount: remainingMutations.filter { $0.status == .pending }.count,
      mutationCount: remainingMutations.count,
      drainedMutationCount: mutations.count,
      mutations: mutations
    )

    switch output {
    case .human:
      print("outbox: \(update.cachePath)")
      print("event: \(event)")
      print("drained mutations: \(mutations.count)")
      for mutation in mutations {
        print(
          "- \(mutation.id) status=\(mutation.status.rawValue) createdAtMs=\(mutation.createdAt.milliseconds) operations=\(mutation.transaction.operations.count)"
        )
      }
      print("pending mutations: \(update.pendingMutationCount)")

    case .json:
      try writeJSON(update)

    case .jsonl:
      try writeJSONLine(
        EvidenceRow(
          caseID: "cli.outbox.drain",
          side: "swift",
          event: event,
          appID: context.appID,
          ok: true,
          details: update
        )
      )
      for mutation in mutations {
        try writeJSONLine(
          EvidenceRow(
            caseID: "cli.outbox.drain",
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

  private static func printTodos(
    context: CLIContext,
    output: OutputMode,
    event: String,
    changedID: String? = nil,
    query: InstantQueryPlan = TodoExample.query,
    caseID: String = "cli.examples.todos"
  ) async throws {
    let emission = try await context.runtime.queryOnce(query)
    let todos = try TodoExample.decode(emission.values)
    let pending = await context.runtime.pendingMutations()
    let payload = TodosOutput(
      appID: context.appID,
      cachePath: context.cacheURL.path,
      event: event,
      changedID: changedID,
      transport: "not-implemented-local-cache-only",
      queryID: query.id,
      cacheKey: query.cacheKey,
      pageInfo: emission.pageInfo,
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
      print("transport: \(payload.transport)")
      printPageInfo(payload.pageInfo)
      print("pending mutations: \(pending.count)")
      print("cache: \(context.cacheURL.path)")

    case .json:
      try writeJSON(payload)

    case .jsonl:
      try writeJSONLine(
        EvidenceRow(
          caseID: caseID,
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
            caseID: caseID,
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

  private static func printTodoLinks(
    context: CLIContext,
    output: OutputMode,
    event: String,
    changedID: String? = nil
  ) async throws {
    let projectsEmission = try await context.runtime.queryOnce(TodoProjectExample.projectsQuery)
    let todosEmission = try await context.runtime.queryOnce(TodoProjectExample.todosQuery)
    let projects = try TodoProjectExample.decodeProjects(projectsEmission.values)
    let todos = try TodoProjectExample.decodeLinkedTodos(todosEmission.values)
    let pending = await context.runtime.pendingMutations()
    let payload = TodoLinksOutput(
      appID: context.appID,
      cachePath: context.cacheURL.path,
      event: event,
      changedID: changedID,
      transport: "not-implemented-local-cache-only",
      projectQueryID: TodoProjectExample.projectsQuery.id,
      todoQueryID: TodoProjectExample.todosQuery.id,
      projectCacheKey: TodoProjectExample.projectsQuery.cacheKey,
      todoCacheKey: TodoProjectExample.todosQuery.cacheKey,
      pendingMutationCount: pending.count,
      projects: projects,
      todos: todos
    )

    switch output {
    case .human:
      if projects.isEmpty {
        print("No projects.")
      } else {
        for project in projects {
          print("project \(project.id) \(project.title)")
        }
      }
      if todos.isEmpty {
        print("No linked todos.")
      } else {
        for todo in todos {
          let mark = todo.isCompleted ? "[x]" : "[ ]"
          let project = todo.projectID.map { " project=\($0)" } ?? ""
          print("\(mark) \(todo.id) \(todo.text)\(project)")
        }
      }
      print("transport: \(payload.transport)")
      print("pending mutations: \(pending.count)")
      print("cache: \(context.cacheURL.path)")

    case .json:
      try writeJSON(payload)

    case .jsonl:
      try writeJSONLine(
        EvidenceRow(
          caseID: "cli.examples.todo-links",
          side: "swift",
          event: event,
          appID: context.appID,
          ok: true,
          details: payload
        )
      )
      for project in projects {
        try writeJSONLine(
          EvidenceRow(
            caseID: "cli.examples.todo-links",
            side: "swift",
            event: "project",
            appID: context.appID,
            entityID: project.id,
            ok: true,
            details: project
          )
        )
      }
      for todo in todos {
        try writeJSONLine(
          EvidenceRow(
            caseID: "cli.examples.todo-links",
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

  private static func printTodoLinkSnapshots(
    context: CLIContext,
    output: OutputMode,
    event: String
  ) async throws {
    let todosEmission = try await context.runtime.queryOnce(TodoProjectExample.todosWithProjectQuery)
    let projectsEmission = try await context.runtime.queryOnce(TodoProjectExample.projectsWithTodosQuery)
    let pending = await context.runtime.pendingMutations()
    let payload = TodoLinkSnapshotsOutput(
      appID: context.appID,
      cachePath: context.cacheURL.path,
      event: event,
      transport: "not-implemented-local-cache-only",
      todoQueryID: TodoProjectExample.todosWithProjectQuery.id,
      projectQueryID: TodoProjectExample.projectsWithTodosQuery.id,
      todoCacheKey: TodoProjectExample.todosWithProjectQuery.cacheKey,
      projectCacheKey: TodoProjectExample.projectsWithTodosQuery.cacheKey,
      pendingMutationCount: pending.count,
      todos: todosEmission.values,
      projects: projectsEmission.values
    )

    switch output {
    case .human:
      if todosEmission.values.isEmpty, projectsEmission.values.isEmpty {
        print("No nested snapshots.")
      } else {
        for snapshot in todosEmission.values {
          let links = snapshot.links?.keys.sorted().joined(separator: ",") ?? ""
          print("\(snapshot.namespace)/\(snapshot.id) links=\(links)")
        }
        for snapshot in projectsEmission.values {
          let links = snapshot.links?.keys.sorted().joined(separator: ",") ?? ""
          print("\(snapshot.namespace)/\(snapshot.id) links=\(links)")
        }
      }
      print("transport: \(payload.transport)")
      print("pending mutations: \(pending.count)")
      print("cache: \(context.cacheURL.path)")

    case .json:
      try writeJSON(payload)

    case .jsonl:
      try writeJSONLine(
        EvidenceRow(
          caseID: "cli.examples.todo-links.nested",
          side: "swift",
          event: event,
          appID: context.appID,
          ok: true,
          details: payload
        )
      )
      for snapshot in todosEmission.values {
        try writeJSONLine(
          EvidenceRow(
            caseID: "cli.examples.todo-links.nested",
            side: "swift",
            event: "todo",
            appID: context.appID,
            entityID: snapshot.id,
            ok: true,
            details: snapshot
          )
        )
      }
      for snapshot in projectsEmission.values {
        try writeJSONLine(
          EvidenceRow(
            caseID: "cli.examples.todo-links.nested",
            side: "swift",
            event: "project",
            appID: context.appID,
            entityID: snapshot.id,
            ok: true,
            details: snapshot
          )
        )
      }
    }
  }

  private static func printSnapshots(
    context: CLIContext,
    output: OutputMode,
    event: String,
    query: InstantQueryPlan,
    caseID: String
  ) async throws {
    let emission = try await context.runtime.queryOnce(query)
    let pending = await context.runtime.pendingMutations()
    let payload = QuerySnapshotsOutput(
      appID: context.appID,
      cachePath: context.cacheURL.path,
      event: event,
      transport: "not-implemented-local-cache-only",
      queryID: query.id,
      cacheKey: query.cacheKey,
      selectedFields: query.selectedFields,
      pageInfo: emission.pageInfo,
      pendingMutationCount: pending.count,
      snapshots: emission.values
    )

    switch output {
    case .human:
      if emission.values.isEmpty {
        print("No snapshots.")
      } else {
        for snapshot in emission.values {
          let fields = snapshot.values.keys.sorted().joined(separator: ",")
          print("\(snapshot.namespace)/\(snapshot.id) fields=\(fields)")
        }
      }
      print("transport: \(payload.transport)")
      printPageInfo(payload.pageInfo)
      print("pending mutations: \(pending.count)")
      print("cache: \(context.cacheURL.path)")

    case .json:
      try writeJSON(payload)

    case .jsonl:
      try writeJSONLine(
        EvidenceRow(
          caseID: caseID,
          side: "swift",
          event: event,
          appID: context.appID,
          ok: true,
          details: payload
        )
      )
      for snapshot in emission.values {
        try writeJSONLine(
          EvidenceRow(
            caseID: caseID,
            side: "swift",
            event: "snapshot",
            appID: context.appID,
            entityID: snapshot.id,
            ok: true,
            details: snapshot
          )
        )
      }
    }
  }

  private static func printAdminTransact(
    context: CLIContext,
    output: OutputMode,
    options: AdminTransactOptions,
    result: InstantStoreMutationResult
  ) async throws {
    let emission = try await context.runtime.queryOnce(options.query)
    let pending = await context.runtime.pendingMutations()
    let payload = AdminTransactOutput(
      appID: context.appID,
      cachePath: context.cacheURL.path,
      event: "transact",
      changedID: options.entityID,
      transport: "not-implemented-local-cache-only",
      namespace: options.namespace,
      transactionID: result.transactionID,
      changedEntityIDs: result.changedEntityIDs.sorted(),
      tripleCount: result.tripleCount,
      queryID: options.query.id,
      cacheKey: options.query.cacheKey,
      pendingMutationCount: pending.count,
      snapshotCount: emission.values.count,
      snapshots: emission.values
    )

    switch output {
    case .human:
      print("transact: \(options.namespace)/\(options.entityID)")
      print("transaction: \(payload.transactionID)")
      print("changed entities: \(payload.changedEntityIDs.joined(separator: ","))")
      for snapshot in payload.snapshots {
        let fields = snapshot.values.keys.sorted().joined(separator: ",")
        print("\(snapshot.namespace)/\(snapshot.id) fields=\(fields)")
      }
      print("transport: \(payload.transport)")
      print("pending mutations: \(pending.count)")
      print("cache: \(context.cacheURL.path)")

    case .json:
      try writeJSON(payload)

    case .jsonl:
      try writeJSONLine(
        EvidenceRow(
          caseID: "cli.admin.transact",
          side: "swift",
          event: "transact",
          appID: context.appID,
          entityID: options.entityID,
          ok: true,
          details: payload
        )
      )
      for snapshot in payload.snapshots {
        try writeJSONLine(
          EvidenceRow(
            caseID: "cli.admin.transact",
            side: "swift",
            event: "snapshot",
            appID: context.appID,
            entityID: snapshot.id,
            ok: true,
            details: snapshot
          )
        )
      }
    }
  }

  private static func printPageInfo(_ pageInfo: InstantQueryPageInfo?) {
    guard let pageInfo else { return }
    let start = pageInfo.startCursor?.entityID ?? "-"
    let end = pageInfo.endCursor?.entityID ?? "-"
    print(
      "page: start=\(start) end=\(end) previous=\(pageInfo.hasPreviousPage) next=\(pageInfo.hasNextPage)"
    )
  }

  private static func watchTodos(
    context: CLIContext,
    output: OutputMode,
    options: TodoWatchOptions
  ) async throws {
    _ = try await context.runtime.queryOnce(options.query)
    let stream = await context.runtime.observe(options.query)
    var iterator = stream.makeAsyncIterator()
    var emissions: [TodoWatchEmissionOutput] = []
    emissions.reserveCapacity(options.eventCount)

    while emissions.count < options.eventCount {
      guard let emission = await iterator.next() else { break }
      let todos = try TodoExample.decode(emission.values)
      let pending = await context.runtime.pendingMutations()
      let payload = TodoWatchEmissionOutput(
        appID: context.appID,
        cachePath: context.cacheURL.path,
        event: "watch",
        transport: "not-implemented-local-cache-only",
        queryID: options.query.id,
        cacheKey: options.query.cacheKey,
        emissionIndex: emissions.count,
        sequence: emission.sequence,
        pageInfo: emission.pageInfo,
        pendingMutationCount: pending.count,
        todos: todos
      )

      switch output {
      case .human:
        print("event: watch index=\(payload.emissionIndex) sequence=\(payload.sequence)")
        if todos.isEmpty {
          print("No todos.")
        } else {
          for todo in todos {
            let mark = todo.isCompleted ? "[x]" : "[ ]"
            print("\(mark) \(todo.id) \(todo.text)")
          }
        }
        printPageInfo(payload.pageInfo)
        print("pending mutations: \(pending.count)")
        print("cache: \(context.cacheURL.path)")

      case .json, .jsonl:
        break
      }

      emissions.append(payload)

      if output == .jsonl {
        try writeJSONLine(
          EvidenceRow(
            caseID: "cli.examples.todos.watch",
            side: "swift",
            event: "watch",
            appID: context.appID,
            ok: true,
            details: payload
          )
        )
      }
    }

    switch output {
    case .human, .jsonl:
      break

    case .json:
      try writeJSON(
        TodoWatchOutput(
          appID: context.appID,
          cachePath: context.cacheURL.path,
          event: "watch",
          transport: "not-implemented-local-cache-only",
          queryID: options.query.id,
          cacheKey: options.query.cacheKey,
          requestedEventCount: options.eventCount,
          emittedEventCount: emissions.count,
          emissions: emissions
        )
      )
    }
  }

  private static func printHelp() {
    print(
      """
      instant-swift-data

      Commands:
        init --example todos --to <directory> [--force] [--json|--jsonl]
        schema generate --example todos [--to instant.schema.ts] [--json|--jsonl]
        schema verify --example todos --from instant.schema.ts [--json|--jsonl]
        perms generate --example todos [--to instant.perms.ts] [--json|--jsonl]
        perms verify --example todos --from instant.perms.ts [--json|--jsonl]
        query todos [--completed true|false] [--search text] [--offset n] [--limit n] [--first n] [--after id] [--after-inclusive id] [--last n] [--before id] [--before-inclusive id] [--order asc|desc] [--order-by none|createdAt|serverCreatedAt] [--raw] [--select field[,field]] [--json|--jsonl]
        admin query <namespace> [--limit n] [--json|--jsonl]
        admin transact <namespace> <entity-id> --merge '{...}' [--json|--jsonl]
        examples todos seed [--json|--jsonl]
        examples todos add "do the dishes" [--json|--jsonl]
        examples todos list [--completed true|false] [--search text] [--offset n] [--limit n] [--first n] [--after id] [--after-inclusive id] [--last n] [--before id] [--before-inclusive id] [--order asc|desc] [--order-by none|createdAt|serverCreatedAt] [--json|--jsonl]
        examples todos watch [--events 1] [--completed true|false] [--search text] [--offset n] [--limit n] [--first n] [--after id] [--after-inclusive id] [--last n] [--before id] [--before-inclusive id] [--order asc|desc] [--order-by none|createdAt|serverCreatedAt] [--json|--jsonl]
        examples todos complete <todo-id> [--json|--jsonl]
        examples todos update <todo-id> "new text" [--json|--jsonl]
        examples todos delete <todo-id> [--json|--jsonl]
        examples todos reset [--json|--jsonl]
        examples todos refresh [--completed true|false] [--search text] [--offset n] [--limit n] [--first n] [--after id] [--after-inclusive id] [--last n] [--before id] [--before-inclusive id] [--order asc|desc] [--order-by none|createdAt|serverCreatedAt] [--json|--jsonl]
        examples todo-links seed [--json|--jsonl]
        examples todo-links list [--json|--jsonl]
        examples todo-links nested [--json|--jsonl]
        examples todo-links unlink [--json|--jsonl]
        cache inspect [--json|--jsonl]
        cache attributes [namespace] [--json|--jsonl]
        cache triples [namespace] [--json|--jsonl]
        outbox inspect [--json|--jsonl]
        outbox transport [--all] [--json|--jsonl]
        outbox flush [--limit n] [--json|--jsonl]
        outbox confirm <mutation-id> [--json|--jsonl]
        outbox fail <mutation-id> "reason" [--json|--jsonl]
        outbox retry <mutation-id> [--json|--jsonl]
        outbox drain --local-confirm [--limit n] [--json|--jsonl]
        local-id get <name> [--json|--jsonl]
        local-id list [--json|--jsonl]
        auth show [--json|--jsonl]
        auth guest [--json|--jsonl]
        auth token <refresh-token> [--user-id id] [--json|--jsonl]
        auth id-token <client-name> <id-token> [--nonce nonce] [--json|--jsonl]
        auth oauth <code> [--code-verifier verifier] [--json|--jsonl]
        auth oauth-url <client-name> <redirect-url> [--json|--jsonl]
        auth issuer [--json|--jsonl]
        auth magic-code send <email> [--json|--jsonl]
        auth magic-code verify <email> <code> [--json|--jsonl]
        auth watch [--events 1] [--json|--jsonl]
        auth sign-out [--skip-token-invalidation] [--json|--jsonl]
        rooms presence set <room-type> <room-id> --value '{...}' [--user-id id] [--json|--jsonl]
        rooms presence list <room-type> <room-id> [--json|--jsonl]
        rooms presence leave <room-type> <room-id> [--user-id id] [--json|--jsonl]
        rooms topics publish <room-type> <room-id> <topic> --value '{...}' [--user-id id] [--json|--jsonl]
        rooms topics list <room-type> <room-id> <topic> [--limit n] [--json|--jsonl]
        files upload <path> [--name name] [--content-type type] [--json|--jsonl]
        files list [--json|--jsonl]
        files delete <file-id> [--json|--jsonl]
        streams append <stream-id> --value '{...}' [--json|--jsonl]
        streams read <stream-id> [--limit n] [--json|--jsonl]
        shares create <namespace> <entity-id> [--json|--jsonl]
        shares list [--json|--jsonl]
        shares accept <token> [--json|--jsonl]
        shares revoke <share-id> [--json|--jsonl]
        app show [--json|--jsonl]
        app select <app-id> [--json|--jsonl]
        app ephemeral --title <title> [--json|--jsonl]
        connection status [--json|--jsonl]
        connection connect [--json|--jsonl]
        connection close [--json|--jsonl]
        sync inspect [--json|--jsonl]
        sync mark-processed <tx-id> [--json|--jsonl]
        validation local-todos [--json|--jsonl]
        benchmark [--suite local-todos] [--iterations n] [--app-id id] [--json|--jsonl]

      Environment:
        INSTANT_SWIFT_DATA_HOME  Directory for CLI SQLite state. Defaults to ~/.instant-swift-data.
        INSTANT_APP_ID           Logical app id recorded in output. Defaults to local-demo.
        INSTANT_API_URI          Instant HTTP API endpoint. Defaults to https://api.instantdb.com.
        INSTANT_WEBSOCKET_URI    Instant WebSocket endpoint. Defaults to wss://api.instantdb.com/runtime/session.
      """
    )
  }

  private static func requireTodoExample(_ example: String) throws {
    guard example == "todos" else {
      throw CLIError("Only '--example todos' is implemented in this core slice.", exitCode: 64)
    }
  }

  private static func printGeneratedArtifact(
    _ contents: String,
    kind: String,
    fileName: String,
    example: String,
    to outputPath: String?,
    output: OutputMode,
    caseID: String,
    appID: String
  ) throws {
    let data = Data(contents.utf8)
    let path: String?
    if let outputPath {
      path = try writeGenerated(contents, to: outputPath)
    } else {
      path = nil
    }

    let summary = GeneratedArtifactOutput(
      example: example,
      kind: kind,
      fileName: fileName,
      path: path,
      byteCount: data.count,
      transport: "not-implemented-local-cache-only",
      contents: path == nil ? contents : nil
    )

    switch output {
    case .human:
      guard outputPath == nil else { return }
      FileHandle.standardOutput.write(data)

    case .json:
      try writeJSON(summary)

    case .jsonl:
      try writeJSONLine(
        EvidenceRow(
          caseID: caseID,
          side: "swift",
          event: "artifact",
          appID: appID,
          entityID: path ?? fileName,
          ok: true,
          details: summary
        )
      )
    }
  }

  private static func writeGenerated(_ contents: String, to outputPath: String) throws -> String {
    let data = Data(contents.utf8)
    let currentDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    let url = URL(fileURLWithPath: outputPath, relativeTo: currentDirectory).standardizedFileURL
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try data.write(to: url, options: .atomic)
    return url.path
  }

  private static func scaffoldTodoExample(
    options: ScaffoldOptions,
    output: OutputMode
  ) throws {
    let currentDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    let directoryURL = URL(fileURLWithPath: options.outputDirectory, relativeTo: currentDirectory)
      .standardizedFileURL

    let fileSpecs = [
      ScaffoldFileSpec(
        contents: try TypeScriptSchemaPrinter().printSchema(InstantSchemaExamples.todosDocument),
        fileName: "instant.schema.ts",
        kind: "schema"
      ),
      ScaffoldFileSpec(
        contents: try TypeScriptPermissionsPrinter().printPermissions(InstantSchemaExamples.todoPermissions),
        fileName: "instant.perms.ts",
        kind: "permissions"
      ),
      ScaffoldFileSpec(
        contents: scaffoldSchemaSwift,
        fileName: "Schema.swift",
        kind: "swift-schema"
      ),
      ScaffoldFileSpec(
        contents: scaffoldReadme,
        fileName: "README.md",
        kind: "readme"
      ),
    ]
    try preflightScaffoldWrite(fileSpecs: fileSpecs, directoryURL: directoryURL, force: options.force)
    let files = try fileSpecs.map {
      try writeScaffoldFile($0, directoryURL: directoryURL, force: options.force)
    }

    let summary = ScaffoldOutput(
      example: options.example,
      directory: directoryURL.path,
      transport: "not-implemented-local-cache-only",
      files: files
    )

    switch output {
    case .human:
      print("scaffold: \(summary.example)")
      print("transport: \(summary.transport)")
      print("directory: \(summary.directory)")
      for file in summary.files {
        print("- \(file.kind): \(file.path)")
      }

    case .json:
      try writeJSON(summary)

    case .jsonl:
      try writeJSONLine(
        EvidenceRow(
          caseID: "cli.init",
          side: "swift",
          event: "summary",
          appID: "scaffold",
          ok: true,
          details: summary
        )
      )
      for file in summary.files {
        try writeJSONLine(
          EvidenceRow(
            caseID: "cli.init",
            side: "swift",
            event: "file",
            appID: "scaffold",
            entityID: file.path,
            ok: true,
            details: file
          )
        )
      }
    }
  }

  private static func writeScaffoldFile(
    _ fileSpec: ScaffoldFileSpec,
    directoryURL: URL,
    force: Bool
  ) throws -> ScaffoldFileOutput {
    let url = directoryURL.appendingPathComponent(fileSpec.fileName)
    try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    if !force && FileManager.default.fileExists(atPath: url.path) {
      throw CLIError(
        "Scaffold refused to overwrite existing file: \(url.path). Re-run with --force to replace it.",
        exitCode: 73
      )
    }
    try Data(fileSpec.contents.utf8).write(to: url, options: .atomic)
    return ScaffoldFileOutput(kind: fileSpec.kind, path: url.path)
  }

  private static func preflightScaffoldWrite(
    fileSpecs: [ScaffoldFileSpec],
    directoryURL: URL,
    force: Bool
  ) throws {
    var isDirectory: ObjCBool = false
    let fileManager = FileManager.default
    if fileManager.fileExists(atPath: directoryURL.path, isDirectory: &isDirectory),
      !isDirectory.boolValue
    {
      throw CLIError(
        "Scaffold destination exists and is not a directory: \(directoryURL.path)",
        exitCode: 73
      )
    }
    guard !force else { return }

    let existingPaths = fileSpecs
      .map { directoryURL.appendingPathComponent($0.fileName).path }
      .filter { fileManager.fileExists(atPath: $0) }
    guard existingPaths.isEmpty else {
      throw CLIError(
        """
        Scaffold refused to overwrite existing file(s): \(existingPaths.joined(separator: ", ")). \
        Re-run with --force to replace them.
        """,
        exitCode: 73
      )
    }
  }

  private static var scaffoldSchemaSwift: String {
    """
    import InstantSwiftDataSchema

    public enum AppSchema {
      public static let schema = InstantSchemaExamples.todosDocument
      public static let permissions = InstantSchemaExamples.todoPermissions
    }

    """
  }

  private static var scaffoldReadme: String {
    """
    # Instant Swift Data Todo Scaffold

    This scaffold is generated from the Swift-owned `InstantSchemaExamples.todosDocument`
    and `InstantSchemaExamples.todoPermissions` fixtures.

    Verify the generated files:

    ```bash
    swift run instant-swift-data schema verify --example todos --from instant.schema.ts --json
    swift run instant-swift-data perms verify --example todos --from instant.perms.ts --json
    ```

    The current transport is intentionally `not-implemented-local-cache-only`.
    It proves local schema/perms generation and CLI workflows, not a pushed Instant app.
    Re-run `instant-swift-data init ... --force` to replace generated files.

    """
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

  private static func verifyPermissions(
    options: PermissionsVerifyOptions,
    output: OutputMode
  ) throws {
    let currentDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    let url = URL(fileURLWithPath: options.inputPath, relativeTo: currentDirectory)
      .standardizedFileURL
    let source = try String(contentsOf: url, encoding: .utf8)
    let parsed: InstantPermissionsDocument
    do {
      parsed = try TypeScriptPermissionsParser().parse(source)
    } catch let error as TypeScriptPermissionsParseError {
      throw CLIError("Permissions parse failed: \(error.description)", exitCode: 66)
    } catch let error as TypeScriptSchemaParseError {
      throw CLIError("Permissions parse failed: \(error.description)", exitCode: 66)
    }

    let expected = InstantSchemaExamples.todoPermissions
    guard parsed == expected else {
      throw CLIError("Permissions do not match --example todos.", exitCode: 66)
    }

    let summary = PermissionsVerifyOutput(
      example: options.example,
      path: url.path,
      namespaceCount: parsed.namespaces.count,
      allowRuleCount: allowRuleCount(in: parsed),
      rateLimitCount: parsed.rateLimits.count
    )

    switch output {
    case .human:
      print("permissions: ok")
      print("example: \(summary.example)")
      print("namespaces: \(summary.namespaceCount)")
      print("allow rules: \(summary.allowRuleCount)")
      print("rate limits: \(summary.rateLimitCount)")
      print("path: \(summary.path)")

    case .json:
      try writeJSON(summary)

    case .jsonl:
      try writeJSONLine(
        EvidenceRow(
          caseID: "cli.perms.verify",
          side: "swift",
          event: "summary",
          appID: "permissions-tooling",
          ok: true,
          details: summary
        )
      )
    }
  }

  private static func printLocalTodoValidation(
    result: LocalTodoValidationResult,
    output: OutputMode
  ) throws {
    let summary = LocalTodoValidationOutput(
      appID: result.appID,
      cachePath: result.cacheURL.path,
      event: "local-todos",
      transport: "not-implemented-local-cache-only",
      ok: result.evidence.allSatisfy { $0.ok },
      evidenceCount: result.evidence.count,
      events: result.evidence.map(\.event),
      finalTodoCount: result.evidence.last?.details.todoIDs.count ?? 0,
      pendingMutationCount: result.evidence.last?.details.pendingMutationIDs.count ?? 0
    )

    switch output {
    case .human:
      print("validation: \(summary.ok ? "ok" : "failed")")
      print("case: validation.local.todos")
      print("events: \(summary.events.joined(separator: ", "))")
      print("evidence rows: \(summary.evidenceCount)")
      print("pending mutations: \(summary.pendingMutationCount)")
      print("cache: \(summary.cachePath)")

    case .json:
      try writeJSON(summary)

    case .jsonl:
      for row in result.evidence {
        try writeJSONLine(row)
      }
    }
  }

  private static func printBenchmark(
    result: InstantLocalTodoBenchmarkResult,
    output: OutputMode
  ) throws {
    switch output {
    case .human:
      print("benchmark: \(result.ok ? "ok" : "failed")")
      print("suite: \(result.suite)")
      print("iterations: \(result.iterations)")
      print("transport: \(result.transport)")
      print("final todos: \(result.finalTodoCount)")
      print("pending mutations: \(result.pendingMutationCount)")
      print("cache: \(result.cachePath)")
      for metric in result.metrics {
        print(
          "\(metric.name): p50 \(metric.p50Nanoseconds) ns, p95 \(metric.p95Nanoseconds) ns"
        )
      }

    case .json:
      try writeJSON(result)

    case .jsonl:
      for row in result.evidenceRows {
        try writeJSONLine(row)
      }
    }
  }

  private static func validationAppID() -> String {
    let appID = ProcessInfo.processInfo.environment["INSTANT_APP_ID"]?
      .trimmingCharacters(in: .whitespacesAndNewlines)
    guard let appID, !appID.isEmpty else {
      return "local-demo"
    }
    return appID
  }

  private static func validationFailureRow(
    appID: String,
    error: any Error
  ) -> ValidationEvidenceRow<[String: String]> {
    ValidationEvidenceRow(
      caseID: "validation.local.todos",
      side: "swift",
      event: "failed",
      appID: appID,
      timestampMs: Int64((Date().timeIntervalSince1970 * 1000).rounded()),
      ok: false,
      details: ["message": String(describing: error)]
    )
  }

  private static func allowRuleCount(in document: InstantPermissionsDocument) -> Int {
    (document.attrs?.allow.count ?? 0)
      + (document.defaults?.allow.count ?? 0)
      + document.namespaces.reduce(0) { $0 + $1.allow.count }
  }

  private static func parseAuthUserID(arguments: [String]) throws -> String? {
    var arguments = arguments
    var userID: String?
    while let option = arguments.popFirstArgument() {
      switch option {
      case "--user-id":
        guard let value = arguments.popFirstArgument(),
          !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
          throw CLIError(
            "Usage: instant-swift-data auth token <refresh-token> [--user-id id] [--json|--jsonl]",
            exitCode: 64
          )
        }
        userID = value

      default:
        throw CLIError(
          "Unknown auth token option: \(option). Usage: instant-swift-data auth token <refresh-token> [--user-id id] [--json|--jsonl]",
          exitCode: 64
        )
      }
    }
    return userID
  }

  private static func parseAuthIDTokenNonce(arguments: [String]) throws -> String? {
    var arguments = arguments
    var nonce: String?
    while let option = arguments.popFirstArgument() {
      switch option {
      case "--nonce":
        guard let value = arguments.popFirstArgument(),
          !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
          throw CLIError(
            "Usage: instant-swift-data auth id-token <client-name> <id-token> [--nonce nonce] [--json|--jsonl]",
            exitCode: 64
          )
        }
        nonce = value

      default:
        throw CLIError(
          "Unknown auth id-token option: \(option). Usage: instant-swift-data auth id-token <client-name> <id-token> [--nonce nonce] [--json|--jsonl]",
          exitCode: 64
        )
      }
    }
    return nonce
  }

  private static func parseAuthOAuthCodeVerifier(arguments: [String]) throws -> String? {
    var arguments = arguments
    var codeVerifier: String?
    while let option = arguments.popFirstArgument() {
      switch option {
      case "--code-verifier":
        guard let value = arguments.popFirstArgument(),
          !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
          throw CLIError(
            "Usage: instant-swift-data auth oauth <code> [--code-verifier verifier] [--json|--jsonl]",
            exitCode: 64
          )
        }
        codeVerifier = value

      default:
        throw CLIError(
          "Unknown auth oauth option: \(option). Usage: instant-swift-data auth oauth <code> [--code-verifier verifier] [--json|--jsonl]",
          exitCode: 64
        )
      }
    }
    return codeVerifier
  }

  private static func parseAuthSignOutInvalidateToken(arguments: [String]) throws -> Bool {
    var arguments = arguments
    var invalidateToken = true
    while let option = arguments.popFirstArgument() {
      switch option {
      case "--invalidate-token":
        invalidateToken = true

      case "--skip-token-invalidation", "--no-invalidate-token":
        invalidateToken = false

      default:
        throw CLIError(
          "Unknown auth sign-out option: \(option). Usage: instant-swift-data auth sign-out [--skip-token-invalidation] [--json|--jsonl]",
          exitCode: 64
        )
      }
    }
    return invalidateToken
  }

  private static func parseAuthWatchEventCount(arguments: [String]) throws -> Int {
    var arguments = arguments
    var eventCount = 1
    while let option = arguments.popFirstArgument() {
      switch option {
      case "--events":
        guard let value = arguments.popFirstArgument(),
          let parsed = Int(value),
          parsed == 1
        else {
          throw CLIError("Usage: instant-swift-data auth watch --events 1", exitCode: 64)
        }
        eventCount = parsed

      default:
        throw CLIError(
          "Unknown auth watch option: \(option). Usage: instant-swift-data auth watch [--events 1] [--json|--jsonl]",
          exitCode: 64
        )
      }
    }
    return eventCount
  }

  private static func todoListQuery(
    arguments: [String],
    usageCommand: String = "instant-swift-data examples todos list"
  ) throws -> InstantQueryPlan {
    var arguments = arguments
    let usage = "\(usageCommand) [--completed true|false] [--search text] [--offset n] [--limit n] [--first n] [--after id] [--after-inclusive id] [--last n] [--before id] [--before-inclusive id] [--order asc|desc] [--order-by none|createdAt|serverCreatedAt]"
    var completed: Bool?
    var search: String?
    var offset: Int?
    var limit: Int?
    var first: Int?
    var after: InstantQueryCursor?
    var last: Int?
    var before: InstantQueryCursor?
    var direction = InstantQuerySortDirection.ascending
    var orderField = "createdAt"

    while let option = arguments.popFirstArgument() {
      switch option {
      case "--completed":
        guard let value = arguments.popFirstArgument(), let parsed = parseBool(value) else {
          throw CLIError("Usage: \(usageCommand) --completed true|false", exitCode: 64)
        }
        completed = parsed

      case "--search":
        guard let value = arguments.popFirstArgument(),
          !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
          throw CLIError("Usage: \(usageCommand) --search text", exitCode: 64)
        }
        search = value

      case "--limit":
        guard let value = arguments.popFirstArgument(),
          let parsed = Int(value),
          parsed >= 0
        else {
          throw CLIError("Usage: \(usageCommand) --limit n", exitCode: 64)
        }
        limit = parsed

      case "--first":
        guard let value = arguments.popFirstArgument(),
          let parsed = Int(value),
          parsed >= 0
        else {
          throw CLIError("Usage: \(usageCommand) --first n", exitCode: 64)
        }
        first = parsed

      case "--after", "--after-inclusive":
        guard let value = arguments.popFirstArgument() else {
          throw CLIError("Usage: \(usageCommand) \(option) id", exitCode: 64)
        }
        after = try parseTodoCursor(
          value,
          inclusive: option == "--after-inclusive",
          usageCommand: usageCommand,
          option: option
        )

      case "--last":
        guard let value = arguments.popFirstArgument(),
          let parsed = Int(value),
          parsed >= 0
        else {
          throw CLIError("Usage: \(usageCommand) --last n", exitCode: 64)
        }
        last = parsed

      case "--before", "--before-inclusive":
        guard let value = arguments.popFirstArgument() else {
          throw CLIError("Usage: \(usageCommand) \(option) id", exitCode: 64)
        }
        before = try parseTodoCursor(
          value,
          inclusive: option == "--before-inclusive",
          usageCommand: usageCommand,
          option: option
        )

      case "--offset":
        guard let value = arguments.popFirstArgument(),
          let parsed = Int(value),
          parsed >= 0
        else {
          throw CLIError("Usage: \(usageCommand) --offset n", exitCode: 64)
        }
        offset = parsed

      case "--order":
        guard let value = arguments.popFirstArgument(), let parsed = parseSortDirection(value) else {
          throw CLIError("Usage: \(usageCommand) --order asc|desc", exitCode: 64)
        }
        direction = parsed

      case "--order-by":
        guard let value = arguments.popFirstArgument(), let parsed = parseTodoOrderField(value) else {
          throw CLIError("Usage: \(usageCommand) --order-by none|createdAt|serverCreatedAt", exitCode: 64)
        }
        orderField = parsed

      default:
        throw CLIError(
          "Unknown todo list option: \(option). Usage: \(usage)",
          exitCode: 64
        )
      }
    }

    guard first == nil || last == nil else {
      throw CLIError(
        "Use either --first or --last, not both. Usage: \(usage)",
        exitCode: 64
      )
    }

    return makeTodoListQuery(
      completed: completed,
      search: search,
      offset: offset,
      limit: limit,
      first: first,
      after: after,
      last: last,
      before: before,
      direction: direction,
      orderField: orderField
    )
  }

  private static func todoQueryOptions(
    arguments: [String],
    usageCommand: String
  ) throws -> TodoQueryOptions {
    var arguments = arguments
    let usage =
      "\(usageCommand) [--completed true|false] [--search text] [--offset n] [--limit n] [--first n] [--after id] [--after-inclusive id] [--last n] [--before id] [--before-inclusive id] [--order asc|desc] [--order-by none|createdAt|serverCreatedAt] [--raw] [--select field[,field]]"
    var completed: Bool?
    var search: String?
    var offset: Int?
    var limit: Int?
    var first: Int?
    var after: InstantQueryCursor?
    var last: Int?
    var before: InstantQueryCursor?
    var direction = InstantQuerySortDirection.ascending
    var orderField = "createdAt"
    var selectedFields: [String]?
    var rawSnapshots = false

    while let option = arguments.popFirstArgument() {
      switch option {
      case "--completed":
        guard let value = arguments.popFirstArgument(), let parsed = parseBool(value) else {
          throw CLIError("Usage: \(usageCommand) --completed true|false", exitCode: 64)
        }
        completed = parsed

      case "--search":
        guard let value = arguments.popFirstArgument(),
          !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
          throw CLIError("Usage: \(usageCommand) --search text", exitCode: 64)
        }
        search = value

      case "--limit":
        guard let value = arguments.popFirstArgument(),
          let parsed = Int(value),
          parsed >= 0
        else {
          throw CLIError("Usage: \(usageCommand) --limit n", exitCode: 64)
        }
        limit = parsed

      case "--first":
        guard let value = arguments.popFirstArgument(),
          let parsed = Int(value),
          parsed >= 0
        else {
          throw CLIError("Usage: \(usageCommand) --first n", exitCode: 64)
        }
        first = parsed

      case "--after", "--after-inclusive":
        guard let value = arguments.popFirstArgument() else {
          throw CLIError("Usage: \(usageCommand) \(option) id", exitCode: 64)
        }
        after = try parseTodoCursor(
          value,
          inclusive: option == "--after-inclusive",
          usageCommand: usageCommand,
          option: option
        )

      case "--last":
        guard let value = arguments.popFirstArgument(),
          let parsed = Int(value),
          parsed >= 0
        else {
          throw CLIError("Usage: \(usageCommand) --last n", exitCode: 64)
        }
        last = parsed

      case "--before", "--before-inclusive":
        guard let value = arguments.popFirstArgument() else {
          throw CLIError("Usage: \(usageCommand) \(option) id", exitCode: 64)
        }
        before = try parseTodoCursor(
          value,
          inclusive: option == "--before-inclusive",
          usageCommand: usageCommand,
          option: option
        )

      case "--offset":
        guard let value = arguments.popFirstArgument(),
          let parsed = Int(value),
          parsed >= 0
        else {
          throw CLIError("Usage: \(usageCommand) --offset n", exitCode: 64)
        }
        offset = parsed

      case "--order":
        guard let value = arguments.popFirstArgument(), let parsed = parseSortDirection(value) else {
          throw CLIError("Usage: \(usageCommand) --order asc|desc", exitCode: 64)
        }
        direction = parsed

      case "--order-by":
        guard let value = arguments.popFirstArgument(), let parsed = parseTodoOrderField(value) else {
          throw CLIError("Usage: \(usageCommand) --order-by none|createdAt|serverCreatedAt", exitCode: 64)
        }
        orderField = parsed

      case "--raw", "--snapshots":
        rawSnapshots = true

      case "--select":
        guard let value = arguments.popFirstArgument() else {
          throw CLIError("Usage: \(usageCommand) --select field[,field]", exitCode: 64)
        }
        selectedFields = try parseTodoSelectedFields(value, usageCommand: usageCommand)
        rawSnapshots = true

      default:
        throw CLIError(
          "Unknown todo query option: \(option). Usage: \(usage)",
          exitCode: 64
        )
      }
    }

    guard first == nil || last == nil else {
      throw CLIError(
        "Use either --first or --last, not both. Usage: \(usage)",
        exitCode: 64
      )
    }

    return TodoQueryOptions(
      query: makeTodoListQuery(
        completed: completed,
        search: search,
        offset: offset,
        limit: limit,
        first: first,
        after: after,
        last: last,
        before: before,
        direction: direction,
        orderField: orderField,
        selectedFields: selectedFields
      ),
      rawSnapshots: rawSnapshots
    )
  }

  private static func todoWatchOptions(arguments: [String]) throws -> TodoWatchOptions {
    var arguments = arguments
    var completed: Bool?
    var search: String?
    var offset: Int?
    var limit: Int?
    var first: Int?
    var after: InstantQueryCursor?
    var last: Int?
    var before: InstantQueryCursor?
    var direction = InstantQuerySortDirection.ascending
    var orderField = "createdAt"
    var eventCount = 1

    while let option = arguments.popFirstArgument() {
      switch option {
      case "--completed":
        guard let value = arguments.popFirstArgument(), let parsed = parseBool(value) else {
          throw CLIError("Usage: instant-swift-data examples todos watch --completed true|false", exitCode: 64)
        }
        completed = parsed

      case "--search":
        guard let value = arguments.popFirstArgument(),
          !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
          throw CLIError("Usage: instant-swift-data examples todos watch --search text", exitCode: 64)
        }
        search = value

      case "--limit":
        guard let value = arguments.popFirstArgument(),
          let parsed = Int(value),
          parsed >= 0
        else {
          throw CLIError("Usage: instant-swift-data examples todos watch --limit n", exitCode: 64)
        }
        limit = parsed

      case "--first":
        guard let value = arguments.popFirstArgument(),
          let parsed = Int(value),
          parsed >= 0
        else {
          throw CLIError("Usage: instant-swift-data examples todos watch --first n", exitCode: 64)
        }
        first = parsed

      case "--after", "--after-inclusive":
        guard let value = arguments.popFirstArgument() else {
          throw CLIError("Usage: instant-swift-data examples todos watch \(option) id", exitCode: 64)
        }
        after = try parseTodoCursor(
          value,
          inclusive: option == "--after-inclusive",
          usageCommand: "instant-swift-data examples todos watch",
          option: option
        )

      case "--last":
        guard let value = arguments.popFirstArgument(),
          let parsed = Int(value),
          parsed >= 0
        else {
          throw CLIError("Usage: instant-swift-data examples todos watch --last n", exitCode: 64)
        }
        last = parsed

      case "--before", "--before-inclusive":
        guard let value = arguments.popFirstArgument() else {
          throw CLIError("Usage: instant-swift-data examples todos watch \(option) id", exitCode: 64)
        }
        before = try parseTodoCursor(
          value,
          inclusive: option == "--before-inclusive",
          usageCommand: "instant-swift-data examples todos watch",
          option: option
        )

      case "--offset":
        guard let value = arguments.popFirstArgument(),
          let parsed = Int(value),
          parsed >= 0
        else {
          throw CLIError("Usage: instant-swift-data examples todos watch --offset n", exitCode: 64)
        }
        offset = parsed

      case "--order":
        guard let value = arguments.popFirstArgument(), let parsed = parseSortDirection(value) else {
          throw CLIError("Usage: instant-swift-data examples todos watch --order asc|desc", exitCode: 64)
        }
        direction = parsed

      case "--order-by":
        guard let value = arguments.popFirstArgument(), let parsed = parseTodoOrderField(value) else {
          throw CLIError("Usage: instant-swift-data examples todos watch --order-by none|createdAt|serverCreatedAt", exitCode: 64)
        }
        orderField = parsed

      case "--events":
        guard let value = arguments.popFirstArgument(),
          let parsed = Int(value),
          parsed == 1
        else {
          throw CLIError("Usage: instant-swift-data examples todos watch --events 1", exitCode: 64)
        }
        eventCount = parsed

      default:
        throw CLIError(
          "Unknown todo watch option: \(option). Usage: instant-swift-data examples todos watch [--events 1] [--completed true|false] [--search text] [--offset n] [--limit n] [--first n] [--after id] [--after-inclusive id] [--last n] [--before id] [--before-inclusive id] [--order asc|desc] [--order-by none|createdAt|serverCreatedAt]",
          exitCode: 64
        )
      }
    }

    guard first == nil || last == nil else {
      throw CLIError(
        "Use either --first or --last, not both. Usage: instant-swift-data examples todos watch [--events 1] [--completed true|false] [--search text] [--offset n] [--limit n] [--first n] [--after id] [--after-inclusive id] [--last n] [--before id] [--before-inclusive id] [--order asc|desc] [--order-by none|createdAt|serverCreatedAt]",
        exitCode: 64
      )
    }

    return TodoWatchOptions(
      query: makeTodoListQuery(
        completed: completed,
        search: search,
        offset: offset,
        limit: limit,
        first: first,
        after: after,
        last: last,
        before: before,
        direction: direction,
        orderField: orderField
      ),
      eventCount: eventCount
    )
  }

  private static func makeTodoListQuery(
    completed: Bool?,
    search: String?,
    offset: Int?,
    limit: Int?,
    first: Int?,
    after: InstantQueryCursor?,
    last: Int?,
    before: InstantQueryCursor?,
    direction: InstantQuerySortDirection,
    orderField: String = "createdAt",
    selectedFields: [String]? = nil
  ) -> InstantQueryPlan {
    var filters: [InstantQueryFilter] = []
    var id = "examples.todos.list"
    if let completed {
      filters.append(.equals(field: "isCompleted", value: .bool(completed)))
      id += ".completed-\(completed)"
    }
    if let search {
      let pattern = "%\(search)%"
      filters.append(.iLike(field: "text", pattern: pattern))
      id += ".search-\(queryIDFragment(search))"
    }
    if orderField != "none", direction != .ascending {
      id += ".order-\(direction.rawValue)"
    }
    if orderField != "createdAt" {
      id += ".order-by-\(orderField)"
    }
    if let offset {
      id += ".offset-\(offset)"
    }
    if let limit {
      id += ".limit-\(limit)"
    }
    if let first {
      id += ".first-\(first)"
    }
    if let after {
      id += ".after-\(queryIDFragment(after.entityID))"
      if after.inclusive {
        id += "-inclusive"
      }
    }
    if let last {
      id += ".last-\(last)"
    }
    if let before {
      id += ".before-\(queryIDFragment(before.entityID))"
      if before.inclusive {
        id += "-inclusive"
      }
    }
    if let selectedFields {
      id += ".select-\(queryIDFragment(selectedFields.joined(separator: ",")))"
    }

    return InstantQueryPlan(
      id: id,
      namespace: TodoExample.namespace,
      filters: filters,
      order: orderField == "none"
        ? nil
        : orderField == InstantQueryOrder.serverCreatedAtField
        ? .serverCreatedAt(direction)
        : InstantQueryOrder(orderField, direction),
      offset: offset,
      limit: limit,
      first: first,
      after: after,
      last: last,
      before: before,
      selectedFields: selectedFields
    )
  }

  private static func parseTodoCursor(
    _ value: String,
    inclusive: Bool,
    usageCommand: String,
    option: String
  ) throws -> InstantQueryCursor {
    let entityID = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !entityID.isEmpty else {
      throw CLIError("Usage: \(usageCommand) \(option) id", exitCode: 64)
    }
    return InstantQueryCursor(entityID: entityID, inclusive: inclusive)
  }

  private static func parseTodoSelectedFields(
    _ value: String,
    usageCommand: String
  ) throws -> [String] {
    let fields = value
      .split(separator: ",")
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
    guard !fields.isEmpty else {
      throw CLIError(
        "Usage: \(usageCommand) --select field[,field]",
        exitCode: 64
      )
    }
    return Array(Set(fields)).sorted()
  }

  private static func queryIDFragment(_ value: String) -> String {
    Data(value.utf8).base64EncodedString()
      .replacingOccurrences(of: "+", with: "-")
      .replacingOccurrences(of: "/", with: "_")
      .replacingOccurrences(of: "=", with: "")
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

  private static func parseTodoOrderField(_ value: String) -> String? {
    switch value {
    case "none":
      return "none"
    case "createdAt":
      return "createdAt"
    case InstantQueryOrder.serverCreatedAtField:
      return InstantQueryOrder.serverCreatedAtField
    default:
      return nil
    }
  }

  private static var outboxUsage: String {
    """
    Usage: instant-swift-data outbox <inspect|transport|flush|confirm|fail|retry|drain>
      instant-swift-data outbox inspect [--json|--jsonl]
      instant-swift-data outbox transport [--all] [--json|--jsonl]
      instant-swift-data outbox flush [--limit n] [--json|--jsonl]
      instant-swift-data outbox confirm <mutation-id> [--json|--jsonl]
      instant-swift-data outbox fail <mutation-id> "reason" [--json|--jsonl]
      instant-swift-data outbox retry <mutation-id> [--json|--jsonl]
      instant-swift-data outbox drain --local-confirm [--limit n] [--json|--jsonl]
    """
  }

  private static func parseOutboxTransportOptions(arguments: [String]) throws -> Bool {
    var arguments = arguments
    var includeFailed = false

    while let option = arguments.popFirstArgument() {
      switch option {
      case "--all":
        includeFailed = true

      default:
        throw CLIError(
          "Usage: instant-swift-data outbox transport [--all] [--json|--jsonl]",
          exitCode: 64
        )
      }
    }

    return includeFailed
  }

  private static func parseOutboxFlushLimit(arguments: [String]) throws -> Int? {
    var arguments = arguments
    var limit: Int?

    while let option = arguments.popFirstArgument() {
      switch option {
      case "--limit":
        guard let value = arguments.popFirstArgument(),
          let parsed = Int(value),
          parsed >= 0
        else {
          throw CLIError(
            "Usage: instant-swift-data outbox flush [--limit n] [--json|--jsonl]",
            exitCode: 64
          )
        }
        limit = parsed

      default:
        throw CLIError(
          "Unknown outbox flush option: \(option). Usage: instant-swift-data outbox flush [--limit n] [--json|--jsonl]",
          exitCode: 64
        )
      }
    }

    return limit
  }

  private static func parseOutboxDrainLimit(arguments: [String]) throws -> Int? {
    var arguments = arguments
    var sawLocalConfirm = false
    var limit: Int?

    while let option = arguments.popFirstArgument() {
      switch option {
      case "--local-confirm":
        sawLocalConfirm = true

      case "--limit":
        guard let value = arguments.popFirstArgument(),
          let parsed = Int(value),
          parsed >= 0
        else {
          throw CLIError(
            "Usage: instant-swift-data outbox drain --local-confirm [--limit n] [--json|--jsonl]",
            exitCode: 64
          )
        }
        limit = parsed

      default:
        throw CLIError(
          "Unknown outbox drain option: \(option). Usage: instant-swift-data outbox drain --local-confirm [--limit n] [--json|--jsonl]",
          exitCode: 64
        )
      }
    }

    guard sawLocalConfirm else {
      throw CLIError(
        "Usage: instant-swift-data outbox drain --local-confirm [--limit n] [--json|--jsonl]",
        exitCode: 64
      )
    }
    return limit
  }

  private static var authUsage: String {
    """
    Usage: instant-swift-data auth <show|guest|token|id-token|oauth|oauth-url|issuer|magic-code|watch|sign-out>
      instant-swift-data auth show [--json|--jsonl]
      instant-swift-data auth guest [--json|--jsonl]
      instant-swift-data auth token <refresh-token> [--user-id id] [--json|--jsonl]
      instant-swift-data auth id-token <client-name> <id-token> [--nonce nonce] [--json|--jsonl]
      instant-swift-data auth oauth <code> [--code-verifier verifier] [--json|--jsonl]
      instant-swift-data auth oauth-url <client-name> <redirect-url> [--json|--jsonl]
      instant-swift-data auth issuer [--json|--jsonl]
      instant-swift-data auth magic-code send <email> [--json|--jsonl]
      instant-swift-data auth magic-code verify <email> <code> [--json|--jsonl]
      instant-swift-data auth watch [--events 1] [--json|--jsonl]
      instant-swift-data auth sign-out [--skip-token-invalidation] [--json|--jsonl]
    """
  }

  private static var magicCodeUsage: String {
    """
    Usage: instant-swift-data auth magic-code <send|verify>
      instant-swift-data auth magic-code send <email> [--json|--jsonl]
      instant-swift-data auth magic-code verify <email> <code> [--json|--jsonl]
    """
  }

  private static var appUsage: String {
    """
    Usage: instant-swift-data app <show|select|ephemeral>
      instant-swift-data app show [--json|--jsonl]
      instant-swift-data app select <app-id> [--json|--jsonl]
      instant-swift-data app ephemeral --title <title> [--json|--jsonl]
    """
  }

  private static var syncUsage: String {
    """
    Usage: instant-swift-data sync <inspect|mark-processed>
      instant-swift-data sync inspect [--json|--jsonl]
      instant-swift-data sync mark-processed <tx-id> [--json|--jsonl]
    """
  }

  private static var connectionUsage: String {
    """
    Usage: instant-swift-data connection <status|connect|close>
      instant-swift-data connection status [--json|--jsonl]
      instant-swift-data connection connect [--json|--jsonl]
      instant-swift-data connection close [--json|--jsonl]
    """
  }

  private static var roomsUsage: String {
    """
    Usage: instant-swift-data rooms <presence|topics>
      instant-swift-data rooms presence set <room-type> <room-id> --value '{...}' [--user-id id] [--json|--jsonl]
      instant-swift-data rooms presence list <room-type> <room-id> [--json|--jsonl]
      instant-swift-data rooms presence leave <room-type> <room-id> [--user-id id] [--json|--jsonl]
      instant-swift-data rooms topics publish <room-type> <room-id> <topic> --value '{...}' [--user-id id] [--json|--jsonl]
      instant-swift-data rooms topics list <room-type> <room-id> <topic> [--limit n] [--json|--jsonl]
    """
  }

  fileprivate static var roomPresenceUsage: String {
    """
    Usage: instant-swift-data rooms presence <set|list|leave>
      instant-swift-data rooms presence set <room-type> <room-id> --value '{...}' [--user-id id] [--json|--jsonl]
      instant-swift-data rooms presence list <room-type> <room-id> [--json|--jsonl]
      instant-swift-data rooms presence leave <room-type> <room-id> [--user-id id] [--json|--jsonl]
    """
  }

  fileprivate static var roomTopicsUsage: String {
    """
    Usage: instant-swift-data rooms topics <publish|list>
      instant-swift-data rooms topics publish <room-type> <room-id> <topic> --value '{...}' [--user-id id] [--json|--jsonl]
      instant-swift-data rooms topics list <room-type> <room-id> <topic> [--limit n] [--json|--jsonl]
    """
  }

  fileprivate static var filesUsage: String {
    """
    Usage: instant-swift-data files <upload|list|delete>
      instant-swift-data files upload <path> [--name name] [--content-type type] [--json|--jsonl]
      instant-swift-data files list [--json|--jsonl]
      instant-swift-data files delete <file-id> [--json|--jsonl]
    """
  }

  fileprivate static var streamsUsage: String {
    """
    Usage: instant-swift-data streams <append|read>
      instant-swift-data streams append <stream-id> --value '{...}' [--json|--jsonl]
      instant-swift-data streams read <stream-id> [--limit n] [--json|--jsonl]
    """
  }

  fileprivate static var sharesUsage: String {
    """
    Usage: instant-swift-data shares <create|list|accept|revoke>
      instant-swift-data shares create <namespace> <entity-id> [--json|--jsonl]
      instant-swift-data shares list [--json|--jsonl]
      instant-swift-data shares accept <token> [--json|--jsonl]
      instant-swift-data shares revoke <share-id> [--json|--jsonl]
    """
  }

  private static var validationUsage: String {
    """
    Usage: instant-swift-data validation <local-todos>
      instant-swift-data validation local-todos [--json|--jsonl]
    """
  }

  private static var queryUsage: String {
    """
    Usage: instant-swift-data query <namespace>
      instant-swift-data query todos [--completed true|false] [--search text] [--offset n] [--limit n] [--first n] [--after id] [--after-inclusive id] [--last n] [--before id] [--before-inclusive id] [--order asc|desc] [--order-by none|createdAt|serverCreatedAt] [--raw] [--select field[,field]] [--json|--jsonl]
    """
  }

  private static var cacheUsage: String {
    """
    Usage: instant-swift-data cache <inspect|attributes|triples>
      instant-swift-data cache inspect [--json|--jsonl]
      instant-swift-data cache attributes [namespace] [--json|--jsonl]
      instant-swift-data cache triples [namespace] [--json|--jsonl]
    """
  }

  private static var localIDUsage: String {
    """
    Usage: instant-swift-data local-id <get|list>
      instant-swift-data local-id get <name> [--json|--jsonl]
      instant-swift-data local-id list [--json|--jsonl]
    """
  }

  private static var adminUsage: String {
    """
    Usage: instant-swift-data admin <query|transact>
      instant-swift-data admin query <namespace> [--limit n] [--json|--jsonl]
      instant-swift-data admin transact <namespace> <entity-id> --merge '{...}' [--json|--jsonl]
    """
  }

  fileprivate static func adminQueryOptions(
    namespace: String,
    limit: Int? = nil
  ) -> AdminQueryOptions {
    let limitFragment = limit.map { ".limit-\($0)" } ?? ""
    return AdminQueryOptions(
      query: InstantQueryPlan(
        id: "admin.\(queryIDFragment(namespace)).query\(limitFragment)",
        namespace: namespace,
        limit: limit
      )
    )
  }

  private static func adminUpsertOperations(
    options: AdminTransactOptions,
    transactionID: String,
    txTime: InstantTimestamp
  ) -> [InstantTripleOperation] {
    let identity = InstantTripleOperation.insert(
      InstantTriple(
        entityID: options.entityID,
        attributeID: InstantAttribute.primaryKeyID(namespace: options.namespace),
        value: .string(options.entityID),
        txID: transactionID,
        txTime: txTime
      )
    )
    let fields = options.fields.map { field in
      InstantTripleOperation.insert(
        InstantTriple(
          entityID: options.entityID,
          attributeID: "\(options.namespace)/\(field.name)",
          value: field.value,
          txID: transactionID,
          txTime: txTime
        )
      )
    }
    return [identity] + fields
  }

  fileprivate static func parseAdminNamespace(_ value: String, usage: String) throws -> String {
    let namespace = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard isValidAdminPathComponent(namespace) else {
      throw CLIError("\(usage): namespace must not be empty or contain whitespace or '/'.", exitCode: 64)
    }
    return namespace
  }

  fileprivate static func parseAdminEntityID(_ value: String, usage: String) throws -> String {
    let entityID = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !entityID.isEmpty else {
      throw CLIError("\(usage): entity id must not be empty.", exitCode: 64)
    }
    return entityID
  }

  fileprivate static func parseAdminField(_ value: String, usage: String) throws -> String {
    let field = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard isValidAdminPathComponent(field) else {
      throw CLIError("\(usage): field names must not be empty or contain whitespace or '/'.", exitCode: 64)
    }
    guard field != "id" else {
      throw CLIError("\(usage): --merge must not include the reserved 'id' field.", exitCode: 64)
    }
    guard field != InstantQueryOrder.serverCreatedAtField else {
      throw CLIError(
        "\(usage): --merge must not include reserved order metadata '\(InstantQueryOrder.serverCreatedAtField)'.",
        exitCode: 64
      )
    }
    return field
  }

  fileprivate static func parseAdminMergeObject(
    _ string: String,
    usage: String
  ) throws -> [String: JSONValue] {
    guard case let .object(values) = try parseJSONValue(string, operation: "admin transact")
    else {
      throw CLIError("\(usage): --merge must be a JSON object.", exitCode: 64)
    }
    guard !values.isEmpty else {
      throw CLIError("\(usage): --merge must include at least one field.", exitCode: 64)
    }
    return values
  }

  fileprivate static func adminFieldValue(
    _ value: JSONValue
  ) -> (value: InstantValue, valueType: InstantValueType) {
    switch value {
    case let .string(value):
      return (.string(value), .string)
    case let .number(value):
      return (.number(value), .number)
    case let .bool(value):
      return (.bool(value), .boolean)
    case .null, .array, .object:
      return (.json(value), .json)
    }
  }

  private static func isValidAdminPathComponent(_ value: String) -> Bool {
    !value.isEmpty
      && !value.contains("/")
      && !value.contains(where: { $0.isWhitespace })
  }

  private static var examplesUsage: String {
    """
    Usage: instant-swift-data examples <todos|todo-links>
      instant-swift-data examples todos <add|seed|list|watch|complete|update|delete|reset|refresh>
      instant-swift-data examples todo-links <seed|list|nested|unlink> [--json|--jsonl]
    """
  }

  private static var todoLinksUsage: String {
    """
    Usage: instant-swift-data examples todo-links <seed|list|nested|unlink>
      instant-swift-data examples todo-links seed [--json|--jsonl]
      instant-swift-data examples todo-links list [--json|--jsonl]
      instant-swift-data examples todo-links nested [--json|--jsonl]
      instant-swift-data examples todo-links unlink [--json|--jsonl]
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

  private static func cacheAttributes(
    _ snapshot: InstantStoreSnapshot,
    namespace: String?
  ) -> [InstantAttribute] {
    snapshot.attributes
      .filter { namespace == nil || $0.namespace == namespace }
      .sorted {
        ($0.namespace, $0.name, $0.id) < ($1.namespace, $1.name, $1.id)
      }
  }

  private static func cacheTriples(
    _ snapshot: InstantStoreSnapshot,
    namespace: String?
  ) -> [InstantTriple] {
    let attributesByID = Dictionary(uniqueKeysWithValues: snapshot.attributes.map { ($0.id, $0) })
    return snapshot.triples
      .filter {
        guard let namespace else { return true }
        return cacheNamespace(forAttributeID: $0.attributeID, attributesByID: attributesByID)
          == namespace
      }
      .sorted {
        (
          cacheNamespace(forAttributeID: $0.attributeID, attributesByID: attributesByID),
          $0.entityID,
          $0.attributeID,
          $0.value.comparableKey,
          $0.txID
        )
          < (
            cacheNamespace(forAttributeID: $1.attributeID, attributesByID: attributesByID),
            $1.entityID,
            $1.attributeID,
            $1.value.comparableKey,
            $1.txID
          )
      }
  }

  private static func cacheNamespace(
    forAttributeID attributeID: String,
    attributesByID: [String: InstantAttribute]
  ) -> String {
    attributesByID[attributeID]?.namespace
      ?? attributeID.split(separator: "/", maxSplits: 1).first.map(String.init)
      ?? "unknown"
  }

  private static func parseOptionalCacheNamespace(
    arguments: [String],
    usage: String
  ) throws -> String? {
    var arguments = arguments
    guard let namespace = arguments.popFirstArgument() else { return nil }
    guard arguments.isEmpty else {
      throw CLIError(usage, exitCode: 64)
    }
    return try parseAdminNamespace(namespace, usage: usage)
  }

  private static func queryCacheSummaries(
    _ entries: [InstantCachedQuery]
  ) -> [CacheQuerySummary] {
    entries.map { entry in
      CacheQuerySummary(
        queryID: entry.queryID,
        cacheKey: entry.cacheKey,
        namespace: entry.plan.namespace,
        resultCount: entry.emission.values.count,
        updatedAt: entry.updatedAt,
        storeRevision: entry.storeRevision
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

  fileprivate static func parseJSONValue(_ string: String, operation: String) throws -> JSONValue {
    guard let data = string.data(using: .utf8) else {
      throw CLIError("\(operation): JSON input must be UTF-8.", exitCode: 64)
    }
    do {
      let object = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
      return try jsonValue(from: object, operation: operation)
    } catch let error as CLIError {
      throw error
    } catch {
      throw CLIError("\(operation): Invalid JSON value: \(error)", exitCode: 64)
    }
  }

  fileprivate static func parseJSONObject(
    _ string: String,
    operation: String
  ) throws -> [String: JSONValue] {
    guard case let .object(values) = try parseJSONValue(string, operation: operation) else {
      throw CLIError("\(operation): --value must be a JSON object.", exitCode: 64)
    }
    return values
  }

  private static func jsonValue(from object: Any, operation: String) throws -> JSONValue {
    switch object {
    case _ as NSNull:
      return .null

    case let value as String:
      return .string(value)

    case let value as NSNumber:
      if CFGetTypeID(value) == CFBooleanGetTypeID() {
        return .bool(value.boolValue)
      }
      return .number(value.doubleValue)

    case let values as [Any]:
      return .array(try values.map { try jsonValue(from: $0, operation: operation) })

    case let values as [String: Any]:
      var object: [String: JSONValue] = [:]
      for key in values.keys.sorted() {
        object[key] = try jsonValue(from: values[key] as Any, operation: operation)
      }
      return .object(object)

    default:
      throw CLIError("\(operation): Unsupported JSON value.", exitCode: 64)
    }
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

private enum CLIAppIDSource: String, Codable, Sendable {
  case argument
  case environment
  case selected
  case `default`
}

private struct CLIContext: Sendable {
  var appID: String
  var appIDSource: CLIAppIDSource
  var cacheURL: URL
  var runtime: InstantRuntime

  static func bootstrap(
    appIDOverride: String? = nil,
    initialAttributes: [InstantAttribute] = TodoExample.attributes
  ) async throws -> Self {
    let environment = ProcessInfo.processInfo.environment
    let homeURL = environment["INSTANT_SWIFT_DATA_HOME"].map(URL.init(fileURLWithPath:))
      ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".instant-swift-data")
    let cacheURL = homeURL.appendingPathComponent("state.sqlite")
    let resolved = try await resolveAppID(
      override: appIDOverride,
      environment: environment,
      cacheURL: cacheURL
    )
    let apiURI = try endpointURL(
      environment["INSTANT_API_URI"],
      defaultURL: InstantRuntimeConfiguration.defaultAPIURI,
      name: "INSTANT_API_URI",
      isValid: InstantRuntimeConfiguration.isValidAPIURI,
      requirement: "an absolute http or https URL with a host and no query or fragment"
    )
    let websocketURI = try endpointURL(
      environment["INSTANT_WEBSOCKET_URI"],
      defaultURL: InstantRuntimeConfiguration.defaultWebSocketURI,
      name: "INSTANT_WEBSOCKET_URI",
      isValid: InstantRuntimeConfiguration.isValidWebSocketURI,
      requirement: "an absolute ws or wss URL with a host and no query or fragment"
    )
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: resolved.appID,
        apiURI: apiURI,
        websocketURI: websocketURI,
        persistenceURL: cacheURL,
        initialAttributes: initialAttributes
      )
    )
    return Self(
      appID: resolved.appID,
      appIDSource: resolved.source,
      cacheURL: cacheURL,
      runtime: runtime
    )
  }

  private static func resolveAppID(
    override: String?,
    environment: [String: String],
    cacheURL: URL
  ) async throws -> (appID: String, source: CLIAppIDSource) {
    if let appID = override?.trimmingCharacters(in: .whitespacesAndNewlines),
      !appID.isEmpty
    {
      return (appID, .argument)
    }
    if let appID = environment["INSTANT_APP_ID"]?.trimmingCharacters(in: .whitespacesAndNewlines),
      !appID.isEmpty
    {
      return (appID, .environment)
    }

    if let appID = try await persistedSelectedAppID(cacheURL: cacheURL) {
      return (appID, .selected)
    }

    return ("local-demo", .default)
  }

  private static func endpointURL(
    _ value: String?,
    defaultURL: URL,
    name: String,
    isValid: (URL) -> Bool,
    requirement: String
  ) throws
    -> URL
  {
    guard let rawValue = value?.trimmingCharacters(in: .whitespacesAndNewlines),
      !rawValue.isEmpty
    else {
      return defaultURL
    }
    guard let url = URL(string: rawValue), isValid(url) else {
      throw CLIError("\(name) must be \(requirement).", exitCode: 64)
    }
    return url
  }

  private static func persistedSelectedAppID(cacheURL: URL) async throws -> String? {
    let persistence = try SQLitePersistenceStore(fileURL: cacheURL)
    try await persistence.bootstrap()
    guard let appID = try await persistence.loadMetadataValue(
      key: InstantRuntime.selectedAppIDMetadataKey
    )?.trimmingCharacters(in: .whitespacesAndNewlines),
      !appID.isEmpty
    else {
      return nil
    }
    return appID
  }
}

private enum OutputMode: Equatable, Sendable {
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
  var queryID: String
  var cacheKey: String
  var pageInfo: InstantQueryPageInfo?
  var pendingMutationCount: Int
  var todos: [TodoRecord]
}

private struct TodoLinksOutput: Codable, Sendable {
  var appID: String
  var cachePath: String
  var event: String
  var changedID: String?
  var transport: String
  var projectQueryID: String
  var todoQueryID: String
  var projectCacheKey: String
  var todoCacheKey: String
  var pendingMutationCount: Int
  var projects: [TodoProjectRecord]
  var todos: [LinkedTodoRecord]
}

private struct TodoLinkSnapshotsOutput: Codable, Sendable {
  var appID: String
  var cachePath: String
  var event: String
  var transport: String
  var todoQueryID: String
  var projectQueryID: String
  var todoCacheKey: String
  var projectCacheKey: String
  var pendingMutationCount: Int
  var todos: [InstantEntitySnapshot]
  var projects: [InstantEntitySnapshot]
}

private struct QuerySnapshotsOutput: Codable, Sendable {
  var appID: String
  var cachePath: String
  var event: String
  var transport: String
  var queryID: String
  var cacheKey: String
  var selectedFields: [String]?
  var pageInfo: InstantQueryPageInfo?
  var pendingMutationCount: Int
  var snapshots: [InstantEntitySnapshot]
}

private struct AdminQueryOptions: Sendable {
  var query: InstantQueryPlan

  static func parse(arguments: [String]) throws -> Self {
    var arguments = arguments
    let usage = "Usage: instant-swift-data admin query <namespace> [--limit n]"
    guard let namespaceArgument = arguments.popFirstArgument() else {
      throw CLIError(usage, exitCode: 64)
    }
    let namespace = try InstantSwiftDataCLI.parseAdminNamespace(
      namespaceArgument,
      usage: usage
    )
    var limit: Int?

    while let option = arguments.popFirstArgument() {
      switch option {
      case "--limit":
        guard let value = arguments.popFirstArgument(),
          let parsed = Int(value),
          parsed >= 0
        else {
          throw CLIError("\(usage): --limit must be a non-negative integer.", exitCode: 64)
        }
        limit = parsed

      default:
        throw CLIError("Unknown admin query option: \(option). \(usage)", exitCode: 64)
      }
    }

    return InstantSwiftDataCLI.adminQueryOptions(namespace: namespace, limit: limit)
  }
}

private struct AdminTransactOptions: Sendable {
  var namespace: String
  var entityID: String
  var fields: [AdminFieldValue]
  var attributes: [InstantAttribute]
  var query: InstantQueryPlan

  static func parse(arguments: [String]) throws -> Self {
    var arguments = arguments
    let usage = "Usage: instant-swift-data admin transact <namespace> <entity-id> --merge '{...}'"
    guard let namespaceArgument = arguments.popFirstArgument(),
      let entityIDArgument = arguments.popFirstArgument()
    else {
      throw CLIError(usage, exitCode: 64)
    }
    let namespace = try InstantSwiftDataCLI.parseAdminNamespace(
      namespaceArgument,
      usage: usage
    )
    let entityID = try InstantSwiftDataCLI.parseAdminEntityID(
      entityIDArgument,
      usage: usage
    )
    var merge: [String: JSONValue]?

    while let option = arguments.popFirstArgument() {
      switch option {
      case "--merge":
        guard merge == nil, let value = arguments.popFirstArgument() else {
          throw CLIError(usage, exitCode: 64)
        }
        merge = try InstantSwiftDataCLI.parseAdminMergeObject(value, usage: usage)

      default:
        throw CLIError("Unknown admin transact option: \(option). \(usage)", exitCode: 64)
      }
    }

    guard let merge else {
      throw CLIError(usage, exitCode: 64)
    }

    var fields: [AdminFieldValue] = []
    var seenFields: Set<String> = []
    for key in merge.keys.sorted() {
      let field = try InstantSwiftDataCLI.parseAdminField(key, usage: usage)
      guard seenFields.insert(field).inserted else {
        throw CLIError("\(usage): duplicate field '\(field)' after normalization.", exitCode: 64)
      }
      let typed = InstantSwiftDataCLI.adminFieldValue(merge[key] ?? .null)
      fields.append(AdminFieldValue(name: field, value: typed.value, valueType: typed.valueType))
    }

    let attributes =
      [InstantAttribute.primaryKey(namespace: namespace)]
      + fields.map { field in
        InstantAttribute(
          id: "\(namespace)/\(field.name)",
          namespace: namespace,
          name: field.name,
          valueType: field.valueType,
          isRequired: false,
          isIndexed: true
        )
      }

    return Self(
      namespace: namespace,
      entityID: entityID,
      fields: fields,
      attributes: attributes,
      query: InstantSwiftDataCLI.adminQueryOptions(namespace: namespace).query
    )
  }
}

private struct AdminFieldValue: Hashable, Codable, Sendable {
  var name: String
  var value: InstantValue
  var valueType: InstantValueType
}

private struct AdminTransactOutput: Codable, Sendable {
  var appID: String
  var cachePath: String
  var event: String
  var changedID: String
  var transport: String
  var namespace: String
  var transactionID: String
  var changedEntityIDs: [String]
  var tripleCount: Int
  var queryID: String
  var cacheKey: String
  var pendingMutationCount: Int
  var snapshotCount: Int
  var snapshots: [InstantEntitySnapshot]
}

private struct TodoQueryOptions: Sendable {
  var query: InstantQueryPlan
  var rawSnapshots: Bool
}

private struct TodoWatchOptions: Sendable {
  var query: InstantQueryPlan
  var eventCount: Int
}

private struct TodoWatchOutput: Codable, Sendable {
  var appID: String
  var cachePath: String
  var event: String
  var transport: String
  var queryID: String
  var cacheKey: String
  var requestedEventCount: Int
  var emittedEventCount: Int
  var emissions: [TodoWatchEmissionOutput]
}

private struct TodoWatchEmissionOutput: Codable, Sendable {
  var appID: String
  var cachePath: String
  var event: String
  var transport: String
  var queryID: String
  var cacheKey: String
  var emissionIndex: Int
  var sequence: Int64
  var pageInfo: InstantQueryPageInfo?
  var pendingMutationCount: Int
  var todos: [TodoRecord]
}

private struct CacheInspectOutput: Codable, Sendable {
  var appID: String
  var cachePath: String
  var transport: String
  var attributeCount: Int
  var tripleCount: Int
  var queryCacheCount: Int
  var outboxMutationCount: Int
  var namespaces: [CacheNamespaceSummary]
  var queries: [CacheQuerySummary]
}

private struct CacheAttributesOutput: Codable, Sendable {
  var appID: String
  var cachePath: String
  var transport: String
  var namespace: String?
  var attributeCount: Int
  var attributes: [InstantAttribute]
}

private struct CacheTriplesOutput: Codable, Sendable {
  var appID: String
  var cachePath: String
  var transport: String
  var namespace: String?
  var tripleCount: Int
  var triples: [InstantTriple]
}

private struct CacheNamespaceSummary: Codable, Sendable {
  var namespace: String
  var entityCount: Int
  var tripleCount: Int
  var attributeCount: Int
}

private struct CacheQuerySummary: Codable, Sendable {
  var queryID: String
  var cacheKey: String
  var namespace: String
  var resultCount: Int
  var updatedAt: InstantTimestamp
  var storeRevision: Int64

  var shortCacheKey: String {
    String(cacheKey.prefix(32))
  }
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

private struct OutboxDrainOutput: Codable, Sendable {
  var appID: String
  var cachePath: String
  var event: String
  var transport: String
  var pendingMutationCount: Int
  var mutationCount: Int
  var drainedMutationCount: Int
  var mutations: [PendingMutation]
}

private struct OutboxTransportOutput: Encodable, Sendable {
  var appID: String
  var cachePath: String
  var event: String
  var transport: String
  var includeFailed: Bool
  var mutationCount: Int
  var txStepCount: Int
  var preconditionCount: Int
  var mutations: [InstantTransportMutation]
}

private struct OutboxFlushOutput: Encodable, Sendable {
  var appID: String
  var cachePath: String
  var event: String
  var transport: String
  var attemptedMutationCount: Int
  var confirmedMutationCount: Int
  var failedMutationCount: Int
  var pendingMutationCount: Int
  var mutationCount: Int
  var request: InstantMutationTransportRequest
  var results: [InstantMutationTransportResult]
  var confirmed: [PendingMutation]
  var failed: [PendingMutation]
}

private struct LocalIDOutput: Codable, Sendable {
  var appID: String
  var cachePath: String
  var transport: String
  var name: String
  var id: String
}

private struct LocalIDsOutput: Codable, Sendable {
  var appID: String
  var cachePath: String
  var transport: String
  var localIDCount: Int
  var localIDs: [InstantLocalID]
}

private struct AuthWatchOutput: Codable, Sendable {
  var appID: String
  var cachePath: String
  var event: String
  var transport: String
  var requestedEventCount: Int
  var emittedEventCount: Int
  var emissions: [AuthOutput]
}

private struct AuthOutput: Codable, Sendable {
  var appID: String
  var cachePath: String
  var event: String
  var transport: String
  var isSignedIn: Bool
  var userID: String?
  var isGuest: Bool?
  var hasRefreshToken: Bool
  var createdAt: InstantTimestamp?
  var updatedAt: InstantTimestamp?
}

private struct AuthEndpointOutput: Codable, Sendable {
  var appID: String
  var cachePath: String
  var event: String
  var transport: String
  var apiURI: String
  var websocketURI: String
  var authorizationURL: String?
  var issuerURI: String
}

private struct MagicCodeOutput: Codable, Sendable {
  var appID: String
  var cachePath: String
  var event: String
  var transport: String
  var email: String
  var expiresAt: InstantTimestamp
  var localVerificationCode: String
}

private struct AppOutput: Codable, Sendable {
  var appID: String
  var cachePath: String
  var event: String
  var transport: String
  var selectionSource: String
  var title: String?
  var isLocalOnly: Bool?
  var createdAt: InstantTimestamp?
}

private struct SyncOutput: Codable, Sendable {
  var appID: String
  var cachePath: String
  var event: String
  var transport: String
  var processedTransactionID: String?
}

private struct ConnectionStatusOutput: Codable, Sendable {
  var appID: String
  var cachePath: String
  var event: String
  var apiURI: String
  var websocketURI: String
  var transport: String
  var state: String
  var isAuthenticated: Bool
  var userID: String?
  var pendingMutationCount: Int
  var processedTransactionID: String?
  var lastErrorMessage: String?
}

private struct RoomPresenceOutput: Codable, Sendable {
  var appID: String
  var cachePath: String
  var event: String
  var transport: String
  var room: InstantRoomHandle
  var userID: String?
  var memberCount: Int
  var members: [InstantRoomPresenceMember]
}

private struct RoomTopicOutput: Codable, Sendable {
  var appID: String
  var cachePath: String
  var event: String
  var transport: String
  var room: InstantRoomHandle
  var topic: String
  var publishedMessageID: String?
  var messageCount: Int
  var messages: [InstantRoomTopicMessage]
}

private struct FilesOutput: Codable, Sendable {
  var appID: String
  var cachePath: String
  var event: String
  var changedID: String?
  var transport: String
  var fileCount: Int
  var files: [InstantStoredFile]
}

private struct StreamsOutput: Codable, Sendable {
  var appID: String
  var cachePath: String
  var event: String
  var changedID: String?
  var transport: String
  var streamID: String
  var chunkCount: Int
  var chunks: [InstantStreamChunk]
}

private struct SharesOutput: Codable, Sendable {
  var appID: String
  var cachePath: String
  var event: String
  var changedID: String?
  var transport: String
  var shareCount: Int
  var shares: [InstantShareSnapshot]
}

private struct SchemaVerifyOutput: Codable, Sendable {
  var example: String
  var path: String
  var entityCount: Int
  var attributeCount: Int
  var linkCount: Int
}

private struct PermissionsVerifyOutput: Codable, Sendable {
  var example: String
  var path: String
  var namespaceCount: Int
  var allowRuleCount: Int
  var rateLimitCount: Int
}

private struct GeneratedArtifactOutput: Codable, Sendable {
  var example: String
  var kind: String
  var fileName: String
  var path: String?
  var byteCount: Int
  var transport: String
  var contents: String?
}

private struct LocalTodoValidationOutput: Codable, Sendable {
  var appID: String
  var cachePath: String
  var event: String
  var transport: String
  var ok: Bool
  var evidenceCount: Int
  var events: [String]
  var finalTodoCount: Int
  var pendingMutationCount: Int
}

private struct ScaffoldOutput: Codable, Sendable {
  var example: String
  var directory: String
  var transport: String
  var files: [ScaffoldFileOutput]
}

private struct ScaffoldFileOutput: Codable, Sendable {
  var kind: String
  var path: String
}

private struct ScaffoldFileSpec: Sendable {
  var contents: String
  var fileName: String
  var kind: String
}

private struct RoomPresenceSetOptions: Sendable {
  var room: InstantRoomHandle
  var userID: String?
  var values: [String: JSONValue]

  static func parse(arguments: [String]) throws -> Self {
    var arguments = arguments
    guard let roomType = arguments.popFirstArgument(),
      let roomID = arguments.popFirstArgument()
    else {
      throw CLIError(InstantSwiftDataCLI.roomPresenceUsage, exitCode: 64)
    }

    var userID: String?
    var values: [String: JSONValue]?
    while let option = arguments.popFirstArgument() {
      switch option {
      case "--user-id":
        guard let value = arguments.popFirstArgument(),
          !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
          throw CLIError(InstantSwiftDataCLI.roomPresenceUsage, exitCode: 64)
        }
        userID = value.trimmingCharacters(in: .whitespacesAndNewlines)

      case "--value":
        guard let value = arguments.popFirstArgument() else {
          throw CLIError(InstantSwiftDataCLI.roomPresenceUsage, exitCode: 64)
        }
        values = try InstantSwiftDataCLI.parseJSONObject(value, operation: "set room presence")

      default:
        throw CLIError(
          "Unknown rooms presence set option: \(option). \(InstantSwiftDataCLI.roomPresenceUsage)",
          exitCode: 64
        )
      }
    }

    guard let values else {
      throw CLIError(InstantSwiftDataCLI.roomPresenceUsage, exitCode: 64)
    }
    return Self(
      room: InstantRoomHandle(
        type: roomType.trimmingCharacters(in: .whitespacesAndNewlines),
        id: roomID.trimmingCharacters(in: .whitespacesAndNewlines)
      ),
      userID: userID,
      values: values
    )
  }
}

private struct RoomPresenceListOptions: Sendable {
  var room: InstantRoomHandle

  static func parse(arguments: [String]) throws -> Self {
    var arguments = arguments
    guard let roomType = arguments.popFirstArgument(),
      let roomID = arguments.popFirstArgument(),
      arguments.isEmpty
    else {
      throw CLIError(InstantSwiftDataCLI.roomPresenceUsage, exitCode: 64)
    }
    return Self(
      room: InstantRoomHandle(
        type: roomType.trimmingCharacters(in: .whitespacesAndNewlines),
        id: roomID.trimmingCharacters(in: .whitespacesAndNewlines)
      )
    )
  }
}

private struct RoomPresenceLeaveOptions: Sendable {
  var room: InstantRoomHandle
  var userID: String?

  static func parse(arguments: [String]) throws -> Self {
    var arguments = arguments
    guard let roomType = arguments.popFirstArgument(),
      let roomID = arguments.popFirstArgument()
    else {
      throw CLIError(InstantSwiftDataCLI.roomPresenceUsage, exitCode: 64)
    }

    var userID: String?
    while let option = arguments.popFirstArgument() {
      switch option {
      case "--user-id":
        guard let value = arguments.popFirstArgument(),
          !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
          throw CLIError(InstantSwiftDataCLI.roomPresenceUsage, exitCode: 64)
        }
        userID = value.trimmingCharacters(in: .whitespacesAndNewlines)

      default:
        throw CLIError(
          "Unknown rooms presence leave option: \(option). \(InstantSwiftDataCLI.roomPresenceUsage)",
          exitCode: 64
        )
      }
    }
    return Self(
      room: InstantRoomHandle(
        type: roomType.trimmingCharacters(in: .whitespacesAndNewlines),
        id: roomID.trimmingCharacters(in: .whitespacesAndNewlines)
      ),
      userID: userID
    )
  }
}

private struct RoomTopicPublishOptions: Sendable {
  var room: InstantRoomHandle
  var topic: String
  var userID: String?
  var payload: JSONValue

  static func parse(arguments: [String]) throws -> Self {
    var arguments = arguments
    guard let roomType = arguments.popFirstArgument(),
      let roomID = arguments.popFirstArgument(),
      let topic = arguments.popFirstArgument()
    else {
      throw CLIError(InstantSwiftDataCLI.roomTopicsUsage, exitCode: 64)
    }

    var userID: String?
    var payload: JSONValue?
    while let option = arguments.popFirstArgument() {
      switch option {
      case "--user-id":
        guard let value = arguments.popFirstArgument(),
          !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
          throw CLIError(InstantSwiftDataCLI.roomTopicsUsage, exitCode: 64)
        }
        userID = value.trimmingCharacters(in: .whitespacesAndNewlines)

      case "--value":
        guard let value = arguments.popFirstArgument() else {
          throw CLIError(InstantSwiftDataCLI.roomTopicsUsage, exitCode: 64)
        }
        payload = try InstantSwiftDataCLI.parseJSONValue(value, operation: "publish room topic")

      default:
        throw CLIError(
          "Unknown rooms topics publish option: \(option). \(InstantSwiftDataCLI.roomTopicsUsage)",
          exitCode: 64
        )
      }
    }

    guard let payload else {
      throw CLIError(InstantSwiftDataCLI.roomTopicsUsage, exitCode: 64)
    }
    return Self(
      room: InstantRoomHandle(
        type: roomType.trimmingCharacters(in: .whitespacesAndNewlines),
        id: roomID.trimmingCharacters(in: .whitespacesAndNewlines)
      ),
      topic: topic.trimmingCharacters(in: .whitespacesAndNewlines),
      userID: userID,
      payload: payload
    )
  }
}

private struct RoomTopicListOptions: Sendable {
  var room: InstantRoomHandle
  var topic: String
  var limit: Int?

  static func parse(arguments: [String]) throws -> Self {
    var arguments = arguments
    guard let roomType = arguments.popFirstArgument(),
      let roomID = arguments.popFirstArgument(),
      let topic = arguments.popFirstArgument()
    else {
      throw CLIError(InstantSwiftDataCLI.roomTopicsUsage, exitCode: 64)
    }

    var limit: Int?
    while let option = arguments.popFirstArgument() {
      switch option {
      case "--limit":
        guard let value = arguments.popFirstArgument(),
          let parsed = Int(value),
          parsed >= 0
        else {
          throw CLIError(InstantSwiftDataCLI.roomTopicsUsage, exitCode: 64)
        }
        limit = parsed

      default:
        throw CLIError(
          "Unknown rooms topics list option: \(option). \(InstantSwiftDataCLI.roomTopicsUsage)",
          exitCode: 64
        )
      }
    }

    return Self(
      room: InstantRoomHandle(
        type: roomType.trimmingCharacters(in: .whitespacesAndNewlines),
        id: roomID.trimmingCharacters(in: .whitespacesAndNewlines)
      ),
      topic: topic.trimmingCharacters(in: .whitespacesAndNewlines),
      limit: limit
    )
  }
}

private struct FileUploadOptions: Sendable {
  var sourceURL: URL
  var name: String?
  var contentType: String?

  static func parse(arguments: [String]) throws -> Self {
    var arguments = arguments
    guard let path = arguments.popFirstArgument(),
      !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    else {
      throw CLIError(InstantSwiftDataCLI.filesUsage, exitCode: 64)
    }

    var name: String?
    var contentType: String?
    while let option = arguments.popFirstArgument() {
      switch option {
      case "--name":
        guard let value = arguments.popFirstArgument(),
          !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
          throw CLIError(InstantSwiftDataCLI.filesUsage, exitCode: 64)
        }
        name = value.trimmingCharacters(in: .whitespacesAndNewlines)

      case "--content-type":
        guard let value = arguments.popFirstArgument(),
          !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
          throw CLIError(InstantSwiftDataCLI.filesUsage, exitCode: 64)
        }
        contentType = value.trimmingCharacters(in: .whitespacesAndNewlines)

      default:
        throw CLIError(
          "Unknown files upload option: \(option). \(InstantSwiftDataCLI.filesUsage)",
          exitCode: 64
        )
      }
    }

    let currentDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    let sourceURL = URL(fileURLWithPath: path, relativeTo: currentDirectory).standardizedFileURL
    return Self(sourceURL: sourceURL, name: name, contentType: contentType)
  }
}

private struct StreamAppendOptions: Sendable {
  var streamID: String
  var payload: JSONValue

  static func parse(arguments: [String]) throws -> Self {
    var arguments = arguments
    guard let streamID = arguments.popFirstArgument(),
      !streamID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    else {
      throw CLIError(InstantSwiftDataCLI.streamsUsage, exitCode: 64)
    }

    var payload: JSONValue?
    while let option = arguments.popFirstArgument() {
      switch option {
      case "--value":
        guard let value = arguments.popFirstArgument() else {
          throw CLIError(InstantSwiftDataCLI.streamsUsage, exitCode: 64)
        }
        payload = try InstantSwiftDataCLI.parseJSONValue(value, operation: "append stream chunk")

      default:
        throw CLIError(
          "Unknown streams append option: \(option). \(InstantSwiftDataCLI.streamsUsage)",
          exitCode: 64
        )
      }
    }

    guard let payload else {
      throw CLIError(InstantSwiftDataCLI.streamsUsage, exitCode: 64)
    }
    return Self(
      streamID: streamID.trimmingCharacters(in: .whitespacesAndNewlines),
      payload: payload
    )
  }
}

private struct StreamReadOptions: Sendable {
  var streamID: String
  var limit: Int?

  static func parse(arguments: [String]) throws -> Self {
    var arguments = arguments
    guard let streamID = arguments.popFirstArgument(),
      !streamID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    else {
      throw CLIError(InstantSwiftDataCLI.streamsUsage, exitCode: 64)
    }

    var limit: Int?
    while let option = arguments.popFirstArgument() {
      switch option {
      case "--limit":
        guard let value = arguments.popFirstArgument(),
          let parsed = Int(value),
          parsed >= 0
        else {
          throw CLIError(InstantSwiftDataCLI.streamsUsage, exitCode: 64)
        }
        limit = parsed

      default:
        throw CLIError(
          "Unknown streams read option: \(option). \(InstantSwiftDataCLI.streamsUsage)",
          exitCode: 64
        )
      }
    }

    return Self(
      streamID: streamID.trimmingCharacters(in: .whitespacesAndNewlines),
      limit: limit
    )
  }
}

private struct ScaffoldOptions: Sendable {
  var example: String
  var outputDirectory: String
  var force: Bool

  static func parse(arguments: [String]) throws -> Self {
    var arguments = arguments
    var example: String?
    var outputDirectory: String?
    var force = false

    while let option = arguments.popFirstArgument() {
      switch option {
      case "--example":
        guard let value = arguments.popFirstArgument() else {
          throw CLIError(usage, exitCode: 64)
        }
        example = value

      case "--to":
        guard let value = arguments.popFirstArgument(),
          !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
          throw CLIError(usage, exitCode: 64)
        }
        outputDirectory = value

      case "--force":
        force = true

      default:
        throw CLIError("Unknown init option: \(option). \(usage)", exitCode: 64)
      }
    }

    guard let example, let outputDirectory else {
      throw CLIError(usage, exitCode: 64)
    }
    return Self(example: example, outputDirectory: outputDirectory, force: force)
  }

  private static var usage: String {
    """
    Usage: instant-swift-data init --example todos --to <directory> [--force] [--json|--jsonl]
    """
  }
}

private struct BenchmarkOptions: Sendable {
  var suite: String
  var iterations: Int
  var appID: String

  static func parse(arguments: [String]) throws -> Self {
    var arguments = arguments
    var suite = InstantSwiftDataLocalBenchmarks.localTodosSuite
    var iterations = 3
    var appID = ProcessInfo.processInfo.environment["INSTANT_APP_ID"]?
      .trimmingCharacters(in: .whitespacesAndNewlines) ?? "local-demo"
    if appID.isEmpty {
      appID = "local-demo"
    }

    while let option = arguments.popFirstArgument() {
      switch option {
      case "--suite":
        guard let value = arguments.popFirstArgument(), !value.isEmpty else {
          throw CLIError(usage, exitCode: 64)
        }
        suite = value

      case "--iterations":
        guard let value = arguments.popFirstArgument(), let parsed = Int(value), parsed > 0 else {
          throw CLIError(usage, exitCode: 64)
        }
        iterations = parsed

      case "--app-id":
        guard let value = arguments.popFirstArgument(),
          !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
          throw CLIError(usage, exitCode: 64)
        }
        appID = value

      default:
        throw CLIError("Unknown benchmark option: \(option). \(usage)", exitCode: 64)
      }
    }

    guard suite == InstantSwiftDataLocalBenchmarks.localTodosSuite else {
      throw CLIError("Unsupported benchmark suite: \(suite). \(usage)", exitCode: 64)
    }

    return Self(suite: suite, iterations: iterations, appID: appID)
  }

  private static var usage: String {
    """
    Usage: instant-swift-data benchmark [--suite local-todos] [--iterations n] [--app-id id] [--json|--jsonl]
    """
  }
}

private struct EphemeralAppOptions: Sendable {
  var title: String

  static func parse(arguments: [String]) throws -> Self {
    var arguments = arguments
    var title: String?

    while let option = arguments.popFirstArgument() {
      switch option {
      case "--title":
        guard let value = arguments.popFirstArgument() else {
          throw CLIError(usage, exitCode: 64)
        }
        title = value

      default:
        throw CLIError("Unknown ephemeral app option: \(option). \(usage)", exitCode: 64)
      }
    }

    guard let title, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw CLIError(usage, exitCode: 64)
    }
    return Self(title: title)
  }

  private static var usage: String {
    """
    Usage: instant-swift-data app ephemeral --title <title> [--json|--jsonl]
    """
  }
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

private struct PermissionsVerifyOptions: Sendable {
  var example: String
  var inputPath: String

  static func parse(arguments: [String]) throws -> Self {
    let usage = "Usage: instant-swift-data perms verify --example todos --from instant.perms.ts"
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
        throw CLIError("Unknown permissions verify option: \(option). \(usage)", exitCode: 64)
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
