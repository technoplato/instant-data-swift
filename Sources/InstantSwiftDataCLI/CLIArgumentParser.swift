import Foundation
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

public enum CLIConnectionInvocation: Equatable, Sendable {
  case status
  case connect
  case close
}

public enum CLIConnectionUsage {
  public static let connection = """
    Usage: instant-swift-data connection <status|connect|close>
      instant-swift-data connection status [--json|--jsonl]
      instant-swift-data connection connect [--json|--jsonl]
      instant-swift-data connection close [--json|--jsonl]
    """

  public static let status = "Usage: instant-swift-data connection status [--json|--jsonl]"
  public static let connect = "Usage: instant-swift-data connection connect [--json|--jsonl]"
  public static let close = "Usage: instant-swift-data connection close [--json|--jsonl]"
}

public enum CLIConnectionArgumentError: Error, Equatable, Sendable {
  case missingCommand
  case unknownCommand(String)
  case unexpectedArgument(String, usage: String)

  public var exitCode: Int32 { 64 }
}

public enum CLILocalIDInvocation: Equatable, Sendable {
  case get(name: String)
  case list
}

public enum CLILocalIDUsage {
  public static let localID = """
    Usage: instant-swift-data local-id <get|list>
      instant-swift-data local-id get <name> [--json|--jsonl]
      instant-swift-data local-id list [--json|--jsonl]
    """

  public static let get = "Usage: instant-swift-data local-id get <name> [--json|--jsonl]"
  public static let list = "Usage: instant-swift-data local-id list [--json|--jsonl]"
}

public enum CLILocalIDArgumentError: Error, Equatable, Sendable {
  case missingCommand
  case unknownCommand(String)
  case missingArguments(usage: String)
  case unexpectedArgument(String, usage: String)

  public var exitCode: Int32 { 64 }
}

public enum CLIRoomsInvocation: Equatable, Sendable {
  case presence(CLIRoomPresenceInvocation)
  case topics(CLIRoomTopicsInvocation)
}

public enum CLIRoomPresenceInvocation: Equatable, Sendable {
  case set(CLIRoomPresenceSetInvocation)
  case list(CLIRoomIdentifier)
  case watch(CLIRoomPresenceWatchInvocation)
  case leave(CLIRoomPresenceLeaveInvocation)
}

public enum CLIRoomTopicsInvocation: Equatable, Sendable {
  case publish(CLIRoomTopicPublishInvocation)
  case list(CLIRoomTopicListInvocation)
  case watch(CLIRoomTopicWatchInvocation)
}

public struct CLIRoomIdentifier: Equatable, Sendable {
  public var type: String
  public var id: String

  public init(type: String, id: String) {
    self.type = type
    self.id = id
  }
}

public struct CLIRoomPresenceSetInvocation: Equatable, Sendable {
  public var room: CLIRoomIdentifier
  public var userID: String?
  public var values: [String]

  public var value: String {
    get { values.last ?? "" }
    set { values = [newValue] }
  }

  public init(room: CLIRoomIdentifier, userID: String? = nil, value: String) {
    self.init(room: room, userID: userID, values: [value])
  }

  public init(room: CLIRoomIdentifier, userID: String? = nil, values: [String]) {
    self.room = room
    self.userID = userID
    self.values = values
  }
}

public struct CLIRoomPresenceWatchInvocation: Equatable, Sendable {
  public var room: CLIRoomIdentifier
  public var eventCount: Int

  public init(room: CLIRoomIdentifier, eventCount: Int = 1) {
    self.room = room
    self.eventCount = eventCount
  }
}

public struct CLIRoomPresenceLeaveInvocation: Equatable, Sendable {
  public var room: CLIRoomIdentifier
  public var userID: String?

  public init(room: CLIRoomIdentifier, userID: String? = nil) {
    self.room = room
    self.userID = userID
  }
}

public struct CLIRoomTopicPublishInvocation: Equatable, Sendable {
  public var room: CLIRoomIdentifier
  public var topic: String
  public var userID: String?
  public var values: [String]

  public var value: String {
    get { values.last ?? "" }
    set { values = [newValue] }
  }

  public init(
    room: CLIRoomIdentifier,
    topic: String,
    userID: String? = nil,
    value: String
  ) {
    self.init(room: room, topic: topic, userID: userID, values: [value])
  }

  public init(
    room: CLIRoomIdentifier,
    topic: String,
    userID: String? = nil,
    values: [String]
  ) {
    self.room = room
    self.topic = topic
    self.userID = userID
    self.values = values
  }
}

public struct CLIRoomTopicListInvocation: Equatable, Sendable {
  public var room: CLIRoomIdentifier
  public var topic: String
  public var limit: Int?

  public init(room: CLIRoomIdentifier, topic: String, limit: Int? = nil) {
    self.room = room
    self.topic = topic
    self.limit = limit
  }
}

public struct CLIRoomTopicWatchInvocation: Equatable, Sendable {
  public var room: CLIRoomIdentifier
  public var topic: String
  public var eventCount: Int

  public init(room: CLIRoomIdentifier, topic: String, eventCount: Int = 1) {
    self.room = room
    self.topic = topic
    self.eventCount = eventCount
  }
}

public enum CLIRoomsUsage {
  public static let rooms = """
    Usage: instant-swift-data rooms <presence|topics>
      instant-swift-data rooms presence set <room-type> <room-id> --value '{...}' [--user-id id] [--json|--jsonl]
      instant-swift-data rooms presence list <room-type> <room-id> [--json|--jsonl]
      instant-swift-data rooms presence watch <room-type> <room-id> [--events 1] [--json|--jsonl]
      instant-swift-data rooms presence leave <room-type> <room-id> [--user-id id] [--json|--jsonl]
      instant-swift-data rooms topics publish <room-type> <room-id> <topic> --value '{...}' [--user-id id] [--json|--jsonl]
      instant-swift-data rooms topics list <room-type> <room-id> <topic> [--limit n] [--json|--jsonl]
      instant-swift-data rooms topics watch <room-type> <room-id> <topic> [--events 1] [--json|--jsonl]
    """

  public static let presence = """
    Usage: instant-swift-data rooms presence <set|list|watch|leave>
      instant-swift-data rooms presence set <room-type> <room-id> --value '{...}' [--user-id id] [--json|--jsonl]
      instant-swift-data rooms presence list <room-type> <room-id> [--json|--jsonl]
      instant-swift-data rooms presence watch <room-type> <room-id> [--events 1] [--json|--jsonl]
      instant-swift-data rooms presence leave <room-type> <room-id> [--user-id id] [--json|--jsonl]
    """

  public static let topics = """
    Usage: instant-swift-data rooms topics <publish|list|watch>
      instant-swift-data rooms topics publish <room-type> <room-id> <topic> --value '{...}' [--user-id id] [--json|--jsonl]
      instant-swift-data rooms topics list <room-type> <room-id> <topic> [--limit n] [--json|--jsonl]
      instant-swift-data rooms topics watch <room-type> <room-id> <topic> [--events 1] [--json|--jsonl]
    """
}

public enum CLIRoomsArgumentError: Error, Equatable, Sendable {
  case missingDomain
  case unknownDomain(String)
  case missingCommand(usage: String)
  case unknownCommand(command: String, usage: String)
  case missingArguments(usage: String)
  case missingValue(option: String, usage: String)
  case emptyValue(option: String, usage: String)
  case missingRequiredOption(option: String, usage: String)
  case invalidLimit(String, usage: String)
  case invalidEventCount(String, usageCommand: String)
  case unknownOption(domain: String, option: String, usage: String)
  case unexpectedArgument(String, usage: String)

  public var exitCode: Int32 { 64 }
}

