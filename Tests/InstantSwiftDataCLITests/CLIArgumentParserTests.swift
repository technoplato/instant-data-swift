import CustomDump
import InstantSwiftDataCLIParsing
import Testing

@Suite
struct CLIArgumentParserTests {
  @Test
  func outputModeCanAppearBeforeBetweenOrAfterCommandTokens() throws {
    expectNoDifference(
      try CLIArguments.parse(["--jsonl", "schema", "generate"]),
      CLIInvocation(output: .jsonl, command: .schema, arguments: ["generate"])
    )
    expectNoDifference(
      try CLIArguments.parse(["schema", "--jsonl", "generate"]),
      CLIInvocation(output: .jsonl, command: .schema, arguments: ["generate"])
    )
    expectNoDifference(
      try CLIArguments.parse(["schema", "generate", "--jsonl"]),
      CLIInvocation(output: .jsonl, command: .schema, arguments: ["generate"])
    )
    expectNoDifference(
      try CLIArguments.parse(["schema", "generate", "--json"]),
      CLIInvocation(output: .json, command: .schema, arguments: ["generate"])
    )
    expectNoDifference(
      try CLIArguments.parse(["schema", "generate"]),
      CLIInvocation(output: .human, command: .schema, arguments: ["generate"])
    )
  }

  @Test
  func jsonlTakesPrecedenceAndOnlyOneOutputFlagIsConsumed() throws {
    expectNoDifference(
      try CLIArguments.parse(["schema", "--json", "generate", "--jsonl"]),
      CLIInvocation(output: .jsonl, command: .schema, arguments: ["--json", "generate"])
    )
    expectNoDifference(
      try CLIArguments.parse(["schema", "--json", "generate", "--json"]),
      CLIInvocation(output: .json, command: .schema, arguments: ["generate", "--json"])
    )
  }

  @Test
  func topLevelAliasesNormalizeToCommands() throws {
    let cases: [(String, CLITopLevelCommand)] = [
      ("perms", .permissions),
      ("permissions", .permissions),
      ("local-id", .localID),
      ("localid", .localID),
      ("connection", .connection),
      ("connect", .connection),
      ("rooms", .rooms),
      ("room", .rooms),
      ("files", .files),
      ("storage", .files),
      ("streams", .streams),
      ("stream", .streams),
      ("shares", .shares),
      ("share", .shares),
      ("sharing", .shares),
      ("validate", .validation),
      ("validation", .validation),
      ("benchmark", .benchmark),
      ("benchmarks", .benchmark),
      ("--help", .help),
      ("-h", .help),
    ]

    for (rawCommand, command) in cases {
      expectNoDifference(
        try CLIArguments.parse([rawCommand, "tail"]),
        CLIInvocation(output: .human, command: command, arguments: ["tail"])
      )
    }
  }

  @Test
  func unknownAndEmptyCommandsKeepCurrentDispatchShape() throws {
    expectNoDifference(
      try CLIArguments.parse(["definitely-not-a-command", "--json"]),
      CLIInvocation(
        output: .json,
        command: .unknown("definitely-not-a-command"),
        arguments: []
      )
    )
    expectNoDifference(
      try CLIArguments.parse(["--jsonl"]),
      CLIInvocation(output: .jsonl, command: nil, arguments: [])
    )
  }

  @Test
  func examplesParserNormalizesTodosCommandsAndPreservesArguments() throws {
    expectNoDifference(
      try parseExamples(["todos", "add", "do", "the", "dishes"]),
      .todos(
        CLIExamplesTodosInvocation(
          command: .add,
          arguments: ["do", "the", "dishes"]
        )
      )
    )
    expectNoDifference(
      try parseExamples(["todos", "observe", "--events", "1"]),
      .todos(
        CLIExamplesTodosInvocation(
          command: .watch,
          arguments: ["--events", "1"]
        )
      )
    )
    expectNoDifference(
      try parseExamples(["todos", "edit", "todo-1", "new", "text"]),
      .todos(
        CLIExamplesTodosInvocation(
          command: .update,
          arguments: ["todo-1", "new", "text"]
        )
      )
    )
    expectNoDifference(
      try parseExamples(["todos", "remove", "todo-1"]),
      .todos(
        CLIExamplesTodosInvocation(
          command: .delete,
          arguments: ["todo-1"]
        )
      )
    )
  }

  @Test
  func topLevelOutputModeNormalizesAroundExamplesCommand() throws {
    expectNoDifference(
      try CLIArguments.parse(["examples", "todos", "observe", "--events", "1", "--jsonl"]),
      CLIInvocation(
        output: .jsonl,
        command: .examples,
        arguments: ["todos", "observe", "--events", "1"]
      )
    )
    expectNoDifference(
      try CLIArguments.parse(["examples", "--json", "todos", "edit", "todo-1", "new"]),
      CLIInvocation(
        output: .json,
        command: .examples,
        arguments: ["todos", "edit", "todo-1", "new"]
      )
    )
    expectNoDifference(
      try CLIArguments.parse(["shares", "role", "share-1", "user-2", "writer", "--json"]),
      CLIInvocation(
        output: .json,
        command: .shares,
        arguments: ["role", "share-1", "user-2", "writer"]
      )
    )
    expectNoDifference(
      try CLIArguments.parse(["shares", "--jsonl", "ls"]),
      CLIInvocation(
        output: .jsonl,
        command: .shares,
        arguments: ["ls"]
      )
    )
    expectNoDifference(
      try CLIArguments.parse(["files", "upload", "./photo.jpg", "--json"]),
      CLIInvocation(
        output: .json,
        command: .files,
        arguments: ["upload", "./photo.jpg"]
      )
    )
    expectNoDifference(
      try CLIArguments.parse(["auth", "token", "refresh-token", "--user-id", "user-1", "--json"]),
      CLIInvocation(
        output: .json,
        command: .auth,
        arguments: ["token", "refresh-token", "--user-id", "user-1"]
      )
    )
    expectNoDifference(
      try CLIArguments.parse(["connection", "status", "--jsonl"]),
      CLIInvocation(
        output: .jsonl,
        command: .connection,
        arguments: ["status"]
      )
    )
    expectNoDifference(
      try CLIArguments.parse(["connect", "show", "--json"]),
      CLIInvocation(
        output: .json,
        command: .connection,
        arguments: ["show"]
      )
    )
    expectNoDifference(
      try CLIArguments.parse(["localid", "get", "todos.viewer", "--json"]),
      CLIInvocation(
        output: .json,
        command: .localID,
        arguments: ["get", "todos.viewer"]
      )
    )
    expectNoDifference(
      try CLIArguments.parse(["local-id", "--jsonl", "ls"]),
      CLIInvocation(
        output: .jsonl,
        command: .localID,
        arguments: ["ls"]
      )
    )
    expectNoDifference(
      try CLIArguments.parse(["sync", "status", "--json"]),
      CLIInvocation(
        output: .json,
        command: .sync,
        arguments: ["status"]
      )
    )
    expectNoDifference(
      try CLIArguments.parse(["sync", "--jsonl", "mark-processed", "tx-1"]),
      CLIInvocation(
        output: .jsonl,
        command: .sync,
        arguments: ["mark-processed", "tx-1"]
      )
    )
    expectNoDifference(
      try CLIArguments.parse(["app", "status", "--json"]),
      CLIInvocation(
        output: .json,
        command: .app,
        arguments: ["status"]
      )
    )
    expectNoDifference(
      try CLIArguments.parse(["app", "--jsonl", "ephemeral", "--title", "Reminders"]),
      CLIInvocation(
        output: .jsonl,
        command: .app,
        arguments: ["ephemeral", "--title", "Reminders"]
      )
    )
    expectNoDifference(
      try CLIArguments.parse(["admin", "query", "notes", "--limit", "2", "--json"]),
      CLIInvocation(
        output: .json,
        command: .admin,
        arguments: ["query", "notes", "--limit", "2"]
      )
    )
    expectNoDifference(
      try CLIArguments.parse(["admin", "--jsonl", "tx", "notes", "note-1", "--merge", "{}"]),
      CLIInvocation(
        output: .jsonl,
        command: .admin,
        arguments: ["tx", "notes", "note-1", "--merge", "{}"]
      )
    )
    expectNoDifference(
      try CLIArguments.parse(["query", "todos", "--limit", "2", "--json"]),
      CLIInvocation(
        output: .json,
        command: .query,
        arguments: ["todos", "--limit", "2"]
      )
    )
    expectNoDifference(
      try CLIArguments.parse(["validation", "--jsonl", "todos"]),
      CLIInvocation(
        output: .jsonl,
        command: .validation,
        arguments: ["todos"]
      )
    )
    expectNoDifference(
      try CLIArguments.parse(["init", "--example", "todos", "--to", "Out", "--json"]),
      CLIInvocation(
        output: .json,
        command: .initScaffold,
        arguments: ["--example", "todos", "--to", "Out"]
      )
    )
    expectNoDifference(
      try CLIArguments.parse(["perms", "--jsonl", "generate", "--example", "todos"]),
      CLIInvocation(
        output: .jsonl,
        command: .permissions,
        arguments: ["generate", "--example", "todos"]
      )
    )
    expectNoDifference(
      try CLIArguments.parse(["cache", "attrs", "todos", "--json"]),
      CLIInvocation(
        output: .json,
        command: .cache,
        arguments: ["attrs", "todos"]
      )
    )
    expectNoDifference(
      try CLIArguments.parse(["cache", "--jsonl", "facts"]),
      CLIInvocation(
        output: .jsonl,
        command: .cache,
        arguments: ["facts"]
      )
    )
    expectNoDifference(
      try CLIArguments.parse(["outbox", "transport", "--all", "--json"]),
      CLIInvocation(
        output: .json,
        command: .outbox,
        arguments: ["transport", "--all"]
      )
    )
    expectNoDifference(
      try CLIArguments.parse(["outbox", "--jsonl", "drain", "--local-confirm"]),
      CLIInvocation(
        output: .jsonl,
        command: .outbox,
        arguments: ["drain", "--local-confirm"]
      )
    )
    expectNoDifference(
      try CLIArguments.parse([
        "streams", "append", "chat/lobby", "--value", "{}", "--jsonl",
      ]),
      CLIInvocation(
        output: .jsonl,
        command: .streams,
        arguments: ["append", "chat/lobby", "--value", "{}"]
      )
    )
  }

