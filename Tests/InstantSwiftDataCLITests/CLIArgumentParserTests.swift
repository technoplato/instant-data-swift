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