public enum CLIAuthInvocation: Equatable, Sendable {
  case show
  case guest
  case token(CLIAuthTokenInvocation)
  case idToken(CLIAuthIDTokenInvocation)
  case oauth(CLIAuthOAuthInvocation)
  case oauthURL(CLIAuthOAuthURLInvocation)
  case issuer
  case magicCode(CLIAuthMagicCodeInvocation)
  case watch(CLIAuthWatchInvocation)
  case signOut(CLIAuthSignOutInvocation)
}

public struct CLIAuthTokenInvocation: Equatable, Sendable {
  public var refreshToken: String
  public var userID: String?

  public init(refreshToken: String, userID: String? = nil) {
    self.refreshToken = refreshToken
    self.userID = userID
  }
}

public struct CLIAuthIDTokenInvocation: Equatable, Sendable {
  public var clientName: String
  public var idToken: String
  public var nonce: String?

  public init(clientName: String, idToken: String, nonce: String? = nil) {
    self.clientName = clientName
    self.idToken = idToken
    self.nonce = nonce
  }
}

public struct CLIAuthOAuthInvocation: Equatable, Sendable {
  public var code: String
  public var codeVerifier: String?

  public init(code: String, codeVerifier: String? = nil) {
    self.code = code
    self.codeVerifier = codeVerifier
  }
}

public struct CLIAuthOAuthURLInvocation: Equatable, Sendable {
  public var clientName: String
  public var redirectURL: String

  public init(clientName: String, redirectURL: String) {
    self.clientName = clientName
    self.redirectURL = redirectURL
  }
}

public enum CLIAuthMagicCodeInvocation: Equatable, Sendable {
  case send(email: String)
  case verify(email: String, code: String)
}

public struct CLIAuthWatchInvocation: Equatable, Sendable {
  public var eventCount: Int

  public init(eventCount: Int = 1) {
    self.eventCount = eventCount
  }
}

public struct CLIAuthSignOutInvocation: Equatable, Sendable {
  public var invalidateToken: Bool

  public init(invalidateToken: Bool = true) {
    self.invalidateToken = invalidateToken
  }
}

