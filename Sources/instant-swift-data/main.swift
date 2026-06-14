import Foundation
import InstantSwiftDataCLIParsing
import InstantSwiftDataCore
import InstantSwiftDataSchema

@main
struct InstantSwiftDataCLI {
  static func main() async {
    do {
      try await run()
    } catch let help as CLIHelp {
      print(help.description)
      exit(0)
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
    let invocation = try CLIArguments.parse(Array(CommandLine.arguments.dropFirst()))
    let arguments = invocation.arguments
    let output = OutputMode(invocation.output)

    guard let command = invocation.command else {
      printHelp()
      return
    }

    switch command {
    case .help:
      printHelp()

    case .initScaffold:
      try runInit(arguments: arguments, output: output)

    case .schema:
      try runSchema(arguments: arguments, output: output)

    case .permissions:
      try runPermissions(arguments: arguments, output: output)

    case .examples:
      try await runExamples(arguments: arguments, output: output)

    case .query:
      try await runQuery(arguments: arguments, output: output)

    case .admin:
      try await runAdmin(arguments: arguments, output: output)

    case .cache:
      try await runCache(arguments: arguments, output: output)

    case .outbox:
      try await runOutbox(arguments: arguments, output: output)

    case .localID:
      try await runLocalID(arguments: arguments, output: output)

    case .auth:
      try await runAuth(arguments: arguments, output: output)

    case .app:
      try await runApp(arguments: arguments, output: output)

    case .sync:
      try await runSync(arguments: arguments, output: output)

    case .connection:
      try await runConnection(arguments: arguments, output: output)

    case .rooms:
      try await runRooms(arguments: arguments, output: output)

    case .files:
      try await runFiles(arguments: arguments, output: output)

    case .streams:
      try await runStreams(arguments: arguments, output: output)

    case .shares:
      try await runShares(arguments: arguments, output: output)

    case .validation:
      try await runValidation(arguments: arguments, output: output)

    case .benchmark:
      try await runBenchmark(arguments: arguments, output: output)

    case let .unknown(command):
      throw CLIError("Unknown command: \(command)", exitCode: 64)
    }
  }

  private static func runInit(arguments: [String], output: OutputMode) throws {
    let invocation: CLIScaffoldInvocation
    do {
      var input = arguments[...]
      invocation = try CLIInitParser().parse(&input)
    } catch let error as CLIInitArgumentError {
      throw CLIError(error.description, exitCode: error.exitCode)
    }
    let options = ScaffoldOptions(invocation: invocation)
    try requireTodoExample(options.example)
    try scaffoldTodoExample(options: options, output: output)
  }

  private static func runSchema(arguments: [String], output: OutputMode) throws {
    let invocation: CLISchemaInvocation
    do {
      var input = arguments[...]
      invocation = try CLISchemaParser().parse(&input)
    } catch let error as CLISchemaArgumentError {
      throw CLIError(error.description, exitCode: error.exitCode)
    }

    switch invocation {
    case let .verify(verify):
      let options = SchemaVerifyOptions(invocation: verify)
      try requireTodoExample(options.example)
      try verifySchema(options: options, output: output)

    case let .generate(generate):
      let options = GenerateOptions(invocation: generate)
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
  }

  private static func runPermissions(arguments: [String], output: OutputMode) throws {
    let invocation: CLIPermissionsInvocation
    do {
      var input = arguments[...]
      invocation = try CLIPermissionsParser().parse(&input)
    } catch let error as CLIPermissionsArgumentError {
      throw CLIError(error.description, exitCode: error.exitCode)
    }

    switch invocation {
    case let .verify(verify):
      let options = PermissionsVerifyOptions(invocation: verify)
      try requireTodoExample(options.example)
      try verifyPermissions(options: options, output: output)

    case let .generate(generate):
      let options = GenerateOptions(invocation: generate)
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
  }

  private static func runValidation(arguments: [String], output: OutputMode) async throws {
    let invocation: CLIValidationInvocation
    do {
      var input = arguments[...]
      invocation = try CLIValidationParser().parse(&input)
    } catch let error as CLIValidationArgumentError {
      throw CLIError(error.description, exitCode: error.exitCode)
    }

    switch invocation {
    case .localTodos:
      let appID = validationAppID()
      do {
        let result = try await InstantSwiftDataLocalTodoValidation.run(appID: appID)
        try printLocalTodoValidation(result: result, output: output)
      } catch {
        if output == .jsonl {
          try writeJSONLine(
            validationFailureRow(
              caseID: "validation.local.todos",
              appID: appID,
              error: error
            )
          )
        }
        throw error
      }

    case .localIntegrations:
      let appID = validationAppID()
      do {
        let result = try await InstantSwiftDataLocalIntegrationValidation.run(appID: appID)
        try printLocalIntegrationValidation(result: result, output: output)
      } catch {
        if output == .jsonl {
          try writeJSONLine(
            validationFailureRow(
              caseID: "validation.local.integrations",
              appID: appID,
              error: error
            )
          )
        }
        throw error
      }
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
    let invocation: CLIQueryInvocation
    do {
      var input = arguments[...]
      invocation = try CLIQueryParser().parse(&input)
    } catch let error as CLIQueryArgumentError {
      throw CLIError(error.description, exitCode: error.exitCode)
    }

    switch invocation {
    case let .todos(todos):
      let options = todoQueryOptions(invocation: todos)
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
    }
  }

  private static func runAdmin(arguments: [String], output: OutputMode) async throws {
    let invocation: CLIAdminInvocation
    do {
      var input = arguments[...]
      invocation = try CLIAdminParser().parse(&input)
    } catch let error as CLIAdminArgumentError {
      if let mergeJSON = firstAdminMergeJSONAfterValidTransactHead(arguments: arguments) {
        _ = try parseAdminMergeObject(mergeJSON, usage: CLIAdminUsage.transact)
      }
      throw CLIError(error.description, exitCode: error.exitCode)
    }

    switch invocation {
    case let .query(query):
      let options = adminQueryOptions(namespace: query.namespace, limit: query.limit)
      let context = try await CLIContext.bootstrap(initialAttributes: [])
      try await printSnapshots(
        context: context,
        output: output,
        event: "admin-query",
        query: options.query,
        caseID: "cli.admin.query"
      )

    case let .transact(transact):
      let options = try AdminTransactOptions.parse(invocation: transact)
      let context = try await CLIContext.bootstrap(initialAttributes: options.attributes)
      let transactionID = options.transactionID ?? context.runtime.configuration.makeID()
      let existingPendingMutation = await context.runtime.outboxMutations()
        .first { $0.id == transactionID && $0.status == .pending }
      let now = existingPendingMutation?.createdAt ?? context.runtime.configuration.now()
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
    }
  }

  private static func runExamples(arguments: [String], output: OutputMode) async throws {
    guard !arguments.isEmpty else {
      throw CLIError(examplesUsage, exitCode: 64)
    }
    var input = arguments[...]
    let invocation = try CLIExamplesParser().parse(&input)
    let todos: CLIExamplesTodosInvocation
    switch invocation {
    case let .syncUps(arguments):
      try await runSyncUps(arguments: arguments, output: output)
      return

    case let .reminders(arguments):
      try await runReminders(arguments: arguments, output: output)
      return

    case let .todoLinks(arguments):
      try await runTodoLinks(arguments: arguments, output: output)
      return

    case let .todos(parsedTodos):
      todos = parsedTodos

    case .unknown:
      throw CLIError(examplesUsage, exitCode: 64)
    }
    guard let command = todos.command else {
      throw CLIError("Usage: instant-swift-data examples todos <add|seed|list|watch|complete|update|delete|reset|refresh>", exitCode: 64)
    }
    let arguments = todos.arguments

    let context = try await CLIContext.bootstrap()

    switch command {
    case .seed:
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
      try await printTodos(
        context: context,
        output: output,
        event: "seed",
        allowOfflineLocalEmission: true
      )

    case .add:
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
      try await printTodos(
        context: context,
        output: output,
        event: "add",
        changedID: todoID,
        allowOfflineLocalEmission: true
      )

    case .list:
      let query = try todoListQuery(arguments: arguments)
      try await printTodos(context: context, output: output, event: "list", query: query)

    case .watch:
      let options = try todoWatchOptions(arguments: arguments)
      try await watchTodos(context: context, output: output, options: options)

    case .complete:
      var arguments = arguments
      guard let todoID = arguments.popFirstArgument(), arguments.isEmpty else {
        throw CLIError("Usage: instant-swift-data examples todos complete <todo-id>", exitCode: 64)
      }
      let currentTodos = try await TodoExample.decode(
        todoEmission(
          context: context,
          query: TodoExample.query,
          allowOfflineLocalEmission: true
        ).values
      )
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
      try await printTodos(
        context: context,
        output: output,
        event: "complete",
        changedID: todoID,
        allowOfflineLocalEmission: true
      )

    case .update:
      var arguments = arguments
      guard let todoID = arguments.popFirstArgument() else {
        throw CLIError("Usage: instant-swift-data examples todos update <todo-id> \"new text\"", exitCode: 64)
      }
      let text = arguments.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
      guard !text.isEmpty else {
        throw CLIError("Usage: instant-swift-data examples todos update <todo-id> \"new text\"", exitCode: 64)
      }
      let currentTodos = try await TodoExample.decode(
        todoEmission(
          context: context,
          query: TodoExample.query,
          allowOfflineLocalEmission: true
        ).values
      )
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
      try await printTodos(
        context: context,
        output: output,
        event: "update",
        changedID: todoID,
        allowOfflineLocalEmission: true
      )

    case .delete:
      var arguments = arguments
      guard let todoID = arguments.popFirstArgument(), arguments.isEmpty else {
        throw CLIError("Usage: instant-swift-data examples todos delete <todo-id>", exitCode: 64)
      }
      let currentTodos = try await TodoExample.decode(
        todoEmission(
          context: context,
          query: TodoExample.query,
          allowOfflineLocalEmission: true
        ).values
      )
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
      try await printTodos(
        context: context,
        output: output,
        event: "delete",
        changedID: todoID,
        allowOfflineLocalEmission: true
      )

    case .reset:
      guard arguments.isEmpty else {
        throw CLIError("Usage: instant-swift-data examples todos reset [--json|--jsonl]", exitCode: 64)
      }
      let currentTodos = try await TodoExample.decode(
        todoEmission(
          context: context,
          query: TodoExample.query,
          allowOfflineLocalEmission: true
        ).values
      )
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
      try await printTodos(
        context: context,
        output: output,
        event: "reset",
        allowOfflineLocalEmission: true
      )

    case .refresh:
      let query = try todoListQuery(arguments: arguments)
      try await printTodos(context: context, output: output, event: "refresh", query: query)

    case let .unknown(command):
      throw CLIError("Unknown todos command: \(command)", exitCode: 64)
    }
  }

  private static func runSyncUps(arguments: [String], output: OutputMode) async throws {
    var arguments = arguments
    guard let command = arguments.popFirstArgument() else {
      throw CLIError(syncUpsUsage, exitCode: 64)
    }
    let context = try await CLIContext.bootstrap(initialAttributes: SyncUpsExample.attributes)

    switch command {
    case "seed":
      guard arguments.isEmpty else {
        throw CLIError("Usage: instant-swift-data examples sync-ups seed [--json|--jsonl]", exitCode: 64)
      }
      let transactionID = context.runtime.configuration.makeID()
      let now = context.runtime.configuration.now()
      var syncUpIDs: [String: String] = [:]
      var syncUps: [(id: String, seed: SyncUpSeedRecord)] = []
      for seed in SyncUpsExample.seedSyncUps {
        let id = try await context.runtime.localID(named: seed.localIDName)
        syncUpIDs[seed.localIDName] = id
        syncUps.append((id: id, seed: seed))
      }
      var attendees: [(id: String, syncUpID: String, seed: SyncUpAttendeeSeedRecord)] = []
      for seed in SyncUpsExample.seedAttendees {
        let id = try await context.runtime.localID(named: seed.localIDName)
        let syncUpID: String
        if let seededSyncUpID = syncUpIDs[seed.syncUpLocalIDName] {
          syncUpID = seededSyncUpID
        } else {
          syncUpID = try await context.runtime.localID(named: seed.syncUpLocalIDName)
        }
        attendees.append((id: id, syncUpID: syncUpID, seed: seed))
      }
      var meetings: [(id: String, syncUpID: String, seed: SyncUpMeetingSeedRecord)] = []
      for seed in SyncUpsExample.seedMeetings {
        let id = try await context.runtime.localID(named: seed.localIDName)
        let syncUpID: String
        if let seededSyncUpID = syncUpIDs[seed.syncUpLocalIDName] {
          syncUpID = seededSyncUpID
        } else {
          syncUpID = try await context.runtime.localID(named: seed.syncUpLocalIDName)
        }
        meetings.append((id: id, syncUpID: syncUpID, seed: seed))
      }
      try await context.runtime.transact(
        InstantStoreTransaction(
          id: transactionID,
          operations: SyncUpsExample.seedOperations(
            syncUps: syncUps,
            attendees: attendees,
            meetings: meetings,
            baseCreatedAt: now,
            transactionID: transactionID
          )
        ),
        createdAt: now,
        source: "cli.examples.sync-ups.seed"
      )
      try await printSyncUps(context: context, output: output, event: "seed")

    case "list", "refresh", "detail":
      var event = command == "refresh" ? "refresh" : "list"
      var syncUpID: String?
      if command == "detail" {
        guard let value = arguments.popFirstArgument(), arguments.isEmpty else {
          throw CLIError(
            "Usage: instant-swift-data examples sync-ups detail <sync-up-id> [--json|--jsonl]",
            exitCode: 64
          )
        }
        syncUpID = value
        event = "detail"
      } else {
        while let option = arguments.popFirstArgument() {
          switch option {
          case "--refresh":
            event = "refresh"
          case "--sync-up-id":
            guard let value = arguments.popFirstArgument(), !value.isEmpty else {
              throw CLIError(
                "Usage: instant-swift-data examples sync-ups list [--refresh] [--sync-up-id id] [--json|--jsonl]",
                exitCode: 64
              )
            }
            syncUpID = value
          default:
            throw CLIError(
              "Usage: instant-swift-data examples sync-ups list [--refresh] [--sync-up-id id] [--json|--jsonl]",
              exitCode: 64
            )
          }
        }
      }
      try await printSyncUps(context: context, output: output, event: event, syncUpID: syncUpID)

    case "add":
      guard let rawTitle = arguments.popFirstArgument() else {
        throw CLIError(
          "Usage: instant-swift-data examples sync-ups add \"title\" [--seconds n] [--theme theme] [--attendee name ...]",
          exitCode: 64
        )
      }
      let title = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !title.isEmpty else {
        throw CLIError(
          "Usage: instant-swift-data examples sync-ups add \"title\" [--seconds n] [--theme theme] [--attendee name ...]",
          exitCode: 64
        )
      }
      var seconds = 60 * 5
      var theme = SyncUpTheme.bubblegum
      var attendeeNames: [String] = []
      while let option = arguments.popFirstArgument() {
        switch option {
        case "--seconds":
          guard let value = arguments.popFirstArgument(),
            let parsed = Int(value),
            parsed > 0
          else {
            throw CLIError("Sync-up seconds must be a positive integer.", exitCode: 64)
          }
          seconds = parsed
        case "--theme":
          guard let value = arguments.popFirstArgument(), let parsed = SyncUpTheme(rawValue: value)
          else {
            throw CLIError("Unknown SyncUps theme. Use one of: \(syncUpThemeList).", exitCode: 64)
          }
          theme = parsed
        case "--attendee":
          guard let value = arguments.popFirstArgument() else {
            throw CLIError("Usage: instant-swift-data examples sync-ups add \"title\" --attendee name", exitCode: 64)
          }
          let name = value.trimmingCharacters(in: .whitespacesAndNewlines)
          if !name.isEmpty {
            attendeeNames.append(name)
          }
        default:
          throw CLIError("Unknown sync-ups add option: \(option). \(syncUpsUsage)", exitCode: 64)
        }
      }
      guard !attendeeNames.isEmpty else {
        throw CLIError("Sync-ups require at least one --attendee name.", exitCode: 64)
      }
      let transactionID = context.runtime.configuration.makeID()
      let syncUpID = context.runtime.configuration.makeID()
      let now = context.runtime.configuration.now()
      var operations = SyncUpsExample.createSyncUpOperations(
        id: syncUpID,
        title: title,
        seconds: seconds,
        theme: theme,
        updatedAt: now,
        transactionID: transactionID
      )
      for name in attendeeNames {
        operations += SyncUpsExample.createAttendeeOperations(
          id: context.runtime.configuration.makeID(),
          syncUpID: syncUpID,
          name: name,
          updatedAt: now,
          transactionID: transactionID
        )
      }
      try await context.runtime.transact(
        InstantStoreTransaction(id: transactionID, operations: operations),
        createdAt: now,
        source: "cli.examples.sync-ups.add"
      )
      try await printSyncUps(
        context: context,
        output: output,
        event: "add",
        changedID: syncUpID,
        syncUpID: syncUpID
      )

    case "update", "edit":
      guard let syncUpID = arguments.popFirstArgument() else {
        throw CLIError(
          "Usage: instant-swift-data examples sync-ups edit <sync-up-id> [--title title] [--seconds n] [--theme theme] [--attendee name ...]",
          exitCode: 64
        )
      }
      let currentSyncUps = try SyncUpsExample.decodeSyncUps(
        (try await context.runtime.queryOnce(SyncUpsExample.syncUpsQuery)).values
      )
      guard let current = currentSyncUps.first(where: { $0.id == syncUpID }) else {
        throw CLIError("Sync-up not found: \(syncUpID)", exitCode: 66)
      }
      var title = current.title
      var seconds = current.seconds
      var theme = current.theme
      var didChange = false
      var replacementAttendeeNames: [String]?
      while let option = arguments.popFirstArgument() {
        switch option {
        case "--title":
          guard let rawValue = arguments.popFirstArgument() else {
            throw CLIError("Sync-up title must not be empty.", exitCode: 64)
          }
          let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
          guard !value.isEmpty else {
            throw CLIError("Sync-up title must not be empty.", exitCode: 64)
          }
          title = value
          didChange = true
        case "--seconds":
          guard let value = arguments.popFirstArgument(),
            let parsed = Int(value),
            parsed > 0
          else {
            throw CLIError("Sync-up seconds must be a positive integer.", exitCode: 64)
          }
          seconds = parsed
          didChange = true
        case "--theme":
          guard let value = arguments.popFirstArgument(), let parsed = SyncUpTheme(rawValue: value)
          else {
            throw CLIError("Unknown SyncUps theme. Use one of: \(syncUpThemeList).", exitCode: 64)
          }
          theme = parsed
          didChange = true
        case "--attendee":
          guard let value = arguments.popFirstArgument() else {
            throw CLIError(
              "Usage: instant-swift-data examples sync-ups edit <sync-up-id> --attendee name",
              exitCode: 64
            )
          }
          let name = value.trimmingCharacters(in: .whitespacesAndNewlines)
          if replacementAttendeeNames == nil {
            replacementAttendeeNames = []
          }
          if !name.isEmpty {
            replacementAttendeeNames?.append(name)
          }
          didChange = true
        default:
          throw CLIError("Unknown sync-ups update option: \(option). \(syncUpsUsage)", exitCode: 64)
        }
      }
      guard didChange else {
        throw CLIError(
          "Usage: instant-swift-data examples sync-ups edit <sync-up-id> [--title title] [--seconds n] [--theme theme] [--attendee name ...]",
          exitCode: 64
        )
      }
      if let replacementAttendeeNames, replacementAttendeeNames.isEmpty {
        throw CLIError("Sync-up attendee replacement requires at least one non-empty --attendee.", exitCode: 64)
      }
      let transactionID = context.runtime.configuration.makeID()
      let now = context.runtime.configuration.now()
      var operations = SyncUpsExample.updateSyncUpOperations(
        id: syncUpID,
        title: title,
        seconds: seconds,
        theme: theme,
        updatedAt: now,
        transactionID: transactionID
      )
      if let replacementAttendeeNames {
        let existingAttendees = try SyncUpsExample.decodeAttendees(
          (try await context.runtime.queryOnce(SyncUpsExample.attendeesForSyncUpQuery(syncUpID))).values
        )
        operations += SyncUpsExample.replaceAttendeesOperations(
          syncUpID: syncUpID,
          existingAttendeeIDs: existingAttendees.map(\.id),
          newAttendees: replacementAttendeeNames.map { name in
            SyncUpAttendeeDraft(id: context.runtime.configuration.makeID(), name: name)
          },
          updatedAt: now,
          transactionID: transactionID
        )
      }
      try await context.runtime.transact(
        InstantStoreTransaction(
          id: transactionID,
          operations: operations
        ),
        createdAt: now,
        source: "cli.examples.sync-ups.edit"
      )
      try await printSyncUps(
        context: context,
        output: output,
        event: command == "edit" ? "edit" : "update",
        changedID: syncUpID,
        syncUpID: syncUpID
      )

    case "add-attendee":
      guard let syncUpID = arguments.popFirstArgument() else {
        throw CLIError(
          "Usage: instant-swift-data examples sync-ups add-attendee <sync-up-id> \"name\"",
          exitCode: 64
        )
      }
      let name = arguments.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
      guard !name.isEmpty else {
        throw CLIError(
          "Usage: instant-swift-data examples sync-ups add-attendee <sync-up-id> \"name\"",
          exitCode: 64
        )
      }
      let attendeeID = context.runtime.configuration.makeID()
      let transactionID = context.runtime.configuration.makeID()
      let now = context.runtime.configuration.now()
      try await context.runtime.transact(
        InstantStoreTransaction(
          id: transactionID,
          operations: SyncUpsExample.createAttendeeOperations(
            id: attendeeID,
            syncUpID: syncUpID,
            name: name,
            updatedAt: now,
            transactionID: transactionID
          )
        ),
        createdAt: now,
        source: "cli.examples.sync-ups.add-attendee"
      )
      try await printSyncUps(
        context: context,
        output: output,
        event: "add-attendee",
        changedID: attendeeID,
        syncUpID: syncUpID
      )

    case "record", "record-meeting":
      guard let syncUpID = arguments.popFirstArgument() else {
        throw CLIError(
          "Usage: instant-swift-data examples sync-ups record <sync-up-id> [--transcript] \"transcript\"",
          exitCode: 64
        )
      }
      var transcriptParts: [String] = []
      while let value = arguments.popFirstArgument() {
        if value == "--transcript" {
          guard let transcript = arguments.popFirstArgument() else {
            throw CLIError(
              "Usage: instant-swift-data examples sync-ups record <sync-up-id> --transcript \"text\"",
              exitCode: 64
            )
          }
          transcriptParts.append(transcript)
        } else {
          transcriptParts.append(value)
        }
      }
      let transcript = transcriptParts.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
      guard !transcript.isEmpty else {
        throw CLIError(
          "Usage: instant-swift-data examples sync-ups record <sync-up-id> [--transcript] \"transcript\"",
          exitCode: 64
        )
      }
      let currentAttendees = try SyncUpsExample.decodeAttendees(
        (try await context.runtime.queryOnce(SyncUpsExample.attendeesForSyncUpQuery(syncUpID))).values
      )
      guard !currentAttendees.isEmpty else {
        throw CLIError(
          "Cannot record a sync-up meeting without at least one attendee.",
          exitCode: 66
        )
      }
      let meetingID = context.runtime.configuration.makeID()
      let transactionID = context.runtime.configuration.makeID()
      let now = context.runtime.configuration.now()
      try await context.runtime.transact(
        InstantStoreTransaction(
          id: transactionID,
          operations: SyncUpsExample.recordMeetingOperations(
            id: meetingID,
            syncUpID: syncUpID,
            transcript: transcript,
            date: now,
            transactionID: transactionID
          )
        ),
        createdAt: now,
        source: "cli.examples.sync-ups.record"
      )
      try await printSyncUps(
        context: context,
        output: output,
        event: "record",
        changedID: meetingID,
        syncUpID: syncUpID
      )

    case "delete":
      guard let syncUpID = arguments.popFirstArgument(), arguments.isEmpty else {
        throw CLIError("Usage: instant-swift-data examples sync-ups delete <sync-up-id>", exitCode: 64)
      }
      let transactionID = context.runtime.configuration.makeID()
      let now = context.runtime.configuration.now()
      try await context.runtime.transact(
        InstantStoreTransaction(
          id: transactionID,
          operations: SyncUpsExample.deleteSyncUpOperations(id: syncUpID)
        ),
        createdAt: now,
        source: "cli.examples.sync-ups.delete"
      )
      try await printSyncUps(context: context, output: output, event: "delete", changedID: syncUpID)

    case "delete-attendee":
      guard let attendeeID = arguments.popFirstArgument(), arguments.isEmpty else {
        throw CLIError(
          "Usage: instant-swift-data examples sync-ups delete-attendee <attendee-id>",
          exitCode: 64
        )
      }
      let allAttendees = try SyncUpsExample.decodeAttendees(
        (try await context.runtime.queryOnce(SyncUpsExample.attendeesQuery)).values
      )
      guard let attendee = allAttendees.first(where: { $0.id == attendeeID }) else {
        throw CLIError("Attendee not found: \(attendeeID)", exitCode: 66)
      }
      let remainingAttendeeIDs = allAttendees
        .filter { $0.syncUpID == attendee.syncUpID && $0.id != attendeeID }
        .map(\.id)
      let transactionID = context.runtime.configuration.makeID()
      let now = context.runtime.configuration.now()
      let replacementAttendeeID = remainingAttendeeIDs.isEmpty
        ? context.runtime.configuration.makeID()
        : nil
      try await context.runtime.transact(
        InstantStoreTransaction(
          id: transactionID,
          operations: SyncUpsExample.deleteAttendeeOperations(
            id: attendeeID,
            syncUpID: attendee.syncUpID,
            remainingAttendeeIDs: remainingAttendeeIDs,
            replacementAttendeeID: replacementAttendeeID,
            updatedAt: now,
            transactionID: transactionID
          )
        ),
        createdAt: now,
        source: "cli.examples.sync-ups.delete-attendee"
      )
      try await printSyncUps(context: context, output: output, event: "delete-attendee", changedID: attendeeID)

    case "delete-meeting":
      guard let meetingID = arguments.popFirstArgument(), arguments.isEmpty else {
        throw CLIError(
          "Usage: instant-swift-data examples sync-ups delete-meeting <meeting-id>",
          exitCode: 64
        )
      }
      let transactionID = context.runtime.configuration.makeID()
      let now = context.runtime.configuration.now()
      try await context.runtime.transact(
        InstantStoreTransaction(
          id: transactionID,
          operations: SyncUpsExample.deleteMeetingOperations(id: meetingID)
        ),
        createdAt: now,
        source: "cli.examples.sync-ups.delete-meeting"
      )
      try await printSyncUps(context: context, output: output, event: "delete-meeting", changedID: meetingID)

    default:
      throw CLIError("Unknown sync-ups command: \(command). \(syncUpsUsage)", exitCode: 64)
    }
  }

  private static func runReminders(arguments: [String], output: OutputMode) async throws {
    var arguments = arguments
    guard let command = arguments.popFirstArgument() else {
      throw CLIError(remindersUsage, exitCode: 64)
    }
    let context = try await CLIContext.bootstrap(initialAttributes: ReminderExample.attributes)

    switch command {
    case "seed":
      guard arguments.isEmpty else {
        throw CLIError("Usage: instant-swift-data examples reminders seed [--json|--jsonl]", exitCode: 64)
      }
      let transactionID = context.runtime.configuration.makeID()
      let now = context.runtime.configuration.now()
      var listIDs: [String: String] = [:]
      var lists: [(id: String, seed: RemindersListSeedRecord)] = []
      for seed in ReminderExample.seedLists {
        let id = try await context.runtime.localID(named: seed.localIDName)
        listIDs[seed.localIDName] = id
        lists.append((id: id, seed: seed))
      }
      var reminders: [(id: String, listID: String, seed: ReminderSeedRecord)] = []
      for seed in ReminderExample.seedReminders {
        let id = try await context.runtime.localID(named: seed.localIDName)
        let listID: String
        if let seededListID = listIDs[seed.listLocalIDName] {
          listID = seededListID
        } else {
          listID = try await context.runtime.localID(named: seed.listLocalIDName)
        }
        reminders.append((id: id, listID: listID, seed: seed))
      }
      let tagSeeds = Dictionary(
        uniqueKeysWithValues: ReminderExample.seedTags.compactMap { seed in
          ReminderExample.normalizedTagTitle(seed.title).map { ($0, seed) }
        }
      )
      var tagsByID = tagSeeds
      var reminderTags: [(reminderID: String, tagID: String)] = []
      for reminder in reminders {
        for rawTitle in reminder.seed.tagTitles {
          guard let tagID = ReminderExample.normalizedTagTitle(rawTitle) else { continue }
          tagsByID[tagID] = tagsByID[tagID] ?? ReminderTagSeedRecord(title: tagID)
          reminderTags.append((reminderID: reminder.id, tagID: tagID))
        }
      }
      let tags = tagsByID
        .map { (id: $0.key, seed: $0.value) }
        .sorted { $0.id < $1.id }
      try await context.runtime.transact(
        InstantStoreTransaction(
          id: transactionID,
          operations: ReminderExample.seedOperations(
            lists: lists,
            reminders: reminders,
            tags: tags,
            reminderTags: reminderTags,
            baseCreatedAt: now,
            transactionID: transactionID
          )
        ),
        createdAt: now,
        source: "cli.examples.reminders.seed"
      )
      try await printReminders(context: context, output: output, event: "seed")

    case "list", "lists", "refresh":
      let options = try parseRemindersListOptions(
        arguments: arguments,
        event: command == "refresh" ? "refresh" : "list"
      )
      let query = ReminderExample.remindersFilterQuery(
        listID: options.listID,
        includeCompleted: options.includeCompleted,
        flagged: options.flagged,
        scheduled: options.scheduled,
        today: options.today ? context.runtime.configuration.now() : nil,
        priority: options.priority
      )
      try await printReminders(
        context: context,
        output: output,
        event: options.event,
        listID: options.listID,
        remindersQuery: query
      )

    case "stats":
      guard arguments.isEmpty else {
        throw CLIError("Usage: instant-swift-data examples reminders stats [--json|--jsonl]", exitCode: 64)
      }
      try await printReminders(context: context, output: output, event: "stats")

    case "tags", "list-tags":
      guard arguments.isEmpty else {
        throw CLIError("Usage: instant-swift-data examples reminders tags [--json|--jsonl]", exitCode: 64)
      }
      try await printReminders(context: context, output: output, event: "tags")

    case "add-list":
      let title = arguments.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
      guard !title.isEmpty else {
        throw CLIError(
          "Usage: instant-swift-data examples reminders add-list \"list title\"",
          exitCode: 64
        )
      }
      let existingLists = try ReminderExample.decodeLists(
        (try await context.runtime.queryOnce(ReminderExample.listsQuery)).values
      )
      let transactionID = context.runtime.configuration.makeID()
      let listID = context.runtime.configuration.makeID()
      let now = context.runtime.configuration.now()
      try await context.runtime.transact(
        InstantStoreTransaction(
          id: transactionID,
          operations: ReminderExample.createListOperations(
            id: listID,
            title: title,
            position: existingLists.count,
            createdAt: now,
            transactionID: transactionID
          )
        ),
        createdAt: now,
        source: "cli.examples.reminders.add-list"
      )
      try await printReminders(context: context, output: output, event: "add-list", changedID: listID)

    case "rename-list", "update-list":
      guard let listID = arguments.popFirstArgument() else {
        throw CLIError(
          "Usage: instant-swift-data examples reminders rename-list <list-id> \"new title\"",
          exitCode: 64
        )
      }
      let title = arguments.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
      guard !title.isEmpty else {
        throw CLIError(
          "Usage: instant-swift-data examples reminders rename-list <list-id> \"new title\"",
          exitCode: 64
        )
      }
      let transactionID = context.runtime.configuration.makeID()
      let now = context.runtime.configuration.now()
      try await context.runtime.transact(
        InstantStoreTransaction(
          id: transactionID,
          operations: ReminderExample.renameListOperations(
            id: listID,
            title: title,
            updatedAt: now,
            transactionID: transactionID
          )
        ),
        createdAt: now,
        source: "cli.examples.reminders.rename-list"
      )
      try await printReminders(
        context: context,
        output: output,
        event: "rename-list",
        changedID: listID,
        listID: listID
      )

    case "add":
      guard let listID = arguments.popFirstArgument() else {
        throw CLIError(
          remindersAddUsage,
          exitCode: 64
        )
      }
      let options = try parseReminderAddOptions(arguments: arguments)
      let existingReminders = try ReminderExample.decodeReminders(
        (try await context.runtime.queryOnce(ReminderExample.remindersForListQuery(listID))).values
      )
      let transactionID = context.runtime.configuration.makeID()
      let reminderID = context.runtime.configuration.makeID()
      let now = context.runtime.configuration.now()
      try await context.runtime.transact(
        InstantStoreTransaction(
          id: transactionID,
          operations: ReminderExample.createReminderOperations(
            id: reminderID,
            listID: listID,
            title: options.title,
            notes: options.notes,
            isFlagged: options.isFlagged,
            dueDate: options.dueDate,
            priority: options.priority,
            position: existingReminders.count,
            createdAt: now,
            transactionID: transactionID
          )
        ),
        createdAt: now,
        source: "cli.examples.reminders.add"
      )
      try await printReminders(
        context: context,
        output: output,
        event: "add",
        changedID: reminderID,
        listID: listID
      )

    case "update", "edit":
      guard let reminderID = arguments.popFirstArgument() else {
        throw CLIError(
          remindersUpdateUsage,
          exitCode: 64
        )
      }
      let currentReminders = try ReminderExample.decodeReminders(
        (try await context.runtime.queryOnce(ReminderExample.remindersQuery)).values
      )
      guard let reminder = currentReminders.first(where: { $0.id == reminderID }) else {
        throw CLIError("Reminder not found: \(reminderID)", exitCode: 66)
      }
      let options = try parseReminderUpdateOptions(arguments: arguments, current: reminder)
      let transactionID = context.runtime.configuration.makeID()
      let now = context.runtime.configuration.now()
      try await context.runtime.transact(
        InstantStoreTransaction(
          id: transactionID,
          operations: ReminderExample.updateReminderDetailsOperations(
            id: reminderID,
            listID: reminder.remindersListID,
            title: options.title,
            notes: options.notes,
            isFlagged: options.isFlagged,
            dueDate: options.dueDate,
            priority: options.priority,
            updatedAt: now,
            transactionID: transactionID
          )
        ),
        createdAt: now,
        source: "cli.examples.reminders.update"
      )
      try await printReminders(
        context: context,
        output: output,
        event: "update",
        changedID: reminderID,
        listID: reminder.remindersListID
      )

    case "complete":
      guard let reminderID = arguments.popFirstArgument(), arguments.isEmpty else {
        throw CLIError(
          "Usage: instant-swift-data examples reminders complete <reminder-id>",
          exitCode: 64
        )
      }
      let currentReminders = try ReminderExample.decodeReminders(
        (try await context.runtime.queryOnce(ReminderExample.remindersQuery)).values
      )
      guard let reminder = currentReminders.first(where: { $0.id == reminderID }) else {
        throw CLIError("Reminder not found: \(reminderID)", exitCode: 66)
      }
      let transactionID = context.runtime.configuration.makeID()
      let now = context.runtime.configuration.now()
      try await context.runtime.transact(
        InstantStoreTransaction(
          id: transactionID,
          operations: ReminderExample.completeReminderOperations(
            id: reminderID,
            listID: reminder.remindersListID,
            updatedAt: now,
            transactionID: transactionID
          )
        ),
        createdAt: now,
        source: "cli.examples.reminders.complete"
      )
      try await printReminders(
        context: context,
        output: output,
        event: "complete",
        changedID: reminderID,
        listID: reminder.remindersListID
      )

    case "delete":
      guard let reminderID = arguments.popFirstArgument(), arguments.isEmpty else {
        throw CLIError(
          "Usage: instant-swift-data examples reminders delete <reminder-id>",
          exitCode: 64
        )
      }
      let currentReminders = try ReminderExample.decodeReminders(
        (try await context.runtime.queryOnce(ReminderExample.remindersQuery)).values
      )
      guard let reminder = currentReminders.first(where: { $0.id == reminderID }) else {
        throw CLIError("Reminder not found: \(reminderID)", exitCode: 66)
      }
      let transactionID = context.runtime.configuration.makeID()
      let now = context.runtime.configuration.now()
      try await context.runtime.transact(
        InstantStoreTransaction(
          id: transactionID,
          operations: ReminderExample.deleteReminderOperations(
            id: reminderID,
            listID: reminder.remindersListID,
            updatedAt: now,
            transactionID: transactionID
          )
        ),
        createdAt: now,
        source: "cli.examples.reminders.delete"
      )
      try await printReminders(
        context: context,
        output: output,
        event: "delete",
        changedID: reminderID,
        listID: reminder.remindersListID
      )

    case "delete-completed":
      var listID: String?
      while let option = arguments.popFirstArgument() {
        switch option {
        case "--list-id":
          guard let value = arguments.popFirstArgument(), !value.isEmpty else {
            throw CLIError(
              "Usage: instant-swift-data examples reminders delete-completed [--list-id id]",
              exitCode: 64
            )
          }
          listID = value
        default:
          throw CLIError(
            "Usage: instant-swift-data examples reminders delete-completed [--list-id id]",
            exitCode: 64
          )
        }
      }
      let query = listID.map(ReminderExample.remindersForListQuery) ?? ReminderExample.remindersQuery
      if let listID {
        let lists = try ReminderExample.decodeLists(
          (try await context.runtime.queryOnce(ReminderExample.listsQuery)).values
        )
        guard lists.contains(where: { $0.id == listID }) else {
          throw CLIError("Reminder list not found: \(listID)", exitCode: 66)
        }
      }
      let currentReminders = try ReminderExample.decodeReminders(
        (try await context.runtime.queryOnce(query)).values
      )
      let completedReminders = currentReminders.filter(\.isCompleted)
      let transactionID = context.runtime.configuration.makeID()
      let now = context.runtime.configuration.now()
      if !completedReminders.isEmpty {
        try await context.runtime.transact(
          InstantStoreTransaction(
            id: transactionID,
            operations: ReminderExample.deleteCompletedReminderOperations(
              reminders: completedReminders.map { ($0.id, $0.remindersListID) },
              updatedAt: now,
              transactionID: transactionID
            )
          ),
          createdAt: now,
          source: "cli.examples.reminders.delete-completed"
        )
      }
      try await printReminders(
        context: context,
        output: output,
        event: "delete-completed",
        changedID: completedReminders.isEmpty ? nil : completedReminders.map(\.id).joined(separator: ","),
        listID: listID
      )

    case "delete-list":
      guard let listID = arguments.popFirstArgument(), arguments.isEmpty else {
        throw CLIError(
          "Usage: instant-swift-data examples reminders delete-list <list-id>",
          exitCode: 64
        )
      }
      let transactionID = context.runtime.configuration.makeID()
      let now = context.runtime.configuration.now()
      try await context.runtime.transact(
        InstantStoreTransaction(
          id: transactionID,
          operations: ReminderExample.deleteListOperations(id: listID)
        ),
        createdAt: now,
        source: "cli.examples.reminders.delete-list"
      )
      try await printReminders(
        context: context,
        output: output,
        event: "delete-list",
        changedID: listID
      )

    case "add-tag", "tag":
      guard let reminderID = arguments.popFirstArgument() else {
        throw CLIError(
          "Usage: instant-swift-data examples reminders add-tag <reminder-id> <tag>",
          exitCode: 64
        )
      }
      let rawTag = arguments.joined(separator: " ")
      guard let tagID = ReminderExample.normalizedTagTitle(rawTag) else {
        throw CLIError(
          "Usage: instant-swift-data examples reminders add-tag <reminder-id> <tag>",
          exitCode: 64
        )
      }
      let currentReminders = try ReminderExample.decodeReminders(
        (try await context.runtime.queryOnce(ReminderExample.remindersQuery)).values
      )
      guard let reminder = currentReminders.first(where: { $0.id == reminderID }) else {
        throw CLIError("Reminder not found: \(reminderID)", exitCode: 66)
      }
      let transactionID = context.runtime.configuration.makeID()
      let now = context.runtime.configuration.now()
      try await context.runtime.transact(
        InstantStoreTransaction(
          id: transactionID,
          operations: ReminderExample.addTagOperations(
            reminderID: reminderID,
            listID: reminder.remindersListID,
            tagID: tagID,
            title: tagID,
            updatedAt: now,
            transactionID: transactionID
          )
        ),
        createdAt: now,
        source: "cli.examples.reminders.add-tag"
      )
      try await printReminders(
        context: context,
        output: output,
        event: "add-tag",
        changedID: reminderID,
        listID: reminder.remindersListID
      )

    case "remove-tag", "untag":
      guard let reminderID = arguments.popFirstArgument() else {
        throw CLIError(
          "Usage: instant-swift-data examples reminders remove-tag <reminder-id> <tag>",
          exitCode: 64
        )
      }
      let rawTag = arguments.joined(separator: " ")
      guard let tagID = ReminderExample.normalizedTagTitle(rawTag) else {
        throw CLIError(
          "Usage: instant-swift-data examples reminders remove-tag <reminder-id> <tag>",
          exitCode: 64
        )
      }
      let currentReminders = try ReminderExample.decodeReminders(
        (try await context.runtime.queryOnce(ReminderExample.remindersQuery)).values
      )
      guard let reminder = currentReminders.first(where: { $0.id == reminderID }) else {
        throw CLIError("Reminder not found: \(reminderID)", exitCode: 66)
      }
      let transactionID = context.runtime.configuration.makeID()
      let now = context.runtime.configuration.now()
      try await context.runtime.transact(
        InstantStoreTransaction(
          id: transactionID,
          operations: ReminderExample.removeTagOperations(
            reminderID: reminderID,
            listID: reminder.remindersListID,
            tagID: tagID,
            updatedAt: now,
            transactionID: transactionID
          )
        ),
        createdAt: now,
        source: "cli.examples.reminders.remove-tag"
      )
      try await printReminders(
        context: context,
        output: output,
        event: "remove-tag",
        changedID: reminderID,
        listID: reminder.remindersListID
      )

    case "search":
      let options = try parseRemindersSearchOptions(arguments: arguments)
      let query = ReminderExample.remindersSearchQuery(
        text: options.text,
        listID: options.listID,
        tagID: options.tagID,
        includeCompleted: options.includeCompleted,
        flagged: options.flagged,
        scheduled: options.scheduled,
        today: options.today ? context.runtime.configuration.now() : nil,
        priority: options.priority
      )
      try await printReminders(
        context: context,
        output: output,
        event: "search",
        listID: options.listID,
        remindersQuery: query
      )

    default:
      throw CLIError("Unknown reminders command: \(command). \(remindersUsage)", exitCode: 64)
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
    let invocation: CLICacheInvocation
    do {
      var input = arguments[...]
      invocation = try CLICacheParser().parse(&input)
    } catch let error as CLICacheArgumentError {
      throw CLIError(error.description, exitCode: error.exitCode)
    }

    let context = try await CLIContext.bootstrap(initialAttributes: [])
    let snapshot = try await context.runtime.persistence.loadSnapshot()

    switch invocation {
    case .inspect:
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

    case let .attributes(namespace):
      try printCacheAttributes(
        context: context,
        output: output,
        namespace: namespace,
        attributes: cacheAttributes(snapshot.store, namespace: namespace)
      )

    case let .triples(namespace):
      try printCacheTriples(
        context: context,
        output: output,
        namespace: namespace,
        triples: cacheTriples(snapshot.store, namespace: namespace)
      )
    }
  }

  private static func runOutbox(arguments: [String], output: OutputMode) async throws {
    let invocation: CLIOutboxInvocation
    do {
      var input = arguments[...]
      invocation = try CLIOutboxParser().parse(&input)
    } catch let error as CLIOutboxArgumentError {
      throw CLIError(error.description, exitCode: error.exitCode)
    }

    let context = try await CLIContext.bootstrap()

    switch invocation {
    case .inspect:
      try await printOutbox(context: context, output: output)

    case let .transport(includeFailed):
      let mutations = await context.runtime.outboxTransportMutations(includeFailed: includeFailed)
      try printOutboxTransport(
        context: context,
        output: output,
        includeFailed: includeFailed,
        mutations: mutations
      )

    case let .flush(limit):
      let result = try await context.runtime.flushPendingMutations(limit: limit)
      try await printOutboxFlush(context: context, output: output, result: result)

    case let .confirm(mutationID):
      let mutation = try await context.runtime.confirmMutation(id: mutationID)
      try await printOutboxUpdate(
        context: context,
        output: output,
        event: "confirm",
        mutation: mutation
      )

    case let .fail(mutationID, message):
      let mutation = try await context.runtime.failMutation(id: mutationID, message: message)
      try await printOutboxUpdate(
        context: context,
        output: output,
        event: "fail",
        mutation: mutation
      )

    case let .retry(mutationID):
      let mutation = try await context.runtime.retryMutation(id: mutationID)
      try await printOutboxUpdate(
        context: context,
        output: output,
        event: "retry",
        mutation: mutation
      )

    case let .drain(limit):
      let mutations = try await context.runtime.drainPendingMutationsLocally(limit: limit)
      try await printOutboxDrain(
        context: context,
        output: output,
        event: "drain-local-confirm",
        mutations: mutations
      )
    }
  }

  private static func runLocalID(arguments: [String], output: OutputMode) async throws {
    let invocation: CLILocalIDInvocation
    do {
      var input = arguments[...]
      invocation = try CLILocalIDParser().parse(&input)
    } catch let error as CLILocalIDArgumentError {
      throw CLIError(error.description, exitCode: error.exitCode)
    }

    switch invocation {
    case let .get(name):
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

    case .list:
      let context = try await CLIContext.bootstrap(initialAttributes: [])
      let localIDs = try await context.runtime.localIDs()
      try printLocalIDs(context: context, output: output, localIDs: localIDs)
    }
  }

  private static func runAuth(arguments: [String], output: OutputMode) async throws {
    let invocation: CLIAuthInvocation
    do {
      var input = arguments[...]
      invocation = try CLIAuthParser().parse(&input)
    } catch let error as CLIAuthArgumentError {
      throw CLIError(error.description, exitCode: error.exitCode)
    }

    let context = try await CLIContext.bootstrap(initialAttributes: [])

    switch invocation {
    case .show:
      let session = try await context.runtime.authSession()
      try printAuth(context: context, event: "show", session: session, output: output)

    case .guest:
      let session = try await context.runtime.signInAsGuest()
      try printAuth(context: context, event: "guest", session: session, output: output)

    case let .token(options):
      let session = try await context.runtime.signInWithRefreshToken(
        options.refreshToken,
        userID: options.userID
      )
      try printAuth(context: context, event: "token", session: session, output: output)

    case let .idToken(options):
      let session = try await context.runtime.signInWithIDToken(
        clientName: options.clientName,
        idToken: options.idToken,
        nonce: options.nonce
      )
      try printAuth(context: context, event: "id-token", session: session, output: output)

    case let .oauth(options):
      let session = try await context.runtime.signInWithOAuth(
        code: options.code,
        codeVerifier: options.codeVerifier
      )
      try printAuth(context: context, event: "oauth", session: session, output: output)

    case let .oauthURL(options):
      guard let redirectURL = URL(string: options.redirectURL) else {
        throw CLIError(
          CLIAuthUsage.oauthURL,
          exitCode: 64
        )
      }
      let authorizationURL = try context.runtime.oauthAuthorizationURL(
        clientName: options.clientName,
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

    case .issuer:
      let issuerURI = try context.runtime.issuerURI()
      try printAuthEndpoint(
        context: context,
        event: "issuer",
        authorizationURL: nil,
        issuerURI: issuerURI,
        output: output
      )

    case let .magicCode(.send(email)):
      let challenge = try await context.runtime.sendMagicCode(email: email)
      try printMagicCodeChallenge(context: context, challenge: challenge, output: output)

    case let .magicCode(.verify(email, code)):
      let session = try await context.runtime.signInWithMagicCode(email: email, code: code)
      try printAuth(context: context, event: "magic-code", session: session, output: output)

    case let .watch(options):
      try await watchAuth(context: context, output: output, eventCount: options.eventCount)

    case let .signOut(options):
      try await context.runtime.signOut(invalidateToken: options.invalidateToken)
      try printAuth(context: context, event: "sign-out", session: nil, output: output)
    }
  }

  private static func runApp(arguments: [String], output: OutputMode) async throws {
    let invocation: CLIAppInvocation
    do {
      var input = arguments[...]
      invocation = try CLIAppParser().parse(&input)
    } catch let error as CLIAppArgumentError {
      throw CLIError(error.description, exitCode: error.exitCode)
    }

    switch invocation {
    case .show:
      let context = try await CLIContext.bootstrap(initialAttributes: [])
      try printApp(context: context, event: "show", output: output)

    case let .select(appID):
      let context = try await CLIContext.bootstrap(appIDOverride: appID, initialAttributes: [])
      _ = try await context.runtime.saveSelectedAppID(appID)
      try printApp(context: context, event: "select", output: output)

    case let .ephemeral(options):
      let app = try InstantEphemeralApps.makeLocal(title: options.title)
      let context = try await CLIContext.bootstrap(appIDOverride: app.appID, initialAttributes: [])
      _ = try await context.runtime.saveSelectedAppID(app.appID)
      try printApp(context: context, event: "ephemeral", output: output, ephemeralApp: app)
    }
  }

  private static func runSync(arguments: [String], output: OutputMode) async throws {
    let invocation: CLISyncInvocation
    do {
      var input = arguments[...]
      invocation = try CLISyncParser().parse(&input)
    } catch let error as CLISyncArgumentError {
      throw CLIError(error.description, exitCode: error.exitCode)
    }

    let context = try await CLIContext.bootstrap(initialAttributes: [])

    switch invocation {
    case .inspect:
      let state = try await context.runtime.syncState()
      try printSync(context: context, event: "inspect", state: state, output: output)

    case let .markProcessed(transactionID):
      let state = try await context.runtime.markProcessedTransaction(id: transactionID)
      try printSync(context: context, event: "mark-processed", state: state, output: output)
    }
  }

  private static func runConnection(arguments: [String], output: OutputMode) async throws {
    let invocation: CLIConnectionInvocation
    do {
      var input = arguments[...]
      invocation = try CLIConnectionParser().parse(&input)
    } catch let error as CLIConnectionArgumentError {
      throw CLIError(error.description, exitCode: error.exitCode)
    }

    let context = try await CLIContext.bootstrap(initialAttributes: [])

    switch invocation {
    case .status:
      let status = try await context.runtime.connectionStatus()
      try printConnectionStatus(context: context, event: "status", status: status, output: output)

    case .connect:
      let status = try await context.runtime.connect()
      try printConnectionStatus(context: context, event: "connect", status: status, output: output)

    case .close:
      let status = try await context.runtime.closeConnection()
      try printConnectionStatus(context: context, event: "close", status: status, output: output)
    }
  }

  private static func runRooms(arguments: [String], output: OutputMode) async throws {
    let invocation: CLIRoomsInvocation
    do {
      var input = arguments[...]
      invocation = try CLIRoomsParser().parse(&input)
    } catch let error as CLIRoomsArgumentError {
      throw CLIError(error.description, exitCode: error.exitCode)
    }

    let context = try await CLIContext.bootstrap(initialAttributes: [])

    switch invocation {
    case let .presence(presence):
      try await runRoomPresence(invocation: presence, context: context, output: output)

    case let .topics(topics):
      try await runRoomTopics(invocation: topics, context: context, output: output)
    }
  }

  private static func runRoomPresence(
    invocation: CLIRoomPresenceInvocation,
    context: CLIContext,
    output: OutputMode
  ) async throws {
    switch invocation {
    case let .set(options):
      let room = options.room.instantRoomHandle
      let values = try parseLastJSONObject(
        options.values,
        operation: "set room presence",
        usage: roomPresenceUsage
      )
      let member = try await context.runtime.setPresence(
        room: room,
        userID: options.userID,
        values: values
      )
      let members = try await context.runtime.roomPresence(room: room)
      try printRoomPresence(
        context: context,
        event: "presence-set",
        room: room,
        userID: member.userID,
        members: members,
        output: output
      )

    case let .list(roomIdentifier):
      let room = roomIdentifier.instantRoomHandle
      let members = try await context.runtime.roomPresence(room: room)
      try printRoomPresence(
        context: context,
        event: "presence-list",
        room: room,
        userID: nil,
        members: members,
        output: output
      )

    case let .watch(options):
      let room = options.room.instantRoomHandle
      let members = try await firstWatchSnapshot(
        from: context.runtime.observeRoomPresence(room: room),
        operation: "room presence watch",
        eventCount: options.eventCount
      )
      try printRoomPresence(
        context: context,
        event: "presence-watch",
        room: room,
        userID: nil,
        members: members,
        output: output
      )

    case let .leave(options):
      let room = options.room.instantRoomHandle
      let userID = try await context.runtime.leavePresence(
        room: room,
        userID: options.userID
      )
      let members = try await context.runtime.roomPresence(room: room)
      try printRoomPresence(
        context: context,
        event: "presence-leave",
        room: room,
        userID: userID,
        members: members,
        output: output
      )
    }
  }

  private static func runRoomTopics(
    invocation: CLIRoomTopicsInvocation,
    context: CLIContext,
    output: OutputMode
  ) async throws {
    switch invocation {
    case let .publish(options):
      let room = options.room.instantRoomHandle
      let payload = try parseLastJSONValue(
        options.values,
        operation: "publish room topic",
        usage: roomTopicsUsage
      )
      let message = try await context.runtime.publishTopicMessage(
        room: room,
        topic: options.topic,
        userID: options.userID,
        payload: payload
      )
      let messages = try await context.runtime.roomTopicMessages(
        room: room,
        topic: options.topic
      )
      try printRoomTopic(
        context: context,
        event: "topic-publish",
        room: room,
        topic: options.topic,
        publishedMessageID: message.id,
        messages: messages,
        output: output
      )

    case let .list(options):
      let room = options.room.instantRoomHandle
      let messages = try await context.runtime.roomTopicMessages(
        room: room,
        topic: options.topic,
        limit: options.limit
      )
      try printRoomTopic(
        context: context,
        event: "topic-list",
        room: room,
        topic: options.topic,
        publishedMessageID: nil,
        messages: messages,
        output: output
      )

    case let .watch(options):
      let room = options.room.instantRoomHandle
      let messages = try await firstWatchSnapshot(
        from: context.runtime.observeRoomTopicMessages(
          room: room,
          topic: options.topic
        ),
        operation: "room topic watch",
        eventCount: options.eventCount
      )
      try printRoomTopic(
        context: context,
        event: "topic-watch",
        room: room,
        topic: options.topic,
        publishedMessageID: nil,
        messages: messages,
        output: output
      )
    }
  }

  private static func runFiles(arguments: [String], output: OutputMode) async throws {
    let invocation: CLIFilesInvocation
    do {
      var input = arguments[...]
      invocation = try CLIFilesParser().parse(&input)
    } catch let error as CLIFilesArgumentError {
      throw CLIError(error.description, exitCode: error.exitCode)
    }

    let context = try await CLIContext.bootstrap(initialAttributes: [])

    switch invocation {
    case let .upload(options):
      let file = try await context.runtime.uploadFile(
        from: fileSourceURL(for: options.sourcePath),
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

    case let .uploadProgress(options):
      try await printFileUploadProgress(
        context: context,
        options: options,
        output: output
      )

    case .list:
      let files = try await context.runtime.storedFiles()
      try printFiles(
        context: context,
        event: "list",
        changedID: nil,
        files: files,
        output: output
      )

    case let .watch(options):
      let files = try await firstWatchSnapshot(
        from: context.runtime.observeStoredFiles(),
        operation: "files watch",
        eventCount: options.eventCount
      )
      try printFiles(
        context: context,
        event: "watch",
        changedID: nil,
        files: files,
        output: output
      )

    case let .read(fileID):
      let contents = try await context.runtime.storedFileContents(id: fileID)
      try printFileContents(
        context: context,
        contents: contents,
        output: output
      )

    case let .delete(fileID):
      let file = try await context.runtime.deleteStoredFile(id: fileID)
      let files = try await context.runtime.storedFiles()
      try printFiles(
        context: context,
        event: "delete",
        changedID: file.id,
        files: files,
        output: output
      )
    }
  }

  private static func runStreams(arguments: [String], output: OutputMode) async throws {
    let invocation: CLIStreamsInvocation
    do {
      var input = arguments[...]
      invocation = try CLIStreamsParser().parse(&input)
    } catch let error as CLIStreamsArgumentError {
      throw CLIError(error.description, exitCode: error.exitCode)
    }

    let context = try await CLIContext.bootstrap(initialAttributes: [])

    switch invocation {
    case let .append(options):
      var payload: JSONValue?
      for value in options.values {
        payload = try parseJSONValue(value, operation: "append stream chunk")
      }
      guard let payload else {
        throw CLIError(streamsUsage, exitCode: 64)
      }
      let chunk = try await context.runtime.appendStreamChunk(
        streamID: options.streamID,
        payload: payload
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

    case let .read(options):
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

    case let .watch(options):
      let chunks = try await firstWatchSnapshot(
        from: context.runtime.observeStreamChunks(streamID: options.streamID),
        operation: "stream watch",
        eventCount: options.eventCount
      )
      try printStreamChunks(
        context: context,
        event: "watch",
        streamID: options.streamID,
        changedID: nil,
        chunks: chunks,
        output: output
      )
    }
  }

  private static func firstWatchSnapshot<Value: Sendable>(
    from stream: AsyncStream<[Value]>,
    operation: String,
    eventCount: Int
  ) async throws -> [Value] {
    guard eventCount == 1 else {
      throw CLIError("Only --events 1 is supported for \(operation).", exitCode: 64)
    }
    var iterator = stream.makeAsyncIterator()
    guard let snapshot = await iterator.next() else {
      throw CLIError("Expected \(operation) to emit an initial snapshot.", exitCode: 70)
    }
    return snapshot
  }

  private static func runShares(arguments: [String], output: OutputMode) async throws {
    let invocation: CLISharesInvocation
    do {
      var input = arguments[...]
      invocation = try CLISharesParser().parse(&input)
    } catch let error as CLISharesArgumentError {
      throw CLIError(error.description, exitCode: error.exitCode)
    }

    let context = try await CLIContext.bootstrap(initialAttributes: [])

    switch invocation {
    case let .create(create):
      let snapshot = try await context.runtime.createShare(
        rootNamespace: create.namespace,
        rootID: create.entityID
      )
      try printShares(
        context: context,
        event: "create",
        changedID: snapshot.share.id,
        shares: [snapshot],
        output: output
      )

    case .list:
      let shares = try await context.runtime.shares()
      try printShares(
        context: context,
        event: "list",
        changedID: nil,
        shares: shares,
        output: output
      )

    case let .accept(token):
      let snapshot = try await context.runtime.acceptShare(token: token)
      try printShares(
        context: context,
        event: "accept",
        changedID: snapshot.share.id,
        shares: [snapshot],
        output: output
      )

    case let .role(roleInvocation):
      let snapshot = try await context.runtime.updateShareMembershipRole(
        shareID: roleInvocation.shareID,
        userID: roleInvocation.userID,
        role: shareRole(roleInvocation.role)
      )
      try printShares(
        context: context,
        event: "role",
        changedID: snapshot.share.id,
        shares: [snapshot],
        output: output
      )

    case let .revoke(shareID):
      let snapshot = try await context.runtime.revokeShare(id: shareID)
      try printShares(
        context: context,
        event: "revoke",
        changedID: snapshot.share.id,
        shares: [snapshot],
        output: output
      )
    }
  }

  private static func shareRole(_ role: CLIShareRole) -> InstantShareRole {
    switch role {
    case .reader:
      return .reader
    case .writer:
      return .writer
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

  private static func printFileUploadProgress(
    context: CLIContext,
    options: CLIFileUploadInvocation,
    output: OutputMode
  ) async throws {
    let stream = try await context.runtime.uploadFileProgress(
      from: fileSourceURL(for: options.sourcePath),
      name: options.name,
      contentType: options.contentType
    )
    var events: [FileUploadProgressOutput] = []
    var index = 0

    for try await progress in stream {
      let payload = FileUploadProgressOutput(
        appID: context.appID,
        cachePath: context.cacheURL.path,
        event: "upload-progress",
        transport: "not-implemented-local-cache-only",
        index: index,
        operationID: progress.operationID,
        fileID: progress.fileID,
        fileName: progress.fileName,
        contentType: progress.contentType,
        state: progress.state,
        completedByteCount: progress.completedByteCount,
        totalByteCount: progress.totalByteCount,
        progress: progress.progress,
        file: progress.file,
        errorMessage: progress.errorMessage,
        updatedAt: progress.updatedAt
      )

      switch output {
      case .human:
        print(
          "upload: \(payload.state.rawValue) \(payload.completedByteCount)/\(payload.totalByteCount) bytes"
        )
        if let file = payload.file {
          print("file: \(file.id) \(file.name)")
        }
        if let errorMessage = payload.errorMessage {
          print("error: \(errorMessage)")
        }

      case .json:
        break

      case .jsonl:
        try writeJSONLine(
          EvidenceRow(
            caseID: "cli.files.upload-progress",
            side: "swift",
            event: payload.state.rawValue,
            appID: context.appID,
            entityID: payload.fileID,
            ok: payload.state != .error,
            details: payload
          )
        )
      }

      events.append(payload)
      index += 1
    }

    switch output {
    case .human, .jsonl:
      break

    case .json:
      try writeJSON(
        FileUploadProgressSummaryOutput(
          appID: context.appID,
          cachePath: context.cacheURL.path,
          event: "upload-progress",
          transport: "not-implemented-local-cache-only",
          emittedEventCount: events.count,
          finalState: events.last?.state ?? .idle,
          events: events
        )
      )
    }
  }

  private static func printFileContents(
    context: CLIContext,
    contents: InstantStoredFileContents,
    output: OutputMode
  ) throws {
    let utf8Content = String(data: contents.data, encoding: .utf8)
    let payload = FileContentsOutput(
      appID: context.appID,
      cachePath: context.cacheURL.path,
      event: "read",
      transport: "not-implemented-local-cache-only",
      file: contents.file,
      byteCount: contents.byteCount,
      base64Content: contents.data.base64EncodedString(),
      utf8Content: utf8Content
    )

    switch output {
    case .human:
      if let utf8Content {
        print(utf8Content, terminator: utf8Content.hasSuffix("\n") ? "" : "\n")
      } else {
        print(payload.base64Content)
      }

    case .json:
      try writeJSON(payload)

    case .jsonl:
      try writeJSONLine(
        EvidenceRow(
          caseID: "cli.files.contents",
          side: "swift",
          event: "read",
          appID: context.appID,
          entityID: contents.file.id,
          ok: true,
          details: payload
        )
      )
    }
  }

  private static func fileSourceURL(for path: String) -> URL {
    let currentDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    return URL(fileURLWithPath: path, relativeTo: currentDirectory).standardizedFileURL
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
    caseID: String = "cli.examples.todos",
    allowOfflineLocalEmission: Bool = false
  ) async throws {
    let emission = try await todoEmission(
      context: context,
      query: query,
      allowOfflineLocalEmission: allowOfflineLocalEmission
    )
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

  private static func printReminders(
    context: CLIContext,
    output: OutputMode,
    event: String,
    changedID: String? = nil,
    listID: String? = nil,
    remindersQuery explicitRemindersQuery: InstantQueryPlan? = nil
  ) async throws {
    let listsEmission = try await context.runtime.queryOnce(ReminderExample.listsQuery)
    let remindersQuery = explicitRemindersQuery
      ?? listID.map(ReminderExample.remindersForListQuery)
      ?? ReminderExample.remindersQuery
    let remindersEmission = try await context.runtime.queryOnce(remindersQuery)
    let allRemindersEmission = listID == nil && explicitRemindersQuery == nil
      ? remindersEmission
      : try await context.runtime.queryOnce(ReminderExample.remindersQuery)
    let tagsEmission = try await context.runtime.queryOnce(ReminderExample.tagsQuery)
    let lists = try ReminderExample.decodeLists(listsEmission.values)
    let reminders = try ReminderExample.decodeReminders(remindersEmission.values)
    let allReminders = try ReminderExample.decodeReminders(allRemindersEmission.values)
    let tags = try ReminderExample.decodeTags(tagsEmission.values)
    let reminderTags = try ReminderExample.decodeReminderTagLinks(remindersEmission.values)
    let remindersByListID = Dictionary(grouping: allReminders, by: \.remindersListID)
    let stats = ReminderExample.stats(
      for: allReminders,
      today: context.runtime.configuration.now()
    )
    let listSummaries = lists.map { list in
      RemindersListSummary(
        list: list,
        reminderCount: remindersByListID[list.id]?.filter { !$0.isCompleted }.count ?? 0
      )
    }
    let pending = await context.runtime.pendingMutations()
    let payload = RemindersOutput(
      appID: context.appID,
      cachePath: context.cacheURL.path,
      event: event,
      changedID: changedID,
      transport: "not-implemented-local-cache-only",
      listQueryID: ReminderExample.listsQuery.id,
      reminderQueryID: remindersQuery.id,
      tagQueryID: ReminderExample.tagsQuery.id,
      listCacheKey: ReminderExample.listsQuery.cacheKey,
      reminderCacheKey: remindersQuery.cacheKey,
      tagCacheKey: ReminderExample.tagsQuery.cacheKey,
      pendingMutationCount: pending.count,
      lists: listSummaries,
      stats: stats,
      reminders: reminders,
      tags: tags,
      reminderTags: reminderTags
    )

    switch output {
    case .human:
      if listSummaries.isEmpty {
        print("No reminder lists.")
      } else {
        for summary in listSummaries {
          print(
            "list \(summary.list.id) \(summary.list.title) reminders=\(summary.reminderCount)"
          )
        }
      }
      print(
        "stats: all=\(stats.allCount) completed=\(stats.completedCount) flagged=\(stats.flaggedCount) scheduled=\(stats.scheduledCount) today=\(stats.todayCount)"
      )
      if reminders.isEmpty {
        print("No reminders.")
      } else {
        let tagsByReminderID = Dictionary(grouping: reminderTags, by: \.reminderID)
        for reminder in reminders {
          let mark = reminder.isCompleted ? "[x]" : "[ ]"
          let flag = reminder.isFlagged ? " flagged" : ""
          let dueDate = reminder.dueDate.map { " due=\(formatReminderDueDate($0))" } ?? ""
          let priority = reminder.priority.map { " priority=\($0.rawValue)" } ?? ""
          let notes = reminder.notes.isEmpty ? "" : " notes=\"\(escapedHumanValue(reminder.notes))\""
          let tagList = (tagsByReminderID[reminder.id] ?? [])
            .map { "#\($0.tagID)" }
            .joined(separator: " ")
          let suffix = tagList.isEmpty ? "" : " \(tagList)"
          print(
            "\(mark) \(reminder.id) list=\(reminder.remindersListID)\(flag)\(dueDate)\(priority) \(reminder.title)\(suffix)\(notes)"
          )
        }
      }
      if !tags.isEmpty {
        print("tags: \(tags.map { "#\($0.title)" }.joined(separator: " "))")
      }
      print("transport: \(payload.transport)")
      print("pending mutations: \(pending.count)")
      print("cache: \(context.cacheURL.path)")

    case .json:
      try writeJSON(payload)

    case .jsonl:
      try writeJSONLine(
        EvidenceRow(
          caseID: "cli.examples.reminders",
          side: "swift",
          event: event,
          appID: context.appID,
          ok: true,
          details: payload
        )
      )
      for summary in listSummaries {
        try writeJSONLine(
          EvidenceRow(
            caseID: "cli.examples.reminders",
            side: "swift",
            event: "reminders-list",
            appID: context.appID,
            entityID: summary.id,
            ok: true,
            details: summary
          )
        )
      }
      for reminder in reminders {
        try writeJSONLine(
          EvidenceRow(
            caseID: "cli.examples.reminders",
            side: "swift",
            event: "reminder",
            appID: context.appID,
            entityID: reminder.id,
            ok: true,
            details: reminder
          )
        )
      }
      for tag in tags {
        try writeJSONLine(
          EvidenceRow(
            caseID: "cli.examples.reminders",
            side: "swift",
            event: "tag",
            appID: context.appID,
            entityID: tag.id,
            ok: true,
            details: tag
          )
        )
      }
      for reminderTag in reminderTags {
        try writeJSONLine(
          EvidenceRow(
            caseID: "cli.examples.reminders",
            side: "swift",
            event: "reminder-tag",
            appID: context.appID,
            entityID: reminderTag.id,
            ok: true,
            details: reminderTag
          )
        )
      }
    }
  }

  private static func printSyncUps(
    context: CLIContext,
    output: OutputMode,
    event: String,
    changedID: String? = nil,
    syncUpID: String? = nil
  ) async throws {
    let syncUpsEmission = try await context.runtime.queryOnce(SyncUpsExample.syncUpsQuery)
    let attendeeQuery = syncUpID.map(SyncUpsExample.attendeesForSyncUpQuery)
      ?? SyncUpsExample.attendeesQuery
    let meetingQuery = syncUpID.map(SyncUpsExample.meetingsForSyncUpQuery)
      ?? SyncUpsExample.meetingsQuery
    let attendeesEmission = try await context.runtime.queryOnce(attendeeQuery)
    let meetingsEmission = try await context.runtime.queryOnce(meetingQuery)
    let allAttendeesEmission = syncUpID == nil
      ? attendeesEmission
      : try await context.runtime.queryOnce(SyncUpsExample.attendeesQuery)
    let allMeetingsEmission = syncUpID == nil
      ? meetingsEmission
      : try await context.runtime.queryOnce(SyncUpsExample.meetingsQuery)

    let syncUps = try SyncUpsExample.decodeSyncUps(syncUpsEmission.values)
    let attendees = try SyncUpsExample.decodeAttendees(attendeesEmission.values)
    let meetings = try SyncUpsExample.decodeMeetings(meetingsEmission.values)
    let allAttendees = try SyncUpsExample.decodeAttendees(allAttendeesEmission.values)
    let allMeetings = try SyncUpsExample.decodeMeetings(allMeetingsEmission.values)
    let attendeesBySyncUpID = Dictionary(grouping: allAttendees, by: \.syncUpID)
    let meetingsBySyncUpID = Dictionary(grouping: allMeetings, by: \.syncUpID)
    let visibleSyncUps = syncUpID.map { id in
      syncUps.filter { $0.id == id }
    } ?? syncUps
    let summaries = visibleSyncUps.map { syncUp in
      SyncUpSummary(
        syncUp: syncUp,
        attendeeCount: attendeesBySyncUpID[syncUp.id]?.count ?? 0,
        meetingCount: meetingsBySyncUpID[syncUp.id]?.count ?? 0
      )
    }
    let pending = await context.runtime.pendingMutations()
    let payload = SyncUpsOutput(
      appID: context.appID,
      cachePath: context.cacheURL.path,
      event: event,
      changedID: changedID,
      transport: "not-implemented-local-cache-only",
      syncUpQueryID: SyncUpsExample.syncUpsQuery.id,
      attendeeQueryID: attendeeQuery.id,
      meetingQueryID: meetingQuery.id,
      syncUpCacheKey: SyncUpsExample.syncUpsQuery.cacheKey,
      attendeeCacheKey: attendeeQuery.cacheKey,
      meetingCacheKey: meetingQuery.cacheKey,
      pendingMutationCount: pending.count,
      syncUps: summaries,
      attendees: attendees,
      meetings: meetings
    )

    switch output {
    case .human:
      if summaries.isEmpty {
        print("No sync-ups.")
      } else {
        for summary in summaries {
          print(
            "sync-up \(summary.syncUp.id) \(summary.syncUp.title) "
              + "attendees=\(summary.attendeeCount) meetings=\(summary.meetingCount) "
              + "seconds=\(summary.syncUp.seconds) theme=\(summary.syncUp.theme.rawValue)"
          )
        }
      }
      if attendees.isEmpty {
        print("No attendees.")
      } else {
        for attendee in attendees {
          print("attendee \(attendee.id) syncUp=\(attendee.syncUpID) \(attendee.name)")
        }
      }
      if meetings.isEmpty {
        print("No meetings.")
      } else {
        for meeting in meetings {
          print(
            "meeting \(meeting.id) syncUp=\(meeting.syncUpID) "
              + "date=\(meeting.date.milliseconds) transcript=\(meeting.transcript)"
          )
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
          caseID: "cli.examples.sync-ups",
          side: "swift",
          event: event,
          appID: context.appID,
          ok: true,
          details: payload
        )
      )
      for summary in summaries {
        try writeJSONLine(
          EvidenceRow(
            caseID: "cli.examples.sync-ups",
            side: "swift",
            event: "sync-up",
            appID: context.appID,
            entityID: summary.id,
            ok: true,
            details: summary
          )
        )
      }
      for attendee in attendees {
        try writeJSONLine(
          EvidenceRow(
            caseID: "cli.examples.sync-ups",
            side: "swift",
            event: "sync-up-attendee",
            appID: context.appID,
            entityID: attendee.id,
            ok: true,
            details: attendee
          )
        )
      }
      for meeting in meetings {
        try writeJSONLine(
          EvidenceRow(
            caseID: "cli.examples.sync-ups",
            side: "swift",
            event: "sync-up-meeting",
            appID: context.appID,
            entityID: meeting.id,
            ok: true,
            details: meeting
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

  private static func todoEmission(
    context: CLIContext,
    query: InstantQueryPlan,
    allowOfflineLocalEmission: Bool
  ) async throws -> InstantQueryEmission {
    do {
      return try await context.runtime.queryOnce(query)
    } catch let error as InstantError {
      guard allowOfflineLocalEmission, error.code == .networkFailed else {
        throw error
      }
      let stream = await context.runtime.observe(query)
      var iterator = stream.makeAsyncIterator()
      guard let emission = await iterator.next() else {
        throw error
      }
      return emission
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
    do {
      _ = try await context.runtime.queryOnce(options.query)
    } catch let error as InstantError where error.code == .networkFailed {
      // Offline watches can still emit from the local SQLite-backed snapshot.
    }
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
        admin transact <namespace> <entity-id> --merge '{...}' [--transaction-id id] [--json|--jsonl]
        examples todos seed [--json|--jsonl]
        examples todos add "do the dishes" [--json|--jsonl]
        examples reminders list [--refresh] [--json|--jsonl]
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
        files upload-progress <path> [--name name] [--content-type type] [--json|--jsonl]
        files list [--json|--jsonl]
        files watch [--events 1] [--json|--jsonl]
        files read <file-id> [--json|--jsonl]
        files delete <file-id> [--json|--jsonl]
        streams append <stream-id> --value '{...}' [--json|--jsonl]
        streams read <stream-id> [--limit n] [--json|--jsonl]
        shares create <namespace> <entity-id> [--json|--jsonl]
        shares list [--json|--jsonl]
        shares accept <token> [--json|--jsonl]
        shares role <share-id> <user-id> <reader|writer> [--json|--jsonl]
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
        validation local-integrations [--json|--jsonl]
        benchmark [--suite local-todos] [--iterations n] [--app-id id] [--json|--jsonl]

      Environment:
        INSTANT_SWIFT_DATA_HOME  Directory for CLI SQLite state. Defaults to ~/.instant-swift-data.
        INSTANT_APP_ID           Logical app id recorded in output. Defaults to local-demo.
        INSTANT_SWIFT_DATA_NOW   Fixed clock for local runs. Accepts YYYY-MM-DD, ISO-8601, or epoch milliseconds.
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

  private static func printLocalIntegrationValidation(
    result: LocalIntegrationValidationResult,
    output: OutputMode
  ) throws {
    let finalDetails = result.evidence.last?.details
    let summary = LocalIntegrationValidationOutput(
      appID: result.appID,
      cachePath: result.cacheURL.path,
      event: "local-integrations",
      transport: "not-implemented-local-cache-only",
      ok: result.evidence.allSatisfy { $0.ok },
      evidenceCount: result.evidence.count,
      events: result.evidence.map(\.event),
      authUserID: finalDetails?.authUserID,
      roomMemberCount: finalDetails?.roomMemberIDs.count ?? 0,
      topicMessageCount: finalDetails?.topicMessageIDs.count ?? 0,
      fileCount: finalDetails?.fileIDs.count ?? 0,
      streamChunkCount: finalDetails?.streamChunkIDs.count ?? 0,
      activeShareCount: finalDetails?.activeShareIDs.count ?? 0,
      revokedShareCount: result.evidence.flatMap(\.details.revokedShareIDs).count
    )

    switch output {
    case .human:
      print("validation: \(summary.ok ? "ok" : "failed")")
      print("case: validation.local.integrations")
      print("events: \(summary.events.joined(separator: ", "))")
      print("evidence rows: \(summary.evidenceCount)")
      print("files: \(summary.fileCount)")
      print("stream chunks: \(summary.streamChunkCount)")
      print("active shares: \(summary.activeShareCount)")
      print("revoked shares: \(summary.revokedShareCount)")
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
    caseID: String,
    appID: String,
    error: any Error
  ) -> ValidationEvidenceRow<[String: String]> {
    ValidationEvidenceRow(
      caseID: caseID,
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

  fileprivate static func parseFiniteWatchEventCount(
    arguments: [String],
    usageCommand: String,
    domain: String
  ) throws -> Int {
    var arguments = arguments
    var eventCount = 1
    while let option = arguments.popFirstArgument() {
      switch option {
      case "--events":
        guard let value = arguments.popFirstArgument(),
          let parsed = Int(value),
          parsed == 1
        else {
          throw CLIError("Usage: \(usageCommand) --events 1", exitCode: 64)
        }
        eventCount = parsed

      default:
        throw CLIError(
          "Unknown \(domain) option: \(option). Usage: \(usageCommand) [--events 1] [--json|--jsonl]",
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

  private static func todoQueryOptions(invocation: CLITodosQueryInvocation) -> TodoQueryOptions {
    return TodoQueryOptions(
      query: makeTodoListQuery(
        completed: invocation.completed,
        search: invocation.search,
        offset: invocation.offset,
        limit: invocation.limit,
        first: invocation.first,
        after: invocation.after.map(instantCursor),
        last: invocation.last,
        before: invocation.before.map(instantCursor),
        direction: instantSortDirection(invocation.direction),
        orderField: instantTodoOrderField(invocation.orderField),
        selectedFields: invocation.selectedFields
      ),
      rawSnapshots: invocation.rawSnapshots
    )
  }

  private static func instantCursor(_ cursor: CLIQueryCursor) -> InstantQueryCursor {
    InstantQueryCursor(entityID: cursor.entityID, inclusive: cursor.inclusive)
  }

  private static func instantSortDirection(
    _ direction: CLIQuerySortDirection
  ) -> InstantQuerySortDirection {
    switch direction {
    case .ascending:
      return .ascending
    case .descending:
      return .descending
    }
  }

  private static func instantTodoOrderField(
    _ orderField: CLITodosQueryOrderField
  ) -> String {
    switch orderField {
    case .none:
      return "none"
    case .createdAt:
      return "createdAt"
    case .serverCreatedAt:
      return InstantQueryOrder.serverCreatedAtField
    }
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

  private static func parseRemindersSearchOptions(arguments: [String]) throws -> RemindersSearchOptions {
    var arguments = arguments
    var terms: [String] = []
    var listID: String?
    var tagID: String?
    var includeCompleted = false
    var flagged: Bool?
    var scheduled = false
    var today = false
    var priority: ReminderPriority?

    while let option = arguments.popFirstArgument() {
      switch option {
      case "--list-id":
        guard let value = arguments.popFirstArgument(), !value.isEmpty else {
          throw CLIError(remindersSearchUsage, exitCode: 64)
        }
        listID = value

      case "--tag":
        guard let rawValue = arguments.popFirstArgument(),
          let normalized = ReminderExample.normalizedTagTitle(rawValue)
        else {
          throw CLIError(remindersSearchUsage, exitCode: 64)
        }
        tagID = normalized

      case "--completed", "--include-completed":
        includeCompleted = true

      case "--flagged":
        flagged = true

      case "--unflagged":
        flagged = false

      case "--scheduled":
        scheduled = true

      case "--today":
        today = true
        scheduled = true

      case "--priority":
        guard let value = arguments.popFirstArgument(), let parsed = ReminderPriority(rawValue: value) else {
          throw CLIError(remindersSearchUsage, exitCode: 64)
        }
        priority = parsed

      default:
        terms.append(option)
      }
    }

    let text = terms.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty || tagID != nil || listID != nil || flagged != nil || scheduled || today || priority != nil else {
      throw CLIError(remindersSearchUsage, exitCode: 64)
    }

    return RemindersSearchOptions(
      text: text,
      listID: listID,
      tagID: tagID,
      includeCompleted: includeCompleted,
      flagged: flagged,
      scheduled: scheduled,
      today: today,
      priority: priority
    )
  }

  private static func parseRemindersListOptions(arguments: [String], event: String) throws -> RemindersListOptions {
    var arguments = arguments
    var event = event
    var listID: String?
    var includeCompleted = true
    var didSetCompleted = false
    var flagged: Bool?
    var scheduled = false
    var today = false
    var priority: ReminderPriority?

    while let option = arguments.popFirstArgument() {
      switch option {
      case "--refresh":
        event = "refresh"

      case "--list-id":
        guard let value = arguments.popFirstArgument(), !value.isEmpty else {
          throw CLIError(remindersListUsage, exitCode: 64)
        }
        listID = value

      case "--completed":
        guard let value = arguments.popFirstArgument(), let parsed = parseBool(value) else {
          throw CLIError(remindersListUsage, exitCode: 64)
        }
        includeCompleted = parsed
        didSetCompleted = true

      case "--flagged":
        flagged = true
        if !didSetCompleted {
          includeCompleted = false
        }

      case "--unflagged":
        flagged = false
        if !didSetCompleted {
          includeCompleted = false
        }

      case "--scheduled":
        scheduled = true
        if !didSetCompleted {
          includeCompleted = false
        }

      case "--today":
        today = true
        scheduled = true
        if !didSetCompleted {
          includeCompleted = false
        }

      case "--priority":
        guard let value = arguments.popFirstArgument(), let parsed = ReminderPriority(rawValue: value) else {
          throw CLIError(remindersListUsage, exitCode: 64)
        }
        priority = parsed
        if !didSetCompleted {
          includeCompleted = false
        }

      default:
        throw CLIError(remindersListUsage, exitCode: 64)
      }
    }

    return RemindersListOptions(
      event: event,
      listID: listID,
      includeCompleted: includeCompleted,
      flagged: flagged,
      scheduled: scheduled,
      today: today,
      priority: priority
    )
  }

  private static func parseReminderAddOptions(arguments: [String]) throws -> ReminderAddOptions {
    var arguments = arguments
    var titleParts: [String] = []
    var notes = ""
    var isFlagged = false
    var dueDate: InstantTimestamp?
    var priority: ReminderPriority?

    while let value = arguments.popFirstArgument() {
      switch value {
      case "--notes":
        guard let rawNotes = arguments.popFirstArgument() else {
          throw CLIError(remindersAddUsage, exitCode: 64)
        }
        notes = rawNotes

      case "--flagged":
        isFlagged = true

      case "--unflagged":
        isFlagged = false

      case "--due-date":
        guard let rawDueDate = arguments.popFirstArgument() else {
          throw CLIError(remindersAddUsage, exitCode: 64)
        }
        dueDate = try parseReminderDueDate(rawDueDate)

      case "--priority":
        guard let rawPriority = arguments.popFirstArgument(), let parsed = ReminderPriority(rawValue: rawPriority) else {
          throw CLIError(remindersAddUsage, exitCode: 64)
        }
        priority = parsed

      default:
        titleParts.append(value)
      }
    }

    let title = titleParts.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    guard !title.isEmpty else {
      throw CLIError(remindersAddUsage, exitCode: 64)
    }

    return ReminderAddOptions(
      title: title,
      notes: notes,
      isFlagged: isFlagged,
      dueDate: dueDate,
      priority: priority
    )
  }

  private static func parseReminderUpdateOptions(
    arguments: [String],
    current: ReminderRecord
  ) throws -> ReminderUpdateOptions {
    var arguments = arguments
    var titleParts: [String] = []
    var notes = current.notes
    var isFlagged = current.isFlagged
    var dueDate = current.dueDate
    var priority = current.priority
    var didSetField = false

    while let value = arguments.popFirstArgument() {
      switch value {
      case "--notes":
        guard let rawNotes = arguments.popFirstArgument() else {
          throw CLIError(remindersUpdateUsage, exitCode: 64)
        }
        notes = rawNotes
        didSetField = true

      case "--flagged":
        isFlagged = true
        didSetField = true

      case "--unflagged":
        isFlagged = false
        didSetField = true

      case "--due-date":
        guard let rawDueDate = arguments.popFirstArgument() else {
          throw CLIError(remindersUpdateUsage, exitCode: 64)
        }
        dueDate = try parseReminderDueDate(rawDueDate)
        didSetField = true

      case "--clear-due-date":
        dueDate = nil
        didSetField = true

      case "--priority":
        guard let rawPriority = arguments.popFirstArgument() else {
          throw CLIError(remindersUpdateUsage, exitCode: 64)
        }
        if rawPriority == "none" {
          priority = nil
        } else if let parsed = ReminderPriority(rawValue: rawPriority) {
          priority = parsed
        } else {
          throw CLIError(remindersUpdateUsage, exitCode: 64)
        }
        didSetField = true

      case "--clear-priority":
        priority = nil
        didSetField = true

      default:
        titleParts.append(value)
      }
    }

    let title = titleParts.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    if title.isEmpty && !didSetField {
      throw CLIError(remindersUpdateUsage, exitCode: 64)
    }

    return ReminderUpdateOptions(
      title: title.isEmpty ? current.title : title,
      notes: notes,
      isFlagged: isFlagged,
      dueDate: dueDate,
      priority: priority
    )
  }

  private static func parseReminderDueDate(_ rawValue: String) throws -> InstantTimestamp {
    if let timestamp = parseInstantTimestamp(rawValue) {
      return timestamp
    }

    throw CLIError("Invalid due date '\(rawValue)'. Use YYYY-MM-DD, ISO-8601, or epoch milliseconds.", exitCode: 64)
  }

  private static func formatReminderDueDate(_ timestamp: InstantTimestamp) -> String {
    let date = Date(timeIntervalSince1970: Double(timestamp.milliseconds) / 1000)
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let components = calendar.dateComponents([.year, .month, .day], from: date)
    return String(
      format: "%04d-%02d-%02d",
      components.year ?? 0,
      components.month ?? 0,
      components.day ?? 0
    )
  }

  private static func escapedHumanValue(_ value: String) -> String {
    value
      .replacingOccurrences(of: "\\", with: "\\\\")
      .replacingOccurrences(of: "\n", with: "\\n")
      .replacingOccurrences(of: "\"", with: "\\\"")
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
    CLIOutboxUsage.outbox
  }

  private static var authUsage: String {
    CLIAuthUsage.auth
  }

  private static var appUsage: String {
    CLIAppUsage.app
  }

  private static var syncUsage: String {
    CLISyncUsage.sync
  }

  private static var connectionUsage: String {
    CLIConnectionUsage.connection
  }

  private static var roomsUsage: String {
    CLIRoomsUsage.rooms
  }

  fileprivate static var roomPresenceUsage: String {
    CLIRoomsUsage.presence
  }

  fileprivate static var roomTopicsUsage: String {
    CLIRoomsUsage.topics
  }

  fileprivate static var filesUsage: String {
    CLIFilesUsage.files
  }

  fileprivate static var streamsUsage: String {
    CLIStreamsUsage.streams
  }

  fileprivate static var sharesUsage: String {
    CLISharesUsage.shares
  }

  private static var validationUsage: String {
    CLIValidationUsage.validation
  }

  private static var queryUsage: String {
    CLIQueryUsage.query
  }

  private static var cacheUsage: String {
    CLICacheUsage.cache
  }

  private static var localIDUsage: String {
    CLILocalIDUsage.localID
  }

  private static var adminUsage: String {
    CLIAdminUsage.admin
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

  private static func firstAdminMergeJSONAfterValidTransactHead(
    arguments: [String]
  ) -> String? {
    var arguments = arguments
    guard let command = arguments.popFirstArgument(),
      command == "transact" || command == "tx",
      let namespace = arguments.popFirstArgument()?.trimmingCharacters(in: .whitespacesAndNewlines),
      let entityID = arguments.popFirstArgument()?.trimmingCharacters(in: .whitespacesAndNewlines),
      isValidAdminPathComponent(namespace),
      !entityID.isEmpty
    else {
      return nil
    }

    var sawTransactionID = false
    while let option = arguments.popFirstArgument() {
      switch option {
      case "--merge":
        return arguments.popFirstArgument()

      case "--transaction-id":
        guard !sawTransactionID,
          let value = arguments.popFirstArgument()?.trimmingCharacters(in: .whitespacesAndNewlines),
          !value.isEmpty
        else {
          return nil
        }
        sawTransactionID = true

      default:
        return nil
      }
    }
    return nil
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
    Usage: instant-swift-data examples <todos|todo-links|reminders|sync-ups>
      instant-swift-data examples todos <add|seed|list|watch|complete|update|delete|reset|refresh>
      instant-swift-data examples todo-links <seed|list|nested|unlink> [--json|--jsonl]
      instant-swift-data examples reminders <seed|list|stats|tags|list-tags|search|add-list|rename-list|delete-list|add|update|complete|delete|delete-completed|add-tag|remove-tag> [--json|--jsonl]
      instant-swift-data examples sync-ups <seed|list|detail|add|edit|add-attendee|record|delete|delete-attendee|delete-meeting> [--json|--jsonl]
    """
  }

  private static var syncUpsUsage: String {
    """
    Usage: instant-swift-data examples sync-ups <seed|list|detail|add|edit|add-attendee|record|delete|delete-attendee|delete-meeting>
      instant-swift-data examples sync-ups seed [--json|--jsonl]
      instant-swift-data examples sync-ups list [--refresh] [--sync-up-id id] [--json|--jsonl]
      instant-swift-data examples sync-ups detail <sync-up-id> [--json|--jsonl]
      instant-swift-data examples sync-ups add "title" --attendee "name" [--seconds n] [--theme theme] [--json|--jsonl]
      instant-swift-data examples sync-ups edit <sync-up-id> [--title title] [--seconds n] [--theme theme] [--attendee name ...] [--json|--jsonl]
      instant-swift-data examples sync-ups add-attendee <sync-up-id> "name" [--json|--jsonl]
      instant-swift-data examples sync-ups record <sync-up-id> [--transcript] "transcript" [--json|--jsonl]
      instant-swift-data examples sync-ups delete <sync-up-id> [--json|--jsonl]
      instant-swift-data examples sync-ups delete-attendee <attendee-id> [--json|--jsonl]
      instant-swift-data examples sync-ups delete-meeting <meeting-id> [--json|--jsonl]
    """
  }

  private static var syncUpThemeList: String {
    SyncUpTheme.allCases.map(\.rawValue).joined(separator: ", ")
  }

  private static var remindersUsage: String {
    """
    Usage: instant-swift-data examples reminders <seed|list|stats|tags|list-tags|search|add-list|rename-list|delete-list|add|update|complete|delete|delete-completed|add-tag|remove-tag>
      instant-swift-data examples reminders seed [--json|--jsonl]
      instant-swift-data examples reminders list [--refresh] [--list-id id] [--completed true|false] [--flagged|--unflagged] [--scheduled] [--today] [--priority \(reminderPriorityList)] [--json|--jsonl]
      instant-swift-data examples reminders stats [--json|--jsonl]
      instant-swift-data examples reminders tags [--json|--jsonl]
      instant-swift-data examples reminders list-tags [--json|--jsonl]
      instant-swift-data examples reminders search "text" [--list-id id] [--tag tag] [--include-completed] [--flagged|--unflagged] [--scheduled] [--today] [--priority \(reminderPriorityList)] [--json|--jsonl]
      instant-swift-data examples reminders add-list "list title" [--json|--jsonl]
      instant-swift-data examples reminders rename-list <list-id> "new title" [--json|--jsonl]
      instant-swift-data examples reminders delete-list <list-id> [--json|--jsonl]
      instant-swift-data examples reminders add <list-id> "reminder title" [--notes text] [--due-date date] [--priority \(reminderPriorityList)] [--flagged] [--json|--jsonl]
      instant-swift-data examples reminders update <reminder-id> ["new title"] [--notes text] [--due-date date|--clear-due-date] [--priority \(reminderPriorityList)|none|--clear-priority] [--flagged|--unflagged] [--json|--jsonl]
      instant-swift-data examples reminders complete <reminder-id> [--json|--jsonl]
      instant-swift-data examples reminders delete <reminder-id> [--json|--jsonl]
      instant-swift-data examples reminders delete-completed [--list-id id] [--json|--jsonl]
      instant-swift-data examples reminders add-tag <reminder-id> <tag> [--json|--jsonl]
      instant-swift-data examples reminders remove-tag <reminder-id> <tag> [--json|--jsonl]
    """
  }

  private static var remindersSearchUsage: String {
    "Usage: instant-swift-data examples reminders search \"text\" [--list-id id] [--tag tag] [--include-completed] [--flagged|--unflagged] [--scheduled] [--today] [--priority \(reminderPriorityList)] [--json|--jsonl]"
  }

  private static var remindersListUsage: String {
    "Usage: instant-swift-data examples reminders list [--refresh] [--list-id id] [--completed true|false] [--flagged|--unflagged] [--scheduled] [--today] [--priority \(reminderPriorityList)] [--json|--jsonl]"
  }

  private static var remindersAddUsage: String {
    "Usage: instant-swift-data examples reminders add <list-id> \"reminder title\" [--notes text] [--due-date YYYY-MM-DD|ISO-8601|milliseconds] [--priority \(reminderPriorityList)] [--flagged] [--json|--jsonl]"
  }

  private static var remindersUpdateUsage: String {
    "Usage: instant-swift-data examples reminders update <reminder-id> [\"new title\"] [--notes text] [--due-date YYYY-MM-DD|ISO-8601|milliseconds] [--clear-due-date] [--priority \(reminderPriorityList)|none] [--clear-priority] [--flagged|--unflagged] [--json|--jsonl]"
  }

  private static var reminderPriorityList: String {
    ReminderPriority.allCases.map(\.rawValue).joined(separator: "|")
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

  fileprivate static func parseLastJSONValue(
    _ strings: [String],
    operation: String,
    usage: String
  ) throws -> JSONValue {
    guard !strings.isEmpty else {
      throw CLIError(usage, exitCode: 64)
    }
    var value: JSONValue?
    for string in strings {
      value = try parseJSONValue(string, operation: operation)
    }
    guard let value else {
      throw CLIError(usage, exitCode: 64)
    }
    return value
  }

  fileprivate static func parseLastJSONObject(
    _ strings: [String],
    operation: String,
    usage: String
  ) throws -> [String: JSONValue] {
    guard !strings.isEmpty else {
      throw CLIError(usage, exitCode: 64)
    }
    var values: [String: JSONValue]?
    for string in strings {
      values = try parseJSONObject(string, operation: operation)
    }
    guard let values else {
      throw CLIError(usage, exitCode: 64)
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

private func parseInstantTimestamp(_ rawValue: String) -> InstantTimestamp? {
  let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
  if let milliseconds = Int64(value) {
    return InstantTimestamp(milliseconds: milliseconds)
  }

  let iso8601 = ISO8601DateFormatter()
  iso8601.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
  if let date = iso8601.date(from: value) {
    return InstantTimestamp(milliseconds: Int64((date.timeIntervalSince1970 * 1000).rounded()))
  }
  iso8601.formatOptions = [.withInternetDateTime]
  if let date = iso8601.date(from: value) {
    return InstantTimestamp(milliseconds: Int64((date.timeIntervalSince1970 * 1000).rounded()))
  }

  let dateFormatter = DateFormatter()
  dateFormatter.calendar = Calendar(identifier: .gregorian)
  dateFormatter.locale = Locale(identifier: "en_US_POSIX")
  dateFormatter.timeZone = TimeZone(secondsFromGMT: 0)
  dateFormatter.dateFormat = "yyyy-MM-dd"
  if let date = dateFormatter.date(from: value) {
    return InstantTimestamp(milliseconds: Int64((date.timeIntervalSince1970 * 1000).rounded()))
  }

  return nil
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
    let fixedNow = try environment["INSTANT_SWIFT_DATA_NOW"].map { rawValue -> InstantTimestamp in
      guard let timestamp = parseInstantTimestamp(rawValue) else {
        throw CLIError(
          "Invalid INSTANT_SWIFT_DATA_NOW '\(rawValue)'. Use YYYY-MM-DD, ISO-8601, or epoch milliseconds.",
          exitCode: 64
        )
      }
      return timestamp
    }
    let now: @Sendable () -> InstantTimestamp = {
      if let fixedNow {
        return fixedNow
      }
      return InstantTimestamp(milliseconds: Int64((Date().timeIntervalSince1970 * 1000).rounded()))
    }
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: resolved.appID,
        apiURI: apiURI,
        websocketURI: websocketURI,
        persistenceURL: cacheURL,
        initialAttributes: initialAttributes,
        now: now
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

  init(_ outputMode: CLIOutputMode) {
    switch outputMode {
    case .human:
      self = .human
    case .json:
      self = .json
    case .jsonl:
      self = .jsonl
    }
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

private struct RemindersOutput: Codable, Sendable {
  var appID: String
  var cachePath: String
  var event: String
  var changedID: String?
  var transport: String
  var listQueryID: String
  var reminderQueryID: String
  var tagQueryID: String
  var listCacheKey: String
  var reminderCacheKey: String
  var tagCacheKey: String
  var pendingMutationCount: Int
  var lists: [RemindersListSummary]
  var stats: RemindersStats
  var reminders: [ReminderRecord]
  var tags: [ReminderTagRecord]
  var reminderTags: [ReminderTagLinkRecord]
}

private struct RemindersSearchOptions: Sendable {
  var text: String
  var listID: String?
  var tagID: String?
  var includeCompleted: Bool
  var flagged: Bool?
  var scheduled: Bool
  var today: Bool
  var priority: ReminderPriority?
}

private struct RemindersListOptions: Sendable {
  var event: String
  var listID: String?
  var includeCompleted: Bool
  var flagged: Bool?
  var scheduled: Bool
  var today: Bool
  var priority: ReminderPriority?
}

private struct ReminderAddOptions: Sendable {
  var title: String
  var notes: String
  var isFlagged: Bool
  var dueDate: InstantTimestamp?
  var priority: ReminderPriority?
}

private struct ReminderUpdateOptions: Sendable {
  var title: String
  var notes: String
  var isFlagged: Bool
  var dueDate: InstantTimestamp?
  var priority: ReminderPriority?
}

private struct SyncUpsOutput: Codable, Sendable {
  var appID: String
  var cachePath: String
  var event: String
  var changedID: String?
  var transport: String
  var syncUpQueryID: String
  var attendeeQueryID: String
  var meetingQueryID: String
  var syncUpCacheKey: String
  var attendeeCacheKey: String
  var meetingCacheKey: String
  var pendingMutationCount: Int
  var syncUps: [SyncUpSummary]
  var attendees: [SyncUpAttendeeRecord]
  var meetings: [SyncUpMeetingRecord]
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
}

private struct AdminTransactOptions: Sendable {
  var namespace: String
  var entityID: String
  var fields: [AdminFieldValue]
  var attributes: [InstantAttribute]
  var query: InstantQueryPlan
  var transactionID: String?

  static func parse(invocation: CLIAdminTransactInvocation) throws -> Self {
    let usage = CLIAdminUsage.transact
    let namespace = invocation.namespace
    let merge = try InstantSwiftDataCLI.parseAdminMergeObject(
      invocation.mergeJSON,
      usage: usage
    )

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
      entityID: invocation.entityID,
      fields: fields,
      attributes: attributes,
      query: InstantSwiftDataCLI.adminQueryOptions(namespace: namespace).query,
      transactionID: invocation.transactionID
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

private struct FileUploadProgressOutput: Codable, Sendable {
  var appID: String
  var cachePath: String
  var event: String
  var transport: String
  var index: Int
  var operationID: String
  var fileID: String
  var fileName: String
  var contentType: String?
  var state: InstantStorageOperationState
  var completedByteCount: Int64
  var totalByteCount: Int64
  var progress: Double
  var file: InstantStoredFile?
  var errorMessage: String?
  var updatedAt: InstantTimestamp
}

private struct FileUploadProgressSummaryOutput: Codable, Sendable {
  var appID: String
  var cachePath: String
  var event: String
  var transport: String
  var emittedEventCount: Int
  var finalState: InstantStorageOperationState
  var events: [FileUploadProgressOutput]
}

private struct FileContentsOutput: Codable, Sendable {
  var appID: String
  var cachePath: String
  var event: String
  var transport: String
  var file: InstantStoredFile
  var byteCount: Int64
  var base64Content: String
  var utf8Content: String?
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

private struct LocalIntegrationValidationOutput: Codable, Sendable {
  var appID: String
  var cachePath: String
  var event: String
  var transport: String
  var ok: Bool
  var evidenceCount: Int
  var events: [String]
  var authUserID: String?
  var roomMemberCount: Int
  var topicMessageCount: Int
  var fileCount: Int
  var streamChunkCount: Int
  var activeShareCount: Int
  var revokedShareCount: Int
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

private extension CLIRoomIdentifier {
  var instantRoomHandle: InstantRoomHandle {
    InstantRoomHandle(type: type, id: id)
  }
}

private struct ScaffoldOptions: Sendable {
  var example: String
  var outputDirectory: String
  var force: Bool

  init(invocation: CLIScaffoldInvocation) {
    self.example = invocation.example
    self.outputDirectory = invocation.outputDirectory
    self.force = invocation.force
  }
}

private struct BenchmarkOptions: Sendable {
  var suite: String
  var iterations: Int
  var appID: String

  static func parse(arguments: [String]) throws -> Self {
    var appID = ProcessInfo.processInfo.environment["INSTANT_APP_ID"]?
      .trimmingCharacters(in: .whitespacesAndNewlines) ?? "local-demo"
    if appID.isEmpty {
      appID = "local-demo"
    }

    let invocation: CLIBenchmarkInvocation
    do {
      invocation = try CLIBenchmarkArguments.parse(
        arguments,
        defaultAppID: appID,
        allowsOutputFlags: false,
        usageCommand: "instant-swift-data benchmark"
      )
    } catch let error as CLIBenchmarkArgumentError {
      guard error.exitCode != 0 else {
        throw CLIHelp(error.description)
      }
      throw CLIError(error.description, exitCode: error.exitCode)
    }

    guard invocation.suite == InstantSwiftDataLocalBenchmarks.localTodosSuite else {
      throw CLIError("Unsupported benchmark suite: \(invocation.suite). \(usage)", exitCode: 64)
    }

    return Self(
      suite: invocation.suite,
      iterations: invocation.iterations,
      appID: invocation.appID
    )
  }

  private static var usage: String {
    """
    Usage: instant-swift-data benchmark [--suite local-todos] [--iterations n] [--app-id id] [--json|--jsonl]
    """
  }
}

private struct GenerateOptions: Sendable {
  var example: String
  var outputPath: String?

  init(invocation: CLIGenerateArtifactInvocation) {
    self.example = invocation.example
    self.outputPath = invocation.outputPath
  }
}

private struct SchemaVerifyOptions: Sendable {
  var example: String
  var inputPath: String

  init(invocation: CLIVerifyArtifactInvocation) {
    self.example = invocation.example
    self.inputPath = invocation.inputPath
  }
}

private struct PermissionsVerifyOptions: Sendable {
  var example: String
  var inputPath: String

  init(invocation: CLIVerifyArtifactInvocation) {
    self.example = invocation.example
    self.inputPath = invocation.inputPath
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

private struct CLIHelp: Error, CustomStringConvertible {
  var description: String

  init(_ description: String) {
    self.description = description
  }
}

private extension Array {
  mutating func popFirstArgument() -> Element? {
    guard !isEmpty else { return nil }
    return removeFirst()
  }
}
