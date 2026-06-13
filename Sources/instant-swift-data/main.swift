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
      try runPermissions(arguments: arguments, output: output)

    case "examples":
      try await runExamples(arguments: arguments, output: output)

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

  private static func runPermissions(arguments: [String], output: OutputMode) throws {
    if arguments.first == "verify" {
      let options = try PermissionsVerifyOptions.parse(arguments: arguments)
      try requireTodoExample(options.example)
      try verifyPermissions(options: options, output: output)
      return
    }

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
      throw CLIError("Usage: instant-swift-data examples todos <add|list|watch|complete|update|delete|refresh>", exitCode: 64)
    }
    guard let command = arguments.popFirstArgument() else {
      throw CLIError("Usage: instant-swift-data examples todos <add|list|watch|complete|update|delete|refresh>", exitCode: 64)
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

    case "watch", "observe":
      let options = try todoWatchOptions(arguments: arguments)
      try await watchTodos(context: context, output: output, options: options)

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

    let context = try await CLIContext.bootstrap(initialAttributes: [])
    let snapshot = try await context.runtime.persistence.loadSnapshot()
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
    guard arguments.popFirstArgument() == "get",
      let name = arguments.popFirstArgument(),
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

    case "magic-code", "magic":
      try await runMagicCode(arguments: arguments, context: context, output: output)

    case "sign-out", "signout", "logout":
      guard arguments.isEmpty else {
        throw CLIError("Usage: instant-swift-data auth sign-out [--json|--jsonl]", exitCode: 64)
      }
      try await context.runtime.signOut()
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

  private static func printAuth(
    context: CLIContext,
    event: String,
    session: InstantAuthSession?,
    output: OutputMode
  ) throws {
    let payload = AuthOutput(
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

    switch output {
    case .human:
      if let session {
        print("auth: \(session.isGuest ? "guest" : "token")")
        print("user: \(session.userID)")
        print("refresh token: \(session.refreshToken == nil ? "none" : "present")")
      } else {
        print("auth: signed out")
      }
      print("cache: \(context.cacheURL.path)")

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
    output: OutputMode
  ) throws {
    let payload = AppOutput(
      appID: context.appID,
      cachePath: context.cacheURL.path,
      event: event,
      transport: "not-implemented-local-cache-only",
      selectionSource: context.appIDSource.rawValue
    )

    switch output {
    case .human:
      print("app: \(payload.appID)")
      print("source: \(payload.selectionSource)")
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
    query: InstantQueryPlan = TodoExample.query
  ) async throws {
    let snapshots = try await context.runtime.query(query)
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
        schema generate --example todos [--to instant.schema.ts]
        schema verify --example todos --from instant.schema.ts [--json|--jsonl]
        perms generate --example todos [--to instant.perms.ts]
        perms verify --example todos --from instant.perms.ts [--json|--jsonl]
        examples todos add "do the dishes" [--json|--jsonl]
        examples todos list [--completed true|false] [--search text] [--offset n] [--limit n] [--order asc|desc] [--json|--jsonl]
        examples todos watch [--events 1] [--completed true|false] [--search text] [--offset n] [--limit n] [--order asc|desc] [--json|--jsonl]
        examples todos complete <todo-id> [--json|--jsonl]
        examples todos update <todo-id> "new text" [--json|--jsonl]
        examples todos delete <todo-id> [--json|--jsonl]
        examples todos refresh [--completed true|false] [--search text] [--offset n] [--limit n] [--order asc|desc] [--json|--jsonl]
        cache inspect [--json|--jsonl]
        outbox inspect [--json|--jsonl]
        outbox confirm <mutation-id> [--json|--jsonl]
        outbox fail <mutation-id> "reason" [--json|--jsonl]
        outbox retry <mutation-id> [--json|--jsonl]
        outbox drain --local-confirm [--limit n] [--json|--jsonl]
        local-id get <name> [--json|--jsonl]
        auth show [--json|--jsonl]
        auth guest [--json|--jsonl]
        auth token <refresh-token> [--user-id id] [--json|--jsonl]
        auth magic-code send <email> [--json|--jsonl]
        auth magic-code verify <email> <code> [--json|--jsonl]
        auth sign-out [--json|--jsonl]
        app show [--json|--jsonl]
        app select <app-id> [--json|--jsonl]
        sync inspect [--json|--jsonl]
        sync mark-processed <tx-id> [--json|--jsonl]

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

  private static func todoListQuery(arguments: [String]) throws -> InstantQueryPlan {
    var arguments = arguments
    var completed: Bool?
    var search: String?
    var offset: Int?
    var limit: Int?
    var direction = InstantQuerySortDirection.ascending

    while let option = arguments.popFirstArgument() {
      switch option {
      case "--completed":
        guard let value = arguments.popFirstArgument(), let parsed = parseBool(value) else {
          throw CLIError("Usage: instant-swift-data examples todos list --completed true|false", exitCode: 64)
        }
        completed = parsed

      case "--search":
        guard let value = arguments.popFirstArgument(),
          !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
          throw CLIError("Usage: instant-swift-data examples todos list --search text", exitCode: 64)
        }
        search = value

      case "--limit":
        guard let value = arguments.popFirstArgument(),
          let parsed = Int(value),
          parsed >= 0
        else {
          throw CLIError("Usage: instant-swift-data examples todos list --limit n", exitCode: 64)
        }
        limit = parsed

      case "--offset":
        guard let value = arguments.popFirstArgument(),
          let parsed = Int(value),
          parsed >= 0
        else {
          throw CLIError("Usage: instant-swift-data examples todos list --offset n", exitCode: 64)
        }
        offset = parsed

      case "--order":
        guard let value = arguments.popFirstArgument(), let parsed = parseSortDirection(value) else {
          throw CLIError("Usage: instant-swift-data examples todos list --order asc|desc", exitCode: 64)
        }
        direction = parsed

      default:
        throw CLIError(
          "Unknown todo list option: \(option). Usage: instant-swift-data examples todos list [--completed true|false] [--search text] [--offset n] [--limit n] [--order asc|desc]",
          exitCode: 64
        )
      }
    }

    return makeTodoListQuery(
      completed: completed,
      search: search,
      offset: offset,
      limit: limit,
      direction: direction
    )
  }

  private static func todoWatchOptions(arguments: [String]) throws -> TodoWatchOptions {
    var arguments = arguments
    var completed: Bool?
    var search: String?
    var offset: Int?
    var limit: Int?
    var direction = InstantQuerySortDirection.ascending
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
          "Unknown todo watch option: \(option). Usage: instant-swift-data examples todos watch [--events 1] [--completed true|false] [--search text] [--offset n] [--limit n] [--order asc|desc]",
          exitCode: 64
        )
      }
    }

    return TodoWatchOptions(
      query: makeTodoListQuery(
        completed: completed,
        search: search,
        offset: offset,
        limit: limit,
        direction: direction
      ),
      eventCount: eventCount
    )
  }

  private static func makeTodoListQuery(
    completed: Bool?,
    search: String?,
    offset: Int?,
    limit: Int?,
    direction: InstantQuerySortDirection
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
    if direction != .ascending {
      id += ".order-\(direction.rawValue)"
    }
    if let offset {
      id += ".offset-\(offset)"
    }
    if let limit {
      id += ".limit-\(limit)"
    }

    return InstantQueryPlan(
      id: id,
      namespace: TodoExample.namespace,
      filters: filters,
      order: InstantQueryOrder("createdAt", direction),
      offset: offset,
      limit: limit
    )
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

  private static var outboxUsage: String {
    """
    Usage: instant-swift-data outbox <inspect|confirm|fail|retry|drain>
      instant-swift-data outbox inspect [--json|--jsonl]
      instant-swift-data outbox confirm <mutation-id> [--json|--jsonl]
      instant-swift-data outbox fail <mutation-id> "reason" [--json|--jsonl]
      instant-swift-data outbox retry <mutation-id> [--json|--jsonl]
      instant-swift-data outbox drain --local-confirm [--limit n] [--json|--jsonl]
    """
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
    Usage: instant-swift-data auth <show|guest|token|magic-code|sign-out>
      instant-swift-data auth show [--json|--jsonl]
      instant-swift-data auth guest [--json|--jsonl]
      instant-swift-data auth token <refresh-token> [--user-id id] [--json|--jsonl]
      instant-swift-data auth magic-code send <email> [--json|--jsonl]
      instant-swift-data auth magic-code verify <email> <code> [--json|--jsonl]
      instant-swift-data auth sign-out [--json|--jsonl]
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
    Usage: instant-swift-data app <show|select>
      instant-swift-data app show [--json|--jsonl]
      instant-swift-data app select <app-id> [--json|--jsonl]
    """
  }

  private static var syncUsage: String {
    """
    Usage: instant-swift-data sync <inspect|mark-processed>
      instant-swift-data sync inspect [--json|--jsonl]
      instant-swift-data sync mark-processed <tx-id> [--json|--jsonl]
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
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: resolved.appID,
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
  var pendingMutationCount: Int
  var todos: [TodoRecord]
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

private struct LocalIDOutput: Codable, Sendable {
  var appID: String
  var cachePath: String
  var transport: String
  var name: String
  var id: String
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
}

private struct SyncOutput: Codable, Sendable {
  var appID: String
  var cachePath: String
  var event: String
  var transport: String
  var processedTransactionID: String?
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