public enum CLIAuthUsage {
  public static let auth = """
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

  public static let show = "Usage: instant-swift-data auth show [--json|--jsonl]"
  public static let guest = "Usage: instant-swift-data auth guest [--json|--jsonl]"
  public static let token =
    "Usage: instant-swift-data auth token <refresh-token> [--user-id id] [--json|--jsonl]"
  public static let idToken =
    "Usage: instant-swift-data auth id-token <client-name> <id-token> [--nonce nonce] [--json|--jsonl]"
  public static let oauth =
    "Usage: instant-swift-data auth oauth <code> [--code-verifier verifier] [--json|--jsonl]"
  public static let oauthURL =
    "Usage: instant-swift-data auth oauth-url <client-name> <redirect-url> [--json|--jsonl]"
  public static let issuer = "Usage: instant-swift-data auth issuer [--json|--jsonl]"
  public static let magicCode = """
    Usage: instant-swift-data auth magic-code <send|verify>
      instant-swift-data auth magic-code send <email> [--json|--jsonl]
      instant-swift-data auth magic-code verify <email> <code> [--json|--jsonl]
    """
  public static let magicCodeSend =
    "Usage: instant-swift-data auth magic-code send <email> [--json|--jsonl]"
  public static let magicCodeVerify =
    "Usage: instant-swift-data auth magic-code verify <email> <code> [--json|--jsonl]"
  public static let watch = "Usage: instant-swift-data auth watch [--events 1] [--json|--jsonl]"
  public static let signOut =
    "Usage: instant-swift-data auth sign-out [--skip-token-invalidation] [--json|--jsonl]"
}

public enum CLIAuthArgumentError: Error, Equatable, Sendable {
  case missingCommand
  case unknownCommand(String)
  case missingMagicCodeCommand
  case unknownMagicCodeCommand(String)
  case missingArguments(usage: String)
  case missingValue(option: String, usage: String)
  case emptyValue(option: String, usage: String)
  case invalidEventCount(String, usageCommand: String)
  case unknownOption(domain: String, option: String, usage: String)
  case unexpectedArgument(String, usage: String)

  public var exitCode: Int32 { 64 }
}

public enum CLIFilesInvocation: Equatable, Sendable {
  case upload(CLIFileUploadInvocation)
  case uploadProgress(CLIFileUploadInvocation)
  case list
  case watch(CLIFilesWatchInvocation)
  case read(fileID: String)
  case delete(fileID: String)
}

public struct CLIFileUploadInvocation: Equatable, Sendable {
  public var sourcePath: String
  public var name: String?
  public var contentType: String?

  public init(
    sourcePath: String,
    name: String? = nil,
    contentType: String? = nil
  ) {
    self.sourcePath = sourcePath
    self.name = name
    self.contentType = contentType
  }
}

public struct CLIFilesWatchInvocation: Equatable, Sendable {
  public var eventCount: Int

  public init(eventCount: Int = 1) {
    self.eventCount = eventCount
  }
}

public enum CLIFilesUsage {
  public static let files = """
    Usage: instant-swift-data files <upload|upload-progress|list|watch|read|delete>
      instant-swift-data files upload <path> [--name name] [--content-type type] [--json|--jsonl]
      instant-swift-data files upload-progress <path> [--name name] [--content-type type] [--json|--jsonl]
      instant-swift-data files list [--json|--jsonl]
      instant-swift-data files watch [--events 1] [--json|--jsonl]
      instant-swift-data files read <file-id> [--json|--jsonl]
      instant-swift-data files delete <file-id> [--json|--jsonl]
    """

  public static let upload =
    "Usage: instant-swift-data files upload <path> [--name name] [--content-type type] [--json|--jsonl]"
  public static let uploadProgress =
    "Usage: instant-swift-data files upload-progress <path> [--name name] [--content-type type] [--json|--jsonl]"
  public static let list = "Usage: instant-swift-data files list [--json|--jsonl]"
  public static let watch = "Usage: instant-swift-data files watch [--events 1] [--json|--jsonl]"
  public static let read = "Usage: instant-swift-data files read <file-id> [--json|--jsonl]"
  public static let delete = "Usage: instant-swift-data files delete <file-id> [--json|--jsonl]"
}

public enum CLIFilesArgumentError: Error, Equatable, Sendable {
  case missingCommand
  case unknownCommand(String)
  case missingArguments(usage: String)
  case missingValue(option: String, usage: String)
  case emptyValue(option: String, usage: String)
  case invalidEventCount(String, usageCommand: String)
  case unknownOption(domain: String, option: String, usage: String)
  case unexpectedArgument(String, usage: String)

  public var exitCode: Int32 { 64 }
}

public enum CLIStreamsInvocation: Equatable, Sendable {
  case append(CLIStreamAppendInvocation)
  case read(CLIStreamReadInvocation)
  case watch(CLIStreamWatchInvocation)
}

public struct CLIStreamAppendInvocation: Equatable, Sendable {
  public var streamID: String
  public var values: [String]

  public var value: String {
    get { values.last ?? "" }
    set { values = [newValue] }
  }

  public init(streamID: String, value: String) {
    self.init(streamID: streamID, values: [value])
  }

  public init(streamID: String, values: [String]) {
    self.streamID = streamID
    self.values = values
  }
}

public struct CLIStreamReadInvocation: Equatable, Sendable {
  public var streamID: String
  public var limit: Int?

  public init(streamID: String, limit: Int? = nil) {
    self.streamID = streamID
    self.limit = limit
  }
}

public struct CLIStreamWatchInvocation: Equatable, Sendable {
  public var streamID: String
  public var eventCount: Int

  public init(streamID: String, eventCount: Int = 1) {
    self.streamID = streamID
    self.eventCount = eventCount
  }
}

public enum CLIStreamsUsage {
  public static let streams = """
    Usage: instant-swift-data streams <append|read|watch>
      instant-swift-data streams append <stream-id> --value '{...}' [--json|--jsonl]
      instant-swift-data streams read <stream-id> [--limit n] [--json|--jsonl]
      instant-swift-data streams watch <stream-id> [--events 1] [--json|--jsonl]
    """

  public static let append =
    "Usage: instant-swift-data streams append <stream-id> --value '{...}' [--json|--jsonl]"
  public static let read =
    "Usage: instant-swift-data streams read <stream-id> [--limit n] [--json|--jsonl]"
  public static let watch =
    "Usage: instant-swift-data streams watch <stream-id> [--events 1] [--json|--jsonl]"
}

public enum CLIStreamsArgumentError: Error, Equatable, Sendable {
  case missingCommand
  case unknownCommand(String)
  case missingArguments(usage: String)
  case missingValue(option: String, usage: String)
  case missingRequiredOption(option: String, usage: String)
  case invalidLimit(String, usage: String)
  case invalidEventCount(String, usageCommand: String)
  case unknownOption(domain: String, option: String, usage: String)

  public var exitCode: Int32 { 64 }
}

public enum CLISharesInvocation: Equatable, Sendable {
  case create(CLISharesCreateInvocation)
  case list
  case accept(token: String)
  case role(CLISharesRoleInvocation)
  case revoke(shareID: String)
}

public struct CLISharesCreateInvocation: Equatable, Sendable {
  public var namespace: String
  public var entityID: String

  public init(namespace: String, entityID: String) {
    self.namespace = namespace
    self.entityID = entityID
  }
}

public struct CLISharesRoleInvocation: Equatable, Sendable {
  public var shareID: String
  public var userID: String
  public var role: CLIShareRole

  public init(shareID: String, userID: String, role: CLIShareRole) {
    self.shareID = shareID
    self.userID = userID
    self.role = role
  }
}

public enum CLIShareRole: String, Equatable, Sendable {
  case reader
  case writer
}

public enum CLISharesUsage {
  public static let shares = """
    Usage: instant-swift-data shares <create|list|accept|role|revoke>
      instant-swift-data shares create <namespace> <entity-id> [--json|--jsonl]
      instant-swift-data shares list [--json|--jsonl]
      instant-swift-data shares accept <token> [--json|--jsonl]
      instant-swift-data shares role <share-id> <user-id> <reader|writer> [--json|--jsonl]
      instant-swift-data shares revoke <share-id> [--json|--jsonl]
    """

  public static let create =
    "Usage: instant-swift-data shares create <namespace> <entity-id> [--json|--jsonl]"
  public static let list = "Usage: instant-swift-data shares list [--json|--jsonl]"
  public static let accept = "Usage: instant-swift-data shares accept <token> [--json|--jsonl]"
  public static let role =
    "Usage: instant-swift-data shares role <share-id> <user-id> <reader|writer> [--json|--jsonl]"
  public static let revoke = "Usage: instant-swift-data shares revoke <share-id> [--json|--jsonl]"
}

public enum CLISharesArgumentError: Error, Equatable, Sendable {
  case missingCommand
  case unknownCommand(String)
  case missingArguments(usage: String)
  case invalidRole(String, usage: String)
  case unexpectedArgument(String, usage: String)

  public var exitCode: Int32 { 64 }
}

public struct CLIBenchmarkInvocation: Equatable, Sendable {
  public static let defaultSuite = "local-todos"

  public var suite: String
  public var iterations: Int
  public var appID: String
  public var output: CLIOutputMode

  public init(
    suite: String = Self.defaultSuite,
    iterations: Int = 3,
    appID: String = "local-benchmark",
    output: CLIOutputMode = .json
  ) {
    self.suite = suite
    self.iterations = iterations
    self.appID = appID
    self.output = output
  }
}

public enum CLIArgumentParseError: Error, Equatable, Sendable {
  case missingCommand
  case missingOutputFlag
}

public enum CLIBenchmarkArgumentError: Error, Equatable, Sendable {
  case missingValue(option: String, usage: String)
  case invalidIterations(String, usage: String)
  case emptyAppID(usage: String)
  case unknownOption(String, usage: String)
  case help(usage: String)

  public var exitCode: Int32 {
    switch self {
    case .help:
      return 0
    case .emptyAppID, .invalidIterations, .missingValue, .unknownOption:
      return 64
    }
  }
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

public struct CLIConnectionParser: Parser {
  public init() {}

  public func parse(_ input: inout ArraySlice<String>) throws -> CLIConnectionInvocation {
    guard let command = input.first else {
      throw CLIConnectionArgumentError.missingCommand
    }
    input.removeFirst()

    switch command {
    case "inspect", "show", "status":
      try requireNoRemainingConnectionArguments(&input, usage: CLIConnectionUsage.status)
      return .status

    case "connect", "open":
      try requireNoRemainingConnectionArguments(&input, usage: CLIConnectionUsage.connect)
      return .connect

    case "close", "disconnect":
      try requireNoRemainingConnectionArguments(&input, usage: CLIConnectionUsage.close)
      return .close

    default:
      throw CLIConnectionArgumentError.unknownCommand(command)
    }
  }
}

public struct CLILocalIDParser: Parser {
  public init() {}

  public func parse(_ input: inout ArraySlice<String>) throws -> CLILocalIDInvocation {
    guard let command = input.first else {
      throw CLILocalIDArgumentError.missingCommand
    }
    input.removeFirst()

    switch command {
    case "get":
      let name = try parseRequiredLocalIDArgument(from: &input, usage: CLILocalIDUsage.get)
      try requireNoRemainingLocalIDArguments(&input, usage: CLILocalIDUsage.get)
      return .get(name: name)

    case "list", "ls":
      try requireNoRemainingLocalIDArguments(&input, usage: CLILocalIDUsage.list)
      return .list

    default:
      throw CLILocalIDArgumentError.unknownCommand(command)
    }
  }
}

public struct CLIRoomsParser: Parser {
  public init() {}

  public func parse(_ input: inout ArraySlice<String>) throws -> CLIRoomsInvocation {
    guard let domain = input.first else {
      throw CLIRoomsArgumentError.missingDomain
    }
    input.removeFirst()

    switch domain {
    case "presence":
      return .presence(try CLIRoomPresenceParser().parse(&input))

    case "topics", "topic":
      return .topics(try CLIRoomTopicsParser().parse(&input))

    default:
      throw CLIRoomsArgumentError.unknownDomain(domain)
    }
  }
}

public struct CLIRoomPresenceParser: Parser {
  public init() {}

  public func parse(_ input: inout ArraySlice<String>) throws -> CLIRoomPresenceInvocation {
    guard let command = input.first else {
      throw CLIRoomsArgumentError.missingCommand(usage: CLIRoomsUsage.presence)
    }
    input.removeFirst()

    switch command {
    case "set":
      return .set(try CLIRoomPresenceSetParser().parse(&input))

    case "list":
      let room = try CLIRoomIdentifierParser(usage: CLIRoomsUsage.presence).parse(&input)
      try requireNoRemainingArguments(&input, usage: CLIRoomsUsage.presence)
      return .list(room)

    case "watch":
      return .watch(try CLIRoomPresenceWatchParser().parse(&input))

    case "leave":
      return .leave(try CLIRoomPresenceLeaveParser().parse(&input))

    default:
      throw CLIRoomsArgumentError.unknownCommand(command: command, usage: CLIRoomsUsage.presence)
    }
  }
}

public struct CLIRoomTopicsParser: Parser {
  public init() {}

  public func parse(_ input: inout ArraySlice<String>) throws -> CLIRoomTopicsInvocation {
    guard let command = input.first else {
      throw CLIRoomsArgumentError.missingCommand(usage: CLIRoomsUsage.topics)
    }
    input.removeFirst()

    switch command {
    case "publish":
      return .publish(try CLIRoomTopicPublishParser().parse(&input))

    case "list":
      return .list(try CLIRoomTopicListParser().parse(&input))

    case "watch":
      return .watch(try CLIRoomTopicWatchParser().parse(&input))

    default:
      throw CLIRoomsArgumentError.unknownCommand(command: command, usage: CLIRoomsUsage.topics)
    }
  }
}

public struct CLIRoomPresenceSetParser: Parser {
  public init() {}

  public func parse(_ input: inout ArraySlice<String>) throws -> CLIRoomPresenceSetInvocation {
    let room = try CLIRoomIdentifierParser(usage: CLIRoomsUsage.presence).parse(&input)
    var userID: String?
    var values: [String] = []
    while let option = input.first {
      input.removeFirst()
      switch option {
      case "--user-id":
        userID = try parseNonEmptyOptionValue(
          from: &input,
          option: option,
          usage: CLIRoomsUsage.presence
        )

      case "--value":
        values.append(
          try parseOptionValue(from: &input, option: option, usage: CLIRoomsUsage.presence)
        )

      default:
        throw CLIRoomsArgumentError.unknownOption(
          domain: "rooms presence set",
          option: option,
          usage: CLIRoomsUsage.presence
        )
      }
    }
    guard !values.isEmpty else {
      throw CLIRoomsArgumentError.missingRequiredOption(
        option: "--value",
        usage: CLIRoomsUsage.presence
      )
    }
    return CLIRoomPresenceSetInvocation(room: room, userID: userID, values: values)
  }
}

public struct CLIRoomPresenceWatchParser: Parser {
  public init() {}

  public func parse(_ input: inout ArraySlice<String>) throws -> CLIRoomPresenceWatchInvocation {
    let room = try CLIRoomIdentifierParser(usage: CLIRoomsUsage.presence).parse(&input)
    let eventCount = try parseFiniteWatchEventCount(
      from: &input,
      usageCommand: "instant-swift-data rooms presence watch <room-type> <room-id>",
      domain: "rooms presence watch"
    )
    return CLIRoomPresenceWatchInvocation(room: room, eventCount: eventCount)
  }
}

public struct CLIRoomPresenceLeaveParser: Parser {
  public init() {}

  public func parse(_ input: inout ArraySlice<String>) throws -> CLIRoomPresenceLeaveInvocation {
    let room = try CLIRoomIdentifierParser(usage: CLIRoomsUsage.presence).parse(&input)
    var userID: String?
    while let option = input.first {
      input.removeFirst()
      switch option {
      case "--user-id":
        userID = try parseNonEmptyOptionValue(
          from: &input,
          option: option,
          usage: CLIRoomsUsage.presence
        )

      default:
        throw CLIRoomsArgumentError.unknownOption(
          domain: "rooms presence leave",
          option: option,
          usage: CLIRoomsUsage.presence
        )
      }
    }
    return CLIRoomPresenceLeaveInvocation(room: room, userID: userID)
  }
}

public struct CLIRoomTopicPublishParser: Parser {
  public init() {}

  public func parse(_ input: inout ArraySlice<String>) throws -> CLIRoomTopicPublishInvocation {
    let (room, topic) = try CLIRoomTopicHeadParser(usage: CLIRoomsUsage.topics).parse(&input)
    var userID: String?
    var values: [String] = []
    while let option = input.first {
      input.removeFirst()
      switch option {
      case "--user-id":
        userID = try parseNonEmptyOptionValue(
          from: &input,
          option: option,
          usage: CLIRoomsUsage.topics
        )

      case "--value":
        values.append(
          try parseOptionValue(from: &input, option: option, usage: CLIRoomsUsage.topics)
        )

      default:
        throw CLIRoomsArgumentError.unknownOption(
          domain: "rooms topics publish",
          option: option,
          usage: CLIRoomsUsage.topics
        )
      }
    }
    guard !values.isEmpty else {
      throw CLIRoomsArgumentError.missingRequiredOption(
        option: "--value",
        usage: CLIRoomsUsage.topics
      )
    }
    return CLIRoomTopicPublishInvocation(
      room: room,
      topic: topic,
      userID: userID,
      values: values
    )
  }
}

public struct CLIRoomTopicListParser: Parser {
  public init() {}

  public func parse(_ input: inout ArraySlice<String>) throws -> CLIRoomTopicListInvocation {
    let (room, topic) = try CLIRoomTopicHeadParser(usage: CLIRoomsUsage.topics).parse(&input)
    var limit: Int?
    while let option = input.first {
      input.removeFirst()
      switch option {
      case "--limit":
        let value = try parseOptionValue(from: &input, option: option, usage: CLIRoomsUsage.topics)
        guard let parsed = Int(value), parsed >= 0 else {
          throw CLIRoomsArgumentError.invalidLimit(value, usage: CLIRoomsUsage.topics)
        }
        limit = parsed

      default:
        throw CLIRoomsArgumentError.unknownOption(
          domain: "rooms topics list",
          option: option,
          usage: CLIRoomsUsage.topics
        )
      }
    }
    return CLIRoomTopicListInvocation(room: room, topic: topic, limit: limit)
  }
}

public struct CLIRoomTopicWatchParser: Parser {
  public init() {}

  public func parse(_ input: inout ArraySlice<String>) throws -> CLIRoomTopicWatchInvocation {
    let (room, topic) = try CLIRoomTopicHeadParser(usage: CLIRoomsUsage.topics).parse(&input)
    let eventCount = try parseFiniteWatchEventCount(
      from: &input,
      usageCommand: "instant-swift-data rooms topics watch <room-type> <room-id> <topic>",
      domain: "rooms topics watch"
    )
    return CLIRoomTopicWatchInvocation(room: room, topic: topic, eventCount: eventCount)
  }
}

public struct CLIAuthParser: Parser {
  public init() {}

  public func parse(_ input: inout ArraySlice<String>) throws -> CLIAuthInvocation {
    guard let command = input.first else {
      throw CLIAuthArgumentError.missingCommand
    }
    input.removeFirst()

    switch command {
    case "show", "status":
      try requireNoRemainingAuthArguments(&input, usage: CLIAuthUsage.show)
      return .show

    case "guest":
      try requireNoRemainingAuthArguments(&input, usage: CLIAuthUsage.guest)
      return .guest

    case "token":
      return .token(try CLIAuthTokenParser().parse(&input))

    case "id-token", "idtoken":
      return .idToken(try CLIAuthIDTokenParser().parse(&input))

    case "oauth":
      return .oauth(try CLIAuthOAuthParser().parse(&input))

    case "oauth-url", "authorization-url":
      return .oauthURL(try CLIAuthOAuthURLParser().parse(&input))

    case "issuer", "issuer-uri":
      try requireNoRemainingAuthArguments(&input, usage: CLIAuthUsage.issuer)
      return .issuer

    case "magic-code", "magic":
      return .magicCode(try CLIAuthMagicCodeParser().parse(&input))

    case "watch", "observe":
      return .watch(try CLIAuthWatchParser().parse(&input))

    case "sign-out", "signout", "logout":
      return .signOut(try CLIAuthSignOutParser().parse(&input))

    default:
      throw CLIAuthArgumentError.unknownCommand(command)
    }
  }
}

public struct CLIAuthTokenParser: Parser {
  public init() {}

  public func parse(_ input: inout ArraySlice<String>) throws -> CLIAuthTokenInvocation {
    let refreshToken = try parseRawAuthArgument(from: &input, usage: CLIAuthUsage.token)
    var userID: String?

    while let option = input.first {
      input.removeFirst()
      switch option {
      case "--user-id":
        userID = try parseNonEmptyAuthOptionValue(
          from: &input,
          option: option,
          usage: CLIAuthUsage.token
        )

      default:
        throw CLIAuthArgumentError.unknownOption(
          domain: "auth token",
          option: option,
          usage: CLIAuthUsage.token
        )
      }
    }

    return CLIAuthTokenInvocation(refreshToken: refreshToken, userID: userID)
  }
}

public struct CLIAuthIDTokenParser: Parser {
  public init() {}

  public func parse(_ input: inout ArraySlice<String>) throws -> CLIAuthIDTokenInvocation {
    let clientName = try parseRawAuthArgument(from: &input, usage: CLIAuthUsage.idToken)
    let idToken = try parseRawAuthArgument(from: &input, usage: CLIAuthUsage.idToken)
    var nonce: String?

    while let option = input.first {
      input.removeFirst()
      switch option {
      case "--nonce":
        nonce = try parseNonEmptyAuthOptionValue(
          from: &input,
          option: option,
          usage: CLIAuthUsage.idToken
        )

      default:
        throw CLIAuthArgumentError.unknownOption(
          domain: "auth id-token",
          option: option,
          usage: CLIAuthUsage.idToken
        )
      }
    }

    return CLIAuthIDTokenInvocation(clientName: clientName, idToken: idToken, nonce: nonce)
  }
}

public struct CLIAuthOAuthParser: Parser {
  public init() {}

  public func parse(_ input: inout ArraySlice<String>) throws -> CLIAuthOAuthInvocation {
    let code = try parseRawAuthArgument(from: &input, usage: CLIAuthUsage.oauth)
    var codeVerifier: String?

    while let option = input.first {
      input.removeFirst()
      switch option {
      case "--code-verifier":
        codeVerifier = try parseNonEmptyAuthOptionValue(
          from: &input,
          option: option,
          usage: CLIAuthUsage.oauth
        )

      default:
        throw CLIAuthArgumentError.unknownOption(
          domain: "auth oauth",
          option: option,
          usage: CLIAuthUsage.oauth
        )
      }
    }

    return CLIAuthOAuthInvocation(code: code, codeVerifier: codeVerifier)
  }
}

public struct CLIAuthOAuthURLParser: Parser {
  public init() {}

  public func parse(_ input: inout ArraySlice<String>) throws -> CLIAuthOAuthURLInvocation {
    let clientName = try parseRawAuthArgument(from: &input, usage: CLIAuthUsage.oauthURL)
    let redirectURL = try parseRawAuthArgument(from: &input, usage: CLIAuthUsage.oauthURL)
    try requireNoRemainingAuthArguments(&input, usage: CLIAuthUsage.oauthURL)
    return CLIAuthOAuthURLInvocation(clientName: clientName, redirectURL: redirectURL)
  }
}

public struct CLIAuthMagicCodeParser: Parser {
  public init() {}

  public func parse(_ input: inout ArraySlice<String>) throws -> CLIAuthMagicCodeInvocation {
    guard let command = input.first else {
      throw CLIAuthArgumentError.missingMagicCodeCommand
    }
    input.removeFirst()

    switch command {
    case "send":
      let email = try parseRawAuthArgument(from: &input, usage: CLIAuthUsage.magicCodeSend)
      try requireNoRemainingAuthArguments(&input, usage: CLIAuthUsage.magicCodeSend)
      return .send(email: email)

    case "verify":
      let email = try parseRawAuthArgument(from: &input, usage: CLIAuthUsage.magicCodeVerify)
      let code = try parseRawAuthArgument(from: &input, usage: CLIAuthUsage.magicCodeVerify)
      try requireNoRemainingAuthArguments(&input, usage: CLIAuthUsage.magicCodeVerify)
      return .verify(email: email, code: code)

    default:
      throw CLIAuthArgumentError.unknownMagicCodeCommand(command)
    }
  }
}

public struct CLIAuthWatchParser: Parser {
  public init() {}

  public func parse(_ input: inout ArraySlice<String>) throws -> CLIAuthWatchInvocation {
    CLIAuthWatchInvocation(eventCount: try parseAuthFiniteWatchEventCount(from: &input))
  }
}

public struct CLIAuthSignOutParser: Parser {
  public init() {}

  public func parse(_ input: inout ArraySlice<String>) throws -> CLIAuthSignOutInvocation {
    var invalidateToken = true

    while let option = input.first {
      input.removeFirst()
      switch option {
      case "--invalidate-token":
        invalidateToken = true

      case "--skip-token-invalidation", "--no-invalidate-token":
        invalidateToken = false

      default:
        throw CLIAuthArgumentError.unknownOption(
          domain: "auth sign-out",
          option: option,
          usage: CLIAuthUsage.signOut
        )
      }
    }

    return CLIAuthSignOutInvocation(invalidateToken: invalidateToken)
  }
}

public struct CLIFilesParser: Parser {
  public init() {}

  public func parse(_ input: inout ArraySlice<String>) throws -> CLIFilesInvocation {
    guard let command = input.first else {
      throw CLIFilesArgumentError.missingCommand
    }
    input.removeFirst()

    switch command {
    case "upload", "put":
      return .upload(try CLIFileUploadParser(usage: CLIFilesUsage.upload).parse(&input))

    case "upload-progress", "progress":
      return .uploadProgress(
        try CLIFileUploadParser(usage: CLIFilesUsage.uploadProgress).parse(&input)
      )

    case "list", "ls":
      try requireNoRemainingFileArguments(&input, usage: CLIFilesUsage.list)
      return .list

    case "watch":
      return .watch(try CLIFilesWatchParser().parse(&input))

    case "read", "cat":
      return .read(
        fileID: try parseSingleFileArgument(from: &input, usage: CLIFilesUsage.read)
      )

    case "delete", "rm":
      return .delete(
        fileID: try parseSingleFileArgument(from: &input, usage: CLIFilesUsage.delete)
      )

    default:
      throw CLIFilesArgumentError.unknownCommand(command)
    }
  }
}

public struct CLIFileUploadParser: Parser {
  public var usage: String

  public init(usage: String) {
    self.usage = usage
  }

  public func parse(_ input: inout ArraySlice<String>) throws -> CLIFileUploadInvocation {
    let sourcePath = try parseRequiredFilePath(from: &input, usage: usage)
    var name: String?
    var contentType: String?

    while let option = input.first {
      input.removeFirst()
      switch option {
      case "--name":
        name = try parseNonEmptyFileOptionValue(
          from: &input,
          option: option,
          usage: usage
        )

      case "--content-type":
        contentType = try parseNonEmptyFileOptionValue(
          from: &input,
          option: option,
          usage: usage
        )

      default:
        throw CLIFilesArgumentError.unknownOption(
          domain: "files upload",
          option: option,
          usage: CLIFilesUsage.files
        )
      }
    }

    return CLIFileUploadInvocation(
      sourcePath: sourcePath,
      name: name,
      contentType: contentType
    )
  }
}

public struct CLIFilesWatchParser: Parser {
  public init() {}

  public func parse(_ input: inout ArraySlice<String>) throws -> CLIFilesWatchInvocation {
    CLIFilesWatchInvocation(eventCount: try parseFilesFiniteWatchEventCount(from: &input))
  }
}

public struct CLIStreamsParser: Parser {
  public init() {}

  public func parse(_ input: inout ArraySlice<String>) throws -> CLIStreamsInvocation {
    guard let command = input.first else {
      throw CLIStreamsArgumentError.missingCommand
    }
    input.removeFirst()

    switch command {
    case "append", "write":
      return .append(try CLIStreamAppendParser().parse(&input))

    case "read", "list":
      return .read(try CLIStreamReadParser().parse(&input))

    case "watch":
      return .watch(try CLIStreamWatchParser().parse(&input))

    default:
      throw CLIStreamsArgumentError.unknownCommand(command)
    }
  }
}

public struct CLIStreamAppendParser: Parser {
  public init() {}

  public func parse(_ input: inout ArraySlice<String>) throws -> CLIStreamAppendInvocation {
    let streamID = try parseRequiredStreamArgument(from: &input, usage: CLIStreamsUsage.append)
    var values: [String] = []
    while let option = input.first {
      input.removeFirst()
      switch option {
      case "--value":
        values.append(
          try parseStreamOptionValue(from: &input, option: option, usage: CLIStreamsUsage.append)
        )

      default:
        throw CLIStreamsArgumentError.unknownOption(
          domain: "streams append",
          option: option,
          usage: CLIStreamsUsage.streams
        )
      }
    }
    guard !values.isEmpty else {
      throw CLIStreamsArgumentError.missingRequiredOption(
        option: "--value",
        usage: CLIStreamsUsage.append
      )
    }
    return CLIStreamAppendInvocation(streamID: streamID, values: values)
  }
}

public struct CLIStreamReadParser: Parser {
  public init() {}

  public func parse(_ input: inout ArraySlice<String>) throws -> CLIStreamReadInvocation {
    let streamID = try parseRequiredStreamArgument(from: &input, usage: CLIStreamsUsage.read)
    var limit: Int?
    while let option = input.first {
      input.removeFirst()
      switch option {
      case "--limit":
        let value = try parseStreamOptionValue(
          from: &input,
          option: option,
          usage: CLIStreamsUsage.read
        )
        guard let parsed = Int(value), parsed >= 0 else {
          throw CLIStreamsArgumentError.invalidLimit(value, usage: CLIStreamsUsage.read)
        }
        limit = parsed

      default:
        throw CLIStreamsArgumentError.unknownOption(
          domain: "streams read",
          option: option,
          usage: CLIStreamsUsage.read
        )
      }
    }
    return CLIStreamReadInvocation(streamID: streamID, limit: limit)
  }
}

public struct CLIStreamWatchParser: Parser {
  public init() {}

  public func parse(_ input: inout ArraySlice<String>) throws -> CLIStreamWatchInvocation {
    let streamID = try parseRequiredStreamArgument(from: &input, usage: CLIStreamsUsage.watch)
    let eventCount = try parseStreamFiniteWatchEventCount(from: &input)
    return CLIStreamWatchInvocation(streamID: streamID, eventCount: eventCount)
  }
}

public struct CLISharesParser: Parser {
  public init() {}

  public func parse(_ input: inout ArraySlice<String>) throws -> CLISharesInvocation {
    guard let command = input.first else {
      throw CLISharesArgumentError.missingCommand
    }
    input.removeFirst()

    switch command {
    case "create":
      return .create(try CLISharesCreateParser().parse(&input))

    case "list", "ls":
      try requireNoRemainingShareArguments(&input, usage: CLISharesUsage.list)
      return .list

    case "accept":
      return .accept(
        token: try parseSingleShareArgument(
          from: &input,
          usage: CLISharesUsage.accept
        )
      )

    case "role":
      return .role(try CLISharesRoleParser().parse(&input))

    case "revoke":
      return .revoke(
        shareID: try parseSingleShareArgument(
          from: &input,
          usage: CLISharesUsage.revoke
        )
      )

    default:
      throw CLISharesArgumentError.unknownCommand(command)
    }
  }
}

public struct CLISharesCreateParser: Parser {
  public init() {}

  public func parse(_ input: inout ArraySlice<String>) throws -> CLISharesCreateInvocation {
    let namespace = try parseRequiredShareArgument(from: &input, usage: CLISharesUsage.create)
    let entityID = try parseRequiredShareArgument(from: &input, usage: CLISharesUsage.create)
    try requireNoRemainingShareArguments(&input, usage: CLISharesUsage.create)
    return CLISharesCreateInvocation(namespace: namespace, entityID: entityID)
  }
}

public struct CLISharesRoleParser: Parser {
  public init() {}

  public func parse(_ input: inout ArraySlice<String>) throws -> CLISharesRoleInvocation {
    let shareID = try parseRequiredShareArgument(from: &input, usage: CLISharesUsage.role)
    let userID = try parseRequiredShareArgument(from: &input, usage: CLISharesUsage.role)
    let roleValue = try parseRequiredShareArgument(from: &input, usage: CLISharesUsage.role)
    guard let role = CLIShareRole(rawValue: roleValue.lowercased()) else {
      throw CLISharesArgumentError.invalidRole(roleValue, usage: CLISharesUsage.role)
    }
    try requireNoRemainingShareArguments(&input, usage: CLISharesUsage.role)
    return CLISharesRoleInvocation(shareID: shareID, userID: userID, role: role)
  }
}

public struct CLIRoomIdentifierParser: Parser {
  public var usage: String

  public init(usage: String) {
    self.usage = usage
  }

  public func parse(_ input: inout ArraySlice<String>) throws -> CLIRoomIdentifier {
    guard let roomType = input.first else {
      throw CLIRoomsArgumentError.missingArguments(usage: usage)
    }
    input.removeFirst()
    guard let roomID = input.first else {
      throw CLIRoomsArgumentError.missingArguments(usage: usage)
    }
    input.removeFirst()
    return CLIRoomIdentifier(type: trimmed(roomType), id: trimmed(roomID))
  }
}

public struct CLIRoomTopicHeadParser: Parser {
  public var usage: String

  public init(usage: String) {
    self.usage = usage
  }

  public func parse(_ input: inout ArraySlice<String>) throws -> (CLIRoomIdentifier, String) {
    let room = try CLIRoomIdentifierParser(usage: usage).parse(&input)
    guard let topic = input.first else {
      throw CLIRoomsArgumentError.missingArguments(usage: usage)
    }
    input.removeFirst()
    return (room, trimmed(topic))
  }
}

public struct CLIBenchmarkParser: Parser {
  public var defaultAppID: String
  public var allowsOutputFlags: Bool
  public var usageCommand: String

  public init(
    defaultAppID: String = "local-benchmark",
    allowsOutputFlags: Bool = true,
    usageCommand: String = "instant-swift-data benchmark"
  ) {
    self.defaultAppID = defaultAppID
    self.allowsOutputFlags = allowsOutputFlags
    self.usageCommand = usageCommand
  }

  public func parse(_ input: inout ArraySlice<String>) throws -> CLIBenchmarkInvocation {
    var invocation = CLIBenchmarkInvocation(appID: normalizedDefaultAppID)

    while let option = input.first {
      input.removeFirst()
      switch option {
      case "--suite":
        guard let value = takeValue(from: &input), !value.isEmpty else {
          throw CLIBenchmarkArgumentError.missingValue(option: option, usage: usage)
        }
        invocation.suite = value

      case "--iterations":
        guard let value = takeValue(from: &input) else {
          throw CLIBenchmarkArgumentError.missingValue(option: option, usage: usage)
        }
        guard let iterations = Int(value), iterations > 0 else {
          throw CLIBenchmarkArgumentError.invalidIterations(value, usage: usage)
        }
        invocation.iterations = iterations

      case "--app-id":
        guard let value = takeValue(from: &input) else {
          throw CLIBenchmarkArgumentError.missingValue(option: option, usage: usage)
        }
        let appID = trimmed(value)
        guard !appID.isEmpty else {
          throw CLIBenchmarkArgumentError.emptyAppID(usage: usage)
        }
        invocation.appID = appID

      case "--json":
        guard allowsOutputFlags else {
          throw CLIBenchmarkArgumentError.unknownOption(option, usage: usage)
        }
        invocation.output = .json

      case "--jsonl":
        guard allowsOutputFlags else {
          throw CLIBenchmarkArgumentError.unknownOption(option, usage: usage)
        }
        invocation.output = .jsonl

      case "help", "--help", "-h":
        throw CLIBenchmarkArgumentError.help(usage: usage)

      default:
        throw CLIBenchmarkArgumentError.unknownOption(option, usage: usage)
      }
    }

    return invocation
  }

  private var normalizedDefaultAppID: String {
    let appID = trimmed(defaultAppID)
    return appID.isEmpty ? "local-benchmark" : appID
  }

  private var usage: String {
    "Usage: \(usageCommand) [--suite local-todos] [--iterations n] [--app-id id] [--json|--jsonl]"
  }

  private func takeValue(
    from input: inout ArraySlice<String>
  ) -> String? {
    guard let value = input.first else { return nil }
    input.removeFirst()
    return value
  }

  private func trimmed(_ string: String) -> String {
    string.trimmingCharacters(in: .whitespacesAndNewlines)
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

public enum CLIBenchmarkArguments {
  public static func parse(
    _ arguments: [String],
    defaultAppID: String = "local-benchmark",
    allowsOutputFlags: Bool = true,
    usageCommand: String = "instant-swift-data benchmark"
  ) throws -> CLIBenchmarkInvocation {
    var input = arguments[...]
    return try CLIBenchmarkParser(
      defaultAppID: defaultAppID,
      allowsOutputFlags: allowsOutputFlags,
      usageCommand: usageCommand
    )
    .parse(&input)
  }
}

private func parseOptionValue(
  from input: inout ArraySlice<String>,
  option: String,
  usage: String
) throws -> String {
  guard let value = input.first else {
    throw CLIRoomsArgumentError.missingValue(option: option, usage: usage)
  }
  input.removeFirst()
  return value
}

private func parseNonEmptyOptionValue(
  from input: inout ArraySlice<String>,
  option: String,
  usage: String
) throws -> String {
  let value = try parseOptionValue(from: &input, option: option, usage: usage)
  let trimmedValue = trimmed(value)
  guard !trimmedValue.isEmpty else {
    throw CLIRoomsArgumentError.emptyValue(option: option, usage: usage)
  }
  return trimmedValue
}

private func parseFiniteWatchEventCount(
  from input: inout ArraySlice<String>,
  usageCommand: String,
  domain: String
) throws -> Int {
  var eventCount = 1
  while let option = input.first {
    input.removeFirst()
    switch option {
    case "--events":
      let value = try parseOptionValue(
        from: &input,
        option: option,
        usage: "Usage: \(usageCommand) --events 1"
      )
      guard let parsed = Int(value), parsed == 1 else {
        throw CLIRoomsArgumentError.invalidEventCount(value, usageCommand: usageCommand)
      }
      eventCount = parsed

    default:
      throw CLIRoomsArgumentError.unknownOption(
        domain: domain,
        option: option,
        usage: "Usage: \(usageCommand) [--events 1] [--json|--jsonl]"
      )
    }
  }
  return eventCount
}

private func requireNoRemainingArguments(
  _ input: inout ArraySlice<String>,
  usage: String
) throws {
  if let argument = input.first {
    throw CLIRoomsArgumentError.unexpectedArgument(argument, usage: usage)
  }
}

private func parseRawAuthArgument(
  from input: inout ArraySlice<String>,
  usage: String
) throws -> String {
  guard let value = input.first else {
    throw CLIAuthArgumentError.missingArguments(usage: usage)
  }
  input.removeFirst()
  return value
}

private func parseAuthOptionValue(
  from input: inout ArraySlice<String>,
  option: String,
  usage: String
) throws -> String {
  guard let value = input.first else {
    throw CLIAuthArgumentError.missingValue(option: option, usage: usage)
  }
  input.removeFirst()
  return value
}

private func parseNonEmptyAuthOptionValue(
  from input: inout ArraySlice<String>,
  option: String,
  usage: String
) throws -> String {
  let value = try parseAuthOptionValue(from: &input, option: option, usage: usage)
  guard !trimmed(value).isEmpty else {
    throw CLIAuthArgumentError.emptyValue(option: option, usage: usage)
  }
  return value
}

private func parseAuthFiniteWatchEventCount(
  from input: inout ArraySlice<String>
) throws -> Int {
  let usageCommand = "instant-swift-data auth watch"
  var eventCount = 1
  while let option = input.first {
    input.removeFirst()
    switch option {
    case "--events":
      let value = try parseAuthOptionValue(
        from: &input,
        option: option,
        usage: "Usage: \(usageCommand) --events 1"
      )
      guard let parsed = Int(value), parsed == 1 else {
        throw CLIAuthArgumentError.invalidEventCount(value, usageCommand: usageCommand)
      }
      eventCount = parsed

    default:
      throw CLIAuthArgumentError.unknownOption(
        domain: "auth watch",
        option: option,
        usage: CLIAuthUsage.watch
      )
    }
  }
  return eventCount
}

private func requireNoRemainingAuthArguments(
  _ input: inout ArraySlice<String>,
  usage: String
) throws {
  if let argument = input.first {
    throw CLIAuthArgumentError.unexpectedArgument(argument, usage: usage)
  }
}

private func parseSingleFileArgument(
  from input: inout ArraySlice<String>,
  usage: String
) throws -> String {
  let value = try parseRequiredFileArgument(from: &input, usage: usage)
  try requireNoRemainingFileArguments(&input, usage: usage)
  return value
}

private func parseRequiredFilePath(
  from input: inout ArraySlice<String>,
  usage: String
) throws -> String {
  guard let value = input.first else {
    throw CLIFilesArgumentError.missingArguments(usage: usage)
  }
  input.removeFirst()
  guard !trimmed(value).isEmpty else {
    throw CLIFilesArgumentError.missingArguments(usage: usage)
  }
  return value
}

private func parseRequiredFileArgument(
  from input: inout ArraySlice<String>,
  usage: String
) throws -> String {
  guard let value = input.first else {
    throw CLIFilesArgumentError.missingArguments(usage: usage)
  }
  input.removeFirst()
  let parsed = trimmed(value)
  guard !parsed.isEmpty else {
    throw CLIFilesArgumentError.missingArguments(usage: usage)
  }
  return parsed
}

private func parseFileOptionValue(
  from input: inout ArraySlice<String>,
  option: String,
  usage: String
) throws -> String {
  guard let value = input.first else {
    throw CLIFilesArgumentError.missingValue(option: option, usage: usage)
  }
  input.removeFirst()
  return value
}

private func parseNonEmptyFileOptionValue(
  from input: inout ArraySlice<String>,
  option: String,
  usage: String
) throws -> String {
  let value = try parseFileOptionValue(from: &input, option: option, usage: usage)
  let parsed = trimmed(value)
  guard !parsed.isEmpty else {
    throw CLIFilesArgumentError.emptyValue(option: option, usage: usage)
  }
  return parsed
}

private func parseFilesFiniteWatchEventCount(
  from input: inout ArraySlice<String>
) throws -> Int {
  let usageCommand = "instant-swift-data files watch"
  var eventCount = 1
  while let option = input.first {
    input.removeFirst()
    switch option {
    case "--events":
      let value = try parseFileOptionValue(
        from: &input,
        option: option,
        usage: "Usage: \(usageCommand) --events 1"
      )
      guard let parsed = Int(value), parsed == 1 else {
        throw CLIFilesArgumentError.invalidEventCount(value, usageCommand: usageCommand)
      }
      eventCount = parsed

    default:
      throw CLIFilesArgumentError.unknownOption(
        domain: "files watch",
        option: option,
        usage: CLIFilesUsage.watch
      )
    }
  }
  return eventCount
}

private func requireNoRemainingFileArguments(
  _ input: inout ArraySlice<String>,
  usage: String
) throws {
  if let argument = input.first {
    throw CLIFilesArgumentError.unexpectedArgument(argument, usage: usage)
  }
}

private func parseRequiredStreamArgument(
  from input: inout ArraySlice<String>,
  usage: String
) throws -> String {
  guard let value = input.first else {
    throw CLIStreamsArgumentError.missingArguments(usage: usage)
  }
  input.removeFirst()
  let parsed = trimmed(value)
  guard !parsed.isEmpty else {
    throw CLIStreamsArgumentError.missingArguments(usage: usage)
  }
  return parsed
}

private func parseStreamOptionValue(
  from input: inout ArraySlice<String>,
  option: String,
  usage: String
) throws -> String {
  guard let value = input.first else {
    throw CLIStreamsArgumentError.missingValue(option: option, usage: usage)
  }
  input.removeFirst()
  return value
}

private func parseStreamFiniteWatchEventCount(
  from input: inout ArraySlice<String>
) throws -> Int {
  let usageCommand = "instant-swift-data streams watch <stream-id>"
  var eventCount = 1
  while let option = input.first {
    input.removeFirst()
    switch option {
    case "--events":
      let value = try parseStreamOptionValue(
        from: &input,
        option: option,
        usage: "Usage: \(usageCommand) --events 1"
      )
      guard let parsed = Int(value), parsed == 1 else {
        throw CLIStreamsArgumentError.invalidEventCount(value, usageCommand: usageCommand)
      }
      eventCount = parsed

    default:
      throw CLIStreamsArgumentError.unknownOption(
        domain: "streams watch",
        option: option,
        usage: CLIStreamsUsage.watch
      )
    }
  }
  return eventCount
}

private func parseSingleShareArgument(
  from input: inout ArraySlice<String>,
  usage: String
) throws -> String {
  let value = try parseRequiredShareArgument(from: &input, usage: usage)
  try requireNoRemainingShareArguments(&input, usage: usage)
  return value
}

private func parseRequiredShareArgument(
  from input: inout ArraySlice<String>,
  usage: String
) throws -> String {
  guard let value = input.first else {
    throw CLISharesArgumentError.missingArguments(usage: usage)
  }
  input.removeFirst()
  let parsed = trimmed(value)
  guard !parsed.isEmpty else {
    throw CLISharesArgumentError.missingArguments(usage: usage)
  }
  return parsed
}

private func requireNoRemainingShareArguments(
  _ input: inout ArraySlice<String>,
  usage: String
) throws {
  if let argument = input.first {
    throw CLISharesArgumentError.unexpectedArgument(argument, usage: usage)
  }
}

private func requireNoRemainingConnectionArguments(
  _ input: inout ArraySlice<String>,
  usage: String
) throws {
  if let argument = input.first {
    throw CLIConnectionArgumentError.unexpectedArgument(argument, usage: usage)
  }
}

private func parseRequiredLocalIDArgument(
  from input: inout ArraySlice<String>,
  usage: String
) throws -> String {
  guard let value = input.first else {
    throw CLILocalIDArgumentError.missingArguments(usage: usage)
  }
  input.removeFirst()
  guard !trimmed(value).isEmpty else {
    throw CLILocalIDArgumentError.missingArguments(usage: usage)
  }
  return value
}

private func requireNoRemainingLocalIDArguments(
  _ input: inout ArraySlice<String>,
  usage: String
) throws {
  if let argument = input.first {
    throw CLILocalIDArgumentError.unexpectedArgument(argument, usage: usage)
  }
}

private func trimmed(_ string: String) -> String {
  string.trimmingCharacters(in: .whitespacesAndNewlines)
}

extension CLIConnectionArgumentError: CustomStringConvertible {
  public var description: String {
    switch self {
    case .missingCommand:
      return CLIConnectionUsage.connection

    case .unknownCommand:
      return CLIConnectionUsage.connection

    case let .unexpectedArgument(argument, usage):
      return "Unexpected argument: \(argument). \(usage)"
    }
  }
}

extension CLILocalIDArgumentError: CustomStringConvertible {
  public var description: String {
    switch self {
    case .missingCommand:
      return CLILocalIDUsage.localID

    case .unknownCommand:
      return CLILocalIDUsage.localID

    case let .missingArguments(usage):
      return usage

    case let .unexpectedArgument(argument, usage):
      return "Unexpected argument: \(argument). \(usage)"
    }
  }
}

extension CLIRoomsArgumentError: CustomStringConvertible {
  public var description: String {
    switch self {
    case .missingDomain:
      return CLIRoomsUsage.rooms

    case .unknownDomain:
      return CLIRoomsUsage.rooms

    case let .missingCommand(usage):
      return usage

    case let .unknownCommand(_, usage):
      return usage

    case let .missingArguments(usage):
      return usage

    case let .missingValue(option, usage):
      return "Missing value for \(option). \(usage)"

    case let .emptyValue(option, usage):
      return "Missing non-empty value for \(option). \(usage)"

    case let .missingRequiredOption(option, usage):
      return "Missing required option \(option). \(usage)"

    case let .invalidLimit(value, usage):
      return "Invalid --limit value: \(value). \(usage)"

    case let .invalidEventCount(_, usageCommand):
      return "Usage: \(usageCommand) --events 1"

    case let .unknownOption(domain, option, usage):
      return "Unknown \(domain) option: \(option). \(usage)"

    case let .unexpectedArgument(argument, usage):
      return "Unexpected argument: \(argument). \(usage)"
    }
  }
}

extension CLIAuthArgumentError: CustomStringConvertible {
  public var description: String {
    switch self {
    case .missingCommand:
      return CLIAuthUsage.auth

    case .unknownCommand:
      return CLIAuthUsage.auth

    case .missingMagicCodeCommand:
      return CLIAuthUsage.magicCode

    case .unknownMagicCodeCommand:
      return CLIAuthUsage.magicCode

    case let .missingArguments(usage):
      return usage

    case let .missingValue(option, usage):
      return "Missing value for \(option). \(usage)"

    case let .emptyValue(option, usage):
      return "Missing non-empty value for \(option). \(usage)"

    case let .invalidEventCount(_, usageCommand):
      return "Usage: \(usageCommand) --events 1"

    case let .unknownOption(domain, option, usage):
      return "Unknown \(domain) option: \(option). \(usage)"

    case let .unexpectedArgument(argument, usage):
      return "Unexpected argument: \(argument). \(usage)"
    }
  }
}

extension CLIFilesArgumentError: CustomStringConvertible {
  public var description: String {
    switch self {
    case .missingCommand:
      return CLIFilesUsage.files

    case .unknownCommand:
      return CLIFilesUsage.files

    case let .missingArguments(usage):
      return usage

    case let .missingValue(option, usage):
      return "Missing value for \(option). \(usage)"

    case let .emptyValue(option, usage):
      return "Missing non-empty value for \(option). \(usage)"

    case let .invalidEventCount(_, usageCommand):
      return "Usage: \(usageCommand) --events 1"

    case let .unknownOption(domain, option, usage):
      return "Unknown \(domain) option: \(option). \(usage)"

    case let .unexpectedArgument(argument, usage):
      return "Unexpected argument: \(argument). \(usage)"
    }
  }
}

extension CLIStreamsArgumentError: CustomStringConvertible {
  public var description: String {
    switch self {
    case .missingCommand:
      return CLIStreamsUsage.streams

    case .unknownCommand:
      return CLIStreamsUsage.streams

    case let .missingArguments(usage):
      return usage

    case let .missingValue(option, usage):
      return "Missing value for \(option). \(usage)"

    case let .missingRequiredOption(option, usage):
      return "Missing required option \(option). \(usage)"

    case let .invalidLimit(value, usage):
      return "Invalid --limit value: \(value). \(usage)"

    case let .invalidEventCount(_, usageCommand):
      return "Usage: \(usageCommand) --events 1"

    case let .unknownOption(domain, option, usage):
      return "Unknown \(domain) option: \(option). \(usage)"
    }
  }
}

extension CLIBenchmarkArgumentError: CustomStringConvertible {
  public var description: String {
    switch self {
    case let .emptyAppID(usage):
      return "Missing non-empty value for --app-id. \(usage)"
    case let .help(usage):
      return usage
    case let .invalidIterations(value, usage):
      return "Invalid --iterations value: \(value). \(usage)"
    case let .missingValue(option, usage):
      return "Missing value for \(option). \(usage)"
    case let .unknownOption(option, usage):
      return "Unknown benchmark option: \(option). \(usage)"
    }
  }
}

extension CLISharesArgumentError: CustomStringConvertible {
  public var description: String {
    switch self {
    case .missingCommand:
      return CLISharesUsage.shares

    case .unknownCommand:
      return CLISharesUsage.shares

    case let .missingArguments(usage):
      return usage

    case let .invalidRole(value, usage):
      return "Invalid share role: \(value). \(usage)"

    case let .unexpectedArgument(argument, usage):
      return "Unexpected argument: \(argument). \(usage)"
    }
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