  @Test
  func authParserParsesCommandsAndAliases() throws {
    expectNoDifference(try parseAuth(["show"]), .show)
    expectNoDifference(try parseAuth(["status"]), .show)
    expectNoDifference(try parseAuth(["guest"]), .guest)
    expectNoDifference(
      try parseAuth(["token", "refresh-token", "--user-id", " user-1 "]),
      .token(CLIAuthTokenInvocation(refreshToken: "refresh-token", userID: " user-1 "))
    )
    expectNoDifference(
      try parseAuth(["id-token", "google-ios", " local-jwt ", "--nonce", " nonce-1 "]),
      .idToken(
        CLIAuthIDTokenInvocation(
          clientName: "google-ios",
          idToken: " local-jwt ",
          nonce: " nonce-1 "
        )
      )
    )
    expectNoDifference(
      try parseAuth(["idtoken", "google-ios", "local-jwt"]),
      .idToken(CLIAuthIDTokenInvocation(clientName: "google-ios", idToken: "local-jwt"))
    )
    expectNoDifference(
      try parseAuth(["oauth", " local-code ", "--code-verifier", " verifier-1 "]),
      .oauth(CLIAuthOAuthInvocation(code: " local-code ", codeVerifier: " verifier-1 "))
    )
    expectNoDifference(
      try parseAuth(["oauth-url", "google-ios", "myapp://oauth/callback?state=abc"]),
      .oauthURL(
        CLIAuthOAuthURLInvocation(
          clientName: "google-ios",
          redirectURL: "myapp://oauth/callback?state=abc"
        )
      )
    )
    expectNoDifference(
      try parseAuth(["authorization-url", "google-ios", "myapp://oauth/callback"]),
      .oauthURL(
        CLIAuthOAuthURLInvocation(
          clientName: "google-ios",
          redirectURL: "myapp://oauth/callback"
        )
      )
    )
    expectNoDifference(try parseAuth(["issuer"]), .issuer)
    expectNoDifference(try parseAuth(["issuer-uri"]), .issuer)
    expectNoDifference(
      try parseAuth(["magic-code", "send", " user@example.com "]),
      .magicCode(.send(email: " user@example.com "))
    )
    expectNoDifference(
      try parseAuth(["magic", "verify", "user@example.com", "123456"]),
      .magicCode(.verify(email: "user@example.com", code: "123456"))
    )
    expectNoDifference(
      try parseAuth(["watch", "--events", "1"]),
      .watch(CLIAuthWatchInvocation(eventCount: 1))
    )
    expectNoDifference(
      try parseAuth(["observe"]),
      .watch(CLIAuthWatchInvocation())
    )
    expectNoDifference(
      try parseAuth(["sign-out"]),
      .signOut(CLIAuthSignOutInvocation())
    )
    expectNoDifference(
      try parseAuth(["signout", "--skip-token-invalidation"]),
      .signOut(CLIAuthSignOutInvocation(invalidateToken: false))
    )
    expectNoDifference(
      try parseAuth(["logout", "--skip-token-invalidation", "--invalidate-token"]),
      .signOut(CLIAuthSignOutInvocation(invalidateToken: true))
    )
  }

  @Test
  func authParserReportsMalformedArguments() throws {
    try expectAuthParseError([], contains: "Usage: instant-swift-data auth")
    try expectAuthParseError(
      ["show", "extra"],
      contains: "Unexpected argument: extra."
    )
    try expectAuthParseError(
      ["token"],
      contains: "auth token <refresh-token>"
    )
    try expectAuthParseError(
      ["token", "refresh-token", "--user-id"],
      contains: "Missing value for --user-id."
    )
    try expectAuthParseError(
      ["token", "refresh-token", "--user-id", "  "],
      contains: "Missing non-empty value for --user-id."
    )
    try expectAuthParseError(
      ["token", "refresh-token", "--surprise"],
      contains: "Unknown auth token option: --surprise."
    )
    try expectAuthParseError(
      ["id-token", "google-ios"],
      contains: "auth id-token <client-name> <id-token>"
    )
    try expectAuthParseError(
      ["id-token", "google-ios", "local-jwt", "--nonce", " "],
      contains: "Missing non-empty value for --nonce."
    )
    try expectAuthParseError(
      ["oauth", "local-code", "--code-verifier", " "],
      contains: "Missing non-empty value for --code-verifier."
    )
    try expectAuthParseError(
      ["oauth-url", "google-ios"],
      contains: "auth oauth-url <client-name> <redirect-url>"
    )
    try expectAuthParseError(
      ["issuer", "extra"],
      contains: "Unexpected argument: extra."
    )
    try expectAuthParseError(
      ["magic-code"],
      contains: "Usage: instant-swift-data auth magic-code"
    )
    try expectAuthParseError(
      ["magic-code", "send"],
      contains: "magic-code send <email>"
    )
    try expectAuthParseError(
      ["magic-code", "send", "user@example.com", "extra"],
      contains: "Unexpected argument: extra."
    )
    try expectAuthParseError(
      ["magic-code", "verify", "user@example.com"],
      contains: "magic-code verify <email> <code>"
    )
    try expectAuthParseError(
      ["magic-code", "dance"],
      contains: "Usage: instant-swift-data auth magic-code"
    )
    try expectAuthParseError(
      ["watch", "--events", "2"],
      contains: "instant-swift-data auth watch --events 1"
    )
    try expectAuthParseError(
      ["watch", "--surprise"],
      contains: "Unknown auth watch option: --surprise."
    )
    try expectAuthParseError(
      ["sign-out", "--surprise"],
      contains: "Unknown auth sign-out option: --surprise."
    )
    try expectAuthParseError(
      ["dance"],
      contains: "Usage: instant-swift-data auth"
    )
  }

  @Test
  func connectionParserParsesCommandsAndAliases() throws {
    expectNoDifference(try parseConnection(["status"]), .status)
    expectNoDifference(try parseConnection(["show"]), .status)
    expectNoDifference(try parseConnection(["inspect"]), .status)
    expectNoDifference(try parseConnection(["connect"]), .connect)
    expectNoDifference(try parseConnection(["open"]), .connect)
    expectNoDifference(try parseConnection(["close"]), .close)
    expectNoDifference(try parseConnection(["disconnect"]), .close)
  }

  @Test
  func connectionParserReportsMalformedArguments() throws {
    try expectConnectionParseError([], contains: "Usage: instant-swift-data connection")
    try expectConnectionParseError(
      ["status", "extra"],
      contains: "Unexpected argument: extra."
    )
    try expectConnectionParseError(
      ["open", "extra"],
      contains: "connection connect"
    )
    try expectConnectionParseError(
      ["disconnect", "extra"],
      contains: "connection close"
    )
    try expectConnectionParseError(
      ["dance"],
      contains: "Usage: instant-swift-data connection"
    )
  }

