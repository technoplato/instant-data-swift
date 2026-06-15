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
          arguments: ["do", "the", "dishes"],
          leaf: .add(text: "do the dishes")
        )
      )
    )
    expectNoDifference(
      try parseExamples(["todos", "observe", "--events", "1"]),
      .todos(
        CLIExamplesTodosInvocation(
          command: .watch,
          arguments: ["--events", "1"],
          leaf: .watch(CLIExamplesTodosWatchInvocation(eventCount: 1))
        )
      )
    )
    expectNoDifference(
      try parseExamples(["todos", "edit", "todo-1", "new", "text"]),
      .todos(
        CLIExamplesTodosInvocation(
          command: .update,
          arguments: ["todo-1", "new", "text"],
          leaf: .update(todoID: "todo-1", text: "new text")
        )
      )
    )
    expectNoDifference(
      try parseExamples(["todos", "remove", "todo-1"]),
      .todos(
        CLIExamplesTodosInvocation(
          command: .delete,
          arguments: ["todo-1"],
          leaf: .delete(todoID: "todo-1")
        )
      )
    )
  }

  @Test
  func examplesParserNormalizesAuthRecipeAliasesAndParsesLeaf() throws {
    expectNoDifference(
      try parseExamples(["auth", "send-code", "User@Example.com"]),
      .auth(.sendCode(email: "User@Example.com"))
    )
    expectNoDifference(
      try parseExamples(["authentication", "verify", "user@example.com", "123456"]),
      .auth(.verifyCode(email: "user@example.com", code: "123456"))
    )
    expectNoDifference(
      try parseExamples(["magic-code-auth", "status"]),
      .auth(.status)
    )
  }

  @Test
  func examplesParserNormalizesAppBuilderAliasesAndParsesLeaf() throws {
    expectNoDifference(
      try parseExamples(["app-builder", "generate", "Build", "a", "game"]),
      .appBuilder(
        .generate(
          CLIExamplesAppBuilderGenerateInvocation(
            prompt: "Build a game",
            orgID: "local-instant-swift-data"
          )
        )
      )
    )
    expectNoDifference(
      try parseExamples(["appbuilder", "list"]),
      .appBuilder(.list)
    )
    expectNoDifference(
      try parseExamples(["builder", "show", "build-1"]),
      .appBuilder(.show(buildID: "build-1"))
    )
  }

  @Test
  func examplesTodosLeafParserParsesCommandsAndOptions() throws {
    expectNoDifference(try parseExamplesTodosLeaf(["seed"]), .seed)
    expectNoDifference(
      try parseExamplesTodosLeaf(["add", "do", "the", "dishes"]),
      .add(text: "do the dishes")
    )
    expectNoDifference(
      try parseExamplesTodosLeaf([
        "list", "--completed", "false", "--completed", "yes", "--search", " milk ",
        "--offset", "2", "--limit", "1", "--limit", "3", "--first", "4",
        "--after", "note-1", "--after-inclusive", " note-2 ", "--order", "descending",
        "--order-by", "serverCreatedAt",
      ]),
      .list(
        CLITodosQueryInvocation(
          completed: true,
          search: " milk ",
          offset: 2,
          limit: 3,
          first: 4,
          after: CLIQueryCursor(entityID: "note-2", inclusive: true),
          direction: .descending,
          orderField: .serverCreatedAt
        )
      )
    )
    expectNoDifference(
      try parseExamplesTodosLeaf([
        "observe", "--events", "1", "--last", "2", "--before", " note-9 ",
        "--order-by", "none",
      ]),
      .watch(
        CLIExamplesTodosWatchInvocation(
          query: CLITodosQueryInvocation(
            last: 2,
            before: CLIQueryCursor(entityID: "note-9"),
            orderField: .none
          ),
          eventCount: 1
        )
      )
    )
    expectNoDifference(
      try parseExamplesTodosLeaf(["complete", "todo-1"]),
      .complete(todoID: "todo-1")
    )
    expectNoDifference(
      try parseExamplesTodosLeaf(["edit", "todo-1", "new", "text"]),
      .update(todoID: "todo-1", text: "new text")
    )
    expectNoDifference(
      try parseExamplesTodosLeaf(["remove", "todo-1"]),
      .delete(todoID: "todo-1")
    )
    expectNoDifference(try parseExamplesTodosLeaf(["reset"]), .reset)
    expectNoDifference(
      try parseExamplesTodosLeaf(["refresh", "--completed", "no", "--limit", "2"]),
      .refresh(CLITodosQueryInvocation(completed: false, limit: 2))
    )
    expectNoDifference(
      try parseExamplesTodosLeaf(["dance", "--fast"]),
      .unknown("dance")
    )
  }

  @Test
  func examplesAuthLeafParserParsesCommandsAndOptions() throws {
    expectNoDifference(
      try parseExamplesAuthLeaf(["send-code", "User@Example.com"]),
      .sendCode(email: "User@Example.com")
    )
    expectNoDifference(
      try parseExamplesAuthLeaf(["send", " user@example.com "]),
      .sendCode(email: " user@example.com ")
    )
    expectNoDifference(
      try parseExamplesAuthLeaf(["verify-code", "user@example.com", "123456"]),
      .verifyCode(email: "user@example.com", code: "123456")
    )
    expectNoDifference(
      try parseExamplesAuthLeaf(["magic-code-verify", "user@example.com", " 654321 "]),
      .verifyCode(email: "user@example.com", code: " 654321 ")
    )
    expectNoDifference(try parseExamplesAuthLeaf(["status"]), .status)
    expectNoDifference(try parseExamplesAuthLeaf(["dashboard"]), .status)
    expectNoDifference(
      try parseExamplesAuthLeaf(["watch", "--events", "1"]),
      .watch(CLIExamplesAuthWatchInvocation(eventCount: 1))
    )
    expectNoDifference(
      try parseExamplesAuthLeaf(["observe"]),
      .watch(CLIExamplesAuthWatchInvocation(eventCount: 1))
    )
    expectNoDifference(
      try parseExamplesAuthLeaf(["sign-out", "--skip-token-invalidation"]),
      .signOut(CLIExamplesAuthSignOutInvocation(invalidateToken: false))
    )
    expectNoDifference(
      try parseExamplesAuthLeaf(["logout"]),
      .signOut(CLIExamplesAuthSignOutInvocation(invalidateToken: true))
    )
    expectNoDifference(
      try parseExamplesAuthLeaf(["dance", "--fast"]),
      .unknown("dance")
    )
  }

  @Test
  func examplesAuthLeafParserReportsMalformedArguments() throws {
    try expectExamplesAuthLeafParseError([], description: CLIExamplesAuthUsage.auth)
    try expectExamplesAuthLeafParseError(
      ["send-code"],
      description: CLIExamplesAuthUsage.sendCode
    )
    try expectExamplesAuthLeafParseError(
      ["send-code", "user@example.com", "extra"],
      description:
        "Unknown examples auth option: extra. \(CLIExamplesAuthUsage.sendCode)"
    )
    try expectExamplesAuthLeafParseError(
      ["verify-code", "user@example.com"],
      description: CLIExamplesAuthUsage.verifyCode
    )
    try expectExamplesAuthLeafParseError(
      ["watch", "--events", "2"],
      description: "Usage: instant-swift-data examples auth watch --events 1"
    )
    try expectExamplesAuthLeafParseError(
      ["watch", "--unknown"],
      description:
        "Unknown examples auth watch option: --unknown. \(CLIExamplesAuthUsage.watch)"
    )
    try expectExamplesAuthLeafParseError(
      ["sign-out", "--unknown"],
      description:
        "Unknown examples auth sign-out option: --unknown. \(CLIExamplesAuthUsage.signOut)"
    )
  }

  @Test
  func examplesAppBuilderLeafParserParsesCommandsAndOptions() throws {
    expectNoDifference(
      try parseExamplesAppBuilderLeaf(["generate", "Build", "a", "timer", "--org-id", "org-1"]),
      .generate(
        CLIExamplesAppBuilderGenerateInvocation(
          prompt: "Build a timer",
          orgID: "org-1"
        )
      )
    )
    expectNoDifference(
      try parseExamplesAppBuilderLeaf(["create", "--org-id", "org-2", "Build", "notes"]),
      .generate(
        CLIExamplesAppBuilderGenerateInvocation(
          prompt: "Build notes",
          orgID: "org-2"
        )
      )
    )
    expectNoDifference(try parseExamplesAppBuilderLeaf(["list"]), .list)
    expectNoDifference(try parseExamplesAppBuilderLeaf(["builds"]), .list)
    expectNoDifference(
      try parseExamplesAppBuilderLeaf(["detail", " build-1 "]),
      .show(buildID: "build-1")
    )
    expectNoDifference(
      try parseExamplesAppBuilderLeaf([
        "append", "build-1", "--code", "let x = 1", "--reasoning", "Looks good",
        "--previewable", "yes",
      ]),
      .append(
        CLIExamplesAppBuilderAppendInvocation(
          buildID: "build-1",
          code: "let x = 1",
          reasoning: "Looks good",
          isPreviewable: true
        )
      )
    )
    expectNoDifference(try parseExamplesAppBuilderLeaf(["finish", "build-1"]), .finish(buildID: "build-1"))
    expectNoDifference(try parseExamplesAppBuilderLeaf(["reset"]), .reset)
    expectNoDifference(try parseExamplesAppBuilderLeaf(["dance", "--fast"]), .unknown("dance"))
  }

  @Test
  func examplesAppBuilderLeafParserReportsMalformedArguments() throws {
    try expectExamplesAppBuilderLeafParseError([], description: CLIExamplesAppBuilderUsage.appBuilder)
    try expectExamplesAppBuilderLeafParseError(
      ["generate"],
      description: CLIExamplesAppBuilderUsage.generate
    )
    try expectExamplesAppBuilderLeafParseError(
      ["generate", "--unknown", "Build"],
      description:
        "Unknown examples app-builder option: --unknown. \(CLIExamplesAppBuilderUsage.generate)"
    )
    try expectExamplesAppBuilderLeafParseError(
      ["generate", "Build", "--org-id"],
      description: "Missing value for --org-id. \(CLIExamplesAppBuilderUsage.generate)"
    )
    try expectExamplesAppBuilderLeafParseError(
      ["show"],
      description: CLIExamplesAppBuilderUsage.show
    )
    try expectExamplesAppBuilderLeafParseError(
      ["append", "build-1"],
      description: CLIExamplesAppBuilderUsage.append
    )
    try expectExamplesAppBuilderLeafParseError(
      ["append", "build-1", "--previewable", "maybe"],
      description: CLIExamplesAppBuilderUsage.append
    )
    try expectExamplesAppBuilderLeafParseError(
      ["append", "build-1", "--unknown", "value"],
      description:
        "Unknown examples app-builder option: --unknown. \(CLIExamplesAppBuilderUsage.append)"
    )
    try expectExamplesAppBuilderLeafParseError(
      ["reset", "extra"],
      description:
        "Unknown examples app-builder option: extra. \(CLIExamplesAppBuilderUsage.reset)"
    )
  }

  @Test
  func examplesTodosLeafParserReportsMalformedArguments() throws {
    try expectExamplesTodosLeafParseError([], description: CLIExamplesTodosUsage.todos)
    try expectExamplesTodosLeafParseError(
      ["seed", "unexpected"],
      description: CLIExamplesTodosUsage.seed
    )
    try expectExamplesTodosLeafParseError(
      ["add", "  "],
      description: CLIExamplesTodosUsage.add
    )
    try expectExamplesTodosLeafParseError(
      ["list", "--completed", "maybe"],
      description: "Usage: \(CLIExamplesTodosUsage.listCommand) --completed true|false"
    )
    try expectExamplesTodosLeafParseError(
      ["list", "--after", "  "],
      description: "Usage: \(CLIExamplesTodosUsage.listCommand) --after id"
    )
    try expectExamplesTodosLeafParseError(
      ["list", "--first", "1", "--last", "1"],
      description: "Use either --first or --last, not both. Usage: \(CLIExamplesTodosUsage.list)"
    )
    try expectExamplesTodosLeafParseError(
      ["list", "--unknown"],
      description: "Unknown todo list option: --unknown. Usage: \(CLIExamplesTodosUsage.list)"
    )
    try expectExamplesTodosLeafParseError(
      ["watch", "--events", "2"],
      description: "Usage: \(CLIExamplesTodosUsage.watchCommand) --events 1"
    )
    try expectExamplesTodosLeafParseError(
      ["watch", "--completed", "maybe"],
      description: "Usage: \(CLIExamplesTodosUsage.watchCommand) --completed true|false"
    )
    try expectExamplesTodosLeafParseError(
      ["watch", "--after-inclusive", "  "],
      description: "Usage: \(CLIExamplesTodosUsage.watchCommand) --after-inclusive id"
    )
    try expectExamplesTodosLeafParseError(
      ["watch", "--order-by", "title"],
      description: "Usage: \(CLIExamplesTodosUsage.watchCommand) --order-by none|createdAt|serverCreatedAt"
    )
    try expectExamplesTodosLeafParseError(
      ["watch", "--first", "1", "--last", "1"],
      description: "Use either --first or --last, not both. Usage: \(CLIExamplesTodosUsage.watch)"
    )
    try expectExamplesTodosLeafParseError(
      ["watch", "--unknown"],
      description: "Unknown todo watch option: --unknown. Usage: \(CLIExamplesTodosUsage.watch)"
    )
    try expectExamplesTodosLeafParseError(
      ["complete"],
      description: CLIExamplesTodosUsage.complete
    )
    try expectExamplesTodosLeafParseError(
      ["complete", "todo-1", "unexpected"],
      description: CLIExamplesTodosUsage.complete
    )
    try expectExamplesTodosLeafParseError(
      ["update", "todo-1"],
      description: CLIExamplesTodosUsage.update
    )
    try expectExamplesTodosLeafParseError(
      ["delete", "todo-1", "unexpected"],
      description: CLIExamplesTodosUsage.delete
    )
    try expectExamplesTodosLeafParseError(
      ["reset", "unexpected"],
      description: CLIExamplesTodosUsage.reset
    )
    try expectExamplesTodosLeafParseError(
      ["refresh", "--completed", "maybe"],
      description: "Usage: \(CLIExamplesTodosUsage.listCommand) --completed true|false"
    )
  }

  @Test
  func examplesTodosQueryOptionsParserConsumesListOptions() throws {
    expectNoDifference(
      try parseExamplesTodosQueryOptions([
        "--completed", "false", "--completed", "1", "--search", " milk ",
        "--offset", "2", "--limit", "3", "--last", "4", "--before-inclusive", " note-2 ",
        "--order", "descending", "--order-by", "serverCreatedAt",
      ]),
      CLITodosQueryInvocation(
        completed: true,
        search: " milk ",
        offset: 2,
        limit: 3,
        last: 4,
        before: CLIQueryCursor(entityID: "note-2", inclusive: true),
        direction: .descending,
        orderField: .serverCreatedAt
      )
    )
  }

  @Test
  func examplesTodosQueryOptionsParserReportsMalformedArguments() throws {
    try expectExamplesTodosQueryOptionsParseError(
      ["--completed", "maybe"],
      description: "Usage: \(CLIExamplesTodosUsage.listCommand) --completed true|false"
    )
    try expectExamplesTodosQueryOptionsParseError(
      ["--after"],
      description: "Usage: \(CLIExamplesTodosUsage.listCommand) --after id"
    )
    try expectExamplesTodosQueryOptionsParseError(
      ["--first", "1", "--last", "1"],
      description: "Use either --first or --last, not both. Usage: \(CLIExamplesTodosUsage.list)"
    )
    try expectExamplesTodosQueryOptionsParseError(
      ["--raw"],
      description: "Unknown todo list option: --raw. Usage: \(CLIExamplesTodosUsage.list)"
    )
  }

  @Test
  func examplesTodosWatchOptionsParserConsumesWatchOptions() throws {
    expectNoDifference(
      try parseExamplesTodosWatchOptions([
        "--events", "1", "--completed", "yes", "--search", " tea ",
        "--first", "2", "--after", "todo-1", "--order", "asc", "--order-by", "none",
      ]),
      CLIExamplesTodosWatchInvocation(
        query: CLITodosQueryInvocation(
          completed: true,
          search: " tea ",
          first: 2,
          after: CLIQueryCursor(entityID: "todo-1"),
          orderField: .none
        ),
        eventCount: 1
      )
    )
  }

  @Test
  func examplesTodosWatchOptionsParserReportsMalformedArguments() throws {
    try expectExamplesTodosWatchOptionsParseError(
      ["--events", "2"],
      description: "Usage: \(CLIExamplesTodosUsage.watchCommand) --events 1"
    )
    try expectExamplesTodosWatchOptionsParseError(
      ["--search", "  "],
      description: "Usage: \(CLIExamplesTodosUsage.watchCommand) --search text"
    )
    try expectExamplesTodosWatchOptionsParseError(
      ["--first", "1", "--last", "1"],
      description: "Use either --first or --last, not both. Usage: \(CLIExamplesTodosUsage.watch)"
    )
    try expectExamplesTodosWatchOptionsParseError(
      ["--raw"],
      description: "Unknown todo watch option: --raw. Usage: \(CLIExamplesTodosUsage.watch)"
    )
  }

  @Test
  func examplesTodoLinksLeafParserParsesCommands() throws {
    expectNoDifference(try parseExamplesTodoLinksLeaf(["seed"]), .seed)
    expectNoDifference(try parseExamplesTodoLinksLeaf(["list"]), .list)
    expectNoDifference(try parseExamplesTodoLinksLeaf(["nested"]), .nested)
    expectNoDifference(try parseExamplesTodoLinksLeaf(["unlink"]), .unlink)
    expectNoDifference(
      try parseExamplesTodoLinksLeaf(["dance", "--fast"]),
      .unknown("dance")
    )
  }

  @Test
  func examplesTodoLinksLeafParserReportsMalformedArguments() throws {
    try expectExamplesTodoLinksLeafParseError(
      [],
      description: CLIExamplesTodoLinksUsage.todoLinks
    )
    try expectExamplesTodoLinksLeafParseError(
      ["seed", "unexpected"],
      description: CLIExamplesTodoLinksUsage.seed
    )
    try expectExamplesTodoLinksLeafParseError(
      ["list", "unexpected"],
      description: CLIExamplesTodoLinksUsage.list
    )
    try expectExamplesTodoLinksLeafParseError(
      ["nested", "unexpected"],
      description: CLIExamplesTodoLinksUsage.nested
    )
    try expectExamplesTodoLinksLeafParseError(
      ["unlink", "unexpected"],
      description: CLIExamplesTodoLinksUsage.unlink
    )
  }

  @Test
  func examplesCountersLeafParserParsesCommandsAndOptions() throws {
    expectNoDifference(try parseExamplesCountersLeaf(["seed"]), .seed)
    expectNoDifference(try parseExamplesCountersLeaf(["add"]), .add(count: 0))
    expectNoDifference(
      try parseExamplesCountersLeaf(["add", "--count", "24"]),
      .add(count: 24)
    )
    expectNoDifference(try parseExamplesCountersLeaf(["list"]), .list)
    expectNoDifference(
      try parseExamplesCountersLeaf(["increment", "counter-1"]),
      .increment(counterID: "counter-1")
    )
    expectNoDifference(
      try parseExamplesCountersLeaf(["inc", "counter-1"]),
      .increment(counterID: "counter-1")
    )
    expectNoDifference(
      try parseExamplesCountersLeaf(["+", "counter-1"]),
      .increment(counterID: "counter-1")
    )
    expectNoDifference(
      try parseExamplesCountersLeaf(["decrement", "counter-1"]),
      .decrement(counterID: "counter-1")
    )
    expectNoDifference(
      try parseExamplesCountersLeaf(["dec", "counter-1"]),
      .decrement(counterID: "counter-1")
    )
    expectNoDifference(
      try parseExamplesCountersLeaf(["-", "counter-1"]),
      .decrement(counterID: "counter-1")
    )
    expectNoDifference(
      try parseExamplesCountersLeaf(["delete", "counter-1"]),
      .delete(counterID: "counter-1")
    )
    expectNoDifference(
      try parseExamplesCountersLeaf(["remove", "counter-1"]),
      .delete(counterID: "counter-1")
    )
    expectNoDifference(
      try parseExamplesCountersLeaf(["dance", "--fast"]),
      .unknown("dance")
    )
  }

  @Test
  func examplesCountersLeafParserReportsMalformedArguments() throws {
    try expectExamplesCountersLeafParseError(
      [],
      description: CLIExamplesCountersUsage.counters
    )
    try expectExamplesCountersLeafParseError(
      ["seed", "unexpected"],
      description: CLIExamplesCountersUsage.seed
    )
    try expectExamplesCountersLeafParseError(
      ["add", "--count"],
      description: CLIExamplesCountersUsage.add
    )
    try expectExamplesCountersLeafParseError(
      ["add", "--count", "nope"],
      description: CLIExamplesCountersUsage.add
    )
    try expectExamplesCountersLeafParseError(
      ["add", "--surprise"],
      description: CLIExamplesCountersUsage.add
    )
    try expectExamplesCountersLeafParseError(
      ["list", "unexpected"],
      description: CLIExamplesCountersUsage.list
    )
    try expectExamplesCountersLeafParseError(
      ["increment"],
      description: CLIExamplesCountersUsage.increment
    )
    try expectExamplesCountersLeafParseError(
      ["increment", "  "],
      description: CLIExamplesCountersUsage.increment
    )
    try expectExamplesCountersLeafParseError(
      ["increment", "counter-1", "unexpected"],
      description: CLIExamplesCountersUsage.increment
    )
    try expectExamplesCountersLeafParseError(
      ["decrement"],
      description: CLIExamplesCountersUsage.decrement
    )
    try expectExamplesCountersLeafParseError(
      ["delete"],
      description: CLIExamplesCountersUsage.delete
    )
  }

  @Test
  func examplesChatLeafParserParsesCommandsAndOptions() throws {
    expectNoDifference(try parseExamplesChatLeaf(["seed"]), .seed)
    expectNoDifference(try parseExamplesChatLeaf(["channels"]), .channels)
    expectNoDifference(try parseExamplesChatLeaf(["messages"]), .messages(channelID: nil))
    expectNoDifference(
      try parseExamplesChatLeaf(["messages", "channel-1"]),
      .messages(channelID: "channel-1")
    )
    expectNoDifference(
      try parseExamplesChatLeaf(["post", "channel-1", "Hello", "there"]),
      .post(CLIExamplesChatPostInvocation(channelID: "channel-1", text: "Hello there"))
    )
    expectNoDifference(
      try parseExamplesChatLeaf(["send", "channel-1", "--author", "Blob", "Hello"]),
      .post(
        CLIExamplesChatPostInvocation(
          channelID: "channel-1",
          text: "Hello",
          authorName: "Blob"
        )
      )
    )
    expectNoDifference(
      try parseExamplesChatLeaf(["post", "channel-1", "Hello", "--author", "Blob Jr"]),
      .post(
        CLIExamplesChatPostInvocation(
          channelID: "channel-1",
          text: "Hello",
          authorName: "Blob Jr"
        )
      )
    )
    expectNoDifference(try parseExamplesChatLeaf(["reset"]), .reset)
    expectNoDifference(
      try parseExamplesChatLeaf(["dance", "--fast"]),
      .unknown("dance")
    )
  }

  @Test
  func examplesChatLeafParserReportsMalformedArguments() throws {
    try expectExamplesChatLeafParseError(
      [],
      description: CLIExamplesChatUsage.chat
    )
    try expectExamplesChatLeafParseError(
      ["seed", "unexpected"],
      description: CLIExamplesChatUsage.seed
    )
    try expectExamplesChatLeafParseError(
      ["channels", "unexpected"],
      description: CLIExamplesChatUsage.channels
    )
    try expectExamplesChatLeafParseError(
      ["messages", "channel-1", "unexpected"],
      description: CLIExamplesChatUsage.messages
    )
    try expectExamplesChatLeafParseError(
      ["messages", "  "],
      description: CLIExamplesChatUsage.messages
    )
    try expectExamplesChatLeafParseError(
      ["post"],
      description: CLIExamplesChatUsage.post
    )
    try expectExamplesChatLeafParseError(
      ["post", "  ", "Hello"],
      description: CLIExamplesChatUsage.post
    )
    try expectExamplesChatLeafParseError(
      ["post", "channel-1"],
      description: CLIExamplesChatUsage.post
    )
    try expectExamplesChatLeafParseError(
      ["post", "channel-1", "--author"],
      description: CLIExamplesChatUsage.post
    )
    try expectExamplesChatLeafParseError(
      ["post", "channel-1", "--author", "  ", "Hello"],
      description: CLIExamplesChatUsage.post
    )
    try expectExamplesChatLeafParseError(
      ["post", "channel-1", "--surprise", "Hello"],
      description: "Unknown chat post option: --surprise. \(CLIExamplesChatUsage.post)"
    )
    try expectExamplesChatLeafParseError(
      ["reset", "unexpected"],
      description: CLIExamplesChatUsage.reset
    )
  }

  @Test
  func examplesMicroblogLeafParserParsesCommandsAndOptions() throws {
    expectNoDifference(try parseExamplesMicroblogLeaf(["seed"]), .seed)
    expectNoDifference(try parseExamplesMicroblogLeaf(["feed"]), .feed)
    expectNoDifference(try parseExamplesMicroblogLeaf(["posts"]), .feed)
    expectNoDifference(try parseExamplesMicroblogLeaf(["profiles"]), .profiles)
    expectNoDifference(try parseExamplesMicroblogLeaf(["profile"]), .profile(userID: nil))
    expectNoDifference(
      try parseExamplesMicroblogLeaf(["profile", "user-1"]),
      .profile(userID: "user-1")
    )
    expectNoDifference(
      try parseExamplesMicroblogLeaf(["setup-profile", "Blob", " @blob "]),
      .setupProfile(displayName: "Blob", handle: "@blob")
    )
    expectNoDifference(
      try parseExamplesMicroblogLeaf(["create-profile", "Blob Jr", "blob-jr"]),
      .setupProfile(displayName: "Blob Jr", handle: "blob-jr")
    )
    expectNoDifference(
      try parseExamplesMicroblogLeaf(["post", "Hello", "there"]),
      .post(CLIExamplesMicroblogPostInvocation(content: "Hello there"))
    )
    expectNoDifference(
      try parseExamplesMicroblogLeaf(["post", "--color", "bg-green-100", "Hello"]),
      .post(CLIExamplesMicroblogPostInvocation(content: "Hello", color: "bg-green-100"))
    )
    expectNoDifference(
      try parseExamplesMicroblogLeaf(["like", "post-1"]),
      .like(postID: "post-1")
    )
    expectNoDifference(
      try parseExamplesMicroblogLeaf(["unlike", "post-1"]),
      .unlike(postID: "post-1")
    )
    expectNoDifference(
      try parseExamplesMicroblogLeaf(["delete-post", "post-1"]),
      .deletePost(postID: "post-1")
    )
    expectNoDifference(
      try parseExamplesMicroblogLeaf(["delete", "post-1"]),
      .deletePost(postID: "post-1")
    )
    expectNoDifference(try parseExamplesMicroblogLeaf(["reset"]), .reset)
    expectNoDifference(
      try parseExamplesMicroblogLeaf(["dance", "--fast"]),
      .unknown("dance")
    )
  }

  @Test
  func examplesMicroblogLeafParserReportsMalformedArguments() throws {
    try expectExamplesMicroblogLeafParseError(
      [],
      description: CLIExamplesMicroblogUsage.microblog
    )
    try expectExamplesMicroblogLeafParseError(
      ["seed", "unexpected"],
      description: CLIExamplesMicroblogUsage.seed
    )
    try expectExamplesMicroblogLeafParseError(
      ["feed", "unexpected"],
      description: CLIExamplesMicroblogUsage.feed
    )
    try expectExamplesMicroblogLeafParseError(
      ["profiles", "unexpected"],
      description: CLIExamplesMicroblogUsage.profiles
    )
    try expectExamplesMicroblogLeafParseError(
      ["profile", "  "],
      description: CLIExamplesMicroblogUsage.profile
    )
    try expectExamplesMicroblogLeafParseError(
      ["profile", "user-1", "unexpected"],
      description: CLIExamplesMicroblogUsage.profile
    )
    try expectExamplesMicroblogLeafParseError(
      ["setup-profile"],
      description: CLIExamplesMicroblogUsage.setupProfile
    )
    try expectExamplesMicroblogLeafParseError(
      ["setup-profile", "Blob"],
      description: CLIExamplesMicroblogUsage.setupProfile
    )
    try expectExamplesMicroblogLeafParseError(
      ["setup-profile", "Blob", "  "],
      description: CLIExamplesMicroblogUsage.setupProfile
    )
    try expectExamplesMicroblogLeafParseError(
      ["setup-profile", "Blob", "blob", "unexpected"],
      description: CLIExamplesMicroblogUsage.setupProfile
    )
    try expectExamplesMicroblogLeafParseError(
      ["post"],
      description: CLIExamplesMicroblogUsage.post
    )
    try expectExamplesMicroblogLeafParseError(
      ["post", "--color"],
      description: CLIExamplesMicroblogUsage.post
    )
    try expectExamplesMicroblogLeafParseError(
      ["post", "--color", "  ", "Hello"],
      description: CLIExamplesMicroblogUsage.post
    )
    try expectExamplesMicroblogLeafParseError(
      ["post", "--surprise", "Hello"],
      description: "Unknown microblog post option: --surprise. \(CLIExamplesMicroblogUsage.post)"
    )
    try expectExamplesMicroblogLeafParseError(
      ["like"],
      description: CLIExamplesMicroblogUsage.like
    )
    try expectExamplesMicroblogLeafParseError(
      ["like", "  "],
      description: CLIExamplesMicroblogUsage.like
    )
    try expectExamplesMicroblogLeafParseError(
      ["like", "post-1", "unexpected"],
      description: CLIExamplesMicroblogUsage.like
    )
    try expectExamplesMicroblogLeafParseError(
      ["unlike"],
      description: CLIExamplesMicroblogUsage.unlike
    )
    try expectExamplesMicroblogLeafParseError(
      ["delete-post"],
      description: CLIExamplesMicroblogUsage.deletePost
    )
    try expectExamplesMicroblogLeafParseError(
      ["reset", "unexpected"],
      description: CLIExamplesMicroblogUsage.reset
    )
  }

  @Test
  func examplesMobileChatLeafParserParsesCommandsAndOptions() throws {
    expectNoDifference(try parseExamplesMobileChatLeaf(["seed"]), .seed)
    expectNoDifference(try parseExamplesMobileChatLeaf(["channels"]), .channels)
    expectNoDifference(try parseExamplesMobileChatLeaf(["messages"]), .messages(channelID: nil))
    expectNoDifference(
      try parseExamplesMobileChatLeaf(["messages", "channel-1"]),
      .messages(channelID: "channel-1")
    )
    expectNoDifference(try parseExamplesMobileChatLeaf(["profiles"]), .profiles)
    expectNoDifference(try parseExamplesMobileChatLeaf(["profile"]), .profile(userID: nil))
    expectNoDifference(
      try parseExamplesMobileChatLeaf(["profile", "user-1"]),
      .profile(userID: "user-1")
    )
    expectNoDifference(
      try parseExamplesMobileChatLeaf(["setup-profile", "Blob"]),
      .setupProfile(displayName: "Blob")
    )
    expectNoDifference(
      try parseExamplesMobileChatLeaf(["ensure-profile", "Blob Jr"]),
      .setupProfile(displayName: "Blob Jr")
    )
    expectNoDifference(
      try parseExamplesMobileChatLeaf(["send", "channel-1", "Hello", "there"]),
      .send(CLIExamplesMobileChatSendInvocation(channelID: "channel-1", content: "Hello there"))
    )
    expectNoDifference(
      try parseExamplesMobileChatLeaf(["post", "channel-1", "Hello"]),
      .send(CLIExamplesMobileChatSendInvocation(channelID: "channel-1", content: "Hello"))
    )
    expectNoDifference(
      try parseExamplesMobileChatLeaf(["join", "channel-1"]),
      .join(channelID: "channel-1")
    )
    expectNoDifference(
      try parseExamplesMobileChatLeaf(["presence", "channel-1"]),
      .presence(channelID: "channel-1")
    )
    expectNoDifference(
      try parseExamplesMobileChatLeaf(["leave", "channel-1"]),
      .leave(channelID: "channel-1")
    )
    expectNoDifference(try parseExamplesMobileChatLeaf(["reset"]), .reset)
    expectNoDifference(
      try parseExamplesMobileChatLeaf(["dance", "--fast"]),
      .unknown("dance")
    )
  }

  @Test
  func examplesMobileChatLeafParserReportsMalformedArguments() throws {
    try expectExamplesMobileChatLeafParseError(
      [],
      description: CLIExamplesMobileChatUsage.mobileChat
    )
    try expectExamplesMobileChatLeafParseError(
      ["seed", "unexpected"],
      description: CLIExamplesMobileChatUsage.seed
    )
    try expectExamplesMobileChatLeafParseError(
      ["channels", "unexpected"],
      description: CLIExamplesMobileChatUsage.channels
    )
    try expectExamplesMobileChatLeafParseError(
      ["messages", "channel-1", "unexpected"],
      description: CLIExamplesMobileChatUsage.messages
    )
    try expectExamplesMobileChatLeafParseError(
      ["messages", "  "],
      description: CLIExamplesMobileChatUsage.messages
    )
    try expectExamplesMobileChatLeafParseError(
      ["profiles", "unexpected"],
      description: CLIExamplesMobileChatUsage.profiles
    )
    try expectExamplesMobileChatLeafParseError(
      ["profile", "  "],
      description: CLIExamplesMobileChatUsage.profile
    )
    try expectExamplesMobileChatLeafParseError(
      ["profile", "user-1", "unexpected"],
      description: CLIExamplesMobileChatUsage.profile
    )
    try expectExamplesMobileChatLeafParseError(
      ["setup-profile"],
      description: CLIExamplesMobileChatUsage.setupProfile
    )
    try expectExamplesMobileChatLeafParseError(
      ["setup-profile", "  "],
      description: CLIExamplesMobileChatUsage.setupProfile
    )
    try expectExamplesMobileChatLeafParseError(
      ["setup-profile", "Blob", "unexpected"],
      description: CLIExamplesMobileChatUsage.setupProfile
    )
    try expectExamplesMobileChatLeafParseError(
      ["send"],
      description: CLIExamplesMobileChatUsage.send
    )
    try expectExamplesMobileChatLeafParseError(
      ["send", "channel-1"],
      description: CLIExamplesMobileChatUsage.send
    )
    try expectExamplesMobileChatLeafParseError(
      ["send", "channel-1", "--surprise", "Hello"],
      description: "Unknown mobile chat send option: --surprise. \(CLIExamplesMobileChatUsage.send)"
    )
    try expectExamplesMobileChatLeafParseError(
      ["join"],
      description: CLIExamplesMobileChatUsage.join
    )
    try expectExamplesMobileChatLeafParseError(
      ["presence"],
      description: CLIExamplesMobileChatUsage.presence
    )
    try expectExamplesMobileChatLeafParseError(
      ["leave"],
      description: CLIExamplesMobileChatUsage.leave
    )
    try expectExamplesMobileChatLeafParseError(
      ["reset", "unexpected"],
      description: CLIExamplesMobileChatUsage.reset
    )
  }

  @Test
  func examplesStroopwafelLeafParserParsesCommandsAndOptions() throws {
    expectNoDifference(
      try parseExamples(["stroopwafel", "rooms"]),
      .stroopwafel(arguments: ["rooms"])
    )
    expectNoDifference(
      try parseExamplesStroopwafelLeaf(["setup-profile", "Ada123"]),
      .setupProfile(handle: "Ada123")
    )
    expectNoDifference(
      try parseExamplesStroopwafelLeaf(["profile"]),
      .profile(userID: nil)
    )
    expectNoDifference(
      try parseExamplesStroopwafelLeaf(["profile", "user-1"]),
      .profile(userID: "user-1")
    )
    expectNoDifference(try parseExamplesStroopwafelLeaf(["score", "42"]), .score(42))
    expectNoDifference(
      try parseExamplesStroopwafelLeaf(["create-room"]),
      .createRoom(code: nil)
    )
    expectNoDifference(
      try parseExamplesStroopwafelLeaf(["create-game", "ab12"]),
      .createRoom(code: "ab12")
    )
    expectNoDifference(try parseExamplesStroopwafelLeaf(["rooms"]), .rooms)
    expectNoDifference(try parseExamplesStroopwafelLeaf(["room", "AB12"]), .room(code: "AB12"))
    expectNoDifference(try parseExamplesStroopwafelLeaf(["status", "AB12"]), .room(code: "AB12"))
    expectNoDifference(try parseExamplesStroopwafelLeaf(["join", "AB12"]), .join(code: "AB12"))
    expectNoDifference(
      try parseExamplesStroopwafelLeaf(["ready", "AB12"]),
      .ready(code: "AB12", isReady: true)
    )
    expectNoDifference(
      try parseExamplesStroopwafelLeaf(["not-ready", "AB12"]),
      .ready(code: "AB12", isReady: false)
    )
    expectNoDifference(
      try parseExamplesStroopwafelLeaf(["kick", "AB12", "user-2"]),
      .kick(code: "AB12", userID: "user-2")
    )
    expectNoDifference(try parseExamplesStroopwafelLeaf(["start", "AB12"]), .start(code: "AB12"))
    expectNoDifference(try parseExamplesStroopwafelLeaf(["games"]), .games)
    expectNoDifference(
      try parseExamplesStroopwafelLeaf(["game", "game-1"]),
      .game(gameID: "game-1")
    )
    expectNoDifference(
      try parseExamplesStroopwafelLeaf(["tap", "game-1", "Blue"]),
      .tap(gameID: "game-1", color: "blue")
    )
    expectNoDifference(try parseExamplesStroopwafelLeaf(["leave", "AB12"]), .leave(code: "AB12"))
    expectNoDifference(try parseExamplesStroopwafelLeaf(["reset"]), .reset)
    expectNoDifference(
      try parseExamplesStroopwafelLeaf(["dance", "--fast"]),
      .unknown("dance")
    )
  }

  @Test
  func examplesStroopwafelLeafParserReportsMalformedArguments() throws {
    try expectExamplesStroopwafelLeafParseError(
      [],
      description: CLIExamplesStroopwafelUsage.stroopwafel
    )
    try expectExamplesStroopwafelLeafParseError(
      ["setup-profile"],
      description: CLIExamplesStroopwafelUsage.setupProfile
    )
    try expectExamplesStroopwafelLeafParseError(
      ["setup-profile", "  "],
      description: CLIExamplesStroopwafelUsage.setupProfile
    )
    try expectExamplesStroopwafelLeafParseError(
      ["profile", "user-1", "extra"],
      description: CLIExamplesStroopwafelUsage.profile
    )
    try expectExamplesStroopwafelLeafParseError(
      ["score"],
      description: CLIExamplesStroopwafelUsage.score
    )
    try expectExamplesStroopwafelLeafParseError(
      ["score", "-1"],
      description: "Invalid Stroopwafel score: -1. \(CLIExamplesStroopwafelUsage.score)"
    )
    try expectExamplesStroopwafelLeafParseError(
      ["score", "NaN"],
      description: "Invalid Stroopwafel score: NaN. \(CLIExamplesStroopwafelUsage.score)"
    )
    try expectExamplesStroopwafelLeafParseError(
      ["create-room", "AB12", "extra"],
      description: CLIExamplesStroopwafelUsage.createRoom
    )
    try expectExamplesStroopwafelLeafParseError(
      ["rooms", "extra"],
      description: CLIExamplesStroopwafelUsage.rooms
    )
    try expectExamplesStroopwafelLeafParseError(
      ["room"],
      description: CLIExamplesStroopwafelUsage.room
    )
    try expectExamplesStroopwafelLeafParseError(
      ["join"],
      description: CLIExamplesStroopwafelUsage.join
    )
    try expectExamplesStroopwafelLeafParseError(
      ["ready", "AB12", "extra"],
      description: CLIExamplesStroopwafelUsage.ready
    )
    try expectExamplesStroopwafelLeafParseError(
      ["kick", "AB12"],
      description: CLIExamplesStroopwafelUsage.kick
    )
    try expectExamplesStroopwafelLeafParseError(
      ["start"],
      description: CLIExamplesStroopwafelUsage.start
    )
    try expectExamplesStroopwafelLeafParseError(
      ["game"],
      description: CLIExamplesStroopwafelUsage.game
    )
    try expectExamplesStroopwafelLeafParseError(
      ["tap", "game-1"],
      description: CLIExamplesStroopwafelUsage.tap
    )
    try expectExamplesStroopwafelLeafParseError(
      ["tap", "game-1", "purple"],
      description: "Invalid Stroopwafel color: purple. \(CLIExamplesStroopwafelUsage.tap)"
    )
    try expectExamplesStroopwafelLeafParseError(
      ["leave"],
      description: CLIExamplesStroopwafelUsage.leave
    )
    try expectExamplesStroopwafelLeafParseError(
      ["reset", "extra"],
      description: CLIExamplesStroopwafelUsage.reset
    )
  }

  @Test
  func examplesReactionsLeafParserParsesCommandsAndOptions() throws {
    expectNoDifference(
      try parseExamples(["reactions", "tap", "fire"]),
      .reactions(.tap(CLIExamplesReactionsTapInvocation(name: "fire")))
    )
    expectNoDifference(
      try parseExamples(["reaction", "list"]),
      .reactions(.list(CLIExamplesReactionsListInvocation()))
    )
    expectNoDifference(
      try parseExamples(["topics-reactions", "watch"]),
      .reactions(.watch(CLIExamplesReactionsWatchInvocation()))
    )
    expectNoDifference(
      try parseExamplesReactionsLeaf(
        [
          "tap", "wave",
          "--direction", "45",
          "--rotation", "90",
          "--user-id", "user-2",
        ]
      ),
      .tap(
        CLIExamplesReactionsTapInvocation(
          name: "wave",
          directionAngle: 45,
          rotationAngle: 90,
          userID: "user-2"
        )
      )
    )
    expectNoDifference(
      try parseExamplesReactionsLeaf(["send", "heart"]),
      .tap(CLIExamplesReactionsTapInvocation(name: "heart"))
    )
    expectNoDifference(
      try parseExamplesReactionsLeaf(["tap", "confetti"]),
      .tap(CLIExamplesReactionsTapInvocation(name: "confetti"))
    )
    expectNoDifference(
      try parseExamplesReactionsLeaf(["list", "--limit", "1"]),
      .list(CLIExamplesReactionsListInvocation(limit: 1))
    )
    expectNoDifference(
      try parseExamplesReactionsLeaf(["messages"]),
      .list(CLIExamplesReactionsListInvocation())
    )
    expectNoDifference(
      try parseExamplesReactionsLeaf(["watch", "--events", "1"]),
      .watch(CLIExamplesReactionsWatchInvocation(eventCount: 1))
    )
    expectNoDifference(
      try parseExamplesReactionsLeaf(["dance", "--fast"]),
      .unknown("dance")
    )
  }

  @Test
  func examplesReactionsLeafParserReportsMalformedArguments() throws {
    try expectExamplesReactionsLeafParseError(
      [],
      description: CLIExamplesReactionsUsage.reactions
    )
    try expectExamplesReactionsLeafParseError(
      ["tap"],
      description: CLIExamplesReactionsUsage.tap
    )
    try expectExamplesReactionsLeafParseError(
      ["tap", "sparkle"],
      description: "Invalid reactions name: sparkle. \(CLIExamplesReactionsUsage.tap)"
    )
    try expectExamplesReactionsLeafParseError(
      ["tap", "wave", "--direction", "-1"],
      description: "Invalid reactions angle: -1. \(CLIExamplesReactionsUsage.tap)"
    )
    try expectExamplesReactionsLeafParseError(
      ["tap", "wave", "--rotation", "NaN"],
      description: "Invalid reactions angle: NaN. \(CLIExamplesReactionsUsage.tap)"
    )
    try expectExamplesReactionsLeafParseError(
      ["tap", "wave", "--user-id", "  "],
      description: CLIExamplesReactionsUsage.tap
    )
    try expectExamplesReactionsLeafParseError(
      ["tap", "wave", "--surprise"],
      description: "Unknown reactions tap option: --surprise. \(CLIExamplesReactionsUsage.tap)"
    )
    try expectExamplesReactionsLeafParseError(
      ["tap", "wave", "extra"],
      description: CLIExamplesReactionsUsage.tap
    )
    try expectExamplesReactionsLeafParseError(
      ["list", "--limit", "-1"],
      description: CLIExamplesReactionsUsage.list
    )
    try expectExamplesReactionsLeafParseError(
      ["list", "unexpected"],
      description: CLIExamplesReactionsUsage.list
    )
    try expectExamplesReactionsLeafParseError(
      ["watch", "--events", "2"],
      description: CLIExamplesReactionsUsage.watch
    )
    try expectExamplesReactionsLeafParseError(
      ["watch", "--surprise"],
      description: CLIExamplesReactionsUsage.watch
    )
  }

  @Test
  func examplesTypingIndicatorLeafParserParsesCommandsAndOptions() throws {
    expectNoDifference(
      try parseExamples(["typing-indicator", "join", "user-1"]),
      .typingIndicator(.join(userID: "user-1"))
    )
    expectNoDifference(
      try parseExamples(["typing", "type", "user-1"]),
      .typingIndicator(.type(userID: "user-1"))
    )
    expectNoDifference(
      try parseExamples(["typing-indicators", "watch"]),
      .typingIndicator(.watch(CLIExamplesTypingIndicatorWatchInvocation()))
    )
    expectNoDifference(
      try parseExamplesTypingIndicatorLeaf(["join", "user-1"]),
      .join(userID: "user-1")
    )
    expectNoDifference(
      try parseExamplesTypingIndicatorLeaf(["enter", "user-2"]),
      .join(userID: "user-2")
    )
    expectNoDifference(
      try parseExamplesTypingIndicatorLeaf(["typing", "user-1"]),
      .type(userID: "user-1")
    )
    expectNoDifference(
      try parseExamplesTypingIndicatorLeaf(["start", "user-2"]),
      .type(userID: "user-2")
    )
    expectNoDifference(
      try parseExamplesTypingIndicatorLeaf(["blur", "user-1"]),
      .stop(userID: "user-1")
    )
    expectNoDifference(
      try parseExamplesTypingIndicatorLeaf(["list"]),
      .list(CLIExamplesTypingIndicatorListInvocation())
    )
    expectNoDifference(
      try parseExamplesTypingIndicatorLeaf(["presence", "--viewer-user-id", "user-1"]),
      .list(CLIExamplesTypingIndicatorListInvocation(viewerUserID: "user-1"))
    )
    expectNoDifference(
      try parseExamplesTypingIndicatorLeaf(["watch", "--events", "1"]),
      .watch(CLIExamplesTypingIndicatorWatchInvocation(eventCount: 1))
    )
    expectNoDifference(
      try parseExamplesTypingIndicatorLeaf(["observe", "--viewer-user-id", "user-2"]),
      .watch(CLIExamplesTypingIndicatorWatchInvocation(viewerUserID: "user-2"))
    )
    expectNoDifference(
      try parseExamplesTypingIndicatorLeaf(["leave", "user-1"]),
      .leave(userID: "user-1")
    )
    expectNoDifference(
      try parseExamplesTypingIndicatorLeaf(["dance", "--fast"]),
      .unknown("dance")
    )
  }

  @Test
  func examplesTypingIndicatorLeafParserReportsMalformedArguments() throws {
    try expectExamplesTypingIndicatorLeafParseError(
      [],
      description: CLIExamplesTypingIndicatorUsage.typingIndicator
    )
    try expectExamplesTypingIndicatorLeafParseError(
      ["join"],
      description: CLIExamplesTypingIndicatorUsage.user
    )
    try expectExamplesTypingIndicatorLeafParseError(
      ["type", "  "],
      description: CLIExamplesTypingIndicatorUsage.user
    )
    try expectExamplesTypingIndicatorLeafParseError(
      ["stop", "user-1", "extra"],
      description: CLIExamplesTypingIndicatorUsage.user
    )
    try expectExamplesTypingIndicatorLeafParseError(
      ["list", "unexpected"],
      description: CLIExamplesTypingIndicatorUsage.list
    )
    try expectExamplesTypingIndicatorLeafParseError(
      ["list", "--viewer-user-id", "  "],
      description: CLIExamplesTypingIndicatorUsage.list
    )
    try expectExamplesTypingIndicatorLeafParseError(
      ["watch", "--events", "2"],
      description: CLIExamplesTypingIndicatorUsage.watch
    )
    try expectExamplesTypingIndicatorLeafParseError(
      ["watch", "--viewer-user-id", "  "],
      description: CLIExamplesTypingIndicatorUsage.watch
    )
    try expectExamplesTypingIndicatorLeafParseError(
      ["watch", "--surprise"],
      description: CLIExamplesTypingIndicatorUsage.watch
    )
    try expectExamplesTypingIndicatorLeafParseError(
      ["leave"],
      description: CLIExamplesTypingIndicatorUsage.user
    )
  }

  @Test
  func examplesAvatarStackLeafParserParsesCommandsAndOptions() throws {
    expectNoDifference(
      try parseExamples(["avatar-stack", "join", "user-1"]),
      .avatarStack(.join(CLIExamplesAvatarStackJoinInvocation(userID: "user-1")))
    )
    expectNoDifference(
      try parseExamples(["avatars", "list"]),
      .avatarStack(.list(CLIExamplesAvatarStackListInvocation()))
    )
    expectNoDifference(
      try parseExamples(["avatar-stack-recipe", "watch"]),
      .avatarStack(.watch(CLIExamplesAvatarStackWatchInvocation()))
    )
    expectNoDifference(
      try parseExamplesAvatarStackLeaf(["join", "user-1"]),
      .join(CLIExamplesAvatarStackJoinInvocation(userID: "user-1"))
    )
    expectNoDifference(
      try parseExamplesAvatarStackLeaf(["enter", "user-2", "--name", "Betty"]),
      .join(CLIExamplesAvatarStackJoinInvocation(userID: "user-2", name: "Betty"))
    )
    expectNoDifference(
      try parseExamplesAvatarStackLeaf(["list"]),
      .list(CLIExamplesAvatarStackListInvocation())
    )
    expectNoDifference(
      try parseExamplesAvatarStackLeaf(["presence", "--viewer-user-id", "user-1"]),
      .list(CLIExamplesAvatarStackListInvocation(viewerUserID: "user-1"))
    )
    expectNoDifference(
      try parseExamplesAvatarStackLeaf(["watch", "--events", "1"]),
      .watch(CLIExamplesAvatarStackWatchInvocation(eventCount: 1))
    )
    expectNoDifference(
      try parseExamplesAvatarStackLeaf(["observe", "--viewer-user-id", "user-2"]),
      .watch(CLIExamplesAvatarStackWatchInvocation(viewerUserID: "user-2"))
    )
    expectNoDifference(
      try parseExamplesAvatarStackLeaf(["leave", "user-1"]),
      .leave(userID: "user-1")
    )
    expectNoDifference(
      try parseExamplesAvatarStackLeaf(["dance", "--fast"]),
      .unknown("dance")
    )
  }

  @Test
  func examplesAvatarStackLeafParserReportsMalformedArguments() throws {
    try expectExamplesAvatarStackLeafParseError(
      [],
      description: CLIExamplesAvatarStackUsage.avatarStack
    )
    try expectExamplesAvatarStackLeafParseError(
      ["join"],
      description: CLIExamplesAvatarStackUsage.join
    )
    try expectExamplesAvatarStackLeafParseError(
      ["join", "  "],
      description: CLIExamplesAvatarStackUsage.join
    )
    try expectExamplesAvatarStackLeafParseError(
      ["join", "user-1", "--name", "  "],
      description: CLIExamplesAvatarStackUsage.join
    )
    try expectExamplesAvatarStackLeafParseError(
      ["join", "user-1", "extra"],
      description: CLIExamplesAvatarStackUsage.join
    )
    try expectExamplesAvatarStackLeafParseError(
      ["list", "unexpected"],
      description: CLIExamplesAvatarStackUsage.list
    )
    try expectExamplesAvatarStackLeafParseError(
      ["list", "--viewer-user-id", "  "],
      description: CLIExamplesAvatarStackUsage.list
    )
    try expectExamplesAvatarStackLeafParseError(
      ["watch", "--events", "2"],
      description: CLIExamplesAvatarStackUsage.watch
    )
    try expectExamplesAvatarStackLeafParseError(
      ["watch", "--viewer-user-id", "  "],
      description: CLIExamplesAvatarStackUsage.watch
    )
    try expectExamplesAvatarStackLeafParseError(
      ["watch", "--surprise"],
      description: CLIExamplesAvatarStackUsage.watch
    )
    try expectExamplesAvatarStackLeafParseError(
      ["leave"],
      description: CLIExamplesAvatarStackUsage.leave
    )
    try expectExamplesAvatarStackLeafParseError(
      ["leave", "user-1", "extra"],
      description: CLIExamplesAvatarStackUsage.leave
    )
  }

  @Test
  func examplesCursorsLeafParserParsesCommandsAndOptions() throws {
    expectNoDifference(
      try parseExamples([
        "cursors", "move", "user-1",
        "--x", "0",
        "--y", "0",
        "--x-percent", "0",
        "--y-percent", "0",
      ]),
      .cursors(.move(CLIExamplesCursorsMoveInvocation(
        userID: "user-1",
        x: 0,
        y: 0,
        xPercent: 0,
        yPercent: 0
      )))
    )
    expectNoDifference(
      try parseExamples(["cursor", "list"]),
      .cursors(.list(CLIExamplesCursorsListInvocation()))
    )
    expectNoDifference(
      try parseExamples(["custom-cursors", "move", "user-1"]),
      .customCursors(arguments: ["move", "user-1"])
    )
    expectNoDifference(
      try parseExamples(["custom-cursor", "watch"]),
      .customCursors(arguments: ["watch"])
    )
    expectNoDifference(
      try parseExamplesCursorsLeaf([
        "move", "user-1",
        "--x", "10",
        "--y", "20",
        "--x-percent", "25",
        "--y-percent", "50",
        "--color", "#123456",
      ]),
      .move(
        CLIExamplesCursorsMoveInvocation(
          userID: "user-1",
          x: 10,
          y: 20,
          xPercent: 25,
          yPercent: 50,
          color: "#123456"
        )
      )
    )
    expectNoDifference(
      try parseExamplesCursorsLeaf([
        "set", "user-2",
        "--y-percent", "40",
        "--x-percent", "30",
        "--y", "20",
        "--x", "10",
      ]),
      .move(
        CLIExamplesCursorsMoveInvocation(
          userID: "user-2",
          x: 10,
          y: 20,
          xPercent: 30,
          yPercent: 40
        )
      )
    )
    expectNoDifference(
      try parseExamplesCustomCursorsLeaf([
        "move", "user-3",
        "--x", "1",
        "--y", "2",
        "--x-percent", "3",
        "--y-percent", "4",
        "--name", "Ada",
      ]),
      .move(
        CLIExamplesCursorsMoveInvocation(
          userID: "user-3",
          x: 1,
          y: 2,
          xPercent: 3,
          yPercent: 4,
          name: "Ada"
        )
      )
    )
    expectNoDifference(
      try parseExamplesCursorsLeaf(["presence", "--viewer-user-id", "user-1"]),
      .list(CLIExamplesCursorsListInvocation(viewerUserID: "user-1"))
    )
    expectNoDifference(
      try parseExamplesCustomCursorsLeaf(["observe", "--events", "1", "--viewer-user-id", "user-2"]),
      .watch(CLIExamplesCursorsWatchInvocation(eventCount: 1, viewerUserID: "user-2"))
    )
    expectNoDifference(
      try parseExamplesCursorsLeaf(["hide", "user-1"]),
      .clear(userID: "user-1")
    )
    expectNoDifference(
      try parseExamplesCustomCursorsLeaf(["leave", "user-2"]),
      .leave(userID: "user-2")
    )
    expectNoDifference(
      try parseExamplesCursorsLeaf(["dance", "--fast"]),
      .unknown("dance")
    )
  }

  @Test
  func examplesCursorsLeafParserReportsMalformedArguments() throws {
    try expectExamplesCursorsLeafParseError(
      [],
      description: CLIExamplesCursorsUsage.cursors
    )
    try expectExamplesCursorsLeafParseError(
      ["move", "user-1", "--x", "1", "--y", "2", "--x-percent", "3"],
      description: CLIExamplesCursorsUsage.move
    )
    try expectExamplesCursorsLeafParseError(
      ["move", "user-1", "--x", "NaN", "--y", "2", "--x-percent", "3", "--y-percent", "4"],
      description: CLIExamplesCursorsUsage.move
    )
    try expectExamplesCursorsLeafParseError(
      ["move", "user-1", "--x", "1", "--y", "2", "--x-percent", "3", "--y-percent", "4", "--name", "Ada"],
      description: CLIExamplesCursorsUsage.move
    )
    try expectExamplesCustomCursorsLeafParseError(
      ["move", "user-1", "--x", "1", "--y", "2", "--x-percent", "3", "--y-percent", "4", "--name", "  "],
      description: CLIExamplesCustomCursorsUsage.move
    )
    try expectExamplesCursorsLeafParseError(
      ["list", "--viewer-user-id", "  "],
      description: CLIExamplesCursorsUsage.list
    )
    try expectExamplesCursorsLeafParseError(
      ["watch", "--events", "2"],
      description: CLIExamplesCursorsUsage.watch
    )
    try expectExamplesCustomCursorsLeafParseError(
      ["watch", "--surprise"],
      description: CLIExamplesCustomCursorsUsage.watch
    )
    try expectExamplesCursorsLeafParseError(
      ["clear"],
      description: CLIExamplesCursorsUsage.user
    )
    try expectExamplesCustomCursorsLeafParseError(
      ["leave", "user-1", "extra"],
      description: CLIExamplesCustomCursorsUsage.user
    )
  }

  @Test
  func examplesMergeTileGameLeafParserParsesCommandsAndOptions() throws {
    expectNoDifference(
      try parseExamples(["merge-tile-game", "board"]),
      .mergeTileGame(arguments: ["board"])
    )
    expectNoDifference(
      try parseExamples(["tile-game", "tap", "user-1", "0", "1"]),
      .mergeTileGame(arguments: ["tap", "user-1", "0", "1"])
    )
    expectNoDifference(
      try parseExamples(["merge-game", "watch"]),
      .mergeTileGame(arguments: ["watch"])
    )
    expectNoDifference(
      try parseExamplesMergeTileGameLeaf(["join", "user-1", "--color", "#e76f51"]),
      .join(CLIExamplesMergeTileGameJoinInvocation(userID: "user-1", color: "#e76f51"))
    )
    expectNoDifference(
      try parseExamplesMergeTileGameLeaf(["tap", "user-1", "0", "3", "--color", "#2a9d8f"]),
      .tap(
        CLIExamplesMergeTileGameTapInvocation(
          userID: "user-1",
          row: 0,
          column: 3,
          color: "#2a9d8f"
        )
      )
    )
    expectNoDifference(
      try parseExamplesMergeTileGameLeaf(["paint", "user-2", "3", "0"]),
      .tap(CLIExamplesMergeTileGameTapInvocation(userID: "user-2", row: 3, column: 0))
    )
    expectNoDifference(
      try parseExamplesMergeTileGameLeaf(["state", "--viewer-user-id", "user-1"]),
      .board(CLIExamplesMergeTileGameBoardInvocation(viewerUserID: "user-1"))
    )
    expectNoDifference(
      try parseExamplesMergeTileGameLeaf(["observe", "--events", "1", "--viewer-user-id", "user-2"]),
      .watch(CLIExamplesMergeTileGameWatchInvocation(eventCount: 1, viewerUserID: "user-2"))
    )
    expectNoDifference(
      try parseExamplesMergeTileGameLeaf(["reset"]),
      .reset
    )
    expectNoDifference(
      try parseExamplesMergeTileGameLeaf(["leave", "user-1"]),
      .leave(userID: "user-1")
    )
    expectNoDifference(
      try parseExamplesMergeTileGameLeaf(["dance", "--fast"]),
      .unknown("dance")
    )
  }

  @Test
  func examplesMergeTileGameLeafParserReportsMalformedArguments() throws {
    try expectExamplesMergeTileGameLeafParseError(
      [],
      description: CLIExamplesMergeTileGameUsage.mergeTileGame
    )
    try expectExamplesMergeTileGameLeafParseError(
      ["join"],
      description: CLIExamplesMergeTileGameUsage.join
    )
    try expectExamplesMergeTileGameLeafParseError(
      ["join", "user-1", "--color"],
      description: CLIExamplesMergeTileGameUsage.join
    )
    try expectExamplesMergeTileGameLeafParseError(
      ["tap", "user-1", "0"],
      description: CLIExamplesMergeTileGameUsage.tap
    )
    try expectExamplesMergeTileGameLeafParseError(
      ["tap", "user-1", "4", "0"],
      description: CLIExamplesMergeTileGameUsage.tap
    )
    try expectExamplesMergeTileGameLeafParseError(
      ["tap", "user-1", "0", "-1"],
      description: CLIExamplesMergeTileGameUsage.tap
    )
    try expectExamplesMergeTileGameLeafParseError(
      ["board", "--viewer-user-id", "  "],
      description: CLIExamplesMergeTileGameUsage.board
    )
    try expectExamplesMergeTileGameLeafParseError(
      ["watch", "--events", "2"],
      description: CLIExamplesMergeTileGameUsage.watch
    )
    try expectExamplesMergeTileGameLeafParseError(
      ["reset", "again"],
      description: CLIExamplesMergeTileGameUsage.reset
    )
    try expectExamplesMergeTileGameLeafParseError(
      ["leave", "user-1", "extra"],
      description: CLIExamplesMergeTileGameUsage.leave
    )
  }

  @Test
  func examplesSyncUpsLeafParserParsesCommandsAndOptions() throws {
    expectNoDifference(try parseExamplesSyncUpsLeaf(["seed"]), .seed)
    expectNoDifference(
      try parseExamplesSyncUpsLeaf(["list"]),
      .list(CLIExamplesSyncUpsListInvocation())
    )
    expectNoDifference(
      try parseExamplesSyncUpsLeaf(["list", "--refresh", "--sync-up-id", "sync-1"]),
      .list(CLIExamplesSyncUpsListInvocation(event: "refresh", syncUpID: "sync-1"))
    )
    expectNoDifference(
      try parseExamplesSyncUpsLeaf(["refresh", "--sync-up-id", "sync-2"]),
      .list(CLIExamplesSyncUpsListInvocation(event: "refresh", syncUpID: "sync-2"))
    )
    expectNoDifference(
      try parseExamplesSyncUpsLeaf(["detail", "sync-1"]),
      .detail(syncUpID: "sync-1")
    )
    expectNoDifference(
      try parseExamplesSyncUpsLeaf([
        "add", "Design", "--seconds", "900", "--theme", "periwinkle", "--attendee",
        "Blob", "--attendee", "  ", "--attendee", "Blob Jr",
      ]),
      .add(
        CLIExamplesSyncUpsAddInvocation(
          title: "Design",
          seconds: 900,
          theme: "periwinkle",
          attendeeNames: ["Blob", "Blob Jr"]
        )
      )
    )
    expectNoDifference(
      try parseExamplesSyncUpsLeaf([
        "edit", "sync-1", "--title", "Design Review", "--seconds", "1200",
        "--theme", "appOrange", "--attendee", "Blob",
      ]),
      .update(
        CLIExamplesSyncUpsUpdateInvocation(
          event: "edit",
          syncUpID: "sync-1",
          title: "Design Review",
          seconds: 1200,
          theme: "appOrange",
          replacementAttendeeNames: ["Blob"]
        )
      )
    )
    expectNoDifference(
      try parseExamplesSyncUpsLeaf(["update", "sync-1", "--title", "Planning"]),
      .update(
        CLIExamplesSyncUpsUpdateInvocation(
          event: "update",
          syncUpID: "sync-1",
          title: "Planning"
        )
      )
    )
    expectNoDifference(
      try parseExamplesSyncUpsLeaf(["add-attendee", "sync-1", "Blob", "Jr"]),
      .addAttendee(syncUpID: "sync-1", name: "Blob Jr")
    )
    expectNoDifference(
      try parseExamplesSyncUpsLeaf([
        "record-meeting", "sync-1", "--transcript", "Reviewed", "risks",
      ]),
      .record(syncUpID: "sync-1", transcript: "Reviewed risks")
    )
    expectNoDifference(
      try parseExamplesSyncUpsLeaf(["record-demo", "sync-1"]),
      .recordDemo(syncUpID: "sync-1")
    )
    expectNoDifference(
      try parseExamplesSyncUpsLeaf(["recording-demo", "sync-2"]),
      .recordDemo(syncUpID: "sync-2")
    )
    expectNoDifference(
      try parseExamplesSyncUpsLeaf(["delete", "sync-1"]),
      .delete(syncUpID: "sync-1")
    )
    expectNoDifference(
      try parseExamplesSyncUpsLeaf(["delete-attendee", "attendee-1"]),
      .deleteAttendee(attendeeID: "attendee-1")
    )
    expectNoDifference(
      try parseExamplesSyncUpsLeaf(["delete-meeting", "meeting-1"]),
      .deleteMeeting(meetingID: "meeting-1")
    )
    expectNoDifference(
      try parseExamplesSyncUpsLeaf(["dance", "--fast"]),
      .unknown("dance")
    )
  }

  @Test
  func examplesSyncUpsLeafParserReportsMalformedArguments() throws {
    try expectExamplesSyncUpsLeafParseError([], description: CLIExamplesSyncUpsUsage.syncUps)
    try expectExamplesSyncUpsLeafParseError(
      ["seed", "unexpected"],
      description: CLIExamplesSyncUpsUsage.seed
    )
    try expectExamplesSyncUpsLeafParseError(
      ["list", "--unknown"],
      description: CLIExamplesSyncUpsUsage.list
    )
    try expectExamplesSyncUpsLeafParseError(
      ["list", "--sync-up-id", ""],
      description: CLIExamplesSyncUpsUsage.list
    )
    try expectExamplesSyncUpsLeafParseError(
      ["detail"],
      description: CLIExamplesSyncUpsUsage.detail
    )
    try expectExamplesSyncUpsLeafParseError(
      ["detail", "sync-1", "unexpected"],
      description: CLIExamplesSyncUpsUsage.detail
    )
    try expectExamplesSyncUpsLeafParseError(
      ["add"],
      description: CLIExamplesSyncUpsUsage.add
    )
    try expectExamplesSyncUpsLeafParseError(
      ["add", "  "],
      description: CLIExamplesSyncUpsUsage.add
    )
    try expectExamplesSyncUpsLeafParseError(
      ["add", "Design", "--seconds", "0", "--attendee", "Blob"],
      description: "Sync-up seconds must be a positive integer."
    )
    try expectExamplesSyncUpsLeafParseError(
      ["add", "Design", "--theme"],
      description: "Unknown SyncUps theme."
    )
    try expectExamplesSyncUpsLeafParseError(
      ["add", "Design", "--attendee"],
      description: #"Usage: instant-swift-data examples sync-ups add "title" --attendee name"#
    )
    try expectExamplesSyncUpsLeafParseError(
      ["add", "Design"],
      description: "Sync-ups require at least one --attendee name."
    )
    try expectExamplesSyncUpsLeafParseError(
      ["add", "Design", "--unknown"],
      description: "Unknown sync-ups add option: --unknown. \(CLIExamplesSyncUpsUsage.syncUps)"
    )
    try expectExamplesSyncUpsLeafParseError(
      ["edit"],
      description: CLIExamplesSyncUpsUsage.edit
    )
    try expectExamplesSyncUpsLeafParseError(
      ["edit", "sync-1"],
      description: CLIExamplesSyncUpsUsage.edit
    )
    try expectExamplesSyncUpsLeafParseError(
      ["edit", "sync-1", "--title", "  "],
      description: "Sync-up title must not be empty."
    )
    try expectExamplesSyncUpsLeafParseError(
      ["edit", "sync-1", "--seconds", "-1"],
      description: "Sync-up seconds must be a positive integer."
    )
    try expectExamplesSyncUpsLeafParseError(
      ["edit", "sync-1", "--theme", "--attendee", "Blob"],
      description: "Unknown SyncUps theme."
    )
    try expectExamplesSyncUpsLeafParseError(
      ["edit", "sync-1", "--attendee"],
      description: "Usage: instant-swift-data examples sync-ups edit <sync-up-id> --attendee name"
    )
    try expectExamplesSyncUpsLeafParseError(
      ["edit", "sync-1", "--attendee", "  "],
      description: "Sync-up attendee replacement requires at least one non-empty --attendee."
    )
    try expectExamplesSyncUpsLeafParseError(
      ["edit", "sync-1", "--unknown"],
      description: "Unknown sync-ups update option: --unknown. \(CLIExamplesSyncUpsUsage.syncUps)"
    )
    try expectExamplesSyncUpsLeafParseError(
      ["add-attendee", "sync-1", "  "],
      description: CLIExamplesSyncUpsUsage.addAttendee
    )
    try expectExamplesSyncUpsLeafParseError(
      ["record", "sync-1"],
      description: CLIExamplesSyncUpsUsage.record
    )
    try expectExamplesSyncUpsLeafParseError(
      ["record", "sync-1", "--transcript"],
      description: CLIExamplesSyncUpsUsage.recordTranscript
    )
    try expectExamplesSyncUpsLeafParseError(
      ["record-demo"],
      description: CLIExamplesSyncUpsUsage.recordDemo
    )
    try expectExamplesSyncUpsLeafParseError(
      ["record-demo", "sync-1", "unexpected"],
      description: CLIExamplesSyncUpsUsage.recordDemo
    )
    try expectExamplesSyncUpsLeafParseError(
      ["delete", "sync-1", "unexpected"],
      description: CLIExamplesSyncUpsUsage.delete
    )
    try expectExamplesSyncUpsLeafParseError(
      ["delete-attendee"],
      description: CLIExamplesSyncUpsUsage.deleteAttendee
    )
    try expectExamplesSyncUpsLeafParseError(
      ["delete-meeting", "meeting-1", "unexpected"],
      description: CLIExamplesSyncUpsUsage.deleteMeeting
    )
  }

  @Test
  func examplesRemindersLeafParserParsesCommandsAndOptions() throws {
    expectNoDifference(try parseExamplesRemindersLeaf(["seed"]), .seed)
    expectNoDifference(
      try parseExamplesRemindersLeaf([
        "list", "--refresh", "--list-id", "list-1", "--completed", "false",
        "--flagged", "--scheduled", "--today", "--priority", "high",
      ]),
      .list(
        CLIExamplesRemindersListInvocation(
          event: "refresh",
          listID: "list-1",
          includeCompleted: false,
          flagged: true,
          scheduled: true,
          today: true,
          priorityRawValue: "high"
        )
      )
    )
    expectNoDifference(
      try parseExamplesRemindersLeaf(["lists", "--priority", "medium"]),
      .list(
        CLIExamplesRemindersListInvocation(
          event: "list",
          includeCompleted: false,
          priorityRawValue: "medium"
        )
      )
    )
    expectNoDifference(
      try parseExamplesRemindersLeaf(["refresh", "--list-id", "list-1"]),
      .list(CLIExamplesRemindersListInvocation(event: "refresh", listID: "list-1"))
    )
    expectNoDifference(try parseExamplesRemindersLeaf(["stats"]), .stats)
    expectNoDifference(try parseExamplesRemindersLeaf(["tags"]), .tags)
    expectNoDifference(try parseExamplesRemindersLeaf(["list-tags"]), .tags)
    expectNoDifference(
      try parseExamplesRemindersLeaf(["add-list", "Family", "Errands"]),
      .addList(title: "Family Errands")
    )
    expectNoDifference(
      try parseExamplesRemindersLeaf(["update-list", "list-1", "New", "Title"]),
      .renameList(listID: "list-1", title: "New Title")
    )
    expectNoDifference(
      try parseExamplesRemindersLeaf([
        "add", "list-1", "Take", "out", "trash", "--notes", "Bins",
        "--due-date", "2026-06-13", "--priority", "high", "--flagged",
      ]),
      .add(
        CLIExamplesReminderAddInvocation(
          listID: "list-1",
          title: "Take out trash",
          notes: "Bins",
          isFlagged: true,
          dueDateRawValue: "2026-06-13",
          priorityRawValue: "high"
        )
      )
    )
    expectNoDifference(
      try parseExamplesRemindersLeaf([
        "edit", "reminder-1", "New", "title", "--notes", "Updated",
        "--due-date", "1700000000000", "--priority", "none", "--unflagged",
      ]),
      .update(
        CLIExamplesReminderUpdateInvocation(
          reminderID: "reminder-1",
          title: "New title",
          notes: "Updated",
          isFlagged: false,
          dueDateRawValue: "1700000000000",
          priorityRawValue: "none"
        )
      )
    )
    expectNoDifference(
      try parseExamplesRemindersLeaf([
        "update", "reminder-1", "--clear-due-date", "--clear-priority", "--flagged",
      ]),
      .update(
        CLIExamplesReminderUpdateInvocation(
          reminderID: "reminder-1",
          isFlagged: true,
          clearsDueDate: true,
          clearsPriority: true
        )
      )
    )
    expectNoDifference(
      try parseExamplesRemindersLeaf(["complete", "reminder-1"]),
      .complete(reminderID: "reminder-1")
    )
    expectNoDifference(
      try parseExamplesRemindersLeaf(["delete", "reminder-1"]),
      .delete(reminderID: "reminder-1")
    )
    expectNoDifference(
      try parseExamplesRemindersLeaf(["delete-completed", "--list-id", "list-1"]),
      .deleteCompleted(listID: "list-1")
    )
    expectNoDifference(
      try parseExamplesRemindersLeaf(["delete-list", "list-1"]),
      .deleteList(listID: "list-1")
    )
    expectNoDifference(
      try parseExamplesRemindersLeaf(["tag", "reminder-1", "#Kids"]),
      .addTag(reminderID: "reminder-1", rawTag: "#Kids")
    )
    expectNoDifference(
      try parseExamplesRemindersLeaf(["untag", "reminder-1", "social"]),
      .removeTag(reminderID: "reminder-1", rawTag: "social")
    )
    expectNoDifference(
      try parseExamplesRemindersLeaf([
        "search", "Take", "trash", "--list-id", "list-1", "--tag", "kids",
        "--include-completed", "--flagged", "--scheduled", "--today",
        "--priority", "high",
      ]),
      .search(
        CLIExamplesRemindersSearchInvocation(
          text: "Take trash",
          listID: "list-1",
          rawTag: "kids",
          includeCompleted: true,
          flagged: true,
          scheduled: true,
          today: true,
          priorityRawValue: "high"
        )
      )
    )
    expectNoDifference(
      try parseExamplesRemindersLeaf(["dance", "--json"]),
      .unknown("dance")
    )
  }

  @Test
  func examplesRemindersLeafParserReportsMalformedArguments() throws {
    try expectExamplesRemindersLeafParseError([], description: CLIExamplesRemindersUsage.reminders)
    try expectExamplesRemindersLeafParseError(
      ["seed", "unexpected"],
      description: CLIExamplesRemindersUsage.seed
    )
    try expectExamplesRemindersLeafParseError(
      ["list", "--completed", "maybe"],
      description: CLIExamplesRemindersUsage.list
    )
    try expectExamplesRemindersLeafParseError(
      ["list", "--list-id", "  "],
      description: CLIExamplesRemindersUsage.list
    )
    try expectExamplesRemindersLeafParseError(
      ["list", "--unknown"],
      description: CLIExamplesRemindersUsage.list
    )
    try expectExamplesRemindersLeafParseError(
      ["stats", "unexpected"],
      description: CLIExamplesRemindersUsage.stats
    )
    try expectExamplesRemindersLeafParseError(
      ["tags", "unexpected"],
      description: CLIExamplesRemindersUsage.tags
    )
    try expectExamplesRemindersLeafParseError(
      ["add-list", "  "],
      description: CLIExamplesRemindersUsage.addList
    )
    try expectExamplesRemindersLeafParseError(
      ["rename-list"],
      description: CLIExamplesRemindersUsage.renameList
    )
    try expectExamplesRemindersLeafParseError(
      ["rename-list", "list-1", "  "],
      description: CLIExamplesRemindersUsage.renameList
    )
    try expectExamplesRemindersLeafParseError(
      ["add"],
      description: CLIExamplesRemindersUsage.add
    )
    try expectExamplesRemindersLeafParseError(
      ["add", "list-1", "  "],
      description: CLIExamplesRemindersUsage.add
    )
    try expectExamplesRemindersLeafParseError(
      ["add", "list-1", "Title", "--notes"],
      description: CLIExamplesRemindersUsage.add
    )
    try expectExamplesRemindersLeafParseError(
      ["add", "list-1", "Title", "--due-date"],
      description: CLIExamplesRemindersUsage.add
    )
    try expectExamplesRemindersLeafParseError(
      ["add", "list-1", "Title", "--priority"],
      description: CLIExamplesRemindersUsage.add
    )
    try expectExamplesRemindersLeafParseError(
      ["update"],
      description: CLIExamplesRemindersUsage.update
    )
    try expectExamplesRemindersLeafParseError(
      ["update", "reminder-1"],
      description: CLIExamplesRemindersUsage.update
    )
    try expectExamplesRemindersLeafParseError(
      ["update", "reminder-1", "--notes"],
      description: CLIExamplesRemindersUsage.update
    )
    try expectExamplesRemindersLeafParseError(
      ["update", "reminder-1", "--due-date"],
      description: CLIExamplesRemindersUsage.update
    )
    try expectExamplesRemindersLeafParseError(
      ["update", "reminder-1", "--priority"],
      description: CLIExamplesRemindersUsage.update
    )
    try expectExamplesRemindersLeafParseError(
      ["complete", "reminder-1", "extra"],
      description: CLIExamplesRemindersUsage.complete
    )
    try expectExamplesRemindersLeafParseError(
      ["delete"],
      description: CLIExamplesRemindersUsage.delete
    )
    try expectExamplesRemindersLeafParseError(
      ["delete-completed", "--list-id"],
      description: CLIExamplesRemindersUsage.deleteCompleted
    )
    try expectExamplesRemindersLeafParseError(
      ["delete-completed", "--unknown"],
      description: CLIExamplesRemindersUsage.deleteCompleted
    )
    try expectExamplesRemindersLeafParseError(
      ["delete-list", "list-1", "extra"],
      description: CLIExamplesRemindersUsage.deleteList
    )
    try expectExamplesRemindersLeafParseError(
      ["add-tag", "reminder-1", "  "],
      description: CLIExamplesRemindersUsage.addTag
    )
    try expectExamplesRemindersLeafParseError(
      ["remove-tag"],
      description: CLIExamplesRemindersUsage.removeTag
    )
    try expectExamplesRemindersLeafParseError(
      ["search"],
      description: CLIExamplesRemindersUsage.search
    )
    try expectExamplesRemindersLeafParseError(
      ["search", "--tag"],
      description: CLIExamplesRemindersUsage.search
    )
    try expectExamplesRemindersLeafParseError(
      ["search", "--priority"],
      description: CLIExamplesRemindersUsage.search
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
  func authWatchOptionsParserConsumesEventCount() throws {
    expectNoDifference(try parseAuthWatchOptions([]), 1)
    expectNoDifference(try parseAuthWatchOptions(["--events", "1"]), 1)
    expectNoDifference(try parseAuthWatchOptions(["--events", "1", "--events", "1"]), 1)
  }

  @Test
  func authWatchOptionsParserReportsMalformedArguments() throws {
    try expectAuthWatchOptionsParseError(
      ["--events"],
      description: "Missing value for --events. Usage: instant-swift-data auth watch --events 1"
    )
    try expectAuthWatchOptionsParseError(
      ["--events", "2"],
      description: "Usage: instant-swift-data auth watch --events 1"
    )
    try expectAuthWatchOptionsParseError(
      ["--surprise"],
      description: "Unknown auth watch option: --surprise. \(CLIAuthUsage.watch)"
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
  func initOptionsParserConsumesScaffoldOptions() throws {
    expectNoDifference(
      try parseInitOptions(["--example", "todos", "--to", "Scaffold"]),
      CLIScaffoldInvocation(example: "todos", outputDirectory: "Scaffold")
    )
    expectNoDifference(
      try parseInitOptions([
        "--example", "rooms", "--example", "todos", "--to", "First", "--to", "Second",
        "--force", "--force",
      ]),
      CLIScaffoldInvocation(example: "todos", outputDirectory: "Second", force: true)
    )
  }

  @Test
  func initOptionsParserReportsMalformedArguments() throws {
    try expectInitOptionsParseError([], description: CLIInitUsage.initScaffold)
    try expectInitOptionsParseError(["--example"], description: CLIInitUsage.initScaffold)
    try expectInitOptionsParseError(
      ["--example", "todos", "--to", "  "],
      description: CLIInitUsage.initScaffold
    )
    try expectInitOptionsParseError(
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
  func artifactOptionsParsersConsumeDuplicateOptionsWithLastValueWinning() throws {
    expectNoDifference(
      try parseGenerateArtifactOptions([
        "--example", "rooms", "--example", "todos", "--to", "old.ts",
        "--to", "instant.schema.ts",
      ]),
      CLIGenerateArtifactInvocation(example: "todos", outputPath: "instant.schema.ts")
    )
    expectNoDifference(
      try parseVerifyArtifactOptions([
        "--example", "rooms", "--example", "todos", "--from", "old.ts",
        "--from", "instant.schema.ts",
      ]),
      CLIVerifyArtifactInvocation(example: "todos", inputPath: "instant.schema.ts")
    )
  }

  @Test
  func artifactOptionsParsersReportMalformedArguments() throws {
    try expectGenerateArtifactOptionsParseError(
      ["--to", "instant.schema.ts"],
      description: CLISchemaUsage.generate
    )
    try expectGenerateArtifactOptionsParseError(
      ["--example", "todos", "--unknown"],
      description: "Unknown generate option: --unknown. \(CLISchemaUsage.generate)"
    )
    try expectVerifyArtifactOptionsParseError(
      ["--example", "todos"],
      description: CLISchemaUsage.verify
    )
    try expectVerifyArtifactOptionsParseError(
      ["--example", "todos", "--unknown"],
      description: "Unknown schema verify option: --unknown. \(CLISchemaUsage.verify)"
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
  func appEphemeralOptionsParserConsumesTitleOptions() throws {
    expectNoDifference(
      try parseAppEphemeralOptions(["--title", " Reminders Port "]),
      CLIAppEphemeralInvocation(title: " Reminders Port ")
    )
    expectNoDifference(
      try parseAppEphemeralOptions(["--title", "First", "--title", "Second"]),
      CLIAppEphemeralInvocation(title: "Second")
    )
  }

  @Test
  func appEphemeralOptionsParserReportsMalformedArguments() throws {
    try expectAppEphemeralOptionsParseError([], contains: "app ephemeral --title <title>")
    try expectAppEphemeralOptionsParseError(["--title"], contains: "app ephemeral --title <title>")
    try expectAppEphemeralOptionsParseError(
      ["--title", "   "],
      contains: "app ephemeral --title <title>"
    )
    try expectAppEphemeralOptionsParseError(
      ["--surprise"],
      contains: "Unknown ephemeral app option: --surprise."
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
    expectNoDifference(try parseValidation(["reminders"]), .reminders)
    expectNoDifference(try parseValidation(["local-reminders"]), .reminders)
    expectNoDifference(try parseValidation(["typed-drafts"]), .typedDrafts)
    expectNoDifference(try parseValidation(["drafts"]), .typedDrafts)
    expectNoDifference(try parseValidation(["platform-adapters"]), .platformAdapters)
    expectNoDifference(try parseValidation(["adapters"]), .platformAdapters)
    expectNoDifference(try parseValidation(["wrappers"]), .platformAdapters)
    expectNoDifference(try parseValidation(["syncups-recording"]), .syncUpsRecording)
    expectNoDifference(try parseValidation(["sync-ups-recording"]), .syncUpsRecording)
    expectNoDifference(try parseValidation(["recording"]), .syncUpsRecording)
    expectNoDifference(try parseValidation(["syncups"]), .syncUpsRecording)
    expectNoDifference(try parseValidation(["parity-report"]), .parityReport)
    expectNoDifference(try parseValidation(["parity"]), .parityReport)
    expectNoDifference(try parseValidation(["coverage"]), .parityReport)
  }

  @Test
  func validationParserReportsMalformedArguments() throws {
    #expect(CLIValidationUsage.validation.contains("parity-report|coverage"))
    #expect(CLIValidationUsage.validation.contains("validation reminders [--json|--jsonl]"))
    #expect(CLIValidationUsage.validation.contains("validation coverage [--json|--jsonl]"))
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
  func adminMergeHeadScannerExtractsMergeJSONOnlyAfterValidTransactHead() {
    expectNoDifference(
      CLIAdminArguments.firstMergeJSONAfterValidTransactHead([
        "transact", " notes ", " note-1 ", "--merge", #"{"title":"Hi"}"#,
      ]),
      #"{"title":"Hi"}"#
    )
    expectNoDifference(
      CLIAdminArguments.firstMergeJSONAfterValidTransactHead([
        "tx", "notes", "note-1", "--transaction-id", " tx-1 ", "--merge", "[",
      ]),
      "["
    )

    let invalidHeads: [[String]] = [
      ["query", "notes", "--merge", "{}"],
      ["transact", "bad namespace", "note-1", "--merge", "{}"],
      ["transact", "notes", "  ", "--merge", "{}"],
      ["transact", "notes", "note-1", "--transaction-id", "  ", "--merge", "{}"],
      [
        "transact", "notes", "note-1", "--transaction-id", "tx-1",
        "--transaction-id", "tx-2", "--merge", "{}",
      ],
      ["transact", "notes", "note-1", "--unknown", "--merge", "{}"],
      ["transact", "notes", "note-1", "--merge"],
    ]
    for arguments in invalidHeads {
      expectNoDifference(CLIAdminArguments.firstMergeJSONAfterValidTransactHead(arguments), nil)
    }
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
  func outboxTransportOptionsParserConsumesAllFlag() throws {
    expectNoDifference(try parseOutboxTransportOptions([]), false)
    expectNoDifference(try parseOutboxTransportOptions(["--all"]), true)
    expectNoDifference(try parseOutboxTransportOptions(["--all", "--all"]), true)
  }

  @Test
  func outboxTransportOptionsParserReportsMalformedArguments() throws {
    var input = ["--failed"][...]
    do {
      _ = try CLIOutboxTransportOptionsParser().parse(&input)
      #expect(Bool(false), "Expected outbox transport option parsing to fail.")
    } catch let error as CLIOutboxArgumentError {
      expectNoDifference(error.description, CLIOutboxUsage.transport)
    } catch {
      #expect(Bool(false), "Unexpected error: \(error)")
    }
    expectNoDifference(Array(input), [])
  }

  @Test
  func outboxFlushOptionsParserConsumesLimit() throws {
    expectNoDifference(try parseOutboxFlushOptions([]), nil)
    expectNoDifference(try parseOutboxFlushOptions(["--limit", "0"]), 0)
    expectNoDifference(try parseOutboxFlushOptions(["--limit", "1", "--limit", "3"]), 3)
  }

  @Test
  func outboxFlushOptionsParserReportsMalformedArguments() throws {
    try expectOutboxFlushOptionsParseError(["--limit"], description: CLIOutboxUsage.flush)
    try expectOutboxFlushOptionsParseError(["--limit", "-1"], description: CLIOutboxUsage.flush)
    try expectOutboxFlushOptionsParseError(
      ["--unknown"],
      description: "Unknown outbox flush option: --unknown. \(CLIOutboxUsage.flush)"
    )
  }

  @Test
  func outboxDrainOptionsParserConsumesLocalConfirmAndLimit() throws {
    expectNoDifference(try parseOutboxDrainOptions(["--local-confirm"]), nil)
    expectNoDifference(try parseOutboxDrainOptions(["--local-confirm", "--limit", "0"]), 0)
    expectNoDifference(
      try parseOutboxDrainOptions(["--limit", "1", "--local-confirm", "--limit", "3"]),
      3
    )
  }

  @Test
  func outboxDrainOptionsParserReportsMalformedArguments() throws {
    try expectOutboxDrainOptionsParseError([], description: CLIOutboxUsage.drain)
    try expectOutboxDrainOptionsParseError(["--limit", "1"], description: CLIOutboxUsage.drain)
    try expectOutboxDrainOptionsParseError(
      ["--local-confirm", "--limit", "oops"],
      description: CLIOutboxUsage.drain
    )
    try expectOutboxDrainOptionsParseError(
      ["--unknown"],
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
      .todoLinks(.seed)
    )
    expectNoDifference(
      try parseExamples(["counters", "seed"]),
      .counters(.seed)
    )
    expectNoDifference(
      try parseExamples(["cloudkit-demo", "list"]),
      .counters(.list)
    )
    expectNoDifference(
      try parseExamples(["chat", "seed"]),
      .chat(arguments: ["seed"])
    )
    expectNoDifference(
      try parseExamples(["microblog", "seed"]),
      .microblog(arguments: ["seed"])
    )
    expectNoDifference(
      try parseExamples(["mobile-chat", "seed"]),
      .mobileChat(arguments: ["seed"])
    )
    expectNoDifference(
      try parseExamples(["mobilechat", "seed"]),
      .mobileChat(arguments: ["seed"])
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
          arguments: ["--fast"],
          leaf: .unknown("dance")
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
  func roomWatchOptionsParserConsumesEventCount() throws {
    expectNoDifference(try parseRoomWatchOptions([]), 1)
    expectNoDifference(try parseRoomWatchOptions(["--events", "1"]), 1)
    expectNoDifference(try parseRoomWatchOptions(["--events", "1", "--events", "1"]), 1)
  }

  @Test
  func roomWatchOptionsParserReportsMalformedArguments() throws {
    let usageCommand = "instant-swift-data rooms presence watch <room-type> <room-id>"
    try expectRoomWatchOptionsParseError(
      ["--events"],
      description: "Missing value for --events. Usage: \(usageCommand) --events 1"
    )
    try expectRoomWatchOptionsParseError(
      ["--events", "2"],
      description: "Usage: \(usageCommand) --events 1"
    )
    try expectRoomWatchOptionsParseError(
      ["--surprise"],
      description:
        "Unknown rooms presence watch option: --surprise. Usage: \(usageCommand) [--events 1] [--json|--jsonl]"
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
  func filesWatchOptionsParserConsumesEventCount() throws {
    expectNoDifference(try parseFilesWatchOptions([]), 1)
    expectNoDifference(try parseFilesWatchOptions(["--events", "1"]), 1)
    expectNoDifference(try parseFilesWatchOptions(["--events", "1", "--events", "1"]), 1)
  }

  @Test
  func filesWatchOptionsParserReportsMalformedArguments() throws {
    try expectFilesWatchOptionsParseError(
      ["--events"],
      description: "Missing value for --events. Usage: instant-swift-data files watch --events 1"
    )
    try expectFilesWatchOptionsParseError(
      ["--events", "2"],
      description: "Usage: instant-swift-data files watch --events 1"
    )
    try expectFilesWatchOptionsParseError(
      ["--surprise"],
      description: "Unknown files watch option: --surprise. \(CLIFilesUsage.watch)"
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
  func streamWatchOptionsParserConsumesEventCount() throws {
    expectNoDifference(try parseStreamWatchOptions([]), 1)
    expectNoDifference(try parseStreamWatchOptions(["--events", "1"]), 1)
    expectNoDifference(try parseStreamWatchOptions(["--events", "1", "--events", "1"]), 1)
  }

  @Test
  func streamWatchOptionsParserReportsMalformedArguments() throws {
    try expectStreamWatchOptionsParseError(
      ["--events"],
      description:
        "Missing value for --events. Usage: instant-swift-data streams watch <stream-id> --events 1"
    )
    try expectStreamWatchOptionsParseError(
      ["--events", "2"],
      description: "Usage: instant-swift-data streams watch <stream-id> --events 1"
    )
    try expectStreamWatchOptionsParseError(
      ["--surprise"],
      description: "Unknown streams watch option: --surprise. \(CLIStreamsUsage.watch)"
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

private func parseExamplesTodosLeaf(
  _ arguments: [String]
) throws -> CLIExamplesTodosLeafInvocation {
  var input = arguments[...]
  let invocation = try CLIExamplesTodosLeafParser().parse(&input)
  expectNoDifference(Array(input), [])
  return invocation
}

private func parseExamplesAuthLeaf(
  _ arguments: [String]
) throws -> CLIExamplesAuthLeafInvocation {
  var input = arguments[...]
  let invocation = try CLIExamplesAuthLeafParser().parse(&input)
  expectNoDifference(Array(input), [])
  return invocation
}

private func parseExamplesAppBuilderLeaf(
  _ arguments: [String]
) throws -> CLIExamplesAppBuilderLeafInvocation {
  var input = arguments[...]
  let invocation = try CLIExamplesAppBuilderLeafParser().parse(&input)
  expectNoDifference(Array(input), [])
  return invocation
}

private func parseExamplesTodosQueryOptions(
  _ arguments: [String]
) throws -> CLITodosQueryInvocation {
  var input = arguments[...]
  let parser = CLIExamplesTodosQueryOptionsParser(
    usageCommand: CLIExamplesTodosUsage.listCommand,
    usage: CLIExamplesTodosUsage.list,
    unknown: { option, usage in
      CLIExamplesTodosArgumentError.unknownListOption(option, usage: usage)
    }
  )
  let invocation = try parser.parse(&input)
  expectNoDifference(Array(input), [])
  return invocation
}

private func parseExamplesTodosWatchOptions(
  _ arguments: [String]
) throws -> CLIExamplesTodosWatchInvocation {
  var input = arguments[...]
  let invocation = try CLIExamplesTodosWatchOptionsParser().parse(&input)
  expectNoDifference(Array(input), [])
  return invocation
}

private func parseExamplesTodoLinksLeaf(
  _ arguments: [String]
) throws -> CLIExamplesTodoLinksLeafInvocation {
  var input = arguments[...]
  let invocation = try CLIExamplesTodoLinksLeafParser().parse(&input)
  expectNoDifference(Array(input), [])
  return invocation
}

private func parseExamplesCountersLeaf(
  _ arguments: [String]
) throws -> CLIExamplesCountersLeafInvocation {
  var input = arguments[...]
  let invocation = try CLIExamplesCountersLeafParser().parse(&input)
  expectNoDifference(Array(input), [])
  return invocation
}

private func parseExamplesChatLeaf(
  _ arguments: [String]
) throws -> CLIExamplesChatLeafInvocation {
  var input = arguments[...]
  let invocation = try CLIExamplesChatLeafParser().parse(&input)
  expectNoDifference(Array(input), [])
  return invocation
}

private func parseExamplesMicroblogLeaf(
  _ arguments: [String]
) throws -> CLIExamplesMicroblogLeafInvocation {
  var input = arguments[...]
  let invocation = try CLIExamplesMicroblogLeafParser().parse(&input)
  expectNoDifference(Array(input), [])
  return invocation
}

private func parseExamplesMobileChatLeaf(
  _ arguments: [String]
) throws -> CLIExamplesMobileChatLeafInvocation {
  var input = arguments[...]
  let invocation = try CLIExamplesMobileChatLeafParser().parse(&input)
  expectNoDifference(Array(input), [])
  return invocation
}

private func parseExamplesStroopwafelLeaf(
  _ arguments: [String]
) throws -> CLIExamplesStroopwafelLeafInvocation {
  var input = arguments[...]
  let invocation = try CLIExamplesStroopwafelLeafParser().parse(&input)
  expectNoDifference(Array(input), [])
  return invocation
}

private func parseExamplesReactionsLeaf(
  _ arguments: [String]
) throws -> CLIExamplesReactionsLeafInvocation {
  var input = arguments[...]
  let invocation = try CLIExamplesReactionsLeafParser().parse(&input)
  expectNoDifference(Array(input), [])
  return invocation
}

private func parseExamplesTypingIndicatorLeaf(
  _ arguments: [String]
) throws -> CLIExamplesTypingIndicatorLeafInvocation {
  var input = arguments[...]
  let invocation = try CLIExamplesTypingIndicatorLeafParser().parse(&input)
  expectNoDifference(Array(input), [])
  return invocation
}

private func parseExamplesAvatarStackLeaf(
  _ arguments: [String]
) throws -> CLIExamplesAvatarStackLeafInvocation {
  var input = arguments[...]
  let invocation = try CLIExamplesAvatarStackLeafParser().parse(&input)
  expectNoDifference(Array(input), [])
  return invocation
}

private func parseExamplesCursorsLeaf(
  _ arguments: [String]
) throws -> CLIExamplesCursorsLeafInvocation {
  var input = arguments[...]
  let invocation = try CLIExamplesCursorsLeafParser().parse(&input)
  expectNoDifference(Array(input), [])
  return invocation
}

private func parseExamplesCustomCursorsLeaf(
  _ arguments: [String]
) throws -> CLIExamplesCursorsLeafInvocation {
  var input = arguments[...]
  let invocation = try CLIExamplesCustomCursorsLeafParser().parse(&input)
  expectNoDifference(Array(input), [])
  return invocation
}

private func parseExamplesMergeTileGameLeaf(
  _ arguments: [String]
) throws -> CLIExamplesMergeTileGameLeafInvocation {
  var input = arguments[...]
  let invocation = try CLIExamplesMergeTileGameLeafParser().parse(&input)
  expectNoDifference(Array(input), [])
  return invocation
}

private func parseExamplesSyncUpsLeaf(
  _ arguments: [String]
) throws -> CLIExamplesSyncUpsLeafInvocation {
  var input = arguments[...]
  let invocation = try CLIExamplesSyncUpsLeafParser().parse(&input)
  expectNoDifference(Array(input), [])
  return invocation
}

private func parseExamplesRemindersLeaf(
  _ arguments: [String]
) throws -> CLIExamplesRemindersLeafInvocation {
  var input = arguments[...]
  let invocation = try CLIExamplesRemindersLeafParser().parse(&input)
  expectNoDifference(Array(input), [])
  return invocation
}

private func parseAuth(_ arguments: [String]) throws -> CLIAuthInvocation {
  var input = arguments[...]
  let invocation = try CLIAuthParser().parse(&input)
  expectNoDifference(Array(input), [])
  return invocation
}

private func parseAuthWatchOptions(_ arguments: [String]) throws -> Int {
  var input = arguments[...]
  let eventCount = try CLIAuthWatchOptionsParser().parse(&input)
  expectNoDifference(Array(input), [])
  return eventCount
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

private func parseInitOptions(_ arguments: [String]) throws -> CLIScaffoldInvocation {
  var input = arguments[...]
  let invocation = try CLIInitOptionsParser().parse(&input)
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

private func parseGenerateArtifactOptions(
  _ arguments: [String]
) throws -> CLIGenerateArtifactInvocation {
  var input = arguments[...]
  let parser = CLIGenerateArtifactOptionsParser(
    usage: CLISchemaUsage.generate,
    unknown: { option, usage in
      CLISchemaArgumentError.unknownGenerateOption(option, usage: usage)
    },
    invalid: { usage in
      CLISchemaArgumentError.invalidArguments(usage: usage)
    }
  )
  let invocation = try parser.parse(&input)
  expectNoDifference(Array(input), [])
  return invocation
}

private func parseVerifyArtifactOptions(
  _ arguments: [String]
) throws -> CLIVerifyArtifactInvocation {
  var input = arguments[...]
  let parser = CLIVerifyArtifactOptionsParser(
    usage: CLISchemaUsage.verify,
    unknown: { option, usage in
      CLISchemaArgumentError.unknownVerifyOption(option, usage: usage)
    },
    invalid: { usage in
      CLISchemaArgumentError.invalidArguments(usage: usage)
    }
  )
  let invocation = try parser.parse(&input)
  expectNoDifference(Array(input), [])
  return invocation
}

private func parseApp(_ arguments: [String]) throws -> CLIAppInvocation {
  var input = arguments[...]
  let invocation = try CLIAppParser().parse(&input)
  expectNoDifference(Array(input), [])
  return invocation
}

private func parseAppEphemeralOptions(
  _ arguments: [String]
) throws -> CLIAppEphemeralInvocation {
  var input = arguments[...]
  let invocation = try CLIAppEphemeralOptionsParser().parse(&input)
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

private func parseOutboxTransportOptions(_ arguments: [String]) throws -> Bool {
  var input = arguments[...]
  let includeFailed = try CLIOutboxTransportOptionsParser().parse(&input)
  expectNoDifference(Array(input), [])
  return includeFailed
}

private func parseOutboxFlushOptions(_ arguments: [String]) throws -> Int? {
  var input = arguments[...]
  let limit = try CLIOutboxFlushOptionsParser().parse(&input)
  expectNoDifference(Array(input), [])
  return limit
}

private func parseOutboxDrainOptions(_ arguments: [String]) throws -> Int? {
  var input = arguments[...]
  let limit = try CLIOutboxDrainOptionsParser().parse(&input)
  expectNoDifference(Array(input), [])
  return limit
}

private func parseRooms(_ arguments: [String]) throws -> CLIRoomsInvocation {
  var input = arguments[...]
  let invocation = try CLIRoomsParser().parse(&input)
  expectNoDifference(Array(input), [])
  return invocation
}

private func parseRoomWatchOptions(_ arguments: [String]) throws -> Int {
  var input = arguments[...]
  let parser = CLIRoomWatchOptionsParser(
    usageCommand: "instant-swift-data rooms presence watch <room-type> <room-id>",
    domain: "rooms presence watch"
  )
  let eventCount = try parser.parse(&input)
  expectNoDifference(Array(input), [])
  return eventCount
}

private func parseFiles(_ arguments: [String]) throws -> CLIFilesInvocation {
  var input = arguments[...]
  let invocation = try CLIFilesParser().parse(&input)
  expectNoDifference(Array(input), [])
  return invocation
}

private func parseFilesWatchOptions(_ arguments: [String]) throws -> Int {
  var input = arguments[...]
  let eventCount = try CLIFilesWatchOptionsParser().parse(&input)
  expectNoDifference(Array(input), [])
  return eventCount
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

private func parseStreamWatchOptions(_ arguments: [String]) throws -> Int {
  var input = arguments[...]
  let eventCount = try CLIStreamWatchOptionsParser().parse(&input)
  expectNoDifference(Array(input), [])
  return eventCount
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

private func expectAuthWatchOptionsParseError(
  _ arguments: [String],
  description expectedDescription: String
) throws {
  do {
    _ = try parseAuthWatchOptions(arguments)
    Issue.record("Expected auth watch options parser to reject \(arguments).")
  } catch let error as CLIAuthArgumentError {
    expectNoDifference(error.description, expectedDescription)
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

private func expectInitOptionsParseError(
  _ arguments: [String],
  description expectedDescription: String
) throws {
  do {
    _ = try parseInitOptions(arguments)
    Issue.record("Expected init options parser to reject \(arguments).")
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

private func expectGenerateArtifactOptionsParseError(
  _ arguments: [String],
  description expectedDescription: String
) throws {
  do {
    _ = try parseGenerateArtifactOptions(arguments)
    Issue.record("Expected generate artifact options parser to reject \(arguments).")
  } catch let error as CLISchemaArgumentError {
    expectNoDifference(error.description, expectedDescription)
    expectNoDifference(error.exitCode, 64)
  }
}

private func expectVerifyArtifactOptionsParseError(
  _ arguments: [String],
  description expectedDescription: String
) throws {
  do {
    _ = try parseVerifyArtifactOptions(arguments)
    Issue.record("Expected verify artifact options parser to reject \(arguments).")
  } catch let error as CLISchemaArgumentError {
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

private func expectAppEphemeralOptionsParseError(
  _ arguments: [String],
  contains expectedFragment: String
) throws {
  do {
    _ = try parseAppEphemeralOptions(arguments)
    Issue.record("Expected app ephemeral options parser to reject \(arguments).")
  } catch let error as CLIAppArgumentError {
    #expect(error.description.contains(expectedFragment))
    expectNoDifference(error.exitCode, 64)
  }
}

private func expectExamplesTodosLeafParseError(
  _ arguments: [String],
  description expectedDescription: String
) throws {
  do {
    _ = try parseExamplesTodosLeaf(arguments)
    Issue.record("Expected examples todos parser to reject \(arguments).")
  } catch let error as CLIExamplesTodosArgumentError {
    expectNoDifference(error.description, expectedDescription)
    expectNoDifference(error.exitCode, 64)
  }
}

private func expectExamplesTodosQueryOptionsParseError(
  _ arguments: [String],
  description expectedDescription: String
) throws {
  do {
    _ = try parseExamplesTodosQueryOptions(arguments)
    Issue.record("Expected examples todos query options parser to reject \(arguments).")
  } catch let error as CLIExamplesTodosArgumentError {
    expectNoDifference(error.description, expectedDescription)
    expectNoDifference(error.exitCode, 64)
  }
}

private func expectExamplesTodosWatchOptionsParseError(
  _ arguments: [String],
  description expectedDescription: String
) throws {
  do {
    _ = try parseExamplesTodosWatchOptions(arguments)
    Issue.record("Expected examples todos watch options parser to reject \(arguments).")
  } catch let error as CLIExamplesTodosArgumentError {
    expectNoDifference(error.description, expectedDescription)
    expectNoDifference(error.exitCode, 64)
  }
}

private func expectExamplesAuthLeafParseError(
  _ arguments: [String],
  description expectedDescription: String
) throws {
  do {
    _ = try parseExamplesAuthLeaf(arguments)
    Issue.record("Expected examples auth parser to reject \(arguments).")
  } catch let error as CLIExamplesAuthArgumentError {
    expectNoDifference(error.description, expectedDescription)
    expectNoDifference(error.exitCode, 64)
  }
}

private func expectExamplesAppBuilderLeafParseError(
  _ arguments: [String],
  description expectedDescription: String
) throws {
  do {
    _ = try parseExamplesAppBuilderLeaf(arguments)
    Issue.record("Expected examples app-builder parser to reject \(arguments).")
  } catch let error as CLIExamplesAppBuilderArgumentError {
    expectNoDifference(error.description, expectedDescription)
    expectNoDifference(error.exitCode, 64)
  }
}

private func expectExamplesTodoLinksLeafParseError(
  _ arguments: [String],
  description expectedDescription: String
) throws {
  do {
    _ = try parseExamplesTodoLinksLeaf(arguments)
    Issue.record("Expected examples todo-links parser to reject \(arguments).")
  } catch let error as CLIExamplesTodoLinksArgumentError {
    expectNoDifference(error.description, expectedDescription)
    expectNoDifference(error.exitCode, 64)
  }
}

private func expectExamplesCountersLeafParseError(
  _ arguments: [String],
  description expectedDescription: String
) throws {
  do {
    _ = try parseExamplesCountersLeaf(arguments)
    Issue.record("Expected examples counters parser to reject \(arguments).")
  } catch let error as CLIExamplesCountersArgumentError {
    expectNoDifference(error.description, expectedDescription)
    expectNoDifference(error.exitCode, 64)
  }
}

private func expectExamplesChatLeafParseError(
  _ arguments: [String],
  description expectedDescription: String
) throws {
  do {
    _ = try parseExamplesChatLeaf(arguments)
    Issue.record("Expected examples chat parser to reject \(arguments).")
  } catch let error as CLIExamplesChatArgumentError {
    expectNoDifference(error.description, expectedDescription)
    expectNoDifference(error.exitCode, 64)
  }
}

private func expectExamplesMicroblogLeafParseError(
  _ arguments: [String],
  description expectedDescription: String
) throws {
  do {
    _ = try parseExamplesMicroblogLeaf(arguments)
    Issue.record("Expected examples microblog parser to reject \(arguments).")
  } catch let error as CLIExamplesMicroblogArgumentError {
    expectNoDifference(error.description, expectedDescription)
    expectNoDifference(error.exitCode, 64)
  }
}

private func expectExamplesMobileChatLeafParseError(
  _ arguments: [String],
  description expectedDescription: String
) throws {
  do {
    _ = try parseExamplesMobileChatLeaf(arguments)
    Issue.record("Expected examples mobile chat parser to reject \(arguments).")
  } catch let error as CLIExamplesMobileChatArgumentError {
    expectNoDifference(error.description, expectedDescription)
    expectNoDifference(error.exitCode, 64)
  }
}

private func expectExamplesStroopwafelLeafParseError(
  _ arguments: [String],
  description expectedDescription: String
) throws {
  do {
    _ = try parseExamplesStroopwafelLeaf(arguments)
    Issue.record("Expected examples Stroopwafel parser to reject \(arguments).")
  } catch let error as CLIExamplesStroopwafelArgumentError {
    expectNoDifference(error.description, expectedDescription)
    expectNoDifference(error.exitCode, 64)
  }
}

private func expectExamplesReactionsLeafParseError(
  _ arguments: [String],
  description expectedDescription: String
) throws {
  do {
    _ = try parseExamplesReactionsLeaf(arguments)
    Issue.record("Expected examples reactions parser to reject \(arguments).")
  } catch let error as CLIExamplesReactionsArgumentError {
    expectNoDifference(error.description, expectedDescription)
    expectNoDifference(error.exitCode, 64)
  }
}

private func expectExamplesTypingIndicatorLeafParseError(
  _ arguments: [String],
  description expectedDescription: String
) throws {
  do {
    _ = try parseExamplesTypingIndicatorLeaf(arguments)
    Issue.record("Expected examples typing indicator parser to reject \(arguments).")
  } catch let error as CLIExamplesTypingIndicatorArgumentError {
    expectNoDifference(error.description, expectedDescription)
    expectNoDifference(error.exitCode, 64)
  }
}

private func expectExamplesAvatarStackLeafParseError(
  _ arguments: [String],
  description expectedDescription: String
) throws {
  do {
    _ = try parseExamplesAvatarStackLeaf(arguments)
    Issue.record("Expected examples avatar stack parser to reject \(arguments).")
  } catch let error as CLIExamplesAvatarStackArgumentError {
    expectNoDifference(error.description, expectedDescription)
    expectNoDifference(error.exitCode, 64)
  }
}

private func expectExamplesCursorsLeafParseError(
  _ arguments: [String],
  description expectedDescription: String
) throws {
  do {
    _ = try parseExamplesCursorsLeaf(arguments)
    Issue.record("Expected examples cursors parser to reject \(arguments).")
  } catch let error as CLIExamplesCursorsArgumentError {
    expectNoDifference(error.description, expectedDescription)
    expectNoDifference(error.exitCode, 64)
  }
}

private func expectExamplesCustomCursorsLeafParseError(
  _ arguments: [String],
  description expectedDescription: String
) throws {
  do {
    _ = try parseExamplesCustomCursorsLeaf(arguments)
    Issue.record("Expected examples custom cursors parser to reject \(arguments).")
  } catch let error as CLIExamplesCursorsArgumentError {
    expectNoDifference(error.description, expectedDescription)
    expectNoDifference(error.exitCode, 64)
  }
}

private func expectExamplesMergeTileGameLeafParseError(
  _ arguments: [String],
  description expectedDescription: String
) throws {
  do {
    _ = try parseExamplesMergeTileGameLeaf(arguments)
    Issue.record("Expected examples merge tile game parser to reject \(arguments).")
  } catch let error as CLIExamplesMergeTileGameArgumentError {
    expectNoDifference(error.description, expectedDescription)
    expectNoDifference(error.exitCode, 64)
  }
}

private func expectExamplesSyncUpsLeafParseError(
  _ arguments: [String],
  description expectedDescription: String
) throws {
  do {
    _ = try parseExamplesSyncUpsLeaf(arguments)
    Issue.record("Expected examples sync-ups parser to reject \(arguments).")
  } catch let error as CLIExamplesSyncUpsArgumentError {
    expectNoDifference(error.description, expectedDescription)
    expectNoDifference(error.exitCode, 64)
  }
}

private func expectExamplesRemindersLeafParseError(
  _ arguments: [String],
  description expectedDescription: String
) throws {
  do {
    _ = try parseExamplesRemindersLeaf(arguments)
    Issue.record("Expected examples reminders parser to reject \(arguments).")
  } catch let error as CLIExamplesRemindersArgumentError {
    expectNoDifference(error.description, expectedDescription)
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

private func expectOutboxFlushOptionsParseError(
  _ arguments: [String],
  description expectedDescription: String
) throws {
  do {
    _ = try parseOutboxFlushOptions(arguments)
    Issue.record("Expected outbox flush options parser to reject \(arguments).")
  } catch let error as CLIOutboxArgumentError {
    expectNoDifference(error.description, expectedDescription)
    expectNoDifference(error.exitCode, 64)
  }
}

private func expectOutboxDrainOptionsParseError(
  _ arguments: [String],
  description expectedDescription: String
) throws {
  do {
    _ = try parseOutboxDrainOptions(arguments)
    Issue.record("Expected outbox drain options parser to reject \(arguments).")
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

private func expectRoomWatchOptionsParseError(
  _ arguments: [String],
  description expectedDescription: String
) throws {
  do {
    _ = try parseRoomWatchOptions(arguments)
    Issue.record("Expected room watch options parser to reject \(arguments).")
  } catch let error as CLIRoomsArgumentError {
    expectNoDifference(error.description, expectedDescription)
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

private func expectFilesWatchOptionsParseError(
  _ arguments: [String],
  description expectedDescription: String
) throws {
  do {
    _ = try parseFilesWatchOptions(arguments)
    Issue.record("Expected files watch options parser to reject \(arguments).")
  } catch let error as CLIFilesArgumentError {
    expectNoDifference(error.description, expectedDescription)
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

private func expectStreamWatchOptionsParseError(
  _ arguments: [String],
  description expectedDescription: String
) throws {
  do {
    _ = try parseStreamWatchOptions(arguments)
    Issue.record("Expected stream watch options parser to reject \(arguments).")
  } catch let error as CLIStreamsArgumentError {
    expectNoDifference(error.description, expectedDescription)
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
