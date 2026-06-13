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
}