  @Test
  func localIDParserParsesCommandsAndAliases() throws {
    expectNoDifference(
      try parseLocalID(["get", " todos.viewer "]),
      .get(name: " todos.viewer ")
    )
    expectNoDifference(try parseLocalID(["list"]), .list)
    expectNoDifference(try parseLocalID(["ls"]), .list)
  }

  @Test
  func localIDParserReportsMalformedArguments() throws {
    try expectLocalIDParseError([], contains: "Usage: instant-swift-data local-id")
    try expectLocalIDParseError(
      ["get"],
      contains: "local-id get <name>"
    )
    try expectLocalIDParseError(
      ["get", "  "],
      contains: "local-id get <name>"
    )
    try expectLocalIDParseError(
      ["get", "todos.viewer", "extra"],
      contains: "Unexpected argument: extra."
    )
    try expectLocalIDParseError(
      ["list", "extra"],
      contains: "local-id list"
    )
    try expectLocalIDParseError(
      ["dance"],
      contains: "Usage: instant-swift-data local-id"
    )
  }

  @Test
  func syncParserParsesCommandsAndAliases() throws {
    expectNoDifference(try parseSync(["inspect"]), .inspect)
    expectNoDifference(try parseSync(["show"]), .inspect)
    expectNoDifference(try parseSync(["status"]), .inspect)
    expectNoDifference(
      try parseSync(["mark-processed", " tx-1 "]),
      .markProcessed(transactionID: " tx-1 ")
    )
  }

  @Test
  func syncParserReportsMalformedArguments() throws {
    try expectSyncParseError([], contains: "Usage: instant-swift-data sync")
    try expectSyncParseError(
      ["inspect", "extra"],
      contains: "Unexpected argument: extra."
    )
    try expectSyncParseError(
      ["mark-processed"],
      contains: "sync mark-processed <tx-id>"
    )
    try expectSyncParseError(
      ["mark-processed", "  "],
      contains: "sync mark-processed <tx-id>"
    )
    try expectSyncParseError(
      ["mark-processed", "tx-1", "extra"],
      contains: "Unexpected argument: extra."
    )
    try expectSyncParseError(
      ["dance"],
      contains: "Usage: instant-swift-data sync"
    )
  }

  @Test
  func initParserParsesOptions() throws {
    expectNoDifference(
      try parseInit(["--example", "todos", "--to", "Scaffold"]),
      CLIScaffoldInvocation(example: "todos", outputDirectory: "Scaffold")
    )
    expectNoDifference(
      try parseInit([
        "--example", "rooms", "--example", "todos", "--to", "First", "--to", "Second",
        "--force",
      ]),
      CLIScaffoldInvocation(example: "todos", outputDirectory: "Second", force: true)
    )
  }

  @Test
  func initParserReportsMalformedArguments() throws {
    try expectInitParseError([], description: CLIInitUsage.initScaffold)
    try expectInitParseError(
      ["--example", "todos"],
      description: CLIInitUsage.initScaffold
    )
    try expectInitParseError(
      ["--example"],
      description: CLIInitUsage.initScaffold
    )
    try expectInitParseError(
      ["--example", "todos", "--to", "  "],
      description: CLIInitUsage.initScaffold
    )
    try expectInitParseError(
      ["--example", "todos", "--to", "Out", "--unknown"],
      description: "Unknown init option: --unknown. \(CLIInitUsage.initScaffold)"
    )
  }

  @Test
  func schemaParserParsesGenerateAndVerifyOptions() throws {
    expectNoDifference(
      try parseSchema(["generate", "--example", "todos"]),
      .generate(CLIGenerateArtifactInvocation(example: "todos"))
    )
    expectNoDifference(
      try parseSchema([
        "generate", "--example", "rooms", "--example", "todos", "--to", "old.ts",
        "--to", "instant.schema.ts",
      ]),
      .generate(CLIGenerateArtifactInvocation(example: "todos", outputPath: "instant.schema.ts"))
    )
    expectNoDifference(
      try parseSchema(["verify", "--example", "todos", "--from", "instant.schema.ts"]),
      .verify(CLIVerifyArtifactInvocation(example: "todos", inputPath: "instant.schema.ts"))
    )
  }

  @Test
  func schemaParserReportsMalformedArguments() throws {
    try expectSchemaParseError([], description: CLISchemaUsage.generate)
    try expectSchemaParseError(["dance"], description: CLISchemaUsage.generate)
    try expectSchemaParseError(["generate"], description: CLISchemaUsage.generate)
    try expectSchemaParseError(
      ["generate", "--example"],
      description: CLISchemaUsage.generate
    )
    try expectSchemaParseError(
      ["generate", "--unknown"],
      description: "Unknown generate option: --unknown. \(CLISchemaUsage.generate)"
    )
    try expectSchemaParseError(["verify"], description: CLISchemaUsage.verify)
    try expectSchemaParseError(
      ["verify", "--example", "todos", "--from"],
      description: CLISchemaUsage.verify
    )
    try expectSchemaParseError(
      ["verify", "--unknown"],
      description: "Unknown schema verify option: --unknown. \(CLISchemaUsage.verify)"
    )
  }

  @Test
  func permissionsParserParsesGenerateAndVerifyOptions() throws {
    expectNoDifference(
      try parsePermissions(["generate", "--example", "todos"]),
      .generate(CLIGenerateArtifactInvocation(example: "todos"))
    )
    expectNoDifference(
      try parsePermissions([
        "generate", "--example", "rooms", "--example", "todos", "--to", "old.ts",
        "--to", "instant.perms.ts",
      ]),
      .generate(CLIGenerateArtifactInvocation(example: "todos", outputPath: "instant.perms.ts"))
    )
    expectNoDifference(
      try parsePermissions(["verify", "--example", "todos", "--from", "instant.perms.ts"]),
      .verify(CLIVerifyArtifactInvocation(example: "todos", inputPath: "instant.perms.ts"))
    )
  }

  @Test
  func permissionsParserReportsMalformedArguments() throws {
    try expectPermissionsParseError([], description: CLIPermissionsUsage.generate)
    try expectPermissionsParseError(["dance"], description: CLIPermissionsUsage.generate)
    try expectPermissionsParseError(["generate"], description: CLIPermissionsUsage.generate)
    try expectPermissionsParseError(
      ["generate", "--example"],
      description: CLIPermissionsUsage.generate
    )
    try expectPermissionsParseError(
      ["generate", "--unknown"],
      description: "Unknown generate option: --unknown. \(CLIPermissionsUsage.generate)"
    )
    try expectPermissionsParseError(["verify"], description: CLIPermissionsUsage.verify)
    try expectPermissionsParseError(
      ["verify", "--example", "todos", "--from"],
      description: CLIPermissionsUsage.verify
    )
    try expectPermissionsParseError(
      ["verify", "--unknown"],
      description: "Unknown permissions verify option: --unknown. \(CLIPermissionsUsage.verify)"
    )
  }

  @Test
  func appParserParsesCommandsAndAliases() throws {
    expectNoDifference(try parseApp(["show"]), .show)
    expectNoDifference(try parseApp(["status"]), .show)
    expectNoDifference(try parseApp(["current"]), .show)
    expectNoDifference(
      try parseApp(["select", " local-demo "]),
      .select(appID: " local-demo ")
    )
    expectNoDifference(
      try parseApp(["ephemeral", "--title", " Reminders Port "]),
      .ephemeral(CLIAppEphemeralInvocation(title: " Reminders Port "))
    )
    expectNoDifference(
      try parseApp(["ephemeral", "--title", "First", "--title", "Second"]),
      .ephemeral(CLIAppEphemeralInvocation(title: "Second"))
    )
  }

  @Test
  func appParserReportsMalformedArguments() throws {
    try expectAppParseError([], contains: "Usage: instant-swift-data app")
    try expectAppParseError(
      ["show", "extra"],
      contains: "Unexpected argument: extra."
    )
    try expectAppParseError(
      ["select"],
      contains: "app select <app-id>"
    )
    try expectAppParseError(
      ["select", "  "],
      contains: "app select <app-id>"
    )
    try expectAppParseError(
      ["select", "local-demo", "extra"],
      contains: "Unexpected argument: extra."
    )
    try expectAppParseError(
      ["ephemeral"],
      contains: "app ephemeral --title <title>"
    )
    try expectAppParseError(
      ["ephemeral", "--title"],
      contains: "app ephemeral --title <title>"
    )
    try expectAppParseError(
      ["ephemeral", "--title", "   "],
      contains: "app ephemeral --title <title>"
    )
    try expectAppParseError(
      ["ephemeral", "--surprise"],
      contains: "Unknown ephemeral app option: --surprise."
    )
    try expectAppParseError(
      ["dance"],
      contains: "Usage: instant-swift-data app"
    )
  }

