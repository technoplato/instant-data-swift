import Foundation
import InstantSwiftDataCLIParsing
import InstantSwiftData
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
      let example = try schemaExample(named: options.example)
      try verifySchema(options: options, example: example, output: output)

    case let .generate(generate):
      let options = GenerateOptions(invocation: generate)
      let example = try schemaExample(named: options.example)

      try printGeneratedArtifact(
        try TypeScriptSchemaPrinter().printSchema(example.schema),
        kind: "schema",
        fileName: "instant.schema.ts",
        example: example.name,
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
      let example = try schemaExample(named: options.example)
      try verifyPermissions(options: options, example: example, output: output)

    case let .generate(generate):
      let options = GenerateOptions(invocation: generate)
      let example = try schemaExample(named: options.example)

      try printGeneratedArtifact(
        try TypeScriptPermissionsPrinter().printPermissions(example.permissions),
        kind: "permissions",
        fileName: "instant.perms.ts",
        example: example.name,
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

    case .reminders:
      let appID = validationAppID()
      do {
        let result = try await InstantSwiftDataRemindersValidation.run(appID: appID)
        try printRemindersValidation(result: result, output: output)
      } catch {
        if output == .jsonl {
          try writeJSONLine(
            validationFailureRow(
              caseID: "validation.reminders",
              appID: appID,
              error: error
            )
          )
        }
        throw error
      }

    case .serverTransactionLoopback:
      let appID = validationAppID(defaultAppID: "server-transaction-loopback-validation")
      do {
        let result = try await InstantSwiftDataServerTransactionLoopbackValidation.run(
          appID: appID,
          typeScriptServerTransactionContract: try typeScriptServerTransactionContract()
        )
        try printServerTransactionLoopbackValidation(result: result, output: output)
      } catch {
        if output == .jsonl {
          try writeJSONLine(
            validationFailureRow(
              caseID: "validation.server.transaction.loopback",
              appID: appID,
              error: error
            )
          )
        }
        throw error
      }

    case .parityReport:
      let appID = validationAppID()
      try printParityCoverageReport(
        result: InstantSwiftDataParityCoverage.current,
        appID: appID,
        output: output
      )

    case .coverage:
      let appID = validationAppID()
      try printValidationCoverageSummary(
        result: InstantSwiftDataParityCoverage.current,
        appID: appID,
        output: output
      )

    case .platformAdapters:
      let appID = validationAppID()
      do {
        let result = try await InstantSwiftDataPlatformAdapterValidation.run(appID: appID)
        try printPlatformAdapterValidation(result: result, output: output)
      } catch {
        if output == .jsonl {
          try writeJSONLine(
            validationFailureRow(
              caseID: "validation.platform.adapters",
              appID: appID,
              error: error
            )
          )
        }
        throw error
      }

    case .syncUpsRecording:
      let appID = validationAppID()
      do {
        let result = try await InstantSwiftDataSyncUpsRecordingValidation.run(appID: appID)
        try printSyncUpsRecordingValidation(result: result, output: output)
      } catch {
        if output == .jsonl {
          try writeJSONLine(
            validationFailureRow(
              caseID: "validation.syncups.recording",
              appID: appID,
              error: error
            )
          )
        }
        throw error
      }

    case .typedDrafts:
      let appID = validationAppID()
      do {
        let result = try await InstantSwiftDataDraftValidation.run(appID: appID)
        try printDraftValidation(result: result, output: output)
      } catch {
        if output == .jsonl {
          try writeJSONLine(
            validationFailureRow(
              caseID: "validation.typed.drafts",
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
      if let mergeJSON = CLIAdminArguments.firstMergeJSONAfterValidTransactHead(arguments) {
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
    let invocation: CLIExamplesInvocation
    do {
      invocation = try CLIExamplesParser().parse(&input)
    } catch let error as CLIExamplesTodosArgumentError {
      throw CLIError(error.description, exitCode: error.exitCode)
    } catch let error as CLIExamplesAuthArgumentError {
      throw CLIError(error.description, exitCode: error.exitCode)
    } catch let error as CLIExamplesAppBuilderArgumentError {
      throw CLIError(error.description, exitCode: error.exitCode)
    } catch let error as CLIExamplesTodoLinksArgumentError {
      throw CLIError(error.description, exitCode: error.exitCode)
    } catch let error as CLIExamplesCountersArgumentError {
      throw CLIError(error.description, exitCode: error.exitCode)
    } catch let error as CLIExamplesChatArgumentError {
      throw CLIError(error.description, exitCode: error.exitCode)
    } catch let error as CLIExamplesMicroblogArgumentError {
      throw CLIError(error.description, exitCode: error.exitCode)
    } catch let error as CLIExamplesMobileChatArgumentError {
      throw CLIError(error.description, exitCode: error.exitCode)
    } catch let error as CLIExamplesReactionsArgumentError {
      throw CLIError(error.description, exitCode: error.exitCode)
    } catch let error as CLIExamplesTypingIndicatorArgumentError {
      throw CLIError(error.description, exitCode: error.exitCode)
    } catch let error as CLIExamplesAvatarStackArgumentError {
      throw CLIError(error.description, exitCode: error.exitCode)
    } catch let error as CLIExamplesCursorsArgumentError {
      throw CLIError(error.description, exitCode: error.exitCode)
    } catch let error as CLIExamplesStroopwafelArgumentError {
      throw CLIError(error.description, exitCode: error.exitCode)
    } catch let error as CLIExamplesMergeTileGameArgumentError {
      throw CLIError(error.description, exitCode: error.exitCode)
    } catch CLIExamplesSyncUpsArgumentError.invalidTheme {
      throw CLIError("Unknown SyncUps theme. Use one of: \(syncUpThemeList).", exitCode: 64)
    } catch let error as CLIExamplesSyncUpsArgumentError {
      throw CLIError(error.description, exitCode: error.exitCode)
    } catch let error as CLIExamplesRemindersArgumentError {
      throw CLIError(error.description, exitCode: error.exitCode)
    }
    switch invocation {
    case let .auth(leaf):
      try await runAuthRecipe(leaf: leaf, output: output)
      return

    case let .appBuilder(leaf):
      try await runAppBuilder(leaf: leaf, output: output)
      return

    case let .chat(leaf):
      try await runChat(leaf: leaf, output: output)
      return

    case let .counters(leaf):
      try await runCounters(leaf: leaf, output: output)
      return

    case let .microblog(leaf):
      try await runMicroblog(leaf: leaf, output: output)
      return

    case let .mobileChat(leaf):
      try await runMobileChat(leaf: leaf, output: output)
      return

    case let .reactions(leaf):
      try await runReactions(leaf: leaf, output: output)
      return

    case let .typingIndicator(leaf):
      try await runTypingIndicator(leaf: leaf, output: output)
      return

    case let .avatarStack(leaf):
      try await runAvatarStack(leaf: leaf, output: output)
      return

    case let .cursors(leaf):
      try await runCursors(leaf: leaf, output: output)
      return

    case let .customCursors(leaf):
      try await runCustomCursors(leaf: leaf, output: output)
      return

    case let .mergeTileGame(leaf):
      try await runMergeTileGame(leaf: leaf, output: output)
      return

    case let .stroopwafel(leaf):
      try await runStroopwafel(leaf: leaf, output: output)
      return

    case let .syncUps(leaf):
      try await runSyncUps(leaf: leaf, output: output)
      return

    case let .reminders(leaf):
      try await runReminders(leaf: leaf, output: output)
      return

    case let .todoLinks(leaf):
      try await runTodoLinks(leaf: leaf, output: output)
      return

    case let .todos(todosInvocation):
      guard let leaf = todosInvocation.leaf else {
        throw CLIError(CLIExamplesTodosUsage.todos, exitCode: 64)
      }

      try await runTodos(leaf: leaf, output: output)
      return

    case .unknown:
      throw CLIError(examplesUsage, exitCode: 64)
    }
  }

  private static func runAuthRecipe(leaf: CLIExamplesAuthLeafInvocation, output: OutputMode) async throws {
    if case let .unknown(command) = leaf {
      throw CLIError("Unknown auth recipe command: \(command)", exitCode: 64)
    }

    let context = try await CLIContext.bootstrap(initialAttributes: [])

    switch leaf {
    case let .sendCode(email):
      try await requireAuthRecipeSignedOut(context: context, operation: "send-code")
      let challenge = try await context.runtime.sendMagicCode(email: email)
      let session = try await context.runtime.authSession()
      try printAuthRecipe(
        context: context,
        event: "send-code",
        session: session,
        challenge: challenge,
        output: output
      )

    case let .verifyCode(email, code):
      try await requireAuthRecipeSignedOut(context: context, operation: "verify-code")
      let session = try await context.runtime.signInWithMagicCode(email: email, code: code)
      try printAuthRecipe(
        context: context,
        event: "verify-code",
        session: session,
        sentEmail: email,
        output: output
      )

    case .status:
      let session = try await context.runtime.authSession()
      try printAuthRecipe(context: context, event: "status", session: session, output: output)

    case let .watch(options):
      try await watchAuthRecipe(context: context, output: output, eventCount: options.eventCount)

    case let .signOut(options):
      try await context.runtime.signOut(invalidateToken: options.invalidateToken)
      try printAuthRecipe(context: context, event: "sign-out", session: nil, output: output)

    case .unknown:
      break
    }
  }

  private static func requireAuthRecipeSignedOut(
    context: CLIContext,
    operation: String
  ) async throws {
    if try await context.runtime.authSession() != nil {
      throw CLIError(
        """
        Auth recipe \(operation) is only available while signed out. Run \
        'instant-swift-data examples auth sign-out' first.
        """,
        exitCode: 65
      )
    }
  }

  private static func runAppBuilder(leaf: CLIExamplesAppBuilderLeafInvocation, output: OutputMode) async throws {
    if case let .unknown(command) = leaf {
      throw CLIError("Unknown app-builder command: \(command). \(appBuilderUsage)", exitCode: 64)
    }

    let context = try await CLIContext.bootstrap(initialAttributes: AppBuilderExample.attributes)

    switch leaf {
    case let .generate(options):
      let (session, email) = try await requireAppBuilderEmailSession(context: context)
      let buildID = context.runtime.configuration.makeID()
      let now = context.runtime.configuration.now()
      let title = AppBuilderExample.friendlyTitle(for: options.prompt)
      let platformApp = try await context.runtime.configuration.platformAppClient.createApp(
        InstantPlatformAppCreateRequest(
          title: title,
          orgID: options.orgID,
          createdAt: now,
          makeID: { buildID }
        )
      )

      let createTransactionID = context.runtime.configuration.makeID()
      try await context.runtime.transact(
        InstantStoreTransaction(
          id: createTransactionID,
          operations: AppBuilderExample.createBuildOperations(
            id: buildID,
            ownerID: session.userID,
            ownerEmail: email,
            instantAppID: platformApp.id,
            title: title,
            createdAt: now,
            transactionID: createTransactionID
          )
        ),
        createdAt: now,
        source: "cli.examples.app-builder.create"
      )

      var generationEvents = [
        AppBuilderGenerationEventOutput(
          event: "create",
          kind: nil,
          text: nil,
          codeLength: 0,
          reasoningLength: 0,
          isPreviewable: false
        )
      ]
      var code = ""
      var reasoning = ""
      let stream = try await context.runtime.configuration.appBuilderCodeGenerator.generate(
        AppBuilderGenerationRequest(
          prompt: options.prompt,
          buildID: buildID,
          instantAppID: platformApp.id
        )
      )
      for try await chunk in stream {
        switch chunk.kind {
        case .code:
          code += chunk.text
        case .reasoning:
          reasoning += chunk.text
        }
        let transactionID = context.runtime.configuration.makeID()
        let updatedAt = context.runtime.configuration.now()
        try await context.runtime.transact(
          InstantStoreTransaction(
            id: transactionID,
            operations: AppBuilderExample.updateBuildOperations(
              id: buildID,
              code: code,
              reasoning: reasoning,
              isPreviewable: false,
              updatedAt: updatedAt,
              transactionID: transactionID
            )
          ),
          createdAt: updatedAt,
          source: "cli.examples.app-builder.generate"
        )
        generationEvents.append(
          AppBuilderGenerationEventOutput(
            event: "chunk",
            kind: chunk.kind.rawValue,
            text: chunk.text,
            codeLength: code.count,
            reasoningLength: reasoning.count,
            isPreviewable: false
          )
        )
      }

      let finishTransactionID = context.runtime.configuration.makeID()
      let finishedAt = context.runtime.configuration.now()
      try await context.runtime.transact(
        InstantStoreTransaction(
          id: finishTransactionID,
          operations: AppBuilderExample.updateBuildOperations(
            id: buildID,
            code: code,
            reasoning: reasoning,
            isPreviewable: true,
            updatedAt: finishedAt,
            transactionID: finishTransactionID
          )
        ),
        createdAt: finishedAt,
        source: "cli.examples.app-builder.finish"
      )
      generationEvents.append(
        AppBuilderGenerationEventOutput(
          event: "finish",
          kind: nil,
          text: nil,
          codeLength: code.count,
          reasoningLength: reasoning.count,
          isPreviewable: true
        )
      )

      try await printAppBuilder(
        context: context,
        output: output,
        event: "generate",
        changedID: buildID,
        selectedBuildID: buildID,
        platformApp: platformApp,
        generationEvents: generationEvents
      )

    case .list:
      let (session, _) = try await requireAppBuilderEmailSession(context: context)
      try await printAppBuilder(
        context: context,
        output: output,
        event: "list",
        ownerID: session.userID
      )

    case let .show(buildID):
      _ = try await requireAppBuilderEmailSession(context: context)
      _ = try await requireAppBuilderBuild(context: context, id: buildID)
      try await printAppBuilder(
        context: context,
        output: output,
        event: "show",
        selectedBuildID: buildID
      )

    case let .append(options):
      _ = try await requireAppBuilderEmailSession(context: context)
      let build = try await requireAppBuilderBuild(context: context, id: options.buildID)
      let code = options.code.map { build.code + $0 }
      let reasoning = options.reasoning.map { (build.reasoning ?? "") + $0 }
      let transactionID = context.runtime.configuration.makeID()
      let now = context.runtime.configuration.now()
      try await context.runtime.transact(
        InstantStoreTransaction(
          id: transactionID,
          operations: AppBuilderExample.updateBuildOperations(
            id: build.id,
            code: code,
            reasoning: reasoning,
            isPreviewable: options.isPreviewable,
            updatedAt: now,
            transactionID: transactionID
          )
        ),
        createdAt: now,
        source: "cli.examples.app-builder.append"
      )
      try await printAppBuilder(
        context: context,
        output: output,
        event: "append",
        changedID: build.id,
        selectedBuildID: build.id
      )

    case let .finish(buildID):
      _ = try await requireAppBuilderEmailSession(context: context)
      _ = try await requireAppBuilderBuild(context: context, id: buildID)
      let transactionID = context.runtime.configuration.makeID()
      let now = context.runtime.configuration.now()
      try await context.runtime.transact(
        InstantStoreTransaction(
          id: transactionID,
          operations: AppBuilderExample.updateBuildOperations(
            id: buildID,
            isPreviewable: true,
            updatedAt: now,
            transactionID: transactionID
          )
        ),
        createdAt: now,
        source: "cli.examples.app-builder.finish"
      )
      try await printAppBuilder(
        context: context,
        output: output,
        event: "finish",
        changedID: buildID,
        selectedBuildID: buildID
      )

    case .reset:
      let (session, _) = try await requireAppBuilderEmailSession(context: context)
      let builds = try await currentAppBuilderBuilds(context: context, ownerID: session.userID)
      if !builds.isEmpty {
        let transactionID = context.runtime.configuration.makeID()
        let now = context.runtime.configuration.now()
        try await context.runtime.transact(
          InstantStoreTransaction(
            id: transactionID,
            operations: builds.flatMap { AppBuilderExample.deleteBuildOperations(id: $0.id) }
          ),
          createdAt: now,
          source: "cli.examples.app-builder.reset"
        )
      }
      try await printAppBuilder(
        context: context,
        output: output,
        event: "reset",
        ownerID: session.userID
      )

    case .unknown:
      preconditionFailure("Unknown app-builder commands are handled before bootstrapping.")
    }
  }

  private static func runTodos(leaf: CLIExamplesTodosLeafInvocation, output: OutputMode) async throws {
    if case let .unknown(command) = leaf {
      throw CLIError("Unknown todos command: \(command)", exitCode: 64)
    }

    let context = try await CLIContext.bootstrap()

    switch leaf {
    case .seed:
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

    case let .add(text):
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

    case let .list(list):
      let query = todoListQuery(invocation: list)
      try await printTodos(context: context, output: output, event: "list", query: query)

    case let .watch(watch):
      let options = todoWatchOptions(invocation: watch)
      try await watchTodos(context: context, output: output, options: options)

    case let .complete(todoID):
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

    case let .update(todoID, text):
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

    case let .delete(todoID):
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

    case let .refresh(refresh):
      let query = todoListQuery(invocation: refresh)
      try await printTodos(context: context, output: output, event: "refresh", query: query)

    case .unknown:
      preconditionFailure("Unknown todos commands are handled before bootstrapping.")
    }
  }

  private static func runSyncUps(
    leaf invocation: CLIExamplesSyncUpsLeafInvocation,
    output: OutputMode
  ) async throws {
    if case let .unknown(command) = invocation {
      throw CLIError("Unknown sync-ups command: \(command). \(syncUpsUsage)", exitCode: 64)
    }
    try validateSyncUpsThemeValues(in: invocation)

    let context = try await CLIContext.bootstrap(initialAttributes: SyncUpsExample.attributes)

    switch invocation {
    case .seed:
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

    case let .list(list):
      try await printSyncUps(
        context: context,
        output: output,
        event: list.event,
        syncUpID: list.syncUpID
      )

    case let .detail(syncUpID):
      try await printSyncUps(context: context, output: output, event: "detail", syncUpID: syncUpID)

    case let .add(add):
      let transactionID = context.runtime.configuration.makeID()
      let syncUpID = context.runtime.configuration.makeID()
      let now = context.runtime.configuration.now()
      var operations = SyncUpsExample.createSyncUpOperations(
        id: syncUpID,
        title: add.title,
        seconds: add.seconds,
        theme: syncUpTheme(add.theme),
        updatedAt: now,
        transactionID: transactionID
      )
      for name in add.attendeeNames {
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

    case let .update(update):
      let currentSyncUps = try SyncUpsExample.decodeSyncUps(
        (try await context.runtime.queryOnce(SyncUpsExample.syncUpsQuery)).values
      )
      guard let current = currentSyncUps.first(where: { $0.id == update.syncUpID }) else {
        throw CLIError("Sync-up not found: \(update.syncUpID)", exitCode: 66)
      }
      let transactionID = context.runtime.configuration.makeID()
      let now = context.runtime.configuration.now()
      var operations = SyncUpsExample.updateSyncUpOperations(
        id: update.syncUpID,
        title: update.title ?? current.title,
        seconds: update.seconds ?? current.seconds,
        theme: update.theme.map(syncUpTheme) ?? current.theme,
        updatedAt: now,
        transactionID: transactionID
      )
      if let replacementAttendeeNames = update.replacementAttendeeNames {
        let existingAttendees = try SyncUpsExample.decodeAttendees(
          (try await context.runtime.queryOnce(SyncUpsExample.attendeesForSyncUpQuery(update.syncUpID))).values
        )
        operations += SyncUpsExample.replaceAttendeesOperations(
          syncUpID: update.syncUpID,
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
        event: update.event,
        changedID: update.syncUpID,
        syncUpID: update.syncUpID
      )

    case let .addAttendee(syncUpID, name):
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

    case let .record(syncUpID, transcript):
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

    case let .recordDemo(syncUpID):
      let currentSyncUps = try SyncUpsExample.decodeSyncUps(
        (try await context.runtime.queryOnce(SyncUpsExample.syncUpsQuery)).values
      )
      guard let syncUp = currentSyncUps.first(where: { $0.id == syncUpID }) else {
        throw CLIError("Sync-up not found: \(syncUpID)", exitCode: 66)
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
      var model = SyncUpRecordingModel(syncUp: syncUp, attendees: currentAttendees)
      let meetingID = context.runtime.configuration.makeID()
      let transactionID = context.runtime.configuration.makeID()
      let now = context.runtime.configuration.now()
      let save = try await model.runDemo(
        meetingID: meetingID,
        date: now,
        transactionID: transactionID
      )
      try await context.runtime.transact(
        InstantStoreTransaction(
          id: transactionID,
          operations: save.operations
        ),
        createdAt: now,
        source: "cli.examples.sync-ups.record-demo"
      )
      try await printSyncUps(
        context: context,
        output: output,
        event: "record-demo",
        changedID: meetingID,
        syncUpID: syncUpID,
        recording: SyncUpRecordingSummary(model: model, save: save)
      )

    case let .delete(syncUpID):
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

    case let .deleteAttendee(attendeeID):
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

    case let .deleteMeeting(meetingID):
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

    case .unknown:
      preconditionFailure("Unknown sync-ups commands are handled before bootstrapping.")
    }
  }

  private static func runReminders(
    leaf invocation: CLIExamplesRemindersLeafInvocation,
    output: OutputMode
  ) async throws {
    if case let .unknown(command) = invocation {
      throw CLIError("Unknown reminders command: \(command). \(remindersUsage)", exitCode: 64)
    }

    try validateReminderRawValues(in: invocation)

    let context = try await CLIContext.bootstrap(initialAttributes: ReminderExample.attributes)

    switch invocation {
    case .seed:
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

    case let .list(options):
      let query = ReminderExample.remindersFilterQuery(
        listID: options.listID,
        includeCompleted: options.includeCompleted,
        flagged: options.flagged,
        scheduled: options.scheduled,
        today: options.today ? context.runtime.configuration.now() : nil,
        priority: try reminderPriority(options.priorityRawValue, usage: remindersListUsage)
      )
      try await printReminders(
        context: context,
        output: output,
        event: options.event,
        listID: options.listID,
        remindersQuery: query
      )

    case .stats:
      try await printReminders(context: context, output: output, event: "stats")

    case .tags:
      try await printReminders(context: context, output: output, event: "tags")

    case let .addList(title):
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

    case let .renameList(listID, title):
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

    case let .add(options):
      let existingReminders = try ReminderExample.decodeReminders(
        (try await context.runtime.queryOnce(ReminderExample.remindersForListQuery(options.listID))).values
      )
      let dueDate = try reminderDueDate(options.dueDateRawValue)
      let priority = try reminderPriority(options.priorityRawValue, usage: remindersAddUsage)
      let transactionID = context.runtime.configuration.makeID()
      let reminderID = context.runtime.configuration.makeID()
      let now = context.runtime.configuration.now()
      try await context.runtime.transact(
        InstantStoreTransaction(
          id: transactionID,
          operations: ReminderExample.createReminderOperations(
            id: reminderID,
            listID: options.listID,
            title: options.title,
            notes: options.notes,
            isFlagged: options.isFlagged,
            dueDate: dueDate,
            priority: priority,
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
        listID: options.listID
      )

    case let .update(options):
      let currentReminders = try ReminderExample.decodeReminders(
        (try await context.runtime.queryOnce(ReminderExample.remindersQuery)).values
      )
      guard let reminder = currentReminders.first(where: { $0.id == options.reminderID }) else {
        throw CLIError("Reminder not found: \(options.reminderID)", exitCode: 66)
      }
      let dueDate: InstantTimestamp?
      if options.clearsDueDate {
        dueDate = nil
      } else if let rawDueDate = options.dueDateRawValue {
        dueDate = try parseReminderDueDate(rawDueDate)
      } else {
        dueDate = reminder.dueDate
      }
      let priority: ReminderPriority?
      if options.clearsPriority {
        priority = nil
      } else if let rawPriority = options.priorityRawValue {
        priority = try reminderPriority(
          rawPriority,
          usage: remindersUpdateUsage,
          allowsNone: true
        )
      } else {
        priority = reminder.priority
      }
      let transactionID = context.runtime.configuration.makeID()
      let now = context.runtime.configuration.now()
      try await context.runtime.transact(
        InstantStoreTransaction(
          id: transactionID,
          operations: ReminderExample.updateReminderDetailsOperations(
            id: options.reminderID,
            listID: reminder.remindersListID,
            title: options.title ?? reminder.title,
            notes: options.notes ?? reminder.notes,
            isFlagged: options.isFlagged ?? reminder.isFlagged,
            dueDate: dueDate,
            priority: priority,
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
        changedID: options.reminderID,
        listID: reminder.remindersListID
      )

    case let .complete(reminderID):
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

    case let .delete(reminderID):
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

    case let .deleteCompleted(listID):
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

    case let .deleteList(listID):
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

    case let .addTag(reminderID, rawTag):
      let tagID = try normalizedReminderTag(rawTag, usage: CLIExamplesRemindersUsage.addTag)
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

    case let .removeTag(reminderID, rawTag):
      let tagID = try normalizedReminderTag(rawTag, usage: CLIExamplesRemindersUsage.removeTag)
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

    case let .search(options):
      let tagID = try normalizedReminderTagIfPresent(options.rawTag, usage: remindersSearchUsage)
      let query = ReminderExample.remindersSearchQuery(
        text: options.text,
        listID: options.listID,
        tagID: tagID,
        includeCompleted: options.includeCompleted,
        flagged: options.flagged,
        scheduled: options.scheduled,
        today: options.today ? context.runtime.configuration.now() : nil,
        priority: try reminderPriority(options.priorityRawValue, usage: remindersSearchUsage)
      )
      try await printReminders(
        context: context,
        output: output,
        event: "search",
        listID: options.listID,
        remindersQuery: query
      )

    case .unknown:
      preconditionFailure("Unknown reminders commands are handled before bootstrapping.")
    }
  }

  private static func runTodoLinks(leaf: CLIExamplesTodoLinksLeafInvocation, output: OutputMode) async throws {
    if case let .unknown(command) = leaf {
      throw CLIError("Unknown todo-links command: \(command). \(todoLinksUsage)", exitCode: 64)
    }

    let context = try await CLIContext.bootstrap(initialAttributes: TodoProjectExample.attributes)

    switch leaf {
    case .seed:
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

    case .list:
      try await printTodoLinks(context: context, output: output, event: "list")

    case .nested:
      try await printTodoLinkSnapshots(context: context, output: output, event: "nested")

    case .unlink:
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

    case .unknown:
      preconditionFailure("Unknown todo-links commands are handled before bootstrapping.")
    }
  }

  private static func runCounters(leaf: CLIExamplesCountersLeafInvocation, output: OutputMode) async throws {
    if case let .unknown(command) = leaf {
      throw CLIError("Unknown counters command: \(command). \(countersUsage)", exitCode: 64)
    }

    let context = try await CLIContext.bootstrap(initialAttributes: CounterExample.attributes)

    switch leaf {
    case .seed:
      let transactionID = context.runtime.configuration.makeID()
      let now = context.runtime.configuration.now()
      let firstID = try await context.runtime.localID(named: CounterExample.firstSeedIDName)
      let secondID = try await context.runtime.localID(named: CounterExample.secondSeedIDName)
      try await context.runtime.transact(
        InstantStoreTransaction(
          id: transactionID,
          operations: CounterExample.upsertOperations(
            id: firstID,
            count: 24,
            createdAt: now,
            transactionID: transactionID
          ) + CounterExample.upsertOperations(
            id: secondID,
            count: 1_729,
            createdAt: InstantTimestamp(milliseconds: now.milliseconds + 1),
            transactionID: transactionID
          )
        ),
        createdAt: now,
        source: "cli.examples.counters.seed"
      )
      try await printCounters(context: context, output: output, event: "seed")

    case let .add(count):
      let transactionID = context.runtime.configuration.makeID()
      let counterID = context.runtime.configuration.makeID()
      let now = context.runtime.configuration.now()
      try await context.runtime.transact(
        InstantStoreTransaction(
          id: transactionID,
          operations: CounterExample.createOperations(
            id: counterID,
            count: count,
            createdAt: now,
            transactionID: transactionID
          )
        ),
        createdAt: now,
        source: "cli.examples.counters.add"
      )
      try await printCounters(context: context, output: output, event: "add", changedID: counterID)

    case .list:
      try await printCounters(context: context, output: output, event: "list")

    case let .increment(counterID):
      let counter = try await requireCounter(context: context, id: counterID)
      let transactionID = context.runtime.configuration.makeID()
      let now = context.runtime.configuration.now()
      try await context.runtime.transact(
        InstantStoreTransaction(
          id: transactionID,
          operations: CounterExample.updateCountOperations(
            id: counterID,
            count: counter.count + 1,
            updatedAt: now,
            transactionID: transactionID
          )
        ),
        createdAt: now,
        source: "cli.examples.counters.increment"
      )
      try await printCounters(
        context: context,
        output: output,
        event: "increment",
        changedID: counterID
      )

    case let .decrement(counterID):
      let counter = try await requireCounter(context: context, id: counterID)
      let transactionID = context.runtime.configuration.makeID()
      let now = context.runtime.configuration.now()
      try await context.runtime.transact(
        InstantStoreTransaction(
          id: transactionID,
          operations: CounterExample.updateCountOperations(
            id: counterID,
            count: counter.count - 1,
            updatedAt: now,
            transactionID: transactionID
          )
        ),
        createdAt: now,
        source: "cli.examples.counters.decrement"
      )
      try await printCounters(
        context: context,
        output: output,
        event: "decrement",
        changedID: counterID
      )

    case let .delete(counterID):
      _ = try await requireCounter(context: context, id: counterID)
      let transactionID = context.runtime.configuration.makeID()
      let now = context.runtime.configuration.now()
      try await context.runtime.transact(
        InstantStoreTransaction(
          id: transactionID,
          operations: CounterExample.deleteOperations(id: counterID)
        ),
        createdAt: now,
        source: "cli.examples.counters.delete"
      )
      try await printCounters(context: context, output: output, event: "delete", changedID: counterID)

    case .unknown:
      preconditionFailure("Unknown counters commands are handled before bootstrapping.")
    }
  }

  private static func runChat(
    leaf invocation: CLIExamplesChatLeafInvocation,
    output: OutputMode
  ) async throws {
    if case let .unknown(command) = invocation {
      throw CLIError("Unknown chat command: \(command). \(chatUsage)", exitCode: 64)
    }

    let context = try await CLIContext.bootstrap(initialAttributes: ChatExample.attributes)

    switch invocation {
    case .seed:
      let transactionID = context.runtime.configuration.makeID()
      let now = context.runtime.configuration.now()
      let generalChannelID = try await context.runtime.localID(
        named: ChatExample.generalChannelIDName
      )
      let randomChannelID = try await context.runtime.localID(
        named: ChatExample.randomChannelIDName
      )
      let welcomeMessageID = try await context.runtime.localID(
        named: ChatExample.welcomeMessageIDName
      )
      let randomMessageID = try await context.runtime.localID(
        named: ChatExample.randomMessageIDName
      )
      try await context.runtime.transact(
        InstantStoreTransaction(
          id: transactionID,
          operations: ChatExample.seedOperations(
            generalChannelID: generalChannelID,
            randomChannelID: randomChannelID,
            welcomeMessageID: welcomeMessageID,
            randomMessageID: randomMessageID,
            createdAt: now,
            transactionID: transactionID
          )
        ),
        createdAt: now,
        source: "cli.examples.chat.seed"
      )
      try await printChat(context: context, output: output, event: "seed")

    case .channels:
      try await printChat(context: context, output: output, event: "channels")

    case let .messages(channelID):
      if let channelID {
        _ = try await requireChatChannel(context: context, id: channelID)
      }
      try await printChat(
        context: context,
        output: output,
        event: "messages",
        selectedChannelID: channelID
      )

    case let .post(post):
      _ = try await requireChatChannel(context: context, id: post.channelID)
      let session = try await currentOrGuestChatSession(context: context)
      let messageID = context.runtime.configuration.makeID()
      let transactionID = context.runtime.configuration.makeID()
      let now = context.runtime.configuration.now()
      try await context.runtime.transact(
        InstantStoreTransaction(
          id: transactionID,
          operations: ChatExample.createMessageOperations(
            id: messageID,
            channelID: post.channelID,
            text: post.text,
            authorName: post.authorName ?? (session.isGuest ? "Guest" : session.userID),
            authorUserID: session.userID,
            createdAt: now,
            transactionID: transactionID
          )
        ),
        createdAt: now,
        source: "cli.examples.chat.post"
      )
      try await printChat(
        context: context,
        output: output,
        event: "post",
        changedID: messageID,
        selectedChannelID: post.channelID
      )

    case .reset:
      let channels = try await currentChatChannels(context: context)
      let messages = try await currentChatMessages(context: context)
      let operations =
        messages.flatMap { ChatExample.deleteMessageOperations(id: $0.id) }
        + channels.flatMap { ChatExample.deleteChannelOperations(id: $0.id) }
      if !operations.isEmpty {
        let transactionID = context.runtime.configuration.makeID()
        let now = context.runtime.configuration.now()
        try await context.runtime.transact(
          InstantStoreTransaction(id: transactionID, operations: operations),
          createdAt: now,
          source: "cli.examples.chat.reset"
        )
      }
      try await printChat(context: context, output: output, event: "reset")

    case .unknown:
      preconditionFailure("Unknown chat commands are handled before bootstrapping.")
    }
  }

  private static func runMicroblog(
    leaf invocation: CLIExamplesMicroblogLeafInvocation,
    output: OutputMode
  ) async throws {
    if case let .unknown(command) = invocation {
      throw CLIError("Unknown microblog command: \(command). \(microblogUsage)", exitCode: 64)
    }

    let context = try await CLIContext.bootstrap(initialAttributes: MicroblogExample.attributes)

    switch invocation {
    case .seed:
      let transactionID = context.runtime.configuration.makeID()
      let now = context.runtime.configuration.now()
      try await context.runtime.transact(
        InstantStoreTransaction(
          id: transactionID,
          operations: MicroblogExample.seedOperations(
            ids: try await microblogSeedIDs(context: context),
            baseTimestamp: now,
            transactionID: transactionID
          )
        ),
        createdAt: now,
        source: "cli.examples.microblog.seed"
      )
      try await printMicroblog(context: context, output: output, event: "seed")

    case .feed:
      try await printMicroblog(context: context, output: output, event: "feed")

    case .profiles:
      try await printMicroblog(context: context, output: output, event: "profiles")

    case let .profile(userID):
      let selectedUserID = try await selectedMicroblogUserID(
        context: context,
        explicitUserID: userID
      )
      let selectedProfile = try await requireMicroblogProfile(
        context: context,
        userID: selectedUserID
      )
      try await printMicroblog(
        context: context,
        output: output,
        event: "profile",
        selectedUserID: selectedUserID,
        selectedProfile: selectedProfile
      )

    case let .setupProfile(displayName, rawHandle):
      let session = try await requireMicroblogAuthSession(
        context: context,
        operation: "set up a profile"
      )
      let transactionID = context.runtime.configuration.makeID()
      let now = context.runtime.configuration.now()
      try await context.runtime.transact(
        InstantStoreTransaction(
          id: transactionID,
          operations: MicroblogExample.createProfileOperations(
            userID: session.userID,
            displayName: displayName,
            handle: normalizedMicroblogHandle(rawHandle),
            transactionID: transactionID,
            updatedAt: now
          )
        ),
        createdAt: now,
        source: "cli.examples.microblog.setup-profile"
      )
      try await printMicroblog(
        context: context,
        output: output,
        event: "setup-profile",
        changedID: session.userID,
        selectedUserID: session.userID
      )

    case let .post(post):
      let profile = try await requireCurrentMicroblogProfile(context: context)
      let postID = context.runtime.configuration.makeID()
      let transactionID = context.runtime.configuration.makeID()
      let now = context.runtime.configuration.now()
      try await context.runtime.transact(
        InstantStoreTransaction(
          id: transactionID,
          operations: MicroblogExample.createPostOperations(
            id: postID,
            authorProfileID: profile.id,
            color: post.color,
            content: post.content,
            timestamp: now,
            transactionID: transactionID
          )
        ),
        createdAt: now,
        source: "cli.examples.microblog.post"
      )
      try await printMicroblog(
        context: context,
        output: output,
        event: "post",
        changedID: postID,
        selectedUserID: profile.userID,
        selectedPostID: postID
      )

    case let .like(postID):
      let profile = try await requireCurrentMicroblogProfile(context: context)
      _ = try await requireMicroblogPost(context: context, id: postID)
      if let existing = try await currentMicroblogLikes(
        context: context,
        query: MicroblogExample.likesForPostQuery(postID)
      )
      .first(where: { $0.userID == profile.id }) {
        try await printMicroblog(
          context: context,
          output: output,
          event: "like",
          changedID: existing.id,
          selectedUserID: profile.userID,
          selectedPostID: postID
        )
      } else {
        let likeID = context.runtime.configuration.makeID()
        let transactionID = context.runtime.configuration.makeID()
        let now = context.runtime.configuration.now()
        try await context.runtime.transact(
          InstantStoreTransaction(
            id: transactionID,
            operations: MicroblogExample.createLikeOperations(
              id: likeID,
              userID: profile.id,
              postID: postID,
              transactionID: transactionID,
              updatedAt: now
            )
          ),
          createdAt: now,
          source: "cli.examples.microblog.like"
        )
        try await printMicroblog(
          context: context,
          output: output,
          event: "like",
          changedID: likeID,
          selectedUserID: profile.userID,
          selectedPostID: postID
        )
      }

    case let .unlike(postID):
      let profile = try await requireCurrentMicroblogProfile(context: context)
      _ = try await requireMicroblogPost(context: context, id: postID)
      let like = try await requireMicroblogLike(
        context: context,
        postID: postID,
        userID: profile.id
      )
      let transactionID = context.runtime.configuration.makeID()
      let now = context.runtime.configuration.now()
      try await context.runtime.transact(
        InstantStoreTransaction(
          id: transactionID,
          operations: MicroblogExample.deleteLikeOperations(id: like.id)
        ),
        createdAt: now,
        source: "cli.examples.microblog.unlike"
      )
      try await printMicroblog(
        context: context,
        output: output,
        event: "unlike",
        changedID: like.id,
        selectedUserID: profile.userID,
        selectedPostID: postID
      )

    case let .deletePost(postID):
      let profile = try await requireCurrentMicroblogProfile(context: context)
      let post = try await requireMicroblogPost(context: context, id: postID)
      guard post.authorProfileID == profile.id else {
        throw CLIError(
          "Microblog post \(postID) is owned by profile \(post.authorProfileID).",
          exitCode: 77
        )
      }
      let transactionID = context.runtime.configuration.makeID()
      let now = context.runtime.configuration.now()
      try await context.runtime.transact(
        InstantStoreTransaction(
          id: transactionID,
          operations: MicroblogExample.deletePostOperations(id: postID)
        ),
        createdAt: now,
        source: "cli.examples.microblog.delete-post"
      )
      try await printMicroblog(
        context: context,
        output: output,
        event: "delete-post",
        changedID: postID,
        selectedUserID: profile.userID,
        selectedPostID: postID
      )

    case .reset:
      let users = try await currentMicroblogUsers(context: context)
      let operations = users.flatMap { MicroblogExample.deleteUserOperations(id: $0.id) }
      if !operations.isEmpty {
        let transactionID = context.runtime.configuration.makeID()
        let now = context.runtime.configuration.now()
        try await context.runtime.transact(
          InstantStoreTransaction(id: transactionID, operations: operations),
          createdAt: now,
          source: "cli.examples.microblog.reset"
        )
      }
      try await printMicroblog(context: context, output: output, event: "reset")

    case .unknown:
      preconditionFailure("Unknown microblog commands are handled before bootstrapping.")
    }
  }

  private static func runMobileChat(
    leaf invocation: CLIExamplesMobileChatLeafInvocation,
    output: OutputMode
  ) async throws {
    if case let .unknown(command) = invocation {
      throw CLIError("Unknown mobile chat command: \(command). \(mobileChatUsage)", exitCode: 64)
    }

    let context = try await CLIContext.bootstrap(initialAttributes: MobileChatExample.attributes)

    switch invocation {
    case .seed:
      let transactionID = context.runtime.configuration.makeID()
      let now = context.runtime.configuration.now()
      try await context.runtime.transact(
        InstantStoreTransaction(
          id: transactionID,
          operations: MobileChatExample.seedOperations(
            ids: try await mobileChatSeedIDs(context: context),
            baseTimestamp: now,
            transactionID: transactionID
          )
        ),
        createdAt: now,
        source: "cli.examples.mobile-chat.seed"
      )
      try await printMobileChat(context: context, output: output, event: "seed")

    case .channels:
      try await printMobileChat(context: context, output: output, event: "channels")

    case let .messages(channelID):
      if let channelID {
        _ = try await requireMobileChatChannel(context: context, id: channelID)
      }
      try await printMobileChat(
        context: context,
        output: output,
        event: "messages",
        selectedChannelID: channelID
      )

    case .profiles:
      try await printMobileChat(context: context, output: output, event: "profiles")

    case let .profile(userID):
      let selectedUserID = try await selectedMobileChatUserID(
        context: context,
        explicitUserID: userID
      )
      let selectedProfile = try await requireMobileChatProfile(
        context: context,
        userID: selectedUserID
      )
      try await printMobileChat(
        context: context,
        output: output,
        event: "profile",
        selectedUserID: selectedUserID,
        selectedProfile: selectedProfile
      )

    case let .setupProfile(displayName):
      let session = try await requireMobileChatAuthSession(
        context: context,
        operation: "set up a profile"
      )
      let transactionID = context.runtime.configuration.makeID()
      let now = context.runtime.configuration.now()
      try await context.runtime.transact(
        InstantStoreTransaction(
          id: transactionID,
          operations: MobileChatExample.createProfileOperations(
            userID: session.userID,
            displayName: displayName,
            email: mobileChatEmail(for: session),
            transactionID: transactionID,
            updatedAt: now
          )
        ),
        createdAt: now,
        source: "cli.examples.mobile-chat.setup-profile"
      )
      let profile = try await requireMobileChatProfile(
        context: context,
        userID: session.userID
      )
      try await printMobileChat(
        context: context,
        output: output,
        event: "setup-profile",
        changedID: profile.id,
        selectedUserID: session.userID,
        selectedProfile: profile
      )

    case let .send(send):
      _ = try await requireMobileChatChannel(context: context, id: send.channelID)
      let session = try await requireMobileChatAuthSession(
        context: context,
        operation: "send a message"
      )
      let profile = try await mobileChatProfile(context: context, userID: session.userID)
      let messageID = context.runtime.configuration.makeID()
      let transactionID = context.runtime.configuration.makeID()
      let now = context.runtime.configuration.now()
      try await context.runtime.transact(
        InstantStoreTransaction(
          id: transactionID,
          operations: MobileChatExample.createMessageOperations(
            id: messageID,
            channelID: send.channelID,
            authorProfileID: profile?.id,
            content: send.content,
            timestamp: now,
            transactionID: transactionID
          )
        ),
        createdAt: now,
        source: "cli.examples.mobile-chat.send"
      )
      try await printMobileChat(
        context: context,
        output: output,
        event: "send",
        changedID: messageID,
        selectedUserID: session.userID,
        selectedProfile: profile,
        selectedChannelID: send.channelID
      )

    case let .join(channelID):
      _ = try await requireMobileChatChannel(context: context, id: channelID)
      let profile = try await requireCurrentMobileChatProfile(context: context)
      let room = MobileChatExample.room(forChannelID: channelID)
      let member = try await context.runtime.setPresence(
        room: room,
        userID: profile.userID,
        values: MobileChatExample.presenceValues(profile: profile)
      )
      try await printMobileChat(
        context: context,
        output: output,
        event: "join",
        changedID: member.userID,
        selectedUserID: profile.userID,
        selectedProfile: profile,
        selectedChannelID: channelID
      )

    case let .presence(channelID):
      _ = try await requireMobileChatChannel(context: context, id: channelID)
      try await printMobileChat(
        context: context,
        output: output,
        event: "presence",
        selectedChannelID: channelID
      )

    case let .leave(channelID):
      _ = try await requireMobileChatChannel(context: context, id: channelID)
      let session = try await requireMobileChatAuthSession(
        context: context,
        operation: "leave a room"
      )
      let room = MobileChatExample.room(forChannelID: channelID)
      let userID = try await context.runtime.leavePresence(room: room, userID: session.userID)
      try await printMobileChat(
        context: context,
        output: output,
        event: "leave",
        changedID: userID,
        selectedUserID: session.userID,
        selectedProfile: try await mobileChatProfile(context: context, userID: session.userID),
        selectedChannelID: channelID
      )

    case .reset:
      let channels = try await currentMobileChatChannels(context: context)
      try await clearMobileChatPresence(context: context, channels: channels)
      let messages = try await currentMobileChatMessages(context: context)
      let profiles = try await currentMobileChatProfiles(context: context)
      let operations =
        messages.flatMap { MobileChatExample.deleteMessageOperations(id: $0.id) }
        + profiles.flatMap { MobileChatExample.deleteProfileOperations(id: $0.id) }
        + channels.flatMap { MobileChatExample.deleteChannelOperations(id: $0.id) }
      if !operations.isEmpty {
        let transactionID = context.runtime.configuration.makeID()
        let now = context.runtime.configuration.now()
        try await context.runtime.transact(
          InstantStoreTransaction(id: transactionID, operations: operations),
          createdAt: now,
          source: "cli.examples.mobile-chat.reset"
        )
      }
      try await printMobileChat(context: context, output: output, event: "reset")

    case .unknown:
      preconditionFailure("Unknown mobile chat commands are handled before bootstrapping.")
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

  private static func printAuthRecipe(
    context: CLIContext,
    event: String,
    session: InstantAuthSession?,
    challenge: InstantMagicCodeChallenge? = nil,
    sentEmail: String? = nil,
    output: OutputMode
  ) throws {
    let payload = makeAuthRecipeOutput(
      context: context,
      event: event,
      session: session,
      challenge: challenge,
      sentEmail: sentEmail
    )

    switch output {
    case .human:
      printAuthRecipe(payload)

    case .json:
      try writeJSON(payload)

    case .jsonl:
      try writeJSONLine(
        EvidenceRow(
          caseID: "cli.examples.auth",
          side: "swift",
          event: event,
          appID: context.appID,
          entityID: session?.userID ?? challenge?.email,
          ok: true,
          details: payload
        )
      )
    }
  }

  private static func makeAuthRecipeOutput(
    context: CLIContext,
    event: String,
    session: InstantAuthSession?,
    challenge: InstantMagicCodeChallenge? = nil,
    sentEmail: String? = nil
  ) -> AuthRecipeOutput {
    let recipeEmail = AuthRecipeExample.userEmail(from: session)
    return AuthRecipeOutput(
      appID: context.appID,
      cachePath: context.cacheURL.path,
      event: event,
      recipeSlug: AuthRecipeExample.recipeSlug,
      transport: "not-implemented-local-cache-only",
      isLoginVisible: AuthRecipeExample.isLoginVisible(for: session),
      isEmailEntryVisible: AuthRecipeExample.isEmailEntryVisible(
        session: session,
        challenge: challenge
      ),
      isCodeEntryVisible: AuthRecipeExample.isCodeEntryVisible(
        session: session,
        challenge: challenge
      ),
      isDashboardVisible: AuthRecipeExample.isDashboardVisible(for: session),
      isSignedIn: session != nil,
      userID: session?.userID,
      userEmail: recipeEmail,
      isGuest: session?.isGuest,
      hasRefreshToken: session?.refreshToken != nil,
      sentEmail: challenge?.email ?? sentEmail,
      localVerificationCode: challenge?.code,
      expiresAt: challenge?.expiresAt,
      createdAt: session?.createdAt,
      updatedAt: session?.updatedAt
    )
  }

  private static func printAuthRecipe(_ payload: AuthRecipeOutput) {
    print("recipe: \(payload.recipeSlug)")
    if payload.isDashboardVisible {
      print("view: dashboard")
      if let email = payload.userEmail {
        print("email: \(email)")
      } else if let userID = payload.userID {
        print("user: \(userID)")
      }
      print("refresh token: \(payload.hasRefreshToken ? "present" : "none")")
    } else {
      print("view: \(payload.isCodeEntryVisible ? "code-entry" : "login")")
      if let sentEmail = payload.sentEmail {
        print("sent email: \(sentEmail)")
      }
      if let localVerificationCode = payload.localVerificationCode {
        print("local verification code: \(localVerificationCode)")
      }
    }
    print("cache: \(payload.cachePath)")
  }

  private static func watchAuthRecipe(
    context: CLIContext,
    output: OutputMode,
    eventCount: Int
  ) async throws {
    let stream = try await context.runtime.observeAuthSession()
    var iterator = stream.makeAsyncIterator()
    var emissions: [AuthRecipeOutput] = []
    emissions.reserveCapacity(eventCount)

    while emissions.count < eventCount {
      guard let session = await iterator.next() else { break }
      let payload = makeAuthRecipeOutput(
        context: context,
        event: "watch",
        session: session
      )

      switch output {
      case .human:
        print("event: watch index=\(emissions.count)")
        printAuthRecipe(payload)

      case .json, .jsonl:
        break
      }

      emissions.append(payload)

      if output == .jsonl {
        try writeJSONLine(
          EvidenceRow(
            caseID: "cli.examples.auth.watch",
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
        AuthRecipeWatchOutput(
          appID: context.appID,
          cachePath: context.cacheURL.path,
          event: "watch",
          recipeSlug: AuthRecipeExample.recipeSlug,
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

  private static func printCounters(
    context: CLIContext,
    output: OutputMode,
    event: String,
    changedID: String? = nil
  ) async throws {
    let counters = try await currentCounters(context: context)
    let status = try await context.runtime.connectionStatus()
    let shares = status.userID == nil ? [] : try await context.runtime.shares()
    let rows = CounterExample.sharedRows(counters: counters, shares: shares, userID: status.userID)
    let pending = await context.runtime.pendingMutations()
    let payload = CountersOutput(
      appID: context.appID,
      cachePath: context.cacheURL.path,
      event: event,
      changedID: changedID,
      transport: "not-implemented-local-cache-only",
      queryID: CounterExample.query.id,
      cacheKey: CounterExample.query.cacheKey,
      pendingMutationCount: pending.count,
      counterCount: rows.count,
      sharedCounterCount: rows.filter(\.isShared).count,
      counters: rows
    )

    switch output {
    case .human:
      if rows.isEmpty {
        print("No counters.")
      } else {
        for row in rows {
          let shared = row.isShared ? " shared" : ""
          print("\(row.counter.id) \(row.counter.count)\(shared)")
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
          caseID: "cli.examples.counters",
          side: "swift",
          event: event,
          appID: context.appID,
          entityID: changedID,
          ok: true,
          details: payload
        )
      )
      for row in rows {
        try writeJSONLine(
          EvidenceRow(
            caseID: "cli.examples.counters",
            side: "swift",
            event: "counter",
            appID: context.appID,
            entityID: row.counter.id,
            ok: true,
            details: row
          )
        )
      }
    }
  }

  private static func currentCounters(context: CLIContext) async throws -> [CounterRecord] {
    try CounterExample.decode((try await context.runtime.queryOnce(CounterExample.query)).values)
  }

  private static func requireCounter(context: CLIContext, id: String) async throws -> CounterRecord {
    let counters = try await currentCounters(context: context)
    guard let counter = counters.first(where: { $0.id == id }) else {
      throw CLIError("Counter not found: \(id)", exitCode: 66)
    }
    return counter
  }

  private static func printChat(
    context: CLIContext,
    output: OutputMode,
    event: String,
    changedID: String? = nil,
    selectedChannelID: String? = nil
  ) async throws {
    let channels = try await currentChatChannels(context: context)
    let messageQuery = selectedChannelID.map(ChatExample.messagesForChannelQuery)
      ?? ChatExample.messagesQuery
    let messages = try await currentChatMessages(context: context, query: messageQuery)
    let pending = await context.runtime.pendingMutations()
    let session = try await context.runtime.authSession()
    let payload = ChatOutput(
      appID: context.appID,
      cachePath: context.cacheURL.path,
      event: event,
      changedID: changedID,
      selectedChannelID: selectedChannelID,
      authUserID: session?.userID,
      authIsGuest: session?.isGuest,
      transport: "not-implemented-local-cache-only",
      channelQueryID: ChatExample.channelsQuery.id,
      messageQueryID: messageQuery.id,
      channelCacheKey: ChatExample.channelsQuery.cacheKey,
      messageCacheKey: messageQuery.cacheKey,
      pendingMutationCount: pending.count,
      channelCount: channels.count,
      messageCount: messages.count,
      channels: channels,
      messages: messages
    )

    switch output {
    case .human:
      if channels.isEmpty {
        print("No channels.")
      } else {
        for channel in channels {
          print("channel \(channel.id) #\(channel.title)")
        }
      }
      if messages.isEmpty {
        print("No messages.")
      } else {
        for message in messages {
          let user = message.authorUserID.map { " user=\($0)" } ?? ""
          print(
            "\(message.id) channel=\(message.channelID)\(user) \(message.authorName): \(message.text)"
          )
        }
      }
      if let authUserID = payload.authUserID {
        print("auth: \(payload.authIsGuest == true ? "guest" : "user") \(authUserID)")
      } else {
        print("auth: signed out")
      }
      print("transport: \(payload.transport)")
      print("pending mutations: \(pending.count)")
      print("cache: \(context.cacheURL.path)")

    case .json:
      try writeJSON(payload)

    case .jsonl:
      try writeJSONLine(
        EvidenceRow(
          caseID: "cli.examples.chat",
          side: "swift",
          event: event,
          appID: context.appID,
          entityID: changedID,
          ok: true,
          details: payload
        )
      )
      for channel in channels {
        try writeJSONLine(
          EvidenceRow(
            caseID: "cli.examples.chat",
            side: "swift",
            event: "channel",
            appID: context.appID,
            entityID: channel.id,
            ok: true,
            details: channel
          )
        )
      }
      for message in messages {
        try writeJSONLine(
          EvidenceRow(
            caseID: "cli.examples.chat",
            side: "swift",
            event: "message",
            appID: context.appID,
            entityID: message.id,
            ok: true,
            details: message
          )
        )
      }
    }
  }

  private static func currentChatChannels(context: CLIContext) async throws -> [ChatChannelRecord] {
    try ChatExample.decodeChannels(
      (try await context.runtime.queryOnce(ChatExample.channelsQuery)).values
    )
  }

  private static func currentChatMessages(
    context: CLIContext,
    query: InstantQueryPlan = ChatExample.messagesQuery
  ) async throws -> [ChatMessageRecord] {
    try ChatExample.decodeMessages((try await context.runtime.queryOnce(query)).values)
  }

  private static func requireChatChannel(
    context: CLIContext,
    id: String
  ) async throws -> ChatChannelRecord {
    let channels = try await currentChatChannels(context: context)
    guard let channel = channels.first(where: { $0.id == id }) else {
      throw CLIError("Chat channel not found: \(id)", exitCode: 66)
    }
    return channel
  }

  private static func currentOrGuestChatSession(
    context: CLIContext
  ) async throws -> InstantAuthSession {
    if let session = try await context.runtime.authSession() {
      return session
    }
    return try await context.runtime.signInAsGuest()
  }

  private static func printAppBuilder(
    context: CLIContext,
    output: OutputMode,
    event: String,
    changedID: String? = nil,
    selectedBuildID: String? = nil,
    ownerID explicitOwnerID: String? = nil,
    platformApp: InstantPlatformApp? = nil,
    generationEvents: [AppBuilderGenerationEventOutput] = []
  ) async throws {
    let session = try await context.runtime.authSession()
    let ownerID = explicitOwnerID ?? session?.userID
    let builds = try await currentAppBuilderBuilds(context: context, ownerID: ownerID)
    let selectedBuild: AppBuilderBuildRecord?
    if let selectedBuildID {
      selectedBuild = try await currentAppBuilderBuild(context: context, id: selectedBuildID)
    } else {
      selectedBuild = nil
    }
    let pending = await context.runtime.pendingMutations()
    let ownerQuery = ownerID.map(AppBuilderExample.buildsForOwnerQuery)
    let payload = AppBuilderOutput(
      appID: context.appID,
      cachePath: context.cacheURL.path,
      event: event,
      changedID: changedID,
      selectedBuildID: selectedBuildID,
      authUserID: session?.userID,
      authUserEmail: AuthRecipeExample.userEmail(from: session),
      transport: "not-implemented-local-cache-only",
      platformApp: platformApp,
      queryID: AppBuilderExample.buildsQuery.id,
      cacheKey: AppBuilderExample.buildsQuery.cacheKey,
      ownerQueryID: ownerQuery?.id,
      ownerCacheKey: ownerQuery?.cacheKey,
      pendingMutationCount: pending.count,
      buildCount: builds.count,
      previewableBuildCount: builds.filter { $0.isPreviewable == true }.count,
      builds: builds,
      selectedBuild: selectedBuild,
      generationEvents: generationEvents
    )

    switch output {
    case .human:
      if let selectedBuild {
        print("build: \(selectedBuild.id)")
        print("title: \(selectedBuild.title ?? "")")
        print("instant app: \(selectedBuild.instantAppID)")
        print("previewable: \(selectedBuild.isPreviewable == true)")
        if let reasoning = selectedBuild.reasoning, !reasoning.isEmpty {
          print("reasoning: \(reasoning)")
        }
        if selectedBuild.code.isEmpty {
          print("code: <empty>")
        } else {
          print(selectedBuild.code)
        }
      } else if builds.isEmpty {
        print("No app-builder builds.")
      } else {
        for build in builds {
          let status = build.isPreviewable == true ? "Previewable" : "Not Previewable"
          print("\(build.id) \(status) \(build.title ?? "")")
        }
      }
      if let platformApp {
        print("created Instant app: \(platformApp.id)")
      }
      if let authUserID = payload.authUserID {
        print("auth: \(authUserID)")
      } else {
        print("auth: signed out")
      }
      print("transport: \(payload.transport)")
      print("pending mutations: \(pending.count)")
      print("cache: \(context.cacheURL.path)")

    case .json:
      try writeJSON(payload)

    case .jsonl:
      try writeJSONLine(
        EvidenceRow(
          caseID: "cli.examples.app-builder",
          side: "swift",
          event: event,
          appID: context.appID,
          entityID: changedID ?? selectedBuildID,
          ok: true,
          details: payload
        )
      )
      for generationEvent in generationEvents {
        try writeJSONLine(
          EvidenceRow(
            caseID: "cli.examples.app-builder",
            side: "swift",
            event: generationEvent.event,
            appID: context.appID,
            entityID: changedID ?? selectedBuildID,
            ok: true,
            details: generationEvent
          )
        )
      }
      for build in builds {
        try writeJSONLine(
          EvidenceRow(
            caseID: "cli.examples.app-builder",
            side: "swift",
            event: "build",
            appID: context.appID,
            entityID: build.id,
            ok: true,
            details: build
          )
        )
      }
    }
  }

  private static func currentAppBuilderBuilds(
    context: CLIContext,
    ownerID: String? = nil
  ) async throws -> [AppBuilderBuildRecord] {
    let query = ownerID.map(AppBuilderExample.buildsForOwnerQuery) ?? AppBuilderExample.buildsQuery
    return try AppBuilderExample.decodeBuilds(
      (try await context.runtime.queryOnce(query)).values
    )
  }

  private static func currentAppBuilderBuild(
    context: CLIContext,
    id: String
  ) async throws -> AppBuilderBuildRecord? {
    try AppBuilderExample.decodeBuilds(
      (try await context.runtime.queryOnce(AppBuilderExample.buildQuery(id))).values
    )
    .first
  }

  private static func requireAppBuilderBuild(
    context: CLIContext,
    id: String
  ) async throws -> AppBuilderBuildRecord {
    guard let build = try await currentAppBuilderBuild(context: context, id: id) else {
      throw CLIError("App-builder build not found: \(id)", exitCode: 66)
    }
    return build
  }

  private static func requireAppBuilderEmailSession(
    context: CLIContext
  ) async throws -> (InstantAuthSession, String) {
    guard let session = try await context.runtime.authSession() else {
      throw CLIError(
        """
        App-builder requires a signed-in email user. Run \
        'instant-swift-data examples auth send-code user@example.com' and \
        'instant-swift-data examples auth verify-code user@example.com <code>' first.
        """,
        exitCode: 65
      )
    }
    guard let email = AuthRecipeExample.userEmail(from: session) else {
      throw CLIError(
        """
        App-builder requires an email-backed auth session because the upstream API writes \
        builds as adminDB.asUser({ email }). Sign in with the magic-code auth recipe first.
        """,
        exitCode: 65
      )
    }
    return (session, email)
  }

  private static func printMicroblog(
    context: CLIContext,
    output: OutputMode,
    event: String,
    changedID: String? = nil,
    selectedUserID: String? = nil,
    selectedProfile: MicroblogProfileRecord? = nil,
    selectedPostID: String? = nil
  ) async throws {
    let users = try await currentMicroblogUsers(context: context)
    let profiles = try await currentMicroblogProfiles(context: context)
    let posts = try await currentMicroblogPosts(context: context)
    let likes = try await currentMicroblogLikes(context: context)
    let feed = try await currentMicroblogFeed(context: context)
    let pending = await context.runtime.pendingMutations()
    let session = try await context.runtime.authSession()
    let payload = MicroblogOutput(
      appID: context.appID,
      cachePath: context.cacheURL.path,
      event: event,
      changedID: changedID,
      selectedUserID: selectedUserID,
      selectedProfile: selectedProfile,
      selectedPostID: selectedPostID,
      authUserID: session?.userID,
      transport: "not-implemented-local-cache-only",
      userQueryID: MicroblogExample.usersQuery.id,
      profileQueryID: MicroblogExample.profilesQuery.id,
      postQueryID: MicroblogExample.postsQuery.id,
      likeQueryID: MicroblogExample.likesQuery.id,
      feedQueryID: MicroblogExample.feedQuery.id,
      userCacheKey: MicroblogExample.usersQuery.cacheKey,
      profileCacheKey: MicroblogExample.profilesQuery.cacheKey,
      postCacheKey: MicroblogExample.postsQuery.cacheKey,
      likeCacheKey: MicroblogExample.likesQuery.cacheKey,
      feedCacheKey: MicroblogExample.feedQuery.cacheKey,
      pendingMutationCount: pending.count,
      userCount: users.count,
      profileCount: profiles.count,
      postCount: posts.count,
      likeCount: likes.count,
      users: users,
      profiles: profiles,
      posts: posts,
      likes: likes,
      feed: feed
    )

    switch output {
    case .human:
      if let selectedProfile {
        print(
          "profile: \(selectedProfile.displayName) @\(selectedProfile.handle) user=\(selectedProfile.userID)"
        )
      }
      if feed.isEmpty {
        print("No microblog posts.")
      } else {
        for item in feed {
          let author = item.author.map { "@\($0.handle)" } ?? "@unknown"
          print(
            "\(item.post.id) \(author) likes=\(item.likes.count) color=\(item.post.color) \(item.post.content)"
          )
        }
      }
      if !profiles.isEmpty {
        print("profiles: \(profiles.map { "@\($0.handle)" }.joined(separator: " "))")
      }
      if let authUserID = payload.authUserID {
        print("auth: \(authUserID)")
      } else {
        print("auth: signed out")
      }
      print("transport: \(payload.transport)")
      print("pending mutations: \(pending.count)")
      print("cache: \(context.cacheURL.path)")

    case .json:
      try writeJSON(payload)

    case .jsonl:
      try writeJSONLine(
        EvidenceRow(
          caseID: "cli.examples.microblog",
          side: "swift",
          event: event,
          appID: context.appID,
          entityID: changedID,
          ok: true,
          details: payload
        )
      )
      for user in users {
        try writeJSONLine(
          EvidenceRow(
            caseID: "cli.examples.microblog",
            side: "swift",
            event: "user",
            appID: context.appID,
            entityID: user.id,
            ok: true,
            details: user
          )
        )
      }
      for profile in profiles {
        try writeJSONLine(
          EvidenceRow(
            caseID: "cli.examples.microblog",
            side: "swift",
            event: "profile",
            appID: context.appID,
            entityID: profile.id,
            ok: true,
            details: profile
          )
        )
      }
      for post in posts {
        try writeJSONLine(
          EvidenceRow(
            caseID: "cli.examples.microblog",
            side: "swift",
            event: "post",
            appID: context.appID,
            entityID: post.id,
            ok: true,
            details: post
          )
        )
      }
      for like in likes {
        try writeJSONLine(
          EvidenceRow(
            caseID: "cli.examples.microblog",
            side: "swift",
            event: "like",
            appID: context.appID,
            entityID: like.id,
            ok: true,
            details: like
          )
        )
      }
    }
  }

  private static func microblogSeedIDs(context: CLIContext) async throws
    -> MicroblogExample.SeedIDs
  {
    var userIDs: [String] = []
    var postIDs: [String] = []
    var likeIDs: [[String]] = []
    for seed in MicroblogExample.seedPosts {
      userIDs.append(
        try await context.runtime.localID(named: "examples.microblog.users.\(seed.slug)")
      )
      postIDs.append(
        try await context.runtime.localID(named: "examples.microblog.posts.\(seed.slug)")
      )
      var seedLikeIDs: [String] = []
      for index in 0..<seed.likes {
        seedLikeIDs.append(
          try await context.runtime.localID(named: "examples.microblog.likes.\(seed.slug).\(index)")
        )
      }
      likeIDs.append(seedLikeIDs)
    }
    return MicroblogExample.SeedIDs(userIDs: userIDs, postIDs: postIDs, likeIDs: likeIDs)
  }

  private static func currentMicroblogUsers(context: CLIContext) async throws
    -> [MicroblogUserRecord]
  {
    try MicroblogExample.decodeUsers(
      (try await context.runtime.queryOnce(MicroblogExample.usersQuery)).values
    )
  }

  private static func currentMicroblogProfiles(context: CLIContext) async throws
    -> [MicroblogProfileRecord]
  {
    try MicroblogExample.decodeProfiles(
      (try await context.runtime.queryOnce(MicroblogExample.profilesQuery)).values
    )
  }

  private static func currentMicroblogPosts(context: CLIContext) async throws
    -> [MicroblogPostRecord]
  {
    try MicroblogExample.decodePosts(
      (try await context.runtime.queryOnce(MicroblogExample.postsQuery)).values
    )
  }

  private static func currentMicroblogLikes(
    context: CLIContext,
    query: InstantQueryPlan = MicroblogExample.likesQuery
  ) async throws -> [MicroblogLikeRecord] {
    try MicroblogExample.decodeLikes((try await context.runtime.queryOnce(query)).values)
  }

  private static func currentMicroblogFeed(context: CLIContext) async throws
    -> [MicroblogFeedPostRecord]
  {
    try MicroblogExample.decodeFeed(
      (try await context.runtime.queryOnce(MicroblogExample.feedQuery)).values
    )
  }

  private static func selectedMicroblogUserID(
    context: CLIContext,
    explicitUserID: String?
  ) async throws -> String {
    if let explicitUserID {
      return explicitUserID
    }
    let session = try await requireMicroblogAuthSession(
      context: context,
      operation: "view a profile"
    )
    return session.userID
  }

  private static func requireMicroblogAuthSession(
    context: CLIContext,
    operation: String
  ) async throws -> InstantAuthSession {
    guard let session = try await context.runtime.authSession() else {
      throw CLIError(
        """
        Microblog \(operation) requires a signed-in user. Run \
        'instant-swift-data auth token <refresh-token> --user-id <user-id>' first.
        """,
        exitCode: 65
      )
    }
    return session
  }

  private static func requireMicroblogProfile(
    context: CLIContext,
    userID: String
  ) async throws -> MicroblogProfileRecord {
    let profiles = try MicroblogExample.decodeProfiles(
      (try await context.runtime.queryOnce(MicroblogExample.profileForUserQuery(userID))).values
    )
    guard let profile = profiles.first else {
      throw CLIError(
        "Microblog profile not found for user: \(userID).",
        exitCode: 66
      )
    }
    return profile
  }

  private static func requireCurrentMicroblogProfile(
    context: CLIContext
  ) async throws -> MicroblogProfileRecord {
    let session = try await requireMicroblogAuthSession(context: context, operation: "mutation")
    do {
      return try await requireMicroblogProfile(context: context, userID: session.userID)
    } catch let error as CLIError where error.exitCode == 66 {
      throw CLIError(
        """
        Microblog profile not found for user: \(session.userID). Run \
        'instant-swift-data examples microblog setup-profile "Display Name" <handle>' first.
        """,
        exitCode: 66
      )
    }
  }

  private static func requireMicroblogPost(
    context: CLIContext,
    id: String
  ) async throws -> MicroblogPostRecord {
    let posts = try await currentMicroblogPosts(context: context)
    guard let post = posts.first(where: { $0.id == id }) else {
      throw CLIError("Microblog post not found: \(id)", exitCode: 66)
    }
    return post
  }

  private static func requireMicroblogLike(
    context: CLIContext,
    postID: String,
    userID: String
  ) async throws -> MicroblogLikeRecord {
    let likes = try await currentMicroblogLikes(
      context: context,
      query: MicroblogExample.likesForPostQuery(postID)
    )
    guard let like = likes.first(where: { $0.userID == userID }) else {
      throw CLIError("Microblog like not found for post: \(postID)", exitCode: 66)
    }
    return like
  }

  private static func normalizedMicroblogHandle(_ value: String) -> String {
    var handle = value.trimmingCharacters(in: .whitespacesAndNewlines)
    if handle.hasPrefix("@") {
      handle.removeFirst()
    }
    return handle.lowercased()
  }

  private static func printMobileChat(
    context: CLIContext,
    output: OutputMode,
    event: String,
    changedID: String? = nil,
    selectedUserID: String? = nil,
    selectedProfile: MobileChatProfileRecord? = nil,
    selectedChannelID: String? = nil
  ) async throws {
    let profiles = try await currentMobileChatProfiles(context: context)
    let users = try await currentMobileChatUsers(context: context, profiles: profiles)
    let channels = try await currentMobileChatChannels(context: context)
    let messageQuery = selectedChannelID.map(MobileChatExample.messagesForChannelQuery)
      ?? MobileChatExample.messagesQuery
    let messages = try await currentMobileChatMessages(context: context, query: messageQuery)
    let pending = await context.runtime.pendingMutations()
    let session = try await context.runtime.authSession()
    let presenceRoom = selectedChannelID.map(MobileChatExample.room(forChannelID:))
    let presenceMembers: [InstantRoomPresenceMember]
    if let presenceRoom {
      presenceMembers = try await context.runtime.roomPresence(room: presenceRoom)
    } else {
      presenceMembers = []
    }
    let payload = MobileChatOutput(
      appID: context.appID,
      cachePath: context.cacheURL.path,
      event: event,
      changedID: changedID,
      selectedUserID: selectedUserID,
      selectedProfile: selectedProfile,
      selectedChannelID: selectedChannelID,
      authUserID: session?.userID,
      authIsGuest: session?.isGuest,
      transport: "not-implemented-local-cache-only",
      userQueryID: MobileChatExample.usersQuery.id,
      profileQueryID: MobileChatExample.profilesQuery.id,
      channelQueryID: MobileChatExample.channelsQuery.id,
      messageQueryID: messageQuery.id,
      userCacheKey: MobileChatExample.usersQuery.cacheKey,
      profileCacheKey: MobileChatExample.profilesQuery.cacheKey,
      channelCacheKey: MobileChatExample.channelsQuery.cacheKey,
      messageCacheKey: messageQuery.cacheKey,
      pendingMutationCount: pending.count,
      userCount: users.count,
      profileCount: profiles.count,
      channelCount: channels.count,
      messageCount: messages.count,
      presenceRoom: presenceRoom,
      presenceMemberCount: presenceMembers.count,
      users: users,
      profiles: profiles,
      channels: channels,
      messages: messages,
      presenceMembers: presenceMembers
    )

    switch output {
    case .human:
      if let selectedProfile {
        print("profile: \(selectedProfile.displayName) user=\(selectedProfile.userID)")
      }
      if channels.isEmpty {
        print("No mobile chat channels.")
      } else {
        for channel in channels {
          print("channel \(channel.id) #\(channel.name)")
        }
      }
      if messages.isEmpty {
        print("No mobile chat messages.")
      } else {
        for message in messages {
          let author =
            message.authorUser?.email
            ?? message.author?.displayName
            ?? "Guest"
          print(
            "\(message.id) channel=\(message.channelID) \(author): \(message.content)"
          )
        }
      }
      if !presenceMembers.isEmpty {
        let members = presenceMembers.map { $0.userID }.joined(separator: " ")
        print("presence: \(members)")
      }
      if let authUserID = payload.authUserID {
        print("auth: \(payload.authIsGuest == true ? "guest" : "user") \(authUserID)")
      } else {
        print("auth: signed out")
      }
      print("transport: \(payload.transport)")
      print("pending mutations: \(pending.count)")
      print("cache: \(context.cacheURL.path)")

    case .json:
      try writeJSON(payload)

    case .jsonl:
      try writeJSONLine(
        EvidenceRow(
          caseID: "cli.examples.mobile-chat",
          side: "swift",
          event: event,
          appID: context.appID,
          entityID: changedID,
          ok: true,
          details: payload
        )
      )
      for user in users {
        try writeJSONLine(
          EvidenceRow(
            caseID: "cli.examples.mobile-chat",
            side: "swift",
            event: "user",
            appID: context.appID,
            entityID: user.id,
            ok: true,
            details: user
          )
        )
      }
      for profile in profiles {
        try writeJSONLine(
          EvidenceRow(
            caseID: "cli.examples.mobile-chat",
            side: "swift",
            event: "profile",
            appID: context.appID,
            entityID: profile.id,
            ok: true,
            details: profile
          )
        )
      }
      for channel in channels {
        try writeJSONLine(
          EvidenceRow(
            caseID: "cli.examples.mobile-chat",
            side: "swift",
            event: "channel",
            appID: context.appID,
            entityID: channel.id,
            ok: true,
            details: channel
          )
        )
      }
      for message in messages {
        try writeJSONLine(
          EvidenceRow(
            caseID: "cli.examples.mobile-chat",
            side: "swift",
            event: "message",
            appID: context.appID,
            entityID: message.id,
            ok: true,
            details: message
          )
        )
      }
      for member in presenceMembers {
        try writeJSONLine(
          EvidenceRow(
            caseID: "cli.examples.mobile-chat",
            side: "swift",
            event: "presence",
            appID: context.appID,
            entityID: member.userID,
            ok: true,
            details: member
          )
        )
      }
    }
  }

  private static func mobileChatSeedIDs(context: CLIContext) async throws
    -> MobileChatExample.SeedIDs
  {
    MobileChatExample.SeedIDs(
      generalChannelID: try await context.runtime.localID(
        named: MobileChatExample.generalChannelIDName
      ),
      randomChannelID: try await context.runtime.localID(
        named: MobileChatExample.randomChannelIDName
      ),
      seedUserID: try await context.runtime.localID(
        named: MobileChatExample.seedUserIDName
      ),
      welcomeMessageID: try await context.runtime.localID(
        named: MobileChatExample.welcomeMessageIDName
      ),
      randomMessageID: try await context.runtime.localID(
        named: MobileChatExample.randomMessageIDName
      )
    )
  }

  private static func currentMobileChatUsers(
    context: CLIContext,
    profiles: [MobileChatProfileRecord]
  ) async throws -> [MobileChatUserRecord] {
    let userIDs = Set(profiles.map(\.userID))
    return try MobileChatExample.decodeUsers(
      (try await context.runtime.queryOnce(MobileChatExample.usersQuery)).values
    )
    .filter { userIDs.contains($0.id) }
  }

  private static func currentMobileChatProfiles(context: CLIContext) async throws
    -> [MobileChatProfileRecord]
  {
    try MobileChatExample.decodeProfiles(
      (try await context.runtime.queryOnce(MobileChatExample.profilesQuery)).values
    )
  }

  private static func currentMobileChatChannels(context: CLIContext) async throws
    -> [MobileChatChannelRecord]
  {
    try MobileChatExample.decodeChannels(
      (try await context.runtime.queryOnce(MobileChatExample.channelsQuery)).values
    )
  }

  private static func currentMobileChatMessages(
    context: CLIContext,
    query: InstantQueryPlan = MobileChatExample.messagesQuery
  ) async throws -> [MobileChatMessageRecord] {
    try MobileChatExample.decodeMessages((try await context.runtime.queryOnce(query)).values)
  }

  private static func selectedMobileChatUserID(
    context: CLIContext,
    explicitUserID: String?
  ) async throws -> String {
    if let explicitUserID {
      return explicitUserID
    }
    let session = try await requireMobileChatAuthSession(
      context: context,
      operation: "view a profile"
    )
    return session.userID
  }

  private static func requireMobileChatAuthSession(
    context: CLIContext,
    operation: String
  ) async throws -> InstantAuthSession {
    guard let session = try await context.runtime.authSession() else {
      throw CLIError(
        """
        Mobile chat \(operation) requires a signed-in user. Run \
        'instant-swift-data auth guest' or \
        'instant-swift-data auth token <refresh-token> --user-id <user-id>' first.
        """,
        exitCode: 65
      )
    }
    return session
  }

  private static func mobileChatProfile(
    context: CLIContext,
    userID: String
  ) async throws -> MobileChatProfileRecord? {
    try MobileChatExample.decodeProfiles(
      (try await context.runtime.queryOnce(MobileChatExample.profileForUserQuery(userID))).values
    )
    .first
  }

  private static func requireMobileChatProfile(
    context: CLIContext,
    userID: String
  ) async throws -> MobileChatProfileRecord {
    guard let profile = try await mobileChatProfile(context: context, userID: userID) else {
      throw CLIError(
        "Mobile chat profile not found for user: \(userID).",
        exitCode: 66
      )
    }
    return profile
  }

  private static func requireCurrentMobileChatProfile(
    context: CLIContext
  ) async throws -> MobileChatProfileRecord {
    let session = try await requireMobileChatAuthSession(context: context, operation: "join a room")
    do {
      return try await requireMobileChatProfile(context: context, userID: session.userID)
    } catch let error as CLIError where error.exitCode == 66 {
      throw CLIError(
        """
        Mobile chat profile not found for user: \(session.userID). Run \
        'instant-swift-data examples mobile-chat setup-profile "Display Name"' first.
        """,
        exitCode: 66
      )
    }
  }

  private static func requireMobileChatChannel(
    context: CLIContext,
    id: String
  ) async throws -> MobileChatChannelRecord {
    let channels = try await currentMobileChatChannels(context: context)
    guard let channel = channels.first(where: { $0.id == id }) else {
      throw CLIError("Mobile chat channel not found: \(id)", exitCode: 66)
    }
    return channel
  }

  private static func mobileChatEmail(for session: InstantAuthSession) -> String? {
    let prefix = "email:"
    guard session.userID.hasPrefix(prefix) else { return nil }
    let email = String(session.userID.dropFirst(prefix.count))
      .trimmingCharacters(in: .whitespacesAndNewlines)
    return email.contains("@") ? email : nil
  }

  private static func clearMobileChatPresence(
    context: CLIContext,
    channels: [MobileChatChannelRecord]
  ) async throws {
    for channel in channels {
      let room = MobileChatExample.room(forChannelID: channel.id)
      let members = try await context.runtime.roomPresence(room: room)
      for member in members {
        _ = try await context.runtime.leavePresence(room: room, userID: member.userID)
      }
    }
  }

  private static func runReactions(
    leaf: CLIExamplesReactionsLeafInvocation,
    output: OutputMode
  ) async throws {
    if case let .unknown(command) = leaf {
      throw CLIError("Unknown reactions command: \(command). \(reactionsUsage)", exitCode: 64)
    }

    let context = try await CLIContext.bootstrap(initialAttributes: [])
    switch leaf {
    case let .tap(options):
      let message = try await context.runtime.publishTopicMessage(
        room: ReactionsRecipeExample.room,
        topic: ReactionsRecipeExample.topic,
        userID: options.userID,
        payload: ReactionsRecipeExample.payload(
          name: options.name,
          directionAngle: options.directionAngle,
          rotationAngle: options.rotationAngle
        )
      )
      let messages = try await context.runtime.roomTopicMessages(
        room: ReactionsRecipeExample.room,
        topic: ReactionsRecipeExample.topic
      )
      try await printReactions(
        context: context,
        output: output,
        event: "tap",
        publishedMessageID: message.id,
        messages: messages
      )

    case let .list(options):
      let messages = try await context.runtime.roomTopicMessages(
        room: ReactionsRecipeExample.room,
        topic: ReactionsRecipeExample.topic,
        limit: options.limit
      )
      try await printReactions(
        context: context,
        output: output,
        event: "list",
        publishedMessageID: nil,
        messages: messages
      )

    case let .watch(options):
      let messages = try await firstWatchSnapshot(
        from: context.runtime.observeRoomTopicMessages(
          room: ReactionsRecipeExample.room,
          topic: ReactionsRecipeExample.topic
        ),
        operation: "reactions watch",
        eventCount: options.eventCount
      )
      try await printReactions(
        context: context,
        output: output,
        event: "watch",
        publishedMessageID: nil,
        messages: messages
      )

    case .unknown:
      preconditionFailure("Unknown reactions commands are handled before bootstrapping.")
    }
  }

  private static func printReactions(
    context: CLIContext,
    output: OutputMode,
    event: String,
    publishedMessageID: String?,
    messages: [InstantRoomTopicMessage]
  ) async throws {
    let reactions = ReactionsRecipeExample.reactions(from: messages)
    let recipeMessages = messages.compactMap(ReactionsRecipeMessageOutput.init(message:))
    let session = try await context.runtime.authSession()
    let payload = ReactionsRecipeOutput(
      appID: context.appID,
      cachePath: context.cacheURL.path,
      event: event,
      publishedMessageID: publishedMessageID,
      authUserID: session?.userID,
      authIsGuest: session?.isGuest,
      transport: "not-implemented-local-cache-only",
      room: ReactionsRecipeExample.room,
      topic: ReactionsRecipeExample.topic,
      messageCount: messages.count,
      reactionCount: reactions.count,
      messages: recipeMessages,
      reactions: reactions
    )

    switch output {
    case .human:
      print("room: \(payload.room.type)/\(payload.room.id)")
      print("topic: \(payload.topic)")
      if let publishedMessageID {
        print("message: \(publishedMessageID)")
      }
      if reactions.isEmpty {
        print("No reactions.")
      } else {
        for reaction in reactions {
          print(
            "- \(reaction.id) \(reaction.name) \(reaction.symbol) user=\(reaction.userID) direction=\(reaction.directionAngle) rotation=\(reaction.rotationAngle)"
          )
        }
      }
      if let authUserID = payload.authUserID {
        print("auth: \(payload.authIsGuest == true ? "guest" : "user") \(authUserID)")
      } else {
        print("auth: signed out")
      }
      print("messages: \(messages.count)")
      print("reactions: \(reactions.count)")
      print("transport: \(payload.transport)")
      print("cache: \(context.cacheURL.path)")

    case .json:
      try writeJSON(payload)

    case .jsonl:
      try writeJSONLine(
        EvidenceRow(
          caseID: "cli.examples.reactions",
          side: "swift",
          event: event,
          appID: context.appID,
          entityID: publishedMessageID,
          ok: true,
          details: payload
        )
      )
      for reaction in reactions {
        try writeJSONLine(
          EvidenceRow(
            caseID: "cli.examples.reactions",
            side: "swift",
            event: "reaction",
            appID: context.appID,
            entityID: reaction.id,
            ok: true,
            details: reaction
          )
        )
      }
    }
  }

  private static func runTypingIndicator(
    leaf: CLIExamplesTypingIndicatorLeafInvocation,
    output: OutputMode
  ) async throws {
    if case let .unknown(command) = leaf {
      throw CLIError(
        "Unknown typing indicator command: \(command). \(typingIndicatorUsage)",
        exitCode: 64
      )
    }

    let context = try await CLIContext.bootstrap(initialAttributes: [])
    switch leaf {
    case let .join(userID):
      _ = try await context.runtime.setPresence(
        room: TypingIndicatorRecipeExample.room,
        userID: userID,
        values: TypingIndicatorRecipeExample.presenceValues(
          presenceID: userID,
          isTyping: false
        )
      )
      let members = try await context.runtime.roomPresence(
        room: TypingIndicatorRecipeExample.room
      )
      try printTypingIndicator(
        context: context,
        output: output,
        event: "join",
        userID: userID,
        viewerUserID: userID,
        presence: members
      )

    case let .type(userID):
      _ = try await context.runtime.setPresence(
        room: TypingIndicatorRecipeExample.room,
        userID: userID,
        values: TypingIndicatorRecipeExample.presenceValues(
          presenceID: userID,
          isTyping: true
        )
      )
      let members = try await context.runtime.roomPresence(
        room: TypingIndicatorRecipeExample.room
      )
      try printTypingIndicator(
        context: context,
        output: output,
        event: "type",
        userID: userID,
        viewerUserID: userID,
        presence: members
      )

    case let .stop(userID):
      _ = try await context.runtime.setPresence(
        room: TypingIndicatorRecipeExample.room,
        userID: userID,
        values: TypingIndicatorRecipeExample.presenceValues(
          presenceID: userID,
          isTyping: false
        )
      )
      let members = try await context.runtime.roomPresence(
        room: TypingIndicatorRecipeExample.room
      )
      try printTypingIndicator(
        context: context,
        output: output,
        event: "stop",
        userID: userID,
        viewerUserID: userID,
        presence: members
      )

    case let .list(options):
      let members = try await context.runtime.roomPresence(
        room: TypingIndicatorRecipeExample.room
      )
      try printTypingIndicator(
        context: context,
        output: output,
        event: "list",
        userID: nil,
        viewerUserID: options.viewerUserID,
        presence: members
      )

    case let .watch(options):
      let members = try await firstWatchSnapshot(
        from: context.runtime.observeRoomPresence(room: TypingIndicatorRecipeExample.room),
        operation: "typing indicator watch",
        eventCount: options.eventCount
      )
      try printTypingIndicator(
        context: context,
        output: output,
        event: "watch",
        userID: nil,
        viewerUserID: options.viewerUserID,
        presence: members
      )

    case let .leave(userID):
      let leftUserID = try await context.runtime.leavePresence(
        room: TypingIndicatorRecipeExample.room,
        userID: userID
      )
      let members = try await context.runtime.roomPresence(
        room: TypingIndicatorRecipeExample.room
      )
      try printTypingIndicator(
        context: context,
        output: output,
        event: "leave",
        userID: leftUserID,
        viewerUserID: leftUserID,
        presence: members
      )

    case .unknown:
      preconditionFailure("Unknown typing indicator commands are handled before bootstrapping.")
    }
  }

  private static func printTypingIndicator(
    context: CLIContext,
    output: OutputMode,
    event: String,
    userID: String?,
    viewerUserID: String?,
    presence: [InstantRoomPresenceMember]
  ) throws {
    let members = TypingIndicatorRecipeExample.members(from: presence)
    let activeMembers = TypingIndicatorRecipeExample.activeMembers(
      from: presence,
      excludingUserID: viewerUserID
    )
    let payload = TypingIndicatorRecipeOutput(
      appID: context.appID,
      cachePath: context.cacheURL.path,
      event: event,
      userID: userID,
      viewerUserID: viewerUserID,
      transport: "not-implemented-local-cache-only",
      room: TypingIndicatorRecipeExample.room,
      inputName: TypingIndicatorRecipeExample.inputName,
      memberCount: members.count,
      activeCount: activeMembers.count,
      typingInfo: TypingIndicatorRecipeExample.typingInfo(activeCount: activeMembers.count),
      members: members,
      activeMembers: activeMembers
    )

    switch output {
    case .human:
      print("room: \(payload.room.type)/\(payload.room.id)")
      print("input: \(payload.inputName)")
      if let userID {
        print("user: \(userID)")
      }
      if let viewerUserID {
        print("viewer: \(viewerUserID)")
      }
      print("members: \(payload.memberCount)")
      print("active: \(payload.activeCount)")
      if let typingInfo = payload.typingInfo {
        print(typingInfo)
      }
      for member in members {
        let state = member.isTyping ? "typing" : "idle"
        print("- \(member.userID) id=\(member.presenceID ?? "missing") \(state)")
      }
      print("transport: \(payload.transport)")
      print("cache: \(context.cacheURL.path)")

    case .json:
      try writeJSON(payload)

    case .jsonl:
      try writeJSONLine(
        EvidenceRow(
          caseID: "cli.examples.typing-indicator",
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
            caseID: "cli.examples.typing-indicator",
            side: "swift",
            event: member.isTyping ? "typing-member" : "idle-member",
            appID: context.appID,
            entityID: member.userID,
            ok: true,
            details: member
          )
        )
      }
    }
  }

  private static func runAvatarStack(
    leaf: CLIExamplesAvatarStackLeafInvocation,
    output: OutputMode
  ) async throws {
    if case let .unknown(command) = leaf {
      throw CLIError("Unknown avatar stack command: \(command). \(avatarStackUsage)", exitCode: 64)
    }

    let context = try await CLIContext.bootstrap(initialAttributes: [])
    switch leaf {
    case let .join(options):
      let name = options.name ?? AvatarStackRecipeExample.defaultName(forUserID: options.userID)
      _ = try await context.runtime.setPresence(
        room: AvatarStackRecipeExample.room,
        userID: options.userID,
        values: AvatarStackRecipeExample.presenceValues(name: name)
      )
      let members = try await context.runtime.roomPresence(room: AvatarStackRecipeExample.room)
      try printAvatarStack(
        context: context,
        output: output,
        event: "join",
        userID: options.userID,
        viewerUserID: options.userID,
        presence: members
      )

    case let .list(options):
      let members = try await context.runtime.roomPresence(room: AvatarStackRecipeExample.room)
      try printAvatarStack(
        context: context,
        output: output,
        event: "list",
        userID: nil,
        viewerUserID: options.viewerUserID,
        presence: members
      )

    case let .watch(options):
      let members = try await firstWatchSnapshot(
        from: context.runtime.observeRoomPresence(room: AvatarStackRecipeExample.room),
        operation: "avatar stack watch",
        eventCount: options.eventCount
      )
      try printAvatarStack(
        context: context,
        output: output,
        event: "watch",
        userID: nil,
        viewerUserID: options.viewerUserID,
        presence: members
      )

    case let .leave(userID):
      let leftUserID = try await context.runtime.leavePresence(
        room: AvatarStackRecipeExample.room,
        userID: userID
      )
      let members = try await context.runtime.roomPresence(room: AvatarStackRecipeExample.room)
      try printAvatarStack(
        context: context,
        output: output,
        event: "leave",
        userID: leftUserID,
        viewerUserID: leftUserID,
        presence: members
      )

    case .unknown:
      preconditionFailure("Unknown avatar stack commands are handled before bootstrapping.")
    }
  }

  private static func printAvatarStack(
    context: CLIContext,
    output: OutputMode,
    event: String,
    userID: String?,
    viewerUserID: String?,
    presence: [InstantRoomPresenceMember]
  ) throws {
    let snapshot = AvatarStackRecipeExample.snapshot(
      from: presence,
      viewerUserID: viewerUserID
    )
    let payload = AvatarStackRecipeOutput(
      appID: context.appID,
      cachePath: context.cacheURL.path,
      event: event,
      userID: userID,
      viewerUserID: viewerUserID,
      transport: "not-implemented-local-cache-only",
      room: AvatarStackRecipeExample.room,
      nameKey: AvatarStackRecipeExample.nameKey,
      memberCount: snapshot.members.count,
      peerCount: snapshot.peers.count,
      onlineCount: snapshot.onlineCount,
      currentUser: snapshot.currentUser,
      peers: snapshot.peers,
      members: snapshot.members
    )

    switch output {
    case .human:
      print("room: \(payload.room.type)/\(payload.room.id)")
      if let userID {
        print("user: \(userID)")
      }
      if let viewerUserID {
        print("viewer: \(viewerUserID)")
      }
      print("members: \(payload.memberCount)")
      print("online: \(payload.onlineCount)")
      if let currentUser = payload.currentUser {
        print("current: \(currentUser.name) (\(currentUser.userID))")
      }
      for peer in payload.peers {
        print("- \(peer.name) (\(peer.userID))")
      }
      print("transport: \(payload.transport)")
      print("cache: \(context.cacheURL.path)")

    case .json:
      try writeJSON(payload)

    case .jsonl:
      try writeJSONLine(
        EvidenceRow(
          caseID: "cli.examples.avatar-stack",
          side: "swift",
          event: event,
          appID: context.appID,
          entityID: userID,
          ok: true,
          details: payload
        )
      )
      for member in snapshot.members {
        try writeJSONLine(
          EvidenceRow(
            caseID: "cli.examples.avatar-stack",
            side: "swift",
            event: member.isViewer ? "current-user" : "avatar-member",
            appID: context.appID,
            entityID: member.userID,
            ok: true,
            details: member
          )
        )
      }
    }
  }

  private enum CursorsRecipeKind {
    case plain
    case custom

    var room: InstantRoomHandle {
      switch self {
      case .plain:
        return CursorsRecipeExample.room
      case .custom:
        return CursorsRecipeExample.customRoom
      }
    }

    var caseID: String {
      switch self {
      case .plain:
        return "cli.examples.cursors"
      case .custom:
        return "cli.examples.custom-cursors"
      }
    }

    var commandName: String {
      switch self {
      case .plain:
        return "cursors"
      case .custom:
        return "custom cursors"
      }
    }

    var usage: String {
      switch self {
      case .plain:
        return InstantSwiftDataCLI.cursorsUsage
      case .custom:
        return InstantSwiftDataCLI.customCursorsUsage
      }
    }

    var nameKey: String? {
      switch self {
      case .plain:
        return nil
      case .custom:
        return CursorsRecipeExample.nameKey
      }
    }
  }

  private static func runCursors(
    leaf: CLIExamplesCursorsLeafInvocation,
    output: OutputMode
  ) async throws {
    try await runCursorsRecipe(kind: .plain, leaf: leaf, output: output)
  }

  private static func runCustomCursors(
    leaf: CLIExamplesCursorsLeafInvocation,
    output: OutputMode
  ) async throws {
    try await runCursorsRecipe(kind: .custom, leaf: leaf, output: output)
  }

  private static func runCursorsRecipe(
    kind: CursorsRecipeKind,
    leaf invocation: CLIExamplesCursorsLeafInvocation,
    output: OutputMode
  ) async throws {
    if case let .unknown(command) = invocation {
      throw CLIError("Unknown \(kind.commandName) command: \(command). \(kind.usage)", exitCode: 64)
    }

    let context = try await CLIContext.bootstrap(initialAttributes: [])
    switch invocation {
    case let .move(options):
      var values = CursorsRecipeExample.cursorValues(
        room: kind.room,
        x: options.x,
        y: options.y,
        xPercent: options.xPercent,
        yPercent: options.yPercent,
        color: options.color ?? CursorsRecipeExample.defaultColor
      )
      if kind.nameKey != nil {
        values[CursorsRecipeExample.nameKey] = .string(options.name ?? options.userID)
      }
      _ = try await context.runtime.setPresence(
        room: kind.room,
        userID: options.userID,
        values: values
      )
      let members = try await context.runtime.roomPresence(room: kind.room)
      try printCursors(
        context: context,
        kind: kind,
        output: output,
        event: "move",
        userID: options.userID,
        viewerUserID: options.userID,
        presence: members
      )

    case let .list(options):
      let members = try await context.runtime.roomPresence(room: kind.room)
      try printCursors(
        context: context,
        kind: kind,
        output: output,
        event: "list",
        userID: nil,
        viewerUserID: options.viewerUserID,
        presence: members
      )

    case let .watch(options):
      let members = try await firstWatchSnapshot(
        from: context.runtime.observeRoomPresence(room: kind.room),
        operation: "\(kind.commandName) watch",
        eventCount: options.eventCount
      )
      try printCursors(
        context: context,
        kind: kind,
        output: output,
        event: "watch",
        userID: nil,
        viewerUserID: options.viewerUserID,
        presence: members
      )

    case let .clear(userID):
      let values = try await clearedCursorsPresenceValues(
        context: context,
        kind: kind,
        userID: userID
      )
      _ = try await context.runtime.setPresence(
        room: kind.room,
        userID: userID,
        values: values
      )
      let members = try await context.runtime.roomPresence(room: kind.room)
      try printCursors(
        context: context,
        kind: kind,
        output: output,
        event: "clear",
        userID: userID,
        viewerUserID: userID,
        presence: members
      )

    case let .leave(userID):
      let leftUserID = try await context.runtime.leavePresence(
        room: kind.room,
        userID: userID
      )
      let members = try await context.runtime.roomPresence(room: kind.room)
      try printCursors(
        context: context,
        kind: kind,
        output: output,
        event: "leave",
        userID: leftUserID,
        viewerUserID: leftUserID,
        presence: members
      )

    case .unknown:
      preconditionFailure("Unknown cursor commands are handled before bootstrapping.")
    }
  }

  private static func clearedCursorsPresenceValues(
    context: CLIContext,
    kind: CursorsRecipeKind,
    userID: String
  ) async throws -> [String: JSONValue] {
    guard kind.nameKey != nil else {
      return [:]
    }

    let members = try await context.runtime.roomPresence(room: kind.room)
    let existingName = members.first { $0.userID == userID }
      .flatMap { member -> String? in
        guard case let .string(name)? = member.values[CursorsRecipeExample.nameKey] else {
          return nil
        }
        return name
      }
    return [CursorsRecipeExample.nameKey: .string(existingName ?? userID)]
  }

  private static func printCursors(
    context: CLIContext,
    kind: CursorsRecipeKind,
    output: OutputMode,
    event: String,
    userID: String?,
    viewerUserID: String?,
    presence: [InstantRoomPresenceMember]
  ) throws {
    let snapshot = CursorsRecipeExample.snapshot(
      from: presence,
      room: kind.room,
      viewerUserID: viewerUserID
    )
    let payload = CursorsRecipeOutput(
      appID: context.appID,
      cachePath: context.cacheURL.path,
      event: event,
      userID: userID,
      viewerUserID: viewerUserID,
      transport: "not-implemented-local-cache-only",
      room: kind.room,
      spaceID: CursorsRecipeExample.spaceID(for: kind.room),
      nameKey: kind.nameKey,
      memberCount: snapshot.members.count,
      cursorCount: snapshot.cursorCount,
      visibleCursors: snapshot.visibleCursors,
      members: snapshot.members
    )

    switch output {
    case .human:
      print("room: \(payload.room.type)/\(payload.room.id)")
      print("space: \(payload.spaceID)")
      if let nameKey = payload.nameKey {
        print("name key: \(nameKey)")
      }
      if let userID {
        print("user: \(userID)")
      }
      if let viewerUserID {
        print("viewer: \(viewerUserID)")
      }
      print("members: \(payload.memberCount)")
      print("visible cursors: \(payload.cursorCount)")
      for cursor in payload.visibleCursors {
        var suffix = "(\(cursor.xPercent)%, \(cursor.yPercent)%)"
        if let color = cursor.color {
          suffix += " \(color)"
        }
        if let name = cursor.name {
          suffix += " \(name)"
        }
        print("- \(cursor.userID) \(suffix)")
      }
      print("transport: \(payload.transport)")
      print("cache: \(context.cacheURL.path)")

    case .json:
      try writeJSON(payload)

    case .jsonl:
      try writeJSONLine(
        EvidenceRow(
          caseID: kind.caseID,
          side: "swift",
          event: event,
          appID: context.appID,
          entityID: userID,
          ok: true,
          details: payload
        )
      )
      for cursor in snapshot.visibleCursors {
        try writeJSONLine(
          EvidenceRow(
            caseID: kind.caseID,
            side: "swift",
            event: cursor.isViewer ? "current-cursor" : "cursor-member",
            appID: context.appID,
            entityID: cursor.userID,
            ok: true,
            details: cursor
          )
        )
      }
    }
  }

  private static func runMergeTileGame(
    leaf invocation: CLIExamplesMergeTileGameLeafInvocation,
    output: OutputMode
  ) async throws {
    if case let .unknown(command) = invocation {
      throw CLIError(
        "Unknown merge tile game command: \(command). \(mergeTileGameUsage)",
        exitCode: 64
      )
    }

    let context = try await CLIContext.bootstrap(
      initialAttributes: MergeTileGameRecipeExample.attributes
    )
    switch invocation {
    case let .join(options):
      _ = try await ensureMergeTileGameBoard(context: context)
      let members = try await context.runtime.roomPresence(room: MergeTileGameRecipeExample.room)
      let players = MergeTileGameRecipeExample.players(from: members)
      let existingColor = players.first { $0.userID == options.userID }?.color
      let color = try mergeTileGameColor(
        requestedColor: options.color,
        fallbackColor: existingColor,
        players: players,
        usage: CLIExamplesMergeTileGameUsage.join
      )
      _ = try await context.runtime.setPresence(
        room: MergeTileGameRecipeExample.room,
        userID: options.userID,
        values: MergeTileGameRecipeExample.presenceValues(color: color)
      )
      try await printMergeTileGame(
        context: context,
        output: output,
        event: "join",
        userID: options.userID,
        viewerUserID: options.userID
      )

    case let .tap(options):
      guard MergeTileGameRecipeExample.isValidCell(row: options.row, column: options.column) else {
        throw CLIError("\(CLIExamplesMergeTileGameUsage.tap): row and column must be 0...3.", exitCode: 64)
      }
      _ = try await ensureMergeTileGameBoard(context: context)
      let members = try await context.runtime.roomPresence(room: MergeTileGameRecipeExample.room)
      let players = MergeTileGameRecipeExample.players(from: members)
      let existingColor = players.first { $0.userID == options.userID }?.color
      let color = try mergeTileGameColor(
        requestedColor: options.color,
        fallbackColor: existingColor,
        players: players,
        usage: CLIExamplesMergeTileGameUsage.tap
      )
      _ = try await context.runtime.setPresence(
        room: MergeTileGameRecipeExample.room,
        userID: options.userID,
        values: MergeTileGameRecipeExample.presenceValues(color: color)
      )
      let transactionID = context.runtime.configuration.makeID()
      let now = context.runtime.configuration.now()
      try await context.runtime.transact(
        InstantStoreTransaction(
          id: transactionID,
          operations: MergeTileGameRecipeExample.tapOperations(
            row: options.row,
            column: options.column,
            color: color,
            transactionID: transactionID,
            updatedAt: now
          )
        ),
        createdAt: now,
        source: "cli.examples.merge-tile-game.tap"
      )
      try await printMergeTileGame(
        context: context,
        output: output,
        event: "tap",
        userID: options.userID,
        viewerUserID: options.userID
      )

    case let .board(options):
      _ = try await ensureMergeTileGameBoard(context: context)
      try await printMergeTileGame(
        context: context,
        output: output,
        event: "board",
        userID: nil,
        viewerUserID: options.viewerUserID
      )

    case let .watch(options):
      _ = try await ensureMergeTileGameBoard(context: context)
      _ = try await firstWatchSnapshot(
        from: context.runtime.observeRoomPresence(room: MergeTileGameRecipeExample.room),
        operation: "merge tile game watch",
        eventCount: options.eventCount
      )
      try await printMergeTileGame(
        context: context,
        output: output,
        event: "watch",
        userID: nil,
        viewerUserID: options.viewerUserID
      )

    case .reset:
      let transactionID = context.runtime.configuration.makeID()
      let now = context.runtime.configuration.now()
      try await context.runtime.transact(
        InstantStoreTransaction(
          id: transactionID,
          operations: MergeTileGameRecipeExample.resetBoardOperations(
            transactionID: transactionID,
            updatedAt: now
          )
        ),
        createdAt: now,
        source: "cli.examples.merge-tile-game.reset"
      )
      try await printMergeTileGame(
        context: context,
        output: output,
        event: "reset",
        userID: nil,
        viewerUserID: nil
      )

    case let .leave(userID):
      let leftUserID = try await context.runtime.leavePresence(
        room: MergeTileGameRecipeExample.room,
        userID: userID
      )
      _ = try await ensureMergeTileGameBoard(context: context)
      try await printMergeTileGame(
        context: context,
        output: output,
        event: "leave",
        userID: leftUserID,
        viewerUserID: leftUserID
      )

    case .unknown:
      preconditionFailure("Unknown merge tile game commands are handled before bootstrapping.")
    }
  }

  private static func ensureMergeTileGameBoard(context: CLIContext) async throws
    -> MergeTileGameBoard
  {
    if let board = try await currentMergeTileGameBoard(context: context) {
      return board
    }
    let transactionID = context.runtime.configuration.makeID()
    let now = context.runtime.configuration.now()
    try await context.runtime.transact(
      InstantStoreTransaction(
        id: transactionID,
        operations: MergeTileGameRecipeExample.createBoardOperations(
          transactionID: transactionID,
          createdAt: now
        )
      ),
      createdAt: now,
      source: "cli.examples.merge-tile-game.create-board"
    )
    guard let board = try await currentMergeTileGameBoard(context: context) else {
      throw CLIError("Merge tile game board was not created.", exitCode: 70)
    }
    return board
  }

  private static func currentMergeTileGameBoard(context: CLIContext) async throws
    -> MergeTileGameBoard?
  {
    try MergeTileGameRecipeExample.decodeBoards(
      (try await context.runtime.queryOnce(MergeTileGameRecipeExample.boardQuery)).values
    ).first
  }

  private static func mergeTileGameColor(
    requestedColor: String?,
    fallbackColor: String?,
    players: [MergeTileGamePlayer],
    usage: String
  ) throws -> String {
    if let requestedColor {
      guard MergeTileGameRecipeExample.colors.contains(requestedColor) else {
        throw CLIError("Invalid merge tile game color: \(requestedColor). \(usage)", exitCode: 64)
      }
      return requestedColor
    }
    if let fallbackColor {
      return fallbackColor
    }
    return MergeTileGameRecipeExample.selectedColor(requestedColor: nil, players: players)
  }

  private static func printMergeTileGame(
    context: CLIContext,
    output: OutputMode,
    event: String,
    userID: String?,
    viewerUserID: String?
  ) async throws {
    let board = try await currentMergeTileGameBoard(context: context)
    let presence = try await context.runtime.roomPresence(room: MergeTileGameRecipeExample.room)
    let snapshot = MergeTileGameRecipeExample.snapshot(
      board: board,
      presence: presence,
      viewerUserID: viewerUserID
    )
    let cells = mergeTileGamePaintedCells(board: board)
    let payload = MergeTileGameRecipeOutput(
      appID: context.appID,
      cachePath: context.cacheURL.path,
      event: event,
      userID: userID,
      viewerUserID: viewerUserID,
      transport: "not-implemented-local-cache-only",
      room: MergeTileGameRecipeExample.room,
      boardID: MergeTileGameRecipeExample.boardID,
      boardSize: MergeTileGameRecipeExample.boardSize,
      emptyColor: MergeTileGameRecipeExample.emptyColor,
      colors: MergeTileGameRecipeExample.colors,
      colorKey: MergeTileGameRecipeExample.colorKey,
      playerCount: snapshot.playerCount,
      filledCount: board?.filledCount ?? 0,
      currentPlayer: snapshot.currentPlayer,
      peers: snapshot.peers,
      players: snapshot.players,
      availableColors: snapshot.availableColors,
      board: board,
      paintedCells: cells
    )

    switch output {
    case .human:
      print("room: \(payload.room.type)/\(payload.room.id)")
      print("board: \(payload.boardID)")
      if let userID {
        print("user: \(userID)")
      }
      if let viewerUserID {
        print("viewer: \(viewerUserID)")
      }
      print("players: \(payload.playerCount)")
      if let currentPlayer = payload.currentPlayer {
        print("current: \(currentPlayer.userID) \(currentPlayer.color)")
      }
      for peer in payload.peers {
        print("- \(peer.userID) \(peer.color)")
      }
      if let board = payload.board {
        for row in 0..<payload.boardSize {
          let colors = (0..<payload.boardSize).map { column in
            board.state[MergeTileGameRecipeExample.cellKey(row: row, column: column)]
              ?? payload.emptyColor
          }
          print(colors.joined(separator: " "))
        }
      }
      print("filled: \(payload.filledCount)")
      print("transport: \(payload.transport)")
      print("cache: \(context.cacheURL.path)")

    case .json:
      try writeJSON(payload)

    case .jsonl:
      try writeJSONLine(
        EvidenceRow(
          caseID: "cli.examples.merge-tile-game",
          side: "swift",
          event: event,
          appID: context.appID,
          entityID: userID ?? payload.boardID,
          ok: true,
          details: payload
        )
      )
      for player in snapshot.players {
        try writeJSONLine(
          EvidenceRow(
            caseID: "cli.examples.merge-tile-game",
            side: "swift",
            event: player.isViewer ? "current-player" : "player",
            appID: context.appID,
            entityID: player.userID,
            ok: true,
            details: player
          )
        )
      }
      for cell in cells {
        try writeJSONLine(
          EvidenceRow(
            caseID: "cli.examples.merge-tile-game",
            side: "swift",
            event: "painted-cell",
            appID: context.appID,
            entityID: cell.key,
            ok: true,
            details: cell
          )
        )
      }
    }
  }

  private static func mergeTileGamePaintedCells(board: MergeTileGameBoard?)
    -> [MergeTileGameCellOutput]
  {
    guard let board else { return [] }
    return (0..<MergeTileGameRecipeExample.boardSize).flatMap { row in
      (0..<MergeTileGameRecipeExample.boardSize).compactMap { column in
        let key = MergeTileGameRecipeExample.cellKey(row: row, column: column)
        let color = board.state[key] ?? MergeTileGameRecipeExample.emptyColor
        guard color != MergeTileGameRecipeExample.emptyColor else {
          return nil
        }
        return MergeTileGameCellOutput(
          boardID: board.id,
          key: key,
          row: row,
          column: column,
          color: color
        )
      }
    }
  }

  private static func runStroopwafel(
    leaf invocation: CLIExamplesStroopwafelLeafInvocation,
    output: OutputMode
  ) async throws {
    if case let .unknown(command) = invocation {
      throw CLIError("Unknown Stroopwafel command: \(command). \(stroopwafelUsage)", exitCode: 64)
    }

    let context = try await CLIContext.bootstrap(initialAttributes: StroopwafelExample.attributes)

    switch invocation {
    case let .setupProfile(handle):
      let session = try await requireStroopwafelAuthSession(
        context: context,
        operation: "set up a profile"
      )
      let normalizedHandle = try normalizedStroopwafelHandle(handle)
      let existingUser = try await currentStroopwafelUsers(context: context)
        .first { $0.id == session.userID }
      let transactionID = context.runtime.configuration.makeID()
      let now = context.runtime.configuration.now()
      try await context.runtime.transact(
        InstantStoreTransaction(
          id: transactionID,
          operations: StroopwafelExample.setupProfileOperations(
            userID: session.userID,
            handle: normalizedHandle,
            email: stroopwafelEmail(for: session),
            highScore: existingUser == nil ? 0 : nil,
            createdAt: existingUser == nil ? stroopwafelISOString(from: now) : nil,
            transactionID: transactionID,
            updatedAt: now
          )
        ),
        createdAt: now,
        source: "cli.examples.stroopwafel.setup-profile"
      )
      try await printStroopwafel(
        context: context,
        output: output,
        event: "setup-profile",
        changedID: session.userID,
        selectedUserID: session.userID
      )

    case let .profile(userID):
      let selectedUserID = try await selectedStroopwafelUserID(
        context: context,
        explicitUserID: userID
      )
      let user = try await requireStroopwafelUser(context: context, userID: selectedUserID)
      try await printStroopwafel(
        context: context,
        output: output,
        event: "profile",
        selectedUserID: selectedUserID,
        selectedUser: user
      )

    case let .score(score):
      let user = try await requireCurrentStroopwafelUser(context: context, operation: "save score")
      let currentHighScore = user.highScore ?? 0
      if score > currentHighScore {
        let transactionID = context.runtime.configuration.makeID()
        let now = context.runtime.configuration.now()
        try await context.runtime.transact(
          InstantStoreTransaction(
            id: transactionID,
            operations: StroopwafelExample.updateHighScoreOperations(
              userID: user.id,
              score: score,
              transactionID: transactionID,
              updatedAt: now
            )
          ),
          createdAt: now,
          source: "cli.examples.stroopwafel.score"
        )
      }
      try await printStroopwafel(
        context: context,
        output: output,
        event: "score",
        changedID: user.id,
        selectedUserID: user.id
      )

    case let .createRoom(explicitCode):
      let user = try await requireCurrentStroopwafelUser(context: context, operation: "create a room")
      let code = try await availableStroopwafelRoomCode(context: context, explicitCode: explicitCode)
      let roomID = context.runtime.configuration.makeID()
      let transactionID = context.runtime.configuration.makeID()
      let now = context.runtime.configuration.now()
      try await context.runtime.transact(
        InstantStoreTransaction(
          id: transactionID,
          operations: StroopwafelExample.createRoomOperations(
            id: roomID,
            code: code,
            hostID: user.id,
            createdAt: stroopwafelISOString(from: now),
            transactionID: transactionID,
            updatedAt: now
          )
        ),
        createdAt: now,
        source: "cli.examples.stroopwafel.create-room"
      )
      let room = try await requireStroopwafelRoom(context: context, code: code)
      try await printStroopwafel(
        context: context,
        output: output,
        event: "create-room",
        changedID: roomID,
        selectedUserID: user.id,
        selectedRoomCode: code,
        selectedRoom: room
      )

    case .rooms:
      try await printStroopwafel(context: context, output: output, event: "rooms")

    case let .room(code):
      let room = try await requireStroopwafelRoom(context: context, code: code)
      try await printStroopwafel(
        context: context,
        output: output,
        event: "room",
        selectedRoomCode: room.code,
        selectedRoom: room,
        selectedGameID: room.currentGameID
      )

    case let .join(code):
      let user = try await requireCurrentStroopwafelUser(context: context, operation: "join a room")
      let room = try await requireStroopwafelRoom(context: context, code: code)
      try validateStroopwafelCanJoin(room: room, userID: user.id)
      let transactionID = context.runtime.configuration.makeID()
      let now = context.runtime.configuration.now()
      try await context.runtime.transact(
        InstantStoreTransaction(
          id: transactionID,
          operations: StroopwafelExample.joinRoomOperations(
            room: room,
            userID: user.id,
            transactionID: transactionID,
            updatedAt: now
          )
        ),
        createdAt: now,
        source: "cli.examples.stroopwafel.join"
      )
      try await printStroopwafel(
        context: context,
        output: output,
        event: "join",
        changedID: user.id,
        selectedUserID: user.id,
        selectedRoomCode: room.code
      )

    case let .ready(code, isReady):
      let user = try await requireCurrentStroopwafelUser(context: context, operation: "mark ready")
      let room = try await requireStroopwafelRoom(context: context, code: code)
      try validateStroopwafelMembership(room: room, userID: user.id, operation: "mark ready")
      let transactionID = context.runtime.configuration.makeID()
      let now = context.runtime.configuration.now()
      try await context.runtime.transact(
        InstantStoreTransaction(
          id: transactionID,
          operations: StroopwafelExample.readyRoomOperations(
            room: room,
            userID: user.id,
            isReady: isReady,
            transactionID: transactionID,
            updatedAt: now
          )
        ),
        createdAt: now,
        source: "cli.examples.stroopwafel.ready"
      )
      try await printStroopwafel(
        context: context,
        output: output,
        event: isReady ? "ready" : "unready",
        changedID: user.id,
        selectedUserID: user.id,
        selectedRoomCode: room.code
      )

    case let .kick(code, userID):
      let host = try await requireCurrentStroopwafelUser(context: context, operation: "kick a player")
      let room = try await requireStroopwafelRoom(context: context, code: code)
      try validateStroopwafelHost(room: room, userID: host.id, operation: "kick a player")
      guard userID != host.id else {
        throw CLIError("Stroopwafel host cannot kick themselves.", exitCode: 77)
      }
      try validateStroopwafelMembership(room: room, userID: userID, operation: "kick a player")
      let transactionID = context.runtime.configuration.makeID()
      let now = context.runtime.configuration.now()
      try await context.runtime.transact(
        InstantStoreTransaction(
          id: transactionID,
          operations: StroopwafelExample.kickRoomOperations(
            room: room,
            userID: userID,
            transactionID: transactionID,
            updatedAt: now
          )
        ),
        createdAt: now,
        source: "cli.examples.stroopwafel.kick"
      )
      try await printStroopwafel(
        context: context,
        output: output,
        event: "kick",
        changedID: userID,
        selectedUserID: host.id,
        selectedRoomCode: room.code
      )

    case let .start(code):
      let host = try await requireCurrentStroopwafelUser(context: context, operation: "start a game")
      let room = try await requireStroopwafelRoom(context: context, code: code)
      try validateStroopwafelHost(room: room, userID: host.id, operation: "start a game")
      let playerIDs = stroopwafelPlayerIDs(in: room)
      guard !playerIDs.isEmpty else {
        throw CLIError("Stroopwafel room \(code) has no players.", exitCode: 66)
      }
      let gameID = context.runtime.configuration.makeID()
      let pointIDsByPlayerID = playerIDs.map {
        (pointID: context.runtime.configuration.makeID(), playerID: $0)
      }
      let transactionID = context.runtime.configuration.makeID()
      let now = context.runtime.configuration.now()
      try await context.runtime.transact(
        InstantStoreTransaction(
          id: transactionID,
          operations: StroopwafelExample.startGameOperations(
            room: room,
            gameID: gameID,
            pointIDsByPlayerID: pointIDsByPlayerID,
            colors: StroopwafelExample.generateGameColors(seed: gameID),
            createdAt: stroopwafelISOString(from: now),
            transactionID: transactionID,
            updatedAt: now
          )
        ),
        createdAt: now,
        source: "cli.examples.stroopwafel.start"
      )
      try await printStroopwafel(
        context: context,
        output: output,
        event: "start",
        changedID: gameID,
        selectedUserID: host.id,
        selectedRoomCode: room.code,
        selectedGameID: gameID
      )

    case .games:
      try await printStroopwafel(context: context, output: output, event: "games")

    case let .game(gameID):
      let game = try await requireStroopwafelGame(context: context, id: gameID)
      try await printStroopwafel(
        context: context,
        output: output,
        event: "game",
        selectedGameID: gameID,
        selectedGame: game
      )

    case let .tap(gameID, color):
      let user = try await requireCurrentStroopwafelUser(context: context, operation: "tap a color")
      let game = try await requireStroopwafelGame(context: context, id: gameID)
      try validateStroopwafelPlayer(game: game, userID: user.id)
      guard game.status == StroopwafelExample.gameInProgress else {
        throw CLIError("Stroopwafel game \(gameID) is not in progress.", exitCode: 77)
      }
      let transactionID = context.runtime.configuration.makeID()
      let now = context.runtime.configuration.now()
      let operations = StroopwafelExample.tapOperations(
        game: game,
        userID: user.id,
        selectedColor: color,
        transactionID: transactionID,
        updatedAt: now
      )
      guard !operations.isEmpty else {
        throw CLIError("Stroopwafel point row not found for user: \(user.id)", exitCode: 66)
      }
      try await context.runtime.transact(
        InstantStoreTransaction(id: transactionID, operations: operations),
        createdAt: now,
        source: "cli.examples.stroopwafel.tap"
      )
      try await printStroopwafel(
        context: context,
        output: output,
        event: "tap",
        changedID: user.id,
        selectedUserID: user.id,
        selectedGameID: gameID
      )

    case let .leave(code):
      let user = try await requireCurrentStroopwafelUser(context: context, operation: "leave a room")
      let room = try await requireStroopwafelRoom(context: context, code: code)
      try validateStroopwafelMembership(room: room, userID: user.id, operation: "leave a room")
      let transactionID = context.runtime.configuration.makeID()
      let now = context.runtime.configuration.now()
      try await context.runtime.transact(
        InstantStoreTransaction(
          id: transactionID,
          operations: StroopwafelExample.leaveRoomOperations(
            room: room,
            userID: user.id,
            deletedAt: stroopwafelISOString(from: now),
            transactionID: transactionID,
            updatedAt: now
          )
        ),
        createdAt: now,
        source: "cli.examples.stroopwafel.leave"
      )
      try await printStroopwafel(
        context: context,
        output: output,
        event: "leave",
        changedID: user.id,
        selectedUserID: user.id,
        selectedRoomCode: room.code
      )

    case .reset:
      let games = try await currentStroopwafelGames(context: context)
      let rooms = try await currentStroopwafelRooms(context: context)
      let gameAndRoomOperations =
        games.flatMap { StroopwafelExample.deleteGameOperations(id: $0.id) }
        + rooms.flatMap { StroopwafelExample.deleteRoomOperations(id: $0.id) }
      if !gameAndRoomOperations.isEmpty {
        let transactionID = context.runtime.configuration.makeID()
        let now = context.runtime.configuration.now()
        try await context.runtime.transact(
          InstantStoreTransaction(id: transactionID, operations: gameAndRoomOperations),
          createdAt: now,
          source: "cli.examples.stroopwafel.reset"
        )
      }
      let points = try await currentStroopwafelPoints(context: context)
      let pointOperations = points.flatMap {
        StroopwafelExample.deletePointOperations(id: $0.id)
      }
      if !pointOperations.isEmpty {
        let transactionID = context.runtime.configuration.makeID()
        let now = context.runtime.configuration.now()
        try await context.runtime.transact(
          InstantStoreTransaction(id: transactionID, operations: pointOperations),
          createdAt: now,
          source: "cli.examples.stroopwafel.reset.points"
        )
      }
      try await printStroopwafel(context: context, output: output, event: "reset")

    case .unknown:
      preconditionFailure("Unknown Stroopwafel commands are handled before bootstrapping.")
    }
  }

  private static func printStroopwafel(
    context: CLIContext,
    output: OutputMode,
    event: String,
    changedID: String? = nil,
    selectedUserID: String? = nil,
    selectedUser: StroopwafelUserRecord? = nil,
    selectedRoomCode: String? = nil,
    selectedRoom: StroopwafelRoomRecord? = nil,
    selectedGameID: String? = nil,
    selectedGame: StroopwafelGameRecord? = nil
  ) async throws {
    let users = try await currentStroopwafelUsers(context: context)
    let rooms = try await currentStroopwafelRooms(context: context)
    let games = try await currentStroopwafelGames(context: context)
    let points = try await currentStroopwafelPoints(context: context)
    let pending = await context.runtime.pendingMutations()
    let session = try await context.runtime.authSession()
    let resolvedSelectedRoom =
      selectedRoom
      ?? selectedRoomCode.flatMap { code in
        rooms.first { $0.code == StroopwafelExample.normalizeRoomCode(code) }
      }
    let resolvedSelectedGame =
      selectedGame
      ?? selectedGameID.flatMap { id in games.first { $0.id == id } }
    let resolvedSelectedUser =
      selectedUser
      ?? selectedUserID.flatMap { id in users.first { $0.id == id } }
    let payload = StroopwafelOutput(
      appID: context.appID,
      cachePath: context.cacheURL.path,
      event: event,
      changedID: changedID,
      selectedUserID: selectedUserID,
      selectedUser: resolvedSelectedUser,
      selectedRoomCode: resolvedSelectedRoom?.code ?? selectedRoomCode,
      selectedRoom: resolvedSelectedRoom,
      selectedGameID: resolvedSelectedGame?.id ?? selectedGameID,
      selectedGame: resolvedSelectedGame,
      authUserID: session?.userID,
      authIsGuest: session?.isGuest,
      transport: "not-implemented-local-cache-only",
      userQueryID: StroopwafelExample.usersQuery.id,
      roomQueryID: StroopwafelExample.roomsQuery.id,
      gameQueryID: StroopwafelExample.gamesQuery.id,
      pointQueryID: StroopwafelExample.pointsQuery.id,
      userCacheKey: StroopwafelExample.usersQuery.cacheKey,
      roomCacheKey: StroopwafelExample.roomsQuery.cacheKey,
      gameCacheKey: StroopwafelExample.gamesQuery.cacheKey,
      pointCacheKey: StroopwafelExample.pointsQuery.cacheKey,
      pendingMutationCount: pending.count,
      userCount: users.count,
      roomCount: rooms.count,
      gameCount: games.count,
      pointCount: points.count,
      users: users,
      rooms: rooms,
      games: games,
      points: points
    )

    switch output {
    case .human:
      if let user = payload.selectedUser {
        print(
          "profile: \(user.handle ?? "(no handle)") user=\(user.id) highScore=\(user.highScore ?? 0)"
        )
      }
      if rooms.isEmpty {
        print("No Stroopwafel rooms.")
      } else {
        for room in rooms {
          let code = room.code ?? "(deleted)"
          let handles = room.users.map { $0.handle ?? $0.id }.joined(separator: ",")
          print(
            "room \(room.id) code=\(code) host=\(room.hostID) ready=\(room.readyIDs.count) players=[\(handles)] currentGame=\(room.currentGameID ?? "none")"
          )
        }
      }
      if games.isEmpty {
        print("No Stroopwafel games.")
      } else {
        for game in games {
          let points = game.points
            .sorted { $0.userID < $1.userID }
            .map { "\($0.userID):\($0.value)" }
            .joined(separator: ",")
          print("game \(game.id) status=\(game.status) players=\(game.playerIDs.count) points=[\(points)]")
        }
      }
      if let authUserID = payload.authUserID {
        print("auth: \(payload.authIsGuest == true ? "guest" : "user") \(authUserID)")
      } else {
        print("auth: signed out")
      }
      print("transport: \(payload.transport)")
      print("pending mutations: \(pending.count)")
      print("cache: \(context.cacheURL.path)")

    case .json:
      try writeJSON(payload)

    case .jsonl:
      try writeJSONLine(
        EvidenceRow(
          caseID: "cli.examples.stroopwafel",
          side: "swift",
          event: event,
          appID: context.appID,
          entityID: changedID,
          ok: true,
          details: payload
        )
      )
      for user in users {
        try writeJSONLine(
          EvidenceRow(
            caseID: "cli.examples.stroopwafel",
            side: "swift",
            event: "user",
            appID: context.appID,
            entityID: user.id,
            ok: true,
            details: user
          )
        )
      }
      for room in rooms {
        try writeJSONLine(
          EvidenceRow(
            caseID: "cli.examples.stroopwafel",
            side: "swift",
            event: "room",
            appID: context.appID,
            entityID: room.id,
            ok: true,
            details: room
          )
        )
      }
      for game in games {
        try writeJSONLine(
          EvidenceRow(
            caseID: "cli.examples.stroopwafel",
            side: "swift",
            event: "game",
            appID: context.appID,
            entityID: game.id,
            ok: true,
            details: game
          )
        )
      }
      for point in points {
        try writeJSONLine(
          EvidenceRow(
            caseID: "cli.examples.stroopwafel",
            side: "swift",
            event: "point",
            appID: context.appID,
            entityID: point.id,
            ok: true,
            details: point
          )
        )
      }
    }
  }

  private static func currentStroopwafelUsers(context: CLIContext) async throws
    -> [StroopwafelUserRecord]
  {
    try StroopwafelExample.decodeUsers(
      (try await context.runtime.queryOnce(StroopwafelExample.usersQuery)).values
    )
    .filter { $0.handle != nil || $0.highScore != nil || $0.createdAt != nil }
  }

  private static func currentStroopwafelRooms(context: CLIContext) async throws
    -> [StroopwafelRoomRecord]
  {
    try StroopwafelExample.decodeRooms(
      (try await context.runtime.queryOnce(StroopwafelExample.roomsQuery)).values
    )
  }

  private static func currentStroopwafelGames(context: CLIContext) async throws
    -> [StroopwafelGameRecord]
  {
    try StroopwafelExample.decodeGames(
      (try await context.runtime.queryOnce(StroopwafelExample.gamesQuery)).values
    )
  }

  private static func currentStroopwafelPoints(context: CLIContext) async throws
    -> [StroopwafelPointRecord]
  {
    try StroopwafelExample.decodePoints(
      (try await context.runtime.queryOnce(StroopwafelExample.pointsQuery)).values
    )
  }

  private static func selectedStroopwafelUserID(
    context: CLIContext,
    explicitUserID: String?
  ) async throws -> String {
    if let explicitUserID {
      return explicitUserID
    }
    let session = try await requireStroopwafelAuthSession(
      context: context,
      operation: "view a profile"
    )
    return session.userID
  }

  private static func requireStroopwafelAuthSession(
    context: CLIContext,
    operation: String
  ) async throws -> InstantAuthSession {
    guard let session = try await context.runtime.authSession() else {
      throw CLIError(
        """
        Stroopwafel \(operation) requires a signed-in user. Run \
        'instant-swift-data auth guest' or \
        'instant-swift-data auth token <refresh-token> --user-id <user-id>' first.
        """,
        exitCode: 65
      )
    }
    return session
  }

  private static func requireStroopwafelUser(
    context: CLIContext,
    userID: String
  ) async throws -> StroopwafelUserRecord {
    guard
      let user = try StroopwafelExample.decodeUsers(
        (try await context.runtime.queryOnce(StroopwafelExample.userQuery(userID))).values
      )
      .first
    else {
      throw CLIError("Stroopwafel profile not found for user: \(userID).", exitCode: 66)
    }
    return user
  }

  private static func requireCurrentStroopwafelUser(
    context: CLIContext,
    operation: String
  ) async throws -> StroopwafelUserRecord {
    let session = try await requireStroopwafelAuthSession(context: context, operation: operation)
    do {
      let user = try await requireStroopwafelUser(context: context, userID: session.userID)
      guard user.handle != nil else {
        throw CLIError("Stroopwafel profile has no handle for user: \(session.userID).", exitCode: 66)
      }
      return user
    } catch let error as CLIError where error.exitCode == 66 {
      throw CLIError(
        """
        Stroopwafel profile not found for user: \(session.userID). Run \
        'instant-swift-data examples stroopwafel setup-profile <handle>' first.
        """,
        exitCode: 66
      )
    }
  }

  private static func requireStroopwafelRoom(
    context: CLIContext,
    code rawCode: String
  ) async throws -> StroopwafelRoomRecord {
    let code = StroopwafelExample.normalizeRoomCode(rawCode)
    guard !code.isEmpty else {
      throw CLIError("Invalid Stroopwafel room code: \(rawCode)", exitCode: 64)
    }
    let rooms = try StroopwafelExample.decodeRooms(
      (try await context.runtime.queryOnce(StroopwafelExample.roomForCodeQuery(code))).values
    )
    guard let room = rooms.first else {
      throw CLIError("Stroopwafel room not found for code: \(code)", exitCode: 66)
    }
    return room
  }

  private static func requireStroopwafelGame(
    context: CLIContext,
    id: String
  ) async throws -> StroopwafelGameRecord {
    guard
      let game = try StroopwafelExample.decodeGames(
        (try await context.runtime.queryOnce(StroopwafelExample.gameQuery(id))).values
      )
      .first
    else {
      throw CLIError("Stroopwafel game not found: \(id)", exitCode: 66)
    }
    return game
  }

  private static func validateStroopwafelCanJoin(
    room: StroopwafelRoomRecord,
    userID: String
  ) throws {
    guard !room.kickedIDs.contains(userID) else {
      throw CLIError(
        "User \(userID) was kicked from Stroopwafel room \(room.code ?? room.id).",
        exitCode: 77
      )
    }
    guard room.deletedAt == nil, room.code != nil else {
      throw CLIError("Stroopwafel room \(room.id) has been deleted.", exitCode: 66)
    }
  }

  private static func validateStroopwafelMembership(
    room: StroopwafelRoomRecord,
    userID: String,
    operation: String
  ) throws {
    guard room.users.contains(where: { $0.id == userID }) else {
      throw CLIError(
        "User \(userID) must be in Stroopwafel room \(room.code ?? room.id) to \(operation).",
        exitCode: 77
      )
    }
  }

  private static func validateStroopwafelHost(
    room: StroopwafelRoomRecord,
    userID: String,
    operation: String
  ) throws {
    guard room.hostID == userID else {
      throw CLIError(
        "User \(userID) must host Stroopwafel room \(room.code ?? room.id) to \(operation).",
        exitCode: 77
      )
    }
  }

  private static func validateStroopwafelPlayer(
    game: StroopwafelGameRecord,
    userID: String
  ) throws {
    guard game.playerIDs.contains(userID) else {
      throw CLIError("User \(userID) is a spectator in Stroopwafel game \(game.id).", exitCode: 77)
    }
  }

  private static func stroopwafelPlayerIDs(in room: StroopwafelRoomRecord) -> [String] {
    room.users.map(\.id).filter { $0 == room.hostID || room.readyIDs.contains($0) }
  }

  private static func availableStroopwafelRoomCode(
    context: CLIContext,
    explicitCode: String?
  ) async throws -> String {
    let rawCode = explicitCode ?? String(context.runtime.configuration.makeID().prefix(8))
    let code = StroopwafelExample.normalizeRoomCode(rawCode)
    guard !code.isEmpty else {
      throw CLIError("Invalid Stroopwafel room code: \(rawCode)", exitCode: 64)
    }
    let existing = try StroopwafelExample.decodeRooms(
      (try await context.runtime.queryOnce(StroopwafelExample.roomForCodeQuery(code))).values
    )
    guard existing.isEmpty else {
      throw CLIError("Stroopwafel room already exists for code: \(code)", exitCode: 77)
    }
    return code
  }

  private static func normalizedStroopwafelHandle(_ value: String) throws -> String {
    let handle = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard StroopwafelExample.isValidHandle(handle) else {
      throw CLIError(
        "Invalid Stroopwafel handle: \(value). Handles must be 3-16 alphanumeric characters.",
        exitCode: 64
      )
    }
    return handle
  }

  private static func stroopwafelEmail(for session: InstantAuthSession) -> String? {
    let prefix = "email:"
    guard session.userID.hasPrefix(prefix) else { return nil }
    let email = String(session.userID.dropFirst(prefix.count))
      .trimmingCharacters(in: .whitespacesAndNewlines)
    return email.contains("@") ? email : nil
  }

  private static func stroopwafelISOString(from timestamp: InstantTimestamp) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.string(from: Date(timeIntervalSince1970: Double(timestamp.milliseconds) / 1000))
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
    syncUpID: String? = nil,
    recording: SyncUpRecordingSummary? = nil
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
      meetings: meetings,
      recording: recording
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
      if let recording {
        print(
          "recording: auth=\(recording.authorizationStatus?.rawValue ?? "unknown") "
            + "speechResults=\(recording.speechResultCount) "
            + "sounds=\(recording.soundEffectPlayCount) "
            + "seconds=\(recording.secondsElapsed) transcript=\(recording.transcript)"
        )
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
        schema generate --example todos|validation [--to instant.schema.ts] [--json|--jsonl]
        schema verify --example todos|validation --from instant.schema.ts [--json|--jsonl]
        perms generate --example todos|validation [--to instant.perms.ts] [--json|--jsonl]
        perms verify --example todos|validation --from instant.perms.ts [--json|--jsonl]
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
        examples avatar-stack <join|list|watch|leave> [--json|--jsonl]
        examples cursors <move|list|watch|clear|leave> [--json|--jsonl]
        examples custom-cursors <move|list|watch|clear|leave> [--json|--jsonl]
        examples counters seed [--json|--jsonl]
        examples counters add [--count n] [--json|--jsonl]
        examples counters list [--json|--jsonl]
        examples counters increment <counter-id> [--json|--jsonl]
        examples counters decrement <counter-id> [--json|--jsonl]
        examples counters delete <counter-id> [--json|--jsonl]
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
        validation reminders [--json|--jsonl]
        validation server-transaction-loopback [--json|--jsonl]
        validation typed-drafts [--json|--jsonl]
        validation platform-adapters [--json|--jsonl]
        validation syncups-recording [--json|--jsonl]
        validation parity-report [--json|--jsonl]
        validation coverage [--json|--jsonl]
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

  private static func schemaExample(named rawName: String) throws -> CLISchemaExample {
    switch rawName {
    case "todos":
      return CLISchemaExample(
        name: "todos",
        schema: InstantSchemaExamples.todosDocument,
        permissions: InstantSchemaExamples.todoPermissions
      )

    case "validation":
      return CLISchemaExample(
        name: "validation",
        schema: InstantSchemaExamples.validationDocument,
        permissions: InstantSchemaExamples.validationPermissions
      )

    default:
      throw CLIError(
        "Unsupported --example '\(rawName)'. Available examples: todos, validation.",
        exitCode: 64
      )
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

  private static func verifySchema(
    options: SchemaVerifyOptions,
    example: CLISchemaExample,
    output: OutputMode
  ) throws {
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

    let expected = ParsedInstantSchemaDocument(example.schema)
    guard parsed == expected else {
      throw CLIError("Schema does not match --example \(example.name).", exitCode: 66)
    }

    let summary = SchemaVerifyOutput(
      example: example.name,
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
    example: CLISchemaExample,
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

    let expected = example.permissions
    guard parsed == expected else {
      throw CLIError("Permissions do not match --example \(example.name).", exitCode: 66)
    }

    let summary = PermissionsVerifyOutput(
      example: example.name,
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

  private static func printRemindersValidation(
    result: RemindersValidationResult,
    output: OutputMode
  ) throws {
    let finalDetails = result.evidence.last?.details
    let summary = RemindersValidationOutput(
      appID: result.appID,
      cachePath: result.cacheURL.path,
      event: "reminders",
      transport: "not-implemented-local-cache-only",
      ok: result.evidence.allSatisfy { $0.ok },
      evidenceCount: result.evidence.count,
      events: result.evidence.map(\.event),
      listCount: finalDetails?.listIDs.count ?? 0,
      reminderCount: finalDetails?.reminderIDs.count ?? 0,
      completedReminderCount: finalDetails?.completedReminderIDs.count ?? 0,
      tagCount: finalDetails?.tagIDs.count ?? 0,
      activeShareCount: finalDetails?.activeShareIDs.count ?? 0,
      rejectedOperations: result.evidence.flatMap(\.details.rejectedOperations),
      pendingMutationCount: finalDetails?.pendingMutationIDs.count ?? 0,
      stats: finalDetails?.stats ?? RemindersStats()
    )

    switch output {
    case .human:
      print("validation: \(summary.ok ? "ok" : "failed")")
      print("case: validation.reminders")
      print("events: \(summary.events.joined(separator: ", "))")
      print("evidence rows: \(summary.evidenceCount)")
      print("lists: \(summary.listCount)")
      print("reminders: \(summary.reminderCount)")
      print("completed reminders: \(summary.completedReminderCount)")
      print("tags: \(summary.tagCount)")
      print("active shares: \(summary.activeShareCount)")
      print("rejections: \(summary.rejectedOperations.joined(separator: ", "))")
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

  private static func printServerTransactionLoopbackValidation(
    result: ServerTransactionLoopbackValidationResult,
    output: OutputMode
  ) throws {
    let finalDetails = result.evidence.last?.details
    let summary = ServerTransactionLoopbackValidationOutput(
      appID: result.appID,
      cachePath: result.cacheURL.path,
      event: "server-transaction-loopback",
      transport: "local-server-transaction-loopback",
      ok: result.evidence.allSatisfy { $0.ok },
      evidenceCount: result.evidence.count,
      events: result.evidence.map(\.event),
      todoIDs: finalDetails?.todoIDs ?? [],
      pendingMutationIDs: finalDetails?.pendingMutationIDs ?? [],
      processedTransactionID: finalDetails?.processedTransactionID,
      mutationTransactionID: finalDetails?.mutationTransactionID,
      changedEntityIDs: finalDetails?.changedEntityIDs ?? [],
      emissionQueryIDs: finalDetails?.emissionQueryIDs ?? [],
      pendingMutationCount: finalDetails?.pendingMutationCount ?? 0,
      storeRevision: finalDetails?.storeRevision ?? 0,
      outboxRevision: finalDetails?.outboxRevision ?? 0
    )

    switch output {
    case .human:
      print("validation: \(summary.ok ? "ok" : "failed")")
      print("case: validation.server.transaction.loopback")
      print("events: \(summary.events.joined(separator: ", "))")
      print("evidence rows: \(summary.evidenceCount)")
      print("processed transaction: \(summary.processedTransactionID ?? "")")
      print("pending mutations: \(summary.pendingMutationCount)")
      print("revisions: store \(summary.storeRevision), outbox \(summary.outboxRevision)")
      print("todos: \(summary.todoIDs.joined(separator: ", "))")
      print("cache: \(summary.cachePath)")

    case .json:
      try writeJSON(summary)

    case .jsonl:
      for row in result.evidence {
        try writeJSONLine(row)
      }
    }
  }

  private static func printDraftValidation(
    result: DraftValidationResult,
    output: OutputMode
  ) throws {
    let finalDetails = result.evidence.last?.details
    let summary = DraftValidationOutput(
      appID: result.appID,
      cachePath: result.cacheURL.path,
      event: "typed-drafts",
      transport: "not-implemented-local-cache-only",
      ok: result.evidence.allSatisfy { $0.ok },
      evidenceCount: result.evidence.count,
      events: result.evidence.map(\.event),
      newDraftIDWasNil: finalDetails?.newDraftIDWasNil ?? false,
      newDraftAssignmentAttributeIDs: finalDetails?.newDraftAssignmentAttributeIDs ?? [],
      newDraftIncludedPrimaryKeyAssignment: finalDetails?.newDraftIncludedPrimaryKeyAssignment
        ?? false,
      draftTodoAttributeIDs: finalDetails?.draftTodoAttributeIDs ?? [],
      draftTodoIDs: finalDetails?.draftTodoIDs ?? [],
      draftTodoTitles: finalDetails?.draftTodoTitles ?? [],
      draftTodoCompletionStates: finalDetails?.draftTodoCompletionStates ?? [],
      draftTodoNotes: finalDetails?.draftTodoNotes ?? [],
      draftAuthorIDs: finalDetails?.draftAuthorIDs ?? [],
      draftAuthorNames: finalDetails?.draftAuthorNames ?? [],
      draftPostAttributeIDs: finalDetails?.draftPostAttributeIDs ?? [],
      draftPostIDs: finalDetails?.draftPostIDs ?? [],
      draftPostTitles: finalDetails?.draftPostTitles ?? [],
      draftPostAuthorIDs: finalDetails?.draftPostAuthorIDs ?? [],
      draftPostAuthorAttributeValueType: finalDetails?.draftPostAuthorAttributeValueType,
      draftPostAuthorLinkNamespace: finalDetails?.draftPostAuthorLinkNamespace,
      draftPostAuthorForwardIdentity: finalDetails?.draftPostAuthorForwardIdentity,
      draftPostAuthorReverseIdentity: finalDetails?.draftPostAuthorReverseIdentity,
      draftMutationSummaries: finalDetails?.draftMutationSummaries ?? [],
      pendingMutationCount: finalDetails?.pendingMutationIDs.count ?? 0,
      createdID: result.evidence.compactMap(\.details.createdID).first,
      editedID: result.evidence.compactMap(\.details.editedID).last,
      relationAuthorID: result.evidence.compactMap(\.details.relationAuthorID).last,
      relationPostID: result.evidence.compactMap(\.details.relationPostID).last
    )

    switch output {
    case .human:
      print("validation: \(summary.ok ? "ok" : "failed")")
      print("case: validation.typed.drafts")
      print("events: \(summary.events.joined(separator: ", "))")
      print("evidence rows: \(summary.evidenceCount)")
      print("new draft id omitted: \(summary.newDraftIDWasNil)")
      print("new draft assignments: \(summary.newDraftAssignmentAttributeIDs.joined(separator: ", "))")
      print("draft attributes: \(summary.draftTodoAttributeIDs.joined(separator: ", "))")
      print("draft todo ids: \(summary.draftTodoIDs.joined(separator: ", "))")
      print("draft post ids: \(summary.draftPostIDs.joined(separator: ", "))")
      print("draft post author relation: \(summary.draftPostAuthorRelationSummary)")
      print("draft mutation ids: \(summary.draftMutationSummaries.map(\.mutationID).joined(separator: ", "))")
      print("draft create mutation: \(summary.draftCreateMutationSummary)")
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

  private static func printPlatformAdapterValidation(
    result: PlatformAdapterValidationResult,
    output: OutputMode
  ) throws {
    let bindingAdapters = result.evidence.flatMap(\.details.bindingAdapters)
    let summary = PlatformAdapterValidationOutput(
      appID: result.appID,
      cachePath: result.cacheURL.path,
      event: "platform-adapters",
      transport: "not-implemented-local-cache-only",
      ok: result.evidence.allSatisfy { $0.ok },
      evidenceCount: result.evidence.count,
      events: result.evidence.map(\.event),
      adapters: result.evidence.map(\.details.adapter),
      bindingAdapterCount: bindingAdapters.count,
      bindingAdapters: bindingAdapters,
      todoCount: result.evidence.first { $0.event == "fetch-all" }?.details.todoCount
        ?? result.evidence.map(\.details.todoCount).max()
        ?? 0,
      selectedTodoID: result.evidence.compactMap(\.details.selectedTodoID).first,
      localID: result.evidence.compactMap(\.details.localID).first,
      authUserID: result.evidence.compactMap(\.details.authUserID).last,
      roomMemberCount: Set(result.evidence.flatMap(\.details.roomMemberIDs)).count,
      topicMessageCount: Set(result.evidence.flatMap(\.details.topicMessageIDs)).count,
      fileCount: Set(result.evidence.flatMap(\.details.fileIDs)).count,
      streamChunkCount: Set(result.evidence.flatMap(\.details.streamChunkIDs)).count,
      shareCount: Set(result.evidence.flatMap(\.details.shareIDs)).count,
      lifecycleEventCount: result.evidence.filter {
        $0.event.hasPrefix("fetch-all-")
          || $0.event.hasPrefix("fetch-one-")
          || $0.event.hasPrefix("fetch-request-")
          || $0.event.hasPrefix("infinite-query-")
          || $0.event.hasPrefix("live-wrapper-")
      }.count,
      queryProbeCount: result.evidence.compactMap(\.details.queryCount).reduce(0, +),
      observationProbeCount: result.evidence.compactMap(\.details.observationCount).reduce(0, +),
      loadErrorOperations: result.evidence.compactMap(\.details.loadErrorOperation),
      cancellationTerminated: result.evidence.contains {
        $0.details.cancellationTerminated == true
      }
    )

    switch output {
    case .human:
      print("validation: \(summary.ok ? "ok" : "failed")")
      print("case: validation.platform.adapters")
      print("events: \(summary.events.joined(separator: ", "))")
      print("adapters: \(summary.adapters.joined(separator: ", "))")
      print("binding adapters: \(summary.bindingAdapters.joined(separator: ", "))")
      print("evidence rows: \(summary.evidenceCount)")
      print("todos: \(summary.todoCount)")
      print("auth user: \(summary.authUserID ?? "none")")
      print("room members: \(summary.roomMemberCount)")
      print("topic messages: \(summary.topicMessageCount)")
      print("files: \(summary.fileCount)")
      print("stream chunks: \(summary.streamChunkCount)")
      print("shares: \(summary.shareCount)")
      print("lifecycle probes: \(summary.lifecycleEventCount)")
      print("query probes: \(summary.queryProbeCount)")
      print("observation probes: \(summary.observationProbeCount)")
      print("load errors: \(summary.loadErrorOperations.joined(separator: ", "))")
      print("cancellation terminated: \(summary.cancellationTerminated)")
      print("cache: \(summary.cachePath)")

    case .json:
      try writeJSON(summary)

    case .jsonl:
      for row in result.evidence {
        try writeJSONLine(row)
      }
    }
  }

  private static func printSyncUpsRecordingValidation(
    result: SyncUpsRecordingValidationResult,
    output: OutputMode
  ) throws {
    let savedRecording =
      result.evidence.first { $0.event == "meeting-save" }?.details.recording
      ?? result.evidence.first { $0.event == "finish" }?.details.recording
    let deniedRecording = result.evidence.first { $0.event == "settings-open" }?.details.recording
    let meetingTranscripts = result.evidence.last?.details.meetingTranscripts ?? []
    let summary = SyncUpsRecordingValidationOutput(
      appID: result.appID,
      cachePath: result.cacheURL.path,
      event: "syncups-recording",
      transport: "not-implemented-local-cache-only",
      ok: result.evidence.allSatisfy { $0.ok },
      evidenceCount: result.evidence.count,
      events: result.evidence.map(\.event),
      syncUpID: result.syncUpID,
      attendeeIDs: result.attendeeIDs,
      meetingID: result.meetingID,
      meetingTranscripts: meetingTranscripts,
      transcript: savedRecording?.transcript ?? "",
      authorizationStatus: savedRecording?.authorizationStatus,
      requestedAuthorization: savedRecording?.requestedAuthorization ?? false,
      loadedSoundEffectFileName: savedRecording?.loadedSoundEffectFileName,
      speechResultCount: result.evidence.map { $0.details.recording?.speechResultCount ?? 0 }.max() ?? 0,
      soundEffectPlayCount: result.evidence.map { $0.details.recording?.soundEffectPlayCount ?? 0 }.max()
        ?? 0,
      secondsElapsed: result.evidence.map { $0.details.recording?.secondsElapsed ?? 0 }.max() ?? 0,
      speakerIndex: result.evidence.map { $0.details.recording?.speakerIndex ?? 0 }.max() ?? 0,
      currentSpeakerName: savedRecording?.currentSpeakerName,
      openSettingsCount: result.evidence.map(\.details.openSettingsCount).max() ?? 0,
      finalAlert: deniedRecording?.alert,
      isDismissed: savedRecording?.isDismissed ?? false
    )

    switch output {
    case .human:
      print("validation: \(summary.ok ? "ok" : "failed")")
      print("case: validation.syncups.recording")
      print("events: \(summary.events.joined(separator: ", "))")
      print("evidence rows: \(summary.evidenceCount)")
      print("sync-up: \(summary.syncUpID)")
      print("attendees: \(summary.attendeeIDs.joined(separator: ", "))")
      print("meeting: \(summary.meetingID)")
      print("transcript: \(summary.transcript)")
      print("speech results: \(summary.speechResultCount)")
      print("sound effects: \(summary.soundEffectPlayCount)")
      print("open settings: \(summary.openSettingsCount)")
      print("cache: \(summary.cachePath)")

    case .json:
      try writeJSON(summary)

    case .jsonl:
      for row in result.evidence {
        try writeJSONLine(row)
      }
    }
  }

  private static func printParityCoverageReport(
    result: InstantParityCoverageReport,
    appID: String,
    output: OutputMode
  ) throws {
    switch output {
    case .human:
      print("parity coverage: \(result.coverageComplete ? "complete" : "incomplete")")
      print("records: \(result.recordCount)")
      print("exact: \(result.exactCount)")
      print("adapted: \(result.adaptedCount)")
      print("blocked: \(result.blockedCount)")
      print("not applicable: \(result.notApplicableCount)")
      print("source files: \(result.sourceFiles.count)")
      print("swift files: \(result.swiftFiles.count)")

    case .json:
      try writeJSON(result)

    case .jsonl:
      for row in result.evidenceRows(appID: appID) {
        try writeJSONLine(row)
      }
    }
  }

  private static func printValidationCoverageSummary(
    result: InstantParityCoverageReport,
    appID: String,
    output: OutputMode
  ) throws {
    let summary = InstantParityCoverageSummary(result)

    switch output {
    case .human:
      print("validation coverage: \(summary.coverageComplete ? "complete" : "incomplete")")
      print("records: \(summary.recordCount)")
      print("exact: \(summary.exactCount)")
      print("adapted: \(summary.adaptedCount)")
      print("blocked: \(summary.blockedCount)")
      print("not applicable: \(summary.notApplicableCount)")
      print("source files: \(summary.sourceFileCount)")
      print("swift files: \(summary.swiftFileCount)")

    case .json:
      try writeJSON(summary)

    case .jsonl:
      try writeJSONLine(
        ValidationEvidenceRow(
          caseID: "validation.coverage",
          side: "swift",
          event: "coverage-summary",
          appID: appID,
          timestampMs: 0,
          ok: summary.ok,
          details: summary
        )
      )
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

  private static func validationAppID(defaultAppID: String = "local-demo") -> String {
    let appID = ProcessInfo.processInfo.environment["INSTANT_APP_ID"]?
      .trimmingCharacters(in: .whitespacesAndNewlines)
    guard let appID, !appID.isEmpty else {
      return defaultAppID
    }
    return appID
  }

  private static func typeScriptServerTransactionContract() throws
    -> TypeScriptServerTransactionContract?
  {
    guard
      let path = ProcessInfo.processInfo.environment[
        "INSTANT_SWIFT_DATA_TYPESCRIPT_SERVER_TRANSACTION_CONTRACT"
      ]?.trimmingCharacters(in: .whitespacesAndNewlines),
      !path.isEmpty
    else { return nil }
    return try InstantSwiftDataServerTransactionLoopbackValidation
      .loadTypeScriptServerTransactionContract(from: URL(fileURLWithPath: path))
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

  private static func todoListQuery(invocation: CLITodosQueryInvocation) -> InstantQueryPlan {
    makeTodoListQuery(
      completed: invocation.completed,
      search: invocation.search,
      offset: invocation.offset,
      limit: invocation.limit,
      first: invocation.first,
      after: invocation.after.map(instantCursor),
      last: invocation.last,
      before: invocation.before.map(instantCursor),
      direction: instantSortDirection(invocation.direction),
      orderField: instantTodoOrderField(invocation.orderField)
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

  private static func todoWatchOptions(
    invocation: CLIExamplesTodosWatchInvocation
  ) -> TodoWatchOptions {
    TodoWatchOptions(
      query: todoListQuery(invocation: invocation.query),
      eventCount: invocation.eventCount
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

  private static func queryIDFragment(_ value: String) -> String {
    Data(value.utf8).base64EncodedString()
      .replacingOccurrences(of: "+", with: "-")
      .replacingOccurrences(of: "/", with: "_")
      .replacingOccurrences(of: "=", with: "")
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
    Usage: instant-swift-data examples <todos|auth|app-builder|todo-links|counters|chat|mobile-chat|microblog|reactions|typing-indicator|avatar-stack|cursors|custom-cursors|merge-tile-game|stroopwafel|reminders|sync-ups>
      instant-swift-data examples todos <add|seed|list|watch|complete|update|delete|reset|refresh>
      instant-swift-data examples auth <send-code|verify-code|status|watch|sign-out> [--json|--jsonl]
      instant-swift-data examples app-builder <generate|list|show|append|finish|reset> [--json|--jsonl]
      instant-swift-data examples todo-links <seed|list|nested|unlink> [--json|--jsonl]
      instant-swift-data examples counters <seed|add|list|increment|decrement|delete> [--json|--jsonl]
      instant-swift-data examples chat <seed|channels|messages|post|reset> [--json|--jsonl]
      instant-swift-data examples mobile-chat <seed|channels|messages|profiles|profile|setup-profile|send|join|presence|leave|reset> [--json|--jsonl]
      instant-swift-data examples microblog <seed|feed|profiles|profile|setup-profile|post|like|unlike|delete-post|reset> [--json|--jsonl]
      instant-swift-data examples reactions <tap|list|watch> [--json|--jsonl]
      instant-swift-data examples typing-indicator <join|type|stop|list|watch|leave> [--json|--jsonl]
      instant-swift-data examples avatar-stack <join|list|watch|leave> [--json|--jsonl]
      instant-swift-data examples cursors <move|list|watch|clear|leave> [--json|--jsonl]
      instant-swift-data examples custom-cursors <move|list|watch|clear|leave> [--json|--jsonl]
      instant-swift-data examples merge-tile-game <join|tap|board|watch|reset|leave> [--json|--jsonl]
      instant-swift-data examples stroopwafel <setup-profile|profile|score|create-room|rooms|room|join|ready|unready|kick|start|games|game|tap|leave|reset> [--json|--jsonl]
      instant-swift-data examples reminders <seed|list|stats|tags|list-tags|search|add-list|rename-list|delete-list|add|update|complete|delete|delete-completed|add-tag|remove-tag> [--json|--jsonl]
      instant-swift-data examples sync-ups <seed|list|detail|add|edit|add-attendee|record|record-demo|delete|delete-attendee|delete-meeting> [--json|--jsonl]
    """
  }

  private static var countersUsage: String {
    CLIExamplesCountersUsage.counters
  }

  private static var chatUsage: String {
    CLIExamplesChatUsage.chat
  }

  private static var appBuilderUsage: String {
    CLIExamplesAppBuilderUsage.appBuilder
  }

  private static var microblogUsage: String {
    CLIExamplesMicroblogUsage.microblog
  }

  private static var mobileChatUsage: String {
    CLIExamplesMobileChatUsage.mobileChat
  }

  private static var reactionsUsage: String {
    CLIExamplesReactionsUsage.reactions
  }

  private static var typingIndicatorUsage: String {
    CLIExamplesTypingIndicatorUsage.typingIndicator
  }

  private static var avatarStackUsage: String {
    CLIExamplesAvatarStackUsage.avatarStack
  }

  private static var cursorsUsage: String {
    CLIExamplesCursorsUsage.cursors
  }

  private static var customCursorsUsage: String {
    CLIExamplesCustomCursorsUsage.customCursors
  }

  private static var mergeTileGameUsage: String {
    CLIExamplesMergeTileGameUsage.mergeTileGame
  }

  private static var stroopwafelUsage: String {
    CLIExamplesStroopwafelUsage.stroopwafel
  }

  private static var syncUpsUsage: String {
    """
    Usage: instant-swift-data examples sync-ups <seed|list|detail|add|edit|add-attendee|record|record-demo|delete|delete-attendee|delete-meeting>
      instant-swift-data examples sync-ups seed [--json|--jsonl]
      instant-swift-data examples sync-ups list [--refresh] [--sync-up-id id] [--json|--jsonl]
      instant-swift-data examples sync-ups detail <sync-up-id> [--json|--jsonl]
      instant-swift-data examples sync-ups add "title" --attendee "name" [--seconds n] [--theme theme] [--json|--jsonl]
      instant-swift-data examples sync-ups edit <sync-up-id> [--title title] [--seconds n] [--theme theme] [--attendee name ...] [--json|--jsonl]
      instant-swift-data examples sync-ups add-attendee <sync-up-id> "name" [--json|--jsonl]
      instant-swift-data examples sync-ups record <sync-up-id> [--transcript] "transcript" [--json|--jsonl]
      instant-swift-data examples sync-ups record-demo <sync-up-id> [--json|--jsonl]
      instant-swift-data examples sync-ups delete <sync-up-id> [--json|--jsonl]
      instant-swift-data examples sync-ups delete-attendee <attendee-id> [--json|--jsonl]
      instant-swift-data examples sync-ups delete-meeting <meeting-id> [--json|--jsonl]
    """
  }

  private static func validateSyncUpsThemeValues(
    in invocation: CLIExamplesSyncUpsLeafInvocation
  ) throws {
    switch invocation {
    case let .add(add):
      try validateSyncUpTheme(add.theme)

    case let .update(update):
      if let theme = update.theme {
        try validateSyncUpTheme(theme)
      }

    case .seed, .list, .detail, .addAttendee, .record, .recordDemo, .delete, .deleteAttendee,
      .deleteMeeting, .unknown:
      return
    }
  }

  private static func validateSyncUpTheme(_ rawValue: String) throws {
    guard SyncUpTheme(rawValue: rawValue) != nil else {
      throw CLIError("Unknown SyncUps theme. Use one of: \(syncUpThemeList).", exitCode: 64)
    }
  }

  private static func syncUpTheme(_ rawValue: String) -> SyncUpTheme {
    guard let theme = SyncUpTheme(rawValue: rawValue) else {
      preconditionFailure("CLI theme validation accepted an unknown SyncUps theme.")
    }
    return theme
  }

  private static var syncUpThemeList: String {
    SyncUpTheme.allCases.map(\.rawValue).joined(separator: ", ")
  }

  private static func validateReminderRawValues(
    in invocation: CLIExamplesRemindersLeafInvocation
  ) throws {
    switch invocation {
    case let .list(options):
      _ = try reminderPriority(options.priorityRawValue, usage: remindersListUsage)

    case let .add(options):
      _ = try reminderDueDate(options.dueDateRawValue)
      _ = try reminderPriority(options.priorityRawValue, usage: remindersAddUsage)

    case let .update(options):
      _ = try reminderDueDate(options.dueDateRawValue)
      _ = try reminderPriority(
        options.priorityRawValue,
        usage: remindersUpdateUsage,
        allowsNone: true
      )

    case let .addTag(_, rawTag):
      _ = try normalizedReminderTag(rawTag, usage: CLIExamplesRemindersUsage.addTag)

    case let .removeTag(_, rawTag):
      _ = try normalizedReminderTag(rawTag, usage: CLIExamplesRemindersUsage.removeTag)

    case let .search(options):
      _ = try normalizedReminderTagIfPresent(options.rawTag, usage: remindersSearchUsage)
      _ = try reminderPriority(options.priorityRawValue, usage: remindersSearchUsage)

    case .seed, .stats, .tags, .addList, .renameList, .complete, .delete,
      .deleteCompleted, .deleteList, .unknown:
      break
    }
  }

  private static func reminderDueDate(_ rawValue: String?) throws -> InstantTimestamp? {
    guard let rawValue else { return nil }
    return try parseReminderDueDate(rawValue)
  }

  private static func reminderPriority(
    _ rawValue: String?,
    usage: String,
    allowsNone: Bool = false
  ) throws -> ReminderPriority? {
    guard let rawValue else { return nil }
    if allowsNone, rawValue == "none" {
      return nil
    }
    guard let priority = ReminderPriority(rawValue: rawValue) else {
      throw CLIError(usage, exitCode: 64)
    }
    return priority
  }

  private static func normalizedReminderTagIfPresent(
    _ rawTag: String?,
    usage: String
  ) throws -> String? {
    guard let rawTag else { return nil }
    return try normalizedReminderTag(rawTag, usage: usage)
  }

  private static func normalizedReminderTag(
    _ rawTag: String,
    usage: String
  ) throws -> String {
    guard let tagID = ReminderExample.normalizedTagTitle(rawTag) else {
      throw CLIError(usage, exitCode: 64)
    }
    return tagID
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
    try await runtime.migrateLocalPersistenceSnapshot(
      name: "reminders.priority-ranks",
      transform: ReminderExample.migrateLegacyPriorityRanks(in:)
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

private struct CountersOutput: Codable, Sendable {
  var appID: String
  var cachePath: String
  var event: String
  var changedID: String?
  var transport: String
  var queryID: String
  var cacheKey: String
  var pendingMutationCount: Int
  var counterCount: Int
  var sharedCounterCount: Int
  var counters: [SharedCounterRecord]
}

private struct ChatOutput: Codable, Sendable {
  var appID: String
  var cachePath: String
  var event: String
  var changedID: String?
  var selectedChannelID: String?
  var authUserID: String?
  var authIsGuest: Bool?
  var transport: String
  var channelQueryID: String
  var messageQueryID: String
  var channelCacheKey: String
  var messageCacheKey: String
  var pendingMutationCount: Int
  var channelCount: Int
  var messageCount: Int
  var channels: [ChatChannelRecord]
  var messages: [ChatMessageRecord]
}

private struct AppBuilderGenerationEventOutput: Codable, Sendable {
  var event: String
  var kind: String?
  var text: String?
  var codeLength: Int
  var reasoningLength: Int
  var isPreviewable: Bool
}

private struct AppBuilderOutput: Codable, Sendable {
  var appID: String
  var cachePath: String
  var event: String
  var changedID: String?
  var selectedBuildID: String?
  var authUserID: String?
  var authUserEmail: String?
  var transport: String
  var platformApp: InstantPlatformApp?
  var queryID: String
  var cacheKey: String
  var ownerQueryID: String?
  var ownerCacheKey: String?
  var pendingMutationCount: Int
  var buildCount: Int
  var previewableBuildCount: Int
  var builds: [AppBuilderBuildRecord]
  var selectedBuild: AppBuilderBuildRecord?
  var generationEvents: [AppBuilderGenerationEventOutput]
}

private struct MicroblogOutput: Codable, Sendable {
  var appID: String
  var cachePath: String
  var event: String
  var changedID: String?
  var selectedUserID: String?
  var selectedProfile: MicroblogProfileRecord?
  var selectedPostID: String?
  var authUserID: String?
  var transport: String
  var userQueryID: String
  var profileQueryID: String
  var postQueryID: String
  var likeQueryID: String
  var feedQueryID: String
  var userCacheKey: String
  var profileCacheKey: String
  var postCacheKey: String
  var likeCacheKey: String
  var feedCacheKey: String
  var pendingMutationCount: Int
  var userCount: Int
  var profileCount: Int
  var postCount: Int
  var likeCount: Int
  var users: [MicroblogUserRecord]
  var profiles: [MicroblogProfileRecord]
  var posts: [MicroblogPostRecord]
  var likes: [MicroblogLikeRecord]
  var feed: [MicroblogFeedPostRecord]
}

private struct MobileChatOutput: Codable, Sendable {
  var appID: String
  var cachePath: String
  var event: String
  var changedID: String?
  var selectedUserID: String?
  var selectedProfile: MobileChatProfileRecord?
  var selectedChannelID: String?
  var authUserID: String?
  var authIsGuest: Bool?
  var transport: String
  var userQueryID: String
  var profileQueryID: String
  var channelQueryID: String
  var messageQueryID: String
  var userCacheKey: String
  var profileCacheKey: String
  var channelCacheKey: String
  var messageCacheKey: String
  var pendingMutationCount: Int
  var userCount: Int
  var profileCount: Int
  var channelCount: Int
  var messageCount: Int
  var presenceRoom: InstantRoomHandle?
  var presenceMemberCount: Int
  var users: [MobileChatUserRecord]
  var profiles: [MobileChatProfileRecord]
  var channels: [MobileChatChannelRecord]
  var messages: [MobileChatMessageRecord]
  var presenceMembers: [InstantRoomPresenceMember]
}

private struct StroopwafelOutput: Codable, Sendable {
  var appID: String
  var cachePath: String
  var event: String
  var changedID: String?
  var selectedUserID: String?
  var selectedUser: StroopwafelUserRecord?
  var selectedRoomCode: String?
  var selectedRoom: StroopwafelRoomRecord?
  var selectedGameID: String?
  var selectedGame: StroopwafelGameRecord?
  var authUserID: String?
  var authIsGuest: Bool?
  var transport: String
  var userQueryID: String
  var roomQueryID: String
  var gameQueryID: String
  var pointQueryID: String
  var userCacheKey: String
  var roomCacheKey: String
  var gameCacheKey: String
  var pointCacheKey: String
  var pendingMutationCount: Int
  var userCount: Int
  var roomCount: Int
  var gameCount: Int
  var pointCount: Int
  var users: [StroopwafelUserRecord]
  var rooms: [StroopwafelRoomRecord]
  var games: [StroopwafelGameRecord]
  var points: [StroopwafelPointRecord]
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
  var recording: SyncUpRecordingSummary?
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

private struct AuthRecipeWatchOutput: Codable, Sendable {
  var appID: String
  var cachePath: String
  var event: String
  var recipeSlug: String
  var transport: String
  var requestedEventCount: Int
  var emittedEventCount: Int
  var emissions: [AuthRecipeOutput]
}

private struct AuthRecipeOutput: Codable, Sendable {
  var appID: String
  var cachePath: String
  var event: String
  var recipeSlug: String
  var transport: String
  var isLoginVisible: Bool
  var isEmailEntryVisible: Bool
  var isCodeEntryVisible: Bool
  var isDashboardVisible: Bool
  var isSignedIn: Bool
  var userID: String?
  var userEmail: String?
  var isGuest: Bool?
  var hasRefreshToken: Bool
  var sentEmail: String?
  var localVerificationCode: String?
  var expiresAt: InstantTimestamp?
  var createdAt: InstantTimestamp?
  var updatedAt: InstantTimestamp?
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

private struct ReactionsRecipeOutput: Codable, Sendable {
  var appID: String
  var cachePath: String
  var event: String
  var publishedMessageID: String?
  var authUserID: String?
  var authIsGuest: Bool?
  var transport: String
  var room: InstantRoomHandle
  var topic: String
  var messageCount: Int
  var reactionCount: Int
  var messages: [ReactionsRecipeMessageOutput]
  var reactions: [ReactionsRecipeReaction]
}

private struct ReactionsRecipeMessageOutput: Codable, Sendable {
  var id: String
  var appID: String
  var room: InstantRoomHandle
  var topic: String
  var userID: String
  var payload: ReactionsRecipePayload
  var createdAt: InstantTimestamp

  init?(message: InstantRoomTopicMessage) {
    guard let payload = ReactionsRecipeExample.recipePayload(from: message.payload) else {
      return nil
    }
    self.id = message.id
    self.appID = message.appID
    self.room = message.room
    self.topic = message.topic
    self.userID = message.userID
    self.payload = payload
    self.createdAt = message.createdAt
  }
}

private struct TypingIndicatorRecipeOutput: Codable, Sendable {
  var appID: String
  var cachePath: String
  var event: String
  var userID: String?
  var viewerUserID: String?
  var transport: String
  var room: InstantRoomHandle
  var inputName: String
  var memberCount: Int
  var activeCount: Int
  var typingInfo: String?
  var members: [TypingIndicatorRecipeMember]
  var activeMembers: [TypingIndicatorRecipeMember]
}

private struct AvatarStackRecipeOutput: Codable, Sendable {
  var appID: String
  var cachePath: String
  var event: String
  var userID: String?
  var viewerUserID: String?
  var transport: String
  var room: InstantRoomHandle
  var nameKey: String
  var memberCount: Int
  var peerCount: Int
  var onlineCount: Int
  var currentUser: AvatarStackRecipeMember?
  var peers: [AvatarStackRecipeMember]
  var members: [AvatarStackRecipeMember]
}

private struct CursorsRecipeOutput: Codable, Sendable {
  var appID: String
  var cachePath: String
  var event: String
  var userID: String?
  var viewerUserID: String?
  var transport: String
  var room: InstantRoomHandle
  var spaceID: String
  var nameKey: String?
  var memberCount: Int
  var cursorCount: Int
  var visibleCursors: [CursorsRecipeCursor]
  var members: [CursorsRecipeCursor]
}

private struct MergeTileGameRecipeOutput: Codable, Sendable {
  var appID: String
  var cachePath: String
  var event: String
  var userID: String?
  var viewerUserID: String?
  var transport: String
  var room: InstantRoomHandle
  var boardID: String
  var boardSize: Int
  var emptyColor: String
  var colors: [String]
  var colorKey: String
  var playerCount: Int
  var filledCount: Int
  var currentPlayer: MergeTileGamePlayer?
  var peers: [MergeTileGamePlayer]
  var players: [MergeTileGamePlayer]
  var availableColors: [String]
  var board: MergeTileGameBoard?
  var paintedCells: [MergeTileGameCellOutput]
}

private struct MergeTileGameCellOutput: Codable, Sendable {
  var boardID: String
  var key: String
  var row: Int
  var column: Int
  var color: String
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

private struct RemindersValidationOutput: Codable, Sendable {
  var appID: String
  var cachePath: String
  var event: String
  var transport: String
  var ok: Bool
  var evidenceCount: Int
  var events: [String]
  var listCount: Int
  var reminderCount: Int
  var completedReminderCount: Int
  var tagCount: Int
  var activeShareCount: Int
  var rejectedOperations: [String]
  var pendingMutationCount: Int
  var stats: RemindersStats
}

private struct ServerTransactionLoopbackValidationOutput: Codable, Sendable {
  var appID: String
  var cachePath: String
  var event: String
  var transport: String
  var ok: Bool
  var evidenceCount: Int
  var events: [String]
  var todoIDs: [String]
  var pendingMutationIDs: [String]
  var processedTransactionID: String?
  var mutationTransactionID: String?
  var changedEntityIDs: [String]
  var emissionQueryIDs: [String]
  var pendingMutationCount: Int
  var storeRevision: Int64
  var outboxRevision: Int64
}

private struct DraftValidationOutput: Codable, Sendable {
  var appID: String
  var cachePath: String
  var event: String
  var transport: String
  var ok: Bool
  var evidenceCount: Int
  var events: [String]
  var newDraftIDWasNil: Bool
  var newDraftAssignmentAttributeIDs: [String]
  var newDraftIncludedPrimaryKeyAssignment: Bool
  var draftTodoAttributeIDs: [String]
  var draftTodoIDs: [String]
  var draftTodoTitles: [String]
  var draftTodoCompletionStates: [Bool]
  var draftTodoNotes: [String?]
  var draftAuthorIDs: [String]
  var draftAuthorNames: [String]
  var draftPostAttributeIDs: [String]
  var draftPostIDs: [String]
  var draftPostTitles: [String]
  var draftPostAuthorIDs: [String]
  var draftPostAuthorAttributeValueType: String?
  var draftPostAuthorLinkNamespace: String?
  var draftPostAuthorForwardIdentity: String?
  var draftPostAuthorReverseIdentity: String?
  var draftMutationSummaries: [DraftValidationMutationSummary]
  var pendingMutationCount: Int
  var createdID: String?
  var editedID: String?
  var relationAuthorID: String?
  var relationPostID: String?

  var draftPostAuthorRelationSummary: String {
    [
      draftPostAuthorAttributeValueType,
      draftPostAuthorLinkNamespace,
      draftPostAuthorForwardIdentity,
      draftPostAuthorReverseIdentity,
    ]
    .compactMap { $0 }
    .joined(separator: " ")
  }

  var draftCreateMutationSummary: String {
    guard let mutation = draftMutationSummaries.first(where: {
      $0.mutationID == "validation.typed-drafts.create"
    }) else { return "" }
    return (
      mutation.preconditionKinds
        + mutation.txStepAttributeIDs
        + mutation.txStepOptionModes
    )
    .joined(separator: " ")
  }
}

private struct PlatformAdapterValidationOutput: Codable, Sendable {
  var appID: String
  var cachePath: String
  var event: String
  var transport: String
  var ok: Bool
  var evidenceCount: Int
  var events: [String]
  var adapters: [String]
  var bindingAdapterCount: Int
  var bindingAdapters: [String]
  var todoCount: Int
  var selectedTodoID: String?
  var localID: String?
  var authUserID: String?
  var roomMemberCount: Int
  var topicMessageCount: Int
  var fileCount: Int
  var streamChunkCount: Int
  var shareCount: Int
  var lifecycleEventCount: Int
  var queryProbeCount: Int
  var observationProbeCount: Int
  var loadErrorOperations: [String]
  var cancellationTerminated: Bool
}

private struct SyncUpsRecordingValidationOutput: Codable, Sendable {
  var appID: String
  var cachePath: String
  var event: String
  var transport: String
  var ok: Bool
  var evidenceCount: Int
  var events: [String]
  var syncUpID: String
  var attendeeIDs: [String]
  var meetingID: String
  var meetingTranscripts: [String]
  var transcript: String
  var authorizationStatus: SyncUpSpeechAuthorizationStatus?
  var requestedAuthorization: Bool
  var loadedSoundEffectFileName: String?
  var speechResultCount: Int
  var soundEffectPlayCount: Int
  var secondsElapsed: Int
  var speakerIndex: Int
  var currentSpeakerName: String?
  var openSettingsCount: Int
  var finalAlert: SyncUpRecordingAlert?
  var isDismissed: Bool
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

private struct CLISchemaExample: Sendable {
  var name: String
  var schema: InstantSchemaDocument
  var permissions: InstantPermissionsDocument
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
