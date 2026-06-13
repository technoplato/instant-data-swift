import Parsing

public enum CLIOutputMode: Equatable, Sendable {
  case human
  case json
  case jsonl
}

public enum CLITopLevelCommand: Equatable, Sendable {
  case admin
  case app
  case auth
  case benchmark
  case cache
  case connection
  case examples
  case files
  case help
  case initScaffold
  case localID
  case outbox
  case permissions
  case query
  case rooms
  case schema
  case shares
  case streams
  case sync
  case validation
  case unknown(String)
}

public struct CLIInvocation: Equatable, Sendable {
  public var output: CLIOutputMode
  public var command: CLITopLevelCommand?
  public var arguments: [String]

  public init(
    output: CLIOutputMode,
    command: CLITopLevelCommand?,
    arguments: [String]
  ) {
    self.output = output
    self.command = command
    self.arguments = arguments
  }
}

public enum CLIExamplesInvocation: Equatable, Sendable {
  case todos(CLIExamplesTodosInvocation)
  case syncUps(arguments: [String])
  case reminders(arguments: [String])
  case todoLinks(arguments: [String])
  case unknown(String, arguments: [String])
}

public struct CLIExamplesTodosInvocation: Equatable, Sendable {
  public var command: CLIExamplesTodosCommand?
  public var arguments: [String]

  public init(
    command: CLIExamplesTodosCommand?,
    arguments: [String]
  ) {
    self.command = command
    self.arguments = arguments
  }
}

public enum CLIExamplesTodosCommand: Equatable, Sendable {
  case seed
  case add
  case list
  case watch
  case complete
  case update
  case delete
  case reset
  case refresh
  case unknown(String)
}

public enum CLIArgumentParseError: Error, Equatable, Sendable {
  case missingCommand
  case missingOutputFlag
}

public struct CLIOutputFlagParser: Parser {
  public init() {}

  public func parse(_ input: inout ArraySlice<String>) throws -> CLIOutputMode {
    guard let flag = input.first else {
      throw CLIArgumentParseError.missingOutputFlag
    }
    switch flag {
    case "--jsonl":
      input.removeFirst()
      return .jsonl
    case "--json":
      input.removeFirst()
      return .json
    default:
      throw CLIArgumentParseError.missingOutputFlag
    }
  }
}

public struct CLITopLevelCommandParser: Parser {
  public init() {}

  public func parse(_ input: inout ArraySlice<String>) throws -> CLITopLevelCommand {
    guard let command = input.first else {
      throw CLIArgumentParseError.missingCommand
    }
    input.removeFirst()
    return CLITopLevelCommand(command)
  }
}

public struct CLIInvocationParser: Parser {
  public init() {}

  public func parse(_ input: inout ArraySlice<String>) throws -> CLIInvocation {
    var arguments = Array(input)
    let output = CLIArguments.normalizeOutputMode(in: &arguments)
    var commandInput = arguments[...]
    let command = commandInput.isEmpty
      ? nil
      : try CLITopLevelCommandParser().parse(&commandInput)
    input.removeAll()
    return CLIInvocation(output: output, command: command, arguments: Array(commandInput))
  }
}

public struct CLIExamplesParser: Parser {
  public init() {}

  public func parse(_ input: inout ArraySlice<String>) throws -> CLIExamplesInvocation {
    guard let example = input.first else {
      throw CLIArgumentParseError.missingCommand
    }
    input.removeFirst()

    switch example {
    case "todos":
      return .todos(try CLIExamplesTodosParser().parse(&input))

    case "sync-ups", "syncups":
      let arguments = Array(input)
      input.removeAll()
      return .syncUps(arguments: arguments)

    case "reminders":
      let arguments = Array(input)
      input.removeAll()
      return .reminders(arguments: arguments)

    case "todo-links":
      let arguments = Array(input)
      input.removeAll()
      return .todoLinks(arguments: arguments)

    default:
      let arguments = Array(input)
      input.removeAll()
      return .unknown(example, arguments: arguments)
    }
  }
}

public struct CLIExamplesTodosParser: Parser {
  public init() {}

  public func parse(_ input: inout ArraySlice<String>) throws -> CLIExamplesTodosInvocation {
    let command = input.isEmpty ? nil : try CLIExamplesTodosCommandParser().parse(&input)
    let arguments = Array(input)
    input.removeAll()
    return CLIExamplesTodosInvocation(command: command, arguments: arguments)
  }
}

public struct CLIExamplesTodosCommandParser: Parser {
  public init() {}

  public func parse(_ input: inout ArraySlice<String>) throws -> CLIExamplesTodosCommand {
    guard let command = input.first else {
      throw CLIArgumentParseError.missingCommand
    }
    input.removeFirst()
    return CLIExamplesTodosCommand(command)
  }
}

public enum CLIArguments {
  public static func parse(_ arguments: [String]) throws -> CLIInvocation {
    var input = arguments[...]
    return try CLIInvocationParser().parse(&input)
  }

  public static func normalizeOutputMode(in arguments: inout [String]) -> CLIOutputMode {
    if let index = arguments.firstIndex(where: { token in
      parseOutputFlag(token) == .jsonl
    }) {
      arguments.remove(at: index)
      return .jsonl
    }
    if let index = arguments.firstIndex(where: { token in
      parseOutputFlag(token) == .json
    }) {
      arguments.remove(at: index)
      return .json
    }
    return .human
  }

  private static func parseOutputFlag(_ token: String) -> CLIOutputMode? {
    var input = [token][...]
    return try? CLIOutputFlagParser().parse(&input)
  }
}

extension CLITopLevelCommand {
  public init(_ rawValue: String) {
    switch rawValue {
    case "admin":
      self = .admin
    case "app":
      self = .app
    case "auth":
      self = .auth
    case "benchmark", "benchmarks":
      self = .benchmark
    case "cache":
      self = .cache
    case "connection", "connect":
      self = .connection
    case "examples":
      self = .examples
    case "files", "storage":
      self = .files
    case "help", "--help", "-h":
      self = .help
    case "init":
      self = .initScaffold
    case "local-id", "localid":
      self = .localID
    case "outbox":
      self = .outbox
    case "perms", "permissions":
      self = .permissions
    case "query":
      self = .query
    case "rooms", "room":
      self = .rooms
    case "schema":
      self = .schema
    case "shares", "share", "sharing":
      self = .shares
    case "streams", "stream":
      self = .streams
    case "sync":
      self = .sync
    case "validate", "validation":
      self = .validation
    default:
      self = .unknown(rawValue)
    }
  }
}

extension CLIExamplesTodosCommand {
  public init(_ rawValue: String) {
    switch rawValue {
    case "seed":
      self = .seed
    case "add":
      self = .add
    case "list":
      self = .list
    case "watch", "observe":
      self = .watch
    case "complete":
      self = .complete
    case "update", "edit":
      self = .update
    case "delete", "remove":
      self = .delete
    case "reset":
      self = .reset
    case "refresh":
      self = .refresh
    default:
      self = .unknown(rawValue)
    }
  }
}