  @Test
  func queryParserParsesTodosOptions() throws {
    expectNoDifference(
      try parseQuery(["todos"]),
      .todos(CLITodosQueryInvocation())
    )
    expectNoDifference(
      try parseQuery([
        "todos", "--completed", "false", "--completed", "1", "--search", " milk ",
        "--offset", "2", "--limit", "1", "--limit", "3", "--first", "4",
        "--after", "note-1", "--after-inclusive", " note-2 ", "--order", "descending",
        "--order-by", "serverCreatedAt", "--raw", "--select", "title, done,title",
      ]),
      .todos(
        CLITodosQueryInvocation(
          completed: true,
          search: " milk ",
          offset: 2,
          limit: 3,
          first: 4,
          after: CLIQueryCursor(entityID: "note-2", inclusive: true),
          direction: .descending,
          orderField: .serverCreatedAt,
          selectedFields: ["done", "title"],
          rawSnapshots: true
        )
      )
    )
    expectNoDifference(
      try parseQuery([
        "todos", "--last", "2", "--before", " note-9 ", "--order", "asc",
        "--order-by", "none", "--snapshots",
      ]),
      .todos(
        CLITodosQueryInvocation(
          last: 2,
          before: CLIQueryCursor(entityID: "note-9"),
          orderField: .none,
          rawSnapshots: true
        )
      )
    )
  }

  @Test
  func queryParserReportsMalformedTodosArguments() throws {
    try expectQueryParseError([], description: CLIQueryUsage.query)
    try expectQueryParseError(["rooms"], description: CLIQueryUsage.query)
    try expectQueryParseError(
      ["todos", "--completed"],
      description: "Usage: \(CLIQueryUsage.todosCommand) --completed true|false"
    )
    try expectQueryParseError(
      ["todos", "--completed", "maybe"],
      description: "Usage: \(CLIQueryUsage.todosCommand) --completed true|false"
    )
    try expectQueryParseError(
      ["todos", "--search", "  "],
      description: "Usage: \(CLIQueryUsage.todosCommand) --search text"
    )
    try expectQueryParseError(
      ["todos", "--offset", "-1"],
      description: "Usage: \(CLIQueryUsage.todosCommand) --offset n"
    )
    try expectQueryParseError(
      ["todos", "--limit", "nope"],
      description: "Usage: \(CLIQueryUsage.todosCommand) --limit n"
    )
    try expectQueryParseError(
      ["todos", "--first", "-1"],
      description: "Usage: \(CLIQueryUsage.todosCommand) --first n"
    )
    try expectQueryParseError(
      ["todos", "--after", "  "],
      description: "Usage: \(CLIQueryUsage.todosCommand) --after id"
    )
    try expectQueryParseError(
      ["todos", "--last", "-1"],
      description: "Usage: \(CLIQueryUsage.todosCommand) --last n"
    )
    try expectQueryParseError(
      ["todos", "--before-inclusive"],
      description: "Usage: \(CLIQueryUsage.todosCommand) --before-inclusive id"
    )
    try expectQueryParseError(
      ["todos", "--order", "sideways"],
      description: "Usage: \(CLIQueryUsage.todosCommand) --order asc|desc"
    )
    try expectQueryParseError(
      ["todos", "--order-by", "title"],
      description: "Usage: \(CLIQueryUsage.todosCommand) --order-by none|createdAt|serverCreatedAt"
    )
    try expectQueryParseError(
      ["todos", "--select", " , "],
      description: "Usage: \(CLIQueryUsage.todosCommand) --select field[,field]"
    )
    try expectQueryParseError(
      ["todos", "--first", "1", "--last", "1"],
      description: "Use either --first or --last, not both. Usage: \(CLIQueryUsage.todos)"
    )
    try expectQueryParseError(
      ["todos", "--unknown"],
      description: "Unknown todo query option: --unknown. Usage: \(CLIQueryUsage.todos)"
    )
  }

  @Test
  func validationParserParsesCommandsAndAliases() throws {
    expectNoDifference(try parseValidation(["local-todos"]), .localTodos)
    expectNoDifference(try parseValidation(["todos"]), .localTodos)
    expectNoDifference(try parseValidation(["local-integrations"]), .localIntegrations)
    expectNoDifference(try parseValidation(["integrations"]), .localIntegrations)
  }

  @Test
  func validationParserReportsMalformedArguments() throws {
    try expectValidationParseError([], description: CLIValidationUsage.validation)
    try expectValidationParseError(["remote"], description: CLIValidationUsage.validation)
    try expectValidationParseError(["todos", "extra"], description: CLIValidationUsage.validation)
  }

  @Test
  func adminParserParsesCommandsOptionsAndAliases() throws {
    expectNoDifference(
      try parseAdmin(["query", "notes"]),
      .query(CLIAdminQueryInvocation(namespace: "notes"))
    )
    expectNoDifference(
      try parseAdmin(["query", " notes ", "--limit", "1", "--limit", "3"]),
      .query(CLIAdminQueryInvocation(namespace: "notes", limit: 3))
    )
    expectNoDifference(
      try parseAdmin(["transact", "notes", "note-1", "--merge", #"{"title":"Hi"}"#]),
      .transact(
        CLIAdminTransactInvocation(
          namespace: "notes",
          entityID: "note-1",
          mergeJSON: #"{"title":"Hi"}"#
        )
      )
    )
    expectNoDifference(
      try parseAdmin([
        "tx", " notes ", " note-1 ", "--merge", #"{"title":"Hi"}"#,
        "--transaction-id", " tx-1 ",
      ]),
      .transact(
        CLIAdminTransactInvocation(
          namespace: "notes",
          entityID: "note-1",
          mergeJSON: #"{"title":"Hi"}"#,
          transactionID: "tx-1"
        )
      )
    )
  }

  @Test
  func adminParserReportsMalformedArguments() throws {
    try expectAdminParseError([], description: CLIAdminUsage.admin)
    try expectAdminParseError(["dance"], description: CLIAdminUsage.admin)
    try expectAdminParseError(["query"], description: CLIAdminUsage.query)
    try expectAdminParseError(
      ["query", "bad/namespace"],
      description: "\(CLIAdminUsage.query): namespace must not be empty or contain whitespace or '/'."
    )
    try expectAdminParseError(
      ["query", "notes", "--limit"],
      description: "\(CLIAdminUsage.query): --limit must be a non-negative integer."
    )
    try expectAdminParseError(
      ["query", "notes", "--limit", "-1"],
      description: "\(CLIAdminUsage.query): --limit must be a non-negative integer."
    )
    try expectAdminParseError(
      ["query", "notes", "--unknown"],
      description: "Unknown admin query option: --unknown. \(CLIAdminUsage.query)"
    )
    try expectAdminParseError(["transact", "notes"], description: CLIAdminUsage.transact)
    try expectAdminParseError(
      ["transact", "bad namespace", "note-1", "--merge", "{}"],
      description: "\(CLIAdminUsage.transact): namespace must not be empty or contain whitespace or '/'."
    )
    try expectAdminParseError(
      ["transact", "notes", "  ", "--merge", "{}"],
      description: "\(CLIAdminUsage.transact): entity id must not be empty."
    )
    try expectAdminParseError(
      ["transact", "notes", "note-1"],
      description: CLIAdminUsage.transact
    )
    try expectAdminParseError(
      ["transact", "notes", "note-1", "--merge"],
      description: CLIAdminUsage.transact
    )
    try expectAdminParseError(
      ["transact", "notes", "note-1", "--merge", "{}", "--merge", "{}"],
      description: CLIAdminUsage.transact
    )
    try expectAdminParseError(
      ["transact", "notes", "note-1", "--merge", "{}", "--transaction-id", "  "],
      description: "\(CLIAdminUsage.transact): transaction id must not be empty."
    )
    try expectAdminParseError(
      [
        "transact", "notes", "note-1", "--merge", "{}", "--transaction-id", "tx-1",
        "--transaction-id", "tx-2",
      ],
      description: CLIAdminUsage.transact
    )
    try expectAdminParseError(
      ["transact", "notes", "note-1", "--merge", "{}", "--unknown"],
      description: "Unknown admin transact option: --unknown. \(CLIAdminUsage.transact)"
    )
  }

  @Test
  func cacheParserParsesCommandsAndAliases() throws {
    expectNoDifference(try parseCache(["inspect"]), .inspect)
    expectNoDifference(try parseCache(["attributes"]), .attributes(namespace: nil))
    expectNoDifference(
      try parseCache(["attributes", " todos "]),
      .attributes(namespace: "todos")
    )
    expectNoDifference(
      try parseCache(["attrs", "todos"]),
      .attributes(namespace: "todos")
    )
    expectNoDifference(try parseCache(["triples"]), .triples(namespace: nil))
    expectNoDifference(
      try parseCache(["triples", "todos"]),
      .triples(namespace: "todos")
    )
    expectNoDifference(
      try parseCache(["facts", "todos"]),
      .triples(namespace: "todos")
    )
  }

  @Test
  func cacheParserReportsMalformedArguments() throws {
    try expectCacheParseError([], contains: "Usage: instant-swift-data cache")
    try expectCacheParseError(
      ["inspect", "extra"],
      description: CLICacheUsage.inspect
    )
    try expectCacheParseError(
      ["attributes", "todos", "extra"],
      description: CLICacheUsage.attributes
    )
    try expectCacheParseError(
      ["attributes", "  "],
      contains: "namespace must not be empty"
    )
    try expectCacheParseError(
      ["attributes", "todo list"],
      contains: "namespace must not be empty or contain whitespace or '/'"
    )
    try expectCacheParseError(
      ["triples", "todos/items"],
      contains: "namespace must not be empty or contain whitespace or '/'"
    )
    try expectCacheParseError(
      ["dance"],
      contains: "Usage: instant-swift-data cache"
    )
  }

  @Test
  func outboxParserParsesCommandsOptionsAndAliases() throws {
    expectNoDifference(try parseOutbox(["inspect"]), .inspect)
    expectNoDifference(
      try parseOutbox(["transport"]),
      .transport(includeFailed: false)
    )
    expectNoDifference(
      try parseOutbox(["wire", "--all"]),
      .transport(includeFailed: true)
    )
    expectNoDifference(
      try parseOutbox(["tx-steps", "--all"]),
      .transport(includeFailed: true)
    )
    expectNoDifference(
      try parseOutbox(["flush"]),
      .flush(limit: nil)
    )
    expectNoDifference(
      try parseOutbox(["send", "--limit", "1", "--limit", "3"]),
      .flush(limit: 3)
    )
    expectNoDifference(
      try parseOutbox(["confirm", "mutation-1"]),
      .confirm(mutationID: "mutation-1")
    )
    expectNoDifference(
      try parseOutbox(["confirm", ""]),
      .confirm(mutationID: "")
    )
    expectNoDifference(
      try parseOutbox(["fail", "mutation-1", "server", "rejected"]),
      .fail(mutationID: "mutation-1", message: "server rejected")
    )
    expectNoDifference(
      try parseOutbox(["fail", "", "server", "rejected"]),
      .fail(mutationID: "", message: "server rejected")
    )
    expectNoDifference(
      try parseOutbox(["retry", "mutation-1"]),
      .retry(mutationID: "mutation-1")
    )
    expectNoDifference(
      try parseOutbox(["retry", ""]),
      .retry(mutationID: "")
    )
    expectNoDifference(
      try parseOutbox(["drain", "--local-confirm"]),
      .drain(limit: nil)
    )
    expectNoDifference(
      try parseOutbox(["drain", "--limit", "1", "--local-confirm", "--limit", "2"]),
      .drain(limit: 2)
    )
  }

  @Test
  func outboxParserReportsMalformedArguments() throws {
    try expectOutboxParseError([], description: CLIOutboxUsage.outbox)
    try expectOutboxParseError(["dance"], description: CLIOutboxUsage.outbox)
    try expectOutboxParseError(["inspect", "extra"], description: CLIOutboxUsage.inspect)
    try expectOutboxParseError(
      ["transport", "--unknown"],
      description: CLIOutboxUsage.transport
    )
    try expectOutboxParseError(["flush", "--limit"], description: CLIOutboxUsage.flush)
    try expectOutboxParseError(["flush", "--limit", "-1"], description: CLIOutboxUsage.flush)
    try expectOutboxParseError(
      ["flush", "--unknown"],
      description: "Unknown outbox flush option: --unknown. \(CLIOutboxUsage.flush)"
    )
    try expectOutboxParseError(["confirm"], description: CLIOutboxUsage.confirm)
    try expectOutboxParseError(["confirm", "mutation-1", "extra"], description: CLIOutboxUsage.confirm)
    try expectOutboxParseError(["fail"], description: CLIOutboxUsage.fail)
    try expectOutboxParseError(["fail", "mutation-1", "  "], description: CLIOutboxUsage.fail)
    try expectOutboxParseError(["retry"], description: CLIOutboxUsage.retry)
    try expectOutboxParseError(["retry", "mutation-1", "extra"], description: CLIOutboxUsage.retry)
    try expectOutboxParseError(["drain"], description: CLIOutboxUsage.drain)
    try expectOutboxParseError(["drain", "--limit", "1"], description: CLIOutboxUsage.drain)
    try expectOutboxParseError(
      ["drain", "--local-confirm", "--limit", "oops"],
      description: CLIOutboxUsage.drain
    )
    try expectOutboxParseError(
      ["drain", "--unknown"],
      description: "Unknown outbox drain option: --unknown. \(CLIOutboxUsage.drain)"
    )
  }

  @Test
  func examplesParserKeepsLegacyDispatchForOtherExamplesAndUnknowns() throws {
    expectNoDifference(
      try parseExamples(["syncups", "add", "Daily"]),
      .syncUps(arguments: ["add", "Daily"])
    )
    expectNoDifference(
      try parseExamples(["sync-ups", "list"]),
      .syncUps(arguments: ["list"])
    )
    expectNoDifference(
      try parseExamples(["reminders", "list", "--today"]),
      .reminders(arguments: ["list", "--today"])
    )
    expectNoDifference(
      try parseExamples(["todo-links", "seed"]),
      .todoLinks(arguments: ["seed"])
    )
    expectNoDifference(
      try parseExamples(["chat", "seed"]),
      .unknown("chat", arguments: ["seed"])
    )
    expectNoDifference(
      try parseExamples(["todos"]),
      .todos(CLIExamplesTodosInvocation(command: nil, arguments: []))
    )
    expectNoDifference(
      try parseExamples(["todos", "dance", "--fast"]),
      .todos(
        CLIExamplesTodosInvocation(
          command: .unknown("dance"),
          arguments: ["--fast"]
        )
      )
    )
  }

  @Test
  func roomsParserParsesPresenceCommands() throws {
    expectNoDifference(
      try parseRooms([
        "presence", "set", " chat ", " lobby ", "--value", "{\"status\":\"online\"}",
        "--user-id", " user-1 ",
      ]),
      .presence(
        .set(
          CLIRoomPresenceSetInvocation(
            room: CLIRoomIdentifier(type: "chat", id: "lobby"),
            userID: "user-1",
            value: "{\"status\":\"online\"}"
          )
        )
      )
    )
    expectNoDifference(
      try parseRooms(["presence", "list", "chat", "lobby"]),
      .presence(.list(CLIRoomIdentifier(type: "chat", id: "lobby")))
    )
    expectNoDifference(
      try parseRooms(["presence", "watch", "chat", "lobby", "--events", "1"]),
      .presence(
        .watch(
          CLIRoomPresenceWatchInvocation(
            room: CLIRoomIdentifier(type: "chat", id: "lobby"),
            eventCount: 1
          )
        )
      )
    )
    expectNoDifference(
      try parseRooms(["presence", "leave", "chat", "lobby", "--user-id", " user-1 "]),
      .presence(
        .leave(
          CLIRoomPresenceLeaveInvocation(
            room: CLIRoomIdentifier(type: "chat", id: "lobby"),
            userID: "user-1"
          )
        )
      )
    )
  }

  @Test
  func roomsParserParsesTopicCommandsAndAliases() throws {
    expectNoDifference(
      try parseRooms([
        "topic", "publish", "chat", "lobby", " sendEmoji ", "--value", "{\"emoji\":\"wave\"}",
        "--user-id", " user-1 ",
      ]),
      .topics(
        .publish(
          CLIRoomTopicPublishInvocation(
            room: CLIRoomIdentifier(type: "chat", id: "lobby"),
            topic: "sendEmoji",
            userID: "user-1",
            value: "{\"emoji\":\"wave\"}"
          )
        )
      )
    )
    expectNoDifference(
      try parseRooms(["topics", "list", "chat", "lobby", "sendEmoji", "--limit", "2"]),
      .topics(
        .list(
          CLIRoomTopicListInvocation(
            room: CLIRoomIdentifier(type: "chat", id: "lobby"),
            topic: "sendEmoji",
            limit: 2
          )
        )
      )
    )
    expectNoDifference(
      try parseRooms(["topics", "watch", "chat", "lobby", "sendEmoji", "--events", "1"]),
      .topics(
        .watch(
          CLIRoomTopicWatchInvocation(
            room: CLIRoomIdentifier(type: "chat", id: "lobby"),
            topic: "sendEmoji",
            eventCount: 1
          )
        )
      )
    )
  }

  @Test
  func roomsParserPreservesDuplicateValuesInOrder() throws {
    expectNoDifference(
      try parseRooms([
        "presence", "set", "chat", "lobby",
        "--value", "not-json",
        "--value", "{\"status\":\"online\"}",
      ]),
      .presence(
        .set(
          CLIRoomPresenceSetInvocation(
            room: CLIRoomIdentifier(type: "chat", id: "lobby"),
            values: ["not-json", "{\"status\":\"online\"}"]
          )
        )
      )
    )
    expectNoDifference(
      try parseRooms([
        "topics", "publish", "chat", "lobby", "sendEmoji",
        "--value", "not-json",
        "--value", "{\"emoji\":\"wave\"}",
      ]),
      .topics(
        .publish(
          CLIRoomTopicPublishInvocation(
            room: CLIRoomIdentifier(type: "chat", id: "lobby"),
            topic: "sendEmoji",
            values: ["not-json", "{\"emoji\":\"wave\"}"]
          )
        )
      )
    )
  }

  @Test
  func roomsParserReportsMalformedArguments() throws {
    try expectRoomsParseError([], contains: "Usage: instant-swift-data rooms")
    try expectRoomsParseError(
      ["presence", "set", "chat", "lobby"],
      contains: "Missing required option --value."
    )
    try expectRoomsParseError(
      ["presence", "set", "chat", "lobby", "--user-id", "  ", "--value", "{}"],
      contains: "Missing non-empty value for --user-id."
    )
    try expectRoomsParseError(
      ["presence", "watch", "chat", "lobby", "--events", "2"],
      contains: "rooms presence watch <room-type> <room-id> --events 1"
    )
    try expectRoomsParseError(
      ["topics", "list", "chat", "lobby", "sendEmoji", "--limit", "-1"],
      contains: "Invalid --limit value: -1."
    )
    try expectRoomsParseError(
      ["topics", "watch", "chat", "lobby", "sendEmoji", "--surprise"],
      contains: "Unknown rooms topics watch option: --surprise."
    )
  }

  @Test
  func filesParserParsesCommandsAndAliases() throws {
    expectNoDifference(
      try parseFiles([
        "upload", " ./photo.jpg ", "--name", " Uploaded Photo ", "--content-type",
        " image/jpeg ",
      ]),
        .upload(
        CLIFileUploadInvocation(
          sourcePath: " ./photo.jpg ",
          name: "Uploaded Photo",
          contentType: "image/jpeg"
        )
      )
    )
    expectNoDifference(
      try parseFiles(["put", "./photo.jpg"]),
      .upload(CLIFileUploadInvocation(sourcePath: "./photo.jpg"))
    )
    expectNoDifference(
      try parseFiles([
        "upload", "./photo.jpg",
        "--name", "first.jpg",
        "--name", "second.jpg",
        "--content-type", "image/jpeg",
      ]),
      .upload(
        CLIFileUploadInvocation(
          sourcePath: "./photo.jpg",
          name: "second.jpg",
          contentType: "image/jpeg"
        )
      )
    )
    expectNoDifference(
      try parseFiles(["upload-progress", "./photo.jpg", "--content-type", "image/jpeg"]),
      .uploadProgress(
        CLIFileUploadInvocation(sourcePath: "./photo.jpg", contentType: "image/jpeg")
      )
    )
    expectNoDifference(
      try parseFiles(["progress", "./photo.jpg"]),
      .uploadProgress(CLIFileUploadInvocation(sourcePath: "./photo.jpg"))
    )
    expectNoDifference(try parseFiles(["list"]), .list)
    expectNoDifference(try parseFiles(["ls"]), .list)
    expectNoDifference(
      try parseFiles(["watch", "--events", "1"]),
      .watch(CLIFilesWatchInvocation(eventCount: 1))
    )
    expectNoDifference(
      try parseFiles(["read", " file-1 "]),
      .read(fileID: "file-1")
    )
    expectNoDifference(
      try parseFiles(["cat", "file-1"]),
      .read(fileID: "file-1")
    )
    expectNoDifference(
      try parseFiles(["delete", " file-1 "]),
      .delete(fileID: "file-1")
    )
    expectNoDifference(
      try parseFiles(["rm", "file-1"]),
      .delete(fileID: "file-1")
    )
  }

  @Test
  func filesParserReportsMalformedArguments() throws {
    try expectFilesParseError([], contains: "Usage: instant-swift-data files")
    try expectFilesParseError(
      ["upload"],
      contains: "files upload <path>"
    )
    try expectFilesParseError(
      ["upload", "  "],
      contains: "files upload <path>"
    )
    try expectFilesParseError(
      ["upload", "./photo.jpg", "--name"],
      contains: "Missing value for --name."
    )
    try expectFilesParseError(
      ["upload", "./photo.jpg", "--name", "  "],
      contains: "Missing non-empty value for --name."
    )
    try expectFilesParseError(
      ["upload", "./photo.jpg", "--surprise"],
      contains: "Unknown files upload option: --surprise."
    )
    try expectFilesParseError(
      ["list", "extra"],
      contains: "Unexpected argument: extra."
    )
    try expectFilesParseError(
      ["watch", "--events", "2"],
      contains: "instant-swift-data files watch --events 1"
    )
    try expectFilesParseError(
      ["watch", "--surprise"],
      contains: "Unknown files watch option: --surprise."
    )
    try expectFilesParseError(
      ["read"],
      contains: "files read <file-id>"
    )
    try expectFilesParseError(
      ["delete", "file-1", "--force"],
      contains: "Unexpected argument: --force."
    )
    try expectFilesParseError(
      ["dance"],
      contains: "Usage: instant-swift-data files"
    )
  }

  @Test
  func sharesParserParsesCommandsAndAliases() throws {
    expectNoDifference(
      try parseShares(["create", " todos ", " todo-1 "]),
      .create(CLISharesCreateInvocation(namespace: "todos", entityID: "todo-1"))
    )
    expectNoDifference(
      try parseShares(["list"]),
      .list
    )
    expectNoDifference(
      try parseShares(["ls"]),
      .list
    )
    expectNoDifference(
      try parseShares(["accept", " local-share-token "]),
      .accept(token: "local-share-token")
    )
    expectNoDifference(
      try parseShares(["role", " share-1 ", " user-2 ", "WRITER"]),
      .role(CLISharesRoleInvocation(shareID: "share-1", userID: "user-2", role: .writer))
    )
    expectNoDifference(
      try parseShares(["role", "share-1", "user-2", "reader"]),
      .role(CLISharesRoleInvocation(shareID: "share-1", userID: "user-2", role: .reader))
    )
    expectNoDifference(
      try parseShares(["revoke", " share-1 "]),
      .revoke(shareID: "share-1")
    )
  }

  @Test
  func sharesParserReportsMalformedArguments() throws {
    try expectSharesParseError([], contains: "Usage: instant-swift-data shares")
    try expectSharesParseError(
      ["create", "todos"],
      contains: "shares create <namespace> <entity-id>"
    )
    try expectSharesParseError(
      ["list", "extra"],
      contains: "Unexpected argument: extra."
    )
    try expectSharesParseError(
      ["accept", "  "],
      contains: "shares accept <token>"
    )
    try expectSharesParseError(
      ["role", "share-1", "user-2", "owner"],
      contains: "Invalid share role: owner."
    )
    try expectSharesParseError(
      ["role", "share-1", "user-2"],
      contains: "shares role <share-id> <user-id> <reader|writer>"
    )
    try expectSharesParseError(
      ["revoke", "share-1", "--force"],
      contains: "Unexpected argument: --force."
    )
    try expectSharesParseError(
      ["revoke"],
      contains: "shares revoke <share-id>"
    )
    try expectSharesParseError(
      ["dance"],
      contains: "Usage: instant-swift-data shares"
    )
  }

  @Test
  func streamsParserParsesCommandsAndAliases() throws {
    expectNoDifference(
      try parseStreams(["append", " chat/lobby ", "--value", "{\"text\":\"hello\"}"]),
      .append(CLIStreamAppendInvocation(streamID: "chat/lobby", value: "{\"text\":\"hello\"}"))
    )
    expectNoDifference(
      try parseStreams(["write", "chat/lobby", "--value", "{\"text\":\"hello\"}"]),
      .append(CLIStreamAppendInvocation(streamID: "chat/lobby", value: "{\"text\":\"hello\"}"))
    )
    expectNoDifference(
      try parseStreams([
        "append", "chat/lobby",
        "--value", "{\"text\":\"first\"}",
        "--value", "{\"text\":\"second\"}",
      ]),
      .append(
        CLIStreamAppendInvocation(
          streamID: "chat/lobby",
          values: ["{\"text\":\"first\"}", "{\"text\":\"second\"}"]
        )
      )
    )
    expectNoDifference(
      try parseStreams(["read", " chat/lobby "]),
      .read(CLIStreamReadInvocation(streamID: "chat/lobby"))
    )
    expectNoDifference(
      try parseStreams(["list", "chat/lobby", "--limit", "2"]),
      .read(CLIStreamReadInvocation(streamID: "chat/lobby", limit: 2))
    )
    expectNoDifference(
      try parseStreams(["watch", " chat/lobby ", "--events", "1"]),
      .watch(CLIStreamWatchInvocation(streamID: "chat/lobby", eventCount: 1))
    )
  }

  @Test
  func streamsParserReportsMalformedArguments() throws {
    try expectStreamsParseError([], contains: "Usage: instant-swift-data streams")
    try expectStreamsParseError(
      ["append", "chat/lobby"],
      contains: "Missing required option --value."
    )
    try expectStreamsParseError(
      ["append", "chat/lobby", "--value"],
      contains: "Missing value for --value."
    )
    try expectStreamsParseError(
      ["append", "chat/lobby", "--surprise"],
      contains: "Unknown streams append option: --surprise."
    )
    try expectStreamsParseError(
      ["read", "chat/lobby", "--limit", "-1"],
      contains: "Invalid --limit value: -1."
    )
    try expectStreamsParseError(
      ["read", "chat/lobby", "--limit"],
      contains: "Missing value for --limit."
    )
    try expectStreamsParseError(
      ["watch", "chat/lobby", "--events", "2"],
      contains: "instant-swift-data streams watch <stream-id> --events 1"
    )
    try expectStreamsParseError(
      ["watch", "chat/lobby", "--surprise"],
      contains: "Unknown streams watch option: --surprise."
    )
    try expectStreamsParseError(
      ["dance"],
      contains: "Usage: instant-swift-data streams"
    )
  }

  @Test
  func benchmarkParserParsesOptionsAndDefaults() throws {
    expectNoDifference(
      try CLIBenchmarkArguments.parse([]),
      CLIBenchmarkInvocation()
    )
    expectNoDifference(
      try CLIBenchmarkArguments.parse(
        ["--iterations", "2", "--suite", "local-todos", "--app-id", "cli-benchmark", "--jsonl"]
      ),
      CLIBenchmarkInvocation(
        suite: "local-todos",
        iterations: 2,
        appID: "cli-benchmark",
        output: .jsonl
      )
    )
    expectNoDifference(
      try CLIBenchmarkArguments.parse(
        ["--app-id", "  trimmed-app  ", "--json"],
        defaultAppID: " default-app "
      ),
      CLIBenchmarkInvocation(appID: "trimmed-app", output: .json)
    )
    expectNoDifference(
      try CLIBenchmarkArguments.parse([], defaultAppID: "  "),
      CLIBenchmarkInvocation()
    )
  }

  @Test
  func benchmarkParserReportsMalformedOptions() throws {
    try expectBenchmarkParseError(
      ["--iterations", "0"],
      contains: "Invalid --iterations value: 0."
    )
    try expectBenchmarkParseError(
      ["--iterations"],
      contains: "Missing value for --iterations."
    )
    try expectBenchmarkParseError(
      ["--app-id", "  "],
      contains: "Missing non-empty value for --app-id."
    )
    try expectBenchmarkParseError(
      ["--surprise"],
      contains: "Unknown benchmark option: --surprise."
    )
    try expectBenchmarkParseError(
      ["--help"],
      contains: "Usage: instant-swift-data benchmark",
      exitCode: 0
    )
    try expectBenchmarkParseError(
      ["help"],
      contains: "Usage: instant-swift-data benchmark",
      exitCode: 0
    )
    try expectBenchmarkParseError(
      ["-h"],
      contains: "Usage: instant-swift-data benchmark",
      exitCode: 0
    )
  }

  @Test
  func benchmarkParserKeepsLastLeafOutputFlag() throws {
    expectNoDifference(
      try CLIBenchmarkArguments.parse(["--jsonl", "--json"]),
      CLIBenchmarkInvocation(output: .json)
    )
    expectNoDifference(
      try CLIBenchmarkArguments.parse(["--json", "--jsonl"]),
      CLIBenchmarkInvocation(output: .jsonl)
    )

    try expectBenchmarkParseError(
      ["--json"],
      contains: "Unknown benchmark option: --json.",
      allowsOutputFlags: false
    )
  }
}

private func parseExamples(_ arguments: [String]) throws -> CLIExamplesInvocation {
  var input = arguments[...]
  let invocation = try CLIExamplesParser().parse(&input)
  expectNoDifference(Array(input), [])
  return invocation
}

private func parseAuth(_ arguments: [String]) throws -> CLIAuthInvocation {
  var input = arguments[...]
  let invocation = try CLIAuthParser().parse(&input)
  expectNoDifference(Array(input), [])
  return invocation
}

private func parseConnection(_ arguments: [String]) throws -> CLIConnectionInvocation {
  var input = arguments[...]
  let invocation = try CLIConnectionParser().parse(&input)
  expectNoDifference(Array(input), [])
  return invocation
}

private func parseLocalID(_ arguments: [String]) throws -> CLILocalIDInvocation {
  var input = arguments[...]
  let invocation = try CLILocalIDParser().parse(&input)
  expectNoDifference(Array(input), [])
  return invocation
}

private func parseSync(_ arguments: [String]) throws -> CLISyncInvocation {
  var input = arguments[...]
  let invocation = try CLISyncParser().parse(&input)
  expectNoDifference(Array(input), [])
  return invocation
}

private func parseInit(_ arguments: [String]) throws -> CLIScaffoldInvocation {
  var input = arguments[...]
  let invocation = try CLIInitParser().parse(&input)
  expectNoDifference(Array(input), [])
  return invocation
}

private func parseSchema(_ arguments: [String]) throws -> CLISchemaInvocation {
  var input = arguments[...]
  let invocation = try CLISchemaParser().parse(&input)
  expectNoDifference(Array(input), [])
  return invocation
}

private func parsePermissions(_ arguments: [String]) throws -> CLIPermissionsInvocation {
  var input = arguments[...]
  let invocation = try CLIPermissionsParser().parse(&input)
  expectNoDifference(Array(input), [])
  return invocation
}

private func parseApp(_ arguments: [String]) throws -> CLIAppInvocation {
  var input = arguments[...]
  let invocation = try CLIAppParser().parse(&input)
  expectNoDifference(Array(input), [])
  return invocation
}

private func parseQuery(_ arguments: [String]) throws -> CLIQueryInvocation {
  var input = arguments[...]
  let invocation = try CLIQueryParser().parse(&input)
  expectNoDifference(Array(input), [])
  return invocation
}

private func parseValidation(_ arguments: [String]) throws -> CLIValidationInvocation {
  var input = arguments[...]
  let invocation = try CLIValidationParser().parse(&input)
  expectNoDifference(Array(input), [])
  return invocation
}

private func parseAdmin(_ arguments: [String]) throws -> CLIAdminInvocation {
  var input = arguments[...]
  let invocation = try CLIAdminParser().parse(&input)
  expectNoDifference(Array(input), [])
  return invocation
}

private func parseCache(_ arguments: [String]) throws -> CLICacheInvocation {
  var input = arguments[...]
  let invocation = try CLICacheParser().parse(&input)
  expectNoDifference(Array(input), [])
  return invocation
}

private func parseOutbox(_ arguments: [String]) throws -> CLIOutboxInvocation {
  var input = arguments[...]
  let invocation = try CLIOutboxParser().parse(&input)
  expectNoDifference(Array(input), [])
  return invocation
}

private func parseRooms(_ arguments: [String]) throws -> CLIRoomsInvocation {
  var input = arguments[...]
  let invocation = try CLIRoomsParser().parse(&input)
  expectNoDifference(Array(input), [])
  return invocation
}

private func parseFiles(_ arguments: [String]) throws -> CLIFilesInvocation {
  var input = arguments[...]
  let invocation = try CLIFilesParser().parse(&input)
  expectNoDifference(Array(input), [])
  return invocation
}

private func parseShares(_ arguments: [String]) throws -> CLISharesInvocation {
  var input = arguments[...]
  let invocation = try CLISharesParser().parse(&input)
  expectNoDifference(Array(input), [])
  return invocation
}

private func parseStreams(_ arguments: [String]) throws -> CLIStreamsInvocation {
  var input = arguments[...]
  let invocation = try CLIStreamsParser().parse(&input)
  expectNoDifference(Array(input), [])
  return invocation
}

private func expectAuthParseError(
  _ arguments: [String],
  contains expectedFragment: String
) throws {
  do {
    _ = try parseAuth(arguments)
    Issue.record("Expected auth parser to reject \(arguments).")
  } catch let error as CLIAuthArgumentError {
    #expect(error.description.contains(expectedFragment))
    expectNoDifference(error.exitCode, 64)
  }
}

private func expectConnectionParseError(
  _ arguments: [String],
  contains expectedFragment: String
) throws {
  do {
    _ = try parseConnection(arguments)
    Issue.record("Expected connection parser to reject \(arguments).")
  } catch let error as CLIConnectionArgumentError {
    #expect(error.description.contains(expectedFragment))
    expectNoDifference(error.exitCode, 64)
  }
}

private func expectLocalIDParseError(
  _ arguments: [String],
  contains expectedFragment: String
) throws {
  do {
    _ = try parseLocalID(arguments)
    Issue.record("Expected local-id parser to reject \(arguments).")
  } catch let error as CLILocalIDArgumentError {
    #expect(error.description.contains(expectedFragment))
    expectNoDifference(error.exitCode, 64)
  }
}

private func expectSyncParseError(
  _ arguments: [String],
  contains expectedFragment: String
) throws {
  do {
    _ = try parseSync(arguments)
    Issue.record("Expected sync parser to reject \(arguments).")
  } catch let error as CLISyncArgumentError {
    #expect(error.description.contains(expectedFragment))
    expectNoDifference(error.exitCode, 64)
  }
}

private func expectInitParseError(
  _ arguments: [String],
  description expectedDescription: String
) throws {
  do {
    _ = try parseInit(arguments)
    Issue.record("Expected init parser to reject \(arguments).")
  } catch let error as CLIInitArgumentError {
    expectNoDifference(error.description, expectedDescription)
    expectNoDifference(error.exitCode, 64)
  }
}

private func expectSchemaParseError(
  _ arguments: [String],
  description expectedDescription: String
) throws {
  do {
    _ = try parseSchema(arguments)
    Issue.record("Expected schema parser to reject \(arguments).")
  } catch let error as CLISchemaArgumentError {
    expectNoDifference(error.description, expectedDescription)
    expectNoDifference(error.exitCode, 64)
  }
}

private func expectPermissionsParseError(
  _ arguments: [String],
  description expectedDescription: String
) throws {
  do {
    _ = try parsePermissions(arguments)
    Issue.record("Expected permissions parser to reject \(arguments).")
  } catch let error as CLIPermissionsArgumentError {
    expectNoDifference(error.description, expectedDescription)
    expectNoDifference(error.exitCode, 64)
  }
}

private func expectAppParseError(
  _ arguments: [String],
  contains expectedFragment: String
) throws {
  do {
    _ = try parseApp(arguments)
    Issue.record("Expected app parser to reject \(arguments).")
  } catch let error as CLIAppArgumentError {
    #expect(error.description.contains(expectedFragment))
    expectNoDifference(error.exitCode, 64)
  }
}

private func expectQueryParseError(
  _ arguments: [String],
  description expectedDescription: String
) throws {
  do {
    _ = try parseQuery(arguments)
    Issue.record("Expected query parser to reject \(arguments).")
  } catch let error as CLIQueryArgumentError {
    expectNoDifference(error.description, expectedDescription)
    expectNoDifference(error.exitCode, 64)
  }
}

private func expectValidationParseError(
  _ arguments: [String],
  description expectedDescription: String
) throws {
  do {
    _ = try parseValidation(arguments)
    Issue.record("Expected validation parser to reject \(arguments).")
  } catch let error as CLIValidationArgumentError {
    expectNoDifference(error.description, expectedDescription)
    expectNoDifference(error.exitCode, 64)
  }
}

private func expectAdminParseError(
  _ arguments: [String],
  description expectedDescription: String
) throws {
  do {
    _ = try parseAdmin(arguments)
    Issue.record("Expected admin parser to reject \(arguments).")
  } catch let error as CLIAdminArgumentError {
    expectNoDifference(error.description, expectedDescription)
    expectNoDifference(error.exitCode, 64)
  }
}

private func expectCacheParseError(
  _ arguments: [String],
  contains expectedFragment: String
) throws {
  do {
    _ = try parseCache(arguments)
    Issue.record("Expected cache parser to reject \(arguments).")
  } catch let error as CLICacheArgumentError {
    #expect(error.description.contains(expectedFragment))
    expectNoDifference(error.exitCode, 64)
  }
}

private func expectCacheParseError(
  _ arguments: [String],
  description expectedDescription: String
) throws {
  do {
    _ = try parseCache(arguments)
    Issue.record("Expected cache parser to reject \(arguments).")
  } catch let error as CLICacheArgumentError {
    expectNoDifference(error.description, expectedDescription)
    expectNoDifference(error.exitCode, 64)
  }
}

private func expectOutboxParseError(
  _ arguments: [String],
  description expectedDescription: String
) throws {
  do {
    _ = try parseOutbox(arguments)
    Issue.record("Expected outbox parser to reject \(arguments).")
  } catch let error as CLIOutboxArgumentError {
    expectNoDifference(error.description, expectedDescription)
    expectNoDifference(error.exitCode, 64)
  }
}

private func expectRoomsParseError(
  _ arguments: [String],
  contains expectedFragment: String
) throws {
  do {
    _ = try parseRooms(arguments)
    Issue.record("Expected rooms parser to reject \(arguments).")
  } catch let error as CLIRoomsArgumentError {
    #expect(error.description.contains(expectedFragment))
    expectNoDifference(error.exitCode, 64)
  }
}

private func expectFilesParseError(
  _ arguments: [String],
  contains expectedFragment: String
) throws {
  do {
    _ = try parseFiles(arguments)
    Issue.record("Expected files parser to reject \(arguments).")
  } catch let error as CLIFilesArgumentError {
    #expect(error.description.contains(expectedFragment))
    expectNoDifference(error.exitCode, 64)
  }
}

private func expectSharesParseError(
  _ arguments: [String],
  contains expectedFragment: String
) throws {
  do {
    _ = try parseShares(arguments)
    Issue.record("Expected shares parser to reject \(arguments).")
  } catch let error as CLISharesArgumentError {
    #expect(error.description.contains(expectedFragment))
    expectNoDifference(error.exitCode, 64)
  }
}

private func expectStreamsParseError(
  _ arguments: [String],
  contains expectedFragment: String
) throws {
  do {
    _ = try parseStreams(arguments)
    Issue.record("Expected streams parser to reject \(arguments).")
  } catch let error as CLIStreamsArgumentError {
    #expect(error.description.contains(expectedFragment))
    expectNoDifference(error.exitCode, 64)
  }
}

private func expectBenchmarkParseError(
  _ arguments: [String],
  contains expectedFragment: String,
  exitCode expectedExitCode: Int32 = 64,
  allowsOutputFlags: Bool = true
) throws {
  do {
    _ = try CLIBenchmarkArguments.parse(arguments, allowsOutputFlags: allowsOutputFlags)
    Issue.record("Expected benchmark parser to reject \(arguments).")
  } catch let error as CLIBenchmarkArgumentError {
    #expect(error.description.contains(expectedFragment))
    expectNoDifference(error.exitCode, expectedExitCode)
  }
}
